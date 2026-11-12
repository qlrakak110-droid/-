// Ember presets — Kael, the Cinder Warden. Visual language: heavy, slow, huge arcs of flame that cool into black
// smoke; magma bleeding through split stone; everything buoyant rises (flames, embers, smoke columns) while molten
// rock falls and bounces; burning ash flutters down afterwards; heat haze bends the air. Palette: white-yellow core
// (8, 3, 0.6) -> orange (3, 0.5, 0.05) -> deep red -> black smoke.

import { LIB, PALETTE } from '../library.js';
import { def, KIT, arcPoint, arcTangent, floor, vec, lightAt, DUST, DUST_SMALL, PEBBLES, SMOKE_COLUMN } from './common.js';
import { launch } from './motion.js';

const E = PALETTE.ember;

// ---- particle definitions (module scope) -------------------------------------------------------------------------

/** embers peeling off a blade arc: drift with the sweep, rise, flicker */
const CINDERS = def({ ...LIB.embers, count: 6, spread: 35, emit: 'axis', lift: 0.25, speed: [0.6, 3, 1.4], life: [0.6, 1.6, 0.8], delay: 0, size: [0.035, 0.1, 2.2] });
/** sparks thrown off the end of an arc along its tangent */
const ARC_SPARKS = def({ ...LIB.sparks, count: 34, spread: 16, speed: [5, 15, 1.4], life: [0.2, 0.75, 1.5] });
/** dark wisps left along the arc (alpha, value contrast next to the flame) */
const ARC_SMOKE = def({ ...LIB.smoke, count: 2, size: [0.45, 1.0, 1.3], life: [0.8, 1.6], speed: [0.2, 0.9], gravity: 0.9, delay: [0.04, 0.12], lift: 0.6,
  additive: [[0, 0.7], [0.12, 0]], color: [[0, 1.2, 0.4, 0.08, 0], [0.08, 0.24, 0.11, 0.05, 0.55], [0.4, 0.11, 0.09, 0.08, 0.45], [1, 0.08, 0.075, 0.07, 0]] });
/** flames peeling off the arc (velocity-aligned tongues cooling to smoke) */
const ARC_LICKS = def({ ...LIB.fireLicks, count: 2, size: [0.28, 0.6], speed: [0.8, 2.6], life: [0.2, 0.45], emit: 'axis', spread: 30, lift: 0.4 });
/** burning ash flakes: glowing rims, flutter down, dissolve edge first */
const ASH = def({ tex: 'ash', blend: 'alpha', count: 12, life: [1.2, 2.6], shape: { type: 'sphere', radius: 0.8 }, emit: 'random', speed: [0.2, 1.0],
  size: [0.04, 0.11, 1.8], gravity: -0.55, drag: 2.2, turbulence: { amp: 0.6, freq: 1.4, speed: 1.2 }, spin: [1, 4], heat: 0.45, groundFade: 0.02,
  additive: [[0, 1], [0.35, 0.6], [1, 0.15]], erode: 'erodeLate', erodeGlow: 1.2, erodeChannel: 'cracks', delay: [0, 0.3],
  color: [[0, 6, 2.2, 0.4, 1], [0.25, 1.6, 0.35, 0.05, 1], [0.6, 0.12, 0.05, 0.03, 0.9], [1, 0.04, 0.035, 0.03, 0]] });
/** fire spitting out of a splitting floor (anticipation): short, narrow, upward */
const SPIT = def({ ...LIB.sparks, count: 16, spread: 12, speed: [3, 8], life: [0.15, 0.45], gravity: -9, size: [0.025, 0.06, 2] });
/** column sparks shooting up an eruption */
const COLUMN_SPARKS = def({ ...LIB.sparks, count: 70, spread: 13, spreadPow: 1.4, speed: [7, 19, 1.3], gravity: -9, drag: 1.4, life: [0.35, 1.2, 1.4], stretch: 0.05 });
/** radial fireball (explosions): big overlapping puffs that stay clustered and cool into dark smoke within ~40% of life */
const BLAST = def({ tex: 'smoke', blend: 'alpha', count: 16, life: [0.7, 1.4], shape: { type: 'sphere', radius: 0.35 }, emit: 'radial', spread: 30, lift: 0.4,
  speed: [1, 4.5, 1.2], drag: 3.8, gravity: 1.8, size: [1.1, 2.0, 1.3], sizeOverLife: [[0, 0.3], [0.15, 0.8, 'outQuad'], [1, 1.25]], spin: [0.2, 0.9],
  turbulence: { amp: 0.4, freq: 0.8, speed: 1 }, heat: 0.3, shade: 0.85, erode: [[0, 0], [0.4, 0.08], [1, 0.95]], erodeSoft: 0.3,
  additive: [[0, 0.85], [0.15, 0.7], [0.35, 0.12], [1, 0]],
  color: [[0, 2.3, 0.95, 0.2, 0.9], [0.08, 1.5, 0.4, 0.05, 1], [0.22, 0.65, 0.12, 0.02, 0.95], [0.4, 0.11, 0.06, 0.04, 0.9], [1, 0.045, 0.04, 0.04, 0]] });
