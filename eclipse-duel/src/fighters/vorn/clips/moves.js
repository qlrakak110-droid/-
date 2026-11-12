// VORN move clips, authored 1:1 on the rules move clock (clip time = move time, duration = move duration; moves.js).
// Every clip: `impact` on the first active frame, trailOn / trailOff on the moves.js marker times, root keys equal to
// the rules `motion` (origin-space feet stay planted while the body travels), and the last key = vorn.stance.
// Beats: WIND-UP (outCubic coil, hips lead) -> RELEASE (2-4 frame smear, an arc-steering key) -> IMPACT (held) ->
// AFTERMATH (outQuad follow-through) -> SETTLE (inOutSine back to the stance, feet step home).

import { defineClip } from '../../../char/index.js';
import { STANCE, LARM0, FL, FR, YL, YR, sp, ft, heel, keyset, rootKeys, stanceFeet } from './common.js';

const clip = (name, duration, k, events, o = {}) => defineClip(name, {
  duration, breath: o.breath ?? 0.25, gripAt: 'choke', base: 'vorn.stance', keys: k.keys(), events: events.sort((a, b) => a.t - b.t),
});
const ev = (t, name, data) => (data ? { t, name, data } : { t, name });
const start = (k) => k(0, { pose: 'vorn.stance', ik: stanceFeet(0) });
const settle = (k, t, d) => k(t, { ease: 'inOutSine', pose: 'vorn.stance', bones: { ...STANCE.bones }, ik: stanceFeet(d) });
const B = (spine, chest, neck, head, extra) => ({ spine, chest, neck, head, ...(extra || {}) });

// ---- light1: 섬광 찌르기 Flash Jab (0.38) — one-handed snap thrust, the left hand releases and counter-pulls -----------
{
  const k = keyset();
  start(k);
  rootKeys(k, [[0, 0], [0.02, 0], [0.1, 0.12], [0.38, 0.12]]);
  // anticipation: the spear is drawn back level beside the hip, hips coil toward the camera
  k(0.05, { ease: 'outCubic', hips: { pos: [-0.07, -0.12, 0], rot: [0, -38, 0] }, bones: B([0, -10, -2], [1, -10, 0], [0, 16, 2], [0, 20, -2]),
    ik: { handR: sp([0.24, 1.1, 0.23], [0.97, -0.06, -0.22]) }, grip: 0.6 });
  // smear: hips have already turned through, the arm drives
  k(0.08, { hips: { pos: [0.04, -0.12, 0], rot: [0, -12, -2] }, bones: B([0, 0, -4], [0, 0, -3], [0, 4, 2], [0, 6, 0]),
    ik: { handR: sp([0.52, 1.24, 0.2], [0.99, 0.03, -0.13]) }, grip: 0.35 });
  // impact: full extension, right shoulder through, weight on the front foot; the left hand pulls back to the hip
  k(0.11, { hips: { pos: [0.13, -0.13, 0], rot: [0, 8, -3] }, bones: B([0, 8, -6], [0, 8, -4], [0, -8, 4], [0, -12, 2], { upperArmL: [-18, 0, -34], foreArmL: [0, 0, 84], handL: [0, 0, 10] }),
    ik: { handR: sp([0.9, 1.3, 0.12], [1, 0.02, -0.08], { soft: 0 }) }, grip: 0, curl: [0.85, 1] });
  // overshoot and hold through the active frames
  k(0.15, { ease: 'outQuad', hips: { pos: [0.15, -0.135, 0], rot: [0, 10, -3] }, ik: { handR: sp([0.95, 1.31, 0.11], [1, 0.03, -0.08], { soft: 0 }) } });
  // retract: the spear slides back through the fist line, the hips re-coil
  k(0.2, { ease: 'inOutSine', hips: { pos: [0.1, -0.125, 0], rot: [0, 0, -2] }, ik: { handR: sp([0.74, 1.24, 0.16], [0.98, -0.06, -0.14]) } });
  k(0.28, { ease: 'inOutSine', hips: { pos: [0.02, -0.11, 0], rot: [0, -24, 0] }, bones: B([0, -6, -3], [1, -6, -1], [0, 10, 2], [0, 14, -4], LARM0),
    ik: { handR: sp([0.42, 1.08, 0.21], [0.9, -0.32, -0.26]) }, grip: 1 });
  // feet: a quick front shuffle lands on the impact; the rear foot drags home in the recovery
  k.step('footL', 0.02, 0.1, [FL[0], 0, FL[2]], [FL[0] + 0.12, 0, FL[2]], YL, YL, 0.05);
  k(0.02, { ik: { footR: ft(FR, YR) } });
  k(0.11, { ik: { footR: heel(FR, YR, 22) } });
  k(0.2, { ik: { footR: heel(FR, YR, 18) } });
  k.step('footR', 0.25, 0.33, FR, [FR[0] + 0.12, 0, FR[2]], YR, YR, 0.05);
  settle(k, 0.38, 0.12);
  clip('vorn.flash_jab', 0.38, k, [ev(0.07, 'trailOn'), ev(0.11, 'impact'), ev(0.1, 'step', { foot: 'footL' }), ev(0.19, 'trailOff'), ev(0.33, 'step', { foot: 'footR' })]);
}

