// ISKA 이스카 — signature frost effects (registered once by present.setup, before vfx.prewarm()).
// Visual language (MOVES.md): fast, precise, airy. Thin starlight crescents, hard crystal geometry, four-point star
// glints that hang and drift down, glitter, snow, and pale cold mist that sinks along the floor (never dark smoke).
// Palette: starlight white -> (1.5, 4, 8) -> cyan (0.3, 1.2, 3) -> white mist. Large areas stay at 0.6-3 HDR, only
// pin-point heads / 1-3 frame flashes go hotter, so the bloom never washes the fighters out.
//
// Every particle definition is created here at module scope and registered by name in setup (vfx.particleDef), so
// nothing is hashed or uploaded mid-fight. Presets only pass per-call values (pos, dir, count, scale, delay).

import { LIB, PALETTE } from '../../vfx/library.js';
import { heatRamp } from '../../vfx/util.js';
import { arcPoint, arcTangent } from '../../vfx/presets/common.js';

export const F = PALETTE.frost;
/** starlight white (hot heads, star glints) */
export const STAR = [6, 8, 10];
const key = (t, c, a = 1, k = 1) => [t, c[0] * k, c[1] * k, c[2] * k, a];
const n = (c, i = 1) => Math.max(1, Math.round(c * i));

// ---- particle definitions ------------------------------------------------------------------------------------------
export const D = {
  /** four-point star glints that pop, twinkle, hang and drift down */
  glint: { nearFade: 0.9, tex: 'star4', blend: 'add', count: 14, life: [0.5, 1.3], shape: { type: 'sphere', radius: 0.3 }, emit: 'random', speed: [0.1, 0.9],
    size: [0.05, 0.16, 2.2], gravity: -0.35, drag: 2.5, turbulence: { amp: 0.25, freq: 1.5, speed: 1 }, flicker: { amount: 0.7, rate: 12 }, rotation: [-0.3, 0.3], groundFade: 0.05,
    color: [key(0, STAR, 0), key(0.05, STAR, 1), key(0.4, F.core, 0.9, 0.7), key(1, F.mid, 0, 0.5)] },
  /** fine glitter dust that hangs */
  glitter: { ...LIB.glitter, count: 24, color: [key(0, STAR, 0, 0.6), key(0.1, STAR, 1, 0.6), key(1, F.mid, 0, 0.6)] },
  /** snowflakes drifting and spinning */
  snow: { nearFade: 0.9, tex: 'snow', blend: 'add', count: 10, life: [0.9, 2.0], shape: { type: 'sphere', radius: 0.5 }, emit: 'random', speed: [0.1, 0.7],
    size: [0.04, 0.1, 1.6], spin: [0.5, 2.2], gravity: -0.45, drag: 2.2, turbulence: { amp: 0.4, freq: 1.2, speed: 0.8 }, groundFade: 0.03,
    color: [[0, 1.6, 2.2, 3, 0], [0.1, 1.6, 2.2, 3, 0.9], [1, 0.5, 0.8, 1.2, 0]] },
  /** pale cold mist: puffs that sink and spread (alpha, faintly luminous) */
  mist: { tex: 'smoke', blend: 'alpha', count: 4, life: [0.8, 1.6], shape: { type: 'sphere', radius: 0.25 }, emit: 'random', speed: [0.2, 0.9],
    size: [0.5, 1.1, 1.3], sizeOverLife: 'puff', gravity: -0.35, drag: 2.4, spin: [0.1, 0.4], turbulence: { amp: 0.2, freq: 0.8, speed: 0.6 }, shade: 0.5,
    additive: 0.15, erode: 'erodeLate', erodeSoft: 0.4, groundFade: 0.3,
    color: [[0, 0.9, 1.1, 1.4, 0], [0.1, 0.6, 0.74, 0.9, 0.28], [0.5, 0.5, 0.6, 0.72, 0.18], [1, 0.45, 0.55, 0.65, 0]] },
  /** low creeping mist (radial along the floor) */
  mistLow: { ...LIB.dustRing, count: 12, speed: [1.5, 4.5], size: [0.7, 1.4, 1.3], life: [1.0, 2.0], lift: 0.08, additive: 0.15, shade: 0.4,
    color: [[0, 0.8, 1.0, 1.3, 0], [0.1, 0.55, 0.68, 0.85, 0.28], [0.6, 0.45, 0.55, 0.68, 0.16], [1, 0.4, 0.5, 0.6, 0]] },
  /** crystal shards flung out (additive, crack erosion, floor bounce) */
  shards: { tex: 'shard', blend: 'add', count: 18, life: [0.4, 1.0], shape: { type: 'sphere', radius: 0.15 }, emit: 'radial', spread: 60, lift: 0.4,
    speed: [3, 9, 1.3], size: [0.06, 0.2, 2], spin: [4, 14], gravity: -11, drag: 0.8, collide: 'ground', bounce: 0.35, erode: 'erodeLate', erodeChannel: 'cracks',
    color: [key(0, STAR, 1, 1.1), key(0.12, F.core, 1, 0.6), key(0.6, F.mid, 0.9, 0.8), key(1, F.tail, 0)] },
  /** a fan of shards along the cut */
  shardFan: { tex: 'shard', blend: 'add', count: 12, life: [0.35, 0.8], shape: { type: 'point' }, emit: 'axis', spread: [55, 18], speed: [5, 12, 1.3],
    size: [0.07, 0.22, 2], spin: [4, 12], gravity: -9, drag: 1.2, collide: 'ground', bounce: 0.3, erode: 'erodeLate', erodeChannel: 'cracks',
    color: [key(0, STAR, 1, 1.2), key(0.12, F.core, 1, 0.65), key(0.6, F.mid, 0.9, 0.8), key(1, F.tail, 0)] },
  /** cold ice sparks: velocity-stretched, light gravity */
  sparks: { ...LIB.sparks, count: 30, gravity: -5, drag: 3, life: [0.2, 0.6, 1.5], color: heatRamp(STAR, F.core, F.mid, { flash: 1.2 }) },
  /** ice sparks thrown radially (finishers) */
  sparksRadial: { ...LIB.sparks, count: 60, spread: 180, emit: 'radial', speed: [3, 12, 1.4], gravity: -5, drag: 3, life: [0.2, 0.7, 1.5], color: heatRamp(STAR, F.core, F.mid, { flash: 1.2 }) },
  /** 1-3 frame core flash, cold (kept small: the generic hit adds its own) */
  flash: { ...LIB.flashCore, color: [[0, 5, 7, 10, 1], [0.3, 1.2, 3, 6, 0.7], [1, 0.1, 0.25, 0.5, 0]] },
  /** wind-up: motes converging and swirling into a point (attract) */
  gather: { ...LIB.chargeMotes, rate: 0, count: 26, life: [0.18, 0.3], shape: { type: 'sphere', radius: 0.9, inner: 0.55 }, size: [0.03, 0.09, 1.5],
    color: [key(0, F.tail, 0, 4), key(0.3, F.mid, 1), key(1, STAR, 0.8, 0.8)] },
  /** wind-up: thin streaks converging (attract + swirl) */
  gatherStreaks: { ...LIB.chargeStreaks, rate: 0, count: 30, life: [0.2, 0.32], shape: { type: 'sphere', radius: 1.2, inner: 0.7 }, size: [0.015, 0.04, 1.6],
    color: [key(0, F.tail, 0, 4), key(0.25, F.mid, 1), key(1, STAR, 1, 0.9)] },
  /** frost spray kicked off the floor by a slide (emitter, per metre) */
  skid: { tex: 'spark', blend: 'add', count: 0, perMeter: 26, life: [0.2, 0.5], shape: { type: 'disc', radius: 0.15 }, emit: 'axis', spread: [40, 25], speed: [2, 5],
    size: [0.025, 0.06], stretch: 0.05, maxStretch: 0.5, gravity: -9, drag: 2, collide: 'ground', bounce: 0.3, groundFade: 0.02,
    color: heatRamp(STAR, F.core, F.mid, { flash: 1.1 }) },
  skidMist: { tex: 'smoke', blend: 'alpha', count: 0, perMeter: 3, life: [0.6, 1.1], shape: { type: 'disc', radius: 0.2 }, emit: 'axis', spread: 50, speed: [0.4, 1.2],
    size: [0.4, 0.8, 1.3], sizeOverLife: 'puff', gravity: -0.2, drag: 2.4, spin: [0.1, 0.4], shade: 0.5, additive: 0.2, erode: 'erodeLate', erodeSoft: 0.4, groundFade: 0.25,
    color: [[0, 0.9, 1.1, 1.4, 0], [0.12, 0.6, 0.74, 0.9, 0.24], [1, 0.45, 0.55, 0.65, 0]] },
  // ---- ambient (idle): "a slow snowfall of glittering motes around her" --------------------------------------------
  ambSnow: { nearFade: 0.9, tex: 'snow', blend: 'add', count: 0, rate: 6, life: [1.6, 2.4], shape: { type: 'disc', radius: 0.75 }, emit: 'axis', dir: [0, -1, 0], spread: 20, speed: [0.25, 0.5],
    size: [0.035, 0.08, 1.6], spin: [0.5, 1.8], drag: 0.6, turbulence: { amp: 0.25, freq: 1.2, speed: 0.6 }, groundFade: 0.05,
    color: [[0, 1.4, 2, 2.8, 0], [0.15, 1.4, 2, 2.8, 0.75], [1, 0.4, 0.7, 1.1, 0]] },
  ambMotes: { nearFade: 0.9, tex: 'star4', blend: 'add', count: 0, rate: 5, life: [0.9, 1.6], shape: { type: 'sphere', radius: 0.6, inner: 0.65 }, emit: 'tangent', spread: 10, speed: [0.2, 0.5],
    swirl: 1.1, gravity: -0.1, size: [0.04, 0.11, 2], flicker: { amount: 0.7, rate: 10 }, rotation: [-0.3, 0.3], groundFade: 0.05,
    color: [key(0, STAR, 0, 0.7), key(0.15, STAR, 0.9, 0.7), key(1, F.mid, 0, 0.5)] },
  ambTip: { nearFade: 0.9, tex: 'star4', blend: 'add', count: 0, rate: 2.5, life: [0.5, 0.9], shape: { type: 'point' }, emit: 'random', speed: [0.05, 0.25], gravity: -0.25, drag: 2,
    size: [0.03, 0.08, 2], flicker: { amount: 0.6, rate: 12 }, rotation: [-0.3, 0.3], groundFade: 0.05,
    color: [key(0, STAR, 0, 0.8), key(0.1, STAR, 1, 0.8), key(1, F.mid, 0, 0.6)] },
  ambPool: { ...LIB.dustRing, count: 0, rate: 1.6, shape: { type: 'ring', radius: 0.25, thickness: 0.2 }, speed: [0.2, 0.6], life: [1.8, 2.8], size: [0.7, 1.2], sizeOverLife: [[0, 0.4], [1, 1.3]],
    additive: 0.35, shade: 0.4, color: [[0, 1.0, 1.3, 1.7, 0], [0.15, 0.6, 0.78, 1.0, 0.16], [0.6, 0.55, 0.66, 0.8, 0.1], [1, 0.5, 0.6, 0.72, 0]] },
  /** super-freeze: snow motes swirling around her, drawn in (vortex) */
  vortex: { nearFade: 0.9, tex: 'snow', blend: 'add', count: 0, rate: 40, life: [0.5, 0.8], shape: { type: 'sphere', radius: 1.4, inner: 0.7 }, emit: 'tangent', spread: 20, speed: [1, 2.2],
    swirl: 3.2, attract: 0.8, attractPow: 1.8, size: [0.04, 0.1, 1.6], spin: [1, 3], groundFade: 0.05,
    color: [[0, 0.9, 1.4, 2.0, 0], [0.2, 0.9, 1.4, 2.0, 0.8], [1, 1.3, 2.0, 2.8, 0.5]] },
  /** constellation star dust (hangs in the sky) */
  skyDust: { tex: 'glint', blend: 'add', count: 40, life: [1.4, 2.4], shape: { type: 'box', size: [7, 2.5, 3] }, emit: 'random', speed: [0.05, 0.3], drag: 1,
    size: [0.06, 0.16, 2], flicker: { amount: 0.8, rate: 9 }, groundFade: 0, nearFade: 0,
    color: [key(0, STAR, 0, 0.7), key(0.15, STAR, 1, 0.7), key(1, F.mid, 0, 0.6)] },
};

