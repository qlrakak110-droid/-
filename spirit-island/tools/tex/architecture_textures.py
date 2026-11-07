"""Village PBR sets (architecture workstream) -> assets/tex/architecture/arch_<set>_{albedo,normal,orm}.jpg (+ _512)

  arch_plaster  lime plaster (2.5 m tile): trowel swirls, sand grain, hairline cracks, flaked patches showing the
                rough render underneath. Near-white so the runtime wall colour tints it. Grime is added at runtime.
  arch_wood     weathered timber (U across 0.5 m, V along the grain 2 m): annual rings with early/late wood relief,
                knots that deflect the grain, drying checks, silvered ridges and brown grooves.
  arch_stone    rubble masonry (2 m tile): irregular coursed fieldstones of mixed geology, recessed sandy mortar,
                rounded weathered arrises, pitting, lichen rosettes and dirt in the joints.
  arch_tile     glazed clay pantile surface (one tile, 512): glaze variation, crazing, sooty speckles, lichen.
  arch_cobble   plaza setts (3 m tile): rounded granite / basalt cobbles, polished tops, sand and moss joints.
  arch_iron     forged iron (0.5 m tile, 512): hammer dents, rust blooms and pitting.
usage: python3 tools/tex/architecture_textures.py [set ...]   (previews -> $TEX_PREVIEW or cwd)
"""
import os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
import texlib as T
import architecture_common as A

PREV = os.environ.get('TEX_PREVIEW', os.getcwd())
N = 1024


def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def grid(n):
    yy, xx = np.meshgrid(np.arange(n, dtype=np.float32) / n, np.arange(n, dtype=np.float32) / n, indexing='ij')
    return yy, xx


# ------------------------------------------------------------------ plaster
def plaster():
    low = T.fbm(N, 3, 5, seed=11)
    mid = T.fbm(N, 9, 4, seed=12)
    # trowel swirls: two families of elongated smears, warped so they curve like hand strokes
    wx, wy = T.fbm(N, 4, 3, seed=13), T.fbm(N, 4, 3, seed=14)
    s1 = T.warp(A.afbm(N, N, 22, 5, 4, seed=15), wx, wy, 0.06)
    s2 = T.warp(A.afbm(N, N, 6, 20, 4, seed=16), wy, wx, 0.06)
    pick = sstep(0.4, 0.6, T.fbm(N, 4, 3, seed=17))
    trowel = s1 * pick + s2 * (1 - pick)
    ridge = 1 - np.abs(trowel - 0.5) * 2                                   # soft ridges where strokes meet
    grain = 0.6 * T.value_noise(N, 256, seed=18) + 0.4 * T.value_noise(N, 512, seed=19)
    pores = np.clip((0.12 - A.aworley(N, N, 90, 90, seed=20)[0]) * 10, 0, 1) * (T.fbm(N, 8, 3, seed=21) > 0.45)
    # hairline cracks: warped cell edges, only in a few regions
    c1, c2, _ = A.aworley(N, N, 5, 5, seed=22, jitter=1.0)
    ce = T.warp(c2 - c1, T.fbm(N, 6, 4, seed=23), T.fbm(N, 6, 4, seed=24), 0.03)
    crack = (1 - np.clip(ce / 0.012, 0, 1)) * sstep(0.56, 0.66, T.fbm(N, 3, 4, seed=25))
    # flaked patches: plaster gone, rough grey-brown render underneath with a crisp broken edge
    fm = T.fbm(N, 5, 6, seed=26)
    flake = sstep(0.715, 0.73, fm)
    flake_edge = sstep(0.70, 0.715, fm) * (1 - flake)
    render = T.fbm(N, 64, 3, seed=27)
    h = 0.42 + 0.16 * (low - 0.5) + 0.1 * (trowel - 0.5) + 0.05 * ridge + 0.05 * (mid - 0.5) + 0.035 * (grain - 0.5)
    h = h - 0.06 * pores - 0.18 * crack
    h = h * (1 - flake) + flake * (0.2 + 0.08 * render) + flake_edge * 0.03
    h = np.clip(h, 0, 1)
    ao = np.clip(T.ao_from_height(h, 6, 2.0) * (1 - 0.4 * crack), 0, 1)
    tone = 0.935 + 0.05 * (low - 0.5) + 0.035 * (mid - 0.5) + 0.03 * (ridge - 0.5) + 0.02 * (grain - 0.5)
    rgb = np.stack([tone * 0.985, tone * 0.972, tone * 0.945], -1)
    # faint water tide marks and a warm ochre wash in places
    wash = sstep(0.55, 0.75, T.fbm(N, 3, 4, seed=28))
    rgb = T.mix(rgb, rgb * A.col('#efe2c8'), wash * 0.35)
    streak = sstep(0.62, 0.78, A.afbm(N, N, 2, 26, 3, seed=29)) * sstep(0.45, 0.7, T.fbm(N, 3, 3, seed=30))
    rgb = T.mix(rgb, rgb * A.col('#cfc6b8'), streak * 0.4)
    under = T.ramp(render, [(0, '#7d7366'), (0.5, '#958a7b'), (1, '#ab9f8e')])
    rgb = T.mix(rgb, under, flake)
    rgb = T.mix(rgb, rgb * 0.8, flake_edge * 0.6)
    rgb = T.mix(rgb, A.col('#5a5248') * np.ones_like(rgb), crack * 0.55 + pores * 0.12)
    rough = 0.9 + 0.05 * (grain - 0.5) - 0.06 * ridge * (1 - flake) + 0.05 * flake
    A.save('arch_plaster', np.clip(rgb, 0, 1), h, np.clip(rough, 0, 1), ao, normal_strength=5.0, q=86)
    print(A.preview('arch_plaster', os.path.join(PREV, '_prev_arch_plaster.jpg'), tint=(0.95, 0.9, 0.82)))


