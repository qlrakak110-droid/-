// Test runner of the rules engine: plain Node (>= 22), no framework.
//
//   node src/game/logic/test/run.mjs                 unit + determinism tests, then the 300-match AI soak
//   node src/game/logic/test/run.mjs --quick         skip the soak
//   node src/game/logic/test/run.mjs --soak 60       soak with 60 matches
//   node src/game/logic/test/run.mjs --only guard    run tests whose name contains "guard" (no soak)
//
// Exit code 1 when anything fails.

import { tests } from './harness.mjs';
import './unit.test.mjs';
import './determinism.test.mjs';
import { runSoak } from './soak.mjs';

const args = process.argv.slice(2);
const flag = (name) => args.includes(name);
const value = (name, def) => { const i = args.indexOf(name); return i >= 0 && args[i + 1] !== undefined ? args[i + 1] : def; };
const only = value('--only', null);

let pass = 0, fail = 0;
const t0 = Date.now();
for (const t of tests()) {
  if (only && !t.name.includes(only)) continue;
  const s = Date.now();
  try {
    t.fn();
    pass++;
    console.log(`  ok    ${t.name}  (${Date.now() - s} ms)`);
  } catch (e) {
    fail++;
    console.log(`  FAIL  ${t.name}\n        ${String(e && e.stack || e).split('\n').slice(0, 6).join('\n        ')}`);
  }
}
console.log(`\n${pass} passed, ${fail} failed (${((Date.now() - t0) / 1000).toFixed(2)} s)`);

if (!only && !flag('--quick')) {
  const n = Number(value('--soak', 300));
  const res = runSoak({ matches: n, log: console.log });
  if (!res.ok) fail++;
}
process.exit(fail ? 1 : 0);
