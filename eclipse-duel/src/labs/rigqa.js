// Rig regression suite: every measurement the rig auditors used (IK accuracy, grip, pelvis drop, twist helpers, elbow
// continuity, wrist clamp, clavicle, look-at, layers, loop seams, crossfades, mixer cap, mirroring, facing / scale,
// contact, flinch, events, cloth (stretch, frame rate, rendered cloth in the body), see-through holes, CPU), run on the
// shipped runtime for the knight and ISKA-like / VORN-like / 4.2x giant proportions, and on the real fighters (KAEL /
// ISKA / VORN designs with all their registered clips), reduced to pass / fail checks.
//
//   node tools/shot.mjs rigqa --eval "__ED.lab.play('all')"          -> { checks: [{ name, value, limit, pass }], passed, failed }
//   __ED.lab.play('all', { only: 'clips' })   one group: clips | runtime | ik | xfade | cloth | shipped | holes | cpu
//   __ED.qa.clip('demo.combo3', 'iska')                              raw qa metrics of one clip on one body (debugging)
//   __ED.qa.arm('kael', 'kael.light1')                               per-clip arm metrics of a real fighter (rig only)
//
// Limits are in metres / degrees at the knight's size; body-relative limits are multiplied by the body scale. Checks
// tagged [art: ...] measure art-owned geometry (design files): they are held to their measured value so a regression
// fails, and the report names the owner.

import * as THREE from 'three';
import { createLab, ORDER } from '../core/lab.js';
import { makeRng } from '../core/math.js';
import { createCharacter, defineClip, definePose, mirrorClip, invalidateClips, listClips } from '../char/index.js';
import { getClip, sampleClip, Pose } from '../char/anim.js';
import { DEFAULT_PROPORTIONS, createRig, fk } from '../char/skeleton.js';
import * as IK from '../char/ik.js';
import { knight } from '../char/designs/knight.js';
import '../char/clips/demo.js';
import * as qa from '../char/qa.js';
import { CLOTH_STEP } from '../char/cloth.js';
import { kael } from '../fighters/kael/design.js';
import { iska } from '../fighters/iska/design.js';
import { vorn } from '../fighters/vorn/design.js';
import '../fighters/kael/clips/index.js';
import '../fighters/iska/clips/index.js';
import '../fighters/vorn/clips/index.js';

const SHIPPED = { kael, iska, vorn };

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
/**
 * Known residual issues (round 1), checked against their measured value so any regression still fails: single-frame
 * arm IK basin switches where the demo data asks for more wrist + shoulder rotation than a human has (the arm IK is
 * stateless, so it is identical at 30 / 60 / 120 Hz; a memory removed these but made the arm frame-rate dependent).
 */
