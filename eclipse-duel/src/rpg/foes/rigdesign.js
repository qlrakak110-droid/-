// The cultists' rig and under-body (the husk), without the Blender asset:
//   node tools/blender/export_rig.mjs cult --design src/rpg/foes/rigdesign.js#cultRig --no-poses
import { huskDesign } from '../core/kinds.js';
export const cultBase = (id, elite) => huskDesign(id, elite ? 0x8a6f5c : 0x5d5560, elite ? [3.4, 0.5, 0.2] : [2.4, 0.5, 0.25]);
export const cultRig = cultBase('rpg-cult', false);
