# edlib base body: a parametric but anatomical body fitted to a hero's rig joints. Masses are authored as lofts and
# ellipsoids in bone frames (torso, neck, head, deltoids, pectorals, trapezius, lats, glutes, limbs with muscle
# bellies, knee caps, elbows, ankles, clavicles), fused by a voxel remesh, smoothed and decimated to a triangle budget;
# the hands are clean lofted meshes with separated fingers and joint loops, skinned analytically to the rig's finger
# bones. The heroes show necks, hands, wrists and sometimes forearms or shins, and cloth must drape on a believable body.

import bpy
import math
import os
import numpy as np
from .core import (Rig, new_mesh, verts_of, set_verts, join, delete, add_mod, apply_mods, shade, set_weights, get_weights, set_attr, get_attr, normalize,
                   smoothstep, lerp, log, duplicate, recalc_normals, weld, select, collection, look, assign_look, set_color)
from .model import loft, ellipse_ring, ellipsoid, capsule, smooth as smooth_mesh, grid_faces
from . import skin as SK

TAU = math.pi * 2

DEFAULT_BUILD = {
    'mass': 1.0,        # overall girth of torso and limbs
    'chest': 1.0,       # chest depth / width
    'waist': 1.0,       # waist width
    'hips': 1.0,        # pelvis width
    'arms': 1.0,        # arm girth
    'legs': 1.0,        # leg girth
    'neck': 1.0,
    'muscle': 1.0,      # definition of the muscle bellies (0 = smooth mannequin)
    'bust': 0.0,        # female chest (0..1)
    'hands': 1.0,       # hand girth (length follows the rig)
}


def _frame_ring(rig, bone, y, rx, rz, ox=0.0, oz=0.0, n=20, power=2.0, bumps=None):
    """Ring around the bone's long axis at height y (game bone frame): radii along the bone's X (front) / Z (side)."""
    c = rig.pt(bone, [ox, y, oz])
    return ellipse_ring(c, rig.vec(bone, [1, 0, 0]), rig.vec(bone, [0, 0, 1]), rx, rz, n, power, 0.0, bumps)


def _bump(theta0, width, amp):
    """Angular gaussian bump for ellipse_ring: centred at theta0 (0 = front, pi/2 = the bone's +Z), radial gain `amp`."""
    def f(th):
        d = np.angle(np.exp(1j * (th - theta0)))
        return amp * np.exp(-(d / width) ** 2)
    return f


def _sum(*fs):
    return lambda th: sum(f(th) for f in fs)


def _ell(rig, name, bone, off, radii, coll, tilt=None):
    """Ellipsoid in a bone frame: radii along the bone's (X, Y, Z)."""
    R = np.stack([rig.vec(bone, [1, 0, 0]), rig.vec(bone, [0, 1, 0]), rig.vec(bone, [0, 0, 1])], axis=1)
    if tilt is not None:
        R = R @ np.asarray(tilt)
    return ellipsoid(name, rig.pt(bone, off), radii, R, (14, 10), coll)


