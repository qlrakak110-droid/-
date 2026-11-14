# KAEL's own helpers on top of edlib (candidates for the shared library; reported, not merged into edlib):
#
#   hard-surface SDF sculpting      F = sdf functions of (N, 3) points in a bone's GAME frame (numpy), combined with
#                                   smooth / chamfer unions, intersections and subtractions; sdf_mesh() meshes them with
#                                   naive surface nets + Newton projection onto the zero set (no marching cubes in the venv)
#   wrap_open()                     a body-fitted garment shell whose opening (front gap) varies per ring: open robes
#   orient_out(), thick()           sheet winding away from an axis + solidify with a lining look
#   surf_path()                     points / normals along a (u, v) polyline on a parametric surface
#
# Every SDF primitive takes points q (N, 3) in the frame it was authored in and returns signed distances (m).

import math
import numpy as np
import bmesh
import edlib as ed
from ed import sdf as EDS, model as EDM, cloth as EDC, skin as EDK

TAU = math.pi * 2


# ---- SDF primitives (numpy, vectorised) ------------------------------------------------------------------------------------

def sd_sphere(q, c, r):
    return np.linalg.norm(q - np.asarray(c, float), axis=1) - r


def sd_ell(q, c, r, rot=None):
    """Ellipsoid (approximate distance, exact on the surface). rot: 3x3 whose columns are the ellipsoid axes."""
    p = q - np.asarray(c, float)
    if rot is not None:
        p = p @ np.asarray(rot, float)
    r = np.asarray(r, float)
    k0 = np.linalg.norm(p / r, axis=1)
    k1 = np.linalg.norm(p / (r * r), axis=1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


def sd_capsule(q, a, b, ra, rb=None):
    """Round cone from sphere ra at a to sphere rb at b (exact)."""
    rb = ra if rb is None else rb
    return EDS.sd_round_cone(q, np.asarray(a, float), np.asarray(b, float), ra, rb)


def sd_box(q, c, half, r=0.0, rot=None):
    """Rounded box: centre, half extents, corner radius r (inside the extents). rot: columns = box axes."""
    p = q - np.asarray(c, float)
    if rot is not None:
        p = p @ np.asarray(rot, float)
    d = np.abs(p) - (np.asarray(half, float) - r)
    return np.linalg.norm(np.maximum(d, 0), axis=1) + np.minimum(np.max(d, axis=1), 0) - r


def sd_plane(q, p0, n):
    n = ed.normalize(np.asarray(n, float))
    return (q - np.asarray(p0, float)) @ n


def sd_path(q, pts, r):
    """Tube along a polyline (r: number or per-point radii): min over segments of round cones."""
    pts = np.asarray(pts, float)
    rr = np.broadcast_to(np.asarray(r, float), (len(pts),))
    d = None
    for i in range(len(pts) - 1):
        di = EDS.sd_round_cone(q, pts[i], pts[i + 1], float(rr[i]), float(rr[i + 1]))
        d = di if d is None else np.minimum(d, di)
    return d


def smin(a, b, k):
    return EDS.smin(a, b, k)


def smax(a, b, k):
    return EDS.smax(a, b, k)


def cmin(a, b, k):
    """Chamfer union: a 45 deg bevel of width ~k where the two meet (hard-surface joints that catch light)."""
    return np.minimum(np.minimum(a, b), (a + b - k) * math.sqrt(0.5))


def cmax(a, b, k):
    """Chamfer intersection (a bevelled edge where two planes meet)."""
    return np.maximum(np.maximum(a, b), (a + b + k) * math.sqrt(0.5))


def union(ds, k=0.0):
    out = ds[0]
    for d in ds[1:]:
        out = smin(out, d, k) if k > 0 else np.minimum(out, d)
    return out


# ---- surface nets mesher -----------------------------------------------------------------------------------------------

_CORNERS = np.array([[0, 0, 0], [1, 0, 0], [0, 1, 0], [1, 1, 0], [0, 0, 1], [1, 0, 1], [0, 1, 1], [1, 1, 1]])
_EDGES = [(0, 1), (2, 3), (4, 5), (6, 7), (0, 2), (1, 3), (4, 6), (5, 7), (0, 4), (1, 5), (2, 6), (3, 7)]


def surface_nets(F, origin, h):
    """
    Naive surface nets over a sampled field F (nx, ny, nz) (negative inside) on the grid origin + index * h.
    Returns (V (n, 3), quads (m, 4)) with quads wound so that their normals point outward (toward F > 0).
    """
    nx, ny, nz = F.shape
    inside = F < 0
    # active cells: mixed signs among the 8 corners
    c = [inside[dx:nx - 1 + dx, dy:ny - 1 + dy, dz:nz - 1 + dz] for dx, dy, dz in _CORNERS]
    anyin = np.zeros_like(c[0]); allin = np.ones_like(c[0])
    for a in c:
        anyin |= a; allin &= a
    active = anyin & ~allin
    idx = np.argwhere(active)
    vid = -np.ones(active.shape, dtype=np.int64)
    vid[active] = np.arange(len(idx))
    # vertex: mean of the edge crossings
    acc = np.zeros((len(idx), 3)); cnt = np.zeros(len(idx))
    i, j, k = idx[:, 0], idx[:, 1], idx[:, 2]
    vals = [F[i + dx, j + dy, k + dz] for dx, dy, dz in _CORNERS]
    for a, b in _EDGES:
        fa, fb = vals[a], vals[b]
        m = (fa < 0) != (fb < 0)
        t = fa[m] / (fa[m] - fb[m])
        pa = _CORNERS[a]; pb = _CORNERS[b]
        acc[m] += pa[None, :] + (pb - pa)[None, :] * t[:, None]
        cnt[m] += 1
    V = np.asarray(origin, float) + (idx + acc / np.maximum(cnt, 1)[:, None]) * h
    quads = []
    # edges along x between (i, j, k) and (i+1, j, k): cells (i, j-1, k-1), (i, j, k-1), (i, j, k), (i, j-1, k)
    for axis in range(3):
        sl0 = [slice(None)] * 3; sl1 = [slice(None)] * 3
        sl0[axis] = slice(0, -1); sl1[axis] = slice(1, None)
        a0 = inside[tuple(sl0)]; a1 = inside[tuple(sl1)]
        ch = a0 != a1
        e = np.argwhere(ch)
        u, v = [(1, 2), (2, 0), (0, 1)][axis]
        e = e[(e[:, u] >= 1) & (e[:, v] >= 1)]
        e = e[(e[:, u] <= active.shape[u]) & (e[:, v] <= active.shape[v])]
        if not len(e):
            continue

        def cell(du, dv):
            cc = e.copy()
            cc[:, u] -= du; cc[:, v] -= dv
            ok = (cc[:, u] < active.shape[u]) & (cc[:, v] < active.shape[v]) & (cc[:, axis] < active.shape[axis])
            out = -np.ones(len(cc), dtype=np.int64)
            out[ok] = vid[cc[ok, 0], cc[ok, 1], cc[ok, 2]]
            return out
        q = np.stack([cell(1, 1), cell(0, 1), cell(0, 0), cell(1, 0)], axis=1)
        good = (q >= 0).all(axis=1)
        q = q[good]
        flip = inside[tuple(e[good].T)]          # inside at the lower end: the outward normal points along +axis
        q[flip] = q[flip][:, ::-1]
        quads.append(q)
    Q = np.concatenate(quads) if quads else np.zeros((0, 4), dtype=np.int64)
    return V, Q


def sdf_mesh(name, fn, bmin, bmax, h=0.002, frame=None, rig=None, project=4, smooth=0, coll=None):
    """
    Mesh the zero set of fn (points (N, 3) in a bone's GAME frame -> distances) inside the box bmin..bmax (same frame)
    at cell size h: surface nets, then Newton steps onto the zero set. The mesh is moved into Blender bind space through
    rig.M[frame] (frame = bone name) when given. Returns the object (largest island kept: stray specks are dropped).
    """
    bmin = np.asarray(bmin, float); bmax = np.asarray(bmax, float)
    n = np.maximum(2, np.ceil((bmax - bmin) / h).astype(int) + 1)
    xs = [bmin[a] + np.arange(n[a]) * h for a in range(3)]
    F = np.empty(tuple(n))
    for ii in range(n[0]):                                     # slab by slab (memory)
        G = np.stack(np.meshgrid([xs[0][ii]], xs[1], xs[2], indexing='ij'), axis=-1).reshape(-1, 3)
        F[ii] = fn(G).reshape(n[1], n[2])
    V, Q = surface_nets(F, bmin, h)
    for _ in range(project):
        d = fn(V)
        g = np.zeros_like(V)
        e = h * 0.25
        for a in range(3):
            o = np.zeros(3); o[a] = e
            g[:, a] = (fn(V + o) - fn(V - o)) / (2 * e)
        gg = np.maximum(np.einsum('ij,ij->i', g, g), 1e-8)
        mv = (d / gg)[:, None] * g
        L = np.linalg.norm(mv, axis=1)
        mv *= np.minimum(1.0, h * 0.75 / np.maximum(L, 1e-12))[:, None]
        V = V - mv
    if frame is not None:
        M = rig.M[frame]
        V = V @ M[:3, :3].T + M[:3, 3]
    obj = ed.new_mesh(name, V, Q.tolist(), coll)
    _largest_islands(obj)
    # the nets come out wound inward after the move into bind space: face outward again (else AO bakes black and the
    # object-space normal map is inverted: a dark chrome-looking piece in the engine)
    ed.recalc_normals(obj)
    if smooth:
        EDM.smooth(obj, 0.35, smooth)
    ed.shade(obj)
    return obj


def _largest_islands(obj, min_frac=0.02):
    """Drop islands smaller than min_frac of the vertex count (surface-net specks)."""
    ids = EDK.islands(obj)
    u, cnt = np.unique(ids, return_counts=True)
    dead = np.isin(ids, u[cnt < max(8, min_frac * len(ids))])
    if dead.any():
        bm = bmesh.new(); bm.from_mesh(obj.data); bm.verts.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[bm.verts[int(i)] for i in np.nonzero(dead)[0]], context='VERTS')
        bm.to_mesh(obj.data); bm.free(); obj.data.update()
    return obj


