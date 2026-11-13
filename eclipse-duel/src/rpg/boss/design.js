// 「흑일마신상 黑日魔神像」 — the design. The body under the armour is the husk's lofts (smooth-skinned, dark); everything
// you see on top of it is the Blender-made asset `idol.edb` (tools/blender/heroes/idol.py): ~78k triangles of rigid
// pieces, one bone each, with baked per-vertex colour (looks, wear, patina), cavity (ambient occlusion) and glow
// (eclipse fire in the cracks). Two draw calls (plate, blade).
//
//   EDB1  'EDB1' | u32 json length | JSON { pieces: [{ bone, slot, rough, metal, detail, nv, ni, bmin, bmax,
//         pos, nrm, col, idx (byte offsets into the data block) }] } | data
//         pos u16 x 3 (in bmin..bmax, the bone's zero-pose frame) · nrm i8 x 3 + u8 cavity · col u8 x 3 (sqrt) + u8 glow · idx u16

import * as THREE from 'three';
import { idolBase, SABER } from './rigdesign.js';
import EDB from './idol.edb';

export { SABER };
const GOLD = [3.6, 1.75, 0.4];

function decode(bytes) {
  const dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (dv.getUint32(0, true) !== 0x31424445) throw new Error('idol.edb: bad magic');
  const jl = dv.getUint32(4, true);
  const head = JSON.parse(new TextDecoder().decode(bytes.subarray(8, 8 + jl)));
  const base = bytes.byteOffset + 8 + jl;
  const u8 = (o, n) => new Uint8Array(bytes.buffer, base + o, n);
  return head.pieces.map((p) => {
    const q = new Uint16Array(bytes.buffer.slice(base + p.pos, base + p.pos + p.nv * 6));
    const nb = u8(p.nrm, p.nv * 4), cb = u8(p.col, p.nv * 4);
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

let PIECES = null;

export function idolDesign(id = 'rpg-idol') {
  const base = idolBase(id);
  const baseBuild = base.build;
  return {
    ...base,
    materials: {
      plate: { roughness: 1, metalness: 1, envMapIntensity: 0.9, detailScale: 7, bump: 0.2 },
      blade: { roughness: 1, metalness: 1, envMapIntensity: 1.0, detailScale: 6, bump: 0.06 },
    },
    build(kit, S) {
      // the husk's under-body only: its plates, helm and sword go to a throw-away facade
      const body = { ...kit, add: () => body, addPair: () => body, loft: (...a) => (kit.loft(...a), body), loftPair: (...a) => (kit.loftPair(...a), body) };
      baseBuild(body, S);
      kit.addPair('plate', 'hand', S.box(0.085, 0.1, 0.085, 0.02), { color: 0x101114, rough: 0.6, metal: 0.5, at: [0, -0.07, 0] });
      if (!PIECES) PIECES = decode(EDB);
      const c = [0, 0, 0], g = [0, 0, 0];
      for (const p of PIECES) {
        const cb = p.cb, nb = p.nb;
        kit.add(p.slot, p.bone, p.geo, {
          rough: p.rough, metal: p.metal, detail: p.detail,
          color: (P, N, i) => { const r = cb[i * 4] / 255, gg = cb[i * 4 + 1] / 255, b = cb[i * 4 + 2] / 255; c[0] = r * r; c[1] = gg * gg; c[2] = b * b; return c; },
          cavity: (P, N, i) => nb[i * 4 + 3] / 255,
          glow: (P, N, i) => { const k = cb[i * 4 + 3] / 255, e = k * k; g[0] = GOLD[0] * e; g[1] = GOLD[1] * e; g[2] = GOLD[2] * e; return g; },
        });
      }
    },
  };
}