# ------------------------------------------------------------------ weathered timber
def wood():
    yy, xx = grid(N)
    # straight grain: ring phase is a 1-D function of x (irregular ring widths), bent only slightly by a slow wobble
    row = lambda per, oc, sd: T.fbm(N, per, oc, seed=sd)[0][None, :]
    wob = A.afbm(N, N, 2, 3, 3, seed=32)
    xw = xx + 0.004 * (wob - 0.5)
    phase = xw * 38 + 4.0 * (row(5, 3, 30) - 0.5) + 2.0 * (row(17, 2, 31) - 0.5) + 0.35 * (A.afbm(N, N, 3, 9, 3, seed=33) - 0.5)
    rings = phase % 1.0
    late = sstep(0.55, 0.8, rings) * sstep(1.0, 0.86, rings)
    fibre = A.afbm(N, N, 4, 260, 2, seed=34)
    streak = A.afbm(N, N, 2, 30, 3, seed=39)
    checks_n = A.aperlin(N, N, 2, 30, seed=35)
    check = (1 - np.clip(np.abs(checks_n - 0.5) / 0.007, 0, 1)) * sstep(0.5, 0.62, A.afbm(N, N, 2, 3, 3, seed=36))
    erode = A.afbm(N, N, 3, 14, 4, seed=37)
    h = 0.5 + 0.09 * late + 0.06 * (fibre - 0.5) + 0.08 * (erode - 0.5) + 0.04 * (streak - 0.5) - 0.45 * check
    h = np.clip(h, 0, 1)
    ao = np.clip(T.ao_from_height(h, 3, 2.4) * (1 - 0.6 * check), 0, 1)
    silver = sstep(0.4, 0.75, A.afbm(N, N, 2, 7, 4, seed=38))
    tone = np.clip(0.5 + 0.55 * (fibre - 0.5) + 0.7 * (streak - 0.5), 0, 1)
    base = T.ramp(tone, [(0, '#76614d'), (0.5, '#8a735d'), (1, '#9f8971')])
    grey = T.ramp(tone, [(0, '#857f76'), (0.5, '#99938a'), (1, '#aea89c')])
    rgb = T.mix(base, grey, silver * 0.3)
    rgb = T.mix(rgb, rgb * A.col('#8e7a68'), late * 0.4)
    rgb = T.mix(rgb, A.col('#3a2c21') * np.ones_like(rgb), check * 0.85)
    rgb = T.mix(rgb, rgb * 0.86, (1 - ao) * 0.8)
    rough = 0.8 + 0.1 * (1 - h) + 0.04 * silver - 0.04 * late
    A.save('arch_wood', np.clip(rgb, 0, 1), h, np.clip(rough, 0, 1), ao, normal_strength=6.0, q=86)
    print(A.preview('arch_wood', os.path.join(PREV, '_prev_arch_wood.jpg')))


