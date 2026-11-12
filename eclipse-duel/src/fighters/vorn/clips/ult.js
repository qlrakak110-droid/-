// VORN ultimate lock beat clips (천벌의 뇌창 Lance of the Ninefold Storm), played by the choreography with h.play() on
// the lock clock (BALANCE.md section 9). In place: leaps / dives are the choreography's root offsets (h.offset); feet in
// the air are keyed in root space so they ride the offset. Each clip starts on the previous one's last pose.
// Table of start times: NAMES.md.

import { defineClip, definePose } from '../../../char/index.js';
import { STANCE, LARM0, FL, FR, YL, YR, sp, ft } from './common.js';

const B = (spine, chest, neck, head, extra) => ({ spine, chest, neck, head, ...(extra || {}) });
const R = (pos, yaw, pitch = 0) => ft(pos, yaw, { space: 'root', pitch });
const ult = (name, duration, keys, events = [], o = {}) => defineClip(name, {
  duration, breath: o.breath ?? 0.2, gripAt: 'choke', base: 'vorn.stance', loop: !!o.loop, keys, events,
});

// skewer: the dash-thrust's impact pose with both feet planted (the lock starts here)
definePose('vorn.ult.skewerPose', {
  hips: { pos: [0.2, -0.26, 0], rot: [0, -6, -5] }, bones: B([0, 4, -14], [0, 4, -10], [0, -4, 12], [0, -6, 14]),
  ik: { handR: sp([0.94, 1.24, 0.11], [1, 0.02, -0.05], { soft: 0 }), footL: R([0.66, 0, -0.15], YL), footR: R([-0.66, 0, 0.2], YR + 6) },
  grip: 1, curl: [1, 1],
});

// lock 0.05 — lift: the victim is levered up on the spear (hips sink, the rear hand drives the butt down)
ult('vorn.ult.lift', 0.25, [
  { t: 0, pose: 'vorn.ult.skewerPose' },
  { t: 0.12, ease: 'outCubic', hips: { pos: [0.06, -0.32, 0], rot: [0, -18, -2] }, bones: B([0, -4, 2], [0, -4, 6], [0, 6, 8], [0, 8, 12]),
    ik: { handR: sp([0.62, 1.1, 0.18], [0.8, 0.58, -0.12]) } },
  { t: 0.25, ease: 'inOutSine', hips: { pos: [0.04, -0.33, 0], rot: [0, -20, -2] }, bones: B([0, -4, 4], [0, -4, 8], [0, 6, 10], [0, 8, 16]),
    ik: { handR: sp([0.58, 1.1, 0.18], [0.72, 0.68, -0.12]) } },
]);

// lock 0.30 — hurl: the spear flicks skyward and throws the victim up, the body rises onto the toes
ult('vorn.ult.hurl', 0.15, [
  { t: 0, pose: 'vorn.ult.skewerPose', hips: { pos: [0.04, -0.33, 0], rot: [0, -20, -2] }, bones: B([0, -4, 4], [0, -4, 8], [0, 6, 10], [0, 8, 16]),
    ik: { handR: sp([0.58, 1.1, 0.18], [0.72, 0.68, -0.12]) } },
  { t: 0.07, hips: { pos: [0.1, -0.1, 0], rot: [0, -10, -4] }, bones: B([0, -2, 8], [0, -2, 12], [0, 4, 12], [0, 6, 22]),
    ik: { handR: sp([0.62, 1.66, 0.14], [0.45, 0.88, -0.1], { soft: 0 }), footR: R([-0.66, 0.05, 0.2], YR + 6, -30) } },
  { t: 0.15, ease: 'outQuad', hips: { pos: [0.1, -0.08, 0] }, ik: { handR: sp([0.62, 1.72, 0.14], [0.42, 0.9, -0.1], { soft: 0 }) } },
]);

