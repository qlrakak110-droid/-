// Print the frame-data table (and validation warnings) of a fighter definition.
//
//   node src/game/logic/test/framedata.mjs                                 the sample fighter
//   node src/game/logic/test/framedata.mjs src/fighters/kael/moves.js      any module exporting a definition
//   node src/game/logic/test/framedata.mjs <module> --seconds              times in seconds instead of frames

import path from 'node:path';
import url from 'node:url';
import { frameDataTable } from '../framedata.js';
import { validateFighterDef } from '../defs.js';
import { sampleFighter } from '../sample-fighter.js';

const args = process.argv.slice(2);
const file = args.find((a) => !a.startsWith('--'));
let def = sampleFighter;
if (file) {
  const mod = await import(url.pathToFileURL(path.resolve(file)).href);
  def = mod.default && mod.default.moves ? mod.default : Object.values(mod).find((v) => v && typeof v === 'object' && v.moves);
  if (!def) { console.error(`${file}: no export with a 'moves' field`); process.exit(1); }
}
const v = validateFighterDef(def);
if (!v.ok) {
  console.error(`INVALID (${v.errors.length} errors):\n  - ${v.errors.join('\n  - ')}`);
  process.exit(1);
}
console.log(frameDataTable(def, { unit: args.includes('--seconds') ? 'seconds' : 'frames' }));
if (v.warnings.length) console.log(`\nwarnings:\n  - ${v.warnings.join('\n  - ')}`);
