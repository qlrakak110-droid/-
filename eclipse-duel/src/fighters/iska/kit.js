// ISKA's kit pieces (Froststar Oracle). Geometry builders in bone zero-pose frames (+X forward, +Y up, +Z the fighter's
// right / camera side), returning kit-geo geometries (position, normal, cav) for put() / putPair() / putSkinned().
//
//   head frame:  headBase, oracleMask { brow, lower, eyes, veil, tears }, hood (hood + shoulder mantle, skin it with
//                hoodWeights), circlet { band, crest, star, drops }
//   neck frame:  highCollar { collar, flare, clasp }
//   any frame:   lamellarRow, scaleRows (around a body cross-section), crystal / crystalCluster, starShape
//   deltoid:     crescentSpaulder { crescent, cap, lames, trim, rivets }
//   forearm:     crescentVambrace          shin: oracleGreave
//
// Silhouette intent (vs KAEL's heavy, blocky asymmetry): tall hood point + standing crescent crest, narrow shoulders with
// small swept crescent fins, a cinched lamellar waist, long slender legs, twin cape tails and a long front tabard.

import { profile } from '../../char/shapes.js';
import { plate, sweep, lathe, extrude, strip, studs, onSurface, merge, circle, rrect, curve } from '../../char/kit/geo.js';
import { hoop, se, dome } from '../../char/kit/armor.js';

const DEG = Math.PI / 180;
const lerp = (a, b, t) => a + (b - a) * t;
const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);
const sstep = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
const bump = (x, a, b) => (x <= a || x >= b ? 0 : Math.sin(Math.PI * (x - a) / (b - a)));

// ---- head reference (head frame: origin at the skull base, head top ~ +0.19) ----------------------------------------------
const HY = [-0.07, -0.04, 0.0, 0.03, 0.07, 0.1, 0.14, 0.17, 0.19];
const curveY = (vals) => profile(HY.map((y, i) => [y, vals[i]]));
/** Head (under-face) cross-section by height: rx front-back half depth, rz half width, ox centre offset. */
export const HEAD = {
  rx: curveY([0.03, 0.066, 0.084, 0.091, 0.095, 0.096, 0.09, 0.072, 0.034]),
  rz: curveY([0.03, 0.05, 0.062, 0.069, 0.073, 0.074, 0.072, 0.062, 0.03]),
  ox: curveY([0.052, 0.04, 0.026, 0.021, 0.017, 0.013, 0.007, 0.0, -0.005]),
};
/** Eye line and eye opening (angles around the head axis, degrees from the front). */
export const EYE = { y: 0.073, aIn: 10.5, aOut: 37, arch: 0.0115, dip: 0.0062, slope: 0.0055 };
const eyeS = (a) => (Math.abs(a) - EYE.aIn) / (EYE.aOut - EYE.aIn);
const baseLine = (a) => EYE.slope * clamp(eyeS(a), 0, 1);
const upperLid = (a) => { const s = eyeS(a); return s > 0 && s < 1 ? EYE.arch * Math.pow(Math.sin(Math.PI * s), 0.72) * (1.12 - 0.3 * s) : 0; };
const lowerLid = (a) => { const s = eyeS(a); return s > 0 && s < 1 ? EYE.dip * Math.pow(Math.sin(Math.PI * s), 1.05) : 0; };

/** Dark under-face / skull form (veil cloth) filling everything the hood and mask do not cover. */
export function headBase() {
  const y0 = 0.19, y1 = -0.07, Y = (v) => lerp(y0, y1, v);
  return plate((u, v) => {
    const a = lerp(-180, 180, u) * DEG, y = Y(v);
    const [x, z] = se(a, HEAD.rx(y), HEAD.rz(y), 2.1);
    return [HEAD.ox(y) + x, y, z];
  }, { closeU: true, nu: 20, nv: 10, thick: 0, axis: [0.02, 0] });
}

/**
 * Oracle half-mask: brow plate + cheek / nose plate meeting around almond eye openings (bevelled edges), frost eyes
 * glowing behind the openings, a fine mail veil from the nose down into the collar, glowing frost "tear" lines.
 * Returns { brow, lower, eyes, veil, tears, browS, lowerS } (eyes carry no glow: put them with an eye look + eyeGlow()).
 */
