# KAEL's hard pieces, built in their bone frames (game axes) and placed in Blender bind space through the rig:
#   saber(rig, LK)      참마대도 in the weaponR frame: EXACT length (ring end -0.334 .. point 1.6), grips (0, -0.17, -0.27,
#                       0.17, 0.56), sockets (base 0.12, tip 1.6) of WEAPON_SPECS.greatsword
# Every function returns {name: object} (looks assigned, per-vertex data written, no weights yet).

import math
import numpy as np
import bmesh
import edlib as ed
import kael_lib as KL

TAU = math.pi * 2
sstep = lambda a, b, x: ed.smoothstep(a, b, x)


# ---- the 참마대도 --------------------------------------------------------------------------------------------------------------
SX0, SX1, SXC = 0.075, 1.6, 1.2          # blade root (guard face), point, start of the clip


def saber_back(x):
    """Back (spine) line of the blade, +Y in the weapon frame (the kit saber's outline, refined)."""
    x = np.asarray(x, float)
    k = np.clip((x - SXC) / (SX1 - SXC), 0, 1)
    straight = ed.lerp(0.036, 0.058, sstep(SX0, SXC, x)) + 0.012 * np.exp(-(((x - (SXC - 0.035)) / 0.022) ** 2))
    clip = 0.058 * (1 - k) - 0.011 * np.sin(k * np.pi)
    return np.where(x <= SXC, straight, clip)


def saber_edge(x):
    """Cutting edge line, -Y (a broad belly swelling toward the point)."""
    x = np.asarray(x, float)
    t = (x - SX0) / (SX1 - SX0)
    belly = 0.05 + 0.04 * sstep(0.06, 0.7, t)
    tip = -0.09 * (1 - np.clip((t - 0.7) / 0.3, 0, 1) ** 2.2)
    return np.where(t < 0.7, -belly, tip)


def _wframe(rig, bone='weaponR'):
    R, o = KL.frame_mat(rig, bone)
    return R, o


def _place(R, o, q):
    q = np.asarray(q, float)
    return q @ R.T + o


def _extrude_outline(name, outline_yz, x0, x1, R, o, bevel=0.0015, segs=2):
    """A plate whose outline lies in the weapon's (y, z) plane, extruded from x0 to x1, edges bevelled."""
    bm = bmesh.new()
    a = [bm.verts.new(_place(R, o, [x0, y, z])) for y, z in outline_yz]
    b = [bm.verts.new(_place(R, o, [x1, y, z])) for y, z in outline_yz]
    n = len(outline_yz)
    bm.faces.new(a[::-1]); bm.faces.new(b)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], a[j], b[j], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=[e for e in bm.edges if e.calc_face_angle(0) > 0.6], offset=bevel, segments=segs, profile=0.5, affect='EDGES')
    me = ed.bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    obj = ed.bpy.data.objects.new(name, me); ed.link(obj)
    ed.shade(obj, 40)
    return obj


