// The Blender asset pipeline pilot: a soldier-monk spearman modelled entirely in Blender (tools/blender/heroes/pilot.py
// -> assets/chars/pilot) on VORN's rig. Proportions, skeleton, colliders, weapon (length, grips, gripAngle) and sockets are
// VORN's, unchanged; what changes is what the skeleton wears: one spring chain for the hair queue (queue1..queue4 under
// the head) and three runtime cloth panels (skirtF, skirtBL, skirtBR) defined from the Blender drape instead of VORN's
// surcoat panels. Used by the asset lab (src/labs/asset.js) and by tools/blender/export_rig.mjs (-> rigs/pilot.json).

import pilotAsset from '../../assets/chars/pilot/index.js';
import { vorn } from '../fighters/vorn/design.js';
import { addAsset, assetCloth, attachAssetMaps } from './assets.js';
import { attachGlow } from './materials.js';
import { WEAPON_MATERIALS } from './weapons.js';

export const QUEUE = ['queue1', 'queue2', 'queue3', 'queue4'];
const SEG = 0.125;
/** Storm palette (linear HDR): eyes under the hat, glow through the old-gold lacing and the thunder brocade. */
const GLOW = { inlay: [2.6, 1.75, 6.6], vein: [1.6, 0.8, 4.6], eye: [6.0, 4.9, 11.5] };
const RIM = [0.2, 0.24, 0.46, 3.0];

export const pilot = {
  ...vorn,
  id: 'pilot',
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
  glow: GLOW,
  // slots = draw calls: cloth (robe, skirt panels, sash, wraps, face wrap), gear (body, armour, hat, hair, boots),
  // hair (alpha-cut tassel strands), blade (the spear)
  materials: {
    cloth: { envMapIntensity: 0.6, bump: 1, glow: GLOW, rim: RIM, thread: [0.42, 0.28, 0.08], wear: [0.4, 0.9, 0.55, 0] },
    gear: { envMapIntensity: 0.9, bump: 1, glow: GLOW, rim: RIM, lace: [0.32, 0.2, 0.055], undercoat: [0.03, 0.02, 0.045], wear: [0.85, 0.8, 0.4, 0] },
    hair: { envMapIntensity: 0.5, bump: 1, cutout: true, glow: GLOW, rim: RIM },
    blade: { ...WEAPON_MATERIALS.spear },
  },
  // the skirt panels draped in Blender (the asset carries their rest grid and binds the skirt's lower part to them)
  cloth: pilotAsset ? assetCloth(pilotAsset) : [],
  /** Baked maps (the hat's weave; skipped on the low tier) + glow control. */
  attach(char, quality) {
    attachAssetMaps(char, pilotAsset, quality);
    return attachGlow(char, GLOW);
  },
  build(kit) {
    if (!pilotAsset) throw new Error('pilot: assets/chars/pilot is missing (tools/blender/build_assets.sh pilot)');
    addAsset(kit, pilotAsset, { design: this });
  },
};

export default pilot;
