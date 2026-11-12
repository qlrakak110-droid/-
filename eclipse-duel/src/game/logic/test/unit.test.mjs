// Unit tests of the rules engine. Each test builds a small scripted duel (see harness.mjs: no intro, fighters placed
// 1.6 m apart unless stated) and checks events and state.

import { test, assert, eq, near, throws, clone, duel, run, runUntil, events, first, sampleFighter } from './harness.mjs';
import { validateFighterDef } from '../defs.js';
import { deriveFrameData, frameDataTable } from '../framedata.js';
import { createMatch } from '../match.js';
import { createScriptedController } from '../controllers.js';
import { createAIController } from '../ai.js';

const S = sampleFighter;

// ------------------------------------------------------------------------------------------------ definitions

test('validate: the sample fighter is valid and warning-free', () => {
  const r = validateFighterDef(S);
  eq(r.ok, true, r.errors.join('; '));
  eq(r.warnings.length, 0, r.warnings.join('; '));
});

test('validate: precise, path-qualified errors and suggestions', () => {
  const d = clone(S);
  delete d.moves.light1.duration;
  d.moves.light2.hits[0].t = [0.1, 0.9];
  d.moves.light2.hits[0].level = 'ligt';
  d.moves.heavy.cancels[0].into = ['@skill', 'lunj'];
  d.moves.heavy.hit = [];
  d.commands['f+heavy'] = 'lungee';
  d.moves.verdict.superFreeze = 0.9;
  d.moves.tempest.hits[0].multi = { interval: 0.2, max: 5 };
  const r = validateFighterDef(d);
  eq(r.ok, false);
  const has = (list, s) => assert(list.some((e) => e.includes(s)), `missing message containing "${s}" in:\n  ${list.join('\n  ')}`);
  has(r.errors, 'moves.light1.duration: required number is missing');
  has(r.errors, 'moves.light2.hits[0].t: hit window (s) [0.1,0.9] must lie inside [0, 0.4]');
  has(r.errors, "moves.light2.hits[0].level: expected one of 'light' | 'heavy' | 'launch' | 'crumple' | 'knockdown', got \"ligt\" - did you mean 'light'?");
  has(r.errors, "moves.heavy.cancels[0].into: unknown move 'lunj' - did you mean 'lunge'?");
  has(r.errors, "def.commands.f+heavy: unknown move \"lungee\" - did you mean 'lunge'?");
  has(r.errors, 'moves.verdict.superFreeze: the first active time 0.82 s falls inside the 0.9 s super-freeze');
  has(r.warnings, "moves.heavy.hit: unknown field (ignored) - did you mean 'hits'?");
  has(r.warnings, 'moves.tempest.hits[0].multi: window 0.44');
});

test('validate: createMatch throws on an invalid definition and on unknown rules', () => {
  const d = clone(S);
  d.moves.light1.hits[0].box = { f: [1, 0.5], u: [0, 1] };
  throws(() => createMatch({ fighters: [d, S] }), /moves\.light1\.hits\[0\]\.box\.f: forward range \(m\) start 1 must be < its end 0.5/);
  throws(() => createMatch({ fighters: [S, S], rules: { roundTim: 60 } }), /rules\.roundTim: unknown rule/);
});

test('frame data: derived from the move data, printable as a table', () => {
  const fd = deriveFrameData(S.moves.light1);
  near(fd.startup, 0.1, 1e-9);
  near(fd.recovery, 0.22, 1e-9);
  near(fd.onHit, 0.04, 1e-9);
  near(fd.onBlock, -0.06, 1e-9);
  eq(fd.frames.startup, 6);
  eq(fd.frames.onBlock, -4);
  const lunge = deriveFrameData(S.moves.lunge);
  near(lunge.reach, 2.6 + 1.6, 1e-9, 'lunge reach includes its motion');
  const tbl = frameDataTable(S);
  for (const id of Object.keys(S.moves)) assert(tbl.includes(id), `table lists ${id}`);
  assert(/light1\s+light\s+6\s+2\s+13/.test(tbl), 'light1 row: startup 6f, active 2f, recovery 13f');
});

// ------------------------------------------------------------------------------------------------ hits

test('hit: damage, reaction, hit-stop on both fighters, victim shakes', () => {
  const { m, log } = duel({ s0: [{ t: 0, light: true }] });
  runUntil(m, () => events(log, 'hit').length > 0, 1);
  const h = first(log, 'hit');
  eq(h.attacker, 0); eq(h.defender, 1); eq(h.move, 'light1'); eq(h.damage, 34); eq(h.blocked, false); eq(h.level, 'light');
  near(h.hitstop, 0.06, 1e-9);
  eq(m.fighters[1].hp, 966);
  eq(m.fighters[1].state, 'hitstun');
  assert(m.fighters[0].hitstop > 0 && m.fighters[1].hitstop > 0, 'both frozen');
  eq(m.fighters[1].hitstopShake, true);
  eq(m.fighters[0].hitstopShake, false);
  assert(h.x > m.fighters[0].x && h.x < m.fighters[1].x + 0.5, 'contact point between the fighters');
  // timers do not advance during hit-stop
  const mt = m.fighters[0].moveTime, st = m.fighters[1].timer;
  m.step(1 / 60);
  eq(m.fighters[0].moveTime, mt, 'attacker move clock frozen');
  eq(m.fighters[1].timer, st, 'victim stun frozen');
  run(m, 0.1);
  assert(m.fighters[0].moveTime > mt, 'attacker resumes');
  assert(m.fighters[1].timer < st, 'victim stun resumes');
});

