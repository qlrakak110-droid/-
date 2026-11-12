// KAEL — move clips, authored on the move clock (clip time = rules move time, duration = move duration) with an
// `impact` (+ `hit`) event on the first active frame, `trailOn` / `trailOff` on the moves.js markers and `step` on foot
// plants. Rules-driven travel (motion) is keyed as root motion so the feet can stay planted in 'origin' space.
// Beats per MOVES.md: WIND-UP (anticipation, hips coil first) -> RELEASE (2-4 frame smear, hips lead the shoulders lead
// the blade) -> IMPACT -> AFTERMATH (follow-through, overshoot, weight on the front foot) -> SETTLE (back to the stance).

import { defineClip, definePose } from '../../../char/index.js';
import { FL, FR, YAW_L, YAW_R, FEET, SHOULDER_HAND, STANCE_BODY, dir, plane, stance, sorted } from './common.js';

const H = (pos, o) => ({ pos, ...o });                         // hand target: position + blade orientation
const ev = (list) => list.map(([t, name, data]) => (data ? { t, name, data } : { t, name }));
const impact = (t) => [[t, 'impact'], [t, 'hit']];
/** Origin-space feet (planted in the world while the rules move the root). */
const oL = (f, u = 0, p = 0, yaw = YAW_L) => ({ space: 'origin', pos: [f, u, FL[2]], rot: [0, yaw, p] });
const oR = (f, u = 0, p = 0, yaw = YAW_R) => ({ space: 'origin', pos: [f, u, FR[2]], rot: [0, yaw, p] });
/** Root keys for a constant-velocity rules motion segment [t0, t1] covering d metres. */
const travel = (t0, t1, d) => [{ t: t0, interp: 'linear', root: { pos: [0, 0] } }, { t: t1, interp: 'linear', root: { pos: [d, 0] } }];
/** The blade back onto the shoulder: body + hand of the stance (feet untouched). */
const home = (t, ease = 'inOutSine') => ({ t, ease, hips: STANCE_BODY.hips, bones: STANCE_BODY.bones, ik: { handR: SHOULDER_HAND }, grip: 1 });
/** Blade rising off the shoulder toward the vertical (recovery helper key). */
const lifting = (pos) => H(pos, { aim: dir(-120, 72), up: [-0.6, -0.3, 0.74] });

// ---- the forehand diagonal plane (light1 cuts down it, light2's back-edge cut climbs back up it) -----------------
const DIAG = plane([-0.8, 0.5, 0.32], [0.25, 0.8, 0.55]);       // 0 = behind the right shoulder ... 130 = front ... 200 = low left

// link pose: light1's follow-through = light2's start (blade low left, hips turned through, weight on the front foot)
definePose('kael.l1end', {
  hips: { pos: [0.075, -0.17, -0.02], rot: [-3, 26, -4] },
  bones: { spine: [-3, 9, -12], chest: [-4, 10, -9], neck: [0, -10, 6], head: [0, -14, 8] },
  ik: { handR: H([0.44, 0.84, -0.2], DIAG(200)), footL: FEET.footL, footR: { pos: [FR[0] + 0.03, 0.02, FR[2] - 0.01], rot: [0, -16, -16] } },
  grip: 1, curl: [1, 1],
});
// link pose: light2's follow-through = light3's start (blade cocked high behind the right shoulder)
definePose('kael.l2end', {
  hips: { pos: [-0.02, -0.1, 0.02], rot: [2, -38, 3] },
  bones: { spine: [2, -9, 6], chest: [2, -12, 8], neck: [0, 18, -4], head: [0, 24, -8] },
  ik: { handR: H([0.08, 1.72, 0.26], DIAG(-12)), ...FEET },
  grip: 1, curl: [1, 1],
});

// ---- light1 · Ash Cleave (0.42; active 0.14-0.19) ---------------------------------------------------------------
defineClip('kael.light1', {
  duration: 0.42, breath: 0.3,
  keys: [
    { t: 0, ...stance() },
    // wind-up: the blade lifts off the shoulder and cocks back, hips coil, weight settles on the back foot
    { t: 0.07, ease: 'outCubic', hips: { pos: [-0.08, -0.115, 0.015], rot: [2, -36, 1] }, bones: { spine: [1, -8, 3], chest: [2, -12, 5], neck: [0, 18, -2], head: [0, 23, -4] },
      ik: { handR: H([0.06, 1.55, 0.27], DIAG(-14)) } },
    // hang: the hips already unwind while the blade still drifts back (lag)
    { t: 0.1, ease: 'inOutSine', hips: { pos: [-0.05, -0.125, 0.01], rot: [1, -24, 0] }, bones: { spine: [0, -4, 0], chest: [1, -8, 2] },
      ik: { handR: H([0.12, 1.66, 0.26], DIAG(8)) } },
    // smear over the right side
    { t: 0.12, ik: { handR: H([0.38, 1.66, 0.2], DIAG(68)) } },
    // impact: arms extended at chest height, weight onto the front foot, hips past square
    { t: 0.14, hips: { pos: [0.04, -0.155, -0.005], rot: [-2, 6, -2] }, bones: { spine: [-2, 5, -9], chest: [-3, 7, -8], neck: [0, -2, 4], head: [0, -4, 6] },
      ik: { handR: H([0.66, 1.22, 0.06], DIAG(130)) } },
    { t: 0.19, hips: { pos: [0.07, -0.168, -0.015], rot: [-3, 20, -3] }, ik: { handR: H([0.58, 0.94, -0.12], DIAG(170)), footR: { pos: [FR[0] + 0.02, 0.015, FR[2] - 0.01], rot: [0, -22, -12] } } },
    // follow-through into the link pose (overshoot), then a beat of weight
    { t: 0.24, ease: 'outQuad', pose: 'kael.l1end' },
    { t: 0.3, ease: 'inOutSine', hips: { pos: [0.07, -0.165, -0.02], rot: [-3, 24, -3] }, ik: { handR: H([0.45, 0.86, -0.19], DIAG(197)) } },
    // settle: the blade rises in front of the body and drops back onto the shoulder
    { t: 0.36, ease: 'inOutSine', hips: { pos: [0.01, -0.14, 0], rot: [0, -8, 0] }, bones: { spine: [0, -2, -5], chest: [0, -3, -4], neck: [0, 6, 2], head: [0, 9, 0] },
      ik: { handR: lifting([0.32, 1.2, 0.18]), footR: FEET.footR } },
    { ...home(0.42) },
  ],
  events: ev([[0.08, 'trailOn'], ...impact(0.14), [0.23, 'trailOff']]),
});

