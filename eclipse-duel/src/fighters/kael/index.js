// KAEL 카엘 — 잿불의 집행자 · Cinder Warden: the fighter module (src/game/README.md "Fighter content API").
//   design   ./design.js   armour, greatsword, cloth (src/char "Design format")
//   def      ./moves.js    rules definition (frame data, markers, the ultimate lock clock)
//   clips    kael.* clips registered by ./clips/index.js (NAMES.md), mapped below only when they exist
//   present  ./present.js  choreography of every move, projectiles, the ultimate (fx: ./fx.js)

import { kael as design } from './design.js';
import { def } from './moves.js';
import './clips/index.js';
import { present } from './present.js';
import { getClipDef } from '../../char/anim.js';

/** State slot -> clip (NAMES.md); a slot whose clip is not registered falls back to the generic clip. */
const STATES = {
  intro: 'kael.intro', idle: 'kael.idle', recovery: 'kael.idle', walkF: 'kael.walkF', walkB: 'kael.walkB',
  dash: 'kael.dash', backstep: 'kael.backstep', dodge: 'kael.dodge', guard: 'kael.guard',
  hitLight: 'kael.hitLight', hitHeavy: 'kael.hitHeavy', victory: 'kael.victory', defeat: 'kael.defeat',
};
/** Move id -> clip (authored on the move clock; `hit` = the clip's impact event, retimed onto the first active frame). */
const MOVES = {
  light1: 'kael.light1', light2: 'kael.light2', light3: 'kael.light3', sweep: 'kael.sweep', lunge: 'kael.lunge',
  vent: 'kael.vent', crescent: 'kael.crescent', eruption: 'kael.eruption', bulwark: 'kael.bulwark',
  bulwark_burst: 'kael.bulwark_burst', pyre: 'kael.pyre',
};

/** First `impact` / `hit` event time of a registered clip (null when it has none). */
function impactOf(name) {
  const d = getClipDef(name);
  if (!d || !d.events) return null;
  let t = null;
  for (const e of d.events) if ((e.name === 'impact' || e.name === 'hit') && (t === null || e.t < t)) t = e.t;
  return t;
}

/**
 * The state / move -> clip map, built once per actor when the clips are registered: only names the animator has
 * registered are mapped (everything else keeps the generic fallback), strikes as { clip, hit } entries.
 * @param {{ hasClip: (name: string) => boolean }} api
 */
function clips({ hasClip }) {
  const map = {};
  for (const [slot, name] of Object.entries(STATES)) if (hasClip(name)) map[slot] = name;
  for (const [id, name] of Object.entries(MOVES)) {
    if (!hasClip(name)) continue;
    const hit = impactOf(name);
    map[id] = hit === null ? name : { clip: name, hit };
  }
  return map;
}

export default { id: 'kael', element: 'ember', design, def, clips, present };
