// Frost presets — Iska, the Froststar Oracle. Visual language: fast, precise, airy. Thin crisp crescents and hard
// crystal geometry (shards, spikes), four-point star glints, glitter that hangs in the air and drifts down, snowflakes,
// cold mist that sinks and creeps along the floor (pale, never dark smoke). Motion snaps in, then floats.
// Palette: starlight white -> (1.5, 4, 8) -> cyan (0.3, 1.2, 3) -> white mist.

import { LIB, PALETTE } from '../library.js';
import { heatRamp } from '../util.js';
import { def, key, KIT, arcPoint, arcTangent, floor, vec } from './common.js';
import { launch } from './motion.js';

const F = PALETTE.frost;
const STAR = [6, 8, 10];

// ---- particle definitions (module scope) -------------------------------------------------------------------------

/** four-point star glints that pop, twinkle, hang and drift down */
const GLINTS = def({ tex: 'star4', blend: 'add', count: 16, life: [0.5, 1.4], shape: { type: 'sphere', radius: 0.35 }, emit: 'random', speed: [0.1, 0.9],
  size: [0.05, 0.17, 2.2], gravity: -0.35, drag: 2.5, turbulence: { amp: 0.25, freq: 1.5, speed: 1 }, flicker: { amount: 0.7, rate: 12 }, rotation: [-0.3, 0.3], groundFade: 0.05,
  color: [key(0, STAR, 0), key(0.05, STAR, 1), key(0.4, F.core, 0.9, 0.7), key(1, F.mid, 0, 0.5)] });
/** fine glitter dust */
const GLITTER = def({ ...LIB.glitter, count: 30, color: [key(0, STAR, 0, 0.7), key(0.1, STAR, 1, 0.7), key(1, F.mid, 0, 0.6)] });
/** snowflakes drifting and spinning */
const SNOW = def({ tex: 'snow', blend: 'add', count: 12, life: [0.9, 2.0], shape: { type: 'sphere', radius: 0.5 }, emit: 'random', speed: [0.1, 0.7],
  size: [0.04, 0.1, 1.6], spin: [0.5, 2.2], gravity: -0.45, drag: 2.2, turbulence: { amp: 0.4, freq: 1.2, speed: 0.8 }, groundFade: 0.03,
  color: [[0, 1.6, 2.2, 3, 0], [0.1, 1.6, 2.2, 3, 0.9], [1, 0.5, 0.8, 1.2, 0]] });
/** cold mist: pale puffs that sink and spread (alpha, slightly luminous) */
const MIST = def({ tex: 'smoke', blend: 'alpha', count: 5, life: [0.8, 1.6], shape: { type: 'sphere', radius: 0.25 }, emit: 'random', speed: [0.2, 0.9],
  size: [0.5, 1.1, 1.3], sizeOverLife: 'puff', gravity: -0.35, drag: 2.4, spin: [0.1, 0.4], turbulence: { amp: 0.2, freq: 0.8, speed: 0.6 }, shade: 0.5,
  additive: 0.15, erode: 'erodeLate', erodeSoft: 0.4, groundFade: 0.3,
  color: [[0, 0.9, 1.1, 1.4, 0], [0.1, 0.6, 0.74, 0.9, 0.3], [0.5, 0.5, 0.6, 0.72, 0.2], [1, 0.45, 0.55, 0.65, 0]] });
/** low creeping mist on the floor (radial) */
const MIST_LOW = def({ ...LIB.dustRing, count: 16, speed: [1.5, 4.5], size: [0.7, 1.4, 1.3], life: [1.0, 2.0], lift: 0.08, additive: 0.15, shade: 0.4,
  color: [[0, 0.8, 1.0, 1.3, 0], [0.1, 0.55, 0.68, 0.85, 0.3], [0.6, 0.45, 0.55, 0.68, 0.18], [1, 0.4, 0.5, 0.6, 0]] });
/** crystal shards flung out (additive, crack erosion, bounce) */
const SHARDS = def({ tex: 'shard', blend: 'add', count: 20, life: [0.4, 1.0], shape: { type: 'sphere', radius: 0.2 }, emit: 'radial', spread: 60, lift: 0.4,
  speed: [3, 9, 1.3], size: [0.06, 0.2, 2], spin: [4, 14], gravity: -11, drag: 0.8, collide: 'ground', bounce: 0.35, erode: 'erodeLate', erodeChannel: 'cracks',
  color: [key(0, STAR, 1, 1.2), key(0.12, F.core, 1, 0.6), key(0.6, F.mid, 0.9, 0.8), key(1, F.tail, 0)] });