// ---- light2 · Back Edge (0.46; active 0.13-0.18; steps 0.25 m in 0-0.1) -------------------------------------------
defineClip('kael.light2', {
  duration: 0.46, breath: 0.3, base: 'kael.l1end',
  keys: sorted([
    { t: 0, pose: 'kael.l1end', ik: { footL: oL(FL[0]), footR: oR(FR[0] + 0.03, 0.02, -16, -16) } },
    // wind-up: the hips keep turning left, the blade sinks further back low on the left side
    { t: 0.06, ease: 'outCubic', hips: { pos: [0.07, -0.18, -0.025], rot: [-3, 36, -4] }, bones: { spine: [-3, 12, -12], chest: [-4, 14, -9], neck: [0, -14, 6], head: [0, -19, 8] },
      ik: { handR: H([0.24, 0.82, -0.3], DIAG(222)) } },
    { t: 0.09, ease: 'inOutSine', hips: { pos: [0.08, -0.17, -0.02], rot: [-2, 24, -3] }, ik: { handR: H([0.28, 0.82, -0.28], DIAG(214)) } },
    // smear: the back edge climbs the diagonal, hips whip back to the right
    { t: 0.11, ik: { handR: H([0.52, 0.98, -0.12], DIAG(170)) } },
    { t: 0.13, hips: { pos: [0.06, -0.135, 0.01], rot: [1, -8, 2] }, bones: { spine: [1, -6, -3], chest: [1, -8, -1], neck: [0, 8, 0], head: [0, 10, -2] },
      ik: { handR: H([0.64, 1.3, 0.08], DIAG(128)) } },
    { t: 0.18, ik: { handR: H([0.44, 1.66, 0.22], DIAG(62)) } },
    // follow-through high behind the right shoulder = light3's wind-up
    { t: 0.23, ease: 'outQuad', pose: 'kael.l2end', ik: { footL: oL(FL[0] + 0.25), footR: oR(FR[0] + 0.25) } },
    { t: 0.3, ease: 'inOutSine', ik: { handR: H([0.1, 1.68, 0.26], DIAG(-8)) } },
    { ...home(0.46) },
    // feet: the front foot steps in with the root, the back foot follows
    { t: 0.0, ik: { footL: oL(FL[0]) } },
    { t: 0.05, ik: { footL: oL(FL[0] + 0.12, 0.07, 6) } },
    { t: 0.1, ease: 'inQuad', ik: { footL: oL(FL[0] + 0.25) } },
    { t: 0.14, ik: { footR: oR(FR[0] + 0.03, 0.0, 0, -30) } },
    { t: 0.19, ik: { footR: oR(FR[0] + 0.15, 0.06, -6) } },
    { t: 0.23, ease: 'inQuad', ik: { footR: oR(FR[0] + 0.25) } },
    { t: 0.46, ik: { footL: oL(FL[0] + 0.25), footR: oR(FR[0] + 0.25) } },
    ...travel(0, 0.1, 0.25),
  ]),
  events: ev([[0.07, 'trailOn'], ...impact(0.13), [0.1, 'step', { foot: 'footL' }], [0.22, 'trailOff'], [0.23, 'step', { foot: 'footR' }]]),
});

