// Combat presets (element-neutral, tintable with opts.element): hits, guards, footwork dust, swing whooshes, charge,
// KO and the ultimate activation flash. Hit flashes, their lights and star glints run on real time by default so they
// bloom while hit-stop freezes the world; sparks, smoke and debris wait for game time and burst out when it resumes.

import { LIB } from '../library.js';
import { heatRamp } from '../util.js';
import {
  def, key, mul, EL, KIT, STEEL, SLASH_LOOK, MESH_PAL, elementOf, meshColors, cutThrough, arcPoint, arcTangent, floor, vec, lightAt,
  DUST, DUST_SMALL, PEBBLES, DUST_MOTES, SMOKE_COLUMN, LEAVES, STOMP_INK, groundMark,
} from './common.js';

/** Cool pale air for whooshes. */
const AIR = { core: [1.7, 1.8, 2.0], mid: [0.45, 0.5, 0.58], tail: [0.08, 0.09, 0.1] };
/** Guard steel-blue (barrier glints). */
const GUARD = { core: [6, 7.5, 10], mid: [1.2, 1.8, 3.2], tail: [0.12, 0.18, 0.35] };

// ---- particle definitions (module scope) -------------------------------------------------------------------------

/** pierce: a tight fast cone of long sparks blown out along the thrust axis */
const PIERCE_SPARKS = {};
for (const el in KIT) PIERCE_SPARKS[el] = def({ ...KIT[el].sparks, count: 40, spread: 9, spreadPow: 1.6, speed: [9, 26, 1.3], stretch: 0.06, maxStretch: 1.8, drag: 3, gravity: -6, life: [0.15, 0.5, 1.4] });
/** guard: glancing fan of steel sparks */
const GUARD_SPARKS = def({ ...LIB.sparks, count: 34, spread: [70, 22], speed: [3, 12, 1.4], life: [0.15, 0.6, 1.5], color: heatRamp(STEEL.core, STEEL.mid, STEEL.tail) });
/** guard break: barrier fragments (crystal shards and hex flakes) that spin and fall */
const GUARD_SHARDS = def({ tex: 'shard', blend: 'add', count: 26, life: [0.45, 1.1], shape: { type: 'sphere', radius: 0.25 }, emit: 'radial', spread: 60, lift: 0.5,
  speed: [2.5, 8, 1.3], size: [0.07, 0.22, 2], spin: [4, 14], gravity: -11, drag: 0.8, collide: 'ground', bounce: 0.35, erode: 'erodeLate', erodeChannel: 'cracks',
  color: [key(0, [8, 9, 11]), key(0.12, GUARD.core, 1, 0.5), key(0.6, GUARD.mid, 0.9), key(1, GUARD.tail, 0)] });
const GUARD_HEX = def({ tex: 'hex', blend: 'add', count: 14, life: [0.35, 0.8], shape: { type: 'sphere', radius: 0.35 }, emit: 'radial', spread: 70,
  speed: [1.5, 5], size: [0.08, 0.2, 1.6], spin: [2, 6], gravity: -4, drag: 2, rotation: [0, 6.28], flicker: { amount: 0.4, rate: 20 },
  color: [key(0, [3, 4, 6], 0), key(0.06, GUARD.core, 1, 0.4), key(1, GUARD.tail, 0)] });
/** directional dash dust: a low cloud blown backward */
const DUST_DASH = def({ ...LIB.dustRing, count: 9, shape: { type: 'disc', radius: 0.2 }, emit: 'axis', spread: [35, 55], lift: 0.25, speed: [1.5, 5.5],
  size: [0.35, 0.85, 1.3], life: [0.5, 1.1], drag: 3.5 });
/** skid mark: pale dust smeared flat along the floor */
const SKID_MARK = def({ tex: 'smoke', blend: 'alpha', count: 1, life: [1.0, 1.7], speed: 0, align: 'flat', dir: [0, 1, 0], size: [0.22, 0.4], aspect: 3.2, rotation: [-0.08, 0.08],
  groundFade: 0, shade: 0.4, erode: [[0, 0.15], [0.6, 0.35], [1, 1]], erodeSoft: 0.45, color: [[0, 0.3, 0.27, 0.23, 0], [0.1, 0.26, 0.23, 0.2, 0.28], [1, 0.2, 0.18, 0.16, 0]] });
/** skid dust: puffs that roll up from a sliding foot */
const DUST_SKID = def({ ...LIB.dustRing, count: 0, rate: 0, perMeter: 9, shape: { type: 'disc', radius: 0.1 }, emit: 'axis', spread: [40, 40], lift: 0.5,
  speed: [0.5, 2], size: [0.3, 0.7, 1.3], life: [0.5, 1.0], drag: 2.5, inherit: 0.25 });
/** skid grit: tiny stones and sparks of grit kicked along a slide */
const SKID_GRIT = def({ ...LIB.pebbles, count: 0, rate: 0, perMeter: 7, size: [0.02, 0.06, 2], speed: [1, 3], spread: 50, inherit: 0.4, life: [0.4, 0.9] });
/** whoosh: faint wind streaks along the swing */
const WIND = def({ tex: 'streak', blend: 'add', count: 10, life: [0.12, 0.3], shape: { type: 'sphere', radius: 0.15 }, emit: 'axis', spread: 8,
  speed: [4, 9], size: [0.03, 0.06], stretch: 0.05, maxStretch: 0.9, drag: 5, rotation: 0, groundFade: 0,
  color: [key(0, AIR.core, 0, 0.6), key(0.15, AIR.core, 0.6, 0.6), key(1, AIR.mid, 0)] });
/** heavy whoosh: dust swirled up by the blade's wake */
const WAKE_DUST = def({ ...DUST_MOTES, count: 14, emit: 'axis', spread: 30, speed: [1, 3], drag: 2.5, gravity: -0.4 });

