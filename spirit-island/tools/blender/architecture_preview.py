"""Review render of the village GLBs (Cycles CPU, textured, vertex AO, roof tiles instanced from the variant meta):
    blender -b -P tools/blender/architecture_preview.py -- <out.png> [variants=A,B,C] [cam=x,y,z,lx,ly,lz (game coords)] [size=W,H]
"""
import bpy, os, sys, math, random
from mathutils import Vector, Matrix
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..', 'assets'))
TEX = os.path.join(ROOT, 'tex', 'architecture')
argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
out = argv[0] if argv else '/tmp/arch_prev.png'
opts = dict(a.split('=') for a in argv[1:])
variants = opts.get('variants', 'A,B,C').split(',')
size = [int(x) for x in opts.get('size', '1200,560').split(',')]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, 'models', 'architecture', 'houses.glb'))
bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, 'models', 'architecture', 'tiles.glb'))
B = lambda p: Vector((p[0], -p[2], p[1]))


def img(n, col=True):
    p = os.path.join(TEX, n)
    if not os.path.exists(p): return None
    im = bpy.data.images.load(p)
    if not col: im.colorspace_settings.name = 'Non-Color'
    return im


def mat(name, tex=None, tint=(1, 1, 1), rough=0.8, metal=0.0, vc='R', emit=None, glass=False):
    m = bpy.data.materials.new(name); m.use_nodes = True; nt = m.node_tree
    bsdf = nt.nodes['Principled BSDF']; bsdf.inputs['Roughness'].default_value = rough; bsdf.inputs['Metallic'].default_value = metal
    col = None
    if tex:
        t = nt.nodes.new('ShaderNodeTexImage'); t.image = img(tex + '_albedo.jpg'); col = t.outputs['Color']
        n = nt.nodes.new('ShaderNodeTexImage'); n.image = img(tex + '_normal.jpg', False)
        nm = nt.nodes.new('ShaderNodeNormalMap'); nt.links.new(n.outputs['Color'], nm.inputs['Color']); nt.links.new(nm.outputs['Normal'], bsdf.inputs['Normal'])
        o = nt.nodes.new('ShaderNodeTexImage'); o.image = img(tex + '_orm.jpg', False)
        sp = nt.nodes.new('ShaderNodeSeparateColor'); nt.links.new(o.outputs['Color'], sp.inputs['Color']); nt.links.new(sp.outputs['Green'], bsdf.inputs['Roughness'])
    tn = nt.nodes.new('ShaderNodeRGB'); tn.outputs[0].default_value = (*tint, 1)
    mul = nt.nodes.new('ShaderNodeMixRGB'); mul.blend_type = 'MULTIPLY'; mul.inputs['Fac'].default_value = 1
    if col: nt.links.new(col, mul.inputs['Color1'])
    else: mul.inputs['Color1'].default_value = (1, 1, 1, 1)
    nt.links.new(tn.outputs[0], mul.inputs['Color2'])
    last = mul.outputs['Color']
    if vc:
        v = nt.nodes.new('ShaderNodeVertexColor')
        sp2 = nt.nodes.new('ShaderNodeSeparateColor'); nt.links.new(v.outputs['Color'], sp2.inputs['Color'])
        m2 = nt.nodes.new('ShaderNodeMixRGB'); m2.blend_type = 'MULTIPLY'; m2.inputs['Fac'].default_value = 1
        nt.links.new(last, m2.inputs['Color1'])
        if vc == 'RGB': nt.links.new(v.outputs['Color'], m2.inputs['Color2'])
        else:
            # AO (R) and grime (B): darken toward a dirt colour
            ao = nt.nodes.new('ShaderNodeMath'); ao.operation = 'MULTIPLY_ADD'; ao.inputs[1].default_value = 0.6; ao.inputs[2].default_value = 0.4
            nt.links.new(sp2.outputs['Red'], ao.inputs[0])
            gr = nt.nodes.new('ShaderNodeMath'); gr.operation = 'MULTIPLY_ADD'; gr.inputs[1].default_value = -0.5; gr.inputs[2].default_value = 1.0
            nt.links.new(sp2.outputs['Blue'], gr.inputs[0])
            mm = nt.nodes.new('ShaderNodeMath'); mm.operation = 'MULTIPLY'; nt.links.new(ao.outputs[0], mm.inputs[0]); nt.links.new(gr.outputs[0], mm.inputs[1])
            nt.links.new(mm.outputs[0], m2.inputs['Color2'])
        last = m2.outputs['Color']
    nt.links.new(last, bsdf.inputs['Base Color'])
    if emit:
        bsdf.inputs['Emission Color'].default_value = (*emit, 1); bsdf.inputs['Emission Strength'].default_value = 3.0
    if glass:
        bsdf.inputs['Base Color'].default_value = (0.02, 0.025, 0.03, 1); bsdf.inputs['Roughness'].default_value = 0.05
        bsdf.inputs['Specular IOR Level'].default_value = 0.35
    return m


