// Motion-quality metrics for the character runtime (QA). Pure module: no DOM, no three.js import, no randomness, no
// state between calls. It drives a Character through its public API at a fixed rate (default 120 Hz), records every
// bone transform, and turns the recording into numbers that a clip author or a rig fixer can act on:
//
//   record(char, opts)            run + record frames (bones local + world, weapon tip / base, root, events, timings)
//   recordClip(char, clip, opts)  reset + play a clip (from a source clip when crossfading) + record it
//   tipPath(rec)                  weapon-tip arcs: swings, speed, straight segments, kinks, jerk spikes, edge alignment
//   angular(rec)                  per-bone angular velocity / acceleration, velocity steps (pops), over-speed
//   jointLimits(rec)              violations of a documented human range-of-motion table (ROM / ROM_CHAINS)
//   balance(rec)                  centre of mass vs support polygon (static + extrapolated COM)
//   feet(rec)                     planted-foot drift / slide speed / moon-walk ratio vs root motion
//   floor(rec)                    floor penetration of feet, blade, pommel, hands, knees
//   intersections(rec)            self-intersection proxies (body capsules, blade through the body)
//   seam(rec)                     loop-seam continuity of pose + velocity in the full runtime
//   keyContinuity(rig, clip)      clip-data velocity continuity at every key (eases / tangents), seam of the data
//   crossfade(char, a, b, opts)   transition pops between two clips (joint velocity steps vs both clips alone)
//   poseOf(char) / poseDiff(a,b)  animated-pose signatures for determinism tests
//   auditClip(char, clip, opts)   everything above for one clip, summarised
//
// Units: metres, seconds, degrees. Positions are world space (the recorder keeps the root at the origin facing +X and
// applies the clip's root motion, so world = fighter frame + root travel). Every distance threshold scales with the
// body (`scaleOf(char)`: hips pivot height / 1.04 m), so the same functions work on a 1.78 m oracle and an 8 m giant.

import { getClip, sampleClip, Pose, EFFECTORS, EFF_STRIDE } from './anim.js';

export const QA_HZ = 120;
const R2D = 180 / Math.PI;

// ---- tables ------------------------------------------------------------------------------------------------------

/**
 * Human active range of motion per bone (degrees) in the rig's authoring convention (README section 4: local Euler
 * ZXY relative to the zero pose, left bones mirrored so equal numbers mean the same anatomical motion). `twist` is the
 * swing-twist angle about the bone's own long axis (Y), +internal rotation. Values: average adult active ROM
 * (AAOS / Kapandji tables), rounded; per-bone shares of spine / neck motion follow a 2-bone split of the chain totals
 * (ROM_CHAINS). A violation is a value outside [lo, hi] by more than `tol` degrees.
 *
 *  bone      axis  range          meaning (README axis table)
 *  spine     x     -20..20        lumbar side-bend
 *            y     -25..25        lumbar twist (real lumbar rotation is ~5 deg; the rig spreads trunk twist over 2 bones)
 *            z     -40..25        -bend forward / +lean back
 *  chest     x/y/z -20..20 / -30..30 / -35..25
 *  neck      x/y/z -35..35 / -45..45 / -40..50   (-Z chin down)
 *  head      x/y/z -25..25 / -45..45 / -30..35
 *  shoulder  x     -35..10        -X shrug (elevation 35), +X depress 10
 *            y     -25..25        protract / retract
 *            z     -15..15        clavicle roll (avoid)
 *  upperArm  z     -60..180       -Z extension 60, +Z flexion (180 with the scapula)
 *            x     -180..45       -X abduction, +X adduction across the body
 *            twist -90..80        external 90 / internal 80
 *  foreArm   z     -5..150        elbow flexion, <0 = hyperextension
 *            x     -5..5          not anatomical
 *  hand      swing 0..85        wrist bend = angle between the hand's long axis and the forearm's (flexion 80 /
 *                               extension 70 / ulnar 40 / radial 25 combined; swing is used instead of Euler X/Z
 *                               because the hand also carries the forearm pronation, which makes ZXY ambiguous)
 *            twist -90..90      forearm pronation / supination (moved into the hand by the runtime)
 *  thigh     z     -30..125       -extension 30 / +flexion 125
 *            x     -45..30        -abduction 45 / +adduction 30
 *            twist -45..45        hip external / internal rotation
 *  shin      z     -150..3        knee flexion (negative), >0 = hyperextension
 *            x     -3..3          not anatomical
 *  foot      z     -50..30        -plantarflexion 50 / +dorsiflexion 30
 *            x     -20..35        -eversion 20 / +inversion 35
 *            y     -30..30        toe-in / toe-out relative to the shin (tibial rotation + subtalar)
 *  toe       z     -40..70        MTP flexion / extension
 */
export const ROM = {
  spine: { x: [-20, 20], y: [-25, 25], z: [-40, 25] },
  chest: { x: [-20, 20], y: [-30, 30], z: [-35, 25] },
  neck: { x: [-35, 35], y: [-45, 45], z: [-40, 50] },
  head: { x: [-25, 25], y: [-45, 45], z: [-30, 35] },
  shoulder: { x: [-35, 10], y: [-25, 25], z: [-15, 15] },
  upperArm: { x: [-180, 45], z: [-60, 180], twist: [-90, 80] },
  foreArm: { x: [-5, 5], z: [-5, 150] },
  hand: { swing: [0, 85], twist: [-90, 90] },
  thigh: { x: [-45, 30], z: [-30, 125], twist: [-45, 45] },
  shin: { x: [-3, 3], z: [-150, 3] },
  foot: { x: [-20, 35], y: [-30, 30], z: [-50, 30] },
  toe: { z: [-40, 70] },
};

/** Whole-chain limits (composed local rotations), degrees: thoracolumbar trunk and cervical spine (AAOS totals). */
export const ROM_CHAINS = {
  trunk: { bones: ['spine', 'chest'], x: [-35, 35], y: [-45, 45], z: [-80, 30] },
  cervical: { bones: ['neck', 'head'], x: [-45, 45], y: [-80, 80], z: [-50, 60] },
};

/**
 * Plausible peak joint angular speeds (deg/s) for an armoured adult swinging a heavy weapon (sports-biomechanics peaks
 * for trunk rotation ~800-1000, elbow extension ~2000, wrist ~2500, hip ~1200). Above = super-human snap.
 */
export const MAX_SPEED = { hips: 900, spine: 900, chest: 900, neck: 1000, head: 1000, shoulder: 900, upperArm: 2000, foreArm: 2400, hand: 2600, thigh: 1300, shin: 1800, foot: 1500, toe: 1500 };

/** Segment mass fractions (Winter 2009) and COM points (bone frame, metres at default proportions, scaled). */
export const SEGMENTS = [
  ['head', 'head', 0.081, [0.02, 0.09, 0]],
  ['thorax', 'chest', 0.216, [-0.01, 0.12, 0]],
  ['abdomen', 'spine', 0.139, [0, 0.08, 0]],
  ['pelvis', 'hips', 0.142, [0, -0.03, 0]],
  ...['R', 'L'].flatMap((s) => [
    ['upperArm' + s, 'upperArm' + s, 0.028, 'l1:0.436'],
    ['foreArm' + s, 'foreArm' + s, 0.016, 'l2:0.43'],
    ['hand' + s, 'hand' + s, 0.006, 'hand:0.6'],
    ['thigh' + s, 'thigh' + s, 0.1, 'lt:0.433'],
    ['shank' + s, 'shin' + s, 0.0465, 'ls:0.433'],
    ['foot' + s, 'foot' + s, 0.0145, [0.04, -0.05, 0]],
  ]),
];

const CORE_BONES = ['hips', 'spine', 'chest', 'neck', 'head'];
const LIMB_BASES = ['shoulder', 'upperArm', 'foreArm', 'hand', 'thigh', 'shin', 'foot', 'toe'];
/** Bones the angular / limit metrics look at (the authored skeleton: no helpers, fingers or simulated bones). */
export const MAIN_BONES = [...CORE_BONES, ...['R', 'L'].flatMap((s) => LIMB_BASES.map((b) => b + s))];
const baseOf = (n) => n.replace(/[RL]$/, '');

