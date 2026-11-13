// Reference outfits: three murim archetypes built only from the kit, on any hero's rig (proportions, colliders, weapons
// and grip angle are taken from a base design, so clips and sockets keep working). They are the kit's test dummies in
// the art lab (#design=heavy | slender | tall) and worked examples for the hero artists: copy the parts you need.
//
//   heavy    charred silk robe, flame brocade, beast-face pauldron, demon half-mask, topknot + loose mane, headband,
//            lamellar waist guards, gourd, one wide and one fitted sleeve
//   slender  moon-white robe over indigo, wave brocade, long split skirt, wide sleeves, wide veiled bamboo hat, silver
//            half-mask, long bound tail with a pin, jade pendant
//   tall     ink and violet robe, fret brocade, lamellar cuirass and spaulders, deep cone hat, face wrap, braided queue,
//            bracers, a verlet coat tail with a brocade hem
//
// Slots: `robe` (cut-out, double sided: cloth, hair, veil), `gear` (everything hard), `blade` (the weapon).

import { attachGlow } from '../materials.js';
import { put, putPair, putSkinned, weightsOf, mirror, band as bandOf } from './geo.js';
import { MURIM, MOTIF } from './looks.js';
import { clothSpec, clothSurface, clothBorder } from './cloth.js';
import * as M from './murim.js';
import * as H from './head.js';
import { buildWeapon, WEAPON_SPECS, WEAPON_MATERIALS, spearTasselRig } from '../weapons.js';
import { DEFAULT_PROPORTIONS, bodyScale } from '../skeleton.js';

const PAL = {
  heavy: {
    glow: { inlay: [6.2, 2.0, 0.34], vein: [3.2, 0.8, 0.09], eye: [9.5, 3.4, 0.7] },
    robe: [0.016, 0.014, 0.014], inner: [0.17, 0.012, 0.008], sash: [0.1, 0.008, 0.006], trim: [0.02, 0.012, 0.01], thread: [0.5, 0.26, 0.07], lace: [0.3, 0.03, 0.012],
    pants: [0.03, 0.026, 0.024], hair: [0.014, 0.012, 0.012], rim: [0.3, 0.38, 0.6, 3], motif: MOTIF.flame, emblem: MOTIF.sun, width: 1.12, depth: 1.1, weapon: 'greatsword',
  },
  slender: {
    glow: { inlay: [1.5, 4, 8], vein: [0.5, 1.6, 3.4], eye: [2.2, 5, 9] },
    robe: [0.3, 0.32, 0.36], inner: [0.014, 0.02, 0.085], sash: [0.02, 0.03, 0.11], trim: [0.03, 0.04, 0.12], thread: [0.62, 0.64, 0.68], lace: [0.1, 0.14, 0.32],
    pants: [0.2, 0.21, 0.24], hair: [0.012, 0.012, 0.016], rim: [0.2, 0.28, 0.46, 3.2], motif: MOTIF.wave, emblem: MOTIF.moon, width: 0.86, depth: 0.86, weapon: 'crescents',
  },
  tall: {
    glow: { inlay: [5, 3.5, 9], vein: [2.4, 1.6, 5.0], eye: [6, 4.2, 10] },
    robe: [0.014, 0.012, 0.02], inner: [0.06, 0.02, 0.12], sash: [0.05, 0.02, 0.1], trim: [0.016, 0.012, 0.024], thread: [0.5, 0.36, 0.12], lace: [0.16, 0.06, 0.3],
    pants: [0.02, 0.018, 0.026], hair: [0.012, 0.011, 0.014], rim: [0.28, 0.3, 0.5, 3.2], motif: MOTIF.fret, emblem: MOTIF.thunder, width: 1.0, depth: 0.98, weapon: 'spear',
  },
};

/**
 * A reference outfit on a hero's rig.
 * @param {'heavy'|'slender'|'tall'} kind
 * @param {object} base  the design whose rig it borrows: { proportions, colliders, gripAngle, idle } (weapons are the
 *   kit's own: greatsword / crescents / spear, as the heroes use)
 */
