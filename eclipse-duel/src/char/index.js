// Character runtime: createCharacter(ctx, design) -> Character.
// One skeleton (contract bones + clavicles, twist / half-joint helpers, fingers, weapon bones, design extras, cloth
// particle bones), one SkinnedMesh per material slot, a clip mixer (crossfades, masked / additive layers), IK passes
// (limbs, two-handed grip, foot planting + floor contact, look-at), procedural breathing and flinch springs, spring
// bones and verlet cloth. See README.md.

import * as THREE from 'three';
import { createRig, bindMatrices, fk, driveHelpers, bodyScale } from './skeleton.js';
import { createKit } from './build.js';
import * as shapes from './shapes.js';
import { createKitMaterial } from './materials.js';
import { getClip, sampleClip, Pose, EFFECTORS, EFF_STRIDE, defineClip } from './anim.js';
import { makeLimbs, solveLimb, floorFoot, solveLook, SOFT } from './ik.js';
import { SpringChain } from './spring.js';
import { Cloth, clothLayout, clothGeometry } from './cloth.js';
import { createCapsules, updateCapsules } from './collide.js';
import { qmul, qmulInv, qrot, qslerp, qaxis, qidentity, qcopy, eulerToQuat, sampleTrack, softRamp, softLimit, smooth01, twistAngle } from './rigmath.js';

export { defineClip, definePose, mirrorClip, mirrorPose, listClips, listPoses, hasClip, invalidateClips } from './anim.js';
export { createKitMaterial, shapes };

