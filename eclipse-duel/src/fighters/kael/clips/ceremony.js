// KAEL — round intro, victory, defeat and hit reactions. Every clip starts or ends in kael.stance so the game's
// crossfades into idle / out of hit-stun have nothing to bridge.

import { defineClip, definePose } from '../../../char/index.js';
import { FL, FR, YAW_L, YAW_R, FEET, SHOULDER_HAND, dir, grip, stance } from './common.js';

const G = (pos, o) => grip(pos, o.aim || o);                   // blade direction (vector or plane sample), natural roll
/** Blade planted point-down in front, both gauntlets stacked on the hilt (left on the pommel: clips use gripAt 'pommel'). */
const PLANTED_HAND = { pos: [0.4, 1.12, 0.02], aim: dir(0, -86), up: [-1, -0.07, 0] };

// warden at rest: the sword planted before him, standing tall, head bowed over the hilt
definePose('kael.vigil', {
  hips: { pos: [-0.02, -0.04, 0], rot: [0, -10, 0] },
  bones: { spine: [0, -2, -2], chest: [0, -3, 2], neck: [0, 4, -10], head: [0, 6, -18], shoulderR: [-4, 0, 0], shoulderL: [-4, 0, 0] },
  ik: { handR: PLANTED_HAND, footL: { pos: [0.16, 0, -0.17], rot: [0, 10, 0] }, footR: { pos: [-0.14, 0, 0.18], rot: [0, -26, 0] } },
  grip: 1, curl: [1, 1],
});

// ---- intro: vigil, the head rises, he wrenches the blade out of the stone and shoulders it (2.4 s) ------------------
defineClip('kael.intro', {
  duration: 2.4, breath: 1.1, gripAt: 'pommel',
  keys: [
    { t: 0, pose: 'kael.vigil' },
    { t: 0.5, ease: 'inOutSine', pose: 'kael.vigil', bones: { neck: [0, 4, -9], head: [0, 6, -16] } },
    // the head comes up: eyes on the opponent
    { t: 1.0, ease: 'inOutSine', bones: { neck: [0, 6, 2], head: [0, 8, 2], chest: [0, -3, 5] } },
    // sinks, grips, rips it free
    { t: 1.25, ease: 'inOutSine', hips: { pos: [-0.04, -0.12, 0], rot: [0, -14, 0] }, ik: { handR: { ...PLANTED_HAND, pos: [0.4, 1.02, 0.03] } } },
    { t: 1.45, ease: 'outCubic', hips: { pos: [-0.04, -0.06, 0], rot: [0, -20, 0] }, bones: { spine: [0, -4, 2], chest: [0, -5, 6] },
      ik: { handR: G([0.3, 1.36, 0.18], dir(-30, 68)), footL: { pos: [0.26, 0.09, -0.17], rot: [0, 12, -6] } } },
    // steps out into the stance as the blade drops onto the right pauldron
    { t: 1.62, ease: 'inQuad', ik: { footL: FEET.footL } },
    { t: 1.75, ease: 'inOutSine', ik: { footR: { pos: [FR[0] + 0.1, 0.09, FR[2]], rot: [0, YAW_R, -6] } } },
    { t: 1.88, ease: 'inQuad', ik: { footR: FEET.footR } },
    { t: 1.95, ease: 'inOutSine', ...stance(), hips: { pos: [-0.03, -0.14, 0], rot: [0, -25, 0] } },
    { t: 2.4, ease: 'inOutSine', ...stance() },
  ],
  events: [{ t: 1.45, name: 'wrench' }, { t: 1.62, name: 'step', data: { foot: 'footL' } }, { t: 1.88, name: 'step', data: { foot: 'footR' } }],
});

// ---- victory: the blade swung down and planted, both hands on the pommel, chin raised (2.0 s, holds) --------------
defineClip('kael.victory', {
  duration: 2.0, breath: 1.4, gripAt: 'pommel',
  keys: [
    { t: 0, ...stance() },
    { t: 0.3, ease: 'outCubic', hips: { pos: [-0.04, -0.12, 0], rot: [0, -20, 0] }, ik: { handR: G([0.34, 1.62, 0.16], dir(-20, 80)) } },
    { t: 0.5, ease: 'inQuad', hips: { pos: [-0.03, -0.1, 0], rot: [0, -12, 0] }, ik: { handR: { ...PLANTED_HAND, pos: [0.4, 1.06, 0.03] }, footL: { pos: [0.24, 0.09, -0.17], rot: [0, 10, -6] } } },
    { t: 0.66, ease: 'inQuad', ik: { footL: { pos: [0.16, 0, -0.17], rot: [0, 10, 0] } } },
    { t: 0.8, ease: 'inOutSine', ik: { footR: { pos: [-0.24, 0.09, 0.18], rot: [0, -26, -6] } } },
    { t: 0.92, ease: 'inQuad', pose: 'kael.vigil', bones: { neck: [0, 4, 2], head: [0, 6, 4] } },
    { t: 2.0, ease: 'inOutSine', pose: 'kael.vigil', hips: { pos: [-0.02, -0.03, 0], rot: [0, -10, 0] }, bones: { chest: [0, -3, 6], neck: [0, 4, 6], head: [0, 6, 10] } },
  ],
  events: [{ t: 0.5, name: 'plant' }, { t: 0.66, name: 'step', data: { foot: 'footL' } }, { t: 0.92, name: 'step', data: { foot: 'footR' } }],
});

