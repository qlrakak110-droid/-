# edlib core: scene, axes, the game rig as a Blender armature, mesh / attribute / modifier helpers, looks (materials).
#
# AXES (converted exactly once, here):
#   game    (x, y, z) = (forward, up, right)        metres, right-handed, the fighter faces +X
#   blender (x, y, z) = (-right, -forward, up)      the hero faces -Y (numpad-1 front view), Z up, right hand at -X
#   blender = (-gz, -gx, gy)      game = (-by, bz, -bx)
# World-space arguments of every edlib function are BLENDER coordinates. Offsets relative to a bone are given in the
# bone's GAME frame, exactly as in the JS kit (+X forward, +Y up along the limb toward its parent, +Z the fighter's
# right): rig.pt('foreArmR', [0, -0.1, 0]) is the point 10 cm down the right forearm, in Blender world space.

import bpy
import bmesh
import json
import math
import os
import time
import hashlib
import numpy as np
from mathutils import Matrix, Vector

G2B = np.array([[0.0, 0.0, -1.0], [-1.0, 0.0, 0.0], [0.0, 1.0, 0.0]])  # blender = G2B @ game
B2G = G2B.T
G2B4 = np.eye(4); G2B4[:3, :3] = G2B
B2G4 = G2B4.T

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))          # tools/blender
ROOT = os.path.dirname(os.path.dirname(HERE))                                # project root
THREADS = int(os.environ.get('ED_THREADS', '2'))
_T0 = time.time()


def log(*a):
    """Progress line with elapsed seconds (stdout is the build log)."""
    print('[ed %6.1fs]' % (time.time() - _T0), *a, flush=True)


def g2b(p):
    """Game -> Blender coordinates (one point or an (N, 3) array)."""
    return np.asarray(p, dtype=np.float64) @ G2B.T


def b2g(p):
    """Blender -> game coordinates (one point or an (N, 3) array)."""
    return np.asarray(p, dtype=np.float64) @ B2G.T


