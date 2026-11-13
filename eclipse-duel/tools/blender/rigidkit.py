# Rigid-piece character kit for Blender (used by heroes/idol.py, heroes/cultist.py): pieces are modelled in bone frames on
# an exported game rig, each RIGID on one bone, then decimated to a triangle budget, given per-vertex colour (look + wear
# + patina), cavity (ray-cast ambient occlusion) and glow, and written as an EDB1 asset the JS kit loads
# (src/rpg/boss/design.js documents the format; src/rpg/edb.js decodes it).
#
#   import rigidkit as K; from rigidkit import *; K.init('idol'); rig = K.rig
#   ... reg(shell(...), 'chest', 'stone') ...
#   K.finish(out_path, budget=78000, hero='idol', preview='--preview' in sys.argv)

import sys
import os
import math
import json
import struct
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy                      # noqa: E402,F401
import bmesh                    # noqa: E402
from mathutils import Vector    # noqa: E402
from mathutils.bvhtree import BVHTree   # noqa: E402
import edlib as ed              # noqa: E402
from ed.model import fbm, vnoise   # noqa: E402,F401

TAU = math.pi * 2
rig = None
PARTS = []      # dict(obj, bone, look, glow)

LOOKS = {
    #          colour (linear)        rough metal detail slot
    'stone':  ((0.055, 0.058, 0.072), 0.80, 0.08, 1.0, 'plate'),
    'bronze': ((0.30, 0.185, 0.07), 0.42, 0.90, 1.0, 'plate'),
    'gold':   ((0.62, 0.40, 0.11), 0.30, 1.00, 0.8, 'plate'),
    'iron':   ((0.028, 0.03, 0.036), 0.46, 0.85, 1.0, 'plate'),
    'cord':   ((0.24, 0.022, 0.016), 0.92, 0.00, 0.6, 'plate'),
    'black':  ((0.002, 0.002, 0.003), 0.95, 0.0, 0.2, 'plate'),
    'ember':  ((0.02, 0.012, 0.006), 0.6, 0.2, 0.5, 'plate'),
    'straw':  ((0.30, 0.22, 0.09), 0.95, 0.00, 1.0, 'plate'),
    'robe':   ((0.042, 0.02, 0.022), 0.95, 0.00, 0.7, 'plate'),
    'steel':  ((0.09, 0.095, 0.11), 0.34, 1.00, 0.9, 'blade'),
    'hilt':   ((0.30, 0.185, 0.07), 0.42, 0.90, 1.0, 'blade'),
    'wrap':   ((0.24, 0.022, 0.016), 0.92, 0.00, 0.6, 'blade'),
}


# the engine's texture set of each look (src/char/kit/textures.js SET) and its detail amount; glow channel of a piece:
# stone -> 'vein' (the set's crack mask x the vertex value = fire in the cracks), ember -> 'eye', everything else 'inlay'
# (never 'legacy' for a glowing look: the legacy set adds the glow attribute as raw RGB even in channel mode)
SETS = {'stone': ('scorched', 1.0), 'bronze': ('bronze', 1.0), 'gold': ('hammered', 0.45), 'iron': ('lacquer', 0.9), 'cord': ('cloth', 1.0),
        'black': ('leather', 0.15), 'ember': ('hammered', 0.2), 'steel': ('hammered', 0.3), 'hilt': ('bronze', 1.0), 'wrap': ('cloth', 1.0),
        'straw': ('hemp', 1.0), 'robe': ('hemp', 0.9), 'sash': ('silk', 1.0), 'bandage': ('hemp', 1.0)}


def init(name):
    """Fresh scene + the game rig tools/blender/rigs/<name>.json."""
    global rig
    ed.reset_scene()
    rig = ed.Rig(name)
    PARTS.clear()
    return rig


def reg(obj, bone, look, glow=0.0, chip=0.0, wear=1.0):
    """Register a piece: rigid on `bone`. glow: constant 0..1 or fn(P_local) -> (n,). chip: stone damage (m)."""
    ed.recalc_normals(obj)
    if chip:
        damage(obj, chip)
    PARTS.append(dict(obj=obj, bone=bone, look=look, glow=glow, wear=wear))
    return obj


