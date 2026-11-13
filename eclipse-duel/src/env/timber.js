// The Heaven-Martial Sect's timber architecture, built from code: red-lacquered columns on lotus bases, lintels
// with faded 단청, simplified bracket sets (공포) with their ox-tongue arms, and curved tile roofs (roof.js).
// Assemblies: the gallery (회랑) around the court, the collapsed hall (천무전) on the west side and the mountain
// gate (산문) with its hanging name board 天武 on the south side. Stone goes to C.S, painted timber to C.P, metal to
// C.M (see ruins.js for the build context C).

import * as THREE from 'three';
import { DEG, smoothstep } from '../core/math.js';
import { chamferBox, latheGrid, addAll, trs, noise3, setOrnUv, beam, prism, ringM, tube, brokenBlock, ashlar, sweep, linePath, frontFace, rock } from './geometry.js';
import { LAYOUT, PALETTE, HALL, GATE } from './config.js';
import { ORN, panel } from './ornament.js';
import { roofPatch, ridge, rafters, eaveBoard } from './roof.js';

const V = (x, y, z) => new THREE.Vector3(x, y, z);
const T = (m, x, y, z, ry = 0, rx = 0, rz = 0, sx = 1, sy = sx, sz = sx) => m.clone().multiply(trs(x, y, z, ry, rx, rz, sx, sy, sz));
const ROT_X2Z = -Math.PI / 2;  // yaw that turns a piece built along X so that it runs along +Z

// ---------------------------------------------------------------------------------------------------------------------
// pieces
// ---------------------------------------------------------------------------------------------------------------------

/** Stone column base (주춧돌): a square plinth and a lotus drum. `m`: column foot. */
export function columnBase(C, m, r = 0.26, h = 0.34) {
  const tint = C.blockTint();
  C.S.add(chamferBox(r * 3.4, 0.16, r * 3.4, 0.03, C.rng, 0.3), T(m, 0, 0.08, 0), C.st(tint));
  const parts = latheGrid({ rows: 3, segs: 12, profile: (t) => [r * (1.75 - 0.5 * t * t) * (1 + 0.1 * Math.sin(t * Math.PI)), 0.16 + t * (h - 0.16)], capTop: true });
  setOrnUv(parts[0], (p, n, i) => [((i % 13) / 12) * 8, (p.y - 0.16) / (h - 0.16), 1]);
  addAll(C.S, parts, m, { ...C.st(tint), orn: { cell: ORN.petal, amount: C.erosion() * 0.9, su: 1, sv: 1 } });
  return h;
}

/**
 * Timber column standing at `m` (foot on its base): lacquer red, a jade band with a petal collar under the head.
 * `broken`: snapped off with a splintered top. @returns the top height
 */
export function column(C, m, H, r = 0.26, { broken = false, band = true, segs = 12 } = {}) {
  const seed = C.rng.range(0, 60);
  const jag = Math.min(0.9, H * 0.3);
  const parts = latheGrid({
    rows: broken ? 3 : 2, segs,
    profile: (t) => [r * (1 - 0.1 * t * t), t * H],
    rmod: (phi, y) => 1 + (noise3(Math.cos(phi) * 2 + seed, y * 0.7, Math.sin(phi) * 2) - 0.5) * 0.05,
    topY: broken ? (phi) => H - Math.pow(Math.abs(noise3(Math.cos(phi) * 2.6 + seed, Math.sin(phi) * 2.6, 3.3)), 1.4) * jag * 1.6 - (0.5 + 0.5 * Math.cos(phi - seed)) * jag * 0.5 : null,
    capTop: broken ? H - jag * 0.8 : false,
  });
  addAll(C.P, parts, m, C.wd(C.lacquer(broken ? 0.75 : 1), { uv: 'keep', uvScale: 1.1 }));
  if (band && !broken) {
    const bh = 0.5, rr = r * 0.9 + 0.012;
    const g = latheGrid({ rows: 1, segs, profile: (t) => [rr, H - bh + t * bh] });
    setOrnUv(g[0], (p, n, i) => [((i % (segs + 1)) / segs) * 10, (p.y - (H - bh)) / bh, 1]);
    addAll(C.P, g, m, C.wd(C.jade(1), { uv: 'keep', uvScale: 1.1, orn: { cell: ORN.petal, amount: 0.9, su: 1, sv: -1, ov: 1 } }));
  }
  return H;
}

/**
 * Lintel (창방) between two points at the same height: jade with a painted band, fan-ended (머리초) when long.
 * `a`, `b`: world end points on the column axes (y = beam centre).
 */
export function lintel(C, a, b, { h = 0.3, d = 0.22, cell = ORN.cloud, color = null, sag = 0 } = {}) {
  const L = a.distanceTo(b);
  const mid = a.clone().add(b).multiplyScalar(0.5);
  const yaw = Math.atan2(-(b.z - a.z), b.x - a.x);
  const pitch = Math.atan2(b.y - a.y, Math.hypot(b.x - a.x, b.z - a.z));
  const m = trs(mid.x, mid.y - sag, mid.z, yaw, 0, pitch);
  const col = color || C.jade(1);
  if (L < 2.6) {
    C.P.add(beam(L, h, d, { ends: false, ornFace: 'both' }), m, C.wd(col, { uv: 'keep', uvScale: 1.1, orn: { cell, amount: 0.9, su: Math.max(1, Math.round(L / 0.7)), sv: 1 } }));
    return;
  }
  const e = 0.95;
  for (const s of [-1, 1]) {
    C.P.add(beam(e, h, d, { ends: false, ornFace: 'both' }), T(m, s * (L / 2 - e / 2), 0, 0), C.wd(col, { uv: 'keep', uvScale: 1.1, orn: { cell: ORN.danHead, amount: 0.95, su: -s, ou: s > 0 ? 1 : 0, sv: 1 } }));
  }
  const Lm = L - 2 * e;
  C.P.add(beam(Lm, h, d, { ends: false, ornFace: 'both' }), m, C.wd(col, { uv: 'keep', uvScale: 1.1, orn: { cell, amount: 0.85, su: Math.max(1, Math.round(Lm / 0.8)), sv: 1 } }));
}