// ---- small math ---------------------------------------------------------------------------------------------------
function qmul(a, b, o) { // o = a * b  (arrays [x,y,z,w])
  const ax = a[0], ay = a[1], az = a[2], aw = a[3], bx = b[0], by = b[1], bz = b[2], bw = b[3];
  o[0] = ax * bw + aw * bx + ay * bz - az * by; o[1] = ay * bw + aw * by + az * bx - ax * bz;
  o[2] = az * bw + aw * bz + ax * by - ay * bx; o[3] = aw * bw - ax * bx - ay * by - az * bz;
  return o;
}
/** Rotation angle (rad) of the relative rotation between unit quaternions a and b (precise for small angles). */
export function qangle(a, ao, b, bo) {
  // r = b * conj(a)
  const ax = -a[ao], ay = -a[ao + 1], az = -a[ao + 2], aw = a[ao + 3];
  const bx = b[bo], by = b[bo + 1], bz = b[bo + 2], bw = b[bo + 3];
  const x = bx * aw + bw * ax + by * az - bz * ay, y = by * aw + bw * ay + bz * ax - bx * az;
  const z = bz * aw + bw * az + bx * ay - by * ax, w = bw * aw - bx * ax - by * ay - bz * az;
  return 2 * Math.atan2(Math.hypot(x, y, z), Math.abs(w));
}
/** Rotation vector (axis * angle, rad) of b * conj(a): the rotation taking a to b, in the parent / spatial frame. */
function qdelta(a, ao, b, bo, out) {
  const ax = -a[ao], ay = -a[ao + 1], az = -a[ao + 2], aw = a[ao + 3];
  const bx = b[bo], by = b[bo + 1], bz = b[bo + 2], bw = b[bo + 3];
  let x = bx * aw + bw * ax + by * az - bz * ay, y = by * aw + bw * ay + bz * ax - bx * az;
  let z = bz * aw + bw * az + bx * ay - by * ax, w = bw * aw - bx * ax - by * ay - bz * az;
  if (w < 0) { x = -x; y = -y; z = -z; w = -w; }
  const s = Math.hypot(x, y, z);
  const ang = 2 * Math.atan2(s, w), k = s > 1e-12 ? ang / s : 2;
  out[0] = x * k; out[1] = y * k; out[2] = z * k;
  return out;
}
/** Euler ZXY (degrees, R = Rz * Rx * Ry, the rig's authoring order) of quaternion q[o..]. */
export function eulerZXY(q, o = 0, out = [0, 0, 0]) {
  const x = q[o], y = q[o + 1], z = q[o + 2], w = q[o + 3];
  const m11 = 1 - 2 * (y * y + z * z), m12 = 2 * (x * y - w * z), m21 = 2 * (x * y + w * z), m22 = 1 - 2 * (x * x + z * z);
  const m31 = 2 * (x * z - w * y), m32 = 2 * (y * z + w * x), m33 = 1 - 2 * (x * x + y * y);
  const c = Math.max(-1, Math.min(1, m32));
  out[0] = Math.asin(c) * R2D;
  if (Math.abs(c) < 0.9999999) { out[1] = Math.atan2(-m31, m33) * R2D; out[2] = Math.atan2(-m12, m22) * R2D; } else { out[1] = 0; out[2] = Math.atan2(m21, m11) * R2D; }
  return out;
}
/** Twist angle (degrees) about the local Y axis (swing-twist decomposition). */
export function twistY(q, o = 0) {
  let w = q[o + 3], y = q[o + 1];
  if (w < 0) { w = -w; y = -y; }
  return 2 * Math.atan2(y, w) * R2D;
}
const median = (a) => { if (!a.length) return 0; const s = Float64Array.from(a).sort(); return s[s.length >> 1]; };
const pct = (a, p) => { if (!a.length) return 0; const s = Float64Array.from(a).sort(); return s[Math.min(s.length - 1, Math.floor(s.length * p))]; };
const r = (x, d = 3) => (Number.isFinite(x) ? Math.round(x * 10 ** d) / 10 ** d : x);

/** Closest distance between segments p1-q1 and p2-q2 (arrays of 3). */
export function segDist(p1, q1, p2, q2) {
  const d1x = q1[0] - p1[0], d1y = q1[1] - p1[1], d1z = q1[2] - p1[2];
  const d2x = q2[0] - p2[0], d2y = q2[1] - p2[1], d2z = q2[2] - p2[2];
  const rx = p1[0] - p2[0], ry = p1[1] - p2[1], rz = p1[2] - p2[2];
  const a = d1x * d1x + d1y * d1y + d1z * d1z, e = d2x * d2x + d2y * d2y + d2z * d2z, f = d2x * rx + d2y * ry + d2z * rz;
  let s, t;
  if (a <= 1e-12 && e <= 1e-12) { s = t = 0; } else if (a <= 1e-12) { s = 0; t = Math.max(0, Math.min(1, f / e)); } else {
    const c = d1x * rx + d1y * ry + d1z * rz;
    if (e <= 1e-12) { t = 0; s = Math.max(0, Math.min(1, -c / a)); } else {
      const b = d1x * d2x + d1y * d2y + d1z * d2z, den = a * e - b * b;
      s = den > 1e-12 ? Math.max(0, Math.min(1, (b * f - c * e) / den)) : 0;
      t = (b * s + f) / e;
      if (t < 0) { t = 0; s = Math.max(0, Math.min(1, -c / a)); } else if (t > 1) { t = 1; s = Math.max(0, Math.min(1, (b - c) / a)); }
    }
  }
  const x = p1[0] + d1x * s - (p2[0] + d2x * t), y = p1[1] + d1y * s - (p2[1] + d2y * t), z = p1[2] + d1z * s - (p2[2] + d2z * t);
  return Math.hypot(x, y, z);
}

/** 2D convex hull (monotone chain) of points [[x,z], ...]. */
function hull(pts) {
  if (pts.length < 3) return pts.slice();
  const p = pts.slice().sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  const cross = (o, a, b) => (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);
  const lo = [], up = [];
  for (const q of p) { while (lo.length >= 2 && cross(lo[lo.length - 2], lo[lo.length - 1], q) <= 0) lo.pop(); lo.push(q); }
  for (let i = p.length - 1; i >= 0; i--) { const q = p[i]; while (up.length >= 2 && cross(up[up.length - 2], up[up.length - 1], q) <= 0) up.pop(); up.push(q); }
  up.pop(); lo.pop();
  return lo.concat(up);
}
/** Signed distance from point (x,z) to a convex polygon / segment / point (positive = outside). */
function polyDist(poly, x, z) {
  if (!poly.length) return Infinity;
  if (poly.length === 1) return Math.hypot(x - poly[0][0], z - poly[0][1]);
  let inside = poly.length >= 3, best = Infinity;
  for (let i = 0; i < poly.length; i++) {
    const a = poly[i], b = poly[(i + 1) % poly.length];
    if (poly.length === 2 && i === 1) break;
    const ex = b[0] - a[0], ez = b[1] - a[1], px = x - a[0], pz = z - a[1];
    const L = ex * ex + ez * ez, t = L > 1e-12 ? Math.max(0, Math.min(1, (px * ex + pz * ez) / L)) : 0;
    best = Math.min(best, Math.hypot(px - ex * t, pz - ez * t));
    if (ex * pz - ez * px < 0) inside = false; // hull is counter-clockwise in (x, z)
  }
  return inside ? -best : best;
}

// ---- recording ----------------------------------------------------------------------------------------------------

/** Body scale factor (1 = the 1.95 m default proportions). */
export function scaleOf(char) {
  const P = char.rig.P;
  return (P.hipHeight + P.pelvisDrop) / 1.04;
}

/** Indices of the bones a recording keeps: everything but simulated cloth particles (model-space roots other than hips). */
function trackedBones(char) {
  const rig = char.rig, out = [];
  for (let i = 0; i < rig.count; i++) if (rig.parent[i] >= 0 || rig.names[i] === 'hips') out.push(i);
  return out;
}

/**
 * Run the character and record every frame.
 * opts: { frames, hz = 120 (or dts: [dt per frame], for hit-stop / slow-mo scripts), before(i, char, t) (drive the
 *         character before update i: play / setClipTime / impulse ...), applyRoot = true (root motion moves the root),
 *         time = true (measure ms per update) }
 * Returns a recording: { n, h, t[], names, idx, Q (local quats), M (world 3x4: X, Y, Z axes + position), tip, base,
 *         root, clipT, clip[], events[{ i, name, data, clip }], ms[], P, lengths, scale, weapon, tipOff, baseOff, nan }
 */
export function record(char, opts = {}) {
  const hz = opts.hz || QA_HZ;
  const dts = opts.dts || null;
  const n = dts ? dts.length : opts.frames;
  const bi = trackedBones(char), B = bi.length;
  const names = bi.map((i) => char.rig.names[i]);
  const idx = Object.fromEntries(names.map((nm, k) => [nm, k]));
  const bones = names.map((nm) => char.bones[nm]);
  const Q = new Float64Array(n * B * 4), M = new Float64Array(n * B * 12);
  const tip = new Float64Array(n * 3), base = new Float64Array(n * 3), root = new Float64Array(n * 3), clipT = new Float64Array(n);
  const t = new Float64Array(n), ms = new Float64Array(n), clip = new Array(n);
  const events = [];
  let frame = 0, time = 0;
  const off = char.onEvent((name, data, c) => events.push({ i: frame, name, data, clip: c }));
  const tipS = char.sockets.weaponTip, baseS = char.sockets.weaponBase;
  const applyWas = char.applyRootMotion;
  char.applyRootMotion = opts.applyRoot !== false;
  const now = typeof performance !== 'undefined' ? () => performance.now() : () => 0;
  let nan = null;
  try {
    for (frame = 0; frame < n; frame++) {
      const dt = dts ? dts[frame] : 1 / hz;
      if (opts.before) opts.before(frame, char, time);
      const t0 = opts.time === false ? 0 : now();
      char.update(dt, dt);
      ms[frame] = opts.time === false ? 0 : now() - t0;
      time += dt;
      t[frame] = time;
      for (let k = 0; k < B; k++) {
        const b = bones[k], q = b.quaternion, e = b.matrixWorld.elements, o = (frame * B + k) * 12, oq = (frame * B + k) * 4;
        Q[oq] = q.x; Q[oq + 1] = q.y; Q[oq + 2] = q.z; Q[oq + 3] = q.w;
        M[o] = e[0]; M[o + 1] = e[1]; M[o + 2] = e[2]; M[o + 3] = e[4]; M[o + 4] = e[5]; M[o + 5] = e[6];
        M[o + 6] = e[8]; M[o + 7] = e[9]; M[o + 8] = e[10]; M[o + 9] = e[12]; M[o + 10] = e[13]; M[o + 11] = e[14];
        if (!nan && !(Number.isFinite(e[12]) && Number.isFinite(e[13]) && Number.isFinite(e[14]) && Number.isFinite(q.w))) nan = { frame, bone: names[k] };
      }
      if (tipS) { const e = tipS.matrixWorld.elements; tip[frame * 3] = e[12]; tip[frame * 3 + 1] = e[13]; tip[frame * 3 + 2] = e[14]; }
      if (baseS) { const e = baseS.matrixWorld.elements; base[frame * 3] = e[12]; base[frame * 3 + 1] = e[13]; base[frame * 3 + 2] = e[14]; }
      root[frame * 3] = char.root.position.x; root[frame * 3 + 1] = char.root.position.y; root[frame * 3 + 2] = char.root.position.z;
      clipT[frame] = char.clipTime; clip[frame] = char.clip;
    }
  } finally {
    off();
    char.applyRootMotion = applyWas;
  }
  const wb = tipS && tipS.parent ? tipS.parent.name : null;
  return {
    n, h: dts ? null : 1 / hz, hz, t, names, idx, B, Q, M, tip, base, root, clipT, clip, events, ms, nan,
    P: char.rig.P, lengths: char.rig.lengths, scale: scaleOf(char), weapon: wb,
    tipOff: tipS ? [tipS.position.x, tipS.position.y, tipS.position.z] : null,
    baseOff: baseS ? [baseS.position.x, baseS.position.y, baseS.position.z] : null,
    gripAt: null, facing: char.facing,
  };
}

