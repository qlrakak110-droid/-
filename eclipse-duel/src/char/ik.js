// Inverse kinematics on model-space (fighter-local) arrays: analytic two-bone limbs with pole hints and soft reach,
// floor / toe contact for feet, and a distributed neck + head look-at. All functions read the current FK result
// (mq / mp) and write local rotations (lq); callers re-run FK on the affected range afterwards.

import { qmul, qmulInv, qrot, qslerp, qfromBasis, qaxis, qfromTo, qcopy } from './rigmath.js';
import { fk } from './skeleton.js';

/**
 * Limb descriptors for a rig: handR, handL, footR, footL.
 * endOff = the effector point in the end bone's frame (hands: centre of the fist / grip axis; feet: the sole point
 * straight below the ankle).
 */
export function makeLimbs(rig) {
  const ix = rig.index, P = rig.P, out = {};
  for (const [s, z] of [['R', 1], ['L', -1]]) {
    out['hand' + s] = {
      kind: 'arm', side: z, sign: 1, clav: ix['shoulder' + s], parent: ix['shoulder' + s], root: ix['upperArm' + s], mid: ix['foreArm' + s], end: ix['hand' + s],
      l1: rig.lengths.upperArm, l2: rig.lengths.foreArm, endOff: [0, -P.hand, -z * P.palm],
      first: ix['shoulder' + s],
    };
    out['foot' + s] = {
      kind: 'leg', side: z, sign: -1, parent: ix.hips, root: ix['thigh' + s], mid: ix['shin' + s], end: ix['foot' + s], toe: ix['toe' + s],
      l1: rig.lengths.thigh, l2: rig.lengths.shin, endOff: [0, -P.ankleHeight, 0],
      first: ix['thigh' + s],
    };
  }
  return out;
}

const tq = new Float32Array(16), tv = new Float32Array(12);
const X = [0, 0, 0], Y = [0, 0, 0], Z = [0, 0, 0];
const oldL = new Float32Array(12), newL = new Float32Array(12), endModel = new Float32Array(4);

/**
 * Two-bone IK. target: Float32Array/array [x,y,z] (model space, effector point), rot: quaternion array or null (keep
 * the end bone's current model orientation), pole: point [x,y,z] or null (default pole), weight 0..1.
 * Returns the reach ratio (dist / max length) before softening.
 */
