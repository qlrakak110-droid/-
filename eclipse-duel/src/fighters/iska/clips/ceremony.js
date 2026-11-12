// ISKA round ceremony and reactions: intro, victory, defeat, hitLight, hitHeavy, guardBreak, crumple, getup, launched, fall, down, ko.

import { defineClip, definePose } from '../../../char/index.js';
import { foot, hand, FL, FR, YAW_L, YAW_R, PITCH, ev } from './common.js';

const S = 'iska.stance';

// intro (2.4): kneeling in prayer with the crossed blades held against the chest, rises, opens both blades in a slow
// fan, spins them once and settles into the guard stance
defineClip('iska.intro', {
  duration: 2.4, breath: 1.2,
  keys: [
    { t: 0, hips: { pos: [-0.04, -0.46, 0], rot: [0, -20, 0] }, bones: { spine: [0, -2, -8], chest: [0, -2, -6], neck: [0, 4, -10], head: [0, 6, -22] },
      ik: { handR: hand([0.26, 0.92, 0.07], [0.1, 0.8, -0.58], [0.98, -0.1, 0.1], { pole: [0.1, 0.6, 0.6] }), handL: hand([0.27, 0.9, -0.03], [0.1, 0.8, 0.58], [0.98, -0.1, -0.1], { pole: [0.1, 0.6, -0.6] }),
        footL: foot([0.32, 0, -0.13], 12, 0), footR: foot([-0.38, 0, 0.14], -36, -62) }, grip: 0, curl: [1, 1] },
    { t: 0.6, ease: 'inOutSine', bones: { neck: [0, 4, -6], head: [0, 6, -14] } },
    // rise: head lifts first, then the body
    { t: 1.2, ease: 'inOutSine', hips: { pos: [-0.03, -0.06, 0], rot: [0, -22, 0] }, bones: { spine: [0, -4, 4], chest: [0, -6, 6], neck: [0, 8, 0], head: [0, 12, 0] },
      ik: { handR: hand([0.34, 1.26, 0.09], [0.15, 0.8, -0.58], [0.98, -0.1, 0.1], { pole: [0.2, 1.0, 0.6] }), handL: hand([0.35, 1.24, -0.03], [0.15, 0.8, 0.58], [0.98, -0.1, -0.1], { pole: [0.2, 1.0, -0.6] }),
        footL: foot(FL, YAW_L, -10), footR: foot([-0.28, 0.02, 0.14], YAW_R, -20) } },
    // the fan: both blades swept open and down to the sides
    { t: 1.6, ease: 'inOutSine', hips: { pos: [-0.03, -0.05, 0], rot: [0, -24, 0] }, bones: { chest: [0, -6, 10], head: [0, 12, 4] },
      ik: { handR: hand([0.14, 1.12, 0.52], [0.4, 0.3, 0.86], [-0.85, 0.4, 0.3]), handL: hand([0.22, 1.1, -0.48], [0.4, 0.3, -0.86], [-0.85, 0.4, -0.3]) } },
    { t: 1.85, ease: 'inOutSine', ik: { handR: hand([0.18, 1.0, 0.46], [0.3, -0.7, 0.64], [0.75, 0.65, 0.1]), handL: hand([0.24, 1.0, -0.42], [0.3, -0.7, -0.64], [0.75, 0.65, -0.1]) } },
    { t: 2.4, ease: 'inOutSine', pose: S },
  ],
  events: ev([[1.2, 'rise'], [1.6, 'fan']]),
});

