// Demo clips for the knight design: greatsword held right hand at the guard, left hand on the pommel grip
// (two-handed grip by IK). Positions are fighter-local metres (f forward, u up, s toward the camera); see README.md.
//
//   demo.idle     loop   low ready guard, weight shift, breathing
//   demo.guard    loop   half-sword block (left hand braced on the blade)
//   demo.walkF / demo.walkB   loop, root motion   step-drag walk that keeps the stance
//   demo.combo1 -> demo.combo2 -> demo.combo3   forehand diagonal / rising backhand / spinning sweep finisher
//   demo.slam     heavy overhead slam into the floor with a lunge (root motion)
//   demo.hit      heavy hit reaction from the front (root motion back)
//   demo.combo1M  mirrorClip(..., { hands: 'keep' }) demo: combo1's mirrored diagonal with the same sword hand
// Events: trailOn / hit / trailOff on attacks, impact on the slam, step on foot plants.

import { definePose, defineClip, mirrorClip } from '../anim.js';

const FL = [0.3, 0, -0.14], FR = [-0.3, 0, 0.17];
const FEET = { footL: { pos: FL, rot: [0, 14, 0] }, footR: { pos: FR, rot: [0, -45, 0] } };

// ---- poses -----------------------------------------------------------------------------------------------------------
definePose('demo.stance', {
  hips: { pos: [-0.03, -0.09, 0], rot: [0, -26, 0] },
  bones: { spine: [0, -8, -4], chest: [1, -6, -3], neck: [0, 10, 2], head: [0, 14, -2] },
  ik: { handR: { pos: [0.33, 1.08, 0.1], aim: [0.8, 0.45, -0.15], up: [-0.4, 0.85, 0] }, ...FEET },
  grip: 1, curl: [1, 1],
});

definePose('demo.low', {
  hips: { pos: [-0.02, -0.075, 0], rot: [0, -22, 0] },
  bones: { spine: [0, -6, -2], chest: [0, -5, 0], neck: [0, 9, 2], head: [0, 12, -4] },
  ik: { handR: { pos: [0.26, 0.98, 0.17], aim: [0.75, -0.45, -0.12], up: [0.4, 0.8, 0] }, ...FEET },
  grip: 1, curl: [1, 1],
});

definePose('demo.block', {
  hips: { pos: [-0.06, -0.15, 0], rot: [0, -30, 0] },
  bones: { spine: [0, -6, -10], chest: [2, -8, -6], neck: [0, 12, 8], head: [0, 18, 2] },
  ik: {
    handR: { pos: [0.3, 1.02, 0.16], aim: [0.28, 0.88, -0.38], up: [-1, 0, 0.1] },
    footL: { pos: [0.34, 0, -0.15], rot: [0, 14, 0] }, footR: { pos: [-0.34, 0, 0.18], rot: [0, -48, 0] },
  },
  grip: 1, curl: [1, 1],
});

// follow-through of combo1 = start of combo2 (the link pose makes the chain seamless)
definePose('demo.c1end', {
  hips: { pos: [0.08, -0.14, -0.02], rot: [-3, 34, -4] },
  bones: { spine: [-3, 12, -12], chest: [-4, 10, -10], neck: [0, -10, 4], head: [0, -16, 6] },
  ik: {
    handR: { pos: [0.44, 0.92, -0.12], aim: [0.46, -0.5, -0.72], up: [0.6, 0.6, -0.1] },
    footL: { pos: [0.42, 0, -0.15], rot: [0, 10, 0] }, footR: { pos: FR, rot: [0, -28, 0] },
  },
  grip: 1, curl: [1, 1],
});

// follow-through of combo2 = start of combo3: blade high behind the right shoulder
definePose('demo.c2end', {
  hips: { pos: [0.02, -0.08, 0.02], rot: [2, -46, 3] },
  bones: { spine: [2, -10, 5], chest: [2, -12, 6], neck: [0, 16, 0], head: [0, 22, -6] },
  ik: {
    handR: { pos: [0.02, 1.72, 0.27], aim: [-0.72, 0.42, 0.5], up: [0.2, -0.8, 0.5] },
    footL: { pos: [0.4, 0, -0.15], rot: [0, 12, 0] }, footR: { pos: FR, rot: [0, -50, 0] },
  },
  grip: 1, curl: [1, 1],
});