// ---- light2: 회전 쳐올리기 Haft Spin (0.44) — the spear whirls tip-over-the-top, the butt rises hip -> jaw; 0.72 m skip in --
{
  const k = keyset();
  // starts from the jab's extension (the chain cancels from it); feet where the jab left them
  k(0, { hips: { pos: [0.12, -0.13, 0], rot: [0, 8, -3] }, bones: B([0, 8, -6], [0, 8, -4], [0, -8, 4], [0, -12, 2], { upperArmL: [-18, 0, -34], foreArmL: [0, 0, 84], handL: [0, 0, 10] }),
    ik: { handR: sp([0.88, 1.3, 0.12], [1, 0.02, -0.08]), footL: ft(FL, YL), footR: ft([FR[0] - 0.12, 0, FR[2]], YR) }, grip: 0, curl: [0.85, 1] });
  rootKeys(k, [[0, 0], [0.12, 0.72], [0.44, 0.72]]);
  // spin: the tip rises and goes over the top (the butt drops and swings under), the left hand catches the haft
  k(0.04, { hips: { pos: [0.02, -0.15, 0], rot: [0, -16, 0] }, bones: B([0, -4, -6], [0, -4, -4], [0, 8, 2], [0, 10, 0], LARM0),
    ik: { handR: sp([0.5, 1.36, 0.22], [0.62, 0.74, -0.25], { up: [-0.75, 0.6, 0] }) }, grip: 0.6 });
  k(0.075, { hips: { pos: [-0.02, -0.17, 0], rot: [0, -28, 0] }, ik: { handR: sp([0.36, 1.22, 0.25], [-0.42, 0.88, 0.1], { up: [-0.9, -0.42, 0] }) }, grip: 1 });
  k(0.1, { hips: { pos: [0.02, -0.18, 0], rot: [0, -26, 2] }, bones: B([0, -4, 2], [0, -4, 4], [0, 6, -2], [0, 8, -4]),
    ik: { handR: sp([0.38, 1.04, 0.24], [-0.9, 0.3, 0.12], { up: [0.3, 0.95, 0] }) } });
  // impact: the butt-end rises into the jaw (both hands drive it), body rising out of the skip, chest opens
  k(0.12, { hips: { pos: [0.06, -0.15, 0], rot: [0, -20, 2] }, bones: B([0, -4, 5], [0, -4, 7], [0, 6, -4], [0, 8, -6]),
    ik: { handR: sp([0.46, 1.04, 0.22], [-0.8, -0.54, 0.18], { up: [-0.54, 0.8, 0] }) } });
  // follow-through: the butt keeps rising, then hangs
  k(0.17, { ease: 'outQuad', hips: { pos: [0.07, -0.13, 0], rot: [0, -18, 2] }, bones: B([0, -4, 7], [0, -4, 9], [0, 6, -6], [0, 8, -8]),
    ik: { handR: sp([0.46, 1.15, 0.22], [-0.62, -0.68, 0.38], { up: [-0.7, 0.66, 0] }) } });
  k(0.26, { ease: 'inOutSine', ik: { handR: sp([0.44, 1.18, 0.22], [-0.66, -0.64, 0.38], { up: [-0.66, 0.7, 0] }) } });
  // settle: the spear rolls back over the top into the low guard
  k(0.32, { hips: { pos: [0.0, -0.12, 0], rot: [0, -26, 0] }, bones: B([0, -6, -2], [1, -6, 0], [0, 10, 2], [0, 14, -4]),
    ik: { handR: sp([0.36, 1.22, 0.22], [-0.5, 0.86, 0.08], { up: [-0.86, -0.5, 0] }) } });
  k(0.37, { ik: { handR: sp([0.36, 1.2, 0.22], [0.45, 0.88, -0.15], { up: [-0.88, 0.45, 0] }) } });
  // feet: the rear foot skips up behind the front one, the front foot lunges and lands on the impact
  k.step('footR', 0, 0.06, [FR[0] - 0.12, 0, FR[2]], [0.1, 0, 0.22], YR, -40, 0.06);
  k.step('footL', 0.04, 0.12, [FL[0], 0, FL[2]], [FL[0] + 0.72, 0, FL[2]], YL, YL, 0.07);
  k(0.12, { ik: { footR: heel([0.1, 0, 0.22], -40, 22) } });
  k(0.2, { ik: { footR: heel([0.1, 0, 0.22], -40, 16) } });
  k.step('footR', 0.26, 0.36, [0.1, 0, 0.22], [FR[0] + 0.72, 0, FR[2]], -40, YR, 0.06);
  settle(k, 0.44, 0.72);
  clip('vorn.haft_spin', 0.44, k, [ev(0.02, 'spin'), ev(0.05, 'trailOn'), ev(0.12, 'impact'), ev(0.12, 'step', { foot: 'footL' }), ev(0.21, 'trailOff'), ev(0.36, 'step', { foot: 'footR' })]);
}