export function oracleMask() {
  const out = {};
  const R = (y, g) => [HEAD.rx(y) + g, HEAD.rz(y) + g * 0.85, HEAD.ox(y)];
  // brow plate: forehead to the upper lids, a widow's-peak point under the circlet, sculpted brow ridge
  const by0 = 0.156;
  out.brow = hoop({
    y0: by0, y1: EYE.y, a0: -86, a1: 86,
    rx: (v) => R(lerp(by0, EYE.y, v), 0.0085)[0], rz: (v) => R(lerp(by0, EYE.y, v), 0.0085)[1], ox: (v) => R(lerp(by0, EYE.y, v), 0)[2], n: 2.05,
    top: (a) => 0.013 * Math.pow(Math.max(0, Math.cos(a * DEG)), 14) - 0.012 * sstep(40, 86, Math.abs(a)),
    bot: (a) => baseLine(a) + upperLid(a) - 0.01 * sstep(60, 86, Math.abs(a)),
    bulge: (u, v) => { const a = lerp(-86, 86, u); return 0.0042 * sstep(0.45, 0.9, v) * (1 - sstep(0.9, 1, v)) * (bump(Math.abs(a), 4, 44) ** 0.8) + 0.002 * (1 - v) * Math.cos(a * DEG); },
    ridge: { at: 0, h: 0.0022, w: 10 },
    nu: 40, nv: 6, thick: 0.0045, edgeR: 0.0028, edgeSegs: 3,
  });
  out.browS = out.brow.userData;
  // lower plate: lower lids, nose ridge (crease), cheekbone bulges, cheek guards sweeping down along the jaw
  const ly1 = 0.019;
  out.lower = hoop({
    y0: EYE.y, y1: ly1, a0: -82, a1: 82,
    rx: (v) => R(lerp(EYE.y, ly1, v), 0.0085)[0], rz: (v) => R(lerp(EYE.y, ly1, v), 0.0085)[1], ox: (v) => R(lerp(EYE.y, ly1, v), 0)[2], n: 2.05,
    top: (a) => baseLine(a) - lowerLid(a) - 0.01 * sstep(60, 86, Math.abs(a)),
    bot: (a) => 0.006 * bump(Math.abs(a), 6, 30) - 0.03 * sstep(28, 76, Math.abs(a)),
    ridge: { at: 0, h: (v) => 0.0035 + 0.0175 * Math.pow(v, 1.25), w: 13, pow: 1.2 },
    bulge: (u, v) => { const a = Math.abs(lerp(-82, 82, u)); return 0.0045 * bump(a, 24, 62) * bump(v, -0.1, 0.8); },
    nu: 40, nv: 6, thick: 0.0045, edgeR: 0.0028, edgeSegs: 3,
  });
  out.lowerS = out.lower.userData;
  // frost eyes: shallow glowing patches just in front of the under-face, behind each opening
  const eyes = [];
  for (const s of [1, -1]) {
    const a0 = s > 0 ? EYE.aIn - 3 : -EYE.aOut - 3, a1 = s > 0 ? EYE.aOut + 3 : -EYE.aIn + 3;
    eyes.push(hoop({
      y0: EYE.y + EYE.slope + EYE.arch + 0.004, y1: EYE.y - EYE.dip - 0.004, a0, a1,
      rx: R(EYE.y, 0.0022)[0], rz: R(EYE.y, 0.0022)[1], ox: R(EYE.y, 0)[2], n: 2.05, nu: 10, nv: 4, thick: 0, closed: false,
    }));
  }
  out.eyes = merge(eyes);
  // face wrap: fine veil from under the nose into the collar
  const vy0 = 0.03, vy1 = -0.075;
  out.veil = hoop({
    y0: vy0, y1: vy1, a0: -74, a1: 74,
    rx: (v) => Math.max(R(lerp(vy0, vy1, v), 0.005)[0], R(vy0, 0.003)[0] - 0.012 * v), rz: (v) => R(lerp(vy0, vy1, v), 0.006)[1] + 0.006 * v,
    ox: (v) => R(lerp(vy0, vy1, v), 0)[2] * (1 - 0.4 * v) + 0.006 * v, n: 2.0,
    bot: (a) => 0.02 * sstep(30, 74, Math.abs(a)),
    nu: 20, nv: 4, thick: 0.0015, edgeR: 0.0012, edgeSegs: 2,
  });
  // frost tears: thin inlay lines from the lower lids down the cheeks (the "oracle weeps starlight")
  const tears = [];
  for (const s of [1, -1]) {
    const ac = s * (EYE.aIn + (EYE.aOut - EYE.aIn) * 0.42), u = (ac + 82) / 164;
    tears.push(strip(out.lowerS, curve([[u, 0.14, 0], [u + s * 0.003, 0.36, 0], [u - s * 0.002, 0.58, 0]], 10).map((p) => [p[0], p[1]]), { width: 0.0021, lift: 0.0007, bead: 0.0006, smooth: 2 }));
  }
  out.tears = merge(tears);
  // frost liners: thin inlays tracing each upper lid from the inner corner and sweeping up toward the temple
  const arcs = [];
  for (const s of [1, -1]) {
    const pts = [];
    for (let i = 0; i <= 16; i++) {
      const t = i / 16, a = s * lerp(EYE.aIn + 1, EYE.aOut + 13, t);
      const lidY = EYE.y + baseLine(a) + upperLid(a) * 0.8 + 0.0028 + 0.009 * sstep(0.72, 1, t);
      pts.push([(a + 86) / 172, clamp((by0 + 0.013 * Math.pow(Math.max(0, Math.cos(a * DEG)), 14) - 0.012 * sstep(40, 86, Math.abs(a)) - lidY) / (by0 - EYE.y), 0, 1)]);
    }
    arcs.push(strip(out.browS, pts, { width: 0.0019, lift: 0.0007, bead: 0.0006, smooth: 2 }));
  }
  out.arcs = merge(arcs);
  return out;
}

