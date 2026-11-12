// VORN 볼른 — 뇌명의 창기사 · Stormcaller Lancer. Rules definition (pure data for src/game/logic; see its README.md).
// War spear: the longest reach of the roster (2.4 m jab, 2.6 m sweep, 3.7 m lightning spike), mid speed, explosive
// dashes (a 4 m lightning charge, a 6 m ultimate dash-thrust) and armour-piercing thrusts, a fast javelin, a delayed
// sky strike that targets the opponent, and a pass-through teleport dash. Strong at spear's length, weak up close:
// long recoveries, whiff-punishable spear (the auto hurtbox extension), mediocre advantage on block.
// Creative brief: src/fighters/MOVES.md. Frame data: node src/game/logic/test/framedata.mjs src/fighters/vorn/moves.js
//
// SLOTS (move id <- command; meta.slot = the roster slot name used by the UI move list and the clip fallbacks)
//   light1  flash_jab          light            섬광 찌르기 Flash Jab           0.11 startup, quick thrust, 2.4 m
//   light2  haft_spin          (light route)    회전 쳐올리기 Haft Spin          0.12, spins the spear, rising butt-end strike
//   light3  thunder_pierce     (light route)    천둥 꿰기 Thunder Pierce         0.20, lunge + thrust, lightning spike out of
//                                                                              the tip (2 hits, 3.7 m), big knockback
//   heavy   gale_sweep         heavy            폭풍 휩쓸기 Gale Sweep           0.28, wide low sweep (2.6 m), trip knockdown
//   fheavy  lightning_charge   f+heavy          번개 돌격 Lightning Charge       0.20, 4 m lightning dash, armour-piercing,
//                                                                              crumple
//   dheavy  skyward_lance      d+heavy          하늘 꿰뚫기 Skyward Lance         0.18, upward thrust, launch, bolt to the sky
//   skill1  thunder_javelin    skill1           뇌창 투척 Thunder Javelin        FP 25, CD 4 s: 20 m/s javelin, crumple
//   skill2  stormfall          skill2           낙뢰 Stormfall                   FP 35, CD 7 s: marker under the opponent,
//                                                                              3 sky bolts 0.45 / 0.57 / 0.69, last launches
//   skill3  arc_step           skill3           섬전 보법 Arc Step               FP 20, CD 5 s: 4 m bolt-form dash through the
//                                                                              opponent (intangible), the line detonates
//                                                                              0.25 s after re-forming
//   ult     ninefold_storm     ult              천벌의 뇌창 Lance of the Ninefold Storm  ULT 100: 6 m armour-piercing
//                                                                              dash-thrust (active 0.7-0.9) into a 5.0 s lock
//
// COMBO GRAMMAR (cancel routes; every target is listed by id, so only follow-ups that connect are offered)
//   light1 -> light2 -> light3                       chain (also on whiff / block: a real string)
//   light1 / light2 on hit -> d+heavy, f+heavy, heavy, ult        (light2 also -> skill1: the javelin at point blank)
//   light3 on hit -> f+heavy, skill2, ult ;  on hit or block -> skill1, skill3
//                                                    (the spike knocks the victim out to spear range: the javelin, the
//                                                    charge, the sky bolts or the ult dash catch them there; on block the
//                                                    javelin keeps them guarding and Arc Step crosses through them)
//   heavy on hit or block -> skill3                  (step over the tripped opponent for a wake-up cross-up / bail out)
//   f+heavy on hit (crumple, Vorn in their face) -> light1, heavy, d+heavy, skill1, skill2, ult
//   d+heavy on hit (launch) -> skill2, ult           (the sky bolts juggle the floating victim)
//   skill1 on hit (crumple at range) -> f+heavy, skill2, ult
//   skill2 on hit (the third bolt launches) -> ult ; skill3 after the detonation -> light1, heavy, f+heavy, d+heavy,
//   skill1 (whatever happened), ult (on hit)
//   e.g.  light1 > light2 > light3 > skill1 > ult                 the long-range route into the lock
//         light1 > d+heavy > skill2 > ult                         launcher, 3 sky bolts, lock
//         f+heavy > d+heavy > skill2                              from 6 m: charge, launch, bolts (~6 hits)
//         skill1 (crumple) > skill2 > ult                         full screen
//
// TIMELINE MARKERS (`marker` events: presentation hangs clips, trails, VFX, camera and audio on these names; the rules
// never read them). Beat notation of MOVES.md: WIND-UP -> RELEASE -> IMPACT -> AFTERMATH -> SETTLE.
//   every move    windup    WIND-UP starts: anticipation pose / clip start (t = 0)
//                 trailOn   the spear trail starts.  data: { style: 'thrust' | 'rising' | 'huge' | 'overhead' | 'glow' }
//                           ('glow' = no ribbon: the spear's arc glow only - stances, bolt-form travel)
//                 swing     RELEASE of a strike: the smear starts (a few frames before the first active frame)
//                 release   RELEASE of a skill / the ultimate: the thing leaves (javelin, spear brought down, bolt, dash)
//                 (impact)  IMPACT needs no marker: the engine's `hit` event carries contact point, level and hit-stop
//                 trailOff  the trail stops: AFTERMATH / follow-through
//                 recover   SETTLE: back toward the guard pose (spear low behind)
//   Hits carry a `label` (echoed in `hit` events): jab | butt | thrust spike | sweep | charge | lance | javelin |
//   bolt1 bolt2 bolt3 | detonation | lance (ult trigger).
//   haft_spin           spin                             the spear whirls in the hands before the butt-end rises
//   thunder_pierce      lunge spike                      step-in / the lightning spike shoots out of the tip (hit or not)
//   gale_sweep          sparks                           the blade drags along the floor: sparks + scorch along the arc
//   lightning_charge    dash stop                        bursts into a streak of lightning (afterimages) / arrives, skids
//   skyward_lance       bolt                             a bolt shoots from the tip to the sky (hit or not)
//   thunder_javelin     form detach                      the lightning javelin forms on the spear / it leaves the hand
//                                                        (`volt.javelin`, 20 m/s, crackling ribbon: follow the projectile,
//                                                        kind 'volt.javelin'; impact = bolt explosion + chain arcs)
//   stormfall           raise clouds mark strike1..strike3
//                                                        spear to the sky (camera tilts up) / the clouds above the arena
//                                                        flicker / the marker scorches under the opponent (the bolts are
//                                                        anchored there: projectileSpawn kind 'volt.strike', data.index
//                                                        1..3, same x) / each sky bolt (`volt.strike`; camera crash-down cut
//                                                        on strike1, shake 0.6 on the huge strike3)
//   arc_step            blink reappear detonate          dissolves into a bolt (`volt.dash`) / re-forms 4 m forward (the
//                                                        lightning line runs from blink.x to reappear.x: both markers carry
//                                                        x) / the line detonates (`volt.chain`; the hit is the projectile
//                                                        kind 'volt.chain' spawned at that instant)
//   ninefold_storm (move clock)   superFreeze (engine, t = 0) windup freeze skyBolt charge trailOn release dash swing
//                                 overrun trailOff recover
//                                 freeze = the rain streaks stop mid-air; skyBolt = a sky bolt hits the spear tip;
//                                 release/dash = the lightning dash-thrust (camera cut: weapon-follow along the spear).
//                                 On a hit the lock takes over (the move clock stops): overrun / trailOff / recover fire
//                                 only on a whiff or a block (overrun = the big harmless lightning burst at the end of the dash)
//   ninefold_storm (lock clock, `cinematic: true` markers; ticks and the finish emit their own `marker`)
//                                 lift hurl throw leap bolt1..bolt9 catch storm slam land blendBack twirl settle
//
// Marker `data` keys: style (trailOn); shake (trauma), kickFov (deg), afterimage, vfx (preset at the weapon tip) are the
// generic feel hints of src/game/feel.js; fx (named effect placed by the choreography: at 'target' | 'line' | 'sky' ...),
// cam (shot cue), audio (cue name), post (screen fx), storyboard (MOVES.md table time) are cues for the hand-made
// choreography only.
//
// ULTIMATE TIMING. Storyboard rows 0.00 and 0.60 are the opener on the MOVE clock: super-freeze 0 .. 0.6 s (low hero
// angle, a sky bolt hits the spear tip; world violet-black via env.setMood({ darken: 0.8, tint: 0xa080ff }), letterbox
// in), then the lightning dash-thrust (6 m, active 0.7 .. 0.9, armour-piercing, invulnerable while it bursts out). The
// 0.90 row ("spear skewers, victim lifted on the spear") is the trigger itself: the lock clock starts there (t = 0 at the
// contact; the impact punch-in, impact frame, violet-white flash and 0.2 s hit-stop ride on `cinematicStart` and the
// trigger's `hit` event, parameters in ninefold_storm.meta.impact: the engine never emits lock markers or ticks at t = 0).
// Every later row keeps its spacing from the impact:  storyboard t = 0.90 + lock t.  The lock lasts 5.0 s: the 5.00 row
// (blend back, Vorn lands, spear twirl) starts at lock 4.10 and runs to cinematicEnd at lock 5.00. Every lock marker and
// tick carries its storyboard time in data.storyboard.
//   lock 0.05 lift | 0.30 hurl (orbit sweep rising) | 0.45 throw (the spear after the victim) | 0.90 leap (over the
//   shoulder looking up) | 1.00 .. 2.01 bolt1..bolt9, an accelerating rhythm (0.16 -> 0.10 s apart), stuttered hit-stops |
//   2.30 catch (slow-mo 0.35) | 2.40 storm | 3.20 slam = finish (crash zoom, colossal pillar) | 4.10 land + blendBack |
//   4.40 twirl | 5.00 settle (= cinematicEnd)
//   Damage 90 (dash-thrust) + 9 x 22 + 230 = 518 (lock damage x max(0.7, combo scale at the trigger)).

