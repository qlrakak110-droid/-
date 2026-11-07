"""architecture_common — helpers for the village (architecture) PBR sets (architecture_textures.py).

Anisotropic periodic noise (grain, trowel marks), anisotropic cellular noise (stones, cobbles), JPEG PBR writer
(normals as JPEG 4:4:4 to stay inside the size budget) and a lit preview sheet for checking results by eye.
Output: assets/tex/architecture/<name>_{albedo,normal,orm}.jpg (+ _512 phone versions; ORM = R ao, G rough, B height)
"""
import os, sys
import numpy as np
from PIL import Image, ImageFile
ImageFile.MAXBLOCK = 1 << 25
sys.path.insert(0, os.path.dirname(__file__))
import texlib as T

OUT = os.path.normpath(os.path.join(os.path.dirname(__file__), '..', '..', 'assets', 'tex', 'architecture'))


def aperlin(H, Wd, py, px, seed=0):
    """periodic gradient noise with separate lattice periods along y (py cells) and x (px cells), in [0,1]"""
    r = np.random.default_rng(seed); ang = r.random((py, px)) * 2 * np.pi
    gx, gy = np.cos(ang).astype(np.float32), np.sin(ang).astype(np.float32)
    ty = np.arange(H, dtype=np.float32) * py / H; tx = np.arange(Wd, dtype=np.float32) * px / Wd
    iy0 = np.floor(ty).astype(int); fy = (ty - iy0)[:, None]; iy1 = (iy0 + 1) % py; iy0 %= py
    ix0 = np.floor(tx).astype(int); fx = (tx - ix0)[None, :]; ix1 = (ix0 + 1) % px; ix0 %= px
    def dot(iy, ix, oy, ox): return gx[np.ix_(iy, ix)] * ox + gy[np.ix_(iy, ix)] * oy
    n00 = dot(iy0, ix0, fy, fx); n01 = dot(iy0, ix1, fy, fx - 1); n10 = dot(iy1, ix0, fy - 1, fx); n11 = dot(iy1, ix1, fy - 1, fx - 1)
    sx = fx * fx * fx * (fx * (fx * 6 - 15) + 10); sy = fy * fy * fy * (fy * (fy * 6 - 15) + 10)
    v = (n00 * (1 - sx) + n01 * sx) * (1 - sy) + (n10 * (1 - sx) + n11 * sx) * sy
    return np.clip(v * 0.7071 + 0.5, 0, 1).astype(np.float32)


def afbm(H, Wd, py, px, octaves=5, seed=0, gain=0.5):
    out = np.zeros((H, Wd), np.float32); amp = 1.0; tot = 0.0
    for o in range(octaves):
        out += amp * aperlin(H, Wd, int(py), int(px), seed + o * 101); tot += amp; amp *= gain; py *= 2; px *= 2
        if px > Wd // 2 or py > H // 2: break
    return out / tot


def aworley(H, Wd, py, px, seed=0, jitter=0.9, sy=1.0, sx=1.0):
    """periodic cellular noise on a (py, px) grid; distances measured with axis scales (sy, sx) in cell units.
    returns F1, F2 and the id (0..1 random per cell) of the nearest cell"""
    r = np.random.default_rng(seed)
    pts = r.random((py, px, 2)) * jitter + (1 - jitter) * 0.5
    ids = r.random((py, px)).astype(np.float32)
    ty = (np.arange(H, dtype=np.float32) + 0.5) * py / H; tx = (np.arange(Wd, dtype=np.float32) + 0.5) * px / Wd
    cy = np.floor(ty).astype(int); cx = np.floor(tx).astype(int)
    F1 = np.full((H, Wd), 1e9, np.float32); F2 = np.full((H, Wd), 1e9, np.float32); ID = np.zeros((H, Wd), np.float32)
    ry = int(np.ceil(1.0 / min(sy, 1.0))) + 1; rx = int(np.ceil(1.0 / min(sx, 1.0))) + 1
    for oy in range(-ry, ry + 1):
        for ox in range(-rx, rx + 1):
            gy_ = cy + oy; gx_ = cx + ox
            p = pts[np.ix_(gy_ % py, gx_ % px)]
            dy = (gy_[:, None] + p[..., 0] - ty[:, None]) * sy; dx = (gx_[None, :] + p[..., 1] - tx[None, :]) * sx
            d = np.sqrt(dx * dx + dy * dy)
            idv = ids[np.ix_(gy_ % py, gx_ % px)]
            closer = d < F1
            F2 = np.where(closer, F1, np.minimum(F2, d)); ID = np.where(closer, idv, ID); F1 = np.where(closer, d, F1)
    return F1, F2, ID


def stretch_y(img, k):
    """periodic vertical squeeze by an integer factor (features k times shorter along y), stays tileable"""
    n = img.shape[0]
    idx = (np.arange(n) * k) % n
    return img[idx]


def col(h):
    return T.hexrgb(h)


