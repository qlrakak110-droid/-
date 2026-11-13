# MOTION.md — the motion bible of 「흑일무림 黑日武林」

Owner: animation director. Binding for every clip of `src/fighters/<id>/clips/` and for the generic `game.*` clips.
Read with `MURIM.md` (art direction), `src/char/README.md` (rig, clip format) and `src/game/README.md` §3.2 (state →
clip map). Frame data is law (`moves.js`, `present.js`, `BALANCE.md` §8–9): a move clip's duration, its first impact
time, its `trailOn` / `trailOff` times, its root-motion distances and the lock-clock beats never change. You change
**how** the body gets there, never when or how far.

Contents: 1 the bar · 2 stance sheets · 3 review harness · 4 variant slots · 5 the generic set · 6 worked examples ·
7 per-clip review (염무강 / 설리화 / 뇌진천) · 8 new clips per hero · 9 rig and design findings · 10 checklist.

Hero ids and names: `kael` = 염무강 (참마대도, the colossal great saber), `iska` = 설리화 (월아쌍도, twin crescents),
`vorn` = 뇌진천 (뇌룡창, the tasselled spear).

---

## 1. The bar

Every clip is judged on the sheet first (section 3), on the numbers second. The numbers only tell you where to look.

**1.1 Martial foundation.** A pose comes from a stance, never from a standing mannequin.

| stance | use | in bone terms (fighter frame, metres / degrees) |
|---|---|---|
| 마보 horse | 염무강's coils, stomps, guard hits | feet 0.7–0.8 apart on the fight line, hips ≥ 0.15 below standing, both knees over the toes, hips yaw −20…−30 |
| 궁보 bow | every committed cut / thrust | front shin vertical, rear leg long (thigh `z` ≤ −20), hips ≥ 0.17 low and 0.05–0.15 ahead of the stance, rear foot flat for 염무강, heel up 20–26° for the other two |
| 허보 empty / cat | 설리화's stillness, every retreat | 70 % of the weight on the rear leg (hips −0.08…−0.12 f), front foot on its ball (pitch −20…−26), front knee soft |
| 헐보 / 교차보 crossed | pivots, 설리화's spins, turn-arounds | the stepping foot crosses the line, the support foot turns on its ball (yaw change with the ball fixed: see `pivot()` in `iska/clips/moves.js`) |

**1.2 Power travels foot → hip → waist → shoulder → elbow → wrist → blade.** Offset timing is measurable:

* at the *hang* (the key before the strike) the hips have already unwound ≥ 12° while the weapon still moves back;
* hips reach their impact yaw 1–2 frames before the hands reach the impact position;
* the hand `aim` reaches the impact direction on the impact frame, never before (the blade arrives last);
* the clavicle joins: `shoulderR` Y −8…−12 (retracted) in the coil, +12…+16 (protracted) at the impact.

A swing whose hips move less than 20° of yaw between coil and impact is an arm swing: redo it.

**1.3 Timing (60 fps frames).**

| beat | lights (≤ 9 f startup) | heavies / skills |
|---|---|---|
| anticipation | 3 f sink + coil (`outCubic`), 2 f hang | 6–12 f: a sink, a breath (chest `z` +4…+6), the coil; 염무강 stamps |
| strike | 2–3 f for 100–130° of arc, one steering key in the middle | 3–4 f |
| kime (the held instant) | 2 f, ≤ 6° of blade travel, `outQuad` into it | 3–4 f |
| follow-through | 3–4 f, `inQuad` out of the kime, carried past the target | 5–8 f |
| settle | the way back is a different path (never the strike reversed); 2–4 cm / 3–5° overshoot past the stance | long hauls for 염무강 |

No even spacing: read the dots of the tip trail on the sheet (one per frame). Equal gaps = linear = wrong.

**1.4 Arcs.** Hands and tips travel on arcs or on a deliberate straight thrust line. `knk` (kinks) on a strike must be
0–2. The weapon never passes through the body, the head, the hat, the hair-tail root (`clear` ≥ +5 cm at 240 Hz) or the
floor (`flBl` = 0 unless the clip is *about* biting the floor, and then ≤ 150 mm).

**1.5 Feet.** A planted foot does not move: `drift` ≤ 1 cm. A step shows the weight leaving first (hips shift 1–2 f
before the foot lifts), lifts ≥ 5 cm (a 3 cm lift reads as a slide and the audit counts it as one), lands with
`ease: 'inQuad'` and a `step` event. Stamps (진각) land one frame before the impact. Heels and toes roll (pitch keys).

**1.6 Ceremony.** Intros open with 포권례 (fist in palm) or a 기수식 flourish into the guard; victories end with a
flick of the blade and stillness; defeat is a knee and the weapon as a strut; skill wind-ups have an 운기 beat (a sink,
a breath, a hand seal or the weapon drawn across the body).

**1.7 Life.** Idles breathe (`breath` ≥ 1.2), drift, re-grip, turn the head; reactions have direction and mass: the
head goes first, the torso folds around the blow, a step recovers.

**1.8 The pass line of the audit** (`node tools/motion.mjs <hero> <clips> --audit`):

| column | meaning | pass |
|---|---|---|
| `drift` / `skid` | planted-foot drift / slide into the plant (cm) | drift ≤ 1 (pivots and skating slides are listed by name in section 7) |
| `flFt` `flBl` `flBd` | deepest point below the floor: feet / blade / hands, knees, pommel (mm) | ≤ 5 / 0 / ≤ 10 |
| `lim` | joints beyond the human range | no arm or spine entry; rear-ankle dorsiflexion in a deep stance ≤ +15° |
| `isx` / `bld` | body capsule pairs / blade-vs-body pairs deeper than 1.5 cm | `bld` 0; `isx` arm-vs-torso ≤ 6 cm |
| `clear` | weapon clearance of the head and the costume keep-outs, at 240 Hz (cm) | ≥ +5 |
| `pop` / `ovr` | joint velocity steps / joints above the human speed table | compare with the clip's own baseline; a kime adds deliberate steps |
| `unsup` / `comOut` | centre of mass outside the support while both feet are flat | 0 unless a committed lunge |
| `aim` | worst wrist clamp (deg): the blade is that far from its key | ≤ 30 (above: the key asks for a wrist no human has; see 3.4) |
| `tip` / `knk` | peak tip speed (m/s) / direction kinks in a swing | knk ≤ 2 |

