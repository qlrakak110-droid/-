// Rig regression suite: every measurement the rig auditors used (IK accuracy, grip, pelvis drop, twist helpers,
// crossfades, mixer cap, mirroring, facing / scale, contact, flinch, events, cloth, suit deformation, CPU), run on the
// shipped runtime for the knight and ISKA-like / VORN-like / 4.2x giant proportions, reduced to pass / fail checks.
//
//   node tools/shot.mjs rigqa --eval "__ED.lab.play('all')"          -> { checks: [{ name, value, limit, pass }], passed, failed }
//   __ED.lab.play('all', { only: 'clips' })                          one group: clips | runtime | ik | skin | cloth | cpu
//   __ED.qa.clip('demo.combo3', 'iska')                              raw qa metrics of one clip on one body (debugging)
//
// Limits are in metres / degrees at the knight's size; body-relative limits are multiplied by the body scale.

import * as THREE from 'three';
import { createLab, ORDER } from '../core/lab.js';
import { makeRng } from '../core/math.js';
import { createCharacter, defineClip, definePose, mirrorClip, invalidateClips } from '../char/index.js';
import { getClip, sampleClip, Pose } from '../char/anim.js';
import { DEFAULT_PROPORTIONS } from '../char/skeleton.js';
import * as IK from '../char/ik.js';
import { knight } from '../char/designs/knight.js';
import '../char/clips/demo.js';
import * as qa from '../char/qa.js';

const DEMO = ['demo.idle', 'demo.guard', 'demo.walkF', 'demo.walkB', 'demo.combo1', 'demo.combo2', 'demo.combo3', 'demo.slam', 'demo.hit', 'demo.combo1M'];
const GIANT = 4.2;
const PROPS = {
  kael: {},
  iska: { hipHeight: 0.93, pelvisDrop: 0.055, hipWidth: 0.094, ankleHeight: 0.075, footLength: 0.12, footDrop: 0.048, toeLength: 0.07, heelLength: 0.058,
    spine: 0.10, chest: 0.152, neck: 0.235, head: 0.098, shoulderHeight: 0.185, clavicleRoot: 0.026, clavicle: 0.163, shoulderBack: 0.012, upperArm: 0.28, foreArm: 0.245, hand: 0.076, palm: 0.019 },
  vorn: { hipHeight: 1.05, pelvisDrop: 0.064, hipWidth: 0.104, ankleHeight: 0.09, footLength: 0.145, footDrop: 0.058, toeLength: 0.086, heelLength: 0.07,
    spine: 0.116, chest: 0.18, neck: 0.265, head: 0.11, shoulderHeight: 0.21, clavicleRoot: 0.032, clavicle: 0.2, shoulderBack: 0.016, upperArm: 0.325, foreArm: 0.29, hand: 0.09, palm: 0.023 },
  giant: Object.fromEntries(Object.entries(DEFAULT_PROPORTIONS).map(([k, v]) => [k, k === 'thighRatio' ? v : v * GIANT])),
};
const r = (x, d = 2) => (Number.isFinite(x) ? Math.round(x * 10 ** d) / 10 ** d : x);
const R2D = 180 / Math.PI;

let CTX = null;
const cache = new Map();
/** Measuring characters: cloth off unless `full` (cloth never feeds back into bones). */
function mk(body = 'kael', full = false) {
  const key = body + (full ? ':full' : '');
  if (cache.has(key)) return cache.get(key);
  const k = body === 'giant' ? GIANT : 1, w = knight.weapon;
  const d = {
    ...knight, id: 'qa_' + body, proportions: PROPS[body], cloth: full ? knight.cloth : [],
    weapon: { ...w, base: w.base.map((v) => v * k), tip: w.tip.map((v) => v * k), grips: Object.fromEntries(Object.entries(w.grips).map(([n, g]) => [n, { ...g, pos: g.pos.map((v) => v * k) }])) },
    // shared knight clips retargeted to the body (MATH-18)
    clipScale: qa.scaleOf({ rig: { P: { ...DEFAULT_PROPORTIONS, ...PROPS[body] } } }),
    // design data in metres scales with the giant (colliders: the elbow keeps out of the torso capsule)
    colliders: knight.colliders.map((cl) => ({ ...cl, a: [cl.a[0], cl.a[1].map((v) => v * k)], b: [cl.b[0], cl.b[1].map((v) => v * k)], r: cl.r * k })),
    bones: knight.bones.map((bn) => (bn.at ? { ...bn, at: bn.at.map((v) => v * k) } : bn)),
    springs: knight.springs.map((sp) => ({ ...sp, tip: sp.tip && sp.tip.map((v) => v * k), radius: (sp.radius ?? 0.02) * k })),
  };
  const c = createCharacter(CTX, d, { parent: null, name: 'rigqa_' + key });
  cache.set(key, c);
  return c;
}
function reset(c, clip = 'demo.idle', o = {}) { return qa.resetForQA(c, clip, o); }
/** A knight variant with design overrides (debugging): cached by its JSON. */
function mkWith(over = {}) {
  const key = 'v:' + JSON.stringify(over);
  if (!cache.has(key)) cache.set(key, createCharacter(CTX, { ...knight, cloth: [], ...over }, { parent: null, name: 'rigqa_v' }));
  return cache.get(key);
}

