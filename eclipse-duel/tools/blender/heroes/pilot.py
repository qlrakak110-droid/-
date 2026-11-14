# Pipeline pilot on VORN's rig (+ a queue spring chain: src/char/asset_pilot.js): a soldier-monk spearman built
# entirely through edlib. Base body, robe with a crossed collar, split skirt draped by the cloth solver and bound to the
# rig's cloth panels, lamellar cuirass + left shoulder piece laced in old gold, conical woven bamboo hat, cloth face
# wrap, hair queue on spring bones, wrapped forearms and shins, trousers, boots, and the spear.
#
#   /opt/blender-env/venv/bin/python tools/blender/heroes/pilot.py [--stage N] [--no-preview] [--save]
#   -> assets/chars/pilot/ (pilot.edm, pilot.json, index.js) + shots/blender/pilot/*.png

import os
import sys
import time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import numpy as np
import edlib as ed

ARGS = sys.argv[1:]
STAGE = int(ARGS[ARGS.index('--stage') + 1]) if '--stage' in ARGS else 99
PREVIEW = '--no-preview' not in ARGS
HERO = 'pilot'
T0 = time.time()

ed.reset_scene()
rig = ed.Rig(HERO)
arm = ed.build_armature(rig)
K = rig.K
Lu, Lf, Lt, Ls = (rig.data['lengths'][k] for k in ('upperArm', 'foreArm', 'thigh', 'shin'))
P = rig.pt

# ---- looks: storm violet, ink black, old gold (linear colours) ------------------------------------------------------------
LK = {
    'skin': ed.look('skin', color=(0.2, 0.12, 0.08), rough=0.6, set='leather', amt=0.15),
    'robe': ed.look('robe', color=(0.05, 0.02, 0.09), rough=0.6, set='silk', amt=0.9),               # storm-violet silk
    'robeIn': ed.look('robeIn', color=(0.012, 0.011, 0.014), rough=0.85, set='hemp', amt=0.8),       # ink-black hemp lining / under-layer
    'collar': ed.look('collar', color=(0.01, 0.009, 0.012), rough=0.55, set='silk', amt=0.8),        # black lapel band
    'dongjeong': ed.look('dongjeong', color=(0.42, 0.4, 0.36), rough=0.7, set='silk', amt=0.6),      # pale inner collar strip
    'trim': ed.look('trim', color=(0.03, 0.012, 0.05), rough=0.5, set='brocade', amt=1.0),           # thunder brocade, old-gold thread
    'sash': ed.look('sash', color=(0.016, 0.014, 0.018), rough=0.8, set='hemp', amt=0.9),
    'trousers': ed.look('trousers', color=(0.018, 0.017, 0.022), rough=0.88, set='hemp', amt=1.0),
    'wrap': ed.look('wrap', color=(0.12, 0.1, 0.075), rough=0.9, set='hemp', amt=1.0),               # undyed hemp wraps
    'leather': ed.look('leather', color=(0.02, 0.016, 0.014), rough=0.58, set='leather', amt=1.0),
    'lamellar': ed.look('lamellar', color=(0.014, 0.012, 0.016), rough=0.3, set='lacquer', amt=1.0, wear=0.35),   # black lacquered plates
    'lace': ed.look('lace', color=(0.32, 0.2, 0.055), rough=0.6, set='hemp', amt=0.6, vein=0.12),               # old-gold lacing
    'bamboo': ed.look('bamboo', color=(0.1, 0.068, 0.032), rough=0.45, set='hemp', amt=0.35),
    'bambooDark': ed.look('bambooDark', color=(0.045, 0.032, 0.02), rough=0.5, set='hemp', amt=0.5),
    'hair': ed.look('hair', color=(0.012, 0.011, 0.012), rough=0.42, set='hair', amt=1.0),
    'shaft': ed.look('shaft', color=(0.032, 0.027, 0.03), rough=0.3, set='lacquer', amt=0.8),
    'bronze': ed.look('bronze', color=(0.42, 0.27, 0.11), rough=0.36, metal=1.0, set='bronze', amt=0.9),
    'steel': ed.look('steel', color=(0.2, 0.21, 0.25), rough=0.22, metal=1.0, set='blade', amt=1.0),
    'horsehair': ed.look('horsehair', color=(0.07, 0.02, 0.11), rough=0.5, set='hair', amt=1.0),     # violet-dyed horsehair
    'eye': ed.look('eye', color=(0.02, 0.016, 0.03), rough=0.6, set='hammered', amt=0.0, eye=1.0, emission=(0.7, 0.55, 1.0)),
}
MOTIF_THUNDER = 6

def orient_out(obj, axis_pts):
    """Make an open garment sheet's faces point away from its axis (the lining then goes inside)."""
    V, N = ed.verts_of(obj), ed.normals_of(obj)
    k, c, _ = ed.skin.path_param(V, np.asarray(axis_pts))
    if float(np.mean(np.einsum('ij,ij->i', N, V - c))) < 0:
        import bmesh
        bm = bmesh.new(); bm.from_mesh(obj.data)
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
        bm.to_mesh(obj.data); bm.free(); obj.data.update()
    return obj


