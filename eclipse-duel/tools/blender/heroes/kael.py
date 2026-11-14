# 염무강 炎武剛 (id kael) — 적염패도, the Crimson Flame Tyrant Saber of the Red Sun Gate. Built entirely by code on the game
# rig (tools/blender/rigs/kael.json): proportions, bones, sockets, weapon length / grips and colliders are the rig's.
#
#   /opt/blender-env/venv/bin/python tools/blender/heroes/kael.py [--stage N] [--no-preview] [--only piece] [--pose idle]
#   -> assets/chars/kael/ (kael.edm, kael.json, index.js) + shots/blender/kael/*.png
#
# Stages: 1 block-out (masses, silhouette)  2 garments + hard pieces  3 details  4 game mesh + bakes + skin + export.

import os
import sys
import time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import edlib as ed
import kael_lib as KL
import kael_parts as KP

ARGS = sys.argv[1:]
ONLY = ARGS[ARGS.index('--only') + 1] if '--only' in ARGS else None
STAGE = int(ARGS[ARGS.index('--stage') + 1]) if '--stage' in ARGS else 99
PREVIEW = '--no-preview' not in ARGS
POSE = ARGS[ARGS.index('--pose') + 1] if '--pose' in ARGS else None
HERO = 'kael'
T0 = time.time()

ed.reset_scene()
rig = ed.Rig(HERO)
arm = ed.build_armature(rig)
K = rig.K
Lu, Lf, Lt, Ls = (rig.data['lengths'][k] for k in ('upperArm', 'foreArm', 'thigh', 'shin'))
P = rig.pt
SCRATCH = os.environ.get('KAEL_SCRATCH', os.path.join(ed.ROOT, 'build', 'bake', 'kael'))
os.makedirs(SCRATCH, exist_ok=True)

# ---- looks: charred black, ember red-orange, dark bronze (linear colours) -------------------------------------------------
LK = {
    'skin': ed.look('skin', color=(0.16, 0.085, 0.055), rough=0.55, set='leather', amt=0.12),
    'scar': ed.look('scar', color=(0.21, 0.085, 0.07), rough=0.38, set='leather', amt=0.1),
    'coat': ed.look('coat', color=(0.016, 0.014, 0.014), rough=0.62, set='damask', amt=0.9),                # charred black figured silk
    'lining': ed.look('lining', color=(0.16, 0.012, 0.009), rough=0.5, set='silk', amt=1.0),                    # deep red silk
    'robe': ed.look('robe', color=(0.13, 0.01, 0.008), rough=0.55, set='silk', amt=1.0),                       # the red inner robe
    'trim': ed.look('trim', color=(0.05, 0.008, 0.006), rough=0.5, set='brocade', amt=1.0),                    # flame brocade, gold thread
    'sash': ed.look('sash', color=(0.2, 0.016, 0.01), rough=0.62, set='silk', amt=1.0),
    'trousers': ed.look('trousers', color=(0.02, 0.018, 0.018), rough=0.88, set='hemp', amt=1.0),
    'wrap': ed.look('wrap', color=(0.11, 0.09, 0.07), rough=0.9, set='hemp', amt=1.0),
    'scarf': ed.look('scarf', color=(0.075, 0.022, 0.014), rough=0.86, set='hemp', amt=1.0),               # rust-red hemp scarf
    'band': ed.look('band', color=(0.1, 0.075, 0.055), rough=0.92, set='hemp', amt=1.0),                       # chest bands (sweat-darkened hemp)
    'leather': ed.look('leather', color=(0.032, 0.018, 0.012), rough=0.6, set='leather', amt=1.0),
    'leatherDark': ed.look('leatherDark', color=(0.016, 0.012, 0.011), rough=0.58, set='leather', amt=1.0),
    'bronze': ed.look('bronze', color=(0.36, 0.2, 0.08), rough=0.38, metal=1.0, set='bronze', amt=0.9),
    'iron': ed.look('iron', color=(0.045, 0.04, 0.038), rough=0.6, metal=0.85, set='scorched', amt=1.0),   # charred iron: cracks glow (per-vertex patches)
    'ironDark': ed.look('ironDark', color=(0.03, 0.028, 0.027), rough=0.6, metal=0.75, set='scorched', amt=1.0, vein=0.35),
    'fang': ed.look('fang', color=(0.32, 0.27, 0.2), rough=0.42, metal=0.0, set='jade', amt=0.4),               # old bone / ivory
    'eye': ed.look('eye', color=(0.02, 0.008, 0.004), rough=0.6, set='hammered', amt=0.0, eye=1.0, emission=(1.0, 0.45, 0.1)),
    'pit': ed.look('pit', color=(0.004, 0.003, 0.003), rough=0.95, set='hammered', amt=0.0, occ=0.3),
    'hair': ed.look('hair', color=(0.03, 0.024, 0.02), rough=0.42, set='hair', amt=1.0),
    'cord': ed.look('cord', color=(0.16, 0.012, 0.008), rough=0.8, set='hemp', amt=0.9),
    'steel': ed.look('steel', color=(0.085, 0.082, 0.082), rough=0.3, metal=1.0, set='blade', amt=0.6, wear=0.9),
    'groove': ed.look('groove', color=(0.02, 0.016, 0.014), rough=0.6, metal=0.4, set='scorched', amt=1.0, inlay=0.65, vein=1.0, emission=(1.0, 0.4, 0.1)),
    'saberBack': ed.look('saberBack', color=(0.03, 0.028, 0.028), rough=0.5, metal=0.9, set='scorched', amt=0.9, vein=0.8),
    'strip': ed.look('strip', color=(0.2, 0.014, 0.01), rough=0.6, set='silk', amt=1.0),
}
MOTIF_FLAME, MOTIF_SUN, MOTIF_CLOUD = 2, 4, 0


def only_preview(objs, views, label, frame=None):
    """--only <piece>: render close-ups of one piece (no body) and exit. views: (dir, dist, target) with `dir` the view
    direction from the target toward the camera in `frame`'s game axes (or Blender axes without a frame)."""
    import math
    paths = []
    for i, (D, dist, tgt) in enumerate(views):
        D = np.asarray(D, float)
        if frame is not None:
            D = rig.vec(frame, D)
        D = ed.normalize(D)
        pitch = math.degrees(math.asin(max(-1, min(1, D[2])))); yaw = math.degrees(math.atan2(-D[0], -D[1]))
        paths.append(ed.render_view(HERO, '_only_%s_%d' % (label, i), np.asarray(tgt), dist, yaw, pitch, size=(480, 400), samples=12, height=1.0))
    ed.contact_sheet(paths, os.path.join(ed.ROOT, 'shots', 'blender', HERO, 'only_%s.png' % label), cols=3)
    ed.log('only', label, 'done', round(time.time() - T0, 1), 's')
    sys.exit(0)


if ONLY == 'saber':
    parts = KP.saber(rig, LK)
    parts['strip'] = KP.saber_strip(rig, LK)
    for k_, o_ in parts.items():
        ed.log('saber part', k_, ed.tri_count(o_, evaluated=False))
    W_ = lambda x: P('weaponR', [x, 0, 0])
    only_preview(list(parts.values()), [([0, 0, 1], 4.6, W_(0.66)), ([0.2, 0.3, -1], 4.6, W_(0.66)), ([0, 0.2, 1], 0.55, W_(-0.1)),
                                        ([0.3, 0.6, -0.7], 0.5, W_(0.05)), ([0, 0, 1], 0.7, W_(1.35)), ([0.6, 0.15, 0.8], 0.5, W_(0.3))], 'saber', frame='weaponR')

