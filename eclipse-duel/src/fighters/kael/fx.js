// KAEL 카엘 — signature VFX (registered once by present.setup through vfx.define, before vfx.prewarm).
//
// Visual language (MOVES.md, CONTRACT palette): heavy flame arcs with a razor-hot edge that cool into black smoke,
// magma bleeding through split stone, embers dripping from the armour cracks, burning ash that flutters down after
// every big blow, heat haze. Everything is built from the VFX primitives and the ember preset library; every particle
// definition lives at module scope (registered with vfx.particleDef in defineKaelFx) so nothing is compiled mid-fight.
//
// Presets (at = { pos, dir, facing, scale }; all positions in world space, `at.local(f, u, s)` for fighter-local):
//   kael.flower      ember impact flower at a contact point (opts.k strength 0.5..1.6, opts.cut: slash angle deg,
//                    opts.accent: no flash / star / light, layered over the generic hit)
//   kael.bite        the blade bites the floor at at.pos: magma crack, ember spray, fire ring, molten debris (opts.k)
//   kael.geyser      fire geyser out of a split floor (Vent Launcher, the ult hurl)
//   kael.column      one Fault Eruption magma column (opts.last: the big one)
//   kael.fault       racing fissure along at.dir: crack decals + spitting sparks + a running light (opts.length, speed)
//   kael.groove      molten groove + scraping sparks following opts.follow (the dragged blade) for opts.duration
//   kael.shell       ember shell around the body (Pyre Bulwark): flame tongues, armour cracks, heat ring (opts.follow)
//   kael.shed        the shell sheds harmlessly (whiff)
//   kael.updraft     super-freeze: embers sucked upward around Kael into the raised blade (opts.target, duration)
//   kael.corona      the blade drinks the eclipse corona and ignites white-hot (opts.follow = weapon tip)
//   kael.ashfall     aftermath: burning ash and embers settling over an area (opts.radius, opts.smoke: a smoke column)
//   kael.ringOfFire  a full vertical ring of fire around a point (the ult spin), opts.radius
//   kael.shockwave   arena-wide shockwave: fire + dust rings, ground distortion, pillars of fire around (opts.pillars)

import { LIB, PALETTE } from '../../vfx/library.js';
import { heatRamp } from '../../vfx/util.js';
import { KIT, DUST, DUST_SMALL, PEBBLES, SMOKE_COLUMN } from '../../vfx/presets/common.js';

const E = PALETTE.ember;
const EC = PALETTE.eclipse;
const RAMP = heatRamp(E.core, E.mid, E.tail, { flash: 1.3 });

// ---- particle definitions (module scope) ------------------------------------------------------------------------

/** embers dripping from the armour cracks (ambient): small, falling, cooling fast */
export const DRIP = { ...LIB.embers, count: 0, rate: 6, delay: 0, shape: { type: 'box', size: [0.42, 0.9, 0.3] }, emit: 'random', spread: 180, lift: 0,
  speed: [0.02, 0.25], gravity: -2.2, drag: 0.8, life: [0.5, 1.1], size: [0.022, 0.05, 2], turbulence: { amp: 0.15, freq: 2, speed: 1 },
  color: [[0, 10, 4, 0.9, 1], [0.3, 5, 1.2, 0.15, 1], [0.8, 1.2, 0.18, 0.02, 0.7], [1, 0.2, 0.03, 0, 0]] };
/** a few embers rising off the shoulders (ambient) */
export const RISE = { ...LIB.embers, count: 0, rate: 3, delay: 0, shape: { type: 'box', size: [0.5, 0.25, 0.3] }, emit: 'axis', spread: 25,
  speed: [0.3, 0.9], life: [0.9, 1.8, 0.8], size: [0.025, 0.06, 2] };
/** directional ember spray of a cut (along the strike direction) */
const CUT_SPRAY = { ...LIB.sparks, count: 40, spread: [38, 16], speed: [4, 13, 1.4], life: [0.18, 0.7, 1.4], color: RAMP };
/** slow burning cinders that hang after a cut */
export const CINDERS = { ...LIB.embers, count: 16, speed: [0.4, 2.4, 1.4], life: [0.7, 1.8, 0.8], size: [0.03, 0.09, 2.2], lift: 0.5 };
/** flame petals bursting from a contact */
const PETALS = { ...LIB.fireLicks, count: 10, spread: 55, speed: [2.5, 7], size: [0.45, 0.95], life: [0.2, 0.45] };
/** compact fireball cooling into smoke */
const PUFF = { ...LIB.fireball, count: 8, size: [0.55, 1.1, 1.3], speed: [0.6, 2.6, 1.2], life: [0.5, 1.0] };
/** burning ash flakes: glowing rims, flutter down, dissolve edge first */
export const ASH = { tex: 'ash', blend: 'alpha', count: 14, life: [1.4, 3.0], shape: { type: 'sphere', radius: 1.0 }, emit: 'random', speed: [0.15, 0.8],
  size: [0.04, 0.11, 1.8], gravity: -0.45, drag: 2.2, turbulence: { amp: 0.6, freq: 1.3, speed: 1.1 }, spin: [1, 4], heat: 0.45, groundFade: 0.02,
  additive: [[0, 1], [0.35, 0.55], [1, 0.12]], erode: 'erodeLate', erodeGlow: 1.2, erodeChannel: 'cracks', delay: [0, 0.4],
  color: [[0, 6, 2.2, 0.4, 1], [0.25, 1.6, 0.35, 0.05, 1], [0.6, 0.12, 0.05, 0.03, 0.9], [1, 0.04, 0.035, 0.03, 0]] };
