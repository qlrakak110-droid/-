// 뇌진천 雷震天 (id `vorn`) — 천뢰신창 天雷神槍, the Heaven-Thunder Spear of 뇌운보 雷雲堡 (Thundercloud Keep). Character
// design (src/char/README.md "Design format") whose whole visible surface is a Blender asset:
// tools/blender/heroes/vorn.py -> assets/chars/vorn (rebuild: tools/blender/build_assets.sh vorn --preview).
//
// Look: tall and disciplined, a soldier-monk. A deep conical bamboo hat (삿갓: a real over-under plait baked into maps)
// over a cloth face wrap with glowing storm-violet eyes in its shadow and a long braided queue down the back; a
// storm-violet robe with crossed ink-black collars over an ink under-robe; a black lacquered lamellar cuirass (찰갑)
// and left shoulder piece laced in old gold; a lacquered waist guard over a black hemp sash knotted at the front left;
// a three-panel split skirt (front + two back panels, runtime cloth); sleeves bound by hemp wraps from mid-forearm to
// the knuckles; loose trousers gathered into tall wrapped boots; old-gold thunder-fret embroidery on the collars, cuffs
// and hems that crawls with violet-white light. The 뇌룡창 keeps the exact length, grips and sockets of
// WEAPON_SPECS.spear: leaf head with a midrib, a small crossguard, a violet horsehair tassel on a spring chain,
// lacquered shaft with bronze bands and butt cap.
//
// Slots (draw calls): cloth (robe, collars, sash, trousers, wraps, face wrap, skirt panels), gear (body, eyes, armour,
// hat, hair, boots), hair (alpha-cut tassel strands), blade (the spear) = 4.
// Glow: vorn.glow = { inlay: thunder embroidery + the spear's bolt, vein: the old-gold lacing and bronze fittings
// (운기 flares), eye: the eyes under the hat }; vorn.attach(char) -> char.glow (attachGlow + the arc crackle).
// Unchanged from the knight it replaces (108 clips depend on them): proportions, skeleton, colliders, the weapon (length,
// grips) and the socket names / positions (visor, hornR, hornL, finL, runes: fx / present anchors).

import vornAsset from '../../../assets/chars/vorn/index.js';
import { addAsset, assetCloth, attachAssetMaps } from '../../char/assets.js';
import { attachGlow } from '../../char/materials.js';
import { hang } from '../../char/kit/murim.js';
import { spear, WEAPON_SPECS, WEAPON_MATERIALS } from '../../char/weapons.js';
import { crackle, stormHornTips } from './kit.js';

/** Storm palette (linear HDR): violet-white arc core (5, 3.5, 9) -> electric violet; the eyes burn whitest. */
const GLOW = { inlay: [2.6, 1.75, 6.6], vein: [1.6, 0.8, 4.6], eye: [6.0, 4.9, 11.5] };
const RIM = [0.2, 0.24, 0.46, 3.0];
const RIM_GEAR = [0.14, 0.17, 0.32, 3.6];

// ---- spring chains (skinned in Blender: tools/blender/heroes/vorn.py along_chain) -------------------------------------------
/** The long braided queue from under the hat down the back. */
const QUEUE = hang('queue', 'head', [-0.1, 0.075, 0], { n: 4, len: 0.5, dir: [0, -1, 0], stiffness: 26, damping: 3.0, gravity: 0.9, limit: 70, radius: 0.022, inertia: 1 });
/** The two tails of the face wrap, tied at the nape. */
const WRAPTAIL = hang('wrapTail', 'head', [-0.098, 0.05, 0.0], { n: 2, len: 0.2, dir: [-0.35, -1, 0], stiffness: 22, damping: 2.6, gravity: 0.85, limit: 70, radius: 0.016 });
/** The spear's violet horsehair tassel (창영) below the socket (weapon frame). */
const TASSEL = hang('tassel', 'weaponR', [0.93, 0, 0], { n: 2, len: 0.2, dir: [-1, -0.3, 0], stiffness: 30, damping: 3.2, gravity: 1, limit: 75, radius: 0.012, collide: false });
const CHAINS = [QUEUE, WRAPTAIL, TASSEL];
export const VORN_CHAINS = { QUEUE, WRAPTAIL, TASSEL };
/** Look retunes over the Blender looks (tools/blender/heroes/vorn.py LK), judged in the engine. */
const LOOKS = {
  face: { color: [0.075, 0.064, 0.088], rough: 0.92 },          // smoke-violet wrap: its folds must read in the hat's shadow
  lamellar: { color: [0.016, 0.013, 0.02], rough: 0.4 },         // lacquer glints stay small (no bloom stars on the plates)
  // roster review: the storm-violet silk read as bright lavender satin (the loudest, least murim colour of the roster)
  // -> a deep, dusky storm violet with a dry lustre; ink-black and old gold carry the contrast
  robe: { color: [0.026, 0.012, 0.048], rough: 0.72 },
  horsehair: { color: [0.05, 0.016, 0.08] },
  grip: { color: [0.035, 0.016, 0.06] },
  skin: { rough: 0.74 },                                          // the eye band in the hat's shadow: no wet sheen
};

