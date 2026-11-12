// KAEL — ultimate lock beats ("Pyre of the Black Sun"), played by the choreographer with h.play() during the 5.2 s
// cinematic lock. Each beat starts where the previous one ends; the lock time to start each one is in NAMES.md, and
// each beat's `impact` events then fall on the lock ticks (cut1-3 at lock 0.25 / 0.40 / 0.55, hurl 1.30, meteor 2.90).
// Air beats switch the feet off IK (FK tucks); the height and travel of the leaps are the choreographer's h.offset().

import { defineClip } from '../../../char/index.js';
import { FL, FR, YAW_L, YAW_R, FEET, SHOULDER_HAND, STANCE_BODY, dir, grip, plane } from './common.js';

const G = (pos, o) => grip(pos, o.aim || o);                   // blade direction (vector or plane sample), natural roll
const ev = (list) => list.map(([t, name, data]) => (data ? { t, name, data } : { t, name }));
const hits = (t, cut) => [[t, 'impact', { cut }], [t, 'hit', { cut }]];
const DIAG = plane([-0.8, 0.5, 0.32], [0.25, 0.8, 0.55]);       // the forehand diagonal (see moves.js)
const OVER = plane(dir(180, 28), dir(0, 85));                  // overhead chop: 0 behind, 60 up, 150 forward, 176 floor
const BACK_FOOT_UP = { pos: FR, rot: [0, YAW_R, -26] };
/** Feet off IK (airborne): FK legs take over. */
const AIR = { footL: { pos: FL, w: 0 }, footR: { pos: FR, w: 0 } };
const GROUND = { footL: { pos: FL, rot: [0, YAW_L, 0], w: 1 }, footR: { pos: FR, rot: [0, YAW_R, 0], w: 1 } };
const LEGS0 = { thighL: [0, 0, 0], shinL: [0, 0, 0], footL: [0, 0, 0], thighR: [0, 0, 0], shinR: [0, 0, 0], footR: [0, 0, 0] };