// ---- idle / guard ------------------------------------------------------------------------------------------------
defineClip('demo.idle', {
  duration: 2.6, loop: true, breath: 1.2,
  keys: [
    { t: 0, pose: 'demo.low', ease: 'inOutSine' },
    { t: 0.75, ease: 'inOutSine', hips: { pos: [-0.035, -0.084, 0.016], rot: [1.6, -24, 0.8] }, bones: { chest: [-0.5, -6, 0.6] },
      ik: { handR: { pos: [0.255, 0.972, 0.176], aim: [0.75, -0.48, -0.12] } } },
    { t: 1.3, ease: 'inOutSine', hips: { pos: [-0.02, -0.075, 0], rot: [0, -22, 0] }, bones: { chest: [0, -5, 0] },
      ik: { handR: { pos: [0.262, 0.982, 0.17], aim: [0.75, -0.45, -0.12] } } },
    { t: 2.0, ease: 'inOutSine', hips: { pos: [-0.008, -0.081, -0.014], rot: [-1.6, -20, -0.6] }, bones: { chest: [0.6, -4, -0.6] },
      ik: { handR: { pos: [0.268, 0.976, 0.164], aim: [0.76, -0.42, -0.12] } } },
  ],
});

defineClip('demo.guard', {
  duration: 2.0, loop: true, gripAt: 'blade', breath: 0.6,
  keys: [
    { t: 0, pose: 'demo.block', ease: 'inOutSine' },
    { t: 1.0, ease: 'inOutSine', hips: { pos: [-0.065, -0.157, 0.006] }, bones: { chest: [2, -8.5, -6.8] },
      ik: { handR: { pos: [0.298, 1.012, 0.162], aim: [0.29, 0.88, -0.37] } } },
  ],
});

// ---- walks ---------------------------------------------------------------------------------------------------------
/** Step-drag stance walk: lead foot steps, trail foot follows; planted feet move exactly with the root (no sliding). */
function walk(name, dir) {
  const T = 0.76, D = 0.36 * dir, v = D / T, h = 0.075;
  const lead = dir > 0 ? 'footL' : 'footR', trail = dir > 0 ? 'footR' : 'footL';
  const x0 = { footL: FL, footR: FR };
  const yaw = { footL: 14, footR: -45 };
  const step = (foot, a, b) => {
    const p = x0[foot], m = (a + b) / 2;
    return [
      [a, { pos: [p[0] - v * a, 0, p[2]], rot: [0, yaw[foot], 0] }, 'linear'],
      [a + (b - a) * 0.3, { pos: [p[0] + D * 0.2 - v * (a + (b - a) * 0.3), h * 0.8, p[2]], rot: [0, yaw[foot], -14 * dir] }, 'auto', 'outQuad'],
      [m, { pos: [p[0] + D * 0.5 - v * m, h, p[2] + 0.01 * Math.sign(p[2])], rot: [0, yaw[foot], 0] }, 'auto'],
      [b, { pos: [p[0] + D - v * b, 0, p[2]], rot: [0, yaw[foot], 6 * dir] }, 'auto', 'inQuad'],
    ];
  };
  const keys = [{ t: 0, pose: 'demo.stance', root: { pos: [0, 0] } }];
  const add = (t, ik, interp, ease, extra = {}) => keys.push({ t, ik, interp, ease, ...extra });
  for (const [t, k, interp, ease] of step(lead, 0.04 * T, 0.42 * T)) add(t, { [lead]: k }, interp, ease);
  for (const [t, k, interp, ease] of step(trail, 0.5 * T, 0.88 * T)) add(t, { [trail]: k }, interp, ease);
  // body: bob up during each swing, surge after each plant, slight sway of the blade
  const hy = -0.09;
  keys.push({ t: 0.23 * T, ease: 'inOutSine', hips: { pos: [-0.03 + 0.02 * dir, hy + 0.018, -0.008], rot: [-1.5, -27 + 3 * dir, -1] }, ik: { handR: { pos: [0.33, 1.095, 0.1] } } });
  keys.push({ t: 0.46 * T, ease: 'inOutSine', hips: { pos: [-0.03 + 0.03 * dir, hy - 0.012, 0], rot: [0, -26, 0] }, ik: { handR: { pos: [0.335, 1.07, 0.1] } } });
  keys.push({ t: 0.69 * T, ease: 'inOutSine', hips: { pos: [-0.03 - 0.005 * dir, hy + 0.015, 0.008], rot: [1.5, -25 - 3 * dir, 1] }, ik: { handR: { pos: [0.325, 1.09, 0.1] } } });
  keys.push({ t: 0.94 * T, ease: 'inOutSine', hips: { pos: [-0.03, hy - 0.006, 0], rot: [0, -26, 0] }, ik: { handR: { pos: [0.33, 1.075, 0.1] } } });
  keys.push({ t: T, interp: 'linear', root: { pos: [D, 0] }, ik: { footL: { pos: FL, rot: [0, yaw.footL, 0] }, footR: { pos: FR, rot: [0, yaw.footR, 0] } } });
  defineClip(name, {
    duration: T, loop: true, breath: 0.5,
    keys: keys.sort((a, b) => a.t - b.t),
    events: [{ t: 0.42 * T, name: 'step', data: { foot: lead } }, { t: 0.88 * T, name: 'step', data: { foot: trail } }],
  });
}
walk('demo.walkF', 1);
walk('demo.walkB', -1);