// ---- light3: 천둥 꿰기 Thunder Pierce (0.64) — two-handed lunging thrust, held for the lightning spike ---------------------
{
  const k = keyset();
  start(k);
  rootKeys(k, [[0, 0], [0.04, 0], [0.2, 0.512], [0.64, 0.512]]);
  // coil: spear drawn back level along the right hip, deep and turned toward the camera
  k(0.06, { ease: 'outCubic', hips: { pos: [-0.12, -0.17, 0], rot: [0, -46, 0] }, bones: B([0, -10, -2], [0, -10, 0], [0, 20, 4], [0, 24, 0]),
    ik: { handR: sp([0.16, 1.1, 0.22], [0.98, 0.02, -0.2]) } });
  k(0.14, { hips: { pos: [-0.02, -0.2, 0], rot: [0, -34, 0] }, ik: { handR: sp([0.28, 1.14, 0.2], [0.99, 0.03, -0.15]) } });
  // impact: hips square, both arms through, back leg straight
  k(0.2, { hips: { pos: [0.16, -0.25, 0], rot: [0, -6, -4] }, bones: B([0, 4, -10], [0, 6, -8], [0, -6, 8], [0, -8, 6]),
    ik: { handR: sp([0.96, 1.24, 0.12], [1, 0.02, -0.06], { soft: 0 }) } });
  // spike: one more push (the lightning runs down the haft), held
  k(0.25, { ease: 'outQuad', hips: { pos: [0.19, -0.26, 0], rot: [0, -2, -4] }, ik: { handR: sp([1.0, 1.25, 0.11], [1, 0.03, -0.06], { soft: 0 }) } });
  k(0.33, { ease: 'inOutSine', hips: { pos: [0.17, -0.25, 0], rot: [0, -4, -4] }, ik: { handR: sp([0.97, 1.24, 0.12], [1, 0.01, -0.07], { soft: 0 }) } });
  // recover: retract, rise, the feet come home
  k(0.46, { ease: 'inOutSine', hips: { pos: [0.06, -0.17, 0], rot: [0, -20, 0] }, bones: B([0, -4, -4], [1, -4, -2], [0, 8, 2], [0, 12, -4]),
    ik: { handR: sp([0.5, 1.1, 0.2], [0.94, -0.18, -0.24]) } });
  k.step('footR', 0.02, 0.1, FR, [FR[0] + 0.27, 0, FR[2]], YR, YR, 0.05);
  k.step('footL', 0.08, 0.19, FL, [FL[0] + 0.71, 0, FL[2]], YL, YL, 0.08);
  k.step('footL', 0.42, 0.53, [FL[0] + 0.71, 0, FL[2]], [FL[0] + 0.512, 0, FL[2]], YL, YL, 0.04);
  k(0.15, { ik: { footR: ft([FR[0] + 0.27, 0, FR[2]], YR) } });
  k(0.2, { ik: { footR: heel([FR[0] + 0.27, 0, FR[2]], YR, 26) } });
  k(0.38, { ik: { footR: heel([FR[0] + 0.27, 0, FR[2]], YR, 22) } });
  k(0.46, { ease: 'inOutSine', ik: { footR: ft([FR[0] + 0.27, 0, FR[2]], YR) } });
  k.step('footR', 0.5, 0.6, [FR[0] + 0.27, 0, FR[2]], [FR[0] + 0.512, 0, FR[2]], YR, YR, 0.05);
  settle(k, 0.64, 0.512);
  clip('vorn.thunder_pierce', 0.64, k, [ev(0.14, 'trailOn'), ev(0.2, 'impact'), ev(0.19, 'step', { foot: 'footL' }), ev(0.33, 'trailOff'), ev(0.53, 'step', { foot: 'footL' }), ev(0.6, 'step', { foot: 'footR' })]);
}

