// Signature weapons in the murim idiom: 염무강's 참마대도 (colossal single-edged great saber; builder `greatsword`),
// 설리화's 월아쌍도 (twin crescent blades; `crescents`), 뇌진천's 뇌룡창 (long war spear with a horsehair tassel; `spear`).
// Lengths, sockets, grip points and hand alignment are those of the weapons they replace: 108 clips depend on them.
//
// Every weapon is authored in the WEAPON BONE frame of the rig (src/char/README.md "Weapons"): origin = centre of the
// main fist on the grip axis, +X toward the tip, -Y = the true edge (blade) / the spear head's lower wing, +-Z = the
// flats. The design's weapon spec (WEAPON_SPECS.<name>) carries the sockets and grip points the runtime reads:
//   base / tip   -> char.sockets.weaponBase / weaponTip (weaponBase2 / weaponTip2 ... for the second weapon)
//   grips        -> off-hand IK targets ({ pos, rot } in the weapon bone frame; clips choose one with `gripAt`)
//
//   import { WEAPON_SPECS, buildWeapon, saberStripRig } from '../../char/weapons.js';
//   const STRIP = saberStripRig();                                  // optional spring chain of the pommel's cloth strip
//   design.weapon = WEAPON_SPECS.greatsword; design.bones = [...STRIP.bones]; design.springs = [...STRIP.springs];
//   build(kit) { buildWeapon(kit, 'greatsword', { strip: STRIP }); ... }   // adds the pieces on weaponR / weaponL
//
// Blades use the `blade` uv set (bright honed edge, misty temper line, flowing grain on the darker body). Glow channels
// (material option `glow`): inlay = the seam in the blood groove / star and rune inlays, vein = engraved fittings.

import * as THREE from 'three';
import { sweep, lathe, extrude, circle, rrect, curve, put, putPair, putSkinned, weightsOf, mk, fixWinding, creased, autoCav, withUvw, band, ribbon, merge } from './kit/geo.js';
import { hang, chainPath, chainWeights, spearTassel, tassel } from './kit/murim.js';

const DEG = Math.PI / 180;
const lerp = (a, b, t) => a + (b - a) * t;
const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);
const sstep = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };

/**
 * Weapon specs (sockets + grip points), weapon bone frame, metres.
 *
 * greatsword (KAEL, two-handed, right hand at the guard):
 *   weaponBase [0.12, 0, 0]  blade root just above the ricasso lugs      weaponTip [1.6, 0, 0]  point
 *   grips: grip [-0.17, 0, 0] off hand below the main hand (two-handed)  pommel [-0.27, 0, 0] hand on the pommel
 *          blade [0.56, 0, 0] half-swording on the flat (guard / bind)    ricasso [0.17, 0, 0] choked grip on the ricasso
 * crescents (ISKA, one per hand; mirrored for the left hand):
 *   weaponBase  [0.07, 0, 0] (right blade) / weaponBase2 (left blade)    blade root at the guard ring
 *   weaponTip   [0.449, 0.263, 0] / weaponTip2                           crescent point (the blade curves toward +Y; = CRESCENT_TIP)
 *   grips: grip [0, 0, 0] (own fist; twin blades never two-hand), pommel [-0.075, 0, 0]
 * spear (VORN, two-handed, right hand forward of centre):
 *   weaponBase [1.02, 0, 0]  head root above the socket                 weaponTip [1.5, 0, 0]  point
 *   grips: grip [-0.52, 0, 0] rear hand    choke [-0.26, 0, 0] short grip    butt [-0.86, 0, 0] hand at the counterweight
 *          head [0.78, 0, 0] hand under the socket (close thrusts / binds)
 */
export const WEAPON_SPECS = {
  greatsword: {
    name: 'greatsword', hand: 'R', slot: 'blade',
    base: [0.12, 0, 0], tip: [1.6, 0, 0],
    grips: { grip: { pos: [-0.17, 0, 0] }, pommel: { pos: [-0.27, 0, 0] }, blade: { pos: [0.56, 0, 0] }, ricasso: { pos: [0.17, 0, 0] } },
  },
  crescents: [
    { name: 'crescentR', hand: 'R', slot: 'blade', base: [0.07, 0, 0], tip: [0.449, 0.263, 0], grips: { grip: { pos: [0, 0, 0] }, pommel: { pos: [-0.075, 0, 0] } } },
    { name: 'crescentL', hand: 'L', slot: 'blade', base: [0.07, 0, 0], tip: [0.449, 0.263, 0], grips: { grip: { pos: [0, 0, 0] }, pommel: { pos: [-0.075, 0, 0] } } },
  ],
  spear: {
    name: 'spear', hand: 'R', slot: 'blade',
    base: [1.02, 0, 0], tip: [1.5, 0, 0],
    grips: { grip: { pos: [-0.52, 0, 0] }, choke: { pos: [-0.26, 0, 0] }, butt: { pos: [-0.86, 0, 0] }, head: { pos: [0.78, 0, 0] } },
  },
};

