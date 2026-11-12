// Shared constants and defaults of the rules engine. Pure data, no imports.
// Every number is in metres, seconds or meter points unless the comment says otherwise.

/** Hit levels, from weakest to strongest reaction. */
export const LEVELS = ['light', 'heavy', 'launch', 'crumple', 'knockdown'];

/** Every boolean button of an input state (`move` is the separate -1|0|1 axis). */
export const BUTTONS = ['up', 'down', 'light', 'heavy', 'skill1', 'skill2', 'skill3', 'ult', 'guard', 'dodge'];

/** Buttons that start moves through the command map, in resolution priority order (first wins). */
export const ATTACK_BUTTONS = ['ult', 'skill1', 'skill2', 'skill3', 'heavy', 'light'];

/** Direction prefixes of command keys ('f+heavy'), relative to the fighter's facing. Checked in this order. */
export const DIR_PREFIXES = ['d', 'u', 'f', 'b'];

/** Move groups. Cancel windows can name a whole group as '@normal', '@skill', '@ult' (or '@any'). */
export const GROUPS = ['normal', 'skill', 'ult'];

/** Cancel tokens that are not move ids. */
export const CANCEL_TOKENS = ['@any', '@normal', '@skill', '@ult', '@dodge', '@dash'];

/** Fighter states (fighter.state). */
export const STATES = [
  'intro', 'idle', 'walk', 'dash', 'backstep', 'roll', 'dodge', 'guard', 'blockstun', 'attack', 'hitstun',
  'launched', 'knockdown', 'getup', 'guardbreak', 'locked', 'recovery', 'ko', 'victory', 'defeat',
];

/** States in which the fighter reads the stick and buttons freely. */
export const NEUTRAL_STATES = new Set(['idle', 'walk', 'guard']);

/** States in which the fighter is the victim of a running combo. */
export const COMBO_STATES = new Set(['hitstun', 'launched', 'guardbreak', 'locked']);

/** A neutral input state (what a controller returns when nothing is held). */
export const NEUTRAL_INPUT = Object.freeze({
  move: 0, up: false, down: false, light: false, heavy: false, skill1: false, skill2: false, skill3: false,
  ult: false, guard: false, dodge: false,
});

/**
 * Match rules. Pass a partial object as `createMatch({ rules })`; nested objects merge key by key.
 * See README.md "Rules" for the meaning of every field.
 */
export const DEFAULT_RULES = {
  roundsToWin: 2,
  maxRounds: 5,
  roundTime: 99,
  introTime: 2.2,
  koTime: 2.8,
  timeUpTime: 2.0,
  outroTime: 2.4,

  arenaHalfWidth: 9,
  startX: 2.5,
  maxSeparation: 11,

  gravity: 24,
  groundFriction: 15,
  airDrag: 0.4,

  maxSubstep: 1 / 60,
  maxStep: 0.1,

  inputBuffer: 0.2,
  doubleTapWindow: 0.22,
  turnDelay: 0.05,

  combo: {
    fullHits: 2,        // hits at 100 % damage before scaling starts
    step: 0.1,          // damage scale lost per further hit
    floor: 0.4,         // minimum damage scale
    hitstunStep: 0.03,  // hitstun lost per hit (fraction)
    hitstunFloor: 0.5,  // minimum hitstun multiplier
    hitstunTime: 3.0,   // after this many seconds of combo, hitstun decays further ...
    hitstunTimeRate: 0.15, // ... by this fraction per second
    maxHits: 40,        // safety net: past this many hits (or maxTime) every hit becomes a knockdown
    maxTime: 8,
  },
  juggle: { limit: 6, gravityStep: 0.08, pop: 4.2, airHitstunCarry: true },
  counterHit: { damage: 1.2, hitstun: 1.3, hitstop: 1.35 },
  block: { hitstopScale: 0.75, pushbackScale: 0.85, perfectWindow: 0.12, perfectStunScale: 0.5, chipCanKO: false },
  chip: { normal: 0, skill: 0.15, ult: 0.2 },
  guardDamageRatio: 0.3,
  guardBreakTime: 1.1,
  knockdownTime: 0.7,
  getupTime: 0.45,
  techRollDistance: 1.4,
  wallBounce: { speed: 5.5, restitution: 0.35, pop: 4.5, max: 1 },
  cinematicScaleFloor: 0.7,

  meters: {
    fpStart: 100,
    fpRegen: 7,          // per second
    fpRegenDelay: 0.6,   // seconds after spending FP before regen resumes
    fpOnHit: 1.0,        // FP gained per hit dealt
    ultDeal: 0.055,      // ULT gained per HP of damage dealt
    ultTake: 0.075,      // ULT gained per HP of damage taken
    ultBlockDeal: 0.02,  // per point of chip / guard damage dealt
    ultBlockTake: 0.03,
    ultCarry: true,      // ULT carries between rounds (HP and FP reset)
    guardRegen: 22,      // guard gauge per second
    guardRegenDelay: 1.0,
    guardRegenWhileGuarding: 0.35,
  },
};

/** Fighter stats defaults (def.stats). */
export const DEFAULT_STATS = {
  hp: 1000,
  fpMax: 100,
  ultMax: 100,
  guardMax: 100,
  walkSpeed: 2.5,
  backSpeed: 1.8,
  weight: 1,
  pushWidth: 0.4,
  hurtWidth: 0.42,
  height: 1.85,
};

/** Movement defaults (def.movement). Times in seconds, distances in metres. */
export const DEFAULT_MOVEMENT = {
  dash: { duration: 0.3, distance: 2.4, cancelFrom: 0.14 },
  backstep: { duration: 0.34, distance: 1.7, invuln: [0, 0.14] },
  dodge: { duration: 0.42, invuln: [0.02, 0.3], cooldown: 0.7, cancelFrom: 0.3 },
  roll: { duration: 0.42, distance: 2.6 },
};

/** Defaults filled into every hit (move hits and projectile hits). */
export const HIT_DEFAULTS = {
  light: { hitstun: 0.3, blockstun: 0.18, knockback: { x: 2.4, y: 0 }, hitstop: 0.06 },
  heavy: { hitstun: 0.45, blockstun: 0.26, knockback: { x: 4.2, y: 0 }, hitstop: 0.1 },
  launch: { hitstun: 0.5, blockstun: 0.26, knockback: { x: 1.2, y: 8.5 }, hitstop: 0.11 },
  crumple: { hitstun: 0.95, blockstun: 0.26, knockback: { x: 1.0, y: 0 }, hitstop: 0.12 },
  knockdown: { hitstun: 0.5, blockstun: 0.28, knockback: { x: 4.5, y: 3.4 }, hitstop: 0.12 },
};
