// Signature weapons: KAEL's greatsword, ISKA's twin crescent blades, VORN's war spear.
//
// Every weapon is authored in the WEAPON BONE frame of the rig (src/char/README.md "Weapons"): origin = centre of the
// main fist on the grip axis, +X toward the tip, -Y = the true edge (blade) / the spear head's lower wing, +-Z = the
// flats. The design's weapon spec (WEAPON_SPECS.<name>) carries the sockets and grip points the runtime reads:
//   base / tip   -> char.sockets.weaponBase / weaponTip (weaponBase2 / weaponTip2 ... for the second weapon)
//   grips        -> off-hand IK targets ({ pos, rot } in the weapon bone frame; clips choose one with `gripAt`)
//
//   import { WEAPON_SPECS, buildWeapon } from '../../char/weapons.js';
//   design.weapon = WEAPON_SPECS.greatsword;                      // or design.weapons = WEAPON_SPECS.crescents (R + L)
//   build(kit, S) { buildWeapon(kit, 'greatsword', LOOKS); ... }   // adds the pieces on weaponR / weaponL
//
// Glow channels (material option `glow`): inlay = runes / fuller core / star inlays, vein = ember cracks of the blade.

import * as THREE from 'three';
import { sweep, lathe, extrude, merge, circle, rrect, curve, put, putPair, mk, fixWinding, autoCav, studs } from './kit/geo.js';

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
 *   weaponTip   [0.5, 0.21, 0] / weaponTip2                              crescent point (the blade curves toward +Y)
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
    { name: 'crescentR', hand: 'R', slot: 'blade', base: [0.07, 0, 0], tip: [0.5, 0.21, 0], grips: { grip: { pos: [0, 0, 0] }, pommel: { pos: [-0.075, 0, 0] } } },
    { name: 'crescentL', hand: 'L', slot: 'blade', base: [0.07, 0, 0], tip: [0.5, 0.21, 0], grips: { grip: { pos: [0, 0, 0] }, pommel: { pos: [-0.075, 0, 0] } } },
  ],
  spear: {
    name: 'spear', hand: 'R', slot: 'blade',
    base: [1.02, 0, 0], tip: [1.5, 0, 0],
    grips: { grip: { pos: [-0.52, 0, 0] }, choke: { pos: [-0.26, 0, 0] }, butt: { pos: [-0.86, 0, 0] }, head: { pos: [0.78, 0, 0] } },
  },
};

/** Default looks of the weapons (override per design). */
export const WEAPON_LOOKS = {
  greatsword: {
    blade: { color: [0.05, 0.047, 0.046], rough: 0.36, metal: 1, set: 'scorched', amt: 0.85, wear: 1.2 },
    edge: { color: [0.5, 0.49, 0.48], rough: 0.2, metal: 1, set: 'hammered', amt: 0.35, wear: 0.6 },
    fuller: { color: [0.02, 0.016, 0.014], rough: 0.6, metal: 0.4, set: 'scorched', amt: 1, inlay: 0.65, vein: 1 },
    iron: { color: [0.07, 0.065, 0.063], rough: 0.42, metal: 1, set: 'hammered', amt: 1 },
    bronze: { color: [0.32, 0.19, 0.08], rough: 0.36, metal: 1, set: 'engraved', amt: 0.9, vein: 0.5 },
    leather: { color: [0.05, 0.028, 0.018], rough: 0.72, metal: 0, set: 'leather', amt: 1 },
    wire: { color: [0.3, 0.2, 0.1], rough: 0.3, metal: 1, set: 'hammered', amt: 0.3 },
    gem: { color: [0.08, 0.02, 0.005], rough: 0.15, metal: 0, set: 'hammered', amt: 0, inlay: 1.2 },
  },
  crescents: {
    blade: { color: [0.62, 0.66, 0.72], rough: 0.16, metal: 1, set: 'hammered', amt: 0.5, wear: 0.4 },
    spine: { color: [0.16, 0.2, 0.28], rough: 0.3, metal: 1, set: 'engraved', amt: 0.8 },
    star: { color: [0.6, 0.8, 1.0], rough: 0.2, metal: 0, set: 'hammered', amt: 0, inlay: 1 },
    silver: { color: [0.55, 0.57, 0.6], rough: 0.25, metal: 1, set: 'engraved', amt: 0.9, vein: 0.35 },
    wrap: { color: [0.06, 0.07, 0.1], rough: 0.7, metal: 0, set: 'leather', amt: 1 },
  },
  spear: {
    head: { color: [0.28, 0.27, 0.3], rough: 0.24, metal: 1, set: 'hammered', amt: 0.7 },
    edge: { color: [0.55, 0.55, 0.58], rough: 0.18, metal: 1, set: 'hammered', amt: 0.3 },
    rune: { color: [0.05, 0.03, 0.08], rough: 0.4, metal: 0.3, set: 'hammered', amt: 0, inlay: 1 },
    haft: { color: [0.06, 0.04, 0.035], rough: 0.6, metal: 0, set: 'leather', amt: 0.5 },
    band: { color: [0.2, 0.17, 0.12], rough: 0.32, metal: 1, set: 'engraved', amt: 0.9, vein: 0.6 },
    wrap: { color: [0.05, 0.035, 0.05], rough: 0.75, metal: 0, set: 'leather', amt: 1 },
    gold: { color: [0.55, 0.36, 0.12], rough: 0.28, metal: 1, set: 'engraved', amt: 0.8 },
  },
};

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

