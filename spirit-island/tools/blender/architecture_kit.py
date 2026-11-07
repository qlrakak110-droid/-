"""architecture_kit — hard-surface mesh builder for the village (architecture workstream).

Everything is authored in GAME coordinates (x right, y up, z toward the viewer / house front); the kit converts to
Blender's Z-up frame (bx, by, bz) = (x, -z, y) so the glTF exporter (+Y up) hands the game exactly these coordinates.

A Bin collects the geometry of one material: shared vertices (so vertex AO interpolates smoothly across a wall), faces,
per-loop UVs (in texture tiles) and per-vertex data:  COLOR_0 = (R ambient occlusion, G per-piece variation,
B grime mask, A 1). Pieces are convex prisms ("beams" with chamfered arrises), lathed solids, rubble stones, grids.
"""
import bpy, bmesh, math, random, os, sys
from mathutils import Vector, Matrix, Euler, noise
from mathutils.bvhtree import BVHTree


_DATA = {}


def V3(x, y=None, z=None):
    if y is None: return Vector(x)
    return Vector((x, y, z))


def to_b(p):
    return (p[0], -p[2], p[1])


class Bin:
    def __init__(self, name):
        self.name = name; self.V = []; self.F = []; self.UV = []; self.VAR = []; self.GR = []; self.COL = []
        self._key = {}

    def vert(self, p, var=0.5, key=None, col=None):
        if key is not None and key in self._key: return self._key[key]
        self.V.append(Vector(p)); self.VAR.append(var); self.GR.append(None); self.COL.append(col)
        i = len(self.V) - 1
        if key is not None: self._key[key] = i
        return i

    def face(self, idx, uvs, outward=None):
        """add a polygon; if `outward` (a direction) is given the winding is fixed so the normal points along it"""
        if outward is not None and len(idx) >= 3:
            n = poly_normal([self.V[i] for i in idx])
            if n.dot(Vector(outward)) < 0: idx = list(reversed(idx)); uvs = list(reversed(uvs))
        self.F.append(list(idx)); self.UV.append([tuple(u) for u in uvs])

    def __len__(self): return len(self.F)


def world_uv(pts, tile):
    """planar projection along the face's dominant axis, horizontal texture axis kept horizontal in the world"""
    n = poly_normal(pts); ax = max(range(3), key=lambda k: abs(n[k]))
    if ax == 0: return [(p.z / tile, p.y / tile) for p in pts]
    if ax == 2: return [(p.x / tile, p.y / tile) for p in pts]
    return [(p.x / tile, p.z / tile) for p in pts]


def poly_normal(pts):
    n = Vector((0, 0, 0))
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        n.x += (a.y - b.y) * (a.z + b.z); n.y += (a.z - b.z) * (a.x + b.x); n.z += (a.x - b.x) * (a.y + b.y)
    return n.normalized() if n.length > 1e-12 else n


