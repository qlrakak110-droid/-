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


def body(rig, name='body', build=None, voxel=0.0065, tris=9000, hands=True, feet=True, coll=None, arm=None, cache=True, head=True):
    """
    The base body of a rig, skinned. Returns the mesh object (vertex groups = game bones incl. helper bones; attribute
    ed_region: 0 torso, 1 head / neck, 2 arms, 3 hands, 4 legs, 5 feet).
      build   overrides of DEFAULT_BUILD (mass, chest, waist, hips, arms, legs, neck, muscle, bust, hands)
      voxel   remesh size (m) before decimation
      tris    triangle budget of the fused body (the two hands add ~1.9k)
      arm     armature from build_armature (needed for skinning; without it the body is returned unskinned)
    The masses are signed-distance primitives in bone frames joined by smooth unions (ed/sdf.py): muscles flow into each
    other with fillets. Typical use: drape and skin garments against it, then keep only what shows (keep_regions /
    cull_hidden).
    """
    from .sdf import SDF
    B = {**DEFAULT_BUILD, **(build or {})}
    S = body_sdf(rig, B, feet=feet, head=head)
    obj = _cached_mesh(S, rig, B, voxel, name + '_fused', collection('_body_tmp'), cache)
    V = verts_of(obj)
    V[:, 2] = np.maximum(V[:, 2], 0.0015)                        # flat soles
    set_verts(obj, V)
    obj.data.calc_loop_triangles()
    n0 = len(obj.data.loop_triangles)
    if n0 > tris:
        dm = add_mod(obj, 'DECIMATE', decimate_type='COLLAPSE', ratio=tris / n0)
        dm.use_symmetry = True; dm.symmetry_axis = 'X'
        apply_mods(obj)
    smooth_mesh(obj, 0.2, 1)
    shade(obj)
    log(f'body: {n0} -> {len(obj.data.polygons)} faces')
    if arm is not None:
        SK.auto_skin(obj, arm, rig, helpers=True, smooth=2)
    _regions(obj, rig)
    if hands:
        hs = [hand(rig, s, name + '_hand' + s, B['hands']) for s in ('R', 'L')]
        obj = join([obj] + hs, name + '_all')
    out = obj
    out.name = name; out.data.name = name
    from .core import link
    link(out, coll)
    if arm is not None:
        SK.attach(out, arm)
    try:
        bpy.data.collections.remove(bpy.data.collections['_body_tmp'])
    except Exception:
        pass
    out['ed_sdf_eval'] = 1
    body.last_sdf = S
    return out


def _cached_mesh(S, rig, B, voxel, name, coll, cache):
    """The SDF meshing takes ~1 min: cache the fused mesh in build/blender-cache keyed by rig + build + body.py + sdf.py."""
    import hashlib, json
    from .core import ROOT, link
    h = hashlib.sha1()
    for p in (os.path.join(os.path.dirname(__file__), 'body.py'), os.path.join(os.path.dirname(__file__), 'sdf.py'), rig.path):
        with open(p, 'rb') as f:
            h.update(f.read())
    h.update(json.dumps([B, voxel], sort_keys=True).encode())
    path = os.path.join(ROOT, 'build', 'blender-cache', 'body_%s.npz' % h.hexdigest()[:16])
    if cache and os.path.exists(path):
        z = np.load(path)
        F = z['faces'].reshape(-1, 4)
        return new_mesh(name, z['verts'], [list(f) if f[3] >= 0 else list(f[:3]) for f in F], coll)
    obj = S.mesh(name, voxel=voxel, coll=coll)
    if cache:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        F = np.full((len(obj.data.polygons), 4), -1, dtype=np.int32)
        for i, p in enumerate(obj.data.polygons):
            vs = list(p.vertices)[:4]
            F[i, :len(vs)] = vs
        np.savez_compressed(path, verts=verts_of(obj).astype(np.float32), faces=F.reshape(-1))
    return obj