// ---- combo ---------------------------------------------------------------------------------------------------------
// 1: forehand diagonal descending cut (high right -> low left). Coil 0-0.15, hang, smear 0.205-0.25, follow-through.
defineClip('demo.combo1', {
  duration: 0.95, breath: 0.3,
  keys: [
    { t: 0, pose: 'demo.stance' },
    { t: 0.15, ease: 'outCubic',
      hips: { pos: [-0.1, -0.07, 0.02], rot: [3, -50, 2] },
      bones: { spine: [2, -10, 6], chest: [3, -15, 6], neck: [0, 18, 0], head: [0, 26, -6] },
      ik: { handR: { pos: [-0.08, 1.6, 0.21], aim: [-0.85, 0.28, 0.44], up: [0.25, -0.9, 0.15] } } },
    { t: 0.2, ease: 'inOutSine',
      hips: { pos: [-0.08, -0.08, 0.015], rot: [2, -38, 1] },
      bones: { spine: [2, -10, 4], chest: [3, -17, 4] },
      ik: { handR: { pos: [-0.04, 1.63, 0.2], aim: [-0.92, 0.04, 0.4], up: [0.1, -0.9, 0.3] }, footL: { pos: [0.37, 0.06, -0.145], rot: [0, 12, -8] } } },
    { t: 0.225, ik: { handR: { pos: [0.22, 1.55, 0.14], aim: [0.15, 0.96, 0.15], up: [-0.95, 0.1, 0.25] } } },
    { t: 0.25,
      hips: { pos: [0.06, -0.12, -0.01], rot: [-2, 12, -3] },
      bones: { spine: [-2, 8, -8], chest: [-3, 8, -6], neck: [0, -6, 2], head: [0, -8, 4] },
      ik: { handR: { pos: [0.56, 1.17, 0.03], aim: [0.82, -0.42, -0.38], up: [0.3, 0.8, -0.5] }, footL: { pos: [0.42, 0, -0.15], rot: [0, 10, 0] }, footR: { pos: FR, rot: [0, -32, 0] } } },
    { t: 0.34, ease: 'outQuad', pose: 'demo.c1end' },
    { t: 0.47, ease: 'inOutSine', hips: { pos: [0.07, -0.135, -0.02], rot: [-2, 31, -3] }, ik: { handR: { pos: [0.44, 0.95, -0.11], aim: [0.5, -0.46, -0.72] } } },
    { t: 0.62, ease: 'inOutSine', ik: { footL: { pos: [0.42, 0, -0.15], rot: [0, 10, 0] } } },
    { t: 0.74, ease: 'inOutSine', ik: { footL: { pos: [0.36, 0.05, -0.145], rot: [0, 12, -6] } } },
    { t: 0.84, ease: 'inQuad', ik: { footL: { pos: FL, rot: [0, 14, 0] } } },
    { t: 0.95, ease: 'inOutSine', pose: 'demo.stance' },
  ],
  events: [{ t: 0.17, name: 'trailOn' }, { t: 0.245, name: 'hit' }, { t: 0.25, name: 'step', data: { foot: 'footL' } }, { t: 0.42, name: 'trailOff' }],
});

