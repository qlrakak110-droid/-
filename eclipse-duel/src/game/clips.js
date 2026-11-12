// Clip resolution for the presentation layer + the generic fallback clips (`game.*`).
//
// Every fighter animates from the rules state. A state / move id resolves to a clip in this order:
//   1. the fighter's own map (fighter module `clips`: { idle: 'kael.idle', light1: 'kael.light1', ... })
//   2. the generic clips below / the demo knight clips, retimed onto the rules' frame data
// Move clips are sampled at the rules' move time (`setClipTime`), so animation is locked to the frame data:
//   * a fighter clip is assumed authored against its move (clip time = move time) unless its entry gives `hit`
//     (the clip time of the first impact) - then it is retimed like the fallbacks;
//   * fallback clips are retimed piecewise: [0, startup] -> [0, clip impact], [startup, end] -> [clip impact, clip end].
// The generic clips are authored for a right-handed weapon held two-handed by grip IK (the knight's greatsword) but
// only use hand IK in the fighter frame, so other designs stay readable until their own clips exist.

import { defineClip, definePose, hasClip } from '../char/index.js';
import { getClipDef } from '../char/anim.js';
import '../char/clips/demo.js';
import { deriveFrameData } from './logic/index.js';

// ---------------------------------------------------------------------------------------------------------------
// generic clips (fallbacks for states the demo set does not cover)

const FL = [0.3, 0, -0.14], FR = [-0.3, 0, 0.17];
const FEET = { footL: { pos: FL, rot: [0, 14, 0] }, footR: { pos: FR, rot: [0, -45, 0] } };
const STANCE_HAND = { pos: [0.33, 1.08, 0.1], aim: [0.8, 0.45, -0.15], up: [-0.4, 0.85, 0] };
const LOOSE_ARMS = { upperArmR: [-28, 0, 10], foreArmR: [0, 0, 30], upperArmL: [-30, 0, 14], foreArmL: [0, 0, 26] };
const NO_FEET = { footL: { pos: FL, w: 0 }, footR: { pos: FR, w: 0 } };
/** Weapon hand riding the torso (chest frame) while lying: blade flat on the floor beside the body, toward the feet. */
const LYING_HAND = { space: 'chest', pos: [-0.08, -0.42, 0.42], aim: [-0.08, -0.92, 0.38], up: [0, 0.38, 0.92] };
/** Weapon hand while airborne: blade trailing along the body. */
const AIR_HAND = { space: 'chest', pos: [0.05, -0.5, 0.36], aim: [-0.5, -0.82, 0.25], up: [0.82, -0.5, 0] };

