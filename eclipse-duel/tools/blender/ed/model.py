# edlib modelling helpers: lofts / lathes / sweeps from profile curves, ribbons, solidify + bevel, displacement (folds,
# wrinkles), booleans / engraving, and the pattern generators of this art style: braids, woven bamboo, lamellar rows with
# lacing, helical wraps, knots, tassels. Everything returns ordinary mesh objects (Blender space, identity transforms).

import bpy
import bmesh
import math
import numpy as np
from mathutils import Vector
from .core import (new_mesh, verts_of, set_verts, normals_of, faces_of, add_mod, apply_mods, select, join, delete, shade, set_attr, get_attr,
                   normalize, smoothstep, lerp, curve_fn, catmull, polyline, duplicate, recalc_normals, log)

TAU = math.pi * 2


# ---- noise (vectorised, deterministic) ------------------------------------------------------------------------------------

def _hash3(i, j, k, seed):
    h = (i * 374761393 + j * 668265263 + k * 2147483647 + seed * 1274126177) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFFFF) / float(0xFFFFFF)


def vnoise(P, seed=0):
    """Smooth value noise in [-1, 1] at points P ((N, 3)); period-free, deterministic."""
    P = np.asarray(P, dtype=np.float64)
    i = np.floor(P).astype(np.int64); f = P - i
    u = f * f * (3 - 2 * f)
    out = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (u[:, 0] if dx else 1 - u[:, 0]) * (u[:, 1] if dy else 1 - u[:, 1]) * (u[:, 2] if dz else 1 - u[:, 2])
                out = out + w * _hash3(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz, seed)
    return out * 2 - 1


def fbm(P, octaves=4, lacunarity=2.0, gain=0.5, seed=0):
    """Fractal value noise, roughly in [-1, 1]."""
    P = np.asarray(P, dtype=np.float64)
    a, s, out, f = 1.0, 0.0, 0.0, 1.0
    for o in range(octaves):
        out = out + a * vnoise(P * f + 17.3 * o, seed + o)
        s += a; a *= gain; f *= lacunarity
    return out / s


# ---- grids, lofts, lathes, sweeps --------------------------------------------------------------------------------------------

def grid_faces(nu, nv, close_u=False, close_v=False, flip=False, offset=0):
    """Quad faces of an (nv rows x nu columns) vertex grid stored row-major (index = j * nu + i)."""
    faces = []
    for j in range(nv if close_v else nv - 1):
        j1 = (j + 1) % nv
        for i in range(nu if close_u else nu - 1):
            i1 = (i + 1) % nu
            a, b, c, d = j * nu + i, j * nu + i1, j1 * nu + i1, j1 * nu + i
            faces.append((a + offset, d + offset, c + offset, b + offset) if flip else (a + offset, b + offset, c + offset, d + offset))
    return faces


def loft(name, rings, close=True, caps=(False, False), flip=False, coll=None, uv=True):
    """
    Skin a stack of rings ((R, N, 3): R rings of N points each) with quads. close: rings are closed loops.
    caps: n-gon caps on the first / last ring. Stores the grid parameters as the POINT attribute `ed_uv` (u around 0..1,
    v along 0..1) and obj['ed_grid'] = [N, R] (pattern generators, panel binding and UVs use them).
    """
    rings = np.asarray(rings, dtype=np.float64)
    R, N = rings.shape[0], rings.shape[1]
    V = rings.reshape(-1, 3)
    F = grid_faces(N, R, close_u=close, flip=flip)
    if caps[0]:
        F.append(tuple(range(N)) if flip else tuple(reversed(range(N))))
    if caps[1]:
        b = (R - 1) * N
        F.append(tuple(reversed(range(b, b + N))) if flip else tuple(range(b, b + N)))
    obj = new_mesh(name, V, F, coll)
    obj['ed_grid'] = [N, R]
    if uv:
        u = np.tile(np.arange(N) / (N if close else max(1, N - 1)), R)
        v = np.repeat(np.arange(R) / max(1, R - 1), N)
        set_attr(obj, 'ed_uv', np.stack([u, v, np.zeros_like(u)], axis=1), 'FLOAT_VECTOR')
    return obj


def ellipse_ring(center, ax, az, rx, rz, n=16, power=2.0, phase=0.0, bumps=None):
    """
    One closed ring: superellipse in the plane spanned by unit vectors ax / az around `center`. power 2 = ellipse,
    larger = boxier. bumps: fn(theta) -> radial scale added to 1 (muscle bellies, ridges). theta 0 = +ax, pi/2 = +az.
    """
    th = phase + np.arange(n) / n * TAU
    c, s = np.cos(th), np.sin(th)
    e = 2.0 / power
    x = np.sign(c) * np.abs(c) ** e * rx
    z = np.sign(s) * np.abs(s) ** e * rz
    if bumps is not None:
        k = 1.0 + bumps(th)
        x, z = x * k, z * k
    return np.asarray(center)[None, :] + x[:, None] * np.asarray(ax)[None, :] + z[:, None] * np.asarray(az)[None, :]


def frames_along(path, up=None):
    """
    Rotation-minimising frames along a polyline ((n, 3)): returns (T, N, B) unit vectors per point. `up` fixes the first
    normal (default: the axis least aligned with the first tangent).
    """
    P = np.asarray(path, dtype=np.float64)
    n = len(P)
    T = np.zeros_like(P)
    T[1:-1] = P[2:] - P[:-2]; T[0] = P[1] - P[0]; T[-1] = P[-1] - P[-2]
    T = normalize(T)
    if up is None:
        up = np.eye(3)[np.argmin(np.abs(T[0]))]
    N0 = np.asarray(up, dtype=np.float64) - T[0] * np.dot(up, T[0])
    N0 = normalize(N0)
    Ns = [N0]
    for i in range(1, n):
        v = np.cross(T[i - 1], T[i]); s = np.linalg.norm(v); c = float(np.dot(T[i - 1], T[i]))
        Nn = Ns[-1]
        if s > 1e-9:
            ax = v / s; ang = math.atan2(s, c)
            Nn = Nn * math.cos(ang) + np.cross(ax, Nn) * math.sin(ang) + ax * np.dot(ax, Nn) * (1 - math.cos(ang))
        Nn = normalize(Nn - T[i] * np.dot(Nn, T[i]))
        Ns.append(Nn)
    Nv = np.array(Ns)
    return T, Nv, np.cross(T, Nv)


