# src/cam — camera director

Fight framing, trauma shake / kicks / zoom, a cinematic shot sequencer with a reusable shot vocabulary, the
cinematic lens (auto-focus depth of field, focus breathing, exposure hints, whip-pan blur) and the letterbox. One
object, `ctx.cam`, updated once per frame at `ctx.ORDER.CAM` (after GAME / CHAR / VFX, before ENV / UI / POST). The
director writes `ctx.camera` (position, quaternion, fov) and calls `camera.updateMatrixWorld()`, so anything later in
the frame (`post.radialAt`, UI projections) sees this frame's camera. Art direction: `MURIM.md` (wuxia flourishes on
cinematic shots: low sweeps, the held duel frame with the eclipse between the masters, push-ins on a drawn blade).

```
src/cam/index.js      createCameraDirector(ctx) -> ctx.cam       (public API)
src/cam/framing.js    fight rig: analytic two-shot solve, springs, walls
src/cam/sequencer.js  cinematic shots: frames, keys, cues, transitions, late-bound shots
src/cam/shots.js      shot vocabulary (16 parameterised builders + the duelIntro sequence)
src/cam/lens.js       cinematic lens: depth of field, focus breathing, tone hints, whip / crash blur (through ctx.post)
src/cam/shake.js      trauma shake, impulse kicks, handheld drift + operator micro-motion (real time)
src/cam/pose.js       Pose, critically damped springs, point sources, orientation
src/labs/cam.js       lab: dummy fighters + scenarios (node tools/build.mjs cam)
```