/** charge: converging streaks / motes / gathering sparks per element */
const CHARGE = {};
for (const el of ['steel', 'ember', 'frost', 'volt', 'eclipse']) {
  const P = EL[el];
  CHARGE[el] = {
    streaks: def({ ...LIB.chargeStreaks, color: [key(0, P.tail, 0, 4), key(0.25, P.mid, 1), key(1, P.core, 1, 1.2)] }),
    motes: def({ ...LIB.chargeMotes, color: [key(0, P.mid, 0, 0.5), key(0.3, P.mid, 1, 1.4), key(1, P.core, 0.6)] }),
    sparkle: def({ ...LIB.chargeStreaks, rate: 40, size: [0.015, 0.035], shape: { type: 'sphere', radius: 0.9, inner: 0.5 }, color: [key(0, P.core, 0, 0.3), key(0.3, P.core, 1), key(1, [10, 9, 8], 1)] }),
    ring: def({ tex: 'ring', blend: 'add', rate: 3.2, life: [0.5, 0.5], speed: 0, size: [1.6, 1.6], sizeOverLife: [[0, 1], [1, 0.05, 'inQuad']], groundFade: 0, rotation: 0,
      color: [key(0, P.mid, 0, 0.4), key(0.3, P.mid, 0.5, 0.6), key(1, P.core, 0.9, 0.5)] }),
    burst: def({ ...LIB.sparks, count: 90, spread: 180, emit: 'radial', speed: [5, 18, 1.4], color: el === 'volt' ? [[0, 12, 10, 6, 1], [0.15, 8, 5, 1, 1], [0.6, 2.5, 1.2, 0.15, 1], [1, 0.4, 0.15, 0, 0]] : heatRamp(P.core, P.mid, P.tail) }),
    flash: def({ ...LIB.flashCore, color: [[0, 11, 10, 10, 1], key(0.3, P.core, 0.75, 0.6), key(1, P.tail, 0)] }),
    glitter: def({ ...LIB.glitter, count: 30, color: [key(0, P.core, 0, 0.8), key(0.1, P.core, 1, 0.8), key(1, P.mid, 0, 0.6)] }),
  };
}

/** KO: long embers of light rising after the blast */
const KO_RISE = def({ ...LIB.embers, count: 40, life: [1.4, 3.2, 0.8], speed: [1, 5, 1.4], gravity: 1.1, size: [0.04, 0.12, 2.2], color: [[0, 12, 9, 5, 1], [0.3, 6, 3, 0.8, 1], [0.8, 1.5, 0.5, 0.05, 0.7], [1, 0.3, 0.06, 0, 0]] });
const KO_GLOW = def({ tex: 'glow', blend: 'add', align: 'flat', count: 1, life: [1.2, 1.2], speed: 0, size: 3.6, groundFade: 0, rotation: 0,
  color: [[0, 3, 2.2, 1.4, 1], [0.15, 1.4, 0.8, 0.3, 0.7], [1, 0.1, 0.03, 0, 0]] });
/**
 * Register the combat presets.
 * @param {object} vfx
 * @param {object} P  preset helpers from presets/index.js ({ define, alias, rng })
 */