def hexc(h): return tuple(((h >> s) & 255) / 255 for s in (16, 8, 0))
def lin(c): return tuple(x ** 2.2 for x in c)
WALL = {'A': 0xf3e6d2, 'B': 0xf0dcc8, 'C': 0xe8e0d0}; ROOFC = {'A': 0x4e5aa8, 'B': 0xc4584a, 'C': 0x4f8a5a}; SHUT = {'A': 0x3f6aa8, 'B': 0x4f7a5a, 'C': 0x9a5a3a}
mats = {}
for v in 'ABC':
    mats[v] = {
        'plaster': mat('plaster' + v, 'arch_plaster', lin(hexc(WALL[v]))), 'timber': mat('timber' + v, 'arch_wood', lin(hexc(0x7a5a42))),
        'wood': mat('wood' + v, 'arch_wood', lin(hexc(0xb59a7c))), 'door': mat('door' + v, 'arch_wood', lin(hexc(0xa8724a))),
        'paint': mat('paint' + v, 'arch_wood', lin(hexc(SHUT[v]))), 'stone': mat('stone' + v, 'arch_stone'), 'iron': mat('iron' + v, 'arch_iron', metal=0.6),
        'glass': mat('glass' + v, glass=True, vc=None), 'cloth': mat('cloth' + v, tint=(0.8, 0.75, 0.65)), 'glow': mat('glow' + v, emit=(1, 0.7, 0.4), vc=None),
        'flora': mat('flora' + v, vc='RGB', rough=0.7), 'clay': mat('clay' + v, 'arch_tile', lin(hexc(0xb0583a))),
        'tile': mat('tile' + v, 'arch_tile', lin(hexc(ROOFC[v])), rough=0.45, vc='RGB'),
    }
tiles = {o.name: o for o in bpy.data.objects if o.name in ('tile_hi', 'ridge_hi', 'tile_lo', 'ridge_lo')}
for o in tiles.values(): o.hide_render = True
offs = {'A': -9.5, 'B': 0.0, 'C': 9.5} if len(variants) > 1 else {variants[0]: 0.0}
rnd = random.Random(5)


def place(src, M, matl):
    o = bpy.data.objects.new('t', src.data); o.matrix_world = M; bpy.context.scene.collection.objects.link(o)
    o.hide_render = False
    if not o.material_slots: o.data.materials.append(None) if not o.data.materials else None
    o.material_slots[0].link = 'OBJECT'; o.material_slots[0].material = matl
    return o