def B(bone, pts):
    """Bone-frame points (game axes: x forward, y up / along the limb toward its parent, z right) -> Blender world."""
    return rig.pts(bone, np.atleast_2d(np.asarray(pts, dtype=np.float64)))


def ring(bone, y, rx, rz, n=24, a0=0.0, a1=360.0, power=2.3, ox=0.0, oz=0.0, bump=None):
    """A superellipse ring in the bone's XZ plane at height y. Angles in degrees: 0 = forward (+X), 90 = right (+Z)."""
    closed = a1 - a0 >= 359.9
    th = np.radians(np.linspace(a0, a1, n, endpoint=not closed))
    c, s = np.cos(th), np.sin(th)
    e = 2.0 / power
    k = 1.0 + (bump(th) if bump else 0.0)
    x = ox + rx * k * np.sign(c) * np.abs(c) ** e
    z = oz + rz * k * np.sign(s) * np.abs(s) ** e
    return B(bone, np.stack([x, np.full_like(x, y), z], 1))


def lip(obj, thick):
    """Give an open shell a visible edge thickness: extrude its boundary inward (no inner surface: half the triangles)."""
    me = obj.data
    bm = bmesh.new(); bm.from_mesh(me)
    bm.normal_update()
    edges = [e for e in bm.edges if e.is_boundary]
    if edges:
        nrm = {v: v.normal.copy() for e in edges for v in e.verts}
        r = bmesh.ops.extrude_edge_only(bm, edges=edges)
        new = [g for g in r['geom'] if isinstance(g, bmesh.types.BMVert)]
        # each new vertex sits on its source: find the source through the connecting edge
        for v in new:
            src = None
            for e in v.link_edges:
                o = e.other_vert(v)
                if o in nrm:
                    src = o; break
            v.co -= (nrm[src] if src else v.normal) * thick
    bm.to_mesh(me); bm.free()
    me.update()


def shell(name, bone, stations, n=24, a0=0.0, a1=360.0, power=2.3, thick=0.012, sub=0, bev=0.0025, bump=None, caps=(False, False)):
    """Lofted plate: stations [(y, rx, rz[, ox, oz])] in the bone frame; open shells get an edge lip."""
    closed = a1 - a0 >= 359.9
    rings = [ring(bone, s[0], s[1], s[2], n, a0, a1, power, s[3] if len(s) > 3 else 0.0, s[4] if len(s) > 4 else 0.0, bump) for s in stations]
    o = ed.loft(name, np.array(rings), close=closed, caps=caps)
    ed.recalc_normals(o)
    if sub:
        ed.subdivide(o, sub)
    if thick:
        lip(o, thick)
    if bev:
        ed.bevel(o, width=bev, segments=1, angle=40.0)
    ed.shade(o, angle=38)
    return o


def damage(obj, amount):
    """Old stone and cast bronze: a slow hammered undulation and sparse sharp chips knocked out of it."""
    def fn(P, N):
        a = fbm(P * 9.0, octaves=3, seed=11) - 0.5
        chips = np.clip((fbm(P * 42.0, octaves=3, seed=5) - 0.63) / 0.12, 0, 1)
        return a * 0.45 * amount - chips * amount
    ed.displace(obj, fn, strength=1.0)


def sweep(name, bone, pts, radius, section=8, scale_y=1.0, twist=None):
    path = B(bone, pts)
    o = ed.sweep(name, path, section=section, radius=radius, scale_y=scale_y, twist=twist)
    ed.shade(o, angle=45)
    return o


