// Rig audit lab, lens ANIM: animation runtime and motion-naturalness metrics (auditor's sandbox, read-only on
// src/char). Every number comes from src/char/qa.js sampling the shipped runtime at 120 Hz.
//
//   node tools/shot.mjs rigaudit_anim --eval "__ED.audit.clip('demo.combo1')"      JSON results
//   __ED.audit.list()                      demo clips
//   __ED.audit.clip(name, opts)            every qa metric for one clip (tip arcs, pops, ROM, balance, feet, floor,
//                                          self-intersection, loop seam, key continuity, cpu)
//   __ED.audit.summary()                   one line per demo clip (the headline numbers)
//   __ED.audit.keys(name)                  clip-data velocity steps at keys (ease / tangent C1 breaks)
//   __ED.audit.xfade({ at, fade })         crossfade matrix (every clip -> every other clip)
//   __ED.audit.runtime(name?)              runtime tests: scrub, stepping, events, speed, layers, flinch, cap, fuzz, cpu
//   __ED.audit.bodies(clip)                the same clip on KAEL / ISKA / VORN proportions (ROM + feet + floor)
//   __ED.audit.synthetic()                 sampler tests on hand-made clips (uniform spin, ease pairs, loop seam)
//   scenarios (captures): trace(clip, tHold, view) plot(clip, bones) xplot() balance(clip) layer() flinch()

import * as THREE from 'three';
import { createLab, ORDER } from '../core/lab.js';
import { makeRng } from '../core/math.js';
import { createCharacter, defineClip, invalidateClips } from '../char/index.js';
import { getClip, getClipDef } from '../char/anim.js';
import { knight } from '../char/designs/knight.js';
import '../char/clips/demo.js';
import * as qa from '../char/qa.js';

const DEMO = ['demo.idle', 'demo.guard', 'demo.walkF', 'demo.walkB', 'demo.combo1', 'demo.combo2', 'demo.combo3', 'demo.slam', 'demo.hit', 'demo.combo1M'];
const H = 1 / 120;
const r = (x, d = 3) => (Number.isFinite(x) ? Math.round(x * 10 ** d) / 10 ** d : x);

// proportion sets for the three fighters (heights 1.95 / 1.78 / 2.02 m)
const PROPS = {
  kael: {},
  iska: { hipHeight: 0.93, pelvisDrop: 0.055, hipWidth: 0.094, ankleHeight: 0.075, footLength: 0.12, footDrop: 0.048, toeLength: 0.07, heelLength: 0.058,
    spine: 0.10, chest: 0.152, neck: 0.235, head: 0.098, shoulderHeight: 0.185, clavicleRoot: 0.026, clavicle: 0.163, shoulderBack: 0.012, upperArm: 0.28, foreArm: 0.245, hand: 0.076, palm: 0.019 },
  vorn: { hipHeight: 1.05, pelvisDrop: 0.064, hipWidth: 0.104, ankleHeight: 0.09, footLength: 0.145, footDrop: 0.058, toeLength: 0.086, heelLength: 0.07,
    spine: 0.116, chest: 0.18, neck: 0.265, head: 0.11, shoulderHeight: 0.21, clavicleRoot: 0.032, clavicle: 0.2, shoulderBack: 0.016, upperArm: 0.325, foreArm: 0.29, hand: 0.09, palm: 0.023 },
};

let CTX = null, LAB = null;
const cache = new Map();
/** Measuring characters: 'lite' = knight without cloth (cloth never feeds back into bones; 3x faster), 'full' = as shipped. */
function mk(kind = 'lite', props = 'kael') {
  const key = kind + ':' + props;
  if (cache.has(key)) return cache.get(key);
  const d = { ...knight, proportions: PROPS[props], cloth: kind === 'full' ? knight.cloth : [] };
  const c = createCharacter(CTX, d, { parent: null, name: 'qa_' + key });
  cache.set(key, c);
  return c;
}
const fresh = (kind = 'lite') => createCharacter(CTX, { ...knight, cloth: kind === 'full' ? knight.cloth : [] }, { parent: null, name: 'qa_fresh' });

const LAYER_NAMES = ['atk', 'legs', 'flinch', 'kick', 'a', 'b', 'L0', 'L1', 'L2'];
/** Layers survive play() / teleport(): stop every layer name this lab uses, then reset. */
function reset(c, clip, o) { for (const n of LAYER_NAMES) c.stopLayer(n, 0); return qa.resetForQA(c, clip, o); }

let REST = null;
function rest() {
  if (REST) return REST;
  const c = mk();
  const rec = qa.recordClip(c, 'neutral.hold', { duration: 0, breath: 0 });
  REST = qa.restDepths(rec);
  return REST;
}

// ---- clip audits -----------------------------------------------------------------------------------------------------
function cleanAll() { for (const c of cache.values()) for (const n of LAYER_NAMES) c.stopLayer(n, 0); }
function clip(name, opts = {}) {
  cleanAll();
  const res = qa.auditClip(mk(), name, { rest: rest(), ...opts });
  delete res.rec; delete res.series;
  if (opts.brief) {
    res.keys = res.keys.slice(0, 12);
    res.limits = res.limits.slice(0, 12);
    res.angular.pops = res.angular.pops.slice(0, 12);
  }
  return res;
}

function summary() {
  cleanAll();
  return DEMO.map((name) => {
    const a = qa.auditClip(mk(), name, { rest: rest() });
    const sw = a.tip;
    const keySteps = a.keys.filter((k) => !k.seam);
    return {
      clip: name,
      swings: sw.map((s) => `${s.t0}-${s.t1} pk${s.peak} str${s.straight} kinks${s.kinks} jerkSp${s.jerkSpikes} edge${s.edge} flat${s.flat}`),
      pops: a.angular.pops.length, worstPop: a.angular.pops[0] ? `${a.angular.pops[0].bone}@${a.angular.pops[0].t} ${a.angular.pops[0].w0}->${a.angular.pops[0].w1}` : null,
      over: a.angular.over.map((o) => `${o.bone} ${o.maxW}>${o.limit}@${o.t}`),
      rom: a.limits.slice(0, 6).map((l) => `${l.joint}.${l.axis} ${l.value} (${l.range}) +${l.over}@${l.t} ${Math.round(l.frac * 100)}%`), romCount: a.limits.length,
      balance: `both ${a.balance.bothPlanted}s unsup ${a.balance.unsupported}s max ${a.balance.maxOutside}@${a.balance.maxOutsideT} xcom ${a.balance.xcomOutside}s single ${a.balance.single}s/${a.balance.singleOutside}s air ${a.balance.airborne}s`,
      feet: { maxDrift: a.feet.maxDrift, maxSlide: a.feet.maxSlide, worst: a.feet.worst, moonwalk: a.feet.plants.filter((p) => p.moonwalk !== null).map((p) => `${p.foot}${p.t0}-${p.t1}:${p.moonwalk}`) },
      floor: Object.fromEntries(Object.entries(a.floor).map(([g, v]) => [g, `${v.min}@${v.t} below ${v.below}s`])),
      ix: a.intersections.slice(0, 6).map((x) => `${x.pair} ${x.depth}@${x.t} ${x.time}s`),
      seam: a.seam.map((s) => `t${s.t} ang ${s.angStep}(${s.angBone}) x${s.angRatio} vel ${s.velStep}(${s.velJoint}) x${s.velRatio} root ${s.rootV}`),
      keySteps: keySteps.length, worstKey: keySteps.slice(0, 3).map((k) => `${k.ch}@${k.t} ${k.before}->${k.after}${k.unit}`),
      cpu: a.cpu, nan: a.nan, events: a.events.length,
    };
  });
}