def body_sdf(rig, B=None, feet=True, head=True):
    """The anatomical signed-distance model of a rig's body (see body()). Returns an ed.sdf.SDF (eval / project / mesh)."""
    from .sdf import SDF
    B = {**DEFAULT_BUILD, **(B or {})}
    K = rig.K
    L = rig.data['lengths']
    P = rig.P
    m = B['mass']; mu = B['muscle']
    wc, ww, wh = B['chest'] * m, B['waist'] * m, B['hips'] * m
    sh = rig.local('chest', rig.head('upperArmR'))          # shoulder joint in the chest frame
    neck0 = rig.local('chest', rig.head('neck'))
    k = K
    S = SDF(rig)
    S.group('torso', 0.05 * k)
    # pelvis, abdomen, ribcage, upper chest, back
    S.ell('torso', 'hips', [-0.006 * k, -0.035 * k, 0], [0.098 * k * wh, 0.115 * k, 0.158 * k * wh])
    S.ell('torso', 'spine', [0.004 * k, 0.07 * k, 0], [0.098 * k * ww, 0.13 * k, 0.132 * k * ww])
    S.ell('torso', 'chest', [0.004 * k, 0.085 * k, 0], [0.112 * k * wc, 0.165 * k, 0.15 * k * wc])
    S.ell('torso', 'chest', [-0.012 * k, sh[1] - 0.025 * k, 0], [0.092 * k * wc, 0.075 * k, (abs(sh[2]) - 0.035 * k) * wc])
    S.cone('torso', 'chest', [-0.05 * k, -0.1 * k, 0], [-0.06 * k, sh[1] - 0.03 * k, 0], 0.07 * k, 0.07 * k, squash=[0.8, 1, 1.4])   # back muscles
    # pectorals (flat plates angled down-out), abdominal wall, obliques
    for z in (1.0, -1.0):
        ang = math.radians(-14 * z)
        rot = np.array([[1, 0, 0], [0, math.cos(ang), -math.sin(ang)], [0, math.sin(ang), math.cos(ang)]])
        S.ell('torso', 'chest', [0.072 * k * wc, sh[1] - 0.085 * k, z * 0.068 * k], [0.05 * k * (1 + 0.6 * B['bust']) * mu ** 0.5, 0.06 * k, 0.088 * k], rot=rot, k=0.03 * k)
        S.ell('torso', 'chest', [-0.035 * k, 0.07 * k, z * 0.11 * k * wc], [0.06 * k, 0.12 * k, 0.05 * k * m], k=0.04 * k)     # latissimus
        S.ell('torso', 'spine', [0.0, 0.0, z * 0.11 * k * ww], [0.07 * k, 0.09 * k, 0.04 * k], k=0.04 * k)                     # obliques / flank
        S.ell('torso', 'hips', [-0.068 * k, -0.085 * k, z * 0.07 * k * wh], [0.07 * k, 0.085 * k, 0.08 * k], k=0.04 * k)        # glutes
        S.cone('torso', 'chest', [neck0[0] - 0.03 * k, neck0[1] - 0.01 * k, z * 0.03 * k], [sh[0] - 0.02 * k, sh[1] + 0.015 * k, z * (abs(sh[2]) - 0.045 * k)],
               0.05 * k * m, 0.032 * k * m, k=0.04 * k)                                                                              # trapezius
        S.cone('torso', 'chest', [neck0[0] + 0.07 * k, neck0[1] - 0.03 * k, z * 0.02 * k], [sh[0] + 0.03 * k, sh[1] + 0.02 * k, z * (abs(sh[2]) - 0.03 * k)],
               0.012 * k, 0.012 * k, k=0.02 * k)                                                                                     # clavicle
    S.ell('torso', 'spine', [0.07 * k * ww, 0.04 * k, 0], [0.045 * k, 0.12 * k, 0.085 * k], k=0.04 * k)                             # rectus abdominis
    S.cut('torso', 'chest', 'cone', [0.125 * k, 0.04 * k, 0], [0.125 * k, sh[1] - 0.07 * k, 0], 0.012 * k, 0.012 * k, k=0.02 * k)  # sternal furrow
    S.cut('torso', 'chest', 'cone', [-0.115 * k, -0.12 * k, 0], [-0.105 * k, sh[1] - 0.04 * k, 0], 0.014 * k, 0.012 * k, k=0.025 * k)   # spine furrow
    # neck
    S.group('neck', 0.03 * k).blend('torso', 'neck', 0.045 * k)
    nk = B['neck']
    S.cone('neck', 'neck', [-0.004 * k, -0.015 * k, 0], [0.008 * k, 0.1 * k, 0], 0.06 * k * nk, 0.052 * k * nk, squash=[0.95, 1, 1.0])
    for z in (1.0, -1.0):   # sternocleidomastoid
        S.cone('neck', 'neck', [-0.012 * k, 0.085 * k, z * 0.042 * k], [0.05 * k, -0.01 * k, z * 0.022 * k], 0.016 * k * nk, 0.014 * k * nk, k=0.015 * k)
    if head:
        S.group('head', 0.02 * k).blend('neck', 'head', 0.03 * k).blend('torso', 'head', 0.0)
        S.ell('head', 'head', [-0.006 * k, 0.122 * k, 0], [0.098 * k, 0.104 * k, 0.078 * k])                   # cranium
        S.ell('head', 'head', [0.045 * k, 0.065 * k, 0], [0.06 * k, 0.07 * k, 0.058 * k], k=0.03 * k)          # face mass
        S.ell('head', 'head', [0.058 * k, 0.018 * k, 0], [0.04 * k, 0.03 * k, 0.05 * k], k=0.02 * k)           # jaw
        S.ell('head', 'head', [0.083 * k, 0.012 * k, 0], [0.022 * k, 0.025 * k, 0.026 * k], k=0.012 * k)       # chin
        S.ell('head', 'head', [0.087 * k, 0.137 * k, 0], [0.02 * k, 0.016 * k, 0.058 * k], k=0.014 * k)        # brow ridge
        S.cone('head', 'head', [0.101 * k, 0.118 * k, 0], [0.113 * k, 0.076 * k, 0], 0.007 * k, 0.0115 * k, k=0.01 * k)   # nose
        S.ell('head', 'head', [0.098 * k, 0.045 * k, 0], [0.012 * k, 0.012 * k, 0.026 * k], k=0.01 * k)       # lips
        for z in (1.0, -1.0):
            S.ell('head', 'head', [0.065 * k, 0.098 * k, z * 0.047 * k], [0.026 * k, 0.018 * k, 0.026 * k], k=0.014 * k)   # cheekbones
            S.ell('head', 'head', [-0.002 * k, 0.098 * k, z * 0.077 * k], [0.016 * k, 0.028 * k, 0.009 * k], k=0.006 * k)  # ears
            S.cut('head', 'head', 'ell', [0.106 * k, 0.117 * k, z * 0.034 * k], [0.011 * k, 0.0105 * k, 0.017 * k], k=0.01 * k)   # eye sockets
        S.group('eyes', 0.003 * k).blend('head', 'eyes', 0.004 * k)
        for z in (1.0, -1.0):
            S.ell('eyes', 'head', [0.09 * k, 0.116 * k, z * 0.034 * k], [0.0125 * k, 0.0125 * k, 0.0125 * k])                 # eyeballs
    # arms
    a = B['arms'] * m
    for s, z in (('R', 1.0), ('L', -1.0)):
        ua, fa, hb = 'upperArm' + s, 'foreArm' + s, 'hand' + s
        Lu, Lf = L['upperArm'], L['foreArm']
        g = 'arm' + s
        S.group(g, 0.022 * k).blend('torso', g, 0.035 * k)
        S.chain(g, ua, [(0.01, 0.046 * k * a), (-0.4 * Lu, 0.043 * k * a), (-0.98 * Lu, 0.036 * k * a)])
        S.ell(g, ua, [-0.004 * k, -0.045 * k, 0.004 * z * k], [0.058 * k * a, 0.09 * k, 0.056 * k * a], k=0.03 * k)          # deltoid
        S.ell(g, ua, [0.022 * k, -0.52 * Lu, 0], [0.032 * k * a * mu ** 0.5, 0.085 * k, 0.034 * k * a], k=0.02 * k)            # biceps
        S.ell(g, ua, [-0.022 * k, -0.42 * Lu, 0], [0.033 * k * a * mu ** 0.5, 0.1 * k, 0.037 * k * a], k=0.02 * k)            # triceps
        S.ell(g, fa, [-0.022 * k, 0.004 * k, 0], [0.018 * k, 0.024 * k, 0.019 * k], k=0.012 * k)                              # olecranon
        S.chain(g, fa, [(0.0, 0.037 * k * a), (-0.3 * Lf, 0.036 * k * a), (-0.97 * Lf, 0.0235 * k * a)], squash=[1.0, 1, 0.82])
        S.ell(g, fa, [0.012 * k, -0.2 * Lf, z * 0.012 * k], [0.03 * k * a, 0.085 * k, 0.03 * k * a], k=0.02 * k)            # brachioradialis / flexors
        S.ell(g, fa, [-0.012 * k, -0.24 * Lf, -z * 0.01 * k], [0.026 * k * a, 0.09 * k, 0.027 * k * a], k=0.02 * k)          # extensors
        S.cone(g, fa, [0, -0.9 * Lf, 0], [0, -1.0 * Lf - 0.012 * k, 0], 0.022 * k * a, 0.021 * k * a, squash=[1.25, 1, 0.8], k=0.012 * k)  # wrist
    # legs
    gl = B['legs'] * m
    for s, z in (('R', 1.0), ('L', -1.0)):
        th, sn, ft, toe = 'thigh' + s, 'shin' + s, 'foot' + s, 'toe' + s
        Lt, Ls = L['thigh'], L['shin']
        g = 'leg' + s
        S.group(g, 0.025 * k).blend('torso', g, 0.05 * k)
        S.chain(g, th, [(0.04, 0.084 * k * gl), (-0.35 * Lt, 0.074 * k * gl), (-0.98 * Lt, 0.05 * k * gl)])
        S.ell(g, th, [0.03 * k, -0.42 * Lt, 0.004 * z * k], [0.052 * k * gl, 0.19 * k, 0.06 * k * gl], k=0.03 * k)          # quadriceps
        S.ell(g, th, [0.022 * k, -0.8 * Lt, -z * 0.03 * k], [0.035 * k * gl, 0.065 * k, 0.034 * k * gl], k=0.02 * k)        # vastus medialis
        S.ell(g, th, [0.012 * k, -0.62 * Lt, z * 0.04 * k], [0.034 * k * gl, 0.13 * k, 0.03 * k * gl], k=0.025 * k)         # vastus lateralis
        S.ell(g, th, [-0.03 * k, -0.45 * Lt, 0], [0.05 * k * gl, 0.18 * k, 0.055 * k * gl], k=0.03 * k)                     # hamstrings
        S.ell(g, sn, [0.04 * k, 0.004 * k, 0], [0.02 * k, 0.032 * k, 0.027 * k], k=0.012 * k)                               # patella
        S.chain(g, sn, [(0.0, 0.05 * k * gl), (-0.25 * Ls, 0.043 * k * gl), (-0.97 * Ls, 0.029 * k * gl)])
        S.ell(g, sn, [-0.03 * k, -0.27 * Ls, z * 0.012 * k], [0.042 * k * gl, 0.11 * k, 0.034 * k * gl], k=0.025 * k)        # calf (outer)
        S.ell(g, sn, [-0.028 * k, -0.24 * Ls, -z * 0.016 * k], [0.04 * k * gl, 0.12 * k, 0.034 * k * gl], k=0.025 * k)      # calf (inner)
        S.cone(g, sn, [0.028 * k, -0.05 * Ls, 0], [0.024 * k, -0.85 * Ls, 0], 0.016 * k, 0.012 * k, k=0.02 * k)             # tibia ridge
        if feet:
            ah, fl, fd, tl, hl = P['ankleHeight'], P['footLength'], P['footDrop'], P['toeLength'], P['heelLength']
            S.ell(g, ft, [0.0, 0.004 * k, z * 0.028 * k], [0.013 * k, 0.015 * k, 0.012 * k], k=0.01 * k)                     # malleoli
            S.ell(g, ft, [0.0, 0.012 * k, -z * 0.027 * k], [0.013 * k, 0.015 * k, 0.011 * k], k=0.01 * k)
            S.ell(g, ft, [-hl * 0.42, -ah * 0.55, 0], [hl * 0.62, ah * 0.48, 0.033 * k], k=0.02 * k)                          # heel
            S.cone(g, ft, [0.0, -ah * 0.2, 0], [fl * 0.88, -fd - 0.002 * k, -z * 0.003 * k], 0.033 * k, 0.026 * k, squash=[1, 0.75, 1.3], k=0.02 * k)  # instep
            S.ell(g, ft, [fl * 0.88, -fd + 0.002 * k, -z * 0.004 * k], [0.035 * k, 0.024 * k, 0.045 * k], k=0.015 * k)        # ball
            S.ell(g, toe, [tl * 0.42, -0.003 * k, 0], [tl * 0.6, 0.017 * k, 0.041 * k], k=0.012 * k)                         # toes
    return S


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
