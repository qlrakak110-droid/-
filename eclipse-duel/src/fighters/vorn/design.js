// VORN 볼른 — 뇌명의 창기사 · Stormcaller Lancer. Character design (src/char/README.md "Design format").
//
// A tall (head top ~2.0 m, helm ~2.07 m, horn tips ~2.3 m), long-limbed cavalry knight: storm-blued gunmetal plate with
// bronze secondary plates and gold rolled rims, violet-white arc-runes crackling along the cuirass, pauldrons, limbs and
// helm (glow-controllable), a horned storm helm with fanned storm-feather wings and a glowing T-visor, a heavy layered
// LEFT pauldron (spear bracing) crowned with jagged lightning fins, a compact right pauldron (spear arm), a split mail
// hauberk skirt for riding, a long storm-violet surcoat (front panel + two long back tails, lightning-scorched hems), rowel
// spurs, and the war spear (src/char/weapons.js). Silhouette: tall and vertical, spiked at the head and the far
// shoulder, coat tails streaming behind the legs — against KAEL's heavy, wide, caped mass and ISKA's hooded slender line.
//
// Slots (draw calls): plate (rigid armour), suit (under-layers + mail skirt), cloth (surcoat: alpha-cut torn hems), blade.
// Glow: vorn.glow = { inlay: arc-runes, vein: charge (engraved grooves of the gold trim and horns: near dark at rest, they
// light up on a 'vein' flare) + the scorched surcoat hems, eye: T-visor and breaths } (HDR linear).
// Runtime: vorn.attach(char) -> char.glow (attachGlow + a deterministic arc crackle on the rune / visor channels).
// Quality: build(kit, S, rig, quality) builds the light variant on quality.tier === 'low' (no rivets, fewer lames / feathers,
// coarser plates and rims; the rig passes no quality yet: see the README); vornLow is the same design pinned to it.

import { attachGlow, surfDetail } from '../../char/materials.js';
import * as A from '../../char/kit/armor.js';
import { put, putPair, putSkinned, merge, mirror, extrude, kitOpts } from '../../char/kit/geo.js';
import { clothEdges, clothSpec } from '../../char/kit/cloth.js';
import { spear, WEAPON_SPECS, WEAPON_MATERIALS, WEAPON_LOOKS } from '../../char/weapons.js';
import { stormHelm, stormHornTips, stormFins, arcRune, arcInlay, rim, combAlong, mailSkirt, spur, crackle, gorget, rerebrace, vambrace, cuisse, greave, flutedBack, couterLames, poleynLames } from './kit.js';

const DEG = Math.PI / 180;
const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);
const sstep = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };

/** Storm palette (linear HDR): violet-white arc core (5, 3.5, 9) -> electric violet; the visor burns whitest. */
const GLOW = { inlay: [2.6, 1.75, 6.6], vein: [1.6, 0.8, 4.6], eye: [6.0, 4.9, 11.5] };

// ---- looks (linear colours; metals: colour = F0) ------------------------------------------------------------------------
const L = {
  plate: { color: [0.15, 0.16, 0.19], rough: 0.36, metal: 0.95, set: 'hammered', amt: 0.42 },
  lame: { color: [0.11, 0.118, 0.142], rough: 0.35, metal: 0.95, set: 'hammered', amt: 0.55 },
  legPlate: { color: [0.14, 0.15, 0.178], rough: 0.38, metal: 0.95, set: 'hammered', amt: 0.42 },
  dark: { color: [0.058, 0.063, 0.078], rough: 0.38, metal: 0.92, set: 'hammered', amt: 0.7 },
  bronze: { color: [0.21, 0.12, 0.05], rough: 0.34, metal: 1, set: 'engraved', amt: 0.9 },
  bronzeDark: { color: [0.12, 0.07, 0.034], rough: 0.36, metal: 1, set: 'engraved', amt: 0.9, vein: 0.08 },
  gold: { color: [0.6, 0.41, 0.13], rough: 0.24, metal: 1, set: 'engraved', amt: 0.7, wear: 0.6, vein: 0.06 },
  rimGold: { color: [0.56, 0.38, 0.12], rough: 0.25, metal: 1, set: 'hammered', amt: 0.35, wear: 0.9 },
  rivet: { color: [0.5, 0.34, 0.11], rough: 0.3, metal: 1, set: 'hammered', amt: 0.4, wear: 1.2 },
  rune: { color: [0.02, 0.016, 0.03], rough: 0.45, metal: 0, set: 'hammered', amt: 0, inlay: 1 },
  // engraved channel the arc-runes sit in: blackened, grimy floor; its lips catch the light (cav: edge wear)
  groove: { color: [0.03, 0.031, 0.04], rough: 0.5, metal: 0.9, set: 'hammered', amt: 0.3, occ: 0.55, wear: 1.2 },
  slit: { color: [0.003, 0.003, 0.004], rough: 0.95, metal: 0, set: 'hammered', amt: 0, occ: 0.3 },
  eye: { color: [0.02, 0.016, 0.03], rough: 0.6, metal: 0, set: 'hammered', amt: 0, eye: 1 },
  leather: { color: [0.026, 0.02, 0.018], rough: 0.64, metal: 0, set: 'leather', amt: 1 },
  strap: { color: [0.034, 0.024, 0.02], rough: 0.6, metal: 0, set: 'leather', amt: 1 },
  mail: { color: [0.11, 0.116, 0.132], rough: 0.42, metal: 1, set: 'mail', amt: 1 },
  gambeson: { color: [0.022, 0.018, 0.038], rough: 0.86, metal: 0, set: 'quilted', amt: 1 },
};
// storm-violet surcoat (apart from ISKA's indigo-blue: the roster reads ember / frost-indigo / violet-gold)
const CLOTH = { color: [0.021, 0.011, 0.038], rough: 0.82, set: 'cloth', amt: 1 };
const LINING = { color: [0.012, 0.006, 0.02], rough: 0.92, cavity: 0.5 };