// ---- crossfade matrix -------------------------------------------------------------------------------------------------
function xfade({ at = null, fade = 0.1, clips = DEMO } = {}) {
  cleanAll();
  const c = mk(), baselines = {}, rows = [];
  for (const a of clips) for (const b of clips) {
    if (a === b) continue;
    const ca = getClip(c.rig, a);
    const t = at === null ? Math.min(0.45 * ca.duration, 0.6) : at * ca.duration;
    rows.push(qa.crossfade(c, a, b, { at: t, fade, baselines }));
  }
  const pops = rows.filter((x) => x.pop).sort((x, y) => Math.max(y.angRatio, y.bodyRatio) - Math.max(x.angRatio, x.bodyRatio));
  return {
    pairs: rows.length, pops: pops.length, nan: rows.filter((x) => x.nan).length,
    worstAng: rows.slice().sort((x, y) => y.ang - x.ang).slice(0, 8).map((x) => `${x.from}->${x.to}: ${x.ang} deg/s/frame ${x.angBone} @+${x.angT} (clips max ${x.angRef}) x${x.angRatio}`),
    worstBody: rows.slice().sort((x, y) => y.body - x.body).slice(0, 8).map((x) => `${x.from}->${x.to}: ${x.body} m/s/frame ${x.bodyJoint} @+${x.bodyT} (clips max ${x.bodyRef}) x${x.bodyRatio}`),
    medianAngRatio: r(rows.map((x) => x.angRatio).sort((p, q) => p - q)[rows.length >> 1], 2),
    medianBodyRatio: r(rows.map((x) => x.bodyRatio).sort((p, q) => p - q)[rows.length >> 1], 2),
    rows,
  };
}

// ---- runtime tests ------------------------------------------------------------------------------------------------------
function runScript(c, frames) {
  // frames: array of [dt, fn?]
  for (const [dt, fn] of frames) { if (fn) fn(c); c.update(dt, dt); }
}

/** setClipTime scrubbing: forward, backward, shuffled, with dt 1/120, 1/30 and 0 -> identical poses at equal t. */
function testScrub() {
  const out = {};
  for (const name of ['demo.combo1', 'demo.combo3', 'demo.walkF', 'demo.slam']) {
    const c = mk();
    const d = getClip(c.rig, name).duration;
    const ts = []; for (let k = 0; k <= Math.round(d * 120); k++) ts.push(k / 120);
    reset(c, name, { breath: 0 });
    const ref = new Map();
    for (const t of ts) { c.setClipTime(t); c.update(H, H); ref.set(t, qa.poseOf(c)); }
    // self-advancing at 120 Hz must hit the same poses
    reset(c, name, { breath: 0 });
    let selfMax = { deg: 0, mm: 0 };
    for (let k = 1; k < ts.length; k++) { c.update(H, H); const dd = qa.poseDiff(ref.get(ts[k]), qa.poseOf(c)); if (dd.deg > selfMax.deg) selfMax = dd; }
    const rng = makeRng(7);
    const orders = { backward: ts.slice().reverse(), shuffled: ts.slice().sort(() => rng() - 0.5) };
    const res = { selfAdvanceVsScrub: selfMax };
    for (const [on, order] of Object.entries(orders)) {
      for (const dt of [H, 1 / 30, 0]) {
        reset(c, name, { breath: 0 });
        let worst = { deg: 0, mm: 0 };
        for (const t of order) { c.setClipTime(t); c.update(dt, dt); const dd = qa.poseDiff(ref.get(t), qa.poseOf(c)); if (dd.deg > worst.deg || dd.mm > worst.mm) worst = dd; }
        res[on + '@' + (dt ? Math.round(1 / dt) : 0)] = worst;
      }
    }
    out[name] = res;
  }
  return out;
}

/** 1/30 vs 1/60 vs 1/120 stepping of the same script (play, crossfades, speed change, optional flinch): pose at equal t. */
function testStepping({ impulse = false, breath = 1 } = {}) {
  const rates = [30, 60, 120], chars = rates.map(() => fresh());
  const snaps = rates.map(() => new Map());
  // every action happens at a frame boundary that all three rates share (multiples of 1/30 s)
  const script = (c, t0) => {
    const at = (x) => Math.abs(t0 - x) < 1e-6;
    if (at(0)) c.play('demo.combo1', { fade: 0.1, restart: true });
    if (at(0.5)) c.play('demo.combo2', { fade: 0.08, restart: true });
    if (impulse && at(0.6)) c.impulse({ dir: [-1, 0.1, 0.2], amount: 1.2 });
    if (at(1.2)) c.play('demo.walkF', { fade: 0.15, speed: 1.3 });
    if (at(1.9)) c.play('demo.idle', { fade: 0.2 });
  };
  rates.forEach((hz, k) => {
    const c = chars[k];
    reset(c, 'demo.idle', { breath });
    let t = 0;
    const n = Math.round(2.6 * hz);
    for (let i = 0; i < n; i++) {
      script(c, t);
      c.update(1 / hz, 1 / hz); t = (i + 1) / hz;
      if (Math.abs(t * 30 - Math.round(t * 30)) < 1e-6) snaps[k].set(Math.round(t * 30), qa.poseOf(c));
    }
  });
  const cmp = (a, b) => { let w = { deg: 0, mm: 0 }; for (const [k, p] of snaps[a]) { const q = snaps[b].get(k); if (!q) continue; const d = qa.poseDiff(p, q); if (d.deg > w.deg) w = { ...d, t: r(k / 30) }; } return w; };
  chars.forEach((c) => c.dispose());
  return { '30vs120': cmp(0, 2), '60vs120': cmp(1, 2) };
}