# ---- 1. base body ---------------------------------------------------------------------------------------------------------------
body = ed.body(rig, arm=arm, tris=12000)
S = ed.body.last_sdf
S_torso = S.subset(['torso', 'neck'])
ed.assign_look(body, LK['skin'])
ed.log('body', ed.tri_count(body), ed.weight_report(body))

# ---- 2. robe: torso shell, sleeves -------------------------------------------------------------------------------------------
sh = rig.local('chest', rig.head('upperArmR'))
top = P('chest', [-0.01, sh[1] + 0.075, 0])
waist = P('hips', [0.0, -0.02, 0])
ax = ed.ring_axis([top, P('chest', [0.0, sh[1] - 0.05, 0]), P('chest', [0.01, 0.05, 0]), P('spine', [0.012, 0.05, 0]), waist], 30)
# looseness: more over the belly and the back (the robe blouses above the sash), tight at the collar
ease = lambda u, v: 0.004 + 0.012 * ed.smoothstep(0.15, 0.8, v) * (0.6 + 0.4 * np.cos(u * 2 * np.pi) ** 2)
robe = ed.wrap('robe_torso', S_torso, ax, n=56, offset=0.009, ease=ease)
ed.wrinkle(robe, amount=0.0025, scale=22, seed=3)
ed.push_out(robe, S, 0.006)
ed.assign_look(robe, LK['robe'])

sleeves = []
for s in ('R', 'L'):
    sa = ed.ring_axis([P('upperArm' + s, [-0.005, 0.045, 0]), P('upperArm' + s, [0, -0.5 * Lu, 0]), P('foreArm' + s, [0, 0, 0]),
                       P('foreArm' + s, [0, -0.55 * Lf, 0])], 22)
    # loose upper sleeve bunching toward the elbow, gathered under the forearm wrap
    sl_off = lambda u, v: 0.012 + 0.016 * np.sin(np.clip(v, 0, 1) * np.pi * 0.95) ** 1.2 - 0.008 * ed.smoothstep(0.8, 1.0, v)
    sv = ed.wrap('sleeve' + s, S.subset(['arm' + s]), sa, n=28, offset=sl_off, rmax=0.2, min_r=lambda v: 0.072 - 0.05 * min(1.0, v * 3))
    ed.wrinkle(sv, amount=0.004, scale=26, seed=11 if s == 'R' else 12, stretch=(1.0, 1.0, 1.0))
    ed.push_out(sv, S, 0.005)
    ed.assign_look(sv, LK['robe'])
    sleeves.append(sv)



def thick(obj, t, inner=None, offset=-1.0):
    """Solidify a sheet; the inner shell takes the `inner` look (lining)."""
    if inner is not None:
        obj.data.materials.append(inner)
    ed.add_mod(obj, 'SOLIDIFY', thickness=t, offset=offset, use_rim=True, use_even_offset=False, use_quality_normals=True, material_offset=1 if inner is not None else 0)
    return ed.apply_mods(obj)


def stage_done(n, name):
    if STAGE <= n:
        for o in ed.bpy.context.scene.objects:
            if o.type == 'MESH':
                V = ed.verts_of(o)
                if len(V):
                    print('BBOX', o.name, np.round(V.min(0), 3), np.round(V.max(0), 3), len(V))
        if PREVIEW:
            ed.preview_sheet(HERO, name, height=2.25, samples=10)
        ed.log('stage', n, 'done', round(time.time() - T0, 1), 's')
        sys.exit(0)


def limb_radius(Ssub, a, b, e1, e2, ts, n=24):
    """Mean body radius around the segment a -> b at parameters ts (for wraps)."""
    A = np.linspace(0, 2 * np.pi, n, endpoint=False)
    return [[t, float(np.mean(ed.body_radius(Ssub, a + (b - a) * t, e1, e2, A, rmax=0.2)))] for t in ts]


stage_done(2, 'stage2')

# ---- 3. crossed collar, trousers, skirt, sash, wraps, boots ------------------------------------------------------------------------
SR = ed.grid_surface(robe, 0.0)


def surf_path(Sf, uv, n=24, lift=0.0):
    """Points + normals along a (u, v) polyline on a parametric surface."""
    UV = ed.polyline(np.array([[u, v, 0.0] for u, v in uv]), n)
    pts, nrm = [], []
    for u, v, _ in UV:
        p, nn, tu, tv = ed.surface_normal(Sf, u, v)
        pts.append(p + nn * lift); nrm.append(nn)
    return np.array(pts), np.array(nrm)


