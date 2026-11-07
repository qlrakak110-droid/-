"""ground_grass — meadow turf seen from standing height (tile ~2.5 m).

Layers (bottom -> top, z-buffered): humus soil with grit, a mat of dead thatch, tufted live blades radiating from
clump centres (tapered, darker at the base, lighter mid-rib), clover patches. Density is broken up by two noise
scales so there are thin spots where thatch/soil shows, and dry/yellow drifts at macro scale.
"""
import numpy as np
import terrain_common as C
from terrain_common import T

SS = 2; N = 1024; n = N * SS
r = C.rng(7)

# ---------------- soil
soil_h = 0.10 * T.fbm(n, 6, 6, seed=1) + 0.04 * C.up(T.fbm(N, 32, 3, seed=2), n)
soil_c = T.ramp(T.fbm(n, 12, 5, seed=3), [(0, '#2c2118'), (0.5, '#3d2f22'), (1, '#54412e')])
soil_c *= (1 + 0.18 * C.grain(n, 4))[..., None]
zbuf = soil_h.astype(np.float32).copy()
col = soil_c.astype(np.float32).copy()
occ = np.full((n, n), 0.55, np.float32)
rough = np.full((n, n), 0.95, np.float32)

# density masks (tileable): macro thin spots + mid-scale tufts
macro = T.levels(C.up(T.fbm(256, 3, 4, seed=11), n), 0.25, 0.75)
mid = T.levels(C.up(T.fbm(512, 10, 3, seed=12), n), 0.2, 0.8)
dens = np.clip(0.35 + 0.65 * macro * (0.55 + 0.45 * mid), 0, 1)
dry = T.levels(C.up(T.fbm(256, 4, 3, seed=13), n), 0.55, 0.85)          # dry drifts (yellowing)


def sample_positions(count, mask, seed):
    rr = C.rng(seed)
    xs = []; ys = []
    while sum(len(a) for a in xs) < count:
        x = rr.random(count) * n; y = rr.random(count) * n
        keep = rr.random(count) < mask[y.astype(int) % n, x.astype(int) % n]
        xs.append(x[keep]); ys.append(y[keep])
    return np.concatenate(xs)[:count], np.concatenate(ys)[:count]


def draw(P, cols, zgain, occ_fn, rough_v):
    i = P['id']
    c = cols[i] * occ_fn(P)[:, None]
    C.splat_points(n, P['iy'], P['ix'], P['z'] * zgain, [c, occ_fn(P), np.full(len(i), rough_v, np.float32)], zbuf, [col, occ, rough])


# ---------------- thatch (dead blades lying flat)
thatch_cols = [(3, '#8b7b4b'), (2, '#9e8c5a'), (2, '#6f5f3b'), (1, '#b09f70'), (1, '#5c4c30')]
for ch in range(3):
    cnt = 26000
    x, y = sample_positions(cnt, 0.6 + 0.4 * (1 - dens), 100 + ch)
    P = C.strokes(n, cnt, C.rng(200 + ch), x=x, y=y, length=(18, 60), width=(1.6, 2.6), bend=0.25, z0=(0.13, 0.2), z1=(0.2, 0.32), taper=0.5)
    cols = C.palette(C.rng(300 + ch), cnt, thatch_cols, 0.08)
    draw(P, cols, 1.0, lambda P: (0.7 + 0.3 * P['t']) * (1 - 0.18 * np.abs(P['across'])), 0.82)