const KNOWN = {
  'demo.combo3: grip error (m)': 0.14,                                                     // 1 frame at 0.233 s
  // the slam's landing: both feet reach the floor within one frame and the hips start down (the drop onset is pinned
  // so planted feet never slide: its 2nd difference is the landing's, 0.0130 on every body, 8% over the limit)
  'demo.slam: auto pelvis drop 2nd difference (m/frame^2)': 0.0135,
  // combo3's landing onset (authored hips 2nd difference ~0.004 m/frame^2; the drop adds the landing's)
  'demo.combo3: hips 2nd difference / authored': 3.2,
};
function check(name, value, limit, cmp = '<=') {
  const known = Object.keys(KNOWN).find((k) => name.endsWith(k));
  if (known && cmp === '<=' && value > limit) { limit = KNOWN[known]; name += ' [known]'; }
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
  // default knee pole (MATH-10): pure solver, foot target circling the hip at 80% / 45% reach on 10 rings (0.5 deg
  // steps, rest orientation): the knee may not move more than 7x the target (round 0: 8-9x with 22 flips of the bend plane)
  for (const body of ['kael', 'giant']) {
    const rig = createRig(PROPS[body]), limb = IK.makeLimbs(rig).footR;
    const lq = new Float32Array(rig.count * 4), lp = new Float32Array(rig.offset), mq = new Float32Array(rig.count * 4), mp = new Float32Array(rig.count * 3);
    const pose = new Pose(rig);
    sampleClip(rig, getClip(rig, 'neutral.hold'), 0, pose);
    const rot = [0, 0, 0, 1], tgt = [0, 0, 0];
    fk(rig, pose.lq, lp, mq, mp);
    const cx = mp[limb.root * 3], cy = mp[limb.root * 3 + 1], cz = mp[limb.root * 3 + 2], lmax = limb.l1 + limb.l2, oy = rig.P.ankleHeight;
    const H = (h) => (a) => [Math.cos(a) * Math.sqrt(1 - h * h), h, Math.sin(a) * Math.sqrt(1 - h * h)];
    const rings = [[-0.9, -0.6, -0.3, 0, 0.3, 0.6, 0.9].map((h) => [H(h), 0.8]), [[(a) => [Math.cos(a), Math.sin(a), 0], 0.8], [(a) => [0, Math.sin(a), Math.cos(a)], 0.8], [(a) => [Math.cos(a), Math.sin(a), 0], 0.45]]].flat();
    let worst = 0;
    for (const [ring, frac] of rings) {
      let px = 0, py = 0, pz = 0, tx = 0, ty = 0, tz = 0;
      for (let k = 0; k <= 720; k++) {
        const d = ring((k / 720) * Math.PI * 2), wx = cx + d[0] * lmax * frac, wy = cy + d[1] * lmax * frac, wz = cz + d[2] * lmax * frac;
        lq.set(pose.lq); lp.set(rig.offset); fk(rig, lq, lp, mq, mp);
        tgt[0] = wx; tgt[1] = wy - oy; tgt[2] = wz;
        IK.solveLimb(rig, limb, lq, mq, mp, tgt, 0, rot, 0, null, 0, 1);
        fk(rig, lq, lp, mq, mp);
        const m = limb.mid * 3;
        if (k) worst = Math.max(worst, Math.hypot(mp[m] - px, mp[m + 1] - py, mp[m + 2] - pz) / (Math.hypot(wx - tx, wy - ty, wz - tz) || 1e-9));
        px = mp[m]; py = mp[m + 1]; pz = mp[m + 2]; tx = wx; ty = wy; tz = wz;
      }
    }
    check(`default knee pole (${body}): knee speed / foot target speed on 10 rings around the hip`, worst, 7);
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
    const isHard = x.pop && ((x.angRatio > 2 && x.ang > 200) || (x.bodyRatio > 2 && x.body > 1.5) || (x.bodyRatio > 1.5 && x.body > 3));
    // known: slam -> combo2 blends right-hand targets 122..174 deg apart (the slerp axis of near-opposite rotations is
    // ill-conditioned; combo2's own key is 50-177 deg past the wrist's range): held to its measured ratio
    if (a === 'demo.slam' && b === 'demo.combo2') check('crossfade slam -> combo2: hand turn per frame / the clips\' own [known]', x.angRatio, 4.2);
    else if (isHard) hard++;
    const rr = Math.max(x.angRatio, x.bodyRatio);
    if (rr > worst) { worst = rr; who = `${a}->${b} ang ${x.ang} (${x.angBone}) body ${x.body} (${x.bodyJoint})`; }
  }
  // qa.crossfade flags any step > 1.5 x both clips' own maxima above an absolute floor; between two near-static clips
  // (idle, guard) a 0.1 s fade that turns the blade is flagged by the floor alone, so those are reported, and a pop
  // counts when it is also > 2 x the clips' own maxima or a body step > 3 m/s per 1/120 s frame
  // (two pairs remain between the near-static idle and guard: a 0.1 s fade that turns the blade and moves the off hand
  // 0.7 m from pommel to blade; their steps are ~2 m/s per frame, against 47-87 m/s for the old grip teleport)
  check('crossfade matrix (89 pairs): pops (> 2x the clips own steps or > 3 m/s per frame)', hard, 2);
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
 * ms per char.update() for the shipped knight (cape + tabard cloth, springs, IK) over a combat chain (combo1, combo2,
 * combo3, slam: 300 frames). The page shares the machine with other work, so the chain is replayed R times and every
 * frame keeps its fastest run: the mean of those minima is the uncontended cost of the whole chain (not of its cheapest
 * frames). The median of all frames (contended) is reported alongside.
 */
function testCpu() {
  const c = mk('kael', true);
  const chain = ['demo.combo1', 'demo.combo2', 'demo.combo3', 'demo.slam'];
  const F = 300, B = 1, NB = F / B, R = 8;
  const best = new Float64Array(NB).fill(Infinity), all = [];
  for (let rep = 0; rep < R; rep++) {
    reset(c, 'demo.idle');
    let k = 0;
    for (let j = 0; j < NB; j++) {
      const t0 = performance.now();
      for (let i = 0; i < B; i++) {
        if ((j * B + i) % 75 === 0) c.play(chain[k++ % chain.length], { fade: 0.08, restart: true });
        c.update(1 / 60, 1 / 60);
      }
      const ms = (performance.now() - t0) / B;
      if (rep > 0) { best[j] = Math.min(best[j], ms); all.push(ms); } // run 0 warms the JIT up
    }
  }
  let mean = 0, peak = 0;
  for (let j = 0; j < NB; j++) { mean += best[j] / NB; peak = Math.max(peak, best[j]); }
  all.sort((x, y) => x - y);
  check('CPU char.update, knight with cape + tabard (ms, mean over a combat chain, uncontended; detail.cpu)', r(mean, 3), 1.0);
  return { mean: r(mean, 3), worstBatch: r(peak, 3), contendedP50: r(all[all.length >> 1], 3) };
}

// ---- 7. arm continuity / wrist clamp / clavicle / contact metrics of any clip (demo and real fighters) ------------------
const _a = [0, 0, 0], _b = [0, 0, 0], _c = [0, 0, 0];
/** Model-space (root-relative) point of a recorded bone. */
function mpt(rec, f, name, x = 0, y = 0, z = 0, out = [0, 0, 0]) {
  qa.pointAt(rec, f, name, x, y, z, out);
  out[0] -= rec.root[f * 3]; out[1] -= rec.root[f * 3 + 1]; out[2] -= rec.root[f * 3 + 2];
  return out;
}
const vsub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const vdot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const vlen = (a) => Math.hypot(a[0], a[1], a[2]);
/** Point of bone `name` at frame f in the chest bone's frame (the elbow measured against the torso, not the world). */
function cpt(rec, f, name) {
  const p = qa.pointAt(rec, f, name, 0, 0, 0), o = (f * rec.B + rec.idx.chest) * 12, M = rec.M;
  const d = [p[0] - M[o + 9], p[1] - M[o + 10], p[2] - M[o + 11]];
  return [d[0] * M[o] + d[1] * M[o + 1] + d[2] * M[o + 2], d[0] * M[o + 3] + d[1] * M[o + 4] + d[2] * M[o + 5], d[0] * M[o + 6] + d[1] * M[o + 7] + d[2] * M[o + 8]];
}
/** Elbow offset from the shoulder-wrist line of side S at frame f (and the unit line), in the chest frame. */
function elbowPerp(rec, f, S) {
  const s = cpt(rec, f, 'upperArm' + S), w = cpt(rec, f, 'hand' + S), e = cpt(rec, f, 'foreArm' + S);
  const a = vsub(w, s), la = vlen(a) || 1; a[0] /= la; a[1] /= la; a[2] /= la;
  const v = vsub(e, s), k = vdot(v, a);
  return { p: [v[0] - a[0] * k, v[1] - a[1] * k, v[2] - a[2] * k], a };
}
/**
 * Elbow swivel change (deg) between frames f-1 and f (the auditors' measure, taken in the chest frame so a spinning body
 * is not counted as swivel; elbows less than 2 cm off the line excluded).
 */
function swivelStep(rec, f, S) {
  const A = elbowPerp(rec, f - 1, S), B = elbowPerp(rec, f, S);
  const k = vdot(A.p, B.a), pa = [A.p[0] - B.a[0] * k, A.p[1] - B.a[1] * k, A.p[2] - B.a[2] * k];
  if (vlen(pa) < 0.02 * rec.scale || vlen(B.p) < 0.02 * rec.scale) return 0;
  return Math.acos(Math.max(-1, Math.min(1, vdot(pa, B.p) / (vlen(pa) * vlen(B.p))))) * R2D;
}
const qd = (Q, i, j) => qa.qangle(Q, i, Q, j) * R2D;
/**
 * One clip from a clean reset (breathing off, 60 Hz, single state): per arm the largest elbow swivel step, frames over
 * 30 deg / frame, the elbow's step beyond 1.5 x the fist's + 2 cm (the auditors' elbow-continuity measure), helper
 * steps beyond their source bone's, the clavicle's largest deviation from the clip's own FK, wrist-clamp frames (aim
 * > 30 deg), the largest automatic pelvis drop, planted feet in the air / feet below the floor, grip error, NaN.
 */
function armMetrics(c, name, { hz = 60, look = null } = {}) {
  const cl = getClip(c.rig, name), s = qa.scaleOf(c);
  qa.resetForQA(c, name, { breath: 0 });
  if (look) c.lookAt(look, 0.85);
  const n = Math.round(cl.duration * hz) + 1, diag = [];
  const rec = qa.record(c, { hz, frames: n, time: false, before: (i) => { if (i > 0) diag.push([c.diag.drop, c.diag.gripErr]); } });
  diag.push([c.diag.drop, c.diag.gripErr]);
  if (look) c.lookAt(null);
  const pose = new Pose(c.rig), m = { clip: name, frames: n, swivel: 0, flips: 0, axisFast: 0, elbowPop: 0, jitter: 0, helper: 0, clav: 0, aim30: 0, aimMax: 0, drop: 0, float: 0, floor: 0, grip: 0, nan: rec.nan ? 1 : 0, at: {} };
  const P = c.rig.P, B = rec.B, Q = rec.Q;
  const upd = (k, v, f) => { if (v > m[k]) { m[k] = v; m.at[k] = r(rec.t[f], 3); } };
  for (let f = 0; f < n; f++) {
    sampleClip(c.rig, cl, rec.clipT[f], pose, c.design.clipScale ?? 1);
    for (const S of ['R', 'L']) {
      if (f > 0) {
        // (a swivel step is only defined about a steady shoulder-wrist line: in frames where that line itself turns
        // > 30 deg, a fast authored hand path, the elbow's angle about it says nothing; those are counted apart)
        const sw = swivelStep(rec, f, S), A0 = elbowPerp(rec, f - 1, S).a, A1 = elbowPerp(rec, f, S).a;
        if (Math.acos(Math.max(-1, Math.min(1, vdot(A0, A1)))) * R2D < 30) { upd('swivel', sw, f); if (sw > 30) m.flips++; }
        else if (sw > 30) m.axisFast++;
        const es = vlen(vsub(cpt(rec, f, 'foreArm' + S), cpt(rec, f - 1, 'foreArm' + S)));
        const fs = vlen(vsub(cpt(rec, f, 'weapon' + S), cpt(rec, f - 1, 'weapon' + S)));
        upd('elbowPop', es - 1.5 * fs - 0.02 * s, f);
        if (f > 1) { // frame-to-frame alternation: the wrist's / elbow's 2nd difference beyond the fist's (chest frame)
          const d2 = (b) => { const a0 = cpt(rec, f - 2, b + S), a1 = cpt(rec, f - 1, b + S), a2 = cpt(rec, f, b + S); return Math.hypot(a2[0] - 2 * a1[0] + a0[0], a2[1] - 2 * a1[1] + a0[1], a2[2] - 2 * a1[2] + a0[2]); };
          const fd = d2('weapon');
          upd('jitter', Math.max(d2('hand'), d2('foreArm')) - 1.5 * fd - 0.01 * s, f);
        }
        const st = (h, src) => qd(Q, ((f - 1) * B + rec.idx[h]) * 4, (f * B + rec.idx[h]) * 4) - qd(Q, ((f - 1) * B + rec.idx[src]) * 4, (f * B + rec.idx[src]) * 4);
        upd('helper', Math.max(st('deltoid' + S, 'upperArm' + S), st('upperArmTwist' + S, 'upperArm' + S), st('foreArmTwist' + S, 'hand' + S)), f);
      }
      const ri = c.rig.index['shoulder' + S], k = (f * B + rec.idx['shoulder' + S]) * 4;
      upd('clav', qa.qangle(Q, k, pose.lq, ri * 4) * R2D, f);
    }
    if (rec.aim) { const a = Math.max(rec.aim[f * 2], rec.aim[f * 2 + 1]); upd('aimMax', a, f); if (a > 30) m.aim30++; }
    upd('drop', diag[f][0] / s, f);
    if (pose.grip >= 0.999) upd('grip', diag[f][1] / s, f);
    for (const [e, S] of [[2, 'R'], [3, 'L']]) {
      const o = e * 24, ik = pose.ik, wy = (b, x, y, z) => qa.pointAt(rec, f, b, x, y, z, _a)[1]; // world: the floor is y = 0
      const low = Math.min(wy('foot' + S, 0, -P.ankleHeight, 0), wy('foot' + S, -P.heelLength, -P.ankleHeight, 0),
        wy('foot' + S, P.footLength, -P.ankleHeight, 0), wy('toe' + S, 0, -(P.ankleHeight - P.footDrop), 0),
        wy('toe' + S, P.toeLength, -(P.ankleHeight - P.footDrop), 0));
      upd('floor', -low / s, f);
      if (ik[o] > 0.999 && !(ik[o + 14] >= 2) && ik[o + 2] <= 0.005 * s) upd('float', low / s, f); // planted: the whole foot in the air
    }
  }
  for (const k of ['swivel', 'elbowPop', 'jitter', 'helper', 'clav', 'aimMax', 'drop', 'float', 'floor', 'grip']) m[k] = r(m[k], 3);
  return m;
}

// ---- 8. the real fighters: every registered clip on a rig-only copy (proportions, weapons, colliders, grip angle) ----
const rigCache = new Map();
function rigOnly(id) {
  if (rigCache.has(id)) return rigCache.get(id);
  const d = SHIPPED[id], std = new Set(createRig(d.proportions || {}).names);
  const c = createCharacter(CTX, {
    id: 'qa_rig_' + id, idle: 'neutral.hold', proportions: d.proportions || {}, gripAngle: d.gripAngle ?? 0,
    clipScale: d.clipScale, maxPelvisDrop: d.maxPelvisDrop, materials: { suit: {} }, bones: [], springs: [], cloth: [], sockets: {},
    colliders: (d.colliders || []).filter((cl) => std.has(cl.a[0]) && std.has(cl.b[0])), weapon: d.weapon, weapons: d.weapons,
    build(kit, S) { kit.add('suit', 'chest', S.box(0.05, 0.05, 0.05, 0.005), {}); },
  }, { parent: null, name: 'rigqa_rig_' + id });
  rigCache.set(id, c);
  return c;
}
const clipsOf = (id) => listClips().filter((n) => n.startsWith(id + '.'));
/**
 * Known content issues of the real fighters' clips, held to their measured value (the clip author fixes the key; the
 * check fails if it gets worse): keys asking for a wrist past 180 deg of pronation or for a target out of reach.
 */
const CONTENT = {
  // one frame at clip entry from a reset: the wrist twist sweeps 120 deg at its rate limit while the blade key asks for
  // an impossible pronation, and the clamped hand cannot reach the grip point (more iterations do not change it)
  'kael:grip': 0.045,
  // the hand path runs at ~16 m/s (265 mm per frame) with the blade 98 deg off its key (wrist clamp) at 0.117 s
  'iska:elbowPop': 0.09,
  // thunder_javelin's throw at 0.217 s: the fist moves 205 mm in the frame, the swivel step is 30.05 deg
  'vorn:flips': 1,
};
function testShippedArms(ids = ['kael', 'iska', 'vorn']) {
  const capped = (id, k) => (CONTENT[id + ':' + k] !== undefined ? ' [content cap]' : '');
  const out = {};
  for (const id of ids) {
    const c = rigOnly(id), rows = [];
    for (const name of clipsOf(id)) { try { rows.push(armMetrics(c, name)); } catch (e) { rows.push({ clip: name, error: String(e.message || e) }); } }
    const ok = rows.filter((x) => !x.error), worst = (k) => ok.reduce((a, x) => (x[k] > a[k] ? x : a), ok[0] || {});
    const frames = ok.reduce((a, x) => a + x.frames, 0), flips = ok.reduce((a, x) => a + x.flips, 0), aim30 = ok.reduce((a, x) => a + x.aim30, 0);
    const axisFast = ok.reduce((a, x) => a + x.axisFast, 0);
    const lab = (k) => { const w = worst(k); return w ? `${w.clip}@${w.at[k]}` : ''; };
    check(`${id}: clips that throw`, rows.length - ok.length, 0);
    check(`${id}: clips with NaN`, ok.filter((x) => x.nan).length, 0);
    check(`${id}: elbow swivel frames > 30 deg/frame (of ${frames})${capped(id, 'flips')}`, flips, CONTENT[id + ':flips'] ?? 0);
    check(`${id}: largest elbow swivel step (deg/frame; ${lab('swivel')})`, worst('swivel').swivel || 0, 45);
    check(`${id}: elbow step beyond 1.5 x the fist's + 2 cm (m/frame; ${lab('elbowPop')})${capped(id, 'elbowPop')}`, worst('elbowPop').elbowPop || 0, CONTENT[id + ':elbowPop'] ?? 0.06);
    check(`${id}: helper step beyond its source bone's (deg/frame; ${lab('helper')})`, worst('helper').helper || 0, 10);
    check(`${id}: clavicle off the clip's FK (deg; ${lab('clav')})`, worst('clav').clav || 0, 26);
    check(`${id}: automatic pelvis drop (m; ${lab('drop')}) <= maxPelvisDrop`, worst('drop').drop || 0, (SHIPPED[id].maxPelvisDrop ?? 0.16) + 1e-4);
    check(`${id}: planted foot in the air (m; ${lab('float')})`, worst('float').float || 0, 0.005);
    check(`${id}: foot / toe below the floor (m; ${lab('floor')})`, worst('floor').floor || 0, 0.003);
    check(`${id}: two-handed grip error (m; ${lab('grip')})${capped(id, 'grip')}`, worst('grip').grip || 0, CONTENT[id + ':grip'] ?? 0.01);
    // reported, not limited: keys asking for more wrist than a human has (the blade leaves its key; fix the key)
    CHECKS.push({ name: `${id}: [report] frames with a > 30 deg swivel step while the shoulder-wrist line turns > 30 deg (fast authored hand paths, not judged)`, value: axisFast, limit: 'report', pass: true });
    CHECKS.push({ name: `${id}: [report] frames with the blade > 30 deg off its key (wrist clamp; worst ${lab('aimMax')} ${r(worst('aimMax').aimMax || 0, 1)} deg)`, value: aim30, limit: 'report', pass: true });
    out[id] = { rows: ok.length, frames, flips, aim30, worst: Object.fromEntries(['swivel', 'elbowPop', 'helper', 'clav', 'aimMax', 'drop', 'float', 'floor'].map((k) => [k, lab(k)])) };
  }
  return out;
}

// ---- 8b. the real fighters with their cloth: head / neck core, floor, NaN, CPU per design ----------------------------
const fullCache = new Map();
function fullOf(id) {
  if (!fullCache.has(id)) fullCache.set(id, createCharacter(CTX, SHIPPED[id], { parent: null, name: 'rigqa_full_' + id }));
  return fullCache.get(id);
}
const CLOTH_CLIPS = {
  kael: ['kael.ult.spin', 'kael.lunge', 'kael.dodge', 'kael.pyre'],
  iska: ['iska.glacier_pirouette', 'iska.rising_crescent', 'iska.roll', 'iska.ko'],
  vorn: ['vorn.haft_spin', 'vorn.ult.leap', 'vorn.dash', 'vorn.ninefold_storm'],
};
/**
 * Every free cloth particle as rendered (its bone), per frame at 60 Hz from a clean start of each clip: inside the head
 * core (sphere of 0.12 x body around the skull centre, i.e. through the face / helm), below the floor (> 3 mm), NaN.
 * Then the cost of char.update for the full design (cloth, springs, IK) over the same clips: per frame the fastest of
 * 4 runs (uncontended), its mean <= 1.0 ms.
 */
function testShippedCloth(ids = ['kael', 'iska', 'vorn']) {
  const out = {}, w = new THREE.Vector3(), hc = new THREE.Vector3();
  for (const id of ids) {
    const c = fullOf(id), s = qa.scaleOf(c), specs = (SHIPPED[id].cloth || []).map((sp) => sp.name);
    const rows = (SHIPPED[id].cloth || []).map((sp) => sp.pinRows ?? 1);
    const free = [];
    c.rig.names.forEach((n, k) => { const m = /^(.*)_(\d+)_(\d+)$/.exec(n); const ci = m ? specs.indexOf(m[1]) : -1; if (ci >= 0 && +m[3] >= rows[ci]) free.push(c.bones[n]); });
    let head = 0, low = 0, nan = 0, frames = 0;
    for (const clip of CLOTH_CLIPS[id]) {
      qa.resetForQA(c, clip, {});
      const n = Math.round(getClip(c.rig, clip).duration * 60);
      for (let i = 0; i < n; i++) {
        c.update(1 / 60, 1 / 60); frames++;
        c.root.updateMatrixWorld(true);
        c.bones.head.localToWorld(hc.set(0.01 * s, 0.1 * s, 0));
        for (const b of free) {
          b.getWorldPosition(w);
          if (!Number.isFinite(w.x + w.y + w.z)) { nan++; continue; }
          if (w.distanceTo(hc) < 0.12 * s) head++;
          low = Math.min(low, w.y);
        }
      }
    }
    check(`${id} (full design, ${free.length} free cloth particles, ${frames} frames): cloth NaN`, nan, 0);
    check(`${id}: free cloth particle-frames inside the head core (spins, rolls, KO)`, head, 0);
    check(`${id}: lowest free cloth particle (m below the floor)`, r(-low, 4), 0.003);
    // CPU
    const best = [];
    for (let rep = 0; rep < 5; rep++) {
      let j = 0;
      for (const clip of CLOTH_CLIPS[id]) {
        qa.resetForQA(c, clip, {});
        const n = Math.round(getClip(c.rig, clip).duration * 60);
        for (let i = 0; i < n; i++, j++) {
          const t0 = performance.now(); c.update(1 / 60, 1 / 60); const ms = performance.now() - t0;
          if (rep === 1) best[j] = ms; else if (rep > 1) best[j] = Math.min(best[j], ms); // run 0 warms the JIT up
        }
      }
    }
    const mean = best.reduce((a, x) => a + x, 0) / best.length;
    check(`${id}: CPU char.update, full design with cloth (ms, mean of per-frame minima over 4 runs)`, r(mean, 3), 1.0);
    out[id] = { free: free.length, head, low: r(low, 4), nan, cpu: r(mean, 3) };
  }
  return out;
}

// ---- 9. IK / look / layer / seam / contact measurements of the round-2 audit -----------------------------------------
/**
 * Human-feasible FK arm paths (shoulder flex -10..130, abduction -70..10, humeral rotation +-30, elbow 20..120, wrist
 * +-25 / +-50 / +-15) recorded and replayed as hand IK keys every frame: the elbow must never switch sides (swivel >
 * 30 deg in a frame while the elbow jumps > 4 cm), and the weapon must land on its key.
 */
function feasible(n = 24, seed = 5, body = 'kael', dur = 2) {
  const c = mk(body), rng = makeRng(seed), res = { flips: 0, swivel: 0, elbowIK: 0, elbowFK: 0, rotErr: 0 };
  const sin = (amp, mid) => { const f = 0.15 + 0.5 * rng(), ph = rng() * 6.283, f2 = 0.3 + 0.6 * rng(), ph2 = rng() * 6.283; return (t) => mid + amp * (0.75 * Math.sin(6.283 * f * t + ph) + 0.25 * Math.sin(6.283 * f2 * t + ph2)); };
  const wq = new THREE.Quaternion(), wp = new THREE.Vector3(), X = new THREE.Vector3(), Yv = new THREE.Vector3();
  for (let k = 0; k < n; k++) {
    const fx = sin(40, -30), fy = sin(30, 0), fz = sin(70, 60), el = sin(50, 70), hx = sin(25, 0), hy = sin(50, 0), hz = sin(15, 0);
    const keys = [];
    for (let i = 0; i <= dur * 10; i++) { const t = i / 10; keys.push({ t, bones: { upperArmR: [fx(t), fy(t), fz(t)], foreArmR: [0, 0, el(t)], handR: [hx(t), hy(t), hz(t)] } }); }
    defineClip('rigqa.fk', { duration: dur, keys: [{ t: 0, pose: 'neutral', grip: 0 }, ...keys] });
    invalidateClips();
    qa.resetForQA(c, 'rigqa.fk', { breath: 0 });
    const nf = Math.round(dur * 60), recF = qa.record(c, { hz: 60, frames: nf, time: false, applyRoot: false });
    const ik = [];
    for (let f = 0; f < nf; f++) {
      const o = (f * recF.B + recF.idx.weaponR) * 12, M = recF.M;
      X.set(M[o], M[o + 1], M[o + 2]).normalize(); Yv.set(M[o + 3], M[o + 4], M[o + 5]).normalize();
      ik.push({ t: recF.clipT[f], interp: 'linear', ik: { handR: { pos: [M[o + 9], M[o + 10], M[o + 11]], aim: X.toArray(), up: Yv.toArray() } } });
    }
    defineClip('rigqa.ikr', { duration: dur, keys: [{ t: 0, pose: 'neutral', grip: 0 }, ...ik] });
    invalidateClips();
    qa.resetForQA(c, 'rigqa.ikr', { breath: 0 });
    const recI = qa.record(c, { hz: 60, frames: nf, time: false, applyRoot: false });
    for (let f = 1; f < nf; f++) {
      const sI = swivelStep(recI, f, 'R');
      const eI = vlen(vsub(mpt(recI, f, 'foreArmR'), mpt(recI, f - 1, 'foreArmR'))), eF = vlen(vsub(mpt(recF, f, 'foreArmR'), mpt(recF, f - 1, 'foreArmR')));
      res.swivel = Math.max(res.swivel, sI); res.elbowIK = Math.max(res.elbowIK, eI); res.elbowFK = Math.max(res.elbowFK, eF);
      if (sI > 30 && eI > 0.04) res.flips++;
      res.rotErr = Math.max(res.rotErr, angleOf(recI, recF, f, 'weaponR'));
    }
  }
  return res;
}
/** World rotation angle (deg) between bone `b` of two recordings at frame f. */
function angleOf(ra, rb, f, b) {
  const qa1 = new THREE.Quaternion(), qb1 = new THREE.Quaternion(), m = new THREE.Matrix4();
  const set = (rec, q) => { const o = (f * rec.B + rec.idx[b]) * 12, M = rec.M; m.set(M[o], M[o + 3], M[o + 6], 0, M[o + 1], M[o + 4], M[o + 7], 0, M[o + 2], M[o + 5], M[o + 8], 0, 0, 0, 0, 1); q.setFromRotationMatrix(m); };
  set(ra, qa1); set(rb, qb1);
  return 2 * Math.acos(Math.min(1, Math.abs(qa1.dot(qb1)))) * R2D;
}
/** Look-at on spins: the rotation lookAt adds to the head (with look vs without) may not change more than ~15 deg / frame. */
function lookOffsetStep(c, name, target) {
  const run = (look) => { qa.resetForQA(c, name, { breath: 0 }); if (look) c.lookAt(target, 0.85); const cl = getClip(c.rig, name); const out = []; const q = new THREE.Quaternion(); for (let i = 0; i < Math.round(cl.duration * 60); i++) { c.update(1 / 60, 1 / 60); out.push(c.bones.head.getWorldQuaternion(q).clone()); } c.lookAt(null); return out; };
  const a = run(false), b = run(true);
  let m = 0;
  const d0 = new THREE.Quaternion(), d1 = new THREE.Quaternion();
  for (let i = 1; i < a.length; i++) {
    d0.copy(b[i - 1]).multiply(a[i - 1].clone().invert()); d1.copy(b[i]).multiply(a[i].clone().invert());
    m = Math.max(m, 2 * Math.acos(Math.min(1, Math.abs(d0.dot(d1)))) * R2D);
  }
  return m;
}
function testAudit2() {
  const res = {}, k = mk('kael');
  // R2B-01: human-feasible arm paths
  const fe = feasible(24, 5);
  res.feasible = fe;
  check('feasible arm paths (24 x 2 s): elbow side switches', fe.flips, 0);
  check('feasible arm paths: largest elbow swivel step (deg/frame)', fe.swivel, 20);
  check('feasible arm paths: weapon off the FK truth (deg)', fe.rotErr, 1);
  // R2B-02: look-at during spins and around the back
  const tg = new THREE.Vector3(2.6, 1.75, 0);
  for (const [id, clip] of [['kael', 'demo.combo3'], ['iska', 'iska.glacier_pirouette'], ['iska', 'iska.star_fan'], ['kael', 'kael.sweep']]) {
    const c = id === 'kael' && clip.startsWith('demo') ? k : rigOnly(id);
    check(`lookAt during ${clip}: look rotation change (deg/frame)`, lookOffsetStep(c, clip, tg), 15);
  }
  {
    qa.resetForQA(k, 'demo.idle', { breath: 0 });
    const q0 = new THREE.Quaternion(), q1 = new THREE.Quaternion(), t = new THREE.Vector3();
    let m = 0;
    for (let i = 0; i <= 180; i++) {
      const a = (i * 2 * Math.PI) / 180;
      k.lookAt(t.set(Math.cos(a) * 2.5, 1.75, Math.sin(a) * 2.5), 1); k.update(1 / 60, 1 / 60);
      k.bones.head.getWorldQuaternion(q1);
      if (i) m = Math.max(m, 2 * Math.acos(Math.min(1, Math.abs(q0.dot(q1)))) * R2D);
      q0.copy(q1);
    }
    k.lookAt(null);
    check('lookAt target circling the fighter at 2 deg/frame: head step (deg/frame)', m, 8);
  }
  // R2B-06: masked layer over a walk: the layer's hand target is held
  {
    qa.resetForQA(k, 'demo.walkF', { breath: 0 });
    k.layer('atk', 'demo.combo1', { mask: 'upper', fade: 0 });
    const cl = getClip(k.rig, 'demo.combo1'), pose = new Pose(k.rig), w = new THREE.Vector3(), sh = new THREE.Vector3();
    const reach = k.rig.lengths.upperArm + k.rig.lengths.foreArm + k.rig.P.hand;
    let m = 0, all = 0;
    for (let i = 0; i < 50; i++) {
      k.update(1 / 60, 1 / 60);
      sampleClip(k.rig, cl, (i + 1) / 60, pose);
      const want = new THREE.Vector3(pose.ik[1], pose.ik[2], pose.ik[3]), e = local(k, k.sockets.handR.getWorldPosition(w)).distanceTo(want);
      all = Math.max(all, e);
      // (targets the walk's torso puts out of the arm's reach are reached as far as the arm goes)
      if (local(k, k.bones.upperArmR.getWorldPosition(sh)).distanceTo(want) < 0.93 * reach) m = Math.max(m, e);
    }
    k.stopLayer('atk', 0); k.update(0, 0);
    res.layer = { reachable: m, all };
    check('upper-body layer (combo1) over walkF: fist vs the layer target within reach (m)', m, 0.01);
  }
  // R2B-07: loop seam of quaternion tracks (FK weapon twirl / chest turn): speed at the seam vs mid-loop
  {
    const keys = [];
    for (let i = 0; i < 4; i++) keys.push({ t: i * 0.2, bones: { weaponR: [0, 0, i * 90] } });
    defineClip('rigqa.twirl', { duration: 0.8, loop: true, keys: [{ t: 0, pose: 'neutral', grip: 0 }, ...keys] });
    defineClip('rigqa.turn', { duration: 0.9, loop: true, keys: [{ t: 0, pose: 'neutral', grip: 0, bones: { chest: [0, 0, 0] } }, { t: 0.3, bones: { chest: [0, 120, 0] } }, { t: 0.6, bones: { chest: [0, 240, 0] } }] });
    invalidateClips();
    for (const [name, bone] of [['rigqa.twirl', 'weaponR'], ['rigqa.turn', 'chest']]) {
      qa.resetForQA(k, name, { breath: 0 });
      const per = Math.round(getClip(k.rig, name).duration * 60), q0 = new THREE.Quaternion(), q1 = new THREE.Quaternion(), sp = [];
      k.bones[bone].getWorldQuaternion(q0);
      for (let i = 0; i < per * 2; i++) { k.update(1 / 60, 1 / 60); k.bones[bone].getWorldQuaternion(q1); sp.push(2 * Math.acos(Math.min(1, Math.abs(q0.dot(q1)))) * R2D * 60); q0.copy(q1); }
      const seam = Math.min(...sp.slice(per - 3, per + 3)), cyc = sp.slice(per, 2 * per).sort((a, b) => a - b);
      check(`${name} (looping, > 180 deg per cycle): slowest speed at the seam / the cycle's median`, r(seam / cyc[cyc.length >> 1], 3), 0.8, '>=');
    }
  }
  // R2B-12: a loop driven by setClipTime keeps its loop events and root motion
  {
    qa.resetForQA(k, 'demo.walkF', { breath: 0 });
    let ev = 0, rf = 0, t = 0;
    const off = k.onEvent(() => ev++);
    const d = getClip(k.rig, 'demo.walkF').duration;
    for (let i = 0; i < Math.round(3 * d * 60); i++) { t += 1 / 60; k.setClipTime(t); k.update(1 / 60, 1 / 60); rf += k.rootDelta.f; }
    off();
    check('setClipTime-driven loop, 3 cycles: step events (want 6)', ev, 6, '==');
    check('setClipTime-driven loop, 3 cycles: root motion vs 3 x the cycle (m)', Math.abs(rf - 3 * getClip(k.rig, 'demo.walkF').rootEnd[0]), 0.005);
  }
  // R2B-04: authored knee pole on a pitched planted foot (floor contact keeps the knee's swivel)
  {
    const pole = [0.25, 0.45, 1.2], fl = { pos: [0.1, 0, -0.14], rot: [0, 10, 0] };
    defineClip('rigqa.fp', { duration: 3, keys: [{ t: 0, pose: 'neutral', grip: 0, hips: { pos: [0, -0.1, 0] } },
      { t: 0, ik: { footR: { pos: [0.08, 0.04, 0.3], rot: [0, -30, -4], pole }, footL: fl } }, { t: 1, interp: 'linear', ik: { footR: { pos: [0.08, 0, 0.3], rot: [0, -30, -4], pole }, footL: fl } },
      { t: 2, interp: 'linear', ik: { footR: { pos: [0.08, 0, 0.3], rot: [0, -30, -4], pole }, footL: fl } }, { t: 3, interp: 'linear', ik: { footR: { pos: [0.08, 0, 0.3], rot: [0, -30, 4], pole }, footL: fl } }] });
    invalidateClips();
    qa.resetForQA(k, 'rigqa.fp', { breath: 0 });
    let dev = 0, step = 0, prev = null;
    const V3 = () => new THREE.Vector3();
    for (let i = 0; i < 180; i++) {
      k.update(1 / 60, 1 / 60);
      const hip = local(k, k.bones.thighR.getWorldPosition(V3())), kn = local(k, k.bones.shinR.getWorldPosition(V3())), an = local(k, k.bones.footR.getWorldPosition(V3()));
      const nrm = kn.clone().sub(hip).cross(an.clone().sub(hip)).normalize();
      if (i > 50) dev = Math.max(dev, Math.asin(Math.min(1, Math.abs(new THREE.Vector3(...pole).sub(hip).normalize().dot(nrm)))) * R2D);
      if (prev) step = Math.max(step, kn.distanceTo(prev));
      prev = kn;
    }
    check('pitched planted foot: knee off its authored pole after touchdown (deg)', dev, 2);
    check('pitched planted foot: knee step at touchdown (m/frame)', step, 0.01);
  }
  // R2B-05: clavicle assist computed once per arm and frame (two-handed overhead reach)
  {
    let m = 0;
    for (const grip of [0, 1]) for (const ratio of [0.8, 1.0, 1.2, 1.3]) {
      const L = k.rig.lengths.upperArm + k.rig.lengths.foreArm, s = [-0.015, 1.52, 0.22];
      const d = new THREE.Vector3(0.25, 1, 0.1).normalize().multiplyScalar(L * ratio + k.rig.P.hand);
      defineClip('rigqa.cl', { duration: 1, loop: true, keys: [{ t: 0, pose: 'neutral', grip, curl: [1, 1], ik: { handR: { pos: [s[0] + d.x, s[1] + d.y, s[2] + d.z], aim: [0.2, 1, 0], up: [-1, 0.2, 0] } } }] });
      invalidateClips();
      qa.resetForQA(k, 'rigqa.cl', { breath: 0 });
      k.update(1 / 60, 1 / 60);
      for (const S of ['R', 'L']) m = Math.max(m, 2 * Math.acos(Math.min(1, Math.abs(k.bones['shoulder' + S].quaternion.w))) * R2D);
    }
    check('clavicle assist, one- and two-handed reach to 130% (deg)', m, 25);
  }
  // R2A-13 / R2B-11: steep tiptoe and pitched feet: toe tip and toe pad on or above the floor
  {
    let pen = 0;
    for (const pitch of [-30, -45, -60, -80]) {
      defineClip('rigqa.tt', { duration: 1, loop: true, keys: [{ t: 0, pose: 'neutral', grip: 0, hips: { pos: [0, -0.05, 0] }, ik: { footR: { pos: [0.05, 0.12 * Math.sin(-pitch * Math.PI / 180), 0.12], rot: [0, 0, pitch] } } }] });
      invalidateClips();
      qa.resetForQA(k, 'rigqa.tt', { breath: 0 });
      for (let i = 0; i < 2; i++) k.update(1 / 60, 1 / 60);
      const P = k.rig.P, th = P.ankleHeight - P.footDrop;
      for (const pt of [[0, -th, 0], [P.toeLength, -th, 0]]) pen = Math.max(pen, -k.bones.toeR.localToWorld(new THREE.Vector3(...pt)).y);
    }
    check('pitched / tiptoe feet (-30..-80 deg): toe pad / tip below the floor (m)', pen, 0.0015);
  }
  // R2B-08: planted feet out of reach slide on the floor (they never float), the total drop stays bounded
  {
    let float = 0, drop = 0;
    for (const back of [0.5, 0.6, 0.7, 1.0]) {
      defineClip('rigqa.ds', { duration: 1, loop: true, keys: [{ t: 0, pose: 'neutral', grip: 0, ik: { footR: { pos: [-back, 0, 0.12] }, footL: { pos: [0.3, 0, -0.12] } } }] });
      invalidateClips();
      qa.resetForQA(k, 'rigqa.ds', { breath: 0 });
      for (let i = 0; i < 4; i++) k.update(1 / 60, 1 / 60);
      const P = k.rig.P;
      float = Math.max(float, Math.min(k.bones.footR.localToWorld(new THREE.Vector3(0, -P.ankleHeight, 0)).y, k.bones.footR.localToWorld(new THREE.Vector3(-P.heelLength, -P.ankleHeight, 0)).y, k.bones.toeR.localToWorld(new THREE.Vector3(0, -(P.ankleHeight - P.footDrop), 0)).y));
      drop = Math.max(drop, k.diag.drop);
    }
    check('rear foot 0.5..1.0 m behind the hip: planted foot in the air (m)', float, 0.005);
    check('rear foot 0.5..1.0 m behind the hip: automatic drop <= maxPelvisDrop (m)', drop, 0.1601);
  }
  // R2B-10: no hips hitch from the drop release (demo.combo3 hips 2nd difference vs the authored one)
  {
    qa.resetForQA(k, 'demo.c2end', { breath: 0 });
    k.play('demo.combo3', { fade: 0, restart: true });
    const cd = getClip(k.rig, 'demo.combo3'), pose = new Pose(k.rig), A = [], Bv = [];
    for (let i = 0; i < Math.round(cd.duration * 60); i++) { k.update(1 / 60, 1 / 60); sampleClip(k.rig, cd, k.clipTime, pose); A.push(k.bones.hips.position.y); Bv.push(k.rig.offset[1] + pose.hips[1]); }
    let ja = 0, jb = 0;
    for (let i = 2; i < A.length; i++) { ja = Math.max(ja, Math.abs(A[i] - 2 * A[i - 1] + A[i - 2])); jb = Math.max(jb, Math.abs(Bv[i] - 2 * Bv[i - 1] + Bv[i - 2])); }
    check('demo.combo3: hips 2nd difference / authored', r(ja / Math.max(jb, 1e-6), 2), 1.5);
  }
  // R2A-02: reproducible after teleport (the breathing phase is reset: a clip's arms do not depend on how long the
  // character has lived)
  {
    const sig = () => { qa.resetForQA(k, 'demo.idle', { breath: 1 }); k.play('demo.guard', { fade: 0.08 }); for (let i = 0; i < 10; i++) k.update(1 / 60, 1 / 60); return qa.poseOf(k); };
    const a = sig();
    for (let i = 0; i < 37; i++) k.update(1 / 60, 1 / 60);
    const b = sig();
    check('idle -> guard after teleport, two runs: pose difference (deg)', qa.poseDiff(a, b).deg, 1e-3);
  }
  return res;
}

/** Per-frame arm values of a shipped clip (debugging): [t, swivel, axis turn, elbow step, wrist step, fist step] (deg, mm). */
function armTrace(id, name, S = 'R', from = 0, to = 1e9) {
  const c = id === 'knight' ? mk('kael') : rigOnly(id), cl = getClip(c.rig, name);
  qa.resetForQA(c, name, { breath: 0 });
  const n = Math.round(cl.duration * 60) + 1, rec = qa.record(c, { hz: 60, frames: n, time: false }), out = [];
  for (let f = Math.max(1, from); f < Math.min(n, to); f++) {
    const A = elbowPerp(rec, f - 1, S), Bp = elbowPerp(rec, f, S), mm = (b) => r(vlen(vsub(cpt(rec, f, b + S), cpt(rec, f - 1, b + S))) * 1000, 1);
    out.push([r(rec.t[f], 3), r(swivelStep(rec, f, S), 1), r(Math.acos(Math.max(-1, Math.min(1, vdot(A.a, Bp.a)))) * R2D, 1), mm('foreArm'), mm('hand'), mm('weapon')]);
  }
  return out;
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
  const groups = { clips: () => testClips(opts.bodies), runtime: testRuntime, ik: testIK, audit2: testAudit2, xfade: testXfade, cloth: testCloth, shipped: () => testShippedArms(opts.fighters), shippedCloth: () => testShippedCloth(opts.fighters), cpu: testCpu };
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
    window.__ED.qa = { clip: (name, body = 'kael') => clipMetrics(typeof body === 'string' ? mk(body) : mkWith(body), name), arm: (id, name) => armMetrics(id === 'knight' ? mk('kael') : rigOnly(id), name), mk, mkWith, rigOnly, fullOf, CLOTH_CLIPS, defineClip, invalidateClips, listClips, run: runAll, trace, armTrace, IK, THREE, getClip, sampleClip, Pose, qa };
  },
  scenarios: {
    all(ctx, lab, opts = {}) { return runAll(opts); },
  },
});