Clocks: framing, shake, kicks, zoom, letterbox and every **blend** run on **real time** (they keep moving through
hit-stop and slow-motion). Shot timelines run on **game time** by default (they stay in sync with the choreography and
freeze with hit-stop); set `clock: 'real'` on a shot (or the whole sequence) to override, e.g. for a super-freeze.
Determinism: no `Math.random()`; the shake noise is seeded (`createCameraDirector(ctx, { seed })`).
Cost: ~30 µs CPU per frame, no per-frame allocations, no draw calls or shader programs of its own (the lens only
switches existing post passes on: see "Cinematic lens"). Every filter is dt-exact (critically damped springs,
phase-accumulated noise, exponential velocity smoothing), so a dropped frame (dt 1/30) follows the same path as two
1/60 frames (lab check: within 3 cm in calm motion, within one frame of motion in launches / impacts).
URL flag `#camfx=0`: the plain camera (no lens, no operator micro-motion, no hit zoom) for A/B checks.

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
| `setTargets(a, b, { scale })` | the two fighters: point sources at **chest height** (Object3D, `() => Vector3`, Vector3, `[x,y,z]`), read every frame; index 0 / 1 elsewhere refers to these. `scale`: number or `[a, b]`, body size relative to the 1.9 m reference (default 1; e.g. `[1, 4.5]` against a colossal boss) |
| `targetScale` | live `[a, b]` body scales (see above). Chest / head / width margins of each target and the follow-lift in shots scale with it |
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
| `state` | last frame, read-only: `{mode, shot, pos, quat, look, fov, roll, blend, cut, focus, aperture}` (`cut` true on a hard-cut frame; `focus` m / `aperture` of the lens) |
| `limits` | safety limits for every camera: `{minZ: 0.5, minY: 0.12, knee: 0.4}` (soft floors, then hard clamps after shake) |
| `shakeSettings` | amplitudes at trauma 1 + global `scale` (accessibility "reduce shake": set `scale` 0..1) |
| `lens` | the cinematic lens: `lens.settings` (live, table in "Cinematic lens") and `lens.info` (this frame: `{focus, aperture, range, near, exposure, vignette, blur, breathe, dof}`) |
| `cine` | cinematic defaults (live): `{handheld: 0.2}` = handheld amount of shots that do not set one |
| `shots` | the shot vocabulary (`shots.js`) on the director, for data-driven choreography and tests: `cam.play([cam.shots.lowSweep()])` |
| `sun` | optional `Vector3` toward the eclipse for sun-aware shots (`duelStandoff`); default `ctx.env.sunDir` |
| `debug` | `{rig, shake, base, seqShot()}`: fight-rig readout, last shake sample, pre-shake pose, the normalised shot on screen |
| `dispose()` | remove the per-frame update and return every post value the lens offset |

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
| `near` / `mid` / `far` | `{sep 1, fov 34, fill .6, feet .13, pitch 4.5}` / `{4.5, 37, .46, .17, 6.5}` / `{10, 40, .36, .2, 8.5}` | m, deg, frac, frac, deg | look by separation `sep` (measured in units of the larger target's scale): vertical fov, standing height of the larger target as a fraction of frame height (`fill`), floor line from the bottom (`feet`), down-tilt. Blended near→mid→far (pushes in on a clinch, pulls back as they part) |
| `air` | `{top .8, feet .08, pan 2}` | frac, frac, m | a jump first spends the headroom up to `top` and pans up by lowering the floor line toward `feet` over `pan` metres of lift; only then pulls back |
| `chestHeight` / `headTop` | 1.35 / 0.62 | m at scale 1 | target point height / chest → top of head + margin |
| `sideMargin` / `edgePad` | 1.15 / 0.04 | m at scale 1 / frac | soft width: each fighter's outer side keeps this much room, plus a screen-edge pad |
| `bodyMargin`, `hardTop`, `hardPad`, `hardPadTop` | 0.55, 0.5, 0.03, 0.1 | m at scale 1, m at scale 1, frac, frac | walls: body half-width, chest → head top, edge pads (top pad keeps heads clear of the HUD) |
| `wallMargin`, `pushSpeed` | 0.1, 8 | frac, m/s | how early the springs steer away from a wall; speed cap of a wall-pushed spring |
| `lead` | 0.14 | s | look-ahead on the highest fighter's climb rate |
| `minDist` / `maxDist` | 3.2 / 24 | m | soft distance range (walls may exceed `maxDist`: both fighters always win) |
| `parallax` | 0.16 | frac | the dolly x trails the aim toward the arena centre → slight yaw toward the fighters |
| `bounds`, `overscan`, `camInset` | `{minX -9, maxX 9}`, 1.6, 1.2 | m | arena limits (taken from `ctx.env.bounds` when present); the frame may run at most `overscan` past a wall; dolly x stays `camInset` inside |
| `aspectRef` / `aspectFov` | 1.5 / 16 | – / deg | below this aspect, fov widens by `aspectFov` per unit of aspect |
| `breathe` | 0.12 | – | handheld drift amount in fight mode (0 = locked off; the operator micro-motion of cinematic shots is never added here) |
| `hitZoom` / `hitZoomMin` | 0.035 / 0.3 | frac / trauma | big hits only: a `cam.shake(amount)` of `hitZoomMin` or more in fight mode punches the dolly in by up to `hitZoom` (1.4 % at 0.3, 3.5 % at 1.0; 35 ms in, ~0.4 s out). The walls still keep both fighters in frame. 0 = off |
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
| `handheld` | 0.2 (`cam.cine.handheld`) | slow rotational drift (1 ≈ 0.6° yaw) plus, on cinematic shots only, the operator's micro-motion: a faint 2.3 Hz tremor (0.12° at 1), a few centimetres of body sway (real parallax) and a slow lens respiration (±0.5 % fov at 1). Blends across shots; 0 = locked off |
| `dof` | auto | depth of field of the shot (table in "Cinematic lens"): `false` = none, a number = aperture, `{ focus, aperture, gain, range, near, pull, protect }` |
| `tone` | auto lift | exposure hint: `false` = none, a number = exposure offset, `{ exposure, vignette, auto }` (additive on `post.fx`) |
| `blur` | 1 (0.3 with `follow: true`) | scale of the whip-pan / crash-zoom blur of this shot (`false` / 0 = none) |
| `breathe` | 1 | focus-breathing scale of this shot |
| `grade`, `gradeDur` | –, 0.5 s | `post.grade` preset name or params applied when the shot starts; the baseline grade returns when the sequence ends (`grade: false` returns it at this shot) |
| `name` | – | label (the vocabulary builders set their own name); shown by the lab's `#lens` readout |

**Late-bound shots.** An entry of the shot list may be a function `(c) => shot`: the sequencer calls it when that shot
starts (one normalisation at the shot change, nothing per frame) with the live context `c = { facing (+1 / -1), aspect
(viewport), sun (unit Vector3 toward the eclipse), anchor, target, mid (chest points, Vector3), sep (m), index, count }`.
Use it for shots that frame world things or depend on where the fighters stand; `duelStandoff` and `lowSweep` are built
this way (pass options to the builder; do not spread its result). To cancel the sequencer's mirroring for a world-fixed
offset `dx`, author `f = dx * c.facing`.

Safety for every shot: the camera position is eased above `z = limits.minZ` and `y = limits.minY` (soft knee, then a
hard clamp after shake). Near-vertical views keep a stable screen-up (−Z looking down, +Z looking up), so a crane from
side-on to top-down never flips.


---

## Cinematic lens — `src/cam/lens.js` (`cam.lens`)

Runs only while a cinematic shot is on screen (`cam.play`); fight framing keeps depth of field, tone hints, breathing
and blur **off** (readability first). Everything is real-time, dt-exact, snaps on hard cuts and eases on blends.

### Depth of field (`shot.dof`)

The director is the focus puller: each frame it measures the focus distance along the view axis, smooths it (a focus
pull), and drives `post.dof` with the distance, the sharp range and the aperture. On the hand-back to fight framing the
aperture closes in ~0.3 s and `post.dof` is released.

| `dof` key | default | meaning |
|---|---|---|
| `focus` | `'auto'` | `'auto'` / `'look'`: the aim point; `'anchor'` / `'target'`: that fighter's chest (live); `'both'` / `'mid'`: half-way between the two fighters with both inside the sharp range; a number: metres; a point source (Object3D, `() => Vector3`, Vector3, `[x,y,z]`): e.g. a weapon socket |
| `aperture` | auto | 0..1.5 blur strength (`post.dof`). Auto: `1.1 · (tan 20° / tan(fov/2)) · 2.6 / focus`, capped at 1, times `gain`: tight framings open up, wide ones stop down |
| `gain` | 0.7 (`lens.settings.autoGain`) | multiplier of the auto aperture |
| `range` | `0.35 + 0.1 · focus` | m in front of / behind the focus that stay sharp |
| `near` | 1 | foreground blur scale (0 = none; > 1 for a foreground wipe) |
| `pull` | 0.14 s | focus pull smooth time (rack focus: change `focus` on a blended shot with `pull: 0.3`) |
| `protect` | true | a fighter that is in frame and within `0.3 · focus + 0.5` m of the focal plane widens the sharp range to include it, so a two-shot never loses a fighter to the blur. `false` isolates the subject (over-shoulder, blade close-ups) |

`dof: false` = no depth of field on the shot; a number = aperture; omitted = auto focus + auto aperture.

### Tone hints (`shot.tone`, `shot.grade`)

`tone: { exposure, vignette, auto }` are small **additive** offsets on `post.fx.exposure` / `vignette` for the length
of the shot. `auto` (default on) adds the dark-angle lift: up to `lens.settings.lift` (0.11) when the view looks up
28° or more (a master against the night sky) and `liftDown` (0.07) on near-vertical top-down views. `tone: false`
switches the hint off; a number is an exposure offset. `grade` applies a `post.grade` preset for the sequence
(`duelStandoff` / `duelIntro` use `'ink'`). The letterbox is untouched (still `shot.letterbox` / `cam.letterbox`).

### Motion blur (`shot.blur`)

Whip pans and crash zooms smear for the few frames they last, through the post radial blur: the lens follows the
screen motion of the point the camera aimed at one frame earlier (a pan) and the change of the subject's scale (a push
or pull), and places the radial centre so both are right (a pan alone = a centre 3 screens away = directional blur).
Orbits, cranes and slow moves keep their subject still on screen and stay sharp. Dead zones: 0.6 % of the screen per
1/60 s (pan), 2 % scale (zoom). Streaks are capped at `blurLen` (7 % of the screen): the post blur has 10 taps and
longer streaks break thin HDR highlights into dots.

