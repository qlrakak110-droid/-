// ISKA 이스카 — 서릿별 무녀 · Froststar Oracle. Rules definition (pure data for src/game/logic; see its README.md).
// Twin crescent blades: the fastest walk, dash and startups of the roster, low damage per hit, long multi-hit strings,
// mobility (a slide-through, a blink, a backflip launcher) and zoning (ice shards, a racing line of spikes).
// Creative brief: src/fighters/MOVES.md. Frame data: node src/game/logic/test/framedata.mjs src/fighters/iska/moves.js
//
// SLOTS (move id <- command; meta.slot = the roster slot name used by the UI move list)
//   light1  rime_flick          light            서리 긋기 Rime Flick           0.09 startup, chain starter
//   light2  twin_moons          (light route)    쌍월 Twin Moons                left then right (2 hits)
//   light3  star_fan            (light route)    별부채 Star Fan                spinning double slash, shards, knockback
//   heavy   glacier_pirouette   heavy            빙결 회전 Glacier Pirouette     full spin, 3 hits, frost ring (hits behind too)
//   fheavy  frostline_step      f+heavy          얼음길 Frostline Step          3.5 m ice slide through the opponent, 2 cuts (1.6..4.3 m)
//   dheavy  rising_crescent     d+heavy          초승 올려치기 Rising Crescent    backflip launcher
//   skill1  starshard_volley    skill1           서릿별 투창 Starshard Volley    3 shards 14 m/s, the third freezes (crumple)
//   skill2  crystal_procession  skill2           빙정 행렬 Crystal Procession    5 spikes racing 7 m, growing, launch
//   skill3  moonlit_afterimage  skill3           월광 잔상 Moonlit Afterimage    intangible blink counter, cut from behind + statue (2 hits)
//   ult     frozen_star         ult              떨어지는 서릿별 Fall of the Frozen Star
//
// COMBO GRAMMAR (cancel routes)
//   light1 -> light2 -> light3                       chain (also on whiff / block: a real string)
//   light1 / light2 on hit -> heavy, d+heavy, any skill, ult      (light1 also -> f+heavy)
//   light3 on hit -> any skill, ult ;  light3 on block -> skill1 (shards keep the pressure safe)
//   heavy on hit -> any skill, ult                   (no second launcher: the spin also extends juggles, where a
//                                                    Rising Crescent off an airborne victim whiffs)
//   f+heavy on hit (Iska ends behind the victim) -> light1, heavy, d+heavy, any skill
//                                                    (no ult: the slide is the juggle extender after d+heavy, and the
//                                                    ground rune misses an airborne victim)
//   d+heavy on hit (launch) -> skill1 / skill2 / f+heavy (juggles; the ult rune cannot touch an airborne victim)
//   skill1 on hit -> skill2, ult ;  skill2 on hit -> skill1 (juggle) ;  skill3 on hit -> ult
//   e.g.  light1 > light2 > heavy > d+heavy > skill1        10 hits, ~180 damage
//         light1 > light2 > light3 > skill1 (crumple) > ult  the bread-and-butter into the lock
//
// TIMELINE MARKERS (`marker` events; presentation hangs clips, trails, VFX, camera and audio on these names — the rules
// never read them). Beat notation of MOVES.md: WIND-UP -> RELEASE -> IMPACT -> AFTERMATH -> SETTLE.
//   every move    windup    WIND-UP starts: anticipation pose / clip start (t = 0)
//                 trailOn   blade trails on.
//                           data: { blades: 'R' | 'L' | 'both', style: 'light' | 'heavy' | 'spin' | 'rising' }
//                 swing     RELEASE of a strike: the smear starts (a frame or two before the first active frame)
//                 release   RELEASE of a skill / the ultimate: the thing leaves (shard, spike line, rune snap)
//                 (impact)  IMPACT needs no marker: the engine's `hit` event carries contact point, level and hit-stop
//                 trailOff  trails off: AFTERMATH / follow-through
//                 recover   SETTLE: back toward the guard pose
//   Hits carry a `label` (echoed in `hit` events): flick | left right | spin shards | spin frostRing | slash | crescent |
//   strike (+ the statue projectile) | rune.
//   twin_moons          slashL slashR                    each blade's cut (also on whiff)
//   star_fan            spin shards                      spin starts / crystalline shard burst on the knockback cut
//   glacier_pirouette   spin1 spin2 spin3 frostRing      each revolution's cut / the frost ring on the third
//   frostline_step      iceLine slide stop               ice line forms ahead / slide starts / she stops (behind
//                                                        the victim on a hit)
//   rising_crescent     flip land                        backflip take-off (crescent trail of starlight) / touch-down
//   starshard_volley    crystallise shard1 shard2 shard3 shards form in a fan / each shard fires (`frost.shard`)
//   crystal_procession  stab frost crack spike1..spike5  blades into the floor / frost spreads / the line races / each
//                                                        spike erupts (camera cue: slow-mo 0.7 on spike5). The spikes'
//                                                        own VFX follow projectileSpawn / projectileActive (kind
//                                                        'frost.spike', data.index, data.size); each holds data.hold
//                                                        = 0.6 s after erupting, then shatters (`frost.shatter`)
//   moonlit_afterimage  blink statue vanish reappear strike shatter
//                                                        blink back / frozen statue left at the start spot / gone /
//                                                        behind the opponent (whip-pan; the rules teleport, 0.06 s
//                                                        before the cut so a guard can turn) / her cut at 0.30 / the
//                                                        statue bursts forward (projectile kind 'frost.statue')
//   frozen_star (move clock)   superFreeze (engine, t = 0) windup aura trailOn rune release snap trailOff recover
//                              release = the super-freeze ends and the circle starts to close; snap = first active frame.
//                              On a hit the lock takes over at snap (moveEnd 'cinematic'): trailOff / recover fire only
//                              on a whiff (the rune shatters harmlessly, 0.5 s recovery)
//   frozen_star (lock clock, `cinematic: true` markers; ticks and the finish emit their own `marker`)
//                              crystal (0.01: the engine emits no lock marker at exactly t = 0; cinematicStart is that
//                              instant) orbit slash1..slash6 leap constellation starfall lance1..lance12 land shatter
//                              frostWave blendBack settle
//
// ULTIMATE TIMING (roster convention, the same for Kael and Vorn: MOVES.md times are seconds from MOVE start, and the
// lock continues that clock from the trigger, so storyboard t = trigger move time + lock t; every lock marker / tick
// carries its storyboard time in data.storyboard, the anchor is meta.storyboardAtTrigger). Rows 0.00 and 0.60 are the
// opener on the move clock: super-freeze 0..0.6 s (face close-up), then the top-down rune shot while the circle snaps
// shut (unblockable, active 0.75..0.95). The trigger is the rune's first active frame, move time 0.75, so
// storyboard t = 0.75 + lock t. Lock 0 .. 0.45 is the crystal-encasing beat of the top-down shot (frost.nova,
// ice_form; meta.impact). The lock lasts 5.4 s: the 5.40 row (blend back, Iska flicks the frost off her blades) starts
// at lock 4.65 and runs to cinematicEnd at lock 5.40 (storyboard 6.15).
//   lock 0.45 orbit: 6 slashes 0.20 s apart (0.45 .. 1.45) | 1.65 leap (slow-mo 0.4) | 1.95 constellation |
//   2.65 starfall: 12 lances 0.08 s apart (2.65 .. 3.53) | 3.65 land + shatter (finish, slow-mo 0.2) | 4.15 frostWave |
//   4.65 blendBack | 5.40 settle (= cinematicEnd)
//   Damage 60 (rune) + 6 x 25 + 12 x 10 + 200 = 530 (lock damage x max(0.7, combo scale at the trigger)).

