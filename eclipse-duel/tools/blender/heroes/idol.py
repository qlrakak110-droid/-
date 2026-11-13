# 「흑일마신상 黑日魔神像」 — the boss, modelled in Blender on the game rig (tools/blender/rigs/idol.json).
#
#   /opt/blender-env/venv/bin/python tools/blender/heroes/idol.py [--preview] [--tris 78000]
#
# A guardian-deity statue in stone, bronze and lacquered lamellar: crowned helm with flame crest and horns, a stern mask,
# gorget, cuirass with a mirror plate, layered pauldrons, vambraces, lamellar tassets on a rope belt with tassels,
# poleyns, ridged greaves, upturned boots, the black-sun halo with a ring of flame tongues, and the great saber.
# Every piece is RIGID on one bone (a statue's plates ride over the joints of the dark under-body the JS kit lofts), so
# nothing stretches at elbows or knees whatever the pose. Per vertex: colour (look + wear + patina), cavity (ray-cast
# ambient occlusion), glow (eclipse fire in the cracks). Output: src/rpg/boss/idol.edb (binary, embedded by the build).

import sys
import os
import math
import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import rigidkit as K            # noqa: E402
from rigidkit import *          # noqa: E402,F401,F403
from rigidkit import ed, TAU    # noqa: E402

ARGS = sys.argv[1:]
BUDGET = int(ARGS[ARGS.index('--tris') + 1]) if '--tris' in ARGS else 78000
rig = K.init('idol')