### Focus breathing and operator micro-motion

While the focus racks the fov follows it by up to ±1.5 % (3.5 % per e-fold of focus distance, relaxing in 0.9 s),
like a real lens. The handheld layer of cinematic shots adds a tremor, body sway and a slow respiration on top of the
drift (see `handheld`). None of it is applied in fight framing.

### Settings — `cam.lens.settings` (live)

| key | default | meaning |
|---|---|---|
| `enabled` | true | master switch (`#camfx=0` sets it false) |
| `dof` | 1 | aperture scale (0 = never touch `post.dof`) |
| `dofMin` | 0.12 | apertures below this keep the DOF passes off |
| `dofMinMid` | 0.45 | on the mid tier only shots at or above this aperture (portraits, close-ups, the low sweep) pay for DOF |
| `autoGain` | 0.7 | aperture gain of shots without a `dof` field |
| `pull` | 0.14 s | default focus pull time |
| `breathe` | 1 | focus breathing scale |
| `tone` | 1 | scale of every exposure / vignette hint |
| `lift` / `liftDown` | 0.11 / 0.07 | automatic dark-angle exposure lifts |
| `blur` | 1 | whip / crash blur scale (0 = off) |
| `shutter` | 0.9 | blur length in 1/60 s frames of screen motion |
| `blurLen` | 0.07 | longest streak, fraction of the screen |