// ---- cuts: three rapid burning cuts (lock 0.10 -> 0.95; impacts at clip 0.15 / 0.30 / 0.45) ------------------------
defineClip('kael.ult.cuts', {
  duration: 0.85, breath: 0,
  keys: [
    // from the opener's landing: blade low in front, deep crouch
    { t: 0, hips: { pos: [-0.04, -0.33, 0], rot: [0, -14, 0] }, bones: { spine: [0, -2, -20], chest: [0, -2, -15], neck: [0, 4, 12], head: [0, 6, 14] },
      ik: { handR: G([0.62, 0.78, 0.05], OVER(172)), ...FEET, footR: BACK_FOOT_UP }, grip: 1, curl: [1, 1] },
    // wrench up, cocked high over the right shoulder
    { t: 0.09, ease: 'outCubic', hips: { pos: [-0.06, -0.16, 0.01], rot: [1, -36, 1] }, bones: { spine: [1, -8, 2], chest: [2, -12, 5], neck: [0, 18, -2], head: [0, 23, -4] },
      ik: { handR: { pos: [0.06, 1.58, 0.27], ...DIAG(-10) }, footR: FEET.footR } },
    // cut 1: forehand diagonal down
    { t: 0.13, ik: { handR: { pos: [0.4, 1.64, 0.2], ...DIAG(70) } } },
    { t: 0.15, hips: { pos: [0.05, -0.2, -0.01], rot: [-2, 8, -2] }, bones: { spine: [-2, 6, -10], chest: [-3, 8, -8], neck: [0, -4, 4], head: [0, -6, 6] },
      ik: { handR: { pos: [0.66, 1.2, 0.05], ...DIAG(132) } } },
    { t: 0.2, ease: 'outQuad', hips: { pos: [0.07, -0.22, -0.02], rot: [-3, 28, -4] }, bones: { spine: [-3, 10, -12], chest: [-4, 12, -9], neck: [0, -12, 6], head: [0, -16, 8] },
      ik: { handR: { pos: [0.42, 0.84, -0.24], ...DIAG(208) } } },
    // cut 2: the back edge climbs straight back up the same line
    { t: 0.26, ik: { handR: { pos: [0.5, 0.96, -0.14], ...DIAG(176) } } },
    { t: 0.3, hips: { pos: [0.06, -0.17, 0.01], rot: [1, -10, 2] }, bones: { spine: [1, -6, -3], chest: [1, -8, 0], neck: [0, 8, 0], head: [0, 10, -2] },
      ik: { handR: { pos: [0.64, 1.32, 0.08], ...DIAG(126) } } },
    { t: 0.35, ease: 'outQuad', hips: { pos: [-0.02, -0.12, 0.02], rot: [1, -26, 2] }, bones: { spine: [0, -6, 6], chest: [0, -6, 10], neck: [0, 10, -6], head: [0, 12, -10] },
      ik: { handR: G([0.2, 1.9, 0.16], OVER(20)) } },
    // cut 3: straight down the middle, the X's crossing stroke
    { t: 0.41, ik: { handR: G([0.5, 1.82, 0.08], OVER(85)) } },
    { t: 0.45, ease: 'inQuad', hips: { pos: [-0.04, -0.3, 0], rot: [0, -12, 0] }, bones: { spine: [0, -2, -20], chest: [0, -2, -16], neck: [0, 4, 12], head: [0, 6, 14] },
      ik: { handR: G([0.64, 0.86, 0.05], OVER(166)), footR: BACK_FOOT_UP } },
    { t: 0.52, ease: 'outQuad', ik: { handR: G([0.62, 0.82, 0.05], OVER(170)) } },
    // the point lifts off the floor and swings around the right side
    { t: 0.61, ease: 'inOutSine', hips: { pos: [-0.06, -0.26, 0.02], rot: [0, -40, -1] }, ik: { handR: G([0.24, 0.98, 0.32], dir(-95, -8)) } },
    // coil for the hurl: the blade swings back low on the right, point down by the rear foot
    { t: 0.7, ease: 'inOutSine', hips: { pos: [-0.08, -0.3, 0.03], rot: [0, -62, -2] }, bones: { spine: [0, -12, -12], chest: [0, -14, -10], neck: [0, 26, 8], head: [0, 32, 8] },
      ik: { handR: G([-0.08, 0.86, 0.34], dir(-160, -30)), footR: FEET.footR } },
    { t: 0.85, ease: 'inOutSine', hips: { pos: [-0.09, -0.31, 0.03], rot: [0, -66, -2] }, ik: { handR: G([-0.1, 0.85, 0.34], dir(-165, -30)) } },
  ],
  events: ev([[0.05, 'trailOn'], ...hits(0.15, 1), ...hits(0.3, 2), ...hits(0.45, 3), [0.52, 'trailOff']]),
});

