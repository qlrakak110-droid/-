// Murim heads: no modelled faces. A head is read through what covers it: a cloth wrap with a dark eye slot, a snarling
// iron demon half-mask (귀면), a plain silver half-mask, a face wrap, a headband, conical / wide bamboo hats (죽립) with
// an optional gauze veil (면사), and hair: a combed cap, topknot (상투), bound tail, braided queue, loose mane, hairpin
// (비녀). Eyes are glow lozenges (the `eye` glow channel) behind the slots.
//
// Everything is authored in the HEAD frame: origin at the skull base (head pivot), +X the face, +Y up, head top ~ +0.22,
// eye line ~ +0.085 (metres at body scale 1; pass `scale: rig.k` for other bodies). Hair pieces use the `hair` uv set
// (u across the strands, v root -> tip, code = where the lock thins out); hats use `bamboo`, veils `gauze`.
// Tails, queues, manes and veils are skinned to hang() chains (./murim.js): declare the chains in the design.

import * as THREE from 'three';
import { fnOf } from '../shapes.js';
import { plate, sweep, lathe, band, ribbon, merge, mk, fixWinding, circle, curve, withUvw } from './geo.js';
import { hoop, se } from './armor.js';
import { hang, chainPath, chainWeights } from './murim.js';

const DEG = Math.PI / 180;
const lerp = (a, b, t) => a + (b - a) * t;
const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);
const sstep = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
const norm3 = (v) => { const l = Math.hypot(v[0], v[1], v[2]) || 1; return [v[0] / l, v[1] / l, v[2] / l]; };
const gauss = (x, s) => Math.exp(-((x / s) ** 2));

/** Skull + neck cross-section by height (head frame, body scale 1): [y, rx (front-back), rz (side), ox]. */
const SKULL = [[-0.1, 0.056, 0.056, -0.012], [-0.045, 0.062, 0.058, -0.006], [-0.01, 0.08, 0.066, 0.008], [0.03, 0.094, 0.074, 0.015], [0.075, 0.101, 0.08, 0.016], [0.12, 0.102, 0.082, 0.013], [0.165, 0.094, 0.078, 0.008], [0.2, 0.07, 0.06, 0.004], [0.218, 0.036, 0.032, 0.002]];
const SK = [1, 2, 3].map((c) => fnOf(SKULL.map((r) => [r[0], r[c]])));
function skullAt(y) { const yy = clamp(y, SKULL[0][0], SKULL[SKULL.length - 1][0]); return [yy, SK[0](yy), SK[1](yy), SK[2](yy)]; }
/** Point and outward normal on the head surface at angle a (deg, 0 = face, 90 = the fighter's right) and height y, `grow` m off it. */
export function headAt(a, y, grow = 0, k = 1) {
  const pt = (aa, yy) => { const s = skullAt(yy / k), [x, z] = se(aa * DEG, s[1] * k + grow, s[2] * k + grow, 2.15); return [s[3] * k + x, yy, z]; };
  const p = pt(a, y), pa = pt(a + 2, y), pb = pt(a - 2, y), pu = pt(a, y + 0.004), pd = pt(a, y - 0.004);
  const ta = [pa[0] - pb[0], 0, pa[2] - pb[2]], ty = [pu[0] - pd[0], pu[1] - pd[1], pu[2] - pd[2]];
  let n = norm3([ty[1] * ta[2] - ty[2] * ta[1], ty[2] * ta[0] - ty[0] * ta[2], ty[0] * ta[1] - ty[1] * ta[0]]);
  if (n[0] * Math.cos(a * DEG) + n[2] * Math.sin(a * DEG) < 0) n = [-n[0], -n[1], -n[2]];
  return { p, n };
}

/** Glowing almond eyes + their dark sockets on the head surface. o: y=0.085, a=23 (deg off centre), w=0.016, h=0.0048, slant=12, grow. */
export function eyes(o = {}) {
  const k = o.scale ?? 1, y = (o.y ?? 0.085) * k, a = o.a ?? 23, w = (o.w ?? 0.016) * k, h = (o.h ?? 0.0048) * k, grow = o.grow ?? 0.002;
  const pits = [], glow = [];
  for (const sg of [1, -1]) {
    const f = headAt(sg * a, y, grow, k), n = new THREE.Vector3(...f.n);
    const t = new THREE.Vector3(-Math.sin(sg * a * DEG), 0, Math.cos(sg * a * DEG)).multiplyScalar(sg).applyAxisAngle(n, sg * (o.slant ?? 12) * DEG * -1);
    t.addScaledVector(n, -t.dot(n)).normalize();
    const M = new THREE.Matrix4().makeBasis(t, n, new THREE.Vector3().crossVectors(n, t).negate());
    const almond = (ww, hh, lift) => { const g = lathe([[0, 0.0014 * k], [ww * 0.6, 0.0011 * k], [ww, 0]], { segs: 10 }); g.scale(1, 1, hh / ww); g.applyMatrix4(M); g.translate(f.p[0] + n.x * lift, f.p[1] + n.y * lift, f.p[2] + n.z * lift); return fixWinding(g); };
    pits.push(almond(w * 1.5, h * 2.4, 0));
    glow.push(almond(w, h, 0.0012 * k));
  }
  return { pits: merge(pits), glow: merge(glow) };
}

/**
 * Cloth-wrapped head and neck (두건): the base under every hat and mask. A closed ovoid in the weave of its look with
 * two diagonal turns of cloth over the brow and jaw, and a dark slot across the eyes.
 * @param {object} o  scale=1 (rig.k)   grow=0.004   slot=true (the eye slot band)   turns=true   yBot=-0.1
 * @returns {{ wrap, turns, slot }}  slot: put with a dark look; add eyes() for the glow
 */