/**
 * Put the character in a clean measuring state: root at the origin (or `x`) facing `facing`, no look-at, no wind,
 * breathing `breath` (1 = default), then play `clip` with no fade and let cloth / springs re-hang. Layers survive
 * play(): the Character API cannot list them, so callers stop their own layers (stopLayer(name, 0)) first. Flinch
 * springs and the breathing phase also persist; determinism comparisons use fresh characters.
 */
export function resetForQA(char, clip, { facing = 1, x = 0, breath = 1, startAt = 0 } = {}) {
  char.root.position.set(x, 0, 0);
  char.root.rotation.set(0, 0, 0);
  char.setFacing(facing);
  char.lookAt(null);
  char.wind = [0, 0, 0];
  char.breath.depth = breath;
  char.play(clip, { fade: 0, restart: true, startAt });
  char.teleport();
  char.update(0, 0);
  return char;
}

/**
 * Reset, play `clip` and record it. opts: { hz = 120, duration (default: one clip length, two for loops), speed = 1,
 * from: source clip (crossfade into `clip` after `fromTime` s of the source), fromTime, fade = 0.1, breath = 1, facing }
 */
export function recordClip(char, clip, opts = {}) {
  const hz = opts.hz || QA_HZ;
  const c = getClip(char.rig, clip);
  const speed = opts.speed ?? 1;
  const dur = opts.duration ?? (c.loop ? 2 * c.duration : c.duration) / speed;
  const pre = opts.from ? Math.round((opts.fromTime ?? 0) * hz) : 0;
  resetForQA(char, opts.from || clip, { facing: opts.facing ?? 1, breath: opts.breath ?? 1 });
  if (!opts.from) char.play(clip, { fade: 0, restart: true, speed });
  const rec = record(char, {
    hz, frames: pre + Math.round(dur * hz) + 1,
    before: (i) => { if (opts.from && i === pre) char.play(clip, { fade: opts.fade ?? 0.1, restart: true, speed }); },
  });
  rec.clipName = clip; rec.loop = c.loop; rec.duration = c.duration; rec.switchFrame = opts.from ? pre : -1;
  rec.gripAt = c.gripAt;
  return rec;
}

// ---- accessors ----------------------------------------------------------------------------------------------------
/** World position of bone-local point (x,y,z) of bone `name` at frame f -> out. */
export function pointAt(rec, f, name, x, y, z, out = [0, 0, 0]) {
  const k = rec.idx[name];
  const o = (f * rec.B + k) * 12, M = rec.M;
  out[0] = M[o] * x + M[o + 3] * y + M[o + 6] * z + M[o + 9];
  out[1] = M[o + 1] * x + M[o + 4] * y + M[o + 7] * z + M[o + 10];
  out[2] = M[o + 2] * x + M[o + 5] * y + M[o + 8] * z + M[o + 11];
  return out;
}
/** World direction of the bone's local axis a (0 X, 1 Y, 2 Z) at frame f (unit length unless scaled). */
function axisAt(rec, f, name, a, out = [0, 0, 0]) {
  const o = (f * rec.B + rec.idx[name]) * 12 + a * 3, M = rec.M;
  out[0] = M[o]; out[1] = M[o + 1]; out[2] = M[o + 2];
  const l = Math.hypot(out[0], out[1], out[2]) || 1;
  out[0] /= l; out[1] /= l; out[2] /= l;
  return out;
}
const vget = (A, f) => [A[f * 3], A[f * 3 + 1], A[f * 3 + 2]];

// ---- 1. weapon tip path ---------------------------------------------------------------------------------------------
/**
 * Weapon-tip arc quality. A swing = frames with tip speed > vSwing (4 m/s x scale). Per swing: peak speed, path
 * length, `straight` = share of the path length whose radius of curvature exceeds `straightR` (3 m x scale) over >= 3
 * consecutive frames (a blade pivoting on shoulder + wrist never travels straight; long straight runs are the
 * signature of linear position interpolation), `kinks` = frames whose direction change exceeds max(8 deg, 3 x the
 * swing median) (curvature discontinuities at keys), `jerkSpikes` = |jerk| > 4 x the swing median and > 2e4 m/s^3,
 * `edge` = mean |cos| between the blade edge axis and the tip velocity across the blade (1 = cutting edge-first,
 * 0 = slapping with the flat), `flat` = share of swing frames with |cos| < 0.5. Also returns the per-frame series.
 */
