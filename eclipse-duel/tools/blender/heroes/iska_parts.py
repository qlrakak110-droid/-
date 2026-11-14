# Helpers of tools/blender/heroes/iska.py (설리화): looks, garment / ornament builders that edlib does not have yet.
# Not a hero script: running it does nothing (tools/blender/build_assets.sh all runs every heroes/*.py).
#
# Candidates for edlib (reported, not moved: edlib is shared): orient_out, thick, surf_path, brocade_uv, sleeve_shell
# (a wide sleeve with a per-angle hem: mouth lower at the back), shell_on_head (offset shell over a region of the head
# SDF in angular coordinates: masks, veils), atlas_bake (several low pieces baked into one map pair: one set per slot).

import math
import os
import numpy as np
import edlib as ed

TAU = math.pi * 2
MOTIF = {'cloud': 0, 'wave': 1, 'flame': 2, 'fret': 3, 'sun': 4, 'moon': 5, 'thunder': 6, 'lattice': 7}


def looks():
    """The 한월궁 palette: moon white, deep indigo, pearl silver; frost glow (linear colours)."""
    L = ed.look
    return {
        'skin': L('skin', color=(0.3, 0.25, 0.235), rough=0.55, set='leather', amt=0.1),
        'moon': L('moon', color=(0.33, 0.37, 0.48), rough=0.5, set='silk', amt=0.9),                 # outer robe: moon-white silk
        'moonIn': L('moonIn', color=(0.018, 0.024, 0.09), rough=0.6, set='silk', amt=0.8),           # its indigo lining
        'indigo': L('indigo', color=(0.014, 0.019, 0.078), rough=0.5, set='silk', amt=1.0),          # inner robe, sleeves under the bell
        'band': L('band', color=(0.018, 0.024, 0.1), rough=0.5, set='brocade', amt=1.0),            # collar / hem / cuff bands: silver snow crystals on indigo
        'dongjeong': L('dongjeong', color=(0.6, 0.62, 0.66), rough=0.6, set='silk', amt=0.6),        # pale inner-collar strip
        'sash': L('sash', color=(0.016, 0.02, 0.085), rough=0.55, set='damask', amt=1.0, vein=0.12),  # figured indigo silk, frost through the figure
        'cord': L('cord', color=(0.5, 0.52, 0.58), rough=0.7, set='hemp', amt=0.7),
        'trousers': L('trousers', color=(0.012, 0.015, 0.05), rough=0.85, set='hemp', amt=1.0),
        'wrap': L('wrap', color=(0.1, 0.11, 0.14), rough=0.9, set='hemp', amt=1.0),                # moon-grey shin wraps
        'shoe': L('shoe', color=(0.014, 0.017, 0.055), rough=0.75, set='hemp', amt=0.9),
        'sole': L('sole', color=(0.44, 0.43, 0.41), rough=0.85, set='hemp', amt=0.8),
        'glove': L('glove', color=(0.018, 0.022, 0.06), rough=0.6, set='leather', amt=1.0),
        'silver': L('silver', color=(0.66, 0.7, 0.8), rough=0.36, metal=0.74, set='engraved', amt=0.7, vein=0.3),
        'silverPlain': L('silverPlain', color=(0.64, 0.67, 0.74), rough=0.22, metal=1.0, set='hammered', amt=0.4),
        'maskIn': L('maskIn', color=(0.008, 0.009, 0.014), rough=0.8, set='hammered', amt=0.0, occ=0.4),
        'eye': L('eye', color=(0.06, 0.12, 0.22), rough=0.4, set='hammered', amt=0.0, eye=1.0, emission=(0.6, 0.85, 1.0)),
        'hair': L('hair', color=(0.011, 0.012, 0.018), rough=0.4, set='hair', amt=1.0),
        'hairCut': L('hairCut', color=(0.011, 0.012, 0.018), rough=0.42, set='hair', amt=1.0),
        'gauze': L('gauze', color=(0.03, 0.04, 0.12), rough=0.75, set='gauze', amt=1.0),
        'jade': L('jade', color=(0.32, 0.46, 0.41), rough=0.2, set='jade', amt=0.7),
        'crystal': L('crystal', color=(0.34, 0.55, 0.8), rough=0.07, set='hammered', amt=0.0, inlay=0.35, wear=0.3, emission=(0.5, 0.8, 1.0)),
        'tassel': L('tassel', color=(0.36, 0.42, 0.55), rough=0.5, set='hair', amt=1.0),
        # the crescents
        'steel': L('steel', color=(0.36, 0.38, 0.43), rough=0.2, metal=1.0, set='blade', amt=0.45, wear=0.4),
        'spine': L('spine', color=(0.09, 0.12, 0.2), rough=0.3, metal=1.0, set='engraved', amt=0.8, vein=0.25),
        'frost': L('frost', color=(0.5, 0.75, 1.0), rough=0.2, set='hammered', amt=0.0, inlay=1.0, emission=(0.5, 0.8, 1.0)),
        'gripWrap': L('gripWrap', color=(0.02, 0.03, 0.09), rough=0.8, set='hemp', amt=0.9),
    }


