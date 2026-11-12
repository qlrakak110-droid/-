// Adversarial edge cases: trades, frame-exact windows, cancels vs hits, buffering through freezes, simultaneous
// ultimates, cinematic vs clock / projectiles, corners and side switches, lying bodies, dt equivalence, extreme data.

import { test, assert, eq, near, clone, duel, run, runUntil, events, first, sampleFighter as S } from './harness.mjs';
import { createMatch } from '../match.js';
import { validateFighterDef } from '../defs.js';
import { createIdleController, createScriptedController } from '../controllers.js';

/** Minimal definitions: light -> a, heavy -> b (+ extra commands). */
const lab = (moves, commands = {}) => ({
  id: 'lab', name: 'Lab', commands: { light: 'a', heavy: 'b', ...commands },
  moves: { b: { duration: 0.3 }, ...moves },
});
const BOX = { f: [0, 2], u: [0, 2] };

// ------------------------------------------------------------------------------------------------ authoring

test('validate: authoring traps are caught (unpayable costs, free ults, hidden counters, sign slips, late ticks)', () => {
  const d = clone(S);
  d.stats.weight = 0.05;
  d.moves.crescent.fpCost = 150;
  delete d.moves.verdict.ultCost;
  d.moves.ward.invuln = [[0, 0.3]];
  d.moves.light1.hits[0].box.f = [-1.75, -0.3];
  d.moves.heavy.hits[0].cinematic = true;
  d.moves.blink.requires = { minDistance: 5, maxDistance: 4 };
  d.moves.verdict.cinematic.ticks.push({ t: 3.5, damage: 10 });
  const r = validateFighterDef(d);
  const has = (list, s) => assert(list.some((e) => e.includes(s)), `missing "${s}" in:\n  ${list.join('\n  ')}`);
  has(r.errors, 'def.stats.weight: must be >= 0.2');
  has(r.errors, 'moves.crescent.fpCost: 150 can never be paid (stats.fpMax is 100)');
  has(r.errors, "moves.heavy.hits[0].cinematic: a cinematic trigger needs the move's `cinematic` block");
  has(r.errors, 'moves.blink.requires: minDistance 5 > maxDistance 4');
  has(r.warnings, 'moves.verdict.ultCost: an ultimate (superFreeze / cinematic) without an ultCost is free to spam');
  has(r.warnings, 'moves.ward.counter.t: overlaps invuln[0]');
  has(r.warnings, 'moves.light1.hits[0].box.f: [-1.75,-0.3] only reaches behind the fighter');
  has(r.warnings, 'moves.verdict.cinematic.ticks[4].t: 3.5 s comes after the finish');
});

test('validate: [from, to] shorthand for invuln / armour / passThrough windows', () => {
  const d = clone(S);
  d.moves.ward_burst.invuln = [[0, 0.3]];
  d.moves.heavy.armour = [[0.08, 0.34]];
  const r = validateFighterDef(d);
  eq(r.ok, true, r.errors.join('; '));
  eq(r.warnings.length, 0, r.warnings.join('; '));
  const { m, log } = duel({ defs: [d, d], s0: [{ t: 0, heavy: true }], s1: [{ t: 0.04, light: true }] });
  run(m, 0.8);
  assert(first(log, 'hit', (e) => e.defender === 0).armoured, 'shorthand armour absorbs');
  eq(m.defs[0].moves.ward_burst.invuln[0].vs, 'all');
});

// ------------------------------------------------------------------------------------------------ trades

test('trade: simultaneous jabs both land (both counter hits, both stunned, both frozen)', () => {
  const { m, log } = duel({ s0: [{ t: 0, light: true }], s1: [{ t: 0, light: true }] });
  runUntil(m, () => events(log, 'hit').length >= 2, 1);
  const [h0, h1] = events(log, 'hit');
  eq(h0.time, h1.time, 'same substep');
  eq(h0.attacker + h1.attacker, 1, 'one each way');
  assert(h0.counter && h1.counter, 'both caught in their startup: counter hits');
  eq(m.fighters[0].state, 'hitstun'); eq(m.fighters[1].state, 'hitstun');
  assert(m.fighters[0].hitstop > 0 && m.fighters[1].hitstop > 0, 'both frozen');
  eq(m.fighters[0].hp, m.fighters[1].hp, 'symmetric damage');
  eq(events(log, 'moveEnd', (e) => e.reason === 'interrupted').length, 2, 'both moves interrupted');
});

