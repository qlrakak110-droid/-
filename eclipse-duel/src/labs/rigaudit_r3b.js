// Rig audit lab, round 3, lens R3B: math, IK, grip, runtime and naturalness metrics (re-audit). Read-only on
// src/char: every number is measured on the shipped runtime and on the real fighter clips.
//
//   node tools/shot.mjs rigaudit_r3b --eval "__ED.audit.run('cut', 'kael')"      JSON results (__ED.audit.list())
//   tests:
//     cut(fighter, pairs?, frozen = 6)   a cut (play fade 0) into a hit reaction during hit-stop (update(0) x frozen),
//                                        as src/game/actor.js does: weapon / elbow / hand twist vs the converged pose of
//                                        the same clip time, per frame, until it settles
//     lag(fighter, filter?, slow = 8)    history dependence: every clip at normal speed vs at 1/slow speed (same clip
//                                        times, the rig's rate-limited memories have slow x the time to settle)
//     rates(fighter, filter?)            30 / 60 / 120 Hz: elbow and weapon at common clip times
//     offGrip(fighter, filter?)          off hand on a two-handed grip: hand grip axis vs weapon axis, fist to grip point
//     pull(fighter, filter?)             weapon-hand fist vs its key: share caused by the two-handed reach-grip pull
//                                        (the same clip with grip 0), what char.diag shows on those frames
//     poleSing(body?)                    position-only hand key (keepLocal path, default elbow pole) swept through the
//                                        default pole direction: elbow swivel / hand orientation steps
//     posOnly(fighter)                   frames of real clips whose hand IK has a position but no orientation
//     aimDiag(fighter, filter?)          char.diag.aimErr vs the measured weapon deviation from the key
//     spinSpeed()                        uniformly keyed FK spins (90 / 120 / 150 deg key spacing): angular speed range
//     cpuIK(fighter)                     ms per update of a rig-only fighter (IK only, no cloth): 1 clip vs 4-state fades

import * as THREE from 'three';
import { createLab, ORDER } from '../core/lab.js';
import { createCharacter, defineClip, invalidateClips, listClips } from '../char/index.js';
import { getClip, getClipDef, sampleClip, Pose } from '../char/anim.js';
import { createRig } from '../char/skeleton.js';
import { qfromBasis } from '../char/rigmath.js';
import { GRIP, WRIST } from '../char/ik.js';
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
const REAL = { kael, iska, vorn, knight };
let CTX = null;
const cache = new Map();

/** A rig-only copy of a design: proportions, grip angle, weapons, colliders (no armour, cloth or springs). */
function rigOnly(d, over = {}) {
  const std = new Set(createRig(d.proportions || {}).names);
  const colliders = (d.colliders || []).filter((c) => std.has(c.a[0]) && std.has(c.b[0]));
  return {
    id: 'r3b_' + (d.id || 'x'), idle: 'neutral.hold', proportions: d.proportions || {}, gripAngle: d.gripAngle, edgeRoll: d.edgeRoll,
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
  const c = createCharacter(CTX, rigOnly(REAL[id], over), { parent: null, name: 'r3b_' + id });
  cache.set(key, c);
  return c;
}
const clipsOf = (id, filter) => listClips().filter((n) => n.startsWith((id === 'knight' ? 'demo' : id) + '.') && !n.includes('.r3b') && (!filter || new RegExp(filter).test(n)));

// ---- vector / quaternion helpers -----------------------------------------------------------------------------------
const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const len = (a) => Math.hypot(a[0], a[1], a[2]);
const qrotv = (q, v) => {
  const [x, y, z, w] = q, tx = 2 * (y * v[2] - z * v[1]), ty = 2 * (z * v[0] - x * v[2]), tz = 2 * (x * v[1] - y * v[0]);
  return [v[0] + w * tx + y * tz - z * ty, v[1] + w * ty + z * tx - x * tz, v[2] + w * tz + x * ty - y * tx];
};
const qmulA = (a, b) => [a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1], a[3] * b[1] + a[1] * b[3] + a[2] * b[0] - a[0] * b[2], a[3] * b[2] + a[2] * b[3] + a[0] * b[1] - a[1] * b[0], a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2]];
const qinv = (q) => [-q[0], -q[1], -q[2], q[3]];
const qang = (a, b) => 2 * Math.acos(Math.min(1, Math.abs(a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3]))) * R2D;
const vang = (a, b) => Math.acos(Math.max(-1, Math.min(1, dot(a, b) / ((len(a) * len(b)) || 1)))) * R2D;
const twistOf = (q) => { let w = q[3], y = q[1]; if (w < 0) { w = -w; y = -y; } return 2 * Math.atan2(y, w) * R2D; };
const swingOf = (q) => Math.acos(Math.max(-1, Math.min(1, 1 - 2 * (q[0] * q[0] + q[2] * q[2])))) * R2D;