/** Eye glow mask for oracleMask().eyes: hot iris core at each eye centre, dimmer sclera. Returns fn(p) -> [0, 0, k]. */
export function eyeGlow(k = 1) {
  const ac = (EYE.aIn + EYE.aOut) * 0.5 + 1.5;
  return (p) => {
    const x = p[0] - HEAD.ox(EYE.y), a = Math.atan2(Math.abs(p[2]), x) / DEG;
    const yc = EYE.y + baseLine(ac) + 0.0025;
    const core = Math.exp(-(((a - ac) / 6.5) ** 2) - (((p[1] - yc) / 0.0055) ** 2));
    return [0, 0, k * (0.22 + 0.95 * core)];
  };
}

// ---- hood + shoulder mantle -------------------------------------------------------------------------------------------------
// the crown rounds over the brow and rises into a peak at the back of the head (a cowl, not a cone: the front profile
// is a smooth curve, the point sits behind)
const HOOD_Y = [-0.25, -0.16, -0.1, -0.05, 0.0, 0.06, 0.12, 0.18, 0.21, 0.235, 0.255, 0.268, 0.276];
const hoodC = (vals) => profile(HOOD_Y.map((y, i) => [y, vals[i]]));
const HOOD = {
  rx: hoodC([0.17, 0.145, 0.12, 0.112, 0.117, 0.124, 0.123, 0.111, 0.095, 0.072, 0.048, 0.027, 0.008]),
  rz: hoodC([0.182, 0.152, 0.117, 0.099, 0.099, 0.104, 0.103, 0.097, 0.086, 0.068, 0.046, 0.026, 0.008]),
  ox: hoodC([-0.035, -0.022, -0.008, -0.004, 0.0, 0.0, -0.008, -0.022, -0.035, -0.055, -0.078, -0.1, -0.118]),
};
/** Hood height at surface parameter v (more rows near the crown: the rounded peak stays smooth). */
const hoodY = (v) => lerp(0.276, -0.25, Math.pow(v, 1.3));
/** Face-opening half angle (deg) of the hood at height y: an oval around the face, a narrow front opening below the chin. */
function hoodOpen(y) {
  const t = (y - 0.052) / 0.118;
  const oval = Math.abs(t) < 1 ? 60 * Math.pow(1 - t * t, 0.62) : 0;
  const low = y < 0.0 ? lerp(24, 44, sstep(-0.06, -0.25, y)) : 0;
  return Math.max(oval, low);
}

/**
 * Hood with a peaked crown, framing the masked face, flowing into a short shoulder mantle over the upper back and the
 * collarbones (head frame; skin with hoodWeights). o: { nu = 30, nv = 16 }. Returns { hood, hem, S, vArch } (S =
 * parametric surface: u around from the left face edge, v from the crown point down to the mantle hem; hem = rolled
 * edge around the face opening; vArch = v of the opening's pointed top).
 */
