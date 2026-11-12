// Test fixtures: deliberately nasty fighter definitions for edge-case tests and the fuzzer.

import { sampleFighter } from '../sample-fighter.js';

/** Deep clone of plain data. */
const clone = (o) => JSON.parse(JSON.stringify(o));

/**
 * Extreme-but-valid data: zero-length and last-frame windows, a hit at t = 0, tiny and long moves, very fast motion
 * (velocity and key jumps), self-cancels, overlapping armour / invulnerability / counter windows, a gravity projectile,
 * a piercing multi-hit beam, a teleport without pass-through, a lethal-capable cinematic with ticks after the finish
 * marker, and a counter whose follow-up is itself a counter stance.
 */
export const extremeFighter = {
  id: 'extreme',
  name: 'Extreme',
  stats: { hp: 700, fpMax: 60, walkSpeed: 4.5, backSpeed: 4.4, pushWidth: 0.3, hurtWidth: 0.3, height: 1.6, weight: 0.6 },
  movement: {
    dash: { duration: 0.12, distance: 3.5, cancelFrom: 0 },
    backstep: { duration: 0.6, distance: 4, invuln: [0, 0.6] },
    dodge: { duration: 0.2, invuln: [0, 0.2], cooldown: 0, cancelFrom: 0 },
    roll: { duration: 0.1, distance: 4 },
  },
  commands: {
    light: 'jab', 'f+light': 'zero', 'b+light': 'edge', 'd+light': 'blink', 'u+light': 'loop',
    heavy: 'rush', 'f+heavy': 'warp', 'd+heavy': 'pop',
    skill1: 'lob', skill2: 'beam', skill3: 'mirror', ult: 'doom',
  },
  moves: {
    jab: {
      duration: 0.05,
      hits: [{ t: [0, 0.05], box: { f: [0, 1.2], u: [0, 1.6] }, damage: 1, hitstop: 0 }],
      cancels: [{ t: [0, 0.05], on: 'light', into: 'jab' }, { t: [0, 0.05], into: ['@any', '@dodge', '@dash'] }],
    },
    zero: { duration: 0.2, hits: [{ t: [0, 0], box: { f: [-0.5, 1.5], u: [0, 2] }, damage: 40, level: 'heavy' }] },
    edge: {
      duration: 0.3,
      hits: [{ t: [0.3, 0.3], box: { f: [0, 1.5], u: [0, 2] }, damage: 60, level: 'crumple', hitstun: 2 }],
      cancels: [{ t: [0.3, 0.3], into: ['@any'] }],
    },
    loop: {
      duration: 0.4,
      hits: [{ t: [0.05, 0.35], box: { f: [-1, 1], u: [0, 3] }, damage: 0, multi: { interval: 0.0001, max: 50 }, hitstop: 0.6, juggle: 0, knockback: { x: -30, y: 30 } }],
      cancels: [{ t: [0, 0.4], on: 'light', into: 'loop' }],
    },
    rush: {
      duration: 0.6,
      motion: [{ t: [0, 0.3], v: 40 }],
      armour: [{ t: [0, 0.6], damageScale: 0 }],
      hits: [{ t: [0.05, 0.3], box: { f: [0, 0.6], u: [0, 1.6] }, damage: 30, level: 'launch', knockback: { x: 30, y: 30 }, armourPierce: true }],
      cancels: [{ t: [0.1, 0.6], into: ['@skill'], onContact: true }],
    },
    warp: {
      duration: 0.5,
      motion: { keys: [[0, 0], [0.1, 0], [0.1001, 6], [0.3, 6, 3], [0.5, 4, 0]] },
      hits: [{ t: [0.12, 0.45], box: { f: [-1, 1], u: [-0.5, 3] }, damage: 50, level: 'knockdown', unblockable: true, knockback: { x: 30, y: 0 } }],
    },
    pop: {
      duration: 0.5,
      hits: [{ t: [0.1, 0.4], box: { f: [0, 1.6], u: [0, 4] }, damage: 10, level: 'launch', knockback: { x: 0, y: 30 }, multi: { interval: 0.05, max: 6 }, juggle: 0.01 }],
      cancels: [{ t: [0.1, 0.5], into: ['pop', '@ult'], onHit: true }],
    },
    blink: {
      duration: 0.4,
      teleport: [{ t: 0, to: 'behind', distance: 0 }, { t: 0.1, to: 'forward', distance: 18 }, { t: 0.2, to: 'behind', distance: 0.1, face: false }],
      hits: [{ t: [0.2, 0.25], box: { f: [-1, 1], u: [0, 2] }, damage: 25 }],
    },
    lob: {
      duration: 0.3, fpCost: 10,
      projectiles: [
        { t: 0, box: { f: [-0.2, 0.2], u: [-0.2, 0.2] }, velocity: { x: 6, y: 9 }, gravity: 18, lifetime: 3, hit: { damage: 20, level: 'launch' } },
        { t: 0.3, at: 'opponent', box: { f: [-1, 1], u: [0, 2.5] }, delay: 0, lifetime: 0.0001, hit: { damage: 15 }, clash: false },
      ],
    },
    beam: {
      duration: 1.2, fpCost: 30, cooldown: 0.5,
      projectiles: [{ t: 0.1, box: { f: [0, 8], u: [0.5, 1.5] }, velocity: { x: 0.5, y: 0 }, lifetime: 1, multi: { interval: 0.05, max: 20 }, pierce: true, durability: 50, hit: { damage: 4, level: 'light', hitstop: 0.02, juggle: 0.05 } }],
    },
    mirror: {
      duration: 0.8, fpCost: 5,
      counter: { t: [0, 0.8], move: 'mirror2', vs: 'all', hitstop: 0 },
      invuln: [{ t: [0.79, 0.8], vs: 'projectile' }],
    },
    mirror2: {
      duration: 0.5, group: 'skill',
      counter: { t: [0, 0.5], move: 'mirror', vs: 'strike', hitstop: 0.3 },
      invuln: [{ t: [0, 0.01] }],
      hits: [{ t: [0.2, 0.2], box: { f: [-2, 2], u: [0, 3] }, damage: 35, level: 'knockdown' }],
    },
    doom: {
      ultCost: 50, superFreeze: { duration: 0.3, userAnimates: false },
      duration: 0.6,
      hits: [{ t: [0.05, 0.5], box: { f: [-0.4, 3], u: [0, 3] }, damage: 1, level: 'heavy' }],
      cinematic: {
        hit: 0, duration: 0.5, distance: 0, recovery: 0,
        ticks: [{ t: 0, damage: 999 }, { t: 0.5, damage: 999 }],
        finish: { t: 0.1, damage: 999, level: 'launch', knockback: { x: -5, y: 12 } },
        markers: [{ t: 0, name: 'a' }, { t: 0.5, name: 'b' }],
      },
    },
  },
};