/** Old helm geometry the fx sockets were placed on (kept: present.js / fx.js anchor sparks there). */
const HELM = { rx: 0.124, rz: 0.106, top: 0.282, bottom: -0.08, eyeY: 0.08, eyeH: 0.018 };
const HELM_EYE_Y = HELM.eyeY;
const HORN_TIPS = stormHornTips(HELM);

/**
 * Glow control with the storm crackle: attachGlow (char.glow: set / flare / gain / rim) plus a deterministic flicker and
 * sparse arc surges on the embroidery (inlay) and eye channels, driven by game time. glow.crackle (0..1, default 1)
 * scales the effect (0 = steady). set(name, colour, k) keeps working: k is the base the crackle modulates.
 */
function attachStorm(char) {
  if (char.glow && char.glow.crackle !== undefined) return char.glow;
  const glow = attachGlow(char, GLOW);
  const user = { inlay: 1, vein: 1, eye: 1 };
  const set0 = glow.set;
  glow.set = (name, color, k = 1) => { if (name in user) user[name] = k; return set0(name, color, k); };
  glow.crackle = 1;
  const update = char.update;
  char.update = function (dtGame, dtReal) {
    const t = glow.time + (dtGame || 0), c = glow.crackle;
    const ch = glow.channels;
    ch.inlay.intensity = user.inlay * (1 + c * (crackle(t, 1) - 1));
    ch.vein.intensity = user.vein * (1 + c * 0.6 * (crackle(t * 1.3, 4) - 1));
    ch.eye.intensity = user.eye * (1 + c * 0.25 * (crackle(t, 1) - 1));
    return update.call(char, dtGame, dtReal);
  };
  return glow;
}