def saber(rig, LK, quality=1.0):
    """The great saber in the weaponR frame (+X along the blade, -Y the true edge, +-Z the flats)."""
    R, o = _wframe(rig)
    out = {}
    # ---- blade: faceted sections lofted along x ----------------------------------------------------------------------------
    xs = np.concatenate([np.linspace(SX0 + 0.003, 1.1, 24), np.linspace(1.12, SXC - 0.07, 2), np.linspace(SXC - 0.06, SXC - 0.012, 5),
                         np.linspace(SXC, SX1 - 0.006, 14), [SX1]])
    TH = lambda t: np.interp(t, [0, 0.7, 0.93, 1], [0.0072, 0.0052, 0.0034, 0.0004])
    rings, uv = [], []
    F0, F1 = 0.12, 1.02                                                    # blood groove extent (x)
    for x in xs:
        t = (x - SX0) / (SX1 - SX0)
        ys, ye = float(saber_back(x)), float(saber_edge(x))
        W = max(ys - ye, 0.0016)
        th = float(TH(t))
        kc = float(np.clip((x - SXC) / (SX1 - SXC), 0, 1))
        thb = th * 0.78 * (1 - kc) ** 0.8 + 0.0004 * kc                  # spine thickness: the clip becomes a false edge
        ch = min(0.0025, W * 0.04) * (1 - kc)                              # spine chamfer
        yr = ye + min(0.042, 0.34 * W)                                     # bevel line (the wide honed edge below it)
        kf = float(np.clip(min((x - F0) / 0.05, (F1 - x) / 0.09), 0, 1))
        yf = ys - 0.021 - 0.004 * t                                        # groove centre, running under the spine
        fw = 0.0062 * kf ** 0.5 + 0.0008; fd = 0.0021 * kf + 0.00012
        th_r = th * 0.86
        face = [(ys - ch, th), (yf + fw * 1.5, th), (yf + fw, th - fd * 0.35), (yf + fw * 0.45, th - fd), (yf - fw * 0.45, th - fd), (yf - fw, th - fd * 0.35),
                (yf - fw * 1.5, th * 0.995), ((yf - fw * 1.5 + yr) * 0.5, th * 0.94), (yr, th_r), (ye + 0.0016, 0.00055)]
        sec = [(ys, thb)] + face + [(ye, 0.0)] + [(y, -z) for y, z in reversed(face)] + [(ys, -thb)]
        rings.append([_place(R, o, [x, y, z]) for y, z in sec])
        uv.append([(x, (y - ye) / W) for y, z in sec])
    blade = ed.loft('saber_blade', np.array(rings), close=True, caps=(True, False))
    ed.shade(blade, 24)
    U = np.array(uv).reshape(-1, 2)
    ed.set_attr(blade, 'ed_uvw', np.stack([U[:, 0], np.clip(U[:, 1], 0, 1), np.full(len(U), 0.27)], axis=1), 'FLOAT_VECTOR')
    ed.assign_look(blade, LK['steel'])
    # the charred spine (faces whose normal points along +Y of the weapon) takes the scorched look: its cracks glow
    me = blade.data
    wy = R[:, 1]
    fn = np.array([np.dot(p.normal, wy) for p in me.polygons])
    fc = np.array([((np.array(p.center) - o) @ R)[0] for p in me.polygons])
    ed.assign_look(blade, LK['saberBack'], faces=np.nonzero((fn > 0.82) & (fc < SXC - 0.02))[0])
    out['blade'] = blade

    # ---- ember seam on the groove floor (both flats): hot core + halo, fading before the run-out -----------------------------
    seams = []
    for sgn in (1, -1):
        xsl = np.linspace(F0 + 0.03, F1 - 0.05, 24)
        pts, nrm, wid = [], [], []
        for x in xsl:
            t = (x - SX0) / (SX1 - SX0)
            ys = float(saber_back(x)); yf = ys - 0.021 - 0.004 * t
            kf = float(np.clip(min((x - F0) / 0.05, (F1 - x) / 0.09), 0, 1))
            th = float(TH(t)); fd = 0.0021 * kf
            pts.append(_place(R, o, [x, yf, sgn * (th - fd + 0.00035)]))
            nrm.append(R[:, 2] * sgn)
        sm = ed.ribbon('saber_seam%d' % (sgn > 0), np.array(pts), width=0.0068, normal=np.array(nrm), camber=0.05, nu=2)
        q = ed.get_attr(sm, 'ed_uv')
        across = np.abs(q[:, 0] - 0.5) * 2
        along = q[:, 1]
        xa = F0 + 0.03 + along * (F1 - 0.08 - F0)
        core = (1 - across) ** 1.6 * (0.62 + 0.38 * np.sin(xa * 29) * np.sin(xa * 8.3 + 0.7)) * (1 - sstep(0.62, 0.96, along)) * sstep(0.0, 0.06, along)
        KL.set_glow(sm, inlay=core, vein=0.5 * (1 - across))
        ed.assign_look(sm, LK['groove'])
        if sgn < 0:
            KL.flip(sm)
        seams.append(sm)
    out['seam'] = ed.join(seams, 'saber_seam')

    # ---- bronze collar (the mouth the blade grows from) + flame tongues licking onto the steel -----------------------------
    cx0, cx1 = SX0 - 0.016, SX0 + 0.052
    n_sec = 20
    rings = []
    for j, x in enumerate(np.linspace(cx0, cx1, 6)):
        ys, ye = float(saber_back(max(x, SX0))) + 0.0058, float(saber_edge(max(x, SX0))) - 0.0058
        th = 0.0118 * (1 - 0.1 * (x - cx0) / (cx1 - cx0))
        ring = []
        for i in range(n_sec):
            a = i / n_sec * TAU
            cy, cz = math.cos(a), math.sin(a)
            yy = (ys + ye) / 2 + (ys - ye) / 2 * np.sign(cy) * abs(cy) ** 0.35
            zz = th * np.sign(cz) * abs(cz) ** 0.5
            ring.append(_place(R, o, [x, yy, zz]))
        rings.append(ring)
    collar = ed.loft('saber_collar', np.array(rings), close=True, caps=(True, True))
    ed.bevel(collar, 0.0012, 1, 35)
    tongues = []
    for sgn in (1, -1):
        for (y0, y1, ln) in ((0.03, 0.006, 0.085), (0.002, -0.026, 0.12), (-0.03, -0.058, 0.075)):
            # flat flame tongue: a pointed, slightly curling plate lying on the blade face
            th0 = float(TH(0.03))
            outline = [(0.0, y0), (ln * 0.35, (y0 + y1) / 2 + (y0 - y1) * 0.42), (ln * 0.72, (y0 + y1) / 2 + (y0 - y1) * 0.12), (ln, (y0 + y1) / 2 + 0.006),
                       (ln * 0.62, (y0 + y1) / 2 - (y0 - y1) * 0.18), (ln * 0.3, (y0 + y1) / 2 - (y0 - y1) * 0.36), (0.0, y1)]
            pts = []
            for zl in (0.0, 0.0016):
                pts.append([_place(R, o, [cx1 - 0.004 + xx, yy, sgn * (th0 + 0.0004 + zl * (1 - 0.6 * xx / ln))]) for xx, yy in outline])
            bm = bmesh.new()
            va = [bm.verts.new(p_) for p_ in pts[0]]; vb = [bm.verts.new(p_) for p_ in pts[1]]
            bm.faces.new(vb if sgn > 0 else vb[::-1]); bm.faces.new(va[::-1] if sgn > 0 else va)
            m = len(outline)
            for i in range(m):
                jj = (i + 1) % m
                bm.faces.new((va[i], va[jj], vb[jj], vb[i]) if sgn > 0 else (va[jj], va[i], vb[i], vb[jj]))
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
            bmesh.ops.bevel(bm, geom=bm.edges[:], offset=0.0005, segments=1, profile=0.5, affect='EDGES')
            me = ed.bpy.data.meshes.new('tongue'); bm.to_mesh(me); bm.free()
            to = ed.bpy.data.objects.new('tongue', me); ed.link(to); ed.shade(to, 40)
            tongues.append(to)
    collar = ed.join([collar] + tongues, 'saber_collar')
    ed.assign_look(collar, LK['bronze'])
    out['collar'] = collar

    # ---- guard: a thick lobed oval plate with a raised bronze rim ----------------------------------------------------------
    gl = []
    for i in range(28):
        a = i / 28 * TAU
        r = 1 + 0.085 * math.cos(4 * a) + 0.03 * math.cos(8 * a)
        gl.append((math.cos(a) * 0.074 * r - 0.007, math.sin(a) * 0.043 * r))
    guard = _extrude_outline('saber_guard', gl, SX0 - 0.031, SX0 - 0.015, R, o, bevel=0.0028, segs=1)
    ed.assign_look(guard, LK['iron'])
    rim = []
    for s_ in (-1, 1):
        pts = [_place(R, o, [SX0 - 0.023 + s_ * 0.0085, y * 0.97, z * 0.97]) for y, z in gl]
        rim.append(ed.tube('saber_guardrim', np.array(pts + pts[:1]), 0.0022, 6, caps=False))
    rim = ed.join(rim, 'saber_guardrim')
    ed.assign_look(rim, LK['bronze'])
    out['guard'] = ed.join([guard, rim], 'saber_guard')

    # ---- hilt: oval core, diamond cord wrap (two flat cords wound in opposite directions), ferrules ------------------------
    GX0, GX1 = SX0 - 0.031, -0.255
    core_prof = [[0.0158, GX0], [0.0166, GX0 - 0.02], [0.0158, -0.06], [0.0154, -0.12], [0.0162, -0.2], [0.0172, GX1 + 0.01], [0.0168, GX1]]
    core = ed.lathe('saber_core', [[r, x] for r, x in core_prof], 12, origin=o, axis=R[:, 0])
    V = ed.verts_of(core); q = (V - o) @ R
    q[:, 1] *= 1.06; q[:, 2] *= 0.9
    ed.set_verts(core, _place(R, o, q))
    ed.assign_look(core, LK['leatherDark'])
    cords = []
    turns = 11.5
    for hand in (1, -1):
        m = int(turns * 13)
        xs_c = np.linspace(GX0 - 0.012, GX1 + 0.014, m)
        ang = hand * np.linspace(0, turns * TAU, m) + (0 if hand > 0 else math.pi)
        rr = np.interp(xs_c, [x for r, x in core_prof][::-1], [r for r, x in core_prof][::-1])
        # the cords pass over / under each other where they cross: a small radial wave
        lift = 0.0012 + 0.0007 * np.sin(2 * (np.linspace(0, turns * TAU, m)) + (0 if hand > 0 else math.pi))
        y = np.cos(ang) * (rr * 1.06 + lift); z = np.sin(ang) * (rr * 0.9 + lift)
        pts = _place(R, o, np.stack([xs_c, y, z], axis=1))
        nrm = ed.normalize(np.stack([np.zeros(m), np.cos(ang), np.sin(ang)], axis=1) @ R.T)
        c = ed.ribbon('saber_cord', pts, width=0.0118, normal=nrm, camber=0.12, nu=2)
        cords.append(c)
    cords = ed.join(cords, 'saber_cords')
    ed.assign_look(cords, LK['cord'])
    out['cords'] = cords
    fer = []
    for xf, r in ((GX0 - 0.004, 0.0205), (-0.086, 0.0195), (GX1 - 0.002, 0.0215)):
        fer.append(ed.lathe('saber_ferrule', [[r * 0.86, xf - 0.008], [r, xf - 0.006], [r * 1.04, xf], [r, xf + 0.006], [r * 0.86, xf + 0.008]], 14, origin=o, axis=R[:, 0]))
    fer = ed.join(fer, 'saber_ferrules')
    ed.assign_look(fer, LK['bronze'])
    out['core'] = ed.join([core, fer], 'saber_hilt')

    # ---- ring pommel (환두): a neck and a heavy ring in the blade plane; the ring end stays at x = -0.334 ------------------
    RX, RR = -0.298, 0.029
    neck = ed.lathe('saber_neck', [[0.0185, GX1 + 0.004], [0.0205, GX1 - 0.004], [0.0145, GX1 - 0.012], [0.0105, GX1 - 0.02]], 14, origin=o, axis=R[:, 0])
    ring_pts = [[RX + math.cos(a) * RR, math.sin(a) * RR, 0.0] for a in np.linspace(0, TAU, 21)[:-1]]
    sec = [(1.0, 0.0), (0.55, 0.85), (-0.55, 0.85), (-1.0, 0.0), (-0.55, -0.85), (0.55, -0.85)]
    ring = ed.sweep('saber_ring', _place(R, o, ring_pts), np.array(sec), radius=0.0074, up=R[:, 2])
    # three forged flame spurs on the ring's outer side
    spurs = []
    for a in (math.pi * 0.72, math.pi, math.pi * 1.28):
        base = np.array([RX + math.cos(a) * (RR + 0.004), math.sin(a) * (RR + 0.004), 0.0])
        tip = np.array([RX + math.cos(a) * (RR + 0.0085), math.sin(a) * (RR + 0.0085) + 0.006 * math.sin(a), 0.0])
        spurs.append(ed.capsule('saber_spur', _place(R, o, base), _place(R, o, tip), 0.0042, 0.0012, 6))
    ringo = ed.join([ring] + spurs, 'saber_ring')
    ed.assign_look(ringo, LK['iron'])
    ed.assign_look(neck, LK['bronze'])
    out['ring'] = ed.join([ringo, neck], 'saber_pommel')
    return out


