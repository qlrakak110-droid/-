"""Trees, bushes and ferns for the island: procedural branching skeletons meshed as tapered tubes (bark UVs), leaf
cluster cards (folded quads into the foliage atlas) and fern fronds (cover atlas).

    blender -b -P tools/blender/vegetation_trees.py            -> assets/models/vegetation/trees.glb

Every species/variant is exported as named objects:
    <name>_wood, <name>_leaf            (LOD0, <= ~5k tris together)
    <name>_wood_lod1, <name>_leaf_lod1  (LOD1, ~1/4: fewer sides/rings, no twigs, fewer bigger cards)
Vertex colour COLOR_0 (RGBA): R = ambient occlusion (BVH ray casts against wood + leaves + ground, leaves counted as
half-opaque), G = sway weight (0 at the trunk base -> 1 at the outer twigs), B = random phase per branch / card,
A = leaf flutter (0 on wood, 0 at a card's twig base -> 1 at its tip).
Leaf-card normals are bent toward the crown's outward direction (spherical normals) so the canopy shades as a volume.
Units: metres, Z-up in Blender (glTF export -> Y-up). Origin = trunk centre at ground level; roots sink to z = -0.35.
"""
import bpy, bmesh, math, random, os, sys
from mathutils import Vector, Matrix, Quaternion
from mathutils.bvhtree import BVHTree
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, '..', 'tex'))
import blib as B
import vegetation_layout as LAY

OUT = os.path.normpath(os.path.join(HERE, '..', '..', 'assets', 'models', 'vegetation'))
UP = Vector((0, 0, 1))


# --------------------------------------------------------------------------------------------- skeleton
class Br:
    def __init__(self, pts, rad, level, sway0, seed):
        self.pts, self.rad, self.level, self.kids = pts, rad, level, []
        L = [0.0]
        for i in range(1, len(pts)): L.append(L[-1] + (pts[i] - pts[i - 1]).length)
        self.cum = L; self.length = L[-1]
        self.sway = [sway0 + 0.0] * len(pts)
        self.phase = seed

    def at(self, t):
        s = t * self.length
        for i in range(1, len(self.pts)):
            if self.cum[i] >= s or i == len(self.pts) - 1:
                f = (s - self.cum[i - 1]) / max(self.cum[i] - self.cum[i - 1], 1e-6); f = max(0.0, min(1.0, f))
                p = self.pts[i - 1].lerp(self.pts[i], f); r = self.rad[i - 1] + (self.rad[i] - self.rad[i - 1]) * f
                d = (self.pts[i] - self.pts[i - 1]).normalized(); w = self.sway[i - 1] + (self.sway[i] - self.sway[i - 1]) * f
                return p, d, r, w
        return self.pts[-1], (self.pts[-1] - self.pts[-2]).normalized(), self.rad[-1], self.sway[-1]


def rvec(rng):
    while True:
        v = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)))
        if 0.01 < v.length <= 1: return v.normalized()


def grow(rng, p0, d0, length, r0, r1, seglen, grav=0.0, wander=0.1, level=0, sway0=0.0, sway_gain=0.3, bend_up=0.0, max_r=None):
    n = max(2, int(math.ceil(length / seglen)))
    step = length / n
    pts, rad = [p0.copy()], [r0]
    p, d = p0.copy(), d0.normalized()
    for i in range(1, n + 1):
        t = i / n
        d = (d + UP * (grav + bend_up * t) * step + rvec(rng) * wander * step).normalized()
        p = p + d * step
        pts.append(p.copy()); rad.append(r0 + (r1 - r0) * (t ** 0.85))
    b = Br(pts, rad, level, sway0, rng.random())
    for i in range(len(pts)):
        b.sway[i] = sway0 + sway_gain * (b.cum[i] / max(length, 1e-6))
    return b


def perp(d):
    a = Vector((1, 0, 0)) if abs(d.x) < 0.8 else Vector((0, 1, 0))
    return d.cross(a).normalized()


def child_dir(rng, d, angle, az):
    """rotate d away from itself by `angle` (rad) around an axis spun by azimuth `az` around d"""
    ax = perp(d)
    ax = Quaternion(d, az) @ ax
    return (Quaternion(ax, angle) @ d).normalized()


