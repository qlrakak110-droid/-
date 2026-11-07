"""Rock surface set 'rock_a': fractured stone with lichen, for cliffs and boulders (triplanar)."""
import os, sys, numpy as np
sys.path.insert(0, os.path.dirname(__file__)); import texlib as T
N = 1024; OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'assets', 'tex')
f1, f2, cid = T.worley(N, period=6, seed=11)
cracks = T.levels(f2 - f1, 0.0, 0.08)                     # 0 at cell borders = cracks
base = T.fbm(N, 4, 7, seed=3)
strata = 0.5 + 0.5 * np.sin((np.arange(N)[:, None] / N) * 2 * np.pi * 9 + T.fbm(N, 3, 4, seed=8) * 6)
h = 0.45 * base + 0.25 * cid + 0.15 * strata + 0.25 * cracks
h = T.warp(h, T.fbm(N, 3, 3, seed=21), T.fbm(N, 3, 3, seed=22), 0.02)
h = T.norm01(h + 0.08 * T.ridged(N, 8, 4, seed=5))
tone = T.ramp(h, [(0, '#2d2a27'), (0.35, '#5e584f'), (0.7, '#8b8375'), (1, '#b9b0a0')])
lichen = T.levels(T.fbm(N, 6, 5, seed=40), 0.58, 0.75) * T.levels(h, 0.45, 0.8)
tone = T.mix(tone, T.ramp(T.fbm(N, 16, 3, seed=41), [(0, '#5d6b3a'), (1, '#9aa25a')]), lichen * 0.8)
tone *= (0.85 + 0.3 * T.fbm(N, 24, 3, seed=9))[..., None]
rough = 0.62 + 0.3 * (1 - h) - 0.1 * lichen
print(T.save_pbr(OUT, 'rock_a', tone, h, rough, normal_strength=7))
