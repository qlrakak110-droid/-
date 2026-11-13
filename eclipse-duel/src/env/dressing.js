// Set dressing of 「천무대」, merged into the shared builders (no draw calls of its own): stone lanterns (석등:
// standing and lit, leaning, toppled), bronze incense braziers (향로) on lotus drums, weapon racks, the sect's
// stele, a war drum, banner poles, talisman ropes, spilled roof tiles. Returns what the moving layers need: flames
// for the fire mesh, smoke sources, cloth specs (banners, pennants, talismans).

import * as THREE from 'three';
import { DEG } from '../core/math.js';
import { chamferBox, latheGrid, addAll, trs, noise3, tube, setOrnUv, brokenBlock, beam, prism, flatNormals, ringM, rock, frontFace } from './geometry.js';
import { LAYOUT, PALETTE, HALL, GATE, rimR } from './config.js';
import { ORN, panel } from './ornament.js';
import { CLOTH } from './bake.js';

const V = (x, y, z) => new THREE.Vector3(x, y, z);
const T = (m, x, y, z, ry = 0, rx = 0, rz = 0, s = 1) => m.clone().multiply(trs(x, y, z, ry, rx, rz, s));
const ringPos = (r, th, y = 0) => V(r * Math.sin(th), y, -r * Math.cos(th));

/** The roof stone of a lantern (옥개석): a square hipped cap, concave slopes, lifted corners. Flat shaded. */
function lanternCap(w, h) {
  const out = [];
  const P = (side, u, t) => {
    const d = 0.06 + (w / 2 - 0.06) * t;
    const x = u * d, z = d, y = h * Math.pow(1 - t, 1.7) + 0.15 * w * Math.abs(u * u * u) * t * t;
    const c = Math.cos(side * Math.PI / 2), s = Math.sin(side * Math.PI / 2);
    return [x * c + z * s, y, -x * s + z * c];
  };
  for (let side = 0; side < 4; side++) for (let j = 0; j < 2; j++) for (let i = 0; i < 3; i++) {
    const u0 = -1 + (2 * i) / 3, u1 = -1 + (2 * (i + 1)) / 3, t0 = j / 2, t1 = (j + 1) / 2;
    const a = P(side, u0, t0), b = P(side, u1, t0), c = P(side, u1, t1), e = P(side, u0, t1);
    out.push(...a, ...e, ...c, ...a, ...c, ...b);
  }
  // underside
  const y = -0.07, k = w / 2;
  out.push(-k, y, -k, k, y, -k, k, y, k, -k, y, -k, k, y, k, -k, y, k);
  for (let side = 0; side < 4; side++) {
    const a = P(side, -1, 1), b = P(side, 1, 1);
    out.push(a[0], y, a[2], b[0], y, b[2], b[0], b[1], b[2], a[0], y, a[2], b[0], b[1], b[2], a[0], a[1], a[2]);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(out, 3));
  return flatNormals(g);
}

/**
 * A stone lantern (석등). `m`: foot on the ground. `state`: 'lit' | 'dark' | 'lean' | 'toppled'.
 * @returns {THREE.Vector3|null} world position of the flame (lit / leaning lanterns)
 */