// live-character probes (root at the origin, facing +1, unrotated: world = fighter frame + root)
const _v = new THREE.Vector3(), _q = new THREE.Quaternion(), _s = new THREE.Vector3();
function bpos(c, name, x = 0, y = 0, z = 0) {
  _v.set(x, y, z).applyMatrix4(c.bones[name].matrixWorld);
  return [_v.x - c.root.position.x, _v.y - c.root.position.y, _v.z - c.root.position.z];
}
function bquat(c, name) { c.bones[name].matrixWorld.decompose(_v, _q, _s); return [_q.x, _q.y, _q.z, _q.w]; }
function lquat(c, name) { const q = c.bones[name].quaternion; return [q.x, q.y, q.z, q.w]; }
/** Elbow swivel direction (unit, perpendicular to the shoulder-wrist line) of side S. */
function swivelDir(c, S) {
  const s = bpos(c, 'upperArm' + S), w = bpos(c, 'hand' + S), e = bpos(c, 'foreArm' + S);
  const a = sub(w, s), la = len(a) || 1; a[0] /= la; a[1] /= la; a[2] /= la;
  const v = sub(e, s), k = dot(v, a), p = [v[0] - a[0] * k, v[1] - a[1] * k, v[2] - a[2] * k], lp = len(p) || 1;
  return { p: [p[0] / lp, p[1] / lp, p[2] / lp], off: lp };
}
/** Snapshot of everything the arm solver decides (model space). */
function armState(c, main = 'R') {
  const off = main === 'R' ? 'L' : 'R';
  return {
    elbowR: bpos(c, 'foreArmR'), elbowL: bpos(c, 'foreArmL'), fistR: bpos(c, 'weaponR'), fistL: bpos(c, 'weaponL'),
    weaponR: bquat(c, 'weaponR'), weaponL: bquat(c, 'weaponL'), handR: lquat(c, 'handR'), handL: lquat(c, 'handL'),
    swR: swivelDir(c, 'R'), swL: swivelDir(c, 'L'), tip: c.sockets.weaponTip ? (() => { const p = c.sockets.weaponTip.getWorldPosition(new THREE.Vector3()); return [p.x - c.root.position.x, p.y - c.root.position.y, p.z - c.root.position.z]; })() : null,
    main, off,
  };
}
/** Differences between two arm snapshots: elbow mm, weapon deg, hand-local twist deg, tip mm (both arms, worst). */
function armDiff(a, b) {
  const el = Math.max(len(sub(a.elbowR, b.elbowR)), len(sub(a.elbowL, b.elbowL))) * 1000;
  const wp = Math.max(qang(a.weaponR, b.weaponR), qang(a.weaponL, b.weaponL));
  const tw = Math.max(Math.abs(twistOf(a.handR) - twistOf(b.handR)), Math.abs(twistOf(a.handL) - twistOf(b.handL)));
  const sw = Math.max(vang(a.swR.p, b.swR.p), vang(a.swL.p, b.swL.p));
  const fist = Math.max(len(sub(a.fistR, b.fistR)), len(sub(a.fistL, b.fistL))) * 1000;
  const tip = a.tip && b.tip ? len(sub(a.tip, b.tip)) * 1000 : 0;
  return { elbowMM: el, weaponDeg: wp, twistDeg: tw, swivelDeg: sw, fistMM: fist, tipMM: tip };
}
function reset(c, clip, startAt = 0) { qa.resetForQA(c, clip, { breath: 0, startAt }); }

// ---- 1. cut into a hit reaction during hit-stop -------------------------------------------------------------------
/** Converged pose of `clip` at time t: held for `n` frames at 60 Hz (the rig's memories settle). */
function converged(c, clip, t, n = 90) {
  reset(c, clip, t);
  for (let i = 0; i < n; i++) { c.setClipTime(t); c.update(1 / 60, 1 / 60); }
  return armState(c);
}
const HIT = { kael: ['kael.hitLight', 0.05, 'kael.hitHeavy', 0.06], iska: ['iska.hitLight', 0.05, 'iska.hitHeavy', 0.06], vorn: ['vorn.hitLight', 0.05, 'vorn.hitHeavy', 0.06], knight: ['demo.hit', 0.05, 'demo.hit', 0.1] };
function cut(id = 'kael', froms = null, frozen = 6, settle = 30) {
  const c = mk(id);
  const [hl, tl, hh, th] = HIT[id];
  const all = clipsOf(id).filter((n) => !/hit|defeat|victory|intro|ko|down|getup|ult\./i.test(n));
  froms = froms || all;
  const out = { fighter: id, frozenFrames: frozen, rows: [] };
  const refs = {};
  for (const [to, tt] of [[hl, tl], [hh, th]]) refs[to] = converged(c, to, tt);
  for (const from of froms) {
    const fc = getClip(c.rig, from);
    for (const tf of [0.3, 0.6]) {
      const ft = Math.min(fc.duration * tf, fc.duration);
      for (const [to, tt] of [[hl, tl], [hh, th]]) {
        reset(c, from, 0);
        const nf = Math.round(ft * 60);
        for (let i = 0; i < nf; i++) c.update(1 / 60, 1 / 60);
        c.play(to, { fade: 0, restart: true, startAt: tt });
        let worstFrozen = { elbowMM: 0, weaponDeg: 0, twistDeg: 0, swivelDeg: 0, fistMM: 0, tipMM: 0 };
        for (let i = 0; i < frozen; i++) {
          c.setClipTime(tt); c.update(0, 1 / 60);
          const d = armDiff(armState(c), refs[to]);
          for (const k of Object.keys(worstFrozen)) worstFrozen[k] = Math.max(worstFrozen[k], d[k]);
        }
        // after the hit-stop (clip time still held at the impact key: only the rig's memories move)
        let settleFrame = -1, after = null, maxStepEl = 0, maxStepWp = 0, prev = armState(c);
        for (let i = 0; i < settle; i++) {
          c.setClipTime(tt); c.update(1 / 60, 1 / 60);
          const s = armState(c), d = armDiff(s, refs[to]);
          if (i === 0) after = d;
          const st = armDiff(s, prev); maxStepEl = Math.max(maxStepEl, st.elbowMM); maxStepWp = Math.max(maxStepWp, st.weaponDeg);
          prev = s;
          if (settleFrame < 0 && d.weaponDeg < 2 && d.elbowMM < 5) settleFrame = i + 1;
        }
        const row = { from, at: r(ft, 3), to, frozen: Object.fromEntries(Object.entries(worstFrozen).map(([k, v]) => [k, r(v)])),
          firstMovingFrame: Object.fromEntries(Object.entries(after).map(([k, v]) => [k, r(v)])), settleFrames: settleFrame < 0 ? '>' + settle : settleFrame,
          stepAfterFreeze: { elbowMM: r(maxStepEl), weaponDeg: r(maxStepWp) } };
        out.rows.push(row);
      }
    }
  }
  const W = (k) => out.rows.reduce((a, x) => (x.frozen[k] > a.frozen[k] ? x : a), out.rows[0]);
  out.summary = {
    cuts: out.rows.length,
    frozenWeaponOver10deg: out.rows.filter((x) => x.frozen.weaponDeg > 10).length,
    frozenWeaponOver30deg: out.rows.filter((x) => x.frozen.weaponDeg > 30).length,
    frozenElbowOver50mm: out.rows.filter((x) => x.frozen.elbowMM > 50).length,
    worstWeapon: (({ from, at, to, frozen: f, settleFrames }) => ({ from, at, to, weaponDeg: f.weaponDeg, elbowMM: f.elbowMM, twistDeg: f.twistDeg, tipMM: f.tipMM, settleFrames }))(W('weaponDeg')),
    worstElbow: (({ from, at, to, frozen: f, settleFrames }) => ({ from, at, to, weaponDeg: f.weaponDeg, elbowMM: f.elbowMM, settleFrames }))(W('elbowMM')),
    notSettledIn10: out.rows.filter((x) => typeof x.settleFrames !== 'number' || x.settleFrames > 10).length,
  };
  out.rows = out.rows.sort((a, b) => b.frozen.weaponDeg - a.frozen.weaponDeg).slice(0, 10);
  return out;
}

