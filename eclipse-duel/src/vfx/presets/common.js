// Shared building blocks for the composed presets (src/vfx/presets/*): element palettes and kits, module-scope
// particle definitions (registered in DEFS so vfx.prewarm() uploads them once), geometry helpers for arcs and
// fighter-local placement, and the realtime view that makes a whole preset run on real time.
//
// Every particle definition a preset uses is created once at module scope through def(); preset bodies only pass
// per-call values (pos, dir, count, scale, colour) in `at`, so no definition is hashed or uploaded mid-fight.

import * as THREE from 'three';
import { LIB, PALETTE } from '../library.js';
import { heatRamp, toVec3 } from '../util.js';
import { planeQuat } from '../meshfx.js';
import { DEG } from '../../core/math.js';

/** Every particle definition created by the presets (handed to the particle table at prewarm). */
export const DEFS = [];
/** Register a module-scope particle definition. */
export const def = (d) => { DEFS.push(d); return d; };

/** Steel guard / neutral hit palette (white-gold). */
export const STEEL = { core: [9, 7, 4.6], mid: [3.2, 1.7, 0.55], tail: [0.3, 0.1, 0.02], smoke: [0.06, 0.055, 0.05] };
/** Gold spark palette of the volt element (CONTRACT: gold sparks (8, 5, 1)). */
export const GOLD = { core: [10, 7.5, 3.5], mid: [8, 5, 1], tail: [0.7, 0.25, 0.02] };
/** Palettes by element name. */
export const EL = { ember: PALETTE.ember, frost: PALETTE.frost, volt: PALETTE.volt, steel: STEEL, eclipse: PALETTE.eclipse };
/** Slash look per element. */
export const SLASH_LOOK = { ember: 'flame', frost: 'ice', volt: 'electric', steel: 'razor', eclipse: 'eclipse' };
/** Mesh-effect palette name per element (steel uses explicit colours). */
export const MESH_PAL = { ember: 'ember', frost: 'frost', volt: 'volt', eclipse: 'eclipse' };

/** [r, g, b] * k. */
export const mul = (c, k) => [c[0] * k, c[1] * k, c[2] * k];
/** Ramp key [t, r, g, b, a] from a colour. */
export const key = (t, c, a = 1, k = 1) => [t, c[0] * k, c[1] * k, c[2] * k, a];
/** Mesh-effect colour options for a palette (steel and custom palettes have no registered name). */
export function meshColors(P, extra = {}) {
  return { core: P.core, color: P.mid, tail: P.tail, ...extra };
}

/** Element name from preset opts (falls back to `fallback`). */
export const elementOf = (o, fallback = 'steel') => (o && EL[o.element] ? o.element : fallback);

// ---- geometry --------------------------------------------------------------------------------------------------------

const _q = new THREE.Quaternion();
const _F = new THREE.Vector3(), _Y = new THREE.Vector3();

/**
 * Point on a slash arc: centre `pos`, plane from { normal, forward, roll, facing } (vfx.slash conventions), angle in
 * degrees from forward toward local up, radius r. Returns a new Vector3 (spawn time only).
 */
export function arcPoint(pos, plane, angle, r) {
  planeQuat(plane, _q);
  _F.set(1, 0, 0).applyQuaternion(_q);
  _Y.set(0, 1, 0).applyQuaternion(_q);
  const a = angle * DEG;
  return new THREE.Vector3().copy(pos).addScaledVector(_F, Math.cos(a) * r).addScaledVector(_Y, Math.sin(a) * r);
}

/** Sweep tangent of the arc at `angle` (unit, in the direction the head travels for a sweep sign `sgn`). */
export function arcTangent(plane, angle, sgn) {
  planeQuat(plane, _q);
  _F.set(1, 0, 0).applyQuaternion(_q);
  _Y.set(0, 1, 0).applyQuaternion(_q);
  const a = angle * DEG;
  return new THREE.Vector3().addScaledVector(_F, -Math.sin(a) * sgn).addScaledVector(_Y, Math.cos(a) * sgn).normalize();
}