/** An 8 m giant built from the sample fighter's structure (scale is a parameter). */
export const giantFighter = (() => {
  const g = clone(sampleFighter);
  g.id = 'giant';
  g.name = 'Giant';
  const k = 8 / 1.85;
  g.stats = { ...g.stats, hp: 4000, height: 8, hurtWidth: 0.42 * k * 0.6, pushWidth: 0.4 * k * 0.6, weight: 4, walkSpeed: 1.6, backSpeed: 1.2 };
  g.movement = { dash: { duration: 0.6, distance: 5 }, backstep: { duration: 0.6, distance: 3.5, invuln: [0, 0.2] }, dodge: { duration: 0.6, invuln: [0.05, 0.4], cooldown: 1.2, cancelFrom: 0.45 }, roll: { duration: 0.6, distance: 5 } };
  const scaleBox = (b) => { b.f = b.f.map((v) => v * k * 0.7); b.u = b.u.map((v) => v * k); };
  for (const mv of Object.values(g.moves)) {
    for (const h of mv.hits || []) scaleBox(h.box);
    for (const h of mv.hurt || []) scaleBox(h.box);
    for (const p of mv.projectiles || []) { scaleBox(p.box); if (p.offset) p.offset.f *= k * 0.7; }
    if (Array.isArray(mv.motion)) for (const s of mv.motion) s.v *= 1.5;
    if (mv.ai && mv.ai.range) mv.ai.range = mv.ai.range.map((v) => Math.min(18, v * k * 0.7));
    if (mv.cinematic && mv.cinematic.distance !== undefined) mv.cinematic.distance *= 2;
    if (mv.requires) for (const key of ['minDistance', 'maxDistance']) if (mv.requires[key] !== undefined) mv.requires[key] *= 2;
    for (const tp of mv.teleport || []) tp.distance *= 2.5;
  }
  return g;
})();

/**
 * A 10-move fighter with a cinematic ultimate written from README.md alone, with no `ai` hints: the authoring
 * smoke test (it must validate warning-free and the generic AI must find a use for every move).
 */
