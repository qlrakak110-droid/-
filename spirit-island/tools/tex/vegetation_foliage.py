"""foliage atlas (1024²): deciduous twig cluster, birch twigs, fir needle spray, cherry blossom twig.
-> assets/tex/vegetation/foliage_{albedo,alpha,normal}.jpg (+_512).  Layout: vegetation_layout.FOLIAGE
Each region is one 'cluster card': the twig base sits at the bottom centre of the region; leaves never cross the
region border (no straight cuts), and every leaf carries its own midrib, veins, serration, colour drift and a drop
shadow on what lies under it.
"""
import math, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
import vegetation_common as V
from vegetation_layout import FOLIAGE

cv = V.Canvas(1024, 1024, ss=2, noise_seed=11)
C = V.hexc


def inside(reg, pts, m=6):
    x0, y0, x1, y1 = reg
    return all(x0 + m < x < x1 - m and y0 + m < y < y1 - m for x, y in pts)


def leaf_fits(reg, bx, by, ang, L, Wd, m=6):
    dx, dy = math.cos(ang), math.sin(ang); hw = Wd * 0.5
    pts = [(bx + dx * L, by + dy * L), (bx + dx * L * 0.4 - dy * hw, by + dy * L * 0.4 + dx * hw), (bx + dx * L * 0.4 + dy * hw, by + dy * L * 0.4 - dx * hw)]
    return inside(reg, pts, m)


def bezier(p0, p1, p2, n=12):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0], (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]) for t in np.linspace(0, 1, n)]


def along(pts, t):
    """point + tangent angle at fraction t of a polyline"""
    L = [0.0]
    for i in range(1, len(pts)): L.append(L[-1] + math.dist(pts[i], pts[i - 1]))
    s = t * L[-1]
    for i in range(1, len(pts)):
        if L[i] >= s:
            f = (s - L[i - 1]) / max(L[i] - L[i - 1], 1e-6)
            x = pts[i - 1][0] + (pts[i][0] - pts[i - 1][0]) * f; y = pts[i - 1][1] + (pts[i][1] - pts[i - 1][1]) * f
            return x, y, math.atan2(pts[i][1] - pts[i - 1][1], pts[i][0] - pts[i - 1][0])
    return pts[-1][0], pts[-1][1], math.atan2(pts[-1][1] - pts[-2][1], pts[-1][0] - pts[-2][0])


def twig_cluster(reg, seed, *, leaf_cols, L=(70, 110), W=0.5, shape='ovate', serr=0.25, teeth=16, n_side=5, per=3,
                 twig_col=C('#4a3a2c'), droop=0.0, spread=1.0, petiole=10, veins=7, vein_amt=0.09, edge='#8a8f3a',
                 mid=None, back_dark=0.72, gloss=0.03, twig_w=(7, 2.5), leaf_jit=0.5, tip_cluster=4, blotch=0.14):
    r = V.rng(seed)
    x0, y0, x1, y1 = reg; cx = (x0 + x1) / 2; h = y1 - y0; w = x1 - x0
    base = (cx + r.normal(0, 4), y1 - 4)
    main = bezier(base, (cx + r.normal(0, w * 0.08), y0 + h * 0.45), (cx + r.normal(0, w * 0.1), y0 + h * (0.08 + droop * 0.3)), 16)
    sides = []
    for k in range(n_side):
        t = 0.22 + 0.68 * k / max(1, n_side - 1) + r.normal(0, 0.03)
        px, py, a = along(main, min(0.97, t))
        sd = 1 if k % 2 == 0 else -1
        ang = a + sd * (0.75 + r.random() * 0.35) * spread
        ln = (0.42 - 0.22 * t) * h * (0.85 + r.random() * 0.3)
        ex, ey = px + math.cos(ang) * ln, py + math.sin(ang) * ln + droop * ln * 0.5
        mx, my = px + math.cos(ang) * ln * 0.5, py + math.sin(ang) * ln * 0.5 - (1 - droop) * ln * 0.08
        sides.append(bezier((px, py), (mx, my), (ex, ey), 8))
    twigs = [main] + sides
    # leaf placements along every twig (alternate, pointing forward/outward), a rosette at each tip
    leaves = []
    for ti, tw in enumerate(twigs):
        nn = per * (3 if ti == 0 else 2)
        for j in range(nn):
            t = 0.25 + 0.75 * (j + 0.5) / nn if ti else 0.35 + 0.6 * (j + 0.5) / nn
            px, py, a = along(tw, min(0.98, t))
            sd = 1 if j % 2 == 0 else -1
            ang = a + sd * (0.65 + r.random() * 0.5)
            leaves.append((px, py, ang))
        px, py, a = along(tw, 1.0)
        for j in range(tip_cluster if ti else tip_cluster + 1):
            leaves.append((px, py, a + (j - (tip_cluster - 1) / 2) * 0.45 + r.normal(0, 0.12)))
    r.shuffle(leaves)
    placed = []
    for (px, py, ang) in leaves:
        for attempt in range(6):
            Ll = r.uniform(*L) * (1 - 0.12 * attempt); Wl = Ll * W * (0.85 + r.random() * 0.3)
            a2 = ang + r.normal(0, 0.15 + 0.1 * attempt)
            if leaf_fits(reg, px + math.cos(a2) * petiole, py + math.sin(a2) * petiole, a2, Ll, Wl): placed.append((px, py, a2, Ll, Wl)); break
    nb = len(placed) // 2
    def paint_leaf(p, dark):
        px, py, a2, Ll, Wl = p
        col = leaf_cols[int(r.integers(len(leaf_cols)))] * (dark * (0.9 + r.random() * 0.2))
        cv.leaf(px, py, a2, Ll, Wl, col, shape=shape, serr=serr, teeth=teeth, petiole=petiole, pet_col=twig_col * 1.4 if petiole else None,
                veins=veins, vein_amt=vein_amt, edge_col=C(edge) * dark if edge else None, mid_col=(C(mid) * dark) if mid else None,
                curl=r.normal(0, 0.15), gloss=gloss, blotch=blotch, z=0.2 + 0.6 * r.random(), clip_rect=reg)
    for p in placed[:nb]: paint_leaf(p, back_dark)                 # back layer (in the twig's shade)
    for tw in twigs: cv.stem(tw, twig_w[0] if tw is main else twig_w[0] * 0.6, twig_w[1], twig_col, clip_rect=reg)
    for p in placed[nb:]: paint_leaf(p, 1.0)
    return twigs


