// VORN-specific kit pieces (src/char/kit is shared and read-only for fighter designs; everything here is built on its
// public geometry core). Frames follow the kit convention: a bone's zero-pose frame, +X forward, +Y up, +Z the fighter's
// right / camera side; right-side pieces are mirrored for the left with mirror() / putPair().
//
//   stormHelm(o)        close helm with a T-visor (gold-lipped eye slit + vertical breath slot over a glowing recess),
//                       V-fronted cheek plates with glowing breaths, chin plate, swept horns and fanned storm-feather wings
//   stormHornTips(o)    horn tip positions (sockets)
//   stormFins(o)        jagged lightning-bolt fins standing on a pauldron (silhouette spikes)
//   feather(o), blade2d(outline, o)   bevelled flat blades (+ edge mask for gold edging by vertex index)
//   arcPath(...)        deterministic zig-zag lightning path in a plate's (u, v) space (+ forks) -> strips via arcRune()
//   arcRune(plate, ...) glowing arc-rune inlay (strip) following an arcPath on a plate surface
//   rim(plate, side, r) rolled gold bead along one edge of a plate (over the plate's own bead / roll)
//   combAlong(plate, uv, o)   forged comb standing on a plate surface
//   gorget, rerebrace, vambrace, cuisse, greave, couterLames, poleynLames   shared shapes at VORN's segment budget
//   mailSkirt(o)        split cavalry hauberk skirt half (hips frame, R side), for putSkinned (hips -> thigh)
//   spur(o)             rowel spur on the heel (foot frame)
//   crackle(t, seed)    deterministic arc flicker (~0.82 .. ~2.0) used by the design's glow driver
//
// Every builder returns indexed geometry with the kit attributes (`cav`), ready for put() / putPair().

import * as THREE from 'three';
import { plate, sweep, extrude, strip, merge, circle, curve, lathe, studs, onSurface, fixWinding } from '../../char/kit/geo.js';
import { se, hoop } from '../../char/kit/armor.js';

const DEG = Math.PI / 180;
const lerp = (a, b, t) => a + (b - a) * t;
const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);
const sstep = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
/** Deterministic hash -> [0, 1). */
const hash1 = (n) => { const s = Math.sin(n * 127.1 + 311.7) * 43758.5453; return s - Math.floor(s); };

// ---- arc runes ----------------------------------------------------------------------------------------------------------

/**
 * Zig-zag lightning path in (u, v) parameter space from (u0, v0) to (u1, v1).
 * o: { segs = 8, amp = 0.03 (perpendicular jag, uv units), seed = 1, jitter = 0.35 (segment length variation) }
 * Returns [[u, v], ...] (segs + 1 points; end points exact).
 */
export function arcPath(u0, v0, u1, v1, o = {}) {
  const n = o.segs ?? 8, amp = o.amp ?? 0.03, seed = o.seed ?? 1, jit = o.jitter ?? 0.35;
  const du = u1 - u0, dv = v1 - v0, L = Math.hypot(du, dv) || 1;
  const pu = -dv / L, pv = du / L;
  // uneven stations along the path
  const st = [0];
  for (let i = 1; i < n; i++) st.push(i / n + (hash1(seed * 13 + i) - 0.5) * jit / n);
  st.push(1);
  return st.map((t, i) => {
    const edge = i === 0 || i === n;
    const side = i % 2 ? 1 : -1;
    const a = edge ? 0 : side * amp * (0.45 + 0.55 * hash1(seed * 7 + i * 3.1));
    return [u0 + du * t + pu * a, v0 + dv * t + pv * a];
  });
}

/**
 * Glowing arc-rune inlay on a plate: a main zig-zag bolt plus short forks branching off its corners.
 * o: arcPath options + { width = 0.0032, forks = [[index, angle (deg, relative), length (uv)], ...], lift }
 */
export function arcRune(plateGeo, u0, v0, u1, v1, o = {}) {
  const S = plateGeo.userData;
  const main = arcPath(u0, v0, u1, v1, o);
  const w = o.width ?? 0.0032;
  const parts = [strip(S, main, { width: w, lift: o.lift ?? 0.0007, bead: 0.0005, smooth: 2 })];
  for (const [k, ang, len] of o.forks || []) {
    const a = main[Math.max(1, Math.min(main.length - 2, k))], b = main[Math.min(main.length - 1, k + 1)];
    const d = Math.atan2(b[1] - a[1], b[0] - a[0]) + ang * DEG;
    const end = [a[0] + Math.cos(d) * len, a[1] + Math.sin(d) * len];
    const fk = arcPath(a[0], a[1], end[0], end[1], { segs: 3, amp: (o.amp ?? 0.03) * 0.6, seed: (o.seed ?? 1) * 5 + k });
    parts.push(strip(S, fk, { width: w * 0.7, lift: o.lift ?? 0.0007, bead: 0.0004, smooth: 2 }));
  }
  return merge(parts);
}

// ---- trim ---------------------------------------------------------------------------------------------------------------

/** Rim bead section: angles (deg) of a rounded crown around the plate normal (open underneath, tucked into the plate). */
const BEAD = [-108, -60, -20, 20, 60, 108].map((d) => [Math.cos(d * DEG), Math.sin(d * DEG)]);

