"""Roof tiles for the runtime instancer (architecture workstream):
  tile_hi / tile_lo  glazed pantile (0.30 x 0.40 m, 16 mm thick): wide shallow pan + high roll, visible lip thickness.
                     local frame: x across the tile, y = roof normal, z up-slope; lip at z=0, head at z=0.40.
  ridge_hi / ridge_lo half-round ridge cap (0.42 m long, r 0.14) with a thick lower edge; local z along the ridge.
COLOR_0 = AO (pan darker than the roll crest, lip underside dark).  UV: u across, v from lip (0) to head (1).
blender -b -P tools/blender/architecture_tiles.py -> assets/models/architecture/tiles.glb
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector
import architecture_kit as K

OUT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'assets', 'models', 'architecture'))
W, L, T = 0.30, 0.40, 0.016


def prof(t):
    """pantile cross-section height at t in 0..1 across the tile: pan (shallow trough) then roll"""
    if t < 0.6: return -0.022 * math.sin(math.pi * t / 0.6)
    return 0.062 * math.sin(math.pi * (t - 0.6) / 0.4) ** 0.85


def tile(name, segs):
    k = K.Kit(1); B = k.bin(name)
    ts = [i / segs for i in range(segs + 1)]
    # roll needs more resolution than the pan
    ts = sorted(set([round(x, 4) for x in ts] + [0.6 + 0.4 * i / (segs // 2) for i in range(segs // 2 + 1)]))
    hmax = 0.062
    top0 = []; top1 = []; bot0 = []
    for t in ts:
        x = (t - 0.5) * W; y = prof(t)
        ao = 0.72 + 0.28 * (y + 0.022) / (hmax + 0.022)
        top0.append(B.vert((x, y + T, 0.0), 0.5, col=(ao, ao, ao)))
        top1.append(B.vert((x, y + T * 0.6, L), 0.5, col=(ao * 0.9, ao * 0.9, ao * 0.9)))
        bot0.append(B.vert((x, y - 0.002, 0.012), 0.5, col=(0.45, 0.45, 0.45)))
    for i in range(len(ts) - 1):
        B.face([top0[i], top0[i + 1], top1[i + 1], top1[i]], [(ts[i], 0), (ts[i + 1], 0), (ts[i + 1], 1), (ts[i], 1)], outward=(0, 1, 0))
        B.face([bot0[i], bot0[i + 1], top0[i + 1], top0[i]], [(ts[i], -0.04), (ts[i + 1], -0.04), (ts[i + 1], 0), (ts[i], 0)], outward=(0, 0, -1))
    return k.build('tiles')[0]


def ridge(name, segs):
    k = K.Kit(2); B = k.bin(name)
    R, Lr, Tr = 0.14, 0.42, 0.022
    a = [math.pi * i / segs for i in range(segs + 1)]
    top0 = []; top1 = []; bot0 = []
    for ang in a:
        x = math.cos(ang) * R; y = math.sin(ang) * R * 0.8
        ao = 0.8 + 0.2 * math.sin(ang)
        top0.append(B.vert((x, y, 0.0), 0.5, col=(ao, ao, ao)))
        top1.append(B.vert((x * 0.94, y * 0.94, Lr), 0.5, col=(ao * 0.9, ao * 0.9, ao * 0.9)))
        bot0.append(B.vert((x * (1 - Tr / R), y * (1 - Tr / R), 0.01), 0.5, col=(0.5, 0.5, 0.5)))
    for i in range(segs):
        u0, u1 = i / segs, (i + 1) / segs
        B.face([top0[i], top0[i + 1], top1[i + 1], top1[i]], [(u0, 0), (u1, 0), (u1, 1), (u0, 1)], outward=(math.cos((a[i] + a[i + 1]) / 2), math.sin((a[i] + a[i + 1]) / 2), 0))
        B.face([bot0[i], bot0[i + 1], top0[i + 1], top0[i]], [(u0, -0.05), (u1, -0.05), (u1, 0), (u0, 0)], outward=(0, 0, -1))
    # thick lower edges along the length
    for i in (0, segs):
        e0 = B.vert((B.V[top0[i]].x, -0.01, 0.0), 0.5, col=(0.55, 0.55, 0.55))
        e1 = B.vert((B.V[top1[i]].x, -0.01, Lr), 0.5, col=(0.55, 0.55, 0.55))
        B.face([top0[i], top1[i], e1, e0], [(0, 0), (0, 1), (0.05, 1), (0.05, 0)], outward=(1 if i == 0 else -1, 0, 0))
    return k.build('tiles')[0]


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    objs = [tile('tile_hi', 12), tile('tile_lo', 6), ridge('ridge_hi', 9), ridge('ridge_lo', 5)]
    K.bake_colors(objs, rays=4, dist=0.01, skip_ao=tuple(o['bin'] for o in objs))
    for o in objs:
        name = o['bin']; o.name = name; o.data.name = name
    for o in objs:
        K.material(o, 'arch_tile'); print(o.name, K.tris([o]))
    p = K.export(os.path.join(OUT, 'tiles.glb'), objs)
    print('wrote', p, os.path.getsize(p))


if __name__ == '__main__':
    main()