export function solveLimb(rig, limb, lq, mq, mp, target, to, rot, ro, pole, po, weight, soft = 0.04) {
  if (weight <= 0) return 0;
  const { root, mid, end, parent, sign, l1, l2, endOff } = limb;
  // current end orientation (model)
  qcopy(endModel, 0, mq, end * 4);
  const er = rot || endModel, eo = rot ? ro : 0;
  qrot(tv, 0, er, eo, endOff[0], endOff[1], endOff[2]);
  const wx = target[to] - tv[0], wy = target[to + 1] - tv[1], wz = target[to + 2] - tv[2];
  const ax = mp[root * 3], ay = mp[root * 3 + 1], az = mp[root * 3 + 2];
  let dx = wx - ax, dy = wy - ay, dz = wz - az;
  const dist = Math.hypot(dx, dy, dz) || 1e-6;
  const ux = dx / dist, uy = dy / dist, uz = dz / dist;
  const lmax = l1 + l2, lmin = Math.abs(l1 - l2) + 1e-3;
  let d = dist;
  const ds = lmax * (1 - soft);
  if (d > ds) d = ds + (lmax - ds) * (1 - Math.exp(-(d - ds) / (lmax - ds)));
  if (d < lmin) d = lmin;
  // pole direction (perpendicular to the reach)
  let px, py, pz;
  if (pole) { px = pole[po] - ax; py = pole[po + 1] - ay; pz = pole[po + 2] - az; }
  else defaultPole(rig, limb, mq, mp, ux, uy, uz, er, eo, tv);
  if (!pole) { px = tv[3]; py = tv[4]; pz = tv[5]; }
  let k = px * ux + py * uy + pz * uz;
  px -= ux * k; py -= uy * k; pz -= uz * k;
  let pl = Math.hypot(px, py, pz);
  if (pl < 1e-5) { // pole on the reach line: use the current mid joint
    px = mp[mid * 3] - ax; py = mp[mid * 3 + 1] - ay; pz = mp[mid * 3 + 2] - az;
    k = px * ux + py * uy + pz * uz; px -= ux * k; py -= uy * k; pz -= uz * k; pl = Math.hypot(px, py, pz) || 1;
    if (pl < 1e-5) { px = -uy; py = ux; pz = 0; pl = Math.hypot(px, py) || 1; }
  }
  px /= pl; py /= pl; pz /= pl;
  const ca = Math.max(-1, Math.min(1, (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d))), sa = Math.sqrt(1 - ca * ca);
  // upper bone direction and frame
  const d1x = ux * ca + px * sa, d1y = uy * ca + py * sa, d1z = uz * ca + pz * sa;
  const qx = px * ca - ux * sa, qy = py * ca - uy * sa, qz = pz * ca - uz * sa; // perp toward the pole side
  Y[0] = -d1x; Y[1] = -d1y; Y[2] = -d1z;
  X[0] = -sign * qx; X[1] = -sign * qy; X[2] = -sign * qz;
  Z[0] = X[1] * Y[2] - X[2] * Y[1]; Z[1] = X[2] * Y[0] - X[0] * Y[2]; Z[2] = X[0] * Y[1] - X[1] * Y[0];
  qfromBasis(tq, 0, X, Y, Z);                     // upper model rotation
  const cb = Math.max(-1, Math.min(1, (l1 * l1 + l2 * l2 - d * d) / (2 * l1 * l2)));
  const bend = Math.PI - Math.acos(cb);
  oldL.set(lq.subarray(root * 4, root * 4 + 4), 0);
  oldL.set(lq.subarray(mid * 4, mid * 4 + 4), 4);
  oldL.set(lq.subarray(end * 4, end * 4 + 4), 8);
  qmulInv(newL, 0, mq, parent * 4, tq, 0);       // root local
  qaxis(newL, 4, 0, 0, 1, sign * bend);          // mid local (hinge about Z)
  qmul(tq, 4, tq, 0, newL, 4);                   // mid model
  qmulInv(newL, 8, tq, 4, er, eo);               // end local keeps / reaches the requested model orientation
  if (weight >= 1) {
    lq.set(newL.subarray(0, 4), root * 4); lq.set(newL.subarray(4, 8), mid * 4); lq.set(newL.subarray(8, 12), end * 4);
  } else {
    qslerp(lq, root * 4, oldL, 0, newL, 0, weight);
    qslerp(lq, mid * 4, oldL, 4, newL, 4, weight);
    qslerp(lq, end * 4, oldL, 8, newL, 8, weight);
  }
  return dist / lmax;
}

/** Default pole point direction for a limb -> tv[3..5] (relative to the limb root). */
function defaultPole(rig, limb, mq, mp, ux, uy, uz, er, eo, out) {
  if (limb.kind === 'arm') {
    // elbows point down / back / out in the chest frame
    const chest = rig.index.chest;
    qrot(out, 3, mq, chest * 4, -0.35, -1, limb.side * 0.75);
    // reaching high: let the elbow swing outward rather than flip
    if (uy > 0.2) { out[3] += 0; out[4] -= uy * 0.4; }
    return;
  }
  // knees track the toes: average of foot forward and hips forward (horizontal), slightly outward
  qrot(out, 6, er, eo, 1, 0, 0);
  qrot(out, 9, mq, rig.index.hips * 4, 1, 0, 0);
  let fx = out[6] + out[9] * 0.6, fz = out[8] + out[11] * 0.6;
  const l = Math.hypot(fx, fz) || 1;
  fx /= l; fz /= l;
  out[3] = fx; out[4] = 0.05; out[5] = fz + limb.side * 0.12;
}

/**
 * Keep a foot's sole and toe tip on or above the floor (model-space height floorY). Re-solves the leg if the sole
 * dips below the floor and rolls the toe up when the toe tip would sink. Call with FK up to date.
 */