/** Event delivery: counts per schedule vs the expected count (each marker exactly once per pass). */
function testEvents() {
  const out = {};
  // synthetic clips with markers at 0, mid, end
  defineClip('qa.evLoop', { duration: 0.5, loop: true, keys: [{ t: 0, pose: 'neutral' }, { t: 0.25, bones: { chest: [0, 10, 0] } }], events: [{ t: 0, name: 'e0' }, { t: 0.25, name: 'eMid' }, { t: 0.5, name: 'eEnd' }, { t: 1 / 60, name: 'e1f' }] });
  defineClip('qa.evOnce', { duration: 0.5, keys: [{ t: 0, pose: 'neutral' }, { t: 0.5, bones: { chest: [0, 10, 0] } }], events: [{ t: 0, name: 'e0' }, { t: 0.25, name: 'eMid' }, { t: 0.5, name: 'eEnd' }] });
  invalidateClips();
  const c = mk();
  const schedules = {
    dt120: () => Array(240).fill(H),
    dt60: () => Array(120).fill(1 / 60),
    dt30: () => Array(60).fill(1 / 30),
    dt15: () => Array(30).fill(1 / 15),
    hitstop: () => { const a = []; for (let i = 0; i < 120; i++) { a.push(1 / 60); if (i % 7 === 3) for (let k = 0; k < 6; k++) a.push(0); } return a; },
    slowmo: () => Array(1200).fill(1 / 600),
    jitter: () => { const rng = makeRng(3), a = []; let s = 0; while (s < 2 - 1e-9) { const d = Math.min(2 - s, [0, 1 / 120, 1 / 60, 1 / 30, 1 / 15][rng.int(0, 4)]); a.push(d); s += d; } return a; },
  };
  for (const name of ['qa.evLoop', 'qa.evOnce', ...DEMO]) {
    const cl = getClip(c.rig, name);
    const row = {};
    for (const [sn, mkS] of Object.entries(schedules)) {
      for (const speed of sn === 'dt60' ? [1, 2, 0.5] : [1]) {
        const dts = mkS();
        const total = dts.reduce((a, x) => a + x, 0);
        reset(c, 'demo.idle', { breath: 0 });
        const evs = [];
        const off = c.onEvent((n, d, cn) => { if (cn === name) evs.push(n); });
        c.play(name, { fade: 0, restart: true, speed });
        for (const dt of dts) c.update(dt, dt);
        // markers exactly on the last boundary may land on either side of it in floating point: one extra frame
        // decides them; nothing may fire twice
        c.update(1e-4, 1e-4);
        off();
        // expected: loops -> markers crossed in [0, span]; one-shots -> each marker with t <= span once
        const exp = {};
        const span = total * speed + 1e-4 * speed;
        for (const e of cl.events) {
          let k = 0;
          if (cl.loop) { for (let cyc = 0; cyc * cl.duration + e.t <= span + 1e-9; cyc++) k++; } else k = e.t <= Math.min(span, cl.duration) + 1e-9 ? 1 : 0;
          exp[e.name] = (exp[e.name] || 0) + k;
        }
        const got = {};
        for (const n of evs) got[n] = (got[n] || 0) + 1;
        const bad = Object.keys({ ...exp, ...got }).filter((k) => (exp[k] || 0) !== (got[k] || 0)).map((k) => `${k}: got ${got[k] || 0} want ${exp[k] || 0}`);
        row[sn + (speed !== 1 ? 'x' + speed : '')] = bad.length ? bad : 'ok';
      }
    }
    out[name] = row;
  }
  // game-style external time on a loop (setClipTime every frame) across 3 cycles: step events + root motion
  {
    const name = 'demo.walkF', cl = getClip(c.rig, name);
    reset(c, name, { breath: 0 });
    let steps = 0, rootF = 0, tm = 0;
    const off = c.onEvent((n) => { if (n === 'step') steps++; });
    for (let i = 0; i < Math.round(3 * cl.duration * 60); i++) { tm += 1 / 60; c.setClipTime(tm); c.update(1 / 60, 1 / 60); rootF += c.rootDelta.f; }
    off();
    out.externalLoop = { clip: name, cycles: 3, stepEvents: steps, stepWant: 6, rootF: r(rootF), rootWant: r(3 * cl.rootEnd[0]) };
    // self-advanced reference
    reset(c, name, { breath: 0 });
    let rf2 = 0;
    for (let i = 0; i < Math.round(3 * cl.duration * 60); i++) { c.update(1 / 60, 1 / 60); rf2 += c.rootDelta.f; }
    out.externalLoop.rootSelfAdvance = r(rf2);
    // markers at / near the wrap under external time (qa.evLoop: e0 at 0, e1f at 1/60, eMid, eEnd at d)
    const ev = getClip(c.rig, 'qa.evLoop');
    for (const dt of [1 / 60, 1 / 30]) {
      reset(c, 'qa.evLoop', { breath: 0 });
      const got = {};
      const off2 = c.onEvent((n) => { got[n] = (got[n] || 0) + 1; });
      let tt = 0;
      const n = Math.round(4 * ev.duration / dt);
      for (let i = 0; i < n; i++) { tt += dt; c.setClipTime(tt); c.update(dt, dt); }
      off2();
      out['externalWrapEvents@' + Math.round(1 / dt)] = { cycles: 4, got, want: { e0: 5, e1f: 4, eMid: 4, eEnd: 4 } };
    }
  }
  // cancel: combo1 -> combo2 at combo1 t = 0.40 (before combo1's trailOff at 0.42)
  {
    reset(c, 'demo.idle', { breath: 0 });
    const cnt = {};
    const off = c.onEvent((n, d, cn) => { cnt[cn + ':' + n] = (cnt[cn + ':' + n] || 0) + 1; });
    c.play('demo.combo1', { fade: 0.06, restart: true });
    for (let i = 0; i < 24; i++) c.update(1 / 60, 1 / 60);
    c.play('demo.combo2', { fade: 0.06, restart: true });
    for (let i = 0; i < 60; i++) c.update(1 / 60, 1 / 60);
    off();
    out.cancel = cnt;
  }
  // events of a masked layer clip (attack while walking)
  {
    reset(c, 'demo.walkF', { breath: 0 });
    const cnt = {};
    const off = c.onEvent((n, d, cn) => { cnt[cn + ':' + n] = (cnt[cn + ':' + n] || 0) + 1; });
    c.layer('atk', 'demo.combo1', { mask: 'upper', fade: 0.05 });
    for (let i = 0; i < 70; i++) c.update(1 / 60, 1 / 60);
    c.stopLayer('atk', 0);
    c.update(1 / 60, 1 / 60);
    off();
    out.layerEvents = cnt;
  }
  return out;
}

/** speed: pose(speed s, t) == pose(speed 1, s t); root motion total independent of speed. */
function testSpeed() {
  const c = mk(), out = {};
  for (const name of ['demo.combo3', 'demo.walkF', 'demo.slam']) {
    const res = {};
    for (const sp of [0.5, 2]) {
      reset(c, name, { breath: 0 });
      c.play(name, { fade: 0, restart: true, speed: 1 });
      const ref = new Map();
      const d = getClip(c.rig, name).duration;
      for (let k = 1; k <= Math.round(d * 120); k++) { c.update(H, H); ref.set(k, qa.poseOf(c)); }
      reset(c, name, { breath: 0 });
      c.play(name, { fade: 0, restart: true, speed: sp });
      let worst = { deg: 0 }, rootSum = 0, rootRef = getClip(c.rig, name).rootEnd[0];
      const n = Math.round((d / sp) * 120);
      for (let k = 1; k <= n; k++) { c.update(H, H); rootSum += c.rootDelta.f; const kk = Math.round(k * sp); const p = ref.get(kk); if (p && Math.abs(k * sp - kk) < 1e-6) { const dd = qa.poseDiff(p, qa.poseOf(c)); if (dd.deg > worst.deg) worst = { ...dd, t: r(k / 120) }; } }
      res['x' + sp] = { worst, root: r(rootSum), rootWant: r(rootRef) };
    }
    out[name] = res;
  }
  // negative speed (reverse playback)
  reset(c, 'demo.combo1', { breath: 0 });
  c.play('demo.combo1', { fade: 0, restart: true, speed: -1, startAt: 0.6 });
  for (let i = 0; i < 60; i++) c.update(1 / 60, 1 / 60);
  out.reverse = { clipTime: r(c.clipTime), finished: c.finished };
  return out;
}

