// Rig audit lab, lens MATH: skeleton math, axis conventions, mirroring, two-bone IK, two-handed grip, ground contact,
// proportions / scale. Read-only on src/char: everything here measures the runtime as shipped.
//
//   node tools/shot.mjs rigaudit_math --eval "__ED.audit.run('conventions')"      JSON results (__ED.audit.list())
//   tests: conventions examples mirror facing keepFK | ikPure ikSweep ikPole ikPoleGiant ikPipeline ikPipelineBent
//          spaces hipsFoot resolveDropHand kneePole dropSweep toeRoll misc | grip gripSwitch gripReach aimRoll fingers
//          wrist twistPops | contact contact30 contactNoBreath hipsJerk fadeSlide | props giantNorm cpu
//          trace(clip, start, f0, f1, bones) traceFeet(clip, start, f0, f1, every)
//   scenarios (captures): reset clip(name, id, start, view) gripswitch guardroll dropsweep hipsfoot kneepole polesweep
//          kicksweep fadeslide turn lineup giant

import * as THREE from 'three';
import { RoomEnvironment } from 'three/examples/jsm/environments/RoomEnvironment.js';
import { createLab, ORDER } from '../core/lab.js';
import { makeRng } from '../core/math.js';
import { createCharacter, defineClip, definePose, mirrorClip, mirrorPose, invalidateClips } from '../char/index.js';
import { getClip, getClipDef, getPoseDef, sampleClip, Pose } from '../char/anim.js';
import { createRig, fk, DEFAULT_PROPORTIONS } from '../char/skeleton.js';
import { makeLimbs, solveLimb } from '../char/ik.js';
import { knight } from '../char/designs/knight.js';
import '../char/clips/demo.js';

// ---- proportion sets ---------------------------------------------------------------------------------------------
const GIANT_K = 4.2;
const PROPS = {
  kael: {},
  // ~1.78 m, slender, female proportions
  iska: { hipHeight: 0.93, pelvisDrop: 0.055, hipWidth: 0.094, ankleHeight: 0.075, footLength: 0.12, footDrop: 0.048, toeLength: 0.07, heelLength: 0.058,
    spine: 0.10, chest: 0.152, neck: 0.235, head: 0.098, shoulderHeight: 0.185, clavicleRoot: 0.026, clavicle: 0.163, shoulderBack: 0.012,
    upperArm: 0.28, foreArm: 0.245, hand: 0.076, palm: 0.019 },
  // ~2.02 m, long-limbed lancer
  vorn: { hipHeight: 1.05, pelvisDrop: 0.064, hipWidth: 0.104, ankleHeight: 0.09, footLength: 0.145, footDrop: 0.058, toeLength: 0.086, heelLength: 0.07,
    spine: 0.116, chest: 0.18, neck: 0.265, head: 0.11, shoulderHeight: 0.21, clavicleRoot: 0.032, clavicle: 0.2, shoulderBack: 0.016,
    upperArm: 0.325, foreArm: 0.29, hand: 0.09, palm: 0.023 },
  giant: Object.fromEntries(Object.entries(DEFAULT_PROPORTIONS).map(([k, v]) => [k, k === 'thighRatio' ? v : v * GIANT_K])),
};
const hipsPivot = (P) => (P.hipHeight ?? DEFAULT_PROPORTIONS.hipHeight) + (P.pelvisDrop ?? DEFAULT_PROPORTIONS.pelvisDrop);
const SCALE = Object.fromEntries(Object.entries(PROPS).map(([k, P]) => [k, hipsPivot(P) / hipsPivot(DEFAULT_PROPORTIONS)]));

function variant(id) {
  if (id === 'kael') return knight;
  const k = id === 'giant' ? GIANT_K : 1;
  const w = knight.weapon;
  return {
    ...knight, id: 'audit_' + id, proportions: PROPS[id], cloth: id === 'giant' ? [] : knight.cloth,
    weapon: { ...w, base: w.base.map((v) => v * k), tip: w.tip.map((v) => v * k), grips: { grip: { pos: [-0.155 * k, 0, 0] }, blade: { pos: [0.56 * k, 0, 0] } } },
  };
}

// ---- clip helpers ------------------------------------------------------------------------------------------------
function resolveKeyLocal(k) {
  if (!k.pose) return k;
  const base = resolveKeyLocal(getPoseDef(k.pose));
  const out = { ...base, ...k };
  delete out.pose;
  for (const ch of ['bones', 'ik']) if (base[ch] || k[ch]) out[ch] = { ...(base[ch] || {}), ...(k[ch] || {}) };
  if (base.hips || k.hips) out.hips = { ...(base.hips || {}), ...(k.hips || {}) };
  return out;
}
const sc = (v, s) => (Array.isArray(v) ? v.map((x) => x * s) : v);
function scaleKey(k0, s) {
  const k = resolveKeyLocal(k0);
  const o = { ...k };
  if (k.hips) o.hips = { ...k.hips, pos: sc(k.hips.pos, s) };
  if (k.ik) { o.ik = {}; for (const [e, v] of Object.entries(k.ik)) o.ik[e] = v && { ...v, pos: sc(v.pos, s), pole: sc(v.pole, s) }; }
  if (k.root) o.root = Array.isArray(k.root) ? sc(k.root, s) : { ...k.root, pos: sc(k.root.pos, s) };
  if (k.look && k.look.at) o.look = { ...k.look, at: sc(k.look.at, s) };
  return o;
}
/** Register `dst` = clip `src` with every positional channel scaled by s (what a retargeting option would do). */
function scaledClip(src, dst, s) {
  const d = getClipDef(src);
  const base = typeof d.base === 'string' ? scaleKey({ pose: d.base }, s) : undefined;
  defineClip(dst, { ...d, base, keys: d.keys.map((k) => scaleKey(k, s)) });
  return dst;
}

const DEMO = ['demo.idle', 'demo.guard', 'demo.walkF', 'demo.walkB', 'demo.combo1', 'demo.combo2', 'demo.combo3', 'demo.slam', 'demo.hit', 'demo.combo1M'];

// ---- measurement utilities ---------------------------------------------------------------------------------------
let CTX = null;
const charCache = new Map();
function mk(id) {
  if (charCache.has(id)) return charCache.get(id);
  const c = createCharacter(CTX, variant(id), { parent: null, name: 'audit_' + id });
  charCache.set(id, c);
  return c;
}
function resetChar(c, clip = 'demo.idle') {
  c.root.position.set(0, 0, 0); c.root.rotation.set(0, 0, 0); c.setFacing(1); c.root.scale.set(1, 1, 1);
  c.breath.depth = 1; c.lookAt(null); c.wind = [0, 0, 0];
  c.play(clip, { fade: 0, restart: true });
  c.teleport();
  c.update(0, 0); c.root.updateMatrixWorld(true);
}
function step(c, dt = 1 / 60, applyRoot = true) {
  c.update(dt, dt);
  if (applyRoot) { c.root.position.x += c.rootDelta.f * c.facing; c.root.position.y += c.rootDelta.u; }
  c.root.updateMatrixWorld(true);
}
const V = () => new THREE.Vector3();
const _inv = new THREE.Matrix4();
function wpos(c, bone, pt = [0, 0, 0], out = V()) { return out.set(pt[0], pt[1], pt[2]).applyMatrix4(c.bones[bone].matrixWorld); }
function lpos(c, bone, pt = [0, 0, 0], out = V()) { _inv.copy(c.root.matrixWorld).invert(); return wpos(c, bone, pt, out).applyMatrix4(_inv); }
function wquat(c, bone, out = new THREE.Quaternion()) { c.bones[bone].matrixWorld.decompose(_tv, out, _ts); return out; }
const _tv = V(), _ts = V();
const r1 = (x, d = 1) => Math.round(x * 10 ** d) / 10 ** d;
const mm = (x) => r1(x * 1000, 2);
const deg = (r) => r1((r * 180) / Math.PI, 2);
const qAngle = (a, b) => 2 * Math.acos(Math.min(1, Math.abs(a.dot(b))));
function stats(a) {
  if (!a.length) return { n: 0 };
  const s = [...a].sort((x, y) => x - y);
  return { n: a.length, mean: s.reduce((p, x) => p + x, 0) / s.length, max: s[s.length - 1], p50: s[Math.floor(s.length * 0.5)], p95: s[Math.floor(s.length * 0.95)], min: s[0] };
}
const statsMM = (a) => { const s = stats(a); return s.n ? { n: s.n, mean: mm(s.mean), p50: mm(s.p50), p95: mm(s.p95), max: mm(s.max) } : s; };
function anyNaN(c) { for (const b of Object.values(c.bones)) { const e = b.matrixWorld.elements; for (let i = 0; i < 16; i++) if (!Number.isFinite(e[i])) return b.name; } return null; }
/** Twist (about local Y) and swing angles of a local quaternion, degrees. */
function twistSwing(q) {
  let w = q.w, y = q.y; if (w < 0) { w = -w; y = -y; }
  const tw = 2 * Math.atan2(y, w);
  const t = new THREE.Quaternion(0, Math.sin(tw / 2), 0, Math.cos(tw / 2));
  const sw = q.clone().multiply(t.invert());
  return { twist: (tw * 180) / Math.PI, swing: (2 * Math.acos(Math.min(1, Math.abs(sw.w))) * 180) / Math.PI };
}
function animatedNames(c) {
  const extra = new Set((c.design.bones || []).map((b) => b.name));
  return c.rig.names.filter((n, i) => i < c.rig.names.length && !c.rig.helper[i] && !extra.has(n) && !/_\d+_\d+$/.test(n));
}