def spline(pts, n=24):
    """Catmull-Rom through control points ((k, 3)) -> (n, 3)."""
    pts = np.asarray(pts, dtype=np.float64)
    k = len(pts)
    t = np.linspace(0, k - 1, n)
    out = np.zeros((n, 3))
    for i, x in enumerate(t):
        j = min(int(x), k - 2); f = x - j
        p0, p1, p2, p3 = pts[max(j - 1, 0)], pts[j], pts[j + 1], pts[min(j + 2, k - 1)]
        out[i] = 0.5 * ((2 * p1) + (-p0 + p2) * f + (2 * p0 - 5 * p1 + 4 * p2 - p3) * f * f + (-p0 + 3 * p1 - 3 * p2 + p3) * f ** 3)
    return out


def ball(name, bone, c, radii, segs=(12, 8)):
    R = np.stack([rig.vec(bone, [1, 0, 0]), rig.vec(bone, [0, 1, 0]), rig.vec(bone, [0, 0, 1])], 1)
    o = ed.ellipsoid(name, B(bone, c)[0], radii, rot=R, segs=segs)
    ed.shade(o, angle=60)
    return o


def rivets(name, bone, y, rx, rz, count, r=0.008, a0=0.0, a1=360.0, power=2.3):
    P = ring(bone, y, rx, rz, count, a0, a1, power)
    objs = [ed.ellipsoid(f'{name}{i}', p, (r, r, r), segs=(6, 4)) for i, p in enumerate(P)]
    o = ed.join(objs, name)
    ed.shade(o, angle=60)
    return o


def cone(bone, apex, radius, height, toward, bell=1.0, v0=0.45):
    """Cone surface hanging down the bone's -Y from `apex` (bone frame); u = 0 faces the bone-frame direction `toward`."""
    S = ed.cone_surface(B(bone, apex)[0], rig.vec(bone, [0, 1, 0]), radius, height, bell=bell, v0=v0)
    want = ed.normalize(rig.vec(bone, toward))
    best, bu = -9.0, 0.0
    for u in np.linspace(0, 1, 144, endpoint=False):
        dd = float(np.dot(ed.normalize(np.asarray(S(u, 1.0)) - np.asarray(S(u + 0.5, 1.0))), want))
        if dd > best:
            best, bu = dd, u
    return lambda u, v: S(u + bu, v)


def lam(bone, name, S, lace=True, **kw):
    """Lamellar panel: dark lacquered plates and their red lacing."""
    plates, lacing = ed.lamellar(name, S, lace=lace, lace_r=0.0022, **kw)
    ed.shade(plates, angle=35)
    reg(plates, bone, 'iron')
    if lacing is not None:
        reg(lacing, bone, 'cord')


def both(fn):
    """Build a right-side piece and its mirrored left twin: fn(side, sgn) -> list of (obj, boneBase, look, kwargs)."""
    for side, sgn in (('R', 1.0), ('L', -1.0)):
        fn(side, sgn)



