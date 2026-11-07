"""blib — helpers for authoring game assets headless in Blender 4.0 (apt build).

Run a script:   blender -b -P tools/blender/<script>.py -- <args>
Import in scripts:  import sys, os; sys.path.insert(0, os.path.dirname(__file__)); import blib as B

NOTE: Cycles baking does NOT work in this Blender build (bakes return zeros). Do not use bpy.ops.object.bake.
Bake ambient occlusion into vertex colours with B.vertex_ao() (BVH ray casts) and get surface detail at runtime
from tileable PBR textures (tools/tex/texlib.py) via triplanar or UV mapping.
Units: 1 Blender unit = 1 game unit (player ≈ 2 units tall). Blender is Z-up; the glTF exporter converts to Y-up.
"""
import bpy, bmesh, math, random, os
from mathutils import Vector
from mathutils.bvhtree import BVHTree

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def active(obj):
    bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True); bpy.context.view_layer.objects.active = obj
    return obj

def apply_mods(obj):
    active(obj)
    for m in list(obj.modifiers): bpy.ops.object.modifier_apply(modifier=m.name)
    return obj

def displace(obj, ttype='CLOUDS', size=0.5, strength=0.2, coords='OBJECT', mid=0.5, **kw):
    """add a Displace modifier driven by a procedural texture (CLOUDS, VORONOI, MUSGRAVE, DISTORTED_NOISE, ...)"""
    t = bpy.data.textures.new(f'{ttype}_{size}', ttype)
    if hasattr(t, 'noise_scale'): t.noise_scale = size
    for k, v in kw.items(): setattr(t, k, v)
    m = obj.modifiers.new('disp', 'DISPLACE'); m.texture = t; m.strength = strength; m.texture_coords = coords; m.mid_level = mid
    return m

def subdivide(obj, levels=2, simple=False):
    m = obj.modifiers.new('sub', 'SUBSURF'); m.levels = levels; m.render_levels = levels
    if simple: m.subdivision_type = 'SIMPLE'
    return m

def bevel(obj, width=0.02, segments=2, angle=30):
    m = obj.modifiers.new('bev', 'BEVEL'); m.width = width; m.segments = segments
    m.limit_method = 'ANGLE'; m.angle_limit = math.radians(angle)
    return m

def decimate(obj, ratio):
    m = obj.modifiers.new('dec', 'DECIMATE'); m.ratio = ratio; apply_mods(obj); return obj

def smooth(obj, auto_angle=None):
    active(obj); bpy.ops.object.shade_smooth()
    if auto_angle is not None:
        try: bpy.ops.object.shade_smooth_by_angle(angle=math.radians(auto_angle))
        except Exception: pass
    return obj

def smart_uv(obj, angle=66, margin=0.02):
    active(obj); bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(angle), island_margin=margin)
    bpy.ops.object.mode_set(mode='OBJECT'); return obj

def cube_uv(obj, size=1.0):
    active(obj); bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.cube_project(cube_size=size); bpy.ops.object.mode_set(mode='OBJECT'); return obj

def join(objs, name=None):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]; bpy.ops.object.join()
    if name: objs[0].name = name
    return objs[0]

def material(obj, name, color=(0.8, 0.8, 0.8, 1), rough=0.8, metal=0.0):
    """assign a named Principled material; the game maps glTF material NAMES to its own PBR sets"""
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True; p = m.node_tree.nodes.get('Principled BSDF')
    if p:
        p.inputs['Base Color'].default_value = color; p.inputs['Roughness'].default_value = rough; p.inputs['Metallic'].default_value = metal
    obj.data.materials.clear(); obj.data.materials.append(m)
    return m

def vertex_ao(obj, rays=24, dist=1.5, strength=1.0, name='Col', tint=None, seed=1):
    """bake ambient occlusion into a vertex colour layer with BVH ray casts (works without Cycles).
    Also occludes against every other mesh in the scene (ground contact, neighbours)."""
    random.seed(seed)
    dg = bpy.context.evaluated_depsgraph_get()
    trees = []
    for o in bpy.context.scene.objects:
        if o.type == 'MESH':
            bm = bmesh.new(); bm.from_object(o, dg); bm.transform(o.matrix_world); trees.append(BVHTree.FromBMesh(bm)); bm.free()
    me = obj.data; mw = obj.matrix_world; nm = mw.to_3x3().inverted().transposed()
    dirs = []
    while len(dirs) < rays:
        v = Vector((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-1, 1)))
        if 0.05 < v.length <= 1: dirs.append(v.normalized())
    occ = []
    for v in me.vertices:
        p = mw @ v.co; n = (nm @ v.normal).normalized(); o = p + n * 0.004; hit = 0.0; tot = 0.0
        for d in dirs:
            if d.dot(n) < 0: d = -d
            w = d.dot(n); tot += w
            for t in trees:
                h = t.ray_cast(o, d, dist)
                if h[0] is not None: hit += w * (1 - (h[3] / dist) ** 2); break
        occ.append(1 - strength * hit / max(tot, 1e-6))
    if name in me.color_attributes: me.color_attributes.remove(me.color_attributes[name])
    ca = me.color_attributes.new(name, 'FLOAT_COLOR', 'POINT')
    for i, a in enumerate(occ):
        a = max(0.0, min(1.0, a))
        c = (a * tint[0], a * tint[1], a * tint[2], 1) if tint else (a, a, a, 1)
        ca.data[i].color = c
    return occ

def export_glb(path, objects=None, colors=True):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if objects is not None:
        bpy.ops.object.select_all(action='DESELECT')
        for o in objects: o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=objects is not None,
                              export_colors=colors, export_apply=True, export_yup=True)
    return path

def stats(obj):
    return f'{obj.name}: verts {len(obj.data.vertices)} tris {sum(len(p.vertices) - 2 for p in obj.data.polygons)}'
