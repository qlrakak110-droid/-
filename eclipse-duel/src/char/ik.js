// Inverse kinematics on model-space (fighter-local) arrays: analytic two-bone limbs with pole hints and soft reach,
// arm extras (clavicle assist, elbow swivel chosen to keep the wrist in its human range, off-hand roll around a weapon
// grip), floor / toe contact for feet, and a distributed neck + head look-at. All functions read the current FK result
// (mq / mp) and write local rotations (lq); callers re-run FK on the affected range afterwards.

import { qmul, qmulInv, qrot, qslerp, qfromBasis, qaxis, qfromTo, qcopy, softLimit, smooth01 } from './rigmath.js';
import { fk } from './skeleton.js';

/** Default soft-reach fraction (of l1 + l2) where the limb starts to ease into full extension. 0 = can lock straight. */
export const SOFT = 0.006;
/** Wrist range used by the arm solver (radians): swing of the hand off the forearm axis, pronation / supination. */
export const WRIST = { swing: (85 * Math.PI) / 180, twist: (90 * Math.PI) / 180, swingKnee: (68 * Math.PI) / 180, twistKnee: (74 * Math.PI) / 180 };

/**
 * Limb descriptors for a rig: handR, handL, footR, footL.
 * endOff = the effector point in the end bone's frame (hands: centre of the fist / grip axis; feet: the sole point
 * straight below the ankle). Arms also carry the weapon bone (its rest rotation in the hand is the grip angle).
 */
