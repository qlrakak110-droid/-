"""Village props + fountain (architecture workstream). Origin of every prop = centre of its footprint on the ground,
front = +z. Materials by object suffix (same as the houses): wood timber stone ashlar iron glow flora clay soil.
  barrel, barrel_b (open, with water), crate, crate_s, bench, well, lamp (street lantern post), fence (2.4 m run),
  kerb_0..2 (plaza kerb stones), planter (round stone flower bed), logs (stacked firewood), pebbles_0..1 (ground scatter),
  fountain (octagonal basin with mouldings, pedestal, upper bowl, finial; water surfaces stay procedural at runtime)
blender -b -P tools/blender/architecture_props.py -> assets/models/architecture/props.glb
"""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector
import architecture_kit as K
from architecture_houses import plant_bed, sstep

OUT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'assets', 'models', 'architecture'))
UP = Vector((0, 1, 0)); X = Vector((1, 0, 0)); Z = Vector((0, 0, 1))


def barrel(k, r, open_top=False):
    H, R0, R1 = 0.92, 0.3, 0.355
    n = 18
    prof = []
    for i in range(9):
        t = i / 8; y = t * H
        prof.append((R0 + (R1 - R0) * math.sin(math.pi * t), y))
    # staves: lathe per stave so each one gets its own tone and a tiny radial offset
    for s in range(n):
        a0 = s / n * 2 * math.pi; a1 = (s + 0.94) / n * 2 * math.pi
        dr = r.uniform(-0.004, 0.006)
        rows = []
        for (rad, y) in prof:
            rows.append([Vector((math.cos(a) * (rad + dr), y, math.sin(a) * (rad + dr))) for a in (a0, (a0 + a1) / 2, a1)])
        B = k.bin('wood'); var = r.random(); uo = r.random()
        ids = [[B.vert(p, var) for p in row] for row in rows]
        for i in range(len(rows) - 1):
            for j in range(2):
                q = [ids[i][j], ids[i][j + 1], ids[i + 1][j + 1], ids[i + 1][j]]
                c = (rows[i][j] + rows[i + 1][j + 1]) / 2
                B.face(q, [(uo + j * 0.05, prof[i][1] / 1.0), (uo + (j + 1) * 0.05, prof[i][1]), (uo + (j + 1) * 0.05, prof[i + 1][1]), (uo + j * 0.05, prof[i + 1][1])], outward=Vector((c.x, 0, c.z)))
    for t in (0.1, 0.28, 0.72, 0.9):
        y = t * H; rad = R0 + (R1 - R0) * math.sin(math.pi * t) + 0.008
        k.lathe('iron', (0, y, 0), [(rad, -0.025), (rad + 0.006, -0.02), (rad + 0.006, 0.02), (rad, 0.025)], seg=24, uv=(0.5, 0.5))
    if open_top:
        k.lathe('glass', (0, H - 0.08, 0), [(R0 - 0.01, 0), (0.0, 0.0)], seg=18)
        k.lathe('wood', (0, 0, 0), [(R0 - 0.02, H - 0.005), (R0 - 0.035, H - 0.005), (R0 - 0.035, H - 0.08)], seg=18)
    else:
        k.lathe('wood', (0, H - 0.04, 0), [(R0 - 0.012, 0), (0.0, 0.0)], seg=18, uv=(0.5, 0.5))
        k.lathe('wood', (0, 0, 0), [(R0 - 0.01, H + 0.004), (R0 - 0.03, H + 0.004), (R0 - 0.03, H - 0.04)], seg=18)


def crate(k, r, S=0.62):
    h = S / 2
    for ax in range(3):
        for a in (-1, 1):
            for b in (-1, 1):
                p = [0, 0, 0]; q = [0, 0, 0]
                o = [i for i in range(3) if i != ax]
                p[o[0]] = a * (h - 0.035); p[o[1]] = b * (h - 0.035); q[:] = p
                p[ax] = -h; q[ax] = h
                p[1] += h; q[1] += h
                nrm = [0, 0, 0]; nrm[o[0]] = a
                k.prism('timber', Vector(p), Vector(q), 0.07, 0.07, Vector(nrm), ch=0.008)
    # side planks with gaps
    for (axis, sgn) in ((0, 1), (0, -1), (2, 1), (2, -1), (1, 1)):
        for i in range(3):
            w = (S - 0.14) / 3
            c = -h + 0.07 + w * (i + 0.5)
            p = [0, 0, 0]; size = [0, 0, 0]
            p[axis] = sgn * (h - 0.02)
            other = [j for j in range(3) if j != axis]
            long_ax = other[0] if axis != 0 else 2
            short_ax = [j for j in other if j != long_ax][0]
            p[short_ax] = c; size[axis] = 0.025; size[long_ax] = S - 0.14; size[short_ax] = w - 0.014
            p[1] += h
            k.box('wood', Vector(p), size, ch=0.004)