export function headWrap(o = {}) {
  const k = o.scale ?? 1, grow = o.grow ?? 0.004, yb = (o.yBot ?? -0.1) * k, yt = 0.2185 * k;
  const S = (u, v) => headAt(lerp(-180, 180, u), lerp(yt, yb, Math.pow(v, 0.85)), grow + 0.0015 * Math.sin(v * 40 + u * 9), k).p;
  const wrap = plate(S, { closeU: true, nu: 28, nv: 16, thick: 0, out: (p) => [p[0] - 0.012 * k, 0, p[2]], curv: 0.002 });
  // crown cap (the plate leaves a small hole at the top)
  const cap = lathe([[0, 0.2215 * k], [0.02 * k, 0.2205 * k], [0.04 * k, 0.2175 * k]], { segs: 12 }); cap.scale(1, 1, 0.9); cap.translate(0.002 * k, 0, 0);
  const out = { wrap: merge([wrap, cap]) };
  if (o.turns !== false) {
    const tb = [];
    for (const [y0, y1, w, ph] of [[0.155, 0.118, 0.034, 0], [0.012, 0.05, 0.04, 180]]) {
      const fr = [];
      for (let i = 0; i < 32; i++) { const a = (i / 32) * 360 - 180; fr.push(headAt(a, lerp(y0, y1, 0.5 - 0.5 * Math.cos((a + ph) * DEG)) * k, grow + 0.002, k)); }
      tb.push(band(fr, { width: w * k, closed: true, side: [0, -1, 0], thick: 0.0022, crown: 0.0012 }));
    }
    out.turns = merge(tb);
  }
  if (o.slot !== false) {
    const fr = [];
    for (let i = 0; i <= 16; i++) { const a = lerp(-62, 62, i / 16); fr.push(headAt(a, 0.086 * k, grow + 0.0006, k)); }
    out.slot = band(fr, { width: 0.03 * k, side: [0, -1, 0], thick: 0.0004, crown: 0, flat: true });
  }
  return out;
}

/**
 * Face wrap (복면): cloth drawn over the nose and mouth and wound around the neck, loose folds over the chin.
 * @param {object} o  scale=1   yTop=0.07 (nose bridge)   yBot=-0.1   grow=0.009
 * @returns geometry (rigid on the head)
 */
export function faceWrap(o = {}) {
  const k = o.scale ?? 1, yt = (o.yTop ?? 0.07) * k, yb = (o.yBot ?? -0.1) * k, grow = o.grow ?? 0.009;
  const S = (u, v) => {
    const a = lerp(-180, 180, u), front = Math.max(0, Math.cos(a * DEG));
    const y = lerp(yt - 0.012 * k * (1 - front) + 0.004 * k * Math.sin(a * DEG * 3), yb, v);
    // the cloth stands off the chin and hangs in soft folds toward the throat
    const loose = 0.016 * k * Math.pow(front, 2) * Math.sin(Math.PI * clamp(v * 1.15, 0, 1)) + 0.003 * k * Math.sin(v * 26 + a * 0.12) * (0.4 + 0.6 * front);
    return headAt(a, y, grow + loose, k).p;
  };
  return plate(S, { closeU: true, nu: 28, nv: 9, thick: 0.003, edgeSegs: 2, out: (p) => [p[0] - 0.012 * k, 0, p[2]], curv: 0.002, edgeWear: 0.3 });
}

/**
 * Snarling iron demon half-mask (귀면): a heavy plate over the upper face — knotted, scowling brows over deep eye pits,
 * a broad flat nose, bulging cheekbones, the upper lip curled off a row of fangs — with two short horns at the temples.
 * @param {object} o  scale=1   stand=0.012 (off the face)   relief=1   horns=0.085 (length; 0 = none)   fangs=true
 *   nu=40, nv=22
 * @returns {{ face, pits, eyes, fangs, horns, brow }}  pits: dark sockets, eyes: glow slits (`eye` channel)
 */
