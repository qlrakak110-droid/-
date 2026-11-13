// Body collision capsules for cloth and spring bones, evaluated in model (fighter-local) space every frame.

import { qrot } from './rigmath.js';

export const CAP_STRIDE = 7; // ax ay az bx by bz r

/**
 * Capsule set from design colliders: [{ name, a: [bone, [x,y,z]], b: [bone, [x,y,z]], r }].
 */
export function createCapsules(rig, defs) {
  const n = defs.length;
  const caps = {
    count: n,
    data: new Float32Array(n * CAP_STRIDE),
    names: defs.map((d) => d.name || ''),
    bones: new Int16Array(n * 2),
    offs: new Float32Array(n * 6),
    r: new Float32Array(n),
  };
  defs.forEach((d, i) => {
    const ba = rig.index[d.a[0]], bb = rig.index[d.b[0]];
    if (ba === undefined || bb === undefined) throw new Error('collider ' + d.name + ': unknown bone');
    caps.bones[i * 2] = ba; caps.bones[i * 2 + 1] = bb;
    caps.offs.set(d.a[1] || [0, 0, 0], i * 6); caps.offs.set(d.b[1] || [0, 0, 0], i * 6 + 3);
    caps.r[i] = d.r;
  });
  return caps;
}

/** Recompute capsule endpoints from model-space bone transforms. */
export function updateCapsules(caps, mq, mp) {
  const d = caps.data;
  for (let i = 0; i < caps.count; i++) {
    const o = i * CAP_STRIDE;
    for (let e = 0; e < 2; e++) {
      const b = caps.bones[i * 2 + e], f = caps.offs, fo = i * 6 + e * 3;
      qrot(d, o + e * 3, mq, b * 4, f[fo], f[fo + 1], f[fo + 2]);
      d[o + e * 3] += mp[b * 3]; d[o + e * 3 + 1] += mp[b * 3 + 1]; d[o + e * 3 + 2] += mp[b * 3 + 2];
    }
    d[o + 6] = caps.r[i];
  }
}

/** Distance (m) from point (x, y, z) to the axis segment of capsule i (minus nothing: compare with the radius). */
export function capsuleAxisDist(caps, i, x, y, z) {
  const d = caps.data, c = i * CAP_STRIDE;
  const ax = d[c], ay = d[c + 1], az = d[c + 2], ex = d[c + 3] - ax, ey = d[c + 4] - ay, ez = d[c + 5] - az;
  const ee = ex * ex + ey * ey + ez * ez;
  let t = ee > 1e-12 ? ((x - ax) * ex + (y - ay) * ey + (z - az) * ez) / ee : 0;
  t = t < 0 ? 0 : t > 1 ? 1 : t;
  return Math.hypot(x - ax - ex * t, y - ay - ey * t, z - az - ez * t);
}

/**
 * Push point p[o..o+2] out of every capsule (radius + margin). depth (optional, Float32Array): depth[mo + i] > 0 is the
 * reduced radius capsule i has for this point (a cloth particle that rests inside it by design may stay as deep as it
 * rests, never deeper), < 0 skips the capsule. idx / nidx (optional): only test these capsule indices (a broad phase).
 * Returns true if moved.
 */
export function pushOutCapsules(p, o, caps, margin, depth = null, mo = 0, idx = null, nidx = 0) {
  const d = caps.data;
  let moved = false;
  const x = p[o], y = p[o + 1], z = p[o + 2];
  const nn = idx ? nidx : caps.count;
  for (let j = 0; j < nn; j++) {
    const i = idx ? idx[j] : j;
    const dr = depth ? depth[mo + i] : 0;
    if (dr < 0) continue;
    const c = i * CAP_STRIDE;
    const ax = d[c], ay = d[c + 1], az = d[c + 2];
    // early out: farther than radius + margin + half the segment from the segment's midpoint
    const mx = x - 0.5 * (ax + d[c + 3]), my = y - 0.5 * (ay + d[c + 4]), mz = z - 0.5 * (az + d[c + 5]);
    const hx = 0.5 * (d[c + 3] - ax), hy = 0.5 * (d[c + 4] - ay), hz = 0.5 * (d[c + 5] - az);
    const reach = dr > 0 ? dr : d[c + 6] + margin;
    if (mx * mx + my * my + mz * mz > reach * reach + 2 * reach * Math.sqrt(hx * hx + hy * hy + hz * hz) + hx * hx + hy * hy + hz * hz) continue;
    const ex = d[c + 3] - ax, ey = d[c + 4] - ay, ez = d[c + 5] - az;
    const px = p[o] - ax, py = p[o + 1] - ay, pz = p[o + 2] - az;
    const ee = ex * ex + ey * ey + ez * ez;
    let t = ee > 1e-9 ? (px * ex + py * ey + pz * ez) / ee : 0;
    t = t < 0 ? 0 : t > 1 ? 1 : t;
    const qx = px - ex * t, qy = py - ey * t, qz = pz - ez * t;
    const r = reach, dd = qx * qx + qy * qy + qz * qz;
    if (dd < r * r) {
      const l = Math.sqrt(dd);
      if (l > 1e-6) { const k = r / l; p[o] = ax + ex * t + qx * k; p[o + 1] = ay + ey * t + qy * k; p[o + 2] = az + ez * t + qz * k; }
      else p[o] -= r;
      moved = true;
    }
  }
  return moved;
}

/**
 * Broad phase: indices of the capsules whose bounding box (+ margin) overlaps the box of points p[from..to) (stride 3)
 * -> idx; returns their count.
 */
export function capsulesNear(caps, p, from, to, margin, idx) {
  let x0 = Infinity, y0 = Infinity, z0 = Infinity, x1 = -Infinity, y1 = -Infinity, z1 = -Infinity;
  for (let k = from * 3; k < to * 3; k += 3) {
    const x = p[k], y = p[k + 1], z = p[k + 2];
    if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; if (z < z0) z0 = z; if (z > z1) z1 = z;
  }
  const d = caps.data;
  let n = 0;
  for (let i = 0; i < caps.count; i++) {
    const c = i * CAP_STRIDE, r = d[c + 6] + margin;
    if (Math.min(d[c], d[c + 3]) - r > x1 || Math.max(d[c], d[c + 3]) + r < x0) continue;
    if (Math.min(d[c + 1], d[c + 4]) - r > y1 || Math.max(d[c + 1], d[c + 4]) + r < y0) continue;
    if (Math.min(d[c + 2], d[c + 5]) - r > z1 || Math.max(d[c + 2], d[c + 5]) + r < z0) continue;
    idx[n++] = i;
  }
  return n;
}