# =====================================================================================================================
# HEAD
# =====================================================================================================================
def head():
    b = 'head'
    # helm dome with six raised ribs
    ribs = lambda th: 0.035 * np.maximum(0.0, np.cos(th * 6.0)) ** 6
    dome = shell('helm', b, [(0.085, 0.142, 0.14), (0.13, 0.146, 0.143), (0.18, 0.138, 0.134), (0.225, 0.112, 0.108), (0.255, 0.074, 0.07), (0.272, 0.03, 0.028)],
                 n=48, power=2.0, thick=0, sub=1, bump=ribs, caps=(False, True))
    reg(dome, b, 'bronze', chip=0.004)
    # brow band and flared brim with an upturned edge, riveted
    reg(shell('band', b, [(0.07, 0.15, 0.148), (0.1, 0.153, 0.15), (0.105, 0.147, 0.144)], n=40, power=2.0, thick=0.008), b, 'gold')
    reg(shell('brim', b, [(0.088, 0.15, 0.148), (0.07, 0.2, 0.2), (0.058, 0.245, 0.25), (0.066, 0.262, 0.268), (0.078, 0.268, 0.274)], n=40, a0=-128, a1=128, power=2.1, thick=0.008, sub=1), b, 'bronze', chip=0.003)
    reg(rivets('rv', b, 0.086, 0.153, 0.151, 18, r=0.0075, power=2.0), b, 'gold')
    # finial and the flame crest (three tongues rising from the brow)
    reg(ed.lathe('finial', [[0.034, 0.0], [0.024, 0.03], [0.05, 0.06], [0.055, 0.08], [0.022, 0.11], [0.014, 0.17], [0.03, 0.2], [0.012, 0.235], [0.0, 0.3]], segs=12,
                 origin=B(b, [0, 0.268, 0])[0], axis=rig.vec(b, [0, 1, 0])), b, 'gold')
    for k, (z, h, lean) in enumerate([(0.0, 0.36, 0.0), (0.052, 0.27, 0.35), (-0.052, 0.27, -0.35)]):
        pts = spline([[0.132, 0.11, z], [0.158, 0.17, z + lean * 0.03], [0.146, 0.25, z + lean * 0.07], [0.168, 0.11 + h * 0.86, z + lean * 0.1], [0.15, 0.11 + h, z + lean * 0.13]], 14)
        reg(sweep(f'crest{k}', b, pts, radius=lambda t: 0.03 * (np.sin(math.pi * np.minimum(1.0, t * 1.15)) ** 0.7) * (1 - 0.55 * t) + 0.002, section=8, scale_y=0.34), b, 'gold', glow=0.25)
    # horns sweeping out and up from the temples
    def horn(side, s):
        pts = spline([[0.03, 0.15, 0.13 * s], [0.035, 0.19, 0.22 * s], [0.02, 0.27, 0.285 * s], [-0.01, 0.39, 0.3 * s], [-0.03, 0.5, 0.27 * s]], 18)
        reg(sweep('horn' + side, b, pts, radius=lambda t: 0.034 * (1 - t) ** 0.8 + 0.003, section=9), b, 'stone')
        reg(ball('hornring' + side, b, [0.031, 0.165, 0.158 * s], (0.046, 0.022, 0.046)), b, 'gold')
    both(horn)
    # the mask: a stern face of stone under the brim
    face = shell('face', b, [(0.105, 0.128, 0.118), (0.06, 0.138, 0.124), (0.02, 0.134, 0.118), (-0.02, 0.118, 0.104), (-0.05, 0.092, 0.082), (-0.066, 0.06, 0.05)],
                 n=36, a0=-112, a1=112, power=2.15, thick=0.01, sub=2)
    # sculpt it: brow shelf, eye sockets, nose, cheeks, grim mouth
    L = rig.local(b, ed.verts_of(face))
    x, y, z = L[:, 0], L[:, 1], L[:, 2]
    g = lambda cy, cz, sy, sz: np.exp(-((y - cy) / sy) ** 2 - ((np.abs(z) - cz) / sz) ** 2)
    front = np.clip(x / 0.1, 0, 1)
    d = (0.016 * np.exp(-((y - 0.062) / 0.014) ** 2) * (0.6 + 0.4 * np.clip(np.abs(z) / 0.07, 0, 1))          # brow shelf
         - 0.02 * g(0.036, 0.046, 0.013, 0.028)                                                                 # eye sockets
         + 0.03 * np.exp(-((y - 0.012) / 0.03) ** 2 - (z / 0.014) ** 2) * (1 - 0.5 * np.clip((y - 0.012) / 0.04, 0, 1))   # nose
         + 0.011 * g(0.0, 0.06, 0.02, 0.022)                                                                    # cheek bones
         - 0.012 * np.exp(-((y + 0.032) / 0.006) ** 2) * np.clip(1 - np.abs(z) / 0.055, 0, 1)                   # mouth line
         + 0.012 * np.exp(-((y + 0.05) / 0.012) ** 2 - (z / 0.035) ** 2)) * front                               # chin
    N = ed.normals_of(face)
    ed.set_verts(face, ed.verts_of(face) + N * d[:, None])
    reg(face, b, 'stone', chip=0.0025)
    for s_ in (1, -1):
        reg(ball('eye%d' % s_, b, [0.126, 0.037, 0.046 * s_], (0.01, 0.0065, 0.021), segs=(8, 5)), b, 'ember', glow=1.0)
    # tusks, cheek guards, a third-eye boss on the brow
    def tusk(side, s):
        pts = spline([[0.118, -0.034, 0.03 * s], [0.134, -0.02, 0.034 * s], [0.136, 0.006, 0.037 * s]], 8)
        reg(sweep('tusk' + side, b, pts, radius=lambda t: 0.0085 * (1 - t) + 0.0012, section=6), b, 'gold')
        reg(shell('cheek' + side, b, [(0.07, 0.15, 0.146), (0.0, 0.148, 0.146), (-0.07, 0.11, 0.118), (-0.1, 0.07, 0.085)], n=10, a0=62 * s if s > 0 else -128, a1=128 if s > 0 else -62, power=2.1, thick=0.008), b, 'bronze', chip=0.002)
    both(tusk)
    reg(ball('thirdeye', b, [0.158, 0.105, 0.0], (0.012, 0.022, 0.016), segs=(10, 6)), b, 'ember', glow=1.0)
    # lamellar neck guard hanging from the back of the brim
    S = cone(b, [-0.01, 0.2, 0], 0.245, 0.255, [-1, 0, 0], bell=0.8, v0=0.42)
    lam(b, 'aventail', S, rows=4, cols=22, plate_w=0.03, plate_h=0.05, thick=0.003, u_range=(-0.3, 0.3), seed=4)