/** Default looks of the weapons (override per design: `looks` option of each builder). */
export const WEAPON_LOOKS = {
  greatsword: {
    blade: { color: [0.085, 0.082, 0.082], rough: 0.3, metal: 1, set: 'blade', amt: 0.6, wear: 0.9 },
    edge: { color: [0.5, 0.49, 0.48], rough: 0.2, metal: 1, set: 'hammered', amt: 0.35, wear: 0.6 },
    back: { color: [0.03, 0.028, 0.028], rough: 0.5, metal: 0.9, set: 'scorched', amt: 0.9, vein: 0.8 },
    fuller: { color: [0.02, 0.016, 0.014], rough: 0.6, metal: 0.4, set: 'scorched', amt: 1, inlay: 0.65, vein: 1 },
    iron: { color: [0.07, 0.065, 0.063], rough: 0.42, metal: 1, set: 'hammered', amt: 1 },
    bronze: { color: [0.3, 0.17, 0.07], rough: 0.38, metal: 1, set: 'engraved', amt: 0.9, vein: 0.5 },
    leather: { color: [0.04, 0.022, 0.015], rough: 0.72, metal: 0, set: 'leather', amt: 1 },
    cord: { color: [0.13, 0.012, 0.008], rough: 0.85, metal: 0, set: 'hemp', amt: 0.9 },
    cloth: { color: [0.2, 0.014, 0.01], rough: 0.6, metal: 0, set: 'silk', amt: 1 },
    wire: { color: [0.3, 0.2, 0.1], rough: 0.3, metal: 1, set: 'hammered', amt: 0.3 },
    gem: { color: [0.05, 0.004, 0.003], rough: 0.06, metal: 0, set: 'hammered', amt: 0, inlay: 0.012 },
  },
  crescents: {
    blade: { color: [0.36, 0.38, 0.43], rough: 0.2, metal: 1, set: 'blade', amt: 0.4, wear: 0.4 },
    spine: { color: [0.1, 0.13, 0.2], rough: 0.3, metal: 1, set: 'engraved', amt: 0.8 },
    star: { color: [0.6, 0.8, 1.0], rough: 0.2, metal: 0, set: 'hammered', amt: 0, inlay: 1 },
    silver: { color: [0.55, 0.57, 0.6], rough: 0.25, metal: 1, set: 'engraved', amt: 0.9, vein: 0.35 },
    wrap: { color: [0.02, 0.03, 0.09], rough: 0.8, metal: 0, set: 'hemp', amt: 0.9 },
    jade: { color: [0.42, 0.5, 0.46], rough: 0.22, metal: 0, set: 'jade', amt: 0.6 },
    hair: { color: [0.36, 0.4, 0.5], rough: 0.45, metal: 0, set: 'hair', amt: 1 },
  },
  spear: {
    head: { color: [0.13, 0.125, 0.14], rough: 0.26, metal: 1, set: 'blade', amt: 0.5 },
    edge: { color: [0.55, 0.55, 0.58], rough: 0.18, metal: 1, set: 'hammered', amt: 0.3 },
    rune: { color: [0.05, 0.03, 0.08], rough: 0.4, metal: 0.3, set: 'hammered', amt: 0, inlay: 1 },
    haft: { color: [0.02, 0.012, 0.012], rough: 0.34, metal: 0, set: 'lacquer', amt: 0.7 },
    band: { color: [0.24, 0.16, 0.07], rough: 0.36, metal: 1, set: 'engraved', amt: 0.9, vein: 0.6 },
    wrap: { color: [0.05, 0.02, 0.09], rough: 0.85, metal: 0, set: 'hemp', amt: 0.9 },
    gold: { color: [0.36, 0.23, 0.09], rough: 0.36, metal: 1, set: 'bronze', amt: 0.8 },
    hair: { color: [0.3, 0.02, 0.012], rough: 0.5, metal: 0, set: 'hair', amt: 1 },
  },
};

// ---- grip wraps -----------------------------------------------------------------------------------------------------------

/**
 * Shingled helical leather wrap around the X axis: a flat band whose leading edge sits higher than its trailing edge so
 * consecutive turns overlap like real wrapped leather. Radial frames (no twist). Returns geometry.
 * o: x0, x1 (extent), r (core radius, number or fn(t)), turns, width (band width along the axis), thick, seg (samples per turn)
 */
export function helixWrap(o) {
  const turns = o.turns ?? 12, seg = o.seg ?? 10, n = Math.ceil(turns * seg), w = o.width ?? 0.016, th = o.thick ?? 0.0018;
  const R = typeof o.r === 'function' ? o.r : () => o.r ?? 0.018;
  const across = [-0.5, -0.2, 0.25, 0.5];
  const lift = [0.15, 0.45, 0.9, 1.0];
  const pos = [], nor = [], idx = [], cav = [];
  for (let i = 0; i <= n; i++) {
    const t = i / n, a = t * turns * Math.PI * 2, xc = lerp(o.x0, o.x1, t);
    const c = Math.cos(a), sn = Math.sin(a), r = R(t);
    for (let k = 0; k < across.length; k++) {
      const x = xc + across[k] * w, rr = r + th * lift[k];
      pos.push(x, c * rr, sn * rr);
      // normal tilts toward the raised edge on the shingle step
      const tilt = k === 3 ? 0.8 : k === 0 ? -0.15 : 0.12;
      const nx = -tilt * Math.sign(o.x1 - o.x0), l = Math.hypot(nx, 1);
      nor.push(nx / l, (c) / l, (sn) / l);
      cav.push(k === 3 ? 1.35 : k === 0 ? 0.55 : 1);
    }
  }
  const K = across.length;
  for (let i = 0; i < n; i++) for (let k = 0; k < K - 1; k++) {
    const a0 = i * K + k, b0 = a0 + 1, c0 = a0 + K, d0 = c0 + 1;
    idx.push(a0, c0, b0, b0, c0, d0);
  }
  return fixWinding(mk(pos, nor, idx, cav));
}

// ---- blade cross-section sweep ----------------------------------------------------------------------------------------

/**
 * Faceted blade along +X from x0 to x1: diamond / hollow-ground section with edge bevels (hard), an optional fuller,
 * width / thickness curves over t (0 base .. 1 tip). Section x -> Y (edges at +-w), y -> Z (flats).
 * o: x0, x1, w(t), th(t), bevel(t) (width of the edge bevel), fuller { from, to, w (half), depth }, back (single edge:
 *    +Y spine flat), path(t) -> [dx, dy] centre offset (curved blades), segs
 * Returns { blade, edges (thin geometry along the bevels for a brighter edge look), fullerFloor }
 */
export function bladeSweep(o) {
  const n = o.segs ?? 40;
  const W = typeof o.w === 'function' ? o.w : () => o.w;
  const TH = typeof o.th === 'function' ? o.th : () => o.th;
  const BV = typeof o.bevel === 'function' ? o.bevel : () => o.bevel ?? 0.01;
  const F = o.fuller;
  const off = o.path || (() => [0, 0]);
  const section = (t) => {
    const w = Math.max(0.0008, W(t)), th = Math.max(0.0004, TH(t)), e = Math.min(BV(t), w * 0.8);
    let fw = 0, fd = 0;
    if (F && t > F.from && t < F.to) {
      const k = Math.min(1, Math.min(t - F.from, F.to - t) / 0.035);
      fw = Math.min(F.w, (w - e) * 0.72) * Math.sqrt(k); fd = F.depth * k;
    }
    const top = o.back ? [[w, th * 0.8], [w, -th * 0.8]] : [[w, 0]];
    const flat = (s) => {
      // one face (s = +1 / -1): from the top bevel line to the bottom bevel line, fuller in between
      const pts = [];
      const zf = th * s, inner = w - e;
      pts.push([inner, zf * 0.92]);
      pts.push([Math.max(fw * 1.3, inner * 0.5), zf]);
      pts.push([fw, zf - s * fd * 0.15]);
      pts.push([fw * 0.55, zf - s * fd]);
      pts.push([0, zf - s * fd * 1.05]);
      pts.push([-fw * 0.55, zf - s * fd]);
      pts.push([-fw, zf - s * fd * 0.15]);
      pts.push([-Math.max(fw * 1.3, inner * 0.5), zf]);
      pts.push([-inner, zf * 0.92]);
      return s > 0 ? pts : pts.reverse().map(([a, b]) => [a, b]);
    };
    // order: top edge -> +Z face (top to bottom) -> bottom edge -> -Z face (bottom to top)
    const f1 = flat(1), f2 = flat(-1);
    const out = [];
    if (o.back) out.push([w, th * 0.8]); else out.push([w, 0]);
    out.push(...f1);
    out.push([-w, 0]);
    out.push(...f2.map(([a, b]) => [a, b]));
    if (o.back) out.push([w, -th * 0.8]);
    return out;
  };
  const m = section(0.5).length;
  // hard corners: edges and the bevel lines
  const hard = o.back ? [0, 1, 9, 10, 11, 19, 20] : [0, 1, 9, 10, 11, 19];
  const pts = [];
  for (let i = 0; i <= n; i++) {
    const t = i / n, [dx, dy] = off(t);
    pts.push([lerp(o.x0, o.x1, t) + dx, dy, 0]);
  }
  // the section function receives t; sweep() frames come from the path (curved blades follow it)
  const g = sweep(pts, (t) => section(t), { up: [0, 1, 0], hard: hard.filter((h) => h < m), caps: true, cavScale: 0.003 });
  return g;
}