export function demonMask(o = {}) {
  const k = o.scale ?? 1, st = (o.stand ?? 0.012) * k, rel = (o.relief ?? 1) * k, A = 66;
  const yT = 0.172 * k;
  const yB = (a) => (-0.014 + 0.013 * gauss(a, 13) - 0.02 * gauss(Math.abs(a) - 31, 11) + 0.03 * sstep(44, A, Math.abs(a))) * k;
  const browY = (a) => (0.098 + 0.026 * Math.min(1, Math.abs(a) / 38)) * k;
  const relief = (a, y) => {
    const aa = Math.abs(a), yy = y / k;
    let h = 0;
    h += 0.015 * gauss(yy - browY(a) / k, 0.013) * sstep(2, 9, aa) * (1 - sstep(48, 60, aa));       // scowling brows
    h += 0.01 * gauss(a, 7) * gauss(yy - 0.104, 0.014);                                           // knot between them
    h += 0.004 * Math.sin((yy - 0.125) * 300) * sstep(0.128, 0.14, yy) * (1 - sstep(34, 50, aa));  // forehead furrows
    h -= 0.011 * gauss(aa - 24, 11) * gauss(yy - 0.082, 0.012);                                   // eye pits
    h += 0.024 * gauss(a, 11) * gauss(yy - 0.036, 0.024) + 0.01 * gauss(a, 5) * sstep(0.1, 0.05, yy) * sstep(0.02, 0.04, yy); // nose
    h += 0.012 * gauss(aa - 12, 5) * gauss(yy - 0.02, 0.011);                                     // flared nostrils
    h += 0.013 * gauss(aa - 41, 13) * gauss(yy - 0.04, 0.022);                                    // cheekbones
    h += 0.009 * gauss(yy - (yB(a) / k + 0.011), 0.008) * (1 - sstep(40, 56, aa));                  // curled lip
    return h * rel;
  };
  const S = (u, v) => { const a = lerp(-A, A, u), y = lerp(yT - 0.02 * k * sstep(40, A, Math.abs(a)), yB(a), v); return headAt(a, y, st + relief(a, y), k).p; };
  const face = plate(S, { nu: o.nu ?? 40, nv: o.nv ?? 22, thick: 0.006 * k, edgeR: 0.0045 * k, roll: { v0: 0.004 * k }, out: (p) => [p[0] - 0.012 * k, 0, p[2]], curv: 0.004 });
  const out = { face };
  const fr = (a, y, lift) => { const f = headAt(a, y, st + relief(a, y) + lift, k); return f; };
  // eyes: sockets and glow slits, slanted with the scowl
  const pits = [], eyeG = [];
  for (const sg of [1, -1]) {
    const f = fr(sg * 24, 0.081 * k, 0.0004), n = new THREE.Vector3(...f.n);
    const t = new THREE.Vector3(-Math.sin(sg * 24 * DEG), 0, Math.cos(sg * 24 * DEG)).multiplyScalar(sg).applyAxisAngle(n, -sg * 0.3);
    t.addScaledVector(n, -t.dot(n)).normalize();
    const M = new THREE.Matrix4().makeBasis(t, n, new THREE.Vector3().crossVectors(n, t).negate());
    const almond = (w, h, lift) => { const g = lathe([[0, 0.0015 * k], [w * 0.6, 0.0012 * k], [w, 0]], { segs: 10 }); g.scale(1, 1, h / w); g.applyMatrix4(M); g.translate(f.p[0] + n.x * lift, f.p[1] + n.y * lift, f.p[2] + n.z * lift); return fixWinding(g); };
    // (the plate's facets bridge the eye pit ~2 mm above the sculpt: the lozenges sit clear of them)
    pits.push(almond(0.021 * k, 0.0095 * k, 0.0028 * k)); eyeG.push(almond(0.0135 * k, 0.0038 * k, 0.0042 * k));
  }
  out.pits = merge(pits); out.eyes = merge(eyeG);
  if (o.fangs !== false) {
    const fg = [];
    for (const [a, len, r] of [[19, 0.03, 0.0068], [-19, 0.03, 0.0068], [9, 0.014, 0.0044], [-9, 0.014, 0.0044], [3, 0.011, 0.0038], [-3, 0.011, 0.0038], [27, 0.012, 0.004], [-27, 0.012, 0.004]]) {
      const f = fr(a, yB(a) + 0.004 * k, -0.002 * k), dn = norm3([f.n[0] * 0.35, -1, f.n[2] * 0.35 + Math.sign(a) * (Math.abs(a) > 15 ? 0.12 : 0)]);
      const g = lathe([[r * k, 0], [r * 0.82 * k, len * 0.45 * k], [r * 0.32 * k, len * 0.9 * k], [0, len * k]], { segs: 6 });
      g.applyQuaternion(new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, 1, 0), new THREE.Vector3(...dn)));
      g.translate(f.p[0], f.p[1], f.p[2]);
      fg.push(g);
    }
    out.fangs = merge(fg);
  }
  const hl = (o.horns ?? 0.085) * k;
  if (hl > 0) {
    const hs = [];
    for (const sg of [1, -1]) {
      const f = fr(sg * 47, 0.15 * k, -0.004 * k), n = f.n;
      const pts = curve([f.p, [f.p[0] + n[0] * hl * 0.3 - hl * 0.05, f.p[1] + hl * 0.36, f.p[2] + n[2] * hl * 0.34], [f.p[0] + n[0] * hl * 0.34 - hl * 0.3, f.p[1] + hl * 0.82, f.p[2] + n[2] * hl * 0.42], [f.p[0] - hl * 0.62, f.p[1] + hl * 1.08, f.p[2] + n[2] * hl * 0.3]], 9);
      hs.push(sweep(pts, [[1, 0], [0.5, 0.8], [-0.5, 0.8], [-1, 0], [-0.5, -0.8], [0.5, -0.8]], { scale: (t) => 0.0145 * k * (1 - 0.86 * t), hard: [0, 3], caps: true, up: [0, 1, 0] }));
    }
    out.horns = merge(hs);
  }
  return out;
}

/**
 * Plain silver half-mask: a smooth plate from the brow to the cheeks with a fine nose guard, its lower edge sweeping up
 * to the temples; long slanted eye slots.
 * @param {object} o  scale=1   stand=0.008   nose=0.034 (nose guard drop)   nu=32, nv=12
 * @returns {{ face, pits, eyes, ridge }}
 */