// ---- light3 · Cinder Drop (0.70; active 0.24-0.29; steps 0.35 m in 0.04-0.2) --------------------------------------
{
  const OVER = plane(dir(180, 28), dir(0, 85));                 // 0 = behind, 90 = straight up, 150 = forward, 165 = into the floor
  const d = 2.2 * 0.16;
  defineClip('kael.light3', {
    duration: 0.7, breath: 0.2, base: 'kael.l2end',
    keys: sorted([
      { t: 0, pose: 'kael.l2end', ik: { footL: oL(FL[0]), footR: oR(FR[0]) } },
      // wind-up: rises tall, blade high back over the head, chest arched, front foot lifts into the step
      { t: 0.1, ease: 'outCubic', hips: { pos: [-0.09, -0.07, 0], rot: [0, -16, 0] }, bones: { spine: [0, -4, 9], chest: [0, -5, 12], neck: [0, 8, -8], head: [0, 10, -12] },
        ik: { handR: H([-0.02, 1.95, 0.14], OVER(-4)) } },
      { t: 0.15, ease: 'inOutSine', hips: { pos: [-0.08, -0.08, 0], rot: [0, -14, 0] }, bones: { spine: [0, -3, 11], chest: [0, -4, 14] },
        ik: { handR: H([-0.05, 1.98, 0.12], OVER(-12)) } },
      // smear over the top
      { t: 0.19, ik: { handR: H([0.3, 1.92, 0.07], OVER(80)) } },
      // impact: the blade bites the floor, deep lunge, head and chest driven down over the front knee
      { t: 0.24, ease: 'inQuad', hips: { pos: [-0.05, -0.33, -0.01], rot: [0, -12, 0] }, bones: { spine: [0, -2, -24], chest: [0, -2, -19], neck: [0, 4, 13], head: [0, 6, 17] },
        ik: { handR: H([0.62, 0.74, 0.05], OVER(158)) } },
      { t: 0.29, ease: 'outQuad', hips: { pos: [-0.06, -0.31, -0.01] }, bones: { spine: [0, -2, -22], chest: [0, -2, -17] }, ik: { handR: H([0.61, 0.77, 0.05], OVER(156)) } },
      { t: 0.44, ease: 'inOutSine', hips: { pos: [-0.08, -0.3, -0.01], rot: [0, -14, 0] }, ik: { handR: H([0.6, 0.78, 0.06], OVER(155)) } },
      // wrench the blade free and swing it up onto the shoulder; the back foot closes the stance
      { t: 0.56, ease: 'inOutSine', hips: { pos: [-0.04, -0.16, 0], rot: [0, -20, 0] }, bones: { spine: [0, -4, -6], chest: [0, -5, -4], neck: [0, 10, 2], head: [0, 13, 0] },
        ik: { handR: lifting([0.3, 1.24, 0.18]) } },
      { ...home(0.7) },
      // feet
      { t: 0.04, ik: { footL: oL(FL[0]) } },
      { t: 0.11, ik: { footL: oL(FL[0] + 0.16, 0.12, 8) } },
      { t: 0.2, ease: 'inQuad', ik: { footL: oL(FL[0] + d) } },
      { t: 0.44, ik: { footR: oR(FR[0]) } },
      { t: 0.55, ik: { footR: oR(FR[0] + d * 0.5, 0.07, -6) } },
      { t: 0.63, ease: 'inQuad', ik: { footR: oR(FR[0] + d) } },
      { t: 0.7, ik: { footL: oL(FL[0] + d), footR: oR(FR[0] + d) } },
      ...travel(0.04, 0.2, d),
    ]),
    events: ev([[0.13, 'trailOn'], [0.2, 'step', { foot: 'footL' }], ...impact(0.24), [0.33, 'trailOff'], [0.63, 'step', { foot: 'footR' }]]),
  });
}

// ---- sweep · Furnace Sweep (0.86; armour 0.12-0.32; active 0.32-0.40) --------------------------------------------
{
  const FLAT = plane(dir(-160, -6), dir(-70, 0));              // 0 = behind right ... 160 = front ... 250 = left ... 300 = behind left
  const ring = (az, r, u) => { const a = (az * Math.PI) / 180; return [+(-0.04 + r * Math.cos(a)).toFixed(3), u, +(-r * Math.sin(a)).toFixed(3)]; };
  defineClip('kael.sweep', {
    duration: 0.86, breath: 0.15,
    keys: [
      { t: 0, ...stance() },
      // armoured coil: the blade comes off the shoulder and is drawn far back low on the right, hips wound, knees deep
      { t: 0.1, ease: 'inOutSine', hips: { pos: [-0.08, -0.2, 0.02], rot: [0, -52, 0] }, bones: { spine: [0, -10, -6], chest: [0, -12, -4], neck: [0, 20, 4], head: [0, 26, 2] },
        ik: { handR: H(ring(-95, 0.34, 1.12), FLAT(-6)), footR: { pos: FR, rot: [0, -52, 0] } } },
      { t: 0.2, ease: 'outCubic', hips: { pos: [-0.1, -0.24, 0.03], rot: [0, -70, -2] }, bones: { spine: [0, -12, -8], chest: [0, -14, -6], neck: [0, 26, 6], head: [0, 32, 4] },
        ik: { handR: H(ring(-112, 0.3, 1.02), FLAT(4)), footL: { pos: FL, rot: [0, 4, 0] } } },
      { t: 0.24, ease: 'inOutSine', hips: { pos: [-0.08, -0.24, 0.02], rot: [0, -58, -1] }, bones: { spine: [0, -10, -8], chest: [0, -14, -6] },
        ik: { handR: H(ring(-110, 0.3, 1.0), FLAT(10)) } },
      // release: hips lead, the blade wraps around the right side into the front
      { t: 0.28, hips: { pos: [-0.02, -0.23, 0.01], rot: [0, -22, 0] }, bones: { spine: [0, -6, -8], chest: [0, -6, -7], neck: [0, 12, 4], head: [0, 14, 2] },
        ik: { handR: H(ring(-62, 0.42, 1.04), FLAT(88)) } },
      { t: 0.32, hips: { pos: [0.04, -0.22, -0.01], rot: [0, 12, 0] }, bones: { spine: [0, 6, -8], chest: [0, 8, -7], neck: [0, -6, 4], head: [0, -8, 2] },
        ik: { handR: H(ring(-6, 0.56, 1.06), FLAT(160)) } },
      { t: 0.36, hips: { pos: [0.06, -0.21, -0.02], rot: [0, 36, 0] }, bones: { spine: [0, 12, -6], chest: [0, 14, -5], neck: [0, -16, 4], head: [0, -20, 2] },
        ik: { handR: H(ring(40, 0.52, 1.06), FLAT(212)), footR: { pos: [FR[0] + 0.02, 0.02, FR[2] - 0.01], rot: [0, -10, -16] } } },
      { t: 0.4, ik: { handR: H(ring(78, 0.44, 1.08), FLAT(250)) } },
      // follow-through: torso wrapped far left, blade swept behind, back heel up on the ball of the foot
      { t: 0.47, ease: 'outQuad', hips: { pos: [0.06, -0.2, -0.03], rot: [-2, 58, -3] }, bones: { spine: [-2, 16, -6], chest: [-3, 18, -4], neck: [0, -26, 6], head: [0, -32, 6] },
        ik: { handR: H(ring(112, 0.36, 1.12), FLAT(296)), footL: { pos: FL, rot: [0, 30, 0] }, footR: { pos: [FR[0] + 0.03, 0.03, FR[2] - 0.02], rot: [0, 6, -22] } } },
      { t: 0.56, ease: 'inOutSine', hips: { pos: [0.05, -0.19, -0.03], rot: [-2, 54, -3] }, ik: { handR: H(ring(108, 0.36, 1.16), FLAT(290)) } },
      // haul the blade up over the head and back onto the shoulder
      { t: 0.7, ease: 'inOutSine', hips: { pos: [-0.01, -0.15, 0], rot: [0, 8, 0] }, bones: { spine: [0, 2, -2], chest: [0, 2, 2], neck: [0, 4, -2], head: [0, 4, -4] },
        ik: { handR: H([0.06, 1.68, -0.02], { aim: dir(178, 62), up: [-0.85, -0.5, 0.15] }), footL: FEET.footL, footR: { pos: FR, rot: [0, -30, -4] } } },
      { ...home(0.86), ik: { handR: SHOULDER_HAND, ...FEET } },
    ],
    events: ev([[0.23, 'trailOn'], ...impact(0.32), [0.47, 'trailOff']]),
  });
}

