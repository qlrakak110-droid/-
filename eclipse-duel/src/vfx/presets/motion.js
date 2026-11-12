// Pooled moving anchors for presets: projectiles, falling meteors and star lances, travelling ground fronts. Each anchor
// is an Object3D (never added to the scene) that the preset's layers follow (emitters, flares, lights, ribbons,
// slashes, beam ends ...). An anchor moves along a path (eased), with a velocity (+ gravity) or follows a target, on
// game or real time; it calls onStep every frame and onEnd once when its path or life completes. Callbacks run inside
// the preset group that started the anchor, so whatever they spawn is killed with the group.

import * as THREE from 'three';
import { ease as resolveEase } from '../../core/math.js';
import { toVec3 } from '../util.js';
import { vec } from './common.js';

const N = 24;

/**
 * @param {object} shared  vfx shared resources (clock, track, currentGroup, runInGroup)
 */
export function createMotion(shared) {
  const { clock } = shared;
  const recs = [];
  for (let i = 0; i < N; i++) {
    recs.push({
      obj: new THREE.Object3D(), live: false, serial: 0, mode: 0, t0: 0, life: 0, rt: false,
      from: new THREE.Vector3(), to: new THREE.Vector3(), vel: new THREE.Vector3(), offset: new THREE.Vector3(), prev: new THREE.Vector3(),
      gravity: 0, ease: null, follow: null, onStep: null, onEnd: null, group: null, dist: 0, age: 0, dt: 0, step: null,
    });
  }
  // per-record step callback built once (no closure allocated per frame)
  for (const r of recs) r.step = () => r.onStep(r, r.dt);
  let serial = 1;

  function free(r) { r.live = false; r.serial = 0; r.onStep = r.onEnd = r.follow = null; r.group = null; }

  /**
   * Start an anchor. o = { pos, to?, dur?, ease?  (path)  |  vel?, gravity?  (ballistic)  |  follow?, offset? (tracking),
   * life (s, path: dur), realtime, onStep(rec, dt), onEnd(rec) }. Returns a handle { obj, pos, alive, kill(), stop() }.
   */
  function start(o) {
    let r = null;
    for (const x of recs) if (!x.live) { r = x; break; }
    if (!r) { r = recs[0]; for (const x of recs) if (x.t0 < r.t0) r = x; free(r); }
    r.live = true;
    r.serial = serial++;
    r.rt = !!o.realtime;
    r.t0 = r.rt ? clock.real : clock.game;
    r.age = 0;
    r.dist = 0;
    toVec3(o.pos, r.from);
    r.obj.position.copy(r.from);
    r.prev.copy(r.from);
    r.follow = o.follow || null;
    if (o.offset) toVec3(o.offset, r.offset); else r.offset.set(0, 0, 0);
    if (r.follow) { r.mode = 2; r.life = o.life != null ? o.life : Infinity; place(r); }
    else if (o.to != null) { r.mode = 0; toVec3(o.to, r.to); r.life = Math.max(1e-3, o.dur != null ? o.dur : 0.5); r.ease = resolveEase(o.ease || 'linear'); }
    else { r.mode = 1; toVec3(o.vel, r.vel); r.gravity = o.gravity || 0; r.life = o.life != null ? o.life : 1; }
    r.obj.updateMatrixWorld(true);
    r.onStep = o.onStep || null;
    r.onEnd = o.onEnd || null;
    r.group = shared.currentGroup();
    const my = r.serial;
    const h = {
      obj: r.obj,
      get pos() { return r.obj.position; },
      get alive() { return r.live && r.serial === my; },
      /** remove now (no onEnd) */
      kill() { if (r.live && r.serial === my) free(r); },
      /** same as kill: an anchor has nothing to finish */
      stop() { h.kill(); },
      /** current velocity estimate (m/s), written into out */
      velocity(out) { return r.mode === 1 ? out.copy(r.vel) : out.copy(r.obj.position).sub(r.prev).multiplyScalar(60); },
    };
    shared.track(h);
    return h;
  }

  function place(r) {
    const f = r.follow;
    if (f.isObject3D) { f.updateWorldMatrix(true, false); r.obj.position.copy(r.offset).applyMatrix4(f.matrixWorld); }
    else toVec3(f, r.obj.position).add(r.offset);
  }

  function step(r, dt) {
    r.prev.copy(r.obj.position);
    r.age += dt;
    const p = r.obj.position;
    if (r.mode === 0) {
      const t = Math.min(1, r.age / r.life);
      p.copy(r.from).lerp(r.to, r.ease(t));
    } else if (r.mode === 1) {
      r.vel.y += r.gravity * dt;
      p.addScaledVector(r.vel, dt);
    } else place(r);
    r.dist += r.prev.distanceTo(p);
    r.obj.updateMatrixWorld(true);
  }

  return {
    start,
    update(dtGame, dtReal) {
      for (const r of recs) {
        if (!r.live) continue;
        const dt = r.rt ? dtReal : dtGame;
        if (dt <= 0) continue;
        step(r, dt);
        const my = r.serial;
        r.dt = dt;
        if (r.onStep) shared.runInGroup(r.group, r.step);
        if (r.serial !== my || !r.live) continue;
        if (r.age >= r.life) {
          const end = r.onEnd, g = r.group;
          free(r);
          if (end) shared.runInGroup(g, () => end(r));
        }
      }
    },
    clear() { for (const r of recs) free(r); },
  };
}

/**
 * Launch a projectile body on a pooled anchor and return the preset API { pos, anchor, impact(p?, dir?), stop() }.
 *   spec = { speed, life, body(anchor) -> handles[], impact(pos, dir), fizzle?(pos), onStep?(rec, dt) }
 * The anchor follows opts.follow / an Object3D or function in at.target (game-driven projectile), flies to opts.to and
 * impacts there, or flies along at.dir at spec.speed until its life ends (then fizzles).
 */
export function launch(v, motion, at, o, spec) {
  const tgt = at.target && (at.target.isObject3D || typeof at.target === 'function') ? at.target : null;
  const follow = o.follow || tgt;
  const speed = (o.speed != null ? o.speed : spec.speed) * at.scale;
  let m;
  const base = { pos: at.pos, realtime: v.realtime, onStep: spec.onStep };
  if (follow) m = motion.start({ ...base, follow, life: o.life != null ? o.life : Infinity, onEnd: () => end(false) });
  else if (o.to != null) {
    const to = vec(o.to);
    m = motion.start({ ...base, to, dur: Math.max(0.02, to.distanceTo(at.pos) / speed), onEnd: () => end(true, to) });
  } else m = motion.start({ ...base, vel: at.dir.clone().multiplyScalar(speed), life: o.life != null ? o.life : spec.life, onEnd: () => end(false) });
  const body = spec.body(m.obj);
  let done = false;
  function end(hit, p, d) {
    if (done) return;
    done = true;
    const at2 = p ? vec(p) : m.obj.position.clone();
    for (const h of body) if (h) { if (h.stop) h.stop(); else h.kill(); }
    m.kill();
    if (hit) spec.impact(at2, d ? vec(d).normalize() : at.dir);
    else if (spec.fizzle) spec.fizzle(at2);
  }
  return {
    /** live position of the projectile (Vector3) */
    get pos() { return m.obj.position; },
    /** the Object3D the body follows */
    get anchor() { return m.obj; },
    /** burst on impact at p (default: current position) along dir (default: travel direction); ends the body */
    impact(p, d) { end(true, p, d); },
    /** dissipate without an impact */
    stop() { end(false); },
  };
}