# the top lapel crosses from the hero's left shoulder to his right hip (left over right); the under lapel shows in the V
LAP_TOP = [(0.5, 0.0), (0.36, 0.0), (0.24, 0.015), (0.13, 0.06), (0.06, 0.2), (-0.01, 0.37), (-0.08, 0.58), (-0.13, 0.8), (-0.165, 0.99)]
LAP_UND = [(0.5, 0.0), (0.64, 0.0), (0.76, 0.015), (0.87, 0.06), (0.94, 0.2), (1.01, 0.36), (1.06, 0.5)]
collar = []
neck_pt = P('neck', [0.0, 0.03, 0])
for nm, path, lift in (('lapelU', LAP_UND, 0.003), ('lapelT', LAP_TOP, 0.007)):
    pts, nrm = surf_path(SR, path, 40, lift)
    lap = ed.ribbon(nm, pts, width=0.072, normal=nrm, camber=0.12, nu=4)
    thick(lap, 0.005, offset=0.0)
    ed.assign_look(lap, LK['collar'])
    collar.append(lap)
    # the pale inner-collar strip (동정) on the neck edge, and the old-gold trim on the outer edge
    T_ = np.gradient(pts, axis=0); side = ed.normalize(np.cross(T_, nrm))
    sgn = 1.0 if np.mean(np.linalg.norm(pts + side * 0.03 - neck_pt, axis=1)) < np.mean(np.linalg.norm(pts - side * 0.03 - neck_pt, axis=1)) else -1.0
    k = int(len(pts) * (0.42 if nm == 'lapelT' else 0.7))
    dj = ed.ribbon(nm + '_dj', pts[:k] + side[:k] * sgn * 0.026 + nrm[:k] * 0.0035, width=0.02, normal=nrm[:k], camber=0.3, nu=2)
    thick(dj, 0.003, offset=0.0)
    ed.assign_look(dj, LK['dongjeong'])
    collar.append(dj)
    tr = ed.ribbon(nm + '_trim', pts - side * sgn * 0.031 + nrm * 0.0032, width=0.011, normal=nrm, camber=0.2, nu=2, code=0.2)
    # brocade uv: u along the band in band widths, v across, code = motif + glow through the thread
    q = ed.get_attr(tr, 'ed_uvw'); Ltr = float(np.linalg.norm(np.diff(pts, axis=0), axis=1).sum())
    ed.set_attr(tr, 'ed_uvw', np.stack([q[:, 1] * Ltr / 0.011 * 0.5, q[:, 0], np.full(len(q), MOTIF_THUNDER + 0.15)], axis=1), 'FLOAT_VECTOR')
    thick(tr, 0.002, offset=0.0)
    ed.assign_look(tr, LK['trim'])
    collar.append(tr)

# trousers: loose hemp, gathered into the shin wraps
trousers = []
for s in ('R', 'L'):
    ta = ed.ring_axis([P('thigh' + s, [0.0, 0.0, 0]), P('thigh' + s, [0, -0.5 * Lt, 0]), P('shin' + s, [0, 0, 0]), P('shin' + s, [0, -0.62 * Ls, 0])], 22)
    tro = ed.wrap('trousers' + s, S.subset(['leg' + s]), ta, n=26, offset=lambda u, v: 0.016 + 0.008 * np.sin(np.clip(v, 0, 1) * np.pi) - 0.006 * ed.smoothstep(0.6, 1.0, v), rmax=0.3)
    ed.wrinkle(tro, amount=0.004, scale=22, seed=21 if s == 'R' else 22, stretch=(1.0, 1.0, 0.6))
    ed.push_out(tro, S, 0.006)
    ed.assign_look(tro, LK['trousers'])
    trousers.append(tro)

# skirt: front panel + two back panels (split for riding and fighting), overlapping at the sides, draped by the solver
S_skirt = S.subset(['torso', 'legR', 'legL'])
hem_z = 0.36
c0 = P('hips', [0.0, 0.055, 0])
sk_axis = ed.ring_axis([c0, np.array([c0[0], c0[1] - 0.01, (c0[2] + hem_z) / 2]), np.array([c0[0], c0[1] - 0.02, hem_z])], 26)
flare = lambda u, v: 0.045 + 0.12 * v ** 1.15 + 0.02 * np.cos(u * 2 * np.pi) ** 2 * v
skirt = []
for nm, arc_, n_ in (('skirtF', (-0.25, 0.25), 40), ('skirtBL', (0.21, 0.52), 26), ('skirtBR', (0.48, 0.79), 26)):
    sk = ed.wrap(nm, S_skirt, sk_axis, n=n_, offset=flare, arc=arc_, rmax=0.5)
    ed.pleats(sk, count=22, depth=0.011, grow=(0.0, 1.0), phase=0.13 if nm == 'skirtF' else 0.0)
    skirt.append(sk)
# the drape collider is the convex hull of hips + legs (a skirt spans the gap between the legs, it does not fall into it)
legs_hull = ed.wrap('_legs_hull', S_skirt, ed.ring_axis([c0, np.array([c0[0], c0[1], 0.25])], 20), n=48, offset=0.014)
orient_out(legs_hull, [c0, np.array([c0[0], c0[1], 0.25])])     # Blender's collision keeps cloth on the normal side
for sk in skirt:
    ed.drape(sk, [legs_hull], pin=lambda q, Pp: 1 - ed.smoothstep(0.06, 0.16, q[:, 1]), frames=12, mass=0.3, tension=25, bending=6.0, thickness=0.006)