/** directional shards spraying along a cut */
const SHARD_SPRAY = def({ ...SHARDS, emit: 'axis', spread: 22, speed: [4, 11, 1.3], count: 12 });
/** ice sparks: stretched, cold, light gravity */
const ICE_SPARKS = def({ ...LIB.sparks, count: 40, gravity: -5, drag: 3, life: [0.2, 0.7, 1.5], color: heatRamp(STAR, F.core, F.mid, { flash: 1.2 }) });
const ICE_SPARKS_RADIAL = def({ ...ICE_SPARKS, count: 80, spread: 180, emit: 'radial', speed: [3, 12, 1.4] });

// trail: thin, bright, crisp; short life
const TRAIL = {
  life: 0.17, color: [[0, 3, 5.5, 9, 0.9], [0.15, 0.8, 2.2, 4.5, 0.65], [0.5, 0.25, 0.7, 1.6, 0.3], [1, 0.1, 0.2, 0.4, 0]],
  edge: [6, 9, 12], edgeWidth: 0.05, gradient: 0.8, fadeBase: 0.65, width: [[0, 1], [0.3, 0.6], [1, 0.06]],
  erode: [[0, 0], [0.25, 0.05], [1, 0.95]], erodeSoft: 0.2, noise: { scale: [2.4, 0.9], speed: 0.6, amount: 0.35 }, distort: 0.012,
};
const TRAIL_GLINTS = def({ ...GLINTS, count: 0, perMeter: 9, shape: { type: 'point' }, speed: [0.05, 0.4], inherit: 0.08 });
const TRAIL_SNOW = def({ ...SNOW, count: 0, perMeter: 5, shape: { type: 'point' }, inherit: 0.08 });
const TRAIL_MIST = def({ ...MIST, count: 0, perMeter: 1.6, shape: { type: 'point' }, size: [0.3, 0.6], life: [0.6, 1.1], inherit: 0.04 });

// aura: snowfall from above the head, glints orbiting the body, mist pooling at the feet
const SNOWFALL = def({ ...SNOW, count: 0, rate: 20, shape: { type: 'disc', radius: 0.9 }, emit: 'axis', dir: [0, -1, 0], spread: 20, speed: [0.2, 0.5], life: [1.8, 2.6] });
const ORBIT = def({ ...GLINTS, count: 0, rate: 22, shape: { type: 'sphere', radius: 0.75, inner: 0.7 }, emit: 'tangent', spread: 10, speed: [0.4, 0.9], swirl: 1.4, gravity: -0.15, life: [0.8, 1.6], size: [0.07, 0.2, 2] });
const POOL = def({ ...MIST_LOW, count: 0, rate: 6, shape: { type: 'ring', radius: 0.25, thickness: 0.2 }, speed: [0.3, 1.0], life: [1.6, 2.6], size: [0.8, 1.4], sizeOverLife: [[0, 0.4], [1, 1.3]], additive: 0.35,
  color: [[0, 1.0, 1.3, 1.7, 0], [0.15, 0.7, 0.88, 1.1, 0.22], [0.6, 0.6, 0.72, 0.88, 0.14], [1, 0.5, 0.6, 0.72, 0]] });

// projectile body
const SHOT_GLINTS = def({ ...TRAIL_GLINTS, perMeter: 7 });

// blizzard
const GUST = def({ tex: 'streak', blend: 'add', count: 0, rate: 300, life: [0.3, 0.7], shape: { type: 'box', size: [18, 5, 7] }, emit: 'axis', spread: 6,
  speed: [10, 16], size: [0.04, 0.09, 1.5], stretch: 0.08, maxStretch: 2.2, rotation: 0, gravity: -2, groundFade: 0.1,
  color: [[0, 1.6, 2.1, 2.8, 0], [0.15, 1.6, 2.1, 2.8, 0.75], [1, 0.6, 0.8, 1.1, 0]] });
const FLAKES = def({ ...SNOW, count: 0, rate: 80, shape: { type: 'box', size: [18, 5, 7] }, emit: 'axis', spread: 25, speed: [3, 6], size: [0.08, 0.2, 1.6], life: [1.0, 2.0] });
const WALL = def({ ...MIST, count: 0, perMeter: 4, shape: { type: 'box', size: [0.8, 1.4, 4] }, emit: 'axis', spread: 30, speed: [2, 4.5], size: [1.4, 2.4, 1.3], life: [0.8, 1.5], gravity: -0.3,
  additive: [[0, 0.6], [0.5, 0.3], [1, 0]], erode: [[0, 0.15], [0.5, 0.3], [1, 1]],
  color: [[0, 1.4, 1.8, 2.4, 0], [0.1, 0.9, 1.1, 1.4, 0.26], [0.5, 0.6, 0.72, 0.88, 0.16], [1, 0.5, 0.6, 0.72, 0]] });
