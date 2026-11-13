// Base particle layers (vfx.lib): tuned building blocks for composed effects. Each is a plain definition object;
// derive element variants with spread syntax, e.g. { ...vfx.lib.sparks, color: heatRamp(FROST.core, FROST.mid, FROST.tail) }.
// Colours default to Kael's ember palette. Sizes are metres at at.scale = 1; counts are scaled by quality.
// Burst direction (at.dir) is the direction of the action: the slash direction for hit sparks, up for eruptions.

import { heatRamp } from './util.js';

/** Element palettes from CONTRACT.md (linear HDR). core -> mid -> tail. */
export const PALETTE = {
  ember: { core: [8, 3, 0.6], mid: [3, 0.5, 0.05], tail: [0.25, 0.03, 0.01], smoke: [0.06, 0.05, 0.045] },
  frost: { core: [1.5, 4, 8], mid: [0.3, 1.2, 3], tail: [0.1, 0.25, 0.5], smoke: [0.5, 0.6, 0.7] },
  volt: { core: [5, 3.5, 9], mid: [1.6, 0.8, 4], tail: [0.25, 0.08, 0.6], spark: [8, 5, 1], smoke: [0.05, 0.04, 0.07] },
  /** corona gold-white around a black core (the arena's eclipse; ultimates, the colossus) */
  eclipse: { core: [9, 6.5, 3.2], mid: [2.6, 1.2, 0.35], tail: [0.18, 0.06, 0.02], smoke: [0.012, 0.01, 0.014] },
  /** ground dust / rubble (alpha looks: lit top, body, settled tail) */
  dust: { core: [0.3, 0.27, 0.23], mid: [0.15, 0.135, 0.115], tail: [0.07, 0.064, 0.058], smoke: [0.08, 0.075, 0.07] },
};