/**
 * Close-up blade: an explicit faceted cross-section swept along a path (forged facets, crisp creases).
 * pts: path [[x, y, z]...]; sec(t) -> { top, face, bot } with points [x, z, hard] (x across the blade along the frame
 * normal, z toward the +Z flat): top = the +x end (spine / edge) from z = 0 upward (a single [w, 0] = edge), face = the +Z
 * flat from +x to -x, bot = the -x end from +z to -z. The -Z flat mirrors the +Z one. Point count must not change with t
 * (collapse a feature to zero size instead). Returns geometry.
 */
function facetBlade(pts, sec, o = {}) {
  const loop = (t) => {
    const { top, face, bot } = sec(t);
    const lo = top.filter((p) => p[1] > 0).reverse().map(([x, z, h]) => [x, -z, h]);
    return [...top, ...face, ...bot, ...face.slice().reverse().map(([x, z, h]) => [x, -z, h]), ...lo];
  };
  const hard = [];
  loop(0.5).forEach((p, i) => { if (p[2]) hard.push(i); });
  return sweep(pts, (t) => loop(t).map(([x, z]) => [x, z]), { up: o.up ?? [0, 1, 0], hard, caps: o.caps ?? true, cavScale: o.cavScale ?? 0.003 });
}

/** z of a section's +Z flat at x (piecewise linear over the face points; x outside -> the nearest end). */
function faceZ(face, x) {
  for (let i = 0; i < face.length - 1; i++) {
    const [x0, z0] = face[i], [x1, z1] = face[i + 1];
    if ((x <= x0 && x >= x1) && x0 - x1 > 1e-9) return lerp(z0, z1, (x0 - x) / (x0 - x1));
  }
  return x > face[0][0] ? face[0][1] : face[face.length - 1][1];
}

/** Lightning glyph polygon: centreline [[x, y, halfWidth]...] (x increasing) -> outline offset across y (never folds). */
function boltShape(cl) {
  const up = cl.map(([x, y, w]) => [x, y + w]), dn = cl.map(([x, y, w]) => [x, y - w]).reverse();
  const out = [...up, ...dn];
  // drop the duplicate point at a zero-width end
  return out.filter((p, i) => { const q = out[(i + 1) % out.length]; return Math.hypot(p[0] - q[0], p[1] - q[1]) > 1e-7; });
}

// ---- 염무강: 참마대도 (great saber; code name greatsword) -------------------------------------------------------------------

/** Outline of the great saber in the weapon frame: back (spine, +Y) and edge (-Y) lines over x, guard face .. point. */
const SX0 = 0.075, SX1 = 1.6, SXC = 1.2;
const saberBack = (x) => {
  if (x <= SXC) return lerp(0.036, 0.058, sstep(SX0, SXC, x)) + 0.012 * Math.exp(-(((x - (SXC - 0.035)) / 0.022) ** 2));
  const k = (x - SXC) / (SX1 - SXC);
  return 0.058 * (1 - k) - 0.011 * Math.sin(k * Math.PI);               // clip point: a hollow cut from the back to the point
};
const saberEdge = (x) => {
  const t = (x - SX0) / (SX1 - SX0), belly = 0.05 + 0.04 * sstep(0.06, 0.7, t);
  return t < 0.7 ? -belly : -0.09 * (1 - Math.pow((t - 0.7) / 0.3, 2.2));
};

/**
 * Spring chain of the cloth strip tied through the great saber's ring pommel (weapon frame; spread .bones / .springs
 * into the design and pass it as `strip`).
 */
export function saberStripRig(o = {}) {
  return hang(o.name || 'strip', 'weapon' + (o.hand || 'R'), [-0.322, -0.022, 0], { n: 3, len: o.len ?? 0.3, dir: [-0.45, -1, 0], stiffness: 16, damping: 2.4, gravity: 1, limit: 80, radius: 0.012, collide: false });
}

/**
 * Build 염무강's 참마대도 on `bone` (default weaponR): a colossal single-edged saber — broad blade with a curved back, a
 * spur and a hollow clip to the point, a wide honed edge bevel, a blood groove with an ember seam, a bronze collar and
 * lobed guard, a long cord-wrapped two-handed hilt and a ring pommel with a cloth strip.
 * o: bone, slot, looks (WEAPON_LOOKS.greatsword keys), strip (saberStripRig() chain; without it the strip is a knot)
 */