### Cost per tier (60 fps plan)

The lens has no passes or programs of its own; it switches post features that were compiled at boot (no mid-fight
compiles: program counts are identical before and after a cinematic).

| tier | depth of field | whip / crash blur | tone, breathing, micro-motion, hit zoom |
|---|---|---|---|
| low | off (post has no depth) | off | on (uniforms / camera only: free) |
| mid | only shots with aperture ≥ 0.45: +2 half-res passes (16 taps) while such a shot is up | on: the composite's 10-tap radial branch for the 3-8 frames of a whip / crash | on |
| high | every cinematic shot with aperture ≥ 0.12: +2 half-res passes (32 taps); `topDownSlam` never | same | on |

Fight framing never pays for any of it (`__ED.info().post.dof` is false outside cinematics; the aperture tail is cut
0.3 s after the hand-back). CPU: ~8 µs per frame for the lens, no allocations (shot normalisation happens at `play`
/ shot changes).

### Sharing the post pipeline

* `post.fx.exposure / vignette / radial` are offset additively. If anything else writes one of those keys (a
  `post.to` tween, `post.reset`, `setBaseline`), that write wins: it becomes the new base and the lens eases its
  offset back in afterwards. `post.pulse` is unaffected (pulses add on top).
* `post.fx.radialCenter` is moved only while the lens blur is active and put back afterwards. A `radial` pulse fired
  during a whip pan without `post.radialAt` would streak along the pan: call `radialAt` first (the game already does).
* `post.dof` belongs to the director while a cinematic shot with depth of field is up; it is released (aperture 0)
  when the sequence ends. Another module that wants DOF outside cinematics (photo mode, result screen) can call
  `post.dof` freely then.

---

## Shot vocabulary — `src/cam/shots.js`

