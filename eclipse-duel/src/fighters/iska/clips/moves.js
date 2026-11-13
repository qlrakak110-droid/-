// ISKA move clips: one per move of moves.js, duration = the move's duration, an `impact` event on the first active
// frame (the game samples them at the rules' move time; `hit` in the clip map keeps that frame on the first active
// frame if the data changes). Beats per MOVES.md: WIND-UP -> RELEASE (smear) -> IMPACT -> AFTERMATH -> SETTLE, ending
// on iska.stance. Root motion keys mirror the rules motion (it is never applied: the rules move the fighter) so that
// origin-space feet stay planted in the world while the body travels.

import { defineClip } from '../../../char/index.js';
import { foot, ball, hand, mir, sweep, XR as X_R, XL as X_L, FL, FR, YAW_L, YAW_R, PITCH, ev } from './common.js';

const S = 'iska.stance';
const o = (x) => ({ ...x, space: 'origin' });
const add = (a, d) => [a[0] + d[0], a[1] + d[1], a[2] + d[2]];

// ---- shared one-blade forehand diagonal (right hand: high-right -> low-left), mirrored for the left hand ----------
// cock: blade over the shoulder, edge up | over: blade vertical above the fist, edge forward | hit: arm long, blade
// angled forward-up, edge down-forward | thru: fist past the far hip, blade across the body.
const CUT = {
  cock: hand([0.06, 1.36, 0.34], [-0.8, 0.38, 0.46], [0.3, -0.92, 0.2], { pole: [0.3, 1.25, 0.8] }),
  over: hand([0.34, 1.4, 0.15], [0.25, 0.95, 0.15], [-0.96, 0.26, 0.1]),
  hit: hand([0.6, 1.12, -0.01], [0.9, 0.1, -0.4], [0.2, 0.5, 0.85]),
  thru: hand([0.5, 0.86, -0.2], [0.35, -0.22, -0.9], [0.72, 0.68, 0.1]),
};
const CUTL = { cock: mir(CUT.cock), over: mir(CUT.over), hit: mir(CUT.hit), thru: mir(CUT.thru) };
// off-hand guard while the other blade cuts (drawn back to the hip, blade low)
const GUARD_L = hand([0.12, 1.0, -0.17], [0.55, -0.45, 0.7], [0.8, 0.55, -0.2]);
const GUARD_R = mir(GUARD_L);

// ======================================================================================================================
// light1 - Rime Flick (0.30): quick right-hand forehand diagonal. trailOn .05, swing .07, ACTIVE .09-.12, trailOff .14
// The reference clip of src/fighters/MOTION.md ("Worked examples"). Beats (frames at 60 fps):
//   0-3   gather: up onto the ball of the rear foot, hips wind away, the right crescent goes over the shoulder while
//         the LEFT one comes up as a guard in front (one blade covers while the other loads)
//   3-5   the hips have already turned through when the blade is only over the top (the lag that makes the whip)
//   5-7   the cut and its kime: the arm long, the rear foot pivoted on its ball (heel swung out), the left blade
//         pulled back to the hip (one blade high and long, one low and close): the two hands trade places, which is
//         what turns the waist
//   7-9   follow-through: the wrist lets the crescent roll on down and across
//   9-18  the circle closes: the blade does not come back the way it went, it dips under and rises into the low guard
//         from below while the left blade settles from above; the body floats up a little past the stance and sinks
/** A foot turning on its ball: sole target at yaw `y1` / pitch `p` whose ball stays where the stance ball (yaw `y0`) is. */
const pivot = (pos, y0, y1, p, p0 = PITCH) => {
  const L = 0.125, r = Math.PI / 180;
  const bx = pos[0] + L * Math.cos(p0 * r) * Math.cos(y0 * r), bz = pos[2] - L * Math.cos(p0 * r) * Math.sin(y0 * r);
  return { pos: [bx - L * Math.cos(p * r) * Math.cos(y1 * r), pos[1] + L * (Math.sin(p0 * r) - Math.sin(p * r)), bz + L * Math.cos(p * r) * Math.sin(y1 * r)], rot: [0, y1, p] };
};
// left crescent upright before the body (cover), then pulled back to the hip with its point on the opponent, low
// (both scanned for the wrist: 0 deg of clamp; the first version stood the blade up at the hip and cut the hair tail)
const FLICK_COVER = hand([0.36, 1.08, -0.1], [0.2, 0.95, 0.2], [-0.97, 0.2, 0.1]);
const FLICK_PULL = hand([0, 0.92, -0.26], [0.9, -0.2, 0.38], [0, 1, 0]);
defineClip('iska.rime_flick', {
  duration: 0.3, breath: 0.2,
  keys: [
    { t: 0, pose: S },
    // the blade is turned up through the vertical on its way over the shoulder (a steering key: without it the wrist
    // is asked for 200 deg in three frames and the blade flips)
    { t: 0.025, ik: { handR: hand([0.14, 1.15, 0.26], [0.25, 0.93, 0.27], [-0.9, 0.3, -0.3]) } },
    // gather
    { t: 0.05, ease: 'outCubic', hips: { pos: [-0.065, -0.095, 0.012], rot: [2, -42, 2] },
      bones: { spine: [2, -6, 5], chest: [2, -12, 6], neck: [0, 16, 0], head: [0, 22, -4], shoulderR: [0, -10, 0] },
      ik: { handR: CUT.cock, handL: FLICK_COVER, footR: ball(FR, YAW_R, -26) } },
    // the hips lead: turned through 28 deg while the blade is only over the top
    { t: 0.07, hips: { pos: [0.01, -0.115, 0], rot: [0, -12, -1] }, bones: { shoulderR: [0, 2, 0] }, ik: { handR: CUT.over } },
    // the cut
    { t: 0.09, hips: { pos: [0.085, -0.135, -0.01], rot: [-3, 15, -4] },
      bones: { spine: [-2, 10, -9], chest: [-3, 10, -7], neck: [0, -12, 4], head: [0, -16, 6], shoulderR: [0, 14, 0] },
      ik: { handR: CUT.hit, handL: FLICK_PULL, footR: pivot(FR, YAW_R, -16, -34) } },
    // kime: two frames at full reach
    { t: 0.117, ease: 'outQuad', hips: { pos: [0.092, -0.14, -0.01], rot: [-3, 18, -4] },
      ik: { handR: hand([0.61, 1.08, -0.03], [0.88, 0.04, -0.47], [0.22, 0.55, 0.8]) } },
    // follow-through: the crescent rolls on down and across the body
    { t: 0.15, ease: 'inQuad', hips: { pos: [0.09, -0.14, -0.012], rot: [-3, 23, -4] },
      bones: { spine: [-2, 12, -10], chest: [-3, 12, -8], neck: [0, -14, 4], head: [0, -18, 6], shoulderR: [0, 10, 0] }, ik: { handR: CUT.thru } },
    // the circle closes from below; the body floats up past the stance
    { t: 0.21, ease: 'inOutSine', hips: { pos: [0.02, -0.085, 0], rot: [-1, -4, -1] }, bones: { spine: [0, 2, -4], chest: [-1, 0, -3], neck: [0, 2, 3], head: [0, 2, 0], shoulderR: [0, 2, 0] },
      ik: { handR: hand([0.33, 0.84, 0.0], [0.34, -0.74, -0.58], [0.9, 0.42, 0.1]), footR: pivot(FR, YAW_R, -30, -22) } },
    { t: 0.26, ease: 'inOutSine', hips: { pos: [-0.035, -0.066, 0], rot: [0, -27, 0] }, ik: { footR: ball(FR, YAW_R, -18) } },
    { t: 0.3, ease: 'inOutSine', pose: S, bones: { shoulderR: [0, 0, 0] } },
  ],
  events: ev([[0.09, 'impact']]),
});

