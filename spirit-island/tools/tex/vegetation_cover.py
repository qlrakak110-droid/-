"""ground-cover atlas (1024²): lawn strip, tall wild grass, tussock, fern frond, reeds, clover / plantain / moss /
leaf-litter patches and four flowering plants.  -> assets/tex/vegetation/cover_{albedo,alpha,normal}.jpg (+_512)
Layout: vegetation_layout.COVER.  Every blade is a tapered curved stroke with a base-to-tip colour ramp (dark, AO'd
base -> lit, yellower tip), so a card of them reads as a real clump instead of flat paint.
"""
import math, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
import vegetation_common as V
from vegetation_layout import COVER

cv = V.Canvas(1024, 1024, ss=2, noise_seed=23)
C = V.hexc
R = np.random.default_rng(7)


def bez(p0, p1, p2, n):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0], (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]) for t in np.linspace(0, 1, n)]


def blade(reg, bx, by, h, lean, w, c0, c1, bend=0.35, seg=7, z=0.3, shadow=0.12, tipw=0.4):
    """curved tapered grass blade from (bx, by) up to height h, leaning sideways by `lean` px"""
    tip = (bx + lean, by - h)
    ctrl = (bx + lean * bend * 0.2, by - h * (0.55 + 0.2 * bend))
    pts = bez((bx, by), ctrl, tip, seg + 1)
    for i in range(seg):
        t0, t1 = i / seg, (i + 1) / seg
        col = c0 * (1 - t1) + c1 * t1
        cv.stem([pts[i], pts[i + 1]], w * (1 - 0.9 * t0 ** 1.15) + 0.4, w * (1 - 0.9 * t1 ** 1.15) + 0.4, col,
                z=z + 0.4 * t1, shadow=shadow, dark=0.85, clip_rect=reg)
    return pts


GREENS = [C('#3f6b23'), C('#4c7a27'), C('#5a862c'), C('#36601f'), C('#6b9131'), C('#4a7330')]
TIPS = [C('#8fae4a'), C('#9cb752'), C('#a9bd5a'), C('#7fa442'), C('#b5bd68')]
STRAW = [C('#b9a868'), C('#c8b77a'), C('#a89558')]


def pick(lst): return lst[int(R.integers(len(lst)))]


# ---------------------------------------------------------------- lawn strip: dense short blades
def lawn(reg):
    """a wide grass clump: blade bases bunched in the middle, blades fanning outward, ragged top (few tall blades),
    so crossed cards read as a round tuft from every side instead of a strip"""
    x0, y0, x1, y1 = reg; H = y1 - y0; cx = (x0 + x1) / 2; Wd = x1 - x0
    for layer in range(3):
        n = [70, 90, 80][layer]
        dark = [0.62, 0.82, 1.0][layer]
        for i in range(n):
            off = R.normal(0, 0.16) * Wd
            bx = min(max(cx + off, x0 + 30), x1 - 30)
            h = H * (0.22 + 0.74 * R.random() ** 1.7) * (1 - 0.45 * min(1, abs(off) / (Wd * 0.4)))
            lean = (off / (Wd * 0.5)) * h * 0.9 + R.normal(0, 0.18) * h
            lean = max(min(lean, (x1 - 10) - bx), (x0 + 10) - bx)
            w = R.uniform(4.5, 8)
            c0 = pick(GREENS) * 0.55 * dark; c1 = (pick(TIPS) if R.random() > 0.1 else pick(STRAW)) * dark * R.uniform(0.85, 1.05)
            blade(reg, bx, y1 - 2, h, lean, w, c0, c1, bend=R.uniform(0.3, 0.9), seg=6, z=0.2 + 0.2 * layer)


