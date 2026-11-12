// Humanoid rig: bone table, proportions -> rest offsets, zero / bind pose, model-space forward kinematics.
//
// Every bone's local frame in the ZERO pose (all rotations 0) is parallel to the fighter frame:
//   +X = forward (f, toward the opponent), +Y = up (u), +Z = side toward the camera (s, the fighter's RIGHT side).
// Limbs hang straight down (-Y) in the zero pose, feet and toes point +X. Authored rotations are local Euler degrees
// (order ZXY) relative to that frame; left-side bones (`...L`) are mirrored (X and Y negated) so equal numbers give the
// mirror-image pose. The BIND pose (arms in an A-pose) is only used to build the smooth under-suit.

import { eulerToQuat, qmul, qrot, qaxis, qslerp, qidentity, qcopy, twistAngle, swingAngle, smooth01 } from './rigmath.js';

/** Default heroic proportions (metres). A design may override any of these. */
export const DEFAULT_PROPORTIONS = {
  hipHeight: 0.98,      // hip joint height above the floor
  pelvisDrop: 0.06,     // hips pivot sits this far above the hip joints
  hipWidth: 0.10,       // half distance between the hip joints
  thighRatio: 0.52,     // thigh share of (hipHeight - ankleHeight)
  ankleHeight: 0.085,   // ankle joint above the sole
  footLength: 0.135,    // ankle -> ball of the foot (forward)
  footDrop: 0.055,      // ankle -> ball height difference
  toeLength: 0.08,      // ball -> toe tip
  heelLength: 0.065,    // ankle -> back of the heel
  spine: 0.11,          // hips pivot -> spine (lumbar) pivot
  chest: 0.17,          // spine -> chest (thorax) pivot
  neck: 0.255,          // chest -> neck base
  head: 0.105,          // neck base -> head pivot (skull base); head top ~0.22 above it
  shoulderHeight: 0.20, // chest pivot -> clavicle root (up)
  clavicleRoot: 0.03,   // clavicle root off the midline
  clavicle: 0.19,       // clavicle length (root -> shoulder joint, sideways)
  shoulderBack: 0.015,  // shoulder joint sits slightly behind the clavicle root
  upperArm: 0.30,
  foreArm: 0.27,
  hand: 0.085,          // wrist -> centre of the fist (grip axis)
  palm: 0.022,          // grip axis offset toward the palm
};

// [name, parent, side]   side: 0 centre, 1 right, -1 left
const CORE = [
  ['hips', null, 0], ['spine', 'hips', 0], ['chest', 'spine', 0], ['neck', 'chest', 0], ['head', 'neck', 0],
];
const ARM = (s) => [
  ['shoulder' + s, 'chest'], ['upperArm' + s, 'shoulder' + s], ['foreArm' + s, 'upperArm' + s], ['hand' + s, 'foreArm' + s],
  ['fingers' + s, 'hand' + s], ['fingerTips' + s, 'fingers' + s], ['thumb' + s, 'hand' + s], ['weapon' + s, 'hand' + s],
];
const LEG = (s) => [['thigh' + s, 'hips'], ['shin' + s, 'thigh' + s], ['foot' + s, 'shin' + s], ['toe' + s, 'foot' + s]];
const HELPERS = (s) => [
  ['deltoid' + s, 'shoulder' + s], ['upperArmTwist' + s, 'upperArm' + s], ['elbow' + s, 'upperArm' + s],
  ['foreArmTwist' + s, 'foreArm' + s], ['knee' + s, 'thigh' + s],
  ['hipJoint' + s, 'hips'], ['thighTwist' + s, 'thigh' + s], ['elbowVol' + s, 'upperArm' + s], ['kneeVol' + s, 'thigh' + s],
];

/** Bones whose rotation the runtime computes from others every frame (never author them). */
export const HELPER_NAMES = ['R', 'L'].flatMap((s) => HELPERS(s).map((h) => h[0]));

/**
 * A-pose used to build the smooth-skinned suit (authoring convention, degrees). Close to the mean of the poses the
 * arms actually take (28 deg abduction), so the suit deforms least on average.
 */
export const BIND_POSE = {
  upperArmR: [-28, 0, 8], upperArmL: [-28, 0, 8],
  foreArmR: [0, 0, 14], foreArmL: [0, 0, 14],
  thighR: [-3, 0, 0], thighL: [-3, 0, 0],
};

