// Rig audit lab, round 2, lens R2B: math, IK, grip, runtime and naturalness metrics. Read-only on src/char: every
// number here is measured on the shipped runtime (and on the real fighter clips authored on top of it).
//
//   node tools/shot.mjs rigaudit_r2b --eval "__ED.audit.run('realClips', 'kael')"     JSON results (__ED.audit.list())
//   tests:
//     realClips(fighter, filter?)   every registered <fighter>.* clip on a rig-only copy of the real design: elbow
//                                   swivel jumps, weapon aim / roll vs the key, fist error, clavicle assist, wrist,
//                                   grip error, pelvis drop, helper steps, head snaps
//     demoClips(gripAngle?)          the same metrics on the demo clips (knight, optional gripAngle override)
//     feasible(n, seed)              human-feasible FK arm paths replayed as hand IK targets: elbow flips + aim error
//     lookSpin()                     lookAt(opponent head) during spins / a target circling the fighter: head snaps
//     layerIK()                      masked upper-body attack layer over a walk: hand / tip vs the clip's own targets,
//                                    layer fade-in velocity step vs a crossfade
//     floorPole()                    authored knee pole on a planted foot that the floor contact has to re-solve
//     clavicle()                     clavicle assist applied more than once per frame (clip IK + reach-grip + grip)
//     cpu()                          ms per update (uncontended estimate)
//   scenarios (captures): clip(fighter, name, view) look(clip) feasible(seed) floorpole layer

import * as THREE from 'three';
import { RoomEnvironment } from 'three/examples/jsm/environments/RoomEnvironment.js';
import { createLab, ORDER } from '../core/lab.js';
import { makeRng } from '../core/math.js';
import { createCharacter, defineClip, invalidateClips, listClips } from '../char/index.js';
import { getClip, sampleClip, Pose } from '../char/anim.js';
import { createRig } from '../char/skeleton.js';
import { qfromBasis } from '../char/rigmath.js';
import * as qa from '../char/qa.js';
import { knight } from '../char/designs/knight.js';
import '../char/clips/demo.js';
import { kael } from '../fighters/kael/design.js';
import { iska } from '../fighters/iska/design.js';
import { vorn } from '../fighters/vorn/design.js';
import '../fighters/kael/clips/index.js';
import '../fighters/iska/clips/index.js';
import '../fighters/vorn/clips/index.js';

const R2D = 180 / Math.PI;
const r = (x, d = 1) => (Number.isFinite(x) ? Math.round(x * 10 ** d) / 10 ** d : x);
const DEMO = ['demo.idle', 'demo.guard', 'demo.walkF', 'demo.walkB', 'demo.combo1', 'demo.combo2', 'demo.combo3', 'demo.slam', 'demo.hit', 'demo.combo1M'];
const REAL = { kael, iska, vorn };

let CTX = null;
const cache = new Map();

/** A rig-only copy of a design: proportions, grip angle, weapons, colliders (no armour, no cloth / springs). */
function rigOnly(d, over = {}) {
  const std = new Set(createRig(d.proportions || {}).names);
  const colliders = (d.colliders || []).filter((c) => std.has(c.a[0]) && std.has(c.b[0]));
  return {
    id: 'r2b_' + (d.id || 'x'), idle: 'neutral.hold', proportions: d.proportions || {}, gripAngle: d.gripAngle,
    clipScale: d.clipScale, maxPelvisDrop: d.maxPelvisDrop,
    materials: { suit: {} }, bones: [], springs: [], cloth: [], colliders,
    weapon: d.weapon, weapons: d.weapons, sockets: {},
    build(kit, S) { kit.add('suit', 'chest', S.box(0.05, 0.05, 0.05, 0.005), {}); },
    ...over,
  };
}
function mk(id, over = {}) {
  const key = id + JSON.stringify(over);
  if (cache.has(key)) return cache.get(key);
  const base = id === 'knight' ? knight : REAL[id];
  const c = createCharacter(CTX, rigOnly(base, over), { parent: null, name: 'r2b_' + id });
  cache.set(key, c);
  return c;
}

// ---- recording helpers ------------------------------------------------------------------------------------------
const qv = new Float64Array(4);
/** World rotation of a recorded bone at frame f (from the 3x4 axes). */
function boneQ(rec, f, name, out = new Float64Array(4)) {
  const o = (f * rec.B + rec.idx[name]) * 12, M = rec.M;
  const X = [M[o], M[o + 1], M[o + 2]], Y = [M[o + 3], M[o + 4], M[o + 5]], Z = [M[o + 6], M[o + 7], M[o + 8]];
  for (const v of [X, Y, Z]) { const l = Math.hypot(v[0], v[1], v[2]) || 1; v[0] /= l; v[1] /= l; v[2] /= l; }
  qfromBasis(out, 0, X, Y, Z);
  return out;
}
/** Model-space (root-relative; recordings keep the root unrotated, facing +X) position of a bone point at frame f. */
function mpos(rec, f, name, x = 0, y = 0, z = 0) {
  const p = qa.pointAt(rec, f, name, x, y, z);
  p[0] -= rec.root[f * 3]; p[1] -= rec.root[f * 3 + 1]; p[2] -= rec.root[f * 3 + 2];
  return p;
}
const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const len = (a) => Math.hypot(a[0], a[1], a[2]);
const qrotv = (q, v) => {
  const [x, y, z, w] = q, tx = 2 * (y * v[2] - z * v[1]), ty = 2 * (z * v[0] - x * v[2]), tz = 2 * (x * v[1] - y * v[0]);
  return [v[0] + w * tx + y * tz - z * ty, v[1] + w * ty + z * tx - x * tz, v[2] + w * tz + x * ty - y * tx];
};
const qmulA = (a, b) => [a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1], a[3] * b[1] + a[1] * b[3] + a[2] * b[0] - a[0] * b[2], a[3] * b[2] + a[2] * b[3] + a[0] * b[1] - a[1] * b[0], a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2]];
const qang = (a, b) => 2 * Math.acos(Math.min(1, Math.abs(a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3]))) * R2D;
const vang = (a, b) => Math.acos(Math.max(-1, Math.min(1, dot(a, b) / ((len(a) * len(b)) || 1)))) * R2D;