// ---- KAEL: greatsword ---------------------------------------------------------------------------------------------------

/** Build KAEL's greatsword on `bone` (default weaponR). looks: WEAPON_LOOKS.greatsword (override any key). */
export function greatsword(kit, o = {}) {
  const L = { ...WEAPON_LOOKS.greatsword, ...(o.looks || {}) };
  const bone = o.bone ?? 'weaponR', slot = o.slot ?? 'blade';
  const add = (g, look, extra) => put(kit, slot, bone, g, look, extra);
  const X0 = 0.075, XR = 0.235, X1 = 1.6;              // guard face, ricasso end, tip
  // blade: broad slab with hollow-ground bevels, deep fuller, swelling toward the tip (clip point)
  const bw = (t) => {
    const base = 0.062, mid = 0.058;
    if (t > 0.86) { const k = (t - 0.86) / 0.14; return lerp(mid * 0.92, 0.0008, Math.pow(k, 0.85)); }
    return lerp(base, mid * 0.92, t / 0.86) + 0.004 * Math.sin(Math.PI * t / 0.86);
  };
  const blade = bladeSweep({
    x0: XR, x1: X1, segs: 34,
    w: bw, th: (t) => lerp(0.0085, 0.0045, t) * (t > 0.9 ? 1 - (t - 0.9) * 6 : 1) + 0.0006,
    bevel: (t) => lerp(0.016, 0.01, t),
    fuller: { from: 0.0, to: 0.62, w: 0.015, depth: 0.0035 },
  });
  // vertex glow: ember cracks concentrated along the core, fading toward the edges and the tip
  const crack = (p) => {
    const t = (p[0] - XR) / (X1 - XR), off = Math.abs(p[1]);
    const core = 1 - sstep(0.012, 0.05, off);
    const v = core * (1 - sstep(0.55, 0.95, t)) * (0.55 + 0.45 * Math.sin(p[0] * 23.0 + 1.3) * Math.sin(p[0] * 7.1));
    return [0, Math.max(0, v), 0];
  };
  add(blade, L.blade, { glow: crack });
  // fuller floor: a glowing molten seam inside the fuller (thin strip on both flats)
  for (const s of [1, -1]) {
    const pts = [];
    for (let i = 0; i <= 18; i++) { const t = (i / 18) * 0.6; pts.push([lerp(XR + 0.02, X1, t), 0, s * (lerp(0.0085, 0.0045, t) + 0.0006 - 0.0035 * 1.05 + 0.0004)]); }
    const seam = sweep(pts, rrect(0.0035, 0.0006, 0, 0), { up: [0, 1, 0], caps: true, scale: 1 });
    add(seam, L.fuller, { glow: (p) => { const t = (p[0] - XR) / (X1 - XR); return [0.55 + 0.45 * Math.sin(p[0] * 31.0) * Math.sin(p[0] * 9.0 + 0.7), 0.6, 0].map((x, k) => (k === 0 ? x * (1 - sstep(0.45, 0.62, t)) : x)); } });
  }
  // ricasso: blunt thick block between the guard and the blade with two parrying lugs
  const ric = sweep([[X0 - 0.005, 0, 0], [XR + 0.004, 0, 0]], rrect(0.048, 0.0115, 0.006, 2), { up: [0, 1, 0], hard: [] });
  add(ric, L.iron);
  // leather wrap on the ricasso (choked grip)
  const rwrap = [];
  for (let i = 0; i <= 44; i++) {
    const a = i * 0.98, x = X0 + 0.02 + (i / 44) * 0.11;
    rwrap.push([x, Math.cos(a) * 0.05, Math.sin(a) * 0.0135]);
  }
  add(sweep(rwrap, circle(5).map(([c, d]) => [c * 0.0022, d * 0.0042]), { up: [1, 0, 0] }), L.leather);
  for (const s of [1, -1]) {
    const lug = extrude([[0, 0], [0.018, 0], [0.034, 0.024], [0.026, 0.03], [0.006, 0.02]], { depth: 0.013, bevel: 0.0025, bevelSegs: 2 });
    lug.scale(1, s, 1);
    if (s < 0) fixWinding(lug);
    lug.translate(XR - 0.018, s * 0.05, 0);
    add(lug, L.iron);
  }
  // guard: heavy cross with an escutcheon block, swept quillons curving toward the blade, flame-forked tips
  const esc = extrude([[0.0, -0.05], [0.05, -0.034], [0.074, 0], [0.05, 0.034], [0.0, 0.05], [-0.022, 0.03], [-0.022, -0.03]], { depth: 0.04, bevel: 0.005, bevelSegs: 2 });
  esc.translate(X0 - 0.03, 0, 0);
  add(esc, L.iron);
  // ember gem in the escutcheon (both faces)
  for (const s of [1, -1]) {
    const gem = lathe([[0.0, 0.009], [0.012, 0.007], [0.017, 0.002], [0.017, 0], [0.0, 0]], { segs: 12, hard: [2] });
    gem.rotateX(s * 90 * DEG);
    gem.translate(X0 + 0.004, 0, s * 0.0215);
    add(gem, L.gem);
    const bez = sweep(circle(16).map(([c, d]) => [X0 + 0.004 + c * 0.0195, d * 0.0195, s * 0.021]), circle(5), { scale: 0.0028, closed: true, up: [0, 0, 1] });
    add(bez, L.bronze);
  }
  for (const s of [1, -1]) {
    const q = curve([[X0 - 0.01, s * 0.045, 0], [X0 - 0.005, s * 0.12, 0], [X0 + 0.02, s * 0.2, 0], [X0 + 0.062, s * 0.25, 0]], 16);
    const quill = sweep(q, rrect(1, 1, 0.55, 1), {
      scale: (t) => { const k = 1 - 0.45 * sstep(0, 0.85, t) + 0.5 * sstep(0.85, 1, t); return [0.0145 * k, 0.017 * k]; },
      up: [1, 0, 0], caps: true,
    });
    add(quill, L.iron);
    // forked tip: two short flame prongs
    for (const f of [-1, 1]) {
      const pr = curve([[X0 + 0.055, s * 0.243, 0], [X0 + 0.075 + f * 0.012, s * 0.265, f * 0.004], [X0 + 0.09 + f * 0.022, s * 0.272, f * 0.006]], 6);
      add(sweep(pr, circle(6), { scale: (t) => 0.0085 * (1 - t * 0.85), caps: true, up: [0, 0, 1] }), L.iron);
    }
    // langet plates running onto the blade (both flats)
    const lg = extrude([[0, -0.016], [0.07, -0.012], [0.085, 0], [0.07, 0.012], [0, 0.016]], { depth: 0.003, bevel: 0.0012, bevelSegs: 1 });
    lg.translate(XR - 0.01, 0, s * 0.0135);
    add(lg, L.bronze);
  }
  // grip: waisted core, helical leather wrap, binding wire rings, bronze ferrules
  const GX0 = X0 - 0.032, GX1 = -0.235;
  const core = lathe([[0.0, 0], [0.0175, 0], [0.0165, 0.08], [0.0158, 0.15], [0.0168, 0.23], [0.0182, 0.27], [0.0, 0.27]], { segs: 14 });
  core.rotateZ(90 * DEG); core.translate(GX0, 0, 0);
  add(core, L.leather);
  const wrap = [];
  const nW = 96;
  for (let i = 0; i <= nW; i++) {
    const t = i / nW, a = t * Math.PI * 2 * 12, x = lerp(GX0 - 0.006, GX1 + 0.012, t);
    const r = 0.0182 + 0.0012 * Math.sin(t * Math.PI);
    wrap.push([x, Math.cos(a) * r, Math.sin(a) * r]);
  }
  add(sweep(wrap, circle(6).map(([c, d]) => [c * 0.0013, d * 0.0052]), { up: [1, 0, 0] }), L.leather);
  for (const xw of [-0.088, -0.1]) add(sweep(circle(14).map(([c, d]) => [xw, c * 0.02, d * 0.02]), circle(4), { scale: 0.0013, closed: true, up: [1, 0, 0] }), L.wire);
  for (const [xf, r] of [[GX0 + 0.004, 0.0215], [GX1 - 0.002, 0.022]]) {
    const fe = lathe([[r * 0.9, -0.009], [r, -0.006], [r * 1.04, 0], [r, 0.006], [r * 0.9, 0.009]], { segs: 16 });
    fe.rotateZ(90 * DEG); fe.translate(xf, 0, 0);
    add(fe, L.bronze);
  }
  // pommel: heavy faceted wheel with an ember core, peen block
  const PX = GX1 - 0.045;
  const wheel = lathe([[0.0, -0.022], [0.026, -0.022], [0.036, -0.014], [0.041, 0], [0.036, 0.014], [0.026, 0.022], [0.0, 0.022]], { segs: 10, hard: [1, 2, 4, 5] });
  wheel.rotateX(90 * DEG); wheel.translate(PX, 0, 0);
  add(wheel, L.iron);
  for (const s of [1, -1]) {
    const core2 = lathe([[0.0, 0.004], [0.011, 0.003], [0.015, 0.0], [0.0, 0.0]], { segs: 10 });
    core2.rotateX(s * 90 * DEG); core2.translate(PX, 0, s * 0.0222);
    add(core2, L.gem);
  }
  const peen = lathe([[0.0, 0], [0.012, 0], [0.014, 0.008], [0.009, 0.016], [0.0, 0.018]], { segs: 8, hard: [1] });
  peen.rotateZ(90 * DEG); peen.translate(PX - 0.036, 0, 0);
  add(peen, L.bronze);
  return WEAPON_SPECS.greatsword;
}

