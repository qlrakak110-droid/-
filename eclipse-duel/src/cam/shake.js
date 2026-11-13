// Trauma shake, impulse kicks and handheld drift. Real time only (keeps moving through hit-stop and slow-motion).
//
// Shake: each instance holds a trauma value that decays linearly; its visible amplitude is trauma^2, so a hit fades
// fast at the tail. Motion is smooth 1D gradient noise (two octaves) per channel: camera-space position x/y/z and
// yaw/pitch/roll. Instances overlap; the sum is soft-clipped. A direction concentrates the motion along one axis.
// Kick: a one-off impulse on fov / dolly / roll / position with a snappy attack and a damped-spring release (slight
// overshoot), ending exactly at zero.

import * as THREE from 'three';
import { makeRng, clamp, DEG } from '../core/math.js';

/** Integer hash -> [-1, 1]. */
function hash1(i, seed) {
  let h = Math.imul((i | 0) ^ Math.imul(seed | 0, 0x9e3779b1), 0x27d4eb2d);
  h ^= h >>> 15;
  h = Math.imul(h, 0x85ebca6b);
  h ^= h >>> 13;
  h = Math.imul(h, 0xc2b2ae35);
  h ^= h >>> 16;
  return ((h >>> 0) / 4294967295) * 2 - 1;
}

/** Smooth 1D gradient noise, roughly in [-1, 1]. Deterministic for a given seed. */
export function noise1(x, seed) {
  const i = Math.floor(x), f = x - i;
  const g0 = hash1(i, seed), g1 = hash1(i + 1, seed);
  const u = f * f * f * (f * (f * 6 - 15) + 10);
  const a = g0 * f, b = g1 * (f - 1);
  return (a + (b - a) * u) * 2.2;
}

/** Two-octave noise, roughly in [-1, 1]. */
export function fbm1(x, seed) {
  return (noise1(x, seed) + 0.5 * noise1(x * 2.13 + 17.31, seed + 7919)) * 0.6667;
}

const softClip = (x, lim) => lim * Math.tanh(x / lim);

/** Default amplitudes at trauma 1 (positions in metres, angles in degrees). */
export const SHAKE_DEFAULTS = { pos: 0.1, yaw: 3.0, pitch: 2.6, roll: 3.2, scale: 1, maxTrauma: 1.5 };

