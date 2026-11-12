// Placeholder content so every roster fighter is playable before its real files exist:
//   tintedKnight(element)  the demo knight design recoloured for an element (cape, tabard, plume, glow, plate tint)
//   placeholderDef(roster) the rules sample fighter, renamed after MOVES.md and lightly re-tuned per fighter
// src/fighters/registry.js uses these when src/fighters/<id>/design.js / moves.js are missing or broken.

import { knight } from '../char/designs/knight.js';
import { sampleFighter } from './logic/index.js';

/** Recolour tables per element: cloth outer / lining, plume, glow hue (normalised), plate multiplier. */
const TINTS = {
  ember: { cape: [0x5e0d13, 0x1c0d0d], tabard: [0x4f0b10, 0x170a0a], plume: 0x5a0c10, glow: [1, 0.3, 0.064], plate: 0xffffff },
  frost: { cape: [0x1b4469, 0x0b1624], tabard: [0x163a5a, 0x0a121c], plume: 0xa9c6de, glow: [0.19, 0.5, 1], plate: 0xe2ecff },
  volt: { cape: [0x33185c, 0x120a1e], tabard: [0x2a1249, 0x0e0818], plume: 0x2a1450, glow: [0.56, 0.39, 1], plate: 0xd9d3ea },
};
const PLUME_HEX = 0x5a0c10;
const cache = new Map();

/**
 * The demo knight recoloured for an element. The knight's own build() runs through a kit proxy that re-hues every
 * emissive glow and the plume; cloth and the plate tint are design data.
 * @param {'ember'|'frost'|'volt'} element
 * @returns {object} design (cached per element)
 */
export function tintedKnight(element = 'ember') {
  if (cache.has(element)) return cache.get(element);
  const T = TINTS[element] || TINTS.ember;
  const reglow = (g) => {
    if (typeof g === 'function') return (...a) => reglow(g(...a));
    if (!Array.isArray(g)) return g;
    const m = Math.max(g[0], g[1], g[2]);
    return [T.glow[0] * m, T.glow[1] * m, T.glow[2] * m];
  };
  const fix = (o) => {
    if (!o || typeof o !== 'object') return o;
    let r = o;
    if (o.glow !== undefined) r = { ...r, glow: reglow(o.glow) };
    if (o.color === PLUME_HEX) r = { ...r, color: T.plume };
    return r;
  };
  const wrapKit = (kit) => {
    const k = Object.create(kit);
    k.add = (slot, bone, geo, opts) => kit.add(slot, bone, geo, fix(opts));
    k.addPair = (slot, base, geo, opts) => kit.addPair(slot, base, geo, fix(opts));
    k.addBlend = (slot, frame, geo, w, opts) => kit.addBlend(slot, frame, geo, w, fix(opts));
    k.addSkinned = (slot, geo, fn, opts) => kit.addSkinned(slot, geo, fn, fix(opts));
    k.loft = (slot, spec, opts) => kit.loft(slot, spec, fix(opts));
    k.loftPair = (slot, spec, opts) => kit.loftPair(slot, spec, fix(opts));
    return k;
  };
  const cloth = (knight.cloth || []).map((c) => {
    const col = c.name === 'cape' ? T.cape : T.tabard;
    const s = c.surface || {};
    return { ...c, surface: { ...s, outer: { ...(s.outer || {}), color: col[0] }, inner: { ...(s.inner || {}), color: col[1] } } };
  });
  const design = {
    ...knight,
    id: 'knight-' + element,
    cloth,
    materials: { ...knight.materials, plate: { ...knight.materials.plate, color: T.plate } },
    build(kit, S, rig) { return knight.build(wrapKit(kit), S, rig); },
  };
  cache.set(element, design);
  return design;
}

/** Sample move id per MOVES.md slot (the sample's extra moves are dropped). */
const SLOT_MOVE = {
  light1: 'light1', light2: 'light2', light3: 'light3', heavy: 'heavy', fheavy: 'lunge', dheavy: 'launcher',
  skill1: 'crescent', skill2: 'tempest', skill3: 'ward', ult: 'verdict',
};
/** Light per-fighter re-tuning so the placeholders feel different (stats only; moves stay the sample's). */
const TUNING = {
  kael: { hp: 1050, walkSpeed: 2.2, backSpeed: 1.6, weight: 1.15, aggression: 0.6, zoning: 0.35 },
  iska: { hp: 950, walkSpeed: 2.8, backSpeed: 2.1, weight: 0.9, aggression: 0.5, zoning: 0.6 },
  vorn: { hp: 1000, walkSpeed: 2.5, backSpeed: 1.85, weight: 1, aggression: 0.55, zoning: 0.45 },
};

/**
 * The rules sample fighter as a stand-in for a roster fighter: id, names from MOVES.md, light stat tuning.
 * @param {object} roster roster entry (registry ROSTER)
 * @returns {object} author-format rules definition (validates)
 */
export function placeholderDef(roster) {
  const s = JSON.parse(JSON.stringify(sampleFighter));
  const tune = TUNING[roster.id] || {};
  s.id = roster.id;
  s.name = `${roster.name} · ${roster.nameEn}`;
  s.title = `${roster.title} (placeholder)`;
  s.stats = { ...s.stats, hp: tune.hp ?? s.stats.hp, walkSpeed: tune.walkSpeed ?? s.stats.walkSpeed, backSpeed: tune.backSpeed ?? s.stats.backSpeed, weight: tune.weight ?? s.stats.weight };
  s.ai = { ...s.ai, aggression: tune.aggression ?? 0.55, zoning: tune.zoning ?? 0.45 };
  // keep the MOVES.md command layout only
  for (const k of ['b+skill1', 'f+skill3', 'b+skill3']) delete s.commands[k];
  for (const id of ['grave', 'phase_step', 'blink']) delete s.moves[id];
  for (const m of roster.moves) {
    const id = SLOT_MOVE[m.slot];
    if (id && s.moves[id]) s.moves[id].name = `${m.name} · ${m.nameEn}`;
  }
  if (s.moves.ward_burst) s.moves.ward_burst.name = `${s.moves.ward.name} — 반격`;
  s.meta = { placeholder: true, element: roster.element };
  return s;
}