/** Body scale of a proportion set: hips pivot height / 1.04 m (1 = the default 1.95 m fighter). */
export function bodyScale(P) { return (P.hipHeight + P.pelvisDrop) / 1.04; }

function offsetsFor(P) {
  const leg = P.hipHeight - P.ankleHeight;
  const thigh = leg * P.thighRatio, shin = leg - thigh;
  const k = bodyScale(P), kh = P.hand / 0.085; // every constant below is a fraction of a body / hand size
  const o = {
    hips: [0, P.hipHeight + P.pelvisDrop, 0],
    spine: [0, P.spine, 0], chest: [0, P.chest, 0], neck: [-0.01 * k, P.neck, 0], head: [0.01 * k, P.head, 0],
  };
  for (const [s, z] of [['R', 1], ['L', -1]]) {
    o['shoulder' + s] = [0, P.shoulderHeight, z * P.clavicleRoot];
    o['upperArm' + s] = [-P.shoulderBack, 0, z * P.clavicle];
    o['foreArm' + s] = [0, -P.upperArm, 0];
    o['hand' + s] = [0, -P.foreArm, 0];
    o['fingers' + s] = [0.004 * kh, -P.hand - 0.012 * kh, -z * 0.004 * kh];
    o['fingerTips' + s] = [0, -0.048 * kh, 0];
    o['thumb' + s] = [0.026 * kh, -0.035 * kh, -z * 0.016 * kh];
    o['weapon' + s] = [0, -P.hand, -z * P.palm];
    o['thigh' + s] = [0, -P.pelvisDrop, z * P.hipWidth];
    o['shin' + s] = [0, -thigh, 0];
    o['foot' + s] = [0, -shin, 0];
    o['toe' + s] = [P.footLength, -P.footDrop, 0];
    o['deltoid' + s] = [-P.shoulderBack, 0, z * P.clavicle];
    o['upperArmTwist' + s] = [0, -P.upperArm * 0.1333, 0];
    o['elbow' + s] = [0, -P.upperArm, 0];
    o['foreArmTwist' + s] = [0, -P.foreArm * 0.5, 0];
    o['knee' + s] = [0, -thigh, 0];
    o['hipJoint' + s] = [0, -P.pelvisDrop, z * P.hipWidth];
    o['thighTwist' + s] = [0, -thigh * 0.12, 0];
    o['elbowVol' + s] = [0, -P.upperArm, 0];
    o['kneeVol' + s] = [0, -thigh, 0];
  }
  return { o, thigh, shin };
}

/**
 * Build the rig description.
 * @param {object} proportions  overrides of DEFAULT_PROPORTIONS
 * @param {Array} extra  design bones: [{ name, parent, at:[x,y,z] (parent zero frame), rot?:[x,y,z] deg | quat?:[x,y,z,w] rest rotation,
 *                       follow?: { bone, k } (driven: k x that bone's swing; `at` defaults to its position) }]
 */
