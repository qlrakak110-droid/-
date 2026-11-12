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

/**
 * Menu data (src/ui select / vs / result / move list). Names and numbers follow src/fighters/MOVES.md.
 * stats are 1..5 for the select screen; `mood` is the ultimate's world mood (env.setMood) and `cine` its tint.
 */
export const ROSTER = [
  {
    id: 'kael', name: '카엘', nameEn: 'KAEL', title: '잿불의 집행자', titleEn: 'Cinder Warden',
    weapon: '대검', weaponEn: 'Greatsword', weaponArt: 'greatsword', element: 'ember',
    blurb: '거대한 호를 그리는 느리고 무거운 일격. 강공에 슈퍼아머.', blurbEn: 'Slow, enormous arcs. Armoured heavies.',
    stats: { power: 5, speed: 2, reach: 4, difficulty: 2 },
    mood: { darken: 0.75, tint: 0xff5020 },
    moves: [
      { slot: 'light1', name: '재가르기', nameEn: 'Ash Cleave', desc: '대각선 내려베기' },
      { slot: 'light2', name: '역날베기', nameEn: 'Back Edge', desc: '역방향 올려베기' },
      { slot: 'light3', name: '잿불내려찍기', nameEn: 'Cinder Drop', desc: '바닥을 내려찍어 다운' },
      { slot: 'heavy', name: '용광로 휘두르기', nameEn: 'Furnace Sweep', desc: '300° 회전 베기 · 슈퍼아머' },
      { slot: 'fheavy', name: '돌진 찌르기', nameEn: 'Molten Lunge', desc: '3.2m 돌진 찌르기' },
      { slot: 'dheavy', name: '분화 올려베기', nameEn: 'Vent Launcher', desc: '화염 분출 띄우기' },
      { slot: 'skill1', name: '잿불 초승달', nameEn: 'Ember Crescent', desc: '불타는 초승달 파동 발사', cost: 25, cd: 4, icon: 'kael-crescent' },
      { slot: 'skill2', name: '균열 분출', nameEn: 'Fault Eruption', desc: '전방으로 용암 기둥 4연속 분출', cost: 35, cd: 7, icon: 'kael-eruption' },
      { slot: 'skill3', name: '화염 갑주', nameEn: 'Pyre Bulwark', desc: '받아치기 자세 · 피격 시 폭발 반격', cost: 30, cd: 9, icon: 'kael-bulwark' },
      { slot: 'ult', name: '일식의 장작', nameEn: 'Pyre of the Black Sun', desc: '도약 베기 적중 시 5초 연출 연속기', cost: 100, icon: 'kael-ult' },
    ],
  },
  {
    id: 'iska', name: '이스카', nameEn: 'ISKA', title: '서릿별 무녀', titleEn: 'Froststar Oracle',
    weapon: '쌍월도', weaponEn: 'Twin Crescent Blades', weaponArt: 'crescents', element: 'frost',
    blurb: '빠르고 정교한 연격과 원거리 견제. 공중 기동에 강하다.', blurbEn: 'Fast, precise, airy. Mobility and zoning.',
    stats: { power: 3, speed: 5, reach: 3, difficulty: 4 },
    mood: { darken: 0.8, tint: 0x8fc8ff },
    moves: [
      { slot: 'light1', name: '서리 긋기', nameEn: 'Rime Flick', desc: '빠른 오른손 베기' },
      { slot: 'light2', name: '쌍월', nameEn: 'Twin Moons', desc: '좌우 연속 베기' },
      { slot: 'light3', name: '별부채', nameEn: 'Star Fan', desc: '회전 이연격 · 넉백' },
      { slot: 'heavy', name: '빙결 회전', nameEn: 'Glacier Pirouette', desc: '3연타 회전 베기' },
      { slot: 'fheavy', name: '얼음길', nameEn: 'Frostline Step', desc: '얼음 위를 미끄러지며 베기' },
      { slot: 'dheavy', name: '초승 올려치기', nameEn: 'Rising Crescent', desc: '공중제비 띄우기' },
      { slot: 'skill1', name: '서릿별 투창', nameEn: 'Starshard Volley', desc: '얼음 파편 3연속 발사', cost: 20, cd: 3.5, icon: 'iska-shards' },
      { slot: 'skill2', name: '빙정 행렬', nameEn: 'Crystal Procession', desc: '전방으로 커지는 얼음 가시', cost: 30, cd: 6, icon: 'iska-procession' },
      { slot: 'skill3', name: '월광 잔상', nameEn: 'Moonlit Afterimage', desc: '잔상을 남기고 배후 기습', cost: 25, cd: 7, icon: 'iska-afterimage' },
      { slot: 'ult', name: '떨어지는 서릿별', nameEn: 'Fall of the Frozen Star', desc: '봉인진 적중 시 5초 연출 연속기', cost: 100, icon: 'iska-ult' },
    ],
  },
  {
    id: 'vorn', name: '볼른', nameEn: 'VORN', title: '뇌명의 창기사', titleEn: 'Stormcaller Lancer',
    weapon: '전쟁창', weaponEn: 'War Spear', weaponArt: 'spear', element: 'volt',
    blurb: '가장 긴 사거리와 폭발적인 돌진. 방어 관통 찌르기.', blurbEn: 'Longest reach, explosive dashes.',
    stats: { power: 4, speed: 3, reach: 5, difficulty: 3 },
    mood: { darken: 0.8, tint: 0xa080ff },
    moves: [
      { slot: 'light1', name: '섬광 찌르기', nameEn: 'Flash Jab', desc: '긴 사거리 찌르기' },
      { slot: 'light2', name: '회전 쳐올리기', nameEn: 'Haft Spin', desc: '창대 회전 타격' },
      { slot: 'light3', name: '천둥 꿰기', nameEn: 'Thunder Pierce', desc: '번개 돌진 찌르기 · 넉백' },
      { slot: 'heavy', name: '폭풍 휩쓸기', nameEn: 'Gale Sweep', desc: '하단 휩쓸기 · 다운' },
      { slot: 'fheavy', name: '번개 돌격', nameEn: 'Lightning Charge', desc: '4m 번개 돌진 · 방어 관통' },
      { slot: 'dheavy', name: '하늘 꿰뚫기', nameEn: 'Skyward Lance', desc: '수직 찌르기 띄우기' },
      { slot: 'skill1', name: '뇌창 투척', nameEn: 'Thunder Javelin', desc: '번개 투창 · 기절', cost: 25, cd: 4, icon: 'vorn-javelin' },
      { slot: 'skill2', name: '낙뢰', nameEn: 'Stormfall', desc: '상대 위치에 낙뢰 3연속', cost: 35, cd: 7, icon: 'vorn-stormfall' },
      { slot: 'skill3', name: '섬전 보법', nameEn: 'Arc Step', desc: '번개로 관통 순간이동', cost: 20, cd: 5, icon: 'vorn-arcstep' },
      { slot: 'ult', name: '천벌의 뇌창', nameEn: 'Lance of the Ninefold Storm', desc: '돌진 찌르기 적중 시 5초 연출 연속기', cost: 100, icon: 'vorn-ult' },
    ],
  },
];

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