/** Vorn's fighter definition (author format, validated by validateFighterDef). */
export const def = {
  id: 'vorn',
  name: '볼른 · VORN',
  title: '뇌명의 창기사 · Stormcaller Lancer',

  // Tall, lean lancer in plate with a horned helm (the horns are not hurtbox): average HP and weight, a slim body,
  // medium feet, the most explosive dash of the roster (long and quick) and a long backstep to reset spear range.
  stats: {
    hp: 1000,
    fpMax: 100,
    ultMax: 100,
    guardMax: 100,
    walkSpeed: 2.6,
    backSpeed: 2.0,
    weight: 1.0,
    pushWidth: 0.4,
    hurtWidth: 0.41,
    height: 1.9,
  },

  movement: {
    dash: { duration: 0.26, distance: 2.9, cancelFrom: 0.12 },
    backstep: { duration: 0.32, distance: 1.85, invuln: [0, 0.13] },
    dodge: { duration: 0.42, invuln: [0.02, 0.29], cooldown: 0.7, cancelFrom: 0.3 },
    roll: { duration: 0.42, distance: 2.6 },
  },

  commands: {
    light: 'flash_jab',
    heavy: 'gale_sweep',
    'f+heavy': 'lightning_charge',
    'd+heavy': 'skyward_lance',
    skill1: 'thunder_javelin',
    skill2: 'stormfall',
    skill3: 'arc_step',
    ult: 'ninefold_storm',
  },

  // Spacing fighter: holds the tip of his spear (~2.3 m, outside most pokes), zones with the javelin and the sky
  // bolts from afar, and closes the gap in one explosive burst when he sees an opening.
  ai: { aggression: 0.5, zoning: 0.55, preferredRange: 2.3 },

  meta: { element: 'volt', weapon: 'war spear' },

  moves: {
    // -----------------------------------------------------------------------------------------------------------------
    // LIGHT CHAIN
    flash_jab: {
      name: '섬광 찌르기 · Flash Jab',
      duration: 0.38,
      motion: [{ t: [0.02, 0.1], v: 1.5 }],                      // a 12 cm lean into the thrust
      hits: [{
        // straight one-handed thrust at chest height: the spear's full length (2.3 m + the lean = 2.4 m)
        t: [0.11, 0.15], box: { f: [0.4, 2.3], u: [0.95, 1.6] }, label: 'jab',
        damage: 34, level: 'light', hitstun: 0.32, blockstun: 0.18, knockback: { x: 2.2, y: 0 }, hitstop: 0.055, guardDamage: 10,
      }],
      cancels: [
        { t: [0.14, 0.36], on: 'light', into: 'haft_spin' },
        { t: [0.13, 0.3], into: ['skyward_lance', 'lightning_charge', 'gale_sweep', '@ult'], onHit: true },
      ],
      markers: [
        { t: 0, name: 'windup' },
        { t: 0.07, name: 'trailOn', data: { style: 'thrust' } },
        { t: 0.08, name: 'swing' },
        { t: 0.19, name: 'trailOff' },
        { t: 0.24, name: 'recover' },
      ],
      ai: { range: [0, 2.4], role: 'poke', weight: 1.3 },
      meta: { slot: 'light1' },
    },

    haft_spin: {
      name: '회전 쳐올리기 · Haft Spin',
      duration: 0.44,
      motion: [{ t: [0, 0.12], v: 3.75 }],                       // steps 0.45 m in while the spear whirls
      hits: [{
        // the spear spins in the hands and the butt-end rises from the hip to the jaw (shorter than the blade end)
        t: [0.12, 0.16], box: { f: [0.2, 1.8], u: [0.6, 1.95] }, label: 'butt',
        damage: 38, level: 'light', hitstun: 0.36, blockstun: 0.2, knockback: { x: 2.4, y: 0 }, hitstop: 0.06, guardDamage: 12,
      }],
      cancels: [
        { t: [0.15, 0.4], on: 'light', into: 'thunder_pierce' },
        { t: [0.14, 0.32], into: ['skyward_lance', 'lightning_charge', 'gale_sweep', 'thunder_javelin', '@ult'], onHit: true },
      ],
      markers: [
        { t: 0, name: 'windup', data: { continues: 'flash_jab' } },
        { t: 0.02, name: 'spin' },
        { t: 0.05, name: 'trailOn', data: { style: 'rising' } },
        { t: 0.09, name: 'swing' },
        { t: 0.21, name: 'trailOff' },
        { t: 0.27, name: 'recover' },
      ],
      ai: { role: 'combo', comboOnly: true },
      meta: { slot: 'light2' },
    },

    thunder_pierce: {
      name: '천둥 꿰기 · Thunder Pierce',
      duration: 0.64,
      motion: [{ t: [0.04, 0.2], v: 3.2 }],                      // half-metre lunge into the thrust
      hits: [
        {
          // the lunging two-handed thrust
          t: [0.2, 0.24], box: { f: [0.4, 2.5], u: [0.8, 1.7] }, label: 'thrust',
          damage: 30, level: 'light', hitstun: 0.3, blockstun: 0.18, knockback: { x: 1.2, y: 0 }, hitstop: 0.06, guardDamage: 10,
        },
        {
          // the lightning spike: runs down the whole shaft and shoots 0.7 m out of the tip; blasts the victim back to
          // spear range (slide ~1.6 m). Armour-piercing like every Vorn thrust.
          t: [0.25, 0.3], box: { f: [0.4, 3.2], u: [0.7, 1.8] }, label: 'spike',
          damage: 42, level: 'heavy', hitstun: 0.55, blockstun: 0.26, knockback: { x: 7, y: 0 }, hitstop: 0.11, guardDamage: 16,
          armourPierce: true,
        },
      ],
      cancels: [
        { t: [0.28, 0.5], into: ['thunder_javelin', 'arc_step'], onContact: true },
        { t: [0.28, 0.5], into: ['lightning_charge', 'stormfall', '@ult'], onHit: true },
      ],
      markers: [
        { t: 0, name: 'windup' },
        { t: 0.04, name: 'lunge' },
        { t: 0.14, name: 'trailOn', data: { style: 'thrust' } },
        { t: 0.17, name: 'swing' },
        { t: 0.25, name: 'spike', data: { fx: 'volt.spike', length: 0.7 } },
        { t: 0.33, name: 'trailOff' },
        { t: 0.42, name: 'recover' },
      ],
      ai: { role: 'combo', comboOnly: true },
      meta: { slot: 'light3' },
    },

    // -----------------------------------------------------------------------------------------------------------------
    // HEAVIES
    gale_sweep: {
      name: '폭풍 휩쓸기 · Gale Sweep',
      duration: 0.76,
      motion: [{ t: [0.1, 0.26], v: 1.25 }],                     // pivot step (0.2 m) into the sweep
      hits: [{
        // wide low sweep at ankle-to-knee height: the arc starts at his side (catches a close cross-up) and ends at the
        // blade's full length; trips the opponent into a knockdown
        t: [0.28, 0.36], box: { f: [-0.5, 2.45], u: [0, 0.7] }, label: 'sweep',
        damage: 100, level: 'knockdown', knockback: { x: 3, y: 3.2 }, hitstop: 0.12, blockstun: 0.28, guardDamage: 28,
      }],
      cancels: [{ t: [0.38, 0.6], into: ['arc_step'], onContact: true }],
      markers: [
        { t: 0, name: 'windup' },
        { t: 0.2, name: 'trailOn', data: { style: 'huge' } },
        { t: 0.24, name: 'swing' },
        { t: 0.28, name: 'sparks', data: { fx: 'floor sparks', decal: 'scorch arc' } },
        { t: 0.42, name: 'trailOff' },
        { t: 0.5, name: 'recover' },
      ],
      ai: { range: [0.5, 2.6], role: 'pressure', weight: 0.85 },
      meta: { slot: 'heavy' },
    },

    lightning_charge: {
      name: '번개 돌격 · Lightning Charge',
      duration: 0.74,
      // 4 m: a crouch, an explosive burst, the thrust as he arrives, a short skid. Up close the spear is out at 0.20;
      // at the far end of its range (6 m) it lands around 0.30. Solid: the spear stops in the victim (or the guard)
      // and shoves it instead of passing through.
      motion: { keys: [[0, 0], [0.06, 0.05], [0.2, 1.6], [0.32, 3.8], [0.38, 4.0]] },
      hits: [{
        // the thrust at the head of the streak: chest height, the spear's length
        t: [0.2, 0.32], box: { f: [0.2, 2.3], u: [0.6, 1.8] }, label: 'charge',
        damage: 68, level: 'crumple', hitstun: 0.95, blockstun: 0.24, knockback: { x: 1.5, y: 0 }, hitstop: 0.12, guardDamage: 26,
        armourPierce: true,
      }],
      cancels: [{ t: [0.32, 0.58], into: ['flash_jab', 'gale_sweep', 'skyward_lance', 'thunder_javelin', 'stormfall', '@ult'], onHit: true }],
      markers: [
        { t: 0, name: 'windup' },
        { t: 0.06, name: 'dash', data: { afterimage: true, fx: 'volt.dash' } },
        { t: 0.12, name: 'trailOn', data: { style: 'thrust' } },
        { t: 0.17, name: 'swing' },
        { t: 0.38, name: 'stop' },
        { t: 0.4, name: 'trailOff' },
        { t: 0.52, name: 'recover' },
      ],
      ai: { range: [2.8, 5.6], role: 'approach', weight: 0.6 },
      meta: { slot: 'fheavy' },
    },

    skyward_lance: {
      name: '하늘 꿰뚫기 · Skyward Lance',
      duration: 0.64,
      motion: [{ t: [0.02, 0.14], v: 2.5 }],                     // 0.3 m drive from the crouch
      hits: [{
        // upward thrust from a crouch: from the hips to well above the head along the spear's angle (anti-air too)
        t: [0.18, 0.25], box: { f: [0.2, 1.95], u: [0.3, 3.0] }, label: 'lance',
        damage: 60, level: 'launch', knockback: { x: 1.0, y: 9.5 }, hitstop: 0.11, blockstun: 0.24, guardDamage: 22,
      }],
      cancels: [{ t: [0.24, 0.5], into: ['stormfall', '@ult'], onHit: true }],
      markers: [
        { t: 0, name: 'windup' },
        { t: 0.12, name: 'trailOn', data: { style: 'rising' } },
        { t: 0.15, name: 'swing' },
        { t: 0.18, name: 'bolt', data: { fx: 'volt.skybolt', from: 'tip', to: 'sky' } },
        { t: 0.3, name: 'trailOff' },
        { t: 0.42, name: 'recover' },
      ],
      ai: { range: [0, 2.2], role: 'launcher', weight: 0.65 },
      meta: { slot: 'dheavy' },
    },

    // -----------------------------------------------------------------------------------------------------------------
    // SKILLS
    thunder_javelin: {
      name: '뇌창 투척 · Thunder Javelin',
      duration: 0.68,
      fpCost: 25,
      cooldown: 4,
      projectiles: [{
        // WIND-UP 0-0.26 spear drawn back over the shoulder while a duplicate javelin of pure lightning forms on it;
        // RELEASE 0.26 thrown at 20 m/s (9 m of flight) at shoulder height with a crackling ribbon.
        // IMPACT: bolt explosion, chain arcs to the floor, the victim seizes up (crumple).
        t: 0.26, kind: 'volt.javelin', offset: { f: 0.8, u: 1.55 }, box: { f: [-0.75, 0.45], u: [-0.3, 0.3] },
        velocity: { x: 20, y: 0 }, lifetime: 0.45, durability: 1,
        data: { ribbon: 'crackle', impact: { fx: 'bolt explosion', chainArcs: true, shake: 0.35 } },
        hit: { damage: 72, level: 'crumple', hitstun: 0.9, blockstun: 0.22, knockback: { x: 1.2, y: 0 }, hitstop: 0.15, guardDamage: 20, label: 'javelin' },
      }],
      cancels: [{ t: [0.3, 0.66], into: ['lightning_charge', 'stormfall', '@ult'], onHit: true }],
      markers: [
        { t: 0, name: 'windup' },
        { t: 0.04, name: 'form', data: { fx: 'volt.charge', audio: 'volt_charge' } },
        { t: 0.18, name: 'trailOn', data: { style: 'thrust' } },
        { t: 0.26, name: 'release', data: { kickFov: -2 } },
        { t: 0.26, name: 'detach', data: { fx: 'volt.javelin', audio: 'volt_zap' } },
        { t: 0.36, name: 'trailOff' },
        { t: 0.44, name: 'recover' },
      ],
      ai: { range: [2.6, 9.5], role: 'zoning', weight: 1.0 },
      meta: { slot: 'skill1' },
    },

    stormfall: {
      name: '낙뢰 · Stormfall',
      duration: 0.86,
      fpCost: 35,
      cooldown: 7,
      // WIND-UP 0-0.45: the spear rises to the sky, the clouds flicker, and at 0.08 a marker scorches under the opponent
      // (all three bolts are anchored there: 0.37 s to get off it - a dash, a backstep, a well-timed dodge or a walk
      // toward Vorn escape; walking away only for the quickest feet). RELEASE 0.45: a sky bolt strikes the marker, then two more 0.12 s apart,
      // the last one huge and wider (launches: the ult dash or a juggle follows). Columns reach 5 m up, so they also
      // strike a victim floating in a juggle. No drift: blocked from the side the victim faces.
      projectiles: [
        {
          t: 0.08, kind: 'volt.strike', at: 'opponent', box: { f: [-0.4, 0.4], u: [0, 5.0] }, delay: 0.37, lifetime: 0.08,
          clash: false, data: { index: 1 },
          hit: { damage: 28, level: 'heavy', hitstun: 0.42, blockstun: 0.2, knockback: { x: 0.3, y: 0 }, hitstop: 0.07, guardDamage: 10, juggle: 1, label: 'bolt1' },
        },
        {
          t: 0.08, kind: 'volt.strike', at: 'opponent', box: { f: [-0.4, 0.4], u: [0, 5.0] }, delay: 0.49, lifetime: 0.08,
          clash: false, data: { index: 2 },
          hit: { damage: 28, level: 'heavy', hitstun: 0.42, blockstun: 0.2, knockback: { x: 0.3, y: 0 }, hitstop: 0.07, guardDamage: 10, juggle: 1, label: 'bolt2' },
        },
        {
          t: 0.08, kind: 'volt.strike', at: 'opponent', box: { f: [-0.55, 0.55], u: [0, 5.0] }, delay: 0.61, lifetime: 0.1,
          clash: false, data: { index: 3, huge: true },
          hit: { damage: 56, level: 'launch', knockback: { x: 0.8, y: 8.5 }, blockstun: 0.26, hitstop: 0.16, guardDamage: 20, juggle: 1, label: 'bolt3' },
        },
      ],
      cancels: [{ t: [0.5, 0.84], into: ['@ult'], onHit: true }],
      markers: [
        { t: 0, name: 'windup' },
        { t: 0.04, name: 'raise', data: { cam: { shot: 'tiltUp', dur: 0.4 } } },
        { t: 0.08, name: 'mark', data: { fx: 'scorch marker', at: 'target' } },
        { t: 0.1, name: 'clouds', data: { fx: 'cloud flicker', at: 'sky' } },
        { t: 0.36, name: 'trailOn', data: { style: 'overhead' } },
        { t: 0.45, name: 'release', data: { cam: { shot: 'crashDown', cut: true } } },
        { t: 0.45, name: 'strike1', data: { fx: 'volt.strike', at: 'target', shake: 0.35, audio: 'volt_strike' } },
        { t: 0.55, name: 'trailOff' },
        { t: 0.57, name: 'strike2', data: { fx: 'volt.strike', at: 'target', shake: 0.4, audio: 'volt_strike' } },
        { t: 0.69, name: 'strike3', data: { fx: 'volt.strike', at: 'target', huge: true, shake: 0.6, audio: 'volt_strike' } },
        { t: 0.7, name: 'recover' },
      ],
      ai: { range: [2.8, 9.0], role: 'zoning', weight: 0.6 },
      meta: { slot: 'skill2' },
    },

    arc_step: {
      name: '섬전 보법 · Arc Step',
      duration: 0.62,
      fpCost: 20,
      cooldown: 5,
      // Vorn dissolves into a bolt at 0.08 and re-forms 4 m forward at 0.18 (40 m/s), passing through the opponent:
      // intangible and without a push-box during the travel. The lightning line he leaves (from his start to the
      // arrival point) detonates at 0.43, 0.25 s after he re-forms: a projectile laid over the 4 m behind him, so only
      // the victim freezes and he can follow up from the other side. It creeps back toward the start, so a victim who
      // turned to face Vorn blocks it; one still facing the start (busy attacking) is hit from behind. Interrupt him
      // before 0.43 and the line fizzles.
      motion: { keys: [[0, 0], [0.08, 0], [0.18, 4.0]] },
      invuln: [{ t: [0.06, 0.22], vs: 'all' }],
      passThrough: [[0.06, 0.26]],
      projectiles: [{
        t: 0.43, kind: 'volt.chain', offset: { f: -2.0, u: 0 }, box: { f: [-2.0, 2.0], u: [0, 1.9] },
        velocity: { x: -0.3, y: 0 }, lifetime: 0.08, clash: false, data: { length: 4, detonate: true },
        hit: { damage: 55, level: 'heavy', hitstun: 0.5, blockstun: 0.22, knockback: { x: 1.2, y: 0 }, hitstop: 0.14, guardDamage: 16, label: 'detonation' },
      }],
      cancels: [
        { t: [0.44, 0.6], into: ['flash_jab', 'gale_sweep', 'lightning_charge', 'skyward_lance', 'thunder_javelin'] },
        { t: [0.44, 0.6], into: ['@ult'], onHit: true },
      ],
      markers: [
        { t: 0, name: 'windup' },
        { t: 0.06, name: 'trailOn', data: { style: 'glow' } },
        { t: 0.08, name: 'release' },
        { t: 0.08, name: 'blink', data: { fx: 'volt.dash', afterimage: true } },
        { t: 0.18, name: 'reappear', data: { fx: 'volt.reform', line: 4 } },
        { t: 0.2, name: 'trailOff' },
        { t: 0.43, name: 'detonate', data: { fx: 'volt.chain', at: 'line', shake: 0.3 } },
        { t: 0.45, name: 'recover' },
      ],
      ai: { range: [1.4, 3.6], role: 'mobility', weight: 0.5 },
      meta: { slot: 'skill3' },
    },

    // -----------------------------------------------------------------------------------------------------------------
    // ULTIMATE
    ninefold_storm: {
      name: '천벌의 뇌창 · Lance of the Ninefold Storm',
      ultCost: 100,
      superFreeze: 0.6,                                        // env.setMood({ darken: 0.8, tint: 0xa080ff }), letterbox in
      duration: 1.35,
      // the lightning dash-thrust: push-off at 0.6, a bolt-fast run 0.7 .. 0.86, 6 m in all. Invulnerable while it bursts
      // out of the freeze (nothing the frozen opponent left active can stop it); solid: the spear stops in the victim
      // (or a guard) instead of passing through.
      invuln: [{ t: [0.6, 0.8], vs: 'all' }],
      motion: { keys: [[0, 0], [0.6, 0], [0.64, 0.2], [0.7, 1.0], [0.86, 5.6], [0.9, 6.0]] },
      hits: [{
        // the spear at full extension, wrapped in lightning: chest to head height (lifts the victim off the floor)
        t: [0.7, 0.9], box: { f: [0.3, 2.7], u: [0.3, 2.3] }, label: 'lance',
        damage: 90, level: 'heavy', knockback: { x: 4, y: 0 }, hitstop: 0.2, blockstun: 0.34, guardDamage: 30,
        armourPierce: true,
      }],
      cinematic: {
        hit: 0,
        duration: 5.0,
        distance: 1.9,                                         // skewered at the spear's tip
        recovery: 0.5,
        ticks: [
          // 1.80 over-the-shoulder looking up: Vorn leaps; nine bolts strike the floating victim in sequence, an
          // accelerating rhythm with stuttered hit-stops (9 x volt.chain / bolt, rapid flashes)
          { t: 1.0, damage: 22, hitstop: 0.06, marker: 'bolt1', data: { storyboard: 1.9, fx: 'volt.chain', flash: 'violet' } },
          { t: 1.16, damage: 22, hitstop: 0.03, marker: 'bolt2', data: { storyboard: 2.06, fx: 'volt.chain', flash: 'violet' } },
          { t: 1.31, damage: 22, hitstop: 0.05, marker: 'bolt3', data: { storyboard: 2.21, fx: 'volt.chain', flash: 'violet' } },
          { t: 1.45, damage: 22, hitstop: 0.03, marker: 'bolt4', data: { storyboard: 2.35, fx: 'volt.chain', flash: 'violet' } },
          { t: 1.58, damage: 22, hitstop: 0.05, marker: 'bolt5', data: { storyboard: 2.48, fx: 'volt.chain', flash: 'violet' } },
          { t: 1.7, damage: 22, hitstop: 0.03, marker: 'bolt6', data: { storyboard: 2.6, fx: 'volt.chain', flash: 'violet' } },
          { t: 1.81, damage: 22, hitstop: 0.04, marker: 'bolt7', data: { storyboard: 2.71, fx: 'volt.chain', flash: 'violet' } },
          { t: 1.91, damage: 22, hitstop: 0.03, marker: 'bolt8', data: { storyboard: 2.81, fx: 'volt.chain', flash: 'violet' } },
          { t: 2.01, damage: 22, hitstop: 0.09, marker: 'bolt9', data: { storyboard: 2.91, fx: 'volt.strike', flash: 'white', last: true } },
        ],
        // 4.10 top-down slam view, crash zoom: Vorn drives the victim down with the spear, a colossal pillar of
        // lightning (volt.strike huge + pillar, crater, ult_impact, white flash, shake 1). The victim stays in the crater
        // until the lock releases it with a short bounce (knockdown).
        finish: {
          t: 3.2, damage: 230, level: 'knockdown', knockback: { x: 2, y: 3 }, hitstop: 0.24, marker: 'slam',
          data: {
            storyboard: 4.1, fx: 'volt.strike', huge: true, pillar: true, decal: 'crater', audio: 'ult_impact',
            post: { flash: 'white' }, cam: { shot: 'topDownSlam', crashZoom: true, shake: 1 },
          },
        },
        markers: [
          // 0.90 impact punch-in (the trigger itself; see meta.impact): the victim is lifted on the spear
          { t: 0.05, name: 'lift', data: { storyboard: 0.95 } },
          // 1.20 orbit sweep rising: Vorn hurls the victim upward and throws the spear after them
          { t: 0.3, name: 'hurl', data: { storyboard: 1.2, cam: { shot: 'orbitRising' } } },
          { t: 0.45, name: 'throw', data: { storyboard: 1.35, fx: 'volt.javelin', audio: 'volt_zap' } },
          { t: 0.9, name: 'leap', data: { storyboard: 1.8, cam: { shot: 'overShoulderUp' } } },
          // 3.20 wide low establishing, slow-mo 0.35: Vorn catches the spear mid-air, the storm gathers into it
          { t: 2.3, name: 'catch', data: { storyboard: 3.2, cam: { shot: 'wideLow', slowmo: 0.35 } } },
          { t: 2.4, name: 'storm', data: { storyboard: 3.3, fx: 'volt.storm', corona: 'violet flicker', audio: 'volt_loop' } },
          // 5.00 blend back to the fight camera: Vorn lands, spear twirl, arcs fade (sparks + scorch linger)
          { t: 4.1, name: 'land', data: { storyboard: 5.0 } },
          { t: 4.1, name: 'blendBack', data: { storyboard: 5.0, cam: { shot: 'blendBack', dur: 0.9 }, letterbox: false, mood: null } },
          { t: 4.4, name: 'twirl', data: { storyboard: 5.3, linger: { sparks: 2, scorch: 3 } } },
          { t: 5.0, name: 'settle', data: { storyboard: 5.9 } },
        ],
      },
      markers: [
        { t: 0, name: 'windup', data: { mood: { darken: 0.8, tint: 0xa080ff }, letterbox: true, cam: { shot: 'lowHero', rain: true } } },
        { t: 0, name: 'freeze', data: { rain: 'frozen' } },
        { t: 0.1, name: 'skyBolt', data: { fx: 'volt.strike', into: 'spear tip', audio: 'ult_start' } },
        { t: 0.2, name: 'charge', data: { fx: 'volt.charge', audio: 'volt_charge' } },
        { t: 0.56, name: 'trailOn', data: { style: 'huge' } },
        { t: 0.6, name: 'release' },
        { t: 0.6, name: 'dash', data: { fx: 'volt.dash', afterimage: true, speedlines: true, cam: { shot: 'weaponFollow', cut: true } } },
        { t: 0.66, name: 'swing' },
        { t: 0.92, name: 'overrun', data: { fx: 'volt.strike', harmless: true, shake: 0.4 } },
        { t: 0.98, name: 'trailOff' },
        { t: 1.05, name: 'recover' },
      ],
      ai: { range: [0, 8.0], role: 'finisher', weight: 1 },
      // storyboard row 0.90 (lock t = 0: the engine emits nothing at lock 0 but cinematicStart / the trigger's `hit`)
      meta: {
        slot: 'ult',
        storyboardAtTrigger: 0.9,
        mood: { darken: 0.8, tint: 0xa080ff },
        impact: { shot: 'impactPunchIn', impactFrames: 3, flash: 'violet-white', hitstop: 0.2, chroma: 1, radial: 0.8 },
      },
    },
  },
};

export default def;
