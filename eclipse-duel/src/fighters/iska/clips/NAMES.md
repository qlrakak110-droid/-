# ISKA 이스카 — clip names (src/fighters/iska/clips/)

Owner: ISKA lead animator. The choreographer reads this file. Every clip registers on import of
`src/fighters/iska/clips/index.js`, which also exports the ready-made state -> clip map:

```js
import { clips } from './clips/index.js';      // registers every iska.* clip and gives the map for index.js
export default { id: 'iska', design, def, clips, present };
```

All 38 clips below are registered (`hasClip` is true for every name). Files: `common.js` (stance, guard pose,
helpers), `locomotion.js`, `moves.js`, `ult.js`, `ceremony.js` (ceremony + hit / air / lying reactions).

## Moves (sampled at the rules' move time; duration = move duration, `impact` event at the first active frame)

The `clips` map gives each move `{ clip, hit }` with `hit` = the first active frame, so the retime is the identity
for the current frame data and keeps the impact on the first active frame if the data changes.

| clip | move / slot | dur | impact (s) | in-clip events / notes |
|---|---|--:|--:|---|
| `iska.rime_flick` | light1 | 0.30 | 0.09 | right forehand diagonal (cock .05, over .07, hit .09, follow-through .14) |
| `iska.twin_moons` | light2 | 0.36 | 0.10 | left cut .10 (+ lead step), `cut` .17 right cut, trail foot drags up .26-.30 |
| `iska.star_fan` | light3 | 0.56 | 0.16 | left-turning pirouette with both blades out (cut .16 front + back), `cut` .25 = both blades fan open |
| `iska.glacier_pirouette` | heavy | 0.78 | 0.22 | two revolutions on the lead foot: right blade .22, left .30, low frost-ring pass .38; wide low landing .44 |
| `iska.frostline_step` | f+heavy | 0.64 | 0.18 | low skating slide (feet glide with the root), right cut .18, left `cut` .23, braking skid .40 |
| `iska.rising_crescent` | d+heavy | 0.62 | 0.16 | step in, two-blade scoop .13-.16, backflip (hips pitch 0 -> 360 over .16-.50), crouched landing .50 |
| `iska.starshard_volley` | skill1 | 0.62 | 0.18 | blades crossed .05, flings: right high .18, left mid `cut` .24, right low lunge `cut` .30 |
| `iska.crystal_procession` | skill2 | 0.78 | 0.25 | `stab` .12 both blades into the floor in a kneel, forward drive at release .25, rises .56-.78 |
| `iska.moonlit_afterimage` | skill3 | 0.70 | 0.30 | recoil .03 (blink), coiled with both blades high at reappear .24 (step key), X cut .30 |
| `iska.frozen_star` | ult opener | 1.45 | 0.75 | head bowed 0, rises + opens .14, blade twirls .19-.29, `point` .35 (right blade at the rune, held through the freeze), blades overhead .66, snap .75 (crouch, blades crossed down); whiff recovery to 1.45 |

## Locomotion / states

| clip | slot | notes |
|---|---|---|
| `iska.idle` | idle, recovery | loop 2.4 s: on the balls of the feet, blades crossed low, breathing, weight drifting |
| `iska.walkF` / `iska.walkB` | walkF / walkB | loop, root speed exactly 3.1 / 2.4 m/s (playback speed 1), gliding chasse, planted feet |
| `iska.dash` | dash | 0.24 s skating glide, blades swept back |
| `iska.backstep` | backstep | 0.30 s hop back, blades drawn across the chest |
| `iska.dodge` | dodge | 0.38 s deep sway away (in place) |
| `iska.roll` | roll | 0.38 s low spinning glide (one turn toward the camera, blades tucked), lands in the stance |
| `iska.guard` | guard / blockstun | loop: blades crossed in an X before the face (pose `iska.block`) |
| `iska.hitLight` / `iska.hitHeavy` | hitLight / hitHeavy | flinch (impact pose at .05 / .06, as the game starts them), heavy staggers a step back |
| `iska.guardBreak` | guardBreak | 0.7 s progress-driven: blades knocked apart, chest thrown open, stagger step, hunched open guard |
| `iska.getup` | getup, tech | 0.45 s progress-driven: from lying on the back (pose `iska.downPose` = the generic down pose with both crescents) onto one knee, springs up into `iska.stance` |
| `iska.crumple` | crumple | 0.9 s progress-driven: rigid frozen jolt, knees give way into a kneel, head bowed |
| `iska.intro` | intro | 2.4 s: kneeling prayer with crossed blades, rises 1.2, fans the blades open 1.6, settles in the stance |
| `iska.victory` | victory | 2.0 s: frost flick, right crescent raised to the sky (held) |
| `iska.defeat` | defeat | 1.6 s: staggers, sinks to one knee, blades on the floor, head bowed (held) |
| `iska.launched` / `iska.fall` | launched / fall | loops 0.8 s: arched rising / tipping back to horizontal; FK legs, both crescents trailing along the body |
| `iska.down` / `iska.ko` | down / ko | loops: lying on the back (`iska.downPose`), crescents flat beside her; KO is still, head turned away |

Not authored (the generic twin-blade fallback plays): `locked` (Iska as the victim of an opponent's lock).

Poses: `iska.stance` (every clip starts / ends here), `iska.block`, `iska.downPose`, `iska.ult.snapPose` (= frozen_star at .75).

## Ultimate lock beats (`h.play` during the lock; lock clock = seconds from the trigger, BALANCE.md section 9)

| clip | play at lock t | dur | in-clip events | action |
|---|--:|--:|---|---|
| `iska.ult.crystal` | 0.01 | 0.44 | — | from the snap pose: rises, blades spun out, coils for the dash; ends on the orbit start |
| `iska.ult.orbit` (play with `fade: 0.03`; started at slash1 = 0.45 every cut lands 2 frames after its tick) | **0.42** | 1.23 | `impact` 0.03, `cut` 0.03 / 0.23 / 0.43 / 0.63 / 0.83 / 1.03 (R L R L R L) | six alternating cuts = ticks slash1..slash6 at lock 0.45 ... 1.45 when started at 0.42; ends crouched (leap start) |
| `iska.ult.leap` | 1.65 | 0.30 | `takeoff` 0.12 | crouch and spring; pair with `h.offset([f, ~4.5], 0.6, 'outCubic')` from takeoff (lock 1.77) |
| `iska.ult.constellation` | 1.95 | 0.70 | — | airborne, arched toward the eclipse, blades drawing star lines (ends with both raised) |
| `iska.ult.starfall` | 2.65 | 1.00 | `fling` 0.001 + 0.08 k (12, R/L alternating) | pitched down over the crystal, a blade fling per lance (lance1..12) |
| `iska.ult.land` | **3.53** | 0.62 | `impact` 0.12 (= shatter at lock 3.65) | descends with blades overhead, lands in a kneel driving both blades down crossed; offset u should reach 0 at lock 3.65 |
| `iska.ult.frostWave` | 4.15 | 0.50 | — | rises, both blades swept wide |
| `iska.ult.blendBack` | 4.65 | 0.75 | `flick` 0.24 | gathers, flicks the frost off both blades, back into `iska.stance` |


Root: every lock clip keeps the root still; leaps / descents / dashes are `h.offset` moves of the choreographer.