test('trade: both KO on the same step -> double KO, drawn round, a round point each', () => {
  const { m, log } = duel({ s0: [{ t: 0, light: true }], s1: [{ t: 0, light: true }], rules: { koTime: 0.3, outroTime: 0.2 } });
  m.setMeter(0, 'hp', 10); m.setMeter(1, 'hp', 10);
  run(m, 1.5);
  const kos = events(log, 'ko');
  eq(kos.length, 2); eq(kos[0].time, kos[1].time, 'same step');
  assert(events(log, 'hit').every((h) => h.ko), 'both hits flagged as kills');
  const re = first(log, 'roundEnd');
  eq(re.winner, -1); eq(re.reason, 'doubleKo');
  eq(JSON.stringify(re.rounds), '[1,1]');
});

test('trade: simultaneous ultimates both start under one shared freeze; simultaneous triggers clash (no lock)', () => {
  const { m, log } = duel({ s0: [{ t: 0, ult: true }], s1: [{ t: 0, ult: true }], x: [-1.5, 1.5] });
  m.setMeter(0, 'ult', 100); m.setMeter(1, 'ult', 100);
  run(m, 0.05);
  eq(events(log, 'superFreezeStart').length, 2, 'both ultimates start (no side priority)');
  eq(events(log, 'moveDenied').length, 0);
  assert(first(log, 'superFreezeStart', (e) => e.fighter === 1).simultaneous, 'flagged simultaneous');
  eq(JSON.stringify(m.freeze.owners), '[0,1]');
  run(m, 2.5);
  eq(events(log, 'superFreezeEnd').length, 2);
  eq(events(log, 'cinematicStart').length, 0, 'clash: neither lock starts');
  const hs = events(log, 'hit', (h) => h.move === 'verdict');
  eq(hs.length, 2); assert(hs.every((h) => h.clash && !h.cinematic), 'both resolve as ordinary clashing hits');
  eq(m.fighters[0].hp, m.fighters[1].hp);
  eq(m.fighters[0].ult + m.fighters[1].ult < 50, true, 'both bars spent');
});

test('ultimate: the user\'s timeline advances by exactly the freeze duration during the freeze, at any dt', () => {
  for (const dt of [1 / 30, 1 / 60, 1 / 144]) {
    const { m, log } = duel({ s0: [{ t: 0, ult: true }], x: [-4, 4] });
    m.setMeter(0, 'ult', 100);
    let atEnd = null;
    m.on('superFreezeEnd', () => { atEnd = m.fighters[0].moveTime; });
    runUntil(m, () => atEnd !== null, 2, dt);
    // the freeze ends inside a step; the rest of that step runs normally
    assert(atEnd >= 0.6 - 1e-6 && atEnd <= 0.6 + dt + 1e-6, `dt ${dt.toFixed(4)}: user clock ${atEnd} at the freeze end`);
  }
});

test('ultimate: an ultimate pressed a step after the opponent\'s is frozen out (the press expires in the freeze)', () => {
  const { m, log } = duel({ s0: [{ t: 0, ult: true }], s1: [{ t: 1 / 60 + 1e-6, ult: true }], x: [-1.5, 1.5] });
  m.setMeter(0, 'ult', 100); m.setMeter(1, 'ult', 100);
  run(m, 1.2);
  eq(events(log, 'superFreezeStart').length, 1);
  eq(events(log, 'moveStart', (e) => e.fighter === 1).length, 0);
  eq(m.canUse(1, 'verdict'), null, 'the bar is still there for later');
});

// ------------------------------------------------------------------------------------------------ frame-exact windows

test('windows: a hit on the last active frame lands (box comes into range only on that frame)', () => {
  const def = lab({ a: { duration: 0.5, motion: { keys: [[0, 0], [0.19, 0], [0.2, 0.3], [0.5, 0.3]] }, hits: [{ t: [0.1, 0.2], box: { f: [0, 1.0], u: [0, 2] }, damage: 50 }] } });
  const { m, log } = duel({ s0: [{ t: 0, light: true }], defs: [def, def] });
  run(m, 0.6);
  const h = first(log, 'hit');
  assert(h, 'the last active frame connects');
  const ms = first(log, 'moveStart');
  near(h.time - ms.time, 0.2, 1e-6, 'on the last active frame');
});