export function createShaker(seed = 0xca3e) {
  const rng = makeRng(seed);
  const settings = { ...SHAKE_DEFAULTS };
  const MAX_SHAKES = 12, MAX_KICKS = 10;
  const shakes = [];
  for (let i = 0; i < MAX_SHAKES; i++) shakes.push({ on: false, gen: 0, trauma: 0, decay: 1, freq: 15, phase: 0, seed: 0, dir: new THREE.Vector3(), hasDir: false, rot: 1, pos: 1 });
  const kicks = [];
  for (let i = 0; i < MAX_KICKS; i++) kicks.push({ on: false, gen: 0, t: 0, dur: 0.3, attack: 0.05, fov: 0, push: 0, roll: 0, offset: new THREE.Vector3(), zeta: 0.8, omega: 10 });

  /** Output of the last sample() (camera space; angles in radians). */
  const out = { px: 0, py: 0, pz: 0, yaw: 0, pitch: 0, roll: 0, fov: 0, push: 0, kroll: 0, offset: new THREE.Vector3(), trauma: 0 };

  function freeSlot(arr, weakest) {
    for (const s of arr) if (!s.on) return s;
    let best = arr[0];
    for (const s of arr) if (weakest(s) < weakest(best)) best = s;
    return best;
  }

  /**
   * Add trauma. amount ~0.1 (tap) .. 1 (ultimate impact). opts: duration (s; sets decay = amount / duration),
   * decay (trauma per second, default 1.6), freq (Hz, default 15), dir (world Vector3 / [x,y,z]: shake mostly along
   * it), rot / pos (0..1 channel weights). Returns {stop()}.
   */
  function shake(amount, { duration, freq = 15, decay = 1.6, dir = null, rot = 1, pos = 1 } = {}) {
    const s = freeSlot(shakes, (x) => x.trauma);
    s.on = amount > 0;
    s.gen++;
    s.trauma = Math.min(settings.maxTrauma, Math.max(0, amount));
    s.decay = duration > 0 ? s.trauma / duration : Math.max(1e-3, decay);
    s.freq = Math.max(0.1, freq);
    s.phase = rng() * 64;
    s.seed = (rng() * 1e6) | 0;
    s.rot = rot; s.pos = pos;
    s.hasDir = false;
    if (dir) {
      if (Array.isArray(dir)) s.dir.set(dir[0], dir[1], dir[2]); else s.dir.copy(dir);
      if (s.dir.lengthSq() > 1e-8) { s.dir.normalize(); s.hasDir = true; }
    }
    const gen = s.gen;
    return { stop() { if (s.gen === gen) s.on = false; } };
  }

  /**
   * Impulse. fov (deg, negative = punch in), push (m along the view, positive = toward the subject), roll (deg),
   * offset (world [x,y,z] m), duration (s, default 0.32), attack (s, default 0.045), bounce (0..1 overshoot, default 0.3).
   */
  function kick({ fov = 0, push = 0, roll = 0, offset = null, duration = 0.32, attack = 0.045, bounce = 0.3 } = {}) {
    const k = freeSlot(kicks, (x) => x.dur - x.t);
    k.on = true;
    k.gen++;
    k.t = 0;
    k.dur = Math.max(0.02, duration);
    k.attack = clamp(attack, 0.001, k.dur * 0.6);
    k.fov = fov; k.push = push; k.roll = roll * DEG;
    if (offset) { if (Array.isArray(offset)) k.offset.set(offset[0], offset[1], offset[2]); else k.offset.copy(offset); } else k.offset.set(0, 0, 0);
    k.zeta = clamp(1 - 0.65 * bounce, 0.3, 1);
    k.omega = 3.9 / ((k.dur - k.attack) * k.zeta);
    const gen = k.gen;
    return { stop() { if (k.gen === gen) k.on = false; } };
  }

  function kickEnvelope(k) {
    const t = k.t;
    if (t < k.attack) { const u = t / k.attack; return 1 - (1 - u) * (1 - u) * (1 - u); }
    const tr = t - k.attack, R = k.dur - k.attack;
    const z = k.zeta, w = k.omega;
    let x;
    if (z >= 0.999) x = (1 + w * tr) * Math.exp(-w * tr);
    else {
      const wd = w * Math.sqrt(1 - z * z);
      x = Math.exp(-z * w * tr) * (Math.cos(wd * tr) + ((z * w) / wd) * Math.sin(wd * tr));
    }
    const u = tr / R;
    const fade = u < 0.7 ? 1 : 1 - (u - 0.7) / 0.3;
    return x * fade * fade * (3 - 2 * fade);
  }

  /**
   * Advance by dt (real seconds) and fill `out`. right / up / fwd: the camera basis (world) used to project shake
   * directions into camera space.
   */
  function sample(dt, right, up, fwd) {
    let px = 0, py = 0, pz = 0, yaw = 0, pitch = 0, roll = 0, total = 0;
    const S = settings;
    for (const s of shakes) {
      if (!s.on) continue;
      s.phase += dt * s.freq;
      s.trauma -= s.decay * dt;
      if (s.trauma <= 0) { s.on = false; continue; }
      const k = s.trauma * s.trauma * S.scale;
      total += k;
      const ph = s.phase, sd = s.seed;
      const n0 = fbm1(ph, sd), n1 = fbm1(ph + 31.7, sd + 1), n2 = fbm1(ph + 63.1, sd + 2);
      const n3 = fbm1(ph * 0.93 + 11.3, sd + 3), n4 = fbm1(ph * 0.91 + 47.9, sd + 4), n5 = fbm1(ph * 0.87 + 83.3, sd + 5);
      const kp = k * S.pos * s.pos, kr = k * s.rot * DEG;
      if (s.hasDir) {
        const dr = s.dir.dot(right), du = s.dir.dot(up), df = s.dir.dot(fwd);
        const leak = 0.22;
        px += kp * (dr * n0 + leak * n1);
        py += kp * (du * n0 + leak * n2);
        pz += kp * (df * n0 + leak * n3) * 0.6;
        yaw += kr * S.yaw * (dr * n0 + leak * n4);
        pitch += kr * S.pitch * (du * n0 + leak * n5);
        roll += kr * S.roll * (0.3 * n3 + 0.7 * Math.abs(dr) * n4);
      } else {
        px += kp * n0; py += kp * n1; pz += kp * n2 * 0.5;
        yaw += kr * S.yaw * n3; pitch += kr * S.pitch * n4; roll += kr * S.roll * n5;
      }
    }
    const lp = S.pos * 1.6, la = 1.6 * DEG;
    out.px = softClip(px, lp); out.py = softClip(py, lp); out.pz = softClip(pz, lp);
    out.yaw = softClip(yaw, S.yaw * la); out.pitch = softClip(pitch, S.pitch * la); out.roll = softClip(roll, S.roll * la);
    out.trauma = Math.sqrt(total);

    let fov = 0, push = 0, kroll = 0;
    out.offset.set(0, 0, 0);
    for (const k of kicks) {
      if (!k.on) continue;
      k.t += dt;
      if (k.t >= k.dur) { k.on = false; continue; }
      const e = kickEnvelope(k);
      fov += k.fov * e; push += k.push * e; kroll += k.roll * e;
      out.offset.addScaledVector(k.offset, e);
    }
    out.fov = fov; out.push = push; out.kroll = kroll;
    return out;
  }

  /** Stop every shake and kick (round reset). */
  function clear() {
    for (const s of shakes) s.on = false;
    for (const k of kicks) k.on = false;
  }

  return { settings, shake, kick, sample, clear, out };
}