export function silverMask(o = {}) {
  const k = o.scale ?? 1, st = (o.stand ?? 0.008) * k, A = 72, yT = 0.166 * k;
  const yB = (a) => (0.03 + 0.062 * Math.pow(Math.abs(a) / A, 1.6) - (o.nose ?? 0.034) * gauss(a, 9)) * k;
  const relief = (a, y) => (0.006 * gauss(a, 8) * sstep(0.12, 0.06, y / k) + 0.004 * gauss(y / k - 0.106, 0.012) * sstep(6, 16, Math.abs(a)) * (1 - sstep(46, 60, Math.abs(a))) - 0.004 * gauss(Math.abs(a) - 25, 12) * gauss(y / k - 0.084, 0.011)) * k;
  const S = (u, v) => { const a = lerp(-A, A, u), y = lerp(yT - 0.03 * k * Math.pow(Math.abs(a) / A, 2), yB(a), v); return headAt(a, y, st + relief(a, y), k).p; };
  const face = plate(S, { nu: o.nu ?? 32, nv: o.nv ?? 12, thick: 0.004 * k, edgeR: 0.003 * k, creaseU: [0.5], ridgeWear: 0.4, out: (p) => [p[0] - 0.012 * k, 0, p[2]], curv: 0.004 });
  const out = { face };
  const pits = [], eyeG = [];
  for (const sg of [1, -1]) {
    const f = headAt(sg * 25, 0.083 * k, st + relief(sg * 25, 0.083 * k) + 0.0004, k), n = new THREE.Vector3(...f.n);
    const t = new THREE.Vector3(-Math.sin(sg * 25 * DEG), 0, Math.cos(sg * 25 * DEG)).multiplyScalar(sg).applyAxisAngle(n, sg * 0.24);
    t.addScaledVector(n, -t.dot(n)).normalize();
    const M = new THREE.Matrix4().makeBasis(t, n, new THREE.Vector3().crossVectors(n, t).negate());
    const almond = (w, h, lift) => { const g = lathe([[0, 0.0012 * k], [w * 0.6, 0.001 * k], [w, 0]], { segs: 10 }); g.scale(1, 1, h / w); g.applyMatrix4(M); g.translate(f.p[0] + n.x * lift, f.p[1] + n.y * lift, f.p[2] + n.z * lift); return fixWinding(g); };
    pits.push(almond(0.022 * k, 0.0056 * k, 0.0012 * k)); eyeG.push(almond(0.016 * k, 0.0024 * k, 0.0022 * k));
  }
  out.pits = merge(pits); out.eyes = merge(eyeG);
  // engraved brow line: a thin band under the top edge
  const fr = [];
  for (let i = 0; i <= 24; i++) { const a = lerp(-A + 6, A - 6, i / 24), y = yT - 0.03 * k * Math.pow(Math.abs(a) / A, 2) - 0.012 * k; fr.push(headAt(a, y, st + relief(a, y) + 0.0002, k)); }
  out.ridge = band(fr, { width: 0.007 * k, side: [0, -1, 0], thick: 0.0008, crown: 0.0008, lift: 0.0002 });
  return out;
}

/**
 * Headband (머리띠) around the brow, tied behind: a band with a knot seat; hang its ends with sashTail() on a hang()
 * chain rooted at `knotAt`.
 * @param {object} o  scale=1   y=0.14 (front), yBack=0.115   w=0.03   grow=0.006   motif=-1 (brocade code; -1 = plain: no uv glow)
 * @returns {{ band, knotAt: [x,y,z], knotN: [x,y,z] }}
 */
export function headband(o = {}) {
  const k = o.scale ?? 1, yF = (o.y ?? 0.14) * k, yBk = (o.yBack ?? 0.115) * k, grow = o.grow ?? 0.006, fr = [];
  for (let i = 0; i < 36; i++) { const a = (i / 36) * 360 - 180; fr.push(headAt(a, lerp(yBk, yF, 0.5 + 0.5 * Math.cos(a * DEG)), grow, k)); }
  const kf = headAt(o.knotA ?? 168, yBk, grow + 0.004, k);
  return { band: band(fr, { width: (o.w ?? 0.03) * k, closed: true, side: [0, -1, 0], thick: 0.0028, crown: 0.0012, code: Math.max(0, o.motif ?? 0) }), knotAt: kf.p, knotN: kf.n };
}

/**
 * Bamboo hat (죽립 / 삿갓): a woven cone (or a wide shallow brim with a low crown) seen from above and from below, with a
 * rolled rim, a finial and chin cords. Rigid on the head; tilt it with put(..., { rot: [0, 0, -8] }).
 * @param {object} o  scale=1   R=0.3 (brim radius)   h=0.17 (apex above the brim)   y=0.15 (brim height in the head frame)
 *   bell=0.85 (profile exponent: 1 straight cone, < 1 swelling, > 1 flaring)   crown=0 (0..1: share of the radius
 *   taken by a low rounded crown, for wide flat hats)   dip=0 (m the brim droops at its edge)   code=0 (glow through
 *   the plait)   tiles=[6, 1 / 0.04] (uv tiles around, per metre of slope)   cords=true   nu=36, nv=7
 * @returns {{ shell, knob, cords, brimR, brimY, apexY }}
 */