Nothing may get worse without a stated reason in the clip's comment.

---

## 2. Stance sheets

Bone values are the clip poses of the libraries (`common.js` of each hero): `hips.pos` is the pelvis offset from
standing (f, u, s), `hips.rot` and bones are degrees (src/char README §4), feet are sole points with toe yaw.

### 2.1 염무강 (`kael`) — 패도, the tyrant's saber

| pose | body | weapon | feet |
|---|---|---|---|
| **idle / ready** `kael.stance` (견도세: the saber resting on the right shoulder) | hips `[-0.03, -0.125, 0]` yaw −24; spine `[0,-5,-3]` chest `[1,-6,-2]` neck `[0,14,2]` head `[0,18,-3]` | right fist `[0.16, 1.355, 0.24]` before the right shoulder, blade `aim [-0.75, 0.66, 0.05]` sloping back over the pauldron, edge up; left hand on the grip (`grip: 1`) | L `[0.36, 0, -0.16]` yaw 12, R `[-0.36, 0, 0.20]` yaw −40: 0.72 m long, both flat |
| **guard** `kael.block` | hips `[-0.07, -0.18, 0]` yaw −30; spine `[0,-6,-9]` chest `[2,-8,-7]` head `[0,20,4]`; shoulders shrugged −4 | fist `[0.3, 1.0, 0.2]`, blade upright across the body `aim [0.26, 0.92, -0.3]`, the flat to the opponent, left palm braced on the flat (`gripAt: 'blade'`) | stance, rear foot 4 cm further back |
| **link** `kael.l1end` | hips `[0.08, -0.18, -0.02]` yaw +27, chest folded −10 | blade low on the left, the point a hand above the floor (`DIAG(180)`, fist height 0.84) | front flat, rear heel peeled (pitch −16) |
| **ceremony** `kael.vigil` | standing tall over the hilt, head hung −18 | blade planted point-down ahead, hands stacked | feet 0.3 apart |

Direction: the head stays **low and forward** (head `z` −3…−8 in every held pose, never above 0 outside reactions and
the victory). The weight sits low: no held pose with hips above −0.10. He *steps into* every cut and stamps before the
big ones; cuts finish low; recoveries are hauls (hips first, the blade dragged after, ≥ 7 f). Breathing is visible:
`breath` 1.3–1.5 in every loop.

### 2.2 설리화 (`iska`) — circles that never stop

| pose | body | weapons | feet |
|---|---|---|---|
| **ready** `iska.stance` | hips `[-0.03, -0.08, 0]` yaw −24; spine `[2,-4,-3]` chest `[0,-6,-2]` neck `[0,8,2]` head `[0,12,-4]` | both crescents crossed low before the hips, points down-forward: R fist `[0.22, 0.93, 0.12]` `aim [0.5,-0.66,-0.56]`, L fist `[0.27, 0.96, -0.06]` `aim [0.52,-0.62,0.58]`; never a grip (`grip: 0`), both fists curled | both on the balls (pitch −14, heels 2–3 cm up): L `[0.24, 0.02, -0.12]` yaw 14, R `[-0.25, 0.02, 0.14]` yaw −38 |
| **guard** `iska.block` | hips `[-0.06, -0.13, 0]` yaw −22, weight back | forearms crossed before the face, both blades standing up in an X | pitch −8 |
| **stillness** (to author: section 8) | 허보: hips `[-0.09, -0.10, 0]` (70 % on the rear leg), spine tall, head level | **one blade low, one high**: right as in the stance, left raised before the left shoulder, blade upright | front foot touching on its ball (pitch −24), rear foot flat |

Direction: one cut's follow-through is the next cut's wind-up, so a recovery never retraces the strike: the blade closes
its circle from the other side (see 6.2). Pivots turn on the ball with the ball fixed; in spins the head whips last
(hold the head on the opponent while the hips turn ≥ 90°, then snap it round in 2 f). The two blades trade roles (one
long and high, one short and low): that exchange is what turns her waist. Sleeves and hair trail: leave them room
(`clear` ≥ +8 around the head).

### 2.3 뇌진천 (`vorn`) — the spear's three fundamentals

| pose | body | weapon | feet |
|---|---|---|---|
| **idle / ready** `vorn.stance` (low guard) | hips `[-0.03, -0.10, 0]` yaw −30; spine `[0,-8,-3]` chest `[1,-8,-1]` neck `[0,12,2]` head `[0,16,-4]` | right fist `[0.32, 1.02, 0.16]` at the front of the right hip, spear `aim [0.86, -0.42, -0.27]` (point at knee height 1.6 m ahead), left hand on `choke` (0.26 behind); every clip keys `weaponR [0,0,-42]` and uses `sp()` | L `[0.35, 0, -0.15]` yaw 12, R `[-0.36, 0, 0.20]` yaw −48 |
| **guard** `vorn.guardPose` | hips `[-0.06, -0.22, 0]`, spine −14, chest −10: crouched behind the left shoulder | spear level at the opponent | stance |
| **ceremony** `vorn.sentinel` | upright, head level | spear planted upright beside the right foot | feet together |

