// 「흑일마신상 黑日魔神像」 — the design: one of the arena's guardian statues, woken by the black sun.
// Dark stone and old bronze, a stern mask under a flared crown helm, layered armour skirts, a black-sun disc with a
// gold corona behind the head, eclipse-gold fire in the cracks, and a colossal single-edged great saber whose tip
// rests on the floor while it stands. Built on the husk body lofts (same rig, same sockets), ~9k triangles, 2 draws.

import { huskDesign } from '../core/kinds.js';

const STONE = { color: 0x3b3d46, rough: 0.7, metal: 0.35, detail: 1 };
const BRONZE = { color: 0x6b5330, rough: 0.5, metal: 0.85, detail: 1 };
const DARK = { color: 0x16171c, rough: 0.8, metal: 0.3, detail: 1 };
const GOLD = [3.4, 1.7, 0.42];

/** eclipse-gold fire in the cracks: a cheap cellular vein pattern over the piece's own coordinates */
const veins = (k = 1, f = 26) => (p) => {
  const a = Math.sin(p[0] * f + Math.sin(p[1] * f * 0.7 + p[2] * 9) * 2.1), b = Math.sin(p[1] * f * 0.8 + Math.sin(p[2] * f + p[0] * 7) * 1.7);
  const v = Math.max(0, 1 - Math.min(Math.abs(a), Math.abs(b)) * 9);
  const g = v * v * k;
  return [GOLD[0] * g, GOLD[1] * g, GOLD[2] * g];
};

export const SABER = { hilt: 0.4, length: 1.62, tip: 1.74 };