export function floorFoot(rig, limb, lq, mq, mp, floorY, buf) {
  const P = rig.P, end = limb.end, toe = limb.toe;
  // lowest of heel / ankle-sole / ball points
  qrot(tv, 0, mq, end * 4, 0, -P.ankleHeight, 0);
  const sy = mp[end * 3 + 1] + tv[1];
  qrot(tv, 3, mq, end * 4, -P.heelLength, -P.ankleHeight + 0.01, 0);
  const hy = mp[end * 3 + 1] + tv[4];
  qrot(tv, 6, mq, toe * 4, 0, -(P.ankleHeight - P.footDrop), 0);
  const by = mp[toe * 3 + 1] + tv[7];
  const low = Math.min(sy, hy, by);
  if (low < floorY - 1e-4) {
    buf[0] = mp[end * 3] + tv[0]; buf[1] = sy + (floorY - low); buf[2] = mp[end * 3 + 2] + tv[2];
    qcopy(buf, 4, mq, end * 4);
    solveLimb(rig, limb, lq, mq, mp, buf, 0, buf, 4, null, 0, 1, 0.02);
    fk(rig, lq, null, mq, mp, limb.first, rig.count);
  }
  // toe roll: keep the toe tip above the floor
  qrot(tv, 0, mq, toe * 4, P.toeLength, -(P.ankleHeight - P.footDrop) + 0.005, 0);
  const tipY = mp[toe * 3 + 1] + tv[1];
  if (tipY < floorY) {
    const ang = Math.asin(Math.min(1, (floorY - tipY) / P.toeLength));
    qaxis(tv, 0, 0, 0, 1, ang);
    qmul(lq, toe * 4, tv, 0, lq, toe * 4);
  }
}

const lookTmp = new Float32Array(16);

/**
 * Rotate neck (40%) and head (60%) so the head's +X faces `target` (model space), limited to `maxDeg`.
 */
export function solveLook(rig, lq, mq, mp, target, to, weight, maxDeg = 75) {
  if (weight <= 0) return;
  const chest = rig.index.chest, neck = rig.index.neck, head = rig.index.head;
  let dx = target[to] - mp[head * 3], dy = target[to + 1] - mp[head * 3 + 1] - 0.08, dz = target[to + 2] - mp[head * 3 + 2];
  const l = Math.hypot(dx, dy, dz);
  if (l < 1e-4) return;
  dx /= l; dy /= l; dz /= l;
  // into the chest frame
  const c4 = chest * 4;
  lookTmp[0] = -mq[c4]; lookTmp[1] = -mq[c4 + 1]; lookTmp[2] = -mq[c4 + 2]; lookTmp[3] = mq[c4 + 3];
  qrot(lookTmp, 4, lookTmp, 0, dx, dy, dz);
  qrot(lookTmp, 7, mq, head * 4, 1, 0, 0);
  qrot(lookTmp, 7, lookTmp, 0, lookTmp[7], lookTmp[8], lookTmp[9]);
  qfromTo(lookTmp, 10, lookTmp[7], lookTmp[8], lookTmp[9], lookTmp[4], lookTmp[5], lookTmp[6]);
  // limit + weight
  const w = lookTmp[13];
  let ang = 2 * Math.acos(Math.max(-1, Math.min(1, w)));
  const max = (maxDeg * Math.PI) / 180;
  const k = (ang > max ? max / ang : 1) * weight;
  const s = Math.sqrt(Math.max(1e-12, 1 - w * w));
  const axx = lookTmp[10] / s, axy = lookTmp[11] / s, axz = lookTmp[12] / s;
  if (!(ang > 1e-4)) return;
  ang *= k;
  // neck: rotation in the chest (= neck parent) frame
  qaxis(lookTmp, 0, axx, axy, axz, ang * 0.4);
  qmul(lq, neck * 4, lookTmp, 0, lq, neck * 4);
  // head: same axis expressed in the neck frame
  qaxis(lookTmp, 4, axx, axy, axz, ang * 0.6);
  qmulInv(lookTmp, 8, lq, neck * 4, lookTmp, 4);
  qmul(lookTmp, 8, lookTmp, 8, lq, neck * 4);
  qmul(lq, head * 4, lookTmp, 8, lq, head * 4);
}
