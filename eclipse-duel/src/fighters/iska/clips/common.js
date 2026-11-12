// ISKA clip toolkit: her stance, link poses and small helpers shared by every clip file.
// Fighter frame (src/char README section 3): f forward (+X), u up, s toward the camera = her right side.
// Her proportions (design.js): hips pivot 1.005, hip joints 0.95 (s +-0.088), shoulders 1.45 (s +-0.19), knees 0.50,
// shoulder -> fist ~0.6 m. Twin crescents: one blade per fist, never a grip (grip: 0 everywhere), both fists curled.
// Hand IK: pos = fist centre, aim = where the blade leaves the fist (thumb side), up = the blade's back (the crescent
// curves toward up); the true edge is -up, so a cut moves along -up.

import { definePose } from '../../../char/index.js';

/** Foot target: sole point under the ankle, toe yaw (deg, + = toes turned left / toward -s), pitch (- = on the ball). */
export const foot = (pos, yaw = 0, pitch = 0, extra) => ({ pos, rot: [0, yaw, pitch], ...extra });
/**
 * Planted foot that rolls onto its ball (heel up) without the ball sliding: `pos` / `yaw` are the stance target at
 * pitch `p0`; the sole point under the ankle moves so the ball stays where it was at `p0`.
 */
export const ball = (pos, yaw, pitch, p0 = -14, extra) => {
  const L = 0.125, r = Math.PI / 180, a0 = p0 * r, a1 = pitch * r, y = yaw * r;
  const df = L * (Math.cos(a0) - Math.cos(a1)), du = L * (Math.sin(a0) - Math.sin(a1));
  return { pos: [pos[0] + df * Math.cos(y), pos[1] + du, pos[2] - df * Math.sin(y)], rot: [0, yaw, pitch], ...extra };
};
/**
 * Horizontal sweep target for the RIGHT hand (mir() it for the left): the arm points at angle `phi` (deg, from +f
 * toward +s) at height `u`, the blade lies across it pointing `phi - 90` (forearm and blade at a right angle, wrist
 * neutral) with the true edge leading the sweep toward -s.
 */
export const sweep = (phi, u = 1.1, r = 0.5, c = [0.05, 0.1]) => {
  const a = phi * Math.PI / 180, b = (phi - 90) * Math.PI / 180;
  return { pos: [c[0] + r * Math.cos(a), u, c[1] + r * Math.sin(a)], aim: [Math.cos(b), 0.05, Math.sin(b)], up: [Math.cos(a), 0, Math.sin(a)] };
};
/** Hand target: fist centre, blade direction, blade back. */
export const hand = (pos, aim, up, extra) => ({ pos, aim, up, ...extra });
/** Mirror a hand / foot target across the fight line (s -> -s): the left-hand version of a right-hand key. */
export const mir = (h) => {
  const o = { ...h };
  for (const k of ['pos', 'aim', 'up', 'pole']) if (h[k]) o[k] = [h[k][0], h[k][1], -h[k][2]];
  return o;
};

// ---- stance ---------------------------------------------------------------------------------------------------------
// Left foot leads (far side), right foot back (camera side), both on the balls of the feet; hips opened toward the
// camera; blades crossed low in front of the hips, points down and forward.
export const FL = [0.24, 0.02, -0.12];
export const FR = [-0.25, 0.02, 0.14];
export const YAW_L = 14, YAW_R = -38, PITCH = -14;
export const FEET = { footL: foot(FL, YAW_L, PITCH), footR: foot(FR, YAW_R, PITCH) };
export const HR = hand([0.22, 0.93, 0.12], [0.5, -0.66, -0.56], [0.86, 0.5, 0.1]);
export const HL = hand([0.27, 0.96, -0.06], [0.52, -0.62, 0.58], [0.84, 0.54, -0.1]);
export const STANCE = {
  hips: { pos: [-0.03, -0.08, 0], rot: [0, -24, 0] },
  bones: { spine: [2, -4, -3], chest: [0, -6, -2], neck: [0, 8, 2], head: [0, 12, -4] },
  ik: { handR: HR, handL: HL, ...FEET },
  grip: 0, curl: [1, 1],
};
definePose('iska.stance', STANCE);

// crossed forearms before the face, fists on the opposite sides, both blades standing up (an X with the forearms),
// elbows out; true edges toward the opponent
export const XR = hand([0.34, 1.3, -0.07], [0.12, 0.95, -0.28], [-0.99, 0.12, 0.0], { pole: [0.2, 1.15, 0.65] });
export const XL = hand([0.36, 1.27, 0.08], [0.12, 0.95, 0.28], [-0.99, 0.12, 0.0], { pole: [0.2, 1.15, -0.65] });
// crossed guard: both blades raised in an X before the face, elbows out, weight back
definePose('iska.block', {
  hips: { pos: [-0.06, -0.13, 0], rot: [0, -22, 0] },
  bones: { spine: [0, -6, -6], chest: [0, -8, -5], neck: [0, 8, 6], head: [0, 12, 4] },
  ik: {
    handR: XR, handL: XL,
    footL: foot([0.27, 0.01, -0.12], 14, -8), footR: foot([-0.3, 0.01, 0.15], -42, -8),
  },
  grip: 0, curl: [1, 1],
});

/** Events helper: [[t, name, data?], ...] -> [{ t, name, data }]. */
export const ev = (list) => list.map(([t, name, data]) => (data ? { t, name, data } : { t, name }));
