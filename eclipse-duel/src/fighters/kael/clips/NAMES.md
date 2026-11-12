# KAEL clip names (src/fighters/kael/clips) — for the choreographer

Registered by `import './clips/index.js'` (defineClip / definePose from `src/char/index.js`). `clips/index.js` also exports
`KAEL_CLIPS`, the ready-made state / move map for the fighter module (`clips: KAEL_CLIPS`).

Conventions
- Move clips are authored **on the move clock** (clip time = rules move time, duration = move duration). Each has an
  `impact` event (and `hit`) at the first active frame, so `{ clip, hit }` retiming is the identity today and keeps the
  impact on the first active frame if the frame data changes. Clip events also carry `trailOn` / `trailOff` / `step`.
- Every clip starts from and returns to `kael.stance` (greatsword resting on the right shoulder, both hands on the
  grip, left foot forward), so chains, cancels and recoveries blend without pops.
- Ultimate lock beats are authored on their own clock: play them with `h.play(name, { fade })` at the **lock time given
  below**; their `impact` events then fall on the lock ticks. Air beats keep the feet off IK; the height of a leap is
  the choreographer's `h.offset([f, u], dur, ease)`.

## Poses
| name | what |
|---|---|
| `kael.stance` | guard / idle base: blade on the right shoulder, heavy wide stance |

## Locomotion / stance (priority 2)
| name | loop | what |
|---|---|---|
| `kael.idle` | yes | shoulder-rest stance, slow heavy breathing, weight shift (2.8 s) |
| `kael.walkF` | yes | heavy step-drag forward, root motion = walkSpeed 2.1 m/s, planted feet |
| `kael.walkB` | yes | step-drag backward, root motion = backSpeed 1.55 m/s, planted feet |
| `kael.dash` | – | short shoulder-down rush (0.34 s, clip time = state progress) |
| `kael.backstep` | – | hop back (0.38 s) |
| `kael.dodge` | – | low sidestep / duck (0.46 s) |
| `kael.guard` | yes | blade held vertical in front, left forearm braced on the flat |

## Moves (priority 1) — clip time = move time
| name | impact (first active) | what |
|---|---|---|
| `kael.light1` | 0.14 | Ash Cleave: diagonal down cut from the shoulder, ends low left (link pose `kael.l1end`) |
| `kael.light2` | 0.13 | Back Edge: rising backhand from low left to high right, step 0.25 m (link `kael.l2end`) |
| `kael.light3` | 0.24 | Cinder Drop: overhead into the floor, step 0.35 m |
| `kael.sweep` | 0.32 | Furnace Sweep: armoured coil, 300° horizontal wrap-around swing |
| `kael.lunge` | 0.26 | Molten Lunge: shoulder-first charge (3.2 m root motion is the rules'), thrust |
| `kael.vent` | 0.22 | Vent Launcher: blade low, splits the floor, rising cut to the sky |
| `kael.crescent` | 0.28 | Ember Crescent: blade dragged on the floor behind, rising diagonal release |
| `kael.eruption` | 0.40 | Fault Eruption: overhead raise, blade driven into the floor (0.40–0.74), wrench free |
| `kael.bulwark` | – (`plant` 0.04) | Pyre Bulwark: sword planted, braced stance to 0.6, shed + pull free |
| `kael.bulwark_burst` | 0.05 | counter burst: rips the sword up and out, body flung open |
| `kael.pyre` | 0.85 | ultimate opener: sword raised to the eclipse (0–0.56), leap 0.6, down-slash 0.85–1.0, landing |

## Ultimate lock beats (priority 3) — `h.play()` at the given lock time
| name | play at lock t | impacts (lock t) | what |
|---|---|---|---|
| `kael.ult.cuts` | 0.10 | 0.25, 0.40, 0.55 | three rapid burning cuts in an X (cut1 / cut2 / cut3), ends coiled low |
| `kael.ult.hurl` | 0.95 | 1.30 | rising cut that hurls the victim into the air, ends crouched for the leap |
| `kael.ult.leapAfter` | 1.80 | – | crouch + leap after the victim (airborne pose; add h.offset for the height) |
| `kael.ult.spin` | 2.40 | – | one full spin in the air, blade at arm's length (ring of fire), ends sword overhead |
| `kael.ult.meteor` | 2.70 | 2.90 | downward meteor slam onto the floor, deep landing crouch held through the shockwave (3.30) |
| `kael.ult.rise` | 4.20 | – | rises from the crater, wrenches the blade up onto the shoulder, ends in `kael.stance` at 5.20 (settle) |

## Ceremony / reactions (priority 4)
| name | what |
|---|---|
| `kael.intro` | blade planted, head bowed; wrenches it free and shoulders it |
| `kael.victory` | blade planted, hands on the pommel, head raised |
| `kael.defeat` | drops to one knee, leaning on the planted blade |
| `kael.hitLight` / `kael.hitHeavy` | flinch / heavy stagger back (root motion back), back to the stance |

Status column of what is actually registered: see `clipNames` in `clips/index.js` (`KAEL_CLIP_NAMES`).
