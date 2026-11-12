# src/vfx — VFX library

`createVfx(ctx)` builds the effect system, stores it on `ctx.vfx` and registers its per-frame update at
`ctx.ORDER.VFX`. Everything is pooled and allocated once; every layer is hidden (zero draw calls) while idle.
Create it **before the first render** (its pooled point lights must exist when lit shaders compile), define your
presets, then call `vfx.prewarm()` once while loading.

```js
import { createVfx } from '../vfx/index.js';
const vfx = createVfx(ctx);          // ctx.vfx === vfx
vfx.define('ember.hit', (v, at) => { ... });
vfx.prewarm();
// later, from game code
vfx.play('ember.hit', { pos: hitPos, dir: slashDir, facing: -1 });
```

Conventions (CONTRACT.md): metres, seconds, Y up; positions accept `THREE.Vector3`, `[x, y, z]` (and, where noted, an
`Object3D` or a function returning a position); colours accept `THREE.Color`, a hex number / CSS string (sRGB, converted
to linear) or `[r, g, b]` **linear HDR** (2–10 for hot cores, < 1 for smoke). Everything runs on **game time**
(frozen by hit-stop, scaled by slow motion) unless the call passes `realtime: true`. Randomness comes from `ctx.rng`, so
captures are deterministic.

Contents: [Facade](#facade) · [Particles](#particles-burst--emitter) · [Particle definitions](#particle-definitions) ·
[Trails and ribbons](#trails-and-ribbons) · [Lights](#lights) · [Flares](#flares) · [Distortion](#distortion) ·
[Scheduler and presets](#scheduler-and-presets) · [Library layers](#library-layers-vfxlib) ·
[Textures](#textures-sprite-and-noise-catalogue) · [Extending](#extending-sub-modules) · [Performance](#performance) ·
[Look guide](#look-guide) · [Examples](#worked-examples) · [Lab](#lab)

---

## Facade

| member | description |
|---|---|
| `vfx.prewarm(defs = [])` | Compile every VFX program (`renderer.compile` on the scene and `post.distortionScene`), upload the definition tables, and register `defs` (plus all of `vfx.lib`) so no row upload happens mid-fight. Call after defining presets. |
| `vfx.clear()` | Kill everything (round reset): particles, emitters, ribbons, lights (back to 0), flares, distortion, pending scheduled callbacks. Rebases the VFX clocks to 0. |
| `vfx.now(realtime = false)` | Seconds on the VFX game clock (or real clock) since the last `clear()`. |
| `vfx.clock` | `{ game, real, now(realtime) }` (getters). |
| `vfx.schedule(delay, fn, { realtime })` | See [Scheduler](#scheduler-and-presets). |
| `vfx.define(name, fn)` / `vfx.play(name, at, opts)` / `vfx.presets()` | Composed presets. |
| `vfx.burst`, `vfx.emitter`, `vfx.particleDef` | [Particles](#particles-burst--emitter). |
| `vfx.trail`, `vfx.ribbon` | [Ribbons](#trails-and-ribbons). |
| `vfx.light`, `vfx.flare`, `vfx.distort` | Pooled point lights, flares, screen refraction. |
| `vfx.lib`, `vfx.palette` | Tuned base particle layers and element palettes (`library.js`). |
| `vfx.textures` | `{ atlas, noise, flow, sprites, sprite(name), targets }` (see [Textures](#textures-sprite-and-noise-catalogue)). |
| `vfx.util` | Coercion helpers (`util.js`): `toVec3, toColor, sampleRange, toCurveFn, toRampFn, heatRamp, makeFrame, local, CURVES, RENDER_ORDER ...` |
| `vfx.root` | `THREE.Group` in `ctx.scene` that holds the VFX meshes and the light pool. |
| `vfx.use(install)` | Install a sub-module (see [Extending](#extending-sub-modules)). |
| `vfx.particles / ribbons / lights` | Internals for debugging (layers, rings, tables, pools). |

**Handles.** Every spawn returns a handle with `kill()` (remove now) and `alive`; continuous things also have `stop()`
(stop emitting / sampling, let what exists finish). `vfx.play()` returns a *group* handle covering everything the
preset spawned, including layers it schedules for later.

---

## Particles: burst / emitter

GPU particles: instanced quads in ring buffers; position, velocity, size, colour and dissolve are evaluated
analytically in the vertex shader from data written once at spawn (24 floats per particle). Every definition is a row
of a shared float data texture, so **all definitions share one draw call per blend layer**:

| layer | blend | render order | use |
|---|---|---|---|
| `alpha` | premultiplied alpha, optionally partially additive over life (`additive` curve) | 10 | smoke, dust, debris, fire that cools into smoke |
| `add` | additive | 20 | sparks, embers, glows, runes, glints |
| `distort` | additive into `ctx.post.distortionScene` (.rg = UV offset) | — | heat haze |

Capacity (high / mid / low): alpha 4096 / 3072 / 2048, add 8192 / 6144 / 4096, distort 512 / 384 / 256. The ring
overwrites the oldest particles when full.

### `vfx.burst(def, at) -> { kill(), alive }`

One-shot. `def` is a definition object (or a name registered with `particleDef`). `at` is a position or:

| `at` field | default | meaning |
|---|---|---|
| `pos` | `[0,0,0]` | spawn origin (world) |
| `dir` | `def.dir` or up | emission axis: local +Y of the emission frame (cone axis, ring/disc normal) |
| `side` | world X | hint for the frame's local +X (ring orientation, elliptical spread axes, `line` direction) |
| `facing` | `1` | `-1` mirrors local X (fighter-local mirroring; local Z keeps pointing at the camera side) |
| `scale` | `1` | uniform scale of the whole burst: sizes, shape extents, speeds and accelerations (times unchanged) |
| `color` | white | multiplies the colour ramp's RGB (author tintable defs with neutral ramps) |
| `intensity` | `1` | multiplies RGB |
| `alpha` | `1` | multiplies alpha |
| `count` | `def.count` | absolute particle count override (still scaled by `ctx.quality.particleScale`) |
| `vel` | `[0,0,0]` | world velocity (m/s) added to every particle |
| `to` | — | end point for `shape: { type: 'line' }` (spawn along pos → to) |
| `target` | `pos` | attractor / swirl centre (`attract`, `swirl`), e.g. absorb into a hand |
| `delay` | `0` | seconds added to every particle's birth |
| `realtime` | `false` | particles run on real time (keep moving through hit-stop) |

Counts are multiplied by `ctx.quality.particleScale` (high 1, mid 0.7, low 0.45); a non-zero count never drops below 1.

### `vfx.emitter(def, at) -> h`

Continuous emission at `def.rate` particles/s and/or `def.perMeter` particles per metre the emitter travels (great for
weapon tips). Spawns are spread over the frame in time *and* along the emitter's path, so a fast-moving emitter leaves
a continuous stream. `at` as for `burst` plus `duration` (s, auto-`stop()`; default `def.duration`, 0 = until stopped).

| handle member | description |
|---|---|
| `h.pos`, `h.dir` | live `THREE.Vector3`s: move / aim the emitter by writing them |
| `h.rate`, `h.perMeter` | live emission rates (before quality scaling) |
| `h.scale`, `h.color`, `h.intensity`, `h.alpha`, `h.facing` | live spawn modifiers |
| `h.follow(target, offset?, orient = false)` | track an `Object3D` (offset in its local space; `orient` makes `h.dir` its local +Y) or a function / position |
| `h.setPosition(v)` | set `h.pos` |
| `h.stop()` | stop emitting; existing particles finish |
| `h.kill()` | stop and remove its particles now |
| `h.alive` | emitting or particles still alive |

### `vfx.particleDef(name, def)`

Registers a named definition (then `vfx.burst('name', at)` works) and returns the compiled definition.
Definitions are compiled once and cached by identity *and* by content, so inline literals do not leak rows, but define
them at module scope anyway: 192 definition rows exist and the least recently used dead row is recycled when full.

---

## Particle definitions

All fields optional. Ranges are `number`, `[min, max]` or `[min, max, pow]` (`min + (max-min) * u^pow`; `pow > 1` skews
toward `min`: "many small, few large"). Curves are `number`, a name from `CURVES` / `Ease`
(`'grow' 'puff' 'swell' 'shrink' 'shrinkSlow' 'shrinkFast' 'pop' 'flash' 'converge' 'fadeIn' 'fadeOut' 'fadeInOut' 'pulse' 'erode' 'erodeLate' 'erodeEarly' 'linear'`, `'outExpo'` ...),
`[[t, v, ease?], ...]` keyframes, `[v0, v1, ...]` evenly spaced, or `t => v`. Curves and ramps are baked into 16 / 32
samples spaced as `t = (i/(n-1))²` (dense at birth, so 1–3 frame flashes survive).

### Emission

| field | default | units | meaning |
|---|---|---|---|
| `tex` | `'glow'` | — | sprite or group name ([catalogue](#sprites)); a group picks a random variant per particle |
| `frames` | group size | — | limit the variants used |
| `fps` | `0` | 1/s | `> 0`: cycle through the group's variants as a flipbook (cross-faded), e.g. flickering flames |
| `blend` | `'add'` | — | `'add'` \| `'alpha'` \| `'distort'` |
| `count` | `16` | range | burst size |
| `rate` | `0` | 1/s | emitter rate |
| `perMeter` | `0` | 1/m | emitter particles per metre travelled |
| `duration` | `0` | s | emitter auto-stop (0 = until `stop()`) |
| `life` | `[0.5, 1]` | s range | lifetime |
| `delay` | `0` | s range | per-particle birth delay (stagger inside one burst) |
| `shape` | `{ type: 'point' }` | — | see below |
| `jitter` | `0` | m | extra random offset (sphere) |
| `emit` | `'axis'` | — | initial direction: `'axis'` cone around `dir` · `'radial'` from the shape centre · `'random'` · `'inward'` · `'tangent'` (around `dir`: vortex) · `'normal'` (shape normal) |
| `spread` | `25` (or `shape.angle`) | deg | cone half-angle; `[degX, degZ]` elliptical (a fan in the local XY plane: slash sprays) |
| `spreadPow` | `1` | — | `> 1` concentrates directions near the cone axis |
| `lift` | `0` | — | adds `dir * lift` to the direction before normalising (radial dust that rises a bit) |
| `dir` | up | vector | default emission axis when `at.dir` is not given |
| `speed` | `[1, 3]` | m/s range | initial speed |
| `vel` | — | m/s vector | constant world velocity added (wind) |
| `inherit` | `0` | 0..1 | fraction of the emitter's velocity added |

Shapes (local frame: +Y = `dir`, +X = `side`/facing, +Z toward the camera side):

| `shape.type` | fields (defaults) | positions |
|---|---|---|
| `'point'` | — | the origin |
| `'sphere'` | `radius` 0.5, `inner` 0 (0..1 shell), `hemi` false (upper half only) | in / on a sphere |
| `'disc'` | `radius` 0.5, `inner` 0, `height` 0 | in the local XZ plane |
| `'ring'` | `radius` 0.5, `thickness` 0, `height` 0 | on a circle in local XZ |
| `'cone'` | `radius` 0 (base disc), `angle` (deg, default spread) | base disc; directions within `angle` |
| `'box'` | `size` `[1, 1, 1]` | in a local box |
| `'line'` | `length` 1, `centered` true | along local X; or from `at.pos` to `at.to` |

### Motion (all analytic on the GPU)

| field | default | units | meaning |
|---|---|---|---|
| `gravity` | `0` | m/s² (number = Y, or `[x,y,z]`) | constant acceleration; positive Y = buoyancy (smoke, embers) |
| `drag` | `0` | 1/s | exponential velocity damping (with gravity → terminal velocity `g/drag`) |
| `turbulence` | — | `{ amp m/s, freq 1/m = 1, speed 1/s = 1 }` | smooth, spatially coherent meander (integrated sum-of-sines velocity field) |
| `swirl` | `0` | rad/s | rotation around `dir` through the origin (`at.target`) |
| `attract` | `0` | 0..1 | pull toward the origin, reaching it at the end of life with `attract: 1`: **converging charge-ups** |
| `attractPow` | `2` | — | attraction ease exponent (higher = later, faster collapse) |
| `collide` | — | `'ground'` | bounce on the floor `y = 0` (exact for gravity + drag, up to 3 bounces, then slide) |
| `bounce` | `0.4` | 0..1 | restitution (setting it also enables `collide`) |
| `friction` | `0.7` | 0..1 | horizontal velocity kept per bounce |

### Look

| field | default | units | meaning |
|---|---|---|---|
| `size` | `[0.05, 0.12]` | m range | quad height |
| `sizeOverLife` | `1` | curve | size multiplier |
| `aspect` | `1` | — | quad width / height |
| `rotation` | `[0, 2π]` | rad range | initial rotation |
| `spin` | `0` | rad/s range | spin speed (random sign unless `spinBoth: false`) |
| `align` | `'velocity'` if `stretch` else `'billboard'` | — | `'billboard'` camera-facing · `'velocity'` stretched along the screen-space velocity · `'flat'` lies in the plane ⟂ `dir` (ground rings, rune circles) · `'axis'` camera-facing but upright along `dir` (flames) · `'velocityAxis'` upright along the 3D velocity |
| `stretch` | `0` | s | motion blur length = speed × stretch (sparks 0.03–0.06) |
| `maxStretch` | `3` | m | clamp of the stretch length |
| `color` | ember ramp | ramp | `[[t, r, g, b, a], ...]` (or `[[t, colour, a], ...]`, or one colour): HDR colour over life |
| `alpha` | — | curve | extra alpha multiplier over life |
| `intensity` | `1` | — | RGB multiplier; `intensityOverLife` curve too |
| `additive` | `0` | curve | alpha layer only: 0 = alpha blended, 1 = additive (fire that starts glowing and cools into occluding smoke) |
| `heat` | `0` | life fraction | the sprite's heat mask (G) shows the ramp colour from `heat` earlier in life: hot cores inside one sprite |
| `shade` | `1` | 0..1 | how much the sprite's shade channel (R) modulates the colour |
| `erode` | `0` | curve 0..1 | dissolve threshold over life (0 intact, 1 gone): noise erosion instead of a plain fade |
| `erodeSoft` | `0.15` | 0..1 | dissolve edge softness |
| `erodeNoise` | `0.6` | 0..1 | 0 = erode by the sprite's own order mask (B), 1 = by tiling noise |
| `erodeScale` | `0.9` | tiles per quad | noise frequency |
| `erodeChannel` | `'fbm'` | — | `'fbm'` \| `'cells'` \| `'cracks'` \| `'grain'` \| `[r, g, b, a]` weights |
| `erodeGlow` | `0` | — | adds the hot colour along the dissolve edge (burning paper / ash rims) |
| `noiseScroll` | `[0, 0]` | uv/s | scroll the erosion noise |
| `flicker` | `0` | `amount` or `{ amount 0..1, rate Hz = 18 }` | smooth random brightness flicker |
| `groundFade` | `0.12` | m | soft fade where the quad meets the floor; `0` = hard cut below `y = 0` |
| `nearFade` | `0.25` | m | fade when close to the camera |
| `pull` | `0` | m | move the quad toward the camera (flash cores in front of the body they hit) |
| `strength` | `0.02` | UV | `blend: 'distort'` only: refraction strength |
| `realtime` | `false` | — | always run on real time |

---

## Trails and ribbons

All ribbons are re-tessellated every frame into **one shared mesh** (one draw call for all of them; one more for the
refraction twins). Samples are joined with centripetal Catmull-Rom splines and subdivided adaptively (`segLen`), so a
fast swing that moves 40 cm per frame still draws a smooth arc. In slow motion, samples closer than `life / 40` move
the head sample instead of adding one.

### `vfx.trail({ a, b, ... }) -> h`

Weapon trail between two sockets (`Object3D`s, or positions / functions): `a` = base (hilt side), `b` = tip.
Across the ribbon `v` runs 0 (base) → 1 (tip); along it `t` runs 0 (newest) → 1 (oldest).

| option | default | units | meaning |
|---|---|---|---|
| `life` | `0.2` | s | how long a sample stays (trail length in time) |
| `color` | ember: `[[0, 2.6,1,0.25,0.8], [0.12, 1.5,0.38,0.05,0.5], [0.45, 0.6,0.1,0.015,0.22], [1, 0.1,0.02,0,0]]` | ramp over `t` | colour / alpha over age |
| `alpha`, `intensity` | — / `1` | | as for particles |
| `edge` | `[8, 4, 1.2]` | HDR colour or `false` | hot line along the tip edge, fading with age |
| `edgeWidth` | `0.07` | fraction of `v` | edge line width |
| `gradient` | `0.75` | 0..1 | brightness drop toward the base |
| `fadeBase` | `0.6` | fraction of `v` | transparent toward the hilt |
| `width` | `[[0,1],[0.35,0.75],[1,0.12]]` | curve over `t` | fraction of the blade width kept (older parts collapse toward the tip edge: crescent taper) |
| `erode` | `[[0,0],[0.35,0.05],[1,0.85]]` | curve over `t` | noise dissolve of the tail |
| `erodeSoft` | `0.25` | | dissolve softness |
| `noise` | `{ scale: [0.9, 0.55], speed: 1.2, amount: 0.4 }` | per m along, across; scroll; 0..1 | streak noise scrolling along the trail |
| `minSpeed` | `3` | m/s | tip speed below which new samples are invisible (wind-ups and holds draw nothing) |
| `segLen` / `maxSub` | `0.05` / `8` | m / count | adaptive subdivision |
| `distort` | `0` | UV | strength of the refraction twin (e.g. 0.02) |
| `blend` / `additive` | `'add'` / — | | `'alpha'` with an `additive` curve for occluding trails |
| `realtime`, `autoStart` | `false`, `true` | | |

Handle: `start()`, `stop()` (stop sampling, tail fades), `kill()`, `setSockets(a, b)`, `alive`, `sampling`.

### `vfx.ribbon({ ... }) -> h`

Camera-facing strip following one point (projectile tails, dash lines). Options as for `trail` (defaults: `life`
0.45, `edge` none, `fadeBase` 0, `gradient` 0, `minSpeed` 0) plus `follow` (Object3D / function), `offset`, `pos`,
`width` (m, 0.15), `widthOverLife` (curve over `t`, `[[0,1],[1,0.1]]`), `widthScale` (1).
Handle: `setPosition(v)`, `follow(obj, offset?)`, `start()`, `stop()`, `kill()`, `alive`.

---

## Lights

`vfx.light(opts) -> h` borrows one of `ctx.quality.maxLights` pooled `PointLight`s (added once at start-up, never
added or removed; idle ones sit at intensity 0). When all are busy it steals the dimmest.

| option | default | units | meaning |
|---|---|---|---|
| `pos` | — | | position |
| `color` | `[6, 3, 1]` | colour | normalised to its brightest channel (the hue); brightness comes from `intensity` |
| `intensity` | `60` | candela | peak (three r170 physical units: tens to hundreds) |
| `range` | `6` | m | `PointLight.distance` (decay 2) |
| `duration` | `0.35` | s | `Infinity` = until `stop()` |
| `attack` | `0` | s | rise time (0 = full on at once: visible through a hit-stop) |
| `decay` | `'outQuad'` | ease name | fall-off shape: intensity = 1 − ease(x) |
| `curve` | — | curve over life | custom envelope (overrides attack / decay) |
| `flicker`, `flickerRate` | `0`, `14` | 0..1, Hz | smooth random flicker |
| `follow`, `offset` | — | | track an Object3D (offset local) or a function |
| `realtime` | `false` | | |

Handle: `light`, `kill()`, `stop()` (0.18 s fade), `follow(obj, offset)`, `setIntensity(v)`, `alive`.

## Flares

`vfx.flare(opts) -> h`: camera-facing procedural shapes (resolution independent), one instanced draw for all.

| option | default | meaning |
|---|---|---|
| `kind` | `'glow'` | `'glow'` (white-hot pin + halo) · `'star'` (4 long + 4 short rays) · `'streak'` (anamorphic line) · `'ring'` · `'flash'` (wide soft bloom) |
| `pos` | — | world position |
| `color`, `intensity` | `[6, 4, 2.5]`, `1` | HDR colour × intensity |
| `size` | `0.6` | m (quad height); `[start, end]` grows with outExpo over life |
| `aspect` | `1` (`streak`: 8) | width / height |
| `life` | `0.25` | s |
| `attack` / `decay` | `0` / `2` | rise (s) / fall-off power over the rest of the life |
| `rotation` | `0` | rad (screen) |
| `dir` | — | world direction the long axis follows on screen (streak along a slash) |
| `pull` | `0.3` | m toward the camera |
| `screen` | `false` | `size` is a fraction of the screen height instead of metres |
| `follow`, `offset`, `realtime` | | |

Handle: `kill()`, `stop()` (0.12 s fade), `follow()`, `alive`.

## Distortion

`vfx.distort(opts) -> h`: refraction sprites in `ctx.post.distortionScene` (fragment `.rg` = signed UV offset). The
mesh is hidden when nothing is alive, so the post pass skips the distortion buffer entirely.

| option | default | meaning |
|---|---|---|
| `kind` | `'shock'` | `'shock'` expanding refractive band · `'heat'` rising shimmer · `'lens'` bulge (`strength > 0`) / pinch (`< 0`) |
| `pos` | — | centre |
| `radius` | shock `[0.2, 2.5]`, else `0.8` | m; `[start, end]` expands (shock: outQuart) |
| `strength` | shock 0.035, heat 0.012, lens 0.04 | UV offset (0.005–0.06). A shock's strength ramps in as it expands |
| `width` | `0.18` | shock band width as a fraction of the radius |
| `life` | shock 0.45, heat 1.2, lens 0.6 | s |
| `attack` / `decay` | shock 0 / 1.5, others 0.15 / 1.2 | s / fall-off power |
| `normal` | — | world normal for a flat ring (`[0,1,0]`: ground shockwave); omit for camera-facing |
| `follow`, `offset`, `realtime` | | |

---

## Scheduler and presets

`vfx.schedule(delay, fn, { realtime }) -> { cancel(), kill(), alive }` runs `fn(vfx)` after `delay` game seconds
(honours hit-stop and slow motion). Callbacks may schedule more; zero-delay ones run in the same update.

`vfx.define(name, fn(vfx, at, opts))` registers a composed preset; `vfx.play(name, at, opts)` runs it and returns a
group handle `{ kill(), stop(), alive, handles }`. Everything spawned while the preset runs — **including callbacks it
schedules, and what those spawn later** — belongs to the group, so `group.kill()` removes the whole effect and cancels
its pending layers. `at` inside the preset is normalised and owned by the call (safe to capture in closures):

| `at` field | meaning |
|---|---|
| `pos` | `THREE.Vector3` |
| `dir` | `THREE.Vector3`, normalised; default fighter forward `(facing, 0, 0)` |
| `facing` | `±1` |
| `scale` | number (1) |
| `color` | `THREE.Color` or `null` |
| `target` | whatever the caller passed (Object3D, position ...) |
| `local(f, u, s)` | world position in the fighter-local frame relative to `pos` (f is mirrored by `facing`) |
| `raw` | the caller's original object |

---

## Library layers (`vfx.lib`)

Tuned building blocks in `library.js` (ember palette by default). Derive variants with spread syntax and swap the
`color` ramp (`heatRamp(core, mid, tail)` from `util.js` builds flash → core → mid → dark-tail ramps).
`vfx.palette` holds the CONTRACT palettes: `ember`, `frost`, `volt` (`core`, `mid`, `tail`, `smoke`, volt `spark`).

| name | layer | role |
|---|---|---|
| `flashCore` | add | 1–3 frame white-hot burst sprite |
| `splash` | add | few big, fast, heavily dragged streaks that shape a hit's first frames along `dir` |
| `sparks` | add | directional velocity-stretched sparks, gravity, drag, floor bounce (many small, few long-lived) |
| `sparksFine` | add | wide, short secondary spray |
| `embers` | add | slow buoyant turbulent flickering embers (lingering) |
| `smoke` | alpha | dark expanding puffs next to the glows |
| `smokeLinger` | alpha | big delayed rising smoke column |
| `fireball` | alpha | puffs that start additive white-orange and cool into dark smoke |
| `fireLicks` | alpha | flames flying outward along their motion |
| `fire` | alpha | standing fire emitter (`rate`) |
| `dustRing` | alpha | radial ground dust (spawn at floor height, dir up) |
| `pebbles` | alpha | lit stone chips with bounce |
| `glowPuff` | add | expanding soft light bloom |
| `glitter` | add | twinkling glints |
| `chargeStreaks` / `chargeMotes` | add | converging (attract + swirl) charge-up emitters |
| `heatHaze` | distort | rising heat shimmer |

---

## Textures: sprite and noise catalogue

Generated once on the GPU at start-up (one generator program, ~40 ms even on SwiftShader). No images.

**Atlas** 1024×1024 RGBA8, mipmapped. Channels are masks, colour comes from ramps:
`R` shade (form / lighting, `shade`) · `G` heat core (`heat`) · `B` dissolve order (`erode`) · `A` coverage.

<a id="sprites"></a>

| name (group) | size | description |
|---|---|---|
| `smoke1..4` (`smoke`) | 256 | billowing puffs: gaussian lobes, warped fbm, lit from the upper left through the density gradient; round / wide / wispy / lumpy |
| `flame1..3` (`flame`) | 256 | flame licks (single, double, triple tongue), ragged torn tips, hot core in G, top dissolves first |
| `burst` | 256 | radial flash with uneven rays |
| `glow` | 128 | soft round glow with a long tail |
| `glowHard` | 128 | hard white core + halo |
| `disc` | 128 | soft-edged round disc |
| `spark` | 128 | comet streak: hot head at +X, fading tail (head leads when velocity-stretched) |
| `ember` | 128 | irregular glowing blob with hot core and halo |
| `dust` | 128 | small irregular soft dust mote |
| `star4` | 128 | four-point star |
| `glint` | 128 | four long + four short rays |
| `ring` | 128 | thin soft ring |
| `shard1..3` (`shard`) | 128 | faceted crystal shards with bright ridges |
| `snow1..2` (`snow`) | 128 | dendrite snowflake, stellar-plate crystal |
| `ash1..2` (`ash`) | 128 | ash flakes with burning rim (G) and edge-first dissolve |
| `petal` | 128 | petal / leaf flake with midrib |
| `rune1..3` (`rune`) | 128 | original glyphs: ringed seal, standalone stave glyph, dotted circle seal |
| `wisp1..2` (`wisp`) | 128 | curved smoke tendrils |
| `streak` | 128 | thin tapered line (speed lines, rain) |
| `dot` | 128 | crisp dot with small halo |
| `hex` | 128 | hexagonal bokeh with bright rim |
| `arc1..3` (`arc`) | 128 | jagged lightning crackles with a branch |
| `pebble1..3` (`pebble`) | 128 | lit rock chips |
| `crescent` | 128 | thin crescent with a bright inner edge |

`vfx.textures.sprite(name)` returns `{ u, v, w, h, frames }` (UV rect of the first variant; variants follow in +U).

**Noise** 256×256 RGBA8, tiling, mipmapped, linear: `R` perlin fbm · `G` cellular F1 (bubbles) · `B` cellular F2−F1
(cracks) · `A` fine grain fbm.
**Flow** 256×256 RGBA8, tiling: `R` streaks along U (long in U, fine in V) · `G` domain-warped swirl fbm ·
`BA` divergence-free flow vector (0.5 = zero).

---

## Extending: sub-modules

`index.js` installs `MODULES` in order through `vfx.use(install)`. A sub-module is one function:

```js
// src/vfx/slash.js
import * as THREE from 'three';
export function installSlash(vfx, shared) {
  const { ctx, root, textures, clock, uniforms, util, EffectPool } = shared;
  const pool = new EffectPool(shared, 12, (i) => ({ mesh: makeSlashMesh(i) }));   // allocate once
  pool.onFree = (s) => { s.mesh.visible = false; };
  return {
    name: 'slash',
    api: {
      /** vfx.slash({ pos, ... }) */
      slash(opts) {
        const { slot, handle } = pool.alloc({ life: opts.life ?? 0.3, realtime: !!opts.realtime });
        util.toVec3(opts.pos, slot.mesh.position);
        slot.mesh.visible = true;
        return handle;                    // already tracked into the running preset group
      },
    },
    update(dtGame, dtReal) { pool.forEach((s, age, t) => { s.mesh.material.uniforms.uT.value = t; }); },
    clear() { pool.clear(); },
    prewarm() {},                         // programs are compiled by vfx.prewarm(); add extra warm-up here
    dispose() {},
  };
}
// index.js: export const MODULES = [..., installSlash];
```

`shared` provides:

| member | description |
|---|---|
| `ctx`, `root` | app context; the `Group` to add meshes to (`ctx.post.distortionScene` for refraction meshes) |
| `textures` | `atlas`, `noise`, `flow`, `sprites`, `sprite(name)` |
| `clock` | `game` / `real` seconds since the last clear (use these, never `performance.now()`) |
| `uniforms` | `{ uTime, uTimeReal }` uniform objects updated every frame: share them in your materials |
| `rng` | `ctx.rng` |
| `util` | `toVec3, toColor, sampleRange, rangeMax, toCurveFn, toRampFn, heatRamp, CURVES, makeFrame, normalizeAt, makeAt, local, defKey, RENDER_ORDER` |
| `EffectPool` | pooled-effect base: fixed slots, birth time on either clock, life, follow (`pool.place(slot)`), stale-safe handles, oldest-steal |
| `InstanceRing`, `makeQuadGeometry` | instanced quad + interleaved per-instance buffer with partial uploads (`alloc`, `dirty`, `commit`) |
| `ParamTable`, `tableGlsl(sampler, prefix)` | definition rows in a float texture (ramp + curves + params) and their GLSL accessors (`<p>Ramp(t,row)`, `<p>Curve`, `<p>Param`) |
| `track(handle)` | add a handle to the running preset group (EffectPool handles are tracked automatically) |
| `currentGroup()`, `runInGroup(group, fn)` | group plumbing for deferred work |

Render-order bands (`util.RENDER_ORDER`): alpha particles 10, alpha meshes 12, additive meshes 16, additive particles
20, ribbons 22, flares 30. All VFX materials are `transparent`, `depthWrite: false`, premultiplied
(`blendSrc: One, blendDst: OneMinusSrcAlpha`, output `vec4(rgb * a, a * (1 - additive))`), so one material can be
additive, alpha-blended or anything in between.

---

## Performance

- Draw calls: at most ~7 for the whole library at once (alpha, add and distortion particles, flares, distortion
  sprites, ribbons, ribbon refraction); **zero when idle** (every layer hides itself).
- No per-particle CPU work after spawn; no per-frame allocations in update paths; ring buffers upload only the
  written ranges.
- Overdraw: big soft sprites cost the most. Quads are clamped to 70% of the screen height (45% on `low`) and fade
  near the camera. Prefer fewer, larger smoke puffs with `erode` over many overlapping ones.
- Quality: counts and rates × `particleScale`; capacities scale with the tier; the light pool is `maxLights`.
- Call `vfx.prewarm()` after defining presets so programs and tables are ready before the first fight.
- `vfx.clear()` rebases the VFX clocks (float precision stays high in long sessions).

## Look guide

Lessons baked into the library (verified on captures):
- **Value discipline.** ACES turns anything above ~1.5 in its main channel yellow-white, and bloom grows with area.
  Keep large areas (trail bodies, fireballs, runes) in 0.6–3; keep values of 6–14 for small things or 1–4 frames
  (flash cores, spark heads, edges).
- **Stagger.** Flash at frame 0, splash and sparks at 0–1, smoke and dust at 2–4, refraction shock after the flash
  (a shock over a bright flash reads as a magnifying lens).
- **Direction.** Sparks and splash use `emit: 'axis'` around the action direction; use elliptical `spread` for fans.
- **Contrast.** Put dark alpha smoke next to additive glows; the fireball starts additive and cools into occluding
  smoke through the `additive` curve.
- **Dissolve, do not fade**: `erode` curves on smoke, flames and trails.

---

## Worked examples

**1. A frost hit built from library layers**

```js
const F = vfx.palette.frost;
const iceSparks = { ...vfx.lib.sparks, color: vfx.util.heatRamp(F.core, F.mid, F.tail), gravity: -6 };
const shards = { tex: 'shard', blend: 'add', count: 14, life: [0.4, 0.9], spread: 40, speed: [3, 9], size: [0.08, 0.2, 2],
  spin: [4, 12], gravity: -9, collide: 'ground', erode: 'erodeLate', erodeChannel: 'cracks', color: vfx.util.heatRamp(F.core, F.mid, F.tail) };
vfx.define('frost.hit', (v, at) => {
  v.burst(vfx.lib.flashCore, { pos: at.pos, color: [0.5, 0.9, 1.6] });
  v.burst(iceSparks, { pos: at.pos, dir: at.dir });
  v.burst(shards, { pos: at.pos, dir: at.dir, scale: at.scale });
  v.burst({ ...vfx.lib.glitter, color: [[0, 3, 6, 9, 0], [0.1, 3, 6, 9, 1], [1, 1, 2, 3, 0]] }, { pos: at.pos });
  v.light({ pos: at.pos, color: F.core, intensity: 120, duration: 0.3 });
  v.schedule(0.05, (v2) => v2.distort({ kind: 'shock', pos: at.pos, radius: [0.2, 1.4] }));
});
vfx.play('frost.hit', { pos: [1, 1.35, 0], dir: [-1, 0.2, 0.3] });
```

**2. A weapon trail with embers from the tip**

```js
const trail = vfx.trail({ a: char.sockets.weaponBase, b: char.sockets.weaponTip, life: 0.22, distort: 0.02 });
const tipEmbers = vfx.emitter({ ...vfx.lib.embers, rate: 0, perMeter: 20, delay: 0, emit: 'random', spread: 180, inherit: 0.15 }, {})
  .follow(char.sockets.weaponTip);
vfx.schedule(0.45, () => { trail.stop(); tipEmbers.stop(); });      // end of the active frames
```

**3. A charge-up that converges, then releases**

```js
vfx.define('volt.charge', (v, at, o) => {
  const T = o.time ?? 1.0;
  const streaks = v.emitter(vfx.lib.chargeStreaks, { pos: at.pos, color: [0.5, 0.4, 1.2] });   // attract + swirl
  v.flare({ kind: 'glow', pos: at.pos, size: [0.15, 1.0], life: T, attack: T * 0.9, decay: 6, color: [5, 3.5, 9] });
  v.distort({ kind: 'lens', pos: at.pos, radius: 1, strength: -0.05, life: T, attack: T * 0.8 });
  v.light({ pos: at.pos, color: [5, 3.5, 9], intensity: 90, duration: T, curve: [[0, 0], [0.85, 1], [1, 1]] });
  v.schedule(T, (v2) => {
    streaks.stop();
    v2.burst({ ...vfx.lib.sparks, emit: 'radial', spread: 180, count: 90 }, { pos: at.pos });
    v2.distort({ kind: 'shock', pos: at.pos, radius: [0.2, 3] });
  });
});
const h = vfx.play('volt.charge', { pos: hand }, { time: 1.2 });
// interrupted? h.kill() removes the charge and cancels the release
```

---

## Lab

`src/labs/vfx.js` (`node tools/build.mjs vfx`). The stage has a dim block wall behind the action (refraction and
smoke need something to read against) and a swinging two-socket weapon rig. Scenarios (positions are `[x, y, z]`):

| scenario | shows |
|---|---|
| `atlas(which = 'atlas', mode)` | a texture full screen: `which` = `atlas` / `noise` / `flow`; `mode` 0 tinted preview, 1 alpha, 2 rgb×a, 3 raw |
| `gallery('all' \| 'add' \| 'alpha')` | every sprite as a static particle |
| `sparks(pos)` `embers(pos)` `smoke(pos)` `converge(pos)` | library layers on their own |
| `fire(pos)` | standing fire: flame + smoke + ember emitters and a flickering pooled light |
| `trail(opts)` | the rig swings (anticipation → smear → follow-through) with a trail; `opts` are trail options |
| `ribbon()` | a projectile on a curved path with a ribbon and an ember emitter following it |
| `flare()` `distort()` `light(pos)` `schedule()` | every flare kind; every distortion kind; a light flash; staggered bursts |
| `swordImpact(pos, dir)` | composed hit: flash, anamorphic streak, splash, sparks with floor bounce, fine spray, embers, smoke, light, delayed shock, ground dust |
| `fireBurst(pos)` | composed explosion: flash, fireball cooling into smoke, licks, sparks, embers, smoke column, ground glow, dust ring, heat haze, two shocks |
| `chargeRelease(pos, time)` | converging charge (streaks, motes, rune circle, lens pinch, rising light) that releases (flash, arcs, gold sparks, ring, shocks) |
| `swingTrail()` | trail with a refraction twin plus ember and spark emitters following the tip per metre |
| `frostHit(pos, dir)` | README example 1 (frost palette) |
| `slowmo(scale, dur)` `hitstop(sec)` `clear()` | time controls |

```
node tools/shot.mjs vfx --do "__ED.lab.play('swordImpact')" --at 0,0.033,0.083,0.15,0.3,0.5,0.8 --sheet-only --out shots/vfx/impact
```