export function createRig(proportions = {}, extra = [], opts = {}) {
  const P = { ...DEFAULT_PROPORTIONS, ...proportions };
  const { o, thigh, shin } = offsetsFor(P);
  const list = [...CORE];
  for (const s of ['R', 'L']) for (const b of ARM(s)) list.push([b[0], b[1], s === 'R' ? 1 : -1]);
  for (const s of ['R', 'L']) for (const b of LEG(s)) list.push([b[0], b[1], s === 'R' ? 1 : -1]);
  for (const s of ['R', 'L']) for (const b of HELPERS(s)) list.push([b[0], b[1], s === 'R' ? 1 : -1]);
  for (const e of extra) list.push([e.name, e.parent, e.side ?? (/R$/.test(e.name) ? 1 : /L$/.test(e.name) ? -1 : 0)]);

  const count = list.length;
  const rig = {
    P, count,
    names: list.map((b) => b[0]),
    index: Object.create(null),
    parent: new Int16Array(count),
    side: new Int8Array(count),
    mirror: new Int16Array(count),
    offset: new Float32Array(count * 3),
    restRot: new Float32Array(count * 4),
    bindLocal: new Float32Array(count * 4),
    helper: new Uint8Array(count),
    lengths: { upperArm: P.upperArm, foreArm: P.foreArm, thigh, shin, hand: P.hand },
    k: bodyScale(P),                 // body scale (constants in metres are multiplied by it)
    gripAngle: opts.gripAngle ?? 0,  // weapon bone rest pitch in the fist (deg, toward the little finger)
  };
  list.forEach(([name], i) => { rig.index[name] = i; });
  list.forEach(([name, parent, side], i) => {
    if (parent && rig.index[parent] === undefined) throw new Error('char: bone ' + name + ' has unknown parent ' + parent);
    rig.parent[i] = parent ? rig.index[parent] : -1;
    rig.side[i] = side;
    const ex = extra.find((e) => e.name === name);
    // a follower without `at` sits where the bone it follows sits (same parent)
    const fo = ex && !ex.at && ex.follow ? rig.index[ex.follow.bone] : undefined;
    const off = ex ? ex.at || (fo !== undefined ? Array.from(rig.offset.subarray(fo * 3, fo * 3 + 3)) : [0, 0, 0]) : o[name];
    rig.offset.set(off, i * 3);
    if (ex && ex.quat) rig.restRot.set(ex.quat, i * 4);
    else if (ex && ex.rot) eulerToQuat(rig.restRot, i * 4, ex.rot[0], ex.rot[1], ex.rot[2]);
    else if (/^weapon[RL]$/.test(name) && rig.gripAngle) eulerToQuat(rig.restRot, i * 4, 0, 0, -rig.gripAngle);
    else rig.restRot.set([0, 0, 0, 1], i * 4);
    rig.helper[i] = HELPER_NAMES.includes(name) ? 1 : 0;
  });
  list.forEach(([name], i) => {
    const m = name.endsWith('R') ? name.slice(0, -1) + 'L' : name.endsWith('L') ? name.slice(0, -1) + 'R' : name;
    rig.mirror[i] = rig.index[m] ?? i;
  });
  // bind pose local rotations; helper bones take the values the drivers give them in the bind pose (the suit is
  // undeformed in its own bind pose)
  for (let i = 0; i < count; i++) {
    const b = BIND_POSE[rig.names[i]];
    if (b) eulerToQuat(rig.bindLocal, i * 4, b[0], b[1], b[2], rig.side[i] < 0);
    else rig.bindLocal.set(rig.restRot.subarray(i * 4, i * 4 + 4), i * 4);
  }
  rig.helperBones = ['R', 'L'].map((s) => {
    const o = { side: s === 'R' ? 1 : -1 };
    for (const b of ['shoulder', 'upperArm', 'foreArm', 'hand', 'thigh', 'shin', ...HELPERS('').map((h) => h[0])]) o[b] = rig.index[b + s];
    return o;
  });
  rig.helperScale = new Float32Array(count * 3).fill(1);
  driveHelpers(rig, rig.bindLocal, null);
  rig.bindHelperScale = Float32Array.from(rig.helperScale);
  return rig;
}

// ---- helper bones -------------------------------------------------------------------------------------------------
const hq = new Float32Array(24);
/**
 * A twist angle near +-180 deg continues on the branch of the previous frame (mem[i]) instead of jumping to the other
 * sign; only acts in that band, so poses inside the human range never depend on history.
 */
function unwrap(mem, i, a) {
  if (!mem) return a;
  const prev = mem[i];
  if (Math.abs(a) > 2.6 && Math.abs(prev) > 2.0 && Math.sign(a) !== Math.sign(prev)) a += a < 0 ? 2 * Math.PI : -2 * Math.PI;
  mem[i] = a;
  return a;
}

/**
 * Twist (rad) about the bone's own Y axis, faded out where swing-twist is ill-conditioned (swing near 180 deg); the
 * raw twist is unwrapped against last frame (mem slot i) before fading.
 */
function fadedTwist(q, o, mem = null, i = 0) {
  const sw = swingAngle(q, o, 0, -1, 0);
  const f = smooth01(sw, 2.62, 1.75); // full below 100 deg of swing, zero above 150 deg
  return f > 0 ? unwrap(mem, i, twistAngle(q, o, 0, 1, 0)) * f : 0;
}

