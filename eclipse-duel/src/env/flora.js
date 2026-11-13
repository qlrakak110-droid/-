// Vegetation as ink silhouettes: twisted pines gripping rock outcrops on the vista shoulders, bamboo clumps behind
// the gallery (they sway), dry grass in the cracks and along the wall foot. Trunks and rocks go into the shared
// builders; needles, bamboo and grass form one alpha-tested mesh (materials.js createFoliageMaterial) animated in
// its vertex shader.

import * as THREE from 'three';
import { DEG } from '../core/math.js';
import { rock, trs, noise3, tube, addAll } from './geometry.js';
import { LAYOUT, STAIRS, rimR } from './config.js';
import { FOLIAGE } from './bake.js';

const V = (x, y, z) => new THREE.Vector3(x, y, z);
const ringPos = (r, th, y = 0) => V(r * Math.sin(th), y, -r * Math.cos(th));

/** Accumulates the foliage mesh: position, normal, uv (atlas), color, aSway (amplitude m, phase, flutter). */
class FoliageBuilder {
  constructor() { this.pos = []; this.nrm = []; this.uv = []; this.col = []; this.sway = []; this.idx = []; }
  /** A textured quad: centre-bottom `c`, unit `right` and `up` vectors, size w x h, atlas cell [cx, cy]. */
  quad(c, right, up, w, h, cell, color, sway, normal = null) {
    const b = this.pos.length / 3;
    const n = normal || V(0, 1, 0);
    const [cx, cy] = cell;
    for (const [u, v] of [[0, 0], [1, 0], [1, 1], [0, 1]]) {
      const p = c.clone().addScaledVector(right, (u - 0.5) * w).addScaledVector(up, v * h);
      this.pos.push(p.x, p.y, p.z);
      this.nrm.push(n.x, n.y, n.z);
      this.uv.push((cx + 0.03 + 0.94 * u) / 2, (cy + 0.03 + 0.94 * v) / 2);
      this.col.push(color[0], color[1], color[2]);
      const s = typeof sway === 'function' ? sway(p, v) : sway;
      this.sway.push(s[0], s[1], s[2]);
    }
    this.idx.push(b, b + 1, b + 2, b, b + 2, b + 3);
  }
  /** A solid tube (bamboo culm): sways with the leaves. `swayAt(p)` -> [amp, phase, flutter]. */
  tube(geo, color, swayAt) {
    const b = this.pos.length / 3;
    const p = geo.attributes.position, n = geo.attributes.normal;
    const q = V(0, 0, 0);
    for (let i = 0; i < p.count; i++) {
      q.fromBufferAttribute(p, i);
      this.pos.push(q.x, q.y, q.z);
      this.nrm.push(n.getX(i), n.getY(i) + 0.6, n.getZ(i));
      this.uv.push(0.75, 0.25);
      const k = 0.8 + 0.4 * noise3(q.x * 3, q.y * 1.5, q.z * 3);
      this.col.push(color[0] * k, color[1] * k, color[2] * k);
      const s = swayAt(q);
      this.sway.push(s[0], s[1], s[2]);
    }
    for (const i of geo.index.array) this.idx.push(b + i);
  }
  build() {
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(this.pos, 3));
    g.setAttribute('normal', new THREE.Float32BufferAttribute(this.nrm, 3));
    g.setAttribute('uv', new THREE.Float32BufferAttribute(this.uv, 2));
    g.setAttribute('color', new THREE.Float32BufferAttribute(this.col, 3));
    g.setAttribute('aSway', new THREE.Float32BufferAttribute(this.sway, 3));
    g.setIndex(this.pos.length / 3 > 65535 ? new THREE.Uint32BufferAttribute(this.idx, 1) : new THREE.Uint16BufferAttribute(this.idx, 1));
    g.computeBoundingSphere();
    return g;
  }
}

const NEEDLE = [0.016, 0.026, 0.02];
const BARK = [0.03, 0.026, 0.023];
const CULM = [0.02, 0.034, 0.022];
const BLADE = [0.07, 0.065, 0.04];

/**
 * A twisted pine on a rock outcrop. `at`: ground point; `toward`: horizontal unit vector the tree leans to.
 */