# =====================================================================================================================
# TORSO
# =====================================================================================================================
def torso():
    c = 'chest'
    pec = lambda th: 0.05 * np.exp(-((np.abs(th) - 0.55) / 0.42) ** 2) - 0.03 * np.exp(-(th / 0.12) ** 2)
    cuir = shell('cuirass', c, [(-0.17, 0.134, 0.178), (-0.09, 0.15, 0.192), (0.0, 0.176, 0.218), (0.09, 0.19, 0.238), (0.17, 0.182, 0.24), (0.225, 0.15, 0.225), (0.262, 0.105, 0.17)],
                 n=44, power=2.5, thick=0.014, sub=1, bump=None)
    L = rig.local(c, ed.verts_of(cuir)); th = np.arctan2(L[:, 2], L[:, 0])
    k = np.clip((L[:, 1] + 0.02) / 0.1, 0, 1) * np.clip((0.24 - L[:, 1]) / 0.06, 0, 1) * (L[:, 0] > 0)
    ed.set_verts(cuir, ed.verts_of(cuir) + ed.normals_of(cuir) * (pec(th) * 0.5 * k)[:, None])
    # three belly lames stepping down under the chest
    L = rig.local(c, ed.verts_of(cuir))
    step = 0.008 * (np.floor(np.clip((0.02 - L[:, 1]) / 0.06, 0, 3)) ) - 0.006 * np.exp(-((((0.02 - L[:, 1]) / 0.06) % 1.0) / 0.12) ** 2) * (L[:, 1] < 0.02)
    ed.set_verts(cuir, ed.verts_of(cuir) - ed.normals_of(cuir) * step[:, None])
    reg(cuir, c, 'stone', chip=0.006)
    for y in (0.02, -0.04, -0.1):
        reg(shell(f'lameband{y}', c, [(y + 0.006, 0.179 + (y - 0.02) * 0.28, 0.222 + (y - 0.02) * 0.27), (y - 0.006, 0.181 + (y - 0.02) * 0.28, 0.224 + (y - 0.02) * 0.27)], n=40, a0=-150, a1=150, power=2.5, thick=0.005, bev=0), c, 'gold')
    # gilded edge bands, the gorget
    reg(shell('cuirband', c, [(-0.185, 0.137, 0.181), (-0.15, 0.142, 0.186), (-0.146, 0.136, 0.18)], n=36, power=2.5, thick=0.008), c, 'gold')
    reg(shell('gorget', c, [(0.235, 0.135, 0.19), (0.27, 0.1, 0.13), (0.325, 0.085, 0.095), (0.335, 0.092, 0.102)], n=28, power=2.2, thick=0.009), c, 'bronze', chip=0.002)
    # the mirror plate over the heart: concentric rings and a burning core
    ax = rig.vec(c, [1, 0, 0])
    reg(ed.lathe('mirror', [[0.0, 0.03], [0.022, 0.028], [0.03, 0.02], [0.05, 0.022], [0.058, 0.012], [0.078, 0.014], [0.09, 0.006], [0.098, -0.004], [0.094, -0.014]], segs=28,
                 origin=B(c, [0.178, 0.085, 0])[0], axis=ax), c, 'bronze', glow=lambda Pl: np.clip(1.2 - np.hypot(Pl[:, 1] - 0.085, Pl[:, 2]) / 0.026, 0, 1), chip=0.0015)
    for i in range(8):
        a = i / 8 * TAU
        reg(ball(f'mstud{i}', c, [0.192, 0.085 + math.cos(a) * 0.082, math.sin(a) * 0.082], (0.008, 0.008, 0.008), segs=(6, 4)), c, 'gold')
    # shoulder straps
    def strap(side, s):
        pts = spline([[0.15, 0.2, 0.13 * s], [0.07, 0.262, 0.15 * s], [-0.06, 0.255, 0.15 * s], [-0.14, 0.18, 0.13 * s]], 12)
        reg(sweep('strap' + side, c, pts, radius=0.03, section=6, scale_y=0.22), c, 'iron')
    both(strap)
    # ---- the black sun behind the head: a black disc, a gold corona ring, a wheel of flame tongues -------------------
    cy, cx = 0.6, -0.215
    reg(ed.lathe('sun', [[0.0, 0.012], [0.3, 0.012], [0.318, 0.0], [0.3, -0.012], [0.0, -0.012]], segs=40, origin=B(c, [cx, cy, 0])[0], axis=ax), c, 'black')
    ringpts = np.array([[cx, cy + math.cos(a) * 0.33, math.sin(a) * 0.33] for a in np.linspace(0, TAU, 49)])
    reg(sweep('corona', c, ringpts, radius=0.012, section=6), c, 'gold', glow=0.55)
    for i in range(14):
        a = i / 14 * TAU + 0.11
        ln = 0.2 if i % 2 == 0 else 0.12
        r0, sw = 0.34, 0.5
        pts = []
        for t in np.linspace(0, 1, 9):
            r = r0 + ln * t; aa = a + sw * t * t * 0.5
            pts.append([cx + 0.012 * math.sin(t * 3.0), cy + math.cos(aa) * r, math.sin(aa) * r])
        reg(sweep(f'flame{i}', c, np.array(pts), radius=lambda t, ln=ln: (0.03 if ln > 0.15 else 0.022) * (np.sin(math.pi * np.minimum(1.0, t * 1.4 + 0.12)) ** 0.8) * (1 - 0.75 * t) + 0.0015, section=6, scale_y=0.3), c, 'gold', glow=0.3)
    # halo stem
    reg(sweep('stem', c, spline([[-0.14, 0.2, 0.0], [-0.2, 0.3, 0.0], [-0.21, 0.42, 0.0]], 6), radius=0.02, section=6), c, 'bronze')

    # ---- waist: spine plates, belt, rope, buckle -----------------------------------------------------------------------
    sp = 'spine'
    reg(shell('fauld', sp, [(0.16, 0.138, 0.184), (0.07, 0.132, 0.176), (-0.02, 0.134, 0.182), (-0.07, 0.14, 0.19)], n=36, power=2.5, thick=0.01, sub=1), sp, 'iron', chip=0.002)
    h = 'hips'
    reg(shell('belt', h, [(0.085, 0.146, 0.196), (0.07, 0.152, 0.202), (0.01, 0.154, 0.206), (-0.005, 0.148, 0.2)], n=40, power=2.5, thick=0.01), h, 'bronze', chip=0.002)
    reg(rivets('beltrv', h, 0.04, 0.156, 0.208, 22, r=0.0085, power=2.5), h, 'gold')
    loop = ring(h, 0.105, 0.156, 0.204, 72, power=2.5)
    loop = np.vstack([loop, loop[:1]])
    reg(ed.braid('rope', loop, width=0.04, thickness=0.026, pitch=0.05, taper=1.0, sides=5, per_cross=5), h, 'cord')
    reg(ed.lathe('buckle', [[0.0, 0.034], [0.02, 0.034], [0.03, 0.024], [0.05, 0.028], [0.066, 0.016], [0.08, 0.0], [0.076, -0.012]], segs=20, origin=B(h, [0.15, 0.04, 0])[0], axis=rig.vec(h, [1, 0, 0])), h, 'gold',
        glow=lambda Pl: np.clip(1.1 - np.hypot(Pl[:, 1] - 0.04, Pl[:, 2]) / 0.02, 0, 1))
    for s in (1, -1):
        top = B(h, [0.16, 0.09, 0.075 * s])[0]
        reg(ed.knot('knot%d' % s, top, size=0.03, facing=rig.vec(h, [1, 0, 0]), up=rig.vec(h, [0, 1, 0])), h, 'cord')
        reg(ed.tassel('tassel%d' % s, B(h, [0.168, 0.07, 0.078 * s])[0], direction=rig.vec(h, [0.12, -1, 0.05 * s]), length=0.2, radius=0.02, strands=12), h, 'cord')
    # back and front tabard panels of lamellar (on the hips), a stone codpiece plate
    Sc = cone(h, [0, 0.42, 0], 0.3, 0.92, [-1, 0, 0], v0=0.44)
    lam(h, 'skirtB', Sc, rows=6, cols=13, plate_w=0.042, plate_h=0.085, thick=0.004, u_range=(-0.17, 0.17), seed=7)
    reg(shell('tabard', h, [(0.0, 0.15, 0.085), (-0.14, 0.165, 0.08), (-0.3, 0.178, 0.07), (-0.36, 0.176, 0.045)], n=10, a0=-34, a1=34, power=2.0, thick=0.008, sub=1), h, 'stone', chip=0.003,
        glow=lambda Pl: 0.0 * Pl[:, 0])
    reg(shell('tabtrim', h, [(-0.345, 0.18, 0.062), (-0.375, 0.18, 0.04)], n=8, a0=-30, a1=30, power=2.0, thick=0.006), h, 'gold')