def sweep(name, path, section=8, radius=0.01, scale_y=1.0, twist=None, up=None, caps=True, close=True, coll=None):
    """
    Sweep a section along a path ((n, 3)). section: an int (regular polygon with that many sides) or an (m, 2) outline
    (x along the frame normal, y along the binormal). radius: number, [[t, r], ...] or fn(t) over t = 0..1 along the path.
    scale_y flattens the section (ribbons, straps), twist: fn(t) radians.
    """
    P = np.asarray(path, dtype=np.float64)
    T, N, B = frames_along(P, up)
    if isinstance(section, int):
        a = np.arange(section) / section * TAU
        sec = np.stack([np.cos(a), np.sin(a)], axis=1)
    else:
        sec = np.asarray(section, dtype=np.float64)
    n = len(P)
    t = np.linspace(0, 1, n)
    r = curve_fn(radius)(t) * np.ones(n)
    tw = (twist(t) if twist else np.zeros(n)) * np.ones(n)
    sy = curve_fn(scale_y)(t) * np.ones(n)
    rings = np.zeros((n, len(sec), 3))
    for i in range(n):
        c, s = math.cos(tw[i]), math.sin(tw[i])
        nn, bb = N[i] * c + B[i] * s, B[i] * c - N[i] * s
        rings[i] = P[i] + r[i] * (sec[:, :1] * nn + sec[:, 1:2] * sy[i] * bb)
    return loft(name, rings, close=close, caps=(caps, caps) if close else (False, False), coll=coll)


def tube(name, path, radius=0.01, sides=8, caps=True, coll=None):
    """Round tube along a path (cords, stems, hafts)."""
    return sweep(name, path, sides, radius, caps=caps, coll=coll)


def lathe(name, profile, segs=24, origin=(0, 0, 0), axis=(0, 0, 1), a0=0.0, a1=360.0, caps=(False, False), coll=None):
    """
    Surface of revolution: profile [[r, h], ...] (radius, height along `axis` from `origin`), listed along the profile.
    Hafts, knobs, pommels, gourds, hat cones. a0 / a1 in degrees (a partial lathe is open).
    """
    prof = np.asarray(profile, dtype=np.float64)
    ax = normalize(np.asarray(axis, dtype=np.float64))
    ref = np.eye(3)[np.argmin(np.abs(ax))]
    e1 = normalize(np.cross(ax, ref)); e2 = np.cross(ax, e1)
    full = abs((a1 - a0) - 360.0) < 1e-6
    n = segs if full else segs + 1
    ang = np.radians(a0) + np.arange(n) / segs * np.radians(a1 - a0)
    rings = np.zeros((len(prof), n, 3))
    for j, (r, h) in enumerate(prof):
        rings[j] = np.asarray(origin) + ax * h + r * (np.cos(ang)[:, None] * e1 + np.sin(ang)[:, None] * e2)
    return loft(name, rings, close=full, caps=caps, coll=coll)


def ribbon(name, path, width=0.02, normal=None, camber=0.0, nu=2, thickness=0.0, coll=None, uv_scale=(1.0, 1.0), code=0.0):
    """
    Flat strip along a path: hair cards, sash ends, bandage tails, lacing. width: number / curve over t. `normal` is the
    facing direction (one vector or per point); camber bows the strip across its width (fraction of the width).
    Writes ed_uvw = (u across * uv_scale[0], v along * uv_scale[1], code) for the UV texture sets (hair ...).
    """
    P = np.asarray(path, dtype=np.float64)
    n = len(P)
    T = np.zeros_like(P); T[1:-1] = P[2:] - P[:-2]; T[0] = P[1] - P[0]; T[-1] = P[-1] - P[-2]; T = normalize(T)
    if normal is None:
        _, Nn, _ = frames_along(P)
    else:
        Nn = np.broadcast_to(np.asarray(normal, dtype=np.float64), P.shape).copy()
        Nn = normalize(Nn - T * np.sum(Nn * T, axis=1, keepdims=True))
    S = np.cross(T, Nn)
    t = np.linspace(0, 1, n)
    w = curve_fn(width)(t) * np.ones(n)
    cols = nu + 1
    rings = np.zeros((n, cols, 3))
    for i in range(cols):
        a = i / nu - 0.5
        rings[:, i] = P + S * (w * a)[:, None] + Nn * (w * camber * (1 - 4 * a * a))[:, None]
    obj = loft(name, rings, close=False, coll=coll)
    u = np.tile(np.arange(cols) / nu, n) * uv_scale[0]
    v = np.repeat(t, cols) * uv_scale[1]
    set_attr(obj, 'ed_uvw', np.stack([u, v, np.full_like(u, code)], axis=1), 'FLOAT_VECTOR')
    if thickness > 0:
        solidify(obj, thickness, offset=0)
    return obj


def ellipsoid(name, center, radii, rot=None, segs=(16, 10), coll=None):
    """UV ellipsoid (muscle masses, heads, beads). rot: 3x3 matrix whose columns are the ellipsoid axes."""
    nu, nv = segs
    rot = np.eye(3) if rot is None else np.asarray(rot, dtype=np.float64)
    V = [np.array([0, 0, 1.0])]
    for j in range(1, nv):
        ph = math.pi * j / nv
        for i in range(nu):
            th = TAU * i / nu
            V.append([math.sin(ph) * math.cos(th), math.sin(ph) * math.sin(th), math.cos(ph)])
    V.append([0, 0, -1.0])
    V = np.array(V) * np.asarray(radii)
    V = V @ rot.T + np.asarray(center)
    F = []
    for i in range(nu):
        F.append((0, 1 + i, 1 + (i + 1) % nu))
    for j in range(nv - 2):
        for i in range(nu):
            a = 1 + j * nu + i; b = 1 + j * nu + (i + 1) % nu
            F.append((a, a + nu, b + nu, b))
    last = len(V) - 1; base = 1 + (nv - 2) * nu
    for i in range(nu):
        F.append((last, base + (i + 1) % nu, base + i))
    return new_mesh(name, V, F, coll)


