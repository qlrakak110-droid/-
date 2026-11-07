"""Boulders: displaced icospheres, decimated to game density, vertex AO, smart UV. -> assets/models/boulder_{0..2}.glb"""
import sys, os, bpy, random, math
sys.path.insert(0, os.path.dirname(__file__)); import blib as B
OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'assets', 'models')
for k in range(3):
    B.reset(); random.seed(10 + k)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=6, radius=1.0); o = bpy.context.active_object; o.name = f'boulder_{k}'
    o.scale = (1.2 + random.random() * 0.4, 0.9 + random.random() * 0.4, 0.75 + random.random() * 0.3); B.apply_mods(o)
    bpy.ops.object.transform_apply(scale=True)
    B.displace(o, 'VORONOI', 0.8 + k * 0.1, 0.32, distance_metric='DISTANCE_SQUARED')
    B.displace(o, 'CLOUDS', 0.4, 0.14, noise_depth=4)
    B.displace(o, 'CLOUDS', 0.1, 0.03, noise_depth=2)
    B.apply_mods(o)
    for v in o.data.vertices:                      # flatten the underside so it sits on the ground
        if v.co.z < -0.35: v.co.z = -0.35 + (v.co.z + 0.35) * 0.15
    B.decimate(o, 0.12); B.smooth(o); B.smart_uv(o)
    bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, -0.37)); ground = bpy.context.active_object
    B.vertex_ao(o, rays=28, dist=1.2)
    bpy.data.objects.remove(ground)
    B.material(o, 'rock_a', (0.55, 0.52, 0.48, 1), 0.85)
    print(B.stats(o))
    B.export_glb(os.path.join(OUT, f'boulder_{k}.glb'), [o])
print('DONE')
