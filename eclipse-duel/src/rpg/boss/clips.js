// rpg.idol.* — the motion of 「흑일마신상」. Authored in the 1.9 m character frame ([f, u, s] metres; the actor is scaled
// 3x), every clip from / to the standing pose `rpg.idol.rest` (saber tip resting on the floor ahead of the lead foot).
// Weight rules: slow gather, a held telegraph, a strike of 5-7 frames, a long heavy recovery; the hips lead and the
// blade trails; the feet stay planted (IK) unless a key steps them. Attack clips are sampled at the attack clock, so
// every key time below is also the frame data (index.js keeps the hit windows next to the strike keys).

import { definePose, defineClip, hasClip } from '../../char/index.js';

const FL = [0.36, 0, -0.2], FR = [-0.36, 0, 0.24];
const FEET = { footL: { pos: FL, rot: [0, 14, 0] }, footR: { pos: FR, rot: [0, -45, 0] } };
const H = (pos, aim, up) => ({ pos, aim, up });

/** Timings shared with index.js (seconds on the attack clock). */
export const T = {
  sweep: { dur: 2.7, a: 1.13, b: 1.33 },
  cleave: { dur: 3.2, a: 1.38, hit: 1.44 },
  thrust: { dur: 2.5, a: 1.03, b: 1.15 },
  stomp: { dur: 2.3, hit: 1.05 },
  eclipse: { dur: 3.8, gather: 0.7, casts: [2.05, 2.4, 2.75, 3.1] },
  combo: { dur: 4.5, s1: [0.9, 1.08], s2: [1.76, 1.96], hit: 2.9 },
  enrage: { dur: 3.6, roar: 1.7 },
  wake: 4.2, kneel: 3.4, death: 5,
};