// lying on the back, head away from the opponent, one knee up, arms out
definePose('game.downPose', {
  hips: { pos: [0.22, -0.9, 0], rot: [0, -8, 84] },
  bones: {
    spine: [0, 0, 4], chest: [0, -4, 6], neck: [0, 10, -6], head: [6, 24, -10],
    thighR: [-8, 0, 8], shinR: [0, 0, -14], footR: [0, 0, -30], thighL: [10, 0, 34], shinL: [0, 0, -64], footL: [0, 0, -10],
    upperArmL: [-48, 0, 20], foreArmL: [0, 0, 34],
  },
  ik: { handR: LYING_HAND },
  grip: 0, curl: [0.5, 1],
});
definePose('game.koPose', {
  hips: { pos: [0.22, -0.91, 0], rot: [0, -4, 87] },
  bones: {
    spine: [2, 0, 2], chest: [2, -2, 3], neck: [0, 18, -2], head: [10, 40, -6],
    thighR: [-12, 0, 2], shinR: [0, 0, -6], footR: [0, 0, -36], thighL: [6, 0, 14], shinL: [0, 0, -26], footL: [0, 0, -30],
    upperArmL: [-70, 0, 6], foreArmL: [0, 0, 18],
  },
  ik: { handR: { ...LYING_HAND, pos: [-0.06, -0.38, 0.5] } },
  grip: 0, curl: [0.2, 1],
});
// airborne, rising: arched back, limbs trailing
definePose('game.airRisePose', {
  hips: { pos: [0, 0.05, 0], rot: [0, -18, 32] },
  bones: {
    spine: [0, 0, 10], chest: [0, -4, 12], neck: [0, 8, 14], head: [4, 10, 18],
    thighR: [-6, 0, 18], shinR: [0, 0, -48], footR: [0, 0, -24], thighL: [6, 0, 36], shinL: [0, 0, -70], footL: [0, 0, -20],
    ...LOOSE_ARMS, upperArmL: [-64, 0, 26],
  },
  ik: { handR: AIR_HAND },
  grip: 0, curl: [0.4, 1],
});
// airborne, falling: body near horizontal, ready to hit the floor on the back
definePose('game.airFallPose', {
  hips: { pos: [0.05, -0.25, 0], rot: [0, -12, 66] },
  bones: {
    spine: [0, 0, 6], chest: [0, -2, 6], neck: [0, 6, -10], head: [2, 12, -14],
    thighR: [-4, 0, 30], shinR: [0, 0, -36], footR: [0, 0, -20], thighL: [8, 0, 48], shinL: [0, 0, -58], footL: [0, 0, -16],
    ...LOOSE_ARMS, upperArmL: [-58, 0, 40],
  },
  ik: { handR: { ...AIR_HAND, pos: [0.12, -0.42, 0.4], aim: [-0.2, -0.75, 0.62] } },
  grip: 0, curl: [0.4, 1],
});

/** Step-drag stance walk with planted feet (no sliding at `D / T` m/s; D < 0 walks backward, trail foot first). */
function walk(name, dir, D, T) {
  const v = D / T, h = 0.09;
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
  for (const [t, k, interp, ease] of step(lead, 0.04 * T, 0.42 * T)) keys.push({ t, ik: { [lead]: k }, interp, ease });
  for (const [t, k, interp, ease] of step(trail, 0.5 * T, 0.88 * T)) keys.push({ t, ik: { [trail]: k }, interp, ease });
  const hy = -0.1, lean = dir > 0 ? -4 : 3;
  keys.push({ t: 0.23 * T, ease: 'inOutSine', hips: { pos: [-0.03 + 0.03 * dir, hy + 0.022, -0.01], rot: [-2, -27 + 4 * dir, -1.5] }, bones: { spine: [0, -8, lean], chest: [1, -6, lean] }, ik: { handR: { pos: [0.34, 1.1, 0.1] } } });
  keys.push({ t: 0.46 * T, ease: 'inOutSine', hips: { pos: [-0.03 + 0.045 * dir, hy - 0.016, 0], rot: [0, -26, 0] }, ik: { handR: { pos: [0.335, 1.065, 0.1] } } });
  keys.push({ t: 0.69 * T, ease: 'inOutSine', hips: { pos: [-0.03 - 0.01 * dir, hy + 0.02, 0.01], rot: [2, -25 - 4 * dir, 1.5] }, bones: { spine: [0, -8, lean], chest: [1, -6, lean] }, ik: { handR: { pos: [0.325, 1.095, 0.1] } } });
  keys.push({ t: 0.94 * T, ease: 'inOutSine', hips: { pos: [-0.03, hy - 0.008, 0], rot: [0, -26, 0] }, ik: { handR: { pos: [0.33, 1.075, 0.1] } } });
  keys.push({ t: T, interp: 'linear', root: { pos: [D, 0] }, ik: { footL: { pos: FL, rot: [0, yaw.footL, 0] }, footR: { pos: FR, rot: [0, yaw.footR, 0] } } });
  defineClip(name, {
    duration: T, loop: true, breath: 0.4,
    keys: keys.sort((a, b) => a.t - b.t),
    events: [{ t: 0.42 * T, name: 'step', data: { foot: lead } }, { t: 0.88 * T, name: 'step', data: { foot: trail } }],
  });
}
walk('game.walkF', 1, 0.5, 0.46);
walk('game.walkB', -1, -0.42, 0.5);