export function greatsword(kit, o = {}) {
  const L = { ...WEAPON_LOOKS.greatsword, ...(o.looks || {}) };
  const bone = o.bone ?? 'weaponR', slot = o.slot ?? 'blade';
  const add = (g, look, extra) => put(kit, slot, bone, g, look, extra);
  const X0 = SX0, X1 = SX1;
  const xOf = (t) => lerp(X0 + 0.004, X1, t);
  const TH = (t) => lerp(0.0068, 0.0034, t) * (t > 0.93 ? 1 - (t - 0.93) * 8 : 1) + 0.0005;
  const FT0 = 0.05, FT1 = 0.7;
  const dims = (t) => {
    const x = xOf(t), ys = saberBack(x), ye = saberEdge(x), W = Math.max(0.0016, ys - ye), th = TH(t);
    const k = clamp(Math.min((t - FT0) / 0.04, (FT1 - t) / 0.08), 0, 1);
    return { x, ys, ye, W, th, ch: Math.min(0.004, W * 0.05), fc: ys - Math.min(0.025, W * 0.22), fw: Math.min(0.0075, W * 0.07) * Math.sqrt(k), fd: 0.003 * Math.min(1, k * 1.5), e: Math.min(0.032, W * 0.3) };
  };
  const sec = (t) => {
    const d = dims(t), mid = lerp(d.fc - d.fw, d.ye + d.e, 0.5);
    return {
      top: [[d.ys, d.th * 0.78, 1]],
      face: [[d.ys - d.ch, d.th, 1], [d.fc + d.fw, d.th, 1], [d.fc + d.fw * 0.62, d.th - d.fd, 1], [d.fc - d.fw * 0.62, d.th - d.fd, 1], [d.fc - d.fw, d.th, 1], [mid, d.th * 0.97, 0], [d.ye + d.e, d.th * 0.72, 1]],
      bot: [[d.ye, 0, 1]],
    };
  };
  const BS = 30, bpts = [];
  for (let i = 0; i <= BS; i++) bpts.push([xOf(i / BS), 0, 0]);
  const blade = facetBlade(bpts, sec);
  const tOf = (p) => clamp((p[0] - X0 - 0.004) / (X1 - X0 - 0.004), 0, 1);
  // blade uv set: u along the blade (m), v from the cutting edge (0) to the back (1), code = height of the temper line
  withUvw(blade, (p) => { const x = Math.max(X0, Math.min(X1, p[0])), ys = saberBack(x), ye = saberEdge(x); return [p[0], clamp((p[1] - ye) / Math.max(1e-4, ys - ye), 0, 1), o.temper ?? 0.27]; });
  const kindOf = (p) => { const d = dims(tOf(p)); return p[1] > d.ys - d.ch * 1.2 ? 1 : d.fd > 0.0004 && Math.abs(p[1] - d.fc) < d.fw * 0.96 && Math.abs(p[2]) < d.th - d.fd * 0.3 ? 2 : 0; };
  const bc = L.blade.color, kc = L.back.color, fcol = L.fuller.color;
  add(blade, L.blade, { color: (p) => [bc, kc, fcol][kindOf(p)], cav: (p) => (kindOf(p) === 2 ? 0.55 : 1) });
  // ember seam on the floor of the blood groove (both flats): a hot core with a softer halo, fading before the run-out
  for (const s of [1, -1]) {
    const fr = [];
    for (let i = 0; i <= 22; i++) { const t = lerp(FT0 + 0.02, FT1 - 0.04, i / 22), d = dims(t); fr.push({ p: [d.x, d.fc, s * (d.th - d.fd + 0.0003)], n: [0, 0, s] }); }
    const seam = band(fr, { width: (t) => 0.0062 * Math.sin(Math.PI * clamp(0.12 + t * 0.88, 0, 1)) ** 0.5 + 0.0012, flat: true, lift: 0.0002, thick: 0.0002, crown: 0.0003, side: [0, -1, 0] });
    add(seam, L.fuller, { glow: (p) => { const d = dims(tOf(p)), k = 1 - Math.min(1, Math.abs(p[1] - d.fc) / 0.0031), t = tOf(p); return [k * k * (0.6 + 0.4 * Math.sin(p[0] * 29) * Math.sin(p[0] * 8.3 + 0.7)) * (1 - sstep(0.52, 0.68, t)), 0.5 * k, 0]; } });
  }
  // charred back: a strip of scorched iron along the spine whose cracks carry the vein glow (염무강's heat climbing the blade)
  {
    const fr = [];
    for (let i = 0; i <= 26; i++) { const t = lerp(0.02, 0.74, i / 26), d = dims(t); fr.push({ p: [d.x, d.ys, 0], n: [0, 1, 0] }); }
    add(band(fr, { width: (t) => 2 * TH(lerp(0.02, 0.74, t)) * 0.8 + 0.001, lift: 0.0003, thick: 0.0006, crown: 0.0004, side: [0, 0, 1] }), L.back, { glow: (p) => [0, 0.5 + 0.5 * Math.sin(p[0] * 17 + 1), 0] });
  }
  // blade collar (the mouth the blade grows from): a faceted bronze sleeve, flame-cut where it meets the steel
  {
    const cs = (x) => { const ys = saberBack(Math.max(x, X0)) + 0.005, ye = saberEdge(Math.max(x, X0)) - 0.005; return [[ys, 0.0118], [ys - 0.006, 0.0138], [ye + 0.008, 0.0138], [ye, 0.006], [ye, -0.006], [ye + 0.008, -0.0138], [ys - 0.006, -0.0138], [ys, -0.0118]]; };
    const col = sweep([[X0 - 0.002, 0, 0], [X0 + 0.07, 0, 0], [X0 + 0.118, 0, 0]], (t) => cs(lerp(X0, X0 + 0.118, t)).map(([y, z]) => [y, z * (1 - 0.14 * t)]), { up: [0, 1, 0], hard: [0, 1, 2, 3, 4, 5, 6, 7] });
    add(col, L.bronze);
    for (const s of [1, -1]) {
      // three flame tongues licking onto the blade
      for (const [y, len] of [[0.012, 0.075], [-0.012, 0.11], [-0.036, 0.07]]) {
        const tg = extrude([[0, -0.009], [len * 0.5, -0.006], [len, 0.003], [len * 0.55, 0.006], [0, 0.009]], { depth: 0.0022, bevel: 0.0008, bevelSegs: 1 });
        tg.translate(X0 + 0.112, y, s * (TH(0.06) + 0.0012));
        add(tg, L.bronze);
      }
    }
  }
  // guard: a thick four-lobed oval plate
  {
    const pts = [];
    for (let i = 0; i < 28; i++) { const a = (i / 28) * Math.PI * 2, r = 1 + 0.07 * Math.cos(4 * a); pts.push([Math.cos(a) * 0.037 * r, Math.sin(a) * 0.07 * r - 0.006]); }
    const g = extrude(pts, { depth: 0.012, bevel: 0.003, bevelSegs: 2 });
    g.rotateY(90 * DEG); g.translate(X0 - 0.01, 0, 0);
    add(g, L.iron);
    for (const sx of [-1, 1]) {
      const rim = sweep(pts.map(([z, y]) => [X0 - 0.01 + sx * 0.0068, y * 0.86, -z * 0.84]), circle(4), { scale: 0.0018, closed: true, up: [1, 0, 0] });
      add(rim, L.bronze);
    }
  }
  // long two-handed hilt: waisted wooden core, cord wrap, bronze ferrules
  const GX0 = X0 - 0.017, GX1 = -0.25;
  const core = lathe([[0.0, 0], [0.018, 0], [0.0168, 0.09], [0.016, 0.17], [0.0172, 0.26], [0.0186, GX0 - GX1], [0.0, GX0 - GX1]], { segs: 14 });
  core.rotateZ(90 * DEG); core.scale(1, 1.08, 0.9); core.translate(GX0, 0, 0);
  add(core, L.leather);
  add(helixWrap({ x0: GX0 - 0.01, x1: GX1 + 0.016, r: (t) => 0.0178 + 0.0012 * Math.sin(t * Math.PI), turns: 17, width: 0.017, thick: 0.0024, seg: 8 }), L.cord);
  for (const [xf, r] of [[GX0 + 0.002, 0.0225], [GX1 - 0.001, 0.023], [-0.118, 0.0212]]) {
    const fe = lathe([[r * 0.9, -0.009], [r, -0.006], [r * 1.05, 0], [r, 0.006], [r * 0.9, 0.009]], { segs: 16 });
    fe.rotateZ(90 * DEG); fe.translate(xf, 0, 0);
    add(fe, L.bronze);
  }
  // ring pommel (환두): a neck and a heavy ring in the plane of the blade; the pommel end stays at x = -0.334
  const RX = -0.298, RR = 0.029;
  const neck = lathe([[0.019, 0], [0.021, 0.006], [0.015, 0.014], [0.011, 0.022]], { segs: 10 });
  neck.rotateZ(90 * DEG); neck.translate(GX1 - 0.006, 0, 0);
  add(neck, L.bronze);
  const rpts = [];
  for (let i = 0; i < 22; i++) { const a = (i / 22) * Math.PI * 2; rpts.push([RX + Math.cos(a) * RR, Math.sin(a) * RR, 0]); }
  add(sweep(rpts, [[1, 0], [0.5, 0.82], [-0.5, 0.82], [-1, 0], [-0.5, -0.82], [0.5, -0.82]], { scale: 0.0072, closed: true, up: [0, 0, 1], hard: [0, 3] }), L.iron);
  // cloth strip tied through the ring: knot + hanging ends (on the spring chain when the design declares one)
  const kn = lathe([[0, 0.012], [0.008, 0.009], [0.011, 0], [0.008, -0.009], [0, -0.012]], { segs: 8 });
  kn.scale(1, 1, 1.5); kn.translate(RX - RR + 0.002, -0.006, 0);
  add(kn, L.cloth);
  if (o.strip) {
    const H = o.strip, path = chainPath(kit, H), cv = new THREE.CatmullRomCurve3(path.map((q) => new THREE.Vector3(...q)), false, 'centripetal').getPoints(H.n * 4);
    for (const [w, off, len] of [[0.03, 0.006, 1], [0.024, -0.006, 0.72]]) {
      const n = Math.round(cv.length * len), pts = cv.slice(0, n).map((q) => q.clone().add(new THREE.Vector3(0, 0, off)));
      const g = ribbon(pts, { width: (t) => w * (1 - 0.3 * t), normal: [0, 0, 1], camber: 0.12, nu: 2, weights: (t) => chainWeights(H, t * len, 0.05) });
      putSkinned(kit, slot, g, L.cloth, weightsOf(g.userData.W));
    }
  } else {
    for (const [dx, len] of [[-0.012, 0.07], [0.004, 0.05]]) add(ribbon([[RX - RR + 0.002, -0.012, 0], [RX - RR + dx, -0.012 - len * 0.5, 0.004], [RX - RR + dx * 1.6, -0.012 - len, 0]], { width: 0.024, normal: [0, 0, 1], camber: 0.12, nu: 2, solid: true }), L.cloth);
  }
  return WEAPON_SPECS.greatsword;
}