Direction: 란 (outward parry circle), 나 (inward pressing circle), 찰 (thrust): the tip draws a small circle (5–15 cm)
while the whole body spirals behind it, then the thrust is one straight line from the rear heel through the hip and
shoulder to the point. The rear leg drives every lunge; the shaft slides through the forward hand (`grip` 1 → 0.3 → 0
on thrusts, back to 1 on the retract). The stance stays upright and **the hat brim stays level**: head `x` (roll) 0 and
|head `z`| ≤ 6 in every held pose. The spear is long: watch `flBl` in every whirl.

---

## 3. Review harness

Lab `src/labs/motion_dir.js`, batch tool `tools/motion.mjs`, quick numbers `tools/motion_eval.mjs`. One browser
session per batch.

```
node tools/motion.mjs kael kael.light1 kael.sweep --audit            # sheets + audit table -> shots/murim/motion/dir/
node tools/motion.mjs iska moves --frames 10 --audit --tag before    # a group: all | moves | states | ult | generic
node tools/motion.mjs vorn vorn.flash_jab --body mannequin --cols 7 --every 1 --cell 220x200 \
     --times 0,0.033,0.05,0.067,0.083,0.1,0.117,0.133,0.15,0.183,0.217,0.283,0.333,0.383    # frame-by-frame
node tools/motion.mjs knight generic --audit-only --json /tmp/x.json  # the generic set at its authored proportions
node tools/motion_eval.mjs "__ED.motion.aimTrace('kael','kael.light1')"   # per frame: wrist clamp R / L, tip height
```

A private copy for parallel work: `src/labs/motion_<label>.js` containing `import './motion_dir.js';`, then
`--lab motion_<label>`. Options: `tools/motion.mjs` header. Output: `<out>/<clip>[_<tag>].png`.

**3.1 Reading a sheet.** 960 × 574: eight side frames (the fight camera side) and four three-quarter frames (`q`),
evenly spaced, the first impact always one of them (shown on the first whole frame at or after it: the frame the
hit-stop holds). Frame labels carry the events crossed since the previous frame (`impact` red, `trailOn` / `trailOff`
blue, `step` green). The yellow line is the weapon-tip path (cyan: the second weapon): bright up to the frame shown,
dim for what is still to come, **one dot per 1/60 s**, so dot spacing is speed. The thin skeleton over the body
(right limbs orange, left blue) shows the legs through robes. `--body mannequin` swaps the design for colour-coded
limbs on the same rig data: use it to judge mechanics, the design to judge silhouette and costume. The footer is the
clip's audit row.

**3.2 Reading the audit table.** Section 1.8. `feet` counts every foot that stays within 1.5 cm of the floor as planted:
a deliberate pivot, a skating slide or a knocked foot shows as `drift`; name it in the clip comment. Lying clips use FK
legs (their feet are not "planted"). `clear` is measured at 240 Hz against the head and the costume keep-outs
(`KEEP_OUT` in the lab: 염무강 topknot, 설리화 hair-tail root, 뇌진천 hat brim and cone; a design may publish
`design.keepOut`): at 60 Hz a fast blade tunnels through a head between two frames and the check lies.

**3.3 Generic clips on a hero.** `node tools/motion.mjs kael game.getup` plays exactly what the game plays for him
(`game.getup@kael`: re-based on his stance; twin-blade variants for 설리화).

**3.4 The wrist check.** `aim` over ~30° means the hand key asks for a wrist no human has: the rig clamps it and the
blade is not where the key says, usually for one or two frames in the middle of a strike (a visible flip).
`aimTrace(hero, clip)` gives the frames. Fixes, in order: use the `up` a wrist can hold (염무강: `grip()` = the edge
continues the forearm; `H()` only where the keyed roll was measured); lower the hands so the blade continues the
forearms (염무강's cut lands at solar-plexus height, not at the shoulder with a level blade); add a steering key that
takes the blade through the vertical instead of asking for 200° in two frames. `__ED.motion.setGrip(hero, deg)` rebuilds
the mannequin with another `gripAngle` to measure what a design change would do.

**3.5 In the game.** `node tools/shot.mjs game --as mm-<label> --hash "training=kael,iska" …` with
`__ED.game.pose(i, clip, t)` / `forceMove`. The variant resolution of both fighters and what really plays: the
scenario of section 4.4.

---

## 4. Variant slots

Implemented in `src/game/clips.js` (resolution) and `src/game/actor.js` (selection). Additive: a fighter map without any
of them plays exactly as before.

**4.1 How a slot resolves.** (1) the fighter's map entry (`clips[slot]`: a name, `{ clip, speed, fade }` or an array of
those); (2) a registered clip named **`<fighter id>.<slot>`** (the convention: register `kael.hitLightHigh` and it is
live, no map edit); (3) the fighter's own clip of the parent slot (a hero's grips and stance stay the hero's);
(4) the generic variant; (5) the generic parent. Every clip a fighter can play, variants included, is compiled when its
actor is created.

| slot | plays when | parent | generic | driven |
|---|---|---|---|---|
| `hitLightHigh` / `hitLightMid` / `hitLightLow` | light hitstun, by the contact height: > 72 % / 40–72 % / < 40 % of the victim's height | `hitLight` | `game.hitLightHigh/Mid/Low` | restarted per hit, no fade, from 0.05 (the impact pose is held through the hit-stop) |
| `hitLightBack`, `hitHeavyBack` | the blow came from behind (`e.front === false`) | `hitLight`, `hitHeavy` | `game.hitLightBack`, `game.hitHeavyBack` | as above (heavy from 0.06) |
| `launchedProne` `fallProne` `downProne` `getupProne` `koProne` | the face-down chain: launched / knocked down by a blow from behind | `launched` `fall` `down` `getup` `ko` | `game.airRiseProne` `game.airFallProne` `game.downProne` `game.getupProne` `game.koProne` | loops; get-up progress-driven |
| `tech`, `techProne` | the fall was teched (rules `tech` event: the recovery roll away from the opponent) | `getup`, `tech` | `game.tech`, `game.techProne` | progress-driven over the get-up time |
| `guardHit`, `guardHitHeavy` | a blocked hit (heavy: level above light, or a long hit-stop); then back into `guard` | `guard`, `guardHit` | `game.guardHit`, `game.guardHitHeavy` | one-shot, optional |
| `idleFidget`, `idleFidget2` … `idleFidget6` | 4.5–8.5 still seconds in the fight phase; one at random (never the same twice running), then the idle loop; any state change cuts it | `idle` | `game.fidget1`, `game.fidget2` | one-shot, optional |
| `turn` | the facing flips while standing idle (the opponent crossed over): played in the new facing over the 0.1 s spin | `idle` | `game.turn` | one-shot, optional |
| `walkStopF`, `walkStopB` | walk → idle | `walkF`, `walkB` | none | one-shot, optional |
| `victory`, `victory2` … `victory6` | round won: one per round at random | — | `game.victory`, `game.victory2` | plays once, holds |