// victory (2.0): flicks both blades, then raises the right crescent to the sky, left blade low behind
defineClip('iska.victory', {
  duration: 2.0, breath: 1.2,
  keys: [
    { t: 0, pose: S },
    { t: 0.25, ease: 'outCubic', ik: { handR: hand([0.24, 0.92, 0.36], [0.3, -0.8, 0.5], [0.8, 0.5, 0.2]), handL: hand([0.28, 0.94, -0.3], [0.3, -0.8, -0.5], [0.8, 0.5, -0.2]) } },
    { t: 0.8, ease: 'inOutCubic', hips: { pos: [-0.02, -0.02, 0], rot: [0, -30, 4] }, bones: { spine: [0, -4, 8], chest: [0, -6, 12], neck: [0, 6, -8], head: [0, 10, -16] },
      ik: { handR: hand([0.16, 2.0, 0.22], [0.2, 0.9, 0.3], [-0.95, 0.2, 0.1]), handL: hand([-0.22, 0.98, -0.3], [-0.6, -0.5, -0.6], [-0.3, 0.86, -0.3]),
        footL: foot([0.12, 0.02, -0.08], 10, -24), footR: foot([-0.2, 0.02, 0.14], -30, -20) } },
    { t: 2.0, ease: 'inOutSine', bones: { chest: [0, -6, 13], head: [0, 10, -18] }, ik: { handR: hand([0.16, 2.02, 0.22], [0.2, 0.9, 0.3]) } },
  ],
});

// defeat (1.6): staggers, sinks to one knee, blades lowered to the floor, head bowed
defineClip('iska.defeat', {
  duration: 1.6, breath: 1.6,
  keys: [
    { t: 0, pose: S },
    { t: 0.5, ease: 'inOutSine', hips: { pos: [-0.08, -0.2, 0], rot: [-4, -26, 6] }, bones: { spine: [0, -4, -10], chest: [0, -4, -8], neck: [0, 4, -8], head: [4, 6, -16] },
      ik: { handR: hand([0.2, 0.8, 0.24], [0.4, -0.86, 0.1], [0.9, 0.4, 0.0]), handL: hand([0.24, 0.84, -0.2], [0.4, -0.86, -0.1], [0.9, 0.4, 0.0]),
        footR: foot([-0.36, 0.01, 0.14], YAW_R, -30) } },
    { t: 1.1, ease: 'inOutCubic', hips: { pos: [-0.06, -0.48, 0], rot: [-2, -22, 4] }, bones: { spine: [0, -4, -18], chest: [0, -4, -14], neck: [0, 2, -12], head: [4, 4, -26] },
      ik: { handR: hand([0.42, 0.36, 0.2], [0.3, -0.9, 0.3], [0.9, 0.3, 0.0]), handL: hand([0.36, 0.4, -0.22], [0.4, -0.9, -0.2], [0.9, 0.4, 0.0]),
        footL: foot([0.3, 0, -0.13], 12, 0), footR: foot([-0.4, 0, 0.14], -36, -64) } },
    { t: 1.6, ease: 'inOutSine', bones: { head: [4, 4, -30] } },
  ],
});

// hit reactions (the game starts them at 0.05 / 0.06: the impact pose is held through the hit-stop)
defineClip('iska.hitLight', {
  duration: 0.32, breath: 0.4,
  keys: [
    { t: 0, pose: S },
    { t: 0.05, ease: 'outQuad', hips: { pos: [-0.08, -0.1, 0.01], rot: [-2, -30, 5] }, bones: { spine: [-2, -8, 8], chest: [-3, -8, 10], neck: [3, 6, 10], head: [4, 8, 16] },
      ik: { handR: hand([0.16, 1.02, 0.18], [0.5, -0.3, -0.8], [0.8, 0.55, 0.1]), handL: hand([0.2, 1.04, -0.1], [0.5, -0.3, 0.8], [0.8, 0.55, -0.1]),
        footR: foot(FR, YAW_R, -24) } },
    { t: 0.32, ease: 'inOutSine', pose: S },
  ],
});

