// The stage frame (README §6.5). The fighters' choreography and the whole VFX preset library were authored on the
// duel's fight line: the fighter at (x, 0, 0) facing +X or -X, effects oriented with `facing: ±1`, the camera on +Z.
// In the RPG a hero faces any yaw. Instead of re-authoring every effect, a *stage frame* — a rigid transform
// (position on the floor + yaw) between that virtual fight line and the world — is active while choreography runs:
//
//   * stage space: the actor stands at the origin facing +X, its right is +Z (the old camera side), +Y is up;
//   * while the mode runs, every ctx.vfx primitive is wrapped: with a frame active, positions, directions, plane
//     normals and point sources are mapped stage -> world on the way in (and Object3D proxies are unwrapped);
//     `vfx.play` (presets: stage-native code) runs inside the frame and its group remembers it, so everything the
//     preset schedules or runs later (scheduler, motion anchors, impact() ...) is back in the same frame;
//   * with no frame active the wrappers pass straight through (world space, as in the duel).
//
//   withStage(actor, () => ctx.vfx.play('ember.eruption', { pos: [3, 0, 0] }, { k: 1 }));
//   const f = actorFrame(actor); withFrame(f, fn); stageToWorld(v, f); worldToStage(v, f);
//
// Not covered (documented in the README): particle *definitions* with a horizontal `vel` / `gravity` vector keep their
// stage axes (definitions are shared GPU rows; only per-spawn values are rotated).

import * as THREE from 'three';
import { planeQuat } from '../../vfx/meshfx.js';

let cur = null;
const Y = new THREE.Vector3(0, 1, 0);
const _q = new THREE.Quaternion(), _qy = new THREE.Quaternion();
const gwp = THREE.Object3D.prototype.getWorldPosition;

/** A frame: stage origin (x, z) on the floor and the yaw of stage +X. */
export function makeFrame(x, z, yaw, out = {}) {
  out.x = x; out.z = z; out.yaw = yaw; out.c = Math.cos(yaw); out.s = Math.sin(yaw); out.node = null;
  return out;
}
/** The frame of an actor right now (a new snapshot). `toward`: aim stage +X at a world point instead of its facing. */
export function actorFrame(a, toward) {
  let yaw = a.view ? a.yaw : a.yaw;
  if (toward) {
    const dx = toward.x - a.pos.x, dz = toward.z - a.pos.z;
    if (dx * dx + dz * dz > 0.09) yaw = Math.atan2(-dz, dx);
  }
  return makeFrame(a.pos.x, a.pos.z, yaw);
}
export function stageToWorld(v, f, out = v) {
  const x = v.x, z = v.z;
  out.x = f.x + x * f.c + z * f.s; out.y = v.y; out.z = f.z - x * f.s + z * f.c;
  return out;
}
export function worldToStage(v, f, out = v) {
  const dx = v.x - f.x, dz = v.z - f.z;
  out.x = dx * f.c - dz * f.s; out.y = v.y; out.z = dx * f.s + dz * f.c;
  return out;
}
export function dirToWorld(v, f, out = v) {
  const x = v.x, z = v.z;
  out.x = x * f.c + z * f.s; out.y = v.y; out.z = -x * f.s + z * f.c;
  return out;
}
/** The active frame (null outside choreography). */
export const currentFrame = () => cur;
/** Run fn with `frame` active (null = force world space). */
export function withFrame(frame, fn) {
  const prev = cur;
  cur = frame;
  try { return fn(); } finally { cur = prev; }
}
/** Run fn in the stage frame of an actor. */
export function withStage(actor, fn) { return withFrame(actorFrame(actor), fn); }

/** Scene node carrying a frame's transform: stage-space Object3Ds (preset anchors) are parented to it. */
function frameNode(f) {
  if (!f.node) {
    const n = new THREE.Object3D();
    n.isStageNode = true;
    n.position.set(f.x, 0, f.z);
    n.rotation.y = f.yaw;
    n.updateMatrixWorld(true);
    f.node = n;
  }
  return f.node;
}

// ---- proxies ----------------------------------------------------------------------------------------------------
const proxies = new WeakMap();
/**
 * A stand-in for a scene object (socket, character root) handed to choreography: every read goes to the real object,
 * except getWorldPosition(), which answers in stage space while a frame is active.
 */
export function proxy(obj) {
  if (!obj || !obj.isObject3D || obj.__real) return obj;
  let p = proxies.get(obj);
  if (!p) {
    p = Object.create(obj);
    p.__real = obj;
    p.getWorldPosition = function (out) { gwp.call(obj, out); return cur ? worldToStage(out, cur, out) : out; };
    proxies.set(obj, p);
  }
  return p;
}
export const unwrap = (o) => (o && o.__real ? o.__real : o);
/** Proxy map of a socket table. */
export function proxySockets(sockets) {
  const out = {};
  for (const k in sockets) out[k] = proxy(sockets[k]);
  return out;
}