/**
 * A crescent that cuts THROUGH `pos` along the strike direction `dir` (camera-facing plane): returns slash options
 * { pos: centre, arc, facing, normal } for a crescent of radius r and half-angle `half` (deg) whose middle sits on pos.
 */
export function cutThrough(pos, dir, facing, r, half, roll = 0) {
  const th = Math.atan2(dir.y, dir.x * facing || 1e-6) / DEG;
  const mid = th + 90 + roll;
  const m = mid * DEG;
  const c = new THREE.Vector3(pos.x - facing * Math.cos(m) * r, pos.y - Math.sin(m) * r, pos.z);
  return { pos: c, arc: [mid + half, mid - half], facing, normal: [0, 0, 1], radius: r };
}

/**
 * Where to put a pooled light for an event at p: pulled toward the camera side (+Z) and a little up, so it lights
 * the bodies nearby without sitting inside them (irradiance grows with 1/d²: a light 0.3 m from armour whites it out;
 * 1.5 m keeps a hit light to a sheen on both fighters instead of a white-out).
 */
export const lightAt = (p, dz = 1.5, dy = 0.2) => new THREE.Vector3(p.x, p.y + dy, p.z + dz);

/** Floor point under p (y = lift). */
export const floor = (p, lift = 0.02) => new THREE.Vector3(p.x, lift, p.z);

/** Copy a position-like value into a new Vector3. */
export const vec = (v, fallback) => toVec3(v, new THREE.Vector3(), fallback);

// ---- realtime view ---------------------------------------------------------------------------------------------------

const ONE_ARG = ['trail', 'ribbon', 'slash', 'ring', 'pillar', 'beam', 'bolt', 'spikes', 'debris', 'decal', 'flare', 'light', 'distort', 'speedlines'];
const rtAt = (a) => (a == null ? { realtime: true } : a.isVector3 || Array.isArray(a) ? { pos: a, realtime: true } : a.realtime !== undefined ? a : { ...a, realtime: true });

/**
 * A view of `vfx` whose spawn functions default to `realtime: true` (and whose scheduled callbacks run on real time and
 * receive the view). Presets receive it instead of vfx when played with opts.realtime (KO slow motion, super-freeze).
 */
export function realtimeView(vfx) {
  const w = Object.create(vfx);
  for (const k of ONE_ARG) w[k] = (o) => vfx[k](rtAt(o));
  w.burst = (d, a) => vfx.burst(d, rtAt(a));
  w.emitter = (d, a) => vfx.emitter(d, rtAt(a));
  w.afterimage = (obj, o) => vfx.afterimage(obj, rtAt(o));
  w.schedule = (delay, fn, o) => vfx.schedule(delay, () => fn(w), { ...o, realtime: true });
  w.play = (name, at, o) => vfx.play(name, at, { ...o, realtime: true });
  w.realtime = true;
  return w;
}

// ---- element hit kits -------------------------------------------------------------------------------------------------

/** Spark palette per element: volt throws gold sparks, the others their own colours. */
const sparkPal = (el, P) => (el === 'volt' ? GOLD : P);