/**
 * The generic walk re-authored for a rules walk speed v (m/s): the cadence rises a little with speed (period
 * T0 / (v / v0)^0.3, at most 1.4x) and the stride takes the rest, so the planted feet move exactly with the root at
 * playback speed 1 (no foot slide whatever the fighter's walkSpeed / backSpeed). Defined once per speed.
 * @returns {string} clip name
 */
export function walkClipFor(dir, v) {
  const [T0, v0] = dir > 0 ? [0.46, 0.5 / 0.46] : [0.5, 0.42 / 0.5];
  if (!(v > 0)) return dir > 0 ? 'game.walkF' : 'game.walkB';
  const name = `game.walk${dir > 0 ? 'F' : 'B'}@${v.toFixed(2)}`;
  if (!hasClip(name)) {
    const T = T0 / Math.min(1.4, Math.max(1, Math.pow(v / v0, 0.3)));
    walk(name, dir, dir * v * T, T);
  }
  return name;
}

defineClip('game.dash', {
  duration: 0.3, breath: 0,
  keys: [
    { t: 0, pose: 'demo.stance' },
    { t: 0.06, ease: 'outCubic', hips: { pos: [0.08, -0.22, 0], rot: [0, -18, 0] }, bones: { spine: [0, -4, -16], chest: [0, -4, -12], neck: [0, 6, 10], head: [0, 8, 14] },
      ik: { handR: { pos: [-0.02, 0.86, 0.3], aim: [-0.78, -0.5, 0.36], up: [-0.5, 0.85, 0.1] }, footL: { pos: [0.5, 0.14, -0.14], rot: [0, 14, -10] }, footR: { pos: [-0.42, 0.04, 0.17], rot: [0, -45, 20] } } },
    { t: 0.17, ease: 'inOutSine', hips: { pos: [0.1, -0.24, 0], rot: [0, -20, 0] }, ik: { handR: { pos: [-0.04, 0.84, 0.3] }, footL: { pos: [0.42, 0, -0.14], rot: [0, 14, 0] } } },
    { t: 0.24, ease: 'inOutSine', ik: { footR: { pos: [-0.26, 0.05, 0.17], rot: [0, -45, 6] } } },
    { t: 0.3, ease: 'inOutSine', pose: 'demo.stance' },
  ],
  events: [{ t: 0.17, name: 'step', data: { foot: 'footL' } }],
});

defineClip('game.backstep', {
  duration: 0.34, breath: 0,
  keys: [
    { t: 0, pose: 'demo.stance' },
    { t: 0.08, ease: 'outQuad', hips: { pos: [-0.1, -0.02, 0], rot: [0, -30, 0] }, bones: { spine: [0, -6, 8], chest: [0, -6, 8], neck: [0, 8, -6], head: [0, 12, -8] },
      ik: { handR: { pos: [0.3, 1.2, 0.12], aim: [0.6, 0.78, -0.1], up: [-0.75, 0.6, 0] }, footL: { pos: [0.22, 0.14, -0.14], rot: [0, 14, -14] }, footR: { pos: [-0.44, 0.1, 0.17], rot: [0, -45, -10] } } },
    { t: 0.2, ease: 'inQuad', hips: { pos: [-0.06, -0.2, 0], rot: [0, -28, 0] }, bones: { spine: [0, -6, -4], chest: [0, -6, -2] },
      ik: { footL: { pos: [0.26, 0, -0.14], rot: [0, 14, 0] }, footR: { pos: [-0.4, 0, 0.17], rot: [0, -45, 0] } } },
    { t: 0.34, ease: 'inOutSine', pose: 'demo.stance' },
  ],
  events: [{ t: 0.2, name: 'step', data: { foot: 'footR' } }],
});