export function bambooHat(o = {}) {
  const k = o.scale ?? 1, R = (o.R ?? 0.3) * k, h = (o.h ?? 0.17) * k, yb = (o.y ?? 0.15) * k, bell = o.bell ?? 0.85, cr = o.crown ?? 0, dip = (o.dip ?? 0) * k;
  const tiles = o.tiles || [6, 1 / 0.04], code = o.code ?? 0;
  const prof = (s) => {
    // wide hat: a low rounded crown over the skull flowing into a broad brim; otherwise a cone with a `bell` profile
    if (cr > 0) return s < cr ? [R * s, yb + h * Math.pow(Math.cos((s / cr) * Math.PI / 2), 0.8)] : [R * s, yb - dip * ((s - cr) / (1 - cr)) ** 2];
    return [R * s, yb + h * (1 - Math.pow(s, bell)) - dip * s * s];
  };
  const slope = Math.hypot(R, h);
  const S = (u, v) => { const s = lerp(0.035, 1, v), a = u * Math.PI * 2, [r, y] = prof(s); return [Math.cos(a) * r, y, Math.sin(a) * r]; };
  const shell = plate(S, {
    closeU: true, nu: o.nu ?? 36, nv: o.nv ?? 7, thick: 0.005 * k, inner: true, innerCav: 0.5, edge: { v0: 'none' }, roll: { v1: 0.0055 * k }, rollSegs: 5,
    out: (p) => [p[0], 0.25 * Math.hypot(p[0], p[2]) + 0.02, p[2]], curv: 0.003, edgeWear: 0.4,
    uvw: (u, v) => [u * tiles[0], v * slope * tiles[1], code],
  });
  const ya = prof(0.035)[1];
  const knob = lathe([[0.0, ya + 0.03 * k], [0.007 * k, ya + 0.027 * k], [0.01 * k, ya + 0.018 * k], [0.006 * k, ya + 0.011 * k], [0.013 * k, ya + 0.006 * k], [0.02 * k, ya - 0.002 * k], [0.022 * k, ya - 0.008 * k]], { segs: 10 });
  const out = { shell, knob, brimR: R, brimY: prof(1)[1], apexY: ya };
  if (o.cords !== false) {
    const cs = [];
    for (const sg of [1, -1]) {
      const [r1, y1] = prof(0.42);
      cs.push(sweep(curve([[0.0, y1 - 0.004, sg * r1], [0.02 * k, 0.07 * k, sg * 0.086 * k], [0.04 * k, 0.0, sg * 0.062 * k], [0.05 * k, -0.035 * k, sg * 0.012 * k]], 10), circle(5), { scale: 0.0024 * k, caps: true }));
    }
    cs.push(lathe([[0, 0.006 * k], [0.005 * k, 0.004 * k], [0.006 * k, 0], [0.004 * k, -0.005 * k], [0, -0.007 * k]], { segs: 6 }).translate(0.05 * k, -0.04 * k, 0));
    out.cords = merge(cs);
  }
  return out;
}

/**
 * Spring chains of a veil hanging from a hat brim: `chains` hang() chains spaced around the head.
 * @param {string} name  bone prefix   @param {object} o  R=0.27 (ring radius)   y=0.15 (ring height, head frame)   len=0.26
 *   chains=6   n=2   a0=-180, a1=180 (deg; a parted veil: e.g. 40 .. 320)   tilt=0 (deg, the hat's forward tilt)   + hang() spring options
 */
export function veilRig(name, o = {}) {
  const R = o.R ?? 0.27, y = o.y ?? 0.15, len = o.len ?? 0.26, N = o.chains ?? 6, a0 = o.a0 ?? -180, a1 = o.a1 ?? 180, closed = a1 - a0 >= 360;
  const tilt = (o.tilt ?? 0) * DEG, chains = [];
  for (let i = 0; i < N; i++) {
    const a = lerp(a0, a1, closed ? i / N : i / (N - 1)) * DEG, x = Math.cos(a) * R, z = Math.sin(a) * R;
    // the ring tilts with the hat (about Z, forward down for a negative tilt)
    chains.push(hang(`${name}${String.fromCharCode(97 + i)}`, 'head', [x * Math.cos(tilt) - 0 * Math.sin(tilt), y + x * Math.sin(tilt), z],
      { n: o.n ?? 2, len, stiffness: o.stiffness ?? 16, damping: o.damping ?? 3.2, gravity: o.gravity ?? 0.7, limit: o.limit ?? 55, radius: o.radius ?? 0.012, collide: o.collide ?? false, inertia: o.inertia ?? 0.8 }));
  }
  return { name, chains, bones: chains.flatMap((c) => c.bones), springs: chains.flatMap((c) => c.springs), R, y, len, a0, a1, closed, tilt: o.tilt ?? 0 };
}

/**
 * Gauze veil (면사) on a veilRig(): a sheer curtain from the hat brim with soft pleats, skinned between the chains.
 * Use the `gauze` look on a cut-out slot.
 * @param {object} kit  @param {object} V  veilRig()
 * @param {object} o  opacity=0.5 (uv code)   pleat=0.012   nu=36, nv=6   flare=0.02 (radius gained at the hem)   hem: fn(u) -> length factor
 * @returns geometry (bind space) with `uvw` and skin weights
 */
export function veil(kit, V, o = {}) {
  const hb = kit.bonePos('head'), nu = o.nu ?? 36, nv = o.nv ?? 6, op = o.opacity ?? 0.5, pl = o.pleat ?? 0.012, fl = o.flare ?? 0.02, hem = o.hem || (() => 1);
  const N = V.chains.length, tl = V.tilt * DEG;
  const pos = [], nor = [], idx = [], uvw = [], W = [];
  for (let j = 0; j <= nv; j++) for (let i = 0; i <= nu; i++) {
    const u = i / nu, v = j / nv, a = lerp(V.a0, V.a1, u) * DEG;
    const r = V.R + fl * v + pl * Math.sin(u * Math.PI * 2 * 9 + 0.5) * (0.2 + 0.8 * v);
    const x = Math.cos(a) * r, z = Math.sin(a) * r, y = V.y + Math.cos(a) * V.R * Math.sin(tl) - V.len * hem(u) * v;
    pos.push(hb[0] + x, hb[1] + y, hb[2] + z); nor.push(Math.cos(a), 0, Math.sin(a));
    uvw.push((a * V.R) / 0.02, (V.len * v) / 0.02, op);
    // two nearest chains by angle, each with its weights down the chain
    const f = V.closed ? (u * N) % N : u * (N - 1), c0 = Math.floor(f) % N, c1 = V.closed ? (c0 + 1) % N : Math.min(N - 1, c0 + 1), t = f - Math.floor(f);
    const w = [];
    for (const [c, k] of [[c0, 1 - t], [c1, t]]) if (k > 1e-3) for (const [b, ww] of chainWeights(V.chains[c], v, 0.08)) w.push([b, ww * k]);
    // merge duplicate bones (the head on the pinned rows)
    const m = new Map(); for (const [b, ww] of w) m.set(b, (m.get(b) || 0) + ww);
    W.push([...m.entries()]);
  }
  for (let j = 0; j < nv; j++) for (let i = 0; i < nu; i++) { const a = j * (nu + 1) + i, b = a + 1, c = a + nu + 1, d = c + 1; idx.push(a, c, b, b, c, d); }
  const g = fixWinding(mk(pos, nor, idx, null, uvw));
  g.userData.W = W;
  return g;
}