# ---------------------------------------------------------------- tall wild grass with seed heads
def wild(reg, tuss=False):
    x0, y0, x1, y1 = reg; H = y1 - y0; cx = (x0 + x1) / 2; Wd = x1 - x0
    nb = 70 if not tuss else 55
    for layer in range(2):
        for i in range(nb):
            bx = cx + R.normal(0, Wd * (0.09 if not tuss else 0.12)); bx = min(max(bx, x0 + 20), x1 - 20)
            h = R.uniform(0.45, 0.95) * H * (0.95 if not tuss else 0.8)
            spread = (bx - cx) / (Wd * 0.5)
            lean = (spread * 0.9 + R.normal(0, 0.35)) * h * (0.35 if not tuss else 0.75)
            lean = max(min(lean, (x1 - 10) - bx), (x0 + 10) - bx)
            w = R.uniform(5, 9) if not tuss else R.uniform(7, 12)
            dark = 0.65 if layer == 0 else 1.0
            c0 = pick(GREENS) * 0.4 * dark
            c1 = (pick(STRAW) if (tuss and R.random() < 0.45) or R.random() < 0.15 else pick(TIPS)) * dark
            blade(reg, bx, y1 - 2, h, lean, w, c0, c1, bend=R.uniform(0.5, 1.0) if tuss else R.uniform(0.1, 0.5), seg=9, z=0.2 + 0.3 * layer)
    if tuss: return
    # seed heads: slender stems with drooping panicles of spikelets
    for k in range(9):
        bx = cx + R.normal(0, Wd * 0.07); h = R.uniform(0.75, 0.97) * H; lean = R.normal(0, 0.12) * h
        lean = max(min(lean, (x1 - 30) - bx), (x0 + 30) - bx)
        pts = bez((bx, y1 - 2), (bx + lean * 0.2, y1 - h * 0.6), (bx + lean, y1 - h), 12)
        cv.stem(pts, 3.2, 1.6, C('#7f8f47') * R.uniform(0.85, 1.1), z=0.6, shadow=0.1, clip_rect=reg)
        tx, ty = pts[-1]
        for j in range(16):
            t = j / 16; px, py = pts[-1 - int(t * 4)] if t < 0.9 else pts[-1]
            px = tx + (px - tx) * 0.5; py = ty + t * h * 0.16
            for sd in (-1, 1):
                a = -math.pi / 2 + sd * R.uniform(0.35, 0.9) + R.normal(0, 0.1)
                L = R.uniform(10, 18)
                cv.leaf(px, py, a, L, 5, pick(STRAW) * R.uniform(0.85, 1.1), shape='elliptic', veins=0, z=0.75, shadow=0.15, blotch=0.05, clip_rect=reg)


# ---------------------------------------------------------------- fern frond
def fern(reg):
    """lady-fern frond: spaced pinnae angled toward the tip, each cut into distinct pinnules; lanceolate outline"""
    x0, y0, x1, y1 = reg; H = y1 - y0; cx = (x0 + x1) / 2; Wd = x1 - x0
    rach = bez((cx, y1 - 2), (cx + 8, y0 + H * 0.5), (cx - 6, y0 + 8), 60)
    col0, col1 = C('#3a6824'), C('#7aa640')
    npin = 19
    for i in range(npin):
        t = 0.16 + 0.82 * i / npin
        px, py = rach[int(t * 59)]
        env = math.sin(math.pi * min(1, (t - 0.08) / 0.95)) ** 0.9 * (1 - 0.25 * t)
        L = (0.08 + 0.4 * env) * Wd
        for sd in (-1, 1):
            off = 0.5 * (sd > 0)                                        # alternate attachment
            qx0, qy0 = rach[min(59, int((t + off * 0.02) * 59))]
            a = (-math.pi / 2) + sd * (1.0 - 0.3 * t) + R.normal(0, 0.05)
            col = (col0 * (1 - t) + col1 * t) * R.uniform(0.88, 1.08)
            ex, ey = qx0 + math.cos(a) * L, qy0 + math.sin(a) * L - L * 0.12
            nl = max(2, int(L / 9))
            for j in range(nl):
                u = (j + 0.6) / (nl + 0.4); qx, qy = qx0 + (ex - qx0) * u, qy0 + (ey - qy0) * u
                ll = (1 - u * 0.7) * min(L * 0.22, 15) + 2.5
                for s2 in (-1, 1):
                    cv.leaf(qx, qy, a + s2 * 1.05 - 0.35 * s2, ll, ll * 0.55, col * (0.92 + 0.08 * s2), shape='ovate', serr=0.2, teeth=4, veins=0,
                            z=0.4 + 0.1 * u, shadow=0.22, blotch=0.08, edge_col=col * 0.8, clip_rect=reg)
            cv.leaf(ex, ey, a - 0.2 * sd, 7, 3.5, col, shape='lance', veins=0, z=0.5, shadow=0.1, clip_rect=reg)
            cv.stem([(qx0, qy0), (ex, ey)], 2.0, 0.8, col * 0.7, z=0.55, shadow=0.0, clip_rect=reg)
    cv.stem(rach, 5, 1.2, C('#55602c'), z=0.6, shadow=0.15, clip_rect=reg)


