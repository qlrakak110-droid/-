# 설리화 雪梨花 (iska) — 빙월쌍도, the Frost-Moon Twin Blades of the Cold Moon Palace, modelled in headless Blender on the
# game rig (rigs/iska.json; spring chains declared in src/fighters/iska/design.js).
#
#   /opt/blender-env/venv/bin/python tools/blender/heroes/iska.py [--stage N] [--no-preview] [--views]
#   -> assets/chars/iska/ (iska.edm, iska.json, index.js) + shots/blender/iska/*.png
#
# Stages: 1 body, 2 garments (robe, high crossed collars, floating sleeves, sash, draped split skirt, trousers, wraps,
# shoes), 3 head (silver half-mask, gauze veil, hair cap + bound tail + hairpin), bracers, jade pendant, brooches and the
# twin crescents, 4 skinning, culling, budgets, baked maps, export. --stage N stops after stage N with a preview sheet.

import math
import os
import sys
import time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import numpy as np
import edlib as ed
import iska_parts as IP

ARGS = sys.argv[1:]
STAGE = int(ARGS[ARGS.index('--stage') + 1]) if '--stage' in ARGS else 99
PREVIEW = '--no-preview' not in ARGS
VIEWS = '--views' in ARGS
HERO = 'iska'
T0 = time.time()

ed.reset_scene()
rig = ed.Rig(HERO)
arm = ed.build_armature(rig)
P = rig.pt
K = rig.K
H = 1.84          # framing height of the previews (hair ornament ~1.82)


QUICK = [a for a in ARGS if a.startswith('--quick')]


def quick_views(name):
    """--quick=bust,front,...: a few stills instead of the full sheet (iteration)."""
    views = {'bust': ((0, 0, 1.45), 0.9, 25, 3), 'front': ((0, 0, 0.95), 4.6, 0, 3), 'side': ((0, 0, 0.95), 4.6, 90, 3), 'back': ((0, 0, 0.95), 4.6, 180, 3),
             'q': ((0, 0, 0.95), 4.6, 35, 3), 'head': ((0, 0, 1.66), 0.6, 30, 2), 'headb': ((0, 0, 1.6), 0.8, 150, 2), 'waist': ((0, 0, 1.0), 1.4, 30, 3),
             'legs': ((0, 0, 0.5), 1.8, 30, 3), 'hand': ((-0.45, -0.15, 0.95), 0.6, 40, 10), 'blade': ((-0.5, -0.3, 1.05), 0.9, 60, 20)}
    paths = []
    for v in QUICK[0].split('=', 1)[1].split(','):
        t, d, yaw, pitch = views[v]
        paths.append(ed.render_view(HERO, '_q_' + v, t, d, yaw, pitch, size=(480, 540), samples=10, height=H))
    ed.contact_sheet(paths, os.path.join(ed.ROOT, 'shots', 'blender', HERO, name + '_q.png'), cols=len(paths))


def stage_done(n, name):
    if STAGE <= n:
        if '--bbox' in ARGS:
            for o in ed.bpy.context.scene.objects:
                if o.type == 'MESH':
                    V = ed.verts_of(o)
                    if len(V):
                        print('BBOX', o.name, np.round(V.min(0), 3), np.round(V.max(0), 3), len(V), [m.name for m in o.data.materials])
        if QUICK:
            quick_views(name)
        elif PREVIEW:
            ed.preview_sheet(HERO, name, height=H, samples=10)
        ed.log('stage', n, 'done', round(time.time() - T0, 1), 's')
        sys.exit(0)


# ---- 1. base body: slender, long-limbed, a woman's chest; pale cold skin --------------------------------------------------
LK = IP.looks()
body = ed.body(rig, arm=arm, tris=12000, build={'mass': 0.84, 'chest': 0.9, 'waist': 0.8, 'hips': 0.9, 'arms': 0.8, 'legs': 0.88, 'neck': 0.82,
                                                 'muscle': 0.45, 'bust': 0.6, 'hands': 0.86})
S = ed.body.last_sdf
ed.assign_look(body, LK['skin'])
ed.log('body', ed.tri_count(body), ed.weight_report(body))
stage_done(1, 'stage1')

# ---- 2. garments -------------------------------------------------------------------------------------------------------------
S_torso = S.subset(['torso', 'neck'])
Lu, Lf, Lt, Ls = (rig.data['lengths'][k] for k in ('upperArm', 'foreArm', 'thigh', 'shin'))
MOON = IP.MOTIF['moon']
thick, surf_path = IP.thick, IP.surf_path

# 2a. outer robe torso: moon-white silk from the base of the neck to below the sash, bloused above the sash
neck_base = P('neck', [0.0, 0.012, 0])
waist = P('hips', [0.0, -0.035, 0])
ax_t = ed.ring_axis([neck_base, P('chest', [0.0, 0.17, 0]), P('chest', [0.01, 0.05, 0]), P('spine', [0.01, 0.06, 0]), waist], 34)
TAU = 2 * np.pi
ease_t = lambda u, v: 0.004 + 0.016 * ed.smoothstep(0.35, 0.82, v) * (1 - ed.smoothstep(0.86, 1.0, v)) * (0.55 + 0.45 * np.cos(u * TAU) ** 2)
robe = ed.wrap('robe_torso', S_torso, ax_t, n=64, offset=0.013, ease=ease_t)
ed.push_out(robe, S, 0.006)
# relax the shoulder rings (rays glancing along the shoulders leave spikes), then clear the body again
qr = ed.get_attr(robe, 'ed_uv')
ed.smooth(robe, 0.6, 10, mask=1 - ed.smoothstep(0.18, 0.32, qr[:, 1]))
ed.push_out(robe, S, 0.006)
SR = ed.grid_surface(robe, 0.0)              # the full grid (before the V is cut): lapels, sash and brooch lie on it
# the crossed V opening (left over right): the inner robe shows between the two lapel edges above the crossing
VC = 0.34                                    # crossing height (v) on the sternum (the `heart` socket: the moon brooch)
UV0 = 0.155                                  # half-opening at the base of the neck (u: 0.25 = a quarter turn)
BW = 0.05                                    # lapel band width (m)
q = ed.get_attr(robe, 'ed_uv')
def us_(u):
    return ((u + 0.5) % 1.0) - 0.5          # signed: + toward the hero's left
def edge_top(v):                             # the top (left) lapel's edge: left of the neck -> crossing -> right of the waist
    t = np.clip(v / VC, 0, 1)
    return np.where(v < VC, UV0 * (1 - t) ** 0.9, -0.2 * ed.smoothstep(VC, 0.95, v) ** 0.9)
def edge_und(v):                             # the under (right) lapel's edge: right of the neck -> crossing
    return -UV0 * (1 - np.clip(v / VC, 0, 1)) ** 0.9
import bmesh
bm = bmesh.new(); bm.from_mesh(robe.data); bm.faces.ensure_lookup_table()
dead = []
for f in bm.faces:
    ua = np.array([us_(q[v.index, 0]) for v in f.verts])
    if ua.max() - ua.min() > 0.5:            # a face across the seam at the back (us jumps from +0.5 to -0.5)
        continue
    uu = ua.mean(); vv = np.mean([q[v.index, 1] for v in f.verts])
    if vv < VC and edge_und(vv) < uu < edge_top(vv):
        dead.append(f)
