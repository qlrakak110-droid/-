// Verlet cloth (capes, tabards, waist cloth). Particles live in model (fighter-local) space; root motion feeds back
// as inertia, so facing flips and teleports never disturb it. Each particle drives one "cloth bone"; the render mesh
// is part of a merged SkinnedMesh, bilinearly weighted to 4 particle bones (smooth surface from a coarse grid, normals
// from per-particle frames, zero CPU vertex work).
//
// Stability: sub-stepping, Gauss-Seidel distance constraints (stretch / shear / bend), long-range tethers to the pinned
// row (no runaway stretch), velocity clamp, capsule + floor collision, NaN / explosion failsafe.

import * as THREE from 'three';
import { qrot, qfromBasis } from './rigmath.js';
import { pushOutCapsules } from './collide.js';
import { shift } from './spring.js';

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
export function computeFrames(p, C, R, out) {
  const X = [0, 0, 0], Y = [0, 0, 0], Z = [0, 0, 0];
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
  // rim: walk the border and stitch outer to inner
  const border = [];
  for (let gu = 0; gu < NU; gu++) border.push(gu);
  for (let gv = 1; gv < NV; gv++) border.push(gv * NU + NU - 1);
  for (let gu = NU - 2; gu >= 0; gu--) border.push((NV - 1) * NU + gu);
  for (let gv = NV - 2; gv >= 1; gv--) border.push(gv * NU);
  for (let k = 0; k < border.length; k++) {
    const a = border[k], b = border[(k + 1) % border.length];
    idx.push(bo + a, bi + a, bo + b, bo + b, bi + a, bi + b);
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setIndex(idx);
  // orientation: outer faces must point along +outward particle normal
  geo.computeVertexNormals();
  const N = geo.attributes.normal.array;
  qrot(n, 0, frames, Math.floor(C / 2) * 4 + Math.floor(R / 2) * C * 4, 1, 0, 0);
  const mid = bo + Math.floor(NV / 2) * NU + Math.floor(NU / 2);
  if ((N[mid * 3] * n[0] + N[mid * 3 + 1] * n[1] + N[mid * 3 + 2] * n[2]) * outward < 0) {
    const a = geo.index.array;
    for (let i = 0; i < a.length; i += 3) { const t = a[i + 1]; a[i + 1] = a[i + 2]; a[i + 2] = t; }
    geo.computeVertexNormals();
  }
  return { geo, weights: (i) => wts[i], layer: (i) => layer[i] };
}

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
    this.first = rig.index[layout.bones[0].name];
    this.iters = Math.max(4, Math.round(5 + 5 * Math.min(1, quality)));
    this.p = new Float32Array(this.n * 3);
    this.pp = new Float32Array(this.n * 3);
    this.inv = new Float32Array(this.n).fill(1);
    for (let k = 0; k < C * layout.pinRows; k++) this.inv[k] = 0;
    // anchors: pinned particle offsets in their bone's bind frame
    this.anchor = new Float32Array(C * layout.pinRows * 3);
    this.anchorTarget = new Float32Array(C * layout.pinRows * 3);
    this.anchorStart = new Float32Array(C * layout.pinRows * 3);
    // constraints
    const cons = [];
    const add = (a, b, k) => {
      const ra = layout.rest, d = Math.hypot(ra[a * 3] - ra[b * 3], ra[a * 3 + 1] - ra[b * 3 + 1], ra[a * 3 + 2] - ra[b * 3 + 2]);
      cons.push(a, b, d, k);
    };
    const id = (i, j) => j * C + i;
    const sp = this.spec;
    for (let j = 0; j < R; j++) for (let i = 0; i < C; i++) {
      if (i < C - 1) add(id(i, j), id(i + 1, j), sp.stretch);
      if (j < R - 1) add(id(i, j), id(i, j + 1), sp.stretch);
      if (i < C - 1 && j < R - 1) { add(id(i, j), id(i + 1, j + 1), sp.shear); add(id(i + 1, j), id(i, j + 1), sp.shear); }
      if (i < C - 2) add(id(i, j), id(i + 2, j), sp.bend);
      if (j < R - 2) add(id(i, j), id(i, j + 2), sp.bend);
    }
    this.cons = Float32Array.from(cons);
    // tethers: each particle to the pinned particle of its column
    this.tether = new Float32Array(this.n);
    for (let j = 0; j < R; j++) for (let i = 0; i < C; i++) {
      const k = id(i, j), t = id(i, 0), ra = layout.rest;
      this.tether[k] = Math.hypot(ra[k * 3] - ra[t * 3], ra[k * 3 + 1] - ra[t * 3 + 1], ra[k * 3 + 2] - ra[t * 3 + 2]);
    }
    this.frames = new Float32Array(this.n * 4);
    this.ready = false;
    this._bindReady = false;
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
    this._bindReady = true;
  }

  reset() { this.ready = false; }

  inertia(m) {
    if (!this.ready) return;
    const k = this.spec.inertia;
    shift(this.p, m, k);
    shift(this.pp, m, k);
  }

  _anchors(mq, mp, out) {
    const L = this.layout, a = this.anchor;
    for (let k = 0; k < L.C * L.pinRows; k++) {
      const b = L.anchorBone[k];
      qrot(out, k * 3, mq, b * 4, a[k * 3], a[k * 3 + 1], a[k * 3 + 2]);
      out[k * 3] += mp[b * 3]; out[k * 3 + 1] += mp[b * 3 + 1]; out[k * 3 + 2] += mp[b * 3 + 2];
    }
  }

  /** Place the cloth at its rest shape relative to the current anchors (no motion). */
  _snap(mq, mp) {
    // rigidly carry the rest layout with the first anchor bone's transform
    const L = this.layout, b = L.anchorBone[0], tmp = new Float32Array(3), bq = this._bindQ;
    const iq = [-bq[0], -bq[1], -bq[2], bq[3]];
    for (let k = 0; k < this.n; k++) {
      // rest offset from the bone's bind position, re-expressed with its current transform
      const dx = L.rest[k * 3] - this._bindP[0], dy = L.rest[k * 3 + 1] - this._bindP[1], dz = L.rest[k * 3 + 2] - this._bindP[2];
      qrot(tmp, 0, iq, 0, dx, dy, dz);
      qrot(tmp, 0, mq, b * 4, tmp[0], tmp[1], tmp[2]);
      this.p[k * 3] = this.pp[k * 3] = mp[b * 3] + tmp[0];
      this.p[k * 3 + 1] = this.pp[k * 3 + 1] = mp[b * 3 + 1] + tmp[1];
      this.p[k * 3 + 2] = this.pp[k * 3 + 2] = mp[b * 3 + 2] + tmp[2];
    }
    this.ready = true;
  }

  /** Remember the bind transform of the main anchor bone (for snapping). */
  setBind(mq, mp) {
    const b = this.layout.anchorBone[0];
    this._bindQ = [mq[b * 4], mq[b * 4 + 1], mq[b * 4 + 2], mq[b * 4 + 3]];
    this._bindP = [mp[b * 3], mp[b * 3 + 1], mp[b * 3 + 2]];
    this.bindAnchors(mq, mp);
  }

  /**
   * Step the simulation. gravity / wind: model-space accelerations (m/s^2); capsules from collide.js; floorY model.
   */
  update(dt, mq, mp, gravity, wind, capsules, floorY, time) {
    if (!this.ready) this._snap(mq, mp);
    const s = this.spec, C = this.C, n = this.n, p = this.p, pp = this.pp, inv = this.inv;
    const pinN = C * this.layout.pinRows;
    this.anchorStart.set(p.subarray(0, pinN * 3));
    this._anchors(mq, mp, this.anchorTarget);
    if (dt <= 0) { // frozen (hit-stop): keep pins attached, nothing else moves
      p.set(this.anchorTarget, 0); pp.set(this.anchorTarget, 0);
      return;
    }
    dt = Math.min(dt, 1 / 30);
    const steps = dt > 1 / 55 ? 3 : 2, h = dt / steps, h2 = h * h;
    const damp = 1 - s.damping;
    const vmax = s.maxSpeed * h;
    const cons = this.cons, nc = cons.length;
    for (let st = 1; st <= steps; st++) {
      const f = st / steps;
      for (let k = 0; k < pinN; k++) {
        const o = k * 3;
        pp[o] = p[o]; pp[o + 1] = p[o + 1]; pp[o + 2] = p[o + 2];
        p[o] = this.anchorStart[o] + (this.anchorTarget[o] - this.anchorStart[o]) * f;
        p[o + 1] = this.anchorStart[o + 1] + (this.anchorTarget[o + 1] - this.anchorStart[o + 1]) * f;
        p[o + 2] = this.anchorStart[o + 2] + (this.anchorTarget[o + 2] - this.anchorStart[o + 2]) * f;
      }
      const tt = time + h * st;
      for (let k = pinN; k < n; k++) {
        const o = k * 3, i = k % C, j = (k / C) | 0;
        let vx = (p[o] - pp[o]) * damp, vy = (p[o + 1] - pp[o + 1]) * damp, vz = (p[o + 2] - pp[o + 2]) * damp;
        const vl = Math.hypot(vx, vy, vz);
        if (vl > vmax) { const c = vmax / vl; vx *= c; vy *= c; vz *= c; }
        const gust = s.wind * (0.65 + 0.35 * Math.sin(tt * 1.7 + i * 0.45 + j * 0.3) * Math.sin(tt * 0.63 + j * 0.21));
        pp[o] = p[o]; pp[o + 1] = p[o + 1]; pp[o + 2] = p[o + 2];
        p[o] += vx + (gravity[0] * s.gravity + wind[0] * gust) * h2;
        p[o + 1] += vy + (gravity[1] * s.gravity + wind[1] * gust) * h2;
        p[o + 2] += vz + (gravity[2] * s.gravity + wind[2] * gust) * h2;
      }
      for (let it = 0; it < this.iters; it++) {
        for (let c = 0; c < nc; c += 4) {
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
      // tethers + collision
      for (let k = pinN; k < n; k++) {
        const o = k * 3, t = (k % C) * 3, maxd = this.tether[k] * s.tether;
        const dx = p[o] - p[t], dy = p[o + 1] - p[t + 1], dz = p[o + 2] - p[t + 2];
        const l = Math.sqrt(dx * dx + dy * dy + dz * dz);
        if (l > maxd) { const c = maxd / l; p[o] = p[t] + dx * c; p[o + 1] = p[t + 1] + dy * c; p[o + 2] = p[t + 2] + dz * c; }
        if (capsules) pushOutCapsules(p, o, capsules, s.margin);
        const fy = floorY + s.margin * 0.6;
        if (p[o + 1] < fy) {
          p[o + 1] = fy;
          pp[o] += (p[o] - pp[o]) * 0.6; pp[o + 2] += (p[o + 2] - pp[o + 2]) * 0.6; // friction
        }
      }
    }
    // failsafe
    for (let k = 0; k < n * 3; k++) {
      if (!(Math.abs(p[k]) < 50)) { this.ready = false; this._snap(mq, mp); break; }
    }
  }

  /** Write particle positions + frames into the rig's local arrays (cloth bones are model-space roots). */
  write(lq, lp) {
    computeFrames(this.p, this.C, this.R, this.frames);
    const f = this.first;
    lp.set(this.p, f * 3);
    lq.set(this.frames, f * 4);
  }
}