// ---- ISKA: crescent blade -------------------------------------------------------------------------------------------------

/** One crescent blade authored for the right hand (mirror for the left: pass side 'L'). */
function crescentGeo(L) {
  const parts = [];
  // crescent: the spine follows an arc curving toward +Y (the back); the edge (-Y) is the outer, convex side
  const R = 0.36, A = 62 * DEG, X0 = 0.06;
  const arc = (t) => { const a = t * A; return [Math.sin(a) * R, (1 - Math.cos(a)) * R]; };
  const blade = bladeSweep({
    x0: X0, x1: X0, segs: 44, back: false,
    path: (t) => arc(t),
    w: (t) => 0.004 + 0.034 * Math.pow(Math.sin(Math.PI * Math.min(1, t * 1.05)), 0.8) * (1 - 0.25 * t),
    th: (t) => 0.0042 * (1 - 0.6 * t) + 0.0008,
    bevel: () => 0.009,
    fuller: { from: 0.08, to: 0.7, w: 0.006, depth: 0.0018 },
  });
  parts.push([blade, L.blade, (p) => {
    // starlight: a scatter of points and a constellation line along the flat
    const s = Math.sin(p[0] * 97.0) * Math.sin(p[1] * 131.0 + p[0] * 17.0);
    return [s > 0.93 ? 1 : 0, 0.2, 0];
  }]);
  // guard ring around the fist knuckles + short quillon
  const ring = sweep(curve(circle(16).map(([c, d]) => [0.0 + c * 0.0, 0.0 + c * 0.055 - 0.0, d * 0.03 + 0]), 32, true), circle(6), { scale: 0.005, closed: true, up: [1, 0, 0] });
  ring.translate(0.05, -0.02, 0);
  parts.push([ring, L.silver]);
  const guard = extrude([[0, -0.03], [0.02, -0.028], [0.03, 0], [0.02, 0.03], [0, 0.034], [-0.01, 0]], { depth: 0.018, bevel: 0.003, bevelSegs: 2 });
  guard.translate(0.045, 0, 0);
  parts.push([guard, L.silver]);
  const grip = lathe([[0.0, 0], [0.015, 0], [0.0145, 0.06], [0.016, 0.11], [0.0, 0.11]], { segs: 12 });
  grip.rotateZ(90 * DEG); grip.translate(0.05, 0, 0);
  parts.push([grip, L.wrap]);
  const pom = lathe([[0.0, -0.012], [0.017, -0.01], [0.021, 0], [0.012, 0.016], [0.0, 0.026]], { segs: 10, hard: [2] });
  pom.rotateZ(90 * DEG); pom.translate(-0.068, 0, 0);
  parts.push([pom, L.silver]);
  const star = [];
  for (let k = 0; k < 8; k++) { const a = (k / 8) * Math.PI * 2, rr = k % 2 ? 0.004 : 0.011; star.push([Math.cos(a) * rr, Math.sin(a) * rr]); }
  for (const s of [1, -1]) {
    const st = extrude(star, { depth: 0.002, bevel: 0.0008, bevelSegs: 1 });
    st.translate(0.06, 0.004, s * 0.011);
    parts.push([st, L.star]);
  }
  return parts;
}