# ---- small geometry helpers ----------------------------------------------------------------------------------------------

def orient_out(obj, axis_pts):
    """Make an open garment sheet's faces point away from its axis (the lining then goes inside)."""
    V, N = ed.verts_of(obj), ed.normals_of(obj)
    k, c, _ = ed.skin.path_param(V, np.asarray(axis_pts))
    if float(np.mean(np.einsum('ij,ij->i', N, V - c))) < 0:
        flip(obj)
    return obj


def flip(obj):
    import bmesh
    bm = bmesh.new(); bm.from_mesh(obj.data)
    bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    bm.to_mesh(obj.data); bm.free(); obj.data.update()
    return obj


def thick(obj, t, inner=None, offset=-1.0, max_tris=None):
    """Solidify a sheet; the inner shell takes the `inner` look (lining). Rims close the cut edges. max_tris: decimate
    the SHEET first (decimating a solidified shell collapses its two skins into each other: holes)."""
    if max_tris and ed.tri_count(obj, evaluated=False) > max_tris:
        ed.decimate_to(obj, max_tris)
    if inner is not None:
        obj.data.materials.append(inner)
    ed.add_mod(obj, 'SOLIDIFY', thickness=t, offset=offset, use_rim=True, use_even_offset=False, use_quality_normals=True,
               material_offset=1 if inner is not None else 0)
    return ed.apply_mods(obj)


def surf_path(Sf, uv, n=24, lift=0.0):
    """Points + normals along a (u, v) polyline on a parametric surface."""
    UV = ed.polyline(np.array([[u, v, 0.0] for u, v in uv]), n)
    pts, nrm = [], []
    for u, v, _ in UV:
        p, nn, tu, tv = ed.surface_normal(Sf, u, v)
        pts.append(p + nn * lift); nrm.append(nn)
    return np.array(pts), np.array(nrm)


def brocade_uv(obj, length, width, code):
    """ed_uvw of a ribbon for the `brocade` set: u along the band in band widths, v across, code = motif + glow."""
    q = ed.get_attr(obj, 'ed_uvw')
    ed.set_attr(obj, 'ed_uvw', np.stack([q[:, 1] * length / width * 0.5, q[:, 0], np.full(len(q), code)], axis=1), 'FLOAT_VECTOR')


def band_along(name, pts, nrm, width, look, code=None, thickness=0.0025, camber=0.15, nu=3, offset=0.0):
    """An embroidered band (ribbon + thickness) following surface points / normals."""
    r = ed.ribbon(name, pts, width=width, normal=nrm, camber=camber, nu=nu)
    if code is not None:
        brocade_uv(r, float(np.linalg.norm(np.diff(pts, axis=0), axis=1).sum()), width if np.ndim(width) == 0 else 0.03, code)
    if thickness:
        thick(r, thickness, offset=offset)
    ed.assign_look(r, look)
    return r


def limb_radius(Ssub, a, b, e1, e2, ts, n=24):
    """Mean body radius around the segment a -> b at parameters ts."""
    A = np.linspace(0, TAU, n, endpoint=False)
    return [[t, float(np.mean(ed.body_radius(Ssub, a + (b - a) * t, e1, e2, A, rmax=0.2)))] for t in ts]