/** fireball puffs launched up a column */
const PLUME = def({ ...BLAST, count: 12, emit: 'axis', spread: 14, speed: [2.5, 8, 1.2], drag: 2.4, gravity: 3, lift: 0, size: [0.9, 1.6, 1.3] });
/** flames thrown up an eruption column: they stand upright as they rise (velocity-aligned they fan out like feathers) */
const ERUPT_LICKS = def({ ...LIB.fireLicks, align: 'axis', spread: 22, speed: [2.5, 7], size: [0.45, 1.1, 1.4] });
/** radial flame petals (fire flower / explosion) */
const PETALS = def({ ...LIB.fireLicks, count: 14, spread: 50, speed: [3, 8], size: [0.45, 1.0, 1.3], life: [0.2, 0.5, 1.3], align: 'axis' });
/** radial sparks (explosions) */
const SPARKS_RADIAL = def({ ...LIB.sparks, count: 90, spread: 180, emit: 'radial', speed: [4, 15, 1.4], life: [0.3, 1.1, 1.4] });
/** long-lived embers rising after a blast */
const EMBERS_LONG = def({ ...LIB.embers, count: 40, life: [1.4, 3.2, 0.8], speed: [1, 5, 1.4], gravity: 1.2 });
/** floor glow under a fire event (flat additive pool) */
const FLOOR_GLOW = def({ tex: 'glow', blend: 'add', align: 'flat', count: 1, life: [1.4, 1.4], speed: 0, size: 3.2, groundFade: 0, rotation: 0,
  color: [[0, 4, 1.3, 0.2, 1], [0.15, 2, 0.45, 0.05, 0.8], [1, 0.15, 0.02, 0, 0]] });

// trail (alpha ribbon that glows, then cools into an occluding smoky tail)
// (the outer third of the blade carries it: a solid fan from hilt to tip reads as a pie slice, not a blade smear)
const TRAIL = {
  life: 0.26, blend: 'alpha', additive: [[0, 1], [0.3, 0.85], [0.6, 0.3], [1, 0.05]],
  color: [[0, 2.6, 0.95, 0.18, 0.95], [0.1, 1.9, 0.42, 0.05, 0.8], [0.35, 0.6, 0.09, 0.02, 0.55], [0.65, 0.08, 0.055, 0.045, 0.4], [1, 0.045, 0.04, 0.035, 0]],
  edge: [10, 4.2, 1], edgeWidth: 0.06, gradient: 0.85, fadeBase: 0.72,
  width: [[0, 1], [0.3, 0.62], [1, 0.16]], erode: [[0, 0], [0.25, 0.06], [1, 0.92]], erodeSoft: 0.3,
  noise: { scale: [1.5, 1.4], speed: 1.8, amount: 0.8 }, distort: 0.016,
};
const TRAIL_EMBERS = def({ ...LIB.embers, count: 0, rate: 0, perMeter: 16, delay: 0, emit: 'random', spread: 180, inherit: 0.15, speed: [0.2, 1.2], life: [0.4, 1.2] });
const TRAIL_SPARKS = def({ ...LIB.sparksFine, count: 0, rate: 0, perMeter: 9, life: [0.1, 0.35], inherit: 0.35, spread: 180, emit: 'random' });
const TRAIL_SMOKE = def({ ...LIB.smoke, count: 0, rate: 0, perMeter: 3, delay: 0, size: [0.25, 0.55], life: [0.5, 1.0], speed: [0.1, 0.5], inherit: 0.05, emit: 'random', spread: 180,
  color: [[0, 0.3, 0.1, 0.03, 0], [0.1, 0.1, 0.06, 0.04, 0.4], [1, 0.05, 0.05, 0.05, 0]] });
const TRAIL_LICKS = def({ ...LIB.fireLicks, count: 0, rate: 0, perMeter: 4, size: [0.2, 0.45], speed: [0.3, 1.2], life: [0.15, 0.35], inherit: 0.1, emit: 'random', spread: 180 });

// aura (emitters around a body; box centred on the hips)
// many small tongues licking off the silhouette (a few big flame sprites on a body read as stickers)
const AURA_FIRE = def({ ...LIB.fire, rate: 46, shape: { type: 'box', size: [0.5, 1.5, 0.3] }, size: [0.2, 0.58, 1.5], life: [0.3, 0.65], speed: [0.6, 1.8], gravity: 3.2,
  erode: [[0, 0.05], [0.3, 0.15], [1, 1]], erodeSoft: 0.25 });
const AURA_FEET = def({ ...LIB.fire, rate: 16, shape: { type: 'ring', radius: 0.42, thickness: 0.15 }, size: [0.35, 0.8, 1.4], life: [0.3, 0.65] });
const AURA_EMBERS = def({ ...LIB.embers, count: 0, rate: 30, delay: 0, shape: { type: 'box', size: [0.7, 1.6, 0.45] }, emit: 'axis', spread: 25, speed: [0.3, 1.6], life: [0.8, 1.8, 0.8] });
/** cracks in the armour flaring: short hot sparks of light popping on the body */
const AURA_CRACKS = def({ tex: 'ember', blend: 'add', count: 0, rate: 24, life: [0.08, 0.25], shape: { type: 'box', size: [0.45, 1.5, 0.3] }, speed: 0, size: [0.05, 0.14, 2],
  flicker: { amount: 0.7, rate: 25 }, groundFade: 0, color: [[0, 10, 5, 1.2, 1], [0.4, 5, 1.4, 0.2, 1], [1, 1, 0.15, 0.02, 0]] });
const AURA_SMOKE = def({ ...LIB.smoke, count: 0, rate: 5, delay: 0, shape: { type: 'box', size: [0.5, 0.3, 0.3] }, emit: 'axis', spread: 20, speed: [0.3, 0.9], size: [0.6, 1.2], life: [1.2, 2.0], gravity: 0.8,
  color: [[0, 0.25, 0.09, 0.03, 0], [0.12, 0.07, 0.05, 0.04, 0.5], [1, 0.05, 0.05, 0.05, 0]] });
const AURA_HAZE = def({ ...LIB.heatHaze, count: 0, rate: 2.5, shape: { type: 'box', size: [0.6, 1.2, 0.3] }, size: [0.6, 1.1], life: [0.8, 1.3] });
const AURA_ASH = def({ ...ASH, count: 0, rate: 4, delay: 0, shape: { type: 'box', size: [0.8, 0.6, 0.5] }, emit: 'axis', spread: 40, speed: [0.5, 1.4], gravity: 0.2 });