/** Masked / additive layers. */
function testLayers() {
  const c = mk(), out = {};
  const lower = ['thighR', 'thighL', 'shinR', 'shinL', 'footR', 'footL'], upper = ['chest', 'neck', 'head', 'shoulderR', 'upperArmR', 'foreArmR', 'handR', 'upperArmL', 'foreArmL', 'handL'];
  const angDiff = (a, b, list) => { let m = 0, who = null; for (const bn of list) { const k = a.bones.indexOf(bn); const d = qa.qangle(a.q, k * 4, b.q, k * 4) * 180 / Math.PI; if (d > m) { m = d; who = bn; } } return { deg: r(m, 2), bone: who }; };
  const run = (base, setup, frames) => { reset(c, base, { breath: 0 }); if (setup) setup(c); const snaps = []; for (let i = 0; i < frames; i++) { c.update(1 / 60, 1 / 60); snaps.push({ pose: qa.poseOf(c), tip: c.sockets.weaponTip.getWorldPosition(new THREE.Vector3()), grip: gripErr(c) }); } return snaps; };
  // off-hand distance to the clip's grip point (weapon bone frame): measures where the left hand actually is
  const gripErr = (ch) => {
    const w = ch.bones.weaponR, hl = ch.bones.weaponL;
    const inv = new THREE.Matrix4().copy(w.matrixWorld).invert();
    const p = new THREE.Vector3().setFromMatrixPosition(hl.matrixWorld).applyMatrix4(inv);
    return [r(p.x), r(p.y), r(p.z)];
  };
  // a) upper-body attack layered over a walk
  const walk = run('demo.walkF', null, 60), atk = run('demo.combo1', null, 60);
  const lay = run('demo.walkF', (ch) => ch.layer('atk', 'demo.combo1', { mask: 'upper', fade: 0 }), 60);
  let lo = { deg: 0 }, up = { deg: 0 }, tipDev = 0, tipDevT = 0;
  for (let i = 5; i < 55; i++) {
    const a = angDiff(walk[i].pose, lay[i].pose, lower); if (a.deg > lo.deg) lo = { ...a, t: r((i + 1) / 60) };
    const b = angDiff(atk[i].pose, lay[i].pose, upper); if (b.deg > up.deg) up = { ...b, t: r((i + 1) / 60) };
    // tip relative to the hips (root motion differs between walk and combo1)
    const d = lay[i].tip.clone().sub(c.root.position).distanceTo(atk[i].tip);
    if (d > tipDev) { tipDev = d; tipDevT = (i + 1) / 60; }
  }
  out.upperOverWalk = { lowerVsWalk: lo, upperVsCombo1: up, tipVsCombo1: { m: r(tipDev), t: r(tipDevT) } };
  // b) layer whose gripAt differs from the base clip's (guard grips the blade, combo1 the handle)
  const g1 = run('demo.guard', (ch) => ch.layer('atk', 'demo.combo1', { mask: 'upper', fade: 0 }), 20);
  const g0 = run('demo.combo1', null, 20);
  out.gripAtFromBase = { offHandInWeaponFrame_layered: g1[15].grip, offHandInWeaponFrame_combo1Alone: g0[15].grip, gripPoints: { grip: [-0.155, 0, 0], blade: [0.56, 0, 0] } };
  // c) lower-body layer (a step) under the idle
  const footTravel = (snaps, foot) => { const k = snaps[0].pose.bones.indexOf(foot); let mn = 9, mx = -9; for (const s of snaps) { const x = s.pose.p[k * 3]; mn = Math.min(mn, x); mx = Math.max(mx, x); } return r(mx - mn); };
  const idleL = run('demo.idle', (ch) => ch.layer('legs', 'demo.walkF', { mask: 'lower', fade: 0 }), 46);
  const walkAlone = run('demo.walkF', null, 46);
  out.lowerLayer = { footL_travel_layered: footTravel(idleL, 'footL'), footL_travel_walkAlone: footTravel(walkAlone, 'footL'), footR_travel_layered: footTravel(idleL, 'footR') };
  // d) additive layer: idle + additive hit (upper). Afterwards: stopLayer -> exactly back to idle?
  const idle = run('demo.idle', null, 150);
  const add = run('demo.idle', (ch) => ch.layer('flinch', 'demo.hit', { additive: true, fade: 0, mask: 'upper' }), 150);
  let peak = { deg: 0 }, end = null;
  for (let i = 0; i < 150; i++) { const d = angDiff(idle[i].pose, add[i].pose, upper); if (d.deg > peak.deg) peak = { ...d, t: r((i + 1) / 60) }; if (i === 140) end = d; }
  out.additive = { peak, afterClipEnd_t2_35: end, note: 'hit is 0.85 s long; a non-looping additive layer never stops by itself' };
  reset(c, 'demo.idle', { breath: 0 });
  c.layer('flinch', 'demo.hit', { additive: true, fade: 0, mask: 'upper' });
  for (let i = 0; i < 30; i++) c.update(1 / 60, 1 / 60);
  c.stopLayer('flinch', 0.1);
  for (let i = 0; i < 30; i++) c.update(1 / 60, 1 / 60);
  const back = qa.poseOf(c);
  reset(c, 'demo.idle', { breath: 0 });
  for (let i = 0; i < 60; i++) c.update(1 / 60, 1 / 60);
  out.additive.afterStop = qa.poseDiff(qa.poseOf(c), back);
  // e) additive on the legs is undone by the foot re-plant
  const addLegs = run('demo.idle', (ch) => ch.layer('kick', 'demo.combo1', { additive: true, fade: 0, mask: 'lower' }), 40);
  const combo1Legs = run('demo.combo1', null, 40);
  let la = { deg: 0 }, lc = { deg: 0 };
  for (let i = 0; i < 40; i++) { const a = angDiff(idle[i].pose, addLegs[i].pose, lower); if (a.deg > la.deg) la = a; const b = angDiff(combo1Legs[0].pose, combo1Legs[i].pose, lower); if (b.deg > lc.deg) lc = b; }
  out.additiveLegs = { legMotionAddedOverIdle: la, legMotionInCombo1Itself: lc };
  c.stopLayer('kick', 0); c.update(0, 0);
  return out;
}

/** Flinch springs: peak, settle, residual drift, frame-rate dependence, stacking, hit-stop, mirroring. */
function testFlinch() {
  const out = {};
  const runF = (hz, { amount = 1, bone = 'body', dir = [-1, 0, 0], times = [0.1], dur = 3, facing = 1, hitstop = null } = {}) => {
    const c = fresh(), ref = fresh();
    for (const ch of [c, ref]) { reset(ch, 'demo.idle', { breath: 0, facing }); ch.root.position.set(0, 0, 0); }
    let t = 0, peakC = 0, peakH = 0, peakT = 0, settle = null, last = null;
    const n = Math.round(dur * hz);
    const tt = (x) => times.some((y) => t <= y + 1e-9 && t + 1 / hz > y + 1e-9);
    const ser = [];
    for (let i = 0; i < n; i++) {
      if (tt()) c.impulse({ bone, dir, amount });
      const frozen = hitstop && t >= hitstop[0] && t < hitstop[1];
      const dt = frozen ? 0 : 1 / hz;
      c.update(dt, 1 / hz); ref.update(dt, 1 / hz);
      t += 1 / hz;
      const a = qa.poseOf(c), b = qa.poseOf(ref);
      const kb = a.bones.indexOf(bone === 'body' ? 'chest' : bone);
      // deviation from the reference character: sum of the local rotation differences along hips..chest / neck..head
      const dChest = ['hips', 'spine', 'chest'].reduce((s, bn) => { const k = a.bones.indexOf(bn); return s + qa.qangle(a.q, k * 4, b.q, k * 4); }, 0) * 57.2958;
      const dHead = ['neck', 'head'].reduce((s, bn) => { const k = a.bones.indexOf(bn); return s + qa.qangle(a.q, k * 4, b.q, k * 4); }, 0) * 57.2958;
      const dBone = qa.qangle(a.q, kb * 4, b.q, kb * 4) * 57.2958;
      const m = bone === 'body' ? dChest : dBone;
      if (m > peakC) { peakC = m; peakT = t; }
      peakH = Math.max(peakH, dHead);
      if (m > 0.5) settle = null; else if (settle === null && peakC > 0.5) settle = t;
      last = { chest: r(dChest, 4), head: r(dHead, 4), bone: r(dBone, 4) };
      if (i % Math.round(hz / 30) === 0) ser.push(r(m, 2));
    }
    c.dispose(); ref.dispose();
    return { peak: r(peakC, 2), peakT: r(peakT - times[0], 3), headPeak: r(peakH, 2), settledBelow0_5At: settle === null ? null : r(settle - times[times.length - 1], 3), residualAtEnd: last, series: ser };
  };
  out.body_120 = runF(120); out.body_60 = runF(60); out.body_30 = runF(30);
  for (const k of ['body_120', 'body_60', 'body_30']) delete out[k].series;
  out.amount3_60 = runF(60, { amount: 3 }); delete out.amount3_60.series;
  const many = []; for (let k = 0; k < 20; k++) many.push(0.1 + k * 0.05);
  out.stack20_60 = runF(60, { times: many, dur: 4 }); delete out.stack20_60.series;
  out.hitstop_60 = runF(60, { hitstop: [0.1, 0.35] }); delete out.hitstop_60.series;
  out.headBone_60 = runF(60, { bone: 'head', dir: [-1, 0, 0.3] }); delete out.headBone_60.series;
  out.facingL_60 = runF(60, { facing: -1 }); delete out.facingL_60.series;
  return out;
}

/**
 * More than 4 clips blending: play() drops the oldest state while it may still carry most of the weight. Base = guard
 * (w 1), then four plays with a long fade (1 s) one frame apart: the 5th play removes the guard although the four
 * newer states together hold only ~3% of the weight. Measures the per-frame jump of the weapon tip / hands.
 */
function testCap() {
  const c = mk();
  const seq = ['demo.slam', 'demo.hit', 'demo.combo1', 'demo.combo2'];
  const runSeq = (n) => {
    reset(c, 'demo.idle', { breath: 0 });
    c.play('demo.idle', { fade: 0, restart: true });
    c.update(H, H);
    const tip = [], hand = [];
    for (let i = 0; i < 12; i++) {
      if (i >= 4 && i < 4 + n) c.play(seq[i - 4], { fade: 1.0, restart: true });
      c.update(H, H);
      tip.push(c.sockets.weaponTip.getWorldPosition(new THREE.Vector3()));
      hand.push(c.sockets.handL.getWorldPosition(new THREE.Vector3()));
    }
    const jumps = tip.slice(1).map((p, i) => r(p.distanceTo(tip[i]) * 1000, 1));
    return { tipJumpPerFrame_mm: jumps, handLJumpMax_mm: r(Math.max(...hand.slice(1).map((p, i) => p.distanceTo(hand[i]))) * 1000, 1) };
  };
  return { threePlays: runSeq(3), fourPlays_dropsIdle: runSeq(4), note: 'frames 4..7 play one clip each (fade 1 s); with 4 plays the 5th state pushes idle (weight ~0.97) out at frame 7' };
}

