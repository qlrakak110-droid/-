// ISKA ultimate lock beats (Fall of the Frozen Star): clips the choreographer plays with h.play() on the lock clock
// (BALANCE.md section 9, iska). Names follow the lock markers; NAMES.md lists when to start each one. The lock places
// the crystal-encased victim 1.7 m in front of her; leaps / descents are h.offset() moves (clips keep the root still).
//
//   iska.ult.crystal        lock 0.01  (0.44)  snap follow-through, blades spun out, coils for the dash
//   iska.ult.orbit          lock 0.42  (1.23)  six alternating cuts, impact at 0.03 / 0.23 / ... / 1.03 (= ticks slash1..6)
//   iska.ult.leap           lock 1.65  (0.30)  crouch and spring (event 'takeoff' at 0.12)
//   iska.ult.constellation  lock 1.95  (0.70)  airborne, arched, blades drawing the star lines
//   iska.ult.starfall       lock 2.65  (1.00)  airborne, pitched down, a fling every 0.08 s (lance1..12)
//   iska.ult.land           lock 3.53  (0.62)  drops and lands crossing both blades: impact at 0.12 (= shatter, lock 3.65)
//   iska.ult.frostWave      lock 4.15  (0.50)  rises, both blades swept wide
//   iska.ult.blendBack      lock 4.65  (0.75)  flicks the frost off the blades, back into the stance

import { defineClip, definePose } from '../../../char/index.js';
import { foot, hand, mir, FL, FR, YAW_L, YAW_R, ev } from './common.js';

const S = 'iska.stance';
const add = (a, d) => [a[0] + d[0], a[1] + d[1], a[2] + d[2]];

// same blade path as the light cuts (moves.js), duplicated here so the ult file stands alone
const CUT = {
  cock: hand([0.06, 1.36, 0.34], [-0.8, 0.38, 0.46], [0.3, -0.92, 0.2], { pole: [0.3, 1.25, 0.8] }),
  over: hand([0.34, 1.4, 0.15], [0.25, 0.95, 0.15], [-0.96, 0.26, 0.1]),
  hit: hand([0.62, 1.1, -0.01], [0.9, 0.1, -0.4], [0.2, 0.5, 0.85]),
  thru: hand([0.5, 0.86, -0.2], [0.35, -0.22, -0.9], [0.72, 0.68, 0.1]),
  mid: hand([0.18, 1.0, 0.24], [0.4, -0.5, 0.76], [0.8, 0.55, -0.1]),
};
const M = (h) => mir(h);

// the snap pose of the opener (frozen_star at 0.75): crouched, both blades driven down crossed
definePose('iska.ult.snapPose', {
  hips: { pos: [0.02, -0.24, 0], rot: [0, -20, 0] },
  bones: { spine: [0, -2, -14], chest: [0, -2, -10], neck: [0, 4, 8], head: [0, 6, 10] },
  ik: {
    handR: hand([0.44, 0.78, -0.04], [0.45, -0.6, -0.66], [0.85, 0.5, 0.15]), handL: hand([0.46, 0.8, 0.06], [0.45, -0.6, 0.66], [0.85, 0.5, -0.15]),
    footL: foot(add(FL, [0.02, -0.02, 0]), YAW_L, 0), footR: foot(FR, YAW_R, -30),
  },
  grip: 0, curl: [1, 1],
});
// sprint start for the first cut: low, right blade cocked, left blade forward low
const ORBIT0 = {
  hips: { pos: [-0.02, -0.22, 0.02], rot: [2, -40, 2] },
  bones: { spine: [2, -8, -8], chest: [2, -12, -4], neck: [0, 16, 6], head: [0, 22, 6] },
  ik: { handR: CUT.cock, handL: hand([0.3, 0.9, -0.16], [0.6, -0.4, 0.7], [0.75, 0.6, -0.2]),
    footL: foot(add(FL, [0.08, -0.02, 0]), YAW_L, -4), footR: foot(add(FR, [-0.04, 0, 0]), YAW_R, -34) },
};

defineClip('iska.ult.crystal', {
  duration: 0.44, breath: 0.3,
  keys: [
    { t: 0, pose: 'iska.ult.snapPose' },
    { t: 0.18, ease: 'outCubic', hips: { pos: [-0.02, -0.12, 0], rot: [0, -24, 0] }, bones: { spine: [0, -4, 4], chest: [0, -6, 6], neck: [0, 8, 2], head: [0, 12, 0] },
      ik: { handR: hand([0.16, 1.0, 0.46], [0.3, -0.7, 0.64], [0.75, 0.65, 0.1]), handL: hand([0.24, 1.0, -0.4], [0.3, -0.7, -0.64], [0.75, 0.65, -0.1]) } },
    { t: 0.44, ease: 'inOutSine', ...ORBIT0 },
  ],
});