export const LIB = {
  /** 1-3 frame white-hot core flash: a single big burst sprite (spawn 1-2). */
  flashCore: {
    tex: 'burst', blend: 'add', count: 1, life: [0.05, 0.08], speed: 0, size: [0.8, 1.1], sizeOverLife: [[0, 0.75], [0.3, 1.05], [1, 1.2]],
    rotation: [0, 6.28], groundFade: 0, pull: 0.4,
    color: [[0, 10, 8.5, 7, 1], [0.3, 5, 2.4, 0.7, 0.75], [1, 0.4, 0.08, 0, 0]],
  },
  /** Directional splash: a few big, fast, heavily-dragged streaks that shape the first frames of a hit. */
  splash: {
    tex: 'spark', blend: 'add', count: 14, life: [0.07, 0.16], shape: { type: 'point' }, spread: 22, spreadPow: 1.3,
    speed: [7, 14], size: [0.07, 0.16], stretch: 0.07, maxStretch: 1.4, drag: 9, rotation: 0, groundFade: 0, pull: 0.2,
    color: [[0, 12, 9, 6, 1], [0.4, 8, 3.2, 0.6, 0.9], [1, 2, 0.4, 0.04, 0]],
  },
  /** Fast directional sparks: velocity-stretched, gravity, drag, floor bounce. Many small, few large and long-lived. */
  sparks: {
    tex: 'spark', blend: 'add', count: 80, life: [0.2, 0.95, 1.5], shape: { type: 'sphere', radius: 0.05 },
    spread: 34, spreadPow: 1.5, speed: [4, 18, 1.5], size: [0.028, 0.085, 2.2], stretch: 0.045, maxStretch: 1.3, rotation: 0,
    gravity: -12, drag: 2.4, collide: 'ground', bounce: 0.38, friction: 0.55, groundFade: 0.02,
    color: [[0, 14, 10, 7, 1], [0.1, 10, 4.2, 1.1, 1], [0.5, 4, 0.9, 0.12, 1], [1, 0.5, 0.06, 0.0, 0]],
  },
  /** Wider, slower, short spray of fine sparks around the main cone (secondary layer). */
  sparksFine: {
    tex: 'spark', blend: 'add', count: 46, life: [0.12, 0.45, 1.4], shape: { type: 'sphere', radius: 0.08 },
    spread: 75, speed: [1.5, 8, 1.3], size: [0.02, 0.045], stretch: 0.03, maxStretch: 0.6, rotation: 0,
    gravity: -6, drag: 4, flicker: { amount: 0.5, rate: 30 },
    color: [[0, 10, 6, 3, 1], [0.3, 6, 2, 0.4, 1], [1, 1, 0.15, 0.02, 0]],
  },
  /** Slow glowing embers that drift up and meander, flickering (lingering layer). */
  embers: {
    tex: 'ember', blend: 'add', count: 22, life: [0.9, 2.4, 0.8], shape: { type: 'sphere', radius: 0.3 }, emit: 'radial', spread: 70, lift: 0.9,
    speed: [0.4, 2.6, 1.6], size: [0.06, 0.16, 2.2], gravity: 0.7, drag: 1.4, turbulence: { amp: 1.0, freq: 1.3, speed: 1.3 },
    flicker: { amount: 0.55, rate: 8 }, sizeOverLife: 'shrinkSlow', delay: [0.02, 0.08],
    color: [[0, 14, 6, 1.4, 1], [0.35, 8, 2.1, 0.3, 1], [0.8, 2.6, 0.4, 0.04, 0.8], [1, 0.6, 0.06, 0.0, 0]],
  },
  /** Dark, slowly expanding smoke puffs (alpha): value contrast next to additive glows. */
  smoke: {
    tex: 'smoke', blend: 'alpha', count: 8, life: [1.0, 2.0], shape: { type: 'sphere', radius: 0.18 }, emit: 'axis', spread: 55, lift: 0.4,
    speed: [0.5, 1.8], size: [0.7, 1.35, 1.4], sizeOverLife: 'puff', gravity: 0.5, drag: 2.2, spin: [0.15, 0.6],
    turbulence: { amp: 0.25, freq: 0.7, speed: 0.6 }, erode: 'erodeLate', erodeSoft: 0.35, delay: [0.03, 0.07],
    color: [[0, 0.5, 0.18, 0.05, 0], [0.06, 0.2, 0.1, 0.05, 0.55], [0.35, 0.08, 0.07, 0.065, 0.5], [1, 0.06, 0.06, 0.06, 0]],
  },
  /** Big lingering smoke column (alpha), rises and drifts; spawn delayed after an explosion. */
  smokeLinger: {
    tex: 'smoke', blend: 'alpha', count: 14, life: [2.4, 4.0], shape: { type: 'sphere', radius: 0.6, hemi: true }, emit: 'radial', spread: 40, lift: 1.4,
    speed: [0.3, 1.4], size: [1.6, 3.0, 1.3], sizeOverLife: [[0, 0.45], [0.3, 0.85], [1, 1.25]], gravity: 0.7, drag: 1.3, spin: [0.05, 0.3],
    turbulence: { amp: 0.35, freq: 0.45, speed: 0.5 }, erode: 'erodeLate', erodeSoft: 0.4, delay: [0.08, 0.35],
    color: [[0, 0.6, 0.2, 0.05, 0], [0.08, 0.16, 0.08, 0.04, 0.8], [0.4, 0.075, 0.07, 0.065, 0.7], [1, 0.06, 0.06, 0.06, 0]],
  },
  /** Fireball body: dense puffs that start additive and white-orange, cool through orange into dark smoke (alpha). */
  fireball: {
    tex: 'smoke', blend: 'alpha', count: 26, life: [0.6, 1.3], shape: { type: 'sphere', radius: 0.3 }, emit: 'radial', spread: 30, lift: 0.5,
    speed: [0.8, 4.2, 1.2], size: [0.8, 1.6, 1.3], sizeOverLife: [[0, 0.25], [0.2, 0.75], [1, 1.1, 'outQuad']], gravity: 2.4, drag: 3.0, spin: [0.2, 1.0],
    turbulence: { amp: 0.4, freq: 0.8, speed: 1.0 }, heat: 0.25, shade: 0.85, erode: [[0, 0], [0.55, 0.1], [1, 0.9]], erodeSoft: 0.3,
    additive: [[0, 1], [0.25, 0.9], [0.55, 0.15], [1, 0]],
    color: [[0, 4, 1.7, 0.4, 0.9], [0.12, 3, 0.9, 0.12, 1], [0.32, 1.3, 0.25, 0.035, 0.95], [0.55, 0.3, 0.08, 0.03, 0.85], [1, 0.05, 0.045, 0.04, 0]],
  },
  /** Flame licks flying outward, oriented along their motion; short-lived. */
  fireLicks: {
    tex: 'flame', blend: 'alpha', count: 16, life: [0.2, 0.45, 1.3], shape: { type: 'sphere', radius: 0.25 }, emit: 'radial', spread: 35, lift: 0.6,
    speed: [2, 6], size: [0.4, 0.95, 1.4], sizeOverLife: [[0, 0.6], [0.3, 1], [1, 0.85]], align: 'velocityAxis', gravity: 3, drag: 3.2, fps: 10, heat: 0.18,
    erode: [[0, 0], [0.25, 0.12], [1, 1]], erodeSoft: 0.25, additive: [[0, 1], [0.45, 0.6], [1, 0.1]],
    color: [[0, 10, 5, 1.4, 1], [0.2, 6, 1.6, 0.25, 1], [0.55, 1.3, 0.2, 0.03, 0.75], [0.85, 0.2, 0.06, 0.03, 0.5], [1, 0.08, 0.05, 0.04, 0]],
  },
  /** Standing fire (use as an emitter: rate per second). Upright flames that flicker through atlas variants. */
  fire: {
    tex: 'flame', blend: 'alpha', rate: 26, life: [0.45, 0.95], shape: { type: 'disc', radius: 0.25 }, spread: 10, speed: [0.6, 1.6],
    size: [0.5, 1.05, 1.4], sizeOverLife: [[0, 0.45], [0.25, 1], [1, 0.7]], align: 'axis', gravity: 1.6, drag: 1.2,
    turbulence: { amp: 0.45, freq: 1.4, speed: 1.8 }, fps: 8, erode: [[0, 0], [0.45, 0.12], [1, 0.95]], erodeSoft: 0.22, heat: 0.15,
    additive: [[0, 1], [0.6, 0.85], [1, 0.4]],
    color: [[0, 4, 1.6, 0.35, 0], [0.1, 3.2, 1.1, 0.18, 1], [0.45, 1.4, 0.24, 0.03, 0.85], [1, 0.12, 0.04, 0.02, 0]],
  },
  /** Ground dust kicked radially along the floor (alpha). Spawn at floor height with dir up. */
  dustRing: {
    tex: 'smoke', blend: 'alpha', count: 14, life: [0.8, 1.6], shape: { type: 'ring', radius: 0.35, thickness: 0.2 }, emit: 'radial', spread: 12, lift: 0.18,
    speed: [2.2, 5.5], size: [0.6, 1.2, 1.3], sizeOverLife: 'puff', gravity: 0.25, drag: 3.2, spin: [0.1, 0.5], groundFade: 0.25,
    erode: 'erodeLate', erodeSoft: 0.4, shade: 0.45,
    color: [[0, 0.24, 0.21, 0.17, 0], [0.08, 0.21, 0.18, 0.15, 0.4], [0.5, 0.15, 0.13, 0.11, 0.26], [1, 0.1, 0.09, 0.08, 0]],
  },
  /** Chunky lit pebbles thrown up, falling and bouncing (alpha). */
  pebbles: {
    tex: 'pebble', blend: 'alpha', count: 14, life: [0.9, 1.6], shape: { type: 'disc', radius: 0.3 }, emit: 'axis', spread: 40,
    speed: [2.5, 7, 1.4], size: [0.04, 0.13, 2], gravity: -14, drag: 0.4, collide: 'ground', bounce: 0.3, friction: 0.5, spin: [3, 12],
    groundFade: 0, shade: 1, color: [[0, 0.5, 0.42, 0.36, 1], [0.85, 0.42, 0.36, 0.3, 1], [1, 0.42, 0.36, 0.3, 0]],
  },
  /** Soft additive glow puff (expanding light bloom around an impact). */
  glowPuff: {
    tex: 'glow', blend: 'add', count: 1, life: [0.2, 0.28], speed: 0, size: [1.3, 1.7], sizeOverLife: [[0, 0.55], [0.25, 1], [1, 1.15]],
    groundFade: 0, pull: 0.3, color: [[0, 3, 1.3, 0.3, 0.9], [0.3, 1.4, 0.35, 0.04, 0.45], [1, 0.1, 0.02, 0, 0]],
  },
  /** Twinkling glitter motes (additive dots) that hang in the air. */
  glitter: {
    tex: 'glint', blend: 'add', count: 30, life: [0.6, 1.6], shape: { type: 'sphere', radius: 0.6 }, emit: 'random',
    speed: [0.1, 0.8], size: [0.04, 0.12, 2], gravity: -0.4, drag: 1.5, turbulence: { amp: 0.4, freq: 1.5, speed: 1 },
    flicker: { amount: 0.85, rate: 14 }, rotation: [0, 0.8],
    color: [[0, 6, 6, 6, 0], [0.1, 6, 6, 6, 1], [1, 2, 2, 2, 0]],
  },
  /** Converging charge streaks: spawn on a shell, swirl and get pulled into the centre by the end of their life. */
  chargeStreaks: {
    tex: 'spark', blend: 'add', rate: 120, life: [0.45, 0.8], shape: { type: 'sphere', radius: 1.5, inner: 0.75 }, emit: 'tangent', spread: 25,
    speed: [0.4, 1.4], size: [0.018, 0.05, 1.6], stretch: 0.06, maxStretch: 0.6, attract: 1, attractPow: 2.4, swirl: 2.2, rotation: 0, groundFade: 0,
    color: [[0, 1, 0.4, 0.1, 0], [0.25, 4, 1.4, 0.3, 1], [1, 12, 7, 3, 1]],
  },
  /** Converging soft motes (slower, bigger, fewer) under the streaks. */
  chargeMotes: {
    tex: 'glowHard', blend: 'add', rate: 30, life: [0.7, 1.1], shape: { type: 'sphere', radius: 1.1, inner: 0.6 }, emit: 'random',
    speed: [0.1, 0.5], size: [0.05, 0.14, 1.5], attract: 1, attractPow: 1.6, swirl: -1.2, groundFade: 0, flicker: { amount: 0.4, rate: 10 },
    color: [[0, 2, 0.7, 0.15, 0], [0.3, 5, 2, 0.4, 1], [1, 9, 5, 2, 0.6]],
  },
  // ---- murim accents (MURIM.md section 5) --------------------------------------------------------------------------
  /** Ink strokes of an impact: near-black dry-brush streaks that shoot out of the contact and stop dead (alpha). */
  inkStrokes: {
    tex: 'brush', blend: 'alpha', count: 8, life: [0.1, 0.22], shape: { type: 'sphere', radius: 0.05 }, emit: 'radial', spread: 180,
    speed: [7, 20, 1.3], drag: 16, size: [0.07, 0.16, 1.4], stretch: 0.05, maxStretch: 1.2, rotation: 0, groundFade: 0, pull: 0.2, soft: 0, shade: 0,
    erode: [[0, 0], [0.5, 0.15], [1, 1]], erodeNoise: 0.2, erodeSoft: 0.2,
    color: [[0, 0.012, 0.012, 0.016, 0.95], [0.6, 0.012, 0.012, 0.016, 0.85], [1, 0.012, 0.012, 0.016, 0]],
  },
  /** Ink blot thrown at the contact: one splat that blooms in two frames and erodes from its edges (alpha). */
  inkBlot: {
    tex: 'ink', blend: 'alpha', count: 1, life: [0.22, 0.34], speed: 0, size: [0.55, 0.8], sizeOverLife: [[0, 0.45], [0.18, 1, 'outQuad'], [1, 1.12]], rotation: [0, 6.28],
    groundFade: 0, pull: 0.1, soft: 0.1, shade: 0, erode: [[0, 0], [0.35, 0.1], [1, 1]], erodeNoise: 0.35, erodeSoft: 0.12,
    color: [[0, 0.012, 0.012, 0.016, 0.9], [1, 0.012, 0.012, 0.016, 0.7]],
  },
  /** Leaves torn loose from the terrace: dark tumbling leaves that flutter down (alpha). */
  leaves: {
    tex: 'leaf', blend: 'alpha', count: 8, life: [1.2, 2.6], shape: { type: 'disc', radius: 0.5 }, emit: 'axis', spread: 55, lift: 0.4,
    speed: [1.2, 4.5, 1.3], size: [0.11, 0.22, 1.5], spin: [3, 9], gravity: -2.2, drag: 1.6, turbulence: { amp: 0.9, freq: 1.1, speed: 1.2 },
    groundFade: 0.02, shade: 0.9, soft: 0, sizeOverLife: [[0, 1], [0.8, 1], [1, 0.6]],
    color: [[0, 0.3, 0.26, 0.13, 1], [0.85, 0.24, 0.2, 0.1, 1], [1, 0.2, 0.16, 0.08, 0]],
  },
  /** Pale blossom petals, drifting and tumbling slowly (alpha). */
  petals: {
    tex: 'petal', blend: 'alpha', count: 10, life: [1.4, 3.0], shape: { type: 'sphere', radius: 0.5 }, emit: 'axis', spread: 70, lift: 0.3,
    speed: [0.6, 3, 1.4], size: [0.08, 0.15, 1.4], spin: [2, 7], gravity: -0.9, drag: 1.8, turbulence: { amp: 0.8, freq: 1.0, speed: 1.0 },
    groundFade: 0.02, shade: 0.8, soft: 0,
    color: [[0, 1.1, 1.05, 1.15, 0], [0.08, 0.95, 0.92, 1.0, 0.95], [0.85, 0.8, 0.78, 0.86, 0.9], [1, 0.7, 0.7, 0.8, 0]],
  },
  /** Paper talisman scraps: tumbling slips whose script glows (ramp start), then burn away from the edges (alpha). */
  talismans: {
    tex: 'talisman', blend: 'alpha', count: 4, life: [1.0, 2.0], shape: { type: 'sphere', radius: 0.35 }, emit: 'axis', spread: 60, lift: 0.5,
    speed: [1.5, 5, 1.3], size: [0.16, 0.26], spin: [2, 7], gravity: -2.4, drag: 1.5, turbulence: { amp: 0.8, freq: 1.0, speed: 1.1 },
    groundFade: 0.03, shade: 1, soft: 0, heat: 0.4, erode: [[0, 0], [0.55, 0.05], [1, 1]], erodeNoise: 0.25, erodeSoft: 0.08, erodeGlow: 0.8,
    // the paper is paper from the first frames; the script (heat mask) keeps the hot start of the ramp for 40 % of the life
    color: [[0, 5, 2.6, 0.8, 1], [0.04, 0.42, 0.37, 0.27, 1], [0.8, 0.34, 0.3, 0.22, 1], [1, 0.14, 0.1, 0.07, 0.8]],
  },
  /** Flowing inner-energy wisps (auras): thin tendrils that rise, curl around the axis and thin out (emitter). */
  wisps: {
    tex: 'wisp', blend: 'add', rate: 12, life: [0.55, 1.1], shape: { type: 'disc', radius: 0.28 }, emit: 'axis', spread: 16, speed: [0.8, 2.0],
    size: [0.16, 0.32, 1.3], aspect: 2.8, align: 'velocity', stretch: 0.08, maxStretch: 0.5, gravity: 0.8, drag: 0.6, turbulence: { amp: 0.9, freq: 1.4, speed: 1.4 },
    swirl: 1.2, rotation: 0, groundFade: 0.05, sizeOverLife: [[0, 0.5], [0.3, 1], [1, 0.7]], erode: [[0, 0], [0.5, 0.1], [1, 0.9]], erodeSoft: 0.3, erodeNoise: 0.5,
    color: [[0, 3, 1.2, 0.3, 0], [0.15, 2.4, 0.8, 0.15, 0.7], [0.6, 1.2, 0.25, 0.04, 0.45], [1, 0.2, 0.03, 0.01, 0]],
  },
  /** Heat shimmer particles for the distortion layer (blend 'distort'). */
  heatHaze: {
    tex: 'glow', blend: 'distort', count: 6, life: [0.8, 1.4], shape: { type: 'sphere', radius: 0.4, hemi: true }, emit: 'axis', spread: 20,
    speed: [0.5, 1.4], size: [0.8, 1.6], gravity: 0.6, drag: 1, strength: 0.012, erodeScale: 0.6, noiseScroll: [0, -0.6],
  },
};

export { heatRamp };