export function tipPath(rec, opts = {}) {
  const n = rec.n, h = rec.h, s = rec.scale, P = rec.tip;
  const vSwing = (opts.vSwing ?? 4) * s, straightR = (opts.straightR ?? 3) * s;
  const speed = new Float64Array(n), turn = new Float64Array(n), radius = new Float64Array(n).fill(Infinity), jerk = new Float64Array(n), edge = new Float64Array(n);
  const Y = [0, 0, 0], X = [0, 0, 0];
  for (let i = 1; i < n - 1; i++) {
    const vx = (P[(i + 1) * 3] - P[(i - 1) * 3]) / (2 * h), vy = (P[(i + 1) * 3 + 1] - P[(i - 1) * 3 + 1]) / (2 * h), vz = (P[(i + 1) * 3 + 2] - P[(i - 1) * 3 + 2]) / (2 * h);
    const ax = (P[(i + 1) * 3] - 2 * P[i * 3] + P[(i - 1) * 3]) / (h * h), ay = (P[(i + 1) * 3 + 1] - 2 * P[i * 3 + 1] + P[(i - 1) * 3 + 1]) / (h * h), az = (P[(i + 1) * 3 + 2] - 2 * P[i * 3 + 2] + P[(i - 1) * 3 + 2]) / (h * h);
    const v = Math.hypot(vx, vy, vz);
    speed[i] = v;
    const cx = vy * az - vz * ay, cy = vz * ax - vx * az, cz = vx * ay - vy * ax;
    const k = v > 1e-6 ? Math.hypot(cx, cy, cz) / (v * v * v) : 0;
    radius[i] = k > 1e-9 ? 1 / k : Infinity;
    const ux = P[i * 3] - P[(i - 1) * 3], uy = P[i * 3 + 1] - P[(i - 1) * 3 + 1], uz = P[i * 3 + 2] - P[(i - 1) * 3 + 2];
    const wx = P[(i + 1) * 3] - P[i * 3], wy = P[(i + 1) * 3 + 1] - P[i * 3 + 1], wz = P[(i + 1) * 3 + 2] - P[i * 3 + 2];
    const lu = Math.hypot(ux, uy, uz), lw = Math.hypot(wx, wy, wz);
    turn[i] = lu > 1e-7 && lw > 1e-7 ? Math.acos(Math.max(-1, Math.min(1, (ux * wx + uy * wy + uz * wz) / (lu * lw)))) * R2D : 0;
    if (i < n - 2) {
      let j2 = 0;
      for (let d = 0; d < 3; d++) { const j = (P[(i + 2) * 3 + d] - 3 * P[(i + 1) * 3 + d] + 3 * P[i * 3 + d] - P[(i - 1) * 3 + d]) / (h * h * h); j2 += j * j; }
      jerk[i] = Math.sqrt(j2);
    }
    if (rec.weapon && v > 1e-3) {
      axisAt(rec, i, rec.weapon, 0, X); axisAt(rec, i, rec.weapon, 1, Y);
      const d = (vx * X[0] + vy * X[1] + vz * X[2]);
      const px = vx - X[0] * d, py = vy - X[1] * d, pz = vz - X[2] * d, pl = Math.hypot(px, py, pz);
      edge[i] = pl > 1e-6 ? Math.abs(px * Y[0] + py * Y[1] + pz * Y[2]) / pl : 1;
    }
  }
  // swings
  const swings = [];
  let i = 1;
  while (i < n - 1) {
    if (speed[i] <= vSwing) { i++; continue; }
    let j = i;
    while (j < n - 1 && (speed[j] > vSwing || (speed[j + 1] > vSwing && j + 1 < n - 1) || (speed[j + 2] > vSwing && j + 2 < n - 1))) j++;
    if (j - i >= 3) swings.push([i, j]);
    i = j + 1;
  }
  const out = [];
  for (const [a, b] of swings) {
    let len = 0, straight = 0, run = 0, runLen = 0, longest = 0, peak = 0, peakAt = a, jerkMax = 0, edgeSum = 0, flat = 0;
    const turns = [], jerks = [];
    for (let k = a; k <= b; k++) {
      const seg = Math.hypot(P[k * 3] - P[(k - 1) * 3], P[k * 3 + 1] - P[(k - 1) * 3 + 1], P[k * 3 + 2] - P[(k - 1) * 3 + 2]);
      len += seg;
      if (radius[k] > straightR) { run++; runLen += seg; } else { if (run >= 3) { straight += runLen; longest = Math.max(longest, runLen); } run = 0; runLen = 0; }
      if (speed[k] > peak) { peak = speed[k]; peakAt = k; }
      turns.push(turn[k]); jerks.push(jerk[k]);
      jerkMax = Math.max(jerkMax, jerk[k]);
      edgeSum += edge[k]; if (edge[k] < 0.5) flat++;
    }
    if (run >= 3) { straight += runLen; longest = Math.max(longest, runLen); }
    const mt = median(turns), mj = median(jerks);
    const kinks = [], spikes = [];
    for (let k = a; k <= b; k++) {
      if (turn[k] > Math.max(8, 3 * mt)) kinks.push({ t: r(rec.t[k]), deg: r(turn[k], 1) });
      if (jerk[k] > 4 * mj && jerk[k] > 2e4 * s) spikes.push({ t: r(rec.t[k]), jerk: Math.round(jerk[k]) });
    }
    const chord = Math.hypot(P[b * 3] - P[a * 3], P[b * 3 + 1] - P[a * 3 + 1], P[b * 3 + 2] - P[a * 3 + 2]);
    out.push({
      t0: r(rec.t[a]), t1: r(rec.t[b]), dur: r(rec.t[b] - rec.t[a]), peak: r(peakAt ? peak : 0, 2), peakT: r(rec.t[peakAt]), len: r(len), chord: r(chord),
      straight: r(len > 0 ? straight / len : 0), longestStraight: r(longest), maxTurn: r(Math.max(...turns), 1), medianTurn: r(mt, 2),
      kinks: kinks.length, kinkList: kinks.slice(0, 6), jerkMax: Math.round(jerkMax), jerkMedian: Math.round(mj), jerkSpikes: spikes.length, spikeList: spikes.slice(0, 6),
      edge: r(edgeSum / (b - a + 1)), flat: r(flat / (b - a + 1)),
    });
  }
  return { swings: out, series: { speed, turn, radius, jerk, edge } };
}

// ---- 2. angular velocity / acceleration / pops ---------------------------------------------------------------------
/**
 * Per bone (local rotation, i.e. the joint): peak angular speed (deg/s), peak angular acceleration (deg/s^2), pops and
 * over-speed. A pop is a velocity step |w(i+1) - w(i)| (deg/s, joint angular velocity in the parent frame) that is
 * > popAbs (120 deg/s per 1/120 s frame = 14,400 deg/s^2) AND > popRel (3) x the median step of the surrounding
 * +-6 frames (isolated: smooth fast motion has steady steps, a discontinuity stands alone). Over-speed: peak > MAX_SPEED.
 */
export function angular(rec, opts = {}) {
  const bones = (opts.bones || MAIN_BONES).filter((b) => rec.idx[b] !== undefined);
  const popAbs = opts.popAbs ?? 120, popRel = opts.popRel ?? 3, n = rec.n;
  const res = {};
  const w = new Float64Array(n * 3), step = new Float64Array(n), v = [0, 0, 0];
  for (const name of bones) {
    const k = rec.idx[name];
    w.fill(0); step.fill(0);
    let maxW = 0, maxWt = 0;
    for (let i = 0; i < n - 1; i++) {
      const h = rec.t[i + 1] - rec.t[i];
      if (h <= 1e-9) continue;
      qdelta(rec.Q, (i * rec.B + k) * 4, rec.Q, ((i + 1) * rec.B + k) * 4, v);
      w[i * 3] = (v[0] / h) * R2D; w[i * 3 + 1] = (v[1] / h) * R2D; w[i * 3 + 2] = (v[2] / h) * R2D;
      const m = Math.hypot(w[i * 3], w[i * 3 + 1], w[i * 3 + 2]);
      if (m > maxW) { maxW = m; maxWt = rec.t[i]; }
    }
    let maxA = 0;
    for (let i = 0; i < n - 2; i++) {
      step[i] = Math.hypot(w[(i + 1) * 3] - w[i * 3], w[(i + 1) * 3 + 1] - w[i * 3 + 1], w[(i + 1) * 3 + 2] - w[i * 3 + 2]);
      const h = rec.t[i + 1] - rec.t[i];
      if (h > 1e-9) maxA = Math.max(maxA, step[i] / h);
    }
    const pops = [];
    for (let i = 1; i < n - 3; i++) {
      if (step[i] < popAbs) continue;
      const around = [];
      for (let j = i - 6; j <= i + 6; j++) if (j >= 0 && j < n - 2 && Math.abs(j - i) > 1) around.push(step[j]);
      const m = median(around);
      if (step[i] > popRel * m && step[i] >= step[i - 1] && step[i] >= step[i + 1]) {
        pops.push({ t: r(rec.t[i + 1]), step: Math.round(step[i]), w0: Math.round(Math.hypot(w[i * 3], w[i * 3 + 1], w[i * 3 + 2])), w1: Math.round(Math.hypot(w[(i + 1) * 3], w[(i + 1) * 3 + 1], w[(i + 1) * 3 + 2])), ctx: Math.round(m) });
      }
    }
    const lim = MAX_SPEED[baseOf(name)];
    res[name] = { maxW: Math.round(maxW), maxWt: r(maxWt), maxA: Math.round(maxA), over: lim && maxW > lim ? Math.round(maxW - lim) : 0, pops };
  }
  const allPops = Object.entries(res).flatMap(([b, x]) => x.pops.map((p) => ({ bone: b, ...p }))).sort((a, b) => b.step - a.step);
  const over = Object.entries(res).filter(([, x]) => x.over > 0).map(([b, x]) => ({ bone: b, maxW: x.maxW, t: x.maxWt, limit: MAX_SPEED[baseOf(b)] }));
  return { bones: res, pops: allPops, over };
}

// ---- 3. joint limits ------------------------------------------------------------------------------------------------
/**
 * Range-of-motion violations (ROM / ROM_CHAINS). Per bone and axis: worst overshoot (deg), the value and time, and the
 * share of frames over by more than tol (2 deg). Left bones are mirrored back to the right-side convention.
 */
export function jointLimits(rec, opts = {}) {
  const rom = opts.rom || ROM, chains = opts.chains || ROM_CHAINS, tol = opts.tol ?? 2, n = rec.n;
  const out = [];
  const e = [0, 0, 0], q = [0, 0, 0, 1], qa = [0, 0, 0, 0], qb = [0, 0, 0, 0];
  const check = (label, vals, lims) => {
    for (const ax of Object.keys(lims)) {
      if (ax === 'bones') continue;
      const [lo, hi] = lims[ax];
      let worst = 0, wv = 0, wt = 0, cnt = 0;
      for (let i = 0; i < n; i++) {
        const v = vals(i, ax);
        const o = v > hi ? v - hi : v < lo ? lo - v : 0;
        if (o > tol) cnt++;
        if (o > worst) { worst = o; wv = v; wt = rec.t[i]; }
      }
      if (worst > tol) out.push({ joint: label, axis: ax, over: r(worst, 1), value: r(wv, 1), range: [lo, hi], t: r(wt), frac: r(cnt / n) });
    }
  };
  const getQ = (i, name, o) => { const b = (i * rec.B + rec.idx[name]) * 4; o[0] = rec.Q[b]; o[1] = rec.Q[b + 1]; o[2] = rec.Q[b + 2]; o[3] = rec.Q[b + 3]; return o; };
  const cache = new Map();
  const euler = (i, name, left, composed) => {
    const key = name + i;
    if (cache.has(key)) return cache.get(key);
    if (composed) { getQ(i, composed[0], qa); getQ(i, composed[1], qb); qmul(qa, qb, q); } else getQ(i, name, q);
    eulerZXY(q, 0, e);
    const swing = Math.acos(Math.max(-1, Math.min(1, 1 - 2 * (q[0] * q[0] + q[2] * q[2])))) * R2D; // angle between local Y and parent Y
    const res = { x: left ? -e[0] : e[0], y: left ? -e[1] : e[1], z: e[2], twist: (left ? -1 : 1) * twistY(q, 0), swing };
    cache.set(key, res);
    return res;
  };
  for (const [base, lims] of Object.entries(rom)) {
    const names = rec.idx[base] !== undefined ? [base] : ['R', 'L'].map((s) => base + s).filter((nm) => rec.idx[nm] !== undefined);
    for (const nm of names) check(nm, (i, ax) => euler(i, nm, nm.endsWith('L') && nm !== base)[ax], lims);
  }
  for (const [label, ch] of Object.entries(chains)) {
    if (ch.bones.some((b) => rec.idx[b] === undefined)) continue;
    check(label, (i, ax) => euler(i, label, false, ch.bones)[ax], ch);
  }
  out.sort((a, b) => b.over - a.over);
  return out;
}