# ---------------------------------------------------------------- reeds / sedge with cattails
def reed(reg):
    x0, y0, x1, y1 = reg; H = y1 - y0; cx = (x0 + x1) / 2; Wd = x1 - x0
    for i in range(46):
        bx = cx + R.normal(0, Wd * 0.12); bx = min(max(bx, x0 + 14), x1 - 14)
        h = R.uniform(0.5, 0.97) * H; lean = R.normal(0, 0.2) * h * 0.4; lean = max(min(lean, (x1 - 8) - bx), (x0 + 8) - bx)
        c0 = C('#2f4f22') * 0.6; c1 = (C('#8d9a4c') if R.random() < 0.7 else C('#b0a060')) * R.uniform(0.85, 1.05)
        blade(reg, bx, y1 - 2, h, lean, R.uniform(6, 10), c0, c1, bend=R.uniform(0.6, 1.0), seg=10, z=0.3)
    for k in range(3):
        bx = cx + R.normal(0, Wd * 0.08); h = R.uniform(0.72, 0.92) * H
        pts = bez((bx, y1 - 2), (bx + R.normal(0, 6), y1 - h * 0.5), (bx + R.normal(0, 10), y1 - h), 10)
        cv.stem(pts, 4, 2.5, C('#6b7a3c'), z=0.6, shadow=0.1, clip_rect=reg)
        tx, ty = pts[-1]
        cv.stem([(tx, ty + 18), (tx, ty + 70)], 13, 12, C('#5a3a22'), z=0.8, shadow=0.2, dark=0.6, clip_rect=reg)   # cattail spike
        cv.stem([(tx, ty - 2), (tx, ty + 18)], 2, 1.5, C('#8a7a50'), z=0.8, shadow=0.0, clip_rect=reg)


# ---------------------------------------------------------------- top-down patches
def patch_mask(reg, seed, edge=0.25):
    """soft irregular disc mask (bbox-sized array, output px) to cull elements outside the patch"""
    x0, y0, x1, y1 = reg; cx, cy = (x0 + x1) / 2, (y0 + y1) / 2; rad = (x1 - x0) / 2 - 10
    def inside(x, y):
        a = math.atan2(y - cy, x - cx); d = math.hypot(x - cx, y - cy) / rad
        wob = 0.78 + 0.12 * math.sin(a * 3 + seed) + 0.08 * math.sin(a * 5 + seed * 2.1)
        return d < wob - edge * R.random()
    return inside


def clover(reg):
    x0, y0, x1, y1 = reg; ins = patch_mask(reg, 1.3)
    cols = [C('#3e6e28'), C('#4a7a2c'), C('#5a8a34'), C('#355f24')]
    leaves = []
    for i in range(420):
        x, y = R.uniform(x0, x1), R.uniform(y0, y1)
        if ins(x, y): leaves.append((x, y))
    for (x, y) in leaves:
        rot = R.random() * 2 * math.pi; s = R.uniform(7, 12); col = pick(cols) * R.uniform(0.8, 1.1)
        for k in range(3):
            a = rot + k * 2 * math.pi / 3
            cv.leaf(x, y, a, s, s * 1.05, col, shape='petal', veins=0, mid_col=col * 1.25, z=0.4 + 0.2 * R.random(), shadow=0.35, blotch=0.12, tip_light=0.0, clip_rect=reg)
            # pale chevron mark
            cv.disc(x + math.cos(a) * s * 0.45, y + math.sin(a) * s * 0.45, s * 0.12, col * 1.45, z=0.62, shadow=0.0, dome=0.05, rim_dark=0.0)
    for i in range(7):
        x, y = R.uniform(x0 + 30, x1 - 30), R.uniform(y0 + 30, y1 - 30)
        if not ins(x, y): continue
        cv.disc(x, y, 9, C('#d9d2c4'), z=0.85, shadow=0.35, dome=0.5, rim_dark=0.35)
        for k in range(40):                                          # globe of tiny florets, pink-tinged at the base
            a = R.random() * 2 * math.pi; d = R.random() ** 0.6 * 8
            cv.disc(x + math.cos(a) * d, y + math.sin(a) * d, 1.6, C('#f4f1ea') * R.uniform(0.85, 1.0) if d < 6 else C('#e2c8c8'), z=0.95 + 0.05 * (1 - d / 8), shadow=0.1, dome=0.2, rim_dark=0.3)