test('windows: a hit window ending at the move end still connects; the move then ends', () => {
  const def = lab({ a: { duration: 0.3, hits: [{ t: [0.3, 0.3], box: BOX, damage: 50 }] } });
  const { m, log } = duel({ s0: [{ t: 0, light: true }], defs: [def, def] });
  run(m, 0.6);
  eq(events(log, 'hit').length, 1);
  eq(first(log, 'moveEnd').reason, 'complete');
  eq(m.fighters[0].state, 'idle');
});

test('windows: zero-length windows (at t = 0, mid-move, at the end) each strike exactly once, at any dt', () => {
  for (const dt of [1 / 30, 1 / 60, 1 / 120, 1 / 144]) {
    for (const t of [0, 0.1, 0.25]) {
      const def = lab({ a: { duration: 0.25, hits: [{ t: [t, t], box: BOX, damage: 50, hitstop: 0 }] } });
      const { m, log } = duel({ s0: [{ t: 0, light: true }], defs: [def, def] });
      run(m, 0.6, dt);
      eq(events(log, 'hit').length, 1, `window [${t}, ${t}] at dt ${dt.toFixed(4)}`);
    }
  }
});

test('windows: markers at t = 0 and t = duration are emitted exactly once', () => {
  const def = lab({ a: { duration: 0.2, markers: [{ t: 0, name: 'start' }, { t: 0.2, name: 'end' }] } });
  const { m, log } = duel({ s0: [{ t: 0, light: true }], defs: [def, def] });
  run(m, 0.5);
  eq(JSON.stringify(events(log, 'marker').map((k) => k.name)), '["start","end"]');
});

// ------------------------------------------------------------------------------------------------ cancels and buffering

test('cancel on the same frame as the hit: the hit lands first, the cancel comes out after the hit-stop', () => {
  const def = lab({ a: { duration: 0.5, hits: [{ t: [0.1, 0.1], box: BOX, damage: 50, hitstop: 0.1 }], cancels: [{ t: [0.1, 0.4], on: 'heavy', into: 'b' }] } });
  const { m, log } = duel({ s0: [{ t: 0, light: true }, { t: 0.05, heavy: true }], defs: [def, def] });
  run(m, 0.6);
  const h = first(log, 'hit');
  assert(h, 'the active frame is not swallowed by the cancel');
  const b = first(log, 'moveStart', (e) => e.move === 'b');
  assert(b && b.cancelFrom === 'a', 'the route is taken');
  assert(b.time >= h.time + 0.1 - 1e-6, 'after the hit-stop');
});

test('cancel on a whiff still comes out on the first frame of the window', () => {
  const def = lab({ a: { duration: 0.5, hits: [{ t: [0.1, 0.1], box: BOX, damage: 50 }], cancels: [{ t: [0.1, 0.4], on: 'heavy', into: 'b' }] } });
  const { m, log } = duel({ s0: [{ t: 0, light: true }, { t: 0.05, heavy: true }], defs: [def, def], x: [-4, 4] });
  run(m, 0.6);
  const a = first(log, 'moveStart', (e) => e.move === 'a'), b = first(log, 'moveStart', (e) => e.move === 'b');
  near(b.time - a.time, 0.1, 1e-6);
});

test('buffer: a press during a long hit-stop (longer than the buffer) still comes out when the freeze ends', () => {
  const def = lab({ a: { duration: 0.6, hits: [{ t: [0.1, 0.12], box: BOX, damage: 50, hitstop: 0.35 }], cancels: [{ t: [0.12, 0.5], on: 'heavy', into: 'b', onHit: true }] } });
  const { m, log } = duel({ s0: [{ t: 0, light: true }, { t: 0.13, heavy: true }], defs: [def, def] });
  run(m, 0.8);
  const h = first(log, 'hit');
  assert(h.time < 0.13, 'pressed during the hit-stop');
  const b = first(log, 'moveStart', (e) => e.move === 'b');
  assert(b && b.cancelFrom === 'a', 'the cancel comes out');
  assert(b.time >= h.time + 0.35 - 1e-6, 'after the freeze');
});