/**
 * Rolled trim bead along one edge of a plate (sits over the plate's own bead / roll: a gold rim on a steel plate).
 * Rounded crown section framed by the plate normal at every sample (no twist drift), 10 triangles per sample.
 * side: 'v0' | 'v1' | 'u0' | 'u1'; r: bead radius; o: { n = 32 samples, from = 0, to = 1 (edge range), closed,
 * lift (outward along the plate normal; default r * 0.2 - thick / 2), out (past the edge; default r * 0.3), thick }
 */
export function rim(plateGeo, side, r = 0.005, o = {}) {
  const S = plateGeo.userData, n = o.n ?? 32, t = o.thick ?? 0.006;
  const lift = o.lift ?? r * 0.2 - t * 0.5, out = o.out ?? r * 0.3;
  const closed = !!o.closed, cnt = closed ? n : n + 1;
  const C = [], Nn = [], E = [];
  for (let i = 0; i < cnt; i++) {
    const s = lerp(o.from ?? 0, o.to ?? 1, i / n);
    const [u, v] = side === 'v0' ? [s, 0] : side === 'v1' ? [s, 1] : side === 'u0' ? [0, s] : [1, s];
    const f = S.normalAt(clamp(u, 0, 1), clamp(v, 0, 1));
    const e = side === 'v0' ? f.dv.clone().negate() : side === 'v1' ? f.dv : side === 'u0' ? f.du.clone().negate() : f.du;
    e.addScaledVector(f.n, -e.dot(f.n)).normalize();
    C.push(f.p.clone().addScaledVector(f.n, lift).addScaledVector(e, out));
    Nn.push(f.n.clone());
    E.push(e);
  }
  const m = BEAD.length, pos = [], nor = [], cav = [], idx = [];
  const T = new THREE.Vector3(), B = new THREE.Vector3(), Nf = new THREE.Vector3();
  for (let i = 0; i < cnt; i++) {
    const a = C[closed ? (i - 1 + cnt) % cnt : Math.max(0, i - 1)], b = C[closed ? (i + 1) % cnt : Math.min(cnt - 1, i + 1)];
    T.subVectors(b, a).normalize();
    Nf.copy(Nn[i]).addScaledVector(T, -T.dot(Nn[i])).normalize();
    B.crossVectors(T, Nf);
    if (B.dot(E[i]) < 0) B.negate();
    for (const [x, y] of BEAD) {
      const dx = Nf.x * x + B.x * y, dy = Nf.y * x + B.y * y, dz = Nf.z * x + B.z * y;
      pos.push(C[i].x + dx * r, C[i].y + dy * r, C[i].z + dz * r);
      nor.push(dx, dy, dz);
      cav.push(x > 0.5 ? 1 + 0.6 * x : 0.75 + 0.25 * x);
    }
  }
  for (let i = 0; i < (closed ? cnt : cnt - 1); i++) {
    const i2 = (i + 1) % cnt;
    for (let k = 0; k < m - 1; k++) { const a = i * m + k, b = a + 1, c = i2 * m + k, d = c + 1; idx.push(a, c, b, b, c, d); }
  }
  if (!closed) {
    // end caps: fan over the crown
    for (const [i, sg] of [[0, -1], [cnt - 1, 1]]) {
      const a = C[Math.max(0, i - 1)], b = C[Math.min(cnt - 1, i + 1)];
      T.subVectors(b, a).normalize().multiplyScalar(sg);
      const base = pos.length / 3;
      pos.push(C[i].x, C[i].y, C[i].z); nor.push(T.x, T.y, T.z); cav.push(1.2);
      for (let k = 0; k < m; k++) { const q = (i * m + k) * 3; pos.push(pos[q], pos[q + 1], pos[q + 2]); nor.push(T.x, T.y, T.z); cav.push(1.2); }
      for (let k = 0; k < m - 1; k++) idx.push(base, base + 1 + k, base + 2 + k);
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
  g.setAttribute('cav', new THREE.Float32BufferAttribute(cav, 1));
  g.setIndex(idx);
  return fixWinding(g);
}

/**
 * Forged comb along a path on a plate surface: a blade standing on the surface normal (a ridge crest in profile).
 * uv: [[u, v], ...] path on the plate; o: { h = 0.02 (peak height, curve over t via h(t) when a function), t = 0.003
 * (half thickness), n = 24 }
 */
export function combAlong(plateGeo, uv, o = {}) {
  const S = plateGeo.userData, n = o.n ?? 24;
  const H = typeof o.h === 'function' ? o.h : (t) => (o.h ?? 0.02) * Math.pow(Math.sin(Math.PI * clamp(t * 1.04, 0, 1)), 0.6) + 0.003;
  const pts = [], ups = [];
  for (let i = 0; i <= n; i++) {
    const f = i / n, k = f * (uv.length - 1), j = Math.min(uv.length - 2, Math.floor(k)), r = k - j;
    const u = lerp(uv[j][0], uv[j + 1][0], r), v = lerp(uv[j][1], uv[j + 1][1], r);
    const q = S.normalAt(clamp(u, 0, 1), clamp(v, 0, 1));
    pts.push(q.p.addScaledVector(q.n, -0.002)); ups.push(q.n);
  }
  const th = o.t ?? 0.003;
  const prof = (t) => { const h = H(t); return [[-0.002, -th], [h * 0.78, -th * 0.6], [h, 0], [h * 0.78, th * 0.6], [-0.002, th]]; };
  return sweep(pts, prof, { up: ups[0].toArray(), hard: [1, 2, 3], caps: true, cavScale: 0.003 });
}

// ---- flat bevelled blades (feathers, fins) ------------------------------------------------------------------------------

/**
 * Bevelled flat blade from a 2D outline (x along the blade, y across), lying in XY (normal +Z), thickness `depth`.
 * Returns the geometry with userData.edge (Float32Array, 1 on the outline band / bevel, 0 on the flats) so a design can
 * colour the edges (gold edging) by vertex index, and userData.face (z of the +Z flat).
 */
export function blade2d(outline, o = {}) {
  const depth = o.depth ?? 0.005, bevel = o.bevel ?? 0.0016;
  const g = extrude(outline, { depth, bevel, bevelSegs: o.bevelSegs ?? 2, curveSegs: 2, crease: o.crease ?? 35 });
  const N = g.attributes.normal.array, n = N.length / 3, edge = new Float32Array(n);
  for (let i = 0; i < n; i++) edge[i] = Math.abs(N[i * 3 + 2]) < 0.93 ? 1 : 0;
  g.userData.edge = edge;
  g.userData.face = depth / 2 + bevel;
  return g;
}

/** Copy of edge masks through merge(): concatenates userData.edge of the parts (parts without one -> 0). */
function mergeEdges(parts) {
  const g = merge(parts);
  const e = new Float32Array(g.attributes.position.count);
  let o = 0;
  for (const p of parts) {
    const c = p.attributes.position.count;
    if (p.userData.edge) e.set(p.userData.edge, o);
    o += c;
  }
  g.userData.edge = e;
  return g;
}

/** Apply a Matrix4 to a geometry keeping userData (edge masks are per vertex, order unchanged). */
function applyM(g, m) {
  const ud = g.userData;
  g.applyMatrix4(m);
  g.userData = ud;
  return g;
}

/**
 * Storm feather: a long blade with a notched trailing edge, optionally a lightning groove (rune strip along its centre
 * on the +Z flat). o: { L, w, depth, rune = true, seed } -> { blade (with userData.edge), rune | null }
 */
export function feather(o = {}) {
  const L = o.L ?? 0.18, w = o.w ?? 0.046;
  const outline = [
    [0, -w * 0.3], [L * 0.4, -w * 0.5], [L * 0.78, -w * 0.32], [L, 0.004],
    [L * 0.72, w * 0.4], [L * 0.55, w * 0.3], [L * 0.47, w * 0.5], [L * 0.27, w * 0.38], [L * 0.2, w * 0.52], [0, w * 0.34],
  ];
  const b = blade2d(outline, { depth: o.depth ?? 0.0055, bevel: 0.0018, bevelSegs: 1 });
  if (o.rune === false) return { blade: b, rune: null };
  const z = b.userData.face + 0.0003;
  const pts = arcPath(L * 0.1, 0, L * 0.82, 0.0, { segs: 6, amp: w * 0.14, seed: o.seed ?? 3 }).map(([x, y]) => [x, y - w * 0.04, z]);
  const rune = sweep(pts, [[0.0024, 0], [0, 0.0007], [-0.0024, 0], [0, -0.0003]], { up: [0, 0, 1], caps: true });
  return { blade: b, rune };
}

// ---- helm ---------------------------------------------------------------------------------------------------------------

/** Horn centre line (head frame) of side s (+1 right, -1 left), hk = height scale: 19 points root -> tip. */
function hornCurve(s, hk = 1) {
  const k = (y) => 0.15 + (y - 0.15) * hk;
  return curve([
    [0.01, 0.15, s * 0.084], [-0.006, k(0.205), s * 0.124], [-0.03, k(0.28), s * 0.147], [-0.064, k(0.36), s * 0.153],
    [-0.108, k(0.44), s * 0.144], [-0.152, k(0.5), s * 0.128], [-0.18, k(0.54), s * 0.114],
  ], 18);
}

/** Horn tip positions [right, left] in the head frame (sockets for the idle arcs). o: stormHelm options (hornH). */
export function stormHornTips(o = {}) {
  const t = hornCurve(1, o.hornH ?? 1)[18];
  return [t, [t[0], t[1], -t[2]]];
}

/**
 * VORN's storm helm (head frame: pivot at the skull base, head top ~+0.22). A tall close helm: ogival skull with a gold
 * comb, a V-fronted face whose prow carries the vertical breath slot of the T-visor, a brow plate dipping into a frown
 * over the eye slit (gold-trimmed), cheek plates with glowing arc "tears", a chin plate, a flared nape guard, swept
 * horns rising high above the crown and a fan of storm feathers behind each horn.
 * o: rx=0.124 (half depth), rz=0.106 (half width), top=0.282 (apex), bottom=-0.08, ox=0.016, eyeY=0.08, eyeH=0.018,
 *    slotW=0.014 (vertical slot width), slotY=0.0 (slot bottom), prow=0.04 (beak ridge), hornH=1 (horn height scale),
 *    wings=4 (feathers per side), runes=true (feather / horn / cheek arc lines), rivets=true
 * Returns { skull, comb, brow, browTrim, cheeks, cheekTrim (gold lips of the T), breaths, chin, chinTrim, nape, recess, eye, horns, hornRoots, feathers
 *           (userData.edge: gold edging mask), runes, rivets, hornTips: [[x,y,z] R, [x,y,z] L] }
 */
export function stormHelm(o = {}) {
  const rx = o.rx ?? 0.124, rz = o.rz ?? 0.106, top = o.top ?? 0.282, bottom = o.bottom ?? -0.08, ox = o.ox ?? 0.016;
  const ey = o.eyeY ?? 0.08, eh = o.eyeH ?? 0.018, slotW = o.slotW ?? 0.014, slotY = o.slotY ?? 0.0, prow = o.prow ?? 0.04;
  const yd = 0.13; // dome starts here
  const yb = ey + eh * 0.5 + 0.026; // skull's lower edge (front)
  const RX = (y) => {
    if (y > yd) { const t = (y - yd) / (top - yd); return rx * Math.pow(Math.max(0, 1 - Math.pow(t, 2.0)), 0.55); }
    const t = (yd - y) / (yd - bottom);
    return rx * (1 - 0.2 * Math.pow(t, 1.6));
  };
  const RZ = (y) => {
    if (y > yd) { const t = (y - yd) / (top - yd); return rz * Math.pow(Math.max(0, 1 - Math.pow(t, 2.1)), 0.5); }
    const t = (yd - y) / (yd - bottom);
    return rz * (1 - 0.16 * t * t);
  };
  const NE = (y) => (y > yd ? 2.15 : y > ey + eh ? lerp(1.75, 2.15, (y - ey - eh) / (yd - ey - eh)) : 1.6);
  const ridgeK = (a, h, w) => h * Math.pow(Math.max(0, 1 - Math.abs(a) / w), 1.25);
  const P = (a, y, grow = 0, ridge = 0, rw = 20) => {
    const ar = a * DEG;
    const [x, z] = se(ar, Math.max(1e-4, RX(y) + grow), Math.max(1e-4, RZ(y) + grow), NE(y));
    const rr = Math.hypot(x, z) || 1, k = ridgeK(((a + 540) % 360) - 180, ridge, rw) / rr;
    return [ox * (y > yd ? 1 - ((y - yd) / (top - yd)) * 0.6 : 1) + x * (1 + k), y, z * (1 + k)];
  };
  // the face prow: strongest at the slot, fading toward the chin; a lower ridge over the brow
  const prowAt = (y) => (y < ey ? prow * (1 - 0.5 * Math.pow(clamp((ey - y) / (ey - bottom), 0, 1), 1.3)) : prow * lerp(1, 0.25, clamp((y - ey) / (yd + 0.03 - ey), 0, 1)));
  const out = {};
  // skull: hoop from the brow line (front) / nape line (back) to the apex, sharp medial crease under the comb
  const skBot = (a) => yb - 0.004 - 0.055 * Math.pow(Math.max(0, -Math.cos(a * DEG)), 1.5);
  out.skull = plate((u, v) => {
    const a = lerp(-180, 180, u), y = lerp(skBot(a), top - 0.003, Math.pow(v, 0.8));
    return P(a, y, 0, 0.01 * (1 - v * 0.5), 16);
  }, { closeU: true, nu: 30, nv: 10, thick: 0.007, edge: { v1: 'none' }, roll: { v0: 0.0045 }, creaseU: [0.5], axis: [ox, 0] });
  // comb: low forged blade from the brow over the crown to the nape (gold)
  {
    const mid = [];
    for (let i = 0; i <= 10; i++) mid.push(P(0, lerp(yb + 0.02, top - 0.002, i / 10), 0, 0.01, 16));
    for (let i = 9; i >= 0; i--) mid.push(P(180, lerp(yb - 0.04, top - 0.002, i / 10), 0, 0.01, 16));
    const prof = (t) => {
      const h = 0.003 + 0.013 * Math.pow(Math.sin(Math.PI * clamp(t * 1.05, 0, 1)), 0.7);
      return [[-0.003, -0.003], [h * 0.75, -0.0021], [h, 0], [h * 0.75, 0.0021], [-0.003, 0.003]];
    };
    out.comb = sweep(curve(mid, 36), prof, { up: [1, 0.25, 0], hard: [1, 2, 3], caps: true, cavScale: 0.003 });
  }
  // brow plate: over the eye slit, its lower edge dipping into a frown over the breath slot (the T's cross bar)
  const browTop = yb + 0.014;
  const browLow = (a) => ey + eh * 0.5 + 0.0015 - 0.013 * Math.pow(Math.max(0, Math.cos(a * DEG)), 5) + 0.007 * sstep(65, 112, Math.abs(a));
  out.brow = plate((u, v) => {
    const a = lerp(-114, 114, u), y = lerp(browTop, browLow(a), v);
    return P(a, y, 0.0022 + 0.006 * v * v, prowAt(y), 40);
  }, { nu: 26, nv: 3, thick: 0.007, edgeR: 0.0045, roll: { v1: 0.0045 }, edge: { v0: 'none' }, creaseU: [0.5], axis: [ox, 0] });
  out.browTrim = rim(out.brow, 'v1', 0.0042, { n: 34, thick: 0.008 });
  // cheek plates: below the slit, split by the vertical slot at the prow
  const cheekTop = (a) => ey - eh * 0.5 - 0.0015 + 0.005 * sstep(60, 108, Math.abs(a));
  const aS = (slotW * 0.5 / (rx + prow)) / DEG;
  const cheekS = (s) => (u, v) => {
    const a = s * lerp(aS, 112, u), y = lerp(cheekTop(a), bottom, v);
    return P(a, y, 0.004, prowAt(y), 40);
  };
  const cheeks = [1, -1].map((s) => plate(cheekS(s), { nu: 14, nv: 8, thick: 0.008, edgeR: 0.005, roll: { v1: 0.005 }, axis: [ox, 0] }));
  out.cheeks = merge(cheeks);
  // gold lips framing the T (the slot edges and the slit's lower edge)
  out.cheekTrim = merge(cheeks.flatMap((c) => [rim(c, 'u0', 0.0034, { n: 10, thick: 0.008 }), rim(c, 'v0', 0.0034, { n: 14, thick: 0.008 })]));
  // breaths: a column of slanted slits down each cheek (the storm inside the helm glows through them)
  out.breaths = merge(cheeks.flatMap((c) => [0, 1, 2, 3, 4].map((k) => {
    const uc = 0.5 + 0.03 * k, vc = 0.2 + 0.09 * k;
    return strip(c.userData, [[uc - 0.06, vc + 0.025], [uc + 0.06, vc - 0.025]], { width: 0.0042, lift: 0.0004, bead: -0.0006, smooth: 2 });
  })));
  // chin plate riveted over the cheeks below the slot, gold-rimmed
  out.chin = plate((u, v) => {
    const a = lerp(-52, 52, u), y = lerp(slotY - 0.003 + 0.03 * Math.pow(Math.abs(a) / 52, 1.6), bottom - 0.004, v);
    return P(a, y, 0.0085, prowAt(y) + 0.0012, 40);
  }, { nu: 14, nv: 4, thick: 0.007, edgeR: 0.0045, creaseU: [0.5], axis: [ox, 0] });
  out.chinTrim = rim(out.chin, 'v0', 0.0038, { n: 22, thick: 0.007 });
  // nape guard: back plate under the skull edge, flaring over the gorget
  out.nape = plate((u, v) => {
    const a = lerp(96, 264, u), y = lerp(skBot(a) + 0.012, bottom - 0.02, v);
    return P(a, y, 0.0015 + 0.013 * v * v, 0.004);
  }, { nu: 14, nv: 6, thick: 0.007, edgeR: 0.0045, roll: { v1: 0.005 }, creaseU: [0.5], axis: [ox, 0] });
  // dark recess behind the T opening
  out.recess = merge([
    plate((u, v) => P(lerp(-100, 100, u), lerp(ey + eh * 0.95, ey - eh * 0.95, v), -0.011, 0), { nu: 20, nv: 1, thick: 0, axis: [ox, 0] }),
    plate((u, v) => P(lerp(-9, 9, u), lerp(ey, slotY - 0.006, v), -0.008, 0), { nu: 4, nv: 3, thick: 0, axis: [ox, 0] }),
  ]);
  // glow strip deeper in the T: the cross bar (eyes hot) and the breath slot
  out.eye = merge([
    plate((u, v) => P(lerp(-66, 66, u), lerp(ey + eh * 0.32, ey - eh * 0.32, v), -0.0085, 0), { nu: 16, nv: 1, thick: 0, axis: [ox, 0] }),
    plate((u, v) => P(lerp(-2.4, 2.4, u), lerp(ey - eh * 0.2, slotY + 0.002, v), -0.006, 0), { nu: 2, nv: 3, thick: 0, axis: [ox, 0] }),
  ]);
  // horns: faceted, swept up and back from the temples, rising high above the crown (vertical silhouette)
  const hk = o.hornH ?? 1;
  const hornSec = [[1, 0], [0.55, 0.62], [0, 0.85], [-0.6, 0.6], [-1, 0], [-0.6, -0.55], [0, -0.8], [0.55, -0.6]];
  const hornR = (t) => 0.029 * Math.pow(1 - t, 0.85) + 0.0012;
  const horn = (s) => sweep(hornCurve(s, hk), hornSec, { scale: (t) => [hornR(t), hornR(t) * 0.9], up: [0, 0, s], hard: [0, 4], caps: true, cavScale: 0.003 });
  out.horns = merge([horn(1), horn(-1)]);
  out.hornTips = stormHornTips(o);
  // horn roots: gold rosettes on the temples (also cover the feather roots)
  const rosette = lathe([[0.0, 0.011], [0.013, 0.0105], [0.024, 0.0068], [0.033, 0.003], [0.037, 0.0], [0.0, 0.0]], { segs: 16, hard: [3] });
  const roots = [];
  for (const s of [1, -1]) {
    const f = P(80 * s, 0.168, 0.0, 0);
    const n = new THREE.Vector3(0.12, 0.2, s).normalize();
    const g = rosette.clone();
    g.applyMatrix4(new THREE.Matrix4().compose(new THREE.Vector3(f[0], f[1], f[2]).addScaledVector(n, -0.003), new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, 1, 0), n), new THREE.Vector3(1, 1, 1)));
    roots.push(g);
  }
  out.hornRoots = merge(roots);
  // storm-feather wings: a fan behind each horn, upper feathers outermost (broad faces to the side: they read from the
  // fight camera)
  const nW = o.wings ?? 4, runesOn = o.runes !== false;
  const fParts = [], rParts = [];
  for (const s of [1, -1]) {
    for (let k = 0; k < nW; k++) {
      const L = 0.25 - k * 0.032, w = 0.064 - k * 0.005, th = (50 - k * 15) * DEG, beta = (12 + k * 3) * DEG;
      const { blade, rune } = feather({ L, w, seed: 3 + k * 7 + (s > 0 ? 0 : 31), rune: runesOn && k % 2 === 0 });
      const m = new THREE.Matrix4();
      const rot = new THREE.Matrix4().makeRotationZ(Math.PI - th).multiply(new THREE.Matrix4().makeRotationY(-beta));
      m.copy(rot).setPosition(-0.006 - 0.012 * k, 0.172 - 0.01 * k, 0.103 - 0.003 * k);
      if (s < 0) m.premultiply(new THREE.Matrix4().makeScale(1, 1, -1));
      for (const g of rune ? [blade, rune] : [blade]) {
        applyM(g, m);
        if (s < 0) { const a = g.index.array; for (let i = 0; i < a.length; i += 3) { const t = a[i + 1]; a[i + 1] = a[i + 2]; a[i + 2] = t; } }
      }
      fParts.push(blade);
      if (rune) rParts.push(rune);
    }
  }
  out.feathers = mergeEdges(fParts);
  if (runesOn) {
    // arc seams along the outer face of the horns
    for (const s of [1, -1]) {
      const hp = hornCurve(s, hk), pts = [];
      for (let i = 2; i <= 14; i += 2) {
        const t = i / 18, p = hp[i];
        pts.push([p[0] + 0.003 * Math.sin(i * 2.1), p[1], p[2] + s * (hornR(t) * 0.84 + 0.0004)]);
      }
      rParts.push(sweep(curve(pts, 16), [[0.0018, 0], [0, 0.0006], [-0.0018, 0], [0, -0.0003]], { up: [0, 0, s], caps: true }));
    }
    // arc "tears" running from the outer ends of the eye slit down the cheeks
    cheeks.forEach((c, i) => rParts.push(arcRune(c, 0.72, 0.04, 0.9, 0.74, { segs: 5, amp: 0.045, seed: 61 + i, width: 0.0028, lift: 0.0006 })));
  }
  out.runes = merge(rParts);
  if (o.rivets !== false) {
    out.rivets = merge([
      studs(onSurface(out.chin.userData, [[0.22, 0.45], [0.78, 0.45]]), { r: 0.0052, h: 0.0034, segs: 5 }),
      studs(onSurface(cheeks[0].userData, [[0.82, 0.2], [0.82, 0.62]]), { r: 0.005, h: 0.0032, segs: 5 }),
      studs(onSurface(cheeks[1].userData, [[0.82, 0.2], [0.82, 0.62]]), { r: 0.005, h: 0.0032, segs: 5 }),
      studs(onSurface(out.nape.userData, [[0.2, 0.25], [0.5, 0.25], [0.8, 0.25]]), { r: 0.005, h: 0.0032, segs: 5 }),
    ]);
  }
  return out;
}

