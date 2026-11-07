"""Review render of the vegetation GLBs (Cycles CPU, textured, vertex AO):
    blender -b -P tools/blender/vegetation_preview.py -- <glb> <out.png> [name_prefix,...] [lod1]
"""
import bpy, os, sys, math
HERE = os.path.dirname(os.path.abspath(__file__))
TEX = os.path.normpath(os.path.join(HERE, '..', '..', 'assets', 'tex', 'vegetation'))
argv = sys.argv[sys.argv.index('--') + 1:]
glb, out = argv[0], argv[1]
names = argv[2].split(',') if len(argv) > 2 and argv[2] else None
lod1 = len(argv) > 3 and argv[3] == 'lod1'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
for o in bpy.data.objects:
    if o.type == 'MESH' and o.data.color_attributes: print('colattr', o.name, [a.name for a in o.data.color_attributes]); break


def img(n):
    p = os.path.join(TEX, n)
    return bpy.data.images.load(p) if os.path.exists(p) else None


def mat(name, albedo, alpha=None, rough=0.8):
    m = bpy.data.materials.new(name); m.use_nodes = True; nt = m.node_tree
    bsdf = nt.nodes['Principled BSDF']; bsdf.inputs['Roughness'].default_value = rough
    t = nt.nodes.new('ShaderNodeTexImage'); t.image = img(albedo)
    vc = nt.nodes.new('ShaderNodeVertexColor'); vc.layer_name = ''
    sep = nt.nodes.new('ShaderNodeSeparateColor'); nt.links.new(vc.outputs['Color'], sep.inputs['Color'])
    mul = nt.nodes.new('ShaderNodeMixRGB'); mul.blend_type = 'MULTIPLY'; mul.inputs['Fac'].default_value = 1.0
    nt.links.new(t.outputs['Color'], mul.inputs['Color1']); nt.links.new(sep.outputs['Red'], mul.inputs['Color2'])
    nt.links.new(mul.outputs['Color'], bsdf.inputs['Base Color'])
    if alpha:
        a = nt.nodes.new('ShaderNodeTexImage'); a.image = img(alpha); a.image.colorspace_settings.name = 'Non-Color'
        nt.links.new(a.outputs['Color'], bsdf.inputs['Alpha'])
        m.blend_method = 'CLIP'
        try: bsdf.inputs['Transmission Weight'].default_value = 0.25
        except Exception: pass
    return m


M = {'bark_oak': mat('bark_oak_r', 'bark_oak_albedo.jpg'), 'bark_birch': mat('bark_birch_r', 'bark_birch_albedo.jpg'), 'bark_pine': mat('bark_pine_r', 'bark_pine_albedo.jpg'),
     'leaf': mat('leaf_r', 'foliage_albedo.jpg', 'foliage_alpha.jpg', 0.6), 'cover': mat('cover_r', 'cover_albedo.jpg', 'cover_alpha.jpg', 0.7),
     'rock': mat('rock_r', 'rock_granite_albedo.jpg', None, 0.85)}
objs = [o for o in bpy.data.objects if o.type == 'MESH']
want = []
for o in objs:
    nm = o.name
    is1 = nm.endswith('_lod1')
    if is1 != lod1 or (names and not any(nm.startswith(p) for p in names)): o.hide_render = True; continue
    want.append(o)
groups = {}
for o in want: groups.setdefault(o.name.split('_wood')[0].split('_leaf')[0], []).append(o)
x = 0.0
for k in sorted(groups):
    gs = groups[k]
    w = max(max(abs(v.co.x) for v in o.data.vertices) for o in gs) if gs else 1
    x += w + 0.6
    for o in gs:
        o.location.x = x
        mn = o.data.materials[0].name if o.data.materials else ''
        o.data.materials.clear()
        if '_leaf' in o.name: o.data.materials.append(M['cover'] if o.name.startswith('fern') else M['leaf'])
        elif o.name.startswith('rock') or o.name.startswith('pebble'): o.data.materials.append(M['rock'])
        else: o.data.materials.append(M.get(mn, M['bark_oak']) if mn in M else M['bark_birch' if 'birch' in o.name else 'bark_pine' if 'fir' in o.name else 'bark_oak'])
    x += w + 0.6
bpy.ops.mesh.primitive_plane_add(size=400, location=(x / 2, 0, 0)); g = bpy.context.active_object
gm = bpy.data.materials.new('g'); gm.use_nodes = True; gm.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.16, 0.22, 0.09, 1); g.data.materials.append(gm)
sun = bpy.data.lights.new('sun', 'SUN'); sun.energy = 4.0; so = bpy.data.objects.new('sun', sun); bpy.context.scene.collection.objects.link(so)
so.rotation_euler = (math.radians(50), math.radians(10), math.radians(-35))
w = bpy.data.worlds.new('w'); bpy.context.scene.world = w; w.use_nodes = True; w.node_tree.nodes['Background'].inputs['Color'].default_value = (0.5, 0.62, 0.8, 1); w.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.9
H = 9.0 if not names or any(n.startswith(('oak', 'birch', 'fir', 'cherry')) for n in names) else 2.0
cam = bpy.data.cameras.new('c'); cam.lens = 40; co = bpy.data.objects.new('c', cam); bpy.context.scene.collection.objects.link(co)
dist = max(x * 0.62, H * 1.6)
co.location = (x / 2, -dist, H * 0.42); co.rotation_euler = (math.radians(88), 0, 0)
bpy.context.scene.camera = co
sc = bpy.context.scene; sc.render.engine = 'CYCLES'; sc.cycles.samples = 24; sc.cycles.device = 'CPU'; sc.cycles.use_denoising = False; sc.cycles.max_bounces = 3
sc.render.resolution_x = int(os.environ.get('RW', 1400)); sc.render.resolution_y = int(os.environ.get('RH', 560)); sc.render.filepath = out
sc.view_settings.view_transform = 'Standard'
bpy.ops.render.render(write_still=True)
print('rendered', out)