def grid_mesh(name, G, close_u=False, flipf=False):
    """Mesh from an (R, C, 3) grid of points (row-major), ed_uv = (u across, v down), obj['ed_grid'] = [C, R]."""
    R, C = G.shape[0], G.shape[1]
    from ed.model import grid_faces
    F = grid_faces(C, R, close_u=close_u, flip=flipf)
    o = ed.new_mesh(name, G.reshape(-1, 3), F)
    us = np.tile(np.linspace(0, 1, C, endpoint=not close_u) if not close_u else np.arange(C) / C, R)
    vs = np.repeat(np.linspace(0, 1, R), C)
    ed.set_attr(o, 'ed_uv', np.stack([us, vs, np.zeros(len(us))], axis=1), 'FLOAT_VECTOR')
    o['ed_grid'] = [C, R]
    return o


def sleeve_shell(name, sdf, axis, n=32, rows=26, offset=None, hem=None, min_r=0.03, rmax=0.3):
    """
    A wide sleeve around an arm: rings perpendicular to the arm `axis` ((k, 3) control points from the shoulder past the
    mouth, Blender space), radius = the arm's hull + offset(u, s) where s is the arc length (m) from the shoulder. The hem
    is shaped per angle: hem(u) -> arc length of the mouth at that angle (u 0 = front, 0.25 = hero's left, 0.5 = back):
    a sleeve whose mouth hangs lower at the back. Rows are spread from the shoulder to each angle's hem, so ed_uv.v = 1
    is the hem all round. Returns the loft (ed_uv, ed_grid; closed in u).
    """
    A = ed.polyline(np.asarray(axis, dtype=np.float64), 200)
    seg = np.linalg.norm(np.diff(A, axis=0), axis=1)
    sl = np.concatenate([[0], np.cumsum(seg)])
    T, _, _ = ed.frames_along(A)
    us = np.arange(n) / n
    ang = us * TAU
    hems = np.array([hem(u) for u in us])
    rings = []
    for j in range(rows):
        v = j / (rows - 1)
        ring = []
        for i in range(n):
            s_ = min(v * hems[i], sl[-1])
            k = int(np.clip(np.searchsorted(sl, s_), 1, len(sl) - 1))
            f = (s_ - sl[k - 1]) / max(sl[k] - sl[k - 1], 1e-9)
            c = A[k - 1] * (1 - f) + A[k] * f
            t = T[k]
            fr = ed.normalize(np.array([0.0, -1.0, 0.0]) - t * np.dot([0.0, -1.0, 0.0], t))
            sd = np.cross(t, fr)
            if sd[0] < 0:
                sd = -sd
            AA = np.linspace(0, TAU, 48, endpoint=False)
            rb = ed.convexify(ed.body_radius(sdf, c, fr, sd, AA, rmax=rmax), AA, 40, True)
            r = float(np.interp(ang[i], np.concatenate([AA, [TAU]]), np.concatenate([rb, rb[:1]])))
            r = max(r, min_r) + (offset(us[i], s_) if offset else 0.01)
            ring.append(c + r * (np.cos(ang[i]) * fr + np.sin(ang[i]) * sd))
        rings.append(ring)
    obj = ed.loft(name, np.array(rings), close=True)
    return obj


def closed_band(name, S, v, width, look, code, n=96, lift=0.002, thickness=0.0025, camber=0.04):
    """An embroidered band all round a closed loft surface S at parameter v (hems, cuffs, sash edges)."""
    pts, nrm = [], []
    for u in np.linspace(0, 1, n + 1):
        p, nn, _, _ = ed.surface_normal(S, u, v)
        pts.append(p + nn * lift); nrm.append(nn)
    pts, nrm = np.array(pts), np.array(nrm)
    return band_along(name, pts, nrm, width, look, code=code, thickness=thickness, camber=camber, nu=2)