test('buffer: the victim of a super-freeze can buffer a dodge late in the freeze, but early presses expire', () => {
  const late = duel({ s0: [{ t: 0, ult: true }], s1: [{ t: 0.5, dodge: true }], x: [-1.5, 1.5] });
  late.m.setMeter(0, 'ult', 100);
  run(late.m, 1);
  const fe = first(late.log, 'superFreezeEnd');
  const d = first(late.log, 'dodge', (e) => e.fighter === 1);
  assert(d && d.time >= fe.time - 1e-9 && d.time <= fe.time + 1 / 30, 'comes out as the freeze ends');
  const early = duel({ s0: [{ t: 0, ult: true }], s1: [{ t: 0.1, dodge: true }], x: [-1.5, 1.5] });
  early.m.setMeter(0, 'ult', 100);
  run(early.m, 1);
  eq(events(early.log, 'dodge', (e) => e.fighter === 1).length, 0, 'no mashing through the freeze');
});

test('dodge: getting hit in the recovery after the invulnerable window is a punish; the cooldown still applies', () => {
  const { m, log } = duel({ s0: [{ t: 0.2, light: true }], s1: [{ t: 0, dodge: true }, { t: 0.9, dodge: true }] });
  run(m, 1.2);
  const h = first(log, 'hit');
  assert(h && h.defender === 1 && h.punish && !h.counter, 'punished in the dodge recovery');
  eq(events(log, 'dodge', (e) => e.fighter === 1).length, 1, 'no second dodge: the cooldown started with the dodge');
  const c = duel({ s0: [{ t: 0, dodge: true }, { t: 0.32, light: true }, { t: 0.75, dodge: true }], x: [-4, 4] });
  run(c.m, 1);
  eq(events(c.log, 'dodge').length, 1, 'cancelling the dodge into an attack does not skip the cooldown');
});

test('guard: released during blockstun the stun runs its course (still blocking), then the fighter is open', () => {
  const hit = (t) => ({ t: [t, t], box: BOX, damage: 40, blockstun: 0.25, hitstop: 0.02, knockback: { x: 0, y: 0 } });
  const def = lab({ a: { duration: 1.2, hits: [hit(0.1), hit(0.3), hit(0.8)] } }); // the third hit leaves a gap
  // guard pressed long before the first hit (no perfect guard), released right after it
  const { m, log } = duel({ s0: [{ t: 0.1, light: true }], s1: [{ t: 0, dur: 0.25, guard: true }], defs: [def, def] });
  run(m, 1.5);
  const hs = events(log, 'hit');
  assert(!hs[0].perfect && hs[0].blocked && hs[1].blocked, 'blockstun keeps blocking the string after release');
  assert(hs.slice(2).some((h) => !h.blocked), 'once the stun ends without guard held, hits land');
  const bs = first(log, 'state', (e) => e.fighter === 1 && e.from === 'blockstun');
  eq(bs.to, 'idle', 'back to idle, not guard');
});

// ------------------------------------------------------------------------------------------------ cinematic

const caster = (() => {
  const d = clone(S);
  d.id = 'caster';
  d.moves.snare = {
    duration: 0.2, fpCost: 10,
    projectiles: [{ t: 0.05, at: 'opponent', box: { f: [-0.7, 0.7], u: [0, 2] }, delay: 0.5, lifetime: 6, multi: { interval: 0.3, max: 20 }, pierce: true, clash: false, hit: { damage: 5, level: 'light', hitstop: 0.02 } }],
    cancels: [{ t: [0.06, 0.2], into: ['@ult'] }],
  };
  d.commands.skill1 = 'snare';
  return d;
})();

test('cinematic: the owner\'s projectiles freeze during its lock and never hit the locked victim', () => {
  const { m, log } = duel({ defs: [caster, S], s0: [{ t: 0, skill1: true }, { t: 0.12, ult: true }], x: [-1.5, 1.5] });
  m.setMeter(0, 'ult', 100);
  let ageStart = null, ageEnd = null;
  m.on('cinematicStart', () => { ageStart = m.projectiles[0] && m.projectiles[0].age; });
  m.on('cinematicEnd', () => { ageEnd = m.projectiles[0] && m.projectiles[0].age; });
  run(m, 7);
  const cs = first(log, 'cinematicStart'), ce = first(log, 'cinematicEnd');
  assert(cs && ce, 'the ultimate locks');
  eq(events(log, 'hit', (h) => h.kind === 'projectile' && h.time > cs.time && h.time <= ce.time).length, 0, 'no projectile hit during the lock');
  assert(ageStart !== null && ageStart === ageEnd, `projectile frozen (age ${ageStart} -> ${ageEnd})`);
});

