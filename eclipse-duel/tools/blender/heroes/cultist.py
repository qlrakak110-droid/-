# 흑일교 무사 / 호법 — the Black Sun Cult's fighters, modelled in Blender on the husk rig (tools/blender/rigs/cult.json).
#
#   /opt/blender-env/venv/bin/python tools/blender/heroes/cultist.py [--elite] [--preview]
#
#   무사   a wide ribbed bamboo hat over a cloth hood and mask, a crossed-collar black robe with a lamellar bib, a broad
#          crimson sash with a hanging knot, bandaged forearms and shins, cloth boots, a ring-pommel saber
#   호법   an iron war hat with a bronze rim, finial and red plume, lamellar aventail and cuirass, bronze pauldrons
# Rigid pieces (one bone each) over the husk's dark under-body; ~12k / ~14k triangles (the enemy budget is 16k).
# Output: src/rpg/foes/cultist.edb / protector.edb.

import sys
import os
import math
import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import rigidkit as K            # noqa: E402
from rigidkit import *          # noqa: E402,F401,F403
from rigidkit import ed, TAU    # noqa: E402

ARGS = sys.argv[1:]
ELITE = '--elite' in ARGS
rig = K.init('cult')
K.LOOKS['bandage'] = ((0.16, 0.13, 0.095), 0.95, 0.0, 0.8, 'plate')
K.LOOKS['sash'] = ((0.3, 0.03, 0.022), 0.9, 0.0, 0.7, 'plate')


def cloth(obj, amount=0.006, scale=16.0, seed=1):
    ed.wrinkle(obj, amount=amount, scale=scale, seed=seed)
    ed.shade(obj, angle=50)
    return obj


def head():
    b = 'head'
    # hood and mask: only a slit for the eyes
    hood = shell('hood', b, [(0.23, 0.05, 0.05), (0.2, 0.112, 0.108), (0.13, 0.136, 0.13), (0.05, 0.134, 0.126), (-0.03, 0.118, 0.108), (-0.07, 0.1, 0.1), (-0.1, 0.115, 0.125)], n=24, power=2.1, thick=0, sub=1, caps=(True, False))
    reg(cloth(hood, 0.004, 22, 3), b, 'robe')
    for s in (1, -1):
        reg(ball('eye%d' % s, b, [0.124, 0.105, 0.045 * s], (0.012, 0.007, 0.022), segs=(8, 5)), b, 'ember', glow=1.0)
    reg(shell('brow', b, [(0.128, 0.139, 0.132), (0.118, 0.142, 0.135)], n=14, a0=-70, a1=70, power=2.1, thick=0.004, bev=0), b, 'sash')
    if not ELITE:
        ribs = lambda th: 0.012 * np.cos(th * 28.0)
        hat = shell('hat', b, [(0.36, 0.006, 0.006), (0.345, 0.05, 0.05), (0.3, 0.14, 0.14), (0.245, 0.25, 0.25), (0.195, 0.355, 0.355), (0.185, 0.372, 0.372)], n=56, power=2.0, thick=0.01, bump=ribs, caps=(True, False), bev=0)
        reg(hat, b, 'straw')
        for (y, r) in ((0.3, 0.142), (0.245, 0.253), (0.19, 0.368)):
            reg(shell(f'hoop{y}', b, [(y + 0.006, r, r), (y - 0.006, r + 0.01, r + 0.01)], n=40, power=2.0, thick=0.004, bev=0), b, 'bandage')
        reg(ball('knob', b, [0, 0.365, 0], (0.02, 0.016, 0.02), segs=(8, 5)), b, 'bandage')
        # chin cord
        for s in (1, -1):
            reg(sweep('cord%d' % s, b, spline([[0.02, 0.2, 0.2 * s], [0.06, 0.08, 0.145 * s], [0.085, -0.03, 0.09 * s], [0.1, -0.07, 0.0]], 8), radius=0.006, section=5), b, 'sash')
    else:
        dome = shell('helm', b, [(0.085, 0.145, 0.142), (0.15, 0.146, 0.142), (0.21, 0.118, 0.114), (0.25, 0.07, 0.066), (0.264, 0.025, 0.024)], n=28, power=2.0, thick=0, sub=1, caps=(False, True))
        reg(dome, b, 'iron', chip=0.003)
        reg(shell('brim', b, [(0.1, 0.148, 0.146), (0.085, 0.24, 0.24), (0.08, 0.3, 0.3), (0.09, 0.315, 0.315)], n=36, power=2.0, thick=0.008), b, 'iron', chip=0.002)
        reg(shell('rim', b, [(0.096, 0.317, 0.317), (0.082, 0.322, 0.322), (0.076, 0.312, 0.312)], n=36, power=2.0, thick=0.005, bev=0), b, 'bronze')
        reg(ed.lathe('finial', [[0.03, 0.0], [0.02, 0.02], [0.036, 0.04], [0.016, 0.065], [0.008, 0.11], [0.0, 0.12]], segs=10, origin=B(b, [0, 0.262, 0])[0], axis=rig.vec(b, [0, 1, 0])), b, 'bronze')
        reg(ed.tassel('plume', B(b, [0, 0.37, 0])[0], direction=rig.vec(b, [-0.7, -1, 0.1]), length=0.22, radius=0.02, strands=12), b, 'sash')
        S = cone(b, [-0.01, 0.2, 0], 0.25, 0.26, [-1, 0, 0], bell=0.8, v0=0.42)
        lam(b, 'aventail', S, lace=False, rows=3, cols=16, plate_w=0.036, plate_h=0.06, thick=0.003, u_range=(-0.3, 0.3), seed=4)