def smoothstep(a, b, x):
    t = np.clip((np.asarray(x, dtype=np.float64) - a) / (b - a if b != a else 1e-9), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def normalize(v, axis=-1):
    v = np.asarray(v, dtype=np.float64)
    return v / np.maximum(np.linalg.norm(v, axis=axis, keepdims=True), 1e-12)


def curve_fn(c, default=0.0):
    """A "curve" argument -> fn(t): number, [[t, value], ...] control points (monotone smooth interpolation) or fn."""
    if c is None:
        return lambda t: np.full_like(np.asarray(t, dtype=np.float64), default) if np.ndim(t) else default
    if callable(c):
        return c
    if np.ndim(c) == 0:
        return lambda t, k=float(c): np.full_like(np.asarray(t, dtype=np.float64), k) if np.ndim(t) else k
    pts = np.asarray(c, dtype=np.float64)
    xs, ys = pts[:, 0], pts[:, 1]

    def f(t):
        return catmull(xs, ys, t)
    return f


def catmull(xs, ys, t):
    """Catmull-Rom through (xs, ys) evaluated at t (scalar or array); clamps outside. ys may be (N,) or (N, k)."""
    xs = np.asarray(xs, dtype=np.float64); ys = np.asarray(ys, dtype=np.float64)
    tt = np.atleast_1d(np.asarray(t, dtype=np.float64))
    n = len(xs)
    i = np.clip(np.searchsorted(xs, tt, side='right') - 1, 0, n - 2)
    x0, x1 = xs[i], xs[i + 1]
    u = np.clip((tt - x0) / np.maximum(x1 - x0, 1e-12), 0, 1)
    im, ip = np.maximum(i - 1, 0), np.minimum(i + 2, n - 1)
    h = x1 - x0
    m0 = (ys[i + 1] - ys[im]) / np.maximum((xs[i + 1] - xs[im]), 1e-12)[(...,) + (None,) * (ys.ndim - 1)]
    m1 = (ys[ip] - ys[i]) / np.maximum((xs[ip] - xs[i]), 1e-12)[(...,) + (None,) * (ys.ndim - 1)]
    ex = (...,) + (None,) * (ys.ndim - 1)
    u_, h_ = u[ex], h[ex]
    h00 = 2 * u_ ** 3 - 3 * u_ ** 2 + 1; h10 = u_ ** 3 - 2 * u_ ** 2 + u_; h01 = -2 * u_ ** 3 + 3 * u_ ** 2; h11 = u_ ** 3 - u_ ** 2
    out = h00 * ys[i] + h10 * h_ * m0 + h01 * ys[i + 1] + h11 * h_ * m1
    return out if np.ndim(t) else out[0]


def polyline(points, n, closed=False):
    """Resample a Catmull-Rom spline through `points` ((k, 3)) at n evenly spaced arc-length positions -> (n, 3)."""
    P = np.asarray(points, dtype=np.float64)
    if closed:
        P = np.vstack([P, P[:1]])
    k = len(P)
    dense = catmull(np.arange(k, dtype=np.float64), P, np.linspace(0, k - 1, max(64, k * 24)))
    seg = np.linalg.norm(np.diff(dense, axis=0), axis=1)
    s = np.concatenate([[0], np.cumsum(seg)])
    t = np.linspace(0, s[-1], n + 1 if closed else n)[: n]
    return np.stack([np.interp(t, s, dense[:, a]) for a in range(3)], axis=1)


# ---- scene ----------------------------------------------------------------------------------------------------------------

def reset_scene(threads=None):
    """Factory-empty scene, metric units, Cycles on the CPU with a thread limit (the machine is shared)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = 'METRIC'
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.render.threads_mode = 'FIXED'
    sc.render.threads = threads or THREADS
    sc.frame_set(1)
    return sc


def collection(name, parent=None):
    """Get or create a collection linked under `parent` (default: the scene collection)."""
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
        (parent or bpy.context.scene.collection).children.link(c)
    return c


def link(obj, coll=None):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    (coll or bpy.context.scene.collection).objects.link(obj)
    return obj


def select(objs, active=None):
    """Deselect all, select `objs` (object or list), make `active` (default: the last) active. Object mode."""
    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    if not isinstance(objs, (list, tuple)):
        objs = [objs]
    for o in objs:
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or objs[-1]


def delete(objs):
    if not isinstance(objs, (list, tuple)):
        objs = [objs]
    for o in objs:
        if o is None:
            continue
        data = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if data is not None and data.users == 0 and isinstance(data, bpy.types.Mesh):
            bpy.data.meshes.remove(data)


def file_hash(*paths):
    """Short hash of the given files (scripts): stored in the asset manifest so a stale asset is detectable."""
    h = hashlib.sha1()
    for p in paths:
        with open(p, 'rb') as f:
            h.update(f.read())
    return h.hexdigest()[:12]


# ---- rig ---------------------------------------------------------------------------------------------------------------------

class Rig:
    """The game rig of one hero (tools/blender/rigs/<hero>.json, written by export_rig.mjs)."""

    def __init__(self, path_or_hero):
        path = path_or_hero if os.path.exists(path_or_hero) else os.path.join(HERE, 'rigs', path_or_hero + '.json')
        with open(path) as f:
            self.data = json.load(f)
        self.path = path
        self.hero = self.data['hero']
        self.P = self.data['proportions']
        self.K = self.data['bodyScale']
        self.names = [b['name'] for b in self.data['bones']]
        self.bones = {b['name']: b for b in self.data['bones']}
        # bind / zero matrices: game column-major -> 4x4 mapping the bone's GAME-frame coordinates to BLENDER world
        self.Mg = {n: np.array(b['matrix'], dtype=np.float64).reshape(4, 4).T for n, b in self.bones.items()}
        self.M = {n: G2B4 @ m for n, m in self.Mg.items()}
        self.Minv = {n: np.linalg.inv(m) for n, m in self.M.items()}
        self.Z = {n: G2B4 @ np.array(b['zero'], dtype=np.float64).reshape(4, 4).T for n, b in self.bones.items()}

    def has(self, bone):
        return bone in self.bones

    def kind(self, bone):
        return self.bones[bone]['kind']

    def of_kind(self, *kinds):
        """Bone names of the given kinds: core, finger, weapon, helper, extra, follow, spring, cloth."""
        return [n for n in self.names if self.bones[n]['kind'] in kinds]

    def pt(self, bone, off=(0, 0, 0)):
        """Bind-space (Blender world) position of a point given in the bone's game frame."""
        m = self.M[bone]
        return m[:3, :3] @ np.asarray(off, dtype=np.float64) + m[:3, 3]

    def pts(self, bone, offs):
        m = self.M[bone]
        return np.asarray(offs, dtype=np.float64) @ m[:3, :3].T + m[:3, 3]

    def vec(self, bone, v):
        """Bind-space direction of a vector given in the bone's game frame."""
        return self.M[bone][:3, :3] @ np.asarray(v, dtype=np.float64)

    def vecs(self, bone, v):
        return np.asarray(v, dtype=np.float64) @ self.M[bone][:3, :3].T

    def local(self, bone, p):
        """Blender world point(s) -> coordinates in the bone's game frame (bind pose)."""
        m = self.Minv[bone]
        return np.asarray(p, dtype=np.float64) @ m[:3, :3].T + m[:3, 3]

    def head(self, bone):
        return g2b(self.bones[bone]['head'])

    def tail(self, bone):
        return g2b(self.bones[bone]['tail'])

    def zero_pt(self, bone, off=(0, 0, 0)):
        m = self.Z[bone]
        return m[:3, :3] @ np.asarray(off, dtype=np.float64) + m[:3, 3]

    def mirror(self, bone):
        if bone.endswith('R'):
            return bone[:-1] + 'L'
        if bone.endswith('L'):
            return bone[:-1] + 'R'
        return bone

    def socket(self, name):
        return g2b(self.data['sockets'][name]['bind'])

    def capsules(self):
        """Collider capsules in Blender bind space: [(name, a (3,), b (3,), r)]."""
        return [(c['name'], g2b(c['a']['bind']), g2b(c['b']['bind']), c['r']) for c in self.data['colliders']]

    def weapon(self, k=0):
        return self.data['weapons'][k]

    def panel(self, name):
        """A cloth panel defined by the JS design: dict with cols, rows, rest ((rows, cols, 3) Blender space), anchorBones."""
        for c in self.data['cloth']:
            if c['name'] == name:
                out = dict(c)
                out['rest'] = g2b(np.array(c['rest']).reshape(c['rows'], c['cols'], 3))
                return out
        raise KeyError('no cloth panel ' + name)

    def chain(self, prefix):
        """Bones of a spring / extra chain named prefix1, prefix2 ... in order."""
        out = []
        i = 1
        while prefix + str(i) in self.bones:
            out.append(prefix + str(i)); i += 1
        if not out:
            raise KeyError('no chain ' + prefix)
        return out

    def chain_points(self, prefix):
        """Bind-space joints of a chain: root, joints, tip ((n + 1, 3), Blender space)."""
        names = self.chain(prefix)
        return np.array([self.head(n) for n in names] + [self.tail(names[-1])])


def build_armature(rig, name='rig', coll=None, kinds=None):
    """
    The game rig as a Blender armature in its bind pose (the A-pose every mesh is authored in). Bone names are the game's.
    Heads sit on the joints, tails on the end of the limb segment the bone stands for (what bone-heat weighting needs);
    bone rolls are meaningless: skin weights are exported by bone NAME and the engine keeps its own bone frames.
    kinds: restrict to bone kinds (default: every bone except cloth particles, which are bound by panel coordinates).
    """
    kinds = kinds or ('core', 'finger', 'weapon', 'helper', 'extra', 'follow', 'spring')
    arm = bpy.data.armatures.new(name)
    obj = bpy.data.objects.new(name, arm)
    link(obj, coll)
    select(obj)
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm.edit_bones
    for n in rig.names:
        b = rig.bones[n]
        if b['kind'] not in kinds:
            continue
        e = eb.new(n)
        h, t = rig.head(n), rig.tail(n)
        if np.linalg.norm(t - h) < 0.012:
            t = h + normalize(t - h + np.array([0, 0, 1e-6])) * 0.012
        e.head, e.tail = Vector(h), Vector(t)
        if b['parent'] and b['parent'] in eb:
            e.parent = eb[b['parent']]
        e.use_connect = False
    bpy.ops.object.mode_set(mode='OBJECT')
    for bn in arm.bones:
        bn['ed_kind'] = rig.bones[bn.name]['kind']
    obj.show_in_front = True
    obj['ed_rig'] = rig.hero
    return obj


def pose_armature(arm, rig, pose=None):
    """
    Put the armature in a pose sampled from the game (rig.data['poses'][name]: model-space bone matrices), exactly as the
    engine skins it (linear blend, the same bind matrices): check deformation in Blender before going to the engine.
    pose=None restores the bind pose. Cloth particles are simulated at runtime and stay at rest here.
    """
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    if pose is None:
        bpy.context.view_layer.update()
        return
    mats = rig.data['poses'][pose]['bones'] if isinstance(pose, str) else pose
    D = {}
    for n, m in mats.items():
        if n in rig.Mg:
            D[n] = G2B4 @ np.array(m, dtype=np.float64).reshape(4, 4).T @ np.linalg.inv(rig.Mg[n]) @ B2G4
    rest = {b.name: np.array(b.matrix_local) for b in arm.data.bones}
    for pb in arm.pose.bones:  # parents first
        n = pb.name
        d = D.get(n)
        par = pb.parent.name if pb.parent else None
        if d is None:
            d = D.get(par, np.eye(4))
            D[n] = d
        b_pose = d @ rest[n]
        if par:
            basis = np.linalg.inv(np.linalg.inv(rest[par]) @ rest[n]) @ (np.linalg.inv(D[par] @ rest[par]) @ b_pose)
        else:
            basis = np.linalg.inv(rest[n]) @ b_pose
        pb.matrix_basis = Matrix(basis.tolist())
    bpy.context.view_layer.update()


# ---- meshes ------------------------------------------------------------------------------------------------------------------

def new_mesh(name, verts, faces, coll=None, smooth=True):
    """Mesh object from vertices ((N, 3) Blender space) and faces (lists of vertex indices; tris / quads / n-gons)."""
    me = bpy.data.meshes.new(name)
    V = np.asarray(verts, dtype=np.float64)
    me.from_pydata(V.tolist(), [], [list(map(int, f)) for f in faces])
    me.update()
    if smooth and len(me.polygons):
        me.polygons.foreach_set('use_smooth', np.ones(len(me.polygons), dtype=bool))
    obj = bpy.data.objects.new(name, me)
    link(obj, coll)
    return obj


def verts_of(obj):
    """Vertex positions ((N, 3) float64) of a mesh object in world space (object transforms are identity in edlib)."""
    me = obj.data
    a = np.empty(len(me.vertices) * 3, dtype=np.float32)
    me.vertices.foreach_get('co', a)
    V = a.reshape(-1, 3).astype(np.float64)
    if obj.matrix_world != Matrix.Identity(4):
        m = np.array(obj.matrix_world)
        V = V @ m[:3, :3].T + m[:3, 3]
    return V


def set_verts(obj, V):
    obj.data.vertices.foreach_set('co', np.asarray(V, dtype=np.float32).reshape(-1))
    obj.data.update()


def normals_of(obj):
    me = obj.data
    a = np.empty(len(me.vertices) * 3, dtype=np.float32)
    me.vertices.foreach_get('normal', a)
    return a.reshape(-1, 3).astype(np.float64)


def faces_of(obj):
    """Faces as a list of vertex-index lists."""
    return [list(p.vertices) for p in obj.data.polygons]


def tris_of(obj):
    """Triangles ((M, 3) int) of the mesh (n-gons fan / ear triangulated by Blender's loop triangles)."""
    me = obj.data
    me.calc_loop_triangles()
    a = np.empty(len(me.loop_triangles) * 3, dtype=np.int32)
    me.loop_triangles.foreach_get('vertices', a)
    return a.reshape(-1, 3)


def tri_count(obj, evaluated=True):
    """Triangle count of an object (with its modifiers when `evaluated`)."""
    if evaluated:
        dg = bpy.context.evaluated_depsgraph_get()
        me = obj.evaluated_get(dg).data
    else:
        me = obj.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)