// ---- defeat: the knees give, down onto the right knee, leaning on the planted blade, head hung (1.8 s, holds) ------
defineClip('kael.defeat', {
  duration: 1.8, breath: 1.8, gripAt: 'pommel',
  keys: [
    { t: 0, ...stance() },
    { t: 0.35, ease: 'inOutSine', hips: { pos: [-0.06, -0.2, 0], rot: [0, -16, 0] }, bones: { spine: [0, -3, -8], chest: [0, -4, -8], neck: [0, 6, -6], head: [0, 8, -10] },
      ik: { handR: G([0.42, 1.0, 0.04], dir(0, -70)) } },
    { t: 0.6, ease: 'inQuad', ik: { handR: { ...PLANTED_HAND, pos: [0.44, 0.86, 0.03] } } },
    // down on one knee: the right knee to the floor, the left foot planted ahead
    { t: 1.1, ease: 'inOutCubic', hips: { pos: [-0.1, -0.5, 0.02], rot: [0, -16, 0] }, bones: { spine: [0, -3, -14], chest: [0, -4, -14], neck: [0, 4, -16], head: [0, 6, -26], shoulderR: [6, 0, 0], shoulderL: [6, 0, 0] },
      ik: { handR: { ...PLANTED_HAND, pos: [0.46, 0.76, 0.03] }, footL: { pos: [0.34, 0, FL[2]], rot: [0, YAW_L, 0] }, footR: { pos: [-0.36, 0, FR[2]], rot: [0, YAW_R + 10, -60], pole: [0.2, 0.0, 0.3] } } },
    { t: 1.8, ease: 'inOutSine', hips: { pos: [-0.1, -0.52, 0.02] }, bones: { spine: [0, -3, -16], chest: [0, -4, -16], neck: [0, 4, -18], head: [0, 6, -30] } },
  ],
  events: [{ t: 0.6, name: 'plant' }, { t: 1.1, name: 'kneel' }],
});

// ---- hit reactions ------------------------------------------------------------------------------------------------
defineClip('kael.hitLight', {
  duration: 0.34, breath: 0.4,
  keys: [
    { t: 0, ...stance() },
    { t: 0.05, ease: 'outQuad', hips: { pos: [-0.07, -0.15, 0.01], rot: [-2, -30, 4] }, bones: { spine: [-2, -8, 7], chest: [-3, -7, 10], neck: [3, 18, 10], head: [4, 22, 14] },
      ik: { handR: { pos: [0.12, 1.4, 0.26], aim: SHOULDER_HAND.aim } } },
    { t: 0.34, ease: 'inOutSine', ...stance() },
  ],
});

defineClip('kael.hitHeavy', {
  duration: 0.8, breath: 0.6,
  keys: [
    { t: 0, ...stance() },
    // rocked back: chest and head snap back, the blade lifts off the shoulder, the front foot slides back
    { t: 0.06, ease: 'outQuad', hips: { pos: [-0.12, -0.13, 0.01], rot: [-4, -36, 6] }, bones: { spine: [-4, -10, 12], chest: [-5, -8, 15], neck: [4, 14, 16], head: [6, 18, 24], shoulderR: [0, 0, 6], shoulderL: [0, 0, 6] },
      ik: { handR: G([0.2, 1.44, 0.3], dir(-150, 50)) } },
    { t: 0.16, ease: 'inOutSine', hips: { pos: [-0.12, -0.19, 0.01], rot: [-3, -34, 5] }, bones: { spine: [-2, -8, 4], chest: [-3, -8, 6], neck: [2, 14, 6], head: [3, 18, 4], shoulderR: [0, 0, 0], shoulderL: [0, 0, 0] },
      ik: { handR: G([0.18, 1.34, 0.28], dir(-155, 45)), footR: { pos: [FR[0] - 0.1, 0.06, FR[2]], rot: [0, YAW_R, 6] } } },
    // a stagger step back with the rear foot to catch the weight
    { t: 0.26, ease: 'inQuad', ik: { footR: { pos: [FR[0] - 0.14, 0, FR[2]], rot: [0, YAW_R, 0] } } },
    { t: 0.42, ease: 'inOutSine', hips: { pos: [-0.08, -0.16, 0], rot: [-1, -28, 2] }, bones: { spine: [0, -6, -3], chest: [0, -6, -2] } },
    { t: 0.52, ease: 'inOutSine', ik: { footR: { pos: [FR[0] - 0.08, 0.05, FR[2]], rot: [0, YAW_R, -6] } } },
    { t: 0.62, ease: 'inQuad', ik: { footR: FEET.footR } },
    { t: 0.8, ease: 'inOutSine', ...stance() },
  ],
  events: [{ t: 0.26, name: 'step', data: { foot: 'footR' } }, { t: 0.62, name: 'step', data: { foot: 'footR' } }],
});

export const CEREMONY = ['kael.intro', 'kael.victory', 'kael.defeat', 'kael.hitLight', 'kael.hitHeavy'];