/**
 * Simplified bracket set (공포) on a column head. `m`: column top centre, local +Z toward the eave.
 * `tiers` 1..2; `s` scales the set. @returns height of the set
 */
export function bracketSet(C, m, { s = 1, tiers = 2, blocks = true } = {}) {
  const jade = C.wd(C.jade(1), { uv: 'keep', uvScale: 1.1 });
  const red = C.wd(C.lacquer(0.9), { uv: 'keep', uvScale: 1.1 });
  // capital block (주두)
  C.P.add(prism([[-0.2, 0], [0.2, 0], [0.3, 0.1], [0.3, 0.2], [-0.3, 0.2], [-0.3, 0.1]], 0.6), T(m, 0, 0, 0, 0, 0, 0, s), red);
  const tongue = (len) => prism([[-0.62, -0.085], [len - 0.4, -0.085], [len - 0.06, -0.24], [len, -0.17], [len - 0.3, 0.085], [-0.62, 0.085]], 0.17);
  for (let k = 0; k < tiers; k++) {
    const y = (0.29 + k * 0.24) * s;
    const L = 1.25 + k * 0.7;
    C.P.add(beam(L, 0.17, 0.19, { ornFace: 'both' }), T(m, 0, y, 0, 0, 0, 0, s), C.wd(C.jade(1), { uv: 'keep', uvScale: 1.1, orn: { cell: ORN.cloud, amount: 0.8, su: Math.round(L / 0.6), sv: 1 } }));
    C.P.add(tongue(0.95 + k * 0.42), T(m, 0, y, 0, ROT_X2Z, 0, 0, s), jade);
    if (blocks && k < tiers - 1) for (const sx of [-1, 1]) C.P.add(new THREE.BoxGeometry(0.2, 0.1, 0.2), T(m, sx * (L / 2 - 0.12) * s, y + 0.13 * s, 0, 0, 0, 0, s), red);
  }
  return (0.29 + tiers * 0.24 - 0.04) * s;
}

/** Roof-tile vertex colour (on the stone material): blue-black fired clay, paler and mossy where it has weathered. */
function tileColor(C, k = 1) {
  const [r, g, b] = PALETTE.tile;
  return (p, n, out) => {
    const v = k * (0.62 + 0.5 * noise3(p.x * 0.9, p.y * 0.9, p.z * 0.9)) * (0.8 + 0.4 * noise3(p.x * 0.17, p.y * 0.17, p.z * 0.17));
    const moss = smoothstep(0.56, 0.74, noise3(p.x * 0.5 + 9, p.y * 0.5, p.z * 0.5)) * 0.55;
    out[0] = v * r * (1 - moss * 0.4); out[1] = v * g * (1 - moss * 0.1); out[2] = v * b * (1 - moss * 0.5);
  };
}

/**
 * Add a roof patch (surface, tile rows, ridge pieces, rafters, eave board, soffit) placed by `m`.
 * @param {object} o  roofPatch options + { raft: every-n rows (0 = none), under: bool (soffit boards) }
 * @returns the patch (frame functions S / N in patch space)
 */
export function addRoof(C, m, o) {
  const patch = roofPatch({ ...o, soffit: !!o.under });
  const tiles = { color: tileColor(C, o.tone || 1), glow: C.glow, uv: 'keep', uvScale: 1.7, orn: { cell: ORN.tile, amount: 1.1, su: 1, sv: 1 } };
  C.S.section('roofs');
  C.S.add(patch.surface, m, tiles);
  if (patch.rows) C.S.add(patch.rows, m, { ...tiles, orn: { cell: ORN.tile, amount: 0.9, su: 1, sv: 1 } });
  C.P.section('roofwood');
  if (patch.soffit) C.P.add(patch.soffit, m, C.wd(C.bare(0.55), { uv: 'keep', uvScale: 1.1 }));
  if (o.raft) C.P.add(rafters(patch, { every: o.raft, len: Math.min(o.depth * 0.6, 1.8) }), m, C.wd(C.lacquer(0.7), { uv: 'keep', uvScale: 1.1 }));
  const eb = eaveBoard(patch);
  if (eb) C.P.add(eb, m, C.wd(C.jade(0.8), { uv: 'keep', uvScale: 1.1 }));
  return patch;
}

/** Ridge tiles along world points (patch-space points through `m`). */
export function addRidge(C, m, pts, opts = {}) {
  C.S.section('roofs');
  C.S.add(ridge(pts, opts), m, { color: tileColor(C, 0.9), glow: C.glow, uv: 'keep', uvScale: 1.7, orn: { cell: ORN.scales, amount: 0.6, su: 2, sv: 1 } });
}

/** A horn tile (취두-like, our own): the upswept block that ends a ridge. `m`: at the ridge end, +X pointing outward. */
function ridgeHorn(C, m, s = 1) {
  const g = prism([[-0.35, 0], [0.3, 0], [0.42, 0.28], [0.36, 0.78], [0.2, 0.86], [0.08, 0.52], [-0.35, 0.4]].map(([x, y]) => [x * s, y * s]), 0.3 * s);
  C.S.add(g, m, { color: tileColor(C, 0.85), glow: C.glow, uv: 'box', uvScale: 1.7 });
}

// ---------------------------------------------------------------------------------------------------------------------
// the gallery (회랑)
// ---------------------------------------------------------------------------------------------------------------------

/**
 * Gallery slots around the court: [theta deg, inner column, outer column] with a column given as its height in
 * metres (4.2 = whole, less = snapped, 0 = gone), and the bays that keep beams / roof.
 */