// ======================================================================================================================
// light2 - Twin Moons (0.36): left descending diagonal (.10) then right (.17): an X of two thin crescents. Steps 0.24 m.
defineClip('iska.twin_moons', {
  duration: 0.36, breath: 0.2,
  keys: [
    { t: 0, pose: S, root: { pos: [0, 0] }, ik: { footL: o(foot(FL, YAW_L, PITCH)), footR: o(foot(FR, YAW_R, PITCH)) } },
    // wind-up: left blade cocked over the left shoulder, hips turned away (left shoulder back), lead foot lifts
    { t: 0.05, ease: 'outCubic', hips: { pos: [-0.03, -0.1, -0.01], rot: [-2, 4, -2] },
      bones: { spine: [-2, 6, 4], chest: [-2, 8, 5], neck: [0, -2, 0], head: [0, -2, -4] },
      ik: { handL: CUTL.cock, handR: GUARD_R, footL: o(foot(add(FL, [0.12, 0.07, 0]), YAW_L, -8)) } },
    { t: 0.075, hips: { rot: [0, -16, 0] }, ik: { handL: CUTL.over } },
    // left cut lands with the lead foot (weight onto it)
    { t: 0.1, ease: 'inQuad', root: { pos: [0.24, 0] }, hips: { pos: [0.08, -0.13, 0.01], rot: [2, -46, 3] },
      bones: { spine: [2, -10, -9], chest: [3, -12, -7], neck: [0, 14, 4], head: [0, 18, 4] },
      ik: { handL: CUTL.hit, handR: CUT.cock, footL: o(foot(add(FL, [0.24, 0, 0]), YAW_L, -6)) } },
    { t: 0.13, ease: 'outQuad', hips: { rot: [1, -40, 2] }, ik: { handL: CUTL.thru, handR: hand([0.12, 1.4, 0.24], [-0.6, 0.62, 0.48], [0.4, -0.75, 0.5]) } },
    { t: 0.15, hips: { rot: [0, -20, 0] }, ik: { handR: CUT.over } },
    // right cut
    { t: 0.17, hips: { pos: [0.1, -0.14, -0.01], rot: [-3, 16, -4] },
      bones: { spine: [-2, 10, -9], chest: [-3, 11, -7], neck: [0, -12, 4], head: [0, -16, 6] },
      ik: { handR: CUT.hit, handL: hand([0.18, 0.92, -0.1], [0.4, -0.6, 0.7], [0.85, 0.5, -0.1]), footR: o(ball(FR, YAW_R, -34)) } },
    { t: 0.22, ease: 'outQuad', hips: { pos: [0.1, -0.15, -0.01], rot: [-3, 22, -4] }, bones: { spine: [-2, 12, -10], chest: [-3, 12, -8] },
      ik: { handR: CUT.thru } },
    // trail foot drags up to re-form the stance
    { t: 0.26, ease: 'inOutSine', ik: { footR: o(foot(add(FR, [0.14, 0.05, 0]), YAW_R, -24)) } },
    { t: 0.3, ease: 'inQuad', hips: { pos: [0.0, -0.1, 0], rot: [-1, -12, -1] }, ik: { footR: o(foot(add(FR, [0.24, 0, 0]), YAW_R, PITCH)), handR: hand([0.28, 0.94, 0.06], [0.55, -0.62, -0.55], [0.82, 0.55, 0]) } },
    { t: 0.36, ease: 'inOutSine', pose: S, ik: { footL: o(foot(add(FL, [0.24, 0, 0]), YAW_L, PITCH)), footR: o(foot(add(FR, [0.24, 0, 0]), YAW_R, PITCH)) } },
  ],
  events: ev([[0.1, 'impact'], [0.1, 'step', { foot: 'footL' }], [0.17, 'cut'], [0.3, 'step', { foot: 'footR' }]]),
});

