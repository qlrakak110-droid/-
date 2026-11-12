// KAEL 카엘 — motion library. Importing this module registers every kael.* clip and pose (src/char README section 5).
// Clip list for the choreographer: NAMES.md. KAEL_CLIPS is the state / move map for the fighter module.

import './common.js';
import { LOCOMOTION } from './locomotion.js';
import { MOVES, MOVE_HITS } from './moves.js';

/** Every clip this library registers. */
export const KAEL_CLIP_NAMES = [...LOCOMOTION, ...MOVES];

/** State / move id -> clip map for `src/fighters/kael/index.js` (`clips: KAEL_CLIPS`). */
export const KAEL_CLIPS = {
  idle: 'kael.idle', recovery: 'kael.idle', walkF: 'kael.walkF', walkB: 'kael.walkB',
  dash: 'kael.dash', backstep: 'kael.backstep', dodge: 'kael.dodge', guard: 'kael.guard',
  bulwark: 'kael.bulwark',
};
for (const id in MOVE_HITS) KAEL_CLIPS[id] = { clip: 'kael.' + id, hit: MOVE_HITS[id] };