function stageGwp(out) { gwp.call(this, out); return cur ? worldToStage(out, cur, out) : out; }
/** A stage-space object (unparented preset anchor / projectile marker): hang it under the frame node. */
function adopt(obj) {
  if (obj.parent && !obj.parent.isStageNode) return obj;
  if (!cur) {
    if (obj.parent) { obj.removeFromParent(); delete obj.getWorldPosition; obj.updateMatrixWorld(true); }
    return obj;
  }
  const node = frameNode(cur);
  if (obj.parent !== node) { node.add(obj); obj.getWorldPosition = stageGwp; obj.updateMatrixWorld(true); }
  return obj;
}

// ---- value conversion -------------------------------------------------------------------------------------------
const isVecLike = (v) => v && (v.isVector3 || Array.isArray(v) || ArrayBuffer.isView(v) || (typeof v === 'object' && typeof v.x === 'number' && !v.isObject3D));
function toV(v, out) {
  if (v.isVector3) return out.copy(v);
  if (Array.isArray(v) || ArrayBuffer.isView(v)) return out.set(+v[0] || 0, +v[1] || 0, +v[2] || 0);
  return out.set(+v.x || 0, +v.y || 0, +v.z || 0);
}
/** A function-valued point source: evaluated in the frame it was given in, result mapped to the world. */
function liveSource(fn, f) {
  const out = new THREE.Vector3();
  return () => {
    const prev = cur;
    cur = f;
    let r;
    try { r = fn(out); } finally { cur = prev; }
    if (r == null) r = out;
    if (r.isObject3D) return unwrap(r);
    toV(r, out);
    return stageToWorld(out, f, out);
  };
}
/** Position-like value -> world (objects are unwrapped / adopted, functions wrapped). */
function pt(v) {
  if (v == null) return v;
  if (typeof v === 'function') return cur ? liveSource(v, cur) : v;
  if (v.isObject3D) return adopt(unwrap(v));
  if (!cur || !isVecLike(v)) return v;
  return stageToWorld(toV(v, new THREE.Vector3()), cur);
}
function dv(v) {
  if (v == null || !cur || !isVecLike(v)) return v;
  return dirToWorld(toV(v, new THREE.Vector3()), cur);
}
const POINTS = ['pos', 'from', 'to', 'a', 'b', 'target'];
const DIRS = ['dir', 'normal', 'vel', 'side', 'drift'];
/** Shallow copy of an options / at object with every positional field mapped to the world. */
function conv(o) {
  if (o == null) return o;
  if (o.isVector3 || Array.isArray(o)) return pt(o);
  if (o.isObject3D) return adopt(unwrap(o));
  if (typeof o !== 'object') return o;
  let out = null;
  const put = (k, v) => { if (v !== o[k]) { if (!out) out = { ...o }; out[k] = v; } };
  for (let i = 0; i < POINTS.length; i++) { const k = POINTS[i]; if (o[k] != null) put(k, pt(o[k])); }
  if (o.follow != null) put('follow', pt(o.follow));
  if (cur) {
    for (let i = 0; i < DIRS.length; i++) { const k = DIRS[i]; if (o[k] != null) put(k, dv(o[k])); }
    // an offset is local to a followed Object3D; with a function / point target it is a stage-space vector
    if (o.offset != null && !(o.follow && o.follow.isObject3D)) put('offset', dv(o.offset));
  }
  return out || o;
}

/** Wrap follow / setPosition / setEnds / setSockets of a spawn handle created inside frame f. */
function wrapHandle(h, f) {
  if (!h || typeof h !== 'object' || h.__stage) return h;
  let any = false;
  const wrap = (name, n) => {
    const orig = h[name];
    if (typeof orig !== 'function') return;
    any = true;
    h[name] = (...args) => {
      const fr = cur || f;
      const prev = cur;
      cur = fr;
      try {
        for (let i = 0; i < n; i++) args[i] = pt(args[i]);
        if (name === 'follow' && args[1] != null && !(args[0] && args[0].isObject3D)) args[1] = dv(args[1]);
      } finally { cur = prev; }
      return world(() => orig.apply(h, args));
    };
  };
  wrap('follow', 1); wrap('setPosition', 1); wrap('setEnds', 2); wrap('setSockets', 2);
  if (any) { try { h.__stage = true; } catch (e) { /* frozen handle */ } }
  return h;
}
/** Run fn in world space (frame suspended): the original primitives and whatever they spawn / schedule themselves. */
function world(fn) {
  const prev = cur;
  cur = null;
  try { return fn(); } finally { cur = prev; }
}

// ---- the vfx wrappers ---------------------------------------------------------------------------------------------
const ONE_ARG = ['trail', 'ribbon', 'light', 'flare', 'distort', 'ring', 'pillar', 'beam', 'bolt', 'debris', 'decal', 'speedlines'];

/**
 * Wrap the primitives of a vfx facade. Returns uninstall().
 * @param {object} vfx ctx.vfx
 */