def saber_strip(rig, LK):
    """The red cloth strip knotted through the ring pommel: two ribbons along the strip spring chain + a knot."""
    pts = rig.chain_points('strip')
    R, o = _wframe(rig)
    objs = []
    for k, (w, off, frac) in enumerate(((0.032, 0.006, 1.0), (0.026, -0.006, 0.78))):
        path = ed.polyline(pts, 14)
        n = max(4, int(len(path) * frac))
        p = path[:n] + R[:, 2] * off
        rb = ed.ribbon('strip%d' % k, p, width=[[0, w], [1, w * 0.72]], normal=R[:, 2], camber=0.14, nu=2)
        q = ed.get_attr(rb, 'ed_uv')
        ed.set_attr(rb, 'ed_uv', np.stack([q[:, 0], q[:, 1] * frac, q[:, 2]], axis=1), 'FLOAT_VECTOR')
        objs.append(rb)
    kn = ed.ellipsoid('strip_knot', _place(R, o, [-0.323, -0.018, 0.0]), [0.011, 0.014, 0.016], R, (10, 7))
    q = np.zeros((len(kn.data.vertices), 3))
    ed.set_attr(kn, 'ed_uv', q, 'FLOAT_VECTOR')
    strip = ed.join([kn] + objs, 'saber_strip')
    ed.assign_look(strip, LK['strip'])
    return strip