function lantern(C, m, state = 'lit', s = 1) {
  const { S, rng } = C;
  const tint = C.blockTint() * 1.05;
  const st = (extra) => C.st(tint, extra);
  const toppled = state === 'toppled';
  const body = state === 'lean' ? T(m, 0, -0.04, 0, 0, 0.07, -0.09, s) : T(m, 0, 0, 0, 0, 0, 0, s);
  // foot slab, lotus foot, octagonal shaft with a girdle
  S.add(chamferBox(0.84, 0.16, 0.84, 0.03, rng, 0.3), T(body, 0, 0.08, 0), st());
  const foot = latheGrid({ rows: 3, segs: 8, profile: (t) => [0.4 - 0.2 * Math.pow(t, 0.7), 0.16 + t * 0.26] });
  setOrnUv(foot[0], (p, n, i) => [((i % 9) / 8) * 8, 1 - (p.y - 0.16) / 0.26, 1]);
  addAll(S, foot, body, st({ orn: { cell: ORN.petal, amount: C.erosion(), su: 1, sv: 1 } }));
  const shaftH = toppled ? 0.4 : 0.76;
  const shaft = latheGrid({ rows: toppled ? 1 : 3, segs: 8, profile: (t) => [0.145 + (Math.abs(t - 0.5) < 0.18 && !toppled ? 0.035 : 0), 0.42 + t * shaftH], topY: toppled ? (phi) => 0.42 + shaftH - Math.abs(Math.sin(phi * 1.5 + 1)) * 0.22 : null, capTop: toppled ? 0.42 + shaftH - 0.15 : false });
  addAll(S, shaft.map((g) => flatNormals(g.index ? g.toNonIndexed() : g)), body, st());
  if (toppled) C.colliders.circles.push({ x: body.elements[12], z: body.elements[14], r: 0.5, y0: body.elements[13], h: 0.8, tag: 'lantern' });
  else C.colliders.circles.push({ x: body.elements[12], z: body.elements[14], r: 0.52, y0: body.elements[13], h: 2.4 * s, tag: 'lantern' });
  // the head: lotus bowl, fire chamber (four posts between two slabs), roof stone, bud
  const head = toppled ? T(m, 0.95 * s, 0.3 * s, 0.35 * s, 0.6, 0.2, Math.PI / 2 + 0.25, s).multiply(trs(0, -1.5, 0)) : body;
  const bowl = latheGrid({ rows: 3, segs: 8, profile: (t) => [0.16 + 0.21 * Math.pow(t, 0.75), 1.18 + t * 0.22], capBottom: toppled });
  setOrnUv(bowl[0], (p, n, i) => [((i % 9) / 8) * 8, (p.y - 1.18) / 0.22, 1]);
  addAll(S, bowl, head, st({ orn: { cell: ORN.petal, amount: C.erosion(), su: 1, sv: 1 } }));
  S.add(new THREE.BoxGeometry(0.64, 0.07, 0.64), T(head, 0, 1.435, 0), st());
  for (const [x, z] of [[-1, -1], [1, -1], [1, 1], [-1, 1]]) S.add(new THREE.BoxGeometry(0.1, 0.42, 0.1), T(head, x * 0.24, 1.68, z * 0.24), st());
  S.add(new THREE.BoxGeometry(0.64, 0.07, 0.64), T(head, 0, 1.925, 0), st());
  const capM = toppled ? T(m, -0.7 * s, 0.2 * s, 0.9 * s, 1.1, 0.5, 0.2, s) : T(head, 0, 2.03, 0);
  S.add(lanternCap(1.02, 0.42), capM, st({ uvScale: 1.6 }));
  const bud = latheGrid({ rows: 4, segs: 6, profile: (t) => [t < 0.2 ? 0.07 : 0.04 + 0.085 * Math.sin(Math.pow((t - 0.2) / 0.8, 0.8) * Math.PI), 0.38 + t * 0.26], capTop: true });
  addAll(S, bud, capM, st());
  if (state === 'lit' || state === 'lean') return V(0, 1.6, 0).applyMatrix4(body);
  return null;
}

/**
 * A bronze incense brazier (향로) on a lotus drum. `m`: foot on the ground.
 * @returns {{ fire: THREE.Vector3, sticks: THREE.Vector3[] }} bowl centre (ash level) and glowing incense tips
 */
