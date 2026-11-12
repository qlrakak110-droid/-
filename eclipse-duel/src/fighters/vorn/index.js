// VORN 볼른 — 뇌명의 창기사 · Stormcaller Lancer. The fighter module (src/game/README.md "Fighter content API"):
// design (./design.js), rules definition (./moves.js), clips (./clips: the animator's vorn.* library, NAMES.md) and the
// skill choreography (./present.js, signature effects in ./fx.js).

import design from './design.js';
import { def } from './moves.js';
import './clips/index.js';
import { getClipDef } from '../../char/anim.js';
import { present } from './present.js';

/** State slot -> clip name (NAMES.md "State clips"). */
const STATES = {
  intro: 'vorn.intro', idle: 'vorn.idle', recovery: 'vorn.idle', walkF: 'vorn.walkF', walkB: 'vorn.walkB',
  dash: 'vorn.dash', backstep: 'vorn.backstep', dodge: 'vorn.dodge', roll: 'vorn.dodge', guard: 'vorn.guard',
  guardBreak: 'vorn.guardBreak', hitLight: 'vorn.hitLight', hitHeavy: 'vorn.hitHeavy', crumple: 'vorn.crumple',
  launched: 'vorn.launched', fall: 'vorn.fall', down: 'vorn.down', getup: 'vorn.getup', tech: 'vorn.tech', ko: 'vorn.ko',
  locked: 'vorn.locked', victory: 'vorn.victory', defeat: 'vorn.defeat',
};

/** First `impact` / `hit` event time of a registered clip (the retiming anchor), null when it has none. */
function impactOf(name) {
  const d = getClipDef(name);
  if (!d || !d.events) return null;
  let t = null;
  for (const e of d.events) if ((e.name === 'impact' || e.name === 'hit') && (t === null || e.t < t)) t = e.t;
  return t;
}

/** First active instant of a move: its first hit window, else its first projectile (spawn + delay). */
function firstActive(mv) {
  let t = null;
  for (const h of mv.hits || []) if (t === null || h.t[0] < t) t = h.t[0];
  if (t !== null) return t;
  for (const p of mv.projectiles || []) { const a = p.t + (p.delay || 0); if (t === null || a < t) t = a; }
  return t;
}

/**
 * Presentation slot / move id -> clip, only for clips the animator has registered (anything missing falls back to the
 * generic clips). Move clips are `vorn.<move id>`, authored 1:1 on the move clock with an `impact` event on the first
 * active frame: mapped as { clip, hit } so they stay locked to the frame data even if a move is retuned. A clip whose
 * impact marks something else (Arc Step: the blink, before the trailing detonation) plays 1:1.
 */
function clips({ hasClip }) {
  const map = {};
  for (const slot in STATES) if (hasClip(STATES[slot])) map[slot] = STATES[slot];
  for (const id in def.moves) {
    const name = 'vorn.' + id;
    if (!hasClip(name)) continue;
    const hit = impactOf(name), act = firstActive(def.moves[id]);
    map[id] = hit !== null && act !== null && Math.abs(hit - act) < 0.02 ? { clip: name, hit } : name;
  }
  return map;
}

export default { id: 'vorn', element: 'volt', design, def, clips, present };