function hitKit(el) {
  const P = EL[el], S = sparkPal(el, P);
  const sRamp = heatRamp(S.core, S.mid, S.tail);
  const frost = el === 'frost';
  const k = {
    /** 2-3 frame white-hot burst sprite tinted toward the element core (short: a longer one reads as a white ball) */
    flash: def({ ...LIB.flashCore, life: [0.03, 0.05], sizeOverLife: [[0, 0.7], [0.35, 1.05], [1, 1.2]],
      color: [[0, 11, 10, 9.5, 1], key(0.3, P.core, 0.6, 0.55), key(1, P.tail, 0)] }),
    /** radial impact lines: thin hot streaks that shoot out of the contact in every direction and stop dead (frames 1-5) */
    lines: def({ tex: 'streak', blend: 'add', count: 12, life: [0.05, 0.12], shape: { type: 'sphere', radius: 0.04 }, emit: 'radial', spread: 180,
      speed: [9, 24, 1.3], drag: 14, size: [0.02, 0.045, 1.5], stretch: 0.075, maxStretch: 1.1, rotation: 0, groundFade: 0, pull: 0.25,
      color: [[0, 12, 11, 10, 1], key(0.3, S.core, 1, 0.8), key(1, S.mid, 0, 0.6)] }),
    /** few big fast streaks that shape the first frames along the strike */
    splash: def({ ...LIB.splash, color: heatRamp(S.core, S.mid, S.tail, { flash: 1.4 }) }),
    /** main directional sparks (frost: lighter, floatier, star-tipped) */
    sparks: def(frost
      ? { ...LIB.sparks, gravity: -5, drag: 3, life: [0.2, 0.8, 1.5], color: heatRamp([6, 8, 10], P.core, P.mid, { flash: 1.3 }) }
      : { ...LIB.sparks, color: sRamp }),
    /** wide short spray around the main cone */
    fine: def({ ...LIB.sparksFine, color: frost ? heatRamp([5, 7, 10], P.core, P.tail) : sRamp }),
    /** expanding soft light bloom (dim and short: it only tints the air around the flash) */
    puff: def({ ...LIB.glowPuff, life: [0.1, 0.15], color: [key(0, P.core, 0.7, 0.16), key(0.3, P.mid, 0.35, 0.3), [1, 0, 0, 0, 0]] }),
    /** ink splash of the impact frame: black dry-brush strokes thrown out of the contact, under the light (frames 1-8) */
    ink: def({ ...LIB.inkStrokes }),
    /** ink blot behind the flash (the light sits on black: readable against bright ground and fire) */
    blot: def({ ...LIB.inkBlot }),
    /** bright brush flicks: fewer and broader than the hairline `lines`, in the element's colour */
    strokes: def({ tex: 'brush', blend: 'add', count: 6, life: [0.06, 0.15], shape: { type: 'sphere', radius: 0.04 }, emit: 'radial', spread: 180,
      speed: [8, 22, 1.3], drag: 14, size: [0.05, 0.11, 1.5], stretch: 0.07, maxStretch: 1.2, rotation: 0, groundFade: 0, pull: 0.25, soft: 0,
      color: [[0, 10, 9, 8, 1], key(0.35, S.core, 1, 0.7), key(1, S.mid, 0, 0.5)] }),
  };
  // accent scraps of a heavy blow in the murim idiom: burning talisman paper (ember), snow crystals (frost), talisman
  // slips with violet script (volt), dry leaves (steel)
  if (el === 'ember') k.scrap = def({ ...LIB.talismans, count: 3 });
  else if (frost) k.scrap = def({ tex: 'snow', blend: 'add', count: 6, life: [0.7, 1.6], shape: { type: 'sphere', radius: 0.25 }, emit: 'axis', spread: 65, lift: 0.3,
    speed: [1, 4.5, 1.4], size: [0.07, 0.15, 1.6], spin: [1, 4], gravity: -1.1, drag: 2.2, turbulence: { amp: 0.5, freq: 1.2, speed: 1 }, flicker: { amount: 0.35, rate: 9 },
    color: [key(0, [6, 8, 10], 0), key(0.08, P.core, 1, 0.7), key(0.6, P.mid, 0.9, 1.1), key(1, P.tail, 0)] });
  else if (el === 'volt') k.scrap = def({ ...LIB.talismans, count: 3, color: [[0, 3.2, 2.2, 6, 1], [0.04, 0.4, 0.37, 0.29, 1], [0.8, 0.32, 0.3, 0.25, 1], [1, 0.12, 0.1, 0.12, 0.8]] });
  else k.scrap = def({ ...LIB.leaves, count: 3 });
  // lingering puff blown out of the contact along the strike: lit grey dust (steel), dark smoke with a warm underglow
  // (ember), pale mist (frost), violet-black ozone (volt). Lighter than the floor so it reads against dark armour.
  const puffBase = { tex: 'smoke', blend: 'alpha', count: 3, life: [0.6, 1.3], shape: { type: 'sphere', radius: 0.1 }, emit: 'axis', spread: 38, lift: 0.35,
    speed: [0.8, 2.6, 1.3], size: [0.42, 1.0, 1.4], sizeOverLife: [[0, 0.35], [0.2, 0.8, 'outQuad'], [1, 1.2]], gravity: 0.35, drag: 3.2, spin: [0.2, 0.8],
    turbulence: { amp: 0.25, freq: 0.9, speed: 0.8 }, erode: [[0, 0], [0.35, 0.12], [1, 1]], erodeSoft: 0.35, shade: 0.75, delay: [0.01, 0.05], groundFade: 0.15 };
  k.dust = def(el === 'ember'
    ? { ...puffBase, heat: 0.25, additive: [[0, 0.9], [0.18, 0.35], [0.4, 0]],
      color: [[0, 2.4, 0.8, 0.15, 0.7], [0.12, 0.5, 0.14, 0.04, 0.75], [0.35, 0.09, 0.075, 0.065, 0.6], [1, 0.07, 0.065, 0.06, 0]] }
    : frost
      ? { ...puffBase, gravity: -0.3, additive: 0.15, shade: 0.5, color: [[0, 1.3, 1.6, 2, 0], [0.08, 0.62, 0.74, 0.9, 0.42], [0.5, 0.5, 0.6, 0.7, 0.28], [1, 0.45, 0.55, 0.65, 0]] }
      : el === 'volt'
        ? { ...puffBase, additive: [[0, 0.8], [0.15, 0]], color: [[0, 2.4, 1.6, 5, 0.6], [0.1, 0.1, 0.08, 0.16, 0.6], [0.5, 0.07, 0.06, 0.1, 0.45], [1, 0.06, 0.055, 0.08, 0]] }
        : { ...puffBase, color: [[0, 1.6, 1.3, 0.9, 0.55], [0.08, 0.3, 0.28, 0.26, 0.68], [0.45, 0.2, 0.19, 0.18, 0.5], [1, 0.14, 0.135, 0.13, 0]] });
  // element accent of a heavy blow: fire licks (ember), crystal shards (frost), crackle arcs (volt), hot steel chips
  if (el === 'ember') k.accent = def({ ...LIB.fireLicks, count: 5, size: [0.35, 0.7], speed: [2, 5], life: [0.18, 0.4], emit: 'axis', spread: 45, lift: 0.3 });
  else if (frost) k.accent = def({ tex: 'shard', blend: 'add', count: 8, life: [0.35, 0.8], shape: { type: 'sphere', radius: 0.1 }, emit: 'axis', spread: 50, lift: 0.3,
    speed: [3, 8, 1.3], size: [0.05, 0.16, 2], spin: [4, 14], gravity: -11, drag: 0.8, collide: 'ground', bounce: 0.35, erode: 'erodeLate', erodeChannel: 'cracks',
    color: [key(0, [6, 8, 10], 1, 1.2), key(0.12, P.core, 1, 0.6), key(0.6, P.mid, 0.9, 0.8), key(1, P.tail, 0)] });
  else if (el === 'volt') k.accent = def({ tex: 'arc', blend: 'add', count: 6, life: [0.05, 0.14], shape: { type: 'sphere', radius: 0.2 }, emit: 'axis', spread: 70, speed: [4, 10],
    size: [0.3, 0.7], aspect: 2.2, align: 'velocity', stretch: 0.01, rotation: 0, flicker: { amount: 0.8, rate: 45 }, groundFade: 0,
    color: [key(0, [7, 6, 11], 1, 1.1), key(0.4, P.core, 1, 0.8), key(1, P.mid, 0)] });
  else k.accent = def({ ...LIB.sparks, count: 6, tex: 'ember', size: [0.03, 0.06], stretch: 0, align: 'billboard', speed: [2, 6], life: [0.5, 1.2], gravity: -9, flicker: { amount: 0.4, rate: 12 },
    color: [[0, 9, 7, 4, 1], [0.2, 5, 2.4, 0.6, 1], [0.7, 1.2, 0.3, 0.04, 0.9], [1, 0.3, 0.06, 0, 0]] });
  // lingering layer: embers rise, frost glitter hangs and falls, volt crackles, steel motes drift
  if (el === 'ember') k.motes = def({ ...LIB.embers, count: 10 });
  else if (frost) k.motes = def({ ...LIB.glitter, count: 16, gravity: -0.6, life: [0.5, 1.4], size: [0.04, 0.11, 2], color: [[0, 4, 7, 10, 0], [0.08, 4, 7, 10, 1], [0.6, 1.2, 2.6, 5, 0.8], [1, 0.4, 0.8, 1.6, 0]] });
  else if (el === 'volt') k.motes = def({ tex: 'arc', blend: 'add', count: 8, life: [0.06, 0.16], shape: { type: 'sphere', radius: 0.25 }, emit: 'radial', spread: 30, speed: [3, 8], size: [0.25, 0.6], aspect: 2, align: 'velocity', stretch: 0.01, rotation: 0, flicker: { amount: 0.8, rate: 45 }, groundFade: 0, color: [key(0, P.core, 1, 1.2), key(1, P.mid, 0)] });
  else k.motes = def({ ...LIB.embers, count: 8, size: [0.03, 0.07, 2], color: [[0, 9, 7, 4, 1], [0.35, 4, 2.2, 0.6, 1], [1, 0.4, 0.15, 0.02, 0]] });
  // dark smoke next to the glow for value contrast (frost: pale cold mist instead)
  k.smoke = def(frost
    ? { ...LIB.smoke, count: 4, gravity: -0.25, life: [0.7, 1.3], color: [[0, 0.9, 1.1, 1.3, 0], [0.08, 0.55, 0.68, 0.82, 0.32], [0.5, 0.45, 0.55, 0.65, 0.2], [1, 0.4, 0.48, 0.56, 0]] }
    : { ...LIB.smoke, count: 4, size: [0.45, 0.9, 1.4], life: [0.6, 1.2] });
  return k;
}