// ---- 1. conventions ----------------------------------------------------------------------------------------------
// expected direction of the marker movement for a +30 deg rotation (right / centre bones; left bones flip s)
const EXP = {
  hips: { X: ['tip', [0, 0, 1], 'side-bend: top toward +s'], Y: ['front', [0, 0, -1], 'turn left: front toward -s'], Z: ['tip', [-1, 0, 0], 'tilt back: top toward -f'] },
  spine: { X: ['tip', [0, 0, 1], 'same as hips'], Y: ['front', [0, 0, -1], 'same'], Z: ['tip', [-1, 0, 0], 'lean back'] },
  chest: { X: ['tip', [0, 0, 1], 'same as hips'], Y: ['front', [0, 0, -1], 'same'], Z: ['tip', [-1, 0, 0], 'lean back'] },
  neck: { X: ['tip', [0, 0, 1], 'same as hips'], Y: ['front', [0, 0, -1], 'same'], Z: ['tip', [-1, 0, 0], 'head back'] },
  head: { X: ['tip', [0, 0, 1], 'ear toward +s shoulder'], Y: ['front', [0, 0, -1], 'look left (-s)'], Z: ['front', [0, 1, 0], 'look up'] },
  shoulder: { X: ['tip', [0, -1, 0], 'depress'], Y: ['tip', [1, 0, 0], 'protract'], Z: ['elbow', null, 'roll about the clavicle'] },
  upperArm: { X: ['tip', [0, 0, -1], 'adduct toward midline'], Y: ['front', [0, 0, -1], 'internal rotation'], Z: ['tip', [1, 0, 0], 'raise forward'] },
  foreArm: { X: ['tip', null, 'not anatomical'], Y: ['front', [0, 0, -1], 'pronation (thumb to midline)'], Z: ['tip', [1, 0, 0], 'bend elbow'] },
  hand: { X: ['tip', [0, 0, -1], 'flex toward palm (midline)'], Y: ['front', [0, 0, -1], 'thumb toward midline'], Z: ['tip', [1, 0, 0], 'radial (toward thumb)'] },
  weapon: { X: ['edge', null, 'roll about the blade'], Y: ['tip', [0, 0, -1], 'yaw toward midline'], Z: ['tip', [0, 1, 0], 'tip up'] },
  thigh: { X: ['tip', [0, 0, -1], 'adduct'], Y: ['front', [0, 0, -1], 'internal rotation (knee to midline)'], Z: ['tip', [1, 0, 0], 'hip flexion'] },
  shin: { X: ['tip', null, 'keep 0'], Y: ['front', null, 'keep 0'], Z: ['tip', [1, 0, 0], '+Z hyperextends (ankle forward)'] },
  foot: { X: ['bottom', [0, 0, -1], 'invert (sole to midline)'], Y: ['tip', [0, 0, -1], 'toe-in'], Z: ['tip', [0, 1, 0], 'toes up'] },
  toe: { X: ['tip', null, '-'], Y: ['tip', null, '-'], Z: ['tip', [0, 1, 0], 'toes up'] },
  fingers: { X: ['tip', null, 'curl channel only'] },
  fingerTips: { X: ['tip', null, 'curl channel only'] },
  thumb: { X: ['tip', null, 'curl channel only'] },
};
function markersFor(c, base, S) {
  const P = c.rig.P, L = c.rig.lengths, z = S === 'L' ? -1 : 1, b = base + S;
  switch (base) {
    case 'hips': case 'spine': case 'chest': case 'neck': return { tip: [base, [0, 0.3, 0]], front: [base, [0.2, 0, 0]] };
    case 'head': return { tip: ['head', [0, 0.22, 0]], front: ['head', [0.2, 0, 0]] };
    case 'shoulder': return { tip: [b, [-P.shoulderBack, 0, z * P.clavicle]], elbow: ['upperArm' + S, [0, -P.upperArm, 0]] };
    case 'upperArm': return { tip: [b, [0, -P.upperArm, 0]], front: [b, [0.15, -0.15, 0]] };
    case 'foreArm': return { tip: [b, [0, -P.foreArm, 0]], front: ['hand' + S, [0.15, -0.04, 0]] };
    case 'hand': return { tip: [b, [0, -0.15, 0]], front: [b, [0.15, -0.04, 0]] };
    case 'weapon': return { tip: [b, [1, 0, 0]], edge: [b, [0.3, -0.15, 0]] };
    case 'thigh': return { tip: [b, [0, -L.thigh, 0]], front: [b, [0.15, -0.2, 0]] };
    case 'shin': return { tip: [b, [0, -L.shin, 0]], front: [b, [0.15, -0.2, 0]] };
    case 'foot': return { tip: [b, [P.footLength, -P.footDrop, 0]], bottom: [b, [0, -P.ankleHeight, 0]] };
    case 'toe': return { tip: [b, [P.toeLength, -(P.ankleHeight - P.footDrop), 0]] };
    default: return { tip: [b, [0, -0.05, 0]] };
  }
}
function zeroPoseDef(c, extraBones = {}) {
  const bones = {};
  for (const n of animatedNames(c)) if (n !== 'hips') bones[n] = [0, 0, 0];
  Object.assign(bones, extraBones);
  return { hips: { pos: [0, 0, 0], rot: [0, 0, 0] }, bones, grip: 0, curl: [0, 0] };
}
function holdPose(c, name, def) {
  definePose(name, def);
  invalidateClips();
  c.play(name, { fade: 0, restart: true });
  step(c, 1 / 60, false); step(c, 1 / 60, false);
}
function testConventions(id = 'kael') {
  const c = mk(id);
  resetChar(c);
  c.breath.depth = 0;
  c.root.position.y = 1.5; // off the floor: no floor contact / re-plant interference
  holdPose(c, 'audit.zero', zeroPoseDef(c));
  const rows = [], bad = [];
  const pivotOf = (bone) => wpos(c, bone);
  for (const name of animatedNames(c)) {
    const S = /[RL]$/.test(name) && name !== 'hips' ? name.slice(-1) : '';
    const base = S ? name.slice(0, -1) : name;
    const exp = EXP[base];
    if (!exp) continue;
    const marks = markersFor(c, base, S);
    holdPose(c, 'audit.zero', zeroPoseDef(c));
    const before = {}, piv0 = {};
    for (const [k, [bn, pt]] of Object.entries(marks)) { before[k] = wpos(c, bn, pt); piv0[k] = pivotOf(bn); }
    for (const ax of ['X', 'Y', 'Z']) {
      const e = exp[ax];
      if (!e) continue;
      const r = [0, 0, 0]; r['XYZ'.indexOf(ax)] = 30;
      if (name === 'hips') holdPose(c, 'audit.ax', { ...zeroPoseDef(c), hips: { pos: [0, 0, 0], rot: r } });
      else holdPose(c, 'audit.ax', zeroPoseDef(c, { [name]: r }));
      const [mk_, ev, label] = e;
      const [bn, pt] = marks[mk_] || marks.tip;
      const after = wpos(c, bn, pt);
      const disp = after.clone().sub(before[mk_] || before.tip);
      // direction change of the marker seen from its bone pivot (pure rotation, pivot-independent)
      const d0 = (before[mk_] || before.tip).clone().sub(piv0[mk_] || piv0.tip).normalize();
      const d1 = after.clone().sub(pivotOf(bn)).normalize();
      const dd = d1.clone().sub(d0);
      const n = dd.length() > 1e-6 ? dd.clone().normalize() : V();
      let expV = ev ? new THREE.Vector3(ev[0], ev[1], S === 'L' ? -ev[2] : ev[2]) : null;
      const dot = expV ? n.dot(expV) : null;
      const row = { bone: name, axis: '+' + ax, claim: label, marker: mk_, dispMM: [mm(disp.x), mm(disp.y), mm(disp.z)], dirChange: [r1(n.x, 3), r1(n.y, 3), r1(n.z, 3)], expected: expV && [expV.x, expV.y, expV.z], dot: dot === null ? null : r1(dot, 3) };
      if (dot !== null && dot < 0.85) bad.push(row);
      if (dot === null && disp.length() < 1e-4) row.note = 'NO EFFECT (keyed value ignored)';
      rows.push(row);
    }
  }
  c.root.position.y = 0;
  return { design: id, tested: rows.length, mismatches: bad, ignored: rows.filter((r) => r.note), noClaim: rows.filter((r) => r.dot === null), rows };
}

// worked examples of README section 4 (zero pose + listed values)
function testExamples() {
  const c = mk('kael');
  resetChar(c); c.breath.depth = 0;
  const z = zeroPoseDef(c);
  const out = {};
  const run = (name, def) => { holdPose(c, 'audit.ex', def); return def; };
  run('relaxed', { ...z, bones: { ...z.bones, upperArmR: [-14, 6, 4], upperArmL: [-14, 6, 4], foreArmR: [0, 0, 16], foreArmL: [0, 0, 16] } });
  out.relaxed = { fistR: lpos(c, 'weaponR').toArray().map(mm), fistL: lpos(c, 'weaponL').toArray().map(mm) };
  run('armForward', { ...z, bones: { ...z.bones, upperArmR: [0, 0, 90] } });
  out.armForward = { fistR: lpos(c, 'weaponR').toArray().map(mm), shoulderR: lpos(c, 'upperArmR').toArray().map(mm) };
  run('tpose', { ...z, bones: { ...z.bones, upperArmR: [-90, 0, 0], upperArmL: [-90, 0, 0] } });
  out.tpose = { fistR: lpos(c, 'weaponR').toArray().map(mm), fistL: lpos(c, 'weaponL').toArray().map(mm) };
  run('chin', { ...z, bones: { ...z.bones, upperArmR: [0, 0, 40], foreArmR: [0, 0, 130] } });
  const chin = lpos(c, 'head', [0.1, -0.06, 0]);
  out.fistAtChin = { fistR: lpos(c, 'weaponR').toArray().map(mm), chinApprox: chin.toArray().map(mm), distMM: mm(lpos(c, 'weaponR').distanceTo(chin)) };
  run('wound', { ...z, hips: { pos: [0, 0, 0], rot: [0, -30, 0] }, bones: { ...z.bones, spine: [0, -10, -8], chest: [0, -10, -6], neck: [0, 18, 4], head: [0, 26, 0] } });
  const chestFwd = wpos(c, 'chest', [1, 0, 0]).sub(wpos(c, 'chest'));
  const headFwd = wpos(c, 'head', [1, 0, 0]).sub(wpos(c, 'head'));
  out.wound = { chestForward: chestFwd.toArray().map((x) => r1(x, 3)), headForward: headFwd.toArray().map((x) => r1(x, 3)) };
  run('highKnee', { ...z, bones: { ...z.bones, thighL: [0, 0, 90], shinL: [0, 0, -90], footL: [0, 0, -20] } });
  out.highKnee = { kneeL: lpos(c, 'shinL').toArray().map(mm), ankleL: lpos(c, 'footL').toArray().map(mm), hipL: lpos(c, 'thighL').toArray().map(mm) };
  run('ikHand', { ...z, ik: { handR: { pos: [0.3, 1.0, 0.18], aim: [0.77, 0.64, 0], up: [-0.64, 0.77, 0] } } });
  const bx = wpos(c, 'weaponR', [1, 0, 0]).sub(wpos(c, 'weaponR')), edge = wpos(c, 'weaponR', [0, -1, 0]).sub(wpos(c, 'weaponR'));
  out.ikHand = { fistR: lpos(c, 'weaponR').toArray().map(mm), bladeDir: bx.toArray().map((x) => r1(x, 3)), trueEdgeDir: edge.toArray().map((x) => r1(x, 3)), bladeElevDeg: deg(Math.asin(bx.y)) };
  // IK rot convention on the left foot (not mirrored) vs FK footL (mirrored)
  run('ikRotFootL', { ...z, ik: { footL: { pos: [0.2, 0.1, -0.12], rot: [0, 20, 0] } } });
  const toeIK = wpos(c, 'toeL').sub(wpos(c, 'footL'));
  run('fkFootL', { ...z, bones: { ...z.bones, footL: [0, 20, 0] } });
  const toeFK = wpos(c, 'toeL').sub(wpos(c, 'footL'));
  out.footL_yaw20 = { ikRot_toeDir: toeIK.toArray().map((x) => r1(x, 3)), fk_toeDir: toeFK.toArray().map((x) => r1(x, 3)), note: 'same number +20 on Y: IK rot turns the left toes OUT (-s), FK footL turns them IN (+s)' };
  // socket vs IK sole point
  out.footSocketVsIKSole = { socketLocal: c.sockets.footR.position.toArray(), ikSolePoint: [0, -c.rig.P.ankleHeight, 0] };
  return out;
}

