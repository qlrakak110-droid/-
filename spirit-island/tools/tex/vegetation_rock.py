"""rock PBR sets for boulders / pebbles (triplanar at runtime):
   rock_granite — weathered grey granite: feldspar / quartz / biotite grain, sparse warped cracks, crustose lichen,
                  dirt settled in cavities, rounded weathering relief (1024², phones 512²)
   rock_slate   — (experimental, not shipped: reads as planks) layered sedimentary stone
-> assets/tex/vegetation/rock_*_{albedo,normal,orm}.jpg (+ _512)
"""
import os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
import texlib as T
import vegetation_common as V

N = 1024


def granite():
    big = T.fbm(N, 3, 5, seed=1); mid = T.fbm(N, 8, 4, seed=2)
    rid = T.ridged(N, 4, 5, seed=3)
    # fine mineral grain (kept subtle: it only reads up close)
    G1, G2, ID2 = V.aworley(N, N, 300, 300, seed=5, jitter=1.0)
    bio = (ID2 < 0.1).astype(np.float32); feld = (ID2 > 0.7).astype(np.float32)
    grain = T.blur(bio, 1)
    # cracks: a few long warped fractures
    wx = T.fbm(N, 3, 4, seed=6); wy = T.fbm(N, 3, 4, seed=7)
    C1, C2, CID = V.aworley(N, N, 3, 3, seed=8, jitter=1.0)
    ce = T.warp(C2 - C1, wx, wy, 0.08)
    open_ = np.clip((T.fbm(N, 3, 3, seed=9) - 0.5) * 5, 0, 1)
    crack = (1 - np.clip(ce / 0.022, 0, 1)) * open_
    crack_w = (1 - np.clip(ce / 0.1, 0, 1)) ** 2 * open_
    pits = np.clip((0.18 - V.aworley(N, N, 40, 40, seed=18, jitter=1.0)[0]) * 6, 0, 1) * np.clip((T.fbm(N, 5, 3, seed=19) - 0.5) * 3, 0, 1)
    h = 0.5 * big + 0.28 * rid + 0.14 * mid + 0.03 * feld - 0.03 * grain + 0.02 * (T.fbm(N, 128, 2, seed=10) - 0.5)
    h = T.norm01(h) - 0.5 * crack - 0.12 * crack_w - 0.1 * pits
    h = np.clip(T.norm01(h), 0, 1)
    ao = np.clip(T.ao_from_height(h, 10, 2.0) * (1 - 0.5 * crack), 0, 1)
    tone = np.clip(0.5 + 0.45 * (big - 0.5) + 0.35 * (mid - 0.5), 0, 1)
    rgb = T.ramp(tone, [(0, '#5f5c57'), (0.45, '#7f7b74'), (0.75, '#97928a'), (1, '#aaa59b')])
    rgb = T.mix(rgb, rgb * np.array([1.08, 1.03, 0.98], np.float32), feld * 0.5)
    rgb = T.mix(rgb, np.array([0.18, 0.18, 0.18], np.float32) * np.ones_like(rgb), grain * 0.35)
    stain = np.clip((T.fbm(N, 5, 4, seed=11) - 0.5) * 3, 0, 1)
    rgb = T.mix(rgb, rgb * np.array([0.88, 0.8, 0.68], np.float32), stain * 0.45)
    cav = np.clip((1 - ao) * 2.0, 0, 1)
    rgb = T.mix(rgb, np.array([0.19, 0.16, 0.12], np.float32) * np.ones_like(rgb), np.clip(cav * 0.7 + crack * 0.9 + pits * 0.4, 0, 1))
    # lichen: pale grey-green crust in patches made of small rosettes, black crust spots, rare orange
    L1, L2, LID = V.aworley(N, N, 26, 26, seed=12, jitter=1.0)
    lm = np.clip((T.fbm(N, 4, 4, seed=13) - 0.47) * 4, 0, 1)
    ros = np.clip((0.5 + 0.3 * T.fbm(N, 64, 3, seed=14) - L1) * 7, 0, 1) * lm * (1 - crack)
    lich = T.ramp(T.fbm(N, 32, 3, seed=15), [(0, '#9a9e86'), (0.6, '#b6b89c'), (1, '#cfcdb2')])
    rgb = T.mix(rgb, lich, ros * 0.8)
    blk = np.clip((0.22 - L1) * 9, 0, 1) * (LID < 0.18) * np.clip((T.fbm(N, 5, 3, seed=20) - 0.4) * 3, 0, 1)
    rgb = T.mix(rgb, np.array([0.1, 0.1, 0.09], np.float32) * np.ones_like(rgb), blk * 0.6)
    orange = np.clip((0.2 - L1) * 10, 0, 1) * (LID > 0.9) * np.clip((T.fbm(N, 6, 3, seed=16) - 0.45) * 4, 0, 1)
    rgb = T.mix(rgb, T.ramp(T.fbm(N, 48, 2, seed=17), [(0, '#b0682a'), (1, '#d08a3a')]), orange * 0.75)
    h = np.clip(h + 0.04 * ros, 0, 1)
    rough = 0.8 + 0.12 * (1 - h) + 0.06 * ros
    files = V.save_pbr_jpg('rock_granite', np.clip(rgb, 0, 1), h, np.clip(rough, 0, 1), ao, normal_strength=6.0, q=86)
    print(V.lit_preview('rock_granite'))
    return files