/** The same cut at normal speed (no hit-stop): how many frames the elbow / weapon need to land on the new clip's pose. */
function cutLive(id = 'kael', from = null, to = null, tt = 0.05) {
  const c = mk(id);
  to = to || HIT[id][0];
  from = from || clipsOf(id).find((n) => /guard$|idle$/.test(n));
  const ref = converged(c, to, tt);
  const fresh = (() => { reset(c, to, tt); return armState(c); })();
  reset(c, from, 0);
  for (let i = 0; i < 20; i++) c.update(1 / 60, 1 / 60);
  c.play(to, { fade: 0, restart: true, startAt: tt });
  const rows = [];
  for (let i = 0; i < 20; i++) { c.setClipTime(tt); c.update(1 / 60, 1 / 60); const d = armDiff(armState(c), ref); rows.push({ f: i + 1, weaponDeg: r(d.weaponDeg), elbowMM: r(d.elbowMM), twistDeg: r(d.twistDeg), tipMM: r(d.tipMM) }); }
  return { from, to, tt, freshVsConverged: Object.fromEntries(Object.entries(armDiff(fresh, ref)).map(([k, v]) => [k, r(v)])), rows };
}

/** Per-frame trace of one hit-stop cut: weapon / elbow / twist / fist vs converged, pelvis drop, tip height. */
function cutTrace(id = 'kael', from = 'kael.eruption', ft = 0.6, to = 'kael.hitHeavy', tt = 0.06, frozen = 6, n = 24) {
  const c = mk(id);
  const ref = converged(c, to, tt), refDrop = c.diag.drop;
  reset(c, from, 0);
  for (let i = 0; i < Math.round(ft * 60); i++) c.update(1 / 60, 1 / 60);
  const before = armState(c), dropBefore = c.diag.drop;
  c.play(to, { fade: 0, restart: true, startAt: tt });
  const rows = [];
  for (let i = 0; i < n; i++) {
    c.setClipTime(tt); c.update(i < frozen ? 0 : 1 / 60, 1 / 60);
    const s = armState(c), d = armDiff(s, ref);
    rows.push({ f: i + 1, dt: i < frozen ? 0 : r(1 / 60, 4), weaponDeg: r(d.weaponDeg), elbowMM: r(d.elbowMM), twistDeg: r(d.twistDeg), swivelDeg: r(d.swivelDeg), fistMM: r(d.fistMM), tipMM: r(d.tipMM),
      dropMM: r(c.diag.drop * 1000), tipY: s.tip ? r(s.tip[1], 2) : null, tipZ: s.tip ? r(s.tip[2], 2) : null, twistR: r(twistOf(s.handR)), twistL: r(twistOf(s.handL)) });
  }
  return { from, ft, to, tt, frozen, refDropMM: r(refDrop * 1000), dropBeforeMM: r(dropBefore * 1000), refTwistR: r(twistOf(ref.handR)), refTwistL: r(twistOf(ref.handL)), beforeTwistR: r(twistOf(before.handR)), beforeTwistL: r(twistOf(before.handL)),
    refTip: ref.tip && ref.tip.map((x) => r(x, 2)), beforeVsRef: Object.fromEntries(Object.entries(armDiff(before, ref)).map(([k, v]) => [k, r(v)])), rows };
}

