// ISKA 이스카 — her motion library. Importing this file registers every iska.* clip (src/char clip registry) and
// exports `clips`, the presentation slot / move id -> clip map for src/fighters/iska/index.js (src/game README 3.2).
// Clip names and the ultimate's lock-beat clips are listed in NAMES.md.

import './common.js';
import './locomotion.js';
import './moves.js';
import './ult.js';
import './ceremony.js';

/** State / move -> clip map (move clips carry `hit` = clip time of the first impact, retimed onto the frame data). */
export const clips = {
  idle: 'iska.idle', recovery: 'iska.idle',
  walkF: 'iska.walkF', walkB: 'iska.walkB',
  dash: 'iska.dash', backstep: 'iska.backstep', dodge: 'iska.dodge', roll: 'iska.roll',
  guard: 'iska.guard',
  hitLight: 'iska.hitLight', hitHeavy: 'iska.hitHeavy', crumple: 'iska.crumple', guardBreak: 'iska.guardBreak', getup: 'iska.getup', tech: 'iska.getup',
  launched: 'iska.launched', fall: 'iska.fall', down: 'iska.down', ko: 'iska.ko',
  intro: 'iska.intro', victory: 'iska.victory', defeat: 'iska.defeat',
  rime_flick: { clip: 'iska.rime_flick', hit: 0.09 },
  twin_moons: { clip: 'iska.twin_moons', hit: 0.1 },
  star_fan: { clip: 'iska.star_fan', hit: 0.16 },
  glacier_pirouette: { clip: 'iska.glacier_pirouette', hit: 0.22 },
  frostline_step: { clip: 'iska.frostline_step', hit: 0.18 },
  rising_crescent: { clip: 'iska.rising_crescent', hit: 0.16 },
  starshard_volley: { clip: 'iska.starshard_volley', hit: 0.18 },
  crystal_procession: { clip: 'iska.crystal_procession', hit: 0.25 },
  moonlit_afterimage: { clip: 'iska.moonlit_afterimage', hit: 0.3 },
  frozen_star: { clip: 'iska.frozen_star', hit: 0.75 },
};

export default clips;
