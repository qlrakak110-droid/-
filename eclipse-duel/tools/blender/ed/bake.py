# edlib baking: Cycles ambient occlusion baked into vertex attributes (with every other part of the hero occluding),
# mesh curvature (convex edges -> edge wear, concave -> grime), the combined ed_cav the game shader reads, decimation to
# a triangle budget with silhouette / boundary protection, UV unwrap + packing and Cycles high -> low map baking
# (normal / AO) for parts where maps beat vertex data.

import bpy
import math
import os
import numpy as np
from .core import (verts_of, set_verts, normals_of, tris_of, get_attr, set_attr, select, add_mod, apply_mods, log, THREADS, ROOT, smoothstep, link, delete)


def _adjacency(obj):
    me = obj.data
    e = np.empty(len(me.edges) * 2, dtype=np.int32)
    me.edges.foreach_get('vertices', e)
    return e.reshape(-1, 2)


def curvature(obj, scale=0.012):
    """
    Per-vertex signed curvature from the normal field: > 0 convex (edges, ridges: wear), < 0 concave (creases: grime).
    Roughly 1 / radius x scale, clipped to [-1, 1].
    """
    P, N = verts_of(obj), normals_of(obj)
    E = _adjacency(obj)
    n = len(P)
    acc = np.zeros(n); cnt = np.zeros(n)
    a, b = E[:, 0], E[:, 1]
    d = P[b] - P[a]
    L2 = np.maximum(np.einsum('ij,ij->i', d, d), 1e-12)
    # convex where the neighbour's normal turns away: (n_b - n_a) . d > 0
    k = np.einsum('ij,ij->i', N[b] - N[a], d) / L2
    np.add.at(acc, a, k); np.add.at(acc, b, k)
    np.add.at(cnt, a, 1); np.add.at(cnt, b, 1)
    c = acc / np.maximum(cnt, 1)
    return np.clip(c * scale, -1, 1)


def smooth_values(obj, x, iterations=2, factor=0.5):
    E = _adjacency(obj)
    x = np.asarray(x, dtype=np.float64).copy()
    n = len(x)
    for _ in range(iterations):
        acc = np.zeros(n); cnt = np.zeros(n)
        np.add.at(acc, E[:, 0], x[E[:, 1]]); np.add.at(acc, E[:, 1], x[E[:, 0]])
        np.add.at(cnt, E[:, 0], 1); np.add.at(cnt, E[:, 1], 1)
        x = x * (1 - factor) + factor * acc / np.maximum(cnt, 1)
    return x


def bake_vertex_ao(objs, samples=48, distance=0.12, occluders=()):
    """
    Cycles AO baked to a temporary colour attribute of each object -> returns {obj.name: (N,) ao 0..1}. Every visible
    object in the scene occludes (pass the whole hero), so a robe darkens under the lamellar and inside the hat.
    """
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = samples
    sc.render.threads_mode = 'FIXED'; sc.render.threads = THREADS
    sc.render.bake.target = 'VERTEX_COLORS'
    sc.render.bake.use_selected_to_active = False
    try:
        sc.world.light_settings.distance = distance
    except Exception:
        pass
    out = {}
    for o in objs:
        me = o.data
        if '_ao' in me.color_attributes:
            me.color_attributes.remove(me.color_attributes['_ao'])
        ca = me.color_attributes.new('_ao', 'FLOAT_COLOR', 'POINT')
        me.color_attributes.active_color = ca
        if not me.materials:
            m = bpy.data.materials.new('_bake'); me.materials.append(m)
        mods = [m for m in o.modifiers if m.type == 'ARMATURE']
        for m in mods:
            m.show_render = False
        select(o)
        try:
            bpy.ops.object.bake(type='AO', target='VERTEX_COLORS', margin=0)
            a = np.empty(len(me.vertices) * 4, dtype=np.float32)
            me.color_attributes['_ao'].data.foreach_get('color', a)
            out[o.name] = a.reshape(-1, 4)[:, 0].astype(np.float64)
        except RuntimeError as e:
            log('AO bake failed on', o.name, str(e).strip())
            out[o.name] = np.ones(len(me.vertices))
        for m in mods:
            m.show_render = True
        me.color_attributes.remove(me.color_attributes['_ao'])
    return out


def surface_cavity(obj, ao=None, ao_strength=0.85, wear=0.6, grime=0.35, curv_scale=0.012, keep=True):
    """
    Combine baked AO and curvature into the shader's per-vertex ed_cav (< 1 occlusion / grime, 1..2 edge wear) and
    multiply it into what the modelling step already wrote there (weave gaps, plate overlaps, stitches) when `keep`.
    """
    n = len(obj.data.vertices)
    c = smooth_values(obj, curvature(obj, curv_scale), 1)
    occ = np.ones(n) if ao is None else (1 - ao_strength) + ao_strength * np.clip(ao, 0, 1)
    edge = 1 + wear * smoothstep(0.15, 0.8, c)
    crease = 1 - grime * smoothstep(0.15, 0.8, -c)
    # convex edges carry wear only where they are not occluded
    cav = np.where(edge > 1.001, 1 + (edge - 1) * occ, occ * crease)
    if keep:
        old = get_attr(obj, 'ed_cav')
        if old is not None:
            cav = cav * np.where(old < 1, old, 1) + np.where(old > 1, old - 1, 0)
    set_attr(obj, 'ed_cav', np.clip(cav, 0, 2).astype(np.float32))
    return obj


