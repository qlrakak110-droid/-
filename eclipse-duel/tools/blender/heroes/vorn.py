# 뇌진천 雷震天 (VORN) — 천뢰신창, the Heaven-Thunder Spear of 뇌운보 (Thundercloud Keep). The whole visible surface of
# the hero, built on the game rig (rigs/vorn.json: src/fighters/vorn/design.js, incl. the queue / wrapTail / tassel
# spring chains) from the pipeline pilot (heroes/pilot.py), taken to final quality:
#   * base body (anatomical SDF, separated fingers closed on the haft), skinned with the rig's helper bones
#   * storm-violet robe: torso shell + bound sleeves, crossed ink-black collars with a pale inner strip (동정) and old-gold
#     thunder-fret brocade; ink hemp trousers gathered into tall wrapped boots
#   * three-panel split skirt draped by Blender cloth over the hip / leg hull, embroidered hem bands, bound to the
#     runtime cloth panels (skirtF / skirtBL / skirtBR); black hemp sash knotted at the front left, ends on the front panel
#   * lacquered lamellar cuirass + left shoulder piece laced in old gold (찰갑), leather strap; lacquered lamellar waist
#     guard (요갑) over the hips
#   * deep conical bamboo hat (삿갓): the real over-under plait is baked into object-space normal / AO maps on a
#     low cone; inner crown, bound rim, bronze finial, chin cords
#   * cloth face wrap with horizontal folds and a tied knot + two tails on spring bones, glowing eyes, combed hair cap
#     and a long braided queue on spring bones
#   * the 뇌룡창 at EXACTLY the rig's weapon extent (butt -0.975 .. tip 1.5): leaf head with a raised midrib, bevelled
#     edges and an inlaid lightning bolt (inlay glow), bronze socket, crossguard, bands and butt cap, lacquered shaft,
#     violet hemp grip wraps, violet horsehair tassel on the `tassel` spring chain
#
#   tools/blender/bl.sh tools/blender/heroes/vorn.py [--stage N] [--no-preview]
#   -> assets/chars/vorn/ (vorn.edm, vorn.json, index.js) + shots/blender/vorn/*.png

import os
import sys
import time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import numpy as np
import edlib as ed

ARGS = sys.argv[1:]
STAGE = int(ARGS[ARGS.index('--stage') + 1]) if '--stage' in ARGS else 99
PREVIEW = '--no-preview' not in ARGS
HERO = 'vorn'
T0 = time.time()

ed.reset_scene()
rig = ed.Rig(HERO)
arm = ed.build_armature(rig)
K = rig.K
Lu, Lf, Lt, Ls = (rig.data['lengths'][k] for k in ('upperArm', 'foreArm', 'thigh', 'shin'))
P = rig.pt

# ---- looks: storm violet, ink black, old gold (linear colours) -------------------------------------------------------------
LK = {
    'skin': ed.look('skin', color=(0.16, 0.1, 0.07), rough=0.6, set='leather', amt=0.15),
    'robe': ed.look('robe', color=(0.062, 0.026, 0.11), rough=0.6, set='silk', amt=0.9),             # storm-violet silk
    'robeIn': ed.look('robeIn', color=(0.012, 0.011, 0.014), rough=0.85, set='hemp', amt=0.8),       # ink-black hemp lining
    'collar': ed.look('collar', color=(0.01, 0.009, 0.012), rough=0.55, set='silk', amt=0.8),        # black lapel band
    'dongjeong': ed.look('dongjeong', color=(0.36, 0.34, 0.31), rough=0.7, set='silk', amt=0.6),     # pale inner collar strip
    'trim': ed.look('trim', color=(0.03, 0.012, 0.05), rough=0.5, set='brocade', amt=1.0),           # thunder brocade, old-gold thread
    'sash': ed.look('sash', color=(0.016, 0.014, 0.018), rough=0.8, set='hemp', amt=0.9),
    'trousers': ed.look('trousers', color=(0.02, 0.018, 0.026), rough=0.88, set='hemp', amt=1.0),
    'wrap': ed.look('wrap', color=(0.11, 0.092, 0.07), rough=0.9, set='hemp', amt=1.0),              # undyed hemp wraps
    'face': ed.look('face', color=(0.034, 0.027, 0.042), rough=0.9, set='hemp', amt=1.0),            # smoke-violet face wrap
    'leather': ed.look('leather', color=(0.022, 0.017, 0.015), rough=0.58, set='leather', amt=1.0),
    'lamellar': ed.look('lamellar', color=(0.014, 0.012, 0.017), rough=0.3, set='lacquer', amt=1.0, wear=0.35),
    'lace': ed.look('lace', color=(0.32, 0.2, 0.055), rough=0.6, set='hemp', amt=0.6, vein=0.12),    # old-gold lacing
    'bamboo': ed.look('bamboo', color=(0.095, 0.064, 0.03), rough=0.45, set='hemp', amt=0.35),
    'bambooDark': ed.look('bambooDark', color=(0.04, 0.029, 0.018), rough=0.5, set='hemp', amt=0.5),
    'hair': ed.look('hair', color=(0.012, 0.011, 0.012), rough=0.42, set='hair', amt=1.0),
    'shaft': ed.look('shaft', color=(0.03, 0.02, 0.03), rough=0.3, set='lacquer', amt=0.8),
    'bronze': ed.look('bronze', color=(0.42, 0.27, 0.11), rough=0.36, metal=1.0, set='bronze', amt=0.9),
    'steel': ed.look('steel', color=(0.2, 0.21, 0.25), rough=0.22, metal=1.0, set='blade', amt=1.0),
    'grip': ed.look('grip', color=(0.05, 0.02, 0.09), rough=0.85, set='hemp', amt=0.9),
    'bolt': ed.look('bolt', color=(0.05, 0.03, 0.08), rough=0.4, metal=0.3, set='hammered', amt=0.0, inlay=1.0),
    'horsehair': ed.look('horsehair', color=(0.07, 0.02, 0.11), rough=0.5, set='hair', amt=1.0),     # violet-dyed horsehair
    'eye': ed.look('eye', color=(0.02, 0.016, 0.03), rough=0.6, set='hammered', amt=0.0, eye=1.0, emission=(0.7, 0.55, 1.0)),
}
MOTIF_THUNDER = 6
for m_ in LK.values():
    m_.use_fake_user = True          # orphans_purge after heavy steps must not drop looks not yet assigned


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


