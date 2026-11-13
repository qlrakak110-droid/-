// Verlet cloth (capes, tabards, waist cloth). Particles live in model (fighter-local) space; root motion feeds back
// as inertia, so facing flips and teleports never disturb it. Each particle drives one "cloth bone"; the render mesh
// is part of a merged SkinnedMesh, bilinearly weighted to 4 particle bones (smooth surface from a coarse grid, normals
// from per-particle frames, zero CPU vertex work).
//
// Stability: fixed 1/120 s steps (frame-rate and slow-motion independent; rendering interpolates between steps),
// Gauss-Seidel distance constraints (stretch / shear / bend), a strain limit on structural / shear edges, long-range
// tethers to the pinned row, velocity clamp, capsule (a particle that rests inside a capsule by design may stay as
// deep as it rests) + floor collision, NaN / explosion failsafe.

import * as THREE from 'three';
import { qrot, qfromBasis, qslerp, qmul } from './rigmath.js';
import { pushOutCapsules, capsuleAxisDist, capsulesNear } from './collide.js';
import { shift } from './spring.js';

const ZERO3 = new Float32Array(3);

/**
 * Segment a-b (particles at p[a..], p[b..], inverse masses wa / wb) against every capsule both particles collide
 * with: where the segment's closest point to a capsule axis is inside the capsule, both particles move out along
 * that point's normal by the penetration (a sheet stretched across a limb is lifted round it). mask / ma / mb: the
 * particles' capsule masks.
 */
function edgeOut(p, a, b, caps, margin, mask, ma, mb, wa, wb, idx, nidx) {
  const d = caps.data;
  for (let j = 0; j < nidx; j++) {
    const i = idx[j];
    if (mask && (mask[ma + i] !== 0 || mask[mb + i] !== 0)) continue;
    const c = i * 7, ax = d[c], ay = d[c + 1], az = d[c + 2], ux = d[c + 3] - ax, uy = d[c + 4] - ay, uz = d[c + 5] - az;
    const vx = p[b] - p[a], vy = p[b + 1] - p[a + 1], vz = p[b + 2] - p[a + 2];
    const wx = p[a] - ax, wy = p[a + 1] - ay, wz = p[a + 2] - az;
    // closest points of segment s(t) = pa + v t and the axis q(u) = A + U u, t and u in [0, 1]
    const A = ux * ux + uy * uy + uz * uz, B = ux * vx + uy * vy + uz * vz, Cc = vx * vx + vy * vy + vz * vz;
    const D = ux * wx + uy * wy + uz * wz, Ee = vx * wx + vy * wy + vz * wz, den = A * Cc - B * B;
    let t = den > 1e-12 ? (A * Ee - B * D) / -den : 0;
    t = t < 0 ? 0 : t > 1 ? 1 : t;
    let u = A > 1e-12 ? (D + B * t) / A : 0;
    u = u < 0 ? 0 : u > 1 ? 1 : u;
    t = Cc > 1e-12 ? (ux * u * 1 - wx) * vx / Cc + (uy * u - wy) * vy / Cc + (uz * u - wz) * vz / Cc : 0;
    t = t < 0 ? 0 : t > 1 ? 1 : t;
    if (t <= 0.02 || t >= 0.98) continue; // the closest point is an end particle: the particle collision handles it
    const sx = p[a] + vx * t, sy = p[a + 1] + vy * t, sz = p[a + 2] + vz * t;
    const qx = sx - ax - ux * u, qy = sy - ay - uy * u, qz = sz - az - uz * u;
    const r = d[c + 6] + margin, l = Math.sqrt(qx * qx + qy * qy + qz * qz);
    if (l >= r || l < 1e-6) continue;
    const k = (r - l) / l, ox = qx * k, oy = qy * k, oz = qz * k;
    if (wa > 0) { p[a] += ox; p[a + 1] += oy; p[a + 2] += oz; }
    if (wb > 0) { p[b] += ox; p[b + 1] += oy; p[b + 2] += oz; }
  }
}

/**
 * Lay out a cloth grid in bind space.
 * spec: { name, top: [[bone, [x,y,z]], ...] (pinned edge, ordered from the fighter's LEFT (-Z) to RIGHT (+Z)),
 *         cols=9, rows=12, length=1.0, drape=[-0.12,-1,0] (hang direction), flare=0.3 (relative widening at the
 *         bottom), offset: fn(u, v) -> [dx,dy,dz] extra rest offset, pinRows=1 }
 * anchorPos(bone, offset) -> [x,y,z] bind-space point.
 */