// ---- hurl: the rising cut that throws the victim up (lock 0.95 -> 1.80; impact at clip 0.35 = lock 1.30) ----------
{
  const RISE = plane([-0.8, -0.5, 0.33], [0.0, 0.1, 1]);
  const LIFT = plane(dir(-6, -36), dir(0, 30), true);
  defineClip('kael.ult.hurl', {
    duration: 0.85, breath: 0,
    keys: [
      { t: 0, hips: { pos: [-0.09, -0.31, 0.03], rot: [0, -66, -2] }, bones: { spine: [0, -12, -12], chest: [0, -14, -10], neck: [0, 26, 8], head: [0, 32, 8] },
        ik: { handR: G([-0.1, 0.85, 0.34], dir(-165, -30)), ...FEET }, grip: 1, curl: [1, 1] },
      // tension: sinks further, the blade grinds along the floor behind him
      { t: 0.24, ease: 'inOutSine', hips: { pos: [-0.12, -0.36, 0.03], rot: [0, -76, -3] }, bones: { spine: [0, -13, -14], chest: [0, -15, -12] },
        ik: { handR: G([-0.14, 0.82, 0.33], dir(-172, -30)), footR: { pos: FR, rot: [0, -60, 0] } } },
      // release along the right side and up through the victim
      { t: 0.3, hips: { pos: [-0.04, -0.28, 0.02], rot: [0, -40, 0] }, ik: { handR: { pos: [0.08, 0.88, 0.36], ...RISE(80) } } },
      { t: 0.35, hips: { pos: [0.04, -0.16, 0], rot: [0, -6, 0] }, bones: { spine: [0, -2, -4], chest: [0, 0, 0], neck: [0, 4, -2], head: [0, 4, -6] },
        ik: { handR: G([0.56, 1.2, 0.12], LIFT(80)), footL: FEET.footL, footR: BACK_FOOT_UP } },
      // follow-through: stretched tall onto the toes, blade straight up after the victim, head up
      { t: 0.44, ease: 'outQuad', hips: { pos: [0.02, 0.0, 0], rot: [0, -14, 0] }, bones: { spine: [0, -4, 8], chest: [0, -6, 13], neck: [0, 8, -12], head: [0, 10, -20] },
        ik: { handR: G([0.3, 1.96, 0.12], LIFT(118)), footR: { pos: [FR[0] + 0.04, 0.05, FR[2]], rot: [0, YAW_R, -34] } } },
      { t: 0.56, ease: 'inOutSine', hips: { pos: [0.0, -0.02, 0] }, ik: { handR: G([0.28, 1.94, 0.12], LIFT(120)) } },
      // load the leap: blade back over the right shoulder, knees deep, eyes on the victim above
      { t: 0.85, ease: 'inOutSine', hips: { pos: [-0.08, -0.36, 0], rot: [0, -22, 0] }, bones: { spine: [0, -4, -6], chest: [0, -6, 2], neck: [0, 12, -10], head: [0, 14, -18] },
        ik: { handR: G([-0.02, 1.5, 0.22], dir(180, 20)), ...FEET, footR: BACK_FOOT_UP } },
    ],
    events: ev([[0.26, 'trailOn'], [0.35, 'impact', { hurl: true }], [0.35, 'hit', { hurl: true }], [0.5, 'trailOff']]),
  });
}

// ---- leapAfter: explodes upward after the victim (lock 1.80 -> 2.40) -----------------------------------------------
defineClip('kael.ult.leapAfter', {
  duration: 0.6, breath: 0,
  keys: [
    { t: 0, hips: { pos: [-0.08, -0.36, 0], rot: [0, -22, 0] }, bones: { spine: [0, -4, -6], chest: [0, -6, 2], neck: [0, 12, -10], head: [0, 14, -18], ...LEGS0 },
      ik: { handR: G([-0.02, 1.5, 0.22], dir(180, 20)), ...GROUND, footR: { ...BACK_FOOT_UP, w: 1 } }, grip: 1, curl: [1, 1] },
    // push-off: full extension, toes last off the floor
    { t: 0.1, ease: 'inQuad', hips: { pos: [0.02, 0.04, 0], rot: [0, -18, 0] }, bones: { spine: [0, -2, 6], chest: [0, -3, 10], neck: [0, 8, -14], head: [0, 10, -22] },
      ik: { handR: G([-0.06, 1.8, 0.18], dir(180, 26)), footL: { pos: [FL[0], 0.06, FL[2]], rot: [0, YAW_L, -40], w: 1 }, footR: { pos: [FR[0], 0.08, FR[2]], rot: [0, YAW_R, -44], w: 1 } } },
    // flight: knees tuck, the blade trails low behind, body coiled under the victim
    { t: 0.2, ease: 'outQuad', hips: { pos: [0.02, -0.02, 0], rot: [0, -16, 10] },
      bones: { spine: [0, -2, 4], chest: [0, -3, 8], thighL: [0, 0, 70], shinL: [0, 0, -95], footL: [0, 0, -20], thighR: [0, 0, 20], shinR: [0, 0, -110], footR: [0, 0, -30] },
      ik: { handR: G([-0.12, 1.66, 0.22], dir(-170, 6)), ...AIR } },
    { t: 0.6, ease: 'inOutSine', hips: { pos: [0.02, -0.02, 0], rot: [0, -18, 14] },
      bones: { spine: [0, -2, 6], chest: [0, -3, 10], neck: [0, 8, -10], head: [0, 10, -16], thighL: [0, 0, 80], shinL: [0, 0, -105], thighR: [0, 0, 30], shinR: [0, 0, -115] },
      ik: { handR: G([-0.14, 1.62, 0.24], dir(-172, 0)) } },
  ],
  events: ev([[0.1, 'leap']]),
});