export function defineIdolClips() {
  if (hasClip('rpg.idol.idle')) return;

  // ---- poses ------------------------------------------------------------------------------------------------------
  definePose('rpg.idol.rest', {
    hips: { pos: [-0.03, -0.12, 0], rot: [0, -26, 0] },
    bones: { spine: [0, -8, -3], chest: [1, -6, -2], neck: [0, 10, 2], head: [0, 14, -3] },
    ik: { handR: H([0.26, 1.0, 0.2], [0.78, -0.56, 0.28], [0.56, 0.8, 0]), ...FEET },
    grip: 1, curl: [1, 1],
  });
  // coiled to the right, blade back over the right shoulder (start of the sweep)
  const COIL = (k = 1) => ({
    hips: { pos: [-0.1 - 0.03 * k, -0.18 - 0.03 * k, 0.03], rot: [3, -58 - 6 * k, 2] },
    bones: { spine: [2, -10, 4], chest: [3, -16, 5], neck: [0, 18, 0], head: [0, 30, -4] },
    ik: { handR: H([-0.12 - 0.04 * k, 1.3 + 0.02 * k, 0.36], [-0.72 - 0.08 * k, 0.3 - 0.08 * k, 0.62 - 0.06 * k], [0.3, 0.95, 0.05]) },
  });
  // the three poses of the horizontal cut: blade to the right, ahead, to the left (tip ~0.45 m over the floor in 1.9 m units)
  const CUT_R = { hips: { pos: [-0.04, -0.27, 0.02], rot: [0, -38, 0] }, bones: { spine: [0, -6, -6], chest: [0, -8, -6], neck: [0, 12, 2], head: [0, 16, 0] },
    ik: { handR: H([0.1, 1.0, 0.42], [0.05, -0.28, 0.96], [0.1, 0.95, 0.28]) } };
  const CUT_F = { hips: { pos: [0.07, -0.3, 0], rot: [-2, 6, -3] }, bones: { spine: [-2, 6, -12], chest: [-3, 8, -10], neck: [0, -4, 6], head: [0, -6, 4] },
    ik: { handR: H([0.5, 0.9, 0.1], [0.95, -0.3, 0.08], [0.3, 0.95, 0]) } };
  const CUT_L = { hips: { pos: [0.09, -0.28, -0.02], rot: [-3, 40, -4] }, bones: { spine: [-3, 12, -12], chest: [-4, 12, -10], neck: [0, -12, 6], head: [0, -18, 6] },
    ik: { handR: H([0.36, 0.92, -0.3], [0.2, -0.26, -0.94], [0.05, 0.96, -0.27]) } };
  const PAST_L = { hips: { pos: [0.08, -0.24, -0.03], rot: [-3, 50, -4] }, bones: { spine: [-3, 12, -10], chest: [-4, 12, -8], neck: [0, -14, 4], head: [0, -20, 4] },
    ik: { handR: H([0.2, 1.0, -0.38], [-0.4, -0.12, -0.9], [-0.05, 0.99, -0.1]) } };
  // towering overhead, and the blade buried in the floor
  const HIGH = (k = 0) => ({ hips: { pos: [-0.12 - 0.02 * k, -0.05 + 0.02 * k, 0], rot: [0, -10, 0] }, bones: { spine: [0, -2, 12 + 3 * k], chest: [0, -3, 14 + 3 * k], neck: [0, 4, -8], head: [0, 6, -10] },
    ik: { handR: H([-0.06 - 0.04 * k, 1.9 + 0.04 * k, 0.1], [-0.62 - 0.16 * k, 0.78 - 0.16 * k, 0.05], [0.78, 0.62, 0]) } });
  const BURIED = { hips: { pos: [-0.06, -0.36, -0.01], rot: [0, -12, 0] }, bones: { spine: [0, -2, -26], chest: [0, -2, -22], neck: [0, 4, 14], head: [0, 6, 18] },
    ik: { handR: H([0.5, 0.62, 0.05], [0.94, -0.34, -0.02], [0.34, 0.94, 0]) } };
  // the statue's kneel: one knee down, leaning on the saber, head bowed
  const KNEEL = (bow = 1) => ({
    hips: { pos: [-0.06, -0.56, 0.02], rot: [0, -12, 0] },
    bones: { spine: [0, -2, -14 * bow], chest: [0, -2, -12 * bow], neck: [0, 4, -16 * bow], head: [0, 6, -20 * bow] },
    ik: { handR: H([0.3, 0.94, 0.12], [0.82, -0.52, 0.22], [0.52, 0.85, 0]),
      footL: { pos: [0.34, 0, -0.2], rot: [0, 10, 0] }, footR: { pos: [-0.5, 0.02, 0.24], rot: [0, -20, -55] } },
    grip: 1,
  });

  // ---- idle / walk --------------------------------------------------------------------------------------------------
  defineClip('rpg.idol.idle', {
    duration: 5.2, loop: true, breath: 1.6,
    keys: [
      { t: 0, pose: 'rpg.idol.rest', ease: 'inOutSine' },
      { t: 1.4, ease: 'inOutSine', hips: { pos: [-0.04, -0.132, 0.014], rot: [1.2, -27.5, 0.6] }, bones: { chest: [0.4, -6.6, -1.2], head: [0, 12, -2] }, ik: { handR: { pos: [0.256, 0.992, 0.204] } } },
      { t: 2.6, ease: 'inOutSine', hips: { pos: [-0.03, -0.12, 0], rot: [0, -26, 0] }, bones: { chest: [1, -6, -2], head: [0, 14, -3] }, ik: { handR: { pos: [0.26, 1.0, 0.2] } } },
      { t: 3.9, ease: 'inOutSine', hips: { pos: [-0.02, -0.128, -0.012], rot: [-1.2, -24.6, -0.5] }, bones: { chest: [1.4, -5.2, -2.6], head: [0, 17, -4] }, ik: { handR: { pos: [0.264, 0.994, 0.196] } } },
    ],
  });

  // a slow planted march: the lead foot steps, the body surges onto it, the rear foot is dragged up; the saber tip
  // trails on the stone. No root keys: the mode moves the actor (stats.walk = stride speed x scale).
  {
    const TW = 1.4, v = 0.4, D = v * TW, h = 0.11;
    const yaw = { footL: 14, footR: -45 }, x0 = { footL: FL, footR: FR };
    const keys = [{ t: 0, pose: 'rpg.idol.rest' }];
    const step = (foot, a, b) => {
      const p = x0[foot], m = (a + b) / 2, q = a + (b - a) * 0.3;
      keys.push({ t: a, interp: 'linear', ik: { [foot]: { pos: [p[0] - v * a, 0, p[2]], rot: [0, yaw[foot], 0] } } });
      keys.push({ t: q, ease: 'outQuad', ik: { [foot]: { pos: [p[0] + D * 0.2 - v * q, h * 0.8, p[2]], rot: [0, yaw[foot], -16] } } });
      keys.push({ t: m, ik: { [foot]: { pos: [p[0] + D * 0.55 - v * m, h, p[2]], rot: [0, yaw[foot], 0] } } });
      keys.push({ t: b, ease: 'inQuad', ik: { [foot]: { pos: [p[0] + D - v * b, 0, p[2]], rot: [0, yaw[foot], 5] } } });
    };
    step('footL', 0.06 * TW, 0.4 * TW);
    step('footR', 0.54 * TW, 0.9 * TW);
    const hy = -0.15;
    keys.push({ t: 0.22 * TW, ease: 'inOutSine', hips: { pos: [-0.01, hy + 0.03, -0.02], rot: [-2.5, -22, -1.5] }, bones: { chest: [2, -8, -1] }, ik: { handR: H([0.27, 1.02, 0.2], [0.78, -0.56, 0.28], [0.56, 0.8, 0]) } });
    keys.push({ t: 0.44 * TW, ease: 'inOutSine', hips: { pos: [0.02, hy - 0.035, 0], rot: [0, -26, 0] }, bones: { chest: [1, -6, -4] }, ik: { handR: H([0.26, 0.985, 0.2], [0.78, -0.56, 0.28], [0.56, 0.8, 0]) } });
    keys.push({ t: 0.7 * TW, ease: 'inOutSine', hips: { pos: [-0.04, hy + 0.025, 0.02], rot: [2.5, -30, 1.5] }, bones: { chest: [0, -4, -1] }, ik: { handR: H([0.255, 1.015, 0.2], [0.78, -0.56, 0.28], [0.56, 0.8, 0]) } });
    keys.push({ t: 0.94 * TW, ease: 'inOutSine', hips: { pos: [-0.03, hy - 0.03, 0], rot: [0, -26, 0] }, bones: { chest: [1, -6, -4] }, ik: { handR: H([0.26, 0.99, 0.2], [0.78, -0.56, 0.28], [0.56, 0.8, 0]) } });
    keys.push({ t: TW, interp: 'linear', ik: { footL: { pos: FL, rot: [0, 14, 0] }, footR: { pos: FR, rot: [0, -45, 0] } } });
    defineClip('rpg.idol.walk', {
      duration: TW, loop: true, breath: 0.4, base: 'rpg.idol.rest',
      keys: keys.sort((a, b) => a.t - b.t),
      events: [{ t: 0.4 * TW, name: 'step', data: { foot: 'footL' } }, { t: 0.9 * TW, name: 'step', data: { foot: 'footR' } }],
    });
  }

  // ---- 흑일횡참: the horizontal cut, right to left, a hand above the floor --------------------------------------------
  defineClip('rpg.idol.sweep', {
    duration: T.sweep.dur, breath: 0.2, base: 'rpg.idol.rest',
    keys: [
      { t: 0, pose: 'rpg.idol.rest' },
      { t: 0.6, ease: 'outCubic', ...COIL(0) },
      { t: 1.05, ease: 'inOutSine', ...COIL(1) },
      { t: 1.14, ...CUT_R },
      { t: 1.23, ...CUT_F },
      { t: 1.32, ...CUT_L },
      { t: 1.52, ease: 'outQuad', ...PAST_L },
      { t: 2.05, ease: 'inOutSine', hips: { pos: [0.07, -0.25, -0.03], rot: [-3, 46, -4] }, ik: { handR: H([0.22, 0.98, -0.34], [-0.3, -0.2, -0.93], [-0.05, 0.98, -0.2]) } },
      { t: T.sweep.dur, ease: 'inOutSine', pose: 'rpg.idol.rest' },
    ],
  });

  // ---- 낙일참: the overhead cleave that buries the blade ---------------------------------------------------------------
  defineClip('rpg.idol.cleave', {
    duration: T.cleave.dur, breath: 0.2, base: 'rpg.idol.rest',
    keys: [
      { t: 0, pose: 'rpg.idol.rest' },
      { t: 0.5, ease: 'inOutSine', hips: { pos: [-0.05, -0.2, 0], rot: [0, -22, 0] }, bones: { spine: [0, -6, -8], chest: [0, -4, -6] }, ik: { handR: H([0.28, 0.98, 0.14], [0.82, 0.3, -0.1], [-0.3, 0.95, 0]) } },
      { t: 1.08, ease: 'outCubic', ...HIGH(0) },
      { t: 1.3, ease: 'inOutSine', ...HIGH(1) },
      { t: 1.37, ik: { handR: H([0.26, 1.8, 0.06], [0.45, 0.89, 0], [-0.89, 0.45, 0]) } },
      { t: T.cleave.hit, ease: 'inQuad', ...BURIED },
      { t: 1.53, ease: 'outQuad', hips: { pos: [-0.065, -0.345, -0.01] }, ik: { handR: H([0.49, 0.66, 0.05], [0.95, -0.31, -0.02], [0.31, 0.95, 0]) } },
      { t: 2.2, ease: 'inOutSine', ...BURIED },
      { t: 2.62, ease: 'inOutSine', hips: { pos: [-0.1, -0.22, 0], rot: [0, -20, 0] }, bones: { spine: [0, -6, -10], chest: [0, -5, -6], neck: [0, 8, 4], head: [0, 12, 0] }, ik: { handR: H([0.3, 0.97, 0.14], [0.86, -0.5, 0.1], [0.5, 0.86, 0]) } },
      { t: T.cleave.dur, ease: 'inOutSine', pose: 'rpg.idol.rest' },
    ],
  });

  // ---- 관일자: the levelled thrust ----------------------------------------------------------------------------------
  defineClip('rpg.idol.thrust', {
    duration: T.thrust.dur, breath: 0.2, base: 'rpg.idol.rest',
    keys: [
      { t: 0, pose: 'rpg.idol.rest' },
      { t: 0.5, ease: 'outCubic', hips: { pos: [-0.14, -0.2, 0.02], rot: [0, -52, 0] }, bones: { spine: [0, -10, -2], chest: [2, -14, 0], neck: [0, 20, 0], head: [0, 30, -2] },
        ik: { handR: H([-0.1, 1.22, 0.34], [0.96, -0.2, -0.18], [0.2, 0.98, 0]) } },
      { t: 0.95, ease: 'inOutSine', hips: { pos: [-0.18, -0.22, 0.02], rot: [0, -58, 0] }, ik: { handR: H([-0.17, 1.24, 0.36], [0.97, -0.22, -0.1], [0.22, 0.97, 0]), footL: { pos: [0.38, 0.05, -0.2], rot: [0, 12, -8] } } },
      { t: 1.07, hips: { pos: [0.17, -0.32, 0], rot: [0, 16, -4] }, bones: { spine: [0, 8, -16], chest: [0, 10, -12], neck: [0, -6, 10], head: [0, -10, 12] },
        ik: { handR: H([0.62, 0.98, 0.06], [0.97, -0.24, 0], [0.24, 0.97, 0]), footL: { pos: [0.62, 0, -0.2], rot: [0, 10, 0] } } },
      { t: 1.22, ease: 'outQuad', hips: { pos: [0.18, -0.33, 0] }, ik: { handR: H([0.64, 0.96, 0.06], [0.97, -0.25, 0], [0.25, 0.97, 0]) } },
      { t: 1.75, ease: 'inOutSine', hips: { pos: [0.15, -0.3, 0], rot: [0, 12, -3] }, ik: { handR: H([0.58, 0.95, 0.08], [0.94, -0.34, 0.02], [0.34, 0.94, 0]) } },
      { t: 2.15, ease: 'inOutSine', ik: { footL: { pos: [0.5, 0.06, -0.2], rot: [0, 12, -6] } } },
      { t: T.thrust.dur, ease: 'inOutSine', pose: 'rpg.idol.rest' },
    ],
    events: [{ t: 1.07, name: 'step', data: { foot: 'footL' } }],
  });

  // ---- 진악각: the stomp ---------------------------------------------------------------------------------------------
  defineClip('rpg.idol.stomp', {
    duration: T.stomp.dur, breath: 0.2, base: 'rpg.idol.rest',
    keys: [
      { t: 0, pose: 'rpg.idol.rest' },
      { t: 0.7, ease: 'outCubic', hips: { pos: [-0.14, -0.05, 0.06], rot: [0, -30, 2] }, bones: { spine: [0, -8, 6], chest: [0, -6, 6], neck: [0, 10, -8], head: [0, 14, -12] },
        ik: { handR: H([0.2, 1.1, 0.24], [0.7, -0.5, 0.5], [0.5, 0.85, 0]), footL: { pos: [0.28, 0.5, -0.2], rot: [0, 14, -28] } } },
      { t: 0.95, ease: 'inOutSine', hips: { pos: [-0.16, -0.03, 0.07] }, ik: { footL: { pos: [0.33, 0.56, -0.2], rot: [0, 14, -20] } } },
      { t: T.stomp.hit, ease: 'inQuad', hips: { pos: [0.05, -0.32, -0.02], rot: [0, -18, -3] }, bones: { spine: [0, -6, -16], chest: [0, -4, -12], neck: [0, 8, 10], head: [0, 10, 14] },
        ik: { handR: H([0.3, 0.96, 0.22], [0.74, -0.54, 0.4], [0.54, 0.84, 0]), footL: { pos: [0.46, 0, -0.2], rot: [0, 14, 0] } } },
      { t: 1.16, ease: 'outQuad', hips: { pos: [0.04, -0.28, -0.02] } },
      { t: 1.7, ease: 'inOutSine', hips: { pos: [0.03, -0.26, -0.02], rot: [0, -20, -2] } },
      { t: 2.0, ease: 'inOutSine', ik: { footL: { pos: [0.42, 0.06, -0.2], rot: [0, 14, -6] } } },
      { t: T.stomp.dur, ease: 'inOutSine', pose: 'rpg.idol.rest' },
    ],
    events: [{ t: T.stomp.hit, name: 'step', data: { foot: 'footL' } }],
  });

  // ---- 흑일강림: the free hand calls the black sun down ----------------------------------------------------------------
  {
    const hold = H([0.3, 1.04, 0.16], [0.8, -0.58, 0.16], [0.58, 0.8, 0]);
    defineClip('rpg.idol.eclipse', {
      duration: T.eclipse.dur, breath: 0.3, base: 'rpg.idol.rest',
      keys: [
        { t: 0, pose: 'rpg.idol.rest' },
        { t: 0.55, ease: 'inOutSine', grip: 0, hips: { pos: [-0.05, -0.14, 0], rot: [0, -16, 0] }, ik: { handR: hold, handL: { pos: [0.3, 1.2, -0.3] } } },
        { t: 1.3, ease: 'outCubic', hips: { pos: [-0.08, -0.06, 0], rot: [0, -8, 0] }, bones: { spine: [0, -2, 8], chest: [0, 0, 10], neck: [0, 2, 8], head: [0, 4, 16] }, ik: { handR: hold, handL: { pos: [0.16, 2.06, -0.3] } } },
        { t: 1.9, ease: 'inOutSine', hips: { pos: [-0.09, -0.05, 0] }, bones: { chest: [0, 0, 12] }, ik: { handL: { pos: [0.13, 2.1, -0.3] } } },
        { t: 2.05, ease: 'inQuad', hips: { pos: [-0.02, -0.24, 0], rot: [0, -14, -2] }, bones: { spine: [0, -4, -12], chest: [0, -4, -10], neck: [0, 6, 6], head: [0, 10, 8] }, ik: { handR: hold, handL: { pos: [0.44, 1.02, -0.3] } } },
        { t: 3.2, ease: 'inOutSine', hips: { pos: [-0.03, -0.22, 0] }, ik: { handL: { pos: [0.42, 1.06, -0.3] } } },
        { t: T.eclipse.dur, ease: 'inOutSine', pose: 'rpg.idol.rest', grip: 1 },
      ],
    });
  }

  // ---- 일식연환: cut, back cut, cleave ---------------------------------------------------------------------------------
  defineClip('rpg.idol.combo', {
    duration: T.combo.dur, breath: 0.1, base: 'rpg.idol.rest',
    keys: [
      { t: 0, pose: 'rpg.idol.rest' },
      { t: 0.5, ease: 'outCubic', ...COIL(0) },
      { t: 0.84, ease: 'inOutSine', ...COIL(1) },
      { t: 0.91, ...CUT_R }, { t: 0.99, ...CUT_F }, { t: 1.07, ...CUT_L },
      { t: 1.22, ease: 'outQuad', ...PAST_L },
      // coils on the left for the back cut
      { t: 1.66, ease: 'inOutSine', hips: { pos: [0.06, -0.22, -0.04], rot: [-3, 60, -3] }, bones: { spine: [-2, 12, -4], chest: [-3, 16, -2], neck: [0, -20, 0], head: [0, -32, -2] },
        ik: { handR: H([0.08, 1.12, -0.42], [-0.72, 0.08, -0.69], [0.05, 0.99, 0.05]) } },
      { t: 1.77, ...CUT_L }, { t: 1.86, ...CUT_F }, { t: 1.95, ...CUT_R },
      // the cut carries the blade up over the head
      { t: 2.14, ease: 'outQuad', hips: { pos: [-0.08, -0.14, 0.02], rot: [1, -34, 1] }, bones: { spine: [1, -8, 4], chest: [2, -10, 6], neck: [0, 12, -4], head: [0, 16, -6] }, ik: { handR: H([-0.1, 1.66, 0.3], [-0.66, 0.6, 0.45], [0.6, 0.76, 0.2]) } },
      { t: 2.52, ease: 'inOutSine', ...HIGH(0) },
      { t: 2.76, ease: 'inOutSine', ...HIGH(1) },
      { t: 2.83, ik: { handR: H([0.26, 1.8, 0.06], [0.45, 0.89, 0], [-0.89, 0.45, 0]) } },
      { t: T.combo.hit, ease: 'inQuad', ...BURIED },
      { t: 2.99, ease: 'outQuad', hips: { pos: [-0.065, -0.345, -0.01] }, ik: { handR: H([0.49, 0.66, 0.05], [0.95, -0.31, -0.02], [0.31, 0.95, 0]) } },
      { t: 3.7, ease: 'inOutSine', ...BURIED },
      { t: 4.05, ease: 'inOutSine', hips: { pos: [-0.1, -0.22, 0], rot: [0, -20, 0] }, bones: { spine: [0, -6, -10], chest: [0, -5, -6], neck: [0, 8, 4], head: [0, 12, 0] }, ik: { handR: H([0.3, 0.97, 0.14], [0.86, -0.5, 0.1], [0.5, 0.86, 0]) } },
      { t: T.combo.dur, ease: 'inOutSine', pose: 'rpg.idol.rest' },
    ],
  });

  // ---- 개안: the second eye opens (phase change) -------------------------------------------------------------------------
  defineClip('rpg.idol.enrage', {
    duration: T.enrage.dur, breath: 0, base: 'rpg.idol.rest',
    keys: [
      { t: 0, pose: 'rpg.idol.rest' },
      { t: 0.5, ease: 'outCubic', hips: { pos: [-0.1, -0.3, 0], rot: [0, -20, 0] }, bones: { spine: [0, -4, -24], chest: [0, -4, -18], neck: [0, 6, -14], head: [0, 8, -18] }, ik: { handR: H([0.3, 0.9, 0.16], [0.8, -0.5, 0.33], [0.5, 0.86, 0]) } },
      { t: 1.4, ease: 'inOutSine', hips: { pos: [-0.11, -0.34, 0] }, bones: { spine: [0, -4, -28], chest: [0, -4, -22] }, grip: 1 },
      { t: T.enrage.roar, ease: 'outCubic', grip: 0, hips: { pos: [-0.06, -0.04, 0], rot: [0, -6, 0] }, bones: { spine: [0, 0, 12], chest: [0, 0, 16], neck: [0, 0, 8], head: [0, 0, 20] },
        ik: { handR: H([0.06, 1.34, 0.52], [0.36, -0.6, 0.71], [0.3, 0.8, 0.5]), handL: { pos: [0.06, 1.3, -0.56] } } },
      { t: 2.6, ease: 'inOutSine', hips: { pos: [-0.07, -0.05, 0] }, bones: { chest: [0, 0, 18], head: [0, 0, 22] }, ik: { handR: H([0.05, 1.36, 0.53], [0.36, -0.6, 0.71], [0.3, 0.8, 0.5]), handL: { pos: [0.05, 1.33, -0.57] } } },
      { t: T.enrage.dur, ease: 'inOutSine', pose: 'rpg.idol.rest', grip: 1 },
    ],
  });

  // ---- wake (spawn): the statue lifts its head, rises and takes the saber off the floor ---------------------------
  defineClip('rpg.idol.wake', {
    duration: T.wake, breath: 0, look: false, base: 'rpg.idol.rest',
    keys: [
      { t: 0, ...KNEEL(1), hips: { pos: [-0.06, -0.56, 0.02], rot: [0, -12, 0] } },
      { t: 1.5, ease: 'linear', ...KNEEL(1) },
      { t: 2.1, ease: 'inOutSine', ...KNEEL(-0.25) },
      { t: 2.5, ease: 'inOutSine', ...KNEEL(-0.2) },
      { t: 3.5, ease: 'inOutSine', hips: { pos: [-0.05, -0.2, 0.01], rot: [0, -20, 0] }, bones: { spine: [0, -6, -6], chest: [0, -4, -4], neck: [0, 8, 2], head: [0, 12, 0] },
        ik: { handR: H([0.28, 0.98, 0.16], [0.8, -0.55, 0.24], [0.55, 0.83, 0]), footR: { pos: FR, rot: [0, -45, 0] }, footL: { pos: FL, rot: [0, 14, 0] } } },
      { t: T.wake, ease: 'inOutSine', pose: 'rpg.idol.rest' },
    ],
  });

  // ---- broken guard: driven to one knee, a long opening ----------------------------------------------------------------
  defineClip('rpg.idol.kneel', {
    duration: T.kneel, breath: 2.2, look: false, base: 'rpg.idol.rest',
    keys: [
      { t: 0, pose: 'rpg.idol.rest' },
      { t: 0.16, ease: 'outQuad', hips: { pos: [-0.14, -0.1, 0.02], rot: [-3, -34, 6] }, bones: { spine: [-3, -8, 14], chest: [-4, -8, 16], neck: [3, 6, 14], head: [5, 8, 22] }, ik: { handR: H([0.18, 1.1, 0.24], [0.7, -0.4, 0.58], [0.4, 0.9, 0]) } },
      { t: 0.75, ease: 'inQuad', ...KNEEL(1.2) },
      { t: 0.86, ease: 'outQuad', ...KNEEL(1.5), hips: { pos: [-0.06, -0.6, 0.02], rot: [0, -12, 0] } },
      { t: 1.6, ease: 'inOutSine', ...KNEEL(1.1) },
      { t: 2.4, ease: 'inOutSine', ...KNEEL(1.35) },
      { t: 2.9, ease: 'inOutSine', hips: { pos: [-0.05, -0.3, 0.01], rot: [0, -20, 0] }, bones: { spine: [0, -6, -10], chest: [0, -4, -6], neck: [0, 8, 0], head: [0, 12, -2] }, ik: { footR: { pos: FR, rot: [0, -45, 0] } } },
      { t: T.kneel, ease: 'inOutSine', pose: 'rpg.idol.rest' },
    ],
  });

  // ---- death: back to stone. The knee gives, the head falls, the statue is a statue again ---------------------------
  defineClip('rpg.idol.death', {
    duration: T.death, breath: 0, look: false, base: 'rpg.idol.rest',
    keys: [
      { t: 0, pose: 'rpg.idol.rest' },
      { t: 0.3, ease: 'outCubic', hips: { pos: [-0.16, -0.06, 0.02], rot: [-4, -36, 8] }, bones: { spine: [-4, -8, 16], chest: [-5, -8, 20], neck: [4, 6, 18], head: [6, 8, 26] }, ik: { handR: H([0.14, 1.16, 0.26], [0.66, -0.36, 0.66], [0.36, 0.93, 0]) } },
      { t: 1.1, ease: 'inOutSine', hips: { pos: [-0.12, -0.12, 0.02], rot: [-2, -30, 4] }, bones: { spine: [-2, -8, 6], chest: [-2, -8, 8], neck: [2, 6, 4], head: [3, 8, 6] } },
      { t: 1.9, ease: 'inQuad', ...KNEEL(1) },
      { t: 2.02, ease: 'outQuad', ...KNEEL(1.3), hips: { pos: [-0.06, -0.6, 0.02], rot: [0, -12, 0] } },
      { t: 3.4, ease: 'inOutSine', ...KNEEL(1.7), hips: { pos: [-0.04, -0.6, 0.02], rot: [0, -12, 0] } },
      { t: T.death, ease: 'inOutSine', ...KNEEL(1.9), hips: { pos: [-0.03, -0.61, 0.02], rot: [0, -12, 0] } },
    ],
  });
}