// ---- pauldron fins --------------------------------------------------------------------------------------------------------

/**
 * Jagged lightning-bolt fins standing on a pauldron (deltoid frame of the R side; mirror for the left).
 * o: { at: [x,y,z] base centre (top of the cop), h = 0.15 (tallest spike), len = 0.19 (front-back), lean = 12 (deg
 *      about X), yaw = 0 (deg about Y: turns the broad faces toward the front / back views), count = 2,
 *      gap = 0.032 (sideways spacing), depth = 0.008 }
 * Returns { fins (userData.edge), runes }
 */
export function stormFins(o = {}) {
  const at = o.at || [0, 0.12, 0], H = o.h ?? 0.15, Lf = o.len ?? 0.19, n = o.count ?? 2, gap = o.gap ?? 0.032;
  const parts = [], rparts = [];
  for (let k = 0; k < n; k++) {
    const s = 1 - k * 0.28, h = H * s, L = Lf * (1 - k * 0.18);
    // side profile: blunt front, three bolt-like spikes leaning back, the last one the tallest
    const ol = [
      [L * 0.5, -0.03], [L * 0.5, h * 0.14], [L * 0.3, h * 0.42], [L * 0.22, h * 0.3], [0, h * 0.7],
      [-L * 0.07, h * 0.52], [-L * 0.5, h], [-L * 0.4, h * 0.4], [-L * 0.46, -0.03],
    ];
    const g = blade2d(ol, { depth: o.depth ?? 0.008, bevel: 0.0024, crease: 30 });
    const z = g.userData.face + 0.0003;
    const pts = [[L * 0.38, h * 0.12, z], [L * 0.2, h * 0.22, z], [L * 0.24, h * 0.28, z], [0, h * 0.45, z], [L * 0.04, h * 0.5, z], [-L * 0.3, h * 0.68, z]];
    const rn = sweep(pts, [[0.0026, 0], [0, 0.0007], [-0.0026, 0], [0, -0.0003]], { up: [0, 0, 1], caps: true });
    const m = new THREE.Matrix4().makeRotationY((o.yaw ?? 0) * DEG).multiply(new THREE.Matrix4().makeRotationX(-((o.lean ?? 12) + k * 10) * DEG));
    m.setPosition(at[0] - k * 0.02, at[1] - k * 0.012, at[2] + k * gap);
    applyM(g, m); applyM(rn, m);
    parts.push(g); rparts.push(rn);
  }
  return { fins: mergeEdges(parts), runes: merge(rparts) };
}