// ---- heavy: 폭풍 휩쓸기 Gale Sweep (0.76) — deep pivot, the blade skims the floor from his side round to the far side --------
{
  const k = keyset();
  start(k);
  rootKeys(k, [[0, 0], [0.1, 0], [0.26, 0.2], [0.76, 0.2]]);
  // wind-up: sink and coil hard toward the camera, the spear drawn back low behind on the near side
  k(0.18, { ease: 'outCubic', hips: { pos: [-0.14, -0.3, 0.02], rot: [0, -66, 0] }, bones: B([0, -12, -10], [0, -12, -6], [0, 26, 8], [0, 30, 4]),
    ik: { handR: sp([-0.08, 0.86, 0.36], [-0.86, -0.22, 0.46]) } });
  // the hips whip round first, the spear lags behind them (smear toward the viewer)
  k(0.24, { hips: { pos: [-0.04, -0.36, 0.02], rot: [0, -34, 0] }, bones: B([0, -12, -10], [0, -10, -8], [0, 20, 8], [0, 24, 4]),
    ik: { handR: sp([0.16, 0.78, 0.42], [0.06, -0.3, 0.95]) } });
  // impact: the head crosses the front at shin height
  k(0.28, { hips: { pos: [0.04, -0.38, 0.0], rot: [0, -8, -2] }, bones: B([0, -2, -12], [0, 0, -10], [0, 6, 8], [0, 8, 6]),
    ik: { handR: sp([0.5, 0.74, 0.3], [0.78, -0.4, 0.48]) } });
  k(0.32, { hips: { pos: [0.08, -0.38, -0.02], rot: [0, 14, -2] }, bones: B([0, 6, -12], [0, 8, -10], [0, -6, 8], [0, -8, 6]),
    ik: { handR: sp([0.8, 0.72, 0.1], [0.92, -0.39, -0.04]) } });
  k(0.36, { hips: { pos: [0.08, -0.37, -0.04], rot: [0, 30, -2] }, bones: B([0, 10, -12], [0, 12, -10], [0, -14, 8], [0, -18, 6]),
    ik: { handR: sp([0.74, 0.74, -0.06], [0.55, -0.37, -0.75]) } });
  // follow-through: wound round to the far side, the spear across the front pointing away
  k(0.44, { ease: 'outQuad', hips: { pos: [0.05, -0.35, -0.04], rot: [0, 40, -2] }, bones: B([0, 12, -10], [0, 14, -8], [0, -20, 6], [0, -26, 4]),
    ik: { handR: sp([0.56, 0.8, -0.12], [0.3, -0.26, -0.92]) } });
  k(0.52, { ease: 'inOutSine', hips: { pos: [0.02, -0.3, -0.02], rot: [0, 30, -1] }, ik: { handR: sp([0.56, 0.84, -0.06], [0.42, -0.28, -0.86]) } });
  // recover: unwind back through the front into the low guard
  k(0.64, { ease: 'inOutSine', hips: { pos: [-0.02, -0.17, 0], rot: [0, -10, 0] }, bones: B([0, -4, -4], [1, -4, -2], [0, 6, 2], [0, 10, -4]),
    ik: { handR: sp([0.42, 0.98, 0.14], [0.92, -0.38, -0.08]) } });
  // feet: the front foot pivots out wide and plants for the sweep; the rear foot follows in the recovery
  k(0.08, { grip: 1, curl: [1, 1], bones: LARM0 });
  k(0.16, { grip: 0, curl: [0.5, 1], bones: { upperArmL: [-40, 0, 30], foreArmL: [0, 0, 40], handL: [0, 0, 0] } });
  k(0.3, { bones: { upperArmL: [-60, 0, -10], foreArmL: [0, 0, 20], handL: [0, 0, 0] } });
  k(0.44, { bones: { upperArmL: [-50, 0, -36], foreArmL: [0, 0, 30], handL: [0, 0, 0] } });
  k(0.54, { grip: 0, bones: { upperArmL: [-30, 0, -20], foreArmL: [0, 0, 40], handL: [0, 0, 0] } });
  k(0.66, { grip: 1, curl: [1, 1], bones: LARM0 });
  k.step('footL', 0.1, 0.22, FL, [FL[0] + 0.32, 0, FL[2] - 0.04], YL, YL + 8, 0.05);
  k(0.1, { ik: { footR: ft(FR, YR) } });
  k(0.2, { ik: { footR: heel(FR, YR - 3, 16) } });
  k(0.3, { ik: { footR: heel(FR, YR - 6, 30) } });
  k(0.46, { ik: { footR: heel(FR, YR - 6, 26) } });
  k(0.58, { ease: 'inOutSine', ik: { footR: ft(FR, YR - 6) } });
  k.step('footL', 0.56, 0.66, [FL[0] + 0.32, 0, FL[2] - 0.04], [FL[0] + 0.2, 0, FL[2]], YL + 8, YL, 0.04);
  k.step('footR', 0.6, 0.72, FR, [FR[0] + 0.2, 0, FR[2]], YR - 6, YR, 0.05);
  settle(k, 0.76, 0.2);
  clip('vorn.gale_sweep', 0.76, k, [ev(0.2, 'trailOn'), ev(0.28, 'impact'), ev(0.22, 'step', { foot: 'footL' }), ev(0.42, 'trailOff'), ev(0.66, 'step', { foot: 'footL' }), ev(0.72, 'step', { foot: 'footR' })]);
}