// ---- lunge · Molten Lunge (0.78; travels 3.2 m; active 0.26-0.34) ---------------------------------------------------
{
  const motion = [[0, 0], [0.06, 0], [0.22, 2.4], [0.3, 3.05], [0.36, 3.2]];
  const thrust = (el = 2, az = 0) => ({ aim: dir(az, el), up: [0, 1, 0] });
  defineClip('kael.lunge', {
    duration: 0.78, breath: 0.1,
    keys: sorted([
      { t: 0, ...stance(), ik: { handR: SHOULDER_HAND, footL: oL(FL[0]), footR: oR(FR[0]) } },
      // wind-up: the left shoulder drops and leads, the blade is chambered at the right hip, point at the foe
      { t: 0.06, ease: 'outCubic', hips: { pos: [0.02, -0.22, 0.02], rot: [0, -58, 0] }, bones: { spine: [0, -10, -14], chest: [0, -10, -12], neck: [0, 26, 10], head: [0, 32, 8] },
        ik: { handR: H([-0.08, 1.0, 0.3], thrust(4)) } },
      // the charge: low and flat, the front knee driving, the rear toe dragging along the floor
      { t: 0.14, hips: { pos: [0.08, -0.26, 0.02], rot: [0, -54, 0] }, bones: { spine: [0, -9, -16], chest: [0, -9, -13] }, ik: { handR: H([-0.06, 0.98, 0.3], thrust(3)) } },
      { t: 0.22, hips: { pos: [0.12, -0.26, 0.01], rot: [0, -40, 0] }, bones: { spine: [0, -6, -14], chest: [0, -6, -11], neck: [0, 20, 8], head: [0, 24, 6] },
        ik: { handR: H([0.1, 1.04, 0.24], thrust(3)) } },
      // thrust: hips unwind, both arms drive the point through, full extension
      { t: 0.26, hips: { pos: [0.16, -0.3, 0], rot: [0, -10, 0] }, bones: { spine: [0, 0, -12], chest: [0, 2, -9], neck: [0, 6, 6], head: [0, 8, 4] },
        ik: { handR: H([0.56, 1.1, 0.08], thrust(1)) } },
      { t: 0.34, ease: 'outQuad', hips: { pos: [0.18, -0.32, -0.01], rot: [0, 0, 0] }, ik: { handR: H([0.66, 1.1, 0.04], thrust(0, 2)) } },
      { t: 0.42, ease: 'inOutSine', hips: { pos: [0.16, -0.31, -0.01], rot: [0, -4, 0] }, ik: { handR: H([0.64, 1.1, 0.05], thrust(-2, 2)) } },
      // recover: draw the blade back and up onto the shoulder, front foot pulls back, rear foot steps up
      { t: 0.6, ease: 'inOutSine', hips: { pos: [0.02, -0.18, 0], rot: [0, -18, 0] }, bones: { spine: [0, -4, -6], chest: [0, -5, -4], neck: [0, 12, 2], head: [0, 15, 0] },
        ik: { handR: lifting([0.3, 1.2, 0.2]) } },
      { ...home(0.78) },
      // feet: left foot driven forward through the air, lands on the thrust; right foot drags then steps up
      { t: 0.06, ik: { footL: oL(FL[0]), footR: oR(FR[0]) } },
      { t: 0.14, ik: { footL: { pos: [0.62, 0.22, -0.16], rot: [0, YAW_L, 10] }, footR: { pos: [-0.78, 0.02, 0.2], rot: [0, YAW_R, -40] } } },
      { t: 0.24, ik: { footL: { pos: [0.74, 0.1, -0.16], rot: [0, YAW_L, 8] }, footR: { pos: [-0.86, 0.02, 0.2], rot: [0, YAW_R, -44] } } },
      { t: 0.3, ease: 'inQuad', ik: { footL: oL(3.05 + 0.76) } },
      { t: 0.34, ease: 'inQuad', ik: { footR: oR(3.2 - 0.84, 0, 0) } },
      { t: 0.52, ik: { footL: oL(3.05 + 0.76), footR: oR(3.2 - 0.84) } },
      { t: 0.6, ik: { footR: oR(3.2 - 0.6, 0.08, -6) } },
      { t: 0.68, ease: 'inQuad', ik: { footR: oR(3.2 + FR[0]), footL: oL(3.05 + 0.76) } },
      { t: 0.72, ik: { footL: oL(3.2 + FL[0] + 0.1, 0.05, 0) } },
      { t: 0.78, ease: 'inQuad', ik: { footL: oL(3.2 + FL[0]), footR: oR(3.2 + FR[0]) } },
      ...motion.map(([t, f]) => ({ t, interp: 'linear', root: { pos: [f, 0] } })),
    ]),
    events: ev([[0.18, 'trailOn'], ...impact(0.26), [0.3, 'step', { foot: 'footL' }], [0.4, 'trailOff'], [0.68, 'step', { foot: 'footR' }]]),
  });
}