def to_frame(rig, bone, P):
    """Blender world points -> bone game frame."""
    return rig.local(bone, P)


# ---- garments ---------------------------------------------------------------------------------------------------------------

def wrap_open(name, sdf, centers, n, offset, gap, ease=None, rmax=0.45, tension=1.0):
    """
    Like edlib.wrap, but an OPEN garment whose front opening varies per ring: gap(v) -> half opening (0..0.5 of the turn,
    0 = closed) at ring v (0 top .. 1 bottom). Columns run from the hero's front-left edge around the back to the front-right
    edge (u = gap .. 1 - gap). ed_uv: u = absolute turn position (0 front, 0.25 the hero's left, 0.5 back), v down.
    offset / ease: number or fn(u, v) -> metres.
    """
    C = np.asarray(centers, float)
    R = len(C)
    T, Nn, B = EDM.frames_along(C, up=(0, -1, 0))
    rings, us_all = [], []
    A = np.linspace(0, TAU, 128, endpoint=False)
    for j in range(R):
        v = j / max(1, R - 1)
        t = T[j]
        fr = ed.normalize(np.array([0.0, -1.0, 0.0]) - t * np.dot([0.0, -1.0, 0.0], t))
        side = np.cross(t, fr)
        if side[0] < 0:
            side = -side
        rb = EDC.body_radius(sdf, C[j], fr, side, A, rmax=rmax)
        rb = EDC.convexify(rb, A, 60, True, tension)
        g = float(gap(v)) if callable(gap) else float(gap)
        us = g + (1 - 2 * g) * np.arange(n) / (n - 1)
        ang = us * TAU
        r = np.interp(ang % TAU, np.concatenate([A, [TAU]]), np.concatenate([rb, rb[:1]]))
        off = offset(us, np.full(n, v)) if callable(offset) else np.full(n, float(offset))
        r = r + off
        if ease is not None:
            r = r + ease(us, np.full(n, v))
        rings.append(C[j][None, :] + r[:, None] * (np.cos(ang)[:, None] * fr[None, :] + np.sin(ang)[:, None] * side[None, :]))
        us_all.append(us)
    obj = ed.loft(name, np.array(rings), close=False)
    q = ed.get_attr(obj, 'ed_uv').copy()
    q[:, 0] = np.concatenate(us_all)
    ed.set_attr(obj, 'ed_uv', q, 'FLOAT_VECTOR')
    return obj