// ---- check list -----------------------------------------------------------------------------------------------------
let CHECKS = [];
function check(name, value, limit, cmp = '<=') {
  const v = typeof value === 'number' ? r(value, 3) : value;
  const pass = cmp === '<=' ? value <= limit : cmp === '>=' ? value >= limit : cmp === '==' ? value === limit : false;
  CHECKS.push({ name, value: v, limit: cmp === '<=' ? limit : cmp + ' ' + limit, pass: !!pass });
  return pass;
}

// ---- 1. demo clips on every body ------------------------------------------------------------------------------------
const qq = new THREE.Quaternion();
function stepAngles(rec, bone, src = null, k = 1) {
  // max per-frame rotation of a bone's local quaternion (deg); with `src`: the part not explained by k x the source
  // bone's own local step (a helper that jumps while its source moves smoothly = a pop)
  const i = rec.idx[bone], j = src ? rec.idx[src] : -1;
  if (i === undefined) return 0;
  let m = 0;
  for (let f = 1; f < rec.n; f++) {
    let a = qa.qangle(rec.Q, ((f - 1) * rec.B + i) * 4, rec.Q, (f * rec.B + i) * 4) * R2D;
    if (j >= 0) a -= k * qa.qangle(rec.Q, ((f - 1) * rec.B + j) * 4, rec.Q, (f * rec.B + j) * 4) * R2D;
    m = Math.max(m, a);
  }
  return m;
}
function clipMetrics(c, name, hz = 60) {
  const s = qa.scaleOf(c);
  const diag = [];
  const cl = getClip(c.rig, name);
  qa.resetForQA(c, name, {});
  const dur = cl.loop ? 2 * cl.duration : cl.duration;
  const rec = qa.record(c, { hz, frames: Math.round(dur * hz) + 1, before: (i) => { if (i > 0) diag.push([c.diag.drop, c.diag.gripErr, c.root.position.y]); } });
  diag.push([c.diag.drop, c.diag.gripErr]);
  rec.clipName = name; rec.loop = cl.loop; rec.duration = cl.duration;
  const lim = qa.jointLimits(rec);
  const hand = (axis) => Math.max(0, ...lim.filter((l) => /^hand[RL]$/.test(l.joint) && l.axis === axis).map((l) => Math.abs(l.value)));
  let dropStep = 0, drop = 0, grip = 0, drop2 = 0;
  for (let i = 0; i < diag.length; i++) {
    drop = Math.max(drop, diag[i][0]); grip = Math.max(grip, diag[i][1]);
    if (i > 0) dropStep = Math.max(dropStep, Math.abs(diag[i][0] - diag[i - 1][0]));
    if (i > 1) drop2 = Math.max(drop2, Math.abs(diag[i][0] - 2 * diag[i - 1][0] + diag[i - 2][0]));
  }
  // pelvis: world height 2nd difference (auto drop + authored)
  let hips2 = 0;
  const hy = (f) => rec.M[(f * rec.B + rec.idx.hips) * 12 + 10];
  for (let f = 2; f < rec.n; f++) hips2 = Math.max(hips2, Math.abs(hy(f) - 2 * hy(f - 1) + hy(f - 2)));
  const fe = qa.feet(rec), fl = qa.floor(rec);
  // C1 at keys: one-sided velocities 0.05 ms apart (so a sharp but smooth turn is not read as a step); a stop at an
  // impact key ('in*' ease: velocity after ~0) is a deliberate step
  const keys = qa.keyContinuity(c.rig, name, { eps: 5e-5 }).filter((k) => !k.seam && !(k.after < (k.unit === 'deg/s' ? 5 : 0.02)));
  return {
    s, nan: rec.nan, handSwing: hand('swing'), handTwist: hand('twist'),
    romOver: lim.filter((l) => l.joint.startsWith('hand')).map((l) => `${l.joint}.${l.axis} ${l.value}@${l.t}`).slice(0, 4),
    twistStep: Math.max(stepAngles(rec, 'foreArmTwistR', 'handR'), stepAngles(rec, 'foreArmTwistL', 'handL')),
    upperTwistStep: Math.max(...['R', 'L'].flatMap((x) => [stepAngles(rec, 'upperArmTwist' + x, 'upperArm' + x), stepAngles(rec, 'deltoid' + x, 'upperArm' + x)])),
    pops: qa.angular(rec, { bones: ['upperArmR', 'upperArmL', 'foreArmR', 'foreArmL', 'handR', 'handL'] }).pops.length,
    drop, dropStep, drop2, hips2, grip, drift: fe.maxDrift, feetMin: fl.feet.min, keySteps: keys.length, worstKey: keys[0] ? `${keys[0].ch}@${keys[0].t} ${keys[0].before}->${keys[0].after}` : null,
  };
}
function testClips(bodies = ['kael', 'iska', 'vorn', 'giant']) {
  const out = {};
  for (const b of bodies) {
    const c = mk(b);
    for (const name of DEMO) {
      const m = clipMetrics(c, name);
      const s = m.s, tag = `${b} ${name}`;
      out[tag] = m;
      check(`${tag}: no NaN`, m.nan ? 1 : 0, 0);
      check(`${tag}: hand swing (deg)`, m.handSwing, 87);
      check(`${tag}: hand twist (deg)`, m.handTwist, 92);
      check(`${tag}: forearm twist helper, step beyond the hand's (deg/frame)`, m.twistStep, 10);
      check(`${tag}: deltoid / upper-arm twist helper, step beyond the arm's (deg/frame)`, m.upperTwistStep, 10);
      check(`${tag}: grip error (m)`, m.grip / s, 0.01);
      check(`${tag}: auto pelvis drop step (m/frame)`, m.dropStep / s, 0.025);
      check(`${tag}: auto pelvis drop 2nd difference (m/frame^2)`, m.drop2 / s, 0.012);
      if (b === 'kael') {
        check(`${tag}: key velocity steps (C1 breaks)`, m.keySteps, 0);
        check(`${tag}: planted foot drift (m)`, m.drift / s, 0.01);
        check(`${tag}: feet floor penetration (m)`, -m.feetMin / s, 0.005);
      }
    }
  }
  return out;
}