// six cuts, 0.2 s apart, alternating hands; the free hand recovers low at its own side, then cocks for its next cut
{
  const keys = [{ t: 0, ...ORBIT0, ik: { ...ORBIT0.ik, handR: CUT.over } }];
  const sides = ['R', 'L', 'R', 'L', 'R', 'L'];
  sides.forEach((s, i) => {
    const t = 0.03 + i * 0.2, R = s === 'R';
    const H = R ? 'handR' : 'handL', O = R ? 'handL' : 'handR';
    const cut = R ? CUT : { hit: M(CUT.hit), thru: M(CUT.thru), cock: M(CUT.cock), over: M(CUT.over), mid: M(CUT.mid) };
    const oc = R ? { cock: M(CUT.cock), over: M(CUT.over), mid: M(CUT.mid) } : CUT;
    const low = i >= 4 ? -0.05 : 0;
    // impact: hips drive the cutting shoulder through, weight onto the front foot
    keys.push({ t, ease: 'inQuad', hips: { pos: [0.1, -0.17 + low, R ? -0.07 : 0.07], rot: R ? [-3, 18, -5] : [3, -50, 5] },
      bones: R ? { spine: [-2, 10, -10], chest: [-3, 10, -8], neck: [0, -12, 6], head: [0, -16, 8] } : { spine: [2, -10, -10], chest: [3, -12, -8], neck: [0, 14, 6], head: [0, 18, 8] },
      ik: { [H]: { ...cut.hit, pos: add(cut.hit.pos, [0, low, 0]) }, [O]: oc.mid, footL: foot(add(FL, [0.08, -0.02, 0]), YAW_L, R ? -4 : -10), footR: foot(add(FR, [-0.04, R ? 0.02 : 0, 0]), YAW_R, R ? -36 : -22) } });
    keys.push({ t: t + 0.07, ease: 'outQuad', ik: { [H]: cut.thru } });
    if (i < sides.length - 1) {
      keys.push({ t: t + 0.11, ease: 'outCubic', hips: { pos: [0.02, -0.1 + low, 0], rot: R ? [0, 4, 0] : [0, -30, 0] },
        ik: { footL: foot(add(FL, [0.1, 0.06, 0]), YAW_L, -24), footR: foot(add(FR, [0.02, 0.05, 0]), YAW_R, -40) } });
      keys.push({ t: t + 0.15, ease: 'inQuad', hips: { pos: [0.0, -0.18 + low, 0], rot: R ? [0, 6, 0] : [0, -32, 0] }, ik: { [O]: oc.cock, [H]: cut.mid } });
      keys.push({ t: t + 0.175, ik: { [O]: oc.over } });
    }
  });
  // settle low after the sixth cut: the crouch the leap starts from
  keys.push({ t: 1.23, ease: 'outCubic', hips: { pos: [-0.04, -0.3, 0], rot: [0, -26, 0] }, bones: { spine: [0, -6, -12], chest: [0, -8, -8], neck: [0, 10, 10], head: [0, 14, 12] },
    ik: { handR: hand([-0.1, 0.86, 0.3], [-0.5, -0.6, 0.62], [-0.3, 0.8, 0.5]), handL: hand([0.0, 0.88, -0.26], [-0.5, -0.6, -0.62], [-0.3, 0.8, -0.5]),
      footL: foot(add(FL, [0.04, 0, 0]), YAW_L, 0), footR: foot(FR, YAW_R, -24) } });
  defineClip('iska.ult.orbit', {
    duration: 1.23, breath: 0, base: S,
    keys: keys.sort((a, b) => a.t - b.t),
    events: ev([[0.03, 'impact'], ...sides.map((s, i) => [0.03 + i * 0.2, 'cut', { hand: s }])]),
  });
}

