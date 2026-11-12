// VORN round ceremony clips: intro (spear planted upright, wrenched up into the guard), victory (spear planted, chin up),
// defeat (sinks to one knee on the planted spear).

import { defineClip, definePose } from '../../../char/index.js';
import { FL, FR, YL, YR, sp, ft } from './common.js';

const B = (spine, chest, neck, head, extra) => ({ spine, chest, neck, head, ...(extra || {}) });
const R = (pos, yaw, pitch = 0) => ft(pos, yaw, { space: 'root', pitch });

// sentinel: standing tall, the spear planted upright at his right side (butt on the floor), left fist on the hip
definePose('vorn.sentinel', {
  hips: { pos: [-0.01, -0.025, 0], rot: [0, -16, 0] },
  bones: B([0, -4, 1], [-1, -4, 3], [0, 8, 0], [0, 12, -2], { upperArmL: [-24, 10, -12], foreArmL: [0, 0, 112], handL: [0, 0, -10] }),
  ik: { handR: sp([0.3, 0.92, 0.3], [0.05, 1, 0.03], { up: [-1, 0, 0] }), footL: R([0.14, 0, -0.13], 10), footR: R([-0.06, 0, 0.15], -22) },
  grip: 0, curl: [1, 1],
});

defineClip('vorn.intro', {
  duration: 2.2, breath: 0.9, gripAt: 'choke', base: 'vorn.stance',
  keys: [
    { t: 0, pose: 'vorn.sentinel', bones: { neck: [0, 6, -8], head: [0, 8, -16] } },
    // the head comes up
    { t: 0.7, ease: 'inOutSine', bones: { neck: [0, 8, 2], head: [0, 12, 2] } },
    // wrench the spear out of the floor
    { t: 1.0, ease: 'inOutSine', hips: { pos: [-0.02, -0.06, 0], rot: [0, -20, 0] }, ik: { handR: sp([0.32, 1.1, 0.3], [0.06, 1, 0.03], { up: [-1, 0, 0] }) } },
    { t: 1.18, ease: 'outCubic', hips: { pos: [-0.04, -0.1, 0], rot: [0, -26, 0] }, bones: B([0, -6, -1], [0, -6, 1], [0, 10, 2], [0, 14, 0], { upperArmL: [0, 0, 0], foreArmL: [0, 0, 0], handL: [0, 0, 0] }),
      ik: { handR: sp([0.44, 1.42, 0.24], [0.62, 0.76, -0.18]) }, grip: 0 },
    // swung down into the low guard, the left hand catches the haft, feet step out into the stance
    { t: 1.42, hips: { pos: [-0.03, -0.12, 0], rot: [0, -32, 0] }, bones: B([0, -8, -4], [1, -8, -2], [0, 12, 2], [0, 16, -4]),
      ik: { handR: sp([0.32, 1.0, 0.23], [0.86, -0.46, -0.24]) }, grip: 1 },
    { t: 1.15, ik: { footL: R([0.14, 0, -0.13], 10) } },
    { t: 1.25, ease: 'outQuad', ik: { footL: R([0.26, 0.07, -0.14], 11, -10) } },
    { t: 1.38, ease: 'inQuad', ik: { footL: R(FL, YL) } },
    { t: 1.3, ik: { footR: R([-0.06, 0, 0.15], -22) } },
    { t: 1.42, ease: 'outQuad', ik: { footR: R([-0.22, 0.06, 0.18], -36, -8) } },
    { t: 1.56, ease: 'inQuad', ik: { footR: R(FR, YR) } },
    { t: 1.75, ease: 'inOutSine', hips: { pos: [-0.03, -0.11, 0], rot: [0, -30, 0] } },
    { t: 2.2, ease: 'inOutSine', pose: 'vorn.stance' },
  ],
  events: [{ t: 1.0, name: 'wrench' }, { t: 1.38, name: 'step', data: { foot: 'footL' } }, { t: 1.56, name: 'step', data: { foot: 'footR' } }],
});

defineClip('vorn.victory', {
  duration: 2.0, breath: 1.2, gripAt: 'choke', base: 'vorn.stance',
  keys: [
    { t: 0, pose: 'vorn.stance' },
    // the spear rises upright, the feet gather under him
    { t: 0.35, ease: 'outCubic', hips: { pos: [-0.02, -0.06, 0], rot: [0, -20, 0] }, ik: { handR: sp([0.36, 1.5, 0.28], [0.12, 0.99, 0.0], { up: [-1, 0, 0] }) }, grip: 0 },
    { t: 0.3, ik: { footR: R(FR, YR) } },
    { t: 0.42, ease: 'outQuad', ik: { footR: R([-0.18, 0.07, 0.17], -30, -10) } },
    { t: 0.55, ease: 'inQuad', ik: { footR: R([-0.06, 0, 0.15], -22) } },
    { t: 0.45, ik: { footL: R(FL, YL) } },
    { t: 0.6, ease: 'outQuad', ik: { footL: R([0.24, 0.05, -0.14], 11, -8) } },
    { t: 0.72, ease: 'inQuad', ik: { footL: R([0.14, 0, -0.13], 10) } },
    // planted: the butt strikes the floor; chin up, fist on the hip
    { t: 0.62, ease: 'inQuad', pose: 'vorn.sentinel', ik: { footL: R([0.2, 0.03, -0.13], 10), footR: R([-0.06, 0, 0.15], -22) } },
    { t: 1.1, ease: 'inOutSine', bones: { chest: [-1, -4, 6], neck: [0, 8, 6], head: [0, 12, 10] } },
    { t: 2.0, ease: 'inOutSine', bones: { chest: [-1, -4, 7], neck: [0, 8, 7], head: [0, 12, 12] } },
  ],
  events: [{ t: 0.62, name: 'plant' }, { t: 0.72, name: 'step', data: { foot: 'footL' } }],
});

defineClip('vorn.defeat', {
  duration: 1.6, breath: 1.6, gripAt: 'choke', base: 'vorn.stance',
  keys: [
    { t: 0, pose: 'vorn.stance' },
    // the spear is planted upright in front, the body sags onto it, the rear knee drops to the floor
    { t: 0.35, ease: 'inOutSine', hips: { pos: [-0.04, -0.2, 0], rot: [0, -24, 0] }, ik: { handR: sp([0.42, 1.3, 0.24], [0.14, 0.98, -0.06], { up: [-1, 0, 0] }) }, grip: 0 },
    { t: 0.9, ease: 'inOutCubic', hips: { pos: [-0.06, -0.56, 0], rot: [0, -22, 0] }, bones: B([0, -4, -18], [0, -4, -14], [0, 2, -12], [0, 4, -26], { upperArmL: [-10, 0, 20], foreArmL: [0, 0, 40] }),
      ik: { handR: sp([0.46, 0.98, 0.24], [0.1, 0.99, -0.05], { up: [-1, 0, 0] }), footL: R([0.38, 0, -0.15], YL), footR: R([-0.42, 0, 0.2], YR + 20, -62) } },
    { t: 1.6, ease: 'inOutSine', hips: { pos: [-0.06, -0.58, 0] }, bones: { head: [0, 4, -32] } },
  ],
});
