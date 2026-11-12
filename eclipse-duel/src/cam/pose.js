// Camera pose, critically damped springs, point sources and orientation helpers shared by the camera director.
// Everything here is allocation-free per call (module-level scratch objects).

import * as THREE from 'three';
import { smoothstep } from '../core/math.js';

const Z_AXIS = new THREE.Vector3(0, 0, 1);

/** A camera pose before shake / kicks: eye position, look-at point, vertical fov (deg) and roll (rad, about the view axis). */
export class Pose {
  constructor() {
    this.pos = new THREE.Vector3(0, 2.2, 8);
    this.look = new THREE.Vector3(0, 1.2, 0);
    this.fov = 40;
    this.roll = 0;
  }
  copy(p) { this.pos.copy(p.pos); this.look.copy(p.look); this.fov = p.fov; this.roll = p.roll; return this; }
}

/**
 * Critically damped spring toward `target` (SmoothDamp, Game Programming Gems 4 ch. 1.10). `s` = {v, vel}.
 * `smoothTime` ~ the time to cover most of the gap; exact for any dt, never overshoots.
 */
export function damp1(s, target, smoothTime, dt) {
  if (!(dt > 0)) return s.v;
  const omega = 2 / Math.max(1e-4, smoothTime);
  const x = omega * dt;
  const exp = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x);
  const change = s.v - target;
  const temp = (s.vel + omega * change) * dt;
  s.vel = (s.vel - omega * temp) * exp;
  let out = target + (change + temp) * exp;
  if ((target - s.v > 0) === (out > target) && target !== s.v) { out = target; s.vel = 0; }
  s.v = out;
  return out;
}

/** Three independent critically damped springs (a smoothed point). */
export class Damp3 {
  constructor() {
    this.x = { v: 0, vel: 0 }; this.y = { v: 0, vel: 0 }; this.z = { v: 0, vel: 0 };
    this.value = new THREE.Vector3();
  }
  reset(p) {
    this.x.v = p.x; this.y.v = p.y; this.z.v = p.z;
    this.x.vel = this.y.vel = this.z.vel = 0;
    this.value.copy(p);
    return this.value;
  }
  step(target, smoothTime, dt) {
    this.value.set(damp1(this.x, target.x, smoothTime, dt), damp1(this.y, target.y, smoothTime, dt), damp1(this.z, target.z, smoothTime, dt));
    return this.value;
  }
}

/**
 * Read a "point source" into `out`: Object3D (world position), function (called with `out`; may fill it or return a
 * Vector3 / [x,y,z]), Vector3, [x, y, z] or {x, y, z}. Returns false when the source is empty.
 */
export function readPoint(src, out) {
  if (src == null) return false;
  if (typeof src === 'function') {
    const r = src(out);
    if (r && r !== out) {
      if (r.isVector3) out.copy(r);
      else if (Array.isArray(r)) out.set(r[0], r[1], r[2]);
    }
    return true;
  }
  if (src.isObject3D) { src.getWorldPosition(out); return true; }
  if (src.isVector3) { out.copy(src); return true; }
  if (Array.isArray(src)) { out.set(src[0], src[1], src[2]); return true; }
  if (typeof src.x === 'number') { out.set(src.x, src.y || 0, src.z || 0); return true; }
  return false;
}

const _m4 = new THREE.Matrix4();
const _fw = new THREE.Vector3();
const _up = new THREE.Vector3();
const _tgt = new THREE.Vector3();
const _qr = new THREE.Quaternion();

/**
 * Orientation looking from `pos` to `look`, then rolled by `roll` radians about the view axis (positive roll dips the
 * right end of the horizon). Near-vertical views (top-down / straight up) keep a stable screen-up: toward -Z when
 * looking down, toward +Z when looking up, blended smoothly so a crane from side-on to top-down never flips.
 */
export function orient(pos, look, roll, out) {
  _fw.subVectors(look, pos);
  const len = _fw.length();
  if (len < 1e-6) _fw.set(0, 0, -1); else _fw.multiplyScalar(1 / len);
  const k = smoothstep(0.8, 0.999, Math.abs(_fw.y));
  _up.set(0, 1 - k, _fw.y > 0 ? k : -k).normalize();
  _tgt.copy(pos).add(_fw);
  _m4.lookAt(pos, _tgt, _up);
  out.setFromRotationMatrix(_m4);
  if (roll !== 0) out.multiply(_qr.setFromAxisAngle(Z_AXIS, roll));
  return out;
}

/**
 * Soft lower bound: identity above `min + knee`, approaches `min` exponentially below it (C1-continuous), so a camera
 * path that dips under a limit is eased along the limit instead of creasing against it.
 */
export function softFloor(v, min, knee) {
  const k = Math.max(1e-3, knee);
  if (v >= min + k) return v;
  return min + k * Math.exp((v - min) / k - 1);
}
