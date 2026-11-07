"""vegetation_common — a small numpy 'painter' for alpha-tested plant atlases (leaves, needles, petals, blades) and
helpers shared by the vegetation workstream's texture scripts.

Everything is painted supersampled (SS x) on a Canvas: colour (sRGB float), coverage alpha and a height field (for the
normal map). Each element is evaluated only inside its bounding box, composited front-to-back by paint order
(painter's algorithm), and casts a soft drop shadow onto what is already painted, so overlapping leaves read with depth.
"""
import os, sys, math
import numpy as np
from PIL import Image, ImageFile
ImageFile.MAXBLOCK = 1 << 25
sys.path.insert(0, os.path.dirname(__file__))
import texlib as T

OUT = os.path.normpath(os.path.join(os.path.dirname(__file__), '..', '..', 'assets', 'tex', 'vegetation'))


def rng(seed):
    return np.random.default_rng(seed)


def hexc(h):
    return T.hexrgb(h)


def down(a, f):
    if f == 1: return a
    h, w = a.shape[:2]
    return a.reshape(h // f, f, w // f, f, *a.shape[2:]).mean(axis=(1, 3)).astype(np.float32)


class Canvas:
    def __init__(self, W, H, ss=2, noise_seed=5):
        self.W, self.H, self.ss = W * ss, H * ss, ss
        self.rgb = np.zeros((self.H, self.W, 3), np.float32)
        self.a = np.zeros((self.H, self.W), np.float32)
        self.h = np.zeros((self.H, self.W), np.float32)
        self.tr = np.zeros((self.H, self.W), np.float32)     # translucency / thickness (1 thin leaf, 0 stem)
        # low-frequency blotch field used to vary colour across leaves
        n = 256
        self.blotch = T.fbm(n, 8, 4, seed=noise_seed)
        self.fine = T.fbm(n, 32, 3, seed=noise_seed + 7)

    def _sample(self, field, ys, xs):
        n = field.shape[0]
        return field[(ys * n // self.H) % n, (xs * n // self.W) % n]

    def _bbox(self, pts, pad):
        xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
        x0 = int(max(0, math.floor(min(xs) - pad))); x1 = int(min(self.W, math.ceil(max(xs) + pad)))
        y0 = int(max(0, math.floor(min(ys) - pad))); y1 = int(min(self.H, math.ceil(max(ys) + pad)))
        return x0, y0, x1, y1

    def composite(self, x0, y0, cov, col, hgt, tr=1.0, shadow=0.35, sh_off=(3, 5), clip=None):
        """paint cov (bbox array) with colour col (bbox,3) and height hgt (bbox) at (x0, y0); drop shadow first"""
        if cov.size == 0: return
        if clip is not None: cov = cov * clip
        hh, ww = cov.shape
        if shadow > 0:
            dx, dy = int(sh_off[0] * self.ss), int(sh_off[1] * self.ss)
            sh = np.zeros_like(cov)
            sh[dy:, dx:] = cov[:hh - dy, :ww - dx] if dy < hh and dx < ww else 0
            sh = T.blur(np.pad(sh, 4), 2)[4:-4, 4:-4] if min(hh, ww) > 12 else sh
            k = 1 - shadow * sh * self.a[y0:y0 + hh, x0:x0 + ww]
            self.rgb[y0:y0 + hh, x0:x0 + ww] *= k[..., None]
        c3 = cov[..., None]
        R = self.rgb[y0:y0 + hh, x0:x0 + ww]; R[:] = R * (1 - c3) + col * c3
        Hh = self.h[y0:y0 + hh, x0:x0 + ww]; Hh[:] = Hh * (1 - cov) + hgt * cov
        Tr = self.tr[y0:y0 + hh, x0:x0 + ww]; Tr[:] = Tr * (1 - cov) + tr * cov
        A = self.a[y0:y0 + hh, x0:x0 + ww]; A[:] = np.maximum(A, cov)

    # ------------------------------------------------------------------ primitives (coordinates in OUTPUT pixels)
    def stem(self, pts, w0, w1, col, z=0.2, shadow=0.25, dark=0.75, clip_rect=None):
        """tapered polyline stem / twig. pts: [(x, y), ...] in output pixels; widths in output pixels"""
        s = self.ss
        P = [(x * s, y * s) for x, y in pts]
        L = [0.0]
        for i in range(1, len(P)): L.append(L[-1] + math.hypot(P[i][0] - P[i - 1][0], P[i][1] - P[i - 1][1]))
        tot = max(L[-1], 1e-3)
        for i in range(len(P) - 1):
            (ax, ay), (bx, by) = P[i], P[i + 1]
            wa = (w0 + (w1 - w0) * L[i] / tot) * s * 0.5; wb = (w0 + (w1 - w0) * L[i + 1] / tot) * s * 0.5
            x0, y0, x1, y1 = self._bbox([(ax, ay), (bx, by)], max(wa, wb) + 2)
            if clip_rect is not None:
                cx0, cy0, cx1, cy1 = [v * s for v in clip_rect]
                x0, y0, x1, y1 = max(x0, cx0), max(y0, cy0), min(x1, cx1), min(y1, cy1)
            if x1 <= x0 or y1 <= y0: continue
            yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32) + 0.5
            vx, vy = bx - ax, by - ay; ll = vx * vx + vy * vy + 1e-6
            t = np.clip(((xx - ax) * vx + (yy - ay) * vy) / ll, 0, 1)
            dx, dy = xx - (ax + vx * t), yy - (ay + vy * t)
            d = np.sqrt(dx * dx + dy * dy); w = wa + (wb - wa) * t
            cov = np.clip(w - d + 0.5, 0, 1)
            across = np.clip(d / np.maximum(w, 0.5), 0, 1)
            shade = (1 - 0.35 * across ** 2) * (dark + (1 - dark) * (1 - across))
            colv = np.asarray(col, np.float32)[None, None, :] * shade[..., None]
            hgt = z + 0.25 * np.sqrt(np.clip(1 - across ** 2, 0, 1))
            self.composite(x0, y0, cov, colv, hgt, tr=0.15, shadow=shadow)

    def leaf(self, bx, by, ang, L, Wd, col, *, shape='ovate', serr=0.0, teeth=14, z=0.3, veins=7, vein_amt=0.08,
             mid_col=None, edge_col=None, curl=0.0, shadow=0.35, petiole=0.0, pet_col=None, blotch=0.12, gloss=0.0,
             tip_light=0.08, clip_rect=None, tr=1.0):
        """one leaf from base (bx, by) pointing along ang (radians, image space: 0 = +x, pi/2 = down)."""
        s = self.ss
        if petiole > 0:
            ex, ey = bx + math.cos(ang) * petiole, by + math.sin(ang) * petiole
            self.stem([(bx, by), (ex, ey)], max(0.9, Wd * 0.07), max(0.7, Wd * 0.05), pet_col if pet_col is not None else col * 0.8, z=z - 0.05, shadow=0.15, clip_rect=clip_rect)
            bx, by = ex, ey
        bx *= s; by *= s; L *= s; Wd *= s
        dx, dy = math.cos(ang), math.sin(ang)
        hw = Wd * 0.5
        corners = [(bx - dy * hw, by + dx * hw), (bx + dy * hw, by - dx * hw), (bx + dx * L - dy * hw, by + dy * L + dx * hw), (bx + dx * L + dy * hw, by + dy * L - dx * hw)]
        x0, y0, x1, y1 = self._bbox(corners, 3)
        if clip_rect is not None:
            cx0, cy0, cx1, cy1 = [v * s for v in clip_rect]
            x0, y0, x1, y1 = max(x0, cx0), max(y0, cy0), min(x1, cx1), min(y1, cy1)
        if x1 <= x0 or y1 <= y0: return
        yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32) + 0.5
        px, py = xx - bx, yy - by
        u = (px * dx + py * dy) / L
        vp = (-px * dy + py * dx)                       # signed across distance in px
        uc = np.clip(u, 0, 1)
        if shape == 'ovate':        # rounded base, pointed tip
            prof = (uc ** 0.55) * (1 - uc) ** 0.85; prof /= (0.393 ** 0.55) * (0.607 ** 0.85)
        elif shape == 'elliptic':
            prof = np.sqrt(np.clip(4 * uc * (1 - uc), 0, 1)) * (1 - 0.25 * uc ** 3)
        elif shape == 'lance':
            prof = (uc ** 0.45) * (1 - uc) ** 1.1; prof /= (0.29 ** 0.45) * (0.71 ** 1.1)
        elif shape == 'deltoid':   # birch: broad near the base, long point
            prof = (uc ** 0.35) * (1 - uc) ** 1.25; prof /= (0.219 ** 0.35) * (0.781 ** 1.25)
        elif shape == 'petal':
            prof = np.sqrt(np.clip(uc, 0, 1)) * (1 - uc ** 4) * 1.15
            prof *= 1 - 0.35 * np.exp(-((uc - 1.0) / 0.08) ** 2) * np.exp(-(vp / (hw * 0.25)) ** 2)  # notch
        elif shape == 'blade':
            prof = (1 - uc) ** 0.9 * np.clip(uc * 8, 0, 1)
        else:
            prof = np.sqrt(np.clip(4 * uc * (1 - uc), 0, 1))
        if serr > 0:
            saw = (uc * teeth) % 1.0
            prof = prof * (1 - serr * saw * np.clip(uc * 3, 0, 1) * np.clip((1 - uc) * 5, 0, 1))
        w = prof * hw
        edge = w - np.abs(vp)                               # px inside the outline
        cov = np.clip(edge + 0.5, 0, 1) * np.clip(np.minimum(u * L, (1 - u) * L) + 0.5, 0, 1)
        if not cov.any(): return
        vv = np.clip(np.abs(vp) / np.maximum(w, 1e-3), 0, 1)
        # colour
        base = np.asarray(col, np.float32)
        bl = self._sample(self.blotch, yy.astype(int), xx.astype(int)); fi = self._sample(self.fine, yy.astype(int), xx.astype(int))
        k = (1 - blotch) + blotch * 2 * bl
        c = base[None, None, :] * k[..., None] * (0.94 + 0.12 * fi[..., None])
        mid = np.exp(-(vp / max(1.2 * s, Wd * 0.035)) ** 2) * np.clip(u * 1.2, 0, 1) * (1 - uc ** 3)
        mc = np.asarray(mid_col if mid_col is not None else base * 1.25 + 0.04, np.float32)
        c = c * (1 - 0.6 * mid[..., None]) + mc * 0.6 * mid[..., None]
        if veins > 0:
            sv = uc - 0.45 * vv * prof.clip(0.2, 1)
            vein = np.exp(-(((sv * veins) % 1.0 - 0.5) / 0.07) ** 2) * (vv > 0.08) * (vv < 0.9)
            c = c * (1 + vein_amt * vein[..., None])
        else:
            vein = 0
        if edge_col is not None:
            e = np.clip((vv - 0.7) / 0.3, 0, 1) ** 2
            c = c * (1 - 0.5 * e[..., None]) + np.asarray(edge_col, np.float32) * 0.5 * e[..., None]
        c = c * (1 + tip_light * uc[..., None]) * (1 - 0.18 * vv[..., None] ** 2)
        if gloss > 0:
            c = c + gloss * np.exp(-((vv - 0.35) / 0.25) ** 2)[..., None] * (1 - uc[..., None])
        hgt = z + 0.35 * np.sqrt(np.clip(1 - vv * vv, 0, 1)) - 0.18 * mid - 0.06 * vein + curl * (uc - 0.5) ** 2
        self.composite(x0, y0, cov, np.clip(c, 0, 1), hgt, tr=tr, shadow=shadow)

    def disc(self, cx, cy, r, col, z=0.5, shadow=0.2, dome=0.3, rim_dark=0.3, tr=0.6):
        s = self.ss; cx *= s; cy *= s; r *= s
        x0, y0, x1, y1 = self._bbox([(cx - r, cy - r), (cx + r, cy + r)], 2)
        if x1 <= x0 or y1 <= y0: return
        yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32) + 0.5
        d = np.hypot(xx - cx, yy - cy)
        cov = np.clip(r - d + 0.5, 0, 1)
        rr = np.clip(d / r, 0, 1)
        fi = self._sample(self.fine, yy.astype(int) * 3, xx.astype(int) * 3)
        c = np.asarray(col, np.float32)[None, None, :] * ((1 - rim_dark * rr ** 2) * (0.85 + 0.3 * fi))[..., None]
        hgt = z + dome * np.sqrt(np.clip(1 - rr * rr, 0, 1))
        self.composite(x0, y0, cov, c, hgt, tr=tr, shadow=shadow)

    # ------------------------------------------------------------------ output
    def finish(self, bleed=True):
        """downsample, bleed colour into transparent texels (no dark fringes in mips); returns rgb, alpha, height, tr"""
        s = self.ss
        rgb = down(self.rgb * self.a[..., None], s); a = down(self.a, s); h = down(self.h * self.a, s); tr = down(self.tr * self.a, s)
        nz = np.maximum(a, 1e-4)
        rgb = rgb / nz[..., None]; h = h / nz; tr = tr / nz
        if bleed:
            fill = rgb.copy(); filled = a > 0.02
            for r in (2, 6, 16, 40):
                num = T.blur(rgb * (a[..., None] > 0.02), r); den = T.blur((a > 0.02).astype(np.float32), r)
                ok = (~filled) & (den > 1e-3)
                fill[ok] = num[ok] / den[ok][..., None]; filled = filled | ok
            rgb = np.where((a > 0.02)[..., None], rgb, fill)
        h = h * np.clip(a * 1.5, 0, 1)
        return np.clip(rgb, 0, 1), np.clip(a, 0, 1), h, tr