// ======================================================================================================================
// light3 - Star Fan (0.56): coil, a left-turning pirouette with both blades out (cut .16 hits front and back), arms
// pull in to whip the turn, then both blades fan open forward (.25, shards, knockback). Moves 0.3 m (.04-.16).
{
  const PIV = (y) => ({ space: 'hips', pos: [0.04, y, -0.09], rot: [0, 6, -20] });
  const PASSE = (y) => ({ space: 'hips', pos: [0.1, y + 0.34, 0.06], rot: [0, -18, -48] });
  const OUT = (k) => ({
    handR: { space: 'chest', pos: [0.06, -0.04 - 0.04 * k, 0.5], aim: [0.62, 0.05, 0.78], up: [-0.78, 0.1, 0.62] },
    handL: { space: 'chest', pos: [0.06, -0.04 - 0.04 * k, -0.5], aim: [0.62, 0.05, -0.78], up: [-0.78, 0.1, -0.62] },
  });
  const IN = {
    handR: { space: 'chest', pos: [0.26, -0.06, -0.04], aim: [0.2, 0.7, -0.68], up: [0.95, -0.15, 0.2] },
    handL: { space: 'chest', pos: [0.28, -0.03, 0.05], aim: [0.2, 0.7, 0.68], up: [0.95, -0.15, -0.2] },
  };
  defineClip('iska.star_fan', {
    duration: 0.56, breath: 0,
    keys: [
      { t: 0, pose: S, root: { pos: [0, 0] } },
      { t: 0.04, root: { pos: [0, 0] } },
      // coil: turn right, blades gathered low on the right, sink
      { t: 0.07, ease: 'outCubic', hips: { pos: [-0.02, -0.12, 0], rot: [0, -54, 0] },
        bones: { spine: [0, -10, -4], chest: [0, -12, -2], neck: [0, 22, 0], head: [0, 28, -2] },
        ik: { handR: hand([-0.02, 0.98, 0.3], [-0.4, -0.3, 0.86], [-0.5, 0.86, 0.1]), handL: hand([0.08, 1.0, 0.18], [-0.3, -0.4, 0.86], [-0.4, 0.88, 0.2]),
          footL: foot(FL, YAW_L, -8), footR: ball(FR, YAW_R, -26) } },
      // unwinding: blades fly out, onto the ball of the lead foot
      { t: 0.11, hips: { pos: [0.0, -0.07, 0], rot: [0, 10, 0] }, bones: { spine: [0, 8, -2], chest: [0, 8, -2], neck: [0, -4, 0], head: [0, -6, 0] },
        ik: { ...OUT(0), footL: PIV(-0.935), footR: PASSE(-0.935) } },
      // cut 1 (.16): right arm forward, left arm behind - both sides hit
      { t: 0.16, root: { pos: [0.3, 0] }, hips: { pos: [0.01, -0.05, 0], rot: [0, 110, 0] }, bones: { spine: [0, -8, -2], chest: [0, -10, 0], neck: [0, 6, 0], head: [0, 8, 0] },
        ik: { ...OUT(0.5), footL: PIV(-0.955), footR: PASSE(-0.955) } },
      // arms pull in, the turn whips around
      { t: 0.21, hips: { pos: [0.02, -0.06, 0], rot: [0, 250, 0] }, ik: { ...IN, footL: PIV(-0.945), footR: PASSE(-0.945) } },
      { t: 0.235, ik: { footL: PIV(-0.95), footR: PASSE(-0.95) } },
      // the fan: both blades thrown open forward, lunge onto the lead foot
      { t: 0.25, hips: { pos: [0.08, -0.15, 0], rot: [-2, 344, -2] },
        bones: { spine: [0, 6, -10], chest: [0, 8, -8], neck: [0, -2, 6], head: [0, -2, 8] },
        ik: { handR: hand([0.5, 1.22, 0.38], [0.62, 0.3, 0.72], [-0.72, 0.62, 0.3]), handL: hand([0.52, 1.18, -0.36], [0.62, 0.3, -0.72], [-0.72, 0.62, -0.3]),
          footL: foot(add(FL, [0.12, -0.02, 0]), YAW_L, -4), footR: foot(add(FR, [-0.06, -0.02, 0]), YAW_R, -30) } },
      { t: 0.32, ease: 'outQuad', hips: { pos: [0.1, -0.17, 0], rot: [-2, 338, -2] }, bones: { spine: [0, 0, -9], chest: [0, -1, -7], neck: [0, 6, 6], head: [0, 9, 8] },
        ik: { handR: hand([0.42, 1.18, 0.5], [0.4, 0.2, 0.9], [-0.8, 0.55, 0.3]), handL: hand([0.44, 1.12, -0.48], [0.4, 0.2, -0.9], [-0.8, 0.55, -0.3]) } },
      { t: 0.42, ease: 'inOutSine', hips: { pos: [0.02, -0.12, 0], rot: [-1, 336, -1] }, bones: { spine: [1, -3, -5], chest: [0, -5, -4] },
        ik: { handR: hand([0.28, 0.98, 0.2], [0.55, -0.6, -0.55], [0.82, 0.55, 0.1]), handL: hand([0.32, 1.0, -0.12], [0.55, -0.6, 0.55], [0.82, 0.55, -0.1]),
          footL: foot(add(FL, [0.04, 0, 0]), YAW_L, PITCH), footR: foot(FR, YAW_R, -20) } },
      { t: 0.56, ease: 'inOutSine', pose: S, hips: { pos: [-0.03, -0.08, 0], rot: [0, 336, 0] } },
    ],
    events: ev([[0.16, 'impact'], [0.25, 'cut'], [0.25, 'step', { foot: 'footR' }]]),
  });
}