/** Hit kits by element name (steel, ember, frost, volt). */
export const KIT = { steel: hitKit('steel'), ember: hitKit('ember'), frost: hitKit('frost'), volt: hitKit('volt') };

// ---- shared layers -----------------------------------------------------------------------------------------------------

/** Ground dust: low rolling puffs kicked radially (alpha). */
export const DUST = def({ ...LIB.dustRing });
/** Small, tight foot puff. */
export const DUST_SMALL = def({ ...LIB.dustRing, count: 6, speed: [0.8, 2.6], size: [0.25, 0.55, 1.3], life: [0.45, 0.9], shape: { type: 'ring', radius: 0.12, thickness: 0.1 }, lift: 0.3 });
/** Pebbles thrown up that bounce. */
export const PEBBLES = def({ ...LIB.pebbles });
/** Dark smoke column that rises and lingers. */
export const SMOKE_COLUMN = def({ ...LIB.smokeLinger });
/** Fine dust motes drifting (alpha, lit). */
export const DUST_MOTES = def({ tex: 'dust', blend: 'alpha', count: 12, life: [0.8, 1.6], shape: { type: 'disc', radius: 0.4 }, emit: 'radial', spread: 30, lift: 0.8,
  speed: [0.3, 1.4], size: [0.03, 0.08, 2], gravity: -0.6, drag: 1.6, turbulence: { amp: 0.3, freq: 1.5, speed: 1 }, groundFade: 0.02, shade: 0.6,
  color: [[0, 0.35, 0.32, 0.28, 0], [0.1, 0.32, 0.29, 0.25, 0.8], [1, 0.2, 0.18, 0.16, 0]] });
