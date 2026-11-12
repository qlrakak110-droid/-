// KAEL 카엘 — 잿불의 집행자 · Cinder Warden. Rules definition (pure data for src/game/logic; see its README.md).
// Two-handed greatsword (~2.1 m of reach): the slowest feet and startups of the roster, enormous arcs, the highest damage
// per hit, big pushback, hyper-armour on the heavies and a counter stance. Weak to fast pressure: unsafe normals, a
// short dash and a wide body. Creative brief: src/fighters/MOVES.md.
// Frame data: node src/game/logic/test/framedata.mjs src/fighters/kael/moves.js
//
// SLOTS (move id <- command; meta.slot = the roster slot name used by the UI move list)
//   light1  light1         light            재가르기 Ash Cleave           0.14 startup, diagonal down-right cut
//   light2  light2         (light route)    역날베기 Back Edge            0.13, rising backhand that continues the arc
//   light3  light3         (light route)    잿불내려찍기 Cinder Drop       0.24, overhead into the floor, knockdown
//   heavy   sweep          heavy            용광로 휘두르기 Furnace Sweep   0.32, armour 0.12-0.32 (1 hit), 300° spin
//   fheavy  lunge          f+heavy          돌진 찌르기 Molten Lunge       0.26, travels 3.2 m, shoulder armour, crumple
//   dheavy  vent           d+heavy          분화 올려베기 Vent Launcher     0.22, upward cut, fire geyser, launch
//   skill1  crescent       skill1           잿불 초승달 Ember Crescent      FP 25, CD 4 s: 2.2 m crescent wave, 11 m/s
//   skill2  eruption       skill2           균열 분출 Fault Eruption        FP 35, CD 7 s: 6 m crack, 4 magma columns
//   skill3  bulwark        skill3           화염 갑주 Pyre Bulwark          FP 30, CD 9 s: counter stance 0.04-0.6
//           bulwark_burst  (counter)        화염 갑주 · 폭발                the counter: 360° explosion, knockdown
//   ult     pyre           ult              일식의 장작 Pyre of the Black Sun  ULT 100: leap-slash into a 5.2 s lock
//
// COMBO GRAMMAR (cancel routes; every target is listed by id, so nothing unsafe or useless is ever offered)
//   light1 -> light2 -> light3                       chain (also on whiff / block: a real string; light3 knocks down)
//   light1 / light2 on hit -> d+heavy, f+heavy, heavy, skill1          (d+heavy, f+heavy, skill1: true combos)
//                                                    The ultimate is the payoff of a big hit, never of a jab: it is
//                                                    offered after heavy, f+heavy, d+heavy and the skills (balance
//                                                    pass, see src/fighters/BALANCE.md)
//   light3 on hit or block -> skill1 / skill2         (the wave covers the -12 recovery on block)
//   heavy on hit -> skill1, skill2, ult               (Furnace Sweep -> Fault Eruption launches)
//   f+heavy on hit (crumple) -> d+heavy, skill1, skill2, ult   (no heavy: the lunge also juggles, the sweep would whiff)
//   d+heavy on hit (launch) -> skill1, skill2, ult    (the wave and the columns reach an airborne victim)
//   skill1 on hit -> ult ;  skill2 on hit -> ult      (the leap-slash catches the juggled victim)
//   e.g.  light1 > light2 > light3                                  3 hits, knockdown
//         light1 > f+heavy > d+heavy > skill2                       launcher route, ~6 hits
//         heavy (armour through a poke) > skill2 > ult              the meter dump into the lock
//
// TIMELINE MARKERS (`marker` events: presentation hangs clips, trails, VFX, camera and audio on these names; the rules
// never read them). Beat notation of MOVES.md: WIND-UP -> RELEASE -> IMPACT -> AFTERMATH -> SETTLE.
//   every move    windup    WIND-UP starts: anticipation pose / clip start (t = 0)
//                 trailOn   the blade trail starts.  data: { style: 'light' | 'rising' | 'overhead' | 'huge' |
//                           'thrust' | 'drag' | 'glow' }  ('glow' = no ribbon: the blade's ember glow, stances)
//                 swing     RELEASE of a strike: the smear starts (a few frames before the first active frame)
//                 release   RELEASE of a skill / the ultimate: the thing leaves (wave, blade into the floor, shell, leap)
//                 (impact)  IMPACT needs no marker: the engine's `hit` event carries contact point, level and hit-stop
//                 trailOff  the trail stops: AFTERMATH / follow-through
//                 recover   SETTLE: back toward the guard pose (sword on the shoulder)
//   light2              (continues the light1 arc; data.continues)
//   light3              crack                             blade meets the floor: small crack + ember spray (hit or not)
//   sweep               armour sparks                     armour cracks flare (0.12) / wall of sparks along the arc
//   lunge               charge                            shoulder-first launch, magma streak + afterimage behind
//   vent                split geyser                      blade splits the floor / fire geyser erupts (hit or not)
//   crescent            drag detach                       blade dragged along the floor (sparks, molten groove) /
//                                                         the wave detaches (`ember.wave`; camera kick fov -3)
//   eruption            rune aura crack column1..column4  rune circle under the feet / ember aura flares / blade in
//                                                         the floor, cracks race 6 m (camera: ground skim 0.5 s,
//                                                         slow-mo 0.6) / each magma column erupts (debris + ring).
//                                                         The columns' own VFX may also follow projectileSpawn /
//                                                         projectileActive: kind 'ember.column', data.index 1..4
//   bulwark             shell shed                        ember shell forms around Kael / whiff: sheds it harmlessly
//   bulwark_burst       counter explode                   the counter catches (crash-zoom 0.25 s) / `ember.explosion`
//                                                         + 360° fire ring (impact frame, shake 0.5)
//   pyre (move clock)   superFreeze (engine, t = 0) windup gather ignite trailOn leap release slam trailOff recover
//   pyre (lock clock, `cinematic: true` markers; ticks emit their own `marker`)
//                       orbit cut1 cut2 cut3 hurl leapAfter spin meteor shockwave rise settle
//
// ULTIMATE TIMING. Storyboard rows 0.00 and 0.60 are the opener on the MOVE clock: super-freeze 0 .. 0.6 s (sword raised
// to the eclipse; world darkens, letterbox in), then the leap-slash (4 m, active 0.85 .. 1.0). The 1.00 row ("blade
// connects") is the trigger itself: the lock clock starts there (t = 0 at the contact; the impact punch-in, impact
// frame and 0.2 s hit-stop ride on `cinematicStart` and the trigger's `hit` event, parameters in pyre.meta.impact: the
// engine never emits lock markers or ticks at t = 0, so none is authored there). Every later row keeps its spacing
// from the impact:  storyboard t = 1.00 + lock t.  The lock lasts 5.2 s: the 5.20 row (blend back while Kael rises from
// the crater) starts at lock 4.20 and runs to cinematicEnd at lock 5.20, where Kael stands with the sword on his
// shoulder and the fight resumes. Every lock marker / tick carries its storyboard time in data.storyboard.
//   lock 0.25 orbit + cut1 | 0.40 cut2 | 0.55 cut3 | 1.30 hurl | 1.80 leapAfter | 2.40 spin | 2.90 meteor (finish)
//   3.30 shockwave | 4.20 rise | 5.20 settle (= cinematicEnd)
//   Damage 80 (leap-slash) + 3 x 40 + 60 + 260 = 520 (lock damage x max(0.7, combo scale at the trigger)).