def bake_cavity(objs, samples=48, distance=0.12, **kw):
    """AO bake + curvature for a whole hero (every object occludes the others)."""
    ao = bake_vertex_ao(objs, samples, distance)
    for o in objs:
        surface_cavity(o, ao.get(o.name), **kw)
    log(f'bake_cavity: {len(objs)} objects')
    return ao


# ---- budgets ------------------------------------------------------------------------------------------------------------------

def decimate_to(obj, tris, protect_boundary=True, symmetry=False, protect=None):
    """
    Collapse-decimate an object to about `tris` triangles. Open borders (hems, cuffs: the silhouette of cloth) and the
    optional `protect` (N,) 0..1 mask keep their vertices (weighted decimation). Attributes and weights interpolate.
    """
    from .core import tri_count
    cur = tri_count(obj, evaluated=False)
    if cur <= tris:
        return obj
    w = np.zeros(len(obj.data.vertices))
    if protect_boundary:
        import bmesh
        bm = bmesh.new(); bm.from_mesh(obj.data)
        for v in bm.verts:
            if v.is_boundary:
                w[v.index] = 1.0
        bm.free()
    if protect is not None:
        w = np.maximum(w, np.asarray(protect, dtype=np.float64))
    m = add_mod(obj, 'DECIMATE', decimate_type='COLLAPSE', ratio=tris / cur)
    if w.max() > 0:
        g = obj.vertex_groups.new(name='_keep')
        for i in np.nonzero(w < 0.999)[0]:
            g.add([int(i)], float(1 - w[i]), 'REPLACE')
        m.vertex_group = '_keep'
        m.vertex_group_factor = 1.0
    if symmetry:
        m.use_symmetry = True; m.symmetry_axis = 'X'
    apply_mods(obj)
    if obj.vertex_groups.get('_keep'):
        obj.vertex_groups.remove(obj.vertex_groups['_keep'])
    log(f'decimate {obj.name}: {cur} -> {tri_count(obj, evaluated=False)} tris')
    return obj


def uv_unwrap(obj, name='ed_bake', angle=66.0, margin=0.004):
    """Smart-project UVs into layer `name` and pack the islands (bake target)."""
    me = obj.data
    layer = me.uv_layers.get(name) or me.uv_layers.new(name=name)
    me.uv_layers.active = layer
    select(obj)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(angle), island_margin=margin)
    bpy.ops.uv.pack_islands(margin=margin)
    bpy.ops.object.mode_set(mode='OBJECT')
    return layer


def bake_maps(high, low, size=1024, kinds=('NORMAL', 'AO'), out_dir=None, name=None, extrusion=0.01, samples=32, fmt='WEBP', quality=88):
    """
    Cycles bake from the high-poly objects `high` onto `low` (needs a UV layer 'ed_bake': uv_unwrap): tangent-space
    NORMAL and/or AO -> image files (WEBP / JPEG / PNG) in out_dir. Returns {kind: path}.
    """
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'; sc.cycles.device = 'CPU'; sc.cycles.samples = samples
    sc.render.threads_mode = 'FIXED'; sc.render.threads = THREADS
    out_dir = out_dir or os.path.join(ROOT, 'build', 'bake')
    os.makedirs(out_dir, exist_ok=True)
    name = name or low.name
    me = low.data
    me.uv_layers.active = me.uv_layers['ed_bake']
    if not me.materials:
        me.materials.append(bpy.data.materials.new('_bake_' + name))
    paths = {}
    for kind in kinds:
        img = bpy.data.images.new(f'{name}_{kind.lower()}', size, size, alpha=False, float_buffer=False)
        if kind == 'NORMAL':
            img.colorspace_settings.name = 'Non-Color'
        nodes = []
        for mat in me.materials:
            mat.use_nodes = True
            nt = mat.node_tree
            n = nt.nodes.new('ShaderNodeTexImage'); n.image = img
            nt.nodes.active = n
            nodes.append((nt, n))
        sc.render.bake.use_selected_to_active = True
        sc.render.bake.cage_extrusion = extrusion
        sc.render.bake.max_ray_distance = extrusion * 2
        sc.render.bake.target = 'IMAGE_TEXTURES'
        sc.render.bake.margin = 4
        select(list(high) + [low], active=low)
        bpy.ops.object.bake(type=kind, use_selected_to_active=True, cage_extrusion=extrusion, normal_space='TANGENT')
        ext = {'WEBP': '.webp', 'JPEG': '.jpg', 'PNG': '.png'}[fmt]
        path = os.path.join(out_dir, f'{name}_{kind.lower()}{ext}')
        img.filepath_raw = path
        img.file_format = fmt
        sc.render.image_settings.quality = quality
        img.save()
        paths[kind] = path
        for nt, n in nodes:
            nt.nodes.remove(n)
        bpy.data.images.remove(img)
    log(f'bake_maps {name}: {", ".join(paths)} {size}px')
    return paths
