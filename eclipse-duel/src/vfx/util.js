// Shared helpers for every VFX sub-module: value coercion (positions, colours, ranges, curves, ramps), the local
// emission frame, `at` normalisation and scratch objects. Pure functions; nothing here touches the scene.

import * as THREE from 'three';
import { Ease, ease as resolveEase, TAU } from '../core/math.js';

export const V_UP = Object.freeze(new THREE.Vector3(0, 1, 0));
export const V_X = Object.freeze(new THREE.Vector3(1, 0, 0));
export const V_Z = Object.freeze(new THREE.Vector3(0, 0, 1));

/** Render-order bands of the VFX layers (transparent pass). Mesh effects slot themselves in between. */
export const RENDER_ORDER = {
  alphaParticles: 10, // premultiplied smoke / dust / debris particles
  meshAlpha: 12,      // alpha-blended mesh effects (decals ...)
  meshAdd: 16,        // additive mesh effects (slash arcs, rings, pillars, beams)
  addParticles: 20,   // additive particles (sparks, embers, glows)
  ribbons: 22,        // weapon trails and ribbons
  flares: 30,         // camera-facing flares (drawn last, on top of everything they light)
};

/**
 * Coerce a position-like value into `out`.
 * Accepts THREE.Vector3, [x, y, z], {x, y, z}, an Object3D (its world position) or a function returning any of these.
 * @returns {THREE.Vector3} out
 */
export function toVec3(v, out = new THREE.Vector3(), fallback = null) {
  if (v == null) return fallback ? out.copy(fallback) : out.set(0, 0, 0);
  if (v.isVector3) return out.copy(v);
  if (Array.isArray(v) || ArrayBuffer.isView(v)) return out.set(+v[0] || 0, +v[1] || 0, +v[2] || 0);
  if (v.isObject3D) return v.getWorldPosition(out);
  if (typeof v === 'function') return toVec3(v(), out, fallback);
  return out.set(+v.x || 0, +v.y || 0, +v.z || 0);
}

/**
 * Coerce a colour into `out` (linear RGB, components may exceed 1 for HDR).
 * THREE.Color is copied; [r, g, b] is raw linear HDR; a hex number / CSS string is sRGB and converted to linear
 * (three's colour management). `fallback` is used for null.
 */
export function toColor(c, out = new THREE.Color(), fallback = null) {
  if (c == null) return fallback != null ? toColor(fallback, out) : out.setRGB(1, 1, 1);
  if (c.isColor) return out.copy(c);
  if (Array.isArray(c) || ArrayBuffer.isView(c)) return out.setRGB(+c[0] || 0, +c[1] || 0, +c[2] || 0, THREE.LinearSRGBColorSpace);
  return out.set(c);
}

/**
 * Sample a range with an rng: a number, [min, max] (uniform) or [min, max, pow] (value = min + (max-min) * u^pow:
 * pow > 1 skews toward min — "many small, few large").
 */
export function sampleRange(rng, r, fallback = 0) {
  if (r == null) return fallback;
  if (typeof r === 'number') return r;
  const u = rng();
  return r[0] + (r[1] - r[0]) * (r.length > 2 ? Math.pow(u, r[2]) : u);
}

/** Largest value a range can produce (for lifetime bookkeeping). */
export function rangeMax(r, fallback = 0) {
  if (r == null) return fallback;
  if (typeof r === 'number') return r;
  return Math.max(r[0], r[1]);
}

/** Named scalar curves over normalised life t in [0, 1] (multipliers, usually 0..1). */
export const CURVES = {
  one: () => 1,
  grow: (t) => 0.35 + 0.65 * Ease.outQuad(t),
  puff: (t) => 0.3 + 0.7 * Ease.outExpo(Math.min(1, t * 1.4)),           // fast expansion that settles (smoke)
  swell: (t) => 0.55 + 0.45 * Ease.outCubic(t),
  shrink: (t) => 1 - t,
  shrinkSlow: (t) => 1 - t * t,
  shrinkFast: (t) => (1 - t) * (1 - t),
  pop: (t) => (t < 0.08 ? Ease.outQuad(t / 0.08) : 1 - Ease.inQuad((t - 0.08) / 0.92)),   // snap in, ease out
  flash: (t) => (t < 0.15 ? 1 : Math.max(0, 1 - Ease.outQuad((t - 0.15) / 0.85))),
  converge: (t) => 1 - Ease.inCubic(t),
  fadeIn: (t) => Ease.outQuad(Math.min(1, t * 4)),
  fadeOut: (t) => 1 - t,
  fadeInOut: (t) => Math.min(1, t * 6) * (1 - Ease.inQuad(t)),
  pulse: (t) => 0.75 + 0.25 * Math.sin(t * TAU * 3),
  linear: (t) => t,
  erode: (t) => Ease.inQuad(t),             // erosion threshold: holds, then eats the shape
  erodeLate: (t) => (t < 0.45 ? 0 : Ease.inOutQuad((t - 0.45) / 0.55)),
  erodeEarly: (t) => Ease.outQuad(t),
};

