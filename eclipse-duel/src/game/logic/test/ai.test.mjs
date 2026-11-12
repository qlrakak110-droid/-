// AI behaviour tests: every level defines every field the AI reads, counter stances are read and punished,
// mobility moves are followed up, the levels are ordered in activity, nobody stands still for long or loops one move.

import fs from 'node:fs';
import url from 'node:url';
import { test, assert, eq, clone, duel, run, events, sampleFighter as S } from './harness.mjs';
import { createMatch } from '../match.js';
import { createAIController, AI_LEVELS } from '../ai.js';
import { createScriptedController, createIdleController } from '../controllers.js';
import { validateFighterDef } from '../defs.js';
import { authoredFighter } from './fixtures.mjs';

test('AI: every level defines every tuning field the AI reads (no silently undefined probability)', () => {
  const src = fs.readFileSync(url.fileURLToPath(new URL('../ai.js', import.meta.url)), 'utf8');
  const used = new Set((src.match(/\blv\.[a-zA-Z]+/g) || []).map((s) => s.slice(3)));
  assert(used.size > 20, 'found the level fields');
  for (const [name, lv] of Object.entries(AI_LEVELS)) {
    for (const k of used) assert(k in lv, `${name} is missing '${k}'`);
    for (const k of Object.keys(lv)) assert(used.has(k), `${name}.${k} is never read`);
  }
});

/** A stance spammer vs a nightmare AI: share of stances that catch an attack, and stance recoveries punished. */
function stanceDuel(read) {
  const stance = createScriptedController((t) => ({ skill3: Math.floor(t * 30) % 2 === 0 }));
  const ai = createAIController({ difficulty: 'nightmare', overrides: { read, counter: 0, dodge: 0 } });
  const { m, log } = duel({ controllers: [ai, stance], rules: { meters: { fpRegen: 100 }, roundTime: 99 }, x: [-1, 1] });
  m.defs[1].moves.ward.cooldown = 0;
  run(m, 60);
  const wards = events(log, 'moveStart', (e) => e.fighter === 1 && e.move === 'ward').length;
  const caught = events(log, 'counter').length;
  const punished = events(log, 'hit', (h) => h.attacker === 0 && h.punish).length;
  return { wards, rate: caught / Math.max(1, wards), punished };
}

test('AI: reads counter stances (holds its attacks, then punishes the stance recovery)', () => {
  const blind = stanceDuel(0), reader = stanceDuel(1);
  assert(blind.wards > 10 && reader.wards > 10, `stances thrown (${blind.wards}, ${reader.wards})`);
  assert(reader.rate < blind.rate * 0.6, `attacks into the stance: reader ${(reader.rate * 100).toFixed(0)}% vs blind ${(blind.rate * 100).toFixed(0)}% of stances`);
  assert(reader.punished > 0, 'punishes the recovery');
});

test('AI: a mobility move (dash-through) is followed by an attack', () => {
  const d = clone(S);
  d.moves.phase_step.ai.weight = 20; // make the AI pick it often
  let steps = 0, follows = 0;
  for (const seed of [11, 12, 13]) {
    const m = createMatch({ fighters: [d, S], controllers: [createAIController({ difficulty: 'nightmare' }), createIdleController()], rules: { introTime: 0 }, rng: seed });
    m.on('moveStart', (e) => { if (e.fighter === 0 && e.move === 'phase_step') steps++; if (e.fighter === 0 && e.cancelFrom === 'phase_step') follows++; });
    run(m, 90);
  }
  assert(steps >= 6, `uses Phase Step (${steps})`);
  assert(follows >= steps * 0.5, `follows it up (${follows} of ${steps})`);
});