const MASKS = {
  upper: (n) => /^(spine|chest|neck|head|shoulder|upperArm|foreArm|hand|fingers|fingerTips|thumb|weapon)/.test(n),
  lower: (n) => /^(hips|thigh|shin|foot|toe)/.test(n),
  arms: (n) => /^(shoulder|upperArm|foreArm|hand|fingers|fingerTips|thumb|weapon)/.test(n),
  head: (n) => /^(neck|head)/.test(n),
};
/** Most clips blending at once; a further play() folds the two oldest into one frozen snapshot (never a pop). */
const MAX_STATES = 4;
/** Shortest time (s) the off hand takes to move between two grip points of one weapon during a crossfade. */
const GRIP_FADE = 0.35;

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
  const rigOpts = { gripAngle: design.gripAngle ?? 0 };
  const rig0 = createRig(design.proportions, design.bones || [], rigOpts);
  const bind0 = bindMatrices(rig0);
  const anchorPos = (bone, off) => {
    const i = rig0.index[bone];
    if (i === undefined) throw new Error('cloth anchor: unknown bone ' + bone);
    qrot(tv, 0, bind0.mq, i * 4, off[0], off[1], off[2]);
    return [bind0.mp[i * 3] + tv[0], bind0.mp[i * 3 + 1] + tv[1], bind0.mp[i * 3 + 2] + tv[2]];
  };
  const layouts = (design.cloth || []).map((spec) => clothLayout(spec, quality.cloth ?? 1, anchorPos, (n) => rig0.index[n]));
  const rig = createRig(design.proportions, [...(design.bones || []), ...layouts.flatMap((l) => l.bones)], rigOpts);
  const animCount = rig0.count, animQ = animCount * 4; // bones the mixer blends (cloth bones are simulated)
  const bind = bindMatrices(rig);
  const N = rig.count;
  const K = rig.k; // body scale: every runtime constant in metres is multiplied by it

  const root = new THREE.Group();
  root.name = 'char:' + (opts.name || design.id || 'fighter');
  if (design.scale && design.scale !== 1) root.scale.setScalar(design.scale);
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
  // helper bones that carry a volume-preserving scale (elbow / knee fill)
  const scaled = [];
  for (let i = 0; i < N; i++) if (/^(elbowVol|kneeVol)[RL]$/.test(rig.names[i])) scaled.push(i);

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
  addSocket('chest', 'chest', [0.13 * K, 0.12 * K, 0]);
  addSocket('head', 'head', [0.03 * K, 0.1 * K, 0]);
  addSocket('hips', 'hips', [0, 0, 0]);
  addSocket('footR', 'footR', [0, -P.ankleHeight, 0]);
  addSocket('footL', 'footL', [0, -P.ankleHeight, 0]);
  addSocket('back', 'chest', [-0.17 * K, 0.12 * K, 0]);
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
  const blendTmp = new Pose(rig);
  const statePool = [];
  const states = [];
  const layers = new Map();
  const listeners = [];
  const springsBody = { th: new Float32Array(3), om: new Float32Array(3), hth: new Float32Array(3), hom: new Float32Array(3), x: new Float32Array(3), v: new Float32Array(3) };
  const boneSprings = new Map(), boneSpringList = [];
  const flashState = { color: new THREE.Color(), amount: 0, dur: 0.15, t: 1 };
  const flashCol = new THREE.Color();
  const lookRT = { target: null, weight: 0, w: 0, pos: new Float32Array(3) };
  const inertiaM = new Float32Array(12);
  const lastWorld = new THREE.Matrix4(), curWorld = new THREE.Matrix4(), invWorld = new THREE.Matrix4(), tmpM = new THREE.Matrix4();
  let haveLast = false;
  const gravL = new Float32Array(3), windL = new Float32Array(3), footBuf = new Float32Array(8), gripT = new Float32Array(12);
  const gripQ = new Float32Array(8), twistMem = new Float32Array(4), poleBuf = new Float32Array(3), gripMem = new Float32Array(3);
  // torso capsule the elbows keep out of (design collider 'torso', radius + the arm's own radius)
  const torsoDef = (design.colliders || []).find((c) => c.name === 'torso');
  const body = torsoDef ? new Float32Array(8) : null;
  const torsoA = torsoDef ? [ix[torsoDef.a[0]], ...(torsoDef.a[1] || [0, 0, 0])] : null, torsoB = torsoDef ? [ix[torsoDef.b[0]], ...(torsoDef.b[1] || [0, 0, 0])] : null;
  const ikOpt = { clavicle: 1, wrist: true, roll: null, rollKeep: 0.25, out: null, keepLocal: true, mem: null, body };
  // per clip: the off hand may roll around the handle; after blending: the blended (already rolled) target is kept
  const gripOpt = { clavicle: 1, wrist: true, roll: [1, 0, 0], rollKeep: 0.25, out: new Float32Array(4), body };
  /** Update the torso capsule from the current FK (mq / mp). */
  function bodyPoint(d, o) {
    qrot(body, o, mq, d[0] * 4, d[1], d[2], d[3]);
    body[o] += mp[d[0] * 3]; body[o + 1] += mp[d[0] * 3 + 1]; body[o + 2] += mp[d[0] * 3 + 2];
  }
  function updateBody() {
    if (!body) return;
    bodyPoint(torsoA, 0); bodyPoint(torsoB, 3);
    body[6] = torsoDef.r + 0.065 * K; body[7] = K;
  }
  // bones that follow a fraction of another bone's swing (plates articulated by data: design bone `follow`)
  const followers = (design.bones || []).filter((b) => b.follow).map((b) => {
    const i = ix[b.name], src = ix[b.follow.bone];
    if (src === undefined) throw new Error('bone ' + b.name + ': unknown follow bone ' + b.follow.bone);
    if (rig.parent[i] !== rig.parent[src]) throw new Error('bone ' + b.name + ' must share its parent with the bone it follows (' + b.follow.bone + ')');
    return { i, src, k: b.follow.k ?? 0.5 };
  });
  const fq = new Float32Array(12);
  /** Followers: local = slerp(identity, swing of the source bone, k) * rest. Before the spring bones (their target). */
  function driveFollowers() {
    for (let n = 0; n < followers.length; n++) {
      const F = followers[n], si = F.src * 4;
      const tw = twistAngle(lq, si, 0, 1, 0);
      qaxis(fq, 0, 0, 1, 0, -tw);
      qmul(fq, 4, lq, si, fq, 0);                      // swing of the source
      qidentity(fq, 8);
      qslerp(fq, 0, fq, 8, fq, 4, F.k);
      qmul(lq, F.i * 4, fq, 0, rig.restRot, F.i * 4);
    }
  }
  const tmpV = new THREE.Vector3();
  let simTime = 0, facing = 1, turnLeft = 0, turnDur = 0, turnFrom = 0, breathPhase = 0, dropHold = 0, lockPending = false;
  // foot locks across crossfades: { on, w (0..1), world sole point (3) } per foot; last frame's world sole points
  const footLock = [{ on: false, w: 0, p: new Float32Array(3) }, { on: false, w: 0, p: new Float32Array(3) }];
  const footWorld = new Float32Array(6), footPlanted = new Uint8Array(2), lockV = new THREE.Vector3();
  // weapon bone rest rotation in the fist (grip angle): hand target = weapon target * rest^-1
  const weaponRest = { R: Float32Array.from(rig.restRot.subarray(ix.weaponR * 4, ix.weaponR * 4 + 4)), L: Float32Array.from(rig.restRot.subarray(ix.weaponL * 4, ix.weaponL * 4 + 4)) };
  // grip axis (weapon +X) in the hand frame, per side
  const gripAxis = {};
  for (const s of ['R', 'L']) { const a = new Float32Array(3); qrot(a, 0, weaponRest[s], 0, 1, 0, 0); gripAxis[s] = a; }
  const handTarget = new Float32Array(4);
  // arm chain bones per side (off-arm blending during grip-point changes)
  const armBones = { R: new Uint8Array(animCount), L: new Uint8Array(animCount) };
  for (let i = 0; i < animCount; i++) {
    const m = /^(shoulder|upperArm|foreArm|hand|fingers|fingerTips|thumb|weapon)([RL])$/.exec(rig.names[i]);
    if (m) armBones[m[2]][i] = 1;
  }

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
    /** Body scale of the proportions (hips pivot / 1.04 m): pass as play(name, { scale }) to retarget shared clips. */
    bodyScale: bodyScale(rig.P),
    /** Diagnostics of the last update (QA): automatic pelvis drop (m) and residual two-handed grip error (m). */
    diag: { drop: 0, gripErr: 0, footErr: 0, reach: [0, 0, 0, 0] },
    weapon: mainWeapon ? {
      bone: bones[ix['weapon' + (mainWeapon.hand || 'R')]],
      mesh: meshes[mainWeapon.slot || 'blade'] || null,
      material: materials[mainWeapon.slot || 'blade'] || null,
      grips,
      setVisible(b) { if (this.mesh) this.mesh.visible = b; },
    } : null,

    get facing() { return facing; },
    /** Uniform world scale of the character (root.scale magnitude; facing keeps the mirror sign). */
    get scale() { return Math.abs(root.scale.y); },
    set scale(v) { root.scale.set(facing * Math.abs(v), Math.abs(v), Math.abs(v)); },
    get clip() { const s = states[states.length - 1]; return s ? s.name : null; },
    get clipTime() { const s = states[states.length - 1]; return s ? s.time : 0; },
    get clipDuration() { const s = states[states.length - 1]; return s ? s.c.duration : 0; },
    get finished() { const s = states[states.length - 1]; return !!s && !s.loop && s.time >= s.c.duration - 1e-6; },

    play, setClipTime, update, onEvent, flash, impulse, setVisible, dispose, setFacing, lookAt, layer, stopLayer, teleport, prewarm,
  };

  /**
   * Play a clip. opts: { fade = 0.1 (s crossfade), speed = 1, loop = clip.loop, startAt = 0, restart = false,
   * scale = design.clipScale ?? 1 (multiplies the clip's positional channels: retargeting) }.
   * Re-playing the clip that is already looping keeps it running unless restart is true.
   */
  function play(name, o = {}) {
    const c = getClip(rig, name);
    const cur = states[states.length - 1];
    const loop = o.loop ?? c.loop;
    if (cur && cur.name === name && cur.loop && loop && !o.restart && !cur.frozen) { if (Number.isFinite(o.speed)) cur.speed = o.speed; return char; }
    if (states.length >= MAX_STATES) collapseOldest();
    const s = statePool.pop() || { pose: new Pose(rig) };
    s.c = c; s.name = name; s.speed = Number.isFinite(o.speed) ? o.speed : 1; s.loop = loop; s.external = false; s.frozen = false;
    s.scale = o.scale ?? design.clipScale ?? 1;
    s.time = s.lastT = Math.max(0, o.startAt || 0); s.fresh = true; s.resolved = false;
    s.fade = Math.max(0, o.fade ?? 0.1); s.age = 0; s.w = s.gw = s.fade > 0 ? 0 : 1;
    if (cur && s.fade > 0) s.pose.swivel.set(cur.pose.swivel); else s.pose.swivel.fill(0);
    if (cur && s.fade > 0) lockPending = true;
    states.push(s);
    return char;
  }

  /**
   * Fold the two oldest states into one frozen snapshot that keeps their current blended pose (weight 1, no further
   * sampling): a 5th clip inside one fade window never drops a state that still carries weight.
   */
  function collapseOldest() {
    const a = states[0], b = states[1];
    for (const s of [a, b]) {
      if (s.frozen || s.resolved) continue;
      sampleClip(rig, s.c, s.time, s.pose, s.scale);
      resolve(s.pose, s.c);
      s.resolved = true;
    }
    blendTmp.copy(a.pose);
    blendInto(blendTmp, b.pose, b.w, b.gw);
    b.pose.copy(blendTmp);
    b.frozen = true; b.w = b.gw = 1; b.fade = 0;
    statePool.push(states.shift());
  }

  /** Drive the current clip's time from outside (the game owns move time). The clip stops self-advancing until the next play(). */
  function setClipTime(t) {
    const s = states[states.length - 1];
    if (!s || !Number.isFinite(t) || s.frozen) return char;
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

  /** Advance a state's clock and fade; returns its root motion over this update in s.df / s.du (fighter metres). */
  function advance(s, dt, current) {
    s.df = 0; s.du = 0;
    if (s.frozen) return;
    const c = s.c, d = c.duration;
    let wraps = 0;
    if (!s.external) {
      s.time += dt * s.speed;
      if (s.loop) {
        if (s.time >= d) { wraps = Math.floor(s.time / d); s.time -= wraps * d; if (s.time >= d) s.time = 0; }
      } else if (s.time > d) s.time = d;
    }
    if (current) {
      // events of the newest clip (a huge dt on a loop emits at most two cycles)
      if (wraps > 0) {
        emit(c, s.lastT, d, s.fresh);
        for (let k = 1; k < Math.min(wraps, 2); k++) emit(c, 0, d, true);
        emit(c, 0, s.time, true);
      } else if (s.time >= s.lastT) emit(c, s.lastT, s.time, s.fresh);
    }
    if (c.root) {
      rootAt(c, s.lastT, rootA); rootAt(c, s.time, rootB);
      let df = rootB[0] - rootA[0], du = rootB[1] - rootA[1];
      if (wraps > 0) { df += c.rootEnd[0] * wraps; du += c.rootEnd[1] * wraps; }
      if (s.time < s.lastT && !wraps) { df = 0; du = 0; } // scrubbed backward: no motion
      s.df = df * s.scale; s.du = du * s.scale;
    }
    s.fresh = false;
    s.lastT = s.time;
    s.age += dt;
    const x = s.fade > 0 ? Math.min(1, s.age / s.fade) : 1;
    s.w = x * x * (3 - 2 * x); // smoothstep: crossfades start and end without a velocity step
    // the off hand changes grip point (pommel -> blade ...) over at least GRIP_FADE: it lets go and re-grips
    const g = s.fade > 0 ? Math.min(1, s.age / Math.max(s.fade, GRIP_FADE)) : 1;
    s.gw = g * g * (3 - 2 * g);
  }

  // ---- pose resolution (per state): breathing, curl, FK, pelvis drop, limb IK, two-handed grip, record feet ------
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

  const D2R = Math.PI / 180;
  /** Post-multiply a rotation about the bone's own axis (ax, ay, az) onto bone i. */
  function localRot(i, ax, ay, az, a) { qaxis(tv, 0, ax, ay, az, a); qmul(lq, i * 4, lq, i * 4, tv, 0); }
  /** Breathing (before IK, so IK hands / feet stay exactly on their targets): local rotations + a small rise. */
  function applyBreath(scale, pose) {
    const b = Math.sin(breathPhase) * char.breath.depth * scale * D2R;
    if (b === 0) return;
    localRot(ix.spine, 0, 0, 1, 0.5 * b);
    localRot(ix.chest, 0, 0, 1, 1.3 * b);
    localRot(ix.shoulderR, 1, 0, 0, -1.6 * b);
    localRot(ix.shoulderL, 1, 0, 0, 1.6 * b);
    localRot(ix.neck, 0, 0, 1, -0.9 * b);
    localRot(ix.head, 0, 0, 1, -0.6 * b);
    const bob = 0.003 * K * (b / D2R);
    lp[1] += bob; pose.hips[1] += bob; // kept in the pose: the blended hips include it
  }

  function resolve(pose, c) {
    for (let i = 0; i < animQ; i++) lq[i] = pose.lq[i];
    lp[0] = rig.offset[0] + pose.hips[0]; lp[1] = rig.offset[1] + pose.hips[1]; lp[2] = rig.offset[2] + pose.hips[2];
    applyBreath(c.breath, pose);
    applyCurl(pose.curl, pose.grip, c.gripHand);
    fk(rig, lq, lp, mq, mp, 0, animCount);
    // feet first: drop the pelvis (bounded, smooth) if a foot target is out of reach
    const drop = pelvisDrop(pose.ik, 2 * EFF_STRIDE, 3 * EFF_STRIDE, 1, 1);
    pose.drop = drop;
    if (drop > 0) { lp[1] -= drop; pose.hips[1] -= drop; fk(rig, lq, lp, mq, mp, 0, animCount); }
    updateBody();
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
      let rotBuf = pose.ik[o + 8] ? pose.ik : null, rotOff = o + 4;
      if (limb.kind === 'arm' && rotBuf) { // aim / up / rot describe the weapon frame: hand = weapon * rest^-1
        const wr = weaponRest[EFFECTORS[e] === 'handR' ? 'R' : 'L'];
        tv[8] = -wr[0]; tv[9] = -wr[1]; tv[10] = -wr[2]; tv[11] = wr[3];
        qmul(handTarget, 0, pose.ik, o + 4, tv, 8);
        rotBuf = handTarget; rotOff = 0;
      }
      if (limb.kind === 'arm') ikOpt.mem = e === 0 ? pose.swivelR : pose.swivelL;
      char.diag.reach[e] = solveLimb(rig, limb, lq, mq, mp, pose.ik, o + 1, rotBuf, rotOff, pose.ik[o + 12] ? pose.ik : null, o + 9, w, pose.ik[o + 13], limb.kind === 'arm' ? ikOpt : null);
      any = true;
    }
    if (any) fk(rig, lq, lp, mq, mp, 0, animCount);
    // two-handed grip of this state (the blended grip target is solved again after blending)
    pose.gripW[0] = pose.gripW[1] = 0;
    if (pose.grip > 0) {
      const g = grips[c.gripAt] || grips.grip;
      const hi = c.gripHand === 'R' ? 0 : 1, limb = hi === 0 ? limbs.handR : limbs.handL;
      if (g && limb && rig.parent[g.bone] !== limb.end) {
        reachGrip(pose, c, g, limb);
        pose.gripT.set(g.pos, 0); pose.gripT.set(g.q, 3);
        solveGrip(pose.gripT, c.gripHand, pose.grip, pose.gripT, pose.swivelG);
        pose.gripW[hi] = pose.grip;
      }
    }
    // feet as resolved (sole point + rotation), IK weight, authored pole and soft reach: re-planted after flinch
    for (let f = 0; f < 2; f++) {
      const limb = f === 0 ? limbs.footR : limbs.footL, e = limb.end, o = (2 + f) * EFF_STRIDE;
      qrot(tv, 0, mq, e * 4, limb.endOff[0], limb.endOff[1], limb.endOff[2]);
      pose.feet[f * 7] = mp[e * 3] + tv[0]; pose.feet[f * 7 + 1] = mp[e * 3 + 1] + tv[1]; pose.feet[f * 7 + 2] = mp[e * 3 + 2] + tv[2];
      qcopy(pose.feet, f * 7 + 3, mq, e * 4);
      pose.feetIK[f] = pose.ik[o];
      const hasPole = pose.ik[o] > 0 && pose.ik[o + 12] ? 1 : 0;
      pose.feetPole[f * 4 + 3] = hasPole;
      if (hasPole) { pose.feetPole[f * 4] = pose.ik[o + 9]; pose.feetPole[f * 4 + 1] = pose.ik[o + 10]; pose.feetPole[f * 4 + 2] = pose.ik[o + 11]; }
      pose.feetSoft[f] = pose.ik[o] > 0 ? pose.ik[o + 13] : -1;
    }
    for (let i = 0; i < animQ; i++) pose.lq[i] = lq[i];
  }

  /**
   * Two hands on one weapon: when the grip point is beyond the off arm's reach (shoulder assist included), move the
   * main hand's target toward the off shoulder by the excess (x grip weight) and solve the main arm again, so both
   * hands stay on the weapon instead of the off hand floating off it.
   */
  function reachGrip(pose, c, g, offLimb) {
    const main = c.mainHand === 'R' ? limbs.handR : limbs.handL, o = (c.mainHand === 'R' ? 0 : 1) * EFF_STRIDE;
    if (!main || !(pose.ik[o] > 0)) return;
    for (let it = 0; it < 2; it++) {
      qrot(tv, 0, mq, g.bone * 4, g.pos[0], g.pos[1], g.pos[2]);
      const gx = mp[g.bone * 3] + tv[0], gy = mp[g.bone * 3 + 1] + tv[1], gz = mp[g.bone * 3 + 2] + tv[2];
      const r = offLimb.root, dx = mp[r * 3] - gx, dy = mp[r * 3 + 1] - gy, dz = mp[r * 3 + 2] - gz;
      const d = Math.hypot(dx, dy, dz), reach = (offLimb.l1 + offLimb.l2) * 0.985 + 0.015 * K; // + clavicle travel
      const ex = (d - reach) * pose.grip;
      if (!(ex > 1e-4 * K)) return;
      const k = ex / d;
      pose.ik[o + 1] += dx * k; pose.ik[o + 2] += dy * k; pose.ik[o + 3] += dz * k;
      let rotBuf = pose.ik[o + 8] ? pose.ik : null, rotOff = o + 4;
      if (rotBuf) {
        const wr = weaponRest[c.mainHand];
        tv[8] = -wr[0]; tv[9] = -wr[1]; tv[10] = -wr[2]; tv[11] = wr[3];
        qmul(handTarget, 0, pose.ik, o + 4, tv, 8);
        rotBuf = handTarget; rotOff = 0;
      }
      ikOpt.mem = c.mainHand === 'R' ? pose.swivelR : pose.swivelL;
      solveLimb(rig, main, lq, mq, mp, pose.ik, o + 1, rotBuf, rotOff, pose.ik[o + 12] ? pose.ik : null, o + 9, pose.ik[o], pose.ik[o + 13], ikOpt);
      fk(rig, lq, lp, mq, mp, main.first, animCount);
    }
  }

  /**
   * Off hand onto the main weapon: target = weapon frame * rel (rel = pos (3) + quat (4) in the weapon frame), the
   * hand may roll around the grip axis to keep its wrist in range. The rolled target is written back into relOut.
   */
  function solveGrip(rel, side, w, relOut, mem) {
    const wb = grips.grip ? grips.grip.bone : Object.values(grips)[0].bone;
    qrot(gripT, 0, mq, wb * 4, rel[0], rel[1], rel[2]);
    gripT[0] += mp[wb * 3]; gripT[1] += mp[wb * 3 + 1]; gripT[2] += mp[wb * 3 + 2];
    qmul(gripQ, 0, mq, wb * 4, rel, 3);                   // off-hand weapon-frame target (model)
    const wr = weaponRest[side];
    tv[8] = -wr[0]; tv[9] = -wr[1]; tv[10] = -wr[2]; tv[11] = wr[3];
    qmul(gripT, 4, gripQ, 0, tv, 8);                      // hand target
    const ga = gripAxis[side];
    gripOpt.roll[0] = ga[0]; gripOpt.roll[1] = ga[1]; gripOpt.roll[2] = ga[2];
    const limb = side === 'R' ? limbs.handR : limbs.handL;
    gripOpt.mem = mem;
    gripOpt.rollKeep = relOut ? 0.25 : 1;
    solveLimb(rig, limb, lq, mq, mp, gripT, 0, gripT, 4, null, 0, w, SOFT, gripOpt);
    fk(rig, lq, lp, mq, mp, limb.first, animCount);
    if (relOut) { // store the rolled target relative to the weapon
      qmul(gripQ, 4, gripOpt.out, 0, wr, 0);
      qmulInv(tv, 12, mq, wb * 4, gripQ, 4);
      relOut[3] = tv[12]; relOut[4] = tv[13]; relOut[5] = tv[14]; relOut[6] = tv[15];
    }
    // residual error (diagnostics)
    const e = limb.end;
    qrot(tv, 0, mq, e * 4, limb.endOff[0], limb.endOff[1], limb.endOff[2]);
    return Math.hypot(mp[e * 3] + tv[0] - gripT[0], mp[e * 3 + 1] + tv[1] - gripT[1], mp[e * 3 + 2] + tv[2] - gripT[2]);
  }

  /**
   * Lower the hips so foot targets stay within reach of the legs. Per foot: the drop that brings the ankle target to
   * (1 - soft) of the leg length, eased in with a C1 ramp; feet combined with a smooth max; the total saturates at
   * maxDrop (C1, never a jump). buf layout: Pose.ik (stride 1, effector offsets oR / oL) or Pose.feet (stride 0, with
   * per-foot weights in wts). Returns the drop (m); does not move anything.
   */
  const maxDrop = (design.maxPelvisDrop ?? 0.16) * K;
  const dropW = new Float32Array(2);
  function pelvisDrop(buf, oR, oL, stride, kind, wts = null) {
    let a = 0, b = 0;
    for (let f = 0; f < 2; f++) {
      const o = f === 0 ? oR : oL, limb = f === 0 ? limbs.footR : limbs.footL;
      let w;
      if (stride) { w = buf[o]; if (w > 0 && buf[o + 14] >= 2) w *= 1 - buf[o + 15]; } // hips / chest-space feet move with the hips
      else w = wts ? wts[f] : 1;
      if (!(w > 0)) continue;
      const po = stride ? o + 1 : o, ro = stride ? o + 4 : o + 3;
      // only feet on (or just above) the floor pull the hips down; a foot in the air reaches as far as the leg goes
      const fh = buf[po + 1];
      w *= fh <= 0.015 * K ? 1 : fh >= 0.12 * K ? 0 : 1 - smooth01(fh, 0.015 * K, 0.12 * K);
      if (!(w > 0)) continue;
      const hasRot = stride ? buf[o + 8] : 1;
      qrot(tv, 0, hasRot ? buf : mq, hasRot ? ro : limb.end * 4, limb.endOff[0], limb.endOff[1], limb.endOff[2]);
      const ax = buf[po] - tv[0], ay = buf[po + 1] - tv[1], az = buf[po + 2] - tv[2];
      const h = limb.root * 3, dx = ax - mp[h], dz = az - mp[h + 2], dy = mp[h + 1] - ay;
      const soft = stride && buf[o + 13] >= 0 ? buf[o + 13] : SOFT;
      const R = (limb.l1 + limb.l2) * (1 - soft);
      const hz = Math.min(Math.sqrt(dx * dx + dz * dz), R * 0.9999);
      const need = dy - Math.sqrt(R * R - hz * hz); // > 0: the hips must come down by this much
      const d = softRamp(need, 0.02 * K) * w;
      if (f === 0) a = d; else b = d;
    }
    if (a <= 0 && b <= 0) return 0;
    const m = Math.pow(a ** 6 + b ** 6, 1 / 6); // smooth max (exact when one foot needs nothing)
    return softLimit(Math.max(0, m), maxDrop * 0.55, maxDrop);
  }

  function blendInto(a, b, w, gw = w) {
    if (w >= 1 && gw >= 1) { a.copy(b); return; }
    if (w <= 0 && gw <= 0) return;
    // a grip-point change: the off arm blends at the (slower) grip weight, the rest of the body at w
    const ga0 = a.gripW[0] + a.gripW[1], gb0 = b.gripW[0] + b.gripW[1];
    const change = ga0 > 0 && gb0 > 0 && gw < 1 &&
      Math.hypot(b.gripT[0] - a.gripT[0], b.gripT[1] - a.gripT[1], b.gripT[2] - a.gripT[2]) > 0.05 * K;
    const offArm = change ? (b.gripW[0] > b.gripW[1] ? armBones.R : armBones.L) : null;
    for (let i = 0; i < animCount; i++) qslerp(a.lq, i * 4, a.lq, i * 4, b.lq, i * 4, offArm && offArm[i] ? gw : w);
    for (let k = 0; k < 3; k++) a.hips[k] += (b.hips[k] - a.hips[k]) * w;
    for (let f = 0; f < 2; f++) {
      for (let k = 0; k < 3; k++) a.feet[f * 7 + k] += (b.feet[f * 7 + k] - a.feet[f * 7 + k]) * w;
      qslerp(a.feet, f * 7 + 3, a.feet, f * 7 + 3, b.feet, f * 7 + 3, w);
      a.feetIK[f] += (b.feetIK[f] - a.feetIK[f]) * w;
      const ha = a.feetPole[f * 4 + 3], hb = b.feetPole[f * 4 + 3];
      if (hb > 0 && ha <= 0) for (let k = 0; k < 3; k++) a.feetPole[f * 4 + k] = b.feetPole[f * 4 + k];
      else if (hb > 0) for (let k = 0; k < 3; k++) a.feetPole[f * 4 + k] += (b.feetPole[f * 4 + k] - a.feetPole[f * 4 + k]) * w;
      a.feetPole[f * 4 + 3] = ha + (hb - ha) * w;
      if (w >= 0.5) a.feetSoft[f] = b.feetSoft[f];
    }
    if (a.lookW <= 0) a.look.set(b.look);
    else if (b.lookW > 0) for (let k = 0; k < 3; k++) a.look[k] += (b.look[k] - a.look[k]) * w;
    a.lookW += (b.lookW - a.lookW) * w;
    // grip target (weapon frame): position lerp, orientation slerp (at the grip weight gw); a state without grip
    // contributes no target
    const ga = a.gripW[0] + a.gripW[1], gb = b.gripW[0] + b.gripW[1];
    let let_go = 1;
    if (gb > 0 && ga <= 0) a.gripT.set(b.gripT);
    else if (gb > 0) {
      // changing grip point (pommel -> blade): the hand lets go in the middle of the fade and the two solved arm
      // poses blend (the hand travels with the arm instead of being dragged along the weapon by IK)
      const d = Math.hypot(b.gripT[0] - a.gripT[0], b.gripT[1] - a.gripT[1], b.gripT[2] - a.gripT[2]);
      // free from the start of the grip fade (the arm blends between the two solved grips), re-grip over the last 45%
      const free = 1 - smooth01(gw, 0.55, 1);
      let_go = 1 - free * Math.min(1, d / (0.15 * K));
      for (let k = 0; k < 3; k++) a.gripT[k] += (b.gripT[k] - a.gripT[k]) * gw;
      qslerp(a.gripT, 3, a.gripT, 3, b.gripT, 3, gw);
    }
    a.gripW[0] += (b.gripW[0] - a.gripW[0]) * w; a.gripW[1] += (b.gripW[1] - a.gripW[1]) * w;
    a.gripW[0] *= let_go; a.gripW[1] *= let_go;
    a.grip += (b.grip - a.grip) * w;
    a.drop += (b.drop - a.drop) * w;
    a.curl[0] += (b.curl[0] - a.curl[0]) * w; a.curl[1] += (b.curl[1] - a.curl[1]) * w;
  }

  // ---- layers ------------------------------------------------------------------------------------------------------
  /**
   * Masked override or additive layer. opts: { weight = 1, mask: 'upper'|'lower'|'arms'|'head'|[bone names] (override
   * layers), additive = false, speed = 1, loop = clip.loop, fade = 0.15, scale }. Additive layers add the clip's motion
   * relative to its first frame.
   */
  function layer(name, clip, o = {}) {
    const c = getClip(rig, clip);
    let L = layers.get(name);
    if (!L) { L = { pose: new Pose(rig), ref: new Pose(rig), mask: new Uint8Array(N) }; layers.set(name, L); }
    L.c = c; L.time = 0; L.speed = o.speed ?? 1; L.loop = o.loop ?? c.loop; L.additive = !!o.additive;
    L.target = o.weight ?? 1; L.w = L.w || 0; L.fade = o.fade ?? 0.15; L.stopping = false;
    L.scale = o.scale ?? design.clipScale ?? 1;
    const m = o.mask || 'upper';
    for (let i = 0; i < N; i++) L.mask[i] = Array.isArray(m) ? (m.includes(rig.names[i]) ? 1 : 0) : MASKS[m] ? (MASKS[m](rig.names[i]) ? 1 : 0) : 1;
    if (L.additive) sampleClip(rig, c, 0, L.ref, L.scale);
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
      sampleClip(rig, L.c, L.time, L.pose, L.scale);
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
      resolve(L.pose, L.c);
      for (let i = 0; i < animCount; i++) if (L.mask[i]) qslerp(final.lq, i * 4, final.lq, i * 4, L.pose.lq, i * 4, L.w);
      if (L.mask[0]) for (let k = 0; k < 3; k++) final.hips[k] += (L.pose.hips[k] - final.hips[k]) * L.w;
      if (L.mask[ix.weaponR] || L.mask[ix.handL]) { // the layer owns the hands: its grip target and weight
        const gl = L.pose.gripW[0] + L.pose.gripW[1];
        if (gl > 0) {
          if (final.gripW[0] + final.gripW[1] <= 0) final.gripT.set(L.pose.gripT);
          else { for (let k = 0; k < 3; k++) final.gripT[k] += (L.pose.gripT[k] - final.gripT[k]) * L.w; qslerp(final.gripT, 3, final.gripT, 3, L.pose.gripT, 3, L.w); }
        }
        final.gripW[0] += (L.pose.gripW[0] - final.gripW[0]) * L.w; final.gripW[1] += (L.pose.gripW[1] - final.gripW[1]) * L.w;
        final.grip += (L.pose.grip - final.grip) * L.w;
      }
    }
  }

  // ---- additive procedural motion ----------------------------------------------------------------------------------
  /** Physical flinch: { bone = 'body' | bone name, dir: [f,u,s] push direction, amount = 1 }. */
  function impulse({ bone = 'body', dir = [-1, 0, 0], amount = 1 } = {}) {
    let dx = dir[0], dy = dir[1], dz = dir[2];
    const l = Math.hypot(dx, dy, dz);
    if (!(l > 1e-9) || !Number.isFinite(l) || !Number.isFinite(amount)) return char;
    amount = Math.max(-4, Math.min(4, amount));
    dx /= l; dy /= l; dz /= l;
    // rotation axis = up x dir (push at the chest tips the torso along dir)
    const ax = dz, az = -dx;
    if (bone === 'body') {
      const k = 3.2 * amount, S = springsBody;
      S.om[0] += ax * k; S.om[2] += az * k;
      S.hom[0] += ax * k * 1.4; S.hom[2] += az * k * 1.4;
      S.v[0] += dx * 0.55 * amount * K; S.v[1] += (dy * 0.35 - 0.12) * amount * K; S.v[2] += dz * 0.45 * amount * K;
      // stacked hits saturate (a launcher is ~3; thirty hits in a row are not thirty times one)
      const cap = (v, m) => { const n = Math.hypot(v[0], v[1], v[2]); if (n > m) { const c = softLimit(n, m * 0.6, m) / n; v[0] *= c; v[1] *= c; v[2] *= c; } };
      cap(S.om, 9); cap(S.hom, 12); cap(S.v, 1.4 * K);
    } else {
      if (ix[bone] === undefined) return char;
      let s = boneSprings.get(bone);
      if (!s) { s = { i: ix[bone], th: new Float32Array(3), om: new Float32Array(3) }; boneSprings.set(bone, s); boneSpringList.push(s); }
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

  /** Flinch springs (after IK: a physical push moves hands and weapon too; feet are re-planted). Returns true if active. */
  function flinch(dt) {
    const S = springsBody;
    // spring steps are sub-stepped at <= 1/120 s so the response is the same at 30, 60 and 120 Hz
    const n = Math.max(1, Math.ceil(dt * 120 - 1e-6)), h = dt / n;
    for (let i = 0; i < n; i++) {
      stepSpring(S.th, S.om, 170, 15, h);
      for (let a = 0; a < 3; a++) { S.hom[a] += (-120 * (S.hth[a] - S.th[a] * 1.2) - 9 * S.hom[a]) * h; S.hth[a] += S.hom[a] * h; }
      stepSpring(S.x, S.v, 110, 13, h);
      for (let k = 0; k < boneSpringList.length; k++) stepSpring(boneSpringList[k].th, boneSpringList[k].om, 160, 12, h);
    }
    let active = false;
    if (Math.abs(S.th[0]) + Math.abs(S.th[2]) + Math.abs(S.hth[0]) + Math.abs(S.hth[2]) > 1e-5) {
      addRot(ix.hips, S.th[0] * 0.25, 0, S.th[2] * 0.25);
      addRot(ix.spine, S.th[0] * 0.35, 0, S.th[2] * 0.35);
      addRot(ix.chest, S.th[0] * 0.45, 0, S.th[2] * 0.45);
      addRot(ix.neck, S.hth[0] * 0.35, 0, S.hth[2] * 0.35);
      addRot(ix.head, S.hth[0] * 0.45, 0, S.hth[2] * 0.45);
      addRot(ix.shoulderR, S.hth[0] * 0.3, 0, S.hth[2] * 0.2);
      addRot(ix.shoulderL, S.hth[0] * 0.3, 0, S.hth[2] * 0.2);
      active = true;
    }
    if (Math.abs(S.x[0]) + Math.abs(S.x[1]) + Math.abs(S.x[2]) > 1e-6) { lp[0] += S.x[0]; lp[1] += S.x[1]; lp[2] += S.x[2]; active = true; }
    for (let k = 0; k < boneSpringList.length; k++) {
      const s = boneSpringList[k];
      if (Math.abs(s.th[0]) + Math.abs(s.th[1]) + Math.abs(s.th[2]) > 1e-6) { addRot(s.i, s.th[0], s.th[1], s.th[2]); active = true; }
    }
    return active;
  }

  // ---- look / facing / misc ----------------------------------------------------------------------------------------
  /** Head tracking: target = THREE.Vector3 | Object3D (world) | null; weight 0..1 (blended in over ~0.2 s). */
  function lookAt(target, weight = 1) { lookRT.target = target; lookRT.weight = target ? weight : 0; return char; }

  /**
   * Face +X (1) or -X (-1). opts.turn = seconds: spin through a quick turn instead of an instant mirror. The world
   * scale magnitude (char.scale, design.scale) is kept.
   */
  function setFacing(f, o = {}) {
    const nf = f < 0 ? -1 : 1;
    if (nf === facing) return char;
    facing = nf;
    root.scale.x = facing * Math.abs(root.scale.x || 1);
    footLock[0].on = footLock[1].on = false; footLock[0].w = footLock[1].w = 0;
    if (o.turn > 0) { turnDur = turnLeft = o.turn; turnFrom = facing < 0 ? Math.PI : -Math.PI; root.rotation.y = turnFrom; }
    return char;
  }

  /** Reset cloth, spring bones and flinch springs (after placing the character somewhere new). */
  function teleport() {
    haveLast = false;
    for (const s of states) s.pose.swivel.fill(0);
    gripMem.fill(0); twistMem.fill(0); dropHold = 0;
    footLock[0].on = footLock[1].on = false; footLock[0].w = footLock[1].w = 0; footPlanted.fill(0);
    for (const k of ['th', 'om', 'hth', 'hom', 'x', 'v']) springsBody[k].fill(0);
    for (const b of boneSpringList) { b.th.fill(0); b.om.fill(0); }
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
  function computeInertia(dt) {
    root.updateMatrixWorld();
    curWorld.copy(root.matrixWorld);
    invWorld.copy(curWorld).invert();
    let ok = haveLast;
    if (ok) {
      const e = curWorld.elements, l = lastWorld.elements;
      const dx = e[12] - l[12], dy = e[13] - l[13], dz = e[14] - l[14];
      // teleport: faster than 30 m/s x body / world scale (a dash at 20 m/s still feeds the cloth at dt 1/30)
      const lim = 30 * K * Math.abs(root.scale.y || 1) * Math.max(dt, 1 / 60);
      if (dx * dx + dy * dy + dz * dz > lim * lim) ok = false;
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
    gravL[0] = ie[4] * -9.81; gravL[1] = ie[5] * -9.81; gravL[2] = ie[6] * -9.81;
    const w = char.wind;
    windL[0] = ie[0] * w[0] + ie[4] * w[1] + ie[8] * w[2]; windL[1] = ie[1] * w[0] + ie[5] * w[1] + ie[9] * w[2]; windL[2] = ie[2] * w[0] + ie[6] * w[1] + ie[10] * w[2];
    tmpV.set(curWorld.elements[12], 0, curWorld.elements[14]).applyMatrix4(invWorld);
    return tmpV.y;
  }

  /**
   * Foot locks: a foot that is planted when a crossfade starts keeps its world position (instead of sliding with the
   * pose blend) until the incoming animation lifts it or puts it more than 0.25 m away; then it is released over
   * 0.15 s. Writes the locked targets into final.feet. Returns true if any lock is active.
   */
  function applyFootLocks(dt, floorY) {
    let any = false;
    for (let f = 0; f < 2; f++) {
      const L = footLock[f], o = f * 7;
      const planted = final.feetIK[f] > 0.5 && final.feet[o + 1] - floorY < 0.015 * K;
      if (lockPending && footPlanted[f] && planted && !L.on) {
        L.on = true; L.w = 1;
        L.p[0] = footWorld[f * 3]; L.p[1] = footWorld[f * 3 + 1]; L.p[2] = footWorld[f * 3 + 2];
      }
      if (!L.on && L.w <= 0) continue;
      lockV.set(L.p[0], L.p[1], L.p[2]).applyMatrix4(invWorld);
      const far = Math.hypot(lockV.x - final.feet[o], lockV.z - final.feet[o + 2]) > 0.25 * K;
      if (L.on && (!planted || far)) L.on = false;
      if (!L.on) { L.w = Math.max(0, L.w - dt / 0.15); if (L.w <= 0) continue; }
      const w = L.w * L.w * (3 - 2 * L.w);
      final.feet[o] += (lockV.x - final.feet[o]) * w;
      final.feet[o + 2] += (lockV.z - final.feet[o + 2]) * w;
      any = true;
    }
    lockPending = false;
    return any;
  }

  // ---- main update -------------------------------------------------------------------------------------------------
  const footEq = new Float32Array(3);
  /** Advance animation, IK, secondary motion and cloth. Call once per frame. */
  function update(dtGame, dtReal = dtGame) {
    const dt = Math.max(0, Number.isFinite(dtGame) ? dtGame : 0);
    simTime += dt;
    // flip turn
    if (turnLeft > 0) {
      turnLeft = Math.max(0, turnLeft - dt);
      const k = turnLeft / turnDur;
      root.rotation.y = turnFrom * k * k * (3 - 2 * k);
    }
    const floorY = computeInertia(dt);
    char.rootDelta.f = 0; char.rootDelta.u = 0;
    if (states.length === 0) play(design.idle || 'neutral.hold', { fade: 0 });
    for (let k = 0; k < states.length; k++) advance(states[k], dt, k === states.length - 1);
    // root motion of every state, weighted by its share of the blend (a fading walk keeps carrying its planted feet)
    let keep = 1;
    for (let k = states.length - 1; k >= 0; k--) {
      const s = states[k], we = (k === 0 ? 1 : s.w) * keep;
      char.rootDelta.f += s.df * we; char.rootDelta.u += s.du * we;
      keep *= 1 - (k === 0 ? 1 : s.w);
    }
    // drop states hidden under a fully faded-in newer one
    for (let k = states.length - 1; k > 0; k--) {
      if (states[k].w >= 1 && states[k].gw >= 1) { while (k > 0) { statePool.push(states.shift()); k--; } break; }
    }
    const cur = states[states.length - 1];
    // elbow swivel speed limit of the arm IK this update (~1500 deg/s: the same path at any frame rate)
    ikOpt.maxStep = gripOpt.maxStep = Math.min(Math.PI, 26 * dt);
    breathPhase += dt * char.breath.rate * Math.PI * 2;
    if (breathPhase > 1e4) breathPhase %= Math.PI * 2;
    for (let k = 0; k < states.length; k++) {
      const s = states[k];
      if (!s.frozen) { sampleClip(rig, s.c, s.time, s.pose, s.scale); resolve(s.pose, s.c); }
      s.resolved = false;
      if (k === 0) final.copy(s.pose); else blendInto(final, s.pose, s.w, s.gw);
    }
    if (layers.size) applyLayers(dt);
    // the hips go down as fast as the planted feet need, but come back up smoothly (~80 ms) when a foot lifts
    const release = dropHold - final.drop;
    dropHold = release > 0 ? final.drop + release * Math.exp(-dt / 0.08) : final.drop;
    const extraDrop = dropHold - final.drop;
    char.diag.drop = dropHold;
    // final pose -> local arrays
    for (let i = 0; i < animQ; i++) lq[i] = final.lq[i];
    lp[0] = rig.offset[0] + final.hips[0]; lp[1] = rig.offset[1] + final.hips[1] - extraDrop; lp[2] = rig.offset[2] + final.hips[2];
    applyCurl(final.curl, final.grip, cur.c.gripHand);
    fk(rig, lq, lp, mq, mp, 0, animCount);
    const locked = applyFootLocks(dt, floorY);
    const moved = flinch(dt) || states.length > 1 || layers.size > 0 || extraDrop > 1e-5 || locked;
    if (moved) fk(rig, lq, lp, mq, mp, 0, animCount);
    // re-plant feet where the blended animation put them, then keep them on the floor
    for (let f = 0; f < 2; f++) {
      const h = final.feet[f * 7 + 1] - floorY;
      dropW[f] = final.feetIK[f] * (h < 0.06 * K ? 1 : h > 0.25 * K ? 0 : 1 - (h - 0.06 * K) / (0.19 * K));
    }
    if (moved) {
      const d = pelvisDrop(final.feet, 0, 7, 0, 0, dropW);
      if (d > 0) { lp[1] -= d; fk(rig, lq, lp, mq, mp, 0, animCount); char.diag.drop += d; }
    }
    char.diag.footErr = 0;
    for (let f = 0; f < 2; f++) {
      const limb = f === 0 ? limbs.footR : limbs.footL;
      const h = final.feet[f * 7 + 1] - floorY;
      const w = h < 0.06 * K ? 1 : h > 0.25 * K ? 0 : 1 - (h - 0.06 * K) / (0.19 * K);
      if (w > 0 && moved) {
        const e = limb.end;
        qrot(footEq, 0, mq, e * 4, limb.endOff[0], limb.endOff[1], limb.endOff[2]);
        const off = Math.hypot(mp[e * 3] + footEq[0] - final.feet[f * 7], mp[e * 3 + 1] + footEq[1] - final.feet[f * 7 + 1], mp[e * 3 + 2] + footEq[2] - final.feet[f * 7 + 2]);
        const qd = Math.abs(mq[e * 4] * final.feet[f * 7 + 3] + mq[e * 4 + 1] * final.feet[f * 7 + 4] + mq[e * 4 + 2] * final.feet[f * 7 + 5] + mq[e * 4 + 3] * final.feet[f * 7 + 6]);
        if (off > 1e-4 * K || qd < 0.9999996) {
          const hp = final.feetPole[f * 4 + 3] > 0.5;
          if (hp) { poleBuf[0] = final.feetPole[f * 4]; poleBuf[1] = final.feetPole[f * 4 + 1]; poleBuf[2] = final.feetPole[f * 4 + 2]; }
          solveLimb(rig, limb, lq, mq, mp, final.feet, f * 7, final.feet, f * 7 + 3, hp ? poleBuf : null, 0, w, final.feetSoft[f]);
          fk(rig, lq, lp, mq, mp, limb.first, animCount);
        }
      }
      floorFoot(rig, limb, lq, lp, mq, mp, floorY, footBuf);
      if (final.feetIK[f] > 0.5) { // diagnostics: planted IK foot vs its target
        const e = limb.end;
        qrot(footEq, 0, mq, e * 4, limb.endOff[0], limb.endOff[1], limb.endOff[2]);
        char.diag.footErr = Math.max(char.diag.footErr, Math.hypot(mp[e * 3] + footEq[0] - final.feet[f * 7], mp[e * 3 + 2] + footEq[2] - final.feet[f * 7 + 2]));
      }
    }
    // world sole points (foot locks of the next crossfade)
    for (let f = 0; f < 2; f++) {
      const limb = f === 0 ? limbs.footR : limbs.footL, e = limb.end;
      qrot(footEq, 0, mq, e * 4, limb.endOff[0], limb.endOff[1], limb.endOff[2]);
      lockV.set(mp[e * 3] + footEq[0], mp[e * 3 + 1] + footEq[1], mp[e * 3 + 2] + footEq[2]);
      footPlanted[f] = final.feetIK[f] > 0.5 && lockV.y - floorY < 0.012 * K ? 1 : 0;
      lockV.applyMatrix4(curWorld);
      footWorld[f * 3] = lockV.x; footWorld[f * 3 + 1] = lockV.y; footWorld[f * 3 + 2] = lockV.z;
    }
    // two-handed grip on the blended grip target; the newest clip's own grip solve then follows this one's swivel, so
    // the arm cannot switch solutions when a crossfade ends
    char.diag.gripErr = 0;
    updateBody();
    for (let hi = 0; hi < 2; hi++) {
      const w = final.gripW[hi];
      if (!(w > 0)) continue;
      const side = hi === 0 ? 'R' : 'L';
      const g = grips.grip || Object.values(grips)[0];
      if (!g || rig.parent[g.bone] === (hi === 0 ? limbs.handR : limbs.handL).end) continue; // never IK a hand onto the weapon it holds
      char.diag.gripErr = Math.max(char.diag.gripErr, solveGrip(final.gripT, side, w, null, gripMem) * (w >= 1 ? 1 : w));
      cur.pose.swivelG.set(gripMem);
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
    driveHelpers(rig, lq, twistMem);
    if (followers.length) driveFollowers();
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
    for (let k = 0; k < scaled.length; k++) {
      const i = scaled[k], hs = rig.helperScale;
      bones[i].scale.set(hs[i * 3], hs[i * 3 + 1], hs[i * 3 + 2]);
    }
    if (char.applyRootMotion) { root.position.x += char.rootDelta.f * facing; root.position.y += char.rootDelta.u; }
    root.updateMatrixWorld(true);
    // hit flash (real time)
    if (flashState.t < 1) {
      flashState.t = Math.min(1, flashState.t + (dtReal || 0) / flashState.dur);
      const k = (1 - flashState.t) * (1 - flashState.t) * flashState.amount;
      flashCol.copy(flashState.color).multiplyScalar(k);
      for (let i = 0; i < materialList.length; i++) materialList[i].userData.kit.uFlash.value.copy(flashCol);
    }
    return char;
  }
  const materialList = Object.values(materials);

  // initial pose: neutral, matrices valid before the first update
  fk(rig, lq, lp, mq, mp);
  if (opts.parent !== null) (opts.parent || ctx.scene).add(root);
  return char;
}

// a minimal always-available hold clip (zero motion, neutral pose)
defineClip('neutral.hold', { duration: 1, loop: true, keys: [{ t: 0, pose: 'neutral' }] });
