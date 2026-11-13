// Clip registry and sampler. Clips and poses are plain data; they are compiled lazily per rig into keyed tracks and
// sampled into a Pose (local rotations + hips + IK goals + grip / look / curl / root motion). See README.md for the
// exact key format and the bone axis conventions.

import { ease as resolveEase } from '../core/math.js';
import { eulerToQuat, computeTangents, sampleTrack, qnormalize, qfromBasis, qfromTo, qrot } from './rigmath.js';
/** Floats of one arm's IK memory (= ik.js MEM; kept here so the clip module does not import the solver). */
export const SWIVEL_MEM = 20;

const rawClips = new Map();
const rawPoses = new Map();
let compiledByRig = new WeakMap();

/** IK effectors in Pose.ik order. */
export const EFFECTORS = ['handR', 'handL', 'footR', 'footL'];
// per effector: w, posA(3), quatA(4), hasRotA, pole(3), hasPole, soft, spaceB, k, posB(3), quatB(4), hasRotB
// (soft = soft-reach fraction of the limb length, 0 = may lock straight; -1 = not keyed: the rig default)
// A = fighter frame (root / origin, resolved at sampling), B = hips / chest frame, k = blend A -> B
export const EFF_STRIDE = 24;
/** IK target spaces: 0 root (fighter frame), 1 origin (root at clip start), 2 hips bone frame, 3 chest bone frame. */
export const SPACES = { root: 0, origin: 1, hips: 2, chest: 3 };
const CENTER = new Set(['hips', 'spine', 'chest', 'neck', 'head']);

/** Register a named static pose (same channels as a clip key, without t / ease). */
export function definePose(name, def) {
  rawPoses.set(name, def);
  return name;
}

/**
 * Register a clip.
 * @param {string} name
 * @param {object} def { duration, loop=false, base='neutral', keys:[...], events:[{t, name, data}], mainHand='R',
 *                       gripHand='L', gripAt='grip', breath=1, look=true }
 */
export function defineClip(name, def) {
  if (!def || !Array.isArray(def.keys) || def.keys.length === 0) throw new Error('defineClip ' + name + ': needs keys');
  rawClips.set(name, { ...def, name });
  return name;
}

export function hasClip(name) { return rawClips.has(name); }
export function listClips() { return [...rawClips.keys()]; }
export function listPoses() { return [...rawPoses.keys()]; }
export function getClipDef(name) { return rawClips.get(name); }
export function getPoseDef(name) { return rawPoses.get(name); }

// ---- mirroring -------------------------------------------------------------------------------------------------
const swapName = (n) => (n.endsWith('R') ? n.slice(0, -1) + 'L' : n.endsWith('L') ? n.slice(0, -1) + 'R' : n);
const negS = (v) => (v ? [v[0], v[1], -v[2]] : v);
const mirE = (v) => (v ? [-v[0], -v[1], v[2]] : v);

const ARM = /^(shoulder|upperArm|foreArm|hand|fingers|fingerTips|thumb|weapon)[RL]$/;

function mirrorChannels(k, keepHands = false, fromBase = false, mainHand = 'R') {
  const o = { ...k };
  if (k.bones) {
    o.bones = {};
    for (const [b, v] of Object.entries(k.bones)) {
      if (keepHands && ARM.test(b)) {
        // a kept weapon hand does the mirrored motion with the same arm: an FK pose of that arm has no mirror image
        // (only an IK target does). Off-hand FK keys are kept as they are (loose arm).
        const ikOn = k.ik && k.ik['hand' + mainHand] && k.ik['hand' + mainHand].w !== 0;
        if (!fromBase && b.endsWith(mainHand) && !ikOn) {
          throw new Error(`mirrorClip(hands: 'keep'): FK key on ${b} of the weapon hand; key that hand by IK (ik.hand${mainHand}) instead`);
        }
        o.bones[b] = v;
        continue;
      }
      const isObj = !Array.isArray(v);
      const r = isObj ? v.r : v;
      const r2 = CENTER.has(b) ? mirE(r) : r;
      o.bones[swapName(b)] = isObj ? { ...v, r: r2 } : r2;
    }
  }
  if (k.hips) o.hips = { ...k.hips, pos: negS(k.hips.pos), rot: mirE(k.hips.rot) };
  if (k.ik) {
    o.ik = {};
    for (const [e, v] of Object.entries(k.ik)) {
      const kept = keepHands && e.startsWith('hand');
      const name = kept ? e : swapName(e);
      // a kept hand's elbow pole is mirrored about that arm's own shoulder (resolved per rig at compile: poleKeep)
      o.ik[name] = v && { ...v, pos: negS(v.pos), pole: kept ? undefined : negS(v.pole), poleKeep: kept && v.pole ? negS(v.pole) : v.poleKeep, aim: negS(v.aim), up: negS(v.up), rot: mirE(v.rot) };
    }
  }
  if (k.look) o.look = { ...k.look, at: negS(k.look.at) };
  if (k.curl && !keepHands) o.curl = [k.curl[1], k.curl[0]];
  return o;
}