/** Elbow swivel step (deg) between frames f-1 and f: angle between the elbow's offsets from the shoulder-wrist line. */
function swivelStep(rec, f, S) {
  const perp = (g) => {
    const s = mpos(rec, g, 'upperArm' + S), w = mpos(rec, g, 'hand' + S), e = mpos(rec, g, 'foreArm' + S);
    const a = sub(w, s), la = len(a) || 1; a[0] /= la; a[1] /= la; a[2] /= la;
    const v = sub(e, s), k = dot(v, a);
    return { p: [v[0] - a[0] * k, v[1] - a[1] * k, v[2] - a[2] * k], a };
  };
  const A = perp(f - 1), B = perp(f);
  // project A's offset onto B's plane so a moving axis does not count as swivel
  const k = dot(A.p, B.a), pa = [A.p[0] - B.a[0] * k, A.p[1] - B.a[1] * k, A.p[2] - B.a[2] * k];
  if (len(pa) < 0.02 * rec.scale || len(B.p) < 0.02 * rec.scale) return 0;
  return vang(pa, B.p);
}

/**
 * Requested weapon-hand target of the clip at frame f (model space): { pos, q (weapon frame) | null } or null when the
 * hand is not fully IK-driven in a single space.
 */
function requested(c, rec, f, cl, pose, e = 0) {
  sampleClip(c.rig, cl, rec.clipT[f], pose, c.design.clipScale ?? 1);
  const o = e * 24, ik = pose.ik;
  if (!(ik[o] > 0.999)) return null;
  const sp = ik[o + 14], k = ik[o + 15];
  if (sp >= 2 && k > 0.999) {
    const bn = sp === 2 ? 'hips' : 'chest', bq = boneQ(rec, f, bn), bp = mpos(rec, f, bn);
    const p = qrotv(bq, [ik[o + 16], ik[o + 17], ik[o + 18]]);
    return { pos: [bp[0] + p[0], bp[1] + p[1], bp[2] + p[2]], q: ik[o + 23] ? qmulA(Array.from(bq), [ik[o + 19], ik[o + 20], ik[o + 21], ik[o + 22]]) : null };
  }
  if (sp >= 2 && k > 0.001) return null;
  return { pos: [ik[o + 1], ik[o + 2], ik[o + 3]], q: ik[o + 8] ? [ik[o + 4], ik[o + 5], ik[o + 6], ik[o + 7]] : null };
}

