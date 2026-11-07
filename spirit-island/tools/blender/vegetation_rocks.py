"""Boulders and pebble clusters (triplanar-textured at runtime, so no UVs):
    blender -b -P tools/blender/vegetation_rocks.py      -> assets/models/vegetation/rocks.glb
rock_0..rock_4: weathered boulders (~2.5k tris): squashed, Voronoi-faceted, split by 3-6 fracture planes (flat broken
faces with crisp edges), fine noise, flat sunk underside. Size ~2 units across, bottom at z = -0.2 (sinks into the
ground when placed at ground height).  pebble_0, pebble_1: clusters of 5-7 small stones (~400 tris).
COLOR_0: R = AO (ray cast, including the ground plane), G = convexity (edge wear: 1 on ridges, 0 in hollows),
B = upness for moss / dirt (1 facing up, also stored for convenience), A = 1.
"""
import bpy, bmesh, math, random, os, sys
from mathutils import Vector
from mathutils.bvhtree import BVHTree
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import blib as B
OUT = os.path.normpath(os.path.join(HERE, '..', '..', 'assets', 'models', 'vegetation'))


def fracture(o, rng, n):
    me = o.data
    planes = []
    for k in range(n):
        d = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.25, 1.0))).normalized()
        planes.append((d, rng.uniform(0.45, 0.68)))
    for v in me.vertices:
        for d, off in planes:
            s = v.co.dot(d) - off
            if s > 0: v.co -= d * s * 0.94


def make_rock(name, seed, tris=2600):
    rng = random.Random(seed)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=6, radius=1.0); o = bpy.context.active_object; o.name = name
    o.scale = (rng.uniform(1.0, 1.35), rng.uniform(0.8, 1.1), rng.uniform(0.62, 0.9)); bpy.ops.object.transform_apply(scale=True)
    B.displace(o, 'VORONOI', rng.uniform(0.7, 1.0), 0.28, distance_metric='DISTANCE_SQUARED')
    B.displace(o, 'CLOUDS', 0.55, 0.16, noise_depth=3)
    B.apply_mods(o)
    fracture(o, rng, rng.randint(3, 6))
    B.displace(o, 'CLOUDS', 0.18, 0.05, noise_depth=3)
    B.displace(o, 'VORONOI', 0.08, 0.02, distance_metric='DISTANCE')
    B.apply_mods(o)
    me = o.data
    zs = [v.co.z for v in me.vertices]; zmin = min(zs)
    cut = zmin + (max(zs) - zmin) * 0.22
    for v in me.vertices:
        if v.co.z < cut: v.co.z = cut + (v.co.z - cut) * 0.12
    # centre, put the base at z = -0.2, normalise the footprint to ~1 radius
    xs = [v.co.x for v in me.vertices]; ys = [v.co.y for v in me.vertices]; zs = [v.co.z for v in me.vertices]
    cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2; zb = min(zs)
    rad = max(max(xs) - min(xs), max(ys) - min(ys)) / 2
    for v in me.vertices:
        v.co.x = (v.co.x - cx) / rad; v.co.y = (v.co.y - cy) / rad; v.co.z = (v.co.z - zb) / rad - 0.2
    me.update()
    ratio = tris / max(1, sum(len(p.vertices) - 2 for p in me.polygons))
    B.decimate(o, ratio)
    B.smooth(o)
    me.use_auto_smooth = True; me.auto_smooth_angle = math.radians(48)
    return o