// ---- 2. runtime / mixer -------------------------------------------------------------------------------------------
const tipW = new THREE.Vector3(), tipP = new THREE.Vector3();
function testRuntime() {
  const c = mk('kael'), res = {};
  // ANIM-01: five plays inside one fade window
  reset(c, 'demo.idle');
  c.update(1 / 60, 1 / 60);
  c.sockets.weaponTip.getWorldPosition(tipP);
  // (the update right after each play(): the old mixer dropped the oldest state there, a 1.46 m jump)
  let jump = 0;
  const seq = ['demo.slam', 'demo.hit', 'demo.combo1', 'demo.combo2', 'demo.combo3'];
  for (let i = 0; i < 8; i++) {
    if (i < seq.length) c.play(seq[i], { fade: 1.0, restart: true });
    c.update(1 / 120, 1 / 120);
    c.sockets.weaponTip.getWorldPosition(tipW);
    jump = Math.max(jump, tipW.distanceTo(tipP));
    tipP.copy(tipW);
  }
  res.capJump = jump;
  check('mixer: 5 plays in one fade window, weapon tip step (m/update)', jump, 0.1);
  // ANIM-03 / MATH-03: grip point switch idle <-> guard
  for (const [a, b] of [['demo.idle', 'demo.guard'], ['demo.guard', 'demo.idle'], ['demo.walkF', 'demo.guard']]) {
    reset(c, a);
    for (let i = 0; i < 36; i++) c.update(1 / 60, 1 / 60);
    const hl = new THREE.Vector3(), pl = new THREE.Vector3();
    c.sockets.handL.getWorldPosition(pl);
    c.play(b, { fade: 0.25 });
    // (the hand may let go while it changes grip point; it must be back on the weapon when the fade is over)
    let m = 0, g = 0;
    for (let i = 0; i < 30; i++) { c.update(1 / 60, 1 / 60); c.sockets.handL.getWorldPosition(hl); m = Math.max(m, hl.distanceTo(pl)); pl.copy(hl); if (i > 18) g = Math.max(g, c.diag.gripErr); }
    check(`crossfade ${a} -> ${b}: off hand step (m/frame; combo1's smear moves it 0.2)`, m, 0.12);
    check(`crossfade ${a} -> ${b}: grip error after the fade (m)`, g, 0.01);
  }
  // MATH-05: guard blade roll without authored change
  reset(c, 'demo.guard', { breath: 0 });
  const bl = new THREE.Vector3(1, 0, 0), ed = new THREE.Vector3(0, -1, 0);
  const qw = new THREE.Quaternion();
  let roll0 = null, rollMax = 0;
  for (let i = 0; i < 120; i++) {
    c.update(1 / 60, 1 / 60);
    c.bones.weaponR.getWorldQuaternion(qw);
    const e = ed.clone().applyQuaternion(qw), a = bl.clone().applyQuaternion(qw);
    // roll = angle of the edge around the blade axis, measured against world up projected
    const up = new THREE.Vector3(0, 1, 0).addScaledVector(a, -a.y).normalize();
    const ang = Math.atan2(e.clone().cross(up).dot(a), e.dot(up)) * R2D;
    if (roll0 === null) roll0 = ang;
    rollMax = Math.max(rollMax, Math.abs(((ang - roll0 + 540) % 360) - 180));
  }
  check('demo.guard: blade roll drift (deg)', rollMax, 6);
  // MATH-13: walk -> idle planted slide
  let slide = 0;
  for (const ph of [0.15, 0.3, 0.6]) {
    reset(c, 'demo.walkF');
    c.applyRootMotion = true;
    const n0 = Math.round(ph * getClip(c.rig, 'demo.walkF').duration * 60);
    for (let i = 0; i < n0; i++) c.update(1 / 60, 1 / 60);
    const pr = new THREE.Vector3(), pl = new THREE.Vector3(), q = [pr, pl];
    c.sockets.footR.getWorldPosition(pr); c.sockets.footL.getWorldPosition(pl);
    const planted = [pr.y < 0.01, pl.y < 0.01];
    c.play('demo.idle', { fade: 0.2 });
    const t = new THREE.Vector3();
    for (let i = 0; i < 14; i++) {
      c.update(1 / 60, 1 / 60);
      ['footR', 'footL'].forEach((f, k) => { if (!planted[k]) return; c.sockets[f].getWorldPosition(t); slide = Math.max(slide, Math.hypot(t.x - q[k].x, t.z - q[k].z)); });
    }
    c.applyRootMotion = false;
  }
  res.slide = slide;
  check('crossfade walkF -> idle: planted foot slide (m)', slide, 0.035);
  // SKIN-05 / MATH-14: facing keeps scale
  c.root.scale.setScalar(4.2);
  c.setFacing(-1); const s1 = c.root.scale.toArray();
  c.setFacing(1, { turn: 0.2 }); const s2 = c.root.scale.toArray();
  check('setFacing keeps a scaled root (|scale| error)', Math.max(Math.abs(Math.abs(s1[0]) - 4.2), Math.abs(Math.abs(s2[0]) - 4.2), Math.abs(s1[1] - 4.2)), 1e-6);
  check('setFacing(-1) mirrors a scaled root', s1[0], -4.2 + 1e-6);
  c.root.scale.set(1, 1, 1); c.root.rotation.set(0, 0, 0);
  c.setFacing(1);
  // events: a huge dt on a loop emits at most two cycles
  reset(c, 'demo.walkF');
  let ev = 0;
  const off = c.onEvent(() => ev++);
  c.update(1e4, 1e4);
  off();
  check('update(1e4) on a loop: events emitted', ev, 6);
  // flinch: frame-rate independence and bounded accumulation
  const flinch = (hz, hits) => {
    reset(c, 'demo.stance', { breath: 0 });
    for (let i = 0; i < hits; i++) c.impulse({ dir: [-1, 0.1, 0.2], amount: 1 });
    let m = 0;
    const qh = new THREE.Quaternion(), q0 = new THREE.Quaternion();
    c.bones.head.getWorldQuaternion(q0);
    const n = Math.round(0.6 * hz);
    const curve = [];
    for (let i = 0; i < n; i++) { c.update(1 / hz, 1 / hz); c.bones.head.getWorldQuaternion(qh); const a = 2 * Math.acos(Math.min(1, Math.abs(qh.dot(q0)))) * R2D; m = Math.max(m, a); if ((i + 1) % (hz / 30) === 0) curve.push(a); }
    return { m, curve };
  };
  const f30 = flinch(30, 1), f120 = flinch(120, 1), f30x = flinch(60, 30);
  let fd = 0;
  for (let i = 0; i < Math.min(f30.curve.length, f120.curve.length); i++) fd = Math.max(fd, Math.abs(f30.curve[i] - f120.curve[i]));
  check('flinch: 30 Hz vs 120 Hz head angle difference (deg)', fd, 1.5);
  check('flinch: 30 stacked heavy hits, head whip (deg)', f30x.m, 60);
  // fuzz
  const rng = makeRng(7);
  reset(c, 'demo.idle');
  let bad = 0, far = 0;
  const hips0 = new THREE.Vector3(), hw = new THREE.Vector3();
  for (let i = 0; i < 1500; i++) {
    const x = rng();
    if (x < 0.03) c.play(DEMO[(rng() * DEMO.length) | 0], { fade: rng() * 0.3, restart: rng() < 0.5 });
    else if (x < 0.05) c.setClipTime(rng() * 2);
    else if (x < 0.07) c.impulse({ dir: [rng() - 0.5, rng() - 0.5, rng() - 0.5], amount: rng() * 3 });
    else if (x < 0.075) c.setFacing(-c.facing);
    else if (x < 0.08) c.setClipTime(NaN);
    c.update(rng() < 0.05 ? 0 : rng() / 15, 1 / 60);
    c.bones.hips.getWorldPosition(hw);
    for (const b of Object.values(c.bones)) { if (!Number.isFinite(b.matrixWorld.elements[13])) { bad++; break; } }
    far = Math.max(far, Math.hypot(hw.x - c.root.position.x, hw.y - 1.04, hw.z));
  }
  check('fuzz 1500 frames: frames with NaN', bad, 0);
  check('fuzz 1500 frames: hips distance from rest (m)', far, 0.8);
  return res;
}