/** Iska's fighter definition (author format, validated by validateFighterDef). */
export const def = {
  id: 'iska',
  name: '이스카 · ISKA',
  title: '서릿별 무녀 · Froststar Oracle',

  // Slender, light body: the fastest feet of the roster, a little less HP, knocked a little further (weight < 1).
  stats: {
    hp: 950,
    fpMax: 100,
    ultMax: 100,
    guardMax: 100,
    walkSpeed: 3.1,
    backSpeed: 2.4,
    weight: 0.9,
    pushWidth: 0.37,
    hurtWidth: 0.38,
    height: 1.8,
  },

  movement: {
    dash: { duration: 0.24, distance: 2.9, cancelFrom: 0.1 },
    backstep: { duration: 0.3, distance: 2.0, invuln: [0, 0.14] },
    dodge: { duration: 0.38, invuln: [0.02, 0.28], cooldown: 0.6, cancelFrom: 0.26 },
    roll: { duration: 0.38, distance: 2.7 },
  },

  commands: {
    light: 'rime_flick',
    heavy: 'glacier_pirouette',
    'f+heavy': 'frostline_step',
    'd+heavy': 'rising_crescent',
    skill1: 'starshard_volley',
    skill2: 'crystal_procession',
    skill3: 'moonlit_afterimage',
    ult: 'frozen_star',
  },

  // A mobile zoner: holds a mid range, shards and spikes from afar, dashes in for long strings.
  ai: { aggression: 0.55, zoning: 0.65, preferredRange: 2.2 },

  meta: { element: 'frost', weapon: 'twin crescent blades' },

  moves: {
    // -----------------------------------------------------------------------------------------------------------------
    // LIGHT CHAIN
    rime_flick: {
      name: '서리 긋기 · Rime Flick',
      duration: 0.3,
      hits: [{
        t: [0.09, 0.12], box: { f: [0.25, 1.6], u: [0.85, 1.65] }, label: 'flick',
        damage: 24, level: 'light', hitstun: 0.3, blockstun: 0.18, knockback: { x: 1.8, y: 0 }, hitstop: 0.05, guardDamage: 6,
      }],
      cancels: [
        { t: [0.11, 0.28], on: 'light', into: 'twin_moons' },
        { t: [0.1, 0.27], into: ['glacier_pirouette', 'rising_crescent', 'frostline_step', '@skill', '@ult'], onHit: true },
      ],
      markers: [
        { t: 0, name: 'windup' },
        { t: 0.05, name: 'trailOn', data: { blades: 'R', style: 'light' } },
        { t: 0.07, name: 'swing' },
        { t: 0.14, name: 'trailOff' },
        { t: 0.18, name: 'recover' },
      ],
      ai: { range: [0, 1.6], role: 'poke', weight: 1.3 },
      meta: { slot: 'light1' },
    },

    twin_moons: {
      name: '쌍월 · Twin Moons',
      duration: 0.36,
      motion: [{ t: [0, 0.1], v: 2.4 }],
      hits: [
        {
          t: [0.1, 0.12], box: { f: [0.25, 1.55], u: [0.75, 1.6] }, label: 'left',
          damage: 16, level: 'light', hitstun: 0.32, blockstun: 0.16, knockback: { x: 0.8, y: 0 }, hitstop: 0.05, scaleStep: 0.05,
        },
        {
          t: [0.17, 0.19], box: { f: [0.25, 1.6], u: [0.8, 1.7] }, label: 'right',
          damage: 20, level: 'light', hitstun: 0.32, blockstun: 0.18, knockback: { x: 2.0, y: 0 }, hitstop: 0.055,
        },
      ],
      cancels: [
        { t: [0.18, 0.34], on: 'light', into: 'star_fan' },
        { t: [0.18, 0.32], into: ['glacier_pirouette', 'rising_crescent', '@skill', '@ult'], onHit: true },
      ],
      markers: [
        { t: 0, name: 'windup' },
        { t: 0.05, name: 'trailOn', data: { blades: 'both', style: 'light' } },
        { t: 0.07, name: 'swing' },
        { t: 0.1, name: 'slashL' },
        { t: 0.17, name: 'slashR' },
        { t: 0.22, name: 'trailOff' },
        { t: 0.26, name: 'recover' },
      ],
      ai: { role: 'combo', comboOnly: true },
      meta: { slot: 'light2' },
    },

    star_fan: {
      name: '별부채 · Star Fan',
      duration: 0.56,
      motion: [{ t: [0.04, 0.16], v: 2.5 }],
      hits: [
        {
          t: [0.16, 0.19], box: { f: [-0.6, 1.6], u: [0.5, 1.7] }, label: 'spin',
          damage: 18, level: 'light', hitstun: 0.35, blockstun: 0.18, knockback: { x: 0.8, y: 0 }, hitstop: 0.05, scaleStep: 0.05,
        },
        {
          t: [0.25, 0.29], box: { f: [-0.6, 1.9], u: [0.3, 1.8] }, label: 'shards',
          damage: 32, level: 'heavy', hitstun: 0.5, blockstun: 0.22, knockback: { x: 5.2, y: 0 }, hitstop: 0.1, guardDamage: 12,
        },
      ],
      cancels: [
        { t: [0.27, 0.44], into: ['@skill', '@ult'], onHit: true },
        { t: [0.27, 0.4], into: ['starshard_volley'], onContact: true },
      ],
      markers: [
        { t: 0, name: 'windup' },
        { t: 0.08, name: 'trailOn', data: { blades: 'both', style: 'spin' } },
        { t: 0.12, name: 'swing' },
        { t: 0.16, name: 'spin' },
        { t: 0.25, name: 'shards' },
        { t: 0.32, name: 'trailOff' },
        { t: 0.38, name: 'recover' },
      ],
      ai: { role: 'combo', comboOnly: true },
      meta: { slot: 'light3' },
    },

    // -----------------------------------------------------------------------------------------------------------------
    // HEAVIES
    glacier_pirouette: {
      name: '빙결 회전 · Glacier Pirouette',
      duration: 0.78,                         // -9 on block: the three-hit spin is a commitment, not free pressure
      motion: [{ t: [0.12, 0.42], v: 1.8 }],  // the pirouette drifts 0.54 m forward: strings stay in range
      hits: [
        {
          // two revolutions, both blades out: catches both sides
          t: [0.22, 0.31], box: { f: [-1.0, 1.9], u: [0.3, 1.7] }, label: 'spin', multi: { interval: 0.08, max: 2 },
          damage: 24, level: 'light', hitstun: 0.4, blockstun: 0.2, knockback: { x: 0.6, y: 0 }, hitstop: 0.06, scaleStep: 0.05,
        },
        {
          // the third revolution throws the frost ring
          t: [0.38, 0.42], box: { f: [-1.1, 2.1], u: [0, 1.8] }, label: 'frostRing',
          damage: 34, level: 'heavy', hitstun: 0.5, blockstun: 0.24, knockback: { x: 3.2, y: 0 }, hitstop: 0.11, guardDamage: 14,
        },
      ],
      // skills / ult only: the spin is also a juggle extender, and a second Rising Crescent off an airborne victim whiffs
      cancels: [{ t: [0.4, 0.56], into: ['@skill', '@ult'], onHit: true }],
      markers: [
        { t: 0, name: 'windup' },
        { t: 0.14, name: 'trailOn', data: { blades: 'both', style: 'spin' } },
        { t: 0.18, name: 'swing' },
        { t: 0.22, name: 'spin1' },
        { t: 0.3, name: 'spin2' },
        { t: 0.38, name: 'spin3' },
        { t: 0.38, name: 'frostRing' },
        { t: 0.46, name: 'trailOff' },
        { t: 0.52, name: 'recover' },
      ],
      ai: { range: [0, 2.0], role: 'pressure', weight: 0.9 },
      meta: { slot: 'heavy' },
    },

    frostline_step: {
      name: '얼음길 · Frostline Step',
      duration: 0.64,
      // slides 3.5 m on a line of ice and passes through the opponent. The blades only cut what is still ahead of her,
      // so both slashes land from about 1.8 to 4.2 m; up close it is a slide-through escape that whiffs (no
      // point-blank unblockable cross-up). The slide is slow until the first cut, then fast.
      motion: { keys: [[0, 0], [0.1, 0.2], [0.18, 0.8], [0.32, 3.1], [0.4, 3.5]] },
      passThrough: [[0.12, 0.38]],
      hits: [{
        t: [0.18, 0.34], box: { f: [0.25, 1.3], u: [0.4, 1.7] }, multi: { interval: 0.05, max: 2 }, label: 'slash',
        damage: 22, level: 'heavy', hitstun: 0.55, blockstun: 0.2, knockback: { x: 0.5, y: 0 }, hitstop: 0.1, scaleStep: 0.05,
      }],
      // no ult: the slide is her main juggle extender (after Rising Crescent), and the ground rune misses an airborne victim
      cancels: [{ t: [0.4, 0.58], into: ['rime_flick', 'glacier_pirouette', 'rising_crescent', '@skill'], onHit: true }],
      markers: [
        { t: 0, name: 'windup' },
        { t: 0.06, name: 'iceLine' },
        { t: 0.1, name: 'trailOn', data: { blades: 'both', style: 'light' } },
        { t: 0.1, name: 'slide' },
        { t: 0.16, name: 'swing' },
        { t: 0.36, name: 'trailOff' },
        { t: 0.4, name: 'stop' },
        { t: 0.44, name: 'recover' },
      ],
      ai: { range: [1.8, 4.2], role: 'approach', weight: 0.8 },
      meta: { slot: 'fheavy' },
    },

    rising_crescent: {
      name: '초승 올려치기 · Rising Crescent',
      duration: 0.62,
      // a step in, then the backflip: up to 1 m high, landing 0.2 m behind the start
      motion: { keys: [[0, 0, 0], [0.1, 0.3, 0.05], [0.2, 0.2, 0.55], [0.32, -0.05, 1.0], [0.46, -0.2, 0.45], [0.56, -0.2, 0]] },
      hits: [{
        t: [0.16, 0.22], box: { f: [0.1, 1.5], u: [-0.3, 2.0] }, label: 'crescent',
        damage: 40, level: 'launch', knockback: { x: 1.6, y: 9.5 }, hitstop: 0.11, blockstun: 0.2, guardDamage: 12,
      }],
      cancels: [{ t: [0.22, 0.44], into: ['starshard_volley', 'crystal_procession', 'frostline_step'], onHit: true }],
      markers: [
        { t: 0, name: 'windup' },
        { t: 0.1, name: 'flip' },
        { t: 0.12, name: 'trailOn', data: { blades: 'both', style: 'rising' } },
        { t: 0.14, name: 'swing' },
        { t: 0.3, name: 'trailOff' },
        { t: 0.5, name: 'land' },
        { t: 0.52, name: 'recover' },
      ],
      ai: { range: [0, 1.75], role: 'launcher', weight: 0.7 },
      meta: { slot: 'dheavy' },
    },

    // -----------------------------------------------------------------------------------------------------------------
    // SKILLS
    starshard_volley: {
      name: '서릿별 투창 · Starshard Volley',
      duration: 0.62,
      fpCost: 20,
      cooldown: 3.5,
      projectiles: [
        {
          t: 0.18, kind: 'frost.shard', offset: { f: 0.6, u: 1.38 }, box: { f: [-0.32, 0.32], u: [-0.24, 0.24] },
          velocity: { x: 14, y: 0 }, lifetime: 0.75, data: { index: 1 },
          hit: { damage: 20, level: 'light', hitstun: 0.36, blockstun: 0.2, knockback: { x: 1.0, y: 0 }, hitstop: 0.05, juggle: 0.5 },
        },
        {
          t: 0.24, kind: 'frost.shard', offset: { f: 0.6, u: 1.15 }, box: { f: [-0.32, 0.32], u: [-0.24, 0.24] },
          velocity: { x: 14, y: 0 }, lifetime: 0.75, data: { index: 2 },
          hit: { damage: 20, level: 'light', hitstun: 0.36, blockstun: 0.2, knockback: { x: 1.0, y: 0 }, hitstop: 0.05, juggle: 0.5 },
        },
        {
          // the third shard freezes the victim solid (crumple)
          t: 0.3, kind: 'frost.shard', offset: { f: 0.6, u: 0.95 }, box: { f: [-0.32, 0.32], u: [-0.24, 0.24] },
          velocity: { x: 14, y: 0 }, lifetime: 0.75, data: { index: 3, freeze: true },
          hit: { damage: 34, level: 'crumple', hitstun: 0.9, blockstun: 0.24, knockback: { x: 1.2, y: 0 }, hitstop: 0.15, juggle: 1 },
        },
      ],
      cancels: [{ t: [0.3, 0.56], into: ['crystal_procession', '@ult'], onHit: true }],
      markers: [
        { t: 0, name: 'windup' },
        { t: 0.04, name: 'crystallise' },
        { t: 0.1, name: 'trailOn', data: { blades: 'both', style: 'light' } },
        { t: 0.18, name: 'release' },
        { t: 0.18, name: 'shard1' },
        { t: 0.24, name: 'shard2' },
        { t: 0.3, name: 'shard3' },
        { t: 0.36, name: 'trailOff' },
        { t: 0.42, name: 'recover' },
      ],
      ai: { range: [2.2, 9], role: 'zoning', weight: 1 },
      meta: { slot: 'skill1' },
    },

    crystal_procession: {
      name: '빙정 행렬 · Crystal Procession',
      duration: 0.78,
      fpCost: 30,
      cooldown: 6,
      // five spikes 1.4 m apart race 7 m forward (23 m/s), each larger than the last; each erupts once (lifetime 0.1).
      // The 0.5 m/s creep is the line's direction: guard is judged by travel (toward the victim), so a spike erupting
      // just behind a blocking opponent is blocked like the rest instead of counting as a hit from behind.
      projectiles: [
        {
          t: 0.25, kind: 'frost.spike', offset: { f: 1.3, u: 0 }, box: { f: [-0.55, 0.55], u: [0, 0.9] },
          delay: 0, velocity: { x: 0.5, y: 0 }, lifetime: 0.1, clash: false,
          data: { index: 1, size: 0.5, hold: 0.6 },
          hit: { damage: 18, level: 'launch', knockback: { x: 1.2, y: 8.5 }, hitstop: 0.14, blockstun: 0.24, juggle: 0.5 },
        },
        {
          t: 0.25, kind: 'frost.spike', offset: { f: 2.7, u: 0 }, box: { f: [-0.55, 0.55], u: [0, 1.2] },
          delay: 0.06, velocity: { x: 0.5, y: 0 }, lifetime: 0.1, clash: false,
          data: { index: 2, size: 0.65, hold: 0.6 },
          hit: { damage: 20, level: 'launch', knockback: { x: 1.2, y: 8.5 }, hitstop: 0.14, blockstun: 0.24, juggle: 0.5 },
        },
        {
          t: 0.25, kind: 'frost.spike', offset: { f: 4.1, u: 0 }, box: { f: [-0.55, 0.55], u: [0, 1.5] },
          delay: 0.12, velocity: { x: 0.5, y: 0 }, lifetime: 0.1, clash: false,
          data: { index: 3, size: 0.8, hold: 0.6 },
          hit: { damage: 22, level: 'launch', knockback: { x: 1.2, y: 8.5 }, hitstop: 0.14, blockstun: 0.24, juggle: 0.5 },
        },
        {
          t: 0.25, kind: 'frost.spike', offset: { f: 5.5, u: 0 }, box: { f: [-0.55, 0.55], u: [0, 1.9] },
          delay: 0.18, velocity: { x: 0.5, y: 0 }, lifetime: 0.1, clash: false,
          data: { index: 4, size: 1, hold: 0.6 },
          hit: { damage: 24, level: 'launch', knockback: { x: 1.2, y: 8.5 }, hitstop: 0.14, blockstun: 0.24, juggle: 0.5 },
        },
        {
          // the last one is huge
          t: 0.25, kind: 'frost.spike', offset: { f: 6.9, u: 0 }, box: { f: [-0.75, 0.75], u: [0, 2.6] },
          delay: 0.24, velocity: { x: 0.5, y: 0 }, lifetime: 0.12, clash: false,
          data: { index: 5, size: 1.6, hold: 0.6, last: true },
          hit: { damage: 40, level: 'launch', knockback: { x: 1.5, y: 10 }, hitstop: 0.17, blockstun: 0.26, juggle: 0.5 },
        },
      ],
      cancels: [{ t: [0.3, 0.7], into: ['starshard_volley'], onHit: true }],
      markers: [
        { t: 0, name: 'windup' },
        { t: 0.05, name: 'trailOn', data: { blades: 'both', style: 'heavy' } },
        { t: 0.12, name: 'stab' },
        { t: 0.15, name: 'trailOff' },
        { t: 0.16, name: 'frost' },
        { t: 0.25, name: 'release' },
        { t: 0.25, name: 'crack' },
        { t: 0.25, name: 'spike1' },
        { t: 0.31, name: 'spike2' },
        { t: 0.37, name: 'spike3' },
        { t: 0.43, name: 'spike4' },
        { t: 0.49, name: 'spike5', data: { slowmo: 0.7 } },
        { t: 0.56, name: 'recover' },
      ],
      ai: { range: [2.0, 7.4], role: 'zoning', weight: 0.9 },
      meta: { slot: 'skill2' },
    },

    moonlit_afterimage: {
      name: '월광 잔상 · Moonlit Afterimage',
      duration: 0.7,
      fpCost: 25,
      cooldown: 7,
      requires: { maxDistance: 5 },
      // intangible from the first frame to the cut: attacks pass through the blink (the 'counter' of the kit)
      invuln: [{ t: [0, 0.3], vs: 'all' }],
      passThrough: [[0.12, 0.32]],
      motion: [{ t: [0.02, 0.12], v: -8 }],                            // blinks 0.8 m back
      teleport: [{ t: 0.24, to: 'behind', distance: 0.95, face: true }], // reappears behind, already facing them
      hits: [{
        t: [0.3, 0.35], box: { f: [0.1, 1.5], u: [0.4, 1.8] }, label: 'strike',
        damage: 40, level: 'heavy', hitstun: 0.55, blockstun: 0.22, knockback: { x: 2.5, y: 0 }, hitstop: 0.15, guardDamage: 14,
      }],
      // the frozen statue left on the start spot bursts forward with the cut (the second hit). It arms one frame after
      // the cut's first active frame (a projectile ages from the substep it spawns in), so the two sides resolve in
      // order: a guard-holder turns to the reappeared Iska, blocks the cut and takes the statue in the back - one hit
      // through guard, never both, and only the ultimate can follow it (the sandwich is not a combo starter)
      projectiles: [{
        t: 0, kind: 'frost.statue', offset: { f: 0, u: 0.1 }, box: { f: [-0.45, 0.45], u: [0, 1.6] },
        velocity: { x: 16, y: 0 }, delay: 0.32, lifetime: 0.24, clash: false, data: { statue: true },
        hit: { damage: 26, level: 'heavy', hitstun: 0.5, blockstun: 0.2, knockback: { x: 1.5, y: 0 }, hitstop: 0.1 },
      }],
      cancels: [{ t: [0.36, 0.56], into: ['@ult'], onHit: true }],
      markers: [
        { t: 0, name: 'windup' },
        { t: 0.02, name: 'blink' },
        { t: 0.02, name: 'statue' },
        { t: 0.12, name: 'vanish' },
        { t: 0.24, name: 'reappear' },
        { t: 0.25, name: 'trailOn', data: { blades: 'both', style: 'heavy' } },
        { t: 0.27, name: 'swing' },
        { t: 0.3, name: 'strike' },
        { t: 0.3, name: 'shatter' },
        { t: 0.4, name: 'trailOff' },
        { t: 0.46, name: 'recover' },
      ],
      ai: { range: [0.6, 4.8], role: 'reversal', weight: 3 },
      meta: { slot: 'skill3' },
    },

    // -----------------------------------------------------------------------------------------------------------------
    // ULTIMATE
    frozen_star: {
      name: '떨어지는 서릿별 · Fall of the Frozen Star',
      ultCost: 100,
      superFreeze: 0.6,                       // world goes silver-blue: env.setMood({ darken: 0.8, tint: 0x8fc8ff })
      duration: 1.45,
      invuln: [{ t: [0.6, 1.0], vs: 'all' }], // casting the rune: the freeze covers 0..0.6 already
      hits: [{
        // the star rune drawn under the opponent snaps shut: an unblockable ground rune, avoided by a dodge or by
        // being airborne; reaches 6 m (presentation clamps the circle to marker 'rune' data.maxRange)
        t: [0.75, 0.95], box: { f: [0.3, 6.0], u: [0, 0.45] }, label: 'rune',
        damage: 60, level: 'heavy', unblockable: true, air: false, hitstop: 0.18,
      }],
      cinematic: {
        hit: 0,
        duration: 5.4,
        distance: 1.7,
        recovery: 0.5,
        ticks: [
          // 1.20 orbit (ground skim, 90°): Iska dashes around the crystal slashing 6 times (frost.slash, afterimages)
          { t: 0.45, damage: 25, hitstop: 0.05, marker: 'slash1', data: { storyboard: 1.2, vfx: 'frost.slash' } },
          { t: 0.65, damage: 25, hitstop: 0.05, marker: 'slash2', data: { storyboard: 1.4, vfx: 'frost.slash' } },
          { t: 0.85, damage: 25, hitstop: 0.05, marker: 'slash3', data: { storyboard: 1.6, vfx: 'frost.slash' } },
          { t: 1.05, damage: 25, hitstop: 0.05, marker: 'slash4', data: { storyboard: 1.8, vfx: 'frost.slash' } },
          { t: 1.25, damage: 25, hitstop: 0.05, marker: 'slash5', data: { storyboard: 2.0, vfx: 'frost.slash' } },
          { t: 1.45, damage: 25, hitstop: 0.05, marker: 'slash6', data: { storyboard: 2.2, vfx: 'frost.slash' } },
          // 3.40 starfall (over the shoulder from the air): 12 star lances rain down, each a ring + shard burst
          { t: 2.65, damage: 10, hitstop: 0.03, marker: 'lance1', data: { storyboard: 3.4, vfx: 'frost.starfall' } },
          { t: 2.73, damage: 10, hitstop: 0.03, marker: 'lance2', data: { storyboard: 3.48, vfx: 'frost.starfall' } },
          { t: 2.81, damage: 10, hitstop: 0.03, marker: 'lance3', data: { storyboard: 3.56, vfx: 'frost.starfall' } },
          { t: 2.89, damage: 10, hitstop: 0.03, marker: 'lance4', data: { storyboard: 3.64, vfx: 'frost.starfall' } },
          { t: 2.97, damage: 10, hitstop: 0.03, marker: 'lance5', data: { storyboard: 3.72, vfx: 'frost.starfall' } },
          { t: 3.05, damage: 10, hitstop: 0.03, marker: 'lance6', data: { storyboard: 3.8, vfx: 'frost.starfall' } },
          { t: 3.13, damage: 10, hitstop: 0.03, marker: 'lance7', data: { storyboard: 3.88, vfx: 'frost.starfall' } },
          { t: 3.21, damage: 10, hitstop: 0.03, marker: 'lance8', data: { storyboard: 3.96, vfx: 'frost.starfall' } },
          { t: 3.29, damage: 10, hitstop: 0.03, marker: 'lance9', data: { storyboard: 4.04, vfx: 'frost.starfall' } },
          { t: 3.37, damage: 10, hitstop: 0.03, marker: 'lance10', data: { storyboard: 4.12, vfx: 'frost.starfall' } },
          { t: 3.45, damage: 10, hitstop: 0.03, marker: 'lance11', data: { storyboard: 4.2, vfx: 'frost.starfall' } },
          { t: 3.53, damage: 10, hitstop: 0.03, marker: 'lance12', data: { storyboard: 4.28, vfx: 'frost.starfall' } },
        ],
        // 4.40 impact punch-in, slow-mo 0.2: Iska lands and crosses her blades, crystal and victim shatter (inverted
        // impact frame, white flash, ice_shatter)
        finish: {
          t: 3.65, damage: 200, level: 'knockdown', knockback: { x: 3.0, y: 5.5 }, hitstop: 0.22, marker: 'shatter',
          data: { storyboard: 4.4, vfx: 'frost.shatter', impactFrame: 'invert', audio: 'ice_shatter' },
        },
        markers: [
          // 0.60 row, continued: the circle has snapped shut (the trigger, storyboard 0.75); the ice crystal encases the
          // victim (lock 0 .. 0.45). First lock frame: the engine emits no lock marker at exactly t = 0.
          { t: 0.01, name: 'crystal', data: { storyboard: 0.76, vfx: 'frost.nova', audio: 'ice_form' } },
          { t: 0.45, name: 'orbit', data: { storyboard: 1.2, cam: { shot: 'groundSkimOrbit', degrees: 90 } } },
          { t: 1.65, name: 'leap', data: { storyboard: 2.4, slowmo: 0.4, cam: { shot: 'wideLowEclipse' } } },
          { t: 1.95, name: 'constellation', data: { storyboard: 2.7 } },
          { t: 2.65, name: 'starfall', data: { storyboard: 3.4, cam: { shot: 'overShoulderDown' } } },
          { t: 3.65, name: 'land', data: { storyboard: 4.4, slowmo: 0.2 } },
          { t: 4.15, name: 'frostWave', data: { storyboard: 4.9, vfx: 'frost.blizzard', letterbox: false } },
          { t: 4.65, name: 'blendBack', data: { storyboard: 5.4, cam: { shot: 'blendBack', dur: 0.75 }, linger: { glitter: 2 } } },
          { t: 5.4, name: 'settle', data: { storyboard: 6.15 } },
        ],
      },
      markers: [
        { t: 0, name: 'windup', data: { mood: { darken: 0.8, tint: 0x8fc8ff } } },
        { t: 0.05, name: 'aura' },
        { t: 0.15, name: 'trailOn', data: { blades: 'both', style: 'spin' } },
        { t: 0.35, name: 'rune', data: { maxRange: 6.0 } },
        { t: 0.6, name: 'release' },
        { t: 0.75, name: 'snap' },
        { t: 0.95, name: 'trailOff' },
        { t: 1.05, name: 'recover' },
      ],
      ai: { range: [0, 6.0], role: 'finisher', weight: 1 },
      // storyboard t = 0.75 + lock t (the rune's first active frame is the trigger; see ULTIMATE TIMING above)
      meta: {
        slot: 'ult',
        storyboardAtTrigger: 0.75,
        mood: { darken: 0.8, tint: 0x8fc8ff },
        impact: { shot: 'topDownRune', vfx: 'frost.nova', audio: 'ice_form', encase: true },
      },
    },
  },
};

export default def;
