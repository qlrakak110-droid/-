# edlib SDF sculpting: anatomical masses as signed-distance primitives authored in bone frames, combined with smooth
# unions (polynomial smooth-min) so muscles flow into each other with real fillets instead of the creased seams of a
# hard boolean / voxel union. Meshing: a hard-union start mesh of the same primitives is voxel-remeshed, then every
# vertex is projected onto the smooth zero level set (Newton steps along the numerical gradient), remeshed again for an
# even triangle size and projected once more. No marching cubes needed (no scipy / skimage in the Blender venv).
#
#   S = SDF(rig)
#   S.group('torso', k=0.035)
#   S.ell('torso', 'chest', [0, 0.1, 0], [0.11, 0.17, 0.15])          # ellipsoid: centre + radii in the bone's game frame
#   S.cone('torso', 'neck', [0, 0, 0], [0, 0.1, 0], 0.06, 0.05)       # round cone a -> b, radii ra -> rb (squash optional)
#   S.cut('head', 'head', 'ell', ..., k=0.01)                          # smooth subtraction
#   obj = S.mesh('body', voxel=0.006)
#
# Groups are combined in insertion order: each group's own k blends its members; S.blend(g1, g2, k) sets the fillet
# between two groups (default: the smaller of the two group k).

import math
import numpy as np
from .core import new_mesh, verts_of, set_verts, join, add_mod, apply_mods, recalc_normals, collection, delete, log, normalize
from .model import ellipsoid as _ellipsoid_mesh, capsule as _capsule_mesh


def smin(a, b, k):
    """Polynomial smooth minimum (fillet radius ~k)."""
    if k <= 0:
        return np.minimum(a, b)
    h = np.maximum(k - np.abs(a - b), 0.0) / k
    return np.minimum(a, b) - h * h * k * 0.25


def smax(a, b, k):
    return -smin(-a, -b, k)