// ======================================================================================================================
// heavy - Glacier Pirouette (0.78): crouch and coil, two whirling revolutions on the lead foot with both blades out
// (cuts .22 right blade, .30 left blade), the third pass drops low and throws the frost ring (.38); drifts 0.54 m.
{
  const PIV = (y, s = -0.09) => ({ space: 'hips', pos: [0.04, y, s], rot: [0, 6, -22] });
  const PASSE = (y) => ({ space: 'hips', pos: [0.12, y + 0.36, 0.07], rot: [0, -18, -50] });
  const OUT = (y, k = 0) => ({
    handR: { space: 'chest', pos: [0.08, y, 0.52], aim: [0.6, 0.1 - 0.4 * k, 0.78], up: [-0.78, 0.1, 0.6] },
    handL: { space: 'chest', pos: [0.08, y, -0.52], aim: [0.6, 0.1 - 0.4 * k, -0.78], up: [-0.78, 0.1, -0.6] },
  });
  const spin = (t, yaw, hy, y, extra = {}) => ({ t, hips: { pos: [0.02, hy, 0], rot: [0, yaw, 0] }, bones: { spine: [0, -9, -2], chest: [0, -11, 0], neck: [0, 8, 0], head: [0, 10, 0] }, ik: { ...OUT(-0.04), footL: PIV(y), footR: PASSE(y), ...extra } });
  defineClip('iska.glacier_pirouette', {
    duration: 0.78, breath: 0,
    keys: [
      { t: 0, pose: S, root: { pos: [0, 0] } },
      // gather: sink, turn the shoulders right, blades crossed low at the right hip
      { t: 0.12, ease: 'outCubic', root: { pos: [0, 0] }, hips: { pos: [-0.04, -0.2, 0], rot: [0, -62, 0] },
        bones: { spine: [0, -12, -8], chest: [0, -14, -6], neck: [0, 24, 6], head: [0, 30, 4] },
        ik: { handR: hand([0.0, 0.9, 0.3], [-0.3, -0.5, 0.82], [-0.5, 0.82, 0.25]), handL: hand([0.1, 0.92, 0.2], [-0.2, -0.55, 0.8], [-0.4, 0.82, 0.4]),
          footL: foot(FL, YAW_L, -4), footR: ball(FR, YAW_R, -30) } },
      // spring onto the ball of the lead foot, arms fly out
      { t: 0.17, hips: { pos: [0.0, -0.06, 0], rot: [0, 10, 0] }, bones: { spine: [0, 6, -2], chest: [0, 6, 0], neck: [0, -2, 0], head: [0, -4, 0] },
        ik: { ...OUT(-0.02), footL: PIV(-0.94), footR: PASSE(-0.94) } },
      spin(0.22, 90, -0.04, -0.96),
      spin(0.26, 180, -0.04, -0.96),
      spin(0.3, 270, -0.05, -0.955),
      // third pass: drop low, blades sweep low (frost ring)
      { t: 0.34, hips: { pos: [0.02, -0.16, 0], rot: [0, 360, 0] }, bones: { spine: [0, 0, -12], chest: [0, 0, -10] },
        ik: { ...OUT(-0.14, 0.5), footL: PIV(-0.85), footR: PASSE(-0.85) } },
      { t: 0.38, hips: { pos: [0.04, -0.3, 0], rot: [0, 450, 0] }, bones: { spine: [0, 0, -18], chest: [0, 0, -14], neck: [0, 0, 10], head: [0, 0, 14] },
        ik: { ...OUT(-0.2, 1), footL: PIV(-0.71, -0.1), footR: { space: 'hips', pos: [-0.2, -0.62, 0.24], rot: [0, -40, -30] } } },
      { t: 0.415, ik: { footL: PIV(-0.71, -0.1), footR: { space: 'hips', pos: [-0.2, -0.62, 0.24], rot: [0, -40, -30] } } },
      // land the right foot wide and low, blades flung wide (aftermath pose)
      { t: 0.44, ease: 'outQuad', root: { pos: [0.54, 0] }, hips: { pos: [0.02, -0.3, 0], rot: [-2, 640, -2] },
        bones: { spine: [0, 8, -12], chest: [0, 10, -8], neck: [0, -4, 8], head: [0, -6, 10] },
        ik: { handR: hand([0.12, 0.92, 0.52], [0.45, -0.2, 0.86], [-0.8, 0.5, 0.3]), handL: hand([0.4, 0.95, -0.42], [0.6, -0.2, -0.76], [-0.7, 0.6, -0.3]),
          footL: foot([0.27, 0, -0.08], -40, 0), footR: foot([-0.34, 0, 0.17], -75, -24) } },
      { t: 0.52, ease: 'inOutSine', hips: { pos: [0.0, -0.28, 0], rot: [-1, 638, -1] }, bones: { spine: [0, -2, -12], chest: [0, -3, -8], neck: [0, 8, 8], head: [0, 12, 10] },
        ik: { handR: hand([0.1, 0.9, 0.5], [0.45, -0.25, 0.86]), handL: hand([0.38, 0.93, -0.4], [0.6, -0.25, -0.76]) } },
      { t: 0.66, ease: 'inOutSine', hips: { pos: [-0.02, -0.14, 0], rot: [0, 700, 0] }, bones: { spine: [1, -4, -4], chest: [0, -6, -3] },
        ik: { handR: hand([0.25, 0.95, 0.16], [0.52, -0.64, -0.56], [0.86, 0.5, 0.1]), handL: hand([0.3, 0.97, -0.1], [0.52, -0.62, 0.58], [0.84, 0.54, -0.1]),
          footL: foot(FL, YAW_L, -6), footR: foot([-0.32, 0.07, 0.16], -60, -30) } },
      { t: 0.57, ease: 'inOutSine', ik: { footL: foot([0.26, 0.05, -0.1], -10, -20) } },
      { t: 0.62, ease: 'inQuad', ik: { footL: foot(FL, YAW_L, -6) } },
      { t: 0.73, ease: 'inQuad', ik: { footR: foot(FR, YAW_R, -14) } },
      { t: 0.78, ease: 'inOutSine', pose: S, hips: { pos: [-0.03, -0.08, 0], rot: [0, 696, 0] } },
    ],
    events: ev([[0.22, 'impact'], [0.3, 'cut'], [0.38, 'cut'], [0.44, 'step', { foot: 'footR' }], [0.62, 'step', { foot: 'footL' }], [0.73, 'step', { foot: 'footR' }]]),
  });
}

// ======================================================================================================================
// f+heavy - Frostline Step (0.64): crouch, push off, a long low skating slide on the ice line (3.5 m) with scissor
// cuts (right .18, left .23), a braking skid (.40) and the recovery. Feet glide with the root while she slides.
defineClip('iska.frostline_step', {
  duration: 0.64, breath: 0,
  keys: [
    { t: 0, pose: S, root: { pos: [0, 0] } },
    // crouch, blades swept back low
    { t: 0.06, ease: 'outCubic', hips: { pos: [-0.06, -0.24, 0], rot: [0, -30, 0] },
      bones: { spine: [0, -4, -14], chest: [0, -4, -10], neck: [0, 8, 12], head: [0, 10, 14] },
      ik: { handR: hand([-0.12, 0.88, 0.3], [-0.85, 0.15, 0.5], [0.1, 0.98, 0.1]), handL: hand([-0.04, 0.9, -0.28], [-0.85, 0.15, -0.5], [0.1, 0.98, -0.1]),
        footL: foot(add(FL, [0.06, -0.02, 0]), YAW_L, -2), footR: foot(FR, YAW_R, -30) } },
    { t: 0.1, root: { pos: [0.2, 0] } },
    // the slide: deep skater lunge, rear leg long
    { t: 0.14, ease: 'inOutSine', hips: { pos: [0.02, -0.32, 0], rot: [0, -28, 2] },
      bones: { spine: [0, -4, -16], chest: [0, -4, -12], neck: [0, 8, 14], head: [0, 10, 16] },
      ik: { handR: hand([-0.16, 0.9, 0.32], [-0.85, 0.15, 0.5], [0.1, 0.98, 0.1]), handL: hand([-0.06, 0.92, -0.3], [-0.85, 0.15, -0.5], [0.1, 0.98, -0.1]),
        footL: foot([0.5, 0, -0.13], 12, 0), footR: foot([-0.62, 0.02, 0.15], -50, -40) } },
    // scissor cuts: each arm sweeps from out-back to across the front, blade at a right angle to the forearm
    { t: 0.155, ik: { handR: sweep(120, 1.06), handL: mir(sweep(100, 1.0)) } },
    { t: 0.18, root: { pos: [0.8, 0] }, hips: { rot: [0, 10, -2] }, bones: { spine: [0, 8, -14], chest: [0, 10, -10], neck: [0, -8, 14], head: [0, -10, 16] },
      ik: { handR: sweep(40, 1.1) } },
    { t: 0.21, ease: 'outQuad', ik: { handR: sweep(-35, 1.04), handL: mir(sweep(115, 1.04)) } },
    { t: 0.23, hips: { rot: [0, -40, 2] }, bones: { spine: [0, -10, -14], chest: [0, -12, -10], neck: [0, 12, 14], head: [0, 14, 16] },
      ik: { handL: mir(sweep(40, 1.08)) } },
    { t: 0.27, ease: 'outQuad', ik: { handL: mir(sweep(-35, 1.02)), handR: sweep(60, 1.0) } },
    { t: 0.32, root: { pos: [3.1, 0] }, hips: { pos: [0.0, -0.3, 0], rot: [0, -36, 0] } },
    // brake: front foot skids, body rises a little and settles back
    { t: 0.4, ease: 'outQuad', root: { pos: [3.5, 0] }, hips: { pos: [-0.08, -0.26, 0], rot: [-2, -32, 0] },
      bones: { spine: [0, -6, -4], chest: [0, -8, -2], neck: [0, 12, 4], head: [0, 14, 2] },
      ik: { handR: hand([0.06, 0.96, 0.46], [0.3, -0.3, 0.9], [-0.7, 0.7, 0.2]), handL: hand([0.3, 0.98, -0.4], [0.5, -0.3, -0.8], [-0.6, 0.75, -0.2]),
        footL: foot([0.4, 0, -0.14], 20, 0), footR: foot([-0.46, 0, 0.16], -44, -24) } },
    { t: 0.48, ease: 'inOutSine', hips: { pos: [-0.06, -0.2, 0], rot: [-1, -28, 0] } },
    { t: 0.56, ease: 'inOutSine', ik: { footR: foot([-0.34, 0.05, 0.15], YAW_R, -24) } },
    { t: 0.6, ease: 'inQuad', ik: { footR: foot(FR, YAW_R, PITCH) } },
    { t: 0.64, ease: 'inOutSine', pose: S },
  ],
  events: ev([[0.18, 'impact'], [0.23, 'cut'], [0.4, 'step', { foot: 'footL' }], [0.6, 'step', { foot: 'footR' }]]),
});

