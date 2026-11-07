"""ground_rock — weathered cliff rock for steep terrain (tile ~6 m, sampled triplanar).

Three fracture scales (blocks ~2 m, joints ~70 cm, hairline), each block tilted on its own plane so faces catch
light differently, rounded/weathered edges, warped strata, erosion ridges; colour varies per block, dirt and
moisture collect in the joints, crustose lichen colonies (grey-green, sulphur, rare orange) on the exposed faces.
"""
import numpy as np
import terrain_common as C
from terrain_common import T

N = 1024
yy, xx = np.meshgrid(np.arange(N, dtype=np.float32) / N, np.arange(N, dtype=np.float32) / N, indexing='ij')
wx, wy = T.fbm(N, 3, 4, seed=201), T.fbm(N, 3, 4, seed=202)


def fractures(period, seed, warp):
    f1, f2, cid = T.worley(N, period=period, seed=seed)
    if warp:
        f1 = T.warp(f1, wx, wy, warp); f2 = T.warp(f2, wx, wy, warp); cid = T.warp(cid, wx, wy, warp)
    return f2 - f1, cid


e1, c1 = fractures(3, 211, 0.05)
e2, c2 = fractures(7, 212, 0.03)
# large forms: strongly warped fbm with sedimentary ledges (stepped, softened)
big = T.fbm(N, 3, 6, seed=230)
big = T.warp(big, wx, wy, 0.06)
t = big * 7.0
terr = (np.floor(t) + T.levels(t - np.floor(t), 0.55, 1.0) ** 2) / 7.0
strata = 0.5 + 0.5 * np.sin(2 * np.pi * (yy * 13 + (wx - 0.5) * 2.2 + (wy - 0.5) * 0.8))
detail = T.fbm(N, 16, 5, seed=214)
erosion = T.ridged(N, 5, 6, seed=215)
# fractures appear only where a noise gate allows: irregular, discontinuous cracks with varying width
g1 = T.levels(T.fbm(N, 4, 4, seed=231), 0.42, 0.62)
g2 = T.levels(T.fbm(N, 6, 4, seed=232), 0.5, 0.66)
w1 = 0.012 + 0.03 * T.fbm(N, 12, 3, seed=233)
crack1 = (1 - np.clip(e1 / w1, 0, 1)) * g1
crack2 = (1 - np.clip(e2 / (w1 * 0.5), 0, 1)) * g2
chips = T.ridged(N, 14, 4, seed=236)
h = 0.5 * terr + 0.14 * big + 0.18 * erosion + 0.07 * chips + 0.08 * detail + 0.03 * strata * T.levels(big, 0.3, 0.7) + 0.06 * c1 * g1
h = h - 0.2 * crack1 - 0.08 * crack2
h = T.norm01(h)

# ---------------- colour
region = T.fbm(N, 2, 4, seed=234)
base = T.ramp(region * 0.6 + big * 0.4, [(0, '#55504a'), (0.3, '#66615a'), (0.55, '#77706a'), (0.8, '#867d70'), (1, '#958c7f')])
mott = T.fbm(N, 12, 5, seed=216)
alb = base * (0.84 + 0.28 * mott)[..., None] * (0.96 + 0.08 * strata)[..., None]
alb = T.mix(alb, alb * np.array([1.08, 1.0, 0.88], np.float32), T.levels(T.fbm(N, 4, 3, seed=217), 0.55, 0.8) * 0.6)   # iron staining
cav = T.ao_from_height(h, radius=10, strength=2.2)
expo = T.levels(h - T.blur(h, 8), 0.0, 0.06)                      # exposed edges / ledge lips
alb = T.mix(alb, np.array([0.70, 0.67, 0.62], np.float32) * (0.92 + 0.16 * detail)[..., None], expo * 0.35)
joint = np.clip(crack1 + crack2 * 0.7 + (1 - cav) * 0.8, 0, 1)
alb = T.mix(alb, np.array([0.16, 0.14, 0.115], np.float32), joint * 0.55)
# crustose lichen: fine blotches clustered at two scales, colour by a low-frequency field
colony = T.levels(T.fbm(N, 10, 5, seed=219), 0.6, 0.68) * T.levels(T.fbm(N, 3, 3, seed=220), 0.35, 0.7) * (1 - joint)
kind = T.fbm(N, 4, 3, seed=235)
lcol = T.ramp(kind, [(0, '#9aa08a'), (0.45, '#a8a98e'), (0.6, '#a9a660'), (0.8, '#b9b7a4'), (0.92, '#b07a46'), (1, '#b07a46')])
lcol = lcol * (0.85 + 0.3 * T.fbm(N, 80, 2, seed=221))[..., None]
alb = T.mix(alb, lcol, colony * 0.8)
alb *= (1 + 0.06 * C.grain(N, 222))[..., None]
h2 = np.clip(h + colony * 0.015, 0, 1)
weather = expo; edge1 = 1 - crack1
rough = np.clip(0.78 + 0.12 * (1 - h) + 0.08 * colony - 0.08 * weather + 0.1 * joint, 0, 1)
ao = np.clip(T.ao_from_height(h2, radius=8, strength=1.8) * (1 - 0.5 * joint), 0, 1)
C.save_set('ground_rock', np.clip(alb, 0, 1), h2, rough, ao, normal_strength=40.0, blend_h=T.norm01(T.blur(h2, 2)))
print(C.preview('ground_rock')); print(C.shade_preview('ground_rock'))
