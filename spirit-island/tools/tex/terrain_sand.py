"""ground_sand — beach sand (tile ~4 m).

Asymmetric wind ripples (gentle stoss, steep lee) whose direction and amplitude wander, flattened where the
macro mask says the sand was smoothed by wash; multi-coloured grain (quartz, feldspar, dark mineral specks);
sparse shell fragments, tiny pebbles and a few dried seaweed strands.
"""
import numpy as np
import terrain_common as C
from terrain_common import T

SS = 2; N = 1024; n = N * SS

# ---------------- ripples (tileable: integer cycles across the tile, domain-warped)
yy, xx = np.meshgrid(np.arange(N, dtype=np.float32) / N, np.arange(N, dtype=np.float32) / N, indexing='ij')
wx = (T.fbm(N, 2, 4, seed=41) - 0.5); wy = (T.fbm(N, 3, 4, seed=42) - 0.5)
phase = (xx * 23 + yy * 5 + wx * 3.2 + wy * 1.6)          # ~17 cm wavelength, wandering crests
f = phase - np.floor(phase)
prof = np.where(f < 0.72, f / 0.72, (1 - f) / 0.28)          # asymmetric ripple profile
prof = prof * prof * (3 - 2 * prof)
amp = T.levels(T.fbm(N, 3, 4, seed=43), 0.3, 0.7)            # some areas flattened
phase2 = (xx * 41 - yy * 9 + wy * 5.0)                       # faint secondary set
f2 = phase2 - np.floor(phase2); prof2 = np.minimum(f2, 1 - f2) * 2
h_rip = amp * prof + 0.25 * (1 - amp) * prof2
h_base = T.fbm(N, 4, 6, seed=44)
hN = T.norm01(0.55 * h_rip + 0.35 * h_base + 0.1 * T.fbm(N, 64, 2, seed=45))

# ---------------- colour: base tone + grain specks
tone = T.fbm(N, 5, 5, seed=46)
alb = T.ramp(tone, [(0, '#b39d78'), (0.45, '#c6b089'), (1, '#d6c29c')])
alb = T.mix(alb, alb * np.array([0.86, 0.84, 0.82], np.float32), (1 - hN) * 0.6)  # troughs collect darker grains
alb = np.stack([C.up(alb[..., k], n) for k in range(3)], -1)
r = C.rng(47)
g = r.random((n, n)).astype(np.float32)
alb *= (0.9 + 0.2 * r.random((n, n)).astype(np.float32))[..., None]
dark = g < 0.025; quartz = (g > 0.975); pink = (g > 0.955) & (g < 0.962)
alb[dark] = alb[dark] * 0.45 + np.array([0.12, 0.11, 0.1], np.float32)
alb[quartz] = alb[quartz] * 0.5 + np.array([0.48, 0.47, 0.44], np.float32)
alb[pink] = np.array([0.78, 0.6, 0.52], np.float32)
zbuf = C.up(hN, n) * 0.3
col = alb.astype(np.float32)
rough = np.full((n, n), 0.9, np.float32); occ = np.ones((n, n), np.float32)

# ---------------- debris (clustered by a mask: wrack drifts, clean stretches between)
dmask = T.levels(C.up(T.fbm(256, 3, 4, seed=55), n), 0.55, 0.8)
def place(count, seed):
    rr = C.rng(seed); xs = []; ys = []
    while sum(len(a) for a in xs) < count:
        x = rr.random(count) * n; y = rr.random(count) * n
        k = rr.random(count) < dmask[y.astype(int) % n, x.astype(int) % n] * 0.97 + 0.03
        xs.append(x[k]); ys.append(y[k])
    return np.concatenate(xs)[:count], np.concatenate(ys)[:count]
x, y = place(240, 480)
P = C.blobs(n, 240, C.rng(48), x=x, y=y, rad=(3, 9), aspect=(1.0, 1.8), z0=(0.24, 0.3), dome=0.06, curl=0.05)
cols = C.palette(C.rng(49), 240, [(3, '#e9e1d2'), (2, '#d9cbb6'), (1, '#e6c7b6'), (1, '#b9ab98'), (0.6, '#8f7f70')], 0.05)
ring = 0.85 + 0.15 * np.sin(P['u'] * 14.0)                     # growth rings on shell bits
C.splat_points(n, P['iy'], P['ix'], P['z'], [cols[P['id']] * ring[:, None], np.ones(len(ring), np.float32), np.full(len(ring), 0.55, np.float32)], zbuf, [col, occ, rough])
x, y = place(160, 500)
P = C.blobs(n, 160, C.rng(50), x=x, y=y, rad=(4, 11), aspect=(1.0, 1.4), z0=(0.2, 0.26), dome=0.1)
cols = C.palette(C.rng(51), 160, [(3, '#7e776c'), (2, '#9a8f7e'), (1, '#5f5a52'), (1, '#b3a690')], 0.07)
C.splat_points(n, P['iy'], P['ix'], P['z'], [cols[P['id']] * (0.8 + 0.25 * (1 - P['rr']))[:, None], np.ones(len(P['z']), np.float32), np.full(len(P['z']), 0.7, np.float32)], zbuf, [col, occ, rough])
x, y = place(18, 520)
P = C.strokes(n, 18, C.rng(52), x=x, y=y, length=(60, 180), width=(2, 4), bend=0.6, z0=(0.3, 0.32), z1=(0.3, 0.33), taper=0.3)
cols = C.palette(C.rng(53), 18, [(2, '#3e3a24'), (1, '#4f4a2c'), (1, '#2e2b20')], 0.06)
C.splat_points(n, P['iy'], P['ix'], P['z'], [cols[P['id']], np.ones(len(P['z']), np.float32), np.full(len(P['z']), 0.6, np.float32)], zbuf, [col, occ, rough])

h = C.down(zbuf, SS); albedo = C.down(col, SS); ro = C.down(rough, SS)
ao = T.ao_from_height(h, radius=4, strength=1.4)
C.save_set('ground_sand', np.clip(albedo, 0, 1), h, ro, ao, normal_strength=9.0)
print(C.preview('ground_sand')); print(C.shade_preview('ground_sand'))