// ---- f+heavy: 번개 돌격 Lightning Charge (0.74) — crouch, explosive 4 m glide-thrust, skid stop --------------------------
/** Left arm swept back for balance while the right hand carries the spear alone (lance charge, one-handed sweep). */
const LBACK = { upperArmL: [-34, 0, -38], foreArmL: [0, 0, 36], handL: [0, 0, 10] };
const CHARGE_FLIGHT = (k, t0, t1, tHit, tHold) => {
  // the streak: the whole body pitched into the run (hips bowed forward, so the trailing leg extends from a forward-
  // tilted pelvis), carried by the root, feet skimming just off the floor
  k(t0, { hips: { pos: [0.16, -0.24, 0], rot: [0, -20, -16] }, bones: B([0, -4, -8], [0, -4, -6], [0, 8, 16], [0, 10, 18]),
    ik: { handR: sp([0.5, 1.1, 0.18], [1, 0.02, -0.12]), footL: ft([0.6, 0.1, -0.15], YL, { space: 'root', pitch: -18 }), footR: ft([-0.56, 0.24, 0.2], YR + 10, { space: 'root', pitch: -50 }) } });
  k(t1, { hips: { pos: [0.2, -0.24, 0], rot: [0, -12, -16] }, ik: { handR: sp([0.7, 1.17, 0.15], [1, 0.02, -0.09]) } });
  k(tHit, { hips: { pos: [0.24, -0.24, 0], rot: [0, -4, -14] }, bones: B([0, 4, -8], [0, 4, -4], [0, -4, 12], [0, -6, 14]),
    ik: { handR: sp([0.96, 1.24, 0.1], [1, 0.02, -0.05], { soft: 0 }), footL: ft([0.66, 0.08, -0.15], YL, { space: 'root', pitch: -14 }), footR: ft([-0.6, 0.2, 0.2], YR + 10, { space: 'root', pitch: -52 }) } });
  k(tHold, { hips: { pos: [0.25, -0.24, 0], rot: [0, -3, -14] }, ik: { handR: sp([0.98, 1.24, 0.1], [1, 0.02, -0.05], { soft: 0 }) } });
};
{
  const k = keyset();
  start(k);
  rootKeys(k, [[0, 0], [0.06, 0.05], [0.2, 1.6], [0.32, 3.8], [0.38, 4.0], [0.74, 4.0]]);
  k(0.06, { ease: 'outCubic', hips: { pos: [-0.08, -0.3, 0], rot: [0, -40, 0] }, bones: B([0, -6, -16], [0, -6, -12], [0, 12, 14], [0, 16, 16]),
    ik: { handR: sp([0.16, 1.0, 0.22], [0.98, 0.04, -0.18]), footL: ft(FL, YL), footR: ft(FR, YR, { pitch: -10 }) } });
  CHARGE_FLIGHT(k, 0.11, 0.16, 0.2, 0.32);
  k(0.07, { grip: 1, curl: [1, 1], bones: LARM0 });
  k(0.11, { grip: 0, curl: [0.6, 1], bones: LBACK });
  k(0.38, { grip: 0, bones: LBACK });
  k(0.5, { grip: 1, curl: [1, 1], bones: LARM0 });
  // skid: the front foot bites, the body absorbs, the spear stays on the victim
  k(0.38, { ease: 'outQuad', hips: { pos: [0.1, -0.32, 0], rot: [0, -18, -2] }, bones: B([0, -2, -12], [0, -2, -8], [0, 8, 10], [0, 10, 10]),
    ik: { handR: sp([0.78, 1.14, 0.16], [0.98, -0.1, -0.14]), footL: ft([4.62, 0, -0.15], YL, { ease: 'inQuad' }) } });
  k(0.42, { ik: { footR: ft([3.28, 0, 0.2], YR, { ease: 'inQuad' }) } });
  k(0.54, { ease: 'inOutSine', hips: { pos: [0.0, -0.18, 0], rot: [0, -26, 0] }, bones: B([0, -6, -4], [1, -6, -2], [0, 10, 2], [0, 14, -4]),
    ik: { handR: sp([0.44, 1.04, 0.2], [0.9, -0.34, -0.25]) } });
  k.step('footL', 0.56, 0.66, [4.62, 0, -0.15], [4.0 + FL[0], 0, FL[2]], YL, YL, 0.04);
  k.step('footR', 0.62, 0.72, [3.28, 0, 0.2], [4.0 + FR[0], 0, FR[2]], YR, YR, 0.05);
  settle(k, 0.74, 4.0);
  clip('vorn.lightning_charge', 0.74, k, [ev(0.12, 'trailOn'), ev(0.2, 'impact'), ev(0.38, 'step', { foot: 'footL' }), ev(0.4, 'trailOff'), ev(0.42, 'step', { foot: 'footR' }), ev(0.72, 'step', { foot: 'footR' })], { breath: 0 });
}

// ---- d+heavy: 하늘 꿰뚫기 Skyward Lance (0.64) — deep crouch, the whole body uncoils into an upward thrust -----------------
{
  const k = keyset();
  start(k);
  rootKeys(k, [[0, 0], [0.02, 0], [0.14, 0.12], [0.64, 0.12]]);
  k(0.1, { ease: 'outCubic', hips: { pos: [-0.06, -0.38, 0], rot: [0, -36, 0] }, bones: B([0, -8, -14], [0, -8, -8], [0, 14, 14], [0, 18, 18]),
    ik: { handR: sp([0.16, 0.82, 0.3], [0.62, 0.76, -0.18]) } });
  k(0.15, { hips: { pos: [0.04, -0.2, 0], rot: [0, -20, -4] }, bones: B([0, -2, -2], [0, -2, 2], [0, 6, 10], [0, 8, 14]),
    ik: { handR: sp([0.4, 1.32, 0.22], [0.45, 0.88, -0.14]) } });
  // impact: fully extended, rising onto the rear toes, arching back, eyes up the spear
  k(0.18, { hips: { pos: [0.1, -0.05, 0], rot: [0, -8, -6] }, bones: B([0, 2, 8], [0, 2, 10], [0, -4, 12], [0, -6, 18]),
    ik: { handR: sp([0.55, 1.82, 0.12], [0.38, 0.92, -0.08], { soft: 0 }), footR: ft([FR[0], 0.05, FR[2]], YR, { pitch: -28 }) } });
  k(0.25, { ease: 'outQuad', hips: { pos: [0.11, -0.04, 0], rot: [0, -6, -6] }, ik: { handR: sp([0.57, 1.86, 0.11], [0.36, 0.93, -0.07], { soft: 0 }) } });
  k(0.32, { ease: 'inOutSine', hips: { pos: [0.1, -0.06, 0] }, ik: { handR: sp([0.56, 1.82, 0.12], [0.4, 0.91, -0.08]), footR: ft([FR[0], 0.03, FR[2]], YR, { pitch: -20 }) } });
  // recover: the spear comes down in front, heel down, feet home
  k(0.44, { ease: 'inOutSine', hips: { pos: [0.02, -0.14, 0], rot: [0, -22, 0] }, bones: B([0, -6, -2], [1, -6, 0], [0, 10, 2], [0, 14, -4]),
    ik: { handR: sp([0.44, 1.2, 0.2], [0.75, 0.45, -0.25]), footR: ft(FR, YR, { ease: 'inQuad' }) } });
  k.step('footL', 0.02, 0.1, FL, [FL[0] + 0.2, 0, FL[2]], YL, YL, 0.04);
  k.step('footL', 0.5, 0.58, [FL[0] + 0.2, 0, FL[2]], [FL[0] + 0.12, 0, FL[2]], YL, YL, 0.03);
  k.step('footR', 0.5, 0.6, FR, [FR[0] + 0.12, 0, FR[2]], YR, YR, 0.05);
  settle(k, 0.64, 0.12);
  clip('vorn.skyward_lance', 0.64, k, [ev(0.12, 'trailOn'), ev(0.18, 'impact'), ev(0.1, 'step', { foot: 'footL' }), ev(0.3, 'trailOff'), ev(0.6, 'step', { foot: 'footR' })]);
}