def save_atlas(name, rgb, alpha, height, normal_strength=3.0, outdir=OUT, extra=None, q=90):
    """writes <name>_albedo.jpg (sRGB), <name>_alpha.jpg (L), <name>_normal.jpg (+ _512 versions)"""
    os.makedirs(outdir, exist_ok=True)
    nrm = T.normal_from_height(T.blur(height, 1), normal_strength)
    files = []
    maps = [('albedo', rgb, q, 0), ('alpha', alpha, 92, 0), ('normal', nrm, 88, 0)] + (extra or [])
    for suf, arr, qq, sub in maps:
        a8 = np.clip(arr * 255 + 0.5, 0, 255).astype(np.uint8)
        im = Image.fromarray(a8, 'L' if a8.ndim == 2 else 'RGB')
        p = os.path.join(outdir, f'{name}_{suf}.jpg'); im.save(p, quality=qq, subsampling=sub, optimize=True)
        lo = im.resize((im.width // 2, im.height // 2), Image.LANCZOS)
        lo.save(os.path.join(outdir, f'{name}_{suf}_512.jpg'), quality=min(qq, 86), subsampling=sub, optimize=True)
        files.append(p)
    return files


def preview_atlas(name, outdir=OUT, dest=None, bg=(0.55, 0.62, 0.72)):
    """composite the atlas over a flat sky colour + its normal map, side by side, for review"""
    al = np.asarray(Image.open(os.path.join(outdir, f'{name}_albedo.jpg')).convert('RGB'), np.float32) / 255
    a = np.asarray(Image.open(os.path.join(outdir, f'{name}_alpha.jpg')).convert('L'), np.float32) / 255
    nm = np.asarray(Image.open(os.path.join(outdir, f'{name}_normal.jpg')).convert('RGB'), np.float32) / 255
    cut = (a > 0.5)[..., None]
    comp = np.where(cut, al, np.array(bg, np.float32))
    L = np.array([-0.5, 0.5, 0.7]); L /= np.linalg.norm(L)
    lit = np.clip(((nm * 2 - 1) * L).sum(-1), 0, 1)[..., None]
    shaded = np.where(cut, al * (0.45 + 0.75 * lit), np.array(bg, np.float32))
    sheet = np.concatenate([comp, shaded], 1)
    dest = dest or os.path.join(os.environ.get('TEX_PREVIEW', os.getcwd()), f'_preview_{name}.jpg')
    Image.fromarray(np.clip(sheet * 255, 0, 255).astype(np.uint8)).save(dest, quality=88)
    return dest


# ---------------------------------------------------------------------------------------------------------------------
#  anisotropic tileable noise + PBR saving with JPEG normals (bark, rock)
# ---------------------------------------------------------------------------------------------------------------------
def aperlin(H, Wd, py, px, seed=0):
    """periodic gradient noise with separate lattice periods along y (py cells) and x (px cells); output (H, Wd) in [0,1]"""
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
        out += amp * aperlin(H, Wd, py, px, seed + o * 101); tot += amp; amp *= gain; py *= 2; px *= 2
        if px > Wd // 2 or py > H // 2: break
    return out / tot


def aworley(H, Wd, py, px, seed=0, jitter=0.9, sy=1.0, sx=1.0):
    """periodic cellular noise on a (py, px) grid; distances measured with axis scales (sy, sx) in CELL units.
    returns F1, F2 (in cell units) and the id (0..1 random per cell) of the nearest cell"""
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


def wrap_blur(a, r):
    return T.blur(a, r)


def save_pbr_jpg(name, albedo, height, rough, ao, outdir=OUT, normal_strength=4.0, lo_div=2, q=88, nrm=None):
    """<name>_albedo.jpg (sRGB) <name>_normal.jpg <name>_orm.jpg (R=AO G=rough B=height) + _512 (1/lo_div size)"""
    os.makedirs(outdir, exist_ok=True)
    n = T.normal_from_height(height, normal_strength) if nrm is None else nrm
    rough = np.broadcast_to(np.asarray(rough, np.float32), height.shape)
    orm = np.stack([ao, rough, height], -1)
    out = []
    for suf, arr, qq in (('albedo', albedo, q), ('normal', n, q), ('orm', orm, q - 4)):
        a8 = np.clip(arr * 255 + 0.5, 0, 255).astype(np.uint8)
        im = Image.fromarray(a8)
        p = os.path.join(outdir, f'{name}_{suf}.jpg'); im.save(p, quality=qq, subsampling=0, optimize=True)
        im.resize((im.width // lo_div, im.height // lo_div), Image.LANCZOS).save(os.path.join(outdir, f'{name}_{suf}_512.jpg'), quality=min(qq, 85), subsampling=0, optimize=True)
        out.append(p)
    return out


def lit_preview(name, outdir=OUT, dest=None, reps=2):
    """albedo tiled reps x reps, lit by its normal map from the upper left, next to the plain albedo"""
    al = np.asarray(Image.open(os.path.join(outdir, f'{name}_albedo.jpg')).convert('RGB'), np.float32) / 255
    nm = np.asarray(Image.open(os.path.join(outdir, f'{name}_normal.jpg')).convert('RGB'), np.float32) / 255
    orm = np.asarray(Image.open(os.path.join(outdir, f'{name}_orm.jpg')).convert('RGB'), np.float32) / 255
    L = np.array([-0.55, 0.55, 0.62]); L /= np.linalg.norm(L)
    lit = np.clip(((nm * 2 - 1) * L).sum(-1), 0, 1)[..., None]
    sh = al * (0.25 + 0.95 * lit) * (0.5 + 0.5 * orm[..., :1])
    tile = lambda a: np.tile(a, (reps, reps, 1))
    sheet = np.concatenate([tile(sh), tile(al)], 1)
    dest = dest or os.path.join(os.environ.get('TEX_PREVIEW', os.getcwd()), f'_preview_{name}.jpg')
    im = Image.fromarray(np.clip(sheet * 255, 0, 255).astype(np.uint8))
    if im.width > 2048: im = im.resize((2048, int(im.height * 2048 / im.width)), Image.LANCZOS)
    im.save(dest, quality=88)
    return dest