def body(rig, name='body', build=None, voxel=0.006, tris=6500, hands=True, feet=True, coll=None, arm=None, cache=True):
    """
    The base body of a rig, skinned. Returns the mesh object (vertex groups = game bones incl. helper bones; attribute
    ed_region: 0 torso, 1 head / neck, 2 arms, 3 hands, 4 legs, 5 feet).
      build   overrides of DEFAULT_BUILD (mass, chest, waist, hips, arms, legs, neck, muscle, bust, hands)
      voxel   remesh size (m): 0.006 is plenty under clothes; 0.004 for bare-chested heroes
      tris    triangle budget of the fused body (the two hands add ~1.9k)
      arm     armature from build_armature (needed for skinning; without it the body is returned unskinned)
    Typical use: drape and skin garments against it, then keep only what shows (keep_regions / cull_hidden).
    """
    B = {**DEFAULT_BUILD, **(build or {})}
    K = rig.K
    L = rig.data['lengths']
    P = rig.P
    tmp = collection('_body_tmp')
    parts = []
    mu = B['muscle']
    m, n = B['mass'], 24

    # ---- torso: hips -> neck (frames of the centre bones are the model axes) ---------------------------------------------
    shoulder_z = abs(rig.local('chest', rig.head('upperArmR'))[2])            # shoulder joint offset from the midline
    sh_y = rig.local('chest', rig.head('upperArmR'))[1]                        # and its height above the chest pivot
    hip_z = P['hipWidth']
    wc, ww, wh = B['chest'] * m, B['waist'] * m, B['hips'] * m
    belly = _bump(0.0, 0.9, 0.03)
    pec = lambda a: _sum(_bump(0.55, 0.42, a), _bump(-0.55, 0.42, a))          # two pectoral swells either side of the sternum
    back = lambda a: _sum(_bump(math.pi - 0.6, 0.5, a), _bump(math.pi + 0.6, 0.5, a))   # erector / lat masses with a spine furrow
    spine_len = P['spine']; chest_len = P['chest']; neck_y = P['neck']
    rings = [
        _frame_ring(rig, 'hips', -0.115 * K, 0.060 * K * wh, 0.080 * K * wh, -0.004 * K, 0, n, 2.3),
        _frame_ring(rig, 'hips', -0.05 * K, 0.103 * K * wh, (hip_z + 0.052 * K) * wh, -0.006 * K, 0, n, 2.4),
        _frame_ring(rig, 'hips', 0.03 * K, 0.101 * K * wh, (hip_z + 0.046 * K) * wh, -0.002 * K, 0, n, 2.3, back(0.02 * mu)),
        _frame_ring(rig, 'spine', 0.0, 0.092 * K * ww, 0.131 * K * ww, 0.004 * K, 0, n, 2.2, _sum(belly, back(0.03 * mu))),
        _frame_ring(rig, 'spine', spine_len * 0.55, 0.098 * K * ww, 0.14 * K * ww, 0.006 * K, 0, n, 2.2, back(0.035 * mu)),
        _frame_ring(rig, 'chest', 0.0, 0.108 * K * wc, 0.152 * K * wc, 0.008 * K, 0, n, 2.25, _sum(pec(0.02 * mu), back(0.04 * mu))),
        _frame_ring(rig, 'chest', sh_y * 0.48, 0.116 * K * wc, (shoulder_z - 0.068 * K) * wc + 0.0, 0.011 * K, 0, n, 2.3, _sum(pec(0.055 * mu), back(0.045 * mu))),
        _frame_ring(rig, 'chest', sh_y * 0.86, 0.104 * K * wc, (shoulder_z - 0.07 * K) * wc, 0.006 * K, 0, n, 2.25, _sum(pec(0.03 * mu), back(0.03 * mu))),
        _frame_ring(rig, 'chest', sh_y * 1.1, 0.075 * K * m, 0.105 * K * m, -0.004 * K, 0, n, 2.1),
        _frame_ring(rig, 'neck', 0.01 * K, 0.060 * K * B['neck'], 0.058 * K * B['neck'], 0.0, 0, n, 2.0),
        _frame_ring(rig, 'neck', 0.06 * K, 0.055 * K * B['neck'], 0.052 * K * B['neck'], 0.004 * K, 0, n, 2.0, _bump(0.0, 0.35, 0.05 * mu)),
        _frame_ring(rig, 'head', 0.0, 0.056 * K * B['neck'], 0.053 * K * B['neck'], 0.006 * K, 0, n, 2.0),
        _frame_ring(rig, 'head', 0.05 * K, 0.058 * K, 0.055 * K, 0.008 * K, 0, n, 2.0),
    ]
    parts.append(loft('torso', np.array(rings), caps=(True, True), coll=tmp))
    # ---- head: skull + jaw (hidden under wraps, masks and hats, but they sit on it) ---------------------------------------
    parts.append(_ell(rig, 'skull', 'head', [0.012 * K, 0.118 * K, 0], [0.101 * K, 0.105 * K, 0.079 * K], tmp))
    parts.append(_ell(rig, 'jaw', 'head', [0.04 * K, 0.045 * K, 0], [0.068 * K, 0.062 * K, 0.062 * K], tmp))
    parts.append(_ell(rig, 'chin', 'head', [0.078 * K, 0.012 * K, 0], [0.03 * K, 0.03 * K, 0.036 * K], tmp))
    parts.append(_ell(rig, 'nose', 'head', [0.108 * K, 0.085 * K, 0], [0.017 * K, 0.026 * K, 0.014 * K], tmp))
    parts.append(_ell(rig, 'brow', 'head', [0.092 * K, 0.135 * K, 0], [0.02 * K, 0.016 * K, 0.058 * K], tmp))
    for s, z in (('R', 1.0), ('L', -1.0)):
        parts.append(_ell(rig, 'ear' + s, 'head', [0.0, 0.092 * K, z * 0.08 * K], [0.016 * K, 0.03 * K, 0.008 * K], tmp))
    # ---- shoulders, chest and back masses ----------------------------------------------------------------------------------
    for s, z in (('R', 1.0), ('L', -1.0)):
        ua, fa, th, sn = 'upperArm' + s, 'foreArm' + s, 'thigh' + s, 'shin' + s
        a = B['arms'] * m
        # trapezius: neck -> point of the shoulder; clavicle bar; pectoral; latissimus; shoulder blade
        parts.append(capsule('trap' + s, rig.pt('neck', [-0.02 * K, 0.035 * K, z * 0.035 * K]), rig.pt(ua, [-0.012 * K, 0.012 * K, -z * 0.055 * K]), 0.044 * K * m, 0.034 * K * m, 12, tmp))
        parts.append(capsule('clav' + s, rig.pt('chest', [0.076 * K, sh_y * 0.93, z * 0.024 * K]), rig.pt(ua, [0.012 * K, 0.022 * K, -z * 0.03 * K]), 0.013 * K, 0.012 * K, 8, tmp))
        parts.append(_ell(rig, 'pec' + s, 'chest', [0.078 * K * wc, sh_y * 0.5, z * shoulder_z * 0.43], [0.042 * K * (1 + 0.5 * B['bust']) * mu ** 0.5, 0.07 * K, 0.092 * K], tmp))
        parts.append(_ell(rig, 'lat' + s, 'chest', [-0.058 * K, sh_y * 0.32, z * shoulder_z * 0.62], [0.05 * K * m, 0.13 * K, 0.06 * K * m], tmp))
        parts.append(_ell(rig, 'scap' + s, 'chest', [-0.092 * K, sh_y * 0.72, z * shoulder_z * 0.5], [0.028 * K, 0.075 * K, 0.06 * K], tmp))
        # deltoid cap over the shoulder joint
        parts.append(_ell(rig, 'delt' + s, ua, [-0.004 * K, -0.045 * K, z * 0.008 * K], [0.062 * K * a, 0.088 * K, 0.058 * K * a], tmp))
        # upper arm: biceps in front, triceps behind
        Lu = L['upperArm']
        ur = [
            _frame_ring(rig, ua, 0.02, 0.05 * K * a, 0.047 * K * a, 0, 0, 16),
            _frame_ring(rig, ua, -0.30 * Lu, 0.051 * K * a, 0.046 * K * a, 0.002 * K, 0, 16, 2.0, _sum(_bump(0.0, 0.8, 0.10 * mu), _bump(math.pi, 0.9, 0.08 * mu))),
            _frame_ring(rig, ua, -0.55 * Lu, 0.048 * K * a, 0.043 * K * a, 0.003 * K, 0, 16, 2.0, _sum(_bump(0.0, 0.8, 0.12 * mu), _bump(math.pi, 0.9, 0.06 * mu))),
            _frame_ring(rig, ua, -0.82 * Lu, 0.041 * K * a, 0.040 * K * a, 0, 0, 16),
            _frame_ring(rig, ua, -1.02 * Lu, 0.038 * K * a, 0.041 * K * a, -0.002 * K, 0, 16),
        ]
        parts.append(loft('uarm' + s, np.array(ur), caps=(True, True), coll=tmp))
        # forearm: brachioradialis / extensor belly below the elbow, flat wrist (wide front-back: the palm faces the thigh)
        Lf = L['foreArm']
        fr = [
            _frame_ring(rig, fa, 0.03, 0.037 * K * a, 0.04 * K * a, -0.002 * K, 0, 16),
            _frame_ring(rig, fa, -0.10 * Lf, 0.043 * K * a, 0.042 * K * a, 0.002 * K, 0, 16, 2.0, _bump(z * 0.9, 0.9, 0.08 * mu)),
            _frame_ring(rig, fa, -0.30 * Lf, 0.044 * K * a, 0.041 * K * a, 0.003 * K, 0, 16, 2.0, _bump(z * 0.9, 0.9, 0.10 * mu)),
            _frame_ring(rig, fa, -0.58 * Lf, 0.037 * K * a, 0.034 * K * a, 0.002 * K, 0, 16),
            _frame_ring(rig, fa, -0.82 * Lf, 0.031 * K * a, 0.026 * K * a, 0.001 * K, 0, 16, 2.2),
            _frame_ring(rig, fa, -1.0 * Lf, 0.0285 * K * a, 0.0215 * K * a, 0, 0, 16, 2.4),
            _frame_ring(rig, fa, -1.0 * Lf - 0.03, 0.028 * K * a, 0.02 * K * a, 0, 0, 16, 2.4),
        ]
        parts.append(loft('farm' + s, np.array(fr), caps=(True, True), coll=tmp))
        parts.append(_ell(rig, 'olec' + s, fa, [-0.03 * K, 0.004, 0], [0.02 * K, 0.026 * K, 0.021 * K], tmp))
        parts.append(_ell(rig, 'ulna' + s, 'hand' + s, [-0.02 * K, 0.012 * K, z * 0.012 * K], [0.011 * K, 0.012 * K, 0.011 * K], tmp))
        # ---- legs ------------------------------------------------------------------------------------------------------------
        g = B['legs'] * m
        Lt, Ls = L['thigh'], L['shin']
        parts.append(_ell(rig, 'glute' + s, 'hips', [-0.072 * K, -0.05 * K, z * (hip_z - 0.012 * K)], [0.075 * K * g, 0.092 * K, 0.082 * K * g], tmp))
        tr = [
            _frame_ring(rig, th, 0.05, 0.088 * K * g, 0.084 * K * g, -0.004 * K, 0, 18),
            _frame_ring(rig, th, -0.16 * Lt, 0.092 * K * g, 0.087 * K * g, 0.002 * K, 0, 18, 2.0, _bump(0.0, 1.0, 0.05 * mu)),
            _frame_ring(rig, th, -0.42 * Lt, 0.084 * K * g, 0.078 * K * g, 0.006 * K, 0, 18, 2.0, _sum(_bump(0.0, 0.9, 0.07 * mu), _bump(math.pi, 0.9, 0.05 * mu))),
            _frame_ring(rig, th, -0.70 * Lt, 0.068 * K * g, 0.064 * K * g, 0.005 * K, 0, 18, 2.0, _bump(-z * 1.2, 0.6, 0.06 * mu)),
            _frame_ring(rig, th, -0.92 * Lt, 0.057 * K * g, 0.056 * K * g, 0.002 * K, 0, 18),
            _frame_ring(rig, th, -1.03 * Lt, 0.054 * K * g, 0.054 * K * g, 0.0, 0, 18),
        ]
        parts.append(loft('thigh' + s, np.array(tr), caps=(True, True), coll=tmp))
        sr = [
            _frame_ring(rig, sn, 0.035, 0.054 * K * g, 0.054 * K * g, 0.002 * K, 0, 16),
            _frame_ring(rig, sn, -0.10 * Ls, 0.053 * K * g, 0.051 * K * g, -0.004 * K, 0, 16),
            _frame_ring(rig, sn, -0.30 * Ls, 0.057 * K * g, 0.052 * K * g, -0.013 * K, 0, 16, 2.0, _sum(_bump(math.pi - z * 0.5, 0.7, 0.10 * mu), _bump(math.pi + z * 0.4, 0.7, 0.06 * mu))),
            _frame_ring(rig, sn, -0.55 * Ls, 0.046 * K * g, 0.042 * K * g, -0.009 * K, 0, 16),
            _frame_ring(rig, sn, -0.80 * Ls, 0.036 * K * g, 0.033 * K * g, -0.003 * K, 0, 16),
            _frame_ring(rig, sn, -1.0 * Ls + 0.01, 0.034 * K * g, 0.031 * K * g, 0, 0, 16),
        ]
        parts.append(loft('shin' + s, np.array(sr), caps=(True, True), coll=tmp))
        parts.append(_ell(rig, 'patella' + s, sn, [0.046 * K * g, 0.012 * K, 0], [0.02 * K, 0.034 * K, 0.03 * K], tmp))
        parts.append(_ell(rig, 'mall' + s, 'foot' + s, [-0.004 * K, 0.004 * K, z * 0.03 * K], [0.014 * K, 0.016 * K, 0.012 * K], tmp))
        parts.append(_ell(rig, 'malm' + s, 'foot' + s, [0.0, 0.012 * K, -z * 0.03 * K], [0.014 * K, 0.016 * K, 0.011 * K], tmp))
        if feet:
            ft, toe = 'foot' + s, 'toe' + s
            ah, fl, fd, tl, hl = P['ankleHeight'], P['footLength'], P['footDrop'], P['toeLength'], P['heelLength']
            parts.append(_ell(rig, 'heel' + s, ft, [-hl * 0.45, -ah * 0.55, 0], [hl * 0.75, ah * 0.5, 0.034 * K], tmp))
            parts.append(capsule('instep' + s, rig.pt(ft, [-0.01, -ah * 0.35, 0]), rig.pt(ft, [fl * 0.92, -fd - 0.004, 0]), 0.036 * K, 0.03 * K, 12, tmp))
            parts.append(_ell(rig, 'ball' + s, ft, [fl * 0.92, -fd - 0.002, -z * 0.004], [0.04 * K, 0.026 * K, 0.047 * K], tmp))
            parts.append(_ell(rig, 'toes' + s, toe, [tl * 0.45, -0.006, 0], [tl * 0.6, 0.02 * K, 0.043 * K], tmp))
    obj = join(parts, name + '_fused')
    recalc_normals(obj)
    # ---- fuse: voxel remesh -> smooth -> decimate ------------------------------------------------------------------------------
    add_mod(obj, 'REMESH', mode='VOXEL', voxel_size=voxel, adaptivity=0.0)
    apply_mods(obj)
    smooth_mesh(obj, 0.6, 10)
    V = verts_of(obj)
    floor = 0.0015
    V[:, 2] = np.maximum(V[:, 2], floor)                        # flat soles
    set_verts(obj, V)
    n0 = len(obj.data.polygons) * 2
    if n0 > tris:
        dm = add_mod(obj, 'DECIMATE', decimate_type='COLLAPSE', ratio=tris / n0)
        dm.use_symmetry = True; dm.symmetry_axis = 'X'
        apply_mods(obj)
    smooth_mesh(obj, 0.25, 2)
    shade(obj)
    log(f'body: fused {n0} -> {len(obj.data.polygons)} faces')
    # regions (by height / nearest bone) for culling and looks
    if arm is not None:
        SK.auto_skin(obj, arm, rig, helpers=True, smooth=2)
    _regions(obj, rig)
    if hands:
        hs = []
        for s in ('R', 'L'):
            h = hand(rig, s, name + '_hand' + s, B['hands'], coll=tmp)
            hs.append(h)
        obj = join([obj] + hs, name + '_all')
    out = obj
    out.name = name; out.data.name = name
    from .core import link
    link(out, coll)
    if arm is not None:
        SK.attach(out, arm)
    try:
        bpy.data.collections.remove(tmp)
    except Exception:
        pass
    return out