def torso():
    c, sp, h = 'chest', 'spine', 'hips'
    robe = shell('robe', c, [(-0.16, 0.128, 0.172), (-0.06, 0.142, 0.186), (0.05, 0.158, 0.2), (0.15, 0.158, 0.21), (0.215, 0.13, 0.2), (0.25, 0.095, 0.15), (0.275, 0.075, 0.1)], n=28, power=2.4, thick=0, sub=1)
    reg(cloth(robe, 0.006, 14, 5), c, 'robe')
    # crossed collar: two lapels meeting low on the chest
    for s in (1, -1):
        pts = spline([[-0.04, 0.285, 0.085 * s], [0.07, 0.27, 0.1 * s], [0.14, 0.2, 0.075 * s], [0.166, 0.09, 0.01 * s], [0.16, -0.02, -0.06 * s]], 12)
        reg(sweep('lapel%d' % s, c, pts, radius=0.028, section=6, scale_y=0.3), c, 'sash' if s > 0 else 'bandage')
    reg(cloth(shell('waistrobe', sp, [(0.17, 0.132, 0.176), (0.06, 0.128, 0.17), (-0.05, 0.132, 0.176)], n=24, power=2.4, thick=0, sub=1), 0.006, 16, 6), sp, 'robe')
    if ELITE:
        S = cone(c, [0, 0.62, 0], 0.26, 0.86, [1, 0, 0], v0=0.5)
        lam(c, 'cuirassF', S, lace=False, rows=5, cols=12, plate_w=0.04, plate_h=0.07, thick=0.004, u_range=(-0.27, 0.27), seed=3)
        lam(c, 'cuirassB', lambda u, v: S(u + 0.5, v), lace=False, rows=5, cols=12, plate_w=0.04, plate_h=0.07, thick=0.004, u_range=(-0.27, 0.27), seed=5)
        for s, side in ((1, 'R'), (-1, 'L')):
            d = 'deltoid' + side
            a0, a1 = (-60, 240) if s > 0 else (120, 420)
            for k in range(3):
                y = 0.05 - k * 0.055; r = 0.118 - k * 0.006
                reg(shell(f'pl{k}' + side, d, [(y + 0.035, r * 0.75, r * 0.9, 0, 0.03 * s), (y - 0.01, r, r * 1.12, 0, 0.03 * s), (y - 0.04, r * 1.04, r * 1.18, 0, 0.03 * s)], n=18, a0=a0, a1=a1, power=2.1, thick=0.008), d, 'bronze' if k != 1 else 'iron', chip=0.002)
    else:
        S = cone(c, [0, 0.52, 0], 0.24, 0.62, [1, 0, 0], v0=0.56)
        lam(c, 'bib', S, lace=True, rows=3, cols=7, plate_w=0.036, plate_h=0.062, thick=0.0035, u_range=(-0.14, 0.14), seed=3)
    # the sash: a broad wrapped band, a knot at the left hip and two hanging ends
    reg(cloth(shell('sash', h, [(0.115, 0.146, 0.196), (0.06, 0.152, 0.203), (0.0, 0.15, 0.2), (-0.03, 0.143, 0.192)], n=28, power=2.4, thick=0.008, sub=1), 0.004, 30, 9), h, 'sash')
    reg(ed.knot('knot', B(h, [0.12, 0.05, -0.12])[0], size=0.04, facing=rig.vec(h, [0.8, 0, -0.6]), up=rig.vec(h, [0, 1, 0])), h, 'sash')
    for k, (dx, ln) in enumerate(((0.0, 0.36), (0.03, 0.27))):
        pts = spline([[0.135 + dx, 0.03, -0.125], [0.16 + dx, -0.1, -0.14 - dx], [0.165 + dx, -0.1 - ln * 0.6, -0.15 - dx], [0.15 + dx, -0.1 - ln, -0.14 - dx]], 10)
        reg(sweep(f'sashend{k}', h, pts, radius=lambda t: 0.03 + 0.012 * t, section=6, scale_y=0.16), h, 'sash')
    # the black-sun badge
    reg(ed.lathe('badge', [[0.0, 0.016], [0.03, 0.016], [0.034, 0.008], [0.05, 0.008], [0.054, 0.0], [0.05, -0.006]], segs=16, origin=B(h, [0.146, 0.045, 0.02])[0], axis=rig.vec(h, [1, 0, 0])), h, 'gold',
        glow=lambda Pl: np.clip(0.9 - np.hypot(Pl[:, 1] - 0.045, Pl[:, 2] - 0.02) / 0.03, 0, 1) * 0.0)
    reg(ed.lathe('badgesun', [[0.0, 0.004], [0.028, 0.004], [0.03, 0.0]], segs=14, origin=B(h, [0.163, 0.045, 0.02])[0], axis=rig.vec(h, [1, 0, 0])), h, 'black')
    # robe skirt: a back panel on the hips (the legs carry the front panels)
    back = shell('skirtB', h, [(0.0, 0.14, 0.19), (-0.15, 0.165, 0.215), (-0.32, 0.195, 0.245), (-0.5, 0.225, 0.275)], n=16, a0=70, a1=290, power=2.2, thick=0.006, sub=1)
    reg(cloth(back, 0.012, 9, 12), h, 'robe')