"Optional" slots play nothing extra unless a clip exists for that very slot (own or generic for a fallback fighter).
Selection is deterministic (`ctx.rng`).

**4.2 Without variant clips** a hero still reads direction: the plain reaction clip plays and the body takes the
difference as a physical flinch where the blow landed (high: the head goes first; mid: the chest folds forward as the
hips are shoved back; low: the front thigh is knocked; all reversed for a blow from behind), and every blocked hit adds
a flinch scaled by its hit-stop (0…0.45 of a heavy flinch).

**4.3 Authoring rules for variants.** Reaction clips start on the hero's stance pose and put the impact pose at 0.05
(light) / 0.06 (heavy); durations as the existing ones. `tech*` and `getup*` clips are sampled by progress over 0.45 s
and must start on the matching lying pose and end on the stance. A `turn` clip starts *already facing the new way*
with the chest and weapon still behind (hips yaw ≈ −60) and settles. Fidgets start and end on the idle's first frame.
`guardHit*` start and end on the guard pose and keep its `gripAt`.

**4.4 Checking it.** `P1=kael P2=iska node tools/shot.mjs game --as mm-<label> --size 640x360 --hash q=low --scenario
tools/motion_variants.mjs` prints, for both fighters of a training match, the clip of every slot and the clip / state
sequence that really plays for light, heavy, launch, crumple and knockdown hits from the front and from behind, blocked
hits, 14 s of idling and a KO.

---

## 5. The generic set (`game.*`, `src/game/clips.js`)

Neutral style on the knight's stance, two-handed weapon. Heroes override slot by slot; where they do not, the game plays
the clip **re-based on the hero's own stance** (`<clip>@<id>`: every key that started from the knight's stance pose
starts from `<id>.stance`), so a fallback get-up ends with the saber on 염무강's shoulder instead of swinging there
afterwards.

| clip | beats |
|---|---|
| `game.hitLight` (+ `High` `Mid` `Low` `Back`) | impact pose at 0.05 (the head first) → the torso and hips catch up at 0.10 while the head is already returning → rebound past the stance at 0.20 → settle. High: head whip + shoulders; mid: folds around the blow; low: the front foot is knocked back 11 cm (a deliberate skid) and re-planted; back: arch, then a stumbling step forward |
| `game.hitHeavy`, `game.hitHeavyBack` | head and blade thrown back → driven over the rear leg → the rear foot catches it (0.24) → the front foot is pulled after (0.50) → braced lean back into the guard; root −0.24 m. Back: arched, pitched over the front foot, two stumbling steps, root +0.30 m |
| `game.crumple` | rigid jolt around the blow → the point drops to the floor → the rear knee gives, he sits back on the heel → topples onto his back, the legs shooting out (ends on `game.downPose`) |
| `game.guardbreak` | guard smashed open (blade and left arm flung apart and **out**, clear of the head) → two reeling steps → the guard hauled back together |
| `game.guardHit`, `game.guardHitHeavy` | the blade is driven toward the face, the elbows give, rebound; heavy: the rear foot gives 9 cm |
| `game.airRise` / `airFall` (+ `Prone`) | arched and trailing / tipping to horizontal; prone: chest first, then arms forward to break the fall |
| `game.down`, `game.koDown`, `game.downProne`, `game.koProne` | lying loops; hands and blade in root space on the floor (a chest-space hand rides the breathing and swings the blade 20 cm); prone legs FK |
| `game.getup`, `game.getupProne` | from the back: rocks forward, feet under, rises; from the face: a pike (hips first, hands planted), the front foot steps through, rises |
| `game.tech`, `game.techProne` | backward roll over the shoulders / forward shoulder roll, the blade held out to the side, landing crouch, up |
| `game.dash`, `game.backstep`, `game.dodge` | load (2 f) → drive with the blade couched at the hip, its point on the opponent → the rear foot dragged in; backstep: hips first, the rear foot lands before the front; dodge: the head leaves the line first, overshoot on the way back |
| `game.locked` | reeling on the rear leg, guard hanging open, the head lolling with each sway (three phases) |
| `game.turn`, `game.fidget1`, `game.fidget2` | turn-around settle; neck and shoulder roll with a re-grip; weight shift with a front-foot re-plant |
| `game.victory`, `game.victory2`, `game.defeat` | a flick of the blade stopped dead, then stillness, feet drawn together; the sword salute (blade upright, left palm over the right fist, a short bow); the rear knee and the blade as a strut, the left hand on the front knee |

Before → after on the knight (`shots/murim/motion/dir/before/generic`, `…/generic`; table in the final report):
the blade no longer sinks into the floor in `crumple` (801 → 0 mm), `dash` (252 → 0), `getup` (496 → 0), `down`
(197 → 0), `koDown` (94 → 0), `defeat` (544 → 0); `guardbreak` clears the head (−1.3 → +27 cm); the wrist clamp is gone
from `dash` (174° → 0), `getup` (92° → 0), `crumple`, `defeat`. Known residuals: 1–2 transit frames of `getupProne` /
`techProne` with a knee or fist ≤ 7 cm under the floor; `feet` reports the knocked / pulled feet of `hitLightLow`,
`hitHeavy` and the rolls as drift (deliberate).

