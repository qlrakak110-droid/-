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

import { sweep, lathe, extrude, circle, rrect, curve, put, putPair, mk, fixWinding, creased, autoCav } from './kit/geo.js';

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
    gem: { color: [0.05, 0.004, 0.003], rough: 0.06, metal: 0, set: 'hammered', amt: 0, inlay: 0.012 },
  },
  crescents: {
    blade: { color: [0.62, 0.66, 0.72], rough: 0.14, metal: 1, set: 'hammered', amt: 0.12, wear: 0.4 },
    spine: { color: [0.16, 0.2, 0.28], rough: 0.3, metal: 1, set: 'engraved', amt: 0.8 },
    star: { color: [0.6, 0.8, 1.0], rough: 0.2, metal: 0, set: 'hammered', amt: 0, inlay: 1 },
    silver: { color: [0.55, 0.57, 0.6], rough: 0.25, metal: 1, set: 'engraved', amt: 0.9, vein: 0.35 },
    wrap: { color: [0.06, 0.07, 0.1], rough: 0.7, metal: 0, set: 'leather', amt: 1 },
  },
  spear: {
    head: { color: [0.28, 0.27, 0.3], rough: 0.22, metal: 1, set: 'hammered', amt: 0.25 },
    edge: { color: [0.55, 0.55, 0.58], rough: 0.18, metal: 1, set: 'hammered', amt: 0.3 },
    rune: { color: [0.05, 0.03, 0.08], rough: 0.4, metal: 0.3, set: 'hammered', amt: 0, inlay: 1 },
    haft: { color: [0.06, 0.04, 0.035], rough: 0.6, metal: 0, set: 'leather', amt: 0.5 },
    band: { color: [0.2, 0.17, 0.12], rough: 0.32, metal: 1, set: 'engraved', amt: 0.9, vein: 0.6 },
    wrap: { color: [0.05, 0.035, 0.05], rough: 0.75, metal: 0, set: 'leather', amt: 1 },
    gold: { color: [0.55, 0.36, 0.12], rough: 0.28, metal: 1, set: 'engraved', amt: 0.8 },
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
  // close-up section: hollow-ground edge bevels (hard bevel line), crowned flats, a crisp fuller (hard lips, steep walls,
  // flat floor) that runs out in a point at 0.62, then a hard medial ridge to the point (diamond section)
  const bth = (t) => lerp(0.0085, 0.0045, t) * (t > 0.9 ? 1 - (t - 0.9) * 6 : 1) + 0.0006;
  const bbev = (t) => lerp(0.016, 0.01, t);
  const FT = 0.62, FW = 0.0145, FD = 0.0034;
  const ful = (t) => { if (t >= FT) return [0, 0]; const k = clamp(Math.min(t / 0.03, (FT - t) / 0.07), 0, 1); return [FW * Math.sqrt(k), FD * Math.min(1, k * 1.6)]; };
  const gsec = (t) => {
    const w = Math.max(0.0008, bw(t)), th = Math.max(0.0004, bth(t)), e = Math.min(bbev(t), w * 0.8), [fw, fd] = ful(t);
    const rdg = sstep(FT - 0.04, FT + 0.1, t), crown = Math.max(fw * 1.45, (w - e) * 0.55), zc = th * (1 - 0.14 * rdg);
    return {
      top: [[w, 0, 1]],
      face: [[w - e, th * 0.64, 1], [crown, zc, 0], [fw, th, 1], [fw * 0.74, th - fd, 1], [0, th - fd * 1.04, 1], [-fw * 0.74, th - fd, 1], [-fw, th, 1], [-crown, zc, 0], [-(w - e), th * 0.64, 1]],
      bot: [[-w, 0, 1]],
    };
  };
  const GS = 26, gpts = [];
  for (let i = 0; i <= GS; i++) gpts.push([lerp(XR, X1, i / GS), 0, 0]);
  const blade = facetBlade(gpts, gsec);
  // vertex glow: ember cracks concentrated along the core, fading toward the edges and the tip
  const crack = (p) => {
    const t = (p[0] - XR) / (X1 - XR), off = Math.abs(p[1]);
    const core = 1 - sstep(0.012, 0.05, off);
    const v = core * (1 - sstep(0.55, 0.95, t)) * (0.55 + 0.45 * Math.sin(p[0] * 23.0 + 1.3) * Math.sin(p[0] * 7.1));
    return [0, Math.max(0, v), 0];
  };
  const tOf = (p) => clamp((p[0] - XR) / (X1 - XR), 0, 1);
  const edgeK = (p) => { const t = tOf(p); return Math.abs(p[1]) > bw(t) - bbev(t) * 0.8 ? 1 : 0; };
  // fuller channel (walls + floor): blackened, grimy steel so the molten seam sits in a dark groove
  const fulK = (p) => { const t = tOf(p), [fw, fd] = ful(t); return fd > 0.0004 && Math.abs(p[1]) < fw * 0.96 && Math.abs(p[2]) < bth(t) - fd * 0.3 ? 1 : 0; };
  const ec = L.edge.color, bc = L.blade.color, fcol = L.fuller.color;
  add(blade, L.blade, { glow: crack, color: (p) => (edgeK(p) ? ec : fulK(p) ? fcol : bc), cav: (p) => (fulK(p) ? 0.55 : 1) });
  // fuller floor: a glowing molten seam laid on the floor of the fuller (both flats), narrowing with the run-out
  for (const s of [1, -1]) {
    const pts = [], TS = 0.6;
    for (let i = 0; i <= 18; i++) { const t = 0.02 + (i / 18) * (TS - 0.02), fd = ful(t)[1]; pts.push([lerp(XR, X1, t), 0, s * (bth(t) - fd * 1.04 + 0.0003)]); }
    const seam = sweep(pts, (t) => rrect(Math.max(0.0005, Math.min(0.0034, ful(lerp(0.02, TS, t))[0] * 0.36)), 0.0005, 0, 0), { up: [0, 1, 0], caps: true, scale: 1 });
    add(seam, L.fuller, { glow: (p) => { const t = (p[0] - XR) / (X1 - XR); return [0.55 + 0.45 * Math.sin(p[0] * 31.0) * Math.sin(p[0] * 9.0 + 0.7), 0.6, 0].map((x, k) => (k === 0 ? x * (1 - sstep(0.45, 0.62, t)) : x)); } });
  }
  // ricasso: blunt thick block between the guard and the blade, chamfered (hard facets) so the light breaks crisply on
  // its corners, with two parrying lugs
  const ricS = [[0.048, 0.0035], [0.0435, 0.0115], [-0.0435, 0.0115], [-0.048, 0.0035], [-0.048, -0.0035], [-0.0435, -0.0115], [0.0435, -0.0115], [0.048, -0.0035]];
  const ric = sweep([[X0 - 0.005, 0, 0], [XR + 0.004, 0, 0]], ricS, { up: [0, 1, 0], hard: [0, 1, 2, 3, 4, 5, 6, 7] });
  add(ric, L.iron);
  // maker's mark on the ricasso (both flats): an eclipse ring (bronze) over a sunk ember pip
  for (const s of [1, -1]) {
    const ring = sweep(circle(10).map(([c, d]) => [XR - 0.05 + c * 0.0095, d * 0.0095, s * 0.0118]), [[0.0016, 0], [0, 0.0009], [-0.0016, 0], [0, -0.0009]], { closed: true, up: [0, 0, 1] });
    add(ring, L.bronze);
    const pip = lathe([[0.0, 0.0012], [0.0042, 0.0008], [0.0058, 0.0], [0.0, 0.0]], { segs: 7 });
    pip.rotateX(s * 90 * DEG); pip.translate(XR - 0.05 + 0.0024, 0.0024, s * 0.0113);
    add(pip, L.gem);
  }
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
    const gem = lathe([[0.0, 0.0095], [0.006, 0.0088], [0.011, 0.0068], [0.0145, 0.0038], [0.016, 0.0008], [0.016, 0], [0.0, 0]], { segs: 12, hard: [4] });
    gem.rotateX(s * 90 * DEG);
    gem.translate(X0 + 0.004, 0, s * 0.0215);
    add(gem, L.gem);
    const bez = sweep(circle(14).map(([c, d]) => [X0 + 0.004 + c * 0.0195, d * 0.0195, s * 0.021]), circle(4), { scale: 0.0028, closed: true, up: [0, 0, 1] });
    add(bez, L.bronze);
  }
  for (const s of [1, -1]) {
    const q = curve([[X0 - 0.012, s * 0.045, 0], [X0 - 0.008, s * 0.11, 0], [X0 + 0.006, s * 0.175, 0], [X0 + 0.036, s * 0.215, 0]], 12);
    // forged section: a hard ridge runs along both faces of each quillon (catches a crisp highlight in close-ups)
    const quill = sweep(q, [[1, 0], [0.62, 0.72], [0, 1], [-0.62, 0.72], [-1, 0], [-0.62, -0.72], [0, -1], [0.62, -0.72]], {
      hard: [2, 6],
      scale: (t) => { const k = 1 - 0.32 * sstep(0, 0.8, t) + 0.55 * sstep(0.82, 1, t); return [0.019 * k, 0.024 * k]; },
      up: [1, 0, 0], caps: true,
    });
    add(quill, L.iron);
    // forked tip: two short flame prongs
    for (const f of [-1, 1]) {
      const pr = curve([[X0 + 0.03, s * 0.212, f * 0.006], [X0 + 0.046 + f * 0.01, s * 0.236, f * 0.012], [X0 + 0.056 + f * 0.022, s * 0.244, f * 0.014]], 6);
      add(sweep(pr, circle(5), { scale: (t) => 0.011 * (1 - t * 0.85), caps: true, up: [0, 0, 1] }), L.iron);
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
  add(helixWrap({ x0: GX0 - 0.008, x1: GX1 + 0.014, r: (t) => 0.0172 + 0.0012 * Math.sin(t * Math.PI), turns: 13, width: 0.019, thick: 0.0022, seg: 8 }), L.leather);
  for (const xw of [-0.088, -0.1]) add(sweep(circle(14).map(([c, d]) => [xw, c * 0.02, d * 0.02]), circle(4), { scale: 0.0013, closed: true, up: [1, 0, 0] }), L.wire);
  for (const [xf, r] of [[GX0 + 0.004, 0.0215], [GX1 - 0.002, 0.022]]) {
    const fe = lathe([[r * 0.9, -0.009], [r, -0.006], [r * 1.04, 0], [r, 0.006], [r * 0.9, 0.009]], { segs: 16 });
    fe.rotateZ(90 * DEG); fe.translate(xf, 0, 0);
    add(fe, L.bronze);
  }
  // pommel: heavy faceted wheel with an ember core, peen block
  const PX = GX1 - 0.045;
  // octagonal forged wheel (flat facets), raised rim with a hard apex, dished faces holding the ember cores
  const wheel0 = lathe([[0.0, -0.0165], [0.0165, -0.0165], [0.0205, -0.0225], [0.029, -0.0225], [0.038, -0.0135], [0.0425, 0], [0.038, 0.0135], [0.029, 0.0225], [0.0205, 0.0225], [0.0165, 0.0165], [0.0, 0.0165]], { segs: 8, hard: [1, 2, 3, 4, 5, 6, 7, 8, 9] });
  wheel0.rotateY(22.5 * DEG);
  const wheel = autoCav(creased(wheel0, 30), 0.004);
  wheel0.dispose();
  wheel.rotateX(90 * DEG); wheel.translate(PX, 0, 0);
  add(wheel, L.iron);
  for (const s of [1, -1]) {
    const core2 = lathe([[0.0, 0.0062], [0.006, 0.0054], [0.011, 0.0034], [0.0145, 0.0], [0.0, 0.0]], { segs: 12 });
    core2.rotateX(s * 90 * DEG); core2.translate(PX, 0, s * 0.0163);
    add(core2, L.gem);
  }
  const peen = lathe([[0.0, 0], [0.012, 0], [0.014, 0.008], [0.009, 0.016], [0.0, 0.018]], { segs: 8, hard: [1] });
  peen.rotateZ(90 * DEG); peen.translate(PX - 0.036, 0, 0);
  add(peen, L.bronze);
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
  const bc = arr(L.blade.color), sc = arr(L.spine.color), ec = bc.map((c) => Math.min(1, c * 1.2 + 0.05));
  parts.push([blade, L.blade, { color: (p) => [bc, ec, sc, sc][kind(p)], cav: (p) => (kind(p) === 3 ? 0.6 : 1) }]);
  // starlight seam inset on the fuller floor (both flats), narrowing with the fuller
  const nrmAt = (t) => [-Math.sin(t * CA), Math.cos(t * CA)];
  for (const s of [1, -1]) {
    const pts = [], T0 = 0.14, T1 = 0.7;
    for (let i = 0; i <= 22; i++) {
      const t = lerp(T0, T1, i / 22), [dx, dy] = crescentArc(t), [fc, , fd] = cful(t, W(t)), [nx, ny] = nrmAt(t);
      pts.push([CX0 + dx + nx * fc, dy + ny * fc, s * (TH(t) - fd + 0.0003)]);
    }
    parts.push([sweep(pts, (u) => rrect(Math.max(0.0004, cful(lerp(T0, T1, u), W(lerp(T0, T1, u)))[1] * 0.42), 0.00045, 0, 0), { up: [0, 1, 0] }), L.star]);
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
  for (const [g, look, extra] of crescentGeo(L)) putPair(kit, slot, 'weapon', g, look, extra);
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
  for (const s of [1, -1]) {
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
  const hc = L.head.color, hec = L.edge.color, groove = [0.012, 0.01, 0.018];
  add(head, L.head, {
    color: (p) => [hc, hec, groove][hkind(p)],
    cav: (p) => (hkind(p) === 2 ? 0.45 : 1),
    glow: (p) => (hkind(p) === 2 ? [0.06, 0, 0] : [0, 0, 0]),          // faint spill of the rune on the groove floor
  });
  // the lightning rune: a tapered bolt glyph (long strokes, short sharp returns, a point toward the tip) inlaid on the
  // channel floor of both flats, its top below the lips
  const bolt = boltShape([
    [HX0 + 0.046, 0.0016, 0.0029], [HX0 + 0.118, -0.0024, 0.0025], [HX0 + 0.125, 0.0019, 0.0023],
    [HX0 + 0.196, -0.0019, 0.0019], [HX0 + 0.202, 0.0013, 0.0015], [HX0 + 0.262, 0.0001, 0.0004], [HX0 + 0.282, 0.0, 0.0],
  ]);
  for (const s of [1, -1]) {
    const g = extrude(bolt, { depth: 0.0008, bevel: 0 });
    if (s < 0) { g.scale(1, 1, -1); fixWinding(g); }
    const P = g.attributes.position.array;
    for (let i = 0; i < P.length; i += 3) { const t = clamp((P[i] - HX0) / (XT - HX0), 0, 1), [, d] = chan(t); P[i + 2] += s * (hth(t) - d * 1.04 + 0.00045); }
    g.attributes.position.needsUpdate = true;
    add(g, L.rune);
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

