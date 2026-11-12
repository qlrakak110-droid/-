// ISKA 이스카 — 서릿별 무녀 · Froststar Oracle. Character design (src/char/README.md "Design format").
//
// ~1.78 m, slender and long-legged. Fitted silver-white armour over a dark indigo bodysuit: a sculpted bodice, a cinched
// lamellar waist, scale tassets, crescent-moon spaulders, rerebraces, slim vambraces and greaves. The head is an indigo cowl
// flowing into a shoulder mantle, a pearl-silver oracle half-mask with glowing frost eyes and starlight "tears", a fine
// veil, a high collar and a crescent-and-star circlet standing over the hood brim. Twin cape tails, a long pointed front
// tabard (tailored cloth: shaped hems, silver embroidered borders, glowing star stitching) and four ribbons (spring
// chains) trail in spins. Frost crystals grow from the right spaulder, hang from the circlet and weight the ribbons.
// Weapons: the twin crescent blades (src/char/weapons.js), one per hand.
//
// Slots (draw calls): plate (silver armour, embroidery, crystals, glow), suit (bodysuit, hood, cloth bodies, ribbons),
// blade (crescents) = 3. Glow: iska.glow = { inlay (starlight runes / stars / crystals), vein (engraved grooves and
// embroidery), eye }; runtime control with iska.attach(char) -> char.glow.

import * as THREE from 'three';
import { attachGlow, surfDetail } from '../../char/materials.js';
import * as A from '../../char/kit/armor.js';
import { put, putPair, putSkinned, strip, extrude, merge, lathe } from '../../char/kit/geo.js';
import { clothSpec } from '../../char/kit/cloth.js';
import { crescents, WEAPON_SPECS, WEAPON_MATERIALS, WEAPON_LOOKS } from '../../char/weapons.js';
import { profile } from '../../char/shapes.js';
import * as K from './kit.js';
import { clothSurface, panelCloth, clothCharm, suppressRigCloth, clothGrid } from './tailor.js';

const DEG = Math.PI / 180;
const { sstep, lerp } = K;

/** Frost / starlight palette (linear HDR): core (1.5, 4, 8) -> (0.3, 1.2, 3) -> white mist. */
const GLOW = { inlay: [1.0, 2.7, 5.8], vein: [0.3, 1.05, 2.7], eye: [2.2, 5.2, 9.4] };

// ---- looks (linear colours) ---------------------------------------------------------------------------------------------
// cool pearl-silver: bright, faintly blue F0 with a satin roughness (reads light and cool under the arena's eclipse sky
// instead of a dark chrome mirror), blued steel kept dark for the value contrast
const L = {
  silver: { color: [0.54, 0.59, 0.67], rough: 0.42, metal: 1, set: 'hammered', amt: 0.45 },
  silverEngr: { color: [0.56, 0.61, 0.69], rough: 0.38, metal: 1, set: 'engraved', amt: 0.9, vein: 0.32 },
  crescent: { color: [0.6, 0.645, 0.72], rough: 0.4, metal: 1, set: 'engraved', amt: 0.6, vein: 0.22, wear: 1.2 },
  blued: { color: [0.075, 0.095, 0.16], rough: 0.3, metal: 1, set: 'hammered', amt: 0.6, wear: 1.1 },
  lamella: { color: [0.53, 0.575, 0.65], rough: 0.38, metal: 1, set: 'hammered', amt: 0.55, wear: 1.2 },
  scale: { color: [0.53, 0.575, 0.65], rough: 0.38, metal: 1, set: 'engraved', amt: 0.45, vein: 0.12, wear: 1.2 },
  rivet: { color: [0.7, 0.74, 0.8], rough: 0.26, metal: 1, set: 'hammered', amt: 0.2, wear: 1.3 },
  mask: { color: [0.58, 0.645, 0.76], rough: 0.32, metal: 0.1, set: 'hammered', amt: 0.1 },
  hoodTrim: { color: [0.52, 0.565, 0.645], rough: 0.42, metal: 0.8, set: 'engraved', amt: 0.85, vein: 0.4 },
  star: { color: [0.25, 0.45, 0.75], rough: 0.25, metal: 0, set: 'hammered', amt: 0, inlay: 1 },
  starDim: { color: [0.25, 0.45, 0.75], rough: 0.25, metal: 0, set: 'hammered', amt: 0, inlay: 0.45 },
  crystal: { color: [0.32, 0.56, 0.78], rough: 0.07, metal: 0.1, set: 'hammered', amt: 0, inlay: 0.14, wear: 0.3 },
  eye: { color: [0.06, 0.12, 0.22], rough: 0.4, metal: 0, set: 'hammered', amt: 0, eye: 1 },
  lace: { color: [0.03, 0.035, 0.08], rough: 0.7, metal: 0, set: 'leather', amt: 1 },
  leather: { color: [0.028, 0.03, 0.06], rough: 0.6, metal: 0, set: 'leather', amt: 1 },
  embroidery: { color: [0.55, 0.595, 0.68], rough: 0.4, metal: 0.8, set: 'engraved', amt: 0.85, vein: 0.55 },
};
/** Soft layers (suit slot). */
const S_ = {
  bodysuit: { color: [0.02, 0.024, 0.064], rough: 0.6, metal: 0, set: 'cloth', amt: 0.7 },
  sleeve: { color: [0.018, 0.022, 0.058], rough: 0.5, metal: 0, set: 'leather', amt: 0.55 },
  hood: { color: [0.024, 0.028, 0.075], rough: 0.86, metal: 0, set: 'cloth', amt: 1 },
  under: { color: [0.006, 0.007, 0.014], rough: 0.92, metal: 0, set: 'cloth', amt: 0.6 },
  cloth: { color: [0.022, 0.027, 0.074], rough: 0.84, metal: 0, set: 'cloth', amt: 1 },
  lining: { color: [0.2, 0.235, 0.3], rough: 0.62, metal: 0, set: 'cloth', amt: 1 },
  ribbon: { color: [0.1, 0.16, 0.3], rough: 0.45, metal: 0, set: 'cloth', amt: 0.8 },
};