defineClip('iska.hitHeavy', {
  duration: 0.7, breath: 0.6,
  keys: [
    { t: 0, pose: S },
    { t: 0.06, ease: 'outQuad', hips: { pos: [-0.14, -0.12, 0.02], rot: [-4, -36, 8] }, bones: { spine: [-4, -10, 14], chest: [-5, -8, 16], neck: [4, 6, 16], head: [6, 10, 24] },
      ik: { handR: hand([0.1, 1.2, 0.3], [0.2, 0.6, 0.78], [0.9, -0.2, 0.3]), handL: hand([0.16, 1.18, -0.24], [0.2, 0.6, -0.78], [0.9, -0.2, -0.3]),
        footL: foot([0.24, 0.05, -0.12], YAW_L, -20), footR: foot(FR, YAW_R, -30) } },
    { t: 0.16, ease: 'inOutSine', hips: { pos: [-0.12, -0.17, 0.01], rot: [-3, -32, 5] }, bones: { spine: [-2, -10, 6], chest: [-3, -9, 8], neck: [2, 8, 6], head: [3, 10, 6] },
      ik: { footR: foot([-0.42, 0.06, 0.14], YAW_R, -20) } },
    { t: 0.26, ease: 'inQuad', ik: { footR: foot([-0.46, 0.01, 0.14], YAW_R, -14) } },
    { t: 0.42, ease: 'inOutSine', hips: { pos: [-0.06, -0.12, 0], rot: [-1, -26, 2] }, bones: { spine: [0, -6, -2], chest: [0, -7, -1], neck: [0, 8, 2], head: [0, 12, -2] },
      ik: { handR: hand([0.22, 0.95, 0.14], [0.5, -0.66, -0.56], [0.86, 0.5, 0.1]), handL: hand([0.27, 0.97, -0.07], [0.52, -0.62, 0.58], [0.84, 0.54, -0.1]),
        footL: foot([0.2, 0.02, -0.12], YAW_L, -10) } },
    { t: 0.56, ease: 'inOutSine', ik: { footR: foot([-0.34, 0.05, 0.14], YAW_R, -20) } },
    { t: 0.62, ease: 'inQuad', ik: { footR: foot(FR, YAW_R, PITCH), footL: foot(FL, YAW_L, PITCH) } },
    { t: 0.7, ease: 'inOutSine', pose: S },
  ],
  events: ev([[0.26, 'step', { foot: 'footR' }]]),
});

// guard break (progress-driven): blades knocked apart, chest thrown open, a stagger step back, then a hunched, open
// guard (the punish window)
defineClip('iska.guardBreak', {
  duration: 0.7, breath: 0.8,
  keys: [
    { t: 0, pose: 'iska.block' },
    { t: 0.08, ease: 'outQuad', hips: { pos: [-0.12, -0.12, 0], rot: [-3, -28, 8] }, bones: { spine: [0, -4, 12], chest: [0, -6, 16], neck: [0, 6, 10], head: [0, 8, 18] },
      ik: { handR: hand([-0.02, 1.5, 0.52], [-0.3, 0.6, 0.74], [0.9, 0.2, 0.3]), handL: hand([0.06, 1.46, -0.48], [-0.3, 0.6, -0.74], [0.9, 0.2, -0.3]),
        footL: foot([0.28, 0.06, -0.12], YAW_L, -24), footR: foot([-0.3, 0.01, 0.15], -42, -10) } },
    { t: 0.2, ease: 'inOutSine', hips: { pos: [-0.14, -0.18, 0], rot: [-2, -30, 5] }, ik: { footR: foot([-0.42, 0.06, 0.15], -42, -20) } },
    { t: 0.3, ease: 'inQuad', ik: { footR: foot([-0.5, 0.0, 0.15], -42, -6) } },
    { t: 0.45, ease: 'inOutSine', hips: { pos: [-0.12, -0.2, 0], rot: [0, -26, 2] }, bones: { spine: [0, -4, -10], chest: [0, -6, -8], neck: [0, 6, 4], head: [0, 8, 0] },
      ik: { handR: hand([0.12, 0.86, 0.3], [0.3, -0.85, 0.4], [0.9, 0.3, 0.1]), handL: hand([0.18, 0.88, -0.26], [0.3, -0.85, -0.4], [0.9, 0.3, -0.1]),
        footL: foot([0.24, 0.01, -0.12], YAW_L, -6) } },
    { t: 0.7, ease: 'inOutSine', hips: { pos: [-0.1, -0.19, 0] }, ik: { handR: hand([0.14, 0.87, 0.28], [0.3, -0.85, 0.4]), handL: hand([0.2, 0.89, -0.24], [0.3, -0.85, -0.4]) } },
  ],
  events: ev([[0.3, 'step', { foot: 'footR' }]]),
});