export function makeLimbs(rig) {
  const ix = rig.index, P = rig.P, out = {};
  for (const [s, z] of [['R', 1], ['L', -1]]) {
    out['hand' + s] = {
      kind: 'arm', side: z, sign: 1, clav: ix['shoulder' + s], parent: ix['shoulder' + s], root: ix['upperArm' + s], mid: ix['foreArm' + s], end: ix['hand' + s],
      weapon: ix['weapon' + s], chest: ix.chest,
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
const sv = new Float32Array(32); // swivel search scratch
const rollQ = new Float32Array(8);

/**
 * Arm / leg geometry for one swivel angle phi: writes the upper-bone model rotation into out[oo..] and the end bone's
 * local rotation (relative to the solved middle bone) into out[oo + 4..]; needs the frame set up by solveLimb (sv).
 */
function limbAt(phi, sign, bend, endQ, eo, out, oo) {
  const c = Math.cos(phi), s = Math.sin(phi);
  const px = sv[3] * c + sv[6] * s, py = sv[4] * c + sv[7] * s, pz = sv[5] * c + sv[8] * s;
  const ux = sv[0], uy = sv[1], uz = sv[2], ca = sv[9], sa = sv[10];
  const d1x = ux * ca + px * sa, d1y = uy * ca + py * sa, d1z = uz * ca + pz * sa;
  const qx = px * ca - ux * sa, qy = py * ca - uy * sa, qz = pz * ca - uz * sa;
  Y[0] = -d1x; Y[1] = -d1y; Y[2] = -d1z;
  X[0] = -sign * qx; X[1] = -sign * qy; X[2] = -sign * qz;
  Z[0] = X[1] * Y[2] - X[2] * Y[1]; Z[1] = X[2] * Y[0] - X[0] * Y[2]; Z[2] = X[0] * Y[1] - X[1] * Y[0];
  qfromBasis(out, oo, X, Y, Z);
  qaxis(sv, 12, 0, 0, 1, sign * bend);
  qmul(sv, 16, out, oo, sv, 12);          // middle bone model rotation
  qmulInv(out, oo + 4, sv, 16, endQ, eo); // end local
}

/** Swivel search state (module scope: the search allocates nothing). */
const S = { sign: 1, bend: 0, er: null, eo: 0, mq: null, po: 0, phi0: 0, mem: 0, prev: 0, body: null, l1: 0, rx: 0, ry: 0, rz: 0 };
function swivelCost(f) {
  limbAt(f, S.sign, S.bend, S.er, S.eo, sv, 20);
  let c = armCost(sv, 20, 24, S.mq, S.po) + 0.7 * (1 - Math.cos(f - S.phi0)) + (S.mem ? 4 * (1 - Math.cos(f - S.prev)) : 0);
  const B = S.body;
  if (B) { // elbow inside the torso (capsule B: a, b, radius incl. the arm): push the elbow out of the body
    const cf = Math.cos(f), sf = Math.sin(f);
    const px = sv[3] * cf + sv[6] * sf, py = sv[4] * cf + sv[7] * sf, pz = sv[5] * cf + sv[8] * sf;
    const ex = S.rx + S.l1 * (sv[0] * sv[9] + px * sv[10]), ey = S.ry + S.l1 * (sv[1] * sv[9] + py * sv[10]), ez = S.rz + S.l1 * (sv[2] * sv[9] + pz * sv[10]);
    const sx = B[3] - B[0], sy = B[4] - B[1], sz = B[5] - B[2], qx = ex - B[0], qy = ey - B[1], qz = ez - B[2];
    const t = Math.max(0, Math.min(1, (qx * sx + qy * sy + qz * sz) / (sx * sx + sy * sy + sz * sz || 1)));
    const pen = B[6] - Math.hypot(qx - sx * t, qy - sy * t, qz - sz * t);
    if (pen > 0) c += (pen / (0.05 * B[7])) ** 2;
  }
  return c;
}

/**
 * Smooth arm comfort cost of a candidate swivel: hand pronation / supination (twist about the forearm), wrist bend
 * (swing off the forearm axis) and humeral rotation (upper-arm twist relative to the clavicle, faded out near the
 * overhead singularity). Periodic and smooth in the swivel, so the best swivel moves continuously with the target.
 * u = upper-bone model rotation (sv offset uo), e = end local rotation (offset eo), pq = parent model rotation.
 */
function armCost(q, uo, eo, pq, po) {
  let w = q[eo + 3], y = q[eo + 1];
  if (w < 0) { w = -w; y = -y; }
  const tw = 2 * Math.atan2(y, w);
  const cs = 1 - 2 * (q[eo] * q[eo] + q[eo + 2] * q[eo + 2]); // cos of the wrist swing
  // upper arm local = parent^-1 * upper (model)
  qmulInv(sv, 28, pq, po, q, uo);
  let uw = sv[31], uy = sv[29];
  if (uw < 0) { uw = -uw; uy = -uy; }
  const ucs = 1 - 2 * (sv[28] * sv[28] + sv[30] * sv[30]);   // cos of the arm elevation (swing from hanging)
  const fade = smooth01(-ucs, 0.85, 0.35);                  // full below ~110 deg of elevation, none above ~150
  const ut = 2 * Math.atan2(uy, uw) + 0.09;                 // humeral rotation, centred on its range (-90..80)
  const ex = Math.max(0, Math.abs(tw) - 1.1), eu = Math.max(0, Math.abs(ut) - 1.2); // beyond ~63 / ~69 deg: steep
  return 1.0 * (1 - Math.cos(tw)) + 3 * ex * ex + 0.8 * (1 - cs) + fade * (0.6 * (1 - Math.cos(ut)) + 3 * eu * eu);
}

/**
 * Off-hand roll about the weapon grip axis that brings the hand's long axis closest to the forearm: rotates the target
 * end rotation endQ (model) about its own grip axis (gx, gy, gz in the end frame) by the best angle, blended toward
 * the authored roll by `keep` (0 = free). Writes the rolled end rotation into rollQ[0..3].
 */
function bestRoll(endQ, eo, fq, fo, gx, gy, gz, keep) {
  // forearm long axis (model) -> end frame
  qrot(tv, 0, fq, fo, 0, -1, 0);
  rollQ[4] = -endQ[eo]; rollQ[5] = -endQ[eo + 1]; rollQ[6] = -endQ[eo + 2]; rollQ[7] = endQ[eo + 3];
  qrot(tv, 3, rollQ, 4, tv[0], tv[1], tv[2]);
  // hand long axis a = -Y in the end frame; roll about g: maximise (R(g, psi) a) . f
  const ax = 0, ay = -1, az = 0;
  const ad = ax * gx + ay * gy + az * gz;
  const a1x = ax - gx * ad, a1y = ay - gy * ad, a1z = az - gz * ad;      // a perpendicular to g
  const a2x = gy * a1z - gz * a1y, a2y = gz * a1x - gx * a1z, a2z = gx * a1y - gy * a1x; // g x a1
  const f1 = a1x * tv[3] + a1y * tv[4] + a1z * tv[5], f2 = a2x * tv[3] + a2y * tv[4] + a2z * tv[5];
  let psi = Math.atan2(f2, f1);
  psi *= 1 - keep;
  qaxis(rollQ, 4, gx, gy, gz, psi);
  qmul(rollQ, 0, endQ, eo, rollQ, 4);
}

/**
 * Two-bone IK. target: Float32Array/array [x,y,z] (model space, effector point), rot: quaternion array or null (keep
 * the end bone's current model orientation), pole: point [x,y,z] or null (default pole), weight 0..1, soft = soft-reach
 * fraction (0 = may lock straight). Arms (opt, all optional):
 *   clavicle = 1    shoulder (clavicle) assist toward targets near / beyond reach (elevation + protraction, <= 24 deg)
 *   wrist = true    swivel the elbow around the shoulder-wrist axis to keep the hand within its human range
 *                   (swing <= 85 deg, pronation / supination <= 90 deg), then softly clamp what is left
 *   roll = null     [gx, gy, gz]: grip axis in the end frame around which the hand may roll freely (two-handed grip)
 *   rollKeep = 0.25 how strongly the authored roll is kept (0 = free)
 *   phi = 0         preferred swivel (rad) relative to the pole
 *   mem             Float32Array(3) [swivel, valid, wrist twist] kept by the caller per limb: hysteresis against elbow
 *                   flips and against the clamped wrist jumping between its two twist limits
 *   keepLocal       with rot = null: keep the end bone's local rotation (wrist pose) instead of its model rotation
 *   body            Float32Array(8) torso capsule [a (3), b (3), radius + arm radius, body scale]: elbows stay out of it
 * Returns the reach ratio (dist / max length) before softening.
 */
export function solveLimb(rig, limb, lq, mq, mp, target, to, rot, ro, pole, po, weight, soft = SOFT, opt = null) {
  if (weight <= 0) return 0;
  const { root, mid, end, parent, sign } = limb;
  const arm = limb.kind === 'arm';
  if (soft < 0) soft = SOFT;
  // clavicle assist (arms): rotate the shoulder toward a target near / past full reach
  if (arm && (!opt || opt.clavicle !== 0)) clavicleAssist(rig, limb, lq, mq, mp, target, to, rot, ro, weight * (opt && opt.clavicle !== undefined ? opt.clavicle : 1));
  // requested end orientation (model); null = keep the current one (opt.keepLocal: keep the end bone's local
  // rotation instead, i.e. the wrist pose follows the new forearm)
  qcopy(endModel, 0, rot || mq, rot ? ro : end * 4);
  let er = endModel, eo = 0;
  let bend = limbSetup(rig, limb, mq, mp, target, to, er, eo, pole, po, soft);
  const keepLocal = !rot && opt && opt.keepLocal;
  if (keepLocal) { // the FK wrist pose rides the new forearm (no wrist search / clamp needed: it is the authored pose)
    for (let it = 0; it < 3; it++) {
      limbAt(opt.phi || 0, sign, bend, er, eo, tq, 0);
      qmul(endModel, 0, sv, 16, lq, end * 4); // new forearm (model) x FK wrist pose
      bend = limbSetup(rig, limb, mq, mp, target, to, er, eo, pole, po, soft);
    }
  }
  qcopy(oldL, 0, lq, root * 4); qcopy(oldL, 4, lq, mid * 4); qcopy(oldL, 8, lq, end * 4);
  let phi = opt && opt.phi ? opt.phi : 0;
  const roll = arm && opt && opt.roll;
  const keep = opt && opt.rollKeep !== undefined ? opt.rollKeep : 0.25;
  const wrist = arm && !keepLocal && (!opt || opt.wrist !== false);
  // a two-handed grip lets the hand roll around the grip axis: pick the roll that suits the forearm. Rolling moves
  // the wrist (the axis runs through the fist), so the limb geometry is set up again for the rolled hand.
  if (roll) {
    limbAt(phi, sign, bend, er, eo, tq, 0);
    bestRoll(endModel, 0, sv, 16, roll[0], roll[1], roll[2], keep);
    qcopy(tq, 8, rollQ, 0); er = tq; eo = 8;
    bend = limbSetup(rig, limb, mq, mp, target, to, er, eo, pole, po, soft);
  }
  limbAt(phi, sign, bend, er, eo, tq, 0);
  if (wrist) {
    // swivel search: cost = arm comfort + a pull back to the pole (keeps the authored elbow when the arm is at ease)
    // + a pull toward last frame's swivel (mem): two near-equal solutions never make the elbow flip between frames
    const phi0 = phi, mem = opt && opt.mem, hasMem = mem && mem[1] > 0, prev = hasMem ? mem[0] : 0;
    S.sign = sign; S.bend = bend; S.er = er; S.eo = eo; S.mq = mq; S.po = parent * 4; S.phi0 = phi0; S.mem = hasMem ? 1 : 0; S.prev = prev;
    S.body = opt && opt.body; S.l1 = limb.l1; S.rx = mp[root * 3]; S.ry = mp[root * 3 + 1]; S.rz = mp[root * 3 + 2];
    let best = phi0, bc = swivelCost(phi0);
    if (hasMem) { // track last frame's solution: search a window around it (no jumps to the far side of the circle)
      best = prev; bc = swivelCost(prev);
      for (let i = -8; i <= 8; i++) {
        if (!i) continue;
        const f = prev + i * (Math.PI / 48), c = swivelCost(f);
        if (c < bc - 1e-9) { bc = c; best = f; }
      }
      const c0 = swivelCost(phi0);
      if (c0 < bc - 1e-9) { bc = c0; best = phi0; }
    } else {
      for (let i = 1; i < 24; i++) {
        const f = phi0 + (i < 12 ? i : i - 24) * (Math.PI / 12);
        const c = swivelCost(f);
        if (c < bc - 1e-9) { bc = c; best = f; }
      }
    }
    const span = hasMem ? Math.PI / 48 : Math.PI / 12;
    let lo = best - span, hi = best + span; // golden-section refine
    const g = 0.381966;
    let a1 = lo + g * (hi - lo), b1 = hi - g * (hi - lo), ca1 = swivelCost(a1), cb1 = swivelCost(b1);
    for (let it = 0; it < 8; it++) {
      if (ca1 < cb1) { hi = b1; b1 = a1; cb1 = ca1; a1 = lo + g * (hi - lo); ca1 = swivelCost(a1); }
      else { lo = a1; a1 = b1; ca1 = cb1; b1 = hi - g * (hi - lo); cb1 = swivelCost(b1); }
    }
    phi = ca1 < cb1 ? a1 : b1;
    if (swivelCost(phi) > bc) phi = best;
    phi = Math.atan2(Math.sin(phi), Math.cos(phi));
    if (roll) {
      limbAt(phi, sign, bend, er, eo, tq, 0);
      bestRoll(endModel, 0, sv, 16, roll[0], roll[1], roll[2], keep);
      qcopy(tq, 8, rollQ, 0); er = tq; eo = 8;
      bend = limbSetup(rig, limb, mq, mp, target, to, er, eo, pole, po, soft);
    }
    limbAt(phi, sign, bend, er, eo, tq, 0);
  }
  qcopy(newL, 8, tq, 4);                         // end local keeps / reaches the requested model orientation
  const wm = opt && opt.mem && opt.mem.length > 2 ? opt.mem : null;
  if (wrist && clampWrist(newL, 8, wm)) {
    // the wrist could not take the requested orientation: keep the clamped wrist pose (relative to the forearm) and
    // solve the reach again for it, so the fist (not the wrist) stays on the target
    qcopy(rollQ, 4, newL, 8);                     // clamped local wrist pose
    for (let it = 0; it < 4; it++) {
      qaxis(sv, 12, 0, 0, 1, sign * bend);
      qmul(sv, 16, tq, 0, sv, 12);                // forearm (model)
      qmul(tq, 8, sv, 16, rollQ, 4);              // end model rotation for that wrist pose
      er = tq; eo = 8;
      bend = limbSetup(rig, limb, mq, mp, target, to, er, eo, pole, po, soft);
      limbAt(phi, sign, bend, er, eo, tq, 0);
    }
    qcopy(newL, 8, tq, 4);
  }
  qmulInv(newL, 0, mq, parent * 4, tq, 0);       // root local
  qaxis(newL, 4, 0, 0, 1, sign * bend);          // mid local (hinge about Z)
  if (weight >= 1) {
    qcopy(lq, root * 4, newL, 0); qcopy(lq, mid * 4, newL, 4); qcopy(lq, end * 4, newL, 8);
  } else {
    qslerp(lq, root * 4, oldL, 0, newL, 0, weight);
    qslerp(lq, mid * 4, oldL, 4, newL, 4, weight);
    qslerp(lq, end * 4, oldL, 8, newL, 8, weight);
  }
  if (opt && opt.out) qcopy(opt.out, 0, er, eo);
  if (opt && opt.mem) { opt.mem[0] = phi; opt.mem[1] = 1; }
  return sv[11];
}

/**
 * Reach geometry for a target and an end orientation: wrist point, reach direction u, softened distance, pole frame
 * (e1 = pole perpendicular to u, e2 = u x e1), upper-bone angle -> sv[0..11]. Returns the middle-joint bend angle.
 */
function limbSetup(rig, limb, mq, mp, target, to, er, eo, pole, po, soft) {
  const { root, mid, l1, l2, endOff } = limb;
  qrot(tv, 0, er, eo, endOff[0], endOff[1], endOff[2]);
  const wx = target[to] - tv[0], wy = target[to + 1] - tv[1], wz = target[to + 2] - tv[2];
  const ax = mp[root * 3], ay = mp[root * 3 + 1], az = mp[root * 3 + 2];
  const dx = wx - ax, dy = wy - ay, dz = wz - az;
  const dist = Math.hypot(dx, dy, dz) || 1e-6;
  const ux = dx / dist, uy = dy / dist, uz = dz / dist;
  const lmax = l1 + l2, lmin = Math.abs(l1 - l2) + 1e-3;
  let d = dist;
  const ds = lmax * (1 - soft);
  if (d > ds) d = soft > 1e-6 ? ds + (lmax - ds) * (1 - Math.exp(-(d - ds) / (lmax - ds))) : lmax;
  if (d < lmin) d = lmin;
  let px, py, pz;
  if (pole) { px = pole[po] - ax; py = pole[po + 1] - ay; pz = pole[po + 2] - az; }
  else { defaultPole(rig, limb, mq, er, eo, ux, uy, uz, tv); px = tv[3]; py = tv[4]; pz = tv[5]; }
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
  const cb = Math.max(-1, Math.min(1, (l1 * l1 + l2 * l2 - d * d) / (2 * l1 * l2)));
  sv[0] = ux; sv[1] = uy; sv[2] = uz; sv[3] = px; sv[4] = py; sv[5] = pz;
  sv[6] = uy * pz - uz * py; sv[7] = uz * px - ux * pz; sv[8] = ux * py - uy * px;
  sv[9] = ca; sv[10] = sa; sv[11] = dist / lmax;
  return Math.PI - Math.acos(cb);
}

/** Soft-limit a hand local rotation to the wrist range (swing off the forearm axis, pronation / supination). True if changed. */
function clampWrist(q, o, mem = null) {
  let x = q[o], y = q[o + 1], z = q[o + 2], w = q[o + 3];
  if (w < 0) { x = -x; y = -y; z = -z; w = -w; }
  let tw = 2 * Math.atan2(y, w);
  // a demand past +-180 deg stays on last frame's side (the clamped hand does not flip to the other limit)
  if (mem && mem[2] !== 0 && Math.abs(tw) > 2.4 && Math.abs(mem[2]) > 1.0 && Math.sign(tw) !== Math.sign(mem[2])) tw += tw < 0 ? 2 * Math.PI : -2 * Math.PI;
  const sw = Math.acos(Math.max(-1, Math.min(1, 1 - 2 * (x * x + z * z))));
  const tw2 = softLimit(tw, WRIST.twistKnee, WRIST.twist), sw2 = softLimit(sw, WRIST.swingKnee, WRIST.swing);
  if (mem) mem[2] = tw2;
  if (Math.abs(tw2 - tw) < 1e-6 && Math.abs(sw2 - sw) < 1e-6) return false;
  // swing = q * conj(twist), twist = (0, sin(tw/2), 0, cos(tw/2))
  const ct = Math.cos(tw / 2), st = Math.sin(tw / 2);
  let sx = x * ct + z * st, sz = z * ct - x * st, sw0 = w * ct + y * st;
  const sl = Math.hypot(sx, sz);
  if (sl > 1e-9) { const h = Math.sin(sw2 / 2) / sl; sx *= h; sz *= h; sw0 = Math.cos(sw2 / 2); }
  // q' = swing' * twist'
  const c2 = Math.cos(tw2 / 2), s2 = Math.sin(tw2 / 2);
  q[o] = sx * c2 - sz * s2;
  q[o + 1] = sw0 * s2;
  q[o + 2] = sz * c2 + sx * s2;
  q[o + 3] = sw0 * c2;
  return true;
}

const cl = new Float32Array(16);
/**
 * Clavicle assist: rotate the shoulder bone (in the chest frame) so the shoulder joint moves toward a target the arm
 * can barely or not reach. Ramps in from 82% of the reach, at most 24 deg (12 deg downward), smooth in the target.
 */
function clavicleAssist(rig, limb, lq, mq, mp, target, to, rot, ro, w) {
  if (!(w > 0)) return;
  const c = limb.clav, r = limb.root, par = rig.parent[c];
  // wrist target
  const er = rot || mq, eo = rot ? ro : limb.end * 4;
  qrot(cl, 0, er, eo, limb.endOff[0], limb.endOff[1], limb.endOff[2]);
  const tx = target[to] - cl[0], ty = target[to + 1] - cl[1], tz = target[to + 2] - cl[2];
  const sx = mp[r * 3], sy = mp[r * 3 + 1], sz = mp[r * 3 + 2];
  const lmax = limb.l1 + limb.l2;
  const ratio = Math.hypot(tx - sx, ty - sy, tz - sz) / lmax;
  const k = smooth01(ratio, 0.82, 1.12) * w;
  if (k <= 0) return;
  // rotation of the clavicle vector (root -> shoulder joint) toward the target, from the clavicle root
  const cx = mp[c * 3], cy = mp[c * 3 + 1], cz = mp[c * 3 + 2];
  let ax = sx - cx, ay = sy - cy, az = sz - cz, bx = tx - cx, by = ty - cy, bz = tz - cz;
  const la = Math.hypot(ax, ay, az) || 1, lb = Math.hypot(bx, by, bz) || 1;
  ax /= la; ay /= la; az /= la; bx /= lb; by /= lb; bz /= lb;
  let nx = ay * bz - az * by, ny = az * bx - ax * bz, nz = ax * by - ay * bx;
  const sn = Math.hypot(nx, ny, nz);
  if (sn < 1e-6) return;
  nx /= sn; ny /= sn; nz /= sn;
  const full = Math.atan2(sn, ax * bx + ay * by + az * bz);
  // about half of the remaining angle, softly limited to 24 deg; the clavicle depresses far less than it elevates
  let ang = softLimit(full * 0.55 * k, 0.25, 0.42);
  const moveY = nz * ax - nx * az; // vertical direction the shoulder joint moves (y of n x a)
  if (moveY < 0) ang *= 1 + 0.55 * moveY;
  qaxis(cl, 4, nx, ny, nz, ang);
  qmul(cl, 8, cl, 4, mq, c * 4);           // new clavicle model rotation
  qmulInv(lq, c * 4, mq, par * 4, cl, 8);
  fk(rig, lq, rig.offset, mq, mp, c, r + 1); // clavicle + upper-arm root (their local positions are the rest offsets)
}

/** Default pole point direction for a limb -> tv[3..5] (relative to the limb root). u = reach direction. */
function defaultPole(rig, limb, mq, er, eo, ux, uy, uz, out) {
  if (limb.kind === 'arm') {
    // elbows point down / back / out in the chest frame
    const chest = rig.index.chest;
    qrot(out, 3, mq, chest * 4, -0.35, -1, limb.side * 0.75);
    return;
  }
  // knees track the toes: average of foot forward and hips forward (horizontal), slightly outward
  qrot(out, 6, er, eo, 1, 0, 0);
  qrot(out, 9, mq, rig.index.hips * 4, 1, 0, 0);
  let fx = out[6] + out[9] * 0.6, fz = out[8] + out[11] * 0.6;
  const l = Math.hypot(fx, fz) || 1;
  fx /= l; fz /= l;
  let px = fx, py = 0.05, pz = fz + limb.side * 0.12;
  // a foot in front at hip height (kick, knee raise) puts the reach on that line: lift the knee instead (hips up);
  // a foot behind at hip height drops it. Blended in continuously, so the knee never whips sideways.
  const pn = Math.hypot(px, py, pz) || 1;
  const along = (px * ux + py * uy + pz * uz) / pn;
  const k = smooth01(Math.abs(along), 0.55, 0.9) * 1.6 * Math.sign(along);
  if (k !== 0) {
    qrot(out, 6, mq, rig.index.hips * 4, 0, 1, 0);
    px += out[6] * k; py += out[7] * k; pz += out[8] * k;
  }
  out[3] = px; out[4] = py; out[5] = pz;
}

/**
 * Keep a foot's sole and toe tip on or above the floor (model-space height floorY). Re-solves the leg if a sole point
 * (heel, under the ankle, ball pad) dips below the floor, then bends the toe about its joint so the toe tip lands
 * exactly on the floor. Call with FK up to date.
 */
export function floorFoot(rig, limb, lq, lp, mq, mp, floorY, buf) {
  const P = rig.P, end = limb.end, toe = limb.toe;
  // lowest of heel / ankle-sole / ball pad (all on the foot bone's sole plane)
  qrot(tv, 0, mq, end * 4, 0, -P.ankleHeight, 0);
  const sy = mp[end * 3 + 1] + tv[1];
  qrot(tv, 3, mq, end * 4, -P.heelLength, -P.ankleHeight, 0);
  const hy = mp[end * 3 + 1] + tv[4];
  qrot(tv, 6, mq, end * 4, P.footLength, -P.ankleHeight, 0);
  const by = mp[end * 3 + 1] + tv[7];
  const low = Math.min(sy, hy, by);
  if (low < floorY - 1e-5) {
    buf[0] = mp[end * 3] + tv[0]; buf[1] = sy + (floorY - low); buf[2] = mp[end * 3 + 2] + tv[2];
    qcopy(buf, 4, mq, end * 4);
    solveLimb(rig, limb, lq, mq, mp, buf, 0, buf, 4, null, 0, 1, 0);
    fk(rig, lq, lp, mq, mp, limb.first, rig.count);
  }
  // toe: rotate about the toe joint (its Z axis) until the tip is on the floor
  const th = P.ankleHeight - P.footDrop;
  qrot(tv, 0, mq, toe * 4, P.toeLength, -th, 0);
  const tipY = mp[toe * 3 + 1] + tv[1];
  if (tipY < floorY) {
    const vx = tv[0], vy = tv[1], vz = tv[2];
    qrot(tv, 3, mq, toe * 4, 0, 0, 1); // rotation axis (model)
    const zx = tv[3], zy = tv[4], zz = tv[5];
    const zv = zx * vx + zy * vy + zz * vz;
    // y(a) = A cos a + B sin a + C
    const A = vy - zy * zv, B = zz * vx - zx * vz, C = zy * zv;
    const R = Math.hypot(A, B), goal = floorY - mp[toe * 3 + 1] - C;
    if (R > 1e-6) {
      const del = Math.atan2(B, A), c = Math.max(-1, Math.min(1, goal / R));
      const a1 = del + Math.acos(c), a2 = del - Math.acos(c);
      const wrap = (a) => Math.atan2(Math.sin(a), Math.cos(a));
      const b1 = wrap(a1), b2 = wrap(a2);
      // toes-up solutions are positive; take the smallest positive rotation
      let ang = b1 >= 0 && (b2 < 0 || b1 < b2) ? b1 : b2 >= 0 ? b2 : Math.max(b1, b2);
      ang = Math.max(0, Math.min(1.4, ang));
      qaxis(tv, 0, 0, 0, 1, ang);
      qmul(lq, toe * 4, lq, toe * 4, tv, 0);
    }
  }
}

const lookTmp = new Float32Array(16);

/**
 * Rotate neck (40%) and head (60%) so the head's +X faces `target` (model space), limited to `maxDeg`. `eye` = height of
 * the eyes above the head pivot (m).
 */
export function solveLook(rig, lq, mq, mp, target, to, weight, maxDeg = 75, eye = 0.08 * (rig.k || 1)) {
  if (weight <= 0) return;
  const chest = rig.index.chest, neck = rig.index.neck, head = rig.index.head;
  let dx = target[to] - mp[head * 3], dy = target[to + 1] - mp[head * 3 + 1] - eye, dz = target[to + 2] - mp[head * 3 + 2];
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