bmesh.ops.delete(bm, geom=dead, context='FACES')
bm.to_mesh(robe.data); bm.free(); robe.data.update()
ed.wrinkle(robe, amount=0.0022, scale=24, seed=3)
IP.orient_out(robe, ax_t)
ed.assign_look(robe, LK['moon'])
thick(robe, 0.003, inner=LK['moonIn'], max_tris=1900)

# 2b. inner robe (deep indigo) filling the V, its own crossing higher, a pale 동정 strip on its collar edge
ax_i = ed.ring_axis([neck_base, P('chest', [0.0, 0.17, 0]), P('chest', [0.01, 0.03, 0])], 16)
inner = ed.wrap('robe_inner', S_torso, ax_i, n=40, offset=0.0035, arc=(-0.2, 0.2), close=False)
ed.push_out(inner, S, 0.004)
IP.orient_out(inner, ax_i)
ed.assign_look(inner, LK['indigo'])
SI = ed.grid_surface(inner, 0.0, u_wrap=False)
def iu(us):                                  # signed turn -> the inner sheet's u (0..1 over its arc)
    return (us + 0.2) / 0.4
inner_bits = []
for nm, path in (('innerT', [(0.12, 0.0), (0.05, 0.25), (0.0, 0.42), (-0.06, 0.7)]), ('innerU', [(-0.12, 0.0), (-0.05, 0.25), (0.0, 0.42)])):
    pts, nrm = surf_path(SI, [(iu(u), v) for u, v in path], 22, 0.0025)
    side = ed.normalize(np.cross(np.gradient(pts, axis=0), nrm)) * (1 if nm == 'innerT' else -1)
    inner_bits.append(IP.band_along(nm, pts + side * 0.006, nrm, 0.024, LK['indigo'], thickness=0.0022, camber=0.03, nu=2))
    inner_bits.append(IP.band_along(nm + '_dj', pts - side * 0.004 + nrm * 0.0012, nrm, 0.011, LK['dongjeong'], thickness=0.0018, camber=0.05, nu=2))

# 2c. the high crossed collar: a standing band round the back of the neck (taller at the nape, sinking into the lapels
# at the front), and the two lapel bands along the opening's edges (indigo, silver snow-crystal embroidery); the top
# lapel runs on, diagonally, under the sash on the hero's right
def ring_stand(n=44):
    us = np.linspace(UV0 * 0.9, 1 - UV0 * 0.9, n)   # from the left front edge round the back to the right front edge
    rows = []
    for u in us:
        b0 = SR(u, 0.0)
        a = abs(us_(u)) / 0.5                 # 1 at the nape, ~UV0/0.5 at the front edges
        h = 0.016 + 0.05 * ed.smoothstep(UV0 / 0.5, 0.7, a)
        ang = np.arctan2(b0[0] - neck_base[0], -(b0[1] - neck_base[1]))   # 0 = front, + = hero's left
        c = P('neck', [0.0, 0.012 + h, 0])
        fr, sd = np.array([0, -1.0, 0]), np.array([1.0, 0, 0])
        d = np.cos(ang) * fr + np.sin(ang) * sd
        r = ed.body_radius(S_torso, c, fr, sd, [ang], rmax=0.2)[0]
        top = c + d * (r + 0.014 + 0.004 * a)
        bot = b0 - d * 0.004 + np.array([0, 0, -0.006])
        mid = bot * 0.5 + top * 0.5 + d * 0.004
        rows.append([bot, mid, top])
    G = np.array(rows).transpose(1, 0, 2)    # (3, n, 3): row 0 bottom .. row 2 top
    return IP.grid_mesh('collar_stand', G)
stand = ring_stand()
q2 = ed.get_attr(stand, 'ed_uv')
Lst = float(np.linalg.norm(np.diff(ed.verts_of(stand)[-44:], axis=0), axis=1).sum())
ed.set_attr(stand, 'ed_uvw', np.stack([q2[:, 0] * Lst / 0.05 * 0.5, q2[:, 1], np.full(len(q2), MOON + 0.25)], axis=1), 'FLOAT_VECTOR')
IP.orient_out(stand, [neck_base, P('neck', [0, 0.1, 0])])
thick(stand, 0.004, offset=-1.0)
ed.assign_look(stand, LK['band'])
collar = [stand]
for nm, sgn, fn_edge, v1 in (('lapelU', -1, edge_und, VC + 0.04), ('lapelT', 1, edge_top, 0.74)):
    vs = np.linspace(0.0, v1, 40)
    # band centre half a band inside the robe from the edge (the robe side: away from the opening)
    uv = [(float(fn_edge(v)) + sgn * 0.034, float(v)) for v in vs]
    if sgn > 0:
        uv = [(u if v < VC else float(fn_edge(v)) + 0.034, v) for u, v in uv]
    pts, nrm = surf_path(SR, uv, 46, 0.003)
    lap = ed.ribbon(nm, pts, width=[[0, 0.044], [0.1, BW], [1, BW]], normal=nrm, camber=0.04, nu=4)
    IP.brocade_uv(lap, float(np.linalg.norm(np.diff(pts, axis=0), axis=1).sum()), BW, MOON + 0.22)
    thick(lap, 0.0035, offset=-1.0)
    ed.assign_look(lap, LK['band'])
    collar.append(lap)

# 2d. floating sleeves: moon-white bells lined in indigo, fitted at the shoulder, widening from the elbow to a mouth that
# ends above the wrist at the front and hangs lower at the back (the pouch: spring chains slvR / slvL); an embroidered
# cuff band round the mouth. Under them: fitted indigo under-sleeves from the elbow to the wrist.
sleeves, cuffs, unders = [], [], []
for s_ in ('R', 'L'):
    ua, fa = 'upperArm' + s_, 'foreArm' + s_
    axis = [P(ua, [0.0, 0.06, 0]), P(ua, [0, -0.5 * Lu, 0]), P(fa, [0, 0, 0]), P(fa, [-0.006, -0.55 * Lf, 0]), P(fa, [-0.02, -1.15 * Lf, 0])]
    s_el = float(np.linalg.norm(P(fa, [0, 0, 0]) - P(ua, [0, 0.06, 0])))
    s_m = s_el + 0.6 * Lf                        # the mouth (front) at 60 % of the forearm
    def hem(u, s_m=s_m):
        back = np.cos((u - 0.5) * TAU) * 0.5 + 0.5          # 1 at the back, 0 at the front
        return s_m + 0.13 * back ** 2.2
    def off(u, sa, s_el=s_el, s_m=s_m):
        back = np.cos((u - 0.5) * TAU) * 0.5 + 0.5
        bell = ed.smoothstep(s_el - 0.12, s_m + 0.12, sa)
        return 0.004 + 0.012 * ed.smoothstep(0.0, 0.12, sa) + bell * (0.012 + 0.065 * back ** 1.5)
    sv = IP.sleeve_shell('sleeve' + s_, S.subset(['arm' + s_]), axis, n=36, rows=30, offset=off, hem=hem, min_r=0.028)
    ed.wrinkle(sv, amount=0.0045, scale=22, seed=11 if s_ == 'R' else 12, stretch=(1.0, 1.0, 1.0), along=None)
    ed.push_out(sv, S, 0.006)
    SV_ = ed.grid_surface(sv, 0.0)
    cuffs.append(IP.closed_band('cuff' + s_, SV_, 0.965, 0.034, LK['band'], MOON + 0.3, n=72, lift=0.0025))
    IP.orient_out(sv, axis[:4])
    ed.assign_look(sv, LK['moon'])
    thick(sv, 0.0035, inner=LK['moonIn'], max_tris=1150)
    sleeves.append(sv)
    # fitted under-sleeve, elbow -> wrist
    us_ax = ed.ring_axis([P(fa, [0, 0.02, 0]), P(fa, [0, -0.5 * Lf, 0]), P(fa, [0, -0.97 * Lf, 0])], 14)
    un = ed.wrap('under' + s_, S.subset(['arm' + s_]), us_ax, n=20, offset=0.006, rmax=0.12)
    ed.wrinkle(un, amount=0.002, scale=40, seed=13, stretch=(1, 1, 0.4))
    ed.push_out(un, S, 0.004)
    IP.orient_out(un, us_ax)
    ed.assign_look(un, LK['indigo'])
    unders.append(un)