defineClip('game.dodge', {
  duration: 0.42, breath: 0,
  keys: [
    { t: 0, pose: 'demo.stance' },
    { t: 0.08, ease: 'outCubic', hips: { pos: [-0.16, -0.34, -0.14], rot: [-6, -44, -6] }, bones: { spine: [-4, -10, 4], chest: [-6, -12, 6], neck: [0, 16, -6], head: [0, 20, -10] },
      ik: { handR: { pos: [0.1, 0.95, 0.22], aim: [0.62, 0.7, -0.3], up: [-0.8, 0.5, 0] }, footL: { pos: [0.24, 0, -0.18], rot: [0, 18, 0] }, footR: { pos: [-0.42, 0, 0.12], rot: [0, -48, 0] } } },
    { t: 0.28, ease: 'inOutSine', hips: { pos: [-0.14, -0.3, -0.12], rot: [-5, -40, -5] } },
    { t: 0.42, ease: 'inOutSine', pose: 'demo.stance' },
  ],
});

defineClip('game.hitLight', {
  duration: 0.32, breath: 0.5,
  keys: [
    { t: 0, pose: 'demo.stance' },
    { t: 0.05, ease: 'outQuad', hips: { pos: [-0.07, -0.11, 0.01], rot: [-2, -31, 4] }, bones: { spine: [-2, -9, 8], chest: [-3, -7, 10], neck: [3, 6, 10], head: [4, 8, 16] },
      ik: { handR: { pos: [0.27, 1.1, 0.14], aim: [0.72, 0.6, -0.14] } } },
    { t: 0.32, ease: 'inOutSine', pose: 'demo.stance' },
  ],
});

defineClip('game.crumple', {
  duration: 0.95, breath: 0.2,
  keys: [
    { t: 0, pose: 'demo.stance' },
    { t: 0.07, ease: 'outQuad', hips: { pos: [-0.08, -0.1, 0.01], rot: [-3, -32, 6] }, bones: { spine: [-3, -8, 12], chest: [-4, -6, 14], neck: [4, 6, 16], head: [6, 10, 22] },
      ik: { handR: { pos: [0.24, 1.18, 0.18], aim: [0.5, 0.82, -0.1], up: [-0.8, 0.5, 0] }, ...FEET } },
    { t: 0.4, ease: 'inOutSine', hips: { pos: [-0.06, -0.4, 0], rot: [0, -20, -4] }, bones: { spine: [0, -4, -18], chest: [0, -4, -18], neck: [0, 4, -14], head: [0, 6, -22] },
      ik: { handR: { pos: [0.3, 0.62, 0.22], aim: [0.42, -0.9, 0.05], up: [0.9, 0.42, 0] } }, grip: 0.3 },
    { t: 0.95, ease: 'inQuad', hips: { pos: [-0.1, -0.62, 0], rot: [0, -16, -6] }, bones: { spine: [0, -2, -26], chest: [0, -2, -22], neck: [0, 2, -16], head: [0, 4, -26] },
      ik: { handR: { pos: [0.36, 0.34, 0.24], aim: [0.6, -0.8, 0.05], up: [0.8, 0.6, 0] } }, grip: 0 },
  ],
});

defineClip('game.guardbreak', {
  duration: 1.1, breath: 0.4,
  keys: [
    { t: 0, pose: 'demo.block', grip: 1 },
    { t: 0.08, ease: 'outCubic', hips: { pos: [-0.14, -0.04, 0], rot: [-4, -40, -8] }, bones: { spine: [-4, -12, 14], chest: [-6, -14, 18], neck: [4, 10, 16], head: [6, 14, 24] },
      ik: { handR: { pos: [-0.12, 1.62, 0.36], aim: [-0.55, 0.78, 0.25], up: [0.8, 0.55, 0] }, footL: { pos: [0.24, 0.1, -0.14], rot: [0, 14, -10] } }, grip: 0 },
    { t: 0.3, ease: 'inOutSine', hips: { pos: [-0.12, -0.18, 0], rot: [-2, -36, -4] }, bones: { spine: [-2, -10, 8], chest: [-3, -10, 10], neck: [2, 8, 6], head: [3, 10, 10] },
      ik: { handR: { pos: [0.02, 1.3, 0.34], aim: [-0.2, 0.95, 0.2] }, footL: { pos: [0.22, 0, -0.14], rot: [0, 14, 0] } } },
    { t: 0.75, ease: 'inOutSine', hips: { pos: [-0.08, -0.2, 0], rot: [0, -30, 0] }, bones: { spine: [0, -8, -6], chest: [0, -8, -4], head: [0, 12, -2] },
      ik: { handR: { pos: [0.24, 1.0, 0.16], aim: [0.7, 0.55, -0.15], up: [-0.55, 0.8, 0] } }, grip: 1 },
    { t: 1.1, ease: 'inOutSine', pose: 'demo.stance' },
  ],
});