// ---- vent · Vent Launcher (0.72; active 0.22-0.30) ------------------------------------------------------------------
{
  const UP = plane(dir(-6, -36), dir(0, 30));                  // 0 = tip in the floor ahead, 66 = forward-up, 110 = up, 135 = past vertical
  defineClip('kael.vent', {
    duration: 0.72, breath: 0.1,
    keys: [
      { t: 0, ...stance() },
      // wind-up: drops low, the blade comes off the shoulder and its point sinks into the floor ahead
      { t: 0.08, ease: 'inOutSine', hips: { pos: [-0.03, -0.24, 0.01], rot: [0, -28, 0] }, bones: { spine: [0, -6, -12], chest: [0, -6, -10], neck: [0, 16, 8], head: [0, 20, 10] },
        ik: { handR: H([0.3, 0.98, 0.22], { aim: dir(-20, 20), up: [-0.2, 0.3, 0.93] }) } },
      { t: 0.15, ease: 'outCubic', hips: { pos: [-0.05, -0.32, 0.01], rot: [0, -32, 0] }, bones: { spine: [0, -7, -18], chest: [0, -7, -14], neck: [0, 18, 12], head: [0, 22, 14] },
        ik: { handR: H([0.32, 0.72, 0.2], UP(0)) } },
      // the point rips out of the floor (split) and the cut climbs
      { t: 0.18, ease: 'inOutSine', hips: { pos: [-0.04, -0.3, 0.01], rot: [0, -26, 0] }, ik: { handR: H([0.36, 0.74, 0.18], UP(10)) } },
      { t: 0.2, ik: { handR: H([0.48, 0.86, 0.14], UP(40)) } },
      { t: 0.22, hips: { pos: [0.02, -0.18, 0], rot: [0, -12, 0] }, bones: { spine: [0, -4, -4], chest: [0, -4, -2], neck: [0, 8, 2], head: [0, 10, 0] },
        ik: { handR: H([0.56, 1.06, 0.12], UP(66)) } },
      { t: 0.27, ik: { handR: H([0.48, 1.5, 0.12], UP(98)), footR: { pos: [FR[0] + 0.02, 0.03, FR[2]], rot: [0, -26, -20] } } },
      // follow-through: rises onto the back toes, the blade overhead past vertical, chest open to the sky
      { t: 0.34, ease: 'outQuad', hips: { pos: [0.0, -0.04, 0], rot: [0, -16, 0] }, bones: { spine: [0, -4, 7], chest: [0, -6, 11], neck: [0, 8, -6], head: [0, 10, -12] },
        ik: { handR: H([0.26, 1.88, 0.14], UP(128)) } },
      { t: 0.46, ease: 'inOutSine', hips: { pos: [-0.01, -0.06, 0] }, ik: { handR: H([0.22, 1.86, 0.15], UP(132)) } },
      // settle: the blade tips back onto the shoulder as the knees sink
      { t: 0.58, ease: 'inOutSine', hips: { pos: [-0.03, -0.11, 0], rot: [0, -22, 0] }, bones: { spine: [0, -5, -1], chest: [0, -6, 0] },
        ik: { handR: H([0.12, 1.58, 0.22], { aim: dir(-160, 66), up: [-0.9, -0.38, 0.1] }), footR: FEET.footR } },
      { ...home(0.72) },
    ],
    events: ev([[0.15, 'trailOn'], [0.18, 'split'], ...impact(0.22), [0.34, 'trailOff']]),
  });
}