/** Build ISKA's twin crescent blades (weaponR + mirrored on weaponL). */
export function crescents(kit, o = {}) {
  const L = { ...WEAPON_LOOKS.crescents, ...(o.looks || {}) };
  const slot = o.slot ?? 'blade';
  for (const [g, look, glow] of crescentGeo(L)) putPair(kit, slot, 'weapon', g, look, glow ? { glow } : {});
  return WEAPON_SPECS.crescents;
}

// ---- VORN: war spear --------------------------------------------------------------------------------------------------------

/** Build VORN's war spear on `bone` (default weaponR). */
export function spear(kit, o = {}) {
  const L = { ...WEAPON_LOOKS.spear, ...(o.looks || {}) };
  const bone = o.bone ?? 'weaponR', slot = o.slot ?? 'blade';
  const add = (g, look, extra) => put(kit, slot, bone, g, look, extra);
  const XB = -0.9, XS = 0.88, XH = 1.02, XT = 1.5;
  // haft: slightly tapered octagonal-ish shaft
  const haft = lathe([[0.0, 0], [0.0175, 0], [0.0185, 0.6], [0.017, XS - XB], [0.0, XS - XB]], { segs: 10 });
  haft.rotateZ(-90 * DEG); haft.translate(XB, 0, 0);
  add(haft, L.haft);
  // wraps at the two grip zones
  for (const [a, b] of [[-0.62, -0.38], [-0.12, 0.12]]) {
    const w = [];
    const n = 80;
    for (let i = 0; i <= n; i++) { const t = i / n, ang = t * Math.PI * 2 * 10; w.push([lerp(a, b, t), Math.cos(ang) * 0.0192, Math.sin(ang) * 0.0192]); }
    add(sweep(w, rrect(0.0012, 0.0045, 0.0007, 1), { up: [1, 0, 0] }), L.wrap);
  }
  // bands with arc-runes
  for (const xb of [-0.7, -0.27, 0.3, 0.62]) {
    const band = lathe([[0.019, -0.012], [0.0215, -0.009], [0.022, 0], [0.0215, 0.009], [0.019, 0.012]], { segs: 14 });
    band.rotateZ(90 * DEG); band.translate(xb, 0, 0);
    add(band, L.band, { glow: () => [0, 0.8, 0] });
  }
  // socket + langets
  const sock = lathe([[0.019, 0], [0.023, 0.02], [0.021, 0.1], [0.016, 0.14], [0.0, 0.15]], { segs: 14 });
  sock.rotateZ(-90 * DEG); sock.translate(XS, 0, 0);
  add(sock, L.gold);
  // wings: two lugs below the head, swept back
  for (const s of [1, -1]) {
    const wing = extrude([[0, 0], [0.03, 0.008], [0.05, 0.05], [0.032, 0.062], [0.006, 0.026]], { depth: 0.008, bevel: 0.002, bevelSegs: 2 });
    wing.scale(1, s, 1);
    if (s < 0) fixWinding(wing);
    wing.translate(XH - 0.06, s * 0.012, 0);
    add(wing, L.head);
  }
  // broad leaf head with a central ridge
  const head = bladeSweep({
    x0: XH - 0.01, x1: XT, segs: 30,
    w: (t) => 0.012 + 0.042 * Math.pow(Math.sin(Math.PI * Math.min(1, t * 1.25 + 0.05)), 0.9) * (1 - Math.pow(t, 3)),
    th: (t) => 0.009 * (1 - t) + 0.001,
    bevel: () => 0.012,
  });
  add(head, L.head, { glow: (p) => [0, 0, 0] });
  // arc-rune strip along the ridge (both flats)
  for (const s of [1, -1]) {
    const pts = [];
    for (let i = 0; i <= 20; i++) { const t = i / 20; pts.push([lerp(XH + 0.02, XT - 0.12, t), 0.003 * Math.sin(t * 40), s * (0.009 * (1 - (t * 0.8 + 0.05)) + 0.0014)]); }
    add(sweep(pts, rrect(0.0018, 0.0005, 0.0003, 1), { up: [0, 1, 0] }), L.rune);
  }
  // counterweight: heavy bulb + short spike
  const cw = lathe([[0.0, 0.0], [0.016, 0.0], [0.026, 0.03], [0.03, 0.06], [0.024, 0.085], [0.019, 0.1], [0.0175, 0.11]], { segs: 12, hard: [3] });
  cw.rotateZ(90 * DEG); cw.translate(XB + 0.11, 0, 0);
  add(cw, L.gold, { glow: () => [0, 0.4, 0] });
  const spike = lathe([[0.0, 0.0], [0.015, 0.0], [0.004, 0.07], [0.0, 0.075]], { segs: 8 });
  spike.rotateZ(90 * DEG); spike.translate(XB + 0.0, 0, 0);
  add(spike, L.head);
  return WEAPON_SPECS.spear;
}