def _regions(obj, rig):
    """ed_region per vertex from the dominant bone: 0 torso, 1 head / neck, 2 arms, 3 hands, 4 legs, 5 feet."""
    W = get_weights(obj)
    n = len(obj.data.vertices)
    if not W:
        set_attr(obj, 'ed_region', np.zeros(n, dtype=np.int32), 'INT')
        return
    names = list(W.keys())
    A = np.stack([W[k] for k in names], axis=1)
    dom = A.argmax(axis=1)

    def reg(b):
        base = b.rstrip('RL') if b[-1:] in 'RL' else b
        if base in ('neck', 'head'):
            return 1
        if base in ('shoulder', 'deltoid', 'upperArm', 'upperArmTwist', 'elbow', 'elbowVol', 'foreArm', 'foreArmTwist'):
            return 2
        if base in ('hand', 'fingers', 'fingerTips', 'thumb'):
            return 3
        if base in ('thigh', 'thighTwist', 'hipJoint', 'knee', 'kneeVol', 'shin'):
            return 4
        if base in ('foot', 'toe'):
            return 5
        return 0
    lut = np.array([reg(b) for b in names], dtype=np.int32)
    set_attr(obj, 'ed_region', lut[dom], 'INT')


def hand(rig, side='R', name=None, girth=1.0, coll=None, shaft=None):
    """
    A hand with four separated fingers and a thumb, built in the rig's hand frame (wrist at the origin, fingers along
    -Y, thumb forward, palm toward the body) with edge loops on every joint and analytic weights on hand / fingers /
    fingerTips / thumb. The palm is thin on its inner side so a weapon haft on the grip axis sits IN the palm; the
    fingers ride slightly behind their joint line and carry a relaxed bend, so the rig's curl closes them around a haft
    (design the haft radius <= 0.016 m where the hands hold it). ~950 triangles.
    """
    s = side
    z = 1.0 if s == 'R' else -1.0          # the palm faces -z on the right hand, +z on the left
    kh = rig.P['hand'] / 0.085
    g = girth
    hb, fb, tb, thb = 'hand' + s, 'fingers' + s, 'fingerTips' + s, 'thumb' + s
    name = name or 'hand' + s
    objs = []
    fo = rig.local(hb, rig.head(fb))        # knuckle line in the hand frame
    to = rig.local(hb, rig.head(thb))
    kn_y = fo[1]
    # ---- palm: superellipse rings down the hand; wide front-back (X), thin across (Z), its inner face flat ----------------
    pc = 0.003 * kh * z                     # palm centre plane sits toward the back of the hand
    def pring(y, cx, hx, hz, power=3.0, bumps=None):
        c = rig.pt(hb, [cx, y, pc])
        return ellipse_ring(c, rig.vec(hb, [1, 0, 0]), rig.vec(hb, [0, 0, 1]), hx, hz, 16, power, 0.0, bumps)
    thenar = _bump(-z * 0.75, 0.6, 0.22)                                     # ball of the thumb (palm side, forward)
    knuck = _sum(*[_bump(z * (math.pi / 2) + d, 0.16, 0.10) for d in (-0.62, -0.2, 0.2, 0.6)])
    pr = [
        pring(0.03 * kh, 0.0, 0.0275 * kh * g, 0.0195 * kh * g, 2.6),
        pring(0.0, 0.0, 0.0285 * kh * g, 0.0185 * kh * g, 2.6),
        pring(-0.022 * kh, 0.002 * kh, 0.034 * kh * g, 0.0155 * kh * g, 2.8, thenar),
        pring(-0.05 * kh, 0.004 * kh, 0.0405 * kh * g, 0.0135 * kh * g, 3.0, thenar),
        pring(kn_y * 0.8, 0.004 * kh, 0.043 * kh * g, 0.012 * kh * g, 3.2),
        pring(kn_y - 0.002 * kh, 0.004 * kh, 0.0425 * kh * g, 0.0118 * kh * g, 3.2, knuck),
        pring(kn_y - 0.011 * kh, 0.004 * kh, 0.039 * kh * g, 0.0085 * kh * g, 3.0),
    ]
    palm = loft(name + '_palm', np.array(pr), caps=(True, True), coll=coll)
    nP = len(palm.data.vertices)
    Wp = {hb: np.ones(nP)}
    # the wrist rings follow the forearm twist helper (the wrist is where pronation shows)
    yv = rig.local(hb, verts_of(palm))[:, 1]
    wtw = smoothstep(-0.012 * kh, 0.02 * kh, yv)
    if rig.has('foreArmTwist' + s):
        Wp = {hb: 1 - wtw, 'foreArmTwist' + s: wtw}
    set_weights(palm, Wp)
    objs.append(palm)
    # ---- fingers ------------------------------------------------------------------------------------------------------------
    xs = [0.0305, 0.0102, -0.0102, -0.0296]                                  # index .. little finger, across the knuckle line
    rad = [0.0093, 0.0098, 0.0092, 0.0081]
    tipl = [0.050, 0.056, 0.051, 0.041]                                      # middle + end phalanx
    prox = np.linalg.norm(rig.head(tb) - rig.head(fb))                       # first phalanx (the rig's fingers bone)
    back = 0.0048 * kh                                                       # fingers ride behind the joint line (see docstring)
    for f in range(4):
        r = rad[f] * kh * g
        x = fo[0] + xs[f] * kh
        tl = tipl[f] * kh
        # stations down the finger: (distance from the knuckle, radius scale, lean toward the palm, bone weights)
        st = [(-0.012 * kh, 1.04, 0.0, 'root'), (0.006 * kh, 1.10, 0.0, 'k0'), (prox * 0.5, 0.98, 0.0, 'p'), (prox - 0.007 * kh, 1.0, 0.0, 'p'),
              (prox, 1.07, 0.0, 'j'), (prox + 0.008 * kh, 0.98, 0.0, 't'), (prox + tl * 0.46, 0.93, 0.0015 * kh, 't'), (prox + tl * 0.56, 0.97, 0.0028 * kh, 't'),
              (prox + tl * 0.78, 0.88, 0.0075 * kh, 't'), (prox + tl * 0.93, 0.7, 0.0115 * kh, 't')]
        rings, wts = [], []
        for (d, rs, lean, tag) in st:
            c = rig.pt(hb, [x, kn_y - d, fo[2] + z * back - z * lean])
            rings.append(ellipse_ring(c, rig.vec(hb, [1, 0, 0]), rig.vec(hb, [0, 0, 1]), r * rs * 0.96, r * rs, 8, 2.2))
            wts.append(tag)
        tip = rig.pt(hb, [x, kn_y - (prox + tl), fo[2] + z * back - z * 0.0125 * kh])
        o = loft(f'{name}_f{f}', np.array(rings), caps=(True, False), coll=coll)
        # rounded finger tip: one more vertex fan
        V = np.vstack([verts_of(o), tip[None, :]])
        F = [list(p.vertices) for p in o.data.polygons]
        nb = (len(st) - 1) * 8
        for i in range(8):
            F.append((nb + i, nb + (i + 1) % 8, len(V) - 1))
        delete(o)
        o = new_mesh(f'{name}_f{f}', V, F, coll)
        recalc_normals(o)
        W = {hb: np.zeros(len(V)), fb: np.zeros(len(V)), tb: np.zeros(len(V))}
        for j, tag in enumerate(wts + ['t']):
            sl = slice(j * 8, j * 8 + 8) if j < len(wts) else slice(len(V) - 1, len(V))
            if tag == 'root':
                W[hb][sl] = 1.0
            elif tag == 'k0':
                W[hb][sl] = 0.45; W[fb][sl] = 0.55
            elif tag == 'p':
                W[fb][sl] = 1.0
            elif tag == 'j':
                W[fb][sl] = 0.5; W[tb][sl] = 0.5
            else:
                W[tb][sl] = 1.0
        set_weights(o, W)
        objs.append(o)
    # ---- thumb: from the rig's thumb bone, forward-down and slightly toward the palm, two phalanges ------------------------
    d0 = normalize(np.array([0.62, -0.76, -z * 0.2]))
    side_v = normalize(np.cross(d0, np.array([0, 0, 1.0])))
    up_v = np.cross(side_v, d0)
    tl1, tl2 = 0.036 * kh, 0.031 * kh
    tr = 0.0112 * kh * g
    st = [(-0.02 * kh, 1.25, 'root'), (-0.004 * kh, 1.12, 'k0'), (tl1 * 0.5, 0.98, 'p'), (tl1, 1.03, 'p'), (tl1 + tl2 * 0.5, 0.93, 'p'), (tl1 + tl2 * 0.88, 0.72, 'p')]
    rings = []
    for (d, rs, tag) in st:
        c = rig.pt(hb, to + d0 * d)
        rings.append(ellipse_ring(c, rig.vec(hb, side_v), rig.vec(hb, up_v), tr * rs, tr * rs * 0.9, 8, 2.2))
    o = loft(name + '_thumb', np.array(rings), caps=(True, False), coll=coll)
    tipp = rig.pt(hb, to + d0 * (tl1 + tl2))
    V = np.vstack([verts_of(o), tipp[None, :]])
    F = [list(p.vertices) for p in o.data.polygons]
    nb = (len(st) - 1) * 8
    for i in range(8):
        F.append((nb + i, nb + (i + 1) % 8, len(V) - 1))
    delete(o)
    o = new_mesh(name + '_thumb', V, F, coll)
    recalc_normals(o)
    W = {hb: np.zeros(len(V)), thb: np.zeros(len(V))}
    W[hb][0:8] = 1.0
    W[hb][8:16] = 0.5; W[thb][8:16] = 0.5
    W[thb][16:] = 1.0
    set_weights(o, W)
    objs.append(o)
    out = join(objs, name)
    shade(out)
    set_attr(out, 'ed_region', np.full(len(out.data.vertices), 3, dtype=np.int32), 'INT')
    return out