/** Run one clip (single state, no fade, breathing off) and measure everything per frame. */
function measureClip(c, name, { hz = 60, look = null, loops = 1 } = {}) {
  const cl = getClip(c.rig, name);
  qa.resetForQA(c, name, { breath: 0 });
  if (look) c.lookAt(look, 0.85);
  const dur = cl.loop ? loops * cl.duration : cl.duration;
  const n = Math.round(dur * hz) + 1;
  const diag = [];
  const rec = qa.record(c, { hz, frames: n, time: false, before: (i) => { if (i > 0) diag.push([c.diag.drop, c.diag.gripErr]); } });
  diag.push([c.diag.drop, c.diag.gripErr]);
  const pose = new Pose(c.rig), poseL = new Pose(c.rig);
  const mainS = cl.mainHand || 'R', mainE = mainS === 'R' ? 0 : 1, wb = 'weapon' + mainS;
  const out = { clip: name, frames: n, swivel: { R: [0, 0], L: [0, 0] }, flips: 0, aim: [0, 0], rot: [0, 0], fist: [0, 0], clav: { R: [0, 0], L: [0, 0] },
    twist: [0, 0], swing: [0, 0], helper: [0, 0], grip: [0, 0], drop: [0, 0], head: [0, 0], tip: [0, 0], float: [0, 0], footOff: [0, 0], clampFrames: 0, bigFrames: 0, rotFrames: 0, flipList: [] };
  const upd = (key, v, f) => { if (v > out[key][0]) out[key] = [v, r(rec.t[f], 3)]; };
  const prevH = {}, prevHead = new Float64Array(4);
  for (let f = 0; f < n; f++) {
    // weapon hand vs its key
    const req = requested(c, rec, f, cl, pose, mainE);
    // elbows
    if (f > 0) for (const S of ['R', 'L']) {
      const s = swivelStep(rec, f, S);
      if (s > out.swivel[S][0]) out.swivel[S] = [r(s, 1), r(rec.t[f], 3)];
      if (s > 30) {
        out.flips++;
        if (out.flipList.length < 6) {
          // wrist demand of the key at this frame: requested hand rotation relative to the solved forearm
          let dem = null;
          if (S === mainS && req && req.q) {
            const ri = c.rig.index[wb] * 4, rest = [-c.rig.restRot[ri], -c.rig.restRot[ri + 1], -c.rig.restRot[ri + 2], c.rig.restRot[ri + 3]];
            const hreq = qmulA(req.q, rest), fq = Array.from(boneQ(rec, f, 'foreArm' + S));
            const loc = qmulA([-fq[0], -fq[1], -fq[2], fq[3]], hreq);
            let w = loc[3], y = loc[1]; if (w < 0) { w = -w; y = -y; }
            dem = { twist: r(2 * Math.atan2(y, w) * R2D), swing: r(Math.acos(Math.max(-1, Math.min(1, 1 - 2 * (loc[0] * loc[0] + loc[2] * loc[2])))) * R2D) };
          }
          out.flipList.push({ t: r(rec.t[f], 3), side: S, deg: r(s), grip: S !== mainS && pose.grip > 0 ? 1 : 0, keyWristDemand: dem });
        }
      }
    }
    if (req) {
      const fist = mpos(rec, f, wb);
      upd('fist', len(sub(fist, req.pos)) * 1000, f);
      if (req.q) {
        out.rotFrames++;
        // the IK effector is the hand: the keyed weapon frame = hand * weapon rest (grip angle); an FK key on the
        // weapon bone (VORN's spear tilt) is deliberately on top of it, so compare hand * rest with the key
        const ri = c.rig.index[wb] * 4, rest = [c.rig.restRot[ri], c.rig.restRot[ri + 1], c.rig.restRot[ri + 2], c.rig.restRot[ri + 3]];
        const wq = qmulA(Array.from(boneQ(rec, f, 'hand' + mainS)), rest);
        const ax = qrotv(wq, [1, 0, 0]), bx = qrotv(req.q, [1, 0, 0]);
        const da = vang(ax, bx), dr = qang(wq, req.q);
        upd('aim', da, f); upd('rot', dr, f);
        if (dr > 10) out.clampFrames++;
        if (dr > 30) out.bigFrames++;
      }
    }
    // planted feet (IK weight 1, root / origin space, target on the floor): sole float above the floor, slide off target
    for (const [e, S] of [[2, 'R'], [3, 'L']]) {
      const o = e * 24, ik = pose.ik;
      if (!(ik[o] > 0.999) || ik[o + 14] >= 2 || ik[o + 2] > 0.005 * rec.scale) continue;
      const P = c.rig.P, sole = mpos(rec, f, 'foot' + S, 0, -P.ankleHeight, 0);
      // lowest contact point (heel, under the ankle, ball pad, toe tip): > 0 = the whole foot is in the air
      const low = Math.min(sole[1], mpos(rec, f, 'foot' + S, -P.heelLength, -P.ankleHeight, 0)[1], mpos(rec, f, 'foot' + S, P.footLength, -P.ankleHeight, 0)[1],
        mpos(rec, f, 'toe' + S, P.toeLength, -(P.ankleHeight - P.footDrop), 0)[1]);
      upd('float', low * 1000, f);
      upd('footOff', Math.hypot(sole[0] - ik[o + 1], sole[2] - ik[o + 3]) * 1000, f);
    }
    // clavicle: shoulder local rotation beyond the clip's own FK value
    sampleClip(c.rig, cl, rec.clipT[f], poseL, c.design.clipScale ?? 1);
    for (const S of ['R', 'L']) {
      const i = rec.idx['shoulder' + S], ri = c.rig.index['shoulder' + S];
      const a = [rec.Q[(f * rec.B + i) * 4], rec.Q[(f * rec.B + i) * 4 + 1], rec.Q[(f * rec.B + i) * 4 + 2], rec.Q[(f * rec.B + i) * 4 + 3]];
      const b = [poseL.lq[ri * 4], poseL.lq[ri * 4 + 1], poseL.lq[ri * 4 + 2], poseL.lq[ri * 4 + 3]];
      const d = qang(a, b);
      if (d > out.clav[S][0]) out.clav[S] = [r(d, 1), r(rec.t[f], 3)];
    }
    // wrists (hand local carries the forearm pronation after the helpers)
    for (const S of ['R', 'L']) {
      const i = rec.idx['hand' + S], o = (f * rec.B + i) * 4, Q = rec.Q;
      let w = Q[o + 3], y = Q[o + 1]; if (w < 0) { w = -w; y = -y; }
      upd('twist', Math.abs(2 * Math.atan2(y, w)) * R2D, f);
      upd('swing', Math.acos(Math.max(-1, Math.min(1, 1 - 2 * (Q[o] * Q[o] + Q[o + 2] * Q[o + 2])))) * R2D, f);
      const hi = rec.idx['foreArmTwist' + S], ho = (f * rec.B + hi) * 4;
      const hq = [Q[ho], Q[ho + 1], Q[ho + 2], Q[ho + 3]];
      if (prevH[S]) upd('helper', qang(prevH[S], hq), f);
      prevH[S] = hq;
    }
    if (pose.grip >= 0.999) upd('grip', diag[f][1] * 1000, f); // full two-handed grip only (a release is not an error)
    upd('drop', diag[f][0] * 1000, f);
    const hq = boneQ(rec, f, 'head');
    if (f > 0) upd('head', qang(Array.from(prevHead), Array.from(hq)), f);
    prevHead.set(hq);
    if (f > 0) upd('tip', len(sub([rec.tip[f * 3], rec.tip[f * 3 + 1], rec.tip[f * 3 + 2]], [rec.tip[f * 3 - 3], rec.tip[f * 3 - 2], rec.tip[f * 3 - 1]])) * 1000, f);
  }
  for (const k of ['aim', 'rot', 'fist', 'twist', 'swing', 'helper', 'grip', 'drop', 'head', 'tip', 'float', 'footOff']) out[k] = [r(out[k][0], 1), out[k][1]];
  out.nan = rec.nan;
  return out;
}