// ======================================================================================================================
// d+heavy - Rising Crescent (0.62): step in low, both blades scoop up through the opponent (.16, launch) as she throws
// herself into a backflip (root up to 1 m at .32), tucks, lands crouched (.50) 0.2 m behind the start.
{
  // the tuck is FK (the legs ride the pelvis through the inversion); foot IK fades out for it and back in to land
  const TUCK = (k) => ({ footL: { w: 0 }, footR: { w: 0 } });
  const TUCKB = (k) => ({ thighL: [2, 0, 40 + 80 * k], shinL: [0, 0, -40 - 90 * k], footL: [0, 0, -30], thighR: [-2, 0, 30 + 85 * k], shinR: [0, 0, -50 - 85 * k], footR: [0, 0, -30] });
  const OVER = {
    handR: { space: 'chest', pos: [0.2, 0.48, 0.36], aim: [0.6, 0.6, 0.5], up: [0.5, -0.8, 0.3] },
    handL: { space: 'chest', pos: [0.22, 0.46, -0.36], aim: [0.6, 0.6, -0.5], up: [0.5, -0.8, -0.3] },
  };
  defineClip('iska.rising_crescent', {
    duration: 0.62, breath: 0,
    keys: [
      { t: 0, pose: S, root: { pos: [0, 0] }, ik: { footL: o(foot(FL, YAW_L, PITCH)), footR: o(foot(FR, YAW_R, PITCH)) } },
      // step in low, blades down by the lead foot, edges up
      { t: 0.08, ease: 'outCubic', hips: { pos: [0.04, -0.26, 0], rot: [0, -20, -6] },
        bones: { spine: [0, -4, -14], chest: [0, -4, -10], neck: [0, 6, 12], head: [0, 8, 16] },
        ik: { handR: hand([0.42, 0.6, 0.14], [0.5, -0.8, -0.2], [0.8, 0.5, 0.2]), handL: hand([0.44, 0.62, -0.08], [0.5, -0.8, 0.2], [0.8, 0.5, -0.2]),
          footL: o(foot(add(FL, [0.28, 0, 0]), YAW_L, 0)), footR: o(foot(FR, YAW_R, -30)) } },
      { t: 0.1, root: { pos: [0.3, 0.05] } },
      // the scoop: arms rise through the front, the body arches back, the rear leg kicks
      { t: 0.13, ik: { handR: hand([0.56, 1.0, 0.14], [0.75, 0.6, 0.2], [-0.6, 0.78, 0.1]), handL: hand([0.58, 1.02, -0.1], [0.75, 0.6, -0.2], [-0.6, 0.78, -0.1]) } },
      { t: 0.16, hips: { pos: [0.02, -0.08, 0], rot: [0, -18, 18] },
        bones: { spine: [0, -2, 8], chest: [0, -2, 10], neck: [0, 4, -6], head: [0, 6, -10] },
        ik: { handR: hand([0.5, 1.42, 0.16], [0.4, 0.9, 0.2], [-0.9, 0.4, 0.0]), handL: hand([0.52, 1.4, -0.12], [0.4, 0.9, -0.2], [-0.9, 0.4, 0.0]),
          footL: { space: 'hips', pos: [0.06, -0.93, -0.1], rot: [0, 0, -50], w: 1 }, footR: { space: 'hips', pos: [0.32, -0.66, 0.11], rot: [0, 0, -10], w: 1 } } },
      { t: 0.2, root: { pos: [0.2, 0.55] } },
      { t: 0.22, hips: { pos: [0, -0.06, 0], rot: [0, -16, 110] }, bones: { spine: [0, 0, 8], chest: [0, 0, 8], neck: [0, 0, -4], head: [0, 0, -6], ...TUCKB(0.6) },
        ik: { ...OVER, ...TUCK(0.6) } },
      { t: 0.32, root: { pos: [-0.05, 1.0] }, hips: { pos: [0, -0.04, 0], rot: [0, -14, 200] }, bones: TUCKB(1), ik: { ...OVER, ...TUCK(1) } },
      { t: 0.42, hips: { pos: [0, -0.06, 0], rot: [0, -16, 300] }, bones: { spine: [0, -2, -6], chest: [0, -2, -4], neck: [0, 4, 6], head: [0, 6, 10], ...TUCKB(0.3) },
        ik: { handR: { space: 'chest', pos: [0.2, -0.1, 0.42], aim: [0.6, -0.2, 0.78], up: [-0.6, 0.8, 0] }, handL: { space: 'chest', pos: [0.22, -0.08, -0.42], aim: [0.6, -0.2, -0.78], up: [-0.6, 0.8, 0] }, ...TUCK(0.35) } },
      { t: 0.46, root: { pos: [-0.2, 0.45] } },
      // touch-down: crouched, blades out wide
      { t: 0.5, ease: 'inQuad', hips: { pos: [-0.02, -0.28, 0], rot: [0, -22, 360] }, bones: { spine: [0, -4, -10], chest: [0, -6, -6], neck: [0, 8, 6], head: [0, 12, 8] },
        ik: { handR: hand([0.12, 0.86, 0.46], [0.5, -0.3, 0.8], [-0.7, 0.7, 0.1]), handL: hand([0.36, 0.9, -0.4], [0.55, -0.3, -0.78], [-0.7, 0.7, -0.1]),
          footL: foot(add(FL, [0.04, -0.02, 0]), YAW_L, 0, { w: 1 }), footR: foot(add(FR, [-0.06, -0.02, 0]), YAW_R, -20, { w: 1 }) } },
      { t: 0.56, root: { pos: [-0.2, 0] }, ease: 'inOutSine', hips: { pos: [-0.03, -0.2, 0], rot: [0, -23, 360] } },
      { t: 0.62, ease: 'inOutSine', pose: S, hips: { pos: [-0.03, -0.08, 0], rot: [0, -24, 360] } },
    ],
    events: ev([[0.16, 'impact'], [0.5, 'step', { foot: 'footL' }]]),
  });
}

