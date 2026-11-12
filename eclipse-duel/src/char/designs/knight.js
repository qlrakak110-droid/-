// Demo design: blackened full-plate knight with a two-handed greatsword, crimson cape, horsehair plume and swinging
// tassets. A design is data (proportions, materials, extra bones, springs, colliders, cloth, weapon) plus one build()
// function that adds pieces through the kit. Pieces are authored in each bone's zero-pose frame:
// +X forward, +Y up, +Z toward the camera (the fighter's right side). Left pieces are mirrored with addPair / loftPair.

const STEEL = { color: 0x70747e, rough: 0.3, metal: 1, detail: 1 };
const DARK = { color: 0x393b42, rough: 0.38, metal: 1, detail: 1 };
const BRASS = { color: 0xa47b3c, rough: 0.27, metal: 1, detail: 0.5 };
const LEATHER = { color: 0x3a2619, rough: 0.7, metal: 0, detail: 0.9 };
const MAIL = { color: 0x4d5057, rough: 0.5, metal: 0.95, detail: 1 };
const PADDING = { color: 0x2e1a15, rough: 0.9, metal: 0, detail: 0.8 };
const PLUME = { color: 0x5a0c10, rough: 0.85, metal: 0, detail: 0.6 };
const EMBER = [7, 2.1, 0.45];

/** Plate with rolled brass rims: plate surface + rim tubes in a separate trim colour. */
function plate(kit, S, bone, o, look = STEEL, trim = BRASS, pair = false) {
  const add = pair ? kit.addPair : kit.add;
  add('plate', bone, S.shell({ ...o, part: 'plate' }), look);
  if (o.rim) add('plate', bone, S.shell({ ...o, part: 'rim' }), trim);
}