function summarize(rows) {
  const top = (k, sel, n = 6) => rows.map((x) => ({ clip: x.clip, v: sel(x) })).sort((a, b) => b.v[0] - a.v[0]).slice(0, n).map((x) => `${x.clip} ${x.v[0]}@${x.v[1]}`);
  const cnt = (pred) => rows.filter(pred).length;
  return {
    clips: rows.length,
    elbowSwivelOver30degPerFrame: cnt((x) => Math.max(x.swivel.R[0], x.swivel.L[0]) > 30),
    topSwivel: top('swivel', (x) => (x.swivel.R[0] >= x.swivel.L[0] ? [x.swivel.R[0], 'R ' + x.swivel.R[1]] : [x.swivel.L[0], 'L ' + x.swivel.L[1]])),
    weaponRotOff10deg: cnt((x) => x.rot[0] > 10), topRot: top('rot', (x) => x.rot), topAim: top('aim', (x) => x.aim),
    framesRotOff10: rows.reduce((s, x) => s + x.clampFrames, 0), framesRotOff30: rows.reduce((s, x) => s + x.bigFrames, 0), framesWithRotKey: rows.reduce((s, x) => s + x.rotFrames, 0),
    flipFrames: rows.reduce((s, x) => s + x.flips, 0), totalFrames: rows.reduce((s, x) => s + x.frames, 0),
    flipSamples: rows.flatMap((x) => x.flipList.map((fl) => ({ clip: x.clip, ...fl }))).sort((a, b) => b.deg - a.deg).slice(0, 12),
    fistOff20mm: cnt((x) => x.fist[0] > 20), topFist: top('fist', (x) => x.fist),
    clavOver24: cnt((x) => Math.max(x.clav.R[0], x.clav.L[0]) > 24), topClav: top('clav', (x) => (x.clav.R[0] >= x.clav.L[0] ? [x.clav.R[0], 'R ' + x.clav.R[1]] : [x.clav.L[0], 'L ' + x.clav.L[1]])),
    gripOver10mm: cnt((x) => x.grip[0] > 10), topGrip: top('grip', (x) => x.grip),
    dropOver50mm: cnt((x) => x.drop[0] > 50), topDrop: top('drop', (x) => x.drop),
    twistOver92: cnt((x) => x.twist[0] > 92), swingOver87: cnt((x) => x.swing[0] > 87),
    helperOver20: cnt((x) => x.helper[0] > 20), topHelper: top('helper', (x) => x.helper),
    topHead: top('head', (x) => x.head), topTip: top('tip', (x) => x.tip, 4),
    plantedFloatOver10mm: cnt((x) => x.float[0] > 10), topFloat: top('float', (x) => x.float), topFootOff: top('footOff', (x) => x.footOff, 4),
    nan: rows.filter((x) => x.nan).map((x) => x.clip),
  };
}

function realClips(fighter = 'kael', filter = null, opts = {}) {
  const c = mk(fighter, opts.over || {});
  const names = listClips().filter((n) => n.startsWith(fighter + '.') && (!filter || new RegExp(filter).test(n)));
  const rows = [];
  for (const n of names) {
    try { rows.push(measureClip(c, n, opts)); } catch (e) { rows.push({ clip: n, error: String(e.message || e) }); }
  }
  const ok = rows.filter((x) => !x.error);
  return { fighter, gripAngle: c.rig.gripAngle, summary: summarize(ok), errors: rows.filter((x) => x.error), rows: opts.rows ? ok : undefined };
}

function demoClips(gripAngle = null, rows = false) {
  const c = mk('knight', gripAngle === null ? {} : { gripAngle });
  const res = DEMO.map((n) => measureClip(c, n));
  return { gripAngle: c.rig.gripAngle, summary: summarize(res), rows: rows ? res : undefined };
}

// ---- human-feasible FK arm paths replayed by hand IK ----------------------------------------------------------------
/**
 * n random smooth right-arm FK trajectories inside the human range (shoulder flex -10..130, abduction -70..10,
 * humeral rotation +-30, elbow 20..120, wrist flex +-25 / pronation +-50 / deviation +-15) are recorded (fist position
 * + weapon frame) and fed back as hand IK keys every frame. Every target is reachable with a human wrist by
 * construction, so an elbow flip or a blade that leaves its key is a solver defect.
 */