/** Deterministic fuzz: random play / setClipTime / impulse / layer / dt (0..1/15) for 3000 frames: NaN, bounds. */
function testFuzz() {
  const c = mk(), rng = makeRng(99);
  reset(c, 'demo.idle', { breath: 1 });
  const all = [...DEMO, 'demo.stance', 'demo.c1end', 'neutral.hold'];
  let nan = null, maxHipsDev = 0, maxTip = 0;
  for (let i = 0; i < 3000 && !nan; i++) {
    const p = rng();
    if (p < 0.04) c.play(rng.pick(all), { fade: rng.pick([0, 0.03, 0.1, 0.3]), restart: rng.chance(0.5), speed: rng.pick([0.5, 1, 1.5, 3]), startAt: rng.range(0, 0.5) });
    else if (p < 0.08) c.setClipTime(rng.range(-1, 3));
    else if (p < 0.1) c.impulse({ bone: rng.pick(['body', 'head', 'chest', 'handR']), dir: [rng.range(-1, 1), rng.range(-1, 1), rng.range(-1, 1)], amount: rng.range(0, 3) });
    else if (p < 0.11) c.layer('L' + rng.int(0, 2), rng.pick(all), { mask: rng.pick(['upper', 'lower', 'arms', 'head']), additive: rng.chance(0.3), weight: rng.range(0, 1) });
    else if (p < 0.12) c.stopLayer('L' + rng.int(0, 2), rng.pick([0, 0.1]));
    else if (p < 0.125) c.setFacing(-c.facing);
    const dt = rng.pick([0, 1 / 120, 1 / 60, 1 / 60, 1 / 30, 1 / 15]);
    c.update(dt, dt);
    const s = qa.poseOf(c);
    for (let k = 0; k < s.p.length; k++) if (!Number.isFinite(s.p[k])) { nan = { frame: i, bone: s.bones[Math.floor(k / 3)] }; break; }
    for (let k = 0; k < s.q.length; k++) if (!Number.isFinite(s.q[k])) { nan = { frame: i, bone: s.bones[Math.floor(k / 4)] }; break; }
    maxHipsDev = Math.max(maxHipsDev, Math.hypot(s.p[0], s.p[1] - 1.0, s.p[2]));
    const tp = c.sockets.weaponTip.getWorldPosition(new THREE.Vector3()).sub(c.root.position);
    maxTip = Math.max(maxTip, tp.length());
  }
  return { frames: 3000, nan, maxHipsFromRest: r(maxHipsDev), maxTipFromRoot: r(maxTip) };
}

/** ms per update(): full knight (two cloths), 1 clip / 2 clips crossfading / 4 clips + 2 layers. */
function testCpu() {
  const out = {};
  for (const kind of ['full', 'lite']) {
    const c = mk(kind);
    const time = (setup, each, frames = 600) => {
      reset(c, 'demo.idle');
      setup(c);
      for (let i = 0; i < 300; i++) { if (each) each(c, i); c.update(1 / 60, 1 / 60); } // JIT warm-up on the same path
      const ms = [];
      for (let i = 0; i < frames; i++) { if (each) each(c, i); const t0 = performance.now(); c.update(1 / 60, 1 / 60); ms.push(performance.now() - t0); }
      ms.sort((a, b) => a - b);
      return { mean: r(ms.reduce((a, x) => a + x, 0) / ms.length, 3), p50: r(ms[ms.length >> 1], 3), p95: r(ms[Math.floor(ms.length * 0.95)], 3), max: r(ms[ms.length - 1], 3) };
    };
    out[kind] = {
      oneClip: time((ch) => ch.play('demo.combo3', { fade: 0, restart: true, loop: true })),
      twoClips: time(() => {}, (ch, i) => { if (i % 6 === 0) ch.play(i % 12 ? 'demo.combo1' : 'demo.combo2', { fade: 0.1, restart: true }); }),
      fourClipsTwoLayers: time((ch) => { ch.layer('a', 'demo.walkF', { mask: 'lower' }); ch.layer('b', 'demo.hit', { additive: true, loop: true }); },
        (ch, i) => { if (i % 2 === 0) ch.play(['demo.combo1', 'demo.combo3', 'demo.slam', 'demo.combo2'][(i / 2) % 4], { fade: 0.3, restart: true }); }),
    };
    reset(c, 'demo.idle');
  }
  // a fixed reference workload, to compare this machine with others: 2e6 quaternion products
  const q = new Float32Array(8); q[3] = 1; q[7] = 1; q[4] = 0.01;
  const t0 = performance.now();
  for (let i = 0; i < 2e6; i++) { const ax = q[0], ay = q[1], az = q[2], aw = q[3], bx = q[4], by = q[5], bz = q[6], bw = q[7]; q[0] = ax * bw + aw * bx + ay * bz - az * by; q[1] = ay * bw + aw * by + az * bx - ax * bz; q[2] = az * bw + aw * bz + ax * by - ay * bx; q[3] = aw * bw - ax * bx - ay * by - az * bz; }
  out.refQuatMul2e6ms = r(performance.now() - t0, 2);
  out.clothQuality = CTX.quality.cloth; out.tier = CTX.quality.tier;
  return out;
}

function runtime(only) {
  const tests = { scrub: testScrub, stepping: () => ({ plain: testStepping(), noBreath: testStepping({ breath: 0 }), withFlinch: testStepping({ impulse: true, breath: 0 }) }), events: testEvents, speed: testSpeed, layers: testLayers, flinch: testFlinch, cap: testCap, fuzz: testFuzz, cpu: testCpu };
  const out = {};
  for (const [k, fn] of Object.entries(tests)) {
    if (only && !only.includes(k)) continue;
    try { out[k] = fn(); } catch (e) { out[k] = { error: String(e && e.stack || e).slice(0, 600) }; }
  }
  return out;
}

/** The same clip on the three body types (IK targets are absolute fighter-frame metres). */
function bodies(name = 'demo.combo1') {
  const out = {};
  for (const id of ['kael', 'iska', 'vorn']) {
    const c = mk('lite', id);
    const a = qa.auditClip(c, name, {});
    out[id] = { rom: a.limits.slice(0, 6).map((l) => `${l.joint}.${l.axis} ${l.value} +${l.over}@${l.t} ${Math.round(l.frac * 100)}%`), romCount: a.limits.length, feet: { maxDrift: a.feet.maxDrift, maxSlide: a.feet.maxSlide }, floor: { feet: a.floor.feet.min, blade: a.floor.blade && a.floor.blade.min } };
  }
  return out;
}

