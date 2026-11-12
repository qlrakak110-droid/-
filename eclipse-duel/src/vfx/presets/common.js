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
 * the bodies nearby without sitting inside them (irradiance grows with 1/d²: a light 0.3 m from armour whites it out).
 */
export const lightAt = (p, dz = 1.1, dy = 0.2) => new THREE.Vector3(p.x, p.y + dy, p.z + dz);

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
    /** 1-3 frame white-hot burst sprite tinted toward the element core */
    flash: def({ ...LIB.flashCore, color: [[0, 11, 10, 9.5, 1], key(0.3, P.core, 0.75, 0.65), key(1, P.tail, 0)] }),
    /** few big fast streaks that shape the first frames along the strike */
    splash: def({ ...LIB.splash, color: heatRamp(S.core, S.mid, S.tail, { flash: 1.4 }) }),
    /** main directional sparks (frost: lighter, floatier, star-tipped) */
    sparks: def(frost
      ? { ...LIB.sparks, gravity: -5, drag: 3, life: [0.2, 0.8, 1.5], color: heatRamp([6, 8, 10], P.core, P.mid, { flash: 1.3 }) }
      : { ...LIB.sparks, color: sRamp }),
    /** wide short spray around the main cone */
    fine: def({ ...LIB.sparksFine, color: frost ? heatRamp([5, 7, 10], P.core, P.tail) : sRamp }),
    /** expanding soft light bloom */
    puff: def({ ...LIB.glowPuff, color: [key(0, P.core, 0.9, 0.35), key(0.3, P.mid, 0.45, 0.45), [1, 0, 0, 0, 0]] }),
  };
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