def rosette(reg):
    x0, y0, x1, y1 = reg; cx, cy = (x0 + x1) / 2, (y0 + y1) / 2; Wd = x1 - x0
    for ring in range(2):
        n = 7 if ring == 0 else 5
        for i in range(n):
            a = i / n * 2 * math.pi + ring * 0.4 + R.normal(0, 0.1)
            L = Wd * (0.42 if ring == 0 else 0.3) * R.uniform(0.85, 1.05)
            col = (C('#3d6a2a') if ring == 0 else C('#5a8a38')) * R.uniform(0.85, 1.1)
            cv.leaf(cx, cy, a, L, L * 0.5, col, shape='elliptic', veins=5, vein_amt=0.14, mid_col=col * 1.35, edge_col=col * 0.8, petiole=8, pet_col=col * 1.3,
                    z=0.3 + 0.25 * ring, shadow=0.35, blotch=0.14, curl=0.1, clip_rect=reg)
    for k in range(2):    # seed spikes lying outward
        a = R.random() * 2 * math.pi
        cv.stem([(cx, cy), (cx + math.cos(a) * Wd * 0.45, cy + math.sin(a) * Wd * 0.45)], 2.4, 1.6, C('#6f7a40'), z=0.8, shadow=0.25, clip_rect=reg)


def moss(reg):
    x0, y0, x1, y1 = reg; ins = patch_mask(reg, 2.2, edge=0.12)
    cols = [C('#4f6e1e'), C('#5f7f24'), C('#6f8e2a'), C('#3f5c1a'), C('#7f9a36'), C('#8aa23e')]
    for i in range(260):                                             # cushions: a dark base of overlapping mounds
        x, y = R.uniform(x0, x1), R.uniform(y0, y1)
        if ins(x, y): cv.disc(x, y, R.uniform(8, 16), C('#3a5418') * R.uniform(0.8, 1.1), z=0.2, shadow=0.15, dome=0.5, rim_dark=0.5)
    for i in range(9000):                                            # fine shoots on top
        x, y = R.uniform(x0, x1), R.uniform(y0, y1)
        if not ins(x, y): continue
        cv.disc(x, y, R.uniform(1.0, 2.4), pick(cols) * R.uniform(0.85, 1.15), z=0.45 + 0.3 * R.random(), shadow=0.15, dome=0.3, rim_dark=0.35)
    for i in range(60):    # sporophytes: tiny reddish capsules
        x, y = R.uniform(x0 + 20, x1 - 20), R.uniform(y0 + 20, y1 - 20)
        if ins(x, y): cv.disc(x, y, 1.6, C('#9a6a2a'), z=0.95, shadow=0.2, dome=0.2)


def leafbed(reg):
    x0, y0, x1, y1 = reg; ins = patch_mask(reg, 3.1, edge=0.3)
    cols = [C('#7a4a22'), C('#8f5a28'), C('#a46a2c'), C('#6a4024'), C('#b08040'), C('#5e4a2e'), C('#8a7a3a'), C('#6e5a3e'), C('#c09a50'), C('#4e3e2a')]
    for i in range(380):
        x, y = R.uniform(x0, x1), R.uniform(y0, y1)
        if not ins(x, y): continue
        col = pick(cols) * R.uniform(0.75, 1.05); L = R.uniform(18, 34)
        cv.leaf(x, y, R.random() * 2 * math.pi, L, L * R.uniform(0.45, 0.6), col, shape=['ovate', 'elliptic', 'deltoid'][int(R.integers(3))],
                serr=R.uniform(0, 0.25), veins=6, vein_amt=0.1, mid_col=col * 1.2, edge_col=col * 0.7, curl=R.normal(0, 0.3), petiole=4, pet_col=col * 0.8,
                z=0.2 + 0.5 * R.random(), shadow=0.4, blotch=0.25, clip_rect=reg)
    for i in range(30):   # twigs
        x, y = R.uniform(x0 + 20, x1 - 20), R.uniform(y0 + 20, y1 - 20)
        if not ins(x, y): continue
        a = R.random() * math.pi; L = R.uniform(15, 40)
        cv.stem([(x, y), (x + math.cos(a) * L, y + math.sin(a) * L)], 3, 2, C('#4a3524'), z=0.8, shadow=0.35, clip_rect=reg)