defineClip('game.airRise', { duration: 0.8, loop: true, breath: 0, keys: [
  { t: 0, pose: 'game.airRisePose', ease: 'inOutSine' },
  { t: 0.4, ease: 'inOutSine', hips: { rot: [0, -20, 36] }, bones: { upperArmL: [-70, 0, 30], head: [4, 12, 22] } },
] });
defineClip('game.airFall', { duration: 0.8, loop: true, breath: 0, keys: [
  { t: 0, pose: 'game.airFallPose', ease: 'inOutSine' },
  { t: 0.4, ease: 'inOutSine', hips: { rot: [0, -10, 70] }, bones: { upperArmL: [-62, 0, 46] } },
] });
defineClip('game.down', { duration: 2.4, loop: true, breath: 1.4, keys: [
  { t: 0, pose: 'game.downPose', ease: 'inOutSine' },
  { t: 1.2, ease: 'inOutSine', bones: { head: [6, 18, -8], thighL: [10, 0, 30], shinL: [0, 0, -58] } },
] });
defineClip('game.koDown', { duration: 3, loop: true, breath: 0.25, keys: [{ t: 0, pose: 'game.koPose' }] });

defineClip('game.getup', {
  duration: 0.45, breath: 0,
  keys: [
    { t: 0, pose: 'game.downPose', ik: { ...NO_FEET, handR: { pos: STANCE_HAND.pos, w: 0 } } },
    { t: 0.2, ease: 'outQuad', hips: { pos: [-0.04, -0.52, 0], rot: [0, -24, 12] }, bones: { spine: [0, -6, -10], chest: [0, -6, -8], neck: [0, 8, 4], head: [0, 12, 0], thighL: [0, 0, 0], shinL: [0, 0, 0], thighR: [0, 0, 0], shinR: [0, 0, 0], upperArmL: [-20, 0, 10], foreArmL: [0, 0, 20] },
      ik: { footL: { pos: [0.3, 0, -0.16], rot: [0, 14, 0], w: 1 }, footR: { pos: [-0.36, 0, 0.17], rot: [0, -45, 0], w: 1 }, handR: { pos: [0.4, 0.62, 0.18], aim: [0.6, -0.78, 0], up: [0.78, 0.6, 0], w: 1 } }, grip: 0.4 },
    { t: 0.45, ease: 'inOutSine', pose: 'demo.stance' },
  ],
});