// ---- 4. balance -----------------------------------------------------------------------------------------------------
function segPoint(rec, seg, f, out) {
  const [, bone, , p] = seg, L = rec.lengths, s = rec.scale;
  if (typeof p === 'string') {
    const [key, k] = p.split(':');
    const len = key === 'l1' ? L.upperArm : key === 'l2' ? L.foreArm : key === 'lt' ? L.thigh : key === 'ls' ? L.shin : rec.P.hand;
    return pointAt(rec, f, bone, 0, -len * Number(k), 0, out);
  }
  return pointAt(rec, f, bone, p[0] * s, p[1] * s, p[2] * s, out);
}

/** Foot contact points (bone, local point) of side 'R' / 'L': heel in/out, ball in/out, toe tip. */
function footPoints(rec, side) {
  const P = rec.P, s = rec.scale, w = 0.045 * s, foot = 'foot' + side, toe = 'toe' + side, by = -(P.ankleHeight - P.footDrop);
  return [[foot, -P.heelLength, -P.ankleHeight, w], [foot, -P.heelLength, -P.ankleHeight, -w], [toe, 0, by, w], [toe, 0, by, -w], [toe, P.toeLength, by, 0]];
}

/** Per-frame contact state of both feet: { pts: [[x,z]...] supporting points, flat: [R, L], any: [R, L], sole / ball positions }. */
export function contacts(rec, opts = {}) {
  const tolC = (opts.contact ?? 0.015) * rec.scale, n = rec.n, out = [];
  const tmp = [0, 0, 0];
  for (let f = 0; f < n; f++) {
    const fr = { pts: [], flat: [false, false], any: [false, false], sole: [], ball: [], minY: [0, 0] };
    ['R', 'L'].forEach((side, k) => {
      const pts = footPoints(rec, side);
      let heel = false, ball = false, minY = Infinity;
      pts.forEach(([b, x, y, z], j) => {
        pointAt(rec, f, b, x, y, z, tmp);
        minY = Math.min(minY, tmp[1]);
        if (tmp[1] < tolC) { fr.pts.push([tmp[0], tmp[2]]); if (j < 2) heel = true; else ball = true; }
      });
      fr.flat[k] = heel && ball; fr.any[k] = heel || ball; fr.minY[k] = minY;
      fr.sole.push(pointAt(rec, f, 'foot' + side, 0, -rec.P.ankleHeight, 0));
      fr.ball.push(pointAt(rec, f, 'toe' + side, 0, -(rec.P.ankleHeight - rec.P.footDrop), 0));
    });
    out.push(fr);
  }
  return out;
}

/**
 * Centre of mass (Winter segment table + weapon) vs the support polygon (convex hull of the foot contact points).
 * bothPlanted: frames where both feet are flat on the floor; `unsupported` = of those, frames where the COM ground
 * projection is outside the polygon by > tol (2 cm x scale) — a standing pose that would topple. xcom = extrapolated COM
 * (Hof: com + v / sqrt(g / h)) outside while both feet are planted (would have to step). single: one foot supporting.
 */
export function balance(rec, opts = {}) {
  const n = rec.n, s = rec.scale, tol = (opts.tol ?? 0.02) * s, wMass = opts.weaponMass ?? 0.03;
  const C = opts.contacts || contacts(rec, opts);
  const com = new Float64Array(n * 3), tmp = [0, 0, 0];
  const tipX = rec.tipOff ? rec.tipOff[0] * 0.15 : 0.22;
  for (let f = 0; f < n; f++) {
    let m = 0, x = 0, y = 0, z = 0;
    for (const seg of SEGMENTS) {
      if (rec.idx[seg[1]] === undefined) continue;
      segPoint(rec, seg, f, tmp);
      x += tmp[0] * seg[2]; y += tmp[1] * seg[2]; z += tmp[2] * seg[2]; m += seg[2];
    }
    if (rec.weapon && wMass > 0) { pointAt(rec, f, rec.weapon, tipX, 0, 0, tmp); x += tmp[0] * wMass; y += tmp[1] * wMass; z += tmp[2] * wMass; m += wMass; }
    com[f * 3] = x / m; com[f * 3 + 1] = y / m; com[f * 3 + 2] = z / m;
  }
  let both = 0, unsup = 0, maxOut = 0, maxOutT = 0, xOut = 0, xMax = 0, single = 0, singleOut = 0, singleMax = 0, air = 0;
  const dist = new Float64Array(n);
  for (let f = 0; f < n; f++) {
    const c = C[f];
    const poly = hull(c.pts);
    const d = polyDist(poly, com[f * 3], com[f * 3 + 2]);
    dist[f] = d;
    const nAny = (c.any[0] ? 1 : 0) + (c.any[1] ? 1 : 0);
    if (nAny === 0) { air++; continue; }
    if (c.flat[0] && c.flat[1]) {
      both++;
      if (d > tol) { unsup++; if (d > maxOut) { maxOut = d; maxOutT = rec.t[f]; } }
      if (f > 0 && f < n - 1 && rec.h) {
        const g = 9.81, hc = Math.max(0.3 * s, com[f * 3 + 1]), w0 = Math.sqrt(g / hc);
        const vx = (com[(f + 1) * 3] - com[(f - 1) * 3]) / (2 * rec.h), vz = (com[(f + 1) * 3 + 2] - com[(f - 1) * 3 + 2]) / (2 * rec.h);
        const dx = polyDist(poly, com[f * 3] + vx / w0, com[f * 3 + 2] + vz / w0);
        if (dx > tol) { xOut++; xMax = Math.max(xMax, dx); }
      }
    } else if (nAny === 1) {
      single++;
      if (d > 3 * tol) { singleOut++; singleMax = Math.max(singleMax, d); }
    }
  }
  const h = rec.h || 1 / QA_HZ;
  return {
    bothPlanted: r(both * h), unsupported: r(unsup * h), unsupportedFrac: r(both ? unsup / both : 0), maxOutside: r(maxOut), maxOutsideT: r(maxOutT),
    xcomOutside: r(xOut * h), xcomMax: r(xMax), single: r(single * h), singleOutside: r(singleOut * h), singleMax: r(singleMax), airborne: r(air * h),
    series: { com, dist },
  };
}

// ---- 5. feet --------------------------------------------------------------------------------------------------------
/**
 * Planted-foot quality. A contact run = >= 3 consecutive frames with a heel or ball point within 1.5 cm of the floor
 * (`pivot` if the heel never touches: judged on the ball, else on the sole point under the ankle). The run settles on
 * its first frame slower than 0.3 m/s; `skid` = distance travelled in contact before that (the foot skating into its
 * plant); symmetrically the run's fast tail is the lift-off (`lift`). Between settle and lift-off: `drift` (max
 * horizontal distance from the settled point), peak / mean slide speed, yaw
 * change, root travel and the moon-walk ratio = foot path / root travel (0 = the foot stays put while the body
 * travels, 1 = the foot glides along with the root).
 */