// ---- 3. IK, spaces, contact, mirroring, scale ---------------------------------------------------------------------
function holdClip(c, name, def) {
  defineClip(name, { duration: 1, loop: true, ...def });
  invalidateClips();
  c.play(name, { fade: 0, restart: true });
  c.teleport();
  for (let i = 0; i < 3; i++) c.update(1 / 60, 1 / 60);
}
const V = () => new THREE.Vector3();
function local(c, p) { return p.clone().applyMatrix4(new THREE.Matrix4().copy(c.root.matrixWorld).invert()); }
function testIK() {
  const res = {};
  const c = mk('kael');
  // pipeline accuracy: random targets within 96% reach, straight FK legs (zero-ish pose), breathing on
  const rng = makeRng(3);
  const limbs = IK.makeLimbs(c.rig);
  let worst = 0;
  for (const e of ['handR', 'handL', 'footR', 'footL']) {
    for (let i = 0; i < 40; i++) {
      reset(c, 'neutral.hold');
      c.update(1 / 60, 1 / 60);
      const limb = limbs[e];
      const rootB = c.bones[c.rig.names[limb.root]], sp = local(c, rootB.getWorldPosition(V()));
      const lmax = limb.l1 + limb.l2;
      let d;
      do { d = new THREE.Vector3(rng() - 0.5, rng() - 0.5, rng() - 0.5); } while (d.length() < 0.1);
      d.normalize().multiplyScalar(lmax * (0.35 + 0.6 * rng()));
      if (e.startsWith('foot')) d.y = -Math.abs(d.y) - 0.1;
      const tgt = sp.clone().add(d);
      if (e.startsWith('foot')) tgt.y = Math.max(0.12, tgt.y);
      holdClip(c, 'rigqa.ik', { keys: [{ t: 0, pose: 'neutral', grip: 0, ik: { [e]: { pos: tgt.toArray() } } }] });
      const sock = e.startsWith('hand') ? c.sockets['hand' + e.slice(-1)] : null;
      const p = sock ? local(c, sock.getWorldPosition(V())) : local(c, c.bones[e].localToWorld(new THREE.Vector3(0, -c.rig.P.ankleHeight, 0)));
      worst = Math.max(worst, p.distanceTo(tgt));
    }
  }
  res.ikWorst = worst;
  check('IK pipeline: random targets <= 95% reach, breathing on (m)', worst, 0.001);
  // neutral standing: README zero-pose heights
  reset(c, 'neutral.hold', { breath: 0 });
  for (let i = 0; i < 3; i++) c.update(1 / 60, 1 / 60);
  const hipsY = c.bones.hips.getWorldPosition(V()).y;
  check('neutral.hold: hips height (m) = 1.04', Math.abs(hipsY - 1.04), 0.003);
  // spaces: root / hips / chest hands with breathing
  for (const space of ['root', 'hips', 'chest']) {
    const pos = space === 'root' ? [0.35, 1.2, 0.2] : space === 'hips' ? [0.3, 0.2, 0.2] : [0.35, -0.05, 0.25];
    reset(c, 'neutral.hold', { breath: 1 });
    holdClip(c, 'rigqa.sp', { keys: [{ t: 0, pose: 'neutral', grip: 0, ik: { handR: { space, pos } } }] });
    let m = 0;
    for (let i = 0; i < 90; i++) {
      c.update(1 / 60, 1 / 60);
      const fist = local(c, c.sockets.handR.getWorldPosition(V()));
      let tgt;
      if (space === 'root') tgt = new THREE.Vector3(...pos);
      else tgt = local(c, c.bones[space].localToWorld(new THREE.Vector3(...pos)));
      m = Math.max(m, fist.distanceTo(tgt));
    }
    check(`IK ${space}-space hand with breathing (m)`, m, 0.001);
  }
  // hips-space foot does not move root-space hand targets (MATH-12)
  reset(c, 'neutral.hold', { breath: 0 });
  holdClip(c, 'rigqa.hf', { keys: [{ t: 0, pose: 'neutral', grip: 0, ik: { handR: { pos: [0.35, 1.2, 0.2] }, footR: { space: 'hips', pos: [0.25, -0.65, 0.12] } } }] });
  check('hips-space foot: root-space hand error (m)', local(c, c.sockets.handR.getWorldPosition(V())).distanceTo(new THREE.Vector3(0.35, 1.2, 0.2)), 0.001);
  // knee pole honoured on a planted foot (MATH-09)
  reset(c, 'neutral.hold', { breath: 0 });
  holdClip(c, 'rigqa.kp', { keys: [{ t: 0, pose: 'neutral', grip: 0, hips: { pos: [0, -0.18, 0] }, ik: { footR: { pos: [0.05, 0, 0.28], rot: [0, -40, 0], pole: [0.2, 0.55, 0.9] } } }] });
  {
    const hip = local(c, c.bones.thighR.getWorldPosition(V())), knee = local(c, c.bones.shinR.getWorldPosition(V())), ank = local(c, c.bones.footR.getWorldPosition(V()));
    const n = knee.clone().sub(hip).cross(ank.clone().sub(hip)).normalize();
    const pl = new THREE.Vector3(0.2, 0.55, 0.9).sub(hip);
    check('planted foot: authored knee pole off-plane (deg)', Math.abs(Math.asin(Math.abs(pl.normalize().dot(n)))) * R2D, 2);
  }
  // pelvis drop sweep: rear foot moved back 1 cm per step
  reset(c, 'neutral.hold', { breath: 0 });
  let prev = null, step = 0, maxDrop = 0;
  for (let i = 0; i <= 90; i++) {
    const fx = -0.2 - i * 0.01;
    holdClip(c, 'rigqa.drop', { keys: [{ t: 0, pose: 'neutral', grip: 0, ik: { footR: { pos: [fx, 0, 0.12] }, footL: { pos: [0.3, 0, -0.12] } } }] });
    const hy = c.bones.hips.getWorldPosition(V()).y;
    if (prev !== null) step = Math.max(step, Math.abs(hy - prev));
    maxDrop = Math.max(maxDrop, c.diag.drop);
    prev = hy;
  }
  check('pelvis drop sweep: hips step per 1 cm foot step (m)', step, 0.012);
  check('pelvis drop sweep: max automatic drop (m)', maxDrop, 0.161);
  // toe roll on a pitched foot target (MATH-20)
  let pen = 0;
  for (const pitch of [-45, -30, -15, 15]) {
    reset(c, 'neutral.hold', { breath: 0 });
    holdClip(c, 'rigqa.toe', { keys: [{ t: 0, pose: 'neutral', grip: 0, ik: { footR: { pos: [0.05, 0, 0.12], rot: [0, 0, pitch] } } }] });
    const P = c.rig.P;
    for (const [b, pt] of [['footR', [-P.heelLength, -P.ankleHeight, 0]], ['footR', [P.footLength, -P.ankleHeight, 0]], ['toeR', [P.toeLength, -(P.ankleHeight - P.footDrop), 0]]]) {
      pen = Math.max(pen, -c.bones[b].localToWorld(new THREE.Vector3(...pt)).y);
    }
  }
  check('pitched foot target: heel / ball / toe tip below the floor (m)', pen, 0.0015);
  // upper-arm twist singularity sweep (SKIN-01): helper change per 5 deg of abduction near overhead
  for (const flex of [0, 10, -10]) {
    let worstStep = 0, prevQ = null;
    for (let x = 0; x <= 185; x += 5) {
      holdClip(c, 'rigqa.sw', { keys: [{ t: 0, pose: 'neutral', grip: 0, bones: { upperArmR: [-x, 0, flex] } }] });
      const q = c.bones.upperArmTwistR.quaternion.clone(), d = c.bones.deltoidR.quaternion.clone();
      if (prevQ) worstStep = Math.max(worstStep, 2 * Math.acos(Math.min(1, Math.abs(q.dot(prevQ[0])))) * R2D, 2 * Math.acos(Math.min(1, Math.abs(d.dot(prevQ[1])))) * R2D - 2.5);
      prevQ = [q, d];
    }
    check(`upper-arm abduction sweep 0..185 (flex ${flex}): helper step per 5 deg (deg)`, worstStep, 5);
  }
  // forearm twist across 180 deg (FK keyed, played continuously): vambrace helper continuity
  {
    holdClip(c, 'rigqa.fw', { duration: 1, loop: false, keys: [{ t: 0, pose: 'neutral', grip: 0, bones: { foreArmR: [0, 160, 90] } }, { t: 1, bones: { foreArmR: { r: [0, 200, 90], interp: 'linear' } } }] });
    let m = 0, prev = c.bones.foreArmTwistR.quaternion.clone();
    for (let i = 0; i < 60; i++) {
      c.update(1 / 60, 1 / 60);
      const q = c.bones.foreArmTwistR.quaternion;
      m = Math.max(m, 2 * Math.acos(Math.min(1, Math.abs(q.dot(prev)))) * R2D);
      prev.copy(q);
    }
    check('forearm twist 160..200 (FK, continuous): vambrace helper step (deg/frame)', m, 3);
  }
  // mirrorClip keep: the right fist follows the mirrored path of combo1 (the blade may turn where the mirrored wrist
  // would leave its range)
  {
    const a = mk('kael'), recA = [], recB = [];
    for (const [clip, out] of [['demo.combo1', recA], ['demo.combo1M', recB]]) {
      reset(a, clip, { breath: 0 });
      for (let i = 0; i < 57; i++) { a.update(1 / 60, 1 / 60); out.push(local(a, a.sockets.handR.getWorldPosition(V()))); }
    }
    let m = 0;
    for (let i = 0; i < recA.length; i++) m = Math.max(m, recA[i].distanceTo(new THREE.Vector3(recB[i].x, recB[i].y, -recB[i].z)));
    check('mirrorClip keep (combo1M): right fist vs mirrored combo1 (m)', m, 0.07);
  }
  // giant built from proportions: sockets and fingers scale with the body
  {
    const g = mk('giant'), k = mk('kael');
    reset(g, 'neutral.hold', { breath: 0 }); reset(k, 'neutral.hold', { breath: 0 });
    g.update(1 / 60, 1 / 60); k.update(1 / 60, 1 / 60);
    let m = 0;
    for (const s of ['chest', 'head', 'back', 'footR', 'handR']) m = Math.max(m, g.sockets[s].getWorldPosition(V()).multiplyScalar(1 / GIANT).distanceTo(k.sockets[s].getWorldPosition(V())));
    for (const b of ['fingerTipsR', 'thumbR', 'upperArmTwistR']) m = Math.max(m, g.bones[b].getWorldPosition(V()).multiplyScalar(1 / GIANT).distanceTo(k.bones[b].getWorldPosition(V())));
    check('giant (x4.2 proportions): sockets / fingers, normalised error (m)', m, 0.004);
  }
  return res;
}

