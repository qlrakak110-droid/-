// KAEL — idle, walks, dash / backstep / dodge, guard.
// Walks are a real heavy gait (the feet pass each other) at exactly the rules' walk speeds, so they play at 1x with
// planted feet. Dash / backstep keys follow the rules' ease-out travel (x = d * (1 - (1 - u)^2)) as root motion, with the
// feet keyed in 'origin' space: every planted foot stays fixed in the world while the rules slide the root.

import { defineClip, definePose } from '../../../char/index.js';
import { def } from '../moves.js';
import { FL, FR, YAW_L, YAW_R, SHOULDER_HAND, STANCE_BODY, shoulderHand, stance, sorted } from './common.js';

// ---- idle: shoulder-rest stance, slow heavy breathing, weight rolling between the feet ---------------------------
defineClip('kael.idle', {
  duration: 2.8, loop: true, breath: 1.35,
  keys: [
    { t: 0, ease: 'inOutSine', ...stance() },
    { t: 0.8, ease: 'inOutSine', hips: { pos: [-0.045, -0.137, 0.012], rot: [1.4, -25.5, 0.8] }, bones: { chest: [0.4, -6.5, -3.4], head: [0, 19, -5] },
      ik: { handR: shoulderHand(-0.004, -0.012, 0.002) } },
    { t: 1.5, ease: 'inOutSine', hips: { pos: [-0.024, -0.122, 0.002], rot: [0.2, -23.4, 0.1] }, bones: { chest: [1.2, -5.6, -1.4], head: [0, 17.5, -2] },
      ik: { handR: shoulderHand(0.003, 0.01, -0.001) } },
    { t: 2.15, ease: 'inOutSine', hips: { pos: [-0.016, -0.129, -0.012], rot: [-1.2, -22.5, -0.7] }, bones: { chest: [1.4, -5.4, -2.6], head: [0, 17, -4] },
      ik: { handR: shoulderHand(0.006, 0, -0.002) } },
  ],
});

// ---- walks: alternating heavy gait, stance-width track, planted feet at the rules' speed -------------------------
/**
 * @param {string} name clip name
 * @param {number} dir +1 forward / -1 backward
 * @param {number} v speed (m/s)
 */
function walk(name, dir, v) {
  const S = FL[0] - FR[0];                 // double-support step = the stance's foot spread
  const T = (2 * S) / v;                    // each foot advances 2 S per cycle
  const d = 2 * S * dir;                    // signed root travel per cycle
  const lift = dir > 0 ? 0.13 : 0.1;
  // A swings first (forward: the back foot; backward: the front foot), B second
  const A = dir > 0 ? 'footR' : 'footL', B = dir > 0 ? 'footL' : 'footR';
  const P = { footL: FL, footR: FR };
  const yawOf = { footL: 8, footR: -22 };
  const pos = (foot, f, u = 0) => [+f.toFixed(4), u, P[foot][2]];
  const planted = (foot, f) => ({ pos: pos(foot, f), rot: [0, yawOf[foot], 0] });
  const hy = -0.118, up = 0.026, yaw0 = -22, yawA = dir > 0 ? 7 : -5, sw = 0.022, lean = dir > 0 ? -5 : 2;
  const keys = [{ t: 0, hips: { pos: [-0.03 + 0.015 * dir, hy, 0], rot: [0, yaw0, 0] }, bones: { ...STANCE_BODY.bones, spine: [0, -5, lean] },
    ik: { handR: SHOULDER_HAND, [A]: planted(A, P[A][0]), [B]: planted(B, P[B][0]) }, grip: 1, curl: [1, 1], root: { pos: [0, 0] } }];
  // one swing: lift at ta from local fa (it was planted, moving at -d / T), land at tb on local fb (heel first)
  const swing = (foot, f0, ta, tb, fb) => {
    const fa = f0 - (d / T) * ta, y = yawOf[foot];
    const k = (t, f, u, pitch, interp, ease) => keys.push({ t, interp, ease, ik: { [foot]: { pos: pos(foot, f, u), rot: [0, y, pitch] } } });
    k(ta, fa, 0, dir > 0 ? -8 : 6, 'linear');
    k(ta + (tb - ta) * 0.3, fa + (fb - fa) * 0.22, lift * 0.8, dir > 0 ? -24 : 10, 'auto', 'outQuad');
    k(ta + (tb - ta) * 0.55, fa + (fb - fa) * 0.62, lift, dir > 0 ? 4 : -4, 'auto');
    k(tb, fb, 0, dir > 0 ? 10 : -6, 'auto', 'inQuad');
  };
  swing(A, P[A][0], 0.1 * T, 0.5 * T, -P[A][0]);      // A lands on the mirror spot at half cycle
  swing(B, P[B][0], 0.6 * T, T, P[B][0]);             // B lands back on its stance spot at T
  // body: low at double support, high at mid-stance, pelvis turns with the swinging leg, sways over the stance foot
  const sA = A === 'footR' ? -1 : 1;
  const body = (t, h, y, s, cz) => keys.push({ t, ease: 'inOutSine', hips: { pos: [-0.03 + 0.015 * dir, hy + h, s * sw], rot: [0, y, 0] },
    bones: { spine: [0, -5, lean + cz], chest: [1, -6 - (y - yaw0) * 0.6, -2 + cz * 0.5] },
    ik: { handR: shoulderHand(0, -h * 0.35, 0) } });
  body(0.25 * T, up, yaw0 + yawA, sA, 1.5);
  body(0.5 * T, 0, yaw0, 0, 0);
  body(0.75 * T, up, yaw0 - yawA, -sA, 1.5);
  // close the loop: A planted since 0.5 T (linear = exactly with the root), root travel
  keys.push({ t: T, interp: 'linear', root: { pos: [d, 0] }, ik: { [A]: planted(A, P[A][0]) } });
  defineClip(name, {
    duration: T, loop: true, breath: 0.7,
    keys: sorted(keys),
    events: [{ t: 0.5 * T, name: 'step', data: { foot: A } }, { t: T - 1e-3, name: 'step', data: { foot: B } }],
  });
}
walk('kael.walkF', 1, def.stats.walkSpeed);
walk('kael.walkB', -1, def.stats.backSpeed);

