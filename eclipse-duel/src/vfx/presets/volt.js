// Volt presets — Vorn, the Stormcaller Lancer. Visual language: instantaneous and straight. Lines along the thrust
// axis, jagged branching bolts, rings punched around the spear's axis, strobing flicker, gold sparks that bounce, dark
// scorch and thin ozone wisps. Nothing lingers softly: it strikes, crackles, and is gone, leaving burn marks.
// Palette: violet-white core (5, 3.5, 9) -> violet (1.6, 0.8, 4) -> gold sparks (8, 5, 1).

import { LIB, PALETTE } from '../library.js';
import { heatRamp } from '../util.js';
import { def, key, KIT, GOLD, arcPoint, arcTangent, floor, vec, lightAt, DUST, DUST_SMALL } from './common.js';
import { launch } from './motion.js';
import * as THREE from 'three';

const V = PALETTE.volt;
const WHITE = [7, 6, 11];

// ---- particle definitions (module scope) -------------------------------------------------------------------------

/** gold sparks: ballistic, bouncy, many small */
const GOLD_SPARKS = def({ ...LIB.sparks, count: 40, bounce: 0.5, friction: 0.6, color: heatRamp(GOLD.core, GOLD.mid, GOLD.tail) });
const GOLD_RADIAL = def({ ...GOLD_SPARKS, count: 90, spread: 180, emit: 'radial', speed: [4, 15, 1.4], life: [0.3, 1.1, 1.4] });
const GOLD_UP = def({ ...GOLD_SPARKS, count: 80, spread: 55, speed: [4, 13, 1.4], life: [0.4, 1.2, 1.4] });
/** crackle arcs flying out (velocity-aligned arc sprites, strobing) */
const ARCS = def({ tex: 'arc', blend: 'add', count: 12, life: [0.06, 0.18], shape: { type: 'sphere', radius: 0.25 }, emit: 'radial', spread: 20, speed: [5, 12],
  size: [0.3, 0.8], aspect: 2.2, align: 'velocity', stretch: 0.01, rotation: 0, flicker: { amount: 0.8, rate: 40 }, groundFade: 0,
  color: [key(0, WHITE, 1, 1.1), key(0.4, V.core, 1, 0.8), key(1, V.mid, 0)] });
/** crawling arcs (no motion, random orientation, very short) */
const CRAWL = def({ tex: 'arc', blend: 'add', count: 6, life: [0.05, 0.12], shape: { type: 'sphere', radius: 0.3 }, emit: 'random', speed: 0,
  size: [0.18, 0.45], aspect: 1.8, rotation: [0, 6.28], flicker: { amount: 0.9, rate: 50 }, groundFade: 0,
  color: [key(0, WHITE, 1, 0.9), key(1, V.mid, 0, 1.2)] });
/** arcs and gold sparks spawned along a line (at.pos -> at.to) */
const ARCS_LINE = def({ ...ARCS, shape: { type: 'line' }, speed: [2, 6], size: [0.2, 0.55] });
const GOLD_LINE = def({ ...GOLD_SPARKS, count: 40, shape: { type: 'line' }, spread: 50, speed: [3, 10, 1.4], life: [0.3, 1.0, 1.4] });
/** crackle on the floor while a strike is telegraphed */
const WARN_CRAWL = def({ ...CRAWL, count: 0, rate: 30, shape: { type: 'disc', radius: 1 }, size: [0.2, 0.5] });
/** ionised motes rising and flickering */
const MOTES = def({ tex: 'dot', blend: 'add', count: 14, life: [0.4, 1.0], shape: { type: 'sphere', radius: 0.4 }, emit: 'random', speed: [0.2, 1.0],
  size: [0.025, 0.06, 2], gravity: 0.8, drag: 2, turbulence: { amp: 0.7, freq: 2, speed: 2 }, flicker: { amount: 0.8, rate: 25 },
  color: [key(0, V.core, 0, 0.8), key(0.1, V.core, 1, 0.8), key(1, V.mid, 0, 0.6)] });
/** thin dark ozone wisps after a strike (alpha) */
const OZONE = def({ ...LIB.smoke, count: 4, size: [0.4, 0.9], life: [0.8, 1.5], speed: [0.3, 1.0], gravity: 0.6,
  color: [[0, 0.3, 0.2, 0.6, 0], [0.06, 0.06, 0.05, 0.1, 0.5], [0.5, 0.045, 0.04, 0.06, 0.35], [1, 0.04, 0.04, 0.05, 0]] });
/** violet floor glow under a strike */
const FLOOR_GLOW = def({ tex: 'glow', blend: 'add', align: 'flat', count: 1, life: [0.6, 0.6], speed: 0, size: 3.0, groundFade: 0, rotation: 0,
  color: [[0, 3, 2, 6, 1], [0.15, 1.2, 0.6, 3, 0.6], [1, 0.05, 0.02, 0.2, 0]] });
