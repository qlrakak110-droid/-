# src/cam — camera director

Fight framing, trauma shake / kicks / zoom, a cinematic shot sequencer with a reusable shot vocabulary, and the
letterbox. One object, `ctx.cam`, updated once per frame at `ctx.ORDER.CAM` (after GAME / CHAR / VFX, before ENV /
UI / POST). The director writes `ctx.camera` (position, quaternion, fov) and calls `camera.updateMatrixWorld()`, so
anything later in the frame (`post.radialAt`, UI projections) sees this frame's camera.

```
src/cam/index.js      createCameraDirector(ctx) -> ctx.cam       (public API)
src/cam/framing.js    fight rig: analytic two-shot solve, springs, walls
src/cam/sequencer.js  cinematic shots: frames, keys, cues, transitions
src/cam/shots.js      shot vocabulary (12 parameterised builders)
src/cam/shake.js      trauma shake, impulse kicks, handheld drift (real time)
src/cam/pose.js       Pose, critically damped springs, point sources, orientation
src/labs/cam.js       lab: dummy fighters + scenarios (node tools/build.mjs cam)
```

Clocks: framing, shake, kicks, zoom, letterbox and every **blend** run on **real time** (they keep moving through
hit-stop and slow-motion). Shot timelines run on **game time** by default (they stay in sync with the choreography and
freeze with hit-stop); set `clock: 'real'` on a shot (or the whole sequence) to override, e.g. for a super-freeze.
Determinism: no `Math.random()`; the shake noise is seeded (`createCameraDirector(ctx, { seed })`).
Cost: ~25 µs CPU per frame, no per-frame allocations, no draw calls.

---

## Coordinate frames

World: metres, Y up, fight line = X axis at z = 0, floor y = 0, the camera always on the +Z side (z ≥ 0.5).
Shots are authored in a **fighter-local frame** `[f, u, s]`:

```
                    +u (up, metres above the floor)
                     |
                     |        anchor faces +X  (facing = +1)      anchor faces -X  (facing = -1)
                     |        f  ------------>                    <------------  f
                     |   world.x = origin.x + f            world.x = origin.x - f
                     |
   fight line z=0 ---A----------------T---------> world +X        T----------------A
                    /                                             (mirror image: same shot list)
                   / +s (side: always toward the camera, world +Z, never mirrored)
                  /
            camera side (z > 0.5)

   world = (origin.x + f * facing,  origin.y + u,  origin.z + s)      roll and orbit angles also flip with facing
```

Frames ("spaces") a key, a look-at point or an orbit pivot can be authored in:

| space | origin | facing applied | notes |
|---|---|---|---|
| `'anchor'` (default) | on the floor under the anchor fighter | yes | `u` = height above the floor (chest ≈ 1.35, head ≈ 1.75) |
| `'target'` | on the floor under the target fighter | yes (the **anchor's** facing) | `f < 0` is between the fighters (the target's front) |
| `'mid'` | midpoint of the two floor points | yes | two-shots, orbits |
| `'arena'` | world origin (0,0,0) | yes | arena-relative shots that still mirror |
| `'world'` | world origin | **no** | absolute coordinates; roll is not mirrored either |
| point source | that point exactly (Object3D, `() => Vector3`, Vector3, `[x,y,z]`) | yes | e.g. a weapon-tip socket |

Frames are **snapshotted** when a shot starts (fighter frames on the floor). With `follow` they track the live
points instead (smoothed by `followLag`); with `followY` a followed fighter frame also rises with the fighter
(origin.y = chest height − 1.35), so an aim at `u = 1.35` stays on an airborne chest.

Orbit angles are degrees from straight-on (+s) toward +f: positive views the anchor's front, negative the target's
front. Roll is degrees; positive roll dips the horizon on the anchor's forward side (mirrors with facing).

---

## API

```js
import { createCameraDirector } from './cam/index.js';
import * as shots from './cam/shots.js';
const cam = createCameraDirector(ctx);              // also sets ctx.cam
cam.setTargets(p1.sockets.chest, p2.sockets.chest);
```