// ---- crescent · Ember Crescent (0.74; projectile at 0.28) ----------------------------------------------------------
{
  const RISE = plane([-0.8, -0.5, 0.33], [0.0, 0.1, 1]);       // 0 = point on the floor behind, 90 = right side, 150 = front rising
  defineClip('kael.crescent', {
    duration: 0.74, breath: 0.1,
    keys: [
      { t: 0, ...stance() },
      // the blade drops off the shoulder behind him; its point hits the floor on the right
      { t: 0.05, ease: 'inQuad', hips: { pos: [-0.04, -0.2, 0.02], rot: [0, -40, 0] }, bones: { spine: [0, -8, -10], chest: [0, -10, -8], neck: [0, 20, 6], head: [0, 26, 6] },
        ik: { handR: H([0.04, 0.9, 0.36], { aim: dir(-118, -27), up: [-0.85, 0.2, -0.5] }) } },
      // drag: hips coil, the point scrapes an arc behind him (sparks + molten groove), weight sinks onto the back leg
      { t: 0.22, ease: 'inOutSine', hips: { pos: [-0.1, -0.27, 0.03], rot: [0, -72, -2] }, bones: { spine: [0, -12, -12], chest: [0, -14, -10], neck: [0, 28, 8], head: [0, 34, 8] },
        ik: { handR: H([-0.12, 0.84, 0.33], RISE(-2)), footL: { pos: FL, rot: [0, 2, 0] }, footR: { pos: FR, rot: [0, -58, 0] } } },
      // release: the hips fire, the blade whips up along the right side and leaves the floor rising
      { t: 0.25, hips: { pos: [-0.06, -0.25, 0.02], rot: [0, -48, 0] }, ik: { handR: H([0.0, 0.86, 0.36], RISE(60)) } },
      { t: 0.28, hips: { pos: [0.02, -0.2, 0], rot: [0, -12, 0] }, bones: { spine: [0, -4, -8], chest: [0, -2, -6], neck: [0, 8, 4], head: [0, 10, 2] },
        ik: { handR: H([0.46, 1.08, 0.2], RISE(140)), footL: FEET.footL } },
      { t: 0.33, hips: { pos: [0.05, -0.15, -0.01], rot: [0, 14, 0] }, bones: { spine: [0, 6, -2], chest: [0, 8, 2], neck: [0, -8, 0], head: [0, -10, -2] },
        ik: { handR: H([0.48, 1.5, 0.0], { aim: dir(30, 52), up: [-0.5, 0.0, -0.85] }), footR: { pos: [FR[0] + 0.02, 0.03, FR[2] - 0.01], rot: [0, -18, -20] } } },
      // follow-through: blade high on the left, body open, held a beat while the wave travels
      { t: 0.4, ease: 'outQuad', hips: { pos: [0.05, -0.13, -0.02], rot: [-2, 22, -2] }, bones: { spine: [-2, 8, 2], chest: [-2, 10, 6], neck: [0, -12, -2], head: [0, -14, -4] },
        ik: { handR: H([0.32, 1.76, -0.12], { aim: dir(58, 64), up: [-0.6, 0.2, -0.78] }) } },
      { t: 0.5, ease: 'inOutSine', ik: { handR: H([0.3, 1.78, -0.1], { aim: dir(62, 66), up: [-0.6, 0.2, -0.78] }) } },
      // settle: the blade drops back over to the right shoulder
      { t: 0.62, ease: 'inOutSine', hips: { pos: [-0.01, -0.12, 0], rot: [0, -12, 0] }, bones: { spine: [0, -2, -2], chest: [0, -3, 0], neck: [0, 6, 0], head: [0, 9, -2] },
        ik: { handR: H([0.14, 1.66, 0.12], { aim: dir(-170, 66), up: [-0.9, -0.4, 0.1] }), footR: FEET.footR } },
      { ...home(0.74) },
    ],
    events: ev([[0.04, 'trailOn'], [0.04, 'drag'], ...impact(0.28), [0.28, 'release'], [0.4, 'trailOff']]),
  });
}

// ---- eruption · Fault Eruption (1.0; blade planted 0.40-0.74) -------------------------------------------------------
{
  const CHOP = plane(dir(0, 89), dir(60, 40));                // 0 = straight up, 90 = forward, 140 = point down into the floor ahead
  const DOWN = plane(dir(0, 89), dir(1, 30));
  defineClip('kael.eruption', {
    duration: 1.0, breath: 0.4,
    keys: [
      { t: 0, ...stance() },
      // wind-up: both hands raise the greatsword straight up to the sky, the whole body stretches tall (rune, aura)
      { t: 0.16, ease: 'outCubic', hips: { pos: [-0.05, -0.08, 0], rot: [0, -18, 0] }, bones: { spine: [0, -4, 6], chest: [0, -4, 10], neck: [0, 10, -8], head: [0, 12, -14] },
        ik: { handR: H([0.12, 1.96, 0.12], DOWN(-6)) } },
      { t: 0.3, ease: 'inOutSine', hips: { pos: [-0.07, -0.06, 0], rot: [0, -17, 0] }, bones: { spine: [0, -3, 8], chest: [0, -3, 13], neck: [0, 9, -10], head: [0, 11, -16] },
        ik: { handR: H([0.1, 2.0, 0.12], DOWN(-12)) } },
      // drive: the blade comes over and down, point-first, into the floor at ~1.3 m
      { t: 0.36, ik: { handR: H([0.36, 1.86, 0.08], DOWN(60)) } },
      { t: 0.4, ease: 'inQuad', hips: { pos: [-0.12, -0.34, -0.01], rot: [0, -16, 0] }, bones: { spine: [0, -2, -24], chest: [0, -2, -20], neck: [0, 6, 14], head: [0, 8, 18] },
        ik: { handR: H([0.56, 0.98, 0.04], DOWN(144)) } },
      // leaning over the planted blade: the cracks race away, the weight shudders down onto it
      { t: 0.46, ease: 'outQuad', hips: { pos: [-0.13, -0.37, -0.01] }, bones: { spine: [0, -2, -27], chest: [0, -2, -22] }, ik: { handR: H([0.56, 0.94, 0.04], DOWN(144)) } },
      { t: 0.6, ease: 'inOutSine', hips: { pos: [-0.12, -0.35, -0.01] }, bones: { spine: [0, -3, -25], chest: [0, -3, -21] }, ik: { handR: H([0.56, 0.95, 0.04], DOWN(144)) } },
      { t: 0.74, ease: 'inOutSine', hips: { pos: [-0.14, -0.33, -0.01], rot: [0, -20, 0] }, bones: { spine: [0, -4, -20], chest: [0, -4, -16], neck: [0, 8, 10], head: [0, 10, 12] },
        ik: { handR: H([0.54, 0.98, 0.05], DOWN(143)) } },
      // wrench: hauls it out backward, then up onto the shoulder
      { t: 0.84, ease: 'outCubic', hips: { pos: [-0.12, -0.2, 0.01], rot: [0, -28, 0] }, bones: { spine: [0, -6, -4], chest: [0, -8, -2], neck: [0, 14, 2], head: [0, 18, 0] },
        ik: { handR: lifting([0.3, 1.28, 0.2]) } },
      { ...home(1.0) },
    ],
    events: ev([[0.32, 'trailOn'], ...impact(0.4), [0.46, 'trailOff'], [0.74, 'wrench']]),
  });
  void CHOP;
}

