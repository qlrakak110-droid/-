# edlib skinning: bone-heat weights restricted to bone subsets, the rig's helper bones (twist / half-joint / crease
# helpers) fed by the same station tables as the JS kit's lofts, weight transfer body -> garment, spring-chain and
# cloth-panel bindings, smoothing, max 4 influences, normalisation, mirror checks.

import bpy
import math
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree
from .core import (verts_of, tris_of, get_weights, set_weights, set_attr, get_attr, select, smoothstep, normalize, log, g2b, b2g)

MAIN_KINDS = ('core', 'finger')

# Skin stations along a limb (fractional index on the limb path -> bone), the tables the rig team tuned for the kit's
# under-suit lofts (src/fighters/*/design.js): the helper bones take the shoulder / hip / elbow / knee / wrist regions.
ARM_STATIONS = [(0.0, 'shoulder'), (0.7, 'deltoid'), (1.15, 'upperArmTwist'), (1.9, 'upperArm'), (2.75, 'upperArm'), (3.0, 'elbow'),
                (3.25, 'foreArm'), (3.6, 'foreArm'), (4.4, 'foreArmTwist'), (4.85, 'foreArmTwist'), (5.15, 'hand')]
LEG_STATIONS = [(0.0, 'hips'), (0.75, 'hips'), (0.9975, 'hipJoint'), (1.19, 'thighTwist'), (1.3, 'thigh'), (2.75, 'thigh'), (3.0, 'knee'),
                (3.25, 'shin'), (4.8, 'shin'), (5.15, 'foot')]


def limb_path(rig, limb, side):
    """Centre-line control points (Blender bind space) of an arm / leg, the same as the kit lofts use."""
    s = side
    z = 1.0 if s == 'R' else -1.0
    if limb == 'arm':
        ua, fa = rig.data['lengths']['upperArm'], rig.data['lengths']['foreArm']
        return np.array([rig.pt('shoulder' + s, [-0.005, -0.045, 0.11 * z * rig.K]), rig.pt('upperArm' + s, [0, -0.01, 0]), rig.pt('upperArm' + s, [0, -0.5 * ua, 0]),
                         rig.pt('foreArm' + s, [0, 0, 0]), rig.pt('foreArm' + s, [0, -0.5 * fa, 0]), rig.pt('hand' + s, [0, 0, 0]), rig.pt('hand' + s, [0, -0.03, 0])])
    th, sh = rig.data['lengths']['thigh'], rig.data['lengths']['shin']
    return np.array([rig.pt('hips', [0, -0.03, 0.075 * z * rig.K]), rig.pt('thigh' + s, [0, 0, 0]), rig.pt('thigh' + s, [0, -0.5 * th, 0]),
                     rig.pt('shin' + s, [0, 0, 0]), rig.pt('shin' + s, [0, -0.5 * sh, 0]), rig.pt('foot' + s, [0, 0, 0]), rig.pt('foot' + s, [0, -0.04, 0])])


def path_param(P, path):
    """Fractional index k along a polyline for each point ((N, 3)), the closest point on it and the distance."""
    P = np.asarray(P, dtype=np.float64)
    best_d = np.full(len(P), 1e18); best_k = np.zeros(len(P)); best_c = np.zeros_like(P)
    for i in range(len(path) - 1):
        a, b = path[i], path[i + 1]
        ab = b - a; L2 = float(ab @ ab) or 1e-12
        t = ((P - a) @ ab) / L2
        if i == 0:
            tc = np.minimum(t, 1.0)             # extend before the first point
        elif i == len(path) - 2:
            tc = np.maximum(t, 0.0)             # extend past the last point
        else:
            tc = np.clip(t, 0.0, 1.0)
        c = a + tc[:, None] * ab
        d = np.linalg.norm(P - c, axis=1)
        m = d < best_d
        best_d[m] = d[m]; best_k[m] = i + tc[m]; best_c[m] = c[m]
    return best_k, best_c, best_d


