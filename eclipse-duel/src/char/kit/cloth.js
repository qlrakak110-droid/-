// Cloth helpers: torn / burnt edges for the rig's verlet cloth, cape / tabard / waist-cloth specs.
//
// The rig adds every simulated cloth mesh through kit.addSkinned() right after design.build() returns. clothEdges()
// (call it inside build) wraps kit.addSkinned so those meshes carry their cloth (u, v) and an edge code in the `glow`
// attribute; the cloth slot's material (createKitMaterial({ cutout: true })) then tears and chars the hems in the shader
// (noise-driven rips, burnt holes, an ember-lit burning edge on glow channel `vein`).
//   u: 0 at the fighter's LEFT end of the pinned edge -> 1 at the right end; v: 0 pinned edge -> 1 hem.
// Rig change requested (see kit README): let cloth `surface` take glow / uv data directly so no wrapper is needed.

import { surfDetail } from '../materials.js';

const SIDES = { none: 0, left: 1, right: 2, both: 3 };

/**
 * @param {object} kit  the build kit passed to design.build
 * @param {object} rig  the rig passed to design.build (third argument)
 * @param {object} spec { clothName: { burn = 0.8 (0..1: tear depth + char width), sides = 'none'|'left'|'right'|'both' } }
 */
export function clothEdges(kit, rig, spec) {
  const orig = kit.addSkinned;
  const info = {};
  for (const name of Object.keys(spec)) {
    let C = 0, R = 0, first = -1;
    rig.names.forEach((n, i) => {
      const m = n.startsWith(name + '_') ? /_(\d+)_(\d+)$/.exec(n) : null;
      if (!m) return;
      C = Math.max(C, +m[1] + 1); R = Math.max(R, +m[2] + 1);
      if (first < 0) first = i;
    });
    if (first >= 0) info[name] = { C, R, first, code: Math.min(0.999, spec[name].burn ?? 0.8) + 2 * (SIDES[spec[name].sides ?? 'none'] ?? 0) };
  }
  kit.addSkinned = function (slot, geo, weightFn, opts = {}) {
    const w0 = weightFn(0, 0, 0, 0);
    const bi = w0 && w0[0] ? w0[0][0] : -1;
    const hit = Object.entries(info).find(([, c]) => bi >= c.first && bi < c.first + c.C * c.R);
    if (!hit) return orig.call(kit, slot, geo, weightFn, opts);
    const c = hit[1];
    const glow = (p, n, i) => {
      let u = 0, v = 0, tw = 0;
      for (const [b, w] of weightFn(0, 0, 0, i)) {
        const k = b - c.first;
        u += w * ((k % c.C) / (c.C - 1)); v += w * (Math.floor(k / c.C) / (c.R - 1)); tw += w;
      }
      return [u / (tw || 1), v / (tw || 1), c.code];
    };
    return orig.call(kit, slot, geo, weightFn, { ...opts, glow });
  };
  return kit;
}

/**
 * Cloth spec for design.cloth (verlet). o: { name, top: [[bone, [x,y,z]] ...] (left -> right), length, cols, rows, drape,
 * flare, outer: look, inner: look, slot = 'cloth', ...any rig cloth option }
 */
export function clothSpec(o) {
  const outer = o.outer || {}, inner = o.inner || outer;
  const spec = {
    slot: 'cloth', cols: 9, rows: 12, thickness: 0.012, subdiv: 2, damping: 0.035, margin: 0.028, wind: 1,
    ...o,
    surface: {
      outer: { color: outer.color, rough: outer.rough ?? 0.86, detail: surfDetail(outer.set ?? 'cloth', outer.amt ?? 1), cavity: 1 },
      inner: { color: inner.color ?? outer.color, rough: inner.rough ?? 0.9, cavity: inner.cavity ?? 0.55 },
    },
  };
  delete spec.outer; delete spec.inner;
  return spec;
}