/** storm rain: bright streaks falling fast */
const RAIN = def({ tex: 'streak', blend: 'add', count: 0, rate: 480, life: [0.25, 0.4], shape: { type: 'box', size: [14, 1, 7] }, emit: 'axis', dir: [-0.12, -1, 0], spread: 3,
  speed: [17, 23], size: [0.03, 0.055], stretch: 0.05, maxStretch: 1.6, rotation: 0, groundFade: 0.05,
  color: [[0, 1.3, 1.2, 2.2, 0], [0.15, 1.3, 1.2, 2.2, 0.9], [1, 0.7, 0.65, 1.4, 0.6]] });
/** storm clouds overhead: dark violet-grey billows, lit from inside by flickering glows */
const CLOUD = def({ ...LIB.smokeLinger, count: 0, rate: 7, delay: 0, shape: { type: 'disc', radius: 4.5, height: 0.8 }, emit: 'axis', spread: 70, speed: [0.2, 0.7], gravity: 0, swirl: 0.25,
  size: [2.8, 4.5, 1.3], life: [2.2, 3.4], shade: 0.9, color: [[0, 0.09, 0.075, 0.14, 0], [0.15, 0.07, 0.06, 0.1, 0.85], [0.7, 0.055, 0.05, 0.08, 0.75], [1, 0.05, 0.045, 0.07, 0]] });

const GROUND_CRAWL = def({ ...CRAWL, count: 0, rate: 26, shape: { type: 'disc', radius: 3 }, size: [0.25, 0.6], color: [key(0, V.core, 1, 0.8), key(1, V.mid, 0, 1)] });
const GATHER = def({ ...LIB.chargeStreaks, rate: 60, shape: { type: 'sphere', radius: 3.4, inner: 0.6 }, size: [0.03, 0.08, 1.6], life: [0.6, 1.0], color: [key(0, V.tail, 0, 4), key(0.25, V.mid, 1), key(1, WHITE, 1)] });

// trail
const TRAIL = {
  life: 0.14, color: [[0, 2.4, 1.6, 6, 0.65], [0.15, 0.9, 0.45, 2.6, 0.42], [0.5, 0.22, 0.08, 0.6, 0.2], [1, 0.05, 0.02, 0.15, 0]],
  edge: [7, 5, 12], edgeWidth: 0.055, gradient: 0.85, fadeBase: 0.78, width: [[0, 1], [0.3, 0.5], [1, 0.1]],
  erode: [[0, 0], [0.2, 0.14], [1, 0.95]], erodeSoft: 0.12, noise: { scale: [3.4, 2.2], speed: 5, amount: 0.85 },
};
const TRAIL_SPARKS = def({ ...GOLD_SPARKS, count: 0, perMeter: 8, emit: 'random', spread: 180, speed: [0.5, 3], inherit: 0.3, life: [0.3, 0.8] });
const TRAIL_ARCS = def({ ...CRAWL, count: 0, perMeter: 4, shape: { type: 'point' } });

// aura
const AURA_CRAWL = def({ ...CRAWL, count: 0, rate: 44, shape: { type: 'box', size: [0.55, 1.6, 0.4] }, size: [0.25, 0.6] });
const AURA_MOTES = def({ ...MOTES, count: 0, rate: 16, shape: { type: 'box', size: [0.7, 1.6, 0.5] } });
const AURA_DRIP = def({ ...GOLD_SPARKS, count: 0, rate: 10, shape: { type: 'box', size: [0.6, 1.2, 0.4] }, emit: 'random', speed: [0.3, 1.5], life: [0.4, 0.9], size: [0.025, 0.06] });
const AURA_GROUND = def({ ...CRAWL, count: 0, rate: 10, shape: { type: 'ring', radius: 0.45, thickness: 0.3 }, size: [0.2, 0.45] });

// projectile
const SHOT_SPARKS = def({ ...TRAIL_SPARKS, perMeter: 5 });
const SHOT_ARCS = def({ ...TRAIL_ARCS, perMeter: 3, shape: { type: 'sphere', radius: 0.25 } });

/**
 * Register the volt presets.
 * @param {object} vfx
 * @param {object} P  preset helpers ({ define, rng, motion })
 */