function feasible(n = 24, seed = 5, body = 'knight', dur = 2) {
  const c = mk(body);
  const rng = makeRng(seed);
  const res = { trajectories: n, frames: 0, flips: 0, flipTraj: 0, maxSwivelStep: 0, maxElbowStepIK: 0, maxElbowStepFK: 0, maxRotErr: 0, maxAimErr: 0, maxFistErr: 0, rotErrOver5: 0, worst: [] };
  const sin = (amp, mid) => { const f = 0.15 + 0.5 * rng(), ph = rng() * 6.283, f2 = 0.3 + 0.6 * rng(), ph2 = rng() * 6.283; return (t) => mid + amp * (0.75 * Math.sin(6.283 * f * t + ph) + 0.25 * Math.sin(6.283 * f2 * t + ph2)); };
  for (let k = 0; k < n; k++) {
    const fx = sin(40, -30), fy = sin(30, 0), fz = sin(70, 60), el = sin(50, 70), hx = sin(25, 0), hy = sin(50, 0), hz = sin(15, 0);
    const keys = [];
    for (let i = 0; i <= dur * 10; i++) {
      const t = i / 10;
      keys.push({ t, bones: { upperArmR: [fx(t), fy(t), fz(t)], foreArmR: [0, 0, el(t)], handR: [hx(t), hy(t), hz(t)] } });
    }
    defineClip('r2b.fk', { duration: dur, keys: [{ t: 0, pose: 'neutral', grip: 0 }, ...keys] });
    invalidateClips();
    qa.resetForQA(c, 'r2b.fk', { breath: 0 });
    const nf = Math.round(dur * 60);
    const recF = qa.record(c, { hz: 60, frames: nf, time: false });
    const ikKeys = [];
    for (let f = 0; f < nf; f++) {
      const p = mpos(recF, f, 'weaponR'), q = Array.from(boneQ(recF, f, 'weaponR'));
      ikKeys.push({ t: recF.clipT[f], interp: 'linear', ik: { handR: { pos: p, aim: qrotv(q, [1, 0, 0]), up: qrotv(q, [0, 1, 0]) } } });
    }
    defineClip('r2b.ik', { duration: dur, keys: [{ t: 0, pose: 'neutral', grip: 0 }, ...ikKeys] });
    invalidateClips();
    qa.resetForQA(c, 'r2b.ik', { breath: 0 });
    const recI = qa.record(c, { hz: 60, frames: nf, time: false });
    let flips = 0, worst = null;
    for (let f = 1; f < nf; f++) {
      const sI = swivelStep(recI, f, 'R');
      const eI = len(sub(mpos(recI, f, 'foreArmR'), mpos(recI, f - 1, 'foreArmR'))) * 1000;
      const eF = len(sub(mpos(recF, f, 'foreArmR'), mpos(recF, f - 1, 'foreArmR'))) * 1000;
      res.maxSwivelStep = Math.max(res.maxSwivelStep, sI);
      res.maxElbowStepIK = Math.max(res.maxElbowStepIK, eI); res.maxElbowStepFK = Math.max(res.maxElbowStepFK, eF);
      if (sI > 30 && eI > 40) { flips++; if (!worst || sI > worst.swivelDeg) worst = { traj: k, t: r(recI.t[f], 3), swivelDeg: r(sI), elbowStepMM: r(eI), fkElbowStepMM: r(eF) }; }
      // the weapon frame vs the FK truth (time-aligned: IK key at the FK frame's clip time)
      const qI = Array.from(boneQ(recI, f, 'weaponR')), qF = Array.from(boneQ(recF, f, 'weaponR'));
      const de = qang(qI, qF), da = vang(qrotv(qI, [1, 0, 0]), qrotv(qF, [1, 0, 0]));
      const fe = len(sub(mpos(recI, f, 'weaponR'), mpos(recF, f, 'weaponR'))) * 1000;
      if (de > 5) res.rotErrOver5++;
      res.maxRotErr = Math.max(res.maxRotErr, de); res.maxAimErr = Math.max(res.maxAimErr, da); res.maxFistErr = Math.max(res.maxFistErr, fe);
    }
    res.frames += nf - 1; res.flips += flips; if (flips) { res.flipTraj++; res.worst.push(worst); }
  }
  for (const k of ['maxSwivelStep', 'maxElbowStepIK', 'maxElbowStepFK', 'maxRotErr', 'maxAimErr', 'maxFistErr']) res[k] = r(res[k], 1);
  res.worst = res.worst.sort((a, b) => b.swivelDeg - a.swivelDeg).slice(0, 8);
  return res;
}

// ---- look-at during spins ---------------------------------------------------------------------------------------
function lookSpin(clips = ['demo.combo3', 'kael.sweep', 'iska.glacier_pirouette', 'iska.star_fan', 'vorn.haft_spin']) {
  const out = {};
  for (const name of clips) {
    const fighter = name.split('.')[0], id = fighter === 'demo' ? 'knight' : fighter;
    let c;
    try { c = mk(id); getClip(c.rig, name); } catch (e) { out[name] = 'n/a: ' + e.message; continue; }
    const target = new THREE.Vector3(2.6, 1.75, 0); // opponent's head on the fight line
    const a = measureClip(c, name, { look: null }), b = measureClip(c, name, { look: target });
    out[name] = { headStepNoLook: a.head, headStepWithLook: b.head };
  }
  // a target circling the fighter at 2 deg/frame, standing idle: head response around the back
  const c = mk('knight');
  qa.resetForQA(c, 'demo.idle', { breath: 0 });
  const tg = new THREE.Vector3();
  let prev = null, maxStep = 0, at = 0;
  const yaws = [];
  for (let i = 0; i <= 180; i++) {
    const a = (i * 2 * Math.PI) / 180;
    tg.set(Math.cos(a) * 2.5, 1.75, Math.sin(a) * 2.5);
    c.lookAt(tg, 1);
    c.update(1 / 60, 1 / 60);
    const q = c.bones.head.getWorldQuaternion(new THREE.Quaternion());
    const fwd = new THREE.Vector3(1, 0, 0).applyQuaternion(q);
    yaws.push(r(Math.atan2(-fwd.z, fwd.x) * R2D, 0));
    if (prev) { const d = 2 * Math.acos(Math.min(1, Math.abs(prev.dot(q)))) * R2D; if (d > maxStep) { maxStep = d; at = i * 2; } }
    prev = q.clone();
  }
  c.lookAt(null);
  out.circlingTarget = { maxHeadStepDegPerFrame: r(maxStep), atTargetAngleDeg: at, targetStepDeg: 2, headYawEvery20deg: yaws.filter((_, i) => i % 10 === 0) };
  return out;
}