/** Spear looks: storm-blued head, blackened haft, gold-bronze bands, violet grip wraps. */
const SPEAR = {
  ...WEAPON_LOOKS.spear,
  head: { color: [0.2, 0.21, 0.25], rough: 0.2, metal: 1, set: 'hammered', amt: 0.3 },
  haft: { color: [0.032, 0.027, 0.03], rough: 0.58, metal: 0, set: 'leather', amt: 0.5 },
  wrap: { color: [0.03, 0.014, 0.056], rough: 0.72, metal: 0, set: 'leather', amt: 1 },
};

// ---- torso shape (chest frame): broad chest, narrow cavalry waist ---------------------------------------------------------
const BODY = A.torsoShape({
  rx: [[-0.18, 0.126], [-0.1, 0.13], [0.0, 0.148], [0.08, 0.162], [0.16, 0.158], [0.24, 0.12]],
  rz: [[-0.18, 0.158], [-0.1, 0.164], [0.0, 0.186], [0.08, 0.205], [0.16, 0.206], [0.24, 0.172]],
  ox: [[-0.18, 0.0], [0.06, 0.012], [0.24, 0.0]],
  n: 2.35,
});

/**
 * Rest folds of a back tail (5 columns): two deep pleats (columns alternately out / in) opening toward the hem, a slow
 * secondary wave and the tail's sweep away from the legs; ph / ph2 decorrelate the two tails. The cloth's bend
 * constraints hold the rest shape, so the tails keep their folds at rest instead of hanging as flat sheets.
 */
function tailFolds(u, v, ph, ph2) {
  const open = 0.15 + 0.85 * sstep(0, 0.85, v);
  const pleat = 0.05 * Math.cos(u * Math.PI * 4 + ph) * open;
  const wave = 0.014 * Math.sin(u * Math.PI * 2 + ph2) * (0.3 + 0.7 * v);
  return [-0.03 * Math.sin(v * Math.PI) - 0.03 * v + pleat + wave, 0, 0.016 * Math.sin(u * Math.PI * 4 + ph) * open];
}

const HELM = { rx: 0.124, rz: 0.106, top: 0.282, bottom: -0.08, eyeY: 0.08, eyeH: 0.018 };
const HORN_TIPS = stormHornTips(HELM);

/** Engraved arc-rune: dark channel + glowing core (put / putPair through `fn`, optional geometry transform `xf`). */
function inlay(fn, I, xf = (g) => g) { fn(xf(I.channel), L.groove); fn(xf(I.rune), L.rune); }