/** spray of molten droplets out of a floor bite (upward fan, bouncing) */
const SPRAY = { ...LIB.sparks, count: 60, spread: [55, 20], speed: [3, 10, 1.3], life: [0.3, 1.0, 1.4], gravity: -11, color: RAMP };
/** fire spitting from a splitting floor (anticipation) */
export const SPIT = { ...LIB.sparks, count: 14, spread: 10, speed: [3, 8], life: [0.12, 0.4], gravity: -9, size: [0.025, 0.06, 2], color: RAMP };
/** column sparks shooting up a geyser */
const COLUMN_SPARKS = { ...LIB.sparks, count: 60, spread: 12, spreadPow: 1.4, speed: [7, 18, 1.3], gravity: -9, drag: 1.4, life: [0.35, 1.1, 1.4], stretch: 0.05, color: RAMP };
/** fireball puffs launched up a geyser */
const PLUME = { ...LIB.fireball, count: 10, emit: 'axis', spread: 14, speed: [2.5, 8, 1.2], drag: 2.4, gravity: 3, lift: 0, size: [0.8, 1.5, 1.3] };
/** scraping sparks off the dragged blade (per metre) */
const SCRAPE = { ...LIB.sparks, count: 0, rate: 70, spread: 35, speed: [2, 7, 1.3], life: [0.12, 0.45, 1.4], size: [0.02, 0.05, 2], color: RAMP };
/** molten groove: flat streak on the floor that glows and cools to black */
const GROOVE = { tex: 'smoke', blend: 'alpha', count: 0, rate: 0, perMeter: 9, life: [1.6, 2.4], shape: { type: 'disc', radius: 0.08 }, speed: 0, align: 'flat', dir: [0, 1, 0],
  size: [0.35, 0.55], aspect: 1.8, rotation: [-0.2, 0.2], groundFade: 0, heat: 0.3, additive: [[0, 1], [0.25, 0.85], [0.5, 0.2], [1, 0]], erode: [[0, 0.1], [0.5, 0.25], [1, 1]], erodeSoft: 0.3,
  color: [[0, 6, 2.4, 0.5, 0.9], [0.12, 2.6, 0.6, 0.06, 0.85], [0.35, 0.5, 0.08, 0.02, 0.8], [0.6, 0.03, 0.025, 0.02, 0.7], [1, 0.02, 0.02, 0.02, 0]] };
/** flame tongues climbing the body (bulwark shell) */
const SHELL_FIRE = { ...LIB.fire, rate: 30, shape: { type: 'box', size: [0.75, 1.7, 0.5] }, size: [0.35, 0.8, 1.4], life: [0.3, 0.6], speed: [0.8, 2.0], gravity: 3 };
/** armour cracks flaring: hot pinpricks popping all over the body */
const CRACKS = { tex: 'ember', blend: 'add', count: 0, rate: 40, life: [0.06, 0.22], shape: { type: 'box', size: [0.5, 1.5, 0.32] }, speed: 0, size: [0.05, 0.13, 2],
  flicker: { amount: 0.7, rate: 25 }, groundFade: 0, color: [[0, 10, 5, 1.2, 1], [0.4, 5, 1.4, 0.2, 1], [1, 1, 0.15, 0.02, 0]] };
/** shell motes orbiting the body */
const ORBIT = { ...LIB.embers, count: 0, rate: 40, delay: 0, shape: { type: 'ring', radius: 0.85, thickness: 0.2 }, emit: 'tangent', spread: 15, lift: 0.6, speed: [1.2, 2.4],
  swirl: 3.2, gravity: 1.2, life: [0.5, 1.0], size: [0.04, 0.09, 2] };
/** embers sucked upward (super-freeze): spawn on a floor ring, swirl, rise fast toward the raised blade */
const UPDRAFT = { ...LIB.embers, count: 0, rate: 110, delay: 0, shape: { type: 'ring', radius: 2.2, thickness: 1.4 }, emit: 'axis', spread: 12, speed: [2.5, 6],
  gravity: 4, drag: 0.4, swirl: 1.6, life: [0.5, 1.0], size: [0.03, 0.08, 2], stretch: 0.03, maxStretch: 0.5, turbulence: { amp: 0.4, freq: 1, speed: 1 } };
/** eclipse corona streaks converging on the blade */
const CORONA = { ...LIB.chargeStreaks, rate: 90, shape: { type: 'sphere', radius: 2.4, inner: 0.7 }, life: [0.4, 0.7],
  color: [[0, 1, 0.6, 0.2, 0], [0.25, 4, 2.6, 1.0, 1], [1, 12, 8, 4, 1]] };
/** floor glow pool (flat additive) */
const FLOOR_GLOW = { tex: 'glow', blend: 'add', align: 'flat', count: 1, life: [1.2, 1.2], speed: 0, size: 3.0, groundFade: 0, rotation: 0,
  color: [[0, 3.2, 1.0, 0.15, 1], [0.15, 1.6, 0.35, 0.04, 0.8], [1, 0.1, 0.02, 0, 0]] };
