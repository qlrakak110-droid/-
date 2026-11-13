// Built-in actor kinds so the mode is playable before the foes / boss teams land (README §5):
//   dummy          a training husk that stands still, reacts to every hit and never dies (team 'neutral')
//   husk           a simple melee enemy (telegraphed slash / lunge), `meleeController`
//   husk.elite     a bigger, armoured husk (poise, slam)
//   standin.boss   a 3.6x husk used as the boss until src/rpg/boss registers one (boss: true)
// The husk is a low-poly armoured figure: ~4k triangles, 2 draw calls, no cloth, the default rig and the generic
// game.* / demo.* clips (two-handed sword), so it costs almost nothing and needs no content of its own.

import { defineClip, hasClip } from '../../char/index.js';
import '../../char/clips/demo.js';
import { angDiff, clamp, fwdX, fwdZ, hypot2, rightX, rightZ, yawTo } from './math3.js';

const STONE = { color: 0x4a4d55, rough: 0.62, metal: 0.55, detail: 1 };
const DARK = { color: 0x23252b, rough: 0.7, metal: 0.4, detail: 1 };
const RUST = { color: 0x5b4636, rough: 0.8, metal: 0.3, detail: 0.9 };

/** Low-poly husk design. tint: plate colour multiplier, glow: visor / chest ember colour (HDR). */
export function huskDesign(id, tint = 0xffffff, glow = [2.2, 1.1, 0.5]) {
  return {
    id, idle: 'demo.idle',
    proportions: {},
    gripAngle: 40,
    materials: {
      plate: { roughness: 1, metalness: 1, envMapIntensity: 0.7, detailScale: 5, bump: 0.16, color: tint },
      blade: { roughness: 1, metalness: 1, envMapIntensity: 0.8, detailScale: 5, bump: 0.05 },
    },
    bones: [], springs: [], cloth: [],
    colliders: [{ name: 'torso', a: ['spine', [-0.01, 0, 0]], b: ['chest', [-0.015, 0.15, 0]], r: 0.17 }],
    weapon: { hand: 'R', slot: 'blade', base: [0.09, 0, 0], tip: [1.3, 0, 0], grips: { grip: { pos: [-0.155, 0, 0] }, blade: { pos: [0.5, 0, 0] } } },
    sockets: {},
    build(kit, S) {
      // body: three smooth lofts (torso, arms, legs) with few segments
      kit.loft('plate', {
        path: [['hips', [0, -0.13, 0]], ['hips', [0, -0.02, 0]], ['spine', [0, 0, 0]], ['chest', [0, 0, 0]], ['chest', [0, 0.17, 0]], ['neck', [0.005, 0.02, 0]], ['neck', [0.01, 0.11, 0]]],
        weights: [[0, 'hips'], [1.3, 'hips'], [2.0, 'spine'], [2.5, 'spine'], [3.1, 'chest'], [4.3, 'chest'], [5.0, 'neck'], [5.6, 'neck'], [6, 'head']],
        rx: [[0, 0.08], [1, 0.125], [2, 0.12], [3, 0.14], [4, 0.12], [5, 0.065], [6, 0.058]],
        rz: [[0, 0.1], [1, 0.17], [2, 0.155], [3, 0.19], [4, 0.17], [5, 0.066], [6, 0.058]],
        n: 2.4, segs: [10, 12],
      }, DARK);
      kit.loftPair('plate', {
        path: [['shoulderR', [0, -0.02, 0.1]], ['upperArmR', [0, 0, 0]], ['upperArmR', [0, -0.15, 0]], ['foreArmR', [0, 0, 0]], ['foreArmR', [0, -0.135, 0]], ['handR', [0, 0, 0]], ['handR', [0, -0.06, 0]]],
        weights: [[0, 'shoulderR'], [0.55, 'deltoidR'], [1.4, 'upperArmTwistR'], [2.05, 'upperArmR'], [2.55, 'upperArmR'], [3, 'elbowVolR'], [3.45, 'foreArmR'], [3.7, 'foreArmR'], [4.4, 'foreArmTwistR'], [4.85, 'foreArmTwistR'], [5.15, 'handR']],
        rx: [[0, 0.075], [1, 0.07], [2, 0.064], [3, 0.055], [4, 0.06], [5, 0.048], [6, 0.05]],
        rz: [[0, 0.08], [1, 0.072], [2, 0.066], [3, 0.057], [4, 0.064], [5, 0.048], [6, 0.05]],
        segs: [7, 12],
      }, DARK);
      kit.loftPair('plate', {
        path: [['hips', [0, -0.03, 0.075]], ['thighR', [0, 0, 0]], ['thighR', [0, -0.23, 0]], ['shinR', [0, 0, 0]], ['shinR', [0, -0.21, 0]], ['footR', [0, 0, 0]], ['footR', [0, -0.04, 0]]],
        weights: [[0, 'hips'], [0.5, 'hips'], [1.0, 'hipJointR'], [1.45, 'thighTwistR'], [2.0, 'thighR'], [2.6, 'thighR'], [3, 'kneeVolR'], [3.4, 'shinR'], [4.8, 'shinR'], [5.15, 'footR']],
        rx: [[0, 0.105], [1, 0.105], [2, 0.09], [3, 0.068], [4, 0.074], [5, 0.052], [6, 0.05]],
        rz: [[0, 0.105], [1, 0.102], [2, 0.086], [3, 0.066], [4, 0.068], [5, 0.05], [6, 0.048]],
        segs: [7, 12],
      }, DARK);
      // plates: cuirass, pauldrons, helm with a glowing slit, greaves, boots
      kit.add('plate', 'chest', S.shell({ y0: 0.2, y1: -0.14, rx: [[0, 0.12], [0.3, 0.17], [1, 0.14]], rz: [[0, 0.17], [0.4, 0.205], [1, 0.165]], n: 2.3, a0: -110, a1: 110, thick: 0.012, segs: [12, 5] }), STONE);
      kit.add('plate', 'chest', S.shell({ y0: 0.2, y1: -0.12, rx: [[0, 0.125], [1, 0.14]], rz: [[0, 0.17], [1, 0.16]], n: 2.3, a0: 100, a1: 260, thick: 0.012, segs: [10, 4] }), RUST);
      kit.addPair('plate', 'deltoid', S.sphere(0.115, 8, 6), { ...STONE, at: [0, 0.01, 0.02], scale: [1, 0.8, 1.05] });
      kit.add('plate', 'head', S.lathe([[0.0, 0.3], [0.07, 0.285], [0.118, 0.23], [0.13, 0.15], [0.128, 0.07], [0.105, 0.005], [0.08, -0.02]], { segs: 10 }), { ...STONE, at: [0.01, -0.02, 0] });
      kit.add('plate', 'head', S.box(0.03, 0.022, 0.15, 0.004), { color: 0x0a0a0c, rough: 0.9, metal: 0, at: [0.128, 0.13, 0], glow });
      kit.add('plate', 'chest', S.sphere(0.03, 6, 5), { color: 0x101014, rough: 0.6, metal: 0.2, at: [0.176, 0.06, 0], glow: [glow[0] * 0.7, glow[1] * 0.7, glow[2] * 0.7] });
      kit.addPair('plate', 'shin', S.shell({ y0: -0.02, y1: -0.36, rx: [[0, 0.07], [1, 0.055]], rz: [[0, 0.07], [1, 0.054]], a0: -120, a1: 120, thick: 0.01, segs: [7, 3] }), RUST);
      kit.addPair('plate', 'foot', S.box(0.25, 0.085, 0.105, 0.02), { ...DARK, at: [0.055, -0.045, 0] });
      kit.addPair('plate', 'hand', S.box(0.085, 0.1, 0.085, 0.02), { ...STONE, at: [0, -0.07, 0] });
      // a chipped two-handed blade
      kit.add('blade', 'weaponR', S.blade({ length: 1.22, width: [[0, 0.04], [0.7, 0.036], [0.92, 0.022], [1, 0.001]], thick: [[0, 0.008], [1, 0.002]], edge: 0.012, sections: 10 }), { color: 0x7a7f88, rough: 0.42, metal: 1, detail: 0.8, at: [0.085, 0, 0] });
      kit.add('blade', 'weaponR', S.box(0.035, 0.26, 0.03, 0.006), { ...RUST, at: [0.07, 0, 0] });
      kit.add('blade', 'weaponR', S.cylinder(0.017, 0.018, 0.3, 7), { ...DARK, rot: [0, 0, -90], at: [-0.095, 0, 0] });
    },
  };
}