/** Resolve `pose:` references of a key into explicit channels (key channels win). */
function resolveKey(k) {
  if (!k.pose) return k;
  const p = rawPoses.get(k.pose);
  if (!p) throw new Error('unknown pose ' + k.pose);
  const base = resolveKey(p);
  const out = { ...base, ...k };
  delete out.pose;
  for (const ch of ['bones', 'ik']) if (base[ch] || k[ch]) out[ch] = { ...(base[ch] || {}), ...(k[ch] || {}) };
  if (base.hips || k.hips) out.hips = { ...(base.hips || {}), ...(k.hips || {}) };
  return out;
}

/**
 * Register `dst` as the mirror image of clip `src` (side axis negated, left <-> right swapped).
 * opts.events: optional map { srcEventName: dstEventName }.
 * opts.hands: 'swap' (default: the other hand does the work - twin blades, unarmed) or 'keep' (body, legs and the
 * hand / weapon paths are mirrored but each hand keeps its job: a right-handed weapon swings the mirrored arc).
 */
export function mirrorClip(src, dst, opts = {}) {
  const d = rawClips.get(src);
  if (!d) throw new Error('mirrorClip: unknown clip ' + src);
  const keep = opts.hands === 'keep';
  const m = {
    ...d, name: dst,
    mainHand: keep ? d.mainHand || 'R' : d.mainHand === 'L' ? 'R' : 'L',
    gripHand: keep ? d.gripHand || 'L' : (d.gripHand || 'L') === 'L' ? 'R' : 'L',
    keys: d.keys.map((k) => mirrorChannels(resolveKey(k), keep, false, d.mainHand || 'R')),
    base: d.base ? { mirrorOf: d.base, keepHands: keep } : { mirrorOf: 'neutral', keepHands: keep },
    events: (d.events || []).map((e) => ({ ...e, name: (opts.events && opts.events[e.name]) || e.name })),
  };
  rawClips.set(dst, m);
  return dst;
}

/** Register `dst` as the mirror image of pose `src`. */
export function mirrorPose(src, dst) {
  rawPoses.set(dst, mirrorChannels(resolveKey(rawPoses.get(src))));
  return dst;
}

// ---- compile ---------------------------------------------------------------------------------------------------
function newTrack(dim) { return { n: 0, dim, times: [], values: [], eases: [], modes: [], fs: [], fe: [], fi: [], _last: 0 }; }
const MODES = { auto: 0, smooth: 0, linear: 1, step: 2 };
const SHAPES = '(Quad|Cubic|Quart|Quint|Expo|Sine|Circ)';
const RE_INOUT = new RegExp('^inOut' + SHAPES + '$'), RE_IN = new RegExp('^in' + SHAPES + '$'), RE_OUT = new RegExp('^out' + SHAPES + '$');
const ARRIVE = { Quad: 2, Cubic: 3, Quart: 3, Quint: 3, Expo: 3, Sine: 1.57, Circ: 3 };
/**
 * Eases become tangent constraints instead of time remaps: [flat at the segment's start key, flat at its end key,
 * impact arrival factor]. 'out*' / 'inOut*' stop at their keys with the velocity continuous on both sides (C1);
 * 'in*' leaves its start key from rest and hits its end key at k x the segment's mean speed, then the next segment
 * starts from rest (an impact: the one deliberate velocity step). null = no tangent form (back / elastic / bounce /
 * snap / custom fn): legacy time remap.
 */
export function easeFlags(e) {
  if (e === undefined || e === null || e === 'linear') return [0, 0, 0];
  if (typeof e !== 'string') return null;
  if (RE_INOUT.test(e)) return [1, 1, 0];
  if (RE_IN.test(e)) return [1, 0, ARRIVE[e.slice(2)]];
  if (RE_OUT.test(e)) return [0, 1, 0];
  return null;
}