export function mannequin(kind = 'heavy', base = {}) {
  const C = PAL[kind] || PAL.heavy;
  const P = { ...DEFAULT_PROPORTIONS, ...(base.proportions || {}) }, K = bodyScale(P);
  const silk = (c, extra) => ({ ...MURIM.silk, color: c, wear: 0.3, ...extra });
  const trim = (m, g = 0.12) => ({ look: { ...MURIM.trim, color: C.trim }, code: m + g });
  const wy = 0.085 * K;                                      // waist (sash centre) above the hips pivot
  const rx = 0.128 * K * C.depth, rz = 0.166 * K * C.width;
  const skirtLen = (kind === 'slender' ? 0.82 : kind === 'tall' ? 0.5 : 0.56) * K;
  // ---- rigs of everything that swings -------------------------------------------------------------------------------------
  const SK = {
    fr: M.skirtRig('skFr', { a0: 3, a1: 96, y: wy - 0.05 * K, len: skirtLen, rx, rz, follow: 'thighR', k: 0.66 }),
    fl: M.skirtRig('skFl', { a0: -96, a1: -3, y: wy - 0.05 * K, len: skirtLen, rx, rz, follow: 'thighL', k: 0.66 }),
    br: M.skirtRig('skBr', { a0: 92, a1: 181, y: wy - 0.05 * K, len: skirtLen * 1.04, rx, rz, n: 3 }),
    bl: M.skirtRig('skBl', { a0: -181, a1: -92, y: wy - 0.05 * K, len: skirtLen * 1.04, rx, rz, n: 3 }),
  };
  if (kind === 'tall') { delete SK.br; delete SK.bl; }      // the coat tail (verlet) covers the back
  const sashA = M.hang('sashA', 'hips', [rx * 0.62, wy - 0.02 * K, rz * 0.82], { n: 3, len: 0.46 * K, stiffness: 20, damping: 2.6, radius: 0.03 });
  const sashB = M.hang('sashB', 'hips', [rx * 0.5, wy - 0.02 * K, rz * 0.9], { n: 3, len: 0.36 * K, stiffness: 22, damping: 2.8, radius: 0.03 });
  const rigs = [...Object.values(SK), sashA, sashB];
  const R = { SK, sashA, sashB };
  if (kind === 'heavy') {
    R.mane = [M.hang('maneL', 'head', [-0.075 * K, 0.06 * K, -0.055 * K], { n: 2, len: 0.3 * K, dir: [-0.35, -1, -0.12], stiffness: 26, damping: 3, radius: 0.03 }),
      M.hang('maneC', 'head', [-0.095 * K, 0.05 * K, 0], { n: 2, len: 0.34 * K, dir: [-0.45, -1, 0], stiffness: 26, damping: 3, radius: 0.03 }),
      M.hang('maneR', 'head', [-0.075 * K, 0.06 * K, 0.055 * K], { n: 2, len: 0.3 * K, dir: [-0.35, -1, 0.12], stiffness: 26, damping: 3, radius: 0.03 })];
    R.band = M.hang('hband', 'head', [-0.1 * K, 0.115 * K, 0.02 * K], { n: 2, len: 0.2 * K, dir: [-0.6, -1, 0.1], stiffness: 18, damping: 2.4, radius: 0.015, collide: false });
    R.gourd = M.hang('gourd', 'hips', [-0.02 * K, wy - 0.07 * K, -rz * 1.08], { n: 1, len: 0.06, stiffness: 60, damping: 5, limit: 40, radius: 0.03 });
    R.drapeL = M.hang('drapeL', 'foreArmL', [-0.05 * K, -0.2 * K, 0], { n: 2, len: 0.24 * K, dir: [-0.3, -1, 0], stiffness: 14, damping: 3, gravity: 1, limit: 80, radius: 0.025 });
    rigs.push(...R.mane, R.band, R.gourd, R.drapeL);
  } else if (kind === 'slender') {
    R.tail = M.hang('tail', 'head', [-0.1 * K, 0.17 * K, 0], { n: 5, len: 0.78 * K, dir: [-0.5, -1, 0], stiffness: 20, damping: 2.6, gravity: 0.95, limit: 62, radius: 0.028 });
    R.veil = H.veilRig('veil', { R: 0.285 * K, y: 0.118 * K, len: 0.24 * K, chains: 6, tilt: -6 });
    R.pend = M.hang('pend', 'hips', [rx * 0.2, wy - 0.06 * K, rz * 1.1], { n: 2, len: 0.12, stiffness: 40, damping: 4, limit: 50, radius: 0.02 });
    R.drapeR = M.hang('drapeR', 'foreArmR', [-0.05 * K, -0.2 * K, 0], { n: 2, len: 0.26 * K, dir: [-0.3, -1, 0], stiffness: 14, damping: 3, gravity: 1, limit: 80, radius: 0.025 });
    R.drapeL = M.hang('drapeL', 'foreArmL', [-0.05 * K, -0.2 * K, 0], { n: 2, len: 0.26 * K, dir: [-0.3, -1, 0], stiffness: 14, damping: 3, gravity: 1, limit: 80, radius: 0.025 });
    rigs.push(R.tail, R.veil, R.pend, R.drapeR, R.drapeL);
  } else {
    R.queue = M.hang('queue', 'head', [-0.1 * K, 0.04 * K, 0], { n: 4, len: 0.52 * K, dir: [-0.3, -1, 0], stiffness: 26, damping: 3, gravity: 0.95, limit: 55, radius: 0.026 });
    R.tassel = spearTasselRig();
    rigs.push(R.queue, R.tassel);
  }
  const weaponName = C.weapon;
  const spec = WEAPON_SPECS[weaponName];
  const design = {
    id: 'murim-' + kind, name: kind, kind,
    idle: base.idle || 'demo.idle',
    proportions: base.proportions || {},
    gripAngle: base.gripAngle,
    glow: C.glow,
    materials: {
      robe: { cutout: true, envMapIntensity: 0.7, bump: 1, glow: C.glow, rim: C.rim, thread: C.thread, wear: [0.5, 0.75, 0.5, 0], pulse: [0.2, 1.1, 5, 0] },
      gear: { envMapIntensity: 1, bump: 1, glow: C.glow, rim: C.rim, lace: C.lace, thread: C.thread, wear: [0.9, 0.8, 0.4, 0.8], wearColor: [0.34, 0.33, 0.32] },
      blade: { ...WEAPON_MATERIALS[weaponName] },
    },
    bones: rigs.flatMap((r) => r.bones),
    springs: rigs.flatMap((r) => r.springs),
    colliders: base.colliders || [],
    cloth: kind === 'tall' ? [clothSpec({
      name: 'coat', slot: 'robe', mesh: false,
      top: [['hips', [-rx * 0.5, wy - 0.04 * K, -rz * 0.86]], ['hips', [-rx * 1.02, wy - 0.04 * K, 0]], ['hips', [-rx * 0.5, wy - 0.04 * K, rz * 0.86]]],
      cols: 7, rows: 9, length: 0.82 * K, drape: [-0.16, -1, 0], flare: 0.5, thickness: 0.008, bend: 0.4, damping: 0.04, margin: 0.024, wind: 0.8,
      offset: (u, v) => [-0.03 * Math.sin(v * Math.PI) - 0.02 * Math.sin(u * Math.PI * 4) * v, 0, 0],
      outer: { color: C.robe, set: 'silk' }, inner: { color: C.inner },
    })] : [],
    attach(char) { return attachGlow(char, C.glow); },
    build(kit, S, rig) { buildOutfit(kit, rig, kind, C, R, { K, wy, rx, rz, silk, trim }); buildWeapon(kit, weaponName, { tassel: R.tassel }); },
  };
  if (Array.isArray(spec)) design.weapons = spec; else design.weapon = spec;
  return design;
}