def station_weights(rig, P, limb, side, crease=True):
    """
    Weights of points on an arm / leg purely from their position along the limb: {bone: (N,)} summing to 1.
    The elbow / knee ring is split: its flexor side goes to the crease helper (elbowVol / kneeVol), as the kit lofts do.
    """
    path = limb_path(rig, limb, side)
    k, c, _ = path_param(P, path)
    st = ARM_STATIONS if limb == 'arm' else LEG_STATIONS
    names = [(n if n == 'hips' else n + side) for _, n in st]
    ks = [a for a, _ in st]
    out = {}
    n = len(P)
    for i in range(len(st)):
        w = np.zeros(n)
        if i == 0:
            w += (k <= ks[0])
        if i == len(st) - 1:
            w += (k > ks[-1])
        if i > 0:        # rising edge from station i-1
            m = (k > ks[i - 1]) & (k <= ks[i])
            w[m] += smoothstep(ks[i - 1], ks[i], k[m])
        if i < len(st) - 1:   # falling edge to station i+1
            m = (k > ks[i]) & (k <= ks[i + 1])
            w[m] += 1 - smoothstep(ks[i], ks[i + 1], k[m])
        out[names[i]] = out.get(names[i], 0) + w
    if crease:
        plain, vol, flex = ('elbow', 'elbowVol', 1.0) if limb == 'arm' else ('knee', 'kneeVol', -1.0)
        if rig.has(vol + side) and plain + side in out:
            d = P - c
            dl = rig.vecs(vol + side, np.eye(3))[0]              # the helper's +X axis in Blender bind space
            x = flex * (d @ dl) / np.maximum(np.linalg.norm(d, axis=1), 1e-9)
            sd = smoothstep(0.0, 1.0, np.clip((x + 0.25) / 0.8, 0, 1))
            w = out[plain + side]
            out[vol + side] = w * sd
            out[plain + side] = w * (1 - sd)
    return out, k


def heat_weights(obj, arm, bones):
    """
    Blender's automatic (bone heat) weights restricted to `bones`. Returns True when the solver produced weights for
    every vertex. The object keeps an Armature modifier on `arm` (poses preview in Blender).
    """
    keep = {b.name: b.use_deform for b in arm.data.bones}
    for b in arm.data.bones:
        b.use_deform = b.name in bones
    obj.vertex_groups.clear()
    for m in list(obj.modifiers):
        if m.type == 'ARMATURE':
            obj.modifiers.remove(m)
    obj.parent = None
    select([obj, arm], active=arm)
    try:
        bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    except RuntimeError as e:
        log('bone heat failed on', obj.name, str(e).strip())
    for b in arm.data.bones:
        b.use_deform = keep[b.name]
    W = get_weights(obj)
    tot = np.zeros(len(obj.data.vertices))
    for w in W.values():
        tot += w
    ok = bool(len(tot)) and float((tot > 1e-4).mean()) > 0.995
    return ok


def segment_weights(P, rig, bones, power=4.0, reach=1.6):
    """
    Geometric fallback / helper: weights from the distance to each bone's head-tail segment (inverse power, only the
    nearest few bones within `reach` x the nearest distance). Smooth afterwards.
    """
    P = np.asarray(P, dtype=np.float64)
    D = np.zeros((len(bones), len(P)))
    for i, b in enumerate(bones):
        a, c = rig.head(b), rig.tail(b)
        ab = c - a; L2 = float(ab @ ab) or 1e-12
        t = np.clip(((P - a) @ ab) / L2, 0, 1)
        D[i] = np.linalg.norm(P - (a + t[:, None] * ab), axis=1)
    dmin = D.min(axis=0)
    W = 1.0 / np.maximum(D, 1e-4) ** power
    W[D > reach * dmin[None, :] + 0.02] = 0
    W /= W.sum(axis=0, keepdims=True)
    return {b: W[i] for i, b in enumerate(bones)}


def _adjacency(obj):
    me = obj.data
    e = np.empty(len(me.edges) * 2, dtype=np.int32)
    me.edges.foreach_get('vertices', e)
    return e.reshape(-1, 2)


def smooth_weights(W, obj, iterations=2, factor=0.5, mask=None):
    """Laplacian smoothing of a weight dict over the mesh edges (keeps sums; `mask` (N,) limits where it acts)."""
    E = _adjacency(obj)
    n = len(obj.data.vertices)
    deg = np.zeros(n); np.add.at(deg, E[:, 0], 1); np.add.at(deg, E[:, 1], 1)
    deg = np.maximum(deg, 1)
    f = factor if mask is None else factor * np.asarray(mask)
    out = {}
    for name, w in W.items():
        w = np.array(w, dtype=np.float64)
        for _ in range(iterations):
            acc = np.zeros(n)
            np.add.at(acc, E[:, 0], w[E[:, 1]]); np.add.at(acc, E[:, 1], w[E[:, 0]])
            w = w + f * (acc / deg - w)
        out[name] = w
    return out


