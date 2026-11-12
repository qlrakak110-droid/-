// Character runtime: createCharacter(ctx, design) -> Character.
// One skeleton (contract bones + clavicles, twist / half-joint helpers, fingers, weapon bones, design extras, cloth
// particle bones), one SkinnedMesh per material slot, a clip mixer (crossfades, masked / additive layers), IK passes
// (limbs, two-handed grip, foot planting + floor contact, look-at), procedural breathing and flinch springs, spring
// bones and verlet cloth. See README.md.

import * as THREE from 'three';
import { createRig, bindMatrices, fk } from './skeleton.js';
import { createKit } from './build.js';
import * as shapes from './shapes.js';
import { createKitMaterial } from './materials.js';
import { getClip, sampleClip, Pose, EFFECTORS, EFF_STRIDE, defineClip } from './anim.js';
import { makeLimbs, solveLimb, floorFoot, solveLook } from './ik.js';
import { SpringChain } from './spring.js';
import { Cloth, clothLayout, clothGeometry } from './cloth.js';
import { createCapsules, updateCapsules } from './collide.js';
import { qmul, qmulInv, qrot, qslerp, qaxis, qidentity, twistAngle, qcopy, eulerToQuat, sampleTrack } from './rigmath.js';

export { defineClip, definePose, mirrorClip, mirrorPose, listClips, listPoses, hasClip, invalidateClips } from './anim.js';
export { createKitMaterial, shapes };

const MASKS = {
  upper: (n) => /^(spine|chest|neck|head|shoulder|upperArm|foreArm|hand|fingers|fingerTips|thumb|weapon)/.test(n),
  lower: (n) => /^(hips|thigh|shin|foot|toe)/.test(n),
  arms: (n) => /^(shoulder|upperArm|foreArm|hand|fingers|fingerTips|thumb|weapon)/.test(n),
  head: (n) => /^(neck|head)/.test(n),
};

/**
 * Build a character from a design (see README "Design format").
 * @param {object} ctx  app context
 * @param {object} design
 * @param {object} [opts] { parent = ctx.scene (null: do not add), name }
 * @returns {object} Character
 */