class Kit:
    def __init__(self, seed=1):
        self.bins = {}; self.rng = random.Random(seed)

    def bin(self, name):
        if name not in self.bins: self.bins[name] = Bin(name)
        return self.bins[name]

    # ------------------------------------------------------------ prisms
    def prism(self, mat, p0, p1, w, d, nrm, ch=0.0, var=None, uv=(0.5, 2.0), uvoff=None, taper=1.0, cap0=True, cap1=True, wuv=None):
        """convex prism from p0 to p1: cross-section w (side) x d (along nrm), arrises chamfered by ch.
        UVs: sides u = around the profile / uv[0], v = along the axis / uv[1] (wood grain runs along v)."""
        B = self.bin(mat); r = self.rng
        p0 = Vector(p0); p1 = Vector(p1)
        a = p1 - p0; L = a.length
        if L < 1e-6: return
        a.normalize()
        n = Vector(nrm); n = (n - a * n.dot(a))
        if n.length < 1e-6: n = a.orthogonal()
        n.normalize(); s = a.cross(n).normalized()
        hw, hd = w / 2, d / 2
        c = min(ch, hw * 0.45, hd * 0.45)
        if c > 1e-4:
            prof = [(hw - c, hd), (-hw + c, hd), (-hw, hd - c), (-hw, -hd + c), (-hw + c, -hd), (hw - c, -hd), (hw, -hd + c), (hw, hd - c)]
        else:
            prof = [(hw, hd), (-hw, hd), (-hw, -hd), (hw, -hd)]
        var = r.random() if var is None else var
        uo = uvoff if uvoff is not None else (r.random(), r.random())
        ring0 = [B.vert(p0 + s * x + n * y, var) for x, y in prof]
        ring1 = [B.vert(p1 + (s * x + n * y) * taper, var) for x, y in prof]
        ctr = (p0 + p1) / 2
        per = [0.0]
        for i in range(len(prof)):
            x0, y0 = prof[i]; x1, y1 = prof[(i + 1) % len(prof)]
            per.append(per[-1] + math.hypot(x1 - x0, y1 - y0))
        for i in range(len(prof)):
            j = (i + 1) % len(prof)
            idx = [ring0[i], ring0[j], ring1[j], ring1[i]]
            u0 = per[i] / uv[0] + uo[0]; u1 = per[i + 1] / uv[0] + uo[0]
            uvs = [(u0, uo[1]), (u1, uo[1]), (u1, uo[1] + L / uv[1]), (u0, uo[1] + L / uv[1])]
            fc = sum((B.V[k] for k in idx), Vector()) / 4
            if wuv: uvs = world_uv([B.V[k] for k in idx], wuv)
            B.face(idx, uvs, outward=fc - (ctr + a * (fc - ctr).dot(a)))
        for ring, cap, sgn in ((ring0, cap0, -1), (ring1, cap1, 1)):
            if not cap: continue
            uvs = [(x / 0.5 + uo[0], y / 0.5 + uo[1]) for x, y in prof]
            if wuv: uvs = world_uv([B.V[k] for k in ring], wuv)
            B.face(list(ring), uvs, outward=a * sgn)

    def box(self, mat, c, size, rot=(0, 0, 0), ch=0.0, var=None, uv=(0.5, 2.0), uvoff=None, wuv=None):
        """axis-aligned (then rotated by game-space Euler XYZ) box built as a prism along its longest side"""
        c = Vector(c); R = Euler(rot, 'XYZ').to_matrix()
        axes = [R @ Vector((1, 0, 0)), R @ Vector((0, 1, 0)), R @ Vector((0, 0, 1))]
        order = sorted(range(3), key=lambda i: -size[i])
        ia, iw, idp = order[0], order[1], order[2]
        a = axes[ia] * size[ia] / 2
        self.prism(mat, c - a, c + a, size[iw], size[idp], axes[idp], ch=ch, var=var, uv=uv, uvoff=uvoff, wuv=wuv)

    # ------------------------------------------------------------ polygons in a frame
    def poly(self, mat, pts, uvs, outward, var=0.5, keyed=False):
        B = self.bin(mat)
        idx = [B.vert(p, var, key=(mat, round(p[0], 4), round(p[1], 4), round(p[2], 4)) if keyed else None) for p in pts]
        B.face(idx, uvs, outward=outward)

    # ------------------------------------------------------------ lathe (revolved profile) around a vertical axis
    def lathe(self, mat, c, prof, seg=16, var=None, uv=(1.0, 1.0), cap_top=False, cap_bot=False, phase=0.0, squash=(1.0, 1.0), keyed=True):
        """prof: list of (radius, y) from bottom to top; revolve around the y axis at c. UV u = angle * mean radius / uv[0],
        v = profile arc length / uv[1]."""
        B = self.bin(mat); r = self.rng; var = r.random() if var is None else var
        c = Vector(c)
        rows = []
        for (rad, y) in prof:
            row = []
            for k in range(seg + 1):
                t = (k % seg) / seg * 2 * math.pi + phase
                row.append(c + Vector((math.cos(t) * rad * squash[0], y, math.sin(t) * rad * squash[1])))
            rows.append(row)
        arc = [0.0]
        for i in range(1, len(prof)): arc.append(arc[-1] + math.hypot(prof[i][0] - prof[i - 1][0], prof[i][1] - prof[i - 1][1]))
        rm = max(0.05, sum(p[0] for p in prof) / len(prof))
        ids = []
        for i, row in enumerate(rows):
            ids.append([B.vert(p, var) for p in row[:seg]])
        for i in range(len(rows) - 1):
            for k in range(seg):
                k2 = (k + 1) % seg
                idx = [ids[i][k], ids[i][k2], ids[i + 1][k2], ids[i + 1][k]]
                u0 = k / seg * 2 * math.pi * rm / uv[0]; u1 = (k + 1) / seg * 2 * math.pi * rm / uv[0]
                uvs = [(u0, arc[i] / uv[1]), (u1, arc[i] / uv[1]), (u1, arc[i + 1] / uv[1]), (u0, arc[i + 1] / uv[1])]
                a0 = rows[i][k]; a1 = rows[i][k2]; b1 = rows[i + 1][k2]
                # outward = radial component, unless the profile folds back (rim lips) - use the face normal sign test
                mid = (rows[i][k] + rows[i + 1][k2]) / 2
                rad_dir = Vector((mid.x - c.x, 0, mid.z - c.z))
                dr = prof[i + 1][0] - prof[i][0]; dy = prof[i + 1][1] - prof[i][1]
                # outward normal of the profile segment (in the r-y plane): (dy, -dr) rotated into the radial direction
                o = rad_dir.normalized() * dy + Vector((0, -dr, 0)) if rad_dir.length > 1e-6 else Vector((0, -dr, 0))
                if o.length < 1e-9: o = rad_dir
                B.face(idx, uvs, outward=o)
        if cap_top:
            cc = B.vert(c + Vector((0, prof[-1][1], 0)), var)
            for k in range(seg):
                k2 = (k + 1) % seg
                B.face([ids[-1][k], ids[-1][k2], cc], [(0, 0), (0.1, 0), (0.05, 0.1)], outward=(0, 1, 0))
        if cap_bot:
            cc = B.vert(c + Vector((0, prof[0][1], 0)), var)
            for k in range(seg):
                k2 = (k + 1) % seg
                B.face([ids[0][k], ids[0][k2], cc], [(0, 0), (0.1, 0), (0.05, 0.1)], outward=(0, -1, 0))

    # ------------------------------------------------------------ tube along a polyline (pipes, rods, rings)
    def tube(self, mat, pts, rad, seg=8, var=None, uv=(0.3, 1.0), closed=False):
        B = self.bin(mat); var = self.rng.random() if var is None else var
        pts = [Vector(p) for p in pts]
        rings = []; along = [0.0]
        for i, p in enumerate(pts):
            if closed: t = (pts[(i + 1) % len(pts)] - pts[i - 1])
            else: t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)])
            t.normalize(); n = t.orthogonal().normalized(); b = t.cross(n)
            rings.append([B.vert(p + (n * math.cos(k / seg * 2 * math.pi) + b * math.sin(k / seg * 2 * math.pi)) * rad, var) for k in range(seg)])
            if i: along.append(along[-1] + (pts[i] - pts[i - 1]).length)
        npts = len(pts) if closed else len(pts) - 1
        for i in range(npts):
            i2 = (i + 1) % len(pts)
            for k in range(seg):
                k2 = (k + 1) % seg
                idx = [rings[i][k], rings[i][k2], rings[i2][k2], rings[i2][k]]
                fc = sum((B.V[j] for j in idx), Vector()) / 4
                axis_c = (pts[i] + pts[i2]) / 2
                v0 = along[i] / uv[1]; v1 = (along[i2] if i2 else along[-1] + (pts[0] - pts[-1]).length) / uv[1]
                B.face(idx, [(k / seg * 2 * math.pi * rad / uv[0], v0), ((k + 1) / seg * 2 * math.pi * rad / uv[0], v0), ((k + 1) / seg * 2 * math.pi * rad / uv[0], v1), (k / seg * 2 * math.pi * rad / uv[0], v1)], outward=fc - axis_c)

    # ------------------------------------------------------------ rubble stone (displaced, flattened icosphere)
    def stone(self, mat, c, size, rot_y=0.0, seed=0, sub=1, rough=0.22, var=None, flat_bottom=None, tile=2.0):
        B = self.bin(mat); r = random.Random(seed); var = r.random() if var is None else var
        bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
        R = Euler((0, rot_y, 0), 'XYZ').to_matrix(); c = Vector(c)
        off = Vector((r.random() * 50, r.random() * 50, r.random() * 50))
        idmap = {}
        for v in bm.verts:
            p = v.co.copy()
            d = 1 + rough * (noise.noise(p * 1.3 + off)) + rough * 0.4 * noise.noise(p * 3.1 + off)
            # boxier than a sphere: push toward a rounded cube
            q = Vector((math.copysign(abs(p.x) ** 0.7, p.x), math.copysign(abs(p.y) ** 0.7, p.y), math.copysign(abs(p.z) ** 0.7, p.z)))
            p = (p * 0.4 + q * 0.6) * d
            p = Vector((p.x * size[0] / 2, p.y * size[1] / 2, p.z * size[2] / 2))
            if flat_bottom is not None and p.y < -size[1] / 2 * flat_bottom: p.y = -size[1] / 2 * flat_bottom
            wp = c + R @ p
            idmap[v.index] = B.vert(wp, var)
        for f in bm.faces:
            ids = [idmap[v.index] for v in f.verts]
            pts = [B.V[i] for i in ids]
            n = poly_normal(pts)
            ax = max(range(3), key=lambda k: abs(n[k]))
            uvs = [((p.z if ax == 0 else p.x) / tile, (p.z if ax == 1 else p.y) / tile) for p in pts]
            fc = sum(pts, Vector()) / len(pts)
            B.face(ids, uvs, outward=fc - c)
        bm.free()

    # ------------------------------------------------------------ finalize
    def build(self, prefix, meta=None, collection=None):
        """turn every bin into a Blender object '<prefix>_<mat>'; returns the objects"""
        objs = []
        for name, B in self.bins.items():
            if not B.F: continue
            me = bpy.data.meshes.new(f'{prefix}_{name}')
            me.from_pydata([to_b(p) for p in B.V], [], B.F)
            uvl = me.uv_layers.new(name='UVMap')
            li = 0
            for f, uvs in zip(me.polygons, B.UV):
                for k in range(f.loop_total):
                    uvl.data[f.loop_start + k].uv = uvs[k] if k < len(uvs) else (0, 0)
            me.validate(clean_customdata=False)
            me.update()
            ob = bpy.data.objects.new(f'{prefix}_{name}', me)
            (collection or bpy.context.scene.collection).objects.link(ob)
            for p in me.polygons: p.use_smooth = True
            try:
                me.use_auto_smooth = True; me.auto_smooth_angle = math.radians(32)
            except Exception: pass
            ob['bin'] = name
            _DATA[ob.name] = (list(B.VAR), [list(c) if c else [-1, -1, -1] for c in B.COL])
            objs.append(ob)
        self.bins = {}
        return objs