/** Build a weapon by name ('greatsword' | 'crescents' | 'spear'). Returns its spec (or [spec, spec]). */
export function buildWeapon(kit, name, o = {}) {
  if (name === 'greatsword') return greatsword(kit, o);
  if (name === 'crescents') return crescents(kit, o);
  if (name === 'spear') return spear(kit, o);
  throw new Error('unknown weapon ' + name);
}

/** Material options of the weapon slot per weapon (glow colours from the roster palette). */
export const WEAPON_MATERIALS = {
  greatsword: { envMapIntensity: 1.1, bump: 1, glow: { inlay: [6.5, 2.1, 0.35], vein: [4.2, 1.1, 0.12], eye: [0, 0, 0] }, rim: [0.25, 0.32, 0.45, 3.5], wear: [1.0, 0.7, 0.4, 0.8], wearColor: [0.42, 0.42, 0.43], heatColor: [0.2, 0.08, 0.05] },
  crescents: { envMapIntensity: 1.25, bump: 0.8, glow: { inlay: [1.5, 4, 8], vein: [0.3, 1.0, 2.2], eye: [0, 0, 0] }, rim: [0.3, 0.4, 0.55, 3.5] },
  spear: { envMapIntensity: 1.15, bump: 0.9, glow: { inlay: [5, 3.5, 9], vein: [2.4, 1.6, 5.0], eye: [0, 0, 0] }, rim: [0.3, 0.32, 0.5, 3.5] },
};

export { studs, mk, autoCav, merge };