// crouch and spring (the choreographer lifts her with h.offset from 'takeoff')
const AIR_FEET = (k) => ({
  footL: { space: 'hips', pos: [0.08 + 0.14 * k, -0.9 + 0.36 * k, -0.1], rot: [0, 0, -40] },
  footR: { space: 'hips', pos: [-0.06 + 0.1 * k, -0.86 + 0.26 * k, 0.11], rot: [0, 0, -50] },
});
defineClip('iska.ult.leap', {
  duration: 0.3, breath: 0,
  keys: [
    { t: 0, hips: { pos: [-0.04, -0.3, 0], rot: [0, -26, 0] }, bones: { spine: [0, -6, -12], chest: [0, -8, -8], neck: [0, 10, 10], head: [0, 14, 12] },
      ik: { handR: hand([-0.1, 0.86, 0.3], [-0.5, -0.6, 0.62], [-0.3, 0.8, 0.5]), handL: hand([0.0, 0.88, -0.26], [-0.5, -0.6, -0.62], [-0.3, 0.8, -0.5]),
        footL: foot(add(FL, [0.04, 0, 0]), YAW_L, 0), footR: foot(FR, YAW_R, -24) }, grip: 0, curl: [1, 1] },
    { t: 0.11, ease: 'outCubic', hips: { pos: [-0.06, -0.4, 0], rot: [0, -24, 0] }, bones: { spine: [0, -4, -20], chest: [0, -4, -14], neck: [0, 6, 16], head: [0, 8, 20] },
      ik: { handR: hand([-0.3, 0.82, 0.28], [-0.7, -0.5, 0.5], [-0.4, 0.86, 0.3]), handL: hand([-0.2, 0.84, -0.26], [-0.7, -0.5, -0.5], [-0.4, 0.86, -0.3]),
        footL: foot(add(FL, [0.02, 0, 0]), YAW_L, 0), footR: foot(FR, YAW_R, -20) } },
    // take-off: body long, arms swing up, toes pointed
    { t: 0.19, ease: 'inQuad', hips: { pos: [0.0, 0.02, 0], rot: [0, -20, 8] }, bones: { spine: [0, -2, 8], chest: [0, -2, 10], neck: [0, 4, -8], head: [0, 6, -14] },
      ik: { handR: hand([0.3, 1.86, 0.24], [0.3, 0.9, 0.3], [-0.9, 0.3, 0.2]), handL: hand([0.32, 1.84, -0.2], [0.3, 0.9, -0.3], [-0.9, 0.3, -0.2]),
        footL: { space: 'hips', pos: [0.02, -0.98, -0.09], rot: [0, 0, -50] }, footR: { space: 'hips', pos: [-0.1, -0.95, 0.1], rot: [0, 0, -55] } } },
    { t: 0.3, ease: 'outQuad', hips: { pos: [0.0, 0.0, 0], rot: [0, -20, 14] }, ik: { ...AIR_FEET(0.6) } },
  ],
  events: ev([[0.12, 'takeoff']]),
});

// airborne, arched toward the eclipse, both blades drawing the constellation
defineClip('iska.ult.constellation', {
  duration: 0.7, breath: 0.4,
  keys: [
    { t: 0, hips: { pos: [0, 0, 0], rot: [0, -20, 14] }, bones: { spine: [0, -2, 8], chest: [0, -2, 10], neck: [0, 4, -8], head: [0, 6, -14] },
      ik: { handR: hand([0.3, 1.86, 0.24], [0.3, 0.9, 0.3], [-0.9, 0.3, 0.2]), handL: hand([0.32, 1.84, -0.2], [0.3, 0.9, -0.3], [-0.9, 0.3, -0.2]), ...AIR_FEET(0.6) }, grip: 0, curl: [1, 1] },
    { t: 0.22, ease: 'inOutSine', hips: { rot: [0, -26, 18] }, bones: { chest: [0, -4, 14], head: [0, 8, -20] },
      ik: { handR: hand([0.1, 1.9, 0.5], [0.0, 0.7, 0.72], [-0.95, 0.2, 0.2]), handL: hand([0.44, 1.8, -0.36], [0.6, 0.6, -0.5], [-0.7, 0.7, 0.1]), ...AIR_FEET(0.4) } },
    { t: 0.46, ease: 'inOutSine', hips: { rot: [0, -18, 16] },
      ik: { handR: hand([0.46, 1.78, 0.36], [0.6, 0.6, 0.5], [-0.7, 0.7, -0.1]), handL: hand([0.08, 1.88, -0.48], [0.0, 0.7, -0.72], [-0.95, 0.2, -0.2]), ...AIR_FEET(0.5) } },
    { t: 0.7, ease: 'inOutSine', hips: { rot: [0, -22, 18] }, bones: { chest: [0, -4, 14], head: [0, 8, -22] },
      ik: { handR: hand([0.12, 1.98, 0.26], [0.1, 0.95, 0.3], [-0.95, 0.1, 0.2]), handL: hand([0.14, 1.96, -0.22], [0.1, 0.95, -0.3], [-0.95, 0.1, -0.2]), ...AIR_FEET(0.45) } },
  ],
});