# ------------------------------------------------------------------ rubble masonry
def stone():
    r = np.random.default_rng(43)
    # coursed rubble: rows of varying height, stones of varying length, each a ragged rounded block
    stones = []; y = 0.0
    rows = []
    while y < N - 40:
        hgt = r.uniform(92, 150); rows.append((y, hgt)); y += hgt
    sc = N / y; rows = [(a * sc, b * sc) for a, b in rows]
    for (y0, hgt) in rows:
        x = r.uniform(0, 200)
        x0 = x
        while x < x0 + N:
            w = r.uniform(0.9, 2.4) * hgt
            if x + w > x0 + N: w = x0 + N - x
            if w < 0.45 * hgt: break
            hh = hgt * r.uniform(0.82, 1.0)
            cy = y0 + hgt * 0.5 + r.uniform(-0.06, 0.06) * hgt
            stones.append((cy, x + w * 0.5, hh * 0.5, w * 0.5, r.uniform(-0.06, 0.06), r.uniform(3.0, 4.6)))
            # occasional small pinning stone in the joint
            if r.random() < 0.25: stones.append((y0 + hgt * r.choice([0.15, 0.85]), x + w, hgt * 0.16, hgt * 0.22, r.uniform(0, 3), 2.2))
            x += w
    Hs, ID, Mk, ED = A.stamp_stones(N, stones, seed=44, rough_edge=0.1, profile=0.45)
    face = T.fbm(N, 20, 5, seed=45)
    facets = A.aworley(N, N, 24, 24, seed=46, jitter=1.0)
    chip = sstep(0.0, 0.25, facets[1] - facets[0])
    sand = T.value_noise(N, 384, seed=48)
    mort = 1 - Mk
    h = (0.3 + 0.48 * Hs + 0.12 * (face - 0.5) + 0.015 * chip) * Mk + mort * (0.16 + 0.05 * sand)
    h = np.clip(h, 0, 1)
    ao = np.clip(T.ao_from_height(h, 12, 2.0), 0, 1)
    pal = [('#7f7c76', '#9d9890'), ('#8d7d66', '#a59278'), ('#6f7174', '#8a8b8c'), ('#7c6a5a', '#958271'), ('#a39b8d', '#bbb3a4')]
    k = np.clip((ID * len(pal)).astype(int), 0, len(pal) - 1)
    tone = np.clip(0.5 + 0.8 * (face - 0.5) + 0.25 * (T.fbm(N, 6, 3, seed=49) - 0.5), 0, 1)
    rgb = np.zeros((N, N, 3), np.float32)
    for i, (a, b) in enumerate(pal):
        rgb = np.where((k == i)[..., None], T.ramp(tone, [(0, a), (1, b)]), rgb)
    rgb = rgb * (0.9 + 0.18 * ((ID * 7.31) % 1))[..., None]
    mortar = T.ramp(sand, [(0, '#8f877a'), (1, '#a8a091')])
    rgb = T.mix(rgb, mortar, mort)
    cav = np.clip((1 - ao) * 1.6, 0, 1)
    rgb = T.mix(rgb, A.col('#4a4238') * np.ones_like(rgb), np.clip(cav * 0.45, 0, 0.5))
    L1, _, LID = A.aworley(N, N, 30, 30, seed=50, jitter=1.0)
    lm = sstep(0.55, 0.72, T.fbm(N, 4, 4, seed=51)) * Mk
    ros = np.clip((0.42 + 0.3 * T.fbm(N, 64, 3, seed=52) - L1) * 6, 0, 1) * lm
    rgb = T.mix(rgb, T.ramp(T.fbm(N, 32, 2, seed=53), [(0, '#a3a68e'), (1, '#c4c4a8')]), ros * 0.55)
    h = np.clip(h + 0.02 * ros, 0, 1)
    rough = (0.8 + 0.1 * (1 - ED) + 0.04 * ros) * Mk + mort * 0.96
    A.save('arch_stone', np.clip(rgb, 0, 1), h, np.clip(rough, 0, 1), ao, normal_strength=7.5, q=86)
    print(A.preview('arch_stone', os.path.join(PREV, '_prev_arch_stone.jpg')))