/** long embers rising after a big blow */
const EMBERS_LONG = { ...LIB.embers, count: 30, life: [1.4, 3.0, 0.8], speed: [1, 4.5, 1.4], gravity: 1.1 };
/** a wall of sparks thrown along a sweep (Furnace Sweep) */
export const WALL = { ...LIB.sparks, count: 120, spread: [70, 10], spreadPow: 1.1, speed: [6, 17, 1.3], life: [0.25, 0.9, 1.4], gravity: -8, color: RAMP };
/** sparks thrown forward off the thrust (Molten Lunge) */
export const SPEAR = { ...LIB.sparks, count: 50, spread: 14, speed: [6, 16, 1.3], life: [0.15, 0.5, 1.4], color: RAMP };
/** embers lingering over the crater after the ultimate (emitter) */
export const LINGER = { ...LIB.embers, count: 0, rate: 16, delay: 0, shape: { type: 'disc', radius: 2.2 }, emit: 'axis', spread: 30, speed: [0.3, 1.2], gravity: 0.6, life: [1.2, 2.4, 0.8], size: [0.03, 0.08, 2] };
/** heat haze (distortion) */
const HAZE = { ...LIB.heatHaze, count: 4 };
/** heat haze around the shell (emitter) */
const SHELL_HAZE = { ...LIB.heatHaze, count: 0, rate: 5 };

/** ult firestorm under the airborne pair (kael.inferno): flame tongues swirling up, embers, a smoke ceiling, haze */
const VORTEX = { ...LIB.fire, rate: 40, shape: { type: 'ring', radius: 1.6, thickness: 0.8 }, emit: 'tangent', spread: 15, lift: 1.4, speed: [2, 4], swirl: 2.6,
  size: [0.45, 1.1, 1.4], life: [0.5, 1.0], gravity: 3.4, drag: 0.6, align: 'axis', erode: [[0, 0], [0.35, 0.15], [1, 1]] };
const STORM_EMBERS = { ...LIB.embers, count: 0, rate: 70, delay: 0, shape: { type: 'ring', radius: 2.4, thickness: 2.0 }, emit: 'tangent', spread: 20, lift: 0.8,
  speed: [2, 5], swirl: 1.8, gravity: 1.6, life: [1.0, 2.2] };
const CEILING = { ...LIB.smokeLinger, count: 0, rate: 4.5, delay: 0, shape: { type: 'disc', radius: 2.6 }, emit: 'axis', spread: 30, speed: [0.4, 1.2], swirl: 0.5, life: [2.0, 3.2] };
const STORM_HAZE = { ...LIB.heatHaze, count: 0, rate: 5, shape: { type: 'disc', radius: 2.4 }, size: [1.2, 2.2], life: [1.0, 1.6] };
/** meteor crater: radial sparks thrown low and wide, a dark smoke blast rolling out of the crater */
const CRATER_SPARKS = { ...LIB.sparks, count: 110, spread: [80, 30], spreadPow: 0.8, speed: [5, 15, 1.3], life: [0.3, 1.0, 1.4], gravity: -9, color: RAMP };
const CRATER_SMOKE = { ...LIB.smoke, count: 12, shape: { type: 'disc', radius: 1.0 }, emit: 'radial', spread: 25, speed: [2, 5, 1.2], drag: 2.2, size: [1.0, 2.0, 1.3], life: [1.0, 1.8] };

/** Every module-scope definition (compiled up front by defineKaelFx). */
export const DEFS = [DRIP, RISE, CUT_SPRAY, CINDERS, PETALS, PUFF, ASH, SPRAY, SPIT, COLUMN_SPARKS, PLUME, SCRAPE, GROOVE, SHELL_FIRE, CRACKS, ORBIT,
  UPDRAFT, CORONA, FLOOR_GLOW, EMBERS_LONG, WALL, HAZE, SHELL_HAZE, SPEAR, LINGER, VORTEX, STORM_EMBERS, CEILING, STORM_HAZE, CRATER_SPARKS, CRATER_SMOKE];

const n = (c, k) => Math.max(1, Math.round(c * k));
const lightPos = (p, dz = 1.1, dy = 0.2) => [p.x, p.y + dy, p.z + dz];

/**
 * Register Kael's presets and compile his particle definitions.
 * @param {object} vfx ctx.vfx
 */