def duplicate(obj, name=None, coll=None):
    o = obj.copy()
    o.data = obj.data.copy()
    o.name = name or obj.name + '.copy'
    link(o, coll or (obj.users_collection[0] if obj.users_collection else None))
    return o


def join(objs, name=None):
    """Join mesh objects into the first one (attributes, vertex groups and material slots are merged by name)."""
    objs = [o for o in objs if o is not None]
    if len(objs) > 1:
        select(objs, active=objs[0])
        bpy.ops.object.join()
    if name:
        objs[0].name = name
        objs[0].data.name = name
    return objs[0]


def add_mod(obj, kind, name=None, **props):
    """Add a modifier and set its properties: add_mod(o, 'SOLIDIFY', thickness=0.004, offset=1)."""
    m = obj.modifiers.new(name or kind.lower(), kind)
    for k, v in props.items():
        setattr(m, k, v)
    return m


def apply_mods(obj, only=None):
    """Apply (bake) the object's modifiers into its mesh, in stack order (`only`: a list of modifier names)."""
    select(obj)
    for m in list(obj.modifiers):
        if only and m.name not in only:
            continue
        try:
            bpy.ops.object.modifier_apply(modifier=m.name)
        except RuntimeError as e:
            log('modifier', m.name, 'on', obj.name, 'not applied:', str(e).strip())
            obj.modifiers.remove(m)
    return obj