// ---- masked layers ------------------------------------------------------------------------------------------------
function layerIK() {
  const c = mk('knight');
  const out = {};
  // a) combo1 on the upper body over a walk: weapon hand vs combo1's own root-space hand target
  qa.resetForQA(c, 'demo.walkF', { breath: 0 });
  c.layer('atk', 'demo.combo1', { mask: 'upper', fade: 0 });
  const cl = getClip(c.rig, 'demo.combo1'), pose = new Pose(c.rig);
  let worst = 0, wt = 0, tipW = 0;
  const ref = [];
  { // combo1 alone (reference tip, root-relative)
    const c2 = mk('knight', { tag: 1 });
    qa.resetForQA(c2, 'demo.combo1', { breath: 0 });
    for (let i = 0; i < 50; i++) { c2.update(1 / 60, 1 / 60); ref.push(c2.sockets.weaponTip.getWorldPosition(new THREE.Vector3()).sub(c2.root.position)); }
  }
  for (let i = 0; i < 50; i++) {
    c.update(1 / 60, 1 / 60);
    sampleClip(c.rig, cl, (i + 1) / 60, pose);
    const want = new THREE.Vector3(pose.ik[1], pose.ik[2], pose.ik[3]);
    const got = c.sockets.handR.getWorldPosition(new THREE.Vector3()).sub(c.root.position);
    const e = got.distanceTo(want);
    if (e > worst) { worst = e; wt = (i + 1) / 60; }
    tipW = Math.max(tipW, c.sockets.weaponTip.getWorldPosition(new THREE.Vector3()).sub(c.root.position).distanceTo(ref[i]));
  }
  c.stopLayer('atk', 0); c.update(0, 0);
  out.upperAttackOverWalk = { fistVsCombo1TargetMaxMM: r(worst * 1000), at: r(wt, 3), tipVsCombo1AloneMaxMM: r(tipW * 1000) };
  // b) layer fade-in (linear ramp) vs a crossfade (smoothstep) of the same pose change: joint velocity step at the start
  const run = (useLayer) => {
    qa.resetForQA(c, 'demo.idle', { breath: 0 });
    for (let i = 0; i < 10; i++) c.update(1 / 60, 1 / 60);
    const rec = qa.record(c, { hz: 60, frames: 40, time: false, before: (i) => { if (i === 5) { if (useLayer) c.layer('blk', 'demo.guard', { mask: 'upper', fade: 0.2 }); else c.play('demo.guard', { fade: 0.2 }); } } });
    const ang = qa.angular(rec, { bones: ['upperArmR', 'foreArmR', 'chest', 'upperArmL', 'foreArmL'] });
    let maxStep = 0, who = null;
    for (const [b, x] of Object.entries(ang.bones)) {
      // velocity step at the fade start frame (deg/s per frame) from the recorded local rotations
      for (let f = 4; f <= 8; f++) {
        const k = rec.idx[b];
        const w0 = qa.qangle(rec.Q, ((f - 1) * rec.B + k) * 4, rec.Q, (f * rec.B + k) * 4) * R2D * 60;
        const wm = f > 1 ? qa.qangle(rec.Q, ((f - 2) * rec.B + k) * 4, rec.Q, ((f - 1) * rec.B + k) * 4) * R2D * 60 : 0;
        if (Math.abs(w0 - wm) > maxStep) { maxStep = Math.abs(w0 - wm); who = b + '@' + f; }
      }
    }
    if (useLayer) { c.stopLayer('blk', 0); c.update(0, 0); }
    return { velocityStepDegPerSec: r(maxStep), bone: who };
  };
  out.fadeInVelocityStep = { layerLinear: run(true), crossfadeSmoothstep: run(false) };
  return out;
}

