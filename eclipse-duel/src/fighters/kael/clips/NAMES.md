# KAEL clip names (src/fighters/kael/clips) — for the choreographer

All registered by `import './clips/index.js'`. That module also exports:
- `KAEL_CLIPS` — the ready-made state / move map for the fighter module: `export default { ..., clips: KAEL_CLIPS }`
  (every move as `{ clip, hit }`, locomotion, guard, intro / victory / defeat, hitLight / hitHeavy);
- `KAEL_CLIP_NAMES` — every clip registered (also listed below).

Conventions
- Move clips are authored **on the move clock** (clip time = rules move time, duration = move duration). Each has
  `impact` + `hit` events on the first active frame (= the `hit` value in `KAEL_CLIPS`, so the retime is the identity and
  keeps the impact on the first active frame if the frame data changes), `trailOn` / `trailOff` on the moves.js marker
  times and `step` on foot plants. Rules travel (light2 / light3 / lunge / dash / backstep) is keyed as clip root motion
  so the feet stay planted in 'origin' space while the rules slide the root (the clip root motion is not applied).
- Every clip starts from and returns to `kael.stance` (greatsword resting on the right pauldron, both hands on the
  grip, left foot forward, heavy crouch), so chains, cancels and recoveries blend without pops.
- `kael.pyre` keeps its feet off IK while airborne (0.62–0.98): the leap height is the rules' y.
- Ultimate lock beats are authored on their own clock: `h.play(name, { fade: 0.06 })` at the **lock time given
  below**; their `impact` events then land on the lock ticks. Each beat starts on the previous beat's last pose. Air
  beats switch the feet off IK; the height of the leap (~1.6–2.0 m) is yours: `h.offset([f, u], dur, ease)`
  (suggested: leapAfter `h.offset([0.3, 1.6], 0.5, 'outCubic')` at lock 1.90, `[0.4, 2.0]` over 0.3 s at 2.40, back to
  `[0.4, 0]` over 0.18 s `'inQuad'` at lock 2.72 so the feet land on the meteor impact at 2.90).

## Poses
| name | what |
|---|---|
| `kael.stance` | guard / idle base: blade on the right shoulder, heavy wide stance |
| `kael.l1end`, `kael.l2end` | link poses: light1 follow-through (blade low left) / light2 follow-through (blade high behind) |
| `kael.block` | guard pose (half-sword: left gauntlet on the flat) |
| `kael.planted` | bulwark: blade planted point-down in front, hands stacked on the hilt |
| `kael.vigil` | intro / victory: blade planted, standing tall over the hilt |

## Locomotion / stance
| name | loop | what |
|---|---|---|
| `kael.idle` | yes | shoulder-rest stance, slow heavy breathing, weight rolling between the feet (2.8 s) |
| `kael.walkF` | yes | heavy alternating gait, root motion = walkSpeed 2.1 m/s exactly (plays at 1x, planted feet, drift < 2 mm) |
| `kael.walkB` | yes | backward gait, root motion = backSpeed 1.55 m/s exactly |
| `kael.dash` | – | 0.34 s, shoulder-down rush, two driving steps; root keys follow the rules' ease-out (1.9 m) |
| `kael.backstep` | – | 0.38 s hop back (1.45 m), rear foot lands first |
| `kael.dodge` | – | 0.46 s drop under the line, upper body sways back and away |
| `kael.guard` | yes | blade upright across the body, left gauntlet braced on the flat (`gripAt: 'blade'`) |

## Moves — clip time = move time
| name | impact | what |
|---|---|---|
| `kael.light1` | 0.14 | Ash Cleave: cocks off the shoulder, forehand diagonal down, ends in `kael.l1end` (low left) |
| `kael.light2` | 0.13 | Back Edge: the back edge climbs the same diagonal from low left to high right, 0.25 m step, ends in `kael.l2end` |
| `kael.light3` | 0.24 | Cinder Drop: rises tall, overhead chop, the point bites the floor at ~1.9 m (`crack` at 0.24), 0.35 m step |
| `kael.sweep` | 0.32 | Furnace Sweep: armoured coil (blade drawn back low, hips wound 70°), 300° flat wrap-around arc, hauls it back up |
| `kael.lunge` | 0.26 | Molten Lunge: left shoulder leads, blade chambered at the hip, flying lunge (3.2 m root keys), thrust, recovers |
| `kael.vent` | 0.22 | Vent Launcher: point sunk in the floor ahead (`split` 0.18), rising cut to past vertical, up on the back toes |
| `kael.crescent` | 0.28 | Ember Crescent: point dragged on the floor behind (0.04–0.24, `drag`), rising release along the right side (`release` 0.28) |
| `kael.eruption` | 0.40 | Fault Eruption: sword raised to the sky (0–0.3), driven point-first into the floor at ~1.3 m, leans on it, `wrench` 0.74 |
| `kael.bulwark` | – | Pyre Bulwark: slams the blade point-down in front (`plant` 0.1), braced, `shed` 0.6, pulls it free (`gripAt: 'pommel'`) |
| `kael.bulwark_burst` | 0.05 | counter: rips the blade up one-handed, left arm flung wide, chest open; back to the stance by 0.7 |
| `kael.pyre` | 0.85 | ultimate opener: blade lifted to the eclipse (0.05–0.46), crouch, leap 0.6 (`leap`), down-slash, landing slam 1.0 (`slam`) |

## Ultimate lock beats — `h.play()` at the given lock time
| name | play at lock t | dur | impacts (lock t) | what |
|---|---|---|---|---|
| `kael.ult.cuts` | 0.10 | 0.85 | 0.25, 0.40, 0.55 (`data.cut` 1/2/3) | wrench up, forehand diagonal / back-edge climb / straight overhead chop, then coils low with the point down by the rear foot |
| `kael.ult.hurl` | 0.95 | 0.85 | 1.30 | grinds the point behind him, rising cut along the right side up through the victim, stretched tall, then crouches for the leap |
| `kael.ult.leapAfter` | 1.80 | 0.60 | – (`leap` at clip 0.1) | push-off at 0.1, knees tuck, blade trailing behind (feet off IK from 0.2) |
| `kael.ult.spin` | 2.40 | 0.32 | – (`ring` at 0.06) | one full turn in the air, the blade at arm's length out to the side = the ring of fire; ends blade overhead behind |
| `kael.ult.meteor` | 2.70 | 1.50 | 2.90 | over the top and down, blade through the victim into the floor, crater landing, held through the shockwave (3.30) |
| `kael.ult.rise` | 4.20 | 1.00 | – (`wrench` 0.5) | pushes up on the planted blade, wrenches it free, steps into `kael.stance` exactly at 5.20 (settle) |

The victim stands 1.7 m in front during the lock (rules `cinematic.distance`); the cuts and the hurl are spaced for it.

## Ceremony / reactions
| name | dur | what |
|---|---|---|
| `kael.intro` | 2.4 | vigil over the planted blade, head rises (1.0), wrenches it free (`wrench` 1.45), steps into the stance |
| `kael.victory` | 2.0 | swings the blade down and plants it (`plant` 0.5), stands tall over the hilt, chin up (holds the last frame) |
| `kael.defeat` | 1.8 | leans on the planted blade and goes down on one knee, head hung (holds the last frame) |
| `kael.hitLight` | 0.34 | flinch: head and chest snap back, blade stays on the shoulder |
| `kael.hitHeavy` | 0.8 | rocked back, blade lifts off the shoulder, rear foot stagger-steps back, recovers to the stance |