Every builder returns shot data, takes the parameters below plus any common shot field (`cut, hold, clock, ease,
lookEase, fovEase, shake, kick, slowmo, letterbox, handheld, follow, followY, followLag, dof, tone, blur, breathe,
grade, gradeDur`) and `scale`: the subject's size relative to 1.9 m — every authored distance, height, orbit radius
and focus range is multiplied by it (`shots.heroPushIn({ scale: 4.5 })` frames an 8.5 m colossus the way the default
frames a human). Pairs `[a, b]` are from → to; a single value means constant. `subject`: `'anchor' | 'target' | 'mid' |`
point source. Builders that author their own `shake` / `kick` accept a number (new amount, same character) or an
object / array / `false` (replace). `shots.SHOTS` maps names to builders (also `cam.shots`).

**Lens defaults.** Every builder puts the focus on its subject (the anchored fighter, the victim, both) with an
aperture for its shot type, and a small exposure hint where the angle is dark (last column: focus, aperture — a
number, or `auto × gain` —, then `+exposure` / `vig +vignette`). A caller's `dof` / `tone` object is merged over the
default (`shots.heroPushIn({ dof: { aperture: 0.5 } })`); `dof: false` switches the blur of that shot off.

| builder | use | parameters (defaults) | lens (focus, aperture, tone) |
|---|---|---|---|
| `heroPushIn` | power-up / super-freeze: low camera in front of the subject looking up, slow dolly + fov squeeze | `subject 'anchor', dur 1.1, angle 32, dist [3.6,2.5], height [0.42,0.55], look [1.5,1.62], fov [36,30], roll 0 (dutch; grows 30 %), arc -8` | subject, 0.9, range 0.55; +0.04, vig +0.05 (+ the auto low-angle lift) |
| `crashZoom` | from far and wide to tight in a fraction of a second (expo ease), shake on arrival; zoom blur | `subject 'target', dur 0.36, angle -18, dist [10,2.8], height [1.8,1.5], look 1.45, fov [50,27], shake 0.35` | subject, auto × 0.5, pull 0.06 |
| `overShoulder` | behind the anchor's camera-side shoulder on a long lens, looking at the target, slow push; the shoulder is a soft foreground | `dur 1.3, back 1.7, side 0.62, height 1.95, look 1.4, push 0.35, fov [28,25], from 'anchor', at 'target'` | `at`, 0.85, range 0.6, near 1.2, no protect; +0.04, vig +0.05 |
| `whipPan` | near-static camera snapping its aim from one subject to another (expo), banking roll kick + lateral shake + directional blur | `dur 0.3, from 'anchor', to 'target', pos [-1.2,1.5,3.4], look 1.35, fov [40,33], bank 4` | aim, auto × 0.5, pull 0.08; blur 1.25 |
| `orbitSweep` | arc around a pivot while rising, pivot centred | `subject 'mid', dur 1.3, from -40, to 35, radius [7.2,6.4], height [1.3,2.5], look 1.2, fov 38` | subject (`'mid'` = both), auto × 0.8 |
| `impactPunchIn` | sharp push onto the struck fighter, hard deceleration, fov squeeze, shake + roll kick; zoom blur | `subject 'target', dur 0.45, angle -28, dist [3.8,2.4], height [1.55,1.5], look 1.45, fov [36,29], shake 0.55` | subject, auto × 0.5, pull 0.06 |
| `topDownSlam` | nearly overhead on the impact point, slowly turning and settling | `subject 'target', dur 0.9, height [7.5,6], toward [1.4,1.0], ahead 0, look 0.3, fov [42,38], roll [0,10]` | none (one depth from above); +0.02 (+ the auto top-down lift) |
| `wideEstablishing` | far, high, slow lateral drift and crane — the whole arena | `subject 'mid', dur 1.8, dist [14,13], height [3.2,3.9], look [2,1.8], drift 1.6, fov 42` | subject (both), auto × 0.9 (a soft far backdrop on high); vig +0.04 |
| `faceCloseUp` | three-quarter front head shot at eye level, eyes on the upper third, slow push | `subject 'anchor', dur 1.1, angle 42 (negative for the target), dist [1.35,1.05], height 1.68, look 1.63, fov [30,27]` | aim (the head), 1.15, range 0.3, pull 0.1; +0.06, vig +0.08 |
| `weaponFollow` | rides alongside a moving subject (dash, or a weapon socket as `subject`), subject in the left third, aiming down the line of travel | `subject 'anchor', dur 0.6, pos [[-1.3,1.1,2.1],[-0.9,1.2,1.85]], look [[1.6,1.2,0],[2,1.1,0]], fov [48,44], roll [4,2]` (follows, `followY`, lag 0.08) | subject, 0.5, range 0.8; blur 0.3 |
| `groundSkim` | camera racing along the floor looking up; with `'mid'` frames + `follow:'look', followY` it is the low "airborne fight" shot | `dur 0.9, from [-0.9,0.28,1.3], fromSpace 'anchor', to [-1.3,0.32,1.1], toSpace 'target', look [[2,0.8,0],[0,1.25,0]], lookSpace ['anchor','target'], fov [52,44], roll [-3,0]` | aim, auto × 0.6; +0.04 |
| `dutchDrift` | tilted, uneasy medium shot sliding sideways while the tilt deepens | `subject 'anchor', dur 1.6, angle 18, dist 4, height [1.55,1.7], look 1.4, roll [8,12], drift 0.8, fov 36` | subject, 0.7; vig +0.05 |