// lock 0.45 — throw: cocks back and hurls the spear straight up after the victim (release at 0.08: hide the weapon)
const THROW_END = {
  hips: { pos: [0.0, -0.14, 0], rot: [0, -22, 0] }, bones: B([0, -4, 8], [0, -4, 10], [0, 6, 14], [0, 8, 24], { upperArmL: [-20, 0, 20], foreArmL: [0, 0, 30] }),
  ik: { handR: sp([0.4, 1.9, 0.2], [0.4, 0.9, -0.08]), handL: { pos: [0.1, 1.1, -0.3], w: 0 }, footL: R([0.66, 0, -0.15], YL), footR: R([-0.66, 0, 0.2], YR + 6) },
  grip: 0, curl: [0.4, 0.3],
};
ult('vorn.ult.throw', 0.45, [
  { t: 0, pose: 'vorn.ult.skewerPose', hips: { pos: [0.1, -0.08, 0], rot: [0, -10, -4] }, bones: B([0, -2, 8], [0, -2, 12], [0, 4, 12], [0, 6, 22]),
    ik: { handR: sp([0.62, 1.72, 0.14], [0.42, 0.9, -0.1]), handL: { pos: [0.3, 1.5, -0.1], w: 0 }, footR: R([-0.66, 0.05, 0.2], YR + 6, -30) } },
  { t: 0.05, ease: 'outCubic', hips: { pos: [-0.04, -0.2, 0], rot: [0, -36, 0] }, bones: B([0, -8, 8], [0, -8, 12], [0, 14, 12], [0, 18, 22]),
    ik: { handR: sp([0.0, 1.58, 0.32], [0.5, 0.85, -0.1]), handL: { pos: [0.42, 1.9, -0.16], w: 1 }, footR: R([-0.66, 0, 0.2], YR + 6) }, grip: 0, curl: [0.3, 1] },
  { t: 0.08, hips: { pos: [0.06, -0.06, 0], rot: [0, -14, -2] }, bones: B([0, 2, 10], [0, 2, 14], [0, 2, 14], [0, 4, 26]),
    ik: { handR: sp([0.5, 2.18, 0.14], [0.42, 0.9, -0.06], { soft: 0 }), handL: { pos: [0.1, 1.2, -0.3], w: 1 }, footR: R([-0.62, 0.05, 0.2], YR + 6, -34) } },
  { t: 0.2, ease: 'outQuad', hips: { pos: [0.06, -0.08, 0] }, ik: { handR: sp([0.56, 2.08, 0.13], [0.5, 0.86, -0.06]) }, curl: [0.4, 0.3] },
  { t: 0.45, ease: 'inOutSine', ...THROW_END },
]);

// lock 0.90 — leap: crouch, arms swing back, spring (the choreography lifts the root from clip 0.15), tuck in the air
const AIR = {
  hips: { pos: [0, -0.06, 0], rot: [0, -24, -6] }, bones: B([0, -6, -6], [0, -6, -4], [0, 10, 14], [0, 12, 24], { upperArmL: [0, 0, 0], foreArmL: [0, 0, 0] }),
  ik: { handR: { pos: [-0.12, 1.3, 0.38], w: 1 }, handL: { pos: [0.62, 2.02, -0.14], w: 1 }, footL: R([0.3, 0.36, -0.14], YL, -20), footR: R([-0.2, 0.2, 0.18], YR, -40) },
  grip: 0, curl: [0.1, 0.6],
};
ult('vorn.ult.leap', 0.4, [
  { t: 0, ...THROW_END },
  { t: 0.14, ease: 'outCubic', hips: { pos: [-0.04, -0.44, 0], rot: [0, -22, 0] }, bones: B([0, -6, -16], [0, -6, -12], [0, 10, 18], [0, 12, 24]),
    ik: { handR: { pos: [-0.38, 0.95, 0.34], w: 1 }, handL: { pos: [-0.32, 0.98, -0.3], w: 1 }, footL: R([0.66, 0, -0.15], YL), footR: R([-0.66, 0, 0.2], YR + 6) } },
  { t: 0.22, hips: { pos: [0.04, 0.02, 0], rot: [0, -20, -2] }, bones: B([0, -2, 4], [0, -2, 6], [0, 6, 12], [0, 8, 22]),
    ik: { handR: { pos: [0.24, 2.0, 0.3], w: 1 }, handL: { pos: [0.4, 2.05, -0.22], w: 1 }, footL: R([0.3, 0.06, -0.15], YL, -30), footR: R([-0.3, 0.04, 0.2], YR, -50) } },
  { t: 0.4, ease: 'outQuad', ...AIR },
]);