// ---- ISKA: crescent blade -------------------------------------------------------------------------------------------------

/** Crescent geometry constants: the spine follows an arc of radius CR through CA, starting at CX0 on the grip axis. */
const CR = 0.42, CA = 68 * DEG, CX0 = 0.06;
const crescentArc = (t) => [Math.sin(t * CA) * CR, (1 - Math.cos(t * CA)) * CR];
/** Tip of the crescent in the weapon bone frame (also WEAPON_SPECS.crescents[*].tip). */
export const CRESCENT_TIP = [CX0 + crescentArc(1)[0], crescentArc(1)[1], 0];

/** One crescent blade authored for the right hand (the left one is its mirror image). */
function crescentGeo(L) {
  const parts = [];
  // crescent moon blade: widest in the middle, both ends pointed; curves toward +Y (the back), true edge -Y outside
  const W = (t) => 0.004 + 0.034 * Math.pow(Math.sin(Math.PI * Math.min(1, t * 1.04)), 0.75) * (1 - 0.3 * t);
  const TH = (t) => 0.0042 * (1 - 0.6 * t) + 0.0008;
  // close-up section: blued spine on the concave (+x) side with chamfers, narrowing to a false edge at the point; a
  // fuller toward the spine (hard lips, flat floor) holding the starlight seam as an inset; hollow-ground flat and a
  // polished bevel to the true edge on the convex outside
  const FC0 = 0.1, FC1 = 0.74;
  const cful = (t, w) => { const k = clamp(Math.min((t - FC0) / 0.06, (FC1 - t) / 0.1), 0, 1); return [w * 0.3, Math.min(0.0058, w * 0.2) * Math.sqrt(k), 0.0017 * Math.min(1, k * 1.5)]; };
  const SP = (t) => TH(t) * 0.8 * (1 - sstep(0.7, 0.93, t)) + 0.00015;
  const csec = (t) => {
    const w = Math.max(0.0012, W(t)), th = TH(t), sp = Math.min(SP(t), th * 0.9), ch = Math.min(0.0028, w * 0.14), e = Math.min(0.0095, w * 0.42);
    const [fc, fw, fd] = cful(t, w);
    return {
      top: [[w, sp, 1]],
      face: [[w - ch, th * 0.96, 1], [fc + fw, th, 1], [fc + fw * 0.62, th - fd, 1], [fc - fw * 0.62, th - fd, 1], [fc - fw, th, 1], [lerp(fc - fw, -(w - e), 0.5), th * 0.74, 0], [-(w - e), th * 0.5, 1]],
      bot: [[-w, 0, 1]],
    };
  };
  const CS = 40, cpts = [];
  for (let i = 0; i <= CS; i++) { const [dx, dy] = crescentArc(i / CS); cpts.push([CX0 + dx, dy, 0]); }
  const blade = facetBlade(cpts, csec);
  // section coordinates of a point (right-hand frame): t along the arc, a across (toward the concave side)
  const loc = (p) => { const dx = p[0] - CX0, dy = CR - p[1]; return [clamp(Math.atan2(dx, dy) / CA, 0, 1), CR - Math.hypot(dx, dy)]; };
  const kind = (p) => {
    const [t, a] = loc(p), w = Math.max(0.0012, W(t)), e = Math.min(0.0095, w * 0.42), ch = Math.min(0.0028, w * 0.14), [fc, fw, fd] = cful(t, w);
    if (a < -(w - e * 0.85)) return 1;                                                              // polished bevel
    if (fd > 0.0004 && Math.abs(a - fc) < fw * 0.9 && Math.abs(p[2]) < TH(t) - fd * 0.3) return 3;   // fuller groove
    if (a > w - ch * 1.1 && SP(t) > 0.0009) return 2;                                               // spine + chamfers
    return 0;
  };
  const arr = (c) => (Array.isArray(c) ? c : [0.6, 0.64, 0.7]);
  const bc = arr(L.blade.color), sc = arr(L.spine.color);
  // blade uv set: u along the arc (m), v from the true edge on the convex outside (0) to the spine (1), code = temper line
  withUvw(blade, (p) => { const [t, a] = loc(p), w = Math.max(0.0012, W(t)); return [t * CR * CA, clamp((a + w) / (2 * w), 0, 1), 0.3]; });
  parts.push([blade, L.blade, { color: (p) => [bc, bc, sc, sc][kind(p)], cav: (p) => (kind(p) === 3 ? 0.6 : 1) }]);
  // starlight seam inset on the fuller floor (both flats), narrowing with the fuller
  const nrmAt = (t) => [-Math.sin(t * CA), Math.cos(t * CA)];
  for (const s of [1, -1]) {
    const pts = [], T0 = 0.14, T1 = 0.7;
    for (let i = 0; i <= 22; i++) {
      const t = lerp(T0, T1, i / 22), [dx, dy] = crescentArc(t), [fc, , fd] = cful(t, W(t)), [nx, ny] = nrmAt(t);
      pts.push([CX0 + dx + nx * fc, dy + ny * fc, s * (TH(t) - fd + 0.0003)]);
    }
    parts.push([sweep(pts, (u) => rrect(Math.max(0.0003, Math.min(0.00095, cful(lerp(T0, T1, u), W(lerp(T0, T1, u)))[1] * 0.17)), 0.00045, 0, 0), { up: [0, 1, 0] }), L.star, { glow: () => [0.75, 0, 0] }]);
  }
  // small four-point stars set into the hollow-ground flat (tilted to lie on it), crisp unbevelled cut
  const star4 = [];
  for (let k = 0; k < 8; k++) { const a = (k / 8) * Math.PI * 2, rr = k % 2 ? 0.0012 : 0.0042; star4.push([Math.cos(a) * rr, Math.sin(a) * rr]); }
  for (const [t, f, sc4] of [[0.24, 0.45, 1], [0.36, 0.62, 0.7], [0.49, 0.42, 0.85], [0.61, 0.6, 0.62], [0.77, 0.42, 0.75]]) {
    const face = csec(t).face, a = lerp(face[4][0], face[6][0], f), z = faceZ(face, a);
    const slope = (faceZ(face, a + 0.001) - faceZ(face, a - 0.001)) / 0.002;
    const [dx, dy] = crescentArc(t), [nx, ny] = nrmAt(t);
    for (const s of [1, -1]) {
      const st = extrude(star4, { depth: 0.0007, bevel: 0 });
      st.scale(sc4, sc4, 1);
      st.rotateX(s * Math.atan(slope));
      st.rotateZ(t * CA);
      st.translate(CX0 + dx + nx * a, dy + ny * a, s * (z + 0.00025));
      parts.push([st, L.star]);
    }
  }
  // knuckle bow from the guard around the fingers (-Y side) to the pommel
  parts.push([sweep(curve([[0.05, -0.024, 0], [0.032, -0.058, 0], [-0.015, -0.066, 0], [-0.058, -0.042, 0], [-0.068, -0.014, 0]], 16), circle(6), { scale: 0.0045, caps: true, up: [0, 0, 1] }), L.silver]);
  const guard = extrude([[0, -0.03], [0.02, -0.028], [0.03, 0], [0.02, 0.03], [0, 0.034], [-0.01, 0]], { depth: 0.018, bevel: 0.003, bevelSegs: 2 });
  guard.translate(0.045, 0, 0);
  parts.push([guard, L.silver]);
  const grip = lathe([[0.0, 0], [0.0138, 0], [0.0134, 0.06], [0.0148, 0.11], [0.0, 0.11]], { segs: 12 });
  grip.rotateZ(90 * DEG); grip.translate(0.05, 0, 0);
  parts.push([grip, L.wrap]);
  parts.push([helixWrap({ x0: 0.044, x1: -0.054, r: 0.0142, turns: 9, width: 0.0125, thick: 0.0018, seg: 7 }), L.wrap]);
  // pommel: a silver cap set with a pale jade bead, and a small ring for the tassel cord
  const pom = lathe([[0.0, -0.012], [0.017, -0.01], [0.021, 0], [0.014, 0.014], [0.0105, 0.019]], { segs: 10, hard: [2] });
  pom.rotateZ(90 * DEG); pom.translate(-0.068, 0, 0);
  parts.push([pom, L.silver]);
  const bead = lathe([[0, 0.0085], [0.006, 0.006], [0.0085, 0], [0.006, -0.006], [0, -0.0085]], { segs: 8 });
  bead.translate(-0.093, 0, 0);
  parts.push([bead, L.jade || L.star]);
  const rg = [];
  for (let i = 0; i < 12; i++) { const a = (i / 12) * Math.PI * 2; rg.push([-0.108 + Math.cos(a) * 0.0085, Math.sin(a) * 0.0085, 0]); }
  parts.push([sweep(rg, circle(4), { scale: 0.0017, closed: true, up: [0, 0, 1] }), L.silver]);
  const star = [];
  for (let k = 0; k < 8; k++) { const a = (k / 8) * Math.PI * 2, rr = k % 2 ? 0.004 : 0.011; star.push([Math.cos(a) * rr, Math.sin(a) * rr]); }
  for (const s of [1, -1]) {
    const st = extrude(star, { depth: 0.002, bevel: 0.0008, bevelSegs: 1 });
    st.translate(0.06, 0.004, s * 0.011);
    parts.push([st, L.star]);
  }
  return parts;
}