| member | description |
|---|---|
| `setTargets(a, b)` | the two fighters: point sources at **chest height** (Object3D, `() => Vector3`, Vector3, `[x,y,z]`). Read every frame. Index 0 / 1 elsewhere refers to these. |
| `fight` | live framing parameters (table below) |
| `shake(amount, opts) -> {stop()}` | trauma shake (table below) |
| `kick(opts) -> {stop()}` | impulse on fov / dolly / roll / position (table below) |
| `zoom(factor, duration = 0.6, opts)` | temporary push-in in fight mode (table below) |
| `play(shots, opts) -> handle` | cinematic sequence (tables below) |
| `stop(blend = 0.35)` | end any cinematic and blend back to fight framing over `blend` real s (0 = hard cut) |
| `letterbox(on, dur = 0.35)` | animate `post.fx.letterbox` to `on` (`true` = 1, `false` = 0, or 0..1) over `dur` real s (eased) |
| `mode` | `'fight'` \| `'cine'` \| `'free'` |
| `setMode('free' \| 'fight', blend = 0.5)` | `'free'`: stop writing `ctx.camera` (photo mode, lab orbit) while still computing `state`; leaving `'free'` blends from wherever the camera was |
| `snap()` | jump the fight framing to its ideal now (round start, teleport reset) — treated as a cut |
| `clearFx()` | stop all shakes, kicks and zoom (round reset) |
| `state` | last frame, read-only: `{mode, shot, pos, quat, look, fov, roll, blend, cut}` (`cut` true on a hard-cut frame) |
| `limits` | safety limits for every camera: `{minZ: 0.5, minY: 0.12, knee: 0.4}` (soft floors, then hard clamps after shake) |
| `shakeSettings` | amplitudes at trauma 1 + global `scale` (accessibility "reduce shake": set `scale` 0..1) |
| `debug` | `{rig, shake, base}`: fight-rig readout, last shake sample, pre-shake pose |
| `dispose()` | remove the per-frame update |

Events: `ctx.events.emit('cam:cine', true | false)` when a sequence starts / ends; `play` also calls
`ctx.ui.hud.cinematic(on)` when a UI is present (opt out with `hud: false`).

### Fight framing — `cam.fight`

Each frame the rig solves the ideal two-shot analytically from the chest points, smooths it with critically damped
springs, then applies **walls** (both bodies fully in frame) that shape the spring targets with a margin; only motion
faster than the lag (launches, teleports) reaches a wall, where the spring is clamped but keeps the wall's velocity so
it decelerates smoothly when released. A rising fighter is led by its climb rate. Viewport aspect and the current
letterbox are part of the solve (Hor+: ultra-wide shows more width, portrait / 16:10 pulls back or widens fov).

