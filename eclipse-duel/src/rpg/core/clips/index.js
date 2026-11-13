// rpg.<hero>.* clips: the motion the expedition needs on top of the fighters' own sets. Importing this module
// registers them:
//   rpg.<hero>.run / .sprint            ./locomotion.js  (root speed = the hero's run / sprint speed, planted feet)
//   rpg.<hero>.roll / .drink / .death / .rest            ./actions.js
// <hero> = kael | iska | vorn. Flinch / stagger / knockdown / getup reuse the fighters' own hit clips and the generic
// game.* set (src/game/clips.js); the guard walk reuses the fighters' stance walks.
import './locomotion.js';
import './actions.js';

/** Every clip registered here (per hero). */
export const RPG_CLIPS = ['run', 'sprint', 'roll', 'drink', 'death', 'rest'];
