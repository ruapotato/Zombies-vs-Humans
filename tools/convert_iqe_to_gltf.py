#!/usr/bin/env python3
"""
Convert IQE models to glTF using Blender.
Run with: blender --background --python convert_iqe_to_gltf.py -- input.iqe output.glb
"""

import bpy
import sys
import os

def clear_scene():
    """Clear all objects from scene"""
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()

def import_iqe(filepath):
    """Import IQE file - requires iqe addon or manual parsing"""
    # Check if IQE addon is available
    try:
        bpy.ops.import_scene.iqe(filepath=filepath)
        return True
    except AttributeError:
        print(f"IQE addon not available, trying alternative import...")
        return False

def export_gltf(filepath):
    """Export scene to glTF"""
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format='GLB',
        export_texcoords=True,
        export_normals=True,
        export_materials='EXPORT',
        export_animations=True
    )

def main():
    # Get arguments after --
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        print("Usage: blender --background --python convert_iqe_to_gltf.py -- input.iqe output.glb")
        return

    if len(argv) < 2:
        print("Need input and output paths")
        return

    input_path = argv[0]
    output_path = argv[1]

    print(f"Converting {input_path} to {output_path}")

    clear_scene()

    if import_iqe(input_path):
        export_gltf(output_path)
        print(f"Exported to {output_path}")
    else:
        print("Failed to import IQE")

if __name__ == "__main__":
    main()