// reference raise for the deltoid half-swing: the arm raised 60 deg in the scapular plane (between flexion and
// abduction). Rotations 180 deg away from it (arm pointing back and in, or twisted ~160 deg) are out of the arm's range.
const DELT_REF = new Float32Array(8);
eulerToQuat(DELT_REF, 0, -45, 0, 45);
eulerToQuat(DELT_REF, 4, -45, 0, 45, true);

/**
 * out = normalised (identity + q) with q's sign chosen against reference r (the half rotation of q). Returns the dot
 * product of q and r (0 = on the reference's singular wall).
 */
function halfRot(out, oo, q, qo, r, ro) {
  const dot = q[qo] * r[ro] + q[qo + 1] * r[ro + 1] + q[qo + 2] * r[ro + 2] + q[qo + 3] * r[ro + 3];
  const sg = dot < 0 ? -1 : 1;
  const x = q[qo] * sg, y = q[qo + 1] * sg, z = q[qo + 2] * sg, w = q[qo + 3] * sg + 1;
  const l = 1 / (Math.hypot(x, y, z, w) || 1);
  out[oo] = x * l; out[oo + 1] = y * l; out[oo + 2] = z * l; out[oo + 3] = w * l;
  return dot;
}

/**
 * Drive the helper bones from the animated bones (local rotations in lq): forearm twist moved into the hand (the
 * forearm stays a hinge), deltoid = half of the arm swing, upper-arm / thigh twist helpers cancel half of the twist
 * near the shoulder / hip, elbow / knee half-joints, forearm twist helper = 65% of the wrist pronation, hip joint =
 * half of the thigh swing, elbow / knee volume helpers = half-joint + an inflation scale (rig.helperScale) that keeps
 * the inside of a flexed joint from collapsing onto the bone. `mem` (Float32Array(4) or null) keeps the last forearm /
 * upper-arm twist per side, so the twist helpers never jump across +-180 deg.
 */
export function driveHelpers(rig, lq, mem) {
  const HS = rig.helperScale;
  for (let k = 0; k < 2; k++) {
    const D = rig.helperBones[k], ua = D.upperArm, fa = D.foreArm, ha = D.hand, th = D.thigh;
    // forearm twist -> hand
    const ft = twistAngle(lq, fa * 4, 0, 1, 0);
    if (Math.abs(ft) > 1e-4) {
      qaxis(hq, 0, 0, 1, 0, -ft);
      qmul(lq, fa * 4, lq, fa * 4, hq, 0);
      qaxis(hq, 0, 0, 1, 0, ft);
      qmul(lq, ha * 4, hq, 0, lq, ha * 4);
    }
    qidentity(hq, 8);
    // deltoid: half of the arm swing. Twist removed where it is well defined, the half taken on the branch of a
    // reference raise (scaption, DELT_REF); next to that reference's singular wall (|dot| small: an arm pointing back
    // and in, or wrung far past its twist range) the plain half-elevation in the arm's own plane takes over
    const ut = fadedTwist(lq, ua * 4, mem, 2 + k);
    qaxis(hq, 0, 0, 1, 0, -ut);
    qmul(hq, 4, lq, ua * 4, hq, 0);
    const dr = Math.abs(halfRot(hq, 12, hq, 4, DELT_REF, k * 4));
    if (dr < 0.3) {
      qrot(hq, 16, lq, ua * 4, 0, -1, 0);                               // arm direction (shoulder frame)
      const el = Math.acos(Math.max(-1, Math.min(1, -hq[17])));
      let nx = -hq[18], nz = hq[16];
      const nl = Math.hypot(nx, nz);
      if (nl > 1e-6) { nx /= nl; nz /= nl; } else { nx = 1; nz = 0; }
      qaxis(hq, 20, nx, 0, nz, 0.5 * el);
      qslerp(hq, 12, hq, 20, hq, 12, smooth01(dr, 0.12, 0.3));
    }
    qcopy(lq, D.deltoid * 4, hq, 12);
    qaxis(lq, D.upperArmTwist * 4, 0, 1, 0, -0.5 * ut);
    // elbow half-joint + volume helper
    qslerp(lq, D.elbow * 4, hq, 8, lq, fa * 4, 0.5);
    qcopy(lq, D.elbowVol * 4, lq, D.elbow * 4);
    const eflex = Math.max(0, swingAngle(lq, fa * 4, 0, -1, 0) - 0.25);
    HS[D.elbowVol * 3] = 1 + 0.22 * eflex; HS[D.elbowVol * 3 + 1] = 1; HS[D.elbowVol * 3 + 2] = 1 + 0.08 * eflex;
    // forearm twist helper: 65% of the wrist pronation, unwrapped against the previous frame near +-180 deg
    qaxis(lq, D.foreArmTwist * 4, 0, 1, 0, 0.65 * unwrap(mem, k, twistAngle(lq, ha * 4, 0, 1, 0)));
    // legs: hip joint half-swing, thigh twist helper, knee half-joint + volume helper
    const tt = fadedTwist(lq, th * 4);
    qaxis(hq, 0, 0, 1, 0, -tt);
    qmul(hq, 4, lq, th * 4, hq, 0);
    halfRot(lq, D.hipJoint * 4, hq, 4, hq, 8);
    qaxis(lq, D.thighTwist * 4, 0, 1, 0, -0.5 * tt);
    qslerp(lq, D.knee * 4, hq, 8, lq, D.shin * 4, 0.5);
    qcopy(lq, D.kneeVol * 4, lq, D.knee * 4);
    const kflex = Math.max(0, swingAngle(lq, D.shin * 4, 0, -1, 0) - 0.2);
    HS[D.kneeVol * 3] = 1 + 0.2 * kflex; HS[D.kneeVol * 3 + 1] = 1; HS[D.kneeVol * 3 + 2] = 1 + 0.08 * kflex;
  }
}