def finish(OUT, budget=78000, hero='idol', preview=False, height=2.35):
    """Decimate to the budget, bake per-vertex data, write the EDB1 asset (and a Cycles preview sheet)."""
    global PARTS
    BUDGET = budget
    PARTS[:] = [p for p in PARTS if p and p.get('obj') is not None]
    ed.log('pieces', len(PARTS), 'triangles', sum(ed.tri_count(p['obj']) for p in PARTS))
    # =====================================================================================================================
    # Decimate to the budget, then bake per-vertex data
    # =====================================================================================================================
    total = sum(ed.tri_count(p['obj']) for p in PARTS)
    if total > BUDGET:
        # the dense sculpted pieces give up triangles first; pattern pieces (lamellar, braid, tassels) keep their shape
        dense = [p for p in PARTS if ed.tri_count(p['obj']) > 600 and p['look'] not in ('cord', 'wrap', 'bandage')]
        dt = sum(ed.tri_count(p['obj']) for p in dense)
        ratio = max(0.25, (BUDGET - (total - dt)) / max(dt, 1))
        for p in dense:
            ed.add_mod(p['obj'], 'DECIMATE', ratio=ratio)
            ed.apply_mods(p['obj'])
            ed.shade(p['obj'], angle=38)
        ed.log('decimated dense pieces by', round(ratio, 3), '->', sum(ed.tri_count(p['obj']) for p in PARTS))


    def tri_arrays(obj):
        """Split-normal triangle soup of an object, welded on (vertex, normal): P (n, 3) world, N (n, 3), idx (m, 3), src vertex."""
        me = obj.data
        me.calc_loop_triangles()
        nl = len(me.loops)
        lv = np.zeros(nl, dtype=np.int32); me.loops.foreach_get('vertex_index', lv)
        ln = np.zeros(nl * 3, dtype=np.float32); me.corner_normals.foreach_get('vector', ln); ln = ln.reshape(-1, 3)
        co = ed.verts_of(obj)
        nt = len(me.loop_triangles)
        tl = np.zeros(nt * 3, dtype=np.int32); me.loop_triangles.foreach_get('loops', tl)
        key = np.concatenate([lv[tl][:, None].astype(np.int64), np.round(ln[tl] * 24).astype(np.int64)], 1)
        uniq, inv = np.unique(key, axis=0, return_inverse=True)
        first = np.zeros(len(uniq), dtype=np.int64); first[inv] = np.arange(len(tl))
        src = lv[tl][first]
        return co[src], ln[tl][first].astype(np.float64), inv.reshape(-1, 3), src


    # occluders: every piece plus the under-body as capsules
    occ_v, occ_f, base = [], [], 0
    for p in PARTS:
        P_, N_, I_, _ = tri_arrays(p['obj'])
        p['P'], p['N'], p['I'] = P_, N_, I_
        occ_v.append(P_); occ_f.append(I_ + base); base += len(P_)
    for (nm, a, b_, r) in rig.capsules():
        o = ed.capsule('_occ_' + nm, a, b_, r * 0.92, segs=10)
        P_, N_, I_, _ = tri_arrays(o)
        occ_v.append(P_); occ_f.append(I_ + base); base += len(P_)
        ed.delete([o])
    OV = np.vstack(occ_v); OF = np.vstack(occ_f)
    bvh = BVHTree.FromPolygons([Vector(v) for v in OV], [tuple(int(i) for i in f) for f in OF])
    ed.log('occluder triangles', len(OF))

    rng = np.random.default_rng(3)
    RAYS = 20
    dirs = rng.normal(size=(RAYS, 3)); dirs /= np.linalg.norm(dirs, axis=1)[:, None]


    def ambient(P_, N_, reach=0.22):
        out = np.ones(len(P_))
        for i in range(len(P_)):
            n = N_[i]; p = Vector(P_[i] + n * 0.004)
            hit = 0.0
            for d in dirs:
                dd = d if d @ n > 0 else -d
                dd = dd * 0.75 + n * 0.25
                r = bvh.ray_cast(p, Vector(dd), reach)
                if r[0] is not None:
                    hit += 1.0 - 0.5 * (r[3] / reach)
            out[i] = 1.0 - hit / RAYS
        return out


    def curvature(P_, N_, I_):
        """Signed mean-curvature proxy per vertex: > 0 on convex edges (wear), < 0 in creases (dirt)."""
        acc = np.zeros(len(P_)); cnt = np.zeros(len(P_))
        for a, b in ((0, 1), (1, 2), (2, 0)):
            e = P_[I_[:, b]] - P_[I_[:, a]]
            ln = np.linalg.norm(e, axis=1) + 1e-9
            np.add.at(acc, I_[:, a], -np.einsum('ij,ij->i', N_[I_[:, a]], e) / ln)
            np.add.at(acc, I_[:, b], np.einsum('ij,ij->i', N_[I_[:, b]], e) / ln)
            np.add.at(cnt, I_[:, a], 1); np.add.at(cnt, I_[:, b], 1)
        return acc / np.maximum(cnt, 1)


    pieces = []
    blob = bytearray()


    def pad4():
        while len(blob) % 4:
            blob.append(0)


    nv_total = nt_total = 0
    for p in PARTS:
        P_, N_, I_ = p['P'], p['N'], p['I']
        col0, rough, metal, detail, slot = LOOKS[p['look']]
        ao = ambient(P_, N_)
        cur = curvature(P_, N_, I_)
        Pl = rig.local(p['bone'], P_)
        Nl = N_ @ rig.M[p['bone']][:3, :3]          # world normal -> bone frame (orthonormal)
        g = p['glow']
        glow = np.clip(g(Pl) if callable(g) else np.full(len(P_), float(g)), 0, 1)
        col = np.tile(np.array(col0), (len(P_), 1))
        grime = fbm(P_ * 14.0, octaves=3, seed=21)
        if p['look'] == 'stone':
            # where the cracks of the engine's `scorched` set burn: broad regions, the texture draws the crack lines
            glow = np.clip((fbm(P_ * 2.4, octaves=2, seed=8) - 0.4) / 0.22, 0, 1) * 0.95
            col *= (0.8 + 0.4 * grime)[:, None]
        elif p['look'] in ('bronze', 'gold', 'hilt'):
            col *= (0.85 + 0.3 * grime)[:, None]
        else:
            col *= (0.82 + 0.36 * grime)[:, None]
        col *= (0.7 + 0.3 * ao)[:, None]                                                       # a little baked occlusion in the albedo
        # cavity: < 1 occluded crevice (the material grimes it), > 1 convex edge (the material wears it to bare metal)
        edge = np.clip(cur * 2.6, 0, 1) * np.clip((ao - 0.55) / 0.3, 0, 1)
        cav = np.where(edge > 0.05, 1.0 + edge, np.clip(0.25 + 0.75 * ao + np.clip(cur, -0.4, 0) * 0.5, 0.05, 1))
        bmin, bmax = Pl.min(0) - 1e-4, Pl.max(0) + 1e-4
        q = np.round((Pl - bmin) / (bmax - bmin) * 65535).astype('<u2')
        assert len(P_) < 65536, p['obj'].name
        rec = dict(bone=p['bone'], slot=slot, rough=rough, metal=metal, detail=detail, set=SETS.get(p['look'], ('legacy', detail))[0], amt=SETS.get(p['look'], ('legacy', detail))[1],
                   gch='vein' if p['look'] == 'stone' else 'eye' if p['look'] == 'ember' else 'inlay', nv=len(P_), ni=int(I_.size), bmin=[round(float(x), 5) for x in bmin], bmax=[round(float(x), 5) for x in bmax])
        pad4(); rec['pos'] = len(blob); blob += q.tobytes()
        nb = np.concatenate([np.clip(np.round(Nl * 127), -127, 127).astype('i1').view('u1'), np.round(cav * 127.5).astype('u1')[:, None]], 1)
        pad4(); rec['nrm'] = len(blob); blob += nb.tobytes()
        cb = np.concatenate([np.round(np.sqrt(np.clip(col, 0, 1)) * 255).astype('u1'), np.round(glow * 255).astype('u1')[:, None]], 1)
        pad4(); rec['col'] = len(blob); blob += cb.tobytes()
        pad4(); rec['idx'] = len(blob); blob += I_.astype('<u2').tobytes()
        pieces.append(rec)
        nv_total += len(P_); nt_total += len(I_)

    head_json = json.dumps(dict(format='EDB1', hero=hero, cav2=True, pieces=pieces), separators=(',', ':')).encode()
    while len(head_json) % 4:
        head_json += b' '
    with open(OUT, 'wb') as f:
        f.write(b'EDB1' + struct.pack('<I', len(head_json)) + head_json + bytes(blob))
    ed.log('wrote', OUT, round(os.path.getsize(OUT) / 1024), 'KB', 'pieces', len(pieces), 'vertices', nv_total, 'triangles', nt_total)

    if preview:
        # vertex colours for the Cycles preview
        for p in PARTS:
            col0 = LOOKS[p['look']][0]
            mat = ed.look('pv_' + p['look'], color=tuple(c ** (1 / 2.2) for c in col0), rough=LOOKS[p['look']][1], metal=LOOKS[p['look']][2], vcol=False)
            ed.assign_look(p['obj'], mat)
        ed.preview_sheet(hero, name=hero, height=height, samples=10, cell=(300, 520))