// ---- 2. mirroring -------------------------------------------------------------------------------------------------
const ASYM = {
  hips: { pos: [0.03, -0.08, 0.02], rot: [5, -25, 4] },
  bones: { spine: [3, -10, -6], chest: [2, -12, 5], neck: [1, 8, 3], head: [4, 12, -5], shoulderR: [-5, 8, 0], shoulderL: [4, -6, 0],
    upperArmR: [-40, 20, 35], upperArmL: [-10, -15, 60], foreArmR: [0, 30, 70], foreArmL: [0, -20, 45], handR: [10, 20, -15], handL: [-5, 10, 25],
    thighR: [-8, 10, 30], shinR: [0, 0, -40], footR: [5, -10, 10], thighL: [-12, -5, -10], shinL: [0, 0, -20], footL: [0, 8, -5] },
  ik: { footL: { pos: [0.3, 0, -0.16], rot: [0, 18, 0] }, handR: { pos: [0.35, 1.2, 0.05], aim: [0.6, 0.7, -0.3], up: [-0.6, 0.6, 0.2] } },
  grip: 0, curl: [0.3, 0.8],
};
function mirrorName(n) {
  const m = /^(.*)_(\d+)_(\d+)$/.exec(n);
  if (m) return n; // cloth handled separately
  return n.endsWith('R') ? n.slice(0, -1) + 'L' : n.endsWith('L') ? n.slice(0, -1) + 'R' : n;
}
function compareMirror(a, b, names, mapName = mirrorName) {
  let worst = 0, worstBone = '', worstQ = 0, worstQBone = '';
  const M = new THREE.Matrix4().makeScale(1, 1, -1);
  for (const n of names) {
    const pa = lpos(a, n), pb = lpos(b, mapName(n));
    const e = pb.distanceTo(new THREE.Vector3(pa.x, pa.y, -pa.z));
    if (e > worst) { worst = e; worstBone = n; }
    // orientation: Rb should equal M Ra M
    const ra = new THREE.Matrix4().extractRotation(new THREE.Matrix4().copy(a.root.matrixWorld).invert().multiply(a.bones[n].matrixWorld));
    const rb = new THREE.Matrix4().extractRotation(new THREE.Matrix4().copy(b.root.matrixWorld).invert().multiply(b.bones[mapName(n)].matrixWorld));
    const mra = new THREE.Matrix4().multiplyMatrices(M, ra).multiply(M);
    const qa = new THREE.Quaternion().setFromRotationMatrix(mra), qb = new THREE.Quaternion().setFromRotationMatrix(rb);
    const ang = qAngle(qa, qb);
    if (ang > worstQ) { worstQ = ang; worstQBone = n; }
  }
  return { worstPosMM: mm(worst), worstPosBone: worstBone, worstRotDeg: deg(worstQ), worstRotBone: worstQBone };
}
/** Two fresh instances with identical histories (breath phase / sim time are per-instance state). */
function twins(design = knight) {
  return [createCharacter(CTX, design, { parent: null, name: 'twinA' }), createCharacter(CTX, design, { parent: null, name: 'twinB' })];
}
function perBoneMirror(a, b, names) {
  const rows = [];
  for (const n of names) { const pa = lpos(a, n), pb = lpos(b, mirrorName(n)); rows.push([n, mm(pb.distanceTo(new THREE.Vector3(pa.x, pa.y, -pa.z)))]); }
  return rows.sort((x, y) => y[1] - x[1]).slice(0, 5);
}
function testMirrorReal() {
  const out = {};
  let [a, b] = twins();
  const bodyNames = animatedNames(a).filter((n) => !/^weapon/.test(n));
  const helperNames = a.rig.names.filter((n, i) => a.rig.helper[i]);
  // mirrorPose on an asymmetric FK + IK pose (no grip)
  definePose('audit.asym', ASYM);
  mirrorPose('audit.asym', 'audit.asymM');
  invalidateClips();
  for (const c of [a, b]) resetChar(c);
  a.play('audit.asym', { fade: 0, restart: true }); b.play('audit.asymM', { fade: 0, restart: true });
  for (let i = 0; i < 20; i++) { step(a); step(b); }
  out.mirrorPose = { bones: compareMirror(a, b, bodyNames), helpers: compareMirror(a, b, helperNames), top: perBoneMirror(a, b, bodyNames) };
  a.dispose(); b.dispose(); [a, b] = twins();
  // mirrorClip 'swap' on a moving asymmetric clip without a weapon grip: root motion, origin feet, hips/chest hands, look
  defineClip('audit.mclip', {
    duration: 1.2,
    keys: [
      { t: 0, pose: 'audit.asym', root: { pos: [0, 0] }, look: { at: [2, 1.6, 0.6] } },
      { t: 0.3, hips: { pos: [0.05, -0.12, 0.03], rot: [3, 40, -5] }, bones: { spine: [4, 12, -8], upperArmL: [-30, 10, 80] },
        ik: { footR: { space: 'origin', pos: [-0.25, 0.08, 0.2], rot: [0, -30, 8] }, handR: { space: 'chest', pos: [0.3, -0.1, 0.25], aim: [0.2, 0.9, 0.3], up: [-0.9, 0.2, 0.3] } } },
      { t: 0.7, hips: { rot: [-4, 160, 6] }, ik: { footR: { space: 'origin', pos: [0.1, 0, 0.22], rot: [0, -20, 0] }, handR: { space: 'chest', pos: [0.4, 0.05, 0.1], aim: [0.9, 0.1, -0.4], up: [0, 1, 0] } }, look: { at: [1, 1.2, -0.8] } },
      { t: 1.2, pose: 'audit.asym', root: { pos: [0.4, 0] } },
    ],
  });
  mirrorClip('audit.mclip', 'audit.mclipM', { hands: 'swap' });
  invalidateClips();
  for (const c of [a, b]) resetChar(c);
  a.play('audit.mclip', { fade: 0, restart: true }); b.play('audit.mclipM', { fade: 0, restart: true });
  let w = { worstPosMM: 0 }, wq = 0;
  for (let i = 0; i < 72; i++) {
    step(a); step(b);
    const r = compareMirror(a, b, bodyNames);
    if (r.worstPosMM > w.worstPosMM) w = { ...r, frame: i + 1 };
    wq = Math.max(wq, r.worstRotDeg);
  }
  out.mirrorClipSwap = { ...w, worstRotDegAll: wq, rootA: a.root.position.x, rootB: b.root.position.x, topAtEnd: perBoneMirror(a, b, bodyNames) };
  a.dispose(); b.dispose(); [a, b] = twins();
  // demo.combo1 vs demo.combo1M (hands 'keep'): legs/torso, weapon base/tip and both fists should be exact mirrors
  for (const c of [a, b]) resetChar(c, 'demo.stance');
  a.play('demo.combo1', { fade: 0, restart: true }); b.play('demo.combo1M', { fade: 0, restart: true });
  const legTorso = bodyNames.filter((n) => /^(hips|spine|chest|neck|head|thigh|shin|foot|toe)/.test(n));
  let wk = { worstPosMM: 0 }, tipW = 0, fistW = 0, fistLW = 0, frames = [];
  for (let i = 0; i < 57; i++) {
    step(a); step(b);
    const r = compareMirror(a, b, legTorso);
    if (r.worstPosMM > wk.worstPosMM) wk = { ...r, frame: i + 1 };
    const ta = lpos(a, 'weaponR', [1.47, 0, 0]), tb = lpos(b, 'weaponR', [1.47, 0, 0]);
    const e = tb.distanceTo(new THREE.Vector3(ta.x, ta.y, -ta.z));
    const fa = lpos(a, 'weaponR'), fb = lpos(b, 'weaponR');
    const ef = fb.distanceTo(new THREE.Vector3(fa.x, fa.y, -fa.z));
    const la = lpos(a, 'weaponL'), lb = lpos(b, 'weaponL');
    const el = lb.distanceTo(new THREE.Vector3(la.x, la.y, -la.z));
    if (i % 6 === 0) frames.push({ f: i + 1, tipErrMM: mm(e), fistRErrMM: mm(ef) });
    tipW = Math.max(tipW, e); fistW = Math.max(fistW, ef); fistLW = Math.max(fistLW, el);
  }
  out.combo1M_keep = { legsTorso: wk, weaponTipMaxErrMM: mm(tipW), fistRMaxErrMM: mm(fistW), fistLMaxErrMM: mm(fistLW), samples: frames };
  a.dispose(); b.dispose(); [a, b] = twins();
  // pole mirroring in 'keep' mode: a right-arm pole out to the right becomes a pole on the LEFT of the body
  defineClip('audit.pole', { duration: 0.5, keys: [{ t: 0, pose: 'demo.stance', ik: { handR: { pos: [0.35, 1.25, 0.25], aim: [1, 0.2, 0], up: [0, 1, 0], pole: [-0.2, 1.1, 0.9] } }, grip: 0 }] });
  mirrorClip('audit.pole', 'audit.poleK', { hands: 'keep' });
  invalidateClips();
  for (const c of [a, b]) resetChar(c);
  a.play('audit.pole', { fade: 0, restart: true }); b.play('audit.poleK', { fade: 0, restart: true });
  for (let i = 0; i < 4; i++) { step(a); step(b); }
  const elbowSide = (c) => { const s = lpos(c, 'upperArmR'), e = lpos(c, 'foreArmR'), h = lpos(c, 'handR'); const mid = s.clone().add(h).multiplyScalar(0.5); return e.clone().sub(mid).toArray().map(mm); };
  out.poleKeep = { srcPole: [-0.2, 1.1, 0.9], keptHandPole: [-0.2, 1.1, -0.9], srcElbowOffsetFromLimbMidMM: elbowSide(a), keepElbowOffsetFromLimbMidMM: elbowSide(b), srcHandTargetS: 0.25, keepHandTargetS: -0.25 };
  a.dispose(); b.dispose();
  return out;
}

function testFacing() {
  const out = {};
  let a, b, all;
  for (const clip of ['demo.combo3', 'demo.walkF']) {
    [a, b] = twins(); all = a.rig.names;
    for (const c of [a, b]) resetChar(c);
    b.setFacing(-1); a.teleport(); b.teleport();
    a.play(clip, { fade: 0, restart: true }); b.play(clip, { fade: 0, restart: true });
    let worst = 0, wb = '';
    for (let i = 0; i < 80; i++) {
      step(a); step(b);
      for (const n of all) {
        const pa = wpos(a, n), pb = wpos(b, n);
        const e = Math.hypot(pb.x + pa.x, pb.y - pa.y, pb.z - pa.z);
        if (e > worst) { worst = e; wb = n; }
      }
    }
    out[clip] = { worstWorldMirrorErrMM: mm(worst), bone: wb, rootA: r1(a.root.position.x, 4), rootB: r1(b.root.position.x, 4) };
    a.dispose(); b.dispose();
  }
  a = mk('kael');
  // timed turn: does the side swap still happen instantly?
  resetChar(a);
  for (let i = 0; i < 10; i++) step(a);
  const before = { handR: wpos(a, 'weaponR').toArray().map(mm), tip: wpos(a, 'weaponR', [1.47, 0, 0]).toArray().map(mm) };
  a.setFacing(-1, { turn: 0.3 });
  a.root.updateMatrixWorld(true);
  const atFlip = { handR: wpos(a, 'weaponR').toArray().map(mm), tip: wpos(a, 'weaponR', [1.47, 0, 0]).toArray().map(mm) };
  step(a);
  const next = { handR: wpos(a, 'weaponR').toArray().map(mm), tip: wpos(a, 'weaponR', [1.47, 0, 0]).toArray().map(mm) };
  for (let i = 0; i < 25; i++) step(a);
  const after = { handR: wpos(a, 'weaponR').toArray().map(mm), tip: wpos(a, 'weaponR', [1.47, 0, 0]).toArray().map(mm), rotY: a.root.rotation.y };
  out.timedTurn = { before, firstFrameAfterSetFacing: next, rightAfterCall: atFlip, end: after, note: 'z of the sword hand: + = camera side' };
  a.setFacing(1); a.root.rotation.set(0, 0, 0);
  return out;
}

// ---- 3. IK ---------------------------------------------------------------------------------------------------------
function rigSetup(P) {
  const rig = createRig(P);
  const limbs = makeLimbs(rig);
  const lq = new Float32Array(rig.restRot), lp = new Float32Array(rig.offset), mq = new Float32Array(rig.count * 4), mp = new Float32Array(rig.count * 3);
  const neutral = getClip(rig, 'neutral.hold');
  const pose = new Pose(rig);
  sampleClip(rig, neutral, 0, pose);
  const reset = (useNeutral = true) => { lq.set(useNeutral ? pose.lq : rig.restRot); lp.set(rig.offset); fk(rig, lq, lp, mq, mp); };
  reset();
  const v3 = (i) => new THREE.Vector3(mp[i * 3], mp[i * 3 + 1], mp[i * 3 + 2]);
  const q4 = (i) => new THREE.Quaternion(mq[i * 4], mq[i * 4 + 1], mq[i * 4 + 2], mq[i * 4 + 3]);
  const eff = (limb) => v3(limb.end).add(new THREE.Vector3(...limb.endOff).applyQuaternion(q4(limb.end)));
  return { rig, limbs, lq, lp, mq, mp, reset, v3, q4, eff };
}
function randQuat(rng) {
  const u1 = rng(), u2 = rng() * Math.PI * 2, u3 = rng() * Math.PI * 2;
  const a = Math.sqrt(1 - u1), b = Math.sqrt(u1);
  return new THREE.Quaternion(a * Math.sin(u2), a * Math.cos(u2), b * Math.sin(u3), b * Math.cos(u3));
}
function randDir(rng) {
  const z = rng() * 2 - 1, t = rng() * Math.PI * 2, r = Math.sqrt(1 - z * z);
  return new THREE.Vector3(r * Math.cos(t), z, r * Math.sin(t));
}
function testIkPure(id = 'kael', n = 500) {
  const S = rigSetup(PROPS[id]);
  const rng = makeRng(1234 + id.length);
  const res = {};
  for (const [name, limb] of Object.entries(S.limbs)) {
    const lmax = limb.l1 + limb.l2, lmin = Math.abs(limb.l1 - limb.l2);
    const hard = [], soft = [], ang = [], free = [];
    let nan = 0;
    for (let i = 0; i < n; i++) {
      const dir = randDir(rng), q = randQuat(rng);
      const zone = i % 5 === 4 ? 'soft' : 'hard';
      const r = zone === 'soft' ? lmax * (0.96 + 0.04 * rng()) : lmin + 0.03 + (lmax * 0.96 - lmin - 0.03) * rng();
      S.reset();
      const root = S.v3(limb.root);
      const wrist = root.clone().addScaledVector(dir, r);
      const tgt = wrist.clone().add(new THREE.Vector3(...limb.endOff).applyQuaternion(q));
      solveLimb(S.rig, limb, S.lq, S.mq, S.mp, tgt.toArray(), 0, [q.x, q.y, q.z, q.w], 0, null, 0, 1);
      fk(S.rig, S.lq, S.lp, S.mq, S.mp);
      const e = S.eff(limb).distanceTo(tgt);
      if (!Number.isFinite(e)) { nan++; continue; }
      (zone === 'soft' ? soft : hard).push(e);
      ang.push(qAngle(S.q4(limb.end), q));
      // orientation-free variant (end keeps its FK orientation)
      S.reset();
      const q0 = S.q4(limb.end);
      const tgt2 = wrist.clone().add(new THREE.Vector3(...limb.endOff).applyQuaternion(q0));
      solveLimb(S.rig, limb, S.lq, S.mq, S.mp, tgt2.toArray(), 0, null, 0, null, 0, 1);
      fk(S.rig, S.lq, S.lp, S.mq, S.mp);
      if (zone === 'hard') free.push(S.eff(limb).distanceTo(tgt2));
    }
    res[name] = { lmax: r1(lmax, 4), within96: statsMM(hard), softZone96to100: statsMM(soft), keepOrientation: statsMM(free), rotErrDegMax: deg(Math.max(...ang)), nan };
  }
  return { design: id, perLimb: res };
}
/** Reach sweep along a fixed direction: achieved distance, error, elbow angle continuity. */
function testIkSweep(id = 'kael') {
  const S = rigSetup(PROPS[id]);
  const out = {};
  for (const name of ['handR', 'footR']) {
    const limb = S.limbs[name];
    const lmax = limb.l1 + limb.l2;
    const dir = name === 'handR' ? new THREE.Vector3(0.7, -0.2, 0.68).normalize() : new THREE.Vector3(0.5, -0.86, 0.1).normalize();
    const rows = [];
    let maxStepJump = 0, prevEff = null, prevBend = null, maxBendJump = 0, nonMono = 0, prevD = 0;
    for (let k = 0; k <= 400; k++) {
      const ratio = 0.9 + k * 0.001;
      S.reset();
      const q = S.q4(limb.end);
      const root = S.v3(limb.root);
      const wrist = root.clone().addScaledVector(dir, lmax * ratio);
      const tgt = wrist.clone().add(new THREE.Vector3(...limb.endOff).applyQuaternion(q));
      solveLimb(S.rig, limb, S.lq, S.mq, S.mp, tgt.toArray(), 0, [q.x, q.y, q.z, q.w], 0, null, 0, 1);
      fk(S.rig, S.lq, S.lp, S.mq, S.mp);
      const e = S.eff(limb);
      const wr = S.v3(limb.end);
      const d = wr.distanceTo(root);
      const a = S.v3(limb.mid).sub(root).normalize(), b = wr.clone().sub(S.v3(limb.mid)).normalize();
      const bend = Math.acos(Math.max(-1, Math.min(1, a.dot(b))));
      if (prevEff) { maxStepJump = Math.max(maxStepJump, e.distanceTo(prevEff)); maxBendJump = Math.max(maxBendJump, Math.abs(bend - prevBend)); if (d < prevD - 1e-7) nonMono++; }
      prevEff = e; prevBend = bend; prevD = d;
      if ([0, 50, 60, 65, 70, 75, 80, 90, 100, 110, 150, 200, 300, 400].includes(k)) rows.push({ reach: r1(ratio, 3), errMM: mm(e.distanceTo(tgt)), achieved: r1(d / lmax, 4), bendDeg: deg(bend) });
    }
    out[name] = { lmax: r1(lmax, 4), stepMM: mm(lmax * 0.001), maxEffectorStepMM: mm(maxStepJump), maxBendStepDeg: deg(maxBendJump), nonMonotonicSteps: nonMono, rows };
  }
  return { design: id, ...out };
}
/** Pole stability: sweep targets on circles around the limb root, look for elbow / knee pops between 0.5 deg steps. */
function testIkPole(id = 'kael') {
  const S = rigSetup(PROPS[id]);
  const out = {};
  const sweep = (limb, centre, ring, frac, rotMode) => {
    const lmax = limb.l1 + limb.l2, r = lmax * frac;
    let prevMid = null, prevT = null, pops = [], maxRatio = 0;
    for (let k = 0; k <= 720; k++) {
      const a = (k / 720) * Math.PI * 2;
      const d = ring(a);
      S.reset();
      const q = rotMode === 'fk' ? S.q4(limb.end) : new THREE.Quaternion();
      const wrist = centre.clone().addScaledVector(d, r);
      const tgt = wrist.clone().add(new THREE.Vector3(...limb.endOff).applyQuaternion(q));
      solveLimb(S.rig, limb, S.lq, S.mq, S.mp, tgt.toArray(), 0, [q.x, q.y, q.z, q.w], 0, null, 0, 1);
      fk(S.rig, S.lq, S.lp, S.mq, S.mp);
      const mid = S.v3(limb.mid);
      if (prevMid) {
        const jm = mid.distanceTo(prevMid), jt = wrist.distanceTo(prevT);
        maxRatio = Math.max(maxRatio, jm / jt);
        if (jm > 0.03) pops.push({ deg: r1((k / 720) * 360, 1), jumpMM: mm(jm), targetStepMM: mm(jt), dir: d.toArray().map((x) => r1(x, 2)) });
      }
      prevMid = mid; prevT = wrist;
    }
    return { pops: pops.length, maxMidToTargetSpeedRatio: r1(maxRatio, 1), first: pops.slice(0, 6) };
  };
  for (const [name, limb] of Object.entries({ handR: S.limbs.handR, footR: S.limbs.footR })) {
    const centre = S.v3(limb.root);
    const res = {};
    const H = (h) => (a) => new THREE.Vector3(Math.cos(a) * Math.sqrt(1 - h * h), h, Math.sin(a) * Math.sqrt(1 - h * h));
    for (const h of [-0.9, -0.6, -0.3, 0, 0.3, 0.6, 0.9]) res['horiz_h' + h] = sweep(limb, centre, H(h), 0.8, name === 'handR' ? 'fk' : 'id');
    res.sagittal = sweep(limb, centre, (a) => new THREE.Vector3(Math.cos(a), Math.sin(a), 0), 0.8, name === 'handR' ? 'fk' : 'id');
    res.frontal = sweep(limb, centre, (a) => new THREE.Vector3(0, Math.sin(a), Math.cos(a)), 0.8, name === 'handR' ? 'fk' : 'id');
    res.sagittalNear = sweep(limb, centre, (a) => new THREE.Vector3(Math.cos(a), Math.sin(a), 0), 0.45, name === 'handR' ? 'fk' : 'id');
    out[name] = res;
  }
  return { design: id, ...out };
}

