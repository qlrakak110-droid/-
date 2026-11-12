// KAEL 카엘 — 잿불의 집행자 · Cinder Warden. Character design (src/char/README.md "Design format").
//
// Scorched, fire-blackened plate whose cracks and inlays glow like banked embers; a massive layered right pauldron
// (camera side) with a standing neck guard and forged flame fins, a lighter left pauldron under a soot-black fur mantle
// and a tattered, burnt half-cape; a great helm with a forged flame crest and a glowing visor slit; burnt waist cloth
// between laminated tassets; the greatsword (src/char/weapons.js). ~1.95 m, heavy build.
//
// Slots (draw calls): plate (all rigid armour), suit (under-layers), cloth (cape, waist cloth, fur: alpha-cut), blade.
// Glow: kael.glow = { inlay, vein, eye } HDR colours; attach a runtime control with kael.attach(char) (char.glow).

import { attachGlow, surfDetail } from '../../char/materials.js';
import * as A from '../../char/kit/armor.js';
import { put, putPair, putSkinned, merge, sweep, curve, rrect, circle, lathe, extrude, studs, onSurface, occlude, mirror } from '../../char/kit/geo.js';
import { clothEdges, clothSpec } from '../../char/kit/cloth.js';
import { greatsword, WEAPON_SPECS, WEAPON_MATERIALS } from '../../char/weapons.js';

const DEG = Math.PI / 180;
const sstep = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };

/** Ember palette (linear HDR): core (8, 3, 0.6) -> (3, 0.5, 0.05). */
const GLOW = { inlay: [6.2, 2.0, 0.34], vein: [2.6, 0.62, 0.07], eye: [9.5, 3.6, 0.8] };

// deterministic 3D value noise (vein hot spots)
const hash = (x, y, z) => { const s = Math.sin(x * 127.1 + y * 311.7 + z * 74.7) * 43758.5453; return s - Math.floor(s); };
function noise3(x, y, z) {
  const ix = Math.floor(x), iy = Math.floor(y), iz = Math.floor(z), fx = x - ix, fy = y - iy, fz = z - iz;
  const sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy), sz = fz * fz * (3 - 2 * fz);
  const L = (a, b, t) => a + (b - a) * t;
  const c = (dx, dy, dz) => hash(ix + dx, iy + dy, iz + dz);
  return L(L(L(c(0, 0, 0), c(1, 0, 0), sx), L(c(0, 1, 0), c(1, 1, 0), sx), sy), L(L(c(0, 0, 1), c(1, 0, 1), sx), L(c(0, 1, 1), c(1, 1, 1), sx), sy), sz);
}
/** Vein (crack glow) mask: base level with hot patches. */
const veins = (base, hot = 1, f = 9) => (p) => {
  const n = noise3(p[0] * f + 3.1, p[1] * f + 7.7, p[2] * f + 1.3);
  return [0, base * (0.04 + 0.96 * sstep(0.58, 0.88, n)) * hot, 0];
};

// ---- looks (linear colours) ---------------------------------------------------------------------------------------------
const L = {
  plate: { color: [0.05, 0.046, 0.045], rough: 0.56, metal: 0.8, set: 'scorched', amt: 1 },
  lame: { color: [0.06, 0.056, 0.055], rough: 0.5, metal: 0.85, set: 'hammered', amt: 1 },
  iron: { color: [0.048, 0.045, 0.045], rough: 0.54, metal: 0.82, set: 'hammered', amt: 1 },
  dark: { color: [0.032, 0.03, 0.03], rough: 0.6, metal: 0.75, set: 'scorched', amt: 1 },
  bronze: { color: [0.2, 0.105, 0.042], rough: 0.38, metal: 1, set: 'engraved', amt: 1, vein: 0.55 },
  rivet: { color: [0.24, 0.13, 0.05], rough: 0.32, metal: 1, set: 'hammered', amt: 0.5, wear: 1.3 },
  leather: { color: [0.034, 0.02, 0.014], rough: 0.66, metal: 0, set: 'leather', amt: 1 },
  strap: { color: [0.045, 0.026, 0.016], rough: 0.6, metal: 0, set: 'leather', amt: 1 },
  mail: { color: [0.12, 0.115, 0.115], rough: 0.46, metal: 1, set: 'mail', amt: 1 },
  gambeson: { color: [0.05, 0.032, 0.026], rough: 0.88, metal: 0, set: 'quilted', amt: 1 },
  slit: { color: [0.003, 0.003, 0.003], rough: 0.95, metal: 0, set: 'hammered', amt: 0, occ: 0.3 },
  eye: { color: [0.02, 0.008, 0.004], rough: 0.6, metal: 0, set: 'hammered', amt: 0, eye: 1 },
  ember: { color: [0.02, 0.008, 0.004], rough: 0.5, metal: 0, set: 'hammered', amt: 0, inlay: 1 },
  emberDim: { color: [0.02, 0.008, 0.004], rough: 0.5, metal: 0, set: 'hammered', amt: 0, inlay: 0.4 },
  fur: { color: [0.034, 0.029, 0.026], rough: 0.85, metal: 0, set: 'fur', amt: 1 },
};
const CLOTH = { color: [0.04, 0.013, 0.01], rough: 0.92, set: 'cloth', amt: 1 };
const LINING = { color: [0.016, 0.008, 0.007], rough: 0.95, cavity: 0.5 };