defineClip('game.intro', {
  duration: 2.1, breath: 0.8,
  keys: [
    // blade planted tip-down in front, both hands on the grip, standing tall, head lowered
    { t: 0, hips: { pos: [-0.02, -0.03, 0], rot: [0, -12, 0] }, bones: { spine: [0, -2, -2], chest: [0, -2, 0], neck: [0, 4, -6], head: [0, 6, -14] },
      ik: { handR: { pos: [0.34, 1.12, 0.04], aim: [0.12, -0.99, -0.04], up: [0.99, 0.12, 0] }, footL: { pos: [0.16, 0, -0.14], rot: [0, 8, 0] }, footR: { pos: [-0.12, 0, 0.15], rot: [0, -30, 0] } }, grip: 1, curl: [1, 1] },
    { t: 0.7, ease: 'inOutSine', bones: { neck: [0, 6, 2], head: [0, 10, 4] } },
    // wrench it free and swing it up
    { t: 1.05, ease: 'inOutSine', hips: { pos: [-0.04, -0.08, 0], rot: [0, -20, 0] },
      ik: { handR: { pos: [0.3, 1.2, 0.08], aim: [0.2, -0.97, -0.05], up: [0.97, 0.2, 0] } } },
    { t: 1.35, ease: 'outCubic', hips: { pos: [-0.06, -0.12, 0], rot: [0, -32, 0] }, bones: { spine: [0, -10, -2], chest: [1, -8, 0] },
      ik: { handR: { pos: [0.06, 1.45, 0.3], aim: [-0.4, 0.88, 0.25], up: [-0.85, -0.45, 0.2] }, footL: { pos: [0.3, 0.06, -0.14], rot: [0, 14, -6] } } },
    { t: 1.75, ease: 'inOutSine', pose: 'demo.stance' },
    { t: 2.1, ease: 'inOutSine', pose: 'demo.low' },
  ],
  events: [{ t: 1.05, name: 'wrench' }, { t: 1.75, name: 'step', data: { foot: 'footL' } }],
});

defineClip('game.victory', {
  duration: 1.6, breath: 1.2,
  keys: [
    { t: 0, pose: 'demo.stance' },
    { t: 0.45, ease: 'outCubic', hips: { pos: [-0.02, -0.04, 0], rot: [0, -16, 0] }, bones: { spine: [0, -4, 6], chest: [0, -6, 10], neck: [0, 4, 6], head: [0, 8, 14], upperArmL: [-16, 6, 4], foreArmL: [0, 0, 18] },
      ik: { handR: { pos: [0.12, 2.02, 0.16], aim: [0.12, 0.99, 0.05], up: [-0.99, 0.12, 0] }, footL: { pos: [0.24, 0, -0.14], rot: [0, 12, 0] }, footR: { pos: [-0.22, 0, 0.16], rot: [0, -38, 0] } }, grip: 0 },
    { t: 1.6, ease: 'inOutSine', bones: { chest: [0, -6, 12], head: [0, 8, 18] }, ik: { handR: { pos: [0.12, 2.04, 0.16] } } },
  ],
});

defineClip('game.defeat', {
  duration: 1.4, breath: 1.6,
  keys: [
    { t: 0, pose: 'demo.stance' },
    { t: 0.9, ease: 'inOutCubic', hips: { pos: [-0.08, -0.5, 0], rot: [0, -22, 0] }, bones: { spine: [0, -4, -18], chest: [0, -4, -14], neck: [0, 2, -12], head: [0, 4, -26], upperArmL: [-14, 0, 30], foreArmL: [0, 0, 50] },
      ik: { handR: { pos: [0.46, 0.7, 0.1], aim: [0.16, -0.98, 0.02], up: [0.98, 0.16, 0] }, footL: { pos: [0.34, 0, -0.14], rot: [0, 14, 0] }, footR: { pos: [-0.42, 0.04, 0.16], rot: [0, -45, -30] } }, grip: 0 },
    { t: 1.4, ease: 'inOutSine', bones: { head: [0, 4, -30] } },
  ],
});

defineClip('game.locked', { duration: 1.2, loop: true, breath: 0.4, keys: [
  { t: 0, pose: 'demo.stance', hips: { pos: [-0.08, -0.16, 0], rot: [-3, -34, 5] }, bones: { spine: [-2, -10, 6], chest: [-3, -9, 8], neck: [2, 8, 6], head: [3, 10, 6] }, ik: { handR: { pos: [0.2, 1.06, 0.2], aim: [0.6, 0.62, -0.12] } } },
  { t: 0.6, ease: 'inOutSine', hips: { pos: [-0.09, -0.18, 0], rot: [-3, -35, 6] } },
] });

// ---------------------------------------------------------------------------------------------------------------
// resolution