const WALL_GLINTS = def({ ...GLINTS, count: 0, perMeter: 14, shape: { type: 'box', size: [0.8, 2.6, 4] }, speed: [1, 3], emit: 'axis', spread: 40 });

/**
 * Register the frost presets.
 * @param {object} vfx
 * @param {object} P  preset helpers ({ define, rng, motion })
 */
export function defineFrost(vfx, P) {
  const { define, rng, motion } = P;
  const I = (o) => (o.intensity != null ? o.intensity : 1);
  const n = (c, i) => Math.max(1, Math.round(c * i));

  /** crescent(s), starlight edge, glints and snow hanging in the wake, a star glint at the tip, mist sinking below */
  function slash(v, at, o, heavy) {
    const i = I(o), s = at.scale, f = at.facing;
    const R = (o.radius != null ? o.radius : heavy ? 1.5 : 1.25) * s;
    const W = (o.width != null ? o.width : heavy ? 0.46 : 0.38) * s;
    const arc = o.arc || (heavy ? [-160, 40] : [-150, 30]);
    const sweep = o.sweep != null ? o.sweep : heavy ? 0.065 : 0.05;
    const plane = { normal: o.normal || [0, -0.3, 1], forward: o.forward || [1, 0, 0], roll: o.roll || 0, facing: f };
    const sgn = Math.sign(arc[1] - arc[0]);
    const cut = (w, r, wd, k, ar) => {
      w.slash({ look: 'ice', pos: at.pos, ...plane, arc: ar, radius: r, width: wd, sweep, life: heavy ? 0.6 : 0.45, distort: 0.02, intensity: k * i });
      w.slash({ look: 'razor', palette: 'frost', core: STAR, pos: at.pos, ...plane, arc: ar, radius: r * 0.995, width: 0.06 * s, sweep, life: 0.16, intensity: 1.4 * k * i });
      w.slash({ look: 'razor', palette: 'frost', pos: at.pos, ...plane, arc: ar, radius: r * 1.02, width: wd * 1.9, sweep, life: 0.24, intensity: 0.35 * k * i, alpha: 0.6 });
    };
    cut(v, R, W, 1, arc);
    const twin = heavy || o.twin;
    if (twin) v.schedule(heavy ? 0.04 : 0.07, (w) => cut(w, R * 0.86, W * 0.75, 0.85, heavy ? [arc[0] + 12 * sgn, arc[1] + 10 * sgn] : [arc[1], arc[0]]));
    const end = arcPoint(at.pos, plane, arc[1], R);
    const endT = arcTangent(plane, arc[1], sgn);
    v.schedule(sweep, (w) => {
      w.flare({ kind: 'star', pos: end, size: (heavy ? 1.3 : 0.85) * s, life: heavy ? 0.24 : 0.18, decay: 2.2, color: STAR, intensity: 0.8 * i, rotation: 0.25 });
      w.burst(ICE_SPARKS, { pos: end, dir: endT, count: n(heavy ? 26 : 12, i), scale: 0.8 * s });
      if (heavy) {
        w.burst(SHARD_SPRAY, { pos: end, dir: endT, count: n(14, i), scale: s });
        w.flare({ kind: 'ring', pos: end, size: [0.1 * s, 0.7 * s], life: 0.16, decay: 2, color: F.core, intensity: 0.3 * i });
      }
    });
    const mid = arcPoint(at.pos, plane, (arc[0] + arc[1]) / 2, R);
    v.light({ pos: vec([mid.x, mid.y, mid.z + 1.0]), color: F.core, intensity: (heavy ? 50 : 30) * i, range: 5.5, duration: heavy ? 0.4 : 0.28, decay: 'outCubic' });
    const marks = heavy ? [0.15, 0.35, 0.55, 0.75, 0.95] : [0.25, 0.5, 0.75, 1];
    for (const u of marks) {
      const a = arc[0] + (arc[1] - arc[0]) * u;
      const p = arcPoint(at.pos, plane, a, R * (0.82 + rng() * 0.16));
      v.burst(GLINTS, { pos: p, count: n(heavy ? 7 : 5, i), scale: 0.75 * s, delay: sweep * u });
      v.burst(SNOW, { pos: p, count: heavy ? 3 : 2, scale: 0.5 * s, delay: sweep * u });
    }
    const low = arcPoint(at.pos, plane, arc[0] + (arc[1] - arc[0]) * 0.3, R * 0.8);
    v.burst(MIST, { pos: low, count: heavy ? 4 : 2, scale: (heavy ? 0.9 : 0.6) * s, delay: 0.04 });
    if (heavy) {
      v.debris({ kind: 'ice', pos: end, dir: endT, count: n(5, i), speed: [2, 5], spread: 30, size: [0.04, 0.1, 2], scale: s });
      if (Math.min(end.y, low.y) < 0.6) v.decal({ kind: 'frost', pos: floor(low.y < end.y ? low : end, 0), radius: 1.2 * s, reveal: 0.25, life: 3 });
    }
  }

  /** quick crystalline crescent with a starlight edge; glints and snow hang in its wake; a star glints at the tip. opts.twin: a second, mirrored blade */
  define('frost.slash', (v, at, o) => slash(v, at, o, false));
  /** two concentric crescents (both blades), shard spray and a star ring off the tip, ice chips, frost on the floor when low */
  define('frost.slash.heavy', (v, at, o) => slash(v, at, o, true));

  /** weapon trail: thin starlight ribbon with a hard white edge, glints, snow and a breath of mist from the tip. opts: a, b, duration, life */
  define('frost.trail', (v, at, o) => {
    const tip = o.b || at.target || at.pos;
    const hs = [v.trail({ ...TRAIL, a: o.a || tip, b: tip, life: o.life != null ? o.life : TRAIL.life, intensity: I(o) })];
    for (const d of [TRAIL_GLINTS, TRAIL_SNOW, TRAIL_MIST]) hs.push(v.emitter(d, { pos: vec(tip), scale: at.scale }).follow(tip));
    if (o.duration) v.schedule(o.duration, () => { for (const h of hs) h.stop(); });
  });

  /**
   * frost aura (loop): slow snowfall from above the head, star glints orbiting the body, cold mist pooling and creeping
   * from the feet over a frost patch, a cool light. Follows at.target / opts.follow (feet) or stays at at.pos.
   */
  define('frost.aura', (v, at, o) => {
    const i = I(o), s = at.scale, dur = o.duration || 0;
    const follow = o.follow || (at.target && at.target.isObject3D ? at.target : null);
    const em = (d, off) => { const h = v.emitter(d, { pos: at.pos, scale: s, intensity: i, duration: dur }); if (follow) h.follow(follow, off); else h.pos.add(vec(off)); return h; };
    em(SNOWFALL, [0, 2.3 * s, 0]);
    em(ORBIT, [0, 1.1 * s, 0]);
    em(POOL, [0, 0.03, 0]);
    const halo = v.flare({ kind: 'glow', pos: vec([at.pos.x, at.pos.y + s, at.pos.z]), size: 1.5 * s, life: dur || 1e5, attack: 0.3, decay: 0.5, color: F.mid, intensity: 0.22 * i, pull: 0 });
    const lt = v.light({ pos: vec([at.pos.x, at.pos.y + s, at.pos.z + 1.2]), color: F.core, intensity: 16 * i, range: 4, duration: dur || Infinity, attack: 0.2 });
    const dc = v.decal({ kind: 'frost', pos: floor(at.pos, 0), radius: 1.2 * s, reveal: 0.5, life: dur || 1e5 });
    if (follow) { lt.follow(follow, [0, s, 1.2]); dc.follow(follow, [0, 0, 0]); halo.follow(follow, [0, s, 0]); }
  });

  /**
   * crystal procession: a line of ice spikes races forward from at.pos (floor) along at.facing, each larger than the
   * last, ending in a huge cluster; frost spreads, mist rolls and glints rise along the line; a cold light runs with
   * the front. The spikes hold, then shatter. opts: length (7 m), count (8), hold (0.6 s).
   */
  define('frost.spikes', (v, at, o) => {
    const i = I(o), s = at.scale, f = at.facing, g = floor(at.pos, 0);
    const len = (o.length || 7) * s, cnt = o.count || 8, hold = o.hold != null ? o.hold : 0.6;
    const stag = 0.045, T = stag * cnt;
    v.spikes({ kind: 'ice', pattern: 'line', pos: g, dir: [f, 0, 0.04], length: len * 0.88, count: cnt, stagger: stag, hold: hold + 0.1, height: [0.55 * s, 1.5 * s], grow: [0.55, 1.2], width: 0.22 });
    const endP = vec([g.x + f * len, 0, g.z]);
    v.schedule(T, (w) => {
      w.spikes({ kind: 'ice', pattern: 'cluster', pos: endP, radius: 0.5 * s, count: 5, height: [1.4 * s, 2.5 * s], width: 0.24, stagger: 0.02, hold });
      w.ring({ look: 'frost', pos: endP, radius: [0.3 * s, 2.4 * s], life: 0.7, distort: 0.03, intensity: i });
      w.flare({ kind: 'star', pos: vec([endP.x, 1.6 * s, endP.z + 0.3]), size: 1.8 * s, life: 0.22, decay: 2.5, color: STAR, intensity: 0.6 * i, rotation: 0.2 });
      w.burst(MIST_LOW, { pos: endP, dir: [0, 1, 0], count: n(14, i), scale: 1.2 * s });
      w.burst(GLINTS, { pos: vec([endP.x, 1.2 * s, endP.z]), count: n(30, i), scale: 2 * s });
    });
    const m = motion.start({ pos: vec([g.x, 0.9, g.z + 1.1]), to: vec([endP.x, 0.9, endP.z + 1.1]), dur: T, realtime: v.realtime });
    v.light({ pos: m.pos, color: F.core, intensity: 70 * i, range: 7, duration: T + hold + 0.3, decay: 'outQuad' }).follow(m.obj);
    for (let k = 0; k * 1.0 < len; k++) {
      const x = k * 1.0 + 0.5, t = (x / len) * T;
      const p = vec([g.x + f * x, 0, g.z]);
      v.schedule(t, (w) => {
        w.decal({ kind: 'frost', pos: p, radius: (0.8 + 0.6 * (x / len)) * s, reveal: 0.25, life: hold + 3 });
        w.burst(MIST_LOW, { pos: p, dir: [0, 1, 0], count: n(3, i), scale: 0.8 * s });
        w.burst(GLINTS, { pos: vec([p.x, 0.6, p.z]), count: n(5, i), scale: s });
      });
    }
  });

  /** shard impact: the crystal shatters into shards and glitter with a star flash, a ring and frost on the floor */
  function shardImpact(v, p, d, s, i) {
    v.burst(KIT.frost.flash, { pos: p, scale: 0.42 * s, intensity: i });
    v.flare({ kind: 'star', pos: p, size: 1.4 * s, life: 0.2, decay: 2.5, color: STAR, intensity: 0.8 * i, rotation: rng() });
    v.light({ pos: vec([p.x, p.y, p.z + 0.8]), color: F.core, intensity: 60 * i, range: 5, duration: 0.3 });
    v.ring({ normal: d, look: 'frost', pos: p, radius: [0.1 * s, 1.2 * s], width: [0.2 * s, 0.35 * s], life: 0.35, intensity: 0.8 * i });
    v.burst(SHARDS, { pos: p, dir: d, count: n(22, i), scale: s });
    v.burst(ICE_SPARKS, { pos: p, dir: d, count: n(24, i), scale: 0.8 * s });
    v.burst(GLINTS, { pos: p, count: n(22, i), scale: s });
    v.burst(MIST, { pos: p, count: 3, scale: 0.7 * s });
    v.debris({ kind: 'ice', pos: p, dir: d, count: n(5, i), speed: [1.5, 4], spread: 50, size: [0.04, 0.1, 2], scale: s });
    if (p.y < 2.2) v.decal({ kind: 'frost', pos: floor(p, 0), radius: 1.0 * s, reveal: 0.3, life: 2.5 });
    v.schedule(0.03, (w) => w.distort({ kind: 'shock', pos: p, radius: [0.1 * s, 1.4 * s], life: 0.3, strength: 0.035 }));
  }
  define('frost.shard.impact', (v, at, o) => shardImpact(v, at.pos, at.dir, at.scale, I(o)));

  /**
   * star shard (projectile): a crystal lance of starlight with a white-hot star at its head, a thin frost ribbon,
   * glints and mist shed behind. Motion as ember.wave (follow / to / speed 14 m/s for 1 s). impact(): shatters.
   */
  define('frost.shard', (v, at, o) => {
    const i = I(o), s = at.scale, d = at.dir.clone();
    const tail = vec([0, 0, 0]);
    return launch(v, motion, at, o, {
      speed: 14, life: 1,
      body(a) {
        const back = () => tail.copy(a.position).addScaledVector(d, -0.75 * s);
        const fx = Math.sign(d.x) || 1;
        return [
          v.slash({ look: 'ice', palette: 'frost', core: STAR, follow: a, offset: [-fx * 0.3 * s, 0, 0], normal: [0, 0, 1], forward: [1, 0, 0], facing: fx, arc: [-62, 62], radius: 0.34 * s, width: 0.2 * s, sweep: 0.03, life: 30, heat: 0.004, intensity: i }),
          v.beam({ look: 'frost', from: back, to: a, width: 0.2 * s, coreWidth: 0.3, extend: 0.03, release: 0.08, flareSize: 0.5, intensity: 0.85 * i }),
          v.flare({ kind: 'star', pos: a.position, size: 0.75 * s, life: 30, color: STAR, intensity: 0.75 * i, rotation: 0.2 }).follow(a),
          v.ribbon({ follow: a, width: 0.12 * s, life: 0.24, color: [[0, 3, 5, 8, 0.85], [0.3, 0.6, 1.6, 3.5, 0.5], [1, 0.1, 0.25, 0.5, 0]] }),
          v.light({ pos: a.position, color: F.core, intensity: 40 * i, range: 4, duration: Infinity }).follow(a, [0, 0, 0.8]),
          v.emitter(SHOT_GLINTS, { pos: a.position, scale: s }).follow(a),
        ];
      },
      impact(p, dd) { shardImpact(v, p, dd, s, i); },
      fizzle(p) { v.burst(GLINTS, { pos: p, count: 14, scale: s }); v.burst(SHARDS, { pos: p, dir: d, count: 6, scale: 0.6 * s }); },
    });
  });

  /**
   * nova (radial freeze) at a floor point: a frost rune snaps open, a crystalline ring and frost sweep outward, a
   * ring of ice spikes erupts around the target and (opts.encase, default true) a crystal cluster encases it, mist
   * rolls out low, glitter fills the air.
   */
  define('frost.nova', (v, at, o) => {
    const i = I(o), s = at.scale, g = floor(at.pos, 0);
    v.decal({ kind: 'rune', pos: g, radius: 2.4 * s, palette: 'frost', life: 1.6, reveal: 0.15, fadeOut: 0.5, spin: 1.6, intensity: i });
    v.decal({ kind: 'frost', pos: g, radius: 3.4 * s, reveal: 0.35, life: 5 });
    v.ring({ look: 'frost', pos: g, radius: [0.3 * s, 4.2 * s], life: 0.85, distort: 0.035, intensity: i });
    v.ring({ look: 'shock', palette: 'frost', pos: vec([g.x, 0.05, g.z]), radius: [0.2 * s, 3.2 * s], life: 0.4, intensity: 0.7 * i });
    v.light({ pos: vec([g.x, 1.4, g.z + 1.4]), color: F.core, intensity: 110 * i, range: 9, duration: 1.1, decay: 'outCubic' });
    v.burst(KIT.frost.flash, { pos: vec([g.x, 1.0 * s, g.z + 0.2]), scale: 0.8 * s, intensity: i });
    v.flare({ kind: 'star', pos: vec([g.x, 1.1 * s, g.z + 0.3]), size: 2.2 * s, life: 0.26, decay: 2.5, color: STAR, intensity: 0.7 * i, rotation: 0.15 });
    v.schedule(0.05, (w) => {
      w.spikes({ kind: 'ice', pattern: 'ring', pos: g, radius: 1.25 * s, count: 12, height: [0.5 * s, 1.15 * s], tilt: 28, stagger: 0.012, hold: 1.1 });
      if (o.encase !== false) w.spikes({ kind: 'ice', pattern: 'cluster', pos: g, radius: 0.32 * s, count: 6, height: [1.3 * s, 2.3 * s], width: 0.3, tilt: 14, stagger: 0.02, hold: 1.2 });
      w.burst(MIST_LOW, { pos: g, dir: [0, 1, 0], count: n(20, i), scale: 1.3 * s });
      w.burst(ICE_SPARKS_RADIAL, { pos: vec([g.x, 0.6 * s, g.z]), count: n(60, i), scale: s });
      w.burst(GLINTS, { pos: vec([g.x, 1.3 * s, g.z]), count: n(50, i), scale: 2.4 * s });
      w.burst(SNOW, { pos: vec([g.x, 1.6 * s, g.z]), count: n(26, i), scale: 2.2 * s });
      w.distort({ kind: 'shock', pos: g, normal: [0, 1, 0], radius: [0.3 * s, 4 * s], life: 0.55, strength: 0.04 });
    });
  });

  /**
   * shatter (big): a crystal bursts at at.pos — star flash, shards and lit ice / crystal chunks flying and bouncing,
   * a crystalline ring, sparkling glitter and snow that hang and fall, mist, frost on the floor below.
   */
  define('frost.shatter', (v, at, o) => {
    const i = I(o), s = at.scale, p = at.pos, d = at.dir;
    v.burst(KIT.frost.flash, { pos: p, scale: 0.8 * s, intensity: i });
    v.flare({ kind: 'flash', pos: p, size: 2.4 * s, life: 0.08, decay: 3, color: F.core, intensity: 0.15 * i });
    v.flare({ kind: 'star', pos: p, size: 2.3 * s, life: 0.26, decay: 2.5, color: STAR, intensity: 0.85 * i, rotation: 0.35 });
    v.light({ pos: vec([p.x, p.y, p.z + 1.1]), color: F.core, intensity: 140 * i, range: 8, duration: 0.6, decay: 'outCubic' });
    v.burst(SHARDS, { pos: p, dir: d, count: n(80, i), scale: 1.5 * s });
    v.burst(ICE_SPARKS_RADIAL, { pos: p, count: n(70, i), scale: 1.1 * s });
    v.burst(GLINTS, { pos: p, count: n(60, i), scale: 2 * s });
    v.burst(GLITTER, { pos: p, count: n(40, i), scale: 2 * s });
    v.burst(SNOW, { pos: p, count: n(24, i), scale: 2 * s });
    v.burst(MIST, { pos: p, count: 8, scale: 1.4 * s });
    v.debris({ kind: 'ice', pos: p, dir: [0, 1, 0], count: n(18, i), speed: [2, 7, 1.3], spread: 75, size: [0.05, 0.2, 2], scale: s });
    v.debris({ kind: 'crystal', pos: p, dir: [0, 1, 0], count: n(7, i), speed: [2, 6], spread: 70, size: [0.06, 0.16, 2], scale: s });
    if (p.y < 2.5) {
      const g = floor(p, 0);
      v.decal({ kind: 'frost', pos: g, radius: 2.4 * s, reveal: 0.3, life: 4 });
      v.ring({ look: 'frost', pos: g, radius: [0.3 * s, 3 * s], life: 0.7, intensity: 0.8 * i });
      v.burst(MIST_LOW, { pos: g, dir: [0, 1, 0], count: n(14, i), scale: 1.2 * s });
    }
    v.schedule(0.04, (w) => w.distort({ kind: 'shock', pos: p, radius: [0.3 * s, 3.4 * s], life: 0.5, strength: 0.055 }));
  });

  /**
   * blizzard (ultimate scale, ~3.4 s): a tall crescent wall of ice light rolls forward from at.pos along at.facing
   * (opts.length 12 m in opts.travel 1.6 s) trailing luminous mist, rimes the floor and raises a growing field of
   * crystal clusters, while a gale of snow streaks and flakes blows across the arena; the crystals shatter at the end.
   */
  define('frost.blizzard', (v, at, o) => {
    const i = I(o), s = at.scale, f = at.facing, g = floor(at.pos, 0);
    const L = (o.length || 12) * s, travel = o.travel || 1.6, T = o.duration || 3.2;
    const mid = vec([g.x + f * L * 0.4, 2.3, g.z]);
    const gust = vec([f, -0.12, 0.05]).normalize();
    v.flare({ kind: 'star', pos: vec([g.x, 1.3, g.z + 0.3]), size: 2.4 * s, life: 0.35, decay: 2.5, color: STAR, intensity: 0.8 * i, rotation: 0.2 });
    v.ring({ look: 'frost', pos: g, radius: [0.3 * s, 3.2 * s], life: 0.7, distort: 0.03, intensity: i });
    v.emitter(GUST, { pos: mid, dir: gust, scale: s, intensity: i, duration: T });
    v.emitter(FLAKES, { pos: mid, dir: gust, scale: s, duration: T });
    let next = 0.8, spike = 1.2;
    const m = motion.start({
      pos: vec([g.x + f * 0.6, 0, g.z]), to: vec([g.x + f * L, 0, g.z]), dur: travel, ease: 'outQuad', realtime: v.realtime,
      onStep(r) {
        if (r.dist < next) return;
        next += 1.2 * s;
        const p = r.obj.position.clone();
        v.decal({ kind: 'frost', pos: p, radius: 1.7 * s, reveal: 0.3, life: T + 1.5 });
        v.burst(MIST_LOW, { pos: p, dir: [0, 1, 0], count: n(5, i), scale: 1.2 * s });
        if (r.dist >= spike) {
          spike += (1.1 + rng() * 0.6) * s;
          const k = Math.min(1, r.dist / L);
          v.spikes({ kind: 'ice', pattern: 'cluster', pos: vec([p.x, 0, p.z + (rng() - 0.5) * 1.6]), radius: 0.45 * s, count: 4, height: [(0.5 + 0.5 * k) * s, (1.0 + 1.4 * k + rng() * 0.5) * s], stagger: 0.02, hold: Math.max(0.3, T - travel * k) });
          v.burst(GLINTS, { pos: vec([p.x, 0.8, p.z]), count: n(12, i), scale: 1.4 * s });
        }
      },
    });
    const a = m.obj;
    // the front: a tall crescent of ice light rolling forward (Iska's crescent, stood on end), mist and glints behind it
    const R = 1.7 * s, sl = { normal: [0, 0, 1], forward: [1, 0, 0], facing: f, follow: a, arc: [-76, 76], sweep: 0.08, life: travel + 0.25 };
    v.slash({ look: 'ice', ...sl, offset: [-f * R * 0.9, R * 0.92, 0], radius: R, width: 1.1 * s, heat: 0.2, intensity: 0.8 * i, distort: 0.03 });
    v.slash({ look: 'razor', palette: 'frost', core: STAR, ...sl, offset: [-f * R * 0.9, R * 0.92, 0.05], radius: R * 0.995, width: 0.12 * s, heat: 0.1, intensity: 1.2 * i });
    v.emitter(WALL, { pos: a.position, dir: gust, scale: s, intensity: i, duration: travel }).follow(a, [-f * 0.8 * s, 0.7 * s, 0]);
    v.emitter(WALL_GLINTS, { pos: a.position, scale: s, duration: travel }).follow(a, [0, 1.2 * s, 0]);
    v.light({ pos: a.position, color: F.core, intensity: 120 * i, range: 9, duration: travel + 0.4, decay: 'outQuad' }).follow(a, [0, 1.6, 1.4]);
    v.distort({ kind: 'heat', pos: a.position, radius: 1.6 * s, strength: 0.015, life: travel, attack: 0.1 }).follow(a, [0, 1.3 * s, 0]);
    v.schedule(travel, (w) => {
      const e = vec([g.x + f * L, 1.4 * s, g.z]);
      w.burst(GLITTER, { pos: vec([g.x + f * L * 0.6, 1.5, g.z]), count: n(70, i), scale: 5 * s });
      w.flare({ kind: 'star', pos: e, size: 2.2 * s, life: 0.25, decay: 2.5, color: STAR, intensity: 0.7 * i, rotation: 0.3 });
      w.burst(SHARDS, { pos: e, dir: vec([f, 0.4, 0.2]).normalize(), count: n(30, i), scale: 1.4 * s });
      w.burst(MIST_LOW, { pos: floor(e, 0), dir: [0, 1, 0], count: n(10, i), scale: 1.5 * s });
    });
  });

  /**
   * starfall: star lances fall from the sky onto at.pos (floor). Each: a star kindles high above, a lance of
   * starlight streaks down, then a crystal stabs the floor with a frost ring, shards, glints and a flash.
   * opts: count (1), radius (scatter, 0.9 m), interval (0.08 s), height (9 m).
   */
  define('frost.starfall', (v, at, o) => {
    const i = I(o), s = at.scale, f = at.facing, cnt = o.count || 1;
    const H = (o.height || 9) * s, R = (o.radius != null ? o.radius : 1.6) * s, iv = o.interval != null ? o.interval : 0.08;
    for (let k = 0; k < cnt; k++) {
      const a = rng() * Math.PI * 2, r = cnt > 1 ? R * Math.sqrt(rng()) : 0;
      const g = vec([at.pos.x + Math.cos(a) * r, 0, at.pos.z + Math.sin(a) * r * 0.6]);
      const from = vec([g.x - f * H * (0.15 + rng() * 0.25) + (rng() - 0.5) * 3, H * (0.85 + rng() * 0.3), g.z - H * (0.08 + rng() * 0.15)]);
      v.schedule(k * iv, (w) => {
        w.flare({ kind: 'star', pos: from, size: 1.4 * s, life: 0.24, attack: 0.06, decay: 3, color: STAR, intensity: 0.9 * i, rotation: rng() });
        w.schedule(0.08, (w2) => w2.beam({ look: 'frost', palette: 'frost', core: STAR, from, to: g, width: 0.17 * s, coreWidth: 0.25, extend: 0.07, release: 0.16, life: 0.3, flareSize: 0.5, intensity: 0.85 * i }));
        w.schedule(0.15, (w2) => {
          w2.burst(KIT.frost.flash, { pos: vec([g.x, 0.3, g.z]), scale: 0.5 * s, intensity: i });
          w2.light({ pos: vec([g.x, 0.9, g.z + 1.0]), color: F.core, intensity: 70 * i, range: 6, duration: 0.3 });
          w2.ring({ look: 'frost', pos: g, radius: [0.1 * s, 1.4 * s], life: 0.5, intensity: 0.6 * i });
          w2.decal({ kind: 'frost', pos: g, radius: 0.9 * s, reveal: 0.15, life: 2.5 });
          w2.spikes({ kind: 'ice', pattern: 'cluster', pos: g, radius: 0.08, count: 1, height: [0.8 * s, 1.0 * s], width: 0.18, tilt: 16, stagger: 0, rise: 0.04, hold: 0.7 });
          w2.burst(SHARDS, { pos: vec([g.x, 0.15, g.z]), dir: [0, 1, 0], count: n(14, i), scale: 0.8 * s });
          w2.burst(GLINTS, { pos: vec([g.x, 0.5, g.z]), count: n(14, i), scale: s });
          w2.burst(MIST_LOW, { pos: g, dir: [0, 1, 0], count: 4, scale: 0.7 * s });
          w2.distort({ kind: 'shock', pos: g, normal: [0, 1, 0], radius: [0.1 * s, 1.6 * s], life: 0.35, strength: 0.03 });
        });
      });
    }
  });
}