if ONLY == 'pauldron':
    parts = KP.pauldron(rig, LK)
    sab = KP.saber(rig, LK)
    for o_ in sab.values():
        o_.hide_render = True
    c_ = P('deltoidR', [0.0, 0.0, 0.08])
    only_preview(list(parts.values()), [([0.42, -0.2, 1], 1.0, c_), ([1, 0.2, 0.6], 1.0, c_), ([1, 0.1, -0.2], 1.0, c_), ([-0.8, 0.3, 0.6], 1.0, c_),
                                        ([0.1, 1, 0.3], 1.1, c_), ([0.42, -0.1, 1], 0.55, P('deltoidR', [0.04, -0.05, 0.15]))], 'pauldron', frame='deltoidR')

if ONLY == 'mask':
    parts = KP.mask(rig, LK)
    hd = ed.body(rig, arm=None, tris=14000, build={'mass': 1.12, 'chest': 1.14, 'waist': 1.08, 'hips': 1.04, 'arms': 1.14, 'legs': 1.06, 'neck': 1.2, 'muscle': 1.25}, hands=False)
    ed.assign_look(hd, LK['skin'])
    c_ = P('head', [0.06, 0.12, 0.0])
    only_preview(list(parts.values()), [([1, 0.05, 0], 0.75, c_), ([1, 0.1, 0.7], 0.75, c_), ([0.1, 0.05, 1], 0.75, c_), ([1, -0.3, 0.3], 0.5, c_),
                                        ([1, 0.6, 0.2], 0.75, c_), ([-1, 0.3, 0.6], 0.85, c_)], 'mask', frame='head')

# ---- 1. body -------------------------------------------------------------------------------------------------------------------
BUILD = {'mass': 1.12, 'chest': 1.14, 'waist': 1.08, 'hips': 1.04, 'arms': 1.14, 'legs': 1.06, 'neck': 1.2, 'muscle': 1.25}
body = ed.body(rig, arm=arm, tris=14000, build=BUILD)
S = ed.body.last_sdf
S_torso = S.subset(['torso', 'neck'])
ed.assign_look(body, LK['skin'])
ed.log('body', ed.tri_count(body))

# old sword scars across the open chest and the belly: raised welts (scar tissue) in the glossier, redder scar look
def _on_body(pts, it=8):
    pts = np.asarray(pts, float)
    for _ in range(it):
        d = S_torso.eval(pts); g = S_torso.grad(pts)
        pts = pts - (d / np.maximum(np.einsum('ij,ij->i', g, g), 1e-9))[:, None] * g
    return pts
SCARS = [ed.polyline(_on_body([P('chest', [0.22, 0.2, 0.1]), P('chest', [0.22, 0.1, 0.02]), P('chest', [0.22, 0.0, -0.07]), P('chest', [0.22, -0.05, -0.11])]), 40),
         ed.polyline(_on_body([P('chest', [0.22, 0.13, -0.13]), P('chest', [0.22, 0.09, -0.07]), P('chest', [0.22, 0.06, -0.035])]), 18),
         ed.polyline(_on_body([P('chest', [0.22, 0.03, 0.12]), P('chest', [0.22, 0.045, 0.06])]), 10)]
SCARS = [_on_body(sc) for sc in SCARS]
_Vb = ed.verts_of(body); _dsc = KL.dist_to_paths(_Vb, SCARS)
ed.set_verts(body, _Vb + ed.normals_of(body) * (0.0016 * np.exp(-(_dsc / 0.004) ** 2))[:, None])
_fd = np.array([min(_dsc[v] for v in p_.vertices) for p_ in body.data.polygons])
ed.assign_look(body, LK['scar'], faces=np.nonzero(_fd < 0.0035)[0])

sh = rig.local('chest', rig.head('upperArmR'))          # right shoulder joint in the chest frame


def stage_done(n, name, objs=None, extra=()):
    if STAGE <= n:
        if POSE:
            ed.pose_armature(arm, rig, POSE)
        if PREVIEW:
            ed.preview_sheet(HERO, name, height=2.05, samples=10, extra_views=extra)
        ed.log('stage', n, 'done', round(time.time() - T0, 1), 's')
        sys.exit(0)


# ---- 2. coat: open charred-black outer coat over the red robe, sleeves ---------------------------------------------------
top = P('chest', [-0.012, sh[1] + 0.07, 0])
waist = P('hips', [0.0, 0.06, 0])
coat_axis = ed.ring_axis([top, P('chest', [0.0, sh[1] - 0.06, 0]), P('chest', [0.012, 0.04, 0]), P('spine', [0.012, 0.05, 0]), waist], 30)
# opening: the neck at the top, wide over the chest, closing toward the sash
gap = lambda v: 0.085 + 0.085 * ed.smoothstep(0.0, 0.32, v) - 0.11 * ed.smoothstep(0.42, 1.0, v)
coat_ease = lambda u, v: 0.004 + 0.016 * ed.smoothstep(0.2, 0.85, v) * (0.5 + 0.5 * np.cos(u * 2 * np.pi - np.pi) ** 2)
coat = KL.wrap_open('coat_torso', S_torso, coat_axis, 64, 0.011, gap, ease=coat_ease)
ed.wrinkle(coat, amount=0.0028, scale=20, seed=3)
ed.push_out(coat, S, 0.008)
KL.orient_out(coat, coat_axis)
ed.assign_look(coat, LK['coat'])

sleeves = []
for s in ('R', 'L'):
    sa = ed.ring_axis([P('upperArm' + s, [-0.006, 0.06, 0]), P('upperArm' + s, [0, -0.5 * Lu, 0]), P('foreArm' + s, [0, 0, 0]),
                       P('foreArm' + s, [0, -0.42 * Lf, 0])], 26)
    sl_off = lambda u, v: 0.014 + 0.02 * np.sin(np.clip(v, 0, 1) * np.pi * 0.9) ** 1.1 + 0.012 * ed.smoothstep(0.75, 1.0, v)
    sv = ed.wrap('sleeve' + s, S.subset(['arm' + s]), sa, n=30, offset=sl_off, rmax=0.22, min_r=lambda v: 0.066 - 0.024 * min(1.0, v * 2.4))
    ed.wrinkle(sv, amount=0.0045, scale=24, seed=11 if s == 'R' else 12, stretch=(1.0, 1.0, 1.0))
    ed.push_out(sv, S, 0.006)
    ed.assign_look(sv, LK['coat'])
    sleeves.append(sv)

# ---- coat tails below the sash: front-left / back-left / back-right / front-right, draped by the cloth solver ---------------
S_skirt = S.subset(['torso', 'legR', 'legL'])
c0 = P('hips', [0.0, 0.07, 0])
hem_z = 0.3
tail_axis = ed.ring_axis([c0, np.array([c0[0], c0[1] + 0.01, (c0[2] + hem_z) / 2]), np.array([c0[0], c0[1] + 0.02, hem_z])], 28)
flare = lambda u, v: 0.04 + 0.13 * v ** 1.1 + 0.025 * np.cos(u * 2 * np.pi) ** 2 * v
TAILS = (('tailFL', (0.045, 0.285), 22), ('tailBL', (0.235, 0.497), 24), ('tailBR', (0.503, 0.765), 24), ('tailFR', (0.715, 0.955), 22))
tails = []
for nm, arc_, n_ in TAILS:
    tl = ed.wrap(nm, S_skirt, tail_axis, n=n_, offset=flare, arc=arc_, rmax=0.5)
    ed.pleats(tl, count=26, depth=0.008, grow=(0.0, 1.0), phase=0.1)
    tails.append(tl)
