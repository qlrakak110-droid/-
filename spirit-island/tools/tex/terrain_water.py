"""water_normal — tileable sea-surface detail for the terrain workstream's water shader.

RGB PNG (512): R,G = tangent-space normal x/y (z is rebuilt in the shader), B = lacy foam pattern.
The height field is a sum of ~180 directional waves with integer wave vectors (so it tiles), a wind-aligned
spectrum (amplitude ~ k^-1.3, +-70 deg spread) plus capillary ripples; the shader samples it twice, scrolling in
two directions at two scales, which hides the period.
"""
import os, numpy as np
from PIL import Image
import terrain_common as C
from terrain_common import T

N = 512
r = C.rng(901)
yy, xx = np.meshgrid(np.arange(N, dtype=np.float32) / N, np.arange(N, dtype=np.float32) / N, indexing='ij')
h = np.zeros((N, N), np.float32)
wind = 0.6
for i in range(180):
    k = r.uniform(2, 34)
    a = wind + r.normal(0, 0.7) if i < 150 else r.uniform(0, 2 * np.pi)
    kx, ky = int(round(np.cos(a) * k)), int(round(np.sin(a) * k))
    if kx == 0 and ky == 0: continue
    kk = np.hypot(kx, ky)
    amp = kk ** -1.3 * (0.35 if i >= 150 else 1.0)
    ph = r.random() * 2 * np.pi
    # slightly peaked (trochoid-like) crests
    s = np.sin(2 * np.pi * (kx * xx + ky * yy) + ph)
    h += amp * (s - 0.25 * s * s)
h += 0.06 * (T.fbm(N, 32, 3, seed=902) - 0.5)
h = T.norm01(h)
nrm = T.normal_from_height(h, 9.0)
f1, f2, _ = T.worley(N, period=24, seed=903)
lace = 1 - T.levels(f2 - f1, 0.0, 0.08)
bub = T.levels(f1, 0.0, 0.35)
foam = np.clip(lace * 0.75 + (1 - bub) * 0.25, 0, 1) * (0.6 + 0.4 * T.fbm(N, 8, 3, seed=904))
out = np.stack([nrm[..., 0], nrm[..., 1], foam], -1)
os.makedirs(C.OUT, exist_ok=True)
p = os.path.join(C.OUT, 'water_normal.png')
Image.fromarray(np.clip(out * 255 + 0.5, 0, 255).astype(np.uint8)).save(p, optimize=True)
print(p, os.path.getsize(p))
pv = os.path.join(os.environ.get('TEX_PREVIEW', os.getcwd()), '_preview_water.jpg')
Image.fromarray(np.clip(np.concatenate([nrm, np.repeat(foam[..., None], 3, -1)], 1) * 255, 0, 255).astype(np.uint8)).save(pv, quality=85)
print(pv)