// ---- hair --------------------------------------------------------------------------------------------------------------------

/**
 * Combed hair cap: hair drawn back from the hairline to a knot point (the topknot or the root of a tail). `hair` uv set:
 * strands run from the hairline to the knot.
 * @param {object} o  scale=1   knot=[-0.035, 0.222, 0] (head frame)   grow=0.009   front=0.165 (hairline at the brow),
 *   side=0.085, nape=0.0 (hairline heights)   strands=7 (uv tiles around the knot)   nu=30, nv=10
 * @returns geometry with `uvw`
 */
export function hairCap(o = {}) {
  const k = o.scale ?? 1, K = (o.knot || [-0.035, 0.222, 0]).map((x) => x * k), grow = o.grow ?? 0.009, st = o.strands ?? 7;
  const line = (a) => { const c = Math.cos(a * DEG), f = (o.front ?? 0.165), s = (o.side ?? 0.085), nb = (o.nape ?? 0.0); return (c > 0 ? lerp(s, f, Math.pow(c, 0.7)) : lerp(s, nb, Math.pow(-c, 0.8))) * k; };
  const yt = 0.216 * k;
  const S = (u, v) => { const a = lerp(-180, 180, u); return headAt(a, lerp(yt, line(a), v), grow + 0.002 * Math.sin(u * 40) * v, k).p; };
  const g = plate(S, { closeU: true, nu: o.nu ?? 30, nv: o.nv ?? 10, thick: 0.004, edge: { v0: 'none' }, edgeSegs: 2, out: (p) => [p[0] - 0.012 * k, 0.1, p[2]], curv: 0.002, edgeWear: 0.2 });
  const cap = lathe([[0, 0.2235 * k], [0.022 * k, 0.222 * k], [0.046 * k, 0.2175 * k]], { segs: 12 }); cap.scale(1, 1, 0.9); cap.translate(0.004 * k, 0.004, 0);
  const m = merge([g, cap]);
  // strands radiate from the knot: u = angle around it, v = 1 at the knot .. 0 at the hairline
  return withUvw(m, (p) => { const dx = p[0] - K[0], dz = p[2] - K[2], dy = p[1] - K[1], d = Math.hypot(dx, dy, dz); return [(Math.atan2(dz, dx) / (2 * Math.PI)) * st, clamp(1 - d / (0.26 * k), 0, 1), 0]; });
}

/**
 * Topknot (상투): a wound bun on a bound stem, with an optional pin (비녀) through it.
 * @param {object} o  scale=1   at=[-0.035, 0.224, 0]   r=0.03   h=0.05   lean=-12 (deg, back)   pin=0.11 (length; 0 = none)
 * @returns {{ bun, tie, pin }}  bun has `uvw` (hair); tie = cord band; pin = rod with finials
 */
export function topknot(o = {}) {
  const k = o.scale ?? 1, at = (o.at || [-0.035, 0.224, 0]).map((x) => x * k), r = (o.r ?? 0.03) * k, h = (o.h ?? 0.05) * k;
  const prof = [[r * 0.5, -0.006 * k], [r * 0.56, h * 0.16], [r * 0.52, h * 0.3], [r * 0.9, h * 0.42], [r, h * 0.62], [r * 0.86, h * 0.84], [r * 0.5, h * 0.98], [0, h * 1.02]];
  const bun = lathe(prof, { segs: 12 });
  withUvw(bun, (p) => [(Math.atan2(p[2], p[0]) / (2 * Math.PI)) * 3 + p[1] / h * 1.4, clamp(p[1] / h, 0, 1) * 0.6 + 0.2, 0]);
  const fr = [];
  for (let i = 0; i < 14; i++) { const a = (i / 14) * Math.PI * 2; fr.push({ p: [Math.cos(a) * r * 0.57, h * 0.22, Math.sin(a) * r * 0.57], n: [Math.cos(a), 0, Math.sin(a)] }); }
  const tie = band(fr, { width: 0.014 * k, closed: true, side: [0, -1, 0], thick: 0.002, crown: 0.001 });
  const q = new THREE.Quaternion().setFromEuler(new THREE.Euler(0, 0, (o.lean ?? -12) * -DEG));
  const fin = (g) => { g.applyQuaternion(q); g.translate(at[0], at[1], at[2]); return g; };
  const out = { bun: fin(bun), tie: fin(tie) };
  const pl = (o.pin ?? 0.11) * k;
  if (pl > 0) {
    const pin = lathe([[0, -pl / 2 - 0.004 * k], [0.0026 * k, -pl / 2], [0.0022 * k, pl * 0.3], [0.004 * k, pl * 0.36], [0.006 * k, pl * 0.42], [0.0052 * k, pl * 0.47], [0.002 * k, pl * 0.5], [0, pl * 0.52]], { segs: 7 });
    pin.rotateX(90 * DEG); pin.translate(0, h * 0.24, 0);
    out.pin = fin(pin);
  }
  return out;
}

