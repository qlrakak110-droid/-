"""texlib — tileable PBR texture synthesis with numpy (no other deps).

All generators return float32 arrays in [0, 1] (H, W) and TILE SEAMLESSLY (periodic lattices).
Typical use (see make_example.py):

    import texlib as T
    h = T.fbm(1024, period=8, octaves=6, seed=1)               # height
    h = T.warp(h, T.fbm(1024, 4, 3, seed=2), T.fbm(1024, 4, 3, seed=3), amount=0.04)
    rgb = T.ramp(h, [(0, '#3a332c'), (0.5, '#7a7062'), (1, '#b8ad9c')])
    T.save_pbr('assets/tex', 'rock_a', albedo=rgb, height=h, rough=0.75 + 0.2 * (1 - h), normal_strength=6)

save_pbr writes  <name>_albedo.jpg (sRGB)  <name>_normal.png  <name>_orm.jpg (R=AO, G=roughness, B=height)
plus *_512 half-size versions for phones, and returns a registerAssets() snippet for the game.
"""
import os
import numpy as np
from PIL import Image

# ------------------------------------------------------------------ noise
def _rng(seed):
    return np.random.default_rng(seed)

def value_noise(n, period, seed=0):
    """periodic smooth value noise, `period` lattice cells across the tile"""
    g = _rng(seed).random((period, period)).astype(np.float32)
    t = np.arange(n, dtype=np.float32) * period / n
    i0 = np.floor(t).astype(int); f = t - i0
    f = f * f * (3 - 2 * f)
    i1 = (i0 + 1) % period; i0 = i0 % period
    a = g[np.ix_(i0, i0)]; b = g[np.ix_(i0, i1)]; c = g[np.ix_(i1, i0)]; d = g[np.ix_(i1, i1)]
    fy = f[:, None]; fx = f[None, :]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy

def perlin(n, period, seed=0):
    """periodic gradient (Perlin) noise in [0,1]"""
    r = _rng(seed); ang = r.random((period, period)) * 2 * np.pi
    gx, gy = np.cos(ang).astype(np.float32), np.sin(ang).astype(np.float32)
    t = np.arange(n, dtype=np.float32) * period / n
    i0 = np.floor(t).astype(int); f = t - i0; i1 = (i0 + 1) % period; i0 %= period
    fy = f[:, None]; fx = f[None, :]
    def dot(iy, ix, oy, ox):
        return gx[np.ix_(iy, ix)] * ox + gy[np.ix_(iy, ix)] * oy
    n00 = dot(i0, i0, fy, fx); n01 = dot(i0, i1, fy, fx - 1); n10 = dot(i1, i0, fy - 1, fx); n11 = dot(i1, i1, fy - 1, fx - 1)
    sx = fx * fx * fx * (fx * (fx * 6 - 15) + 10); sy = fy * fy * fy * (fy * (fy * 6 - 15) + 10)
    v = (n00 * (1 - sx) + n01 * sx) * (1 - sy) + (n10 * (1 - sx) + n11 * sx) * sy
    return np.clip(v * 0.7071 + 0.5, 0, 1)

def fbm(n, period=4, octaves=5, seed=0, gain=0.5, lacunarity=2, kind='perlin'):
    f = perlin if kind == 'perlin' else value_noise
    out = np.zeros((n, n), np.float32); amp = 1.0; tot = 0.0; p = period
    for o in range(octaves):
        out += amp * f(n, int(p), seed + o * 101); tot += amp; amp *= gain; p *= lacunarity
        if p > n // 2: break
    return out / tot

def ridged(n, period=4, octaves=5, seed=0):
    out = np.zeros((n, n), np.float32); amp = 1.0; tot = 0.0; p = period
    for o in range(octaves):
        v = 1 - np.abs(perlin(n, int(p), seed + o * 37) * 2 - 1)
        out += amp * v * v; tot += amp; amp *= 0.5; p *= 2
        if p > n // 2: break
    return out / tot

def worley(n, period=8, seed=0, jitter=1.0):
    """periodic cellular noise. returns (F1, F2, cell_id) with distances normalised to ~[0,1]"""
    r = _rng(seed)
    pts = (r.random((period, period, 2)) * jitter + (1 - jitter) * 0.5).astype(np.float32)
    ids = r.random((period, period)).astype(np.float32)
    t = (np.arange(n, dtype=np.float32) + 0.5) * period / n
    Y, X = np.meshgrid(t, t, indexing='ij')
    cy, cx = np.floor(Y).astype(int), np.floor(X).astype(int)
    f1 = np.full((n, n), 9.0, np.float32); f2 = np.full((n, n), 9.0, np.float32); cid = np.zeros((n, n), np.float32)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            ny, nx = cy + dy, cx + dx
            p = pts[ny % period, nx % period]
            d = np.sqrt((ny + p[..., 0] - Y) ** 2 + (nx + p[..., 1] - X) ** 2)
            closer = d < f1
            f2 = np.where(closer, f1, np.minimum(f2, d))
            cid = np.where(closer, ids[ny % period, nx % period], cid)
            f1 = np.where(closer, d, f1)
    return np.clip(f1, 0, 1.5) / 1.5, np.clip(f2, 0, 1.5) / 1.5, cid