// ---- spin: one full turn in the air, blade at arm's length = the ring of fire (lock 2.40 -> 2.72) ------------------
{
  const T = 0.32;
  const ring = { space: 'chest', pos: [0.18, -0.12, 0.58], aim: [0.42, -0.4, 0.82], up: [0, 1, 0] };
  defineClip('kael.ult.spin', {
    duration: T, breath: 0,
    keys: [
      { t: 0, hips: { pos: [0.02, -0.02, 0], rot: [0, -18, 14] },
        bones: { spine: [0, -2, 6], chest: [0, -3, 10], neck: [0, 8, -10], head: [0, 10, -16], thighL: [0, 0, 80], shinL: [0, 0, -105], footL: [0, 0, -20], thighR: [0, 0, 30], shinR: [0, 0, -115], footR: [0, 0, -30] },
        ik: { handR: G([-0.14, 1.62, 0.24], dir(-172, 0)) }, grip: 1, curl: [1, 1] },
      // the blade swings out to the side and the whole body turns once around it
      { t: 0.06, hips: { rot: [0, 30, 6] }, bones: { spine: [0, 6, 0], chest: [0, 8, 2] }, ik: { handR: ring } },
      { t: 0.14, hips: { rot: [0, 150, 4] } },
      { t: 0.22, hips: { rot: [0, 270, 6] }, ik: { handR: ring } },
      // out of the turn: the blade rises overhead behind for the meteor
      { t: T, ease: 'outQuad', hips: { pos: [0.0, 0.0, 0], rot: [0, 336, 0] }, bones: { spine: [0, -2, 9], chest: [0, -3, 14], neck: [0, 6, -6], head: [0, 8, -8],
        thighL: [0, 0, 60], shinL: [0, 0, -80], thighR: [0, 0, 10], shinR: [0, 0, -70] },
        ik: { handR: G([-0.06, 1.9, 0.14], dir(180, 30)) } },
    ],
    events: ev([[0.04, 'trailOn'], [0.06, 'ring'], [0.3, 'trailOff']]),
  });
}

// ---- meteor: the downward slam that carries the victim into the floor (lock 2.70 -> 4.20; impact clip 0.20) --------
defineClip('kael.ult.meteor', {
  duration: 1.5, breath: 1.2,
  keys: [
    { t: 0, hips: { pos: [0.0, 0.0, 0], rot: [0, -24, 0] }, bones: { spine: [0, -2, 9], chest: [0, -3, 14], neck: [0, 6, -6], head: [0, 8, -8],
      thighL: [0, 0, 60], shinL: [0, 0, -80], footL: [0, 0, -10], thighR: [0, 0, 10], shinR: [0, 0, -70], footR: [0, 0, -20] },
      ik: { handR: G([-0.06, 1.9, 0.14], dir(180, 30)), ...AIR }, grip: 1, curl: [1, 1] },
    { t: 0.1, ease: 'inOutSine', bones: { spine: [0, -2, 12], chest: [0, -3, 17] }, ik: { handR: G([-0.08, 1.94, 0.12], OVER(-6)) } },
    // the fall: blade over the top, legs reach for the floor
    { t: 0.16, ik: { handR: G([0.34, 1.86, 0.08], OVER(80)) }, bones: { thighL: [0, 0, 40], shinL: [0, 0, -40], thighR: [0, 0, 0], shinR: [0, 0, -30] } },
    // impact: blade through the victim into the floor, crater landing, everything driven down
    { t: 0.2, ease: 'inQuad', hips: { pos: [-0.06, -0.42, 0], rot: [0, -14, 0] }, bones: { spine: [0, -2, -26], chest: [0, -2, -20], neck: [0, 4, 14], head: [0, 6, 18], ...LEGS0 },
      ik: { handR: G([0.66, 0.66, 0.05], OVER(178)), footL: { pos: [FL[0] + 0.1, 0, FL[2] - 0.02], rot: [0, YAW_L, 0], w: 1 }, footR: { pos: [FR[0] - 0.06, 0, FR[2] + 0.02], rot: [0, YAW_R, -30], w: 1 } } },
    { t: 0.3, ease: 'outQuad', hips: { pos: [-0.07, -0.4, 0] }, bones: { spine: [0, -2, -24], chest: [0, -2, -18] }, ik: { handR: G([0.66, 0.68, 0.05], OVER(177)) } },
    // held in the crater through the shockwave: heavy breaths, the head comes up slowly
    { t: 0.9, ease: 'inOutSine', hips: { pos: [-0.08, -0.38, 0] }, bones: { spine: [0, -3, -21], chest: [0, -3, -14], neck: [0, 6, 8], head: [0, 8, 8] }, ik: { handR: G([0.65, 0.7, 0.05], OVER(177)) } },
    { t: 1.5, ease: 'inOutSine', hips: { pos: [-0.08, -0.37, 0] }, bones: { spine: [0, -3, -19], chest: [0, -4, -10], neck: [0, 8, 4], head: [0, 10, 2] }, ik: { handR: G([0.65, 0.71, 0.05], OVER(177)) } },
  ],
  events: ev([[0.1, 'trailOn'], [0.2, 'impact', { meteor: true }], [0.2, 'hit', { meteor: true }], [0.24, 'trailOff'], [0.2, 'step', { foot: 'footL' }]]),
});