test('cinematic: the round clock pauses through the lock; time-up comes after it (or never, on a lethal lock)', () => {
  const t = duel({ s0: [{ t: 0, ult: true }], x: [-1.5, 1.5], rules: { roundTime: 1.3 } });
  t.m.setMeter(0, 'ult', 100);
  run(t.m, 8);
  const cs = first(t.log, 'cinematicStart'), ce = first(t.log, 'cinematicEnd'), tu = first(t.log, 'timeUp');
  assert(cs && ce && tu, 'lock then time-up');
  assert(tu.time > ce.time, 'time-up waits for the lock');
  // the fight began at t = 0; the clock also stood still through the 0.6 s super-freeze
  near(tu.time - ce.time, 1.3 - (cs.time - 0.6), 1 / 30, 'the clock resumed where it stopped');
  const k = duel({ s0: [{ t: 0, ult: true }], x: [-1.5, 1.5], rules: { roundTime: 1.3 } });
  k.m.setMeter(0, 'ult', 100); k.m.setMeter(1, 'hp', 200);
  run(k.m, 8);
  eq(first(k.log, 'roundEnd').reason, 'ko', 'a lethal lock wins by KO even though the clock had run down');
  eq(events(k.log, 'timeUp').length, 0);
});

test('cinematic: a lock distance shorter than the push-boxes still releases the pair apart', () => {
  const d = clone(S);
  d.moves.verdict.cinematic.distance = 0;
  const { m, log } = duel({ defs: [d, d], s0: [{ t: 0, ult: true }], x: [-1.5, 1.5] });
  m.setMeter(0, 'ult', 100);
  runUntil(m, () => !!first(log, 'cinematicEnd'), 8);
  m.step(1 / 60);
  assert(Math.abs(m.fighters[1].x - m.fighters[0].x) >= 0.8 - 1e-6, 'separated on release');
});

// ------------------------------------------------------------------------------------------------ space

test('corner: a pass-through puts the attacker between the wall and the opponent; pushback then pushes it out', () => {
  const { m, log } = duel({ s0: [{ t: 0, skill3: true, move: 1 }, { t: 0.32, light: true }], s1: [{ t: 0.9, light: true }], x: [5.6, 7.5] });
  run(m, 0.55);
  assert(m.fighters[0].x > m.fighters[1].x, 'crossed into the corner');
  const l = first(log, 'moveStart', (e) => e.fighter === 0 && e.move === 'light1');
  eq(l.facing, -1, 'the follow-up turns around');
  run(m, 1.0);
  eq(m.fighters[1].facing, 1, 'the victim turned to face the attacker in the corner');
  const back = first(log, 'hit', (e) => e.attacker === 1);
  assert(back, 'the cornered side answers');
  assert(m.fighters[0].x <= 9 - 0.4 + 1e-9 && m.fighters[1].x < m.fighters[0].x - 0.8 + 1e-6, 'walls hold; push-boxes hold');
});

test('corner: the wall-pinned victim\'s pushback moves the attacker, never through the wall', () => {
  const { m } = duel({ s0: [{ t: 0, light: true }, { t: 0.15, light: true }, { t: 0.4, light: true }], x: [7.75, 8.6] });
  let minGap = Infinity;
  for (let i = 0; i < 90; i++) {
    m.step(1 / 60);
    for (const f of m.fighters) assert(Math.abs(f.x) <= 8.6 + 1e-9, 'inside the walls');
    if (m.fighters[1].y < 0.05 && m.fighters[1].state !== 'knockdown') minGap = Math.min(minGap, m.fighters[1].x - m.fighters[0].x);
  }
  assert(minGap >= 0.8 - 1e-6, `never overlapping (${minGap})`);
});