# --------------------------------------------------------------------------------------------- species
def oak(seed, variant=0):
    rng = random.Random(seed)
    H = rng.uniform(2.3, 2.7)
    trunk = grow(rng, Vector((0, 0, -0.35)), Vector((rng.uniform(-0.06, 0.06), rng.uniform(-0.06, 0.06), 1)), H + 0.35, 0.3, 0.19, 0.3, wander=0.12, sway_gain=0.12)
    trunk.flare = True
    allb = [trunk]
    nl = rng.choice([3, 4]) if variant == 0 else 4
    az0 = rng.random() * 6.28
    limbs = []
    for k in range(nl + 1):
        lead = k == nl
        t = 1.0 if lead else (rng.uniform(0.86, 0.98) if k < 3 else rng.uniform(0.58, 0.72))
        p, d, r, w = trunk.at(t)
        az = az0 + k * 2 * math.pi / nl + rng.uniform(-0.3, 0.3)
        el = rng.uniform(0.15, 0.25) if lead else rng.uniform(0.55, 0.85) * (1.15 if k >= 3 else 1)
        dd = (Vector((math.cos(az) * math.sin(el), math.sin(az) * math.sin(el), math.cos(el)))).normalized()
        L = (rng.uniform(1.8, 2.3) if lead else rng.uniform(2.3, 3.0)) * (1.1 if variant else 1)
        b = grow(rng, p - d * r * 0.3, dd, L, r * (0.75 if lead else 0.62), 0.035, 0.3, grav=0.06 if not lead else 0.15, wander=0.35, level=1, sway0=w, sway_gain=0.35)
        trunk.kids.append(b); limbs.append(b); allb.append(b)
    for lb in limbs:
        ns = rng.randint(4, 6)
        for j in range(ns):
            t = 0.28 + 0.7 * (j + rng.random() * 0.5) / ns
            p, d, r, w = lb.at(t)
            dd = child_dir(rng, d, rng.uniform(0.6, 1.0), j * 2.4 + rng.random())
            dd = (dd + UP * 0.25).normalized()
            L = rng.uniform(1.0, 1.6) * (1 - 0.35 * t)
            sb = grow(rng, p, dd, L, max(0.022, r * 0.62), 0.012, 0.28, grav=-0.04, wander=0.5, level=2, sway0=w, sway_gain=0.3)
            lb.kids.append(sb); allb.append(sb)
            for m in range(rng.randint(2, 4)):
                t2 = 0.3 + 0.65 * (m + rng.random() * 0.4) / 3
                p2, d2, r2, w2 = sb.at(t2)
                d3 = (child_dir(rng, d2, rng.uniform(0.5, 0.9), m * 2.4 + rng.random()) + UP * 0.2).normalized()
                tw = grow(rng, p2, d3, rng.uniform(0.35, 0.6), max(0.012, r2 * 0.7), 0.006, 0.4, grav=0.0, wander=0.6, level=3, sway0=w2, sway_gain=0.2)
                sb.kids.append(tw); allb.append(tw)
    return dict(branches=allb, leaf='broad', card=(1.0, 1.3), cards_per_twig=3, cards_per_branch=4, crown_center=Vector((0, 0, H + 1.4)),
                crown_r=(2.6, 2.6, 1.9), outward=0.55, up=0.25, leaf_levels=(2, 3), bark='bark_oak', n_target=270)