### Wuxia flourishes (MURIM.md)

| builder | use | parameters (defaults) | lens |
|---|---|---|---|
| `lowSweep` | a long lens skimming the floor on an arc around the subject; the arc starts **behind a foreground element** (default: the other master, whose legs, coat tails and blade wipe across the frame far out of focus) and clears it to reveal the subject. Late-bound (radius from the separation) | `subject 'target', behind (the other fighter; false = plain low orbit), dur 1.3, from 84, to 50 (deg off straight-on on the foreground side; 90 = on the fight line, kept ≥ 0.75 m on the camera side), back 1.9 (m behind the foreground element), radius (overrides sep + back), height [0.34,0.52], look [1.2,1.3], lead 0.22, fov [30,27], roll [-4,0], side` | subject, 1.0, range 0.7, near 1.3, no protect; +0.12, vig +0.06 |
| `duelStandoff` | the **held wide duel frame**: low, far, long lens, both masters small on either side and the eclipse hanging between them at head height; a slow creep and the operator's breathing only. Late-bound: reads the eclipse direction (`cam.sun` / `env.sunDir`), the separation and the aspect; the lens widens on narrow (portrait) viewports until both masters and the eclipse fit | `dur 1.6, dist [13,12.4], height 0.45, fov 24, sunY 0.58, feetY 0.2, margin 1.5, creep 0.25, grade 'ink'` | both, 0.3; vig +0.08; grade `'ink'` |
| `bladeRush` | **fast push-in on a drawn blade**: from a medium three-quarter view the camera lunges (expo) to arm's length of the steel on a tightening lens, the focus racks onto the edge, a small jolt lands with it | `subject 'anchor', blade (point source: a weapon socket; default the point at), at [0.42,1.08,0.12], dur 0.6, angle 36, dist [3.4,0.95], height [1.3,1.14], fov [40,25], roll [-7,-3], shake 0.18` | aim (the blade), 1.1, range 0.3, pull 0.07, no protect; +0.05, vig +0.08 |
| `craneRise` | the light-foot leap (경공): starts at the floor looking up at the take-off, cranes up and back faster than the fighter rises with the aim riding the leap, ends level with the apex | `subject 'anchor', dur 1.0, angle [28,10], dist [3.4,5.6], height [0.32,3.4], look [1.25,1.4], fov [32,40], roll [4,-2]` (aim follows, `followY`, lag 0.045) | subject, auto × 0.75; +0.03 |
| `duelIntro` | **sequence** (returns an array for `cam.play`): `lowSweep` from behind the anchor revealing the rival, cut to `duelStandoff`; the hand-back to fight framing is then a slow push-in. Later rounds: the duel frame only | `dur 2.2 (total), round 1, grade 'ink', sweep {...}, standoff {...}` | – |

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