export function feet(rec, opts = {}) {
  const C = opts.contacts || contacts(rec, opts), n = rec.n, s = rec.scale, vSettle = (opts.settle ?? 0.3) * s;
  const plants = [];
  const hspeed = (A, i, k) => { const h = rec.t[i] - rec.t[i - 1]; return h > 1e-9 ? Math.hypot(A[i][k][0] - A[i - 1][k][0], A[i][k][2] - A[i - 1][k][2]) / h : 0; };
  const sole = C.map((c) => c.sole), ball = C.map((c) => c.ball);
  for (let k = 0; k < 2; k++) {
    const side = k === 0 ? 'R' : 'L';
    let f = 0;
    while (f < n) {
      if (!C[f].any[k]) { f++; continue; }
      let g = f;
      while (g + 1 < n && C[g + 1].any[k]) g++;
      if (g - f + 1 >= 3) {
        const pivot = !C.slice(f, g + 1).some((c) => c.flat[k]);
        const P = pivot ? ball : sole;
        // settle: first frame of the contact run whose horizontal speed is below vSettle; the distance covered in
        // contact before that is the landing skid (foot skating into its plant)
        let st = f;
        while (st < g && st > 0 && hspeed(P, st, k) > vSettle) st++;
        if (st === 0) st = f;
        // lift-off: the tail of the run that is faster than vSettle again (the foot leaving while still near the floor)
        let en = g;
        while (en > st + 1 && hspeed(P, en, k) > vSettle) en--;
        const skid = Math.hypot(P[st][k][0] - P[f][k][0], P[st][k][2] - P[f][k][2]);
        const lift = Math.hypot(P[g][k][0] - P[en][k][0], P[g][k][2] - P[en][k][2]);
        const s0 = P[st][k];
        let drift = 0, path = 0, vmax = 0, vmaxT = 0;
        const yaw = (fr) => { const a = [0, 0, 0]; axisAt(rec, fr, 'foot' + side, 0, a); return Math.atan2(-a[2], a[0]) * R2D; };
        const y0 = yaw(st);
        let yawMax = 0;
        for (let i = st; i <= en; i++) {
          drift = Math.max(drift, Math.hypot(P[i][k][0] - s0[0], P[i][k][2] - s0[2]));
          if (i > st) { const v = hspeed(P, i, k); path += v * (rec.t[i] - rec.t[i - 1]); if (v > vmax) { vmax = v; vmaxT = rec.t[i]; } }
          let dy = yaw(i) - y0; dy = ((dy + 540) % 360) - 180;
          yawMax = Math.max(yawMax, Math.abs(dy));
        }
        const rootTravel = Math.hypot(rec.root[en * 3] - rec.root[st * 3], rec.root[en * 3 + 2] - rec.root[st * 3 + 2]);
        const dur = rec.t[en] - rec.t[st];
        plants.push({
          foot: 'foot' + side, kind: pivot ? 'pivot' : 'flat', t0: r(rec.t[f]), settled: r(rec.t[st]), lifts: r(rec.t[en]), t1: r(rec.t[g]),
          skid: r(skid), lift: r(lift), drift: r(drift), slideMax: r(vmax), slideMaxT: r(vmaxT), slideMean: r(dur > 0 ? path / dur : 0), yaw: r(yawMax, 1),
          rootTravel: r(rootTravel), moonwalk: rootTravel > 0.02 * s ? r(path / rootTravel) : null,
        });
      }
      f = g + 1;
    }
  }
  plants.sort((a, b) => a.t0 - b.t0);
  const worst = plants.reduce((a, p) => (!a || p.drift > a.drift ? p : a), null);
  return { plants, maxDrift: worst ? worst.drift : 0, worst, maxSkid: r(Math.max(0, ...plants.map((p) => p.skid))), maxSlide: r(Math.max(0, ...plants.map((p) => p.slideMax))) };
}

// ---- 6. floor ---------------------------------------------------------------------------------------------------------
/** Lowest point per body group (m; < 0 = below the floor) and frames deeper than tol (5 mm x scale). */
export function floor(rec, opts = {}) {
  const n = rec.n, s = rec.scale, tol = (opts.tol ?? 0.005) * s, tmp = [0, 0, 0];
  const groups = {
    feet: (f) => Math.min(...['R', 'L'].flatMap((sd) => footPoints(rec, sd).map(([b, x, y, z]) => pointAt(rec, f, b, x, y, z, tmp)[1]))),
    hands: (f) => Math.min(...['R', 'L'].map((sd) => pointAt(rec, f, 'weapon' + sd, 0, 0, 0, tmp)[1] - 0.045 * s)),
    knees: (f) => Math.min(...['R', 'L'].map((sd) => pointAt(rec, f, 'shin' + sd, 0.07 * s, 0, 0, tmp)[1] - 0.03 * s)),
  };
  if (rec.weapon && rec.tipOff) {
    const bx = rec.baseOff ? rec.baseOff[0] : 0, tx = rec.tipOff[0];
    groups.blade = (f) => { let m = Infinity; for (let k = 0; k <= 12; k++) m = Math.min(m, pointAt(rec, f, rec.weapon, bx + (tx - bx) * (k / 12), 0, 0, tmp)[1]); return m; };
    groups.pommel = (f) => pointAt(rec, f, rec.weapon, -0.27 * (tx / 1.47), 0, 0, tmp)[1] - 0.035 * s;
  }
  const out = {};
  for (const [g, fn] of Object.entries(groups)) {
    let min = Infinity, at = 0, below = 0, first = null;
    for (let f = 0; f < n; f++) { const y = fn(f); if (y < min) { min = y; at = rec.t[f]; } if (y < -tol) { below++; if (first === null) first = rec.t[f]; } }
    out[g] = { min: r(min), t: r(at), below: r(below * (rec.h || 1 / QA_HZ)), first: first === null ? null : r(first) };
  }
  return out;
}

// ---- 7. self-intersection proxies --------------------------------------------------------------------------------------
/**
 * Body capsules (bone, local a, bone, local b, radius) sized from the proportions; the knight's armour shells are a few
 * cm outside the bones, so radii are armour-inclusive. Pairs exclude jointed neighbours. `blade` = the weapon from the
 * guard to the tip (radius 2 cm) against everything except the hand / forearm holding it and the off hand.
 */
export function bodyCapsules(rec) {
  const s = rec.scale, L = rec.lengths, P = rec.P;
  const c = [
    ['torso', 'spine', [0, 0.02, 0], 'chest', [0, 0.17, 0], 0.15],
    ['pelvis', 'hips', [0, -0.05, -0.08], 'hips', [0, -0.05, 0.08], 0.13],
    ['head', 'head', [0.02, 0.06, 0], 'head', [0.02, 0.12, 0], 0.12],
  ].map(([nm, a, pa, b, pb, rr]) => [nm, a, pa.map((v) => v * s), b, pb.map((v) => v * s), rr * s]);
  for (const sd of ['R', 'L']) {
    c.push(['upperArm' + sd, 'upperArm' + sd, [0, -0.05 * s, 0], 'upperArm' + sd, [0, -(L.upperArm - 0.03 * s), 0], 0.06 * s]);
    c.push(['foreArm' + sd, 'foreArm' + sd, [0, -0.03 * s, 0], 'foreArm' + sd, [0, -(L.foreArm - 0.03 * s), 0], 0.05 * s]);
    c.push(['hand' + sd, 'hand' + sd, [0, -0.03 * s, 0], 'hand' + sd, [0, -P.hand, 0], 0.04 * s]);
    c.push(['thigh' + sd, 'thigh' + sd, [0, -0.06 * s, 0], 'thigh' + sd, [0, -(L.thigh - 0.05 * s), 0], 0.085 * s]);
    c.push(['shin' + sd, 'shin' + sd, [0, -0.05 * s, 0], 'shin' + sd, [0, -(L.shin - 0.05 * s), 0], 0.06 * s]);
    c.push(['foot' + sd, 'foot' + sd, [-0.04 * s, -0.05 * s, 0], 'toe' + sd, [0.03 * s, -0.015 * s, 0], 0.045 * s]);
  }
  if (rec.weapon && rec.tipOff) c.push(['blade', rec.weapon, [rec.baseOff ? rec.baseOff[0] : 0.09, 0, 0], rec.weapon, [rec.tipOff[0], 0, 0], 0.02 * s]);
  return c;
}
const ADJ = new Set(['torso|pelvis', 'pelvis|thighR', 'pelvis|thighL', 'upperArmR|foreArmR', 'upperArmL|foreArmL', 'foreArmR|handR', 'foreArmL|handL',
  'thighR|shinR', 'thighL|shinL', 'shinR|footR', 'shinL|footL', 'torso|head']);
const NOT_BLADE = (main) => new Set(['hand' + main, 'foreArm' + main, 'hand' + (main === 'R' ? 'L' : 'R')]);

/**
 * Max penetration depth per capsule pair, relative to the rest (zero-pose) depth: depth = r1 + r2 - distance. Pairs with
 * a depth increase > tol (1.5 cm x scale) are returned, with time, frames and the blade pairs separately.
 */
export function intersections(rec, opts = {}) {
  const caps = opts.capsules || bodyCapsules(rec), s = rec.scale, tol = (opts.tol ?? 0.015) * s, n = rec.n;
  const main = (rec.weapon || 'weaponR').slice(-1);
  const skipBlade = NOT_BLADE(main);
  const pairs = [];
  for (let i = 0; i < caps.length; i++) for (let j = i + 1; j < caps.length; j++) {
    const a = caps[i][0], b = caps[j][0];
    if (ADJ.has(a + '|' + b) || ADJ.has(b + '|' + a)) continue;
    if ((a === 'blade' || b === 'blade') && skipBlade.has(a === 'blade' ? b : a)) continue;
    pairs.push([i, j]);
  }
  const rest = opts.rest || null;
  const pa = [0, 0, 0], pb = [0, 0, 0], qa = [0, 0, 0], qb = [0, 0, 0];
  const res = [];
  for (const [i, j] of pairs) {
    const A = caps[i], Bc = caps[j];
    let worst = -Infinity, wt = 0, cnt = 0;
    const r0 = rest ? rest[A[0] + '|' + Bc[0]] ?? 0 : 0;
    for (let f = 0; f < n; f++) {
      pointAt(rec, f, A[1], ...A[2], pa); pointAt(rec, f, A[3], ...A[4], pb);
      pointAt(rec, f, Bc[1], ...Bc[2], qa); pointAt(rec, f, Bc[3], ...Bc[4], qb);
      const d = A[5] + Bc[5] - segDist(pa, pb, qa, qb) - Math.max(0, r0);
      if (d > worst) { worst = d; wt = rec.t[f]; }
      if (d > tol) cnt++;
    }
    if (worst > tol) res.push({ pair: A[0] + '|' + Bc[0], depth: r(worst), t: r(wt), time: r(cnt * (rec.h || 1 / QA_HZ)), blade: A[0] === 'blade' || Bc[0] === 'blade' });
  }
  res.sort((a, b) => b.depth - a.depth);
  return res;
}