// ---- body cross-section by bind height (model metres): the bodysuit surface; armour sits on top -------------------------
const BY = [0.86, 0.92, 0.97, 1.02, 1.06, 1.1, 1.15, 1.2, 1.25, 1.3, 1.35, 1.4, 1.45, 1.5];
const bodyC = (vals) => profile(BY.map((y, i) => [y, vals[i]]));
const BODY = {
  rx: bodyC([0.1, 0.112, 0.112, 0.106, 0.098, 0.092, 0.094, 0.1, 0.108, 0.114, 0.11, 0.1, 0.088, 0.062]),
  rz: bodyC([0.13, 0.155, 0.158, 0.148, 0.13, 0.115, 0.115, 0.122, 0.13, 0.135, 0.14, 0.142, 0.13, 0.08]),
  ox: bodyC([-0.01, -0.008, -0.006, -0.006, -0.008, -0.008, -0.006, 0.0, 0.006, 0.01, 0.008, 0.004, 0.0, -0.005]),
};
/** Body radii as curves of a bone frame's local y (bone bind height y0) + a gap. */
const bodyIn = (y0, gap = 0) => ({ rx: (y) => BODY.rx(y + y0) + gap, rz: (y) => BODY.rz(y + y0) + gap, ox: (y) => BODY.ox(y + y0) });

const PROPORTIONS = {
  hipHeight: 0.95, pelvisDrop: 0.055, hipWidth: 0.088, thighRatio: 0.515, ankleHeight: 0.078, footLength: 0.125, footDrop: 0.05,
  toeLength: 0.07, heelLength: 0.058, spine: 0.1, chest: 0.155, neck: 0.24, head: 0.09, shoulderHeight: 0.19, clavicleRoot: 0.028,
  clavicle: 0.162, shoulderBack: 0.012, upperArm: 0.295, foreArm: 0.255, hand: 0.078, palm: 0.02,
};
// bind heights of the torso bones for these proportions
const Y_HIPS = 1.005, Y_SPINE = 1.105, Y_CHEST = 1.26;

const chain = (base, n) => Array.from({ length: n }, (_, k) => base + (k + 1));
const RIB = { R: chain('ribbonR', 5), L: chain('ribbonL', 5), aR: chain('armRibbonR', 3), aL: chain('armRibbonL', 3) };
const ribbonBones = (names, parent, at, step) => names.map((name, k) => ({ name, parent: k ? names[k - 1] : parent, at: k ? step : at }));

const TAIL = { cols: 5, rows: 13, length: 1.0, flare: 0.2, thickness: 0.01, damping: 0.03, margin: 0.028, wind: 1, stretch: 1, bend: 0.3 };
// rest folds (model x = forward; none at the pinned row): one soft pleat wave across each tail, deepening toward the
// hem, and a box pleat down the tabard (centre forward, sides falling back over the thighs): the cloth hangs with depth
// instead of as a flat sheet
const tailFold = (u, v) => 0.024 * Math.sin(2 * Math.PI * u) * Math.pow(v, 0.7);
const tabardFold = (u, v) => [-0.017 * Math.cos(2 * Math.PI * u) * Math.pow(v, 0.7), 0, 0];