def bench(k, r):
    L = 1.8
    for z in (-0.12, 0.12):
        k.prism('wood', Vector((-L / 2, 0.47, z)), Vector((L / 2, 0.47, z)), 0.06, 0.21, UP, ch=0.012)
    for y, rot in ((0.78, 0.0), (0.94, 0.0)):
        k.prism('wood', Vector((-L / 2, y, -0.3 - (y - 0.7) * 0.2)), Vector((L / 2, y, -0.3 - (y - 0.7) * 0.2)), 0.12, 0.035, Vector((0, 0.18, 1)), ch=0.008)
    for x in (-0.72, 0.72):
        # legs: chunky timber trestles
        for z in (-0.18, 0.18):
            k.prism('timber', Vector((x, -0.06, z)), Vector((x, 0.44, z * 0.9)), 0.09, 0.09, Z, ch=0.012)
        k.prism('timber', Vector((x, 0.42, -0.24)), Vector((x, 0.42, 0.24)), 0.07, 0.09, UP, ch=0.01)
        k.prism('timber', Vector((x, 0.12, -0.18)), Vector((x, 0.12, 0.18)), 0.06, 0.06, UP, ch=0.008)
        k.prism('timber', Vector((x, 0.42, -0.26)), Vector((x, 1.02, -0.36)), 0.08, 0.07, X, ch=0.01)


def well(k, r):
    # round fieldstone drum with a dressed coping, two posts, a windlass, a little tiled hood, rope and bucket
    k.lathe('stone', (0, 0, 0), [(0.95, -0.25), (0.95, 0.72), (0.72, 0.72), (0.72, 0.1)], seg=20, uv=(2.0, 2.0))
    k.lathe('ashlar', (0, 0, 0), [(1.02, 0.7), (1.04, 0.78), (1.0, 0.84), (0.7, 0.84), (0.68, 0.78)], seg=20, uv=(2.5, 2.5))
    k.lathe('glass', (0, 0.25, 0), [(0.72, 0.0), (0.0, 0.0)], seg=16)
    for i in range(10):
        a = r.uniform(0, 6.28)
        k.stone('stone', Vector((math.cos(a) * 1.0, -0.02, math.sin(a) * 1.0)), (r.uniform(0.22, 0.36), 0.18, r.uniform(0.2, 0.3)), rot_y=a, seed=500 + i, flat_bottom=0.4)
    for s in (-1, 1):
        k.prism('timber', Vector((s * 0.86, 0.3, 0)), Vector((s * 0.86, 2.15, 0)), 0.14, 0.14, X, ch=0.015)
        k.prism('timber', Vector((s * 0.86, 0.95, 0.0)), Vector((s * 0.86, 1.25, 0.0)), 0.18, 0.22, X, ch=0.02)
    k.prism('timber', Vector((-1.0, 2.1, 0)), Vector((1.0, 2.1, 0)), 0.14, 0.14, UP, ch=0.015)
    k.lathe('wood', (0, 1.42, 0), [(0.0, -0.0)], seg=8) if False else None
    k.prism('wood', Vector((-0.82, 1.45, 0)), Vector((0.82, 1.45, 0)), 0.13, 0.13, UP, ch=0.035)
    k.tube('iron', [Vector((0.82, 1.45, 0)), Vector((1.0, 1.45, 0)), Vector((1.0, 1.25, 0.0)), Vector((1.12, 1.25, 0.0))], 0.018, seg=6)
    k.tube('wood', [Vector((0.05, 1.42, 0.06)), Vector((0.05, 0.95, 0.06))], 0.012, seg=5)
    k.lathe('wood', (0.05, 0.7, 0.06), [(0.12, 0.0), (0.14, 0.24), (0.0, 0.24)], seg=12)
    k.lathe('iron', (0.05, 0.7, 0.06), [(0.125, 0.04), (0.13, 0.06)], seg=12)
    k.tube('iron', [Vector((0.05 - 0.13, 0.94, 0.06)), Vector((0.05, 1.0, 0.06)), Vector((0.05 + 0.13, 0.94, 0.06))], 0.008, seg=4)
    # hood roof: two boarded slopes; tiles come from the runtime instancer (meta in the node extras)
    roof = []
    for s in (-1, 1):
        top = Vector((0, 2.62, 0)); eave = Vector((s * 1.22, 2.02, 0))
        n = Vector((s * 0.6, 1.22, 0)).normalized()
        mid = (top + eave) / 2 - n * 0.035
        k.prism('wood', mid - Vector((0, 0, 0.75)), mid + Vector((0, 0, 0.75)), (top - eave).length, 0.05, n, ch=0.0)
        for z in (-0.74, 0.74):
            k.prism('wood', top + Vector((0, 0.02, z)) - n * 0.05, eave + Vector((0, 0.02, z)) - n * 0.05, 0.2, 0.04, Z, ch=0.004)
        roof += list(eave + Vector((0, 0, -0.76))) + [0, 0, 1] + list((top - eave).normalized()) + [1.52, (top - eave).length]
    k.prism('timber', Vector((0, 2.58, -0.8)), Vector((0, 2.58, 0.8)), 0.12, 0.12, UP, ch=0.015)
    return roof, [0, 2.66, -0.8, 0, 0, 1, 1.6]