/** Rest depths (r1 + r2 - distance) of every capsule pair in a 1-frame recording (pass as opts.rest). */
export function restDepths(rec) {
  const caps = bodyCapsules(rec), out = {}, pa = [0, 0, 0], pb = [0, 0, 0], qa = [0, 0, 0], qb = [0, 0, 0];
  for (let i = 0; i < caps.length; i++) for (let j = i + 1; j < caps.length; j++) {
    const A = caps[i], Bc = caps[j];
    pointAt(rec, 0, A[1], ...A[2], pa); pointAt(rec, 0, A[3], ...A[4], pb);
    pointAt(rec, 0, Bc[1], ...Bc[2], qa); pointAt(rec, 0, Bc[3], ...Bc[4], qb);
    out[A[0] + '|' + Bc[0]] = A[5] + Bc[5] - segDist(pa, pb, qa, qb);
  }
  return out;
}

// ---- 8. joint position velocity steps (seams, crossfades) ---------------------------------------------------------------
/** Joints whose world-position velocity steps are tracked (body landmarks + the weapon tip). */
export const LANDMARKS = ['hips', 'chest', 'head', 'foreArmR', 'foreArmL', 'weaponR', 'weaponL', 'shinR', 'shinL', 'footR', 'footL'];

/** Per frame: max over landmarks of |v(i+1) - v(i)| (m/s) of world positions, and of the weapon tip. */
export function velocitySteps(rec) {
  const n = rec.n, body = new Float64Array(n), tip = new Float64Array(n), who = new Array(n);
  const lm = LANDMARKS.filter((b) => rec.idx[b] !== undefined);
  const pos = (f, b, o) => { const x = (f * rec.B + rec.idx[b]) * 12 + 9; o[0] = rec.M[x]; o[1] = rec.M[x + 1]; o[2] = rec.M[x + 2]; return o; };
  const a = [0, 0, 0], b = [0, 0, 0], c = [0, 0, 0];
  for (let i = 1; i < n - 1; i++) {
    const h0 = rec.t[i] - rec.t[i - 1], h1 = rec.t[i + 1] - rec.t[i];
    if (h0 <= 1e-9 || h1 <= 1e-9) continue;
    let m = 0, mw = null;
    for (const bn of lm) {
      pos(i - 1, bn, a); pos(i, bn, b); pos(i + 1, bn, c);
      const d = Math.hypot((c[0] - b[0]) / h1 - (b[0] - a[0]) / h0, (c[1] - b[1]) / h1 - (b[1] - a[1]) / h0, (c[2] - b[2]) / h1 - (b[2] - a[2]) / h0);
      if (d > m) { m = d; mw = bn; }
    }
    body[i] = m; who[i] = mw;
    const T = rec.tip;
    tip[i] = Math.hypot((T[(i + 1) * 3] - T[i * 3]) / h1 - (T[i * 3] - T[(i - 1) * 3]) / h0, (T[(i + 1) * 3 + 1] - T[i * 3 + 1]) / h1 - (T[i * 3 + 1] - T[(i - 1) * 3 + 1]) / h0, (T[(i + 1) * 3 + 2] - T[i * 3 + 2]) / h1 - (T[i * 3 + 2] - T[(i - 1) * 3 + 2]) / h0);
  }
  return { body, tip, who };
}

/** Max angular velocity step over MAIN_BONES per frame (deg/s): the joint-space version of velocitySteps. */
export function angularSteps(rec, bones = MAIN_BONES) {
  const n = rec.n, out = new Float64Array(n), who = new Array(n), v0 = [0, 0, 0], v1 = [0, 0, 0];
  const list = bones.filter((b) => rec.idx[b] !== undefined);
  for (let i = 1; i < n - 1; i++) {
    const h0 = rec.t[i] - rec.t[i - 1], h1 = rec.t[i + 1] - rec.t[i];
    if (h0 <= 1e-9 || h1 <= 1e-9) continue;
    let m = 0, mw = null;
    for (const b of list) {
      const k = rec.idx[b];
      qdelta(rec.Q, ((i - 1) * rec.B + k) * 4, rec.Q, (i * rec.B + k) * 4, v0);
      qdelta(rec.Q, (i * rec.B + k) * 4, rec.Q, ((i + 1) * rec.B + k) * 4, v1);
      const d = Math.hypot(v1[0] / h1 - v0[0] / h0, v1[1] / h1 - v0[1] / h0, v1[2] / h1 - v0[2] / h0) * R2D;
      if (d > m) { m = d; mw = b; }
    }
    out[i] = m; who[i] = mw;
  }
  return { steps: out, who };
}

/**
 * Loop-seam continuity in the full runtime: for every frame where the clip time wraps, the joint angular velocity step,
 * the landmark / tip velocity steps and the root velocity before / after, compared with the 95th percentile of the
 * same quantity over the whole recording (ratio > 2 = the seam is a visible hitch).
 */
export function seam(rec) {
  const ang = angularSteps(rec), vel = velocitySteps(rec), n = rec.n;
  const p95a = pct(Array.from(ang.steps).filter((x) => x > 0), 0.95), p95v = pct(Array.from(vel.body).filter((x) => x > 0), 0.95);
  const out = [];
  for (let i = 2; i < n - 2; i++) {
    if (!(rec.clipT[i] < rec.clipT[i - 1] - 1e-6)) continue;
    let a = 0, aw = null, v = 0, vw = null;
    for (let j = i - 2; j <= i + 1; j++) { if (ang.steps[j] > a) { a = ang.steps[j]; aw = ang.who[j]; } if (vel.body[j] > v) { v = vel.body[j]; vw = vel.who[j]; } }
    const h = rec.t[i] - rec.t[i - 1];
    const rv0 = (rec.root[(i - 1) * 3] - rec.root[(i - 2) * 3]) / h, rv1 = (rec.root[(i + 1) * 3] - rec.root[i * 3]) / h;
    out.push({ t: r(rec.t[i]), angStep: Math.round(a), angBone: aw, angP95: Math.round(p95a), angRatio: r(p95a > 0 ? a / p95a : 0, 2), velStep: r(v), velJoint: vw, velP95: r(p95v), velRatio: r(p95v > 0 ? v / p95v : 0, 2), rootV: [r(rv0), r(rv1)] });
  }
  return out;
}

// ---- 9. clip data continuity -------------------------------------------------------------------------------------------
/**
 * Velocity continuity of the clip DATA (sampler output before IK / blending) at every interior key time and across
 * the loop seam: per FK bone (deg/s), hips position (m/s) and IK effector position (m/s), the velocity just before vs
 * just after the key (eps = 0.5 ms). A step on a channel that keeps moving is a C1 break introduced by the sampler
 * (ease remaps, tangents). Returns the steps above minStep, worst first.
 */