// ---- skill1: 뇌창 투척 Thunder Javelin (0.68) — javelin draw over the shoulder, overhand whip (the spear stays in hand) ---
{
  const k = keyset();
  start(k);
  // draw: the left hand lets go and points at the target, the spear cocks back over the right shoulder, weight back
  k(0.12, { ease: 'outCubic', hips: { pos: [-0.1, -0.1, 0], rot: [0, -50, 0] }, bones: B([0, -10, 4], [0, -12, 8], [0, 24, -2], [0, 30, -4]),
    ik: { handR: sp([-0.2, 1.62, 0.34], [0.95, 0.24, -0.18]), handL: { pos: [0.42, 1.42, -0.2], w: 1 } }, curl: [0.25, 1] });
  k(0.2, { ease: 'outQuad', hips: { pos: [-0.13, -0.11, 0], rot: [0, -56, 2] }, bones: B([0, -12, 6], [0, -13, 10], [0, 28, -4], [0, 34, -6]),
    ik: { handR: sp([-0.27, 1.6, 0.36], [0.95, 0.26, -0.18]), handL: { pos: [0.5, 1.5, -0.16], w: 1 } } });
  // hang: the hips fire first, the arm still back
  k(0.23, { hips: { pos: [-0.06, -0.12, 0], rot: [0, -36, 0] }, bones: B([0, -10, 2], [0, -10, 4], [0, 20, -2], [0, 24, -4]),
    ik: { handR: sp([-0.2, 1.66, 0.34], [0.96, 0.22, -0.16]) } });
  // release: whip over the top to full extension, the left hand pulls in to the ribs, rear foot pivots onto the toes
  k(0.26, { hips: { pos: [0.08, -0.14, 0], rot: [0, -2, -4] }, bones: B([0, 6, -8], [0, 8, -8], [0, -4, 6], [0, -6, 4]),
    ik: { handR: sp([0.74, 1.68, 0.1], [0.98, 0.12, -0.1], { soft: 0 }), handL: { pos: [0.02, 1.15, -0.3], w: 1 }, footR: ft([FR[0], 0.04, FR[2]], YR + 18, { pitch: -26 }) } });
  // follow-through: the arm keeps travelling down across the body
  k(0.36, { ease: 'outQuad', hips: { pos: [0.13, -0.17, 0], rot: [0, 14, -4] }, bones: B([0, 10, -12], [0, 10, -10], [0, -12, 8], [0, -14, 6]),
    ik: { handR: sp([0.9, 1.22, 0.04], [0.9, -0.36, -0.2]), handL: { pos: [-0.04, 1.1, -0.3], w: 1 } } });
  k(0.48, { ease: 'inOutSine', hips: { pos: [0.04, -0.13, 0], rot: [0, -12, 0] }, bones: B([0, -4, -4], [1, -4, -2], [0, 8, 2], [0, 12, -4]),
    ik: { handR: sp([0.44, 1.08, 0.18], [0.88, -0.38, -0.26]), handL: { pos: [0.1, 1.1, 0.2], w: 0 }, footR: ft(FR, YR, { ease: 'inQuad' }) }, grip: 1, curl: [1, 1] });
  k(0, { ik: { handL: { pos: [0.1, 1.1, 0.2], w: 0 } } });
  k(0.06, { grip: 0, curl: [0.5, 1] });
  settle(k, 0.68, 0);
  k(0.68, { ik: { handL: { pos: [0.1, 1.1, 0.2], w: 0 } } });
  clip('vorn.thunder_javelin', 0.68, k, [ev(0.04, 'form'), ev(0.18, 'trailOn'), ev(0.26, 'impact'), ev(0.36, 'trailOff'), ev(0.48, 'step', { foot: 'footR' })]);
}

