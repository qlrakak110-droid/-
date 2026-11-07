"""terrain_common — shared helpers for the terrain workstream's ground PBR sets (ground_*.py).

Everything is tileable. Sets are rendered supersampled (SS x the output size) and box-filtered down so the
painted micro detail (blades, needles, grains) is anti-aliased, then written as
  <name>_albedo.jpg (sRGB)  <name>_normal.jpg (OpenGL +Y)  <name>_orm.jpg (R=AO G=rough B=height)
plus *_512 phone versions. Normals are JPEG 4:4:4 (q93) instead of PNG to stay inside the size budget.
"""
import os, sys, numpy as np
from PIL import Image, ImageFile
ImageFile.MAXBLOCK = 1 << 25      # optimize=True on big JPEGs needs a large encoder buffer
sys.path.insert(0, os.path.dirname(__file__))
import texlib as T

OUT = os.path.normpath(os.path.join(os.path.dirname(__file__), '..', '..', 'assets', 'tex', 'terrain'))


def rng(seed):
    return np.random.default_rng(seed)


def down(a, f):
    """box-filter downsample by integer factor f (works on (H,W) and (H,W,C))"""
    if f == 1: return a
    h, w = a.shape[:2]
    s = a.reshape(h // f, f, w // f, f, *a.shape[2:])
    return s.mean(axis=(1, 3)).astype(np.float32)


def up(a, n):
    """bilinear periodic resize of a tileable field to n x n"""
    m = a.shape[0]
    t = (np.arange(n, dtype=np.float32) + 0.5) * m / n - 0.5
    yy, xx = np.meshgrid(t, t, indexing='ij')
    return T.bilinear(a, yy % m, xx % m).astype(np.float32)


def splat_points(n, iy, ix, z, vals, zbuf, bufs):
    """z-buffered splat of points: where z > zbuf, write z and each vals[k] into bufs[k] (all periodic, (n,n[,C]))"""
    iy = iy % n; ix = ix % n
    lin = (iy * n + ix).astype(np.int64)
    order = np.argsort(z, kind='stable')
    lin_s = lin[order][::-1]
    u, first = np.unique(lin_s, return_index=True)      # first occurrence in reversed order = highest z
    src = order[::-1][first]
    zf = zbuf.reshape(-1)
    keep = z[src] > zf[u]
    u = u[keep]; src = src[keep]
    zf[u] = z[src]
    for b, v in zip(bufs, vals):
        bf = b.reshape(-1, *b.shape[2:]) if b.ndim == 3 else b.reshape(-1)
        bf[u] = v[src]


def strokes(n, count, r, *, x=None, y=None, ang=None, length=(10, 30), width=(1.5, 3.0), bend=0.0,
            z0=(0.2, 0.4), z1=(0.6, 1.0), taper=0.7):
    """sample points along `count` tapered strokes (blades, needles, twigs). returns dict of flat point arrays:
    iy, ix (int), z (height), t (0 base .. 1 tip), id (stroke index), across (-1..1 across the stroke)"""
    x = r.random(count) * n if x is None else x
    y = r.random(count) * n if y is None else y
    ang = r.random(count) * 2 * np.pi if ang is None else ang
    L = r.uniform(*length, count).astype(np.float32)
    Wd = r.uniform(*width, count).astype(np.float32)
    Z0 = r.uniform(*z0, count).astype(np.float32); Z1 = r.uniform(*z1, count).astype(np.float32)
    B = (r.random(count).astype(np.float32) - 0.5) * 2 * bend
    S = int(np.ceil(length[1] / 0.6)) + 1
    K = int(np.ceil(width[1])) * 2 + 1
    t = np.linspace(0, 1, S, dtype=np.float32)
    a = np.linspace(-1, 1, K, dtype=np.float32)
    dx, dy = np.cos(ang).astype(np.float32), np.sin(ang).astype(np.float32)
    # positions: base + t*L*dir + bend*t^2*L*perp + across*width/2*perp
    tt = t[None, :, None]; aa = a[None, None, :]
    Lc = L[:, None, None]; wc = (Wd[:, None, None] * 0.5) * (1 - taper * tt)
    px = x[:, None, None] + tt * Lc * dx[:, None, None] - (B[:, None, None] * tt * tt * Lc + aa * wc) * dy[:, None, None]
    py = y[:, None, None] + tt * Lc * dy[:, None, None] + (B[:, None, None] * tt * tt * Lc + aa * wc) * dx[:, None, None]
    # drop samples beyond the actual stroke length (S was sized for the longest)
    valid = np.broadcast_to(tt * length[1] <= Lc + 0.6, px.shape)
    # rounded cross-section: centre higher than the edges
    zc = (Z0[:, None, None] + (Z1 - Z0)[:, None, None] * tt) * (1 - 0.25 * aa * aa)
    ids = np.broadcast_to(np.arange(count)[:, None, None], px.shape)
    T_ = np.broadcast_to(tt, px.shape); A_ = np.broadcast_to(aa, px.shape)
    m = valid.reshape(-1)
    return {
        'iy': np.round(py).astype(np.int64).reshape(-1)[m], 'ix': np.round(px).astype(np.int64).reshape(-1)[m],
        'z': zc.reshape(-1)[m].astype(np.float32), 't': T_.reshape(-1)[m].astype(np.float32),
        'id': ids.reshape(-1)[m], 'across': A_.reshape(-1)[m].astype(np.float32),
    }


def blobs(n, count, r, *, x=None, y=None, rad=(3, 8), aspect=(1.0, 1.0), ang=None, z0=(0.3, 0.5), dome=0.3, curl=0.0):
    """filled ellipses (leaves, pebbles, shell bits). returns point dict like strokes(), plus 'rr' (0 centre..1 rim)"""
    x = r.random(count) * n if x is None else x
    y = r.random(count) * n if y is None else y
    ang = r.random(count) * 2 * np.pi if ang is None else ang
    R = r.uniform(*rad, count).astype(np.float32)
    A = r.uniform(*aspect, count).astype(np.float32)
    Z0 = r.uniform(*z0, count).astype(np.float32)
    K = int(np.ceil(rad[1] * max(aspect[1], 1.0))) * 2 + 1
    g = np.arange(K, dtype=np.float32) - K // 2
    gy, gx = np.meshgrid(g, g, indexing='ij')
    ca, sa = np.cos(ang)[:, None, None], np.sin(ang)[:, None, None]
    # local coords (u along the long axis)
    u = (gx[None] * ca + gy[None] * sa) / (R[:, None, None] * A[:, None, None])
    v = (-gx[None] * sa + gy[None] * ca) / R[:, None, None]
    rr = np.sqrt(u * u + v * v)
    inside = rr <= 1.0
    z = Z0[:, None, None] + dome * np.sqrt(np.clip(1 - rr * rr, 0, 1)) + curl * u * u
    iy = np.round(y[:, None, None] + gy[None]).astype(np.int64)
    ix = np.round(x[:, None, None] + gx[None]).astype(np.int64)
    ids = np.broadcast_to(np.arange(count)[:, None, None], u.shape)
    m = inside.reshape(-1)
    return {'iy': iy.reshape(-1)[m], 'ix': ix.reshape(-1)[m], 'z': z.reshape(-1)[m].astype(np.float32),
            'id': ids.reshape(-1)[m], 'rr': rr.reshape(-1)[m].astype(np.float32), 'u': u.reshape(-1)[m].astype(np.float32),
            'v': v.reshape(-1)[m].astype(np.float32)}


def palette(r, count, cols, jitter=0.06):
    """per-instance colour from a weighted list [(weight, '#hex'), ...] with small random jitter (sRGB float)"""
    w = np.array([c[0] for c in cols], np.float32); w /= w.sum()
    idx = r.choice(len(cols), count, p=w)
    base = np.stack([T.hexrgb(c[1]) for c in cols])[idx]
    base *= (1 + (r.random((count, 1)) - 0.5) * 2 * jitter).astype(np.float32)
    base += ((r.random((count, 3)) - 0.5) * jitter * 0.5).astype(np.float32)
    return np.clip(base, 0, 1).astype(np.float32)


def grain(n, seed, amp=1.0):
    """per-pixel white noise in [-1,1] (fine grit)"""
    return ((rng(seed).random((n, n)).astype(np.float32) - 0.5) * 2 * amp)


def save_set(name, albedo, height, rough, ao, normal_strength=4.0, normal=None, outdir=OUT, q=85, blend_h=None):
    """height -> normal map; ORM.b stores `blend_h` (default: a softened height) because the terrain shader uses it
    for height-based layer blending, where mid-scale structure matters and per-pixel noise only costs bytes"""
    os.makedirs(outdir, exist_ok=True)
    nrm = T.normal_from_height(height, normal_strength) if normal is None else normal
    rough = np.broadcast_to(np.asarray(rough, np.float32), height.shape)
    if blend_h is None: blend_h = T.norm01(0.65 * T.blur(height, 3) + 0.35 * height)
    orm = np.stack([T.blur(ao, 1), T.blur(rough, 1), blend_h], -1)
    out = {}
    for suf, arr, sub, qq in (('albedo', albedo, 2, q), ('normal', nrm, 0, 86), ('orm', orm, 0, 80)):
        a = np.clip(arr * 255 + 0.5, 0, 255).astype(np.uint8)
        im = Image.fromarray(a)
        p = os.path.join(outdir, f'{name}_{suf}.jpg')
        im.save(p, quality=qq, subsampling=sub, optimize=True)
        lo = im.resize((im.width // 2, im.height // 2), Image.LANCZOS)
        lo.save(os.path.join(outdir, f'{name}_{suf}_512.jpg'), quality=min(qq, 84), subsampling=sub, optimize=True)
        out[suf] = p
    return out


def preview(name, outdir=OUT, dest=None, reps=2, size=512):
    """contact sheet (albedo, normal, orm, albedo tiled reps x reps) for visual review"""
    dest = dest or os.path.join(os.environ.get('TEX_PREVIEW', os.getcwd()), f'_preview_{name}.jpg')
    ims = [Image.open(os.path.join(outdir, f'{name}_{s}.jpg')).convert('RGB') for s in ('albedo', 'normal', 'orm')]
    a = ims[0]; w, h = a.size
    tiled = Image.new('RGB', (w * reps, h * reps))
    for yy in range(reps):
        for xx in range(reps): tiled.paste(a, (xx * w, yy * h))
    row = [im.resize((size, size)) for im in ims] + [tiled.resize((size, size))]
    sheet = Image.new('RGB', (size * len(row), size))
    for i, im in enumerate(row): sheet.paste(im, (i * size, 0))
    sheet.save(dest, quality=88)
    return dest


def shade_preview(name, outdir=OUT, dest=None, size=768, sun=(-0.6, 0.5, 0.62)):
    """quick lit preview: albedo * (ambient + lambert with the normal map) * AO, to judge relief like the game will"""
    dest = dest or os.path.join(os.environ.get('TEX_PREVIEW', os.getcwd()), f'_lit_{name}.jpg')
    al = np.asarray(Image.open(os.path.join(outdir, f'{name}_albedo.jpg')).convert('RGB'), np.float32) / 255
    nm = np.asarray(Image.open(os.path.join(outdir, f'{name}_normal.jpg')).convert('RGB'), np.float32) / 255 * 2 - 1
    orm = np.asarray(Image.open(os.path.join(outdir, f'{name}_orm.jpg')).convert('RGB'), np.float32) / 255
    L = np.array(sun, np.float32); L /= np.linalg.norm(L)
    nd = np.clip((nm * L).sum(-1), 0, 1)
    lin = al ** 2.2
    c = lin * (0.35 * orm[..., :1] + 1.1 * nd[..., None])
    c = (c / (1 + c)) ** (1 / 2.2) * 1.25
    im = Image.fromarray(np.clip(c * 255, 0, 255).astype(np.uint8)).resize((size, size), Image.LANCZOS)
    im.save(dest, quality=88)
    return dest
