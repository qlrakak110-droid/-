// Fighter registry: the roster (menu data) and the loader that turns src/fighters/<id>/ into a playable fighter.
//
//   import { ROSTER, loadRoster } from './fighters/registry.js';
//   const fighters = await loadRoster();          // Map id -> fighter (see src/game/README.md "Fighter content API")
//
// Each fighter is the module src/fighters/<id>/index.js (default export, or named exports) with
//   { id, design, def, clips, present, element? }.
// Anything it does not provide is filled in, in this order:
//   design   index.design  -> src/fighters/<id>/design.js  -> the demo knight tinted by element
//   def      index.def     -> src/fighters/<id>/moves.js   -> the rules sample fighter renamed after MOVES.md
//   clips    index.clips   -> {}  (every state / move falls back to the generic clips, see src/game/clips.js)
//   present  index.present -> {}  (generic feel for every move, generic ultimate cinematic)
// A design or definition that fails (throws, or does not validate) is reported once and replaced by the fallback, so
// the game always runs while the content teams work.
//
// Modules are found with esbuild glob imports (bundled at build time; a missing file is a runtime miss, not a build
// error), so dropping a design.js / moves.js / index.js into src/fighters/<id>/ is enough: rebuild and it is live.

import { validateFighterDef } from '../game/logic/index.js';
import { placeholderDef, tintedKnight } from '../game/placeholder.js';
import { DEFAULT_ROSTER } from '../ui/roster.js';

// The ultimate's world mood (env.setMood) per fighter: 열양 red-gold, 한빙 moon white, 뇌정 violet.
const MOOD = {
  kael: { darken: 0.75, tint: 0xff5020 },
  iska: { darken: 0.8, tint: 0x8fc8ff },
  vorn: { darken: 0.8, tint: 0xa080ff },
};

/**
 * Menu data (src/ui select / vs / result / move list / HUD) of the three heroes of 「흑일무림 黑日武林」:
 *   kael  염무강 炎武剛 · 적염패도 赤焰覇刀 · 적양문 赤陽門 · 참마대도 斬馬大刀 · 열양진기 烈陽眞氣
 *   iska  설리화 雪梨花 · 빙월쌍도 氷月雙刀 · 한월궁 寒月宮 · 월아쌍도 月牙雙刀 · 한빙진기 寒氷眞氣
 *   vorn  뇌진천 雷震天 · 천뢰신창 天雷神槍 · 뇌운보 雷雲堡 · 뇌룡창 雷龍槍   · 뇌정신공 雷霆神功
 * The player-facing names live in one place, src/ui/roster.js (fields: name / hanja / nameEn, title / titleHanja /
 * titleEn, sect / sectHanja / sectEn, weapon / weaponHanja / weaponEn, art / artHanja / artEn, seal, emblem, blurb,
 * stats 1..5, moves [{ slot, name, hanja, nameEn, desc, cost?, cd?, icon? }]); the 초식 table is in MOVES.md.
 * `mood` is the ultimate's world mood (env.setMood).
 */
export const ROSTER = DEFAULT_ROSTER.map((r) => ({ ...r, mood: MOOD[r.id] }));

/** Roster entry by id (falls back to the first entry). */
export function rosterEntry(id) {
  return ROSTER.find((r) => r.id === id) || ROSTER[0];
}

// ---- module discovery (esbuild bundles every match of these globs; a missing file rejects at runtime) -------------
const IMPORTERS = {
  index: (id) => import(`./${id}/index.js`),
  design: (id) => import(`./${id}/design.js`),
  moves: (id) => import(`./${id}/moves.js`),
};

const warned = new Set();
function warn(key, msg) {
  if (warned.has(key)) return;
  warned.add(key);
  console.warn('[ed] fighters: ' + msg);
}

async function tryImport(kind, id) {
  try { return await IMPORTERS[kind](id); } catch (e) {
    if (!/not found in bundle|Cannot find module|Failed to fetch/i.test(String(e && e.message))) warn(kind + id, `${id}/${kind}.js failed to load: ${e && e.message}`);
    return null;
  }
}

/** A module's main object: default export, else the namespace (named exports). */
const mainOf = (mod) => (mod ? (mod.default && typeof mod.default === 'object' ? mod.default : mod) : null);

/** Find a design in a module: default / design / <id> / the first export with a build() function. */
function pickDesign(mod, id) {
  if (!mod) return null;
  const isDesign = (o) => o && typeof o === 'object' && typeof o.build === 'function';
  for (const k of ['default', 'design', id]) if (isDesign(mod[k])) return mod[k];
  for (const v of Object.values(mod)) if (isDesign(v)) return v;
  return null;
}

/** Find a rules definition in a module: default / def / fighter / <id> / the first export with moves + commands. */
function pickDef(mod, id) {
  if (!mod) return null;
  const isDef = (o) => o && typeof o === 'object' && o.moves && o.commands;
  for (const k of ['default', 'def', 'fighter', id]) if (isDef(mod[k])) return mod[k];
  for (const v of Object.values(mod)) if (isDef(v)) return v;
  return null;
}

/**
 * Load one fighter. Never throws: every missing or broken part is replaced by its fallback.
 * @param {string} id
 * @returns {Promise<object>} fighter: { id, roster, element, design, def, clips, present, sources: {design, def}, stub }
 */
export async function loadFighter(id) {
  const roster = rosterEntry(id);
  const element = roster.element;
  const idx = mainOf(await tryImport('index', id)) || {};
  const out = {
    id, roster, element: idx.element || element, stub: !!idx.stub,
    design: null, def: null, clips: idx.clips || {}, present: idx.present || {}, sources: { design: '', def: '' },
  };

  // design
  let design = idx.design && typeof idx.design.build === 'function' ? idx.design : null;
  out.sources.design = design ? 'index' : '';
  if (!design) { design = pickDesign(await tryImport('design', id), id); if (design) out.sources.design = `${id}/design.js`; }
  out.design = design || tintedKnight(out.element);
  if (!design) out.sources.design = 'knight (tinted)';

  // rules definition
  let def = idx.def || null;
  out.sources.def = def ? 'index' : '';
  if (!def) { def = pickDef(await tryImport('moves', id), id); if (def) out.sources.def = `${id}/moves.js`; }
  if (def) {
    let res;
    try { res = validateFighterDef(def); } catch (e) { res = { ok: false, errors: [String(e && e.message)] }; }
    if (!res.ok) {
      warn('def' + id, `${id}: rules definition does not validate, using the placeholder (${res.errors.slice(0, 3).join(' | ')})`);
      def = null;
    }
  }
  out.def = def || placeholderDef(roster);
  if (!def) out.sources.def = 'sample (placeholder)';
  out.fallbackDesign = () => tintedKnight(out.element);
  return out;
}

/**
 * Load every roster fighter.
 * @returns {Promise<Map<string, object>>}
 */
export async function loadRoster() {
  const map = new Map();
  for (const r of ROSTER) map.set(r.id, await loadFighter(r.id));
  return map;
}