| param | default | unit | meaning |
|---|---|---|---|
| `near` / `mid` / `far` | `{sep 1, fov 34, fill .6, feet .13, pitch 4.5}` / `{4.5, 37, .46, .17, 6.5}` / `{10, 40, .36, .2, 8.5}` | m, deg, frac, frac, deg | look by separation `sep`: vertical fov, standing fighter height as a fraction of frame height (`fill`), floor line from the bottom (`feet`), down-tilt. Blended near→mid→far (pushes in on a clinch, pulls back as they part) |
| `air` | `{top .8, feet .08, pan 2}` | frac, frac, m | a jump first spends the headroom up to `top` and pans up by lowering the floor line toward `feet` over `pan` metres of lift; only then pulls back |
| `chestHeight` / `headTop` | 1.35 / 0.62 | m | target point height / chest → top of head + margin |
| `sideMargin` / `edgePad` | 1.15 / 0.04 | m / frac | soft width: each fighter's outer side keeps this much room, plus a screen-edge pad |
| `bodyMargin`, `hardTop`, `hardPad`, `hardPadTop` | 0.55, 0.5, 0.03, 0.1 | m, m, frac, frac | walls: body half-width, chest → head top, edge pads (top pad keeps heads clear of the HUD) |
| `wallMargin`, `pushSpeed` | 0.1, 8 | frac, m/s | how early the springs steer away from a wall; speed cap of a wall-pushed spring |
| `lead` | 0.14 | s | look-ahead on the highest fighter's climb rate |
| `minDist` / `maxDist` | 3.2 / 24 | m | soft distance range (walls may exceed `maxDist`: both fighters always win) |
| `parallax` | 0.16 | frac | the dolly x trails the aim toward the arena centre → slight yaw toward the fighters |
| `bounds`, `overscan`, `camInset` | `{minX -9, maxX 9}`, 1.6, 1.2 | m | arena limits (taken from `ctx.env.bounds` when present); the frame may run at most `overscan` past a wall; dolly x stays `camInset` inside |
| `aspectRef` / `aspectFov` | 1.5 / 16 | – / deg | below this aspect, fov widens by `aspectFov` per unit of aspect |
| `breathe` | 0.12 | – | handheld drift amount in fight mode (0 = locked off) |
| `lag` | `focus .2, cam .42, out .16, in .55, sep .3, rise .08, fall .45, land .08, lift .25, pan .35, panPush .1, fov .6` | s | spring smooth times: aim, dolly x, pull-out (fast), push-in (slow), separation, head line up/down, floor line up/down, vertical pan relax/push, fov |

### Shake — `cam.shake(amount, opts)`

Trauma model: each shake holds a trauma value that decays linearly; the visible amplitude is trauma², so hits fade
fast at the tail. Motion is smooth two-octave gradient noise per channel (camera-space x/y/z and yaw/pitch/roll);
shakes overlap (summed, soft-clipped). Guide: 0.15 light hit, 0.35 heavy, 0.5 skill finisher, 1.0 ultimate impact.

| opt | default | unit | meaning |
|---|---|---|---|
| `duration` | – | s | if set, decay = amount / duration (trauma reaches 0 at `duration`) |
| `decay` | 1.6 | trauma/s | linear trauma decay (used when no `duration`) |
| `freq` | 15 | Hz | noise frequency (8 = heavy rumble, 20 = sharp jolt) |
| `dir` | – | world `[x,y,z]` | concentrate motion along this direction (e.g. `[0,1,0]` for a slam); in shots it is `[f,u,s]` and mirrors |
| `rot` / `pos` | 1 / 1 | 0..1 | rotational / positional channel weights |

`cam.shakeSettings`: `{pos 0.1 m, yaw 3°, pitch 2.6°, roll 3.2°, scale 1, maxTrauma 1.5}` at trauma 1.

### Kick — `cam.kick(opts)`

A one-off impulse: eased attack, then a damped-spring release with slight overshoot, ending exactly at zero.

| opt | default | unit | meaning |
|---|---|---|---|
| `fov` | 0 | deg | added fov (negative = punch in) |
| `push` | 0 | m | dolly along the view (positive = toward the subject) |
| `roll` | 0 | deg | roll impulse (not mirrored when called directly; mirrored inside shots) |
| `offset` | – | world `[x,y,z]` m | positional jolt |
| `duration` / `attack` | 0.32 / 0.045 | s | total length / time to peak |
| `bounce` | 0.3 | 0..1 | release overshoot |

### Zoom — `cam.zoom(factor, duration = 0.6, opts)`

Multiplies the fight distance by `factor` (0.75 = 25 % closer) for `duration` real seconds with critically damped
attack / release; the walls still keep both fighters in frame. `opts`: `focus` (fighter index or point source to
lean toward), `weight` (0.6), `attack` (0.12 s), `release` (0.3 s). The lean follows the zoom depth, so aim and dolly
release together.

### Cinematics — `cam.play(shots, opts) -> handle`