export function hood(o = {}) {
  const S = (u, v) => {
    const y0 = hoodY(v);
    const ao = hoodOpen(y0);
    const a = lerp(ao, 360 - ao, u), ar = a * DEG;
    // hem: deeper point at the back (where the cape tails hang), shallower over the shoulders
    const back = Math.pow(Math.max(0, -Math.cos(ar)), 3), shoulder = Math.pow(Math.abs(Math.sin(ar)), 4);
    const y = y0 + (v > 0.85 ? (-0.06 * back + 0.025 * shoulder) * sstep(0.85, 1, v) : 0);
    const rx = HOOD.rx(y0), rz = HOOD.rz(y0);
    const [x, z] = se(ar, rx, rz, 2.05);
    // soft folds in the mantle and at the back of the hood
    const fold = 0.007 * Math.sin(a * DEG * 9) * sstep(0.55, 1, v) + 0.006 * Math.sin(a * DEG * 6 + 1) * bump(v, 0.05, 0.62) * (0.35 + back);
    const r = Math.hypot(x, z) || 1;
    // the brim over the forehead leans forward (a soft peak)
    const peak = 0.018 * Math.pow(Math.max(0, Math.cos(ar)), 6) * bump(y0, 0.12, 0.26);
    return [HOOD.ox(y0) + x * (1 + fold / r) + peak, y, z * (1 + fold / r)];
  };
  const g = plate(S, {
    nu: o.nu ?? 30, nv: o.nv ?? 16, thick: 0.006, edgeR: 0.0045, inner: true, innerCav: 0.3,
    roll: { v1: 0.005 }, edge: { v0: 'none', u0: 'none', u1: 'none' },
    out: (p) => [p[0] + 0.01, 0, p[2]], occ: (u, v) => 0.82 + 0.18 * sstep(0.0, 0.3, v),
  });
  // rolled hem around the face opening: up the left edge to the pointed arch over the brow, down the right edge
  // (the hood stays seamless above the arch; the two u edges coincide there)
  const vTop = vArch();
  const hemPts = [];
  for (let i = 0; i <= 30; i++) hemPts.push(S(0, 1 - (1 - vTop) * (i / 30)));
  for (let i = 1; i <= 30; i++) hemPts.push(S(1, vTop + (1 - vTop) * (i / 30)));
  const hem = sweep(hemPts.map((p) => [p[0] - 0.002, p[1], p[2]]), circle(6), { scale: 0.0068, caps: true, cavScale: 0.003 });
  return { hood: g, hem, S: g.userData, vArch: vTop };
}

/** v parameter of the hood surface where the face opening closes (the top of the pointed arch). */
function vArch() {
  let lo = 0, hi = 0.6;
  for (let k = 0; k < 30; k++) { const m = (lo + hi) / 2; if (hoodOpen(hoodY(m)) > 0.5) hi = m; else lo = m; }
  return hi;
}

/** Skin weights for hood-like pieces (bind-space y): head above the jaw, blending through the neck onto the chest. */
export function hoodWeights(kit) {
  const hy = kit.bonePos('head')[1], ny = kit.bonePos('neck')[1];
  return (x, y) => {
    if (y >= hy - 0.035) return [['head', 1]];
    if (y >= ny) { const t = sstep(ny, hy - 0.035, y); return [['head', t], ['neck', 1 - t]]; }
    const t = sstep(ny - 0.075, ny, y);
    return [['neck', t], ['chest', 1 - t]];
  };
}

// ---- circlet: crescent-and-star diadem over the hood brim ------------------------------------------------------------------
/**
 * Circlet: a thin silver band across the forehead (over the mask's top edge, vanishing under the hood at the temples),
 * a standing crescent crest (horns up) leaning back against the hood brim, a star in the crescent's cup, crystal drops
 * at the temples. Returns { band, crest, star, drops, studs }.
 */
