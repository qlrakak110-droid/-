// Camera director: fight framing, trauma shake / kicks / zoom, cinematic sequencer, letterbox.
//
//   const cam = createCameraDirector(ctx);          // -> ctx.cam, updates at ctx.ORDER.CAM
//   cam.setTargets(p1.sockets.chest, p2.sockets.chest);
//   cam.shake(0.35); cam.kick({ fov: -3 });
//   cam.play([shots.heroPushIn({ roll: 6, letterbox: true }), shots.impactPunchIn({ cut: true })], { anchor: 0 });
//
// Per frame: fight rig (always running, so it is warm when a cinematic hands back) -> sequencer (if playing) ->
// transition (hard cut, or inertial blend that carries the previous camera velocity) -> safety limits (z >= 0.5,
// above the floor) -> kicks, shake, handheld drift -> ctx.camera. See README.md.

import * as THREE from 'three';
import { clamp, lerp, DEG, Ease } from '../core/math.js';
import { Pose, orient, readPoint, softFloor, damp1 } from './pose.js';
import { defaultFight, createFightRig } from './framing.js';
import { createShaker, handheld } from './shake.js';
import { createSequencer } from './sequencer.js';

const smootherstep = (t) => t * t * t * (t * (t * 6 - 15) + 10);

/**
 * Create the camera director and store it on ctx.cam.
 * @param {object} ctx app context
 * @param {{seed?: number}} [opts] seed for the shake noise (default fixed, deterministic)
 */