ed.remove_colliders([legs_hull])
ed.delete(legs_hull)
SKIRT_BONES = ['hips', 'spine', 'thighR', 'thighL', 'hipJointR', 'hipJointL', 'thighTwistR', 'thighTwistL']
for sk in skirt:
    ed.push_out(sk, S, 0.012)
    ed.wrinkle(sk, amount=0.0025, scale=30, seed=5, stretch=(1.0, 1.0, 0.2))
    ed.hem(sk, 'v1', 0.022, 0.0025)
    # runtime cloth: a verlet panel defined FROM the drape (the game's cloth starts where Blender left it); the upper
    # skirt rides the hips / thighs by weights, the lower part is handed to the panel's particle bones
    n_, r_ = sk['ed_grid']
    G = ed.verts_of(sk)[: n_ * r_].reshape(r_, n_, 3)
    if G[0, 0, 0] < G[0, -1, 0]:
        G = G[:, ::-1]
    pan = ed.define_panel(sk.name, G, anchor='hips', rig=rig, cols=6 if sk.name == 'skirtF' else 4, rows=9,
                          damping=0.045, margin=0.02, thickness=0.01, wind=0.7, stretch=1.0, bend=0.35)
    ed.transfer_weights(body, sk, arm, smooth=2, bones=SKIRT_BONES)
    ed.bind_panel(sk, pan, share=lambda u, v: ed.smoothstep(0.1, 0.42, v))
    ed.assign_look(sk, LK['robe'])
    orient_out(sk, sk_axis)
    thick(sk, 0.004, inner=LK['robeIn'])

# sash: a wide band of black hemp at the waist, knotted at the front left with two hanging ends
sa_axis = ed.ring_axis([P('hips', [0.0, 0.1, 0]), P('hips', [0.0, 0.0, 0])], 5)
sash = ed.wrap('sash', S_torso, sa_axis, n=56, offset=0.05)
ed.wrinkle(sash, amount=0.002, scale=40, seed=8, stretch=(1, 1, 0.3))
thick(sash, 0.006, offset=1.0)
ed.assign_look(sash, LK['sash'])
SS = ed.grid_surface(sash, 0.008)
kp, kn, _, _ = ed.surface_normal(SS, 0.11, 0.5)
knot = ed.knot('sash_knot', kp + kn * 0.01, size=0.07, facing=kn, up=(0, 0, 1))
ed.assign_look(knot, LK['sash'])
SF = ed.grid_surface(skirt[0], 0.012)
ends = []
for k_, (u0, ln, w) in enumerate(((0.12, 0.42, 0.06), (0.15, 0.34, 0.052))):
    pts, nrm = surf_path(SF, [(u0, 0.08), (u0 + 0.01, 0.3), (u0 + 0.02, 0.3 + ln * 1.4)], 16, 0.008 + 0.004 * k_)
    pts = np.vstack([kp + kn * 0.012, pts])
    nrm = np.vstack([kn, nrm])
    e = ed.ribbon('sash_end%d' % k_, pts, width=[[0, w * 0.6], [0.2, w], [1, w * 0.92]], normal=nrm, camber=0.1, nu=3)
    thick(e, 0.004, offset=0.0)
    ed.assign_look(e, LK['sash'])
    ends.append(e)
# a fringe of old-gold thunder trim along each hem of the sash ends
sash_all = ed.join([sash, knot], 'sash')
# the hanging ends lie on the front skirt panel: they take its skin weights and its runtime cloth binding
pF = ed.skin.PANELS['skirtF']
for e in ends:
    ed.transfer_weights(body, e, arm, smooth=1, bones=SKIRT_BONES)
    ed.bind_panel(e, pF, share=lambda u, v: ed.smoothstep(0.1, 0.42, v))
skirt[0] = ed.join([skirt[0]] + ends, 'skirtF')