// crumple (progress-driven; the freezing shard / heavy stuns): a rigid frozen jolt, then the knees give way into a kneel
defineClip('iska.crumple', {
  duration: 0.9, breath: 0.3,
  keys: [
    { t: 0, pose: S },
    { t: 0.06, ease: 'outQuad', hips: { pos: [-0.08, -0.06, 0], rot: [-2, -26, 6] }, bones: { spine: [0, -4, 8], chest: [0, -6, 10], neck: [2, 6, 8], head: [3, 8, 12], shoulderR: [-8, 0, 0], shoulderL: [-8, 0, 0] },
      ik: { handR: hand([0.16, 1.1, 0.3], [0.3, -0.5, 0.8], [0.9, 0.4, -0.1]), handL: hand([0.2, 1.1, -0.26], [0.3, -0.5, -0.8], [0.9, 0.4, 0.1]),
        footL: foot(FL, YAW_L, -20), footR: foot(FR, YAW_R, -24) } },
    { t: 0.3, ease: 'inOutSine', hips: { pos: [-0.06, -0.12, 0], rot: [-2, -24, 4] }, bones: { spine: [0, -4, 2], chest: [0, -6, 2], neck: [0, 4, -2], head: [2, 6, -6], shoulderR: [0, 0, 0], shoulderL: [0, 0, 0] } },
    { t: 0.62, ease: 'inCubic', hips: { pos: [-0.06, -0.44, 0], rot: [-2, -22, 2] }, bones: { spine: [0, -4, -14], chest: [0, -4, -12], neck: [0, 2, -10], head: [3, 4, -22] },
      ik: { handR: hand([0.3, 0.42, 0.24], [0.4, -0.9, 0.2], [0.9, 0.4, 0.0]), handL: hand([0.34, 0.46, -0.2], [0.4, -0.9, -0.2], [0.9, 0.4, 0.0]),
        footL: foot([0.3, 0, -0.13], 12, 0), footR: foot([-0.38, 0, 0.14], -36, -62) } },
    { t: 0.9, ease: 'outQuad', hips: { pos: [-0.06, -0.46, 0] }, bones: { head: [3, 4, -26] } },
  ],
});

// get-up (progress-driven, 0.45 s): from lying on the back (the generic down pose, both crescents flat beside the
// body) she rolls onto the left knee and springs up into her own stance (the generic get-up ends in the knight's)
definePose('iska.downPose', {
  hips: { pos: [0.22, -0.9, 0], rot: [0, -8, 84] },
  bones: {
    spine: [0, 0, 4], chest: [0, -4, 6], neck: [0, 10, -6], head: [6, 24, -10],
    thighR: [-8, 0, 8], shinR: [0, 0, -14], footR: [0, 0, -30], thighL: [10, 0, 34], shinL: [0, 0, -64], footL: [0, 0, -10],
  },
  ik: {
    handR: { space: 'chest', pos: [0.03, -0.42, 0.42], aim: [0.06, -0.92, 0.38], up: [0.0, 0.38, 0.92] },
    handL: { space: 'chest', pos: [0.05, -0.4, -0.42], aim: [0.06, -0.92, -0.38], up: [0.0, 0.38, -0.92] },
  },
  grip: 0, curl: [1, 1],
});
defineClip('iska.getup', {
  duration: 0.45, breath: 0,
  keys: [
    { t: 0, pose: 'iska.downPose', ik: { footL: { pos: FL, w: 0 }, footR: { pos: FR, w: 0 } } },
    { t: 0.2, ease: 'outQuad', hips: { pos: [-0.04, -0.46, 0], rot: [0, -22, 8] },
      bones: { spine: [0, -6, -12], chest: [0, -6, -8], neck: [0, 8, 6], head: [0, 12, 4], thighL: [0, 0, 0], shinL: [0, 0, 0], thighR: [0, 0, 0], shinR: [0, 0, 0], footL: [0, 0, 0], footR: [0, 0, 0] },
      ik: { footL: foot([0.3, 0, -0.13], 12, 0, { w: 1 }), footR: foot([-0.38, 0, 0.14], -36, -60, { w: 1 }),
        handR: hand([0.36, 0.5, 0.26], [0.5, -0.8, 0.3], [0.8, 0.5, 0.0]), handL: hand([0.4, 0.52, -0.2], [0.5, -0.8, -0.3], [0.8, 0.5, 0.0]) } },
    { t: 0.45, ease: 'inOutSine', pose: S },
  ],
  events: ev([[0.45, 'step', { foot: 'footR' }]]),
});

