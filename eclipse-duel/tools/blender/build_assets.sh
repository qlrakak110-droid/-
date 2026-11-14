#!/usr/bin/env bash
# Regenerate Blender hero assets from code.
#   tools/blender/build_assets.sh <hero|all> [--preview]
# 1. exports the game rigs (node tools/blender/export_rig.mjs -> tools/blender/rigs/*.json)
# 2. runs tools/blender/heroes/<hero>.py in headless Blender (-> assets/chars/<hero>/ + shots/blender/<hero>/)
# Every asset is reproducible: the manifest (assets/chars/<hero>/<hero>.json) carries the hash of the scripts that made it.
# ED_THREADS (default 2) caps Cycles threads (the machine is shared).
set -euo pipefail
cd "$(dirname "$0")/../.."
PY=${BLENDER_PY:-/opt/blender-env/venv/bin/python}
target=${1:-all}; shift || true
preview=--no-preview
[[ "${1:-}" == "--preview" ]] && preview=""
node tools/blender/export_rig.mjs
if [[ "$target" == "all" ]]; then heroes=$(ls tools/blender/heroes/*.py | xargs -n1 basename | sed 's/\.py$//'); else heroes=$target; fi
for h in $heroes; do
  echo "== $h"
  "$PY" "tools/blender/heroes/$h.py" $preview
done
# rigs of designs that embed assets change with them (cloth panels defined in Blender): export again
node tools/blender/export_rig.mjs