def lamp(k, r):
    k.box('stone', Vector((0, 0.1, 0)), (0.5, 0.5, 0.5), ch=0.04, wuv=2.0)
    k.box('stone', Vector((0, 0.42, 0)), (0.4, 0.16, 0.4), ch=0.03, wuv=2.0)
    k.lathe('iron', (0, 0.5, 0), [(0.13, 0), (0.12, 0.08), (0.075, 0.14), (0.06, 0.3), (0.05, 2.25), (0.07, 2.3), (0.07, 2.36), (0.0, 2.4)], seg=10, uv=(0.4, 1.0))
    # scrolled bracket arm
    arm = [Vector((0, 2.55, 0.0)), Vector((0, 2.66, 0.18)), Vector((0, 2.66, 0.44))]
    k.tube('iron', [Vector((0, 2.0, 0.02)), Vector((0, 2.3, 0.2)), Vector((0, 2.58, 0.36))], 0.018, seg=6)
    pts = [Vector((0, 2.6 + 0.1 * math.sin(t), 0.06 + 0.12 * (1 - math.cos(t)))) for t in [i / 8 * math.pi for i in range(9)]]
    k.tube('iron', [Vector((0, 2.62, 0.0)), Vector((0, 2.68, 0.25)), Vector((0, 2.66, 0.44))], 0.022, seg=6)
    c = Vector((0, 2.3, 0.44))
    k.tube('iron', [Vector((0, 2.64, 0.44)), Vector((0, 2.55, 0.44))], 0.012, seg=5)
    k.lathe('iron', c + UP * 0.2, [(0.2, 0.0), (0.19, 0.03), (0.03, 0.2), (0.0, 0.23)], seg=4, phase=math.pi / 4)
    k.prism('glow', c - UP * 0.18, c + UP * 0.18, 0.2, 0.2, X, ch=0.0)
    for a in (-1, 1):
        for b in (-1, 1):
            q = c + Vector((a * 0.115, 0, b * 0.115))
            k.prism('iron', q - UP * 0.2, q + UP * 0.2, 0.026, 0.026, X)
    k.box('iron', c - UP * 0.21, (0.28, 0.035, 0.28))
    k.lathe('iron', c - UP * 0.24, [(0.0, -0.08), (0.05, -0.02), (0.08, 0.0)], seg=6)


