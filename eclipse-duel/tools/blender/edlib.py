# edlib - the Blender side of the 흑일무림 character pipeline (see tools/blender/README.md).
#
#   import sys, os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))   # heroes/*.py
#   import edlib as ed
#   ed.reset_scene(); rig = ed.Rig('vorn'); arm = ed.build_armature(rig); body = ed.body(rig, arm=arm) ...
#
# One namespace over the modules in tools/blender/ed/: core (scene, axes, rig, armature, meshes, attributes, looks,
# parts), model (lofts, sweeps, patterns), body (base body, hands), cloth (garments, draping), skin (weights, chains,
# cloth panels), bake (AO / curvature to vertices, Cycles map baking, decimation, UVs), render (preview sheets),
# export (the EDM1 asset).
import os as _os
import sys as _sys

_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))

from ed.core import *          # noqa: F401,F403,E402
from ed.core import (Rig, G2B, B2G, HERE, ROOT)   # noqa: F401,E402
from ed.model import *         # noqa: F401,F403,E402
from ed.body import (body, hand, keep_regions, cull_hidden, DEFAULT_BUILD)   # noqa: F401,E402
from ed import skin            # noqa: F401,E402
from ed.skin import (auto_skin, transfer_weights, along_chain, by_rows, define_panel, bind_panel, mirror_check, weight_report, attach, smooth_weights,
                     limit_normalize, station_weights, chain_weights)   # noqa: F401,E402
from ed.render import (preview_sheet, render_view, render_still, light_rig, camera, contact_sheet)   # noqa: F401,E402
from ed.export import export_asset   # noqa: F401,E402
try:
    from ed.cloth import *     # noqa: F401,F403,E402
    from ed.bake import *      # noqa: F401,F403,E402
except ImportError as _e:      # modules under construction
    print('[edlib]', _e)