def limbs():
    def side_(side, s):
        t = 'thigh' + side
        a0, a1 = (-95, 125) if s > 0 else (-125, 95)
        front = shell('skirt' + side, t, [(0.1, 0.11, 0.115, 0, 0.0), (-0.06, 0.13, 0.13, 0.0, 0.01 * s), (-0.24, 0.15, 0.148, 0.01, 0.02 * s), (-0.42, 0.172, 0.165, 0.015, 0.03 * s)], n=14, a0=a0, a1=a1, power=2.2, thick=0.006, sub=1)
        reg(cloth(front, 0.012, 9, 14 + (1 if s > 0 else 0)), t, 'robe')
        reg(shell('hem' + side, t, [(-0.405, 0.174, 0.167, 0.015, 0.03 * s), (-0.425, 0.176, 0.169, 0.015, 0.03 * s)], n=14, a0=a0, a1=a1, power=2.2, thick=0.004, bev=0), t, 'sash')
        # sleeves, bandaged forearms and shins
        u = 'upperArm' + side
        reg(cloth(shell('sleeve' + side, u, [(0.02, 0.085, 0.09), (-0.1, 0.082, 0.086), (-0.22, 0.088, 0.092), (-0.28, 0.098, 0.102)], n=14, power=2.1, thick=0.006, sub=1), 0.007, 16, 20), u, 'robe')
        f = 'foreArm' + side
        reg(ed.helix_wrap('wrapF' + side, B(f, [0, -0.02, 0])[0], B(f, [0, -0.25, 0])[0], radius=lambda q: 0.064 - 0.012 * q, turns=8, width=0.04, thick=0.003, sides=10), f, 'bandage')
        sh = 'shin' + side
        reg(ed.helix_wrap('wrapS' + side, B(sh, [0, -0.06, 0])[0], B(sh, [0, -0.38, 0])[0], radius=lambda q: 0.076 - 0.018 * q, turns=9, width=0.048, thick=0.003, sides=10), sh, 'bandage')
        ft = 'foot' + side
        rings = []
        for (x, ry, rz, cy) in [(-0.08, 0.04, 0.045, -0.04), (-0.03, 0.058, 0.055, -0.03), (0.06, 0.05, 0.058, -0.045), (0.14, 0.038, 0.054, -0.058), (0.19, 0.022, 0.04, -0.066), (0.205, 0.006, 0.01, -0.07)]:
            th = np.linspace(0, TAU, 10, endpoint=False)
            yy = np.maximum(cy + ry * np.sin(th), -0.084)
            rings.append(B(ft, np.stack([np.full_like(th, x), yy, rz * np.cos(th)], 1)))
        boot = ed.loft('boot' + side, np.array(rings), close=True, caps=(True, True))
        ed.recalc_normals(boot); ed.shade(boot, angle=50)
        reg(boot, ft, 'robe')
        if ELITE:
            reg(shell('greave' + side, sh, [(-0.04, 0.086, 0.084), (-0.2, 0.08, 0.078), (-0.36, 0.062, 0.06)], n=12, a0=-110, a1=110, power=2.2, thick=0.007), sh, 'bronze', chip=0.002)
    both(side_)


