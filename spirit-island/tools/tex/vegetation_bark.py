"""bark PBR sets (tileable; u = around the trunk, v = along it):
   bark_oak   — grey-brown broadleaf bark: long vertical plates split by deep fissures, cross-cracks, crustose lichen
   bark_birch — chalk-white birch: horizontal lenticels, grey scars, peeling warm curls, dark fissured patches
   bark_pine  — conifer bark: red-brown flaky plates in layers over dark grey-brown furrows
-> assets/tex/vegetation/bark_*_{albedo,normal,orm}.jpg (512²) + _512 (256²). Painted at 1024² and downsampled.
"""
import os, sys
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(__file__))
import texlib as T
import vegetation_common as V

N = 1024
OUT_SIZE = 512


def down2(a):
    f = N // OUT_SIZE
    return V.down(a, f)


def finish(name, rgb, h, rough, ao, nstr):
    rgb, h, rough, ao = down2(rgb), down2(h), down2(rough), down2(ao)
    files = V.save_pbr_jpg(name, np.clip(rgb, 0, 1), np.clip(h, 0, 1), np.clip(rough, 0, 1), np.clip(ao, 0, 1), normal_strength=nstr, q=90)
    print(V.lit_preview(name))
    return files


def oak():
    # long vertical plates (9 around, 3 along) split again by a finer cell layer; fissures of varying width
    w1 = V.afbm(N, N, 4, 4, 4, seed=3); w2 = V.afbm(N, N, 4, 4, 4, seed=4)
    F1, F2, ID = V.aworley(N, N, 3, 9, seed=11, jitter=0.9, sy=0.3, sx=1.0)
    G1, G2, ID2 = V.aworley(N, N, 7, 18, seed=12, jitter=0.9, sy=0.35, sx=1.0)
    e1 = T.warp(F2 - F1, w1, w2, 0.035); e2 = T.warp(G2 - G1, w2, w1, 0.03)
    wid = 0.1 + 0.16 * V.afbm(N, N, 6, 4, 3, seed=5)
    fiss = 1 - np.clip(e1 / wid, 0, 1) ** 0.8                        # main furrows
    sub = (1 - np.clip(e2 / (wid * 0.55), 0, 1)) * np.clip((V.afbm(N, N, 5, 5, 3, seed=6) - 0.42) * 4, 0, 1)
    fib = V.afbm(N, N, 3, 64, 4, seed=7)                             # vertical fibres
    rough_top = V.afbm(N, N, 24, 24, 3, seed=10)
    cross = V.afbm(N, N, 30, 4, 3, seed=8)
    xcr = np.clip((cross - 0.6) * 7, 0, 1) * (1 - fiss)
    big = V.afbm(N, N, 3, 3, 4, seed=9)
    top = np.clip(e1 / 0.18, 0, 1) ** 0.35                           # flat-topped ridges, steep walls
    h = 0.55 * top + 0.12 * (ID - 0.5) + 0.12 * (fib - 0.5) + 0.12 * (rough_top - 0.5) - 0.3 * sub - 0.15 * xcr + 0.06 * (big - 0.5)
    h = h * (1 - 0.85 * fiss)
    h = np.clip(T.norm01(h), 0, 1)
    ao = np.clip(T.ao_from_height(h, 6, 2.6), 0, 1)
    tone = np.clip(0.5 + 0.3 * (big - 0.5) + 0.25 * (ID - 0.5) + 0.35 * (fib - 0.5) + 0.25 * (rough_top - 0.5), 0, 1)
    plate = T.ramp(tone, [(0, '#3e3731'), (0.35, '#57504a'), (0.65, '#706960'), (1, '#8f897f')])
    wall = T.ramp(fib, [(0, '#2a2018'), (1, '#4a3a2c')])            # warm brown inner bark on the furrow walls
    rgb = T.mix(plate, wall, np.clip((1 - top) * 0.8 + sub * 0.5, 0, 1))
    rgb = T.mix(rgb, np.array([0.06, 0.045, 0.035], np.float32) * np.ones_like(rgb), np.clip(fiss * 1.2, 0, 1))
    lich_m = np.clip((T.fbm(N, 6, 5, seed=21) - 0.55) * 5, 0, 1) * top * (1 - fiss)
    lich_s = np.clip((T.fbm(N, 96, 2, seed=22) - 0.38) * 3, 0, 1)
    lich_c = T.ramp(T.fbm(N, 5, 3, seed=23), [(0, '#7d876a'), (0.5, '#9aa27e'), (1, '#b9b78e')])
    rgb = T.mix(rgb, lich_c, lich_m * lich_s * 0.7)
    moss = np.clip((T.fbm(N, 4, 4, seed=24) - 0.58) * 4, 0, 1) * np.clip(fiss + sub, 0, 1)
    rgb = T.mix(rgb, T.ramp(fib, [(0, '#28361a'), (1, '#4a5a26')]), moss * 0.55)
    rgb *= (0.7 + 0.3 * ao)[..., None]
    rough = 0.86 + 0.1 * fiss - 0.06 * lich_m
    return finish('bark_oak', rgb, h, rough, ao, 8.0)