test('hit-stop: exposed per fighter and identical at any dt (sub-stepping)', () => {
  const hitAt = (dt) => {
    const { m, log } = duel({ s0: [{ t: 0, light: true }] });
    runUntil(m, () => events(log, 'hit').length > 0, 1, dt);
    return { t: first(log, 'hit').time, hp: m.fighters[1].hp };
  };
  const a = hitAt(1 / 60), b = hitAt(1 / 30), c = hitAt(1 / 144);
  eq(a.hp, b.hp); eq(a.hp, c.hp);
  // the press is polled once per step, so the move starts one step later at a coarser dt
  near(a.t, b.t, 2 / 30 + 1e-6, 'same hit time within the step quantisation');
  near(a.t, c.t, 2 / 60 + 1e-6);
});

test('guard: blocks from the front, drains the gauge, blockstun, no chip from normals', () => {
  const { m, log } = duel({ s0: [{ t: 0.2, light: true }], s1: [{ t: 0, dur: 2, guard: true }] });
  run(m, 0.6);
  const h = first(log, 'hit');
  eq(h.blocked, true); eq(h.perfect, false); eq(h.damage, 0);
  eq(m.fighters[1].hp, 1000);
  assert(first(log, 'guard'), 'guard event');
  assert(first(log, 'state', (e) => e.fighter === 1 && e.to === 'blockstun'), 'blockstun');
  assert(m.fighters[1].guard < 100 && m.fighters[1].guard >= 92 - 1e-9, 'gauge drained by guardDamage 8');
});

test('guard: skills chip through guard; chip cannot KO by default', () => {
  const { m, log } = duel({ s0: [{ t: 0, skill1: true }], s1: [{ t: 0, dur: 3, guard: true }], x: [-1.5, 1.5] });
  run(m, 1.2);
  const h = first(log, 'hit');
  eq(h.blocked, true); eq(h.kind, 'projectile'); eq(h.chip, 11, '15 % of 70');
  eq(m.fighters[1].hp, 989);
  const { m: m2 } = duel({ s0: [{ t: 0, skill1: true }], s1: [{ t: 0, dur: 3, guard: true }], x: [-1.5, 1.5] });
  m2.setMeter(1, 'hp', 5);
  run(m2, 1.2);
  eq(m2.fighters[1].hp, 1, 'chip stops at 1 HP');
});

test('guard: perfect guard (pressed just before impact) takes no chip and no gauge damage', () => {
  const { m, log } = duel({ s0: [{ t: 0, light: true }], s1: [{ t: 0.06, dur: 1, guard: true }] });
  run(m, 0.5);
  const h = first(log, 'hit');
  eq(h.blocked, true); eq(h.perfect, true);
  eq(m.fighters[1].guard, 100);
});

test('guard: attacks from behind are not blocked', () => {
  const { m, log } = duel({ s0: [{ t: 0.1, light: true }], s1: [{ t: 0, dur: 2, guard: true }], rules: { turnDelay: 100 } });
  m.place(1, 0.8, 1); // facing away, cannot turn (huge turn delay)
  run(m, 0.6);
  const h = first(log, 'hit');
  eq(h.blocked, false);
  eq(m.fighters[1].hp, 966);
});

test('guard break: an empty gauge breaks the guard, stuns, then refills', () => {
  const { m, log } = duel({ s0: [{ t: 0, heavy: true }], s1: [{ t: 0, dur: 3, guard: true }] });
  m.setMeter(1, 'guard', 10);
  run(m, 0.6);
  const gb = first(log, 'guardBreak');
  assert(gb && gb.fighter === 1, 'guardBreak event');
  eq(m.fighters[1].state, 'guardbreak');
  eq(first(log, 'hit').guardBreak, true);
  run(m, 1.3);
  eq(m.fighters[1].guard, 100, 'gauge refilled after the break');
  assert(m.fighters[1].state === 'guard' || m.fighters[1].state === 'idle', 'recovered');
});

test('dodge: invulnerable window evades the hit (perfect dodge), then a cooldown', () => {
  const { m, log } = duel({ s0: [{ t: 0, heavy: true }], s1: [{ t: 0.24, dodge: true }, { t: 0.9, dodge: true }] });
  run(m, 1.3);
  eq(events(log, 'hit').length, 0, 'no hit lands');
  const pd = first(log, 'perfectDodge');
  assert(pd && pd.fighter === 1 && pd.attacker === 0, 'perfectDodge event');
  eq(events(log, 'dodge', (e) => e.fighter === 1).length, 1, 'second dodge refused during the cooldown');
  eq(m.fighters[1].hp, 1000);
});

