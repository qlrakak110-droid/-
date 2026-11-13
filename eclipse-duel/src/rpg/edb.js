// EDB1 assets: rigid character pieces made in Blender (tools/blender/rigidkit.py), one bone each, with baked per-vertex
// colour, cavity (ambient occlusion) and glow.
//   'EDB1' | u32 json length | JSON { pieces: [{ bone, slot, rough, metal, detail, nv, ni, bmin, bmax, pos, nrm, col, idx }] } | data
//   pos u16 x 3 (in bmin..bmax, the bone's zero-pose frame) · nrm i8 x 3 + u8 cavity · col u8 x 3 (sqrt) + u8 glow · idx u16

import * as THREE from 'three';

export function decodeEdb(bytes) {
  const dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (dv.getUint32(0, true) !== 0x31424445) throw new Error('edb: bad magic');
  const jl = dv.getUint32(4, true);
  const head = JSON.parse(new TextDecoder().decode(bytes.subarray(8, 8 + jl)));
  const base = bytes.byteOffset + 8 + jl;
  return head.pieces.map((p) => {
    const q = new Uint16Array(bytes.buffer.slice(base + p.pos, base + p.pos + p.nv * 6));
    const nb = new Uint8Array(bytes.buffer, base + p.nrm, p.nv * 4), cb = new Uint8Array(bytes.buffer, base + p.col, p.nv * 4);
    const pos = new Float32Array(p.nv * 3), nrm = new Float32Array(p.nv * 3);
    for (let i = 0; i < p.nv; i++) {
      for (let k = 0; k < 3; k++) {
        pos[i * 3 + k] = p.bmin[k] + (q[i * 3 + k] / 65535) * (p.bmax[k] - p.bmin[k]);
        const b = nb[i * 4 + k];
        nrm[i * 3 + k] = (b > 127 ? b - 256 : b) / 127;
      }
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    geo.setAttribute('normal', new THREE.BufferAttribute(nrm, 3));
    geo.setIndex(new THREE.BufferAttribute(new Uint16Array(bytes.buffer.slice(base + p.idx, base + p.idx + p.ni * 2)), 1));
    return { ...p, geo, nb, cb };
  });
}

/** Add decoded pieces to a character kit. glow: HDR colour of a fully glowing vertex. */
export function addEdbPieces(kit, pieces, glow = [3.6, 1.75, 0.4]) {
  const c = [0, 0, 0], g = [0, 0, 0];
  for (const p of pieces) {
    const cb = p.cb, nb = p.nb;
    kit.add(p.slot, p.bone, p.geo, {
      rough: p.rough, metal: p.metal, detail: p.detail,
      color: (P, N, i) => { const r = cb[i * 4] / 255, gg = cb[i * 4 + 1] / 255, b = cb[i * 4 + 2] / 255; c[0] = r * r; c[1] = gg * gg; c[2] = b * b; return c; },
      cavity: (P, N, i) => nb[i * 4 + 3] / 255,
      glow: (P, N, i) => { const k = cb[i * 4 + 3] / 255, e = k * k; g[0] = glow[0] * e; g[1] = glow[1] * e; g[2] = glow[2] * e; return g; },
    });
  }
}