// ---- airborne / lying reactions (FK legs; both crescents trailing along the body in the chest frame) -----------------
const AIR_R = { space: 'chest', pos: [0.05, -0.48, 0.38], aim: [-0.5, -0.82, 0.25], up: [0.82, -0.5, 0] };
const AIR_L = { space: 'chest', pos: [0.08, -0.44, -0.4], aim: [-0.4, -0.82, -0.4], up: [0.85, -0.45, 0.2] };
const LIMP_ARMS = { upperArmR: [-30, 0, 12], foreArmR: [0, 0, 30], upperArmL: [-36, 0, 18], foreArmL: [0, 0, 28] };

// launched (rising): arched back, limbs trailing, head thrown back
defineClip('iska.launched', {
  duration: 0.8, loop: true, breath: 0,
  keys: [
    { t: 0, ease: 'inOutSine', hips: { pos: [0, 0.05, 0], rot: [0, -18, 34] },
      bones: { spine: [0, 0, 10], chest: [0, -4, 12], neck: [0, 8, 14], head: [4, 10, 20], ...LIMP_ARMS,
        thighR: [-6, 0, 16], shinR: [0, 0, -50], footR: [0, 0, -30], thighL: [6, 0, 38], shinL: [0, 0, -74], footL: [0, 0, -26] },
      ik: { handR: AIR_R, handL: AIR_L }, grip: 0, curl: [1, 1] },
    { t: 0.4, ease: 'inOutSine', hips: { rot: [0, -20, 38] }, bones: { head: [4, 12, 24], thighL: [6, 0, 44], shinL: [0, 0, -80] } },
  ],
});

// fall: body tipping toward horizontal, ready to land on the back
defineClip('iska.fall', {
  duration: 0.8, loop: true, breath: 0,
  keys: [
    { t: 0, ease: 'inOutSine', hips: { pos: [0.05, -0.25, 0], rot: [0, -12, 66] },
      bones: { spine: [0, 0, 6], chest: [0, -2, 6], neck: [0, 6, -10], head: [2, 12, -14], ...LIMP_ARMS,
        thighR: [-4, 0, 30], shinR: [0, 0, -36], footR: [0, 0, -24], thighL: [8, 0, 48], shinL: [0, 0, -60], footL: [0, 0, -20] },
      ik: { handR: { ...AIR_R, pos: [0.12, -0.42, 0.42], aim: [-0.2, -0.75, 0.62] }, handL: { ...AIR_L, pos: [0.14, -0.4, -0.42], aim: [-0.2, -0.75, -0.62] } }, grip: 0, curl: [1, 1] },
    { t: 0.4, ease: 'inOutSine', hips: { rot: [0, -10, 70] } },
  ],
});

// down (lying on the back, breathing hard) and KO (still, head turned away)
defineClip('iska.down', {
  duration: 2.4, loop: true, breath: 1.4,
  keys: [
    { t: 0, pose: 'iska.downPose', ease: 'inOutSine' },
    { t: 1.2, ease: 'inOutSine', bones: { head: [6, 18, -8], thighL: [10, 0, 30], shinL: [0, 0, -58] } },
  ],
});
defineClip('iska.ko', {
  duration: 3, loop: true, breath: 0.25,
  keys: [{ t: 0, pose: 'iska.downPose', hips: { pos: [0.22, -0.91, 0], rot: [0, -4, 87] },
    bones: { spine: [2, 0, 2], chest: [2, -2, 3], neck: [0, 18, -2], head: [10, 40, -6], thighR: [-12, 0, 2], shinR: [0, 0, -6], footR: [0, 0, -36], thighL: [6, 0, 14], shinL: [0, 0, -26], footL: [0, 0, -30] } }],
});