def shade(obj, angle=None):
    """Smooth shading; with `angle` (degrees) edges sharper than it become hard edges (split normals at export)."""
    me = obj.data
    if len(me.polygons):
        me.polygons.foreach_set('use_smooth', np.ones(len(me.polygons), dtype=bool))
    if angle is not None:
        me.set_sharp_from_angle(angle=math.radians(angle))
    me.update()
    return obj


def recalc_normals(obj, inside=False):
    """Make face windings consistent (outward; `inside` flips)."""
    bm = bmesh.new(); bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if inside:
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    bm.to_mesh(obj.data); bm.free()
    obj.data.update()
    return obj


def weld(obj, dist=1e-5):
    """Merge vertices closer than `dist`."""
    bm = bmesh.new(); bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=dist)
    bm.to_mesh(obj.data); bm.free()
    obj.data.update()
    return obj


def transform(obj, matrix):
    """Bake a 4x4 transform (numpy / Matrix, Blender space) into the mesh vertices."""
    m = np.array(matrix, dtype=np.float64)
    set_verts(obj, verts_of(obj) @ m[:3, :3].T + m[:3, 3])
    return obj


def mirror_x(obj, name=None):
    """A mirrored copy across the Blender YZ plane (the hero's left <-> right), windings fixed, R <-> L vertex groups swapped."""
    o = duplicate(obj, name or _swap_side(obj.name))
    V = verts_of(o); V[:, 0] *= -1
    set_verts(o, V)
    bm = bmesh.new(); bm.from_mesh(o.data)
    bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    bm.to_mesh(o.data); bm.free()
    for g in o.vertex_groups:
        g.name = '\x00' + g.name
    for g in o.vertex_groups:
        g.name = _swap_side(g.name[1:])
    for an in ('ed_uvw', 'ed_cloth'):
        pass
    o.data.update()
    return o