/**
 * Normalise a scalar curve to a function f(t): number (constant), name (see CURVES / Ease), function,
 * [[t, v], ...] keyframes (piecewise linear, optional 3rd element = ease name for the segment ending there),
 * or [v0, v1, ...] evenly spaced values.
 */
export function toCurveFn(c, fallback = 1) {
  if (c == null) return () => fallback;
  if (typeof c === 'number') return () => c;
  if (typeof c === 'function') return c;
  if (typeof c === 'string') {
    if (CURVES[c]) return CURVES[c];
    if (Ease[c]) return Ease[c];
    throw new Error('vfx: unknown curve "' + c + '"');
  }
  if (Array.isArray(c) && c.length && Array.isArray(c[0])) {
    const pts = c.slice().sort((a, b) => a[0] - b[0]);
    return (t) => {
      if (t <= pts[0][0]) return pts[0][1];
      const n = pts.length;
      if (t >= pts[n - 1][0]) return pts[n - 1][1];
      let i = 1;
      while (i < n && pts[i][0] < t) i++;
      const a = pts[i - 1], b = pts[i];
      let k = (t - a[0]) / (b[0] - a[0] || 1);
      if (b[2]) k = resolveEase(b[2])(k);
      return a[1] + (b[1] - a[1]) * k;
    };
  }
  if (Array.isArray(c)) {
    const n = c.length;
    if (n === 1) return () => c[0];
    return (t) => {
      const x = Math.min(Math.max(t, 0), 1) * (n - 1);
      const i = Math.min(n - 2, Math.floor(x));
      return c[i] + (c[i + 1] - c[i]) * (x - i);
    };
  }
  return () => fallback;
}

const _rc = new THREE.Color();
/**
 * Normalise a colour ramp to a function f(t, out4) writing [r, g, b, a] (linear HDR rgb).
 * Accepts: [[t, r, g, b, a?], ...] | [[t, colourLike, a?], ...] | a single colour (constant, alpha 1)
 * | a function (t, out4) => void. Optional `alphaCurve` multiplies alpha.
 */
export function toRampFn(ramp, alphaCurve = null) {
  let fn;
  if (typeof ramp === 'function') fn = ramp;
  else if (Array.isArray(ramp) && ramp.length && Array.isArray(ramp[0])) {
    const keys = ramp.map((k) => {
      if (typeof k[1] === 'number' && k.length >= 4) return [k[0], k[1], k[2], k[3], k.length > 4 ? k[4] : 1];
      toColor(k[1], _rc);
      return [k[0], _rc.r, _rc.g, _rc.b, k.length > 2 ? k[2] : 1];
    }).sort((a, b) => a[0] - b[0]);
    fn = (t, o) => {
      const n = keys.length;
      if (t <= keys[0][0] || n === 1) { const k = keys[0]; o[0] = k[1]; o[1] = k[2]; o[2] = k[3]; o[3] = k[4]; return; }
      if (t >= keys[n - 1][0]) { const k = keys[n - 1]; o[0] = k[1]; o[1] = k[2]; o[2] = k[3]; o[3] = k[4]; return; }
      let i = 1;
      while (i < n && keys[i][0] < t) i++;
      const a = keys[i - 1], b = keys[i];
      const x = (t - a[0]) / (b[0] - a[0] || 1);
      for (let j = 0; j < 4; j++) o[j] = a[j + 1] + (b[j + 1] - a[j + 1]) * x;
    };
  } else {
    toColor(ramp == null ? [1, 1, 1] : ramp, _rc);
    const r = _rc.r, g = _rc.g, b = _rc.b;
    fn = (t, o) => { o[0] = r; o[1] = g; o[2] = b; o[3] = 1; };
  }
  if (!alphaCurve) return fn;
  const ac = toCurveFn(alphaCurve, 1);
  return (t, o) => { fn(t, o); o[3] *= ac(t); };
}