// ---- a reusable melee brain -----------------------------------------------------------------------------------------

/** Attack tokens: at most `max` foes commit to an attack at the same time (a fair crowd). */
function tokens(world) {
  if (!world.aiTokens) world.aiTokens = { holders: new Set(), max: 2 };
  return world.aiTokens;
}

/**
 * Approach / circle / telegraphed attack / back off.
 * o: { attacks: [{ id, range: [min, max], weight = 1, cooldown = 1.5 }], aggro = 14 (m), keep = 1.9 (m, preferred gap),
 *      circle = 0.5 (0..1 strafe appetite), patience: [min, max] s between attacks, run = true, leash = 0 }
 */
export function meleeController(o = {}) {
  const attacks = o.attacks || [];
  const aggroR = o.aggro ?? 14, keep = o.keep ?? 1.9, patience = o.patience || [0.7, 1.7];
  const maxRange = attacks.reduce((m, x) => Math.max(m, x.range[1]), 0);
  return {
    kind: 'melee',
    think(world, a, dt, it) {
      const ai = a.data.ai || (a.data.ai = { aggro: false, cool: world.rng.range(0.4, 1.6), side: world.rng.sign(), sideT: 0, hold: 0, token: false });
      const hero = world.hero;
      const tk = tokens(world);
      if (ai.token && a.state !== 'attack') { ai.hold -= dt; if (ai.hold <= 0) { tk.holders.delete(a.id); ai.token = false; } }
      if (!hero || !hero.alive) { a.target = null; return; }
      const dx = hero.pos.x - a.pos.x, dz = hero.pos.z - a.pos.z;
      const d = hypot2(dx, dz) - hero.radius - a.radius;
      if (!ai.aggro) { if (d < aggroR || a.hp < a.hpMax) ai.aggro = true; else return; }
      a.target = hero;
      const face = yawTo(dx, dz);
      it.face = face;
      ai.cool -= dt;
      ai.sideT -= dt;
      if (ai.sideT <= 0) { ai.sideT = world.rng.range(1.6, 3.6); ai.side = world.rng.chance(0.65) ? ai.side : -ai.side; }
      if (a.state !== 'idle' && a.state !== 'move') return;
      // attack: in range, facing roughly right, a token free
      if (ai.cool <= 0 && d <= maxRange && Math.abs(angDiff(a.yaw, face)) < 0.9 && hero.state !== 'down' && hero.state !== 'getup') {
        if (ai.token || tk.holders.size < tk.max) {
          let total = 0;
          for (const x of attacks) if (d >= x.range[0] && d <= x.range[1]) total += x.weight ?? 1;
          if (total > 0) {
            let r = world.rng() * total, pick = null;
            for (const x of attacks) { if (d < x.range[0] || d > x.range[1]) continue; r -= x.weight ?? 1; if (r <= 0) { pick = x; break; } }
            if (pick) {
              it.attack = pick.id;
              ai.cool = (pick.cooldown ?? 1.5) + world.rng.range(patience[0], patience[1]);
              if (!ai.token) { ai.token = true; tk.holders.add(a.id); }
              ai.hold = 0.5;
              return;
            }
          }
        }
      }
      const nx = dx / (d + hero.radius + a.radius || 1), nz = dz / (d + hero.radius + a.radius || 1);
      if (d > keep + 0.5) {
        // close in (a little to one side so a pack fans out instead of queueing)
        const s = d > 4 ? 0.25 * ai.side : 0;
        it.moveX = nx + rightX(face) * s; it.moveZ = nz + rightZ(face) * s;
        it.run = o.run !== false && d > 3.2;
      } else if (d < keep - 0.6) {
        it.moveX = -nx * 0.8; it.moveZ = -nz * 0.8; it.strafe = true; it.run = false;
      } else if ((o.circle ?? 0.5) > 0 && ai.cool > 0.25) {
        const k = o.circle ?? 0.5;
        it.moveX = rightX(face) * ai.side * k; it.moveZ = rightZ(face) * ai.side * k;
        it.strafe = true; it.run = false;
      }
    },
  };
}

