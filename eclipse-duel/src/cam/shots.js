// Shot vocabulary: parameterised builders that return shot data for cam.play().
//
// Every builder works in the anchor's fighter-local frame (f forward toward the opponent, u up from the floor, s toward
// the camera side), so a shot list authored once mirrors automatically for the left-facing fighter. `subject` picks
// the frame the shot is built around: 'anchor' | 'target' | 'mid' | any point source (Object3D, () => Vector3 ...).
// Orbit-style angles are degrees from straight-on (+s) toward +f: positive looks at the anchor's front, negative at
// the target's front (the target faces -f).
//
// Every builder also passes through the common shot fields: cut, hold, clock, ease, lookEase, fovEase, shake, kick,
// slowmo, letterbox, handheld, follow, followY, followLag, dof, tone, blur, breathe, grade (see README), and takes
// `scale`: the subject's size relative to the 1.9 m reference (every authored distance and height is multiplied by it,
// e.g. 4.5 for a colossal boss).
//
// Lens defaults: every builder sets where its focus sits (`dof.focus`: the anchored fighter / the victim / both) and
// an aperture for its shot type (portraits wide open, action shots stopped down, top-down none), plus a small exposure
// hint for dark angles (`tone`). Action shots stay stopped down on purpose: effects do not write depth, so an energy
// arc in front of a far background takes that background's blur and would lose its brushed edge at a wide aperture. A caller's `dof` / `tone` object is merged over the default; `dof: false` turns the
// depth of field of that shot off.
//
// The wuxia builders that frame world things or depend on the fighters' separation (duelStandoff, lowSweep) return a
// late-bound shot: a function the sequencer calls when the shot starts (see sequencer.js). Pass options to the builder;
// do not spread its result.

import { DEG, clamp } from '../core/math.js';

const PASS = ['cut', 'hold', 'clock', 'ease', 'lookEase', 'fovEase', 'shake', 'kick', 'slowmo', 'letterbox', 'handheld', 'follow', 'followY', 'followLag', 'blur', 'breathe', 'grade', 'gradeDur'];

const two = (v) => (Array.isArray(v) ? v : [v, v]);
/** [f, u, s] at `deg` from straight-on, `dist` metres out, `height` above the frame origin. */
const polar = (deg, dist, height) => [Math.sin(deg * DEG) * dist, height, Math.cos(deg * DEG) * dist];

/** Fields a builder may author itself (merged through own()), so finish() does not overwrite them. */
const OWN = { shake: 1, kick: 1 };

/** A caller's lens hint over the builder's default: an object merges, true keeps the default, anything else replaces. */
function hint(def, v) {
  if (v === undefined || v === true) return def;
  if (v && typeof v === 'object' && !Array.isArray(v) && !v.isObject3D && !v.isVector3 && def && typeof def === 'object') return { ...def, ...v };
  return v;
}

