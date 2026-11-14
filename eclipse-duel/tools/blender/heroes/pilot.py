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
    'skin': ed.look('skin', color=(0.36, 0.22, 0.16), rough=0.62, set='leather', amt=0.15),
    'robe': ed.look('robe', color=(0.075, 0.05, 0.11), rough=0.72, set='silk', amt=0.6),          # storm violet silk
    'robeIn': ed.look('robeIn', color=(0.03, 0.028, 0.034), rough=0.8, set='hemp', amt=0.7),      # ink-black hemp under-layer
    'collar': ed.look('collar', color=(0.02, 0.019, 0.024), rough=0.66, set='silk', amt=0.5),     # black lapel band
    'dongjeong': ed.look('dongjeong', color=(0.55, 0.52, 0.46), rough=0.7, set='silk', amt=0.4),  # pale inner collar strip
    'trim': ed.look('trim', color=(0.36, 0.25, 0.08), rough=0.42, metal=0.6, set='brocade', amt=1.0, vein=0.12),  # old-gold thunder trim
    'sash': ed.look('sash', color=(0.022, 0.02, 0.026), rough=0.75, set='hemp', amt=0.8),
    'trousers': ed.look('trousers', color=(0.035, 0.032, 0.04), rough=0.85, set='hemp', amt=0.9),
    'wrap': ed.look('wrap', color=(0.16, 0.145, 0.13), rough=0.88, set='hemp', amt=1.0),          # undyed hemp wraps
    'leather': ed.look('leather', color=(0.05, 0.038, 0.03), rough=0.55, set='leather', amt=0.9),
    'lamellar': ed.look('lamellar', color=(0.028, 0.026, 0.034), rough=0.32, metal=0.0, set='lamellar', amt=1.0, wear=1.2),   # black lacquered plates
    'lace': ed.look('lace', color=(0.42, 0.28, 0.085), rough=0.55, set='hemp', amt=0.5, vein=0.1),                       # old-gold lacing
    'bamboo': ed.look('bamboo', color=(0.3, 0.22, 0.12), rough=0.6, set='bamboo', amt=0.8),
    'bambooDark': ed.look('bambooDark', color=(0.12, 0.085, 0.05), rough=0.55, set='bamboo', amt=0.8),
    'hair': ed.look('hair', color=(0.018, 0.016, 0.017), rough=0.45, set='hair', amt=1.0),
    'shaft': ed.look('shaft', color=(0.06, 0.03, 0.04), rough=0.3, set='lacquer', amt=0.8),
    'bronze': ed.look('bronze', color=(0.42, 0.27, 0.11), rough=0.38, metal=1.0, set='bronze', amt=0.9),
    'steel': ed.look('steel', color=(0.56, 0.57, 0.6), rough=0.22, metal=1.0, set='blade', amt=1.0),
    'horsehair': ed.look('horsehair', color=(0.2, 0.05, 0.22), rough=0.5, set='hair', amt=1.0),    # violet-dyed horsehair
}

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
flare = lambda u, v: 0.05 + 0.075 * v ** 1.4 + 0.012 * np.cos(u * 2 * np.pi) ** 2 * v
skirt = []
for nm, arc_, n_ in (('skirtF', (-0.25, 0.25), 40), ('skirtBL', (0.21, 0.52), 26), ('skirtBR', (0.48, 0.79), 26)):
    sk = ed.wrap(nm, S_skirt, sk_axis, n=n_, offset=flare, arc=arc_, rmax=0.5)
    ed.pleats(sk, count=22, depth=0.011, grow=(0.0, 1.0), phase=0.13 if nm == 'skirtF' else 0.0)
    skirt.append(sk)
ed.drape_settle = None
for sk in skirt:
    ed.drape(sk, [body] + trousers, pin=lambda q, Pp: 1 - ed.smoothstep(0.06, 0.14, q[:, 1]), frames=32, mass=0.3, tension=20, bending=1.2, thickness=0.006)
ed.remove_colliders([body] + trousers)
for sk in skirt:
    ed.push_out(sk, S, 0.012)
    ed.wrinkle(sk, amount=0.0025, scale=30, seed=5, stretch=(1.0, 1.0, 0.2))
    ed.hem(sk, 'v1', 0.022, 0.0025)
    ed.assign_look(sk, LK['robe'])
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
sash_all = ed.join([sash, knot] + ends, 'sash')

# forearm and shin wraps (undyed hemp), boots
wraps = []
for s in ('R', 'L'):
    fa = 'foreArm' + s
    a, b = P(fa, [0, -0.36 * Lf, 0]), P('hand' + s, [0, -0.012, 0])
    e1, e2 = rig.vec(fa, [1, 0, 0]), rig.vec(fa, [0, 0, 1])
    rad = limb_radius(S.subset(['arm' + s]), a, b, e1, e2, [0, 0.35, 0.7, 1.0])
    rad = [[t, r + 0.004] for t, r in rad]
    w = ed.helix_wrap('wrapA' + s, a, b, rad, turns=9, width=0.03, thick=0.0016, axes=(e1, e2), seed=31 if s == 'R' else 32)
    ed.assign_look(w, LK['wrap'])
    wraps.append(w)
    sn = 'shin' + s
    a, b = P(sn, [0, -0.36 * Ls, 0]), P('foot' + s, [0, 0.015, 0])
    e1, e2 = rig.vec(sn, [1, 0, 0]), rig.vec(sn, [0, 0, 1])
    rad = limb_radius(S.subset(['leg' + s]), a, b, e1, e2, [0, 0.3, 0.6, 0.85, 1.0])
    rad = [[t, r + (0.015 if t < 0.1 else 0.008)] for t, r in rad]
    w = ed.helix_wrap('wrapL' + s, a, b, rad, turns=10, width=0.036, thick=0.0018, axes=(e1, e2), seed=41 if s == 'R' else 42)
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
plates, lace = ed.lamellar('lamellar', SL, rows=8, cols=44, thick=0.0028, dome=0.0018, overlap=0.3, row_overlap=0.28, v_range=(0.2, 0.9),
                           lace_r=0.0013, closed=True)
ed.assign_look(plates, LK['lamellar'])
ed.assign_look(lace, LK['lace'])
SV = ed.grid_surface(sleeves[1], 0.014)
splates, slace = ed.lamellar('shoulderL', SV, rows=4, cols=9, thick=0.0028, dome=0.002, overlap=0.3, row_overlap=0.3, u_range=(0.02, 0.5),
                             v_range=(0.0, 0.42), lace_r=0.0013)
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
weave = ed.weave('hat_weave', Hs, 48, 13, thick=0.0011, lift=0.0013, pattern=(2, 2), sub=2)
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
hat = ed.join([weave, lining, rim, fin, band] + cords, 'hat')

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
tas = ed.tassel('spear_tassel', o + wx * (XB - 0.07) - np.array([0, 0, 0.012]), direction=(0, 0, -1), length=0.2, radius=0.024, strands=16, head=0.22)
ed.assign_look(tas, LK['horsehair'])
spear = ed.join([shaft, blade, guard, tas] + fit + gends, 'spear')

stage_done(4, 'stage4')