export function keyContinuity(rig, clipName, opts = {}) {
  const c = getClip(rig, clipName), d = c.duration, eps = opts.eps ?? 5e-4, minAng = opts.minAng ?? 60, minLin = opts.minLin ?? 0.25;
  const times = new Set();
  const addTimes = (tr) => { if (tr) for (let i = 0; i < tr.n; i++) times.add(Math.round(tr.times[i] * 1e6) / 1e6); };
  c.bones.forEach((b) => addTimes(b.tr)); addTimes(c.hipsRot); addTimes(c.hipsPos); addTimes(c.root);
  c.ik.forEach((E) => { if (E) { addTimes(E.posA); addTimes(E.posB); addTimes(E.rotA); } });
  const L0 = new Pose(rig), L1 = new Pose(rig), R0 = new Pose(rig), R1 = new Pose(rig);
  const at = (t, p) => sampleClip(rig, c, Math.max(0, Math.min(d, t)), p);
  const out = [];
  const push = (o) => out.push(o);
  for (const t of [...times].sort((a, b) => a - b)) {
    if (t >= d - 1e-6) continue;                 // the end of a one-shot has nothing after it; a loop's end is its seam (t = 0)
    const seamKey = c.loop && t <= 1e-6;
    if (!c.loop && t <= 1e-6) continue;
    // left side [t - eps, t] (seam: [d - eps, d]), right side [t, t + eps]
    at(seamKey ? d - eps : t - eps, L0); at(seamKey ? d : t, L1); at(t, R0); at(t + eps, R1);
    for (const b of c.bones) {
      const vl = (qangle(L0.lq, b.i * 4, L1.lq, b.i * 4) / eps) * R2D, vr = (qangle(R0.lq, b.i * 4, R1.lq, b.i * 4) / eps) * R2D;
      const gap = seamKey ? qangle(L1.lq, b.i * 4, R0.lq, b.i * 4) * R2D : 0;
      if (Math.abs(vl - vr) > minAng || gap > 0.5) push({ t: r(t), ch: rig.names[b.i], unit: 'deg/s', before: Math.round(vl), after: Math.round(vr), step: Math.round(Math.abs(vl - vr)), gap: r(gap, 2), seam: seamKey });
    }
    {
      const vl = (qangle(L0.lq, 0, L1.lq, 0) / eps) * R2D, vr = (qangle(R0.lq, 0, R1.lq, 0) / eps) * R2D;
      const gap = seamKey ? qangle(L1.lq, 0, R0.lq, 0) * R2D : 0;
      if (Math.abs(vl - vr) > minAng || gap > 0.5) push({ t: r(t), ch: 'hips.rot', unit: 'deg/s', before: Math.round(vl), after: Math.round(vr), step: Math.round(Math.abs(vl - vr)), gap: r(gap, 2), seam: seamKey });
      const v = (A, B, k) => (B[k] - A[k]) / eps;
      const lin = (name, A0, A1, B0, B1, key, n, gapW = true) => {
        const vl3 = [], vr3 = [];
        for (let k = 0; k < n; k++) { vl3.push(v(A0[key], A1[key], k)); vr3.push(v(B0[key], B1[key], k)); }
        const step = Math.hypot(...vl3.map((x, k) => x - vr3[k]));
        const gap = seamKey && gapW ? Math.hypot(...vl3.map((_, k) => A1[key][k] - B0[key][k])) : 0;
        if (step > minLin || gap > 0.002) push({ t: r(t), ch: name, unit: 'm/s', before: r(Math.hypot(...vl3)), after: r(Math.hypot(...vr3)), step: r(step), gap: r(gap), seam: seamKey });
      };
      lin('hips.pos', L0, L1, R0, R1, 'hips', 3);
      if (c.root) lin('root', L0, L1, R0, R1, 'root', 2, false); // the root wraps by design (rootEnd is carried over)
    }
    for (let e = 0; e < EFFECTORS.length; e++) {
      const o = e * EFF_STRIDE;
      if (!(L0.ik[o] > 0 && L1.ik[o] > 0 && R0.ik[o] > 0 && R1.ik[o] > 0)) continue;
      const org = c.ik[e] && c.ik[e].origin ? 1 : 0; // origin-space effectors: judge the velocity in the origin (world) frame
      const vel = (A, B) => [(B.ik[o + 1] - A.ik[o + 1] + org * (B.root[0] - A.root[0])) / eps, (B.ik[o + 2] - A.ik[o + 2] + org * (B.root[1] - A.root[1])) / eps, (B.ik[o + 3] - A.ik[o + 3]) / eps];
      const vl = vel(L0, L1), vr = vel(R0, R1);
      const step = Math.hypot(vl[0] - vr[0], vl[1] - vr[1], vl[2] - vr[2]);
      const gap = seamKey ? Math.hypot(L1.ik[o + 1] - R0.ik[o + 1], L1.ik[o + 2] - R0.ik[o + 2], L1.ik[o + 3] - R0.ik[o + 3]) : 0;
      if (step > minLin || gap > 0.002) push({ t: r(t), ch: 'ik.' + EFFECTORS[e], unit: 'm/s', before: r(Math.hypot(...vl)), after: r(Math.hypot(...vr)), step: r(step), gap: r(gap), seam: seamKey });
    }
  }
  out.sort((a, b) => (b.unit === 'deg/s' ? b.step / 200 : b.step) - (a.unit === 'deg/s' ? a.step / 200 : a.step));
  return out;
}

// ---- 10. crossfade pops ----------------------------------------------------------------------------------------------
/**
 * Crossfade `a` -> `b` after `at` seconds of `a` with `fade`. Returns the largest joint angular velocity step and
 * landmark / tip velocity step inside the transition (from 2 frames before the switch to 2 frames after the fade),
 * the same maxima over each clip played alone (baselines: the steps the clips themselves contain), and the ratios.
 * ratio > 1.5 with a step above the absolute floors (angular 200 deg/s, body 1.5 m/s per 1/120 s frame) = pop.
 */
export function crossfade(char, a, b, opts = {}) {
  const hz = opts.hz || QA_HZ, fade = opts.fade ?? 0.1, at = opts.at ?? 0.3, post = opts.post ?? 0.2;
  const base = opts.baselines || {};
  const bl = (name) => {
    if (base[name]) return base[name];
    const rec = recordClip(char, name, { hz, breath: 0 });
    const ang = angularSteps(rec), vel = velocitySteps(rec);
    return (base[name] = { ang: Math.max(...ang.steps), body: Math.max(...vel.body), tip: Math.max(...vel.tip) });
  };
  const A = bl(a), Bb = bl(b);
  const rec = recordClip(char, b, { hz, from: a, fromTime: at, fade, duration: fade + post, breath: 0 });
  const ang = angularSteps(rec), vel = velocitySteps(rec);
  const i0 = Math.max(1, rec.switchFrame - 2), i1 = Math.min(rec.n - 2, rec.switchFrame + Math.round(fade * hz) + 2);
  let ma = 0, maw = null, mat = 0, mb = 0, mbw = null, mbt = 0, mt = 0;
  for (let i = i0; i <= i1; i++) {
    if (ang.steps[i] > ma) { ma = ang.steps[i]; maw = ang.who[i]; mat = rec.t[i] - rec.t[rec.switchFrame]; }
    if (vel.body[i] > mb) { mb = vel.body[i]; mbw = vel.who[i]; mbt = rec.t[i] - rec.t[rec.switchFrame]; }
    mt = Math.max(mt, vel.tip[i]);
  }
  const refA = Math.max(A.ang, Bb.ang), refB = Math.max(A.body, Bb.body), refT = Math.max(A.tip, Bb.tip);
  return {
    from: a, to: b, at, fade, nan: rec.nan,
    ang: Math.round(ma), angBone: maw, angT: r(mat), angRef: Math.round(refA), angRatio: r(refA > 0 ? ma / refA : 0, 2),
    body: r(mb), bodyJoint: mbw, bodyT: r(mbt), bodyRef: r(refB), bodyRatio: r(refB > 0 ? mb / refB : 0, 2),
    tip: r(mt), tipRef: r(refT), tipRatio: r(refT > 0 ? mt / refT : 0, 2),
    pop: (ma > 200 && ma > 1.5 * refA) || (mb > 1.5 && mb > 1.5 * refB),
  };
}

// ---- 11. pose signatures (determinism) -----------------------------------------------------------------------------------
/** Snapshot of the animated pose: local quaternions + model-space (root-relative) positions of MAIN_BONES + weapons. */
export function poseOf(char, bones = [...MAIN_BONES, 'weaponR', 'weaponL']) {
  const list = bones.filter((b) => char.bones[b]);
  const q = new Float64Array(list.length * 4), p = new Float64Array(list.length * 3);
  const re = char.root.matrixWorld.elements, rx = re[12], ry = re[13], rz = re[14];
  list.forEach((b, k) => {
    const bn = char.bones[b], e = bn.matrixWorld.elements;
    q[k * 4] = bn.quaternion.x; q[k * 4 + 1] = bn.quaternion.y; q[k * 4 + 2] = bn.quaternion.z; q[k * 4 + 3] = bn.quaternion.w;
    p[k * 3] = e[12] - rx; p[k * 3 + 1] = e[13] - ry; p[k * 3 + 2] = e[14] - rz;
  });
  return { bones: list, q, p };
}

/** Largest difference between two pose signatures: { deg, degBone, mm, mmBone }. */
export function poseDiff(a, b) {
  let deg = 0, db = null, mm = 0, mb = null;
  a.bones.forEach((nm, k) => {
    const d = qangle(a.q, k * 4, b.q, k * 4) * R2D;
    if (d > deg) { deg = d; db = nm; }
    const m = Math.hypot(a.p[k * 3] - b.p[k * 3], a.p[k * 3 + 1] - b.p[k * 3 + 1], a.p[k * 3 + 2] - b.p[k * 3 + 2]) * 1000;
    if (m > mm) { mm = m; mb = nm; }
  });
  return { deg: r(deg, 4), degBone: db, mm: r(mm, 3), mmBone: mb };
}

// ---- 12. one-call clip audit ---------------------------------------------------------------------------------------------
/**
 * Every metric for one clip (recorded at 120 Hz from a clean reset; loops run two cycles). opts: recordClip opts +
 * { rest } (restDepths of a neutral recording). Returns a compact summary plus the recording (rec) for plots.
 */
export function auditClip(char, clip, opts = {}) {
  const rec = recordClip(char, clip, opts);
  const C = contacts(rec);
  const tp = tipPath(rec), an = angular(rec), jl = jointLimits(rec), ba = balance(rec, { contacts: C }), fe = feet(rec, { contacts: C });
  const fl = floor(rec), ix = intersections(rec, { rest: opts.rest }), se = rec.loop ? seam(rec) : [], kc = keyContinuity(char.rig, clip);
  const ms = Array.from(rec.ms);
  return {
    clip, duration: r(rec.duration), loop: rec.loop, frames: rec.n, nan: rec.nan,
    events: rec.events.map((e) => [r(rec.t[e.i]), e.name]),
    rootEnd: [r(rec.root[(rec.n - 1) * 3]), r(rec.root[(rec.n - 1) * 3 + 1])],
    tip: tp.swings, angular: { pops: an.pops, over: an.over, peak: Object.fromEntries(Object.entries(an.bones).map(([b, x]) => [b, [x.maxW, x.maxA]])) },
    limits: jl, balance: { ...ba, series: undefined }, feet: fe, floor: fl, intersections: ix, seam: se, keys: kc,
    cpu: { mean: r(ms.reduce((a, x) => a + x, 0) / ms.length, 3), p95: r(pct(ms, 0.95), 3), max: r(Math.max(...ms), 3) },
    rec, series: { tip: tp.series, com: ba.series },
  };
}