# ---------------- live blades: tufts radiating from clump centres + scattered singles
live_cols = [(3, '#4c772b'), (3, '#5a8632'), (2, '#68903a'), (2, '#3e6a29'), (1.2, '#7a973f'), (1, '#507c3d'), (0.6, '#8d9748')]
nclump = 2600
cx, cy = sample_positions(nclump, dens, 400)
for ch in range(6):
    cnt = 24000
    rr = C.rng(500 + ch)
    if ch < 4:      # tufted
        k = rr.integers(0, nclump, cnt)
        rad = np.abs(rr.normal(0, 9, cnt)); a0 = rr.random(cnt) * 2 * np.pi
        x = cx[k] + np.cos(a0) * rad; y = cy[k] + np.sin(a0) * rad
        ang = a0 + rr.normal(0, 0.55, cnt)
    else:           # scattered singles
        x, y = sample_positions(cnt, dens, 600 + ch); ang = None
    P = C.strokes(n, cnt, rr, x=x, y=y, ang=ang, length=(16, 58), width=(2.2, 3.6), bend=0.35, z0=(0.2, 0.32), z1=(0.55, 1.0), taper=0.8)
    cols = C.palette(C.rng(700 + ch), cnt, live_cols, 0.07)
    # dry drift: shift some blades toward straw at the macro dry areas
    dd = dry[y.astype(int) % n, x.astype(int) % n] * (rr.random(cnt) < 0.55)
    cols = cols * (1 - dd[:, None] * 0.55) + np.array([0.62, 0.58, 0.34], np.float32) * dd[:, None] * 0.55
    def shade(P):
        t = P['t']; a = np.abs(P['across'])
        return (0.42 + 0.58 * t ** 0.7) * (1.06 - 0.22 * a)            # dark base, lit tip, lighter mid-rib
    i = P['id']
    c = cols[i] * shade(P)[:, None]
    tip = (P['t'] > 0.82)[:, None] * 0.12                                # sun-bleached tips
    c = c * (1 - tip) + np.array([0.78, 0.76, 0.46], np.float32) * tip * shade(P)[:, None]
    C.splat_points(n, P['iy'], P['ix'], P['z'], [c, 0.45 + 0.55 * P['t'], np.full(len(i), 0.66, np.float32)], zbuf, [col, occ, rough])

# ---------------- clover / broadleaf weeds in patches
clover = T.levels(C.up(T.fbm(256, 6, 3, seed=31), n), 0.66, 0.8)
cnt = 2600
x, y = sample_positions(cnt, clover * 0.9 + 0.01, 800)
for leaf in range(3):
    a = leaf * 2.094 + C.rng(810).random(cnt) * 0.5
    P = C.blobs(n, cnt, C.rng(820 + leaf), x=x + np.cos(a) * 5.5, y=y + np.sin(a) * 5.5, rad=(4.5, 7.0), aspect=(1.0, 1.25), ang=a, z0=(0.5, 0.72), dome=0.1)
    cols = C.palette(C.rng(830), cnt, [(3, '#3b6326'), (2, '#4a7230'), (1, '#577a36')], 0.05)
    c = cols[P['id']] * (0.8 + 0.25 * (1 - P['rr']))[:, None]
    pale = ((P['rr'] > 0.35) & (P['rr'] < 0.55))[:, None] * 0.25        # the pale chevron on clover leaves
    c = c * (1 - pale) + np.array([0.62, 0.7, 0.5], np.float32) * pale
    C.splat_points(n, P['iy'], P['ix'], P['z'], [c, np.full(len(c), 0.85, np.float32), np.full(len(c), 0.6, np.float32)], zbuf, [col, occ, rough])

# ---------------- downsample, derive maps
h = C.down(zbuf, SS); albedo = C.down(col, SS); o = C.down(occ, SS); ro = C.down(rough, SS)
macro_d = C.down(macro, SS)
albedo *= (0.92 + 0.12 * macro_d)[..., None]
cav = T.ao_from_height(h, radius=3, strength=1.2)
ao = np.clip(o * 0.6 + 0.4, 0, 1) * cav
albedo *= (0.78 + 0.22 * ao)[..., None]
hs = T.blur(h, 1)
C.save_set('ground_grass', np.clip(albedo, 0, 1), hs, ro, ao, normal_strength=7.0)
print(C.preview('ground_grass')); print(C.shade_preview('ground_grass'))