/** Generic clip per presentation slot. */
export const GENERIC = {
  idle: 'demo.idle', walkF: 'game.walkF', walkB: 'game.walkB', dash: 'game.dash', backstep: 'game.backstep',
  dodge: 'game.dodge', roll: 'game.dash', guard: 'demo.guard', guardHit: 'demo.guard', guardBreak: 'game.guardbreak',
  hitLight: 'game.hitLight', hitHeavy: 'demo.hit', crumple: 'game.crumple', launched: 'game.airRise', fall: 'game.airFall',
  down: 'game.down', getup: 'game.getup', tech: 'game.getup', ko: 'game.koDown', locked: 'game.locked',
  intro: 'game.intro', victory: 'game.victory', defeat: 'game.defeat', recovery: 'demo.idle',
};

/** Clip time of the first 'hit' (or 'impact') event, else null. */
function impactTime(name) {
  const d = getClipDef(name);
  if (!d || !d.events) return null;
  let t = null;
  for (const e of d.events) if ((e.name === 'hit' || e.name === 'impact') && (t === null || e.t < t)) t = e.t;
  return t;
}

/** Duration of a registered clip (raw definition: `duration` or the last key). */
export function clipDuration(name) {
  const d = getClipDef(name);
  if (!d) return 1;
  if (d.duration) return d.duration;
  let t = 0;
  for (const k of d.keys) t = Math.max(t, k.t || 0);
  return t || 1;
}

/** Root-motion speed of a looping clip (m/s along f), 0 when it has none. */
export function clipRootSpeed(name) {
  const d = getClipDef(name);
  if (!d) return 0;
  let f = 0;
  for (const k of d.keys) if (k.root) { const p = Array.isArray(k.root) ? k.root : k.root.pos; if (p && Math.abs(p[0]) > Math.abs(f)) f = p[0]; }
  return f / clipDuration(name);
}

/** Command key -> MOVES.md slot name. */
const COMMAND_SLOT = { light: 'light1', heavy: 'heavy', 'f+heavy': 'fheavy', 'd+heavy': 'dheavy', skill1: 'skill1', skill2: 'skill2', skill3: 'skill3', ult: 'ult' };

/** MOVES.md slot of a move: meta.slot, else its command key, else its id. */
export function slotOf(compiled, id) {
  const mv = compiled.moves[id];
  if (mv && mv.meta && typeof mv.meta.slot === 'string') return mv.meta.slot;
  for (const k in compiled.commands) if (compiled.commands[k] === id && COMMAND_SLOT[k]) return COMMAND_SLOT[k];
  return id;
}

/** Move id per slot ({ light1: 'rime_flick', ... }) for the moves a fighter has. */
export function slotMoves(compiled) {
  const out = {};
  for (const id in compiled.moves) { const s = slotOf(compiled, id); if (!(s in out)) out[s] = id; }
  return out;
}

/** Pick a fallback demo clip for a move from its data (the content team's clips replace these). */
function fallbackMoveClip(id, mv, fd) {
  const lvl = fd.level || '';
  if (mv.cinematic) return 'demo.slam';
  if (mv.counter) return 'demo.guard';
  const mLight = /^light(\d)/.exec(id);
  if (mLight) return ['demo.combo1', 'demo.combo2', 'demo.combo3'][Math.min(2, Number(mLight[1]) - 1)];
  if (mv.projectiles && mv.projectiles.length) return mv.projectiles.some((p) => p.at === 'opponent') ? 'demo.slam' : 'demo.combo2';
  if (!mv.hits || !mv.hits.length) return 'game.dash';
  if (lvl === 'launch') return 'demo.combo2';
  if (mv.hits.some((h) => h.multiMax > 1) || (mv.armour && mv.armour.length)) return 'demo.combo3';
  if (lvl === 'knockdown') return 'demo.slam';
  if (fd.motion && Math.abs(fd.motion) > 1.5) return 'demo.combo1M';
  return mv.duration > 0.6 ? 'demo.combo3' : 'demo.combo1';
}

