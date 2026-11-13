// Third-person camera of the RPG mode (README §10): follows the hero from behind the shoulder, free look, lock-on with
// target switching, boom collision against the arena wall and colliders, boss framing, shake / kick from ctx.cam,
// and cinematic hand-over to src/cam shot lists (run in a stage frame, mapped into the world here), then back.
//
//   const cam = createRpgCamera(ctx, world);      world.camera
//   cam.update(dtGame, dtReal)                    ORDER.CAM + 1 (the director is in 'free' mode and only computes)

import * as THREE from 'three';
import { clamp } from '../core/math.js';
import { angDiff, fwdX, fwdZ, hypot2, rightX, rightZ, wrapPi, yawTo } from './core/math3.js';
import { makeFrame, stageToWorld, worldToStage } from './core/stage.js';

const smoother = (t) => t * t * t * (t * (t * 6 - 15) + 10);

/**
 * @param {object} ctx
 * @param {object} world
 */
export function createRpgCamera(ctx, world) {
  const camera = ctx.camera;
  const params = {
    dist: 4.2, height: 1.55, shoulder: 0.42, fov: 46, pitch: 0.2, pitchMin: -0.55, pitchMax: 1.05,
    lag: 0.085, lockLag: 0.16, recover: 0.2, minBoom: 0.7, floor: 0.25,
    /** radians per pixel of mouse / touch drag are applied by src/input; this scales the analogue result */
    sens: 1, autoFollow: 0.9, lockRange: 16, lockBreak: 22,
  };
  const pivot = new THREE.Vector3(), want = new THREE.Vector3(), pos = new THREE.Vector3(), look = new THREE.Vector3();
  const aim = new THREE.Vector3(), tmp = new THREE.Vector3(), tmp2 = new THREE.Vector3();
  const quat = new THREE.Quaternion(), qS = new THREE.Quaternion(), qYaw = new THREE.Quaternion(), euler = new THREE.Euler(0, 0, 0, 'YXZ');
  const mLook = new THREE.Matrix4(), UP = new THREE.Vector3(0, 1, 0);
  const right = new THREE.Vector3(), up = new THREE.Vector3(), fwd = new THREE.Vector3();
  const lookIn = { x: 0, y: 0 };
  let boom = params.dist, idleLook = 9, fovNow = params.fov, zoomK = 1, zoomLeft = 0, zoomTo = 1;
  let first = true;
  /** boss / custom framing while a given target is locked */
  let framing = null;
  /** cinematic through the director (stage frame) or a world-space shot function */
  const cine = { on: false, frame: makeFrame(0, 0, 0), mode: '', fn: null, t: 0, dur: 0, onDone: null, blendOut: 0.6, handle: null };
  /** blend from a held pose back to the follow camera */
  const blend = { on: false, t: 0, T: 0.6, pos: new THREE.Vector3(), quat: new THREE.Quaternion(), fov: 46 };

  const cam = {
    params,
    yaw: 0, pitch: params.pitch,
    get dist() { return boom; },
    target: null,
    focus: new THREE.Vector3(),
    get cinematic() { return cine.on; },
    look(dyaw, dpitch) { lookIn.x += dyaw; lookIn.y += dpitch; },
    lock, toggleLock, switch: switchTarget, setFraming, cine: playCine, worldShot, snap, update, zoom, project, forward, endCine,
    yawOf: () => cam.yaw,
    dispose() {},
  };

  /** Camera forward on the floor plane. */
  function forward(out = new THREE.Vector3()) { return out.set(fwdX(cam.yaw), 0, fwdZ(cam.yaw)); }

  // ---- lock-on --------------------------------------------------------------------------------------------------
  function lock(t) {
    if (t && (!t.alive || t.leaving > 0)) t = null;
    if (cam.target === t) return;
    cam.target = t;
    world.emit('lock', { target: t });
  }
  /** Best target in front of the camera. */
  function pickTarget() {
    const hero = world.hero;
    if (!hero) return null;
    let best = null, score = 1e9;
    for (const b of world.actors) {
      if (b === hero || !b.alive || b.leaving > 0 || !world.hostile(hero, b) || b.spec.lockable === false && !b.spec.boss) continue;
      const dx = b.pos.x - hero.pos.x, dz = b.pos.z - hero.pos.z;
      const d = hypot2(dx, dz);
      if (d > params.lockRange + b.radius) continue;
      const ang = Math.abs(angDiff(cam.yaw, yawTo(dx, dz)));
      if (ang > 1.35 && d > 2.5) continue;
      const s = d * 0.35 + ang * 4;
      if (s < score) { score = s; best = b; }
    }
    return best;
  }
  function toggleLock() { if (cam.target) lock(null); else lock(pickTarget()); return cam.target; }
  /** Switch to the next target to the left (-1) / right (+1) on screen. */
  function switchTarget(dir) {
    const hero = world.hero, cur = cam.target;
    if (!hero || !cur) return;
    const base = yawTo(cur.pos.x - hero.pos.x, cur.pos.z - hero.pos.z);
    let best = null, bestA = 1e9;
    for (const b of world.actors) {
      if (b === hero || b === cur || !b.alive || b.leaving > 0 || !world.hostile(hero, b)) continue;
      const dx = b.pos.x - hero.pos.x, dz = b.pos.z - hero.pos.z;
      if (hypot2(dx, dz) > params.lockRange + b.radius) continue;
      // yaw decreases to the right
      const da = -angDiff(base, yawTo(dx, dz)) * dir;
      const a = da > 0.01 ? da : da + Math.PI * 2;
      if (a < bestA) { bestA = a; best = b; }
    }
    if (best) lock(best);
  }
  /**
   * Framing while `target` is locked (boss): { target, point(out) | socket name, back, up, pitch, fov }. null clears.
   * A kind with `boss: true` gets a default from its scale.
   */
  function setFraming(f) { framing = f; }
  function framingFor(t) {
    if (framing && (!framing.target || framing.target === t)) return framing;
    if (t.spec.boss || t.scale > 1.6) {
      if (!t._framing) t._framing = { target: t, back: 1.1 * t.scale, up: 0.25 * t.scale, pitch: -0.1, fov: 4, point: null };
      return t._framing;
    }
    return null;
  }
  function aimPoint(t, fr, out) {
    if (fr && typeof fr.point === 'function') { fr.point(out); return out; }
    if (fr && typeof fr.point === 'string') return t.socket(fr.point, out);
    if (t.char && t.char.sockets && t.char.sockets.chest) { t.socket('chest', out); return out; }
    return out.set(t.pos.x, t.pos.y + t.height * 0.62, t.pos.z);
  }

  // ---- cinematics -----------------------------------------------------------------------------------------------
  /**
   * Play src/cam shots around an actor in its stage frame (README §6.5): shots keep their [f, u, s] meaning with
   * f = the anchor's forward and s = its right (side -1: its left, mirrored like the duel's P2).
   * o: { anchor: actor, target?: actor | null, side?: 1 | -1, blendOut = 0.6, onDone(completed), hud, keepLetterbox, clock }
   */
  function playCine(shots, o = {}) {
    const director = ctx.cam;
    if (!director || !shots || !shots.length) return null;
    const anchor = o.anchor || world.hero;
    const target = o.target !== undefined ? o.target : anchor.target;
    const side = o.side === -1 ? -1 : o.side === 1 ? 1 : pickSide(anchor);
    beginCine('stage', o);
    makeFrame(anchor.pos.x, anchor.pos.z, anchor.yaw + (side < 0 ? Math.PI : 0), cine.frame);
    const src = (act, fallbackF) => (out) => {
      if (act && !act.gone) act.socket('chest', out); else anchor.at(fallbackF, 1.35, 0, out);
      return worldToStage(out, cine.frame, out);
    };
    const play = director._rpgPlay || director.play;
    const done = (completed) => { if (cine.on && cine.handle === h) endCine(completed); };
    const h = play.call(director, shots, { ...o, anchor: src(anchor, 0), target: src(target, 2.2), facing: side, blendOut: 0, onDone: done, hud: o.hud });
    cine.handle = h;
    return h;
  }
  /** The side of the anchor with more room for a camera (its right by default). */
  function pickSide(a) {
    const R = world.arena.radius - 1.5;
    const rx = a.pos.x + rightX(a.yaw) * 5, rz = a.pos.z + rightZ(a.yaw) * 5;
    const lx = a.pos.x - rightX(a.yaw) * 5, lz = a.pos.z - rightZ(a.yaw) * 5;
    const dr = hypot2(rx, rz), dl = hypot2(lx, lz);
    return dr > R && dl < dr ? -1 : 1;
  }
  /**
   * World-space cinematic: fn(t, out) writes out.pos / out.look (Vector3) and out.fov for t in [0, dur] (game time).
   * o: { dur, blendOut = 0.8, onDone, clock: 'game' | 'real' }
   */
  function worldShot(fn, o = {}) {
    beginCine('world', o);
    cine.fn = fn; cine.t = 0; cine.dur = o.dur ?? 2; cine.real = o.clock === 'real';
    return { stop: () => endCine(false), get done() { return !cine.on; } };
  }
  function beginCine(mode, o) {
    if (cine.on) endCine(false);
    cine.on = true; cine.mode = mode; cine.onDone = o.onDone || null; cine.blendOut = o.blendOut ?? 0.6; cine.fn = null; cine.handle = null;
    world.emit('cine', { on: true });
  }
  /** End the running cinematic and blend back to the follow camera. */
  function endCine(completed = false) {
    if (!cine.on) return;
    const h = cine.handle, cb = cine.onDone;
    cine.on = false; cine.handle = null; cine.onDone = null;
    if (h && !h.done) h.stop(0);
    blend.on = cine.blendOut > 0; blend.t = 0; blend.T = cine.blendOut;
    blend.pos.copy(camera.position); blend.quat.copy(camera.quaternion); blend.fov = camera.fov;
    // come back behind the hero, looking the way the cinematic left off when a target is there
    const hero = world.hero;
    if (hero && !cam.target) cam.yaw = hero.yaw;
    cam.pitch = params.pitch;
    first = true;
    world.emit('cine', { on: false });
    if (cb) cb(completed);
  }
  /** Called by the mode when a director sequence was started directly (choreography using ctx.cam.play). */
  cam.adoptDirector = (anchor, side) => {
    if (cine.on && cine.mode === 'stage') return;
    beginCine('stage', { blendOut: 0.7 });
    makeFrame(anchor.pos.x, anchor.pos.z, anchor.yaw + (side < 0 ? Math.PI : 0), cine.frame);
  };
  cam.stageFrame = () => cine.frame;

  /** Temporary push-in: distance x factor for `dur` real seconds. */
  function zoom(factor, dur = 0.5) { zoomTo = clamp(factor, 0.4, 2); zoomLeft = dur; }

  /** Jump behind the hero (respawn, teleport). */
  function snap(yaw) {
    const hero = world.hero;
    if (hero) cam.yaw = yaw !== undefined ? yaw : hero.yaw;
    cam.pitch = params.pitch;
    first = true;
    blend.on = false;
  }

  // ---- boom collision -------------------------------------------------------------------------------------------
  /** Largest t in [0, max] such that pivot + d * t stays inside the arena and outside camera-blocking colliders. */
  function clearance(px, pz, dx, dz, max) {
    let t = max;
    const R = world.arena.radius + 0.35;
    // circle wall: |p + d t| = R
    const a = dx * dx + dz * dz;
    if (a > 1e-8) {
      const b = 2 * (px * dx + pz * dz), c = px * px + pz * pz - R * R;
      if (c >= 0) t = 0;
      else { const disc = b * b - 4 * a * c; if (disc > 0) { const tw = (-b + Math.sqrt(disc)) / (2 * a); if (tw < t) t = Math.max(0, tw); } }
    }
    const cols = world.colliders;
    for (let i = 0; i < cols.length; i++) {
      const c = cols[i];
      if (!c.blocksCamera || a < 1e-8) continue;
      if (c.type === 'circle') {
        const ox = px - c.x, oz = pz - c.z, r = c.r + 0.25;
        const cc = ox * ox + oz * oz - r * r;
        if (cc <= 0) continue;            // pivot inside: ignore (the hero is pushed out by the world)
        const b = 2 * (ox * dx + oz * dz), disc = b * b - 4 * a * cc;
        if (disc <= 0) continue;
        const th = (-b - Math.sqrt(disc)) / (2 * a);
        if (th > 0 && th < t) t = th;
      } else {
        const cs = Math.cos(c.yaw), sn = Math.sin(c.yaw);
        const ox = px - c.x, oz = pz - c.z;
        const lx = ox * cs - oz * sn, lz = ox * sn + oz * cs, ldx = dx * cs - dz * sn, ldz = dx * sn + dz * cs;
        const hx = c.hx + 0.25, hz = c.hz + 0.25;
        let t0 = 0, t1 = t, ok = true;
        if (Math.abs(ldx) < 1e-8) { if (Math.abs(lx) > hx) ok = false; } else { let ta = (-hx - lx) / ldx, tb = (hx - lx) / ldx; if (ta > tb) { const q = ta; ta = tb; tb = q; } t0 = Math.max(t0, ta); t1 = Math.min(t1, tb); }
        if (ok) { if (Math.abs(ldz) < 1e-8) { if (Math.abs(lz) > hz) ok = false; } else { let ta = (-hz - lz) / ldz, tb = (hz - lz) / ldz; if (ta > tb) { const q = ta; ta = tb; tb = q; } t0 = Math.max(t0, ta); t1 = Math.min(t1, tb); } }
        if (ok && t0 <= t1 && t0 > 0 && t0 < t) t = t0;
      }
    }
    return t;
  }

  // ---- per frame ------------------------------------------------------------------------------------------------
  function followPose(dtReal) {
    const hero = world.hero;
    if (!hero) return;
    const hv = hero.view;
    const hx = hv ? hv.pos.x : hero.pos.x, hy = hv ? hv.pos.y : hero.pos.y, hz = hv ? hv.pos.z : hero.pos.z;
    let t = cam.target;
    if (t && (!t.alive || t.leaving > 0 || hero.distTo(t) > params.lockBreak + t.radius)) { lock(null); t = null; }
    const k = first ? 1 : 1 - Math.exp(-dtReal / params.lag);
    const kl = first ? 1 : 1 - Math.exp(-dtReal / params.lockLag);
    let wantDist = params.dist, wantPitch = cam.pitch, fovAdd = 0, upAdd = 0;
    idleLook += dtReal;
    if (t) {
      const fr = framingFor(t);
      aimPoint(t, fr, aim);
      const dx = aim.x - hx, dz = aim.z - hz, d = hypot2(dx, dz);
      if (d > 0.4) cam.yaw = wrapPi(cam.yaw + angDiff(cam.yaw, yawTo(dx, dz)) * kl);
      // look a little up toward tall targets, a little down on low / close ones
      const elev = Math.atan2(aim.y - (hy + params.height), Math.max(1.5, d + params.dist));
      wantPitch = clamp(params.pitch + 0.06 - elev * 0.75 + (fr ? fr.pitch || 0 : 0) + clamp((2.4 - d) * 0.07, 0, 0.14), params.pitchMin, params.pitchMax);
      cam.pitch += (wantPitch - cam.pitch) * kl;
      if (fr) { wantDist += (fr.back || 0) * clamp(1.4 - d / (8 * Math.max(1, t.scale * 0.5)), 0.35, 1); fovAdd = fr.fov || 0; upAdd = fr.up || 0; }
      lookIn.x = lookIn.y = 0;
    } else {
      if (lookIn.x !== 0 || lookIn.y !== 0) {
        cam.yaw = wrapPi(cam.yaw - lookIn.x * params.sens);
        cam.pitch = clamp(cam.pitch - lookIn.y * params.sens, params.pitchMin, params.pitchMax);
        lookIn.x = lookIn.y = 0;
        idleLook = 0;
      } else if (idleLook > 1.1 && hero.state === 'move' && hero.speed > 1) {
        // drift behind a hero that runs across the view (never when it runs at the camera)
        const d = angDiff(cam.yaw, hero.yaw);
        const s = Math.sin(d);
        if (Math.abs(d) < 2.5) cam.yaw = wrapPi(cam.yaw + s * params.autoFollow * dtReal);
      }
    }
    // pivot: above the hero, a little over its right shoulder (in camera space)
    want.set(hx + rightX(cam.yaw) * params.shoulder, hy * 0.6 + params.height + upAdd, hz + rightZ(cam.yaw) * params.shoulder);
    if (first) pivot.copy(want); else pivot.lerp(want, k);
    if (zoomLeft > 0) zoomLeft -= dtReal;
    zoomK += ((zoomLeft > 0 ? zoomTo : 1) - zoomK) * (1 - Math.exp(-dtReal / 0.12));
    wantDist *= zoomK;
    const cp = Math.cos(cam.pitch), sp = Math.sin(cam.pitch);
    const dx = -fwdX(cam.yaw) * cp, dz = -fwdZ(cam.yaw) * cp, dy = sp;
    let free = clearance(pivot.x, pivot.z, dx, dz, wantDist);
    // the floor: never below params.floor
    if (dy < 0) { const tf = (params.floor - pivot.y) / dy; if (tf > 0 && tf < free) free = tf; }
    free = Math.max(params.minBoom, free);
    if (first || free < boom) boom = free; else boom += (Math.min(wantDist, free) - boom) * (1 - Math.exp(-dtReal / params.recover));
    pos.set(pivot.x + dx * boom, pivot.y + dy * boom, pivot.z + dz * boom);
    if (pos.y < params.floor) pos.y = params.floor;
    // look past the pivot: at the lock target's aim point blended in, else straight ahead of the pivot
    look.set(pivot.x - dx * 6, pivot.y - dy * 6 + 0.1, pivot.z - dz * 6);
    if (t) {
      tmp.copy(aim).sub(pos);
      const dl = tmp.length();
      if (dl > 0.5) { tmp.multiplyScalar(6 / dl).add(pos); look.lerp(tmp, 0.55); }
    }
    fovNow += ((params.fov + fovAdd + portraitFov()) - fovNow) * (first ? 1 : 1 - Math.exp(-dtReal / 0.4));
    cam.focus.set(hx, hy + 1, hz);
    first = false;
  }
  /** Narrow viewports (portrait phones) need a wider vertical fov to keep the surroundings readable. */
  function portraitFov() {
    const a = camera.aspect;
    return a < 1.5 ? Math.min(18, (1.5 - a) * 16) : 0;
  }

  function orient(p, l, out) {
    mLook.lookAt(p, l, UP);
    return out.setFromRotationMatrix(mLook);
  }

  function update(dtGame, dtReal) {
    const director = ctx.cam;
    const sh = director && director.debug ? director.debug.shake : null;
    let fov = fovNow;
    followPose(dtReal);
    fov = fovNow;
    orient(pos, look, quat);
    let p = pos, q = quat;
    if (cine.on) {
      if (cine.mode === 'stage' && director && director.state.shot >= 0) {
        // the director computed this frame in stage space (shake included): map it into the world
        const st = director.state;
        stageToWorld(tmp.copy(st.pos), cine.frame, tmp);
        qYaw.setFromAxisAngle(UP, cine.frame.yaw);
        qS.copy(qYaw).multiply(st.quat);
        // keep the cinematic camera inside the arena shell and above the floor
        const R = world.arena.radius + 2.2, d = hypot2(tmp.x, tmp.z);
        if (d > R) { tmp.x *= R / d; tmp.z *= R / d; }
        camera.position.copy(tmp);
        camera.quaternion.copy(qS);
        setFov(st.fov + portraitFov() * 0.6);
        camera.updateMatrixWorld();
        cam.focus.copy(tmp2.copy(st.look)); stageToWorld(cam.focus, cine.frame, cam.focus);
        return;
      }
      if (cine.mode === 'world' && cine.fn) {
        cine.t += cine.real ? dtReal : dtGame;
        shot.fov = params.fov;
        shot.pos.copy(pos); shot.look.copy(look);
        cine.fn(Math.min(cine.t, cine.dur), shot);
        orient(shot.pos, shot.look, qS);
        p = shot.pos; q = qS; fov = shot.fov + portraitFov() * 0.6;
        cam.focus.copy(shot.look);
        if (cine.t >= cine.dur) { applyPose(p, q, fov, sh); endCine(true); return; }
      } else if (cine.mode === 'stage') {
        // the sequence ended without telling us (direct ctx.cam.play): hand back
        endCine(true);
      }
    }
    if (blend.on) {
      blend.t += dtReal;
      const w = smoother(clamp(blend.t / blend.T));
      tmp.lerpVectors(blend.pos, p, w);
      qS.copy(blend.quat).slerp(q, w);
      fov = blend.fov + (fov - blend.fov) * w;
      if (blend.t >= blend.T) blend.on = false;
      applyPose(tmp, qS, fov, sh);
      return;
    }
    applyPose(p, q, fov, sh);
  }
  const shot = { pos: new THREE.Vector3(), look: new THREE.Vector3(), fov: 46 };

  function setFov(f) {
    f = clamp(f, 8, 110);
    if (Math.abs(camera.fov - f) > 1e-4) { camera.fov = f; camera.updateProjectionMatrix(); }
  }
  /** Write ctx.camera: pose + the director's shake / kick sample of this frame. */
  function applyPose(p, q, fov, sh) {
    camera.position.copy(p);
    camera.quaternion.copy(q);
    if (sh) {
      right.set(1, 0, 0).applyQuaternion(q); up.set(0, 1, 0).applyQuaternion(q); fwd.set(0, 0, -1).applyQuaternion(q);
      camera.position.addScaledVector(fwd, sh.push + sh.pz).addScaledVector(right, sh.px).addScaledVector(up, sh.py).add(sh.offset);
      if (camera.position.y < 0.12) camera.position.y = 0.12;
      euler.set(sh.pitch, sh.yaw, sh.roll + sh.kroll);
      camera.quaternion.multiply(qS.setFromEuler(euler));
      fov += sh.fov;
    }
    setFov(fov);
    camera.updateMatrixWorld();
  }

  /** World point -> CSS pixels of the stage. Returns out with { x, y, visible }. */
  const pv = new THREE.Vector3();
  function project(p, out = { x: 0, y: 0, visible: false }) {
    pv.set(p.x, p.y, p.z).project(camera);
    const v = ctx.viewport;
    out.x = (pv.x * 0.5 + 0.5) * v.cssW;
    out.y = (-pv.y * 0.5 + 0.5) * v.cssH;
    out.visible = pv.z > -1 && pv.z < 1 && pv.x > -1.05 && pv.x < 1.05 && pv.y > -1.05 && pv.y < 1.05;
    return out;
  }

  return cam;
}