---

## 6. Worked examples

Sheets: `shots/murim/motion/dir/ref/<clip>_before_hi.png` and `_after_hi.png` (14 frames, mannequin, side + three-quarter).

### 6.1 `kael.light1` 재가르기 (0.42 s, impact 0.14)

Was: a clean arc with no weight. The body rode at one height, the front foot never moved, the cut "landed" with the
hands at shoulder height and a level blade (a wrist clamp of 22° through the whole strike), the follow-through buried
15 cm of the blade in the floor, and four arm-through-chest intersections in the recovery.

How:
1. **Sheet first.** Frame-by-frame mannequin sheet + `aimTrace`: the clamp started at the over-the-top key and lasted
   to the end of the follow-through. Root cause: a level blade from high hands. The fix is martial, not numeric:
   the cut lands with the hands at the solar plexus and the point at the opponent's chest (`H([0.6, 1.0, 0.02], DIAG(124))`).
2. **Beats on frames** (comment block above the clip): 0–3 sink + coil (hips −0.155, yaw −38, `shoulderR` Y −12), 3–5
   hang (hips already back to −26 while the blade travels on to `DIAG(6)`), 5–8 the cut (115° in 3 frames, steering key
   at 0.117 over the top), 8–10 kime (`outQuad`, 6° of travel), 10–14 follow-through (`inQuad`), 14–18 a beat of weight,
   18–25 the haul (hips first).
3. **The stamp.** The front foot unweights with the coil (heel up 4.5 cm, pitch −9), slams down at 0.125 (`inQuad`, a
   `step` event one frame before the impact), and the hips drop 4 cm into it.
4. **The link pose.** `kael.l1end` stops the point a hand above the floor (`DIAG(180)`): light2 still starts from it.
5. **Audit.** Before → after: `flBl` 154 → 0 mm, `isx` 4 → 0, `lim` 2 → 1, `aim` 22.4 → 18.5°, `knk` 9 → 2, `pop` 44 → 37,
   `ovr` 7 → 4; `tip` 117 → 121 m/s (the cut is 3 % faster: deliberate), `clear` 12.8 → 12.6 cm (the higher coil).

### 6.2 `iska.rime_flick` 서리 긋기 (0.30 s, impact 0.09)

Was: the right blade cut while the left hung at the hip; the recovery ran the strike backwards; the blade grazed the
head (`clear` −4.2 cm) on the way; the wrist was asked for 144°.

How:
1. **Two blades, two jobs.** While the right crescent goes over the shoulder the left comes up as a cover
   (`FLICK_COVER`), and as the right cuts the left is pulled back to the hip, point on the opponent (`FLICK_PULL`):
   one long and high, one short and low. Both poses were *scanned* for the wrist (`motion_eval` with a loop over `aim`
   / `up` candidates printing `diag.aimErr`): 0° of clamp. The first try stood the left blade up at the hip and cut the
   hair tail (`clear` −6 cm): the numbers caught it.
2. **A steering key** at 0.025 turns the blade up through the vertical on its way to the cock (without it: 150° of wrist
   in one frame, a flip).
3. **The pivot.** The rear foot turns on its ball as the hips come through (`pivot()`: yaw −38 → −16, heel swung out,
   the ball pad fixed).
4. **Kime and the circle.** Two frames at full reach (`outQuad`), then the crescent rolls on down and across (`inQuad`)
   and *closes the circle from below*: it rises into the low guard from underneath while the body floats 1.5 cm above
   the stance and sinks.
5. **Audit.** `clear` −4.2 → +14.4 cm, `bld` 1 → 0, `isx` 3 → 1, `aim` 144 → 41° (the remaining 41° is the stance pose
   itself: section 9.1), `knk` 2 → 1; `pop` 40 → 66 (the kime and the eased follow-through are deliberate velocity
   steps, counted on each arm joint), `flFt` 2 → 4 mm (the pivoting foot; inside the 5 mm line).

### 6.3 `vorn.flash_jab` 전광자 (0.38 s, impact 0.11)

Was: correct and stiff: a straight draw-back, a thrust, a straight return down the same path.

How:
1. **나 before 찰.** In the draw-back the point rides a small inward circle: an **aim-only key** at 0.025
   (`aimOnly([0.9, -0.34, -0.3])`: the fist keeps its own path, only the point dips and presses in), then up onto the
   line at 0.05. The tip circles, the body spirals behind it.
2. **Hips before the arm.** At 0.08 the hips are 26° through while the fist has only left the hip.
3. **The line.** Impact: rear heel, hip, shoulder, fist and point on one line; `shoulderR` Y +12; the left hand lets
   the haft run (`grip` 0.7 → 0.3 → 0) and snaps to the hip (the counter-pull squares the shoulders). The shuffle of
   the front foot lands at 0.095, a frame before the point.
4. **The way back is not the way out.** The spear is drawn back *along its own line* first (0.20: still level, point
   on the opponent), then lowers, the point dipping a hand under the guard line at 0.335 and rising into it.
5. **Restraint.** A first version added more hip, a locked rear leg and a bigger shoulder: the audit showed three new
   over-speed joints and two new limit hits for nothing visible. Taken back out.
6. **Audit.** `lim` 2 → 2, `isx` 4 → 4, `drift` 0.9 → 0.9, `aim` 0.1 → 0.1; `knk` 3 → 4 (the tip circle is a deliberate
   change of direction), `tip` 19 → 27.5 m/s (faster thrust and retract), `clear` 103 → 100 cm, `pop` 43 → 46.

---

## 7. Per-clip review (baseline of this pass)