def thick(obj, t, inner=None, offset=-1.0):
    """Solidify a sheet; the inner shell takes the `inner` look (lining)."""
    if inner is not None:
        obj.data.materials.append(inner)
    ed.add_mod(obj, 'SOLIDIFY', thickness=t, offset=offset, use_rim=True, use_even_offset=False, use_quality_normals=True, material_offset=1 if inner is not None else 0)
    return ed.apply_mods(obj)


def brocade_uvw(obj, length, width, glow=0.15):
    """Brocade uv of a ribbon band: u along the band in band widths, v across, code = thunder motif + glow."""
    q = ed.get_attr(obj, 'ed_uvw')
    ed.set_attr(obj, 'ed_uvw', np.stack([q[:, 1] * length / width * 0.5, q[:, 0], np.full(len(q), MOTIF_THUNDER + glow)], axis=1), 'FLOAT_VECTOR')


def band_ring(name, center, axis, radius, width, look, segs=28, bulge=0.0025, glow=0.15):
    """An embroidered cuff / binding ring around a limb (lathe), with brocade uv (u around in band widths, v across)."""
    ax = ed.normalize(np.asarray(axis, dtype=np.float64))
    o = ed.lathe(name, [[radius, -width / 2], [radius + bulge, -width * 0.3], [radius + bulge, width * 0.3], [radius, width / 2]], segs,
                 origin=np.asarray(center) - ax * 0.0, axis=ax)
    V = ed.verts_of(o) - np.asarray(center)
    ref = np.eye(3)[np.argmin(np.abs(ax))]
    e1 = ed.normalize(np.cross(ax, ref)); e2 = np.cross(ax, e1)
    ang = (np.arctan2(V @ e2, V @ e1) / (2 * np.pi)) % 1.0
    h = np.clip((V @ ax) / width + 0.5, 0, 1)
    ed.set_attr(o, 'ed_uvw', np.stack([ang * 2 * np.pi * radius / width * 0.5, h, np.full(len(V), MOTIF_THUNDER + glow)], axis=1), 'FLOAT_VECTOR')
    ed.assign_look(o, look)
    return o


def stage_done(n, name):
    if STAGE <= n:
        for o in ed.bpy.context.scene.objects:
            if o.type == 'MESH':
                V = ed.verts_of(o)
                if len(V):
                    print('BBOX', o.name, np.round(V.min(0), 3), np.round(V.max(0), 3), len(V), ed.tri_count(o, evaluated=False))
        if PREVIEW:
            ed.preview_sheet(HERO, name, height=2.3, samples=10)
        ed.log('stage', n, 'done', round(time.time() - T0, 1), 's')
        sys.exit(0)


def limb_radius(Ssub, a, b, e1, e2, ts, n=24):
    """Mean body radius around the segment a -> b at parameters ts (for wraps)."""
    A = np.linspace(0, 2 * np.pi, n, endpoint=False)
    return [[t, float(np.mean(ed.body_radius(Ssub, a + (b - a) * t, e1, e2, A, rmax=0.2)))] for t in ts]


def surf_path(Sf, uv, n=24, lift=0.0):
    """Points + normals along a (u, v) polyline on a parametric surface."""
    UV = ed.polyline(np.array([[u, v, 0.0] for u, v in uv]), n)
    pts, nrm = [], []
    for u, v, _ in UV:
        p, nn, tu, tv = ed.surface_normal(Sf, u, v)
        pts.append(p + nn * lift); nrm.append(nn)
    return np.array(pts), np.array(nrm)


# ---- 1. base body ---------------------------------------------------------------------------------------------------------------
body = ed.body(rig, arm=arm, tris=12000)
S = ed.body.last_sdf
S_torso = S.subset(['torso', 'neck'])
ed.assign_look(body, LK['skin'])
ed.log('body', ed.tri_count(body), ed.weight_report(body))
stage_done(1, 'stage1')

