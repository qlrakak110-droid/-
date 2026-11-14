# edlib garments: body-fitted garment shells (rings cast against the body's signed-distance model, spanning its
# concavities like real cloth), panel cutting with seams and hems, Blender cloth-simulation draping against the body
# (pinned rows, stepped frames, frozen result), push-out of any body intersection, seam grooves and fold displacement.
#
# Typical robe:
#   S = ed.body.last_sdf                                     (or ed.body_sdf(rig))
#   shell = ed.wrap('robe', S, ed.ring_axis(rig, 'hips', ...), n=40, offset=0.012)
#   ed.drape(shell, [body], pin=lambda uv: uv[:, 1] < 0.05, frames=40)
#   ed.push_out(shell, S, 0.006); ed.hem(shell, 'v1', 0.006)

import bpy
import math
import numpy as np
from .core import (new_mesh, verts_of, set_verts, normals_of, add_mod, apply_mods, select, get_attr, set_attr, log, normalize, smoothstep, polyline,
                   duplicate, delete, link)
from .model import loft, grid_faces, frames_along, displace

TAU = math.pi * 2


# ---- body-fitted shells ---------------------------------------------------------------------------------------------------

def body_radius(sdf, center, e1, e2, angles, rmax=0.45, step=0.003, offset=0.0):
    """
    For rays from `center` in the plane (e1, e2) at `angles` (radians, 0 = e1): the radius of the OUTERMOST body surface
    (sdf <= offset). Rays that miss the body return 0.
    """
    rs = np.arange(rmax, 0.0, -step)
    A = np.asarray(angles, dtype=np.float64)
    dirs = np.cos(A)[:, None] * e1[None, :] + np.sin(A)[:, None] * e2[None, :]
    P = center[None, None, :] + rs[None, :, None] * dirs[:, None, :]          # (na, nr, 3)
    d = sdf.eval(P.reshape(-1, 3)).reshape(len(A), len(rs)) - offset
    inside = d <= 0
    first = np.argmax(inside, axis=1)                                          # first inside sample walking inward
    hit = inside.any(axis=1)
    out = np.zeros(len(A))
    for i in np.nonzero(hit)[0]:
        j = first[i]
        if j == 0:
            out[i] = rs[0]; continue
        d0, d1 = d[i, j - 1], d[i, j]                                          # outside, inside
        t = d0 / max(d0 - d1, 1e-9)
        out[i] = rs[j - 1] + (rs[j] - rs[j - 1]) * t
    return out


def convexify(r, angles, iters=40, closed=True, tension=1.0):
    """Polar ring radii -> span the concavities (a cord / cloth stretched around them). tension < 1 lets it sag in."""
    r = np.array(r, dtype=np.float64)
    n = len(r)
    if n < 3:
        return r
    da = float(np.mean(np.diff(angles))) if n > 1 else 0.0
    c = math.cos(da)
    for _ in range(iters):
        if closed:
            l, rr = np.roll(r, 1), np.roll(r, -1)
        else:
            l = np.concatenate([[r[0]], r[:-1]]); rr = np.concatenate([r[1:], [r[-1]]])
        # the chord between the neighbours passes at radius ~ (l * rr * sin 2da) / (l sin da + rr sin da) along the middle ray
        chord = (l * rr * math.sin(2 * da)) / np.maximum((l + rr) * math.sin(da), 1e-9) if da > 1e-6 else (l + rr) / 2
        r = np.maximum(r, chord * tension)
    return r


def wrap(name, sdf, centers, n=32, offset=0.01, ups=None, fronts=None, hull=True, tension=1.0, arc=(0.0, 1.0), min_r=None, ease=None,
         rmax=0.45, coll=None, close=None):
    """
    A garment shell around the body: one ring per centre point (R, 3), each ring in the plane perpendicular to the
    local axis through the centres, its radius = the body's outermost surface along each ray + offset (number or
    fn(u, v) -> metres), concavities spanned (hull). arc: (u0, u1) part of the turn (0 = front, 0.25 = the hero's LEFT
    (+x), 0.5 = back): open panels for split skirts and lapels. ease: fn(u, v) -> extra metres (looseness, flare).
    min_r: floor radius per ring. Returns the loft (ed_uv: u around, v down the centres; obj['ed_grid'] = [n, R]).
    """
    C = np.asarray(centers, dtype=np.float64)
    R = len(C)
    T, N, B = frames_along(C, up=(0, -1, 0)) if ups is None else (None, None, None)
    full = abs(arc[1] - arc[0]) >= 0.999
    close = full if close is None else close
    nu = n if close else n
    us = arc[0] + (arc[1] - arc[0]) * (np.arange(n) / (n if close else max(1, n - 1)))
    rings = []
    for j in range(R):
        v = j / max(1, R - 1)
        if ups is None:
            t = T[j]
            fr = normalize(np.array([0.0, -1.0, 0.0]) - t * np.dot([0.0, -1.0, 0.0], t)) if fronts is None else normalize(fronts[j])
        else:
            t = normalize(ups[j]); fr = normalize(fronts[j])
        side = np.cross(t, fr)               # with t pointing down the garment: front x down = the hero's left (+x)
        if side[0] < 0:
            side = -side
        ang = us * TAU
        # angle 0 = front, +90 deg = hero's left
        A = np.linspace(0, TAU, 96, endpoint=False)
        rb = body_radius(sdf, C[j], fr, side, A, rmax=rmax)
        if hull:
            rb = convexify(rb, A, 60, True, tension)
        r = np.interp(ang % TAU, np.concatenate([A, [TAU]]), np.concatenate([rb, rb[:1]]))
        off = offset(us, np.full(n, v)) if callable(offset) else np.full(n, float(offset))
        r = r + off
        if ease is not None:
            r = r + ease(us, np.full(n, v))
        if min_r is not None:
            r = np.maximum(r, min_r(v) if callable(min_r) else min_r)
        rings.append(C[j][None, :] + r[:, None] * (np.cos(ang)[:, None] * fr[None, :] + np.sin(ang)[:, None] * side[None, :]))
    obj = loft(name, np.array(rings), close=close, coll=coll)
    q = get_attr(obj, 'ed_uv').copy()
    q[:, 0] = np.tile(us, R)
    set_attr(obj, 'ed_uv', q, 'FLOAT_VECTOR')
    return obj