def birch(seed, variant=0):
    rng = random.Random(seed)
    H = rng.uniform(6.6, 7.4)
    trunk = grow(rng, Vector((0, 0, -0.3)), Vector((rng.uniform(-0.05, 0.05), rng.uniform(-0.05, 0.05), 1)), H + 0.3, 0.17, 0.025, 0.35, wander=0.06, sway_gain=0.6)
    trunk.flare = True
    allb = [trunk]
    nb = 17
    for k in range(nb):
        t = 0.3 + 0.66 * k / nb + rng.uniform(-0.01, 0.01)
        p, d, r, w = trunk.at(t)
        az = k * 2.39996 + rng.uniform(-0.25, 0.25)
        el = rng.uniform(0.6, 0.85)
        dd = Vector((math.cos(az) * math.sin(el), math.sin(az) * math.sin(el), math.cos(el)))
        L = (0.6 + 2.0 * (1 - t) ** 0.7) * rng.uniform(0.85, 1.1) * (1.15 if variant else 1)
        b = grow(rng, p, dd, L, max(0.025, r * 0.45), 0.01, 0.3, grav=-0.32, wander=0.35, level=1, sway0=w, sway_gain=0.4)
        trunk.kids.append(b); allb.append(b)
        for m in range(rng.randint(2, 4)):
            t2 = 0.35 + 0.6 * m / 3 + rng.random() * 0.1
            p2, d2, r2, w2 = b.at(t2)
            d3 = (child_dir(rng, d2, rng.uniform(0.5, 0.8), m * 2.4 + rng.random()) - UP * 0.35).normalized()
            tw = grow(rng, p2, d3, rng.uniform(0.45, 0.8), max(0.01, r2 * 0.7), 0.005, 0.4, grav=-0.4, wander=0.5, level=3, sway0=w2, sway_gain=0.3)
            b.kids.append(tw); allb.append(tw)
    return dict(branches=allb, leaf='birch', card=(0.78, 1.0), cards_per_twig=3, cards_per_branch=4, crown_center=Vector((0, 0, H * 0.68)),
                crown_r=(1.8, 1.8, H * 0.38), outward=0.35, up=-0.35, leaf_levels=(1, 3), bark='bark_birch', n_target=230)


def cherry(seed, variant=0):
    rng = random.Random(seed)
    H = rng.uniform(1.4, 1.7)
    trunk = grow(rng, Vector((0, 0, -0.35)), Vector((rng.uniform(-0.12, 0.12), rng.uniform(-0.12, 0.12), 1)), H + 0.35, 0.25, 0.18, 0.3, wander=0.2, sway_gain=0.1)
    trunk.flare = True
    allb = [trunk]
    az0 = rng.random() * 6.28
    limbs = []
    for k in range(4):
        p, d, r, w = trunk.at(rng.uniform(0.85, 1.0))
        az = az0 + k * math.pi / 2 + rng.uniform(-0.35, 0.35)
        el = rng.uniform(0.75, 1.05)
        dd = Vector((math.cos(az) * math.sin(el), math.sin(az) * math.sin(el), math.cos(el)))
        b = grow(rng, p - d * r * 0.3, dd, rng.uniform(2.4, 3.0), r * 0.62, 0.03, 0.3, grav=-0.02, bend_up=-0.05, wander=0.4, level=1, sway0=w, sway_gain=0.35)
        trunk.kids.append(b); limbs.append(b); allb.append(b)
    for lb in limbs:
        for j in range(5):
            t = 0.3 + 0.68 * (j + rng.random() * 0.5) / 5
            p, d, r, w = lb.at(t)
            dd = (child_dir(rng, d, rng.uniform(0.55, 0.95), j * 2.4 + rng.random()) + UP * 0.35).normalized()
            sb = grow(rng, p, dd, rng.uniform(0.9, 1.4) * (1 - 0.3 * t), max(0.02, r * 0.6), 0.01, 0.28, grav=0.02, wander=0.55, level=2, sway0=w, sway_gain=0.3)
            lb.kids.append(sb); allb.append(sb)
            for m in range(rng.randint(2, 3)):
                p2, d2, r2, w2 = sb.at(0.35 + 0.3 * m + rng.random() * 0.1)
                d3 = (child_dir(rng, d2, rng.uniform(0.5, 0.9), m * 2.4 + rng.random()) + UP * 0.3).normalized()
                tw = grow(rng, p2, d3, rng.uniform(0.35, 0.55), max(0.01, r2 * 0.7), 0.005, 0.4, wander=0.6, level=3, sway0=w2, sway_gain=0.2)
                sb.kids.append(tw); allb.append(tw)
    return dict(branches=allb, leaf='blossom', card=(0.9, 1.15), cards_per_twig=3, cards_per_branch=4, crown_center=Vector((0, 0, H + 1.5)),
                crown_r=(3.0, 3.0, 1.6), outward=0.5, up=0.45, leaf_levels=(2, 3), bark='bark_oak', n_target=260)


