// 설리화 雪梨花 (id iska) — 빙월쌍도 氷月雙刀, the Frost-Moon Twin Blades of 한월궁 寒月宮 (the Cold Moon Palace).
// Character design (src/char/README.md "Design format") whose whole visible surface is a Blender asset:
// tools/blender/heroes/iska.py -> assets/chars/iska (rebuild: tools/blender/build_assets.sh iska --preview).
//
// Look: slender and cold. A sculpted silver half-mask with frost-lit eye slits over a gauze face veil, black hair bound
// high into a long tail (silver bindings, a 비녀 hairpin through the knot, a crescent hair ornament), moon-white outer
// robe with a high crossed collar over a deep-indigo inner robe, wide floating sleeves that end above the wrists over
// silver bracers, a wide indigo sash embroidered with snow crystals, knotted at the front left with two hanging ends and
// a jade pendant, a robe skirt split into four panels that open with the legs, fitted indigo trousers in wrapped shins,
// cloth shoes, and the 월아쌍도 (twin crescent blades) rebuilt in Blender on the exact outline, grips and sockets.
//
// Proportions, skeleton, colliders, weapons (lengths, grips, sockets) and the design sockets are unchanged: 108 clips
// depend on them. What changed: the spring chains (hair tail, sleeve drapes, sash ends, jade pendant, front skirt panels
// that follow the thighs) and the two runtime cloth panels of the back skirt (draped in Blender: assetCloth).
//
// Slots (draw calls): cloth (robes, sleeves, sash, skirts, trousers, wraps), gear (body, mask, bracers, shoes, jade,
// silver fittings, hair mass), hair (alpha-cut: hair strands, gauze veil, tassels), blade (crescents) = 4.
// Glow (frost, linear HDR): inlay = frost seams of the blades and the snow-crystal stones, vein = snow-crystal
// embroidery (brocade thread) and the engraved silver, eye = the eye slits of the mask. design.attach(char, quality) ->
// char.glow (+ baked maps unless the low tier).

import iskaAsset from '../../../assets/chars/iska/index.js';
import { addAsset, assetCloth, attachAssetMaps } from '../../char/assets.js';
import { attachGlow } from '../../char/materials.js';
import { crescents, WEAPON_SPECS, WEAPON_MATERIALS } from '../../char/weapons.js';
import { hang, skirtRig } from '../../char/kit/murim.js';

/** Frost palette (linear HDR): core (1.5, 4, 8) -> (0.3, 1.2, 3) -> white mist. */
const GLOW = { inlay: [1.0, 2.7, 5.8], vein: [0.42, 1.25, 3.0], eye: [2.4, 5.6, 10.0] };
const RIM = [0.16, 0.24, 0.44, 3.2];

const PROPORTIONS = {
  hipHeight: 0.95, pelvisDrop: 0.055, hipWidth: 0.088, thighRatio: 0.515, ankleHeight: 0.078, footLength: 0.125, footDrop: 0.05,
  toeLength: 0.07, heelLength: 0.058, spine: 0.1, chest: 0.155, neck: 0.24, head: 0.09, shoulderHeight: 0.19, clavicleRoot: 0.028,
  clavicle: 0.162, shoulderBack: 0.012, upperArm: 0.295, foreArm: 0.255, hand: 0.078, palm: 0.02,
};

/** A spring chain from explicit joint offsets (each in its parent's zero frame); tip = the last segment. */
function chain(name, parent, at, steps, o = {}) {
  const names = steps.map((_, i) => name + (i + 1));
  const bones = names.map((nm, i) => ({ name: nm, parent: i ? names[i - 1] : parent, at: i ? steps[i - 1] : at, side: 0 }));
  const springs = [{
    bones: names, tip: o.tip || steps[steps.length - 1], stiffness: o.stiffness ?? 22, damping: o.damping ?? 2.6, gravity: o.gravity ?? 0.9,
    limit: o.limit ?? 70, radius: o.radius ?? 0.02, collide: o.collide ?? true, inertia: o.inertia ?? 1,
  }];
  return { name, names, bones, springs };
}