// ---- mail skirt -------------------------------------------------------------------------------------------------------

/**
 * One half of a split cavalry hauberk skirt (hips frame, R side: wraps the outside of the right thigh from the front
 * split to the back split). o: { y0 = 0.035, y1 = -0.32, rx0, rz0, rx1, rz1, a0 = 8, a1 = 172, scallop = 0.008 }
 */
export function mailSkirt(o = {}) {
  return plate((u, v) => {
    const a = lerp(o.a0 ?? 8, o.a1 ?? 172, u) * DEG;
    const y = lerp(o.y0 ?? 0.035, (o.y1 ?? -0.32) + (o.scallop ?? 0.008) * Math.cos(u * Math.PI * 14) - 0.03 * Math.sin(u * Math.PI), Math.pow(v, 1.0));
    const rx = lerp(o.rx0 ?? 0.16, o.rx1 ?? 0.205, v), rz = lerp(o.rz0 ?? 0.178, o.rz1 ?? 0.235, v);
    const [x, z] = se(a, rx, rz, 2.2);
    return [x + (o.ox ?? 0), y, z];
  }, { nu: o.nu ?? 22, nv: o.nv ?? 6, thick: 0.005, edgeR: 0.003, edgeSegs: 2, inner: true, innerCav: 0.5, axis: [0, 0], curv: 0.002 });
}