def head_grid(rig, sdf, a_range, y_fn, nu, nv, offset, cx=-0.01, hull=True, smooth=0):
    """
    An offset shell over a region of the head in angular coordinates (head frame: a = angle round the head's vertical
    axis in degrees, 0 = the face, + = the hero's right (game +z); y = height above the skull base):
      a_range (a0, a1), y_fn(a) -> (y_bottom, y_top) per column, offset(a, y) -> metres off the (hull of the) head.
    Rays run from the head's axis (head frame x = cx) outward; the hull spans the eye sockets and the nose bridge;
    smooth > 0 relaxes the head's radius field that many times first (planes instead of anatomy: masks, veils).
    Returns an (nv, nu, 3) grid (row 0 = bottom) in Blender space and the (a, y) of each point.
    """
    A = np.linspace(a_range[0], a_range[1], nu)
    Rr = np.zeros((nv, nu)); C = np.zeros((nv, nu, 3)); D = np.zeros((nv, nu, 3)); AY = np.zeros((nv, nu, 2))
    fw = rig.vec('head', [1, 0, 0]); rt = rig.vec('head', [0, 0, 1])
    AA = np.radians(np.linspace(-180, 180, 73)[:-1])
    for i, a in enumerate(A):
        y0, y1 = y_fn(a)
        for j, y in enumerate(np.linspace(y0, y1, nv)):
            c = rig.pt('head', [cx, y, 0])
            rb = ed.body_radius(sdf, c, fw, rt, AA, rmax=0.2)
            if hull:
                rb = ed.convexify(rb, AA, 30, True)
            ar = math.radians(a)
            Rr[j, i] = float(np.interp(ar, AA, rb, period=TAU))
            C[j, i] = c; D[j, i] = math.cos(ar) * fw + math.sin(ar) * rt
            AY[j, i] = (a, y)
    for _ in range(smooth):
        Rp = np.pad(Rr, 1, mode='edge')
        Rr = 0.5 * Rr + 0.125 * (Rp[:-2, 1:-1] + Rp[2:, 1:-1] + Rp[1:-1, :-2] + Rp[1:-1, 2:])
    off = np.array([[offset(AY[j, i, 0], AY[j, i, 1]) for i in range(nu)] for j in range(nv)])
    G = C + D * (Rr + off)[..., None]
    return G, AY


def paint_by_normal(obj, axis_pts, out_look, in_look):
    """After solidify: faces whose normal points away from the axis polyline take out_look, the others in_look."""
    import bmesh
    k, c, _ = ed.skin.path_param(np.array([p.center for p in obj.data.polygons]), np.asarray(axis_pts))
    out = []
    for i, p in enumerate(obj.data.polygons):
        out.append(float(np.dot(np.array(p.normal), np.array(p.center) - c[i])) > 0)
    out = np.array(out)
    ed.assign_look(obj, out_look, faces=np.nonzero(out)[0])
    ed.assign_look(obj, in_look, faces=np.nonzero(~out)[0])