def fir(seed, variant=0):
    rng = random.Random(seed)
    H = rng.uniform(7.6, 8.6) * (0.9 if variant else 1)
    trunk = grow(rng, Vector((0, 0, -0.35)), Vector((0, 0, 1)), H + 0.35, 0.27, 0.02, 0.4, wander=0.02, sway_gain=0.7)
    trunk.flare = True
    allb = [trunk]
    z = 1.15 + rng.random() * 0.2; wh = 0
    while z < H - 0.35:
        t = (z + 0.35) / (H + 0.35)
        p, d, r, w = trunk.at(t)
        rel = (H - z) / H
        L = 0.3 + 2.3 * rel ** 0.95 * rng.uniform(0.9, 1.08)
        n = 5 if rel > 0.25 else 4
        for k in range(n):
            az = wh * 0.7 + k * 2 * math.pi / n + rng.uniform(-0.25, 0.25)
            el = math.radians(rng.uniform(88, 100) - 18 * (1 - rel))      # from vertical: about horizontal, upper ones lift
            dd = Vector((math.cos(az) * math.sin(el), math.sin(az) * math.sin(el), math.cos(el)))
            b = grow(rng, p, dd, L, max(0.018, 0.05 * L / 2.4 + 0.012), 0.008, 0.7, grav=-0.12, bend_up=0.2, wander=0.15, level=1, sway0=w, sway_gain=0.35)
            trunk.kids.append(b); allb.append(b)
        z += rng.uniform(0.3, 0.38); wh += 1
    return dict(branches=allb, leaf='needle', card=(0.75, 0.95), cards_per_twig=0, cards_per_branch=0, crown_center=Vector((0, 0, H * 0.5)),
                crown_r=(2.3, 2.3, H * 0.55), outward=0.25, up=0.6, leaf_levels=(1,), bark='bark_pine', conifer=True, top=H)


def bush(seed, variant=0):
    rng = random.Random(seed)
    allb = []
    root = grow(rng, Vector((0, 0, -0.2)), UP, 0.25, 0.05, 0.04, 0.25, level=0, sway_gain=0.05)
    allb.append(root)
    ns = 6 if variant == 0 else 5
    for k in range(ns):
        az = k * 2 * math.pi / ns + rng.uniform(-0.3, 0.3); el = rng.uniform(0.3, 0.75)
        dd = Vector((math.cos(az) * math.sin(el), math.sin(az) * math.sin(el), math.cos(el)))
        b = grow(rng, Vector((rng.uniform(-0.05, 0.05), rng.uniform(-0.05, 0.05), -0.1)), dd, rng.uniform(0.8, 1.3) * (1.25 if variant else 1), 0.035, 0.008, 0.25,
                 grav=-0.05, wander=0.5, level=1, sway0=0.05, sway_gain=0.6)
        root.kids.append(b); allb.append(b)
        for m in range(3):
            p2, d2, r2, w2 = b.at(0.35 + 0.25 * m)
            tw = grow(rng, p2, (child_dir(rng, d2, 0.7, m * 2.4) + UP * 0.2).normalized(), rng.uniform(0.3, 0.5), r2 * 0.7, 0.004, 0.25, wander=0.6, level=3, sway0=w2, sway_gain=0.25)
            b.kids.append(tw); allb.append(tw)
    H = 0.75 if variant == 0 else 1.05
    return dict(branches=allb, leaf='broad' if variant == 0 else 'birch', card=(0.62, 0.8) if variant == 0 else (0.55, 0.75), cards_per_twig=0, cards_per_branch=0,
                crown_center=Vector((0, 0, H * 0.62)), crown_r=(1.0, 1.0, H * 0.75), outward=0.7, up=0.2, leaf_levels=(), bark='bark_oak', dome=90 if variant == 0 else 80, bushh=H)


# --------------------------------------------------------------------------------------------- meshing
class MeshBuf:
    def __init__(self):
        self.v, self.n, self.uv, self.col, self.f = [], [], [], [], []

    def add(self, p, n, uv, c):
        self.v.append(tuple(p)); self.n.append(tuple(n)); self.uv.append(tuple(uv)); self.col.append(list(c)); return len(self.v) - 1

    def tris(self): return len(self.f)