# forearm and shin wraps (undyed hemp), boots
wraps = []
for s in ('R', 'L'):
    fa = 'foreArm' + s
    a, b = P(fa, [0, -0.36 * Lf, 0]), P('hand' + s, [0, -0.012, 0])
    e1, e2 = rig.vec(fa, [1, 0, 0]), rig.vec(fa, [0, 0, 1])
    rad = limb_radius(S.subset(['arm' + s]), a, b, e1, e2, [0, 0.35, 0.7, 1.0])
    rad = [[t, r + 0.004] for t, r in rad]
    w = ed.helix_wrap('wrapA' + s, a, b, rad, turns=9, width=0.03, thick=0.0016, sides=12, axes=(e1, e2), seed=31 if s == 'R' else 32)
    ed.assign_look(w, LK['wrap'])
    wraps.append(w)
    # the wrap continues over the palm to the knuckles (fingers and thumb stay free to close on the haft)
    hb = 'hand' + s
    hz = 0.003 * (1 if s == 'R' else -1)
    w = ed.helix_wrap('wrapH' + s, P(hb, [0, 0.012, hz]), P(hb, [0.004, -0.058, hz]), [[0, 0.031], [0.5, 0.039], [1, 0.044]], turns=4, width=0.026,
                      thick=0.0015, sides=14, ellipse=0.42, axes=(rig.vec(hb, [1, 0, 0]), rig.vec(hb, [0, 0, 1])), seed=33 if s == 'R' else 34)
    ed.assign_look(w, LK['wrap'])
    wraps.append(w)
    sn = 'shin' + s
    a, b = P(sn, [0, -0.36 * Ls, 0]), P('foot' + s, [0, 0.015, 0])
    e1, e2 = rig.vec(sn, [1, 0, 0]), rig.vec(sn, [0, 0, 1])
    rad = limb_radius(S.subset(['leg' + s]), a, b, e1, e2, [0, 0.3, 0.6, 0.85, 1.0])
    rad = [[t, r + (0.015 if t < 0.1 else 0.008)] for t, r in rad]
    w = ed.helix_wrap('wrapL' + s, a, b, rad, turns=10, width=0.036, thick=0.0018, sides=12, axes=(e1, e2), seed=41 if s == 'R' else 42)
    ed.assign_look(w, LK['wrap'])
    wraps.append(w)
boots = ed.keep_regions(body, [5], 'boots')
ed.displace(boots, lambda Pp, Nn: np.full(len(Pp), 1.0), 0.0075)
Vb = ed.verts_of(boots); Vb[:, 2] = np.maximum(Vb[:, 2], 0.0); ed.set_verts(boots, Vb)
boots.data.materials.clear()
ed.assign_look(boots, LK['leather'])

stage_done(3, 'stage3')

# ---- 4. lamellar cuirass + left shoulder piece, hat, face wrap, hair, queue, spear --------------------------------------------------
SL = ed.grid_surface(robe, 0.012)
plates, lace = ed.lamellar('lamellar', SL, rows=8, cols=36, thick=0.0028, dome=0.0018, overlap=0.3, row_overlap=0.28, v_range=(0.2, 0.9),
                           lace_r=0.0014, closed=True, lod=0)
ed.assign_look(plates, LK['lamellar'])
ed.assign_look(lace, LK['lace'])
SV = ed.grid_surface(sleeves[1], 0.014)
splates, slace = ed.lamellar('shoulderL', SV, rows=4, cols=9, thick=0.0028, dome=0.002, overlap=0.3, row_overlap=0.3, u_range=(0.02, 0.5),
                             v_range=(0.0, 0.42), lace_r=0.0014, lod=0)
ed.assign_look(splates, LK['lamellar'])
ed.assign_look(slace, LK['lace'])
# the shoulder piece hangs from a leather strap over the collar
st_pts, st_n = surf_path(SR, [(0.33, 0.05), (0.27, 0.0), (0.2, 0.02)], 10, 0.01)
strap = ed.ribbon('shoulder_strap', np.vstack([st_pts, ed.surface_normal(SV, 0.25, 0.0)[0][None, :]]), width=0.028,
                  normal=np.vstack([st_n, st_n[-1:]]), nu=2)
thick(strap, 0.004, offset=0.0)
ed.assign_look(strap, LK['leather'])

# conical bamboo hat (삿갓): real over-under plait of split bamboo over a dark lining, bound rim, finial, headband, chin cords
hat_up = rig.vec('head', [0, 1, 0])
apex = P('head', [0.006, 0.405, 0])
Hs = ed.cone_surface(apex, hat_up, 0.31, 0.25, bell=0.82, v0=0.035)
weave = ed.weave('hat_weave', Hs, 40, 13, thick=0.0011, lift=0.0013, pattern=(2, 2), sub=2, across=2)
ed.assign_look(weave, LK['bamboo'])
lining = ed.lathe('hat_lining', [[0.31 * (0.035 + 0.965 * v) - 0.0005, 0.25 * (0.035 + 0.965 * v) ** 0.82 + 0.0035] for v in np.linspace(0, 1, 9)], 48,
                  origin=apex, axis=-hat_up)
