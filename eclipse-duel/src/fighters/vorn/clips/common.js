// VORN clip authoring helpers: the stance, spear-hand targets, foot keys and a key builder.
// Fighter frame (f forward, u up, s toward the camera = his right side), metres, VORN's own proportions
// (hips pivot 1.114 m, hip joints 1.05, shoulders 1.62 at s +-0.232, arm shoulder -> fist 0.705, leg 0.96).
// Spear (src/char/weapons.js): the right fist holds the weapon origin (head root 1.02 ahead, tip 1.5, butt 0.86 behind);
// the left hand IKs to `grip` (-0.52, rear) or `choke` (-0.26).

import { definePose } from '../../../char/index.js';

/** Normalised copy of a 3-vector. */
export function nrm(v) {
  const l = Math.hypot(v[0], v[1], v[2]) || 1;
  return [v[0] / l, v[1] / l, v[2] / l];
}

/** `up` orthogonal to `aim` (spear head flats toward the camera when up ~ world up). */
function upFor(aim, up) {
  const a = nrm(aim), u = up || (Math.abs(a[1]) > 0.85 ? [-1, 0, 0] : [0, 1, 0]);
  const d = u[0] * a[0] + u[1] * a[1] + u[2] * a[2];
  return nrm([u[0] - a[0] * d, u[1] - a[1] * d, u[2] - a[2] * d]);
}

/**
 * Grip tilt (deg) of the spear in the right fist, toward the little finger. The design sets no `gripAngle` (the haft
 * would sit square across the fist, so a thrust along the forearm would need a 90 deg wrist). Every VORN clip keys
 * `weaponR: [0, 0, -GRIP_TILT]` (in STANCE, the base of every clip) and `sp()` hands the IK the fist frame of that
 * tilted grip, so `aim` / `up` still say where the spear points. If design.gripAngle is ever set, set this to 0.
 */
export const GRIP_TILT = 42;
const GC = Math.cos(GRIP_TILT * Math.PI / 180), GS = Math.sin(GRIP_TILT * Math.PI / 180);

/** Spear-hand IK target: fist centre `pos`, spear pointing along `aim` (head flats facing `up` x aim). */
export function sp(pos, aim, o = {}) {
  const a = nrm(aim), u = upFor(a, o.up);
  // fist frame = spear frame rotated +GRIP_TILT about its Z (the keyed weaponR tilt takes it back)
  const fa = [GC * a[0] + GS * u[0], GC * a[1] + GS * u[1], GC * a[2] + GS * u[2]];
  const fu = [-GS * a[0] + GC * u[0], -GS * a[1] + GC * u[1], -GS * a[2] + GC * u[2]];
  return { pos, aim: fa, up: fu, ...(o.space ? { space: o.space } : {}), ...(o.soft !== undefined ? { soft: o.soft } : {}), ...(o.ease ? { ease: o.ease } : {}) };
}

/** Point along the spear from the right fist (d metres along aim): tip = 1.5, head root = 1.02, butt = -0.86. */
export function along(pos, aim, d) {
  const a = nrm(aim);
  return [pos[0] + a[0] * d, pos[1] + a[1] * d, pos[2] + a[2] * d];
}

/** Foot target: sole point under the ankle, toe yaw (deg, + = toes toward -s), pitch (deg, + = toes up). */
export function ft(pos, yaw, o = {}) {
  return { pos, rot: [0, yaw, o.pitch || 0], space: o.space || 'origin', ...(o.ease ? { ease: o.ease } : {}), ...(o.pole ? { pole: o.pole } : {}) };
}

// ---- the stance -------------------------------------------------------------------------------------------------------
/** Left arm FK at rest (the grip IK holds it; keys that free the left hand return to this). */
export const LARM0 = { upperArmL: [0, 0, 0], foreArmL: [0, 0, 0], handL: [0, 0, 0] };
/** Stance feet (root space): left foot forward, rear foot turned out. */
export const FL = [0.35, 0, -0.15], FR = [-0.36, 0, 0.2];
export const YL = 12, YR = -48;
/** Low spear guard: right fist at the front of the right hip, spear forward-down (tip at knee height ~1.6 m out),
 * haft rising behind along the right side, left hand on the rear grip. */
export const STANCE_AIM = [0.86, -0.42, -0.27];
export const STANCE_HAND = sp([0.3, 1.02, 0.22], STANCE_AIM);
export const STANCE = {
  hips: { pos: [-0.03, -0.1, 0], rot: [0, -30, 0] },
  bones: { spine: [0, -8, -3], chest: [1, -8, -1], neck: [0, 12, 2], head: [0, 16, -4], weaponR: [0, 0, -GRIP_TILT], ...LARM0 },
  ik: { handR: STANCE_HAND, footL: { pos: FL, rot: [0, YL, 0] }, footR: { pos: FR, rot: [0, YR, 0] } },
  grip: 1, curl: [1, 1],
};
definePose('vorn.stance', STANCE);

/** Stance feet in origin space after the root travelled `d` metres. */
export function stanceFeet(d, o = {}) {
  return { footL: ft([FL[0] + d, 0, FL[2]], YL, o), footR: ft([FR[0] + d, 0, FR[2]], YR, o) };
}

/**
 * Key list builder. `k(t, channels)` pushes a key; several keys may share a `t` (each channel interpolates only
 * between the keys that define it), so each group of channels carries its own ease.
 */
export function keyset() {
  const keys = [];
  const k = (t, ch) => { keys.push({ t, ...ch }); return k; };
  k.keys = () => keys.sort((a, b) => a.t - b.t);
  /** A foot step (origin space): planted at `a` until t0, lifted arc, lands at `b` at t1 (fast landing). */
  k.step = (foot, t0, t1, a, b, yaw0, yaw1, lift = 0.08) => {
    const L = (x, y, s) => [a[0] + (b[0] - a[0]) * s, x, a[2] + (b[2] - a[2]) * s + y];
    const d = t1 - t0;
    k(t0, { ik: { [foot]: ft(a, yaw0) } });
    k(t0 + d * 0.3, { ik: { [foot]: ft(L(lift * 0.85, 0, 0.25), yaw0 + (yaw1 - yaw0) * 0.3, { pitch: -16, ease: 'outQuad' }) } });
    k(t0 + d * 0.65, { ik: { [foot]: ft(L(lift, 0, 0.7), yaw0 + (yaw1 - yaw0) * 0.7, { pitch: 4 }) } });
    k(t1, { ik: { [foot]: ft(b, yaw1, { ease: 'inQuad' }) } });
    return k;
  };
  return k;
}

/** Root-motion keys from the rules motion: `[[t, d], ...]` cumulative metres (linear between). */
export function rootKeys(k, pts) {
  for (const [t, d] of pts) k(t, { root: { pos: [d, 0], interp: 'linear' } });
}
