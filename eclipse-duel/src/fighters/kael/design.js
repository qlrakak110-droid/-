// 염무강 炎武剛 (id `kael`) — 적염패도 赤焰覇刀, the Crimson Flame Tyrant Saber of the Red Sun Gate (적양문). Character design
// (src/char/README.md "Design format"); the look is modelled in Blender by tools/blender/heroes/kael.py and loaded from
// assets/chars/kael (src/char/assets.js).
//
// A broad, heavy master: a charred-black outer coat over a deep-red robe, both worn open at the chest over a scarred torso
// bound with cloth bands; one snarling beast-face pauldron on the right shoulder (the saber rests in the cradle of its
// mane in the stance); a thick crimson sash knotted at the left hip with long hanging ends; split coat tails (the back
// pair on runtime cloth); forearms wrapped in cloth under bronze-studded leather bracers; heavy boots; an iron demon
// half-mask (귀면) with sculpted brows, cheek ridges and fangs under a topknot, a loose mane and a short red headband;
// ember light through the brocade seams, the mask's cracks and the blade's blood groove. The 참마대도 keeps the exact
// length, grips and sockets of WEAPON_SPECS.greatsword.
//
// Slots (draw calls): cloth (coat, robe, sash, trousers, wraps), gear (body, mask, pauldron, bracers, boots, hair cap,
// topknot), hair (alpha-cut mane locks, strip / tassel strands), blade (the saber) = 4.
// Glow: kael.glow = { inlay (brocade embroidery, blood groove), vein (mask cracks, charred iron, saber back), eye };
// kael.attach(char, quality) binds the baked maps and returns the runtime glow control (char.glow).

import kaelAsset from '../../../assets/chars/kael/index.js';
import { addAsset, assetCloth, attachAssetMaps } from '../../char/assets.js';
import { attachGlow } from '../../char/materials.js';
import { hang } from '../../char/kit/murim.js';
import { greatsword, saberStripRig, WEAPON_SPECS, WEAPON_MATERIALS } from '../../char/weapons.js';

/** Ember palette (linear HDR): core (8, 3, 0.6) -> (3, 0.5, 0.05). */
const GLOW = { inlay: [6.2, 2.0, 0.34], vein: [2.6, 0.62, 0.07], eye: [9.5, 3.6, 0.8] };
const RIM = [0.3, 0.36, 0.58, 3.0];

// ---- spring chains (skinned in Blender: tools/blender/heroes/kael.py along_chain) -----------------------------------------
/** The loose mane: three locks falling from the crown down the nape and over the upper back. */
const MANE = [
  hang('maneA', 'head', [-0.07, 0.165, -0.045], { n: 3, len: 0.44, dir: [-0.5, -1, -0.16], stiffness: 18, damping: 2.6, gravity: 0.85, limit: 55, radius: 0.028 }),
  hang('maneB', 'head', [-0.088, 0.15, 0.0], { n: 3, len: 0.5, dir: [-0.55, -1, 0], stiffness: 18, damping: 2.6, gravity: 0.85, limit: 55, radius: 0.028 }),
  hang('maneC', 'head', [-0.07, 0.165, 0.045], { n: 3, len: 0.42, dir: [-0.5, -1, 0.16], stiffness: 18, damping: 2.6, gravity: 0.85, limit: 55, radius: 0.028 }),
];
/** Tails of the red headband, tied at the back of the head. */
const BAND = hang('band', 'head', [-0.098, 0.172, 0.0], { n: 2, len: 0.22, dir: [-0.7, -1, 0.05], stiffness: 20, damping: 2.4, gravity: 0.8, limit: 70, radius: 0.016 });
/** The two hanging ends of the sash knot (front-left hip): they swing over the left thigh. */
const SASH = [
  hang('sashA', 'hips', [0.115, 0.03, -0.12], { n: 3, len: 0.56, dir: [0.12, -1, -0.06], stiffness: 20, damping: 2.8, gravity: 1, limit: 65, radius: 0.03 }),
  hang('sashB', 'hips', [0.1, 0.03, -0.155], { n: 3, len: 0.46, dir: [0.05, -1, -0.16], stiffness: 20, damping: 2.8, gravity: 1, limit: 65, radius: 0.03 }),
];
/** The red cloth strip tied through the saber's ring pommel. */
const STRIP = saberStripRig();
const CHAINS = [...MANE, BAND, ...SASH, STRIP];