/** Copy the common shot fields the caller set; apply `o.scale` (subject size relative to 1.9 m) to every distance. */
function finish(shot, o) {
  for (const k of PASS) if (o[k] !== undefined && !(k in OWN && shot[k] !== undefined)) shot[k] = o[k];
  shot.dof = hint(shot.dof, o.dof);
  shot.tone = hint(shot.tone, o.tone);
  const k = o.scale;
  if (k && k !== 1) {
    const mul = (a) => a.map((v) => v * k);
    for (const key of [shot.from, shot.to]) {
      if (!key) continue;
      if (key.pos) key.pos = mul(key.pos);
      if (key.look) key.look = mul(key.look);
    }
    if (shot.via) shot.via = mul(shot.via);
    if (shot.orbit) {
      const ob = shot.orbit;
      ob.pivot = mul(ob.pivot);
      ob.radius = Array.isArray(ob.radius) ? mul(ob.radius) : ob.radius * k;
      ob.height = Array.isArray(ob.height) ? mul(ob.height) : ob.height * k;
    }
    if (shot.dof && typeof shot.dof === 'object' && typeof shot.dof.range === 'number') shot.dof = { ...shot.dof, range: shot.dof.range * k };
  }
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
    name: 'heroPushIn', dur, space: subject, ease: 'inOutSine', handheld: 0.25,
    dof: { focus: subject, aperture: 0.9, range: 0.55 }, tone: { exposure: 0.04, vignette: 0.05 },
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
    name: 'crashZoom', dur, space: subject, ease: 'outExpo', fovEase: 'outQuart',
    dof: { focus: subject, gain: 0.35, pull: 0.06 },
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
    name: 'overShoulder', dur, space: from, lookSpace: at, ease: 'inOutSine', handheld: 0.35,
    dof: { focus: at, aperture: 0.85, range: 0.6, near: 1.2, protect: false }, tone: { exposure: 0.04, vignette: 0.05 },
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
    name: 'whipPan', dur, space: from, ease: 'inOutSine', lookEase: 'inOutExpo',
    dof: { focus: 'look', gain: 0.35, pull: 0.08 }, blur: 1.25,
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
    name: 'orbitSweep', dur, space: subject, ease: 'inOutSine', handheld: 0.2,
    dof: { focus: subject, gain: 0.45 },
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
    name: 'impactPunchIn', dur, space: subject, ease: 'outExpo', fovEase: 'outCubic',
    dof: { focus: subject, gain: 0.35, pull: 0.06 },
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
    name: 'topDownSlam', dur, space: subject, ease: 'outCubic',
    dof: false, tone: { exposure: 0.02 },      // everything sits at one depth from above: no blur to buy
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
    name: 'wideEstablishing', dur, space: subject, ease: 'inOutSine', handheld: 0.15,
    dof: { focus: subject, gain: 0.9 }, tone: { vignette: 0.04 },
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
    name: 'faceCloseUp', dur, space: subject, ease: 'inOutSine', handheld: 0.3,
    dof: { focus: 'look', aperture: 1.15, range: 0.3, pull: 0.1 }, tone: { exposure: 0.06, vignette: 0.08 },
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
    name: 'weaponFollow', dur, space: subject, ease: 'linear', follow: true, followLag: 0.08, followY: true,
    dof: { focus: subject, aperture: 0.35, range: 0.8 },
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
    name: 'groundSkim', dur, space: fromSpace, ease: 'inOutQuad',
    dof: { focus: 'auto', gain: 0.4 }, tone: { exposure: 0.04 },
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
    name: 'dutchDrift', dur, space: subject, ease: 'inOutSine', handheld: 0.3,
    dof: { focus: subject, aperture: 0.6 }, tone: { vignette: 0.05 },
    from: { pos: [p0[0] - drift * 0.5, p0[1], p0[2]], look: [-drift * 0.15, look, 0], fov, roll: r0 },
    to: { pos: [p1[0] + drift * 0.5, p1[1], p1[2]], look: [drift * 0.15, look, 0], fov, roll: r1 },
  }, o);
}


// ---- wuxia flourishes ----------------------------------------------------------------------------------------------

const other = (s) => (s === 'target' ? 'anchor' : s === 'anchor' ? 'target' : null);

/**
 * Low sweep: a long lens skimming the floor on an arc around the subject. The arc starts behind a foreground element
 * (by default the other master: legs, coat tails and blade wipe across the frame, far out of focus) and clears it to
 * reveal the subject. Late-bound: the radius is taken from the fighters' separation when the shot starts.
 * @param {object} o subject='target' (who is revealed), behind=the other fighter ('anchor' | 'target' | false: plain low
 *   orbit), dur=1.3, from=84, to=50 (deg off straight-on, on the foreground side; 90 = on the fight line), back=1.9 (m
 *   behind the foreground element), radius (m, overrides sep + back), height=[0.34,0.52], look=[1.2,1.3],
 *   lead=0.22 (the aim starts this fraction of the way toward the foreground element), fov=[30,27], roll=[-4,0],
 *   side (+1 / -1: which way the arc opens for 'mid' / point subjects)
 */
export function lowSweep(o = {}) {
  const { subject = 'target', dur = 1.3, from = 84, to = 50, back = 1.9, height = [0.34, 0.52], look = [1.2, 1.3], lead = 0.22, fov = [30, 27], roll = [-4, 0] } = o;
  const behind = o.behind === undefined ? other(subject) : o.behind;
  const sign = o.side ?? (subject === 'anchor' ? 1 : -1);
  const [h0, h1] = two(height), [l0, l1] = two(look), [f0, f1] = two(fov), [r0, r1] = two(roll);
  return (c) => {
    const k = o.scale || 1;
    const R = (o.radius ?? ((behind ? c.sep / k : 3.2) + back));
    // keep the start of the arc on the camera side of the fight line (z >= 0.75 m)
    const a0 = Math.min(from, Math.acos(clamp(0.75 / Math.max(1, R * k), 0, 1)) / DEG);
    return finish({
      name: 'lowSweep', dur, space: subject, ease: 'inOutSine', lookEase: 'outSine', handheld: 0.3,
      dof: { focus: subject, aperture: 1, range: 0.7, near: 1.3, protect: false }, tone: { exposure: 0.12, vignette: 0.06 },
      orbit: { pivot: [0, l1, 0], from: sign * a0, to: sign * to, radius: [R, R * 0.92], height: [h0, h1] },
      from: { look: [sign * (behind ? c.sep / k : 0) * lead, l0, 0], fov: f0, roll: r0 * -sign },
      to: { look: [0, l1, 0], fov: f1, roll: r1 * -sign },
    }, o);
  };
}