# ---- 2. robe: torso shell, bound sleeves ---------------------------------------------------------------------------------------
sh = rig.local('chest', rig.head('upperArmR'))
top = P('chest', [-0.01, sh[1] + 0.075, 0])
waist = P('hips', [0.0, -0.02, 0])
ax = ed.ring_axis([top, P('chest', [0.0, sh[1] - 0.05, 0]), P('chest', [0.01, 0.05, 0]), P('spine', [0.012, 0.05, 0]), waist], 30)
# looseness: the robe blouses over the sash at the belly and the back, tight at the collar
ease = lambda u, v: 0.004 + 0.012 * ed.smoothstep(0.15, 0.8, v) * (0.6 + 0.4 * np.cos(u * 2 * np.pi) ** 2)
robe = ed.wrap('robe_torso', S_torso, ax, n=56, offset=0.009, ease=ease)
ed.wrinkle(robe, amount=0.0025, scale=22, seed=3)
# folds gathered toward the sash: vertical tension lines over the lower back and belly
ed.wrinkle(robe, amount=0.0022, scale=34, seed=4, stretch=(1.0, 1.0, 0.18), mask=lambda Pp: ed.smoothstep(0.55, 0.95, (top[2] - Pp[:, 2]) / max(1e-3, top[2] - waist[2])))
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

stage_done(2, 'stage2')

# ---- 3. crossed collar, trousers, skirt, sash, waist guard, wraps, boots ------------------------------------------------------------
SR = ed.grid_surface(robe, 0.0)

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
    # the pale inner-collar strip (동정) on the neck edge, and the old-gold thunder trim on the outer edge
    T_ = np.gradient(pts, axis=0); side = ed.normalize(np.cross(T_, nrm))
    sgn = 1.0 if np.mean(np.linalg.norm(pts + side * 0.03 - neck_pt, axis=1)) < np.mean(np.linalg.norm(pts - side * 0.03 - neck_pt, axis=1)) else -1.0
    k = int(len(pts) * (0.42 if nm == 'lapelT' else 0.7))
    dj = ed.ribbon(nm + '_dj', pts[:k] + side[:k] * sgn * 0.026 + nrm[:k] * 0.0035, width=0.02, normal=nrm[:k], camber=0.3, nu=2)
    thick(dj, 0.003, offset=0.0)
    ed.assign_look(dj, LK['dongjeong'])
    collar.append(dj)
    tr = ed.ribbon(nm + '_trim', pts - side * sgn * 0.031 + nrm * 0.0032, width=0.013, normal=nrm, camber=0.2, nu=2)
    brocade_uvw(tr, float(np.linalg.norm(np.diff(pts, axis=0), axis=1).sum()), 0.013, glow=0.2)
    thick(tr, 0.002, offset=0.0)
    ed.assign_look(tr, LK['trim'])
    collar.append(tr)

# trousers: loose hemp, gathered into the boot wraps
trousers = []
for s in ('R', 'L'):
    ta = ed.ring_axis([P('thigh' + s, [0.0, 0.0, 0]), P('thigh' + s, [0, -0.5 * Lt, 0]), P('shin' + s, [0, 0, 0]), P('shin' + s, [0, -0.4 * Ls, 0])], 22)
    tro = ed.wrap('trousers' + s, S.subset(['leg' + s]), ta, n=26, offset=lambda u, v: 0.016 + 0.01 * np.sin(np.clip(v, 0, 1) * np.pi) - 0.008 * ed.smoothstep(0.7, 1.0, v), rmax=0.3)
    ed.wrinkle(tro, amount=0.004, scale=22, seed=21 if s == 'R' else 22, stretch=(1.0, 1.0, 0.6))
    ed.push_out(tro, S, 0.006)
    ed.assign_look(tro, LK['trousers'])
    trousers.append(tro)