/** Sampler tests on hand-made clips: uniform spin, ease pairs at a key, loop seam with a sign flip. */
function synthetic() {
  const c = mk();
  const out = {};
  // 1) chest yaw 0 -> 360 deg in 1 s, keys every 45 deg, linear ease: angular speed should be a constant 360 deg/s
  const keys = []; for (let k = 0; k <= 8; k++) keys.push({ t: k / 8, bones: { chest: [0, k * 45, 0] } });
  defineClip('qa.spin', { duration: 1, keys });
  // 2) a monotone 3-key move (0 -> 40 -> 80 deg) with the middle key eased in different ways
  const mid = (ease, ease2) => defineClip('qa.ease_' + ease + '_' + ease2, { duration: 0.4, keys: [{ t: 0, bones: { chest: [0, 0, 0] } }, { t: 0.2, ease, bones: { chest: [0, 40, 0] } }, { t: 0.4, ease: ease2, bones: { chest: [0, 80, 0] } }] });
  const pairs = [['linear', 'linear'], ['inOutSine', 'linear'], ['linear', 'outQuad'], ['outCubic', 'linear'], ['inQuad', 'outQuad']];
  pairs.forEach(([a, b]) => mid(a, b));
  // 3) looping 3-key spin (0, 120, 240, closes at 360): seam velocity
  defineClip('qa.loopSpin', { duration: 0.9, loop: true, keys: [{ t: 0, bones: { chest: [0, 0, 0] } }, { t: 0.3, bones: { chest: [0, 120, 0] } }, { t: 0.6, bones: { chest: [0, 240, 0] } }] });
  invalidateClips();
  const speedOf = (name, t0, t1) => {
    const rec = qa.recordClip(c, name, { breath: 0, duration: t1 });
    const an = qa.angular(rec, { bones: ['chest'] });
    // per-frame chest angular speed series
    const k = rec.idx.chest, sp = [];
    for (let i = 0; i < rec.n - 1; i++) sp.push(qa.qangle(rec.Q, (i * rec.B + k) * 4, rec.Q, ((i + 1) * rec.B + k) * 4) / H * 57.2958);
    return { sp, an };
  };
  {
    const { sp } = speedOf('qa.spin', 0, 1);
    const mid2 = sp.slice(6, 114);
    out.uniformSpin = { want: 360, min: Math.round(Math.min(...mid2)), max: Math.round(Math.max(...mid2)), atKeys: [15, 30, 45, 60].map((i) => Math.round(sp[i])), betweenKeys: [7, 22, 37, 52].map((i) => Math.round(sp[i])) };
  }
  out.easePairs = {};
  for (const [a, b] of pairs) {
    const { sp } = speedOf('qa.ease_' + a + '_' + b, 0, 0.4);
    // speed just before / after the middle key at t = 0.2 (frame 24)
    out.easePairs[a + '|' + b] = { before: Math.round(sp[22]), after: Math.round(sp[24]), data: qa.keyContinuity(c.rig, 'qa.ease_' + a + '_' + b).filter((x) => x.ch === 'chest').map((x) => `${x.before}->${x.after}`) };
  }
  {
    const { sp } = speedOf('qa.loopSpin', 0, 1.8);
    out.loopSpin = { want: 400, nearSeam: sp.slice(104, 112).map(Math.round), mid: sp.slice(50, 58).map(Math.round), data: qa.keyContinuity(c.rig, 'qa.loopSpin').map((x) => `${x.ch}@${x.t}${x.seam ? '(seam)' : ''} ${x.before}->${x.after} gap${x.gap}`) };
  }
  return out;
}

// ---- visual scenarios ---------------------------------------------------------------------------------------------------
let overlay = null;
function canvas2d() {
  if (!overlay) {
    overlay = document.createElement('canvas');
    overlay.style.cssText = 'position:fixed;left:0;top:0;width:100vw;height:100vh;z-index:40;pointer-events:none';
    document.body.appendChild(overlay);
  }
  overlay.width = innerWidth; overlay.height = innerHeight; overlay.style.display = 'block';
  const g = overlay.getContext('2d');
  g.clearRect(0, 0, overlay.width, overlay.height);
  return g;
}
const COLS = ['#ff6b5a', '#ffd166', '#6be38a', '#5ac8ff', '#c792ea', '#ffffff', '#ff9f43', '#9aa5b1'];

/** Draw time series plots: series = [{ name, data: Float64Array|[], t: [], color }] stacked in panels. */
function drawPlots(g, panels, { title = '', keys = [], events = [] } = {}) {
  const W = overlay.width, Hh = overlay.height;
  g.fillStyle = 'rgba(8,10,14,0.94)'; g.fillRect(0, 0, W, Hh);
  g.font = '15px monospace'; g.fillStyle = '#fff'; g.fillText(title, 16, 22);
  const top = 34, ph = (Hh - top - 10) / panels.length;
  panels.forEach((p, pi) => {
    const y0 = top + pi * ph, x0 = 70, x1 = W - 16, yb = y0 + ph - 22, yt = y0 + 16;
    const tmax = p.tmax;
    let vmax = p.vmax ?? Math.max(1e-6, ...p.series.flatMap((s) => Array.from(s.data).filter(Number.isFinite)));
    vmax *= 1.05;
    g.strokeStyle = '#333'; g.strokeRect(x0, yt, x1 - x0, yb - yt);
    g.fillStyle = '#aaa'; g.font = '12px monospace';
    g.fillText(p.label, x0 + 6, yt + 13);
    g.fillText(String(Math.round(vmax)), 8, yt + 10); g.fillText('0', 50, yb);
    for (const k of keys) { const x = x0 + (k / tmax) * (x1 - x0); g.strokeStyle = 'rgba(255,255,255,0.18)'; g.beginPath(); g.moveTo(x, yt); g.lineTo(x, yb); g.stroke(); }
    for (const e of events) { const x = x0 + (e[0] / tmax) * (x1 - x0); g.strokeStyle = 'rgba(255,80,80,0.5)'; g.setLineDash([4, 4]); g.beginPath(); g.moveTo(x, yt); g.lineTo(x, yb); g.stroke(); g.setLineDash([]); g.fillStyle = '#f88'; g.fillText(e[1], x + 2, yb - 4); }
    if (p.marks) for (const m of p.marks) { const x = x0 + (m.t / tmax) * (x1 - x0), y = yb - (m.v / vmax) * (yb - yt); g.strokeStyle = '#ff3b3b'; g.lineWidth = 2; g.beginPath(); g.arc(x, y, 6, 0, Math.PI * 2); g.stroke(); g.lineWidth = 1; }
    p.series.forEach((s, si) => {
      g.strokeStyle = s.color || COLS[si % COLS.length]; g.lineWidth = 1.6; g.beginPath();
      let first = true;
      for (let i = 0; i < s.data.length; i++) {
        const v = s.data[i]; if (!Number.isFinite(v)) continue;
        const x = x0 + (s.t[i] / tmax) * (x1 - x0), y = yb - (Math.min(v, vmax) / vmax) * (yb - yt);
        if (first) { g.moveTo(x, y); first = false; } else g.lineTo(x, y);
      }
      g.stroke();
      g.fillStyle = s.color || COLS[si % COLS.length]; g.fillText(s.name, x1 - 150, yt + 14 + si * 14);
    });
    g.fillStyle = '#777';
    for (let k = 0; k <= 10; k++) { const tt = (tmax * k) / 10; g.fillText(tt.toFixed(2), x0 + (k / 10) * (x1 - x0) - 12, yb + 15); }
  });
}

function keyTimes(rig, name) {
  const c = getClip(rig, name), s = new Set();
  const add = (tr) => { if (tr) for (let i = 0; i < tr.n; i++) s.add(+tr.times[i].toFixed(4)); };
  c.bones.forEach((b) => add(b.tr)); add(c.hipsRot); add(c.hipsPos); c.ik.forEach((E) => E && (add(E.posA), add(E.posB)));
  return [...s].sort((a, b) => a - b);
}