# 2e. the wide sash: figured indigo silk wound twice round the waist over the robe, silver snow-crystal bands along both
# edges, a moon-white cord belt, a knot at the front left with two hanging ends (spring chains sashA / sashB)
sa_axis = ed.ring_axis([P('hips', [0.0, 0.152, 0]), P('hips', [0.0, 0.03, 0])], 7)
sash = ed.wrap('sash', S_torso, sa_axis, n=80, offset=0.026)
ed.wrinkle(sash, amount=0.0018, scale=46, seed=8, stretch=(1, 1, 0.25))
SS = ed.grid_surface(sash, 0.0)
sash_bits = [IP.closed_band('sash_edgeT', SS, 0.07, 0.016, LK['band'], MOON + 0.35, n=64, lift=0.004),
             IP.closed_band('sash_edgeB', SS, 0.93, 0.016, LK['band'], MOON + 0.35, n=64, lift=0.004)]
IP.orient_out(sash, sa_axis)
ed.assign_look(sash, LK['sash'])
thick(sash, 0.005, offset=-1.0, max_tris=1000)
cord_pts = np.array([ed.surface_normal(SS, u, 0.78)[0] + ed.surface_normal(SS, u, 0.78)[1] * 0.009 for u in np.linspace(0, 1, 65)])
cord = ed.tube('sash_cord', cord_pts, 0.0034, 5, caps=False)
ed.assign_look(cord, LK['cord'])
kp, kn, _, _ = ed.surface_normal(SS, 0.115, 0.5)
knot = ed.knot('sash_knot', kp + kn * 0.012, size=0.066, facing=kn, up=(0, 0, 1))
ed.assign_look(knot, LK['sash'])
sash_ends = []
for nm, w, tilt in (('sashA', 0.082, 0.0), ('sashB', 0.068, 0.012)):
    cp = rig.chain_points(nm)
    pts = ed.polyline(np.vstack([kp + kn * 0.02, cp[0] + kn * 0.03, cp[1:] + kn * 0.035]), 24)
    e = ed.ribbon(nm, pts, width=[[0, w * 0.55], [0.15, w], [1, w * 0.95]], normal=kn, camber=0.12, nu=4)
    q3 = ed.get_attr(e, 'ed_uv')
    thick(e, 0.003, offset=0.0)
    ed.assign_look(e, LK['sash'])
    # embroidered tip band across the end
    tp = pts[-4:]
    tb = IP.band_along(nm + '_tip', tp + kn * 0.0035, np.repeat(kn[None, :], len(tp), axis=0), w * 1.0, LK['band'], code=MOON + 0.4, thickness=0.0015, camber=0.12, nu=3)
    sash_ends.append((e, tb, nm))

# 2f. jade pendant (노리개) hanging from the cord at the front right: silver cap, knotted cord, pale jade disc, tassel
jp = rig.chain_points('jade')
jtop = ed.surface_normal(SS, 0.885, 0.78)
jt = jtop[0] + jtop[1] * 0.012
jdir = np.array([0, 0, -1.0])
jade_bits = []
jc = ed.tube('jade_cord', ed.polyline(np.array([jt, jt + np.array([0, -0.004, -0.03]), jt + np.array([0, -0.006, -0.06])]), 8), 0.0022, 5)
ed.assign_look(jc, LK['cord']); jade_bits.append(jc)
jk = ed.knot('jade_knot', jt + np.array([0, -0.008, -0.035]), size=0.022, facing=(0, -1, 0), up=(0, 0, 1))
ed.assign_look(jk, LK['cord']); jade_bits.append(jk)
jcen = jt + np.array([0, -0.008, -0.088])
disc = ed.lathe('jade_disc', [[0.009, -0.004], [0.021, -0.0045], [0.024, 0.0], [0.021, 0.0045], [0.009, 0.004], [0.009, -0.004]], 32, origin=jcen, axis=(0, -1, 0))
ed.assign_look(disc, LK['jade']); jade_bits.append(disc)
cap = ed.lathe('jade_cap', [[0.0, 0.012], [0.006, 0.01], [0.0075, 0.003], [0.005, 0.0]], 12, origin=jcen + np.array([0, 0, -0.026]), axis=(0, 0, 1), caps=(False, True))
ed.assign_look(cap, LK['silver']); jade_bits.append(cap)
jtas = ed.tassel('jade_tassel', jcen + np.array([0, 0, -0.027]), direction=(0, 0, -1), length=0.11, radius=0.012, strands=12, head=0.18)
ed.assign_look(jtas, LK['tassel'])

# 2g. the robe skirt below the sash: four panels (front left / right ride the thighs on follower + spring bones, back
# left / right are runtime cloth), moon white lined in indigo, an embroidered hem band, banded front edges; draped by
# the cloth solver against the hull of hips + legs (a skirt spans the gap between the legs)
S_skirt = S.subset(['torso', 'legR', 'legL'])
HEM_Z = 0.3
c0 = P('hips', [0.0, 0.05, 0])
sk_axis = ed.ring_axis([c0, np.array([c0[0], c0[1] + 0.005, (c0[2] + HEM_Z) / 2]), np.array([c0[0], c0[1] + 0.01, HEM_Z])], 30)
flare = lambda u, v: 0.026 + 0.13 * v ** 1.25 + 0.02 * np.cos(u * TAU) ** 2 * v
SKIRTS = (('skFL', (-0.008, 0.248), 34), ('skBL', (0.236, 0.508), 30), ('skBR', (0.492, 0.764), 30), ('skFR', (0.752, 1.008), 34))
skirts = []
for nm, arc_, n_ in SKIRTS:
    sk = ed.wrap(nm, S_skirt, sk_axis, n=n_, offset=flare, arc=arc_, rmax=0.5)
    ed.pleats(sk, count=26, depth=0.007, grow=(0.0, 1.0), phase=0.11 * len(skirts))
    skirts.append(sk)
legs_hull = ed.wrap('_legs_hull', S_skirt, ed.ring_axis([c0, np.array([c0[0], c0[1], 0.22])], 22), n=56, offset=0.016)
IP.orient_out(legs_hull, [c0, np.array([c0[0], c0[1], 0.22])])
for sk in skirts:
    ed.drape(sk, [legs_hull], pin=lambda q_, Pp: 1 - ed.smoothstep(0.05, 0.14, q_[:, 1]), frames=14, mass=0.25, tension=25, bending=5.0, thickness=0.006)
