// Inverse kinematics on model-space (fighter-local) arrays: analytic two-bone limbs with pole hints and soft reach,
// arm extras (clavicle assist, a continuous elbow swivel chosen to keep the wrist in its human range and the arm out of
// the torso, off-hand roll around a weapon grip), floor / toe contact for feet, and a neck + head look-at by yaw /
// pitch. All functions read the current FK result (mq / mp) and write local rotations (lq); callers re-run FK on the
// affected range afterwards.

import { qmul, qmulInv, qrot, qslerp, qfromBasis, qaxis, qfromTo, qcopy, softLimit, smooth01, setSwingTwist } from './rigmath.js';
import { fk } from './skeleton.js';

/** Default soft-reach fraction (of l1 + l2) where the limb starts to ease into full extension. 0 = can lock straight. */
export const SOFT = 0.006;
/** Wrist range used by the arm solver (radians): swing of the hand off the forearm axis, pronation / supination. */
export const WRIST = { swing: (85 * Math.PI) / 180, twist: (90 * Math.PI) / 180, swingKnee: (68 * Math.PI) / 180, twistKnee: (74 * Math.PI) / 180 };
/**
 * Elbow swivel continuity (arm memory, see solveLimb opt.mem): the swivel follows the minimum of the cost basin it is
 * in (a minimum that moved more than TRACK x dt since last frame - its basin merged into another - is travelled to),
 * and moves to a better basin only when its own is strained (cost > SWITCH_MIN) and the other has been clearly cheaper
 * (by max(SWITCH_MARGIN, 40%)) for SWITCH_HOLD s, travelling at up to SWITCH rad/s (eased in and out: the elbow rolls
 * over instead of flipping in one frame). Rates are per second of game time, so the path is the same at 30 / 60 /
 * 120 Hz.
 */
export const SWIVEL = { TRACK: (1800 * Math.PI) / 180, SWITCH: (450 * Math.PI) / 180, SWITCH_MARGIN: 0.3, SWITCH_MIN: 0.8, SWITCH_HOLD: 0.06 };
/**
 * Floats per arm memory: previous frame [elbow dir (3, chest frame), valid, switch timer, grip roll, travel direction,
 * hand twist] + this frame (the same 8).
 */
