// Small allocation-free math helpers for the character runtime: Euler (degrees, order ZXY) <-> quaternion with the
// left-side mirror convention, basis -> quaternion, swing/twist, and clamped Catmull-Rom (Hermite) sampling of keyed
// N-dimensional values. Quaternions are stored as [x, y, z, w] in Float32Array slices (offset `o`).

import { DEG } from '../core/math.js';

/**
 * Euler degrees (order ZXY: R = Rz * Rx * Ry) -> quaternion written into out[o..o+3].
 * `mirror` = true negates X and Y first (left-side bones / mirrored poses: reflection through the fighter's XY plane).
 */
export function eulerToQuat(out, o, x, y, z, mirror = false) {
  if (mirror) { x = -x; y = -y; }
  const hx = x * DEG * 0.5, hy = y * DEG * 0.5, hz = z * DEG * 0.5;
  const c1 = Math.cos(hx), c2 = Math.cos(hy), c3 = Math.cos(hz);
  const s1 = Math.sin(hx), s2 = Math.sin(hy), s3 = Math.sin(hz);
  // three.js Quaternion.setFromEuler, order 'ZXY'
  out[o] = s1 * c2 * c3 - c1 * s2 * s3;
  out[o + 1] = c1 * s2 * c3 + s1 * c2 * s3;
  out[o + 2] = c1 * c2 * s3 + s1 * s2 * c3;
  out[o + 3] = c1 * c2 * c3 - s1 * s2 * s3;
  return out;
}

/** Quaternion product out = a * b (all arrays with offsets; out may alias a or b). */
export function qmul(out, o, a, ao, b, bo) {
  const ax = a[ao], ay = a[ao + 1], az = a[ao + 2], aw = a[ao + 3];
  const bx = b[bo], by = b[bo + 1], bz = b[bo + 2], bw = b[bo + 3];
  out[o] = ax * bw + aw * bx + ay * bz - az * by;
  out[o + 1] = ay * bw + aw * by + az * bx - ax * bz;
  out[o + 2] = az * bw + aw * bz + ax * by - ay * bx;
  out[o + 3] = aw * bw - ax * bx - ay * by - az * bz;
  return out;
}

/** out = conj(a) * b  (a assumed unit). */
export function qmulInv(out, o, a, ao, b, bo) {
  const ax = -a[ao], ay = -a[ao + 1], az = -a[ao + 2], aw = a[ao + 3];
  const bx = b[bo], by = b[bo + 1], bz = b[bo + 2], bw = b[bo + 3];
  out[o] = ax * bw + aw * bx + ay * bz - az * by;
  out[o + 1] = ay * bw + aw * by + az * bx - ax * bz;
  out[o + 2] = az * bw + aw * bz + ax * by - ay * bx;
  out[o + 3] = aw * bw - ax * bx - ay * by - az * bz;
  return out;
}

/** Rotate vector (vx,vy,vz) by quaternion q[qo..]; writes into out[oo..oo+2]. */
export function qrot(out, oo, q, qo, vx, vy, vz) {
  const x = q[qo], y = q[qo + 1], z = q[qo + 2], w = q[qo + 3];
  const tx = 2 * (y * vz - z * vy), ty = 2 * (z * vx - x * vz), tz = 2 * (x * vy - y * vx);
  out[oo] = vx + w * tx + y * tz - z * ty;
  out[oo + 1] = vy + w * ty + z * tx - x * tz;
  out[oo + 2] = vz + w * tz + x * ty - y * tx;
  return out;
}