def fence(k, r, L=2.4):
    for x in (-L / 2, L / 2):
        k.prism('timber', Vector((x, -0.3, 0)), Vector((x, 1.0, 0)), 0.11, 0.11, Z, ch=0.02)
        k.lathe('timber', (x, 1.0, 0), [(0.075, 0.0), (0.0, 0.06)], seg=4, phase=math.pi / 4)
    for y in (0.38, 0.78):
        a = Vector((-L / 2 - 0.06, y + r.uniform(-0.02, 0.02), 0.07)); b = Vector((L / 2 + 0.06, y + r.uniform(-0.02, 0.02), 0.07))
        k.prism('wood', a, b, 0.09, 0.06, Z.lerp(UP, 0.2), ch=0.02)
    for i in range(5):
        x = -L / 2 + 0.3 + i * (L - 0.6) / 4
        k.prism('wood', Vector((x, 0.0, 0.12)), Vector((x, 0.92 + r.uniform(-0.04, 0.04), 0.12)), 0.08, 0.025, Z, ch=0.006)
        k.lathe('wood', (x, 0.92, 0.12), [(0.05, 0.0), (0.0, 0.06)], seg=4) if False else None


def kerb(k, r, seed):
    rr = random.Random(seed)
    L = rr.uniform(1.25, 1.6)
    k.box('stone', Vector((0, -0.02, 0)), (0.36, 0.3, L), rot=(rr.uniform(-0.02, 0.02), 0, rr.uniform(-0.03, 0.03)), ch=0.05, wuv=2.0)


def planter(k, r):
    for i in range(9):
        a0 = i / 9 * 2 * math.pi
        c = Vector((math.cos(a0 + 0.35) * 0.92, 0.12, math.sin(a0 + 0.35) * 0.92))
        k.stone('stone', c, (0.62, 0.42, 0.34), rot_y=-(a0 + 0.35) + math.pi / 2, seed=700 + i, rough=0.15, flat_bottom=0.5)
    k.lathe('soil', (0, 0, 0), [(0.92, 0.26), (0.5, 0.3), (0.0, 0.32)], seg=16, uv=(1.0, 1.0))
    import random as _r
    plant_bed(k, _r.Random(77), lambda t, q: Vector((math.cos(t * 6.28 * 3) * (0.12 + 0.62 * (0.5 + 0.5 * q)), 0.3, math.sin(t * 6.28 * 3) * (0.12 + 0.62 * (0.5 + 0.5 * q)))), 26, leaves=(8, 11), scale=2.0)


def logs(k, r):
    for row in range(3):
        for i in range(6 - row):
            rad = r.uniform(0.09, 0.12)
            z = -0.62 + i * 0.25 + row * 0.125 + r.uniform(-0.02, 0.02)
            c = Vector((r.uniform(-0.04, 0.04), 0.11 + row * 0.2, z))
            k.prism('timber', c - X * 0.62, c + X * 0.62, rad * 2, rad * 2, Vector((0, 1, r.uniform(-1, 1))), ch=rad * 0.55, uv=(0.5, 2.0))


def pebbles(k, r, seed):
    rr = random.Random(seed)
    for i in range(7):
        a = rr.uniform(0, 6.28); d = rr.uniform(0, 0.55)
        s = rr.uniform(0.06, 0.16)
        k.stone('stone', Vector((math.cos(a) * d, -0.01, math.sin(a) * d)), (s * 1.3, s * 0.7, s), rot_y=rr.uniform(0, 3), seed=900 + seed * 10 + i, sub=1, rough=0.2, flat_bottom=0.3, tile=0.6)


