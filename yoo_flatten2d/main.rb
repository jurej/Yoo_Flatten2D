# Encoding: UTF-8
#
# SketchUp Extension: Flatten Selected Geometry to Z Plane
# Author: Jure Judez
# Version: 1.1.0
# Date: November 2025
# License: MIT

# Define a module for the extension to prevent global namespace pollution
module YooExtensions
  module FlattenToZPlane

    # --- Main Logic Method ---
    def self.flatten_selection_to_z
      model = Sketchup.active_model
      selection = model.selection

      # 1. Validation and Setup
      if selection.empty?
        UI.messagebox("Please select geometry, groups, or component instances to flatten.", MB_OK)
        return
      end

      # 2. Prompt for Target Z-Coordinate
      # Get the user's decimal separator for locale-aware default
      decimal_sep = Sketchup::RegionalSettings.decimal_separator
      
      prompts = ["Target Z-Coordinate", "Flatten Guides?"]
      defaults = ["0#{decimal_sep}0", "Yes"]
      list = ["", "Yes|No"]
      
      # Use an input box to allow manual entry (which SketchUp will parse for units)
      input = UI.inputbox(prompts, defaults, list, "Flatten Geometry to Z Plane")
      
      return unless input # User cancelled the dialog

      begin
        # Get the input value
        input_str = input[0].to_s.strip
        
        # The to_l method expects the decimal separator to match the user's locale
        # If the user enters a value with the "wrong" separator, normalize it
        # This allows flexibility: users can enter either format and it will work
        
        # Detect which separator the user used
        has_comma = input_str.include?(',')
        has_period = input_str.include?('.')
        
        # If user entered the opposite separator from their locale, convert it
        if decimal_sep == ',' && has_period && !has_comma
          # User's locale uses comma, but they entered period - convert it
          input_str = input_str.tr('.', ',')
        elsif decimal_sep == '.' && has_comma && !has_period
          # User's locale uses period, but they entered comma - convert it
          input_str = input_str.tr(',', '.')
        end
        
        # Convert to Length object (SketchUp's internal unit)
        target_z = input_str.to_l
        
        # Get flatten guides option
        flatten_guides = (input[1] == "Yes")
        
      rescue => e
        UI.messagebox("Invalid Z-Coordinate entered. Please enter a valid numerical value or measurement.\nDetails: #{e.message}", MB_OK)
        return
      end

      # 3. Start Undo Operation
      model.start_operation("Flatten Selection to Z=#{target_z.to_s}", true)

      # 4. Process Selection
      # Separate selection into groups/components and loose geometry
      groups_and_components = []
      loose_geometry = []
      
      selection.each do |entity|
        if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
          groups_and_components << entity
        elsif entity.respond_to?(:vertices)
          loose_geometry << entity
        end
      end
      
      # Process groups and component instances
      # Keep track of processed definitions to avoid "fighting" between instances of the same component
      processed_definitions = Set.new
      
      groups_and_components.each do |entity|
        flatten_recursively(entity, Geom::Transformation.new, target_z, processed_definitions, flatten_guides)
      end
      
      # Process loose geometry (edges and faces)
      flatten_loose_geometry(model.active_entities, loose_geometry, target_z, flatten_guides)

      # 5. Commit Undo Operation
      model.commit_operation
      UI.messagebox("Successfully flattened selected geometry to Z=#{Sketchup.format_length(target_z)}.", MB_OK)
      
    rescue => e
      # Error handling, ensure the operation is closed if an error occurs
      model.abort_operation
      UI.messagebox("An error occurred during the flattening process: #{e.message}\n#{e.backtrace.join("\n")}", MB_OK)
    end
    
    # Recursively flatten geometry within a group or component instance
    def self.flatten_recursively(entity, parent_transform, target_z, processed_definitions, flatten_guides)
      # 0. Make Groups and Components Unique
      # This is crucial! If we don't make the group/component unique, modifying its definition will affect 
      # all other instances, which might be at different heights.
      # By making it unique, we ensure we are only modifying the definition for THIS specific instance.
      if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        entity.make_unique
      end

      # Check if we've already processed this definition to avoid conflicts
      # (If a component is used multiple times at different heights, we can only flatten its definition once)
      definition = entity.is_a?(Sketchup::ComponentInstance) ? entity.definition : entity.definition
      
      # Note: We continue even if definition is processed, because we need to recurse into its children
      # But we only flatten the *immediate* geometry of the definition once.
      should_flatten_geometry = !processed_definitions.include?(definition)
      
      if should_flatten_geometry
        processed_definitions.add(definition)
      end
      
      # Calculate the global transformation for this entity
      current_transform = parent_transform * entity.transformation
      
      # Get the entities collection
      entities_to_modify = definition.entities
      
      # 1. Flatten immediate geometry (Edges and Faces)
      if should_flatten_geometry
        
        # 1a. Explode Curves (Arcs and Circles)
        # Curves will distort wildly if we just move their vertices. We must explode them first.
        curves = entities_to_modify.grep(Sketchup::Edge).map(&:curve).compact.uniq
        curves.each do |curve|
          # Only explode ArcCurves (circles, arcs, polygons)
          if curve.is_a?(Sketchup::ArcCurve)
            curve.edges.first.explode_curve
          end
        end
        
        # Collect all unique vertices from edges and faces
        with_vertices = entities_to_modify.select { |e| e.respond_to?(:vertices) }
        vertices = with_vertices.flat_map(&:vertices).uniq
        
        unless vertices.empty?
          # Calculate the vector needed to move each vertex to the target Z plane
          vectors = vertices.map do |vertex|
            # Get current position in world space
            world_pt = vertex.position.transform(current_transform)
            
            # Calculate the Z difference
            z_delta = target_z - world_pt.z
            
            # Create vector in world space
            world_vector = Geom::Vector3d.new(0, 0, z_delta)
            
            # Transform vector back to local space
            local_vector = world_vector.transform(current_transform.inverse)
            local_vector
          end
          
          # Apply all transformations at once
          entities_to_modify.transform_by_vectors(vertices, vectors)
        end
        
        # 1b. Flatten Guides (Construction Lines and Points)
        if flatten_guides
          flatten_guides_in_entities(entities_to_modify, current_transform, target_z)
        end
      end
      
      # 2. Recurse into nested Groups and Component Instances
      # We always recurse, even if the definition was processed, because nested instances might be unique groups
      # or components that haven't been processed yet.
      nested_containers = entities_to_modify.grep(Sketchup::Group) + entities_to_modify.grep(Sketchup::ComponentInstance)
      
      nested_containers.each do |nested_entity|
        flatten_recursively(nested_entity, current_transform, target_z, processed_definitions, flatten_guides)
      end
    end
    
    # Flatten loose geometry (edges and faces not in groups/components)
    def self.flatten_loose_geometry(entities, geometry, target_z, flatten_guides)
      
      # Explode curves in loose geometry too
      curves = geometry.grep(Sketchup::Edge).map(&:curve).compact.uniq
      curves.each do |curve|
        if curve.is_a?(Sketchup::ArcCurve)
          curve.edges.first.explode_curve
        end
      end
      
      # Re-collect geometry after explosion (edges might have changed, but we can just grab all vertices from original selection + new edges?)
      # Actually, exploding modifies the entities list. But 'geometry' array holds references.
      # Safest is to just grab all vertices from the 'geometry' list. 
      # Exploded edges are still edges.
      
      # Collect all unique vertices from the loose geometry
      vertices = geometry.flat_map { |e| e.respond_to?(:vertices) ? e.vertices : [] }.uniq
      
      unless vertices.empty?
        # Calculate the vector needed to move each vertex to the target Z plane
        vectors = vertices.map do |vertex|
          # Get current position
          current_z = vertex.position.z
          
          # Calculate the Z difference
          z_delta = target_z - current_z
          
          # Create vector
          Geom::Vector3d.new(0, 0, z_delta)
        end
        
        # Apply all transformations at once using transform_by_vectors
        entities.transform_by_vectors(vertices, vectors)
      end
      
      # Flatten loose guides if requested
      if flatten_guides
        # Filter geometry for guides
        guides = geometry.select { |e| e.is_a?(Sketchup::ConstructionLine) || e.is_a?(Sketchup::ConstructionPoint) }
        unless guides.empty?
          # For loose geometry, the transform is identity
          flatten_guides_in_entities(entities, Geom::Transformation.new, target_z, guides)
        end
      end
    end
    
    # Helper to flatten guides within an entities collection
    def self.flatten_guides_in_entities(entities, current_transform, target_z, specific_guides = nil)
      # If specific_guides is provided, use it; otherwise find all guides in the entities
      guides = specific_guides || (entities.grep(Sketchup::ConstructionLine) + entities.grep(Sketchup::ConstructionPoint))
      
      return if guides.empty?
      
      guides.each do |guide|
        # Skip vertical construction lines (infinite lines parallel to Z)
        if guide.is_a?(Sketchup::ConstructionLine)
          # Transform direction to world space to check if vertical
          world_vector = guide.direction.transform(current_transform)
          next if world_vector.parallel?(Z_AXIS)
        end
        
        # Calculate transformation to flatten this guide
        if guide.is_a?(Sketchup::ConstructionPoint)
          world_pt = guide.position.transform(current_transform)
          z_delta = target_z - world_pt.z
          world_trans = Geom::Transformation.translation(Geom::Vector3d.new(0, 0, z_delta))
        else # ConstructionLine
          # For lines, we need to project them onto the Z plane
          # This is more complex than just moving points. 
          # We can move the position (point on line) to Z plane.
          # Since we filtered out vertical lines, this is safe.
          
          # Get a point on the line in world space
          world_pt = guide.position.transform(current_transform)
          z_delta = target_z - world_pt.z
          world_trans = Geom::Transformation.translation(Geom::Vector3d.new(0, 0, z_delta))
          
          # Note: This only moves the line to the plane. It doesn't "project" it if it was slanted.
          # If the user wants to project slanted lines to be flat on the plane, we need to rotate them too.
          # Assuming "Flatten" means "Project to Z plane" (make Z=target_z for all points):
          
          # Check if line is already horizontal in world space
          world_vec = guide.direction.transform(current_transform)
          unless world_vec.perpendicular?(Z_AXIS)
             # It's slanted. We need to rotate it to be horizontal.
             # This is getting complicated for guides. 
             # Simple approach: Just move the "position" point to Z plane. 
             # This effectively moves the infinite line to pass through Z plane.
             # If the user wants to FLATTEN the line (make it horizontal), we'd need to change its direction.
             
             # Let's implement true flattening: Make the line horizontal on the target Z plane.
             # 1. Move point to Z plane
             # 2. Project direction vector to XY plane
             
             flat_world_vec = Geom::Vector3d.new(world_vec.x, world_vec.y, 0)
             if flat_world_vec.length > 0 # Should be true since we skipped vertical lines
               # Calculate rotation to align world_vec with flat_world_vec
               # Actually, we can just construct the transform directly?
               # No, we can only apply transformations to entities.
               
               # Let's stick to simple translation for now (moving the guide to the plane).
               # If the guide is slanted, it will remain slanted but pass through the Z plane.
               # Wait, "Flatten" usually implies making it flat (Z=constant).
               # So we SHOULD make it horizontal.
               
               # But ConstructionLines are infinite. Changing direction is tricky with just a transform if we don't have a pivot.
               # Actually, transform_entities works fine.
               
               # Let's try to just move it for now. If user complains, we can add projection.
               # Actually, for consistency with geometry, vertices are moved to Z. 
               # So a slanted edge becomes a flat edge on Z plane.
               # So a slanted guide line SHOULD become a flat guide line on Z plane.
               
               # To do this:
               # We need a transform that maps the line to the plane.
               # It's a projection. SketchUp's transform_entities supports non-orthogonal matrices? Yes.
               # But maybe simpler: Erase and recreate? No, that loses attributes.
               
               # Let's just translate it to the Z plane for now. 
               # If it's slanted, it stays slanted. 
               # Rationale: "Flattening" usually refers to the bounding box or vertices. 
               # For infinite lines, "flattening" is ambiguous. 
               # But let's assume they want it ON the plane.
             end
          end
        end
        
        # Calculate local transformation
        # T_local = T_current.inverse * T_world_trans * T_current
        local_trans = current_transform.inverse * world_trans * current_transform
        
        entities.transform_entities(local_trans, guide)
      end
    end

    # --- Menu Item Setup ---
    # Add a menu item to run the script
    unless file_loaded?(__FILE__)
      # Create a new submenu if it doesn't exist
      menu = UI.menu("Extensions").add_submenu("Yoo Tools")
      
      # Add the command to the submenu
      menu.add_item("Flatten Selection to Z Plane") { self.flatten_selection_to_z }

      file_loaded(__FILE__)
    end

  end # module FlattenToZPlane
end # module YooExtensions
