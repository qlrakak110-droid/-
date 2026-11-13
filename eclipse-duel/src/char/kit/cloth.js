// Cloth helpers: torn / burnt edges for the rig's verlet cloth, cape / tabard / waist-cloth specs.
//
// The rig adds every simulated cloth mesh through kit.addSkinned() right after design.build() returns. clothEdges()
// (call it inside build) wraps kit.addSkinned so those meshes carry their cloth (u, v) and an edge code in the `glow`
// attribute; the cloth slot's material (createKitMaterial({ cutout: true })) then tears and chars the hems in the shader
// (noise-driven rips, burnt holes, an ember-lit burning edge on glow channel `vein`).
//   u: 0 at the fighter's LEFT end of the pinned edge -> 1 at the right end; v: 0 pinned edge -> 1 hem.
// Rig change requested (see kit README): let cloth `surface` take glow / uv data directly so no wrapper is needed.

import { surfDetail } from '../materials.js';
import { qrot } from '../rigmath.js';
import { mk, fixWinding, band, putSkinned, weightsOf } from './geo.js';

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
    if (first >= 0) info[name] = { C, R, first, code: Math.max(0.004, Math.min(0.999, spec[name].burn ?? 0.8)) + 2 * (SIDES[spec[name].sides ?? 'none'] ?? 0) };
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

// ---- tailored panels on simulated cloth -----------------------------------------------------------------------------------

/**
 * Sampler of a simulated cloth's rest surface (inside design.build): the rig's cloth bones `<name>_<i>_<j>` hold the
 * particle grid; u runs across the pinned edge (0 = the fighter's LEFT end), v from the pinned row (0) to the hem (1).
 * @param {object} kit  @param {object} rig  the rig passed to build (contains the cloth bones)
 * @param {string} name  cloth name   @param {object} o  { anchor = 'chest': bone the cloth hangs around (outside = away from it) }
 * @returns {object|null} { name, C, R, first, at(u, v) -> { p, n, du, dv, w } }  w = bilinear skin weights of the point
 */
export function clothSurface(kit, rig, name, o = {}) {
  let C = 0, R = 0, first = -1;
  rig.names.forEach((n, i) => {
    const m = n.startsWith(name + '_') ? /_(\d+)_(\d+)$/.exec(n) : null;
    if (!m) return;
    C = Math.max(C, +m[1] + 1); R = Math.max(R, +m[2] + 1);
    if (first < 0) first = i;
  });
  if (first < 0) return null;
  const mp = kit.bind.mp, mq = kit.bind.mq, N = new Float32Array(C * R * 3);
  for (let k = 0; k < C * R; k++) qrot(N, k * 3, mq, (first + k) * 4, 1, 0, 0);
  const mid = Math.floor(R / 2) * C + Math.floor(C / 2), b = kit.bonePos(o.anchor || 'chest');
  const side = (mp[(first + mid) * 3] - b[0]) * N[mid * 3] + (mp[(first + mid) * 3 + 2] - b[2]) * N[mid * 3 + 2] >= 0 ? 1 : -1;
  const P = (i, j, k) => mp[(first + j * C + i) * 3 + k];
  function at(u, v) {
    const fu = Math.min(1, Math.max(0, u)) * (C - 1), fv = Math.min(1, Math.max(0, v)) * (R - 1);
    const i0 = Math.min(C - 2, Math.floor(fu)), j0 = Math.min(R - 2, Math.floor(fv)), tu = fu - i0, tv = fv - j0;
    const cs = [[i0, j0, (1 - tu) * (1 - tv)], [i0 + 1, j0, tu * (1 - tv)], [i0, j0 + 1, (1 - tu) * tv], [i0 + 1, j0 + 1, tu * tv]];
    const p = [0, 0, 0], n = [0, 0, 0], w = [];
    for (const [i, j, ww] of cs) {
      for (let k = 0; k < 3; k++) { p[k] += P(i, j, k) * ww; n[k] += N[(j * C + i) * 3 + k] * ww; }
      if (ww > 1e-4) w.push([first + j * C + i, ww]);
    }
    const l = Math.hypot(n[0], n[1], n[2]) || 1;
    for (let k = 0; k < 3; k++) n[k] = (n[k] / l) * side;
    return { p, n, w };
  }
  return { name, C, R, first, at, side };
}