/** Pipeline IK accuracy: 500 random targets per limb played through a clip (character update), floor contact off. */
function testIkPipeline(id = 'kael', n = 500, bentLegs = false) {
  const c = mk(id);
  resetChar(c);
  const P = c.rig.P, L = c.rig.lengths, rng = makeRng(77 + id.length);
  const res = {};
  for (const e of ['handR', 'handL', 'footR', 'footL']) {
    const arm = e.startsWith('hand');
    const keys = [];
    const tg = [];
    const z = e.endsWith('R') ? 1 : -1;
    // limb root in the neutral pose (root space)
    const rootPt = arm ? [-P.shoulderBack, (hipsPivot(P)) + P.spine + P.chest + P.shoulderHeight, z * (P.clavicleRoot + P.clavicle)] : [0, P.hipHeight, z * P.hipWidth];
    const lmax = arm ? L.upperArm + L.foreArm : L.thigh + L.shin;
    for (let i = 0; i < n; i++) {
      let p;
      for (let tries = 0; tries < 50; tries++) {
        const d = randDir(rng), r = lmax * (0.35 + 0.55 * rng());
        p = [rootPt[0] + d.x * r, rootPt[1] + d.y * r, rootPt[2] + d.z * r];
        if (arm || p[1] < P.hipHeight - 0.15) break;
      }
      const q = randQuat(rng);
      const ax = new THREE.Vector3(1, 0, 0).applyQuaternion(q), up = new THREE.Vector3(0, 1, 0).applyQuaternion(q);
      // effector = wrist + rot*endOff; we key the effector, so shift by endOff
      const off = arm ? [0, -P.hand, -z * P.palm] : [0, -P.ankleHeight, 0];
      const eo = new THREE.Vector3(...off).applyQuaternion(q);
      const pos = [p[0] + eo.x, p[1] + eo.y, p[2] + eo.z];
      keys.push({ t: i * 0.1, interp: 'step', ik: { [e]: { pos, aim: ax.toArray(), up: up.toArray() } } });
      tg.push({ pos, q });
    }
    const base = bentLegs ? { t: 0, pose: 'neutral', grip: 0, bones: { thighR: [0, 0, 25], shinR: [0, 0, -50], thighL: [0, 0, 25], shinL: [0, 0, -50] } } : { t: 0, pose: 'neutral', grip: 0 };
    defineClip('audit.ikp', { duration: n * 0.1, keys: [base, ...keys] });
    invalidateClips();
    c.root.position.set(0, 3, 0); // floor far below: no contact / re-plant
    c.breath.depth = 0;
    c.play('audit.ikp', { fade: 0, restart: true });
    const errs = [], angs = [];
    for (let i = 0; i < n; i++) {
      c.setClipTime(i * 0.1 + 0.05);
      step(c, 1 / 60, false);
      const effW = arm ? wpos(c, 'weapon' + e.slice(-1)) : wpos(c, 'foot' + e.slice(-1), [0, -P.ankleHeight, 0]);
      const tW = new THREE.Vector3(...tg[i].pos).applyMatrix4(c.root.matrixWorld);
      errs.push(effW.distanceTo(tW));
      angs.push(qAngle(wquat(c, (arm ? 'hand' : 'foot') + e.slice(-1)), tg[i].q));
    }
    res[e] = { err: statsMM(errs), rotErrDeg: { mean: deg(stats(angs).mean), max: deg(stats(angs).max) } };
  }
  c.root.position.set(0, 0, 0); c.breath.depth = 1;
  return { design: id, perLimb: res, nan: anyNaN(c) };
}

/** IK target spaces during root motion / hips spin / chest spin / root rotation. */
function testSpaces() {
  const c = mk('kael');
  const out = {};
  // origin-space planted foot during 0.3 m of root motion (stays reachable), hips / chest-space hands during a 360 deg hips spin
  defineClip('audit.origin', {
    duration: 1.0,
    keys: [
      { t: 0, pose: 'demo.stance', root: { pos: [0, 0] }, ik: { footL: { space: 'origin', pos: [0.3, 0, -0.14], rot: [0, 14, 0] } } },
      { t: 1.0, interp: 'linear', root: { pos: [0.3, 0] }, hips: { pos: [0.12, -0.11, 0] }, ik: { footR: { pos: [0.05, 0, 0.17], rot: [0, -45, 0] } } },
    ],
  });
  defineClip('audit.spaces', {
    duration: 1.0,
    keys: [
      { t: 0, pose: 'neutral', grip: 0, hips: { pos: [0, -0.1, 0], rot: [0, 0, 0] }, bones: { thighR: [0, 0, 30], shinR: [0, 0, -60], thighL: [0, 0, 30], shinL: [0, 0, -60] },
        ik: { handR: { space: 'hips', pos: [0.35, 0.2, 0.3], aim: [1, 0, 0], up: [0, 1, 0] }, handL: { space: 'chest', pos: [0.3, 0.05, -0.32], aim: [1, 0.2, 0], up: [0, 1, 0] } } },
      { t: 0.5, hips: { rot: [0, 180, 0], interp: 'linear' }, bones: { spine: [0, 20, 0], chest: [10, 30, -10] } },
      { t: 1.0, hips: { rot: [0, 360, 0], interp: 'linear' }, bones: { spine: [0, 0, 0], chest: [0, 0, 0] } },
    ],
  });
  invalidateClips();
  for (const dt of [1 / 60, 1 / 30]) {
    resetChar(c, 'demo.stance');
    c.play('audit.origin', { fade: 0, restart: true });
    let f0 = null, footDrift = 0;
    for (let i = 0; i < Math.round(1.0 / dt); i++) {
      step(c, dt, true);
      const f = wpos(c, 'footL', [0, -c.rig.P.ankleHeight, 0]);
      if (!f0) f0 = f.clone();
      footDrift = Math.max(footDrift, Math.hypot(f.x - f0.x, f.z - f0.z));
    }
    resetChar(c, 'neutral.hold'); c.root.position.y = 2;
    c.play('audit.spaces', { fade: 0, restart: true });
    let hipsErr = 0, chestErr = 0;
    for (let i = 0; i < Math.round(1.0 / dt); i++) {
      step(c, dt, false);
      hipsErr = Math.max(hipsErr, wpos(c, 'weaponR').distanceTo(wpos(c, 'hips', [0.35, 0.2, 0.3])));
      chestErr = Math.max(chestErr, wpos(c, 'weaponL').distanceTo(wpos(c, 'chest', [0.3, 0.05, -0.32])));
    }
    out['dt' + Math.round(1 / dt)] = { originFootDriftMM: mm(footDrift), hipsSpaceHandErrMM: mm(hipsErr), chestSpaceHandErrMM: mm(chestErr) };
  }
  // without breathing: is the chest-space error from the additive pass?
  resetChar(c, 'neutral.hold'); c.breath.depth = 0; c.root.position.y = 2;
  c.play('audit.spaces', { fade: 0, restart: true });
  let chestErr0 = 0, hipsErr0 = 0;
  for (let i = 0; i < 60; i++) { step(c, 1 / 60, false); chestErr0 = Math.max(chestErr0, wpos(c, 'weaponL').distanceTo(wpos(c, 'chest', [0.3, 0.05, -0.32]))); hipsErr0 = Math.max(hipsErr0, wpos(c, 'weaponR').distanceTo(wpos(c, 'hips', [0.35, 0.2, 0.3]))); }
  out.noBreath = { hipsSpaceHandErrMM: mm(hipsErr0), chestSpaceHandErrMM: mm(chestErr0) };
  c.root.position.y = 0;
  // root-space target while the ROOT is rotated (cinematic spin) and mirrored
  resetChar(c, 'demo.stance');
  let rootErr = 0;
  for (let i = 0; i < 60; i++) {
    c.root.rotation.y = (i / 60) * Math.PI * 2; c.root.position.z = 0.3 * Math.sin(i * 0.2);
    if (i === 30) c.setFacing(-1);
    step(c, 1 / 60, false);
    const t = new THREE.Vector3(0.33, 1.08, 0.1).applyMatrix4(c.root.matrixWorld);
    rootErr = Math.max(rootErr, wpos(c, 'weaponR').distanceTo(t));
  }
  out.rootSpaceUnderRootSpinAndFlip = { maxErrMM: mm(rootErr), note: 'demo.stance handR target [0.33,1.08,0.1] (breathing on)' };
  c.root.rotation.set(0, 0, 0); c.setFacing(1);
  // continuity of a root -> chest space handoff (combo3 handR: root key 0.09, chest key 0.17)
  resetChar(c, 'demo.c2end');
  c.play('demo.combo3', { fade: 0, restart: true });
  let prev = null, maxJump = 0, at = 0;
  for (let i = 0; i < 81; i++) { step(c); const p = wpos(c, 'weaponR'); if (prev) { const j = p.distanceTo(prev); if (j > maxJump) { maxJump = j; at = (i + 1) / 60; } } prev = p; }
  out.combo3HandPathMaxStepMM = { mm: mm(maxJump), t: r1(at, 3) };
  return out;
}