def orient_out(obj, axis_pts):
    """Make an open sheet's faces point away from its axis polyline (the lining then goes inside)."""
    V, N = ed.verts_of(obj), ed.normals_of(obj)
    k, c, _ = EDK.path_param(V, np.asarray(axis_pts, float))
    if float(np.mean(np.einsum('ij,ij->i', N, V - c))) < 0:
        bm = bmesh.new(); bm.from_mesh(obj.data)
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
        bm.to_mesh(obj.data); bm.free(); obj.data.update()
    return obj


def flip(obj):
    bm = bmesh.new(); bm.from_mesh(obj.data)
    bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    bm.to_mesh(obj.data); bm.free(); obj.data.update()
    return obj


def thick(obj, t, inner=None, offset=-1.0, rim=True):
    """Solidify a sheet (applied); the inner shell takes the `inner` look (lining)."""
    if inner is not None:
        obj.data.materials.append(inner)
    ed.add_mod(obj, 'SOLIDIFY', thickness=t, offset=offset, use_rim=rim, use_even_offset=False, use_quality_normals=True,
               material_offset=1 if inner is not None else 0)
    return ed.apply_mods(obj)


def surf_path(Sf, uv, n=24, lift=0.0):
    """Points + normals along a (u, v) polyline on a parametric surface."""
    UV = ed.polyline(np.array([[u, v, 0.0] for u, v in uv]), n)
    pts, nrm = [], []
    for u, v, _ in UV:
        p, nn, tu, tv = ed.surface_normal(Sf, u, v)
        pts.append(p + nn * lift); nrm.append(nn)
    return np.array(pts), np.array(nrm)