// ---- skill2: 낙뢰 Stormfall (0.86) — the spear raised to the sky in both hands, then brought down to point the bolts -----
{
  const k = keyset();
  start(k);
  k(0.2, { ease: 'outCubic', hips: { pos: [0, -0.06, 0], rot: [0, -22, 0] }, bones: B([0, -6, 6], [0, -6, 9], [0, 8, 12], [0, 10, 20]),
    ik: { handR: sp([0.14, 2.2, 0.17], [0.1, 1, -0.05], { up: [-1, 0, 0] }) } });
  // tension hold while the clouds gather (a slow press higher)
  k(0.36, { ease: 'inOutSine', hips: { pos: [0, -0.05, 0], rot: [0, -20, 0] }, bones: B([0, -6, 7], [0, -6, 11], [0, 8, 13], [0, 10, 22]),
    ik: { handR: sp([0.16, 2.26, 0.16], [0.12, 1, -0.05], { up: [-1, 0, 0] }) } });
  // release: brought down hard to point at the marker, front foot stamps
  k(0.42, { hips: { pos: [0.04, -0.1, 0], rot: [0, -16, -2] }, bones: B([0, -4, 0], [0, -4, 0], [0, 6, 4], [0, 8, 6]),
    ik: { handR: sp([0.5, 1.92, 0.12], [0.85, 0.5, -0.12]) } });
  k(0.45, { ease: 'inQuad', hips: { pos: [0.1, -0.17, 0], rot: [0, -10, -4] }, bones: B([0, 0, -12], [0, 2, -10], [0, -2, 8], [0, -4, 10]),
    ik: { handR: sp([0.8, 1.14, 0.12], [0.88, -0.44, -0.17], { soft: 0 }) } });
  k(0.55, { ease: 'outQuad', hips: { pos: [0.11, -0.18, 0] }, ik: { handR: sp([0.82, 1.12, 0.12], [0.88, -0.45, -0.16], { soft: 0 }) } });
  k(0.7, { ease: 'inOutSine', hips: { pos: [0.08, -0.16, 0], rot: [0, -14, -3] }, ik: { handR: sp([0.74, 1.1, 0.14], [0.88, -0.44, -0.18]) } });
  k(0.4, { grip: 1, curl: [1, 1], bones: LARM0 });
  k(0.45, { grip: 0, curl: [0.4, 1], bones: { upperArmL: [-20, 0, -30], foreArmL: [0, 0, 70], handL: [0, 0, 10] } });
  k(0.76, { grip: 0, bones: { upperArmL: [-14, 0, -12], foreArmL: [0, 0, 60], handL: [0, 0, 10] } });
  k(0.86, { grip: 1, curl: [1, 1], bones: LARM0 });
  k.step('footL', 0.32, 0.45, FL, FL, YL, YL, 0.09);
  k(0.32, { ik: { footR: ft(FR, YR) } });
  settle(k, 0.86, 0);
  clip('vorn.stormfall', 0.86, k, [ev(0.04, 'raise'), ev(0.36, 'trailOn'), ev(0.45, 'impact'), ev(0.45, 'step', { foot: 'footL' }), ev(0.55, 'trailOff')], { breath: 0.4 });
}

// ---- skill3: 섬전 보법 Arc Step (0.62) — coil, burst into a bolt (4 m in 0.1 s), re-form in a skidding crouch -------------
{
  const k = keyset();
  start(k);
  rootKeys(k, [[0, 0], [0.08, 0], [0.18, 4.0], [0.62, 4.0]]);
  k(0.06, { ease: 'outCubic', hips: { pos: [-0.1, -0.3, 0], rot: [0, -40, 0] }, bones: B([0, -6, -14], [0, -6, -10], [0, 12, 12], [0, 16, 14]),
    ik: { handR: sp([0.16, 0.96, 0.22], [0.96, -0.1, -0.2]) } });
  k(0.08, { ik: { footL: ft(FL, YL), footR: ft(FR, YR, { pitch: -16 }) } });
  k(0.06, { grip: 1, curl: [1, 1], bones: LARM0 });
  k(0.1, { grip: 0, curl: [0.6, 1], bones: LBACK });
  k(0.2, { grip: 0, bones: LBACK });
  k(0.34, { grip: 1, curl: [1, 1], bones: LARM0 });
  // bolt form: stretched forward (the choreography hides / ghosts the body here)
  k(0.12, { hips: { pos: [0.16, -0.24, 0], rot: [0, -20, -16] }, bones: B([0, -4, -10], [0, -4, -6], [0, 8, 16], [0, 10, 18]),
    ik: { handR: sp([0.5, 1.06, 0.18], [0.99, 0, -0.14]), footL: ft([0.58, 0.12, -0.15], YL, { space: 'root', pitch: -18 }), footR: ft([-0.56, 0.26, 0.2], YR, { space: 'root', pitch: -50 }) } });
  // re-form: lands skidding in a low crouch, the spear swept out behind
  k(0.18, { ease: 'inQuad', hips: { pos: [0.02, -0.36, 0], rot: [0, -44, 2] }, bones: B([0, -8, -12], [0, -8, -8], [0, 16, 10], [0, 20, 10]),
    ik: { handR: sp([0.24, 0.92, 0.24], [0.9, -0.32, -0.28]), footL: ft([4.5, 0, -0.16], YL + 4), footR: ft([3.52, 0, 0.21], YR) } });
  k(0.26, { ease: 'outQuad', hips: { pos: [-0.04, -0.33, 0], rot: [0, -46, 2] }, ik: { handR: sp([0.22, 0.94, 0.25], [0.88, -0.36, -0.3]) } });
  // rise with a flourish: the spear rolls up into the guard as the line behind him detonates
  k(0.43, { ease: 'inOutSine', hips: { pos: [-0.02, -0.16, 0], rot: [0, -30, 0] }, bones: B([0, -8, -4], [1, -8, -2], [0, 12, 2], [0, 16, -4]),
    ik: { handR: sp([0.34, 1.1, 0.2], [0.92, -0.2, -0.26]) } });
  k.step('footL', 0.44, 0.54, [4.5, 0, -0.16], [4.0 + FL[0], 0, FL[2]], YL + 4, YL, 0.04);
  k.step('footR', 0.5, 0.58, [3.52, 0, 0.21], [4.0 + FR[0], 0, FR[2]], YR, YR, 0.04);
  settle(k, 0.62, 4.0);
  clip('vorn.arc_step', 0.62, k, [ev(0.06, 'trailOn'), ev(0.08, 'impact'), ev(0.18, 'step', { foot: 'footL' }), ev(0.2, 'trailOff'), ev(0.54, 'step', { foot: 'footL' })], { breath: 0 });
}

