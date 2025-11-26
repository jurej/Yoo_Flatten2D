# Yoo_Flatten2D

A SketchUp extension that flattens selected groups and component instances to a specified Z-plane coordinate.

## Features

- Flatten selected geometry to any Z-coordinate
- Works with Groups, Component Instances, and loose geometry (edges and faces)
- **Recursive flattening**: Handles nested groups and components automatically
- **Flatten Guides**: Option to flatten Construction Lines and Points (skips vertical lines)
- **Smart Handling**:
  - Automatically makes groups and components unique to ensure correct positioning
  - Explodes curves (arcs/circles) to prevent distortion
- Supports SketchUp's unit system (enter values like "10ft", "3m", etc.)
- Locale-aware input (supports both "0.0" and "0,0")
- Single undo operation for easy reversal
- Transforms vertices while preserving X and Y coordinates

## Installation

1. Download the `.rbz` file from the releases page
2. In SketchUp, go to **Window > Extension Manager**
3. Click **Install Extension** and select the downloaded `.rbz` file
4. Restart SketchUp

## Usage

1. Select geometry to flatten:
   - Groups
   - Component Instances
   - Edges and faces (loose geometry)
   - Or any combination of the above
2. Go to **Extensions > Yoo Tools > Flatten Selection to Z Plane**
3. Enter the target Z-coordinate (e.g., "0", "10ft", "3m")
4. Click OK

The selected geometry will be flattened to the specified Z-plane while maintaining their X and Y positions.

## Building from Source

To create an `.rbz` file for distribution:

1. Zip the following files:
   - `yoo_flatten2d.rb` (loader)
   - `yoo_flatten2d/` (directory with main.rb)
2. Rename the `.zip` file to `.rbz`

## Version History

### 1.1.0 (November 2025)
- **New Feature**: Recursive flattening for nested groups and components
- **New Feature**: Option to flatten guides (Construction Lines and Points)
- **Improvement**: Locale-aware input handling (supports comma and period decimals)
- **Fix**: Automatically makes groups/components unique to ensure correct positioning
- **Fix**: Explodes arcs and circles to prevent distortion
- **Fix**: Skips vertical construction lines to prevent errors

### 1.0.0 (November 2025)
- Initial release
- Basic flatten to Z-plane functionality

## Author

Jure Judez

## License

MIT License - see [LICENSE](LICENSE) file for details.

This software is provided as-is, without warranty of any kind.
