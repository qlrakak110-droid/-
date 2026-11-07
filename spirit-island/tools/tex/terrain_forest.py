"""ground_forest — forest floor under the island's mixed pine/broadleaf woods (tile ~3 m).

Dark humus, a thick mat of fallen pine needles, layered broadleaf litter (oval leaves with a mid-rib, curled
edges, colours from fresh ochre to decayed umber), moss cushions in damp hollows, and a few twigs.
"""
import numpy as np
import terrain_common as C
from terrain_common import T

SS = 2; N = 1024; n = N * SS

hum = T.fbm(N, 5, 6, seed=61)
zbuf = (C.up(hum, n) * 0.18).astype(np.float32)
col = np.stack([C.up(c, n) for c in np.moveaxis(T.ramp(T.fbm(N, 9, 4, seed=62), [(0, '#1f1712'), (0.5, '#2c2018'), (1, '#3a2b1f')]), -1, 0)], -1)
col *= (1 + 0.15 * C.grain(n, 63))[..., None]
rough = np.full((n, n), 0.92, np.float32); occ = np.full((n, n), 0.6, np.float32)

moss = T.levels(C.up(T.fbm(256, 4, 5, seed=64), n), 0.56, 0.8)
leafy = T.levels(C.up(T.fbm(256, 3, 4, seed=65), n), 0.3, 0.7)        # broadleaf vs needle dominance


def place(count, mask, seed):
    r = C.rng(seed); xs = []; ys = []
    while sum(len(a) for a in xs) < count:
        x = r.random(count) * n; y = r.random(count) * n
        k = r.random(count) < mask[y.astype(int) % n, x.astype(int) % n]
        xs.append(x[k]); ys.append(y[k])
    return np.concatenate(xs)[:count], np.concatenate(ys)[:count]


z_layer = 0.18
# ---------------- needles: several thin layers (older/darker below, fresher on top)
needle_cols = [[(3, '#5a3b22'), (2, '#4a3220'), (1, '#6b4a2c')], [(3, '#7a4f2c'), (2, '#8a5a32'), (1, '#6b4426')], [(3, '#7c5636'), (2, '#8a6040'), (1, '#6b4a30')]]
for layer in range(3):
    cnt = 30000
    x, y = place(cnt, 0.35 + 0.65 * (1 - leafy), 70 + layer)
    P = C.strokes(n, cnt, C.rng(80 + layer), x=x, y=y, length=(22, 44), width=(1.3, 1.9), bend=0.08,
                  z0=(z_layer, z_layer + 0.05), z1=(z_layer + 0.02, z_layer + 0.08), taper=0.2)
    cols = C.palette(C.rng(90 + layer), cnt, needle_cols[layer], 0.08)
    c = cols[P['id']] * (0.8 + 0.25 * (1 - np.abs(P['across'])))[:, None]
    C.splat_points(n, P['iy'], P['ix'], P['z'], [c, np.full(len(c), 0.7 + 0.1 * layer, np.float32), np.full(len(c), 0.7, np.float32)], zbuf, [col, occ, rough])
    z_layer += 0.07

# ---------------- broadleaf litter
leaf_cols = [(3, '#5a4430'), (2.5, '#6b5034'), (2, '#4a3828'), (1.5, '#7a5a34'), (1, '#857048'), (1, '#3e3024'), (0.7, '#8a6236'), (0.5, '#6e6440')]
for layer in range(3):
    cnt = 750
    x, y = place(cnt, 0.1 + 0.9 * leafy, 100 + layer)
    P = C.blobs(n, cnt, C.rng(110 + layer), x=x, y=y, rad=(14, 25), aspect=(1.5, 1.9), z0=(z_layer, z_layer + 0.06), dome=0.05, curl=0.06)
    cols = C.palette(C.rng(120 + layer), cnt, leaf_cols, 0.1)
    u, v, rr = P['u'], P['v'], P['rr']
    tipcut = np.abs(v) < (1 - np.abs(u) ** 1.6) * 1.05                    # pointed leaf outline
    rib = np.exp(-(v * 14) ** 2) * 0.12 + np.exp(-((np.abs(v) - np.abs(u - 0.2) * 0.6) * 22) ** 2) * 0.05
    decay = C.rng(130 + layer).random(len(u)) < 0.0
    c = cols[P['id']] * (0.85 + 0.2 * (1 - rr))[:, None] + rib[:, None] * np.array([0.35, 0.28, 0.16], np.float32)
    c *= (0.85 + 0.15 * np.cos(u * 3.0))[:, None]
    k = tipcut
    C.splat_points(n, P['iy'][k], P['ix'][k], P['z'][k], [c[k], np.full(k.sum(), 0.85, np.float32), np.full(k.sum(), 0.62, np.float32)], zbuf, [col, occ, rough])
    z_layer += 0.06

# ---------------- moss cushions in damp hollows (painted over litter, fuzzy)
mfuzz = C.rng(140).random((n, n)).astype(np.float32)
mosscol = T.ramp(C.up(T.fbm(512, 24, 3, seed=141), n), [(0, '#34421c'), (0.5, '#4a5a24'), (1, '#64702e')])
mt = np.clip((moss * (0.55 + 0.45 * mfuzz) - 0.3) / 0.35, 0, 1)            # soft, fuzzy cushion edges
mk = mt > 0.02
col[mk] = col[mk] * (1 - mt[mk, None]) + mosscol[mk] * (0.75 + 0.35 * mfuzz[mk])[:, None] * mt[mk, None]
zbuf[mk] = np.maximum(zbuf[mk], (0.3 + 0.3 * moss[mk] + 0.05 * mfuzz[mk]) * mt[mk] + zbuf[mk] * (1 - mt[mk]))
rough[mk] = rough[mk] * (1 - mt[mk]) + 0.96 * mt[mk]; occ[mk] = occ[mk] * (1 - mt[mk]) + 0.9 * mt[mk]

# ---------------- twigs
P = C.strokes(n, 180, C.rng(150), length=(70, 220), width=(3, 6), bend=0.25, z0=(0.62, 0.66), z1=(0.62, 0.7), taper=0.35)
cols = C.palette(C.rng(151), 180, [(2, '#4a3a2c'), (1, '#5e4c3a'), (1, '#3a2c22'), (0.6, '#7a6a58')], 0.06)
c = cols[P['id']] * (0.7 + 0.4 * (1 - np.abs(P['across'])))[:, None]
C.splat_points(n, P['iy'], P['ix'], P['z'], [c, np.ones(len(c), np.float32), np.full(len(c), 0.78, np.float32)], zbuf, [col, occ, rough])

h = C.down(zbuf, SS); albedo = C.down(col, SS); ro = C.down(rough, SS); o = C.down(occ, SS)
cav = T.ao_from_height(h, radius=4, strength=1.6)
ao = np.clip(cav * (0.55 + 0.45 * o), 0, 1)
albedo *= (0.8 + 0.2 * ao)[..., None]
C.save_set('ground_forest', np.clip(albedo, 0, 1), T.blur(h, 1), ro, ao, normal_strength=8.0)
print(C.preview('ground_forest')); print(C.shade_preview('ground_forest'))