/** Normalised lerp / slerp of quaternions a,b -> out (shortest path). */
export function qslerp(out, o, a, ao, b, bo, t) {
  let bx = b[bo], by = b[bo + 1], bz = b[bo + 2], bw = b[bo + 3];
  const ax = a[ao], ay = a[ao + 1], az = a[ao + 2], aw = a[ao + 3];
  let cos = ax * bx + ay * by + az * bz + aw * bw;
  if (cos < 0) { cos = -cos; bx = -bx; by = -by; bz = -bz; bw = -bw; }
  let k0, k1;
  if (cos > 0.9995) { k0 = 1 - t; k1 = t; } else {
    const th = Math.acos(cos), s = Math.sin(th);
    k0 = Math.sin((1 - t) * th) / s; k1 = Math.sin(t * th) / s;
  }
  let x = ax * k0 + bx * k1, y = ay * k0 + by * k1, z = az * k0 + bz * k1, w = aw * k0 + bw * k1;
  const l = 1 / (Math.hypot(x, y, z, w) || 1);
  out[o] = x * l; out[o + 1] = y * l; out[o + 2] = z * l; out[o + 3] = w * l;
  return out;
}

export function qnormalize(q, o) {
  const l = 1 / (Math.hypot(q[o], q[o + 1], q[o + 2], q[o + 3]) || 1);
  q[o] *= l; q[o + 1] *= l; q[o + 2] *= l; q[o + 3] *= l;
}

export function qidentity(q, o) { q[o] = 0; q[o + 1] = 0; q[o + 2] = 0; q[o + 3] = 1; }
export function qcopy(out, o, a, ao) { out[o] = a[ao]; out[o + 1] = a[ao + 1]; out[o + 2] = a[ao + 2]; out[o + 3] = a[ao + 3]; }

/** Quaternion from an orthonormal basis given as columns X, Y, Z (each [x,y,z] arrays). */
export function qfromBasis(out, o, X, Y, Z) {
  const m00 = X[0], m10 = X[1], m20 = X[2], m01 = Y[0], m11 = Y[1], m21 = Y[2], m02 = Z[0], m12 = Z[1], m22 = Z[2];
  const tr = m00 + m11 + m22;
  let x, y, z, w;
  if (tr > 0) { const s = 0.5 / Math.sqrt(tr + 1); w = 0.25 / s; x = (m21 - m12) * s; y = (m02 - m20) * s; z = (m10 - m01) * s; }
  else if (m00 > m11 && m00 > m22) { const s = 2 * Math.sqrt(1 + m00 - m11 - m22); w = (m21 - m12) / s; x = 0.25 * s; y = (m01 + m10) / s; z = (m02 + m20) / s; }
  else if (m11 > m22) { const s = 2 * Math.sqrt(1 + m11 - m00 - m22); w = (m02 - m20) / s; x = (m01 + m10) / s; y = 0.25 * s; z = (m12 + m21) / s; }
  else { const s = 2 * Math.sqrt(1 + m22 - m00 - m11); w = (m10 - m01) / s; x = (m02 + m20) / s; y = (m12 + m21) / s; z = 0.25 * s; }
  out[o] = x; out[o + 1] = y; out[o + 2] = z; out[o + 3] = w;
  qnormalize(out, o);
  return out;
}

/**
 * Twist angle (radians) of quaternion q about the unit axis (ax,ay,az) (swing-twist decomposition).
 */
export function twistAngle(q, o, ax, ay, az) {
  const d = q[o] * ax + q[o + 1] * ay + q[o + 2] * az;
  let w = q[o + 3], p = d;
  if (w < 0) { w = -w; p = -p; }
  return 2 * Math.atan2(p, w);
}

/** Axis-angle (unit axis) -> quaternion. */
export function qaxis(out, o, ax, ay, az, ang) {
  const s = Math.sin(ang * 0.5);
  out[o] = ax * s; out[o + 1] = ay * s; out[o + 2] = az * s; out[o + 3] = Math.cos(ang * 0.5);
  return out;
}

/** Shortest rotation taking unit vector a to unit vector b. */
export function qfromTo(out, o, ax, ay, az, bx, by, bz) {
  let w = 1 + ax * bx + ay * by + az * bz;
  let x, y, z;
  if (w < 1e-6) { // opposite: any perpendicular axis
    w = 0;
    if (Math.abs(ax) > Math.abs(az)) { x = -ay; y = ax; z = 0; } else { x = 0; y = -az; z = ay; }
  } else { x = ay * bz - az * by; y = az * bx - ax * bz; z = ax * by - ay * bx; }
  out[o] = x; out[o + 1] = y; out[o + 2] = z; out[o + 3] = w;
  qnormalize(out, o);
  return out;
}