const SLOTS = [
  [33, 3.3, 0], [45, 4.2, 4.2], [57, 4.2, 4.2], [69, 4.2, 2.6], [81, 1.3, 0], [93, 4.2, 0], [105, 4.2, 4.2], [117, 2.9, 0],
  [129, 4.2, 4.2], [141, 4.2, 1.1], [153, 4.2, 4.2],
  [-33, 3.9, 0], [-117, 4.2, 0], [-129, 4.2, 4.2], [-141, 4.2, 4.2], [-153, 4.2, 4.2],
];
const BAYS = [
  // [theta0, theta1, kind]  kind: 'roof' (lintels + cross beams + roof), 'beam' (lintel only), 'fallen' (roof slab slid to the ground)
  [45, 57, 'roof'], [57, 69, 'roofTorn'], [93, 105, 'beam'], [129, 141, 'fallen'], [-129, -141, 'roof'], [-141, -153, 'roof'],
];

export function buildGallery(C) {
  const { platY, pillarR: r0, galleryR1: r1 } = LAYOUT;
  const colH = 4.2, rc = 0.25;
  const at = (th, r, y = platY) => ringM(r, th * DEG, y);
  const pos = (th, r, y) => V(r * Math.sin(th * DEG), y, -r * Math.cos(th * DEG));
  const pillars = [];
  C.P.section('gallery');
  for (const [th, hin, hout] of SLOTS) {
    for (const [r, h] of [[r0, hin], [r1, hout]]) {
      if (!h) continue;
      if (r === r1 && C.tier.detail < 1 && h < colH) continue;
      const m = at(th, r);
      C.S.section('bases');
      const bh = columnBase(C, m, rc);
      C.P.section('gallery');
      const lean = h < colH ? [C.rng.range(-0.05, 0.05), C.rng.range(-0.05, 0.05)] : [0, 0];
      column(C, T(m, 0, bh, 0, C.rng.range(0, 6), lean[0], lean[1]), h, rc, { broken: h < colH });
      pillars.push({ th, r, h, top: platY + bh + h });
      C.colliders.circles.push({ x: m.elements[12], z: m.elements[14], r: 0.5, y0: platY, h: h + bh, tag: 'column' });
    }
  }
  const yTop = platY + 0.34 + colH;
  for (const [t0, t1, kind] of BAYS) {
    const a = pos(t0, r0, yTop - 0.2), b = pos(t1, r0, yTop - 0.2);
    lintel(C, a, b, { cell: ORN.cloud });
    if (kind === 'beam') {
      // one end has dropped: the lintel hangs from the surviving column head
      continue;
    }
    const thM = (t0 + t1) / 2;
    const chord = a.distanceTo(b);
    if (kind === 'fallen') {
      // the bay's roof has slid off whole: a slab of tiles and rafters leaning from the court floor against the columns
      // (tiles toward the terrace: the eave has dug into the court's edge, the ridge leans on the column heads)
      const m = ringM(r0 + 0.85, thM * DEG, platY + 2.1, 0.06, 0.79, 0.1);
      const patch = addRoof(C, m, { eaveHalf: chord / 2 + 0.2, depth: 2.9, rise: 1.5, lift: 0.1, flare: 0, nu: 6, nt: 4, raft: 2, under: true, cut: (x, t) => noise3(x * 0.9, t * 3.0, 4.1) > 0.63, tone: 0.9 });
      addRidge(C, m, [patch.S(-1, 0), patch.S(-0.2, 0)].map((p) => p.clone()), { w: 0.3, h: 0.3 });
      continue;
    }
    C.P.section('gallery');
    // cross beams to the outer row, brackets on the inner heads, a purlin under the eave
    for (const th of [t0, t1]) {
      lintel(C, pos(th, r0, yTop - 0.24), pos(th, r1, yTop - 0.24), { h: 0.26, d: 0.2, cell: ORN.meander, color: C.lacquer(0.9) });
      bracketSet(C, at(th, r0, yTop), { s: 0.82, tiers: 1, blocks: false });
    }
    lintel(C, pos(t0, r1, yTop - 0.2), pos(t1, r1, yTop - 0.2), { cell: ORN.meander });
    const torn = kind === 'roofTorn';
    const rr = (r0 + r1) / 2, depth = rr - (r0 - 1.25), rise = 1.9;
    const m = ringM(rr, thM * DEG, yTop + 0.42);
    const half = (2 * rr * Math.sin((Math.abs(t1 - t0) / 2) * DEG)) / 2 + 0.25;
    const cut = torn ? (x, t) => x > 0.2 + 1.2 * noise3(t * 4, 1.5, 0.5) - t * 1.4 && t > 0.12 : () => false;
    const sag = torn ? (x, t) => -0.35 * smoothstep(-0.5, 1.5, x) * t : (x, t) => -0.06 * Math.sin((x / half) * 1.3 + 0.4) * t;
    const patch = addRoof(C, m, { eaveHalf: half, depth, rise, lift: 0.14, flare: 0, nu: 6, nt: 4, raft: C.tier.detail >= 1 ? 2 : 0, under: true, cut, sag });
    if (C.tier.detail >= 1) addRoof(C, T(m, 0, 0, 0, Math.PI), { eaveHalf: half, depth: depth * 0.8, rise, lift: 0.1, flare: 0, nu: 4, nt: 2, rows: false });
    addRidge(C, m, [patch.S(-1, 0).clone(), patch.S(0, 0).clone(), patch.S(torn ? 0.3 : 1, 0).clone()], { w: 0.32, h: 0.32 });
  }
  // a lintel hanging by one end (the 93-105 bay): it dropped off the far column and rests on the court
  {
    const a = pos(93, r0, yTop - 0.25), b = pos(104, r0 - 0.5, platY + 0.2);
    lintel(C, a, b, { cell: ORN.cloud });
  }
  return pillars;
}

