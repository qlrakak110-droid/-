# edlib exporter: the compact binary hero asset (EDM1) + JSON manifest + the generated JS module that embeds it.
#
#   <hero>.edm   'EDM1' | u32 json length | JSON (utf-8, space padded to 4) | data block
#   JSON         { format, hero, bones?, looks[], panels[], textures[], parts[] }   (see tools/blender/README.md)
#   part         quantised vertex streams, all offsets relative to the data block and 4-byte aligned:
#                  pos   u16 x 4  (x, y, z in the part's bounding box bmin..bmax; 4th: 0)        GAME space, bind pose
#                  nrm   i8 x 3 + u8 cavity (cav / 2 * 255)
#                  col   u8 x 3 (sqrt(colour / 2)) + u8 look index
#                  glow  u8 x 4  (inlay, vein, eye masks, 0)                                      optional
#                  uvw   u16 x 4 ((u, v, code) in uvwMin..uvwMax; 4th: 0)                         optional (UV texture sets)
#                  uv    u16 x 2  (0..1, baked-map texture coordinates)                           optional
#                  skin  u8 x 4 bone palette indices + u8 x 4 weights (sum 255)
#                  cloth u16 x 4  (panel u, panel v, cloth share, 0)                              optional (flag 'cloth')
#                  idx   u16 / u32 triangle indices
#                vertices are sorted by look: runs[] = { look, v0, vn, i0, in } (one kit piece per run at load)
# Everything is deterministic: the same scripts give the same bytes (the manifest carries the script hash).

import bpy
import json
import os
import struct
import time
import numpy as np
from .core import (ROOT, HERE, b2g, get_attr, get_weights, log, file_hash, select)
from . import skin as SK