// ---- 2. history dependence (normal speed vs slow) ------------------------------------------------------------------
function lag(id = 'kael', filter = null, slow = 8) {
  const c = mk(id);
  const rows = [];
  for (const name of clipsOf(id, filter)) {
    const cl = getClip(c.rig, name);
    const n = Math.round(cl.duration * 60);
    reset(c, name, 0);
    const A = [];
    for (let i = 0; i < n; i++) { c.update(1 / 60, 1 / 60); A.push(armState(c)); }
    reset(c, name, 0);
    c.play(name, { fade: 0, restart: true, speed: 1 / slow });
    let worst = { elbowMM: 0, weaponDeg: 0, swivelDeg: 0, tipMM: 0, fistMM: 0, twistDeg: 0 }, at = {}, over10 = 0, over30 = 0;
    for (let j = 0; j < n * slow; j++) {
      c.update(1 / 60, 1 / 60);
      if ((j + 1) % slow) continue;
      const i = (j + 1) / slow - 1, d = armDiff(A[i], armState(c));
      if (d.weaponDeg > 10) over10++;
      if (d.weaponDeg > 30) over30++;
      for (const k of Object.keys(worst)) if (d[k] > worst[k]) { worst[k] = d[k]; at[k] = r((i + 1) / 60, 3); }
    }
    rows.push({ clip: name, frames: n, over10, over30, ...Object.fromEntries(Object.entries(worst).map(([k, v]) => [k, [r(v), at[k]]])) });
  }
  const top = (k, m = 6) => rows.slice().sort((a, b) => b[k][0] - a[k][0]).slice(0, m).map((x) => `${x.clip} ${x[k][0]}@${x[k][1]}`);
  return {
    fighter: id, slow, clips: rows.length, frames: rows.reduce((s, x) => s + x.frames, 0),
    weaponOver10deg: rows.reduce((s, x) => s + x.over10, 0), weaponOver30deg: rows.reduce((s, x) => s + x.over30, 0),
    clipsWeaponOver30: rows.filter((x) => x.weaponDeg[0] > 30).length, clipsElbowOver50mm: rows.filter((x) => x.elbowMM[0] > 50).length,
    topWeapon: top('weaponDeg'), topElbow: top('elbowMM'), topTip: top('tipMM'), topFist: top('fistMM', 4),
  };
}

// ---- 3. frame-rate dependence ---------------------------------------------------------------------------------------
function rates(id = 'kael', filter = null) {
  const c = mk(id);
  const rows = [];
  for (const name of clipsOf(id, filter)) {
    const cl = getClip(c.rig, name);
    const n30 = Math.round(cl.duration * 30);
    const run = (hz) => {
      reset(c, name, 0);
      const k = hz / 30, out = [];
      for (let i = 0; i < n30 * k; i++) { c.update(1 / hz, 1 / hz); if ((i + 1) % k === 0) out.push(armState(c)); }
      return out;
    };
    const a = run(30), b = run(60), d = run(120);
    let w = { e30: 0, w30: 0, e120: 0, w120: 0, t30: 0, t120: 0 }, at = {};
    for (let i = 0; i < n30; i++) {
      const x = armDiff(a[i], b[i]), y = armDiff(d[i], b[i]);
      const set = (k, v) => { if (v > w[k]) { w[k] = v; at[k] = r((i + 1) / 30, 3); } };
      set('e30', x.elbowMM); set('w30', x.weaponDeg); set('t30', x.tipMM); set('e120', y.elbowMM); set('w120', y.weaponDeg); set('t120', y.tipMM);
    }
    rows.push({ clip: name, ...Object.fromEntries(Object.entries(w).map(([k, v]) => [k, [r(v), at[k]]])) });
  }
  const top = (k, m = 5) => rows.slice().sort((a, b) => b[k][0] - a[k][0]).slice(0, m).map((x) => `${x.clip} ${x[k][0]}@${x[k][1]}`);
  return {
    fighter: id, clips: rows.length,
    clipsWeaponOver10deg30Hz: rows.filter((x) => x.w30[0] > 10).length, clipsWeaponOver10deg120Hz: rows.filter((x) => x.w120[0] > 10).length,
    clipsTipOver50mm30Hz: rows.filter((x) => x.t30[0] > 50).length,
    topWeapon30: top('w30'), topWeapon120: top('w120'), topElbow30: top('e30'), topElbow120: top('e120'), topTip30: top('t30'), topTip120: top('t120'),
  };
}

// ---- 4. off hand on a two-handed grip ----------------------------------------------------------------------------
function offGrip(id = 'kael', filter = null) {
  const c = mk(id);
  const rows = [];
  const g = c.weapon && c.weapon.grips;
  if (!g) return { fighter: id, note: 'no grips' };
  for (const name of clipsOf(id, filter)) {
    const cl = getClip(c.rig, name), pose = new Pose(c.rig);
    const n = Math.round(cl.duration * 60);
    reset(c, name, 0);
    const off = cl.gripHand || 'L', main = cl.mainHand || 'R';
    const gp = (g[cl.gripAt] || g.grip);
    if (!gp) continue;
    let worst = { axisDeg: [0, 0], distMM: [0, 0], twist: [0, 0], swing: [0, 0] }, frames = 0, axisOver10 = 0, axisOver25 = 0;
    for (let i = 0; i < n; i++) {
      c.update(1 / 60, 1 / 60);
      sampleClip(c.rig, cl, c.clipTime, pose, c.design.clipScale ?? 1);
      if (!(pose.grip >= 0.999)) continue;
      frames++;
      // grip point on the weapon (model) vs the off fist; weapon axis vs the off hand's grip axis (hand * weaponRest)
      const wq = bquat(c, 'weapon' + main), wp = bpos(c, 'weapon' + main);
      const gpos = qrotv(wq, Array.from(gp.pos)), gm = [wp[0] + gpos[0], wp[1] + gpos[1], wp[2] + gpos[2]];
      const fist = bpos(c, 'weapon' + off);
      // the off hand's grip axis = hand * its weapon rest (grip angle), not the weapon bone (clips may FK-key it)
      const ro = c.rig.index['weapon' + off] * 4, restOff = Array.from(c.rig.restRot.subarray(ro, ro + 4));
      const offAxis = qrotv(qmulA(bquat(c, 'hand' + off), restOff), [1, 0, 0]), wAxis = qrotv(wq, [1, 0, 0]);
      const ax = vang(offAxis, wAxis), dist = len(sub(fist, gm)) * 1000;
      const hl = lquat(c, 'hand' + off), tw = Math.abs(twistOf(hl)), sw = swingOf(hl);
      if (ax > 10) axisOver10++;
      if (ax > 25) axisOver25++;
      const t = r(c.clipTime, 3);
      if (ax > worst.axisDeg[0]) worst.axisDeg = [r(ax), t];
      if (dist > worst.distMM[0]) worst.distMM = [r(dist), t];
      if (tw > worst.twist[0]) worst.twist = [r(tw), t];
      if (sw > worst.swing[0]) worst.swing = [r(sw), t];
    }
    if (frames) rows.push({ clip: name, frames, axisOver10, axisOver25, ...worst });
  }
  const top = (k, m = 6) => rows.slice().sort((a, b) => b[k][0] - a[k][0]).slice(0, m).map((x) => `${x.clip} ${x[k][0]}@${x[k][1]}`);
  return {
    fighter: id, gripClips: rows.length, gripFrames: rows.reduce((s, x) => s + x.frames, 0),
    framesAxisOver10deg: rows.reduce((s, x) => s + x.axisOver10, 0), framesAxisOver25deg: rows.reduce((s, x) => s + x.axisOver25, 0),
    topAxis: top('axisDeg'), topDist: top('distMM'), topTwist: top('twist'), topSwing: top('swing'),
    perClip: rows.slice().sort((a, b) => b.axisOver25 - a.axisOver25).map((x) => `${x.clip} ${x.axisOver25}/${x.frames} max ${x.axisDeg[0]}@${x.axisDeg[1]}`),
  };
}