for o in list(bpy.data.objects):
    key = o.name.split('_')[0]
    if key not in 'ABC' or o.name in tiles: continue
    if key not in variants: o.hide_render = True; continue
    o.location.x += offs[key]
    if o.type == 'MESH':
        b = o.name.split('_', 1)[1]
        if b in mats[key]: o.data.materials.clear(); o.data.materials.append(mats[key][b])
    if o.name.endswith('_meta'):
        R = list(o['roof']); off = Vector((offs[key], 0, 0))
        tm = bpy.data.materials.new('tm'); tm = mats[key]['tile']
        for i in range(0, len(R), 11):
            org, u, vv, U, Vl = Vector(R[i:i + 3]), Vector(R[i + 3:i + 6]), Vector(R[i + 6:i + 9]), R[i + 9], R[i + 10]
            n = vv.cross(u)
            if n.y < 0: org = org + u * U; u = -u; n = -n
            cols = max(1, round(U / 0.3)); w = U / cols; rows = int((Vl + 0.06) / 0.3) + 1
            for r_ in range(rows):
                s = -0.06 + r_ * 0.3
                for c in range(cols):
                    p = org + u * ((c + 0.5) * w + rnd.uniform(-0.006, 0.006)) + vv * s + n * 0.034
                    z = (vv * 0.4 - n * 0.016).normalized(); x = u * (w / 0.3); y = z.cross(u).normalized()
                    Mg = Matrix(((x.x, y.x, z.x, p.x), (x.y, y.y, z.y, p.y), (x.z, y.z, z.z, p.z), (0, 0, 0, 1)))
                    C = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))       # game -> blender
                    place(tiles['tile_hi'], Matrix.Translation(off) @ C @ Mg @ C.inverted(), tm)
        Rg = list(o['ridge'])
        for i in range(0, len(Rg), 7):
            org, d, Ln = Vector(Rg[i:i + 3]), Vector(Rg[i + 3:i + 6]), Rg[i + 6]
            n = int(Ln / 0.36) + 1
            for k in range(n):
                p = org + d * (k * Ln / n) + Vector((0, 0.07, 0)); z = d; x = Vector((0, 1, 0)).cross(z).normalized(); y = z.cross(x)
                Mg = Matrix(((x.x, y.x, z.x, p.x), (x.y, y.y, z.y, p.y), (x.z, y.z, z.z, p.z), (0, 0, 0, 1)))
                C = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
                place(tiles['ridge_hi'], Matrix.Translation(off) @ C @ Mg @ C.inverted(), tm)
# ground
bpy.ops.mesh.primitive_plane_add(size=80, location=(0, 0, 0)); g = bpy.context.active_object
gm = bpy.data.materials.new('g'); gm.use_nodes = True; gm.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.16, 0.2, 0.09, 1); g.data.materials.append(gm)
# light
sun = bpy.data.lights.new('sun', 'SUN'); sun.energy = 4.5; sun.angle = math.radians(2)
so = bpy.data.objects.new('sun', sun); so.rotation_euler = (math.radians(50), 0, math.radians(35)); bpy.context.scene.collection.objects.link(so)
w = bpy.data.worlds.new('w'); bpy.context.scene.world = w; w.use_nodes = True
w.node_tree.nodes['Background'].inputs['Color'].default_value = (0.45, 0.58, 0.8, 1); w.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.9
cam = bpy.data.cameras.new('c'); cam.lens = float(opts.get('lens', 35)); co = bpy.data.objects.new('c', cam); bpy.context.scene.collection.objects.link(co)
cv = [float(x) for x in opts.get('cam', '6,5.5,24,0,2.6,0').split(',')]
co.location = B(cv[:3]); d = B(cv[3:]) - co.location
co.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
sc = bpy.context.scene; sc.camera = co; sc.render.engine = 'CYCLES'; sc.cycles.samples = int(opts.get('spp', 24)); sc.cycles.device = 'CPU'
try: sc.cycles.use_denoising = False
except Exception: pass
sc.render.resolution_x, sc.render.resolution_y = size; sc.render.filepath = out
sc.view_settings.view_transform = 'Filmic' if 'Filmic' in [x.identifier for x in type(sc.view_settings).bl_rna.properties['view_transform'].enum_items] else 'Standard'
bpy.ops.render.render(write_still=True)
print('rendered', out)
