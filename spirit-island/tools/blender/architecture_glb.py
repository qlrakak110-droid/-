"""(architecture copy of the vegetation GLB shrinker) Shrink a Blender-exported GLB (pure python + numpy, runs in Blender or system python):
  COLOR_0  float32 VEC4 -> UNSIGNED_BYTE normalized   (core glTF)
  NORMAL   float32 VEC3 -> BYTE normalized, stride 4   (KHR_mesh_quantization, supported by three's GLTFLoader)
Positions / UVs stay float (bark UVs tile beyond 0..1).
usage: python3 tools/blender/architecture_glb.py file.glb [...]
"""
import json, struct, sys
import numpy as np

CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}


def read(path):
    b = open(path, 'rb').read()
    assert b[:4] == b'glTF'
    off = 12; js = None; bin_ = b''
    while off < len(b):
        L, T = struct.unpack('<II', b[off:off + 8]); chunk = b[off + 8: off + 8 + L]
        if T == 0x4E4F534A: js = json.loads(chunk)
        elif T == 0x004E4942: bin_ = chunk
        off += 8 + L
    return js, bin_


def acc_array(js, bin_, i):
    a = js['accessors'][i]; bv = js['bufferViews'][a['bufferView']]
    dt = CT[a['componentType']]; nc = NC[a['type']]; start = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = bv.get('byteStride', 0); isz = np.dtype(dt).itemsize * nc
    if stride and stride != isz:
        raw = np.frombuffer(bin_, np.uint8, a['count'] * stride, start).reshape(a['count'], stride)[:, :isz].copy()
        return raw.view(dt).reshape(a['count'], nc)
    return np.frombuffer(bin_, dt, a['count'] * nc, start).reshape(a['count'], nc).copy()


def write(path, js, views):
    """views: list of (bytes, target, stride|None) in bufferView order; rebuilds buffer + bufferViews"""
    out = bytearray(); bvs = []
    for data, target, stride in views:
        while len(out) % 4: out.append(0)
        bv = {'buffer': 0, 'byteOffset': len(out), 'byteLength': len(data)}
        if target: bv['target'] = target
        if stride: bv['byteStride'] = stride
        bvs.append(bv); out += data
    while len(out) % 4: out.append(0)
    js['bufferViews'] = bvs; js['buffers'] = [{'byteLength': len(out)}]
    j = json.dumps(js, separators=(',', ':')).encode()
    while len(j) % 4: j += b' '
    glb = struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(j) + 8 + len(out)) + struct.pack('<II', len(j), 0x4E4F534A) + j + struct.pack('<II', len(out), 0x004E4942) + bytes(out)
    open(path, 'wb').write(glb)


def quantize(path):
    js, bin_ = read(path)
    roles = {}
    for m in js['meshes']:
        for p in m['primitives']:
            for k, v in p['attributes'].items(): roles[v] = k
            if 'indices' in p: roles[p['indices']] = 'INDEX'
    views = []
    for i, a in enumerate(js['accessors']):
        arr = acc_array(js, bin_, i); role = roles.get(i, '')
        stride = None; target = 34963 if role == 'INDEX' else 34962
        a.pop('byteOffset', None)
        if role.startswith('COLOR') and a['componentType'] == 5126:
            arr = np.clip(np.round(arr * 255), 0, 255).astype(np.uint8); a['componentType'] = 5121; a['normalized'] = True
        elif role == 'NORMAL' and a['componentType'] == 5126:
            q = np.clip(np.round(arr * 127), -127, 127).astype(np.int8)
            arr = np.zeros((q.shape[0], 4), np.int8); arr[:, :3] = q
            a['componentType'] = 5120; a['normalized'] = True; stride = 4
        a['bufferView'] = len(views)
        views.append((arr.tobytes(), target, stride))
    for ext in ('extensionsUsed', 'extensionsRequired'):
        js[ext] = sorted(set(js.get(ext, []) + ['KHR_mesh_quantization']))
    # drop images / textures if any slipped in (the game binds its own maps)
    for k in ('images', 'textures', 'samplers'): js.pop(k, None)
    for m in js.get('materials', []):
        pb = m.get('pbrMetallicRoughness', {}); pb.pop('baseColorTexture', None); pb.pop('metallicRoughnessTexture', None)
        m.pop('normalTexture', None); m.pop('occlusionTexture', None); m.pop('emissiveTexture', None)
    write(path, js, views)


if __name__ == '__main__':
    import os
    for p in sys.argv[1:]:
        s0 = os.path.getsize(p); quantize(p); print(p, s0, '->', os.path.getsize(p))