// ======================================================================================================================
// skill1 - Starshard Volley (0.62): blades cross before the chest (crystallise .04), three flings: right high (.18),
// left mid (.24), right low with a lunge (.30, the freezing shard).
{
  const XR = { ...X_R, pos: [0.32, 1.24, -0.07] };
  const XL = { ...X_L, pos: [0.34, 1.21, 0.08] };
  const BACK_R = hand([0.06, 1.42, 0.3], [-0.75, 0.45, 0.48], [0.4, -0.85, 0.3], { pole: [0.3, 1.3, 0.75] });
  const BACK_L = mir(BACK_R);
  defineClip('iska.starshard_volley', {
    duration: 0.62, breath: 0.2,
    keys: [
      { t: 0, pose: S },
      { t: 0.05, ease: 'outCubic', hips: { pos: [-0.05, -0.1, 0], rot: [0, -24, 0] }, bones: { spine: [0, -6, -4], chest: [0, -8, -2], neck: [0, 8, 4], head: [0, 12, 2] },
        ik: { handR: XR, handL: XL } },
      { t: 0.12, ease: 'inOutSine', hips: { pos: [-0.07, -0.11, 0.01], rot: [2, -44, 2] }, bones: { spine: [2, -8, 4], chest: [2, -12, 5], neck: [0, 16, 0], head: [0, 22, -2] },
        ik: { handR: BACK_R, handL: hand([0.28, 1.2, -0.08], [0.3, 0.75, 0.6], [0.9, -0.2, -0.38]), footR: foot(FR, YAW_R, -24) } },
      // fling 1: right, high
      { t: 0.18, hips: { pos: [0.04, -0.11, 0], rot: [-2, 8, -2] }, bones: { spine: [-2, 8, -6], chest: [-2, 10, -4], neck: [0, -10, 2], head: [0, -14, 2] },
        ik: { handR: hand([0.6, 1.36, 0.02], [0.9, 0.1, -0.4], [0.2, 0.5, 0.85]), handL: BACK_L } },
      // fling 2: left, mid
      { t: 0.24, hips: { pos: [0.06, -0.13, 0], rot: [2, -46, 2] }, bones: { spine: [2, -10, -6], chest: [2, -12, -4], neck: [0, 14, 2], head: [0, 18, 2] },
        ik: { handL: hand([0.6, 1.18, -0.02], [0.9, 0.1, 0.4], [0.2, 0.5, -0.85]), handR: hand([0.08, 1.24, 0.32], [-0.7, 0.3, 0.64], [0.4, -0.9, 0.2], { pole: [0.3, 1.2, 0.75] }) } },
      // fling 3: right, low lunge (the freezing shard)
      { t: 0.3, hips: { pos: [0.12, -0.2, -0.01], rot: [-3, 12, -4] }, bones: { spine: [-2, 10, -12], chest: [-3, 12, -10], neck: [0, -12, 8], head: [0, -16, 10] },
        ik: { handR: hand([0.66, 1.0, 0.0], [0.9, -0.1, -0.4], [0.25, 0.45, 0.85]), handL: hand([0.08, 1.0, -0.32], [-0.6, 0.2, -0.78], [0.3, 0.95, -0.1]),
          footL: foot(add(FL, [0.04, -0.02, 0]), YAW_L, -2), footR: foot(FR, YAW_R + 4, -36) } },
      { t: 0.38, ease: 'outQuad', hips: { pos: [0.12, -0.21, -0.01], rot: [-3, 16, -4] },
        ik: { handR: hand([0.58, 0.92, -0.06], [0.75, 0.1, -0.65], [-0.2, 0.98, 0.0]) } },
      { t: 0.5, ease: 'inOutSine', hips: { pos: [0.02, -0.12, 0], rot: [-1, -12, -1] }, bones: { spine: [0, 0, -5], chest: [0, -2, -4], neck: [0, 4, 3], head: [0, 6, 0] },
        ik: { handR: hand([0.3, 0.95, 0.06], [0.55, -0.62, -0.55], [0.82, 0.55, 0.05]), handL: hand([0.26, 0.96, -0.08], [0.52, -0.62, 0.58], [0.84, 0.54, -0.1]),
          footL: foot(FL, YAW_L, PITCH), footR: foot(FR, YAW_R, -20) } },
      { t: 0.62, ease: 'inOutSine', pose: S },
    ],
    events: ev([[0.18, 'impact'], [0.24, 'cut'], [0.3, 'cut']]),
  });
}