def saber():
    w = 'weaponR'
    L0, L1, n = 0.1, 1.3, 22
    rings = []
    for i in range(n):
        t = i / (n - 1)
        x = L0 + (L1 - L0) * t
        belly = 0.03 + 0.022 * math.sin(math.pi * min(1.0, t * 1.1)) * (0.4 + 0.6 * t)
        back = 0.02
        if t > 0.88:
            k = (t - 0.88) / 0.12
            back = back * (1 - k) - 0.03 * k; belly = belly * (1 - k * k) + 0.032 * k
        curve = 0.07 * t * t
        ys = np.array([back, 0.0, -belly, 0.0]) + curve
        zs = np.array([0.0, 1.0, 0.0, -1.0]) * (0.007 * (1 - 0.5 * t) + 0.0015)
        rings.append(B(w, np.stack([np.full(4, x), ys, zs], 1)))
    blade = ed.loft('blade', np.array(rings), close=True, caps=(True, True))
    ed.recalc_normals(blade); ed.shade(blade, angle=30)
    reg(blade, w, 'steel')
    reg(ed.lathe('guard', [[0.0, 0.0], [0.05, 0.0], [0.056, 0.008], [0.05, 0.016], [0.0, 0.016]], segs=12, origin=B(w, [0.08, 0, 0])[0], axis=rig.vec(w, [1, 0, 0])), w, 'hilt')
    reg(ed.helix_wrap('grip', B(w, [0.075, 0, 0])[0], B(w, [-0.2, 0, 0])[0], radius=0.018, turns=9, width=0.034, thick=0.0025, sides=8), w, 'wrap')
    rp = np.array([[-0.245 + math.cos(t) * 0.03, math.sin(t) * 0.03, 0.0] for t in np.linspace(0, TAU, 13)])
    reg(sweep('pring', w, rp, radius=0.008, section=5), w, 'hilt')


head(); torso(); limbs(); saber()
name = 'protector' if ELITE else 'cultist'
K.finish(os.path.join(ed.ROOT, f'src/rpg/foes/{name}.edb'), budget=14000 if ELITE else 12500, hero=name, preview='--preview' in ARGS, height=2.2)