export const authoredFighter = {
  id: 'lancer', name: 'Test Lancer',
  stats: { walkSpeed: 2.7, backSpeed: 2.0 },
  commands: { light: 'jab1', heavy: 'sweep', 'f+heavy': 'rush', 'd+heavy': 'rise', skill1: 'throw', skill2: 'storm', skill3: 'parry', ult: 'judgement' },
  moves: {
    jab1: { duration: 0.34, hits: [{ t: [0.09, 0.13], box: { f: [0.3, 2.0], u: [0.9, 1.6] }, damage: 32 }], cancels: [{ t: [0.12, 0.32], on: 'light', into: 'jab2' }, { t: [0.12, 0.28], into: ['@skill', '@ult', 'rise'], onHit: true }] },
    jab2: { duration: 0.38, hits: [{ t: [0.1, 0.14], box: { f: [0.3, 2.1], u: [0.8, 1.7] }, damage: 36 }], cancels: [{ t: [0.13, 0.36], on: 'light', into: 'jab3' }, { t: [0.13, 0.3], into: ['@skill', '@ult', 'rise'], onHit: true }] },
    jab3: { duration: 0.6, motion: [{ t: [0.05, 0.2], v: 4 }], hits: [{ t: [0.2, 0.26], box: { f: [0.2, 2.4], u: [0.2, 1.9] }, damage: 70, level: 'knockdown', knockback: { x: 6, y: 3 } }] },
    sweep: { duration: 0.8, armour: [[0.1, 0.36]], hits: [{ t: [0.36, 0.44], box: { f: [0.2, 2.6], u: [0, 1.0] }, damage: 100, level: 'heavy' }], cancels: [{ t: [0.4, 0.6], into: ['@skill', '@ult'], onHit: true }] },
    rush: { duration: 0.7, motion: [{ t: [0.1, 0.3], v: 14 }], hits: [{ t: [0.2, 0.32], box: { f: [0.2, 2.2], u: [0.7, 1.6] }, damage: 85, level: 'crumple' }], cancels: [{ t: [0.32, 0.5], into: ['rise', '@skill', '@ult'], onHit: true }] },
    rise: { duration: 0.64, hits: [{ t: [0.17, 0.25], box: { f: [0.2, 1.8], u: [0, 2.4] }, damage: 66, level: 'launch', knockback: { x: 1, y: 9 } }], cancels: [{ t: [0.24, 0.45], into: ['@skill', '@ult'], onHit: true }] },
    throw: { duration: 0.6, fpCost: 25, cooldown: 3.5, projectiles: [{ t: 0.24, kind: 'spear', box: { f: [-0.6, 0.6], u: [-0.15, 0.15] }, velocity: { x: 16 }, lifetime: 0.7, hit: { damage: 60, level: 'heavy' } }] },
    storm: { duration: 1.0, fpCost: 35, cooldown: 7, hits: [{ t: [0.15, 0.6], box: { f: [-0.5, 2.2], u: [0, 2] }, damage: 16, multi: { interval: 0.09, max: 5 }, scaleStep: 0.04 }, { t: [0.7, 0.76], box: { f: [0, 2.2], u: [0, 2.4] }, damage: 55, level: 'launch' }] },
    parry: { duration: 0.8, fpCost: 25, cooldown: 8, counter: { t: [0.04, 0.5], move: 'riposte', vs: 'all' } },
    riposte: { duration: 0.55, group: 'skill', invuln: [[0, 0.3]], hits: [{ t: [0.06, 0.14], box: { f: [-1, 2.4], u: [0, 2.2] }, damage: 100, level: 'knockdown', unblockable: true }] },
    judgement: {
      ultCost: 100, superFreeze: 0.5, duration: 1.4, invuln: [[0.5, 0.8]],
      motion: [{ t: [0.5, 0.7], v: 15 }],
      hits: [{ t: [0.62, 0.8], box: { f: [0, 2.0], u: [0, 2.2] }, damage: 90, level: 'heavy' }],
      cinematic: { duration: 4.6, distance: 1.6, ticks: [{ t: 0.4, damage: 50, marker: 'pierce' }, { t: 1.0, damage: 50, marker: 'lift' }, { t: 1.6, damage: 50, marker: 'storm' }], finish: { t: 3.6, damage: 230, level: 'knockdown', marker: 'thunderfall' }, markers: [{ t: 0, name: 'lock' }, { t: 4.4, name: 'land' }] },
      markers: [{ t: 0, name: 'charge' }, { t: 0.5, name: 'dash' }],
    },
  },
};

export { clone };