export function defineKaelFx(vfx) {
  for (let i = 0; i < DEFS.length; i++) vfx.particleDef('kael.def' + i, DEFS[i]);

  /** ember impact flower: flash, star, petals, cut spray along at.dir, cinders, smoke, a tilted fire ring, shock */
  vfx.define('kael.flower', (v, at, o) => {
    const k = o.k ?? 1, p = at.pos, d = at.dir, s = at.scale, full = !o.accent;
    if (full) {
      v.burst(KIT.ember.flash, { pos: p, scale: (0.35 + 0.2 * k) * s, intensity: 0.7 });
      v.flare({ kind: 'star', pos: p, size: (0.9 + 0.9 * k) * s, life: 0.12 + 0.05 * k, decay: 3, color: E.core, intensity: 0.55 + 0.25 * k, rotation: (o.cut ?? 30) * 0.0174 });
    }
    if (full && k >= 0.9) v.flare({ kind: 'streak', pos: p, size: 0.5 * s, aspect: 9, life: 0.12, decay: 2.5, color: E.core, intensity: 0.6, dir: d });
    v.burst(CUT_SPRAY, { pos: p, dir: d, count: n((full ? 36 : 20) + (full ? 40 : 24) * k, 1), scale: s });
    v.burst(PETALS, { pos: p, dir: d, count: n(5 + 7 * k, 1), scale: (0.6 + 0.35 * k) * s });
    v.burst(CINDERS, { pos: p, dir: d, count: n(8 + 14 * k, 1), scale: s });
    if (full && k >= 0.8) v.burst(PUFF, { pos: p, dir: [0, 1, 0], count: n(4 + 5 * k, 1), scale: (0.55 + 0.25 * k) * s });
    v.burst(LIB.smoke, { pos: p, dir: [0, 1, 0], count: n(2 + 3 * k, 1), scale: 0.7 * s, delay: 0.05 });
    if (full) v.ring({ normal: d, look: 'fire', pos: p, radius: [0.15 * s, (0.7 + 0.6 * k) * s], width: [0.2 * s, 0.35 * s], life: 0.32 + 0.1 * k, intensity: 0.3 + 0.1 * k });
    if (full) v.light({ pos: lightPos(p, 1.4), color: E.core, intensity: 30 + 40 * k, range: 6, duration: 0.3 + 0.2 * k, decay: 'outCubic', flicker: 0.25 });
    if (full && k >= 0.9) v.schedule(0.035, (w) => w.distort({ kind: 'shock', pos: p, radius: [0.25 * s, (1.2 + 1.0 * k) * s], life: 0.4, strength: 0.03 + 0.015 * k }));
    v.schedule(0.12, (w) => w.burst(ASH, { pos: p, count: n(4 + 8 * k, 1), scale: 0.8 * s }));
  });

  /** the blade bites the floor: magma crack + scorch, flash, molten spray, dust, (k >= 1) fire ring + molten debris */
  vfx.define('kael.bite', (v, at, o) => {
    const k = o.k ?? 1, s = at.scale, g = [at.pos.x, 0, at.pos.z], f = at.facing;
    v.decal({ kind: 'crack', pos: g, radius: (0.8 + 0.8 * k) * s, magma: 1, life: 2.6 + k, cool: 2.2, reveal: 0.1 });
    v.decal({ kind: 'scorch', pos: g, radius: (0.6 + 0.5 * k) * s, life: 2.6 + k, magma: 0.7 });
    v.burst(KIT.ember.flash, { pos: [g[0], 0.22, g[2]], scale: (0.3 + 0.25 * k) * s, intensity: 0.7 });
    v.burst(SPRAY, { pos: [g[0], 0.08, g[2]], dir: [f * 0.35, 1, 0.25], count: n(30 + 40 * k, 1), scale: s });
    v.burst(DUST, { pos: g, dir: [0, 1, 0], count: n(5 + 6 * k, 1), scale: (0.55 + 0.35 * k) * s });
    v.burst(PEBBLES, { pos: g, dir: [0, 1, 0], count: n(4 + 6 * k, 1), scale: 0.7 * s });
    v.light({ pos: [g[0], 0.6, g[2] + 1.2], color: E.core, intensity: 35 + 55 * k, range: 7, duration: 0.45 + 0.2 * k, decay: 'outCubic', flicker: 0.3 });
    if (k >= 1) {
      v.ring({ look: 'fire', pos: g, radius: [0.2 * s, (1.4 + 0.8 * k) * s], life: 0.55, distort: 0.025, intensity: 0.5 });
      v.debris({ kind: 'ember', pos: [g[0], 0.1, g[2]], dir: [0, 1, 0], count: n(6 + 5 * k, 1), speed: [2, 6.5, 1.3], spread: 45, size: [0.05, 0.16, 2], scale: s });
      v.burst(PETALS, { pos: [g[0], 0.2, g[2]], dir: [0, 1, 0], count: 6, scale: 0.75 * s });
    }
    v.schedule(0.1, (w) => {
      w.burst(LIB.smoke, { pos: [g[0], 0.3, g[2]], dir: [0, 1, 0], count: n(3 + 3 * k, 1), scale: s });
      w.burst(CINDERS, { pos: [g[0], 0.3, g[2]], count: n(10 + 10 * k, 1), scale: s });
    });
  });

  /** fire geyser out of a split floor: crack lead-in, then a column, plume, sparks, debris, rings, ash */
  vfx.define('kael.geyser', (v, at, o) => {
    const k = o.k ?? 1, s = at.scale, g = [at.pos.x, 0.02, at.pos.z];
    v.burst(FLOOR_GLOW, { pos: [g[0], 0.03, g[2]], dir: [0, 1, 0], scale: 0.6 * s });
    v.pillar({ look: 'fire', pos: g, height: (3.2 + 1.4 * k) * s, radius: (0.34 + 0.1 * k) * s, life: 0.8 + 0.2 * k, rise: 0.09, intensity: 0.3 });
    v.burst(KIT.ember.flash, { pos: [g[0], 0.3, g[2]], scale: 0.4 * s, intensity: 0.45 });
    v.burst(PLUME, { pos: [g[0], 0.3, g[2]], dir: [0, 1, 0], count: n(4 + 4 * k, 1), scale: 0.8 * s, delay: 0.05 });
    v.burst(COLUMN_SPARKS, { pos: [g[0], 0.2, g[2]], dir: [0, 1, 0], count: n(40 + 40 * k, 1), scale: s });
    v.debris({ kind: 'ember', pos: [g[0], 0.15, g[2]], dir: [0, 1, 0], count: n(6 + 6 * k, 1), speed: [3, 9, 1.3], spread: 30, size: [0.05, 0.2, 2], scale: s });
    v.debris({ kind: 'rock', pos: [g[0], 0.15, g[2]], dir: [0, 1, 0], count: n(5 + 5 * k, 1), speed: [2.5, 7, 1.3], spread: 40, size: [0.06, 0.2, 2], scale: s });
    v.ring({ look: 'fire', pos: g, radius: [0.25 * s, (1.6 + 0.8 * k) * s], life: 0.55, distort: 0.03, intensity: 0.5 });
    v.ring({ look: 'dust', pos: g, radius: [0.3 * s, (2.2 + 0.8 * k) * s], life: 1.1 });
    v.light({ pos: [g[0], 1.4, g[2] + 1.5], color: E.core, intensity: 50 + 40 * k, range: 8, duration: 0.7, attack: 0.05, decay: 'outCubic', flicker: 0.3 });
    v.burst(HAZE, { pos: [g[0], 1.0, g[2]], dir: [0, 1, 0], scale: 1.2 * s });
    v.schedule(0.3, (w) => {
      w.burst(SMOKE_COLUMN, { pos: [g[0], 1.3, g[2]], dir: [0, 1, 0], count: n(4 + 4 * k, 1), scale: 0.7 * s });
      w.burst(ASH, { pos: [g[0], 2.2, g[2]], count: n(10 + 8 * k, 1), scale: 1.3 * s });
      w.burst(EMBERS_LONG, { pos: [g[0], 1.2, g[2]], count: n(12 + 10 * k, 1), scale: s });
    });
  });

  /** one Fault Eruption column (opts.last: bigger): the crack opens and spits, then the magma column erupts */
  vfx.define('kael.column', (v, at, o) => {
    const big = !!o.last, s = at.scale * (big ? 1.2 : 1), g = [at.pos.x, 0.02, at.pos.z];
    v.decal({ kind: 'crack', pos: g, radius: (big ? 1.7 : 1.3) * s, magma: 1, reveal: 0.06, life: 3.5, cool: 2.4 });
    v.burst(SPIT, { pos: [g[0], 0.05, g[2]], dir: [0, 1, 0], scale: s });
    v.schedule(0.04, (w) => {
      w.pillar({ look: 'fire', pos: g, height: (big ? 5.2 : 4.2) * s, radius: 0.45 * s, life: big ? 1.1 : 0.9, rise: 0.07, intensity: big ? 0.38 : 0.3 });
      w.burst(KIT.ember.flash, { pos: [g[0], 0.5, g[2]], scale: (big ? 0.8 : 0.55) * s, intensity: 0.42 });
      w.burst(PLUME, { pos: [g[0], 0.3, g[2]], dir: [0, 1, 0], count: big ? 5 : 3, scale: 0.85 * s, delay: 0.05 });
      w.burst(COLUMN_SPARKS, { pos: [g[0], 0.2, g[2]], dir: [0, 1, 0], count: big ? 80 : 50, scale: s });
      w.debris({ kind: 'rock', pos: [g[0], 0.15, g[2]], dir: [0, 1, 0], count: big ? 12 : 7, speed: [2.5, 7.5, 1.3], spread: 40, size: [0.07, 0.24, 2], scale: s });
      w.debris({ kind: 'ember', pos: [g[0], 0.15, g[2]], dir: [0, 1, 0], count: big ? 10 : 5, speed: [3, 9, 1.3], spread: 30, size: [0.05, 0.18, 2], scale: s });
      w.ring({ look: 'fire', pos: g, radius: [0.3 * s, (big ? 2.6 : 1.9) * s], life: 0.5, distort: big ? 0.035 : 0.02, intensity: 0.5 });
      w.ring({ look: 'dust', pos: g, radius: [0.4 * s, (big ? 3.2 : 2.4) * s], life: 1.0 });
      w.light({ pos: [g[0], 1.3, g[2] + 1.5], color: E.core, intensity: big ? 90 : 50, range: 8, duration: 0.7, decay: 'outCubic', flicker: 0.3 });
      w.burst(FLOOR_GLOW, { pos: [g[0], 0.03, g[2]], dir: [0, 1, 0], scale: (big ? 0.8 : 0.55) * s });
    });
    v.schedule(0.32, (w) => {
      w.burst(SMOKE_COLUMN, { pos: [g[0], 1.4, g[2]], dir: [0, 1, 0], count: big ? 7 : 4, scale: 0.7 * s });
      w.burst(ASH, { pos: [g[0], 2.4, g[2]], count: big ? 14 : 8, scale: 1.3 * s });
    });
  });

  /**
   * racing fissure: from at.pos along at.dir on the floor, `length` m at `speed` m/s; crack decals open one after the
   * other with fire spitting out, a light runs with the front. opts: length (6), speed (18), step (0.75)
   */
  vfx.define('kael.fault', (v, at, o) => {
    const L = o.length ?? 6, sp = o.speed ?? 18, step = o.step ?? 0.75, f = at.facing, x0 = at.pos.x, z = at.pos.z;
    const cnt = Math.ceil(L / step);
    for (let k = 0; k <= cnt; k++) {
      const d = Math.min(L, k * step);
      v.schedule(d / sp, (w) => {
        const x = x0 + f * d;
        w.decal({ kind: 'crack', pos: [x, 0, z], radius: 0.75, magma: 1, reveal: 0.05, life: 3.2, cool: 2.4, density: 0.85 });
        w.burst(SPIT, { pos: [x, 0.04, z], dir: [0, 1, 0], count: 8 });
        if (k % 2 === 0) w.burst(DUST_SMALL, { pos: [x, 0, z], dir: [0, 1, 0], count: 3, scale: 0.9 });
      });
    }
    const lights = Math.max(1, Math.round(L / 2));
    for (let k = 0; k < lights; k++) {
      const d = (k + 0.5) * (L / lights);
      v.schedule(d / sp, (w) => w.light({ pos: [x0 + f * d, 0.5, z + 1.0], color: E.core, intensity: 70, range: 5, duration: 0.35, decay: 'outQuad' }));
    }
  });

  /** molten groove + scraping sparks following a socket (dragged blade); opts.follow (Object3D), duration */
  vfx.define('kael.groove', (v, at, o) => {
    const dur = o.duration ?? 0.25, tgt = o.follow;
    const sparks = v.emitter(SCRAPE, { pos: at.pos, dir: [-at.facing * 0.4, 1, 0.2], duration: dur });
    const groove = v.emitter(GROOVE, { pos: at.pos, dir: [0, 1, 0], duration: dur });
    if (tgt) {
      // the groove sits on the floor under the tip: follow with a function that drops it to y = 0.02
      const p = at.pos.clone();
      const onFloor = () => { tgt.getWorldPosition(p); p.y = 0.02; p.z = Math.max(p.z, 0.05); return p; };
      sparks.follow(tgt);
      groove.follow(onFloor);
    }
    const lt = v.light({ pos: lightPos(at.pos, 1.0, 0.3), color: E.core, intensity: 40, range: 4, duration: dur + 0.1, flicker: 0.5 });
    if (tgt) lt.follow(tgt, [0, 0.2, 0]);
  });

  /** ember shell (Pyre Bulwark stance): flame tongues climbing the body, cracks flaring, orbiting motes, heat ring */
  vfx.define('kael.shell', (v, at, o) => {
    const dur = o.duration ?? 0.6, tgt = o.follow;
    const em = (d, off) => { const h = v.emitter(d, { pos: at.pos, dir: [0, 1, 0], duration: dur }); if (tgt) h.follow(tgt, off); return h; };
    em(CRACKS, [0, 1.0, 0.05]);
    em(SHELL_HAZE, [0, 1.0, 0]);
    if (o.lite) return;                                    // armour tell only: cracks flaring + heat
    em(SHELL_FIRE, [0, 0.95, 0]);
    em(ORBIT, [0, 0.4, 0]);
    v.ring({ look: 'fire', pos: [at.pos.x, 0, at.pos.z], radius: [0.3, 1.25], width: [0.3, 0.5], life: 0.45, intensity: 0.5 });
    v.decal({ kind: 'glow', pos: [at.pos.x, 0, at.pos.z], radius: 1.4, palette: 'ember', life: dur + 0.2, fadeIn: 0.1, intensity: 1.1 });
    const halo = v.flare({ kind: 'glow', pos: [at.pos.x, 1.1, at.pos.z], size: 2.4, life: dur, attack: 0.08, decay: 0.6, color: E.mid, intensity: 0.14, pull: 0 });
    const lt = v.light({ pos: [at.pos.x, 1.3, at.pos.z + 1.2], color: E.core, intensity: 35, range: 5, duration: dur, attack: 0.06, flicker: 0.4, flickerRate: 11 });
    if (tgt) { halo.follow(tgt, [0, 1.1, 0]); lt.follow(tgt, [0, 1.3, 1.2]); }
  });

  /** the shell sheds harmlessly: a ring of embers and flakes falls away, a puff of smoke */
  vfx.define('kael.shed', (v, at) => {
    const p = at.pos;
    v.burst(CINDERS, { pos: [p.x, 1.1, p.z], count: 26, scale: 1.3 });
    v.burst(ASH, { pos: [p.x, 1.3, p.z], count: 14, scale: 0.9 });
    v.burst(LIB.smoke, { pos: [p.x, 1.0, p.z], dir: [0, 1, 0], count: 5, scale: 1.0 });
    v.burst(DUST_SMALL, { pos: [p.x, 0, p.z], dir: [0, 1, 0], count: 5, scale: 1.2 });
  });

  /** super-freeze: embers sucked upward around the user (ring at the feet) and converging corona streaks at the blade */
  vfx.define('kael.updraft', (v, at, o) => {
    const dur = o.duration ?? 0.6;
    v.emitter(UPDRAFT, { pos: [at.pos.x, 0.05, at.pos.z], dir: [0, 1, 0], duration: dur, target: [at.pos.x, 0, at.pos.z] });
    v.decal({ kind: 'rune', pos: [at.pos.x, 0, at.pos.z], radius: 2.0, palette: 'eclipse', life: dur + 1.0, reveal: 0.35, spin: 1.1, intensity: 0.9 });
    v.burst(DUST, { pos: [at.pos.x, 0, at.pos.z], dir: [0, 1, 0], count: 8, scale: 1.1 });
    v.light({ pos: [at.pos.x, 0.5, at.pos.z + 1.2], color: E.core, intensity: 60, range: 5, duration: dur + 0.2, attack: dur * 0.6, flicker: 0.4 });
  });

  /** corona: eclipse-gold streaks converge on the blade, which then ignites white-hot (opts.follow = tip, duration) */
  vfx.define('kael.corona', (v, at, o) => {
    const dur = o.duration ?? 0.6, tgt = o.follow;
    const st = v.emitter(CORONA, { pos: at.pos, duration: dur * 0.85 });
    const fl = v.flare({ kind: 'star', pos: at.pos, size: [0.4, 2.2], life: dur, attack: dur * 0.85, decay: 4, color: EC.core, intensity: 0.75 });
    const gl = v.flare({ kind: 'glow', pos: at.pos, size: [0.3, 1.4], life: dur + 0.25, attack: dur * 0.7, decay: 3, color: [9, 5.5, 2.4], intensity: 0.7 });
    const lt = v.light({ pos: at.pos, color: EC.core, intensity: 90, range: 6, duration: dur + 0.2, attack: dur * 0.8 });
    if (tgt) { st.follow(tgt); fl.follow(tgt); gl.follow(tgt); lt.follow(tgt, [0, 0, 0.9]); }
  });

  /** aftermath: burning ash and long embers settling over an area (opts.radius) */
  vfx.define('kael.ashfall', (v, at, o) => {
    const r = o.radius ?? 1.5, p = at.pos;
    v.burst(ASH, { pos: [p.x, p.y + 1.6, p.z], count: n(18 * r, 1), scale: r });
    v.burst(EMBERS_LONG, { pos: [p.x, p.y + 0.6, p.z], count: n(14 * r, 1) });
    if (o.smoke) v.burst(SMOKE_COLUMN, { pos: [p.x, p.y + 0.5, p.z], dir: [0, 1, 0], count: 10, scale: 1.2 });
  });

  /** a full vertical ring of fire around at.pos (the ult spin), in the camera plane tilted by opts.roll */
  vfx.define('kael.ringOfFire', (v, at, o) => {
    const R = o.radius ?? 1.6, plane = { normal: [0, 0.12, 1], forward: [1, 0, 0], roll: o.roll ?? 0, facing: at.facing };
    v.slash({ look: 'flame', pos: at.pos, ...plane, arc: [100, -250], radius: R, width: 0.8, sweep: o.sweep ?? 0.22, life: 0.95, distort: 0.03, cone: 0.2, intensity: 0.6 });
    v.slash({ look: 'razor', palette: 'ember', pos: at.pos, ...plane, arc: [100, -250], radius: R * 0.985, width: 0.14, sweep: o.sweep ?? 0.22, life: 0.35, intensity: 0.8 });
    v.light({ pos: lightPos(at.pos, 1.2, 0), color: E.core, intensity: 130, range: 8, duration: 0.6, attack: 0.05, flicker: 0.3 });
    v.burst(CINDERS, { pos: at.pos, count: 30, scale: 1.6 });
    v.schedule(0.15, (w) => w.burst(ASH, { pos: at.pos, count: 12, scale: 1.2 }));
  });

  /**
   * ult firestorm (storyboard 2.80 -> 4.30): a black-sun rune burns into the floor under the airborne pair, a ring of
   * fire races out, pillars rise BEHIND the centre one after another (never between the bodies and the lens) while a
   * swirling storm of flame and embers climbs under a smoke ceiling. No centre detonation: the meteor crater and the
   * shockwave own the finish, and the rise (5.20) must show Kael standing in the crater. opts: radius, duration, intensity
   */
  vfx.define('kael.inferno', (v, at, o) => {
    const i = o.intensity ?? 0.5, s = at.scale, R = (o.radius ?? 1.7) * s, T = o.duration ?? 1.6, g = [at.pos.x, 0.02, at.pos.z];
    v.decal({ kind: 'rune', pos: [g[0], 0, g[2]], radius: R * 1.1, palette: 'eclipse', life: T + 1.2, reveal: 0.4, spin: 0.9, intensity: 0.9 });
    v.decal({ kind: 'crack', pos: g, radius: R * 1.25, magma: 1, life: T + 3, cool: T + 1, reveal: 0.3 });
    v.ring({ look: 'fire', pos: g, radius: [0.5 * s, R * 1.7], life: 0.9, distort: 0.03, intensity: 0.6 * i + 0.2 });
    v.light({ pos: [g[0], 1.5, g[2] + 1.2], color: E.core, intensity: 160 * i, range: 10, duration: T + 0.4, attack: 0.3, flicker: 0.4, flickerRate: 7 });
    const P = o.pillars ?? 4;
    for (let k = 0; k < P; k++) {
      const a = -0.35 - (k / Math.max(1, P - 1)) * 2.45;    // a fan behind the centre (z < 0: away from every lock camera)
      const p = [g[0] + Math.cos(a) * R * 1.25, 0.02, g[2] + Math.sin(a) * R];
      v.schedule(0.15 + k * 0.12, (w) => {
        w.pillar({ look: 'fire', pos: p, height: 5.0 * s, radius: 0.45 * s, life: 1.3, intensity: 0.55 * i + 0.15 });
        w.burst(COLUMN_SPARKS, { pos: [p[0], 0.2, p[2]], dir: [0, 1, 0], count: 24, scale: s });
        w.decal({ kind: 'scorch', pos: p, radius: 0.8 * s, life: T + 1.5, magma: 1 });
      });
    }
    const storm = { pos: [g[0], 0.1, g[2]], dir: [0, 1, 0], target: g, scale: s, intensity: i, duration: T };
    v.schedule(0.2, (w) => {
      w.emitter(VORTEX, storm);
      w.emitter(STORM_EMBERS, storm);
      w.emitter(STORM_HAZE, { ...storm, duration: T - 0.3 });
      w.emitter(CEILING, { ...storm, pos: [g[0], 3.8 * s, g[2]], duration: T - 0.4 });
    });
  });

  /**
   * meteor crater (the ult finish, storyboard 3.90): flash, star, a short fire splash, magma cracks + scorch, fire and
   * dust rings racing out, radial sparks, molten + rock debris thrown wide, a smoke blast rolling out, then ash. Built
   * from soft layers only (no lit spike meshes, which read as pale cones under the ult's orange key lights).
   */
  vfx.define('kael.crater', (v, at, o) => {
    const i = o.intensity ?? 0.5, s = at.scale, g = [at.pos.x, 0.02, at.pos.z], p = [g[0], 0.6 * s, g[2]];
    v.burst(KIT.ember.flash, { pos: p, scale: 1.2 * s, intensity: 0.6 * i });
    v.flare({ kind: 'star', pos: p, size: 2.6 * s, life: 0.16, decay: 3, color: E.core, intensity: 0.7 * i, rotation: 0.2 });
    v.light({ pos: [g[0], 1.6, g[2] + 2.2], color: E.core, intensity: 160 * i, range: 12, duration: 1.0, decay: 'outCubic', flicker: 0.3 });
    v.decal({ kind: 'crack', pos: g, radius: 3.2 * s, magma: 1, life: 7, cool: 3.4, reveal: 0.1 });
    v.decal({ kind: 'scorch', pos: g, radius: 2.4 * s, life: 7, magma: 1 });
    v.pillar({ look: 'fire', pos: g, height: 2.6 * s, radius: 0.8 * s, life: 0.45, rise: 0.05, intensity: 0.45 * i + 0.1 });
    v.ring({ look: 'fire', pos: g, radius: [0.5 * s, 4.6 * s], width: [0.5 * s, 1.1 * s], life: 0.7, distort: 0.04, intensity: 0.6 * i + 0.2 });
    v.ring({ look: 'dust', pos: g, radius: [0.6 * s, 6 * s], life: 1.6 });
    v.burst(CRATER_SPARKS, { pos: [g[0], 0.25, g[2]], dir: [0, 1, 0], scale: 1.2 * s });
    v.burst(PETALS, { pos: [g[0], 0.3, g[2]], dir: [0, 1, 0], count: 10, scale: 1.1 * s });
    v.burst(EMBERS_LONG, { pos: [g[0], 0.4, g[2]], count: 40, scale: 1.3 * s });
    v.burst(DUST, { pos: g, dir: [0, 1, 0], count: 16, scale: 1.6 * s });
    v.burst(FLOOR_GLOW, { pos: [g[0], 0.03, g[2]], dir: [0, 1, 0], scale: 1.3 * s });
    v.debris({ kind: 'ember', pos: [g[0], 0.2, g[2]], dir: [0, 1, 0], count: 14, speed: [3, 9, 1.3], spread: 60, size: [0.06, 0.22, 2], scale: s });
    v.debris({ kind: 'rock', pos: [g[0], 0.2, g[2]], dir: [0, 1, 0], count: 14, speed: [2.5, 8, 1.3], spread: 65, size: [0.07, 0.26, 2], scale: s });
    v.schedule(0.05, (w) => w.distort({ kind: 'shock', pos: p, radius: [0.5 * s, 5 * s], life: 0.6, strength: 0.05 }));
    v.schedule(0.12, (w) => w.burst(CRATER_SMOKE, { pos: [g[0], 0.5, g[2]], dir: [0, 1, 0], scale: 1.3 * s }));
    v.schedule(0.3, (w) => {
      w.burst(SMOKE_COLUMN, { pos: [g[0], 0.8, g[2]], dir: [0, 1, 0], count: 8, scale: 1.1 * s });
      w.burst(ASH, { pos: [g[0], 2.5, g[2]], count: 20, scale: 2.2 * s });
      w.burst(HAZE, { pos: [g[0], 0.8, g[2]], dir: [0, 1, 0], scale: 1.6 * s });
    });
  });

  /** arena shockwave: racing fire + dust rings, ground distortion, pillars of fire around the centre */
  vfx.define('kael.shockwave', (v, at, o) => {
    const g = [at.pos.x, 0.02, at.pos.z], P = o.pillars ?? 6;
    v.ring({ look: 'fire', pos: g, radius: [1.0, 9.5], width: [0.6, 1.6], life: 1.1, height: 0.7, distort: 0.04, intensity: 0.6 });
    v.ring({ look: 'dust', pos: g, radius: [1.2, 11], life: 1.8 });
    v.ring({ look: 'shock', pos: g, radius: [0.8, 8], life: 0.6, intensity: 0.4, palette: 'ember' });
    v.distort({ kind: 'shock', pos: g, normal: [0, 1, 0], radius: [1, 10], life: 0.8, strength: 0.05 });
    v.burst(DUST, { pos: g, dir: [0, 1, 0], count: 18, scale: 2.2 });
    for (let k = 0; k < P; k++) {
      const a = -0.3 - (k / Math.max(1, P - 1)) * 2.55;     // behind and around the centre (never toward the camera)
      const r = 3.1 + 0.6 * (k % 2);
      const p = [g[0] + Math.cos(a) * r * at.facing, 0.02, g[2] + Math.sin(a) * r * 0.85];
      v.schedule(0.06 + k * 0.05, (w) => {
        w.pillar({ look: 'fire', pos: p, height: 5.2 + 1.0 * (k % 2), radius: 0.42, life: 1.0, rise: 0.08, intensity: 0.5 });
        w.burst(COLUMN_SPARKS, { pos: [p[0], 0.2, p[2]], dir: [0, 1, 0], count: 26 });
        w.decal({ kind: 'scorch', pos: p, radius: 0.9, life: 5, magma: 1 });
      });
    }
  });
}