/**
 * Duel standoff: the held wide frame of a wuxia duel. Low, far and on a long lens, both masters small on either side
 * and the eclipse hanging between them; almost still (a slow creep and the operator's breathing). Late-bound: it reads
 * the eclipse direction (cam.sun / env.sunDir), the separation and the viewport aspect when the shot starts, and widens
 * the lens on narrow (portrait) viewports until both masters fit.
 * @param {object} o dur=1.6, dist=[13,12.4] (m from the fight line), height=0.45 (m), fov=24 (the lens widens when
 *   the masters or the eclipse would not fit), sunY=0.58 (screen height of the eclipse centre, 0 bottom .. 1 top: at
 *   the masters' head height in the arena), feetY=0.2 (lowest the masters' feet may sit), margin=1.5 (m of air outside
 *   each master), creep=0.25 (m of sideways drift), grade='ink' (post grade for the shot; false = none)
 */
export function duelStandoff(o = {}) {
  const { dur = 1.6, dist = [13, 12.4], height = 0.45, fov = 24, sunY = 0.58, feetY = 0.2, margin = 1.5, creep = 0.25 } = o;
  const [d0, d1] = two(dist);
  return (c) => {
    const k = o.scale || 1;
    const hx = c.sun.x, hz = c.sun.z, hl = Math.hypot(hx, hz);
    // camera on the line from the eclipse through the midpoint (straight-on when the eclipse is not ahead of us)
    const ok = hz < -0.3 && hl > 1e-3;
    const sx = ok ? hx / hl : 0, sz = ok ? hz / hl : -1;
    const elev = ok ? Math.atan2(c.sun.y, hl) : 6 * DEG;
    // both masters inside the frame width at this aspect
    const need = (c.sep * 0.5 + margin * k) / (Math.min(d0, d1) * k * Math.max(0.3, c.aspect));
    // the eclipse at sunY with the feet no lower than feetY: the angle between them sets the widest lens we may need
    const span = elev + Math.atan(height / Math.min(d0, d1)), a = 2 * (sunY - 0.5), b = 2 * (0.5 - feetY);
    let lo = 0, hi = 1.2;
    for (let i = 0; i < 24; i++) { const m = 0.5 * (lo + hi); if (Math.atan(a * m) + Math.atan(b * m) < span) lo = m; else hi = m; }
    const tanV = Math.min(Math.tan(35 * DEG), Math.max(Math.tan(fov * DEG * 0.5), need, hi));
    const fovV = (2 * Math.atan(tanV)) / DEG;
    const pitch = elev - Math.atan(a * tanV);
    const key = (d, drift) => ({ pos: [(-sx * d + drift) * c.facing, height, -sz * d], look: [drift * 0.4 * c.facing, height + d * Math.tan(pitch), 0], fov: fovV });
    return finish({
      name: 'duelStandoff', dur, space: 'mid', ease: 'inOutSine', handheld: 0.25,
      dof: { focus: 'both', aperture: 0.3 }, tone: { vignette: 0.08, auto: false }, grade: o.grade === undefined ? 'ink' : o.grade,
      from: key(d0, -creep * 0.5), to: key(d1, creep * 0.5),
    }, { ...o, grade: undefined });
  };
}

/**
 * Blade rush: a fast push-in on a drawn blade. From a medium three-quarter view the camera lunges (expo) to arm's length
 * of the steel on a tightening lens, the focus racks onto the edge, a small jolt lands with it; then it creeps.
 * @param {object} o subject='anchor', blade (point source: a weapon socket to aim at; default the point `at`),
 *   at=[0.42,1.08,0.12] (aim in the subject's frame when no socket is given), dur=0.6, angle=36, dist=[3.4,0.95],
 *   height=[1.3,1.14], fov=[40,25], roll=[-7,-3], shake=0.18
 */