// ---- limb shells at VORN's resolution -------------------------------------------------------------------------------------
// The shared builders (src/char/kit/armor.js) fix their segment counts; these follow the same shapes with a segment
// budget (and VORN's longer limbs), so the design stays inside 60k triangles.

/** Gorget lames flaring from the neck to the collar (neck frame; skin chest -> neck). o: count, rTop, rBot, y0, y1, point, nu */
export function gorget(o = {}) {
  const out = [];
  const n = o.count ?? 3, rTop = o.rTop ?? 0.075, rBot = o.rBot ?? 0.15, y0 = o.y0 ?? 0.065, y1 = o.y1 ?? -0.08;
  for (let k = 0; k < n; k++) {
    const t0 = k / n, t1 = Math.min(1, (k + 1) / n + 0.08);
    const ya = lerp(y0, y1, t0), yb = lerp(y0, y1, t1);
    const ra = lerp(rTop, rBot, Math.pow(t0, 1.6)), rb = lerp(rTop, rBot, Math.pow(t1, 1.6));
    out.push(hoop({
      y0: ya, y1: yb, closed: true, rx: [[0, ra * 0.95 + k * 0.003], [1, rb * 0.95 + k * 0.003]], rz: [[0, ra + k * 0.003], [1, rb + k * 0.003]],
      ox: 0.004, n: 2.1, nu: o.nu ?? 20, nv: 2, thick: 0.006, edgeR: 0.004, roll: k === n - 1 ? {} : { v1: 0.0035 },
      bot: (a) => -(o.point ?? 0.02) * Math.pow(Math.max(0, Math.cos(a * DEG)), 4) * (k === n - 1 ? 1 : 0.3) - 0.012 * Math.pow(Math.max(0, -Math.cos(a * DEG)), 3),
      occ: (u, v) => 0.62 + 0.38 * sstep(0.05, 0.5, v),
    }));
  }
  return out;
}