ed.remove_colliders([legs_hull])
ed.delete(legs_hull)
skirt_bands = {}
for sk in skirts:
    ed.push_out(sk, S, 0.014)
    ed.wrinkle(sk, amount=0.0022, scale=30, seed=5, stretch=(1.0, 1.0, 0.2))
    Sk = ed.grid_surface(sk, 0.0, u_wrap=False)
    bands = []
    hp, hn = [], []
    for u in np.linspace(0, 1, 40):
        p_, n_, _, _ = ed.surface_normal(Sk, u, 0.965)
        hp.append(p_); hn.append(n_)
    hp, hn = np.array(hp), np.array(hn)
    bands.append(IP.band_along(sk.name + '_hem', hp + hn * 0.0025, hn, 0.042, LK['band'], code=MOON + 0.32, thickness=0.0022, camber=0.03, nu=2))
    if sk.name in ('skFL', 'skFR'):
        ue = 0.025 if sk.name == 'skFL' else 0.975          # the front opening's edge
        ep, en = [], []
        for v in np.linspace(0.04, 0.94, 30):
            p_, n_, _, _ = ed.surface_normal(Sk, ue, v)
            ep.append(p_); en.append(n_)
        ep, en = np.array(ep), np.array(en)
        bands.append(IP.band_along(sk.name + '_edge', ep + en * 0.0025, en, 0.032, LK['band'], code=MOON + 0.25, thickness=0.0022, camber=0.03, nu=2))
    skirt_bands[sk.name] = bands
    ed.assign_look(sk, LK['moon'])

# 2h. fitted indigo trousers gathered into wrapped shins; cloth shoes (indigo uppers, pale layered soles)
trousers, wraps = [], []
for s_ in ('R', 'L'):
    ta = ed.ring_axis([P('thigh' + s_, [0.0, 0.03, 0]), P('thigh' + s_, [0, -0.5 * Lt, 0]), P('shin' + s_, [0, 0, 0]), P('shin' + s_, [0, -0.3 * Ls, 0])], 24)
    tro = ed.wrap('trousers' + s_, S.subset(['leg' + s_]), ta, n=26, offset=lambda u, v: 0.01 + 0.012 * np.sin(np.clip(v, 0, 1) * np.pi) ** 0.8, rmax=0.3)
    ed.wrinkle(tro, amount=0.0035, scale=24, seed=21 if s_ == 'R' else 22, stretch=(1.0, 1.0, 0.6))
    ed.push_out(tro, S, 0.006)
    IP.orient_out(tro, ta)
    ed.assign_look(tro, LK['trousers'])
    trousers.append(tro)
    sn = 'shin' + s_
    a, b = P(sn, [0, -0.2 * Ls, 0]), P('foot' + s_, [0, 0.018, 0])
    e1, e2 = rig.vec(sn, [1, 0, 0]), rig.vec(sn, [0, 0, 1])
    rad = IP.limb_radius(S.subset(['leg' + s_]), a, b, e1, e2, [0, 0.25, 0.5, 0.8, 1.0])
    rad = [[t, r + (0.016 if t < 0.1 else 0.007)] for t, r in rad]
    w = ed.helix_wrap('wrapL' + s_, a, b, rad, turns=11, width=0.032, thick=0.0017, sides=14, axes=(e1, e2), seed=41 if s_ == 'R' else 42)
    ed.assign_look(w, LK['wrap'])
    wraps.append(w)
shoes = ed.keep_regions(body, [5], 'shoes')
ed.displace(shoes, lambda Pp, Nn: np.full(len(Pp), 1.0), 0.0065)
Vb = ed.verts_of(shoes); Vb[:, 2] = np.maximum(Vb[:, 2], 0.0); ed.set_verts(shoes, Vb)
ed.decimate_to(shoes, 1300)
shoes.data.materials.clear()
ed.assign_look(shoes, LK['shoe'])
fz = np.array([np.mean([ed.verts_of(shoes)[i][2] for i in p.vertices]) for p in shoes.data.polygons])
ed.assign_look(shoes, LK['sole'], faces=np.nonzero(fz < 0.016)[0])
stage_done(2, 'stage2')

# ---- 3. head, hands, bracers, ornaments, weapons ------------------------------------------------------------------------------
S_head = S.subset(['head', 'neck', 'eyes'])
hx, hy, hz = rig.vec('head', [1, 0, 0]), rig.vec('head', [0, 1, 0]), rig.vec('head', [0, 0, 1])

# 3a. the silver half-mask: forehead, nose bridge and cheekbones in sculpted planes (a sharp nose ridge, a brow ridge, cheek
# planes), long slanted eye slits, bevelled edges, engraved frost lines, a crescent-moon crest over the brow
def mask_y(a):
    aa = abs(a)
    return 0.084 + 0.01 * float(ed.smoothstep(4, 28, aa)) + 0.032 * float(ed.smoothstep(46, 84, aa)), 0.19 - 0.012 * float(ed.smoothstep(40, 84, aa))
def mask_off(a, y):
    aa = abs(a)
    o = 0.0058
    o += 0.0032 * max(0.0, 1 - aa / 7.0) * (1 - ed.smoothstep(0.15, 0.17, y))                     # a sharp nose ridge
    o += 0.0026 * max(0.0, 1 - abs(y - 0.137) / 0.012) * (1 - ed.smoothstep(42, 64, aa))         # brow ridge (a crease)
    o += 0.0016 * np.exp(-((y - 0.097) / 0.012) ** 2) * np.exp(-((aa - 36) / 14) ** 2)           # cheekbone plane
    return float(o)