def birch():
    base_n = V.afbm(N, N, 6, 3, 5, seed=31)
    fine = V.afbm(N, N, 64, 12, 3, seed=32)
    # lenticels: short horizontal dark dashes, irregular length/thickness
    r = np.random.default_rng(33)
    lent = np.zeros((N, N), np.float32)
    yy = np.arange(N)[:, None]; xx = np.arange(N)[None, :]
    for _ in range(170):
        cy, cx = r.integers(N), r.integers(N); L = r.uniform(14, 110) * (1 + 1.2 * (r.random() < 0.15)); th = r.uniform(0.9, 2.4)
        y0, y1 = int(cy - 6), int(cy + 7); x0, x1 = int(cx - L / 2 - 4), int(cx + L / 2 + 4)
        ys = np.arange(y0, y1) % N; xs = np.arange(x0, x1) % N
        dy = (np.arange(y0, y1)[:, None] - cy); dx = (np.arange(x0, x1)[None, :] - cx)
        prof = np.clip(1 - (dx / (L / 2)) ** 2, 0, 1) ** 0.6
        m = np.clip(th * prof - np.abs(dy - 0.15 * dx * r.uniform(-0.2, 0.2)) + 0.5, 0, 1) * r.uniform(0.55, 1)
        lent[np.ix_(ys, xs)] = np.maximum(lent[np.ix_(ys, xs)], m)
    # dark rough patches (old fissured bark) and grey scars
    patch = np.clip((V.afbm(N, N, 3, 4, 5, seed=34) - 0.62) * 5, 0, 1)
    F1, F2, ID = V.aworley(N, N, 6, 10, seed=35, sy=0.5)
    pfiss = np.clip(1 - (F2 - F1) / 0.18, 0, 1) * patch
    scar = np.clip((V.afbm(N, N, 5, 8, 4, seed=36) - 0.66) * 6, 0, 1) * (1 - patch)
    peel = np.clip((V.afbm(N, N, 10, 5, 4, seed=37) - 0.64) * 6, 0, 1) * (1 - patch) * (1 - scar)
    rgb = T.ramp(np.clip(base_n * 0.8 + fine * 0.2, 0, 1), [(0, '#cfc8bb'), (0.5, '#e4ded2'), (1, '#f1ece2')])
    rgb = T.mix(rgb, T.ramp(fine, [(0, '#e9cfae'), (1, '#f4dcc0')]), peel * 0.7)               # warm peeling layers
    rgb = T.mix(rgb, T.ramp(base_n, [(0, '#8d8a84'), (1, '#b1aca2')]), scar * 0.8)
    rgb = T.mix(rgb, T.ramp(fine, [(0, '#1c1a19'), (1, '#4a4642')]), np.clip(patch * 0.85 + pfiss * 0.2, 0, 1))
    rgb = T.mix(rgb, T.ramp(fine, [(0, '#1e1b19'), (1, '#4e4741')]), np.clip(lent, 0, 1) * 0.8)
    h = 0.6 + 0.08 * (fine - 0.5) - 0.25 * lent + 0.12 * peel - 0.15 * patch - 0.35 * pfiss + 0.05 * (base_n - 0.5)
    h = np.clip(T.norm01(h), 0, 1)
    ao = np.clip(T.ao_from_height(h, 4, 1.8), 0, 1)
    rough = 0.62 + 0.25 * patch + 0.1 * lent - 0.08 * peel
    return finish('bark_birch', rgb * (0.85 + 0.15 * ao)[..., None], h, rough, ao, 4.0)