// pitched down over the crystal, alternating flings: right on even lances, left on odd (a release every 0.08 s)
{
  const relR = hand([0.58, 0.9, 0.14], [0.85, 0.45, -0.25], [-0.45, 0.88, 0.1]);
  const cockR = hand([0.1, 1.46, 0.3], [-0.8, 0.4, 0.45], [0.3, -0.9, 0.3], { pole: [0.3, 1.3, 0.75] });
  const keys = [{ t: 0, hips: { pos: [0, 0, 0], rot: [0, -22, -30] }, bones: { spine: [0, -2, -8], chest: [0, -2, -6], neck: [0, 4, 4], head: [0, 6, 10] },
    ik: { ...AIR_FEET(0.3), footL: { space: 'hips', pos: [-0.12, -0.86, -0.1], rot: [0, 0, -40] }, footR: { space: 'hips', pos: [0.1, -0.7, 0.11], rot: [0, 0, -50] } }, grip: 0, curl: [1, 1] }];
  for (let i = 0; i <= 12; i++) {
    const t = Math.min(1, i * 0.08), r = i % 2 === 0;
    keys.push({ t: t + (i === 0 ? 0.0001 : 0), ease: 'inQuad', hips: { rot: [0, r ? -12 : -34, -30] },
      ik: { handR: r ? relR : cockR, handL: r ? mir(cockR) : mir(relR) } });
  }
  defineClip('iska.ult.starfall', {
    duration: 1.0, breath: 0,
    keys: keys.sort((a, b) => a.t - b.t),
    events: ev(Array.from({ length: 12 }, (_, i) => [i * 0.08 + 0.001, 'fling', { hand: i % 2 ? 'L' : 'R', index: i + 1 }])),
  });
}

// the descent and the landing: both blades driven down crossed as she touches down (impact .12 = shatter)
defineClip('iska.ult.land', {
  duration: 0.62, breath: 0.2,
  keys: [
    { t: 0, hips: { pos: [0, 0.02, 0], rot: [0, -22, 4] }, bones: { spine: [0, -2, 4], chest: [0, -2, 6], neck: [0, 4, 0], head: [0, 6, 4] },
      ik: { handR: hand([0.28, 1.8, 0.18], [-0.3, 0.6, 0.74], [0.95, 0.3, 0.1]), handL: hand([0.3, 1.78, -0.14], [-0.3, 0.6, -0.74], [0.95, 0.3, -0.1]),
        footL: { space: 'hips', pos: [0.14, -0.94, -0.1], rot: [0, 0, -30] }, footR: { space: 'hips', pos: [-0.1, -0.9, 0.11], rot: [0, 0, -40] } }, grip: 0, curl: [1, 1] },
    { t: 0.09, ik: { handR: hand([0.4, 1.4, 0.12], [0.5, -0.86, 0.0], [-0.86, -0.5, 0.0]), handL: hand([0.42, 1.38, -0.1], [0.5, -0.86, 0.0], [-0.86, -0.5, 0.0]) } },
    { t: 0.12, ease: 'inQuad', hips: { pos: [-0.02, -0.44, 0], rot: [0, -18, 0] }, bones: { spine: [0, -2, -20], chest: [0, -2, -14], neck: [0, 4, 12], head: [0, 6, 16] },
      ik: { handR: hand([0.6, 0.46, 0.04], [0.15, -0.9, -0.4], [-0.98, -0.15, 0.1], { pole: [0.2, 0.7, 0.6] }), handL: hand([0.62, 0.46, -0.02], [0.15, -0.9, 0.4], [-0.98, -0.15, -0.1], { pole: [0.2, 0.7, -0.6] }),
        footL: foot([0.36, 0, -0.14], 14, 0), footR: foot([-0.36, 0, 0.15], -38, -60) } },
    { t: 0.24, ease: 'outQuad', hips: { pos: [-0.03, -0.46, 0] }, bones: { neck: [0, 4, 8], head: [0, 6, 10] } },
    { t: 0.62, ease: 'inOutSine', hips: { pos: [-0.03, -0.45, 0] }, bones: { neck: [0, 4, 4], head: [0, 6, 2] } },
  ],
  events: ev([[0.12, 'impact'], [0.12, 'step', { foot: 'footL' }]]),
});