/** The design's build at a detail level ('high' | 'low'). */
function buildVorn(kit, S, rig, lod) {
  const hi = lod !== 'low';
  const R = (n) => (hi ? n : Math.max(8, Math.round(n * 0.6))); // rim samples per tier
  clothEdges(kit, rig, { surcoatF: { burn: 0.55, sides: 'both' }, tailL: { burn: 0.7, sides: 'both' }, tailR: { burn: 0.7, sides: 'both' } });

  // ---- under-suit: mail torso, quilted storm-navy arms, leather legs (smooth skinned) --------------------------------------
  kit.loft('suit', {
    path: [['hips', [0, -0.12, 0]], ['hips', [0, -0.02, 0]], ['spine', [0, 0, 0]], ['chest', [0, 0, 0]], ['chest', [0, 0.17, 0]], ['neck', [0.005, 0.02, 0]], ['neck', [0.01, 0.11, 0]]],
    weights: [[0, 'hips'], [1.3, 'hips'], [2.0, 'spine'], [2.5, 'spine'], [3.1, 'chest'], [4.3, 'chest'], [5.0, 'neck'], [5.6, 'neck'], [6, 'head']],
    rx: [[0, 0.078], [1, 0.118], [2, 0.112], [3, 0.126], [4, 0.108], [5, 0.06], [6, 0.055]],
    rz: [[0, 0.098], [1, 0.155], [2, 0.145], [3, 0.168], [4, 0.152], [5, 0.062], [6, 0.055]],
    n: 2.3, segs: [16, 18],
  }, kitLook(L.mail));
  kit.loftPair('suit', {
    path: [['shoulderR', [-0.005, -0.045, 0.11]], ['upperArmR', [0, -0.01, 0]], ['upperArmR', [0, -0.16, 0]], ['foreArmR', [0, 0, 0]], ['foreArmR', [0, -0.145, 0]], ['handR', [0, 0, 0]], ['handR', [0, -0.03, 0]]],
    weights: [[0, 'shoulderR'], [0.7, 'deltoidR'], [1.15, 'upperArmTwistR'], [1.9, 'upperArmR'], [2.75, 'upperArmR'], [3, 'elbowR'], [3.25, 'foreArmR'], [3.6, 'foreArmR'], [4.4, 'foreArmTwistR'], [4.85, 'foreArmTwistR'], [5.15, 'handR']],
    rx: [[0, 0.049], [1, 0.06], [2, 0.056], [3, 0.05], [4, 0.05], [5, 0.039], [6, 0.037]],
    rz: [[0, 0.051], [1, 0.062], [2, 0.058], [3, 0.052], [4, 0.054], [5, 0.039], [6, 0.037]],
    segs: [10, 22],
  }, kitLook(L.gambeson));
  kit.loftPair('suit', {
    path: [['hips', [0, -0.03, 0.075]], ['thighR', [0, 0, 0]], ['thighR', [0, -0.25, 0]], ['shinR', [0, 0, 0]], ['shinR', [0, -0.23, 0]], ['footR', [0, 0, 0]], ['footR', [0, -0.04, 0]]],
    weights: [[0, 'hips'], [0.75, 'hips'], [1.3, 'thighR'], [2.75, 'thighR'], [3, 'kneeR'], [3.25, 'shinR'], [4.8, 'shinR'], [5.15, 'footR']],
    rx: [[0, 0.1], [1, 0.1], [2, 0.084], [3, 0.062], [4, 0.066], [5, 0.049], [6, 0.046]],
    rz: [[0, 0.1], [1, 0.096], [2, 0.08], [3, 0.06], [4, 0.06], [5, 0.045], [6, 0.044]],
    ox: [[0, 0], [4, -0.008], [5, 0]],
    segs: [10, 22],
  }, kitLook(L.leather));

  // ---- cuirass ------------------------------------------------------------------------------------------------------------------
  const breast = A.breastplate({ body: BODY, yTop: 0.215, yBot: -0.13, ridgeH: 0.018, swell: 0.012, nu: hi ? 22 : 18, nv: hi ? 9 : 7 });
  put(kit, 'plate', 'chest', breast, L.plate);
  put(kit, 'plate', 'chest', rim(breast, 'v0', 0.0072, { n: R(48), thick: 0.007 }), L.rimGold);
  // the storm bolt down the sternum ridge, forking over the pectorals
  inlay((g, l) => put(kit, 'plate', 'chest', g, l), arcInlay(breast, 0.5, 0.1, 0.5, 0.9, { segs: 9, amp: 0.028, seed: 11, width: 0.0032, channel: 0.017, forks: [[2, 58, 0.16], [3, -62, 0.15], [6, 55, 0.1]] }));
  const plack = A.plackart({ body: BODY, yTop: 0.0, yBot: -0.142, topPoint: 0.12, grow: 0.011, nu: 18, nv: 5 });
  put(kit, 'plate', 'chest', plack, L.dark);
  put(kit, 'plate', 'chest', rim(plack, 'v0', 0.0055, { n: R(36) }), L.rimGold);
  put(kit, 'plate', 'chest', A.runes(plack, { u0: 0.44, u1: 0.56, v0: 0.08, v1: 0.24, glyphs: [3], width: 0.0034, gap: 0.05 }), L.rune);
  const back = A.backplate(flutedBack({ body: BODY, yTop: 0.21, yBot: -0.128, nu: hi ? 24 : 18, nv: 6 }));
  put(kit, 'plate', 'chest', back, L.lame);
  put(kit, 'plate', 'chest', rim(back, 'v0', 0.0062, { n: R(28) }), L.rimGold);
  if (hi) {
    const pr = [];
    for (let i = 1; i < 8; i++) pr.push([i / 8, 0.88]);
    put(kit, 'plate', 'chest', A.rivets(plack, pr, { r: 0.0056, h: 0.0036, segs: 5 }), L.rivet);
  }

  // ---- gorget (skinned chest -> neck), the collar lame gold-rimmed -------------------------------------------------------------
  const gl = gorget({ count: 3, rTop: 0.076, rBot: 0.152, y0: 0.075, y1: -0.085, point: 0.026, nu: hi ? 20 : 16 });
  const neckY = kit.bonePos('neck')[1];
  const gw = (x, y) => { const t = clamp((y - (neckY - 0.05)) / 0.09, 0, 1); return [['chest', 1 - t], ['neck', t]]; };
  putSkinned(kit, 'plate', merge(gl), L.lame, gw, { frame: 'neck' });
  putSkinned(kit, 'plate', merge([rim(gl[0], 'v1', 0.0036, { n: R(26), closed: true }), rim(gl[2], 'v1', 0.0052, { n: R(32), closed: true })]), L.rimGold, gw, { frame: 'neck' });

  // ---- faulds, belt, belt plaques --------------------------------------------------------------------------------------------
  const f1 = A.faulds({ y0: 0.06, lame: 0.066, count: 1, rx: 0.132, rz: 0.165, ox: 0.008, a0: -170, a1: 170, point: 0.012, nu: 18 });
  put(kit, 'plate', 'spine', f1[0], L.dark);
  const f2 = A.faulds({ y0: 0.126, lame: 0.06, overlap: 0.016, count: 2, rx: 0.14, rz: 0.174, ox: 0.01, a0: -160, a1: 160, point: 0.024, nu: 18 });
  f2.forEach((g, k) => {
    put(kit, 'plate', 'hips', g, k ? L.lame : L.plate);
    put(kit, 'plate', 'hips', rim(g, 'v1', 0.0048, { n: R(30) }), L.rimGold);
  });
  put(kit, 'plate', 'hips', A.belt({ y: 0.108, rx: 0.152, rz: 0.186, ox: 0.01, h: 0.04, t: 0.0055, tilt: -0.01, segs: 30 }), L.strap);
  put(kit, 'plate', 'hips', A.buckle({ w: 0.046, h: 0.052, r: 0.0042 }), L.gold, { rot: [0, 90, 0], at: [0.168, 0.097, 0] });
  // gold lozenge plaques with rune cores
  const plaque = extrude([[0.0, 0.026], [0.017, 0.0], [0.0, -0.026], [-0.017, 0.0]], { depth: 0.006, bevel: 0.0022, bevelSegs: 2, crease: 30 });
  const core = extrude([[0.0, 0.011], [0.006, 0.0], [0.0, -0.011], [-0.006, 0.0]], { depth: 0.004, bevel: 0.001, bevelSegs: 1 });
  for (const a of [-52, 52, 128, -128]) {
    const [x, z] = A.se(a * DEG, 0.157, 0.191, 2.3);
    put(kit, 'plate', 'hips', plaque, L.gold, { rot: [0, 90 - a, 0], at: [x + 0.01, 0.097, z] });
    put(kit, 'plate', 'hips', core, L.rune, { rot: [0, 90 - a, 0], at: [x + 0.01 + Math.cos(a * DEG) * 0.004, 0.097, z + Math.sin(a * DEG) * 0.004] });
  }

  // ---- split mail skirt (hips -> thighs) ---------------------------------------------------------------------------------------
  const skirt = mailSkirt({ y0: 0.035, y1: -0.33, rx0: 0.156, rz0: 0.176, rx1: 0.2, rz1: 0.236, nu: hi ? 16 : 12, nv: 4 });
  const hipsY = kit.bonePos('hips')[1];
  for (const s of [1, -1]) {
    const thigh = s > 0 ? 'thighR' : 'thighL';
    const geo = s > 0 ? skirt : mirror(skirt);
    putSkinned(kit, 'suit', geo, L.mail, (x, y) => {
      const v = clamp((hipsY + 0.035 - y) / 0.37, 0, 1);
      const front = x > 0 ? 0.55 + 0.35 * clamp(x / 0.2, 0, 1) : 0.55 - 0.3 * clamp(-x / 0.2, 0, 1);
      const w = front * sstep(0.08, 0.95, v);
      return [['hips', 1 - w], [thigh, w]];
    }, { frame: 'hips' });
  }

  // ---- left pauldron: heavy, layered (spear bracing), crowned with lightning fins ---------------------------------------------
  const PL = A.pauldron({ R: 0.15, lames: hi ? 4 : 3, lameH: 0.06, lameStep: hi ? 0.042 : 0.056, flare: 0.07, haute: 0.1, tilt: 30, nu: hi ? 20 : 16, nv: 6, lameNu: hi ? 12 : 10 });
  put(kit, 'plate', 'deltoidL', mirror(PL.cop), L.dark);
  put(kit, 'plate', 'deltoidL', mirror(PL.over), L.plate);
  inlay((g, l) => put(kit, 'plate', 'deltoidL', g, l), arcInlay(PL.over, 0.12, 0.22, 0.86, 0.5, { segs: 10, amp: 0.07, seed: 5, width: 0.003, channel: 0.016, forks: [[3, 50, 0.1], [7, -50, 0.09]] }), mirror);
  put(kit, 'plate', 'deltoidL', mirror(PL.trim), L.gold);
  put(kit, 'plate', 'deltoidL', mirror(rim(PL.over, 'v1', 0.0078, { n: R(44), thick: 0.008 })), L.rimGold);
  PL.lames.forEach((g, k) => {
    const w = lameBlend(k, PL.lames.length, 'L');
    putBlend(kit, 'plate', 'deltoidL', mirror(g), w, k % 2 ? L.lame : L.plate);
    putBlend(kit, 'plate', 'deltoidL', mirror(rim(g, 'v1', 0.0048, { n: R(16) })), w, L.rimGold);
  });
  put(kit, 'plate', 'deltoidL', mirror(PL.haute), L.dark);
  put(kit, 'plate', 'deltoidL', mirror(rim(PL.haute, 'v1', 0.0068, { n: R(18), thick: 0.008 })), L.rimGold);
  put(kit, 'plate', 'deltoidL', mirror(PL.boss), L.gold);
  if (hi) put(kit, 'plate', 'deltoidL', mirror(A.rivets(PL.over, [0.14, 0.27, 0.4, 0.53, 0.66, 0.79].map((u) => [u, 0.86]), { r: 0.0066, h: 0.004, segs: 5 })), L.rivet);
  const FN = stormFins({ at: [-0.06, 0.1, -0.03], h: 0.25, len: 0.26, count: 2, gap: 0.045, lean: 4, yaw: -35 });
  put(kit, 'plate', 'deltoidL', mirror(FN.fins), L.plate, { color: edgeGold(FN.fins, L.plate.color) });
  put(kit, 'plate', 'deltoidL', mirror(FN.runes), L.rune);

  // ---- right pauldron: compact (spear arm), gold-rimmed lames, arc rune on the cop ---------------------------------------------
  const PR = A.pauldron({ R: 0.122, lames: 3, lameH: 0.054, lameStep: 0.04, tilt: 32, nu: hi ? 20 : 16, nv: hi ? 8 : 6, lameNu: hi ? 12 : 10 });
  put(kit, 'plate', 'deltoidR', PR.cop, L.plate);
  put(kit, 'plate', 'deltoidR', rim(PR.cop, 'v1', 0.0068, { n: R(40), closed: true, thick: 0.008 }), L.rimGold);
  inlay((g, l) => put(kit, 'plate', 'deltoidR', g, l), arcInlay(PR.cop, 0.56, 0.14, 0.8, 0.88, { segs: 7, amp: 0.04, seed: 9, width: 0.003, channel: 0.015, forks: [[3, -55, 0.1]] }));
  PR.lames.forEach((g, k) => {
    const w = lameBlend(k, PR.lames.length, 'R');
    putBlend(kit, 'plate', 'deltoidR', g, w, k % 2 ? L.plate : L.lame);
    putBlend(kit, 'plate', 'deltoidR', rim(g, 'v1', 0.0046, { n: R(16) }), w, L.rimGold);
  });
  // forged comb over the cop, front to back: a crest line on the near shoulder's profile
  put(kit, 'plate', 'deltoidR', combAlong(PR.cop, [[0.5, 0.92], [0.5, 0.1], [0.0, 0.1], [0.0, 0.85]], { h: 0.016, n: 22 }), L.gold);
  put(kit, 'plate', 'deltoidR', PR.boss, L.gold);
  if (hi) put(kit, 'plate', 'deltoidR', A.rivets(PR.cop, [0.38, 0.5, 0.62, 0.74, 0.86].map((u) => [u, 0.86]), { r: 0.006, h: 0.0038, segs: 5 }), L.rivet);

  // ---- arms -------------------------------------------------------------------------------------------------------------------------
  const reb = rerebrace({ r: 0.066, y0: -0.07, y1: -0.228 });
  putPair(kit, 'plate', 'upperArmTwist', reb, L.plate);
  putPair(kit, 'plate', 'upperArmTwist', rim(reb, 'v1', 0.0048, { n: R(26), closed: true }), L.rimGold);
  const cou = A.couter({ r: 0.064, wing: 0.082 });
  putPair(kit, 'plate', 'elbow', cou.cop, L.bronze);
  putPair(kit, 'plate', 'elbow', cou.wing, L.plate);
  couterLames({ r: 0.064 }).forEach((x) => putPair(kit, 'plate', 'elbow', x, L.dark));
  const vam = vambrace({ r: 0.06, y0: 0.13, y1: -0.13 });
  putPair(kit, 'plate', 'foreArmTwist', vam, L.plate);
  putPair(kit, 'plate', 'foreArmTwist', rim(vam, 'v1', 0.0046, { n: R(26), closed: true }), L.rimGold);
  inlay((g, l) => putPair(kit, 'plate', 'foreArmTwist', g, l), arcInlay(vam, 0.7, 0.12, 0.7, 0.86, { segs: 7, amp: 0.035, seed: 21, width: 0.0028, channel: 0.0135, forks: [[3, 50, 0.1]] }));
  const g = A.gauntlet();
  putPair(kit, 'plate', 'hand', g.cuff, L.plate);
  putPair(kit, 'plate', 'hand', rim(g.cuff, 'v1', 0.0038, { n: R(22), closed: true, thick: 0.005 }), L.rimGold);
  putPair(kit, 'plate', 'hand', g.back, L.dark);
  putPair(kit, 'plate', 'hand', g.palm, L.leather);
  putPair(kit, 'plate', 'fingers', g.fingers, L.dark);
  putPair(kit, 'plate', 'fingerTips', g.tips, L.lame);
  putPair(kit, 'plate', 'thumb', g.thumb, L.dark);

  // ---- legs -----------------------------------------------------------------------------------------------------------------------
  const cui = cuisse({ r: 0.116, y0: -0.035, y1: -0.43, nu: hi ? 22 : 16 });
  putPair(kit, 'plate', 'thigh', cui, L.legPlate);
  putPair(kit, 'plate', 'thigh', rim(cui, 'v0', 0.0052, { n: R(24) }), L.rimGold);
  inlay((g, l) => putPair(kit, 'plate', 'thigh', g, l), arcInlay(cui, 0.655, 0.14, 0.635, 0.86, { segs: 8, amp: 0.026, seed: 31, width: 0.003, channel: 0.016, forks: [[4, 55, 0.1]] }));
  const pol = A.poleyn({ r: 0.084, wing: 0.098 });
  putPair(kit, 'plate', 'knee', pol.cop, L.bronze);
  putPair(kit, 'plate', 'knee', pol.wing, L.plate);
  poleynLames({ r: 0.084 }).forEach((x) => putPair(kit, 'plate', 'knee', x, L.dark));
  const grv = greave({ r: 0.075, y0: -0.07, y1: -0.448, nu: hi ? 24 : 18, nv: hi ? 7 : 5 });
  putPair(kit, 'plate', 'shin', grv, L.legPlate);
  putPair(kit, 'plate', 'shin', rim(grv, 'v0', 0.0048, { n: R(28), closed: true }), L.rimGold);
  inlay((g, l) => putPair(kit, 'plate', 'shin', g, l), arcInlay(grv, 0.582, 0.08, 0.578, 0.8, { segs: 9, amp: 0.013, seed: 41, width: 0.003, channel: 0.016, forks: [[3, 50, 0.08], [6, -50, 0.07]] }));
  const sab = A.sabaton({ P: rig.P, width: 0.048, scale: 1.04, point: 0.7 });
  sab.lames.forEach((x, k) => putPair(kit, 'plate', 'foot', x, k % 2 ? L.lame : L.legPlate));
  putPair(kit, 'plate', 'foot', sab.heel, L.dark);
  putPair(kit, 'plate', 'toe', sab.toe, L.legPlate);
  putPair(kit, 'plate', 'foot', sab.sole, L.leather);
  putPair(kit, 'plate', 'toe', sab.toeSole, L.leather);
  putPair(kit, 'plate', 'foot', spur({ hx: -0.074, y: -0.046, w: 0.05 }), L.gold);

  // ---- storm helm ----------------------------------------------------------------------------------------------------------------
  const H = stormHelm({ ...HELM, rivets: hi, wings: hi ? 4 : 3 });
  put(kit, 'plate', 'head', H.skull, L.plate);
  put(kit, 'plate', 'head', H.comb, L.gold);
  put(kit, 'plate', 'head', H.brow, L.plate);
  put(kit, 'plate', 'head', H.browTrim, L.rimGold);
  put(kit, 'plate', 'head', H.cheeks, L.plate);
  put(kit, 'plate', 'head', H.cheekTrim, L.rimGold);
  put(kit, 'plate', 'head', H.breaths, { ...L.eye, eye: 0.12 });
  put(kit, 'plate', 'head', H.chin, L.dark);
  put(kit, 'plate', 'head', H.chinTrim, L.rimGold);
  put(kit, 'plate', 'head', H.nape, L.lame);
  put(kit, 'plate', 'head', H.recess, L.slit);
  put(kit, 'plate', 'head', H.eye, L.eye, { glow: (p) => {
    const e = Math.max(Math.exp(-((p[2] - 0.034) ** 2) / 0.00014), Math.exp(-((p[2] + 0.034) ** 2) / 0.00014));
    const slot = Math.abs(p[2]) < 0.008 ? 0.4 : 0;
    return [0, 0, Math.max(slot, 0.14 + 0.86 * e)];
  } });
  put(kit, 'plate', 'head', H.horns, L.bronzeDark);
  put(kit, 'plate', 'head', H.hornRoots, L.gold);
  put(kit, 'plate', 'head', H.feathers, L.plate, { color: edgeGold(H.feathers, L.plate.color) });
  put(kit, 'plate', 'head', H.runes, L.rune);
  if (hi) put(kit, 'plate', 'head', H.rivets, L.rivet);

  // ---- war spear ----------------------------------------------------------------------------------------------------------------
  spear(kit, { bone: 'weaponR', slot: 'blade', looks: SPEAR });
}