function buildOutfit(kit, rig, kind, C, R, X) {
  const { K, wy, silk, trim } = X;
  const T = M.tailor(kit, { width: C.width, depth: C.depth });
  const SILK = silk(C.robe), INNER = silk(C.inner), SASH = silk(C.sash, { rough: 0.58 }), DAMASK = { ...MURIM.damask, color: C.robe, vein: 0.14, wear: 0.3 };
  const TR = trim(C.motif), EM = trim(C.emblem, 0.3);
  const band = (g, t = TR) => g && T.put('robe', g, t.look);
  const P = rig.P;

  // ---- body under the clothes: wrapped neck, trousers ------------------------------------------------------------------
  kit.loft('robe', {
    path: [['chest', [0, 0.16 * K, 0]], ['neck', [0.004, 0.02 * K, 0]], ['neck', [0.008, 0.1 * K, 0]], ['head', [0.006, 0.02 * K, 0]]],
    weights: [[0, 'chest'], [0.9, 'neck'], [2.0, 'neck'], [2.6, 'head']], rx: [[0, 0.085 * K], [1, 0.06 * K], [3, 0.056 * K]], rz: [[0, 0.1 * K], [1, 0.062 * K], [3, 0.058 * K]], segs: [12, 8],
  }, M.lookOpts({ ...MURIM.hempInk, color: kind === 'slender' ? [0.2, 0.21, 0.24] : [0.02, 0.018, 0.018] }));
  M.trousers(kit, 'robe', { ...MURIM.hemp, color: C.pants }, { r: kind === 'slender' ? [0.094, 0.086, 0.066, 0.06, 0.044] : undefined });

  // ---- layered robe: inner collar, outer robe, sash --------------------------------------------------------------------
  const inner = M.robe(T, { grow: 0.006, yBot: -0.02, cross: { y: 0.125, a: 3, spread: 58 }, lapel: { a: 30, y: 0.0 }, blouse: 0, bandW: 0.026, motif: MOTIF.lattice, nu: 32, nv: 8 });
  T.put('robe', inner.body, INNER);
  band(inner.bandOver, { look: { ...MURIM.trim, color: kind === 'slender' ? [0.5, 0.52, 0.56] : [0.3, 0.28, 0.24] } });
  band(inner.bandUnder, { look: { ...MURIM.trim, color: kind === 'slender' ? [0.5, 0.52, 0.56] : [0.3, 0.28, 0.24] } });
  const outer = M.robe(T, { grow: 0.017, motif: TR.code, cross: { y: 0.03, a: 5, spread: 66 } });
  T.put('robe', outer.body, kind === 'heavy' ? DAMASK : SILK);
  band(outer.bandOver); band(outer.bandUnder);
  const sashG = M.sash(T, { y: -0.2, h: kind === 'slender' ? 0.13 : 0.115, grow: 0.03 });
  T.put('robe', sashG, SASH);
  const kf = sashG.userData.frame(52, -0.005);
  T.put('robe', M.knot(kf, { size: 0.058 * K }), SASH);
  for (const [Hh, w] of [[R.sashA, 0.085 * K], [R.sashB, 0.07 * K]]) {
    const tl = M.sashTail(kit, Hh, { width: w, normal: [0.55, 0, 0.83] });
    putSkinned(kit, 'robe', tl, SASH, weightsOf(tl.userData.W));
  }
  // narrow cord over the sash
  const ring = T.ring(-0.2 * K, 0.04, 40);
  T.put('robe', bandOf(ring, { width: 0.02 * K, closed: true, side: [0, -1, 0], thick: 0.004, crown: 0.002 }), { ...MURIM.cord, color: C.lace });

  // ---- skirt panels -------------------------------------------------------------------------------------------------
  for (const [key, Rg] of Object.entries(R.SK)) {
    const front = key[0] === 'f', right = key[1] === 'r';
    const sp = M.skirtPanel(kit, Rg, {
      flare: (kind === 'slender' ? 0.13 : front ? 0.09 : 0.06) * K, pleats: front ? 2 : 3, pleat: front ? 0.016 : 0.011, lift: front ? 0.008 : 0.003, bandW: 0.05 * K, motif: TR.code, sideW: front ? 0.03 * K : 0, wrap: 3,
      hem: kind === 'heavy' ? (u) => 1 - 0.1 * Math.abs(Math.sin(u * 7 + (right ? 1 : 2))) : kind === 'slender' ? (u) => 1 - 0.14 * (front ? (right ? 1 - u : u) : 0) : () => 1,
    });
    const add = (g, look) => g && putSkinned(kit, 'robe', g, look, weightsOf(g.userData.W));
    add(sp.panel, kind === 'heavy' && front ? DAMASK : SILK);
    add(sp.hem, TR.look); add(sp.edgeL, TR.look); add(sp.edgeR, TR.look);
  }

  // ---- arms ---------------------------------------------------------------------------------------------------------
  const GL = M.glove({ scale: (P.hand / 0.085) * (kind === 'slender' ? 0.9 : 1) });
  const hand = { ...MURIM.leatherBlack };
  for (const [bone, g] of [['hand', GL.wrist], ['hand', GL.palm], ['fingers', GL.fingers], ['fingerTips', GL.tips], ['thumb', GL.thumb]]) putPair(kit, 'gear', bone, g, hand);
  const drape = (Hh) => { const g = M.sashTail(kit, Hh, { width: (t) => 0.12 * K * (1 - 0.5 * t), normal: [0, 0, 1], camber: 0.3, nu: 3, rootBlend: 0.15 }); putSkinned(kit, 'robe', g, SILK, weightsOf(g.userData.W)); };
  if (kind === 'slender') {
    M.sleeve(kit, 'robe', SILK, { to: 'elbow', r: [0.05, 0.058, 0.056, 0.05, 0.04] });
    M.sleeve(kit, 'robe', INNER, { to: 'wrist', r: [0.04, 0.046, 0.04, 0.036, 0.03], folds: 0.002 });
    const B = M.sleeveBell({ len: 0.25 * K, r0: 0.062 * K, r1: 0.12 * K, drop: 0.2 * K, motif: TR.code });
    putPair(kit, 'robe', 'foreArm', B.bell, SILK); putPair(kit, 'robe', 'foreArm', B.trim, TR.look);
    drape(R.drapeR); drape(R.drapeL);
  } else if (kind === 'heavy') {
    // left arm: wide sleeve; right (sword) arm: fitted sleeve under a bracer
    M.sleeve(kit, 'robe', SILK, { to: 'wrist', r: [0.062, 0.074, 0.062, 0.056, 0.046] });
    const B = M.sleeveBell({ len: 0.23 * K, r0: 0.075 * K, r1: 0.125 * K, drop: 0.17 * K, motif: TR.code });
    put(kit, 'robe', 'foreArmL', mirror(B.bell), SILK); put(kit, 'robe', 'foreArmL', mirror(B.trim), TR.look);
    drape(R.drapeL);
    const br = M.bracer({ r: 0.058 * K });
    put(kit, 'gear', 'foreArmTwistR', br.plate, MURIM.lacquer); put(kit, 'gear', 'foreArmTwistR', br.straps, MURIM.leather); put(kit, 'gear', 'foreArmTwistR', br.studs, MURIM.bronze);
  } else {
    M.sleeve(kit, 'robe', SILK, { to: 'wrist', r: [0.058, 0.068, 0.058, 0.052, 0.044] });
    const br = M.bracer({ r: 0.056 * K });
    putPair(kit, 'gear', 'foreArmTwist', br.plate, MURIM.leatherBlack); putPair(kit, 'gear', 'foreArmTwist', br.straps, MURIM.leather); putPair(kit, 'gear', 'foreArmTwist', br.studs, MURIM.bronze);
  }

  // ---- legs: shin wraps, cloth boots ------------------------------------------------------------------------------------
  const boot = M.clothBoot({ P, width: (kind === 'slender' ? 0.04 : 0.047), shaft: 0.19 * K, shaftR: (kind === 'slender' ? 0.054 : 0.064) * K, motif: TR.code });
  const BOOT = { ...MURIM.leatherBlack, set: 'hemp', rough: 0.8, color: [0.018, 0.016, 0.016] };
  putPair(kit, 'gear', 'foot', boot.upper, BOOT); putPair(kit, 'gear', 'foot', boot.heel, BOOT); putPair(kit, 'gear', 'toe', boot.toe, BOOT);
  putPair(kit, 'gear', 'foot', boot.sole, { ...MURIM.hemp, color: [0.36, 0.33, 0.28] }); putPair(kit, 'gear', 'toe', boot.toeSole, { ...MURIM.hemp, color: [0.36, 0.33, 0.28] });
  putPair(kit, 'gear', 'shin', boot.shaft, BOOT); putPair(kit, 'gear', 'shin', boot.top, TR.look);
  const leg = P.hipHeight - P.ankleHeight, shin = leg * (1 - P.thighRatio);
  putPair(kit, 'gear', 'shin', M.limbWrap({ y0: -shin * 0.12, y1: -shin + 0.2 * K, r0: 0.07 * K * (kind === 'slender' ? 0.86 : 1), r1: 0.062 * K * (kind === 'slender' ? 0.86 : 1), turns: 5, ox: -0.006 }), { ...MURIM.wrap, color: kind === 'slender' ? [0.4, 0.42, 0.46] : [0.06, 0.05, 0.04] });

  // ---- armour accents, ornaments ---------------------------------------------------------------------------------------
  if (kind === 'heavy') {
    const bp = M.beastPauldron({ R: 0.128 * K });
    put(kit, 'gear', 'deltoidR', bp.cop, { ...MURIM.ironCharred, vein: 0.5 }); put(kit, 'gear', 'deltoidR', bp.pits, MURIM.dark); put(kit, 'gear', 'deltoidR', bp.eyes, MURIM.eye);
    put(kit, 'gear', 'deltoidR', bp.fangs, MURIM.bronze); put(kit, 'gear', 'deltoidR', bp.ring, MURIM.bronze);
    const sp = M.lamellarRows({ rows: 2, rowH: 0.05 * K, y0: -0.1 * K, a0: -60, a1: 240, rx: 0.088 * K, rz: 0.092 * K, oz: 0.014, flare: 0.006, code: 0.12 });
    sp.forEach((g) => put(kit, 'gear', 'deltoidR', g, MURIM.lamellar));
    const g = M.gourd({});
    put(kit, 'gear', R.gourd.names[0], g.body, { ...MURIM.lacquerRed, color: [0.14, 0.05, 0.016] }); put(kit, 'gear', R.gourd.names[0], g.stopper, MURIM.wood); put(kit, 'gear', R.gourd.names[0], g.cord, MURIM.cord);
  } else if (kind === 'tall') {
    T.put('gear', M.lamellarCuirass(T, { yTop: 0.06, yBot: -0.13, breast: 2, code: 0.1 }), MURIM.lamellar);
    const sp = M.lamellarSpaulder({ R: 0.088 * K, rows: 3, code: 0.1 });
    for (const g of sp.rows) putPair(kit, 'gear', 'deltoid', g, MURIM.lamellar);
    putPair(kit, 'gear', 'deltoid', sp.cap, MURIM.lacquer);
  } else {
    const pd = M.pendant({});
    const b = R.pend.names[R.pend.n - 1];
    put(kit, 'gear', R.pend.names[0], pd.cord, MURIM.cord, { at: [0, 0.06, 0] });
    for (const [g, look] of [[pd.knot, { ...MURIM.cord, color: [0.03, 0.05, 0.2] }], [pd.jade, MURIM.jadeWhite], [pd.tasselHead, MURIM.silverPlain]]) put(kit, 'gear', b, g, look, { at: [0, 0.05, 0] });
    put(kit, 'robe', b, pd.strands, { ...MURIM.hair, color: [0.03, 0.05, 0.2] }, { at: [0, 0.05, 0] });
  }

  // ---- head ---------------------------------------------------------------------------------------------------------
  const hw = H.headWrap({ scale: K });
  const WRAP = { ...MURIM.hempInk, color: kind === 'slender' ? [0.03, 0.034, 0.05] : [0.02, 0.018, 0.018] };
  put(kit, 'gear', 'head', hw.wrap, WRAP); put(kit, 'gear', 'head', hw.turns, WRAP); put(kit, 'gear', 'head', hw.slot, MURIM.dark);
  const HAIR = { ...MURIM.hair, color: C.hair };
  if (kind === 'heavy') {
    const dm = H.demonMask({ scale: K });
    put(kit, 'gear', 'head', dm.face, { ...MURIM.ironCharred, vein: 0.7 }); put(kit, 'gear', 'head', dm.pits, MURIM.dark); put(kit, 'gear', 'head', dm.eyes, MURIM.eye);
    put(kit, 'gear', 'head', dm.fangs, MURIM.bronze); put(kit, 'gear', 'head', dm.horns, MURIM.iron);
    put(kit, 'robe', 'head', H.hairCap({ scale: K }), HAIR);
    const tk = H.topknot({ scale: K });
    put(kit, 'robe', 'head', tk.bun, HAIR); put(kit, 'gear', 'head', tk.tie, MURIM.cord); put(kit, 'gear', 'head', tk.pin, MURIM.bronze);
    const mn = H.mane(kit, R.mane, { scale: K });
    putSkinned(kit, 'robe', mn, HAIR, weightsOf(mn.userData.W));
    const hb = H.headband({ scale: K });
    put(kit, 'robe', 'head', hb.band, { ...MURIM.trim, color: C.sash });
    const tl = M.sashTail(kit, R.band, { width: 0.03 * K, normal: [-0.6, 0.2, 0.75], camber: 0.1, nu: 2 });
    putSkinned(kit, 'robe', tl, silk(C.sash), weightsOf(tl.userData.W));
  } else if (kind === 'slender') {
    const sm = H.silverMask({ scale: K });
    put(kit, 'gear', 'head', sm.face, MURIM.silverPlain); put(kit, 'gear', 'head', sm.pits, MURIM.dark); put(kit, 'gear', 'head', sm.eyes, MURIM.eye); put(kit, 'gear', 'head', sm.ridge, MURIM.silver);
    put(kit, 'robe', 'head', H.hairCap({ scale: K, knot: [-0.1, 0.17, 0] }), HAIR);
    const hat = H.bambooHat({ scale: K, R: 0.33, h: 0.075, y: 0.2, crown: 0.34, dip: 0.07 });
    const tilt = { rot: [0, 0, -6] };
    put(kit, 'gear', 'head', hat.shell, MURIM.bamboo, tilt); put(kit, 'gear', 'head', hat.knob, MURIM.silverPlain, tilt); put(kit, 'gear', 'head', hat.cords, { ...MURIM.cord, color: [0.03, 0.05, 0.2] }, tilt);
    const vl = H.veil(kit, R.veil, { opacity: 0.46 });
    putSkinned(kit, 'robe', vl, MURIM.gauze, weightsOf(vl.userData.W));
    const ht = H.hairTail(kit, R.tail, { width: 0.05 * K });
    putSkinned(kit, 'robe', ht.tail, HAIR, weightsOf(ht.tail.userData.W)); putSkinned(kit, 'gear', ht.tie, MURIM.silver, weightsOf(ht.tie.userData.W));
    put(kit, 'gear', 'head', H.hairpin({ len: 0.14 }), MURIM.silver, { at: [-0.1 * K, 0.172 * K, 0], rot: [0, 0, 20] });
  } else {
    put(kit, 'gear', 'head', H.faceWrap({ scale: K }), { ...MURIM.hempInk, color: [0.03, 0.022, 0.04] });
    const ey = H.eyes({ scale: K, grow: 0.0052 });
    put(kit, 'gear', 'head', ey.glow, MURIM.eye);
    const hat = H.bambooHat({ scale: K, R: 0.285, h: 0.2, y: 0.118, bell: 0.92, code: 0 });
    const tilt = { rot: [0, 0, -9] };
    put(kit, 'gear', 'head', hat.shell, MURIM.bambooDark, tilt); put(kit, 'gear', 'head', hat.knob, MURIM.bronze, tilt); put(kit, 'gear', 'head', hat.cords, MURIM.cord, tilt);
    const q = H.queue(kit, R.queue, { width: 0.036 * K });
    putSkinned(kit, 'robe', q.braid, HAIR, weightsOf(q.braid.userData.W)); putSkinned(kit, 'gear', q.tie, { ...MURIM.cord, color: C.lace }, weightsOf(q.tie.userData.W));
    // verlet coat tail: the rig simulates it (mesh: false), the kit tailors its surface and hem
    const cs = clothSurface(kit, rig, 'coat', { anchor: 'hips' });
    if (cs) clothBorder(kit, cs, { slot: 'robe', body: SILK, lining: INNER, border: EM.look, code: EM.code, hemW: 0.07, sideW: 0.035, hem: (a) => 1 - 0.12 * Math.abs(2 * a - 1) });
  }
}