/**
 * Orthonormal emission frame from an axis: Y = dir, X = `side` (or world X, or world Z when dir is parallel to X)
 * made orthogonal, Z = X × Y. `facing` = -1 mirrors X (fighter-local mirroring; Z keeps pointing at the camera side).
 */
export function makeFrame(dir, side, facing, X, Y, Z) {
  Y.copy(dir);
  if (Y.lengthSq() < 1e-10) Y.set(0, 1, 0);
  Y.normalize();
  if (side && side.lengthSq() > 1e-10) X.copy(side); else X.set(1, 0, 0);
  X.addScaledVector(Y, -X.dot(Y));
  if (X.lengthSq() < 1e-6) { X.set(0, 0, 1).addScaledVector(Y, -Y.z); if (X.lengthSq() < 1e-6) X.set(1, 0, 0).addScaledVector(Y, -Y.x); }
  X.normalize();
  Z.crossVectors(X, Y);
  if (facing < 0) X.negate();
}

/**
 * Normalised spawn context used by every spawn function. `src` is the user's `at` (or a plain position).
 * Fields: pos, dir, side, facing, scale, color (THREE.Color|null), alpha, count, vel, to, target, realtime, delay.
 * Writes into `out` (reused scratch object) - copy what you keep.
 */
export function normalizeAt(src, out) {
  out.pos.set(0, 0, 0);
  out.dir.set(0, 1, 0);
  out.hasDir = false;
  out.side.set(0, 0, 0);
  out.facing = 1;
  out.scale = 1;
  out.color = null;
  out.alpha = 1;
  out.count = null;
  out.vel.set(0, 0, 0);
  out.hasTo = false;
  out.target = null;
  out.realtime = false;
  out.delay = 0;
  out.intensity = 1;
  if (src == null) return out;
  if (src.isVector3 || Array.isArray(src)) { toVec3(src, out.pos); return out; }
  if (src.pos != null) toVec3(src.pos, out.pos);
  if (src.dir != null) { toVec3(src.dir, out.dir); out.hasDir = out.dir.lengthSq() > 1e-12; if (!out.hasDir) out.dir.set(0, 1, 0); }
  if (src.side != null) toVec3(src.side, out.side);
  if (src.facing != null) out.facing = src.facing < 0 ? -1 : 1;
  if (src.scale != null) out.scale = src.scale;
  if (src.color != null) out.color = toColor(src.color, out._color);
  if (src.alpha != null) out.alpha = src.alpha;
  if (src.intensity != null) out.intensity = src.intensity;
  if (src.count != null) out.count = src.count;
  if (src.vel != null) toVec3(src.vel, out.vel);
  if (src.to != null) { toVec3(src.to, out.to); out.hasTo = true; }
  if (src.target != null) out.target = src.target;
  if (src.realtime) out.realtime = true;
  if (src.delay != null) out.delay = src.delay;
  return out;
}

/** Fresh scratch object for normalizeAt. */
export function makeAt() {
  return {
    pos: new THREE.Vector3(), dir: new THREE.Vector3(0, 1, 0), side: new THREE.Vector3(), to: new THREE.Vector3(), vel: new THREE.Vector3(),
    _color: new THREE.Color(), hasDir: false, hasTo: false, facing: 1, scale: 1, color: null, alpha: 1, count: null, target: null,
    realtime: false, delay: 0, intensity: 1,
  };
}

/**
 * Position in a fighter-local frame: origin + f * facing along X, u along Y, s along Z (toward the camera).
 * Handy inside presets: local(at, 1.2, 1.35, 0) -> a point 1.2 m in front of the fighter at chest height.
 */
export function local(at, f = 0, u = 0, s = 0, out = new THREE.Vector3()) {
  const p = at && at.pos ? at.pos : at;
  toVec3(p, out);
  const facing = at && at.facing != null ? (at.facing < 0 ? -1 : 1) : 1;
  out.x += f * facing; out.y += u; out.z += s;
  return out;
}

/** Stable structural key of a definition object (used to dedupe inline definitions). */
export function defKey(def) {
  return JSON.stringify(def, (k, v) => (typeof v === 'function' ? 'fn:' + v.toString().length + ':' + v.name : v && v.isColor ? [v.r, v.g, v.b] : v && v.isVector3 ? [v.x, v.y, v.z] : v));
}

/** Clamp to [0, 1]. */
export const sat = (x) => (x < 0 ? 0 : x > 1 ? 1 : x);
