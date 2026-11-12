// Clip registry and sampler. Clips and poses are plain data; they are compiled lazily per rig into keyed tracks and
// sampled into a Pose (local rotations + hips + IK goals + grip / look / curl / root motion). See README.md for the
// exact key format and the bone axis conventions.

import { ease as resolveEase } from '../core/math.js';
import { eulerToQuat, computeTangents, sampleTrack, qnormalize } from './rigmath.js';

const rawClips = new Map();
const rawPoses = new Map();
let compiledByRig = new WeakMap();

/** IK effectors in Pose.ik order. */
export const EFFECTORS = ['handR', 'handL', 'footR', 'footL'];
// per effector: w, posA(3), quatA(4), hasRotA, pole(3), hasPole, -, spaceB, k, posB(3), quatB(4), hasRotB
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

function mirrorChannels(k) {
  const o = { ...k };
  if (k.bones) {
    o.bones = {};
    for (const [b, v] of Object.entries(k.bones)) {
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
      o.ik[swapName(e)] = v && { ...v, pos: negS(v.pos), pole: negS(v.pole), aim: negS(v.aim), up: negS(v.up), rot: mirE(v.rot) };
    }
  }
  if (k.look) o.look = { ...k.look, at: negS(k.look.at) };
  if (k.curl) o.curl = [k.curl[1], k.curl[0]];
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
 * Register `dst` as the mirror image of clip `src` (left <-> right swapped, side axis negated).
 * opts.events: optional map { srcEventName: dstEventName }.
 */
export function mirrorClip(src, dst, opts = {}) {
  const d = rawClips.get(src);
  if (!d) throw new Error('mirrorClip: unknown clip ' + src);
  const m = {
    ...d, name: dst,
    mainHand: d.mainHand === 'L' ? 'R' : 'L',
    gripHand: (d.gripHand || 'L') === 'L' ? 'R' : 'L',
    keys: d.keys.map((k) => mirrorChannels(resolveKey(k))),
    base: d.base ? { mirrorOf: d.base } : { mirrorOf: 'neutral' },
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
function newTrack(dim) { return { n: 0, dim, times: [], values: [], eases: [], modes: [], _last: 0 }; }
const MODES = { auto: 0, smooth: 0, linear: 1, step: 2 };

function pushKey(tr, t, vals, ease, mode) {
  tr.times.push(t);
  for (const v of vals) tr.values.push(v);
  tr.eases.push(resolveEase(ease || 'linear'));
  tr.modes.push(MODES[mode || 'auto'] ?? 0);
}

function finalizeTrack(tr, loop, duration, isQuat) {
  // loops: close the cycle with a copy of the first key at t = duration
  if (loop && tr.times.length && tr.times[tr.times.length - 1] < duration - 1e-6) {
    tr.times.push(duration);
    for (let d = 0; d < tr.dim; d++) tr.values.push(tr.values[d]);
    tr.eases.push(tr.eases[0]);
    tr.modes.push(tr.modes[0]);
  }
  tr.n = tr.times.length;
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
  // quaternion from basis columns (aim, up, z)
  const m00 = ax, m10 = ay, m20 = az, m01 = ux, m11 = uy, m21 = uz, m02 = zx, m12 = zy, m22 = zz;
  const tr = m00 + m11 + m22;
  if (tr > 0) { const s = 0.5 / Math.sqrt(tr + 1); out[3] = 0.25 / s; out[0] = (m21 - m12) * s; out[1] = (m02 - m20) * s; out[2] = (m10 - m01) * s; }
  else if (m00 > m11 && m00 > m22) { const s = 2 * Math.sqrt(1 + m00 - m11 - m22); out[3] = (m21 - m12) / s; out[0] = 0.25 * s; out[1] = (m01 + m10) / s; out[2] = (m02 + m20) / s; }
  else if (m11 > m22) { const s = 2 * Math.sqrt(1 + m11 - m00 - m22); out[3] = (m02 - m20) / s; out[0] = (m01 + m10) / s; out[1] = 0.25 * s; out[2] = (m12 + m21) / s; }
  else { const s = 2 * Math.sqrt(1 + m22 - m00 - m11); out[3] = (m10 - m01) / s; out[0] = (m02 + m20) / s; out[1] = (m12 + m21) / s; out[2] = 0.25 * s; }
  qnormalize(out, 0);
  return out;
}

function baseKeyOf(base) {
  if (!base) return {};
  if (typeof base === 'object' && base.mirrorOf) return mirrorChannels(baseKeyOf(base.mirrorOf));
  if (typeof base === 'object') return resolveKey(base);
  if (rawPoses.has(base)) return resolveKey({ pose: base });
  if (rawClips.has(base)) return resolveKey(rawClips.get(base).keys[0]);
  throw new Error('unknown base pose/clip ' + base);
}

function compile(rig, def) {
  const duration = Math.max(1e-3, def.duration ?? def.keys[def.keys.length - 1].t ?? 1);
  const loop = !!def.loop;
  const keys = def.keys.map(resolveKey).sort((a, b) => (a.t ?? 0) - (b.t ?? 0));
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
        const r = Array.isArray(v) ? v : v.r;
        if (!boneTracks.has(i)) boneTracks.set(i, newTrack(4));
        const tr = boneTracks.get(i);
        if (isBase && tr.times.length) continue;
        eulerToQuat(q, 0, r[0] || 0, r[1] || 0, r[2] || 0, rig.side[i] < 0);
        pushKey(tr, t, q, (!Array.isArray(v) && v.ease) || ke, (!Array.isArray(v) && v.interp) || km);
      }
    }
    if (k.hips) addHips(k.hips, t, ke, km);
    if (k.ik) {
      for (const [e, v] of Object.entries(k.ik)) {
        if (!EFFECTORS.includes(e)) throw new Error('clip ' + def.name + ': unknown IK effector ' + e);
        if (!ik[e]) {
          ik[e] = { A: { pos: newTrack(3), rot: newTrack(4), space: [] }, B: { pos: newTrack(3), rot: newTrack(4) }, pole: newTrack(3), w: newTrack(1), k: newTrack(1), origin: false, spaceB: 0 };
        }
        const E = ik[e];
        const ee = (v && v.ease) || ke, em = (v && v.interp) || km;
        if (!v || v.w === 0) { pushKey(E.w, t, [0], ee, em); continue; }
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
    breath: def.breath ?? 1, lookEnabled: def.look !== false,
    bones: [...boneTracks].map(([i, tr]) => ({ i, tr: finalizeTrack(tr, loop, duration, true) })),
    hipsPos: hipsPos && finalizeTrack(hipsPos, loop, duration),
    hipsRot: hipsRot && finalizeTrack(hipsRot, loop, duration),
    ik: EFFECTORS.map((e) => {
      const E = ik[e];
      if (!E || E.w.times.length === 0) return null;
      if (!E.A.pos.times.length && !E.B.pos.times.length) throw new Error('clip ' + def.name + ': IK ' + e + ' has no pos key');
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
  }
  copy(p) {
    this.lq.set(p.lq); this.hips.set(p.hips); this.ik.set(p.ik); this.grip = p.grip;
    this.look.set(p.look); this.lookW = p.lookW; this.curl.set(p.curl); this.root.set(p.root); this.feet.set(p.feet);
    return this;
  }
}

const tmp4 = new Float32Array(4);
const tmpR = new Float32Array(2);

/** Sample compiled clip `c` at time t into pose (FK bones not keyed keep their previous value: reset first). */
export function sampleClip(rig, c, t, pose) {
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
    sampleTrack(E.w, t, ik, o);
    if (ik[o] <= 1e-4) { ik[o] = 0; continue; }
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
    if (E.pole) { sampleTrack(E.pole, t, ik, o + 9); ik[o + 12] = 1; }
  }
  if (c.grip) { sampleTrack(c.grip, t, tmpR, 0); pose.grip = Math.max(0, Math.min(1, tmpR[0])); } else pose.grip = 0;
  if (c.lookW) { sampleTrack(c.lookW, t, tmpR, 0); pose.lookW = Math.max(0, Math.min(1, tmpR[0])); if (c.look) sampleTrack(c.look, t, pose.look, 0); } else pose.lookW = 0;
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