export function circlet(o = {}) {
  const out = {};
  const yb = 0.148;
  // band: follows the mask brow at the front, tucks under the hood toward the temples
  const pts = [];
  for (let i = 0; i <= 36; i++) {
    const a = lerp(-74, 74, i / 36), ar = a * DEG;
    const [x, z] = se(ar, HEAD.rx(yb) + 0.0145, HEAD.rz(yb) + 0.012, 2.05);
    pts.push([HEAD.ox(yb) + x, yb + 0.006 * Math.pow(Math.cos(ar), 8), z]);
  }
  out.band = sweep(pts, rrect(0.0022, 0.0052, 0.0016, 1), { up: [0, 1, 0], caps: true });
  // crescent crest: two arcs (outer r 0.068, inner 0.054 offset up) -> horns pointing up, extruded, leaning back
  const cres = [];
  const Ro = 0.064, Ri = 0.05, off = 0.024;
  for (let i = 0; i <= 28; i++) { const t = lerp(-1, 1, i / 28), a = t * 112 * DEG; cres.push([Math.sin(a) * Ro, -Math.cos(a) * Ro]); }
  for (let i = 28; i >= 0; i--) {
    const t = lerp(-1, 1, i / 28), a = t * 112 * DEG;
    const p = [Math.sin(a) * Ri, -Math.cos(a) * Ri + off];
    // only keep the inner arc inside the outer disc (horn tips meet)
    const r = Math.hypot(p[0], p[1]);
    cres.push(r > Ro * 0.995 ? [p[0] * Ro * 0.995 / r, p[1] * Ro * 0.995 / r] : p);
  }
  const crest = extrude(cres, { depth: 0.0055, bevel: 0.0016, bevelSegs: 2, curveSegs: 2 });
  // head frame: shape (sx, sy) -> plane facing +X (sx -> -z), leaning back by `tilt`: (x, y) = (-sy sin t, sy cos t) + T,
  // with the crescent's lowest point resting on the band
  const tilt = (o.tilt ?? 24) * DEG;
  const bandFront = HEAD.ox(yb) + HEAD.rx(yb) + 0.0145;
  const T = [bandFront + 0.004 - Ro * Math.sin(tilt), yb + 0.003 + Ro * Math.cos(tilt), 0];
  const place = (g, sy = 0, dx = 0) => { g.rotateY(90 * DEG); g.rotateZ(tilt); g.translate(T[0] + dx, T[1], T[2]); return [T[0] + dx - sy * Math.sin(tilt), T[1] + sy * Math.cos(tilt), 0]; };
  place(crest);
  out.crest = crest;
  // the star in the crescent's hollow: 8 points, glowing (inlay)
  const sy = 0.006;
  const sg = extrude(starShape(0.019, 0.0068, 8), { depth: 0.0065, bevel: 0.0015, bevelSegs: 1, curveSegs: 1 });
  sg.translate(0, sy, 0);
  out.starPos = place(sg, sy, 0.002);
  out.star = sg;
  // crystal drops at the temples (hang from the band ends)
  const drops = [];
  for (const s of [1, -1]) {
    const c = crystal({ r: 0.0055, h: 0.022, tip: 0.012, base: 0.006, sides: 6 });
    c.rotateZ(180 * DEG);
    const a = s * 70 * DEG, [x, z] = se(a, HEAD.rx(yb - 0.02) + 0.018, HEAD.rz(yb - 0.02) + 0.016, 2.05);
    c.translate(HEAD.ox(yb) + x, yb - 0.012, z);
    drops.push(c);
  }
  out.drops = merge(drops);
  const st = [];
  for (const a of [-50, -30, 30, 50]) {
    const ar = a * DEG, [x, z] = se(ar, HEAD.rx(yb) + 0.0175, HEAD.rz(yb) + 0.0145, 2.05);
    st.push({ p: [HEAD.ox(yb) + x, yb, z], n: [Math.cos(ar), 0, Math.sin(ar)] });
  }
  out.studs = studs(st, { r: 0.0038, h: 0.0028, segs: 6 });
  return out;
}

/** n-point star outline (outer radius ro, inner ri) for extrude(). */
export function starShape(ro, ri, n = 4, rot = 0) {
  const pts = [];
  for (let k = 0; k < n * 2; k++) { const a = (k / (n * 2)) * Math.PI * 2 + rot + Math.PI / 2, r = k % 2 ? ri : ro; pts.push([Math.cos(a) * r, Math.sin(a) * r]); }
  return pts;
}

// ---- frost crystals ----------------------------------------------------------------------------------------------------------
/** Hexagonal crystal along +Y: base point, prism, pointed tip. o: { r, h (prism), tip, base, sides = 6, twist } */
export function crystal(o = {}) {
  const r = o.r ?? 0.01, h = o.h ?? 0.03, tip = o.tip ?? 0.02, base = o.base ?? 0.006;
  const g = lathe([[0, -base], [r * 0.85, 0], [r, h * 0.15], [r * 0.92, h], [0, h + tip]], { segs: o.sides ?? 6, hard: [1, 2, 3], auto: true });
  if (o.twist) g.rotateY(o.twist);
  return g;
}

/** Cluster of crystals growing from a point along +Y, fanned. list: [[len, tiltX deg, tiltZ deg, r]] */
export function crystalCluster(list) {
  return merge(list.map(([len, tx, tz, r, tw = 0]) => {
    const c = crystal({ r, h: len * 0.62, tip: len * 0.38, base: r * 0.6, twist: tw });
    c.rotateX(tx * DEG); c.rotateZ(tz * DEG);
    return c;
  }));
}

// ---- high collar ------------------------------------------------------------------------------------------------------------
/**
 * Standing collar (neck frame): tall silver plate around the front and sides of the neck up to the mouth, top edge
 * rising toward swept points behind the jaw, a gorget flare over the collarbones and a crystal clasp at the throat.
 * o: { top = 0.1, bottom = -0.03, nu = 40 }. Returns { collar, flare, clasp, claspGem, collarS }
 */