# ---------------------------------------------------------------- flowering plants (side cards)
def plant(reg, kind):
    x0, y0, x1, y1 = reg; H = y1 - y0; cx = (x0 + x1) / 2; Wd = x1 - x0
    # basal leaves
    for i in range(7):
        a = -math.pi / 2 + R.normal(0, 0.7); L = R.uniform(0.15, 0.3) * H
        col = pick(GREENS) * R.uniform(0.8, 1.0)
        bx = cx + R.normal(0, 4)
        if kind == 'daisy': cv.leaf(bx, y1 - 3, a, L, L * 0.3, col, shape='lance', serr=0.25, teeth=7, veins=0, z=0.2, shadow=0.2, clip_rect=reg)
        else: cv.leaf(bx, y1 - 3, a, L * 0.8, L * 0.4, col, shape='elliptic', veins=4, z=0.2, shadow=0.2, clip_rect=reg)
    nst = {'daisy': 3, 'butter': 4, 'bell': 2, 'pink': 3}[kind]
    for k in range(nst):
        h = R.uniform(0.62, 0.9) * H; lean = R.normal(0, 0.2) * Wd * 0.6
        lean = max(min(lean, Wd * 0.3), -Wd * 0.3)
        pts = bez((cx + R.normal(0, 3), y1 - 3), (cx + lean * 0.2, y1 - h * 0.55), (cx + lean, y1 - h), 10)
        cv.stem(pts, 3.0, 2.0, C('#4f7a2c') * R.uniform(0.85, 1.1), z=0.45, shadow=0.12, clip_rect=reg)
        for j in (3, 5):   # stem leaves
            px, py = pts[j]; sd = 1 if (j + k) % 2 else -1
            cv.leaf(px, py, -math.pi / 2 + sd * 0.9, H * 0.08, H * 0.03, pick(GREENS), shape='lance', veins=0, z=0.5, shadow=0.15, clip_rect=reg)
        fx, fy = pts[-1]
        if kind == 'daisy':
            r = R.uniform(13, 17); rot = R.random()
            for p in range(16):
                a = rot + p * 2 * math.pi / 16
                cv.leaf(fx, fy, a, r, r * 0.3, C('#f6f4ee') * R.uniform(0.9, 1.0), shape='elliptic', veins=0, mid_col=C('#e8e6e0'), z=0.8, shadow=0.15, blotch=0.03, tip_light=0.0, clip_rect=reg)
            cv.disc(fx, fy, r * 0.32, C('#e8b820'), z=0.95, shadow=0.1, dome=0.3)
        elif kind == 'butter':
            for f in range(2):
                ox, oy = (R.normal(0, 8), R.normal(0, 6)) if f else (0, 0)
                r = R.uniform(8, 11); rot = R.random() * 6
                if f: cv.stem([(fx, fy), (fx + ox, fy + oy)], 1.6, 1.4, C('#4f7a2c'), z=0.5, shadow=0.0, clip_rect=reg)
                for p in range(5):
                    a = rot + p * 2 * math.pi / 5
                    cv.leaf(fx + ox, fy + oy, a, r, r * 0.95, C('#f5c518') * R.uniform(0.92, 1.05), shape='elliptic', veins=0, gloss=0.12, z=0.85, shadow=0.15, blotch=0.04, clip_rect=reg)
                cv.disc(fx + ox, fy + oy, r * 0.3, C('#c89a10'), z=0.95, shadow=0.0, dome=0.2)
        elif kind == 'bell':
            for b in range(4):   # bells hanging along the top of the stem
                t = 1 - b * 0.12; px, py = pts[int(t * 9)]
                sd = 1 if b % 2 else -1; hx, hy = px + sd * 9, py + 6
                cv.stem([(px, py), (hx, hy)], 1.5, 1.2, C('#4f7a2c'), z=0.6, shadow=0.0, clip_rect=reg)
                col = C('#7a6ad8') * R.uniform(0.85, 1.05)
                for p in (-1, 0, 1):
                    cv.leaf(hx, hy, math.pi / 2 + p * 0.32, 17, 9, col * (1 - 0.12 * abs(p)), shape='elliptic', veins=3, vein_amt=0.1, z=0.85 + 0.02 * (p == 0), shadow=0.2, blotch=0.06, edge_col=col * 1.2, clip_rect=reg)
        else:  # pink campion: 5 notched petals
            r = R.uniform(10, 13); rot = R.random() * 6
            for p in range(5):
                a = rot + p * 2 * math.pi / 5
                cv.leaf(fx, fy, a, r, r * 0.9, C('#e870a8') * R.uniform(0.9, 1.05), shape='petal', veins=3, vein_amt=0.06, z=0.85, shadow=0.15, blotch=0.05, clip_rect=reg)
            cv.disc(fx, fy, r * 0.22, C('#f0d0e0'), z=0.95, shadow=0.0, dome=0.2)


lawn(COVER['lawn'])
wild(COVER['wild'])
wild(COVER['tuss'], tuss=True)
fern(COVER['fern'])
reed(COVER['reed'])
clover(COVER['clover'])
rosette(COVER['rosette'])
moss(COVER['moss'])
leafbed(COVER['leafbed'])
for k in ('daisy', 'butter', 'bell', 'pink'): plant(COVER[k], k)

rgb, a, h, tr = cv.finish()
files = V.save_atlas('cover', rgb, a, h, normal_strength=4.0)
print('\n'.join(files))
print(V.preview_atlas('cover'))