test('space: no speed tunnels through a solid opponent; pass-through windows still cross', () => {
  const jump = lab({ a: { duration: 0.5, motion: { keys: [[0, 0], [0.1, 0], [0.1167, 3], [0.5, 3]] } }, b: { duration: 0.5, motion: [{ t: [0, 0.3], v: 40 }] } });
  for (const btn of ['light', 'heavy']) {
    const { m } = duel({ s0: [{ t: 0, [btn]: true }], defs: [jump, jump], x: [-1, 0.5] });
    run(m, 0.6);
    assert(m.fighters[0].x < m.fighters[1].x - 0.8 + 1e-6, `${btn}: stays on its side (${m.fighters[0].x.toFixed(2)} vs ${m.fighters[1].x.toFixed(2)})`);
  }
  const pass = clone(jump);
  pass.moves.a.passThrough = [[0, 0.5]];
  const { m } = duel({ s0: [{ t: 0, light: true }], defs: [pass, pass], x: [-1, 0.5] });
  run(m, 0.6);
  assert(m.fighters[0].x > m.fighters[1].x, 'with passThrough it crosses');
});

test('space: a standing fighter steps over a knocked-down opponent; at get-up they separate and face each other', () => {
  // launcher, then dash forward the moment the victim hits the floor
  const ctl = createScriptedController((t, v) => {
    const down = v.opponent.state === 'knockdown';
    return { heavy: t < 0.05, down: t < 0.05, move: down ? 1 : 0, dodge: down && v.opponent.stateTime < 0.05 };
  });
  const { m, log } = duel({ controllers: [ctl, null], x: [-1, 0.6] });
  runUntil(m, () => m.fighters[1].state === 'knockdown', 3);
  const lyingX = m.fighters[1].x;
  runUntil(m, () => m.fighters[1].state !== 'knockdown', 3);
  // walking at 2.5 m/s into a solid body would shove it ~1.7 m over the 0.7 s knockdown; it only finishes its slide
  near(m.fighters[1].x, lyingX, 0.25, 'the lying body is not shoved along the floor');
  assert(first(log, 'state', (e) => e.fighter === 1 && e.to === 'getup'), 'gets up');
  run(m, 1.2);
  const [a, b] = m.fighters;
  assert(a.x > b.x, 'the attacker crossed over the body');
  assert(Math.abs(a.x - b.x) >= 0.8 - 1e-6, 'push-boxes separate them after get-up');
  eq(b.facing, 1, 'the riser faces the attacker on its other side');
});

// ------------------------------------------------------------------------------------------------ physics caps

test('physics: launch height is capped (rules.juggle.apex x victim height) whatever the knockback / weight', () => {
  const def = lab({ a: { duration: 0.4, hits: [{ t: [0.1, 0.12], box: BOX, damage: 10, level: 'launch', knockback: { x: 0, y: 30 } }] } });
  const light = clone(def); light.stats = { weight: 0.3 };
  const { m } = duel({ s0: [{ t: 0, light: true }], defs: [def, light] });
  let apex = 0;
  for (let i = 0; i < 240; i++) { m.step(1 / 60); apex = Math.max(apex, m.fighters[1].y); }
  assert(apex <= m.rules.juggle.apex * 1.85 + 0.05, `apex ${apex.toFixed(2)} m`);
  assert(apex > 2 * 1.85, 'still a big launch');
});

test('physics: the combo cap counts hit-stop (long hit-stops cannot stretch a combo past rules.combo.maxTime)', () => {
  const def = lab({ a: { duration: 0.6, hits: [{ t: [0.05, 0.5], box: BOX, damage: 1, level: 'light', hitstun: 0.6, hitstop: 0.5, knockback: { x: 0, y: 0 }, multi: { interval: 0.05, max: 10 } }], cancels: [{ t: [0.5, 0.6], on: 'light', into: 'a' }] } });
  const ctl = createScriptedController((t) => ({ light: Math.floor(t * 30) % 2 === 0 }));
  const { m, log } = duel({ controllers: [ctl, createIdleController()], defs: [def, def], rules: { combo: { maxTime: 3 } } });
  run(m, 12);
  const ce = first(log, 'comboEnd');
  assert(ce, 'the combo ends');
  assert(ce.duration < 3 + 2.5, `ended soon after the cap (${ce.duration.toFixed(2)} s)`);
  assert(events(log, 'hit').some((h) => h.level === 'knockdown'), 'converted into a knockdown');
});