test('armour: absorbs one hit (damage, no flinch) and the armoured move still lands', () => {
  const { m, log } = duel({ s0: [{ t: 0, heavy: true }], s1: [{ t: 0.04, light: true }] });
  run(m, 0.8);
  const hs = events(log, 'hit');
  const arm = hs.find((h) => h.defender === 0);
  assert(arm && arm.armoured, 'first hit on P0 is armoured');
  eq(arm.damage, 34);
  const back = hs.find((h) => h.attacker === 0);
  assert(back && back.move === 'heavy' && !back.blocked, 'heavy lands through the jab');
  eq(m.fighters[1].hp, 1000 - 105);
  // a second hit during the same armour window is not absorbed (hits: 1): the multi-hit spin breaks it
  const r2 = duel({ s0: [{ t: 0, heavy: true }], s1: [{ t: 0, skill2: true }] });
  run(r2.m, 0.8);
  const onP0 = events(r2.log, 'hit', (h) => h.defender === 0);
  assert(onP0.length >= 2 && onP0[0].armoured && !onP0[1].armoured, 'second sub-hit interrupts');
  assert(events(r2.log, 'moveEnd', (e) => e.fighter === 0 && e.move === 'heavy' && e.reason === 'interrupted').length === 1, 'heavy interrupted');
});

test('counter stance: a hit inside the window is nullified and triggers the follow-up', () => {
  const { m, log } = duel({ s0: [{ t: 0.12, light: true }], s1: [{ t: 0, skill3: true }] });
  run(m, 1.2);
  const c = first(log, 'counter');
  assert(c && c.fighter === 1 && c.into === 'ward_burst', 'counter event');
  assert(first(log, 'moveStart', (e) => e.fighter === 1 && e.move === 'ward_burst' && e.forced), 'burst starts');
  eq(m.fighters[1].hp, 1000, 'countered hit deals nothing');
  eq(m.fighters[0].hp, 890, 'burst hits for 110');
});

// ------------------------------------------------------------------------------------------------ input, cancels

test('input buffer: a press 0.1 s early comes out on the first frame of the route window', () => {
  const { m, log } = duel({ s0: [{ t: 0, light: true }, { t: 0.07, light: true }], x: [-3, 3] }); // whiff: no hit-stop
  run(m, 0.6);
  const l1 = first(log, 'moveStart', (e) => e.move === 'light1');
  const l2 = first(log, 'moveStart', (e) => e.move === 'light2');
  assert(l2 && l2.cancelFrom === 'light1', 'light2 chained from light1');
  near(l2.time - l1.time, 0.13, 1 / 60 + 1e-9, 'at the window start');
});

test('input buffer: presses older than the buffer expire', () => {
  const { m, log } = duel({ s0: [{ t: 0, light: true }, { t: 0.07, light: true }], rules: { inputBuffer: 0.03 }, x: [-3, 3] });
  run(m, 0.6);
  eq(events(log, 'moveStart', (e) => e.move === 'light2').length, 0);
});

test('cancels: on-hit-only cancels refuse whiffs; the buffered press then starts from neutral', () => {
  const press = [{ t: 0, light: true }, { t: 0.2, dur: 0.05, heavy: true, down: true }];
  const hit = duel({ s0: press });
  run(hit.m, 0.8);
  const l = first(hit.log, 'moveStart', (e) => e.move === 'launcher');
  eq(l.cancelFrom, 'light1', 'on hit: cancels');
  const whiff = duel({ s0: press, x: [-3, 3] });
  run(whiff.m, 0.8);
  const w = first(whiff.log, 'moveStart', (e) => e.move === 'launcher');
  assert(w && w.cancelFrom === null, 'on whiff: no cancel, starts after light1 ends');
  const end = first(whiff.log, 'moveEnd', (e) => e.move === 'light1');
  eq(end.reason, 'complete');
  assert(w.time >= end.time, 'after the end');
});

test('commands: direction variants resolve relative to facing (f+heavy, d+heavy)', () => {
  const a = duel({ s0: [{ t: 0, heavy: true, move: 1 }], x: [-4, 4] });
  run(a.m, 0.1);
  eq(first(a.log, 'moveStart').move, 'lunge');
  const b = duel({ s0: [{ t: 0, heavy: true, move: -1 }], x: [4, -4] }); // P0 on the right faces -X: -1 is forward
  run(b.m, 0.1);
  eq(first(b.log, 'moveStart').move, 'lunge');
  const c = duel({ s0: [{ t: 0, heavy: true, down: true }], x: [-4, 4] });
  run(c.m, 0.1);
  eq(first(c.log, 'moveStart').move, 'launcher');
});