def _swap_side(n):
    if n.endswith('R'):
        return n[:-1] + 'L'
    if n.endswith('L'):
        return n[:-1] + 'R'
    return n + '.m'


# ---- per-vertex data ---------------------------------------------------------------------------------------------------------
# Exported surface data live in mesh attributes (POINT domain unless noted):
#   ed_col   FLOAT_COLOR  linear albedo (multiplied by the look's colour when the look has one)
#   ed_cav   FLOAT        cavity / edge: < 1 occlusion (darker, grimier), 1 neutral, 1..2 convex edge (edge wear)
#   ed_glow  FLOAT_VECTOR glow channel masks (inlay, vein, eye)
#   ed_uvw   FLOAT_VECTOR (u, v, code) of a UV texture set (bamboo, lamellar, hair, brocade, gauze, blade, fur)
#   ed_cloth FLOAT_VECTOR (panel u, panel v, share 0..1): binding to a runtime cloth panel (obj['ed_panel'] = its name)
# Skin weights are vertex groups named after game bones. Looks are material slots (see look()).

def set_attr(obj, name, data, kind=None, domain='POINT'):
    """Create / overwrite a mesh attribute from a numpy array ((N,), (N, 3) or (N, 4) for colours)."""
    me = obj.data
    data = np.asarray(data)
    if kind is None:
        kind = 'FLOAT' if data.ndim == 1 else ('FLOAT_COLOR' if data.shape[1] == 4 else 'FLOAT_VECTOR')
        if data.dtype.kind in 'iu' and data.ndim == 1:
            kind = 'INT'
    a = me.attributes.get(name)
    if a is not None and (a.data_type != kind or a.domain != domain):
        me.attributes.remove(a); a = None
    if a is None:
        a = me.attributes.new(name, kind, domain)
    key = {'FLOAT': 'value', 'INT': 'value', 'FLOAT_VECTOR': 'vector', 'FLOAT_COLOR': 'color', 'BOOLEAN': 'value', 'FLOAT2': 'vector'}[kind]
    a.data.foreach_set(key, np.ascontiguousarray(data, dtype=np.int32 if kind == 'INT' else np.float32).reshape(-1))
    return a


