# edlib previews: Cycles CPU stills of a hero in Blender (turntable sheet front / three-quarter / side / back + bust +
# silhouette on white) under a neutral studio or the "arena night" light rig. Small frames, few samples, two threads:
# the machine is shared. Judge materials in the engine (the art / asset labs); judge FORM, proportion, folds and
# silhouette here.

import bpy
import math
import os
import numpy as np
from mathutils import Vector, Matrix
from .core import THREADS, ROOT, log, collection, link

_RIG_COLL = '_lights'


def _clear_lights():
    c = bpy.data.collections.get(_RIG_COLL)
    if c:
        for o in list(c.objects):
            bpy.data.objects.remove(o, do_unlink=True)
    return collection(_RIG_COLL)


def _area(name, pos, target, size, power, color, coll):
    L = bpy.data.lights.new(name, 'AREA')
    L.shape = 'DISK'; L.size = size; L.energy = power; L.color = color
    o = bpy.data.objects.new(name, L)
    link(o, coll)
    o.location = pos
    d = Vector(target) - Vector(pos)
    o.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    return o


def _world(color, strength=1.0, horizon=None):
    w = bpy.context.scene.world or bpy.data.worlds.new('world')
    bpy.context.scene.world = w
    try:
        w.use_nodes = True
    except Exception:
        pass
    nt = w.node_tree
    bg = next((n for n in nt.nodes if n.type == 'BACKGROUND'), None)
    if bg is None:
        bg = nt.nodes.new('ShaderNodeBackground')
        out = next((n for n in nt.nodes if n.type == 'OUTPUT_WORLD'), None) or nt.nodes.new('ShaderNodeOutputWorld')
        nt.links.new(bg.outputs[0], out.inputs[0])
    for l in list(bg.inputs['Color'].links):
        nt.links.remove(l)
    bg.inputs['Color'].default_value = tuple(color) + (1.0,)
    bg.inputs['Strength'].default_value = strength
    return w