function pushKey(tr, t, vals, ease, mode) {
  tr.times.push(t);
  for (const v of vals) tr.values.push(v);
  const f = easeFlags(ease);
  tr.eases.push(f ? null : resolveEase(ease));
  tr.fs.push(f ? f[0] : 0); tr.fe.push(f ? f[1] : 0); tr.fi.push(f ? f[2] : 0);
  tr.modes.push(MODES[mode || 'auto'] ?? 0);
}

function finalizeTrack(tr, loop, duration, isQuat) {
  // loops: close the cycle with a copy of the first key at t = duration
  if (loop && tr.times.length && tr.times[tr.times.length - 1] < duration - 1e-6) {
    tr.times.push(duration);
    for (let d = 0; d < tr.dim; d++) tr.values.push(tr.values[d]);
    tr.eases.push(tr.eases[0]);
    tr.fs.push(tr.fs[0]); tr.fe.push(tr.fe[0]); tr.fi.push(tr.fi[0]);
    tr.modes.push(tr.modes[0]);
  }
  tr.n = tr.times.length;
  // flat key i: the segment ending at i eases out, or the segment starting at i (ending at i + 1) eases in
  tr.flat = new Uint8Array(tr.n);
  for (let i = 0; i < tr.n; i++) tr.flat[i] = (tr.fe[i] || (i + 1 < tr.n && tr.fs[i + 1])) ? 1 : 0;
  if (loop && tr.n > 1 && tr.fs[1]) tr.flat[tr.n - 1] = 1;
  tr.impact = tr.fi.some((x) => x > 0) ? Float32Array.from(tr.fi) : null;
  if (tr.impact) tr.impact[0] = 0;
  tr.times = Float32Array.from(tr.times);
  tr.values = Float32Array.from(tr.values);
  tr.tangents = new Float32Array(tr.values.length);
  if (isQuat) { // hemisphere-align consecutive keys
    for (let i = 1; i < tr.n; i++) {
      const a = (i - 1) * 4, b = i * 4;
      if (tr.values[a] * tr.values[b] + tr.values[a + 1] * tr.values[b + 1] + tr.values[a + 2] * tr.values[b + 2] + tr.values[a + 3] * tr.values[b + 3] < 0) {
        for (let d = 0; d < 4; d++) tr.values[b + d] = -tr.values[b + d];
      }
    }
  }
  tr.modes = Uint8Array.from(tr.modes);
  tr.quat = !!isQuat;
  computeTangents(tr, loop, duration);
  return tr;
}

function aimUpToQuat(out, aim, up) {
  let ax = aim[0], ay = aim[1], az = aim[2];
  let l = Math.hypot(ax, ay, az) || 1; ax /= l; ay /= l; az /= l;
  let ux = up ? up[0] : 0, uy = up ? up[1] : 1, uz = up ? up[2] : 0;
  let d = ux * ax + uy * ay + uz * az;
  if (Math.abs(d) > 0.999) { ux = 0; uy = 0; uz = 1; d = az; }
  ux -= ax * d; uy -= ay * d; uz -= az * d;
  l = Math.hypot(ux, uy, uz) || 1; ux /= l; uy /= l; uz /= l;
  const zx = ay * uz - az * uy, zy = az * ux - ax * uz, zz = ax * uy - ay * ux;
  return qfromBasis(out, 0, [ax, ay, az], [ux, uy, uz], [zx, zy, zz]);
}

/** q = rest * q (in place). */
function qmulRest(q, rest, o) {
  const ax = rest[o], ay = rest[o + 1], az = rest[o + 2], aw = rest[o + 3], bx = q[0], by = q[1], bz = q[2], bw = q[3];
  q[0] = ax * bw + aw * bx + ay * bz - az * by; q[1] = ay * bw + aw * by + az * bx - ax * bz;
  q[2] = az * bw + aw * bz + ax * by - ay * bx; q[3] = aw * bw - ax * bx - ay * by - az * bz;
}