/** Foot authored in hips space -> spurious pelvis drop (target treated as the model origin). */
function testHipsFoot() {
  const c = mk('kael');
  const out = {};
  const run = (space) => {
    resetChar(c, 'neutral.hold'); c.breath.depth = 0;
    const footR = space === 'hips' ? { space: 'hips', pos: [0.25, -0.65, 0.12], rot: [0, 0, 0] } : null;
    defineClip('audit.hf', { duration: 1, loop: true, keys: [{ t: 0, pose: 'neutral', grip: 0, hips: { pos: [0, 0.05, 0] }, bones: { thighL: [0, 0, 40], shinL: [0, 0, -70], thighR: [0, 0, 20], shinR: [0, 0, -40] }, ik: footR ? { footR } : {} }] });
    invalidateClips();
    c.play('audit.hf', { fade: 0, restart: true });
    step(c, 1 / 60, false); step(c, 1 / 60, false);
    return { hipsY: lpos(c, 'hips').y, footR: lpos(c, 'footR', [0, -c.rig.P.ankleHeight, 0]), target: lpos(c, 'hips', [0.25, -0.65, 0.12]) };
  };
  const a = run('none'), b = run('hips');
  out.hipsYwithoutFootIK = mm(a.hipsY);
  out.hipsYwithHipsSpaceFoot = mm(b.hipsY);
  out.spuriousDropMM = mm(a.hipsY - b.hipsY);
  out.footErrMM = mm(b.footR.distanceTo(b.target));
  // same thing in chest space
  resetChar(c, 'neutral.hold'); c.breath.depth = 0;
  defineClip('audit.hf2', { duration: 1, loop: true, keys: [{ t: 0, pose: 'neutral', grip: 0, hips: { pos: [0, 0.05, 0] }, bones: { thighR: [0, 0, 40], shinR: [0, 0, -70] }, ik: { footL: { space: 'chest', pos: [0.3, -0.85, -0.12] } } }] });
  invalidateClips();
  c.play('audit.hf2', { fade: 0, restart: true }); step(c, 1 / 60, false); step(c, 1 / 60, false);
  out.chestSpaceFootL_hipsYMM = mm(lpos(c, 'hips').y);
  out.restHipsYMM = mm(c.rig.offset[1] + 0.05);
  return out;
}

/** Authored knee pole on a planted foot vs the re-plant pass (which uses the default pole). */
function testKneePole() {
  const c = mk('kael');
  const out = {};
  const pole = [0.2, 0.55, 0.9];
  defineClip('audit.kp', { duration: 1, loop: true, keys: [{ t: 0, pose: 'neutral', grip: 0, hips: { pos: [0, -0.18, 0] }, ik: { footR: { pos: [0.05, 0, 0.28], rot: [0, -40, 0], pole } } }] });
  invalidateClips();
  const kneeDir = () => {
    const h = lpos(c, 'thighR'), k = lpos(c, 'shinR'), a = lpos(c, 'footR');
    const ax = a.clone().sub(h).normalize();
    const kv = k.clone().sub(h); kv.addScaledVector(ax, -kv.dot(ax)).normalize();
    const pv = new THREE.Vector3(...pole).sub(h); pv.addScaledVector(ax, -pv.dot(ax)).normalize();
    return { kneeDir: kv.toArray().map((x) => r1(x, 3)), angleToPoleDeg: deg(Math.acos(Math.max(-1, Math.min(1, kv.dot(pv))))) };
  };
  resetChar(c, 'neutral.hold'); c.breath.depth = 0;
  c.root.position.y = 3; // re-plant weight 0 (foot 3 m above the floor)
  c.play('audit.kp', { fade: 0, restart: true }); step(c, 1 / 60, false); step(c, 1 / 60, false);
  out.airborne = kneeDir();
  c.root.position.y = 0;
  c.play('audit.kp', { fade: 0, restart: true }); step(c, 1 / 60, false); step(c, 1 / 60, false);
  out.onFloor = kneeDir();
  out.pole = pole;
  return out;
}

/** Pelvis drop: sweep the right foot backward (horizontal distance from the hip joint grows past the leg length). */
function testDropSweep() {
  const c = mk('kael');
  const rows = [];
  resetChar(c, 'neutral.hold'); c.breath.depth = 0;
  const keys = [];
  for (let i = 0; i <= 80; i++) keys.push({ t: i * 0.1, interp: 'step', ik: { footR: { pos: [-0.2 - i * 0.01, 0, 0.16], rot: [0, -30, 0] }, footL: { pos: [0.2, 0, -0.14], rot: [0, 10, 0] } } });
  defineClip('audit.drop', { duration: 8.1, keys: [{ t: 0, pose: 'neutral', grip: 0 }, ...keys] });
  invalidateClips();
  c.play('audit.drop', { fade: 0, restart: true });
  let prevY = null, maxJump = 0, jumpAt = null;
  for (let i = 0; i <= 80; i++) {
    c.setClipTime(i * 0.1 + 0.05);
    step(c, 1 / 60, false);
    const hy = lpos(c, 'hips').y;
    const f = lpos(c, 'footR', [0, -c.rig.P.ankleHeight, 0]);
    const hip = lpos(c, 'thighR');
    const hz = Math.hypot(-0.2 - i * 0.01 - hip.x, 0.16 - hip.z);
    const err = f.distanceTo(new THREE.Vector3(-0.2 - i * 0.01, 0, 0.16));
    if (prevY !== null && Math.abs(hy - prevY) > maxJump) { maxJump = Math.abs(hy - prevY); jumpAt = { footF: r1(-0.2 - i * 0.01, 3), hz: r1(hz, 3) }; }
    prevY = hy;
    if (i % 5 === 0 || (hz > 0.83 && hz < 0.9)) rows.push({ footF: r1(-0.2 - i * 0.01, 3), hipFootHorizM: r1(hz, 3), hipsY: mm(hy), footErrMM: mm(err), soleY: mm(f.y) });
  }
  return { legLen: r1(c.rig.lengths.thigh + c.rig.lengths.shin, 4), dropLimit97: r1((c.rig.lengths.thigh + c.rig.lengths.shin) * 0.97, 4), maxHipsStepMM: mm(maxJump), at: jumpAt, rows };
}

/** Heel / toe: pitched foot targets on the floor. */
function testToeRoll() {
  const c = mk('kael');
  const P = c.rig.P;
  const out = [];
  for (const pitch of [-45, -30, -15, 0, 15, 30]) {
    resetChar(c, 'neutral.hold'); c.breath.depth = 0;
    defineClip('audit.toe', { duration: 1, loop: true, keys: [{ t: 0, pose: 'neutral', grip: 0, hips: { pos: [0, -0.06, 0] }, ik: { footR: { pos: [0.1, 0, 0.12], rot: [0, 0, pitch] } } }] });
    invalidateClips();
    c.play('audit.toe', { fade: 0, restart: true }); step(c, 1 / 60, false); step(c, 1 / 60, false);
    const sole = lpos(c, 'footR', [0, -P.ankleHeight, 0]), heel = lpos(c, 'footR', [-P.heelLength, -P.ankleHeight, 0]);
    const ball = lpos(c, 'toeR', [0, -(P.ankleHeight - P.footDrop), 0]), tip = lpos(c, 'toeR', [P.toeLength, -(P.ankleHeight - P.footDrop), 0]);
    const toeBend = twistSwing(c.bones.toeR.quaternion).swing;
    out.push({ pitchDeg: pitch, soleTargetY: 0, soleY: mm(sole.y), heelY: mm(heel.y), ballY: mm(ball.y), toeTipY: mm(tip.y), soleFwdErrMM: mm(sole.x - 0.1), toeBendDeg: r1(toeBend, 1) });
  }
  return out;
}

// ---- 4. grip -------------------------------------------------------------------------------------------------------
function gripErr(c) {
  const clip = getClip(c.rig, c.clip);
  const g = c.weapon.grips[clip.gripAt] || c.weapon.grips.grip;
  const gp = wpos(c, 'weaponR', Array.from(g.pos));
  const fist = wpos(c, 'weaponL');
  const qw = wquat(c, 'weaponR'), qh = wquat(c, 'handL');
  return { d: fist.distanceTo(gp), a: qAngle(qw, qh) };
}
function testGrip(id = 'kael', clips = DEMO, scale = 1) {
  const c = mk(id);
  const res = {};
  for (const name0 of clips) {
    let name = name0;
    if (scale !== 1 && name0 !== 'demo.combo1M') name = scaledClip(name0, name0 + '@' + id, scale);
    invalidateClips();
    const start = /combo2/.test(name0) ? 'demo.c1end' : /combo3/.test(name0) ? 'demo.c2end' : 'demo.stance';
    resetChar(c, scale !== 1 ? scaledClip('demo.idle', 'demo.idle@' + id, scale) : start);
    c.play(name, { fade: 0, restart: true });
    const cd = getClip(c.rig, name);
    const nf = Math.round(cd.duration * 60) * (cd.loop ? 2 : 1);
    const ds = [], as = [];
    let worstT = 0, worst = 0;
    for (let i = 0; i < nf; i++) {
      step(c);
      const pose = new Pose(c.rig); sampleClip(c.rig, cd, c.clipTime, pose);
      if (pose.grip < 0.999) continue;
      const e = gripErr(c);
      ds.push(e.d); as.push(e.a);
      if (e.d > worst) { worst = e.d; worstT = c.clipTime; }
    }
    res[name0] = { dist: statsMM(ds), angDegMax: ds.length ? deg(Math.max(...as)) : null, worstAt: r1(worstT, 3) };
  }
  return { design: id, scale: r1(scale, 3), perClip: res, nan: anyNaN(c) };
}
/** Crossfades between clips that use different grip points / chain transitions: per-frame jump of the off hand. */
function testGripSwitch() {
  const c = mk('kael');
  const out = {};
  const run = (from, to, fade, warm = 0.6) => {
    resetChar(c, from);
    for (let i = 0; i < Math.round(warm * 60); i++) step(c);
    c.play(to, { fade, restart: true });
    const rows = [];
    let prev = wpos(c, 'weaponL'), maxJ = 0, maxD = 0;
    for (let i = 0; i < 30; i++) {
      step(c);
      const p = wpos(c, 'weaponL');
      const j = p.distanceTo(prev); prev = p;
      const e = gripErr(c);
      maxJ = Math.max(maxJ, j); maxD = Math.max(maxD, e.d);
      if (i < 8) rows.push({ frame: i + 1, offHandStepMM: mm(j), gripDistMM: mm(e.d) });
    }
    return { maxOffHandStepMM: mm(maxJ), maxGripDistMM: mm(maxD), first: rows };
  };
  out.idle_to_guard_fade0_25 = run('demo.idle', 'demo.guard', 0.25);
  out.guard_to_idle_fade0_25 = run('demo.guard', 'demo.idle', 0.25);
  out.idle_to_combo1_fade0_06 = run('demo.idle', 'demo.combo1', 0.06);
  out.walkF_to_idle_fade0_2 = run('demo.walkF', 'demo.idle', 0.2, 0.3);
  // reference: steady-state per-frame motion of the off hand in combo1 (fast strike)
  resetChar(c, 'demo.stance'); c.play('demo.combo1', { fade: 0, restart: true });
  let prev = wpos(c, 'weaponL'), maxJ = 0;
  for (let i = 0; i < 57; i++) { step(c); const p = wpos(c, 'weaponL'); maxJ = Math.max(maxJ, p.distanceTo(prev)); prev = p; }
  out.reference_combo1_maxOffHandStepMM = mm(maxJ);
  return out;
}
/** Blade roll around its own axis when a key gives `aim` without `up` (up defaults to world +Y). */
function testAimRoll() {
  const c = mk('kael');
  const out = {};
  const roll = (q0, q1) => {
    const x0 = new THREE.Vector3(1, 0, 0).applyQuaternion(q0), y0 = new THREE.Vector3(0, 1, 0).applyQuaternion(q0);
    const x1 = new THREE.Vector3(1, 0, 0).applyQuaternion(q1), y1 = new THREE.Vector3(0, 1, 0).applyQuaternion(q1);
    const tr = new THREE.Quaternion().setFromUnitVectors(x0, x1);
    const yt = y0.clone().applyQuaternion(tr);
    return (Math.atan2(yt.clone().cross(y1).dot(x1), yt.dot(y1)) * 180) / Math.PI;
  };
  for (const [clip, start, dur] of [['demo.guard', 'demo.guard', 2.0], ['demo.idle', 'demo.idle', 2.6], ['demo.combo1', 'demo.stance', 0.95], ['demo.combo2', 'demo.c1end', 0.9]]) {
    resetChar(c, start); c.breath.depth = 0;
    c.play(clip, { fade: 0, restart: true });
    step(c, 1 / 60, false);
    const q0 = wquat(c, 'weaponR');
    let maxRoll = 0, at = 0, maxAimChange = 0;
    const x0 = new THREE.Vector3(1, 0, 0).applyQuaternion(q0);
    const samples = [];
    for (let i = 1; i < Math.round(dur * 60); i++) {
      step(c, 1 / 60, false);
      const q = wquat(c, 'weaponR');
      const r = roll(q0, q);
      const ac = (Math.acos(Math.min(1, new THREE.Vector3(1, 0, 0).applyQuaternion(q).dot(x0))) * 180) / Math.PI;
      if (Math.abs(r) > Math.abs(maxRoll)) { maxRoll = r; at = c.clipTime; }
      maxAimChange = Math.max(maxAimChange, ac);
      if (i % 15 === 0) samples.push({ t: r1(c.clipTime, 3), rollDeg: r1(r, 1), aimChangeDeg: r1(ac, 1) });
    }
    out[clip] = { maxRollDeg: r1(maxRoll, 1), at: r1(at, 3), maxAimChangeDeg: r1(maxAimChange, 1), samples: clip === 'demo.guard' || clip === 'demo.idle' ? samples : undefined };
  }
  return out;
}
/** Finger geometry vs the grip cylinder (radial distance of finger / thumb vertices from the weapon axis). */
function fingerVerts(c) {
  if (c._fv) return c._fv;
  const mesh = c.meshes.plate, g = mesh.geometry;
  const si = g.attributes.skinIndex, sw = g.attributes.skinWeight, pos = g.attributes.position;
  const want = {};
  for (const s of ['R', 'L']) for (const b of ['fingers', 'fingerTips', 'thumb']) want[c.rig.index[b + s]] = b + s;
  const list = [];
  const v = V();
  for (let i = 0; i < pos.count; i++) {
    const b = si.getX(i);
    if (want[b] === undefined || sw.getX(i) < 0.999) continue;
    v.fromBufferAttribute(pos, i).applyMatrix4(c.skeleton.boneInverses[b]);
    list.push({ bone: want[b], local: v.clone() });
  }
  c._fv = list;
  return list;
}
function testFingers() {
  const c = mk('kael');
  const out = {};
  for (const [clip, t] of [['demo.idle', 0.5], ['demo.guard', 0.5], ['demo.combo1', 0.25], ['demo.walkF', 0.3]]) {
    resetChar(c, clip); c.play(clip, { fade: 0, restart: true });
    for (let i = 0; i < Math.round(t * 60); i++) step(c, 1 / 60, false);
    const o = wpos(c, 'weaponR'), d = wpos(c, 'weaponR', [1, 0, 0]).sub(o).normalize();
    const cd = getClip(c.rig, clip);
    const gp = wpos(c, 'weaponR', Array.from((c.weapon.grips[cd.gripAt] || c.weapon.grips.grip).pos));
    const per = {};
    for (const fv of fingerVerts(c)) {
      const p = fv.local.clone().applyMatrix4(c.bones[fv.bone].matrixWorld);
      const rel = p.clone().sub(o);
      const ax = rel.dot(d);
      const rad = rel.clone().addScaledVector(d, -ax).length();
      const side = fv.bone.slice(-1);
      // axial position relative to the hand's own fist centre on the axis
      const centreAx = side === 'R' ? 0 : gp.clone().sub(o).dot(d);
      (per[fv.bone] = per[fv.bone] || []).push({ rad, ax: ax - centreAx });
    }
    const handle = 0.0199; // leather grip cylinder r 0.0175 + wrap tube 0.0024
    const sum = {};
    for (const [b, arr] of Object.entries(per)) {
      const rads = arr.filter((x) => Math.abs(x.ax) < 0.06).map((x) => x.rad);
      const s = stats(rads);
      sum[b] = s.n ? { verts: s.n, minRadMM: mm(s.min), p10RadMM: mm([...rads].sort((x, y) => x - y)[Math.floor(rads.length * 0.1)]), medianRadMM: mm(s.p50), penetrationMM: mm(Math.max(0, handle - s.min)), innerGapMM: mm(s.min - handle) } : { verts: 0, note: 'no vertex within 6 cm of the grip point along the axis' };
    }
    out[clip] = sum;
  }
  return { handleRadiusMM: 19.9, perClip: out };
}
/** Wrist / forearm / upper-arm twist + swing ranges produced by the IK in the demo clips. */
function testWrist() {
  const c = mk('kael');
  const res = {};
  for (const clip of DEMO) {
    const start = /combo2/.test(clip) ? 'demo.c1end' : /combo3/.test(clip) ? 'demo.c2end' : 'demo.stance';
    resetChar(c, start); c.play(clip, { fade: 0, restart: true });
    const cd = getClip(c.rig, clip);
    const m = {};
    const prevTw = {};
    for (let i = 0; i < Math.round(cd.duration * 60); i++) {
      step(c);
      for (const b of ['handR', 'handL', 'upperArmR', 'upperArmL', 'footR', 'footL']) {
        const ts = twistSwing(c.bones[b].quaternion);
        const r = (m[b] = m[b] || { maxAbsTwist: 0, maxSwing: 0, maxTwistStep: 0 });
        r.maxAbsTwist = Math.max(r.maxAbsTwist, Math.abs(ts.twist)); r.maxSwing = Math.max(r.maxSwing, ts.swing);
        if (prevTw[b] !== undefined) r.maxTwistStep = Math.max(r.maxTwistStep, Math.abs(ts.twist - prevTw[b]));
        prevTw[b] = ts.twist;
      }
      const v = twistSwing(c.bones.foreArmTwistR.quaternion).twist, v2 = twistSwing(c.bones.foreArmTwistL.quaternion).twist;
      m.vambraceTwistR = Math.max(m.vambraceTwistR || 0, Math.abs(v)); m.vambraceTwistL = Math.max(m.vambraceTwistL || 0, Math.abs(v2));
    }
    for (const r of Object.values(m)) if (typeof r === 'object') for (const k of Object.keys(r)) r[k] = r1(r[k], 1);
    res[clip] = m;
  }
  return res;
}