| opt | default | meaning |
|---|---|---|
| `anchor` | 0 | fighter index or point source the shots are authored around |
| `target` | the other fighter | index or point source |
| `facing` | toward the target | +1 / -1: mirrors every `f`, roll and orbit angle |
| `blendOut` | 0.5 | real s back to fight framing after the last shot (0 = cut); `false` = hold the last frame until `stop()` / `handle.stop()` |
| `clock` | `'game'` | default clock of the shots |
| `onShot(i, shot)` | – | called when shot `i` starts |
| `onDone(completed)` | – | called once: `true` when the last shot finished, `false` when interrupted |
| `keepLetterbox` | false | do not restore the letterbox the sequence changed |
| `hud` | true | toggle `ui.hud.cinematic` around the sequence |

Handle: `stop(blend?)`, `next()` (cut to the next shot now; ends after the last), `goto(i)`, `done`, `index`, `time`.
Use `next()` with `hold: true` shots to cut on a gameplay event (e.g. the hit lands) instead of a timer, so the
hit-stop freeze happens on the right shot. A new `play()` replaces a running sequence (its `onDone(false)` fires).

On the hand-back, the fight rig (which kept tracking while hidden) is settled to its ideal for the current positions
and the camera blends there **inertially**: the blend source keeps its last velocity (decaying) while easing toward
the destination with a C2 smootherstep, so blends are continuous from any state (moving shot, top-down, free camera).

#### Shot

| field | default | meaning |
|---|---|---|
| `dur` | 1 | seconds on the shot's clock |
| `from`, `to` | `to` = `from` | keys: `{ pos: [f,u,s], look: [f,u,s], fov (deg, 40), roll (deg, 0), space, lookSpace }`. `to` inherits whatever it omits (including the space of an inherited point). `look` defaults to `[0, 1.3, 0]` |
| `space` / `lookSpace` | `'anchor'` / `space` | frame of positions / look points (per-key overrides allowed, so a move can start near the anchor and end near the target) |
| `ease` | `'inOutSine'` | position / roll easing (`core/math.js` Ease name or function); `lookEase`, `fovEase` override aim / fov |
| `via` (+ `viaSpace`) | – | `[f,u,s]` control point: the position follows a quadratic Bézier from → via → to (crane arcs) |
| `orbit` | – | `{ pivot [f,u,s] = [0,1.2,0], space, from°, to°, radius: r \| [r0,r1], height: h \| [h0,h1] }`; aim defaults to the pivot |
| `cut` | `true` | transition **into** this shot: `true` / 0 = hard cut (no blended frame), number = blend seconds (real time), `false` = 0.35 s blend |
| `hold` | false | stay on the last frame until `handle.next()` / `goto()` |
| `follow` | false | `false` = frames frozen at shot start; `'look'` = the aim tracks live points; `true` = position and aim track |
| `followY`, `followLag` | false, 0.12 s | tracked fighter frames rise with the fighter; tracking smoothness |
| `clock` | sequence clock | `'game'` or `'real'` |
| `shake` | – | number (trauma at shot start) \| shake opts + `amount`, `at` (shot seconds) \| array of those; `dir` in `[f,u,s]` |
| `kick` | – | kick opts + `at` \| array; `roll` / `offset` mirror |
| `slowmo` | – | number (scale for the whole shot) \| `{ scale, at, dur (shot seconds), easeIn = 0.08, easeOut = 0.18 }`. Requests `ctx.time.slowmo` sized so the ease-out lands at the end of the span on a game clock; cancelled when the shot ends |
| `letterbox` | – | `true` / `false` / 0..1 / `{ amount, dur }` at shot start (restored after the sequence unless `keepLetterbox`) |
| `handheld` | 0 | slow rotational drift (1 ≈ 0.6° yaw); blends across shots |

Safety for every shot: the camera position is eased above `z = limits.minZ` and `y = limits.minY` (soft knee, then a
hard clamp after shake). Near-vertical views keep a stable screen-up (−Z looking down, +Z looking up), so a crane from
side-on to top-down never flips.