/** Rotate vector v by the minimal rotation taking direction a to direction b (parallel transport of an up vector). */
function transport(v, a, b) {
  const la = Math.hypot(a[0], a[1], a[2]) || 1, lb = Math.hypot(b[0], b[1], b[2]) || 1;
  const q = qfromTo(new Float32Array(4), 0, a[0] / la, a[1] / la, a[2] / la, b[0] / lb, b[1] / lb, b[2] / lb);
  const o = qrot(new Float32Array(3), 0, q, 0, v[0], v[1], v[2]);
  return [o[0], o[1], o[2]];
}

/**
 * Hand / foot keys with `aim` but no `up` keep the blade roll of the neighbouring keys: the previous key's up is
 * parallel-transported to the new aim (minimal rotation), the first such key borrows the next key's up, and only an
 * effector that never keys `up` falls back to world +Y. Works on the sorted, pose-resolved keys (copies the key objects
 * it changes). Per effector and space group (fighter frame / hips-chest frame).
 */
function fillUps(keys) {
  const out = keys.map((k) => (k.ik ? { ...k, ik: { ...k.ik } } : k));
  for (const e of EFFECTORS) {
    for (const group of [0, 1]) {
      const list = out.filter((k) => {
        const v = k.ik && k.ik[e];
        return v && v.aim && ((SPACES[v.space || 'root'] >= 2 ? 1 : 0) === group);
      });
      if (!list.length) continue;
      let first = list.findIndex((k) => k.ik[e].up);
      if (first < 0) continue; // never keys up: world +Y (aimUpToQuat default)
      for (let i = first - 1; i >= 0; i--) {
        const v = list[i].ik[e], n = list[i + 1].ik[e];
        list[i].ik[e] = { ...v, up: transport(n.up, n.aim, v.aim) };
      }
      for (let i = first + 1; i < list.length; i++) {
        const v = list[i].ik[e], p = list[i - 1].ik[e];
        if (!v.up) list[i].ik[e] = { ...v, up: transport(p.up, p.aim, v.aim) };
      }
    }
  }
  return out;
}

function baseKeyOf(base) {
  if (!base) return {};
  if (typeof base === 'object' && base.mirrorOf) return mirrorChannels(baseKeyOf(base.mirrorOf), !!base.keepHands, true);
  if (typeof base === 'object') return resolveKey(base);
  if (rawPoses.has(base)) return resolveKey({ pose: base });
  if (rawClips.has(base)) return resolveKey(rawClips.get(base).keys[0]);
  throw new Error('unknown base pose/clip ' + base);
}