def limb_radius(Ssub, a, b, e1, e2, ts, n=24):
    """Mean body radius around the segment a -> b at parameters ts (for wraps)."""
    A = np.linspace(0, 2 * np.pi, n, endpoint=False)
    return [[t, float(np.mean(ed.body_radius(Ssub, a + (b - a) * t, e1, e2, A, rmax=0.25)))] for t in ts]


def frame_mat(rig, bone):
    """3x3 (columns = the bone's game X, Y, Z axes in Blender space) and origin."""
    M = rig.M[bone]
    return M[:3, :3], M[:3, 3]


def set_glow(obj, inlay=None, vein=None, eye=None):
    """ed_glow per vertex from arrays / numbers (missing channels 0)."""
    n = len(obj.data.vertices)
    g = ed.get_attr(obj, 'ed_glow')
    g = np.zeros((n, 3), dtype=np.float32) if g is None else g.copy()
    for i, x in enumerate((inlay, vein, eye)):
        if x is not None:
            g[:, i] = np.broadcast_to(np.asarray(x, dtype=np.float32), (n,))
    ed.set_attr(obj, 'ed_glow', g, 'FLOAT_VECTOR')
    return obj


def zero_attrs(obj, names=('ed_bakew',)):
    n = len(obj.data.vertices)
    for nm in names:
        if ed.get_attr(obj, nm) is None:
            ed.set_attr(obj, nm, np.zeros(n, dtype=np.float32))
    return obj


def hull2d(P):
    """Convex hull of 2D points (monotone chain), counter-clockwise."""
    P = np.unique(np.round(np.asarray(P, float), 6), axis=0)
    P = P[np.lexsort((P[:, 1], P[:, 0]))]
    if len(P) < 3:
        return P
    cross = lambda o, a, b: (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in P:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(tuple(p))
    for p in P[::-1]:
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(tuple(p))
    return np.array(lower[:-1] + upper[:-1])


def offset_poly(H, d, n=48):
    """Resample a convex polygon to n points and push it out by d (rounded)."""
    H = np.asarray(H, float)
    c = H.mean(0)
    P = ed.polyline(np.hstack([H, np.zeros((len(H), 1))]), n, closed=True)[:, :2]
    return P + ed.normalize(P - c) * d


def clean(obj, dist=1e-6):
    """Merge coincident vertices and dissolve zero-area faces / zero-length edges (no NaN normals in the engine)."""
    bm = bmesh.new(); bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=dist)
    bmesh.ops.dissolve_degenerate(bm, dist=dist, edges=bm.edges[:])
    dead = [f for f in bm.faces if f.calc_area() < 1e-11]
    if dead:
        bmesh.ops.delete(bm, geom=dead, context='FACES')
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context='VERTS')
    bm.to_mesh(obj.data); bm.free(); obj.data.update()
    return obj