/**
 * A fallback clip for a fighter with a weapon in each hand: the generic / demo clips hold a two-handed greatsword (the
 * off hand IKs onto the main weapon's grip), which would glue twin blades together. The variant drops the grip and
 * closes both fists on their own weapons. Defined once per clip.
 * @returns {string} clip name
 */
export function twinVariant(name) {
  const d = getClipDef(name);
  if (!d || !Array.isArray(d.keys)) return name;
  const v = name + '@twin';
  if (!hasClip(v)) defineClip(v, { ...d, keys: d.keys.map((k) => ({ ...k, grip: 0, curl: [1, 1] })) });
  return v;
}

/**
 * Build the clip resolver of one fighter.
 * @param {object} fighter registry fighter ({ clips, def })
 * @param {object} compiled compiled rules definition (match.defs[i])
 * @param {{ twin?: boolean }} [o] twin: the character holds a weapon in each hand (fallback clips use twinVariant)
 * @returns {{ state(slot): {name, speed}, move(id): {name, map(t) -> clip time, fade}, has(slot) }}
 */
export function createClipSet(fighter, compiled, o = {}) {
  const fallback = o.twin ? twinVariant : (n) => n;
  let map = fighter.clips || {};
  if (typeof map === 'function') {
    try { map = map({ defineClip, definePose, hasClip }) || {}; } catch (e) { console.warn('[ed] clips of ' + fighter.id + ' failed: ' + e.message); map = {}; }
  }
  if (map.map && typeof map.map === 'object') map = map.map;
  const entry = (key) => {
    const v = map[key];
    if (!v) return null;
    const o = typeof v === 'string' ? { clip: v } : v;
    if (!o.clip || !hasClip(o.clip)) return null;
    return o;
  };
  const states = {};
  const stats = (compiled && compiled.stats) || {};
  const state = (slot) => {
    if (states[slot]) return states[slot];
    const o = entry(slot);
    const walkDir = slot === 'walkF' ? 1 : slot === 'walkB' ? -1 : 0;
    const name = o ? o.clip : fallback(walkDir ? walkClipFor(walkDir, walkDir > 0 ? stats.walkSpeed : stats.backSpeed)
      : GENERIC[slot] && hasClip(GENERIC[slot]) ? GENERIC[slot] : 'demo.idle');
    return (states[slot] = { name, speed: (o && o.speed) || 1, own: !!o, duration: clipDuration(name), rootSpeed: clipRootSpeed(name) });
  };
  const moves = {};
  const move = (id) => {
    if (moves[id]) return moves[id];
    const mv = compiled.moves[id];
    const slot = slotOf(compiled, id);
    const o = entry(id) || entry(slot);
    let fd;
    try { fd = deriveFrameData(mv); } catch (e) { fd = { startup: mv ? mv.duration * 0.4 : 0.2, level: null }; }
    const dur = mv ? mv.duration : 1;
    const base = o ? o.clip : fallbackMoveClip(slot, mv || {}, fd);
    const name = o ? base : fallback(base);
    const cd = clipDuration(name);
    let impact = o ? (o.hit ?? null) : impactTime(base);
    const startup = fd.startup ?? (mv && mv.markers && mv.markers.length ? mv.markers[mv.markers.length - 1].t : dur * 0.4);
    let mapFn;
    if (o && impact === null) {
      const k = o.speed || 1;
      mapFn = (t) => Math.min(cd, t * k);
    } else {
      if (impact === null) impact = cd * 0.3;
      const s = Math.max(1e-3, Math.min(startup, dur - 1e-3));
      const a = impact / s, b = (cd - impact) / Math.max(1e-3, dur - s);
      mapFn = (t) => (t <= s ? t * a : Math.min(cd, impact + (t - s) * b));
    }
    return (moves[id] = { name, map: mapFn, own: !!o, fade: (o && o.fade) ?? 0.06, startup, frame: fd, slot });
  };
  return { state, move, map, slots: slotMoves(compiled) };
}
