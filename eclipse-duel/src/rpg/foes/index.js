// The Black Sun Cult 흑일교 (README of src/rpg, §5 / §9): the enemies of the road.
//   cultist     흑일교 무사: a swordsman in a black robe, cloth mask and a wide bamboo hat (rusted cleave, lunge)
//   protector   흑일교 호법 護法: taller, iron hat with a bronze rim, lamellar shoulders, poise; adds the grave slam
// The husk rig and dark under-body lofts, dressed with Blender-made rigid pieces (tools/blender/heroes/cultist.py:
// cultist.edb / protector.edb, ~12-14k triangles, 2 draw calls, no cloth simulation).

import { meleeController } from '../core/kinds.js';
import { cultBase } from './rigdesign.js';
import { decodeEdb, addEdbPieces } from '../edb.js';
import CULTIST from './cultist.edb';
import PROTECTOR from './protector.edb';

const PIECES = {};

function cultDesign(id, elite) {
  const base = cultBase(id, elite);
  const baseBuild = base.build;
  return {
    ...base,
    materials: {
      plate: { roughness: 1, metalness: 1, envMapIntensity: 0.8, detailScale: 6, bump: 0.18 },
      blade: { roughness: 1, metalness: 1, envMapIntensity: 0.9, detailScale: 5, bump: 0.05 },
    },
    build(kit, S) {
      // the husk's dark under-body; everything worn over it is the Blender asset (tools/blender/heroes/cultist.py)
      const body = { ...kit, add: () => body, addPair: () => body, loft: (...a) => (kit.loft(...a), body), loftPair: (...a) => (kit.loftPair(...a), body) };
      baseBuild(body, S);
      kit.addPair('plate', 'hand', S.box(0.085, 0.1, 0.085, 0.02), { color: 0x241a16, rough: 0.9, metal: 0, at: [0, -0.07, 0] });
      const k = elite ? 'protector' : 'cultist';
      if (!PIECES[k]) PIECES[k] = decodeEdb(elite ? PROTECTOR : CULTIST);
      addEdbPieces(kit, PIECES[k], [3.4, 0.6, 0.2]);
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