# ------------------------------------------------------------------ glazed pantile (one tile)
def tile():
    n = 512
    yy, xx = grid(n)
    low = T.fbm(n, 3, 4, seed=61); mid = T.fbm(n, 12, 3, seed=62)
    exposed = sstep(0.75, 0.25, yy)
    grain = T.value_noise(n, 192, seed=63)
    c1, c2, _ = A.aworley(n, n, 9, 9, seed=64, jitter=1.0)
    craze = (1 - np.clip((c2 - c1) / 0.02, 0, 1)) * 0.6
    L1, _, LID = A.aworley(n, n, 14, 14, seed=65, jitter=1.0)
    lich = np.clip((0.22 + 0.25 * T.fbm(n, 32, 3, seed=66) - L1) * 8, 0, 1) * (LID < 0.08) * exposed
    soot = np.clip((0.06 - A.aworley(n, n, 50, 50, seed=67)[0]) * 14, 0, 1) * (T.fbm(n, 6, 3, seed=68) > 0.6)
    # weathering: the exposed lower end (v near 0) loses glaze; texture v runs 0 = eave lip .. 1 = head (covered)
    worn = sstep(0.45, 0.75, T.fbm(n, 5, 4, seed=69)) * exposed
    h = 0.5 + 0.12 * (low - 0.5) + 0.06 * (mid - 0.5) + 0.03 * (grain - 0.5) - 0.05 * craze + 0.08 * lich - 0.04 * worn
    h = np.clip(h, 0, 1)
    ao = np.clip(T.ao_from_height(h, 5, 1.6), 0, 1)
    tone = 0.86 + 0.08 * (low - 0.5) + 0.06 * (mid - 0.5) + 0.04 * (grain - 0.5)
    rgb = np.stack([tone, tone * 0.985, tone * 0.97], -1)
    rgb = T.mix(rgb, rgb * A.col('#d9c4a8'), worn * 0.6)                       # bare terracotta body shows through
    rgb = T.mix(rgb, rgb * 0.7, craze * 0.4)
    rgb = T.mix(rgb, A.col('#2b2622') * np.ones_like(rgb), soot * 0.5)
    rgb = T.mix(rgb, T.ramp(T.fbm(n, 24, 2, seed=70), [(0, '#a9ab92'), (1, '#d2d0b4')]), lich * 0.75)
    rough = 0.36 + 0.1 * (mid - 0.5) + 0.4 * worn + 0.4 * lich + 0.2 * soot
    A.save('arch_tile', np.clip(rgb, 0, 1), h, np.clip(rough, 0, 1), ao, normal_strength=3.0, q=88)
    print(A.preview('arch_tile', os.path.join(PREV, '_prev_arch_tile.jpg'), tint=(0.78, 0.32, 0.26)))