// ---------------------------------------------------------------------------------------------------------------------
// the hall (천무전): five bays, a hipped tile roof whose south end has fallen in
// ---------------------------------------------------------------------------------------------------------------------

export function buildHall(C) {
  const { platY } = LAYOUT;
  const { th, front, bay, bays, porch, wall, depth, plinth, colH } = HALL;
  // local frame: origin at the plinth's front centre on the court, +Z toward the terrace, +X toward the vista (north)
  const base = ringM(front, th, platY);
  const L = (m, x, y, z, ...r) => T(m, x, y, z, ...r);
  const half = (bay * bays) / 2;           // 8 m to the end columns
  const pw = half + 1.7, pd = depth + 1.9; // plinth half width, depth
  const hi = C.tier.detail >= 2, mid = C.tier.detail >= 1;
  // local x < 0 (south) is the fallen end

  // ---- plinth (기단) and front steps -------------------------------------------------------------------------------
  C.S.section('hall');
  C.S.add(new THREE.BoxGeometry(pw * 2 - 0.2, plinth, pd - 0.1), L(base, 0, plinth / 2, -pd / 2 - 0.05), C.st(0.8, { uvScale: 2.6 }));
  for (let k = -3; k < 3; k++) {
    const x = (k + 0.5) * (pw * 2 / 6);
    const steps = Math.abs(x) < 2.7;
    if (steps) continue;
    const g = ashlar(pw * 2 / 6 - 0.03, plinth - 0.16, 0.3, 0.035, C.rng, 0.15, {});
    C.S.add(g, L(base, x, (plinth - 0.16) / 2, -0.15), C.st(C.blockTint(), { orn: { cell: k % 2 ? ORN.cloudPanel : ORN.wave, amount: C.erosion(), su: k % 2 ? 2 : 6, sv: k % 2 ? 1 : 1.4, fn: frontFace(pw * 2 / 6 - 0.03, plinth - 0.16) } }));
  }
  // cap stones along the front and the two visible ends
  const capProf = [[0, 0], [0.1, 0], [0.16, 0.06], [0.16, 0.16], [-0.6, 0.16]];
  for (const [a, b, side] of [[V(-pw, 0, 0), V(pw, 0, 0), V(0, 0, 1)], [V(pw, 0, -pd * 0.6), V(pw, 0, 0), V(1, 0, 0)], [V(-pw, 0, 0), V(-pw, 0, -pd * 0.6), V(-1, 0, 0)]]) {
    C.S.add(sweep(capProf, linePath(a.setY(plinth - 0.16), b.setY(plinth - 0.16), side, 1)), base, C.st(0.92, { uv: 'keep' }));
  }
  // steps: four risers between carved cheeks
  const sw = 5.0, rise = plinth / 4, run = 0.32;
  for (let k = 0; k < 4; k++) {
    C.S.add(chamferBox(sw, rise, run * (4 - k), 0.025, C.rng, 0.2), L(base, 0, rise * (k + 0.5), run * (4 - k) / 2), C.st(C.blockTint() * 0.95));
  }
  for (const s of [-1, 1]) {
    const g = prism([[0, 0], [run * 4 + 0.15, 0], [run * 4 + 0.15, 0.14], [0.1, plinth + 0.1], [0, plinth + 0.1]], 0.3);
    setOrnUv(g, (p, n) => (Math.abs(n.z) > 0.9 ? [p.x / 1.2, p.y / plinth, 1] : null));
    C.S.add(g, L(base, s * (sw / 2 + 0.15), 0, 0, ROT_X2Z), C.st(0.95, { orn: { cell: panel(ORN.cloud), amount: 0.9, su: 1, sv: 1 } }));
  }
  { const c = V(0, 0, -pd / 2).applyMatrix4(base); C.colliders.boxes.push({ x: c.x, z: c.z, hx: pw, hz: pd / 2, yaw: -th, y0: platY, h: plinth, tag: 'hall' }); }

  // ---- columns ------------------------------------------------------------------------------------------------------
  const yF = plinth;                       // hall floor (local)
  const rc = 0.27;
  const colX = [];
  for (let k = 0; k <= bays; k++) colX.push(-half + k * bay);
  const frontM = (x) => L(base, x, yF, -porch);
  const state = {};                        // front column state by index: undefined whole, 'lean', 'gone'
  state[0] = 'gone'; state[1] = 'lean';
  C.P.section('hall');
  let bh = 0.34;
  colX.forEach((x, k) => {
    const st = state[k];
    C.S.section('bases');
    bh = columnBase(C, frontM(x), rc);
    C.P.section('hall');
    if (st === 'gone') {
      // snapped at the foot; the shaft lies down the front steps of the court
      column(C, T(frontM(x), 0, bh, 0, 1.2), 0.7, rc, { broken: true });
      const fm = L(base, x + 1.4, 0.3, 1.9, 0.5, 0, Math.PI / 2 - 0.08);
      column(C, fm, 3.3, rc, { broken: true, band: false });
      return;
    }
    column(C, T(frontM(x), 0, bh, 0, C.rng.range(0, 6), st === 'lean' ? 0.07 : 0, st === 'lean' ? -0.09 : 0), colH, rc, {});
  });
  const yHead = yF + bh + colH;            // column heads
  // ---- wall line: posts, door leaves with lattice, a dark interior behind -------------------------------------------
  const zW = -wall;
  const doorH = 3.05, transom = colH + bh - doorH - 0.34;
  C.P.add(new THREE.BoxGeometry(half * 2 + 1.2, colH + bh + 0.6, 0.1), L(base, 0.4, yF + (colH + bh) / 2, zW - 1.4), C.wd([0.004, 0.004, 0.005], { uv: 'box' }));
  colX.forEach((x, k) => {
    if (x < -4.9) return;                  // the south end of the wall has gone with the roof
    C.P.add(beam(colH + bh, 0.3, 0.3, { ends: false }), L(base, x, yF + (colH + bh) / 2, zW, 0, 0, Math.PI / 2), C.wd(C.lacquer(0.95), { uv: 'keep', uvScale: 1.1 }));
  });
  for (let k = 0; k < bays; k++) {
    const xc = colX[k] + bay / 2;
    if (xc < -4.9) continue;
    const w = bay - 0.3;
    // threshold and head rails, a transom panel of brocade
    C.P.add(beam(w, 0.16, 0.26, { ends: false }), L(base, xc, yF + 0.08, zW), C.wd(C.lacquer(0.8), { uv: 'keep', uvScale: 1.1 }));
    C.P.add(beam(w, 0.2, 0.26, { ends: false, ornFace: true }), L(base, xc, yF + doorH + 0.26, zW), C.wd(C.jade(1), { uv: 'keep', uvScale: 1.1, orn: { cell: ORN.meander, amount: 0.9, su: 5, sv: 1 } }));
    C.P.add(beam(w, transom, 0.08, { ends: false, ornFace: true }), L(base, xc, yF + doorH + 0.36 + transom / 2, zW), C.wd(C.jade(0.9), { uv: 'keep', uvScale: 1.1, orn: { cell: ORN.brocade, amount: 0.8, su: 3, sv: 0.6 } }));
    // four leaves per bay; the centre bay stands open, others have lost or shed a leaf
    for (let j = 0; j < 4; j++) {
      const lw = w / 4;
      const x = xc - w / 2 + (j + 0.5) * lw;
      const open = (k === 2 && (j === 1 || j === 2)) || (k === 1 && j === 3) || (k === 4 && j === 0 && mid);
      const g = beam(doorH, lw - 0.02, 0.05, { ends: false, ornFace: 'both' });
      // beam runs along X: stand it up (rz = 90 deg) so the relief u runs up the leaf; swap through the mapping
      const o = C.wd(C.lacquer(0.85), { uv: 'keep', uvScale: 1.1, orn: { cell: ORN.lattice, amount: -1.0, su: 1, sv: 1 } });
      const leafOrn = (geo) => { const a = geo.attributes.ornUv; for (let i = 0; i < a.count; i++) { const u = a.getX(i), v = a.getY(i); a.setXY(i, v, u); } return geo; };
      if (open) {
        if (k === 2 && j === 1) C.P.add(leafOrn(g), L(base, x - lw / 2, yF + 0.16 + doorH / 2, zW - 0.36, 1.25, 0, Math.PI / 2), o);          // swung inward
        else if (k === 1) C.P.add(leafOrn(g), L(base, x + 0.3, yF + 0.07, zW + 1.1, 0.3, Math.PI / 2 - 0.02, Math.PI / 2 + 0.3), o);        // fallen flat on the porch
        continue;
      }
      const askew = k === 3 && j === 1 ? 0.08 : 0;
      C.P.add(leafOrn(g), L(base, x, yF + 0.16 + doorH / 2 - askew * 0.6, zW + 0.02, askew * 2, 0, Math.PI / 2 + askew), o);
    }
  }
  // ---- lintels, brackets, cross beams, the eave purlin ----------------------------------------------------------------
  const wp = (x, y, z) => V(x, y, z).applyMatrix4(base);
  for (let k = 1; k < bays; k++) {
    lintel(C, wp(colX[k], yHead - 0.2, -porch), wp(colX[k + 1], yHead - 0.2, -porch), { cell: k % 2 ? ORN.dragon : ORN.cloud });
  }
  // the lintel of the fallen bay hangs down from the leaning column
  lintel(C, wp(colX[1] + 0.2, yHead - 0.5, -porch + 0.25), wp(colX[0] + 0.9, yF + 1.0, -porch + 1.3), { cell: ORN.cloud });
  let bk = 0.7;
  colX.forEach((x, k) => {
    if (state[k]) return;
    bk = bracketSet(C, L(base, x, yHead, -porch), { s: 1, tiers: 2, blocks: mid });
    lintel(C, wp(x, yHead - 0.26, -porch), wp(x, yHead - 0.26, zW), { h: 0.28, d: 0.22, cell: ORN.meander, color: C.lacquer(0.9) });
  });
  const yEave = yHead + bk + 0.02;
  {
    // eave purlin (도리): a round timber over the outer bracket arms
    const pts = [V(colX[2] - 1.2, yEave - 0.05, -porch + 0.95), V(colX[bays] + 1.6, yEave - 0.05, -porch + 0.95)];
    C.P.add(tube(pts, 0.13, { sides: 6, caps: true }), base, C.wd(C.lacquer(0.8)));
  }

  // ---- the roof: hipped, the south end collapsed --------------------------------------------------------------------
  const a = half + 3.4, b = (depth - porch) / 2 + porch + 0.35, ar = a - b * 0.82, H = 4.5;
  const zR = -(porch + (depth - porch) / 2);   // ridge line
  const roofM = L(base, 0, yEave + 0.1, zR);
  const brk = -3.6;                            // the break: everything south of ~x = brk is gone
  const edge = (t) => brk + 1.5 * (noise3(t * 5, 0.3, 7.7) - 0.5) + 2.2 * (t - 0.5) * (t - 0.5);
  const cut = (x, t) => x < edge(t);
  const sag = (x, t) => -1.25 * smoothstep(brk + 5.5, brk, x) * (0.35 + 0.65 * t) - 0.1 * Math.sin(x * 0.5) * t;
  const fr = addRoof(C, roofM, { eaveHalf: a, ridgeHalf: ar, depth: b, rise: H, lift: 0.85, flare: 0.5, nu: hi ? 22 : 16, nt: hi ? 6 : 5, pitch: mid ? 0.36 : 0.5, raft: mid ? 2 : 3, under: true, cut, sag });
  addRoof(C, T(roofM, 0, 0, 0, Math.PI), { eaveHalf: a, ridgeHalf: ar, depth: b, rise: H, lift: 0.85, flare: 0.5, nu: 10, nt: 3, rows: false, cut: (x, t) => -x < edge(t), sag: (x, t) => sag(-x, t) });
  // north hip end (toward the vista: the corner the duel camera sees)
  const endM = T(roofM, ar, 0, 0, ROT_X2Z + Math.PI);
  addRoof(C, endM, { eaveHalf: b, ridgeHalf: 0, depth: a - ar, rise: H, lift: 0.85, flare: 0.5, nu: hi ? 12 : 8, nt: hi ? 6 : 5, pitch: mid ? 0.36 : 0.5, raft: mid ? 2 : 0, under: true });
  // ridges: the main ridge runs from the break (sagging) to the north end; two hip ridges with upturned tips
  const rp = [];
  for (let i = 0; i <= 6; i++) { const u = (brk + 0.8) / ar + (1 - (brk + 0.8) / ar) * (i / 6); rp.push(fr.S(u, 0).clone()); }
  addRidge(C, roofM, rp, { w: 0.42, h: 0.5 });
  ridgeHorn(C, T(roofM, ar - 0.1, H + 0.42 + sag(ar, 0), 0), 1.2);
  for (const s of [1, -1]) {
    const pts = fr.hipR.map((p) => p.clone());
    if (s < 0) for (const p of pts) p.z = -p.z;
    addRidge(C, roofM, pts, { w: 0.34, h: 0.36, tip: 0.3 });
  }

  // ---- the collapse: rafters and beams fanned down from the break, a tile scree over the plinth and into the court ----
  C.P.section('hallwreck');
  const nWreck = hi ? 9 : mid ? 6 : 4;
  for (let k = 0; k < nWreck; k++) {
    const x = brk - 0.6 - k * 0.75 + C.rng.range(-0.3, 0.3);
    const top = wp(x + C.rng.range(0.6, 2.2), yEave + 0.2 + C.rng.range(-0.6, 1.6), C.rng.range(-5.5, -1.6));
    const foot = wp(x - C.rng.range(0.3, 1.6), yF + C.rng.range(0.1, 0.5), C.rng.range(-3.0, 1.2));
    lintel(C, top, foot, { h: k % 3 === 0 ? 0.34 : 0.14, d: k % 3 === 0 ? 0.28 : 0.14, cell: ORN.meander, color: k % 3 === 0 ? C.lacquer(0.7) : C.bare(0.8) });
  }
  // a slab of roof that came down whole, tilted against the wreck
  {
    const m = L(base, brk - 3.4, yF + 2.3, -3.3, 0.3, 0.72, 0.2);
    addRoof(C, m, { eaveHalf: 2.6, depth: 3.4, rise: 1.6, lift: 0.2, flare: 0.1, nu: 6, nt: 4, raft: mid ? 2 : 0, under: true, cut: (x, t) => noise3(x * 0.8, t * 3, 2.2) > 0.66, tone: 0.9 });
  }
  C.S.section('hallwreck');
  const scree = Math.round((hi ? 46 : mid ? 30 : 16));
  for (let k = 0; k < scree; k++) {
    // tile shards and plaster lumps: thick on the plinth, thinning down its front and over the court edge
    const u = C.rng(), v = Math.pow(C.rng(), 1.6);
    const x = brk - 0.5 - u * 6.5, z = -3.5 + v * 7.5;
    const onPlinth = z < 0;
    const y = onPlinth ? yF : z < 1.3 ? plinth * (1 - z / 1.3) * 0.5 : 0;
    const s = C.rng.range(0.1, 0.34);
    const g = C.rng.chance(0.55) ? chamferBox(s * 2.0, s * 0.35, s * 1.3, 0.02, C.rng, 0.6) : rock(s * 0.8, C.rng, { detail: 0, squash: 0.5 });
    C.S.add(g, L(base, x, y + s * 0.2, z, C.rng.range(0, 6), C.rng.range(-0.5, 0.5), C.rng.range(-0.5, 0.5)), { color: tileColor(C, C.rng.range(0.7, 1.2)), glow: C.glow, uv: 'box', uvScale: 1.7 });
  }
  // some of it went over the balustrade: tile shards on the terrace floor at the wall foot, two timbers down there
  const over = hi ? 14 : mid ? 9 : 5;
  const fz = front - LAYOUT.wallR;              // local z of the wall face
  for (let k = 0; k < over; k++) {
    const x = brk - 0.8 - C.rng() * 5.2, z = fz + 0.25 + Math.pow(C.rng(), 1.5) * 1.9;
    const s = C.rng.range(0.1, 0.3);
    C.S.add(chamferBox(s * 2.0, s * 0.3, s * 1.3, 0.02, C.rng, 0.6), L(base, x, -platY + s * 0.1, z, C.rng.range(0, 6), C.rng.range(-0.3, 0.3), C.rng.range(-0.3, 0.3)), { color: tileColor(C, C.rng.range(0.7, 1.2)), glow: C.glow, uv: 'box', uvScale: 1.7 });
  }
  C.P.section('hallwreck');
  lintel(C, wp(brk - 2.2, 0.55, fz - 0.9), wp(brk - 3.1, -platY + 0.12, fz + 2.3), { h: 0.3, d: 0.26, cell: ORN.cloud });
  if (mid) lintel(C, wp(brk - 5.4, -platY + 0.1, fz + 0.7), wp(brk - 2.9, -platY + 0.16, fz + 1.5), { h: 0.16, d: 0.16, cell: ORN.meander, color: C.bare(0.8) });
  return { base, yEave: platY + yEave, ridgeY: platY + yEave + 0.1 + H };
}

