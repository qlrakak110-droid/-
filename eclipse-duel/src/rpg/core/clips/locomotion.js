// rpg.<hero>.run / rpg.<hero>.sprint — alternating gaits with a flight phase, authored per hero at exactly its
// run / sprint speed (HEROES in ../hero.js), so they play at 1x with planted feet: while a foot is on the floor it
// moves back in root space at the root speed (linear keys); the swing lifts the heel, passes under the hips and
// reaches forward. The view scales playback by (actual speed / clip root speed) while accelerating.
//
// Carry poses (third-person camera: the back and the weapon read from behind):
//   KAEL  the great blade stays on the right shoulder in one hand, the left arm pumps, heavy forward lean
//   ISKA  both blades swept back and low (the points trail behind her), long light bounds
//   VORN  the spear levelled at the right hip in one hand, point leading, the left arm pumps

import { defineClip } from '../../../char/index.js';
import { MOCAP_RUN as MC } from './mocap_run.js';
import { SHOULDER_HAND as K_HAND } from '../../../fighters/kael/clips/common.js';
import { hand as iHand } from '../../../fighters/iska/clips/common.js';
import { sp as vSpear } from '../../../fighters/vorn/clips/common.js';

const sorted = (keys) => keys.sort((a, b) => a.t - b.t);

/**
 * Build a run cycle.
 * @param {string} name clip name
 * @param {object} P
 *   v        root speed (m/s)                T         cycle period (s, two steps)
 *   land     foot strike ahead of the hips (m)        stance    fraction of a STEP the foot is planted (0.35 .. 0.5)
 *   lift     heel kick height behind (m)     reach     knee-drive / reach height in front (m)
 *   track    half distance between the foot tracks (m)
 *   hipY     hips height offset at mid-stance (m, negative = lower), bounce = extra height in flight
 *   lean     forward lean of the spine (deg), yaw = base hips yaw (deg), twist = pelvis counter-rotation (deg)
 *   poseBase pose filling every channel the cycle does not key; grip / curl: off-hand grip and finger curl
 *   arms(k, phase) -> { ik?, bones? } hand / arm channels at phase 0..1 (0 = right foot strikes)
 */