// ---- floor contact vs authored knee pole -------------------------------------------------------------------------
function floorPole() {
  const c = mk('knight');
  const out = [];
  // right foot planted out to the side with the knee pole pointing out toward the camera; the foot pitches toes-down
  // (sweep) so the ball pad dips under the floor and floorFoot re-solves the leg
  // the foot comes down from 4 cm onto the floor (t 0 -> 1, slightly toes-down: -4 deg), stays (1 -> 2), then the
  // pitch goes through 0 to +4 (toes up, 2 -> 3)
  const pole = [0.25, 0.45, 1.2], fl = { pos: [0.1, 0, -0.14], rot: [0, 10, 0] };
  const keys = [
    { t: 0, ik: { footR: { pos: [0.08, 0.04, 0.3], rot: [0, -30, -4], pole }, footL: fl } },
    { t: 1, interp: 'linear', ik: { footR: { pos: [0.08, 0.0, 0.3], rot: [0, -30, -4], pole }, footL: fl } },
    { t: 2, interp: 'linear', ik: { footR: { pos: [0.08, 0.0, 0.3], rot: [0, -30, -4], pole }, footL: fl } },
    { t: 3, interp: 'linear', ik: { footR: { pos: [0.08, 0.0, 0.3], rot: [0, -30, 4], pole }, footL: fl } },
  ];
  defineClip('r2b.fp', { duration: 3, keys: [{ t: 0, pose: 'neutral', grip: 0, hips: { pos: [0, -0.1, 0] } }, ...keys] });
  invalidateClips();
  qa.resetForQA(c, 'r2b.fp', { breath: 0 });
  const rec = qa.record(c, { hz: 60, frames: 181, time: false });
  let prev = null, maxStep = 0, at = 0;
  for (let f = 0; f < rec.n; f += 1) {
    const hip = mpos(rec, f, 'thighR'), knee = mpos(rec, f, 'shinR'), ank = mpos(rec, f, 'footR');
    const a = sub(ank, hip), la = len(a); const v = sub(knee, hip), k = dot(v, a) / (la * la);
    const p = [v[0] - a[0] * k, v[1] - a[1] * k, v[2] - a[2] * k];
    const kneeDir = r(Math.atan2(p[2], p[0]) * R2D, 1); // 90 = knee toward the camera (+s), 0 = forward
    const pd = [pole[0] - hip[0], pole[1] - hip[1], pole[2] - hip[2]], kp = dot(pd, a) / (la * la);
    const pp = [pd[0] - a[0] * kp, pd[1] - a[1] * kp, pd[2] - a[2] * kp];
    const sole = mpos(rec, f, 'footR', 0, -c.rig.P.ankleHeight, 0);
    if (prev) { const s = len(sub(knee, prev)) * 1000; if (s > maxStep) { maxStep = s; at = rec.t[f]; } }
    prev = knee;
    if (f % 10 === 0 || (f > 55 && f < 64) || (f > 175)) out.push({ t: r(rec.t[f], 3), kneeVsPoleDeg: r(vang(p, pp), 1), kneeDirDeg: kneeDir, soleYmm: r(sole[1] * 1000, 1) });
  }
  return { rows: out, maxKneeStepMM: r(maxStep), at: r(at, 3) };
}

// ---- clavicle assist applied several times in one frame ------------------------------------------------------------
function clavicle() {
  const c = mk('knight');
  const out = {};
  const sh = (S) => { const q = c.bones['shoulder' + S].quaternion; return r(2 * Math.acos(Math.min(1, Math.abs(q.w))) * R2D, 1); };
  for (const [label, k] of [['onehand', 0], ['twohand', 1]]) {
    const rows = [];
    for (const ratio of [0.8, 0.9, 1.0, 1.1, 1.2, 1.3]) {
      // right fist straight overhead (+ forward) at `ratio` x arm length from the right shoulder, blade up
      const L = c.rig.lengths.upperArm + c.rig.lengths.foreArm, s = [-0.015, 1.52, 0.22];
      const d = new THREE.Vector3(0.25, 1, 0.1).normalize().multiplyScalar(L * ratio + c.rig.P.hand);
      defineClip('r2b.cl', { duration: 1, loop: true, keys: [{ t: 0, pose: 'neutral', grip: k, curl: [1, 1], ik: { handR: { pos: [s[0] + d.x, s[1] + d.y, s[2] + d.z], aim: [0.2, 1, 0], up: [-1, 0.2, 0] } } }] });
      invalidateClips();
      qa.resetForQA(c, 'r2b.cl', { breath: 0 });
      c.update(1 / 60, 1 / 60);
      rows.push({ ratio, shoulderR: sh('R'), shoulderL: sh('L'), gripErrMM: r(c.diag.gripErr * 1000, 1) });
    }
    out[label] = rows;
  }
  out.note = 'README: clavicle assist up to ~24 deg; qa ROM shoulder elevation 35 deg';
  return out;
}

// ---- loop seam of quaternion tracks --------------------------------------------------------------------------------
/**
 * A looping weapon twirl (hand IK aim turning a full circle per loop, keys every 90 deg) and a looping FK chest turn
 * (0 / 120 / 240, closing at 360): angular speed of the weapon / chest at the loop seam vs mid-loop.
 */
function loopSeam() {
  const c = mk('knight');
  const out = {};
  // weapon twirl in the fist (FK on the weapon bone: pure sampling, no IK involved)
  const keys = [];
  for (let k = 0; k < 4; k++) keys.push({ t: k * 0.2, bones: { weaponR: [0, 0, k * 90] } });
  defineClip('r2b.twirl', { duration: 0.8, loop: true, keys: [{ t: 0, pose: 'neutral', grip: 0 }, ...keys] });
  defineClip('r2b.turn', { duration: 0.9, loop: true, keys: [{ t: 0, pose: 'neutral', grip: 0, bones: { chest: [0, 0, 0] } }, { t: 0.3, bones: { chest: [0, 120, 0] } }, { t: 0.6, bones: { chest: [0, 240, 0] } }] });
  invalidateClips();
  for (const [name, bone, want] of [['r2b.twirl', 'weaponR', 450], ['r2b.turn', 'chest', 400]]) {
    qa.resetForQA(c, name, { breath: 0 });
    const cl = getClip(c.rig, name), n = Math.round(cl.duration * 60) * 2 + 1;
    const rec = qa.record(c, { hz: 60, frames: n, time: false });
    const sp = [];
    for (let f = 1; f < n; f++) sp.push(r(qang(Array.from(boneQ(rec, f - 1, bone)), Array.from(boneQ(rec, f, bone))) * 60, 0));
    const per = Math.round(cl.duration * 60);
    out[name] = { wantDegPerSec: want, aroundSeam: sp.slice(per - 4, per + 4), midLoop: sp.slice(Math.round(per * 0.4), Math.round(per * 0.4) + 6), min: Math.min(...sp.slice(4)), max: Math.max(...sp.slice(4)) };
  }
  return out;
}

