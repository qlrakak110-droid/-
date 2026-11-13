// The Black Sun Cult 흑일교 (README of src/rpg, §5 / §9): the enemies of the road.
//   cultist     흑일교 무사: a swordsman in a black robe, cloth mask and a wide bamboo hat (rusted cleave, lunge)
//   protector   흑일교 호법 護法: taller, iron hat with a bronze rim, lamellar shoulders, poise; adds the grave slam
// Built on the husk rig and lofts (no cloth, 2 draw calls, ~5k triangles) so four of them cost almost nothing.

import { huskDesign, meleeController } from '../core/kinds.js';

const ROBE = { color: 0x2b1519, rough: 0.95, metal: 0, detail: 0.6 };
const SASH = { color: 0x6a1512, rough: 0.9, metal: 0, detail: 0.6 };
const STRAW = { color: 0x77643a, rough: 0.95, metal: 0, detail: 1 };
const IRON = { color: 0x2b2d33, rough: 0.55, metal: 0.8, detail: 1 };
const BRONZE = { color: 0x6b5330, rough: 0.5, metal: 0.85, detail: 1 };

function cultDesign(id, elite) {
  const base = huskDesign(id, elite ? 0x8a6f5c : 0x5d5560, elite ? [3.4, 0.5, 0.2] : [2.4, 0.5, 0.25]);
  const baseBuild = base.build;
  return {
    ...base,
    build(kit, S) {
      baseBuild(kit, S);
      // the hat: a wide cone, the face lost in its shadow
      kit.add('plate', 'head', S.lathe([[0.004, 0.34], [0.1, 0.3], [0.2, 0.245], [0.33, 0.165], [0.335, 0.15], [0.2, 0.215], [0.1, 0.26]], { segs: 14 }), { ...(elite ? IRON : STRAW), at: [0, 0.0, 0] });
      if (elite) kit.add('plate', 'head', S.lathe([[0.325, 0.172], [0.345, 0.16], [0.34, 0.142], [0.32, 0.156]], { segs: 14 }), BRONZE);
      // cloth mask and collar
      kit.add('plate', 'head', S.shell({ y0: 0.115, y1: -0.03, rx: [[0, 0.134], [1, 0.11]], rz: [[0, 0.132], [1, 0.1]], a0: -100, a1: 100, thick: 0.006, segs: [10, 3] }), ROBE);
      kit.add('plate', 'neck', S.shell({ y0: 0.09, y1: -0.03, rx: [[0, 0.085], [1, 0.12]], rz: [[0, 0.085], [1, 0.14]], thick: 0.008, segs: [10, 2] }), SASH);
      // robe: skirts to the knee (open in front), a sash at the waist with a hanging end
      kit.add('plate', 'hips', S.shell({ y0: 0.02, y1: -0.5, rx: [[0, 0.13], [1, 0.2]], rz: [[0, 0.18], [1, 0.27]], n: 2.3, a0: 40, a1: 320, thick: 0.008, segs: [14, 4], dy: (u, v) => -0.03 * Math.sin(u * 23) * v }), ROBE);
      kit.add('plate', 'hips', S.shell({ y0: 0.07, y1: -0.05, rx: [[0, 0.135], [1, 0.14]], rz: [[0, 0.185], [1, 0.19]], n: 2.4, thick: 0.01, segs: [14, 2] }), SASH);
      kit.add('plate', 'hips', S.box(0.02, 0.34, 0.07, 0.006), { ...SASH, at: [0.13, -0.2, 0.08], rot: [0, 0, 6] });
      // sleeves: wide cuffs over the forearms
      kit.addPair('plate', 'foreArm', S.shell({ y0: 0.02, y1: -0.2, rx: [[0, 0.06], [1, 0.085]], rz: [[0, 0.062], [1, 0.09]], thick: 0.006, segs: [8, 2] }), ROBE);
      if (elite) kit.addPair('plate', 'deltoid', S.shell({ y0: 0.09, y1: -0.1, rx: [[0, 0.1], [1, 0.13]], rz: [[0, 0.11], [1, 0.15]], a0: -20, a1: 200, thick: 0.012, segs: [8, 3] }), { ...BRONZE, at: [0, 0, 0.03] });
    },
  };
}