// 2: rising backhand diagonal (low left -> high right), from the combo1 follow-through.
defineClip('demo.combo2', {
  duration: 0.9, base: 'demo.c1end', breath: 0.3,
  keys: [
    { t: 0, pose: 'demo.c1end' },
    { t: 0.11, ease: 'outCubic',
      hips: { pos: [0.05, -0.15, -0.025], rot: [-3, 46, -5] },
      bones: { spine: [-3, 14, -10], chest: [-4, 17, -8], neck: [0, -14, 4], head: [0, -20, 4] },
      ik: { handR: { pos: [0.12, 0.86, -0.3], aim: [-0.58, -0.5, -0.64], up: [-0.4, -0.4, 0.5] } } },
    { t: 0.155, ease: 'inOutSine',
      hips: { pos: [0.05, -0.15, -0.02], rot: [-3, 36, -4] },
      ik: { handR: { pos: [0.12, 0.84, -0.29], aim: [-0.7, -0.42, -0.58], up: [-0.4, -0.5, 0.4] } } },
    { t: 0.19, ik: { handR: { pos: [0.42, 1.0, -0.08], aim: [0.78, -0.18, -0.6], up: [0.1, -0.98, 0.1] } } },
    { t: 0.225,
      hips: { pos: [0.08, -0.1, 0.0], rot: [1, -14, 2] },
      bones: { spine: [1, -8, 2], chest: [1, -12, 4], neck: [0, 8, -2], head: [0, 10, -6] },
      ik: { handR: { pos: [0.56, 1.36, 0.12], aim: [0.72, 0.62, 0.3], up: [-0.6, 0.4, 0.7] } } },
    { t: 0.28, ik: { handR: { pos: [0.26, 1.72, 0.25], aim: [-0.2, 0.9, 0.38], up: [-0.6, -0.3, 0.7] } } },
    { t: 0.38, ease: 'outQuad', pose: 'demo.c2end' },
    { t: 0.5, ease: 'inOutSine', hips: { pos: [0.02, -0.085, 0.02], rot: [2, -44, 3] }, ik: { handR: { pos: [0.04, 1.69, 0.27], aim: [-0.7, 0.38, 0.52] } } },
    { t: 0.6, ease: 'inOutSine', ik: { footL: { pos: [0.4, 0, -0.15], rot: [0, 12, 0] } } },
    { t: 0.71, ease: 'inOutSine', ik: { footL: { pos: [0.35, 0.05, -0.145], rot: [0, 13, -6] } } },
    { t: 0.8, ease: 'inQuad', ik: { footL: { pos: FL, rot: [0, 14, 0] } } },
    { t: 0.9, ease: 'inOutSine', pose: 'demo.stance' },
  ],
  events: [{ t: 0.15, name: 'trailOn' }, { t: 0.215, name: 'hit' }, { t: 0.44, name: 'trailOff' }],
});