export function bladeRush(o = {}) {
  const { subject = 'anchor', blade = null, at = [0.42, 1.08, 0.12], dur = 0.6, angle = 36, dist = [3.4, 0.95], height = [1.3, 1.14], fov = [40, 25], roll = [-7, -3] } = o;
  const [d0, d1] = two(dist), [h0, h1] = two(height), [f0, f1] = two(fov), [r0, r1] = two(roll);
  const p0 = polar(angle, d0, h0), p1 = polar(angle - 6, d1, h1);
  const aim = blade ? [0, 0, 0] : at;
  return finish({
    name: 'bladeRush', dur, space: subject, lookSpace: blade || subject, ease: 'outExpo', fovEase: 'outQuart', handheld: 0.3,
    follow: blade ? 'look' : undefined, followLag: 0.06,
    dof: { focus: 'look', aperture: 1.1, range: 0.3, pull: 0.07, protect: false }, tone: { exposure: 0.05, vignette: 0.08 },
    shake: own(o.shake, { amount: 0.18, at: dur * 0.24, freq: 22, decay: 1.6 }),
    kick: own(o.kick, { fov: -2, roll: 1.5, at: dur * 0.22, duration: 0.3 }),
    from: { pos: [p0[0] + at[0] * 0.5, p0[1], p0[2]], look: aim, fov: f0, roll: r0 },
    to: { pos: [p1[0] + at[0], p1[1], p1[2] + at[2]], look: aim, fov: f1, roll: r1 },
  }, o);
}

/**
 * Crane rise: the light-foot (경공) leap. The camera starts at the floor looking up at the take-off and cranes up and
 * back faster than the fighter rises, the aim riding with the leap (follow 'look' + followY), to end level with the
 * apex and the terrace falling away below.
 * @param {object} o subject='anchor', dur=1.0, angle=[28,10], dist=[3.4,5.6], height=[0.32,3.4], look=[1.25,1.4],
 *   fov=[32,40], roll=[4,-2]
 */
export function craneRise(o = {}) {
  const { subject = 'anchor', dur = 1.0, angle = [28, 10], dist = [3.4, 5.6], height = [0.32, 3.4], look = [1.25, 1.4], fov = [32, 40], roll = [4, -2] } = o;
  const [a0, a1] = two(angle), [d0, d1] = two(dist), [h0, h1] = two(height), [l0, l1] = two(look), [f0, f1] = two(fov), [r0, r1] = two(roll);
  const p0 = polar(a0, d0, h0), p1 = polar(a1, d1, h1);
  return finish({
    name: 'craneRise', dur, space: subject, ease: 'inOutSine', lookEase: 'linear', handheld: 0.25,
    follow: 'look', followY: true, followLag: 0.045,
    dof: { focus: subject, gain: 0.5 }, tone: { exposure: 0.03 },
    from: { pos: p0, look: [0, l0, 0], fov: f0, roll: r0 },
    via: [p0[0] * 0.7 + p1[0] * 0.3, h1 * 0.8, p0[2] * 0.75 + p1[2] * 0.25],
    to: { pos: p1, look: [0, l1, 0], fov: f1, roll: r1 },
  }, o);
}

/**
 * Round-intro sequence in the wuxia grammar (returns an array of shots for cam.play): a low sweep from behind one
 * master that reveals the other, then the held duel frame with the eclipse between them; the hand-back to the fight
 * framing is then a slow push-in. Later rounds are shorter: the duel frame only.
 * @param {object} o dur=2.2 (total s, e.g. the rules' intro time), round=1, grade='ink' (false = none),
 *   sweep / standoff: option overrides for the two shots
 */
export function duelIntro(o = {}) {
  const { dur = 2.2, round = 1, grade = 'ink' } = o;
  if (round > 1) return [duelStandoff({ dur: dur * 0.85, dist: [12.2, 11.4], grade, ...o.standoff })];
  return [
    lowSweep({ dur: dur * 0.46, grade, ...o.sweep }),
    duelStandoff({ dur: dur * 0.54, cut: true, grade, ...o.standoff }),
  ];
}

/** Every builder by name (labs and data-driven choreography). */
export const SHOTS = { heroPushIn, crashZoom, overShoulder, whipPan, orbitSweep, impactPunchIn, topDownSlam, wideEstablishing, faceCloseUp, weaponFollow, groundSkim, dutchDrift, lowSweep, duelStandoff, bladeRush, craneRise };