test('movement: double-tap dash, dodge+back backstep, walk speeds', () => {
  const a = duel({ s0: [{ t: 0, move: 1, dur: 0.05 }, { t: 0.1, move: 1, dur: 0.05 }], x: [-4, 4] });
  run(a.m, 0.6);
  const d = first(a.log, 'dodge');
  eq(d.kind, 'dash');
  near(a.m.fighters[0].x, -4 + 2.4 + 0.05 * 2.5, 0.06, 'dash distance (+ the first tap walk)');
  const b = duel({ s0: [{ t: 0, dodge: true, move: -1 }], x: [-4, 4] });
  run(b.m, 0.6);
  eq(first(b.log, 'dodge').kind, 'backstep');
  near(b.m.fighters[0].x, -4 - 1.7, 0.06);
  const w = duel({ s0: [{ t: 0, move: 1, dur: 1 }], s1: [{ t: 0, move: 1, dur: 1 }], x: [-6, 4] });
  run(w.m, 1);
  near(w.m.fighters[0].x - -6, 2.5, 0.05, 'forward walk 2.5 m/s');
  near(w.m.fighters[1].x - 4, 1.8, 0.05, 'back walk 1.8 m/s');
});

test('command dash: passes through the opponent; the next move turns around', () => {
  const { m, log } = duel({ s0: [{ t: 0, skill3: true, move: 1 }, { t: 0.3, light: true }] });
  run(m, 0.5);
  assert(m.fighters[0].x > m.fighters[1].x, 'P0 ended up on the other side');
  const l = first(log, 'moveStart', (e) => e.move === 'light1');
  assert(l && l.cancelFrom === 'phase_step', 'light1 cancels the dash');
  eq(l.facing, -1, 'faces the opponent behind it');
});

test('teleport: lands behind the opponent and turns; a guard that cannot turn is crossed up', () => {
  const blink = [{ t: 0, skill3: true, move: -1 }]; // back + skill3 (P0 faces +X)
  const a = duel({ s0: blink });
  run(a.m, 0.8);
  const tp = first(a.log, 'teleport');
  near(tp.from, -0.8, 1e-9); near(tp.to, 0.8 + 1.1, 1e-9); eq(tp.facing, -1);
  eq(first(a.log, 'hit').blocked, false);
  eq(a.m.fighters[1].hp, 935);
  const b = duel({ s0: blink, s1: [{ t: 0, dur: 2, guard: true }] });
  run(b.m, 0.8);
  eq(first(b.log, 'hit').blocked, true, 'a guard that turns in time blocks');
  const c = duel({ s0: blink, s1: [{ t: 0, dur: 2, guard: true }], rules: { turnDelay: 100 } });
  run(c.m, 0.8);
  eq(first(c.log, 'hit').blocked, false, 'cross-up');
});

test('requirements and armour-pierce: distance-gated move refused up close; armourPierce goes through armour', () => {
  const a = duel({ s0: [{ t: 0, skill1: true, move: -1 }] });
  run(a.m, 0.2);
  eq(first(a.log, 'moveDenied').reason, 'distance');
  const b = duel({ s0: [{ t: 0, heavy: true, move: 1 }], s1: [{ t: 0, heavy: true }], x: [-3, 0.5] });
  run(b.m, 0.6);
  const h = first(b.log, 'hit', (e) => e.attacker === 0);
  eq(h.move, 'lunge'); eq(h.armoured, false);
  eq(first(b.log, 'moveEnd', (e) => e.fighter === 1).reason, 'interrupted');
  eq(b.m.fighters[1].stunKind, 'crumple');
});

test('hurtboxes: a whiffed move stays vulnerable at the tip (explicit hurt window)', () => {
  const { m, log } = duel({ s0: [{ t: 0, heavy: true }], s1: [{ t: 0.45, light: true }], x: [-1.3, 1.8] }); // sweep tip 1.0 < body 1.38
  run(m, 0.9);
  const h = first(log, 'hit');
  assert(h && h.attacker === 1 && h.defender === 0, 'the jab reaches the extended blade');
  eq(h.punish, true);
});

// ------------------------------------------------------------------------------------------------ projectiles

test('projectiles: anchored at the opponent, telegraphed, multi-hit; cooldown shared through cooldownKey', () => {
  const { m, log } = duel({ s0: [{ t: 0, skill1: true, move: -1 }, { t: 1.2, skill1: true }], x: [-3, 3] });
  run(m, 1.5);
  const sp = first(log, 'projectileSpawn');
  eq(sp.kind, 'grave_pillar'); near(sp.x, 3, 1e-9); near(sp.delay, 0.45, 1e-9);
  const act = first(log, 'projectileActive');
  near(act.time - sp.time, 0.45, 1 / 60 + 1e-9);
  const hits = events(log, 'hit');
  eq(hits.length, 3);
  assert(hits.every((h) => h.time >= act.time), 'harmless during the telegraph');
  eq(m.fighters[1].hp, 1000 - 30 - 30 - 27);
  eq(first(log, 'moveDenied').reason, 'cooldown', 'crescent shares the cooldown');
});

test('projectiles: spawn on the timeline, travel, expire at the end of their lifetime', () => {
  const { m, log } = duel({ s0: [{ t: 0, skill1: true }], x: [-8, 8] });
  run(m, 1.5);
  const sp = first(log, 'projectileSpawn');
  const ms = first(log, 'moveStart');
  near(sp.time - ms.time, 0.26, 1 / 60 + 1e-9);
  near(sp.x, -8 + 0.8, 1e-9); eq(sp.vx, 11);
  const ex = first(log, 'projectileExpire');
  eq(ex.reason, 'lifetime');
  near(ex.time - sp.time, 0.9, 1 / 60 + 1e-9);
  near(ex.x, sp.x + 11 * 0.9, 0.2);
  eq(m.projectiles.length, 0);
});

