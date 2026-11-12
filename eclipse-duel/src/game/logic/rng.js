// Deterministic random streams for the rules engine. The engine itself never rolls dice; only controllers (the AI)
// do, each on its own stream forked from the match seed so adding a consumer never shifts another one.

import { makeRng } from '../../core/math.js';

/**
 * Turn a seed or an rng function into an rng function with the `makeRng` helpers.
 * @param {number|Function|undefined} r  seed (integer) or `rng()` returning [0,1)
 * @returns {Function} rng
 */
export function toRng(r) {
  if (typeof r === 'function') {
    if (typeof r.range === 'function') return r;
    // wrap a bare function so callers can rely on the helpers
    const w = () => r();
    w.range = (a, b) => a + (b - a) * r();
    w.int = (a, b) => Math.floor(a + (b - a + 1) * r());
    w.pick = (arr) => arr[Math.floor(r() * arr.length) % arr.length];
    w.chance = (p) => r() < p;
    return w;
  }
  return makeRng(typeof r === 'number' && Number.isFinite(r) ? r : 20261112);
}

/** A new independent stream seeded from `rng` (consumes one value of it). */
export function forkRng(rng) {
  return makeRng(Math.floor(rng() * 4294967296));
}

export { makeRng };