legs_hull = ed.wrap('_legs_hull', S_skirt, ed.ring_axis([c0, np.array([c0[0], c0[1], 0.2])], 20), n=48, offset=0.016)
KL.orient_out(legs_hull, [c0, np.array([c0[0], c0[1], 0.2])])
for tl in tails:
    ed.drape(tl, [legs_hull], pin=lambda q, Pp: 1 - ed.smoothstep(0.05, 0.14, q[:, 1]), frames=12, mass=0.35, tension=25, bending=5.0, thickness=0.006)
ed.remove_colliders([legs_hull])
ed.delete(legs_hull)
for tl in tails:
    ed.push_out(tl, S, 0.012)
    ed.wrinkle(tl, amount=0.0025, scale=30, seed=5, stretch=(1.0, 1.0, 0.2))
    ed.hem(tl, 'v1', 0.02, 0.0025)
    KL.orient_out(tl, tail_axis)
    ed.assign_look(tl, LK['coat'])

# ---- sash ---------------------------------------------------------------------------------------------------------------------
sa_axis = ed.ring_axis([P('hips', [0.0, 0.135, 0]), P('hips', [0.0, 0.0, 0])], 9)
sash = ed.wrap('sash', S_torso, sa_axis, n=64, offset=lambda u, v: 0.048 + 0.008 * np.sin(np.clip(v, 0, 1) * np.pi * 3) ** 2)
ed.wrinkle(sash, amount=0.002, scale=40, seed=8, stretch=(1, 1, 0.3))
ed.assign_look(sash, LK['sash'])

# ---- trousers + boots ---------------------------------------------------------------------------------------------------------
trousers = []
for s in ('R', 'L'):
    ta = ed.ring_axis([P('thigh' + s, [0.0, 0.02, 0]), P('thigh' + s, [0, -0.5 * Lt, 0]), P('shin' + s, [0, 0, 0]), P('shin' + s, [0, -0.5 * Ls, 0])], 22)
    tro = ed.wrap('trousers' + s, S.subset(['leg' + s]), ta, n=26, offset=lambda u, v: 0.02 + 0.016 * np.sin(np.clip(v, 0, 1) * np.pi) ** 0.8, rmax=0.3)
    ed.wrinkle(tro, amount=0.005, scale=20, seed=21 if s == 'R' else 22, stretch=(1.0, 1.0, 0.6))
    ed.push_out(tro, S, 0.008)
    ed.assign_look(tro, LK['trousers'])
    trousers.append(tro)

boots = []
for s in ('R', 'L'):
    ba = ed.ring_axis([P('shin' + s, [0.0, -0.38 * Ls, 0]), P('shin' + s, [0, -0.75 * Ls, 0]), P('foot' + s, [0, 0.02, 0])], 12)
    bt = ed.wrap('bootShaft' + s, S.subset(['leg' + s]), ba, n=24, offset=lambda u, v: 0.012 + 0.006 * (1 - v), rmax=0.2)
    ed.assign_look(bt, LK['leather'])
    boots.append(bt)
feet = ed.keep_regions(body, [5], 'feet')
ed.displace(feet, lambda Pp, Nn: np.full(len(Pp), 1.0), 0.009)
Vb = ed.verts_of(feet); Vb[:, 2] = np.maximum(Vb[:, 2], 0.0); ed.set_verts(feet, Vb)
feet.data.materials.clear()
ed.assign_look(feet, LK['leather'])
boots.append(feet)

stage_done(1, 'blockout')

# ==== 2. garment details ===========================================================================================================
def edge_band(Gr, cols, rows, lift, width, inset, name, look, code=None, close=False):
    """A band lying on a lofted garment along a path of grid cells [(row, col), ...]: centred `inset` metres in from the
    edge (toward the next row / column), `lift` off the surface. Returns the ribbon (thickened)."""
    pts, nrm, inw = [], [], []
    for (r, c) in zip(rows, cols):
        p0 = Gr[r, c]
        rr = min(max(r + (1 if r == 0 else -1 if r == Gr.shape[0] - 1 else 0), 0), Gr.shape[0] - 1)
        cc = min(max(c + (1 if c == 0 else -1 if c == Gr.shape[1] - 1 else 0), 0), Gr.shape[1] - 1)
        inward = ed.normalize(Gr[rr, cc] - p0)
        du = Gr[r, min(c + 1, Gr.shape[1] - 1)] - Gr[r, max(c - 1, 0)]
        dv = Gr[min(r + 1, Gr.shape[0] - 1), c] - Gr[max(r - 1, 0), c]
        n_ = ed.normalize(np.cross(du, dv))
        pts.append(p0); nrm.append(n_); inw.append(inward)
    pts, nrm, inw = np.array(pts), np.array(nrm), np.array(inw)
    # outward normals (away from the garment axis)
    cen = Gr.reshape(-1, 3).mean(0)
    flipn = np.sign(np.einsum('ij,ij->i', nrm, pts - cen))
    nrm = nrm * np.where(flipn == 0, 1, flipn)[:, None]
    inw = ed.normalize(inw - nrm * np.einsum('ij,ij->i', inw, nrm)[:, None])
    path = pts + inw * inset + nrm * lift
    m = max(12, len(path) * 2)
    P2 = ed.polyline(path, m); N2 = ed.normalize(ed.polyline(nrm, m))
    rb = ed.ribbon(name, P2, width=width, normal=N2, camber=0.08, nu=3)
    if code is not None:
        q = ed.get_attr(rb, 'ed_uvw'); L_ = float(np.linalg.norm(np.diff(P2, axis=0), axis=1).sum())
        w0 = width if np.ndim(width) == 0 else 0.02
        ed.set_attr(rb, 'ed_uvw', np.stack([q[:, 1] * L_ / w0 * 0.5, q[:, 0], np.full(len(q), code)], axis=1), 'FLOAT_VECTOR')
    KL.thick(rb, 0.0025, offset=-1)
    ed.assign_look(rb, look)
    return rb


nC, nR = coat['ed_grid']
Gc = ed.verts_of(coat)[: nC * nR].reshape(nR, nC, 3)