def limit_normalize(W, max_inf=4, floor=0.004):
    """Keep the `max_inf` largest influences per vertex, drop dust below `floor`, normalise to 1."""
    names = list(W.keys())
    if not names:
        return W
    A = np.stack([np.asarray(W[n], dtype=np.float64) for n in names], axis=0)
    A[A < floor] = 0
    if len(names) > max_inf:
        order = np.argsort(-A, axis=0)
        drop = order[max_inf:]
        np.put_along_axis(A, drop, 0.0, axis=0)
    s = A.sum(axis=0)
    bad = s < 1e-8
    A = A / np.where(bad, 1.0, s)[None, :]
    return {n: A[i] for i, n in enumerate(names) if A[i].max() > 0}


def helpers_from_main(W, rig, P):
    """
    Spread main-bone weights onto the rig's helper bones: for each limb the share a vertex gives to the limb's own
    bones (clavicle..hand, thigh..foot) is redistributed by the station tables along the limb (deltoid, twist helpers,
    half-joints, crease helpers); what it gives to the torso (the armpit / groin blend found by bone heat) is kept.
    """
    n = len(P)
    out = {k: np.array(v, dtype=np.float64) for k, v in W.items()}
    for side in ('R', 'L'):
        for limb, bones in (('arm', ['shoulder', 'upperArm', 'foreArm', 'hand']), ('leg', ['thigh', 'shin', 'foot', 'toe'])):
            names = [b + side for b in bones]
            lw = np.zeros(n)
            for b in names:
                lw += out.get(b, 0)
            if lw.max() < 1e-6:
                continue
            st, k = station_weights(rig, P, limb, side)
            if limb == 'arm':
                # fingers / thumb keep their own weights; the hand keeps what lies beyond the wrist
                for b in names:
                    out.pop(b, None)
                for b, w in st.items():
                    out[b] = out.get(b, 0) + w * lw
            else:
                foot = out.get('foot' + side, np.zeros(n)); toe = out.get('toe' + side, np.zeros(n))
                ft = foot + toe
                toe_share = np.where(ft > 1e-6, toe / np.maximum(ft, 1e-9), 0.0)
                for b in names:
                    out.pop(b, None)
                for b, w in st.items():
                    if b == 'foot' + side:
                        out[b] = out.get(b, 0) + w * lw * (1 - toe_share)
                        out['toe' + side] = out.get('toe' + side, 0) + w * lw * toe_share
                    else:
                        out[b] = out.get(b, 0) + w * lw
    return out


def auto_skin(obj, arm, rig, bones=None, helpers=True, smooth=2, max_inf=4):
    """
    Skin an object to the body rig: bone heat on the anatomical chain (core + finger bones, or `bones`), fallback to
    segment-distance weights when the solver fails, helper bones from the station tables, smoothing, 4 influences,
    normalised. Use it for the body and for garments that have no body underneath to copy from.
    """
    bones = bones or [b for b in rig.names if rig.kind(b) in MAIN_KINDS]
    P = verts_of(obj)
    ok = heat_weights(obj, arm, set(bones))
    if ok:
        W = get_weights(obj)
    else:
        log('auto_skin', obj.name, ': bone heat gave no solution, using segment weights')
        W = segment_weights(P, rig, bones)
        W = smooth_weights(W, obj, 6, 0.6)
        if not any(m.type == 'ARMATURE' for m in obj.modifiers):
            m = obj.modifiers.new('armature', 'ARMATURE'); m.object = arm
    if helpers:
        W = helpers_from_main(W, rig, P)
    if smooth:
        W = smooth_weights(W, obj, smooth, 0.5)
    W = limit_normalize(W, max_inf)
    set_weights(obj, W)
    return obj


def attach(obj, arm):
    """Give the object an Armature modifier on `arm` (so pose_armature() deforms it) without touching its weights."""
    for m in obj.modifiers:
        if m.type == 'ARMATURE':
            m.object = arm
            return obj
    m = obj.modifiers.new('armature', 'ARMATURE'); m.object = arm
    return obj