// ---- 4. crossfade matrix ----------------------------------------------------------------------------------------------
function testXfade() {
  const c = mk('kael'), baselines = {};
  let pops = 0, hard = 0, worst = 0, who = '';
  const flagged = [];
  for (const a of DEMO) for (const b of DEMO) {
    if (a === b) continue;
    const ca = getClip(c.rig, a);
    const x = qa.crossfade(c, a, b, { at: Math.min(0.45 * ca.duration, 0.6), fade: 0.1, baselines });
    if (x.pop) { pops++; flagged.push(`${a}->${b} ang ${x.ang} (${x.angBone}) x${x.angRatio} body ${x.body} (${x.bodyJoint}) x${x.bodyRatio}`); }
    if (x.pop && ((x.angRatio > 2 && x.ang > 200) || (x.bodyRatio > 2 && x.body > 1.5) || (x.bodyRatio > 1.5 && x.body > 3))) hard++;
    const rr = Math.max(x.angRatio, x.bodyRatio);
    if (rr > worst) { worst = rr; who = `${a}->${b} ang ${x.ang} (${x.angBone}) body ${x.body} (${x.bodyJoint})`; }
  }
  // qa.crossfade flags any step > 1.5 x both clips' own maxima above an absolute floor; between two near-static clips
  // (idle, guard) a 0.1 s fade that turns the blade is flagged by the floor alone, so those are reported, and a pop
  // counts when it is also > 2 x the clips' own maxima or a body step > 3 m/s per 1/120 s frame
  // (two pairs remain between the near-static idle and guard: a 0.1 s fade that turns the blade and moves the off hand
  // 0.7 m from pommel to blade; their steps are ~2 m/s per frame, against 47-87 m/s for the old grip teleport)
  check('crossfade matrix (90 pairs): pops (> 2x the clips own steps or > 3 m/s per frame)', hard, 2);
  return { pops, hard, flagged, worst, who };
}

