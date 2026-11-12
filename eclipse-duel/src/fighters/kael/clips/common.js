// KAEL 카엘 — shared clip vocabulary: stance numbers, feet, the shoulder-rest grip and small vector helpers for blade
// arcs. Fighter frame (f, u, s): f toward the opponent, u up, s toward the camera = Kael's right side (src/char README).
// Kael stands in a heavy, wide, bladed stance (left foot forward) with the greatsword resting on the right pauldron.

import { definePose } from '../../../char/index.js';

/** Front (left) and back (right) foot of the stance: sole points + toe yaw (IK rot: not mirrored). */
export const FL = [0.36, 0, -0.16];
export const FR = [-0.36, 0, 0.2];
export const YAW_L = 12;
export const YAW_R = -40;
export const FEET = { footL: { pos: FL, rot: [0, YAW_L, 0] }, footR: { pos: FR, rot: [0, YAW_R, 0] } };

// ---- vectors (allocation is fine here: clips are data, built once at module load) --------------------------------
export const norm = (v) => { const l = Math.hypot(v[0], v[1], v[2]) || 1; return [v[0] / l, v[1] / l, v[2] / l]; };
export const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const r3 = (v) => v.map((x) => Math.round(x * 1000) / 1000);

/**
 * Direction from azimuth / elevation (deg): az 0 = +f (toward the foe), +90 = -s (Kael's left, away from the camera),
 * -90 = +s (his right, camera side), 180 = behind; el + = up.
 */
export function dir(az, el) {
  const a = (az * Math.PI) / 180, e = (el * Math.PI) / 180;
  return r3([Math.cos(e) * Math.cos(a), Math.sin(e), -Math.cos(e) * Math.sin(a)]);
}

/**
 * A swing plane through direction `a` (angle 0) and `b` (the next direction the blade passes, less than 180 deg on):
 * returns blade(deg) = the blade direction `deg` degrees along the swing (any angle: wind-up < 0, follow-through past
 * b), with the true edge leading (`flip`: the other edge leads — the greatsword is double-edged, and for chops that end
 * point-down in front this roll is the one a human wrist can hold).
 */
export function plane(a, b, flip = false) {
  a = norm(a); b = norm(b);
  const n0 = norm(cross(a, b)), m = cross(n0, a), n = flip ? n0.map((x) => -x) : n0;
  return (deg) => {
    const th = (deg * Math.PI) / 180, c = Math.cos(th), s = Math.sin(th);
    const aim = norm([a[0] * c + m[0] * s, a[1] * c + m[1] * s, a[2] * c + m[2] * s]);
    return { aim: r3(aim), up: r3(norm(cross(aim, n))) };
  };
}

/**
 * Hand target with the blade along `aim` and the roll a human wrist holds comfortably: the true edge faces away from
 * the (estimated) right elbow, i.e. it continues the forearm. The greatsword is double-edged, so the roll only has to be
 * feasible; asking the IK for the other roll makes the wrist clamp and the blade deviate. `sh` = right shoulder estimate.
 */
export function grip(pos, aim, sh = [-0.12, 1.4, 0.2]) {
  aim = norm(aim);
  const el = [(sh[0] + pos[0]) / 2, (sh[1] + pos[1]) / 2 - 0.2, (sh[2] + pos[2]) / 2 + 0.08];
  const d = [el[0] - pos[0], el[1] - pos[1], el[2] - pos[2]];
  const k = dot(d, aim);
  let up = [d[0] - aim[0] * k, d[1] - aim[1] * k, d[2] - aim[2] * k];
  if (Math.hypot(up[0], up[1], up[2]) < 1e-4) up = [0, 1, 0];
  return { pos, aim: r3(aim), up: r3(norm(up)) };
}

// ---- the stance -------------------------------------------------------------------------------------------------
/** Right fist on the grip in front of the right shoulder, blade sloping back over the pauldron, true edge forward-up. */
export const SHOULDER_HAND = { pos: [0.16, 1.355, 0.24], aim: [-0.75, 0.66, 0.05], up: [-0.66, -0.75, 0] };

/** The shoulder-rest hand nudged by [df, du, ds] (idle / walk bob). */
export const shoulderHand = (df = 0, du = 0, ds = 0) => ({ pos: SHOULDER_HAND.pos.map((x, i) => +(x + [df, du, ds][i]).toFixed(4)), aim: SHOULDER_HAND.aim });
export const STANCE_BODY = {
  hips: { pos: [-0.03, -0.125, 0], rot: [0, -24, 0] },
  bones: { spine: [0, -5, -3], chest: [1, -6, -2], neck: [0, 14, 2], head: [0, 18, -3] },
};

definePose('kael.stance', { ...STANCE_BODY, ik: { handR: SHOULDER_HAND, ...FEET }, grip: 1, curl: [1, 1] });

/** Merge helper: the stance with overrides (shallow per channel group). */
export function stance(extra = {}) {
  return {
    hips: { ...STANCE_BODY.hips, ...(extra.hips || {}) },
    bones: { ...STANCE_BODY.bones, ...(extra.bones || {}) },
    ik: { handR: SHOULDER_HAND, ...FEET, ...(extra.ik || {}) },
    grip: 1, curl: [1, 1],
  };
}

/** Sorts keys by time (clips are written grouped by channel for readability). */
export const sorted = (keys) => keys.sort((a, b) => a.t - b.t);