ed.assign_look(lining, LK['bambooDark'])
rim = ed.tube('hat_rim', [Hs(u, 1.0) - hat_up * 0.0015 for u in np.linspace(0, 1, 65)], 0.0055, 7, caps=False)
rim_wrap = ed.helix_wrap('hat_rimwrap', apex - hat_up * 0.0, apex - hat_up * 0.001, 0.01, turns=1)  # placeholder (replaced below)
ed.delete(rim_wrap)
fin = ed.lathe('hat_finial', [[0.0, 0.03], [0.012, 0.024], [0.016, 0.012], [0.011, 0.0], [0.014, -0.012]], 12, origin=apex - hat_up * 0.014, axis=hat_up, caps=(True, False))
hb_c = P('head', [-0.005, 0.18, 0])
band = ed.lathe('hat_band', [[0.098, 0.0], [0.101, 0.012], [0.098, 0.024]], 32, origin=hb_c, axis=hat_up)
ed.assign_look(rim, LK['bambooDark']); ed.assign_look(fin, LK['bronze']); ed.assign_look(band, LK['leather'])
cords = []
for z in (1.0, -1.0):
    cp = [P('head', [0.0, 0.19, z * 0.1]), P('head', [0.02, 0.12, z * 0.088]), P('head', [0.05, 0.05, z * 0.07]), P('head', [0.075, 0.0, z * 0.035])]
    cords.append(ed.tube('hat_cord' + ('R' if z > 0 else 'L'), ed.polyline(np.array(cp), 14), 0.0028, 6))
for c in cords:
    ed.assign_look(c, LK['lace'])
# game mesh: a smooth cone at the weave's mid-surface carrying the weave as baked maps (object-space normal, AO, strip
# tones): ~0.9k triangles instead of the plait's ~10k
prof = [[0.31 * (0.035 + 0.965 * v), 0.25 * (0.035 + 0.965 * v) ** 0.82] for v in np.linspace(0, 1, 12)]
hat_low = ed.lathe('hat_low', prof, 48, origin=apex, axis=-hat_up, a1=359.999)
ed.recalc_normals(hat_low)
Vh, Nh = ed.verts_of(hat_low), ed.normals_of(hat_low)
if float(np.mean(np.einsum('ij,ij->i', Nh, Vh - apex) * 0 + Nh @ hat_up)) < 0:
    ed.recalc_normals(hat_low, inside=True)
ed.uv_from_grid(hat_low)
ed.assign_look(hat_low, LK['bamboo'])
HAT_MAPS = ed.bake_object_maps([weave], hat_low, size=(1024, 512), name='pilot_hat', out_dir=os.path.join(ed.ROOT, 'build', 'bake', 'pilot'))
hat_low['ed_maps'] = 'pilot_hat'
ed.delete(weave)
for o_ in [lining, rim, fin, band] + cords:
    ed.set_attr(o_, 'ed_bakew', np.zeros(len(o_.data.vertices), dtype=np.float32))
hat = ed.join([hat_low, lining, rim, fin, band] + cords, 'hat')
hat['ed_maps'] = 'pilot_hat'

# cloth face wrap from the bridge of the nose to the collar, with a tied tail at the nape
S_head = S.subset(['head', 'neck', 'eyes'])
fw_axis = ed.ring_axis([P('head', [0.012, 0.1, 0]), P('head', [0.0, 0.0, 0]), P('neck', [0.0, 0.03, 0])], 16)
bridge = lambda u, v: 0.008 + 0.024 * ed.smoothstep(0.25, 0.75, v) * np.cos(u * np.pi * 2).clip(0, 1) ** 2
face = ed.wrap('facewrap', S_head, fw_axis, n=48, offset=bridge, rmax=0.25)
ed.wrinkle(face, amount=0.003, scale=34, seed=51, stretch=(0.3, 0.3, 1.0))
ed.push_out(face, S, 0.006)
ed.hem(face, 'v0', 0.01, 0.0018)
ed.assign_look(face, LK['robeIn'])
nape = P('head', [-0.088, 0.05, 0])
tails = []
for k_, (zz, ln) in enumerate(((0.02, 0.2), (-0.03, 0.16))):
    tp = np.array([nape, nape + rig.vec('head', [-0.03, -0.06, zz]), nape + rig.vec('head', [-0.04, -0.06 - ln, zz * 1.5])])
    t_ = ed.ribbon('facewrap_tail%d' % k_, ed.polyline(tp, 10), width=[[0, 0.03], [1, 0.042]], normal=rig.vec('head', [-1, 0, 0]), camber=0.15, nu=2)
    thick(t_, 0.003, offset=0.0)
    ed.assign_look(t_, LK['robeIn'])
    tails.append(t_)
fknot = ed.knot('facewrap_knot', nape + rig.vec('head', [-0.012, 0, 0]), size=0.035, facing=rig.vec('head', [-1, 0, 0]), up=(0, 0, 1))
ed.assign_look(fknot, LK['robeIn'])
facewrap = ed.join([face, fknot] + tails, 'facewrap')