def _floor(coll, color=(0.18, 0.18, 0.19), rough=0.7):
    me = bpy.data.meshes.new('_floor')
    s = 30.0
    me.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)], [], [(0, 1, 2, 3)])
    o = bpy.data.objects.new('_floor', me)
    link(o, coll)
    m = bpy.data.materials.new('_floor')
    try:
        m.use_nodes = True
    except Exception:
        pass
    b = next((n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    if b:
        b.inputs['Base Color'].default_value = tuple(color) + (1,)
        b.inputs['Roughness'].default_value = rough
    me.materials.append(m)
    return o


def light_rig(kind='studio', height=1.9):
    """
    Lights + world + floor. 'studio': neutral grey room, large warm key (front-left, high), soft fill, cool rim.
    'arena': the game's night: ink-blue ambience, warm lantern key from low front-right, cold corona rim from behind.
    'white': flat white world for silhouettes (use with silhouette=True).
    """
    coll = _clear_lights()
    h = height
    if kind == 'studio':
        _world((0.06, 0.062, 0.068), 1.0)
        _area('key', (-2.4, -3.4, h * 1.55), (0, 0, h * 0.6), 2.4, 900, (1.0, 0.95, 0.88), coll)
        _area('fill', (3.2, -2.2, h * 0.8), (0, 0, h * 0.55), 3.5, 260, (0.82, 0.88, 1.0), coll)
        _area('rim', (1.6, 3.4, h * 1.4), (0, 0, h * 0.7), 1.6, 700, (0.8, 0.9, 1.0), coll)
        _area('rim2', (-2.6, 2.8, h * 1.0), (0, 0, h * 0.6), 1.4, 380, (0.85, 0.9, 1.0), coll)
        _floor(coll)
    elif kind == 'arena':
        _world((0.006, 0.008, 0.016), 1.0)
        _area('lantern', (1.8, -2.6, h * 0.42), (0, 0, h * 0.55), 0.9, 520, (1.0, 0.55, 0.22), coll)
        _area('corona', (-1.2, 3.6, h * 1.65), (0, 0, h * 0.7), 1.8, 1100, (0.62, 0.74, 1.0), coll)
        _area('corona2', (2.8, 2.4, h * 1.1), (0, 0, h * 0.6), 1.2, 420, (0.55, 0.62, 1.0), coll)
        _area('sky', (0, -0.5, h * 3.0), (0, 0, h * 0.5), 5.0, 160, (0.4, 0.5, 0.9), coll)
        _floor(coll, (0.05, 0.05, 0.055), 0.55)
    else:
        _world((1, 1, 1), 1.0)
    return coll


def camera(target, dist, yaw=0.0, pitch=4.0, lens=70.0, name='_cam'):
    """
    Camera orbiting `target` (Blender space). yaw 0 = front view, 35 = three-quarter toward the game camera side (the
    hero's right), 90 = the game's side view (hero facing screen right), 180 = back. Degrees.
    """
    cam = bpy.data.objects.get(name)
    if cam is None:
        cam = bpy.data.objects.new(name, bpy.data.cameras.new(name))
        link(cam)
    cam.data.lens = lens
    cam.data.clip_start = 0.05; cam.data.clip_end = 100
    y, p = math.radians(yaw), math.radians(pitch)
    t = Vector(target)
    cam.location = t + Vector((-math.sin(y) * math.cos(p) * dist, -math.cos(y) * math.cos(p) * dist, math.sin(p) * dist))
    cam.rotation_euler = (t - cam.location).to_track_quat('-Z', 'Y').to_euler()
    bpy.context.scene.camera = cam
    return cam


def _silhouette(on):
    vl = bpy.context.view_layer
    if on:
        m = bpy.data.materials.get('_sil')
        if m is None:
            m = bpy.data.materials.new('_sil')
            try:
                m.use_nodes = True
            except Exception:
                pass
            nt = m.node_tree
            for n in list(nt.nodes):
                nt.nodes.remove(n)
            e = nt.nodes.new('ShaderNodeEmission'); e.inputs['Color'].default_value = (0, 0, 0, 1)
            o = nt.nodes.new('ShaderNodeOutputMaterial')
            nt.links.new(e.outputs[0], o.inputs[0])
        vl.material_override = m
    else:
        vl.material_override = None


def render_still(path, size=(480, 540), samples=12, denoise=True):
    """Render the current camera to `path` (PNG). Cycles CPU, thread limited."""
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = samples
    sc.cycles.use_adaptive_sampling = False
    sc.cycles.max_bounces = 3
    sc.render.threads_mode = 'FIXED'; sc.render.threads = THREADS
    sc.render.resolution_x, sc.render.resolution_y = size
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = 'PNG'
    sc.render.film_transparent = False
    try:
        sc.cycles.use_denoising = bool(denoise)
        if denoise:
            sc.cycles.denoiser = 'OPENIMAGEDENOISE'
    except Exception:
        sc.cycles.use_denoising = False
    sc.render.filepath = path
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.render.render(write_still=True)
    return path


def _load(path):
    img = bpy.data.images.load(path)
    w, h = img.size
    a = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    bpy.data.images.remove(img)
    return a.reshape(h, w, 4)


def _save(arr, path):
    h, w = arr.shape[0], arr.shape[1]
    img = bpy.data.images.new('_sheet', w, h, alpha=False)
    img.pixels.foreach_set(np.ascontiguousarray(arr, dtype=np.float32).reshape(-1))
    img.filepath_raw = path
    img.file_format = 'PNG'
    img.save()
    bpy.data.images.remove(img)


def contact_sheet(paths, out, cols=4, pad=4, bg=(0.04, 0.04, 0.045), rows=None):
    """Compose rendered PNGs into one sheet: `rows` = lists of paths (each row packed left to right), else row-major by cols."""
    if rows is None:
        rows = [paths[i:i + cols] for i in range(0, len(paths), cols)]
    R = [[_load(p) for p in r] for r in rows if r]
    rh = [max(i.shape[0] for i in r) for r in R]
    rw = [sum(i.shape[1] for i in r) + pad * (len(r) + 1) for r in R]
    W = max(rw); H = sum(rh) + pad * (len(R) + 1)
    sheet = np.ones((H, W, 4), dtype=np.float32)
    sheet[:, :, :3] = bg
    top = pad
    for r, h in zip(R, rh):
        x = pad
        for im in r:
            y = H - top - im.shape[0]          # image rows are bottom-up
            sheet[y: y + im.shape[0], x: x + im.shape[1]] = im
            x += im.shape[1] + pad
        top += h + pad
    _save(sheet, out)
    return out


def preview_sheet(label, name='sheet', height=1.95, rig='studio', hide=(), samples=12, cell=(300, 520), bust=True, silhouette=True, extra_views=(), yaw_bust=28,
                  out_dir=None, focus=None):
    """
    The standard review sheet -> shots/blender/<label>/<name>.png: front, three-quarter, side (the game's fight view),
    back; then a bust close-up, the black silhouette on white and a three-quarter under the other light rig.
      height   the hero's height (m): framing follows it        rig   'studio' | 'arena'
      hide     objects hidden in the renders (armature, colliders)     focus   bust target height (default 0.86 x height)
      extra_views   [(yaw, pitch, target_z, dist)] more cells
    Returns the sheet path. Read it.
    """
    out_dir = out_dir or os.path.join(ROOT, 'shots', 'blender', label)
    os.makedirs(out_dir, exist_ok=True)
    tmp = os.path.join(out_dir, '_cells')
    for o in hide:
        o.hide_render = True
    for o in bpy.context.scene.objects:
        if o.type == 'ARMATURE':
            o.hide_render = True
    h = height
    tgt = (0, 0, h * 0.5)
    dist = h * 2.75 * max(1.0, (cell[1] / cell[0]) / (520 / 300)) ** 0
    paths = []
    light_rig(rig, h)
    for i, yaw in enumerate((0, 35, 90, 180)):
        camera(tgt, dist, yaw, 3.0, 85)
        paths.append(render_still(os.path.join(tmp, f'{name}_v{i}.png'), cell, samples))
    row2 = []
    if bust:
        camera((0, 0, focus or h * 0.86), h * 1.02, yaw_bust, 2.0, 85)
        row2.append(render_still(os.path.join(tmp, f'{name}_bust.png'), (cell[0] * 2, cell[1]), samples + 4))
    if silhouette:
        light_rig('white', h)
        _silhouette(True)
        camera(tgt, dist, 90, 3.0, 85)
        row2.append(render_still(os.path.join(tmp, f'{name}_sil.png'), cell, 1, denoise=False))
        _silhouette(False)
    light_rig('arena' if rig == 'studio' else 'studio', h)
    camera(tgt, dist, 35, 3.0, 85)
    row2.append(render_still(os.path.join(tmp, f'{name}_alt.png'), cell, samples))
    for k, (yaw, pitch, tz, d) in enumerate(extra_views):
        light_rig(rig, h)
        camera((0, 0, tz), d, yaw, pitch, 85)
        row2.append(render_still(os.path.join(tmp, f'{name}_x{k}.png'), cell, samples))
    out = os.path.join(out_dir, name + '.png')
    contact_sheet(None, out, rows=[paths, row2])
    light_rig(rig, h)
    log('preview sheet', os.path.relpath(out, ROOT))
    return out


def render_view(label, name, target, dist, yaw=30, pitch=4, size=(640, 540), rig='studio', samples=14, height=1.95, lens=85, out_dir=None):
    """One close-up still -> shots/blender/<label>/<name>.png (details: hands, lacing, weave, knots)."""
    out_dir = out_dir or os.path.join(ROOT, 'shots', 'blender', label)
    for o in bpy.context.scene.objects:
        if o.type == 'ARMATURE':
            o.hide_render = True
    light_rig(rig, height)
    camera(target, dist, yaw, pitch, lens)
    return render_still(os.path.join(out_dir, name + '.png'), size, samples)
