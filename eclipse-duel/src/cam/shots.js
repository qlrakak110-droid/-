// Shot vocabulary: parameterised builders that return shot data for cam.play().
//
// Every builder works in the anchor's fighter-local frame (f forward toward the opponent, u up from the floor, s toward
// the camera side), so a shot list authored once mirrors automatically for the left-facing fighter. `subject` picks
// the frame the shot is built around: 'anchor' | 'target' | 'mid' | any point source (Object3D, () => Vector3 ...).
// Orbit-style angles are degrees from straight-on (+s) toward +f: positive looks at the anchor's front, negative at
// the target's front (the target faces -f).
//
// Every builder also passes through the common shot fields: cut, hold, clock, ease, lookEase, fovEase, shake, kick,
// slowmo, letterbox, handheld, follow, followY, followLag (see README).

import { DEG } from '../core/math.js';

const PASS = ['cut', 'hold', 'clock', 'ease', 'lookEase', 'fovEase', 'shake', 'kick', 'slowmo', 'letterbox', 'handheld', 'follow', 'followY', 'followLag'];

const two = (v) => (Array.isArray(v) ? v : [v, v]);
/** [f, u, s] at `deg` from straight-on, `dist` metres out, `height` above the frame origin. */
const polar = (deg, dist, height) => [Math.sin(deg * DEG) * dist, height, Math.cos(deg * DEG) * dist];

/** Fields a builder may author itself (merged through own()), so finish() does not overwrite them. */
const OWN = { shake: 1, kick: 1 };

/** Copy the common shot fields the caller set. */
function finish(shot, o) {
  for (const k of PASS) if (o[k] !== undefined && !(k in OWN && shot[k] !== undefined)) shot[k] = o[k];
  return shot;
}

/** A builder's default shake / kick, overridden by the caller: number = amount, object / array / false = replace. */
function own(v, def) {
  if (v === undefined) return def;
  if (typeof v === 'number') return { ...def, amount: v };
  return v;
}

/**
 * Low-angle hero push-in: camera near the floor in front of the subject, looking up, slowly dollying in with a fov
 * squeeze. The power-up / super-freeze shot.
 * @param {object} o subject='anchor', dur=1.1, angle=32, dist=[3.6,2.5], height=[0.42,0.55], look=[1.5,1.62],
 *   fov=[36,30], roll=0 (dutch, deg; grows 30% over the shot), arc=-8 (deg the camera swings around the subject)
 */
export function heroPushIn(o = {}) {
  const { subject = 'anchor', dur = 1.1, angle = 32, dist = [3.6, 2.5], height = [0.42, 0.55], look = [1.5, 1.62], fov = [36, 30], roll = 0, arc = -8 } = o;
  const [d0, d1] = two(dist), [h0, h1] = two(height), [l0, l1] = two(look), [f0, f1] = two(fov);
  return finish({
    dur, space: subject, ease: 'inOutSine', handheld: 0.25,
    from: { pos: polar(angle, d0, h0), look: [0, l0, 0], fov: f0, roll },
    to: { pos: polar(angle + arc, d1, h1), look: [0, l1, 0], fov: f1, roll: roll * 1.3 },
  }, o);
}

/**
 * Crash zoom: from far and wide to a tight framing in a fraction of a second (exponential ease: almost all the move
 * happens in the first third), with a small shake on arrival.
 * @param {object} o subject='target', dur=0.36, angle=-18, dist=[10,2.8], height=[1.8,1.5], look=1.45, fov=[50,27],
 *   shake=0.35
 */
export function crashZoom(o = {}) {
  const { subject = 'target', dur = 0.36, angle = -18, dist = [10, 2.8], height = [1.8, 1.5], look = 1.45, fov = [50, 27] } = o;
  const [d0, d1] = two(dist), [h0, h1] = two(height), [f0, f1] = two(fov);
  return finish({
    dur, space: subject, ease: 'outExpo', fovEase: 'outQuart',
    shake: own(o.shake, { amount: 0.35, at: dur * 0.3, freq: 18 }),
    from: { pos: polar(angle, d0, h0), look: [0, look, 0], fov: f0 },
    to: { pos: polar(angle, d1, h1), look: [0, look, 0], fov: f1 },
  }, o);
}

/**
 * Over-the-shoulder: behind the anchor's camera-side shoulder looking at the target, with a slow push.
 * @param {object} o dur=1.3, back=1.7, side=0.62, height=1.95, look=1.4 (target chest), push=0.35, fov=[28,25],
 *   from='anchor' (the shoulder), at='target' (what we look at)
 */
export function overShoulder(o = {}) {
  const { dur = 1.3, back = 1.7, side = 0.62, height = 1.95, look = 1.4, push = 0.35, fov = [28, 25], from = 'anchor', at = 'target' } = o;
  const [f0, f1] = two(fov);
  return finish({
    dur, space: from, lookSpace: at, ease: 'inOutSine', handheld: 0.35,
    from: { pos: [-back, height, side], look: [0, look, 0], fov: f0 },
    to: { pos: [-back + push, height - 0.03, side - 0.04], look: [0, look - 0.03, 0], fov: f1 },
  }, o);
}