/** Off fist vs the grip point / handle axis at clip time t (held 30 frames), rig-only or the full design. */
function gripAt(id = 'vorn', clip = 'vorn.idle', t = 2.167, full = false) {
  const c = full ? (cache.get('full' + id) || (() => { const x = createCharacter(CTX, REAL[id], { parent: null, name: 'full_' + id }); cache.set('full' + id, x); return x; })()) : mk(id);
  reset(c, clip, 0);
  for (let i = 0; i < Math.round(t * 60); i++) c.update(1 / 60, 1 / 60);
  const cl = getClip(c.rig, clip), pose = new Pose(c.rig);
  sampleClip(c.rig, cl, c.clipTime, pose, c.design.clipScale ?? 1);
  const off = cl.gripHand || 'L', main = cl.mainHand || 'R', g = c.weapon.grips[cl.gripAt] || c.weapon.grips.grip;
  const wq = bquat(c, 'weapon' + main), wp = bpos(c, 'weapon' + main), gpos = qrotv(wq, Array.from(g.pos));
  const gm = [wp[0] + gpos[0], wp[1] + gpos[1], wp[2] + gpos[2]], fist = bpos(c, 'weapon' + off);
  const ro = c.rig.index['weapon' + off] * 4, restOff = Array.from(c.rig.restRot.subarray(ro, ro + 4));
  const offAxis = qrotv(qmulA(bquat(c, 'hand' + off), restOff), [1, 0, 0]), wAxis = qrotv(wq, [1, 0, 0]);
  return { full, clipTime: r(c.clipTime, 3), grip: r(pose.grip, 3), gripAt: cl.gripAt, gripPoint: gm.map((x) => r(x, 3)), fist: fist.map((x) => r(x, 3)), distMM: r(len(sub(fist, gm)) * 1000), axisDeg: r(vang(offAxis, wAxis)),
    handTwist: r(twistOf(lquat(c, 'hand' + off))), handSwing: r(swingOf(lquat(c, 'hand' + off))), diagGripErrMM: r(c.diag.gripErr * 1000, 2), root: [c.root.position.x, c.root.position.y].map((x) => r(x, 3)) };
}

/**
 * offGrip with solver constants changed for the run (diagnosis only, restored afterwards): rollFree = unbounded off-hand
 * roll (GRIP.ROLL_KNEE / ROLL_MAX), wristFree = no wrist clamp (WRIST twist / swing limits huge).
 */
function offGripExp(id = 'vorn', filter = null, rollFree = false, wristFree = false) {
  const g0 = { ...GRIP }, w0 = { ...WRIST };
  try {
    if (rollFree) { GRIP.ROLL_KNEE = 50; GRIP.ROLL_MAX = 60; }
    if (wristFree) { WRIST.twist = 6; WRIST.twistKnee = 5.9; WRIST.swing = 6; WRIST.swingKnee = 5.9; WRIST.swingBack = 7; }
    const o = offGrip(id, filter);
    return { rollFree, wristFree, framesAxisOver10deg: o.framesAxisOver10deg, framesAxisOver25deg: o.framesAxisOver25deg, gripFrames: o.gripFrames, topAxis: o.topAxis, topTwist: o.topTwist, perClip: o.perClip.slice(0, 6) };
  } finally { Object.assign(GRIP, g0); Object.assign(WRIST, w0); }
}