Sheets: `shots/murim/motion/dir/before/<hero>/`. Numbers: the baseline audit (cm / mm / deg as in 1.8).
P1 = visible in every fight, P2 = skill / ultimate, P3 = ceremony. The sheets still show the old armour: re-check
`clear` and the silhouettes when the robes, hats and hair land.

### 7.1 염무강 `kael` (29 clips)

| clip | P | what is wrong / weak | fix |
|---|---|---|---|
| `kael.idle` | P1 | reads as a frozen pose: 1.5 cm of hip travel, no head, no hands | breath 1.5 with a visible chest / shoulder rise, weight roll ±4 cm, head sinks and lifts 4°, a re-grip of the left hand; add `idleFidget*` (section 8) |
| `kael.walkF` | P1 | heavy gait is right, the torso is a statue; the feet glide 10 cm into each plant | hips yaw ±6 with the stride, shoulders counter, the saber bobs on the shoulder a frame late; `inQuad` plants |
| `kael.walkB` | P1 | as walkF; 17 cm glide into the plant | same; rear foot reaches, weight follows |
| `kael.dash` | P1 | a hop with the rear leg kicked up, not a shoulder rush; front ankle +34° over its range; wrist clamp 82° | lead with the left shoulder (chest yaw +20, pitch −20), two driving steps that stay under the hips, blade tight on the shoulder |
| `kael.backstep` | P1 | the blade whips through the head (`clear` −3.4 cm, clamp 179°, blade in the torso 16 cm) | keep the blade on the shoulder plane; hips first, rear foot lands first |
| `kael.dodge` | P1 | a straight drop; balance outside the feet 22 % of the time | the head leaves the line first, weight onto the rear leg, overshoot on the return |
| `kael.guard` | P1 | fine pose, no life, no reaction to hits | breath; author `guardHit` / `guardHitHeavy` |
| `kael.light1` | — | reworked (6.1) | — |
| `kael.light2` | P1 | its own wind-up sinks the blade 44 cm into the floor (`DIAG(222)` at 0.06); the rise is arm-led, no kime | wind-up at `DIAG(205)` with the fist higher; hips drive the rise (yaw +36 → −38), 2 f hold at the top, step lands before the impact |
| `kael.light3` | P1 | good overhead arc; forearm pop of 7165 at 0.175; no stamp; the chop does not fold the body | stamp at 0.22, chest folds −14 at the bite, hold 3 f, then the haul |
| `kael.sweep` | P1 | 300° of arc around feet that never move: an arm swing around a fixed base; left upper arm twisted +23° over its range; head / topknot clearance 12 cm (verified at 240 Hz) but the path runs behind the head: re-check with the mane | pivot: the rear foot steps through on the swing, hips carry 120° of it; raise the arc 10 cm behind the head |
| `kael.lunge` | P1 | rear thigh +39° over its range; the feet glide 19 cm into the landing; left forearm 10 cm inside the chest | shorter rear-leg extension, land with `inQuad` and a 2 f hold, left elbow out |
| `kael.vent` | P1 | reads well; no sink before the rise | 3 f sink (hips −0.22) before the split |
| `kael.crescent` | P2 | the blade grazes the head in the recovery (`clear` −0.3 cm), clamp 64° | recover in front of the body; 운기 beat in the drag (breath, the left palm pressing the flat) |
| `kael.eruption` | P2 | right arm 40° across its range, arm 8.6 cm inside the chest | raise with both elbows out, the plunge driven by a drop of the hips (−0.25) and a stamp |
| `kael.bulwark` | P2 | left-hand pop 7267 at the plant, clamp 75° | plant in two beats (set the point, then drop the weight) |
| `kael.bulwark_burst` | P2 | the blade is ripped up through the torso (10.7 cm), clamp 162° | rip it up outside the right hip |
| `kael.pyre` | P2 | 17 kinks, 105 pops, 11 over-speed joints, rear ankle +29° | re-space the lift and the leap around three held poses |
| `kael.ult.cuts` | P2 | right arm 15 cm inside the chest between cuts | elbows out; each cut from the previous follow-through |
| `kael.ult.hurl` | P2 | forearm 17.6 cm inside the torso, left thigh +28° | — |
| `kael.ult.leapAfter` | P2 | fine | — |
| `kael.ult.spin` | P2 | the blade passes through the head (`clear` −7.7 cm), clamp 180°, left arm twist +44° | blade at arm's length *above* shoulder height through the turn |
| `kael.ult.meteor` | P2 | landing slides 34 cm | plant in origin space on the impact |
| `kael.ult.rise` | P2 | planted foot drifts 4 cm | — |
| `kael.intro` | P3 | no salute; the wrench flips the blade (clamp 177°); the planted blade grazes the left foot | 포권례 over the planted hilt, then the wrench in two beats |
| `kael.victory` | P3 | forearms cross 9.5 cm; clamp 179° at the plant | a blade flick (one sharp diagonal, stopped dead) before the plant; add `victory2` |
| `kael.defeat` | P3 | as he kneels the planted blade sinks 84 cm into the floor | the hands slide down the grip / the blade tilts into a strut |
| `kael.hitLight` | P1 | a small generic shake, front only | variants by height and side (section 8) |
| `kael.hitHeavy` | P1 | good stagger, front only | `hitHeavyBack` |

Fallbacks he still plays from the generic set (re-based on his stance): `crumple` `launched` `fall` `down` `getup`
`tech` `ko` `locked` `guardBreak` and every prone / tech variant.

### 7.2 설리화 `iska` (38 clips)

Systemic: **the wrist clamp**. Her stance alone clamps 49° / 40° (the crescents are not where the keys say), most moves
130–180° for a frame or two. Root cause and the design-side fix: section 9.1. Until then every hand key needs an `up`
a wrist can hold (scan it: 6.2).