def make_pebbles(name, seed, n):
    rng = random.Random(seed)
    parts = []
    for k in range(n):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=1.0); o = bpy.context.active_object
        r = rng.uniform(0.05, 0.14) * (1.6 if k == 0 else 1)
        o.scale = (r * rng.uniform(1.0, 1.5), r * rng.uniform(0.8, 1.1), r * rng.uniform(0.45, 0.7)); bpy.ops.object.transform_apply(scale=True)
        B.displace(o, 'VORONOI', 0.5 * r / 0.1, r * 0.25, distance_metric='DISTANCE_SQUARED'); B.apply_mods(o)
        a = rng.random() * 6.28; d = 0 if k == 0 else rng.uniform(0.12, 0.38)
        o.location = (math.cos(a) * d, math.sin(a) * d, 0); o.rotation_euler = (0, 0, rng.random() * 6.28)
        bpy.ops.object.transform_apply(location=True, rotation=True)
        zs = [v.co.z for v in o.data.vertices]; zb = min(zs)
        for v in o.data.vertices: v.co.z -= zb + (max(zs) - zb) * 0.3       # sunk by 30 %
        B.decimate(o, 70 / max(1, len(o.data.polygons)))
        parts.append(o)
    o = B.join(parts, name); B.smooth(o)
    o.data.use_auto_smooth = True; o.data.auto_smooth_angle = math.radians(50)
    return o


def bake(o, rays=20, dist=1.4):
    random.seed(5)
    bm = bmesh.new(); bm.from_mesh(o.data); t1 = BVHTree.FromBMesh(bm)
    # vertex convexity from the bmesh neighbourhood
    bm.verts.ensure_lookup_table()
    conv = []
    for v in bm.verts:
        if not v.link_edges: conv.append(0.5); continue
        c = sum(((e.other_vert(v).co - v.co).dot(v.normal) for e in v.link_edges)) / len(v.link_edges)
        L = sum((e.other_vert(v).co - v.co).length for e in v.link_edges) / len(v.link_edges)
        conv.append(max(0.0, min(1.0, 0.5 - 2.5 * c / max(L, 1e-5))))
    bm.free()
    g = bmesh.new(); vs = [g.verts.new(v) for v in [(-20, -20, 0), (20, -20, 0), (20, 20, 0), (-20, 20, 0)]]; g.faces.new(vs); t2 = BVHTree.FromBMesh(g); g.free()
    dirs = []
    while len(dirs) < rays:
        v = Vector((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-1, 1)))
        if 0.05 < v.length <= 1: dirs.append(v.normalized())
    me = o.data
    ca = me.color_attributes.new('Col', 'FLOAT_COLOR', 'POINT')
    cols = []
    for i, v in enumerate(me.vertices):
        n = v.normal; p = v.co + n * 0.01; hit = 0.0; tot = 0.0
        for d in dirs:
            if d.dot(n) < 0: d = -d
            w = d.dot(n); tot += w
            for t in (t1, t2):
                h = t.ray_cast(p, d, dist)
                if h[0] is not None: hit += w * (1 - (h[3] / dist) ** 1.3); break
        ao = max(0.1, 1 - hit / max(tot, 1e-6))
        cols += [ao, conv[i], max(0.0, n.z), 1.0]
    ca.data.foreach_set('color', cols)
    me.color_attributes.active_color = ca


def main():
    B.reset(); os.makedirs(OUT, exist_ok=True)
    objs = []
    for k in range(5):
        o = make_rock(f'rock_{k}', 100 + k * 13, tris=2600)
        objs.append(o)
    objs.append(make_pebbles('pebble_0', 7, 6)); objs.append(make_pebbles('pebble_1', 9, 7))
    for i, o in enumerate(objs):
        # bake alone (others out of the way)
        for q in objs: q.location.x = 0 if q is o else 100 + objs.index(q) * 10
        bpy.context.view_layer.update()
        bake(o, dist=1.4 if o.name.startswith('rock') else 0.3)
        print(o.name, 'tris', sum(len(p.vertices) - 2 for p in o.data.polygons), 'verts', len(o.data.vertices))
    for q in objs: q.location.x = 0
    path = os.path.join(OUT, 'rocks.glb')
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_colors=True, export_normals=True,
                              export_apply=True, export_yup=True, export_materials='PLACEHOLDER', export_texcoords=False)
    import vegetation_glb as Q
    s0 = os.path.getsize(path); Q.quantize(path)
    print('wrote', path, s0, '->', os.path.getsize(path))


main()
