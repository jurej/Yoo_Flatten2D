# Encoding: UTF-8
#
# SketchUp Extension Loader: Flatten to Z Plane
# Author: Jure Judez
# Version: 1.0.0
# Date: November 2025

require 'sketchup.rb'
require 'extensions.rb'

module YooExtensions
  module FlattenToZPlane
    
    # Extension Information
    EXTENSION_NAME = "Flatten to Z Plane"
    EXTENSION_VERSION = "1.1.0"
    
    # Create the extension
    extension = SketchupExtension.new(EXTENSION_NAME, 'yoo_flatten2d/main.rb')
    
    # Set extension metadata
    extension.description = "Flatten selected groups and component instances to a specified Z-plane coordinate."
    extension.version     = EXTENSION_VERSION
    extension.creator     = "Jure Judez"
    extension.copyright   = "2025, Jure Judez"
    
    # Register the extension with SketchUp
    Sketchup.register_extension(extension, true)
    
  end
end
