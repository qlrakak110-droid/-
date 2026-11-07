#!/bin/bash
# Rebuild every architecture-workstream asset (textures, cottages, tiles, props) and shrink the GLBs.
#   bash tools/blender/architecture_build.sh            (from the spirit-island folder)
set -e
cd "$(dirname "$0")/../.."
python3 tools/tex/architecture_textures.py
blender -b -P tools/blender/architecture_houses.py
blender -b -P tools/blender/architecture_tiles.py
blender -b -P tools/blender/architecture_props.py
python3 tools/blender/architecture_glb.py assets/models/architecture/houses.glb assets/models/architecture/props.glb assets/models/architecture/tiles.glb
du -sh assets/tex/architecture assets/models/architecture