test('projectiles: enemy projectiles clash and cancel out', () => {
  const { m, log } = duel({ s0: [{ t: 0, skill1: true }], s1: [{ t: 0, skill1: true }], x: [-4, 4] });
  run(m, 1.5);
  const c = first(log, 'projectileClash');
  assert(c, 'clash event');
  eq(c.survivor, null);
  eq(events(log, 'projectileExpire', (e) => e.reason === 'clash').length, 2);
  eq(events(log, 'hit').length, 0);
});

test('projectiles: hit-stop freezes only the victim (and the projectile)', () => {
  const { m, log } = duel({ s0: [{ t: 0, skill1: true }], x: [-2, 2] });
  runUntil(m, () => events(log, 'hit').length > 0, 2);
  const h = first(log, 'hit');
  eq(h.kind, 'projectile');
  assert(m.fighters[1].hitstop > 0, 'victim frozen');
  eq(m.fighters[0].hitstop, 0, 'owner keeps acting');
  const t0 = m.fighters[0].moveTime;
  m.step(1 / 60);
  assert(m.fighters[0].moveTime > t0, 'owner timeline runs');
});

// ------------------------------------------------------------------------------------------------ combos

const lab = (moves, extra = {}) => ({
  id: 'lab', name: 'Lab', commands: { light: 'a', heavy: 'b' },
  moves: { b: { duration: 0.3 }, ...moves }, ...extra,
});

test('combo: damage scaling per hit with a 40 % floor; hitstun decays', () => {
  const def = lab({
    a: {
      duration: 2.2,
      hits: [{ t: [0.1, 1.6], box: { f: [0, 2], u: [0, 2] }, damage: 100, level: 'light', hitstun: 1, knockback: { x: 0, y: 0 }, hitstop: 0, multi: { interval: 0.1, max: 10 }, hurtExtend: false }],
    },
  });
  const { m, log } = duel({ s0: [{ t: 0, light: true }], defs: [def, def] });
  const stuns = [];
  let n = 0;
  runUntil(m, () => {
    const k = events(log, 'hit').length;
    if (k > n) { n = k; stuns.push(m.fighters[1].timer); }
    return k >= 10;
  }, 3);
  const dmg = events(log, 'hit').map((h) => h.damage);
  eq(JSON.stringify(dmg), JSON.stringify([100, 100, 90, 80, 70, 60, 50, 40, 40, 40]));
  eq(m.fighters[0].combo.hits, 10);
  eq(m.fighters[0].combo.damage, 670);
  near(stuns[0], 1, 1e-9);
  near(stuns[4], 1 - 0.03 * 4, 1e-9);
  assert(stuns.every((s, i) => i === 0 || s <= stuns[i - 1] + 1e-9), 'hitstun never grows');
});

test('juggle: air hits add juggle points; at the limit the victim falls through every hit', () => {
  const def = lab({
    a: {
      duration: 3,
      hits: [
        { t: [0.1, 0.12], box: { f: [0, 2], u: [0, 2] }, damage: 50, level: 'launch', knockback: { x: 0, y: 9 }, hitstop: 0 },
        { t: [0.2, 1.0], box: { f: [-0.5, 2], u: [0, 5] }, damage: 10, level: 'light', knockback: { x: 0, y: 0 }, hitstop: 0, multi: { interval: 0.08, max: 10 }, hurtExtend: false },
      ],
    },
  });
  const { m, log } = duel({ s0: [{ t: 0, light: true }], defs: [def, def] });
  run(m, 3.2);
  const hits = events(log, 'hit');
  eq(hits.length, m.rules.juggle.limit, 'launch + (limit - 1) air hits');
  const ce = first(log, 'comboEnd');
  near(ce.juggle, m.rules.juggle.limit, 1e-9);
  assert(first(log, 'state', (e) => e.fighter === 1 && e.to === 'knockdown'), 'lands in a knockdown');
});

test('combo: counter hits deal more damage and hit-stop', () => {
  const { m, log } = duel({ s0: [{ t: 0.1, light: true }], s1: [{ t: 0.1, heavy: true, down: true }] }); // jab beats the launcher's startup
  run(m, 0.5);
  const h = first(log, 'hit', (e) => e.attacker === 0);
  eq(h.counter, true);
  eq(h.damage, Math.round(34 * 1.2));
  near(h.hitstop, 0.06 * 1.35, 1e-9);
});

test('corner: the attacker takes the pushback when the victim is pinned to the wall', () => {
  const { m } = duel({ s0: [{ t: 0, light: true }], x: [7.75, 8.6] });
  run(m, 0.6);
  near(m.fighters[1].x, 8.6, 1e-9, 'victim stays at the wall');
  assert(m.fighters[0].x < 7.75 - 0.05, `attacker pushed back (x ${m.fighters[0].x})`);
});