// ---- 5. weapon-hand fist vs its key: the reach-grip pull ------------------------------------------------------------
function requestedPos(c, cl, t, pose, e) {
  sampleClip(c.rig, cl, t, pose, c.design.clipScale ?? 1);
  const o = e * 24, ik = pose.ik;
  if (!(ik[o] > 0.999) || ik[o + 14] >= 2) return null;
  return [ik[o + 1], ik[o + 2], ik[o + 3]];
}
function noGrip(name) {
  const d = getClipDef(name), nn = name + '.r3bnogrip';
  defineClip(nn, { ...d, keys: d.keys.map((k) => ({ ...k, grip: 0 })) });
  return nn;
}
function pull(id = 'kael', filter = null) {
  const c = mk(id);
  const rows = [];
  for (const name of clipsOf(id, filter)) {
    if (name.endsWith('.r3bnogrip')) continue;
    const cl = getClip(c.rig, name), pose = new Pose(c.rig);
    const e = (cl.mainHand || 'R') === 'R' ? 0 : 1, S = e === 0 ? 'R' : 'L';
    const n = Math.round(cl.duration * 60);
    const run = (clip) => {
      reset(c, clip, 0);
      const out = [];
      for (let i = 0; i < n; i++) {
        c.update(1 / 60, 1 / 60);
        const want = requestedPos(c, cl, c.clipTime, pose, e);
        const sh = bpos(c, 'upperArm' + S);
        out.push(want ? { err: len(sub(bpos(c, 'weapon' + S), want)) * 1000, reach: len(sub(want, sh)), grip: pose.grip, diagReach: c.diag.reach[e], gripErr: c.diag.gripErr * 1000 } : null);
      }
      return out;
    };
    const A = run(name);
    let B = null;
    try { B = run(noGrip(name)); } catch (err) { B = null; }
    let w = { err: 0 }, wn = 0, pulled = 0, pulledFrames = 0, at = 0;
    const L = c.rig.lengths.upperArm + c.rig.lengths.foreArm + c.rig.P.hand;
    for (let i = 0; i < n; i++) {
      const a = A[i], b = B && B[i];
      if (!a) continue;
      if (a.err > w.err) { w = a; at = (i + 1) / 60; }
      if (b) {
        wn = Math.max(wn, b.err);
        const dp = a.err - b.err;
        if (dp > 20) pulledFrames++;
        pulled = Math.max(pulled, dp);
      }
    }
    rows.push({ clip: name, fistErrMM: r(w.err), at: r(at, 3), keyReachRatio: r(w.reach / L, 2), diagReach: r(w.diagReach, 2), diagGripErrMM: r(w.gripErr), fistErrNoGripMM: r(wn), pulledByGripMM: r(pulled), framesPulledOver20mm: pulledFrames });
  }
  invalidateClips();
  return {
    fighter: id, clips: rows.length,
    clipsFistOver20mm: rows.filter((x) => x.fistErrMM > 20).length, clipsPulledOver20mm: rows.filter((x) => x.pulledByGripMM > 20).length,
    framesPulledOver20mm: rows.reduce((s, x) => s + x.framesPulledOver20mm, 0),
    rows: rows.sort((a, b) => b.fistErrMM - a.fistErrMM).slice(0, 10),
  };
}

// ---- 6. position-only hand keys through the default elbow pole -----------------------------------------------------
function poleSing(id = 'knight') {
  const c = mk(id);
  const out = {};
  // shoulder R at about (-0.015, 1.52, 0.22) x body; default pole direction in the chest frame: (-0.35, -1, 0.75)
  const k = c.bodyScale, L = (c.rig.lengths.upperArm + c.rig.lengths.foreArm) * 0.85 + c.rig.P.hand;
  const s = bpos(c, 'upperArmR');
  reset(c, 'neutral.hold', 0); c.update(1 / 60, 1 / 60);
  const sh = bpos(c, 'upperArmR');
  const pd = new THREE.Vector3(-0.35, -1, 0.75).normalize();
  // a horizontal sweep of the fist target on a circle around the pole direction at 12 deg from it (a fist passing near
  // the pole line: back, down and out), then straight through it
  const keys = [];
  const a1 = new THREE.Vector3(0, 0, 1).cross(pd).normalize(), a2 = pd.clone().cross(a1).normalize();
  for (let i = 0; i <= 40; i++) {
    const t = i / 40, ang = -0.6 + 1.2 * t; // sweep across the pole direction (through it at t = 0.5)
    const d = pd.clone().multiplyScalar(Math.cos(ang)).add(a1.clone().multiplyScalar(Math.sin(ang)));
    keys.push({ t: t * 2, interp: 'linear', ik: { handR: { pos: [sh[0] + d.x * L, sh[1] + d.y * L, sh[2] + d.z * L] } } });
  }
  defineClip('r3b.polesing', { duration: 2, keys: [{ t: 0, pose: 'neutral', grip: 0 }, ...keys] });
  invalidateClips();
  reset(c, 'r3b.polesing', 0);
  let prev = null, maxW = 0, maxE = 0, maxSw = 0, atW = 0;
  for (let i = 0; i < 120; i++) {
    c.update(1 / 60, 1 / 60);
    const st = armState(c);
    if (prev) { const d = armDiff(st, prev); if (d.weaponDeg > maxW) { maxW = d.weaponDeg; atW = (i + 1) / 60; } maxE = Math.max(maxE, d.elbowMM); maxSw = Math.max(maxSw, d.swivelDeg); }
    prev = st;
  }
  out.sweepThroughPole = { maxWeaponStepDegPerFrame: r(maxW), at: r(atW, 3), maxElbowStepMM: r(maxE), maxSwivelStepDeg: r(maxSw), shoulder: sh.map((x) => r(x, 3)), unusedS: s.map((x) => r(x, 3)) };
  // the same targets with a blade orientation (wrist path: memory, no flip)
  const keys2 = keys.map((kk) => ({ ...kk, ik: { handR: { ...kk.ik.handR, aim: [0, -1, 0.2], up: [1, 0, 0] } } }));
  defineClip('r3b.polesing2', { duration: 2, keys: [{ t: 0, pose: 'neutral', grip: 0 }, ...keys2] });
  invalidateClips();
  reset(c, 'r3b.polesing2', 0);
  prev = null; maxW = 0; maxE = 0; maxSw = 0;
  for (let i = 0; i < 120; i++) {
    c.update(1 / 60, 1 / 60);
    const st = armState(c);
    if (prev) { const d = armDiff(st, prev); maxW = Math.max(maxW, d.weaponDeg); maxE = Math.max(maxE, d.elbowMM); maxSw = Math.max(maxSw, d.swivelDeg); }
    prev = st;
  }
  out.sameWithAimKeys = { maxWeaponStepDegPerFrame: r(maxW), maxElbowStepMM: r(maxE), maxSwivelStepDeg: r(maxSw) };
  return out;
}

