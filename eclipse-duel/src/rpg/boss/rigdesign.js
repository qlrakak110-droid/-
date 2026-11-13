// The idol's rig and under-body, without the sculpted asset: what tools/blender/export_rig.mjs exports to
// tools/blender/rigs/idol.json (the Blender script models on these joints) and what design.js builds on.
//   node tools/blender/export_rig.mjs idol --design src/rpg/boss/rigdesign.js#idolRig --no-poses

import { huskDesign } from '../core/kinds.js';

export const SABER = { hilt: 0.4, length: 1.62, tip: 1.74 };

export function idolBase(id = 'rpg-idol') {
  const base = huskDesign(id, 0xc4c0cc, [4.2, 2.0, 0.5]);
  return {
    ...base,
    id, idle: 'rpg.idol.idle',
    proportions: { clavicle: 0.235, hipWidth: 0.118, shoulderHeight: 0.205 },
    gripAngle: 40,
    weapon: { hand: 'R', slot: 'blade', base: [0.2, 0, 0], tip: [SABER.tip, 0, 0], grips: { grip: { pos: [-0.17, 0, 0] }, blade: { pos: [0.5, 0, 0] } } },
  };
}

export const idolRig = idolBase();