function censer(C, m, s = 1) {
  const { S, M, rng } = C;
  const tint = C.blockTint();
  // stone drum: an octagonal block between two petal rings
  const drum = latheGrid({ rows: 5, segs: 8, profile: (t) => [t < 0.2 ? 0.62 - 0.4 * t : t > 0.8 ? 0.54 + 0.4 * (t - 0.8) : 0.5, t * 0.5], capTop: true });
  setOrnUv(drum[0], (p, n, i) => [((i % 9) / 8) * 8, p.y < 0.1 ? 1 - p.y / 0.1 : p.y > 0.4 ? (p.y - 0.4) / 0.1 : -1, p.y < 0.1 || p.y > 0.4 ? 1 : 0]);
  addAll(S, drum, T(m, 0, 0, 0, 0, 0, 0, s), C.st(tint, { orn: { cell: ORN.petal, amount: C.erosion(), su: 1, sv: 1 } }));
  const mm = T(m, 0, 0.5 * s, 0, rng.range(0, 6), 0, 0, s);
  // cauldron: foot ring, belly with a band of flames, neck, flared rim with an inner lip
  const prof = [[0.2, 0.3], [0.34, 0.3], [0.5, 0.4], [0.57, 0.56], [0.55, 0.7], [0.46, 0.82], [0.46, 0.88], [0.6, 0.96], [0.6, 1.0], [0.5, 1.0], [0.47, 0.9]];
  const body = latheGrid({ rows: prof.length - 1, segs: 16, profile: (t) => { const k = Math.min(prof.length - 1, Math.round(t * (prof.length - 1))); return prof[k]; } });
  setOrnUv(body[0], (p, n, i) => [((i % 17) / 16) * 8, (p.y - 0.4) / 0.3, p.y > 0.39 && p.y < 0.71 ? 1 : 0]);
  addAll(M, body, mm, C.mt(C.bronze(1), { orn: { cell: ORN.flame, amount: 1.0, su: 1, sv: 1 } }));
  // three beast legs, two upright ears
  for (let k = 0; k < 3; k++) {
    const a = (k / 3) * Math.PI * 2 + 0.5;
    const c = Math.cos(a), sn = Math.sin(a);
    addAll(M, [tube([V(c * 0.42, 0.42, sn * 0.42), V(c * 0.56, 0.24, sn * 0.56), V(c * 0.5, 0.06, sn * 0.5), V(c * 0.56, 0.0, sn * 0.56)], (t) => 0.085 - 0.03 * t, { sides: 5, caps: true })], mm, C.mt(C.bronze(0.9)));
  }
  for (const sx of [-1, 1]) {
    const pts = [];
    for (let i = 0; i <= 6; i++) { const a = (i / 6) * Math.PI; pts.push(V(sx * 0.58, 0.98 + Math.sin(a) * 0.24, Math.cos(a) * 0.15)); }
    addAll(M, [tube(pts, 0.032, { sides: 4 })], mm, C.mt(C.bronze(0.9)));
  }
  // ash and incense sticks
  const ash = latheGrid({ rows: 1, segs: 12, profile: (t) => [0.47 * (1 - t), 0.9 + t * 0.06], capTop: true });
  addAll(S, ash, mm, { color: [0.75, 0.72, 0.68], glow: () => 0, uv: 'box' });
  const sticks = [];
  for (let k = 0; k < 7; k++) {
    const a = rng.range(0, 6.28), d = rng.range(0.02, 0.3);
    const p0 = V(Math.cos(a) * d, 0.93, Math.sin(a) * d), p1 = p0.clone().add(V(rng.range(-0.05, 0.05), rng.range(0.16, 0.32), rng.range(-0.05, 0.05)));
    addAll(C.P, [tube([p0, p1], 0.006, { sides: 3 })], mm, C.wd([0.09, 0.03, 0.02]));
    if (k < 4) sticks.push(p1.clone().applyMatrix4(mm));
  }
  C.colliders.circles.push({ x: mm.elements[12], z: mm.elements[14], r: 0.75 * s, y0: mm.elements[13] - 0.5 * s, h: 1.5 * s, tag: 'censer' });
  return { fire: V(0, 0.98, 0).applyMatrix4(mm), sticks };
}