def facing(obj, edge_cols, edge_rows, trim_n=2, face_n=5, lift=0.003, code=MOTIF_FLAME + 0.35, trim_w=0.03, row_span=0.6):
    """The open edges of a lofted garment turned back: the last `trim_n` grid columns / rows along the opening carry the
    flame brocade trim (ed_uvw written on their vertices), the next `face_n` the red facing of the inner robe; both are
    lifted a little (doubled cloth) and the fold line gets a darker cavity."""
    N_, R_ = obj['ed_grid']
    G = ed.verts_of(obj)[: N_ * R_].reshape(R_, N_, 3)
    ci = np.tile(np.arange(N_), R_); ri = np.repeat(np.arange(R_), N_)
    dist = np.full(N_ * R_, 99)
    along = np.zeros(N_ * R_)
    # step lengths along columns (v) and rows (u) for the brocade u coordinate
    sv = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(G[:, 0], axis=0), axis=1))])
    su = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(G[0], axis=0), axis=1))])
    for c in edge_cols:
        dc = np.abs(ci - c)
        m = dc < dist
        dist = np.where(m, dc, dist); along = np.where(m, sv[ri] + su[-1] * (c > 0), along)
    ucol = np.linspace(0, 1, N_)[ci]
    for r in edge_rows:
        dr = np.abs(ri - r) + np.where(np.abs(ucol - 0.5) < row_span, 0, 99)
        m = dr < dist
        dist = np.where(m, dr, dist); along = np.where(m, su[ci] + sv[-1], along)
    V = ed.verts_of(obj); Nn = ed.normals_of(obj)
    band = (dist <= trim_n + face_n).astype(float)
    V[: N_ * R_] += Nn[: N_ * R_] * (band * lift)[:, None]
    ed.set_verts(obj, V)
    cav = ed.get_attr(obj, 'ed_cav').copy()
    cav[: N_ * R_] *= np.where(dist == trim_n + face_n, 0.62, 1.0)
    ed.set_attr(obj, 'ed_cav', cav)
    uvw = np.zeros((len(V), 3))
    uvw[: N_ * R_, 0] = along / trim_w * 0.5
    uvw[: N_ * R_, 1] = np.clip(dist / max(trim_n, 1), 0, 1)
    uvw[: N_ * R_, 2] = code
    ed.set_attr(obj, 'ed_uvw', uvw, 'FLOAT_VECTOR')
    fdist = np.array([min(dist[v] for v in p.vertices) for p in obj.data.polygons])
    ed.assign_look(obj, LK['trim'], faces=np.nonzero(fdist < trim_n)[0])
    ed.assign_look(obj, LK['robe'], faces=np.nonzero((fdist >= trim_n) & (fdist < trim_n + face_n))[0])
    return obj


facing(coat, [0, nC - 1], [0], trim_n=2, face_n=4, row_span=0.36)


def thick_multi(obj, t, inner, offset=-1.0):
    """Solidify a sheet with several looks: every inner face takes the `inner` look."""
    n = len(obj.data.materials)
    for _ in range(n):
        obj.data.materials.append(inner)
    ed.add_mod(obj, 'SOLIDIFY', thickness=t, offset=offset, use_rim=True, use_even_offset=False, use_quality_normals=True, material_offset=n,
               material_offset_rim=n)
    return ed.apply_mods(obj)