/**
 * Handheld drift: slow, low-amplitude rotational noise that makes a locked-off shot feel operated.
 * amount 1 = ~0.6 deg yaw / pitch, 0.45 deg roll. Writes yaw / pitch / roll (rad) into `out`.
 *
 * `cine` (0..1, cinematic shots only) adds the operator's micro-motion on top: a faint faster tremor (~2.3 Hz,
 * 0.12 deg at amount 1), a few centimetres of body sway (out.px / out.py, metres along the camera's right / up: real
 * parallax between foreground and background) and a slow lens respiration (out.fov, relative: +-0.5 % at amount 1).
 * Fight framing passes cine = 0 and gets the plain drift.
 */
export function handheld(time, amount, seed, out, cine = 0) {
  const t = time * 0.55;
  out.yaw = fbm1(t, seed) * 0.6 * DEG * amount;
  out.pitch = fbm1(t * 0.9 + 13.1, seed + 11) * 0.5 * DEG * amount;
  out.roll = fbm1(t * 0.7 + 29.7, seed + 23) * 0.45 * DEG * amount;
  const a = amount * cine;
  if (a > 1e-4) {
    const q = time * 2.3;
    out.yaw += fbm1(q, seed + 41) * 0.12 * DEG * a;
    out.pitch += fbm1(q * 1.13 + 7.7, seed + 53) * 0.1 * DEG * a;
    out.px = fbm1(time * 0.37 + 3.1, seed + 67) * 0.03 * a;
    out.py = fbm1(time * 0.31 + 19.3, seed + 71) * 0.02 * a;
    out.fov = fbm1(time * 0.21 + 5.9, seed + 83) * 0.005 * a;
  } else { out.px = 0; out.py = 0; out.fov = 0; }
  return out;
}