export function highCollar(o = {}) {
  const out = {};
  const y0 = o.top ?? 0.1, y1 = o.bottom ?? -0.03;
  out.collar = hoop({
    y0, y1, a0: -128, a1: 128,
    rx: [[0, 0.1], [0.45, 0.086], [1, 0.07]], rz: [[0, 0.088], [0.5, 0.075], [1, 0.072]], ox: [[0, 0.034], [0.5, 0.022], [1, 0.008]], n: 2.0,
    // top edge rises from a notch at the throat toward the sides, peaking in a swept point behind the jaw
    top: (a) => {
      const aa = Math.abs(a);
      return 0.014 * sstep(16, 95, aa) + 0.02 * Math.pow(bump(aa, 70, 128), 3) - 0.014 * Math.pow(Math.max(0, Math.cos(a * DEG)), 40);
    },
    bot: (a) => -0.012 * Math.pow(Math.max(0, Math.cos(a * DEG)), 4),
    ridges: [{ at: 0, h: 0.003, w: 8 }],
    flutes: { n: 7, h: 0.0018, a0: -118, a1: 118, fade: (v) => sstep(0.1, 0.7, v) },
    nu: o.nu ?? 40, nv: 4, thick: 0.004, edgeR: 0.0028, roll: { v1: 0.0035 }, inner: true, innerCav: 0.45,
  });
  out.collarS = out.collar.userData;
  // gorget flare over the collarbones
  out.flare = hoop({
    y0: -0.012, y1: -0.072, a0: -140, a1: 140,
    rx: [[0, 0.078], [1, 0.118]], rz: [[0, 0.08], [1, 0.135]], ox: [[0, 0.008], [1, 0.012]], n: 2.1,
    bot: (a) => -0.022 * Math.pow(Math.max(0, Math.cos(a * DEG)), 6),
    nu: 36, nv: 3, thick: 0.004, edgeR: 0.003, roll: { v1: 0.0038 },
  });
  // throat clasp: silver disc + crystal
  const disc = lathe([[0, 0.006], [0.011, 0.0055], [0.016, 0.002], [0.017, 0], [0, 0]], { segs: 16, hard: [2] });
  disc.rotateZ(-90 * DEG);
  disc.translate(0.093, 0.012, 0);
  const cr = crystal({ r: 0.0055, h: 0.012, tip: 0.008, base: 0.003 });
  cr.rotateZ(-90 * DEG);
  cr.translate(0.097, 0.012, 0);
  out.clasp = disc;
  out.claspGem = cr;
  return out;
}

// ---- lamellar and scale -------------------------------------------------------------------------------------------------------
/**
 * One row of lamellae around a body cross-section (bone frame, around the local Y axis): small curved plates
 * overlapping like shingles (each lifted along its trailing edge), rounded / pointed bottoms, a lacing cord.
 * o: y0 (top), h (height), a0, a1 (deg), count, rx(y), rz(y), ox(y) (cross-section by height: fn), n = 2.2, gap = 0.006
 *    (radial offset of the row), cover = 1.12 (width x spacing), point = 0.35 (bottom point / rounding), lace = true
 * Returns { plates, lace }
 */
export function lamellarRow(o) {
  const count = o.count ?? 16, a0 = o.a0 ?? -170, a1 = o.a1 ?? 170, h = o.h ?? 0.04, y0 = o.y0;
  const RX = o.rx, RZ = o.rz, OX = o.ox || (() => 0), nE = o.n ?? 2.2, gap = o.gap ?? 0.006, cover = o.cover ?? 1.14;
  const step = (a1 - a0) / count, half = (step * cover) / 2, lift = o.lift ?? 0.0022;
  const out = [];
  for (let k = 0; k < count; k++) {
    const ac = a0 + step * (k + 0.5);
    out.push(plate((u, v) => {
      const a = ac + (u - 0.5) * 2 * half, y = y0 - v * h;
      // rounded / pointed bottom: corners lift
      const c = 2 * u - 1, yy = y + (v > 0.6 ? (o.point ?? 0.35) * h * (1 - Math.sqrt(Math.max(0, 1 - c * c))) * sstep(0.6, 1, v) : 0);
      const r = gap + lift * u + 0.0012 * Math.sin(Math.PI * u) + (o.flare ?? 0) * v;
      const [x, z] = se(a * DEG, RX(yy) + r, RZ(yy) + r, nE);
      return [OX(yy) + x, yy, z];
    }, { nu: 2, nv: 3, thick: o.thick ?? 0.0026, edgeR: 0.0019, edgeSegs: 2, axis: [OX(y0), 0], curv: 0.003, edgeWear: 1 }));
  }
  const res = { plates: merge(out) };
  if (o.lace !== false) {
    const pts = [], yl = y0 - h * 0.2;
    for (let i = 0; i <= 30; i++) { const a = lerp(a0 + step * 0.2, a1 - step * 0.2, i / 30) * DEG; const [x, z] = se(a, RX(yl) + gap + lift + 0.003, RZ(yl) + gap + lift + 0.003, nE); pts.push([OX(yl) + x, yl, z]); }
    res.lace = sweep(pts, circle(3), { scale: 0.0017, caps: true });
  }
  return res;
}