function compile(rig, def) {
  const duration = Math.max(1e-3, def.duration ?? Math.max(...def.keys.map((k) => k.t ?? 0)));
  const loop = !!def.loop;
  const keys = fillUps(def.keys.map(resolveKey).sort((a, b) => (a.t ?? 0) - (b.t ?? 0)));
  const base = baseKeyOf(def.base ?? 'neutral');
  const q = new Float32Array(4);
  const boneTracks = new Map();
  let hipsPos = null, hipsRot = null, grip = null, look = null, lookW = null, curl = null, root = null;
  const ik = {};

  const addKey = (k, t, isBase) => {
    const ke = k.ease, km = k.interp;
    if (k.bones) {
      for (const [b, v] of Object.entries(k.bones)) {
        if (b === 'hips') { const hv = Array.isArray(v) ? { rot: v } : { rot: v.r, ease: v.ease, interp: v.interp }; addHips(hv, t, ke, km); continue; }
        const i = rig.index[b];
        if (i === undefined) throw new Error('clip ' + def.name + ': unknown bone ' + b);
        if (rig.helper[i]) throw new Error('clip ' + def.name + ': ' + b + ' is a driven helper bone');
        if (/^(fingers|fingerTips|thumb)[RL]$/.test(b)) { // driven by the curl channel: a key here would be silently lost
          if (!isBase) console.warn('clip ' + def.name + ': ' + b + ' is driven by the curl channel; the key is ignored');
          continue;
        }
        const r = Array.isArray(v) ? v : v.r;
        if (!boneTracks.has(i)) boneTracks.set(i, newTrack(4));
        const tr = boneTracks.get(i);
        if (isBase && tr.times.length) continue;
        eulerToQuat(q, 0, r[0] || 0, r[1] || 0, r[2] || 0, rig.side[i] < 0);
        if (/^weapon[RL]$/.test(b)) qmulRest(q, rig.restRot, i * 4); // relative to the weapon's rest pose in the fist
        pushKey(tr, t, q, (!Array.isArray(v) && v.ease) || ke, (!Array.isArray(v) && v.interp) || km);
      }
    }
    if (k.hips) addHips(k.hips, t, ke, km);
    if (k.ik) {
      for (const [e, v] of Object.entries(k.ik)) {
        if (!EFFECTORS.includes(e)) throw new Error('clip ' + def.name + ': unknown IK effector ' + e);
        if (!ik[e]) {
          ik[e] = { A: { pos: newTrack(3), rot: newTrack(4), space: [] }, B: { pos: newTrack(3), rot: newTrack(4) }, pole: newTrack(3), w: newTrack(1), k: newTrack(1), soft: newTrack(1), origin: false, spaceB: 0 };
        }
        const E = ik[e];
        const ee = (v && v.ease) || ke, em = (v && v.interp) || km;
        if (!v || v.w === 0) { pushKey(E.w, t, [0], ee, em); if (v && v.pole) pushKey(E.pole, t, v.pole, ee, em); continue; }
        const sp = SPACES[v.space || 'root'];
        if (sp === undefined) throw new Error('clip ' + def.name + ': unknown IK space ' + v.space);
        if (sp === 1) E.origin = true;
        if (sp >= 2) {
          if (E.spaceB && E.spaceB !== sp) throw new Error('clip ' + def.name + ': ' + e + ' mixes hips and chest spaces');
          E.spaceB = sp;
        }
        const S = sp >= 2 ? E.B : E.A;
        if (v.pos) {
          pushKey(S.pos, t, v.pos, ee, em);
          pushKey(E.k, t, [sp >= 2 ? 1 : 0], ee, em);
          if (sp < 2) E.A.space.push(sp);
        }
        if (v.pos || v.w !== undefined) pushKey(E.w, t, [v.w ?? 1], ee, em);
        if (v.aim) pushKey(S.rot, t, aimUpToQuat(q, v.aim, v.up), ee, em);
        else if (v.rot) pushKey(S.rot, t, eulerToQuat(q, 0, v.rot[0] || 0, v.rot[1] || 0, v.rot[2] || 0), ee, em);
        if (v.pole) pushKey(E.pole, t, v.pole, ee, em);
        else if (v.poleKeep) { // kept hand of a mirrorClip(hands: 'keep'): mirror the pole about the arm's own shoulder
          const sz = (e === 'handR' ? 1 : -1) * (rig.P.clavicleRoot + rig.P.clavicle);
          pushKey(E.pole, t, [v.poleKeep[0], v.poleKeep[1], 2 * sz + v.poleKeep[2]], ee, em);
        }
        if (v.soft !== undefined) pushKey(E.soft, t, [Math.max(0, v.soft)], ee, em);
      }
    }
    const num = (x) => (typeof x === 'number' ? { v: x } : x);
    if (k.grip !== undefined) { if (!grip) grip = newTrack(1); const g = num(k.grip); pushKey(grip, t, [g.v ?? g.w ?? 0], g.ease || ke, g.interp || km); }
    if (k.look !== undefined) {
      if (!look) { look = newTrack(3); lookW = newTrack(1); }
      if (k.look && k.look.at) { pushKey(look, t, k.look.at, k.look.ease || ke, km); pushKey(lookW, t, [k.look.w ?? 1], k.look.ease || ke, km); }
      else pushKey(lookW, t, [0], ke, km);
    }
    if (k.curl) { if (!curl) curl = newTrack(2); pushKey(curl, t, k.curl, ke, km); }
  };
  const addHips = (h, t, ke, km) => {
    if (h.pos) { if (!hipsPos) hipsPos = newTrack(3); pushKey(hipsPos, t, h.pos, h.ease || ke, h.interp || km); }
    if (h.rot) { if (!hipsRot) hipsRot = newTrack(3); pushKey(hipsRot, t, h.rot, h.ease || ke, h.interp || km); }
  };
  // root motion first: origin-space IK keys are relative to it
  for (const k of keys) {
    if (!k.root) continue;
    if (!root) root = newTrack(2);
    const r = Array.isArray(k.root) ? { pos: k.root } : k.root;
    pushKey(root, Math.min(duration, Math.max(0, k.t ?? 0)), r.pos, r.ease || k.ease, r.interp || k.interp);
  }
  if (root) finalizeTrack(root, loop, duration);
  for (const k of keys) addKey(k, Math.min(duration, Math.max(0, k.t ?? 0)), false);
  // fill never-keyed channels from the base pose
  const fill = {};
  if (base.bones) { fill.bones = {}; for (const [b, v] of Object.entries(base.bones)) { const i = rig.index[b]; if (b === 'hips' ? !hipsRot : !boneTracks.has(i)) fill.bones[b] = v; } }
  if (base.hips && !hipsPos && base.hips.pos) fill.hips = { pos: base.hips.pos };
  if (base.hips && !hipsRot && base.hips.rot) fill.hips = { ...(fill.hips || {}), rot: base.hips.rot };
  if (base.ik) { fill.ik = {}; for (const [e, v] of Object.entries(base.ik)) if (!ik[e]) fill.ik[e] = v; }
  if (base.grip !== undefined && !grip) fill.grip = base.grip;
  if (base.look !== undefined && !look) fill.look = base.look;
  if (base.curl && !curl) fill.curl = base.curl;
  addKey(fill, 0, true);

  const c = {
    name: def.name, duration, loop,
    events: (def.events || []).map((e) => ({ t: e.t, name: e.name, data: e.data })).sort((a, b) => a.t - b.t),
    mainHand: def.mainHand || 'R', gripHand: def.gripHand || 'L', gripAt: def.gripAt || 'grip',
    breath: def.breath ?? 1, lookEnabled: def.look !== false, edgeRoll: def.edgeRoll,
    bones: [...boneTracks].map(([i, tr]) => ({ i, tr: finalizeTrack(tr, loop, duration, true) })),
    hipsPos: hipsPos && finalizeTrack(hipsPos, loop, duration),
    hipsRot: hipsRot && finalizeTrack(hipsRot, loop, duration),
    ik: EFFECTORS.map((e) => {
      const E = ik[e];
      if (!E) return null;
      const hasPos = E.A.pos.times.length || E.B.pos.times.length;
      if (!hasPos) {
        // weight-only keys that all switch the effector off (w: 0 / null, e.g. `ik: { footL: { w: 0 } }` to leave a
        // pose's foot IK on FK): the effector is off in this clip. Pole-only keys stay: a hand that holds the weapon
        // grip (grip > 0) takes its elbow pole from them
        if (E.w.values.some((x) => x !== 0)) throw new Error('clip ' + def.name + ': IK ' + e + ' has a weight > 0 but no pos key');
        if (!E.pole.times.length) return null;
        return { origin: false, spaceB: 0, posA: null, rotA: null, posB: null, rotB: null, k: null, pole: finalizeTrack(E.pole, loop, duration), soft: null, w: null };
      }
      if (E.w.times.length === 0) return null;
      if (E.origin && root) { // root-space keys of an origin-space effector -> origin space (add the root motion at that key)
        const r2 = new Float32Array(2);
        E.A.space.forEach((sp, i) => {
          if (sp !== 0) return;
          sampleTrack(root, E.A.pos.times[i], r2, 0);
          E.A.pos.values[i * 3] += r2[0]; E.A.pos.values[i * 3 + 1] += r2[1];
        });
      }
      const fin = (tr, quat) => (tr.times.length ? finalizeTrack(tr, loop, duration, quat) : null);
      return {
        origin: E.origin, spaceB: E.spaceB,
        posA: fin(E.A.pos), rotA: fin(E.A.rot, true), posB: fin(E.B.pos), rotB: fin(E.B.rot, true),
        k: E.A.pos.times.length && E.B.pos.times.length ? fin(E.k) : null,
        pole: fin(E.pole),
        soft: fin(E.soft),
        w: finalizeTrack(E.w, loop, duration),
      };
    }),
    grip: grip && finalizeTrack(grip, loop, duration),
    look: look && finalizeTrack(look, loop, duration),
    lookW: lookW && finalizeTrack(lookW, loop, duration),
    curl: curl && finalizeTrack(curl, loop, duration),
    root,
  };
  c.rootEnd = [0, 0];
  if (c.root) sampleTrack(c.root, duration, c.rootEnd, 0);
  return c;
}