/** Standalone hairpin (비녀) along +Z through the origin. o: len=0.13, r=0.0026. */
export function hairpin(o = {}) {
  const pl = o.len ?? 0.13, r = o.r ?? 0.0026;
  const pin = lathe([[0, -pl / 2 - 0.004], [r, -pl / 2], [r * 0.85, pl * 0.3], [r * 1.5, pl * 0.36], [r * 2.4, pl * 0.42], [r * 2, pl * 0.47], [r * 0.8, pl * 0.5], [0, pl * 0.52]], { segs: 7 });
  pin.rotateX(90 * DEG);
  return pin;
}

/** Smooth points along a hang() chain's bind path (m samples). */
function chainCurve(kit, H, m) {
  const c = new THREE.CatmullRomCurve3(chainPath(kit, H).map((p) => new THREE.Vector3(...p)), false, 'centripetal');
  return c.getPoints(m);
}

/**
 * Bound tail of hair (ponytail / long tail) on a hang() chain: three overlapping ribbons of strands around the chain,
 * thick at the binding and thinning to a wispy end, plus the binding itself. `hair` uv set on a cut-out slot.
 * @param {object} kit  @param {object} H  hang() chain (rooted on the head at the binding)
 * @param {object} o  width=0.05 (at the root)   tip=0.35 (width share at the end)   thin=0.6 (where the lock thins out)
 *   ribbons=3   segs=4 (per bone)   swell=0.25 (the tail fattens just below the binding)   back=[-1, 0, 0] (facing)
 * @returns {{ tail, tie }}  tail: skinned (weightsOf(tail.userData.W), bind space); tie: skinned band at the root
 */
export function hairTail(kit, H, o = {}) {
  const m = H.n * (o.segs ?? 4), pts = chainCurve(kit, H, m), w0 = o.width ?? 0.05, tip = o.tip ?? 0.35, nR = o.ribbons ?? 3, sw = o.swell ?? 0.25;
  const bk = new THREE.Vector3(...(o.back || [-1, 0, 0])).normalize();
  const tg0 = new THREE.Vector3().subVectors(pts[1], pts[0]).normalize();
  const sd = new THREE.Vector3().crossVectors(tg0, bk).normalize();
  const parts = [];
  for (let r = 0; r < nR; r++) {
    const a = ((r - (nR - 1) / 2) / Math.max(1, nR)) * Math.PI * 1.25, nrm = bk.clone().multiplyScalar(Math.cos(a)).addScaledVector(sd, Math.sin(a));
    const off = pts.map((p, i) => { const t = i / m, rad = w0 * 0.2 * (1 + sw * Math.sin(Math.min(1, t * 3) * Math.PI)) * (1 - 0.6 * t); return p.clone().addScaledVector(nrm, rad); });
    parts.push(ribbon(off, { width: (t) => w0 * (1 + sw * Math.sin(Math.min(1, t * 3) * Math.PI)) * lerp(1, tip, t), normal: [nrm.x, nrm.y, nrm.z], camber: 0.24, nu: 3, u0: r * 0.9, du: w0 * 14, code: o.thin ?? 0.6, weights: (t) => chainWeights(H, t, 0.05) }));
  }
  const tail = merge(parts);
  const fr = [], c = pts[0].clone().addScaledVector(tg0, 0.012);
  const rr = w0 * 0.3;
  for (let i = 0; i < 10; i++) { const a = (i / 10) * Math.PI * 2, n = bk.clone().multiplyScalar(Math.cos(a)).addScaledVector(sd, Math.sin(a)); fr.push({ p: c.clone().addScaledVector(n, rr), n, w: [[H.names[0], 1]] }); }
  const tie = band(fr, { width: 0.022, closed: true, side: [tg0.x, tg0.y, tg0.z], thick: 0.0025, crown: 0.001 });
  return { tail, tie };
}

/**
 * Braided queue (땋은 머리) on a hang() chain: overlapping chevron locks that read as a three-strand plait, ending in a
 * cord binding and a loose brush.
 * @param {object} kit  @param {object} H  hang() chain
 * @param {object} o  width=0.034   pitch=0.04 (length of one crossing)   taper=0.55 (width share at the end)   brush=0.07
 *   back=[-1, 0, 0]
 * @returns {{ braid, tie }}  skinned (bind space)
 */