/** Spring chains of the short tassels on the crescents' pommel rings: [right, left] (spread both into the design). */
export function crescentTasselRigs(o = {}) {
  return ['R', 'L'].map((h) => hang('ctas' + h + '_', 'weapon' + h, [-0.116, 0, 0], { n: 2, len: o.len ?? 0.11, dir: [-0.5, -1, 0], stiffness: 26, damping: 3, gravity: 1, limit: 80, radius: 0.01, collide: false }));
}

/**
 * Build 설리화's 월아쌍도, the twin crescent blades (weaponR + mirrored on weaponL): unchanged outline, a honed moon edge
 * with a temper line, a blued spine, the starlight seam and stars, a cord-wrapped grip, a jade-set pommel with a ring.
 * o: slot, looks (WEAPON_LOOKS.crescents keys), tassels ([right, left] chains of crescentTasselRigs(); optional)
 */
export function crescents(kit, o = {}) {
  const L = { ...WEAPON_LOOKS.crescents, ...(o.looks || {}) };
  const slot = o.slot ?? 'blade';
  for (const [g, look, extra] of crescentGeo(L)) putPair(kit, slot, 'weapon', g, look, extra);
  (o.tassels || []).forEach((H) => {
    const T = tassel({ len: 0.075, r: 0.007, strands: 7, head: 0.0055 }), b = H.names[H.n - 1];
    put(kit, slot, b, T.head, L.silver); put(kit, slot, b, T.strands, L.hair);
    put(kit, slot, H.names[0], sweep([[0, 0, 0], [0, -H.seg, 0]], circle(4), { scale: 0.0013, caps: true }), L.wrap);
  });
  return WEAPON_SPECS.crescents;
}