function posOnly(id = 'kael') {
  const c = mk(id);
  let frames = 0, total = 0;
  const clips = [];
  for (const name of clipsOf(id)) {
    const cl = getClip(c.rig, name), pose = new Pose(c.rig);
    const n = Math.round(cl.duration * 60);
    let k = 0;
    for (let i = 0; i <= n; i++) {
      sampleClip(c.rig, cl, i / 60, pose, 1);
      for (const e of [0, 1]) { const o = e * 24; if (pose.ik[o] > 0 && !pose.ik[o + 8] && !pose.ik[o + 23]) { k++; break; } }
      total++;
    }
    if (k) clips.push(name + ' ' + k);
    frames += k;
  }
  return { fighter: id, framesWithPositionOnlyHand: frames, totalFrames: total, clips };
}

// ---- 7. diag.aimErr vs the measured deviation ------------------------------------------------------------------------
function aimDiag(id = 'kael', filter = null) {
  const c = mk(id);
  let worstGap = 0, gapAt = '', framesUnder = 0, keyed = 0, over30 = 0;
  for (const name of clipsOf(id, filter)) {
    const cl = getClip(c.rig, name), pose = new Pose(c.rig);
    const main = cl.mainHand || 'R', e = main === 'R' ? 0 : 1;
    const ri = c.rig.index['weapon' + main] * 4, rest = Array.from(c.rig.restRot.subarray(ri, ri + 4));
    const n = Math.round(cl.duration * 60);
    reset(c, name, 0);
    for (let i = 0; i < n; i++) {
      c.update(1 / 60, 1 / 60);
      sampleClip(c.rig, cl, c.clipTime, pose, c.design.clipScale ?? 1);
      const o = e * 24;
      if (!(pose.ik[o] > 0.999) || pose.ik[o + 14] >= 2 || !pose.ik[o + 8]) continue;
      keyed++;
      const key = [pose.ik[o + 4], pose.ik[o + 5], pose.ik[o + 6], pose.ik[o + 7]];
      const got = qmulA(bquat(c, 'hand' + main), rest);
      const meas = qang(got, key), diag = c.diag.aimErr[e];
      if (meas > 30) over30++;
      if (meas > 10 && diag < meas * 0.5) framesUnder++;
      if (meas - diag > worstGap) { worstGap = meas - diag; gapAt = `${name}@${r(c.clipTime, 3)} measured ${r(meas)} diag ${r(diag)}`; }
    }
  }
  return { fighter: id, keyedFrames: keyed, framesOver30deg: over30, framesDiagUnderHalfOfMeasured: framesUnder, worstUnderreport: gapAt };
}

// ---- 8. uniformly keyed spins through the quaternion spline ------------------------------------------------------
function spinSpeed() {
  const c = mk('knight');
  const out = {};
  for (const step of [60, 90, 120, 150, 170]) {
    const keys = [{ t: 0, pose: 'neutral', grip: 0, bones: { chest: [0, 0, 0] } }];
    for (let a = step; a < 360 - 1e-6; a += step) keys.push({ t: a / 400, bones: { chest: [0, a, 0] } });
    const dur = 360 / 400;
    defineClip('r3b.spin', { duration: dur, loop: true, keys });
    invalidateClips();
    reset(c, 'r3b.spin', 0);
    let prev = null;
    const sp = [];
    for (let i = 0; i < Math.round(dur * 120) * 2; i++) {
      c.update(1 / 120, 1 / 120);
      const q = lquat(c, 'chest');
      if (prev) sp.push(qang(prev, q) * 120);
      prev = q;
    }
    const s2 = sp.slice(4);
    out['keysEvery' + step + 'deg'] = { wantDegPerSec: 400, min: r(Math.min(...s2), 0), max: r(Math.max(...s2), 0), ratio: r(Math.min(...s2) / Math.max(...s2), 2) };
  }
  return out;
}

// ---- 9. CPU of the IK path ---------------------------------------------------------------------------------------------
function cpuIK(id = 'kael', full = false) {
  const c = full ? (cache.get('full' + id) || (() => { const x = createCharacter(CTX, REAL[id], { parent: null, name: 'full_' + id }); cache.set('full' + id, x); return x; })()) : mk(id);
  const names = clipsOf(id).filter((n) => /light|heavy|lunge|sweep|crescent|slash|thrust|combo/.test(n)).slice(0, 4);
  const time = (each) => {
    reset(c, names[0], 0);
    c.play(names[0], { fade: 0, restart: true, loop: true });
    for (let i = 0; i < 60; i++) { each(i); c.update(1 / 60, 1 / 60); }
    const runs = [];
    for (let rep = 0; rep < 6; rep++) { const ms = []; for (let i = 0; i < 120; i++) { each(i); const t0 = performance.now(); c.update(1 / 60, 1 / 60); ms.push(performance.now() - t0); } runs.push(ms); }
    const mins = runs[0].map((_, i) => Math.min(...runs.map((x) => x[i])));
    return { meanOfMinima: r(mins.reduce((a, b) => a + b, 0) / mins.length, 3), maxOfMinima: r(Math.max(...mins), 3) };
  };
  return { fighter: id, full, clips: names, oneClip: time(() => {}), fourStateFades: time((i) => { if (i % 4 === 0) c.play(names[(i / 4) % names.length], { fade: 0.3, restart: true }); }) };
}