MG, MAY = IP.head_grid(rig, S_head, (-84, 84), mask_y, 84, 40, mask_off, smooth=6)
mask = IP.grid_mesh('mask', MG)
ed.set_attr(mask, 'ed_ay', np.concatenate([MAY.reshape(-1, 2), np.zeros((MAY.size // 2, 1))], axis=1), 'FLOAT_VECTOR')
def slit(a, y):
    """Inside an eye slit (long, slanted up toward the temple)?"""
    aa = abs(a); t = (aa - 21.5) / 14.5
    if abs(t) >= 1:
        return False
    yc = 0.1125 + 0.0065 * t
    return abs(y - yc) < 0.0068 * (1 - t * t) ** 0.6
import bmesh
bm = bmesh.new(); bm.from_mesh(mask.data); bm.faces.ensure_lookup_table()
flat = MAY.reshape(-1, 2)
dead = [f for f in bm.faces if slit(np.mean([flat[v.index, 0] for v in f.verts]), np.mean([flat[v.index, 1] for v in f.verts]))]
bmesh.ops.delete(bm, geom=dead, context='FACES')
bm.to_mesh(mask.data); bm.free(); mask.data.update()
flat = ed.get_attr(mask, 'ed_ay')[:, :2].astype(np.float64)       # (a, y) per vertex after the cut
def mask_pt(a, y, lift=0.0):
    i = (a + 84) / 168 * 83
    i0 = int(np.clip(np.floor(i), 0, 82)); fi = i - i0
    y0, y1 = mask_y(a)
    jf = (y - y0) / (y1 - y0) * 39
    j0 = int(np.clip(np.floor(jf), 0, 38)); fj = jf - j0
    p = (MG[j0, i0] * (1 - fi) + MG[j0, i0 + 1] * fi) * (1 - fj) + (MG[j0 + 1, i0] * (1 - fi) + MG[j0 + 1, i0 + 1] * fi) * fj
    return p
# the slit edges: snap the hole's boundary vertices onto the almond outline (smooth cut, not a stair-step of grid cells)
outline = []
for sg in (1, -1):
    for t in np.linspace(-1, 1, 60):
        yc = 0.1125 + 0.0065 * t; h = 0.0068 * (1 - t * t) ** 0.6
        outline += [(sg * (21.5 + 14.5 * t), yc + h), (sg * (21.5 + 14.5 * t), yc - h)]
outline = np.array(outline)
bm = bmesh.new(); bm.from_mesh(mask.data); bm.verts.ensure_lookup_table()
Vm = ed.verts_of(mask)
for v in bm.verts:
    if not v.is_boundary:
        continue
    a, y = flat[v.index]
    if abs(abs(a) - 21.5) > 19 or abs(y - 0.1125) > 0.02:
        continue
    dd = ((outline[:, 0] - a) * 0.00113) ** 2 + (outline[:, 1] - y) ** 2
    a2, y2 = outline[int(np.argmin(dd))]
    v.co = tuple(mask_pt(a2, y2))
    flat[v.index] = (a2, y2)
bm.to_mesh(mask.data); bm.free(); mask.data.update()
eng = []
for sg in (1, -1):
    eng.append(np.array([mask_pt(sg * a, 0.149 + 0.00005 * (a - 30) ** 2 * 0.1 + 0.0002 * a) for a in np.linspace(8, 60, 24)]))   # brow sweep
    eng.append(np.array([mask_pt(sg * (10 + 24 * t), 0.168 + 0.014 * t ** 1.4) for t in np.linspace(0, 1, 10)]))               # frost frond
ed.set_attr(mask, 'ed_cav', np.ones(len(mask.data.vertices), dtype=np.float32))
ed.engrave(mask, eng, width=0.0018, depth=0.0006, falloff=1.8)
IP.orient_out(mask, [rig.pt('head', [-0.02, 0.05, 0]), rig.pt('head', [-0.02, 0.2, 0])])
mask.data.materials.append(LK['silver'])
thick(mask, 0.0032, inner=LK['maskIn'], max_tris=1200)
ed.bevel(mask, 0.0009, 1, 50)
IP.paint_by_normal(mask, [rig.pt('head', [-0.03, 0.05, 0]), rig.pt('head', [-0.03, 0.2, 0])], LK['silver'], LK['maskIn'])
# crescent crest: a silver crescent moon (horns up) standing on the brow, a frost crystal star in its hollow
def crescent_outline(R=0.024, d=0.011, r2=0.0205, n=28):
    """Outline of a crescent: inside the circle (0, 0, R), outside the circle (0, d, r2), horns up."""
    # horn points: intersections of the two circles
    yh = (R * R - r2 * r2 + d * d) / (2 * d); xh = math.sqrt(max(R * R - yh * yh, 0))
    a0 = math.atan2(yh, xh); a1 = math.pi - a0
    outer = [(R * math.cos(a), R * math.sin(a)) for a in np.linspace(a1, a0 + 2 * math.pi, n)]
    b0 = math.atan2(yh - d, xh); b1 = math.pi - b0
    inner = [(r2 * math.cos(a), d + r2 * math.sin(a)) for a in np.linspace(b0 + 2 * math.pi, b1, n)][1:-1]
    return outer + inner
crest_c = P('head', [0.088, 0.215, 0])
crest_n = ed.normalize(hx * 0.95 + hy * 0.3)
crest_up = ed.normalize(hy - crest_n * np.dot(hy, crest_n))
crest = IP.extrude_poly('crest', crescent_outline(n=18), 0.004, crest_c - crest_up * 0.006 - crest_n * 0.004, np.cross(crest_up, crest_n), crest_up, crest_n, bevel=0.0011, segs=1)
ed.assign_look(crest, LK['silver'])
star = []
for k_ in range(8):
    a = k_ / 8 * TAU; rr = 0.0024 if k_ % 2 else 0.0085
    star.append((math.cos(a) * rr, math.sin(a) * rr))
cstar = IP.extrude_poly('crest_star', star, 0.003, crest_c + crest_up * 0.004 - crest_n * 0.002, np.cross(crest_up, crest_n), crest_up, crest_n, bevel=0.0008, segs=1)
ed.assign_look(cstar, LK['crystal'])
# glowing eyes behind the slits, a dark backing round them
eyes = []
for sg in (1, -1):
    c = P('head', [0.088 * K, 0.1125, sg * 0.0345 * K])
    R3 = np.stack([hx, hy, hz], axis=1)
    e = ed.ellipsoid('eye', c, [0.006, 0.0042, 0.013], R3, (12, 6))
    ed.assign_look(e, LK['eye'])
    eyes.append(e)
BG, BAY = IP.head_grid(rig, S_head, (-40, 40), lambda a: (0.098, 0.128), 24, 8, lambda a, y: 0.0012)
backing = IP.grid_mesh('mask_backing', BG)
IP.orient_out(backing, [rig.pt('head', [-0.02, 0.05, 0]), rig.pt('head', [-0.02, 0.2, 0])])
ed.assign_look(backing, LK['maskIn'])
eyes = ed.join(eyes + [backing], 'eyes')

# 3b. gauze veil (면사) from under the mask over the mouth and chin, tucked into the high collar
def veil_y(a):
    return -0.07 + 0.012 * float(ed.smoothstep(40, 90, abs(a))), mask_y(a)[0] + 0.003
VG, VAY = IP.head_grid(rig, S_head, (-92, 92), veil_y, 40, 18, lambda a, y: 0.0035 + 0.012 * float(ed.smoothstep(0.06, -0.06, y)) + 0.004 * float(ed.smoothstep(60, 92, abs(a))), smooth=3)
veil = IP.grid_mesh('veil', VG)
ed.wrinkle(veil, amount=0.0009, scale=36, seed=31, stretch=(1, 1, 0.2))
ed.push_out(veil, S, 0.005)
IP.orient_out(veil, [rig.pt('head', [-0.02, -0.1, 0]), rig.pt('head', [-0.02, 0.2, 0])])
qv = ed.get_attr(veil, 'ed_uv')
ed.set_attr(veil, 'ed_uvw', np.stack([qv[:, 0] * 0.3, qv[:, 1] * 0.14, np.full(len(qv), 0.82)], axis=1), 'FLOAT_VECTOR')
ed.assign_look(veil, LK['gauze'])

# 3c. hair: combed back from the mask's crown to the tie, a bun pierced by the 비녀, the long bound tail (spring chain hair)
tie = rig.head('hair1')
def hair_off(u, v):
    us = ((u + 0.5) % 1.0) - 0.5
    front = 1 - ed.smoothstep(0.17, 0.24, np.abs(us))
    return 0.0055 - 0.012 * front * ed.smoothstep(0.12, 0.2, v)
hc_axis = ed.ring_axis([P('head', [-0.012, 0.222, 0]), P('head', [-0.02, 0.12, 0]), P('head', [-0.03, 0.035, 0])], 18)
haircap = ed.wrap('haircap', S_head, hc_axis, n=48, offset=hair_off, rmax=0.22)
Vh = ed.verts_of(haircap); Nh = ed.normals_of(haircap)
dvec = Vh - tie
ref1 = ed.normalize(np.cross(ed.normalize(P('head', [0, 0.1, 0]) - tie), np.array([1.0, 0, 0])))
phi = np.arctan2(dvec @ np.array([1.0, 0, 0]), dvec @ ref1)
groove = np.abs(np.sin(phi * 34)) ** 0.6
ed.set_verts(haircap, Vh + Nh * (groove * 0.0011)[:, None])
ed.set_attr(haircap, 'ed_cav', (0.75 + 0.25 * groove).astype(np.float32))
IP.orient_out(haircap, hc_axis)
ed.set_attr(haircap, 'ed_uvw', np.stack([phi * 12.0, np.linalg.norm(dvec, axis=1) / 0.2, np.zeros(len(Vh))], axis=1), 'FLOAT_VECTOR')
ed.assign_look(haircap, LK['hair'])
hp = rig.chain_points('hair')
tail_dir0 = ed.normalize(hp[1] - hp[0])
bun = ed.ellipsoid('hair_bun', tie + np.array([0, -0.004, 0.012]), [0.027, 0.025, 0.022], np.stack([np.array([1.0, 0, 0]), ed.normalize(np.cross(np.array([0, 0, 1.0]), [1, 0, 0])), np.array([0, 0, 1.0])], axis=1), (20, 12))
Vb_ = ed.verts_of(bun); Nb_ = ed.normals_of(bun)
ang_b = np.arctan2(Vb_[:, 0] - tie[0], Vb_[:, 2] - tie[2] - 0.012)
ed.set_verts(bun, Vb_ + Nb_ * (np.abs(np.sin(ang_b * 9 + Vb_[:, 1] * 200)) ** 0.7 * 0.0014)[:, None])
ed.set_attr(bun, 'ed_uvw', np.stack([ang_b * 4, (Vb_[:, 1] - Vb_[:, 1].min()) * 20, np.zeros(len(Vb_))], axis=1), 'FLOAT_VECTOR')
ed.assign_look(bun, LK['hair'])
tpath = ed.polyline(np.vstack([tie + np.array([0, 0.01, -0.006]), hp[1:]]), 60)
NS = 24
sec = np.array([[math.cos(a) * (1 + 0.09 * math.cos(9 * a) + 0.05 * math.cos(5 * a + 1)), math.sin(a) * (1 + 0.09 * math.cos(9 * a) + 0.05 * math.cos(5 * a + 1)) * 0.72] for a in np.linspace(0, TAU, NS, endpoint=False)])
tail = ed.sweep('hair_tail', tpath, sec, [[0, 0.015], [0.05, 0.018], [0.3, 0.024], [0.62, 0.023], [0.85, 0.016], [1.0, 0.005]], twist=lambda t: t * 2.4, caps=True,
                up=np.array([1.0, 0, 0]))
qt = ed.get_attr(tail, 'ed_uv')
ed.set_attr(tail, 'ed_uvw', np.stack([qt[:, 0] * 8, qt[:, 1] * 3.5, np.clip((qt[:, 1] - 0.8) * 4, 0, 1)], axis=1), 'FLOAT_VECTOR')
ed.assign_look(tail, LK['hair'])
# loose ends fanning out of the last binding (alpha-cut cards)
cards = []
Tt, Nt, Bt = ed.frames_along(tpath)
for k_ in range(9):
    a = k_ / 9 * TAU
    st = int(0.84 * 59)
    base = tpath[st] + 0.012 * (math.cos(a) * Nt[st] + math.sin(a) * Bt[st])
    d = ed.normalize(Tt[st] + 0.22 * (math.cos(a) * Nt[st] + math.sin(a) * Bt[st]))
    pts = ed.polyline(np.array([base, base + d * 0.06, base + d * 0.12 + np.array([0, 0.01 * math.cos(a), -0.012])]), 8)
    cd = ed.ribbon('hair_card', pts, width=[[0, 0.016], [1, 0.006]], normal=math.cos(a) * Nt[st] + math.sin(a) * Bt[st], camber=0.25, nu=2)
    qc = ed.get_attr(cd, 'ed_uvw')
    ed.set_attr(cd, 'ed_uvw', np.stack([qc[:, 0] + k_, qc[:, 1], qc[:, 1]], axis=1), 'FLOAT_VECTOR')
    q4 = ed.get_attr(cd, 'ed_uv'); ed.set_attr(cd, 'ed_uv', np.stack([q4[:, 0], 0.84 + 0.16 * q4[:, 1], q4[:, 2]], axis=1), 'FLOAT_VECTOR')
    ed.assign_look(cd, LK['hairCut'])
    cards.append(cd)
hair_cards = ed.join(cards, 'hair_cards')
# bindings: the silver tie at the head, two silver rings down the tail, a cord binding above the loose ends
bind = []
def tail_ring(t, length, r_add, look, segs=16, prof=None):
    i = int(t * 59)
    c = tpath[i]; d = Tt[i]
    r0 = float(ed.curve_fn([[0, 0.015], [0.05, 0.018], [0.3, 0.024], [0.62, 0.023], [0.85, 0.016], [1.0, 0.005]])(t)) + r_add
    pr = prof or [[r0 * 0.94, -length / 2], [r0 * 1.03, -length * 0.38], [r0 * 1.05, 0.0], [r0 * 1.03, length * 0.38], [r0 * 0.94, length / 2]]
    o = ed.lathe('tail_ring', pr, segs, origin=c, axis=d)
    ed.shade(o, 40)
    ed.set_attr(o, 'ed_uv', np.stack([np.zeros(len(o.data.vertices)), np.full(len(o.data.vertices), t), np.zeros(len(o.data.vertices))], axis=1), 'FLOAT_VECTOR')
    ed.assign_look(o, look)
    bind.append(o)
tail_ring(0.035, 0.024, 0.004, LK['silver'])
tail_ring(0.33, 0.016, 0.003, LK['silver'])
tail_ring(0.6, 0.016, 0.003, LK['silver'])
tail_ring(0.83, 0.02, 0.002, LK['cord'])
tail_binds = ed.join(bind, 'tail_binds')
# 비녀: a silver pin through the bun, a crescent finial on the hero's left with a dangling frost crystal
pin_c = tie + np.array([0, -0.004, 0.012])
pin_dir = ed.normalize(np.array([1.0, 0.08, -0.12]))
pin = ed.lathe('hairpin', [[0.0, -0.085], [0.0016, -0.075], [0.0028, -0.02], [0.0028, 0.07], [0.0036, 0.074], [0.0036, 0.082], [0.0, 0.085]], 8, origin=pin_c, axis=pin_dir, caps=(False, True))
ed.assign_look(pin, LK['silver'])
fin_c = pin_c + pin_dir * 0.094
fin_n = ed.normalize(np.cross(pin_dir, np.array([0, 0, 1.0])))
finial = IP.extrude_poly('pin_finial', crescent_outline(0.014, 0.0065, 0.012), 0.003, fin_c, ed.normalize(np.cross(np.array([0, 0, 1.0]), fin_n)), np.array([0, 0, 1.0]), fin_n, bevel=0.0007, segs=1)
ed.assign_look(finial, LK['silver'])
drop_top = fin_c - np.array([0, 0, 0.012])
chainp = ed.tube('pin_chain', ed.polyline(np.array([drop_top, drop_top - np.array([0, 0, 0.03])]), 6), 0.0008, 4)
ed.assign_look(chainp, LK['silverPlain'])
drop = ed.lathe('pin_drop', [[0.0, 0.0], [0.004, -0.004], [0.0045, -0.009], [0.0, -0.018]], 6, origin=drop_top - np.array([0, 0, 0.03]), axis=(0, 0, 1))
ed.shade(drop, 30)
ed.assign_look(drop, LK['crystal'])
hairpin = ed.join([pin, finial, chainp, drop], 'hairpin')

# 3d. hands: fingerless indigo leather wraps over the palms; silver bracers from the wrist to the sleeve mouth
gloves, bracers = [], []
for s_ in ('R', 'L'):
    hb, fa = 'hand' + s_, 'foreArm' + s_
    hzs = 0.003 * (1 if s_ == 'R' else -1)
    w = ed.helix_wrap('glove' + s_, P(hb, [0, 0.016, hzs]), P(hb, [0.004, -0.056, hzs]), [[0, 0.03], [0.5, 0.038], [1, 0.043]], turns=4, width=0.024, thick=0.0014,
                      sides=14, ellipse=0.42, axes=(rig.vec(hb, [1, 0, 0]), rig.vec(hb, [0, 0, 1])), seed=33 if s_ == 'R' else 34)
    ed.assign_look(w, LK['glove'])
    gloves.append(w)
    e1, e2 = rig.vec(fa, [1, 0, 0]), rig.vec(fa, [0, 0, 1])
    rings = []
    for t in np.linspace(0.5, 0.965, 16):
        c = P(fa, [0, -t * Lf, 0])
        AA = np.linspace(0, TAU, 40, endpoint=False)
        rb = ed.convexify(ed.body_radius(S.subset(['arm' + s_]), c, e1, e2, AA, rmax=0.12), AA, 30, True)
        fl = 0.0035 * (ed.smoothstep(0.9, 0.965, t) + ed.smoothstep(0.56, 0.5, t))
        rr = rb + 0.0125 + fl
        rings.append(c[None, :] + rr[:, None] * (np.cos(AA)[:, None] * e1[None, :] + np.sin(AA)[:, None] * e2[None, :]))
    br = ed.loft('bracer' + s_, np.array(rings), close=True)
    sd = 1 if s_ == 'R' else -1
    cpos = lambda t, a: P(fa, [0.0, -t * Lf, 0]) + (np.cos(a) * e1 + np.sin(a) * e2) * 0.042
    flake = []
    ctr_t, ctr_a = 0.73, sd * np.pi / 2
    for k_ in range(6):
        ang = k_ / 6 * TAU
        flake.append(np.array([cpos(ctr_t + 0.075 * math.cos(ang) * r, ctr_a + 0.55 * math.sin(ang) * r) for r in np.linspace(0, 1, 6)]))
    flake.append(np.array([cpos(0.53, a) for a in np.linspace(0, TAU, 40)]))
    flake.append(np.array([cpos(0.94, a) for a in np.linspace(0, TAU, 40)]))
    ed.set_attr(br, 'ed_cav', np.ones(len(br.data.vertices), dtype=np.float32))
    ed.subdivide(br, 1, simple=True)
    ed.engrave(br, flake, width=0.0022, depth=0.0008)
    IP.orient_out(br, [P(fa, [0, 0, 0]), P(fa, [0, -Lf, 0])])
    br.data.materials.append(LK['silver'])
    thick(br, 0.0026, inner=LK['maskIn'], max_tris=700)
    ed.bevel(br, 0.0008, 1, 50)
    IP.paint_by_normal(br, [P(fa, [0, 0, 0]), P(fa, [0, -Lf, 0])], LK['silver'], LK['maskIn'])
    bracers.append(br)

# 3e. the moon brooch where the collars cross (`heart` socket): a silver crescent holding a pale frost stone
hc = P('chest', [0.134, 0.07, 0])
hn = ed.normalize(rig.vec('chest', [1, 0, 0]) + rig.vec('chest', [0, 0.25, 0]))
hup = ed.normalize(rig.vec('chest', [0, 1, 0]) - hn * np.dot(rig.vec('chest', [0, 1, 0]), hn))
brooch = IP.extrude_poly('brooch', crescent_outline(0.019, 0.008, 0.016, n=16), 0.0045, hc - hn * 0.002, np.cross(hup, hn), hup, hn, bevel=0.0012, segs=1)
ed.assign_look(brooch, LK['silver'])
stone = ed.ellipsoid('brooch_stone', hc + hup * 0.003 + hn * 0.002, [0.0062, 0.0062, 0.0035], np.stack([np.cross(hup, hn), hup, hn], axis=1), (12, 8))
ed.assign_look(stone, LK['crystal'])
brooch = ed.join([brooch, stone], 'brooch')

# 3f. 월아쌍도: the twin crescent blades on the weapon bones (exact outline, grips and sockets of WEAPON_SPECS.crescents)
blades = {}
for s_, mz in (('R', 1.0), ('L', -1.0)):
    wb = 'weapon' + s_
    pieces = IP.crescent_pieces(lambda x, y, z, wb=wb, mz=mz: P(wb, [x, y, z * mz]), LK)
    objs = []
    for o_, lk in pieces:
        if mz < 0:
            IP.flip(o_)
        if lk != 'steel':
            ed.assign_look(o_, LK[lk])
        objs.append(o_)
    blades[s_] = ed.join(objs, 'crescent' + s_)
stage_done(3, 'stage3')

# ---- 4. skinning, culling, parts, budgets, baked surface data, export ----------------------------------------------------------
SKIRT_BONES = ['hips', 'spine', 'thighR', 'thighL', 'hipJointR', 'hipJointL', 'thighTwistR', 'thighTwistL']
ARM_BONES = lambda s_: ['chest', 'shoulder' + s_, 'deltoid' + s_, 'upperArm' + s_, 'upperArmTwist' + s_, 'elbow' + s_, 'elbowVol' + s_, 'foreArm' + s_, 'foreArmTwist' + s_, 'hand' + s_]

# what the body shows: hands, the face under the gauze, the neck between the collar and the hair; the rest is culled
covers = [robe, inner, mask, haircap, stand] + sleeves + unders + bracers + gloves + skirts + trousers + wraps + [shoes, sash] + collar[1:]
reg = ed.get_attr(body, 'ed_region')
removed = ed.cull_hidden(body, covers, keep=np.isin(reg, [3]))
ed.log('body culled faces', removed)

# torso garments ride the body exactly
for g in [robe, inner, stand] + inner_bits + collar[1:]:
    ed.transfer_weights(body, g, arm, smooth=1)
# sleeves: the arm inside them, the hanging back of the bell on the spring chain slvR / slvL
for s_, sv, cf in zip(('R', 'L'), sleeves, cuffs):
    for o_ in (sv, cf):
        ed.transfer_weights(body, o_, arm, smooth=2, bones=ARM_BONES(s_))
        V_ = ed.verts_of(o_)
        cp = rig.chain_points('slv' + s_)
        k_, c_, d_ = ed.skin.path_param(V_, np.vstack([P('foreArm' + s_, [-0.03, 0.02, 0]), cp]))
        fa_k, _, _ = ed.skin.path_param(V_, np.array([P('foreArm' + s_, [0, 0.05, 0]), P('foreArm' + s_, [0, -Lf, 0])]))
        back = np.clip(-(V_ - c_) @ rig.vec('foreArm' + s_, [1, 0, 0]) / 0.06, 0, 1)        # behind the forearm
        along = ed.smoothstep(0.25, 0.7, fa_k)                                                 # from mid forearm on
        share = np.clip(along * (0.25 + 0.75 * back), 0, 1) * 0.9
        Wc = ed.skin.chain_weights(rig.chain('slv' + s_), np.clip((k_ - 1) / (len(cp) - 1), 0, 1))
        Wb = ed.get_weights(o_)
        keys = set(Wb) | set(Wc)
        ed.set_weights(o_, ed.skin.limit_normalize({kk: Wb.get(kk, 0) * (1 - share) + Wc.get(kk, 0) * share for kk in keys}))
for s_, o_ in [('R', unders[0]), ('L', unders[1])]:
    ed.transfer_weights(body, o_, arm, smooth=1, bones=ARM_BONES(s_))
for s_, br in zip(('R', 'L'), bracers):
    ed.transfer_weights(body, br, arm, smooth=2, bones=['foreArm' + s_, 'foreArmTwist' + s_])
for s_, gl in zip(('R', 'L'), gloves):
    ed.transfer_weights(body, gl, arm, smooth=1, bones=['hand' + s_, 'foreArmTwist' + s_])
# the sash and its cord ride the waist; the knot too; the ends hang on their chains
for g in [sash, cord, knot] + sash_bits:
    ed.transfer_weights(body, g, arm, smooth=2, bones=['hips', 'spine'])
ends = []
for e, tb, nm in sash_ends:
    ed.along_chain(e, rig, nm, parent='hips', root_blend=0.1)
    ed.along_chain(tb, rig, nm, param=np.full(len(tb.data.vertices), 0.97))
    ends += [e, tb]
for o_ in jade_bits + [jtas]:
    k_, _, _ = ed.skin.path_param(ed.verts_of(o_), np.vstack([jt + np.array([0, 0, 0.02]), jp]))
    ed.along_chain(o_, rig, 'jade', param=np.clip((k_ - 1) / (len(jp) - 1), 0, 1), parent='hips', root_blend=0.15)
# skirts: front panels on the follower + spring bones (open with the legs), back panels on runtime cloth
cloth_panels = {}
for sk in skirts:
    nm = sk.name
    bands = skirt_bands[nm]
    n_, r_ = sk['ed_grid']
    G = ed.verts_of(sk)[: n_ * r_].reshape(r_, n_, 3)
    qv = ed.get_attr(sk, 'ed_uv')[:, 1]
    sk = ed.join([sk] + bands, nm)
    if nm in ('skBL', 'skBR'):
        if G[0, 0, 0] < G[0, -1, 0]:
            G = G[:, ::-1]
        pan = ed.define_panel(nm, G, anchor='hips', rig=rig, cols=5, rows=9, damping=0.045, margin=0.022, thickness=0.01, wind=0.75, stretch=1.0, bend=0.35)
        ed.transfer_weights(body, sk, arm, smooth=2, bones=SKIRT_BONES)
        ed.bind_panel(sk, pan, share=lambda u, v: ed.smoothstep(0.08, 0.4, v))
        cloth_panels[nm] = sk
    else:
        side = 'R' if nm == 'skFR' else 'L'
        Vs = ed.verts_of(sk)
        v = np.clip((c0[2] - Vs[:, 2]) / (c0[2] - HEM_Z), 0, 1)
        top = 1 - ed.smoothstep(0.02, 0.14, v)
        names = rig.chain('skF' + side)
        sch = np.clip((v - 0.3) / 0.7, 0, 1)
        Wc = ed.skin.chain_weights(names, sch, parent='skF' + side + '0', root_blend=0.12)
        W = {kk: vv * (1 - top) for kk, vv in Wc.items()}
        W['hips'] = W.get('hips', 0) + top
        ed.set_weights(sk, ed.skin.limit_normalize(W))
        ed.attach(sk, arm)
for sk in skirts:
    IP.orient_out(sk, sk_axis)
    thick(sk, 0.0035, inner=LK['moonIn'], max_tris=760)
for g in trousers + wraps:
    ed.transfer_weights(body, g, arm, smooth=1)
# head pieces are rigid; the veil runs from the head into the collar (neck at the bottom)
for o_ in (mask, eyes, crest, cstar, haircap, bun, hairpin):
    ed.rigid(o_, 'head')
Vv = ed.verts_of(veil)
tv = ed.smoothstep(P('head', [0, 0.02, 0])[2], P('head', [0, -0.06, 0])[2], Vv[:, 2])
ed.set_weights(veil, {'head': 1 - 0.6 * tv, 'neck': 0.6 * tv})
ed.along_chain(tail, rig, 'hair', parent='head', root_blend=0.05)
ed.along_chain(tail_binds, rig, 'hair', parent='head', root_blend=0.05)
ed.along_chain(hair_cards, rig, 'hair', parent='head')
ed.rigid(brooch, 'chest')
for s_ in ('R', 'L'):
    ed.rigid(blades[s_], 'weapon' + s_)

crest_all = ed.join([crest, cstar], 'crest')
parts = [
    (body, 'body', 'gear', ()),
    (ed.join([mask, crest_all, eyes], 'mask'), 'mask', 'gear', ('rigid',)),
    (ed.join([haircap, bun, tail], 'hair'), 'hair', 'gear', ()),
    (ed.join([hairpin, tail_binds], 'hairOrnaments'), 'hairOrnaments', 'gear', ()),
    (ed.join([robe, inner, stand] + inner_bits + collar[1:], 'robe'), 'robe', 'cloth', ()),
    (ed.join(sleeves + cuffs + unders, 'sleeves'), 'sleeves', 'cloth', ()),
    (ed.join([sash, cord, knot] + sash_bits + ends, 'sash'), 'sash', 'cloth', ()),
    (ed.join(trousers + wraps, 'legs'), 'legs', 'cloth', ()),
    (ed.join(bracers + gloves + [shoes, brooch] + jade_bits, 'fittings'), 'fittings', 'gear', ()),
    (ed.join([veil, hair_cards, jtas], 'gauze'), 'gauze', 'hair', ('cutout',)),
    (blades['R'], 'crescentR', 'blade', ('rigid',)),
    (blades['L'], 'crescentL', 'blade', ('rigid',)),
]
for sk in skirts:
    parts.append((sk, sk.name, 'cloth', ('cloth',) if sk.name in cloth_panels else ()))
for i, (obj, name, slot, flags) in enumerate(parts):
    ed.part(obj, name, slot, flags, order=i)
objs = [p_[0] for p_ in parts]
tris = {o_.name: ed.tri_count(o_, evaluated=False) for o_ in objs}
ed.log('triangles before budget', sum(tris.values()), tris)
BUDGET = {'robe': 7100, 'sleeves': 6800, 'sash': 4000, 'legs': 4100, 'skFL': 1900, 'skFR': 1900, 'skBL': 1800, 'skBR': 1800, 'body': 3700, 'mask': 4200,
          'hair': 4300, 'fittings': 7000}
for o_ in objs:
    if o_.name in BUDGET and tris[o_.name] > BUDGET[o_.name]:
        ed.decimate_to(o_, BUDGET[o_.name])
tris = {o_.name: ed.tri_count(o_, evaluated=False) for o_ in objs}
ed.log('triangles', sum(tris.values()), tris)
for o_ in objs:
    if ed.get_attr(o_, 'ed_bakew') is None:
        ed.set_attr(o_, 'ed_bakew', np.zeros(len(o_.data.vertices), dtype=np.float32))
ed.bake_cavity(objs, samples=20, distance=0.08)
for o_ in objs:
    rep = ed.weight_report(o_)
    if rep['unweighted'] or rep['max_influences'] > 4:
        ed.log('WEIGHTS', o_.name, rep)
stage_done(4, 'stage4')
SCRIPTS = [os.path.abspath(__file__), os.path.join(os.path.dirname(os.path.abspath(__file__)), 'iska_parts.py')] + \
    [os.path.join(ed.HERE, 'ed', f) for f in sorted(os.listdir(os.path.join(ed.HERE, 'ed'))) if f.endswith('.py')]
manifest = ed.export_asset(HERO, objs, scripts=SCRIPTS)
if PREVIEW:
    ed.preview_sheet(HERO, 'final', height=H, samples=12)
ed.log('iska done', round(time.time() - T0, 1), 's')