// ---- secondary motion (bind positions are what tools/blender/heroes/iska.py builds on) ---------------------------------------
// the long bound tail of hair: tied high at the back of the head, falling down the back to the waist
const HAIR = chain('hair', 'head', [-0.095, 0.172, 0], [[-0.055, -0.12, 0], [-0.022, -0.14, 0], [-0.008, -0.15, 0], [0, -0.15, 0]],
  { tip: [0, -0.15, 0], stiffness: 16, damping: 2.1, gravity: 0.95, limit: 80, radius: 0.028 });
// floating sleeves: the hanging lower back of each wide sleeve, from just below the elbow
const SLV = ['R', 'L'].map((s) => chain('slv' + s, 'foreArm' + s, [-0.032, -0.045, 0], [[-0.012, -0.085, 0], [-0.01, -0.085, 0]],
  { tip: [-0.008, -0.08, 0], stiffness: 26, damping: 3.0, gravity: 1.0, limit: 75, radius: 0.026 }));
// sash ends hanging from the knot at the front left, and the jade pendant (노리개) at the front right
const SASH = [
  chain('sashA', 'hips', [0.112, 0.052, -0.07], [[0.004, -0.13, -0.004], [0.004, -0.13, -0.004]], { tip: [0.004, -0.12, -0.004], stiffness: 28, damping: 3.0, gravity: 0.9, limit: 60, radius: 0.022 }),
  chain('sashB', 'hips', [0.104, 0.05, -0.098], [[0.0, -0.11, -0.012], [0.0, -0.11, -0.01]], { tip: [0.0, -0.1, -0.008], stiffness: 28, damping: 3.0, gravity: 0.9, limit: 60, radius: 0.022 }),
];
const JADE = chain('jade', 'hips', [0.096, 0.03, 0.098], [[0.0, -0.075, 0.004]], { tip: [0, -0.1, 0], stiffness: 36, damping: 3.2, gravity: 1.0, limit: 65, radius: 0.018 });
// front skirt panels: a follower at the waist rides 62 % of the thigh swing, two spring bones carry the hem
const SKIRT = [
  skirtRig('skFR', { a0: 6, a1: 84, len: 0.6, follow: 'thighR', rx: 0.12, rz: 0.14, y: -0.02, n: 2, stiffness: 34, damping: 3.6, radius: 0.045, limit: 55 }),
  skirtRig('skFL', { a0: -84, a1: -6, len: 0.6, follow: 'thighL', rx: 0.12, rz: 0.14, y: -0.02, n: 2, stiffness: 34, damping: 3.6, radius: 0.045, limit: 55 }),
];
const RIGS = [HAIR, ...SLV, ...SASH, JADE, ...SKIRT];
export const ISKA_CHAINS = { HAIR, SLV, SASH, JADE, SKIRT };