def slate():
    """layered sedimentary stone: bands of varying thickness, fine bedding lines, chipped ledges, iron stains"""
    n = 1024
    big = T.fbm(n, 3, 5, seed=21)
    wob = V.afbm(n, n, 1, 4, 3, seed=22)                              # slow wobble of the beds along x
    yy = np.arange(n, dtype=np.float32)[:, None] / n
    t = yy + (wob - 0.5) * 0.06
    # irregular bed boundaries: cumulative random thicknesses (periodic: 9 beds per tile)
    r = np.random.default_rng(24); th = r.uniform(0.5, 1.6, 9); bounds = np.concatenate([[0], np.cumsum(th) / th.sum()])
    tt = t % 1.0
    idx = np.clip(np.searchsorted(bounds, tt, side='right') - 1, 0, 8)
    local = (tt - bounds[idx]) / (bounds[idx + 1] - bounds[idx])
    bedtone = r.random(9)[idx]
    bed = np.clip(np.minimum(local, 1 - local) * 10, 0, 1)            # rounded bed edges
    fine = ((t * 70 + V.afbm(n, n, 2, 8, 3, seed=25) * 0.8) % 1.0)
    fine = np.clip(np.abs(fine - 0.5) * 2, 0, 1)
    chips = V.aworley(n, n, 12, 6, seed=26, jitter=1.0)
    chip = np.clip(1 - (chips[1] - chips[0]) / 0.04, 0, 1) * np.clip((T.fbm(n, 6, 3, seed=27) - 0.5) * 4, 0, 1)
    h = 0.55 * bed + 0.25 * big + 0.05 * fine + 0.1 * bedtone + 0.06 * T.fbm(n, 64, 3, seed=28) - 0.15 * chip
    h = np.clip(T.norm01(h), 0, 1)
    ao = np.clip(T.ao_from_height(h, 6, 2.2), 0, 1)
    tone = np.clip(0.5 + 0.35 * (bedtone - 0.5) + 0.3 * (big - 0.5) + 0.06 * (fine - 0.5), 0, 1)
    rgb = T.ramp(tone, [(0, '#5a5650'), (0.5, '#7a746a'), (1, '#9b9385')])
    iron = np.clip((T.fbm(n, 4, 4, seed=29) - 0.55) * 4, 0, 1)
    rgb = T.mix(rgb, T.ramp(big, [(0, '#7a5638'), (1, '#9a7048')]), iron * 0.45)
    rgb = T.mix(rgb, np.array([0.16, 0.14, 0.12], np.float32) * np.ones_like(rgb), np.clip((1 - ao) * 1.8 + chip * 0.4, 0, 1) * 0.75)
    rough = 0.74 + 0.18 * (1 - h)
    files = V.save_pbr_jpg('rock_slate', np.clip(V.down(rgb, 2), 0, 1), V.down(h, 2), np.clip(V.down(rough, 2), 0, 1), V.down(ao, 2), normal_strength=5.0, q=88)
    print(V.lit_preview('rock_slate'))
    return files


if __name__ == '__main__':
    for w in (sys.argv[1:] or ['granite']): print(globals()[w]())