export function installStage(vfx) {
  if (!vfx || vfx.__stageInstalled) return () => {};
  const orig = {};
  const groupFrames = new WeakMap();
  const keep = (name) => { orig[name] = vfx[name]; return typeof orig[name] === 'function'; };

  for (const name of ONE_ARG) {
    if (!keep(name)) continue;
    const fn = orig[name];
    vfx[name] = (o) => {
      const f = cur;
      let c = conv(o);
      if (f && name === 'ring' && c && (c.quat != null || c.forward != null)) c = planeOpts(c, f, [0, 0, 1]);
      if (f && name === 'decal' && c && typeof c.rotation === 'number') { if (c === o) c = { ...o }; c.rotation = o.rotation + f.yaw; }
      if (f && name === 'speedlines' && c && c !== o && o.dir != null) c.dir = o.dir;   // a screen direction
      const h = world(() => fn.call(vfx, c));
      return f ? wrapHandle(h, f) : h;
    };
  }
  if (keep('slash')) {
    const fn = orig.slash;
    vfx.slash = (o) => {
      const f = cur;
      let c = conv(o);
      if (f && c) c = planeOpts(c === o ? { ...o } : c, f, [0, 0, 1], true);
      const h = world(() => fn.call(vfx, c));
      return f ? wrapHandle(h, f) : h;
    };
  }
  if (keep('spikes')) {
    const fn = orig.spikes;
    vfx.spikes = (o) => {
      const f = cur;
      let c = conv(o);
      if (f && c) {
        if (c === o) c = { ...o };
        // line direction: default +X, mirrored by facing, then into the world
        const d = toV(o.dir || [1, 0, 0], new THREE.Vector3());
        if (o.facing != null && o.facing < 0) d.x = -d.x;
        c.dir = dirToWorld(d, f);
        c.facing = 1;
      }
      const h = world(() => fn.call(vfx, c));
      return f ? wrapHandle(h, f) : h;
    };
  }
  /** burst / emitter: at + the definition's default axis */
  const atOf = (def, at) => {
    const f = cur;
    let c = conv(at);
    if (!f) return c;
    if (c == null) return c;
    if (c.isVector3) return c;
    if (c === at) c = { ...at };
    if (at.dir == null && def && typeof def === 'object' && def.dir && (def.dir[0] || def.dir[2])) c.dir = dv(def.dir);
    if (at.side == null) c.side = dirToWorld(new THREE.Vector3(1, 0, 0), f);
    return c;
  };
  if (keep('burst')) { const fn = orig.burst; vfx.burst = (def, at) => { const c = atOf(def, at); return world(() => fn.call(vfx, def, c)); }; }
  if (keep('emitter')) {
    const fn = orig.emitter;
    vfx.emitter = (def, at) => { const f = cur; const c = atOf(def, at); const h = world(() => fn.call(vfx, def, c)); return f ? wrapHandle(h, f) : h; };
  }
  if (keep('afterimage')) {
    const fn = orig.afterimage;
    vfx.afterimage = (obj, o) => { const c = conv(o); const r = unwrap(obj); return world(() => fn.call(vfx, r, c)); };
  }
  if (keep('schedule')) {
    const fn = orig.schedule;
    // a callback runs in the frame it was scheduled in (null included: what a primitive schedules is world space)
    vfx.schedule = (delay, cb, opts) => { const f = cur; return fn.call(vfx, delay, (v) => withFrame(f, () => cb(v)), opts); };
  }
  if (keep('play')) {
    const fn = orig.play;
    vfx.play = (name, at, opts) => {
      const g = fn.call(vfx, name, at, opts);
      if (cur && g && typeof g === 'object') groupFrames.set(g, cur);
      return g;
    };
  }
  // everything a preset group runs later (scheduler, motion anchors, impact() / stop() of its API) is back in its frame
  const shared = vfx.shared;
  const runInGroup = shared && shared.runInGroup;
  if (runInGroup) {
    shared.runInGroup = (group, fn) => {
      const f = group ? groupFrames.get(group) : undefined;
      if (f === undefined) return runInGroup.call(shared, group, fn);
      return withFrame(f, () => runInGroup.call(shared, group, fn));
    };
  }
  vfx.__stageInstalled = true;
  return function uninstall() {
    for (const k in orig) vfx[k] = orig[k];
    if (runInGroup) shared.runInGroup = runInGroup;
    vfx.__stageInstalled = false;
    cur = null;
  };
}

/** Resolve a planar effect's orientation in stage space and hand the primitive a world quaternion. */
function planeOpts(c, f, defNormal, always = false) {
  // the caller already mapped normal / dir fields to the world: undo that by resolving from the original stage values
  const src = { quat: c.quat, normal: c.__n, forward: c.forward, roll: c.roll, facing: c.facing };
  void always;
  // `conv` rotated `normal` (a DIRS key) but not `forward`: bring the normal back to stage space for planeQuat
  if (c.normal != null) { const n = toV(c.normal, new THREE.Vector3()); src.normal = [n.x * f.c - n.z * f.s, n.y, n.x * f.s + n.z * f.c]; }
  planeQuat(src, _q, defNormal);
  _qy.setFromAxisAngle(Y, f.yaw);
  const out = { ...c, quat: _qy.clone().multiply(_q) };
  delete out.normal; delete out.forward; delete out.roll; out.facing = 1;
  return out;
}