# ---- beast-face pauldron (deltoidR frame) ---------------------------------------------------------------------------------

def blade_in_frame(rig, bone, poses=('idle', 'walk', 'walk2'), xs=(0.05, 0.75), n=16):
    """Where the resting saber passes in `bone`'s frame for the given sampled poses: list of (back line, edge line), each
    (n, 3) points of the blade's back (y = +saber_back) and edge (y = saber_edge) in the bone's game frame."""
    M = lambda a: np.array(a, dtype=float).reshape(4, 4).T
    out = []
    for pose in poses:
        Pz = rig.data['poses'][pose]['bones']
        W, D = M(Pz['weaponR']), M(Pz[bone])
        T = np.linalg.inv(D) @ W
        X = np.linspace(xs[0], xs[1], n)
        back = np.stack([X, saber_back(X), np.zeros(n), np.ones(n)], axis=1) @ T.T
        edge = np.stack([X, saber_edge(X), np.zeros(n), np.ones(n)], axis=1) @ T.T
        out.append((back[:, :3], edge[:, :3]))
    return out


def _face_frame(F):
    F = ed.normalize(np.asarray(F, float))
    up = ed.normalize(np.array([0, 1.0, 0]) - F * F[1])
    side = np.cross(up, F)
    return F, up, side


def _torus(q, c, axis, R, r):
    p = q - np.asarray(c, float)
    h = p @ axis
    rho = np.linalg.norm(p - h[:, None] * axis[None, :], axis=1)
    return np.sqrt((rho - R) ** 2 + h ** 2) - r