def warp(img, dx, dy, amount=0.05):
    """domain-warp a tileable image by two tileable offset fields (wraps)"""
    n = img.shape[0]
    yy, xx = np.meshgrid(np.arange(n), np.arange(n), indexing='ij')
    sy = (yy + (dy - 0.5) * 2 * amount * n) % n; sx = (xx + (dx - 0.5) * 2 * amount * n) % n
    return bilinear(img, sy, sx)

def bilinear(img, sy, sx):
    n, m = img.shape[:2]
    y0 = np.floor(sy).astype(int); x0 = np.floor(sx).astype(int); fy = sy - y0; fx = sx - x0
    y1 = (y0 + 1) % n; x1 = (x0 + 1) % m; y0 %= n; x0 %= m
    if img.ndim == 3: fy = fy[..., None]; fx = fx[..., None]
    return (img[y0, x0] * (1 - fx) + img[y0, x1] * fx) * (1 - fy) + (img[y1, x0] * (1 - fx) + img[y1, x1] * fx) * fy

def blur(img, r=2):
    """wrap-around box blur (repeated -> approx gaussian)"""
    out = img.astype(np.float32)
    for _ in range(3):
        acc = np.zeros_like(out)
        for k in range(-r, r + 1): acc += np.roll(out, k, axis=0)
        out = acc / (2 * r + 1); acc = np.zeros_like(out)
        for k in range(-r, r + 1): acc += np.roll(out, k, axis=1)
        out = acc / (2 * r + 1)
    return out

def norm01(a):
    a = a.astype(np.float32); lo, hi = a.min(), a.max()
    return (a - lo) / (hi - lo + 1e-8)

def levels(a, lo=0.0, hi=1.0, gamma=1.0):
    return np.clip((a - lo) / (hi - lo + 1e-8), 0, 1) ** gamma

# ------------------------------------------------------------------ colour
def hexrgb(h):
    h = h.lstrip('#'); return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)], np.float32)

def ramp(t, stops):
    """gradient map: stops = [(pos, '#rrggbb'), ...] -> (H, W, 3) sRGB float"""
    t = np.clip(t, 0, 1); pos = np.array([s[0] for s in stops], np.float32); cols = np.stack([hexrgb(s[1]) for s in stops])
    out = np.zeros(t.shape + (3,), np.float32)
    for c in range(3): out[..., c] = np.interp(t, pos, cols[:, c])
    return out

def mix(a, b, t):
    if a.ndim == 3 and np.ndim(t) == 2: t = t[..., None]
    return a * (1 - t) + b * t

# ------------------------------------------------------------------ derived maps
def normal_from_height(h, strength=4.0):
    """tangent-space normal map (OpenGL convention, +Y up) from a tileable height field"""
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * strength
    n = np.stack([-dx, dy, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5

def ao_from_height(h, radius=6, strength=1.6):
    """cheap cavity AO: how far below the local average each texel sits"""
    cav = np.clip((blur(h, radius) - h) * strength * 4, 0, 1)
    return np.clip(1 - cav, 0, 1)

# ------------------------------------------------------------------ io
def _save(arr, path, quality=None):
    a = np.clip(arr * 255 + 0.5, 0, 255).astype(np.uint8)
    im = Image.fromarray(a)
    if path.endswith('.jpg'): im.save(path, quality=quality or 90, subsampling=0, optimize=True)
    else: im.save(path, optimize=True)
    return im

def save_pbr(outdir, name, albedo, height, rough, normal_strength=4.0, ao=None, metal=None, lo=True):
    """writes albedo (jpg), normal (png), orm (jpg: R=AO G=rough B=height) + _512 variants; returns registerAssets snippet"""
    os.makedirs(outdir, exist_ok=True)
    n = normal_from_height(height, normal_strength)
    ao = ao_from_height(height) if ao is None else ao
    rough = np.broadcast_to(np.asarray(rough, np.float32), height.shape)
    orm = np.stack([ao, rough, height], -1)
    files = {}
    for suf, arr, ext in (('albedo', albedo, 'jpg'), ('normal', n, 'png'), ('orm', orm, 'jpg')):
        p = os.path.join(outdir, f'{name}_{suf}.{ext}'); im = _save(arr, p); files[suf] = p
        if lo: im.resize((im.width // 2, im.height // 2), Image.LANCZOS).save(os.path.join(outdir, f'{name}_{suf}_512.{ext}'), **({'quality': 85} if ext == 'jpg' else {}))
    rel = os.path.relpath(outdir, os.path.join(os.path.dirname(__file__), '..', '..', 'assets'))
    snippet = ',\n'.join(f"  {name}_{suf}: {{ file: '{rel}/{name}_{suf}.{ext}', lo: '{rel}/{name}_{suf}_512.{ext}'{', srgb: true' if suf == 'albedo' else ''} }}"
                         for suf, ext in (('albedo', 'jpg'), ('normal', 'png'), ('orm', 'jpg')))
    return snippet

def contact_sheet(paths, out, size=256):
    ims = [Image.open(p).convert('RGB').resize((size, size)) for p in paths]
    sheet = Image.new('RGB', (size * len(ims), size))
    for i, im in enumerate(ims): sheet.paste(im, (i * size, 0))
    sheet.save(out)

def tiled_preview(path, out, reps=2):
    im = Image.open(path).convert('RGB'); w, h = im.size
    sheet = Image.new('RGB', (w * reps, h * reps))
    for y in range(reps):
        for x in range(reps): sheet.paste(im, (x * w, y * h))
    sheet.save(out)