export const vorn = {
  id: 'vorn',
  name: '뇌진천',
  title: '천뢰신창',
  idle: 'demo.idle',
  // unchanged: ~2.02 m long-limbed spearman (the rig team's VORN audit set)
  proportions: {
    hipHeight: 1.05, pelvisDrop: 0.064, hipWidth: 0.104, ankleHeight: 0.09, footLength: 0.145, footDrop: 0.058, toeLength: 0.086, heelLength: 0.07,
    spine: 0.116, chest: 0.18, neck: 0.265, head: 0.11, shoulderHeight: 0.21, clavicleRoot: 0.032, clavicle: 0.2, shoulderBack: 0.016,
    upperArm: 0.325, foreArm: 0.29, hand: 0.09, palm: 0.023,
  },
  glow: GLOW,
  // slots = draw calls: cloth (robe layers, skirt panels, sash, wraps, face wrap), gear (body, armour, hat, hair, boots),
  // hair (alpha-cut tassel strands), blade (the spear)
  materials: {
    cloth: { envMapIntensity: 0.6, bump: 1, glow: GLOW, rim: RIM, thread: [0.42, 0.28, 0.08], wear: [0.4, 0.9, 0.55, 0], sheen: [0.8, 0.6, 1, 0.5] },
    gear: { envMapIntensity: 0.9, bump: 1, glow: GLOW, rim: RIM_GEAR, lace: [0.32, 0.2, 0.055], undercoat: [0.05, 0.02, 0.06], wear: [0.85, 0.8, 0.4, 0], verdigris: [0.035, 0.07, 0.055], verdigrisAmount: 0.4 },
    hair: { envMapIntensity: 0.5, bump: 1, cutout: true, glow: GLOW, rim: RIM },
    blade: { ...WEAPON_MATERIALS.spear },
  },
  bones: CHAINS.flatMap((c) => c.bones),
  springs: CHAINS.flatMap((c) => c.springs),
  colliders: [
    { name: 'torso', a: ['spine', [-0.01, 0, 0]], b: ['chest', [-0.015, 0.16, 0]], r: 0.19 },
    { name: 'pelvis', a: ['hips', [-0.02, -0.04, -0.09]], b: ['hips', [-0.02, -0.04, 0.09]], r: 0.168 },
    { name: 'shoulderR', a: ['chest', [-0.03, 0.19, 0.1]], b: ['upperArmR', [0, -0.05, 0]], r: 0.13 },
    { name: 'shoulderL', a: ['chest', [-0.03, 0.19, -0.1]], b: ['upperArmL', [0, -0.05, 0]], r: 0.15 },
    { name: 'upperArmR', a: ['upperArmR', [0, -0.05, 0]], b: ['upperArmR', [0, -0.31, 0]], r: 0.074 },
    { name: 'upperArmL', a: ['upperArmL', [0, -0.05, 0]], b: ['upperArmL', [0, -0.31, 0]], r: 0.074 },
    { name: 'foreArmR', a: ['foreArmR', [0, 0, 0]], b: ['foreArmR', [0, -0.29, 0]], r: 0.065 },
    { name: 'foreArmL', a: ['foreArmL', [0, 0, 0]], b: ['foreArmL', [0, -0.29, 0]], r: 0.065 },
    { name: 'thighR', a: ['thighR', [0, 0.02, 0]], b: ['thighR', [0, -0.49, 0]], r: 0.118 },
    { name: 'thighL', a: ['thighL', [0, 0.02, 0]], b: ['thighL', [0, -0.49, 0]], r: 0.118 },
    { name: 'shinR', a: ['shinR', [0, 0, 0]], b: ['shinR', [0, -0.46, 0]], r: 0.084 },
    { name: 'shinL', a: ['shinL', [0, 0, 0]], b: ['shinL', [0, -0.46, 0]], r: 0.084 },
  ],
  // the skirt panels draped in Blender (verlet cloth in the game; the asset binds their lower part to it)
  cloth: vornAsset ? assetCloth(vornAsset) : [],
  weapon: WEAPON_SPECS.spear,
  // names and positions unchanged (present.js / fx.js anchors)
  sockets: {
    visor: ['head', [0.152, HELM_EYE_Y, 0]],
    hornR: ['head', HORN_TIPS[0]],
    hornL: ['head', HORN_TIPS[1]],
    finL: ['deltoidL', [-0.09, 0.25, -0.03]],
    runes: ['chest', [0.17, 0.06, 0]],
  },

  /**
   * Glow control (char.glow: set / flare / gain / rim + crackle, advanced by char.update) + the asset's baked maps
   * (skipped on the low tier). The game calls attach(char) without a quality: the tier is then read from the cloth grid.
   */
  attach(char, quality) {
    if (!char.glow && vornAsset) attachAssetMaps(char, vornAsset, quality || { tier: lowTier(char) ? 'low' : 'high' });
    return attachStorm(char);
  },

  build(kit) {
    // a missing asset only happens while bootstrapping (tools/blender/export_rig.mjs before the first Blender build)
    if (!vornAsset) { spear(kit, { bone: 'weaponR', slot: 'blade' }); return; }
    addAsset(kit, vornAsset, { design: this, looks: LOOKS });
  },
};

/** True when the rig's cloth grid is coarser than the asset's panels (ctx.quality.cloth < 1: the low tier). */
function lowTier(char) {
  const idx = char.rig && char.rig.index;
  if (!idx) return false;
  for (const spec of vorn.cloth) {
    let R = 0;
    while (idx[`${spec.name}_0_${R}`] !== undefined) R++;
    if (R && R < spec.rows) return true;
  }
  return false;
}

/** Kept for older imports: the low tier is handled by the asset loader (baked maps skipped), same design. */
export const vornLow = vorn;

export default vorn;