// ======================================================================================================================
// skill2 - Crystal Procession (0.78): rises with both blades high (points down), drives them into the floor in a
// kneel (stab .12), holds while the frost spreads, sends the line with a forward drive (.25), watches it race, rises.
defineClip('iska.crystal_procession', {
  duration: 0.78, breath: 0.3,
  keys: [
    { t: 0, pose: S },
    { t: 0.07, ease: 'outCubic', hips: { pos: [-0.02, -0.02, 0], rot: [0, -18, 0] }, bones: { spine: [0, -2, 6], chest: [0, -2, 8], neck: [0, 4, -4], head: [0, 6, -8] },
      ik: { handR: hand([0.16, 1.74, 0.14], [0.45, 0.2, -0.1], [-0.2, 0.2, 0.96]), handL: hand([0.18, 1.72, -0.12], [0.45, 0.2, 0.1], [-0.2, 0.2, -0.96]),
        footL: foot(FL, YAW_L, -20), footR: foot(FR, YAW_R, -24) } },
    { t: 0.095, ik: { handR: hand([0.42, 1.2, 0.17], [0.3, -0.95, 0.0], [-0.95, -0.3, 0.0], { pole: [0.2, 1.0, 0.6] }), handL: hand([0.44, 1.18, -0.15], [0.3, -0.95, 0.0], [-0.95, -0.3, 0.0], { pole: [0.2, 1.0, -0.6] }) } },
    // stab: kneel, both blades into the floor before the lead foot
    { t: 0.12, ease: 'inQuad', hips: { pos: [-0.04, -0.42, 0], rot: [0, -16, 0] }, bones: { spine: [0, -2, -18], chest: [0, -2, -14], neck: [0, 4, 6], head: [0, 6, 4] },
      ik: { handR: hand([0.62, 0.4, 0.17], [0.1, -0.99, 0.0], [-0.99, -0.1, 0.0], { pole: [0.2, 0.7, 0.6] }), handL: hand([0.64, 0.4, -0.15], [0.1, -0.99, 0.0], [-0.99, -0.1, 0.0], { pole: [0.2, 0.7, -0.6] }),
        footL: foot([0.34, 0, -0.13], 12, 0), footR: foot([-0.36, 0.0, 0.14], -36, -62) } },
    { t: 0.2, ease: 'outQuad', hips: { pos: [-0.05, -0.44, 0] }, bones: { neck: [0, 4, 2], head: [0, 6, 0] },
      ik: { handR: hand([0.62, 0.39, 0.17], [0.1, -0.99, 0.0]), handL: hand([0.64, 0.39, -0.15], [0.1, -0.99, 0.0]) } },
    // release: shoulders drive forward along the line, head up to follow it
    { t: 0.25, ease: 'outCubic', hips: { pos: [0.02, -0.4, 0] }, bones: { spine: [0, -2, -24], chest: [0, -2, -18], neck: [0, 4, 18], head: [0, 6, 22] },
      ik: { handR: hand([0.68, 0.4, 0.17], [0.3, -0.95, 0.0], [-0.95, -0.3, 0.0]), handL: hand([0.7, 0.4, -0.15], [0.3, -0.95, 0.0], [-0.95, -0.3, 0.0]) } },
    { t: 0.5, ease: 'inOutSine', hips: { pos: [0.01, -0.39, 0] }, bones: { neck: [0, 4, 16], head: [0, 6, 18] } },
    // wrench free and rise
    { t: 0.6, ease: 'inOutSine', hips: { pos: [-0.04, -0.24, 0], rot: [0, -22, 0] }, bones: { spine: [0, -4, -6], chest: [0, -6, -4], neck: [0, 8, 4], head: [0, 12, 0] },
      ik: { handR: hand([0.36, 0.86, 0.14], [0.5, -0.6, -0.4], [0.8, 0.55, 0.0]), handL: hand([0.38, 0.88, -0.1], [0.5, -0.6, 0.4], [0.8, 0.55, 0.0]),
        footR: foot([-0.3, 0.02, 0.14], YAW_R, -30) } },
    { t: 0.78, ease: 'inOutSine', pose: S },
  ],
  events: ev([[0.12, 'stab'], [0.25, 'impact']]),
});

// ======================================================================================================================
// skill3 - Moonlit Afterimage (0.70): recoil into the blink (.02, she slides 0.8 m back), vanish (.12-.24), reappear
// behind the opponent coiled with both blades high (.24), double descending X cut (.30), recovery.
defineClip('iska.moonlit_afterimage', {
  duration: 0.7, breath: 0.1,
  keys: [
    { t: 0, pose: S },
    { t: 0.03, ease: 'outCubic', hips: { pos: [-0.12, -0.16, 0], rot: [-2, -30, 4] }, bones: { spine: [0, -6, 8], chest: [0, -8, 10], neck: [0, 10, -6], head: [0, 14, -10] },
      ik: { handR: { ...X_R, pos: [0.26, 1.22, -0.07] }, handL: { ...X_L, pos: [0.28, 1.19, 0.08] },
        footL: foot([0.3, 0.06, -0.12], YAW_L, -30), footR: foot([-0.3, 0.02, 0.14], YAW_R, -30) } },
    { t: 0.12, ease: 'inOutSine', hips: { pos: [-0.14, -0.2, 0], rot: [-2, -30, 6] }, ik: { footL: foot([0.26, 0.03, -0.12], YAW_L, -20) } },
    // reappear: airborne-looking coil, both blades cocked high behind the head
    { t: 0.24, interp: 'step', hips: { pos: [-0.06, -0.06, 0], rot: [0, -26, 8] }, bones: { spine: [0, -4, 10], chest: [0, -6, 12], neck: [0, 6, -6], head: [0, 8, -10] },
      ik: { handR: hand([-0.04, 1.62, 0.2], [-0.7, 0.55, 0.45], [0.3, -0.8, 0.5]), handL: hand([-0.02, 1.6, -0.16], [-0.7, 0.55, -0.45], [0.3, -0.8, -0.5]),
        footL: foot([0.36, 0.1, -0.12], YAW_L, -24), footR: foot([-0.3, 0.02, 0.14], YAW_R, -30) } },
    { t: 0.275, hips: { rot: [0, -20, 0] }, ik: { handR: hand([0.32, 1.66, 0.14], [0.25, 0.95, 0.1], [-0.96, 0.26, 0.05]), handL: hand([0.34, 1.64, -0.1], [0.25, 0.95, -0.1], [-0.96, 0.26, -0.05]) } },
    // the X: both blades come down crossing, lunge onto the lead foot
    { t: 0.3, ease: 'inQuad', hips: { pos: [0.1, -0.24, 0], rot: [-2, -18, -4] }, bones: { spine: [0, -2, -16], chest: [0, -2, -12], neck: [0, 4, 10], head: [0, 6, 12] },
      ik: { handR: hand([0.6, 1.02, -0.06], [0.9, 0.1, -0.4], [0.2, 0.5, 0.85]), handL: hand([0.6, 1.06, 0.06], [0.9, 0.1, 0.4], [0.2, 0.5, -0.85]),
        footL: foot([0.44, 0, -0.13], YAW_L, 0), footR: foot([-0.34, 0.01, 0.15], YAW_R, -34) } },
    { t: 0.37, ease: 'outQuad', hips: { pos: [0.12, -0.27, 0] },
      ik: { handR: hand([0.42, 0.78, -0.22], [0.35, -0.3, -0.88], [0.72, 0.68, 0.1]), handL: hand([0.44, 0.82, 0.2], [0.35, -0.3, 0.88], [0.72, 0.68, -0.1]) } },
    { t: 0.5, ease: 'inOutSine', hips: { pos: [0.03, -0.18, 0], rot: [-1, -22, -2] }, bones: { spine: [0, -4, -6], chest: [0, -6, -4], neck: [0, 8, 4], head: [0, 12, 0] },
      ik: { handR: hand([0.3, 0.92, 0.1], [0.5, -0.66, -0.56]), handL: hand([0.32, 0.94, -0.06], [0.52, -0.62, 0.58]) } },
    { t: 0.58, ease: 'inOutSine', ik: { footL: foot([0.34, 0.05, -0.12], YAW_L, -20) } },
    { t: 0.64, ease: 'inQuad', ik: { footL: foot(FL, YAW_L, PITCH) } },
    { t: 0.7, ease: 'inOutSine', pose: S },
  ],
  events: ev([[0.3, 'impact'], [0.64, 'step', { foot: 'footL' }]]),
});