export function defineCombat(vfx, P) {
  const { define, rng } = P;
  const I = (o) => (o.intensity != null ? o.intensity : 1);
  const n = (c, i) => Math.max(1, Math.round(c * i));
  const rtFlash = (v, o) => o.flashRealtime !== false || v.realtime;
  /** a point in front of the contact (toward the camera side) so marks are not buried in the body */
  const front = (p, s) => vec([p.x, p.y, p.z + 0.24 * s]);

  /**
   * Shock band around the strike axis: a short-lived filled disc (wide band, soft inside) rather than a thin hoop, so it
   * reads as displaced air carrying the direction of the blow instead of a UI circle.
   */
  const shock = (v, p, d, E, r, life, inten, rt) => v.ring({ normal: d, look: 'shock', pos: p, ...meshColors(E), radius: [0.04 * r, r], width: [0.12 * r, 0.55 * r],
    life, ease: 5, fill: 2.6, over: 0.25, noise: 0.55, edgeWidth: 0.12, erodeStart: 0.05, intensity: inten, realtime: rt });

  /** light strike: 2-frame flash, a quick cut mark through the contact, impact lines, a short directional spark spray, a wisp of dust */
  define('hit.light', (v, at, o) => {
    const el = elementOf(o), K = KIT[el], E = EL[el], i = I(o), s = at.scale, p = at.pos, d = at.dir, f = at.facing;
    const rt = rtFlash(v, o);
    v.burst(K.flash, { pos: p, scale: 0.28 * s, intensity: i, realtime: rt });
    v.flare({ kind: 'glow', pos: p, size: 0.36 * s, life: 0.05, color: E.core, intensity: 0.7 * i, realtime: rt });
    v.flare({ kind: 'streak', pos: p, size: 0.08 * s, aspect: 12, life: 0.07, decay: 2.5, dir: d, color: E.core, intensity: 0.6 * i, realtime: rt });
    v.light({ pos: lightAt(p, 1.3), color: E.core, intensity: 24 * i, range: 4, duration: 0.12, decay: 'outExpo', realtime: rt });
    v.slash({ ...cutThrough(front(p, s), d, f, 0.42 * s, 36, (rng() - 0.5) * 30), look: SLASH_LOOK[el], ...meshColors(E), width: 0.13 * s, sweep: 0.025, life: 0.16, intensity: 1.15 * i, realtime: rt });
    v.burst(K.lines, { pos: p, count: n(4, i), scale: 0.6 * s, realtime: rt });
    v.burst(K.strokes, { pos: p, count: n(3, i), scale: 0.6 * s, realtime: rt });
    v.burst(K.ink, { pos: p, count: 3, scale: 0.6 * s, realtime: rt });
    v.burst(K.splash, { pos: p, dir: d, count: n(6, i), scale: 0.7 * s });
    v.burst(K.sparks, { pos: p, dir: d, count: n(26, i), scale: 0.6 * s });
    v.burst(K.fine, { pos: p, dir: d, count: n(10, i), scale: 0.7 * s });
    v.burst(K.motes, { pos: p, dir: d, count: n(4, i), scale: 0.55 * s });
    v.burst(K.dust, { pos: p, dir: d, count: 1, scale: 0.6 * s });
  });

  /** heavy strike: flash, star, impact lines, a thick cut crescent, a shock disc around the strike axis, sparks with floor bounces, element accent, lingering puff */
  define('hit.heavy', (v, at, o) => {
    const el = elementOf(o), K = KIT[el], E = EL[el], i = I(o), s = at.scale, p = at.pos, d = at.dir, f = at.facing;
    const rt = rtFlash(v, o);
    v.burst(K.flash, { pos: p, scale: 0.48 * s, intensity: i, realtime: rt });
    v.flare({ kind: 'star', pos: p, size: 1.3 * s, life: 0.1, decay: 3, color: E.core, intensity: 0.8 * i, rotation: rng() * 0.7, realtime: rt });
    v.flare({ kind: 'streak', pos: p, size: 0.15 * s, aspect: 14, life: 0.11, decay: 2.5, dir: d, color: E.core, intensity: 0.75 * i, realtime: rt });
    v.light({ pos: lightAt(p, 1.6), color: E.core, intensity: 42 * i, range: 5, duration: 0.24, decay: 'outExpo', realtime: rt });
    v.burst(K.puff, { pos: p, scale: 0.36 * s, realtime: rt });
    const pf = front(p, s);
    v.slash({ ...cutThrough(pf, d, f, 0.62 * s, 44, (rng() - 0.5) * 24), look: SLASH_LOOK[el], ...meshColors(E), width: 0.24 * s, sweep: 0.035, life: 0.26, intensity: 1.25 * i, realtime: rt });
    shock(v, pf, d, E, 0.62 * s, 0.11, 0.3 * i, rt);
    v.burst(K.lines, { pos: p, count: n(7, i), scale: 0.85 * s, realtime: rt });
    v.burst(K.strokes, { pos: p, count: n(5, i), scale: 0.85 * s, realtime: rt });
    v.burst(K.blot, { pos: p, scale: 0.75 * s, realtime: rt });
    v.burst(K.ink, { pos: p, count: 6, scale: 0.85 * s, realtime: rt });
    v.burst(K.scrap, { pos: p, dir: d, count: n(2, i), scale: 0.9 * s });
    v.burst(K.splash, { pos: p, dir: d, count: n(11, i), scale: 0.85 * s });
    v.burst(K.sparks, { pos: p, dir: d, count: n(58, i), scale: 0.8 * s });
    v.burst(K.fine, { pos: p, dir: d, count: n(22, i), scale: 0.85 * s });
    v.burst(K.motes, { pos: p, dir: d, count: n(10, i), scale: 0.8 * s });
    v.burst(K.accent, { pos: p, dir: d, count: n(el === 'steel' ? 5 : 4, i), scale: 0.8 * s });
    v.burst(K.dust, { pos: p, dir: d, count: 3, scale: 0.8 * s });
    v.schedule(0.03, (w) => {
      w.burst(K.smoke, { pos: p, dir: d, count: 3, scale: 0.6 * s });
      w.distort({ kind: 'shock', pos: pf, radius: [0.12 * s, 0.95 * s], life: 0.24, strength: 0.026 });
      // the blow reaches the floor: a mark when it lands low, else its pressure kicks a little dust off the stone
      if (p.y < 0.85 * s) groundMark(w, el, p, 0.8 * s, 0.7 * i);
      else if (p.y < 2.2 * s) w.burst(DUST_SMALL, { pos: floor(p, 0.03), dir: [0, 1, 0], count: 3, scale: 0.9 * s });
    });
  });

  /** critical / counter hit: X-cut of two crescents, flash, star, impact lines, axial shock disc, heavy spark shower, element debris, smoke, floor dust, shock */
  define('hit.crit', (v, at, o) => {
    const el = elementOf(o), K = KIT[el], E = EL[el], i = I(o), s = at.scale, p = at.pos, d = at.dir, f = at.facing;
    const rt = rtFlash(v, o);
    const pf = front(p, s);
    v.burst(K.flash, { pos: p, scale: 0.65 * s, intensity: i, realtime: rt });
    v.flare({ kind: 'flash', pos: p, size: 1.8 * s, life: 0.045, decay: 3, color: E.core, intensity: 0.1 * i, realtime: rt });
    v.flare({ kind: 'star', pos: p, size: 1.9 * s, life: 0.15, decay: 3, color: E.core, intensity: 0.9 * i, rotation: 0.2 + rng() * 0.4, realtime: rt });
    v.flare({ kind: 'streak', pos: p, size: 0.2 * s, aspect: 16, life: 0.14, decay: 2.5, dir: d, color: E.core, intensity: 0.8 * i, realtime: rt });
    v.light({ pos: lightAt(p, 1.8), color: E.core, intensity: 68 * i, range: 6.5, duration: 0.34, decay: 'outExpo', realtime: rt });
    v.burst(K.puff, { pos: p, scale: 0.5 * s, realtime: rt });
    v.slash({ ...cutThrough(pf, d, f, 0.8 * s, 46, 32), look: SLASH_LOOK[el], ...meshColors(E), width: 0.28 * s, sweep: 0.03, life: 0.3, intensity: 1.35 * i, realtime: rt });
    shock(v, pf, d, E, 0.95 * s, 0.13, 0.35 * i, rt);
    v.burst(K.lines, { pos: p, count: n(11, i), scale: s, realtime: rt });
    v.burst(K.strokes, { pos: p, count: n(8, i), scale: s, realtime: rt });
    v.burst(K.blot, { pos: p, scale: s, realtime: rt });
    v.burst(K.ink, { pos: p, count: 10, scale: s, realtime: rt });
    v.burst(K.scrap, { pos: p, dir: d, count: n(4, i), scale: s });
    v.burst(K.splash, { pos: p, dir: d, count: n(16, i), scale: s });
    v.burst(K.sparks, { pos: p, dir: d, count: n(95, i), scale: s });
    v.burst(K.fine, { pos: p, dir: d, count: n(36, i), scale: s });
    v.burst(K.motes, { pos: p, dir: d, count: n(18, i), scale: s });
    v.burst(K.dust, { pos: p, dir: d, count: 5, scale: s });
    v.schedule(rt ? 0.04 : 0.045, (w) => w.slash({ ...cutThrough(pf, d, f, 0.8 * s, 46, -32), look: SLASH_LOOK[el], ...meshColors(E), width: 0.26 * s, sweep: 0.03, life: 0.28, intensity: 1.25 * i, realtime: rt }), { realtime: rt });
    v.schedule(0.035, (w) => {
      w.distort({ kind: 'shock', pos: pf, radius: [0.15 * s, 1.15 * s], life: 0.28, strength: 0.026 });
      w.burst(K.smoke, { pos: p, dir: d, count: 5, scale: 0.8 * s });
      if (p.y < 0.9 * s) groundMark(w, el, p, s, i);
      else if (p.y < 2.2 * s) {
        w.burst(DUST_SMALL, { pos: floor(p, 0.03), dir: [0, 1, 0], count: n(5, i), scale: 1.1 * s });
        w.burst(LEAVES, { pos: floor(p, 0.05), dir: [0, 1, 0], count: 3, scale: s });
      }
    });
    if (el === 'ember') v.burst(LIB.fireLicks, { pos: p, dir: d, count: 8, scale: 0.6 * s });
    else if (el === 'frost') v.burst(GUARD_SHARDS, { pos: p, dir: d, count: 16, scale: 0.8 * s, color: [0.6, 0.9, 1.2] });
    else if (el === 'volt') for (let k = 0; k < 2; k++) v.bolt({ from: p, to: p.clone().addScaledVector(d, 1.4 * s).add(vec([(rng() - 0.5) * 0.8, (rng() - 0.3) * 1.2, rng() * 0.4])), width: 0.12 * s, branches: 2, strikes: 2, detail: 5, life: 0.22, leader: 0, impact: false });
    else v.burst(K.accent, { pos: p, dir: d, count: n(9, i), scale: s });
  });

  /** thrust / pierce: a line of light through the body, an exit cone of long sparks, shock discs around the thrust axis */
  define('hit.pierce', (v, at, o) => {
    const el = elementOf(o), K = KIT[el], E = EL[el], i = I(o), s = at.scale, p = at.pos, d = at.dir;
    const rt = rtFlash(v, o);
    const exit = p.clone().addScaledVector(d, 0.35 * s);
    v.burst(K.flash, { pos: p, scale: 0.3 * s, intensity: i, realtime: rt });
    v.flare({ kind: 'streak', pos: exit, size: 0.16 * s, aspect: 22, life: 0.13, decay: 2.5, dir: d, color: E.core, intensity: 0.8 * i, realtime: rt });
    v.flare({ kind: 'glow', pos: exit, size: 0.4 * s, life: 0.05, color: E.core, intensity: 0.7 * i, realtime: rt });
    v.light({ pos: lightAt(exit, 1.4), color: E.core, intensity: 50 * i, range: 5, duration: 0.22, decay: 'outExpo', realtime: rt });
    v.beam({ look: el === 'volt' ? 'volt' : el === 'frost' ? 'frost' : el === 'ember' ? 'fire' : 'energy', ...meshColors(E), from: p.clone().addScaledVector(d, -0.6 * s), to: p.clone().addScaledVector(d, 2.4 * s),
      width: 0.1 * s, life: 0.16, extend: 0.035, release: 0.1, flares: false, intensity: 0.6 * i, realtime: rt });
    shock(v, exit, d, E, 0.7 * s, 0.14, 0.45 * i, rt);
    v.schedule(0.05, (w) => shock(w, exit.clone().addScaledVector(d, 0.55 * s), d, E, 0.45 * s, 0.13, 0.35 * i, false));
    v.burst(K.lines, { pos: exit, count: n(5, i), scale: 0.7 * s, realtime: rt });
    v.burst(K.strokes, { pos: exit, count: n(4, i), scale: 0.7 * s, realtime: rt });
    v.burst(K.ink, { pos: exit, count: 4, scale: 0.7 * s, realtime: rt });
    v.burst(PIERCE_SPARKS[el], { pos: exit, dir: d, count: n(42, i), scale: 0.9 * s });
    v.burst(K.fine, { pos: p, dir: vec([-d.x, 0.4, 0.3]).normalize(), count: n(10, i), scale: 0.6 * s });
    v.burst(K.motes, { pos: exit, dir: d, count: n(10, i), scale: 0.8 * s });
    v.burst(K.dust, { pos: exit, dir: d, count: 3, scale: 0.75 * s });
    v.schedule(0.03, (w) => {
      w.distort({ kind: 'shock', pos: exit, normal: d, radius: [0.1 * s, 0.9 * s], life: 0.24, strength: 0.03 });
      w.burst(K.smoke, { pos: exit.clone().addScaledVector(d, 0.3 * s), dir: d, count: 3, scale: 0.6 * s });
    });
  });

  /** blocked strike: a glancing steel spark fan, a parry ring and a star glint (opts.perfect: bigger glint, cold shimmer) */
  define('guard.block', (v, at, o) => {
    const i = I(o), s = at.scale, p = at.pos, d = at.dir, pf = !!o.perfect;
    const rt = rtFlash(v, o);
    const fan = vec([-d.x * 0.55, 0.75, 0.45]).normalize();
    v.burst(KIT.steel.flash, { pos: p, scale: (pf ? 0.5 : 0.3) * s, intensity: i, realtime: rt });
    v.flare({ kind: 'star', pos: p, size: (pf ? 1.6 : 0.75) * s, life: pf ? 0.24 : 0.12, decay: 2.5, color: pf ? GUARD.core : STEEL.core, intensity: 0.85 * i, rotation: 0.25, realtime: rt });
    const rn = vec([-d.x, 0.2, 0.7]).normalize();
    shock(v, front(p, s), rn, GUARD, (pf ? 0.75 : 0.45) * s, pf ? 0.16 : 0.1, (pf ? 0.5 : 0.35) * i, rt);
    v.light({ pos: lightAt(p, 1.3), color: pf ? GUARD.core : STEEL.core, intensity: (pf ? 52 : 28) * i, range: 4.5, duration: pf ? 0.26 : 0.14, decay: 'outExpo', realtime: rt });
    v.burst(KIT.steel.lines, { pos: p, count: n(pf ? 14 : 7, i), scale: 0.7 * s, realtime: rt });
    v.burst(GUARD_SPARKS, { pos: p, dir: fan, side: d, count: n(pf ? 60 : 32, i), scale: 0.8 * s });
    v.burst(KIT.steel.fine, { pos: p, dir: fan, count: n(14, i), scale: 0.7 * s });
    v.burst(KIT.steel.accent, { pos: p, dir: fan, count: n(pf ? 6 : 3, i), scale: 0.7 * s });
    if (pf) {
      // a perfect guard flashes the barrier: hex flakes light up across the guard plane and hang, cold glitter, a refraction pulse
      v.burst(GUARD_HEX, { pos: front(p, s), dir: rn, count: n(12, i), scale: 0.8 * s, realtime: rt });
      v.burst(CHARGE.frost.glitter, { pos: p, count: 22, scale: 0.6 * s });
      v.schedule(0.04, (w) => w.distort({ kind: 'shock', pos: front(p, s), radius: [0.15 * s, 1.1 * s], life: 0.26, strength: 0.026 }));
    }
  });

  /** guard break: the barrier shatters into spinning shards and hex flakes, flash, shock ring, steel sparks */
  define('guard.break', (v, at, o) => {
    const i = I(o), s = at.scale, p = at.pos, d = at.dir;
    const rt = rtFlash(v, o);
    v.burst(KIT.steel.flash, { pos: p, scale: 0.55 * s, intensity: i, realtime: rt });
    v.flare({ kind: 'flash', pos: p, size: 1.8 * s, life: 0.05, decay: 3, color: GUARD.core, intensity: 0.1 * i, realtime: rt });
    v.flare({ kind: 'star', pos: p, size: 1.6 * s, life: 0.2, decay: 3, color: GUARD.core, intensity: 0.85 * i, rotation: 0.4, realtime: rt });
    v.light({ pos: lightAt(p, 1.8), color: GUARD.core, intensity: 60 * i, range: 6.5, duration: 0.34, decay: 'outExpo', realtime: rt });
    shock(v, front(p, s), d, GUARD, 1.0 * s, 0.16, 0.5 * i, rt);
    // the barrier itself: a filled pane of crystalline cells facing the attacker that cracks apart in a few frames
    v.ring({ normal: vec([-d.x, 0.15, 0.9]).normalize(), look: 'frost', pos: front(p, s), ...meshColors(GUARD), radius: [0.35 * s, 0.85 * s], width: [0.6 * s, 0.85 * s],
      life: 0.13, ease: 4, fill: 1.2, erodeStart: 0, intensity: 0.45 * i, realtime: rt });
    v.burst(KIT.steel.lines, { pos: p, count: n(16, i), scale: s, realtime: rt });
    v.burst(GUARD_SHARDS, { pos: p, dir: d, count: n(30, i), scale: s });
    v.burst(GUARD_HEX, { pos: p, dir: d, count: n(16, i), scale: s });
    v.burst(KIT.steel.sparks, { pos: p, dir: d, count: n(55, i), scale: 0.9 * s });
    v.burst(KIT.steel.splash, { pos: p, dir: d, count: n(10, i), scale: 0.9 * s });
    v.schedule(0.03, (w) => {
      w.distort({ kind: 'shock', pos: front(p, s), radius: [0.2 * s, 1.6 * s], life: 0.32, strength: 0.034 });
      w.burst(KIT.steel.dust, { pos: p, dir: d, count: 4, scale: 0.9 * s });
    });
  });

  /** footstep: a small dust puff and a few motes at the foot (at.pos on the floor) */
  define('dust.step', (v, at, o) => {
    const i = I(o), s = at.scale, g = floor(at.pos, 0.03);
    v.burst(DUST_SMALL, { pos: g, dir: [0, 1, 0], count: n(4, i), scale: 0.8 * s });
    v.burst(DUST_MOTES, { pos: g, dir: [0, 1, 0], count: n(5, i), scale: 0.6 * s });
  });

  /** dash start: dust blown backward (opposite at.facing) in a low elongated cloud, grit and motes */
  define('dust.dash', (v, at, o) => {
    const i = I(o), s = at.scale, g = floor(at.pos, 0.04), f = at.facing;
    const back = vec([-f, 0.22, 0.12]).normalize();
    v.burst(DUST_DASH, { pos: g, dir: back, side: [0, 0, 1], count: n(9, i), scale: s });
    v.burst(DUST_SMALL, { pos: g, dir: [0, 1, 0], count: n(4, i), scale: s });
    v.burst(PEBBLES, { pos: g, dir: vec([-f, 1, 0.2]).normalize(), count: n(6, i), scale: 0.5 * s });
    v.burst(DUST_MOTES, { pos: g, dir: back, count: n(8, i), scale: 0.8 * s });
  });

  /** landing: radial dust ring (mesh + puffs), pebbles; opts.heavy adds a floor shock and more debris */
  define('dust.land', (v, at, o) => {
    const i = I(o), s = at.scale, g = floor(at.pos, 0.03), heavy = !!o.heavy;
    const k = heavy ? 1.5 : 1;
    v.ring({ look: 'dust', pos: g, radius: [0.2 * s, 1.4 * k * s], life: 0.9 * k, alpha: 0.8 });
    v.burst(DUST, { pos: g, dir: [0, 1, 0], count: n(10 * k, i), scale: 0.65 * k * s });
    v.burst(PEBBLES, { pos: g, dir: [0, 1, 0], count: n(5 * k, i), scale: 0.6 * s });
    v.burst(DUST_MOTES, { pos: g, dir: [0, 1, 0], count: n(8 * k, i), scale: k * s });
    v.burst(LEAVES, { pos: g, dir: [0, 1, 0], count: n(heavy ? 5 : 2, i), scale: s });
    if (heavy) {
      v.debris({ kind: 'rock', pos: [g.x, 0.08, g.z], count: n(6, i), speed: [1.5, 4], size: [0.04, 0.12, 2], spread: 60, scale: s });
      v.distort({ kind: 'shock', pos: g, normal: [0, 1, 0], radius: [0.2 * s, 2.2 * s], life: 0.35, strength: 0.03 });
      v.decal({ kind: 'crack', pos: g, radius: 0.9 * s, life: 2.2, density: 0.7 });
    }
  });

  /**
   * stomp (진각): the planted foot of a committed strike. A low dust ring rolls out, ink strokes are thrown flat along
   * the stone, pebbles and leaves jump; opts.heavy cracks the floor and bends the air above it. at.pos = the foot.
   */
  define('dust.stomp', (v, at, o) => {
    const i = I(o), s = at.scale, g = floor(at.pos, 0.03), heavy = !!o.heavy;
    const k = heavy ? 1.35 : 1;
    v.ring({ look: 'dust', pos: g, radius: [0.12 * s, 1.1 * k * s], width: [0.2 * s, 0.6 * k * s], life: 0.65 * k, alpha: 0.7, height: 0.28 * k });
    v.burst(STOMP_INK, { pos: vec([g.x, 0.04, g.z]), dir: [0, 1, 0], count: n(heavy ? 9 : 5, i), scale: 0.9 * k * s });
    v.burst(DUST_SMALL, { pos: g, dir: [0, 1, 0], count: n(5 * k, i), scale: 0.9 * k * s });
    v.burst(PEBBLES, { pos: g, dir: [0, 1, 0], count: n(4 * k, i), scale: 0.5 * s });
    v.burst(LEAVES, { pos: g, dir: [0, 1, 0], count: n(heavy ? 5 : 2, i), scale: 0.9 * s });
    v.burst(DUST_MOTES, { pos: g, dir: [0, 1, 0], count: n(6 * k, i), scale: 0.8 * k * s });
    if (heavy) {
      v.decal({ kind: 'crack', pos: g, radius: 0.7 * s, life: 2.4, density: 0.6 });
      v.distort({ kind: 'shock', pos: g, normal: [0, 1, 0], radius: [0.15 * s, 1.6 * s], life: 0.3, strength: 0.022 });
    }
  });

  /**
   * slide / skid: dust and grit kicked up behind a sliding foot. With opts.follow (or an Object3D at.target) it emits
   * while the foot moves until stop() (or opts.duration); otherwise it lays a skid along `opts.length` behind at.pos.
   */
  define('dust.slide', (v, at, o) => {
    const i = I(o), s = at.scale, f = at.facing;
    const follow = o.follow || (at.target && at.target.isObject3D ? at.target : null);
    const back = vec([-f, 0.25, 0.1]).normalize();
    if (follow) {
      const dur = o.duration != null ? o.duration : 0;
      v.emitter(DUST_SKID, { pos: at.pos, dir: back, scale: s, intensity: i, duration: dur }).follow(follow, o.offset);
      v.emitter(SKID_GRIT, { pos: at.pos, dir: vec([-f, 1, 0.2]).normalize(), scale: s, duration: dur }).follow(follow, o.offset);
      return;
    }
    const len = (o.length != null ? o.length : 1.6) * s;
    const g = floor(at.pos, 0.03);
    // marks overlap at uneven spacing (evenly spaced stamps read as footprints), puffs only every few marks
    let k = 0;
    for (let x = 0; x < len; x += (0.09 + rng() * 0.12) * s, k++) {
      const u = x / len;
      const q = vec([g.x - f * x, 0.03, g.z + (rng() - 0.5) * 0.06 + u * 0.05]);
      const t = (1 - u) * 0.25;
      v.burst(SKID_MARK, { pos: vec([q.x, 0.012, q.z]), dir: [0, 1, 0], scale: (0.75 + 0.5 * rng()) * (1 - 0.4 * u) * s, delay: t });
      if (k % 3 === 0) v.burst(DUST_DASH, { pos: q, dir: back, count: n(2 + Math.round(2 * (1 - u)), i), scale: s, delay: t });
      if (k % 2 === 0) v.burst(DUST_MOTES, { pos: q, dir: back, count: n(2, i), scale: 0.7 * s, delay: t });
      if (k % 4 === 1) v.burst(PEBBLES, { pos: q, dir: [0, 1, 0], count: 1, scale: 0.4 * s, delay: t });
    }
  });

  /**
   * air whoosh of a swing (no element): a faint pale crescent with a refraction twin and wind streaks.
   * at.pos = swing pivot (shoulder); opts: arc [deg, deg], radius, normal, roll (vfx.slash conventions).
   */
  function whoosh(heavy) {
    return (v, at, o) => {
      const i = I(o), s = at.scale, f = at.facing;
      const R = (o.radius != null ? o.radius : heavy ? 1.7 : 1.3) * s;
      const arc = o.arc || (heavy ? [140, -50] : [120, -30]);
      const plane = { normal: o.normal || [0, 0.2, 1], forward: o.forward || [1, 0, 0], roll: o.roll || 0, facing: f };
      v.slash({ look: 'razor', pos: at.pos, ...plane, arc, radius: R, width: (heavy ? 0.5 : 0.32) * s, sweep: heavy ? 0.1 : 0.07, life: heavy ? 0.32 : 0.22,
        ...meshColors(AIR), intensity: (heavy ? 0.75 : 0.6) * i, alpha: 0.75, distort: heavy ? 0.018 : 0.012 });
      const sgn = Math.sign(arc[1] - arc[0]);
      const mids = heavy ? [0.35, 0.6, 0.85] : [0.45, 0.8];
      for (const u of mids) {
        const a = arc[0] + (arc[1] - arc[0]) * u;
        const q = arcPoint(at.pos, plane, a, R * 0.95);
        v.burst(WIND, { pos: q, dir: arcTangent(plane, a, sgn), count: n(heavy ? 6 : 4, i), scale: s, delay: (heavy ? 0.1 : 0.07) * u });
      }
      if (heavy) {
        const end = arcPoint(at.pos, plane, arc[1], R);
        v.burst(WAKE_DUST, { pos: end, dir: arcTangent(plane, arc[1], sgn), count: n(12, i), scale: s, delay: 0.08 });
        if (end.y < 0.45) v.burst(DUST_DASH, { pos: floor(end, 0.04), dir: vec([f, 0.3, 0.1]).normalize(), count: n(6, i), scale: 0.8 * s, delay: 0.08 });
      }
    };
  }
  define('whoosh.light', whoosh(false));
  define('whoosh.heavy', whoosh(true));

  /**
   * charge-up (loop): streaks and motes converge on at.pos, an imploding ring pulses, a glow grows, a lens pinch bends
   * the air, light rises. Runs until stop() (or opts.duration, then optionally opts.release plays charge.release).
   * opts: element, follow (Object3D: the gather point tracks it), rune (floor circle), duration, release.
   */
  define('charge.gather', (v, at, o) => {
    const el = o.element && CHARGE[o.element] ? o.element : 'steel', C = CHARGE[el], E = EL[el], i = I(o), s = at.scale;
    const follow = o.follow || (at.target && at.target.isObject3D ? at.target : null);
    const dur = o.duration != null ? o.duration : Infinity;
    const T = Number.isFinite(dur) ? dur : 1.2;
    const life = Number.isFinite(dur) ? dur + 0.05 : 1e5;
    const hs = [
      v.emitter(C.streaks, { pos: at.pos, scale: s, intensity: i, duration: Number.isFinite(dur) ? dur : 0 }),
      v.emitter(C.motes, { pos: at.pos, scale: s, intensity: i, duration: Number.isFinite(dur) ? dur : 0 }),
      v.emitter(C.sparkle, { pos: at.pos, scale: s, duration: Number.isFinite(dur) ? dur : 0 }),
      v.emitter(C.ring, { pos: at.pos, scale: s, duration: Number.isFinite(dur) ? dur : 0 }),
      v.flare({ kind: 'glow', pos: at.pos, size: [0.15 * s, 0.85 * s], life, attack: T * 0.9, decay: 6, color: E.core, intensity: i }),
      v.flare({ kind: 'star', pos: at.pos, size: 0.9 * s, life, attack: T, decay: 6, color: E.core, intensity: 0.6 * i, rotation: 0.3 }),
      v.light({ pos: lightAt(at.pos), color: E.core, intensity: 45 * i, range: 6, duration: dur, attack: T * 0.8, flicker: 0.2 }),
      v.distort({ kind: 'lens', pos: at.pos, radius: 0.9 * s, strength: -0.045, life, attack: T * 0.85, decay: 6 }),
    ];
    if (follow) for (const h of hs) h.follow(follow, o.offset);
    if (o.rune) v.decal({ kind: 'rune', pos: floor(at.pos, 0), radius: 1.3 * s, palette: MESH_PAL[el] || 'eclipse', life: Number.isFinite(dur) ? dur + 0.4 : 30, reveal: 0.35, spin: 1.1 });
    if (Number.isFinite(dur) && o.release) v.schedule(dur, (w) => w.play('charge.release', { pos: follow ? vec(follow) : at.pos, dir: at.dir, facing: at.facing, scale: s }, { element: el, intensity: i }));
  });

  /** charge release: the gathered energy bursts (flash, imploded ring snapping outward, radial sparks, double shock) */
  define('charge.release', (v, at, o) => {
    const el = o.element && CHARGE[o.element] ? o.element : 'steel', C = CHARGE[el], E = EL[el], i = I(o), s = at.scale, p = at.pos;
    v.burst(C.flash, { pos: p, scale: 1.1 * s, intensity: i });
    v.flare({ kind: 'glow', pos: p, size: 1.0 * s, life: 0.07, color: E.core, intensity: i });
    v.flare({ kind: 'streak', pos: p, size: 0.26 * s, aspect: 18, life: 0.16, decay: 3, color: E.core, intensity: 0.8 * i });
    shock(v, p, vec([0.15 * at.facing, 1, 0.5]).normalize(), E, 1.4 * s, 0.18, 0.45 * i, v.realtime);
    v.light({ pos: lightAt(p, 1.4), color: E.core, intensity: 110 * i, range: 8, duration: 0.42, decay: 'outExpo' });
    v.burst(KIT[el === 'eclipse' ? 'ember' : el].lines, { pos: p, count: n(16, i), scale: 1.1 * s });
    v.burst(C.burst, { pos: p, count: n(90, i), scale: s });
    v.burst(C.glitter, { pos: p, count: n(30, i), scale: 1.5 * s });
    v.burst(KIT[el === 'eclipse' ? 'ember' : el].smoke, { pos: p, dir: [0, 1, 0], count: 5, scale: 0.9 * s });
    v.schedule(0.04, (w) => {
      w.distort({ kind: 'shock', pos: p, radius: [0.25 * s, 1.7 * s], life: 0.34, strength: 0.026 });
      if (p.y < 2.2) {
        w.distort({ kind: 'shock', pos: floor(p), normal: [0, 1, 0], radius: [0.3 * s, 3.2 * s], life: 0.5, strength: 0.03 });
        w.burst(DUST, { pos: floor(p, 0.03), dir: [0, 1, 0], count: n(8, i), scale: 0.8 * s });
      }
    });
  });

  /**
   * KO finisher at the victim's chest: an eclipse corona flash (black disc, gold ring), crit sparks both ways, a double
   * ring, rising embers of light, a floor blast (dust ring, cracks, rocks) and a dark smoke column.
   */
  define('ko.burst', (v, at, o) => {
    const el = elementOf(o), K = KIT[el], E = EL[el], i = I(o), s = at.scale, p = at.pos, d = at.dir, f = at.facing;
    const g = floor(p);
    v.burst(K.flash, { pos: p, scale: 1.3 * s, intensity: i });
    v.flare({ kind: 'flash', pos: p, size: 4 * s, life: 0.07, decay: 3, color: E.core, intensity: 0.22 * i });
    v.flare({ kind: 'star', pos: p, size: 3.2 * s, life: 0.24, decay: 3, color: [9, 7, 5], intensity: i, rotation: 0.15 });
    v.flare({ kind: 'streak', pos: p, size: 0.35 * s, aspect: 22, life: 0.26, decay: 2.5, dir: [1, 0, 0], color: E.core, intensity: i });
    v.light({ pos: lightAt(p, 1.5, 0.4), color: E.core, intensity: 180 * i, range: 10, duration: 0.6, decay: 'outCubic' });
    v.slash({ ...cutThrough(front(p, s), d, f, 0.85 * s, 42, 24), look: SLASH_LOOK[el], ...meshColors(E), width: 0.3 * s, sweep: 0.035, life: 0.34, intensity: 1.2 * i });
    v.burst(K.splash, { pos: p, dir: d, count: n(22, i), scale: 1.2 * s });
    v.burst(K.sparks, { pos: p, dir: d, count: n(150, i), scale: 1.3 * s });
    v.burst(CHARGE[el].burst, { pos: p, count: n(80, i), scale: 1.1 * s });
    v.burst(KO_RISE, { pos: p, count: n(40, i), scale: s });
    // the black sun: a disc that occludes the flash behind it under a corona (spawned last so it draws over the flares)
    v.flare({ kind: 'eclipse', pos: p, size: [1.0 * s, 2.3 * s], life: 0.6, attack: 0.02, decay: 1.4, color: [9, 6.5, 3.2], intensity: i, pull: 0.6, rotation: rng() * 6.28 });
    v.schedule(0.04, (w) => {
      w.distort({ kind: 'shock', pos: p, radius: [0.3 * s, 3.8 * s], life: 0.5, strength: 0.06 });
      w.ring({ look: 'dust', pos: g, radius: [0.3 * s, 3.4 * s], life: 1.3 });
      w.ring({ look: 'shock', pos: g, ...meshColors(E), radius: [0.2 * s, 3.2 * s], width: [0.4 * s, 1.2 * s], life: 0.45, noise: 0.75, edgeWidth: 0.16, intensity: 0.35 * i, distort: 0.03 });
      w.burst(DUST, { pos: g, dir: [0, 1, 0], count: 16, scale: 1.3 * s });
      w.burst(KO_GLOW, { pos: vec([g.x, 0.03, g.z]), dir: [0, 1, 0], scale: s, color: mul(E.core, 0.35) });
      w.decal({ kind: 'crack', pos: g, radius: 1.6 * s, life: 4, magma: el === 'ember' ? 0.8 : 0 });
      w.debris({ kind: 'rock', pos: [g.x, 0.1, g.z], count: 10, speed: [2, 6], spread: 55, size: [0.05, 0.16, 2], scale: s });
      w.burst(K.smoke, { pos: p, dir: [0, 1, 0], count: 7, scale: 1.1 * s });
    });
    v.schedule(0.15, (w) => w.burst(SMOKE_COLUMN, { pos: vec([g.x, 0.3, g.z]), dir: [0, 1, 0], count: 8, scale: 0.75 * s }));
  });

  /**
   * ultimate activation (super-freeze) on the user: an eclipse corona flash, long star rays, a backlight column of
   * light behind the fighter, a rune circle under the feet, a burst of converging-then-exploding sparks. Runs on real
   * time by default (the world is frozen); opts.realtime false puts it on game time.
   */
  define('ult.flash', (v0, at, o) => {
    const v = o.realtime === false ? v0 : P.rt;
    const el = elementOf(o, 'eclipse'), E = EL[el], i = I(o), s = at.scale, p = at.pos, f = at.facing;
    const C = CHARGE[el] || CHARGE.eclipse;
    const g = floor(p, 0);
    v.burst(C.flash, { pos: p, scale: 0.55 * s, intensity: i });
    v.flare({ kind: 'flash', pos: p, size: 3 * s, life: 0.06, decay: 2.5, color: E.core, intensity: 0.08 * i });
    v.flare({ kind: 'star', pos: p, size: 3.0 * s, life: 0.5, decay: 2.2, color: E.core, intensity: 0.7 * i, rotation: 0.12 });
    v.flare({ kind: 'streak', pos: p, size: 0.32 * s, aspect: 26, life: 0.4, decay: 2.2, dir: [1, 0, 0], color: E.core, intensity: 0.6 * i });
    v.light({ pos: lightAt(p, 1.5, 0.3), color: E.core, intensity: 150 * i, range: 9, duration: 0.8, decay: 'outCubic' });
    v.pillar({ look: el === 'frost' ? 'frost' : el === 'volt' ? 'volt' : el === 'ember' ? 'fire' : 'eclipse', palette: MESH_PAL[el] || 'eclipse', pos: vec([g.x - f * 0.15, 0, g.z - 0.6]),
      from: 'ground', height: 7 * s, radius: 0.5 * s, life: 0.9, rise: 0.08, intensity: 0.7 * i });
    v.decal({ kind: 'rune', pos: g, radius: 1.7 * s, palette: MESH_PAL[el] || 'eclipse', life: 2.2, reveal: 0.25, spin: 1.4, intensity: i });
    v.burst(C.burst, { pos: p, count: n(110, i), scale: 1.2 * s });
    v.burst(C.glitter, { pos: p, count: n(40, i), scale: 2 * s });
    v.ring({ look: 'shock', pos: g, ...meshColors(E), radius: [0.3 * s, 3.6 * s], life: 0.5, intensity: 0.7 * i });
    v.flare({ kind: 'eclipse', pos: p, size: [1.2 * s, 2.8 * s], life: 0.85, attack: 0.02, decay: 1.3, color: E.core, intensity: i, pull: 0.6, rotation: rng() * 6.28 });
    v.schedule(0.05, (w) => w.distort({ kind: 'shock', pos: p, radius: [0.3 * s, 4.5 * s], life: 0.6, strength: 0.06 }));
  });

  // aliases the presentation layer looks up (combat.<name>), and element hits that pick a level from opts.k / opts.level
  for (const name of ['hit.light', 'hit.heavy', 'hit.crit', 'hit.pierce', 'guard.block', 'guard.break', 'dust.step', 'dust.dash', 'dust.land', 'dust.stomp', 'dust.slide',
    'whoosh.light', 'whoosh.heavy', 'charge.gather', 'charge.release', 'ko.burst', 'ult.flash']) P.alias('combat.' + name, name);
  for (const lvl of ['launch', 'crumple', 'knockdown']) P.alias('combat.hit.' + lvl, 'hit.heavy');
  for (const el of ['ember', 'frost', 'volt']) {
    define(el + '.hit', (v, at, o) => {
      const k = o.k != null ? o.k : 1;
      const lvl = o.level === 'crit' || o.counter || k >= 1.3 ? 'hit.crit' : o.level === 'pierce' ? 'hit.pierce' : k < 0.75 && o.level !== 'heavy' ? 'hit.light' : 'hit.heavy';
      P.run(lvl, v, at, { ...o, element: el });
    });
  }
}