def save(name, albedo, height, rough, ao, normal_strength=4.0, q=88, lo_div=2, outdir=OUT, nrm=None):
    """<name>_albedo.jpg (sRGB) <name>_normal.jpg <name>_orm.jpg (R=AO G=rough B=height) + _512 (1/lo_div size)"""
    os.makedirs(outdir, exist_ok=True)
    n = T.normal_from_height(height, normal_strength) if nrm is None else nrm
    rough = np.broadcast_to(np.asarray(rough, np.float32), height.shape)
    orm = np.stack([ao, rough, height], -1)
    out = []
    for suf, arr, qq in (('albedo', albedo, q), ('normal', n, q + 2), ('orm', orm, q - 4)):
        a8 = np.clip(arr * 255 + 0.5, 0, 255).astype(np.uint8)
        im = Image.fromarray(a8)
        p = os.path.join(outdir, f'{name}_{suf}.jpg'); im.save(p, quality=qq, subsampling=0, optimize=True)
        im.resize((im.width // lo_div, im.height // lo_div), Image.LANCZOS).save(os.path.join(outdir, f'{name}_{suf}_512.jpg'), quality=min(qq, 85), subsampling=0, optimize=True)
        out.append(p)
    return out


def preview(name, dest, outdir=OUT, reps=2, tint=(1, 1, 1)):
    """albedo (tinted) tiled reps x reps, lit by its normal map from the upper left, next to the plain albedo and roughness"""
    al = np.asarray(Image.open(os.path.join(outdir, f'{name}_albedo.jpg')).convert('RGB'), np.float32) / 255 * np.array(tint, np.float32)
    nm = np.asarray(Image.open(os.path.join(outdir, f'{name}_normal.jpg')).convert('RGB'), np.float32) / 255
    orm = np.asarray(Image.open(os.path.join(outdir, f'{name}_orm.jpg')).convert('RGB'), np.float32) / 255
    L = np.array([-0.55, 0.55, 0.62]); L /= np.linalg.norm(L)
    nn = nm * 2 - 1
    lit = np.clip((nn * L).sum(-1), 0, 1)[..., None]
    Hh = L + np.array([0, 0, 1.0]); Hh /= np.linalg.norm(Hh)
    spec = (np.clip((nn * Hh).sum(-1), 0, 1) ** (2 + 60 * (1 - orm[..., 1]) ** 2))[..., None] * (1 - orm[..., 1:2]) * 0.5
    sh = al * (0.22 + 0.95 * lit) * (0.45 + 0.55 * orm[..., :1]) + spec
    tile = lambda a: np.tile(a, (reps, reps, 1))
    rgh = np.repeat(orm[..., 1:2], 3, -1)
    sheet = np.concatenate([tile(sh), tile(al), tile(rgh)], 1)
    im = Image.fromarray(np.clip(sheet * 255, 0, 255).astype(np.uint8))
    if im.width > 2400: im = im.resize((2400, int(im.height * 2400 / im.width)), Image.LANCZOS)
    im.save(dest, quality=88)
    return dest


def stamp_stones(n, stones, seed=0, rough_edge=0.12, profile=0.55):
    """z-buffered, periodic stamping of rounded stones (superellipses with ragged outlines and domed faces).
    stones: iterable of (cy, cx, ry, rx, rot, p) in pixels / radians (p = superellipse exponent, 2 = ellipse).
    returns height (0 outside stones), id (0..1 per stone), inside mask (0..1 soft), edge (0 at rim .. 1 centre)"""
    import math
    H = np.zeros((n, n), np.float32); ID = np.zeros((n, n), np.float32); M = np.zeros((n, n), np.float32); EDGE = np.zeros((n, n), np.float32)
    jag = T.fbm(n, 24, 3, seed=seed + 7)
    r = np.random.default_rng(seed)
    for (cy, cx, ry, rx, rot, p) in stones:
        R = int(max(rx, ry) * 1.25) + 2
        ys = np.arange(int(cy) - R, int(cy) + R + 1); xs = np.arange(int(cx) - R, int(cx) + R + 1)
        Y, X = np.meshgrid(ys, xs, indexing='ij')
        dy = Y - cy; dx = X - cx
        c, s = math.cos(rot), math.sin(rot)
        u = (dx * c + dy * s) / rx; v = (-dx * s + dy * c) / ry
        d = (np.abs(u) ** p + np.abs(v) ** p) ** (1.0 / p)
        yi = ys % n; xi = xs % n
        d = d * (1 + rough_edge * (jag[np.ix_(yi, xi)] - 0.5) * 2)
        inside = np.clip((1 - d) * 18, 0, 1)
        e = np.clip(1 - d, 0, 1)
        h = (e ** profile) * (0.75 + 0.25 * r.random()) * inside
        sub = H[np.ix_(yi, xi)]
        win = h > sub
        idv = r.random()
        H[np.ix_(yi, xi)] = np.where(win, h, sub)
        ID[np.ix_(yi, xi)] = np.where(win & (inside > 0.01), idv, ID[np.ix_(yi, xi)])
        M[np.ix_(yi, xi)] = np.maximum(M[np.ix_(yi, xi)], inside)
        EDGE[np.ix_(yi, xi)] = np.where(win, e, EDGE[np.ix_(yi, xi)])
    return H, ID, M, EDGE