def frames(pts):
    n = len(pts); T = []
    for i in range(n):
        a = pts[max(i - 1, 0)]; b = pts[min(i + 1, n - 1)]; T.append((b - a).normalized())
    N = [perp(T[0])]
    for i in range(1, n):
        v = N[-1] - T[i] * N[-1].dot(T[i])
        N.append(v.normalized() if v.length > 1e-6 else perp(T[i]))
    return T, N


def tube(buf, br, sides, ring_step=1, vscale=0.55, tile_m=0.55, flare=False, rng=None):
    idx = list(range(0, len(br.pts), ring_step))
    if idx[-1] != len(br.pts) - 1: idx.append(len(br.pts) - 1)
    pts = [br.pts[i] for i in idx]; rad = [br.rad[i] for i in idx]; sw = [br.sway[i] for i in idx]; cum = [br.cum[i] for i in idx]
    T, N = frames(pts)
    urep = max(1, round(2 * math.pi * rad[0] / tile_m))
    lob_ph = rng.random() * 6.28 if rng else 0
    rings = []
    for i, p in enumerate(pts):
        Bn = T[i].cross(N[i])
        ring = []
        for j in range(sides + 1):
            th = j / sides * 2 * math.pi
            dirv = N[i] * math.cos(th) + Bn * math.sin(th)
            r = rad[i]
            if flare:
                zf = max(0.0, p.z + 0.35)
                fl = math.exp(-max(p.z, -0.2) / 0.32)
                r *= 1 + 0.55 * fl + 0.45 * fl * max(0.0, math.sin(th * 5 + lob_ph)) ** 2
            q = p + dirv * r
            ring.append(buf.add(q, dirv, (j / sides * urep, cum[i] / vscale), [1, sw[i], br.phase, 0]))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for j in range(sides):
            a, b, c, d = rings[i][j], rings[i][j + 1], rings[i + 1][j + 1], rings[i + 1][j]
            buf.f.append((a, b, c)); buf.f.append((a, c, d))
    # tip cap
    tip = buf.add(pts[-1] + T[-1] * rad[-1] * 1.5, T[-1], (0.5 * urep, cum[-1] / vscale + 0.05), [1, sw[-1], br.phase, 0])
    for j in range(sides): buf.f.append((rings[-1][j], rings[-1][j + 1], tip))


def card(buf, base, d, side, w, l, rect, fold, nrm_fn, sway, phase):
    """folded quad (6 verts / 4 tris): base at the twig, long axis d, half-width along side; spine raised along n"""
    n = d.cross(side).normalized()
    u0, v0, u1, v1 = rect; um = (u0 + u1) / 2
    hw = w / 2
    lift = n * hw * math.sin(fold); sx = side * hw * math.cos(fold)
    P = [base - sx - lift, base, base + sx - lift, base + d * l - sx - lift, base + d * l, base + d * l + sx - lift]
    UV = [(u0, v0), (um, v0), (u1, v0), (u0, v1), (um, v1), (u1, v1)]
    FL = [0, 0, 0, 1, 1, 1]
    ids = [buf.add(P[k], nrm_fn(P[k], n), UV[k], [1, sway, phase, FL[k] * 0.9 + 0.1 * (k != 1 and k != 4)]) for k in range(6)]
    a = ids
    buf.f += [(a[0], a[1], a[4]), (a[0], a[4], a[3]), (a[1], a[2], a[5]), (a[1], a[5], a[4])]