def fountain(k, r):
    # octagonal basin (lathe with 8 sides): plinth, wall with a moulded rim, inner wall down to the water
    k.lathe('ashlar', (0, 0, 0), [(2.95, -0.3), (2.95, 0.1), (2.86, 0.16), (2.78, 0.2), (2.78, 0.56), (2.86, 0.6), (2.92, 0.68), (2.92, 0.76),
                                 (2.86, 0.8), (2.62, 0.8), (2.6, 0.74), (2.6, 0.3)], seg=8, phase=math.pi / 8, uv=(2.5, 2.5))
    # panel frames on each side of the basin
    for i in range(8):
        a = i / 8 * 2 * math.pi
        nrm = Vector((math.cos(a), 0, math.sin(a))); t = Vector((-math.sin(a), 0, math.cos(a)))
        ap = 2.78 * math.cos(math.pi / 8) + 0.02
        c = nrm * ap
        for s in (-1, 1):
            k.prism('ashlar', c + t * s * 0.82 + UP * 0.22, c + t * s * 0.82 + UP * 0.54, 0.09, 0.05, nrm, ch=0.012, uv=(2.5, 2.5))
        k.prism('ashlar', c + t * -0.86 + UP * 0.25, c + t * 0.86 + UP * 0.25, 0.06, 0.05, nrm, ch=0.012, uv=(2.5, 2.5))
        k.prism('ashlar', c + t * -0.86 + UP * 0.51, c + t * 0.86 + UP * 0.51, 0.06, 0.05, nrm, ch=0.012, uv=(2.5, 2.5))
    # pedestal with mouldings
    k.lathe('ashlar', (0, 0, 0), [(0.62, 0.3), (0.62, 0.78), (0.55, 0.84), (0.46, 0.9), (0.42, 1.0), (0.34, 1.08), (0.3, 1.2), (0.28, 1.55), (0.32, 1.6),
                                 (0.38, 1.66), (0.38, 1.72), (0.3, 1.78)], seg=16, uv=(2.5, 2.5))
    # upper bowl: flared underside with ribs implied by the lathe, thick lip, inner surface down to the water
    k.lathe('ashlar', (0, 0, 0), [(0.3, 1.76), (0.55, 1.8), (0.8, 1.88), (0.98, 1.97), (1.08, 2.05), (1.12, 2.12), (1.1, 2.18), (1.02, 2.18), (0.98, 2.1),
                                 (0.95, 2.02)], seg=24, uv=(2.5, 2.5))
    # finial pedestal for the crystal
    k.lathe('ashlar', (0, 0, 0), [(0.2, 2.0), (0.2, 2.18), (0.14, 2.24), (0.12, 2.36), (0.18, 2.42), (0.2, 2.48), (0.0, 2.5)], seg=12, uv=(2.5, 2.5))
    # wear stones / steps around the basin
    for i in range(14):
        a = i / 14 * 2 * math.pi + r.uniform(-0.1, 0.1)
        k.stone('stone', Vector((math.cos(a) * 3.15, -0.05, math.sin(a) * 3.15)), (r.uniform(0.3, 0.45), 0.16, r.uniform(0.25, 0.35)), rot_y=-a, seed=1200 + i, flat_bottom=0.4, rough=0.15)


def grime_props(p, name):
    y = p.y
    if name in ('stone', 'ashlar'): return 0.7 * sstep(0.5, -0.2, y)
    if name in ('wood', 'timber'): return 0.5 * sstep(0.5, -0.05, y)
    return 0.0


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    r = random.Random(3)
    items = [('barrel', lambda k: barrel(k, r)), ('barrel_b', lambda k: barrel(k, r, True)), ('crate', lambda k: crate(k, r)), ('crate_s', lambda k: crate(k, r, 0.44)),
             ('bench', lambda k: bench(k, r)), ('well', lambda k: well(k, r)), ('lamp', lambda k: lamp(k, r)), ('fence', lambda k: fence(k, r)),
             ('kerb_0', lambda k: kerb(k, r, 1)), ('kerb_1', lambda k: kerb(k, r, 2)), ('kerb_2', lambda k: kerb(k, r, 3)), ('planter', lambda k: planter(k, r)),
             ('logs', lambda k: logs(k, r)), ('pebbles_0', lambda k: pebbles(k, r, 0)), ('pebbles_1', lambda k: pebbles(k, r, 1)), ('fountain', lambda k: fountain(k, r))]
    allobjs = []
    for name, fn in items:
        k = K.Kit(len(allobjs) + 5)
        res = fn(k)
        objs = k.build(name)
        g = K.ground_plane(20, 0.0)
        K.bake_colors(objs, occluders=[g], rays=20, dist=0.8 if name not in ('fountain', 'well') else 1.2, grime_fn=grime_props, skip_ao=('glass', 'glow'))
        bpy.data.objects.remove(g)
        for o in objs: K.material(o, 'arch_' + o['bin'])
        if res:
            meta = bpy.data.objects.new(f'{name}_meta', None); bpy.context.scene.collection.objects.link(meta)
            meta['roof'] = list(res[0]); meta['ridge'] = list(res[1]); objs.append(meta)
        print(name, K.tris([o for o in objs if o.type == 'MESH']))
        allobjs += objs
    p = K.export(os.path.join(OUT, 'props.glb'), allobjs)
    print('wrote', p, os.path.getsize(p))


if __name__ == '__main__':
    main()
