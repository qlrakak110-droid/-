# ISKA 이스카 — clip names (src/fighters/iska/clips/)

Owner: ISKA lead animator. The choreographer reads this file. Every clip registers on import of
`src/fighters/iska/clips/index.js`, which also exports the ready-made state -> clip map:

```js
import { clips } from './clips/index.js';      // registers every iska.* clip and gives the map for index.js
export default { id: 'iska', design, def, clips, present };
```

Status legend: **done** = authored and reviewed in contact sheets; *planned* = name reserved, not yet registered
(check `hasClip(name)` before `h.play`).

## Moves (sampled at the rules' move time; duration = move duration, `impact` event at the first active frame)

| clip | move / slot | dur | impact (s) | notes |
|---|---|--:|--:|---|
| `iska.rime_flick` | light1 | 0.30 | 0.09 | right-hand flick, outward diagonal; ends in `iska.stance` |
| `iska.twin_moons` | light2 | 0.36 | 0.10 | left cut 0.10, right cut 0.17 |
| `iska.star_fan` | light3 | 0.56 | 0.16 | spin cut 0.16, second (shards) cut 0.25 |
| `iska.glacier_pirouette` | heavy | 0.78 | 0.22 | three revolutions 0.22 / 0.30 / 0.38 (frost ring) |
| `iska.frostline_step` | f+heavy | 0.64 | 0.18 | low ice slide, scissor cuts 0.18-0.34, stop 0.40 |
| `iska.rising_crescent` | d+heavy | 0.62 | 0.16 | step-in, backflip launcher, land 0.50 |
| `iska.starshard_volley` | skill1 | 0.62 | 0.18 | crossed blades, three flings 0.18 / 0.24 / 0.30 |
| `iska.crystal_procession` | skill2 | 0.78 | 0.12 | both blades stabbed into the floor at 0.12 (`stab`), release 0.25 |
| `iska.moonlit_afterimage` | skill3 | 0.70 | 0.30 | blink back 0.02-0.12, reappear 0.24, cut 0.30 |
| `iska.frozen_star` | ult opener | 1.45 | 0.75 | super-freeze 0-0.6 (eyes open, blades spun, rune drawn), snap 0.75, whiff recovery |

## Locomotion / states

| clip | slot | notes |
|---|---|---|
| `iska.idle` | idle, recovery | loop: on the toes, blades crossed low, breathing, weight shift |
| `iska.walkF` / `iska.walkB` | walkF / walkB | loop, root motion = 3.1 / 2.4 m/s (def.stats), planted feet |
| `iska.dash` | dash | 0.24 s glide-step |
| `iska.backstep` | backstep | 0.30 s hop back |
| `iska.dodge` | dodge, roll | 0.38 s low side-slip |
| `iska.guard` | guard / blockstun | loop: blades crossed in an X before the face |
| `iska.hitLight` / `iska.hitHeavy` | hitLight / hitHeavy | *planned* (time permitting) |
| `iska.intro` / `iska.victory` / `iska.defeat` | intro / victory / defeat | *planned* |

## Ultimate lock beats (`h.play` during the lock; lock clock = seconds from the trigger, BALANCE.md section 9)

| clip | play at lock t | dur | in-clip events | action |
|---|--:|--:|---|---|
| `iska.ult.crystal` | 0.01 | 0.44 | — | rune snap follow-through, blades spun down, coils for the dash; ends on the orbit start |
| `iska.ult.orbit` | 0.45 | 1.20 | `impact` 0.0, `cut` 0.0 / 0.2 / 0.4 / 0.6 / 0.8 / 1.0 | six alternating dash-cuts (ticks slash1..slash6) |
| `iska.ult.leap` | 1.65 | 0.30 | `takeoff` 0.12 | crouch and spring: pair with `h.offset([f, 4.5], 0.6, 'outCubic')` from 0.12 |
| `iska.ult.constellation` | 1.95 | 0.70 | — | airborne, blades raised drawing the star lines (holdable loop) |
| `iska.ult.starfall` | 2.65 | 1.00 | `fling` every 0.08 from 0.0 (12) | airborne, alternating blade flings downward |
| `iska.ult.land` | 3.53 | 0.62 | `impact` 0.12 (= lock 3.65 shatter) | drops, lands crossing both blades, crouched hold |
| `iska.ult.frostWave` | 4.15 | 0.50 | — | rises, sweeps both blades out (frost wave) |
| `iska.ult.blendBack` | 4.65 | 0.75 | — | flicks the frost off both blades, back into `iska.stance` |