/** Rerebrace (upperArmTwist frame): closed tube, outer ridge, shaped bottom edge (gold rim added by the design). */
export function rerebrace(o = {}) {
  const r = o.r ?? 0.064;
  return hoop({
    y0: o.y0 ?? -0.07, y1: o.y1 ?? -0.22, closed: true,
    rx: [[0, r * 1.02], [1, r * 0.94]], rz: [[0, r * 1.06], [1, r * 0.97]],
    oz: 0.004, n: 2.1, nu: o.nu ?? 16, nv: 3, thick: 0.006, edgeR: 0.004,
    ridge: { at: 90, h: 0.004, w: 20 },
    bot: (a) => -0.012 * Math.pow(Math.max(0, Math.sin(a * DEG)), 2),
  });
}

/** Vambrace (foreArmTwist frame): tapered tube, outer ridge, raised elbow edge on the outside. */
export function vambrace(o = {}) {
  const r = o.r ?? 0.058;
  return hoop({
    y0: o.y0 ?? 0.12, y1: o.y1 ?? -0.12, closed: true,
    rx: [[0, r * 0.98], [0.35, r * 1.02], [0.85, r * 0.84], [1, r * 0.9]],
    rz: [[0, r * 1.04], [0.35, r * 1.08], [0.85, r * 0.88], [1, r * 0.95]],
    n: 2.15, nu: o.nu ?? 16, nv: 5, thick: 0.006, edgeR: 0.0045, roll: { v0: 0.005 },
    ridge: { at: 90, h: 0.007, w: 24 },
    top: (a) => 0.02 * Math.pow(Math.max(0, Math.sin(a * DEG)), 2),
  });
}

