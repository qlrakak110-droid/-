// Safe VFX access for the presentation layer + the generic `game.*` presets the feel layer falls back to.
//
//   const fx = createFx(ctx);
//   fx.play('ember.hit', at, opts)          // a preset that does not exist (yet) never throws: it plays `fallback`
//   fx.play('combat.hit.heavy', at, { element: 'frost', k: 1 }, 'game.hit')
//   fx.call('ring', { pos, ... })           // a vfx primitive that may not exist yet (mesh effects): no-op if missing
//
// The element preset library (combat.* / ember.* / frost.* / volt.*) is being built by the VFX team; everything here
// checks for it at call time and uses the generic presets below meanwhile.

import { LIB, PALETTE } from '../vfx/library.js';
import { heatRamp } from '../vfx/util.js';

/** Steel guard sparks (white-gold), used for blocks whatever the element. */
const STEEL = { core: [9, 7, 4.6], mid: [3.2, 1.7, 0.55], tail: [0.3, 0.1, 0.02] };
const ELEMENTS = ['ember', 'frost', 'volt'];
/** Slash look per element (vfx.slash). */
export const SLASH_LOOK = { ember: 'flame', frost: 'ice', volt: 'electric' };

/** Per-element particle definitions (module scope: compiled once, one table row each). */
function elementDefs(P) {
  const ramp = heatRamp(P.core, P.mid, P.tail);
  return {
    ramp,
    flash: { ...LIB.flashCore, color: [[0, 10, 9, 8, 1], [0.3, P.core[0] * 0.7, P.core[1] * 0.7, P.core[2] * 0.7, 0.75], [1, P.tail[0], P.tail[1], P.tail[2], 0]] },
    splash: { ...LIB.splash, color: heatRamp(P.core, P.mid, P.tail, { flash: 1.4 }) },
    sparks: { ...LIB.sparks, color: ramp },
    fine: { ...LIB.sparksFine, color: ramp },
    puff: { ...LIB.glowPuff, color: [[0, P.core[0] * 0.4, P.core[1] * 0.4, P.core[2] * 0.4, 0.9], [0.3, P.mid[0] * 0.5, P.mid[1] * 0.5, P.mid[2] * 0.5, 0.45], [1, 0, 0, 0, 0]] },
    motes: { ...LIB.embers, count: 14, color: heatRamp(P.core, P.mid, P.tail, { flash: 1.2 }) },
    trailMotes: { ...LIB.embers, count: 0, rate: 0, perMeter: 14, delay: 0, emit: 'random', spread: 180, inherit: 0.12, life: [0.4, 1.0], size: [0.03, 0.08, 2], color: heatRamp(P.core, P.mid, P.tail, { flash: 1.2 }) },
    charge: { ...LIB.chargeStreaks, color: [[0, P.tail[0] * 4, P.tail[1] * 4, P.tail[2] * 4, 0], [0.25, P.mid[0], P.mid[1], P.mid[2], 1], [1, P.core[0], P.core[1], P.core[2], 1]] },
    pillar: { ...LIB.sparks, count: 70, spread: 10, speed: [6, 16, 1.2], gravity: -6, life: [0.3, 0.9, 1.4], color: ramp },
  };
}
/** Generic projectile body: a hot core glow + a tail of motes (the VFX library replaces these with real projectiles). */
const DEFS = {};
for (const el of ELEMENTS) DEFS[el] = elementDefs(PALETTE[el]);
DEFS.steel = elementDefs(STEEL);
const DUST = { ...LIB.dustRing };
const DUST_SMALL = { ...LIB.dustRing, count: 6, speed: [1.2, 3.2], size: [0.35, 0.7, 1.3], life: [0.5, 1.0] };
const PEBBLES = { ...LIB.pebbles };
const SMOKE = { ...LIB.smoke };
const SHARDS = {
  tex: 'shard', blend: 'add', count: 22, life: [0.35, 0.8], spread: 70, speed: [3, 10], size: [0.05, 0.16, 2], spin: [4, 14],
  gravity: -12, collide: 'ground', bounce: 0.3, erode: 'erodeLate', erodeChannel: 'cracks',
  color: heatRamp([6, 7, 9], [1.2, 1.6, 2.6], [0.2, 0.25, 0.4]),
};

