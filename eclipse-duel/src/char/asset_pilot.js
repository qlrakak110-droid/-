// The Blender asset pipeline pilot rig: VORN's rig (proportions, bones, colliders, cloth panels, weapon, sockets: all
// unchanged) plus one spring chain for the pilot's hair queue (queue1..queue4 under the head). Used by
// tools/blender/export_rig.mjs (-> tools/blender/rigs/pilot.json) and by the asset lab (src/labs/asset.js), which builds
// the character from the Blender asset (assets/chars/pilot) instead of the kit build below.

import { vorn } from '../fighters/vorn/design.js';

export const QUEUE = ['queue1', 'queue2', 'queue3', 'queue4'];
const SEG = 0.125;

export const pilot = {
  ...vorn,
  id: 'vorn',
  name: 'PILOT',
  bones: [
    ...(vorn.bones || []),
    { name: 'queue1', parent: 'head', at: [-0.1, 0.075, 0] },
    { name: 'queue2', parent: 'queue1', at: [0, -SEG, 0] },
    { name: 'queue3', parent: 'queue2', at: [0, -SEG, 0] },
    { name: 'queue4', parent: 'queue3', at: [0, -SEG, 0] },
  ],
  springs: [
    ...(vorn.springs || []),
    { bones: QUEUE, stiffness: 26, damping: 3.0, gravity: 0.9, tip: [0, -SEG, 0], radius: 0.022, limit: 70, collide: true, inertia: 1 },
  ],
  // the pilot's own geometry comes from the asset (src/labs/asset.js); this keeps the kit build for a fallback view
  build: vorn.build,
};

export default pilot;