def leaf_cards(spec, rng, lod):
    """returns list of (base, d, side, w, l, sway, phase)"""
    out = []
    cc, cr = spec['crown_center'], spec['crown_r']
    def orient(p, dtw):
        outv = Vector(((p.x - cc.x) / cr[0], (p.y - cc.y) / cr[1], (p.z - cc.z) / cr[2]))
        outv = outv.normalized() if outv.length > 1e-4 else UP.copy()
        d = (dtw * (1 - spec['outward']) + outv * spec['outward'] + UP * spec['up'] + rvec(rng) * 0.35).normalized()
        side = d.cross(rvec(rng)).normalized()
        # bias the card face toward the outside of the crown so it is seen face-on more often
        n = d.cross(side)
        if n.dot(outv) < 0: side = -side
        return d, side
    lo, hi = spec['card']
    if spec.get('conifer'):
        for b in spec['branches']:
            if b.level != 1: continue
            n = max(1, int(b.length / 0.38))
            for k in range(n):
                t = 0.06 + 0.94 * k / n
                p, dtw, r, w = b.at(t)
                d = (dtw + UP * 0.05).normalized()
                lat0 = d.cross(UP).normalized()
                grow_ = 0.65 + 0.45 * min(1.0, b.length / 1.8)
                for sdv in (-1, 1):
                    lat = lat0 * sdv
                    dd = (d * 0.75 + lat * 0.55 + UP * rng.uniform(-0.1, 0.1)).normalized()
                    side = dd.cross(UP).normalized()
                    side = (Quaternion(dd, sdv * rng.uniform(0.25, 0.75)) @ side).normalized()   # sprays tilt like shingles
                    s = rng.uniform(lo, hi) * grow_
                    out.append((p - UP * 0.02, dd, side, s * 0.8, s, w, rng.random()))
                if k % 3 == 1:                                            # hanging skirt under the branch
                    dd = (d * 0.45 - UP * 0.85 + lat0 * rng.uniform(-0.3, 0.3)).normalized()
                    side = lat0.copy()
                    s = rng.uniform(lo, hi) * grow_ * 0.8
                    out.append((p, dd, side, s * 0.8, s, w, rng.random()))
        top = spec['top']
        for k in range(3):            # leader: crossed vertical sprays
            az = k * math.pi / 3
            side = Vector((math.cos(az), math.sin(az), 0))
            out.append((Vector((0, 0, top - 1.0)), UP.copy(), side, 0.6, 1.25, 1.0, rng.random()))
    elif spec.get('dome'):
        H = spec['bushh']
        for k in range(spec['dome']):
            # points over a squashed dome, biased to the shell; base toward the centre, tip outward
            while True:
                v = rvec(rng)
                if v.z > -0.15: break
            rr = 0.55 + 0.45 * rng.random() ** 0.5
            p = Vector((v.x * cr[0] * rr * 0.75, v.y * cr[1] * rr * 0.75, cc.z + v.z * cr[2] * rr * 0.75 - 0.15))
            d = (v * 0.8 + UP * 0.35 + rvec(rng) * 0.3).normalized()
            side = d.cross(rvec(rng)).normalized()
            if d.cross(side).dot(v) < 0: side = -side
            s = rng.uniform(lo, hi)
            out.append((p - d * s * 0.35, d, side, s, s, 0.2 + 0.5 * max(0.0, v.z), rng.random()))
    else:
        for b in spec['branches']:
            if b.level not in spec['leaf_levels']: continue
            if b.level == 3: ts = [0.4, 0.7, 1.0][-spec['cards_per_twig']:]
            else: ts = [0.45 + 0.55 * (k + 0.5) / spec['cards_per_branch'] for k in range(spec['cards_per_branch'])]
            for t in ts:
                p, dtw, r, w = b.at(t)
                d, side = orient(p, dtw)
                s = rng.uniform(lo, hi)
                out.append((p, d, side, s, s, min(1.0, w + 0.1), rng.random()))
    rng.shuffle(out)
    if lod == 1:
        keep = out[: max(12, int(len(out) * 0.36))]
        out = [(p, d, sd, w * 1.45, l * 1.45, sw, ph) for (p, d, sd, w, l, sw, ph) in keep]
    return out


def build(name, spec, seed, lod):
    rng = random.Random(seed * 7 + lod)
    wood, leaf = MeshBuf(), MeshBuf()
    for b in spec['branches']:
        if lod == 1 and b.level >= 3: continue
        if lod == 1 and b.level == 2 and b.length < 0.9: continue
        if lod == 1 and spec.get('conifer') and b.level == 1 and (b.length < 1.1 or rng.random() < 0.5): continue
        sides = [10, 6, 4, 3][b.level] if lod == 0 else [6, 4, 3, 3][b.level]
        if b.level == 0 and spec.get('conifer'): sides = 9 if lod == 0 else 6
        if b.level == 1 and spec.get('conifer'): sides = 3
        tube(wood, b, sides, ring_step=1 if lod == 0 else 2, flare=getattr(b, 'flare', False), rng=rng,
             tile_m=0.5 if spec['bark'] != 'bark_birch' else 0.7, vscale=0.55 if spec['bark'] != 'bark_birch' else 0.75)
    region = LAY.FOLIAGE[spec['leaf']]
    rect = LAY.uv_rect(region, inset=3.0)
    cc, cr = spec['crown_center'], spec['crown_r']
    def nrm_fn(p, n):
        o = Vector(((p.x - cc.x) / cr[0], (p.y - cc.y) / cr[1], (p.z - cc.z) / cr[2] + 0.35))
        o = o.normalized() if o.length > 1e-4 else UP.copy()
        if n.dot(o) < 0: n = -n
        return (o * 0.72 + n * 0.28).normalized()
    for (p, d, side, w, l, sw, ph) in leaf_cards(spec, rng, lod):
        card(leaf, p, d, side, w, l, rect, math.radians(rng.uniform(14, 28)), nrm_fn, sw, ph)
    return wood, leaf


