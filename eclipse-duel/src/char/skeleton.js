// Humanoid rig: bone table, proportions -> rest offsets, zero / bind pose, model-space forward kinematics.
//
// Every bone's local frame in the ZERO pose (all rotations 0) is parallel to the fighter frame:
//   +X = forward (f, toward the opponent), +Y = up (u), +Z = side toward the camera (s, the fighter's RIGHT side).
// Limbs hang straight down (-Y) in the zero pose, feet and toes point +X. Authored rotations are local Euler degrees
// (order ZXY) relative to that frame; left-side bones (`...L`) are mirrored (X and Y negated) so equal numbers give the
// mirror-image pose. The BIND pose (arms in an A-pose) is only used to build the smooth under-suit.

import { eulerToQuat, qmul, qrot } from './rigmath.js';

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
];

/** Bones whose rotation the runtime computes from others every frame (never author them). */
export const HELPER_NAMES = ['deltoidR', 'deltoidL', 'upperArmTwistR', 'upperArmTwistL', 'elbowR', 'elbowL', 'foreArmTwistR', 'foreArmTwistL', 'kneeR', 'kneeL'];

/** A-pose used to build the smooth-skinned suit (authoring convention, degrees). */
export const BIND_POSE = {
  upperArmR: [-42, 0, 6], upperArmL: [-42, 0, 6],
  foreArmR: [0, 0, 12], foreArmL: [0, 0, 12],
  thighR: [-3, 0, 0], thighL: [-3, 0, 0],
};

function offsetsFor(P) {
  const leg = P.hipHeight - P.ankleHeight;
  const thigh = leg * P.thighRatio, shin = leg - thigh;
  const o = {
    hips: [0, P.hipHeight + P.pelvisDrop, 0],
    spine: [0, P.spine, 0], chest: [0, P.chest, 0], neck: [-0.01, P.neck, 0], head: [0.01, P.head, 0],
  };
  for (const [s, z] of [['R', 1], ['L', -1]]) {
    o['shoulder' + s] = [0, P.shoulderHeight, z * P.clavicleRoot];
    o['upperArm' + s] = [-P.shoulderBack, 0, z * P.clavicle];
    o['foreArm' + s] = [0, -P.upperArm, 0];
    o['hand' + s] = [0, -P.foreArm, 0];
    o['fingers' + s] = [0.004, -P.hand - 0.012, -z * 0.004];
    o['fingerTips' + s] = [0, -0.048, 0];
    o['thumb' + s] = [0.026, -0.035, -z * 0.016];
    o['weapon' + s] = [0, -P.hand, -z * P.palm];
    o['thigh' + s] = [0, -P.pelvisDrop, z * P.hipWidth];
    o['shin' + s] = [0, -thigh, 0];
    o['foot' + s] = [0, -shin, 0];
    o['toe' + s] = [P.footLength, -P.footDrop, 0];
    o['deltoid' + s] = [-P.shoulderBack, 0, z * P.clavicle];
    o['upperArmTwist' + s] = [0, -0.04, 0];
    o['elbow' + s] = [0, -P.upperArm, 0];
    o['foreArmTwist' + s] = [0, -P.foreArm * 0.5, 0];
    o['knee' + s] = [0, -thigh, 0];
  }
  return { o, thigh, shin };
}

/**
 * Build the rig description.
 * @param {object} proportions  overrides of DEFAULT_PROPORTIONS
 * @param {Array} extra  design bones: [{ name, parent, at:[x,y,z] (parent zero frame), rot?:[x,y,z] deg rest rotation }]
 */
export function createRig(proportions = {}, extra = []) {
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
  };
  list.forEach(([name], i) => { rig.index[name] = i; });
  list.forEach(([name, parent, side], i) => {
    if (parent && rig.index[parent] === undefined) throw new Error('char: bone ' + name + ' has unknown parent ' + parent);
    rig.parent[i] = parent ? rig.index[parent] : -1;
    rig.side[i] = side;
    const ex = extra.find((e) => e.name === name);
    const off = ex ? ex.at || [0, 0, 0] : o[name];
    rig.offset.set(off, i * 3);
    if (ex && ex.rot) eulerToQuat(rig.restRot, i * 4, ex.rot[0], ex.rot[1], ex.rot[2]);
    else rig.restRot.set([0, 0, 0, 1], i * 4);
    rig.helper[i] = HELPER_NAMES.includes(name) ? 1 : 0;
  });
  list.forEach(([name], i) => {
    const m = name.endsWith('R') ? name.slice(0, -1) + 'L' : name.endsWith('L') ? name.slice(0, -1) + 'R' : name;
    rig.mirror[i] = rig.index[m] ?? i;
  });
  // bind pose local rotations
  for (let i = 0; i < count; i++) {
    const b = BIND_POSE[rig.names[i]];
    if (b) eulerToQuat(rig.bindLocal, i * 4, b[0], b[1], b[2], rig.side[i] < 0);
    else rig.bindLocal.set(rig.restRot.subarray(i * 4, i * 4 + 4), i * 4);
  }
  return rig;
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
