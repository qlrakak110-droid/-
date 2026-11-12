// Minimal test harness (plain Node, no framework) plus helpers to build deterministic duels.

import { createMatch } from '../match.js';
import { createScriptedController } from '../controllers.js';
import { sampleFighter } from '../sample-fighter.js';

const registry = [];

/** Register a test: test('name', () => { ... }) (sync). */
export function test(name, fn, { group = 'unit' } = {}) {
  registry.push({ name, fn, group });
}
export const tests = () => registry;

export class AssertionError extends Error {}

export function assert(cond, msg = 'assertion failed') {
  if (!cond) throw new AssertionError(msg);
}
export function eq(actual, expected, msg = '') {
  if (actual !== expected) throw new AssertionError(`${msg ? msg + ': ' : ''}expected ${fmt(expected)}, got ${fmt(actual)}`);
}
export function near(actual, expected, tol, msg = '') {
  if (!(Math.abs(actual - expected) <= tol)) throw new AssertionError(`${msg ? msg + ': ' : ''}expected ${expected} +- ${tol}, got ${actual}`);
}
export function throws(fn, re, msg = '') {
  try { fn(); } catch (e) {
    if (re && !re.test(String(e.message))) throw new AssertionError(`${msg ? msg + ': ' : ''}error message ${fmt(e.message)} does not match ${re}`);
    return e;
  }
  throw new AssertionError(`${msg ? msg + ': ' : ''}expected an exception`);
}
const fmt = (v) => { try { return JSON.stringify(v); } catch (e) { return String(v); } };

/** Deep clone of a plain-data fighter definition (to derive variants in tests). */
export const clone = (o) => JSON.parse(JSON.stringify(o));

/**
 * A duel with scripted controllers, no intro (the fight starts at t = 0) and fighters placed where asked.
 * @param {object} o
 * @param {object[]} [o.s0] script of fighter 0 (see createScriptedController)
 * @param {object[]} [o.s1] script of fighter 1
 * @param {object} [o.rules] extra rules
 * @param {object[]} [o.defs] fighter definitions (default: the sample fighter twice)
 * @param {number[]} [o.x] start positions [x0, x1] (default [-0.8, 0.8])
 * @returns {{m: object, log: object[]}} the match and the live event log ({ev: event name, ...payload})
 */
export function duel({ s0 = [], s1 = [], rules = {}, defs, x = [-0.8, 0.8], controllers } = {}) {
  const m = createMatch({
    fighters: defs || [sampleFighter, sampleFighter],
    controllers: controllers || [createScriptedController(s0), createScriptedController(s1)],
    rules: { introTime: 0, ...rules },
    rng: 7,
  });
  m.place(0, x[0], x[0] < x[1] ? 1 : -1);
  m.place(1, x[1], x[0] < x[1] ? -1 : 1);
  const log = [];
  m.on('*', (ev, p) => log.push({ ...p, ev }));
  return { m, log };
}

/** Step `m` for `sec` seconds at `dt` (default 1/60). */
export function run(m, sec, dt = 1 / 60) {
  const n = Math.round(sec / dt);
  for (let i = 0; i < n; i++) m.step(dt);
  return m;
}

/** Step until pred(m) is true (or `max` seconds pass). Returns the time waited. */
export function runUntil(m, pred, max = 10, dt = 1 / 60) {
  const t0 = m.time;
  while (!pred(m) && m.time - t0 < max) m.step(dt);
  return m.time - t0;
}

/** Events named `name` in a log (optionally filtered). */
export const events = (log, ev, filter) => log.filter((e) => e.ev === ev && (!filter || filter(e)));
export const first = (log, ev, filter) => events(log, ev, filter)[0];

/** FNV-1a hash of a string (32-bit hex). */
export function hash(s) {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 0x01000193); }
  return (h >>> 0).toString(16).padStart(8, '0');
}

export { sampleFighter };
