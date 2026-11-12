// SAMPLE FIGHTER — a generic sword fighter that exercises every feature of the rules engine.
// Copy this file to start a real fighter (src/fighters/<id>/moves.js) and change the numbers, names and markers.
//
// Conventions (see README.md for the full reference):
//   * Times are SECONDS from the start of the move. 1 frame @60 fps = 0.0167 s.
//   * Boxes are in the FIGHTER-LOCAL frame: f = metres forward of the fighter's origin (the feet, at the body
//     centre), u = metres above the floor. { f: [0.3, 1.7], u: [0.8, 1.7] } is a chest-high slash reaching 1.7 m.
//     Height reference: fighters ~1.9 m tall, chest 1.35, head 1.75, hips 1.0.
//   * knockback is a VELOCITY in m/s: x along the attacker's forward, y up. A grounded slide of x m/s travels about
//     x^2 / (2 * rules.groundFriction) metres (2.4 -> 0.19 m, 4.5 -> 0.68 m).
//   * Every hit needs t (window), box and damage; every other hit field has a level-based default (constants.js
//     HIT_DEFAULTS), so write only what you want to differ.
//   * markers are the hooks for presentation: clips, VFX, camera and audio are triggered by marker names; the rules
//     never look at them. Name them after what happens on screen ('slash', 'release', 'impact').
//   * ai hints are optional: range (centre-to-centre metres at which the move is a good idea), role, weight.
//
// Frame data of this file:  node src/game/logic/test/framedata.mjs