def pauldron(rig, LK, h=0.0024):
    """
    The beast-face pauldron (수면 견갑) on deltoidR: a forged iron cap over the OUTER half of the right shoulder, a snarling
    guardian beast on its lateral face (heavy scowling brows, deep eye pits with ember eyes, a broad snout with flared
    nostrils, a snarling upper lip over fangs, a bronze ring in the open jaws, cheek ruffs and a mane of forged flame
    tongues sweeping back), a rolled rim and two hanging lames. The saber's resting path (idle / walk) is carved out of
    the top as a cradle, so the blade lies on the coat over the shoulder, framed by the mane.
    Returns {'shell', 'eyes', 'fangs', 'ring'} objects (Blender bind space).
    """
    C = np.array([-0.006, -0.016, 0.03])
    RC = 0.13
    A = ed.normalize(np.array([0.08, 0.36, 1.0]))         # cap axis: outward and up
    F, up, side = _face_frame([0.42, -0.2, 1.0])           # the beast looks out, a little forward and down
    F0 = C + F * RC

    def fl(a, b, c):                                        # face coords -> deltoid frame
        return F0 + up * a + side * b + F * c

    blades = blade_in_frame(rig, 'deltoidR')

    def fn(q):
        p = q - C
        L = np.linalg.norm(p, axis=1)
        # cap shell: sphere band, thickness 9 mm, cut to the outer cap (chamfered rim)
        shell = np.abs(L - RC) - 0.0045
        cut = -(p @ A - 0.03)
        d = KL.cmax(shell, cut, 0.004)
        # rolled rim along the cut
        c0 = C + A * 0.03
        Rr = math.sqrt(RC ** 2 - 0.03 ** 2)
        d = KL.smin(d, _torus(q, c0, A, Rr + 0.002, 0.0062), 0.004)
        # ---- the beast: broad forged masses (brows, cheeks, muzzle lobes, flat nose, jaws), smooth-joined -------------------
        rot = np.stack([up, side, F], axis=1)
        E = lambda a, b, c, r, k=None: (KL.sd_ell(q, fl(a, b, c), r, rot), k)
        feat = [E(-0.024, 0, -0.012, [0.078, 0.092, 0.034])]                  # face plate rising out of the cap
        for s_ in (1, -1):
            ta = 0.55
            tilt = np.stack([up * math.cos(ta) + side * s_ * math.sin(ta), side * math.cos(ta) - up * s_ * math.sin(ta), F], axis=1)
            bc = fl(0.03, s_ * 0.042, 0.017)
            brow = KL.sd_ell(q, bc, [0.017, 0.047, 0.024], tilt)
            brow = KL.cmax(brow, (q - (bc + tilt[:, 0] * 0.011)) @ ed.normalize(tilt[:, 0] + F * 0.35), 0.006)   # hard top facet
            feat.append((brow, None))                                                                            # scowling brow
            feat.append(E(-0.03, s_ * 0.055, 0.006, [0.03, 0.032, 0.021]))                                     # cheek
            feat.append(E(-0.054, s_ * 0.024, 0.034, [0.018, 0.026, 0.019]))                                    # snarling lip lobe
            feat.append(E(-0.036, s_ * 0.028, 0.041, [0.012, 0.014, 0.012]))                                    # flared nostril wing
            feat.append(E(0.05, s_ * 0.078, -0.006, [0.022, 0.017, 0.014]))                                     # brow horn root
            feat.append((KL.sd_capsule(q, fl(-0.04, s_ * 0.04, 0.03), fl(-0.012, s_ * 0.07, 0.008), 0.005, 0.003), None))   # snarl fold
        feat.append(E(0.0, 0, 0.03, [0.042, 0.017, 0.017]))                                                    # nose bridge
        feat.append(E(-0.03, 0, 0.042, [0.015, 0.03, 0.014]))                                                  # broad flat nose pad
        feat.append(E(-0.104, 0, 0.012, [0.017, 0.05, 0.024]))                                                 # lower jaw
        beast = None
        for dd, kk in feat:
            beast = dd if beast is None else KL.smin(beast, dd, 0.009)
        d = KL.smin(d, beast, 0.012)
        # snarl wrinkles over the bridge, a furrow between the brows
        for k in range(3):
            d = KL.smin(d, KL.sd_capsule(q, fl(0.004 - k * 0.01, -0.017, 0.044 + k * 0.002), fl(0.004 - k * 0.01, 0.017, 0.044 + k * 0.002), 0.0035), 0.003)
        d = KL.smax(d, -KL.sd_ell(q, fl(0.04, 0, 0.034), [0.026, 0.004, 0.012], rot), 0.002)
        # ---- mane: forged flame curls framing the top and sides of the face, swept hard back ---------------------------------
        mane = []
        for k, ang in enumerate(np.linspace(-2.05, 2.05, 9)):
            r0 = 0.096 + 0.01 * (k % 2)
            base = fl(0.01 + r0 * math.cos(ang) * 0.85, r0 * math.sin(ang) * 1.02, -0.026)
            outv = ed.normalize(up * math.cos(ang) + side * math.sin(ang))
            ln = 0.022 + 0.01 * (k % 2)
            tip = base + outv * ln - F * 0.07 + up * 0.016
            mid = base + outv * ln * 0.7 - F * 0.025
            mane.append(KL.sd_path(q, [base, mid, tip], [0.02, 0.0145, 0.003]))
        # back ruff behind the shoulder
        for k, b0 in enumerate((-0.07, -0.03, 0.01)):
            base = C + ed.normalize(np.array([-0.6, 0.3, 0.72])) * RC * 0.97 + np.array([0, b0 * 0.7, 0])
            tip = base + ed.normalize(np.array([-0.9, 0.2 - k * 0.12, 0.3])) * 0.06
            mane.append(KL.sd_path(q, [base, (base + tip) / 2 + np.array([0, 0.01, 0.012]), tip], [0.018, 0.012, 0.003]))
        d = KL.smin(d, KL.union(mane, 0.008), 0.012)
        # ---- cuts: eye pits (slanted), nostrils, the open snarling mouth --------------------------------------------------
        for s_ in (1, -1):
            te = 0.4
            tilt = np.stack([up * math.cos(te) + side * s_ * math.sin(te), side * math.cos(te) - up * s_ * math.sin(te), F], axis=1)
            d = KL.smax(d, -KL.sd_ell(q, fl(0.008, s_ * 0.041, 0.03), [0.011, 0.02, 0.026], tilt), 0.003)
            d = KL.smax(d, -KL.sd_ell(q, fl(-0.04, s_ * 0.016, 0.06), [0.0062, 0.0085, 0.014], rot), 0.002)
        d = KL.smax(d, -KL.sd_ell(q, fl(-0.09, 0, 0.034), [0.018, 0.043, 0.04], rot), 0.004)
        # the medial top of the cap goes: the blade rests on the coat there (a chamfered cut, below the saber's path)
        npl = ed.normalize(np.array([0.0, 0.6, -1.0]))
        d = KL.cmax(d, (q - np.array([0.0, 0.02, 0.05])) @ npl, 0.006)
        # inside of the cap: hollow (the shoulder goes in there)
        d = KL.smax(d, -(L - (RC - 0.0045)), 0.002)
        # ---- the cradle: the resting saber's path (idle / walk) with clearance ---------------------------------------------
        for back, edge in blades:
            d = KL.smax(d, -KL.sd_path(q, back, 0.034), 0.018)
            d = KL.smax(d, -KL.sd_path(q, (back + edge) / 2, 0.034), 0.018)
        return d

    rigM = rig
    shell = KL.sdf_mesh('pauldron', fn, [-0.17, -0.2, -0.06], [0.2, 0.2, 0.26], h=h, frame='deltoidR', rig=rigM, project=4)
    ed.assign_look(shell, LK['iron'])
    out = {'shell': shell}
    # eyes (ember, deep in the pits), fangs (old bone), the bronze ring in the jaws
    R, o = KL.frame_mat(rig, 'deltoidR')
    toB = lambda p: R @ p + o
    rotB = R @ np.stack([up, side, F], axis=1)
    eyes = [ed.ellipsoid('pd_eye', toB(fl(0.007, s_ * 0.041, 0.014)), [0.0075, 0.013, 0.008], rotB, (12, 8)) for s_ in (1, -1)]
    out['eyes'] = ed.join(eyes, 'pauldron_eyes')
    ed.assign_look(out['eyes'], LK['eye'])
    fangs = []
    for s_, a0, a1, r0, b in ((1, -0.074, -0.112, 0.0072, 0.029), (-1, -0.074, -0.112, 0.0072, 0.029), (1, -0.106, -0.082, 0.0058, 0.017), (-1, -0.106, -0.082, 0.0058, 0.017)):
        fangs.append(ed.capsule('pd_fang', toB(fl(a0, s_ * b, 0.044)), toB(fl(a1, s_ * (b - 0.004), 0.05)), r0, 0.0012, 10))
    for b in (-0.008, 0.008):
        fangs.append(ed.capsule('pd_tooth', toB(fl(-0.076, b, 0.044)), toB(fl(-0.086, b, 0.047)), 0.004, 0.0016, 8))
    out['fangs'] = ed.join(fangs, 'pauldron_fangs')
    ed.assign_look(out['fangs'], LK['fang'])
    ringc = toB(fl(-0.118, 0, 0.05))
    ring = ed.sweep('pd_ring', np.array([ringc + R @ (up * math.cos(t) * 0.03 + side * math.sin(t) * 0.03) for t in np.linspace(0, TAU, 25)[:-1]] * 1),
                    8, 0.0052, close=True)
    # close the ring loop: sweep a closed path
    out['ring'] = ring
    ed.assign_look(ring, LK['bronze'])
    return out


