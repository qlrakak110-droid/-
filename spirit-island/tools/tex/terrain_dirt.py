"""ground_dirt — trodden path soil (tile ~3 m).

Compacted earth with multi-scale undulation (dust collects on the bumps, moisture darkens the hollows), patches of
embedded gravel, scattered rounded pebbles with their own speckle, hairline drying cracks in dry patches, and a
little organic debris (straw stalks, leaf crumbs, twigs) so it reads as a real walked path rather than flat brown.
"""
import numpy as np
import terrain_common as C
from terrain_common import T

SS = 2; N = 1024; n = N * SS

# ---------------- soil body
b1 = T.fbm(N, 4, 7, seed=21)
b1 = T.warp(b1, T.fbm(N, 3, 3, seed=22), T.fbm(N, 3, 3, seed=23), 0.03)
b2 = T.ridged(N, 10, 4, seed=24)
soilN = T.norm01(0.62 * b1 + 0.26 * b2 + 0.12 * T.fbm(N, 48, 3, seed=25))
soil_h = C.up(soilN, n) * 0.30
moist = T.levels(1 - soilN, 0.45, 0.85)                                  # hollows hold moisture
dust = T.levels(soilN, 0.55, 0.9)
tone = T.fbm(N, 6, 5, seed=26)
soil_c = T.ramp(tone, [(0, '#55402c'), (0.35, '#6a5139'), (0.65, '#7c6247'), (1, '#8d7354')])
soil_c = T.mix(soil_c, soil_c * np.array([0.72, 0.68, 0.64], np.float32), moist * 0.75)
soil_c = T.mix(soil_c, T.ramp(T.fbm(N, 20, 3, seed=27), [(0, '#9a8466'), (1, '#b19b7b')]), dust * 0.45)
# drying cracks only in dry patches
f1, f2, _ = T.worley(N, period=18, seed=28)
crack = (1 - T.levels(f2 - f1, 0.0, 0.025)) * T.levels(T.fbm(N, 3, 3, seed=29), 0.55, 0.75)
soil_c *= (1 - 0.35 * crack)[..., None]
soilN2 = soilN - 0.08 * crack
col = np.stack([C.up(soil_c[..., k], n) for k in range(3)], -1)
col *= (1 + 0.09 * C.grain(n, 30))[..., None]
zbuf = (C.up(soilN2, n) * 0.42).astype(np.float32)
soil_h = zbuf.copy()
rough = (0.93 - 0.1 * C.up(moist, n)).astype(np.float32)
occ = np.ones((n, n), np.float32)

gravel_mask = T.levels(C.up(T.fbm(256, 5, 4, seed=31), n), 0.42, 0.72)


def place(count, mask, seed):
    r = C.rng(seed); xs = []; ys = []
    while sum(len(a) for a in xs) < count:
        x = r.random(count) * n; y = r.random(count) * n
        k = r.random(count) < mask[y.astype(int) % n, x.astype(int) % n]
        xs.append(x[k]); ys.append(y[k])
    return np.concatenate(xs)[:count], np.concatenate(ys)[:count]


stone_cols = [(3, '#7d776e'), (2, '#8e8577'), (2, '#9c8f7c'), (1.5, '#6a5f53'), (1, '#a49b8d'), (0.8, '#8a6a52'), (0.6, '#5a5550'), (0.2, '#b8ad9a')]


def stones(count, x, y, rad, aspect, dome, bury, seed, rough_v):
    r = C.rng(seed)
    P = C.blobs(n, count, r, x=x, y=y, rad=rad, aspect=aspect, z0=(-bury, -bury * 0.5), dome=dome)
    i = P['id']
    base = soil_h[y.astype(int) % n, x.astype(int) % n]
    P['z'] = P['z'] + base[i]
    cols = C.palette(C.rng(seed + 1), count, stone_cols, 0.08)
    pix = C.rng(seed + 2).random(len(i)).astype(np.float32)
    sc = col[y.astype(int) % n, x.astype(int) % n][i]                    # dust from the surrounding soil
    c = (cols[i] * 0.62 + sc * 0.38) * (0.82 + 0.25 * (1 - P['rr'] ** 2))[:, None] * (0.9 + 0.18 * pix)[:, None]
    C.splat_points(n, P['iy'], P['ix'], P['z'], [c, np.full(len(i), 1.0, np.float32), np.full(len(i), rough_v, np.float32)], zbuf, [col, occ, rough])


# fine gravel in patches
for ch in range(2):
    x, y = place(7000, gravel_mask * 0.95 + 0.02, 40 + ch)
    stones(7000, x, y, (2.2, 5.5), (1.0, 1.6), 0.05, 0.02, 50 + ch * 3, 0.72)
# rounded pebbles, sparse
x, y = place(520, 0.3 + 0.7 * gravel_mask, 60)
stones(520, x, y, (8, 20), (1.0, 1.45), 0.12, 0.05, 61, 0.66)

# ---------------- organic debris
straw = [(3, '#a08c5c'), (2, '#8a7448'), (1, '#c0ad7e'), (1, '#6e5a3a')]
r = C.rng(70)
P = C.strokes(n, 700, r, length=(20, 70), width=(1.4, 2.4), bend=0.3, z0=(0.3, 0.34), z1=(0.3, 0.36), taper=0.3)
cols = C.palette(C.rng(71), 700, straw, 0.08) * 0.85
c = cols[P['id']] * (0.8 + 0.25 * (1 - np.abs(P['across'])))[:, None]
C.splat_points(n, P['iy'], P['ix'], P['z'], [c, np.full(len(c), 0.9, np.float32), np.full(len(c), 0.85, np.float32)], zbuf, [col, occ, rough])
P = C.blobs(n, 500, C.rng(72), rad=(4, 9), aspect=(1.2, 1.9), z0=(0.3, 0.34), dome=0.02)
cols = C.palette(C.rng(73), 500, [(2, '#6b4a2c'), (2, '#7d5a34'), (1, '#57402a'), (1, '#8e6a3c')], 0.08)
C.splat_points(n, P['iy'], P['ix'], P['z'], [cols[P['id']] * (0.85 + 0.2 * P['rr'])[:, None], np.full(len(P['z']), 0.95, np.float32), np.full(len(P['z']), 0.88, np.float32)], zbuf, [col, occ, rough])
P = C.strokes(n, 140, C.rng(74), length=(60, 160), width=(3, 5), bend=0.2, z0=(0.34, 0.36), z1=(0.34, 0.38), taper=0.4)
cols = C.palette(C.rng(75), 140, [(2, '#5e4a38'), (1, '#74604c'), (1, '#4a3a2c')], 0.06)
c = cols[P['id']] * (0.75 + 0.35 * (1 - np.abs(P['across'])))[:, None]
C.splat_points(n, P['iy'], P['ix'], P['z'], [c, np.full(len(c), 1.0, np.float32), np.full(len(c), 0.8, np.float32)], zbuf, [col, occ, rough])

# ---------------- finish
h = C.down(zbuf, SS); albedo = C.down(col, SS); ro = C.down(rough, SS)
cav = T.ao_from_height(h, radius=4, strength=2.2)
ao = cav * (0.85 + 0.15 * T.blur(h, 6) / max(h.max(), 1e-3))
albedo *= (0.8 + 0.2 * ao)[..., None]
C.save_set('ground_dirt', np.clip(albedo, 0, 1), h, ro, np.clip(ao, 0, 1), normal_strength=11.0)
print(C.preview('ground_dirt')); print(C.shade_preview('ground_dirt'))