def transfer_weights(src, dst, arm=None, smooth=1, max_inf=4, mask=None, bones=None):
    """
    Copy skin weights from `src` (the body) to `dst` (a garment) by the closest point on the source surface
    (barycentric). The standard way to skin clothes: sleeves and trousers then bend exactly like the limb inside them,
    helper bones included. mask: (N,) 0..1 blend with the garment's existing weights (0 keeps them).
    bones: only transfer these (others are dropped and the rest renormalised).
    """
    SV = verts_of(src); ST = tris_of(src)
    SW = get_weights(src)
    if bones is not None:
        SW = {k: v for k, v in SW.items() if k in bones}
    names = list(SW.keys())
    A = np.stack([SW[n] for n in names], axis=1) if names else np.zeros((len(SV), 0))
    bvh = BVHTree.FromPolygons([tuple(v) for v in SV], [tuple(int(i) for i in t) for t in ST])
    P = verts_of(dst)
    out = np.zeros((len(P), len(names)))
    for i, p in enumerate(P):
        loc, nrm, fi, dist = bvh.find_nearest(Vector(p))
        if fi is None:
            continue
        t = ST[fi]
        a, b, c = SV[t[0]], SV[t[1]], SV[t[2]]
        v0, v1, v2 = b - a, c - a, np.array(loc) - a
        d00, d01, d11, d20, d21 = v0 @ v0, v0 @ v1, v1 @ v1, v2 @ v0, v2 @ v1
        den = d00 * d11 - d01 * d01 or 1e-12
        vv = (d11 * d20 - d01 * d21) / den; ww = (d00 * d21 - d01 * d20) / den
        uu = 1 - vv - ww
        out[i] = uu * A[t[0]] + vv * A[t[1]] + ww * A[t[2]]
    W = {n: out[:, i] for i, n in enumerate(names)}
    if smooth:
        W = smooth_weights(W, dst, smooth, 0.5)
    if mask is not None:
        old = get_weights(dst)
        m = np.asarray(mask, dtype=np.float64)
        keys = set(W) | set(old)
        W = {k: W.get(k, 0) * m + old.get(k, 0) * (1 - m) for k in keys}
    W = limit_normalize(W, max_inf)
    set_weights(dst, W)
    if arm is not None:
        attach(dst, arm)
    return dst


def chain_weights(names, s, parent=None, root_blend=0.0):
    """
    Weights along a spring chain for parameter s (array, 0 at the root .. 1 at the tip): every bone carries its own
    segment, joints blend over the middle of the neighbouring segments (the kit's chainWeights). root_blend > 0 leaves
    the first share of the length on `parent` (a tail that grows out of the body).
    """
    s = np.clip(np.asarray(s, dtype=np.float64), 0, 1)
    n = len(names)
    x = s * n
    i = np.minimum(n - 1, np.floor(x).astype(int)); f = x - i
    W = {nm: np.zeros(len(s)) for nm in names}
    for b in range(n):
        m = i == b
        up = m & (f > 0.5) & (b < n - 1)
        dn = m & (f < 0.5) & (b > 0)
        mid = m & ~up & ~dn
        W[names[b]][mid] += 1
        W[names[b]][up] += 1 - (f[up] - 0.5)
        if b < n - 1:
            W[names[b + 1]][up] += f[up] - 0.5
        W[names[b]][dn] += 1 - (0.5 - f[dn])
        if b > 0:
            W[names[b - 1]][dn] += 0.5 - f[dn]
    if parent and root_blend > 0:
        k = np.clip(1 - s / root_blend, 0, 1)
        for nm in names:
            W[nm] *= (1 - k)
        W[parent] = k
    return W


def along_chain(obj, rig, prefix, param=None, parent=None, root_blend=0.0):
    """
    Bind an object to a spring-bone chain (prefix1, prefix2 ...): hair tails, queues, sash ends, tassels, sleeve drapes.
    param: (N,) position along the chain 0..1 per vertex; default: the object's ed_uv.v (lofts, sweeps, braids, ribbons
    and tassels write it), else the projection onto the chain's bind-pose joints.
    """
    names = rig.chain(prefix)
    if param is None:
        q = get_attr(obj, 'ed_uv')
        if q is not None:
            param = q[:, 1]
        else:
            pts = rig.chain_points(prefix)
            k, _, _ = path_param(verts_of(obj), pts)
            param = np.clip(k / (len(pts) - 1), 0, 1)
    parent = parent or rig.bones[names[0]]['parent']
    W = chain_weights(names, param, parent, root_blend)
    set_weights(obj, limit_normalize(W))
    return obj