def vein_patches(obj, base=0.6, hot=1.0, f=9.0, seed=3, lo=0.58, hi=0.88):
    """Per-vertex `vein` glow mask in hot patches (the kit's veins()): the set's crack glow shows only where the metal is
    still hot, a faint trace elsewhere."""
    P = ed.verts_of(obj)
    n = EDM.fbm(P * f, octaves=2, seed=seed) * 0.5 + 0.5
    m = base * (0.04 + 0.96 * ed.smoothstep(lo, hi, n)) * hot
    return set_glow(obj, vein=m)


def crack_paths(obj, n=10, seed=1, step=0.004, length=(10, 26), select=None, branch=0.25):
    """Random-walk crack lines on a mesh surface (lists of (k, 3) points): each starts at a random vertex (filtered by
    select(P, N) -> bool mask), walks along the surface with a wandering heading, sometimes branches."""
    from mathutils.kdtree import KDTree
    from mathutils import Vector
    rng = np.random.RandomState(seed)
    V, Nn = ed.verts_of(obj), ed.normals_of(obj)
    kd = KDTree(len(V))
    for i, p in enumerate(V):
        kd.insert(Vector(p), i)
    kd.balance()
    cand = np.arange(len(V)) if select is None else np.nonzero(select(V, Nn))[0]
    out = []
    starts = list(rng.choice(cand, size=min(n, len(cand)), replace=False))
    queue = [(V[i], None, rng.randint(*length)) for i in starts]
    while queue:
        p, head, L = queue.pop(0)
        co, i, _ = kd.find(Vector(p))
        nrm = Nn[i]
        if head is None:
            t = ed.normalize(np.cross(nrm, rng.normal(size=3)))
        else:
            t = head
        pts = [np.array(co)]
        for k in range(L):
            t = ed.normalize(t - nrm * np.dot(t, nrm) + np.cross(nrm, t) * rng.normal(0, 0.45))
            q = pts[-1] + t * step * rng.uniform(0.7, 1.3)
            co, i, _ = kd.find(Vector(q))
            nrm = Nn[i]
            pts.append(np.array(co))
            if rng.rand() < branch / L * 3 and len(out) < n * 3:
                queue.append((np.array(co), ed.normalize(np.cross(nrm, t) * rng.choice([-1, 1]) + t), int(L * 0.5)))
        out.append(np.array(pts))
    return out


def dist_to_paths(P, paths):
    best = np.full(len(P), 1e9)
    for path in paths:
        for a, b in zip(path[:-1], path[1:]):
            ab = b - a; L2 = float(ab @ ab) or 1e-12
            t = np.clip(((P - a) @ ab) / L2, 0, 1)
            best = np.minimum(best, np.linalg.norm(P - (a + t[:, None] * ab), axis=1))
    return best


def hammer(obj, amount=0.0004, scale=180.0, seed=3):
    """Hammer marks: shallow cellular dents over a forged surface (bake source)."""
    P, Nn = ed.verts_of(obj), ed.normals_of(obj)
    d = EDM.fbm(P * scale, octaves=2, seed=seed)
    ed.set_verts(obj, P - Nn * (np.abs(d) * amount)[:, None])
    return obj


def bake_maps_clean(high, low, **kw):
    """ed.bake_object_maps with the low-poly target hidden from diffuse / shadow / glossy rays while baking: otherwise the
    AO rays cast from the high-poly surface hit the coincident low-poly shell at once and the AO channel bakes black
    (a dark, chrome-looking piece in the engine). Candidate for edlib (reported, not edited: shared library)."""
    flags = ('visible_diffuse', 'visible_glossy', 'visible_shadow', 'visible_transmission', 'visible_volume_scatter')
    saved = {f: getattr(low, f) for f in flags}
    for f in flags:
        setattr(low, f, False)
    try:
        recs = ed.bake_object_maps(high, low, **kw)
    finally:
        for f, v in saved.items():
            setattr(low, f, v)
    return recs