def sd_ellipsoid(q, r):
    """Approximate (iq) ellipsoid distance; exact on the surface, good near it."""
    r = np.asarray(r, dtype=np.float64)
    k0 = np.linalg.norm(q / r, axis=1)
    k1 = np.linalg.norm(q / (r * r), axis=1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


def sd_round_cone(q, a, b, r1, r2):
    """Exact distance to a round cone (sphere r1 at a swept to sphere r2 at b)."""
    a = np.asarray(a, dtype=np.float64); b = np.asarray(b, dtype=np.float64)
    ba = b - a
    l2 = float(ba @ ba)
    rr = r1 - r2
    a2 = l2 - rr * rr
    il2 = 1.0 / max(l2, 1e-12)
    pa = q - a
    y = pa @ ba
    z = y - l2
    xv = pa * l2 - y[:, None] * ba[None, :]
    x2 = np.einsum('ij,ij->i', xv, xv)
    y2 = y * y * l2
    z2 = z * z * l2
    k = np.sign(rr) * rr * rr * x2
    out = np.empty(len(q))
    m1 = np.sign(z) * a2 * z2 > k
    m2 = (np.sign(y) * a2 * y2 < k) & ~m1
    m3 = ~(m1 | m2)
    out[m1] = np.sqrt(x2[m1] + z2[m1]) * il2 - r2
    out[m2] = np.sqrt(x2[m2] + y2[m2]) * il2 - r1
    out[m3] = (np.sqrt(x2[m3] * a2 * il2) + y[m3] * rr) * il2 - r1
    return out


class SDF:
    def __init__(self, rig):
        self.rig = rig
        self.groups = {}          # name -> {'k': k, 'prims': [...], 'cuts': [...]}
        self.order = []
        self.blends = {}
        self._loc = {}
        self.offset = 0.0

    # ---- authoring ---------------------------------------------------------------------------------------------------------
    def group(self, name, k=0.03):
        if name not in self.groups:
            self.groups[name] = {'k': float(k), 'prims': [], 'cuts': []}
            self.order.append(name)
        return self

    def blend(self, g1, g2, k):
        self.blends[(g1, g2)] = self.blends[(g2, g1)] = float(k)
        return self

    def ell(self, g, bone, c, r, rot=None, k=None):
        """Ellipsoid in `bone`'s game frame. rot: optional 3x3 (columns = the ellipsoid axes in the bone frame)."""
        self.groups[g]['prims'].append(('ell', bone, np.asarray(c, float), np.asarray(r, float), None if rot is None else np.asarray(rot, float), k))
        return self

    def cone(self, g, bone, a, b, ra, rb=None, squash=None, k=None):
        """Round cone a -> b (bone frame), radii ra -> rb. squash (sx, sy, sz): anisotropic scale of the cross-section."""
        rb = ra if rb is None else rb
        self.groups[g]['prims'].append(('cone', bone, np.asarray(a, float), np.asarray(b, float), (float(ra), float(rb)),
                                        None if squash is None else np.asarray(squash, float), k))
        return self

    def chain(self, g, bone, stations, squash=None, k=None):
        """Round cones through stations [(y, r) or (x, y, z, r)] down a bone (y negative = toward the bone's child)."""
        pts = []
        for s in stations:
            if len(s) == 2:
                pts.append((np.array([0.0, s[0], 0.0]), s[1]))
            else:
                pts.append((np.array(s[:3], float), s[3]))
        for (a, ra), (b, rb) in zip(pts[:-1], pts[1:]):
            self.cone(g, bone, a, b, ra, rb, squash, k)
        return self

    def cut(self, g, bone, kind, *args, k=0.008):
        """Smooth subtraction (eye sockets, furrows): kind 'ell' (c, r) or 'cone' (a, b, ra, rb)."""
        self.groups[g]['cuts'].append((kind, bone, args, float(k)))
        return self

    def subset(self, names, offset=0.0):
        """A view of some groups only (e.g. ['torso', 'neck'] for a garment that must not bridge to the arms); offset
        grows the surface by that many metres (a padded body for layering)."""
        out = SDF(self.rig)
        out.order = [g for g in self.order if g in names]
        out.groups = {g: self.groups[g] for g in out.order}
        out.blends = self.blends
        out.offset = offset
        return out

    # ---- evaluation ----------------------------------------------------------------------------------------------------------
    def _local(self, bone, P):
        m = self.rig.Minv[bone]
        return P @ m[:3, :3].T + m[:3, 3]

    def _prim(self, p, Q):
        kind = p[0]
        if kind == 'ell':
            _, bone, c, r, rot, _k = p
            q = Q[bone] - c
            if rot is not None:
                q = q @ rot
            return sd_ellipsoid(q, r)
        _, bone, a, b, (ra, rb), sq, _k = p
        q = Q[bone]
        if sq is None:
            return sd_round_cone(q, a, b, ra, rb)
        # anisotropic: scale space around the segment's axis frame (bone frame axes)
        s = sq
        return sd_round_cone(q / s, a / s, b / s, ra, rb) * float(s.min())

    def eval(self, P):
        P = np.asarray(P, dtype=np.float64)
        bones = set()
        for g in self.order:
            for p in self.groups[g]['prims']:
                bones.add(p[1])
            for c in self.groups[g]['cuts']:
                bones.add(c[1])
        Q = {b: self._local(b, P) for b in bones}
        total = None
        totk = None
        names = []
        for g in self.order:
            G = self.groups[g]
            d = None
            for p in G['prims']:
                dp = self._prim(p, Q)
                kk = G['k'] if p[-1] is None else p[-1]
                d = dp if d is None else smin(d, dp, kk)
            if d is None:
                continue
            for kind, bone, args, kc in G['cuts']:
                q = Q[bone]
                if kind == 'ell':
                    dc = sd_ellipsoid(q - np.asarray(args[0], float), np.asarray(args[1], float))
                else:
                    dc = sd_round_cone(q, np.asarray(args[0], float), np.asarray(args[1], float), args[2], args[3])
                d = smax(d, -dc, kc)
            if total is None:
                total = d
            else:
                ks = [self.blends.get((g, h), min(G['k'], self.groups[h]['k'])) for h in names]
                total = smin(total, d, max(ks) if ks else G['k'])
            names.append(g)
        return total - self.offset

    def grad(self, P, eps=6e-4):
        g = np.zeros_like(P)
        for i in range(3):
            e = np.zeros(3); e[i] = eps
            g[:, i] = (self.eval(P + e) - self.eval(P - e)) / (2 * eps)
        return g

    def project(self, obj, iters=6, step=1.0):
        """Move the mesh vertices onto the zero level set."""
        P = verts_of(obj)
        for it in range(iters):
            d = self.eval(P)
            g = self.grad(P)
            gg = np.maximum(np.einsum('ij,ij->i', g, g), 1e-6)
            mv = (d / gg)[:, None] * g * step
            # clamp huge moves (start mesh far from the surface in a deep fillet)
            L = np.linalg.norm(mv, axis=1)
            mv *= np.minimum(1.0, 0.02 / np.maximum(L, 1e-12))[:, None]
            P = P - mv
        set_verts(obj, P)
        return float(np.abs(self.eval(P)).max())

    # ---- meshing --------------------------------------------------------------------------------------------------------------
    def start_mesh(self, name, coll=None):
        """Hard union of the primitives as plain meshes (input to the remesher)."""
        rig = self.rig
        objs = []
        for g in self.order:
            for p in self.groups[g]['prims']:
                bone = p[1]
                M = rig.M[bone]
                R = M[:3, :3]
                if p[0] == 'ell':
                    _, _, c, r, rot, _k = p
                    Rot = R if rot is None else R @ rot
                    objs.append(_ellipsoid_mesh('_s', M[:3, :3] @ c + M[:3, 3], r, Rot, (16, 10), coll))
                else:
                    _, _, a, b, (ra, rb), sq, _k = p
                    A = M[:3, :3] @ a + M[:3, 3]; B = M[:3, :3] @ b + M[:3, 3]
                    if np.linalg.norm(B - A) < 1e-4:
                        objs.append(_ellipsoid_mesh('_s', A, [ra, ra, ra], None, (12, 8), coll)); continue
                    o = _capsule_mesh('_s', A, B, ra, rb, 12, coll)
                    if sq is not None:
                        V = verts_of(o)
                        q = (V - M[:3, 3]) @ R          # into the bone frame
                        ax = (b - a) / np.linalg.norm(b - a)
                        # scale perpendicular components around the segment line
                        t = (q - a) @ ax
                        base = a + t[:, None] * ax
                        q = base + (q - base) * sq
                        set_verts(o, q @ R.T + M[:3, 3])
                    objs.append(o)
        obj = join(objs, name)
        recalc_normals(obj)
        return obj

    def mesh(self, name, voxel=0.006, coll=None, passes=2, smooth_iters=3):
        from .model import smooth as smooth_mesh
        tmp = collection('_sdf_tmp')
        obj = self.start_mesh(name, tmp)
        add_mod(obj, 'REMESH', mode='VOXEL', voxel_size=voxel * 1.4, adaptivity=0.0)
        apply_mods(obj)
        err = self.project(obj, 8)
        for i in range(passes):
            add_mod(obj, 'REMESH', mode='VOXEL', voxel_size=voxel, adaptivity=0.0)
            apply_mods(obj)
            smooth_mesh(obj, 0.5, smooth_iters)
            err = self.project(obj, 4)
        log(f'sdf {name}: {len(obj.data.vertices)} verts, max |d| {err * 1000:.2f} mm')
        from .core import link
        link(obj, coll)
        try:
            import bpy
            bpy.data.collections.remove(tmp)
        except Exception:
            pass
        return obj