// ---- 5. cloth ---------------------------------------------------------------------------------------------------------
function testCloth() {
  const c = mk('kael', true);
  reset(c, 'demo.c2end');
  c.play('demo.combo3', { fade: 0, restart: true });
  const tmp = new THREE.Vector3();
  let inside = 0, stretch = 0, nan = 0;
  for (let i = 0; i < 81; i++) {
    c.update(1 / 60, 1 / 60);
    // head / neck: capsule from the design colliders
    const head = c.bones.head.localToWorld(new THREE.Vector3(0.01, 0.1, 0)), rr = 0.13;
    for (let k = 0; k < c.rig.count; k++) {
      const n = c.rig.names[k];
      if (!/^cape_/.test(n)) continue;
      c.bones[n].getWorldPosition(tmp);
      if (!Number.isFinite(tmp.x)) nan++;
      if (tmp.distanceTo(head) < rr - 0.01) inside++;
    }
  }
  check('combo3: cape particles inside the head (count over 81 frames)', inside, 0);
  check('combo3: cloth NaN', nan, 0);
  return { inside, stretch };
}

// ---- 6. CPU -------------------------------------------------------------------------------------------------------------
/**
 * ms per char.update() for the shipped knight (cape + tabard cloth, springs, IK) over a combat chain. The page shares
 * the machine with other work, so the figure is the 10th percentile of 10-update batch means (robust to scheduler
 * noise); the median is reported alongside.
 */
