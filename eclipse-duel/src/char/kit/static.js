// Static (unskinned) kit: the same add / addPair / addSkinned API and per-vertex surface encoding as the character kit
// (src/char/build.js), merged into one plain Mesh per material slot. Used for weapon / armour displays in the art lab,
// props (dropped weapons, racks) and catalogue renders. Bones are ignored: geometry stays in the frame it was authored in.
//
//   const sk = createStaticKit();
//   buildGreatsword(sk, 'weaponR');                      // any builder that calls kit.add / put()
//   const group = sk.finish({ blade: createKitMaterial({...}) });   // THREE.Group, one Mesh per slot

import * as THREE from 'three';
import { xf, mirrorZ } from '../shapes.js';

const _c = new THREE.Color();
const toLinear = (c) => { if (Array.isArray(c)) return c; _c.set(c); return [_c.r, _c.g, _c.b]; };

function surface(geo, opts) {
  const n = geo.attributes.position.count, P = geo.attributes.position.array, N = geo.attributes.normal.array;
  const col = new Float32Array(n * 3), surf = new Float32Array(n * 4), glow = new Float32Array(n * 3);
  const cFn = typeof opts.color === 'function' ? opts.color : null, cK = cFn ? null : toLinear(opts.color ?? 0x808080);
  const aFn = typeof opts.cavity === 'function' ? opts.cavity : null;
  const gFn = typeof opts.glow === 'function' ? opts.glow : null, gK = gFn ? null : opts.glow || [0, 0, 0];
  const rough = opts.rough ?? 0.5, metal = opts.metal ?? 0, detail = opts.detail ?? 1, cav = aFn ? 1 : opts.cavity ?? 1;
  const p = [0, 0, 0], q = [0, 0, 0];
  for (let i = 0; i < n; i++) {
    p[0] = P[i * 3]; p[1] = P[i * 3 + 1]; p[2] = P[i * 3 + 2]; q[0] = N[i * 3]; q[1] = N[i * 3 + 1]; q[2] = N[i * 3 + 2];
    const c = cFn ? toLinear(cFn(p, q, i)) : cK;
    col.set(c, i * 3);
    surf[i * 4] = rough; surf[i * 4 + 1] = metal; surf[i * 4 + 2] = detail; surf[i * 4 + 3] = aFn ? aFn(p, q, i) : cav;
    glow.set(gFn ? gFn(p, q, i) : gK, i * 3);
  }
  return { col, surf, glow };
}

/** @returns static kit: { add, addPair, addSkinned, finish(materials) -> THREE.Group, triangles } */
export function createStaticKit() {
  const pieces = [];
  const kit = {
    add(slot, bone, geo, opts = {}) {
      const g = xf(geo.clone(), opts);
      pieces.push({ slot, g, s: surface(g, opts) });
      return kit;
    },
    addPair(slot, base, geo, opts = {}) {
      const g = xf(geo.clone(), opts);
      const o2 = { ...opts, at: undefined, rot: undefined, scale: undefined };
      kit.add(slot, base + 'R', g, o2);
      kit.add(slot, base + 'L', mirrorZ(g), o2);
      return kit;
    },
    addSkinned(slot, geo, weightFn, opts = {}) { return kit.add(slot, null, geo, opts); },
    bonePos() { return [0, 0, 0]; },
    finish(materials) {
      const group = new THREE.Group();
      const bySlot = new Map();
      for (const p of pieces) { if (!bySlot.has(p.slot)) bySlot.set(p.slot, []); bySlot.get(p.slot).push(p); }
      let tris = 0;
      for (const [slot, list] of bySlot) {
        let nv = 0, ni = 0;
        for (const p of list) { nv += p.g.attributes.position.count; ni += p.g.index.count; }
        const pos = new Float32Array(nv * 3), nor = new Float32Array(nv * 3), col = new Float32Array(nv * 3);
        const surf = new Float32Array(nv * 4), glow = new Float32Array(nv * 3), idx = new Uint32Array(ni);
        let vo = 0, io = 0;
        for (const p of list) {
          const c = p.g.attributes.position.count;
          pos.set(p.g.attributes.position.array.subarray(0, c * 3), vo * 3);
          nor.set(p.g.attributes.normal.array.subarray(0, c * 3), vo * 3);
          col.set(p.s.col, vo * 3); surf.set(p.s.surf, vo * 4); glow.set(p.s.glow, vo * 3);
          const a = p.g.index.array;
          for (let i = 0; i < a.length; i++) idx[io + i] = a[i] + vo;
          io += a.length; vo += c;
        }
        const geo = new THREE.BufferGeometry();
        geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
        geo.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
        geo.setAttribute('color', new THREE.BufferAttribute(col, 3));
        geo.setAttribute('surf', new THREE.BufferAttribute(surf, 4));
        geo.setAttribute('glow', new THREE.BufferAttribute(glow, 3));
        geo.setIndex(new THREE.BufferAttribute(idx, 1));
        geo.computeBoundingSphere();
        if (!materials[slot]) throw new Error('static kit: no material for slot ' + slot);
        const mesh = new THREE.Mesh(geo, materials[slot]);
        mesh.name = 'static:' + slot;
        mesh.castShadow = mesh.receiveShadow = true;
        group.add(mesh);
        tris += ni / 3;
      }
      group.userData.triangles = tris;
      kit.triangles = tris;
      return group;
    },
    triangles: 0,
  };
  return kit;
}