export function idolDesign(id = 'rpg-idol') {
  const base = huskDesign(id, 0x8a8794, [4.2, 2.0, 0.5]);
  const baseBuild = base.build;
  return {
    ...base,
    id, idle: 'rpg.idol.idle',
    gripAngle: 40,
    weapon: { hand: 'R', slot: 'blade', base: [0.2, 0, 0], tip: [SABER.tip, 0, 0], grips: { grip: { pos: [-0.17, 0, 0] }, blade: { pos: [0.5, 0, 0] } } },
    build(kit, S) {
      // the husk body without its sword: its blade pieces go to a throw-away kit facade
      const mute = { ...kit, add: (slot, bone, geo, o) => (bone === 'weaponR' ? mute : (kit.add(slot, bone, geo, o), mute)), addPair: (...a) => (kit.addPair(...a), mute), loft: (...a) => (kit.loft(...a), mute), loftPair: (...a) => (kit.loftPair(...a), mute) };
      baseBuild(mute, S);

      // crown helm: flared brim, tall crest, two swept horns
      kit.add('plate', 'head', S.lathe([[0.125, 0.1], [0.19, 0.075], [0.245, 0.03], [0.25, 0.015], [0.18, 0.05], [0.12, 0.085]], { segs: 14 }), { ...BRONZE, at: [0.01, 0.03, 0] });
      kit.add('plate', 'head', S.box(0.26, 0.2, 0.022, 0.006), { ...BRONZE, at: [-0.02, 0.36, 0], glow: veins(0.5, 40) });
      for (const s of [1, -1]) kit.add('plate', 'head', S.cylinder(0.002, 0.034, 0.34, 6), { ...DARK, rot: [38 * s, 0, 20], at: [-0.02, 0.33, 0.15 * s] });
      // the mask: a stern stone face with two burning eye slits and a gold brow mark
      kit.add('plate', 'head', S.box(0.05, 0.16, 0.17, 0.02), { ...STONE, at: [0.115, 0.1, 0] });
      for (const s of [1, -1]) kit.add('plate', 'head', S.box(0.02, 0.016, 0.05, 0.003), { color: 0x050506, rough: 0.9, metal: 0, at: [0.142, 0.135, 0.045 * s], rot: [0, 0, 0], glow: [GOLD[0] * 2, GOLD[1] * 2, GOLD[2] * 2] });
      kit.add('plate', 'head', S.box(0.012, 0.05, 0.012, 0.003), { ...BRONZE, at: [0.145, 0.19, 0], glow: GOLD });

      // the black sun behind the head: a black disc, a thin gold corona and eight broken rays
      kit.add('plate', 'chest', S.cylinder(0.3, 0.3, 0.014, 28), { color: 0x020203, rough: 0.35, metal: 0.2, rot: [0, 0, 90], at: [-0.19, 0.5, 0] });
      const ring = [];
      for (let i = 0; i <= 28; i++) { const a = (i / 28) * Math.PI * 2; ring.push([-0.19, 0.5 + Math.cos(a) * 0.315, Math.sin(a) * 0.315]); }
      kit.add('plate', 'chest', S.tube(ring, 0.011, 5, { closed: true, caps: false }), { color: 0x2a1c08, rough: 0.4, metal: 0.8, glow: [GOLD[0] * 1.6, GOLD[1] * 1.6, GOLD[2] * 1.6] });
      for (let i = 0; i < 8; i++) {
        const a = (i / 8) * Math.PI * 2 + 0.2, len = i % 3 === 1 ? 0.09 : 0.17;
        kit.add('plate', 'chest', S.cylinder(0.001, 0.02, len, 5), { ...BRONZE, rot: [a * 180 / Math.PI, 0, 0], at: [-0.19, 0.5 + Math.cos(a) * (0.33 + len / 2), Math.sin(a) * (0.33 + len / 2)], glow: [GOLD[0] * 0.5, GOLD[1] * 0.5, GOLD[2] * 0.5] });
      }

      // layered pauldrons and a cracked breast plate that leaks gold light
      kit.addPair('plate', 'deltoid', S.sphere(0.15, 10, 7), { ...BRONZE, at: [0, 0.03, 0.035], scale: [1.05, 0.72, 1.25] });
      kit.addPair('plate', 'deltoid', S.sphere(0.135, 10, 6), { ...STONE, at: [0, -0.03, 0.06], scale: [1.0, 0.7, 1.2], glow: veins(0.8, 30) });
      kit.add('plate', 'chest', S.shell({ y0: 0.21, y1: -0.15, rx: [[0, 0.13], [0.3, 0.185], [1, 0.15]], rz: [[0, 0.18], [0.4, 0.22], [1, 0.175]], n: 2.4, a0: -105, a1: 105, thick: 0.014, segs: [14, 6] }), { ...STONE, glow: veins(1.1, 24) });
      kit.add('plate', 'chest', S.sphere(0.045, 8, 6), { color: 0x050506, rough: 0.5, metal: 0.2, at: [0.19, 0.07, 0], glow: [GOLD[0] * 1.5, GOLD[1] * 1.5, GOLD[2] * 1.5] });
      // belt and armour skirts (back and flanks long, a short tasset in front: the legs stay free to stride)
      kit.add('plate', 'hips', S.shell({ y0: 0.06, y1: -0.06, rx: [[0, 0.135], [1, 0.14]], rz: [[0, 0.185], [1, 0.19]], n: 2.4, thick: 0.014, segs: [14, 2] }), BRONZE);
      kit.add('plate', 'hips', S.shell({ y0: -0.03, y1: -0.46, rx: [[0, 0.14], [1, 0.25]], rz: [[0, 0.19], [1, 0.3]], n: 2.3, a0: 62, a1: 298, thick: 0.012, segs: [14, 4] }), { ...DARK, glow: veins(0.35, 18) });
      kit.add('plate', 'hips', S.shell({ y0: -0.03, y1: -0.3, rx: [[0, 0.145], [1, 0.21]], rz: [[0, 0.195], [1, 0.26]], n: 2.3, a0: 58, a1: 302, thick: 0.012, segs: [14, 3] }), BRONZE);
      kit.add('plate', 'hips', S.shell({ y0: -0.04, y1: -0.25, rx: [[0, 0.14], [1, 0.17]], rz: [[0, 0.1], [1, 0.07]], n: 2.6, a0: -42, a1: 42, thick: 0.012, segs: [6, 3] }), { ...STONE, glow: veins(0.7, 30) });
      // bracers and heavy greaves
      kit.addPair('plate', 'foreArm', S.shell({ y0: -0.05, y1: -0.25, rx: [[0, 0.07], [1, 0.062]], rz: [[0, 0.072], [1, 0.062]], thick: 0.012, segs: [8, 3] }), BRONZE);
      kit.addPair('plate', 'shin', S.shell({ y0: 0.03, y1: -0.38, rx: [[0, 0.085], [1, 0.065]], rz: [[0, 0.085], [1, 0.064]], a0: -140, a1: 140, thick: 0.012, segs: [9, 4] }), { ...STONE, glow: veins(0.5, 22) });
      kit.addPair('plate', 'shin', S.sphere(0.07, 8, 6), { ...BRONZE, at: [0.05, 0.02, 0], scale: [0.8, 1.1, 1] });

      // the great saber: long two-hand hilt with a ring pommel, a disc guard, a broad single-edged blade that widens
      // toward a clipped tip; the edge carries a line of eclipse fire
      const L = SABER.length;
      kit.add('blade', 'weaponR', S.cylinder(0.021, 0.024, SABER.hilt, 8), { ...DARK, rot: [0, 0, -90], at: [-0.05, 0, 0] });
      kit.add('blade', 'weaponR', S.sphere(0.04, 8, 6), { ...BRONZE, at: [-0.27, 0, 0] });
      kit.add('blade', 'weaponR', S.cylinder(0.085, 0.085, 0.022, 14), { ...BRONZE, rot: [0, 0, -90], at: [0.13, 0, 0] });
      kit.add('blade', 'weaponR', S.blade({ length: L, width: [[0, 0.055], [0.2, 0.062], [0.72, 0.092], [0.9, 0.085], [1, 0.004]], thick: [[0, 0.012], [0.8, 0.008], [1, 0.002]], edge: 0.02, sections: 18 }),
        { color: 0x5a5d66, rough: 0.36, metal: 1, detail: 0.9, at: [0.12, 0, 0], glow: (p) => { const e = Math.max(0, (Math.abs(p[1]) - 0.045) / 0.045); const g = e * e * 0.9; return [GOLD[0] * g, GOLD[1] * g, GOLD[2] * g]; } });
      kit.add('blade', 'weaponR', S.box(0.5, 0.03, 0.03, 0.006), { ...BRONZE, at: [0.42, 0, 0], glow: veins(0.6, 50) });
    },
  };
}