/** Angular speed of chosen bones + tip speed (data series) for a clip recorded at 120 Hz. */
function plot(name = 'demo.combo1', bones = ['hips', 'chest', 'head', 'upperArmR', 'handR']) {
  const c = mk();
  const rec = qa.recordClip(c, name, { breath: 0 });
  const tm = Array.from(rec.t);
  const angSeries = bones.map((b) => { const k = rec.idx[b], d = []; for (let i = 0; i < rec.n - 1; i++) d.push(qa.qangle(rec.Q, (i * rec.B + k) * 4, rec.Q, ((i + 1) * rec.B + k) * 4) / H * 57.2958); d.push(NaN); return { name: b + ' deg/s', data: d, t: tm }; });
  const an = qa.angular(rec, { bones });
  const tp = qa.tipPath(rec);
  const g = canvas2d();
  const tmax = rec.t[rec.n - 1];
  const trunk = angSeries.filter((s) => /hips|spine|chest|neck|head/.test(s.name)), limb = angSeries.filter((s) => !/hips|spine|chest|neck|head/.test(s.name));
  const marks = (list) => an.pops.filter((p) => list.some((s) => s.name.startsWith(p.bone + ' '))).map((p) => ({ t: p.t, v: p.w1 }));
  drawPlots(g, [
    { label: 'trunk joint angular speed (deg/s); red circles = pops (isolated velocity steps)', series: trunk, tmax, marks: marks(trunk) },
    { label: 'arm joint angular speed (deg/s)', series: limb, tmax, marks: marks(limb) },
    { label: 'weapon tip speed (m/s) and |jerk|/2000 (m/s^3)', series: [{ name: 'tip m/s', data: Array.from(tp.series.speed), t: tm, color: '#fff' }, { name: 'jerk/2000', data: Array.from(tp.series.jerk).map((x) => x / 2000), t: tm, color: '#ff6b5a' }], tmax },
  ], { title: `${name} at 120 Hz — grey lines = key times, dashed = events`, keys: keyTimes(c.rig, name), events: rec.events.map((e) => [rec.t[e.i], e.name]) });
  return { pops: an.pops.slice(0, 10), swings: tp.swings.map((s) => ({ ...s, kinkList: undefined, spikeList: undefined })) };
}

/** Crossfade heat map (body velocity-step ratio vs the clips alone). */
function xplot(opts = {}) {
  const res = xfade(opts);
  const g = canvas2d(), W = overlay.width, Hh = overlay.height;
  g.fillStyle = 'rgba(8,10,14,0.96)'; g.fillRect(0, 0, W, Hh);
  const names = DEMO, n = names.length, cell = Math.min(54, (Hh - 120) / n), x0 = 230, y0 = 70;
  g.font = '15px monospace'; g.fillStyle = '#fff';
  g.fillText(`crossfade pops (fade ${res.rows[0].fade}s at ~45% of the source): cell = max landmark velocity step in the transition / max step inside either clip alone`, 16, 24);
  g.fillText('rows = from, columns = to; red >= 2x, orange >= 1.5x; number = m/s per 1/120 s frame', 16, 44);
  g.font = '11px monospace';
  names.forEach((nm, i) => { g.fillStyle = '#ccc'; g.fillText(nm, 16, y0 + i * cell + cell * 0.6); g.save(); g.translate(x0 + i * cell + cell * 0.5, y0 - 6); g.rotate(-0.6); g.fillText(nm.replace('demo.', ''), 0, 0); g.restore(); });
  for (const row of res.rows) {
    const i = names.indexOf(row.from), j = names.indexOf(row.to);
    const k = row.bodyRatio;
    g.fillStyle = k >= 2 ? '#c0392b' : k >= 1.5 ? '#d68910' : k >= 1 ? '#7d6608' : '#1e5631';
    g.fillRect(x0 + j * cell + 1, y0 + i * cell + 1, cell - 2, cell - 2);
    g.fillStyle = '#fff'; g.fillText(row.body.toFixed(1), x0 + j * cell + 6, y0 + i * cell + cell * 0.45); g.fillText('x' + k.toFixed(1), x0 + j * cell + 6, y0 + i * cell + cell * 0.8);
  }
  return { pops: res.pops, worstBody: res.worstBody, worstAng: res.worstAng };
}

/** 3D tip-path trace (coloured by speed; red = kinks / jerk spikes) and a pose held at tHold. */
const traceObjs = [];
function trace(name = 'demo.combo1', tHold = null, view = null) {
  for (const o of traceObjs) { o.removeFromParent(); o.geometry && o.geometry.dispose(); }
  traceObjs.length = 0;
  if (overlay) overlay.style.display = 'none';
  const c = mk('full');
  const rec = qa.recordClip(c, name, { breath: 1 });
  const tp = qa.tipPath(rec);
  const pts = [], cols = [];
  const vmax = Math.max(...tp.series.speed);
  for (let i = 0; i < rec.n; i++) {
    pts.push(rec.tip[i * 3], rec.tip[i * 3 + 1], rec.tip[i * 3 + 2]);
    const k = tp.series.speed[i] / vmax;
    cols.push(0.2 + 0.8 * k, 0.6 + 0.4 * k, 1 - 0.7 * k);
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pts, 3));
  geo.setAttribute('color', new THREE.Float32BufferAttribute(cols, 3));
  const line = new THREE.Line(geo, new THREE.LineBasicMaterial({ vertexColors: true, toneMapped: false }));
  CTX.scene.add(line); traceObjs.push(line);
  // frame dots every 1/60 s (spacing shows speed) and red markers at kinks / jerk spikes
  const dots = [], bad = [];
  for (let i = 0; i < rec.n; i += 2) dots.push(rec.tip[i * 3], rec.tip[i * 3 + 1], rec.tip[i * 3 + 2]);
  for (const s of tp.swings) for (const k of [...s.kinkList, ...s.spikeList]) { const i = Math.round(k.t * 120) - 1; if (i >= 0 && i < rec.n) bad.push(rec.tip[i * 3], rec.tip[i * 3 + 1], rec.tip[i * 3 + 2]); }
  const dg = new THREE.BufferGeometry(); dg.setAttribute('position', new THREE.Float32BufferAttribute(dots, 3));
  const dp = new THREE.Points(dg, new THREE.PointsMaterial({ color: 0xffffff, size: 0.025, toneMapped: false }));
  CTX.scene.add(dp); traceObjs.push(dp);
  if (bad.length) { const bg = new THREE.BufferGeometry(); bg.setAttribute('position', new THREE.Float32BufferAttribute(bad, 3)); const bp = new THREE.Points(bg, new THREE.PointsMaterial({ color: 0xff2020, size: 0.07, toneMapped: false })); CTX.scene.add(bp); traceObjs.push(bp); }
  // hold the full knight at tHold (or the peak tip speed) in the same world frame
  const hold = tHold ?? (tp.swings[0] ? tp.swings[0].peakT : 0.2);
  for (const ch of LAB.chars) ch.setVisible(false);
  if (!c.root.parent) CTX.scene.add(c.root);
  c.setVisible(true);
  reset(c, name, { breath: 1 });
  c.applyRootMotion = true;
  const n = Math.round(hold * 120);
  for (let i = 0; i < n; i++) c.update(H, H);
  c.applyRootMotion = false;
  LAB.st.freeze = c;
  if (view) LAB.view(view);
  return { hold, swings: tp.swings.map((s) => ({ t0: s.t0, t1: s.t1, peak: s.peak, straight: s.straight, kinks: s.kinks, jerkSpikes: s.jerkSpikes, edge: s.edge })) };
}