# =====================================================================================================================
# ARMS
# =====================================================================================================================
def arms():
    def arm(side, s):
        d = 'deltoid' + side
        # pauldron: a ridged cap and three lames, each a partial shell opening toward the body
        a0, a1 = (-60, 240) if s > 0 else (120, 420)
        rid = lambda th: 0.05 * np.exp(-(((th - math.radians(90 * s)) + math.pi) % TAU - math.pi) ** 2 / 0.02) + 0.022 * np.maximum(0.0, np.cos(th * 9.0)) ** 4
        cap = shell('pcap' + side, d, [(0.105, 0.03, 0.03, 0, 0.02 * s), (0.092, 0.09, 0.1, 0, 0.03 * s), (0.055, 0.132, 0.148, 0, 0.04 * s), (0.005, 0.15, 0.17, 0, 0.045 * s), (-0.03, 0.156, 0.178, 0, 0.045 * s)],
                    n=30, a0=a0, a1=a1, power=2.1, thick=0.012, sub=1, bump=rid, caps=(True, False))
        reg(cap, d, 'stone', chip=0.006)
        for k in range(3):
            y = -0.035 - k * 0.058
            r = 0.158 - k * 0.012
            reg(shell(f'plame{k}' + side, d, [(y + 0.03, r * 0.94, r * 1.08, 0, 0.04 * s), (y - 0.02, r, r * 1.14, 0, 0.04 * s), (y - 0.055, r * 1.03, r * 1.18, 0, 0.04 * s)],
                      n=26, a0=a0 + 10, a1=a1 - 10, power=2.1, thick=0.009), d, 'bronze' if k != 1 else 'iron', chip=0.003)
            reg(shell(f'ptrim{k}' + side, d, [(y - 0.05, r * 1.035, r * 1.185, 0, 0.04 * s), (y - 0.064, r * 1.04, r * 1.19, 0, 0.04 * s)], n=26, a0=a0 + 10, a1=a1 - 10, power=2.1, thick=0.007), d, 'gold')
        reg(ball('pboss' + side, d, [0.0, 0.03, 0.19 * s], (0.03, 0.03, 0.018), segs=(10, 6)), d, 'gold', glow=0.4)
        # upper arm: rerebrace with two bands
        u = 'upperArm' + side
        reg(shell('rere' + side, u, [(-0.07, 0.082, 0.084), (-0.16, 0.08, 0.082), (-0.245, 0.072, 0.074)], n=18, power=2.2, thick=0.008, sub=1), u, 'stone', chip=0.003)
        for y in (-0.085, -0.235):
            reg(shell(f'rband{y}' + side, u, [(y + 0.014, 0.086, 0.088), (y, 0.09, 0.092), (y - 0.014, 0.085, 0.087)], n=18, power=2.2, thick=0.006), u, 'gold')
        # couter: a fan plate on the elbow
        e = 'elbow' + side if rig.has('elbow' + side) else 'foreArm' + side
        reg(ball('couter' + side, e, [-0.035, 0.0, 0.03 * s], (0.062, 0.07, 0.075), segs=(12, 8)), e, 'bronze', chip=0.003)
        reg(ball('couterb' + side, e, [-0.07, 0.0, 0.03 * s], (0.018, 0.022, 0.022), segs=(8, 5)), e, 'gold')
        # vambrace with a raised spine, cuffs, a hand plate
        f = 'foreArm' + side
        spine_ = lambda th: 0.07 * np.exp(-(((th - math.radians(90 * s)) + math.pi) % TAU - math.pi) ** 2 / 0.05)
        reg(shell('vamb' + side, f, [(-0.03, 0.086, 0.088), (-0.09, 0.083, 0.085), (-0.17, 0.07, 0.072), (-0.235, 0.062, 0.064)], n=22, power=2.2, thick=0.008, sub=1, bump=spine_), f, 'bronze', chip=0.004)
        reg(shell('vcuff' + side, f, [(-0.02, 0.09, 0.092), (-0.045, 0.092, 0.094), (-0.05, 0.086, 0.088)], n=20, power=2.2, thick=0.006), f, 'gold')
        reg(shell('wcuff' + side, f, [(-0.225, 0.066, 0.068), (-0.25, 0.07, 0.072), (-0.258, 0.064, 0.066)], n=18, power=2.2, thick=0.006), f, 'gold')
        hd = 'hand' + side
        reg(ball('gaunt' + side, hd, [0.0, -0.05, 0.03 * s], (0.05, 0.062, 0.03), segs=(10, 6)), hd, 'bronze', chip=0.002)
    both(arm)