// ---- VORN: war spear --------------------------------------------------------------------------------------------------------

/** Spring chain of the spear's horsehair tassel (창영) below the head (weapon frame; pass it as `tassel`). */
export function spearTasselRig(o = {}) {
  return hang(o.name || 'tassel', 'weapon' + (o.hand || 'R'), [0.928, 0, 0], { n: 2, len: o.len ?? 0.14, dir: [-1, -0.25, 0], stiffness: 30, damping: 3.2, gravity: 1, limit: 75, radius: 0.012, collide: false });
}

/**
 * Build 뇌진천's 뇌룡창 on `bone` (default weaponR): a lacquered haft with cord wraps and engraved bronze bands, a faceted
 * bronze socket, two short wings (o.wings !== false), a broad leaf head with honed edges and the lightning rune in its
 * midrib channel, a bronze butt cap, and the horsehair tassel under the head.
 * o: bone, slot, looks (WEAPON_LOOKS.spear keys), wings=true, tassel (spearTasselRig() chain; without it: a collar only)
 */
export function spear(kit, o = {}) {
  const L = { ...WEAPON_LOOKS.spear, ...(o.looks || {}) };
  const bone = o.bone ?? 'weaponR', slot = o.slot ?? 'blade';
  const add = (g, look, extra) => put(kit, slot, bone, g, look, extra);
  const XB = -0.9, XS = 0.88, XH = 1.02, XT = 1.5;
  // haft: slightly tapered shaft, dark lacquer
  const haft = lathe([[0.0, 0], [0.0175, 0], [0.0185, 0.6], [0.017, XS - XB], [0.0, XS - XB]], { segs: 10 });
  haft.rotateZ(-90 * DEG); haft.translate(XB, 0, 0);
  add(haft, L.haft);
  // wraps at the two grip zones
  for (const [a, b] of [[-0.62, -0.38], [-0.12, 0.12]]) {
    const w = [];
    const n = 80;
    for (let i = 0; i <= n; i++) { const t = i / n, ang = t * Math.PI * 2 * 10; w.push([lerp(a, b, t), Math.cos(ang) * 0.0192, Math.sin(ang) * 0.0192]); }
    add(sweep(w, [[0.0012, -0.0045], [0.0012, 0.0026], [0, 0.0045], [-0.0012, 0.0026], [-0.0012, -0.0045]], { up: [1, 0, 0], hard: [0, 4] }), L.wrap);
  }
  // bands with arc-runes
  for (const xb of [-0.7, -0.27, 0.3, 0.62]) {
    const band = lathe([[0.019, -0.012], [0.0215, -0.009], [0.022, 0], [0.0215, 0.009], [0.019, 0.012]], { segs: 14 });
    band.rotateZ(90 * DEG); band.translate(xb, 0, 0);
    add(band, L.band, { glow: () => [0, 0.8, 0] });
  }
  // socket: octagonal forged socket (flat facets) with a stepped collar at the mouth, a moulded ring below the head and a
  // tapering neck that flows into the midrib; a rivet through it on both flats
  const sock0 = lathe([[0.0188, -0.002], [0.0236, 0.004], [0.0236, 0.012], [0.0206, 0.016], [0.021, 0.06], [0.0186, 0.094], [0.0216, 0.099], [0.0216, 0.106], [0.0176, 0.111], [0.0126, 0.134], [0.006, 0.147], [0.0, 0.152]],
    { segs: 8, hard: [1, 2, 3, 5, 6, 7, 8] });
  sock0.rotateY(22.5 * DEG);
  const sock = autoCav(creased(sock0, 30), 0.004);
  sock0.dispose();
  sock.rotateZ(-90 * DEG); sock.translate(XS, 0, 0);
  add(sock, L.gold);
  for (const s of [1, -1]) {
    const rv = lathe([[0.0, 0.0034], [0.0032, 0.0026], [0.0046, 0.001], [0.0046, 0.0], [0.0, 0.0]], { segs: 7, hard: [3] });
    rv.rotateX(s * 90 * DEG); rv.translate(XS + 0.045, 0, s * 0.0196);
    add(rv, L.band);
  }
  // wings: two lugs below the head, swept back
  for (const s of o.wings === false ? [] : [1, -1]) {
    const wing = extrude([[0, 0], [0.03, 0.008], [0.05, 0.05], [0.032, 0.062], [0.006, 0.026]], { depth: 0.008, bevel: 0.002, bevelSegs: 2 });
    wing.scale(1, s, 1);
    if (s < 0) fixWinding(wing);
    wing.translate(XH - 0.06, s * 0.012, 0);
    add(wing, L.head);
  }
  // broad leaf head, close-up section: polished edge bevels, flats rising to a raised midrib whose crest is split by an
  // engraved channel (dark recessed groove with hard lips) that holds the lightning rune; past the channel the midrib
  // closes into a hard diamond ridge to the point
  const HX0 = XH - 0.01, HS = 30;
  const hw = (t) => 0.012 + 0.042 * Math.pow(Math.sin(Math.PI * Math.min(1, t * 1.25 + 0.05)), 0.9) * (1 - Math.pow(t, 3));
  const hth = (t) => 0.0092 * (1 - t) + 0.001;
  const hev = (t, w) => Math.min(0.012, w * 0.5);
  const chan = (t) => { const k = clamp((t - 0.05) / 0.06, 0, 1) * (1 - sstep(0.44, 0.66, t)); return [0.0085 * Math.sqrt(k), Math.min(0.0032, hth(t) * 0.42) * Math.min(1, k * 1.4)]; };
  const hsec = (t) => {
    const w = Math.max(0.0008, hw(t)), th = hth(t), e = hev(t, w), [cw, d] = chan(t);
    const rw = Math.min(w - e - 0.0005, Math.max(cw + 0.0045, Math.min(0.016, w * 0.45)));
    return {
      top: [[w, 0, 1]],
      face: [[w - e, th * 0.36, 1], [rw, th * 0.6, 1], [cw, th, 1], [cw * 0.7, th - d, 1], [0, th - d * 1.04, 1], [-cw * 0.7, th - d, 1], [-cw, th, 1], [-rw, th * 0.6, 1], [-(w - e), th * 0.36, 1]],
      bot: [[-w, 0, 1]],
    };
  };
  const hpts = [];
  for (let i = 0; i <= HS; i++) hpts.push([lerp(HX0, XT, i / HS), 0, 0]);
  const head = facetBlade(hpts, hsec);
  const htOf = (p) => clamp((p[0] - HX0) / (XT - HX0), 0, 1);
  const hkind = (p) => {
    const t = htOf(p), w = hw(t), [cw, d] = chan(t);
    if (Math.abs(p[1]) > w - hev(t, w) * 0.85) return 1;
    if (d > 0.0005 && Math.abs(p[1]) < cw * 0.92 && Math.abs(p[2]) < hth(t) - d * 0.35) return 2;
    return 0;
  };
  const hc = L.head.color, groove = [0.012, 0.01, 0.018];
  // blade uv set: u along the head (m), v from either cutting edge (0) to the midrib (1), code = temper line
  withUvw(head, (p) => { const t = htOf(p), w = Math.max(0.0008, hw(t)); return [p[0], clamp(1 - Math.abs(p[1]) / w, 0, 1), 0.34]; });
  add(head, L.head, { color: (p) => (hkind(p) === 2 ? groove : hc), cav: (p) => (hkind(p) === 2 ? 0.45 : 1) });
  // the lightning rune: a tapered bolt glyph (long strokes, short sharp returns, a point toward the tip) inlaid on the
  // channel floor of both flats, its top below the lips
  const bolt = boltShape([
    [HX0 + 0.042, 0.0026, 0.0013], [HX0 + 0.09, -0.0032, 0.0012], [HX0 + 0.096, 0.0028, 0.0011], [HX0 + 0.145, -0.003, 0.001],
    [HX0 + 0.151, 0.0024, 0.0009], [HX0 + 0.2, -0.0024, 0.0008], [HX0 + 0.206, 0.0016, 0.0007], [HX0 + 0.262, 0.0, 0.0],
  ]);
  for (const s of [1, -1]) {
    const g = extrude(bolt, { depth: 0.0008, bevel: 0 });
    if (s < 0) { g.scale(1, 1, -1); fixWinding(g); }
    const P = g.attributes.position.array;
    for (let i = 0; i < P.length; i += 3) { const t = clamp((P[i] - HX0) / (XT - HX0), 0, 1), [, d] = chan(t); P[i + 2] += s * (hth(t) - d * 1.04 + 0.00045); }
    g.attributes.position.needsUpdate = true;
    add(g, L.rune, { glow: () => [0.6, 0, 0] });   // a thin hot line: the dark groove must stay readable around it
  }
  // bronze butt cap (창준): a long tapered ferrule with two moulded rings, ending in a blunt point (same reach as before)
  const cap = lathe([[0.0, -0.075], [0.006, -0.068], [0.012, -0.03], [0.0165, 0.0], [0.021, 0.004], [0.021, 0.012], [0.019, 0.016], [0.02, 0.06], [0.0228, 0.064], [0.0228, 0.074], [0.0195, 0.079], [0.0195, 0.11]], { segs: 12, hard: [3, 5, 8, 10] });
  cap.rotateZ(-90 * DEG); cap.translate(XB, 0, 0);
  add(cap, L.gold, { glow: () => [0, 0.3, 0] });
  // horsehair tassel under the head
  if (o.tassel) {
    const T = spearTassel(kit, o.tassel, {});
    add(T.collar, L.gold);
    putSkinned(kit, slot, T.strands, L.hair, weightsOf(T.strands.userData.W));
  }
  return WEAPON_SPECS.spear;
}