// ---- bulwark · Pyre Bulwark (0.92; counter window 0.04-0.6) ---------------------------------------------------------
// The sword is slammed point-down in front of him; both hands stack on the hilt (left hand on the pommel).
definePose('kael.planted', {
  hips: { pos: [-0.08, -0.2, 0], rot: [0, -18, 0] },
  bones: { spine: [0, -4, -2], chest: [0, -6, 6], neck: [0, 10, -2], head: [0, 12, -4], shoulderR: [-6, 0, 0], shoulderL: [-6, 0, 0] },
  ik: { handR: H([0.44, 1.08, 0.04], { aim: dir(0, -84), up: [-1, -0.1, 0] }), footL: { pos: [FL[0] + 0.02, 0, FL[2] - 0.02], rot: [0, YAW_L + 6, 0] }, footR: { pos: [FR[0] - 0.04, 0, FR[2] + 0.04], rot: [0, YAW_R, 0] } },
  grip: 1, curl: [1, 1],
});
defineClip('kael.bulwark', {
  duration: 0.92, breath: 0.9, gripAt: 'pommel',
  keys: [
    { t: 0, ...stance() },
    // plant: the blade swings off the shoulder and is slammed point-first into the floor in front
    { t: 0.05, ik: { handR: H([0.4, 1.4, 0.12], { aim: dir(0, 10), up: [0, 0.2, 1] }) } },
    { t: 0.1, ease: 'inQuad', pose: 'kael.planted', hips: { pos: [-0.08, -0.24, 0], rot: [0, -18, 0] } },
    // braced: chest swells, the cracks blaze; a slow heave of breath under the shell
    { t: 0.18, ease: 'outQuad', pose: 'kael.planted' },
    { t: 0.4, ease: 'inOutSine', hips: { pos: [-0.08, -0.21, 0] }, bones: { chest: [0, -6, 8], head: [0, 12, -6] }, ik: { handR: H([0.44, 1.09, 0.04], { aim: dir(0, -84), up: [-1, -0.1, 0] }) } },
    { t: 0.6, ease: 'inOutSine', pose: 'kael.planted' },
    // shed + recover: pulls the blade free and swings it back onto the shoulder
    { t: 0.74, ease: 'inOutSine', hips: { pos: [-0.06, -0.17, 0], rot: [0, -22, 0] }, bones: { spine: [0, -4, -4], chest: [0, -6, -2] },
      ik: { handR: lifting([0.34, 1.26, 0.18]) } },
    { ...home(0.92), ik: { handR: SHOULDER_HAND, ...FEET } },
  ],
  events: ev([[0.1, 'plant'], [0.6, 'shed']]),
});

// ---- bulwark_burst · the counter (0.70; active 0.05-0.12) -----------------------------------------------------------
defineClip('kael.bulwark_burst', {
  duration: 0.7, breath: 0.2,
  keys: [
    { t: 0, pose: 'kael.planted', grip: 1 },
    // explosion: rips the blade up out of the floor one-handed, left arm flung wide, chest thrown open
    { t: 0.05, ease: 'outCubic', hips: { pos: [-0.06, -0.12, 0], rot: [0, -30, 0] }, bones: { spine: [0, -6, 8], chest: [0, -8, 14], neck: [0, 12, -8], head: [0, 14, -14],
      upperArmL: [-78, 0, 12], foreArmL: [0, 0, 22] }, ik: { handR: H([0.4, 1.46, 0.3], { aim: dir(-20, 50), up: [-0.7, 0.4, 0.6] }) }, grip: 0, curl: [0.2, 1] },
    { t: 0.12, ease: 'outQuad', hips: { pos: [-0.07, -0.1, 0], rot: [0, -34, 0] }, bones: { spine: [0, -7, 10], chest: [0, -9, 16], neck: [0, 12, -10], head: [0, 14, -16],
      upperArmL: [-86, 0, 6], foreArmL: [0, 0, 18] }, ik: { handR: H([0.26, 1.74, 0.36], { aim: dir(-90, 62), up: [-0.6, 0.0, 0.8] }) } },
    { t: 0.3, ease: 'inOutSine', hips: { pos: [-0.06, -0.11, 0], rot: [0, -32, 0] }, bones: { chest: [0, -8, 14], upperArmL: [-80, 0, 10], foreArmL: [0, 0, 24] },
      ik: { handR: H([0.24, 1.72, 0.36], { aim: dir(-110, 60), up: [-0.6, 0.0, 0.8] }) } },
    // settle: the left hand comes back to the grip, blade lowered onto the shoulder
    { t: 0.5, ease: 'inOutSine', hips: { pos: [-0.04, -0.12, 0], rot: [0, -26, 0] }, bones: { spine: [0, -5, -2], chest: [0, -6, 0], neck: [0, 14, 2], head: [0, 18, -2], upperArmL: [-30, 0, 30], foreArmL: [0, 0, 60] },
      ik: { handR: H([0.18, 1.5, 0.28], { aim: dir(-160, 55), up: [-0.75, -0.6, 0.2] }) }, grip: 0.6, curl: [1, 1] },
    { ...home(0.7), ik: { handR: SHOULDER_HAND, ...FEET } },
  ],
  events: ev([[0.02, 'trailOn'], ...impact(0.05), [0.22, 'trailOff']]),
});