export const iska = {
  id: 'iska',
  name: '설리화',
  title: '빙월쌍도',
  idle: 'iska.idle',
  proportions: PROPORTIONS,
  glow: GLOW,
  materials: {
    cloth: { envMapIntensity: 0.62, bump: 1, glow: GLOW, rim: RIM, thread: [0.62, 0.68, 0.78], threadMetal: 1, cloth: [0.35, 0.34, 0.5], wear: [0.3, 0.7, 0.45, 0] },
    gear: { envMapIntensity: 1.0, bump: 0.9, glow: GLOW, rim: RIM, wear: [0.6, 0.55, 0.3, 0], wearColor: [0.82, 0.86, 0.92], grimeColor: [0.36, 0.4, 0.52], lace: [0.05, 0.07, 0.16] },
    hair: { envMapIntensity: 0.55, bump: 1, cutout: true, glow: GLOW, rim: RIM, cloth: [0.3, 0.3, 0.55] },
    blade: { ...WEAPON_MATERIALS.crescents },
  },
  bones: RIGS.flatMap((r) => r.bones),
  springs: RIGS.flatMap((r) => r.springs),
  colliders: [
    { name: 'torso', a: ['spine', [-0.004, -0.02, 0]], b: ['chest', [-0.008, 0.15, 0]], r: 0.13 },
    { name: 'pelvis', a: ['hips', [-0.01, -0.05, -0.07]], b: ['hips', [-0.01, -0.05, 0.07]], r: 0.13 },
    { name: 'shoulderR', a: ['chest', [-0.02, 0.17, 0.08]], b: ['upperArmR', [0, -0.04, 0]], r: 0.095 },
    { name: 'shoulderL', a: ['chest', [-0.02, 0.17, -0.08]], b: ['upperArmL', [0, -0.04, 0]], r: 0.095 },
    { name: 'upperArmR', a: ['upperArmR', [0, -0.04, 0]], b: ['upperArmR', [0, -0.29, 0]], r: 0.055 },
    { name: 'upperArmL', a: ['upperArmL', [0, -0.04, 0]], b: ['upperArmL', [0, -0.29, 0]], r: 0.055 },
    { name: 'foreArmR', a: ['foreArmR', [0, 0, 0]], b: ['foreArmR', [0, -0.25, 0]], r: 0.048 },
    { name: 'foreArmL', a: ['foreArmL', [0, 0, 0]], b: ['foreArmL', [0, -0.25, 0]], r: 0.048 },
    { name: 'thighR', a: ['thighR', [0, 0.02, 0]], b: ['thighR', [0, -0.44, 0]], r: 0.088 },
    { name: 'thighL', a: ['thighL', [0, 0.02, 0]], b: ['thighL', [0, -0.44, 0]], r: 0.088 },
    { name: 'shinR', a: ['shinR', [0, 0, 0]], b: ['shinR', [0, -0.42, 0]], r: 0.06 },
    { name: 'shinL', a: ['shinL', [0, 0, 0]], b: ['shinL', [0, -0.42, 0]], r: 0.06 },
    // the runtime's default head / neck capsules for designs with cloth, written out (same values at her body scale)
    { name: 'head', a: ['head', [0.0097, 0.0676, 0]], b: ['head', [0, 0.1546, 0]], r: 0.1208 },
    { name: 'neck', a: ['neck', [0.0097, 0.029, 0]], b: ['neck', [0.0097, 0.0966, 0]], r: 0.0628 },
  ],
  // the back skirt panels draped in Blender (verlet cloth in the game; the asset binds their lower part to it)
  cloth: iskaAsset ? assetCloth(iskaAsset) : [],
  weapons: WEAPON_SPECS.crescents,
  sockets: {
    eyes: ['head', [0.118, 0.078, 0]],          // between the eye slits of the silver mask (ULT close-up flare)
    crest: ['head', [0.088, 0.215, 0]],         // the crescent-moon hair ornament over the brow
    crystal: ['deltoidR', [-0.04, 0.12, 0.045]], // the frost-crystal clasp on the right shoulder
    heart: ['chest', [0.134, 0.07, 0]],         // the moon brooch where the collars cross
  },

  /**
   * Glow control (char.glow: flare / set / gain, advanced by char.update) + the asset's baked maps (skipped on the low
   * tier). The game calls attach(char) without a quality: the tier is then read from the cloth grid the rig was built with.
   */
  attach(char, quality) {
    if (!char.glow) attachAssetMaps(char, iskaAsset, quality || { tier: lowTier(char) ? 'low' : 'high' });
    return char.glow || attachGlow(char, GLOW);
  },

  build(kit) {
    // a missing asset only happens while bootstrapping (tools/blender/export_rig.mjs before the first Blender build)
    if (!iskaAsset) { crescents(kit, { slot: 'blade' }); return; }
    addAsset(kit, iskaAsset, { design: this });
  },
};

/** True when the rig's cloth grid is coarser than the asset's panels (ctx.quality.cloth < 1: the low tier). */
function lowTier(char) {
  const idx = char.rig && char.rig.index;
  if (!idx) return false;
  for (const spec of iska.cloth) {
    let R = 0;
    while (idx[`${spec.name}_0_${R}`] !== undefined) R++;
    if (R && R < spec.rows) return true;
  }
  return false;
}

export default iska;