def combined_bvh(objs):
    verts = []; polys = []
    for o in objs:
        base = len(verts); mw = o.matrix_world
        verts.extend(mw @ v.co for v in o.data.vertices)
        polys.extend([base + i for i in p.vertices] for p in o.data.polygons)
    return BVHTree.FromPolygons(verts, polys, epsilon=0.0)


def bake_colors(objs, occluders=None, rays=24, dist=1.4, strength=1.0, grime_fn=None, seed=3, skip_ao=()):
    """COLOR_0 = (AO, variation, grime, 1) for every object; flora bins keep their painted colour (times AO).
    AO: cosine-weighted ray casts against all objects + extra occluders (ground plane), one shared BVH."""
    rnd = random.Random(seed)
    tree = combined_bvh(list(objs) + list(occluders or []))
    dirs = []
    while len(dirs) < rays:
        v = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1)))
        if 0.05 < v.length <= 1: dirs.append(v.normalized())
    for o in objs:
        me = o.data; mw = o.matrix_world
        var, cols = _DATA.pop(o.name)
        name = o['bin']
        # smooth vertex normals for the hemisphere (area weighted face normals)
        acc = [Vector((0, 0, 0)) for _ in me.vertices]
        for p in me.polygons:
            for vi in p.vertices: acc[vi] += p.normal * p.area
        ca = me.color_attributes.new('Col', 'FLOAT_COLOR', 'POINT')
        for i, v in enumerate(me.vertices):
            n = acc[i].normalized() if acc[i].length > 1e-9 else Vector((0, 0, 1))
            p = mw @ v.co
            if name in skip_ao: ao = 1.0
            else:
                o0 = p + n * 0.006; hit = 0.0; tot = 0.0
                for d in dirs:
                    if d.dot(n) < 0: d = -d
                    w = d.dot(n); tot += w
                    h = tree.ray_cast(o0, d, dist)
                    if h[0] is not None: hit += w * (1 - (h[3] / dist) ** 1.5)
                ao = max(0.0, min(1.0, 1 - strength * hit / max(tot, 1e-6)))
            g = grime_fn(Vector((p.x, p.z, -p.y)), name) if grime_fn else 0.0
            if cols[i][0] >= 0:
                c = cols[i]; ca.data[i].color = (c[0] * (0.35 + 0.65 * ao), c[1] * (0.35 + 0.65 * ao), c[2] * (0.35 + 0.65 * ao), 1)
            else:
                ca.data[i].color = (ao, var[i], max(0.0, min(1.0, g)), 1)
        me.color_attributes.active_color = ca
        try: me.color_attributes.render_color_index = 0
        except Exception: pass


def material(obj, name):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    obj.data.materials.clear(); obj.data.materials.append(m)


def ground_plane(size=40, y=0.0):
    me = bpy.data.meshes.new('ground'); s = size / 2
    me.from_pydata([(-s, -s, y), (s, -s, y), (s, s, y), (-s, s, y)], [], [[0, 1, 2, 3]])
    ob = bpy.data.objects.new('ground', me); bpy.context.scene.collection.objects.link(ob)
    return ob


def tris(objs):
    return sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs)


def export(path, objs):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_colors=True, export_apply=True,
                              export_yup=True, export_extras=True, export_materials='EXPORT')
    return path