// 3: spinning horizontal sweep finisher (one full turn, two passes through the front), steps 0.5 m forward.
// Hands are keyed in the chest frame during the spin so the blade rides the torso rotation; feet are planted in the
// clip-start ("origin") frame: the left foot pivots, the right foot circles around it.
{
  const T = 1.35, D = 0.5;
  const keys = [{ t: 0, pose: 'demo.c2end', root: { pos: [0, 0] } }];
  const hipYaw = [[0.17, -82], [0.29, -26], [0.37, 62], [0.45, 152], [0.53, 240], [0.61, 318], [0.71, 372], [0.86, 352], [T, 334]];
  const hipPos = [[0.17, [-0.1, -0.11, 0.02]], [0.29, [-0.02, -0.15, 0]], [0.45, [0.02, -0.14, 0]], [0.61, [0.04, -0.15, 0]], [0.71, [0.06, -0.17, -0.01]], [0.86, [0.03, -0.14, 0]]];
  hipYaw.forEach(([t, y], i) => keys.push({ t, ease: i === 0 ? 'outCubic' : i === hipYaw.length - 1 ? 'inOutSine' : 'linear', hips: { rot: [0, y, i > 0 && i < 6 ? -6 : 0] } }));
  hipPos.forEach(([t, p]) => keys.push({ t, hips: { pos: p } }));
  // torso: coil and lag, then whip through
  keys.push({ t: 0.17, ease: 'outCubic', bones: { spine: [2, -12, 6], chest: [3, -18, 6], neck: [0, 20, 0], head: [0, 26, -4] } });
  keys.push({ t: 0.3, bones: { spine: [0, -10, -6], chest: [0, -14, -4], neck: [0, 12, 0], head: [0, 14, 0] } });
  keys.push({ t: 0.45, bones: { spine: [0, 4, -8], chest: [0, 6, -6], neck: [0, -4, 0], head: [0, -6, 0] } });
  keys.push({ t: 0.71, bones: { spine: [-2, 12, -10], chest: [-2, 14, -8], neck: [0, -16, 2], head: [0, -20, 4] } });
  // weapon hand: chest frame during the spin, back to the fighter frame for the recovery
  const ch = (t, pos, aim, up, ease) => keys.push({ t, ease, ik: { handR: { space: 'chest', pos, aim, up } } });
  keys.push({ t: 0.09, ik: { handR: { pos: [-0.12, 1.62, 0.3], aim: [-0.85, 0.2, 0.5], up: [0.3, -0.9, 0.2] } } });
  ch(0.17, [0.18, 0.02, 0.36], [-0.75, -0.05, 0.66], [0.6, 0.05, 0.75], 'outCubic');
  ch(0.29, [0.36, -0.1, 0.28], [-0.15, -0.08, 0.99], [0.98, 0.0, 0.15]);
  ch(0.37, [0.46, -0.13, 0.12], [0.42, -0.1, 0.9], [0.9, 0.05, -0.42]);
  ch(0.53, [0.47, -0.14, 0.1], [0.5, -0.12, 0.86], [0.86, 0.0, -0.5]);
  ch(0.71, [0.43, -0.2, -0.08], [0.82, -0.25, -0.5], [0.5, 0.1, 0.86], 'outQuad');
  ch(0.86, [0.4, -0.22, -0.1], [0.68, -0.4, -0.6], [0.5, 0.3, 0.8], 'inOutSine');
  keys.push({ t: T, ease: 'inOutSine', ik: { handR: { pos: [0.33, 1.08, 0.1], aim: [0.8, 0.45, -0.15], up: [-0.4, 0.85, 0] } } });
  // feet: left pivots in place (toes follow the hips), right circles around it and lands; then the stance re-forms
  const piv = [0.42, 0, -0.15];
  const yawL = (y) => [0, Math.max(-40, Math.min(60, y * 0.3 + 10)), 0];
  keys.push({ t: 0.17, ik: { footL: { space: 'origin', pos: piv, rot: [0, 12, 0] }, footR: { space: 'origin', pos: [-0.3, 0, 0.17], rot: [0, -60, 0] } } });
  const rel = [-0.72, 0.32];
  const around = [[0.3, 0], [0.4, 70], [0.48, 150], [0.56, 230], [0.64, 300], [0.72, 360]];
  around.forEach(([t, a]) => {
    const r = (a * Math.PI) / 180, c = Math.cos(r), s = Math.sin(r);
    const fx = piv[0] + rel[0] * c + rel[1] * s, fz = piv[2] - rel[0] * s + rel[1] * c;
    const lift = a > 0 ? 0.09 * Math.sin(Math.min(1, a / 330) * Math.PI) + 0.03 : 0;
    keys.push({ t, ik: { footR: { space: 'origin', pos: [fx + (a / 360) * 0.18, lift, fz], rot: [0, -60 + a, 0] }, footL: { space: 'origin', pos: piv, rot: yawL(a) } } });
  });
  keys.push({ t: 0.86, ik: { footL: { space: 'origin', pos: piv, rot: [0, 12, 0] }, footR: { space: 'origin', pos: [-0.12, 0, 0.17], rot: [0, -50, 0] } } });
  keys.push({ t: 1.02, ik: { footL: { space: 'origin', pos: [0.62, 0.06, -0.15], rot: [0, 12, -6] } } });
  keys.push({ t: 1.12, ease: 'inQuad', ik: { footL: { space: 'origin', pos: [0.8, 0, -0.14], rot: [0, 14, 0] } } });
  keys.push({ t: 1.2, ease: 'inOutSine', ik: { footR: { space: 'origin', pos: [-0.12 + 0.08, 0.04, 0.17], rot: [0, -46, 0] } } });
  keys.push({ t: T, ease: 'inOutSine', ik: { footL: { space: 'origin', pos: [FL[0] + D, 0, FL[2]], rot: [0, 14, 0] }, footR: { space: 'origin', pos: [FR[0] + D, 0, FR[2]], rot: [0, -45, 0] } } });
  keys.push({ t: 0.3, root: { pos: [0.05, 0] } }, { t: 0.72, root: { pos: [0.3, 0] } }, { t: T, root: { pos: [D, 0] } });
  keys.push({ t: T, bones: { spine: [0, -8, -4], chest: [1, -6, -3], neck: [0, 10, 2], head: [0, 14, -2] }, hips: { pos: [-0.03, -0.09, 0] } });
  defineClip('demo.combo3', {
    duration: T, base: 'demo.c2end', breath: 0.2,
    keys: keys.sort((a, b) => a.t - b.t),
    events: [{ t: 0.24, name: 'trailOn' }, { t: 0.36, name: 'hit' }, { t: 0.66, name: 'hit' }, { t: 0.82, name: 'trailOff' }],
  });
}