function pine(C, F, at, toward, H, seed) {
  const { rng, tier } = C;
  const hi = tier.detail >= 2;
  // the outcrop
  C.S.section('rocks');
  const rocks = [[0, 0, 1.5], [1.3, 0.5, 1.0], [-1.0, -0.8, 0.9], [0.3, 1.2, 0.7]];
  let top = 0;
  rocks.slice(0, hi ? 4 : 3).forEach(([dx, dz, r], k) => {
    C.S.add(rock(r, rng, { detail: hi && k === 0 ? 2 : 1, squash: rng.range(0.6, 0.9), rough: 0.4 }), trs(at.x + dx, at.y + r * 0.25, at.z + dz, rng.range(0, 6)), C.st(0.75, { uvScale: 3 }));
    if (k === 0) top = r * 0.72;
    C.colliders.circles.push({ x: at.x + dx, z: at.z + dz, r: r * 0.9, y0: at.y, h: r, tag: 'rock' });
  });
  // trunk: an S-curve leaning out, wringing as it climbs
  C.P.section('pines');
  const base = at.clone().add(V(0, top, 0));
  const side = V(-toward.z, 0, toward.x);
  const pts = [];
  const n = 9;
  for (let i = 0; i <= n; i++) {
    const t = i / n;
    const out = toward.clone().multiplyScalar(H * (0.5 * t * t + 0.12 * Math.sin(t * 5 + seed)));
    const sw = side.clone().multiplyScalar(H * 0.14 * Math.sin(t * 4.2 + seed * 2));
    pts.push(base.clone().add(out).add(sw).add(V(0, H * (t - 0.14 * t * t) * 0.92, 0)));
  }
  const bark = C.wd((p, nn, o) => { const k = 0.7 + 0.6 * noise3(p.x * 1.8, p.y * 0.9, p.z * 1.8); o[0] = BARK[0] * k; o[1] = BARK[1] * k; o[2] = BARK[2] * k; });
  addAll(C.P, [tube(pts, (t) => 0.3 * (1 - 0.72 * t) + 0.03, { sides: hi ? 7 : 5 })], new THREE.Matrix4(), bark);
  // roots splayed over the rock
  for (let k = 0; k < 4; k++) {
    const a = seed + k * 1.7;
    const d = V(Math.cos(a), 0, Math.sin(a));
    addAll(C.P, [tube([base.clone().add(V(0, 0.35, 0)), base.clone().addScaledVector(d, 0.6).add(V(0, 0.05, 0)), base.clone().addScaledVector(d, 1.3).add(V(0, -0.5, 0))], (t) => 0.13 - 0.08 * t, { sides: 4 })], new THREE.Matrix4(), bark);
  }
  // boughs: long, nearly level, each carrying flat pads of needles
  const boughs = hi ? 7 : 5;
  const pad = (c, w) => {
    const yaw = rng.range(0, Math.PI);
    const sway = [0.05 + w * 0.02, rng.range(0, 6), 0.25];
    for (const a of [yaw, yaw + Math.PI / 2]) F.quad(c.clone().add(V(0, -0.12 * w, 0)), V(Math.cos(a), 0, Math.sin(a)), V(0, 1, 0), w, w * 0.5, FOLIAGE.pineSide, NEEDLE, sway);
    F.quad(c.clone().add(V(0, 0.08 * w, -w / 2)), V(1, 0, 0), V(0, 0.04, 1).normalize(), w, w, FOLIAGE.pineTop, NEEDLE, sway);
  };
  for (let k = 0; k < boughs; k++) {
    const t = 0.42 + 0.58 * (k / (boughs - 1));
    const from = pts[Math.min(n, Math.round(t * n))];
    const az = seed * 3 + k * 2.4;
    const d = toward.clone().multiplyScalar(0.55).add(V(Math.cos(az), 0, Math.sin(az))).normalize();
    const L = H * (0.42 - 0.2 * t) * rng.range(0.8, 1.25) + 0.8;
    const bp = [from.clone()];
    for (let i = 1; i <= 4; i++) {
      const u = i / 4;
      bp.push(from.clone().addScaledVector(d, L * u).add(V(0, L * (0.16 * Math.sin(u * 2.4) - 0.1 * u * u) + 0.1 * Math.sin(u * 9 + k), 0)).addScaledVector(V(-d.z, 0, d.x), 0.25 * Math.sin(u * 5 + k)));
    }
    addAll(C.P, [tube(bp, (u) => (0.09 - 0.06 * u) * (1.3 - 0.5 * t), { sides: 4 })], new THREE.Matrix4(), bark);
    pad(bp[4].clone().add(V(0, 0.1, 0)), rng.range(1.7, 2.5));
    pad(bp[2].clone().add(V(0, 0.2, 0)).addScaledVector(V(-d.z, 0, d.x), rng.range(-0.7, 0.7)), rng.range(1.2, 1.9));
    if (hi) pad(bp[3].clone().add(V(0, 0.25, 0)).addScaledVector(V(-d.z, 0, d.x), rng.range(-0.9, 0.9)), rng.range(1.1, 1.6));
  }
  pad(pts[n].clone().add(V(0, 0.1, 0)), 2.1);
}