// ---- 5. ground contact --------------------------------------------------------------------------------------------
function footVerts(c) {
  if (c._footv) return c._footv;
  const mesh = c.meshes.plate, g = mesh.geometry;
  const si = g.attributes.skinIndex, sw = g.attributes.skinWeight, pos = g.attributes.position;
  const want = {};
  for (const s of ['R', 'L']) for (const b of ['foot', 'toe']) want[c.rig.index[b + s]] = b + s;
  const list = [];
  const v = V();
  for (let i = 0; i < pos.count; i++) {
    const b = si.getX(i);
    if (want[b] === undefined || sw.getX(i) < 0.999) continue;
    v.fromBufferAttribute(pos, i).applyMatrix4(c.skeleton.boneInverses[b]);
    list.push({ bone: want[b], side: want[b].slice(-1), local: v.clone() });
  }
  c._footv = list;
  return list;
}
function testContact(id = 'kael', clips = DEMO, scale = 1, dt = 1 / 60, opts = {}) {
  const c = mk(id);
  const P = c.rig.P;
  const res = {};
  const fv = footVerts(c);
  const tmp = V();
  for (const name0 of clips) {
    let name = name0;
    if (scale !== 1 && name0 !== 'demo.combo1M') name = scaledClip(name0, name0 + '@' + id, scale);
    invalidateClips();
    resetChar(c, scale !== 1 ? scaledClip('demo.idle', 'demo.idle@' + id, scale) : 'demo.idle');
    if (opts.noBreath) c.breath.depth = 0;
    c.play(name, { fade: 0, restart: true });
    const cd = getClip(c.rig, name);
    const nf = Math.round((cd.duration / dt) * (cd.loop ? 2 : 1));
    const feet = { R: { planted: null, drift: [], yaw: [] }, L: { planted: null, drift: [], yaw: [] } };
    let minVert = 1, minSole = 1, minTip = 1, minHeel = 1, maxDrop = 0, maxDropStep = 0, prevDrop = null;
    const pose = new Pose(c.rig);
    for (let i = 0; i < nf; i++) {
      step(c, dt, true);
      sampleClip(c.rig, cd, c.clipTime, pose);
      const drop = (c.rig.offset[1] + pose.hips[1]) - c.bones.hips.position.y;
      maxDrop = Math.max(maxDrop, drop);
      if (prevDrop !== null) maxDropStep = Math.max(maxDropStep, Math.abs(drop - prevDrop));
      prevDrop = drop;
      for (const v of fv) { tmp.copy(v.local).applyMatrix4(c.bones[v.bone].matrixWorld); if (tmp.y < minVert) minVert = tmp.y; }
      for (const S of ['R', 'L']) {
        const sole = wpos(c, 'foot' + S, [0, -P.ankleHeight, 0]);
        const heel = wpos(c, 'foot' + S, [-P.heelLength, -P.ankleHeight + 0.01, 0]);
        const ball = wpos(c, 'toe' + S, [0, -(P.ankleHeight - P.footDrop), 0]);
        const tip = wpos(c, 'toe' + S, [P.toeLength, -(P.ankleHeight - P.footDrop), 0]);
        minSole = Math.min(minSole, sole.y, ball.y); minTip = Math.min(minTip, tip.y); minHeel = Math.min(minHeel, heel.y);
        const fwd = wpos(c, 'foot' + S, [1, 0, 0]).sub(wpos(c, 'foot' + S));
        const yaw = Math.atan2(-fwd.z, fwd.x);
        const F = feet[S];
        const flat = sole.y < 0.004 * scale && ball.y < 0.006 * scale;
        if (flat) {
          if (!F.planted) F.planted = { p: sole.clone(), yaw, t: c.clipTime, max: 0, maxYaw: 0, n: 0 };
          const d = Math.hypot(sole.x - F.planted.p.x, sole.z - F.planted.p.z);
          F.planted.max = Math.max(F.planted.max, d); F.planted.maxYaw = Math.max(F.planted.maxYaw, Math.abs(yaw - F.planted.yaw)); F.planted.n++;
        } else if (F.planted) { if (F.planted.n > 2) { F.drift.push({ t0: r1(F.planted.t, 3), frames: F.planted.n, driftMM: mm(F.planted.max / scale), yawDeg: deg(F.planted.maxYaw) }); } F.planted = null; }
      }
    }
    for (const S of ['R', 'L']) { const F = feet[S]; if (F.planted && F.planted.n > 2) F.drift.push({ t0: r1(F.planted.t, 3), frames: F.planted.n, driftMM: mm(F.planted.max / scale), yawDeg: deg(F.planted.maxYaw), open: true }); }
    const allDrift = [...feet.R.drift, ...feet.L.drift];
    res[name0] = {
      maxPlantedDriftMM: allDrift.length ? Math.max(...allDrift.map((d) => d.driftMM)) : null,
      plantedIntervals: { R: feet.R.drift, L: feet.L.drift },
      minSoleOrBallYMM: mm(minSole / scale), minHeelYMM: mm(minHeel / scale), minToeTipYMM: mm(minTip / scale), minSabatonVertexYMM: mm(minVert / scale),
      maxAutoPelvisDropMM: mm(maxDrop / scale), maxDropStepMM: mm(maxDropStep / scale),
    };
  }
  return { design: id, scale: r1(scale, 3), dtFps: Math.round(1 / dt), perClip: res, nan: anyNaN(c), note: scale !== 1 ? 'values normalised to human scale (divided by the clip scale)' : undefined };
}
/** Crossfade foot slide: walk -> idle fade at various phases. */
function testFadeSlide() {
  const c = mk('kael');
  const out = [];
  for (const phase of [0.15, 0.3, 0.6]) {
    resetChar(c, 'demo.idle');
    c.play('demo.walkF', { fade: 0, restart: true });
    for (let i = 0; i < Math.round(phase * 60); i++) step(c);
    const p0 = { R: wpos(c, 'footR', [0, -c.rig.P.ankleHeight, 0]), L: wpos(c, 'footL', [0, -c.rig.P.ankleHeight, 0]) };
    c.play('demo.idle', { fade: 0.2, restart: true });
    let slide = { R: 0, L: 0 };
    for (let i = 0; i < 20; i++) {
      step(c);
      for (const S of ['R', 'L']) {
        const p = wpos(c, 'foot' + S, [0, -c.rig.P.ankleHeight, 0]);
        if (p0[S].y < 0.004) slide[S] = Math.max(slide[S], Math.hypot(p.x - p0[S].x, p.z - p0[S].z));
      }
    }
    out.push({ walkPhase: phase, plantedFootSlideMM: { R: mm(slide.R), L: mm(slide.L) }, plantedAtFade: { R: p0.R.y < 0.004, L: p0.L.y < 0.004 } });
  }
  return out;
}