---

## Shot vocabulary — `src/cam/shots.js`

Every builder returns plain shot data, takes the parameters below plus any common shot field (`cut, hold, clock,
ease, lookEase, fovEase, shake, kick, slowmo, letterbox, handheld, follow, followY, followLag`). Pairs `[a, b]` are
from → to; a single value means constant. `subject`: `'anchor' | 'target' | 'mid' |` point source. Builders that
author their own `shake` / `kick` accept a number (new amount, same character) or an object / array / `false`
(replace). `shots.SHOTS` maps names to builders.

| builder | use | parameters (defaults) |
|---|---|---|
| `heroPushIn` | power-up / super-freeze: low camera in front of the subject looking up, slow dolly + fov squeeze | `subject 'anchor', dur 1.1, angle 32, dist [3.6,2.5], height [0.42,0.55], look [1.5,1.62], fov [36,30], roll 0 (dutch; grows 30 %), arc -8` |
| `crashZoom` | from far and wide to tight in a fraction of a second (expo ease), shake on arrival | `subject 'target', dur 0.36, angle -18, dist [10,2.8], height [1.8,1.5], look 1.45, fov [50,27], shake 0.35` |
| `overShoulder` | behind the anchor's camera-side shoulder on a long lens, looking at the target, slow push | `dur 1.3, back 1.7, side 0.62, height 1.95, look 1.4, push 0.35, fov [28,25], from 'anchor', at 'target'` |
| `whipPan` | near-static camera snapping its aim from one subject to another (expo), banking roll kick + lateral shake | `dur 0.3, from 'anchor', to 'target', pos [-1.2,1.5,3.4], look 1.35, fov [40,33], bank 4` |
| `orbitSweep` | arc around a pivot while rising, pivot centred | `subject 'mid', dur 1.3, from -40, to 35, radius [7.2,6.4], height [1.3,2.5], look 1.2, fov 38` |
| `impactPunchIn` | sharp push onto the struck fighter, hard deceleration, fov squeeze, shake + roll kick | `subject 'target', dur 0.45, angle -28, dist [3.8,2.4], height [1.55,1.5], look 1.45, fov [36,29], shake 0.55` |
| `topDownSlam` | nearly overhead on the impact point, slowly turning and settling | `subject 'target', dur 0.9, height [7.5,6], toward [1.4,1.0], ahead 0, look 0.3, fov [42,38], roll [0,10]` |
| `wideEstablishing` | far, high, slow lateral drift and crane — the whole arena | `subject 'mid', dur 1.8, dist [14,13], height [3.2,3.9], look [2,1.8], drift 1.6, fov 42` |
| `faceCloseUp` | three-quarter front head shot at eye level, eyes on the upper third, slow push | `subject 'anchor', dur 1.1, angle 42 (negative for the target), dist [1.35,1.05], height 1.68, look 1.63, fov [30,27]` |
| `weaponFollow` | rides alongside a moving subject (dash, or a weapon socket as `subject`), subject in the left third, aiming down the line of travel | `subject 'anchor', dur 0.6, pos [[-1.3,1.1,2.1],[-0.9,1.2,1.85]], look [[1.6,1.2,0],[2,1.1,0]], fov [48,44], roll [4,2]` (follows, `followY`, lag 0.08) |
| `groundSkim` | camera racing along the floor looking up; with `'mid'` frames + `follow:'look', followY` it is the low "airborne fight" shot | `dur 0.9, from [-0.9,0.28,1.3], fromSpace 'anchor', to [-1.3,0.32,1.1], toSpace 'target', look [[2,0.8,0],[0,1.25,0]], lookSpace ['anchor','target'], fov [52,44], roll [-3,0]` |
| `dutchDrift` | tilted, uneasy medium shot sliding sideways while the tilt deepens | `subject 'anchor', dur 1.6, angle 18, dist 4, height [1.55,1.7], look 1.4, roll [8,12], drift 0.8, fov 36` |