def make_obj(name, buf, mat):
    me = bpy.data.meshes.new(name)
    me.from_pydata(buf.v, [], buf.f)
    me.update()
    uv = me.uv_layers.new(name='UVMap')
    loops_uv = []
    for poly in me.polygons:
        for li in poly.loop_indices: loops_uv += buf.uv[me.loops[li].vertex_index]
    uv.data.foreach_set('uv', loops_uv)
    ca = me.color_attributes.new('Col', 'FLOAT_COLOR', 'POINT')
    flat = []
    for c in buf.col: flat += c
    ca.data.foreach_set('color', flat)
    me.color_attributes.active_color = ca
    try: me.color_attributes.render_color_index = me.color_attributes.find('Col')
    except Exception: pass
    me.use_auto_smooth = True
    me.normals_split_custom_set_from_vertices([Vector(n).normalized() for n in buf.n])
    ob = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(ob)
    m = bpy.data.materials.get(mat) or bpy.data.materials.new(mat)
    me.materials.append(m)
    return ob


def bake_ao(objs, ground=True, rays=14, dist=2.4, leaf_alpha=0.55, seed=3):
    """R channel <- occlusion. Leaf hits count as partly transparent (alpha-tested cards)."""
    random.seed(seed)
    trees = []
    for o in objs:
        bm = bmesh.new(); bm.from_mesh(o.data); bm.transform(o.matrix_world)
        trees.append((BVHTree.FromBMesh(bm), leaf_alpha if o.name.find('_leaf') >= 0 else 1.0)); bm.free()
    if ground:
        bm = bmesh.new()
        vs = [bm.verts.new(v) for v in [(-30, -30, 0), (30, -30, 0), (30, 30, 0), (-30, 30, 0)]]
        bm.faces.new(vs); trees.append((BVHTree.FromBMesh(bm), 1.0)); bm.free()
    dirs = []
    while len(dirs) < rays:
        v = Vector((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-1, 1)))
        if 0.05 < v.length <= 1: dirs.append(v.normalized())
    for o in objs:
        me = o.data; ca = me.color_attributes['Col']
        me.calc_normals_split()
        vn = [Vector((0, 0, 0)) for _ in me.vertices]
        for lp in me.loops: vn[lp.vertex_index] += lp.normal
        cols = [0.0] * (len(me.vertices) * 4); ca.data.foreach_get('color', cols)
        isleaf = o.name.find('_leaf') >= 0
        for i, v in enumerate(me.vertices):
            n = vn[i].normalized() if vn[i].length > 1e-6 else UP
            p = v.co + n * 0.03
            hit = 0.0; tot = 0.0
            for d in dirs:
                if d.dot(n) < 0: d = -d
                d = (d + n * 0.3).normalized()
                w = d.dot(n) * (0.6 + 0.4 * max(0.0, d.z))       # sky-weighted
                tot += w
                occ = 0.0
                for t, a in trees:
                    h = t.ray_cast(p, d, dist)
                    if h[0] is not None: occ = max(occ, a * (1 - (h[3] / dist) ** 1.5))
                hit += w * occ
            ao = 1 - hit / max(tot, 1e-6)
            if not isleaf: ao = min(ao, 0.45 + 0.55 * min(1.0, max(0.0, (v.co.z + 0.1) / 0.9)) ** 0.7)   # ground contact
            cols[i * 4] = max(0.08, min(1.0, ao))
        ca.data.foreach_set('color', cols)