test('physics: a wall bounce in the substep that reaches the floor never leaves the body below it', () => {
  const def = lab({ a: { duration: 0.4, hits: [{ t: [0.1, 0.12], box: BOX, damage: 10, level: 'launch', knockback: { x: 12, y: 1.5 } }] } });
  const { m } = duel({ s0: [{ t: 0, light: true }], defs: [def, def], x: [7.2, 8.2], rules: { wallBounce: { speed: 1, pop: 6 } } });
  for (let i = 0; i < 120; i++) { m.step(1 / 60); assert(m.fighters[1].y >= 0, `y ${m.fighters[1].y}`); }
});

test('projectiles: a strike anchored at the opponent rises from the floor by default (its box u is floor-relative)', () => {
  const { m, log } = duel({ s0: [{ t: 0, skill1: true, move: -1 }], x: [-3, 3] });
  run(m, 0.4);
  eq(first(log, 'projectileSpawn').y, 0, 'grave pillar spawns on the floor');
  near(m.boxes(0).projectiles[0].box[2], 0, 1e-9, 'its box starts at the floor');
  const def = lab({ a: { duration: 0.3, projectiles: [{ t: 0.05, box: { f: [-0.2, 0.2], u: [-0.2, 0.2] }, velocity: { x: 8, y: 0 }, lifetime: 1, hit: { damage: 10 } }] } });
  const shot = duel({ s0: [{ t: 0, light: true }], defs: [def, def], x: [-6, 6] });
  run(shot.m, 0.4);
  near(first(shot.log, 'projectileSpawn').y, 1.85 * 0.65, 1e-9, 'a shot without an offset still leaves from the chest');
});

test('projectiles: a hit by the projectile counts for the move that fired it (onHit cancels work on a fireball)', () => {
  const def = lab({
    a: {
      duration: 0.8,
      projectiles: [{ t: 0.05, box: { f: [-0.3, 0.3], u: [0, 2] }, velocity: { x: 10, y: 0 }, lifetime: 1, hit: { damage: 20, level: 'heavy', hitstun: 0.6 } }],
      cancels: [{ t: [0.1, 0.8], on: 'heavy', into: 'b', onHit: true }],
    },
  });
  const { m, log } = duel({ s0: [{ t: 0, light: true }, { t: 0.3, dur: 0.3, heavy: true }], defs: [def, def], x: [-2, 1] });
  run(m, 1);
  assert(first(log, 'hit', (h) => h.kind === 'projectile'), 'the shot lands');
  const b = first(log, 'moveStart', (e) => e.move === 'b');
  assert(b && b.cancelFrom === 'a', 'the on-hit cancel is taken');
});

// ------------------------------------------------------------------------------------------------ payloads

test('payloads: armour and chip kills carry ko: true; hits report reaction, front and facings', () => {
  const a = duel({ s0: [{ t: 0, heavy: true }], s1: [{ t: 0.04, light: true }] });
  a.m.setMeter(0, 'hp', 10);
  run(a.m, 0.8);
  const ah = first(a.log, 'hit', (e) => e.defender === 0);
  assert(ah.armoured && ah.ko, 'armoured kill flagged');
  const c = duel({ s0: [{ t: 0, skill1: true }], s1: [{ t: 0, dur: 3, guard: true }], x: [-1.5, 1.5], rules: { block: { chipCanKO: true } } });
  c.m.setMeter(1, 'hp', 5);
  run(c.m, 1.2);
  const ch = first(c.log, 'hit');
  assert(ch.blocked && ch.ko, 'chip kill flagged');
  const n = duel({ s0: [{ t: 0, light: true }] });
  run(n.m, 0.3);
  const h = first(n.log, 'hit');
  eq(h.reaction, 'hitstun'); eq(h.front, true); eq(h.facing, 1); eq(h.defenderFacing, -1);
  const back = duel({ s0: [{ t: 0.1, light: true }], rules: { turnDelay: 100 } });
  back.m.place(1, 0.8, 1);
  run(back.m, 0.5);
  eq(first(back.log, 'hit').front, false, 'hit from behind');
});