function cpu() {
  // full knight (two cloths): one clip vs four clips cross-fading (a play every 4 frames, fade 0.3 s); per-update
  // percentiles over 5 x 160 frames (p10 approximates the uncontended cost on a loaded machine)
  const c = createCharacter(CTX, knight, { parent: null, name: 'r2b_cpu' });
  const seq = ['demo.combo1', 'demo.combo2', 'demo.combo3', 'demo.slam'];
  const time = (each) => {
    qa.resetForQA(c, 'demo.combo3', { breath: 1 });
    c.play('demo.combo3', { fade: 0, restart: true, loop: true });
    for (let i = 0; i < 120; i++) { each(i); c.update(1 / 60, 1 / 60); }
    const ms = [];
    for (let rep = 0; rep < 5; rep++) for (let i = 0; i < 160; i++) { each(i); const t0 = performance.now(); c.update(1 / 60, 1 / 60); ms.push(performance.now() - t0); }
    ms.sort((a, b) => a - b);
    return { p10: r(ms[Math.floor(ms.length * 0.1)], 3), p50: r(ms[ms.length >> 1], 3), p90: r(ms[Math.floor(ms.length * 0.9)], 3) };
  };
  const out = { oneClip: time(() => {}), fourClips: time((i) => { if (i % 4 === 0) c.play(seq[(i / 4) % 4], { fade: 0.3, restart: true }); }) };
  c.dispose();
  return out;
}

const TESTS = { realClips, demoClips, feasible, lookSpin, layerIK, floorPole, clavicle, loopSeam, cpu, measure: (id, name, o) => measureClip(mk(id), name, o) };

createLab({
  view: { target: [0, 1.05, 0], dist: 5.0, yaw: 0, pitch: 4, fov: 40 },
  setup(ctx, lab) {
    CTX = ctx;
    const pm = new THREE.PMREMGenerator(ctx.renderer);
    ctx.scene.environment = pm.fromScene(new RoomEnvironment(), 0.04).texture;
    ctx.scene.environmentIntensity = 0.45;
    pm.dispose();
    lab.lights.key.intensity = 3.2;
    lab.skel = (c) => {
      const h = new THREE.SkeletonHelper(c.root);
      h.material.linewidth = 2; h.material.color = new THREE.Color(0x40ff60);
      ctx.scene.add(h); lab.helpers.push(h);
    };
    lab.helpers = [];
    const live = [];
    const st = { tick: null };
    lab.live = live; lab.st = st;
    lab.add = (id, over = {}) => {
      const base = id === 'knight' ? knight : REAL[id];
      const c = createCharacter(ctx, id === 'knight' ? { ...base, ...over } : base, { name: 'live_' + id + live.length });
      c.play('neutral.hold', { fade: 0 }); c.update(0, 0);
      live.push(c);
      return c;
    };
    lab.clear = () => { for (const c of live) c.dispose(); live.length = 0; st.tick = null; for (const h of lab.helpers) h.removeFromParent(); lab.helpers.length = 0; };
    ctx.onUpdate((dg, dr) => { if (st.tick) st.tick(dg); for (const c of live) c.update(dg, dr); }, ORDER.CHAR);
    window.__ED.audit = {
      run(name, ...args) { const t = TESTS[name]; if (!t) throw new Error('no test ' + name + ' (' + Object.keys(TESTS).join(', ') + ')'); return t(...args); },
      list: () => Object.keys(TESTS),
    };
  },
  scenarios: {
    clip(ctx, lab, id, name, view = null, look = false, skel = false) {
      lab.clear(); const c = lab.add(id);
      c.play(name, { fade: 0, restart: true }); c.teleport();
      if (look) c.lookAt(new THREE.Vector3(2.6, 1.75, 0), 0.85);
      if (skel) lab.skel(c);
      if (view) lab.view(view);
    },
    pose(ctx, lab, id, name, t, view = null, look = false) {
      lab.clear(); const c = lab.add(id);
      c.play(name, { fade: 0, restart: true }); c.teleport();
      if (look) c.lookAt(new THREE.Vector3(2.6, 1.75, 0), 0.85);
      // advance to t frame by frame (cloth / look smoothing as in play), then hold
      const n = Math.round(t * 60);
      for (let i = 0; i < n; i++) c.update(1 / 60, 1 / 60);
      c.setClipTime(t);
      lab.st.tick = () => c.setClipTime(t);
      if (view) lab.view(view);
    },
    layer(ctx, lab, view = null) {
      // left: demo.combo1 alone; right: demo.walkF with demo.combo1 as an upper-body override layer (same clip time)
      lab.clear();
      const a = lab.add('knight'), b = lab.add('knight');
      a.root.position.x = -1.1; b.root.position.x = 1.1;
      a.play('demo.combo1', { fade: 0, restart: true }); a.teleport();
      b.play('demo.walkF', { fade: 0, restart: true }); b.teleport();
      b.layer('atk', 'demo.combo1', { mask: 'upper', fade: 0 });
      lab.view(view || { target: [0, 1.1, 0], dist: 6.2, yaw: 0, pitch: 4 });
    },
    floorpole(ctx, lab, view = null) {
      floorPole();
      lab.clear(); const c = lab.add('knight');
      c.play('r2b.fp', { fade: 0, restart: true }); c.teleport();
      lab.skel(c);
      lab.view(view || { target: [0.05, 0.5, 0.2], dist: 2.4, yaw: 25, pitch: 15 });
    },
  },
});