// ---- kinds --------------------------------------------------------------------------------------------------------

const HUSK_CLIPS = { idle: 'demo.idle', walk: 'game.walkF', run: 'game.walkF', flinch: 'game.hitLight', stagger: 'demo.hit', guard: 'demo.guard', dead: 'game.koDown', spawn: 'rpg.husk.rise' };

/** Attack table of the husk family (damage for scale 1; elites / the stand-in boss scale them). */
function huskAttacks(k = 1, reach = 1) {
  return {
    slash: {
      name: 'Rusted Cleave', duration: 1.5, clip: { clip: 'demo.combo1' },
      hits: [{ t: [0.62, 0.72], shape: { type: 'arc', r: [0.2, 2.15 * reach], angle: [-65, 65], u: [0.3, 2.0 * reach] }, damage: Math.round(58 * k), level: 'heavy', poise: 30, hitstop: 0.09, guard: 24 }],
      track: { until: 0.5, rate: 200 },
      motion: [[0, 0], [0.45, 0], [0.66, 0.5 * reach]],
      markers: [{ t: 0.5, name: 'swing' }],
    },
    lunge: {
      name: 'Husk Lunge', duration: 1.7, clip: { clip: 'demo.combo1M' },
      hits: [{ t: [0.78, 0.92], shape: { type: 'box', f: [0.1, 2.5 * reach], s: [-0.55 * reach, 0.55 * reach], u: [0.4, 1.8 * reach] }, damage: Math.round(72 * k), level: 'heavy', poise: 34, hitstop: 0.1, guard: 30 }],
      track: { until: 0.62, rate: 170 },
      motion: [[0, 0], [0.6, 0], [0.9, 2.1 * reach]],
      markers: [{ t: 0.64, name: 'swing' }],
    },
    slam: {
      name: 'Grave Slam', duration: 2.1, clip: { clip: 'demo.slam' },
      hits: [{ t: [0.98, 1.08], shape: { type: 'arc', r: [0, 2.6 * reach], angle: [-50, 50], u: [0, 2.6 * reach] }, damage: Math.round(96 * k), level: 'knockdown', poise: 60, hitstop: 0.13, guard: 44 }],
      track: { until: 0.78, rate: 150 },
      markers: [{ t: 0.84, name: 'swing' }, { t: 0.98, name: 'crack', data: { decal: 'crack', shake: 0.4 } }],
    },
  };
}

