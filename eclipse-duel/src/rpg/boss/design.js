// 「흑일마신상 黑日魔神像」 — the design. The body under the armour is the husk's lofts (smooth-skinned, dark); everything
// you see on top of it is the Blender-made asset `idol.edb` (tools/blender/heroes/idol.py): ~78k triangles of rigid
// pieces, one bone each, with baked per-vertex colour (looks, wear, patina), cavity (ambient occlusion) and glow
// (eclipse fire in the cracks). Two draw calls (plate, blade). Format: ../edb.js.

import { idolBase, SABER } from './rigdesign.js';
import { decodeEdb, addEdbPieces } from '../edb.js';
import EDB from './idol.edb';

export { SABER };

const GLOW = { inlay: [5.6, 2.6, 0.55], vein: [3.6, 1.25, 0.16], eye: [11, 5, 1.1] };
let PIECES = null;

export function idolDesign(id = 'rpg-idol') {
  const base = idolBase(id);
  const baseBuild = base.build;
  return {
    ...base,
    materials: {
      // glow channels: inlay = cores, bosses, the blade's edge; vein = eclipse fire in the stone's cracks; eye = the mask's eyes
      plate: { envMapIntensity: 0.95, bump: 1, side: 'double', glow: GLOW, rim: [0.3, 0.38, 0.6, 3.0], wear: [0.9, 0.85, 0.45, 0.9], wearColor: [0.34, 0.31, 0.27],
        grimeColor: [0.2, 0.17, 0.15], heatColor: [0.26, 0.09, 0.03], ember: [0, 2.0, 0, 0.09], pulse: [0.22, 1.1, 2.2, 0] },
      blade: { envMapIntensity: 1.0, bump: 1, glow: GLOW, rim: [0.3, 0.38, 0.6, 3.0], wear: [0.9, 0.8, 0.4, 0.6], wearColor: [0.5, 0.5, 0.53] },
    },
    build(kit, S) {
      // the husk's under-body only: its plates, helm and sword go to a throw-away facade
      const body = { ...kit, add: () => body, addPair: () => body, loft: (...a) => (kit.loft(...a), body), loftPair: (...a) => (kit.loftPair(...a), body) };
      baseBuild(body, S);
      kit.addPair('plate', 'hand', S.box(0.085, 0.1, 0.085, 0.02), { color: 0x101114, rough: 0.6, metal: 0.5, at: [0, -0.07, 0] });
      if (!PIECES) PIECES = decodeEdb(EDB);
      addEdbPieces(kit, PIECES);
    },
  };
}