def get_attr(obj, name, default=None):
    """Mesh attribute as a numpy array, or `default` when missing."""
    a = obj.data.attributes.get(name)
    if a is None:
        return default
    n = len(a.data)
    if a.data_type in ('FLOAT', 'INT', 'BOOLEAN'):
        out = np.empty(n, dtype=np.int32 if a.data_type == 'INT' else (bool if a.data_type == 'BOOLEAN' else np.float32))
        a.data.foreach_get('value', out)
        return out
    w = {'FLOAT_VECTOR': 3, 'FLOAT_COLOR': 4, 'BYTE_COLOR': 4, 'FLOAT2': 2}[a.data_type]
    out = np.empty(n * w, dtype=np.float32)
    a.data.foreach_get('color' if 'COLOR' in a.data_type else 'vector', out)
    return out.reshape(n, w)


def set_color(obj, rgb):
    """Per-vertex linear albedo: one [r, g, b] or an (N, 3) array."""
    n = len(obj.data.vertices)
    c = np.ones((n, 4), dtype=np.float32)
    c[:, :3] = np.asarray(rgb, dtype=np.float32)
    set_attr(obj, 'ed_col', c, 'FLOAT_COLOR')


def set_weights(obj, weights, replace=True):
    """Vertex groups from {bone name: (N,) array} (zeros are not stored)."""
    if replace:
        obj.vertex_groups.clear()
    for name, w in weights.items():
        w = np.asarray(w, dtype=np.float64)
        idx = np.nonzero(w > 1e-5)[0]
        if not len(idx):
            continue
        g = obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name)
        for i in idx:
            g.add([int(i)], float(w[i]), 'REPLACE')


def get_weights(obj, names=None):
    """Vertex groups as {name: (N,) float array}."""
    n = len(obj.data.vertices)
    groups = [g for g in obj.vertex_groups if names is None or g.name in names]
    out = {g.name: np.zeros(n) for g in groups}
    by_index = {g.index: g.name for g in groups}
    for v in obj.data.vertices:
        for ge in v.groups:
            nm = by_index.get(ge.group)
            if nm is not None:
                out[nm][v.index] = ge.weight
    return out


def rigid(obj, bone):
    """Bind every vertex of the object 100% to one bone (hard pieces: hats, plates, weapons)."""
    obj.vertex_groups.clear()
    g = obj.vertex_groups.new(name=bone)
    g.add(list(range(len(obj.data.vertices))), 1.0, 'REPLACE')
    return obj


# ---- looks (material slots) ---------------------------------------------------------------------------------------------------

_LOOKS = {}