# =====================================================================================================================
# LEGS
# =====================================================================================================================
def legs():
    def leg(side, s):
        t = 'thigh' + side
        # lamellar tasset hanging over the thigh (rides with the leg), a stone cuisse under it
        S = cone(t, [0, 0.36, 0], 0.2, 0.74, [0.75, 0, 0.66 * s], v0=0.5)
        lam(t, 'tasset' + side, S, rows=6, cols=13, plate_w=0.04, plate_h=0.075, thick=0.004, u_range=(-0.3, 0.3), seed=9 + (1 if s > 0 else 0))
        reg(shell('cuisse' + side, t, [(-0.2, 0.108, 0.104), (-0.3, 0.098, 0.094), (-0.4, 0.086, 0.083)], n=18, a0=-150, a1=150, power=2.2, thick=0.009, sub=1), t, 'stone', chip=0.004)
        # poleyn: a domed knee with a side fan
        kn = 'knee' + side if rig.has('knee' + side) else 'shin' + side
        reg(ball('poleyn' + side, kn, [0.05, 0.0, 0.0], (0.07, 0.085, 0.082), segs=(14, 9)), kn, 'bronze', chip=0.004)
        reg(ball('kboss' + side, kn, [0.115, 0.0, 0.0], (0.02, 0.026, 0.026), segs=(8, 5)), kn, 'gold', glow=0.35)
        reg(ball('kfan' + side, kn, [0.0, 0.0, 0.085 * s], (0.06, 0.07, 0.016), segs=(12, 6)), kn, 'bronze', chip=0.002)
        # greave with a front ridge, ankle ring
        sh = 'shin' + side
        ridge = lambda th: 0.09 * np.exp(-(th / 0.22) ** 2)
        reg(shell('greave' + side, sh, [(-0.04, 0.098, 0.096), (-0.13, 0.1, 0.098), (-0.25, 0.086, 0.084), (-0.36, 0.07, 0.068), (-0.4, 0.074, 0.072)], n=24, power=2.2, thick=0.009, sub=1, bump=ridge), sh, 'bronze', chip=0.005)
        reg(shell('calf' + side, sh, [(-0.07, 0.104, 0.102), (-0.2, 0.097, 0.095), (-0.33, 0.078, 0.076)], n=14, a0=100, a1=260, power=2.2, thick=0.008, sub=1), sh, 'iron', chip=0.003)
        for y in (-0.16, -0.27):
            rr = 0.1 - (-0.13 - y) * 0.13
            reg(shell(f'gmid{y}' + side, sh, [(y + 0.01, rr + 0.004, rr + 0.002), (y - 0.01, rr + 0.003, rr + 0.001)], n=22, power=2.2, thick=0.005, bev=0), sh, 'gold')
        for y in (-0.05, -0.385):
            reg(shell(f'gband{y}' + side, sh, [(y + 0.016, 0.104, 0.102) if y > -0.2 else (y + 0.016, 0.075, 0.073), (y, 0.108, 0.106) if y > -0.2 else (y, 0.08, 0.078), (y - 0.016, 0.103, 0.101) if y > -0.2 else (y - 0.016, 0.076, 0.074)], n=22, power=2.2, thick=0.006), sh, 'gold')
        # boot with an upturned toe
        ft = 'foot' + side
        prof = [(-0.085, 0.045, 0.05, -0.035), (-0.03, 0.062, 0.06, -0.03), (0.06, 0.06, 0.066, -0.045), (0.14, 0.05, 0.062, -0.058), (0.2, 0.034, 0.048, -0.05), (0.238, 0.018, 0.026, -0.03), (0.252, 0.006, 0.008, -0.008)]
        rings = []
        for (x, ry, rz, cy) in prof:
            th = np.linspace(0, TAU, 14, endpoint=False)
            yy = cy + ry * np.sin(th); yy = np.maximum(yy, -0.084)
            rings.append(B(ft, np.stack([np.full_like(th, x), yy, rz * np.cos(th)], 1)))
        boot = ed.loft('boot' + side, np.array(rings), close=True, caps=(True, True))
        ed.recalc_normals(boot); ed.subdivide(boot, 1); ed.shade(boot, angle=50)
        reg(boot, ft, 'iron', chip=0.002)
        reg(shell('bootcuff' + side, sh, [(-0.385, 0.082, 0.08), (-0.43, 0.09, 0.088), (-0.44, 0.084, 0.082)], n=18, power=2.2, thick=0.007), sh, 'bronze')
    both(leg)