/** Moves per minute, longest standing-still stretch and longest run of one neutral move of `level` vs a guard-mashing dummy. */
function profile(level, seed = 3) {
  const dummy = createScriptedController((t) => ({ guard: Math.floor(t * 1.3) % 3 !== 0, move: Math.floor(t * 0.7) % 4 === 0 ? -1 : 0 }));
  const m = createMatch({ fighters: [S, S], controllers: [createAIController({ difficulty: level }), dummy], rules: { introTime: 0, roundTime: 60 }, rng: seed });
  let moves = 0, idleSince = null, longestIdle = 0, last = null, streak = 0, longestStreak = 0, fight = 0;
  m.on('moveStart', (e) => {
    if (e.fighter !== 0) return;
    moves++;
    if (e.cancelFrom) return;
    streak = e.move === last ? streak + 1 : 1;
    last = e.move;
    longestStreak = Math.max(longestStreak, streak);
  });
  while (m.phase !== 'end' && m.time < 200) {
    m.step(1 / 60);
    if (m.phase !== 'fight') { idleSince = null; continue; }
    fight += 1 / 60;
    const f = m.fighters[0];
    if (f.state === 'idle') { if (idleSince === null) idleSince = m.time; longestIdle = Math.max(longestIdle, m.time - idleSince); } else idleSince = null;
  }
  return { mpm: moves / (fight / 60), longestIdle, longestStreak };
}

test('AI: easy is the most passive, nightmare the busiest; none stands still for long or loops one move', () => {
  const p = Object.fromEntries(['easy', 'normal', 'hard', 'nightmare'].map((l) => [l, profile(l)]));
  assert(p.easy.mpm < p.normal.mpm && p.normal.mpm < p.nightmare.mpm, `activity ordered: ${Object.entries(p).map(([k, v]) => `${k} ${v.mpm.toFixed(0)}`).join(', ')}`);
  for (const [k, v] of Object.entries(p)) {
    assert(v.longestIdle < 2.5, `${k} stood still ${v.longestIdle.toFixed(2)} s`);
    assert(v.longestStreak <= 6, `${k} repeated one move ${v.longestStreak} times`);
  }
  eq(p.nightmare.longestStreak <= p.easy.longestStreak + 1, true, 'the strong levels vary their moves at least as much');
});

test('AI: def.ai.preferredRange shifts where it plays footsies', () => {
  const at = (range) => {
    const d = clone(S);
    d.ai.preferredRange = range;
    const dummy = createScriptedController((t) => ({ guard: Math.floor(t * 2) % 3 === 0 }));
    let near = 0, n = 0;
    for (const seed of [21, 22]) {
      const m = createMatch({ fighters: [d, S], controllers: [createAIController({ difficulty: 'nightmare', overrides: { tempo: 0.2 } }), dummy], rules: { introTime: 0 }, rng: seed });
      for (let i = 0; i < 60 * 40; i++) {
        m.step(1 / 60);
        if (m.fighters[0].state === 'idle' || m.fighters[0].state === 'walk') { n++; if (Math.abs(m.fighters[0].x - m.fighters[1].x) < 2.2) near++; }
      }
    }
    return near / n;
  };
  const close = at(1.2), far = at(3.2);
  assert(far < close, `keeps its distance with a long preferred range (close-range share ${far.toFixed(2)} vs ${close.toFixed(2)})`);
});

test('AI: a fighter written from the README with no ai hints validates clean and every move gets used', () => {
  const v = validateFighterDef(authoredFighter);
  eq(v.ok, true, v.errors.join('; '));
  eq(v.warnings.length, 0, v.warnings.join('; '));
  const used = new Set();
  for (const seed of [2, 3, 4]) {
    const m = createMatch({ fighters: [authoredFighter, authoredFighter], controllers: [createAIController({ difficulty: 'hard' }), createAIController({ difficulty: 'normal' })], rng: seed });
    m.on('moveStart', (e) => used.add(e.move));
    while (m.phase !== 'end' && m.time < 600) m.step(1 / 60);
  }
  const unused = Object.keys(authoredFighter.moves).filter((id) => !used.has(id));
  eq(unused.length, 0, `never used: ${unused.join(', ')}`);
});