# ---------------------------------------------------------------- broadleaf (beech / linden-like)
greens = [C('#3f6a24'), C('#4b7829'), C('#557f2e'), C('#365f20'), C('#62873a'), C('#2f5320'), C('#6a8a34')]
twig_cluster(FOLIAGE['broad'], 1, leaf_cols=greens, L=(78, 118), W=0.56, shape='ovate', serr=0.22, teeth=18, n_side=5, per=3,
             twig_col=C('#4b3b2d'), petiole=9, veins=8, edge='#7f8a37', mid='#86a052', tip_cluster=3)

# ---------------------------------------------------------------- birch: small deltoid serrated leaves on thin drooping twigs
bgreens = [C('#5d8a2b'), C('#6c9631'), C('#79a038'), C('#4f7c27'), C('#86a73f'), C('#557f2b')]
twig_cluster(FOLIAGE['birch'], 2, leaf_cols=bgreens, L=(46, 66), W=0.68, shape='deltoid', serr=0.3, teeth=11, n_side=7, per=4,
             twig_col=C('#5a4436'), droop=0.55, spread=1.15, petiole=8, veins=6, vein_amt=0.07, edge='#9aa646', mid='#9cbc5c',
             twig_w=(4.5, 1.6), tip_cluster=3, gloss=0.05)