// ---- ult opener: 천벌의 뇌창 (1.35) — spear to the sky (the bolt strikes it), couched coil, 6 m dash-thrust, skewer ---------
{
  const k = keyset();
  start(k);
  rootKeys(k, [[0, 0], [0.6, 0], [0.64, 0.2], [0.7, 1.0], [0.86, 5.6], [0.9, 6.0], [1.35, 6.0]]);
  // super-freeze: the spear raised to the eclipse
  k(0.09, { ease: 'outCubic', hips: { pos: [0, -0.05, 0], rot: [0, -20, 0] }, bones: B([0, -6, 6], [0, -6, 10], [0, 8, 12], [0, 10, 22]),
    ik: { handR: sp([0.14, 2.22, 0.17], [0.1, 1, -0.05], { up: [-1, 0, 0] }) } });
  // the sky bolt hits the tip: a jolt down through the body
  k(0.13, { hips: { pos: [-0.01, -0.13, 0], rot: [0, -22, 1] }, bones: B([0, -6, 2], [0, -6, 4], [0, 8, 6], [0, 10, 10]),
    ik: { handR: sp([0.13, 2.12, 0.18], [0.12, 1, -0.06], { up: [-1, 0, 0] }) } });
  k(0.22, { ease: 'outQuad', hips: { pos: [0, -0.08, 0], rot: [0, -21, 0] }, bones: B([0, -6, 5], [0, -6, 8], [0, 8, 10], [0, 10, 18]),
    ik: { handR: sp([0.14, 2.18, 0.17], [0.11, 1, -0.05], { up: [-1, 0, 0] }) } });
  // charge: the spear comes down into the couch, the body coils low (held, trembling with tension)
  k(0.36, { hips: { pos: [-0.04, -0.2, 0], rot: [0, -30, 0] }, ik: { handR: sp([0.3, 1.6, 0.22], [0.85, 0.5, -0.16]) } });
  k(0.46, { ease: 'outCubic', hips: { pos: [-0.1, -0.32, 0], rot: [0, -42, 0] }, bones: B([0, -6, -16], [0, -6, -12], [0, 14, 14], [0, 18, 16]),
    ik: { handR: sp([0.16, 1.0, 0.22], [0.98, 0.04, -0.18]), footR: ft(FR, YR, { pitch: -6 }) } });
  k(0.58, { ease: 'inOutSine', hips: { pos: [-0.13, -0.34, 0], rot: [0, -44, 0] }, ik: { handR: sp([0.13, 1.0, 0.22], [0.98, 0.05, -0.18]), footR: ft(FR, YR, { pitch: -14 }) } });
  CHARGE_FLIGHT(k, 0.63, 0.67, 0.7, 0.88);
  k(0.59, { grip: 1, curl: [1, 1], bones: LARM0 });
  k(0.63, { grip: 0, curl: [0.6, 1], bones: LBACK });
  k(0.94, { grip: 0, bones: LBACK });
  k(1.08, { grip: 1, curl: [1, 1], bones: LARM0 });
  // whiff / block: overrun skid and recover
  k(0.94, { ease: 'outQuad', hips: { pos: [0.1, -0.32, 0], rot: [0, -18, -2] }, bones: B([0, -2, -12], [0, -2, -8], [0, 8, 10], [0, 10, 10]),
    ik: { handR: sp([0.78, 1.14, 0.16], [0.98, -0.1, -0.14]), footL: ft([6.62, 0, -0.15], YL, { ease: 'inQuad' }) } });
  k(0.98, { ik: { footR: ft([5.28, 0, 0.2], YR, { ease: 'inQuad' }) } });
  k(1.12, { ease: 'inOutSine', hips: { pos: [0.0, -0.18, 0], rot: [0, -26, 0] }, bones: B([0, -6, -4], [1, -6, -2], [0, 10, 2], [0, 14, -4]),
    ik: { handR: sp([0.44, 1.04, 0.2], [0.9, -0.34, -0.25]) } });
  k.step('footL', 1.12, 1.22, [6.62, 0, -0.15], [6.0 + FL[0], 0, FL[2]], YL, YL, 0.04);
  k.step('footR', 1.18, 1.3, [5.28, 0, 0.2], [6.0 + FR[0], 0, FR[2]], YR, YR, 0.05);
  settle(k, 1.35, 6.0);
  clip('vorn.ninefold_storm', 1.35, k, [ev(0.56, 'trailOn'), ev(0.6, 'step', { foot: 'footR' }), ev(0.7, 'impact'), ev(0.94, 'step', { foot: 'footL' }), ev(0.98, 'trailOff')], { breath: 0.3 });
}