test('corner: a forward dash with the back to the wall rolls through (no corner trap)', () => {
  const { m, log } = duel({ s1: [{ t: 0, dodge: true, move: -1 }], x: [7.75, 8.6] });
  run(m, 0.7);
  eq(first(log, 'dodge').kind, 'roll');
  assert(m.fighters[1].x < m.fighters[0].x, 'P1 escaped to the other side');
});

test('push-boxes: fighters never overlap, the wall holds both', () => {
  const { m } = duel({ s0: [{ t: 0, dur: 3, move: 1 }], s1: [{ t: 0, dur: 3, move: 1 }], x: [6, 7.5] });
  let minGap = Infinity;
  for (let i = 0; i < 180; i++) { m.step(1 / 60); minGap = Math.min(minGap, m.fighters[1].x - m.fighters[0].x); }
  assert(minGap >= 0.8 - 1e-9, `gap ${minGap}`);
  assert(m.fighters[1].x <= 8.6 + 1e-9, 'wall');
});

test('wall bounce: a hard knockback into the wall bounces once and re-opens the juggle', () => {
  const { m, log } = duel({ s0: [{ t: 0, light: true }, { t: 0.07, light: true }, { t: 0.27, light: true }], x: [6.6, 8.2], rules: { wallBounce: { speed: 3 } } });
  run(m, 1.5);
  assert(first(log, 'wallBounce'), 'wallBounce event');
});

test('tech roll: pressing dodge on landing from a juggle rolls away instead of lying down', () => {
  const def = lab({ a: { duration: 0.6, hits: [{ t: [0.1, 0.12], box: { f: [0, 2], u: [0, 2] }, damage: 50, level: 'launch', knockback: { x: 0, y: 6 } }] } });
  const { m, log } = duel({ s0: [{ t: 0, light: true }], s1: [{ t: 0.55, dodge: true }], defs: [def, def] });
  run(m, 1.4);
  assert(first(log, 'tech'), 'tech event');
  eq(events(log, 'state', (e) => e.fighter === 1 && e.to === 'knockdown').length, 0);
});

// ------------------------------------------------------------------------------------------------ meters

test('meters: FP spent at move start, regenerates after the delay; denied when short; cooldowns', () => {
  const { m, log } = duel({ s0: [{ t: 0, skill1: true }, { t: 1.0, skill1: true }], x: [-6, 6] });
  run(m, 0.05);
  eq(m.fighters[0].fp, 75);
  run(m, 0.55);
  near(m.fighters[0].fp, 75, 1e-9, 'no regen during the delay');
  run(m, 0.8);
  assert(m.fighters[0].fp > 75 + 7 * 0.6 && m.fighters[0].fp < 75 + 7 * 0.85, `regen ~7/s (fp ${m.fighters[0].fp})`);
  const d = first(log, 'moveDenied');
  eq(d.reason, 'cooldown');
  const low = duel({ s0: [{ t: 0, skill1: true }], x: [-6, 6] });
  low.m.setMeter(0, 'fp', 10);
  run(low.m, 0.1);
  eq(first(low.log, 'moveDenied').reason, 'fp');
  eq(events(low.log, 'moveStart').length, 0);
});

test('meters: ULT is gained by dealing and taking damage; ultReady fires when full', () => {
  const { m, log } = duel({ s0: [{ t: 0, light: true }] });
  m.setMeter(1, 'ult', 99);
  run(m, 0.4);
  near(m.fighters[0].ult, 34 * m.rules.meters.ultDeal, 1e-9);
  eq(m.fighters[1].ult, 100);
  assert(first(log, 'ultReady', (e) => e.fighter === 1), 'ultReady');
});

test('meters: HUD slots report costs, cooldowns and readiness', () => {
  const { m } = duel({ s0: [{ t: 0, skill1: true }], x: [-6, 6] });
  run(m, 0.1);
  const s = m.slots(0).find((x) => x.key === 'skill1');
  eq(s.move, 'crescent'); eq(s.fpCost, 25); eq(s.ready, false);
  assert(s.cd > 0.9 && s.cd <= 1, 'cooldown fraction');
  eq(m.slots(0).find((x) => x.key === 'ult').ready, false);
});

// ------------------------------------------------------------------------------------------------ ultimate

function ultDuel(opts = {}) {
  const r = duel({ s0: [{ t: 0, ult: true }], x: [-1.5, 1.5], ...opts });
  r.m.setMeter(0, 'ult', 100);
  return r;
}

test('ultimate: super-freeze freezes the opponent and the clock; the user animates', () => {
  const { m, log } = ultDuel({ s1: [{ t: 0, dur: 2, move: 1 }] });
  run(m, 0.05);
  assert(first(log, 'superFreezeStart'), 'superFreezeStart');
  assert(first(log, 'marker', (e) => e.name === 'superFreeze'), 'superFreeze marker');
  eq(m.fighters[0].ult, 0, 'the bar is emptied');
  const x1 = m.fighters[1].x, clock = m.clock, st1 = m.fighters[1].stateTime, mt = m.fighters[0].moveTime;
  run(m, 0.3);
  eq(m.fighters[1].x, x1, 'opponent frozen');
  eq(m.fighters[1].stateTime, st1);
  eq(m.clock, clock, 'clock frozen');
  near(m.fighters[0].moveTime - mt, 0.3, 1e-6, 'user timeline runs');
  run(m, 0.35);
  const e = first(log, 'superFreezeEnd');
  near(e.time - first(log, 'superFreezeStart').time, 0.6, 1 / 60 + 1e-9);
});