# ---------------------------------------------------------------- fir / spruce needle spray (flat, dense, ovate outline)
def needle_spray(reg, seed):
    r = V.rng(seed)
    x0, y0, x1, y1 = reg; cx = (x0 + x1) / 2; h = y1 - y0; w = x1 - x0
    main = bezier((cx, y1 - 4), (cx + r.normal(0, 8), y0 + h * 0.5), (cx + r.normal(0, 10), y0 + 18), 18)
    twigs = [(main, 1.0)]
    nside = 9
    for k in range(nside * 2):
        t = 0.12 + 0.8 * (k // 2) / nside + r.normal(0, 0.012)
        px, py, a = along(main, min(0.96, t))
        sd = 1 if k % 2 == 0 else -1
        env = math.sin(math.pi * min(1, (t - 0.05) / 0.95)) ** 0.8          # ovate outline of the spray
        ln = (0.06 + 0.4 * env) * w * (0.85 + r.random() * 0.25)
        ang = a + sd * (0.95 + r.normal(0, 0.08))
        ex, ey = px + math.cos(ang) * ln, py + math.sin(ang) * ln
        ex, ey = min(max(ex, x0 + 26), x1 - 26), min(max(ey, y0 + 26), y1 - 26)
        tw = bezier((px, py), ((px + ex) / 2 + r.normal(0, 3), (py + ey) / 2 - ln * 0.1), (ex, ey), 7)
        twigs.append((tw, 0.55))
        # third-order sprigs on longer twigs
        if ln > w * 0.22:
            for j in range(2):
                tt = 0.4 + 0.3 * j; qx, qy, qa = along(tw, tt)
                a3 = qa + (1 if j == 0 else -1) * 0.8; l3 = ln * 0.3
                twigs.append((bezier((qx, qy), (qx + math.cos(a3) * l3 * 0.5, qy + math.sin(a3) * l3 * 0.5), (qx + math.cos(a3) * l3, qy + math.sin(a3) * l3), 5), 0.35))
    ncols = [C('#1f3a26'), C('#26442b'), C('#2c4c2f'), C('#234028'), C('#33553a')]
    tipc = C('#5f7f3c')
    order = list(range(len(twigs)))
    for oi in order:
        tw, wt = twigs[oi]
        Ltw = sum(math.dist(tw[i], tw[i - 1]) for i in range(1, len(tw)))
        n = int(Ltw / 2.6)
        # back needles (darker), twig, front needles
        for layer in (0, 1):
            for j in range(n):
                t = (j + r.random() * 0.6) / max(n, 1)
                px, py, a = along(tw, t)
                for sd in (-1, 1):
                    if r.random() < 0.08: continue
                    ln = (13 + r.random() * 8) * (0.65 + 0.35 * min(1, (1 - t) * 4 + 0.4)) * (0.8 if wt < 0.5 else 1)
                    na = a + sd * (1.05 + r.normal(0, 0.18)) - 0.25 * sd * (layer)
                    ex, ey = px + math.cos(na) * ln, py + math.sin(na) * ln
                    if not inside(reg, [(ex, ey)], 4): continue
                    col = ncols[int(r.integers(len(ncols)))] * (0.72 if layer == 0 else 1.0)
                    if t > 0.82 and layer == 1: col = col * 0.5 + tipc * 0.5
                    cv.stem([(px, py), (ex, ey)], 2.6, 1.0, col * (1.1 + 0.15 * r.random()), z=0.3 + 0.3 * layer + 0.1 * r.random(), shadow=0.18, dark=0.8, clip_rect=reg)
            if layer == 0:
                cv.stem(tw, 6.5 * wt, 2.0 * wt + 0.6, C('#5a4532'), z=0.45, shadow=0.15, clip_rect=reg)

needle_spray(FOLIAGE['needle'], 3)

# ---------------------------------------------------------------- cherry blossom twig
def blossom(reg, seed):
    r = V.rng(seed)
    x0, y0, x1, y1 = reg
    twigs = twig_cluster(reg, seed, leaf_cols=[C('#6f7a33'), C('#7d6f36'), C('#86803e'), C('#64702f')], L=(44, 64), W=0.5, shape='ovate',
                         serr=0.3, teeth=14, n_side=5, per=1, twig_col=C('#4a2f2a'), petiole=6, veins=6, edge='#a07a3a', mid='#a9a060',
                         twig_w=(7, 2.5), tip_cluster=2, back_dark=0.75)
    petal_cols = [C('#f7d9e4'), C('#f3c7d8'), C('#fbe9ef'), C('#eebbd0'), C('#f9dfe8')]
    centres = []
    for tw in twigs:
        nfl = 13 if tw is twigs[0] else 9
        for j in range(nfl):
            px, py, a = along(tw, 0.3 + 0.7 * (j + r.random() * 0.5) / nfl)
            for k in range(2 + int(r.integers(3))):          # flowers hang in little clusters on short pedicels
                aa = r.random() * 2 * math.pi; dd = 8 + r.random() * 30
                fx, fy = px + math.cos(aa) * dd, py + math.sin(aa) * dd
                rad = 14 + r.random() * 8
                if inside(reg, [(fx - rad, fy - rad), (fx + rad, fy + rad)], 5): centres.append((px, py, fx, fy, rad))
    r.shuffle(centres)
    for (px, py, fx, fy, rad) in centres:
        cv.stem([(px, py), (fx, fy)], 1.8, 1.2, C('#6b4a3a'), z=0.5, shadow=0.1, clip_rect=reg)
        col = petal_cols[int(r.integers(len(petal_cols)))]
        rot = r.random() * 2 * math.pi
        for p in range(5):
            a = rot + p * 2 * math.pi / 5 + r.normal(0, 0.08)
            cv.leaf(fx, fy, a, rad * (0.9 + r.random() * 0.15), rad * 0.95, col * (0.92 + 0.12 * r.random()), shape='petal', veins=5, vein_amt=0.05,
                    mid_col=col * 0.96, edge_col=C('#fff4f7'), z=0.7 + 0.05 * p, shadow=0.22, blotch=0.06, tip_light=0.06, clip_rect=reg)
        cv.disc(fx, fy, rad * 0.24, C('#d47a98'), z=0.9, shadow=0.0, dome=0.15)
        for s in range(9):                                   # stamens
            a = r.random() * 2 * math.pi; d = rad * (0.25 + r.random() * 0.25)
            cv.disc(fx + math.cos(a) * d, fy + math.sin(a) * d, 1.6, C('#e8c25a'), z=1.0, shadow=0.0, dome=0.1)

blossom(FOLIAGE['blossom'], 4)

rgb, a, h, tr = cv.finish()
files = V.save_atlas('foliage', rgb, a, h, normal_strength=4.0)
print('\n'.join(files))
print(V.preview_atlas('foliage'))