/** Weapon rack (병기대) with polearms and sabres leaning in it. `m`: centre of its foot line, facing +Z. */
function weaponRack(C, m, { toppled = false, count = 5 } = {}) {
  const { P, M, rng } = C;
  const wood = C.wd(C.bare(0.8), { uv: 'keep', uvScale: 1.1 });
  const base = toppled ? T(m, 0, 0.12, 0, 0, Math.PI / 2 - 0.12, 0.08) : m;
  for (const sx of [-1, 1]) {
    P.add(beam(1.75, 0.1, 0.1), T(base, sx * 0.95, 0.875, 0, 0, 0, Math.PI / 2), wood);
    P.add(beam(0.9, 0.1, 0.12), T(base, sx * 0.95, 0.05, 0, Math.PI / 2), wood);
  }
  for (const y of [0.5, 1.5]) P.add(beam(2.1, 0.09, 0.07, { ornFace: 'both' }), T(base, 0, y, 0), C.wd(C.lacquer(0.7), { uv: 'keep', uvScale: 1.1, orn: { cell: ORN.meander, amount: 0.8, su: 7, sv: 1 } }));
  const iron = C.mt(C.iron(1.2));
  for (let k = 0; k < count; k++) {
    const x = -0.75 + (1.5 * k) / Math.max(1, count - 1) + rng.range(-0.05, 0.05);
    const kind = k % 3;
    const lean = rng.range(0.1, 0.2), roll = rng.range(-0.08, 0.08);
    const wm = T(base, x, 0.02, 0.3, rng.range(-0.3, 0.3), -lean, roll);
    if (kind === 0) {
      // spear: ash shaft, leaf head, a red horsehair tassel
      const L = rng.range(2.3, 2.7);
      addAll(P, [tube([V(0, 0, 0), V(0, L, 0)], 0.019, { sides: 5, caps: true })], wm, C.wd(C.bare(0.6)));
      addAll(M, latheGrid({ rows: 3, segs: 4, squash: 0.28, profile: (t) => [0.055 * Math.sin((1 - t) * Math.PI * 0.82 + 0.25), L + t * 0.36], capTop: true }), wm, iron);
      addAll(P, latheGrid({ rows: 2, segs: 5, profile: (t) => [0.02 + 0.045 * Math.sin(t * Math.PI * 0.7), L - 0.22 + t * 0.2] }), wm, C.wd([0.16, 0.02, 0.015]));
    } else if (kind === 1) {
      // glaive: a broad curved blade on a long shaft
      const L = rng.range(1.9, 2.2);
      addAll(P, [tube([V(0, 0, 0), V(0, L, 0)], 0.022, { sides: 5, caps: true })], wm, C.wd(C.bare(0.55)));
      const g = prism([[-0.03, 0], [0.03, 0], [0.12, 0.3], [0.13, 0.52], [0.02, 0.78], [-0.04, 0.5]], 0.014);
      M.add(g, T(wm, 0, L, 0, rng.range(-0.4, 0.4)), iron);
      M.add(new THREE.BoxGeometry(0.1, 0.035, 0.05), T(wm, 0, L, 0), C.mt(C.bronze(0.8)));
    } else {
      // sabre in a lacquered scabbard, hung by its guard on the upper rail
      const g = prism([[-0.03, 0], [0.03, 0], [0.05, 0.4], [0.1, 0.78], [0.05, 0.8], [-0.01, 0.42]], 0.03);
      P.add(g, T(base, x, 0.72, 0.07, rng.range(-0.2, 0.2), 0, Math.PI + rng.range(-0.1, 0.1)), C.wd(C.lacquer(0.6)));
      M.add(new THREE.BoxGeometry(0.12, 0.03, 0.07), T(base, x, 1.5, 0.07), C.mt(C.bronze(0.8)));
      addAll(P, [tube([V(0, 0, 0), V(0, 0.22, 0)], 0.018, { sides: 5, caps: true })], T(base, x, 1.52, 0.07, 0, 0, rng.range(-0.1, 0.1)), C.wd(C.bare(0.5)));
    }
  }
  const c = V(0, 0, 0).applyMatrix4(m);
  const yaw = Math.atan2(-m.elements[2], m.elements[0]);
  C.colliders.boxes.push({ x: c.x, z: c.z, hx: 1.15, hz: toppled ? 1.0 : 0.5, yaw, y0: c.y, h: toppled ? 0.4 : 1.8, tag: 'rack' });
}

/** The sect's stele (비석): 天武 over a band of seal script, the crest in its rounded head. `m`: foot, facing +Z. */
function stele(C, m) {
  const { S, rng } = C;
  const tint = C.blockTint() * 1.05;
  S.add(chamferBox(1.5, 0.36, 0.8, 0.04, rng, 0.3), T(m, 0, 0.18, 0), C.st(tint * 0.9, { orn: { cell: ORN.wave, amount: 0.9, su: 3, sv: 1, fn: frontFace(1.5, 0.36) } }));
  const w = 0.98, h = 2.25;
  const pts = [[-w / 2, 0], [w / 2, 0], [w / 2, h - 0.34]];
  for (let i = 1; i < 6; i++) { const a = (i / 6) * Math.PI; pts.push([Math.cos(a) * w / 2, h - 0.34 + Math.sin(a) * 0.34]); }
  pts.push([-w / 2, h - 0.34]);
  const g = prism(pts, 0.24);
  const lean = trs(0, 0.36, 0, 0, -0.045, 0.02);
  S.add(g, m.clone().multiply(lean), C.st(tint));
  // the inscription rides on shallow tablets let into the face
  const face = (cell, y, hh, amount, ww = 0.7) => {
    const f = new THREE.BoxGeometry(ww, hh, 0.02);
    setOrnUv(f, frontFace(ww, hh));
    S.add(f, m.clone().multiply(lean).multiply(trs(0, y, 0.118)), C.st(tint * 0.95, { orn: { cell, amount, su: 1, sv: 1 } }));
  };
  face(ORN.tian, 1.5, 0.7, 1.2);
  face(ORN.mu, 0.78, 0.7, 1.2);
  face(ORN.seal, 0.26, 0.26, 1.0, w * 0.8);
  face(ORN.crest, 2.02, 0.34, 1.1, 0.34);
  const c = V(0, 0, 0).applyMatrix4(m);
  C.colliders.boxes.push({ x: c.x, z: c.z, hx: 0.75, hz: 0.4, yaw: Math.atan2(-m.elements[2], m.elements[0]), y0: c.y, h: 2.6, tag: 'stele' });
}