def by_rows(obj, rig, rows_to_bones):
    """Rigid rows (lamellar): rows_to_bones = {row index: bone or [(bone, w), ...]} using the object's ed_row attribute."""
    row = get_attr(obj, 'ed_row')
    n = len(row)
    W = {}
    for r, spec in rows_to_bones.items():
        m = (row == r).astype(np.float64)
        for b, w in ([(spec, 1.0)] if isinstance(spec, str) else spec):
            W[b] = W.get(b, np.zeros(n)) + m * w
    set_weights(obj, limit_normalize(W))
    return obj


# ---- runtime cloth panels ---------------------------------------------------------------------------------------------------

PANELS = {}


def define_panel(name, grid, anchor='hips', rig=None, cols=None, rows=None, **params):
    """
    Define a runtime cloth panel (verlet grid simulated by the game) FROM a draped Blender shape, so the game's cloth
    starts exactly where Blender left it. grid: (R, C, 3) Blender-space rest positions, row 0 = the pinned top edge,
    columns ordered from the fighter's LEFT to his RIGHT (increasing game z = decreasing Blender x) — or a lofted
    object (its ed_grid rows / columns are resampled to cols x rows).
    anchor: bone the top row is pinned to (or one bone per column). params: any rig cloth option (damping, stretch,
    bend, margin, wind, gravity, thickness, pinRows ...), stored in the asset and passed to the design by assets.cloth().
    """
    if not isinstance(grid, np.ndarray):
        obj = grid
        N, R = obj['ed_grid']
        G = verts_of(obj)[: N * R].reshape(R, N, 3)
    else:
        G = np.asarray(grid, dtype=np.float64)
    R0, C0 = G.shape[0], G.shape[1]
    cols = cols or C0; rows = rows or R0
    if (cols, rows) != (C0, R0):
        uu = np.linspace(0, C0 - 1, cols); vv = np.linspace(0, R0 - 1, rows)
        out = np.zeros((rows, cols, 3))
        for j, v in enumerate(vv):
            j0 = min(int(v), R0 - 2); fv = v - j0
            for i, u in enumerate(uu):
                i0 = min(int(u), C0 - 2); fu = u - i0
                out[j, i] = (G[j0, i0] * (1 - fu) + G[j0, i0 + 1] * fu) * (1 - fv) + (G[j0 + 1, i0] * (1 - fu) + G[j0 + 1, i0 + 1] * fu) * fv
        G = out
    if G[0, 0, 0] < G[0, -1, 0]:
        raise ValueError(f'panel {name}: columns must run from the fighter\'s left (+x in Blender) to his right (-x)')
    anchors = [anchor] * cols if isinstance(anchor, str) else list(anchor)
    PANELS[name] = {'name': name, 'cols': cols, 'rows': rows, 'rest': G, 'anchors': anchors, 'params': params}
    return PANELS[name]


def _panel_bvh(G):
    R, C = G.shape[0], G.shape[1]
    V = G.reshape(-1, 3)
    tris, cell = [], []
    for j in range(R - 1):
        for i in range(C - 1):
            a, b, c, d = j * C + i, j * C + i + 1, (j + 1) * C + i + 1, (j + 1) * C + i
            tris.append((a, b, c)); cell.append((i, j, 0))
            tris.append((a, c, d)); cell.append((i, j, 1))
    return BVHTree.FromPolygons([tuple(v) for v in V], tris), V, tris, cell