def capsule(name, a, b, ra, rb=None, segs=12, coll=None):
    """Capsule / tapered limb segment between two points (rb defaults to ra)."""
    a = np.asarray(a, dtype=np.float64); b = np.asarray(b, dtype=np.float64)
    rb = ra if rb is None else rb
    d = b - a; L = np.linalg.norm(d); ax = d / max(L, 1e-9)
    prof = []
    for k in range(5):
        ph = math.pi / 2 * (1 - k / 4)
        prof.append([ra * math.cos(ph) if k else 1e-5, -ra * math.sin(ph)])
    for k in range(5):
        ph = math.pi / 2 * (k / 4)
        prof.append([rb * math.cos(ph) if k < 4 else 1e-5, L + rb * math.sin(ph)])
    return lathe(name, prof, segs, origin=a, axis=ax, coll=coll)


def box(name, size=(0.1, 0.1, 0.1), center=(0, 0, 0), bevel_w=0.0, segs=2, coll=None):
    """Box with optional bevelled edges."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0] + center[0], v.co.y * size[1] + center[1], v.co.z * size[2] + center[2]))
    if bevel_w > 0:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel_w, segments=segs, profile=0.5, affect='EDGES')
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    obj = bpy.data.objects.new(name, me)
    from .core import link
    link(obj, coll)
    shade(obj, 35)
    return obj


# ---- edges, thickness, subdivision ------------------------------------------------------------------------------------------

def solidify(obj, thickness=0.004, offset=-1.0, rim=True, even=False):
    """Give a sheet thickness (applied). offset -1 grows inward, +1 outward, 0 both ways. even=True (even thickness)
    throws long spikes out of the sharp folds of draped cloth: keep it off for cloth."""
    add_mod(obj, 'SOLIDIFY', thickness=thickness, offset=offset, use_rim=rim, use_even_offset=even)
    return apply_mods(obj)


def bevel(obj, width=0.002, segments=2, angle=30.0, harden=True):
    """Bevel the sharp edges (angle limit, degrees): every hard edge catches a highlight."""
    m = add_mod(obj, 'BEVEL', width=width, segments=segments, limit_method='ANGLE', angle_limit=math.radians(angle))
    if hasattr(m, 'harden_normals'):
        m.harden_normals = harden
    return apply_mods(obj)


def subdivide(obj, levels=1, simple=False):
    """Catmull-Clark (or simple) subdivision, applied."""
    add_mod(obj, 'SUBSURF', levels=levels, render_levels=levels, subdivision_type='SIMPLE' if simple else 'CATMULL_CLARK')
    return apply_mods(obj)


def smooth(obj, factor=0.5, iterations=4, mask=None):
    """Laplacian-style smoothing of the vertices (optional (N,) weight mask), keeps the vertex count."""
    if mask is not None:
        g = obj.vertex_groups.new(name='_smooth')
        for i in np.nonzero(np.asarray(mask) > 1e-4)[0]:
            g.add([int(i)], float(mask[i]), 'REPLACE')
        m = add_mod(obj, 'SMOOTH', factor=factor, iterations=iterations)
        m.vertex_group = '_smooth'
        apply_mods(obj)
        obj.vertex_groups.remove(obj.vertex_groups['_smooth'])
        return obj
    add_mod(obj, 'SMOOTH', factor=factor, iterations=iterations)
    return apply_mods(obj)


def displace(obj, fn, strength=1.0, direction=None):
    """
    Move every vertex along its normal (or a fixed `direction`) by strength * fn(P, N) (vectorised: P, N are (n, 3)).
    The workhorse for folds, wrinkles, weave relief and engraving.
    """
    P, N = verts_of(obj), normals_of(obj)
    d = np.asarray(fn(P, N), dtype=np.float64) * strength
    D = N if direction is None else np.broadcast_to(np.asarray(direction, dtype=np.float64), P.shape)
    set_verts(obj, P + D * d[:, None])
    return obj


def wrinkle(obj, amount=0.004, scale=18.0, stretch=(1.0, 1.0, 0.25), seed=1, mask=None, octaves=3, ridged=True, along=None):
    """
    Cloth fold / wrinkle displacement: ridged fractal noise, stretched so the folds run along `along` (default: vertical).
    amount: metres peak, scale: folds per metre across, stretch: frequency multipliers (x, y, z) when `along` is None,
    mask: (N,) weights or fn(P) -> weights (where the cloth bunches: elbows, waist, behind the knee).
    """
    P = verts_of(obj)
    if along is not None:
        a = normalize(np.asarray(along, dtype=np.float64))
        ref = np.eye(3)[np.argmin(np.abs(a))]
        e1 = normalize(np.cross(a, ref)); e2 = np.cross(a, e1)
        Q = np.stack([P @ e1, P @ e2, (P @ a) * 0.25], axis=1) * scale
    else:
        Q = P * scale * np.asarray(stretch)
    n = fbm(Q, octaves=octaves, seed=seed)
    if ridged:
        n = 1.0 - 2.0 * np.abs(n)                      # sharp creases between soft pillows
    w = 1.0 if mask is None else (mask(P) if callable(mask) else np.asarray(mask))
    N = normals_of(obj)
    set_verts(obj, P + N * (n * amount * w)[:, None])
    return obj


def boolean(obj, cutter, op='DIFFERENCE', keep_cutter=False, solver='EXACT'):
    """Boolean with another mesh object (engraved channels, lacing holes, cut-outs)."""
    m = add_mod(obj, 'BOOLEAN', operation=op, object=cutter)
    try:
        m.solver = solver
    except Exception:
        pass
    apply_mods(obj)
    if not keep_cutter:
        delete(cutter)
    return obj


def engrave(obj, paths, width=0.003, depth=0.0015, falloff=1.5):
    """
    Engraving by displacement: sink the surface along polylines (list of (k, 3) arrays near the surface). The mesh must be
    dense enough to hold the line (subdivide first; meant for high-poly bake sources and dense hero pieces).
    Also darkens ed_cav inside the groove. Returns the per-vertex groove mask (0..1).
    """
    P, N = verts_of(obj), normals_of(obj)
    best = np.full(len(P), 1e9)
    for path in paths:
        Q = np.asarray(path, dtype=np.float64)
        for a, b in zip(Q[:-1], Q[1:]):
            ab = b - a; L2 = float(ab @ ab) or 1e-12
            t = np.clip(((P - a) @ ab) / L2, 0, 1)
            d = np.linalg.norm(P - (a + t[:, None] * ab), axis=1)
            best = np.minimum(best, d)
    m = 1.0 - smoothstep(width * 0.5, width * 0.5 * falloff, best)
    set_verts(obj, P - N * (m * depth)[:, None])
    cav = get_attr(obj, 'ed_cav')
    if cav is not None:
        set_attr(obj, 'ed_cav', np.minimum(cav, 1.0 - 0.55 * m))
    return m


# ---- surfaces for pattern generators ------------------------------------------------------------------------------------------

def surface_normal(S, u, v, eps=1e-3):
    """Numeric normal of a parametric surface S(u, v) -> (3,) (u across, v along)."""
    p = np.asarray(S(u, v)); du = np.asarray(S(u + eps, v)) - np.asarray(S(u - eps, v)); dv = np.asarray(S(u, v + eps)) - np.asarray(S(u, v - eps))
    n = np.cross(du, dv)
    if getattr(S, 'flip', False):        # grid_surface(): keep the normal outward whatever the parameter orientation
        n = -n
    return p, normalize(n), normalize(du), normalize(dv)


def cone_surface(apex, axis, radius, height, bell=1.0, v0=0.03):
    """Parametric cone (hats): S(u, v), u around 0..1, v from the apex (0) to the brim (1); bell < 1 swells the profile."""
    apex = np.asarray(apex, dtype=np.float64); ax = normalize(np.asarray(axis, dtype=np.float64))
    ref = np.eye(3)[np.argmin(np.abs(ax))]
    e1 = normalize(np.cross(ax, ref)); e2 = np.cross(ax, e1)

    def S(u, v):
        s = v0 + (1 - v0) * v
        r = radius * s
        h = height * (s ** bell)
        a = u * TAU
        return apex - ax * h + r * (math.cos(a) * e1 + math.sin(a) * e2)
    return S


# ---- pattern generators -----------------------------------------------------------------------------------------------------

def weave(name, S, nu, nv, width_u=None, width_v=None, thick=0.0012, lift=0.0016, pattern=(2, 2), sub=3, u_range=(0, 1), v_range=(0, 1),
          close_u=True, across=3, coll=None):
    """
    REAL woven strips over a parametric surface S(u, v): nu strips run along v (the "stakes" / radial splits of a hat),
    nv strips run along u (the weavers), interlaced over / under in a twill `pattern` (over, under). Every strip is its own
    thin band that rises and dips where it crosses the others. This is a high-poly bake source or a dense hero mesh
    (about nu * nv * sub^2 * 8 triangles); for a game mesh bake it down (bake_maps) or use weave_relief().
    width_u / width_v: strip widths as a fraction of the pitch (default 0.86).
    across: quads across each strip (3: crowned with bevelled edges, 2: crowned, lighter).
    Returns the object; ed_cav darkens the gaps, ed_col alternates slightly per strip.
    """
    wu = 0.86 if width_u is None else width_u
    wv = 0.86 if width_v is None else width_v
    over, under = pattern
    period = over + under
    V, F, CAV, COL = [], [], [], []
    rng = np.random.RandomState(7)

    def phase(i, j):   # +1: the u-running strip (weaver j) is on top at crossing (i, j)
        return 1.0 if ((i + j) % period) < over else -1.0

    def add_strip(pts, nrm, side, hw, h, tone):
        # pts (m, 3) centre line, nrm normals, side = across direction, hw half width (m,), h height offsets (m,)
        m = len(pts)
        base = len(V)
        for k in range(m):
            c = pts[k] + nrm[k] * h[k]
            prof = ((-1.0, 0.0), (-0.45, 0.45 * thick), (0.45, 0.45 * thick), (1.0, 0.0)) if across >= 3 else ((-1.0, 0.0), (0.0, 0.6 * thick), (1.0, 0.0))
            for a, crown in prof:
                V.append(c + side[k] * hw[k] * a + nrm[k] * (crown + thick * 0.5))
                CAV.append(1.0 if abs(a) < 1 else 0.72)
                COL.append(tone)
        w = 4 if across >= 3 else 3
        for k in range(m - 1):
            for a in range(w - 1):
                p = base + k * w + a
                F.append((p, p + 1, p + w + 1, p + w))

    du = (u_range[1] - u_range[0]) / nu
    dv = (v_range[1] - v_range[0]) / nv
    # strips along v (index i), sampled sub times per crossing
    for i in range(nu):
        u = u_range[0] + (i + 0.5) * du
        m = nv * sub + 1
        pts, nrm, side, hw, h = [], [], [], [], []
        for k in range(m):
            v = v_range[0] + k / (m - 1) * (v_range[1] - v_range[0])
            p, n, tu, tv = surface_normal(S, u, v)
            jf = k / sub - 0.5
            j0 = int(math.floor(jf)); f = jf - j0
            a = -phase(i, j0) if 0 <= j0 < nv else 0.0
            b = -phase(i, j0 + 1) if 0 <= j0 + 1 < nv else 0.0
            s = f * f * (3 - 2 * f)
            pitch_u = np.linalg.norm(np.asarray(S(u + du * 0.5, v)) - np.asarray(S(u - du * 0.5, v)))
            pts.append(p); nrm.append(n); side.append(tu); hw.append(0.5 * wu * pitch_u); h.append(lift * (a + (b - a) * s))
        add_strip(np.array(pts), np.array(nrm), np.array(side), np.array(hw), np.array(h), 0.92 + 0.16 * rng.rand())
    # strips along u (index j)
    for j in range(nv):
        v = v_range[0] + (j + 0.5) * dv
        m = nu * sub + 1
        pts, nrm, side, hw, h = [], [], [], [], []
        for k in range(m):
            u = u_range[0] + k / (m - 1) * (u_range[1] - u_range[0])
            p, n, tu, tv = surface_normal(S, u, v)
            jf = k / sub - 0.5
            i0 = int(math.floor(jf)); f = jf - i0
            if close_u:
                a = phase(i0 % nu, j); b = phase((i0 + 1) % nu, j)
            else:
                a = phase(i0, j) if 0 <= i0 < nu else 0.0
                b = phase(i0 + 1, j) if 0 <= i0 + 1 < nu else 0.0
            s = f * f * (3 - 2 * f)
            pitch_v = np.linalg.norm(np.asarray(S(u, v + dv * 0.5)) - np.asarray(S(u, v - dv * 0.5)))
            pts.append(p); nrm.append(n); side.append(tv); hw.append(0.5 * wv * pitch_v); h.append(lift * (a + (b - a) * s))
        add_strip(np.array(pts), np.array(nrm), np.array(side), np.array(hw), np.array(h), 0.8 + 0.16 * rng.rand())
    obj = new_mesh(name, np.array(V), F, coll)
    recalc_normals(obj)
    set_attr(obj, 'ed_cav', np.array(CAV, dtype=np.float32))
    c = np.array(COL, dtype=np.float32)
    set_attr(obj, 'ed_col', np.stack([c, c, c, np.ones_like(c)], axis=1), 'FLOAT_COLOR')
    return obj


def weave_relief(obj, nu, nv, amount=0.0012, pattern=(2, 2), uv='ed_uv'):
    """
    Game-resolution weave: displace a lofted surface (its ed_uv grid parameters) with the over / under relief of nu x nv
    strips and write the gaps into ed_cav and a strip tone into ed_col. The mesh should have >= 2 vertices per strip in
    the direction that must read; combine it with the `bamboo` / `hemp` texture set for the fine plait.
    """
    q = get_attr(obj, uv)
    u, v = q[:, 0] * nu, q[:, 1] * nv
    over, under = pattern; period = over + under
    iu, iv = np.floor(u).astype(int), np.floor(v).astype(int)
    fu, fv = u - iu, v - iv
    top = (((iu + iv) % period) < over).astype(np.float64) * 2 - 1      # +1: the strip running along u is on top
    bump_u = np.sin(fu * math.pi) ** 0.6                                  # cross-section of a strip running along v
    bump_v = np.sin(fv * math.pi) ** 0.6
    h = np.where(top > 0, bump_v, bump_u) * (0.55 + 0.45 * np.sin(fu * math.pi) * np.sin(fv * math.pi))
    gap = np.minimum(np.sin(fu * math.pi), np.sin(fv * math.pi))
    displace(obj, lambda P, N: h - 0.5, amount)
    cav = get_attr(obj, 'ed_cav', np.ones(len(u), dtype=np.float32))
    set_attr(obj, 'ed_cav', (cav * (0.55 + 0.45 * smoothstep(0.0, 0.35, gap))).astype(np.float32))
    tone = 0.86 + 0.14 * np.where(top > 0, np.sin(iv * 12.9898) * 0.5 + 0.5, np.sin(iu * 78.233) * 0.5 + 0.5)
    col = get_attr(obj, 'ed_col', np.ones((len(u), 4), dtype=np.float32)).copy()
    col[:, :3] *= tone[:, None]
    set_attr(obj, 'ed_col', col, 'FLOAT_COLOR')
    return obj


def lamellar(name, S, rows, cols, plate_w=0.024, plate_h=0.05, thick=0.0026, overlap=0.32, row_overlap=0.3, dome=0.0016, u_range=(0, 1), v_range=(0, 1),
             lace=True, lace_r=0.0011, stagger=True, tilt=0.12, seed=3, closed=False, lod=1, coll=None):
    """
    Lamellar (찰갑) armour: `rows` rows of `cols` small plates laid on a parametric surface S(u, v) (u across, v DOWN the
    piece). Plates overlap sideways (each over its right neighbour) and every row overlaps the row below; each plate is a
    rounded, slightly domed lame with a bevelled rim (28 triangles). lace: the suspension lacing, two cords per plate
    column knotted between rows, and a horizontal binding cord per row.
    Returns (plates, lacing) objects; per-vertex ed_cav carries the overlap shadows, ed_col a per-plate tone.
    obj['ed_cells'] on the plates = [rows, cols] (bind rows to bones with skin.by_rows(), or skin.rigid_islands()).
    closed: S is periodic in u (a full cuirass): plates wrap around the seam instead of clamping to it.
    lod: 1 = rounded 9-point plates (~37 triangles + 36 per lace pair), 0 = 7-point plates and flat stitches (~27 + 8):
    the game mesh of a full cuirass.
    """
    rng = np.random.RandomState(seed)
    V, F, CAV, COL, ROW = [], [], [], [], []
    LV, LF = [], []
    du = (u_range[1] - u_range[0]) / cols
    dv = (v_range[1] - v_range[0]) / rows
    # plate outline (x across -1..1, y down 0..1): rounded top corners, scalloped bottom
    outline = np.array([[-1, 0.06], [-0.78, 0.0], [0.78, 0.0], [1, 0.06], [1, 0.82], [0.62, 0.97], [0, 1.0], [-0.62, 0.97], [-1, 0.82]])
    if lod < 1:
        outline = np.array([[-1, 0.0], [1, 0.0], [1, 0.82], [0.58, 0.97], [0, 1.0], [-0.58, 0.97], [-1, 0.82]])
    rim0 = 2 if lod < 1 else 3
    inner = outline * np.array([0.72, 1]) * np.array([1, 0.84]) + np.array([0, 0.07])
    for r in range(rows):
        v_top = v_range[0] + r * dv
        for c in range(cols):
            u = u_range[0] + (c + 0.5 + (0.5 if (stagger and r % 2) else 0.0)) * du
            if u > u_range[1] + 1e-9 and not stagger:
                continue
            if closed:
                u = u % 1.0
            uc = u if closed else min(max(u, u_range[0] + 1e-4), u_range[1] - 1e-4)
            p0, n0, tu, tv = surface_normal(S, uc, v_top + dv * 0.5)
            ua, ub = (u + du * 0.5, u - du * 0.5) if closed else (min(u + du * 0.5, 1.0), max(u - du * 0.5, 0.0))
            pitch_u = np.linalg.norm(np.asarray(S(ua, v_top + dv * 0.5)) - np.asarray(S(ub, v_top + dv * 0.5)))
            pitch_v = np.linalg.norm(np.asarray(S(u, min(v_top + dv, 1.0))) - np.asarray(S(u, max(v_top, 0.0))))
            hw = 0.5 * pitch_u * (1 + overlap)
            hh = pitch_v * (1 + row_overlap)
            top, _, _, _ = surface_normal(S, uc, v_top)
            tone = 0.82 + 0.3 * rng.rand()
            # the plate tilts: its lower edge rides on the row below, one side rides on its neighbour
            base = len(V)
            for ring, zo, cv in ((outline, 0.0, 0.55), (inner, 1.0, 1.25)):
                for (x, y) in ring:
                    lift_row = thick * (0.35 + 1.25 * y)                       # lower end lifted over the next row
                    lift_side = thick * 0.9 * (0.5 + 0.5 * x) * tilt / 0.12     # right side over the neighbour
                    d = dome * (1 - x * x) * zo
                    P = top + tu * (x * hw) + tv * (y * hh) + n0 * (lift_row + lift_side + d + thick * zo)
                    V.append(P); CAV.append(cv if zo else 0.55 + 0.3 * y); COL.append(tone); ROW.append(r)
            k = len(outline)
            for i in range(k):
                j = (i + 1) % k
                F.append((base + i, base + j, base + k + j, base + k + i))
            F.append(tuple(base + k + i for i in range(k)))
            # back rim down to the surface (only the visible lower part)
            for i in range(k):
                x, y = outline[i]
                V.append(top + tu * (x * hw) + tv * (y * hh) + n0 * (thick * 0.2 * y)); CAV.append(0.45); COL.append(tone * 0.8); ROW.append(r)
            b2 = base + 2 * k
            for i in range(rim0, k):
                j = (i + 1) % k
                if j < rim0:
                    continue
                F.append((b2 + i, b2 + j, base + j, base + i))
            if lace:
                # two vertical lace stitches on the upper third of the plate + they continue to the plate above
                for sx in (-0.34, 0.34):
                    a = top + tu * (sx * hw) + tv * (0.16 * hh) + n0 * (thick * 1.9 + dome)
                    b = top + tu * (sx * hw) + tv * (0.42 * hh) + n0 * (thick * 2.3 + dome)
                    _stitch(LV, LF, a, b, n0, tu, lace_r, flat=lod < 1)
        if lace:
            # horizontal binding cord across the row
            pts = []
            per = 2 if lod >= 1 else 1
            for k2 in range(cols * per + 1):
                u = u_range[0] + k2 / (cols * per) * (u_range[1] - u_range[0])
                p, n, tu2, tv2 = surface_normal(S, u if closed else min(max(u, u_range[0] + 1e-4), u_range[1] - 1e-4), v_top + dv * 0.62)
                pts.append(p + n * (thick * 3.0 + dome + lace_r * (1.0 + 0.6 * math.sin(k2 * math.pi))))
            _cord(LV, LF, np.array(pts), lace_r * 1.15, 5 if lod >= 1 else 4)
    plates = new_mesh(name, np.array(V), F, coll)
    recalc_normals(plates)
    shade(plates, 40)
    set_attr(plates, 'ed_cav', np.array(CAV, dtype=np.float32))
    c = np.array(COL, dtype=np.float32)
    set_attr(plates, 'ed_col', np.stack([c, c, c, np.ones_like(c)], axis=1), 'FLOAT_COLOR')
    set_attr(plates, 'ed_row', np.array(ROW, dtype=np.int32), 'INT')
    plates['ed_cells'] = [rows, cols]
    lacing = None
    if lace and LV:
        lacing = new_mesh(name + '_lace', np.array(LV), LF, coll)
        recalc_normals(lacing)
        set_attr(lacing, 'ed_cav', np.full(len(LV), 0.9, dtype=np.float32))
    return plates, lacing


def _stitch(V, F, a, b, n, side, r, flat=False):
    """A short raised lace stitch from a to b (a flat-topped 4-sided cord with sunk ends; flat: one raised ridge, 4 tris)."""
    base = len(V)
    if flat:
        for p, sink in ((a, 1.0), (b, 1.0)):
            for sx, sn in ((-1, 0.0), (0, 1.0), (1, 0.0)):
                V.append(p + side * (sx * r) + n * (sn * r * 0.9 - sink * r * 0.4))
        F.append((base, base + 1, base + 4, base + 3)); F.append((base + 1, base + 2, base + 5, base + 4))
        return
    for p, sink in ((a, 1.0), (a, 0.0), (b, 0.0), (b, 1.0)):
        for sx, sn in ((-1, 0.0), (-0.6, 1.0), (0.6, 1.0), (1, 0.0)):
            V.append(p + side * (sx * r) + n * (sn * r * 0.9 - sink * r * 1.6))
    for k in range(3):
        for i in range(3):
            q = base + k * 4 + i
            F.append((q, q + 1, q + 5, q + 4))


def _cord(V, F, pts, r, sides=5):
    T, N, B = frames_along(pts)
    base = len(V)
    for i in range(len(pts)):
        for s in range(sides):
            a = TAU * s / sides
            V.append(pts[i] + r * (math.cos(a) * N[i] + math.sin(a) * B[i]))
    for i in range(len(pts) - 1):
        for s in range(sides):
            a = base + i * sides + s; b = base + i * sides + (s + 1) % sides
            F.append((a, b, b + sides, a + sides))


def braid(name, path, width=0.034, thickness=0.02, pitch=0.045, taper=0.6, strands=3, sides=6, per_cross=6, up=None, coll=None):
    """
    A real three-strand plait along a path ((n, 3)): each strand is a tube weaving a figure of eight around the centre
    line (the classic braid curve), flattened to width x thickness, thinning to `taper` at the end.
    Writes ed_uvw (u around the strand, v along the path 0..1, strand id) and ed_uv.v = position along the path (0..1):
    bind it to a spring chain with skin.along_chain(). ~ strands * sides * 2 * crossings * per_cross triangles.
    """
    P = np.asarray(path, dtype=np.float64)
    seg = np.linalg.norm(np.diff(P, axis=0), axis=1); L = float(seg.sum())
    crossings = max(2, int(round(L / pitch)))
    m = crossings * per_cross + 1
    C = polyline(P, m)
    T, N, B = frames_along(C, up)
    t = np.linspace(0, 1, m)
    k = lerp(1.0, taper, t)
    objs = []
    for s in range(strands):
        ph = TAU * s / strands
        a = t * crossings * math.pi + ph
        # figure-eight: across = sin(a), depth = sin(2a) / 2
        off = (np.sin(a) * width * 0.5 * k)[:, None] * B + (np.sin(2 * a) * thickness * 0.33 * k)[:, None] * N
        r = thickness * 0.36 * k
        o = sweep(f'{name}_s{s}', C + off, sides, lambda tt, r=r: np.interp(tt, t, r), up=N[0], caps=True, coll=coll)
        q = get_attr(o, 'ed_uv')
        set_attr(o, 'ed_uvw', np.stack([q[:, 0] * 3.0, q[:, 1] * crossings * 0.5, np.full(len(q), 0.0)], axis=1), 'FLOAT_VECTOR')
        objs.append(o)
    obj = join(objs, name)
    return obj


def helix_wrap(name, a, b, radius, turns=7, width=0.03, thick=0.0018, overlap=0.25, sides=18, ellipse=1.0, axes=None, jitter=0.15, seed=5, coll=None):
    """
    Bandage / cord wrapping spiralling from point a to point b around a limb (wrapped forearms and shins, grip wraps).
    radius: number or curve over t = 0..1 (limb radius under the wrap); ellipse: side / front radius ratio; axes: (ax,
    az) unit vectors of the limb cross-section (default: any perpendicular pair). Each turn overlaps the previous by
    `overlap` of the width and sits proud of it; edges get a darker ed_cav. width is the visible band width.
    """
    a = np.asarray(a, dtype=np.float64); b = np.asarray(b, dtype=np.float64)
    ax = normalize(b - a); L = np.linalg.norm(b - a)
    if axes is None:
        ref = np.eye(3)[np.argmin(np.abs(ax))]
        e1 = normalize(np.cross(ax, ref)); e2 = np.cross(ax, e1)
    else:
        e1, e2 = np.asarray(axes[0], dtype=np.float64), np.asarray(axes[1], dtype=np.float64)
    rng = np.random.RandomState(seed)
    R = curve_fn(radius)
    n = int(turns * sides) + 1
    pitch = L / turns
    band = width if width else pitch * (1 + overlap)
    V, F, CAV = [], [], []
    jit = (rng.rand(int(turns) + 2) - 0.5) * jitter
    for i in range(n):
        th = TAU * i / sides
        turn = i / sides
        t0 = turn / turns
        j = jit[int(turn)] * (1 - (turn - int(turn))) + jit[int(turn) + 1] * (turn - int(turn))
        for k, (s, lift, cv) in enumerate(((0.0, 0.25, 0.6), (0.12, 1.0, 1.15), (0.5, 1.15, 1.0), (0.88, 1.0, 1.0), (1.0, 2.1, 0.75))):
            # across the band: the leading edge (s = 1) rides on top of the previous turn
            h = (t0 + (s - 0.5) * band / L + j * pitch / L)
            hc = min(max(h, -0.02), 1.02)
            r = float(R(min(max(hc, 0), 1))) + thick * lift
            c = a + ax * (hc * L)
            V.append(c + r * (math.cos(th) * e1 + math.sin(th) * ellipse * e2))
            CAV.append(cv)
    for i in range(n - 1):
        for k in range(4):
            p = i * 5 + k
            F.append((p, p + 5, p + 6, p + 1))
    obj = new_mesh(name, np.array(V), F, coll)
    recalc_normals(obj)
    set_attr(obj, 'ed_cav', np.array(CAV, dtype=np.float32))
    return obj


def knot(name, center, size=0.03, facing=(0, -1, 0), up=(0, 0, 1), tube_r=None, coll=None):
    """A flat reef-style knot (sash knots, cord ends): two interlocked loops of cord, facing `facing`."""
    f = normalize(np.asarray(facing, dtype=np.float64)); u = normalize(np.asarray(up, dtype=np.float64) - f * np.dot(up, f)); s = np.cross(u, f)
    r = tube_r or size * 0.2
    objs = []
    for sg in (1, -1):
        pts = []
        for k in range(17):
            a = k / 16 * TAU
            x = sg * (0.55 + 0.6 * math.cos(a)) * size * 0.6
            y = math.sin(a) * size * 0.42
            z = sg * math.sin(a * 2) * r * 0.9 + r
            pts.append(np.asarray(center) + s * x + u * y + f * z)
        objs.append(sweep(f'{name}_{sg}', np.array(pts), 6, r, caps=False, coll=coll))
    return join(objs, name)


def tassel(name, top, direction=(0, 0, -1), length=0.12, radius=0.014, strands=14, head=0.3, coll=None, seed=2):
    """
    Tassel / horsehair plume: a bound head and `strands` flat cards fanning below it. ed_uv.v runs 0 (top) .. 1 (tip)
    (bind with skin.along_chain); ed_uvw = (u, v, thin) for the `hair` texture set on a cut-out slot.
    """
    rng = np.random.RandomState(seed)
    d = normalize(np.asarray(direction, dtype=np.float64)); top = np.asarray(top, dtype=np.float64)
    ref = np.eye(3)[np.argmin(np.abs(d))]
    e1 = normalize(np.cross(d, ref)); e2 = np.cross(d, e1)
    hl = length * head
    objs = [lathe(name + '_head', [[radius * 0.35, 0], [radius * 0.8, hl * 0.2], [radius, hl * 0.6], [radius * 0.72, hl * 0.86], [radius * 0.86, hl]], 10, origin=top, axis=d, caps=(True, False), coll=coll)]
    q = get_attr(objs[0], 'ed_uv').copy(); q[:, 1] *= head
    set_attr(objs[0], 'ed_uv', q, 'FLOAT_VECTOR')
    set_attr(objs[0], 'ed_uvw', np.stack([q[:, 0] * 6, q[:, 1], np.full(len(q), 0.0)], axis=1), 'FLOAT_VECTOR')
    for s in range(strands):
        a = TAU * (s + 0.5 * rng.rand()) / strands
        out = math.cos(a) * e1 + math.sin(a) * e2
        spread = 0.7 + 0.5 * rng.rand()
        pts = [top + d * (hl * 0.85) + out * radius * 0.6,
               top + d * (hl + (length - hl) * 0.4) + out * radius * (1.0 + 0.5 * spread),
               top + d * (length * (0.9 + 0.15 * rng.rand())) + out * radius * (1.0 + 0.9 * spread)]
        path = polyline(np.array(pts), 5)
        o = ribbon(f'{name}_c{s}', path, width=radius * 1.15, normal=out, camber=0.18, nu=2, coll=coll, uv_scale=(1.0, 1.0), code=0.55)
        q = get_attr(o, 'ed_uv').copy(); q[:, 1] = head + q[:, 1] * (1 - head)
        set_attr(o, 'ed_uv', q, 'FLOAT_VECTOR')
        w = get_attr(o, 'ed_uvw').copy(); w[:, 0] = w[:, 0] * 0.5 + s * 0.37
        set_attr(o, 'ed_uvw', w, 'FLOAT_VECTOR')
        objs.append(o)
    return join(objs, name)


def lacing(name, left, right, radius=0.0012, cross=True, sag=0.0, coll=None):
    """
    Lacing between two rows of points (left[i], right[i], (n, 3) each): X crosses (cross=True) or straight rungs, as
    thin cords. Ties collars, bracers, armour halves.
    """
    Lp = np.asarray(left, dtype=np.float64); Rp = np.asarray(right, dtype=np.float64)
    V, F = [], []
    n = len(Lp)
    for i in range(n - 1 if cross else n):
        pairs = ((Lp[i], Rp[i + 1]), (Rp[i], Lp[i + 1])) if cross else ((Lp[i], Rp[i]),)
        for k, (a, b) in enumerate(pairs):
            mid = (a + b) / 2 + np.array([0, 0, -sag])
            nrm = normalize(np.cross(b - a, Lp[min(i + 1, n - 1)] - Lp[max(i - 1, 0)]) + 1e-9)
            pts = np.array([a, mid + nrm * radius * (1.5 if k else -0.2), b])
            _cord(V, F, polyline(pts, 5), radius, 5)
    obj = new_mesh(name, np.array(V), F, coll)
    recalc_normals(obj)
    return obj


def grid_surface(obj, offset=0.0, u_wrap=None):
    """
    A parametric surface S(u, v) over a lofted object's vertex grid (obj['ed_grid'] = [N, R]; u around / across 0..1,
    v along 0..1), pushed `offset` metres along the grid normal: lay lamellar rows, weaves, belts or embroidery on top of a
    draped garment. u_wrap: the grid is a closed ring in u (default: from the loft).
    """
    N, R = obj['ed_grid']
    G = verts_of(obj)[: N * R].reshape(R, N, 3)
    closed = True if u_wrap is None else u_wrap
    if closed:
        G = np.concatenate([G, G[:, :1]], axis=1)
    Rr, Nn = G.shape[0], G.shape[1]
    # grid normals
    du = np.gradient(G, axis=1); dv = np.gradient(G, axis=0)
    Nrm = normalize(np.cross(du, dv))
    flip = np.mean(np.einsum('ijk,ijk->ij', Nrm, G - G.reshape(-1, 3).mean(axis=0))) < 0
    if flip:
        Nrm = -Nrm

    def S(u, v):
        x = (u % 1.0 if closed else min(max(u, 0.0), 1.0)) * (Nn - 1)
        y = min(max(v, 0.0), 1.0) * (Rr - 1)
        i = min(int(x), Nn - 2); j = min(int(y), Rr - 2)
        fx, fy = x - i, y - j
        p = (G[j, i] * (1 - fx) + G[j, i + 1] * fx) * (1 - fy) + (G[j + 1, i] * (1 - fx) + G[j + 1, i + 1] * fx) * fy
        n = (Nrm[j, i] * (1 - fx) + Nrm[j, i + 1] * fx) * (1 - fy) + (Nrm[j + 1, i] * (1 - fx) + Nrm[j + 1, i + 1] * fx) * fy
        return p + normalize(n) * offset
    S.flip = bool(flip)
    return S