/** A bamboo clump: culms arcing outward from a crowded foot, leaf sprays hanging down their upper halves. */
function bamboo(C, F, at, count, spread) {
  const { rng, tier } = C;
  const sprays = tier.detail >= 2 ? 9 : tier.detail >= 1 ? 7 : 5;
  for (let k = 0; k < count; k++) {
    const a = rng.range(0, Math.PI * 2), d = Math.sqrt(rng()) * spread;
    const foot = at.clone().add(V(Math.cos(a) * d, 0, Math.sin(a) * d));
    const H = rng.range(5.6, 8.6);
    const lean = V(Math.cos(a), 0, Math.sin(a)).multiplyScalar(rng.range(0.4, 1.5));
    const phase = rng.range(0, 6);
    const pts = [];
    for (let i = 0; i <= 6; i++) { const t = i / 6; pts.push(foot.clone().add(V(0, H * t, 0)).addScaledVector(lean, t * t)); }
    const amp = (y) => { const t = Math.max(0, (y - at.y) / H); return 0.55 * t * t; };
    F.tube(tube(pts, (t) => 0.045 - 0.028 * t, { sides: 4 }), CULM, (p) => [amp(p.y), phase, 0.0]);
    for (let j = 0; j < sprays; j++) {
      const t = rng.range(0.42, 1.0);
      const c = foot.clone().add(V(0, H * t, 0)).addScaledVector(lean, t * t);
      const yaw = rng.range(0, Math.PI * 2);
      const w = rng.range(1.0, 1.6);
      const right = V(Math.cos(yaw), 0, Math.sin(yaw));
      const top = c.clone().addScaledVector(V(-right.z, 0, right.x), rng.range(-0.2, 0.2));
      // hung from its top edge: build the quad downward
      F.quad(top.clone().add(V(0, -w * 0.94, 0)), right, V(0, 1, 0), w, w, FOLIAGE.bamboo, [CULM[0] * 0.9, CULM[1] * 0.95, CULM[2] * 0.9], [amp(c.y), phase, 0.9]);
    }
  }
  C.colliders.circles.push({ x: at.x, z: at.z, r: spread + 0.4, y0: at.y, h: 6, tag: 'bamboo' });
}

/**
 * @param {object} C build context
 * @returns {THREE.BufferGeometry} the foliage mesh geometry
 */
export function buildFlora(C) {
  const { rng, tier } = C;
  const F = new FoliageBuilder();
  const hi = tier.detail >= 2, mid = tier.detail >= 1;
  const { platY, wallR, gap } = LAYOUT;

  // pines on the vista shoulders, leaning out over the cloud sea toward the eclipse; one behind the south-east court
  pine(C, F, ringPos(22.2, 41 * DEG, platY - 0.2), V(-0.82, 0, -0.57).normalize(), 7.6, 1.3);
  pine(C, F, ringPos(23.0, -37 * DEG, platY - 0.2), V(0.9, 0, -0.44).normalize(), 6.4, 4.1);
  if (mid) pine(C, F, ringPos(25.8, 116 * DEG, platY - 0.2), V(-0.5, 0, 0.86).normalize(), 6.8, 7.7);
  // further back, beyond the boundary wall and the hall: ink shapes against the horizon glow
  if (mid) pine(C, F, ringPos(30.5, -127 * DEG, platY - 0.2), V(0.7, 0, 0.7).normalize(), 7.4, 2.6);
  if (hi) pine(C, F, ringPos(29.5, 161 * DEG, platY - 0.2), V(0.3, 0, -0.95).normalize(), 6.0, 5.5);

  // bamboo behind the gallery and the boundary wall
  const clumps = [[86, 23.8, 1.5], [136, 25.2, 1.4], [-137, 25.4, 1.5], [62, 23.6, 1.2], [103, 25.0, 1.3], [-162, 25.6, 1.2]];
  const nC = hi ? 6 : mid ? 5 : 3;
  clumps.slice(0, nC).forEach(([deg, r, sp]) => bamboo(C, F, ringPos(r, deg * DEG, platY - 0.05), hi ? 9 : mid ? 7 : 5, sp));

  // dry grass: along the fallen rim, at the wall foot, on the court's edge, in the cracks of the outer rows
  const tuft = (p, s) => {
    const yaw = rng.range(0, Math.PI);
    const k = rng.range(0.7, 1.3);
    const col = [BLADE[0] * k, BLADE[1] * k, BLADE[2] * k * 0.9];
    const sway = [0.05 * s, rng.range(0, 6), 1.0];
    for (const a of [yaw, yaw + Math.PI / 2]) F.quad(p, V(Math.cos(a), 0, Math.sin(a)), V(0, 1, 0), 0.5 * s, 0.42 * s, FOLIAGE.grass, col, (q, v) => [sway[0] * v, sway[1], 1.0]);
  };
  const inMouth = (th) => STAIRS.some((s) => Math.abs(Math.atan2(Math.sin(th - s.th), Math.cos(th - s.th))) < 0.2);
  const nGrass = hi ? 150 : mid ? 100 : 50;
  for (let i = 0; i < nGrass; i++) {
    const th = rng.range(-Math.PI, Math.PI);
    const roll = rng();
    let p;
    if (Math.abs(th) < gap) p = ringPos(rimR(th) - 0.15 - Math.pow(rng(), 1.5) * 2.0, th, 0);
    else if (inMouth(th)) continue;
    else if (roll < 0.5) p = ringPos(wallR - 0.12 - Math.pow(rng(), 2) * 1.2, th, 0);
    else if (roll < 0.75) p = ringPos(wallR + 1.0 + rng() * 1.6, th, platY);
    else p = ringPos(rng.range(9.6, 14), th, 0);
    if (p.y < 0.1 && Math.abs(p.z) < 2.6 && Math.abs(p.x) < 13) continue;
    tuft(p, rng.range(0.7, 1.5));
  }
  return F.build();
}