// ======================================================================================================================
// ult opener - Fall of the Frozen Star (1.45, move clock): head bowed (0), rises and opens (aura .05), twirls both
// blades (.15-.35), points the right blade at the rune (.35) and holds through the super-freeze, sweeps both blades
// overhead (release .6) and drives them down crossed (snap .75 = the trigger). Whiff: recovery to the stance.
{
  const twirl = (t, a) => {
    const c = Math.cos(a), s = Math.sin(a);
    return { t, ik: {
      handR: hand([0.34 + 0.06 * c, 1.18 + 0.08 * s, 0.32], [0.3 * c, s, 0.4], [-0.8 * s, 0.6 * c, 0.1]),
      handL: hand([0.36 - 0.06 * c, 1.16 - 0.08 * s, -0.3], [-0.3 * c, -s, -0.4], [0.8 * s, -0.6 * c, -0.1]),
    } };
  };
  defineClip('iska.frozen_star', {
    duration: 1.45, breath: 0.4,
    keys: [
      { t: 0, pose: S, hips: { pos: [-0.04, -0.12, 0], rot: [0, -22, 0] }, bones: { spine: [0, -4, -6], chest: [0, -4, -6], neck: [0, 4, -10], head: [0, 6, -20] },
        ik: { handR: hand([0.24, 0.9, 0.06], [0.45, -0.7, -0.55], [0.86, 0.5, 0.0]), handL: hand([0.27, 0.92, -0.02], [0.45, -0.7, 0.55], [0.86, 0.5, 0.0]) } },
      // rises tall on the toes, chest opens, arms spread low
      { t: 0.14, ease: 'outCubic', hips: { pos: [-0.04, -0.03, 0], rot: [0, -26, 0] }, bones: { spine: [0, -4, 6], chest: [0, -6, 8], neck: [0, 6, 0], head: [0, 10, 2] },
        ik: { handR: hand([0.2, 1.0, 0.42], [0.3, -0.6, 0.74], [0.7, 0.7, -0.1]), handL: hand([0.26, 1.0, -0.38], [0.3, -0.6, -0.74], [0.7, 0.7, 0.1]),
          footL: foot(FL, YAW_L, -26), footR: foot(FR, YAW_R, -26) } },
      twirl(0.19, 0), twirl(0.24, 2.1), twirl(0.29, 4.2),
      // point the right blade at the rune on the floor, left blade raised behind (counterweight)
      { t: 0.35, ease: 'outCubic', hips: { pos: [0.02, -0.08, 0], rot: [-2, -6, -2] }, bones: { spine: [0, 2, -6], chest: [0, 4, -4], neck: [0, -2, 6], head: [0, -2, 14] },
        ik: { handR: hand([0.54, 0.99, 0.14], [0.85, -0.3, -0.2], [0.3, 0.6, 0.7]), handL: hand([0.04, 1.5, -0.52], [0.0, 0.75, -0.66], [0.95, 0.0, -0.3]),
          footL: foot(add(FL, [0.04, 0, 0]), YAW_L, -6), footR: foot(FR, YAW_R, -22) } },
      { t: 0.58, ease: 'inOutSine', hips: { pos: [0.03, -0.09, 0], rot: [-2, -5, -2] }, ik: { handR: hand([0.55, 0.98, 0.14], [0.85, -0.3, -0.2]), handL: hand([0.03, 1.52, -0.52], [0.0, 0.75, -0.66]) } },
      // release: both blades sweep up overhead (the circle closes)
      { t: 0.66, ease: 'inOutSine', hips: { pos: [-0.02, -0.04, 0], rot: [0, -20, 0] }, bones: { spine: [0, -2, 8], chest: [0, -2, 10], neck: [0, 4, -2], head: [0, 6, -4] },
        ik: { handR: hand([0.16, 1.84, 0.14], [0.4, 0.4, 0.2], [-0.3, 0.2, 0.93]), handL: hand([0.18, 1.82, -0.12], [0.4, 0.4, -0.2], [-0.3, 0.2, -0.93]),
          footL: foot(FL, YAW_L, -24), footR: foot(FR, YAW_R, -24) } },
      { t: 0.71, ik: { handR: hand([0.4, 1.5, 0.16], [0.5, -0.86, 0.0], [-0.86, -0.5, 0.0]), handL: hand([0.42, 1.48, -0.12], [0.5, -0.86, 0.0], [-0.86, -0.5, 0.0]) } },
      // snap: blades driven down crossed, crouch (the trigger frame)
      { t: 0.75, ease: 'inQuad', hips: { pos: [0.02, -0.24, 0], rot: [0, -20, 0] }, bones: { spine: [0, -2, -14], chest: [0, -2, -10], neck: [0, 4, 8], head: [0, 6, 10] },
        ik: { handR: hand([0.44, 0.78, -0.04], [0.45, -0.6, -0.66], [0.85, 0.5, 0.15]), handL: hand([0.46, 0.8, 0.06], [0.45, -0.6, 0.66], [0.85, 0.5, -0.15]),
          footL: foot(add(FL, [0.02, -0.02, 0]), YAW_L, 0), footR: foot(FR, YAW_R, -30) } },
      { t: 0.95, ease: 'outQuad', hips: { pos: [0.02, -0.26, 0] }, ik: { handR: hand([0.44, 0.76, -0.05], [0.45, -0.62, -0.64]), handL: hand([0.46, 0.78, 0.07], [0.45, -0.62, 0.64]) } },
      { t: 1.2, ease: 'inOutSine', hips: { pos: [-0.02, -0.14, 0], rot: [0, -22, 0] }, bones: { spine: [1, -4, -4], chest: [0, -6, -3], neck: [0, 8, 2], head: [0, 12, -2] },
        ik: { handR: hand([0.26, 0.92, 0.1], [0.5, -0.66, -0.56], [0.86, 0.5, 0.1]), handL: hand([0.3, 0.95, -0.06], [0.52, -0.62, 0.58], [0.84, 0.54, -0.1]),
          footL: foot(FL, YAW_L, -6), footR: foot(FR, YAW_R, -16) } },
      { t: 1.45, ease: 'inOutSine', pose: S },
    ],
    events: ev([[0.75, 'impact'], [0.35, 'point']]),
  });
}