export function defineVolt(vfx, P) {
  const { define, rng, motion } = P;
  const I = (o) => (o.intensity != null ? o.intensity : 1);
  const n = (c, i) => Math.max(1, Math.round(c * i));
  const jit = (p, r, ry = r) => vec([p.x + (rng() - 0.5) * 2 * r, p.y + (rng() - 0.5) * 2 * ry, p.z + (rng() - 0.5) * r]);

  /**
   * spear thrust along at.dir from at.pos (the hand): a lightning line to the tip (opts.reach 2.4 m), rings punched
   * around the thrust axis, bolts forking ahead of the tip, a narrow cone of gold sparks, an axial shock.
   */
  define('volt.thrust', (v, at, o) => {
    const i = I(o), s = at.scale, d = at.dir, reach = (o.reach || 2.4) * s;
    const tip = at.pos.clone().addScaledVector(d, reach);
    v.beam({ look: 'volt', from: at.pos, to: tip, width: 0.3 * s, extend: 0.03, release: 0.09, life: 0.17, flares: false, intensity: i });
    v.flare({ kind: 'streak', pos: tip, size: 0.18 * s, aspect: 22, life: 0.14, decay: 2.5, dir: d, color: V.core, intensity: 0.9 * i });
    v.flare({ kind: 'glow', pos: tip, size: 0.7 * s, life: 0.08, color: WHITE, intensity: 0.8 * i });
    v.light({ pos: lightAt(tip, 1.3), color: V.core, intensity: 60 * i, range: 5, duration: 0.22, decay: 'outCubic', flicker: 0.5 });
    [0.35, 0.68, 1.0].forEach((u, k) => v.schedule(0.012 * k, (w) => w.ring({ normal: d, look: 'volt', pos: at.pos.clone().addScaledVector(d, reach * u),
      radius: [0.05 * s, (0.35 + 0.35 * u) * s], width: [0.1 * s, (0.2 + 0.15 * u) * s], fill: 2.4, life: 0.17, intensity: (0.55 + 0.35 * u) * i })));
    for (let k = 0; k < 2; k++) {
      v.bolt({ from: tip, to: jit(tip.clone().addScaledVector(d, 1.3 * s), 0.25 * s, 0.5 * s), width: 0.12 * s, branches: 2, strikes: 2, detail: 5, life: 0.22, leader: 0, impact: false, intensity: i });
    }
    v.burst(GOLD_SPARKS, { pos: tip, dir: d, count: n(30, i), scale: 0.8 * s });
    v.burst(ARCS_LINE, { pos: at.pos, to: tip, count: n(8, i), scale: s });
    v.schedule(0.03, (w) => w.distort({ kind: 'shock', pos: tip, normal: d, radius: [0.1 * s, 1.1 * s], life: 0.25, strength: 0.04 }));
    // residue: arcs keep crawling where the tip stopped, ionised motes drift up, thin ozone wisps
    for (const t of [0.08, 0.16, 0.26]) v.burst(CRAWL, { pos: tip, count: n(3, i), scale: 0.8 * s, delay: t });
    v.burst(MOTES, { pos: tip, count: n(12, i), scale: 1.2 * s, delay: 0.05 });
    v.burst(OZONE, { pos: tip, dir: [0, 1, 0], count: 2, scale: 0.6 * s, delay: 0.12 });
  });

  /** electric crescent: jagged filaments, gold sparks off the tip, crackle along the arc, small arcs grounding to the floor */
  define('volt.slash', (v, at, o) => {
    const i = I(o), s = at.scale, f = at.facing;
    const R = (o.radius != null ? o.radius : 1.55) * s;
    const arc = o.arc || [160, -20];
    const sweep = o.sweep != null ? o.sweep : 0.07;
    const plane = { normal: o.normal || [0, 0.45, 1], forward: o.forward || [1, 0, 0], roll: o.roll || 0, facing: f };
    const sgn = Math.sign(arc[1] - arc[0]);
    v.slash({ look: 'electric', pos: at.pos, ...plane, arc, radius: R, width: (o.width || 0.45) * s, sweep, life: 0.4, intensity: i });
    v.slash({ look: 'razor', palette: 'volt', core: WHITE, pos: at.pos, ...plane, arc, radius: R * 0.99, width: 0.08 * s, sweep, life: 0.14, intensity: 1.3 * i });
    const end = arcPoint(at.pos, plane, arc[1], R), endT = arcTangent(plane, arc[1], sgn);
    v.burst(GOLD_SPARKS, { pos: end, dir: endT, count: n(36, i), scale: 0.9 * s, delay: sweep });
    v.burst(ARCS, { pos: end, dir: endT, count: n(8, i), scale: s, delay: sweep });
    for (const u of [0.3, 0.6, 0.9]) {
      const a = arc[0] + (arc[1] - arc[0]) * u;
      v.burst(CRAWL, { pos: arcPoint(at.pos, plane, a, R * 0.9), count: n(4, i), scale: s, delay: sweep * u + 0.02 });
    }
    const mid = arcPoint(at.pos, plane, (arc[0] + arc[1]) / 2, R);
    v.light({ pos: lightAt(mid, 1.2), color: V.core, intensity: 55 * i, range: 5.5, duration: 0.3, decay: 'outCubic', flicker: 0.6, flickerRate: 22 });
    const low = arcPoint(at.pos, plane, arc[0] + (arc[1] - arc[0]) * 0.75, R * 0.9);
    if (low.y < 1.4) v.schedule(sweep, (w) => w.bolt({ from: low, to: vec([low.x + f * 0.4, 0.02, low.z + 0.2]), width: 0.1 * s, branches: 1, strikes: 2, detail: 4, life: 0.18, leader: 0, impact: true, intensity: 0.8 * i }));
    v.burst(OZONE, { pos: mid, dir: [0, 1, 0], count: 2, scale: 0.6 * s, delay: 0.1 });
    v.burst(MOTES, { pos: end, count: n(10, i), scale: 1.1 * s, delay: sweep + 0.04 });
    v.burst(CRAWL, { pos: end, count: n(3, i), scale: 0.8 * s, delay: sweep + 0.14 });
  });

  /** weapon trail: a thin crackling violet ribbon with a white edge; gold sparks and arcs shed from the tip. opts: a, b, duration, life */
  define('volt.trail', (v, at, o) => {
    const tip = o.b || at.target || at.pos;
    const hs = [v.trail({ ...TRAIL, a: o.a || tip, b: tip, life: o.life != null ? o.life : TRAIL.life, intensity: I(o) })];
    for (const d of [TRAIL_SPARKS, TRAIL_ARCS]) hs.push(v.emitter(d, { pos: vec(tip), scale: at.scale }).follow(tip));
    if (o.duration) v.schedule(o.duration, () => { for (const h of hs) h.stop(); });
  });

  /**
   * storm aura (loop): small bolts jump between points on the body every 70-160 ms, arcs crawl, ionised motes rise,
   * gold sparks drip and bounce, a strobing violet light. Follows at.target / opts.follow (feet) or stays at at.pos.
   */
  define('volt.aura', (v, at, o) => {
    const i = I(o), s = at.scale, dur = o.duration || 0;
    const follow = o.follow || (at.target && at.target.isObject3D ? at.target : null);
    const base = new THREE.Vector3(), pa = new THREE.Vector3(), pb = new THREE.Vector3();
    const where = () => (follow ? follow.getWorldPosition(base) : base.copy(at.pos));
    const em = (d, off) => { const h = v.emitter(d, { pos: at.pos, scale: s, intensity: i, duration: dur }); if (follow) h.follow(follow, off); else h.pos.add(vec(off)); return h; };
    em(AURA_CRAWL, [0, 1.0 * s, 0]);
    em(AURA_MOTES, [0, 1.0 * s, 0]);
    em(AURA_DRIP, [0, 1.0 * s, 0]);
    em(AURA_GROUND, [0, 0.05, 0]);
    const halo = v.flare({ kind: 'glow', pos: vec([at.pos.x, at.pos.y + s, at.pos.z]), size: 1.6 * s, life: dur || 1e5, attack: 0.15, decay: 0.5, color: V.mid, intensity: 0.22 * i, pull: 0 });
    if (follow) halo.follow(follow, [0, s, 0]);
    const lt = v.light({ pos: vec([at.pos.x, at.pos.y + s, at.pos.z + 1.2]), color: V.core, intensity: 16 * i, range: 4, duration: dur || Infinity, attack: 0.1, flicker: 0.7, flickerRate: 20 });
    if (follow) lt.follow(follow, [0, s, 1.2]);
    let live = true;
    const pick = (out) => out.copy(where()).add(vec([(rng() - 0.5) * 0.7 * s, (0.2 + rng() * 1.6) * s, (rng() - 0.3) * 0.5 * s]));
    const tick = (w) => {
      if (!live) return;
      pick(pa); pick(pb);
      w.bolt({ from: pa.clone(), to: pb.clone(), width: 0.12 * s, branches: 2, strikes: 2, interval: [0.03, 0.05], detail: 5, life: 0.13, leader: 0, impact: false, glow: 1, intensity: i });
      if (rng() < 0.35) { pick(pa); w.bolt({ from: pa.clone(), to: vec([pa.x + (rng() - 0.5) * 0.8, 0.02, pa.z + (rng() - 0.3) * 0.5]), width: 0.07 * s, branches: 1, strikes: 1, detail: 4, life: 0.1, leader: 0, impact: true, intensity: 0.8 * i }); }
      w.schedule(0.05 + rng() * 0.07, tick);
    };
    v.schedule(0.05, tick);
    if (dur) v.schedule(dur, () => { live = false; });
    return { stop() { live = false; } };
  });

  /** one sky strike on a floor point g (k = size) */
  function strike(v, g, s, i, f, k) {
    const from = vec([g.x - f * 1.2 * k + (rng() - 0.5), 9.5, g.z - 2]);
    v.bolt({ from, to: vec([g.x, 0.05, g.z]), width: 0.4 * s * k, branches: Math.round(5 * k), strikes: 3, light: 260 * i * k, lightRange: 10 * k, intensity: i });
    v.pillar({ look: 'volt', pos: g, height: 9.5, radius: 0.3 * s * k, life: 0.55, intensity: 0.85 * i });
    v.burst(KIT.volt.flash, { pos: vec([g.x, 0.35, g.z]), scale: 1.1 * s * k, intensity: i });
    v.decal({ kind: 'scorch', pos: g, radius: 1.4 * s * k, life: 4.5, palette: 'volt', magma: 0.8 });
    v.decal({ kind: 'crack', pos: g, radius: 1.7 * s * k, life: 4.5, density: 0.9 });
    v.ring({ look: 'volt', pos: g, radius: [0.2 * s, 2.8 * s * k], life: 0.45, distort: 0.04, intensity: i });
    v.ring({ look: 'dust', pos: g, radius: [0.3 * s, 2.8 * s * k], life: 1.1 });
    v.burst(FLOOR_GLOW, { pos: vec([g.x, 0.03, g.z]), dir: [0, 1, 0], scale: s * k });
    v.burst(GOLD_UP, { pos: vec([g.x, 0.12, g.z]), dir: [0, 1, 0], count: n(90 * k, i), scale: s });
    v.burst(ARCS, { pos: vec([g.x, 0.15, g.z]), dir: [0, 1, 0], count: n(14 * k, i), scale: 1.3 * s });
    v.burst(DUST, { pos: g, dir: [0, 1, 0], count: Math.round(10 * k), scale: s * k });
    v.debris({ kind: 'rock', pos: [g.x, 0.1, g.z], count: n(10 * k, i), speed: [3, 9, 1.3], spread: 45, scale: s });
    v.schedule(0.12, (w) => w.burst(OZONE, { pos: vec([g.x, 0.4, g.z]), dir: [0, 1, 0], count: Math.round(5 * k), scale: s * k }));
  }

  /**
   * sky strike on a floor point (at.pos): a bolt with return strokes, a column of light, scorch and cracks, a crackling
   * ring, gold sparks, rocks, ozone wisps. opts.huge: bigger, with side bolts and a shock ring; opts.warn (s): a rune
   * marks the spot and crackles first.
   */
  define('volt.strike', (v, at, o) => {
    const i = I(o), s = at.scale, f = at.facing, g = floor(at.pos, 0.02);
    const k = o.huge ? 1.5 : 1, warn = o.warn || 0;
    if (warn > 0) {
      v.decal({ kind: 'rune', pos: vec([g.x, 0, g.z]), radius: 1.3 * s * k, palette: 'volt', life: warn + 0.5, reveal: Math.min(0.3, warn * 0.6), fadeOut: 0.3, spin: 1.3 });
      v.emitter(WARN_CRAWL, { pos: vec([g.x, 0.1, g.z]), dir: [0, 1, 0], scale: k * s, duration: warn });
      v.burst(MOTES, { pos: vec([g.x, 0.4, g.z]), count: 20, scale: 1.5 * s });
    }
    v.schedule(warn, (w) => {
      strike(w, g, s, i, f, k);
      if (o.huge) {
        for (let j = 0; j < 2; j++) w.schedule(0.05 + j * 0.07, (w2) => w2.bolt({ from: vec([g.x + (j ? 1 : -1) * 2, 9, g.z - 1.5]), to: jit(vec([g.x, 0.05, g.z]), 1.4 * s, 0), width: 0.22 * s, branches: 3, strikes: 2, intensity: 0.8 * i }));
        w.distort({ kind: 'shock', pos: vec([g.x, 1, g.z]), radius: [0.4 * s, 4.5 * s], life: 0.5, strength: 0.06 });
      }
    });
  });

  /**
   * chain lightning between at.pos and at.target (position / Object3D; default 3 m forward): a main arc with return
   * strokes and a thinner companion, glowing contacts, gold sparks and arcs at both ends.
   */
  define('volt.chain', (v, at, o) => {
    const i = I(o), s = at.scale;
    const to = at.target != null ? vec(at.target) : at.pos.clone().addScaledVector(at.dir, 3 * s);
    const life = o.life || 0.42;
    v.bolt({ from: at.pos, to, width: 0.26 * s, branches: 3, strikes: o.strikes || 4, interval: [0.04, 0.08], life, leader: 0.02, light: 120 * i, lightRange: 6, intensity: i });
    v.schedule(0.03, (w) => w.bolt({ from: at.pos, to, width: 0.13 * s, branches: 2, strikes: 3, interval: [0.05, 0.09], life: life - 0.04, leader: 0, roughness: 0.32, impact: false, intensity: 0.8 * i }));
    for (const p of [at.pos, to]) {
      v.flare({ kind: 'glow', pos: p, size: 0.8 * s, life, decay: 2, color: WHITE, intensity: 0.7 * i });
      v.burst(GOLD_SPARKS, { pos: p, dir: [0, 1, 0], count: n(18, i), scale: 0.7 * s });
      v.burst(ARCS, { pos: p, count: n(6, i), scale: 0.8 * s });
    }
    v.burst(OZONE, { pos: to, dir: [0, 1, 0], count: 2, scale: 0.6 * s, delay: 0.1 });
  });

  /**
   * lightning dash from at.pos (floor) to opts.to (or opts.length 4 m along facing): the body becomes a streak of
   * lightning (a beam at hip-to-chest height), afterimages of at.target (an Object3D) if given, a bolt racing along
   * the floor, scorch marks, gold sparks and arcs along the path, bursts at both ends. opts.speedlines adds focus lines.
   */
  define('volt.dash', (v, at, o) => {
    const i = I(o), s = at.scale, f = at.facing;
    const a = floor(at.pos, 0);
    const b = o.to != null ? floor(vec(o.to), 0) : vec([a.x + f * (o.length || 4) * s, 0, a.z]);
    const h = 1.1 * s;
    const ah = vec([a.x, h, a.z + 0.1]), bh = vec([b.x, h, b.z + 0.1]);
    if (at.target && at.target.isObject3D) v.afterimage(at.target, { count: o.ghosts || 4, interval: 0.035, life: 0.32, palette: 'volt', drift: [0, 0.1, 0], intensity: i });
    v.burst(KIT.volt.flash, { pos: ah, scale: 0.35 * s, intensity: i });
    v.burst(GOLD_SPARKS, { pos: vec([a.x, 0.1, a.z]), dir: vec([-f, 0.6, 0.2]).normalize(), count: n(26, i), scale: s });
    v.burst(DUST_SMALL, { pos: a, dir: [0, 1, 0], count: 5, scale: s });
    // (a thin streak: a half-metre beam along the whole dash is a white bar across a close camera)
    v.beam({ look: 'volt', from: ah, to: bh, width: 0.3 * s, extend: 0.06, release: 0.14, life: 0.24, flareSize: 0.5, intensity: 0.75 * i });
    v.bolt({ from: vec([a.x, 0.12, a.z]), to: vec([b.x, 0.12, b.z]), width: 0.18 * s, branches: 3, strikes: 2, interval: [0.05, 0.09], detail: 6, roughness: 0.18, life: 0.3, leader: 0.05, impact: false, intensity: i });
    v.burst(ARCS_LINE, { pos: ah, to: bh, count: n(7, i), scale: s, delay: 0.02 });
    v.burst(GOLD_LINE, { pos: vec([a.x, 0.1, a.z]), to: vec([b.x, 0.1, b.z]), dir: [0, 1, 0], count: n(40, i), scale: 0.7 * s, delay: 0.03 });
    const len = a.distanceTo(b);
    for (let x = 0.4 + rng() * 0.5; x < len; x += 0.8 + rng() * 0.9) {
      const p = a.clone().lerp(b, x / len);
      p.z += (rng() - 0.5) * 0.3;
      v.schedule((x / len) * 0.06, (w) => w.decal({ kind: 'scorch', pos: p, radius: (0.3 + rng() * 0.4) * s, life: 2 + rng(), palette: 'volt', magma: 0.5 }));
    }
    v.light({ pos: lightAt(ah.clone().lerp(bh, 0.5), 1.3), color: V.core, intensity: 70 * i, range: 6, duration: 0.3, decay: 'outCubic', flicker: 0.6 });
    v.schedule(0.06, (w) => {
      w.burst(KIT.volt.flash, { pos: bh, scale: 0.32 * s, intensity: i });
      w.burst(ARCS, { pos: bh, count: n(10, i), scale: s });
      w.ring({ look: 'volt', pos: b, radius: [0.1 * s, 1.3 * s], life: 0.3, intensity: 0.8 * i });
      w.burst(DUST_SMALL, { pos: b, dir: [0, 1, 0], count: 5, scale: s });
    });
    if (o.speedlines) v.speedlines({ mode: 'directional', dir: [f, 0], life: 0.3, intensity: 0.6 });
  });

  /** radial lightning burst at at.pos: bolts lash out (some grounding), gold sparks, arcs, a crackling ring, shock, scorch when low */
  function burst(v, p, s, i) {
    // a small white core for two frames; the burst is carried by the bolts, which start OFF the centre (five glowing
    // channels meeting in one point stack into a white ball that hides whoever was struck)
    v.burst(KIT.volt.flash, { pos: p, scale: 0.4 * s, intensity: i });
    v.flare({ kind: 'star', pos: p, size: 1.2 * s, life: 0.1, decay: 3.5, color: V.core, intensity: 0.45 * i, rotation: rng() });
    v.burst(KIT.volt.blot, { pos: p, scale: 0.9 * s });
    v.burst(KIT.volt.ink, { pos: p, count: 8, scale: 0.9 * s });
    v.light({ pos: lightAt(p, 1.4), color: V.core, intensity: 70 * i, range: 7, duration: 0.32, decay: 'outExpo', flicker: 0.6 });
    for (let k = 0; k < 4; k++) {
      const a = (k / 4) * Math.PI * 2 + rng() * 0.8;
      const r = (1.2 + rng()) * s;
      const cz = (rng() - 0.5) * 0.8;
      const from = vec([p.x + Math.cos(a) * 0.3 * s, Math.max(0.03, p.y + Math.sin(a) * 0.26 * s), p.z + cz * 0.25]);
      const to = vec([p.x + Math.cos(a) * r, Math.max(0.03, p.y + Math.sin(a) * r * 0.8), p.z + cz]);
      v.schedule(k * 0.02, (w) => w.bolt({ from, to, width: 0.1 * s, branches: 2, strikes: 2, detail: 5, life: 0.2, leader: 0.015, impact: false, intensity: 0.6 * i }));
    }
    // a crackling disc tilted toward the ground (a camera-facing hoop reads as a bubble)
    // (a thin thunder ring: the filled disc it used to be was a white ellipse over the struck fighter)
    v.ring({ normal: [0.25, 1, 0.35], look: 'volt', pos: p, radius: [0.1 * s, 1.2 * s], width: [0.1 * s, 0.3 * s], fill: 3, life: 0.2, intensity: 0.3 * i });
    v.burst(GOLD_RADIAL, { pos: p, count: n(80, i), scale: s });
    v.burst(ARCS, { pos: p, count: n(16, i), scale: s });
    v.burst(MOTES, { pos: p, count: n(14, i), scale: 1.5 * s });
    v.burst(OZONE, { pos: p, dir: [0, 1, 0], count: 4, scale: 0.8 * s, delay: 0.08 });
    if (p.y < 1.8) {
      const g = floor(p, 0);
      v.decal({ kind: 'scorch', pos: g, radius: 1.1 * s, life: 3, palette: 'volt', magma: 0.6 });
      v.ring({ look: 'volt', pos: g, radius: [0.2 * s, 2.2 * s], life: 0.4, intensity: 0.45 * i });
    }
    v.schedule(0.03, (w) => w.distort({ kind: 'shock', pos: p, radius: [0.2 * s, 2.4 * s], life: 0.38, strength: 0.04 }));
  }
  define('volt.burst', (v, at, o) => burst(v, at.pos, at.scale, I(o)));

  /** javelin impact: a lightning burst plus arcs chaining down into the floor */
  function javelinImpact(v, p, s, i) {
    burst(v, p, s, 0.85 * i);
    for (let k = 0; k < 2; k++) {
      const g = vec([p.x + (rng() - 0.5) * 2.4 * s, 0.03, p.z + (rng() - 0.3) * 1.2 * s]);
      v.schedule(0.04 + k * 0.05, (w) => {
        w.bolt({ from: vec([p.x + (g.x - p.x) * 0.25, p.y * 0.8, p.z]), to: g, width: 0.12 * s, branches: 2, strikes: 2, life: 0.22, leader: 0.02, impact: false, intensity: 0.7 * i });
        w.decal({ kind: 'scorch', pos: g, radius: 0.5 * s, life: 2.5, palette: 'volt', magma: 0.6 });
        w.burst(GOLD_SPARKS, { pos: g, dir: [0, 1, 0], count: n(14, i), scale: 0.6 * s });
      });
    }
  }
  define('volt.javelin.impact', (v, at, o) => javelinImpact(v, at.pos, at.scale, I(o)));

  /**
   * thunder javelin (projectile): a 1.7 m lance of lightning with a white head streak, a crackling ribbon, gold sparks
   * and arcs shed behind, a strobing light. Motion as ember.wave (follow / to / speed 20 m/s for 0.8 s). impact():
   * lightning burst with arcs chaining to the floor.
   */
  define('volt.javelin', (v, at, o) => {
    const i = I(o), s = at.scale, d = at.dir.clone();
    const tail = new THREE.Vector3();
    return launch(v, motion, at, o, {
      speed: 20, life: 0.8,
      body(a) {
        const back = () => tail.copy(a.position).addScaledVector(d, -1.7 * s);
        return [
          v.beam({ look: 'volt', from: back, to: a, width: 0.34 * s, extend: 0.04, release: 0.08, flareSize: 0.9, intensity: i }),
          v.flare({ kind: 'streak', pos: a.position, size: 0.16 * s, aspect: 9, life: 30, dir: d, color: WHITE, intensity: 0.8 * i }).follow(a),
          v.ribbon({ follow: a, width: 0.3 * s, life: 0.2, color: [[0, 3, 2, 7, 0.8], [0.3, 1, 0.5, 2.6, 0.5], [1, 0.1, 0.03, 0.3, 0]], noise: { scale: [3, 1.2], speed: 4, amount: 0.6 } }),
          v.light({ pos: a.position, color: V.core, intensity: 55 * i, range: 5, duration: Infinity, flicker: 0.6, flickerRate: 22 }).follow(a, [0, 0, 0.9]),
          v.emitter(SHOT_SPARKS, { pos: a.position, scale: s }).follow(a),
          v.emitter(SHOT_ARCS, { pos: a.position, scale: s }).follow(a),
        ];
      },
      impact(p) { javelinImpact(v, p, s, i); },
      fizzle(p) { v.burst(ARCS, { pos: p, count: 10, scale: s }); v.burst(GOLD_SPARKS, { pos: p, dir: d, count: 16, scale: 0.6 * s }); },
    });
  });

  /**
   * storm (ultimate scale, ~3.6 s): a rune spreads over the floor and crackles, storm clouds gather overhead, rain
   * streaks lash down, energy is drawn up into the sky, eight bolts with columns of light strike around at.pos in a
   * stutter, then at 2.7 s a huge strike and a lightning burst land at the centre.
   * opts: radius (3.4 m), strikes (8).
   */
  define('volt.storm', (v, at, o) => {
    const i = I(o), s = at.scale, f = at.facing, g = floor(at.pos, 0.02);
    const R = (o.radius || 3.4) * s, N = o.strikes || 8, T = 3.2, climax = 2.7;
    v.decal({ kind: 'rune', pos: vec([g.x, 0, g.z]), radius: R * 1.05, palette: 'volt', life: T + 0.8, reveal: 0.5, spin: 0.8, intensity: i });
    v.emitter(GROUND_CRAWL, { pos: vec([g.x, 0.08, g.z]), dir: [0, 1, 0], scale: s, duration: T });
    v.emitter(RAIN, { pos: vec([g.x, 5.5, g.z]), scale: s, duration: T });
    v.emitter(CLOUD, { pos: vec([g.x, 5.2, g.z - 1.5]), dir: [0, 1, 0], scale: s, duration: T - 0.4 });
    v.emitter(GATHER, { pos: vec([g.x, 6, g.z - 1]), scale: s, intensity: i, duration: T - 0.6 });
    v.light({ pos: vec([g.x, 3, g.z + 1]), color: V.core, intensity: 60 * i, range: 12, duration: T, attack: 0.4, flicker: 0.7, flickerRate: 6 });
    let t = 0.35;
    const gap = (climax - 0.55 - t) / N;
    for (let k = 0; k < N; k++) {
      const a = rng() * Math.PI * 2, r = R * (0.35 + 0.65 * Math.sqrt(rng()));
      const p = vec([g.x + Math.cos(a) * r, 0.02, g.z + Math.sin(a) * r * 0.55]);
      v.schedule(t, (w) => {
        w.bolt({ from: vec([p.x - f * 0.8 + (rng() - 0.5), 9.5, p.z - 2]), to: vec([p.x, 0.05, p.z]), width: 0.36 * s, branches: 4, strikes: 2, light: 170 * i, lightRange: 8, intensity: i });
        w.pillar({ look: 'volt', pos: p, height: 9.5, radius: 0.2 * s, life: 0.4, intensity: 0.7 * i });
        w.burst(KIT.volt.flash, { pos: vec([p.x, 0.3, p.z]), scale: 0.8 * s, intensity: i });
        w.decal({ kind: 'scorch', pos: p, radius: 0.9 * s, life: T, palette: 'volt', magma: 0.7 });
        w.ring({ look: 'volt', pos: p, radius: [0.1 * s, 1.6 * s], life: 0.35, intensity: 0.8 * i });
        w.burst(GOLD_UP, { pos: vec([p.x, 0.1, p.z]), dir: [0, 1, 0], count: n(40, i), scale: 0.8 * s });
        w.burst(OZONE, { pos: vec([p.x, 0.3, p.z]), dir: [0, 1, 0], count: 2, scale: 0.7 * s, delay: 0.1 });
        // sheet lightning: the cloud deck lights up from inside over the strike
        w.flare({ kind: 'flash', pos: vec([p.x, 5.4, p.z - 1.6]), size: 7 * s, life: 0.14, decay: 2, color: V.core, intensity: 0.1 * i, pull: 0 });
      });
      t += gap * (0.6 + rng() * 0.8);
    }
    v.schedule(climax, (w) => {
      strike(w, g, s, i, f, 1.6);
      burst(w, vec([g.x, 1.3 * s, g.z + 0.2]), 1.4 * s, i);
      w.flare({ kind: 'flash', pos: vec([g.x, 5.4, g.z - 1.6]), size: 10 * s, life: 0.2, decay: 2, color: V.core, intensity: 0.14 * i, pull: 0 });
      // aftermath: the charged ground keeps crackling, ions rise, ozone drifts off the scorch
      w.emitter(GROUND_CRAWL, { pos: vec([g.x, 0.08, g.z]), dir: [0, 1, 0], scale: 0.7 * s, duration: 1.3 });
      w.burst(MOTES, { pos: vec([g.x, 0.6, g.z]), count: n(40, i), scale: 3 * s });
      w.burst(OZONE, { pos: vec([g.x, 0.4, g.z]), dir: [0, 1, 0], count: 7, scale: 1.3 * s, delay: 0.2 });
    });
  });
}