/** Kael's fighter definition (author format, validated by validateFighterDef). */
export const def = {
  id: 'kael',
  name: '카엘 · KAEL',
  title: '잿불의 집행자 · Cinder Warden',

  // Big armoured body: the most HP of the roster, pushed around a little less (weight > 1), but a wide hurtbox and
  // the slowest feet. Short dash, short backstep.
  stats: {
    hp: 1230,
    fpMax: 100,
    ultMax: 100,
    guardMax: 100,
    walkSpeed: 2.1,
    backSpeed: 1.55,
    weight: 1.15,
    pushWidth: 0.44,
    hurtWidth: 0.52,   // the widest target of the roster (pauldrons, the blade across the body): weak to fast pressure
    height: 1.95,
  },

  movement: {
    dash: { duration: 0.34, distance: 1.9, cancelFrom: 0.18 },
    backstep: { duration: 0.38, distance: 1.45, invuln: [0, 0.12] },
    dodge: { duration: 0.46, invuln: [0.03, 0.3], cooldown: 0.8, cancelFrom: 0.34 },
    roll: { duration: 0.46, distance: 2.4 },
  },

  commands: {
    light: 'light1',
    heavy: 'sweep',
    'f+heavy': 'lunge',
    'd+heavy': 'vent',
    skill1: 'crescent',
    skill2: 'eruption',
    skill3: 'bulwark',
    ult: 'pyre',
  },

  // Patient bruiser: holds the tip of his sword (~2.2 m, outside most jabs), waits for a whiff, then one big hit.
  ai: { aggression: 0.42, zoning: 0.4, preferredRange: 2.2 },

  meta: { element: 'ember', weapon: 'greatsword' },

  moves: {
    // -----------------------------------------------------------------------------------------------------------------
    // LIGHT CHAIN
    light1: {
      name: '재가르기 · Ash Cleave',
      duration: 0.42,
      hits: [{
        // diagonal down-right cut: from above the head down through the hip, out to the blade's tip
        t: [0.14, 0.19], box: { f: [0.35, 1.95], u: [0.45, 1.95] },
        damage: 51, level: 'light', hitstun: 0.34, blockstun: 0.2, knockback: { x: 2.8, y: 0 }, hitstop: 0.065, guardDamage: 13,
      }],
      cancels: [
        { t: [0.17, 0.4], on: 'light', into: 'light2' },
        { t: [0.16, 0.36], into: ['vent', 'lunge', 'sweep', 'crescent'], onHit: true },
      ],
      markers: [
        { t: 0, name: 'windup' },
        { t: 0.08, name: 'trailOn', data: { style: 'light' } },
        { t: 0.11, name: 'swing' },
        { t: 0.23, name: 'trailOff' },
        { t: 0.27, name: 'recover' },
      ],
      ai: { range: [0, 2.25], role: 'poke', weight: 1.2 },
      meta: { slot: 'light1' },
    },

    light2: {
      name: '역날베기 · Back Edge',
      duration: 0.46,
      motion: [{ t: [0, 0.1], v: 2.5 }],                        // a quarter-metre step into the backhand
      hits: [{
        // rising backhand: from the floor up past the head, the trail continues light1's arc
        t: [0.13, 0.18], box: { f: [0.3, 1.9], u: [0.15, 2.15] },
        damage: 55, level: 'light', hitstun: 0.37, blockstun: 0.21, knockback: { x: 3.0, y: 0 }, hitstop: 0.065, guardDamage: 14,
      }],
      cancels: [
        { t: [0.16, 0.42], on: 'light', into: 'light3' },
        { t: [0.15, 0.38], into: ['vent', 'lunge', 'sweep', 'crescent'], onHit: true },
      ],
      markers: [
        { t: 0, name: 'windup', data: { continues: 'light1' } },
        { t: 0.07, name: 'trailOn', data: { style: 'rising' } },
        { t: 0.1, name: 'swing' },
        { t: 0.22, name: 'trailOff' },
        { t: 0.28, name: 'recover' },
      ],
      ai: { role: 'combo', comboOnly: true },
      meta: { slot: 'light2' },
    },

    light3: {
      name: '잿불내려찍기 · Cinder Drop',
      duration: 0.7,
      motion: [{ t: [0.04, 0.2], v: 2.2 }],                     // steps 0.35 m into the overhead
      hits: [{
        // overhead into the floor: tall box down to the ground at the blade's full length
        t: [0.24, 0.29], box: { f: [0.3, 2.0], u: [0, 2.3] },
        damage: 89, level: 'knockdown', knockback: { x: 5.5, y: 3.6 }, hitstop: 0.12, blockstun: 0.26, guardDamage: 24,
      }],
      // hit or block: the wave or the columns keep the -12 f recovery covered
      cancels: [{ t: [0.27, 0.42], into: ['crescent', 'eruption'], onContact: true }],
      markers: [
        { t: 0, name: 'windup' },
        { t: 0.13, name: 'trailOn', data: { style: 'overhead' } },
        { t: 0.17, name: 'swing' },
        { t: 0.24, name: 'crack', data: { decal: 'crack', embers: true, shake: 0.35 } },
        { t: 0.33, name: 'trailOff' },
        { t: 0.44, name: 'recover' },
      ],
      ai: { role: 'combo', comboOnly: true },
      meta: { slot: 'light3' },
    },

    // -----------------------------------------------------------------------------------------------------------------
    // HEAVIES
    sweep: {
      name: '용광로 휘두르기 · Furnace Sweep',
      duration: 0.86,
      // hyper-armour through the wind-up: takes the damage of one hit without flinching. It eats a poke, but a fast
      // multi-hit string breaks it: Kael is weak to fast pressure (balance pass: 2 hits made him beat Iska's strings)
      armour: [{ t: [0.12, 0.32], hits: 1 }],
      hits: [{
        // full horizontal 300° spin: the arc starts behind him (catches cross-ups) and ends at the tip, waist to chest
        t: [0.32, 0.4], box: { f: [-0.6, 2.25], u: [0.3, 1.8] },
        damage: 125, level: 'heavy', hitstun: 0.6, blockstun: 0.3, knockback: { x: 4.6, y: 0 }, hitstop: 0.12, guardDamage: 32,
      }],
      cancels: [{ t: [0.36, 0.56], into: ['crescent', 'eruption', '@ult'], onHit: true }],
      markers: [
        { t: 0, name: 'windup', data: { armour: true } },
        { t: 0.12, name: 'armour' },
        { t: 0.23, name: 'trailOn', data: { style: 'huge' } },
        { t: 0.27, name: 'swing' },
        { t: 0.32, name: 'sparks', data: { vfx: 'wall of sparks', shake: 0.35 } },
        { t: 0.47, name: 'trailOff' },
        { t: 0.58, name: 'recover' },
      ],
      ai: { range: [0.5, 2.55], role: 'pressure', weight: 0.9 },
      meta: { slot: 'heavy' },
    },

    lunge: {
      name: '돌진 찌르기 · Molten Lunge',
      duration: 0.78,
      // 3.2 m: a hard shoulder-first launch that eases into the thrust (stops at the opponent instead of tunnelling)
      motion: { keys: [[0, 0], [0.06, 0], [0.22, 2.4], [0.3, 3.05], [0.36, 3.2]] },
      armour: [{ t: [0.06, 0.24], hits: 1 }],                  // the shoulder charge shrugs off one hit
      hits: [{
        // the thrust at the end of the charge: chest height, the blade's full length
        t: [0.26, 0.34], box: { f: [0.3, 1.9], u: [0.7, 1.7] },
        damage: 102, level: 'crumple', hitstun: 0.95, blockstun: 0.24, knockback: { x: 1.5, y: 0 }, hitstop: 0.12, guardDamage: 26,
      }],
      // (no heavy follow-up: the lunge is also a juggle tool, and the sweep whiffs on an airborne victim)
      cancels: [{ t: [0.3, 0.54], into: ['vent', 'crescent', 'eruption', '@ult'], onHit: true }],
      markers: [
        { t: 0, name: 'windup' },
        { t: 0.06, name: 'charge', data: { vfx: 'magma streak', afterimage: true } },
        { t: 0.18, name: 'trailOn', data: { style: 'thrust' } },
        { t: 0.22, name: 'swing' },
        { t: 0.4, name: 'trailOff' },
        { t: 0.5, name: 'recover' },
      ],
      ai: { range: [2.2, 5.0], role: 'approach', weight: 0.75 },
      meta: { slot: 'fheavy' },
    },

    vent: {
      name: '분화 올려베기 · Vent Launcher',
      duration: 0.72,
      hits: [{
        // upward cut out of the floor: floor to well above the head
        t: [0.22, 0.3], box: { f: [0.25, 1.85], u: [0, 2.6] },
        damage: 85, level: 'launch', knockback: { x: 1.2, y: 9 }, hitstop: 0.11, blockstun: 0.24, guardDamage: 22,
      }],
      cancels: [{ t: [0.28, 0.5], into: ['crescent', 'eruption', '@ult'], onHit: true }],
      markers: [
        { t: 0, name: 'windup' },
        { t: 0.15, name: 'trailOn', data: { style: 'rising' } },
        { t: 0.18, name: 'split', data: { decal: 'crack' } },
        { t: 0.19, name: 'swing' },
        { t: 0.22, name: 'geyser', data: { vfx: 'fire geyser' } },
        { t: 0.34, name: 'trailOff' },
        { t: 0.46, name: 'recover' },
      ],
      ai: { range: [0, 2.15], role: 'launcher', weight: 0.7 },
      meta: { slot: 'dheavy' },
    },

    // -----------------------------------------------------------------------------------------------------------------
    // SKILLS
    crescent: {
      name: '잿불 초승달 · Ember Crescent',
      duration: 0.74,
      fpCost: 25,
      cooldown: 4,
      projectiles: [{
        // a burning crescent wave 2.2 m tall detaches from the rising swing and runs along the floor at 11 m/s
        t: 0.28, kind: 'ember.wave', offset: { f: 1.0, u: 0 }, box: { f: [-0.45, 0.45], u: [0, 2.2] },
        velocity: { x: 11, y: 0 }, lifetime: 0.85, durability: 1,
        data: { height: 2.2, scorch: true, cinders: true, impact: { vfx: 'fire flower', decal: 'slash', shake: 0.3 } },
        hit: { damage: 81, level: 'heavy', hitstun: 0.5, blockstun: 0.26, knockback: { x: 3.6, y: 0 }, hitstop: 0.12, guardDamage: 22 },
      }],
      cancels: [{ t: [0.32, 0.62], into: ['@ult'], onHit: true }],
      markers: [
        { t: 0, name: 'windup', data: { coil: true } },
        { t: 0.04, name: 'drag', data: { vfx: 'sparks + molten groove' } },
        { t: 0.04, name: 'trailOn', data: { style: 'drag' } },
        { t: 0.28, name: 'release', data: { kickFov: -3 } },
        { t: 0.28, name: 'detach', data: { vfx: 'ember.wave' } },
        { t: 0.4, name: 'trailOff' },
        { t: 0.5, name: 'recover' },
      ],
      ai: { range: [2.8, 9.5], role: 'zoning', weight: 1.2 },
      meta: { slot: 'skill1' },
    },

    eruption: {
      name: '균열 분출 · Fault Eruption',
      duration: 1.0,
      fpCost: 35,
      cooldown: 7,
      // the blade is planted at ~1.2 m: Kael leans over it until he wrenches it free (punishable at the hilt)
      hurt: [{ t: [0.4, 0.74], box: { f: [0.2, 1.25], u: [0.3, 1.4] } }],
      // Cracks race 6 m from the planted blade (18.75 m/s); four magma columns erupt along the line 0.08 s apart,
      // 1.5 m apart. Every column launches whatever it touches first and juggles a victim it finds in the air: the
      // launch carries the victim forward along the crack (4 m/s) into the next column. A slow forward drift (0.5 m/s)
      // gives each column a travel direction, so it is blocked from the front even when it erupts behind the victim.
      // Hit-stop 0.15 on the first column (the launcher in every combo), 0.06 on the follow-ups.
      projectiles: [
        {
          t: 0.4, kind: 'ember.column', offset: { f: 1.5, u: 0 }, box: { f: [-0.9, 0.9], u: [0, 2.8] },
          velocity: { x: 0.5, y: 0 }, delay: 0.04, lifetime: 0.16, pierce: true, clash: false, data: { index: 1, debris: true, ring: true },
          hit: { damage: 55, level: 'launch', knockback: { x: 4, y: 8 }, hitstop: 0.15, blockstun: 0.22, guardDamage: 14, juggle: 0.5 },
        },
        {
          t: 0.4, kind: 'ember.column', offset: { f: 3.0, u: 0 }, box: { f: [-0.9, 0.9], u: [0, 2.8] },
          velocity: { x: 0.5, y: 0 }, delay: 0.12, lifetime: 0.16, pierce: true, clash: false, data: { index: 2, debris: true, ring: true },
          hit: { damage: 49, level: 'launch', knockback: { x: 4, y: 7 }, hitstop: 0.06, blockstun: 0.18, guardDamage: 12, juggle: 0.5, scaleStep: 0.05 },
        },
        {
          t: 0.4, kind: 'ember.column', offset: { f: 4.5, u: 0 }, box: { f: [-0.9, 0.9], u: [0, 2.8] },
          velocity: { x: 0.5, y: 0 }, delay: 0.2, lifetime: 0.16, pierce: true, clash: false, data: { index: 3, debris: true, ring: true },
          hit: { damage: 49, level: 'launch', knockback: { x: 4, y: 7 }, hitstop: 0.06, blockstun: 0.18, guardDamage: 12, juggle: 0.5, scaleStep: 0.05 },
        },
        {
          t: 0.4, kind: 'ember.column', offset: { f: 6.0, u: 0 }, box: { f: [-0.9, 0.9], u: [0, 2.8] },
          velocity: { x: 0.5, y: 0 }, delay: 0.28, lifetime: 0.16, pierce: true, clash: false, data: { index: 4, debris: true, ring: true, last: true },
          hit: { damage: 49, level: 'launch', knockback: { x: 4, y: 7 }, hitstop: 0.06, blockstun: 0.18, guardDamage: 12, juggle: 0.5, scaleStep: 0.05 },
        },
      ],
      cancels: [{ t: [0.5, 0.9], into: ['@ult'], onHit: true }],
      markers: [
        { t: 0, name: 'windup' },
        { t: 0.08, name: 'rune', data: { decal: 'rune circle' } },
        { t: 0.2, name: 'aura', data: { vfx: 'ember aura' } },
        { t: 0.32, name: 'trailOn', data: { style: 'overhead' } },
        { t: 0.4, name: 'release', data: { shake: 0.4 } },
        { t: 0.4, name: 'crack', data: { length: 6, speed: 18.75, cam: { shot: 'groundSkim', dur: 0.5, slowmo: 0.6 } } },
        { t: 0.44, name: 'column1', data: { f: 1.5 } },
        { t: 0.46, name: 'trailOff' },
        { t: 0.52, name: 'column2', data: { f: 3.0 } },
        { t: 0.6, name: 'column3', data: { f: 4.5 } },
        { t: 0.68, name: 'column4', data: { f: 6.0 } },
        { t: 0.74, name: 'recover', data: { wrench: true } },
      ],
      ai: { range: [1.4, 6.6], role: 'launcher', weight: 0.8 },
      meta: { slot: 'skill2' },
    },

    bulwark: {
      name: '화염 갑주 · Pyre Bulwark',
      duration: 0.92,
      fpCost: 30,
      cooldown: 9,
      // sword planted, an ember shell forms: a strike or a projectile landing in the window is swallowed and Kael
      // explodes outward at once (bulwark_burst). Whiffed: the shell sheds at 0.6 and he pulls the sword free.
      counter: { t: [0.04, 0.6], move: 'bulwark_burst', vs: 'all', hitstop: 0.1 },
      markers: [
        { t: 0, name: 'windup', data: { plant: true } },
        { t: 0.02, name: 'trailOn', data: { style: 'glow' } },
        { t: 0.04, name: 'release' },
        { t: 0.04, name: 'shell', data: { vfx: 'ember shell' } },
        { t: 0.6, name: 'shed' },
        { t: 0.62, name: 'trailOff' },
        { t: 0.66, name: 'recover' },
      ],
      ai: { role: 'counter', weight: 0.5 },
      meta: { slot: 'skill3' },
    },

    bulwark_burst: {
      name: '화염 갑주 · 폭발 · Pyre Bulwark — Burst',
      group: 'skill',                                          // reached only through the counter
      duration: 0.7,
      invuln: [{ t: [0, 0.32] }],
      hits: [{
        // Kael explodes outward: a 360° fire ring around him
        t: [0.05, 0.12], box: { f: [-2.1, 2.3], u: [0, 2.5] },
        damage: 125, level: 'knockdown', knockback: { x: 5.5, y: 4 }, hitstop: 0.18, unblockable: true,
      }],
      markers: [
        { t: 0, name: 'windup' },
        { t: 0, name: 'counter', data: { cam: { shot: 'crashZoom', dur: 0.25 } } },
        { t: 0.02, name: 'trailOn', data: { style: 'glow' } },
        { t: 0.04, name: 'release' },
        { t: 0.05, name: 'explode', data: { vfx: 'ember.explosion', ring: 360, impactFrame: true, shake: 0.5 } },
        { t: 0.22, name: 'trailOff' },
        { t: 0.38, name: 'recover' },
      ],
      meta: { slot: 'skill3' },
    },

    // -----------------------------------------------------------------------------------------------------------------
    // ULTIMATE
    pyre: {
      name: '일식의 장작 · Pyre of the Black Sun',
      ultCost: 100,
      superFreeze: 0.6,                                        // env.setMood({ darken: 0.75, tint: 0xff5020 }), letterbox in
      duration: 1.65,
      // the white-hot leap ploughs through anything thrown at it (hyper-armour, every hit, full damage)
      armour: [{ t: [0.6, 1.0] }],
      // forward leap-slash covering 4 m: push-off at 0.6, apex ~0.9 m, the blade comes down 0.85 .. 1.0
      motion: { keys: [[0, 0], [0.6, 0], [0.66, 0.15, 0.1], [0.76, 1.4, 0.8], [0.85, 2.9, 0.9], [0.93, 3.7, 0.45], [1.0, 4.0, 0]] },
      hits: [{
        // the downward slash from the air: the box reaches below his feet so it lands on a standing victim
        t: [0.85, 1.0], box: { f: [0, 2.1], u: [-0.4, 2.4] }, label: 'leapSlash',
        damage: 80, level: 'heavy', knockback: { x: 4.5, y: 0 }, hitstop: 0.2, blockstun: 0.34, guardDamage: 30,
      }],
      cinematic: {
        hit: 0,
        duration: 5.2,
        distance: 1.7,
        recovery: 0.5,
        ticks: [
          // 1.25 orbit sweep 70° around both: three rapid burning cuts in an X (ember.slash, afterimages of Kael)
          { t: 0.25, damage: 40, hitstop: 0.06, marker: 'cut1', data: { storyboard: 1.25, vfx: 'ember.slash', afterimage: true } },
          { t: 0.4, damage: 40, hitstop: 0.06, marker: 'cut2', data: { storyboard: 1.4, vfx: 'ember.slash', afterimage: true } },
          { t: 0.55, damage: 40, hitstop: 0.06, marker: 'cut3', data: { storyboard: 1.55, vfx: 'ember.slash', afterimage: true } },
          // 2.30 top-down slam view: the upward cut hurls the victim into the air (fire geyser, debris, hit.crit)
          { t: 1.3, damage: 60, hitstop: 0.1, marker: 'hurl', data: { storyboard: 2.3, vfx: 'fire geyser', audio: 'hit_crit' } },
        ],
        // 3.90 crash zoom from far: the meteor slam carries the victim into the floor (crater, ring of magma columns,
        // white flash). The victim stays in the crater until the lock releases it with a short bounce (knockdown).
        finish: {
          t: 2.9, damage: 260, level: 'knockdown', knockback: { x: 2.5, y: 3 }, hitstop: 0.22, marker: 'meteor',
          data: { storyboard: 3.9, vfx: 'ember.meteor', decal: 'crater', flash: 'white' },
        },
        markers: [
          { t: 0.25, name: 'orbit', data: { storyboard: 1.25, cam: { shot: 'orbit', degrees: 70 } } },
          { t: 1.8, name: 'leapAfter', data: { storyboard: 2.8, slowmo: 0.3, vfx: 'ember.inferno', sky: 'crimson', music: 'swell' } },
          { t: 2.4, name: 'spin', data: { storyboard: 3.4, vfx: 'ring of fire' } },
          { t: 3.3, name: 'shockwave', data: { storyboard: 4.3, shake: 1.0, audio: 'ult_impact', distort: 'shock', letterbox: false } },
          { t: 4.2, name: 'rise', data: { storyboard: 5.2, cam: { shot: 'blendBack', dur: 1.0 }, lingerEmbers: 3 } },
          { t: 5.2, name: 'settle', data: { storyboard: 6.2 } },
        ],
      },
      markers: [
        { t: 0, name: 'windup', data: { mood: { darken: 0.75, tint: 0xff5020 }, letterbox: true } },
        { t: 0.05, name: 'gather', data: { vfx: 'charge.gather', audio: 'ult_start' } },
        { t: 0.35, name: 'ignite', data: { vfx: 'corona flare', blade: 'white-hot' } },
        { t: 0.56, name: 'trailOn', data: { style: 'huge' } },
        { t: 0.6, name: 'leap', data: { vfx: 'ember.slash.heavy', speedlines: true, audio: 'swing_huge' } },
        { t: 0.8, name: 'release' },
        { t: 1.0, name: 'slam', data: { whiffVfx: 'ember.slash.heavy', shake: 0.5 } },
        { t: 1.06, name: 'trailOff' },
        { t: 1.12, name: 'recover' },
      ],
      ai: { range: [0, 5.8], role: 'finisher', weight: 1 },
      // storyboard row 1.00 (lock t = 0: the engine emits nothing at lock 0 but cinematicStart / the trigger's `hit`)
      meta: {
        slot: 'ult',
        storyboardAtTrigger: 1.0,
        impact: { shot: 'impactPunchIn', impactFrames: 3, flash: 'white', hitstop: 0.2, chroma: 1, radial: 0.8 },
      },
    },
  },
};

export default def;