const TESTS = { offGripExp, gripAt, cut, cutLive, cutTrace, lag, rates, offGrip, pull, poleSing, posOnly, aimDiag, spinSpeed, cpuIK };

createLab({
  view: { target: [0, 1.05, 0], dist: 4.2, yaw: 20, pitch: 6, fov: 40 },
  setup(ctx, lab) {
    CTX = ctx;
    lab.live = [];
    lab.st = { tick: null };
    lab.clear = () => { for (const c of lab.live) c.dispose(); lab.live.length = 0; lab.st.tick = null; };
    lab.add = (id) => { const c = createCharacter(ctx, REAL[id], { name: 'live_' + id }); c.play('neutral.hold', { fade: 0 }); c.update(0, 0); lab.live.push(c); return c; };
    ctx.onUpdate((dg, dr) => { if (lab.st.tick) lab.st.tick(dg, dr); else for (const c of lab.live) c.update(dg, dr); }, ORDER.CHAR);
    window.__ED.audit = {
      run(name, ...args) { const t = TESTS[name]; if (!t) throw new Error('no test ' + name + ' (' + Object.keys(TESTS).join(', ') + ')'); return t(...args); },
      list: () => Object.keys(TESTS),
    };
  },
  scenarios: {
    /** Full design `id` playing `clip` from 0 frame by frame up to `t`, then held at `t` (60 Hz). */
    hold(ctx, lab, id, clip, t, view = null) {
      lab.clear();
      const a = lab.add(id);
      a.play(clip, { fade: 0, restart: true }); a.teleport();
      for (let i = 0; i < Math.round(t * 60); i++) a.update(1 / 60, 1 / 60);
      lab.st.tick = (dg, dr) => { a.setClipTime(t); a.update(dg, dr); if (lab.axes) lab.axes(a); };
      if (view) lab.view(view);
    },
    /** hold + overlay: the weapon axis through the off fist (red), the off hand's grip axis (green), lit close-up. */
    gripaxes(ctx, lab, id, clip, t, view = null) {
      lab.scenarios.hold(ctx, lab, id, clip, t, view);
      const mkLine = (col) => { const l = new THREE.Mesh(new THREE.CylinderGeometry(0.004, 0.004, 0.5, 6), new THREE.MeshBasicMaterial({ color: col, depthTest: false, transparent: true, opacity: 0.9 })); l.renderOrder = 10; l.frustumCulled = false; ctx.scene.add(l); return l; };
      const red = lab.redLine || (lab.redLine = mkLine(0xff2020)), green = lab.greenLine || (lab.greenLine = mkLine(0x20ff40));
      const lamp = lab.lamp || (lab.lamp = new THREE.PointLight(0xffffff, 2.5, 4));
      ctx.scene.add(lamp);
      const v = new THREE.Vector3(), q = new THREE.Quaternion(), s = new THREE.Vector3(), q2 = new THREE.Quaternion();
      lab.axes = (c) => {
        const cl = getClip(c.rig, clip), off = cl.gripHand || 'L', main = cl.mainHand || 'R';
        const fist = new THREE.Vector3().setFromMatrixPosition(c.bones['weapon' + off].matrixWorld);
        c.bones['weapon' + main].matrixWorld.decompose(v, q, s);
        const wa = new THREE.Vector3(1, 0, 0).applyQuaternion(q);
        c.bones['hand' + off].matrixWorld.decompose(v, q2, s);
        const ro = c.rig.index['weapon' + off] * 4;
        q2.multiply(new THREE.Quaternion(c.rig.restRot[ro], c.rig.restRot[ro + 1], c.rig.restRot[ro + 2], c.rig.restRot[ro + 3]));
        const ha = new THREE.Vector3(1, 0, 0).applyQuaternion(q2);
        const set = (l, d) => { l.position.copy(fist); l.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), d.clone().normalize()); };
        set(red, wa); set(green, ha);
        lamp.position.set(fist.x + 0.3, fist.y + 0.5, fist.z + 1.2);
      };
      lab.axes(lab.live[0]);
    },
    /**
     * Hit-stop cut capture: left = the live sequence (clip `from` for `ft` s, then a cut into `to` at `tt` held by
     * hit-stop), right = the same clip time converged. Both full designs. Advance the harness by any time: the right one
     * is held, the left one is frozen for `frozen` frames and then released (clip time still held).
     */
    cut(ctx, lab, id, from, ft, to, tt, frozen = 6, view = null) {
      lab.clear();
      const a = lab.add(id), b = lab.add(id);
      a.root.position.x = -0.75; b.root.position.x = 0.75;
      a.play(from, { fade: 0, restart: true }); a.teleport();
      b.play(to, { fade: 0, restart: true, startAt: tt }); b.teleport();
      for (let i = 0; i < Math.round(ft * 60); i++) a.update(1 / 60, 1 / 60);
      for (let i = 0; i < 60; i++) { b.setClipTime(tt); b.update(1 / 60, 1 / 60); }
      a.play(to, { fade: 0, restart: true, startAt: tt });
      let f = 0;
      lab.st.tick = (dg, dr) => { a.setClipTime(tt); a.update(f < frozen ? 0 : dg, dr); b.setClipTime(tt); b.update(dg, dr); f++; };
      a.setClipTime(tt); a.update(0, 0); b.update(0, 0);
      lab.view(view || { target: [0, 1.15, 0], dist: 3.6, yaw: 12, pitch: 5 });
    },
  },
});