/** Compiled clip for a rig (cached). A registered pose name gives a looping hold of that pose. Throws on unknown names. */
export function getClip(rig, name) {
  let m = compiledByRig.get(rig);
  if (!m) compiledByRig.set(rig, (m = new Map()));
  let c = m.get(name);
  if (!c) {
    let def = rawClips.get(name);
    if (!def && rawPoses.has(name)) def = { name, duration: 1, loop: true, keys: [{ t: 0, pose: name }] }; // hold a pose
    if (!def) throw new Error('unknown clip ' + name);
    c = compile(rig, def);
    m.set(name, c);
  }
  return c;
}

/** Drop compiled caches (after re-defining clips or poses at runtime, e.g. while authoring in a lab). */
export function invalidateClips() {
  compiledByRig = new WeakMap();
}

// ---- pose ------------------------------------------------------------------------------------------------------
/** Evaluated pose buffer. */
export class Pose {
  constructor(rig) {
    this.lq = new Float32Array(rig.count * 4);
    this.lq.set(rig.restRot);
    this.hips = new Float32Array(3);        // hips offset (fighter frame, metres) added to the rest hips position
    this.ik = new Float32Array(EFFECTORS.length * EFF_STRIDE);
    this.grip = 0;
    this.look = new Float32Array(3);
    this.lookW = 0;
    this.curl = new Float32Array([0.25, 1]);
    this.root = new Float32Array(2);
    this.feet = new Float32Array(14);       // resolved sole point (3) + model rotation (4) per foot (R, L)
    this.feetIK = new Float32Array(2);      // IK weight of each foot (0 = FK leg)
    this.feetPole = new Float32Array(8);    // authored knee pole (model space, 3) + weight (1) per foot
    this.feetSoft = new Float32Array(2);    // soft reach per foot (-1 = rig default)
    this.gripT = new Float32Array([0, 0, 0, 0, 0, 0, 1]); // off-hand target in the main weapon frame: pos (3) + quat (4)
    this.gripW = new Float32Array(2);       // grip IK weight of the right / left hand
    this.gripLift = 0;                      // off hand moving between two grip points: 0..1 lift away from the torso
    this.gripM = new Float32Array([0, 0, 0, 0, 0, 0, 1]); // off-hand weapon-frame target in model space (pos + quat)
    this.gripMix = 1;                       // 1 = off hand on the weapon (gripT); < 1: on its way from gripM
    this.gripPole = new Float32Array(4);    // the gripping hand's keyed elbow pole (model space, 3) + weight (1)
    this.drop = 0;                          // automatic pelvis drop applied while resolving (m)
    this.clavBase = new Float32Array([0, 0, 0, 1, 0, 0, 0, 1]); // clavicle local rotations before the IK assist (R, L)
    this.clavBaseR = this.clavBase.subarray(0, 4); this.clavBaseL = this.clavBase.subarray(4, 8);
    this.aimErr = new Float32Array(2);      // weapon frame vs the keyed one after the wrist clamp (rad, R / L hand)
    this.footSlide = new Float32Array(2);   // horizontal move of an out-of-reach planted foot target (m, R / L)
    // arm IK memory (handR, handL, off-hand grip): MEM floats each (ik.js: last / this frame's elbow direction)
    this.swivel = new Float32Array(3 * SWIVEL_MEM);
    this.swivelR = this.swivel.subarray(0, SWIVEL_MEM); this.swivelL = this.swivel.subarray(SWIVEL_MEM, 2 * SWIVEL_MEM);
    this.swivelG = this.swivel.subarray(2 * SWIVEL_MEM, 3 * SWIVEL_MEM);
  }
  copy(p) {
    this.lq.set(p.lq); this.hips.set(p.hips); this.ik.set(p.ik); this.grip = p.grip;
    this.look.set(p.look); this.lookW = p.lookW; this.curl.set(p.curl); this.root.set(p.root); this.feet.set(p.feet);
    this.feetIK.set(p.feetIK); this.feetPole.set(p.feetPole); this.feetSoft.set(p.feetSoft);
    this.gripT.set(p.gripT); this.gripW.set(p.gripW); this.gripLift = p.gripLift; this.drop = p.drop;
    this.gripM.set(p.gripM); this.gripMix = p.gripMix; this.gripPole.set(p.gripPole);
    this.clavBase.set(p.clavBase); this.aimErr.set(p.aimErr); this.footSlide.set(p.footSlide);
    return this;
  }
}