/**
 * Build a weapon by name ('greatsword' | 'crescents' | 'spear'). Returns its spec (or [spec, spec]).
 * o: the builder's options; the spring-chain hooks are passed through by name: `strip` (great saber), `tassels`
 * (crescents), `tassel` (spear).
 */
export function buildWeapon(kit, name, o = {}) {
  if (name === 'greatsword') return greatsword(kit, o);
  if (name === 'crescents') return crescents(kit, o);
  if (name === 'spear') return spear(kit, o);
  throw new Error('unknown weapon ' + name);
}

/**
 * Material options of the weapon slot per weapon (glow colours from the roster palette; wearColor = the honed edge of
 * the `blade` uv set). The weapon slot is double sided (cloth strip, tassels) and cut out (wispy strand ends).
 */
export const WEAPON_MATERIALS = {
  greatsword: { cutout: true, envMapIntensity: 1.1, bump: 1, glow: { inlay: [6.5, 2.1, 0.35], vein: [4.2, 1.1, 0.12], eye: [0, 0, 0] }, rim: [0.25, 0.32, 0.45, 3.5], wear: [1.0, 0.7, 0.4, 0.8], wearColor: [0.46, 0.45, 0.44], heatColor: [0.2, 0.08, 0.05] },
  crescents: { cutout: true, envMapIntensity: 1.25, bump: 0.8, glow: { inlay: [1.5, 4, 8], vein: [0.3, 1.0, 2.2], eye: [0, 0, 0] }, rim: [0.3, 0.4, 0.55, 3.5], wearColor: [0.62, 0.66, 0.72] },
  spear: { cutout: true, envMapIntensity: 1.15, bump: 0.9, glow: { inlay: [5, 3.5, 9], vein: [2.4, 1.6, 5.0], eye: [0, 0, 0] }, rim: [0.3, 0.32, 0.5, 3.5], wearColor: [0.52, 0.52, 0.56], verdigris: [0.035, 0.1, 0.08] },
};