/** Every particle definition this module uses (handed to vfx.prewarm so no table row uploads mid-fight). */
export function fxDefs() {
  const out = [DUST, DUST_SMALL, PEBBLES, SMOKE, SHARDS];
  for (const k in DEFS) for (const n in DEFS[k]) if (n !== 'ramp') out.push(DEFS[k][n]);
  return out;
}

/** Element palette (linear HDR) with a neutral fallback. */
export function paletteOf(element) { return PALETTE[element] || PALETTE.ember; }
export function defsOf(element) { return DEFS[element] || DEFS.ember; }

const NULL_HANDLE = Object.freeze({ kill() {}, stop() {}, alive: false, handles: [] });

/**
 * @param {object} ctx
 * @returns {object} fx  { play, call, has, burst, emitter, defsOf, paletteOf, NULL }
 */
export function createFx(ctx) {
  const vfx = ctx.vfx;
  const failed = new Set();
  // registered preset names: the library's now, and every later vfx.define (fighter setup hooks) through a wrapper,
  // so has() is one Set lookup with no allocation (it runs on every hit)
  const known = new Set(vfx ? vfx.presets() : []);
  if (vfx) {
    const define = vfx.define;
    vfx.define = (name, fn) => { known.add(name); return define.call(vfx, name, fn); };
  }

  /** Is a preset registered. */
  function has(name) { return !!name && known.has(name); }

  /**
   * Play a preset; unknown or throwing presets fall back to `fallback` (default: the generic hit burst).
   * @returns {object} group handle (or a null handle)
   */
  function play(name, at, opts = {}, fallback = 'game.burst') {
    if (!vfx) return NULL_HANDLE;
    const names = Array.isArray(name) ? name : [name];
    for (const n of names) {
      if (!has(n) || failed.has(n)) continue;
      try { return vfx.play(n, at, opts); } catch (e) {
        failed.add(n);
        console.warn('[ed] vfx preset ' + n + ' failed: ' + (e && e.message));
      }
    }
    if (fallback && has(fallback)) {
      try { return vfx.play(fallback, at, opts); } catch (e) { console.warn('[ed] vfx fallback ' + fallback + ': ' + (e && e.message)); }
    }
    return NULL_HANDLE;
  }

  /** Call a vfx primitive that may not exist yet: fx.call('ring', opts). */
  function call(fn, ...args) {
    if (!vfx || typeof vfx[fn] !== 'function') return NULL_HANDLE;
    try { return vfx[fn](...args) || NULL_HANDLE; } catch (e) {
      if (!failed.has('fn:' + fn)) { failed.add('fn:' + fn); console.warn('[ed] vfx.' + fn + ' failed: ' + (e && e.message)); }
      return NULL_HANDLE;
    }
  }

  if (vfx) defineGeneric(vfx, call);
  return { play, call, has, defsOf, paletteOf, NULL: NULL_HANDLE, burst: (d, at) => call('burst', d, at), emitter: (d, at) => call('emitter', d, at) };
}