// ---- heavy overhead slam ------------------------------------------------------------------------------------------
defineClip('demo.slam', {
  duration: 1.75, breath: 0.2,
  keys: [
    { t: 0, pose: 'demo.stance', root: { pos: [0, 0] } },
    // gather: knees sink, blade dips
    { t: 0.13, ease: 'inOutSine', hips: { pos: [-0.05, -0.16, 0], rot: [0, -22, 0] }, bones: { spine: [0, -6, -8], chest: [0, -4, -6] },
      ik: { handR: { pos: [0.3, 0.98, 0.12], aim: [0.82, 0.28, -0.15], up: [-0.3, 0.9, 0] } } },
    // windup: blade raised overhead and back, body arched, front foot lifts
    { t: 0.46, ease: 'outCubic', hips: { pos: [-0.12, -0.04, 0], rot: [0, -10, 0] }, bones: { spine: [0, -2, 12], chest: [0, -3, 14], neck: [0, 4, -8], head: [0, 6, -12] },
      ik: { handR: { pos: [-0.06, 1.92, 0.1], aim: [-0.72, 0.25, 0.05], up: [0.25, -0.95, 0] }, footL: { space: 'origin', pos: [0.36, 0.1, -0.14], rot: [0, 10, -12] } } },
    { t: 0.54, ease: 'inOutSine', hips: { pos: [-0.1, -0.05, 0], rot: [0, -8, 0] }, bones: { spine: [0, -2, 15], chest: [0, -3, 17] },
      ik: { handR: { pos: [-0.09, 1.95, 0.1], aim: [-0.85, -0.2, 0.05], up: [-0.2, -0.95, 0] }, footL: { space: 'origin', pos: [0.48, 0.13, -0.14], rot: [0, 10, 4] } } },
    { t: 0.585, ik: { handR: { pos: [0.28, 1.85, 0.06], aim: [0.4, 0.92, 0.0], up: [-0.92, 0.4, 0] }, footL: { space: 'origin', pos: [0.64, 0.05, -0.15] } } },
    // impact: blade into the floor, deep lunge
    { t: 0.63, ease: 'inQuad', hips: { pos: [-0.1, -0.34, -0.01], rot: [0, -12, 0] }, bones: { spine: [0, -2, -24], chest: [0, -2, -20], neck: [0, 4, 14], head: [0, 6, 18] },
      ik: { handR: { pos: [0.42, 0.72, 0.05], aim: [0.74, -0.67, -0.04], up: [-0.67, -0.74, 0] }, footL: { space: 'origin', pos: [0.74, 0, -0.16], rot: [0, 10, 0] }, footR: { space: 'origin', pos: [-0.3, 0, 0.18], rot: [0, -38, 0] } } },
    { t: 0.7, ease: 'outQuad', hips: { pos: [-0.11, -0.31, -0.01] }, bones: { spine: [0, -2, -22], chest: [0, -2, -18] }, ik: { handR: { pos: [0.41, 0.76, 0.05], aim: [0.76, -0.64, -0.04] } } },
    { t: 1.0, ease: 'inOutSine', hips: { pos: [-0.12, -0.32, -0.01] }, ik: { handR: { pos: [0.42, 0.75, 0.05], aim: [0.75, -0.65, -0.04] } } },
    // recover: wrench the blade free, rear foot steps up
    { t: 1.22, ease: 'inOutSine', hips: { pos: [-0.2, -0.2, 0], rot: [0, -22, 0] }, bones: { spine: [0, -6, -8], chest: [0, -5, -5], neck: [0, 8, 4], head: [0, 12, 0] },
      ik: { handR: { pos: [0.2, 1.05, 0.12], aim: [0.8, 0.2, -0.12], up: [-0.3, 0.9, 0] }, footR: { space: 'origin', pos: [-0.28, 0, 0.18], rot: [0, -40, 0] } } },
    { t: 1.36, ease: 'inOutSine', ik: { footR: { space: 'origin', pos: [-0.06, 0.06, 0.18], rot: [0, -44, 0] } } },
    { t: 1.48, ease: 'inQuad', ik: { footR: { space: 'origin', pos: [0.14, 0, 0.17], rot: [0, -45, 0] } } },
    { t: 1.75, ease: 'inOutSine', pose: 'demo.stance', ik: { footL: { space: 'origin', pos: [0.74, 0, -0.14], rot: [0, 14, 0] }, footR: { space: 'origin', pos: [0.14, 0, 0.17], rot: [0, -45, 0] } } },
    { t: 0.4, root: { pos: [0, 0] } }, { t: 0.63, root: { pos: [0.32, 0] } }, { t: 1.2, root: { pos: [0.34, 0] } }, { t: 1.5, root: { pos: [0.44, 0] } },
  ].sort((a, b) => a.t - b.t),
  events: [{ t: 0.5, name: 'trailOn' }, { t: 0.63, name: 'impact' }, { t: 0.63, name: 'hit' }, { t: 0.66, name: 'trailOff' }, { t: 1.48, name: 'step', data: { foot: 'footR' } }],
});