export function queue(kit, H, o = {}) {
  const w0 = o.width ?? 0.034, pitch = o.pitch ?? 0.04, taper = o.taper ?? 0.55, brush = o.brush ?? 0.07;
  const L = H.len, nC = Math.max(2, Math.round((L - brush) / (pitch * 0.5)));
  const curveP = new THREE.CatmullRomCurve3(chainPath(kit, H).map((p) => new THREE.Vector3(...p)), false, 'centripetal');
  const bk = new THREE.Vector3(...(o.back || [-1, 0, 0])).normalize();
  const at = (s) => { const u = clamp(s / L, 0, 1), p = curveP.getPoint(u), t = curveP.getTangent(clamp(u, 0.001, 0.999)).normalize(); const n = bk.clone().addScaledVector(t, -t.dot(bk)).normalize(); return { p, t, n, sd: new THREE.Vector3().crossVectors(t, n) }; };
  const parts = [];
  for (let c = 0; c < nC; c++) {
    const s0 = c * pitch * 0.5, sg = c & 1 ? 1 : -1, w = w0 * lerp(1, taper, s0 / L), pts = [];
    for (let i = 0; i <= 4; i++) {
      const t = i / 4, f = at(s0 + t * pitch * 1.15);
      // each lock crosses the plait from one edge to the other, rising over the middle
      pts.push(f.p.clone().addScaledVector(f.sd, sg * w * (0.42 - 0.84 * t)).addScaledVector(f.n, w * 0.3 * Math.sin(t * Math.PI) + 0.003));
    }
    const f0 = at(s0 + pitch * 0.5);
    parts.push(ribbon(pts, { width: (t) => w * (0.5 + 0.34 * Math.sin(t * Math.PI)), normal: [f0.n.x, f0.n.y, f0.n.z], camber: 0.34, nu: 2, u0: c * 0.53, du: 0.5, code: 0, weights: (t) => chainWeights(H, (s0 + t * pitch * 1.15) / L, 0.04) }));
  }
  // loose brush below the binding
  const fb = at(L - brush), wb = w0 * taper;
  for (let r = 0; r < 3; r++) {
    const a = (r - 1) * 0.9, n = fb.n.clone().multiplyScalar(Math.cos(a)).addScaledVector(fb.sd, Math.sin(a));
    parts.push(ribbon([fb.p.clone().addScaledVector(n, wb * 0.2), at(L - brush * 0.5).p.clone().addScaledVector(n, wb * 0.34), at(L).p.clone().addScaledVector(n, wb * 0.4)], { width: (t) => wb * (1.1 - 0.3 * t), normal: [n.x, n.y, n.z], camber: 0.22, nu: 2, u0: r * 0.7, du: 0.5, code: 0.3, weights: () => [[H.names[H.n - 1], 1]] }));
  }
  const fr = [];
  for (let i = 0; i < 8; i++) { const a = (i / 8) * Math.PI * 2, n = fb.n.clone().multiplyScalar(Math.cos(a)).addScaledVector(fb.sd, Math.sin(a)); fr.push({ p: fb.p.clone().addScaledVector(n, wb * 0.36), n, w: [[H.names[H.n - 1], 1]] }); }
  return { braid: merge(parts), tie: band(fr, { width: 0.016, closed: true, side: [fb.t.x, fb.t.y, fb.t.z], thick: 0.0022, crown: 0.001 }) };
}

/**
 * Loose mane: locks of hair falling from the back of the head over the neck and shoulders, shared between a few hang()
 * chains (each lock follows the nearest chain). `hair` uv set on a cut-out slot.
 * @param {object} kit  @param {object[]} chains  hang() chains rooted on the head (e.g. left, back, right)
 * @param {object} o  scale=1   locks=9   a0=95, a1=265 (deg around the head where the locks grow)   y0=0.19, y1=0.1 (root
 *   heights: crown .. sides)   width=0.045   spread=0.06 (how far the ends fan out)   thin=0.5   lift=0.02   layers=2
 * @returns geometry (bind space) with `uvw` and skin weights
 */
export function mane(kit, chains, o = {}) {
  const k = o.scale ?? 1, hb = kit.bonePos('head'), n = o.locks ?? 9, a0 = o.a0 ?? 95, a1 = o.a1 ?? 265, layers = o.layers ?? 2;
  const w0 = (o.width ?? 0.045) * k, spread = (o.spread ?? 0.06) * k, lift = (o.lift ?? 0.02) * k;
  const info = chains.map((H) => { const P = chainCurve(kit, H, 8), r = P[0]; return { H, P, ang: Math.atan2(r.z - hb[2], r.x - hb[0]) / DEG }; });
  const parts = [];
  for (let L = 0; L < layers; L++) for (let i = 0; i < n; i++) {
    const f = n > 1 ? (i + 0.5 * L) / (n - 1 + 0.5 * (layers - 1)) : 0.5, a = lerp(a0, a1, f);
    const yr = lerp(o.y0 ?? 0.19, o.y1 ?? 0.1, Math.pow(Math.abs(2 * f - 1), 1.3)) * k - 0.03 * k * L;
    const root = headAt(a, yr, 0.008 + 0.004 * L, k);
    const rp = new THREE.Vector3(hb[0] + root.p[0], hb[1] + root.p[1], hb[2] + root.p[2]), rn = new THREE.Vector3(...root.n);
    // nearest chain by angle
    let best = info[0], bd = 1e9;
    for (const c of info) { const d = Math.abs(((a - c.ang + 540) % 360) - 180); if (d < bd) { bd = d; best = c; } }
    const lat = new THREE.Vector3(-Math.sin(a * DEG), 0, Math.cos(a * DEG)), side = ((a - best.ang + 540) % 360) - 180;
    const pts = [];
    for (let j = 0; j <= 8; j++) {
      const t = j / 8, cp = best.P[j], blend = sstep(0, 0.45, t);
      const p = rp.clone().lerp(cp, blend);
      p.addScaledVector(rn, lift * Math.sin(Math.min(1, t * 2.2) * Math.PI) * (1 - blend * 0.5) + 0.006 * L);
      p.addScaledVector(lat, (side / 60) * spread * t * (0.6 + 0.4 * Math.sin(i * 2.3)));
      p.y -= 0.02 * k * t * Math.sin(i * 1.7 + L);
      pts.push(p);
    }
    parts.push(ribbon(pts, { width: (t) => w0 * (1 - 0.25 * L) * (1 - 0.45 * t), normal: (t) => { const v = rn.clone().lerp(new THREE.Vector3(rn.x, 0.15, rn.z).normalize(), t); return [v.x, v.y, v.z]; }, camber: 0.2, nu: 2, u0: i * 0.61 + L * 0.37, du: 0.55, code: o.thin ?? 0.5,
      weights: (t) => { const hk = 1 - sstep(0.04, 0.3, t), cw = chainWeights(best.H, Math.max(0, (t - 0.12) / 0.88), 0).map(([b, w]) => [b, w * (1 - hk)]); return hk > 0.001 ? [['head', hk], ...cw] : cw; },
    }));
  }
  return merge(parts);
}