# the Red Sun Gate emblem embroidered on the upper back: two brocade rings, glowing faintly
SR = ed.grid_surface(coat, 0.004, u_wrap=False)
emblem = []
row = Gc[int(nR * 0.36)]
Lrow = float(np.linalg.norm(np.diff(row, axis=0), axis=1).sum())
Lcol = float(np.linalg.norm(np.diff(Gc[:, nC // 2], axis=0), axis=1).sum())
for k_, (rad, w) in enumerate(((0.1, 0.028), (0.055, 0.018))):
    uvc = []
    for a in np.linspace(0, 2 * np.pi, 41)[:-1]:
        uvc.append((0.5 + np.cos(a) * rad / Lrow, 0.4 + np.sin(a) * rad / Lcol))
    pts, nrm = KL.surf_path(SR, uvc + uvc[:1], 60, 0.003)
    rb = ed.ribbon('emblem%d' % k_, pts, width=w, normal=nrm, camber=0.06, nu=3)
    q = ed.get_attr(rb, 'ed_uvw'); L_ = float(np.linalg.norm(np.diff(pts, axis=0), axis=1).sum())
    ed.set_attr(rb, 'ed_uvw', np.stack([q[:, 1] * L_ / w * 0.5, q[:, 0], np.full(len(q), MOTIF_SUN + 0.3)], axis=1), 'FLOAT_VECTOR')
    KL.thick(rb, 0.002, offset=-1)
    ed.assign_look(rb, LK['trim'])
    emblem.append(rb)
emblem = ed.join(emblem, 'emblem')

# the red inner robe's sleeves show below the coat sleeves (layered), with a brocade cuff
inner_sleeves = []
for s in ('R', 'L'):
    ia = ed.ring_axis([P('foreArm' + s, [0, -0.3 * Lf, 0]), P('foreArm' + s, [0, -0.5 * Lf, 0])], 6)
    iv = ed.wrap('innerSleeve' + s, S.subset(['arm' + s]), ia, n=26, offset=lambda u, v: 0.014 + 0.004 * (1 - v), rmax=0.15)
    ed.wrinkle(iv, amount=0.002, scale=40, seed=31, stretch=(1, 1, 1))
    ed.assign_look(iv, LK['robe'])
    inner_sleeves.append(iv)

# chest bands: sweat-darkened hemp wound round the belly and lower ribs (the robe hangs open over them)
bands = []
a_ = P('spine', [0.012, 0.035, 0]); b_ = P('chest', [0.02, 0.02, 0])
e1 = ed.normalize(rig.vec('spine', [1, 0, 0])); e2 = ed.normalize(rig.vec('spine', [0, 0, -1]))
ts = [0, 0.33, 0.66, 1.0]
rf = [[t, float(ed.body_radius(S_torso, a_ + (b_ - a_) * t, e1, e2, [0.0], rmax=0.3)[0])] for t in ts]
rs = [float(ed.body_radius(S_torso, a_ + (b_ - a_) * t, e1, e2, [np.pi / 2], rmax=0.3)[0]) for t in ts]
ell = float(np.mean([s_ / f_[1] for s_, f_ in zip(rs, rf)]))
cb = ed.helix_wrap('chestBands', a_, b_, [[t, r + 0.006] for t, r in rf], turns=4.5, width=0.07, thick=0.003, sides=30, ellipse=ell, axes=(e1, e2), jitter=0.3, seed=7)
ed.push_out(cb, S, 0.005)
ed.assign_look(cb, LK['band'])
bands.append(cb)

# the leather strap of the pauldron, across the chest from the right shoulder to the left flank
strap_pts = np.array([P('chest', [0.07, sh[1] + 0.02, 0.15]), P('chest', [0.15, sh[1] - 0.06, 0.09]), P('chest', [0.17, 0.09, 0.0]),
                      P('chest', [0.15, 0.03, -0.1]), P('chest', [0.08, -0.01, -0.17])])
sp = ed.polyline(strap_pts, 30)
cen_ = P('chest', [0.0, 0.05, 0.0])
sp_n = ed.normalize(sp - cen_)
strap = ed.ribbon('strap', sp, width=0.038, normal=sp_n, camber=0.1, nu=3)
ed.push_out(strap, S, 0.016)
KL.thick(strap, 0.004, offset=-1)
ed.assign_look(strap, LK['leather'])
rp = P('chest', [0.168, 0.07, -0.02])
ring_plate = ed.lathe('strap_boss', [[0.0, 0.009], [0.018, 0.008], [0.026, 0.004], [0.028, 0.0], [0.0, 0.0]], 20, origin=rp + ed.normalize(rp - cen_) * 0.004,
                      axis=ed.normalize(rp - cen_), caps=(True, False))
ed.assign_look(ring_plate, LK['bronze'])

# ---- the sash: thick crimson silk wound three times, knotted at the left hip, two long ends -----------------------------------
SS = ed.grid_surface(sash, 0.006)
root = rig.chain_points('sashA')[0]
best, bu = 1e9, 0.1
for u in np.linspace(0, 1, 200):
    p_, n_, _, _ = ed.surface_normal(SS, u, 0.45)
    dd = np.linalg.norm(p_ - root)
    if dd < best:
        best, bu = dd, u
kp, kn, ku, kv = ed.surface_normal(SS, bu, 0.45)
kn = ed.normalize(kn)
kup = ed.normalize(np.array([0, 0, 1.0]) - kn * kn[2])
kside = np.cross(kup, kn)
knot_parts = [ed.ellipsoid('knot_core', kp + kn * 0.018, [0.034, 0.03, 0.026], np.stack([kside, kup, kn], axis=1), (14, 10))]
for sg in (1, -1):
    lp = []
    for a in np.linspace(0, 2 * np.pi, 25)[:-1]:
        lp.append(kp + kn * (0.016 + 0.012 * np.cos(a) ** 2) + kside * sg * (0.045 + 0.04 * np.cos(a)) + kup * (0.03 * np.sin(a) + sg * 0.012 * np.cos(a)))
    lp = np.array(lp + lp[:1])
    lo = ed.sweep('knot_loop', lp, np.array([[1, 0], [0.4, 0.6], [-0.4, 0.6], [-1, 0], [-0.4, -0.6], [0.4, -0.6]]), radius=0.016, up=kn, close=True)
    knot_parts.append(lo)
knot = ed.join(knot_parts, 'sash_knot')
ed.wrinkle(knot, amount=0.002, scale=60, seed=4, stretch=(1, 1, 1))
ed.assign_look(knot, LK['sash'])
sash_ends = []
for k_, (ch, w) in enumerate((('sashA', 0.115), ('sashB', 0.095))):
    cp = rig.chain_points(ch)
    cp = np.vstack([kp + kn * 0.02, cp[1:]])
    path = ed.polyline(cp, 22)
    # the ends hang over the coat tails: keep them in front of the front-left tail
    nrm_ = np.tile(kn * np.array([1, 1, 0.0]) / max(np.linalg.norm(kn[:2]), 1e-6), (len(path), 1))
    e_ = ed.ribbon('sashEnd%d' % k_, path, width=[[0, w * 0.55], [0.15, w], [1, w * 0.9]], normal=nrm_, camber=0.14, nu=4)
    q = ed.get_attr(e_, 'ed_uv')
    e_['ed_chain'] = ch
    KL.thick(e_, 0.005, offset=0.0)
    ed.assign_look(e_, LK['sash'])
    fr = np.nonzero(ed.get_attr(e_, 'ed_uv')[:, 1] > 0.9)[0]
    sash_ends.append(e_)

# trim along the tails' hems and front / slit edges
for tl, (nm, arc_, n_) in zip(tails, TAILS):
    nT, rT = tl['ed_grid']
    cols_ = {'tailFL': [0], 'tailBL': [nT - 1], 'tailBR': [0], 'tailFR': [nT - 1]}[nm]
    facing(tl, cols_, [rT - 1], trim_n=2, face_n=0, lift=0.002, code=MOTIF_FLAME + 0.25)

stage_done(2, 'stage2')

# ==== 3. arms, boots, head, hair ====================================================================================================
# forearm wraps (undyed hemp) from below the elbow over the wrist and the palm; the bracers sit over them
wraps, bracers = [], []
for s in ('R', 'L'):
    fa = 'foreArm' + s
    zs = 1.0 if s == 'R' else -1.0
    a, b = P(fa, [0, -0.3 * Lf, 0]), P('hand' + s, [0, -0.012, 0])
    e1, e2 = rig.vec(fa, [1, 0, 0]), rig.vec(fa, [0, 0, 1])
    rad = KL.limb_radius(S.subset(['arm' + s]), a, b, e1, e2, [0, 0.35, 0.7, 1.0])
    w = ed.helix_wrap('wrapA' + s, a, b, [[t, r + 0.004] for t, r in rad], turns=8, width=0.034, thick=0.0017, sides=10, axes=(e1, e2), seed=31 if s == 'R' else 32)
    ed.assign_look(w, LK['wrap'])
    wraps.append(w)
    hb = 'hand' + s
    hz = 0.003 * zs
    w = ed.helix_wrap('wrapH' + s, P(hb, [0, 0.012, hz]), P(hb, [0.004, -0.058, hz]), [[0, 0.031], [0.5, 0.039], [1, 0.044]], turns=4, width=0.026,
                      thick=0.0015, sides=14, ellipse=0.42, axes=(rig.vec(hb, [1, 0, 0]), rig.vec(hb, [0, 0, 1])), seed=33 if s == 'R' else 34)
    ed.assign_look(w, LK['wrap'])
    wraps.append(w)
    # bronze-studded leather bracer over the wrap: a moulded shell (oval, wider at the elbow end), rolled edges, a laced
    # seam on the inner side, three rows of domed bronze studs on the outer side
    y0, y1 = -0.42 * Lf, -0.9 * Lf
    radf = lambda t: float(np.interp(0.12 + 0.88 * (t * (y1 - y0) + y0 + 0.3 * Lf) / (0.7 * Lf), [x for x, _ in rad], [r_ for _, r_ in rad]))
    rings = []
    nb = 18
    for j, yy in enumerate(np.linspace(y0, y1, 9)):
        t = j / 8
        rr = radf(t) + 0.012 + 0.004 * (1 - t)
        rings.append([P(fa, [np.cos(ang) * rr * 1.06, yy, np.sin(ang) * rr * 0.96]) for ang in np.arange(nb) / nb * 2 * np.pi])
    bz = ed.loft('bracer' + s, np.array(rings), close=True)
    KL.thick(bz, 0.004, offset=-1)
    rims = []
    for t in (0.0, 1.0):
        yy = y0 + t * (y1 - y0)
        rr = radf(t) + 0.0145 + 0.004 * (1 - t)
        rims.append(ed.tube('bracerRim', np.array([P(fa, [np.cos(a_) * rr * 1.06, yy, np.sin(a_) * rr * 0.96]) for a_ in np.linspace(0, 2 * np.pi, 19)]), 0.0033, 5, caps=False))
    bz = ed.join([bz] + rims, 'bracer' + s)
    ed.assign_look(bz, LK['leather'])
    studs = []
    for row_ in range(3):
        t = 0.2 + 0.3 * row_
        yy = y0 + t * (y1 - y0)
        rr = radf(t) + 0.016 + 0.004 * (1 - t)
        for k_ in range(5):
            ang = np.radians(38 + k_ * 30) * zs
            pc = P(fa, [np.cos(ang) * rr * 1.06, yy, np.sin(ang) * rr * 0.96])
            nn = ed.normalize(rig.vec(fa, [np.cos(ang), 0, np.sin(ang)]))
            studs.append(ed.lathe('stud', [[0.0, 0.0048], [0.0042, 0.004], [0.0066, 0.0016], [0.0072, 0.0]], 7, origin=pc, axis=nn, caps=(True, False)))
    angs = (-np.pi / 2 * zs - 0.13, -np.pi / 2 * zs + 0.13)
    ln, rn = [], []
    for t in np.linspace(0.06, 0.94, 7):
        yy = y0 + t * (y1 - y0)
        rr = radf(t) + 0.0165 + 0.004 * (1 - t)
        ln.append(P(fa, [np.cos(angs[0]) * rr * 1.06, yy, np.sin(angs[0]) * rr * 0.96]))
        rn.append(P(fa, [np.cos(angs[1]) * rr * 1.06, yy, np.sin(angs[1]) * rr * 0.96]))
    lace = ed.lacing('bracerLace', np.array(ln), np.array(rn), radius=0.0016)
    ed.assign_look(lace, LK['cord'])
    studs = ed.join(studs, 'bracerStuds')
    ed.assign_look(studs, LK['bronze'])
    bracers.append(ed.join([bz, studs, lace], 'bracer' + s))

# boots: heavy leather to below the knee, a turned-down cuff, two strapped buckles, thick soles
boot_parts = []
Vf = ed.verts_of(feet)
for s in ('R', 'L'):
    sn = 'shin' + s
    zz = 1 if s == 'R' else -1
    rr0 = KL.limb_radius(S.subset(['leg' + s]), P(sn, [0, -0.36 * Ls, 0]), P(sn, [0, -0.38 * Ls, 0]), rig.vec(sn, [1, 0, 0]), rig.vec(sn, [0, 0, 1]), [0.0])[0][1]
    cuff = ed.lathe('bootCuff' + s, [[rr0 + 0.008, -0.004], [rr0 + 0.02, 0.006], [rr0 + 0.026, 0.024], [rr0 + 0.022, 0.044], [rr0 + 0.012, 0.05]], 26,
                    origin=P(sn, [0, -0.34 * Ls, 0]), axis=-rig.vec(sn, [0, 1, 0]))
    KL.thick(cuff, 0.003, offset=1)
    ed.assign_look(cuff, LK['leatherDark'])
    boot_parts.append(cuff)
    for yy, w_ in ((-0.6, 0.024), (-0.86, 0.02)):
        rr_ = KL.limb_radius(S.subset(['leg' + s]), P(sn, [0, yy * Ls, 0]), P(sn, [0, (yy - 0.02) * Ls, 0]), rig.vec(sn, [1, 0, 0]), rig.vec(sn, [0, 0, 1]), [0.0])[0][1]
        st = ed.lathe('bootStrap' + s, [[rr_ + 0.016, -w_ / 2], [rr_ + 0.019, -w_ / 4], [rr_ + 0.019, w_ / 4], [rr_ + 0.016, w_ / 2]], 24, origin=P(sn, [0, yy * Ls, 0]),
                      axis=rig.vec(sn, [0, 1, 0]))
        ed.assign_look(st, LK['leatherDark'])
        bk = ed.box('bootBuckle', (0.022, 0.026, 0.008), (0, 0, 0), bevel_w=0.0018)
        Rb = np.stack([rig.vec(sn, [1, 0, 0]), rig.vec(sn, [0, 1, 0]), rig.vec(sn, [0, 0, zz])], axis=1)
        M4 = np.eye(4); M4[:3, :3] = Rb; M4[:3, 3] = P(sn, [0.0, yy * Ls, zz * (rr_ + 0.021)])
        ed.transform(bk, M4)
        ed.assign_look(bk, LK['bronze'])
        boot_parts += [st, bk]
    # sole: the footprint, offset and extruded (thick hide sole)
    sel = (Vf[:, 0] < 0) if s == 'R' else (Vf[:, 0] > 0)
    H = KL.hull2d(Vf[sel & (Vf[:, 2] < 0.035)][:, :2])
    ring = KL.offset_poly(H, 0.006, 40)
    sole = ed.loft('sole' + s, np.array([np.hstack([ring, np.full((len(ring), 1), z)]) for z in (0.0005, 0.004, 0.02, 0.026)])
                   * np.array([1, 1, 1]) + np.array([0, 0, 0]), close=True, caps=(True, True))
    V_ = ed.verts_of(sole); c_ = V_[:, :2].mean(0)
    V_[V_[:, 2] > 0.019, :2] = c_ + (V_[V_[:, 2] > 0.019, :2] - c_) * 0.985
    ed.set_verts(sole, V_)
    ed.recalc_normals(sole)
    ed.shade(sole, 50)
    ed.assign_look(sole, LK['leatherDark'])
    boot_parts.append(sole)
# lift the boot uppers onto the soles
Vb = ed.verts_of(feet); Vb[:, 2] = np.maximum(Vb[:, 2], 0.022); ed.set_verts(feet, Vb)

# ---- head: face wrap under the mask, hair cap, topknot, headband, the loose mane ------------------------------------------------
HP = lambda off: P('head', np.asarray(off) * K)
S_head = S.subset(['head', 'neck', 'eyes'])
fw_axis = ed.ring_axis([HP([0.03, 0.075, 0]), HP([0.01, 0.0, 0]), P('neck', [0.0, 0.03, 0])], 14)
face = ed.wrap('facewrap', S_head, fw_axis, n=48, offset=lambda u, v: 0.007 + 0.008 * ed.smoothstep(0.2, 0.9, v), rmax=0.25)
ed.wrinkle(face, amount=0.0022, scale=34, seed=51, stretch=(0.3, 0.3, 1.0))
ed.push_out(face, S, 0.006)
# wound in overlapping bands (a long hemp scarf wrapped round jaw and neck): a sawtooth relief along a shallow helix,
# each band's lower edge standing proud of the next, a dark crease under it
_q = ed.get_attr(face, 'ed_uv'); _ph = (_q[:, 1] * 6.5 + _q[:, 0] * 1.0) % 1.0
_Vf = ed.verts_of(face); _Nf = ed.normals_of(face)
ed.set_verts(face, _Vf + _Nf * (0.0045 * _ph ** 1.6)[:, None])
_cav = ed.get_attr(face, 'ed_cav', np.ones(len(_Vf))).copy() if ed.get_attr(face, 'ed_cav') is not None else np.ones(len(_Vf))
ed.set_attr(face, 'ed_cav', np.clip(_cav * (0.55 + 0.45 * ed.smoothstep(0.0, 0.25, _ph)), 0, 2))
ed.assign_look(face, LK['scarf'])

hc_axis = ed.ring_axis([HP([-0.012, 0.215, 0]), HP([-0.01, 0.06, 0])], 12)
haircap = ed.wrap('haircap', S_head, hc_axis, n=40, offset=0.006, arc=(0.13, 0.87), rmax=0.22)
ed.wrinkle(haircap, amount=0.0018, scale=90, seed=61, stretch=(1.0, 1.0, 0.12), ridged=True)
q = ed.get_attr(haircap, 'ed_uv')
ed.set_attr(haircap, 'ed_uvw', np.stack([q[:, 0] * 40.0, q[:, 1], np.zeros(len(q))], axis=1), 'FLOAT_VECTOR')
ed.assign_look(haircap, LK['hair'])
# topknot (상투): a twisted bun on the crown bound with red cord, a bronze pin through it
tk_c = HP([-0.005, 0.228, 0.0]); tk_up = ed.normalize(rig.vec('head', [0.2, 1, 0]))
bun = ed.lathe('topknot', [[0.0, -0.005], [0.03, 0.0], [0.036, 0.018], [0.031, 0.036], [0.018, 0.05], [0.0, 0.054]], 20, origin=tk_c, axis=tk_up, caps=(False, False))
ed.wrinkle(bun, amount=0.0022, scale=110, seed=62, stretch=(1, 1, 1), along=tk_up)
qb = ed.get_attr(bun, 'ed_uv')
ed.set_attr(bun, 'ed_uvw', np.stack([qb[:, 0] * 16.0, qb[:, 1], np.zeros(len(qb))], axis=1), 'FLOAT_VECTOR')
ed.assign_look(bun, LK['hair'])
tie = ed.lathe('topknot_tie', [[0.034, 0.0], [0.037, 0.006], [0.037, 0.016], [0.034, 0.022]], 20, origin=tk_c - tk_up * 0.004, axis=tk_up)
ed.assign_look(tie, LK['cord'])
pin = ed.capsule('topknot_pin', tk_c + tk_up * 0.03 + rig.vec('head', [0, 0, 1]) * 0.07, tk_c + tk_up * 0.026 - rig.vec('head', [0, 0, 1]) * 0.075, 0.004, 0.0028, 8)
ed.assign_look(pin, LK['bronze'])
# headband: a short red band over the top edge of the mask, knotted at the back, two tails (spring chain 'band')
hb_axis = ed.ring_axis([HP([0.0, 0.198, 0]), HP([0.0, 0.17, 0])], 4)
hband = ed.wrap('headband', S_head, hb_axis, n=48, offset=lambda u, v: 0.0135 + 0.006 * np.cos(u * 2 * np.pi) ** 2 * (np.cos(u * 2 * np.pi) > 0), rmax=0.2)
ed.assign_look(hband, LK['strip'])
bp = rig.chain_points('band')
btails = []
for k_, off in enumerate((0.014, -0.014)):
    path = ed.polyline(np.vstack([bp[0], bp[1:] + rig.vec('head', [0, 0, off])]), 10)
    t_ = ed.ribbon('bandTail%d' % k_, path, width=[[0, 0.03], [1, 0.036]], normal=rig.vec('head', [-1, 0, 0]), camber=0.16, nu=2)
    KL.thick(t_, 0.003, offset=0.0)
    ed.assign_look(t_, LK['strip'])
    btails.append(t_)
bknot = ed.knot('band_knot', bp[0] + rig.vec('head', [0.008, 0, 0]), size=0.034, facing=rig.vec('head', [-1, 0, 0]), up=(0, 0, 1))
ed.assign_look(bknot, LK['strip'])
# the mane: layered strand locks from the crown down the nape onto the upper back, one spring chain per lock group
mane = []
rng = np.random.RandomState(9)
for ci, ch in enumerate(('maneA', 'maneB', 'maneC')):
    cp = rig.chain_points(ch)
    zc = rig.local('head', cp[0])[2]
    for j in range(13):
        dz = rng.uniform(-0.034, 0.034)
        # each lock leaves the hair cap at the crown, follows the skull back, then hangs along its chain
        head_run = [HP([0.0, 0.215, (zc + dz) * 0.7]), HP([-0.06, 0.205, (zc + dz) * 1.05]), HP([-0.095, 0.16, (zc + dz) * 1.1])]
        jit = rig.vec('head', [rng.uniform(-0.012, 0.004), 0, dz * 0.8])
        tailp = cp[1:] + jit * np.linspace(0.6, 1.6, len(cp) - 1)[:, None]
        path = ed.polyline(np.vstack([head_run, tailp]), 18)
        ln_ = rng.uniform(0.78, 1.0)
        path = path[: max(8, int(len(path) * ln_))]
        cen_h = P('head', [0.0, 0.1, 0.0])
        nrm_ = ed.normalize(path - cen_h)
        w0 = rng.uniform(0.036, 0.052)
        rb = ed.ribbon('mane_%s%d' % (ch, j), path + nrm_ * (0.004 + 0.0016 * j), width=[[0, w0 * 0.8], [0.45, w0 * 1.25], [1, w0 * 0.35]], normal=nrm_, camber=0.3, nu=3)
        qm = ed.get_attr(rb, 'ed_uv')
        ed.set_attr(rb, 'ed_uvw', np.stack([qm[:, 0] + j * 0.37 + ci, qm[:, 1], np.full(len(qm), 0.6)], axis=1), 'FLOAT_VECTOR')
        rb['ed_chain'] = ch
        ed.assign_look(rb, LK['hair'])
        mane.append(rb)

# hard pieces
mask_parts = KP.mask(rig, LK)
pd_parts = KP.pauldron(rig, LK)
sab_parts = KP.saber(rig, LK)
strip = KP.saber_strip(rig, LK)

stage_done(3, 'stage3', extra=((35, 3, 1.55, 1.1), (200, 8, 1.55, 2.4)))

# ==== 4. skin, parts, budgets, baked surface data, export =============================================================================
T4 = time.time()
SKIRT_BONES = ['hips', 'spine', 'thighR', 'thighL', 'hipJointR', 'hipJointL', 'thighTwistR', 'thighTwistL']


def chain_param(obj, ch):
    """Position along a spring chain (0 root .. 1 tip) by projection onto its bind-pose joints."""
    pts = rig.chain_points(ch)
    k, _, _ = ed.skin.path_param(ed.verts_of(obj), pts)
    return np.clip(k / (len(pts) - 1), 0, 1)


# solidify the open sheets (the lining is the red inner robe)
thick_multi(coat, 0.004, LK['lining'])
for sv in sleeves:
    KL.orient_out(sv, ed.verts_of(sv)[::max(1, len(sv.data.vertices) // 40)][:2])
    thick_multi(sv, 0.003, LK['lining'])
for tl in tails:
    thick_multi(tl, 0.004, LK['lining'])
KL.thick(sash, 0.005, offset=1.0)

# skin: garments copy the body's weights (they bend exactly like the limb inside)
for g in [coat] + sleeves + inner_sleeves + [emblem, strap] + bands + trousers + wraps:
    ed.transfer_weights(body, g, arm, smooth=1)
for g in boot_parts + [feet]:
    ed.transfer_weights(body, g, arm, smooth=1, bones=[b for b in rig.names if b.startswith(('shin', 'foot', 'toe', 'knee'))])
ed.transfer_weights(body, face, arm, smooth=2, bones=['head', 'neck', 'chest'])
ed.transfer_weights(body, sash, arm, smooth=2, bones=['hips', 'spine'])
ed.rigid(knot, 'hips')
ed.rigid(ring_plate, 'chest')
for e_ in sash_ends:
    ed.along_chain(e_, rig, e_['ed_chain'], param=chain_param(e_, e_['ed_chain']), parent='hips', root_blend=0.08)
for tl, (nm, arc_, n_) in zip(tails, TAILS):
    ed.transfer_weights(body, tl, arm, smooth=3, bones=SKIRT_BONES)
    if nm in ('tailFL', 'tailFR'):
        sd = 'L' if nm == 'tailFL' else 'R'
        W = ed.get_weights(tl)
        tot = sum(W.values()) if W else np.zeros(len(tl.data.vertices))
        fill = np.clip(1 - tot, 0, 1)
        for b_, k_ in (('thigh' + sd, 0.6), ('hipJoint' + sd, 0.15), ('hips', 0.25)):
            W[b_] = W.get(b_, 0) + fill * k_
        W = ed.smooth_weights(W, tl, 3, 0.5)
        ed.set_weights(tl, ed.limit_normalize(W, 4))
# the back tails: runtime cloth panels defined from the drape (the lower part rides the verlet grid)
panels = {}
for tl in tails:
    if tl.name not in ('tailBL', 'tailBR'):
        continue
    n_, r_ = tl['ed_grid']
    G = ed.verts_of(tl)[: n_ * r_].reshape(r_, n_, 3)
    if G[0, 0, 0] < G[0, -1, 0]:
        G = G[:, ::-1]
    pan = ed.define_panel(tl.name, G, anchor='hips', rig=rig, cols=4, rows=8, damping=0.04, margin=0.022, thickness=0.012, wind=0.8, stretch=1.0, bend=0.4)
    ed.bind_panel(tl, pan, share=lambda u, v: ed.smoothstep(0.12, 0.45, v))
    panels[tl.name] = pan
for g in [haircap, bun, tie, pin, hband, bknot] + list(mask_parts.values()):
    ed.rigid(g, 'head')
for t_ in btails:
    ed.along_chain(t_, rig, 'band', param=chain_param(t_, 'band'), parent='head', root_blend=0.12)
for rb in mane:
    ed.along_chain(rb, rig, rb['ed_chain'], param=chain_param(rb, rb['ed_chain']), parent='head', root_blend=0.12)
for o_ in pd_parts.values():
    ed.rigid(o_, 'deltoidR')
for i_, bz in enumerate(bracers):
    ed.rigid(bz, 'foreArmTwist' + ('R', 'L')[i_])
for o_ in sab_parts.values():
    ed.rigid(o_, 'weaponR')
ed.along_chain(strip, rig, 'strip', param=chain_param(strip, 'strip'), parent='weaponR', root_blend=0.05)

# high-poly copies of the forged pieces (bake sources): cracks and hammer marks on top of the sculpt
mask_hi = ed.duplicate(mask_parts['mask'], 'mask_hi')
pd_hi = ed.duplicate(pd_parts['shell'], 'pd_hi')
HC = rig.pt('head', [0.0, 0.1, 0.0])
cr_mask = KL.crack_paths(mask_hi, n=4, seed=11, step=0.0035, length=(8, 18), select=lambda V, N: np.einsum('ij,ij->i', N, ed.normalize(V - HC)) > 0.5)
DC = rig.pt('deltoidR', [0.0, 0.0, 0.0])
cr_pd = KL.crack_paths(pd_hi, n=6, seed=13, step=0.0045, length=(10, 22), select=lambda V, N: np.einsum('ij,ij->i', N, ed.normalize(V - DC)) > 0.4)
for hi, cr in ((mask_hi, cr_mask), (pd_hi, cr_pd)):
    KL.hammer(hi, 0.00035, 160, seed=5)
    ed.engrave(hi, cr, width=0.0026, depth=0.0013, falloff=1.8)
# budgets: decimate the dense pieces (cloth keeps its borders; the SDF sculpts go to their game resolution)
for o_, n_ in ((mask_parts['mask'], 2900), (pd_parts['shell'], 4300), (coat, 4600), (face, 1500), (sash, 1200)):
    ed.decimate_to(o_, n_)
# baked maps: one atlas for the gear slot (pauldron left half, mask right half): object-space normals + AO / albedo
for lo, (u0, u1) in ((pd_parts['shell'], (0.0, 0.5)), (mask_parts['mask'], (0.5, 1.0))):
    ed.uv_unwrap(lo, angle=75, margin=0.005)
    me_ = lo.data
    uvl = me_.uv_layers['ed_bake']
    a_ = np.empty(len(me_.loops) * 2, dtype=np.float32); uvl.data.foreach_get('uv', a_)
    a_ = a_.reshape(-1, 2); a_[:, 0] = u0 + a_[:, 0] * (u1 - u0)
    uvl.data.foreach_set('uv', a_.reshape(-1))
    ed.set_attr(lo, 'ed_bakew', np.ones(len(me_.vertices), dtype=np.float32))
for tl in tails:
    ed.decimate_to(tl, 1250 if tl.name in ('tailBL', 'tailBR') else 1050)
for o_ in sleeves:
    ed.decimate_to(o_, 1650)
for o_ in trousers:
    ed.decimate_to(o_, 800)

# ember light in the cracks of the mask and the pauldron: the authored cracks glow (hot core, soft halo) + hot patches
for lo, cr, base, seed in ((mask_parts['mask'], cr_mask, 0.2, 5), (pd_parts['shell'], cr_pd, 0.14, 8)):
    KL.vein_patches(lo, base=base, f=10, seed=seed)
    dcr = KL.dist_to_paths(ed.verts_of(lo), cr)
    g = ed.get_attr(lo, 'ed_glow').copy()
    g[:, 0] = np.maximum(g[:, 0], 0.5 * np.exp(-(dcr / 0.0026) ** 2))
    g[:, 1] = np.maximum(g[:, 1], 0.6 * np.exp(-(dcr / 0.0045) ** 2))
    ed.set_attr(lo, 'ed_glow', g, 'FLOAT_VECTOR')
gear_low = ed.join([pd_parts['shell'], mask_parts['mask']], 'armour')
GEAR_MAPS = KL.bake_maps_clean([pd_hi, mask_hi], gear_low, size=(1024, 1024), name='kael_gear', out_dir=SCRATCH, extrusion=0.01, samples=16)
gear_low['ed_maps'] = 'kael_gear'
ed.delete([pd_hi, mask_hi])
extras = [o_ for k_, o_ in list(mask_parts.items()) + list(pd_parts.items()) if k_ not in ('mask', 'shell')]
for o_ in extras:
    KL.zero_attrs(o_)
armour = ed.join([gear_low] + extras, 'armour')
armour['ed_maps'] = 'kael_gear'

# the body only where it shows: chest, hands, the neck under the face wrap edge
covers = [coat, face, haircap, hband] + sleeves + inner_sleeves + trousers + wraps + bands + tails + [sash, feet, armour] + bracers
reg = ed.get_attr(body, 'ed_region')
removed = ed.cull_hidden(body, covers, keep=np.isin(reg, [3]))
ed.log('body culled faces', removed)

parts = [
    (body, 'body', 'gear', ()),
    (ed.join([feet] + boot_parts, 'boots'), 'boots', 'gear', ()),
    (ed.join(bracers, 'bracers'), 'bracers', 'gear', ()),
    (armour, 'armour', 'gear', ()),
    (ed.join([haircap, bun, tie, pin], 'hairHard'), 'hairHard', 'gear', ()),
    (ed.join([coat] + sleeves + inner_sleeves + [emblem, strap, ring_plate] + bands + [sash, knot] + wraps + [face, hband, bknot] + trousers, 'robe'), 'robe', 'cloth', ()),
    (ed.join(btails, 'bandTails'), 'bandTails', 'cloth', ()),
    (ed.join(sash_ends, 'sashEnds'), 'sashEnds', 'cloth', ()),
    (ed.join(mane, 'mane'), 'mane', 'hair', ('cutout',)),
    (ed.join(list(sab_parts.values()), 'saber'), 'saber', 'blade', ()),
    (strip, 'strip', 'blade', ('cutout',)),
]
for tl in tails:
    parts.append((tl, tl.name, 'cloth', ('cloth',) if tl.name in panels else ()))
for i, (obj, name, slot, flags) in enumerate(parts):
    KL.clean(obj)
    ed.part(obj, name, slot, flags, order=i)
objs = [p_[0] for p_ in parts]
tris = {o.name: ed.tri_count(o, evaluated=False) for o in objs}
ed.log('triangles', sum(tris.values()), tris)
ed.bake_cavity(objs, samples=24, distance=0.1)
for o in objs:
    rep = ed.weight_report(o)
    if rep['unweighted'] or rep['max_influences'] > 4:
        ed.log('WEIGHTS', o.name, rep)
stage_done(4, 'stage4')
scripts = [os.path.abspath(__file__), os.path.join(os.path.dirname(os.path.abspath(__file__)), 'kael_lib.py'), os.path.join(os.path.dirname(os.path.abspath(__file__)), 'kael_parts.py')]
scripts += [os.path.join(ed.HERE, 'ed', f) for f in sorted(os.listdir(os.path.join(ed.HERE, 'ed'))) if f.endswith('.py')]
manifest = ed.export_asset(HERO, objs, scripts=scripts, textures=GEAR_MAPS)
if PREVIEW:
    if POSE:
        ed.pose_armature(arm, rig, POSE)
    ed.preview_sheet(HERO, 'final', height=2.05, samples=12, extra_views=((35, 3, 1.55, 1.1), (200, 8, 1.55, 2.4)))
ed.log('kael done', round(time.time() - T0, 1), 's')