# hair: combed-back cap under the hat and a long bound queue on the spring chain
hc_axis = ed.ring_axis([P('head', [-0.01, 0.2, 0]), P('head', [-0.01, 0.05, 0])], 10)
haircap = ed.wrap('haircap', S_head, hc_axis, n=36, offset=0.005, arc=(0.17, 0.83), rmax=0.2)
ed.wrinkle(haircap, amount=0.0018, scale=90, seed=61, stretch=(1.0, 1.0, 0.12), ridged=True)
ed.assign_look(haircap, LK['hair'])
qp = rig.chain_points('queue')
qp = np.vstack([P('head', [-0.085, 0.1, 0]), qp[1:]])
queue = ed.braid('queue', qp, width=0.03, thickness=0.022, pitch=0.042, taper=0.55)
ed.assign_look(queue, LK['hair'])
qtie = ed.lathe('queue_tie', [[0.017, 0.0], [0.019, 0.01], [0.019, 0.03], [0.017, 0.04]], 12, origin=qp[0] + (qp[1] - qp[0]) * 0.18, axis=ed.normalize(qp[1] - qp[0]))
ed.assign_look(qtie, LK['trim'])
qend = ed.tassel('queue_end', qp[-1] - ed.normalize(qp[-1] - qp[-2]) * 0.02, direction=ed.normalize(qp[-1] - qp[-2]), length=0.1, radius=0.011, strands=9)
ed.assign_look(qend, LK['hair'])

# the spear, in the weapon bone's frame (x along the haft): EXACT current length, butt -0.975 .. tip 1.5
W = rig.weapon(0)
wb = 'weaponR'
wx = rig.vec(wb, [1, 0, 0]); wy = rig.vec(wb, [0, 1, 0]); wz = rig.vec(wb, [0, 0, 1])
o = P(wb, [0, 0, 0])
X0, XB, XT = W['extent']['min'][0], W['base'][0], W['tip'][0]
shaft = ed.lathe('spear_shaft', [[0.0, X0 + 0.04], [0.0150, X0 + 0.04], [0.0158, -0.6], [0.0158, 0.2], [0.0148, XB - 0.06], [0.014, XB - 0.03]], 14, origin=o, axis=wx)
ed.assign_look(shaft, LK['shaft'])
fit = [ed.lathe('spear_butt', [[0.0, X0], [0.012, X0 + 0.002], [0.0172, X0 + 0.016], [0.0168, X0 + 0.05], [0.0182, X0 + 0.056], [0.0155, X0 + 0.062]], 14, origin=o, axis=wx, caps=(True, False))]
for x in (-0.66, -0.38, 0.14, 0.5):
    fit.append(ed.lathe('spear_band', [[0.0154, x - 0.012], [0.0176, x - 0.008], [0.0178, x + 0.008], [0.0154, x + 0.012]], 14, origin=o, axis=wx))
fit.append(ed.lathe('spear_socket', [[0.0146, XB - 0.065], [0.0172, XB - 0.06], [0.0168, XB - 0.02], [0.0186, XB - 0.012], [0.0186, XB - 0.004],
                                    [0.0135, XB + 0.004], [0.0115, XB + 0.03], [0.0128, XB + 0.04], [0.0095, XB + 0.05]], 14, origin=o, axis=wx))
for f in fit:
    ed.assign_look(f, LK['bronze'])
# crossguard: a short bronze bar with rolled ends across the blade plane
gx = XB + 0.012
guard = ed.sweep('spear_guard', np.array([o + wx * gx + wy * t for t in np.linspace(-0.07, 0.07, 9)]), 8, [[0, 0.007], [0.5, 0.011], [1, 0.007]], scale_y=0.6, up=wx)
gends = [ed.ellipsoid('spear_gend', o + wx * gx + wy * sg * 0.072, [0.009, 0.009, 0.009]) for sg in (1, -1)]
for g in [guard] + gends:
    ed.assign_look(g, LK['bronze'])
# leaf blade with a raised midrib, bevelled edges: lens sections lofted from the socket to the tip
xs = np.linspace(XB + 0.045, XT, 26)
t_ = (xs - xs[0]) / (xs[-1] - xs[0])
half_w = 0.0115 + 0.03 * np.sin(np.clip(t_ / 0.62, 0, 1) * np.pi / 2) ** 0.9 * (1 - ed.smoothstep(0.3, 1.0, t_) ** 1.35)
half_w[-1] = 0.0004
half_t = 0.0072 * (1 - 0.65 * t_) + 0.0006
rings = []
for x, w, th in zip(xs, half_w, half_t):
    sec = [(1.0, 0.0), (0.55, 0.3), (0.12, 0.62), (0.0, 1.0), (-0.12, 0.62), (-0.55, 0.3), (-1.0, 0.0), (-0.55, -0.3), (-0.12, -0.62), (0.0, -1.0), (0.12, -0.62), (0.55, -0.3)]
    rings.append([o + wx * x + wy * (a * w) + wz * (b * th) for a, b in sec])
blade = ed.loft('spear_blade', np.array(rings), caps=(True, False))
ed.shade(blade, 28)
ed.assign_look(blade, LK['steel'])
# blade uv for the `blade` set: (metres along, 0 edge .. 1 midrib, temper height)
Vb = ed.verts_of(blade)
loc = Vb - o
xa, ya = loc @ wx, loc @ wy
hw_at = np.interp(xa, xs, half_w)
ed.set_attr(blade, 'ed_uvw', np.stack([xa - XB, np.clip(1 - np.abs(ya) / np.maximum(hw_at, 1e-4), 0, 1), np.full(len(Vb), 0.42)], axis=1), 'FLOAT_VECTOR')