// ---- torso shape (chest frame) ---------------------------------------------------------------------------------------------
const BODY = A.torsoShape({
  rx: [[-0.18, 0.13], [-0.1, 0.133], [0.0, 0.146], [0.08, 0.158], [0.16, 0.152], [0.24, 0.118]],
  rz: [[-0.18, 0.168], [-0.1, 0.172], [0.0, 0.183], [0.08, 0.193], [0.16, 0.19], [0.24, 0.16]],
  ox: [[-0.18, 0.0], [0.06, 0.012], [0.24, 0.0]],
  n: 2.35,
});

export const kael = {
  id: 'kael',
  name: 'KAEL',
  title: 'Cinder Warden',
  idle: 'demo.idle',
  proportions: {
    hipHeight: 1.0, spine: 0.115, chest: 0.18, neck: 0.26, head: 0.105, shoulderHeight: 0.205,
    clavicle: 0.205, upperArm: 0.31, foreArm: 0.28, hipWidth: 0.105,
  },
  glow: GLOW,
  materials: {
    plate: { envMapIntensity: 0.95, bump: 1, glow: GLOW, rim: [0.2, 0.27, 0.42, 3.2], wear: [0.9, 0.85, 0.45, 0.9], wearColor: [0.3, 0.295, 0.29], grimeColor: [0.22, 0.17, 0.14], heatColor: [0.2, 0.075, 0.035] },
    suit: { envMapIntensity: 0.8, bump: 1, rim: [0.12, 0.16, 0.25, 3.5], wear: [0.7, 0.9, 0.5, 0], wearColor: [0.3, 0.3, 0.3] },
    cloth: { envMapIntensity: 0.6, bump: 1, cutout: true, glow: GLOW, rim: [0.1, 0.12, 0.2, 3.0], wear: [0.4, 0.9, 0.55, 0] },
    blade: { ...WEAPON_MATERIALS.greatsword },
  },
  bones: [
    { name: 'tassetR', parent: 'hips', at: [0.072, -0.03, 0.112] },
    { name: 'tassetL', parent: 'hips', at: [0.072, -0.03, -0.112] },
  ],
  springs: [
    { bones: ['tassetR'], stiffness: 220, damping: 13, gravity: 0.4, tip: [0.0, -0.22, 0], radius: 0.035, limit: 36 },
    { bones: ['tassetL'], stiffness: 220, damping: 13, gravity: 0.4, tip: [0.0, -0.22, 0], radius: 0.035, limit: 36 },
  ],
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
  ],
  cloth: [
    // half-cape hung from the left shoulder across the upper back (camera sees it behind his back silhouette)
    clothSpec({
      name: 'cape',
      top: [['chest', [0.07, 0.205, -0.17]], ['chest', [-0.04, 0.24, -0.2]], ['chest', [-0.16, 0.215, -0.1]], ['chest', [-0.175, 0.2, 0.02]], ['chest', [-0.15, 0.18, 0.12]]],
      cols: 10, rows: 13, length: 1.05, drape: [-0.22, -1, -0.12], flare: 0.38, thickness: 0.014,
      offset: (u, v) => [-0.05 * Math.sin(v * Math.PI) - 0.04 * v + 0.028 * v * Math.sin(u * Math.PI * 5 + 0.6), 0, -0.03 * v * (1 - u)],
      damping: 0.032, margin: 0.03, wind: 1,
      outer: CLOTH, inner: LINING,
    }),
    // burnt waist cloth hanging from the belt between the tassets
    clothSpec({
      name: 'waist',
      top: [['hips', [0.15, 0.085, -0.085]], ['hips', [0.168, 0.085, 0]], ['hips', [0.15, 0.085, 0.085]]],
      cols: 6, rows: 8, length: 0.58, drape: [0.12, -1, 0], flare: 0.22, thickness: 0.011,
      damping: 0.045, margin: 0.024, wind: 0.6,
      outer: CLOTH, inner: LINING,
    }),
  ],
  weapon: WEAPON_SPECS.greatsword,
  sockets: { visor: ['head', [0.15, 0.075, 0]], pauldron: ['deltoidR', [0, 0.17, 0.02]], cracks: ['chest', [0.17, 0.05, 0]] },

  /** Glow control for a created character: char.glow (flare / set / gain), advanced by char.update. */
  attach(char) { return attachGlow(char, GLOW); },

  build(kit, S, rig) {
    clothEdges(kit, rig, { cape: { burn: 0.85, sides: 'both' }, waist: { burn: 0.75, sides: 'both' } });

    // ---- under-suit: quilted gambeson torso + arms, mail skirt + leather legs (smooth skinned) -------------------------
    kit.loft('suit', {
      path: [['hips', [0, -0.13, 0]], ['hips', [0, -0.02, 0]], ['spine', [0, 0, 0]], ['chest', [0, 0, 0]], ['chest', [0, 0.17, 0]], ['neck', [0.005, 0.02, 0]], ['neck', [0.01, 0.11, 0]]],
      weights: [[0, 'hips'], [1.3, 'hips'], [2.0, 'spine'], [2.5, 'spine'], [3.1, 'chest'], [4.3, 'chest'], [5.0, 'neck'], [5.6, 'neck'], [6, 'head']],
      rx: [[0, 0.08], [1, 0.125], [2, 0.12], [3, 0.13], [4, 0.11], [5, 0.062], [6, 0.056]],
      rz: [[0, 0.1], [1, 0.165], [2, 0.155], [3, 0.172], [4, 0.155], [5, 0.064], [6, 0.056]],
      n: 2.3, segs: [20, 22],
    }, kitLook(L.mail));
    kit.loftPair('suit', {
      path: [['shoulderR', [-0.005, -0.045, 0.11]], ['upperArmR', [0, -0.01, 0]], ['upperArmR', [0, -0.15, 0]], ['foreArmR', [0, 0, 0]], ['foreArmR', [0, -0.14, 0]], ['handR', [0, 0, 0]], ['handR', [0, -0.03, 0]]],
      weights: [[0, 'shoulderR'], [0.7, 'deltoidR'], [1.15, 'upperArmTwistR'], [1.9, 'upperArmR'], [2.75, 'upperArmR'], [3, 'elbowR'], [3.25, 'foreArmR'], [3.6, 'foreArmR'], [4.4, 'foreArmTwistR'], [4.85, 'foreArmTwistR'], [5.15, 'handR']],
      rx: [[0, 0.05], [1, 0.062], [2, 0.058], [3, 0.052], [4, 0.052], [5, 0.04], [6, 0.038]],
      rz: [[0, 0.052], [1, 0.064], [2, 0.06], [3, 0.054], [4, 0.056], [5, 0.04], [6, 0.038]],
      segs: [12, 26],
    }, kitLook(L.gambeson));
    kit.loftPair('suit', {
      path: [['hips', [0, -0.03, 0.078]], ['thighR', [0, 0, 0]], ['thighR', [0, -0.24, 0]], ['shinR', [0, 0, 0]], ['shinR', [0, -0.22, 0]], ['footR', [0, 0, 0]], ['footR', [0, -0.04, 0]]],
      weights: [[0, 'hips'], [0.75, 'hips'], [1.3, 'thighR'], [2.75, 'thighR'], [3, 'kneeR'], [3.25, 'shinR'], [4.8, 'shinR'], [5.15, 'footR']],
      rx: [[0, 0.105], [1, 0.104], [2, 0.088], [3, 0.064], [4, 0.068], [5, 0.05], [6, 0.047]],
      rz: [[0, 0.105], [1, 0.1], [2, 0.083], [3, 0.062], [4, 0.062], [5, 0.046], [6, 0.045]],
      ox: [[0, 0], [4, -0.008], [5, 0]],
      segs: [12, 24],
    }, kitLook(L.leather));

    // ---- cuirass ----------------------------------------------------------------------------------------------------------
    const breast = A.breastplate({ body: BODY, yTop: 0.215, yBot: -0.13, ridgeH: 0.014, swell: 0.014 });
    put(kit, 'plate', 'chest', breast, L.plate, { glow: veins(0.9, 1.15) });
    const plack = A.plackart({ body: BODY, yTop: 0.02, yBot: -0.142, topPoint: 0.11, grow: 0.011 });
    put(kit, 'plate', 'chest', plack, L.dark, { glow: veins(0.75) });
    // ember rune in the plackart's point + a flowing inlay along the medial ridge
    put(kit, 'plate', 'chest', A.runes(plack, { u0: 0.44, u1: 0.56, v0: 0.06, v1: 0.2, glyphs: [5], width: 0.003, gap: 0.05 }), L.ember);
    put(kit, 'plate', 'chest', A.runes(breast, { u0: 0.4, u1: 0.6, v0: 0.13, v1: 0.21, glyphs: [3, 0, 6], width: 0.0022, gap: 0.35 }), L.emberDim);
    const back = A.backplate({ body: BODY, yTop: 0.21, yBot: -0.128 });
    put(kit, 'plate', 'chest', back, L.iron);
    // rivets along the plackart edge
    const pr = [];
    for (let i = 1; i < 10; i++) pr.push([i / 10, 0.9]);
    put(kit, 'plate', 'chest', A.rivets(plack, pr, { r: 0.006, h: 0.004 }), L.rivet);

    // ---- gorget (skinned between chest and neck) ---------------------------------------------------------------------------
    const gor = merge(A.gorget({ count: 3, rTop: 0.078, rBot: 0.158, y0: 0.07, y1: -0.09, point: 0.024 }));
    const neckY = kit.bonePos('neck')[1];
    putSkinned(kit, 'plate', gor, L.lame, (x, y) => {
      const t = Math.max(0, Math.min(1, (y - (neckY - 0.05)) / 0.09));
      return [['chest', 1 - t], ['neck', t]];
    }, { frame: 'neck' });

    // ---- faulds, belt, tassets --------------------------------------------------------------------------------------------
    const f1 = A.faulds({ y0: 0.065, lame: 0.07, count: 1, rx: 0.136, rz: 0.17, ox: 0.01, a0: -170, a1: 170, point: 0.012 });
    put(kit, 'plate', 'spine', f1[0], L.lame);
    const f2 = A.faulds({ y0: 0.13, lame: 0.062, overlap: 0.016, count: 2, rx: 0.142, rz: 0.176, ox: 0.012, a0: -160, a1: 160, point: 0.02 });
    f2.forEach((g, k) => put(kit, 'plate', 'hips', g, k ? L.lame : L.iron));
    const beltG = A.belt({ y: 0.112, rx: 0.152, rz: 0.186, ox: 0.012, h: 0.048, t: 0.0055, tilt: -0.012 });
    put(kit, 'plate', 'hips', beltG, L.strap);
    const bk = A.buckle({ w: 0.05, h: 0.056, r: 0.0042 });
    put(kit, 'plate', 'hips', bk, L.bronze, { rot: [0, 90, 0], at: [0.17, 0.1, 0] });
    // belt plaques with ember cores
    for (const a of [-55, 55, 125, -125]) {
      const [x, z] = A.se(a * DEG, 0.157, 0.192, 2.3);
      const pl = lathe([[0.0, 0.006], [0.014, 0.005], [0.018, 0.0], [0.0, 0.0]], { segs: 10 });
      pl.rotateZ(-90 * DEG);
      put(kit, 'plate', 'hips', pl, L.rivet, { rot: [0, -a, 0], at: [x + 0.012, 0.1, z] });
    }
    for (const [i, g] of A.tasset({ count: 3, h: 0.088, r: 0.15, point: 0.034 }).entries()) {
      put(kit, 'plate', 'tassetR', g, i === 1 ? L.lame : L.plate, { glow: veins(0.4) });
      put(kit, 'plate', 'tassetL', mirror(g), i === 1 ? L.lame : L.plate, { glow: veins(0.4) });
    }

    // ---- right pauldron: massive, layered (cop + flared over-plate + 4 lames), standing neck guard ----------------------
    const PR = A.pauldron({ R: 0.118, lames: 4, lameH: 0.056, lameStep: 0.04, flare: 0.045, haute: 0.07 });
    put(kit, 'plate', 'deltoidR', PR.cop, L.dark, { glow: veins(0.5) });
    put(kit, 'plate', 'deltoidR', PR.over, L.plate, { glow: veins(1.0, 1.2, 7) });
    PR.lames.forEach((g, k) => put(kit, 'plate', 'deltoidR', g, k % 2 ? L.plate : L.lame, { glow: veins(0.4) }));
    put(kit, 'plate', 'deltoidR', PR.haute, L.dark, { glow: veins(0.7) });
    put(kit, 'plate', 'deltoidR', PR.rivets, L.rivet);
    put(kit, 'plate', 'deltoidR', PR.boss, L.bronze);
    put(kit, 'plate', 'deltoidR', A.inlayLine(PR.over, [[0.2, 0.42], [0.38, 0.36], [0.5, 0.4], [0.62, 0.36], [0.8, 0.42]], { width: 0.003 }), L.emberDim);
    put(kit, 'plate', 'deltoidR', A.runes(PR.haute, { u0: 0.25, u1: 0.75, v0: 0.3, v1: 0.62, glyphs: [1, 7, 4], width: 0.0024 }), L.emberDim);
    // left pauldron: lighter, two lames (under the fur mantle and the cape)
    const PL = A.pauldron({ R: 0.104, lames: 2, nu: 18, nv: 7 });
    put(kit, 'plate', 'deltoidL', mirror(PL.cop), L.iron, { glow: veins(0.4) });
    PL.lames.forEach((g) => put(kit, 'plate', 'deltoidL', mirror(g), L.lame));
    put(kit, 'plate', 'deltoidL', mirror(PL.rivets), L.rivet);
    put(kit, 'plate', 'deltoidL', mirror(PL.boss), L.rivet);
    // cape clasp on the left shoulder: bronze disc with an ember core
    const clasp = lathe([[0.0, 0.012], [0.02, 0.011], [0.032, 0.006], [0.036, 0.0], [0.0, 0.0]], { segs: 18, hard: [2] });
    clasp.rotateX(-90 * DEG);
    put(kit, 'plate', 'chest', clasp, L.bronze, { rot: [0, 0, 0], at: [0.075, 0.2, -0.178] });
    const core = lathe([[0.0, 0.008], [0.012, 0.006], [0.016, 0.0], [0.0, 0.0]], { segs: 12 });
    core.rotateX(-90 * DEG);
    put(kit, 'plate', 'chest', core, L.ember, { at: [0.075, 0.2, -0.19] });
    // fur mantle around the left shoulder and the back of the neck (alpha-cut cards)
    const fur = A.furRing({ center: [-0.03, 0.235, -0.01], rx: 0.15, rz: 0.17, a0: 110, a1: 300, count: 22, len: 0.11, width: 0.07, droop: 0.9, layers: 2, lift: 0.012 });
    put(kit, 'cloth', 'chest', fur, L.fur);

    // ---- arms ---------------------------------------------------------------------------------------------------------------
    putPair(kit, 'plate', 'upperArmTwist', A.rerebrace({ r: 0.064, y0: -0.07, y1: -0.21 }), L.iron, { glow: veins(0.4) });
    const cou = A.couter({ r: 0.064, wing: 0.078 });
    putPair(kit, 'plate', 'elbow', cou.cop, L.iron, { glow: veins(0.5) });
    putPair(kit, 'plate', 'elbow', cou.wing, L.dark);
    cou.lames.forEach((g) => putPair(kit, 'plate', 'elbow', g, L.lame));
    const vam = A.vambrace({ r: 0.057, y0: 0.125, y1: -0.115 });
    putPair(kit, 'plate', 'foreArmTwist', vam, L.plate, { glow: veins(0.7, 1.1) });
    putPair(kit, 'plate', 'foreArmTwist', A.inlayLine(vam, [[0.18, 0.15], [0.24, 0.45], [0.2, 0.8]], { width: 0.0026 }), L.emberDim);
    const g = A.gauntlet();
    putPair(kit, 'plate', 'hand', g.cuff, L.iron, { glow: veins(0.4) });
    putPair(kit, 'plate', 'hand', g.back, L.lame);
    putPair(kit, 'plate', 'hand', g.palm, L.leather);
    putPair(kit, 'plate', 'hand', g.rivets, L.rivet);
    putPair(kit, 'plate', 'fingers', g.fingers, L.lame);
    putPair(kit, 'plate', 'fingerTips', g.tips, L.iron);
    putPair(kit, 'plate', 'thumb', g.thumb, L.lame);

    // ---- legs -----------------------------------------------------------------------------------------------------------------
    putPair(kit, 'plate', 'thigh', A.cuisse({ r: 0.112, y0: -0.035, y1: -0.4 }), L.iron, { glow: veins(0.45) });
    const pol = A.poleyn({ r: 0.076, wing: 0.088 });
    putPair(kit, 'plate', 'knee', pol.cop, L.iron, { glow: veins(0.6) });
    putPair(kit, 'plate', 'knee', pol.wing, L.dark);
    pol.lames.forEach((x) => putPair(kit, 'plate', 'knee', x, L.lame));
    putPair(kit, 'plate', 'shin', A.greave({ r: 0.07, y0: -0.065, y1: -0.415 }), L.plate, { glow: veins(0.55) });
    const sab = A.sabaton();
    sab.lames.forEach((x, k) => putPair(kit, 'plate', 'foot', x, k % 2 ? L.lame : L.iron));
    putPair(kit, 'plate', 'toe', sab.toe, L.iron);
    putPair(kit, 'plate', 'foot', S.box(0.23, 0.026, 0.1, 0.008), L.leather, { at: [0.038, -0.072, 0] });
    putPair(kit, 'plate', 'toe', S.box(0.09, 0.024, 0.092, 0.008), L.leather, { at: [0.036, -0.019, 0] });

    // ---- great helm -----------------------------------------------------------------------------------------------------------
    const H = A.greatHelm({ rx: 0.128, rz: 0.114, top: 0.268, bottom: -0.098, slitY: 0.078, slitH: 0.015, prow: 0.034, crestH: 0.042 });
    put(kit, 'plate', 'head', H.crown, L.iron, { glow: veins(0.6, 1, 8) });
    put(kit, 'plate', 'head', H.brow, L.dark, { glow: veins(0.4) });
    put(kit, 'plate', 'head', H.face, L.plate, { glow: veins(0.75, 1.1, 8) });
    put(kit, 'plate', 'head', H.back, L.lame);
    put(kit, 'plate', 'head', H.slit, L.slit);
    put(kit, 'plate', 'head', H.eye, L.eye, { glow: (p) => { const e = Math.max(Math.exp(-((p[2] - 0.034) ** 2) / 0.00018), Math.exp(-((p[2] + 0.034) ** 2) / 0.00018)); return [0, 0, 0.16 + 0.84 * e]; } });
    put(kit, 'plate', 'head', H.breaths, L.slit);
    if (H.crest) put(kit, 'plate', 'head', H.crest, L.dark);
    put(kit, 'plate', 'head', H.rivets, L.rivet);

    // ---- greatsword ---------------------------------------------------------------------------------------------------------
    greatsword(kit, { bone: 'weaponR', slot: 'blade' });
  },
};

/** Look -> kit.loft options (lofts have no per-vertex cavity data). */
function kitLook(look) {
  return { color: look.color, rough: look.rough, metal: look.metal, detail: surfDetailOf(look), cavity: 1 };
}
const surfDetailOf = (look) => surfDetail(look.set ?? 0, look.amt ?? 1);

export default kael;