test('ultimate: the trigger hit starts the cinematic lock; ticks and finish on schedule', () => {
  const { m, log } = ultDuel();
  runUntil(m, () => !!first(log, 'cinematicStart'), 2);
  const cs = first(log, 'cinematicStart');
  eq(cs.attacker, 0); eq(cs.defender, 1); eq(cs.duration, 4.2);
  eq(first(log, 'hit').cinematic, true);
  eq(m.fighters[1].state, 'locked');
  const clock = m.clock;
  runUntil(m, () => !!first(log, 'cinematicEnd'), 5);
  eq(m.clock, clock, 'clock paused during the lock');
  run(m, 0.3);
  const ticks = events(log, 'cinematicTick');
  eq(JSON.stringify(ticks.map((t) => t.damage)), JSON.stringify([40, 40, 40, 60, 220]));
  near(ticks[0].time - cs.time, 0.3, 1 / 60 + 1e-9);
  eq(ticks[4].final, true);
  const ce = first(log, 'cinematicEnd');
  near(ce.time - cs.time, 4.2, 1 / 60 + 1e-9);
  eq(ce.damage, 400);
  eq(m.fighters[1].hp, 1000 - 80 - 400);
  assert(events(log, 'marker', (e) => e.cinematic && e.name === 'shockwave').length === 1, 'cinematic markers');
  assert(['launched', 'knockdown'].includes(m.fighters[1].state), 'victim released into a knockdown');
  eq(first(log, 'state', (e) => e.fighter === 0 && e.to === 'recovery').fighter, 0);
});

test('ultimate: blocked -> no lock, chip, the move recovers', () => {
  const { m, log } = ultDuel({ s1: [{ t: 0, dur: 3, guard: true }] });
  run(m, 2);
  eq(first(log, 'hit').blocked, true);
  eq(events(log, 'cinematicStart').length, 0);
  eq(first(log, 'moveEnd', (e) => e.move === 'verdict').reason, 'complete');
  eq(m.fighters[1].hp, 1000 - 16, 'ult chip = 20 % of 80');
  eq(m.fighters[0].ult, 0);
});

test('ultimate: whiffed -> no lock, the move recovers', () => {
  const { m, log } = ultDuel({ x: [-6, 4] });
  run(m, 2);
  eq(events(log, 'hit').length, 0);
  eq(events(log, 'cinematicStart').length, 0);
  eq(first(log, 'moveEnd', (e) => e.move === 'verdict').reason, 'complete');
});

test('ultimate: a lethal cinematic KOs at the finish, not before', () => {
  const { m, log } = ultDuel();
  m.setMeter(1, 'hp', 150);
  run(m, 9);
  const ticks = events(log, 'cinematicTick');
  eq(ticks.slice(0, 4).every((t) => t.damage >= 0), true);
  const ko = first(log, 'ko');
  assert(ko && ko.fighter === 1 && ko.cinematic, 'cinematic KO');
  assert(ko.time >= first(log, 'cinematicEnd').time - 1e-9, 'KO at the end of the lock');
  eq(first(log, 'roundEnd').winner, 0);
});

// ------------------------------------------------------------------------------------------------ rounds

test('rounds: KO ends the round; HP / FP reset, ULT carries; first to 2 wins the match', () => {
  const ctl = createScriptedController((t) => ({ light: t > 0.1 && t < 0.15 }));
  const { m, log } = duel({ controllers: [ctl, null], rules: { koTime: 0.5, outroTime: 0.3 } });
  m.setMeter(1, 'hp', 20);
  run(m, 1.2);
  const re = first(log, 'roundEnd');
  eq(re.winner, 0); eq(re.reason, 'ko'); eq(re.matchOver, false);
  eq(m.round, 2);
  eq(m.fighters[1].hp, 1000); eq(m.fighters[0].fp, 100);
  assert(m.fighters[0].ult > 0, 'ULT carried');
  m.place(0, -0.8, 1); m.place(1, 0.8, -1); m.setMeter(1, 'hp', 20);
  run(m, 1.2);
  const me = first(log, 'matchEnd');
  assert(me, 'matchEnd');
  eq(me.winner, 0);
  eq(JSON.stringify(me.rounds), '[2,0]');
  eq(m.phase, 'end');
  eq(m.fighters[0].state, 'victory');
});