/**
 * Tailored render mesh for a simulated cloth declared with `mesh: false`: a shaped panel (outer cloth + lining) with
 * brocade bands along the hem and the side edges, skinned to the cloth particles like the rig's own mesh.
 * @param {object} kit  @param {object} S  clothSurface()
 * @param {object} o  slot='robe'   body, lining (looks; lining defaults to body)   border (look, e.g. MURIM.trim)   code=0
 *   (brocade motif + glow)   hemW=0.05, sideW=0 (band widths, m)   hem: fn(a) -> v of the hem line for a = 0..1 across
 *   (default 1: the full length)   na=12, nb=18   thick=0.004 (gap between cloth and lining)
 */
export function clothBorder(kit, S, o = {}) {
  if (!S) return;
  const hem = o.hem || (() => 1), na = o.na ?? 12, nb = o.nb ?? 18, th = (o.thick ?? 0.004) / 2, slot = o.slot || 'robe';
  for (const layer of [1, -1]) {
    const pos = [], nor = [], idx = [], W = [], cav = [];
    for (let j = 0; j <= nb; j++) for (let i = 0; i <= na; i++) {
      const a = i / na, f = S.at(a, (j / nb) * hem(a));
      pos.push(f.p[0] + f.n[0] * th * layer, f.p[1] + f.n[1] * th * layer, f.p[2] + f.n[2] * th * layer);
      nor.push(f.n[0] * layer, f.n[1] * layer, f.n[2] * layer); W.push(f.w); cav.push(layer > 0 ? 1 : 0.62);
    }
    for (let j = 0; j < nb; j++) for (let i = 0; i < na; i++) { const p0 = j * (na + 1) + i, p1 = p0 + 1, p2 = p0 + na + 1, p3 = p2 + 1; idx.push(p0, p2, p1, p1, p2, p3); }
    putSkinned(kit, slot, fixWinding(mk(pos, nor, idx, cav)), layer > 0 ? o.body : (o.lining || o.body), weightsOf(W));
  }
  if (!o.border) return;
  const frame = (a, v) => { const f = S.at(a, v); return { p: [f.p[0] + f.n[0] * th, f.p[1] + f.n[1] * th, f.p[2] + f.n[2] * th], n: f.n, w: f.w }; };
  const add = (g) => putSkinned(kit, slot, g, o.border, weightsOf(g.userData.W));
  const hw = o.hemW ?? 0.05, sw = o.sideW ?? 0, code = o.code ?? 0;
  if (hw > 0) {
    const fr = [];
    for (let i = 0; i <= na * 2; i++) { const a = i / (na * 2); fr.push(frame(a, hem(a))); }
    add(band(fr, { width: hw, shift: -0.5, side: [0, -1, 0], flat: true, lift: 0.001, thick: 0.0006, crown: 0.0008, code, flipV: true }));
  }
  if (sw > 0) {
    const across = (() => { const a = S.at(0, 0.5).p, b = S.at(1, 0.5).p; const d = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], l = Math.hypot(...d) || 1; return d.map((x) => x / l); })();
    for (const [a, sh] of [[0, 0.5], [1, -0.5]]) {
      const fr = [];
      for (let j = 0; j <= nb; j++) fr.push(frame(a, (j / nb) * hem(a)));
      add(band(fr, { width: sw, shift: sh, side: across, flat: true, lift: 0.001, thick: 0.0006, crown: 0.0008, code }));
    }
  }
}