// ---- pyre · Pyre of the Black Sun, the opener (1.65; leap 0.6-1.0, active 0.85-1.0) --------------------------------
{
  const SLASH = plane(dir(180, 25), dir(0, 89));               // 0 = blade trailing behind, 65 = up, 155 = forward-down
  const air = (k) => ({ footL: { pos: FL, w: k }, footR: { pos: FR, w: k } });
  defineClip('kael.pyre', {
    duration: 1.65, breath: 0.3,
    keys: [
      { t: 0, ...stance() },
      // the sword is lifted to the eclipse: arms fully up, blade vertical, head thrown back to the sky
      { t: 0.22, ease: 'outCubic', hips: { pos: [-0.06, -0.06, 0], rot: [0, -14, 0] }, bones: { spine: [0, -3, 8], chest: [0, -4, 14], neck: [0, 6, -14], head: [0, 8, -22] },
        ik: { handR: H([0.12, 2.0, 0.1], { aim: dir(0, 89), up: [-1, 0, 0.1] }) } },
      { t: 0.35, ease: 'inOutSine', hips: { pos: [-0.07, -0.05, 0] }, bones: { chest: [0, -4, 15], head: [0, 8, -24] }, ik: { handR: H([0.12, 2.02, 0.1], { aim: dir(0, 89), up: [-1, 0, 0.1] }) } },
      // ignite: held at full stretch while the blade drinks the corona
      { t: 0.46, ease: 'inOutSine', ik: { handR: H([0.11, 2.01, 0.1], { aim: dir(0, 89), up: [-1, 0, 0.1] }) } },
      // crouch: the blade swings back over the shoulder, knees load for the leap
      { t: 0.58, ease: 'outCubic', hips: { pos: [-0.1, -0.34, 0], rot: [0, -22, 0] }, bones: { spine: [0, -4, -10], chest: [0, -6, -4], neck: [0, 12, 6], head: [0, 16, 6] },
        ik: { handR: H([-0.02, 1.52, 0.22], SLASH(-8)), ...FEET } },
      // push-off and flight: legs tuck, the blade cocked far back, body arched like a drawn bow
      { t: 0.66, ease: 'outQuad', hips: { pos: [0.02, -0.06, 0], rot: [0, -16, 0] }, bones: { spine: [0, -2, 6], chest: [0, -3, 12], neck: [0, 6, -4], head: [0, 8, -6],
        thighL: [0, 0, 50], shinL: [0, 0, -60], footL: [0, 0, -10], thighR: [0, 0, -10], shinR: [0, 0, -40], footR: [0, 0, -30] },
        ik: { handR: H([-0.08, 1.86, 0.16], SLASH(4)), ...air(0) } },
      { t: 0.8, ease: 'inOutSine', hips: { pos: [0.0, -0.04, 0], rot: [0, -12, 0] }, bones: { spine: [0, -2, 10], chest: [0, -3, 15],
        thighL: [0, 0, 80], shinL: [0, 0, -100], thighR: [0, 0, 30], shinR: [0, 0, -110] },
        ik: { handR: H([-0.1, 1.9, 0.14], SLASH(-4)) } },
      // the slash comes down out of the air
      { t: 0.85, hips: { pos: [0.04, -0.06, 0], rot: [0, -6, 0] }, bones: { spine: [0, 0, -4], chest: [0, 0, -2], neck: [0, 2, 4], head: [0, 2, 6] },
        ik: { handR: H([0.4, 1.86, 0.08], SLASH(80)) } },
      { t: 0.93, hips: { pos: [0.05, -0.16, 0] }, bones: { spine: [0, 0, -16], chest: [0, 0, -12], thighL: [0, 0, 60], shinL: [0, 0, -60], thighR: [0, 0, 6], shinR: [0, 0, -60] },
        ik: { handR: H([0.62, 1.12, 0.05], SLASH(140)), ...air(0) } },
      // landing slam: blade into the floor, deep crouch
      { t: 1.0, ease: 'inQuad', hips: { pos: [-0.04, -0.36, 0], rot: [0, -14, 0] }, bones: { spine: [0, -2, -24], chest: [0, -2, -18], neck: [0, 4, 14], head: [0, 6, 18],
        thighL: [0, 0, 0], shinL: [0, 0, 0], thighR: [0, 0, 0], shinR: [0, 0, 0] },
        ik: { handR: H([0.64, 0.74, 0.05], SLASH(160)), footL: { pos: [FL[0] + 0.06, 0, FL[2]], rot: [0, YAW_L, 0], w: 1 }, footR: { pos: [FR[0] - 0.04, 0, FR[2]], rot: [0, YAW_R, 0], w: 1 } } },
      { t: 1.12, ease: 'outQuad', hips: { pos: [-0.05, -0.33, 0] }, ik: { handR: H([0.63, 0.76, 0.05], SLASH(159)) } },
      { t: 1.4, ease: 'inOutSine', hips: { pos: [-0.04, -0.18, 0], rot: [0, -20, 0] }, bones: { spine: [0, -4, -6], chest: [0, -5, -4], neck: [0, 12, 2], head: [0, 15, 0] },
        ik: { handR: lifting([0.32, 1.24, 0.18]), ...FEET } },
      { ...home(1.65), ik: { handR: SHOULDER_HAND, ...FEET } },
    ],
    events: ev([[0.56, 'trailOn'], [0.6, 'leap'], ...impact(0.85), [1.0, 'slam'], [1.06, 'trailOff']]),
  });
}

export const MOVES = ['kael.light1', 'kael.light2', 'kael.light3', 'kael.sweep', 'kael.lunge', 'kael.vent', 'kael.crescent',
  'kael.eruption', 'kael.bulwark', 'kael.bulwark_burst', 'kael.pyre'];

/** First impact (clip time) of each move clip: `{ clip, hit }` entries of the fighter's clip map. */
export const MOVE_HITS = { light1: 0.14, light2: 0.13, light3: 0.24, sweep: 0.32, lunge: 0.26, vent: 0.22, crescent: 0.28, eruption: 0.4, bulwark_burst: 0.05, pyre: 0.85 };