# ---- 귀면: the iron demon half-mask (head frame) ---------------------------------------------------------------------------

def _face_base(q, K):
    """Smooth face mass under the mask (head frame): cranium, face, brow, cheekbones, nose bridge, upper jaw."""
    d = KL.sd_ell(q, np.array([-0.006, 0.122, 0]) * K, np.array([0.098, 0.104, 0.078]) * K)
    d = KL.smin(d, KL.sd_ell(q, np.array([0.045, 0.065, 0]) * K, np.array([0.06, 0.07, 0.058]) * K), 0.03 * K)
    d = KL.smin(d, KL.sd_ell(q, np.array([0.087, 0.137, 0]) * K, np.array([0.02, 0.016, 0.058]) * K), 0.014 * K)
    for z in (1, -1):
        d = KL.smin(d, KL.sd_ell(q, np.array([0.065, 0.098, z * 0.047]) * K, np.array([0.026, 0.018, 0.026]) * K), 0.014 * K)
    d = KL.smin(d, KL.sd_capsule(q, np.array([0.101, 0.118, 0]) * K, np.array([0.113, 0.076, 0]) * K, 0.009 * K, 0.0135 * K), 0.012 * K)
    return d


def mask(rig, LK, h=0.0016):
    """
    The snarling iron demon half-mask: forehead to upper lip, wrapping to the temples. Heavy scowling brows with hard
    top facets and a cleft between them, slanted eye slits, a broad flared nose with snarl wrinkles, sharp cheek ridges
    sweeping to the temples, a curled upper lip with forged fangs hanging over the mouth, two short horns swept back
    from the temples; a rolled edge all round. Returns {'mask', 'eyes'} (Blender bind space, head frame authored).
    """
    K = rig.K
    k = K

    def fn(q):
        B = _face_base(q, K)
        outer = B - 0.0155 * k
        inner = B - 0.0045 * k
        d = np.maximum(outer, -inner)
        # outline: the forehead top, the upper-lip line rising to the cheeks, the temples
        x, y, z = q[:, 0], q[:, 1], q[:, 2]
        top = y - (0.183 * k + 0.014 * k * np.exp(-z ** 2 / 0.0003) - 0.9 * z ** 2)
        bot = (0.052 * k + 1.6 * z ** 2) - y
        back = (0.028 * k + 0.5 * np.maximum(y - 0.16 * k, 0) - 0.25 * np.maximum(0.1 * k - y, 0)) - x
        d = KL.cmax(d, top, 0.004)
        d = KL.cmax(d, bot, 0.004)
        d = KL.cmax(d, back, 0.004)
        feat = []
        for s_ in (1, -1):
            # scowling brow: an inner low end, an outer high end, a hard upper facet
            a = np.array([0.126, 0.141, s_ * 0.013]) * k; b = np.array([0.098, 0.17, s_ * 0.07]) * k
            br = KL.sd_capsule(q, a, b, 0.0155 * k, 0.011 * k)
            br = KL.cmax(br, (q - (a + b) / 2 - np.array([0, 0.007, 0]) * k) @ ed.normalize(np.array([0.45, 1.0, s_ * 0.25])), 0.003)
            feat.append(br)
            # cheek ridge: from the nostril wing to the temple
            feat.append(KL.sd_capsule(q, np.array([0.128, 0.077, s_ * 0.026]) * k, np.array([0.083, 0.118, s_ * 0.074]) * k, 0.0062 * k, 0.0035 * k))
            feat.append(KL.sd_capsule(q, np.array([0.117, 0.064, s_ * 0.042]) * k, np.array([0.074, 0.088, s_ * 0.079]) * k, 0.005 * k, 0.003 * k))
            # flared nostril wing
            feat.append(KL.sd_ell(q, np.array([0.128, 0.078, s_ * 0.021]) * k, np.array([0.011, 0.011, 0.012]) * k))
            # curled upper lip
            feat.append(KL.sd_capsule(q, np.array([0.133, 0.062, s_ * 0.004]) * k, np.array([0.112, 0.064, s_ * 0.05]) * k, 0.0068 * k, 0.004 * k))
            # horn from the temple, swept back and up
            hp = [np.array([0.076, 0.176, s_ * 0.075]) * k, np.array([0.042, 0.222, s_ * 0.1]) * k, np.array([-0.02, 0.262, s_ * 0.118]) * k]
            feat.append(KL.sd_path(q, hp, [0.017 * k, 0.0105 * k, 0.0025 * k]))
        # nose: bridge ridge + broad tip, snarl wrinkles
        feat.append(KL.sd_capsule(q, np.array([0.126, 0.138, 0]) * k, np.array([0.14, 0.095, 0]) * k, 0.0085 * k, 0.012 * k))
        feat.append(KL.sd_ell(q, np.array([0.137, 0.083, 0]) * k, np.array([0.015, 0.016, 0.02]) * k))
        for i in range(2):
            yy = (0.112 - i * 0.011) * k
            feat.append(KL.sd_capsule(q, np.array([0.14 - i * 0.002, yy, -0.016]) * k, np.array([0.14 - i * 0.002, yy, 0.016]) * k, 0.0032 * k))
        # forehead ridge between the brows
        feat.append(KL.sd_capsule(q, np.array([0.124, 0.152, 0]) * k, np.array([0.112, 0.183, 0]) * k, 0.0085 * k, 0.006 * k))
        d = KL.smin(d, KL.union(feat, 0.006 * k), 0.008 * k)
        # cuts: slanted eye slits, nostrils, the cleft between the brows
        for s_ in (1, -1):
            ang = 0.32 * s_
            rot = np.array([[1, 0, 0], [0, math.cos(ang), -math.sin(ang)], [0, math.sin(ang), math.cos(ang)]])
            d = KL.smax(d, -KL.sd_ell(q, np.array([0.12, 0.121, s_ * 0.036]) * k, np.array([0.04, 0.0072, 0.019]) * k, rot), 0.0025 * k)
            d = KL.smax(d, -KL.sd_ell(q, np.array([0.142, 0.072, s_ * 0.011]) * k, np.array([0.01, 0.0045, 0.006]) * k), 0.0015 * k)
        d = KL.smax(d, -KL.sd_ell(q, np.array([0.13, 0.152, 0]) * k, np.array([0.02, 0.012, 0.0028]) * k), 0.0015 * k)
        # the face inside stays clear
        d = KL.smax(d, -(B - 0.0028 * k), 0.001)
        return d

    obj = KL.sdf_mesh('mask', fn, np.array([-0.04, 0.03, -0.15]) * k, np.array([0.175, 0.27, 0.15]) * k, h=h, frame='head', rig=rig, project=4)
    ed.assign_look(obj, LK['iron'])
    # forged fangs hanging from the curled lip over the mouth (iron, worn bright at the tips)
    R, o = KL.frame_mat(rig, 'head')
    toB = lambda p: R @ (np.asarray(p, float) * k) + o
    fangs = []
    for s_, z0, ln, r0 in ((1, 0.024, 0.036, 0.0066), (-1, 0.024, 0.036, 0.0066), (1, 0.009, 0.016, 0.0042), (-1, 0.009, 0.016, 0.0042)):
        fangs.append(ed.capsule('mk_fang', toB([0.128, 0.06, s_ * z0]), toB([0.127, 0.06 - ln, s_ * (z0 - 0.002)]), r0, 0.0012, 10))
    fangs = ed.join(fangs, 'mask_fangs')
    ed.assign_look(fangs, LK['fang'])
    # ember eyes behind the slits
    eyes = [ed.ellipsoid('mk_eye', toB([0.106, 0.12, s_ * 0.035]), np.array([0.006, 0.0055, 0.014]) * k, R @ np.array([[1, 0, 0], [0, math.cos(0.32 * s_), -math.sin(0.32 * s_)], [0, math.sin(0.32 * s_), math.cos(0.32 * s_)]]), (12, 8)) for s_ in (1, -1)]
    eyes = ed.join(eyes, 'mask_eyes')
    ed.assign_look(eyes, LK['eye'])
    return {'mask': obj, 'fangs': fangs, 'eyes': eyes}