// ---- hit reaction --------------------------------------------------------------------------------------------------
defineClip('demo.hit', {
  duration: 0.85, breath: 0.6,
  keys: [
    { t: 0, pose: 'demo.stance', root: { pos: [0, 0] } },
    { t: 0.06, ease: 'outQuad', hips: { pos: [-0.1, -0.11, 0.01], rot: [-4, -34, 7] }, bones: { spine: [-4, -10, 12], chest: [-5, -8, 15], neck: [4, 6, 16], head: [6, 10, 24], shoulderR: [0, 0, 6], shoulderL: [0, 0, 6] },
      ik: { handR: { pos: [0.2, 1.2, 0.2], aim: [0.5, 0.82, -0.1], up: [-0.8, 0.5, 0] }, footL: { space: 'origin', pos: FL, rot: [0, 14, 0] }, footR: { space: 'origin', pos: FR, rot: [0, -45, 0] } } },
    { t: 0.15, ease: 'inOutSine', hips: { pos: [-0.08, -0.16, 0.01], rot: [-3, -36, 5] }, bones: { spine: [-2, -10, 6], chest: [-3, -9, 8], neck: [2, 8, 6], head: [3, 10, 6], shoulderR: [0, 0, 0], shoulderL: [0, 0, 0] },
      ik: { handR: { pos: [0.18, 1.1, 0.2], aim: [0.6, 0.62, -0.12] }, footR: { space: 'origin', pos: [-0.4, 0.06, 0.19], rot: [0, -48, 6] } } },
    { t: 0.24, ease: 'inQuad', ik: { footR: { space: 'origin', pos: [-0.5, 0, 0.19], rot: [0, -50, 0] } } },
    { t: 0.36, ease: 'inOutSine', hips: { pos: [-0.04, -0.13, 0.0], rot: [-1, -30, 2] }, bones: { spine: [0, -9, -2], chest: [0, -7, -1] }, ik: { handR: { pos: [0.28, 1.05, 0.13], aim: [0.78, 0.45, -0.14] }, footL: { space: 'origin', pos: FL, rot: [0, 14, 0] } } },
    { t: 0.48, ease: 'inOutSine', ik: { footL: { space: 'origin', pos: [0.18, 0.05, -0.14], rot: [0, 14, -6] } } },
    { t: 0.58, ease: 'inQuad', ik: { footL: { space: 'origin', pos: [0.1, 0, -0.14], rot: [0, 14, 0] } } },
    { t: 0.85, ease: 'inOutSine', pose: 'demo.stance', ik: { footL: { space: 'origin', pos: [0.1, 0, -0.14], rot: [0, 14, 0] }, footR: { space: 'origin', pos: [-0.5, 0, 0.17], rot: [0, -45, 0] } } },
    { t: 0.12, root: { pos: [-0.12, 0] } }, { t: 0.55, root: { pos: [-0.2, 0] } },
  ].sort((a, b) => a.t - b.t),
  events: [{ t: 0.24, name: 'step', data: { foot: 'footR' } }, { t: 0.58, name: 'step', data: { foot: 'footL' } }],
});

// mirrored-clip helper demo: the same right-handed knight cuts the mirrored diagonal (high left -> low right)
mirrorClip('demo.combo1', 'demo.combo1M', { hands: 'keep' });