/**
 * Whip-pan: a near-static camera that snaps its aim from one subject to another (expo in-out), banking into the pan
 * with a roll kick and a lateral shake that reads as motion blur.
 * @param {object} o dur=0.3, from='anchor', to='target', pos=[-1.2,1.5,3.4] (in the `from` frame), look=1.35, fov=[40,33],
 *   bank=4 (deg)
 */
export function whipPan(o = {}) {
  const { dur = 0.3, from = 'anchor', to = 'target', pos = [-1.2, 1.5, 3.4], look = 1.35, fov = [40, 33], bank = 4 } = o;
  const [f0, f1] = two(fov);
  return finish({
    dur, space: from, ease: 'inOutSine', lookEase: 'inOutExpo',
    kick: own(o.kick, { roll: -bank, at: dur * 0.3, duration: dur * 1.4, attack: dur * 0.3 }),
    shake: own(o.shake, { amount: 0.3, at: dur * 0.25, freq: 9, dir: [1, 0, 0], duration: dur * 1.2 }),
    from: { pos, look: [0, look, 0], lookSpace: from, fov: f0 },
    to: { pos: [pos[0] + 0.5, pos[1], pos[2] - 0.15], look: [0, look, 0], lookSpace: to, fov: f1 },
  }, o);
}

/**
 * Orbit sweep: arcs around a pivot (default the midpoint of both fighters) while rising, keeping it centred.
 * @param {object} o subject='mid', dur=1.3, from=-40, to=35 (deg), radius=[7.2,6.4], height=[1.3,2.5], look=1.2,
 *   fov=38
 */
export function orbitSweep(o = {}) {
  const { subject = 'mid', dur = 1.3, from = -40, to = 35, radius = [7.2, 6.4], height = [1.3, 2.5], look = 1.2, fov = 38 } = o;
  return finish({
    dur, space: subject, ease: 'inOutSine', handheld: 0.2,
    orbit: { pivot: [0, look, 0], from, to, radius, height },
    from: { fov }, to: { fov },
  }, o);
}

/**
 * Impact punch-in: a sharp push toward the struck fighter that decelerates hard, with a fov squeeze, a punchy shake
 * and a roll kick.
 * @param {object} o subject='target', dur=0.45, angle=-28, dist=[3.8,2.4], height=[1.55,1.5], look=1.45,
 *   fov=[36,29], shake=0.55
 */
export function impactPunchIn(o = {}) {
  const { subject = 'target', dur = 0.45, angle = -28, dist = [3.8, 2.4], height = [1.55, 1.5], look = 1.45, fov = [36, 29] } = o;
  const [d0, d1] = two(dist), [h0, h1] = two(height), [f0, f1] = two(fov);
  return finish({
    dur, space: subject, ease: 'outExpo', fovEase: 'outCubic',
    shake: own(o.shake, { amount: 0.55, freq: 20, decay: 1.8 }),
    kick: own(o.kick, { fov: -4, roll: 3, duration: 0.32 }),
    from: { pos: polar(angle, d0, h0), look: [0, look, 0], fov: f0 },
    to: { pos: polar(angle, d1, h1), look: [0, look, 0], fov: f1 },
  }, o);
}

/**
 * Top-down slam view: nearly overhead, looking down at the impact point, slowly turning and settling.
 * @param {object} o subject='target', dur=0.9, height=[7.5,6], toward=[1.4,1.0] (s offset so the view stays readable),
 *   ahead=0 (f offset), look=0.3, fov=[42,38], roll=[0,10] (deg)
 */
export function topDownSlam(o = {}) {
  const { subject = 'target', dur = 0.9, height = [7.5, 6], toward = [1.4, 1.0], ahead = 0, look = 0.3, fov = [42, 38], roll = [0, 10] } = o;
  const [h0, h1] = two(height), [s0, s1] = two(toward), [f0, f1] = two(fov), [r0, r1] = two(roll);
  return finish({
    dur, space: subject, ease: 'outCubic',
    from: { pos: [ahead, h0, s0], look: [0, look, 0], fov: f0, roll: r0 },
    to: { pos: [ahead, h1, s1], look: [0, look, 0], fov: f1, roll: r1 },
  }, o);
}

/**
 * Wide establishing: far, high and slow - the whole arena with both fighters small, drifting sideways and craning up.
 * @param {object} o subject='mid', dur=1.8, dist=[14,13], height=[3.2,3.9], look=[2,1.8], drift=1.6 (f range),
 *   fov=42
 */
export function wideEstablishing(o = {}) {
  const { subject = 'mid', dur = 1.8, dist = [14, 13], height = [3.2, 3.9], look = [2, 1.8], drift = 1.6, fov = 42 } = o;
  const [d0, d1] = two(dist), [h0, h1] = two(height), [l0, l1] = two(look);
  return finish({
    dur, space: subject, ease: 'inOutSine', handheld: 0.15,
    from: { pos: [-drift, h0, d0], look: [-drift * 0.3, l0, 0], fov },
    to: { pos: [drift, h1, d1], look: [drift * 0.3, l1, 0], fov },
  }, o);
}

