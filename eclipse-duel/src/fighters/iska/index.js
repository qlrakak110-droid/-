// ISKA 이스카 — 서릿별 무녀 · Froststar Oracle. The fighter module (src/game/README.md §3.1):
//   design    ./design.js   character (armour, cloth, twin crescents, glow channels)
//   def       ./moves.js    rules definition (frame data, markers, the ultimate's lock clock)
//   clips     ./clips/      her motion library (registered on import; names in clips/NAMES.md)
//   present   ./present.js  choreography (VFX, camera, audio, the ultimate's shot table); effects in ./fxlib.js

import { iska as design } from './design.js';
import { def } from './moves.js';
import './clips/index.js';
import { getClipDef } from '../../char/anim.js';
import { present } from './present.js';

/** presentation slot -> clip name (registered by ./clips when authored; missing ones fall back to the generic clips) */
const STATES = {
  idle: 'iska.idle', recovery: 'iska.idle',
  walkF: 'iska.walkF', walkB: 'iska.walkB',
  dash: 'iska.dash', backstep: 'iska.backstep', dodge: 'iska.dodge', roll: 'iska.roll',
  guard: 'iska.guard', guardBreak: 'iska.guardBreak',
  hitLight: 'iska.hitLight', hitHeavy: 'iska.hitHeavy', crumple: 'iska.crumple',
  launched: 'iska.launched', fall: 'iska.fall', down: 'iska.down', getup: 'iska.getup', tech: 'iska.getup', ko: 'iska.ko',
  locked: 'iska.locked', intro: 'iska.intro', victory: 'iska.victory', defeat: 'iska.defeat',
};

/** Clip time of a clip's first impact (`impact` / `hit` event), or null. */
function impactOf(name) {
  const d = getClipDef(name);
  if (!d || !Array.isArray(d.events)) return null;
  let t = null;
  for (const e of d.events) if ((e.name === 'impact' || e.name === 'hit') && (t === null || e.t < t)) t = e.t;
  return t;
}

/**
 * State / move -> clip map, built once by the clip resolver (src/game/clips.js) after every clip registered.
 * Moves map to `iska.<move id>`; strikes carry `hit` (the clip's impact event) so they retime onto the frame data.
 * Only clips that exist are mapped (the animator registers them as they are authored).
 * @param {{ hasClip: (name: string) => boolean }} api
 */
export function clips({ hasClip }) {
  const map = {};
  for (const slot in STATES) if (hasClip(STATES[slot])) map[slot] = STATES[slot];
  for (const id in def.moves) {
    const name = 'iska.' + id;
    if (!hasClip(name)) continue;
    // strikes: the impact pose lands on the first active frame whatever the frame data says; projectile skills are
    // authored 1:1 on the move clock (their impact event is the cast, not a hit)
    const strike = Array.isArray(def.moves[id].hits) && def.moves[id].hits.length > 0;
    const hit = strike ? impactOf(name) : null;
    map[id] = hit === null ? name : { clip: name, hit };
  }
  return map;
}

export default { id: 'iska', element: 'frost', design, def, clips, present };