def _mesh_arrays(obj):
    """Evaluated, triangulated mesh -> per-corner arrays (position index, normal, material, uv)."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    # export what the artist authored: modifiers other than Armature must be applied; armature deformation is skipped
    me = obj.data
    me.calc_loop_triangles()
    nt = len(me.loop_triangles)
    loops = np.empty(nt * 3, dtype=np.int32); me.loop_triangles.foreach_get('loops', loops)
    verts = np.empty(nt * 3, dtype=np.int32); me.loop_triangles.foreach_get('vertices', verts)
    mat = np.empty(nt, dtype=np.int32); me.loop_triangles.foreach_get('material_index', mat)
    nl = len(me.loops)
    cn = np.empty(nl * 3, dtype=np.float32)
    me.corner_normals.foreach_get('vector', cn)
    cn = cn.reshape(-1, 3)[loops]
    uv = None
    layer = me.uv_layers.get('ed_bake') or (me.uv_layers.active if len(me.uv_layers) else None)
    if layer is not None:
        a = np.empty(nl * 2, dtype=np.float32); layer.data.foreach_get('uv', a)
        uv = a.reshape(-1, 2)[loops]
    P = np.empty(len(me.vertices) * 3, dtype=np.float32); me.vertices.foreach_get('co', P)
    return P.reshape(-1, 3).astype(np.float64), verts, cn.astype(np.float64), np.repeat(mat, 3), uv


def _gather(obj, look_index, looks):
    """One object -> unique-vertex arrays in game space."""
    P, vidx, cn, cmat, cuv = _mesh_arrays(obj)
    me = obj.data
    nv = len(P)
    # look per corner (material slot -> global look index)
    slot_to_look = []
    for m in me.materials:
        if m is None or 'ed_look' not in m:
            raise ValueError(f'{obj.name}: material slot without a look (use edlib.look / assign_look)')
        L = json.loads(m['ed_look'])
        if L['name'] not in look_index:
            look_index[L['name']] = len(looks); looks.append(L)
        slot_to_look.append(look_index[L['name']])
    if not slot_to_look:
        raise ValueError(f'{obj.name}: no look assigned')
    clook = np.array(slot_to_look, dtype=np.int32)[np.clip(cmat, 0, len(slot_to_look) - 1)]
    nq = np.clip(np.round(cn * 127), -127, 127).astype(np.int32)
    key = [vidx, nq[:, 0], nq[:, 1], nq[:, 2], clook]
    if cuv is not None:
        uq = np.clip(np.round(cuv * 65535), 0, 65535).astype(np.int32)
        key += [uq[:, 0], uq[:, 1]]
    K = np.stack(key, axis=1)
    uniq, first, inv = np.unique(K, axis=0, return_index=True, return_inverse=True)
    inv = inv.reshape(-1)
    vi = vidx[first]
    out = {
        'pos': b2g(P[vi]), 'nrm': b2g(cn[first]), 'look': clook[first], 'tri': inv.reshape(-1, 3),
        'uv': cuv[first] if cuv is not None else None,
    }
    col = get_attr(obj, 'ed_col'); cav = get_attr(obj, 'ed_cav'); glow = get_attr(obj, 'ed_glow'); uvw = get_attr(obj, 'ed_uvw'); cl = get_attr(obj, 'ed_cloth')
    out['col'] = col[vi, :3].astype(np.float64) if col is not None else np.ones((len(vi), 3))
    out['cav'] = cav[vi].astype(np.float64) if cav is not None else np.ones(len(vi))
    out['glow'] = glow[vi].astype(np.float64) if glow is not None else None
    out['uvw'] = uvw[vi].astype(np.float64) if uvw is not None else None
    out['cloth'] = cl[vi].astype(np.float64) if cl is not None and obj.get('ed_panel') else None
    W = get_weights(obj)
    W = SK.limit_normalize(W, 4) if W else {}
    names = list(W.keys())
    if names:
        A = np.stack([W[n] for n in names], axis=1)[vi]
    else:
        A = np.zeros((len(vi), 0))
    out['wnames'] = names; out['w'] = A
    return out


def _quant_weights(A, share=None):
    """(N, B) float weights -> u8 indices x4 / weights x4 summing to 255 (or to 255 * (1 - cloth share))."""
    n = len(A)
    idx = np.zeros((n, 4), dtype=np.uint8); w8 = np.zeros((n, 4), dtype=np.uint8)
    if A.shape[1] == 0:
        return idx, w8
    k = min(4, A.shape[1])
    order = np.argsort(-A, axis=1)[:, :k]
    top = np.take_along_axis(A, order, axis=1)
    s = top.sum(axis=1, keepdims=True)
    top = np.where(s > 1e-9, top / np.maximum(s, 1e-9), 0)
    total = np.full(n, 255.0) if share is None else np.round(255.0 * (1 - share))
    q = np.floor(top * total[:, None]).astype(np.int32)
    rem = (total - q.sum(axis=1)).astype(np.int32)
    has = s[:, 0] > 1e-9
    q[has, 0] += rem[has]                                  # the largest influence takes the rounding remainder
    idx[:, :k] = np.where(q > 0, order, 0).astype(np.uint8)
    w8[:, :k] = np.clip(q, 0, 255).astype(np.uint8)
    return idx, w8


class _Blob:
    def __init__(self):
        self.parts = []
        self.size = 0

    def add(self, arr):
        b = np.ascontiguousarray(arr).tobytes()
        off = self.size
        pad = (-len(b)) % 4
        self.parts.append(b + b'\0' * pad)
        self.size += len(b) + pad
        return off

    def bytes(self):
        return b''.join(self.parts)


def export_asset(hero, objects=None, out_dir=None, scripts=(), textures=(), extra=None):
    """
    Write assets/chars/<hero>/<hero>.edm (+ <hero>.json manifest + index.js embedding module).
      objects   mesh objects marked with part() (default: every such object in the scene); objects sharing a part
                name are concatenated
      scripts   paths hashed into the manifest (pass __file__)
      textures  [{ name, kind ('normal' | 'mask'), path (WEBP / JPEG file), width, height }] baked maps to embed
      extra     dict merged into the manifest
    Returns the manifest dict.
    """
    t0 = time.time()
    out_dir = out_dir or os.path.join(ROOT, 'assets', 'chars', hero)
    os.makedirs(out_dir, exist_ok=True)
    objs = objects or [o for o in bpy.context.scene.objects if o.type == 'MESH' and 'ed_part' in o]
    objs = sorted(objs, key=lambda o: (o.get('ed_order', 0), o['ed_part'], o.name))
    blob = _Blob()
    looks, look_index = [], {}
    groups = {}
    for o in objs:
        groups.setdefault(o['ed_part'], []).append(o)
    parts_json, tri_total, vert_total, bones_used = [], 0, 0, set()
    used_panels = set()
    for pname, olist in groups.items():
        datas = [_gather(o, look_index, looks) for o in olist]
        first = olist[0]
        flags = [f for f in str(first.get('ed_flags', '')).split(',') if f]
        # concatenate
        base = 0
        tris = []
        for d in datas:
            tris.append(d['tri'] + base); base += len(d['pos'])
        tri = np.concatenate(tris)
        pos = np.concatenate([d['pos'] for d in datas]); nrm = np.concatenate([d['nrm'] for d in datas])
        lookv = np.concatenate([d['look'] for d in datas]); col = np.concatenate([d['col'] for d in datas]); cav = np.concatenate([d['cav'] for d in datas])
        n = len(pos)

        def opt(key, width):
            if all(d[key] is None for d in datas):
                return None
            return np.concatenate([d[key] if d[key] is not None else np.zeros((len(d['pos']), width)) for d in datas])
        glow, uvw, uv, cloth = opt('glow', 3), opt('uvw', 3), opt('uv', 2), opt('cloth', 3)
        names = sorted({nm for d in datas for nm in d['wnames']})
        if len(names) > 256:
            raise ValueError(f'part {pname}: more than 256 bones')
        A = np.zeros((n, len(names)))
        base = 0
        for d in datas:
            for j, nm in enumerate(d['wnames']):
                A[base: base + len(d['pos']), names.index(nm)] = d['w'][:, j]
            base += len(d['pos'])
        panel = first.get('ed_panel') if cloth is not None else None
        if cloth is None and 'cloth' in flags:
            flags.remove('cloth')
        if cloth is not None:
            if 'cloth' not in flags:
                flags.append('cloth')
            used_panels.add(panel)
            # vertices with no bone weights at all are fully cloth
            cloth = cloth.copy()
            none = A.sum(axis=1) < 1e-6
            cloth[none, 2] = 1.0
        else:
            bad = int((A.sum(axis=1) < 1e-6).sum())
            if bad:
                raise ValueError(f'part {pname}: {bad} vertices without skin weights')
        # sort vertices by look -> runs
        order = np.argsort(lookv, kind='stable')
        remap = np.empty(n, dtype=np.int64); remap[order] = np.arange(n)
        pos, nrm, lookv, col, cav, A = pos[order], nrm[order], lookv[order], col[order], cav[order], A[order]
        glow = glow[order] if glow is not None else None
        uvw = uvw[order] if uvw is not None else None
        uv = uv[order] if uv is not None else None
        cloth = cloth[order] if cloth is not None else None
        tri = remap[tri]
        tlook = lookv[tri[:, 0]]
        tri = tri[np.argsort(tlook, kind='stable')]
        tlook = lookv[tri[:, 0]]
        runs = []
        for li in np.unique(lookv):
            vs = np.nonzero(lookv == li)[0]; ts = np.nonzero(tlook == li)[0]
            runs.append({'look': int(li), 'v0': int(vs[0]), 'vn': int(len(vs)), 'i0': int(ts[0]) * 3, 'in': int(len(ts)) * 3})
        # ---- quantise ---------------------------------------------------------------------------------------------------
        bmin = pos.min(axis=0) - 1e-5; bmax = pos.max(axis=0) + 1e-5
        q = np.zeros((n, 4), dtype=np.uint16)
        q[:, :3] = np.clip(np.round((pos - bmin) / (bmax - bmin) * 65535), 0, 65535).astype(np.uint16)
        nl = np.linalg.norm(nrm, axis=1, keepdims=True)
        nq = np.zeros((n, 4), dtype=np.int8)
        nq[:, :3] = np.clip(np.round(nrm / np.maximum(nl, 1e-9) * 127), -127, 127).astype(np.int8)
        nq.view(np.uint8)[:, 3] = np.clip(np.round(cav / 2 * 255), 0, 255).astype(np.uint8)
        cq = np.zeros((n, 4), dtype=np.uint8)
        cq[:, :3] = np.clip(np.round(np.sqrt(np.clip(col / 2, 0, 1)) * 255), 0, 255).astype(np.uint8)
        cq[:, 3] = lookv.astype(np.uint8)
        idx8, w8 = _quant_weights(A, cloth[:, 2] if cloth is not None else None)
        pj = {
            'name': pname, 'slot': first['ed_slot'], 'flags': flags, 'vertices': int(n), 'triangles': int(len(tri)),
            'bmin': [round(float(x), 6) for x in bmin], 'bmax': [round(float(x), 6) for x in bmax],
            'bones': names, 'runs': runs,
            'pos': blob.add(q), 'nrm': blob.add(nq), 'col': blob.add(cq), 'skin': blob.add(np.concatenate([idx8, w8], axis=1)),
        }
        if glow is not None:
            g = np.zeros((n, 4), dtype=np.uint8); g[:, :3] = np.clip(np.round(glow * 255), 0, 255).astype(np.uint8)
            pj['glow'] = blob.add(g)
        if uvw is not None:
            lo = uvw.min(axis=0); hi = uvw.max(axis=0); hi = np.where(hi - lo < 1e-9, lo + 1, hi)
            u = np.zeros((n, 4), dtype=np.uint16); u[:, :3] = np.clip(np.round((uvw - lo) / (hi - lo) * 65535), 0, 65535).astype(np.uint16)
            pj['uvw'] = {'off': blob.add(u), 'min': [float(x) for x in lo], 'max': [float(x) for x in hi]}
        if uv is not None:
            pj['uv'] = blob.add(np.clip(np.round(uv * 65535), 0, 65535).astype(np.uint16))
        if cloth is not None:
            c = np.zeros((n, 4), dtype=np.uint16); c[:, :3] = np.clip(np.round(cloth * 65535), 0, 65535).astype(np.uint16)
            pj['cloth'] = {'panel': panel, 'off': blob.add(c)}
        if n <= 65535:
            pj['idx'] = {'off': blob.add(tri.astype(np.uint16).reshape(-1)), 'type': 16}
        else:
            pj['idx'] = {'off': blob.add(tri.astype(np.uint32).reshape(-1)), 'type': 32}
        parts_json.append(pj)
        tri_total += len(tri); vert_total += n; bones_used.update(names)
    panels_json = []
    for name, p in SK.PANELS.items():
        G = b2g(p['rest'].reshape(-1, 3)).astype(np.float32)
        panels_json.append({'name': name, 'cols': p['cols'], 'rows': p['rows'], 'anchors': p['anchors'], 'rest': blob.add(G), 'params': p['params'], 'used': name in used_panels})
    tex_json = []
    for t in textures:
        with open(t['path'], 'rb') as f:
            data = f.read()
        mime = 'image/webp' if t['path'].lower().endswith('.webp') else ('image/png' if t['path'].lower().endswith('.png') else 'image/jpeg')
        tex_json.append({'name': t['name'], 'kind': t.get('kind', 'normal'), 'mime': mime, 'width': t.get('width'), 'height': t.get('height'),
                         'off': blob.add(np.frombuffer(data, dtype=np.uint8)), 'length': len(data)})
    script_hash = file_hash(*scripts) if scripts else ''
    head = {'format': 'edm/1', 'hero': hero, 'script': script_hash, 'triangles': tri_total, 'vertices': vert_total,
            'looks': looks, 'panels': panels_json, 'textures': tex_json, 'parts': parts_json}
    js = json.dumps(head, separators=(',', ':')).encode('utf-8')
    js += b' ' * ((-len(js)) % 4)
    data = blob.bytes()
    path = os.path.join(out_dir, hero + '.edm')
    with open(path, 'wb') as f:
        f.write(b'EDM1'); f.write(struct.pack('<I', len(js))); f.write(js); f.write(data)
    size = os.path.getsize(path)
    tex_bytes = sum(t['length'] for t in tex_json)
    manifest = {
        'hero': hero, 'file': hero + '.edm', 'bytes': size, 'geometryBytes': size - tex_bytes, 'textureBytes': tex_bytes,
        'triangles': tri_total, 'vertices': vert_total,
        'parts': [{'name': p['name'], 'slot': p['slot'], 'flags': p['flags'], 'triangles': p['triangles'], 'vertices': p['vertices'], 'bones': len(p['bones']),
                   'looks': [looks[r['look']]['name'] for r in p['runs']]} for p in parts_json],
        'looks': [l['name'] for l in looks],
        'panels': [{'name': p['name'], 'cols': p['cols'], 'rows': p['rows']} for p in panels_json],
        'textures': [{'name': t['name'], 'kind': t['kind'], 'bytes': t['length'], 'size': [t['width'], t['height']]} for t in tex_json],
        'bonesUsed': sorted(bones_used), 'script': script_hash, 'buildSeconds': round(time.time() - _START, 1),
        'blender': bpy.app.version_string,
    }
    if extra:
        manifest.update(extra)
    with open(os.path.join(out_dir, hero + '.json'), 'w') as f:
        json.dump(manifest, f, indent=1)
    rel = os.path.relpath(os.path.join(ROOT, 'src', 'char', 'assets.js'), out_dir).replace(os.sep, '/')
    with open(os.path.join(out_dir, 'index.js'), 'w') as f:
        f.write('// GENERATED by tools/blender (edlib.export_asset) - do not edit. Embeds the hero asset into the bundle of any\n'
                '// target that imports it (esbuild `binary` loader: tools/build.mjs).\n'
                f"import bin from './{hero}.edm';\n"
                f"import {{ registerAsset }} from '{rel}';\n\n"
                f"export default registerAsset('{hero}', bin);\n")
    log(f'export {hero}: {tri_total} tris, {vert_total} verts, {size / 1024:.0f} KB ({tex_bytes / 1024:.0f} KB textures), {len(parts_json)} parts, {len(looks)} looks, '
        f'{len(bones_used)} bones, {time.time() - t0:.1f}s -> {os.path.relpath(path, ROOT)}')
    return manifest


_START = time.time()