export function createCharacter(ctx, design, opts = {}) {
  const quality = ctx.quality || { cloth: 1 };
  const tv = new Float32Array(32);

  // ---- rig ----------------------------------------------------------------------------------------------------
  const rig0 = createRig(design.proportions, design.bones || []);
  const bind0 = bindMatrices(rig0);
  const anchorPos = (bone, off) => {
    const i = rig0.index[bone];
    if (i === undefined) throw new Error('cloth anchor: unknown bone ' + bone);
    qrot(tv, 0, bind0.mq, i * 4, off[0], off[1], off[2]);
    return [bind0.mp[i * 3] + tv[0], bind0.mp[i * 3 + 1] + tv[1], bind0.mp[i * 3 + 2] + tv[2]];
  };
  const layouts = (design.cloth || []).map((spec) => clothLayout(spec, quality.cloth ?? 1, anchorPos, (n) => rig0.index[n]));
  const rig = createRig(design.proportions, [...(design.bones || []), ...layouts.flatMap((l) => l.bones)]);
  const animCount = rig0.count; // bones the mixer blends (cloth bones are simulated)
  const bind = bindMatrices(rig);
  const N = rig.count;

  const root = new THREE.Group();
  root.name = 'char:' + (opts.name || design.id || 'fighter');
  const bones = rig.names.map((n, i) => {
    const b = new THREE.Bone();
    b.name = n;
    b.position.fromArray(rig.offset, i * 3);
    b.quaternion.fromArray(rig.restRot, i * 4);
    return b;
  });
  for (let i = 0; i < N; i++) (rig.parent[i] < 0 ? root : bones[rig.parent[i]]).add(bones[i]);
  const boneInverses = bones.map((_, i) => new THREE.Matrix4().fromArray(bind.matrices, i * 16).invert());
  const skeleton = new THREE.Skeleton(bones, boneInverses);
  const boneMap = {};
  rig.names.forEach((n, i) => { boneMap[n] = bones[i]; });

  // ---- geometry ---------------------------------------------------------------------------------------------------
  const materials = {};
  for (const [slot, m] of Object.entries(design.materials || {})) materials[slot] = createKitMaterial(m);
  const kit = createKit(rig, bind);
  design.build(kit, shapes, rig);
  layouts.forEach((L) => {
    const first = rig.index[L.bones[0].name];
    // which particle-frame normal sign points away from the body
    const mid = Math.floor(L.R / 2) * L.C + Math.floor(L.C / 2);
    qrot(tv, 0, L.frames, mid * 4, 1, 0, 0);
    const ab = L.anchorBone[0];
    const away = (L.rest[mid * 3] - bind.mp[ab * 3]) * tv[0] + (L.rest[mid * 3 + 2] - bind.mp[ab * 3 + 2]) * tv[2];
    const outward = away >= 0 ? 1 : -1;
    const cg = clothGeometry(L, first, outward);
    const look = L.spec.surface || {};
    const outer = look.outer || { color: 0x4a0d10, rough: 0.8 }, inner = look.inner || outer;
    kit.addSkinned(L.spec.slot || 'suit', cg.geo, (x, y, z, i) => cg.weights(i), {
      color: (p, n, i) => (cg.layer(i) > 0 ? outer.color : inner.color),
      rough: outer.rough ?? 0.8, metal: 0, detail: outer.detail ?? 0.6,
      cavity: (p, n, i) => (cg.layer(i) > 0 ? outer.cavity ?? 1 : inner.cavity ?? 0.7),
    });
  });
  const built = kit.finish(materials, skeleton);
  const meshes = built.meshes;
  for (const m of Object.values(meshes)) root.add(m);

  // ---- sockets ----------------------------------------------------------------------------------------------------
  const P = rig.P;
  const sockets = {};
  const addSocket = (name, bone, off) => {
    if (rig.index[bone] === undefined) return;
    const o = new THREE.Object3D();
    o.name = 'socket:' + name;
    o.position.fromArray(off || [0, 0, 0]);
    bones[rig.index[bone]].add(o);
    sockets[name] = o;
  };
  addSocket('handR', 'weaponR', [0, 0, 0]);
  addSocket('handL', 'weaponL', [0, 0, 0]);
  addSocket('chest', 'chest', [0.13, 0.12, 0]);
  addSocket('head', 'head', [0.03, 0.1, 0]);
  addSocket('hips', 'hips', [0, 0, 0]);
  addSocket('footR', 'footR', [0.03, -P.ankleHeight, 0]);
  addSocket('footL', 'footL', [0.03, -P.ankleHeight, 0]);
  addSocket('back', 'chest', [-0.17, 0.12, 0]);
  const weapons = design.weapons || (design.weapon ? [design.weapon] : []);
  weapons.forEach((w, k) => {
    const sfx = k === 0 ? '' : String(k + 1), bone = 'weapon' + (w.hand || 'R');
    addSocket('weaponBase' + sfx, bone, w.base || [0.1, 0, 0]);
    addSocket('weaponTip' + sfx, bone, w.tip || [1, 0, 0]);
  });
  for (const [name, [bone, off]] of Object.entries(design.sockets || {})) addSocket(name, bone, off);

  // grip points on the main weapon (weapon-bone frame)
  const mainWeapon = weapons[0];
  const grips = {};
  if (mainWeapon) {
    for (const [name, g] of Object.entries(mainWeapon.grips || {})) {
      const q = new Float32Array(4);
      eulerToQuat(q, 0, ...(g.rot || [0, 0, 0]));
      grips[name] = { pos: Float32Array.from(g.pos || [0, 0, 0]), q, bone: rig.index['weapon' + (mainWeapon.hand || 'R')] };
    }
  }

  // ---- runtime state ----------------------------------------------------------------------------------------------
  const lq = new Float32Array(rig.restRot), lp = new Float32Array(rig.offset);
  const mq = new Float32Array(N * 4), mp = new Float32Array(N * 3);
  const limbs = makeLimbs(rig);
  const ix = rig.index;
  const springs = (design.springs || []).map((s) => new SpringChain(rig, s));
  const capsules = createCapsules(rig, design.colliders || []);
  const cloths = layouts.map((L) => new Cloth(rig, L, quality.cloth ?? 1));
  cloths.forEach((c) => c.setBind(bind.mq, bind.mp));
  const final = new Pose(rig);
  const layerPose = new Pose(rig);
  const statePool = [];
  const states = [];
  const layers = new Map();
  const listeners = [];
  const springsBody = { th: new Float32Array(3), om: new Float32Array(3), hth: new Float32Array(3), hom: new Float32Array(3), x: new Float32Array(3), v: new Float32Array(3) };
  const boneSprings = new Map();
  const flashState = { color: new THREE.Color(), amount: 0, dur: 0.15, t: 1 };
  const flashCol = new THREE.Color();
  const lookRT = { target: null, weight: 0, w: 0, pos: new Float32Array(3), has: false };
  const inertiaM = new Float32Array(12);
  const lastWorld = new THREE.Matrix4(), curWorld = new THREE.Matrix4(), invWorld = new THREE.Matrix4(), tmpM = new THREE.Matrix4();
  let haveLast = false;
  const gravL = new Float32Array(3), windL = new Float32Array(3), footBuf = new Float32Array(8), gripT = new Float32Array(8);
  const tmpV = new THREE.Vector3();
  let simTime = 0, facing = 1, turnLeft = 0, turnDur = 0, turnFrom = 0, breathPhase = 0;

  const char = {
    root, rig, skeleton, meshes, materials, sockets, design,
    bones: boneMap,
    stats: { triangles: built.triangles, drawCalls: Object.keys(meshes).length, bones: N },
    rootDelta: { f: 0, u: 0 },
    /** Apply root motion to root.position automatically (default false: the game owns positions). */
    applyRootMotion: false,
    /** World-space wind (m/s^2 acceleration on cloth). */
    wind: [0, 0, 0],
    /** Procedural breathing: rate (Hz), depth (x default amplitude). */
    breath: { rate: 0.32, depth: 1 },
    weapon: mainWeapon ? {
      bone: bones[ix['weapon' + (mainWeapon.hand || 'R')]],
      mesh: meshes[mainWeapon.slot || 'blade'] || null,
      material: materials[mainWeapon.slot || 'blade'] || null,
      grips,
      setVisible(b) { if (this.mesh) this.mesh.visible = b; },
    } : null,

    get facing() { return facing; },
    get clip() { const s = states[states.length - 1]; return s ? s.name : null; },
    get clipTime() { const s = states[states.length - 1]; return s ? s.time : 0; },
    get clipDuration() { const s = states[states.length - 1]; return s ? s.c.duration : 0; },
    get finished() { const s = states[states.length - 1]; return !!s && !s.loop && s.time >= s.c.duration - 1e-6; },

    play, setClipTime, update, onEvent, flash, impulse, setVisible, dispose, setFacing, lookAt, layer, stopLayer, teleport, prewarm,
  };

  /**
   * Play a clip. opts: { fade = 0.1 (s crossfade), speed = 1, loop = clip.loop, startAt = 0, restart = false }.
   * Re-playing the clip that is already looping keeps it running unless restart is true.
   */
  function play(name, o = {}) {
    const c = getClip(rig, name);
    const cur = states[states.length - 1];
    const loop = o.loop ?? c.loop;
    if (cur && cur.name === name && cur.loop && loop && !o.restart) { cur.speed = o.speed ?? cur.speed; return char; }
    const s = statePool.pop() || { pose: new Pose(rig) };
    s.c = c; s.name = name; s.speed = o.speed ?? 1; s.loop = loop; s.external = false;
    s.time = s.lastT = Math.max(0, o.startAt || 0); s.fresh = true;
    s.fade = Math.max(0, o.fade ?? 0.1); s.age = 0; s.w = s.fade > 0 ? 0 : 1;
    states.push(s);
    while (states.length > 4) statePool.push(states.shift());
    return char;
  }

  /** Drive the current clip's time from outside (the game owns move time). The clip stops self-advancing until the next play(). */
  function setClipTime(t) {
    const s = states[states.length - 1];
    if (!s) return char;
    s.external = true;
    const d = s.c.duration;
    s.time = s.loop ? ((t % d) + d) % d : Math.max(0, Math.min(d, t));
    return char;
  }

  /** Subscribe to clip event markers: fn(name, data, clipName). Returns an unsubscribe function. */
  function onEvent(fn) {
    listeners.push(fn);
    return () => { const i = listeners.indexOf(fn); if (i >= 0) listeners.splice(i, 1); };
  }

  function emit(c, from, to, inclusive) {
    const ev = c.events;
    for (let i = 0; i < ev.length; i++) {
      const t = ev[i].t;
      if ((inclusive ? t >= from : t > from) && t <= to) for (let k = 0; k < listeners.length; k++) listeners[k](ev[i].name, ev[i].data, c.name);
    }
  }

  const rootA = new Float32Array(2), rootB = new Float32Array(2);
  function rootAt(c, t, out) {
    if (!c.root) { out[0] = out[1] = 0; return; }
    sampleTrack(c.root, t, out, 0);
  }

  function advance(s, dt, current) {
    const c = s.c, d = c.duration;
    let wraps = 0;
    if (!s.external) {
      s.time += dt * s.speed;
      if (s.loop) { while (s.time >= d) { s.time -= d; wraps++; } }
      else if (s.time > d) s.time = d;
    }
    if (current) {
      // events + root motion of the newest clip
      if (wraps > 0) {
        emit(c, s.lastT, d, s.fresh);
        for (let k = 1; k < wraps; k++) emit(c, 0, d, true);
        emit(c, 0, s.time, true);
      } else if (s.time >= s.lastT) emit(c, s.lastT, s.time, s.fresh);
      rootAt(c, s.lastT, rootA); rootAt(c, s.time, rootB);
      let df = rootB[0] - rootA[0], du = rootB[1] - rootA[1];
      if (wraps > 0) { df += c.rootEnd[0] * wraps; du += c.rootEnd[1] * wraps; }
      if (s.time < s.lastT && !wraps) { df = 0; du = 0; } // scrubbed backward: no motion
      char.rootDelta.f += df; char.rootDelta.u += du;
    }
    s.fresh = false;
    s.lastT = s.time;
    s.age += dt;
    s.w = s.fade > 0 ? Math.min(1, s.age / s.fade) : 1;
  }

  // ---- pose resolution (per state): curl, FK, limb IK, record feet ------------------------------------------------
  function applyCurl(curl, grip, gripHand) {
    for (let side = 0; side < 2; side++) {
      const s = side === 0 ? 'L' : 'R';
      let c = curl[side];
      if (gripHand === s) c = Math.max(c, grip);
      const fi = ix['fingers' + s], ti = ix['fingerTips' + s], th = ix['thumb' + s], mir = s === 'L';
      eulerToQuat(lq, fi * 4, 8 + 80 * c, 0, -4 * c, mir);
      eulerToQuat(lq, ti * 4, 10 + 95 * c, 0, 0, mir);
      eulerToQuat(lq, th * 4, 25 + 45 * c, -20 * c, 10 + 30 * c, mir);
    }
  }

  function resolve(pose, gripHand) {
    lq.set(pose.lq.subarray(0, animCount * 4));
    lp[0] = rig.offset[0] + pose.hips[0]; lp[1] = rig.offset[1] + pose.hips[1]; lp[2] = rig.offset[2] + pose.hips[2];
    applyCurl(pose.curl, pose.grip, gripHand);
    fk(rig, lq, lp, mq, mp, 0, animCount);
    let any = false;
    for (let e = 0; e < EFFECTORS.length; e++) {
      const o = e * EFF_STRIDE, w = pose.ik[o];
      if (w <= 0) continue;
      const limb = limbs[EFFECTORS[e]];
      const sp = pose.ik[o + 14], k = pose.ik[o + 15];
      if (sp >= 2 && k > 0) { // target authored in the hips / chest frame -> model space, blended with the A target
        const b = sp === 2 ? ix.hips : ix.chest, ik = pose.ik;
        qrot(tv, 0, mq, b * 4, ik[o + 16], ik[o + 17], ik[o + 18]);
        const bx = mp[b * 3] + tv[0], by = mp[b * 3 + 1] + tv[1], bz = mp[b * 3 + 2] + tv[2];
        if (k >= 1) { ik[o + 1] = bx; ik[o + 2] = by; ik[o + 3] = bz; }
        else { ik[o + 1] += (bx - ik[o + 1]) * k; ik[o + 2] += (by - ik[o + 2]) * k; ik[o + 3] += (bz - ik[o + 3]) * k; }
        if (ik[o + 23]) {
          qmul(tv, 4, mq, b * 4, ik, o + 19);
          if (ik[o + 8] && k < 1) qslerp(ik, o + 4, ik, o + 4, tv, 4, k); else qcopy(ik, o + 4, tv, 4);
          ik[o + 8] = 1;
        }
      }
      solveLimb(rig, limb, lq, mq, mp, pose.ik, o + 1, pose.ik[o + 8] ? pose.ik : null, o + 4, pose.ik[o + 12] ? pose.ik : null, o + 9, w);
      any = true;
    }
    if (any) fk(rig, lq, lp, mq, mp, 0, animCount);
    // feet as resolved (sole point + rotation), used to re-plant after additive layers
    for (let f = 0; f < 2; f++) {
      const limb = f === 0 ? limbs.footR : limbs.footL, e = limb.end;
      qrot(tv, 0, mq, e * 4, limb.endOff[0], limb.endOff[1], limb.endOff[2]);
      pose.feet[f * 7] = mp[e * 3] + tv[0]; pose.feet[f * 7 + 1] = mp[e * 3 + 1] + tv[1]; pose.feet[f * 7 + 2] = mp[e * 3 + 2] + tv[2];
      qcopy(pose.feet, f * 7 + 3, mq, e * 4);
    }
    pose.lq.set(lq.subarray(0, animCount * 4));
  }

  function blendInto(a, b, w) {
    if (w >= 1) { a.copy(b); return; }
    if (w <= 0) return;
    for (let i = 0; i < animCount; i++) qslerp(a.lq, i * 4, a.lq, i * 4, b.lq, i * 4, w);
    for (let k = 0; k < 3; k++) a.hips[k] += (b.hips[k] - a.hips[k]) * w;
    for (let f = 0; f < 2; f++) {
      for (let k = 0; k < 3; k++) a.feet[f * 7 + k] += (b.feet[f * 7 + k] - a.feet[f * 7 + k]) * w;
      qslerp(a.feet, f * 7 + 3, a.feet, f * 7 + 3, b.feet, f * 7 + 3, w);
    }
    if (a.lookW <= 0) a.look.set(b.look);
    else if (b.lookW > 0) for (let k = 0; k < 3; k++) a.look[k] += (b.look[k] - a.look[k]) * w;
    a.lookW += (b.lookW - a.lookW) * w;
    a.grip += (b.grip - a.grip) * w;
    a.curl[0] += (b.curl[0] - a.curl[0]) * w; a.curl[1] += (b.curl[1] - a.curl[1]) * w;
  }

  // ---- layers ------------------------------------------------------------------------------------------------------
  /**
   * Masked override or additive layer. opts: { weight = 1, mask: 'upper'|'lower'|'arms'|'head'|[bone names] (override
   * layers), additive = false, speed = 1, loop = clip.loop, fade = 0.15 }. Additive layers add the clip's motion
   * relative to its first frame.
   */
  function layer(name, clip, o = {}) {
    const c = getClip(rig, clip);
    let L = layers.get(name);
    if (!L) { L = { pose: new Pose(rig), ref: new Pose(rig), mask: new Uint8Array(N) }; layers.set(name, L); }
    L.c = c; L.time = 0; L.speed = o.speed ?? 1; L.loop = o.loop ?? c.loop; L.additive = !!o.additive;
    L.target = o.weight ?? 1; L.w = L.w || 0; L.fade = o.fade ?? 0.15; L.stopping = false;
    const m = o.mask || 'upper';
    for (let i = 0; i < N; i++) L.mask[i] = Array.isArray(m) ? (m.includes(rig.names[i]) ? 1 : 0) : MASKS[m] ? (MASKS[m](rig.names[i]) ? 1 : 0) : 1;
    if (L.additive) sampleClip(rig, c, 0, L.ref);
    return char;
  }

  /** Fade a layer out (fade seconds) and remove it. */
  function stopLayer(name, fade = 0.15) {
    const L = layers.get(name);
    if (L) { L.stopping = true; L.fade = fade; L.target = 0; }
    return char;
  }

  function applyLayers(dt) {
    for (const [name, L] of layers) {
      L.time += dt * L.speed;
      const d = L.c.duration;
      if (L.loop) L.time %= d; else if (L.time >= d) { L.time = d; if (!L.additive && !L.stopping) { L.stopping = true; L.target = 0; } }
      const step = L.fade > 0 ? dt / L.fade : 1;
      L.w = L.w < L.target ? Math.min(L.target, L.w + step) : Math.max(L.target, L.w - step);
      if (L.stopping && L.w <= 0) { layers.delete(name); continue; }
      if (L.w <= 0) continue;
      sampleClip(rig, L.c, L.time, L.pose);
      if (L.additive) {
        for (let i = 1; i < animCount; i++) {
          if (!L.mask[i]) continue;
          qmulInv(tv, 0, L.ref.lq, i * 4, L.pose.lq, i * 4);  // delta = ref^-1 * cur
          qidentity(tv, 4);
          qslerp(tv, 0, tv, 4, tv, 0, L.w);
          qmul(final.lq, i * 4, final.lq, i * 4, tv, 0);
        }
        continue;
      }
      resolve(L.pose, L.c.gripHand);
      for (let i = 0; i < animCount; i++) if (L.mask[i]) qslerp(final.lq, i * 4, final.lq, i * 4, L.pose.lq, i * 4, L.w);
      if (L.mask[0]) for (let k = 0; k < 3; k++) final.hips[k] += (L.pose.hips[k] - final.hips[k]) * L.w;
      if (L.mask[ix.weaponR]) final.grip += (L.pose.grip - final.grip) * L.w;
    }
  }

  // ---- additive procedural motion ----------------------------------------------------------------------------------
  /** Physical flinch: { bone = 'body' | bone name, dir: [f,u,s] push direction, amount = 1 }. */
  function impulse({ bone = 'body', dir = [-1, 0, 0], amount = 1 } = {}) {
    let dx = dir[0], dy = dir[1], dz = dir[2];
    const l = Math.hypot(dx, dy, dz) || 1;
    dx /= l; dy /= l; dz /= l;
    // rotation axis = up x dir (push at the chest tips the torso along dir)
    const ax = dz, az = -dx;
    if (bone === 'body') {
      const k = 3.2 * amount;
      springsBody.om[0] += ax * k; springsBody.om[2] += az * k;
      springsBody.hom[0] += ax * k * 1.4; springsBody.hom[2] += az * k * 1.4;
      springsBody.v[0] += dx * 0.55 * amount; springsBody.v[1] += (dy * 0.35 - 0.12) * amount; springsBody.v[2] += dz * 0.45 * amount;
    } else {
      if (ix[bone] === undefined) return char;
      let s = boneSprings.get(bone);
      if (!s) { s = { i: ix[bone], th: new Float32Array(3), om: new Float32Array(3) }; boneSprings.set(bone, s); }
      const k = 4 * amount;
      s.om[0] += ax * k; s.om[2] += az * k;
    }
    return char;
  }

  function stepSpring(th, om, k, c, dt) {
    for (let a = 0; a < 3; a++) { om[a] += (-k * th[a] - c * om[a]) * dt; th[a] += om[a] * dt; }
  }

  const rotTmp = new Float32Array(12);
  /** Pre-multiply a fighter-space rotation vector (axis * angle) onto bone i (expressed in its parent frame). */
  function addRot(i, vx, vy, vz) {
    const a = Math.hypot(vx, vy, vz);
    if (a < 1e-6) return;
    const p = rig.parent[i];
    if (p >= 0) { // axis into the parent frame
      rotTmp[0] = -mq[p * 4]; rotTmp[1] = -mq[p * 4 + 1]; rotTmp[2] = -mq[p * 4 + 2]; rotTmp[3] = mq[p * 4 + 3];
      qrot(rotTmp, 4, rotTmp, 0, vx / a, vy / a, vz / a);
    } else { rotTmp[4] = vx / a; rotTmp[5] = vy / a; rotTmp[6] = vz / a; }
    qaxis(rotTmp, 8, rotTmp[4], rotTmp[5], rotTmp[6], a);
    qmul(lq, i * 4, rotTmp, 8, lq, i * 4);
  }

  function additive(dt, breathK) {
    // breathing
    breathPhase += dt * char.breath.rate * Math.PI * 2;
    const b = Math.sin(breathPhase) * char.breath.depth * breathK, D = Math.PI / 180;
    addRot(ix.spine, 0, 0, 0.5 * b * D);
    addRot(ix.chest, 0, 0, 1.3 * b * D);
    addRot(ix.shoulderR, -1.6 * b * D, 0, 0);
    addRot(ix.shoulderL, 1.6 * b * D, 0, 0);
    addRot(ix.neck, 0, 0, -0.9 * b * D);
    addRot(ix.head, 0, 0, -0.6 * b * D);
    lp[1] += 0.003 * b;
    // flinch springs
    const S = springsBody;
    stepSpring(S.th, S.om, 170, 15, dt);
    for (let a = 0; a < 3; a++) { S.hom[a] += (-120 * (S.hth[a] - S.th[a] * 1.2) - 9 * S.hom[a]) * dt; S.hth[a] += S.hom[a] * dt; }
    stepSpring(S.x, S.v, 110, 13, dt);
    if (Math.abs(S.th[0]) + Math.abs(S.th[2]) + Math.abs(S.hth[0]) + Math.abs(S.hth[2]) > 1e-5) {
      addRot(ix.hips, S.th[0] * 0.25, 0, S.th[2] * 0.25);
      addRot(ix.spine, S.th[0] * 0.35, 0, S.th[2] * 0.35);
      addRot(ix.chest, S.th[0] * 0.45, 0, S.th[2] * 0.45);
      addRot(ix.neck, S.hth[0] * 0.35, 0, S.hth[2] * 0.35);
      addRot(ix.head, S.hth[0] * 0.45, 0, S.hth[2] * 0.45);
      addRot(ix.shoulderR, S.hth[0] * 0.3, 0, S.hth[2] * 0.2);
      addRot(ix.shoulderL, S.hth[0] * 0.3, 0, S.hth[2] * 0.2);
    }
    lp[0] += S.x[0]; lp[1] += S.x[1]; lp[2] += S.x[2];
    for (const s of boneSprings.values()) {
      stepSpring(s.th, s.om, 160, 12, dt);
      addRot(s.i, s.th[0], s.th[1], s.th[2]);
    }
  }

  // ---- drivers ------------------------------------------------------------------------------------------------------
  function drive() {
    for (const s of ['R', 'L']) {
      const ua = ix['upperArm' + s], fa = ix['foreArm' + s], ha = ix['hand' + s];
      // move any forearm twist into the hand (the forearm bone stays a pure hinge; helpers spread the twist)
      const ft = twistAngle(lq, fa * 4, 0, 1, 0);
      if (Math.abs(ft) > 1e-4) {
        qaxis(tv, 0, 0, 1, 0, -ft);
        qmul(lq, fa * 4, lq, fa * 4, tv, 0);
        qaxis(tv, 0, 0, 1, 0, ft);
        qmul(lq, ha * 4, tv, 0, lq, ha * 4);
      }
      // deltoid: half of the arm swing (no twist)
      const ut = twistAngle(lq, ua * 4, 0, 1, 0);
      qaxis(tv, 0, 0, 1, 0, -ut);
      qmul(tv, 4, lq, ua * 4, tv, 0);
      qidentity(tv, 8);
      qslerp(lq, ix['deltoid' + s] * 4, tv, 8, tv, 4, 0.5);
      qaxis(lq, ix['upperArmTwist' + s] * 4, 0, 1, 0, -0.5 * ut);
      qslerp(lq, ix['elbow' + s] * 4, tv, 8, lq, fa * 4, 0.5);
      qaxis(lq, ix['foreArmTwist' + s] * 4, 0, 1, 0, 0.65 * twistAngle(lq, ha * 4, 0, 1, 0));
      qslerp(lq, ix['knee' + s] * 4, tv, 8, lq, ix['shin' + s] * 4, 0.5);
    }
  }

  // ---- look / facing / misc ----------------------------------------------------------------------------------------
  /** Head tracking: target = THREE.Vector3 | Object3D (world) | null; weight 0..1 (blended in over ~0.2 s). */
  function lookAt(target, weight = 1) { lookRT.target = target; lookRT.weight = target ? weight : 0; return char; }

  /** Face +X (1) or -X (-1). opts.turn = seconds: spin through a quick turn instead of an instant mirror. */
  function setFacing(f, o = {}) {
    const nf = f < 0 ? -1 : 1;
    if (nf === facing) return char;
    facing = nf;
    root.scale.x = facing;
    if (o.turn > 0) { turnDur = turnLeft = o.turn; turnFrom = facing < 0 ? Math.PI : -Math.PI; root.rotation.y = turnFrom; }
    return char;
  }

  /** Reset cloth / springs (after placing the character somewhere new). */
  function teleport() {
    haveLast = false;
    for (const c of cloths) c.reset();
    for (const s of springs) s.reset();
    return char;
  }

  /** Emissive hit flash on every material: colour (hex / Color / [r,g,b] HDR), amount, duration (real seconds). */
  function flash(color = 0xffffff, amount = 1, dur = 0.15) {
    if (Array.isArray(color)) flashState.color.setRGB(color[0], color[1], color[2]); else flashState.color.set(color);
    flashState.amount = amount; flashState.dur = Math.max(1e-3, dur); flashState.t = 0;
    return char;
  }

  function setVisible(b) { root.visible = !!b; return char; }

  /** Compile this character's programs now (avoids a hitch on first draw). */
  function prewarm() {
    try { ctx.renderer.compile(ctx.scene, ctx.camera); } catch (e) { /* compile is best-effort */ }
    return char;
  }

  function dispose() {
    for (const m of Object.values(meshes)) m.geometry.dispose();
    for (const m of Object.values(materials)) m.dispose();
    skeleton.dispose();
    root.removeFromParent();
    listeners.length = 0;
  }

  // ---- inertia (root world motion -> local sim spaces) ------------------------------------------------------------
  function computeInertia() {
    root.updateMatrixWorld();
    curWorld.copy(root.matrixWorld);
    invWorld.copy(curWorld).invert();
    let ok = haveLast;
    if (ok) {
      const e = curWorld.elements, l = lastWorld.elements;
      const dx = e[12] - l[12], dy = e[13] - l[13], dz = e[14] - l[14];
      if (dx * dx + dy * dy + dz * dz > 0.6 * 0.6) ok = false;              // teleport
      if (Math.sign(curWorld.determinant()) !== Math.sign(lastWorld.determinant())) ok = false; // facing flip
    }
    if (ok) {
      tmpM.multiplyMatrices(invWorld, lastWorld);
      const m = tmpM.elements;
      inertiaM[0] = m[0]; inertiaM[1] = m[1]; inertiaM[2] = m[2];
      inertiaM[3] = m[4]; inertiaM[4] = m[5]; inertiaM[5] = m[6];
      inertiaM[6] = m[8]; inertiaM[7] = m[9]; inertiaM[8] = m[10];
      inertiaM[9] = m[12]; inertiaM[10] = m[13]; inertiaM[11] = m[14];
      for (const s of springs) s.inertia(inertiaM);
      for (const c of cloths) c.inertia(inertiaM);
    }
    lastWorld.copy(curWorld);
    haveLast = true;
    // gravity / wind into model space
    const ie = invWorld.elements;
    const toLocal = (x, y, z, out) => {
      out[0] = ie[0] * x + ie[4] * y + ie[8] * z; out[1] = ie[1] * x + ie[5] * y + ie[9] * z; out[2] = ie[2] * x + ie[6] * y + ie[10] * z;
    };
    toLocal(0, -9.81, 0, gravL);
    toLocal(char.wind[0], char.wind[1], char.wind[2], windL);
    tmpV.set(curWorld.elements[12], 0, curWorld.elements[14]).applyMatrix4(invWorld);
    return tmpV.y;
  }

  // ---- main update -------------------------------------------------------------------------------------------------
  /** Advance animation, IK, secondary motion and cloth. Call once per frame. */
  function update(dtGame, dtReal = dtGame) {
    const dt = Math.max(0, dtGame || 0);
    simTime += dt;
    // flip turn
    if (turnLeft > 0) {
      turnLeft = Math.max(0, turnLeft - dt);
      const k = turnLeft / turnDur;
      root.rotation.y = turnFrom * k * k * (3 - 2 * k);
    }
    const floorY = computeInertia();
    char.rootDelta.f = 0; char.rootDelta.u = 0;
    if (states.length === 0) play(design.idle || 'neutral.hold', { fade: 0 });
    for (let k = 0; k < states.length; k++) advance(states[k], dt, k === states.length - 1);
    // drop states hidden under a fully faded-in newer one
    for (let k = states.length - 1; k > 0; k--) {
      if (states[k].w >= 1) { while (k > 0) { statePool.push(states.shift()); k--; } break; }
    }
    const cur = states[states.length - 1];
    let breathK = 0;
    for (let k = 0; k < states.length; k++) {
      const s = states[k];
      sampleClip(rig, s.c, s.time, s.pose);
      resolve(s.pose, s.c.gripHand);
      if (k === 0) { final.copy(s.pose); breathK = s.c.breath; } else { blendInto(final, s.pose, s.w); breathK += (s.c.breath - breathK) * s.w; }
    }
    if (layers.size) applyLayers(dt);
    // final pose -> local arrays
    lq.set(final.lq.subarray(0, animCount * 4));
    lp[0] = rig.offset[0] + final.hips[0]; lp[1] = rig.offset[1] + final.hips[1]; lp[2] = rig.offset[2] + final.hips[2];
    applyCurl(final.curl, final.grip, cur.c.gripHand);
    fk(rig, lq, lp, mq, mp, 0, animCount);
    additive(dt, breathK);
    fk(rig, lq, lp, mq, mp, 0, animCount);
    // re-plant feet where the blended animation put them, then keep them on the floor
    for (let f = 0; f < 2; f++) {
      const limb = f === 0 ? limbs.footR : limbs.footL;
      const h = final.feet[f * 7 + 1] - floorY;
      const w = h < 0.06 ? 1 : h > 0.25 ? 0 : 1 - (h - 0.06) / 0.19;
      if (w > 0) {
        solveLimb(rig, limb, lq, mq, mp, final.feet, f * 7, final.feet, f * 7 + 3, null, 0, w, 0.03);
        fk(rig, lq, lp, mq, mp, limb.first, animCount);
      }
      floorFoot(rig, limb, lq, lp, mq, mp, floorY, footBuf);
    }
    // two-handed grip
    const gripW = final.grip;
    if (gripW > 0 && cur) {
      const g = grips[cur.c.gripAt] || grips.grip;
      const limb = limbs['hand' + cur.c.gripHand];
      if (g && limb) {
        qrot(gripT, 0, mq, g.bone * 4, g.pos[0], g.pos[1], g.pos[2]);
        gripT[0] += mp[g.bone * 3]; gripT[1] += mp[g.bone * 3 + 1]; gripT[2] += mp[g.bone * 3 + 2];
        qmul(gripT, 4, mq, g.bone * 4, g.q, 0);
        solveLimb(rig, limb, lq, mq, mp, gripT, 0, gripT, 4, null, 0, gripW, 0.02);
        fk(rig, lq, lp, mq, mp, limb.first, animCount);
      }
    }
    // look-at: clip channel first, then the runtime target
    let lw = 0;
    if (final.lookW > 0) { lookRT.pos.set(final.look); lw = final.lookW; }
    else if (lookRT.target && cur.c.lookEnabled) {
      const t = lookRT.target.isObject3D ? lookRT.target.getWorldPosition(tmpV) : tmpV.copy(lookRT.target);
      t.applyMatrix4(invWorld);
      lookRT.pos[0] = t.x; lookRT.pos[1] = t.y; lookRT.pos[2] = t.z;
      lw = lookRT.weight;
    }
    lookRT.w += (lw - lookRT.w) * (1 - Math.exp(-10 * dt));
    if (lookRT.w > 1e-3) { solveLook(rig, lq, mq, mp, lookRT.pos, 0, lookRT.w); }
    drive();
    fk(rig, lq, lp, mq, mp, 0, animCount);
    // secondary motion
    if (capsules.count) updateCapsules(capsules, mq, mp);
    for (const s of springs) s.update(dt, lq, lp, mq, mp, gravL, capsules);
    if (springs.length) fk(rig, lq, lp, mq, mp, 0, animCount);
    for (const c of cloths) { c.update(dt, mq, mp, gravL, windL, capsules, floorY, simTime); c.write(lq, lp); }
    // write bones
    for (let i = 0; i < N; i++) {
      const b = bones[i];
      b.quaternion.set(lq[i * 4], lq[i * 4 + 1], lq[i * 4 + 2], lq[i * 4 + 3]);
      b.position.set(lp[i * 3], lp[i * 3 + 1], lp[i * 3 + 2]);
    }
    if (char.applyRootMotion) { root.position.x += char.rootDelta.f * facing; root.position.y += char.rootDelta.u; }
    root.updateMatrixWorld(true);
    // hit flash (real time)
    if (flashState.t < 1) {
      flashState.t = Math.min(1, flashState.t + (dtReal || 0) / flashState.dur);
      const k = (1 - flashState.t) * (1 - flashState.t) * flashState.amount;
      flashCol.copy(flashState.color).multiplyScalar(k);
      for (const m of Object.values(materials)) m.userData.kit.uFlash.value.copy(flashCol);
    }
    return char;
  }

  // initial pose: neutral, matrices valid before the first update
  fk(rig, lq, lp, mq, mp);
  if (opts.parent !== null) (opts.parent || ctx.scene).add(root);
  return char;
}

// a minimal always-available hold clip (zero motion, neutral pose)
defineClip('neutral.hold', { duration: 1, loop: true, keys: [{ t: 0, pose: 'neutral' }] });