/** The sect's war drum on its stand, the skin split. `m`: foot centre; the drum's axis runs along local Z. */
function warDrum(C, m) {
  const { P, rng } = C;
  const wood = C.wd(C.bare(0.75), { uv: 'keep', uvScale: 1.1 });
  const R = 0.82, D = 1.0;
  const dm = T(m, 0, 1.25, 0, 0, Math.PI / 2 + 0.12, 0.06);
  const shell = latheGrid({ rows: 4, segs: 14, profile: (t) => [R * (0.86 + 0.14 * Math.sin(t * Math.PI)), (t - 0.5) * D] });
  setOrnUv(shell[0], (p, n, i) => [((i % 15) / 14) * 10, Math.abs(p.y) / (D / 2) * 4.0 - 2.9, Math.abs(p.y) > D * 0.36 ? 1 : 0]);
  addAll(P, shell, dm, C.wd(C.lacquer(0.9), { uv: 'keep', uvScale: 1.1, orn: { cell: ORN.studs, amount: -1.0, su: 1, sv: 0.25 } }));
  // skins: the front one split (a dark gash), the back one whole
  const hide = [0.2, 0.17, 0.12];
  addAll(P, latheGrid({ rows: 2, segs: 14, profile: (t) => [R * 0.87 * (1 - t) + 0.001, D / 2 + 0.01 - 0.04 * t] }), dm, C.wd((p, n, o) => { const k = noise3(p.x * 2.2, p.y * 2.2, p.z * 2.2) > 0.56 ? 0.05 : 1; o[0] = hide[0] * k; o[1] = hide[1] * k; o[2] = hide[2] * k; }));
  addAll(P, latheGrid({ rows: 1, segs: 14, profile: (t) => [R * 0.87 * t + 0.001, -D / 2 - 0.01] }), dm, C.wd(hide));
  // stand: two trestles and a cradle beam
  for (const sx of [-1, 1]) {
    for (const sz of [-1, 1]) P.add(beam(1.45, 0.1, 0.1), T(m, sx * 0.62, 0.66, sz * 0.36, 0, 0, Math.PI / 2 + sx * 0.14), wood);
    P.add(beam(0.95, 0.1, 0.1), T(m, sx * 0.55, 0.5, 0, Math.PI / 2), wood);
  }
  void rng;
  const c = V(0, 0, 0).applyMatrix4(m);
  C.colliders.circles.push({ x: c.x, z: c.z, r: 1.1, y0: c.y, h: 2.2, tag: 'drum' });
}

/**
 * @param {object} C  build context (see ruins.js)
 * @param {object} site  { fires: [{pos, kind, y0}], lamps, pillars, hall, gate }
 * @returns {{ flames: Array, smokes: Array, tops: THREE.Vector3[] }}
 */