// ---- 6. proportions ------------------------------------------------------------------------------------------------
function testProps() {
  const out = {};
  for (const id of ['iska', 'vorn']) {
    out[id] = {
      scale: r1(SCALE[id], 4),
      ikPure: testIkPure(id, 200).perLimb,
      gripUnscaledKaelClips: testGrip(id, DEMO).perClip,
      gripScaledClips: testGrip(id, DEMO.filter((n) => n !== 'demo.combo1M'), SCALE[id]).perClip,
      contactUnscaled: testContact(id, ['demo.walkF', 'demo.combo1', 'demo.combo3', 'demo.slam', 'demo.hit']).perClip,
    };
  }
  out.giant = {
    scale: GIANT_K,
    ikPure: testIkPure('giant', 200).perLimb,
    ikSweep: testIkSweep('giant'),
    gripScaledClips: testGrip('giant', DEMO.filter((n) => n !== 'demo.combo1M'), GIANT_K).perClip,
    contactScaledClips: testContact('giant', ['demo.walkF', 'demo.combo1', 'demo.combo3', 'demo.slam', 'demo.hit'], GIANT_K).perClip,
  };
  return out;
}
/** Giant (4.2x) with 4.2x-scaled clips vs the default rig: joint positions / 4.2 should match exactly. */
function testGiantNorm() {
  const g = mk('giant');
  if (!charCache.has('kaelNoCloth')) charCache.set('kaelNoCloth', createCharacter(CTX, { ...knight, cloth: [] }, { parent: null, name: 'kaelNoCloth' }));
  const k = charCache.get('kaelNoCloth');
  const names = animatedNames(k);
  const out = {};
  const sock = ['chest', 'head', 'back', 'footR'];
  for (const clip of ['demo.walkF', 'demo.combo1', 'demo.combo3', 'demo.slam']) {
    scaledClip(clip, clip + '@giant', GIANT_K); scaledClip('demo.idle', 'demo.idle@giant', GIANT_K);
    invalidateClips();
    for (const [c, nm] of [[k, clip], [g, clip + '@giant']]) { resetChar(c, c === k ? 'demo.idle' : 'demo.idle@giant'); c.play(nm, { fade: 0, restart: true }); }
    let worst = 0, wb = '', wt = 0, worstNoBreath = null;
    const fingerW = { v: 0 };
    for (let i = 0; i < 60; i++) {
      step(k); step(g);
      for (const n of names) {
        const a = wpos(k, n), b = wpos(g, n).multiplyScalar(1 / GIANT_K);
        const e = a.distanceTo(b);
        if (e > worst) { worst = e; wb = n; wt = k.clipTime; }
        if (/^finger|^thumb/.test(n)) fingerW.v = Math.max(fingerW.v, e);
      }
    }
    const socketErr = {};
    for (const s of sock) socketErr[s] = mm(g.sockets[s].getWorldPosition(V()).multiplyScalar(1 / GIANT_K).distanceTo(k.sockets[s].getWorldPosition(V())));
    out[clip] = { worstNormalisedErrMM: mm(worst), bone: wb, t: r1(wt, 3), fingersMaxErrMM: mm(fingerW.v), socketErrMM: socketErr, worstNoBreath };
  }
  // with breathing off and no flinch: isolates hard-coded lengths
  for (const c of [k, g]) { resetChar(c, c === k ? 'demo.idle' : 'demo.idle@giant'); c.breath.depth = 0; }
  k.play('demo.combo1', { fade: 0, restart: true }); g.play('demo.combo1@giant', { fade: 0, restart: true });
  let w0 = 0, wb0 = '';
  for (let i = 0; i < 57; i++) {
    step(k); step(g);
    for (const n of names) { const e = wpos(k, n).distanceTo(wpos(g, n).multiplyScalar(1 / GIANT_K)); if (e > w0) { w0 = e; wb0 = n; } }
  }
  out.combo1_noBreath = { worstNormalisedErrMM: mm(w0), bone: wb0 };
  // body only (no fingers / thumb), no breathing
  for (const c of [k, g]) { resetChar(c, c === k ? 'demo.idle' : 'demo.idle@giant'); c.breath.depth = 0; }
  k.play('demo.combo1', { fade: 0, restart: true }); g.play('demo.combo1@giant', { fade: 0, restart: true });
  const body = names.filter((n) => !/^(finger|thumb)/.test(n));
  const per = {};
  for (let i = 0; i < 57; i++) {
    step(k); step(g);
    for (const n of body) { const e = wpos(k, n).distanceTo(wpos(g, n).multiplyScalar(1 / GIANT_K)); per[n] = Math.max(per[n] || 0, e); }
  }
  out.combo1_bodyNoBreath = Object.entries(per).sort((a, b) => b[1] - a[1]).slice(0, 6).map(([n, e]) => [n, mm(e)]);
  // rig rest offsets that do not follow the proportions
  const r0 = createRig({}), rg = createRig(PROPS.giant);
  const fixed = [];
  for (let i = 0; i < r0.count; i++) {
    const a = [r0.offset[i * 3], r0.offset[i * 3 + 1], r0.offset[i * 3 + 2]], b = [rg.offset[i * 3], rg.offset[i * 3 + 1], rg.offset[i * 3 + 2]];
    const e = Math.hypot(b[0] / GIANT_K - a[0], b[1] / GIANT_K - a[1], b[2] / GIANT_K - a[2]);
    if (e > 1e-6) fixed.push({ bone: r0.names[i], offset: a.map((x) => r1(x, 4)), giantOffset: b.map((x) => r1(x, 4)), shouldBe: a.map((x) => r1(x * GIANT_K, 4)) });
  }
  out.restOffsetsNotScaled = fixed;
  return out;
}

// ---- CPU -----------------------------------------------------------------------------------------------------------
function testCpu() {
  const out = {};
  for (const id of ['kael', 'giant']) {
    const c = mk(id);
    resetChar(c);
    c.play(id === 'giant' ? scaledClip('demo.combo3', 'demo.combo3@giant', GIANT_K) : 'demo.combo3', { fade: 0, restart: true, loop: true });
    for (let i = 0; i < 60; i++) step(c);
    const N = 600;
    const t0 = performance.now();
    for (let i = 0; i < N; i++) { c.update(1 / 60, 1 / 60); }
    const t1 = performance.now();
    out[id] = { msPerUpdate: r1((t1 - t0) / N, 3), bones: c.rig.count };
  }
  return out;
}

/** Per-frame trace of a clip: socket / bone positions (root space, mm), clip time, jumps. */
function trace(clip, start = 'demo.stance', f0 = 0, f1 = 60, bones = ['weaponR', 'foreArmR'], id = 'kael') {
  const c = mk(id);
  resetChar(c, start); c.play(clip, { fade: 0, restart: true });
  const out = [];
  const prev = {};
  for (let i = 0; i < f1; i++) {
    step(c);
    const row = { f: i + 1, t: r1(c.clipTime, 4) };
    for (const b of bones) {
      const p = lpos(c, b);
      row[b] = p.toArray().map(mm);
      if (prev[b]) row[b + 'Step'] = mm(p.distanceTo(prev[b]));
      prev[b] = p;
    }
    row.hipsYaw = r1(new THREE.Euler().setFromQuaternion(c.bones.hips.quaternion, 'ZXY').y * 180 / Math.PI, 1);
    if (i >= f0) out.push(row);
  }
  return out;
}

/** Per-frame foot / pelvis trace: sole world xz, clip foot target (root space), hip->target horizontal distance, drop. */
function traceFeet(clip, start = 'demo.stance', f0 = 0, f1 = 60, every = 1) {
  const c = mk('kael');
  resetChar(c, start); c.play(clip, { fade: 0, restart: true });
  const cd = getClip(c.rig, clip), P = c.rig.P, pose = new Pose(c.rig), R = (c.rig.lengths.thigh + c.rig.lengths.shin) * 0.97;
  const out = [];
  for (let i = 0; i < f1; i++) {
    step(c);
    if (i < f0 || (i - f0) % every) continue;
    sampleClip(c.rig, cd, c.clipTime, pose);
    const row = { f: i + 1, t: r1(c.clipTime, 3), drop: mm(c.rig.offset[1] + pose.hips[1] - c.bones.hips.position.y) };
    for (const [S, e] of [['R', 2], ['L', 3]]) {
      const o = e * 24, sole = wpos(c, 'foot' + S, [0, -P.ankleHeight, 0]), hip = lpos(c, 'thigh' + S);
      const tgt = pose.ik[o] > 0 ? [pose.ik[o + 1], pose.ik[o + 2], pose.ik[o + 3]] : null;
      row[S] = { soleW: [mm(sole.x), mm(sole.y), mm(sole.z)], tgtRoot: tgt && tgt.map(mm), hz: tgt && r1(Math.hypot(tgt[0] - hip.x, tgt[2] - hip.z) / R, 3) };
    }
    out.push(row);
  }
  return out;
}

/** Pelvis height smoothness: max second difference (mm/frame^2) of the actual vs the authored hips height. */
function hipsJerk(clips = DEMO) {
  const c = mk('kael');
  const out = {};
  for (const clip of clips) {
    const start = /combo2/.test(clip) ? 'demo.c1end' : /combo3/.test(clip) ? 'demo.c2end' : 'demo.stance';
    resetChar(c, start); c.breath.depth = 0; c.play(clip, { fade: 0, restart: true });
    const cd = getClip(c.rig, clip), pose = new Pose(c.rig);
    const A = [], B = [], T = [];
    const n = Math.round(cd.duration * 60) * (cd.loop ? 2 : 1);
    for (let i = 0; i < n; i++) { step(c); sampleClip(c.rig, cd, c.clipTime, pose); A.push(c.bones.hips.position.y); B.push(c.rig.offset[1] + pose.hips[1]); T.push(c.clipTime); }
    let ja = 0, jb = 0, at = 0;
    for (let i = 2; i < n; i++) {
      if (T[i] < T[i - 2]) continue; // loop wrap
      const a = Math.abs(A[i] - 2 * A[i - 1] + A[i - 2]), b = Math.abs(B[i] - 2 * B[i - 1] + B[i - 2]);
      if (a > ja) { ja = a; at = T[i]; }
      jb = Math.max(jb, b);
    }
    out[clip] = { actualMaxD2mm: mm(ja), authoredMaxD2mm: mm(jb), at: r1(at, 3), ratio: r1(ja / Math.max(jb, 1e-6), 1) };
  }
  return out;
}

/** Twist-helper pops: frames where the forearm twist helper (vambrace) turns > 60 deg in one frame. */
function twistPops(clips = DEMO) {
  const c = mk('kael');
  const out = {};
  for (const clip of clips) {
    const start = /combo2/.test(clip) ? 'demo.c1end' : /combo3/.test(clip) ? 'demo.c2end' : 'demo.stance';
    resetChar(c, start); c.play(clip, { fade: 0, restart: true });
    const cd = getClip(c.rig, clip);
    const prev = {}, pops = [];
    let maxSwing = { R: [0, 0], L: [0, 0] };
    for (let i = 0; i < Math.round(cd.duration * 60); i++) {
      step(c);
      for (const S of ['R', 'L']) {
        const q = wquat(c, 'foreArmTwist' + S);
        if (prev[S]) { const a = deg(qAngle(prev[S], q)); if (a > 60) pops.push({ t: r1(c.clipTime, 3), side: S, helperTurnDeg: a, handTwistDeg: r1(twistSwing(c.bones['hand' + S].quaternion).twist, 1) }); }
        prev[S] = q.clone();
        const sw = twistSwing(c.bones['hand' + S].quaternion).swing;
        if (sw > maxSwing[S][0]) maxSwing[S] = [r1(sw, 1), r1(c.clipTime, 3)];
      }
    }
    out[clip] = { pops, maxWristSwing: maxSwing };
  }
  return out;
}
/** Off-hand reach when the grip is lost: distance shoulder(upperArmL) -> wrist target / arm length. */
function gripReach(clip, start, times) {
  const c = mk('kael');
  resetChar(c, start); c.play(clip, { fade: 0, restart: true });
  const P = c.rig.P, L = c.rig.lengths.upperArm + c.rig.lengths.foreArm;
  const out = [];
  let f = 0;
  for (const t of times) {
    while (f < Math.round(t * 60)) { step(c); f++; }
    const e = gripErr(c);
    const g = wpos(c, 'weaponR', Array.from(c.weapon.grips.grip.pos));
    const qg = wquat(c, 'weaponR');
    const wristT = g.clone().sub(new THREE.Vector3(0, -P.hand, P.palm).applyQuaternion(qg));
    out.push({ t: r1(c.clipTime, 3), gripDistMM: mm(e.d), reachRatio: r1(wristT.distanceTo(wpos(c, 'upperArmL')) / L, 3), mainFist: lpos(c, 'weaponR').toArray().map(mm) });
  }
  return out;
}
/** Root-space hand target error caused by a resolve-stage pelvis drop that update() does not re-apply. */
function resolveDropHand() {
  const c = mk('kael');
  const out = {};
  for (const withFoot of [false, true]) {
    resetChar(c, 'neutral.hold'); c.breath.depth = 0;
    const ik = { handR: { pos: [0.35, 1.2, 0.2], aim: [1, 0, 0], up: [0, 1, 0] } };
    if (withFoot) ik.footR = { space: 'hips', pos: [0.25, -0.65, 0.12], rot: [0, 0, 0] };
    defineClip('audit.rdh', { duration: 1, loop: true, keys: [{ t: 0, pose: 'neutral', grip: 0, hips: { pos: [0, 0.05, 0] }, bones: { thighL: [0, 0, 40], shinL: [0, 0, -70], thighR: [0, 0, 20], shinR: [0, 0, -40] }, ik }] });
    invalidateClips();
    c.play('audit.rdh', { fade: 0, restart: true }); step(c, 1 / 60, false); step(c, 1 / 60, false);
    out[withFoot ? 'withHipsSpaceFoot' : 'handOnly'] = { handErrMM: mm(lpos(c, 'weaponR').distanceTo(new THREE.Vector3(0.35, 1.2, 0.2))), hipsY: mm(lpos(c, 'hips').y) };
  }
  return out;
}

/** Look-at accuracy, root-space hands under a root spin without breathing, straight-leg standing height. */
function misc() {
  const c = mk('kael');
  const out = {};
  // look-at: angle between the head's +X and the direction from the eye point to the target
  const looks = [];
  for (const tg of [[3, 1.75, 0], [3, 1.7, 1.2], [3, 1.7, -1.2], [2, 0.6, 0], [1.2, 2.6, 0.3], [0.5, 1.7, 2.0]]) {
    resetChar(c, 'demo.idle'); c.breath.depth = 0;
    const w = new THREE.Vector3(...tg);
    c.lookAt(w, 1);
    for (let i = 0; i < 60; i++) step(c, 1 / 60, false);
    const hp = wpos(c, 'head'), eye = hp.clone().add(new THREE.Vector3(0, 0.08, 0));
    const fwd = wpos(c, 'head', [1, 0, 0]).sub(hp).normalize();
    const want = w.clone().sub(eye).normalize();
    looks.push({ target: tg, errDeg: deg(Math.acos(Math.min(1, fwd.dot(want)))), requestedDeg: deg(Math.acos(Math.min(1, want.dot(wpos(c, 'chest', [1, 0, 0]).sub(wpos(c, 'chest')).normalize())))) });
  }
  out.lookAt = looks;
  c.lookAt(null);
  // root-space hand target with the root spinning / mirroring, breathing OFF
  resetChar(c, 'demo.stance'); c.breath.depth = 0;
  let rootErr = 0;
  for (let i = 0; i < 60; i++) {
    c.root.rotation.y = (i / 60) * Math.PI * 2; c.root.position.z = 0.3 * Math.sin(i * 0.2);
    if (i === 30) c.setFacing(-1);
    step(c, 1 / 60, false);
    rootErr = Math.max(rootErr, wpos(c, 'weaponR').distanceTo(new THREE.Vector3(0.33, 1.08, 0.1).applyMatrix4(c.root.matrixWorld)));
  }
  out.rootSpaceSpinFlipNoBreathMM = mm(rootErr);
  c.root.rotation.set(0, 0, 0); c.setFacing(1);
  // standing straight-legged (neutral.hold / zero pose): pelvis height and knee bend vs the README zero pose
  for (const [name, y] of [['onFloor', 0], ['airborne', 1.5]]) {
    resetChar(c, 'neutral.hold'); c.breath.depth = 0; c.root.position.y = y;
    for (let i = 0; i < 3; i++) step(c, 1 / 60, false);
    const knee = twistSwing(c.bones.shinR.quaternion).swing;
    out['neutral_' + name] = { hipsYmm: mm(c.bones.hips.position.y), readmeHipsYmm: 1040, kneeBendDeg: r1(knee, 1), soleYmm: mm(lpos(c, 'footR', [0, -c.rig.P.ankleHeight, 0]).y) };
  }
  c.root.position.y = 0;
  return out;
}