---

## Examples

Hit reactions (presentation layer, on the logic's `hit` event):

```js
cam.shake(0.35);                                  // heavy hit (real time, runs through the hit-stop)
cam.kick({ fov: -3, duration: 0.25 });            // small punch-in
cam.shake(0.8, { dir: [0, 1, 0], freq: 11 });     // ground slam: vertical
cam.zoom(0.78, 0.6, { focus: attackerIndex });    // super-freeze emphasis in fight mode
```

An ultimate (authored once, mirrors for either side; cut to the punch-in exactly when the hit lands):

```js
const h = cam.play([
  shots.heroPushIn({ dur: 0.7, roll: 6, letterbox: true, clock: 'real' }),   // super-freeze: game time is stopped
  shots.weaponFollow({ dur: 0.45, hold: true }),                             // dash; held until the hit connects
  shots.impactPunchIn({ dur: 0.3 }),
  shots.groundSkim({ dur: 0.9, cut: 0.22, follow: 'look', followY: true,
    from: [-1.5, 0.28, 3.6], fromSpace: 'mid', to: [0.2, 0.34, 3.2], toSpace: 'mid',
    look: [[0, 1.45, 0], [0.3, 1.4, 0]], lookSpace: 'mid', fov: [54, 48],
    slowmo: { scale: 0.35, dur: 0.45 } }),
  shots.topDownSlam({ dur: 0.85, shake: { amount: 1, at: 0.25, dir: [0, 1, 0] } }),
], { anchor: casterIndex, blendOut: 0.7, onDone: () => game.resume() });
match.on('moveEvent', (e) => { if (e.name === 'ultHit') { h.next(); } });
```

A hand-keyed shot with an orbit and a crane arc:

```js
cam.play([
  { dur: 1.2, space: 'mid', orbit: { from: -30, to: 50, radius: [6, 5], height: [1.2, 2.6] }, from: { fov: 38 }, to: { fov: 34 } },
  { dur: 0.8, cut: 0.3, from: { pos: [-2, 0.4, 3], look: [2, 1.4, 0] }, via: [0, 3, 4],
    to: { pos: [2, 1.6, 3], space: 'target', look: [0, 1.3, 0], lookSpace: 'target' }, ease: 'inOutCubic' },
], { anchor: 1 });
```

---

## Lab — `src/labs/cam.js`

`node tools/build.mjs cam`; flags `#hud` (mock fight HUD to judge headroom), `#scope` (live plot of shake / kick /
framing channels). Scenarios: `clinch near mid far veryFar edgeL edgeR offCentre walk corner swap launch dash`
(framing), `shakeLight shakeHeavy shakeSkill shakeUlt shakeDir shakeStack kickFov kickPush kickRoll zoom letterbox`,
`shot_<name>` / `shotM_<name>` for every vocabulary entry (M = anchored on the right-hand fighter, i.e. mirrored),
`ult` / `ultM` (4-second sample ultimate: 5 shots, cuts, an event-driven cut, a blend, slow-motion, letterbox),
`blendBack` (stop a top-down shot mid-way), `overview` (plan view of the director's camera frustum and path).

```
node tools/shot.mjs cam --do "__ED.lab.play('ult')" --at 0.02,0.4,1.2,2.1,3.2,4.4 --sheet --sheet-only --out shots/cam/ult
node tools/shot.mjs cam --size 800x500 --hash hud --do "__ED.lab.play('walk')" --at 1,2.8,5 --sheet --out shots/cam/walk
```

## Notes for other modules

- The camera can sit up to `fight.maxDist` (24 m) from the fight line when the fighters are far apart (more for a
  very narrow viewport) and cinematic shots go to ~14 m / 7.5 m high: keep the +Z side of the arena free of
  occluders up to z ≈ 20 below y ≈ 6 (or fade them), as nothing needs to look good from behind.
- Pass chest-height sockets to `setTargets`; airborne / knocked-down fighters are handled from those points.