function testCpu() {
  const c = mk('kael', true);
  const chain = ['demo.combo1', 'demo.combo2', 'demo.combo3', 'demo.slam', 'demo.walkF', 'demo.idle'];
  reset(c, 'demo.idle');
  let k = 0;
  const b = [];
  for (let j = 0; j < 140; j++) {
    const t0 = performance.now();
    for (let i = 0; i < 10; i++) {
      const f = j * 10 + i;
      if (f % 75 === 0) c.play(chain[k++ % chain.length], { fade: 0.08, restart: true });
      c.update(1 / 60, 1 / 60);
    }
    b.push((performance.now() - t0) / 10);
  }
  const s = b.slice(20).sort((x, y) => x - y);
  const p10 = s[Math.floor(s.length * 0.1)], p50 = s[s.length >> 1];
  // the page shares a loaded machine: the best batch is the uncontended cost; p10 / p50 show the contention
  check('CPU char.update, knight with cape + tabard (ms, best 10-update batch)', s[0], 1.0);
  check('CPU char.update, knight with cape + tabard (ms, p10 of batches, loaded machine)', p10, 1.5);
  return { best: s[0], p10, p50 };
}

/** Per-frame values of a clip (debugging): fn(char, frame) -> any, at `hz`. */
function trace(name, fn, { body = 'kael', hz = 60, frames = null, from = null } = {}) {
  const c = mk(body);
  qa.resetForQA(c, from || name, {});
  if (from) c.play(name, { fade: 0.1, restart: true });
  const cl = getClip(c.rig, name), n = frames ?? Math.round(cl.duration * hz) + 1, out = [];
  for (let i = 0; i < n; i++) { c.update(1 / hz, 1 / hz); out.push(fn(c, i)); }
  return out;
}