# skirt: front panel + two back panels (split for riding and fighting), overlapping at the sides, draped by the solver
S_skirt = S.subset(['torso', 'legR', 'legL'])
hem_z = 0.36
c0 = P('hips', [0.0, 0.055, 0])
sk_axis_pts = [c0, np.array([c0[0], c0[1] - 0.01, (c0[2] + hem_z) / 2]), np.array([c0[0], c0[1] - 0.02, hem_z])]
sk_axis = ed.ring_axis(sk_axis_pts, 26)
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
ed.bpy.ops.outliner.orphans_purge(do_recursive=True)
SKIRT_BONES = ['hips', 'spine', 'thighR', 'thighL', 'hipJointR', 'hipJointL', 'thighTwistR', 'thighTwistL']
SKIRT_SHARE = lambda u, v: ed.smoothstep(0.1, 0.42, v)
for i_, sk in enumerate(skirt):
    ed.push_out(sk, S, 0.012)
    ed.wrinkle(sk, amount=0.0025, scale=30, seed=5, stretch=(1.0, 1.0, 0.2))
    ed.hem(sk, 'v1', 0.022, 0.0025)
    # runtime cloth: a verlet panel defined FROM the drape (the game's cloth starts where Blender left it); the upper
    # skirt rides the hips / thighs by weights, the lower part is handed to the panel's particle bones
    n_, r_ = sk['ed_grid']
    Vg = ed.verts_of(sk)[: n_ * r_].reshape(r_, n_, 3)
    G = Vg[:, ::-1] if Vg[0, 0, 0] < Vg[0, -1, 0] else Vg
    pan = ed.define_panel(sk.name, G, anchor='hips', rig=rig, cols=6 if sk.name == 'skirtF' else 4, rows=9,
                          damping=0.045, margin=0.02, thickness=0.01, wind=0.7, stretch=1.0, bend=0.35)
    # the embroidered hem band: a thunder-fret brocade strip above the turned hem, on the outside of the panel
    row = Vg[int(round(0.9 * (r_ - 1)))]
    ctr = np.array([c0[0], c0[1], 0.0])
    out_n = row - ctr; out_n[:, 2] = 0.0; out_n = ed.normalize(out_n)
    hb_path = row + out_n * 0.0055
    hb = ed.ribbon(sk.name + '_hemband', hb_path, width=0.034, normal=out_n, camber=0.0, nu=2)
    brocade_uvw(hb, float(np.linalg.norm(np.diff(hb_path, axis=0), axis=1).sum()), 0.034, glow=0.18)
    ed.transfer_weights(body, sk, arm, smooth=2, bones=SKIRT_BONES)
    ed.bind_panel(sk, pan, share=SKIRT_SHARE)
    ed.assign_look(sk, LK['robe'])
    orient_out(sk, sk_axis_pts)
    thick(sk, 0.004, inner=LK['robeIn'])
    thick(hb, 0.0016, offset=0.0)
    ed.assign_look(hb, LK['trim'])
    ed.transfer_weights(body, hb, arm, smooth=2, bones=SKIRT_BONES)
    ed.bind_panel(hb, pan, share=SKIRT_SHARE)
    skirt[i_] = ed.join([sk, hb], sk.name)

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
# waist guard (요갑): two rows of large lacquered lamellae over the hips, front and sides, under the sash
WG = [P('hips', [0.0, -0.005, 0]), P('hips', [0.0, -0.175, 0])]
wg_axis = ed.ring_axis(WG, 8)
wg_shell = ed.wrap('_wg', S_skirt, wg_axis, n=48, offset=lambda u, v: 0.07 + 0.035 * v, arc=(-0.3, 0.3), rmax=0.5)
orient_out(wg_shell, WG)
SW = ed.grid_surface(wg_shell, 0.0, u_wrap=False)
gplates, glace = ed.lamellar('waistguard', SW, rows=2, cols=13, thick=0.003, dome=0.0022, overlap=0.26, row_overlap=0.26, v_range=(0.0, 1.0),
                             lace_r=0.0014, lod=0, seed=7)
ed.delete(wg_shell)
ed.assign_look(gplates, LK['lamellar'])
ed.assign_look(glace, LK['lace'])
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
sash_all = ed.join([sash, knot], 'sash')
# the hanging ends lie on the front skirt panel: they take its skin weights and its runtime cloth binding
pF = ed.skin.PANELS['skirtF']
for e in ends:
    ed.transfer_weights(body, e, arm, smooth=1, bones=SKIRT_BONES)
    ed.bind_panel(e, pF, share=SKIRT_SHARE)
skirt[0] = ed.join([skirt[0]] + ends, 'skirtF')

# forearm wraps from mid-forearm over the palm (fingers free on the haft), embroidered cuff rings; tall wrapped boots
wraps, cuffs = [], []
for s in ('R', 'L'):
    fa = 'foreArm' + s
    a, b = P(fa, [0, -0.34 * Lf, 0]), P('hand' + s, [0, -0.012, 0])
    e1, e2 = rig.vec(fa, [1, 0, 0]), rig.vec(fa, [0, 0, 1])
    rad = limb_radius(S.subset(['arm' + s]), a, b, e1, e2, [0, 0.35, 0.7, 1.0])
    rad = [[t, r + 0.004] for t, r in rad]
    w = ed.helix_wrap('wrapA' + s, a, b, rad, turns=10, width=0.028, thick=0.0016, sides=10, axes=(e1, e2), seed=31 if s == 'R' else 32)
    ed.assign_look(w, LK['wrap'])
    wraps.append(w)
    cuffs.append(band_ring('cuff' + s, P(fa, [0, -0.33 * Lf, 0]), rig.vec(fa, [0, 1, 0]), rad[0][1] + 0.006, 0.026, LK['trim'], segs=24))
    hb = 'hand' + s
    hz = 0.003 * (1 if s == 'R' else -1)
    w = ed.helix_wrap('wrapH' + s, P(hb, [0, 0.012, hz]), P(hb, [0.004, -0.058, hz]), [[0, 0.031], [0.5, 0.039], [1, 0.044]], turns=4, width=0.026,
                      thick=0.0015, sides=14, ellipse=0.42, axes=(rig.vec(hb, [1, 0, 0]), rig.vec(hb, [0, 0, 1])), seed=33 if s == 'R' else 34)
    ed.assign_look(w, LK['wrap'])
    wraps.append(w)
    # boot wraps: from just under the knee to the instep, over the trouser gather
    sn = 'shin' + s
    a, b = P(sn, [0, -0.16 * Ls, 0]), P('foot' + s, [0, 0.015, 0])
    e1, e2 = rig.vec(sn, [1, 0, 0]), rig.vec(sn, [0, 0, 1])
    rad = limb_radius(S.subset(['leg' + s]), a, b, e1, e2, [0, 0.25, 0.5, 0.75, 0.9, 1.0])
    rad = [[t, r + (0.02 if t < 0.35 else 0.012 if t < 0.6 else 0.008)] for t, r in rad]
    w = ed.helix_wrap('wrapL' + s, a, b, rad, turns=15, width=0.034, thick=0.0018, sides=10, axes=(e1, e2), seed=41 if s == 'R' else 42)
    ed.assign_look(w, LK['wrap'])
    wraps.append(w)
    # leather binding garter under the knee (the wrap's top end tucked under it)
    cuffs.append(band_ring('garter' + s, P(sn, [0, -0.155 * Ls, 0]), rig.vec(sn, [0, 1, 0]), rad[0][1] + 0.004, 0.022, LK['leather'], segs=24, glow=0.0))