test('payloads: marker / projectile data cannot be mutated through events (definitions stay intact)', () => {
  const { m, log } = duel({ s0: [{ t: 0, light: true }] });
  m.on('marker', (e) => { try { if (e.data) e.data.trail = 'hacked'; } catch (err) { /* frozen */ } });
  run(m, 0.3);
  eq(S.moves.light1.markers[0].data.trail, 'light');
  eq(first(log, 'marker').data.trail, 'light');
});

test('round reset: every state change is announced (victory / ko -> intro at the next round)', () => {
  const ctl = createScriptedController((t) => ({ light: t > 0.1 && t < 0.15 }));
  const { m, log } = duel({ controllers: [ctl, null], rules: { koTime: 0.5, outroTime: 0.3 } });
  m.setMeter(1, 'hp', 20);
  run(m, 1.5);
  const last = [null, null];
  for (const e of events(log, 'state')) { if (last[e.fighter] !== null) eq(e.from, last[e.fighter], 'state chain'); last[e.fighter] = e.to; }
  assert(first(log, 'state', (e) => e.to === 'intro'), 'intro announced');
});

// ------------------------------------------------------------------------------------------------ time

test('dt: 1/30, 1/60 and 1/120 give the same hits, damage and levels; positions within 5 cm', () => {
  const s0 = [{ t: 0, light: true }, { t: 0.15, light: true }, { t: 0.4, light: true }];
  const s1 = [{ t: 1.6, skill1: true }];
  const res = [1 / 30, 1 / 60, 1 / 120].map((dt) => {
    const { m, log } = duel({ s0, s1, x: [-1.2, 0.8] });
    run(m, 3, dt);
    return { hp: m.fighters.map((f) => f.hp), seq: events(log, 'hit').map((h) => `${h.move}:${h.level}:${h.damage}`).join(','), x: m.fighters.map((f) => f.x) };
  });
  for (const r of res.slice(1)) {
    eq(r.seq, res[0].seq, 'same hit sequence');
    eq(JSON.stringify(r.hp), JSON.stringify(res[0].hp), 'same HP');
    for (let i = 0; i < 2; i++) near(r.x[i], res[0].x[i], 0.05, 'same place');
  }
});

test('long idle: a whole match of nobody pressing anything ends in time-ups and a drawn match, quietly', () => {
  const m = createMatch({ fighters: [S, S], controllers: [createIdleController(), createIdleController()], rng: 1 });
  const names = new Set();
  m.on('*', (n) => names.add(n));
  let t = 0;
  while (m.phase !== 'end' && t < 2000) { m.step(1 / 60); t += 1 / 60; }
  eq(m.phase, 'end'); eq(m.winner, -1);
  eq(JSON.stringify(m.fighters.map((f) => f.rounds)), '[5,5]');
  for (const f of m.fighters) { eq(f.hp, f.hpMax); eq(f.fp, f.fpMax); }
  const allowed = new Set(['roundStart', 'phase', 'fightStart', 'state', 'timeUp', 'roundEnd', 'matchEnd']);
  for (const n of names) assert(allowed.has(n), `unexpected event '${n}' in an idle match`);
});

// ------------------------------------------------------------------------------------------------ extreme data

test('extreme data: tiny moves, self-cancel loops and t = 0 teleports run without errors or stuck states', () => {
  const def = lab({
    a: { duration: 0.001, hits: [{ t: [0, 0.001], box: BOX, damage: 1, hitstop: 0 }], cancels: [{ t: [0, 0.001], on: 'light', into: 'a' }] },
    b: { duration: 0.3, teleport: [{ t: 0, to: 'behind', distance: 0 }, { t: 0.3, to: 'forward', distance: 18 }], armour: [{ t: [0, 0] }], invuln: [{ t: [0.3, 0.3] }] },
  });
  const mash = createScriptedController((t) => ({ light: Math.floor(t * 60) % 2 === 0, heavy: Math.floor(t * 7) % 2 === 0 }));
  const { m } = duel({ controllers: [mash, mash], defs: [def, def] });
  for (let i = 0; i < 600; i++) {
    m.step(1 / 60);
    for (const f of m.fighters) assert(Number.isFinite(f.x) && Math.abs(f.x) <= 9, 'finite, inside');
  }
  assert(m.fighters.some((f) => f.hp < f.hpMax), 'the micro-jabs land');
});