/**
 * Forward kinematics in model (fighter-local) space: mq/mp = model rotation / position of every bone from local
 * rotations lq and local positions lp (bones are ordered parents-first). Bones with parent -1 are model-space roots.
 */
export function fk(rig, lq, lp, mq, mp, from = 0, to = rig.count) {
  const par = rig.parent;
  for (let i = from; i < to; i++) {
    const p = par[i], i3 = i * 3, i4 = i * 4;
    if (p < 0) {
      mp[i3] = lp[i3]; mp[i3 + 1] = lp[i3 + 1]; mp[i3 + 2] = lp[i3 + 2];
      mq[i4] = lq[i4]; mq[i4 + 1] = lq[i4 + 1]; mq[i4 + 2] = lq[i4 + 2]; mq[i4 + 3] = lq[i4 + 3];
    } else {
      qrot(mp, i3, mq, p * 4, lp[i3], lp[i3 + 1], lp[i3 + 2]);
      mp[i3] += mp[p * 3]; mp[i3 + 1] += mp[p * 3 + 1]; mp[i3 + 2] += mp[p * 3 + 2];
      qmul(mq, i4, mq, p * 4, lq, i4);
    }
  }
}

/** Model-space bind matrices (column-major 4x4, Float32Array count*16) of the bind pose. */
export function bindMatrices(rig) {
  const n = rig.count;
  const mq = new Float32Array(n * 4), mp = new Float32Array(n * 3);
  fk(rig, rig.bindLocal, rig.offset, mq, mp);
  const out = new Float32Array(n * 16);
  for (let i = 0; i < n; i++) composeMatrix(out, i * 16, mq, i * 4, mp, i * 3);
  return { matrices: out, mq, mp };
}

/** Write a rotation+translation matrix (column-major) into out[o..o+15]. */
export function composeMatrix(out, o, q, qo, p, po) {
  const x = q[qo], y = q[qo + 1], z = q[qo + 2], w = q[qo + 3];
  const x2 = x + x, y2 = y + y, z2 = z + z;
  const xx = x * x2, xy = x * y2, xz = x * z2, yy = y * y2, yz = y * z2, zz = z * z2, wx = w * x2, wy = w * y2, wz = w * z2;
  out[o] = 1 - (yy + zz); out[o + 1] = xy + wz; out[o + 2] = xz - wy; out[o + 3] = 0;
  out[o + 4] = xy - wz; out[o + 5] = 1 - (xx + zz); out[o + 6] = yz + wx; out[o + 7] = 0;
  out[o + 8] = xz + wy; out[o + 9] = yz - wx; out[o + 10] = 1 - (xx + yy); out[o + 11] = 0;
  out[o + 12] = p[po]; out[o + 13] = p[po + 1]; out[o + 14] = p[po + 2]; out[o + 15] = 1;
  return out;
}