boots = ed.keep_regions(body, [5], 'boots')
ed.displace(boots, lambda Pp, Nn: np.full(len(Pp), 1.0), 0.0075)
Vb = ed.verts_of(boots); Vb[:, 2] = np.maximum(Vb[:, 2], 0.0); ed.set_verts(boots, Vb)
boots.data.materials.clear()
ed.assign_look(boots, LK['leather'])

stage_done(3, 'stage3')

# ---- 4. lamellar cuirass + left shoulder piece, hat, face wrap, hair, queue, spear --------------------------------------------------
SL = ed.grid_surface(robe, 0.012)
plates, lace = ed.lamellar('lamellar', SL, rows=8, cols=32, thick=0.0028, dome=0.0018, overlap=0.3, row_overlap=0.28, v_range=(0.2, 0.9),
                           lace_r=0.0014, closed=True, lod=0)
ed.assign_look(plates, LK['lamellar'])
ed.assign_look(lace, LK['lace'])
# leather binding along the cuirass' top edge (old-gold thunder brocade facing)
cb_pts, cb_n = surf_path(ed.grid_surface(robe, 0.016), [(u, 0.2) for u in np.linspace(0, 1, 9)], 72, 0.0)
cbind = ed.ribbon('cuirass_bind', cb_pts, width=0.018, normal=cb_n, camber=0.25, nu=2)
brocade_uvw(cbind, float(np.linalg.norm(np.diff(cb_pts, axis=0), axis=1).sum()), 0.018, glow=0.2)
thick(cbind, 0.003, offset=0.0)
ed.assign_look(cbind, LK['trim'])
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

# deep conical bamboo hat (삿갓): real over-under plait of split bamboo over a dark lining, inner crown on the head, bound
# rim, bronze finial, chin cords
HAT_R, HAT_H, HAT_BELL = 0.3, 0.32, 0.86
hat_up = rig.vec('head', [0, 1, 0])
apex = P('head', [0.006, 0.47, 0])
Hs = ed.cone_surface(apex, hat_up, HAT_R, HAT_H, bell=HAT_BELL, v0=0.035)
weave = ed.weave('hat_weave', Hs, 44, 16, thick=0.0011, lift=0.0013, pattern=(2, 2), sub=2, across=2)
ed.assign_look(weave, LK['bamboo'])
cone_rh = lambda v: [HAT_R * (0.035 + 0.965 * v), HAT_H * (0.035 + 0.965 * v) ** HAT_BELL]
lining = ed.lathe('hat_lining', [[r - 0.0005, h + 0.0035] for r, h in (cone_rh(v) for v in np.linspace(0, 1, 10))], 48, origin=apex, axis=-hat_up)
ed.assign_look(lining, LK['bambooDark'])
rim = ed.tube('hat_rim', [Hs(u, 1.0) - hat_up * 0.0015 for u in np.linspace(0, 1, 73)], 0.006, 7, caps=False)
rim2 = ed.tube('hat_rim2', [Hs(u, 0.955) + ed.surface_normal(Hs, u, 0.955)[1] * 0.0022 for u in np.linspace(0, 1, 73)], 0.0028, 6, caps=False)
fin = ed.lathe('hat_finial', [[0.0, 0.036], [0.01, 0.032], [0.015, 0.02], [0.012, 0.01], [0.016, 0.0], [0.013, -0.012]], 12, origin=apex - hat_up * 0.016, axis=hat_up, caps=(True, False))
hb_c = P('head', [-0.005, 0.18, 0])
# inner crown: a dark woven frame from the headband up into the cone (the hat sits on the head, it does not float)
v_meet = 0.105 / HAT_R
crown = ed.lathe('hat_crown', [[0.099, 0.0], [0.103, 0.03], [0.1, 0.09], [0.098, (apex - hb_c) @ hat_up - cone_rh(v_meet)[1] - 0.002]], 32, origin=hb_c, axis=hat_up)
band = ed.lathe('hat_band', [[0.101, -0.002], [0.105, 0.012], [0.101, 0.026]], 32, origin=hb_c, axis=hat_up)
ed.assign_look(rim, LK['bambooDark']); ed.assign_look(rim2, LK['lace']); ed.assign_look(fin, LK['bronze'])
ed.assign_look(band, LK['leather']); ed.assign_look(crown, LK['bambooDark'])
cords = []
for z in (1.0, -1.0):
    cp = [P('head', [0.0, 0.19, z * 0.1]), P('head', [0.02, 0.12, z * 0.088]), P('head', [0.05, 0.05, z * 0.07]), P('head', [0.075, 0.0, z * 0.035])]
    cords.append(ed.tube('hat_cord' + ('R' if z > 0 else 'L'), ed.polyline(np.array(cp), 14), 0.0028, 6))