export function clothLayout(spec, quality, anchorPos, rigIndexOf) {
  const q = Math.max(0.35, quality);
  const C = Math.max(4, Math.round((spec.cols || 9) * Math.min(1, q))), R = Math.max(5, Math.round((spec.rows || 12) * Math.min(1, q)));
  const ctrl = spec.top.map(([b, o]) => new THREE.Vector3(...anchorPos(b, o)));
  const curve = new THREE.CatmullRomCurve3(ctrl, false, 'centripetal');
  const top = curve.getSpacedPoints(C - 1);
  const center = new THREE.Vector3();
  for (const p of top) center.add(p);
  center.multiplyScalar(1 / C);
  const drape = new THREE.Vector3(...(spec.drape || [-0.12, -1, 0])).normalize();
  const L = spec.length ?? 1.0, flare = spec.flare ?? 0.3;
  const rest = new Float32Array(C * R * 3);
  for (let j = 0; j < R; j++) {
    const v = j / (R - 1);
    for (let i = 0; i < C; i++) {
      const u = i / (C - 1), t = top[i];
      const off = spec.offset ? spec.offset(u, v) : [0, 0, 0];
      const k = (j * C + i) * 3;
      rest[k] = t.x + drape.x * L * v + (t.x - center.x) * flare * v + off[0];
      rest[k + 1] = t.y + drape.y * L * v + off[1];
      rest[k + 2] = t.z + drape.z * L * v + (t.z - center.z) * flare * v + off[2];
    }
  }
  // anchor bone for each pinned particle: nearest control point's bone
  const pinRows = spec.pinRows ?? 1;
  const anchorBone = new Int16Array(C * pinRows);
  for (let j = 0; j < pinRows; j++) for (let i = 0; i < C; i++) {
    let best = 0, bd = 1e9;
    ctrl.forEach((c, k) => { const d = c.distanceTo(top[i]); if (d < bd) { bd = d; best = k; } });
    anchorBone[j * C + i] = rigIndexOf(spec.top[best][0]);
  }
  const frames = new Float32Array(C * R * 4);
  computeFrames(rest, C, R, frames);
  const bones = [];
  for (let j = 0; j < R; j++) for (let i = 0; i < C; i++) {
    const k = j * C + i;
    bones.push({ name: `${spec.name}_${i}_${j}`, parent: null, at: [rest[k * 3], rest[k * 3 + 1], rest[k * 3 + 2]], quat: [frames[k * 4], frames[k * 4 + 1], frames[k * 4 + 2], frames[k * 4 + 3]] });
  }
  return { spec, C, R, rest, frames, pinRows, anchorBone, bones, center: center.toArray() };
}

/** Per-particle orientation: X = surface normal, Y = up along the cloth, Z = across (left -> right). */
const FX = [0, 0, 0], FY = [0, 0, 0], FZ = [0, 0, 0];
export function computeFrames(p, C, R, out) {
  const X = FX, Y = FY, Z = FZ;
  for (let j = 0; j < R; j++) for (let i = 0; i < C; i++) {
    const a = (j * C + Math.max(0, i - 1)) * 3, b = (j * C + Math.min(C - 1, i + 1)) * 3;
    const c = (Math.max(0, j - 1) * C + i) * 3, d = (Math.min(R - 1, j + 1) * C + i) * 3;
    const hx = p[b] - p[a], hy = p[b + 1] - p[a + 1], hz = p[b + 2] - p[a + 2];
    const vx = p[c] - p[d], vy = p[c + 1] - p[d + 1], vz = p[c + 2] - p[d + 2];
    let nx = hy * vz - hz * vy, ny = hz * vx - hx * vz, nz = hx * vy - hy * vx;
    let l = Math.hypot(nx, ny, nz) || 1;
    nx /= l; ny /= l; nz /= l;
    let yx = vx, yy = vy, yz = vz;
    const dd = yx * nx + yy * ny + yz * nz;
    yx -= nx * dd; yy -= ny * dd; yz -= nz * dd;
    l = Math.hypot(yx, yy, yz) || 1;
    yx /= l; yy /= l; yz /= l;
    X[0] = nx; X[1] = ny; X[2] = nz; Y[0] = yx; Y[1] = yy; Y[2] = yz;
    Z[0] = ny * yz - nz * yy; Z[1] = nz * yx - nx * yz; Z[2] = nx * yy - ny * yx;
    qfromBasis(out, (j * C + i) * 4, X, Y, Z);
  }
}