/**
 * Overlapping scale rows (roof-tile order: each row's scales hang over the next row's tops, rows offset by half a scale).
 * o: rows, perRow, y0, rowStep, h (scale length), a0, a1, rx(y), rz(y), ox(y), oz(y), n = 2.2, gap = 0.006, flare = 0.005 (radial
 *    lift at the scale tip), ridge = 0.0016 (central rib)
 */
export function scaleRows(o) {
  const out = [];
  const rows = o.rows ?? 3, per = o.perRow ?? 12, a0 = o.a0 ?? -60, a1 = o.a1 ?? 60, h = o.h ?? 0.05, nE = o.n ?? 2.2;
  const step = (a1 - a0) / per, half = step * 0.58, gap = o.gap ?? 0.006, fl = o.flare ?? 0.005, rib = o.ridge ?? 0.0016;
  const OZ = o.oz || (() => 0);
  for (let r = 0; r < rows; r++) {
    const y0 = o.y0 - r * (o.rowStep ?? h * 0.62);
    const off = (r % 2) * 0.5, n = per - (r % 2 ? 1 : 0);
    for (let k = 0; k < n; k++) {
      const ac = a0 + step * (k + 0.5 + off);
      out.push(plate((u, v) => {
        // shield outline: straight sides, rounded tip
        const c = 2 * u - 1, w = v < 0.45 ? 1 : Math.sqrt(Math.max(0.02, 1 - ((v - 0.45) / 0.55) ** 2));
        const a = ac + c * half * w, y = y0 - v * h;
        const rr = gap + fl * v * v + rib * Math.max(0, 1 - Math.abs(c) * 3) * sstep(0.1, 0.5, v) - 0.0015 * c * c + 0.0008 * r;
        const [x, z] = se(a * DEG, o.rx(y) + rr, o.rz(y) + rr, nE);
        return [o.ox(y) + x, y, OZ(y) + z];
      }, { nu: 3, nv: 4, thick: o.thick ?? 0.0024, edgeR: 0.0018, edgeSegs: 2, axis: [o.ox(y0), OZ(y0)], curv: 0.003, edgeWear: 1, occ: (u, v) => 0.62 + 0.38 * sstep(0.05, 0.5, v) }));
    }
  }
  return merge(out);
}

// ---- shoulders, arms, legs ------------------------------------------------------------------------------------------------------
/**
 * Crescent spaulder (deltoid frame of the R side; origin = shoulder joint): the main plate is a crescent moon laid over
 * the shoulder, widest over the deltoid and sweeping up into two pointed horns at the front and the back (its outline
 * from the side camera is a crescent), a small cap underneath, two short lames shaped to the outside of the arm, an
 * engraved band and rivets. o: { R = 0.082, nu = 22 }. Returns { crescent, cap, lames, trim, rivets, crescentS }
 */