| clip | P | what is wrong / weak | fix |
|---|---|---|---|
| `iska.idle` | P1 | a held pose; both blades low | settle into the 허보 stillness (2.2) after 0.6 s; breath, a wrist roll of the low blade, a slow head turn |
| `iska.guard` | P1 | fine; right arm 8 cm inside the chest | elbows 5 cm further out; `guardHit*` |
| `iska.walkF` / `walkB` | P1 | the feet glide 35 / 27 cm into each plant, 7 mm under the floor; torso static | 경공: the toes skim, the plant is still: land `inQuad`; hips lead, sleeves need a shoulder counter-swing |
| `iska.dash` | P1 | clamp 174°, forearm 14 cm inside the torso | blades swept back with the edges out |
| `iska.backstep` | P1 | reads | — |
| `iska.dodge` | P1 | the feet slide 22 cm | plant both; sway from the waist |
| `iska.roll` | P1 | both blades inside the body while tucked (16–20 cm), through the head (`clear` −7 cm) | blades held out along the forearms (reverse grip) through the turn |
| `iska.rime_flick` | — | reworked (6.2) | — |
| `iska.twin_moons` | P1 | good flow; left blade through the head region (`clear` −2.6), clamp 150° | the cover / pull exchange of 6.2 for both cuts; steering keys through the vertical |
| `iska.star_fan` | P1 | the head turns with the body; feet slide 42 cm; hand pop 22617 | spot the head (hold, then whip in 2 f); pivot on the ball |
| `iska.glacier_pirouette` | P1 | right arm 18.5 cm inside the chest, blade in the torso 6 cm | arms on a wider circle; head whip; the landing is good |
| `iska.frostline_step` | P1 | right arm crosses 77° past its range (through the chest) | cut from the outside line |
| `iska.rising_crescent` | P1 | blade in the torso 8.5 cm in the scoop; rear ankle +24° | scoop outside the knees |
| `iska.starshard_volley` | P2 | reads; blade touches the head at 0.08 | — |
| `iska.crystal_procession` | P2 | feet 10 mm under the floor in the kneel; blades through the head on the way down (`clear` −4.8) | — |
| `iska.moonlit_afterimage` | P2 | reads | — |
| `iska.frozen_star` | P2 | left arm 80° behind its range at 0.6; 12 kinks | re-space around the `point` hold |
| `iska.ult.crystal` | P2 | fine | — |
| `iska.ult.orbit` | P2 | the worst: 193 pops, blades through the head (`clear` −12.4) and torso (12.7 cm), left arm twist +87° | six cuts as three circles of two; one blade always covers |
| `iska.ult.leap` | P2 | left arm twist +98°, blade in the torso 12.5 cm | — |
| `iska.ult.constellation` | P2 | clean | — |
| `iska.ult.starfall` | P2 | 27 kinks, 128 pops, blades through the head (`clear` −10) | flings from the shoulder line outward |
| `iska.ult.land` | P2 | feet slide 35 cm at the landing | origin-space plant |
| `iska.ult.frostWave` / `blendBack` | P2 | right arm 20 cm inside the chest | — |
| `iska.intro` | P3 | the blades pass through the head when they fan (`clear` −10.4), blade in the torso 15.6 cm; no salute | rise, 포권례 with the blades reversed along the forearms, then the fan outside the shoulders |
| `iska.victory` | P3 | reads; ends with the blade raised | flick first, then stillness (one low, one high); `victory2` |
| `iska.defeat` | P3 | the feet slide 19 cm, 11 mm under the floor | plant; the crescents laid down as she kneels |
| `iska.hitLight` / `hitHeavy` | P1 | front only; heavy slides 21 cm and the blade crosses the head | variants (section 8); real steps |
| `iska.guardBreak` | P1 | feet slide 20 cm, blade through the head (`clear` −7.7) | blades knocked apart *outward* |
| `iska.crumple` | P1 | ends kneeling; the knockdown that follows pops to lying in 4 frames | add the fall onto the back (end on `iska.downPose`) |
| `iska.getup` | P1 | rear ankle +42°; FK feet | — |
| `iska.launched` `fall` `down` `ko` | P1 | fine; left shoulder +12° over its range | prone chain missing |

### 7.3 뇌진천 `vorn` (41 clips)

The cleanest library (wrist clamp ≈ 0 everywhere but the whirls). The weakness is restraint to the point of stiffness:
tips travel straight out and straight back, and the torso rarely spirals.

| clip | P | what is wrong / weak | fix |
|---|---|---|---|
| `vorn.idle` | P1 | a held pose | breath, the point drawing a slow 3 cm circle, a re-grip of the rear hand, the hat level |
| `vorn.guard` | P1 | reads (spear wall) | `guardHit*`: the haft takes it, the rear foot gives |
| `vorn.walkF` / `walkB` | P1 | lunging strides that glide 20 / 15 cm into the plant; torso static | shorter, precise steps (the brief: precise stepping), the point stays on the opponent while the hips move |
| `vorn.dash` | P1 | upright shuffle; rear foot drifts 15 cm | drive from the rear leg, spear couched |
| `vorn.backstep` / `dodge` | P1 | read; dodge drifts 10 cm | — |
| `vorn.flash_jab` | — | reworked (6.3) | — |
| `vorn.haft_spin` | P1 | the whirl puts 27 cm of spear head into the floor; clamp 168°; tip at 182 m/s (a teleport, not a whirl); hard to read | whirl in the vertical plane beside the body with the hands at chest height; three readable quarters |
| `vorn.thunder_pierce` | P1 | the best of the set; left arm twist +25° | a tip circle (란) in the lunge |
| `vorn.gale_sweep` | P1 | reads; rear thigh twist +21°, 10 intersections | pivot the rear foot with the sweep |
| `vorn.lightning_charge` | P1 | reads; the skid stop slides 1.37 m (by design), rear thigh +42° | shorten the rear-leg line |
| `vorn.skyward_lance` | P1 | reads | hold 3 f at the top |
| `vorn.thunder_javelin` | P2 | 11 over-speed joints, clamp 62° | — |
| `vorn.stormfall` | P2 | reads; 운기 beat missing | spear drawn across the body with a breath before the raise |
| `vorn.arc_step` | P2 | reads | — |
| `vorn.ninefold_storm` | P2 | 139 pops, 17 kinks, front ankle +58° at 0.92 | — |
| `vorn.ult.lift` `hurl` `throw` `bolts` `storm` `land` | P2 | read | — |
| `vorn.ult.leap` | P2 | foot drifts 36 cm before take-off, left arm twist +84° | — |
| `vorn.ult.catch` | P2 | clamp 139°, right arm 60° behind its range | — |
| `vorn.ult.slam` | P2 | right arm 77° across its range, clamp 180° | — |
| `vorn.ult.twirl` | P2 | clamp 133°, spear 24 cm from the hat cone | — |
| `vorn.intro` | P3 | no salute | 포권례 with the spear in the crook of the arm, then the 기수식 |
| `vorn.victory` | P3 | reads | tassel flick before the plant; `victory2` |
| `vorn.defeat` | P3 | the idiom is right (knee + spear) ; feet 14 mm under the floor | — |
| `vorn.hitLight` / `hitHeavy` | P1 | front only | variants (section 8) |
| `vorn.guardBreak` `crumple` `launched` `fall` `down` `getup` `tech` `ko` `locked` | P1 | derived from the generic set at module load (`states.js`): they changed with the generic rework of this pass (re-audited: final report) | own prone chain and a real `tech` (currently the get-up) |