for c in cords:
    ed.assign_look(c, LK['lace'])
# game mesh: a smooth cone at the weave's mid-surface carrying the weave as baked maps (object-space normal, AO, strip
# tones) instead of the plait's ~12k triangles
hat_low = ed.lathe('hat_low', [cone_rh(v) for v in np.linspace(0, 1, 13)], 48, origin=apex, axis=-hat_up, a1=359.999)
ed.recalc_normals(hat_low)
Vh, Nh = ed.verts_of(hat_low), ed.normals_of(hat_low)
if float(np.mean(Nh @ hat_up)) < 0:
    ed.recalc_normals(hat_low, inside=True)
ed.uv_from_grid(hat_low)
ed.assign_look(hat_low, LK['bamboo'])
stage_done(4, 'stage4')     # (the hat's plait is still a separate high-poly object here)
HAT_MAPS = ed.bake_object_maps([weave], hat_low, size=(1024, 512), name='vorn_hat', out_dir=os.path.join(ed.ROOT, 'build', 'bake', 'vorn'))
hat_low['ed_maps'] = 'vorn_hat'
ed.delete(weave)
ed.bpy.ops.outliner.orphans_purge(do_recursive=True)
for o_ in [lining, rim, rim2, fin, band, crown] + cords:
    ed.set_attr(o_, 'ed_bakew', np.zeros(len(o_.data.vertices), dtype=np.float32))
hat = ed.join([hat_low, lining, rim, rim2, fin, band, crown] + cords, 'hat')
hat['ed_maps'] = 'vorn_hat'

# cloth face wrap from the bridge of the nose to the collar: horizontal folds of the winding, a turned top edge, a knot
# at the nape with two tails on the wrapTail spring chain
S_head = S.subset(['head', 'neck', 'eyes'])
fw_axis = ed.ring_axis([P('head', [0.012, 0.1, 0]), P('head', [0.0, 0.0, 0]), P('neck', [0.0, 0.03, 0])], 16)
bridge = lambda u, v: 0.008 + 0.024 * ed.smoothstep(0.25, 0.75, v) * np.cos(u * np.pi * 2).clip(0, 1) ** 2
face = ed.wrap('facewrap', S_head, fw_axis, n=48, offset=bridge, rmax=0.25)
ed.wrinkle(face, amount=0.0032, scale=34, seed=51, stretch=(0.25, 0.25, 1.0))
ed.wrinkle(face, amount=0.0012, scale=70, seed=52, stretch=(1.0, 1.0, 0.5))
ed.push_out(face, S, 0.006)
ed.hem(face, 'v0', 0.012, 0.0022)
ed.assign_look(face, LK['face'])
nape = P('head', [-0.088, 0.05, 0])
fknot = ed.knot('facewrap_knot', nape + rig.vec('head', [-0.012, 0, 0]), size=0.035, facing=rig.vec('head', [-1, 0, 0]), up=(0, 0, 1))
ed.assign_look(fknot, LK['face'])
wt = rig.chain_points('wrapTail')
tails = []
for k_, zz in enumerate((0.022, -0.026)):
    off = rig.vec('head', [0, 0, zz])
    tp = np.array([wt[0] + off * 0.5, (wt[0] + wt[1]) / 2 + off, wt[1] + off * 1.2, wt[2] + off * 1.5 - rig.vec('head', [0, 0.03 * k_, 0])])
    t_ = ed.ribbon('facewrap_tail%d' % k_, ed.polyline(tp, 12), width=[[0, 0.028], [1, 0.042]], normal=rig.vec('head', [-1, 0, 0]), camber=0.15, nu=2)
    thick(t_, 0.003, offset=0.0)
    ed.assign_look(t_, LK['face'])
    tails.append(t_)

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
Vq = ed.verts_of(qtie)
ed.set_attr(qtie, 'ed_uvw', np.stack([np.linspace(0, 6, len(Vq)), np.linspace(0, 1, len(Vq)), np.full(len(Vq), MOTIF_THUNDER + 0.1)], axis=1), 'FLOAT_VECTOR')
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
fit = [ed.lathe('spear_butt', [[0.0, X0], [0.012, X0 + 0.002], [0.0172, X0 + 0.016], [0.0168, X0 + 0.05], [0.0182, X0 + 0.056], [0.0182, X0 + 0.062], [0.0155, X0 + 0.068]], 14, origin=o, axis=wx, caps=(True, False))]
for x in (-0.7, -0.27, 0.3, 0.62):
    fit.append(ed.lathe('spear_band', [[0.0154, x - 0.012], [0.0176, x - 0.008], [0.0178, x + 0.008], [0.0154, x + 0.012]], 14, origin=o, axis=wx))