/** @type {object} */
export const knight = {
  id: 'knight',
  name: 'Iron Knight',
  idle: 'demo.idle',
  proportions: {},
  materials: {
    plate: { roughness: 1, metalness: 1, envMapIntensity: 1.2, detailScale: 4.5, bump: 0.1 },
    suit: { roughness: 1, metalness: 1, envMapIntensity: 0.9, detailScale: 26, bump: 0.25 },
    blade: { roughness: 1, metalness: 1, envMapIntensity: 1.0, detailScale: 5, bump: 0.05 },
  },
  bones: [
    { name: 'plume1', parent: 'head', at: [-0.03, 0.245, 0] },
    { name: 'plume2', parent: 'plume1', at: [-0.075, 0.02, 0] },
    { name: 'plume3', parent: 'plume2', at: [-0.085, -0.025, 0] },
    { name: 'plume4', parent: 'plume3', at: [-0.08, -0.06, 0] },
    { name: 'tassetR', parent: 'hips', at: [0.075, -0.035, 0.105] },
    { name: 'tassetL', parent: 'hips', at: [0.075, -0.035, -0.105] },
  ],
  springs: [
    { bones: ['plume1', 'plume2', 'plume3', 'plume4'], stiffness: 50, damping: 3.5, gravity: 0.45, tip: [-0.07, -0.08, 0], limit: 75, collide: false },
    { bones: ['tassetR'], stiffness: 150, damping: 10, gravity: 0.4, tip: [0.0, -0.25, 0], radius: 0.035, limit: 70 },
    { bones: ['tassetL'], stiffness: 150, damping: 10, gravity: 0.4, tip: [0.0, -0.25, 0], radius: 0.035, limit: 70 },
  ],
  colliders: [
    { name: 'torso', a: ['spine', [-0.01, 0, 0]], b: ['chest', [-0.015, 0.15, 0]], r: 0.17 },
    { name: 'pelvis', a: ['hips', [-0.02, -0.04, -0.08]], b: ['hips', [-0.02, -0.04, 0.08]], r: 0.155 },
    { name: 'shoulderR', a: ['chest', [-0.03, 0.18, 0.09]], b: ['upperArmR', [0, -0.06, 0]], r: 0.115 },
    { name: 'shoulderL', a: ['chest', [-0.03, 0.18, -0.09]], b: ['upperArmL', [0, -0.06, 0]], r: 0.115 },
    { name: 'upperArmR', a: ['upperArmR', [0, -0.05, 0]], b: ['upperArmR', [0, -0.3, 0]], r: 0.07 },
    { name: 'upperArmL', a: ['upperArmL', [0, -0.05, 0]], b: ['upperArmL', [0, -0.3, 0]], r: 0.07 },
    { name: 'foreArmR', a: ['foreArmR', [0, 0, 0]], b: ['foreArmR', [0, -0.26, 0]], r: 0.06 },
    { name: 'foreArmL', a: ['foreArmL', [0, 0, 0]], b: ['foreArmL', [0, -0.26, 0]], r: 0.06 },
    { name: 'thighR', a: ['thighR', [0, 0.02, 0]], b: ['thighR', [0, -0.45, 0]], r: 0.1 },
    { name: 'thighL', a: ['thighL', [0, 0.02, 0]], b: ['thighL', [0, -0.45, 0]], r: 0.1 },
    { name: 'shinR', a: ['shinR', [0, 0, 0]], b: ['shinR', [0, -0.42, 0]], r: 0.075 },
    { name: 'shinL', a: ['shinL', [0, 0, 0]], b: ['shinL', [0, -0.42, 0]], r: 0.075 },
  ],
  cloth: [{
    name: 'cape', slot: 'suit',
    top: [['chest', [-0.115, 0.19, -0.165]], ['chest', [-0.165, 0.2, -0.06]], ['chest', [-0.165, 0.2, 0.06]], ['chest', [-0.115, 0.19, 0.165]]],
    cols: 9, rows: 12, length: 1.12, drape: [-0.2, -1, 0], flare: 0.55, thickness: 0.014, subdiv: 2,
    offset: (u, v) => [-0.05 * Math.sin(v * Math.PI) - 0.03 * v, 0, 0],
    damping: 0.03, margin: 0.03, wind: 1,
    surface: { outer: { color: 0x5e0d13, rough: 0.82, detail: 0.7 }, inner: { color: 0x1c0d0d, rough: 0.9, cavity: 0.75 } },
  }],
  weapon: {
    hand: 'R', slot: 'blade',
    base: [0.09, 0, 0], tip: [1.47, 0, 0],
    grips: { grip: { pos: [-0.155, 0, 0] } },
  },
  sockets: {},

  build(kit, S) {
    // ---- under-suit (smooth skinned: mail + padding) ---------------------------------------------------------------
    kit.loft('suit', {
      path: [['hips', [0, -0.13, 0]], ['hips', [0, -0.02, 0]], ['spine', [0, 0, 0]], ['chest', [0, 0, 0]], ['chest', [0, 0.17, 0]], ['neck', [0.005, 0.02, 0]], ['neck', [0.01, 0.11, 0]]],
      weights: [[0, 'hips'], [1.3, 'hips'], [2.0, 'spine'], [2.5, 'spine'], [3.1, 'chest'], [4.3, 'chest'], [5.0, 'neck'], [5.6, 'neck'], [6, 'head']],
      rx: [[0, 0.07], [1, 0.115], [2, 0.11], [3, 0.125], [4, 0.105], [5, 0.06], [6, 0.055]],
      rz: [[0, 0.09], [1, 0.16], [2, 0.145], [3, 0.165], [4, 0.15], [5, 0.062], [6, 0.055]],
      ox: [[0, 0], [3, 0.0], [4, -0.01], [5, 0.0]],
      n: 2.3, segs: [24, 30],
    }, MAIL);
    kit.loftPair('suit', {
      path: [['shoulderR', [0, -0.02, 0.1]], ['upperArmR', [0, 0, 0]], ['upperArmR', [0, -0.15, 0]], ['foreArmR', [0, 0, 0]], ['foreArmR', [0, -0.135, 0]], ['handR', [0, 0, 0]], ['handR', [0, -0.03, 0]]],
      weights: [[0, 'shoulderR'], [0.7, 'deltoidR'], [1.15, 'upperArmTwistR'], [1.9, 'upperArmR'], [2.75, 'upperArmR'], [3, 'elbowR'], [3.25, 'foreArmR'], [3.6, 'foreArmR'], [4.4, 'foreArmTwistR'], [4.85, 'foreArmTwistR'], [5.15, 'handR']],
      rx: [[0, 0.07], [1, 0.064], [2, 0.058], [3, 0.05], [4, 0.05], [5, 0.04], [6, 0.038]],
      rz: [[0, 0.075], [1, 0.066], [2, 0.06], [3, 0.052], [4, 0.054], [5, 0.04], [6, 0.038]],
      segs: [16, 34],
    }, PADDING);
    kit.loftPair('suit', {
      path: [['hips', [0, -0.03, 0.075]], ['thighR', [0, 0, 0]], ['thighR', [0, -0.23, 0]], ['shinR', [0, 0, 0]], ['shinR', [0, -0.21, 0]], ['footR', [0, 0, 0]], ['footR', [0, -0.04, 0]]],
      weights: [[0, 'hips'], [0.75, 'hips'], [1.3, 'thighR'], [2.75, 'thighR'], [3, 'kneeR'], [3.25, 'shinR'], [4.8, 'shinR'], [5.15, 'footR']],
      rx: [[0, 0.1], [1, 0.1], [2, 0.085], [3, 0.062], [4, 0.066], [5, 0.048], [6, 0.046]],
      rz: [[0, 0.1], [1, 0.098], [2, 0.08], [3, 0.06], [4, 0.06], [5, 0.045], [6, 0.044]],
      ox: [[0, 0], [4, -0.008], [5, 0]],
      segs: [16, 34],
    }, PADDING);

    // ---- torso plate -------------------------------------------------------------------------------------------------
    const chestRX = [[0, 0.105], [0.22, 0.158], [0.6, 0.152], [1, 0.128]];
    const chestRZ = [[0, 0.155], [0.3, 0.19], [0.7, 0.172], [1, 0.152]];
    plate(kit, S, 'chest', { y0: 0.22, y1: -0.13, rx: chestRX, rz: chestRZ, ox: 0.008, n: 2.25, a0: -104, a1: 104,
      ridge: { at: 0, w: 22, h: (v) => 0.004 + 0.012 * Math.sin(v * Math.PI) }, thick: 0.008, rim: 0.0065, segs: [40, 16] }, STEEL);
    plate(kit, S, 'chest', { y0: 0.215, y1: -0.125, rx: [[0, 0.12], [0.3, 0.15], [1, 0.13]], rz: chestRZ, ox: -0.005, n: 2.3, a0: 96, a1: 264,
      ridges: [{ at: 180, w: 14, h: 0.006 }], thick: 0.008, rim: 0.006, rimEdges: 'tb', segs: [32, 14] }, DARK);
    // gorget: skinned between chest and neck so it bends with the neck
    const gorget = S.merge([
      S.shell({ y0: 0.0, y1: -0.07, rx: [[0, 0.075], [1, 0.135]], rz: [[0, 0.078], [1, 0.15]], ox: 0.004, a0: 0, a1: 360, thick: 0.006, segs: [32, 4] }),
      S.shell({ y0: 0.06, y1: 0.0, rx: [[0, 0.07], [1, 0.077]], rz: [[0, 0.072], [1, 0.08]], ox: 0.006, a0: 0, a1: 360, thick: 0.006, segs: [32, 3] }),
    ]);
    const neckY = kit.bonePos('neck')[1];
    kit.addSkinned('plate', gorget, (x, y) => {
      const t = Math.max(0, Math.min(1, (y - (neckY - 0.03)) / 0.07));
      return [['chest', 1 - t], ['neck', t]];
    }, { ...DARK, frame: 'neck', at: [0, 0.0, 0] });
    kit.add('plate', 'neck', S.shell({ y0: -0.07, y1: -0.07, rx: 0.135, rz: 0.15, ox: 0.004, a0: 0, a1: 360, thick: 0.0, rim: 0.007, rimEdges: 't', part: 'rim', segs: [32, 1] }), BRASS);

    // fauld: three lames, top one on the spine, lower ones on the hips
    const lame = (bone, y0, y1, r0, r1, look) => plate(kit, S, bone, { y0, y1, rx: [[0, r0[0]], [1, r1[0]]], rz: [[0, r0[1]], [1, r1[1]]], ox: 0.01, n: 2.3, a0: 0, a1: 360, thick: 0.006, rim: 0.005, rimEdges: 'b', segs: [36, 3] }, look);
    lame('spine', 0.04, -0.035, [0.122, 0.148], [0.133, 0.16], DARK);
    lame('hips', 0.09, 0.025, [0.133, 0.16], [0.142, 0.172], STEEL);
    lame('hips', 0.035, -0.035, [0.142, 0.172], [0.152, 0.184], DARK);
    // belt
    const beltPts = [];
    for (let i = 0; i <= 40; i++) { const a = (i / 40) * Math.PI * 2; beltPts.push([0.012 + Math.cos(a) * 0.137, 0.1, Math.sin(a) * 0.164]); }
    kit.add('plate', 'hips', S.tube(beltPts, 0.014, 6, { closed: true, scaleZ: 0.45 }), LEATHER);
    kit.add('plate', 'hips', S.box(0.012, 0.05, 0.06, 0.004), { ...BRASS, at: [0.152, 0.1, 0], rot: [0, 0, 0] });

    // tassets (spring bones): three lames curving around the front-outside of each thigh
    for (let k = 0; k < 3; k++) {
      const y0 = -k * 0.075, y1 = y0 - 0.1, r = 0.15 + k * 0.006;
      plate(kit, S, 'tassetR', { y0, y1, rx: r, rz: r, ox: -0.065, oz: -0.005, a0: -38, a1: 78, thick: 0.006, rim: 0.005, rimEdges: 'b', segs: [16, 3] }, k % 2 ? DARK : STEEL, BRASS, true);
    }

    // ---- shoulders & arms ---------------------------------------------------------------------------------------------
    // pauldron: dome + 3 lames + raised neck guard, on the half-swing deltoid helper
    plate(kit, S, 'deltoidR', { y0: -0.03, y1: 0.105, rx: [[0, 0.128], [0.5, 0.112], [0.85, 0.07], [1, 0.0]], rz: [[0, 0.13], [0.5, 0.115], [0.85, 0.07], [1, 0.0]], a0: 0, a1: 360, thick: 0.008, rim: 0.007, rimEdges: 't', segs: [30, 10], ridge: { at: 90, w: 20, h: 0.008 } }, STEEL, BRASS, true);
    for (let k = 0; k < 3; k++) {
      const y0 = -0.035 - k * 0.045, y1 = y0 - 0.06;
      plate(kit, S, 'deltoidR', { y0, y1, rx: [[0, 0.1 - k * 0.006], [1, 0.108 - k * 0.006]], rz: [[0, 0.104 - k * 0.006], [1, 0.112 - k * 0.006]], oz: 0.008, a0: -45, a1: 225, thick: 0.006, rim: 0.005, rimEdges: 'b', segs: [24, 3] }, k % 2 ? STEEL : DARK, BRASS, true);
    }
    plate(kit, S, 'deltoidR', { y0: 0.17, y1: 0.06, rx: 0.19, rz: 0.19, oz: -0.2, ox: -0.01, a0: 48, a1: 128, thick: 0.007, rim: 0.006, rimEdges: 'tsb', segs: [16, 4],
      bulge: (u, v) => -0.04 * v }, DARK, BRASS, true);
    // rerebrace
    plate(kit, S, 'upperArmTwistR', { y0: -0.1, y1: -0.215, rx: [[0, 0.064], [1, 0.059]], rz: [[0, 0.066], [1, 0.061]], a0: 0, a1: 360, thick: 0.006, rim: 0.005, rimEdges: 'b', segs: [24, 4] }, STEEL, BRASS, true);
    // couter: elbow cop + outer wing + bridging lames
    kit.addPair('plate', 'elbowR', S.shell({ y0: 0, y1: 0.058, rx: [[0, 0.064], [0.6, 0.052], [1, 0.0]], rz: [[0, 0.064], [0.6, 0.052], [1, 0.0]], a0: 0, a1: 360, thick: 0.006, segs: [20, 6] }), { ...STEEL, rot: [0, 0, 90], at: [0.005, 0, 0] });
    kit.addPair('plate', 'elbowR', S.lathe([[0.0, 0.012], [0.05, 0.004], [0.075, -0.006], [0.072, -0.012], [0.0, -0.004]], { segs: 18 }), { ...BRASS, rot: [90, 0, 0], at: [-0.02, 0, 0.05] });
    plate(kit, S, 'elbowR', { y0: 0.05, y1: 0.0, rx: 0.061, rz: 0.063, a0: 0, a1: 360, thick: 0.005, rim: 0.004, rimEdges: 'b', segs: [22, 2] }, DARK, BRASS, true);
    plate(kit, S, 'elbowR', { y0: 0.0, y1: -0.05, rx: 0.057, rz: 0.06, a0: 0, a1: 360, thick: 0.005, rim: 0.004, rimEdges: 't', segs: [22, 2] }, DARK, BRASS, true);
    // vambrace on the forearm twist helper (65% of the wrist twist)
    plate(kit, S, 'foreArmTwistR', { y0: 0.135, y1: -0.085, rx: [[0, 0.054], [0.4, 0.056], [1, 0.044]], rz: [[0, 0.058], [0.4, 0.06], [1, 0.047]], a0: 0, a1: 360, thick: 0.006, rim: 0.005, rimEdges: 'tb', segs: [24, 6], ridge: { at: 90, w: 24, h: 0.006 } }, STEEL, BRASS, true);
    // gauntlet: flared cuff, back-of-hand plate, palm, articulated fingers, thumb
    plate(kit, S, 'handR', { y0: 0.03, y1: -0.04, rx: [[0, 0.047], [1, 0.062]], rz: [[0, 0.05], [1, 0.066]], a0: 0, a1: 360, thick: 0.005, rim: 0.005, rimEdges: 't', segs: [22, 3] }, DARK, BRASS, true);
    kit.addPair('plate', 'handR', S.shell({ y0: -0.035, y1: -0.105, rx: 0.05, rz: 0.03, oz: -0.004, a0: 8, a1: 172, thick: 0.005, segs: [12, 4] }), STEEL);
    kit.addPair('plate', 'handR', S.box(0.085, 0.07, 0.018, 0.006), { ...LEATHER, at: [0, -0.07, -0.012] });
    for (let f = 0; f < 4; f++) {
      const x = 0.027 - f * 0.018, w = f === 3 ? 0.0085 : 0.0095;
      kit.addPair('plate', 'fingersR', S.shell({ y0: 0.004, y1: -0.05, rx: w, rz: 0.0105, a0: 0, a1: 360, thick: 0, segs: [8, 2] }), { ...STEEL, at: [x, 0, 0] });
      kit.addPair('plate', 'fingerTipsR', S.shell({ y0: 0.004, y1: -0.042 + f * 0.002, rx: [[0, w], [1, w * 0.75]], rz: [[0, 0.0095], [1, 0.007]], a0: 0, a1: 360, thick: 0, segs: [8, 2] }), { ...DARK, at: [x, 0, 0] });
    }
    kit.addPair('plate', 'thumbR', S.tube(S.path([[0, 0, 0], [0.012, -0.03, -0.006], [0.018, -0.058, -0.012]], 6), [[0, 0.012], [1, 0.008]], 8), STEEL);

    // ---- legs ----------------------------------------------------------------------------------------------------
    plate(kit, S, 'thighR', { y0: -0.02, y1: -0.4, rx: [[0, 0.108], [0.5, 0.098], [1, 0.084]], rz: [[0, 0.108], [0.5, 0.098], [1, 0.082]], ox: 0.004, a0: -115, a1: 125, thick: 0.007, rim: 0.006, rimEdges: 'tb', segs: [28, 8], ridge: { at: 0, w: 18, h: 0.007 } }, STEEL, BRASS, true);
    kit.addPair('plate', 'kneeR', S.shell({ y0: 0, y1: 0.065, rx: [[0, 0.075], [0.55, 0.06], [1, 0.0]], rz: [[0, 0.072], [0.55, 0.058], [1, 0.0]], a0: 0, a1: 360, thick: 0.007, segs: [22, 7], ridge: { at: 90, w: 25, h: 0.006 } }), { ...STEEL, rot: [0, 0, -90], at: [0.018, 0, 0] });
    kit.addPair('plate', 'kneeR', S.lathe([[0.0, 0.012], [0.055, 0.004], [0.08, -0.006], [0.077, -0.012], [0.0, -0.004]], { segs: 18 }), { ...BRASS, rot: [90, 0, 0], at: [0.01, 0, 0.06] });
    plate(kit, S, 'kneeR', { y0: 0.075, y1: 0.02, rx: 0.088, rz: 0.086, ox: 0.006, a0: -110, a1: 125, thick: 0.006, rim: 0.004, rimEdges: 'b', segs: [20, 2] }, DARK, BRASS, true);
    plate(kit, S, 'kneeR', { y0: -0.02, y1: -0.07, rx: 0.075, rz: 0.072, ox: 0.006, a0: -110, a1: 125, thick: 0.006, rim: 0.004, rimEdges: 't', segs: [20, 2] }, DARK, BRASS, true);
    plate(kit, S, 'shinR', { y0: -0.055, y1: -0.405, rx: [[0, 0.07], [0.3, 0.078], [0.75, 0.06], [1, 0.054]], rz: [[0, 0.066], [0.3, 0.07], [1, 0.052]], ox: [[0, -0.004], [0.3, -0.008], [1, 0]], a0: 0, a1: 360, thick: 0.006, rim: 0.005, rimEdges: 'tb', segs: [28, 9], ridge: { at: 0, w: 20, h: 0.008 } }, STEEL, BRASS, true);
    // sabatons
    kit.addPair('plate', 'footR', S.box(0.215, 0.024, 0.098, 0.008), { ...LEATHER, at: [0.035, -0.073, 0] });
    kit.addPair('plate', 'toeR', S.box(0.085, 0.022, 0.09, 0.008), { ...LEATHER, at: [0.035, -0.019, 0] });
    for (let k = 0; k < 4; k++) {
      const x0 = -0.005 + k * 0.036, r = 0.074 - k * 0.0085;
      kit.addPair('plate', 'footR', S.shell({ y0: -x0, y1: -x0 - 0.048, rx: [[0, r], [1, r - 0.006]], rz: [[0, 0.056], [1, 0.054]], ox: -0.052, a0: -105, a1: 105, thick: 0.005, segs: [16, 2] }), { ...(k % 2 ? DARK : STEEL), rot: [0, 0, 90] });
    }
    kit.addPair('plate', 'toeR', S.shell({ y0: 0.012, y1: -0.09, rx: [[0, 0.042], [0.6, 0.032], [1, 0.006]], rz: [[0, 0.052], [0.6, 0.044], [1, 0.012]], ox: -0.012, n: 2.2, a0: -100, a1: 100, thick: 0.005, segs: [16, 6] }), { ...STEEL, rot: [0, 0, 90] });
    kit.addPair('plate', 'footR', S.shell({ y0: 0.0, y1: -0.07, rx: 0.07, rz: 0.06, ox: 0.0, a0: 115, a1: 245, thick: 0.006, segs: [12, 3] }), DARK);

    // ---- helmet ---------------------------------------------------------------------------------------------------
    plate(kit, S, 'head', { y0: -0.035, y1: 0.255, rx: [[0, 0.116], [0.45, 0.124], [0.78, 0.106], [0.92, 0.07], [1, 0.0]], rz: [[0, 0.1], [0.45, 0.108], [0.78, 0.096], [0.92, 0.062], [1, 0.0]], ox: 0.02, n: 2.15, a0: 0, a1: 360, thick: 0.008, segs: [36, 16], ridges: [{ at: 0, w: 16, h: 0.012 }, { at: 180, w: 16, h: 0.012 }] }, DARK);
    // brow band (visor top) and eye slit glow
    plate(kit, S, 'head', { y0: 0.11, y1: 0.068, rx: [[0, 0.131], [1, 0.136]], rz: [[0, 0.113], [1, 0.116]], ox: 0.022, n: 1.85, a0: -96, a1: 96, thick: 0.008, rim: 0.006, rimEdges: 'tb', segs: [30, 3] }, STEEL);
    kit.add('plate', 'head', S.shell({ y0: 0.066, y1: 0.05, rx: 0.122, rz: 0.105, ox: 0.02, n: 1.85, a0: -60, a1: 60, thick: 0, segs: [24, 1] }), { color: 0x050505, rough: 0.9, metal: 0, detail: 0, glow: EMBER });
    // bevor: prow-shaped face plate
    plate(kit, S, 'head', { y0: 0.05, y1: -0.125, rx: [[0, 0.13], [0.35, 0.142], [0.75, 0.125], [1, 0.1]], rz: [[0, 0.112], [0.4, 0.114], [1, 0.096]], ox: 0.022, n: 1.6, a0: -112, a1: 112, thick: 0.008, rim: 0.006, rimEdges: 'tb', segs: [32, 10], ridge: { at: 0, w: 14, h: 0.006 } }, STEEL);
    // breaths: small slots on the right cheek (glowing faintly)
    for (let k = 0; k < 4; k++) kit.add('plate', 'head', S.box(0.004, 0.024, 0.012, 0.002), { color: 0x050505, rough: 0.9, metal: 0, detail: 0, glow: [EMBER[0] * 0.25, EMBER[1] * 0.25, EMBER[2] * 0.25], at: [0.105 - k * 0.017, -0.04, 0.098 - k * 0.006], rot: [0, -38 - k * 6, 0] });
    // neck guard (tail)
    plate(kit, S, 'head', { y0: -0.02, y1: -0.1, rx: [[0, 0.112], [1, 0.135]], rz: [[0, 0.1], [1, 0.12]], ox: 0.02, a0: 112, a1: 248, thick: 0.007, rim: 0.005, rimEdges: 'bs', segs: [20, 3] }, DARK);
    kit.add('plate', 'head', S.cylinder(0.016, 0.02, 0.04, 10), { ...BRASS, at: [-0.03, 0.24, 0], rot: [0, 0, 70] });
    // plume (smooth-skinned along the spring chain)
    kit.loft('suit', {
      path: [['plume1', [0, 0, 0]], ['plume2', [0, 0, 0]], ['plume3', [0, 0, 0]], ['plume4', [0, 0, 0]], ['plume4', [-0.07, -0.08, 0]]],
      weights: [[0, 'plume1'], [1, 'plume2'], [2, 'plume3'], [3, 'plume4']],
      rx: [[0, 0.02], [1, 0.05], [2.5, 0.05], [4, 0.012]], rz: [[0, 0.018], [1, 0.03], [2.5, 0.026], [4, 0.008]],
      segs: [10, 22],
    }, PLUME);

    // ---- greatsword (on weaponR; blade along +X, edges along +-Y) ----------------------------------------------------
    kit.add('blade', 'weaponR', S.blade({ length: 1.39, width: [[0, 0.034], [0.15, 0.032], [0.7, 0.026], [0.93, 0.016], [1, 0.0005]], thick: [[0, 0.0065], [0.7, 0.0045], [1, 0.0012]], edge: 0.011, fuller: { from: 0.05, to: 0.62, w: 0.0095, depth: 0.0028 }, sections: 30 }), { color: 0x9aa1ab, rough: 0.2, metal: 1, detail: 0.6, at: [0.085, 0, 0] });
    kit.add('blade', 'weaponR', S.box(0.03, 0.078, 0.022, 0.006), { ...DARK, at: [0.07, 0, 0] });
    kit.add('blade', 'weaponR', S.tube(S.path([[0.1, -0.205, 0], [0.072, -0.12, 0], [0.068, 0, 0], [0.072, 0.12, 0], [0.1, 0.205, 0]], 20), [[0, 0.008], [0.5, 0.014], [1, 0.008]], 8, { scaleZ: 1.3 }), DARK);
    kit.add('blade', 'weaponR', S.sphere(0.013, 10, 8), { ...BRASS, at: [0.1, -0.205, 0] });
    kit.add('blade', 'weaponR', S.sphere(0.013, 10, 8), { ...BRASS, at: [0.1, 0.205, 0] });
    kit.add('blade', 'weaponR', S.lathe([[0.0, 0.02], [0.022, 0.018], [0.03, 0.0], [0.022, -0.018], [0.0, -0.02]], { segs: 8 }), { ...BRASS, rot: [90, 0, 0], at: [0.07, 0, 0] });
    kit.add('blade', 'weaponR', S.cylinder(0.0165, 0.0175, 0.3, 12), { ...LEATHER, rot: [0, 0, -90], at: [-0.095, 0, 0] });
    const wrap = [];
    for (let i = 0; i <= 120; i++) { const a = i * 0.55, x = 0.045 - (i / 120) * 0.27; wrap.push([x, Math.cos(a) * 0.0175, Math.sin(a) * 0.0175]); }
    kit.add('blade', 'weaponR', S.tube(wrap, 0.0024, 4), { ...LEATHER, color: 0x24170f });
    kit.add('blade', 'weaponR', S.lathe([[0.0, -0.035], [0.024, -0.03], [0.036, -0.012], [0.038, 0.0], [0.036, 0.012], [0.024, 0.03], [0.0, 0.035]], { segs: 8 }), { ...DARK, rot: [0, 0, -90], at: [-0.27, 0, 0] });
    kit.add('blade', 'weaponR', S.cylinder(0.009, 0.014, 0.025, 8), { ...BRASS, rot: [0, 0, -90], at: [-0.235, 0, 0] });
  },
};

export default knight;