/** Pauldron lame k of n: rigid, shared between the deltoid helper and the upper-arm twist bone (lower lames follow the arm). */
function lameBlend(k, n, side) {
  const w = 0.55 + 0.45 * (k / Math.max(1, n - 1));
  return [['deltoid' + side, 1 - w], ['upperArmTwist' + side, w]];
}

/** put() for a piece blended over several bones (kit.addBlend; authored in `frame`'s zero frame). */
function putBlend(kit, slot, frame, geo, weights, look, o = {}) {
  kit.addBlend(slot, frame, geo, weights, kitOpts(geo, look, o));
}

/** Per-vertex colour: gold on the outline band of a blade2d / feather geometry (userData.edge), base elsewhere. */
function edgeGold(geo, base) {
  const e = geo.userData.edge, gold = L.rimGold.color;
  return (p, n, i) => (e && e[i] ? gold : base);
}

/** Look -> kit.loft options (lofts have no per-vertex cavity data). */
function kitLook(look) {
  return { color: look.color, rough: look.rough, metal: look.metal, detail: surfDetail(look.set ?? 0, look.amt ?? 1), cavity: 1 };
}

/**
 * Glow control with the storm crackle: attachGlow (char.glow: set / flare / gain / rim) plus a deterministic flicker and
 * sparse arc surges on the rune (inlay) and visor (eye) channels, driven by game time. glow.crackle (0..1, default 1)
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
  name: 'VORN',
  title: 'Stormcaller Lancer',
  idle: 'demo.idle',
  // ~2.02 m long-limbed lancer (the rig team's VORN audit set: src/labs/rigaudit_anim.js / rigaudit_math.js)
  proportions: {
    hipHeight: 1.05, pelvisDrop: 0.064, hipWidth: 0.104, ankleHeight: 0.09, footLength: 0.145, footDrop: 0.058, toeLength: 0.086, heelLength: 0.07,
    spine: 0.116, chest: 0.18, neck: 0.265, head: 0.11, shoulderHeight: 0.21, clavicleRoot: 0.032, clavicle: 0.2, shoulderBack: 0.016,
    upperArm: 0.325, foreArm: 0.29, hand: 0.09, palm: 0.023,
  },
  glow: GLOW,
  materials: {
    plate: { envMapIntensity: 1.15, bump: 0.9, glow: GLOW, rim: [0.26, 0.29, 0.52, 3.0], wear: [0.85, 0.75, 0.35, 0], wearColor: [0.42, 0.43, 0.46], grimeColor: [0.2, 0.2, 0.25] },
    suit: { envMapIntensity: 0.85, bump: 1, rim: [0.18, 0.2, 0.36, 3.2], wear: [0.7, 0.9, 0.5, 0], wearColor: [0.3, 0.31, 0.33] },
    cloth: { envMapIntensity: 0.6, bump: 1, cutout: true, glow: GLOW, rim: [0.14, 0.17, 0.34, 3.0], wear: [0.4, 0.9, 0.55, 0] },
    blade: { ...WEAPON_MATERIALS.spear },
  },
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
  cloth: [
    // front surcoat panel from under the faulds to the knees
    clothSpec({
      name: 'surcoatF',
      top: [['hips', [0.138, 0.03, -0.095]], ['hips', [0.156, 0.03, 0]], ['hips', [0.138, 0.03, 0.095]]],
      cols: 6, rows: 10, length: 0.64, drape: [0.1, -1, 0], flare: 0.22, thickness: 0.011,
      // rest pleats (alternate columns in / out, deepening toward the hem; biased outward, clear of the thighs): the bend
      // constraints keep them, so the panel never hangs as a flat sheet
      offset: (u, v) => [0.02 * (0.08 + 0.92 * v) * (Math.cos(u * Math.PI * 5) + 0.7) + 0.006 * Math.sin(u * Math.PI * 2 + 0.6) * v, 0, 0],
      damping: 0.045, margin: 0.024, wind: 0.6,
      outer: CLOTH, inner: LINING,
    }),
    // the split back of the surcoat: two long tails streaming behind the legs (a torn cavalry standard)
    clothSpec({
      name: 'tailL',
      top: [['hips', [-0.09, 0.05, -0.158]], ['hips', [-0.15, 0.05, -0.088]], ['hips', [-0.168, 0.05, -0.014]]],
      cols: 5, rows: 12, length: 1.0, drape: [-0.17, -1, -0.05], flare: 0.3, thickness: 0.012,
      offset: (u, v) => tailFolds(u, v, 0.2, 0.4),
      damping: 0.034, margin: 0.03, wind: 1,
      outer: CLOTH, inner: LINING,
    }),
    clothSpec({
      name: 'tailR',
      top: [['hips', [-0.168, 0.05, 0.014]], ['hips', [-0.15, 0.05, 0.088]], ['hips', [-0.09, 0.05, 0.158]]],
      cols: 5, rows: 12, length: 0.9, drape: [-0.17, -1, 0.05], flare: 0.3, thickness: 0.012,
      offset: (u, v) => tailFolds(u, v, 0.55, 1.9),
      damping: 0.034, margin: 0.03, wind: 1,
      outer: CLOTH, inner: LINING,
    }),
  ],
  weapon: WEAPON_SPECS.spear,
  sockets: {
    visor: ['head', [0.152, HELM.eyeY, 0]],
    hornR: ['head', HORN_TIPS[0]],
    hornL: ['head', HORN_TIPS[1]],
    finL: ['deltoidL', [-0.09, 0.25, -0.03]],
    runes: ['chest', [0.17, 0.06, 0]],
  },

  /** Glow control for a created character: char.glow (set / flare / gain / rim + crackle), advanced by char.update. */
  attach(char) { return attachStorm(char); },

  /** build(kit, S, rig, quality?): quality.tier 'low' builds the light variant. */
  build(kit, S, rig, quality) { buildVorn(kit, S, rig, quality && quality.tier === 'low' ? 'low' : 'high'); },
};

/** The light variant (low tier): no rivets, fewer lames / feathers, coarser plates and rims. Same rig, sockets, materials, cloth. */
export const vornLow = { ...vorn, id: 'vorn', build(kit, S, rig) { buildVorn(kit, S, rig, 'low'); } };

export default vorn;