tas = ed.tassel('spear_tassel', o + wx * (XB - 0.07) - np.array([0, 0, 0.012]), direction=(0, 0, -1), length=0.2, radius=0.024, strands=16, head=0.22)
ed.assign_look(tas, LK['horsehair'])
spear = ed.join([shaft, blade, guard] + fit + gends, 'spear')

stage_done(4, 'stage4')

# ---- 5. what shows, skinning, baked surface data, budgets, export ----------------------------------------------------------------
# glowing eyes in the shadow of the hat (the storm's violet-white: the `eye` glow channel)
eyes = []
for z in (1.0, -1.0):
    e = ed.ellipsoid('eye', P('head', [0.101 * K, 0.116 * K, z * 0.034 * K]), [0.004 * K, 0.0055 * K, 0.013 * K],
                     np.stack([rig.vec('head', [1, 0, 0]), rig.vec('head', [0, 1, 0]), rig.vec('head', [0, 0, 1])], axis=1), (10, 6))
    ed.assign_look(e, LK['eye'])
    eyes.append(e)
eyes = ed.join(eyes, 'eyes')

# haircap strands for the `hair` uv set: u across (strand units), v root -> tip
q = ed.get_attr(haircap, 'ed_uv')
ed.set_attr(haircap, 'ed_uvw', np.stack([q[:, 0] * 40.0, q[:, 1], np.zeros(len(q))], axis=1), 'FLOAT_VECTOR')

garments = [robe] + sleeves + collar + trousers + [sash_all] + wraps + [strap, facewrap, haircap]
for g in garments:
    ed.transfer_weights(body, g, arm, smooth=1)
ed.rigid_islands(plates, body, arm=arm)
ed.rigid_islands(splates, body, arm=arm)
ed.transfer_weights(body, lace, arm, smooth=1)
ed.transfer_weights(body, slace, arm, smooth=1)
ed.transfer_weights(body, eyes, arm, smooth=0, bones=['head'])
ed.rigid(hat, 'head')
ed.along_chain(queue, rig, 'queue', parent='head', root_blend=0.06)
ed.rigid(qtie, 'queue1')
ed.rigid(qend, 'queue4')
ed.rigid(spear, 'weaponR')
ed.rigid(tas, 'weaponR')

# the body only where it shows: hands, the eyes' band of the face, the neck between wrap and collar
covers = [robe, facewrap, haircap, hat] + sleeves + trousers + wraps + skirt + [boots, sash_all]
reg = ed.get_attr(body, 'ed_region')
removed = ed.cull_hidden(body, covers, keep=np.isin(reg, [3]))
ed.log('body culled faces', removed)

parts = [
    (body, 'body', 'gear', ()), (eyes, 'eyes', 'gear', ()),
    (ed.join([robe] + sleeves + collar + trousers + [sash_all] + wraps + [strap, facewrap], 'robe'), 'robe', 'cloth', ()),
    (ed.join([plates, lace, splates, slace, boots], 'armour'), 'armour', 'gear', ()),
    (hat, 'hat', 'gear', ('rigid',)),
    (ed.join([haircap, queue, qtie], 'hair'), 'hair', 'gear', ()),
    (qend, 'queueTassel', 'hair', ('cutout',)),
    (spear, 'spear', 'blade', ('rigid',)),
    (tas, 'spearTassel', 'hair', ('cutout', 'rigid')),
]
for sk in skirt:
    parts.append((sk, sk.name, 'cloth', ('cloth',)))
for i, (obj, name, slot, flags) in enumerate(parts):
    ed.part(obj, name, slot, flags, order=i)

objs = [p[0] for p in parts]
BUDGET = {'robe': 13000, 'skirtF': 3000, 'skirtBL': 2000, 'skirtBR': 2000}
for o in objs:
    if o.name in BUDGET:
        ed.decimate_to(o, BUDGET[o.name])
tris = {o.name: ed.tri_count(o, evaluated=False) for o in objs}
ed.log('triangles', sum(tris.values()), tris)
ed.bake_cavity(objs, samples=24, distance=0.1)
for o in objs:
    rep = ed.weight_report(o)
    if rep['unweighted'] or rep['max_influences'] > 4:
        ed.log('WEIGHTS', o.name, rep)
stage_done(5, 'stage5')
manifest = ed.export_asset(HERO, objs, textures=HAT_MAPS, scripts=[os.path.abspath(__file__)] + [os.path.join(ed.HERE, 'ed', f) for f in sorted(os.listdir(os.path.join(ed.HERE, 'ed'))) if f.endswith('.py')])
if PREVIEW:
    ed.preview_sheet(HERO, 'final', height=2.25, samples=12)
ed.log('pilot done', round(time.time() - T0, 1), 's')