const tmp4 = new Float32Array(4);
const tmpR = new Float32Array(2);
/**
 * Sample compiled clip `c` at time t into pose (FK bones not keyed keep their previous value: reset first). `scale`
 * multiplies every positional channel (hips offset, root motion, IK positions / poles, look target): retargets a clip
 * authored for one body size to another (Character.play(name, { scale })).
 */
export function sampleClip(rig, c, t, pose, scale = 1) {
  pose.lq.set(rig.restRot);
  for (const b of c.bones) {
    sampleTrack(b.tr, t, pose.lq, b.i * 4);
    qnormalize(pose.lq, b.i * 4);
  }
  if (c.hipsRot) {
    sampleTrack(c.hipsRot, t, tmp4, 0);
    eulerToQuat(pose.lq, 0, tmp4[0], tmp4[1], tmp4[2]);
  }
  if (c.hipsPos) sampleTrack(c.hipsPos, t, pose.hips, 0); else pose.hips.fill(0);
  if (c.root) sampleTrack(c.root, t, pose.root, 0); else pose.root.fill(0);
  const ik = pose.ik;
  ik.fill(0);
  for (let e = 0; e < EFFECTORS.length; e++) {
    const E = c.ik[e];
    if (!E) continue;
    const o = e * EFF_STRIDE;
    // the elbow / knee pole is sampled even while the effector is off: the grip solve of an off hand uses it
    if (E.pole) {
      sampleTrack(E.pole, t, ik, o + 9); ik[o + 12] = 1;
      if (scale !== 1) { ik[o + 9] *= scale; ik[o + 10] *= scale; ik[o + 11] *= scale; }
    }
    if (E.w) sampleTrack(E.w, t, ik, o);
    if (!(ik[o] > 1e-4)) { ik[o] = 0; continue; }
    if (E.posA) {
      sampleTrack(E.posA, t, ik, o + 1);
      if (E.origin) { ik[o + 1] -= pose.root[0]; ik[o + 2] -= pose.root[1]; }
      if (E.rotA) { sampleTrack(E.rotA, t, ik, o + 4); qnormalize(ik, o + 4); ik[o + 8] = 1; }
    }
    if (E.posB) {
      ik[o + 14] = E.spaceB;
      sampleTrack(E.posB, t, ik, o + 16);
      if (E.rotB) { sampleTrack(E.rotB, t, ik, o + 19); qnormalize(ik, o + 19); ik[o + 23] = 1; }
      if (E.k) { sampleTrack(E.k, t, tmpR, 0); ik[o + 15] = Math.max(0, Math.min(1, tmpR[0])); } else ik[o + 15] = 1;
    }
    if (E.soft) { sampleTrack(E.soft, t, ik, o + 13); } else ik[o + 13] = -1;
    if (scale !== 1) {
      for (const k of [1, 2, 3, 16, 17, 18]) ik[o + k] *= scale;
    }
  }
  if (scale !== 1) {
    pose.hips[0] *= scale; pose.hips[1] *= scale; pose.hips[2] *= scale;
    pose.root[0] *= scale; pose.root[1] *= scale;
  }
  if (c.grip) { sampleTrack(c.grip, t, tmpR, 0); pose.grip = Math.max(0, Math.min(1, tmpR[0])); } else pose.grip = 0;
  if (c.lookW) {
    sampleTrack(c.lookW, t, tmpR, 0); pose.lookW = Math.max(0, Math.min(1, tmpR[0]));
    if (c.look) { sampleTrack(c.look, t, pose.look, 0); if (scale !== 1) { pose.look[0] *= scale; pose.look[1] *= scale; pose.look[2] *= scale; } }
  } else pose.lookW = 0;
  if (c.curl) sampleTrack(c.curl, t, pose.curl, 0); else { pose.curl[0] = 0.25; pose.curl[1] = 1; }
  return pose;
}

// ---- built-in poses ---------------------------------------------------------------------------------------------
/** Relaxed standing pose (FK only): the default `base` of every clip. */
definePose('neutral', {
  bones: {
    spine: [0, 0, 0], chest: [0, 0, 0], neck: [0, 0, 0], head: [0, 0, 0],
    shoulderR: [0, 0, 0], shoulderL: [0, 0, 0],
    upperArmR: [-14, 6, 4], upperArmL: [-14, 6, 4],
    foreArmR: [0, -10, 16], foreArmL: [0, -10, 16],
    handR: [8, 0, 0], handL: [8, 0, 0],
    thighR: [-2, 0, 0], thighL: [-2, 0, 0], shinR: [0, 0, 0], shinL: [0, 0, 0], footR: [2, 0, 0], footL: [2, 0, 0],
  },
  curl: [0.25, 0.25],
});