/**
 * Render geometry for a cloth layout: outer + lining layers (offset by thickness along the particle normal) and a
 * rim strip, subdivided `sub` times per cell, with bilinear weights to the particle bones.
 * Returns { geo, weights(i) -> [[boneIndex, w], ...], isOuter(i) }.
 */
export function clothGeometry(layout, firstBone, outward) {
  const { C, R, rest, frames, spec } = layout;
  const sub = spec.subdiv ?? 2, th = (spec.thickness ?? 0.012) * 0.5;
  const NU = (C - 1) * sub + 1, NV = (R - 1) * sub + 1;
  const pos = [], idx = [], wts = [], layer = [];
  const n = [0, 0, 0];
  const vert = (gu, gv, side) => {
    const fu = gu / sub, fv = gv / sub;
    const i0 = Math.min(C - 2, Math.floor(fu)), j0 = Math.min(R - 2, Math.floor(fv));
    const tu = fu - i0, tv = fv - j0;
    const ids = [[i0, j0, (1 - tu) * (1 - tv)], [i0 + 1, j0, tu * (1 - tv)], [i0, j0 + 1, (1 - tu) * tv], [i0 + 1, j0 + 1, tu * tv]];
    let x = 0, y = 0, z = 0, nx = 0, ny = 0, nz = 0;
    const w = [];
    for (const [i, j, ww] of ids) {
      const k = j * C + i;
      x += rest[k * 3] * ww; y += rest[k * 3 + 1] * ww; z += rest[k * 3 + 2] * ww;
      qrot(n, 0, frames, k * 4, 1, 0, 0);
      nx += n[0] * ww; ny += n[1] * ww; nz += n[2] * ww;
      if (ww > 1e-4) w.push([firstBone + k, ww]);
    }
    const l = Math.hypot(nx, ny, nz) || 1;
    const o = side * th * outward / l;
    pos.push(x + nx * o, y + ny * o, z + nz * o);
    wts.push(w);
    layer.push(side);
    return pos.length / 3 - 1;
  };
  const grid = (side) => {
    const base = pos.length / 3;
    for (let gv = 0; gv < NV; gv++) for (let gu = 0; gu < NU; gu++) vert(gu, gv, side);
    return base;
  };
  const bo = grid(1), bi = grid(-1);
  for (let gv = 0; gv < NV - 1; gv++) for (let gu = 0; gu < NU - 1; gu++) {
    const a = gv * NU + gu, b = a + 1, c = a + NU, d = c + 1;
    idx.push(bo + a, bo + c, bo + b, bo + b, bo + c, bo + d);
    idx.push(bi + a, bi + b, bi + c, bi + b, bi + d, bi + c);
  }
  // orientation: outer faces must point along +outward particle normal (decided on the layers alone)
  const P = pos;
  {
    qrot(n, 0, frames, Math.floor(C / 2) * 4 + Math.floor(R / 2) * C * 4, 1, 0, 0);
    const m = bo + Math.floor(NV / 2) * NU + Math.floor(NU / 2), a = m, b2 = m + 1, c2 = m + NU;
    const ux = P[b2 * 3] - P[a * 3], uy = P[b2 * 3 + 1] - P[a * 3 + 1], uz = P[b2 * 3 + 2] - P[a * 3 + 2];
    const vx = P[c2 * 3] - P[a * 3], vy = P[c2 * 3 + 1] - P[a * 3 + 1], vz = P[c2 * 3 + 2] - P[a * 3 + 2];
    // triangle (a, c, b) of the outer layer: normal = (c - a) x (b - a)
    const fx = vy * uz - vz * uy, fy = vz * ux - vx * uz, fz = vx * uy - vy * ux;
    if ((fx * n[0] + fy * n[1] + fz * n[2]) * outward < 0) for (let i = 0; i < idx.length; i += 3) { const t = idx[i + 1]; idx[i + 1] = idx[i + 2]; idx[i + 2] = t; }
  }
  // rim: walk the border and stitch outer to inner; every quad faces away from the cloth (outward along the sheet)
  const border = [];
  for (let gu = 0; gu < NU; gu++) border.push(gu);
  for (let gv = 1; gv < NV; gv++) border.push(gv * NU + NU - 1);
  for (let gu = NU - 2; gu >= 0; gu--) border.push((NV - 1) * NU + gu);
  for (let gv = NV - 2; gv >= 1; gv--) border.push(gv * NU);
  const inward = (v) => { // a grid neighbour one step toward the inside of the sheet
    const gu = v % NU, gv = (v / NU) | 0;
    return Math.min(NV - 2, Math.max(1, gv)) * NU + Math.min(NU - 2, Math.max(1, gu));
  };
  for (let k = 0; k < border.length; k++) {
    const a = border[k], b = border[(k + 1) % border.length];
    const A = bo + a, B = bo + b, Ai = bi + a;
    // outward direction of this edge = edge midpoint - inner neighbours' midpoint
    const ia = bo + inward(a), ib = bo + inward(b);
    const ox = (P[A * 3] + P[B * 3] - P[ia * 3] - P[ib * 3]), oy = (P[A * 3 + 1] + P[B * 3 + 1] - P[ia * 3 + 1] - P[ib * 3 + 1]), oz = (P[A * 3 + 2] + P[B * 3 + 2] - P[ia * 3 + 2] - P[ib * 3 + 2]);
    // triangle (A, Ai, B): normal = (Ai - A) x (B - A)
    const ux = P[Ai * 3] - P[A * 3], uy = P[Ai * 3 + 1] - P[A * 3 + 1], uz = P[Ai * 3 + 2] - P[A * 3 + 2];
    const vx = P[B * 3] - P[A * 3], vy = P[B * 3 + 1] - P[A * 3 + 1], vz = P[B * 3 + 2] - P[A * 3 + 2];
    const fx = uy * vz - uz * vy, fy = uz * vx - ux * vz, fz = ux * vy - uy * vx;
    if (fx * ox + fy * oy + fz * oz >= 0) idx.push(A, Ai, B, B, Ai, bi + b);
    else idx.push(A, B, Ai, B, bi + b, Ai);
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setIndex(idx);
  geo.computeVertexNormals();
  return { geo, weights: (i) => wts[i], layer: (i) => layer[i] };
}

/** Fixed simulation step (s of game time): the same cloth at 30 / 60 / 120 Hz and in slow motion. */
export const CLOTH_STEP = 1 / 120;
const MAX_STEPS = 5;
/** Structural / shear edges never stretch past this factor of their rest length (strain limit). */
export const MAX_STRAIN = 1.15;
/** Strain-limit passes per step (a fixed count: an early exit made the sheet react to noise-level differences). */
const STRAIN_PASSES = 4;

export class Cloth {
  /**
   * @param {object} rig
   * @param {object} layout  from clothLayout (its bones are in the rig)
   * @param {number} quality ctx.quality.cloth
   */
  constructor(rig, layout, quality) {
    const s = layout.spec;
    this.rig = rig; this.layout = layout;
    this.spec = { damping: 0.035, gravity: 1, wind: 1, margin: 0.025, stretch: 1, shear: 0.7, bend: 0.25, tether: 1.04, maxSpeed: 14, inertia: 1, ...s };
    const { C, R } = layout;
    this.C = C; this.R = R; this.n = C * R;
    this.K = rig.k || 1;
    this.first = rig.index[layout.bones[0].name];
    // Gauss-Seidel iterations per step (the strain limit keeps the sheet's length; detail scales with quality)
    this.iters = Math.max(3, Math.round(3 + 4 * Math.min(1, quality)));
    this.p = new Float32Array(this.n * 3);
    this.pp = new Float32Array(this.n * 3);
    this.r0 = new Float32Array(this.n * 3);  // state one step earlier (rendering interpolates to the frame time)
    this.rp = new Float32Array(this.n * 3);  // rendered positions
    this.inv = new Float32Array(this.n).fill(1);
    this.contact = new Uint8Array(this.n);   // particle pushed out of a body capsule in this step
    for (let k = 0; k < C * layout.pinRows; k++) this.inv[k] = 0;
    // anchors: pinned particle offsets in their bone's bind frame
    this.anchor = new Float32Array(C * layout.pinRows * 3);
    this.anchorTarget = new Float32Array(C * layout.pinRows * 3);
    // the pinned particles' bone transforms last frame (0) and now (1): the sub-steps move the pins with their bones
    // (rotation slerped, position lerped), so a turning chest carries them on an arc, not on its chord
    this.bq0 = new Float32Array(C * layout.pinRows * 4); this.bq1 = new Float32Array(C * layout.pinRows * 4);
    this.bp0 = new Float32Array(C * layout.pinRows * 3); this.bp1 = new Float32Array(C * layout.pinRows * 3);
    this.rq = new Float32Array(8);
    // constraints
    const cons = [], edges = [], erest = [];
    const ra = layout.rest;
    const dist = (a, b) => Math.hypot(ra[a * 3] - ra[b * 3], ra[a * 3 + 1] - ra[b * 3 + 1], ra[a * 3 + 2] - ra[b * 3 + 2]);
    const add = (a, b, k, strain) => {
      const d = dist(a, b);
      cons.push(a, b, d, k);
      if (strain) { edges.push(a, b); erest.push(d * MAX_STRAIN); }
    };
    const id = (i, j) => j * C + i;
    const sp = this.spec;
    for (let j = 0; j < R; j++) for (let i = 0; i < C; i++) {
      if (i < C - 1) add(id(i, j), id(i + 1, j), sp.stretch, true);
      if (j < R - 1) add(id(i, j), id(i, j + 1), sp.stretch, true);
      if (i < C - 1 && j < R - 1) { add(id(i, j), id(i + 1, j + 1), sp.shear, true); add(id(i + 1, j), id(i, j + 1), sp.shear, true); }
      if (i < C - 2) add(id(i, j), id(i + 2, j), sp.bend, false);
      if (j < R - 2) add(id(i, j), id(i, j + 2), sp.bend, false);
    }
    this.cons = Float32Array.from(cons);
    this.edges = Int32Array.from(edges);
    this.emax = Float32Array.from(erest);
    // tethers: each particle to the pinned particle of its column
    this.tether = new Float32Array(this.n);
    for (let j = 0; j < R; j++) for (let i = 0; i < C; i++) this.tether[id(i, j)] = dist(id(i, j), id(i, 0));
    this.frames = new Float32Array(this.n * 4);
    this.mask = null;
    this.ready = false;
    this.lead = 0;
  }

  /** Store the pinned offsets relative to their bones (call once with bind-pose mq/mp). */
  bindAnchors(mq, mp) {
    const L = this.layout, a = this.anchor, tmp = new Float32Array(4);
    for (let k = 0; k < L.C * L.pinRows; k++) {
      const b = L.anchorBone[k];
      const dx = L.rest[k * 3] - mp[b * 3], dy = L.rest[k * 3 + 1] - mp[b * 3 + 1], dz = L.rest[k * 3 + 2] - mp[b * 3 + 2];
      tmp[0] = -mq[b * 4]; tmp[1] = -mq[b * 4 + 1]; tmp[2] = -mq[b * 4 + 2]; tmp[3] = mq[b * 4 + 3];
      qrot(a, k * 3, tmp, 0, dx, dy, dz);
    }
  }

  /** Bind the pinned particles to their bones (bind-pose model transforms). */
  setBind(mq, mp) { this.bindAnchors(mq, mp); }

  /**
   * Colliders in the bind pose (collide.js capsules updated with the bind transforms): a particle whose rest position
   * is inside a capsule (+ margin) collides with a capsule reduced to its rest depth (the design hangs it there;
   * pushing it out would stretch the sheet at its pins in every frame, ignoring the capsule lets it pass through the
   * limb). Returns { pins, rest, names }: pinned / free particles that start inside a collider (design warnings).
   */
  setColliders(caps) {
    const L = this.layout, C = this.C, nc = caps.count, m = this.spec.margin, pinN = C * L.pinRows;
    this.mask = nc ? new Float32Array(this.n * nc) : null;
    const out = { pins: 0, rest: 0, names: new Set() };
    if (!nc) return out;
    for (let k = 0; k < this.n; k++) {
      const x = L.rest[k * 3], y = L.rest[k * 3 + 1], z = L.rest[k * 3 + 2];
      for (let i = 0; i < nc; i++) {
        const ad = capsuleAxisDist(caps, i, x, y, z);
        if (ad >= caps.data[i * 7 + 6] + m) continue;
        // the first free row (held by its pins, a few cm away) ignores the capsules it rests in; every other particle
        // may be as deep in them as it rests, never deeper (a limb cannot pass through the sheet). A particle on a
        // capsule's axis itself ignores it
        this.mask[k * nc + i] = k < pinN + C || ad < 1e-3 ? -1 : ad * 0.97;
        out.names.add(caps.names[i]);
        if (k < pinN) out.pins++; else out.rest++;
      }
    }
    return out;
  }

  reset() { this.ready = false; this.capReady = false; this.lead = 0; }

  inertia(m) {
    if (!this.ready) return;
    const k = this.spec.inertia;
    shift(this.p, m, k);
    shift(this.pp, m, k);
    shift(this.r0, m, k);
    // last frame's pins and capsules are points of the body: into this frame's model space (the sub-steps interpolate
    // from them; left in last frame's space, the pins lagged by one frame of root motion - twice as far at 30 Hz)
    shift(this.bp0, m, 1);
    const rq = this.rq;
    qfromBasis(rq, 0, [m[0], m[1], m[2]], [m[3], m[4], m[5]], [m[6], m[7], m[8]]);
    for (let i = 0; i < this.bq0.length; i += 4) qmul(this.bq0, i, rq, 0, this.bq0, i);
    if (this.capPrev && this.capReady) {
      const c = this.capPrev;
      for (let i = 0; i < c.length; i += 7) for (let e = i; e <= i + 3; e += 3) {
        const x = c[e], y = c[e + 1], z = c[e + 2];
        c[e] = m[0] * x + m[3] * y + m[6] * z + m[9]; c[e + 1] = m[1] * x + m[4] * y + m[7] * z + m[10]; c[e + 2] = m[2] * x + m[5] * y + m[8] * z + m[11];
      }
    }
  }

  _anchors(mq, mp, out) {
    const L = this.layout, a = this.anchor, bq = this.bq1, bp = this.bp1;
    for (let k = 0; k < L.C * L.pinRows; k++) {
      const b = L.anchorBone[k];
      qrot(out, k * 3, mq, b * 4, a[k * 3], a[k * 3 + 1], a[k * 3 + 2]);
      out[k * 3] += mp[b * 3]; out[k * 3 + 1] += mp[b * 3 + 1]; out[k * 3 + 2] += mp[b * 3 + 2];
      bq[k * 4] = mq[b * 4]; bq[k * 4 + 1] = mq[b * 4 + 1]; bq[k * 4 + 2] = mq[b * 4 + 2]; bq[k * 4 + 3] = mq[b * 4 + 3];
      bp[k * 3] = mp[b * 3]; bp[k * 3 + 1] = mp[b * 3 + 1]; bp[k * 3 + 2] = mp[b * 3 + 2];
    }
  }

  /** Hang the cloth from its current anchors (rest offsets below the pinned row, unrotated), then pre-settle. */
  _snap(mq, mp, gravity, capsules, floorY) {
    const L = this.layout, C = this.C, pinN = C * L.pinRows, p = this.p, pp = this.pp;
    this._anchors(mq, mp, this.anchorTarget);
    for (let k = 0; k < this.n; k++) {
      const top = k < pinN ? k : k % C;
      const ax = this.anchorTarget[top * 3], ay = this.anchorTarget[top * 3 + 1], az = this.anchorTarget[top * 3 + 2];
      if (k < pinN) { p[k * 3] = ax; p[k * 3 + 1] = ay; p[k * 3 + 2] = az; }
      else {
        p[k * 3] = ax + L.rest[k * 3] - L.rest[top * 3];
        p[k * 3 + 1] = ay + L.rest[k * 3 + 1] - L.rest[top * 3 + 1];
        p[k * 3 + 2] = az + L.rest[k * 3 + 2] - L.rest[top * 3 + 2];
      }
    }
    pp.set(p);
    this.bq0.set(this.bq1); this.bp0.set(this.bp1);
    this.ready = true;
    this.capReady = false;
    this.lead = 0;
    // pre-settle against the body so a pose capture or a respawn never starts in a stiff, intersecting shape
    for (let i = 0; i < 10; i++) this.update(1 / 30, mq, mp, gravity, ZERO3, capsules, floorY, 0, true);
    pp.set(p); this.r0.set(p); this.rp.set(p);
    this.lead = 0;
  }

  /**
   * Advance the simulation to this frame. Fixed steps of CLOTH_STEP game seconds (the sim runs up to one step ahead of
   * the frame; pins and capsules are interpolated / extrapolated linearly over the frame), rendered positions
   * interpolated to the frame time. gravity / wind: model-space accelerations (m/s^2); capsules from collide.js;
   * floorY model.
   */
  update(dt, mq, mp, gravity, wind, capsules, floorY, time, settling = false) {
    if (!this.ready && !settling) this._snap(mq, mp, gravity, capsules, floorY);
    const C = this.C, pinN = C * this.layout.pinRows, p = this.p;
    this._anchors(mq, mp, this.anchorTarget);
    if (!(dt > 0)) { // frozen (hit-stop): pins stay attached, nothing else moves
      for (let k = 0; k < pinN * 3; k++) this.rp[k] = this.anchorTarget[k];
      return;
    }
    dt = Math.min(dt, MAX_STEPS * CLOTH_STEP);
    // capsules move from where they were last frame to where they are now
    let caps = capsules;
    if (capsules && capsules.count) {
      if (!this.capPrev || this.capPrev.length !== capsules.data.length) {
        this.capPrev = new Float32Array(capsules.data.length);
        this.capTmp = { count: capsules.count, data: new Float32Array(capsules.data.length) };
      }
      if (!this.capReady || settling) this.capPrev.set(capsules.data);
      caps = this.capTmp;
    }
    this.lead -= dt;
    let steps = 0;
    while (this.lead < -1e-9 && steps < MAX_STEPS) {
      const f = 1 + (this.lead + CLOTH_STEP) / dt; // end of this step: 0 = last frame, 1 = now (> 1: extrapolated)
      if (caps !== capsules) {
        const a0 = this.capPrev, b0 = capsules.data, o0 = caps.data;
        for (let i = 0; i < o0.length; i++) o0[i] = a0[i] + (b0[i] - a0[i]) * f;
      }
      const bq0 = this.bq0, bq1 = this.bq1, bp0 = this.bp0, bp1 = this.bp1, a = this.anchor, rq = this.rq;
      for (let k = 0; k < pinN; k++) {
        qslerp(rq, 4, bq0, k * 4, bq1, k * 4, f);
        qrot(p, k * 3, rq, 4, a[k * 3], a[k * 3 + 1], a[k * 3 + 2]);
        p[k * 3] += bp0[k * 3] + (bp1[k * 3] - bp0[k * 3]) * f;
        p[k * 3 + 1] += bp0[k * 3 + 1] + (bp1[k * 3 + 1] - bp0[k * 3 + 1]) * f;
        p[k * 3 + 2] += bp0[k * 3 + 2] + (bp1[k * 3 + 2] - bp0[k * 3 + 2]) * f;
      }
      this.r0.set(p);
      this._step(gravity, wind, caps, floorY, time + this.lead + CLOTH_STEP);
      this.lead += CLOTH_STEP;
      steps++;
    }
    if (this.lead < 0) this.lead = 0; // more than MAX_STEPS behind (a frame spike): drop the time
    this.bq0.set(this.bq1); this.bp0.set(this.bp1);
    if (caps !== capsules) { this.capPrev.set(capsules.data); this.capReady = true; }
    // rendered state at the frame time: between the last two steps; pins exactly on their anchors
    const al = 1 - this.lead / CLOTH_STEP, r0 = this.r0, rp = this.rp;
    for (let k = 0; k < pinN * 3; k++) rp[k] = this.anchorTarget[k];
    for (let k = pinN * 3; k < this.n * 3; k++) rp[k] = r0[k] + (p[k] - r0[k]) * al;
    // failsafe
    for (let k = 0; k < this.n * 3; k++) {
      if (!(Math.abs(p[k]) < 50)) { this.ready = false; break; }
    }
  }

  /** One fixed step: verlet integration, distance constraints, strain limit, tethers, capsules, floor. */
  _step(gravity, wind, caps, floorY, tt) {
    const s = this.spec, C = this.C, n = this.n, p = this.p, pp = this.pp, inv = this.inv, h = CLOTH_STEP, h2 = h * h;
    const pinN = C * this.layout.pinRows, mask = this.mask, nc = caps ? caps.count : 0;
    const damp = 1 - s.damping, vmax = s.maxSpeed * h;
    for (let k = pinN; k < n; k++) {
      const o = k * 3, i = k % C, j = (k / C) | 0;
      let vx = (p[o] - pp[o]) * damp, vy = (p[o + 1] - pp[o + 1]) * damp, vz = (p[o + 2] - pp[o + 2]) * damp;
      const vl = Math.sqrt(vx * vx + vy * vy + vz * vz);
      if (vl > vmax) { const c = vmax / vl; vx *= c; vy *= c; vz *= c; }
      const gust = s.wind * (0.65 + 0.35 * Math.sin(tt * 1.7 + i * 0.45 + j * 0.3) * Math.sin(tt * 0.63 + j * 0.21));
      pp[o] = p[o]; pp[o + 1] = p[o + 1]; pp[o + 2] = p[o + 2];
      p[o] += vx + (gravity[0] * s.gravity + wind[0] * gust) * h2;
      p[o + 1] += vy + (gravity[1] * s.gravity + wind[1] * gust) * h2;
      p[o + 2] += vz + (gravity[2] * s.gravity + wind[2] * gust) * h2;
    }
    const cons = this.cons, nc4 = cons.length;
    for (let it = 0; it < this.iters; it++) {
      for (let c = 0; c < nc4; c += 4) {
        const a = cons[c] * 3, b = cons[c + 1] * 3, wa = inv[cons[c]], wb = inv[cons[c + 1]], ws = wa + wb;
        if (ws === 0) continue;
        const dx = p[b] - p[a], dy = p[b + 1] - p[a + 1], dz = p[b + 2] - p[a + 2];
        const l = Math.sqrt(dx * dx + dy * dy + dz * dz);
        if (l < 1e-7) continue;
        const corr = ((l - cons[c + 2]) / (l * ws)) * cons[c + 3];
        p[a] += dx * corr * wa; p[a + 1] += dy * corr * wa; p[a + 2] += dz * corr * wa;
        p[b] -= dx * corr * wb; p[b + 1] -= dy * corr * wb; p[b + 2] -= dz * corr * wb;
      }
    }
    // tethers, then body collision (contact particles are remembered); only capsules near the sheet are tested
    const contact = this.contact, fy = floorY + Math.max(s.margin * 0.6, (s.thickness ?? 0.012) * 0.5 + 0.004 * this.K);
    const ci = this.capIdx || (this.capIdx = new Int16Array(Math.max(1, nc)));
    const na = nc ? capsulesNear(caps, p, pinN, n, s.margin + 0.05 * this.K, ci) : 0;
    for (let k = pinN; k < n; k++) {
      const o = k * 3, t = (k % C) * 3, maxd = this.tether[k] * s.tether;
      const dx = p[o] - p[t], dy = p[o + 1] - p[t + 1], dz = p[o + 2] - p[t + 2];
      const l = Math.sqrt(dx * dx + dy * dy + dz * dz);
      if (l > maxd) { const c = maxd / l; p[o] = p[t] + dx * c; p[o + 1] = p[t + 1] + dy * c; p[o + 2] = p[t + 2] + dz * c; }
      contact[k] = na && pushOutCapsules(p, o, caps, s.margin, mask, k * nc, ci, na) ? 1 : 0;
    }
    // strain limit after collision: no structural / shear edge longer than MAX_STRAIN x rest. An over-long edge whose
    // segment runs through a capsule (its two particles pushed to opposite sides of a limb) is first moved out of that
    // capsule as a whole, so the sheet wraps round the limb on one side instead of being torn across it; the length is
    // then restored with the particles that touch the body held (they move 1/4 as much as a free particle)
    const E = this.edges, emax = this.emax, ne = E.length;
    for (let pass = 0; pass < STRAIN_PASSES; pass++) {
      for (let e = 0; e < ne; e += 2) {
        const ia = E[e], ib = E[e + 1];
        let wa = inv[ia], wb = inv[ib];
        if (wa + wb === 0) continue;
        const a = ia * 3, b = ib * 3;
        let dx = p[b] - p[a], dy = p[b + 1] - p[a + 1], dz = p[b + 2] - p[a + 2];
        const l2 = dx * dx + dy * dy + dz * dz, lm = emax[e >> 1];
        if (l2 <= lm * lm) continue;
        if (na && pass === 0) edgeOut(p, a, b, caps, s.margin, mask, ia * nc, ib * nc, wa, wb, ci, na);
        dx = p[b] - p[a]; dy = p[b + 1] - p[a + 1]; dz = p[b + 2] - p[a + 2];
        const l = Math.sqrt(dx * dx + dy * dy + dz * dz);
        if (!(l > lm)) continue;
        if (contact[ia] && wa > 0) wa *= 0.25;
        if (contact[ib] && wb > 0) wb *= 0.25;
        const corr = (l - lm) / (l * (wa + wb));
        p[a] += dx * corr * wa; p[a + 1] += dy * corr * wa; p[a + 2] += dz * corr * wa;
        p[b] -= dx * corr * wb; p[b + 1] -= dy * corr * wb; p[b + 2] -= dz * corr * wb;
      }
    }
    // final collision + floor (the floor keeps the rendered layers above y = floorY too)
    for (let k = pinN; k < n; k++) {
      const o = k * 3;
      if (na) pushOutCapsules(p, o, caps, s.margin, mask, k * nc, ci, na);
      if (p[o + 1] < fy) {
        p[o + 1] = fy;
        pp[o] += (p[o] - pp[o]) * 0.6; pp[o + 2] += (p[o + 2] - pp[o + 2]) * 0.6; // friction
      }
    }
  }

  /** Write rendered particle positions + frames into the rig's local arrays (cloth bones are model-space roots). */
  write(lq, lp) {
    computeFrames(this.rp, this.C, this.R, this.frames);
    const f = this.first;
    lp.set(this.rp, f * 3);
    lq.set(this.frames, f * 4);
  }
}