function attacks(k = 1, reach = 1) {
  return {
    slash: {
      name: '흑일참', duration: 1.5, clip: { clip: 'demo.combo1' },
      hits: [{ t: [0.62, 0.72], shape: { type: 'arc', r: [0.2, 2.15 * reach], angle: [-65, 65], u: [0.3, 2.0 * reach] }, damage: Math.round(58 * k), level: 'heavy', poise: 30, hitstop: 0.09, guard: 24 }],
      track: { until: 0.5, rate: 200 }, motion: [[0, 0], [0.45, 0], [0.66, 0.5 * reach]],
      markers: [{ t: 0.5, name: 'swing' }],
    },
    lunge: {
      name: '추혼보', duration: 1.7, clip: { clip: 'demo.combo1M' },
      hits: [{ t: [0.78, 0.92], shape: { type: 'box', f: [0.1, 2.5 * reach], s: [-0.55 * reach, 0.55 * reach], u: [0.4, 1.8 * reach] }, damage: Math.round(72 * k), level: 'heavy', poise: 34, hitstop: 0.1, guard: 30 }],
      track: { until: 0.62, rate: 170 }, motion: [[0, 0], [0.6, 0], [0.9, 2.1 * reach]],
      markers: [{ t: 0.64, name: 'swing' }],
    },
    slam: {
      name: '파묘격', duration: 2.1, clip: { clip: 'demo.slam' },
      hits: [{ t: [0.98, 1.08], shape: { type: 'arc', r: [0, 2.6 * reach], angle: [-50, 50], u: [0, 2.6 * reach] }, damage: Math.round(96 * k), level: 'knockdown', poise: 60, hitstop: 0.13, guard: 44 }],
      track: { until: 0.78, rate: 150 }, armour: [[0.3, 1.1]],
      markers: [{ t: 0.84, name: 'swing' }, { t: 0.98, name: 'crack', data: { decal: 'crack', shake: 0.4 } }],
    },
  };
}

const CLIPS = { idle: 'demo.idle', walk: 'game.walkF', run: 'game.walkF', flinch: 'game.hitLight', stagger: 'demo.hit', guard: 'demo.guard', dead: 'game.koDown', spawn: 'rpg.husk.rise' };

export default function install(rpg) {
  const cultist = {
    team: 'foe', name: { ko: '흑일교 무사', en: 'Black Sun Cultist' }, element: 'ember',
    stats: { hp: 240, poise: 0, radius: 0.44, height: 1.9, scale: 1, mass: 1, walk: 1.5, run: 3.2, turn: 300, shards: 30, stamina: 60 },
    design: cultDesign('rpg-cultist', false),
    clips: CLIPS, attacks: attacks(1), roll: null, guard: null,
    controller: () => meleeController({ attacks: [{ id: 'slash', range: [0, 2.0], weight: 2, cooldown: 1.2 }, { id: 'lunge', range: [1.6, 3.6], weight: 1.3, cooldown: 1.8 }], aggro: 13, keep: 1.7, circle: 0.55 }),
  };
  rpg.actor('cultist', cultist);
  rpg.actor('protector', {
    ...cultist,
    name: { ko: '흑일교 호법', en: 'Black Sun Protector' }, elite: true,
    stats: { ...cultist.stats, hp: 660, poise: 70, scale: 1.3, radius: 0.57, height: 2.45, mass: 2.2, walk: 1.3, run: 2.6, turn: 240, shards: 120 },
    design: cultDesign('rpg-protector', true),
    attacks: attacks(1.35, 1.25),
    controller: () => meleeController({ attacks: [{ id: 'slash', range: [0, 2.5], weight: 2, cooldown: 1.4 }, { id: 'lunge', range: [2.0, 4.4], weight: 1, cooldown: 2 }, { id: 'slam', range: [0, 2.9], weight: 1.5, cooldown: 2.6 }], aggro: 14, keep: 2.1, circle: 0.35 }),
  });
  rpg.encounter({ id: 'cultists', order: 10, title: { ko: '흑일교 무사들', en: 'BLACK SUN CULTISTS' },
    spawns: [{ kind: 'cultist', x: 3.5, z: -3.2 }, { kind: 'cultist', x: 5.6, z: 0.4, delay: 0.3 }, { kind: 'cultist', x: 3.8, z: 3.6, delay: 0.6 }] });
  rpg.encounter({ id: 'protector', order: 20, title: { ko: '호법과 그 무리', en: 'THE PROTECTOR\'S BAND' },
    spawns: [{ kind: 'protector', x: 6, z: 0 }, { kind: 'cultist', x: 4.5, z: -3.5, delay: 0.3 }, { kind: 'cultist', x: 4.5, z: 3.5, delay: 0.5 }] });
}