# ------------------------------------------------------------------ cobbled plaza
def cobble():
    r = np.random.default_rng(83)
    # setts laid in slightly wavy rows, each a rounded, domed stone; sand / soil joints with a little moss
    rows = 18; ph = N / rows; stones = []
    for i in range(rows):
        x = r.uniform(0, ph); x0 = x
        while x < x0 + N - ph * 0.5:
            w = ph * r.uniform(0.85, 1.35)
            stones.append((i * ph + ph * 0.5 + r.uniform(-0.08, 0.08) * ph, x + w * 0.5, ph * r.uniform(0.4, 0.47), w * r.uniform(0.4, 0.47), r.uniform(-0.25, 0.25), r.uniform(2.2, 3.2)))
            x += w
    Hs, ID, Mk, ED = A.stamp_stones(N, stones, seed=84, rough_edge=0.14, profile=0.5)
    face = T.fbm(N, 40, 4, seed=85)
    sand = T.value_noise(N, 400, seed=86)
    joint = 1 - Mk
    h = (0.32 + 0.55 * Hs + 0.05 * (face - 0.5)) * Mk + joint * (0.14 + 0.06 * sand)
    h = np.clip(h, 0, 1)
    ao = np.clip(T.ao_from_height(h, 8, 1.8), 0, 1)
    pal = [('#7f7d78', '#9a9790'), ('#8e8577', '#a89d8b'), ('#66696c', '#7e8184'), ('#9b958b', '#b4ada1'), ('#867565', '#9e8c7a')]
    k = np.clip((ID * len(pal)).astype(int), 0, len(pal) - 1)
    tone = np.clip(0.5 + 0.9 * (face - 0.5), 0, 1)
    rgb = np.zeros((N, N, 3), np.float32)
    for i, (a, b) in enumerate(pal):
        rgb = np.where((k == i)[..., None], T.ramp(tone, [(0, a), (1, b)]), rgb)
    rgb = rgb * (0.9 + 0.2 * ((ID * 5.77) % 1))[..., None]
    polish = sstep(0.3, 0.8, ED) * Mk
    rgb = T.mix(rgb, rgb * 1.08, polish * 0.5)
    rgb = T.mix(rgb, rgb * 0.8, (1 - sstep(0.0, 0.25, ED)) * Mk * 0.6)          # dirt along each stone's rim
    soil = T.ramp(sand, [(0, '#6b5d4c'), (1, '#8a7a64')])
    rgb = T.mix(rgb, soil, joint)
    moss = sstep(0.58, 0.72, T.fbm(N, 5, 4, seed=87)) * joint
    rgb = T.mix(rgb, T.ramp(T.fbm(N, 64, 2, seed=88), [(0, '#45522c'), (1, '#66763a')]), moss * 0.75)
    rgb = T.mix(rgb, rgb * 0.8, np.clip((1 - ao) * 1.2, 0, 0.45))
    rough = (0.74 - 0.2 * polish + 0.06 * (face - 0.5)) * Mk + joint * 0.97
    A.save('arch_cobble', np.clip(rgb, 0, 1), h, np.clip(rough, 0, 1), ao, normal_strength=8.0, q=86)
    print(A.preview('arch_cobble', os.path.join(PREV, '_prev_arch_cobble.jpg')))


# ------------------------------------------------------------------ forged iron
def iron():
    n = 512
    dents = A.aworley(n, n, 14, 14, seed=91, jitter=1.0)[0]
    low = T.fbm(n, 4, 4, seed=92)
    rust = sstep(0.52, 0.7, T.fbm(n, 5, 5, seed=93))
    bloom = sstep(0.6, 0.75, T.fbm(n, 16, 3, seed=94)) * sstep(0.4, 0.6, low)
    rust = np.clip(rust + bloom * 0.7, 0, 1)
    pit = np.clip((0.12 - A.aworley(n, n, 60, 60, seed=95)[0]) * 10, 0, 1) * rust
    h = 0.55 + 0.18 * np.clip(dents, 0, 0.7) + 0.1 * (low - 0.5) + 0.1 * rust * T.fbm(n, 48, 3, seed=96) - 0.12 * pit
    h = np.clip(h, 0, 1)
    ao = np.clip(T.ao_from_height(h, 4, 1.6), 0, 1)
    metal = T.ramp(low, [(0, '#24221f'), (1, '#3b3834')])
    rc = T.ramp(T.fbm(n, 24, 3, seed=97), [(0, '#4a2a17'), (0.5, '#6e3d1e'), (1, '#94582b')])
    rgb = T.mix(metal, rc, rust * 0.85)
    rgb = T.mix(rgb, A.col('#1a1512') * np.ones_like(rgb), pit * 0.6)
    rough = 0.5 + 0.1 * (low - 0.5) + 0.38 * rust
    A.save('arch_iron', np.clip(rgb, 0, 1), h, np.clip(rough, 0, 1), ao, normal_strength=4.0, q=86)
    print(A.preview('arch_iron', os.path.join(PREV, '_prev_arch_iron.jpg')))


SETS = {'plaster': plaster, 'wood': wood, 'stone': stone, 'tile': tile, 'cobble': cobble, 'iron': iron}
if __name__ == '__main__':
    for k in (sys.argv[1:] or SETS.keys()):
        SETS[k]()