/** The sample fighter definition (author format; see README.md "Fighter definition"). */
export const sampleFighter = {
  id: 'sample',
  name: '견본 검사 · Sample Swordsman',
  title: 'engine template',

  // Body and locomotion. Every field is optional (defaults in constants.js DEFAULT_STATS).
  stats: {
    hp: 1000,          // HP, reset every round
    fpMax: 100,        // focus points, spent by skills, regenerate (rules.meters.fpRegen per second)
    ultMax: 100,       // ultimate gauge, filled by dealing and taking damage, carried between rounds
    guardMax: 100,     // guard gauge, drained by blocking, empty = guard break
    walkSpeed: 2.5,    // m/s walking forward
    backSpeed: 1.8,    // m/s walking back (slower than forward)
    weight: 1,         // knockback is divided by this
    pushWidth: 0.4,    // half-width of the push-box (fighters never overlap closer than the sum)
    hurtWidth: 0.42,   // half-width of the standing hurtbox
    height: 1.85,      // hurtbox height
  },

  // Dash (double-tap forward or dodge + forward), backstep (double-tap back or dodge + back), dodge (dodge alone:
  // short sidestep with an invulnerable window and a cooldown). A forward dash with the back to a wall and the
  // opponent in your face becomes a 'roll' that passes through (the corner escape).
  movement: {
    dash: { duration: 0.3, distance: 2.4, cancelFrom: 0.14 },      // attacks may cancel the dash from 0.14 s
    backstep: { duration: 0.34, distance: 1.7, invuln: [0, 0.14] }, // strike-invulnerable at the start
    dodge: { duration: 0.42, invuln: [0.02, 0.3], cooldown: 0.7, cancelFrom: 0.3 },
    roll: { duration: 0.42, distance: 2.6 },
  },

  // Command map: button (with optional direction prefix relative to facing: f+ b+ d+ u+) -> move id.
  // Resolution order for a press: d+ , u+ , f+ , b+ , plain. Missing slots are simply unavailable.
  commands: {
    light: 'light1',
    heavy: 'heavy',
    'f+heavy': 'lunge',
    'd+heavy': 'launcher',
    skill1: 'crescent',
    'b+skill1': 'grave',
    skill2: 'tempest',
    skill3: 'ward',
    'f+skill3': 'phase_step',
    'b+skill3': 'blink',
    ult: 'verdict',
  },

  // Optional AI personality: aggression 0..1 (rushdown vs patient), zoning 0..1 (how much it likes projectiles).
  ai: { aggression: 0.55, zoning: 0.45 },

  moves: {
    // ---------------------------------------------------------------------------------------------------------
    // LIGHT CHAIN: light1 -> light2 -> light3 by pressing light inside the route windows.
    light1: {
      name: 'Quick Cut',
      duration: 0.36,
      hits: [{
        t: [0.1, 0.14],                            // active from 0.10 s (6 f startup) to 0.14 s
        box: { f: [0.3, 1.75], u: [0.8, 1.7] },
        damage: 34,
        level: 'light',                            // light flinch
        hitstun: 0.3, blockstun: 0.2,              // +2 f on hit, -4 f on block
        knockback: { x: 2.0, y: 0 },
        hitstop: 0.06,
        guardDamage: 8,
      }],
      cancels: [
        // route: pressing light from 0.13 s to 0.34 s goes to light2 (works on whiff too: a real chain)
        { t: [0.13, 0.34], on: 'light', into: 'light2' },
        // on hit: anything in this list may cancel (launcher via d+heavy, any skill, the ultimate)
        { t: [0.12, 0.3], into: ['launcher', '@skill', '@ult'], onHit: true },
      ],
      markers: [{ t: 0.06, name: 'swing', data: { trail: 'light' } }, { t: 0.1, name: 'slash' }],
      ai: { range: [0, 1.75], role: 'poke', weight: 1.3 },
    },
    light2: {
      name: 'Return Cut',
      duration: 0.4,
      motion: [{ t: [0, 0.12], v: 2.5 }],          // velocity segment: 2.5 m/s forward for 0.12 s (0.3 m)
      hits: [{
        t: [0.11, 0.15], box: { f: [0.3, 1.85], u: [0.7, 1.8] },
        damage: 40, level: 'light', hitstun: 0.32, blockstun: 0.2, knockback: { x: 2.4, y: 0 }, hitstop: 0.065,
      }],
      cancels: [
        { t: [0.14, 0.38], on: 'light', into: 'light3' },
        { t: [0.13, 0.32], into: ['launcher', 'lunge', '@skill', '@ult'], onHit: true },
      ],
      markers: [{ t: 0.07, name: 'swing', data: { trail: 'light' } }, { t: 0.11, name: 'slash' }],
      ai: { role: 'combo', comboOnly: true },
    },
    light3: {
      name: 'Cleaving Finish',
      duration: 0.62,
      motion: [{ t: [0.05, 0.22], v: 3 }],
      hits: [{
        t: [0.2, 0.26], box: { f: [0.2, 2.0], u: [0.2, 2.0] },
        damage: 72, level: 'knockdown',            // ends the chain with a knockdown (no juggle after it) ...
        knockback: { x: 6, y: 3.2 },               // ... unless it slams into a wall (x >= rules.wallBounce.speed bounces)
        hitstop: 0.12, blockstun: 0.24, guardDamage: 18,
      }],
      cancels: [{ t: [0.22, 0.36], into: ['@skill'], onContact: true }], // hit or block: skill cancel to stay safe
      markers: [{ t: 0.12, name: 'swing', data: { trail: 'heavy' } }, { t: 0.2, name: 'impact', data: { shake: 0.3 } }],
      ai: { role: 'combo', comboOnly: true },
    },

    // ---------------------------------------------------------------------------------------------------------
    // HEAVY with hyper-armour: absorbs one hit during the wind-up (takes the damage, does not flinch).
    heavy: {
      name: 'Iron Sweep',
      duration: 0.78,
      armour: [{ t: [0.08, 0.34], hits: 1 }],
      // extra hurtbox: the blade stays out during the recovery, so a whiffed sweep can be punished at its tip
      hurt: [{ t: [0.42, 0.62], box: { f: [0.3, 1.9], u: [0.6, 1.6] } }],
      hits: [{
        t: [0.34, 0.42], box: { f: [0.2, 2.3], u: [0.3, 1.9] },
        damage: 105, level: 'heavy', hitstun: 0.5, blockstun: 0.3, knockback: { x: 4.5, y: 0 }, hitstop: 0.11, guardDamage: 28,
      }],
      cancels: [{ t: [0.38, 0.55], into: ['@skill', '@ult'], onHit: true }],
      markers: [{ t: 0, name: 'windup', data: { armour: true } }, { t: 0.28, name: 'swing', data: { trail: 'heavy' } }, { t: 0.34, name: 'impact' }],
      ai: { range: [0.8, 2.25], role: 'pressure', weight: 0.8 },
    },

    // LUNGE: travels 2.6 m with a velocity segment and crumples on hit.
    lunge: {
      name: 'Lunging Thrust',
      duration: 0.72,
      motion: [{ t: [0.1, 0.3], v: 13 }],
      hits: [{
        t: [0.22, 0.32], box: { f: [0.3, 1.6], u: [0.7, 1.6] },
        damage: 88, level: 'crumple', hitstun: 0.95, blockstun: 0.22, knockback: { x: 1.5, y: 0 }, hitstop: 0.12,
        armourPierce: true,                        // goes through hyper-armour (it still loses to guard and dodge)
      }],
      cancels: [{ t: [0.32, 0.52], into: ['launcher', '@skill', '@ult'], onHit: true }],
      markers: [{ t: 0.08, name: 'dash', data: { afterimage: true } }, { t: 0.22, name: 'thrust' }],
      ai: { range: [2.2, 4.1], role: 'approach', weight: 0.7 },
    },

    // LAUNCHER: sends the opponent up for a juggle (each air hit adds juggle points; rules.juggle.limit caps it).
    launcher: {
      name: 'Rising Launcher',
      duration: 0.66,
      hits: [{
        t: [0.18, 0.26], box: { f: [0.2, 1.6], u: [0, 2.2] },
        damage: 70, level: 'launch', knockback: { x: 1.0, y: 9 }, hitstop: 0.1, blockstun: 0.22,
      }],
      cancels: [{ t: [0.24, 0.45], into: ['@skill', '@ult'], onHit: true }],
      markers: [{ t: 0.12, name: 'swing', data: { trail: 'rising' } }, { t: 0.18, name: 'launch' }],
      ai: { range: [0, 1.55], role: 'launcher', weight: 0.6 },
    },

    // ---------------------------------------------------------------------------------------------------------
    // SKILL 1 — projectile. Spawned at t, travels along forward, clashes with enemy projectiles (durability 1).
    crescent: {
      name: 'Crescent Wave',
      duration: 0.7,
      fpCost: 25,
      cooldown: 4,
      projectiles: [{
        t: 0.26,
        kind: 'crescent',                          // presentation picks the VFX by kind
        offset: { f: 0.8, u: 0 },                  // spawn point, fighter-local
        box: { f: [-0.4, 0.4], u: [0, 2.0] },      // relative to the projectile position, f along its travel
        velocity: { x: 11, y: 0 },                 // m/s, x = forward
        lifetime: 0.9,
        durability: 1,
        hit: { damage: 70, level: 'heavy', hitstun: 0.5, blockstun: 0.26, knockback: { x: 3.5, y: 0 }, hitstop: 0.1 },
      }],
      markers: [{ t: 0, name: 'windup', data: { groove: true } }, { t: 0.26, name: 'release' }],
      ai: { range: [3, 9], role: 'zoning', weight: 1 },
    },

    // b+SKILL 1 — delayed strike AT THE OPPONENT: spawns where the opponent stands, telegraphs for 0.45 s (the
    // presentation draws the rune from projectileSpawn), then hits up to 3 times. Shares the skill1 cooldown.
    grave: {
      name: 'Grave Pillar',
      duration: 0.8,
      fpCost: 25,
      cooldown: 4,
      cooldownKey: 'crescent',                     // same key as Crescent Wave: one cooldown for the skill1 slot
      requires: { minDistance: 2.5 },              // refused (moveDenied 'distance') up close
      projectiles: [{
        t: 0.3,
        kind: 'grave_pillar',
        at: 'opponent',                            // anchored at the opponent's x when spawned
        box: { f: [-0.6, 0.6], u: [0, 2.6] },
        velocity: { x: 0, y: 0 },
        delay: 0.45,                               // harmless telegraph, then active
        lifetime: 0.3,
        multi: { interval: 0.1, max: 3 },
        pierce: true,                              // stays for its whole lifetime after the last hit
        clash: false,                              // ground eruption: does not clash with flying projectiles
        hit: { damage: 30, level: 'light', hitstun: 0.4, blockstun: 0.2, knockback: { x: 0.5, y: 0 }, hitstop: 0.05, juggle: 0.5 },
      }],
      markers: [{ t: 0, name: 'cast' }, { t: 0.3, name: 'rune' }],
      ai: { range: [2.5, 7], role: 'zoning', weight: 0.6 },
    },

    // SKILL 2 — multi-hit: one hit window that connects up to 5 times 0.09 s apart, then a launching finisher.
    tempest: {
      name: 'Tempest Whirl',
      duration: 1.05,
      fpCost: 35,
      cooldown: 7,
      motion: [{ t: [0.15, 0.65], v: 2.8 }],
      hits: [
        {
          t: [0.18, 0.62], box: { f: [-0.6, 1.6], u: [0.2, 2.0] },
          damage: 18, level: 'light', hitstun: 0.35, blockstun: 0.2, knockback: { x: 0.6, y: 0 }, hitstop: 0.04,
          multi: { interval: 0.09, max: 5 },
          juggle: 0.4,                             // fractional juggle cost so the spin can carry a juggle
          scaleStep: 0.04,                         // gentler combo scaling per sub-hit
        },
        {
          t: [0.74, 0.8], box: { f: [0, 1.8], u: [0, 2.3] },
          damage: 60, level: 'launch', knockback: { x: 1.5, y: 8 }, hitstop: 0.14, blockstun: 0.26,
        },
      ],
      cancels: [{ t: [0.8, 0.95], into: ['@ult'], onHit: true }],
      markers: [{ t: 0.15, name: 'spin_start' }, { t: 0.62, name: 'spin_end' }, { t: 0.74, name: 'uppercut' }],
      ai: { range: [0, 2.3], role: 'combo', weight: 0.8 },
    },

    // SKILL 3 — counter stance: if struck (strike or projectile) during [0.05, 0.6], the hit is nullified and the
    // fighter instantly performs 'ward_burst'. Whiffed: 0.3 s of recovery.
    ward: {
      name: 'Ember Ward',
      duration: 0.9,
      fpCost: 30,
      cooldown: 9,
      counter: { t: [0.05, 0.6], move: 'ward_burst', vs: 'all', hitstop: 0.12 },
      markers: [{ t: 0, name: 'stance' }, { t: 0.6, name: 'stance_end' }],
      ai: { role: 'counter', weight: 0.45 },
    },
    ward_burst: {
      name: 'Ember Ward — Burst',
      group: 'skill',                              // not in the command map: reached through the counter only
      duration: 0.6,
      invuln: [{ t: [0, 0.3] }],                   // vs 'all' by default
      hits: [{
        t: [0.06, 0.14], box: { f: [-1.2, 2.2], u: [0, 2.2] },
        damage: 110, level: 'knockdown', knockback: { x: 5, y: 4 }, hitstop: 0.18, unblockable: true,
      }],
      markers: [{ t: 0, name: 'counter_flash' }, { t: 0.06, name: 'explosion', data: { radius: 2.2 } }],
    },

    // COMMAND DASH (f+skill3): passes through the opponent (push-boxes off) while invulnerable; attacks may
    // cancel the end of it (light / heavy / launcher), and every move faces the opponent at its start.
    phase_step: {
      name: 'Phase Step',
      duration: 0.5,
      fpCost: 15,
      cooldown: 3,
      motion: [{ t: [0.04, 0.26], v: 15 }],
      passThrough: [[0.04, 0.3]],
      invuln: [{ t: [0.02, 0.28], vs: 'all' }],
      cancels: [{ t: [0.26, 0.42], into: ['light1', 'heavy', 'launcher'] }],
      markers: [{ t: 0.04, name: 'vanish' }, { t: 0.26, name: 'reappear' }],
      ai: { range: [1.0, 3.4], role: 'mobility', weight: 0.5 },
    },

    // b+SKILL 3 — TELEPORT behind the opponent, turn around and cut (a cross-up: guards facing the wrong way fail).
    blink: {
      name: 'Umbral Blink',
      duration: 0.72,
      fpCost: 20,
      cooldown: 6,
      requires: { maxDistance: 4.5 },
      invuln: [{ t: [0.12, 0.26], vs: 'all' }],
      passThrough: [[0.12, 0.3]],
      teleport: [{ t: 0.2, to: 'behind', distance: 1.1, face: true }], // 1.1 m past the opponent, then face it
      hits: [{
        t: [0.32, 0.37], box: { f: [0.2, 1.6], u: [0.5, 1.9] },
        damage: 65, level: 'heavy', hitstun: 0.48, blockstun: 0.22, knockback: { x: 3, y: 0 }, hitstop: 0.1,
      }],
      cancels: [{ t: [0.37, 0.55], into: ['@skill', '@ult'], onHit: true }],
      markers: [{ t: 0.12, name: 'vanish' }, { t: 0.2, name: 'reappear' }, { t: 0.32, name: 'slash' }],
      ai: { range: [1.2, 4.5], role: 'pressure', weight: 0.4 },
    },

    // ---------------------------------------------------------------------------------------------------------
    // ULTIMATE: 0.6 s super-freeze (opponent and clock frozen; this fighter's timeline keeps running so the
    // wind-up animation plays on it), then a leap-slash. If hit 0 connects unblocked, a 4.2 s cinematic lock runs:
    // ticks deal scheduled damage, the finish knocks down. Blocked or whiffed: the move simply recovers.
    verdict: {
      name: 'Eclipse Verdict',
      ultCost: 100,                                // needs a full bar; an ultimate empties the bar
      superFreeze: 0.6,
      duration: 1.6,
      invuln: [{ t: [0.6, 0.86], vs: 'all' }],
      motion: { keys: [[0, 0], [0.6, 0], [0.72, 0.6, 0.45], [0.84, 3.4, 0.7], [0.94, 3.9, 0.2], [1.0, 4.0, 0]] }, // [t, forward, up]
      hits: [{
        t: [0.82, 0.98], box: { f: [0, 1.9], u: [0, 2.4] },
        damage: 80, level: 'heavy', hitstop: 0.2, blockstun: 0.32, guardDamage: 30,
      }],
      cinematic: {
        hit: 0,                                    // index into hits: the trigger
        duration: 4.2,                             // lock length (s, its own clock starting at the trigger)
        distance: 1.4,                             // the victim is placed this far in front of the attacker
        recovery: 0.6,                             // attacker recovery after the lock (invulnerable)
        ticks: [
          { t: 0.3, damage: 40, hitstop: 0.06, marker: 'x_cut_1' },
          { t: 0.42, damage: 40, hitstop: 0.06, marker: 'x_cut_2' },
          { t: 0.54, damage: 40, hitstop: 0.06, marker: 'x_cut_3' },
          { t: 1.3, damage: 60, hitstop: 0.1, marker: 'hurl' },
        ],
        finish: { t: 3.0, damage: 220, level: 'knockdown', knockback: { x: 4, y: 4 }, hitstop: 0.25, marker: 'meteor' },
        markers: [
          { t: 0, name: 'lock_impact', data: { impactFrame: true } },
          { t: 1.8, name: 'leap_after' },
          { t: 3.3, name: 'shockwave' },
          { t: 4.2, name: 'rise' },
        ],
      },
      markers: [{ t: 0, name: 'raise' }, { t: 0.6, name: 'leap' }, { t: 0.82, name: 'slash' }, { t: 1.0, name: 'land' }],
      ai: { range: [0, 4.6], role: 'finisher', weight: 1 },
    },
  },
};

export default sampleFighter;