/** Dry leaves kicked off the terrace floor (alpha, tumbling). */
export const LEAVES = def({ ...LIB.leaves });
/** Pale blossom petals (alpha, drifting). */
export const PETALS = def({ ...LIB.petals });
/** Ink strokes thrown flat along the floor by a stomp (radial around `dir`). */
export const STOMP_INK = def({ ...LIB.inkStrokes, shape: { type: 'ring', radius: 0.14 }, spread: 7, speed: [3.5, 9, 1.3], life: [0.14, 0.28], size: [0.06, 0.13, 1.4], pull: 0 });

/**
 * Inner-energy wisps per element (auras): tendrils that rise along the body and curl. Emitters (rate) for idle auras,
 * bursts (pass count) when a technique flares the energy up.
 */
export const WISPS = {
  ember: def({ ...LIB.wisps }),
  frost: def({ ...LIB.wisps, gravity: 0.25, speed: [0.5, 1.4], swirl: -0.9,
    color: [[0, 1.2, 2.4, 4, 0], [0.15, 0.7, 1.7, 3.2, 0.6], [0.6, 0.3, 0.8, 1.8, 0.4], [1, 0.05, 0.12, 0.3, 0]] }),
  volt: def({ ...LIB.wisps, speed: [1.0, 2.6], turbulence: { amp: 1.2, freq: 1.8, speed: 2.2 }, flicker: { amount: 0.5, rate: 22 },
    color: [[0, 3, 2, 6, 0], [0.15, 1.8, 1.0, 4.2, 0.65], [0.6, 0.7, 0.3, 1.8, 0.4], [1, 0.1, 0.04, 0.3, 0]] }),
  steel: def({ ...LIB.wisps, color: [[0, 2.2, 2.0, 1.6, 0], [0.15, 1.3, 1.2, 1.0, 0.5], [0.6, 0.5, 0.46, 0.4, 0.3], [1, 0.08, 0.07, 0.06, 0]] }),
  eclipse: def({ ...LIB.wisps, color: [[0, 4, 2.8, 1.4, 0], [0.15, 2.4, 1.3, 0.4, 0.65], [0.6, 0.9, 0.35, 0.08, 0.4], [1, 0.1, 0.03, 0.01, 0]] }),
};

