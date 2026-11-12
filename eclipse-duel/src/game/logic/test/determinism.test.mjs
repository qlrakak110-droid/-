// Determinism: the same seed and inputs must give the same event log (hashed), whatever else runs alongside.

import { test, assert, eq, hash, sampleFighter as S } from './harness.mjs';
import { createMatch } from '../match.js';
import { createAIController } from '../ai.js';
import { makeRng } from '../rng.js';

function aiMatch(seed, levels = ['hard', 'normal']) {
  const m = createMatch({
    fighters: [S, S],
    controllers: levels.map((difficulty) => createAIController({ difficulty })),
    rng: seed,
  });
  const parts = [];
  m.on('*', (name, p) => parts.push(name + JSON.stringify(p)));
  return { m, digest: () => hash(parts.join('\n')), count: () => parts.length };
}

function runAll(x, sec, dtOf) {
  let t = 0, i = 0;
  while (t < sec && x.m.phase !== 'end') { const dt = dtOf(i++); x.m.step(dt); t += dt; }
}

test('determinism: same seed and inputs -> identical event-log hash and state', () => {
  const a = aiMatch(42), b = aiMatch(42), c = aiMatch(43);
  runAll(a, 60, () => 1 / 60);
  runAll(b, 60, () => 1 / 60);
  runAll(c, 60, () => 1 / 60);
  assert(a.count() > 500, `a busy log (${a.count()} events)`);
  eq(a.digest(), b.digest(), 'same seed');
  eq(JSON.stringify(a.m.snapshot()), JSON.stringify(b.m.snapshot()));
  assert(a.digest() !== c.digest(), 'a different seed plays a different fight');
});

test('determinism: two matches stepped interleaved equal two matches run alone (no shared state)', () => {
  const solo = aiMatch(7, ['nightmare', 'easy']);
  runAll(solo, 40, () => 1 / 60);
  const x = aiMatch(7, ['nightmare', 'easy']), y = aiMatch(8, ['normal', 'normal']);
  for (let i = 0; i < 40 * 60 && x.m.phase !== 'end'; i++) { x.m.step(1 / 60); y.m.step(1 / 60); }
  eq(x.digest(), solo.digest());
});

test('determinism: variable dt (1/144 .. 1/30, jittered, and 0.1 s spikes) stays sane and reproducible', () => {
  const jitter = (seed) => { const r = makeRng(seed); return (i) => (i % 97 === 50 ? 0.1 : 1 / 144 + r() * (1 / 30 - 1 / 144)); };
  const a = aiMatch(5), b = aiMatch(5);
  runAll(a, 45, jitter(1));
  runAll(b, 45, jitter(1));
  eq(a.digest(), b.digest());
  for (const f of a.m.fighters) for (const k of ['x', 'y', 'vx', 'vy', 'hp', 'fp', 'ult', 'guard']) assert(Number.isFinite(f[k]), `${k} finite`);
  assert(a.m.time > 40, 'the match advanced');
});