export const kael = {
  id: 'kael',
  name: '염무강',
  title: '적염패도',
  idle: 'demo.idle',
  // unchanged: 108 clips depend on these proportions, the colliders, the weapon and the sockets
  proportions: {
    hipHeight: 1.0, spine: 0.115, chest: 0.18, neck: 0.26, head: 0.105, shoulderHeight: 0.205,
    clavicle: 0.215, upperArm: 0.31, foreArm: 0.28, hipWidth: 0.108,
  },
  glow: GLOW,
  materials: {
    cloth: { envMapIntensity: 0.6, bump: 1, glow: GLOW, rim: RIM, thread: [0.5, 0.26, 0.07], wear: [0.4, 0.9, 0.55, 0] },
    gear: { envMapIntensity: 0.95, bump: 1, glow: GLOW, rim: RIM, wear: [0.9, 0.85, 0.45, 0.9], wearColor: [0.3, 0.27, 0.24], grimeColor: [0.22, 0.17, 0.14], heatColor: [0.2, 0.075, 0.035], undercoat: [0.16, 0.03, 0.014] },
    hair: { envMapIntensity: 0.5, bump: 1, cutout: true, glow: GLOW, rim: RIM },
    blade: { ...WEAPON_MATERIALS.greatsword },
  },
  bones: CHAINS.flatMap((c) => c.bones),
  springs: CHAINS.flatMap((c) => c.springs),
  colliders: [
    { name: 'torso', a: ['spine', [-0.01, 0, 0]], b: ['chest', [-0.015, 0.16, 0]], r: 0.2 },
    { name: 'pelvis', a: ['hips', [-0.02, -0.04, -0.09]], b: ['hips', [-0.02, -0.04, 0.09]], r: 0.17 },
    { name: 'shoulderR', a: ['chest', [-0.03, 0.19, 0.1]], b: ['upperArmR', [0, -0.05, 0]], r: 0.15 },
    { name: 'shoulderL', a: ['chest', [-0.03, 0.19, -0.1]], b: ['upperArmL', [0, -0.05, 0]], r: 0.13 },
    { name: 'upperArmR', a: ['upperArmR', [0, -0.05, 0]], b: ['upperArmR', [0, -0.3, 0]], r: 0.075 },
    { name: 'upperArmL', a: ['upperArmL', [0, -0.05, 0]], b: ['upperArmL', [0, -0.3, 0]], r: 0.075 },
    { name: 'foreArmR', a: ['foreArmR', [0, 0, 0]], b: ['foreArmR', [0, -0.27, 0]], r: 0.065 },
    { name: 'foreArmL', a: ['foreArmL', [0, 0, 0]], b: ['foreArmL', [0, -0.27, 0]], r: 0.065 },
    { name: 'thighR', a: ['thighR', [0, 0.02, 0]], b: ['thighR', [0, -0.46, 0]], r: 0.11 },
    { name: 'thighL', a: ['thighL', [0, 0.02, 0]], b: ['thighL', [0, -0.46, 0]], r: 0.11 },
    { name: 'shinR', a: ['shinR', [0, 0, 0]], b: ['shinR', [0, -0.43, 0]], r: 0.08 },
    { name: 'shinL', a: ['shinL', [0, 0, 0]], b: ['shinL', [0, -0.43, 0]], r: 0.08 },
    // added for the cloth tails and the mane (the rig warned about their absence); clips do not read them
    { name: 'head', a: ['head', [0.01, 0.06, 0]], b: ['head', [-0.01, 0.15, 0]], r: 0.115 },
    { name: 'neck', a: ['neck', [0, 0, 0]], b: ['neck', [0.01, 0.1, 0]], r: 0.07 },
  ],
  // the back coat tails draped in Blender (the asset carries their rest grids)
  cloth: kaelAsset ? assetCloth(kaelAsset) : [],
  weapon: WEAPON_SPECS.greatsword,
  sockets: { visor: ['head', [0.15, 0.075, 0]], pauldron: ['deltoidR', [0, 0.17, 0.02]], cracks: ['chest', [0.17, 0.05, 0]] },

  /** Baked maps (skipped on the low tier) + the runtime glow control (char.glow: flare / set / gain). */
  attach(char, quality) {
    if (kaelAsset) attachAssetMaps(char, kaelAsset, quality);
    return attachGlow(char, GLOW);
  },

  build(kit) {
    // bootstrap (tools/blender/export_rig.mjs before the asset exists): the kit saber gives the weapon extent
    if (!kaelAsset) { greatsword(kit, { bone: 'weaponR', slot: 'blade', strip: STRIP }); return; }
    addAsset(kit, kaelAsset, { design: this });
  },
};

export default kael;