/** Register the built-in kinds (called by createRpg with registry.builtin = true). */
export function registerBuiltinKinds(reg) {
  if (!hasClip('rpg.husk.rise')) {
    // rises out of a kneel (spawn)
    defineClip('rpg.husk.rise', {
      duration: 0.7, breath: 0,
      keys: [
        { t: 0, pose: 'demo.stance', hips: { pos: [-0.05, -0.5, 0], rot: [0, -20, 0] }, bones: { spine: [0, -6, -30], chest: [0, -6, -22], neck: [0, 6, -20], head: [0, 8, -24] } },
        { t: 0.45, ease: 'inOutSine', hips: { pos: [-0.03, -0.2, 0], rot: [0, -24, 0] }, bones: { spine: [0, -8, -12], chest: [0, -6, -8], neck: [0, 8, 4], head: [0, 12, 6] } },
        { t: 0.7, ease: 'inOutSine', pose: 'demo.stance' },
      ],
    });
  }
  const husk = {
    team: 'foe',
    name: { ko: '흑일교 무사', en: 'Black Sun Cultist' },
    stats: { hp: 230, poise: 0, radius: 0.44, height: 1.9, scale: 1, mass: 1, walk: 1.5, run: 3.1, turn: 300, shards: 28, stamina: 60 },
    design: huskDesign('rpg-husk'),
    clips: HUSK_CLIPS,
    attacks: huskAttacks(1),
    roll: null, guard: null,
    controller: () => meleeController({ attacks: [{ id: 'slash', range: [0, 2.0], weight: 2, cooldown: 1.2 }, { id: 'lunge', range: [1.6, 3.6], weight: 1.2, cooldown: 1.8 }], aggro: 13, keep: 1.7 }),
  };
  reg.actor('husk', husk);
  reg.actor('husk.elite', {
    ...husk,
    name: { ko: '흑일교 호법', en: 'Black Sun Protector' },
    elite: true,
    stats: { ...husk.stats, hp: 620, poise: 70, scale: 1.28, radius: 0.56, height: 2.4, mass: 2.2, walk: 1.3, run: 2.6, turn: 240, shards: 110 },
    design: huskDesign('rpg-husk-elite', 0xc9b79a, [3.2, 0.7, 0.3]),
    attacks: huskAttacks(1.35, 1.25),
    controller: () => meleeController({ attacks: [{ id: 'slash', range: [0, 2.5], weight: 2, cooldown: 1.4 }, { id: 'lunge', range: [2.0, 4.4], weight: 1, cooldown: 2 }, { id: 'slam', range: [0, 2.9], weight: 1.4, cooldown: 2.6 }], aggro: 14, keep: 2.1, circle: 0.35 }),
  });
  reg.actor('standin.boss', {
    ...husk,
    name: { ko: '흑일마신상 (대역)', en: 'The Black Sun Idol (stand-in)' },
    boss: true, budget: 'boss', lockable: false,
    stats: { ...husk.stats, hp: 5200, poise: 420, scale: 3.6, radius: 1.5, height: 6.8, mass: 60, walk: 1.6, run: 2.6, turn: 110, shards: 900 },
    design: huskDesign('rpg-standin-boss', 0x8d8fa8, [1.2, 2.2, 6]),
    attacks: (() => { const t = huskAttacks(1.9, 3.3); for (const k in t) { t[k].duration *= 1.25; for (const h of t[k].hits) { h.t = [h.t[0] * 1.25, h.t[1] * 1.25 + 0.04]; } if (t[k].track) t[k].track.until *= 1.25; if (t[k].motion) t[k].motion = t[k].motion.map((m) => [m[0] * 1.25, m[1]]); for (const m of t[k].markers) m.t *= 1.25; } return t; })(),
    spawnTime: 1.6,
    corpseTime: 5,
    controller: () => meleeController({ attacks: [{ id: 'slash', range: [0, 6.5], weight: 2, cooldown: 1.6 }, { id: 'slam', range: [0, 7.5], weight: 2, cooldown: 2.4 }, { id: 'lunge', range: [4, 10], weight: 1, cooldown: 2.6 }], aggro: 30, keep: 4.2, circle: 0 }),
    onPoiseBreak(world, a) { a.stun('stagger', 3.2); a.data.breakT = world.time; },
  });
  reg.actor('dummy', {
    team: 'neutral',
    name: { ko: '수련 목인', en: 'Training Figure' },
    stats: { hp: 4000, poise: 0, radius: 0.44, height: 1.9, scale: 1, mass: 1.2, walk: 0, run: 0, turn: 0, shards: 0 },
    design: huskDesign('rpg-dummy', 0xb9c2d6, [0.4, 1.4, 2.6]),
    clips: HUSK_CLIPS,
    attacks: {},
    roll: null, guard: null, spawnTime: 0,
    corpseTime: 1.2,
    controller: () => ({
      kind: 'dummy',
      think(world, a, dt) {
        // heals back when left alone; never dies unless spawned { mortal: true }
        const d = a.data;
        if (d.lastHp === undefined) d.lastHp = a.hp;
        if (a.hp < d.lastHp) d.quiet = 0; else d.quiet = (d.quiet || 0) + dt;
        d.lastHp = a.hp;
        if (d.quiet > 3 && a.hp < a.hpMax) { a.hp = Math.min(a.hpMax, a.hp + a.hpMax * 0.5 * dt); d.lastHp = a.hp; }
      },
    }),
    onHit(world, a) { if (!a.data.mortal && a.hp < a.hpMax * 0.2) a.hp = a.hpMax * 0.2; },
    onSpawn(world, a, opts) { a.data.mortal = !!opts.mortal; if (opts.hp) { a.hp = a.hpMax = opts.hp; } },
  });
  void clamp; void fwdX; void fwdZ;
}

/** The core's stand-in encounters (replaced as soon as a plug-in registers its own). */
export function registerBuiltinEncounters(reg) {
  reg.encounter({ id: 'standin.husks', order: 10, title: { ko: '흑일교 무사들', en: 'BLACK SUN CULTISTS' },
    spawns: [{ kind: 'husk', x: 3.5, z: -3.2 }, { kind: 'husk', x: 5.5, z: 0.4, delay: 0.3 }, { kind: 'husk', x: 3.8, z: 3.6, delay: 0.6 }] });
  reg.encounter({ id: 'standin.pack', order: 20, title: { ko: '호법과 그 무리', en: 'THE PROTECTOR\'S BAND' },
    spawns: [{ kind: 'husk.elite', x: 6, z: 0 }, { kind: 'husk', x: 4.5, z: -3.5, delay: 0.3 }, { kind: 'husk', x: 4.5, z: 3.5, delay: 0.5 }] });
  reg.encounter({ id: 'standin.boss', order: 100, boss: true, title: { ko: '흑일마신상 黑日魔神像', en: 'THE BLACK SUN IDOL' },
    spawns: [{ kind: 'standin.boss', x: 7.5, z: 0 }] });
}