export function createCameraDirector(ctx, opts = {}) {
  const camera = ctx.camera;
  const fight = defaultFight();
  const rig = createFightRig(fight);
  const shaker = createShaker(opts.seed ?? 0xca3e);
  const limits = { minZ: 0.5, minY: 0.12, knee: 0.4 };
  const targets = [null, null];
  const A = new THREE.Vector3(), B = new THREE.Vector3(), _p = new THREE.Vector3();

  const base = new Pose();
  const prev = new Pose();
  const vel = { pos: new THREE.Vector3(), look: new THREE.Vector3(), fov: 0, roll: 0, valid: false };
  const blend = { on: false, t: 0, T: 0, w: 1, tau: 0.15, src: new Pose(), vpos: new THREE.Vector3(), vlook: new THREE.Vector3(), vfov: 0, vroll: 0 };
  const view = { aspect: 16 / 9, letterbox: 0, zoom: 1, focusX: 0, focusW: 0, snap: false };
  const zoom = { factor: 1, left: 0, attack: 0.12, release: 0.3, focus: null, weight: 0.6, s: { v: 1, vel: 0 } };
  const lb = { on: false, from: 0, to: 0, t: 0, dur: 0.35 };
  const hand = { s: { v: fight.breathe, vel: 0 }, time: 0, out: { yaw: 0, pitch: 0, roll: 0 } };
  const quat = new THREE.Quaternion(), qShake = new THREE.Quaternion(), euler = new THREE.Euler(0, 0, 0, 'YXZ');
  const right = new THREE.Vector3(), up = new THREE.Vector3(), fwd = new THREE.Vector3();
  let free = false;
  let cutPending = false;
  let snapReq = true;     // jump the fight rig to its ideal and cut (start, cam.snap())
  let settleReq = false;  // jump the fight rig to its ideal without cutting (hand-back from a cinematic / free mode)
  /** A fighter index (0 / 1) or a point source -> point source. */
  const resolve = (s) => (typeof s === 'number' ? targets[s] : s);

  /** Final camera state of the last frame (read-only). */
  const state = { mode: 'fight', shot: -1, pos: new THREE.Vector3(), quat: new THREE.Quaternion(), look: base.look, fov: 40, roll: 0, blend: 1, cut: false };

  // ---- letterbox -----------------------------------------------------------------------------------------------
  function lbCurrent() { return ctx.post ? ctx.post.fx.letterbox : 0; }
  function letterboxTo(v, dur = 0.35) {
    lb.from = lbCurrent();
    lb.to = clamp(typeof v === 'number' ? v : v ? 1 : 0);
    lb.t = 0;
    lb.dur = Math.max(0, dur);
    lb.on = true;
    if (lb.dur === 0) stepLetterbox(0);
  }
  function stepLetterbox(dt) {
    if (!lb.on || !ctx.post) return;
    lb.t += dt;
    const k = lb.dur > 0 ? clamp(lb.t / lb.dur) : 1;
    ctx.post.fx.letterbox = lerp(lb.from, lb.to, Ease.inOutSine(k));
    if (k >= 1) lb.on = false;
  }

  const seq = createSequencer(ctx, {
    shaker, fight,
    letterboxTo,
    letterboxValue: () => (lb.on ? lb.to : lbCurrent()),
    stop: (b) => stop(b),
  });

  // ---- transitions ---------------------------------------------------------------------------------------------
  /** Blend from `from` (default: the last shown pose) to whatever comes next, over T real seconds (0 = cut). */
  function startBlend(T, from = prev, withVelocity = true) {
    if (!(T > 0)) { blend.on = false; cutPending = true; return; }
    blend.on = true;
    blend.t = 0; blend.T = T;
    blend.tau = clamp(T * 0.35, 0.04, 0.3);
    blend.src.copy(from);
    const v = withVelocity && vel.valid;
    blend.vpos.copy(vel.pos).multiplyScalar(v ? 1 : 0);
    blend.vlook.copy(vel.look).multiplyScalar(v ? 1 : 0);
    blend.vfov = v ? vel.fov : 0;
    blend.vroll = v ? vel.roll : 0;
  }

  /** Inertial blend: the source keeps drifting with its last velocity (decaying) while we ease toward `dest`. */
  function applyBlend(dest, dt, out) {
    blend.t += dt;
    const w = smootherstep(clamp(blend.t / blend.T));
    const g = blend.tau * (1 - Math.exp(-blend.t / blend.tau));
    const s = blend.src;
    _p.copy(s.pos).addScaledVector(blend.vpos, g);
    out.pos.lerpVectors(_p, dest.pos, w);
    _p.copy(s.look).addScaledVector(blend.vlook, g);
    out.look.lerpVectors(_p, dest.look, w);
    out.fov = lerp(s.fov + blend.vfov * g, dest.fov, w);
    out.roll = lerp(s.roll + blend.vroll * g, dest.roll, w);
    blend.w = w;
    if (blend.t >= blend.T) blend.on = false;
  }

  function readCameraPose(out) {
    out.pos.copy(camera.position);
    camera.getWorldDirection(_p);
    out.look.copy(camera.position).addScaledVector(_p, Math.max(2, camera.position.z));
    out.fov = camera.fov;
    out.roll = 0;
    return out;
  }

  // ---- per frame -----------------------------------------------------------------------------------------------
  function update(dtGame, dtReal) {
    const eb = ctx.env && ctx.env.bounds;
    if (eb) { fight.bounds.minX = eb.minX; fight.bounds.maxX = eb.maxX; }
    if (!readPoint(targets[0], A)) A.set(-2.5, fight.chestHeight, 0);
    if (!readPoint(targets[1], B)) B.set(2.5, fight.chestHeight, 0);
    // auto blend-out once the last shot has been shown in full (before the rig update, so it settles this frame)
    if (seq.ended) {
      const bo = seq.opts.blendOut;
      if (bo !== false && bo !== null) stop(bo ?? 0.5, true);
    }
    stepLetterbox(dtReal);

    // zoom envelope (critically damped in and out)
    zoom.left -= dtReal;
    const zOn = zoom.left > 0;
    damp1(zoom.s, zOn ? zoom.factor : 1, (zOn ? zoom.attack : zoom.release) * 0.5, dtReal);
    // the focus pull follows the zoom depth, so aim and dolly release together
    const depth = Math.abs(zoom.factor - 1) > 1e-3 ? clamp((zoom.s.v - 1) / (zoom.factor - 1)) : 0;
    view.focusW = zoom.focus != null && readPoint(resolve(zoom.focus), _p) ? zoom.weight * depth : 0;
    view.focusX = _p.x;

    view.aspect = camera.aspect;
    view.letterbox = lbCurrent();
    view.zoom = zoom.s.v;
    view.snap = snapReq || settleReq;
    const fightPose = rig.update(dtReal, A, B, view);
    if (snapReq) { cutPending = true; blend.on = false; }
    snapReq = settleReq = false;

    let dest = fightPose;
    if (seq.active) {
      dest = seq.update(dtGame, dtReal);
      const tr = seq.transition;
      if (tr) { if (tr.cut) { blend.on = false; cutPending = true; } else startBlend(tr.blend); }
    }
    const cut = cutPending;
    cutPending = false;
    if (blend.on && !cut) applyBlend(dest, dtReal, base);
    else { base.copy(dest); blend.w = 1; }

    base.pos.z = softFloor(base.pos.z, limits.minZ, limits.knee);
    base.pos.y = softFloor(base.pos.y, limits.minY, limits.knee * 0.5);

    // velocity of the shown (pre-shake) camera, for inertial blends
    if (cut || !(dtReal > 0)) { if (cut) { vel.valid = false; vel.pos.set(0, 0, 0); vel.look.set(0, 0, 0); vel.fov = vel.roll = 0; } }
    else {
      const k = vel.valid ? 0.6 : 1, inv = 1 / dtReal;
      vel.pos.lerp(_p.subVectors(base.pos, prev.pos).multiplyScalar(inv), k);
      vel.look.lerp(_p.subVectors(base.look, prev.look).multiplyScalar(inv), k);
      vel.fov = lerp(vel.fov, (base.fov - prev.fov) * inv, k);
      vel.roll = lerp(vel.roll, (base.roll - prev.roll) * inv, k);
      vel.valid = true;
    }
    prev.copy(base);

    // kicks, shake, handheld
    const handTarget = seq.active ? seq.handheld : fight.breathe;
    if (cut) { hand.s.v = handTarget; hand.s.vel = 0; } else damp1(hand.s, handTarget, 0.3, dtReal);
    hand.time += dtReal;
    orient(base.pos, base.look, base.roll, quat);
    right.set(1, 0, 0).applyQuaternion(quat);
    up.set(0, 1, 0).applyQuaternion(quat);
    fwd.set(0, 0, -1).applyQuaternion(quat);
    const sh = shaker.sample(dtReal, right, up, fwd);
    const hh = handheld(hand.time, hand.s.v, 0x4a11, hand.out);
    state.pos.copy(base.pos).addScaledVector(fwd, sh.push + sh.pz).addScaledVector(right, sh.px).addScaledVector(up, sh.py).add(sh.offset);
    state.pos.z = Math.max(limits.minZ, state.pos.z);
    state.pos.y = Math.max(limits.minY * 0.75, state.pos.y);
    euler.set(sh.pitch + hh.pitch, sh.yaw + hh.yaw, sh.roll + sh.kroll + hh.roll);
    state.quat.copy(quat).multiply(qShake.setFromEuler(euler));
    state.fov = clamp(base.fov + sh.fov, 5, 120);
    state.roll = base.roll;
    state.blend = blend.on ? blend.w : 1;
    state.cut = cut;
    state.shot = seq.index;
    state.mode = free ? 'free' : seq.active ? 'cine' : 'fight';

    if (!free) {
      camera.position.copy(state.pos);
      camera.quaternion.copy(state.quat);
      if (Math.abs(camera.fov - state.fov) > 1e-4) { camera.fov = state.fov; camera.updateProjectionMatrix(); }
      camera.updateMatrixWorld();
    }
  }

  // ---- public API ----------------------------------------------------------------------------------------------

  /** Stop any cinematic and blend back to fight framing over `blend` real seconds (0 = hard cut). */
  function stop(blendSec = 0.35, completed = false) {
    // the rig kept tracking (airborne phases, swaps) while hidden: hand back to its settled ideal, not its lag
    if (seq.active) { seq.finish(completed, blendSec); settleReq = true; }
    startBlend(blendSec);
  }

  const cam = {
    /** Framing parameters (live; see README). */
    fight,
    /** Safety limits applied to every camera: minZ (fight-line clearance), minY (floor clearance), knee (soft range). */
    limits,
    /** Shake amplitudes at trauma 1 and a global `scale` (accessibility). */
    shakeSettings: shaker.settings,
    /** Final camera state of the last frame. */
    state,
    /** Debug readout: fight rig values, the last shake sample and the pre-shake pose. */
    debug: { rig: rig.info, shake: shaker.out, base },

    get mode() { return state.mode; },
    get targets() { return targets; },

    /** Two things with a world position at chest height: Object3D, () => Vector3, Vector3 or [x,y,z]. */
    setTargets(a, b) { targets[0] = a; targets[1] = b; },

    /** Trauma shake on real time. See README for options. Returns {stop()}. */
    shake(amount, o) { return shaker.shake(amount, o); },

    /** Impulse kick: { fov, push, roll, offset, duration, attack, bounce }. Returns {stop()}. */
    kick(o) { return shaker.kick(o); },

    /**
     * Temporary push-in while in fight mode: distance x `factor` (0.8 = 20% closer) for `duration` real seconds.
     * o.focus: fighter index / point source to lean the framing toward (weight o.weight, default 0.6).
     */
    zoom(factor, duration = 0.6, o = {}) {
      zoom.factor = clamp(factor, 0.3, 3);
      zoom.attack = o.attack ?? 0.12;
      zoom.release = o.release ?? 0.3;
      zoom.left = Math.max(0, duration - zoom.release);
      zoom.focus = o.focus ?? null;
      zoom.weight = o.weight ?? 0.6;
    },

    /**
     * Play a cinematic. shots: array of shot objects (see README / shots.js). opts: anchor (index | point source,
     * default 0), target (default: the other fighter), facing (+1 | -1, default: toward the target), onDone(completed),
     * onShot(i, shot), blendOut (real s back to fight framing, default 0.5; false = hold the last frame until stop()),
     * clock ('game' | 'real' default for shots), keepLetterbox, hud (default true: ui.hud.cinematic on / off).
     */
    play(shots, o = {}) {
      const anchor = resolve(o.anchor ?? 0);
      const target = resolve(o.target ?? (anchor === targets[1] ? 0 : 1));
      let facing = o.facing;
      if (facing !== 1 && facing !== -1) {
        const ok = readPoint(anchor, A) && readPoint(target, B);
        facing = ok && B.x < A.x ? -1 : 1;
      }
      const hud = o.hud !== false;
      const onDone = o.onDone;
      if (hud && ctx.ui && ctx.ui.hud && ctx.ui.hud.cinematic) ctx.ui.hud.cinematic(true);
      ctx.events.emit('cam:cine', true);
      return seq.play(shots, {
        ...o, anchor, target, facing,
        onDone(completed) {
          if (hud && ctx.ui && ctx.ui.hud && ctx.ui.hud.cinematic) ctx.ui.hud.cinematic(false);
          ctx.events.emit('cam:cine', false);
          if (onDone) onDone(completed);
        },
      });
    },

    stop,

    /** Animate post.fx.letterbox to `on` (true / false / 0..1) over `dur` real seconds. */
    letterbox(on, dur = 0.35) { letterboxTo(on, dur); },

    /**
     * 'free' hands ctx.camera to someone else (photo mode, lab orbit); the director keeps computing `state`.
     * Leaving 'free' blends from wherever the camera was over `blendSec`.
     */
    setMode(m, blendSec = 0.5) {
      const wasFree = free;
      free = m === 'free';
      if (wasFree && !free) { settleReq = true; startBlend(blendSec, readCameraPose(blend.src), false); }
    },

    /** Jump the fight framing to its ideal now (round start, after a teleport): no smoothing, treated as a cut. */
    snap() { snapReq = true; },

    /** Stop shakes, kicks and zoom (round reset). */
    clearFx() { shaker.clear(); zoom.left = 0; zoom.s.v = 1; zoom.s.vel = 0; },

    /** Remove the per-frame update. */
    dispose() { off(); if (ctx.cam === cam) ctx.cam = null; },
  };

  const off = ctx.onUpdate(update, ctx.ORDER.CAM);
  ctx.cam = cam;
  return cam;
}