export function crescentSpaulder(o = {}) {
  const R = o.R ?? 0.082;
  const out = {};
  const X0 = -0.112, X1 = 0.104, cy = 0.012, cz = 0.006;
  const S = (u, v) => {
    const x = lerp(X0, X1, u), e = 2 * u - 1, ae = Math.abs(e);
    const wf = 0.16 + 0.84 * (1 - Math.pow(ae, 2.4));                   // plate width (around the arm) narrows to blade-like horn tips
    const al0 = 6 - 30 * Math.pow(ae, 2.2);                             // horns lean toward the neck side as they rise
    const al = lerp(al0, al0 + 8 + 104 * wf, v);
    const r = R * (1 + 0.1 * Math.sin(Math.PI * v) * wf) * (1 - 0.18 * e * e) + 0.006 * v * v;
    const lift = 0.06 * Math.pow(ae, 2.6) * (1 - 0.35 * v);             // horns curve upward
    return [x, cy + lift + r * Math.cos(al * DEG), cz + r * Math.sin(al * DEG)];
  };
  out.crescent = plate(S, {
    nu: o.nu ?? 22, nv: 6, thick: 0.0055, edgeR: 0.0042, roll: { v1: 0.0045 }, creaseU: [0.5], ridgeWear: 0.8,
    out: (p) => [0, p[1] - cy, p[2] - cz], occ: (u, v) => 0.85 + 0.15 * sstep(0.0, 0.25, v),
  });
  out.crescentS = out.crescent.userData;
  // cap under the crescent: a low dome over the deltoid
  const cap = dome({ r: R * 0.8, h: R * 0.42, thick: 0.004, rim: 0.003, segs: 14 });
  cap.rotateX(28 * DEG);
  cap.translate(-0.004, 0.006, 0.012);
  out.cap = cap;
  // engraved band following the crescent's lower edge
  const band = [];
  for (let i = 0; i <= 24; i++) band.push([0.12 + (i / 24) * 0.76, 0.78]);
  out.trim = strip(out.crescentS, band, { width: 0.008, lift: 0.0009, bead: 0.0009, smooth: 2 });
  // lames on the outside of the upper arm, pointed toward the elbow
  out.lames = [0, 1].map((k) => hoop({
    y0: -0.052 - k * 0.032, y1: -0.09 - k * 0.032, a0: -40, a1: 220,
    rx: [[0, R * 0.58 + k * 0.002], [1, R * 0.6 + k * 0.002]], rz: [[0, R * 0.62 + k * 0.002], [1, R * 0.64 + 0.003 + k * 0.002]], oz: 0.006, n: 2.1,
    bot: (a) => -0.02 * Math.pow(Math.max(0, Math.sin(a * DEG)), 4),
    top: (a) => -0.006 * Math.pow(Math.max(0, -Math.sin(a * DEG)), 2),
    nu: 14, nv: 2, thick: 0.004, edgeR: 0.003, roll: { v1: 0.0032 }, occ: (u, v) => 0.6 + 0.4 * sstep(0.15, 0.6, v),
  }));
  out.rivets = studs(onSurface(out.crescentS, [0.22, 0.36, 0.5, 0.64, 0.78].map((u) => [u, 0.62])), { r: 0.004, h: 0.0028 });
  return out;
}

/** Slim vambrace (forearm twist frame of the R side): tapered tube, engraved ridge, crescent point flaring over the elbow. */
export function crescentVambrace(o = {}) {
  const r = o.r ?? 0.041;
  return hoop({
    y0: o.y0 ?? 0.12, y1: o.y1 ?? -0.115, closed: true,
    rx: [[0, r * 1.02], [0.3, r * 1.04], [0.85, r * 0.8], [1, r * 0.86]],
    rz: [[0, r * 1.08], [0.3, r * 1.1], [0.85, r * 0.86], [1, r * 0.92]],
    n: 2.15, nu: 16, nv: 5, thick: 0.004, edgeR: 0.003, roll: { v1: 0.0035, v0: 0.0032 },
    ridge: { at: 90, h: 0.005, w: 22 },
    // the elbow end rises into a crescent point over the point of the elbow (-X), dipping at the crook (+X)
    top: (a) => 0.042 * Math.pow(Math.max(0, -Math.cos(a * DEG)), 6) - 0.018 * Math.pow(Math.max(0, Math.cos(a * DEG)), 2),
    bot: (a) => -0.008 * Math.pow(Math.max(0, Math.sin(a * DEG)), 3),
  });
}

/** Slim greave (shin frame): closed tube, calf swell, shin ridge, a pointed top rising over the knee front. */
export function oracleGreave(o = {}) {
  const r = o.r ?? 0.052;
  return hoop({
    y0: o.y0 ?? -0.04, y1: o.y1 ?? -0.39, closed: true,
    rx: [[0, r * 1.02], [0.28, r * 1.1], [0.78, r * 0.8], [1, r * 0.86]],
    rz: [[0, r * 0.94], [0.28, r * 1.02], [0.78, r * 0.74], [1, r * 0.8]],
    ox: [[0, -0.002], [0.3, -0.01], [1, 0.002]],
    bulge: (u, v) => 0.01 * Math.pow(Math.max(0, -Math.cos((u * 360 - 180) * DEG)), 2) * Math.sin(Math.PI * clamp(v * 1.3, 0, 1)),
    n: 2.1, nu: 16, nv: 5, thick: 0.0045, edgeR: 0.0034, roll: { v0: 0.0036, v1: 0.0034 },
    ridge: { at: 0, h: 0.0075, w: 20 },
    top: (a) => 0.03 * Math.pow(Math.max(0, Math.cos(a * DEG)), 6) - 0.012 * Math.pow(Math.max(0, -Math.cos(a * DEG)), 2),
    bot: (a) => 0.014 * Math.pow(Math.max(0, Math.cos(a * DEG)), 2),
  });
}

export { sstep, lerp };