def bind_panel(obj, panel, share=None, uv=None):
    """
    Bind an object's vertices to a runtime cloth panel: each vertex gets panel coordinates (u across 0..1, v down 0..1)
    and a share (0..1) of cloth versus its ordinary bone weights (vertex groups). The engine turns (u, v) into bilinear
    weights on the particle bones of whatever grid the quality tier runs, so one asset serves every tier.
    panel: a define_panel() dict or rig.panel(name). share: (N,) array or fn(u, v) -> share (default 1: fully cloth).
    uv: (N, 2) panel coordinates when known (a loft that was draped: its ed_uv); default: closest point on the grid.
    """
    G = panel['rest']
    R, C = G.shape[0], G.shape[1]
    P = verts_of(obj)
    if uv is None:
        bvh, V, tris, cell = _panel_bvh(G)
        UV = np.zeros((len(P), 2))
        for k, p in enumerate(P):
            loc, nrm, fi, dist = bvh.find_nearest(Vector(p))
            i, j, half = cell[fi]
            t = tris[fi]
            a, b, c = V[t[0]], V[t[1]], V[t[2]]
            v0, v1, v2 = b - a, c - a, np.array(loc) - a
            d00, d01, d11, d20, d21 = v0 @ v0, v0 @ v1, v1 @ v1, v2 @ v0, v2 @ v1
            den = d00 * d11 - d01 * d01 or 1e-12
            bv = (d11 * d20 - d01 * d21) / den; bw = (d00 * d21 - d01 * d20) / den
            if half == 0:   # (a, b, c) = (i,j), (i+1,j), (i+1,j+1)
                fu, fv = bv + bw, bw
            else:           # (a, c, d) = (i,j), (i+1,j+1), (i,j+1)
                fu, fv = bv, bv + bw
            UV[k] = ((i + fu) / (C - 1), (j + fv) / (R - 1))
    else:
        UV = np.asarray(uv, dtype=np.float64)[:, :2]
    UV = np.clip(UV, 0, 1)
    if share is None:
        sh = np.ones(len(P))
    elif callable(share):
        sh = np.asarray(share(UV[:, 0], UV[:, 1]), dtype=np.float64) * np.ones(len(P))
    else:
        sh = np.asarray(share, dtype=np.float64)
    set_attr(obj, 'ed_cloth', np.stack([UV[:, 0], UV[:, 1], np.clip(sh, 0, 1)], axis=1), 'FLOAT_VECTOR')
    obj['ed_panel'] = panel['name']
    return obj


# ---- checks ------------------------------------------------------------------------------------------------------------------

def mirror_check(obj, rig, tol=0.002):
    """
    Symmetry report of a skinned object: for every vertex the mirrored vertex (across Blender x = 0) should carry the
    mirrored weights (R <-> L). Returns { unmatched, max_diff, mean_diff }.
    """
    P = verts_of(obj)
    kd = KDTree(len(P))
    for i, p in enumerate(P):
        kd.insert(Vector(p), i)
    kd.balance()
    W = get_weights(obj)
    names = list(W.keys())
    A = np.stack([W[n] for n in names], axis=1) if names else np.zeros((len(P), 0))
    col = {n: i for i, n in enumerate(names)}
    perm = [col.get(rig.mirror(n), -1) for n in names]
    unmatched, diffs = 0, []
    for i, p in enumerate(P):
        co, j, d = kd.find(Vector((-p[0], p[1], p[2])))
        if d > tol:
            unmatched += 1
            continue
        a = A[i]
        b = np.array([A[j][q] if q >= 0 else 0.0 for q in perm])
        diffs.append(float(np.abs(a - b).max()))
    return {'vertices': len(P), 'unmatched': unmatched, 'max_diff': max(diffs) if diffs else 0.0, 'mean_diff': float(np.mean(diffs)) if diffs else 0.0}


def weight_report(obj):
    """{ vertices, bones, max_influences, unweighted, not_normalised } of a skinned object (cloth shares included)."""
    W = get_weights(obj)
    n = len(obj.data.vertices)
    if not W:
        return {'vertices': n, 'bones': 0, 'max_influences': 0, 'unweighted': n, 'not_normalised': n}
    A = np.stack(list(W.values()), axis=1)
    tot = A.sum(axis=1)
    cl = get_attr(obj, 'ed_cloth')
    if cl is not None:
        tot = tot * (1 - cl[:, 2]) + cl[:, 2]
    return {'vertices': n, 'bones': len(W), 'max_influences': int((A > 1e-4).sum(axis=1).max()), 'unweighted': int((tot < 1e-4).sum()),
            'not_normalised': int((np.abs(tot - 1) > 0.02).sum())}