// wave (travelling crescent): flames streaming from its height, falling cinders, a molten groove on the floor
const WAVE_FIRE = def({ ...LIB.fireLicks, count: 0, perMeter: 9, shape: { type: 'box', size: [0.25, 1.7, 0.35] }, emit: 'axis', spread: 30, speed: [1, 3.2], size: [0.35, 0.9, 1.4], life: [0.22, 0.5], inherit: 0.25,
  align: 'axis', erode: [[0, 0.05], [0.3, 0.2], [1, 1]],
  color: [[0, 3.6, 1.5, 0.35, 1], [0.25, 2.2, 0.55, 0.07, 1], [0.7, 0.5, 0.08, 0.02, 0.8], [1, 0.08, 0.04, 0.03, 0]] });
const WAVE_SMOKE = def({ ...TRAIL_SMOKE, perMeter: 2.5, shape: { type: 'box', size: [0.3, 1.4, 0.3] }, size: [0.6, 1.2], life: [0.9, 1.6], gravity: 0.8 });
const WAVE_CINDERS = def({ ...LIB.embers, count: 0, rate: 0, perMeter: 14, delay: 0, shape: { type: 'box', size: [0.25, 1.8, 0.3] }, emit: 'random', speed: [0.2, 1.2], gravity: -1.5, life: [0.5, 1.2] });
const GROOVE = def({ tex: 'smoke', blend: 'alpha', count: 0, perMeter: 13, life: [1.8, 2.6], shape: { type: 'disc', radius: 0.12 }, speed: 0, align: 'flat', dir: [0, 1, 0],
  size: [0.35, 0.75, 1.3], aspect: 2.4, rotation: [-0.25, 0.25], groundFade: 0, heat: 0.3, additive: [[0, 1], [0.25, 0.85], [0.5, 0.2], [1, 0]], erode: [[0, 0.1], [0.5, 0.25], [1, 1]], erodeSoft: 0.3,
  color: [[0, 6, 2.4, 0.5, 0.9], [0.12, 2.6, 0.6, 0.06, 0.85], [0.35, 0.5, 0.08, 0.02, 0.8], [0.6, 0.03, 0.025, 0.02, 0.7], [1, 0.02, 0.02, 0.02, 0]] });
const HAZE_TRAIL = def({ ...LIB.heatHaze, count: 0, perMeter: 1.6, life: [0.6, 1.0] });

// eruption / meteor / inferno
const FALL_FIRE = def({ ...LIB.fireLicks, count: 0, perMeter: 7, shape: { type: 'sphere', radius: 0.35 }, emit: 'random', spread: 180, speed: [0.5, 2], size: [0.7, 1.4], life: [0.25, 0.5], inherit: 0.05 });
const FALL_SMOKE = def({ ...TRAIL_SMOKE, perMeter: 2.2, size: [0.9, 1.6], life: [1.0, 1.8], shape: { type: 'sphere', radius: 0.4 } });
const FALL_EMBERS = def({ ...TRAIL_EMBERS, perMeter: 10, inherit: 0.08 });
const VORTEX = def({ ...LIB.fire, rate: 46, shape: { type: 'ring', radius: 1.6, thickness: 0.8 }, emit: 'tangent', spread: 15, lift: 1.4, speed: [2, 4], swirl: 2.6,
  size: [0.45, 1.15, 1.4], life: [0.5, 1.0], gravity: 3.4, drag: 0.6, align: 'axis', erode: [[0, 0], [0.35, 0.15], [1, 1]] });
const STORM_EMBERS = def({ ...LIB.embers, count: 0, rate: 70, delay: 0, shape: { type: 'ring', radius: 2.4, thickness: 2.0 }, emit: 'tangent', spread: 20, lift: 0.8, speed: [2, 5], swirl: 1.8, gravity: 1.6, life: [1.0, 2.2] });
const CEILING = def({ ...LIB.smokeLinger, count: 0, rate: 4.5, delay: 0, shape: { type: 'disc', radius: 2.6 }, emit: 'axis', spread: 30, speed: [0.4, 1.2], swirl: 0.5, life: [2.0, 3.2] });
const STORM_HAZE = def({ ...LIB.heatHaze, count: 0, rate: 5, shape: { type: 'disc', radius: 2.4 }, size: [1.2, 2.2], life: [1.0, 1.6] });

/**
 * Register the ember presets.
 * @param {object} vfx
 * @param {object} P  preset helpers ({ define, rng, motion })
 */
