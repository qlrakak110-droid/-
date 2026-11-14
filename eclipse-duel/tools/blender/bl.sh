#!/bin/bash
# Run a Blender (bpy) script with a memory cap so a runaway build is killed instead of taking the whole VM down.
#   tools/blender/bl.sh tools/blender/heroes/kael.py --pose idle
# BL_MEM_KB overrides the cap (virtual memory, kB; default 6.5 GB).
ulimit -v "${BL_MEM_KB:-6500000}" 2>/dev/null
exec /opt/blender-env/venv/bin/python "$@"