// ---------------------------------------------------------------------------------------------------------------------
// the mountain gate (산문) and the boundary wall (담장)
// ---------------------------------------------------------------------------------------------------------------------

export function buildGate(C) {
  const { platY } = LAYOUT;
  const { th, line, colH, halfBay, wing } = GATE;
  const hi = C.tier.detail >= 2, mid = C.tier.detail >= 1;
  // local frame: origin on the column line at court level, +Z toward the terrace, +X toward the west
  const base = ringM(line, th, platY);
  const wp = (x, y, z) => V(x, y, z).applyMatrix4(base);
  const rc = 0.31;
  const xs = [-wing, -halfBay, halfBay, wing];
  let bh = 0.5;
  // the east wing post (local -X) has sunk and leans; the roof corner above it has shed its tiles
  const lean = { 0: [0.05, 0.085] };
  xs.forEach((x, k) => {
    C.S.section('bases');
    bh = columnBase(C, T(base, x, 0, 0), rc, 0.5);
    C.P.section('gate');
    const l = lean[k] || [0, 0];
    column(C, T(base, x, bh, 0, C.rng.range(0, 6), l[0], l[1]), colH, rc, { segs: hi ? 14 : 12 });
    C.colliders.circles.push({ x: wp(x, 0, 0).x, z: wp(x, 0, 0).z, r: 0.62, y0: platY, h: colH, tag: 'gate' });
  });
  const yHead = bh + colH;
  C.S.section('gate');
  // stone sill across the centre bay
  C.S.add(chamferBox(halfBay * 2 - 0.7, 0.2, 0.5, 0.03, C.rng, 0.2), T(base, 0, 0.1, 0), C.st(0.9));
  C.P.section('gate');
  // two tiers of lintels across all four posts, panels of dragons between them
  for (let k = 0; k < 3; k++) {
    const x0 = xs[k], x1 = xs[k + 1];
    const drop = k === 0 ? 0.18 : 0;
    lintel(C, wp(x0, yHead - 0.22 - drop, 0), wp(x1, yHead - 0.22, 0), { h: 0.34, d: 0.26, cell: k === 1 ? ORN.dragon : ORN.cloud });
    lintel(C, wp(x0, yHead - 1.3 - drop, 0), wp(x1, yHead - 1.3, 0), { h: 0.3, d: 0.24, cell: ORN.meander, color: C.lacquer(0.95) });
    const w = Math.abs(x1 - x0) - 0.66;
    C.P.add(beam(w, 0.7, 0.07, { ends: false, ornFace: 'both' }), T(base, (x0 + x1) / 2, yHead - 0.76 - drop / 2, 0), C.wd(C.jade(0.85), { uv: 'keep', uvScale: 1.1, orn: { cell: k === 1 ? ORN.brocade : ORN.wave, amount: 0.85, su: Math.round(w / 0.7), sv: 1 } }));
  }
  // the wing bays are boarded; a studded leaf of the great door stands swung back against the west wing
  for (const k of [0, 2]) {
    const x0 = xs[k], x1 = xs[k + 1], w = Math.abs(x1 - x0) - 0.66, hgt = yHead - 1.5;
    const g = beam(w, hgt, 0.07, { ends: false, ornFace: 'both' });
    C.P.add(g, T(base, (x0 + x1) / 2, hgt / 2 + 0.04, 0), C.wd(C.lacquer(0.7), { uv: 'keep', uvScale: 1.1, orn: { cell: ORN.plank, amount: -0.9, su: Math.round(w / 1.1), sv: 1 } }));
  }
  {
    const lw = halfBay - 0.34, lh = yHead - 1.55;
    const g = beam(lw, lh, 0.09, { ends: true, ornFace: 'both' });
    C.P.add(g, T(base, halfBay + 0.12, lh / 2 + 0.2, 0.1 + lw / 2 - 0.05, ROT_X2Z + 0.22, 0, 0.03), C.wd(C.lacquer(0.8), { uv: 'keep', uvScale: 1.1, orn: { cell: ORN.studs, amount: -1.1, su: 2, sv: 4 } }));
  }
  let bk = 0.7;
  xs.forEach((x, k) => {
    const d = k === 0 ? -0.18 : 0;
    bk = bracketSet(C, T(base, x, yHead + d, 0), { s: 1.05, tiers: 2, blocks: mid });
    if (mid) bracketSet(C, T(base, x, yHead + d, 0, Math.PI), { s: 1.05, tiers: 1, blocks: false });
  });
  const yEave = yHead + bk + 0.05;
  C.P.add(tube([V(-wing - 1.9, yEave - 0.08, 0.98), V(wing + 1.9, yEave - 0.08, 0.98)], 0.14, { sides: 6, caps: true }), base, C.wd(C.lacquer(0.8)));

  // ---- roof: a broad gable over deep eaves, the east corner stripped and sagging ----------------------------------------
  const a = wing + 2.75, b = 3.75, H = 3.0;
  const roofM = T(base, 0, yEave + 0.08, 0);
  const cut = (x, t) => x < -a + 2.7 - 2.0 * (1 - t) + 0.9 * noise3(x * 0.9, t * 4, 3.3) && t > 0.25;
  const sag = (x, t) => -0.5 * smoothstep(-a + 4.2, -a, x) * t - 0.05 * Math.sin(x * 0.7) * t;
  const front = addRoof(C, roofM, { eaveHalf: a, depth: b, rise: H, lift: 0.5, flare: 0.22, nu: hi ? 16 : 12, nt: hi ? 6 : 5, pitch: mid ? 0.36 : 0.5, raft: mid ? 2 : 3, under: true, cut, sag });
  addRoof(C, T(roofM, 0, 0, 0, Math.PI), { eaveHalf: a, depth: b, rise: H, lift: 0.5, flare: 0.22, nu: 8, nt: 3, rows: false, under: mid });
  const rp = [];
  for (let i = 0; i <= 6; i++) rp.push(front.S(-1 + (2 * i) / 6, 0).clone().add(V(0, i === 0 || i === 6 ? 0.22 : 0, 0)));
  addRidge(C, roofM, rp, { w: 0.44, h: 0.52 });
  ridgeHorn(C, T(roofM, a - 0.15, H + 0.55, 0), 1.25);
  ridgeHorn(C, T(roofM, -a + 0.15, H + 0.55, 0, Math.PI), 1.25);
  // bargeboards closing the gables
  C.P.section('gate');
  for (const s of [-1, 1]) {
    const g = prism([[-b + 0.5, 0.1], [b - 0.5, 0.1], [0, H - 0.25]], 0.09);
    setOrnUv(g, (p, n) => (Math.abs(n.z) > 0.9 ? [p.x / 1.4, p.y / 1.4, 1] : null));
    C.P.add(g, T(roofM, s * (a - 0.5), 0, 0, ROT_X2Z), C.wd(C.lacquer(0.75), { uv: 'box', orn: { cell: ORN.plank, amount: -0.8, su: 1, sv: 1 } }));
  }

  // ---- the name board 「天武」: a tall board that has slipped one hanger and hangs askew over the doorway ------------------
  C.P.section('nameboard');
  {
    const bw = 1.3, bhgt = 2.6;
    const m = T(base, 0.18, yHead - 0.55, 0.42, 0, 0.16, -0.13);
    C.P.add(beam(bw, bhgt, 0.08, { ends: true, ornFace: true }), m, C.wd(PALETTE.ink, { uv: 'keep', uvScale: 1.1, orn: { cell: ORN.plank, amount: -0.5, su: 1, sv: 1 } }));
    // frame: jade rails with a painted meander, splayed outward
    for (const [x, y, w, h, r] of [[0, bhgt / 2 + 0.03, bw + 0.3, 0.17, 0], [0, -bhgt / 2 - 0.03, bw + 0.3, 0.17, 0], [-bw / 2 - 0.03, 0, bhgt + 0.1, 0.17, Math.PI / 2], [bw / 2 + 0.03, 0, bhgt + 0.1, 0.17, Math.PI / 2]]) {
      C.P.add(beam(w, h, 0.13, { ends: true, ornFace: true }), T(m, x, y, 0.03, 0, 0, r), C.wd(C.jade(1.1), { uv: 'keep', uvScale: 1.1, orn: { cell: ORN.meander, amount: 1, su: Math.round(w / 0.3), sv: 1 } }));
    }
    // the characters: carved, gilded once
    for (const [cell, y] of [[ORN.tian, 0.6], [ORN.mu, -0.62]]) {
      C.P.add(beam(1.08, 1.08, 0.03, { ends: false, ornFace: true }), T(m, 0, y, 0.045), C.wd(PALETTE.ink, { uv: 'keep', uvScale: 1.1, orn: { cell, amount: 1.25, su: 1, sv: 1 } }));
    }
    // hangers: one chain still holds the west corner, the other dangles from the lintel
    C.M.section('fittings');
    const hook = wp(0.72, yHead - 0.1, 0.3), corner = V(bw / 2, bhgt / 2 + 0.1, 0.02).applyMatrix4(m);
    C.M.add(tube([hook, hook.clone().lerp(corner, 0.5).add(V(0, -0.02, 0.03)), corner], 0.018, { sides: 4 }), new THREE.Matrix4(), C.mt(C.iron(1)));
    const h2 = wp(-0.6, yHead - 0.1, 0.3);
    C.M.add(tube([h2, h2.clone().add(V(0.02, -0.5, 0.02)), h2.clone().add(V(0.05, -0.95, 0.0))], 0.018, { sides: 4 }), new THREE.Matrix4(), C.mt(C.iron(1)));
  }

  // ---- the boundary wall (담장): rubble stone under a tile coping, running from the wing posts round to the gallery -------
  C.S.section('wall');
  const wallH = 2.5, wallT = 0.55;
  const run = (pts) => {
    for (let i = 0; i < pts.length - 1; i++) {
      const p0 = pts[i], p1 = pts[i + 1];
      const len = Math.hypot(p1.x - p0.x, p1.z - p0.z);
      const yaw = Math.atan2(-(p1.z - p0.z), p1.x - p0.x);
      const n = Math.max(1, Math.round(len / 2.6));
      for (let k = 0; k < n; k++) {
        const t = (k + 0.5) / n;
        const x = p0.x + (p1.x - p0.x) * t, z = p0.z + (p1.z - p0.z) * t;
        const brokenSeg = C.rng.chance(0.22);
        const h = brokenSeg ? wallH * C.rng.range(0.35, 0.8) : wallH;
        const g = brokenSeg ? brokenBlock(len / n, h, wallT, C.rng, { jag: 0.3, nx: 3, nz: 1 }) : new THREE.BoxGeometry(len / n + 0.02, h, wallT);
        const m = trs(x, platY + h / 2, z, yaw);
        C.S.add(g, m, C.st(C.blockTint() * 0.8, { uvScale: 1.4 }));
        if (!brokenSeg) {
          const a0 = V(-len / n / 2, wallH / 2, 0), a1 = V(len / n / 2, wallH / 2, 0);
          C.S.add(ridge([a0, a1], { w: 0.86, h: 0.3 }), m, { color: tileColor(C, 0.9), glow: C.glow, uv: 'keep', uvScale: 1.7, orn: { cell: ORN.tile, amount: 0.9, su: 3, sv: 1 } });
        }
        C.colliders.boxes.push({ x, z, hx: len / n / 2, hz: wallT / 2, yaw, y0: platY, h, tag: 'wall' });
      }
    }
  };
  for (const s of [-1, 1]) {
    const pts = [wp(s * (wing + 0.5), 0, 0)];
    pts.push(wp(s * (wing + 4.2), 0, 0.0));
    for (const deg of [155, 147, 139, 131, 124]) { const tt = s * deg * DEG; pts.push(V(Math.sin(-tt) * 23.2, 0, -Math.cos(tt) * 23.2)); }
    run(pts);
  }
  return { base, yEave: platY + yEave, ridgeY: platY + yEave + 0.08 + H };
}