# =====================================================================================================================
# THE GREAT SABER (weapon frame: +X along the blade, the edge toward -Y, the flat faces +-Z)
# =====================================================================================================================
def saber():
    w = 'weaponR'
    L0, L1 = 0.16, 1.74
    n = 40
    rings = []
    for i in range(n):
        t = i / (n - 1)
        x = L0 + (L1 - L0) * t
        belly = 0.052 + 0.058 * np.sin(math.pi * np.minimum(1.0, t * 1.12)) ** 0.9 * (0.35 + 0.65 * t)       # edge side grows toward the belly
        back = 0.03 + 0.012 * t
        if t > 0.86:                                                                                     # clipped point
            k = (t - 0.86) / 0.14
            back = back * (1 - k) - 0.04 * k
            belly = belly * (1 - k * k) + 0.045 * k
        curve = 0.05 * t * t
        ys = np.array([back, back * 0.55, 0.0, -belly * 0.6, -belly, -belly * 0.6, 0.0, back * 0.55]) + curve
        thk = 0.013 * (1 - 0.55 * t) + 0.002
        zs = np.array([0.0, 1.0, 1.0, 0.55, 0.0, -0.55, -1.0, -1.0]) * thk
        zs[0] = 0.0
        ys[0] = back + curve
        rings.append(B(w, np.stack([np.full(8, x), ys, zs], 1)))
    blade = ed.loft('blade', np.array(rings), close=True, caps=(True, True))
    ed.recalc_normals(blade); ed.shade(blade, angle=30)
    edge = lambda Pl: np.clip((-(Pl[:, 1] - 0.05 * ((Pl[:, 0] - L0) / (L1 - L0)) ** 2) - 0.045) / 0.05, 0, 1) ** 1.5 * 0.55
    reg(blade, w, 'steel', glow=edge)
    # fuller rail along the spine, collar, lotus guard, wrapped grip, ring pommel with a tassel
    reg(sweep('fuller', w, np.array([[L0 + 0.02 + 1.2 * t, 0.012 + 0.05 * (((0.02 + 1.2 * t)) / (L1 - L0)) ** 2, 0.0] for t in np.linspace(0, 1, 16)]), radius=lambda t: 0.012 * (1 - 0.6 * t), section=6, scale_y=1.6), w, 'hilt', glow=0.2)
    ax = rig.vec(w, [1, 0, 0])
    reg(ed.lathe('collar', [[0.03, 0.0], [0.044, 0.01], [0.046, 0.05], [0.036, 0.075]], segs=12, origin=B(w, [0.115, 0.005, 0])[0], axis=ax), w, 'hilt')
    petals = lambda th: 0.12 * np.abs(np.cos(th * 4.0)) ** 0.6
    grings = []
    for (x, r) in [(0.098, 0.03), (0.104, 0.1), (0.118, 0.108), (0.13, 0.1), (0.136, 0.03)]:
        th = np.linspace(0, TAU, 32, endpoint=False)
        rr = r * (1 + (petals(th) if r > 0.05 else 0))
        grings.append(B(w, np.stack([np.full_like(th, x), rr * np.cos(th), rr * np.sin(th) * 0.62], 1)))
    guard = ed.loft('guard', np.array(grings), close=True, caps=(True, True))
    ed.recalc_normals(guard); ed.shade(guard, angle=40)
    reg(guard, w, 'hilt', chip=0.002)
    a, b_ = B(w, [0.095, 0, 0])[0], B(w, [-0.27, 0, 0])[0]
    reg(ed.helix_wrap('grip', a, b_, radius=0.024, turns=11, width=0.04, thick=0.003, sides=12), w, 'wrap')
    reg(ed.lathe('pcap', [[0.03, 0.0], [0.036, 0.012], [0.028, 0.03], [0.014, 0.04]], segs=10, origin=B(w, [-0.27, 0, 0])[0], axis=-ax), w, 'hilt')
    rp = np.array([[-0.345 + math.cos(t) * 0.04, math.sin(t) * 0.04, 0.0] for t in np.linspace(0, TAU, 21)])
    reg(sweep('pring', w, rp, radius=0.011, section=6), w, 'hilt')
    reg(ed.tassel('ptassel', B(w, [-0.385, 0.0, 0.0])[0], direction=rig.vec(w, [-0.5, -1.0, 0.0]), length=0.26, radius=0.022, strands=12), w, 'wrap')


head(); torso(); arms(); legs(); saber()
K.finish(os.path.join(ed.ROOT, 'src/rpg/boss/idol.edb'), budget=BUDGET, hero='idol', preview='--preview' in ARGS)