fit.append(ed.lathe('spear_socket', [[0.0146, XB - 0.065], [0.0172, XB - 0.06], [0.0168, XB - 0.02], [0.0186, XB - 0.012], [0.0186, XB - 0.004],
                                    [0.0135, XB + 0.004], [0.0115, XB + 0.03], [0.0128, XB + 0.04], [0.0095, XB + 0.05]], 14, origin=o, axis=wx))
for f in fit:
    ed.assign_look(f, LK['bronze'])
# violet hemp grip wraps at the rear-hand and forward-hand zones (grips at -0.52 and 0 in the weapon frame)
grips = []
for k_, (ga, gb) in enumerate(((-0.62, -0.38), (-0.12, 0.12))):
    g_ = ed.helix_wrap('spear_grip%d' % k_, o + wx * ga, o + wx * gb, 0.0162, turns=11, width=0.024, thick=0.0013, sides=10, axes=(wy, wz), seed=71 + k_)
    ed.assign_look(g_, LK['grip'])
    grips.append(g_)
# crossguard: a short bronze bar with rolled ends across the blade plane
gx = XB + 0.012
guard = ed.sweep('spear_guard', np.array([o + wx * gx + wy * t for t in np.linspace(-0.07, 0.07, 9)]), 8, [[0, 0.007], [0.5, 0.011], [1, 0.007]], scale_y=0.6, up=wx)
gends = [ed.ellipsoid('spear_gend', o + wx * gx + wy * sg * 0.072, [0.009, 0.009, 0.009]) for sg in (1, -1)]
for g in [guard] + gends:
    ed.assign_look(g, LK['bronze'])
# leaf blade with a raised midrib, honed edge bevels: lens sections lofted from the socket to the tip
xs = np.linspace(XB + 0.045, XT, 30)
t_ = (xs - xs[0]) / (xs[-1] - xs[0])
half_w = 0.0115 + 0.032 * np.sin(np.clip(t_ / 0.6, 0, 1) * np.pi / 2) ** 0.9 * (1 - ed.smoothstep(0.3, 1.0, t_) ** 1.35)
half_w[-1] = 0.0004
half_t = 0.0074 * (1 - 0.65 * t_) + 0.0006
SEC = [(1.0, 0.0), (0.82, 0.16), (0.55, 0.3), (0.12, 0.62), (0.0, 1.0), (-0.12, 0.62), (-0.55, 0.3), (-0.82, 0.16), (-1.0, 0.0),
       (-0.82, -0.16), (-0.55, -0.3), (-0.12, -0.62), (0.0, -1.0), (0.12, -0.62), (0.55, -0.3), (0.82, -0.16)]
rings = []
for x, w, th in zip(xs, half_w, half_t):
    rings.append([o + wx * x + wy * (a * w) + wz * (b * th) for a, b in SEC])
blade = ed.loft('spear_blade', np.array(rings), caps=(True, False))
ed.shade(blade, 28)
ed.assign_look(blade, LK['steel'])
# blade uv for the `blade` set: (metres along, 0 edge .. 1 midrib, temper height)
Vb = ed.verts_of(blade)
loc = Vb - o
xa, ya = loc @ wx, loc @ wy
hw_at = np.interp(xa, xs, half_w)
ed.set_attr(blade, 'ed_uvw', np.stack([xa - XB, np.clip(1 - np.abs(ya) / np.maximum(hw_at, 1e-4), 0, 1), np.full(len(Vb), 0.42)], axis=1), 'FLOAT_VECTOR')
# the lightning bolt inlaid along the midrib on both flats (inlay glow: flares with the arc-runes)
bolt_x = np.array([0.04, 0.08, 0.086, 0.13, 0.136, 0.18, 0.186, 0.25]) + XB + 0.045
bolt_y = np.array([0.0028, -0.0032, 0.0028, -0.003, 0.0024, -0.0024, 0.0016, 0.0])
bolts = []
for sg in (1, -1):
    th_at = np.interp(bolt_x, xs, half_t)
    bp = np.array([o + wx * x + wy * y + wz * sg * (th + 0.0004) for x, y, th in zip(bolt_x, bolt_y, th_at)])
    bp = ed.polyline(bp, 40)
    bt = ed.ribbon('spear_bolt', bp, width=[[0, 0.0026], [0.8, 0.002], [1, 0.0004]], normal=wz * sg, nu=1)
    ed.assign_look(bt, LK['bolt'])
    bolts.append(bt)