// ---- dash: shoulder-down rush, two driving steps (0.34 s, 1.9 m) --------------------------------------------------
/** Root keys of the rules' ease-out travel: dist * (1 - (1 - u)^2) sampled at 8 points (linear in between). */
function easeOutRoot(dur, dist) {
  const ks = [];
  for (let i = 0; i <= 8; i++) { const u = i / 8; ks.push({ t: +(u * dur).toFixed(4), interp: 'linear', root: { pos: [+(dist * (1 - (1 - u) * (1 - u))).toFixed(4), 0] } }); }
  return ks;
}
{
  const M = def.movement.dash, T = M.duration, Dd = M.distance;
  const L = (f, u, yaw = YAW_L, p = 0) => ({ space: 'origin', pos: [f, u, FL[2]], rot: [0, yaw, p] });
  const R = (f, u, yaw = YAW_R, p = 0) => ({ space: 'origin', pos: [f, u, FR[2]], rot: [0, yaw, p] });
  defineClip('kael.dash', {
    duration: T, breath: 0,
    keys: sorted([
      { t: 0, ...stance(), ik: { footL: L(FL[0], 0), footR: R(FR[0], 0) } },
      // drive: shoulder drops, blade pulled tight to the shoulder, front knee drives forward
      { t: 0.07, ease: 'outCubic', hips: { pos: [0.1, -0.2, 0.01], rot: [-2, -32, -3] }, bones: { spine: [0, -6, -16], chest: [-2, -6, -12], neck: [0, 12, 12], head: [0, 16, 16] },
        ik: { handR: { pos: [0.27, 1.22, 0.28], aim: [-0.42, 0.9, 0.08] }, footL: L(0.78, 0.13, YAW_L, 12), footR: R(FR[0] + 0.06, 0.03, YAW_R, -30) } },
      { t: 0.15, ease: 'inOutSine', ik: { footL: L(1.6, 0.09, YAW_L, 6), footR: R(0.62, 0.11, YAW_R, -14) } },
      // front foot lands, rear foot drags through
      { t: 0.22, ease: 'inQuad', hips: { pos: [0.12, -0.22, 0], rot: [-1, -28, -2] }, bones: { spine: [0, -5, -12], chest: [-1, -6, -8], neck: [0, 13, 8], head: [0, 17, 10] },
        ik: { footL: L(Dd + FL[0], 0) } },
      { t: 0.27, ease: 'inOutSine', ik: { footR: R(1.36, 0.07, YAW_R, 4), handR: shoulderHand(0.04, -0.04, 0) } },
      { t: 0.31, ease: 'inQuad', ik: { footR: R(Dd + FR[0], 0) } },
      { t: T, ease: 'inOutSine', ...stance(), ik: { footL: L(Dd + FL[0], 0), footR: R(Dd + FR[0], 0) } },
      ...easeOutRoot(T, Dd),
    ]),
    events: [{ t: 0.22, name: 'step', data: { foot: 'footL' } }, { t: 0.31, name: 'step', data: { foot: 'footR' } }],
  });
}