export function dressTerrace(C, site) {
  const { S, P, M, rng, tier } = C;
  const hi = tier.detail >= 2, mid = tier.detail >= 1;
  const { platY, wallR } = LAYOUT;
  const flames = [], smokes = [], tops = [];

  // ---- the four fires of env.braziers: two lit lanterns on the vista shoulders, two censers --------------------------
  S.section('lanterns'); M.section('censers');
  LAYOUT.braziers.forEach(([deg, r, kind], i) => {
    const th = deg * DEG;
    const m = ringM(r, th, 0, i === 1 ? 0.5 : 0.2);
    if (kind === 'lantern') {
      const f = lantern(C, m, i === 1 ? 'lean' : 'lit', 1.08);
      tops.push(f);
      flames.push({ pos: f, kind: 'lantern' });
    } else {
      const c = censer(C, m, 1.12);
      tops.push(c.fire);
      flames.push({ pos: c.fire, kind: 'censer' });
      for (const p of c.sticks) flames.push({ pos: p, kind: 'stick' });
      smokes.push({ pos: c.fire.clone().add(V(0, 0.2, 0)), h: 4.2, w: 0.5, k: 1 });
      smokes.push({ pos: c.fire.clone().add(V(0.12, 0.25, -0.1)), h: 3.0, w: 0.34, k: 0.7 });
    }
  });
  // ---- more lanterns: lit ones by the stairs (baked glow only), dark, leaning and toppled ones ------------------------
  const lamps = [];
  LAYOUT.lamps.forEach(([deg, r, y0 = 0], i) => {
    if (i >= 4 && !mid) return;
    const f = lantern(C, ringM(r, deg * DEG, y0, 0.3 * i), 'lit', 1.0);
    lamps.push(f);
    flames.push({ pos: f, kind: 'lantern' });
  });
  lantern(C, ringM(13.6, -104.5 * DEG, 0, 0.8), 'toppled', 1.0);
  if (mid) lantern(C, ringM(14.35, 141 * DEG, 0, 0.4), 'dark', 1.0);
  if (hi) lantern(C, ringM(18.6, 20.6 * DEG + Math.PI, platY, 0.2), 'dark', 0.95);

  // ---- weapon racks along the east wall, one thrown down -------------------------------------------------------------
  P.section('racks'); M.section('arms');
  weaponRack(C, ringM(14.55, 84 * DEG, 0, 0), { count: hi ? 6 : 4 });
  if (mid) weaponRack(C, ringM(14.5, 121 * DEG, 0, 0.05), { count: hi ? 5 : 3 });
  weaponRack(C, ringM(13.9, -129 * DEG, 0, 0.5), { toppled: true, count: 3 });
  // loose arms from the older duel, driven into the floor or lying by the rim (never on the fight line)
  const nArms = hi ? 9 : mid ? 6 : 4;
  const spots = [];
  for (let k = 0; k < 300 && spots.length < nArms; k++) {
    const th = rng.range(-180, 180) * DEG;
    if (Math.abs(th) < 24 * DEG) continue;
    const p = ringPos(rng.range(11.4, 14.2), th, 0);
    if (Math.abs(p.z) < 3.2 || (p.z > 0 && Math.abs(p.x) < 12)) continue;
    if (site.fires.some((b) => Math.hypot(b.x - p.x, b.z - p.z) < 1.8) || spots.some((s) => s.distanceTo(p) < 2)) continue;
    spots.push(p);
  }
  spots.forEach((p, k) => {
    const yaw = rng.range(0, Math.PI * 2);
    const iron = C.mt(C.iron(1.25));
    if (k % 3 === 0) {
      // a great sabre snapped, the blade standing in a cracked flagstone
      const L = rng.range(0.6, 1.0);
      const m = trs(p.x, 0, p.z, yaw, rng.range(-0.45, 0.45), rng.range(-0.4, 0.4));
      M.add(prism([[-0.045, -0.25], [0.05, -0.25], [0.065, L * 0.6], [0.03, L], [-0.045, L * 0.86]], 0.014), m, iron);
      M.add(new THREE.BoxGeometry(0.2, 0.04, 0.06), T(m, 0, L + 0.01, 0), C.mt(C.bronze(0.8)));
    } else if (k % 3 === 1) {
      // a spear snapped in two, the head half buried
      const L1 = rng.range(0.8, 1.3);
      const dir = V(Math.cos(yaw), 0, Math.sin(yaw));
      const a0 = p.clone().add(V(0, 0.03, 0));
      addAll(P, [tube([a0, a0.clone().addScaledVector(dir, L1).add(V(0, 0.02, 0))], 0.02, { sides: 5, caps: true })], new THREE.Matrix4(), C.wd(C.bare(0.6)));
      const hm = trs(a0.x + dir.x * (L1 + 0.5), 0.0, a0.z + dir.z * (L1 + 0.5), Math.atan2(-dir.z, dir.x), 0, -Math.PI / 2 - 0.25);
      addAll(M, latheGrid({ rows: 3, segs: 4, squash: 0.3, profile: (t) => [0.05 * Math.sin((1 - t) * Math.PI * 0.8 + 0.3), t * 0.3], capTop: true }), hm, iron);
    } else {
      // a wide bamboo hat, crushed, and a scabbard
      const m = trs(p.x, 0.02, p.z, yaw, rng.range(-0.15, 0.15), rng.range(-0.1, 0.1));
      addAll(P, latheGrid({ rows: 2, segs: 10, profile: (t) => [0.34 * (1 - t) + 0.01, t * 0.13], rmod: (phi) => (Math.cos(phi * 2 + k) > 0.7 ? 0.7 : 1), capTop: true }), m, C.wd([0.1, 0.085, 0.05]));
      P.add(prism([[-0.03, 0], [0.03, 0], [0.05, 0.4], [0.09, 0.74], [0.04, 0.76], [-0.01, 0.4]], 0.03), trs(p.x + 0.5, 0.03, p.z + 0.2, yaw + 1, Math.PI / 2, 0.2), C.wd(C.lacquer(0.6)));
    }
  });

  // ---- the stele and the drum ---------------------------------------------------------------------------------------
  S.section('stele');
  stele(C, ringM(14.25, 72 * DEG, 0, 0.12));
  if (mid) { P.section('drum'); warDrum(C, ringM(18.9, 87 * DEG, platY, 0.35)); }

  // ---- banner poles on the court edge --------------------------------------------------------------------------------
  P.section('poles');
  const cloth = [];
  const poles = [[41, 'banner'], [-41, 'banner'], [74, 'banner'], [-124, 'banner'], [124, 'banner'], [158, 'pennant'], [-158, 'pennant'], [-109, 'pennant']];
  poles.slice(0, tier.banners).forEach(([deg, kind], i) => {
    const th = deg * DEG;
    const H = kind === 'banner' ? 6.1 : 5.2;
    const lean = [rng.range(-0.035, 0.035), rng.range(-0.035, 0.035)];
    const m = ringM(wallR + 1.25, th, platY, 0, lean[0], lean[1]);
    addAll(P, [tube([V(0, 0, 0), V(0, H * 0.5, 0), V(0, H, 0)], (t) => 0.075 - 0.03 * t, { sides: 6, caps: true })], m, C.wd(C.lacquer(0.65)));
    C.S.add(chamferBox(0.5, 0.42, 0.5, 0.04, rng, 0.3), T(m, 0, 0.21, 0), C.st(0.95));
    addAll(M, latheGrid({ rows: 3, segs: 6, profile: (t) => [0.02 + 0.06 * Math.sin(t * Math.PI), H + t * 0.3], capTop: true }), m, C.mt(C.bronze(0.9)));
    // the yard the cloth hangs from, reaching toward the terrace
    const w = kind === 'banner' ? 1.0 : 0.62;
    P.add(beam(w + 0.25, 0.05, 0.05), T(m, 0, H - 0.2, 0.34), C.wd(C.bare(0.6), { uv: 'keep', uvScale: 1.1 }));
    P.add(beam(0.4, 0.04, 0.04), T(m, 0, H - 0.2, 0.17, Math.PI / 2), C.wd(C.bare(0.6), { uv: 'keep', uvScale: 1.1 }));
    const top = V(0, H - 0.23, 0.34).applyMatrix4(m);
    const inward = V(-Math.sin(th), 0, Math.cos(th));
    cloth.push({ top, normal: inward, width: w, length: kind === 'banner' ? 4.1 : 2.3, seed: rng.range(0, 100), uv: CLOTH[kind], cols: kind === 'banner' ? 6 : 4, rows: kind === 'banner' ? 18 : 10 });
    C.colliders.circles.push({ x: m.elements[12], z: m.elements[14], r: 0.3, y0: platY, h: H, tag: 'pole' });
    void i;
  });

  // ---- talisman ropes (금줄) ---------------------------------------------------------------------------------------------
  P.section('ropes');
  const rope = (a, b, sag, every = 0.42) => {
    const n = Math.max(6, Math.round(a.distanceTo(b) / 0.4));
    const pts = [];
    for (let i = 0; i <= n; i++) { const t = i / n; const p = a.clone().lerp(b, t); p.y -= sag * 4 * t * (1 - t); pts.push(p); }
    addAll(P, [tube(pts, 0.014, { sides: 3 })], new THREE.Matrix4(), C.wd([0.11, 0.095, 0.07]));
    const dir = b.clone().sub(a).setY(0).normalize();
    const normal = V(-dir.z, 0, dir.x);
    const L = a.distanceTo(b);
    const cnt = Math.floor(L / every);
    for (let k = 1; k < cnt; k++) {
      const t = (k + rng.range(-0.15, 0.15)) / cnt;
      const p = a.clone().lerp(b, t); p.y -= sag * 4 * t * (1 - t) + 0.012;
      const hemp = k % 4 === 0;
      if (rng.chance(0.14)) continue;
      cloth.push({ top: p, normal: rng.chance(0.5) ? normal : normal.clone().negate(), width: hemp ? 0.07 : 0.105, length: hemp ? rng.range(0.4, 0.6) : rng.range(0.27, 0.33), seed: rng.range(0, 100), uv: hemp ? CLOTH.hemp : (k % 2 ? CLOTH.talisman : CLOTH.talisman2), cols: 1, rows: hemp ? 4 : 3 });
    }
  };
  {
    // across the gate's doorway (where the mist curtain of the RPG mode hangs)
    const gm = ringM(GATE.line, GATE.th, platY);
    rope(V(-GATE.halfBay + 0.25, 3.5, 0.2).applyMatrix4(gm), V(GATE.halfBay - 0.25, 3.7, 0.2).applyMatrix4(gm), 0.5);
    if (mid) rope(V(GATE.halfBay, 4.5, 0.3).applyMatrix4(gm), V(GATE.wing, 3.9, 0.35).applyMatrix4(gm), 0.35);
    // between two standing columns of the hall's porch
    const hm = ringM(HALL.front, HALL.th, platY);
    const xs = -HALL.bay * HALL.bays / 2;
    rope(V(xs + 3 * HALL.bay, HALL.plinth + 3.0, -HALL.porch + 0.3).applyMatrix4(hm), V(xs + 4 * HALL.bay, HALL.plinth + 3.2, -HALL.porch + 0.3).applyMatrix4(hm), 0.45);
    // from the rim's last posts up to the lit lanterns on the vista shoulders
    for (const s of [1, -1]) {
      const postTh = s > 0 ? 26 * DEG : -24.5 * DEG;
      const a = ringPos(rimR(postTh) - 0.32, postTh, 0.86);
      const b = ringPos(13.7, s * 37 * DEG, 2.2);
      if (s > 0 || mid) rope(a, b, 0.4, 0.5);
    }
    // round the censers: a square of rope on four stakes
    if (hi) {
      for (const sgn of [-1, 1]) {
        const c = ringPos(13.6, sgn * 63 * DEG, 0);
        const corners = [0, 1, 2, 3].map((k) => c.clone().add(V(Math.cos(k * Math.PI / 2 + 0.6) * 1.25, 0, Math.sin(k * Math.PI / 2 + 0.6) * 1.25)));
        corners.forEach((q) => addAll(P, [tube([q, q.clone().add(V(0, 1.05, 0))], 0.025, { sides: 4, caps: true })], new THREE.Matrix4(), C.wd(C.bare(0.6))));
        for (let k = 0; k < 3; k++) rope(corners[k].clone().setY(0.98), corners[k + 1].clone().setY(0.98), 0.1, 0.36);
      }
    }
  }

  // ---- roof tiles spilled at the wall foot under the torn gallery roof ---------------------------------------------------
  S.section('spill');
  const nSpill = hi ? 26 : mid ? 16 : 8;
  for (let k = 0; k < nSpill; k++) {
    const th = rng.range(56, 71) * DEG;
    const p = ringPos(rng.range(13.9, 15.35), th, 0);
    const s = rng.range(0.1, 0.22);
    const col = (pp, n, o) => { const v = rng.range(0.6, 1.1); o[0] = v * PALETTE.tile[0]; o[1] = v * PALETTE.tile[1]; o[2] = v * PALETTE.tile[2]; };
    if (k % 3 === 0) {
      // a whole cover tile (half round)
      const g = latheGrid({ rows: 1, segs: 4, arc: [0, Math.PI], profile: (t) => [0.085, t * 0.36] });
      addAll(S, g, trs(p.x, 0.01, p.z, rng.range(0, 6), Math.PI / 2, rng.range(-0.3, 0.3)), { color: col, glow: C.glow, uv: 'box', uvScale: 1.7 });
    } else S.add(chamferBox(s * 1.8, s * 0.22, s * 1.3, 0.015, rng, 0.7), trs(p.x, s * 0.08, p.z, rng.range(0, 6), rng.range(-0.25, 0.25), rng.range(-0.25, 0.25)), { color: col, glow: C.glow, uv: 'box', uvScale: 1.7 });
  }
  void brokenBlock; void rock; void noise3;
  return { flames, smokes, tops, lamps, cloth };
}