---

## 8. New clips per hero

Register them under these names (`<id>.<slot>`): they go live without a map edit.

| slot | 염무강 `kael` | 설리화 `iska` | 뇌진천 `vorn` |
|---|---|---|---|
| `hitLightHigh` / `Mid` / `Low` / `Back`, `hitHeavyBack` | the saber stays on the shoulder; the head snaps, the bulk barely moves | sleeves and hair carry the whip; light on the feet | the haft takes part of it; the hat stays level within 10° |
| `guardHit`, `guardHitHeavy` | braced: a 2 cm give of the rear knee | the X is driven toward the face | the haft bows, the rear foot gives |
| `idleFidget`, `idleFidget2` | rolls the right shoulder under the saber; shifts his feet | turns the low wrist in a slow circle; the head follows a falling leaf | re-grips the rear hand; touches the hat brim |
| `turn` | a heavy two-beat turn, the saber swinging round last | a spin on the ball, the hair arriving last | a crossed step, the point never leaves the line |
| `walkStopF` / `walkStopB` | the saber's mass carries one beat past the stop | toes skim to rest | a precise closing step |
| `victory2` | 포권례 over the shouldered saber | reversed blades, a bow of the head | the spear grounded, a salute with the left fist |
| `tech`, `techProne` | a heavy shoulder roll | a one-handed spring | a roll along the spear |
| `launchedProne` `fallProne` `downProne` `getupProne` `koProne` | (generic chain plays) | to author | to author |
| own versions of generic fallbacks | `guardBreak` `crumple` `launched` `fall` `down` `getup` `ko` `locked` in the shoulder-rest grip | `locked` | — |
| stillness | — | the 허보 idle (2.2) | — |
| ceremony | intro with 포권례 | intro with 포권례 | intro with 포권례 |

---

## 9. Rig and design findings (for the rig / costume teams; nothing here was changed by this pass)

1. **설리화's grip.** The design sets no `gripAngle`: the crescents sit square across the fist and her keys ask for a
   wrist beyond the human range in almost every pose. Measured wrist clamp (deg, right / left) with the design as it is
   → with `gripAngle` 40: idle 48.8 / 39.7 → 2.5 / 0.1; guard 0.1 / 13.3 → 0.1 / 0.1; walkF 65 / 66 → 16 / 1.4;
   rime_flick 144 / 87 → 66 / 21 (before its rework). Recommendation: `gripAngle: 40` in `iska/design.js`, then re-audit
   every clip. 염무강: tested 25 / 40, it trades light1 for crescent and guard: keep 0, fix per clip.
2. **Keep-outs.** The lab's `KEEP_OUT` volumes (topknot, hair-tail root, hat brim and cone) are estimates from
   `MURIM.md`; the costume team should publish `design.keepOut` (`[name, bone, a, b, radius]`) with the real hats and hair.
3. **Chest-space hands ride the breathing.** A lying pose with a chest-space weapon hand swings the blade 20 cm per
   breath (`breath` 1.4 on the down loops). The generic set now keys lying hands in root space; hero lying poses
   derived from the old generic ones should follow.
4. **Floor-level IK feet fight the automatic pelvis drop**: a foot target on the floor behind a lying body either bends
   the knee into the floor (short reach) or sinks the hips (long reach). Lying poses use FK legs.
5. **`qa.feet` cannot tell a pivot from a slide** (section 3.2): judge on the sheet.
6. **Generic → hero stance.** Fallback clips are re-based on `<id>.stance` when the hero's library defines that pose
   (`stanceVariant` in `src/game/clips.js`): keep that pose name in every hero library. Guard poses are not re-based
   (another guard's blade roll swept 염무강's saber through his head on the first key of the guard break).

---

## 10. Checklist before a clip is committed

1. Frame-by-frame mannequin sheet + design sheet read; the beats written as a frame list in the clip comment.
2. Hips lead (≥ 12° at the hang), kime held, the way back is not the way out.
3. `aimTrace` under 30° through the strike; `clear` ≥ +5 cm; `flBl` 0 (or the stated bite).
4. Feet: `drift` ≤ 1 cm or the pivot / slide named; `step` events on plants; stamps one frame before the impact.
5. Audit row before / after in the clip comment; nothing worse without a reason.
6. Duration, impact time, `trailOn` / `trailOff`, root keys unchanged (`git diff` shows no change in `events` times
   other than added `step`s).