/**
 * Sample a keyed track of `dim`-dimensional values with clamped Catmull-Rom (Hermite) interpolation.
 *   track = { n, dim, times: Float32Array(n), values: Float32Array(n*dim), tangents: Float32Array(n*dim),
 *             eases: Array(n) (fn applied to the segment ENDING at key i), modes: Uint8Array(n) (0 auto, 1 linear, 2 step) }
 * Writes dim values into out[o..]. `t` is clip time (clamped to the key range).
 */
export function sampleTrack(track, t, out, o) {
  const { n, dim, times, values, tangents } = track;
  if (n === 1 || t <= times[0]) { for (let d = 0; d < dim; d++) out[o + d] = values[d]; return out; }
  if (t >= times[n - 1]) { const b = (n - 1) * dim; for (let d = 0; d < dim; d++) out[o + d] = values[b + d]; return out; }
  let i = track._last | 0;
  if (i >= n - 1 || times[i] > t) i = 0;
  while (i < n - 2 && times[i + 1] < t) i++;
  track._last = i;
  const t0 = times[i], t1 = times[i + 1], dt = t1 - t0;
  let u = dt > 1e-9 ? (t - t0) / dt : 1;
  u = track.eases[i + 1](u);
  const mode = track.modes[i + 1];
  const a = i * dim, b = (i + 1) * dim;
  if (mode === 2) { for (let d = 0; d < dim; d++) out[o + d] = u >= 1 ? values[b + d] : values[a + d]; return out; }
  if (mode === 1) { for (let d = 0; d < dim; d++) out[o + d] = values[a + d] + (values[b + d] - values[a + d]) * u; return out; }
  const u2 = u * u, u3 = u2 * u;
  const h00 = 2 * u3 - 3 * u2 + 1, h10 = u3 - 2 * u2 + u, h01 = -2 * u3 + 3 * u2, h11 = u3 - u2;
  for (let d = 0; d < dim; d++) {
    out[o + d] = h00 * values[a + d] + h10 * dt * tangents[a + d] + h01 * values[b + d] + h11 * dt * tangents[b + d];
  }
  return out;
}

/**
 * Compute clamped Catmull-Rom tangents (value per second) for a track. Components that are a local extremum at a key
 * get a flat tangent (no overshoot past keyed values; holds stop dead). Loops wrap; open ends are flat.
 */
export function computeTangents(track, loop, duration) {
  const { n, dim, times, values, tangents } = track;
  for (let i = 0; i < n; i++) {
    for (let d = 0; d < dim; d++) {
      let m = 0;
      const v = values[i * dim + d];
      let prev, next, tp, tn;
      if (i > 0) { prev = values[(i - 1) * dim + d]; tp = times[i - 1]; }
      else if (loop && n > 2) { prev = values[(n - 2) * dim + d]; tp = times[n - 2] - duration; }
      if (i < n - 1) { next = values[(i + 1) * dim + d]; tn = times[i + 1]; }
      else if (loop && n > 2) { next = values[1 * dim + d]; tn = times[1] + duration; }
      if (prev !== undefined && next !== undefined) {
        const sl = (v - prev) / Math.max(1e-6, times[i] - tp);
        const sr = (next - v) / Math.max(1e-6, tn - times[i]);
        if (sl * sr > 0) {
          m = (next - prev) / Math.max(1e-6, tn - tp);
          // monotone limiter (Fritsch-Carlson): never overshoot inside a segment
          const lim = 3 * Math.min(Math.abs(sl), Math.abs(sr));
          if (Math.abs(m) > lim) m = Math.sign(m) * lim;
        }
      }
      tangents[i * dim + d] = m;
    }
  }
}