def extrude_poly(name, pts2, depth, origin, ex, ey, ez, bevel=0.0, segs=2):
    """Prism of a 2D outline (x, y in the frame ex / ey) extruded `depth` along ez, centred; optional bevelled edges."""
    import bmesh, bpy
    bm = bmesh.new()
    o = np.asarray(origin)
    top = [bm.verts.new(tuple(o + ex * x + ey * y + ez * depth / 2)) for x, y in pts2]
    bot = [bm.verts.new(tuple(o + ex * x + ey * y - ez * depth / 2)) for x, y in pts2]
    n = len(pts2)
    bm.faces.new(top); bm.faces.new(list(reversed(bot)))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([bot[i], bot[j], top[j], top[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel, segments=segs, profile=0.5, affect='EDGES')
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    obj = bpy.data.objects.new(name, me)
    ed.link(obj)
    ed.shade(obj, 35)
    return obj


# ---- 월아쌍도: the crescent blade (weapon bone frame: x toward the tip, y the back, z the flats) -------------------------------
CR, CA, CX0 = 0.42, math.radians(68), 0.06          # src/char/weapons.js: the spine arc (unchanged outline)


def crescent_arc(t):
    return np.array([CX0 + math.sin(t * CA) * CR, (1 - math.cos(t * CA)) * CR])


def crescent_w(t):
    return 0.004 + 0.034 * max(0.0, math.sin(math.pi * min(1.0, t * 1.04))) ** 0.75 * (1 - 0.3 * t)


def crescent_th(t):
    return 0.0042 * (1 - 0.6 * t) + 0.0008


def crescent_pieces(frame, LK, n=40):
    """
    The crescent of the right hand built in a weapon frame: frame(x, y, z) -> Blender point (the left blade passes a
    z-mirrored frame). Same outline as the kit's (arc, width law, guard, knuckle bow, grip, pommel, bead, ring), refined:
    a true edge with a polished secondary bevel, hollow-ground flats, a fuller with hard lips and the frost seam in its
    floor, a blued spine with chamfers, a cord-wrapped grip. Returns [(object, look name)].
    """
    out = []
    FC0, FC1 = 0.1, 0.74
    def ful(t, w):
        k = min(max(min((t - FC0) / 0.06, (FC1 - t) / 0.1), 0), 1)
        return w * 0.3, min(0.0058, w * 0.2) * math.sqrt(k), 0.0017 * min(1, k * 1.5)
    def sec(t):
        w, th = max(0.0012, crescent_w(t)), crescent_th(t)
        sp = min(th * 0.8 * (1 - float(ed.smoothstep(0.7, 0.93, t))) + 0.00015, th * 0.9)
        ch, e = min(0.0028, w * 0.14), min(0.0095, w * 0.42)
        fc, fw, fd = ful(t, w)
        top = [(-w, 0.0), (-w + 0.0012, th * 0.16), (-(w - e), th * 0.5), ((-(w - e) + fc - fw) * 0.5, th * 0.8), (fc - fw, th), (fc - fw * 0.62, th - fd),
               (fc + fw * 0.62, th - fd), (fc + fw, th), (w - ch, th * 0.96), (w - ch * 0.15, sp)]
        bot = [(a, -z) for a, z in reversed(top[1:])]
        return top + [(w, 0.0)] + bot, (w, th, fc, fw, fd, e, ch)
    rings, info = [], []
    ts = np.linspace(0.0, 1.0, n)
    for t in ts:
        s2, inf = sec(t)
        c = crescent_arc(t); nn = np.array([-math.sin(t * CA), math.cos(t * CA)])
        rings.append([frame(c[0] + nn[0] * a, c[1] + nn[1] * a, z) for a, z in s2])
        info.append(inf)
    blade = ed.loft('crescent_blade', np.array(rings), close=True, caps=(True, True))
    ed.shade(blade, 24)
    # uvw for the `blade` set (metres along, 0 edge .. 1 back, temper height) + the look of each face by its zone
    m = len(rings[0])
    q = ed.get_attr(blade, 'ed_uv')
    j = np.clip(np.round(q[:, 1] * (n - 1)).astype(int), 0, n - 1)
    k = np.round(q[:, 0] * m).astype(int) % m
    s0, _ = sec(0.5)
    A_rel = np.array([sec(ts[jj])[0][kk][0] / max(info[jj][0], 1e-4) for jj, kk in zip(j, k)])
    ed.set_attr(blade, 'ed_uvw', np.stack([ts[j] * CR * CA, np.clip((A_rel + 1) / 2, 0, 1), np.full(len(j), 0.3)], axis=1), 'FLOAT_VECTOR')
    ed.assign_look(blade, LK['steel'])
    fz = np.array([np.mean(A_rel[list(p.vertices)]) for p in blade.data.polygons])
    ed.assign_look(blade, LK['spine'], faces=np.nonzero(fz > 0.84)[0])
    cav = np.ones(len(j), dtype=np.float32)
    zfull = np.array([abs(sec(ts[jj])[0][kk][1]) < info[jj][1] - info[jj][4] * 0.5 and info[jj][4] > 0.0004 and abs(A_rel[i] * info[jj][0] - info[jj][2]) < info[jj][3] * 0.9
                      for i, (jj, kk) in enumerate(zip(j, k))])
    cav[zfull] = 0.62
    ed.set_attr(blade, 'ed_cav', cav)
    out.append((blade, 'steel'))
    # the frost seam in the fuller floor (both flats)
    for sz in (1, -1):
        pts = []
        for t in np.linspace(0.14, 0.7, 26):
            w, th, fc, fw, fd, e, ch = info[0] if False else sec(t)[1]
            c = crescent_arc(t); nn = np.array([-math.sin(t * CA), math.cos(t * CA)])
            pts.append(frame(c[0] + nn[0] * fc, c[1] + nn[1] * fc, sz * (th - fd + 0.00035)))
        pts = np.array(pts)
        zn = ed.normalize(frame(0, 0, sz) - frame(0, 0, 0))
        r = ed.ribbon('crescent_seam', pts, width=[[0, 0.0012], [0.5, 0.0019], [1, 0.0008]], normal=zn, camber=0.2, nu=2)
        ed.assign_look(r, LK['frost'])
        out.append((r, 'frost'))
    # guard (a lobed silver plate across the blade root), knuckle bow round the fingers to the pommel
    ex, ey, ez = (ed.normalize(frame(1, 0, 0) - frame(0, 0, 0)), ed.normalize(frame(0, 1, 0) - frame(0, 0, 0)), ed.normalize(frame(0, 0, 1) - frame(0, 0, 0)))
    g = extrude_poly('crescent_guard', [(0.0, -0.03), (0.012, -0.031), (0.022, -0.026), (0.03, 0.0), (0.022, 0.027), (0.012, 0.033), (0.0, 0.034), (-0.008, 0.016), (-0.01, 0.0), (-0.008, -0.016)],
                     0.018, frame(0.045, 0, 0), ex, ey, ez, bevel=0.0024, segs=2)
    out.append((g, 'silver'))
    bow = ed.polyline(np.array([frame(x, y, 0) for x, y in [(0.05, -0.024), (0.032, -0.058), (-0.015, -0.066), (-0.058, -0.042), (-0.068, -0.014)]]), 18)
    out.append((ed.tube('crescent_bow', bow, 0.0045, 8), 'silver'))
    # grip: core + cord wrap (the fist holds it at x 0)
    core = ed.lathe('crescent_grip', [[0.0128, 0.05], [0.0132, 0.0], [0.0138, -0.06]], 12, origin=frame(0, 0, 0), axis=ex)
    out.append((core, 'gripWrap'))
    out.append((ed.helix_wrap('crescent_wrap', frame(0.046, 0, 0), frame(-0.056, 0, 0), [[0, 0.0136], [1, 0.0142]], turns=8, width=0.0135, thick=0.0018, sides=8,
                              axes=(ey, ez), seed=7), 'gripWrap'))
    pom = ed.lathe('crescent_pommel', [[0.0, -0.087], [0.0105, -0.087], [0.014, -0.082], [0.021, -0.068], [0.017, -0.058], [0.0128, -0.056]], 14, origin=frame(0, 0, 0), axis=ex,
                   caps=(True, False))
    ed.shade(pom, 40)
    out.append((pom, 'silver'))
    out.append((ed.ellipsoid('crescent_bead', frame(-0.093, 0, 0), [0.0085, 0.0085, 0.0085], segs=(10, 6)), 'jade'))
    ring = [frame(-0.108 + math.cos(a) * 0.0085, math.sin(a) * 0.0085, 0) for a in np.linspace(0, TAU, 16, endpoint=False)]
    out.append((ed.sweep('crescent_ring', np.vstack([ring, ring[:1]]), 6, 0.0017, caps=False), 'silver'))
    # the four-point stars on the guard
    star = []
    for kk in range(8):
        a = kk / 8 * TAU; rr = 0.004 if kk % 2 else 0.011
        star.append((math.cos(a) * rr, math.sin(a) * rr))
    for sz in (1, -1):
        out.append((extrude_poly('crescent_star', star, 0.002, frame(0.06, 0.004, sz * 0.011), ex, ey, ez, bevel=0.0006, segs=1), 'frost'))
    return out


if __name__ == '__main__':
    print('iska_parts.py: helpers of heroes/iska.py (nothing to build)')