/** mirrorClip hands:'keep' with FK-keyed arms and a keyed weapon bone. */
function keepFK() {
  defineClip('audit.kfk', { duration: 0.5, keys: [{ t: 0, pose: 'neutral', grip: 0, hips: { rot: [0, -25, 0] }, bones: { chest: [0, -15, 0], upperArmR: [-30, 0, 70], foreArmR: [0, 0, 40], weaponR: [0, 20, 0] } }] });
  mirrorClip('audit.kfk', 'audit.kfkK', { hands: 'keep' });
  invalidateClips();
  const keys = getClipDef('audit.kfkK').keys[0].bones;
  const [a, b] = twins();
  for (const c of [a, b]) resetChar(c);
  a.play('audit.kfk', { fade: 0, restart: true }); b.play('audit.kfkK', { fade: 0, restart: true });
  for (let i = 0; i < 4; i++) { step(a, 1 / 60, false); step(b, 1 / 60, false); }
  const fa = lpos(a, 'weaponR'), fb = lpos(b, 'weaponR');
  const out = { mirroredKeyBones: Object.keys(keys), fistR_src: fa.toArray().map(mm), fistR_keep: fb.toArray().map(mm), fistR_expectedMirror: [mm(fa.x), mm(fa.y), mm(-fa.z)], fistErrMM: mm(fb.distanceTo(new THREE.Vector3(fa.x, fa.y, -fa.z))) };
  a.dispose(); b.dispose();
  return out;
}

const TESTS = {
  trace, traceFeet, hipsJerk, twistPops, gripReach, resolveDropHand, misc, keepFK,
  conventions: () => testConventions('kael'), examples: testExamples, mirror: testMirrorReal, facing: testFacing,
  ikPure: () => ({ kael: testIkPure('kael'), iska: testIkPure('iska'), vorn: testIkPure('vorn'), giant: testIkPure('giant') }),
  ikPipelineBent: () => testIkPipeline('kael', 500, true),
  ikSweep: () => testIkSweep('kael'), ikPole: () => testIkPole('kael'), ikPoleGiant: () => testIkPole('giant'), ikPipeline: () => testIkPipeline('kael'),
  spaces: testSpaces, hipsFoot: testHipsFoot, kneePole: testKneePole, dropSweep: testDropSweep, toeRoll: testToeRoll,
  grip: () => testGrip('kael'), gripSwitch: testGripSwitch, aimRoll: testAimRoll, fingers: testFingers, wrist: testWrist,
  contact: () => testContact('kael'), contact30: () => testContact('kael', ['demo.walkF', 'demo.walkB', 'demo.slam', 'demo.hit', 'demo.combo3'], 1, 1 / 30),
  contactNoBreath: () => testContact('kael', DEMO, 1, 1 / 60, { noBreath: true }),
  fadeSlide: testFadeSlide, props: testProps, giantNorm: testGiantNorm, cpu: testCpu,
};

// ---- lab page (captures) ------------------------------------------------------------------------------------------
createLab({
  view: { target: [0, 1.05, 0], dist: 5.0, yaw: 0, pitch: 4, fov: 40 },
  setup(ctx, lab) {
    CTX = ctx;
    const pm = new THREE.PMREMGenerator(ctx.renderer);
    ctx.scene.environment = pm.fromScene(new RoomEnvironment(), 0.04).texture;
    ctx.scene.environmentIntensity = 0.35;
    pm.dispose();
    lab.lights.key.intensity = 3.2;
    const live = [];
    const st = { applyRoot: true, tick: null };
    lab.live = live; lab.st = st;
    lab.add = (id, x = 0) => {
      const c = createCharacter(ctx, variant(id), { name: 'live_' + id + live.length });
      c.root.position.x = x; c.play(id === 'giant' ? scaledClip('demo.idle', 'demo.idle@giant', GIANT_K) : 'demo.idle', { fade: 0 }); c.update(0, 0);
      live.push(c);
      return c;
    };
    lab.clear = () => { for (const c of live) c.dispose(); live.length = 0; st.tick = null; };
    ctx.onUpdate((dg, dr) => {
      if (st.tick) st.tick(dg);
      for (const c of live) {
        c.update(dg, dr);
        if (st.applyRoot) c.root.position.x += c.rootDelta.f * c.facing;
      }
    }, ORDER.CHAR);
    window.__ED.audit = {
      run(name, ...args) { const t = TESTS[name]; if (!t) throw new Error('no test ' + name + ' (' + Object.keys(TESTS).join(', ') + ')'); return t(...args); },
      list: () => Object.keys(TESTS),
      PROPS, SCALE,
    };
    lab.add('kael');
  },
  scenarios: {
    reset(ctx, lab) { lab.clear(); lab.add('kael'); lab.view({ target: [0, 1.05, 0], dist: 5, yaw: 0, pitch: 4 }); },
    clip(ctx, lab, name, id = 'kael', start = null, view = null) {
      lab.clear(); const c = lab.add(id);
      if (start) { c.play(start, { fade: 0, restart: true }); c.teleport(); c.update(1 / 60, 1 / 60); }
      c.play(name, { fade: 0, restart: true });
      if (view) lab.view(view);
    },
    gripswitch(ctx, lab) {
      // idle -> guard (grip point changes from 'grip' to 'blade') at t = 0.5 with a 0.25 s crossfade
      lab.clear(); const c = lab.add('kael'); let t = 0;
      lab.st.tick = (dt) => { t += dt; if (t > 0.5 && t - dt <= 0.5) c.play('demo.guard', { fade: 0.25, restart: true }); };
      lab.view({ target: [0.25, 1.15, 0.1], dist: 1.7, yaw: 20, pitch: 6 });
    },
    guardroll(ctx, lab) { lab.clear(); const c = lab.add('kael'); c.play('demo.guard', { fade: 0, restart: true }); lab.view({ target: [0.4, 1.45, 0.0], dist: 2.2, yaw: 60, pitch: 10 }); },
    dropsweep(ctx, lab) {
      lab.clear(); const c = lab.add('kael'); c.breath.depth = 0;
      const keys = [];
      for (let i = 0; i <= 80; i++) keys.push({ t: i * 0.1, interp: 'linear', ik: { footR: { pos: [-0.2 - i * 0.01, 0, 0.16], rot: [0, -30, 0] }, footL: { pos: [0.2, 0, -0.14], rot: [0, 10, 0] } } });
      defineClip('audit.dropv', { duration: 8.0, keys: [{ t: 0, pose: 'neutral', grip: 0 }, ...keys] });
      invalidateClips(); c.play('audit.dropv', { fade: 0, restart: true });
      lab.st.applyRoot = false;
      lab.view({ target: [-0.2, 0.7, 0], dist: 3.6, yaw: 0, pitch: 2 });
    },
    hipsfoot(ctx, lab) {
      lab.clear(); const a = lab.add('kael', -0.7), b = lab.add('kael', 0.7);
      defineClip('audit.hf0', { duration: 1, loop: true, keys: [{ t: 0, pose: 'neutral', grip: 0, hips: { pos: [0, -0.05, 0] } }] });
      defineClip('audit.hf1', { duration: 1, loop: true, keys: [{ t: 0, pose: 'neutral', grip: 0, hips: { pos: [0, -0.05, 0] }, ik: { footR: { space: 'hips', pos: [0.25, -0.65, 0.12], rot: [0, 0, 0] } } }] });
      invalidateClips(); a.play('audit.hf0', { fade: 0 }); b.play('audit.hf1', { fade: 0 });
      lab.st.applyRoot = false;
      lab.view({ target: [0, 0.95, 0], dist: 4.4, yaw: 0, pitch: 2 });
    },
    kneepole(ctx, lab) {
      lab.clear(); const a = lab.add('kael', -0.7), b = lab.add('kael', 0.7);
      defineClip('audit.kpv', { duration: 1, loop: true, keys: [{ t: 0, pose: 'neutral', grip: 0, hips: { pos: [0, -0.18, 0] }, ik: { footR: { pos: [0.05, 0, 0.28], rot: [0, -40, 0], pole: [0.2, 0.55, 0.9] } } }] });
      invalidateClips(); a.play('audit.kpv', { fade: 0 }); b.play('audit.kpv', { fade: 0 });
      a.root.position.y = 0.5; // raised: re-plant off, pole honoured
      lab.st.applyRoot = false;
      lab.view({ target: [0, 0.8, 0], dist: 4.6, yaw: 0, pitch: 25 });
    },
    polesweep(ctx, lab) {
      // right hand target swept on a horizontal circle (shoulder height - 0.45 m) around the shoulder: elbow path
      lab.clear(); const c = lab.add('kael'); c.breath.depth = 0;
      const keys = [];
      const sh = [-0.015, 1.52, 0.22], r = 0.57 * 0.8, h = -0.45;
      for (let i = 0; i <= 72; i++) {
        const a = (i / 72) * Math.PI * 2, rr = Math.sqrt(r * r - h * h);
        keys.push({ t: i * 0.05, interp: 'linear', ik: { handR: { pos: [sh[0] + Math.cos(a) * rr, sh[1] + h - 0.085, sh[2] + Math.sin(a) * rr] } } });
      }
      defineClip('audit.polev', { duration: 3.6, keys: [{ t: 0, pose: 'neutral', grip: 0 }, ...keys] });
      invalidateClips(); c.play('audit.polev', { fade: 0, restart: true });
      lab.st.applyRoot = false;
      lab.view({ target: [0, 1.2, 0.1], dist: 2.6, yaw: 35, pitch: 35 });
    },
    kicksweep(ctx, lab) {
      // right foot target swept on a horizontal arc at hip height (outside -> front -> across): knee path
      lab.clear(); const c = lab.add('kael'); c.breath.depth = 0;
      const keys = [], r = 0.895 * 0.8, hip = [0, 0.98, 0.1];
      for (let i = 0; i <= 36; i++) {
        const a = ((-60 + i * 5) * Math.PI) / 180;
        keys.push({ t: i * 0.1, interp: 'linear', ik: { footR: { pos: [hip[0] + Math.cos(a) * r, hip[1] - 0.085, hip[2] + Math.sin(-a) * r], rot: [0, 0, -30] } } });
      }
      defineClip('audit.kick', { duration: 3.6, keys: [{ t: 0, pose: 'neutral', grip: 0, hips: { pos: [0, -0.1, 0] }, bones: { thighL: [0, 0, 20], shinL: [0, 0, -40] } }, ...keys] });
      invalidateClips(); c.play('audit.kick', { fade: 0, restart: true });
      c.root.position.y = 0.2;
      lab.st.applyRoot = false;
      lab.view({ target: [0.3, 0.9, 0.1], dist: 3.0, yaw: 35, pitch: 30 });
    },
    fadeslide(ctx, lab) {
      // walk forward, at t = 0.3 cross-fade to idle over 0.2 s (planted right foot)
      lab.clear(); const c = lab.add('kael'); c.play('demo.walkF', { fade: 0, restart: true }); let t = 0;
      lab.st.tick = (dt) => { t += dt; if (t > 0.3 && t - dt <= 0.3) c.play('demo.idle', { fade: 0.2, restart: true }); };
      lab.view({ target: [0.3, 0.3, 0.1], dist: 2.4, yaw: 20, pitch: 25 });
    },
    turn(ctx, lab) { lab.clear(); const c = lab.add('kael'); let t = 0; lab.st.tick = (dt) => { t += dt; if (t > 0.1 && t - dt <= 0.1) c.setFacing(-1, { turn: 0.3 }); }; },
    lineup(ctx, lab, clip = 'demo.stance') {
      lab.clear();
      const ids = ['iska', 'kael', 'vorn'];
      ids.forEach((id, i) => { const c = lab.add(id, -1.3 + i * 1.3); c.play(clip, { fade: 0, restart: true }); });
      lab.st.applyRoot = false;
      lab.view({ target: [0, 1.0, 0], dist: 5.6, yaw: 0, pitch: 4 });
    },
    giant(ctx, lab, clip = 'demo.combo1') {
      lab.clear();
      const g = lab.add('giant', 0);
      const k = lab.add('kael', -2.6);
      g.play(scaledClip(clip, clip + '@giant', GIANT_K), { fade: 0, restart: true });
      k.play(clip, { fade: 0, restart: true });
      lab.st.applyRoot = false;
      lab.view({ target: [0, 3.6, 0], dist: 17, yaw: 0, pitch: 4 });
    },
  },
});