/** Couter lames (elbow frame): two closed bands above and below the cop (A.couter's, at VORN's segment budget). */
export function couterLames(o = {}) {
  const r = o.r ?? 0.062;
  return [[0.072, 0.036], [-0.036, -0.072]].map(([y0, y1]) => hoop({ y0, y1, closed: true, rx: r * 0.9, rz: r * 0.92, n: 2.1, nu: o.nu ?? 14, nv: 1, thick: 0.005, edgeR: 0.0035 }));
}

/** Poleyn lames (knee frame): open bands above and below the cop (A.poleyn's, at VORN's segment budget). */
export function poleynLames(o = {}) {
  const r = o.r ?? 0.074;
  return [[0.085, 0.045, 1], [-0.04, -0.08, -1]].map(([y0, y1, k]) => hoop({
    y0, y1, a0: -105, a1: 115, rx: r * 0.98, rz: r * 0.98, ox: 0.004, n: 2.1, nu: o.nu ?? 12, nv: 1, thick: 0.006, edgeR: 0.0045,
    bot: (a) => (k > 0 ? -0.012 * Math.pow(Math.max(0, Math.cos(a * DEG)), 2) : 0),
    top: (a) => (k < 0 ? 0.012 * Math.pow(Math.max(0, Math.cos(a * DEG)), 2) : 0),
  }));
}