A round intro in the wuxia grammar (drop-in for the game's intro shots), and a blade moment before a skill:

```js
cam.play(shots.duelIntro({ dur: rules.introTime, round }), { anchor: 0, blendOut: 0.55, hud: false });
cam.play([shots.bladeRush({ blade: char.sockets.weaponTip, dur: 0.5, hold: true }), shots.whipPan({ cut: 0.1 })], { anchor: i });
```

A rack focus on a locked-off over-shoulder (two blended shots with the same keys; only the focus changes):

```js
const key = { pos: [-1.6, 1.62, 0.8], look: [0, 1.4, 0], fov: 27 };
cam.play([
  { dur: 0.9, space: 'anchor', lookSpace: 'target', from: key, dof: { focus: 'anchor', aperture: 1.1, range: 0.3, protect: false } },
  { dur: 1.0, cut: 0.01, space: 'anchor', lookSpace: 'target', from: key, dof: { focus: 'target', aperture: 1.1, pull: 0.28, protect: false } },
], { anchor: 0 });
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
framing channels), `#lens` (live readout of the lens: shot name, focus distance, range, aperture, exposure hint,
blur, breathing), `#camfx=0` (plain camera). Wuxia scenarios: `duelIntro` / `duelIntroM`, `wuxia` / `wuxiaM` (5.4 s
sample: blade rush, whip pan, over-shoulder rack, crane on a leap, punch-in, low sweep), `focusRack`, `whipBlur`,
`hitZoom`, and `shot_<name>` for the four new builders. Scenarios: `clinch near mid far veryFar edgeL edgeR offCentre walk corner swap launch dash`
(framing), `shakeLight shakeHeavy shakeSkill shakeUlt shakeDir shakeStack kickFov kickPush kickRoll zoom letterbox`,
`shot_<name>` / `shotM_<name>` for every vocabulary entry (M = anchored on the right-hand fighter, i.e. mirrored),
`ult` / `ultM` (4-second sample ultimate: 5 shots, cuts, an event-driven cut, a blend, slow-motion, letterbox),
`blendBack` (stop a top-down shot mid-way), `overview` (plan view of the director's camera frustum and path),
`giant` / `giantShots` (a 4.5x colossus: fight framing and scaled vocabulary shots).

```
node tools/shot.mjs cam --do "__ED.lab.play('ult')" --at 0.02,0.4,1.2,2.1,3.2,4.4 --sheet --sheet-only --out shots/cam/ult
node tools/shot.mjs cam --size 800x500 --hash hud --do "__ED.lab.play('walk')" --at 1,2.8,5 --sheet --out shots/cam/walk
```

## Notes for other modules

- Game: the round intro can use `shots.duelIntro` (example above); choreography gets depth of field, exposure hints
  and blur on every vocabulary shot and on hand-keyed shots without changes. To keep a shot fully sharp (a VFX set
  piece with crisp ink edges) pass `dof: false`; to keep both fighters sharp on a hand-keyed two-shot use
  `dof: { focus: 'both' }`.
- VFX / post: transparent effects do not write depth, so an effect in front of a far background takes the background's
  blur. Action shots are stopped down (auto × 0.5) for that reason; portraits open up.

- The camera can sit up to `fight.maxDist` (24 m) from the fight line when the fighters are far apart (more for a
  very narrow viewport) and cinematic shots go to ~14 m / 7.5 m high: keep the +Z side of the arena free of
  occluders up to z ≈ 20 below y ≈ 6 (or fade them), as nothing needs to look good from behind.
- Pass chest-height sockets to `setTargets`; airborne / knocked-down fighters are handled from those points.
- Boss mode: `cam.setTargets(player.chest, boss.chest, { scale: [1, bossHeight / 1.9] })` and author the boss's shots
  with `scale`; nothing in the director assumes the 1.9 m human.
