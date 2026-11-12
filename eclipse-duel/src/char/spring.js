// Spring bones (plumes, tassets, straps): each bone's tip is a damped verlet particle pulled toward where the
// animation puts it, with gravity, inertia from root motion, an angle limit and capsule collision. Simulated in model
// (fighter-local) space so facing flips are free.

import { qmul, qmulInv, qrot, qfromTo } from './rigmath.js';
import { pushOutCapsules } from './collide.js';

/**
 * spec: { bones: [names], stiffness=80 (1/s^2), damping=5 (1/s), gravity=0.3 (x g), inertia=1, limit=60 (deg),
 *         radius=0.02 (collision), tip=[x,y,z] (last bone tip in its frame, default [0,-0.1,0]), collide=true }
 */
export class SpringChain {
  constructor(rig, spec) {
    this.rig = rig;
    this.spec = { stiffness: 80, damping: 5, gravity: 0.3, inertia: 1, limit: 60, radius: 0.02, collide: true, ...spec };
    this.idx = spec.bones.map((n) => {
      const i = rig.index[n];
      if (i === undefined) throw new Error('spring: unknown bone ' + n);
      return i;
    });
    const n = this.idx.length;
    // tip offsets in each bone's frame: the next bone's offset, or spec.tip for the last
    this.tipOff = new Float32Array(n * 3);
    for (let k = 0; k < n; k++) {
      if (k < n - 1) this.tipOff.set(rig.offset.subarray(this.idx[k + 1] * 3, this.idx[k + 1] * 3 + 3), k * 3);
      else this.tipOff.set(spec.tip || [0, -0.1, 0], k * 3);
    }
    this.len = new Float32Array(n);
    for (let k = 0; k < n; k++) this.len[k] = Math.hypot(this.tipOff[k * 3], this.tipOff[k * 3 + 1], this.tipOff[k * 3 + 2]) || 1e-3;
    this.p = new Float32Array(n * 3);
    this.pp = new Float32Array(n * 3);
    this.ready = false;
    this.t = new Float32Array(16);
  }

  reset() { this.ready = false; }

  /** Shift particle state by the per-frame inertial transform m (3x4, column-major 12 floats) scaled by inertia. */
  inertia(m) {
    if (!this.ready) return;
    shift(this.p, m, this.spec.inertia);
    shift(this.pp, m, this.spec.inertia);
  }

  /**
   * Simulate and write local rotations. Requires FK of the parents (mq/mp valid for the chain's parent);
   * updates mq/mp of the chain bones as it goes.
   */
  update(dt, lq, lp, mq, mp, gravity, capsules) {
    const rig = this.rig, s = this.spec, n = this.idx.length, t = this.t;
    const k = s.stiffness, damp = Math.exp(-s.damping * dt), lim = Math.cos((s.limit * Math.PI) / 180);
    for (let c = 0; c < n; c++) {
      const i = this.idx[c], par = rig.parent[i];
      // bone position and rest rotation from the (already simulated) parent
      qrot(mp, i * 3, mq, par * 4, lp[i * 3], lp[i * 3 + 1], lp[i * 3 + 2]);
      mp[i * 3] += mp[par * 3]; mp[i * 3 + 1] += mp[par * 3 + 1]; mp[i * 3 + 2] += mp[par * 3 + 2];
      qmul(t, 0, mq, par * 4, rig.restRot, i * 4);                    // rest model rotation
      qrot(t, 4, t, 0, this.tipOff[c * 3], this.tipOff[c * 3 + 1], this.tipOff[c * 3 + 2]);
      const bx = mp[i * 3], by = mp[i * 3 + 1], bz = mp[i * 3 + 2], L = this.len[c];
      const rx = t[4] / L, ry = t[5] / L, rz = t[6] / L;              // rest direction
      const tx = bx + t[4], ty = by + t[5], tz = bz + t[6];           // rest tip
      const o = c * 3, p = this.p, pp = this.pp;
      if (!this.ready || dt <= 0) {
        if (!this.ready) { p[o] = pp[o] = tx; p[o + 1] = pp[o + 1] = ty; p[o + 2] = pp[o + 2] = tz; }
      } else {
        const vx = (p[o] - pp[o]) * damp, vy = (p[o + 1] - pp[o + 1]) * damp, vz = (p[o + 2] - pp[o + 2]) * damp;
        pp[o] = p[o]; pp[o + 1] = p[o + 1]; pp[o + 2] = p[o + 2];
        const dt2 = dt * dt;
        p[o] += vx + (k * (tx - p[o]) + gravity[0] * s.gravity) * dt2;
        p[o + 1] += vy + (k * (ty - p[o + 1]) + gravity[1] * s.gravity) * dt2;
        p[o + 2] += vz + (k * (tz - p[o + 2]) + gravity[2] * s.gravity) * dt2;
      }
      // length + collision + cone limit
      for (let it = 0; it < 2; it++) {
        let dx = p[o] - bx, dy = p[o + 1] - by, dz = p[o + 2] - bz;
        let l = Math.hypot(dx, dy, dz) || 1e-6;
        dx /= l; dy /= l; dz /= l;
        const cs = dx * rx + dy * ry + dz * rz;
        if (cs < lim) { // pull back inside the cone
          let ox = dx - rx * cs, oy = dy - ry * cs, oz = dz - rz * cs;
          const ol = Math.hypot(ox, oy, oz) || 1;
          const sl = Math.sqrt(1 - lim * lim);
          dx = rx * lim + (ox / ol) * sl; dy = ry * lim + (oy / ol) * sl; dz = rz * lim + (oz / ol) * sl;
        }
        p[o] = bx + dx * L; p[o + 1] = by + dy * L; p[o + 2] = bz + dz * L;
        if (s.collide && capsules) pushOutCapsules(p, o, capsules, s.radius);
      }
      // orient the bone toward the particle
      let dx = p[o] - bx, dy = p[o + 1] - by, dz = p[o + 2] - bz;
      const l = Math.hypot(dx, dy, dz) || 1e-6;
      dx /= l; dy /= l; dz /= l;
      qfromTo(t, 8, rx, ry, rz, dx, dy, dz);
      qmul(mq, i * 4, t, 8, t, 0);
      qmulInv(lq, i * 4, mq, par * 4, mq, i * 4);
    }
    this.ready = true;
  }
}

/** Apply affine 3x4 m (column-major [r00 r10 r20 r01 r11 r21 r02 r12 r22 tx ty tz]) blended by k to points. */
export function shift(a, m, k) {
  for (let i = 0; i < a.length; i += 3) {
    const x = a[i], y = a[i + 1], z = a[i + 2];
    const nx = m[0] * x + m[3] * y + m[6] * z + m[9], ny = m[1] * x + m[4] * y + m[7] * z + m[10], nz = m[2] * x + m[5] * y + m[8] * z + m[11];
    a[i] = x + (nx - x) * k; a[i + 1] = y + (ny - y) * k; a[i + 2] = z + (nz - z) * k;
  }
}