export function defineEmber(vfx, P) {
  const { define, rng, motion } = P;
  const I = (o) => (o.intensity != null ? o.intensity : 1);
  const n = (c, i) => Math.max(1, Math.round(c * i));
  const q = vfx.ctx.quality;

  /** shared body of the two slash presets */
  function slash(v, at, o, heavy) {
    const i = I(o), s = at.scale, f = at.facing;
    const R = (o.radius != null ? o.radius : heavy ? 2.0 : 1.55) * s;
    const W = (o.width != null ? o.width : heavy ? 0.95 : 0.65) * s;
    const arc = o.arc || (heavy ? [150, -42] : [135, -35]);
    const sweep = o.sweep != null ? o.sweep : heavy ? 0.11 : 0.08;
    const plane = { normal: o.normal || [0, 0.2, 1], forward: o.forward || [1, 0, 0], roll: o.roll || 0, facing: f };
    const sgn = Math.sign(arc[1] - arc[0]);
    v.slash({ look: 'flame', pos: at.pos, ...plane, arc, radius: R, width: W, sweep, life: heavy ? 0.8 : 0.55, distort: heavy ? 0.022 : 0.014, cone: heavy ? 0.25 : 0.15, intensity: 0.85 * i });
    // body: a wider, dimmer flame band trailing just inside the edge that cools into occluding smoke (volume + value contrast)
    if (!heavy) v.schedule(0.02, (w) => w.slash({ look: 'flame', pos: at.pos, ...plane, arc: [arc[0] - 4 * sgn, arc[1] - 3 * sgn], radius: R * 0.9, width: W * 0.85, sweep, life: 0.62, intensity: 0.5 * i, tailAdditive: 0, alpha: 0.85 }));
    v.slash({ look: 'razor', palette: 'ember', pos: at.pos, ...plane, arc, radius: R * 0.985, width: (heavy ? 0.2 : 0.13) * s, sweep, life: heavy ? 0.28 : 0.2, intensity: (heavy ? 1.05 : 1.15) * i });
    if (heavy) v.schedule(0.025, (w) => w.slash({ look: 'flame', pos: at.pos, ...plane, arc: [arc[0] - 6 * sgn, arc[1] - 4 * sgn], radius: R * 0.88, width: W * 0.7, sweep, life: 0.7, intensity: 0.55 * i, tailAdditive: 0 }));
    const mid = arcPoint(at.pos, plane, (arc[0] + arc[1]) / 2, R * 0.85);
    v.light({ pos: lightAt(mid, 1.2), color: E.core, intensity: (heavy ? 120 : 60) * i, range: heavy ? 8 : 6, duration: heavy ? 0.5 : 0.32, attack: 0.03, decay: 'outCubic', flicker: 0.2 });
    // flames, embers and smoke shed along the arc as the head passes
    const marks = heavy ? [0.2, 0.4, 0.6, 0.8, 1] : [0.3, 0.55, 0.8, 1];
    for (const u of marks) {
      const a = arc[0] + (arc[1] - arc[0]) * u;
      const p = arcPoint(at.pos, plane, a, R * (0.85 + rng() * 0.12));
      const tg = arcTangent(plane, a, sgn);
      const t = sweep * u;
      v.burst(CINDERS, { pos: p, dir: tg, count: n(heavy ? 7 : 4, i), scale: s, delay: t });
      v.burst(ARC_LICKS, { pos: p, dir: tg, count: heavy ? 3 : 2, scale: s, delay: t });
      v.burst(ARC_SMOKE, { pos: p, dir: [0, 1, 0], count: heavy ? 2 : 1, scale: (heavy ? 1.2 : 0.9) * s, delay: t });
    }
    const endA = arc[1], end = arcPoint(at.pos, plane, endA, R * 0.95), endT = arcTangent(plane, endA, sgn);
    v.burst(ARC_SPARKS, { pos: end, dir: endT, count: n(heavy ? 50 : 26, i), scale: s, delay: sweep * 0.9 });
    v.burst(LIB.heatHaze, { pos: mid, dir: [0, 1, 0], count: heavy ? 4 : 2, scale: s, delay: 0.1 });
    if (heavy) v.burst(ASH, { pos: mid, count: n(14, i), scale: 1.4 * s, delay: 0.2 });
    // the blade bites the floor at the low end of the arc
    if (end.y < 0.45) {
      v.schedule(sweep * 0.95, (w) => {
        const g = floor(end);
        w.decal({ kind: 'crack', pos: g, radius: (heavy ? 1.5 : 0.9) * s, magma: 1, life: heavy ? 3.5 : 2.4, cool: 2 });
        w.decal({ kind: 'scorch', pos: g, radius: (heavy ? 1.1 : 0.7) * s, life: heavy ? 3.5 : 2.4, magma: 0.6 });
        w.burst(KIT.ember.flash, { pos: vec([g.x, 0.2, g.z]), scale: (heavy ? 1.0 : 0.6) * s, intensity: i });
        w.burst(LIB.sparks, { pos: vec([g.x, 0.1, g.z]), dir: vec([f * 0.5, 1, 0.2]).normalize(), count: n(heavy ? 60 : 30, i), scale: s });
        w.burst(DUST, { pos: g, dir: [0, 1, 0], count: heavy ? 10 : 6, scale: (heavy ? 0.9 : 0.6) * s });
        if (heavy) {
          w.ring({ look: 'fire', pos: g, radius: [0.2 * s, 2.0 * s], life: 0.55, distort: 0.025, intensity: i });
          w.debris({ kind: 'ember', pos: [g.x, 0.1, g.z], count: n(8, i), speed: [2, 6, 1.3], spread: 45, size: [0.05, 0.16, 2], scale: s });
          w.burst(PETALS, { pos: vec([g.x, 0.2, g.z]), dir: [0, 1, 0], count: 6, scale: 0.7 * s });
          w.burst(LIB.smoke, { pos: vec([g.x, 0.3, g.z]), dir: [0, 1, 0], count: 6, scale: s, delay: 0.06 });
        }
      });
    }
  }

  /** burning cut: flame crescent with a razor-hot edge, embers and flames peeling off, dark wisps, heat haze */
  define('ember.slash', (v, at, o) => slash(v, at, o, false));
  /** huge two-layer flame arc, sparks off its end, falling ash; bites the floor (magma crack, fire ring) when it reaches it */
  define('ember.slash.heavy', (v, at, o) => slash(v, at, o, true));

  /**
   * weapon trail: a glowing ribbon that cools into a smoky occluding tail, heat refraction, embers, sparks, flames and
   * smoke shed from the tip per metre. opts: a (base socket), b (tip socket), duration (auto stop), life (trail length).
   */
  define('ember.trail', (v, at, o) => {
    const tip = o.b || at.target || at.pos;
    const hs = [v.trail({ ...TRAIL, a: o.a || tip, b: tip, life: o.life != null ? o.life : TRAIL.life, intensity: I(o) })];
    for (const d of [TRAIL_EMBERS, TRAIL_SPARKS, TRAIL_SMOKE, TRAIL_LICKS]) hs.push(v.emitter(d, { pos: vec(tip), scale: at.scale }).follow(tip));
    if (o.duration) v.schedule(o.duration, () => { for (const h of hs) h.stop(); });
  });

  /**
   * ember aura (loop): flames licking up the body and around the feet, rising embers and ash, dark smoke over the
   * shoulders, heat haze, a floor glow and a flickering light. Follows at.target / opts.follow (an Object3D at the
   * feet) or stays at at.pos. Runs until stop() or opts.duration.
   */
  define('ember.aura', (v, at, o) => {
    const i = I(o), s = at.scale, dur = o.duration || 0;
    const follow = o.follow || (at.target && at.target.isObject3D ? at.target : null);
    const em = (d, off) => { const h = v.emitter(d, { pos: at.pos, scale: s, intensity: i, duration: dur }); if (follow) h.follow(follow, off); else h.pos.add(vec(off)); return h; };
    em(AURA_FIRE, [0, 0.95 * s, 0]);
    em(AURA_FEET, [0, 0.02, 0]);
    em(AURA_EMBERS, [0, 1.0 * s, 0]);
    em(AURA_SMOKE, [0, 1.7 * s, 0]);
    em(AURA_HAZE, [0, 1.0 * s, 0]);
    em(AURA_ASH, [0, 1.5 * s, 0]);
    em(AURA_CRACKS, [0, 0.95 * s, 0.05]);
    const life = dur || 1e5;
    const halo = v.flare({ kind: 'glow', pos: vec([at.pos.x, at.pos.y + s, at.pos.z]), size: 1.7 * s, life, attack: 0.25, decay: 0.5, color: E.mid, intensity: 0.28 * i, pull: 0 });
    const lt = v.light({ pos: vec([at.pos.x, at.pos.y + s, at.pos.z + 1.2]), color: E.core, intensity: 22 * i, range: 4.5, duration: dur || Infinity, attack: 0.15, flicker: 0.45, flickerRate: 9 });
    const dc = v.decal({ kind: 'glow', pos: floor(at.pos, 0), radius: 1.1 * s, palette: 'ember', life, fadeIn: 0.2, intensity: 0.8 * i });
    if (follow) { lt.follow(follow, [0, s, 1.2]); dc.follow(follow, [0, 0, 0]); halo.follow(follow, [0, s, 0]); }
  });

  /** one eruption at a floor point: the floor splits and spits, then a magma column, plume, rocks, ring, smoke */
  function eruption(v, g, s, i) {
    v.decal({ kind: 'crack', pos: g, radius: 1.5 * s, magma: 1, reveal: 0.12, life: 4, cool: 2.6 });
    v.burst(SPIT, { pos: vec([g.x, 0.05, g.z]), dir: [0, 1, 0], count: n(16, i), scale: s });
    v.burst(DUST_SMALL, { pos: g, dir: [0, 1, 0], count: 5, scale: 1.2 * s });
    v.burst(PEBBLES, { pos: g, dir: [0, 1, 0], count: 5, scale: 0.6 * s });
    v.light({ pos: vec([g.x, 1.2, g.z + 1.8]), color: E.core, intensity: 75 * i, range: 9, duration: 1.1, attack: 0.14, decay: 'outCubic', flicker: 0.3 });
    v.schedule(0.14, (w) => {
      const b = vec([g.x, 0.25, g.z]);
      w.pillar({ look: 'fire', pos: g, height: 4.6 * s, radius: 0.55 * s, life: 1.05, intensity: 0.7 * i });
      w.burst(KIT.ember.flash, { pos: vec([g.x, 0.5, g.z]), scale: 1.1 * s, intensity: i });
      w.flare({ kind: 'glow', pos: b, size: 1.6 * s, life: 0.08, color: E.core, intensity: i });
      w.burst(PLUME, { pos: b, dir: [0, 1, 0], count: n(14, i), scale: s });
      w.burst(ERUPT_LICKS, { pos: b, dir: [0, 1, 0], count: n(12, i), scale: s });
      w.burst(COLUMN_SPARKS, { pos: b, dir: [0, 1, 0], count: n(70, i), scale: s });
      w.debris({ kind: 'ember', pos: [g.x, 0.15, g.z], dir: [0, 1, 0], count: n(10, i), speed: [3, 9, 1.3], spread: 32, size: [0.06, 0.22, 2], scale: s });
      w.debris({ kind: 'rock', pos: [g.x, 0.15, g.z], dir: [0, 1, 0], count: n(8, i), speed: [2.5, 7, 1.3], spread: 45, size: [0.07, 0.24, 2], scale: s });
      w.ring({ look: 'fire', pos: g, radius: [0.3 * s, 2.4 * s], life: 0.6, distort: 0.03, intensity: i });
      w.ring({ look: 'dust', pos: g, radius: [0.4 * s, 3.0 * s], life: 1.2 });
      w.burst(FLOOR_GLOW, { pos: vec([g.x, 0.03, g.z]), dir: [0, 1, 0], scale: 0.8 * s });
      w.burst(EMBERS_LONG, { pos: vec([g.x, 1.2, g.z]), count: n(26, i), scale: s });
      w.burst(LIB.heatHaze, { pos: vec([g.x, 1.0, g.z]), dir: [0, 1, 0], count: 5, scale: 1.2 * s });
      w.schedule(0.32, (w2) => {
        w2.burst(SMOKE_COLUMN, { pos: vec([g.x, 1.4, g.z]), dir: [0, 1, 0], count: 8, scale: 0.8 * s });
        w2.burst(ASH, { pos: vec([g.x, 2.5, g.z]), count: n(16, i), scale: 1.5 * s });
      });
    });
  }

  /**
   * fault eruption: at.pos is a floor point. Single: the floor splits (magma crack, spitting sparks, pebbles), then a
   * magma column erupts with a fireball plume, molten rocks, a fire ring and a smoke column. opts.count > 1: a crack
   * races forward from at.pos and `count` columns erupt along it, `spacing` m apart, `interval` s apart.
   */
  define('ember.eruption', (v, at, o) => {
    const i = I(o), s = at.scale, f = at.facing, cnt = o.count || 1;
    if (cnt <= 1) return eruption(v, floor(at.pos), s, i);
    const sp = (o.spacing || 1.5) * s, iv = o.interval != null ? o.interval : 0.08;
    const len = sp * cnt;
    for (let k = 0; k <= Math.ceil(len / 0.8); k++) {
      const x = Math.min(len, k * 0.8);
      v.schedule(x / 14, (w) => w.decal({ kind: 'crack', pos: vec([at.pos.x + f * x, 0, at.pos.z]), radius: 0.8 * s, magma: 1, reveal: 0.06, life: 3.5, cool: 2.2, density: 0.8 }));
    }
    for (let k = 1; k <= cnt; k++) v.schedule((k - 1) * iv + (sp * k) / 14 - 0.14, (w) => eruption(w, vec([at.pos.x + f * sp * k, 0.02, at.pos.z]), s, i));
  });

  /** fire flower: the burst when a fire crescent or fireball hits (also used by ember.wave's impact) */
  function flower(v, p, d, s, i) {
    v.burst(KIT.ember.flash, { pos: p, scale: 0.6 * s, intensity: i });
    v.flare({ kind: 'star', pos: p, size: 1.5 * s, life: 0.12, decay: 3, color: E.core, intensity: 0.75 * i, rotation: rng() });
    v.burst(KIT.ember.lines, { pos: p, count: n(14, i), scale: s });
    v.light({ pos: lightAt(p, 1.8), color: E.core, intensity: 100 * i, range: 8, duration: 0.6, decay: 'outCubic', flicker: 0.3 });
    v.burst(BLAST, { pos: p, count: n(11, i), scale: 0.75 * s });
    v.burst(PETALS, { pos: p, count: n(14, i), scale: s });
    v.burst(SPARKS_RADIAL, { pos: p, count: n(70, i), scale: s });
    v.burst(EMBERS_LONG, { pos: p, count: n(24, i), scale: s });
    v.ring({ normal: d, look: 'fire', pos: p, radius: [0.2 * s, 1.3 * s], width: [0.25 * s, 0.4 * s], life: 0.4, intensity: 0.5 * i });
    if (p.y < 2) {
      const g = floor(p);
      v.decal({ kind: 'scorch', pos: g, radius: 1.3 * s, life: 3.5, magma: 0.8 });
      v.burst(DUST, { pos: g, dir: [0, 1, 0], count: 8, scale: 0.8 * s });
    }
    v.schedule(0.04, (w) => w.distort({ kind: 'shock', pos: p, radius: [0.3 * s, 2.6 * s], life: 0.45, strength: 0.045 }));
    v.schedule(0.16, (w) => w.burst(SMOKE_COLUMN, { pos: p, dir: [0, 1, 0], count: 6, scale: 0.6 * s }));
  }
  define('ember.wave.impact', (v, at, o) => flower(v, at.pos, at.dir, at.scale, I(o)));

  /**
   * ember crescent wave (projectile): a 2.2 m burning crescent standing on the floor travels along at.dir, streaming
   * flames, falling cinders and a molten groove that cools to black scorch. at.pos = its foot on the floor.
   * Motion: opts.follow / Object3D at.target (game-driven), opts.to (flies there, then impacts), else opts.speed (11 m/s)
   * for opts.life (0.9 s). The group gains impact(pos?, dir?) (fire flower at mid height), pos and anchor.
   */
  define('ember.wave', (v, at, o) => {
    const i = I(o), s = at.scale, f = at.facing;
    const R = 1.15 * s;
    return launch(v, motion, at, o, {
      speed: 11, life: 0.9,
      body(anchor) {
        const sl = { normal: [0, 0, 1], forward: [1, 0, 0], facing: f, follow: anchor };
        const hs = [
          v.slash({ look: 'flame', ...sl, offset: [-f * R * 0.88, R * 0.95, 0], arc: [-74, 74], radius: R, width: 0.85 * s, sweep: 0.06, life: 3, heat: 0.12, intensity: 0.9 * i, distort: 0.03 }),
          v.slash({ look: 'razor', palette: 'ember', ...sl, offset: [-f * R * 0.88, R * 0.95, 0.02], arc: [-70, 70], radius: R * 0.99, width: 0.15 * s, sweep: 0.05, life: 3, heat: 0.08, intensity: 1.1 * i }),
          v.light({ pos: anchor.position, color: E.core, intensity: 70 * i, range: 6, duration: Infinity, flicker: 0.3 }).follow(anchor, [0, 1.1 * s, 1.1]),
        ];
        const em = (d, off) => hs.push(v.emitter(d, { pos: anchor.position, scale: s, intensity: i }).follow(anchor, off));
        hs.push(v.emitter(WAVE_FIRE, { pos: anchor.position, dir: vec([-f, 1.2, 0]).normalize(), scale: s, intensity: i }).follow(anchor, [f * 0.05, 1.0 * s, 0]));
        em(WAVE_SMOKE, [-f * 0.2, 1.2 * s, 0]);
        em(WAVE_CINDERS, [0, 1.1 * s, 0]);
        em(GROOVE, [0, 0.02, 0]);
        em(HAZE_TRAIL, [0, 1.0 * s, 0]);
        return hs;
      },
      impact(p, d) { flower(v, p.y < 0.4 ? vec([p.x, p.y + R * 0.95, p.z]) : p, d, s, i); },
      fizzle(p) {
        const c = vec([p.x, p.y + R * 0.9, p.z]);
        v.burst(LIB.fireLicks, { pos: c, dir: [0, 1, 0], count: 8, scale: 0.7 * s });
        v.burst(LIB.smoke, { pos: c, dir: [0, 1, 0], count: 5, scale: 0.8 * s });
        v.burst(LIB.embers, { pos: c, count: 14, scale: s });
      },
    });
  });

  /**
   * pyre explosion around a body (at.pos ~ hips/chest): flash, radial fireball and flame petals, 360° floor fire ring
   * with scorch and magma cracks, sparks, molten debris, double shock, then a rising smoke column and ash.
   */
  define('ember.explosion', (v, at, o) => {
    const i = I(o), s = at.scale, p = at.pos, g = floor(p);
    v.burst(KIT.ember.flash, { pos: p, scale: 1.6 * s, intensity: i });
    v.flare({ kind: 'flash', pos: p, size: 4 * s, life: 0.06, decay: 3, color: E.core, intensity: 0.18 * i });
    v.flare({ kind: 'star', pos: p, size: 2.6 * s, life: 0.18, decay: 3, color: E.core, intensity: i, rotation: 0.3 });
    v.light({ pos: vec([p.x, p.y + 0.4, p.z + 2.0]), color: E.core, intensity: 160 * i, range: 10, duration: 1.0, decay: 'outCubic', flicker: 0.35 });
    v.burst(BLAST, { pos: p, count: n(24, i), scale: 1.2 * s });
    v.burst(PETALS, { pos: p, count: n(18, i), scale: 1.2 * s });
    v.burst(SPARKS_RADIAL, { pos: p, count: n(120, i), scale: 1.2 * s });
    v.burst(EMBERS_LONG, { pos: p, count: n(46, i), scale: 1.2 * s });
    v.ring({ look: 'fire', pos: g, radius: [0.4 * s, 3.6 * s], life: 0.75, distort: 0.035, intensity: 0.85 * i });
    v.ring({ look: 'dust', pos: g, radius: [0.5 * s, 4.2 * s], life: 1.4 });
    v.decal({ kind: 'scorch', pos: g, radius: 2.0 * s, life: 5, magma: 1 });
    v.decal({ kind: 'crack', pos: g, radius: 2.4 * s, magma: 1, life: 5, cool: 2.8 });
    v.burst(FLOOR_GLOW, { pos: vec([g.x, 0.03, g.z]), dir: [0, 1, 0], scale: 1.2 * s });
    v.debris({ kind: 'ember', pos: [g.x, 0.4, g.z], dir: [0, 1, 0], count: n(16, i), speed: [3, 9, 1.3], spread: 70, size: [0.05, 0.2, 2], scale: s });
    v.burst(LIB.heatHaze, { pos: p, dir: [0, 1, 0], count: 8, scale: 1.4 * s, delay: 0.1 });
    v.schedule(0.05, (w) => {
      w.distort({ kind: 'shock', pos: p, radius: [0.5 * s, 3.8 * s], life: 0.55, strength: 0.05 });
      w.distort({ kind: 'shock', pos: g, normal: [0, 1, 0], radius: [0.6 * s, 4.6 * s], life: 0.7, strength: 0.04 });
    });
    v.schedule(0.18, (w) => {
      w.burst(SMOKE_COLUMN, { pos: vec([p.x, p.y + 0.4, p.z]), dir: [0, 1, 0], count: 12, scale: s });
      w.burst(ASH, { pos: vec([p.x, p.y + 1.5, p.z]), count: n(20, i), scale: 2 * s });
    });
  });

  /**
   * meteor: a fireball falls from high behind the user (opts.height 8 m, opts.fall 0.5 s) trailing flames, smoke and
   * embers while a glow grows on the floor, then craters at at.pos: magma rim rocks, cracks, fire column splash,
   * fire and dust rings, molten debris, sparks, smoke. at.pos = impact point on the floor.
   */
  define('ember.meteor', (v, at, o) => {
    const i = I(o), s = at.scale, f = at.facing, g = floor(at.pos);
    const fall = o.fall != null ? o.fall : 0.5, H = (o.height != null ? o.height : 8) * s;
    const from = vec([g.x - f * H * 0.45, H, g.z - H * 0.22]);
    v.decal({ kind: 'glow', pos: vec([g.x, 0, g.z]), radius: 1.6 * s, palette: 'ember', life: fall + 0.25, fadeIn: fall * 0.8, intensity: i });
    v.schedule(Math.max(0, fall - 0.18), (w) => w.burst(DUST_SMALL, { pos: g, dir: [0, 1, 0], count: 6, scale: 1.6 * s }));
    const m = motion.start({ pos: from, to: vec([g.x, 0.6 * s, g.z]), dur: fall, ease: 'inQuad', realtime: v.realtime, onEnd: () => crater() });
    const a = m.obj;
    const body = [
      v.flare({ kind: 'glow', pos: from, size: 1.2 * s, life: fall + 0.02, color: [9, 4.5, 1.2], intensity: 0.8 * i }).follow(a),
      v.light({ pos: from, color: E.core, intensity: 100 * i, range: 9, duration: fall, attack: 0, decay: 'linear', curve: [[0, 0.3], [1, 1]] }).follow(a, [0, 0, 1.2]),
      v.ribbon({ follow: a, width: 0.8 * s, life: 0.26, color: [[0, 2.4, 0.9, 0.18, 0.85], [0.25, 1.2, 0.25, 0.03, 0.55], [1, 0.2, 0.03, 0.01, 0]] }),
      v.emitter(FALL_FIRE, { pos: from, scale: s, intensity: i }).follow(a),
      v.emitter(FALL_SMOKE, { pos: from, scale: s }).follow(a),
      v.emitter(FALL_EMBERS, { pos: from, scale: s }).follow(a),
    ];
    function crater() {
      for (const h of body) h.stop();
      const p = vec([g.x, 0.6 * s, g.z]);
      v.burst(KIT.ember.flash, { pos: p, scale: 2 * s, intensity: i });
      v.flare({ kind: 'flash', pos: p, size: 5 * s, life: 0.07, decay: 3, color: E.core, intensity: 0.2 * i });
      v.flare({ kind: 'star', pos: p, size: 3.4 * s, life: 0.2, decay: 3, color: E.core, intensity: i, rotation: 0.2 });
      v.light({ pos: vec([g.x, 1.6, g.z + 2.2]), color: E.core, intensity: 180 * i, range: 12, duration: 1.2, decay: 'outCubic', flicker: 0.3 });
      v.decal({ kind: 'crack', pos: g, radius: 3.2 * s, magma: 1, life: 6, cool: 3.2, reveal: 0.1 });
      v.decal({ kind: 'scorch', pos: g, radius: 2.3 * s, life: 6, magma: 1 });
      v.spikes({ kind: 'magma', pattern: 'ring', pos: g, radius: 1.45 * s, count: 11, height: [0.35 * s, 0.85 * s], tilt: 42, stagger: 0.012, hold: 1.4, scale: 1 });
      v.pillar({ look: 'fire', pos: g, height: 3.4 * s, radius: 0.95 * s, life: 0.7, rise: 0.06, intensity: 0.7 * i });
      v.ring({ look: 'fire', pos: g, radius: [0.5 * s, 5 * s], life: 0.8, distort: 0.045, intensity: i });
      v.ring({ look: 'dust', pos: g, radius: [0.6 * s, 6 * s], life: 1.6 });
      v.burst(BLAST, { pos: p, count: n(26, i), scale: 1.4 * s });
      v.burst(PETALS, { pos: p, dir: [0, 1, 0], count: n(16, i), scale: 1.3 * s });
      v.burst(SPARKS_RADIAL, { pos: p, dir: [0, 1, 0], count: n(140, i), scale: 1.3 * s });
      v.burst(EMBERS_LONG, { pos: p, count: n(50, i), scale: 1.4 * s });
      v.burst(DUST, { pos: g, dir: [0, 1, 0], count: 18, scale: 1.6 * s });
      v.burst(FLOOR_GLOW, { pos: vec([g.x, 0.03, g.z]), dir: [0, 1, 0], scale: 1.6 * s });
      v.debris({ kind: 'ember', pos: [g.x, 0.2, g.z], dir: [0, 1, 0], count: n(18, i), speed: [3, 10, 1.3], spread: 55, size: [0.06, 0.24, 2], scale: s });
      v.debris({ kind: 'rock', pos: [g.x, 0.2, g.z], dir: [0, 1, 0], count: n(14, i), speed: [2.5, 8, 1.3], spread: 65, size: [0.07, 0.26, 2], scale: s });
      v.schedule(0.05, (w) => w.distort({ kind: 'shock', pos: p, radius: [0.5 * s, 5 * s], life: 0.6, strength: 0.06 }));
      v.schedule(0.22, (w) => {
        w.burst(SMOKE_COLUMN, { pos: vec([g.x, 0.8, g.z]), dir: [0, 1, 0], count: 14, scale: 1.2 * s });
        w.burst(ASH, { pos: vec([g.x, 2.5, g.z]), count: n(24, i), scale: 2.4 * s });
        w.burst(LIB.heatHaze, { pos: vec([g.x, 0.8, g.z]), dir: [0, 1, 0], count: 8, scale: 1.6 * s });
      });
    }
  });

  /**
   * inferno (ultimate scale, ~3.4 s): a rune of the black sun burns into the floor, a ring of fire races out, fire
   * pillars erupt around the centre one after another while a swirling firestorm of flame and embers climbs under a
   * smoke ceiling; at 2.4 s the centre detonates (explosion, huge column). at.pos = centre on the floor.
   * opts: radius (3), duration of the storm (3).
   */
  define('ember.inferno', (v, at, o) => {
    const i = I(o), s = at.scale, g = floor(at.pos), R = (o.radius || 3) * s, T = o.duration || 3;
    v.decal({ kind: 'rune', pos: vec([g.x, 0, g.z]), radius: R * 1.1, palette: 'eclipse', life: T + 1.2, reveal: 0.4, spin: 0.9, intensity: i });
    v.decal({ kind: 'crack', pos: g, radius: R * 1.25, magma: 1, life: T + 3, cool: T + 1, reveal: 0.3 });
    v.ring({ look: 'fire', pos: g, radius: [0.5 * s, R * 1.7], life: 0.9, distort: 0.04, intensity: i });
    v.light({ pos: vec([g.x, 1.5, g.z + 1.2]), color: E.core, intensity: 200 * i, range: 12, duration: T + 0.6, attack: 0.3, flicker: 0.4, flickerRate: 7 });
    const pillars = Math.max(3, Math.round(6 * (0.5 + 0.5 * q.particleScale)));
    for (let k = 0; k < pillars; k++) {
      const a = (k / pillars) * Math.PI * 2 + 0.3;
      const p = vec([g.x + Math.cos(a) * R, 0, g.z + Math.sin(a) * R * 0.8]);
      v.schedule(0.15 + k * 0.12, (w) => {
        w.pillar({ look: 'fire', pos: p, height: 5.5 * s, radius: 0.5 * s, life: 1.7, intensity: 0.65 * i });
        w.burst(COLUMN_SPARKS, { pos: vec([p.x, 0.2, p.z]), dir: [0, 1, 0], count: n(30, i), scale: s });
        w.burst(DUST_SMALL, { pos: p, dir: [0, 1, 0], count: 4, scale: 1.4 * s });
        w.decal({ kind: 'scorch', pos: p, radius: 0.9 * s, life: T + 1, magma: 1 });
      });
    }
    const storm = { pos: vec([g.x, 0.1, g.z]), dir: [0, 1, 0], target: g, scale: s, intensity: i, duration: T };
    v.schedule(0.3, (w) => {
      w.emitter(VORTEX, storm);
      w.emitter(STORM_EMBERS, storm);
      w.emitter(STORM_HAZE, { ...storm, duration: T - 0.3 });
      w.emitter(CEILING, { ...storm, pos: vec([g.x, 3.8 * s, g.z]), duration: T - 0.6 });
    });
    v.schedule(T * 0.8, (w) => {
      P.run('ember.explosion', w, { ...at, pos: vec([g.x, 1.2 * s, g.z]), scale: 1.35 * s, dir: at.dir }, { intensity: i });
      w.pillar({ look: 'fire', pos: g, height: 8 * s, radius: 1.1 * s, life: 1.4, rise: 0.08, intensity: 0.75 * i });
      w.debris({ kind: 'rock', pos: [g.x, 0.2, g.z], dir: [0, 1, 0], count: n(16, i), speed: [3, 10, 1.3], spread: 50, size: [0.08, 0.28, 2], scale: s });
    });
  });
}
