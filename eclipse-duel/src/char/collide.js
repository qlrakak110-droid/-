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

/** Push point p[o..o+2] out of every capsule (radius + margin). Returns true if moved. */
export function pushOutCapsules(p, o, caps, margin) {
  const d = caps.data;
  let moved = false;
  const x = p[o], y = p[o + 1], z = p[o + 2];
  for (let i = 0; i < caps.count; i++) {
    const c = i * CAP_STRIDE;
    const ax = d[c], ay = d[c + 1], az = d[c + 2];
    // early out: farther than radius + margin + half the segment from the segment's midpoint
    const mx = x - 0.5 * (ax + d[c + 3]), my = y - 0.5 * (ay + d[c + 4]), mz = z - 0.5 * (az + d[c + 5]);
    const hx = 0.5 * (d[c + 3] - ax), hy = 0.5 * (d[c + 4] - ay), hz = 0.5 * (d[c + 5] - az);
    const reach = d[c + 6] + margin;
    if (mx * mx + my * my + mz * mz > reach * reach + 2 * reach * Math.sqrt(hx * hx + hy * hy + hz * hz) + hx * hx + hy * hy + hz * hz) continue;
    const ex = d[c + 3] - ax, ey = d[c + 4] - ay, ez = d[c + 5] - az;
    const px = p[o] - ax, py = p[o + 1] - ay, pz = p[o + 2] - az;
    const ee = ex * ex + ey * ey + ez * ez;
    let t = ee > 1e-9 ? (px * ex + py * ey + pz * ez) / ee : 0;
    t = t < 0 ? 0 : t > 1 ? 1 : t;
    const qx = px - ex * t, qy = py - ey * t, qz = pz - ez * t;
    const r = d[c + 6] + margin, dd = qx * qx + qy * qy + qz * qz;
    if (dd < r * r) {
      const l = Math.sqrt(dd);
      if (l > 1e-6) { const k = r / l; p[o] = ax + ex * t + qx * k; p[o + 1] = ay + ey * t + qy * k; p[o + 2] = az + ez * t + qz * k; }
      else p[o] -= r;
      moved = true;
    }
  }
  return moved;
}