function run(name, P) {
  const { v, T } = P;
  const D = v * T;
  const st = P.stance * 0.5;                    // planted fraction of the whole cycle
  const a = P.land, b = v * st * T - a;         // strike point ahead, toe-off point behind
  const sw = 1 - st;
  // one foot's path over its own phase p in [0, 1] (0 = strike): [p, x, u, pitch, interp, ease]
  // the last swing key sits where the foot must be 10 % of the swing before the strike to arrive with the ground's
  // speed (no forward scuff on landing): it then only comes down
  const dtLand = 0.1 * sw * T;
  const PATH = [
    [0, a, 0, 9, 'auto', 'inQuad'],                                   // strike (just ahead of the heel)
    [st * 0.28, a - v * st * 0.28 * T, 0, 0, 'linear'],               // flat
    [st, -b, 0.015, -24, 'linear'],                                   // toe-off: heel up, still on the ball
    [st + sw * 0.2, -b - 0.14, P.lift, -62, 'auto', 'outQuad'],       // heel kicks up behind
    [st + sw * 0.5, -0.04, P.lift * 0.8, -30, 'auto'],                // passes under the hips, knee driving
    [st + sw * 0.72, a + 0.06 + v * dtLand * 0.55, P.reach + 0.05, 10, 'auto'],   // reaches
    [st + sw * 0.9, a + v * dtLand * 0.92, P.reach * 0.45, 12, 'auto'],           // paws back with the ground
    [1, a, 0, 9, 'auto', 'inQuad'],
  ];
  /** piecewise-linear sample of the path (only used for the keys at the loop seam) */
  const at = (p) => {
    let k = 1;
    while (k < PATH.length - 1 && PATH[k][0] < p) k++;
    const A = PATH[k - 1], B = PATH[k], u = (p - A[0]) / (B[0] - A[0] || 1);
    return [A[1] + (B[1] - A[1]) * u, A[2] + (B[2] - A[2]) * u, A[3] + (B[3] - A[3]) * u];
  };
  const keys = [];
  const foot = (which, x, u, pitch) => ({ pos: [+x.toFixed(4), +u.toFixed(4), which === 'footR' ? P.track : -P.track], rot: [0, which === 'footR' ? -P.toe : P.toe, +pitch.toFixed(2)] });
  for (const [which, ph] of [['footR', 0], ['footL', 0.5]]) {
    for (let i = 0; i < PATH.length; i++) {
      const [p, x, u, pitch, interp, ease] = PATH[i];
      let t = ph + p;
      if (i === PATH.length - 1 && ph > 0) continue;        // footL's closing strike is its phase-0 key
      if (t > 1 + 1e-9) t -= 1;
      keys.push({ t: +(t * T).toFixed(4), interp, ease, ik: { [which]: foot(which, x, u, pitch) } });
    }
    if (ph > 0) {
      // the loop seam falls inside this foot's cycle: key both ends with the same sample
      const [x, u, pitch] = at(1 - ph);
      keys.push({ t: 0, interp: 'auto', ik: { [which]: foot(which, x, u, pitch) } });
      keys.push({ t: T, interp: 'auto', ik: { [which]: foot(which, x, u, pitch) } });
    }
  }
  // body: the pelvis, trunk, head and free arm follow a MOTION-CAPTURED run cycle (mocap_run.js: CMU subject 9), warped
  // in phase so its stance / flight line up with this hero's foot keys and scaled to the hero's own amplitudes
  // (bounce, twist, lean). The feet stay on their planted IK paths above, the weapon hand on its carry pose.
  const N = 16;
  const stM = 0.4;                                          // the captured runner's stance, as a fraction of the cycle
  const warp = (ph) => { const h = ph >= 0.5 ? 0.5 : 0, q = ph - h; return h + (q < st ? (q / st) * stM : stM + ((q - st) / (0.5 - st)) * (0.5 - stM)); };
  const mc = (k, ph) => { const a = MC[k], x = (((warp(ph % 1)) % 1) + 1) % 1 * MC.n, i = Math.floor(x) % MC.n, f = x - Math.floor(x); return a[i] + (a[(i + 1) % MC.n] - a[i]) * f; };
  const span = (k) => { const a = MC[k]; return [Math.min(...a), Math.max(...a)]; };
  const [dy0, dy1] = span('dy'), [sw0, sw1] = span('sway');
  const kTw = P.twist / 7, kRoll = P.roll / 1.5, LEG = 0.92;
  const mean = (k) => MC[k].reduce((x, y) => x + y, 0) / MC.n;
  const mPP = mean('pPitch'), mTP = mean('tPitch'), mHP = mean('hPitch'), mSw = mean('swingL');
  for (let i = 0; i <= N; i++) {
    const ph = i / N;
    const up = P.bounce * (mc('dy', ph) - dy0) / (dy1 - dy0);
    const sgn = Math.cos(2 * Math.PI * (ph - 0.1));         // +1: the right foot is planted under the body
    const pYaw = mc('pYaw', ph) * kTw, tYaw = mc('tYaw', ph) * kTw, hYaw = mc('hYaw', ph) * kTw * 0.6;
    const pRoll = mc('pRoll', ph) * 0.5 * kRoll, tRoll = mc('tRoll', ph) * 0.6 * kRoll;
    const pP = mc('pPitch', ph) - mPP, tP = mc('tPitch', ph) - mTP - pP, hP = mc('hPitch', ph) - mHP;
    const dYaw = tYaw - pYaw, dRoll = tRoll - pRoll, nYaw = hYaw - tYaw;
    const arms = P.arms(sgn, ph);
    const bones = arms.bones ? { ...arms.bones } : {};
    if (bones.upperArmL) {
      // the free arm pumps as the captured runner's does (shoulder swing, a little abduction, a runner's bent elbow)
      const g = P.armGain ?? 1;
      bones.upperArmL = [-(mc('abdL', ph) * 0.9 + 3), 0, +((mc('swingL', ph) - mSw) * g + 2).toFixed(2)];
      bones.foreArmL = [0, 0, +(mc('elbowL', ph) * 0.84).toFixed(2)];
    }
    const r2 = (x) => +x.toFixed(2);
    keys.push({
      t: +(ph * T).toFixed(4), interp: 'auto',
      hips: { pos: [+(P.hipF + mc('surge', ph) * LEG * 0.8).toFixed(4), +(P.hipY + up).toFixed(4), +(P.sway * (2 * (mc('sway', ph) - sw0) / (sw1 - sw0) - 1)).toFixed(4)], rot: [r2(pRoll), r2(P.yaw + pYaw), r2(-pP)] },
      bones: { spine: [r2(dRoll * 0.4), r2(P.spineYaw + dYaw * 0.4), r2(-P.lean - tP * 0.5)], chest: [r2(dRoll * 0.6), r2(P.chestYaw + dYaw * 0.6), r2(-P.lean * 0.45 - tP * 0.5)],
        neck: [0, r2(P.neckYaw + nYaw * 0.5), r2(P.lean * 0.55 - hP * 0.5)], head: [0, r2(P.headYaw + nYaw * 0.5), r2(P.lean * 0.5 - hP * 0.5)], ...bones },
      ...(arms.ik ? { ik: arms.ik } : {}),
    });
  }
  keys.push({ t: 0, grip: P.grip ?? 0, curl: P.curl || [1, 1], root: { pos: [0, 0] } });
  keys.push({ t: T, interp: 'linear', root: { pos: [+D.toFixed(4), 0] } });
  defineClip(name, {
    duration: T, loop: true, breath: 0.25, look: false, base: P.poseBase,
    keys: sorted(keys),
    events: [{ t: 0.001, name: 'step', data: { foot: 'footR' } }, { t: 0.5 * T, name: 'step', data: { foot: 'footL' } }],
  });
}