/** Cuisse (thigh frame): open shell over the front and outside of the thigh with a ridge. */
export function cuisse(o = {}) {
  const r = o.r ?? 0.11;
  return hoop({
    y0: o.y0 ?? -0.035, y1: o.y1 ?? -0.42, a0: -112, a1: 128,
    rx: [[0, r * 1.02], [0.5, r * 0.94], [1, r * 0.8]], rz: [[0, r * 1.04], [0.5, r * 0.95], [1, r * 0.8]], ox: 0.006, n: 2.15,
    nu: o.nu ?? 15, nv: o.nv ?? 6, thick: 0.007, edgeR: 0.005, roll: { v0: 0.0055 },
    ridge: { at: 8, h: 0.008, w: 22 },
    top: (a) => 0.03 * Math.pow(Math.max(0, Math.sin(a * DEG)), 2) - 0.02 * Math.pow(Math.max(0, Math.cos(a * DEG)), 2),
  });
}

/** Greave (shin frame): closed tube, calf swell, shin ridge (crease), flared ankle, pointed knee edge. */
export function greave(o = {}) {
  const r = o.r ?? 0.072;
  return hoop({
    y0: o.y0 ?? -0.07, y1: o.y1 ?? -0.44, closed: true,
    rx: [[0, r], [0.28, r * 1.08], [0.75, r * 0.84], [1, r * 0.88]],
    rz: [[0, r * 0.96], [0.28, r * 1.02], [0.75, r * 0.8], [1, r * 0.84]],
    ox: [[0, -0.004], [0.3, -0.012], [1, 0.002]],
    bulge: (u, v) => 0.012 * Math.pow(Math.max(0, -Math.cos((u * 360 - 180) * DEG)), 2) * Math.sin(Math.PI * clamp(v * 1.3, 0, 1)),
    n: 2.1, nu: o.nu ?? 16, nv: o.nv ?? 6, thick: 0.006, edgeR: 0.0045, roll: { v0: 0.005 },
    ridge: { at: 0, h: 0.01, w: 24 },
    top: (a) => 0.016 * Math.pow(Math.max(0, Math.cos(a * DEG)), 3),
    bot: (a) => 0.012 * Math.pow(Math.max(0, Math.cos(a * DEG)), 2),
  });
}

// ---- spur ------------------------------------------------------------------------------------------------------------------

/** Rowel spur on the heel (foot frame, R side): yoke around the heel, neck pointing back, eight-point rowel (faces +-Z). */
export function spur(o = {}) {
  const hx = o.hx ?? -0.072, y = o.y ?? -0.05, w = o.w ?? 0.047;
  const yoke = sweep(curve([[hx + 0.05, y, w], [hx + 0.008, y + 0.002, w * 0.94], [hx - 0.012, y + 0.004, 0], [hx + 0.008, y + 0.002, -w * 0.94], [hx + 0.05, y, -w]], 12),
    circle(5), { scale: [0.0042, 0.0026], up: [0, 1, 0], caps: true });
  const neck = sweep(curve([[hx - 0.01, y + 0.004, 0], [hx - 0.03, y + 0.006, 0], [hx - 0.046, y + 0.002, 0]], 4), circle(5), { scale: (t) => 0.0042 - t * 0.0012, up: [0, 1, 0], caps: true });
  const star = [];
  for (let k = 0; k < 16; k++) { const a = (k / 16) * Math.PI * 2, r = k % 2 ? 0.0055 : 0.019; star.push([Math.cos(a) * r, Math.sin(a) * r]); }
  const rowel = extrude(star, { depth: 0.0028, bevel: 0.0009, bevelSegs: 1, crease: 30 });
  rowel.translate(hx - 0.05, y + 0.002, 0);
  return merge([yoke, neck, rowel]);
}

// ---- glow --------------------------------------------------------------------------------------------------------------------

/**
 * Deterministic arc crackle at time t (s): a fast low flicker plus sparse surges (fast attack, ~0.1 s decay).
 * Returns a multiplier ~0.82 .. ~2.0. seed decorrelates channels.
 */
export function crackle(t, seed = 0) {
  const f = 0.92 + 0.08 * Math.sin(t * 37.0 + seed * 2.3) * Math.sin(t * 23.0 + seed);
  const rate = 2.4, k = Math.floor(t * rate), ph = t * rate - k;
  const h = hash1(k * 1.37 + seed * 17.1);
  const surge = h > 0.62 ? ((h - 0.62) / 0.38) * Math.exp(-ph * 9.0) * (0.6 + 0.4 * Math.sin(ph * 90.0 + seed) ** 2) : 0;
  return f + surge * 1.05;
}