// ---- rise: stands out of the crater, wrenches the blade free and shoulders it (lock 4.20 -> 5.20) -------------------
defineClip('kael.ult.rise', {
  duration: 1.0, breath: 1.0,
  keys: [
    { t: 0, hips: { pos: [-0.08, -0.37, 0], rot: [0, -14, 0] }, bones: { spine: [0, -3, -19], chest: [0, -4, -10], neck: [0, 8, 4], head: [0, 10, 2] },
      ik: { handR: G([0.65, 0.71, 0.05], OVER(177)), footL: { pos: [FL[0] + 0.1, 0, FL[2] - 0.02], rot: [0, YAW_L, 0] }, footR: { pos: [FR[0] - 0.06, 0, FR[2] + 0.02], rot: [0, YAW_R, -30] } }, grip: 1, curl: [1, 1] },
    // pushes up on the planted blade
    { t: 0.3, ease: 'inOutSine', hips: { pos: [-0.1, -0.24, 0], rot: [0, -16, 0] }, bones: { spine: [0, -3, -8], chest: [0, -4, -2], neck: [0, 10, 0], head: [0, 12, -2] },
      ik: { handR: G([0.6, 0.86, 0.06], OVER(178)) } },
    // wrench: the blade rips out and swings up
    { t: 0.5, ease: 'outCubic', hips: { pos: [-0.08, -0.16, 0.01], rot: [0, -22, 0] }, bones: { spine: [0, -5, -4], chest: [0, -6, 0], neck: [0, 12, 2], head: [0, 16, 0] },
      ik: { handR: G([0.34, 1.3, 0.2], dir(-120, 72)) } },
    // the back foot steps up into the stance, the blade comes to rest on the shoulder
    { t: 0.66, ease: 'inOutSine', ik: { footL: { pos: [FL[0] + 0.05, 0.06, FL[2]], rot: [0, YAW_L, -6] } } },
    { t: 0.76, ease: 'inQuad', ik: { footL: FEET.footL } },
    { t: 0.84, ease: 'inOutSine', ik: { footR: { pos: [FR[0] - 0.02, 0.07, FR[2]], rot: [0, YAW_R, -8] } } },
    { t: 0.92, ease: 'inQuad', ik: { footR: FEET.footR } },
    { t: 1.0, ease: 'inOutSine', hips: STANCE_BODY.hips, bones: STANCE_BODY.bones, ik: { handR: SHOULDER_HAND, ...FEET } },
  ],
  events: ev([[0.5, 'wrench'], [0.76, 'step', { foot: 'footL' }], [0.92, 'step', { foot: 'footR' }]]),
});

export const ULT = ['kael.ult.cuts', 'kael.ult.hurl', 'kael.ult.leapAfter', 'kael.ult.spin', 'kael.ult.meteor', 'kael.ult.rise'];