test('rounds: time-up goes to the higher HP ratio; equal HP is a draw; a drawn match is possible', () => {
  const { m, log } = duel({ rules: { roundTime: 2, timeUpTime: 0.2, outroTime: 0.2, maxRounds: 2 } });
  m.setMeter(1, 'hp', 600);
  run(m, 2.6);
  const r1 = first(log, 'roundEnd');
  eq(r1.reason, 'time'); eq(r1.winner, 0);
  assert(first(log, 'timeUp'), 'timeUp');
  run(m, 2.6);
  const r2 = events(log, 'roundEnd')[1];
  eq(r2.winner, -1, 'draw');
  const me = first(log, 'matchEnd');
  eq(me.winner, 0, '2-1 after the drawn second round (draws give both a round)');
  const d = duel({ rules: { roundTime: 1, timeUpTime: 0.1, outroTime: 0.1, maxRounds: 2 } });
  run(d.m, 3);
  eq(first(d.log, 'matchEnd').winner, -1, 'match draw');
});

test('reset paths: reset() restarts the match, restartRound() the round', () => {
  const { m } = duel({ s0: [{ t: 0, light: true }] });
  run(m, 0.5);
  m.setMeter(0, 'ult', 50);
  m.restartRound();
  eq(m.round, 1); eq(m.fighters[1].hp, 1000); eq(m.fighters[0].ult, 50);
  m.reset();
  eq(m.fighters[0].ult, 0); eq(m.fighters[0].rounds, 0); eq(m.phase, 'fight');
  const snap = JSON.parse(JSON.stringify(m.snapshot()));
  eq(snap.fighters.length, 2);
});

test('debug boxes: hurt, active hit and push boxes in world space for the hitbox viewer', () => {
  const { m } = duel({ s0: [{ t: 0, light: true }], x: [-3, 3] });
  run(m, 0.12); // light1 active from 0.10 (move started at 1/60)
  const b = m.boxes(0);
  eq(b.hit.length, 1);
  near(b.hit[0][0], -3 + 0.3, 1e-9); near(b.hit[0][1], -3 + 1.75, 1e-9);
  near(b.push[0], -3.4, 1e-9);
  assert(b.hurt.length >= 2, 'body + extended limb');
  eq(m.boxes(1).hit.length, 0);
});

test('markers and moveEvent: timeline markers are emitted at their time with world position', () => {
  const { m, log } = duel({ s0: [{ t: 0, heavy: true }], x: [-5, 5] });
  const viaAlias = [];
  m.on('moveEvent', (p) => viaAlias.push(p.name));
  run(m, 1);
  const ms = first(log, 'moveStart');
  const mk = events(log, 'marker');
  eq(JSON.stringify(mk.map((k) => k.name)), JSON.stringify(['windup', 'swing', 'impact']));
  eq(JSON.stringify(viaAlias), JSON.stringify(['windup', 'swing', 'impact']), "'moveEvent' (contract name) subscribes to markers");
  near(mk[2].time - ms.time, 0.34, 1 / 60 + 1e-9);
  eq(mk[0].data.armour, true);
});

// ------------------------------------------------------------------------------------------------ AI

test('AI: generic over any definition (no ai hints, no skills, no ultimate)', () => {
  const bare = clone(S);
  for (const mv of Object.values(bare.moves)) delete mv.ai;
  delete bare.ai;
  bare.commands = { light: 'light1', heavy: 'heavy', 'd+heavy': 'launcher' };
  for (const id of Object.keys(bare.moves)) if (!['light1', 'light2', 'light3', 'heavy', 'launcher'].includes(id)) delete bare.moves[id];
  bare.moves.light1.cancels = bare.moves.light1.cancels.slice(0, 1);
  bare.moves.light2.cancels = bare.moves.light2.cancels.slice(0, 1);
  bare.moves.light3.cancels = [];
  bare.moves.heavy.cancels = [];
  bare.moves.launcher.cancels = [];
  eq(validateFighterDef(bare).ok, true, validateFighterDef(bare).errors.join('; '));
  for (const lv of ['easy', 'nightmare']) {
    const m = createMatch({ fighters: [bare, S], controllers: [createAIController({ difficulty: lv }), createAIController({ difficulty: 'normal' })], rng: 3 });
    let hits = 0;
    m.on('hit', (e) => { if (e.attacker === 0) hits++; });
    run(m, 60);
    assert(hits > 5, `${lv} AI with a bare definition lands hits (${hits})`);
  }
});

test('AI: reacts to a perceived attack no sooner than its reaction delay', () => {
  const ai = createAIController({ difficulty: 'nightmare', overrides: { guard: 1, dodge: 0, counter: 0, backoff: 0, think: [30, 30] } });
  const { m, log } = duel({ controllers: [createScriptedController([{ t: 1, heavy: true }]), ai], x: [-1, 1] });
  run(m, 1.6);
  const atk = first(log, 'moveStart', (e) => e.fighter === 0 && e.move === 'heavy');
  const g = first(log, 'state', (e) => e.fighter === 1 && e.to === 'guard' && e.time > atk.time);
  assert(g, 'the AI guards');
  assert(g.time - atk.time >= ai.level.reaction - 1e-9, `reaction ${(g.time - atk.time).toFixed(3)} s >= ${ai.level.reaction}`);
  eq(first(log, 'hit').blocked, true, 'and blocks the heavy');
});