/**
 * What a blow leaves on the floor when it lands low: the element's mark (scorch with dying embers / frost / an ink
 * splash with a dying rim of energy) plus dust, pebbles and leaves kicked off the stone.
 * @param {object} v   vfx (or a realtime view)
 * @param {string} el  'ember' | 'frost' | 'volt' | 'steel' | 'eclipse'
 * @param {THREE.Vector3} p  contact point (the mark goes on the floor under it)
 * @param {number} [s]  scale
 * @param {number} [i]  intensity (counts)
 */
export function groundMark(v, el, p, s = 1, i = 1) {
  const g = floor(p, 0.02);
  const r = (0.5 + 0.25 * i) * s;
  if (el === 'ember') v.decal({ kind: 'scorch', pos: g, radius: r * 1.1, life: 3.4, magma: 0.7, cool: 1.0 });
  else if (el === 'frost') v.decal({ kind: 'frost', pos: g, radius: r * 1.3, life: 3.0, reveal: 0.2 });
  else v.decal({ kind: 'ink', pos: g, radius: r * 1.25, life: 3.4, palette: el === 'volt' ? 'volt' : 'eclipse', cool: 0.7 });
  v.burst(DUST_SMALL, { pos: g, dir: [0, 1, 0], count: Math.max(2, Math.round(5 * i)), scale: 1.2 * s });
  v.burst(PEBBLES, { pos: g, dir: [0, 1, 0], count: Math.max(2, Math.round(4 * i)), scale: 0.6 * s });
  v.burst(LEAVES, { pos: g, dir: [0, 1, 0], count: Math.max(1, Math.round(3 * i)), scale: s });
}