/** Register the generic presets (game.*). opts.element picks the palette, opts.k the strength (0.5 light .. 1.6 KO). */
function defineGeneric(vfx, call) {
  const el = (o) => (o && o.element) || 'ember';

  // impact burst: flash, directional splash + sparks, glow puff, light, streak flare, slash mark, delayed shock
  vfx.define('game.hit', (v, at, o) => {
    const e = el(o), k = o.k ?? 1, D = DEFS[e] || DEFS.ember, P = PALETTE[e] || PALETTE.ember;
    // flash, glow and light run on real time: they bloom and decay through the hit-stop while the sparks wait for it
    v.burst(D.flash, { pos: at.pos, scale: 0.28 + 0.26 * k, intensity: 0.5 + 0.2 * k, realtime: true });
    v.burst(D.splash, { pos: at.pos, dir: at.dir, count: Math.round(5 + 8 * k), intensity: 0.8 });
    v.burst(D.sparks, { pos: at.pos, dir: at.dir, count: Math.round(22 + 40 * k), scale: 0.7 + 0.25 * k });
    if (k > 0.75) v.burst(D.fine, { pos: at.pos, dir: at.dir, count: Math.round(16 * k) });
    v.burst(D.puff, { pos: at.pos, scale: 0.3 + 0.3 * k, intensity: 0.6, realtime: true });
    v.light({ pos: at.pos, color: P.core, intensity: 22 + 40 * k, range: 3.5 + 1.5 * k, duration: 0.14 + 0.1 * k, realtime: true });
    call('flare', { kind: 'streak', pos: at.pos, color: P.core, intensity: 0.35 + 0.25 * k, size: 0.08 + 0.1 * k, life: 0.08 + 0.05 * k, dir: [1, 0, 0], realtime: true });
    if (k >= 0.85 && typeof v.slash === 'function') {
      call('slash', { pos: at.pos, look: SLASH_LOOK[e] || 'razor', palette: e, facing: at.facing, normal: [0, 0, 1], forward: [1, 0, 0], roll: 0,
        arc: [-55, 55], radius: 0.55 + 0.35 * k, width: 0.35, life: 0.22 + 0.1 * k, scale: 1 });
    }
    if (k >= 1) {
      v.schedule(0.035, (v2) => v2.distort({ kind: 'shock', pos: at.pos, radius: [0.2, 0.9 + 0.7 * k], strength: 0.03 }));
      v.burst(D.motes, { pos: at.pos, count: Math.round(8 * k) });
    }
    if (k >= 1.25) v.burst(SMOKE, { pos: at.pos, dir: at.dir, count: 5, scale: 0.7 });
  });

  // generic burst for presets that do not exist yet (element-coloured, medium)
  vfx.define('game.burst', (v, at, o) => {
    const e = el(o), D = DEFS[e] || DEFS.ember, P = PALETTE[e] || PALETTE.ember, s = (o && o.k) || at.scale || 1;
    v.burst(D.flash, { pos: at.pos, scale: 0.4 * s, intensity: 0.7 });
    v.burst(D.sparks, { pos: at.pos, dir: at.dir, count: Math.round(36 * s) });
    v.burst(D.motes, { pos: at.pos, count: Math.round(10 * s) });
    v.light({ pos: at.pos, color: P.core, intensity: 40 * s, range: 5, duration: 0.25 });
  });

  // blocked strike: steel sparks fanned off the guard, small light; perfect guard adds a star glint and a ring
  vfx.define('game.guard', (v, at, o) => {
    const D = DEFS.steel, perfect = !!(o && o.perfect);
    v.burst(D.flash, { pos: at.pos, scale: perfect ? 0.8 : 0.45 });
    v.burst(D.sparks, { pos: at.pos, dir: at.dir, count: perfect ? 70 : 38, scale: 0.8 });
    v.burst(D.fine, { pos: at.pos, dir: at.dir, count: 18 });
    v.light({ pos: at.pos, color: STEEL.core, intensity: perfect ? 120 : 50, range: 4, duration: 0.16 });
    if (perfect) {
      call('flare', { kind: 'star', pos: at.pos, color: [5, 7, 10], intensity: 1, size: [0.3, 1.0], life: 0.26 });
      call('flare', { kind: 'ring', pos: at.pos, color: [2, 3.5, 6], intensity: 0.7, size: [0.2, 0.95], life: 0.26 });
    }
  });

  // guard break: shattering shards, white flash, shock
  vfx.define('game.guardBreak', (v, at) => {
    v.burst(DEFS.steel.flash, { pos: at.pos, scale: 1.2 });
    v.burst(SHARDS, { pos: at.pos, dir: at.dir, count: 30 });
    v.burst(DEFS.steel.sparks, { pos: at.pos, dir: at.dir, count: 60 });
    v.light({ pos: at.pos, color: [4, 5, 8], intensity: 160, range: 6, duration: 0.3 });
    call('flare', { kind: 'flash', pos: at.pos, color: [4, 5, 8], intensity: 1, size: [0.6, 2.4], life: 0.25 });
    v.schedule(0.03, (v2) => v2.distort({ kind: 'shock', pos: at.pos, radius: [0.2, 2.2], strength: 0.04 }));
  });

  // feet on the floor: dust ring (k ~ 0.5 step / dash, 1 landing, 1.5 body fall), pebbles when heavy
  vfx.define('game.dust', (v, at, o) => {
    const k = (o && o.k) || 1;
    v.burst(k < 0.8 ? DUST_SMALL : DUST, { pos: [at.pos.x, 0.03, at.pos.z], dir: [0, 1, 0], scale: 0.6 + 0.4 * k, count: Math.round((k < 0.8 ? 6 : 10) * k) });
    if (k >= 1) v.burst(PEBBLES, { pos: [at.pos.x, 0.05, at.pos.z], dir: [0, 1, 0], count: Math.round(6 * k), scale: 0.8 });
  });

  // skill cast / charge flash at a point (hand, weapon)
  vfx.define('game.cast', (v, at, o) => {
    const e = el(o), D = DEFS[e] || DEFS.ember, P = PALETTE[e] || PALETTE.ember;
    v.burst(D.puff, { pos: at.pos, scale: 0.9 });
    v.burst(D.motes, { pos: at.pos, count: 12 });
    v.burst({ ...D.charge, rate: 0, count: 40, life: [0.25, 0.4] }, { pos: at.pos, scale: 0.6 });
    v.light({ pos: at.pos, color: P.core, intensity: 60, range: 4, duration: 0.35, attack: 0.08 });
  });

  // ground eruption under a targeted strike / projectile hit on the floor
  vfx.define('game.erupt', (v, at, o) => {
    const e = el(o), D = DEFS[e] || DEFS.ember, P = PALETTE[e] || PALETTE.ember, k = (o && o.k) || 1;
    v.burst(D.flash, { pos: [at.pos.x, 0.6, at.pos.z], scale: 0.7 * k, intensity: 0.7 });
    v.burst(D.pillar, { pos: [at.pos.x, 0.05, at.pos.z], dir: [0, 1, 0], count: Math.round(70 * k) });
    v.burst(DUST, { pos: [at.pos.x, 0.03, at.pos.z], dir: [0, 1, 0], scale: k });
    v.light({ pos: [at.pos.x, 1, at.pos.z], color: P.core, intensity: 90 * k, range: 7, duration: 0.4 });
    call('pillar', { pos: [at.pos.x, 0, at.pos.z], palette: e, height: 2.4 * k, radius: 0.32 * k, life: 0.55, intensity: 0.6 });
    v.schedule(0.04, (v2) => v2.distort({ kind: 'shock', pos: [at.pos.x, 0.05, at.pos.z], normal: [0, 1, 0], radius: [0.3, 3 * k], strength: 0.04 }));
    if (ctxEnv(v)) ctxEnv(v).pulse([at.pos.x, 0, at.pos.z], P.core, 0.8 * k);
  });

  // big finisher (KO, ultimate climax)
  vfx.define('game.finisher', (v, at, o) => {
    const e = el(o), D = DEFS[e] || DEFS.ember, P = PALETTE[e] || PALETTE.ember, rt = !!(o && o.realtime), k = (o && o.k) || 1;
    v.burst(D.flash, { pos: at.pos, scale: 0.6, intensity: 0.5, realtime: rt });
    v.burst(D.splash, { pos: at.pos, dir: at.dir, count: Math.round(24 * k) });
    v.burst(D.sparks, { pos: at.pos, dir: at.dir, count: Math.round(160 * k), scale: 1.3 });
    v.burst({ ...D.sparks, emit: 'radial', spread: 180 }, { pos: at.pos, count: Math.round(90 * k), scale: 1.1 });
    v.burst(D.motes, { pos: at.pos, count: 30, scale: 1.4 });
    v.burst(SMOKE, { pos: at.pos, dir: at.dir, count: 8, scale: 1.2 });
    v.light({ pos: at.pos, color: P.core, intensity: 140, range: 9, duration: 0.5, realtime: rt });
    call('flare', { kind: 'flash', pos: at.pos, color: P.core, intensity: 0.28, size: [0.5, 1.6], life: 0.22, realtime: rt });
    call('flare', { kind: 'streak', pos: at.pos, color: P.core, intensity: 0.8, size: 0.3, life: 0.22, dir: [1, 0, 0], realtime: rt });
    v.schedule(0.03, (v2) => v2.distort({ kind: 'shock', pos: at.pos, radius: [0.3, 3.5], strength: 0.05 }));
    v.burst(DUST, { pos: [at.pos.x, 0.03, at.pos.z], dir: [0, 1, 0], scale: 1.6 });
  });
}

function ctxEnv(v) { return v.ctx && v.ctx.env; }