def tri_count(o): return sum(len(p.vertices) - 2 for p in o.data.polygons)


SPECIES = [
    ('oak_a', oak, 11, 0), ('oak_b', oak, 23, 1), ('birch_a', birch, 31, 0), ('birch_b', birch, 37, 1),
    ('cherry_a', cherry, 41, 0), ('fir_a', fir, 51, 0), ('fir_b', fir, 57, 1), ('bush_a', bush, 61, 0), ('bush_b', bush, 67, 1),
]


def fern_obj(name, seed, lod=0):
    rng = random.Random(seed)
    buf = MeshBuf()
    rect = LAY.uv_rect(LAY.COVER['fern'], inset=3.0)
    u0, v0, u1, v1 = rect
    nf = 9 if lod == 0 else 5
    for k in range(nf):
        az = k * 2 * math.pi / nf + rng.uniform(-0.25, 0.25)
        L = rng.uniform(0.75, 1.05); W = L * 0.5
        el = math.radians(rng.uniform(42, 62)); droop = rng.uniform(0.7, 1.0)
        dirh = Vector((math.cos(az), math.sin(az), 0)); side = Vector((-math.sin(az), math.cos(az), 0))
        roll = rng.uniform(-0.3, 0.3)
        seg = 4 if lod == 0 else 2
        prev = None; ph = rng.random()
        for s in range(seg + 1):
            t = s / seg
            c = dirh * (L * t * math.cos(el) * (0.6 + 0.4 * t)) + UP * (L * (t * math.sin(el) - 0.5 * droop * t * t * 0.9))
            tang = (dirh * math.cos(el) + UP * (math.sin(el) - droop * t * 0.9)).normalized()
            sd = (Quaternion(tang, roll) @ side).normalized()
            n = tang.cross(sd).normalized()
            if n.z < 0: n = -n
            nn = (n * 0.6 + UP * 0.4).normalized()
            vv = v0 + (v1 - v0) * t
            a = buf.add(c - sd * W / 2, nn, (u0, vv), [1, 0.2 + 0.6 * t, ph, t])
            b = buf.add(c + sd * W / 2, nn, (u1, vv), [1, 0.2 + 0.6 * t, ph, t])
            if prev: buf.f += [(prev[0], prev[1], b), (prev[0], b, a)]
            prev = (a, b)
    return buf


def main():
    B.reset()
    os.makedirs(OUT, exist_ok=True)
    objs = []
    for name, fn, seed, var in SPECIES:
        spec = fn(seed, var)
        for lod in (0, 1):
            wood, leaf = build(name, spec, seed, lod)
            sfx = '' if lod == 0 else '_lod1'
            ow = make_obj(f'{name}_wood{sfx}', wood, spec['bark'])
            ol = make_obj(f'{name}_leaf{sfx}', leaf, 'leaf_' + spec['leaf'])
            bake_ao([ow, ol], rays=14 if lod == 0 else 8, dist=2.4 if not name.startswith('bush') else 1.2)
            print(f'{name}{sfx}: wood {tri_count(ow)} tris, leaf {tri_count(ol)} tris')
            # keep each tree's objects apart while baking the next (AO only sees its own tree)
            for o in (ow, ol): o.hide_set(False)
            objs += [ow, ol]
            # move out of the way of the next bake, then back at export
            for o in (ow, ol): o.location.x += 1000 + len(objs) * 50
    for nm, seed in (('fern_a', 71), ('fern_b', 73)):
        for lod in (0, 1):
            buf = fern_obj(nm, seed, lod)
            o = make_obj(f'{nm}_leaf' + ('' if lod == 0 else '_lod1'), buf, 'cover')
            o.location.x += 1000 + len(objs) * 50
            print(f'{o.name}: {tri_count(o)} tris')
            objs.append(o)
    for o in objs: o.location.x = 0
    path = os.path.join(OUT, 'trees.glb')
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_colors=True, export_normals=True,
                              export_apply=True, export_yup=True, export_materials='PLACEHOLDER', export_texcoords=True)
    import vegetation_glb as Q
    s0 = os.path.getsize(path); Q.quantize(path)
    print('wrote', path, s0, '->', os.path.getsize(path))


main()