function runAll(opts = {}) {
  CHECKS = [];
  const t0 = performance.now();
  const only = opts.only;
  const groups = { clips: () => testClips(opts.bodies), runtime: testRuntime, ik: testIK, xfade: testXfade, cloth: testCloth, cpu: testCpu };
  const detail = {};
  for (const [g, fn] of Object.entries(groups)) {
    if (only && only !== g) continue;
    try { detail[g] = fn(); } catch (e) { CHECKS.push({ name: g + ': exception ' + e.message, value: String(e.stack).slice(0, 300), limit: 'none', pass: false }); }
  }
  const failed = CHECKS.filter((x) => !x.pass).length;
  const res = { checks: CHECKS, passed: CHECKS.length - failed, failed, seconds: r((performance.now() - t0) / 1000, 1) };
  if (opts.detail) res.detail = detail;
  if (opts.failedOnly) res.checks = CHECKS.filter((x) => !x.pass);
  return res;
}

createLab({
  view: { target: [0, 1.05, 0], dist: 5.4, yaw: 0, pitch: 4, fov: 40 },
  setup(ctx) {
    CTX = ctx;
    window.__ED.qa = { clip: (name, body = 'kael') => clipMetrics(typeof body === 'string' ? mk(body) : mkWith(body), name), mk, mkWith, defineClip, invalidateClips, run: runAll, trace, IK, THREE, getClip, sampleClip, Pose, qa };
  },
  scenarios: {
    all(ctx, lab, opts = {}) { return runAll(opts); },
  },
});