// lock 1.30 .. 2.30 — bolts (loop): hanging in the air, the left hand thrust at the victim directs the nine bolts
ult('vorn.ult.bolts', 0.6, [
  { t: 0, ...AIR, ease: 'inOutSine' },
  { t: 0.3, ease: 'inOutSine', hips: { pos: [0, -0.04, 0], rot: [0, -26, -8] }, bones: B([0, -6, -4], [0, -6, -2], [0, 10, 16], [0, 12, 26]),
    ik: { handR: { pos: [-0.16, 1.34, 0.4], w: 1 }, handL: { pos: [0.66, 2.08, -0.14], w: 1 }, footL: R([0.3, 0.4, -0.14], YL, -24), footR: R([-0.22, 0.24, 0.18], YR, -44) } },
], [], { loop: true, breath: 0.6 });

// lock 2.30 — catch: the right hand snaps up and closes on the falling spear (show the weapon at clip 0)
const STORM_HOLD = {
  hips: { pos: [0, -0.04, 0], rot: [0, -20, -8] }, bones: B([0, -6, 8], [0, -6, 12], [0, 8, 14], [0, 10, 24], { ...LARM0 }),
  ik: { handR: sp([0.14, 2.2, 0.17], [0.1, 1, -0.05], { up: [-1, 0, 0] }), handL: { pos: [0.2, 1.9, 0.0], w: 0 }, footL: R([0.24, 0.3, -0.14], YL, -24), footR: R([-0.34, 0.14, 0.2], YR, -46) },
  grip: 1, curl: [1, 1],
};
ult('vorn.ult.catch', 0.1, [
  { t: 0, ...AIR },
  { t: 0.05, ease: 'outCubic', ik: { handR: sp([0.3, 2.16, 0.22], [0.25, 0.96, -0.08], { up: [-1, 0, 0] }) }, curl: [0.3, 0.5] },
  { t: 0.1, ease: 'inOutSine', hips: { pos: [0, -0.05, 0], rot: [0, -22, -7] },
    ik: { handR: sp([0.24, 2.08, 0.2], [0.18, 0.98, -0.06], { up: [-1, 0, 0] }), handL: { pos: [0.5, 1.9, -0.14], w: 0.8 } }, curl: [0.3, 1] },
]);

// lock 2.40 — storm: spear raised to the sky in both hands, the body arched; ends cocked for the dive
ult('vorn.ult.storm', 0.55, [
  { t: 0, ease: 'inOutSine', hips: { pos: [0, -0.05, 0], rot: [0, -22, -7] }, bones: B([0, -6, -4], [0, -6, -2], [0, 10, 16], [0, 12, 26]),
    ik: { handR: sp([0.24, 2.08, 0.2], [0.18, 0.98, -0.06], { up: [-1, 0, 0] }), handL: { pos: [0.5, 1.9, -0.14], w: 0.8 }, footL: R([0.3, 0.36, -0.14], YL, -20), footR: R([-0.2, 0.2, 0.18], YR, -40) }, grip: 0, curl: [0.3, 1] },
  { t: 0.12, ease: 'outCubic', ...STORM_HOLD },
  { t: 0.38, ease: 'inOutSine', ...STORM_HOLD, hips: { pos: [0, -0.03, 0], rot: [0, -20, -10] }, ik: { ...STORM_HOLD.ik, handR: sp([0.12, 2.26, 0.17], [0.08, 1, -0.05], { up: [-1, 0, 0] }) } },
  // cock for the dive: the spear tips back over the head, knees come up
  { t: 0.55, ease: 'inOutSine', hips: { pos: [-0.04, -0.06, 0], rot: [0, -24, -2] }, bones: B([0, -6, 12], [0, -6, 14], [0, 8, 8], [0, 10, 10]),
    ik: { handR: sp([-0.02, 2.08, 0.24], [0.55, 0.82, -0.1]), footL: R([0.36, 0.4, -0.14], YL, -10), footR: R([0.0, 0.28, 0.18], YR, -30) } },
]);