/**
 * Face close-up: three-quarter front view of the head at eye level with a slow push.
 * @param {object} o subject='anchor', dur=1.1, angle=42 (use a negative angle for the target's face), dist=[1.35,1.05],
 *   height=1.68, look=1.63, fov=[30,27]
 */
export function faceCloseUp(o = {}) {
  const { subject = 'anchor', dur = 1.1, angle = 42, dist = [1.35, 1.05], height = 1.68, look = 1.63, fov = [30, 27] } = o;
  const [d0, d1] = two(dist), [f0, f1] = two(fov);
  return finish({
    dur, space: subject, ease: 'inOutSine', handheld: 0.3,
    from: { pos: polar(angle, d0, height), look: [0, look, 0], fov: f0 },
    to: { pos: polar(angle - 4, d1, height + 0.01), look: [0, look, 0], fov: f1 },
  }, o);
}

/**
 * Weapon-follow: rides alongside a moving subject (the dashing anchor, or a weapon socket passed as `subject`),
 * slightly behind, aiming ahead along the line of travel.
 * @param {object} o subject='anchor', dur=0.6, pos=[[-1.3,1.1,2.1],[-0.9,1.2,1.85]], look=[[1.6,1.2,0],[2.0,1.1,0]],
 *   fov=[48,44], roll=[4,2], followLag=0.08
 */
export function weaponFollow(o = {}) {
  const { subject = 'anchor', dur = 0.6, pos = [[-1.3, 1.1, 2.1], [-0.9, 1.2, 1.85]], look = [[1.6, 1.2, 0], [2.0, 1.1, 0]], fov = [48, 44], roll = [4, 2] } = o;
  const [f0, f1] = two(fov), [r0, r1] = two(roll);
  return finish({
    dur, space: subject, ease: 'linear', follow: true, followLag: 0.08, followY: true,
    from: { pos: pos[0], look: look[0], fov: f0, roll: r0 },
    to: { pos: pos[1], look: look[1], fov: f1, roll: r1 },
  }, o);
}

/**
 * Ground-level skim: the camera races along the floor (from behind the anchor toward the target by default), looking
 * up. With subject frames 'mid' + follow:'look' + followY it becomes the low "looking up at the airborne fight" shot.
 * @param {object} o dur=0.9, from=[-0.9,0.28,1.3], fromSpace='anchor', to=[-1.3,0.32,1.1], toSpace='target',
 *   look=[[2,0.8,0],[0,1.25,0]], lookSpace=['anchor','target'], fov=[52,44], roll=[-3,0]
 */
export function groundSkim(o = {}) {
  const { dur = 0.9, from = [-0.9, 0.28, 1.3], fromSpace = 'anchor', to = [-1.3, 0.32, 1.1], toSpace = 'target', look = [[2, 0.8, 0], [0, 1.25, 0]], lookSpace = ['anchor', 'target'], fov = [52, 44], roll = [-3, 0] } = o;
  const [f0, f1] = two(fov), [r0, r1] = two(roll), [ls0, ls1] = two(lookSpace);
  return finish({
    dur, space: fromSpace, ease: 'inOutQuad',
    from: { pos: from, look: look[0], lookSpace: ls0, fov: f0, roll: r0 },
    to: { pos: to, space: toSpace, look: look[1], lookSpace: ls1, fov: f1, roll: r1 },
  }, o);
}

/**
 * Dutch-angle drift: a tilted, uneasy medium shot that slides sideways while the tilt deepens.
 * @param {object} o subject='anchor', dur=1.6, angle=18, dist=4, height=[1.55,1.7], look=1.4, roll=[8,12],
 *   drift=0.8 (f range), fov=36
 */
export function dutchDrift(o = {}) {
  const { subject = 'anchor', dur = 1.6, angle = 18, dist = 4, height = [1.55, 1.7], look = 1.4, roll = [8, 12], drift = 0.8, fov = 36 } = o;
  const [h0, h1] = two(height), [r0, r1] = two(roll);
  const p0 = polar(angle, dist, h0), p1 = polar(angle, dist, h1);
  return finish({
    dur, space: subject, ease: 'inOutSine', handheld: 0.3,
    from: { pos: [p0[0] - drift * 0.5, p0[1], p0[2]], look: [-drift * 0.15, look, 0], fov, roll: r0 },
    to: { pos: [p1[0] + drift * 0.5, p1[1], p1[2]], look: [drift * 0.15, look, 0], fov, roll: r1 },
  }, o);
}

/** Every builder by name (labs and data-driven choreography). */
export const SHOTS = { heroPushIn, crashZoom, overShoulder, whipPan, orbitSweep, impactPunchIn, topDownSlam, wideEstablishing, faceCloseUp, weaponFollow, groundSkim, dutchDrift };