def pine():
    w1 = V.afbm(N, N, 5, 5, 4, seed=42); w2 = V.afbm(N, N, 5, 5, 4, seed=43)
    F1, F2, ID = V.aworley(N, N, 4, 6, seed=41, jitter=0.95, sy=0.6, sx=1.0)
    G1, G2, ID2 = V.aworley(N, N, 9, 12, seed=46, jitter=0.95, sy=0.6, sx=1.0)
    e1 = T.warp(F2 - F1, w1, w2, 0.06); e2 = T.warp(G2 - G1, w2, w1, 0.05)
    wid = 0.08 + 0.14 * V.afbm(N, N, 5, 5, 3, seed=47)
    fiss = 1 - np.clip(e1 / wid, 0, 1) ** 0.7
    sub = (1 - np.clip(e2 / (wid * 0.5), 0, 1)) * np.clip((V.afbm(N, N, 6, 6, 3, seed=48) - 0.45) * 4, 0, 1)
    # flaky layers: terraces of a plate-local noise, the exposed under-layers are fresh orange
    flake_n = V.afbm(N, N, 8, 8, 4, seed=44) + 0.35 * ID
    q = flake_n * 4.0; terr = np.floor(q) + np.clip((q - np.floor(q) - 0.75) * 5, 0, 1)
    terr = terr / 5.0
    lay = (q - np.floor(q))                                           # 0 just above a step, 1 at the next
    fresh = np.clip(1 - lay * 3, 0, 1) * (1 - fiss)
    big = V.afbm(N, N, 3, 3, 4, seed=45); grain = V.afbm(N, N, 32, 32, 3, seed=49)
    top = np.clip(e1 / 0.16, 0, 1) ** 0.45
    h = (0.45 * top + 0.35 * terr + 0.06 * (grain - 0.5) - 0.25 * sub) * (1 - 0.9 * fiss)
    h = np.clip(T.norm01(h), 0, 1)
    ao = np.clip(T.ao_from_height(h, 6, 2.6), 0, 1)
    tone = np.clip(0.5 + 0.3 * (ID - 0.5) + 0.3 * (big - 0.5) + 0.25 * (grain - 0.5), 0, 1)
    skin = T.ramp(tone, [(0, '#3f3631'), (0.4, '#5c4d43'), (0.75, '#776457'), (1, '#8e7a6a')])      # weathered grey-brown
    under = T.ramp(tone, [(0, '#7a3c22'), (0.5, '#9c5430'), (1, '#b86a40')])                         # fresh red-orange layers
    rgb = T.mix(skin, under, np.clip(fresh * 0.85 + (big - 0.5) * 0.4 + 0.15, 0, 1) * top)
    rgb = T.mix(rgb, T.ramp(grain, [(0, '#2a1a12'), (1, '#4a2e1e')]), np.clip(sub * 0.7 + (1 - top) * 0.6, 0, 1))
    rgb = T.mix(rgb, np.array([0.05, 0.035, 0.028], np.float32) * np.ones_like(rgb), np.clip(fiss * 1.2, 0, 1))
    rgb *= (0.72 + 0.28 * ao)[..., None]
    rough = 0.85 + 0.1 * fiss - 0.05 * fresh
    return finish('bark_pine', rgb, h, rough, ao, 8.0)


if __name__ == '__main__':
    which = sys.argv[1:] or ['oak', 'birch', 'pine']
    for w in which: print(globals()[w]())