// ---- backstep: heavy hop back (0.38 s, 1.45 m) --------------------------------------------------------------------
{
  const M = def.movement.backstep, T = M.duration, Db = -M.distance;
  const L = (f, u, p = 0) => ({ space: 'origin', pos: [f, u, FL[2]], rot: [0, YAW_L, p] });
  const R = (f, u, p = 0) => ({ space: 'origin', pos: [f, u, FR[2]], rot: [0, YAW_R, p] });
  defineClip('kael.backstep', {
    duration: T, breath: 0,
    keys: sorted([
      { t: 0, ...stance(), ik: { footL: L(FL[0], 0), footR: R(FR[0], 0) } },
      // push off the front foot, chest pulls back, blade lifts off the shoulder for balance
      { t: 0.08, ease: 'outCubic', hips: { pos: [-0.1, -0.06, 0], rot: [0, -30, 0] }, bones: { spine: [0, -6, 8], chest: [0, -7, 9], neck: [0, 14, -6], head: [0, 18, -8] },
        ik: { handR: { pos: [0.24, 1.44, 0.27], aim: [-0.4, 0.91, 0.07] }, footL: L(FL[0] - 0.42, 0.12, -14), footR: R(FR[0] - 0.62, 0.1, 10) } },
      // rear foot lands first
      { t: 0.17, ease: 'inQuad', ik: { footR: R(Db + FR[0], 0) } },
      { t: 0.2, ease: 'inOutSine', hips: { pos: [-0.06, -0.21, 0], rot: [0, -27, 0] }, bones: { spine: [0, -5, -6], chest: [0, -6, -4], neck: [0, 14, 4], head: [0, 18, 2] },
        ik: { handR: shoulderHand(0.02, -0.04, 0), footL: L(Db + FL[0] + 0.12, 0.07, 8) } },
      { t: 0.28, ease: 'inQuad', ik: { footL: L(Db + FL[0], 0) } },
      { t: T, ease: 'inOutSine', ...stance(), ik: { footL: L(Db + FL[0], 0), footR: R(Db + FR[0], 0) } },
      ...easeOutRoot(T, Db),
    ]),
    events: [{ t: 0.17, name: 'step', data: { foot: 'footR' } }, { t: 0.28, name: 'step', data: { foot: 'footL' } }],
  });
}

// ---- dodge: drops under the line, upper body sways back and away, blade hugged to the shoulder (0.46 s) -----------
defineClip('kael.dodge', {
  duration: def.movement.dodge.duration, breath: 0,
  keys: [
    { t: 0, ...stance() },
    { t: 0.09, ease: 'outCubic', hips: { pos: [-0.2, -0.36, -0.13], rot: [-6, -40, -8] }, bones: { spine: [-6, -8, 4], chest: [-8, -10, 8], neck: [2, 16, -4], head: [2, 20, -8] },
      ik: { handR: { pos: [0.08, 1.12, 0.3], aim: [-0.5, 0.86, 0.1] }, footL: { pos: [0.16, 0, -0.22], rot: [0, 18, 0] }, footR: { pos: [-0.44, 0, 0.18], rot: [0, -46, 0] } } },
    { t: 0.29, ease: 'inOutSine', hips: { pos: [-0.18, -0.33, -0.12], rot: [-5, -38, -7] }, bones: { spine: [-5, -8, 2], chest: [-7, -9, 6] } },
    { t: 0.38, ease: 'inOutSine', ik: { footL: { pos: [0.3, 0.05, -0.18], rot: [0, 14, -6] } } },
    { t: 0.46, ease: 'inOutSine', ...stance() },
  ],
  events: [{ t: 0.42, name: 'step', data: { foot: 'footL' } }],
});

// ---- guard: blade upright across the body, left gauntlet braced on the flat (half-sword) ---------------------------
definePose('kael.block', {
  hips: { pos: [-0.07, -0.18, 0], rot: [0, -30, 0] },
  bones: { spine: [0, -6, -9], chest: [2, -8, -7], neck: [0, 16, 8], head: [0, 20, 4], shoulderR: [-4, 0, 0], shoulderL: [-4, 0, 0] },
  ik: {
    handR: { pos: [0.3, 1.0, 0.2], aim: [0.26, 0.92, -0.3], up: [0.12, 0.28, 0.95] },
    footL: { pos: [FL[0] - 0.02, 0, FL[2]], rot: [0, YAW_L, 0] }, footR: { pos: [FR[0] - 0.04, 0, FR[2] + 0.01], rot: [0, YAW_R - 4, 0] },
  },
  grip: 1, curl: [1, 1],
});
defineClip('kael.guard', {
  duration: 2.2, loop: true, gripAt: 'blade', breath: 0.6,
  keys: [
    { t: 0, pose: 'kael.block', ease: 'inOutSine' },
    { t: 1.1, ease: 'inOutSine', hips: { pos: [-0.075, -0.188, 0.006] }, bones: { chest: [2, -8.5, -7.8] },
      ik: { handR: { pos: [0.297, 0.99, 0.202], aim: [0.27, 0.92, -0.29] } } },
  ],
});

export const LOCOMOTION = ['kael.idle', 'kael.walkF', 'kael.walkB', 'kael.dash', 'kael.backstep', 'kael.dodge', 'kael.guard'];