def look(name, color=(0.5, 0.5, 0.5), rough=0.5, metal=0.0, set='hammered', amt=1.0, wear=1.0, occ=1.0, glow=(0, 0, 0), vcol=True, **extra):
    """
    A surface look = one Blender material + the data the game's shared character shader needs.
      color  linear albedo (metals: F0); multiplied by the per-vertex ed_col when `vcol`
      rough, metal   0..1       set, amt   texture set name of src/char/kit/textures.js + detail amount
      wear   edge-wear scale (cav > 1)      occ   occlusion multiplier (cav < 1)      glow   (inlay, vein, eye) masks
    The same name always returns the same look. Looks are exported per vertex range; the JS side may override any field.
    """
    if name in _LOOKS and _LOOKS[name].name in bpy.data.materials:
        return _LOOKS[name]
    mat = bpy.data.materials.new('look:' + name)
    try:
        mat.use_nodes = True
    except Exception:
        pass
    nt = mat.node_tree
    bsdf = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    if bsdf is None:
        bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
        out = next((n for n in nt.nodes if n.type == 'OUTPUT_MATERIAL'), None) or nt.nodes.new('ShaderNodeOutputMaterial')
        nt.links.new(bsdf.outputs[0], out.inputs[0])
    col = tuple(float(c) for c in color) + (1.0,)
    bsdf.inputs['Roughness'].default_value = float(rough)
    bsdf.inputs['Metallic'].default_value = float(metal)
    if vcol:
        # preview: albedo = look colour x ed_col x (cavity as soft AO)
        attr = nt.nodes.new('ShaderNodeAttribute'); attr.attribute_name = 'ed_col'; attr.attribute_type = 'GEOMETRY'
        cav = nt.nodes.new('ShaderNodeAttribute'); cav.attribute_name = 'ed_cav'; cav.attribute_type = 'GEOMETRY'
        mul = nt.nodes.new('ShaderNodeMixRGB'); mul.blend_type = 'MULTIPLY'; mul.inputs[0].default_value = 1.0
        mul.inputs[1].default_value = col
        nt.links.new(attr.outputs['Color'], mul.inputs[2])
        clamp = nt.nodes.new('ShaderNodeMath'); clamp.operation = 'MINIMUM'; clamp.inputs[1].default_value = 1.0
        nt.links.new(cav.outputs['Fac'], clamp.inputs[0])
        mul2 = nt.nodes.new('ShaderNodeMixRGB'); mul2.blend_type = 'MULTIPLY'; mul2.inputs[0].default_value = 1.0
        nt.links.new(mul.outputs[0], mul2.inputs[1])
        nt.links.new(clamp.outputs[0], mul2.inputs[2])
        nt.links.new(mul2.outputs[0], bsdf.inputs['Base Color'])
    else:
        bsdf.inputs['Base Color'].default_value = col
    g = tuple(float(x) for x in glow)
    if max(g) > 0:
        em = extra.get('emission', (0.6, 0.45, 1.0))
        bsdf.inputs['Emission Color'].default_value = tuple(em) + (1.0,)
        bsdf.inputs['Emission Strength'].default_value = 4.0 * max(g)
    mat['ed_look'] = json.dumps({'name': name, 'color': [float(c) for c in color], 'rough': float(rough), 'metal': float(metal), 'set': set, 'amt': float(amt),
                                 'wear': float(wear), 'occ': float(occ), 'glow': list(g), **{k: v for k, v in extra.items() if k != 'emission'}})
    _LOOKS[name] = mat
    return mat


def assign_look(obj, mat, faces=None):
    """Give the whole object (or the listed face indices / a boolean face mask) a look."""
    me = obj.data
    idx = next((i for i, m in enumerate(me.materials) if m == mat), None)
    if idx is None:
        me.materials.append(mat)
        idx = len(me.materials) - 1
    n = len(me.polygons)
    cur = np.zeros(n, dtype=np.int32)
    me.polygons.foreach_get('material_index', cur)
    if faces is None:
        cur[:] = idx
    else:
        cur[np.asarray(faces)] = idx
    me.polygons.foreach_set('material_index', cur)
    me.update()
    if get_attr(obj, 'ed_col') is None:
        set_color(obj, (1, 1, 1))
    if get_attr(obj, 'ed_cav') is None:
        set_attr(obj, 'ed_cav', np.ones(len(me.vertices), dtype=np.float32))
    return obj


def part(obj, name, slot, flags=(), panel=None, order=0):
    """
    Mark an object as an exported part. name: part name (assets.add selects parts by name), slot: default material slot
    of the JS design ('robe', 'gear', 'blade' ...), flags: any of 'cutout', 'double', 'cloth', 'rigid'.
    """
    obj['ed_part'] = name
    obj['ed_slot'] = slot
    obj['ed_flags'] = ','.join(flags)
    obj['ed_order'] = order
    if panel:
        obj['ed_panel'] = panel
    return obj