/** COM ground track vs support polygon (top-down plot) for a clip. */
function balancePlot(name = 'demo.slam') {
  const c = mk();
  const rec = qa.recordClip(c, name, { breath: 0 });
  const C = qa.contacts(rec), b = qa.balance(rec, { contacts: C });
  const g = canvas2d(), W = overlay.width, Hh = overlay.height;
  g.fillStyle = 'rgba(8,10,14,0.96)'; g.fillRect(0, 0, W, Hh);
  // left: top-down; right: distance outside over time
  const sc = 300, cx = 320, cz = Hh / 2;
  const P = (x, z) => [cx + (x - 0.2) * sc, cz + z * sc];
  for (let f = 0; f < rec.n; f += 6) {
    const pts = C[f].pts; if (!pts.length) continue;
    g.strokeStyle = `rgba(90,200,255,${0.08 + 0.3 * (f / rec.n)})`; g.beginPath();
    const hp = pts.slice().sort((a, bb) => a[0] - bb[0]);
    hp.forEach((p, k) => { const [x, y] = P(p[0], p[1]); if (!k) g.moveTo(x, y); else g.lineTo(x, y); });
    g.stroke();
  }
  g.strokeStyle = '#ffd166'; g.lineWidth = 2; g.beginPath();
  for (let f = 0; f < rec.n; f++) { const [x, y] = P(b.series.com[f * 3], b.series.com[f * 3 + 2]); if (!f) g.moveTo(x, y); else g.lineTo(x, y); }
  g.stroke(); g.lineWidth = 1;
  for (let f = 0; f < rec.n; f++) { if (C[f].flat[0] && C[f].flat[1] && b.series.dist[f] > 0.02) { const [x, y] = P(b.series.com[f * 3], b.series.com[f * 3 + 2]); g.fillStyle = '#ff3b3b'; g.fillRect(x - 2, y - 2, 4, 4); } }
  g.fillStyle = '#fff'; g.font = '14px monospace';
  g.fillText(`${name}: top-down (x right = forward, down = +s camera side). yellow = COM ground track; blue = foot contact points;`, 16, 22);
  g.fillText(`red = both feet flat but COM outside the support polygon by > 2 cm. unsupported ${b.unsupported}s of ${b.bothPlanted}s, max ${b.maxOutside} m @ ${b.maxOutsideT}s`, 16, 42);
  const tm = Array.from(rec.t);
  // simple right panel
  const x0 = 680, x1 = W - 20, yt = 80, yb = Hh - 40, tmax = tm[tm.length - 1];
  g.strokeStyle = '#333'; g.strokeRect(x0, yt, x1 - x0, yb - yt);
  for (let f = 0; f < rec.n; f++) if (C[f].flat[0] && C[f].flat[1]) { g.fillStyle = 'rgba(255,255,255,0.06)'; g.fillRect(x0 + (tm[f] / tmax) * (x1 - x0), yt, (x1 - x0) / rec.n + 1, yb - yt); }
  const y = (d) => yb - ((Math.max(-0.2, Math.min(0.6, d)) + 0.2) / 0.8) * (yb - yt);
  g.strokeStyle = '#888'; g.beginPath(); g.moveTo(x0, y(0)); g.lineTo(x1, y(0)); g.stroke();
  g.strokeStyle = '#ffd166'; g.beginPath();
  for (let f = 0; f < rec.n; f++) { const xx = x0 + (tm[f] / tmax) * (x1 - x0), yy = y(b.series.dist[f]); if (!f) g.moveTo(xx, yy); else g.lineTo(xx, yy); }
  g.stroke();
  g.fillStyle = '#aaa'; g.font = '12px monospace'; g.fillText('COM distance outside the support polygon (m; < 0 inside). grey = both feet flat', x0 + 6, yt - 8); g.fillText('0', x0 - 14, y(0) + 4); g.fillText('0.6', x0 - 28, yt + 8);
  for (let k = 0; k <= 10; k++) g.fillText((tmax * k / 10).toFixed(2), x0 + (k / 10) * (x1 - x0) - 12, yb + 15);
  return { ...b, series: undefined };
}

createLab({
  view: { target: [0.3, 1.0, 0], dist: 4.6, yaw: 0, pitch: 4, fov: 40 },
  setup(ctx, lab) {
    CTX = ctx; LAB = lab;
    const a = createCharacter(ctx, knight, { name: 'p1' });
    lab.chars = [a];
    lab.st = { freeze: null };
    a.play('demo.idle', { fade: 0 });
    a.update(0, 0);
    ctx.onUpdate((dg, dr) => { for (const c of lab.chars) if (c.root.visible) c.update(dg, dr); }, ORDER.CHAR);
    window.__ED.qa = qa;
    window.__ED.anim = { defineClip, invalidateClips, getClip };
    window.__ED.audit = {
      list: () => DEMO, clip, summary, keys: (name) => qa.keyContinuity(mk().rig, name), xfade, runtime, bodies, synthetic,
      plot, xplot, trace, balancePlot, mk, getClipDef,
    };
  },
  scenarios: {
    /** Hold the full knight at clip time t (run from 0 at 120 Hz), optional camera view and exposure, no overlays. */
    hold(ctx, lab, name, t = 0, view = null, exposure = 1) {
      for (const o of traceObjs) o.visible = false;
      if (overlay) overlay.style.display = 'none';
      for (const ch of lab.chars) ch.setVisible(false);
      const c = mk('full');
      if (!c.root.parent) ctx.scene.add(c.root);
      c.setVisible(true);
      reset(c, name, { breath: 1 });
      c.applyRootMotion = true;
      for (let i = 0; i < Math.round(t * 120); i++) c.update(H, H);
      c.applyRootMotion = false;
      if (ctx.post && ctx.post.fx) ctx.post.fx.exposure = exposure;
      if (view) lab.view(view);
      // bone axes on top: forearm (cyan, elbow -> wrist), hand long axis (yellow, wrist -> 12 cm along the hand's -Y,
      // the direction the forearm continues in when the wrist is straight), blade direction (red, hand +X, 25 cm)
      if (lab.axes) { lab.axes.removeFromParent(); lab.axes.geometry.dispose(); }
      const pts = [], cols = [], v = new THREE.Vector3(), w = new THREE.Vector3();
      const seg = (a, b, col) => { pts.push(a.x, a.y, a.z, b.x, b.y, b.z); cols.push(...col, ...col); };
      const ax = (bone, x, y, z, out) => out.set(x, y, z).applyMatrix4(c.bones[bone].matrixWorld);
      for (const s of ['R', 'L']) {
        seg(ax('foreArm' + s, 0, 0, 0, v), ax('hand' + s, 0, 0, 0, w), [0, 1, 1]);
        seg(ax('hand' + s, 0, 0, 0, v), ax('hand' + s, 0, -0.12, 0, w), [1, 1, 0]);
        seg(ax('hand' + s, 0, -0.085, 0, v), ax('hand' + s, 0.25, -0.085, 0, w), [1, 0.2, 0.2]);
      }
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.Float32BufferAttribute(pts, 3));
      g.setAttribute('color', new THREE.Float32BufferAttribute(cols, 3));
      lab.axes = new THREE.LineSegments(g, new THREE.LineBasicMaterial({ vertexColors: true, depthTest: false, toneMapped: false }));
      lab.axes.renderOrder = 10;
      ctx.scene.add(lab.axes);
      return { t, root: c.root.position.x };
    },
    /** 5-state cap: idle, then 4 plays (fade 1 s) one 1/120 frame apart; hold after `frames` updates (7 = just before, 8 = after the drop). */
    cap(ctx, lab, frames = 7, view = null) {
      if (overlay) overlay.style.display = 'none';
      for (const o of traceObjs) o.visible = false;
      for (const ch of lab.chars) ch.setVisible(false);
      const c = mk('full');
      if (!c.root.parent) ctx.scene.add(c.root);
      c.setVisible(true);
      reset(c, 'demo.idle', { breath: 0 });
      c.play('demo.idle', { fade: 0, restart: true }); c.update(H, H);
      const seq = ['demo.slam', 'demo.hit', 'demo.combo1', 'demo.combo2'];
      for (let i = 0; i < frames; i++) { if (i >= 4 && i < 8) c.play(seq[i - 4], { fade: 1.0, restart: true }); c.update(H, H); }
      if (view) lab.view(view);
      return { tip: c.sockets.weaponTip.getWorldPosition(new THREE.Vector3()).toArray().map((v) => r(v)) };
    },
    /** Base clip + layer clip (mask), held at t. */
    layer(ctx, lab, base, clipName, mask = 'upper', t = 0.3, view = null) {
      if (overlay) overlay.style.display = 'none';
      for (const o of traceObjs) o.visible = false;
      for (const ch of lab.chars) ch.setVisible(false);
      const c = mk('full');
      if (!c.root.parent) ctx.scene.add(c.root);
      c.setVisible(true);
      reset(c, base, { breath: 0 });
      if (clipName) c.layer('atk', clipName, { mask, fade: 0 });
      for (let i = 0; i < Math.round(t * 120); i++) c.update(H, H);
      if (view) lab.view(view);
      const w = c.bones.weaponR.matrixWorld.clone().invert();
      return { offHandInWeaponFrame: new THREE.Vector3().setFromMatrixPosition(c.bones.weaponL.matrixWorld).applyMatrix4(w).toArray().map((v) => r(v)) };
    },
    trace(ctx, lab, name, t, view) { return trace(name, t, view); },
    plot(ctx, lab, name, bones) { return plot(name, bones); },
    xplot(ctx, lab, opts) { return xplot(opts); },
    balance(ctx, lab, name) { return balancePlot(name); },
  },
});