export const MEM = 16;
/** Copy this frame's arm memory into the previous-frame slot (once per update, before any solve of that memory). */
export function commitMem(m, o = 0) { for (let k = 0; k < 8; k++) m[o + k] = m[o + 8 + k]; }
/** Fastest the wrist clamp turns the hand about the forearm (rad/s): a request sweeping through an impossible pronation. */
const WRIST_RATE = (1500 * Math.PI) / 180;

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
let reachD = 0; // softened shoulder -> wrist distance of the last limbSetup

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
const S = { sign: 1, bend: 0, er: null, eo: 0, mq: null, po: 0, phi0: 0, body: null, l1: 0, d: 0, rx: 0, ry: 0, rz: 0 };
/** Penetration (m) of point (x, y, z) into the torso capsule B (a, b, radius incl. the arm). */
function bodyPen(B, x, y, z) {
  const sx = B[3] - B[0], sy = B[4] - B[1], sz = B[5] - B[2], qx = x - B[0], qy = y - B[1], qz = z - B[2];
  const t = Math.max(0, Math.min(1, (qx * sx + qy * sy + qz * sz) / (sx * sx + sy * sy + sz * sz || 1)));
  return B[6] - Math.hypot(qx - sx * t, qy - sy * t, qz - sz * t);
}
function swivelCost(f) {
  limbAt(f, S.sign, S.bend, S.er, S.eo, sv, 20);
  let c = armCost(sv, 20, 24, S.mq, S.po) + 0.7 * (1 - Math.cos(f - S.phi0));
  const B = S.body;
  if (B) { // elbow and mid-forearm inside the torso (capsule B: a, b, radius incl. the arm): push the arm out of the body
    const cf = Math.cos(f), sf = Math.sin(f);
    const px = sv[3] * cf + sv[6] * sf, py = sv[4] * cf + sv[7] * sf, pz = sv[5] * cf + sv[8] * sf;
    const ex = S.rx + S.l1 * (sv[0] * sv[9] + px * sv[10]), ey = S.ry + S.l1 * (sv[1] * sv[9] + py * sv[10]), ez = S.rz + S.l1 * (sv[2] * sv[9] + pz * sv[10]);
    const wx = S.rx + sv[0] * S.d, wy = S.ry + sv[1] * S.d, wz = S.rz + sv[2] * S.d;
    const k = 0.05 * B[7];
    let pen = bodyPen(B, ex, ey, ez);
    if (pen > 0) c += (pen / k) ** 2;
    pen = bodyPen(B, (ex + wx) * 0.5, (ey + wy) * 0.5, (ez + wz) * 0.5);
    if (pen > 0) c += (pen / k) ** 2;
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
  // (the steep part of the humeral term never fades out completely: an overhead arm wrung past ~120 deg is no arm,
  // and it is where the helper bones' swing / twist split is singular)
  return 1.0 * (1 - Math.cos(tw)) + 3 * ex * ex + 0.8 * (1 - cs) + fade * 0.6 * (1 - Math.cos(ut)) + (0.3 + 0.7 * fade) * 3 * eu * eu;
}

/**
 * Off-hand roll about the weapon grip axis that brings the hand's long axis closest to the forearm (fq: forearm model
 * rotation), for the target end rotation endQ (model) and grip axis (gx, gy, gz) in the end frame. Returns the roll
 * (rad), continued from `ref` (NaN: none) so a roll near 180 deg keeps its side.
 */
function bestRoll(endQ, eo, fq, fo, gx, gy, gz, ref) {
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
  const psi = Math.atan2(f2, f1);
  return Number.isFinite(ref) ? psi + 2 * Math.PI * Math.round((ref - psi) / (2 * Math.PI)) : psi;
}
/** rollQ[0..3] = endQ rotated about its own axis (gx, gy, gz) by psi. */
function rollBy(endQ, eo, gx, gy, gz, psi) {
  qaxis(rollQ, 4, gx, gy, gz, psi);
  qmul(rollQ, 0, endQ, eo, rollQ, 4);
}

const wrapA = (a) => Math.atan2(Math.sin(a), Math.cos(a));
/** |humeral rotation| (rad) of the upper arm at swivel f (the frame set up for swivelCost). */
function humeralAt(f) {
  limbAt(f, S.sign, S.bend, S.er, S.eo, sv, 20);
  qmulInv(sv, 28, S.mq, S.po, sv, 20);
  let uw = sv[31], uy = sv[29];
  if (uw < 0) { uw = -uw; uy = -uy; }
  return Math.abs(2 * Math.atan2(uy, uw));
}
/**
 * Direction (+1 / -1) to travel from swivel a to b: the way on which the humeral rotation stays smaller (the elbow rolls
 * over through a strained wrist, which the wrist clamp keeps human, rather than through an upper arm wrung past
 * 150 deg, which no shoulder can do); ties: the shorter way.
 */
function travelDir(a, b) {
  const ccw = ((b - a) % (2 * Math.PI) + 2 * Math.PI) % (2 * Math.PI), cw = 2 * Math.PI - ccw;
  let mp = 0, mn = 0;
  for (let k = 1; k <= 8; k++) { mp = Math.max(mp, humeralAt(a + (ccw * k) / 8)); mn = Math.max(mn, humeralAt(a - (cw * k) / 8)); }
  if (Math.min(mp, mn) < 2.6 && Math.abs(mp - mn) > 0.2) return mp < mn ? 1 : -1;
  return ccw <= Math.PI ? 1 : -1;
}

const GOLD = 0.381966;
/** Golden-section refine of swivelCost on [lo, hi] (8 iterations): returns the best angle, its cost in sw[1]. */
const sw = new Float64Array(2);
function refine(lo, hi) {
  let a1 = lo + GOLD * (hi - lo), b1 = hi - GOLD * (hi - lo), ca1 = swivelCost(a1), cb1 = swivelCost(b1);
  for (let it = 0; it < 8; it++) {
    if (ca1 < cb1) { hi = b1; b1 = a1; cb1 = ca1; a1 = lo + GOLD * (hi - lo); ca1 = swivelCost(a1); }
    else { lo = a1; a1 = b1; ca1 = cb1; b1 = hi - GOLD * (hi - lo); cb1 = swivelCost(b1); }
  }
  if (ca1 < cb1) { sw[0] = a1; sw[1] = ca1; } else { sw[0] = b1; sw[1] = cb1; }
  return sw[0];
}
/** Minimum of the cost basin that contains swivel p (descent in 7.5 deg steps, then a golden refine). */
function basinMin(p) {
  const h = Math.PI / 24;
  const c0 = swivelCost(p), cl = swivelCost(p - h), cr = swivelCost(p + h);
  let x = p, cx = c0;
  if (cl < c0 || cr < c0) {
    const dir = cl < cr ? -1 : 1;
    x = p + dir * h; cx = dir < 0 ? cl : cr;
    for (let k = 0; k < 22; k++) {
      const xn = x + dir * h, cn = swivelCost(xn);
      if (cn >= cx) break;
      x = xn; cx = cn;
    }
  }
  refine(x - h, x + h);
  if (sw[1] > cx) { sw[0] = x; sw[1] = cx; }
  return sw[0];
}

/**
 * Two-bone IK. target: Float32Array/array [x,y,z] (model space, effector point), rot: quaternion array or null (keep
 * the end bone's current model orientation), pole: point [x,y,z] or null (default pole), weight 0..1, soft = soft-reach
 * fraction (0 = may lock straight). Arms (opt, all optional):
 *   clavicle = 1    shoulder (clavicle) assist toward targets near / beyond reach (elevation + protraction <= 24 deg,
 *                   depression <= 10 deg and only past full reach), computed from `clavBase`
 *   clavBase        Float32Array(4): the clavicle's authored local rotation (before any assist): every solve of this
 *                   arm recomputes the assist from it (re-solves in one frame never add up)
 *   wrist = true    swivel the elbow around the shoulder-wrist axis to keep the hand within its human range
 *                   (swing <= 85 deg, pronation / supination <= 90 deg), then softly clamp what is left
 *   roll = null     [gx, gy, gz]: grip axis in the end frame around which the hand may roll freely (two-handed grip)
 *   rollKeep = 0.25 how strongly the authored roll is kept (0 = free)
 *   phi = 0         preferred swivel (rad) relative to the pole
 *   mem, dt         Float32Array(MEM) kept by the caller per arm, and the game time (s) this solve advances: the swivel
 *                   continues from last frame's elbow direction (SWIVEL), so it never flips; commitMem() once per update
 *   keepLocal       with rot = null: keep the end bone's local rotation (wrist pose) instead of its model rotation
 *   body            Float32Array(8) torso capsule [a (3), b (3), radius + arm radius, body scale]: elbow and forearm stay
 *                   out of it
 *   out             Float32Array(4): receives the end rotation actually requested (after the grip roll)
 *   err             Float32Array(1): receives the angle (rad) between the requested and the achieved end rotation
 * Returns the reach ratio (dist / max length) before softening.
 */
export function solveLimb(rig, limb, lq, mq, mp, target, to, rot, ro, pole, po, weight, soft = SOFT, opt = null) {
  if (weight <= 0) return 0;
  const { root, mid, end, parent, sign } = limb;
  const arm = limb.kind === 'arm';
  if (soft < 0) soft = SOFT;
  // clavicle assist (arms): rotate the shoulder toward a target near / past full reach
  if (arm && (!opt || opt.clavicle !== 0)) clavicleAssist(rig, limb, lq, mq, mp, target, to, rot, ro, weight * (opt && opt.clavicle !== undefined ? opt.clavicle : 1), opt && opt.clavBase);
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
  const mem = wrist && opt && opt.mem ? opt.mem : null;
  const ch = limb.chest !== undefined ? limb.chest * 4 : -1;
  // last frame's swivel (the elbow direction kept in the chest frame, re-expressed in this frame's pole frame)
  let phiP = 0, hasMem = false;
  const memDir = () => {
    if (!mem || !(mem[3] > 0) || ch < 0) return false;
    qrot(tv, 0, mq, ch, mem[0], mem[1], mem[2]);
    const a = tv[0] * sv[3] + tv[1] * sv[4] + tv[2] * sv[5], b = tv[0] * sv[6] + tv[1] * sv[7] + tv[2] * sv[8];
    if (a * a + b * b < 0.04) return false; // the old elbow direction is along the reach: no information
    phiP = Math.atan2(b, a);
    return true;
  };
  hasMem = memDir();
  // a two-handed grip lets the hand roll around the grip axis: the roll that suits the forearm, scaled toward the
  // authored one by `keep`. Roll and swivel depend on each other: with memory the swivel is searched at last frame's
  // roll, and the roll then relaxes toward the best one for the new swivel (time constant 30 ms: a damped fixed point,
  // never a frame-to-frame alternation). Rolling moves the wrist (the axis runs through the fist), so the limb
  // geometry is set up again for the rolled hand.
  const psiRef = hasMem ? mem[5] : NaN;
  let psi = 0;
  if (roll) {
    limbAt(phi, sign, bend, er, eo, tq, 0);
    psi = hasMem ? psiRef : bestRoll(endModel, 0, sv, 16, roll[0], roll[1], roll[2], NaN);
    rollBy(endModel, 0, roll[0], roll[1], roll[2], psi * (1 - keep));
    qcopy(tq, 8, rollQ, 0); er = tq; eo = 8;
    bend = limbSetup(rig, limb, mq, mp, target, to, er, eo, pole, po, soft);
    if (hasMem) hasMem = memDir();
  }
  limbAt(phi, sign, bend, er, eo, tq, 0);
  let timer = 0, tdir = 0;
  if (wrist) {
    // swivel cost = arm comfort + a pull back to the pole (keeps the authored elbow when the arm is at ease) + the arm
    // out of the torso. Without memory: the global minimum. With memory: the minimum of the basin the elbow is in,
    // followed at a limited angular speed; a better basin is taken only after it has been clearly cheaper for a moment.
    const phi0 = phi;
    S.sign = sign; S.bend = bend; S.er = er; S.eo = eo; S.mq = mq; S.po = parent * 4; S.phi0 = phi0;
    S.body = opt && opt.body; S.l1 = limb.l1; S.d = reachD; S.rx = mp[root * 3]; S.ry = mp[root * 3 + 1]; S.rz = mp[root * 3 + 2];
    let best = phi0, bc = swivelCost(phi0);
    for (let i = 1; i < 24; i++) {
      const f = phi0 + (i < 12 ? i : i - 24) * (Math.PI / 12);
      const c = swivelCost(f);
      if (c < bc - 1e-9) { bc = c; best = f; }
    }
    const span = Math.PI / 12;
    let gPhi = refine(best - span, best + span), gC = sw[1];
    if (gC > bc) { gPhi = best; gC = bc; }
    if (hasMem) { // timer >= 0: how long another basin has been better; < 0: travelling (-1 - time travelled)
      const dt = Math.max(0, opt.dt || 0);
      const lPhi = basinMin(phiP), lC = sw[1];
      // a better basin: clearly cheaper than a strained one (a comfortable elbow is never moved for a small gain)
      const better = lC > SWIVEL.SWITCH_MIN && gC < lC - Math.max(SWIVEL.SWITCH_MARGIN, 0.4 * lC) && Math.abs(wrapA(gPhi - lPhi)) > Math.PI / 12;
      let goal = lPhi;
      timer = mem[4];
      if (timer >= 0) {
        timer = better ? timer + dt : 0;
        if (timer >= SWIVEL.SWITCH_HOLD) { timer = -1; goal = gPhi; }
        else if (Math.abs(wrapA(lPhi - phiP)) > SWIVEL.TRACK * dt) timer = -1; // the basin merged away: travel to the new one
      } else if (better) goal = gPhi;
      let d = wrapA(goal - phiP);
      if (timer < 0) {
        // the way round is chosen when the travel starts and kept to its end
        tdir = timer === -1 || !mem[6] ? travelDir(phiP, goal) : mem[6];
        const ccw = ((goal - phiP) % (2 * Math.PI) + 2 * Math.PI) % (2 * Math.PI);
        d = tdir > 0 ? ccw : ccw - 2 * Math.PI;
        // travel: eases in over 80 ms, SWITCH for a bent arm (the elbow rolls over at ~2.4 m/s x body), faster as the arm
        // straightens (a straight arm's swivel is only its twist), and settles exponentially on arrival
        const e = -1 - timer, x = Math.min(1, (e + dt) / 0.08);
        const rate = (SWIVEL.SWITCH * dt * x * x * (3 - 2 * x)) / Math.max(0.12, sv[10]);
        const near = Math.abs(d) * (1 - Math.exp(-30 * dt));
        d = Math.sign(d) * Math.min(rate, near);
        timer = Math.abs(wrapA(goal - phiP - d)) < 0.02 ? 0 : timer - dt;
        if (!(timer < 0)) tdir = 0;
      }
      phi = phiP + d;
    } else phi = gPhi;
    phi = wrapA(phi);
    if (roll) {
      limbAt(phi, sign, bend, er, eo, tq, 0);
      const b = bestRoll(endModel, 0, sv, 16, roll[0], roll[1], roll[2], hasMem ? psiRef : psi);
      psi = hasMem ? psiRef + (b - psiRef) * (1 - Math.exp(-Math.max(0, opt.dt || 0) / 0.03)) : b;
      rollBy(endModel, 0, roll[0], roll[1], roll[2], psi * (1 - keep));
      qcopy(tq, 8, rollQ, 0); er = tq; eo = 8;
      phi = resetup(phi, rig, limb, mq, mp, target, to, er, eo, pole, po, soft);
      bend = sBend;
    }
    limbAt(phi, sign, bend, er, eo, tq, 0);
  }
  qcopy(newL, 8, tq, 4);                         // end local keeps / reaches the requested model orientation
  const wmem = mem && mem[3] > 0 ? mem : null;
  if (wrist && clampWrist(newL, 8, wmem, wmem ? Math.max(0, opt.dt || 0) : 0)) {
    // the wrist could not take the requested orientation: keep the clamped wrist pose (relative to the forearm) and
    // solve the reach again for it, so the fist (not the wrist) stays on the target. The hand keeps exactly the clamped
    // pose (a hand never leaves the wrist's range, and never snaps back to the impossible request): where the iteration
    // has not fully settled the fist is a little off the target instead
    qcopy(rollQ, 4, newL, 8);                     // clamped local wrist pose
    for (let it = 0; it < 6; it++) {
      qaxis(sv, 12, 0, 0, 1, sign * bend);
      qmul(sv, 16, tq, 0, sv, 12);                // forearm (model)
      qmul(tq, 8, sv, 16, rollQ, 4);              // end model rotation for that wrist pose
      er = tq; eo = 8;
      phi = resetup(phi, rig, limb, mq, mp, target, to, er, eo, pole, po, soft);
      bend = sBend;
      limbAt(phi, sign, bend, er, eo, tq, 0);
    }
    qcopy(newL, 8, rollQ, 4);
    qmul(tq, 8, sv, 16, rollQ, 4); er = tq; eo = 8;  // the end model rotation that results
  }
  if (mem && ch >= 0) { // this frame's elbow direction (chest frame) for the next frame's solve
    const c = Math.cos(phi), s = Math.sin(phi);
    const px = sv[3] * c + sv[6] * s, py = sv[4] * c + sv[7] * s, pz = sv[5] * c + sv[8] * s;
    tv[8] = -mq[ch]; tv[9] = -mq[ch + 1]; tv[10] = -mq[ch + 2]; tv[11] = mq[ch + 3];
    qrot(mem, 8, tv, 8, px, py, pz);
    mem[11] = 1; mem[12] = timer; mem[13] = psi; mem[14] = tdir; mem[15] = wristOut;
  }
  if (opt && opt.err) { // requested vs achieved end rotation (the wrist clamp's deviation)
    qaxis(sv, 12, 0, 0, 1, sign * bend);
    qmul(sv, 16, tq, 0, sv, 12);
    qmul(sv, 20, sv, 16, newL, 8);
    const d = Math.abs(sv[20] * endModel[0] + sv[21] * endModel[1] + sv[22] * endModel[2] + sv[23] * endModel[3]);
    opt.err[0] = roll ? 0 : 2 * Math.acos(Math.min(1, d));
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
  return sv[11];
}

const edir = new Float32Array(3);
let sBend = 0;
/**
 * limbSetup again for a changed end rotation (the wrist point moves, so does the pole frame), keeping the elbow's
 * direction: returns swivel phi of the old frame re-expressed in the new one (the bend in sBend).
 */
function resetup(phi, rig, limb, mq, mp, target, to, er, eo, pole, po, soft) {
  const c = Math.cos(phi), s = Math.sin(phi);
  edir[0] = sv[3] * c + sv[6] * s; edir[1] = sv[4] * c + sv[7] * s; edir[2] = sv[5] * c + sv[8] * s;
  sBend = limbSetup(rig, limb, mq, mp, target, to, er, eo, pole, po, soft);
  const a = edir[0] * sv[3] + edir[1] * sv[4] + edir[2] * sv[5], b = edir[0] * sv[6] + edir[1] * sv[7] + edir[2] * sv[8];
  return a * a + b * b > 1e-6 ? Math.atan2(b, a) : phi;
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
  reachD = d;
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

let wristOut = 0;
/**
 * Soft-limit a hand local rotation to the wrist range (swing off the forearm axis, pronation / supination). True if
 * changed. Pronation: up to the knee as asked, then saturating at the limit, then (past ~140 deg asked, an impossible
 * demand) easing back so that +180 and -180 meet at neutral - never a jump between the two limits. With an arm memory
 * (mem[7]: last frame's twist) the twist turns at most WRIST_RATE x dt per frame, so a request sweeping through an
 * impossible pronation turns the hand over smoothly. The twist used is left in wristOut.
 */
export function clampWrist(q, o, mem = null, dt = 0) {
  let x = q[o], y = q[o + 1], z = q[o + 2], w = q[o + 3];
  if (w < 0) { x = -x; y = -y; z = -z; w = -w; }
  const tw = 2 * Math.atan2(y, w);
  const sw0 = Math.acos(Math.max(-1, Math.min(1, 1 - 2 * (x * x + z * z))));
  const at = Math.abs(tw), back = 1 - smooth01(at, 2.44, Math.PI);
  let tw2 = Math.sign(tw) * softLimit(at, WRIST.twistKnee, WRIST.twist) * back;
  if (mem) tw2 = mem[7] + Math.max(-WRIST_RATE * dt, Math.min(WRIST_RATE * dt, tw2 - mem[7]));
  wristOut = tw2;
  const sw2 = softLimit(sw0, WRIST.swingKnee, WRIST.swing);
  if (Math.abs(tw2 - tw) < 1e-6 && Math.abs(sw2 - sw0) < 1e-6) return false;
  setSwingTwist(q, o, x, y, z, w, tw, tw2, sw2);
  return true;
}

const cl = new Float32Array(16);
/**
 * Clavicle assist: rotate the shoulder bone (in the chest frame) so the shoulder joint moves toward a target the arm
 * can barely or not reach. Elevation / protraction ramp in from 82% of the reach, <= 24 deg; depression only past full
 * reach (97%), <= 10 deg (a fist low in front stays on a level shoulder). With `base` (the authored local rotation of
 * the clavicle) the assist replaces the previous one instead of adding to it.
 */
function clavicleAssist(rig, limb, lq, mq, mp, target, to, rot, ro, w, base) {
  const c = limb.clav, r = limb.root, par = rig.parent[c];
  if (base) { qcopy(lq, c * 4, base, 0); fk(rig, lq, rig.offset, mq, mp, c, r + 1); }
  if (!(w > 0)) return;
  // wrist target
  const er = rot || mq, eo = rot ? ro : limb.end * 4;
  qrot(cl, 0, er, eo, limb.endOff[0], limb.endOff[1], limb.endOff[2]);
  const tx = target[to] - cl[0], ty = target[to + 1] - cl[1], tz = target[to + 2] - cl[2];
  const sx = mp[r * 3], sy = mp[r * 3 + 1], sz = mp[r * 3 + 2];
  const lmax = limb.l1 + limb.l2;
  const ratio = Math.hypot(tx - sx, ty - sy, tz - sz) / lmax;
  const k = smooth01(ratio, 0.82, 1.12) * w, kd = smooth01(ratio, 0.97, 1.15) * w;
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
  // about half of the remaining angle; upward motion softly limited to 24 deg, downward to 10 deg (blended by the
  // vertical direction the shoulder joint would move: y of n x a)
  const moveY = nz * ax - nx * az;
  const up = softLimit(full * 0.55 * k, 0.25, 0.42), down = softLimit(full * 0.55 * kd, 0.09, 0.17);
  const ang = down + (up - down) * smooth01(moveY, -0.25, 0.25);
  if (!(ang > 1e-7)) return;
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
  // knees track the toes: f = average of foot forward and hips forward (horizontal), slightly outward. The knee points
  // along L x u (L = f x up, the lateral axis): perpendicular to the reach, in the leg's sagittal plane, so a foot
  // below the hip puts the knee over the toes, a foot in front at hip height (kick, knee raise) lifts the knee and a
  // foot behind drops it. With the small forward / up terms the field is continuous for every reach direction but two,
  // beside the hip, above and behind it (out of the leg's range); a pole projected from f alone flips where u = f.
  qrot(out, 6, er, eo, 1, 0, 0);
  qrot(out, 9, mq, rig.index.hips * 4, 1, 0, 0);
  let fx = out[6] + out[9] * 0.6, fz = out[8] + out[11] * 0.6;
  let l = Math.hypot(fx, fz) || 1;
  fx /= l; fz = fz / l + limb.side * 0.12;
  l = Math.hypot(fx, fz) || 1;
  fx /= l; fz /= l;
  const px = -fx * uy + 0.55 * fx, py = fx * ux + fz * uz + 0.3, pz = -fz * uy + 0.55 * fz;
  out[3] = px; out[4] = py; out[5] = pz;
}

const fpole = new Float32Array(3);
/** Raise the planted leg by dy (the foot keeps its orientation, the knee keeps its swivel: the current knee is the pole). */
function liftLeg(rig, limb, lq, lp, mq, mp, buf, dy, soft) {
  const end = limb.end, m = limb.mid * 3;
  qrot(tv, 0, mq, end * 4, limb.endOff[0], limb.endOff[1], limb.endOff[2]);
  buf[0] = mp[end * 3] + tv[0]; buf[1] = mp[end * 3 + 1] + tv[1] + dy; buf[2] = mp[end * 3 + 2] + tv[2];
  qcopy(buf, 4, mq, end * 4);
  fpole[0] = mp[m]; fpole[1] = mp[m + 1]; fpole[2] = mp[m + 2];
  solveLimb(rig, limb, lq, mq, mp, buf, 0, buf, 4, fpole, 0, 1, soft);
  fk(rig, lq, lp, mq, mp, limb.first, rig.count);
}

/** Smallest rotation a >= 0 about unit axis z (model) that brings vector v's y to `goal` (relative). NaN if none. */
function bendTo(zx, zy, zz, vx, vy, vz, goal) {
  const zv = zx * vx + zy * vy + zz * vz;
  // y(a) = A cos a + B sin a + C
  const A = vy - zy * zv, B = zz * vx - zx * vz, C = zy * zv;
  const R = Math.hypot(A, B);
  if (R < 1e-9) return NaN;
  const del = Math.atan2(B, A), c = Math.max(-1, Math.min(1, (goal - C) / R));
  const b1 = wrapA(del + Math.acos(c)), b2 = wrapA(del - Math.acos(c));
  // toes-up solutions are positive; take the smallest positive rotation
  return b1 >= 0 && (b2 < 0 || b1 < b2) ? b1 : b2 >= 0 ? b2 : Math.max(b1, b2);
}

/**
 * Keep a foot's sole, ball pad and toe tip on or above the floor (model-space height floorY). Re-solves the leg if a
 * sole point (heel, under the ankle, ball pad) dips below the floor, then bends the toe about its joint so the toe tip
 * lands on the floor; when that would push the pad under the toe joint below the floor (the toe bent past level) or
 * needs more than the toe's ~80 deg, the leg is raised by the difference instead. Every re-solve keeps the knee's
 * swivel (the current knee is the pole) and the foot's soft reach. Call with FK up to date.
 */
export function floorFoot(rig, limb, lq, lp, mq, mp, floorY, buf, soft = SOFT) {
  const P = rig.P, end = limb.end, toe = limb.toe;
  // lowest of heel / ankle-sole / ball pad (all on the foot bone's sole plane)
  qrot(tv, 0, mq, end * 4, 0, -P.ankleHeight, 0);
  const sy = mp[end * 3 + 1] + tv[1];
  qrot(tv, 3, mq, end * 4, -P.heelLength, -P.ankleHeight, 0);
  const hy = mp[end * 3 + 1] + tv[4];
  qrot(tv, 6, mq, end * 4, P.footLength, -P.ankleHeight, 0);
  const by = mp[end * 3 + 1] + tv[7];
  const low = Math.min(sy, hy, by);
  if (low < floorY - 1e-5) liftLeg(rig, limb, lq, lp, mq, mp, buf, floorY - low, soft);
  // toe: rotate about the toe joint (its Z axis) until the tip is on the floor
  const th = P.ankleHeight - P.footDrop;
  qrot(tv, 0, mq, toe * 4, P.toeLength, -th, 0);
  const tipY = mp[toe * 3 + 1] + tv[1];
  if (!(tipY < floorY)) return;
  const vx = tv[0], vy = tv[1], vz = tv[2];
  qrot(tv, 3, mq, toe * 4, 0, 0, 1); // rotation axis (model)
  const zx = tv[3], zy = tv[4], zz = tv[5];
  const J = mp[toe * 3 + 1];
  let ang = bendTo(zx, zy, zz, vx, vy, vz, floorY - J);
  if (!Number.isFinite(ang)) return;
  ang = Math.max(0, ang);
  // pad under the toe joint after that bend; below the floor = the toe would have to bend past level
  qrot(tv, 6, mq, toe * 4, 0, -th, 0);
  const padAt = (a) => { qaxis(cl, 0, zx, zy, zz, a); qrot(cl, 4, cl, 0, tv[6], tv[7], tv[8]); return J + cl[5]; };
  const pady = padAt(ang);
  let lift = 0;
  if (pady < floorY - 1e-5) {
    // level the toe (pad and tip at the same height) and raise the leg until both rest on the floor
    const lvl = bendTo(zx, zy, zz, vx - tv[6], vy - tv[7], vz - tv[8], 0);
    if (Number.isFinite(lvl)) { ang = Math.max(0, Math.min(ang, lvl)); lift = floorY - padAt(ang); }
  }
  if (ang > 1.4) { // the toe's range: the rest is a lift of the leg
    ang = 1.4;
    qaxis(cl, 0, zx, zy, zz, ang); qrot(cl, 4, cl, 0, vx, vy, vz);
    lift = Math.max(lift, floorY - (J + cl[5]));
  }
  if (lift > 1e-5) liftLeg(rig, limb, lq, lp, mq, mp, buf, lift, soft);
  if (ang > 0) {
    qaxis(tv, 0, 0, 0, 1, ang);
    qmul(lq, toe * 4, lq, toe * 4, tv, 0);
  }
}

const lookTmp = new Float32Array(16);

/**
 * Look angles in the chest frame: out = [target yaw, target pitch, head yaw, head pitch] (rad; yaw + = toward -s, the
 * fighter's left, as the head's +Y). target: model point; `eye` = height of the eyes above the head pivot (m). Returns
 * false if the target is at the eyes.
 */
export function lookAngles(rig, mq, mp, target, to, out, eye = 0.08 * (rig.k || 1)) {
  const chest = rig.index.chest, head = rig.index.head, c4 = chest * 4;
  const dx = target[to] - mp[head * 3], dy = target[to + 1] - mp[head * 3 + 1] - eye, dz = target[to + 2] - mp[head * 3 + 2];
  if (Math.hypot(dx, dy, dz) < 1e-4) return false;
  lookTmp[0] = -mq[c4]; lookTmp[1] = -mq[c4 + 1]; lookTmp[2] = -mq[c4 + 2]; lookTmp[3] = mq[c4 + 3];
  qrot(lookTmp, 4, lookTmp, 0, dx, dy, dz);
  out[0] = Math.atan2(-lookTmp[6], lookTmp[4]); out[1] = Math.atan2(lookTmp[5], Math.hypot(lookTmp[4], lookTmp[6]));
  qrot(lookTmp, 7, mq, head * 4, 1, 0, 0);
  qrot(lookTmp, 7, lookTmp, 0, lookTmp[7], lookTmp[8], lookTmp[9]);
  out[2] = Math.atan2(-lookTmp[9], lookTmp[7]); out[3] = Math.atan2(lookTmp[8], Math.hypot(lookTmp[7], lookTmp[9]));
  return true;
}

/**
 * Turn the head's +X from its current direction (chest-frame yaw / pitch hy, hp) by (dyaw, dpitch): neck 40%, head
 * 60%. A rotation of at most a few tens of degrees between two directions on the same side: never an axis flip.
 */
export function applyLook(rig, lq, hy, hp, dyaw, dpitch) {
  const neck = rig.index.neck, head = rig.index.head;
  const cy = Math.cos(hy), cp = Math.cos(hp), y2 = hy + dyaw, p2 = hp + dpitch;
  qfromTo(lookTmp, 10, cy * cp, Math.sin(hp), -Math.sin(hy) * cp, Math.cos(y2) * Math.cos(p2), Math.sin(p2), -Math.sin(y2) * Math.cos(p2));
  const w = Math.max(-1, Math.min(1, lookTmp[13]));
  const ang = 2 * Math.acos(w);
  if (!(ang > 1e-5)) return;
  const s = Math.sqrt(Math.max(1e-12, 1 - w * w));
  const axx = lookTmp[10] / s, axy = lookTmp[11] / s, axz = lookTmp[12] / s;
  // neck: rotation in the chest (= neck parent) frame
  qaxis(lookTmp, 0, axx, axy, axz, ang * 0.4);
  qmul(lq, neck * 4, lookTmp, 0, lq, neck * 4);
  // head: same axis expressed in the neck frame
  qaxis(lookTmp, 4, axx, axy, axz, ang * 0.6);
  qmulInv(lookTmp, 8, lq, neck * 4, lookTmp, 4);
  qmul(lookTmp, 8, lookTmp, 8, lq, neck * 4);
  qmul(lq, head * 4, lookTmp, 8, lq, head * 4);
}

const lookOut = new Float32Array(4);
/**
 * Rotate neck (40%) and head (60%) so the head's +X faces `target` (model space): yaw limited to ~80 deg and pitch to
 * ~50 deg from the chest, faded out for targets 100..150 deg behind the chest. Stateless (no smoothing): the character
 * uses lookAngles / applyLook with a frame-rate independent follower.
 */
export function solveLook(rig, lq, mq, mp, target, to, weight, eye = 0.08 * (rig.k || 1)) {
  if (weight <= 0 || !lookAngles(rig, mq, mp, target, to, lookOut, eye)) return;
  const w = weight * lookFade(lookOut[0]);
  applyLook(rig, lq, lookOut[2], lookOut[3], w * (lookYaw(lookOut[0]) - lookOut[2]), w * (lookPitch(lookOut[1]) - lookOut[3]));
}
/** Look weight for a target at chest-frame yaw y: 1 in front, 0 from 150 deg (behind: no side to turn to). */
export function lookFade(y) { return 1 - smooth01(Math.abs(y), 1.745, 2.618); }
/** Head yaw limit (rad, chest frame). */
export function lookYaw(y) { return softLimit(y, 1.05, 1.4); }
/** Head pitch limit (rad, chest frame). */
export function lookPitch(p) { return softLimit(p, 0.6, 0.87); }