/** Register every definition by name (compiled + uploaded now, before prewarm). */
export function registerDefs(vfx) {
  if (typeof vfx.particleDef !== 'function') return;
  for (const k in D) { try { vfx.particleDef('iska.' + k, D[k]); } catch (e) { /* the def is still usable by identity */ } }
}

/**
 * Register Iska's composed presets.
 * @param {object} vfx
 * @param {() => number} rng deterministic rng (ctx.rng)
 */
export function defineIskaFx(vfx, rng) {

  /**
   * frost impact flower at a contact point: a cold flash, a four-point star, crystal shards fanned along the strike,
   * glints and snow that hang, a tilted crystalline ring around the strike axis, a breath of mist.
   * opts: k (0.5 light .. 1.6 finisher), ring (bool), floor (frost decal under the victim)
   */
  vfx.define('iska.flower', (v, at, o) => {
    const k = o.k ?? 1, p = at.pos, d = at.dir;
    v.burst(D.flash, { pos: p, scale: 0.12 + 0.16 * k, intensity: 0.7, realtime: true });
    v.flare({ kind: 'star', pos: p, size: 0.3 + 0.45 * k, life: 0.12 + 0.08 * k, decay: 2.6, color: STAR, intensity: 0.3 + 0.2 * k, rotation: 0.2 + rng() * 0.5, realtime: true });
    v.burst(D.shardFan, { pos: p, dir: d, count: n(5 + 10 * k), scale: 0.6 + 0.4 * k });
    v.burst(D.glint, { pos: p, count: n(4 + 8 * k), scale: 0.6 + 0.5 * k });
    if (k >= 0.8) {
      v.ring({ normal: [d.x, d.y, d.z], look: 'frost', pos: p, radius: [0.1, 0.55 + 0.6 * k], width: [0.12, 0.3], life: 0.3, intensity: 0.55 * k });
      v.burst(D.snow, { pos: p, count: n(4 * k), scale: 0.7 });
      v.burst(D.mist, { pos: p, count: 2, scale: 0.5 + 0.2 * k });
    }
    if (o.floor) v.decal({ kind: 'frost', pos: [p.x, 0, p.z * 0.3], radius: 0.6 + 0.5 * k, reveal: 0.25, life: 2.2 });
  });

  /**
   * Iska's crescent cut around a swing pivot: a thin crystalline crescent (ice look) with a starlight razor edge, glints
   * and snow hanging along the arc, a small star at the tip. Brighter / wider with opts.k; opts.twin adds the second
   * blade a beat later (concentric, slightly inside). No point light unless opts.light (the trail and hit carry it).
   * opts: arc, radius, width, normal, roll, sweep, life, k, twin, light
   */
  vfx.define('iska.cut', (v, at, o) => {
    const k = o.k ?? 1, s = at.scale, f = at.facing;
    const R = (o.radius ?? 1.1) * s, Wd = (o.width ?? 0.3) * s, arc = o.arc || [120, -35];
    const sweep = o.sweep ?? 0.05, life = o.life ?? 0.42;
    const plane = { normal: o.normal || [0, -0.15, 1], forward: [1, 0, 0], roll: o.roll || 0, facing: f };
    const cut = (w, r, wd, kk, ar) => {
      w.slash({ look: 'ice', palette: 'frost', pos: at.pos, ...plane, arc: ar, radius: r, width: wd, sweep, life, intensity: 0.7 * kk });
      w.slash({ look: 'razor', palette: 'frost', core: STAR, pos: at.pos, ...plane, arc: ar, radius: r * 0.995, width: 0.045 * s, sweep, life: 0.14, intensity: 1.1 * kk });
    };
    cut(v, R, Wd, k, arc);
    if (o.twin) v.schedule(0.045, (w) => cut(w, R * 0.86, Wd * 0.8, k * 0.8, [arc[0] - 10 * Math.sign(arc[1] - arc[0]), arc[1]]));
    const end = arcPoint(at.pos, plane, arc[1], R);
    v.schedule(sweep, (w) => {
      w.flare({ kind: 'star', pos: end, size: 0.45 * s * (0.6 + 0.4 * k), life: 0.14, decay: 2.4, color: STAR, intensity: 0.5 * k, rotation: 0.25 });
      w.burst(D.sparks, { pos: end, dir: arcTangent(plane, arc[1], Math.sign(arc[1] - arc[0])), count: n(8 * k), scale: 0.6 * s });
    });
    for (const u of [0.3, 0.6, 0.9]) {
      const p = arcPoint(at.pos, plane, arc[0] + (arc[1] - arc[0]) * u, R * 0.92);
      v.burst(D.glint, { pos: p, count: n(3 * k), scale: 0.6 * s, delay: sweep * u });
      v.burst(D.snow, { pos: p, count: 1, scale: 0.4 * s, delay: sweep * u });
    }
    if (o.light) v.light({ pos: [at.pos.x, at.pos.y, at.pos.z + 1.2], color: F.core, intensity: 16 * k, range: 4.5, duration: 0.2, decay: 'outCubic' });
  });

  /** wind-up tell at a point: motes and streaks converge and swirl in, a star kindles (opts.time = gather seconds) */
  vfx.define('iska.gather', (v, at, o) => {
    const T = o.time ?? 0.2, s = at.scale;
    v.burst(D.gather, { pos: at.pos, target: at.pos, scale: s, count: n(o.count ?? 22) });
    v.burst(D.gatherStreaks, { pos: at.pos, target: at.pos, scale: s, count: n((o.count ?? 22) * 1.2) });
    v.flare({ kind: 'star', pos: at.pos, size: [0.15 * s, 0.75 * s], life: T + 0.08, attack: T * 0.85, decay: 3, color: STAR, intensity: 0.55, rotation: 0.3 });
    if (o.lens) v.distort({ kind: 'lens', pos: at.pos, radius: 0.6 * s, strength: -0.025, life: T + 0.05, attack: T * 0.8 });
  });

  /** a crystal shard forming in the air (Starshard Volley wind-up): kindling star, converging glints, a thin ring */
  vfx.define('iska.crystallise', (v, at, o) => {
    const T = o.time ?? 0.14;
    v.burst(D.gather, { pos: at.pos, target: at.pos, count: 12, scale: 0.5 });
    v.flare({ kind: 'star', pos: at.pos, size: [0.1, 0.55], life: T + 0.06, attack: T * 0.9, decay: 4, color: STAR, intensity: 0.7, rotation: 0.1 });
    v.flare({ kind: 'glow', pos: at.pos, size: [0.05, 0.35], life: T + 0.05, attack: T, decay: 4, color: F.core, intensity: 0.5 });
  });

  /**
   * an ice spike erupting from the floor (Crystal Procession): a cluster sized by opts.size, a frost ring and a
   * crystalline decal, shards and glints, mist, a cold flash; the spikes hold opts.hold then shatter.
   * opts.last: the huge final spike (star flare, bigger ring, refraction, more debris).
   */
  vfx.define('iska.spike', (v, at, o) => {
    const size = o.size ?? 1, last = !!o.last, hold = o.hold ?? 0.6, f = at.facing;
    const g = [at.pos.x, 0, at.pos.z];
    const H = last ? 2.7 : Math.max(0.55, 1.45 * size);
    v.spikes({ kind: 'ice', pattern: 'cluster', pos: g, radius: last ? 0.62 : 0.16 + 0.22 * size, count: last ? 7 : 3 + Math.round(size * 2),
      height: [H * 0.45, H], width: last ? 0.26 : 0.22, tilt: last ? 18 : 14, stagger: 0.016, rise: last ? 0.07 : 0.06, hold, facing: f });
    v.decal({ kind: 'frost', pos: g, radius: 0.7 + 0.7 * size, reveal: 0.18, life: hold + 2.6 });
    v.ring({ look: 'frost', pos: g, radius: [0.2, (last ? 3.2 : 1.1 + 0.7 * size)], life: last ? 0.75 : 0.5, intensity: last ? 0.9 : 0.6, distort: last ? 0.03 : 0 });
    v.burst(D.flash, { pos: [g[0], 0.35 * H, 0.25], scale: 0.3 + 0.25 * size });
    v.burst(D.shards, { pos: [g[0], 0.2, 0.1], dir: [0.25 * f, 1, 0.2], count: n(8 + 10 * size), scale: 0.7 + 0.4 * size });
    v.burst(D.glint, { pos: [g[0], 0.6 * H, 0.15], count: n(5 + 6 * size), scale: 0.8 + 0.6 * size });
    v.burst(D.mistLow, { pos: g, dir: [0, 1, 0], count: n(3 + 4 * size), scale: 0.6 + 0.4 * size });
    v.light({ pos: [g[0], 0.9 * H, 1.1], color: F.core, intensity: last ? 150 : 45 + 35 * size, range: last ? 8 : 5, duration: last ? 0.5 : 0.25, decay: 'outCubic' });
    if (last) {
      v.flare({ kind: 'star', pos: [g[0], H * 0.85, 0.35], size: 2.2, life: 0.3, decay: 2.5, color: STAR, intensity: 0.75, rotation: 0.2 });
      v.burst(D.sparksRadial, { pos: [g[0], 0.8, 0.1], count: 50, scale: 1.1 });
      v.burst(D.snow, { pos: [g[0], 1.6, 0], count: 18, scale: 2 });
      v.debris({ kind: 'ice', pos: [g[0], 0.3, 0.1], dir: [0, 1, 0], count: 10, speed: [2, 6], spread: 60, size: [0.05, 0.14, 2] });
      v.schedule(0.03, (w) => w.distort({ kind: 'shock', pos: g, normal: [0, 1, 0], radius: [0.3, 3.4], life: 0.5, strength: 0.04 }));
    }
    // the shatter at the end of the hold: glitter hangs where the spike was
    v.schedule(hold + 0.06, (w) => {
      w.burst(D.glitter, { pos: [g[0], 0.5 * H, 0.1], count: n(10 + 12 * size), scale: 0.6 + 0.5 * size });
      w.burst(D.mist, { pos: [g[0], 0.4, 0.1], count: 2, scale: 0.6 + 0.3 * size });
    });
  });

  /**
   * the ice line of Frostline Step: frost races along the floor from at.pos over opts.length metres (opts.time s), a
   * thin glowing crack and glints run with it, mist creeps behind.
   */
  vfx.define('iska.iceLine', (v, at, o) => {
    const L = o.length ?? 3.6, T = o.time ?? 0.12, f = at.facing, x0 = at.pos.x;
    const steps = Math.max(3, Math.round(L / 0.6));
    for (let k = 0; k <= steps; k++) {
      const u = k / steps, x = x0 + f * L * u;
      v.schedule(T * u, (w) => {
        w.decal({ kind: 'frost', pos: [x, 0, 0.02], radius: 0.55 + 0.15 * (k % 2), reveal: 0.12, life: 2.6, rotation: k * 1.7 });
        w.burst(D.glint, { pos: [x, 0.12, 0.12], count: 3, scale: 0.5 });
        if (k % 2 === 0) w.burst(D.mistLow, { pos: [x, 0.02, 0], dir: [0, 1, 0], count: 2, scale: 0.45 });
      });
    }
    v.flare({ kind: 'streak', pos: [x0 + f * L * 0.5, 0.08, 0.3], size: 0.12, aspect: 30, life: 0.2, decay: 2, color: F.core, intensity: 0.45, dir: [f, 0, 0] });
  });

  /**
   * a star lance (ultimate starfall): a lance of starlight streaks from a sky star (at.target) down to at.pos, a cold
   * flash, a tilted ring, shards and glints burst, an ice crystal stays stuck in the floor (opts.hold) then shatters.
   */
  vfx.define('iska.lance', (v, at, o) => {
    const p = at.pos, from = at.target, k = o.k ?? 1;
    v.beam({ look: 'frost', palette: 'frost', core: STAR, from, to: p, width: 0.16, coreWidth: 0.28, extend: 0.035, release: 0.14, life: 0.2, flareSize: 0.45, intensity: 0.9 * k });
    v.schedule(0.035, (w) => {
      w.burst(D.flash, { pos: p, scale: 0.35 * k });
      w.flare({ kind: 'star', pos: p, size: 0.9 * k, life: 0.16, decay: 2.5, color: STAR, intensity: 0.6, rotation: rng() });
      w.burst(D.shards, { pos: p, dir: [0, 1, 0.3], count: n(10 * k), scale: 0.7 });
      w.burst(D.glint, { pos: p, count: n(6 * k), scale: 0.8 });
      const g = [o.ground ? o.ground.x : p.x, 0, o.ground ? o.ground.z : p.z];
      w.ring({ look: 'frost', pos: g, radius: [0.1, 1.1], life: 0.4, intensity: 0.5 });
      if (o.stick) {
        w.spikes({ kind: 'ice', pattern: 'cluster', pos: g, radius: 0.06, count: 1, height: [0.7, 1.05], width: 0.15, tilt: 22, stagger: 0, rise: 0.035, hold: o.hold ?? 0.6 });
        w.decal({ kind: 'frost', pos: g, radius: 0.7, reveal: 0.12, life: 3 });
      }
      if (o.light) w.light({ pos: [p.x, p.y, p.z + 1.0], color: F.core, intensity: 60, range: 5, duration: 0.18 });
    });
  });
}