// lock 2.95 — slam: dive (0 .. 0.25), the spear driven down through the victim into the floor (impact 0.25 = lock 3.20),
// kneeling hold, wrench free (0.78) and vault back (airborne at the end, lock 4.10)
const KNEEL = {
  hips: { pos: [0.08, -0.52, 0], rot: [0, -20, -4] }, bones: B([0, -4, -22], [0, -4, -16], [0, 8, 16], [0, 10, 10]),
  ik: { handR: sp([0.74, 0.98, 0.14], [0.45, -0.89, -0.05], { soft: 0 }), footL: R([0.5, 0, -0.15], YL), footR: R([-0.6, 0, 0.2], YR + 20, -60) },
  grip: 1, curl: [1, 1],
};
ult('vorn.ult.slam', 1.15, [
  { t: 0, hips: { pos: [-0.04, -0.06, 0], rot: [0, -24, -2] }, bones: B([0, -6, 12], [0, -6, 14], [0, 8, 8], [0, 10, 10]),
    ik: { handR: sp([-0.02, 2.08, 0.24], [0.55, 0.82, -0.1]), footL: R([0.36, 0.4, -0.14], YL, -10), footR: R([0.0, 0.28, 0.18], YR, -30) }, grip: 1 },
  { t: 0.12, hips: { pos: [0.06, -0.1, 0], rot: [0, -16, -10] }, bones: B([0, -4, -10], [0, -4, -8], [0, 6, 12], [0, 8, 8]),
    ik: { handR: sp([0.6, 1.42, 0.15], [0.55, -0.83, -0.06]), footL: R([0.42, 0.2, -0.15], YL, 10), footR: R([-0.3, 0.3, 0.2], YR, -40) } },
  { t: 0.25, ease: 'inQuad', ...KNEEL },
  { t: 0.33, ease: 'outQuad', hips: { pos: [0.1, -0.55, 0] }, ik: { handR: sp([0.76, 0.94, 0.14], [0.45, -0.89, -0.05], { soft: 0 }) } },
  { t: 0.62, ease: 'inOutSine', hips: { pos: [0.09, -0.53, 0] }, bones: B([0, -4, -20], [0, -4, -14], [0, 10, 20], [0, 12, 16]),
    ik: { handR: sp([0.75, 0.96, 0.14], [0.46, -0.88, -0.05], { soft: 0 }) } },
  // wrench the spear free, gather, spring back
  { t: 0.8, ease: 'outCubic', hips: { pos: [-0.06, -0.4, 0], rot: [0, -30, 2] }, bones: B([0, -8, 6], [0, -8, 8], [0, 12, 8], [0, 14, 6]),
    ik: { handR: sp([0.32, 1.32, 0.24], [0.85, 0.42, -0.2]), footL: R([0.45, 0, -0.15], YL), footR: R([-0.5, 0, 0.2], YR) } },
  { t: 0.92, hips: { pos: [-0.12, -0.46, 0], rot: [0, -30, 6] }, bones: B([0, -8, 10], [0, -8, 12], [0, 12, 4], [0, 14, 2]),
    ik: { handR: sp([0.2, 1.2, 0.28], [0.9, 0.3, -0.24]) } },
  // in the air (the choreography lifts the root from lock 3.75 and brings it down by 4.10): tuck, then legs reach down
  { t: 1.0, ease: 'outQuad', hips: { pos: [-0.1, -0.08, 0], rot: [0, -30, 14] }, bones: B([0, -8, 12], [0, -8, 14], [0, 12, -6], [0, 14, -10]),
    ik: { handR: sp([0.3, 1.4, 0.26], [0.92, 0.2, -0.26]), footL: R([0.35, 0.32, -0.15], YL, -10), footR: R([-0.15, 0.22, 0.2], YR, -30) } },
  { t: 1.15, ease: 'inOutSine', hips: { pos: [-0.06, -0.1, 0], rot: [0, -30, 6] }, bones: B([0, -8, 4], [0, -8, 6], [0, 12, 2], [0, 14, 0]),
    ik: { handR: sp([0.28, 1.2, 0.26], [0.92, -0.1, -0.26]), footL: R([0.4, 0.04, -0.16], YL, -8), footR: R([-0.4, 0.06, 0.2], YR, -14) } },
], [{ t: 0.25, name: 'impact' }]);