// rises, both blades swept wide: the frost wave rolls out
defineClip('iska.ult.frostWave', {
  duration: 0.5, breath: 0.6,
  keys: [
    { t: 0, hips: { pos: [-0.03, -0.45, 0], rot: [0, -18, 0] }, bones: { spine: [0, -2, -20], chest: [0, -2, -14], neck: [0, 4, 4], head: [0, 6, 2] },
      ik: { handR: hand([0.6, 0.46, 0.04], [0.15, -0.9, -0.4], [-0.98, -0.15, 0.1], { pole: [0.2, 0.7, 0.6] }), handL: hand([0.62, 0.46, -0.02], [0.15, -0.9, 0.4], [-0.98, -0.15, -0.1], { pole: [0.2, 0.7, -0.6] }),
        footL: foot([0.36, 0, -0.14], 14, 0), footR: foot([-0.36, 0, 0.15], -38, -60) }, grip: 0, curl: [1, 1] },
    { t: 0.22, ease: 'outCubic', hips: { pos: [-0.03, -0.2, 0], rot: [0, -22, 0] }, bones: { spine: [0, -4, 0], chest: [0, -6, 4], neck: [0, 8, 0], head: [0, 12, -2] },
      ik: { handR: hand([0.5, 1.1, 0.4], [0.6, 0.1, 0.8], [-0.8, 0.2, 0.6]), handL: hand([0.52, 1.08, -0.38], [0.6, 0.1, -0.8], [-0.8, 0.2, -0.6]),
        footR: foot([-0.34, 0.01, 0.15], -40, -24) } },
    { t: 0.5, ease: 'outQuad', hips: { pos: [-0.03, -0.1, 0], rot: [0, -24, 0] }, bones: { spine: [0, -4, 4], chest: [0, -6, 8], neck: [0, 8, -2], head: [0, 12, -4] },
      ik: { handR: hand([0.12, 1.14, 0.6], [0.1, -0.2, 0.97], [-0.9, 0.4, 0.1]), handL: hand([0.2, 1.12, -0.56], [0.1, -0.2, -0.97], [-0.9, 0.4, -0.1]),
        footL: foot(FL, YAW_L, -6), footR: foot([-0.32, 0.01, 0.15], YAW_R, -20) } },
  ],
});

// flicks the frost off both blades, back into the stance
defineClip('iska.ult.blendBack', {
  duration: 0.75, breath: 0.8,
  keys: [
    { t: 0, hips: { pos: [-0.03, -0.1, 0], rot: [0, -24, 0] }, bones: { spine: [0, -4, 4], chest: [0, -6, 8], neck: [0, 8, -2], head: [0, 12, -4] },
      ik: { handR: hand([0.12, 1.14, 0.6], [0.1, -0.2, 0.97], [-0.9, 0.4, 0.1]), handL: hand([0.2, 1.12, -0.56], [0.1, -0.2, -0.97], [-0.9, 0.4, -0.1]),
        footL: foot(FL, YAW_L, -6), footR: foot([-0.32, 0.01, 0.15], YAW_R, -20) }, grip: 0, curl: [1, 1] },
    // gather: blades raised and crossed before the chest
    { t: 0.16, ease: 'outCubic', ik: { handR: hand([0.26, 1.3, 0.1], [0.3, 0.76, -0.58], [0.9, -0.12, 0.42]), handL: hand([0.27, 1.28, -0.04], [0.3, 0.76, 0.58], [0.9, -0.12, -0.42]) } },
    // the flick: both wrists snap down and out
    { t: 0.24, ease: 'inQuad', hips: { pos: [-0.02, -0.12, 0] }, bones: { neck: [0, 8, 4], head: [0, 12, 6] },
      ik: { handR: hand([0.24, 0.92, 0.36], [0.3, -0.8, 0.5], [0.8, 0.5, 0.2]), handL: hand([0.28, 0.94, -0.3], [0.3, -0.8, -0.5], [0.8, 0.5, -0.2]) } },
    { t: 0.4, ease: 'outQuad', ik: { handR: hand([0.23, 0.9, 0.34], [0.32, -0.82, 0.48]), handL: hand([0.27, 0.92, -0.28], [0.32, -0.82, -0.48]) } },
    { t: 0.75, ease: 'inOutSine', pose: S },
  ],
  events: ev([[0.24, 'flick']]),
});