// ---- KAEL: heavy, forward-leaning, the blade on the shoulder ---------------------------------------------------------
const kArms = (bob) => (sgn) => ({
  ik: { handR: { pos: [K_HAND.pos[0] + 0.05, K_HAND.pos[1] - 0.1 + bob * (1 - Math.abs(sgn)) * 0.02, K_HAND.pos[2] + 0.01], aim: [-0.82, 0.56, 0.1], up: K_HAND.up } },
  // left arm pumps against the right leg (FK): forward when the right foot is behind
  bones: { upperArmL: [-14, 0, -18 * sgn + 6], foreArmL: [0, 0, 78 - 14 * sgn], handL: [0, 0, 0] },
});
const K_RUN = { land: 0.3, stance: 0.46, lift: 0.34, reach: 0.12, track: 0.11, toe: 6, hipF: 0.02, hipY: -0.13, bounce: 0.05, sway: 0.018, roll: 1.6,
  lean: 15, yaw: -8, twist: 7, spineYaw: -2, chestYaw: -2, neckYaw: 4, headYaw: 6, grip: 0, curl: [0.7, 1], poseBase: 'kael.stance' };
run('rpg.kael.run', { ...K_RUN, v: 4.3, T: 0.68, arms: kArms(1) });
run('rpg.kael.sprint', { ...K_RUN, v: 6.3, T: 0.58, stance: 0.36, land: 0.33, lift: 0.46, reach: 0.18, lean: 24, bounce: 0.07, hipY: -0.16, twist: 10, arms: kArms(1.6) });

// ---- ISKA: light bounds, blades swept back ------------------------------------------------------------------------------
const iArms = (back) => (sgn) => ({
  ik: {
    handR: iHand([-0.2 - back + 0.05 * sgn, 0.9, 0.34], [-0.72, -0.5, 0.42], [0.55, -0.82, 0.12]),
    handL: iHand([-0.2 - back - 0.05 * sgn, 0.9, -0.34], [-0.72, -0.5, -0.42], [0.55, -0.82, -0.12]),
  },
});
const I_RUN = { land: 0.3, stance: 0.4, lift: 0.4, reach: 0.14, track: 0.085, toe: 4, hipF: 0.04, hipY: -0.12, bounce: 0.065, sway: 0.012, roll: 1.2,
  lean: 24, yaw: -4, twist: 8, spineYaw: 0, chestYaw: 0, neckYaw: 0, headYaw: 2, grip: 0, curl: [1, 1], poseBase: 'iska.stance' };
run('rpg.iska.run', { ...I_RUN, v: 5.3, T: 0.58, arms: iArms(0) });
run('rpg.iska.sprint', { ...I_RUN, v: 7.6, T: 0.5, stance: 0.33, land: 0.32, lift: 0.5, reach: 0.2, lean: 34, bounce: 0.08, hipY: -0.15, twist: 11, arms: iArms(0.08) });

// ---- VORN: the spear levelled at the hip, point leading -------------------------------------------------------------------
const vArms = (low) => (sgn) => ({
  ik: { handR: vSpear([0.2 + 0.04 * sgn, 1.04 - low, 0.27], [0.95, -0.14 - low * 0.5, -0.08 + 0.03 * sgn]) },
  // the spear rides in the right hand; the left arm pumps
  bones: { upperArmL: [-12, 0, -20 * sgn + 4], foreArmL: [0, 0, 80 - 12 * sgn], handL: [0, 0, 0] },
});
const V_RUN = { land: 0.32, stance: 0.44, lift: 0.38, reach: 0.14, track: 0.1, toe: 5, hipF: 0.03, hipY: -0.13, bounce: 0.055, sway: 0.015, roll: 1.4,
  lean: 17, yaw: -14, twist: 6, spineYaw: -4, chestYaw: -4, neckYaw: 6, headYaw: 10, grip: 0, curl: [0.8, 1], poseBase: 'vorn.stance' };
run('rpg.vorn.run', { ...V_RUN, v: 4.8, T: 0.64, arms: vArms(0) });
run('rpg.vorn.sprint', { ...V_RUN, v: 7.0, T: 0.54, stance: 0.36, land: 0.35, lift: 0.48, reach: 0.2, lean: 27, bounce: 0.075, hipY: -0.17, twist: 9, arms: vArms(0.08) });