// lock 4.10 — land: drops out of the vault into a low crouch, the spear low and forward
const LANDED = {
  hips: { pos: [-0.04, -0.3, 0], rot: [0, -32, 0] }, bones: B([0, -8, -8], [0, -8, -4], [0, 14, 8], [0, 18, 6], { ...LARM0 }),
  ik: { handR: sp([0.22, 0.98, 0.28], [0.9, -0.3, -0.27]), footL: R([0.42, 0, -0.16], YL), footR: R([-0.44, 0, 0.2], YR) },
  grip: 1, curl: [1, 1],
};
ult('vorn.ult.land', 0.3, [
  { t: 0, hips: { pos: [-0.06, -0.1, 0], rot: [0, -30, 6] }, bones: B([0, -8, 4], [0, -8, 6], [0, 12, 2], [0, 14, 0]),
    ik: { handR: sp([0.28, 1.2, 0.26], [0.92, -0.1, -0.26]), footL: R([0.4, 0.04, -0.16], YL, -8), footR: R([-0.4, 0.06, 0.2], YR, -14) }, grip: 1 },
  { t: 0.08, ease: 'inQuad', ...LANDED, hips: { pos: [-0.04, -0.36, 0], rot: [0, -32, 0] } },
  { t: 0.3, ease: 'outQuad', ...LANDED },
], [{ t: 0.08, name: 'step', data: { foot: 'footL' } }]);

// lock 4.40 — twirl: the spear rolls up over the top onto the shoulder, rests a beat, and is swung back down into the
// guard (lock 5.00 = settle)
ult('vorn.ult.twirl', 0.6, [
  { t: 0, ...LANDED },
  { t: 0.1, ease: 'outCubic', hips: { pos: [-0.03, -0.2, 0], rot: [0, -28, 0] }, bones: B([0, -6, -2], [0, -6, 0], [0, 10, 4], [0, 14, 0]),
    ik: { handR: sp([0.4, 1.3, 0.22], [0.6, 0.76, -0.2], { up: [-0.76, 0.6, 0] }), footL: R([0.42, 0, -0.16], YL), footR: R([-0.44, 0, 0.2], YR) } },
  { t: 0.18, ik: { handR: sp([0.34, 1.24, 0.24], [-0.42, 0.88, 0.1], { up: [-0.9, -0.42, 0] }) } },
  { t: 0.27, ease: 'outQuad', hips: { pos: [-0.04, -0.14, 0], rot: [0, -26, 0] }, bones: B([0, -6, 2], [0, -6, 4], [0, 10, 2], [0, 14, -2]),
    ik: { handR: sp([0.32, 1.1, 0.24], [-0.9, 0.34, 0.12], { up: [0.34, 0.94, 0] }) } },
  { t: 0.38, ease: 'inOutSine', ik: { handR: sp([0.33, 1.12, 0.24], [-0.88, 0.38, 0.12], { up: [0.38, 0.92, 0] }) } },
  { t: 0.46, ik: { handR: sp([0.36, 1.24, 0.23], [-0.2, 0.97, 0.05], { up: [-0.97, -0.2, 0] }) } },
  { t: 0.52, ik: { handR: sp([0.36, 1.18, 0.22], [0.66, 0.68, -0.2], { up: [-0.7, 0.68, 0] }) } },
  { t: 0.6, ease: 'inOutSine', pose: 'vorn.stance', ik: { footL: R(FL, YL), footR: R(FR, YR) } },
], [{ t: 0.6, name: 'step', data: { foot: 'footR' } }]);