# the violet horsehair tassel below the socket, built along the tassel spring chain (its rest direction)
tp = rig.chain_points('tassel')
tas = ed.tassel('spear_tassel', tp[0], direction=ed.normalize(tp[-1] - tp[0]), length=float(np.linalg.norm(tp[-1] - tp[0])) + 0.03, radius=0.024, strands=18, head=0.2)
ed.assign_look(tas, LK['horsehair'])
tcol = ed.lathe('spear_tcollar', [[0.0168, -0.006], [0.02, -0.002], [0.02, 0.006], [0.0168, 0.01]], 14, origin=o + wx * 0.93, axis=wx)
ed.assign_look(tcol, LK['bronze'])
spear = ed.join([shaft, blade, guard, tcol] + fit + gends + grips + bolts, 'spear')

stage_done(5, 'stage5')

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

garments = [robe] + sleeves + collar + trousers + [sash_all] + wraps + cuffs + [strap, face, fknot, cbind, haircap]
for g in garments:
    ed.transfer_weights(body, g, arm, smooth=1)
ed.transfer_weights(body, face, arm, smooth=1, bones=['head', 'neck'])
ed.rigid(fknot, 'head')
for t_ in tails:
    ed.along_chain(t_, rig, 'wrapTail', parent='head', root_blend=0.1)
ed.rigid_islands(plates, body, arm=arm)
ed.rigid_islands(splates, body, arm=arm)
ed.rigid_islands(gplates, body, arm=arm)
ed.transfer_weights(body, lace, arm, smooth=1)
ed.transfer_weights(body, slace, arm, smooth=1)
ed.transfer_weights(body, glace, arm, smooth=1)
ed.transfer_weights(body, eyes, arm, smooth=0, bones=['head'])
ed.rigid(hat, 'head')
ed.along_chain(queue, rig, 'queue', parent='head', root_blend=0.06)
ed.rigid(qtie, 'queue1')
ed.rigid(qend, 'queue4')
ed.rigid(spear, 'weaponR')
ed.along_chain(tas, rig, 'tassel', parent='weaponR', root_blend=0.12)

# the body only where it shows: hands, the eyes' band of the face, the neck between wrap and collar
covers = [robe, face, haircap, hat] + sleeves + trousers + wraps + skirt + [boots, sash_all]
reg = ed.get_attr(body, 'ed_region')
removed = ed.cull_hidden(body, covers, keep=np.isin(reg, [3]))
ed.log('body culled faces', removed)

# soft garments are decimated one by one (patterned pieces: wraps, brocade, lamellar keep their generator resolution)
for o_, n_ in ((sash_all, 1050), (trousers[0], 800), (trousers[1], 800), (face, 1000), (robe, 3000)):
    if ed.tri_count(o_, evaluated=False) > n_:
        ed.decimate_to(o_, n_)
facewrap = ed.join([face, fknot] + tails, 'facewrap')
parts = [
    (body, 'body', 'gear', ()), (eyes, 'eyes', 'gear', ()),
    (ed.join([robe] + sleeves + collar + trousers + [sash_all] + wraps + cuffs + [strap, cbind, facewrap], 'robe'), 'robe', 'cloth', ()),
    (ed.join([plates, lace, splates, slace, gplates, glace, boots], 'armour'), 'armour', 'gear', ()),
    (hat, 'hat', 'gear', ('rigid',)),
    (ed.join([haircap, queue, qtie], 'hair'), 'hair', 'gear', ()),
    (qend, 'queueTassel', 'hair', ('cutout',)),
    (spear, 'spear', 'blade', ('rigid',)),
    (tas, 'spearTassel', 'hair', ('cutout',)),
]
for sk in skirt:
    parts.append((sk, sk.name, 'cloth', ('cloth',)))
for i, (obj, name, slot, flags) in enumerate(parts):
    ed.part(obj, name, slot, flags, order=i)

objs = [p[0] for p in parts]
BUDGET = {'skirtF': 3100, 'skirtBL': 2050, 'skirtBR': 2050}
for o_ in objs:
    if o_.name in BUDGET and ed.tri_count(o_, evaluated=False) > BUDGET[o_.name]:
        ed.decimate_to(o_, BUDGET[o_.name])
tris = {o_.name: ed.tri_count(o_, evaluated=False) for o_ in objs}
ed.log('triangles', sum(tris.values()), tris)
ed.bake_cavity(objs, samples=24, distance=0.1)
for o_ in objs:
    rep = ed.weight_report(o_)
    if rep['unweighted'] or rep['max_influences'] > 4:
        ed.log('WEIGHTS', o_.name, rep)
stage_done(6, 'stage6')
SCRIPTS = [os.path.abspath(__file__)] + [os.path.join(ed.HERE, 'ed', f) for f in sorted(os.listdir(os.path.join(ed.HERE, 'ed'))) if f.endswith('.py')]
manifest = ed.export_asset(HERO, objs, textures=HAT_MAPS, scripts=SCRIPTS)
if PREVIEW:
    ed.preview_sheet(HERO, 'final', height=2.3, samples=12)
ed.log('vorn done', round(time.time() - T0, 1), 's')