def push_out(obj, sdf, clearance=0.004, mask=None, iters=3):
    """Move vertices that are inside the body (or closer than `clearance`) out along the SDF gradient."""
    P = verts_of(obj)
    m = np.ones(len(P), dtype=bool) if mask is None else np.asarray(mask, dtype=bool)
    moved = 0
    for _ in range(iters):
        idx = np.nonzero(m)[0]
        if not len(idx):
            break
        d = sdf.eval(P[idx])
        bad = d < clearance
        if not bad.any():
            break
        ib = idx[bad]
        g = sdf.grad(P[ib])
        g = g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-9)
        P[ib] += g * (clearance - d[bad])[:, None]
        moved = max(moved, int(bad.sum()))
    set_verts(obj, P)
    return moved


# ---- Blender cloth draping ---------------------------------------------------------------------------------------------------

def collider(obj, thickness=0.004, friction=5.0):
    """Make a mesh a cloth collider (Collision modifier)."""
    if not any(m.type == 'COLLISION' for m in obj.modifiers):
        obj.modifiers.new('collision', 'COLLISION')
    c = obj.collision
    c.thickness_outer = thickness
    c.thickness_inner = 0.01
    c.cloth_friction = friction
    c.damping = 0.6
    return obj


def drape(obj, colliders=(), pin=None, frames=40, mass=0.25, tension=15.0, bending=0.5, shrink=0.0, gravity=(0, 0, -9.81), quality=8,
          air=1.0, self_collide=False, thickness=0.004, pressure=None, wind=None, keep_pins=True):
    """
    Drape a garment with Blender's cloth solver and freeze the result into the mesh (modifiers applied).
      pin       (N,) 0..1 weights or fn(ed_uv (N, 3), P (N, 3)) -> weights: pinned vertices keep their place (waistband,
                collar, the rows sewn to a belt)
      colliders mesh objects the cloth rests on (the body, a belt); a Collision modifier is added to each
      frames    simulation length at 24 fps (40 frames ~ 1.7 s: settled for skirts and sleeves)
      bending   stiffness of folds (0.05 silk ... 5 felt / leather), tension: stretch stiffness, shrink: < 0 grows
    The cloth's vertex order and attributes are kept, so ed_uv / panel coordinates stay valid.
    """
    sc = bpy.context.scene
    for c in colliders:
        collider(c, thickness)
    P0 = verts_of(obj)
    if callable(pin):
        w = np.asarray(pin(get_attr(obj, 'ed_uv'), P0), dtype=np.float64)
    elif pin is not None:
        w = np.asarray(pin, dtype=np.float64)
    else:
        w = None
    m = obj.modifiers.new('cloth', 'CLOTH')
    s = m.settings
    s.quality = quality
    s.mass = mass
    s.tension_stiffness = tension; s.compression_stiffness = tension; s.shear_stiffness = tension * 0.5
    s.bending_stiffness = bending
    s.air_damping = air
    s.shrink_min = shrink
    s.use_dynamic_mesh = False
    sc.gravity = gravity
    cs = m.collision_settings
    cs.use_collision = True
    cs.distance_min = thickness
    cs.collision_quality = 4
    cs.use_self_collision = self_collide
    if self_collide:
        cs.self_distance_min = thickness * 0.75
    if w is not None:
        g = obj.vertex_groups.get('_pin') or obj.vertex_groups.new(name='_pin')
        idx = np.nonzero(w > 1e-4)[0]
        for i in idx:
            g.add([int(i)], float(min(1.0, w[i])), 'REPLACE')
        s.vertex_group_mass = '_pin'
        s.pin_stiffness = 1.0
    pc = m.point_cache
    pc.frame_start = 1
    pc.frame_end = frames + 1
    sc.frame_start = 1
    sc.frame_end = frames + 1
    # move the other modifiers (armature) out of the way: the drape works in the bind pose
    for mm in obj.modifiers:
        if mm.type == 'ARMATURE':
            mm.show_viewport = False
    for f in range(1, frames + 2):
        sc.frame_set(f)
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = ev.data
    a = np.empty(len(me.vertices) * 3, dtype=np.float32)
    me.vertices.foreach_get('co', a)
    Pn = a.reshape(-1, 3).astype(np.float64)
    obj.modifiers.remove(m)
    for mm in obj.modifiers:
        if mm.type == 'ARMATURE':
            mm.show_viewport = True
    if len(Pn) == len(P0):
        set_verts(obj, Pn)
    if obj.vertex_groups.get('_pin'):
        obj.vertex_groups.remove(obj.vertex_groups['_pin'])
    sc.frame_set(1)
    moved = float(np.linalg.norm(Pn - P0, axis=1).max()) if len(Pn) == len(P0) else -1
    log(f'drape {obj.name}: {frames} frames, max move {moved * 100:.1f} cm')
    return obj


