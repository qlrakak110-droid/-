// 「흑일마신상 黑日魔神像」 — the design. The body under the armour is the husk's lofts (smooth-skinned, dark); everything
// you see on top of it is the Blender-made asset `idol.edb` (tools/blender/heroes/idol.py): ~78k triangles of rigid
// pieces, one bone each, with baked per-vertex colour (looks, wear, patina), cavity (ambient occlusion) and glow
// (eclipse fire in the cracks). Two draw calls (plate, blade). Format: ../edb.js.

import { idolBase, SABER } from './rigdesign.js';
import { decodeEdb, addEdbPieces } from '../edb.js';
import EDB from './idol.edb';

export { SABER };

let PIECES = null;

export function idolDesign(id = 'rpg-idol') {
  const base = idolBase(id);
  const baseBuild = base.build;
  return {
    ...base,
    materials: {
      plate: { roughness: 1, metalness: 1, envMapIntensity: 0.9, detailScale: 7, bump: 0.2, side: 'double' },   // shells are seen from inside too (brim, pauldrons, skirts)
      blade: { roughness: 1, metalness: 1, envMapIntensity: 1.0, detailScale: 6, bump: 0.06 },
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