def keep_regions(obj, regions, name=None):
    """A copy of the body with only the listed ed_region values (0 torso, 1 head / neck, 2 arms, 3 hands, 4 legs, 5 feet)."""
    o = duplicate(obj, name or obj.name + '_vis')
    reg = get_attr(o, 'ed_region')
    keep = np.isin(reg, list(regions))
    _delete_verts(o, ~keep)
    return o


def _delete_verts(obj, mask):
    import bmesh
    bm = bmesh.new(); bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    dead = [bm.verts[int(i)] for i in np.nonzero(mask)[0]]
    bmesh.ops.delete(bm, geom=dead, context='VERTS')
    bm.to_mesh(obj.data); bm.free()
    obj.data.update()


def cull_hidden(obj, covers, margin=0.004, rays=None, keep=None):
    """
    Delete the faces of `obj` (usually the body) that are hidden under the `covers` (garments): a face goes when every
    vertex of it is covered — rays cast outward along the normal (and four tilted ones) all hit a cover within 6 cm.
    Saves triangles and removes poke-through. keep: (N,) boolean mask of vertices never deleted (neck, wrists).
    Returns the number of faces removed.
    """
    import bmesh
    from mathutils.bvhtree import BVHTree
    from mathutils import Vector
    from .core import normals_of, tris_of
    trees = []
    for c in covers:
        V = verts_of(c); T = tris_of(c)
        trees.append(BVHTree.FromPolygons([tuple(v) for v in V], [tuple(int(i) for i in t) for t in T]))
    P, N = verts_of(obj), normals_of(obj)
    n = len(P)
    hidden = np.zeros(n, dtype=bool)
    for i in range(n):
        nrm = N[i]
        ref = np.eye(3)[np.argmin(np.abs(nrm))]
        t1 = normalize(np.cross(nrm, ref)); t2 = np.cross(nrm, t1)
        dirs = [nrm] + [normalize(nrm + 0.7 * (math.cos(a) * t1 + math.sin(a) * t2)) for a in (0.4, 1.97, 3.54, 5.11)]
        ok = True
        o = Vector(P[i] + nrm * 0.0005)
        for d in dirs:
            hit = False
            for tr in trees:
                loc, nn, fi, dist = tr.ray_cast(o, Vector(d), 0.06)
                if loc is not None and dist > margin * 0.25:
                    hit = True; break
            if not hit:
                ok = False; break
        hidden[i] = ok
    if keep is not None:
        hidden &= ~np.asarray(keep, dtype=bool)
    bm = bmesh.new(); bm.from_mesh(obj.data)
    dead = [f for f in bm.faces if all(hidden[v.index] for v in f.verts)]
    cnt = len(dead)
    bmesh.ops.delete(bm, geom=dead, context='FACES')
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context='VERTS')
    bm.to_mesh(obj.data); bm.free()
    obj.data.update()
    return cnt