def remove_colliders(objs):
    for o in objs:
        for m in list(o.modifiers):
            if m.type == 'COLLISION':
                o.modifiers.remove(m)


# ---- garment details ------------------------------------------------------------------------------------------------------------

def pleats(obj, count=12, depth=0.012, grow=(0.1, 1.0), uv='ed_uv', phase=0.0, sharp=1.6):
    """
    Pleat / fold flutes around a garment loft (before draping: the solver keeps them as natural folds). count folds
    around the full turn, depth metres at the hem, growing with v from grow[0] to grow[1] of `depth`.
    """
    q = get_attr(obj, uv)
    u, v = q[:, 0], q[:, 1]
    s = np.sin((u * count + phase) * TAU)
    prof = np.sign(s) * np.abs(s) ** (1.0 / sharp)
    amt = depth * (grow[0] + (grow[1] - grow[0]) * v)
    N = horizontal_normals(obj)
    set_verts(obj, verts_of(obj) + N * (prof * amt)[:, None])
    return obj


def horizontal_normals(obj):
    N = normals_of(obj).copy()
    N[:, 2] = 0
    return normalize(N + 1e-9)


def hem(obj, side='v1', width=0.012, roll=0.003, uv='ed_uv'):
    """
    A turned hem along one edge of a garment loft (side 'v1' = the bottom, 'v0' = the top, 'u0' / 'u1' = the panel
    sides): the band of `width` from that edge is pushed out by `roll` (doubled cloth) and ed_cav darkens the stitch
    line at its inner edge.
    """
    q = get_attr(obj, uv)
    P = verts_of(obj)
    key = {'v1': 1 - q[:, 1], 'v0': q[:, 1], 'u0': q[:, 0] - q[:, 0].min(), 'u1': q[:, 0].max() - q[:, 0]}[side]
    # parameter -> metres: estimate the garment length along that direction
    span = _span(P, q, side)
    d = key * span
    band = 1 - smoothstep(width * 0.8, width, d)
    N = normals_of(obj)
    set_verts(obj, P + N * (band * roll)[:, None])
    cav = get_attr(obj, 'ed_cav', np.ones(len(P), dtype=np.float32)).copy()
    stitch = np.exp(-((d - width) / (width * 0.12)) ** 2)
    cav *= (1 - 0.35 * stitch).astype(np.float32)
    set_attr(obj, 'ed_cav', cav)
    return obj


def _span(P, q, side):
    if side in ('v0', 'v1'):
        z = P[:, 2]
        return max(float(z.max() - z.min()), 1e-3)
    return max(float(np.ptp(P[:, 0])), 1e-3)


def seam(obj, fn, depth=0.0015, width=0.003):
    """
    A sewn seam groove along a curve on the garment: fn(P, uv) -> signed distance (metres) of each vertex to the seam
    line; vertices within `width` sink by `depth` and get a darker ed_cav (the stitches).
    """
    P = verts_of(obj)
    q = get_attr(obj, 'ed_uv')
    d = np.abs(np.asarray(fn(P, q), dtype=np.float64))
    g = np.exp(-(d / width) ** 2)
    N = normals_of(obj)
    set_verts(obj, P - N * (g * depth)[:, None])
    cav = get_attr(obj, 'ed_cav', np.ones(len(P), dtype=np.float32)).copy()
    cav *= (1 - 0.4 * g).astype(np.float32)
    set_attr(obj, 'ed_cav', cav)
    return obj


def ring_axis(points, n):
    """Resample a garment's axis (a few control points, top to bottom) to n ring centres."""
    return polyline(np.asarray(points, dtype=np.float64), n)
