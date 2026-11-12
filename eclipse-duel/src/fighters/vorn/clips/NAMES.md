# VORN clip names (animator -> choreographer / integration)

Registered by `import './clips/index.js'` (side effect: `defineClip` / `definePose`). Authored for VORN's own
proportions (play at scale 1, no `bodyScale`). Spear: right hand = main hand at the weapon origin (the forward hand of
the two-handed hold, the spear arm); every VORN clip uses `gripAt: 'choke'` (left hand at -0.26 on the haft, so clip ->
clip fades never change the grip point); grip 0 on the one-handed beats (jab, javelin throw, ult throw / air beats).

**Grip tilt.** The design has no `gripAngle`, so every VORN clip keys `weaponR: [0, 0, -42]` (the spear sits 42 deg
toward the little finger, along the forearm on thrusts) and hands the IK the matching fist frame (`sp()` in common.js).
Generic `game.*` / `demo.*` clips do not: fading into one of them rolls the spear 42 deg in the fist over the fade.
If `design.gripAngle` is ever set, set `GRIP_TILT` in common.js to 0.

## Move clips — authored 1:1 on the rules move clock (clip time = move time, duration = move duration)

Map them by move id with a plain string (no `hit` needed: the clip's first `impact` event sits exactly on the
first active frame of the move). Every clip has `impact` (first active frame), `trailOn` / `trailOff` (same times
as moves.js) and `step` events. Root motion keys (`root`) match the rules `motion`, so planted feet stay planted.

| clip | move | impact | notes |
|---|---|---|---|
| `vorn.flash_jab` | light1 | 0.11 | one-handed snap thrust, front-foot shuffle lands on the impact, the left hand releases and counter-pulls, rear heel rises |
| `vorn.haft_spin` | light2 | 0.12 | spear whirls in both hands, butt-end rises hip -> jaw, 0.72 m step |
| `vorn.thunder_pierce` | light3 | 0.20 (spike 0.25) | lunging two-handed thrust, full extension held for the spike |
| `vorn.gale_sweep` | heavy | 0.28 | deep coil, one-handed low sweep (the left arm flung out for balance), the head skims ~0.13 m over the floor 0.28-0.36, wound round to the far side |
| `vorn.lightning_charge` | f+heavy | 0.20 | crouch, explosive 4 m glide (body pitched into the run, one-handed couched lance, left arm swept back), skid stop 0.38 |
| `vorn.skyward_lance` | d+heavy | 0.18 | crouch, upward thrust to the sky |
| `vorn.thunder_javelin` | skill1 | 0.26 (release) | spear drawn back over the shoulder, one-handed overhand throw motion (spear kept) |
| `vorn.stormfall` | skill2 | 0.45 (release) | spear raised to the sky in both hands 0.04-0.36, brought down one-handed to point at the marker at 0.45 (front foot stamps), re-grip 0.8 |
| `vorn.arc_step` | skill3 | 0.08 (blink) | coil, burst forward (the body is hidden by the choreography while in bolt form), re-form crouch at 0.18 |
| `vorn.ninefold_storm` | ult (opener) | 0.70 | super-freeze pose 0-0.6 (spear raised, sky bolt into the tip), dash-thrust 0.6-0.9, skewer hold |

## State clips

| slot | clip | notes |
|---|---|---|
| `idle`, `recovery` | `vorn.idle` | loop 2.8 s, low spear guard (spear held low, haft along the right side), breathing, weight shift |
| `walkF` | `vorn.walkF` | loop, root motion = def.stats.walkSpeed (2.6 m/s) -> plays at 1x, planted feet |
| `walkB` | `vorn.walkB` | loop, root motion = def.stats.backSpeed (2.0 m/s) -> plays at 1x |
| `dash` | `vorn.dash` | 0.26 s progress-driven |
| `backstep` | `vorn.backstep` | 0.32 s |
| `dodge` | `vorn.dodge` | 0.42 s |
| `guard` | `vorn.guard` | loop, crouched behind the heavy left pauldron, spear level at the opponent (spear wall) |
| `intro` | `vorn.intro` | spear planted upright, wrenched into the guard |
| `victory` | `vorn.victory` | spear twirl, planted, head up |
| `defeat` | `vorn.defeat` | sinks to one knee on the spear |
| `hitLight` / `hitHeavy` | `vorn.hitLight` / `vorn.hitHeavy` | 0.32 / 0.85 s, the impact pose at 0.05 / 0.06 (the game's startAt) |
| `guardBreak`, `crumple`, `launched`, `fall`, `down`, `getup`, `tech`, `ko`, `locked` | `vorn.guardBreak` `vorn.crumple` `vorn.launched` `vorn.fall` `vorn.down` `vorn.getup` `vorn.tech` `vorn.ko` `vorn.locked` | the generic `game.*` motion re-expressed with VORN's grip (states.js: spear tilt + choke grip; lying poses keep the spear off the floor), so no state change rolls the spear in the fist |

Poses: `vorn.stance` (the idle's first frame = every recovery's last frame), `vorn.guardPose`, `vorn.sentinel` (spear
planted upright, intro start / victory end), `vorn.ult.skewerPose` (the dash-thrust impact with both feet planted).

## Ultimate lock beat clips — play with `h.play('vorn.ult.<beat>')` on the lock clock

Lock clock t (storyboard = 0.90 + lock t). Each clip starts on its marker unless a lead time is given.

| clip | play at lock t | length | action |
|---|---|---|---|
| `vorn.ult.lift` | 0.05 (`lift`) | 0.25 | skewered victim lifted: spear levered up, hips drop, both hands drive the butt down |
| `vorn.ult.hurl` | 0.30 (`hurl`) | 0.15 | flicks the spear up: hurls the victim into the air |
| `vorn.ult.throw` | 0.45 (`throw`) | 0.45 | one-handed javelin throw straight up after the victim (release at clip 0.08 = lock 0.53). Hide the weapon from the release (`char.weapon.setVisible(false)`), show it again on `catch` |
| `vorn.ult.leap` | 0.90 (`leap`) | 0.40 | crouch and spring upward (offset the root up from clip 0.15); ends airborne |
| `vorn.ult.bolts` | 1.30 | loop 0.6 | airborne, left hand thrust at the victim directing the nine bolts (loop until `catch`) |
| `vorn.ult.catch` | 2.30 (`catch`) | 0.10 | right hand snaps up and closes on the falling spear (show the weapon) |
| `vorn.ult.storm` | 2.40 (`storm`) | 0.55 | spear raised overhead with both hands, body arched, the storm gathers |
| `vorn.ult.slam` | 2.95 (impact event at clip 0.25 = lock 3.20 `slam`) | 1.15 | dive, drives the spear down through the victim into the floor, kneeling hold, wrench free and vault back (airborne at the end, lock 4.10) |
| `vorn.ult.land` | 4.10 (`land`) | 0.30 | lands in a crouch |
| `vorn.ult.twirl` | 4.40 (`twirl`) | 0.60 | the spear rolls up over the top onto the shoulder, rests, swings down into `vorn.stance` (settle at lock 5.00) |

All lock clips are in place (no root motion): the leap / dive / vault heights are the choreography's `h.offset`; feet in
the air are keyed in root space so they ride the offset. `vorn.ult.slam` carries an `impact` event at 0.25.
