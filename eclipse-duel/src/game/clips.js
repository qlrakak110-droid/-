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
/** Weapon hand while lying on the back (root space: it must not ride the breathing chest): fist on the floor beside
 * the hip, blade flat, pointing toward the feet and out. */
const LYING_HAND = { pos: [0.3, 0.06, 0.46], aim: [0.86, 0.02, 0.5], up: [-0.5, 0, 0.86] };
/** Free hand while lying on the back (root space): on the floor out to the far side, at the waist. */
const LYING_OFF_HAND = { pos: [0.08, 0.05, -0.5] };
/** Weapon hand while airborne: blade trailing along the body. */
const AIR_HAND = { space: 'chest', pos: [0.05, -0.5, 0.36], aim: [-0.5, -0.82, 0.25], up: [0.82, -0.5, 0] };

// lying on the back, head away from the opponent, one knee up, arms out
definePose('game.downPose', {
  hips: { pos: [0.22, -0.9, 0], rot: [0, -8, 84] },
  bones: {
    spine: [0, 0, 4], chest: [0, -4, 6], neck: [0, 10, -6], head: [6, 24, -10],
    thighR: [-8, 0, 8], shinR: [0, 0, -14], footR: [0, 0, -30], thighL: [10, 0, 34], shinL: [0, 0, -64], footL: [0, 0, -10],
  },
  ik: { handR: LYING_HAND, handL: LYING_OFF_HAND },
  grip: 0, curl: [0.5, 1],
});
definePose('game.koPose', {
  hips: { pos: [0.22, -0.91, 0], rot: [0, -4, 87] },
  bones: {
    spine: [2, 0, 2], chest: [2, -2, 3], neck: [0, 18, -2], head: [10, 40, -6],
    thighR: [-12, 0, 2], shinR: [0, 0, -6], footR: [0, 0, -36], thighL: [6, 0, 14], shinL: [0, 0, -26], footL: [0, 0, -30],
  },
  ik: { handR: { ...LYING_HAND, pos: [0.26, 0.06, 0.56] }, handL: { ...LYING_OFF_HAND, pos: [-0.16, 0.05, -0.56] } },
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

// ---------------------------------------------------------------------------------------------------------------
// The neutral reaction / knockdown / movement set (src/fighters/MOTION.md, "Generic clips"). Authored on the knight's
// stance (demo.stance) for a two-handed weapon; heroes override slot by slot. Reactions follow the same beats:
//   impact pose (the frame the hit-stop holds: the head goes first) -> the torso and hips catch up while the head is
//   already coming back -> a recovering step or a rebound past the stance -> settle.
// Clips other modules re-express or reuse keep their names and plain key format (game.guardbreak, game.crumple,
// game.airRise, game.airFall, game.down, game.getup, game.koDown, game.locked, game.hitLight, game.koPose).

/** Foot keys: sole point at f (lift u), toe pitch (deg, + = toes up); `o` adds space / pole / rot overrides. */
const fL = (f = FL[0], u = 0, pitch = 0, o) => ({ pos: [f, u, FL[2]], rot: [0, 14, pitch], ...o });
const fR = (f = FR[0], u = 0, pitch = 0, o) => ({ pos: [f, u, FR[2]], rot: [0, -45, pitch], ...o });
const ORIGIN = { space: 'origin' };
/** Torso channels of a key: hips offset / rotation and the spine chain (degrees, src/char README section 4). */
const body = (pos, rot, spine, chest, neck, head, more) => ({ hips: { pos, rot }, bones: { spine, chest, neck, head, ...more } });
/** Weapon hand lying face-down (root space: it must not ride the breathing chest): fist on the floor beside the head,
 * blade flat, pointing ahead and out. */
const PRONE_HAND = { pos: [0.8, 0.06, 0.62], aim: [0.7, 0, 0.7], up: [0.7, 0, -0.7] };
/** Free hand lying face-down: palm on the floor by the far shoulder. */
const PRONE_OFF_HAND = { pos: [0.9, 0.05, -0.36] };
/** Knees tucked to the chest (rolls). */
const TUCK = { thighR: [0, 0, 112], shinR: [0, 0, -128], footR: [0, 0, -10], thighL: [4, 0, 118], shinL: [0, 0, -134], footL: [0, 0, -10] };

// lying face-down, head toward +f (thrown forward by a blow from behind)
definePose('game.pronePose', {
  hips: { pos: [0.22, -0.9, 0], rot: [0, 6, -84] },
  bones: { spine: [0, 0, 3], chest: [0, 4, 7], neck: [0, -24, 12], head: [4, -46, 8] },
  ik: { handR: PRONE_HAND, handL: PRONE_OFF_HAND, footL: { pos: [-0.6, 0, -0.13], rot: [0, 8, -75] }, footR: { pos: [-0.68, 0, 0.19], rot: [0, -24, -75] } },
  grip: 0, curl: [0.4, 1],
});
// airborne, thrown forward and up: chest leads, back arched, limbs trailing
definePose('game.airRisePronePose', {
  hips: { pos: [0, 0.05, 0], rot: [0, 12, -30] },
  bones: {
    spine: [0, 0, 8], chest: [0, 4, 12], neck: [0, -6, 14], head: [0, -8, 20],
    thighR: [-4, 0, -20], shinR: [0, 0, -44], footR: [0, 0, -30], thighL: [4, 0, 4], shinL: [0, 0, -66], footL: [0, 0, -24],
    upperArmL: [-46, 0, -28], foreArmL: [0, 0, 32],
  },
  ik: { handR: { space: 'chest', pos: [-0.12, -0.42, 0.38], aim: [-0.62, -0.74, 0.26], up: [0.74, -0.62, 0] } },
  grip: 0, curl: [0.4, 1],
});
// airborne, falling face-down: near horizontal, arms coming forward to break the fall
definePose('game.airFallPronePose', {
  hips: { pos: [0.05, -0.25, 0], rot: [0, 8, -66] },
  bones: {
    spine: [0, 0, 6], chest: [0, 2, 8], neck: [0, -10, 16], head: [0, -14, 22],
    thighR: [-4, 0, -16], shinR: [0, 0, -30], footR: [0, 0, -36], thighL: [4, 0, -4], shinL: [0, 0, -52], footL: [0, 0, -30],
    upperArmL: [-30, 0, 96], foreArmL: [0, 0, 56],
  },
  ik: { handR: { space: 'chest', pos: [0.28, 0.22, 0.42], aim: [0.3, 0.8, 0.52], up: [0, -0.55, 0.84] } },
  grip: 0, curl: [0.4, 1],
});

// ---- movement fallbacks ------------------------------------------------------------------------------------------------
defineClip('game.dash', {
  duration: 0.3, breath: 0,
  keys: [
    { t: 0, pose: 'demo.stance' },
    // load the rear leg: a short sink before the push (2 frames)
    { t: 0.035, ease: 'outQuad', ...body([-0.05, -0.17, 0], [0, -24, -3], [0, -6, -10], [0, -6, -8], [0, 8, 8], [0, 12, 10]),
      ik: { handR: { pos: [0.26, 1.0, 0.18], aim: [0.86, 0.38, 0], up: [-0.38, 0.9, 0] }, footL: fL(0.3, 0, 0), footR: fR(-0.3, 0, -14) } },
    // drive: rear leg extended, chest low over the front knee, the blade couched at the hip with its point on the foe
    { t: 0.1, ease: 'outCubic', ...body([0.1, -0.24, 0], [0, -16, -6], [0, -4, -18], [0, -4, -14], [0, 6, 12], [0, 8, 16]),
      ik: { handR: { pos: [0.32, 0.96, 0.14], aim: [0.9, 0.3, 0], up: [-0.3, 0.95, 0] }, footL: fL(0.52, 0.12, -12), footR: fR(-0.46, 0.03, -34) } },
    { t: 0.17, ease: 'inQuad', ik: { footL: fL(0.44, 0, 0) } },
    { t: 0.17, ease: 'inOutSine', ...body([0.12, -0.25, 0], [0, -20, -4], [0, -5, -16], [0, -5, -12], [0, 7, 10], [0, 10, 14]), ik: { handR: { pos: [0.34, 0.97, 0.13], aim: [0.9, 0.32, -0.04] } } },
    // the rear foot is dragged in under the hips, the blade swings forward into the guard
    { t: 0.24, ease: 'inOutSine', ik: { footR: fR(-0.24, 0.05, -10) } },
    { t: 0.3, ease: 'inOutSine', pose: 'demo.stance' },
  ],
  events: [{ t: 0.17, name: 'step', data: { foot: 'footL' } }],
});

defineClip('game.backstep', {
  duration: 0.34, breath: 0,
  keys: [
    { t: 0, pose: 'demo.stance' },
    // push off the front foot: hips back first, chest and blade left behind
    { t: 0.08, ease: 'outQuad', ...body([-0.12, -0.03, 0], [0, -30, 2], [0, -6, 10], [0, -6, 9], [0, 8, -8], [0, 12, -10]),
      ik: { handR: { pos: [0.34, 1.2, 0.12], aim: [0.66, 0.74, -0.1], up: [-0.74, 0.66, 0] }, footL: fL(0.24, 0.13, -18), footR: fR(-0.46, 0.09, -8) } },
    // the rear foot lands first and takes the weight, the front foot follows a beat later
    { t: 0.17, ease: 'inQuad', ik: { footR: fR(-0.4, 0, 0) } },
    { t: 0.2, ease: 'outQuad', ...body([-0.07, -0.22, 0], [0, -28, -2], [0, -6, -8], [0, -6, -5], [0, 8, 4], [0, 12, 4]), ik: { handR: { pos: [0.3, 1.02, 0.14], aim: [0.78, 0.5, -0.14], up: [-0.5, 0.86, 0] } } },
    { t: 0.23, ease: 'inQuad', ik: { footL: fL(0.27, 0, 0) } },
    { t: 0.34, ease: 'inOutSine', pose: 'demo.stance' },
  ],
  events: [{ t: 0.17, name: 'step', data: { foot: 'footR' } }, { t: 0.23, name: 'step', data: { foot: 'footL' } }],
});

defineClip('game.dodge', {
  duration: 0.42, breath: 0,
  keys: [
    { t: 0, pose: 'demo.stance' },
    // slip under and away from the line: the head leaves first, the hips sink onto the rear leg
    { t: 0.08, ease: 'outCubic', ...body([-0.17, -0.36, -0.14], [-7, -46, -6], [-4, -10, 2], [-6, -12, 6], [0, 18, -4], [-4, 22, -8]),
      ik: { handR: { pos: [0.08, 0.92, 0.22], aim: [0.6, 0.72, -0.3], up: [-0.8, 0.5, 0] }, footL: fL(0.25, 0, 0, { pos: [0.25, 0, -0.18] }), footR: fR(-0.42, 0, 0, { pos: [-0.42, 0, 0.12] }) } },
    { t: 0.26, ease: 'inOutSine', ...body([-0.15, -0.31, -0.12], [-6, -42, -5], [-4, -10, 0], [-5, -11, 3], [0, 16, 0], [-2, 20, -2]) },
    // back up through the line with a small overshoot forward
    { t: 0.36, ease: 'inOutSine', ...body([-0.01, -0.11, 0.01], [1, -24, -2], [0, -8, -6], [1, -6, -5], [0, 10, 2], [0, 14, -2]), ik: { handR: { pos: [0.34, 1.06, 0.1], aim: [0.82, 0.42, -0.15], up: [-0.4, 0.86, 0] } } },
    { t: 0.42, ease: 'inOutSine', pose: 'demo.stance' },
  ],
});

// ---- hit reactions (the game starts them on the impact pose: 0.05 light, 0.06 heavy) -------------------------------------
// light, chest height from the front (also the fallback of the height variants)
defineClip('game.hitLight', {
  duration: 0.34, breath: 0.5,
  keys: [
    { t: 0, pose: 'demo.stance' },
    { t: 0.05, ease: 'outQuad', ...body([-0.05, -0.1, 0.01], [-2, -29, 4], [-2, -9, 6], [-3, -6, 9], [3, 6, 14], [5, 8, 22]), ik: { handR: { pos: [0.28, 1.13, 0.14], aim: [0.7, 0.62, -0.14] } } },
    { t: 0.1, ease: 'outQuad', ...body([-0.085, -0.13, 0.012], [-3, -32, 6], [-3, -10, 10], [-4, -8, 13], [2, 8, 5], [3, 11, 4]), ik: { handR: { pos: [0.24, 1.17, 0.17], aim: [0.6, 0.75, -0.12] } } },
    { t: 0.2, ease: 'inOutSine', ...body([-0.045, -0.12, 0], [0, -27, -1], [0, -8, -7], [1, -6, -6], [0, 10, -2], [0, 14, -6]), ik: { handR: { pos: [0.31, 1.05, 0.11], aim: [0.82, 0.4, -0.15] } } },
    { t: 0.34, ease: 'inOutSine', pose: 'demo.stance' },
  ],
});
// high: the head whips back and aside, the shoulders follow
defineClip('game.hitLightHigh', {
  duration: 0.34, breath: 0.5,
  keys: [
    { t: 0, pose: 'demo.stance' },
    { t: 0.05, ease: 'outQuad', ...body([-0.03, -0.095, 0.012], [-2, -27, 2], [-1, -8, 3], [-3, -5, 8], [6, 2, 20], [9, 4, 30]), ik: { handR: { pos: [0.3, 1.14, 0.13], aim: [0.72, 0.62, -0.16] } } },
    { t: 0.1, ease: 'outQuad', ...body([-0.075, -0.125, 0.015], [-3, -31, 5], [-3, -10, 9], [-5, -8, 14], [3, 7, 6], [4, 11, 2]), ik: { handR: { pos: [0.25, 1.2, 0.17], aim: [0.56, 0.8, -0.12] } } },
    { t: 0.2, ease: 'inOutSine', ...body([-0.04, -0.12, 0], [0, -27, -1], [0, -8, -6], [1, -6, -6], [-1, 10, -4], [-2, 14, -10]), ik: { handR: { pos: [0.31, 1.06, 0.11], aim: [0.82, 0.42, -0.15] } } },
    { t: 0.34, ease: 'inOutSine', pose: 'demo.stance' },
  ],
});
// mid: folds around the blow (hips shoved back, shoulders round), the head stays up for a beat, then drops
defineClip('game.hitLightMid', {
  duration: 0.34, breath: 0.5,
  keys: [
    { t: 0, pose: 'demo.stance' },
    { t: 0.05, ease: 'outQuad', ...body([-0.1, -0.12, 0], [0, -24, -5], [0, -6, -13], [0, -4, -11], [0, 8, 6], [0, 12, 10], { shoulderR: [0, 10, 0], shoulderL: [0, 10, 0] }), ik: { handR: { pos: [0.3, 1.0, 0.12], aim: [0.84, 0.32, -0.12] } } },
    { t: 0.1, ease: 'outQuad', ...body([-0.14, -0.16, 0], [0, -22, -9], [0, -6, -19], [0, -4, -15], [0, 8, -6], [0, 12, -12], { shoulderR: [0, 12, 0], shoulderL: [0, 12, 0] }), ik: { handR: { pos: [0.27, 0.94, 0.13], aim: [0.88, 0.18, -0.12] } } },
    { t: 0.21, ease: 'inOutSine', ...body([-0.05, -0.1, 0], [0, -26, 1], [0, -8, -1], [1, -6, 0], [0, 10, 3], [0, 14, 2], { shoulderR: [0, 0, 0], shoulderL: [0, 0, 0] }), ik: { handR: { pos: [0.33, 1.09, 0.1], aim: [0.8, 0.47, -0.15] } } },
    { t: 0.34, ease: 'inOutSine', pose: 'demo.stance' },
  ],
});
// low: the front leg is knocked back, the hips drop over it, the upper body pitches forward to keep balance
defineClip('game.hitLightLow', {
  duration: 0.34, breath: 0.5,
  keys: [
    { t: 0, pose: 'demo.stance' },
    { t: 0.05, ease: 'outQuad', ...body([0, -0.15, -0.02], [3, -22, -5], [2, -6, -10], [2, -4, -8], [0, 10, 5], [0, 14, 6]), ik: { handR: { pos: [0.36, 1.0, 0.12], aim: [0.86, 0.26, -0.15] }, footL: fL(0.23, 0.035, -12) } },
    { t: 0.11, ease: 'inQuad', ik: { footL: fL(0.19, 0, 0) } },
    { t: 0.11, ease: 'outQuad', ...body([0.02, -0.21, -0.03], [5, -20, -8], [3, -6, -14], [3, -4, -10], [0, 10, 2], [0, 14, 2]), ik: { handR: { pos: [0.38, 0.94, 0.14], aim: [0.9, 0.12, -0.15] } } },
    { t: 0.22, ease: 'inOutSine', ...body([-0.03, -0.12, 0], [0, -25, 0], [0, -8, -3], [1, -6, -2], [0, 10, 2], [0, 14, -2]), ik: { handR: { pos: [0.33, 1.07, 0.1], aim: [0.8, 0.45, -0.15] }, footL: fL(0.19, 0, 0) } },
    { t: 0.29, ease: 'outQuad', ik: { footL: fL(0.26, 0.04, -6) } },
    { t: 0.34, ease: 'inQuad', ik: { footL: fL(0.3, 0, 0) } },
    { t: 0.34, ease: 'inOutSine', pose: 'demo.stance' },
  ],
  events: [{ t: 0.11, name: 'step', data: { foot: 'footL' } }],
});
// from behind: the back arches (head left behind), then a stumbling step forward
defineClip('game.hitLightBack', {
  duration: 0.36, breath: 0.5,
  keys: [
    { t: 0, pose: 'demo.stance' },
    { t: 0.05, ease: 'outQuad', ...body([0.05, -0.085, 0], [0, -24, -3], [0, -8, 8], [0, -6, 11], [0, 8, 12], [0, 10, 22]), ik: { handR: { pos: [0.4, 1.14, 0.1], aim: [0.74, 0.62, -0.2] } } },
    { t: 0.11, ease: 'outQuad', ...body([0.1, -0.14, 0], [0, -22, -9], [0, -8, -10], [0, -6, -11], [0, 8, -8], [0, 12, -14]), ik: { handR: { pos: [0.43, 0.98, 0.1], aim: [0.88, 0.2, -0.16] }, footL: fL(0.36, 0.05, -8) } },
    { t: 0.18, ease: 'inQuad', ik: { footL: fL(0.42, 0, 0) } },
    { t: 0.24, ease: 'inOutSine', ...body([0.06, -0.14, 0], [0, -25, -3], [0, -8, -6], [1, -6, -4], [0, 10, 2], [0, 14, 0]), ik: { handR: { pos: [0.38, 1.04, 0.1], aim: [0.82, 0.4, -0.15] }, footL: fL(0.42, 0, 0) } },
    { t: 0.31, ease: 'outQuad', ik: { footL: fL(0.35, 0.035, -4) } },
    { t: 0.36, ease: 'inQuad', ik: { footL: fL(0.3, 0, 0) } },
    { t: 0.36, ease: 'inOutSine', pose: 'demo.stance' },
  ],
  events: [{ t: 0.18, name: 'step', data: { foot: 'footL' } }],
});

// heavy from the front: the head and the blade are thrown back, the body is driven over the rear leg, the rear foot
// catches it (a stagger step), the front foot drags after, then a braced lean back into the guard
defineClip('game.hitHeavy', {
  duration: 0.85, breath: 0.6,
  keys: [
    { t: 0, pose: 'demo.stance', root: { pos: [0, 0] }, ik: { footL: fL(0.3, 0, 0, ORIGIN), footR: fR(-0.3, 0, 0, ORIGIN) } },
    { t: 0.06, ease: 'outQuad', ...body([-0.11, -0.11, 0.015], [-5, -36, 8], [-4, -11, 13], [-6, -9, 17], [5, 5, 18], [8, 8, 28], { shoulderR: [0, 0, 6], shoulderL: [0, 0, 6] }),
      ik: { handR: { pos: [0.16, 1.26, 0.22], aim: [0.42, 0.88, -0.08], up: [-0.88, 0.42, 0] }, footL: fL(0.3, 0, 0, ORIGIN), footR: fR(-0.3, 0, 0, ORIGIN) } },
    { t: 0.13, ease: 'outQuad', ...body([-0.14, -0.17, 0.02], [-4, -40, 6], [-3, -12, 10], [-5, -11, 14], [2, 8, 4], [3, 12, 2], { shoulderR: [0, 0, 2], shoulderL: [0, 0, 2] }),
      ik: { handR: { pos: [0.12, 1.2, 0.25], aim: [0.36, 0.9, -0.05] }, footR: fR(-0.44, 0.07, 8, ORIGIN) } },
    { t: 0.14, root: { pos: [-0.14, 0] } },
    { t: 0.24, ease: 'inQuad', ik: { footR: fR(-0.56, 0, 0, ORIGIN) } },
    { t: 0.3, ease: 'inOutSine', ...body([-0.1, -0.2, 0.01], [-1, -34, -2], [0, -10, -6], [0, -9, -5], [0, 10, 2], [0, 14, 0], { shoulderR: [0, 0, 0], shoulderL: [0, 0, 0] }),
      ik: { handR: { pos: [0.22, 1.02, 0.2], aim: [0.66, 0.55, -0.12], up: [-0.55, 0.83, 0] }, footL: fL(0.3, 0, 0, ORIGIN) } },
    { t: 0.42, ease: 'outQuad', ik: { footL: fL(0.15, 0.03, -8, ORIGIN) } },
    { t: 0.5, ease: 'inQuad', ik: { footL: fL(0.06, 0, 0, ORIGIN) } },
    { t: 0.55, root: { pos: [-0.24, 0] } },
    { t: 0.62, ease: 'inOutSine', ...body([-0.04, -0.13, 0], [0, -28, -1], [0, -9, -6], [1, -7, -5], [0, 10, 0], [0, 14, -4]), ik: { handR: { pos: [0.3, 1.06, 0.12], aim: [0.8, 0.45, -0.15], up: [-0.4, 0.86, 0] } } },
    { t: 0.85, ease: 'inOutSine', pose: 'demo.stance', ik: { footL: fL(0.06, 0, 0, ORIGIN), footR: fR(-0.54, 0, 0, ORIGIN) } },
    { t: 0.85, root: { pos: [-0.24, 0] } },
  ].sort((a, b) => a.t - b.t),
  events: [{ t: 0.24, name: 'step', data: { foot: 'footR' } }, { t: 0.5, name: 'step', data: { foot: 'footL' } }],
});
// heavy from behind: arched, pitched forward over the front foot, two stumbling steps, caught bent double
defineClip('game.hitHeavyBack', {
  duration: 0.85, breath: 0.6,
  keys: [
    { t: 0, pose: 'demo.stance', root: { pos: [0, 0] }, ik: { footL: fL(0.3, 0, 0, ORIGIN), footR: fR(-0.3, 0, 0, ORIGIN) } },
    { t: 0.06, ease: 'outQuad', ...body([0.05, -0.08, 0], [0, -22, -4], [0, -6, 10], [0, -4, 14], [0, 6, 14], [0, 8, 24]),
      ik: { handR: { pos: [0.44, 1.2, 0.08], aim: [0.75, 0.62, -0.2], up: [-0.62, 0.78, 0] }, footL: fL(0.3, 0, 0, ORIGIN), footR: fR(-0.3, 0, 0, ORIGIN) } },
    { t: 0.14, ease: 'outQuad', ...body([0.06, -0.14, 0], [0, -18, -12], [0, -6, -14], [0, -4, -16], [0, 6, -8], [0, 10, -16]),
      ik: { handR: { pos: [0.5, 0.96, 0.1], aim: [0.9, 0.1, -0.2], up: [-0.1, 0.98, 0] }, footL: fL(0.44, 0.08, -10, ORIGIN) } },
    { t: 0.16, root: { pos: [0.12, 0] } },
    { t: 0.24, ease: 'inQuad', ik: { footL: fL(0.62, 0, 0, ORIGIN) } },
    { t: 0.32, ease: 'inOutSine', ...body([0.04, -0.22, 0], [0, -16, -16], [0, -6, -18], [0, -4, -14], [0, 8, -2], [0, 12, -6]),
      ik: { handR: { pos: [0.5, 0.86, 0.12], aim: [0.92, -0.1, -0.2] }, footR: fR(-0.3, 0, -10, ORIGIN) } },
    { t: 0.44, ease: 'outQuad', ik: { footR: fR(-0.14, 0.07, -16, ORIGIN) } },
    { t: 0.54, ease: 'inQuad', ik: { footR: fR(0, 0, 0, ORIGIN) } },
    { t: 0.55, root: { pos: [0.3, 0] } },
    { t: 0.64, ease: 'inOutSine', ...body([-0.01, -0.14, 0], [0, -24, -4], [0, -8, -8], [1, -6, -6], [0, 10, 2], [0, 14, 0]), ik: { handR: { pos: [0.36, 1.02, 0.1], aim: [0.84, 0.36, -0.15], up: [-0.4, 0.86, 0] } } },
    { t: 0.85, ease: 'inOutSine', pose: 'demo.stance', ik: { footL: fL(0.6, 0, 0, ORIGIN), footR: fR(0, 0, 0, ORIGIN) } },
    { t: 0.85, root: { pos: [0.3, 0] } },
  ].sort((a, b) => a.t - b.t),
  events: [{ t: 0.24, name: 'step', data: { foot: 'footL' } }, { t: 0.54, name: 'step', data: { foot: 'footR' } }],
});

// crumple (progress-driven over the stun): a rigid jolt around the blow, the blade point drops to the floor, the rear
// knee gives and he sits back onto the heel, then topples onto his back with the legs shooting out from under him
// (it ends on game.downPose: the knockdown that follows lies on the back)
defineClip('game.crumple', {
  duration: 0.95, breath: 0.2,
  keys: [
    { t: 0, pose: 'demo.stance' },
    { t: 0.07, ease: 'outQuad', ...body([-0.1, -0.13, 0], [0, -22, -8], [0, -6, -18], [0, -4, -14], [0, 8, 10], [0, 12, 16], { shoulderR: [-8, 8, 0], shoulderL: [-8, 8, 0] }),
      ik: { handR: { pos: [0.3, 1.0, 0.14], aim: [0.8, 0.4, -0.1], up: [-0.4, 0.9, 0] }, ...FEET } },
    { t: 0.3, ease: 'inOutSine', ...body([-0.08, -0.2, 0.01], [2, -20, -10], [2, -6, -22], [2, -4, -18], [0, 6, -6], [0, 10, -14], { shoulderR: [0, 6, 0], shoulderL: [0, 6, 0] }),
      ik: { handR: { pos: [0.38, 0.8, 0.16], aim: [0.86, -0.5, 0.05], up: [0.5, 0.86, 0] } }, grip: 0.5 },
    { t: 0.56, ease: 'inOutSine', ...body([-0.2, -0.6, 0.01], [0, -18, -4], [0, -4, -16], [0, -2, -12], [0, 4, -6], [0, 6, -14], { shoulderR: [0, 0, 0], shoulderL: [0, 0, 0], upperArmL: [-20, 0, 10], foreArmL: [0, 0, 30] }),
      ik: { handR: { pos: [0.34, 0.5, 0.2], aim: [0.94, -0.3, 0.16], up: [0.3, 0.95, 0] }, handL: { ...LYING_OFF_HAND, w: 0 }, footL: fL(0.3, 0, 0), footR: { pos: [-0.38, 0, 0.17], rot: [0, -36, -60], pole: [0.2, 0, 0.3] } }, grip: 0 },
    { t: 0.8, ease: 'inQuad', hips: { pos: [0, -0.8, 0], rot: [0, -10, 44] }, bones: { spine: [0, 0, -8], chest: [0, -2, -6], neck: [0, 6, -12], head: [2, 12, -16], upperArmL: [-40, 0, 30], foreArmL: [0, 0, 40] },
      ik: { handR: { pos: [0.24, 0.1, 0.44], aim: [0.92, 0.02, 0.38], up: [-0.38, 0, 0.92] }, handL: { ...LYING_OFF_HAND, pos: [0.0, 0.12, -0.46], w: 1 }, footL: { pos: [0.66, 0.03, -0.15], rot: [0, 10, 24] }, footR: { pos: [0.5, 0.02, 0.18], rot: [0, -20, 16] } } },
    { t: 0.95, ease: 'inQuad', pose: 'game.downPose', ik: { ...NO_FEET } },
  ],
});

// guard break (progress-driven): the guard is smashed open (blade and left arm flung apart, chest bare, head back),
// two reeling steps, then the guard is hauled back together
defineClip('game.guardbreak', {
  duration: 1.1, breath: 0.4,
  keys: [
    { t: 0, pose: 'demo.block', grip: 1 },
    { t: 0.08, ease: 'outCubic', ...body([-0.14, -0.05, 0], [-4, -42, -8], [-4, -12, 14], [-6, -14, 18], [4, 10, 16], [6, 14, 26], { upperArmL: [-62, 0, 14], foreArmL: [0, 0, 28] }),
      ik: { handR: { pos: [-0.1, 1.6, 0.44], aim: [-0.5, 0.74, 0.45], up: [0.8, 0.55, 0] }, footL: fL(0.25, 0.1, -12), footR: fR(-0.34, 0, 0) }, grip: 0 },
    { t: 0.22, ease: 'inQuad', ik: { footL: fL(0.2, 0, 0) } },
    { t: 0.3, ease: 'inOutSine', ...body([-0.13, -0.19, 0], [-2, -38, -4], [-2, -10, 8], [-3, -10, 10], [2, 8, 4], [3, 10, 4], { upperArmL: [-40, 0, 8], foreArmL: [0, 0, 40] }),
      ik: { handR: { pos: [0, 1.32, 0.34], aim: [-0.22, 0.95, 0.2], up: [0.95, 0.22, 0] }, footR: fR(-0.34, 0, 0) } },
    { t: 0.4, ease: 'outQuad', ik: { footR: fR(-0.42, 0.06, 6) } },
    { t: 0.5, ease: 'inQuad', ik: { footR: fR(-0.46, 0, 0) } },
    { t: 0.75, ease: 'inOutSine', ...body([-0.09, -0.21, 0], [0, -31, 0], [0, -8, -8], [0, -8, -6], [0, 10, -4], [0, 12, -8], { upperArmL: [-24, 0, 12], foreArmL: [0, 0, 44] }),
      ik: { handR: { pos: [0.22, 0.98, 0.17], aim: [0.7, 0.5, -0.15], up: [-0.5, 0.84, 0] }, footL: fL(0.2, 0, 0), footR: fR(-0.46, 0, 0) }, grip: 0.4 },
    { t: 0.9, ease: 'outQuad', ik: { footL: fL(0.27, 0.04, -4), footR: fR(-0.38, 0, 0) } },
    { t: 1.1, ease: 'inOutSine', pose: 'demo.stance', grip: 1 },
  ],
  events: [{ t: 0.22, name: 'step', data: { foot: 'footL' } }, { t: 0.5, name: 'step', data: { foot: 'footR' } }],
});

// blocked hits (from the guard pose): the blade is driven toward the face, the elbows give, the rear knee takes it
defineClip('game.guardHit', {
  duration: 0.24, breath: 0.4, gripAt: 'blade',
  keys: [
    { t: 0, pose: 'demo.block' },
    { t: 0.04, ease: 'outQuad', ...body([-0.085, -0.17, 0], [0, -31, 2], [0, -6, -7], [2, -8, -3], [0, 12, 10], [0, 18, 6]), ik: { handR: { pos: [0.25, 1.05, 0.17], aim: [0.2, 0.92, -0.34] } } },
    { t: 0.12, ease: 'inOutSine', ...body([-0.05, -0.155, 0], [0, -30, -1], [0, -6, -11], [2, -8, -7], [0, 12, 7], [0, 18, 1]), ik: { handR: { pos: [0.31, 1.01, 0.16], aim: [0.3, 0.87, -0.39] } } },
    { t: 0.24, ease: 'inOutSine', pose: 'demo.block' },
  ],
});
defineClip('game.guardHitHeavy', {
  duration: 0.36, breath: 0.4, gripAt: 'blade',
  keys: [
    { t: 0, pose: 'demo.block' },
    { t: 0.05, ease: 'outQuad', ...body([-0.13, -0.2, 0.01], [-2, -34, 5], [-2, -8, -2], [0, -10, 4], [2, 12, 12], [3, 18, 10]),
      ik: { handR: { pos: [0.19, 1.1, 0.19], aim: [0.1, 0.96, -0.26] }, footR: fR(-0.34, 0, 0, { pos: [-0.34, 0, 0.18], rot: [0, -48, 0] }) } },
    { t: 0.12, ease: 'outQuad', ...body([-0.15, -0.24, 0.01], [-1, -35, 3], [-1, -8, -6], [1, -10, -1], [0, 12, 6], [0, 18, 2]), ik: { handR: { pos: [0.2, 1.06, 0.19], aim: [0.16, 0.94, -0.3] }, footR: { pos: [-0.4, 0.04, 0.18], rot: [0, -48, 6] } } },
    { t: 0.19, ease: 'inQuad', ik: { footR: { pos: [-0.43, 0, 0.18], rot: [0, -48, 0] } } },
    { t: 0.26, ease: 'inOutSine', ...body([-0.05, -0.16, 0], [0, -30, -2], [0, -6, -13], [2, -8, -9], [0, 12, 6], [0, 18, 0]), ik: { handR: { pos: [0.32, 1.0, 0.16], aim: [0.32, 0.86, -0.4] } } },
    { t: 0.36, ease: 'inOutSine', pose: 'demo.block', ik: { footR: { pos: [-0.34, 0, 0.18], rot: [0, -48, 0] } } },
  ],
  events: [{ t: 0.19, name: 'step', data: { foot: 'footR' } }],
});

// ---- airborne / lying: on the back (struck from the front) and face-down (struck from behind) -----------------------------
defineClip('game.airRise', { duration: 0.8, loop: true, breath: 0, keys: [
  { t: 0, pose: 'game.airRisePose', ease: 'inOutSine' },
  { t: 0.4, ease: 'inOutSine', hips: { rot: [0, -20, 38] }, bones: { upperArmL: [-72, 0, 32], head: [4, 12, 24], thighR: [-6, 0, 12], shinR: [0, 0, -58], thighL: [6, 0, 42], shinL: [0, 0, -60] } },
] });
defineClip('game.airFall', { duration: 0.8, loop: true, breath: 0, keys: [
  { t: 0, pose: 'game.airFallPose', ease: 'inOutSine' },
  { t: 0.4, ease: 'inOutSine', hips: { rot: [0, -10, 72] }, bones: { upperArmL: [-64, 0, 48], thighR: [-4, 0, 38], shinR: [0, 0, -28], thighL: [8, 0, 40], shinL: [0, 0, -66] } },
] });
defineClip('game.airRiseProne', { duration: 0.8, loop: true, breath: 0, keys: [
  { t: 0, pose: 'game.airRisePronePose', ease: 'inOutSine' },
  { t: 0.4, ease: 'inOutSine', hips: { rot: [0, 14, -36] }, bones: { upperArmL: [-54, 0, -36], head: [0, -8, 26], thighR: [-4, 0, -26], shinR: [0, 0, -34], thighL: [4, 0, 10], shinL: [0, 0, -74] } },
] });
defineClip('game.airFallProne', { duration: 0.8, loop: true, breath: 0, keys: [
  { t: 0, pose: 'game.airFallPronePose', ease: 'inOutSine' },
  { t: 0.4, ease: 'inOutSine', hips: { rot: [0, 6, -72] }, bones: { upperArmL: [-34, 0, 106], thighR: [-4, 0, -10], shinR: [0, 0, -40], thighL: [4, 0, -10], shinL: [0, 0, -40] } },
] });
defineClip('game.down', { duration: 2.4, loop: true, breath: 1.4, keys: [
  { t: 0, pose: 'game.downPose', ease: 'inOutSine' },
  { t: 1.2, ease: 'inOutSine', bones: { head: [6, 18, -8], thighL: [10, 0, 30], shinL: [0, 0, -58], chest: [0, -4, 8] } },
] });
defineClip('game.downProne', { duration: 2.4, loop: true, breath: 1.4, keys: [
  { t: 0, pose: 'game.pronePose', ease: 'inOutSine' },
  { t: 1.2, ease: 'inOutSine', bones: { chest: [0, 4, 10], neck: [0, -22, 14], head: [4, -40, 10] }, ik: { handL: { pos: [0.87, 0.05, -0.38] } } },
] });
defineClip('game.koDown', { duration: 3, loop: true, breath: 0.25, keys: [{ t: 0, pose: 'game.koPose' }] });
defineClip('game.koProne', { duration: 3, loop: true, breath: 0.25, keys: [
  { t: 0, pose: 'game.pronePose', bones: { spine: [0, 0, 1], chest: [0, 4, 3], neck: [0, -28, 6], head: [6, -52, 2] },
    ik: { handR: { pos: [0.95, 0.06, 0.42], aim: [1, 0, 0], up: [0, 0, -1] }, handL: { pos: [0.8, 0.05, -0.48] }, footL: { pos: [-0.62, 0, -0.16], rot: [0, 16, -78] }, footR: { pos: [-0.7, 0, 0.21], rot: [0, -30, -78] } } },
] });

// get-up from the back (progress-driven): rocks forward (legs tuck, the head leads), onto the feet in a low crouch, rises
defineClip('game.getup', {
  duration: 0.45, breath: 0,
  keys: [
    { t: 0, pose: 'game.downPose', ik: { ...NO_FEET } },
    { t: 0.1, ease: 'outQuad', hips: { pos: [0.12, -0.74, 0], rot: [0, -14, 46] }, bones: { spine: [0, -2, -16], chest: [0, -4, -18], neck: [0, 6, -10], head: [0, 10, -8], thighL: [4, 0, 96], shinL: [0, 0, -112], thighR: [-4, 0, 78], shinR: [0, 0, -100], upperArmL: [-30, 0, 24], foreArmL: [0, 0, 50] },
      ik: { handR: { pos: [0.34, 0.3, 0.38], aim: [0.95, -0.18, 0.26], up: [0.18, 0.98, 0] }, handL: { ...LYING_OFF_HAND, w: 0 } } },
    { t: 0.22, ease: 'outQuad', hips: { pos: [-0.04, -0.5, 0], rot: [0, -24, 8] }, bones: { spine: [0, -6, -14], chest: [0, -6, -10], neck: [0, 8, 6], head: [0, 12, 4], thighL: [0, 0, 0], shinL: [0, 0, 0], thighR: [0, 0, 0], shinR: [0, 0, 0], upperArmL: [-20, 0, 10], foreArmL: [0, 0, 20] },
      ik: { footL: { pos: [0.3, 0, -0.16], rot: [0, 14, 0], w: 1 }, footR: { pos: [-0.36, 0, 0.17], rot: [0, -45, 0], w: 1 }, handR: { pos: [0.4, 0.62, 0.18], aim: [0.92, -0.38, 0.05], up: [0.38, 0.92, 0] } }, grip: 0.4 },
    { t: 0.45, ease: 'inOutSine', pose: 'demo.stance' },
  ],
});
// get-up from face-down (progress-driven): pushes up (hips first, knees under), the front foot steps through, rises
defineClip('game.getupProne', {
  duration: 0.45, breath: 0,
  keys: [
    { t: 0, pose: 'game.pronePose' },
    { t: 0.15, ease: 'outQuad', hips: { pos: [0.02, -0.5, 0], rot: [0, -12, -46] }, bones: { spine: [0, -4, -12], chest: [0, -4, 2], neck: [0, 6, 22], head: [0, 10, 26] },
      ik: { handR: { pos: [0.5, 0.22, 0.24], aim: [0.88, 0.02, 0.46], up: [0.2, 0.9, -0.38] }, handL: { pos: [0.46, 0.1, -0.22] },
        footL: { pos: [-0.3, 0, -0.14], rot: [0, 14, -60] }, footR: { pos: [-0.44, 0, 0.17], rot: [0, -30, -60] } } },
    { t: 0.22, ease: 'outQuad', ik: { footL: { pos: [0.04, 0.09, -0.14], rot: [0, 14, -24] } } },
    { t: 0.3, ease: 'inQuad', ik: { footL: { pos: [0.3, 0, -0.14], rot: [0, 14, 0] } } },
    { t: 0.3, ease: 'inOutSine', hips: { pos: [-0.04, -0.3, 0], rot: [0, -22, -14] }, bones: { spine: [0, -6, -12], chest: [0, -6, -6], neck: [0, 8, 8], head: [0, 12, 8] },
      ik: { handR: { pos: [0.36, 0.84, 0.14], aim: [0.82, 0.3, -0.1], up: [-0.3, 0.9, 0] }, handL: { pos: [0.3, 0.6, -0.2], w: 0 }, footR: { pos: [-0.34, 0, 0.17], rot: [0, -45, -24] } }, grip: 0.6 },
    { t: 0.45, ease: 'inOutSine', pose: 'demo.stance' },
  ],
  events: [{ t: 0.3, name: 'step', data: { foot: 'footL' } }],
});
// tech (progress-driven; the rules roll him away from the opponent): a backward roll over the shoulders from the back
// landing, feet under him in a crouch, up into the guard
defineClip('game.tech', {
  duration: 0.45, breath: 0,
  keys: [
    { t: 0, pose: 'game.downPose', ik: { ...NO_FEET } },
    { t: 0.1, hips: { pos: [0.12, -0.66, 0], rot: [0, -8, 150] }, bones: { spine: [0, 0, -22], chest: [0, -2, -22], neck: [0, 4, -28], head: [0, 8, -22], ...TUCK, upperArmL: [-30, 0, 40], foreArmL: [0, 0, 90] },
      ik: { handR: { space: 'chest', pos: [0.2, -0.24, 0.36], aim: [0, 0, 1], up: [0, 1, 0] }, handL: { ...LYING_OFF_HAND, w: 0 } } },
    { t: 0.2, hips: { pos: [-0.02, -0.56, 0], rot: [0, -12, 238] }, bones: { spine: [0, -2, -24], chest: [0, -4, -20], neck: [0, 6, -16], head: [0, 8, -8], ...TUCK },
      ik: { ...NO_FEET, handR: { space: 'chest', pos: [0.2, -0.24, 0.36], aim: [0, 0, 1], up: [0, 1, 0] } } },
    { t: 0.3, ease: 'outQuad', hips: { pos: [-0.06, -0.4, 0], rot: [0, -20, 330] }, bones: { spine: [0, -6, -10], chest: [0, -6, -4], neck: [0, 8, 16], head: [0, 12, 20], upperArmL: [-20, 0, 10], foreArmL: [0, 0, 20] },
      ik: { footL: { pos: [0.24, 0, -0.14], rot: [0, 14, 0], w: 1 }, footR: { pos: [-0.34, 0, 0.17], rot: [0, -45, -30], w: 1 }, handR: { pos: [0.34, 0.78, 0.2], aim: [0.9, 0.3, 0.1], up: [-0.3, 0.95, 0] } }, grip: 0.3 },
    { t: 0.45, ease: 'inOutSine', pose: 'demo.stance', hips: { pos: [-0.03, -0.09, 0], rot: [0, -26, 360] } },
  ],
  events: [{ t: 0.3, name: 'step', data: { foot: 'footL' } }],
});
// tech from a face-down landing: a forward shoulder roll, the feet swing over and land ahead, up into the guard
defineClip('game.techProne', {
  duration: 0.45, breath: 0,
  keys: [
    { t: 0, pose: 'game.pronePose' },
    { t: 0.1, hips: { pos: [0.3, -0.5, 0], rot: [0, 6, -150] }, bones: { spine: [0, 0, -22], chest: [0, 2, -22], neck: [0, -4, -28], head: [0, -8, -22], ...TUCK, upperArmL: [-20, 0, 40], foreArmL: [0, 0, 110] },
      ik: { handR: { space: 'chest', pos: [0.2, -0.24, 0.36], aim: [0, 0, 1], up: [0, 1, 0] }, handL: { pos: [0.6, 0.2, -0.3], w: 0 }, ...NO_FEET } },
    { t: 0.2, hips: { pos: [0.16, -0.56, 0], rot: [0, 0, -246] }, bones: { spine: [0, -2, -24], chest: [0, -4, -20], neck: [0, 6, -18], head: [0, 8, -10], ...TUCK },
      ik: { ...NO_FEET, handR: { space: 'chest', pos: [0.2, -0.24, 0.36], aim: [0, 0, 1], up: [0, 1, 0] } } },
    { t: 0.31, ease: 'outQuad', hips: { pos: [-0.08, -0.52, 0], rot: [0, -18, -332] }, bones: { spine: [0, -6, -16], chest: [0, -6, -12], neck: [0, 8, 2], head: [0, 12, 4], upperArmL: [-20, 0, 10], foreArmL: [0, 0, 20] },
      ik: { footL: { pos: [0.32, 0, -0.14], rot: [0, 14, 0], w: 1 }, footR: { pos: [-0.2, 0, 0.17], rot: [0, -45, -20], w: 1 }, handR: { pos: [0.36, 0.78, 0.2], aim: [0.9, 0.3, 0.1], up: [-0.3, 0.95, 0] } }, grip: 0.3 },
    { t: 0.45, ease: 'inOutSine', pose: 'demo.stance', hips: { pos: [-0.03, -0.09, 0], rot: [0, -26, -360] } },
  ],
  events: [{ t: 0.31, name: 'step', data: { foot: 'footL' } }],
});

// locked victim (default lock choreography): reeling on the rear leg, guard hanging open, the head lolling with each sway
defineClip('game.locked', { duration: 1.2, loop: true, breath: 0.6, keys: [
  { t: 0, pose: 'demo.stance', ease: 'inOutSine', ...body([-0.09, -0.17, 0], [-3, -35, 5], [-2, -10, 7], [-3, -9, 9], [2, 8, 6], [4, 10, 8]), ik: { handR: { pos: [0.2, 1.02, 0.22], aim: [0.62, 0.56, -0.1], up: [-0.56, 0.82, 0] }, footL: fL(0.27, 0, 0), footR: fR(-0.36, 0, 0) }, grip: 0.6 },
  { t: 0.5, ease: 'inOutSine', ...body([-0.11, -0.2, 0.012], [-4, -37, 7], [-3, -10, 9], [-4, -9, 11], [3, 6, 2], [6, 6, -4]), ik: { handR: { pos: [0.17, 0.96, 0.25], aim: [0.6, 0.5, -0.06] } } },
  { t: 0.86, ease: 'inOutSine', ...body([-0.085, -0.165, -0.004], [-2, -34, 4], [-2, -10, 5], [-3, -9, 7], [1, 9, 8], [2, 12, 10]), ik: { handR: { pos: [0.21, 1.03, 0.21], aim: [0.63, 0.58, -0.1] } } },
] });

// ---- ceremony / life fallbacks -------------------------------------------------------------------------------------------
// turn-around settle (played in the new facing while the root spins in): the eyes are already on the opponent, the
// chest and the blade arrive late and overshoot, the feet re-plant one after the other
defineClip('game.turn', {
  duration: 0.36, breath: 0.4,
  keys: [
    { t: 0, pose: 'demo.stance', ...body([-0.07, -0.15, 0.02], [0, -62, 0], [0, -14, -4], [2, -14, -3], [0, 26, 2], [0, 34, -2]), ik: { handR: { pos: [0.16, 1.02, 0.3], aim: [0.5, 0.42, 0.42], up: [-0.3, 0.9, 0] }, footL: fL(0.22, 0.05, -8, { rot: [0, -4, -8] }), footR: fR(-0.3, 0, 0, { rot: [0, -70, 0] }) } },
    { t: 0.1, ease: 'inQuad', ik: { footL: fL(0.3, 0, 0) } },
    { t: 0.2, ease: 'outQuad', ...body([-0.01, -0.11, -0.01], [0, -17, 0], [0, -5, -5], [1, -3, -4], [0, 6, 2], [0, 10, -2]), ik: { handR: { pos: [0.36, 1.1, 0.07], aim: [0.84, 0.44, -0.24], up: [-0.4, 0.86, 0] }, footR: fR(-0.3, 0.03, 0, { rot: [0, -56, 4] }) } },
    { t: 0.27, ease: 'inQuad', ik: { footR: fR(-0.3, 0, 0) } },
    { t: 0.36, ease: 'inOutSine', pose: 'demo.stance' },
  ],
  events: [{ t: 0.1, name: 'step', data: { foot: 'footL' } }],
});
// idle fidgets (one-shots over demo.idle; start and end on its base pose)
defineClip('game.fidget1', {   // rolls the neck and the shoulders, opens and closes the left hand on the grip
  duration: 2.2, breath: 1.2,
  keys: [
    { t: 0, pose: 'demo.low' },
    { t: 0.5, ease: 'inOutSine', bones: { neck: [8, 4, 2], head: [12, 6, -4], shoulderL: [-8, 0, 0], shoulderR: [2, 0, 0], chest: [2, -5, 1] }, hips: { pos: [-0.025, -0.08, 0.012], rot: [1.5, -23, 0] }, grip: 0.4, curl: [0.3, 1] },
    { t: 1.05, ease: 'inOutSine', bones: { neck: [-8, 14, 3], head: [-12, 20, 0], shoulderL: [2, 0, 0], shoulderR: [-8, 0, 0], chest: [-2, -5, 1] }, hips: { pos: [-0.015, -0.08, -0.012], rot: [-1.5, -21, 0] }, grip: 0.4, curl: [0.1, 1],
      ik: { handR: { pos: [0.265, 0.99, 0.165], aim: [0.76, -0.4, -0.12] } } },
    { t: 1.6, ease: 'inOutSine', bones: { neck: [0, 9, -2], head: [0, 12, -8], shoulderL: [-3, 0, 0], shoulderR: [-3, 0, 0], chest: [0, -5, -2] }, grip: 1, curl: [1, 1], ik: { handR: { pos: [0.258, 0.97, 0.172], aim: [0.74, -0.5, -0.12] } } },
    { t: 2.2, ease: 'inOutSine', pose: 'demo.low' },
  ],
});
defineClip('game.fidget2', {   // shifts onto the rear leg, lifts and re-plants the front foot, tests the blade's weight
  duration: 2.6, breath: 1.2,
  keys: [
    { t: 0, pose: 'demo.low' },
    { t: 0.6, ease: 'inOutSine', hips: { pos: [-0.075, -0.1, 0.015], rot: [1, -27, 1] }, bones: { spine: [0, -7, -1], chest: [0, -6, 1] }, ik: { handR: { pos: [0.24, 1.0, 0.18], aim: [0.78, -0.3, -0.1] }, footL: fL(0.3, 0, 0) } },
    { t: 0.85, ease: 'outQuad', ik: { footL: fL(0.27, 0.05, -12) } },
    { t: 1.05, ease: 'inQuad', ik: { footL: fL(0.31, 0, 0) } },
    { t: 1.3, ease: 'inOutSine', hips: { pos: [-0.01, -0.085, -0.005], rot: [-1, -20, -1] }, bones: { spine: [0, -5, -3], chest: [0, -4, -1] }, ik: { handR: { pos: [0.3, 1.04, 0.15], aim: [0.84, -0.12, -0.14] } } },
    { t: 1.75, ease: 'inOutSine', ik: { handR: { pos: [0.27, 0.96, 0.17], aim: [0.72, -0.52, -0.12] } } },
    { t: 2.6, ease: 'inOutSine', pose: 'demo.low' },
  ],
  events: [{ t: 1.05, name: 'step', data: { foot: 'footL' } }],
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

// victory: a flick of the blade (one sharp diagonal, stopped dead), then stillness: rises tall, the blade lowered at
// the side, the feet drawn together one after the other
defineClip('game.victory', {
  duration: 2.0, breath: 1.2,
  keys: [
    { t: 0, pose: 'demo.stance' },
    { t: 0.22, ease: 'outCubic', ...body([-0.03, -0.07, 0], [0, -34, 0], [0, -10, 0], [1, -10, 2], [0, 14, 2], [0, 20, 0]), ik: { handR: { pos: [0.2, 1.3, 0.02], aim: [0.3, 0.8, -0.52], up: [-0.9, 0.4, 0] } } },
    { t: 0.32, ease: 'inCubic', ...body([-0.02, -0.1, 0], [0, -14, 0], [0, -4, -2], [0, -2, -2], [0, 6, 0], [0, 8, -2]), ik: { handR: { pos: [0.34, 0.86, 0.3], aim: [0.78, -0.5, 0.38], up: [0.42, 0.86, 0.28] } } },
    { t: 0.6, ease: 'inOutSine', ik: { handR: { pos: [0.33, 0.87, 0.3], aim: [0.77, -0.51, 0.38] }, footL: fL(0.3), footR: fR(-0.3) }, grip: 1 },
    { t: 0.78, ease: 'outQuad', ik: { footL: fL(0.26, 0.04, -6) } },
    { t: 0.92, ease: 'inQuad', ik: { footL: fL(0.2), footR: fR(-0.3) } },
    { t: 1.06, ease: 'outQuad', ik: { footR: fR(-0.22, 0.04, 4) } },
    { t: 1.2, ease: 'inQuad', ik: { footR: fR(-0.16) } },
    { t: 1.2, ease: 'inOutSine', ...body([-0.02, -0.03, 0], [0, -10, 0], [0, -2, 2], [0, -2, 3], [0, 4, 2], [0, 6, 2], { upperArmL: [-14, 6, 4], foreArmL: [0, 0, 16] }),
      ik: { handR: { pos: [0.14, 0.98, 0.32], aim: [0.72, -0.62, 0.3], up: [0.62, 0.78, 0] } }, grip: 0 },
    { t: 2.0, ease: 'inOutSine', bones: { neck: [0, 4, -2], head: [0, 6, -6] } },
  ],
  events: [{ t: 0.32, name: 'flick' }, { t: 0.92, name: 'step', data: { foot: 'footL' } }, { t: 1.2, name: 'step', data: { foot: 'footR' } }],
});
// second victory: the sword salute. The blade comes upright before the right shoulder, the left palm closes over the
// right fist, a short bow of the head, held
defineClip('game.victory2', {
  duration: 2.0, breath: 1.2,
  keys: [
    { t: 0, pose: 'demo.stance' },
    { t: 0.3, ease: 'inOutSine', ...body([-0.03, -0.08, 0], [0, -30, 0], [0, -8, -2], [1, -8, -1], [0, 12, 2], [0, 16, 0]), ik: { handR: { pos: [0.3, 1.12, 0.14], aim: [0.6, 0.78, -0.1], up: [-0.78, 0.6, 0] }, footL: fL(0.3), footR: fR(-0.3) }, grip: 0.5 },
    { t: 0.62, ease: 'outCubic', ...body([-0.02, -0.04, 0], [0, -14, 0], [0, -3, 0], [0, -3, 1], [0, 6, 2], [0, 8, 0]), ik: { handR: { pos: [0.34, 1.2, 0.12], aim: [0.06, 0.99, 0.04], up: [-0.99, 0.06, 0] }, handL: { pos: [0.4, 1.2, 0.05] } }, grip: 0 },
    { t: 0.8, ease: 'outQuad', ik: { footL: fL(0.26, 0.04, -6) } },
    { t: 0.94, ease: 'inQuad', ik: { footL: fL(0.2), footR: fR(-0.3) } },
    { t: 1.08, ease: 'outQuad', ik: { footR: fR(-0.22, 0.04, 4) } },
    { t: 1.22, ease: 'inQuad', ik: { footR: fR(-0.16) } },
    { t: 1.3, ease: 'inOutSine', ...body([-0.01, -0.05, 0], [0, -12, -3], [0, -3, -6], [0, -3, -6], [0, 6, -8], [0, 8, -12]), ik: { handR: { pos: [0.36, 1.16, 0.12] }, handL: { pos: [0.42, 1.16, 0.05] } } },
    { t: 2.0, ease: 'inOutSine', ...body([-0.02, -0.035, 0], [0, -12, 0], [0, -3, 1], [0, -3, 2], [0, 6, 0], [0, 8, -2]), ik: { handR: { pos: [0.34, 1.2, 0.12] }, handL: { pos: [0.4, 1.2, 0.05] } } },
  ],
  events: [{ t: 0.62, name: 'salute' }, { t: 0.94, name: 'step', data: { foot: 'footL' } }, { t: 1.22, name: 'step', data: { foot: 'footR' } }],
});

defineClip('game.defeat', {
  duration: 1.6, breath: 1.6,
  keys: [
    { t: 0, pose: 'demo.stance' },
    // the point drops to the floor ahead, he sags over the blade
    { t: 0.45, ease: 'inOutSine', ...body([-0.04, -0.17, 0], [0, -20, -4], [0, -4, -12], [0, -4, -10], [0, 4, -6], [0, 6, -12]),
      ik: { handR: { pos: [0.38, 0.82, 0.16], aim: [0.86, -0.5, 0.05], up: [0.5, 0.86, 0] }, footL: fL(0.3), footR: fR(-0.3) }, grip: 0.6 },
    // the rear knee gives: down onto it, the blade a strut under the right fist, the left hand on the front knee
    { t: 1.0, ease: 'inOutCubic', ...body([-0.1, -0.5, 0.01], [0, -18, -6], [0, -4, -16], [0, -4, -14], [0, 2, -12], [0, 4, -24], { upperArmL: [-8, 0, 34], foreArmL: [0, 0, 62] }),
      ik: { handR: { pos: [0.34, 0.52, 0.2], aim: [0.94, -0.3, 0.16], up: [0.3, 0.95, 0] }, footL: fL(0.32), footR: { pos: [-0.4, 0, 0.17], rot: [0, -38, -60], pole: [0.2, 0, 0.3] } }, grip: 0 },
    { t: 1.6, ease: 'inOutSine', ...body([-0.105, -0.52, 0.01], [0, -18, -7], [0, -4, -18], [0, -4, -16], [0, 2, -14], [0, 4, -28], { upperArmL: [-8, 0, 32], foreArmL: [0, 0, 64] }) },
  ],
  events: [{ t: 0.45, name: 'plant' }, { t: 1.0, name: 'kneel' }],
});

// ---------------------------------------------------------------------------------------------------------------
// resolution

/** Generic clip per presentation slot (state slots, then the variant slots: MOTION.md "Variant slots"). */
export const GENERIC = {
  idle: 'demo.idle', walkF: 'game.walkF', walkB: 'game.walkB', dash: 'game.dash', backstep: 'game.backstep',
  dodge: 'game.dodge', roll: 'game.dash', guard: 'demo.guard', guardBreak: 'game.guardbreak',
  hitLight: 'game.hitLight', hitHeavy: 'game.hitHeavy', crumple: 'game.crumple', launched: 'game.airRise', fall: 'game.airFall',
  down: 'game.down', getup: 'game.getup', ko: 'game.koDown', locked: 'game.locked',
  intro: 'game.intro', victory: 'game.victory', defeat: 'game.defeat', recovery: 'demo.idle',
  // direction-aware reactions
  hitLightHigh: 'game.hitLightHigh', hitLightMid: 'game.hitLightMid', hitLightLow: 'game.hitLightLow', hitLightBack: 'game.hitLightBack',
  hitHeavyBack: 'game.hitHeavyBack', guardHit: 'game.guardHit', guardHitHeavy: 'game.guardHitHeavy',
  // the face-down chain (a blow from behind) and the tech rolls
  launchedProne: 'game.airRiseProne', fallProne: 'game.airFallProne', downProne: 'game.downProne', getupProne: 'game.getupProne',
  koProne: 'game.koProne', tech: 'game.tech', techProne: 'game.techProne',
  // life and ceremony
  turn: 'game.turn', idleFidget: 'game.fidget1', idleFidget2: 'game.fidget2', victory2: 'game.victory2',
};

/**
 * Variant slot -> the slot it is a variant of. A fighter's own clip for a parent slot beats a generic variant (the
 * hero's grips and stance stay the hero's): resolution is own variant -> own parent (up the chain) -> generic variant
 * -> generic parent.
 */
export const VARIANT_BASE = {
  hitLightHigh: 'hitLight', hitLightMid: 'hitLight', hitLightLow: 'hitLight', hitLightBack: 'hitLight', hitHeavyBack: 'hitHeavy',
  guardHit: 'guard', guardHitHeavy: 'guardHit',
  launchedProne: 'launched', fallProne: 'fall', downProne: 'down', getupProne: 'getup', koProne: 'ko', tech: 'getup', techProne: 'tech',
  turn: 'idle', idleFidget: 'idle', walkStopF: 'walkF', walkStopB: 'walkB',
};
/** Variant slots that only exist when a clip was made for them (`has(slot)` is false otherwise and nothing extra plays). */
const OPTIONAL = new Set(['guardHit', 'guardHitHeavy', 'turn', 'idleFidget', 'walkStopF', 'walkStopB']);
/** Highest numbered sibling of a multi-clip slot (`victory`, `victory2` ... `victory6`). */
const MAX_VARIANTS = 6;
/** Every state / variant slot name (for warming). */
export const SLOTS = [...new Set([...Object.keys(GENERIC), ...Object.keys(VARIANT_BASE)])].filter((s) => !/\d$/.test(s));

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
 *
 * State slots resolve in this order: the fighter's map entry (`clips[slot]`: a name, `{ clip, speed, fade }` or an
 * array of those), a registered clip named `<fighter id>.<slot>` (the convention: an animator adds `kael.hitLightHigh`
 * or `iska.idleFidget2` and it is live, no map edit), the fighter's own clip of the parent slot (VARIANT_BASE), then
 * the generic clips. Multi-clip slots (`victory`, `idleFidget`, any slot with numbered siblings `slot2` ... `slot6`)
 * are listed by `variants(slot)`.
 * @param {object} fighter registry fighter ({ id, clips, def })
 * @param {object} compiled compiled rules definition (match.defs[i])
 * @param {{ twin?: boolean }} [o] twin: the character holds a weapon in each hand (fallback clips use twinVariant)
 * @returns {{ state(slot): {name, speed, own, duration, rootSpeed}, has(slot): boolean, variants(slot): object[],
 *   names(): string[], move(id): {name, map(t) -> clip time, fade}, map, slots }}
 */
export function createClipSet(fighter, compiled, o = {}) {
  const fallback = o.twin ? twinVariant : (n) => n;
  let map = fighter.clips || {};
  if (typeof map === 'function') {
    try { map = map({ defineClip, definePose, hasClip }) || {}; } catch (e) { console.warn('[ed] clips of ' + fighter.id + ' failed: ' + e.message); map = {}; }
  }
  if (map.map && typeof map.map === 'object') map = map.map;
  const norm = (v) => {
    const e = typeof v === 'string' ? { clip: v } : v;
    return e && e.clip && hasClip(e.clip) ? e : null;
  };
  /** Map entries of a key (an array entry lists several clips). */
  const entries = (key) => {
    const v = map[key];
    return (Array.isArray(v) ? v : v ? [v] : []).map(norm).filter(Boolean);
  };
  const entry = (key) => entries(key)[0] || null;
  /** A fighter's own clip for a state slot: its map, else the naming convention `<id>.<slot>`. */
  const prefix = typeof fighter.id === 'string' && fighter.id ? fighter.id + '.' : null;
  const ownAll = (slot) => {
    const list = entries(slot);
    if (!list.length && prefix && hasClip(prefix + slot)) list.push({ clip: prefix + slot });
    return list;
  };
  const own = (slot) => ownAll(slot)[0] || null;
  const states = {}, lists = {}, exists = {};
  const stats = (compiled && compiled.stats) || {};
  const made = (slot, e, name) => ({ name, speed: (e && e.speed) || 1, fade: e ? e.fade : undefined, own: !!e, slot, duration: clipDuration(name), rootSpeed: clipRootSpeed(name) });
  /** Resolve a slot: [state object, exact] (exact: a clip made for this very slot, own or generic). */
  const resolve = (slot) => {
    const e = own(slot);
    if (e) return [made(slot, e, e.clip), true];
    for (let b = VARIANT_BASE[slot]; b; b = VARIANT_BASE[b]) if (own(b)) return [state(b), false];
    const walkDir = slot === 'walkF' ? 1 : slot === 'walkB' ? -1 : 0;
    if (walkDir) return [made(slot, null, fallback(walkClipFor(walkDir, walkDir > 0 ? stats.walkSpeed : stats.backSpeed))), true];
    if (GENERIC[slot] && hasClip(GENERIC[slot])) return [made(slot, null, fallback(GENERIC[slot])), true];
    for (let b = VARIANT_BASE[slot]; b; b = VARIANT_BASE[b]) if (GENERIC[b] && hasClip(GENERIC[b])) return [state(b), false];
    return [made(slot, null, fallback('demo.idle')), false];
  };
  const state = (slot) => {
    if (states[slot]) return states[slot];
    const [st, exact] = resolve(slot);
    exists[slot] = exact;
    return (states[slot] = st);
  };
  /** True when a clip exists for this very slot (optional variant slots: nothing extra plays without one). */
  const has = (slot) => { state(slot); return OPTIONAL.has(slot) || slot in VARIANT_BASE ? exists[slot] : true; };
  /** Every clip of a multi-clip slot: the fighter's own (`slot` entries, then `slot2` ... `slot6`), else the generic ones. */
  const variants = (slot) => {
    if (lists[slot]) return lists[slot];
    const out = [];
    const push = (s, e) => { if (!out.some((x) => x.name === e.clip)) out.push(made(s, e, e.clip)); };
    for (const e of ownAll(slot)) push(slot, e);
    for (let k = 2; k <= MAX_VARIANTS; k++) for (const e of ownAll(slot + k)) push(slot + k, e);
    if (!out.length && has(slot)) {
      out.push(state(slot));
      // generic siblings only next to a generic first clip (never mixed into a hero's own set)
      if (!state(slot).own) for (let k = 2; k <= MAX_VARIANTS; k++) { const g = GENERIC[slot + k]; if (g && hasClip(g)) out.push(made(slot + k, null, fallback(g))); }
    }
    return (lists[slot] = out);
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
  /** Every clip name this fighter can be asked to play (states, variants, moves): compile them up front. */
  const names = () => {
    const out = new Set();
    for (const slot of SLOTS) { out.add(state(slot).name); for (const v of variants(slot)) out.add(v.name); }
    if (compiled && compiled.moves) for (const id in compiled.moves) out.add(move(id).name);
    return [...out];
  };
  return { state, has, variants, names, move, map, slots: slotMoves(compiled) };
}
