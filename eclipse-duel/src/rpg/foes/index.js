// The Black Sun Cult 흑일교 (README of src/rpg, §5 / §9): the enemies of the road.
//   cultist     흑일교 무사: a swordsman in a black robe, cloth mask and a wide bamboo hat (rusted cleave, lunge)
//   protector   흑일교 호법 護法: taller, iron hat with a bronze rim, lamellar shoulders, poise; adds the grave slam
// The husk rig and dark under-body lofts, dressed with Blender-made rigid pieces (tools/blender/heroes/cultist.py:
// cultist.edb / protector.edb, ~12-14k triangles, 2 draw calls, no cloth simulation).

import { meleeController } from '../core/kinds.js';
import { cultBase } from './rigdesign.js';
import { decodeEdb, addEdbPieces } from '../edb.js';
import { sequence } from '../cine.js';
import { run as gait, MOCAP_WALK } from '../core/clips/locomotion.js';
import { hasClip } from '../../char/index.js';
import CULTIST from './cultist.edb';
import PROTECTOR from './protector.edb';

const PIECES = {};
const GLOW = { inlay: [3.2, 0.7, 0.2], vein: [2.4, 0.4, 0.08], eye: [9, 1.5, 0.45] };

function cultDesign(id, elite) {
  const base = cultBase(id, elite);
  const baseBuild = base.build;
  return {
    ...base,
    materials: {
      plate: { envMapIntensity: 0.8, bump: 1, side: 'double', glow: GLOW, rim: [0.26, 0.32, 0.5, 3.2], wear: [0.8, 0.9, 0.5, 0.3], wearColor: [0.3, 0.3, 0.31], grimeColor: [0.22, 0.18, 0.16] },
      blade: { envMapIntensity: 0.9, bump: 1, glow: GLOW, rim: [0.26, 0.32, 0.5, 3.2], wear: [0.9, 0.8, 0.4, 0.3], wearColor: [0.5, 0.5, 0.53] },
    },
    build(kit, S) {
      // the husk's dark under-body; everything worn over it is the Blender asset (tools/blender/heroes/cultist.py)
      const body = { ...kit, add: () => body, addPair: () => body, loft: (...a) => (kit.loft(...a), body), loftPair: (...a) => (kit.loftPair(...a), body) };
      baseBuild(body, S);
      kit.addPair('plate', 'hand', S.box(0.085, 0.1, 0.085, 0.02), { color: 0x241a16, rough: 0.9, metal: 0, at: [0, -0.07, 0] });
      const k = elite ? 'protector' : 'cultist';
      if (!PIECES[k]) PIECES[k] = decodeEdb(elite ? PROTECTOR : CULTIST);
      addEdbPieces(kit, PIECES[k]);
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

/**
 * Motion-captured gaits for the husk rig (the builder of the heroes' runs: planted IK feet, the body on CMU curves):
 * a stalking walk with the saber held in the guard, and a run with the blade carried low at the side.
 * k = the actor's scale (the clip is authored at speed / k so the scaled feet stay planted).
 */
function defineGaits(prefix, k, walk, runSpeed) {
  if (hasClip(prefix + '.walk')) return;
  const base = { track: 0.1, toe: 6, hipF: 0.02, sway: 0.014, roll: 1.4, yaw: -12, spineYaw: -3, chestYaw: -3, neckYaw: 5, headYaw: 8, curl: [1, 1], poseBase: 'demo.stance', rootScale: k };
  gait(prefix + '.walk', { ...base, v: walk / k, T: 1.08, stance: 1.16, land: 0.3, lift: 0.1, reach: 0.035, kick: 34, kickBack: 0.06, hipY: -0.13, bounce: 0.022, lean: 5, twist: 6, grip: 1,
    mocap: MOCAP_WALK, mocapStance: 0.58,
    arms: (sgn) => ({ ik: { handR: { pos: [0.33, 1.07 + 0.01 * sgn, 0.1], aim: [0.8, 0.45, -0.15], up: [-0.4, 0.85, 0] } } }) });
  gait(prefix + '.run', { ...base, v: runSpeed / k, T: 0.66, stance: 0.46, land: 0.25, lift: 0.27, reach: 0.09, hipY: -0.13, bounce: 0.045, lean: 12, twist: 7, grip: 0, armGain: 0.9,
    arms: (sgn) => ({ ik: { handR: { pos: [0.1 + 0.05 * sgn, 0.9, 0.3], aim: [0.52, -0.62, 0.18], up: [0.6, 0.75, 0] } }, bones: { upperArmL: [0, 0, 0], foreArmL: [0, 0, 0], handL: [0, 0, 0] } }) });
}

const CLIPS = { idle: 'demo.idle', walk: 'game.walkF', run: 'game.walkF', flinch: 'game.hitLight', stagger: 'demo.hit', guard: 'demo.guard', dead: 'game.koDown', spawn: 'rpg.husk.rise' };

export default function install(rpg) {
  defineGaits('rpg.cult', 1, 1.2, 3.2);
  defineGaits('rpg.prot', 1.3, 1.1, 2.6);
  let ctx = null;
  rpg.setup((x) => { ctx = x.ctx; });
  // the cult steps out of the dark: a short shot past their shoulders toward the hero when an encounter begins
  rpg.on('encounterStart', (e) => {
    const world = ctx && ctx.rpg && ctx.rpg.world, hero = world && world.hero, sp = e.def && e.def.spawns;
    if (!hero || !sp || !sp.length || e.def.boss || !world.camera) return;
    let cx = 0, cz = 0;
    for (const q of sp) { cx += q.x; cz += q.z; }
    cx /= sp.length; cz /= sp.length;
    const dl = Math.hypot(cx - hero.pos.x, cz - hero.pos.z);
    if (dl < 3) return;
    const dx = (cx - hero.pos.x) / dl, dz = (cz - hero.pos.z) / dl, hx = hero.pos.x, hz = hero.pos.z;
    sequence(ctx, world, [{ dur: 1.25, frame: (k, out) => { out.pos.set(cx + dx * (3.6 - 0.5 * k) + dz * 1.7, 1.35 + 0.15 * k, cz + dz * (3.6 - 0.5 * k) - dx * 1.7); out.look.set(hx + dx * dl * 0.45, 1.05, hz + dz * dl * 0.45); out.fov = 44 - 4 * k; } }], { blendOut: 0.55 });
  });
  // the last of them falls: a breath of slow motion and a push-in
  rpg.on('death', (e) => {
    const world = ctx && ctx.rpg && ctx.rpg.world, a = e.actor;
    if (!world || !a || a.team !== 'foe' || a.spec.boss) return;
    for (const b of world.actors) if (b !== a && b.team === 'foe' && b.alive) return;
    if (world.queue && world.queue.length) return;
    world.slowmo(0.3, 0.9);
    if (world.camera && world.camera.zoom) world.camera.zoom(0.78, 1.1);
  });
  const cultist = {
    team: 'foe', name: { ko: '흑일교 무사', en: 'Black Sun Cultist' }, element: 'ember',
    stats: { hp: 240, poise: 0, radius: 0.44, height: 1.9, scale: 1, mass: 1, walk: 1.2, run: 3.2, turn: 300, shards: 30, stamina: 60 },
    design: cultDesign('rpg-cultist', false),
    clips: { ...CLIPS, walk: 'rpg.cult.walk', run: 'rpg.cult.run' }, attacks: attacks(1), roll: null, guard: null,
    controller: () => meleeController({ attacks: [{ id: 'slash', range: [0, 2.0], weight: 2, cooldown: 1.2 }, { id: 'lunge', range: [1.6, 3.6], weight: 1.3, cooldown: 1.8 }], aggro: 13, keep: 1.7, circle: 0.55 }),
  };
  rpg.actor('cultist', cultist);
  rpg.actor('protector', {
    ...cultist,
    name: { ko: '흑일교 호법', en: 'Black Sun Protector' }, elite: true,
    stats: { ...cultist.stats, hp: 660, poise: 70, scale: 1.3, radius: 0.57, height: 2.45, mass: 2.2, walk: 1.1, run: 2.6, turn: 240, shards: 120 },
    design: cultDesign('rpg-protector', true),
    clips: { ...CLIPS, walk: 'rpg.prot.walk', run: 'rpg.prot.run' },
    attacks: attacks(1.35, 1.25),
    controller: () => meleeController({ attacks: [{ id: 'slash', range: [0, 2.5], weight: 2, cooldown: 1.4 }, { id: 'lunge', range: [2.0, 4.4], weight: 1, cooldown: 2 }, { id: 'slam', range: [0, 2.9], weight: 1.5, cooldown: 2.6 }], aggro: 14, keep: 2.1, circle: 0.35 }),
  });
  rpg.encounter({ id: 'cultists', order: 10, title: { ko: '흑일교 무사들', en: 'BLACK SUN CULTISTS' },
    spawns: [{ kind: 'cultist', x: 3.5, z: -3.2 }, { kind: 'cultist', x: 5.6, z: 0.4, delay: 0.3 }, { kind: 'cultist', x: 3.8, z: 3.6, delay: 0.6 }] });
  rpg.encounter({ id: 'protector', order: 20, title: { ko: '호법과 그 무리', en: 'THE PROTECTOR\'S BAND' },
    spawns: [{ kind: 'protector', x: 6, z: 0 }, { kind: 'cultist', x: 4.5, z: -3.5, delay: 0.3 }, { kind: 'cultist', x: 4.5, z: 3.5, delay: 0.5 }] });
}