export const iska = {
  id: 'iska',
  name: 'ISKA',
  title: 'Froststar Oracle',
  idle: 'demo.idle',
  proportions: PROPORTIONS,
  glow: GLOW,
  materials: {
    plate: { envMapIntensity: 0.8, bump: 0.9, glow: GLOW, rim: [0.16, 0.24, 0.42, 3.4], wear: [0.55, 0.5, 0.22, 0], wearColor: [0.8, 0.84, 0.9], grimeColor: [0.42, 0.47, 0.6] },
    suit: { envMapIntensity: 0.75, bump: 1, rim: [0.16, 0.22, 0.4, 3.0], wear: [0.25, 0.55, 0.4, 0], wearColor: [0.3, 0.32, 0.4] },
    blade: { ...WEAPON_MATERIALS.crescents },
  },
  bones: [
    { name: 'tassetR', parent: 'hips', at: [0.012, 0.022, 0.128] },
    { name: 'tassetL', parent: 'hips', at: [0.012, 0.022, -0.128] },
    ...ribbonBones(RIB.R, 'hips', [-0.045, 0.03, 0.13], [0, -0.125, 0]),
    ...ribbonBones(RIB.L, 'hips', [-0.045, 0.03, -0.13], [0, -0.125, 0]),
    ...ribbonBones(RIB.aR, 'upperArmTwistR', [-0.012, -0.11, 0.038], [0, -0.1, 0]),
    ...ribbonBones(RIB.aL, 'upperArmTwistL', [-0.012, -0.11, -0.038], [0, -0.1, 0]),
  ],
  springs: [
    { bones: ['tassetR'], stiffness: 210, damping: 12, gravity: 0.4, tip: [0.0, -0.17, 0.01], radius: 0.03, limit: 34 },
    { bones: ['tassetL'], stiffness: 210, damping: 12, gravity: 0.4, tip: [0.0, -0.17, -0.01], radius: 0.03, limit: 34 },
    { bones: RIB.R, stiffness: 20, damping: 2.4, gravity: 0.85, tip: [0, -0.125, 0], radius: 0.016, limit: 72 },
    { bones: RIB.L, stiffness: 20, damping: 2.4, gravity: 0.85, tip: [0, -0.125, 0], radius: 0.016, limit: 72 },
    { bones: RIB.aR, stiffness: 26, damping: 2.8, gravity: 0.8, tip: [0, -0.1, 0], radius: 0.014, limit: 70 },
    { bones: RIB.aL, stiffness: 26, damping: 2.8, gravity: 0.8, tip: [0, -0.1, 0], radius: 0.014, limit: 70 },
  ],
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
  ],
  cloth: [
    // twin cape tails hung under the shoulder mantle (left tail: outer edge u = 0; right tail: outer edge u = 1)
    clothSpec({
      name: 'tailL', slot: 'suit', ...TAIL,
      top: [['chest', [-0.114, 0.104, -0.118]], ['chest', [-0.134, 0.097, -0.064]], ['chest', [-0.142, 0.092, -0.012]]],
      drape: [-0.16, -1, -0.07], offset: (u, v) => [-0.03 * Math.sin(v * Math.PI) - 0.02 * v + tailFold(u, v), 0, -0.02 * v * (1 - u)],
      outer: S_.cloth, inner: S_.lining,
    }),
    clothSpec({
      name: 'tailR', slot: 'suit', ...TAIL,
      top: [['chest', [-0.142, 0.092, 0.012]], ['chest', [-0.134, 0.097, 0.064]], ['chest', [-0.114, 0.104, 0.118]]],
      drape: [-0.16, -1, 0.07], offset: (u, v) => [-0.03 * Math.sin(v * Math.PI) - 0.02 * v + tailFold(1 - u, v), 0, 0.02 * v * u],
      outer: S_.cloth, inner: S_.lining,
    }),
    // long front tabard from the belt, pointed hem
    clothSpec({
      name: 'tabard', slot: 'suit',
      top: [['hips', [0.116, 0.035, -0.058]], ['hips', [0.128, 0.035, 0]], ['hips', [0.116, 0.035, 0.058]]],
      cols: 5, rows: 10, length: 0.66, drape: [0.1, -1, 0], flare: 0.34, thickness: 0.009, offset: tabardFold,
      damping: 0.04, margin: 0.022, wind: 0.7, outer: S_.cloth, inner: S_.lining,
    }),
  ],
  weapons: WEAPON_SPECS.crescents,
  sockets: {
    eyes: ['head', [0.118, 0.078, 0]],          // between the frost eyes, on the mask (ULT close-up flare)
    crest: ['head', [0.088, 0.215, 0]],         // the star in the circlet's crescent
    crystal: ['deltoidR', [-0.04, 0.12, 0.045]], // tip of the crystal cluster on the right spaulder
    heart: ['chest', [0.134, 0.07, 0]],         // the star medallion on the sternum
  },

  /** Glow control for a created character: char.glow (flare / set / gain), advanced by char.update. */
  attach(char) { return attachGlow(char, GLOW); },

  build(kit, S, rig) {
    // quality: the rig scales cloth grids by ctx.quality.cloth (low tier 0.5), so a coarser tail grid means the low tier:
    // build the lighter variant (fewer lamellae / scales / stitches, no laces / rivets, coarser hood, collar and cloth)
    const lite = (clothGrid(rig, 'tailL')?.R ?? TAIL.rows) < TAIL.rows;

    // ---- bodysuit (smooth skinned, indigo) -----------------------------------------------------------------------------
    kit.loft('suit', {
      path: [['hips', [0, -0.13, 0]], ['hips', [0, -0.03, 0]], ['spine', [0, 0, 0]], ['chest', [0, 0, 0]], ['chest', [0, 0.15, 0]], ['neck', [0.005, 0.02, 0]], ['neck', [0.01, 0.11, 0]]],
      weights: [[0, 'hips'], [1.3, 'hips'], [2.0, 'spine'], [2.5, 'spine'], [3.1, 'chest'], [4.3, 'chest'], [5.0, 'neck'], [5.6, 'neck'], [6, 'head']],
      rx: [[0, 0.08], [1, 0.112], [2, 0.092], [3, 0.106], [4, 0.098], [5, 0.05], [6, 0.046]],
      rz: [[0, 0.1], [1, 0.156], [2, 0.115], [3, 0.13], [4, 0.136], [5, 0.054], [6, 0.046]],
      ox: [[0, -0.006], [2, -0.008], [3, 0.004], [4, 0.002], [5, 0.0]],
      n: 2.3, segs: [20, 22],
    }, loftLook(S_.bodysuit));
    kit.loftPair('suit', {
      path: [['shoulderR', [-0.004, -0.04, 0.1]], ['upperArmR', [0, -0.01, 0]], ['upperArmR', [0, -0.15, 0]], ['foreArmR', [0, 0, 0]], ['foreArmR', [0, -0.13, 0]], ['handR', [0, 0, 0]], ['handR', [0, -0.03, 0]]],
      weights: [[0, 'shoulderR'], [0.7, 'deltoidR'], [1.15, 'upperArmTwistR'], [1.9, 'upperArmR'], [2.75, 'upperArmR'], [3, 'elbowR'], [3.25, 'foreArmR'], [3.6, 'foreArmR'], [4.4, 'foreArmTwistR'], [4.85, 'foreArmTwistR'], [5.15, 'handR']],
      rx: [[0, 0.04], [1, 0.04], [2, 0.036], [3, 0.032], [4, 0.034], [5, 0.027], [6, 0.026]],
      rz: [[0, 0.042], [1, 0.042], [2, 0.038], [3, 0.034], [4, 0.036], [5, 0.029], [6, 0.027]],
      segs: [12, 26],
    }, loftLook(S_.sleeve));
    kit.loftPair('suit', {
      path: [['hips', [0, -0.035, 0.07]], ['thighR', [0, 0, 0]], ['thighR', [0, -0.23, 0]], ['shinR', [0, 0, 0]], ['shinR', [0, -0.21, 0]], ['footR', [0, 0, 0]], ['footR', [0, -0.035, 0]]],
      weights: [[0, 'hips'], [0.75, 'hips'], [1.3, 'thighR'], [2.75, 'thighR'], [3, 'kneeR'], [3.25, 'shinR'], [4.8, 'shinR'], [5.15, 'footR']],
      rx: [[0, 0.09], [1, 0.088], [2, 0.072], [3, 0.05], [4, 0.054], [5, 0.035], [6, 0.033]],
      rz: [[0, 0.088], [1, 0.085], [2, 0.068], [3, 0.048], [4, 0.05], [5, 0.034], [6, 0.032]],
      ox: [[0, 0], [4, -0.008], [5, 0]],
      segs: [12, 24],
    }, loftLook(S_.sleeve));

    // ---- head: under-face, oracle mask, frost eyes, mail veil, hood + mantle, circlet ------------------------------------
    put(kit, 'suit', 'head', K.headBase(), S_.under);
    const M = K.oracleMask();
    put(kit, 'plate', 'head', M.brow, L.mask);
    put(kit, 'plate', 'head', M.lower, L.mask);
    put(kit, 'plate', 'head', M.eyes, L.eye, { glow: K.eyeGlow(1) });
    put(kit, 'plate', 'head', M.tears, L.star);
    put(kit, 'plate', 'head', M.arcs, L.starDim);
    put(kit, 'suit', 'head', M.veil, S_.hood);
    const H = K.hood(lite ? { nu: 22, nv: 12 } : {});
    const hw = K.hoodWeights(kit);
    putSkinned(kit, 'suit', H.hood, S_.hood, hw, { frame: 'head' });
    putSkinned(kit, 'suit', H.hem, S_.hood, hw, { frame: 'head' });
    const mh = [];
    for (let i = 0; i <= 48; i++) mh.push([0.02 + (i / 48) * 0.96, 0.955]);
    putSkinned(kit, 'plate', strip(H.S, mh, { width: 0.014, lift: 0.0012, bead: 0.001, smooth: 1 }), L.hoodTrim, hw, { frame: 'head' });
    for (const u of [0.028, 0.972]) {
      const path = [];
      for (let i = 0; i <= 26; i++) path.push([u, H.vArch + 0.03 + (i / 26) * (0.975 - H.vArch - 0.03)]);
      putSkinned(kit, 'plate', strip(H.S, path, { width: 0.011, lift: 0.0012, bead: 0.001, smooth: 2 }), L.hoodTrim, hw, { frame: 'head' });
    }
    const C = K.circlet();
    put(kit, 'plate', 'head', C.band, L.silverEngr);
    put(kit, 'plate', 'head', C.crest, L.silver);
    put(kit, 'plate', 'head', C.star, L.star);
    put(kit, 'plate', 'head', C.drops, L.crystal);
    if (!lite) put(kit, 'plate', 'head', C.studs, L.rivet);

    // ---- high collar (skinned chest -> neck) ------------------------------------------------------------------------------
    const neckY = kit.bonePos('neck')[1];
    const collarW = (x, y) => { const t = sstep(neckY - 0.03, neckY + 0.03, y); return [['chest', 1 - t], ['neck', t]]; };
    const Co = K.highCollar(lite ? { nu: 28 } : {});
    putSkinned(kit, 'plate', Co.collar, L.silver, collarW, { frame: 'neck' });
    const cb = [];
    for (let i = 0; i <= 40; i++) cb.push([0.03 + (i / 40) * 0.94, 0.62]);
    putSkinned(kit, 'plate', stripOn(Co.collarS, cb, 0.01), L.silverEngr, collarW, { frame: 'neck' });
    putSkinned(kit, 'plate', Co.flare, L.silver, collarW, { frame: 'neck' });
    putSkinned(kit, 'plate', Co.clasp, L.silver, collarW, { frame: 'neck' });
    putSkinned(kit, 'plate', Co.claspGem, L.crystal, collarW, { frame: 'neck' });

    // ---- bodice: sculpted breastplate with a crescent inlay, backplate ---------------------------------------------------
    const BC = A.torsoShape({
      rx: BY.map((y, i) => [y - Y_CHEST, BODY.rx(y)]), rz: BY.map((y) => [y - Y_CHEST, BODY.rz(y)]), ox: BY.map((y) => [y - Y_CHEST, BODY.ox(y)]), n: 2.3,
    });
    const bust = (u, v) => {
      const a = lerp(-100, 100, u);
      const cup = (c) => Math.exp(-(((a - c) / 21) ** 2) - (((v - 0.55) / 0.22) ** 2));
      return 0.019 * (cup(25) + cup(-25)) * (1 - 0.5 * Math.exp(-((a / 7) ** 2)));
    };
    const breast = A.breastplate({ body: BC, yTop: 0.205, yBot: -0.08, a0: -100, a1: 100, ridgeH: 0.003, swell: 0, bulge: bust, grow: 0.012, thick: 0.0048, edgeR: 0.0036, nu: 28, nv: 10, neck: { dip: 0.062, k: 5 }, arm: { drop: 0.075, from: 48, to: 92 }, roll: { v0: 0.004, v1: 0.0035 }, point: 0.03, pointK: 8 });
    put(kit, 'plate', 'chest', breast, L.silver);
    const bs = breast.userData;
    // engraved neckline band + starlight crescent over the sternum
    const nb = [];
    for (let i = 0; i <= 40; i++) nb.push([0.04 + (i / 40) * 0.92, 0.075]);
    put(kit, 'plate', 'chest', stripOn(bs, nb, 0.012), L.silverEngr);
    const lb = [];
    for (let i = 0; i <= 40; i++) lb.push([0.06 + (i / 40) * 0.88, 0.9]);
    put(kit, 'plate', 'chest', stripOn(bs, lb, 0.009), L.silverEngr);
    // sternum medallion: raised silver boss with a glowing four-point star, frost vines flowing down over the bodice
    const mf = bs.normalAt(0.5, 0.3);
    const orient = (g, lift) => { g.applyMatrix4(new THREE.Matrix4().compose(mf.p.clone().addScaledVector(mf.n, lift), new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, 1, 0), mf.n), new THREE.Vector3(1, 1, 1))); return g; };
    put(kit, 'plate', 'chest', orient(lathe([[0, 0.0075], [0.017, 0.0068], [0.024, 0.0042], [0.027, 0.0012], [0.027, 0], [0, 0]], { segs: 20, hard: [2, 3] }), 0.0), L.silverEngr);
    const mstar = extrude(K.starShape(0.02, 0.0058, 4), { depth: 0.004, bevel: 0.0014, bevelSegs: 1, curveSegs: 1 });
    mstar.rotateX(-90 * DEG);
    put(kit, 'plate', 'chest', orient(mstar, 0.0085), L.star);
    for (const sd of lite ? [] : [1, -1]) {
      put(kit, 'plate', 'chest', A.inlayLine(breast, [[0.5 + sd * 0.035, 0.36], [0.5 + sd * 0.075, 0.48], [0.5 + sd * 0.07, 0.62], [0.5 + sd * 0.11, 0.78], [0.5 + sd * 0.17, 0.84]], { width: 0.0024, n: 14 }), L.starDim);
    }
    const back = A.backplate({ body: BC, yTop: 0.19, yBot: -0.075, grow: 0.011, thick: 0.0045, edgeR: 0.0034, roll: { v0: 0.004 } });
    put(kit, 'plate', 'chest', back, L.blued);

    // ---- lamellar waist (spine): four laced rows, hourglass ------------------------------------------------------------------
    for (let k = 0; k < 4; k++) {
      const y0 = 0.135 - k * 0.04;
      const row = K.lamellarRow({ y0, h: 0.05, count: lite ? 11 : 14, a0: -168, a1: 168, ...bodyIn(Y_SPINE, 0), gap: 0.007 + 0.002 * k, point: 0.4, lace: !lite });
      put(kit, 'plate', 'spine', row.plates, k % 2 ? L.blued : L.lamella);
      if (row.lace) put(kit, 'plate', 'spine', row.lace, L.lace);
    }

    // ---- belt, buckle, tassets (springs) ------------------------------------------------------------------------------------
    const by = 0.032, bR = bodyIn(Y_HIPS, 0.012);
    put(kit, 'plate', 'hips', A.belt({ y: by, rx: bR.rx(by), rz: bR.rz(by), ox: bR.ox(by), h: 0.032, t: 0.0048, tilt: -0.008 }), L.leather);
    const buckle = extrude(K.starShape(0.03, 0.012, 4), { depth: 0.006, bevel: 0.0022, bevelSegs: 2, curveSegs: 1 });
    put(kit, 'plate', 'hips', buckle, L.silver, { rot: [0, 90, 0], at: [bR.ox(by) + bR.rx(by) + 0.012, by, 0] });
    const bgem = K.crystal({ r: 0.0065, h: 0.008, tip: 0.008, base: 0.003 });
    put(kit, 'plate', 'hips', bgem, L.crystal, { rot: [0, 0, -90], at: [bR.ox(by) + bR.rx(by) + 0.017, by, 0] });
    for (const s of ['R', 'L']) {
      const tz = s === 'R' ? 1 : -1;
      // scales arranged around the hip, authored in the tasset frame (hips centre at (-0.012, -0.022, -0.128 z))
      const hz = -0.128 * tz, ty = Y_HIPS + 0.022;
      const sc = K.scaleRows({
        rows: lite ? 2 : 3, perRow: 3, y0: 0.0, rowStep: 0.05, h: 0.074, a0: tz > 0 ? 56 : -124, a1: tz > 0 ? 124 : -56,
        rx: (y) => BODY.rx(y + ty) + 0.014 - y * 0.05, rz: (y) => BODY.rz(y + ty) + 0.016 - y * 0.1, ox: (y) => BODY.ox(y + ty) - 0.012,
        oz: () => hz, gap: 0.0, flare: 0.004, ridge: 0.0022, n: 2.2,
      });
      put(kit, 'plate', 'tasset' + s, sc, L.scale);
    }

    // ---- shoulders: crescent spaulders, crystal cluster on the right ---------------------------------------------------------
    const SP = K.crescentSpaulder({ R: 0.08, nu: lite ? 16 : 22 });
    putPair(kit, 'plate', 'deltoid', SP.crescent, L.crescent);
    putPair(kit, 'plate', 'deltoid', SP.cap, L.blued);
    putPair(kit, 'plate', 'deltoid', SP.trim, L.silverEngr);
    SP.lames.forEach((g, k) => putPair(kit, 'plate', 'deltoid', g, k ? L.silver : L.blued));
    if (!lite) putPair(kit, 'plate', 'deltoid', SP.rivets, L.rivet);
    const cl = K.crystalCluster([[0.07, -18, 22, 0.009], [0.052, 8, 38, 0.0075, 0.4], [0.04, -34, 8, 0.006, 0.9], [0.032, 20, 52, 0.0055, 1.3]]);
    put(kit, 'plate', 'deltoidR', cl, L.crystal, { at: [-0.03, 0.07, 0.045] });

    // ---- arms ------------------------------------------------------------------------------------------------------------------
    // rerebrace: a blued half-tube with an outer ridge below the engraved band (the upper arm no longer reads as a bare tube)
    const reb = A.hoop({ y0: -0.142, y1: -0.25, a0: -60, a1: 160, rx: [[0, 0.045], [1, 0.041]], rz: [[0, 0.047], [1, 0.043]], n: 2.1, nu: lite ? 8 : 10, nv: 2, thick: 0.004, edgeR: 0.003, edgeSegs: 2, roll: { v1: 0.0026 }, rollSegs: 4, ridge: { at: 80, h: 0.0035, w: 22 }, bot: (a) => 0.012 * Math.pow(Math.max(0, Math.sin(a * DEG)), 3) });
    putPair(kit, 'plate', 'upperArmTwist', reb, L.blued);
    const band = A.hoop({ y0: -0.118, y1: -0.14, closed: true, rx: 0.041, rz: 0.044, n: 2.1, nu: 16, nv: 1, thick: 0.004, edgeR: 0.003, roll: { v1: 0.0026 } });
    putPair(kit, 'plate', 'upperArmTwist', band, L.silverEngr);
    const cou = A.couter({ r: 0.04, wing: 0.05 });
    putPair(kit, 'plate', 'elbow', cou.cop, L.silver);
    const vam = K.crescentVambrace({ r: 0.04, y0: 0.1, y1: -0.112 });
    putPair(kit, 'plate', 'foreArmTwist', vam, L.silver);
    putPair(kit, 'plate', 'foreArmTwist', A.inlayLine(vam, [[0.25, 0.12], [0.22, 0.4], [0.26, 0.66], [0.25, 0.8]], { width: 0.0024 }), L.star);
    putPair(kit, 'plate', 'foreArmTwist', starOn(vam.userData, 0.25, 0.86, 0.011), L.star);
    const ring = (v) => Array.from({ length: 17 }, (_, i) => [i / 16, v]);
    if (!lite) for (const v of [0.07, 0.93]) putPair(kit, 'plate', 'foreArmTwist', strip(vam.userData, ring(v), { width: 0.007, lift: 0.0009, bead: 0.0008, smooth: 1 }), L.silverEngr);
    const gl = A.gauntlet();
    const gs = { scale: 0.86 };
    putPair(kit, 'plate', 'hand', gl.cuff, L.silver, { scale: [0.74, 0.8, 0.74], at: [0, 0.004, 0] });
    putPair(kit, 'plate', 'hand', gl.back, L.silverEngr, gs);
    putPair(kit, 'plate', 'hand', gl.palm, L.leather, gs);
    putPair(kit, 'plate', 'fingers', gl.fingers, L.blued, gs);
    putPair(kit, 'plate', 'fingerTips', gl.tips, L.silver, gs);
    putPair(kit, 'plate', 'thumb', gl.thumb, L.blued, gs);

    // ---- legs ------------------------------------------------------------------------------------------------------------------
    const cuisse = A.hoop({
      y0: -0.25, y1: -0.405, a0: -78, a1: 96, rx: [[0, 0.075], [1, 0.062]], rz: [[0, 0.072], [1, 0.06]], ox: 0.006, n: 2.15,
      top: (a) => 0.07 * Math.pow(Math.max(0, Math.cos((a - 8) * DEG)), 4), nu: 18, nv: 5, thick: 0.0045, edgeR: 0.0034, roll: { v0: 0.0034 },
      ridge: { at: 10, h: 0.005, w: 18 },
    });
    putPair(kit, 'plate', 'thigh', cuisse, L.silver);
    const pol = A.poleyn({ r: 0.05, wing: 0.056 });
    putPair(kit, 'plate', 'knee', pol.cop, L.silver);
    const greave = K.oracleGreave({ r: 0.05, y0: -0.035, y1: -0.385 });
    putPair(kit, 'plate', 'shin', greave, L.silver);
    if (!lite) {
      for (const v of [0.1, 0.9]) putPair(kit, 'plate', 'shin', strip(greave.userData, ring(v), { width: 0.008, lift: 0.0009, bead: 0.0008, smooth: 1 }), L.silverEngr);
      putPair(kit, 'plate', 'shin', A.inlayLine(greave, [[0.5, 0.16], [0.5, 0.5], [0.5, 0.78]], { width: 0.0022, n: 10 }), L.starDim);
      putPair(kit, 'plate', 'shin', starOn(greave.userData, 0.5, 0.82, 0.01), L.star);
    }
    const sab = A.sabaton({ P: rig.P, width: 0.04, scale: 0.92, point: 0.8 });
    sab.lames.forEach((x, k) => putPair(kit, 'plate', 'foot', x, k % 2 ? L.blued : L.silver));
    putPair(kit, 'plate', 'foot', sab.heel, L.blued);
    putPair(kit, 'plate', 'toe', sab.toe, L.silver);
    putPair(kit, 'plate', 'foot', sab.sole, L.leather);
    putPair(kit, 'plate', 'toe', sab.toeSole, L.leather);

    // ---- ribbons (spring chains): flat silk bands with crystal weights ----------------------------------------------------------
    for (const [names, tip, w] of [[RIB.R, [0, -0.125, 0], 0.021], [RIB.L, [0, -0.125, 0], 0.021], [RIB.aR, [0, -0.1, 0], 0.017], [RIB.aL, [0, -0.1, 0], 0.017]]) {
      const n = names.length;
      kit.loft('suit', {
        path: [...names.map((b) => [b, [0, 0, 0]]), [names[n - 1], tip]],
        weights: names.map((b, k) => [k, b]),
        rx: w, rz: 0.0022, n: 2, segs: [6, n * 5], caps: [true, true],
      }, loftLook(S_.ribbon));
      const c = K.crystal({ r: 0.0075, h: 0.016, tip: 0.012, base: 0.005 });
      c.rotateZ(180 * DEG);
      put(kit, 'plate', names[n - 1], c, L.crystal, { at: [0, tip[1] - 0.004, 0] });
    }

    // ---- tailored cloth: twin tails + tabard ------------------------------------------------------------------------------------
    const tL = clothSurface(kit, rig, 'tailL', { anchor: 'chest', thickness: TAIL.thickness });
    const tR = clothSurface(kit, rig, 'tailR', { anchor: 'chest', thickness: TAIL.thickness });
    const tb = clothSurface(kit, rig, 'tabard', { anchor: 'hips', thickness: 0.009 });
    const tailStars = (outer) => (lite ? [0.5, 0.72] : [0.42, 0.58, 0.74]).map((b, k) => ({ a: outer === 0 ? 0.24 : 0.76, b, r: 0.022 - k * 0.002 }));
    const res = lite ? { na: 6, nb: 11 } : { na: 8, nb: 18 };
    panelCloth(kit, tL, { ...res, hem: (a) => 1 - 0.2 * Math.pow(a, 1.3), hemBand: 0.07, sideBand: 0.11, bandSides: 'left', body: S_.cloth, lining: S_.lining, border: L.embroidery, starLook: L.star, stars: tailStars(0) });
    panelCloth(kit, tR, { ...res, hem: (a) => 1 - 0.2 * Math.pow(1 - a, 1.3), hemBand: 0.07, sideBand: 0.11, bandSides: 'right', body: S_.cloth, lining: S_.lining, border: L.embroidery, starLook: L.star, stars: tailStars(1) });
    panelCloth(kit, tb, { na: res.na, nb: lite ? 9 : 14, hem: (a) => 1 - 0.17 * Math.pow(Math.abs(2 * a - 1), 1.2), hemBand: 0.09, sideBand: 0.1, body: S_.cloth, lining: S_.lining, border: L.embroidery, starLook: L.star,
      stars: lite ? [{ a: 0.5, b: 0.5, r: 0.024 }] : [{ a: 0.5, b: 0.3, r: 0.018 }, { a: 0.5, b: 0.5, r: 0.024 }, { a: 0.5, b: 0.7, r: 0.018 }] });
    // tail tips: small crescent weights
    const weight = K.crystal({ r: 0.006, h: 0.014, tip: 0.01, base: 0.004 });
    weight.rotateZ(180 * DEG);
    clothCharm(kit, tL, 0.0, 1.0, weight, L.crystal, { offset: 0.0 });
    clothCharm(kit, tR, 1.0, 1.0, weight, L.crystal, { offset: 0.0 });
    clothCharm(kit, tb, 0.5, 0.995, weight, L.crystal, { offset: 0.0 });

    // ---- twin crescent blades (a touch more blade roughness: the mirror polish threw large warm glints under key lights) --------
    crescents(kit, { slot: 'blade', looks: { blade: { ...WEAPON_LOOKS.crescents.blade, rough: 0.2 } } });

    // last: drop the rig's default (rectangular) cloth meshes, the tailored panels replace them
    suppressRigCloth(kit, rig, ['tailL', 'tailR', 'tabard']);
  },
};

/** Raised strip on a plate surface (inlays, engraved bands). */
function stripOn(surf, uv, width) { return strip(surf, uv, { width, lift: 0.0009, bead: 0.0008, smooth: 2 }); }

/** Small raised four-point star on a plate surface at (u, v), outer radius r (m). */
function starOn(surf, u, v, r) {
  const f = surf.normalAt(u, v), out = [];
  const du = surf.normalAt(Math.min(1, u + 0.01), v).p.distanceTo(f.p) / 0.01, dv = surf.normalAt(u, Math.min(1, v + 0.01)).p.distanceTo(f.p) / 0.01;
  for (const [a, b, k] of [[0, 1, 1], [0, -1, 1], [1, 0, 0.6], [-1, 0, 0.6]]) out.push(strip(surf, [[u, v], [u + (a * r * k) / du, v + (b * r * k) / dv]], { width: 0.0026 * k, lift: 0.0008, bead: 0.0008, smooth: 3 }));
  return merge(out);
}

/** Look -> kit.loft options (lofts carry no per-vertex cavity data). */
function loftLook(look) {
  return { color: look.color, rough: look.rough, metal: look.metal, detail: surfDetail(look.set ?? 0, look.amt ?? 1), cavity: 1 };
}

export default iska;
