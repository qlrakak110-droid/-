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
[Mesh effects](#mesh-effects) (slash, ring, pillar, beam, bolt, spikes, debris, decal, speedlines, afterimage) ·
[Scheduler and presets](#scheduler-and-presets) · [Preset catalogue](#preset-catalogue) · [Library layers](#library-layers-vfxlib) ·
[Textures](#textures-sprite-and-noise-catalogue) · [Extending](#extending-sub-modules) · [Performance](#performance) ·
[Look guide](#look-guide) · [Examples](#worked-examples) · [Lab](#lab)

---

## Facade

| member | description |
|---|---|
| `vfx.prewarm(defs = [])` | Compile every VFX program (`renderer.compile` on the scene and `post.distortionScene`), upload the definition tables, and register `defs` (plus all of `vfx.lib`) so no row upload happens mid-fight. Call after defining presets. |
| `vfx.clear()` | Kill everything (round reset): particles, emitters, ribbons, lights (back to 0), flares, distortion, every mesh effect, pending scheduled callbacks. Rebases the VFX clocks to 0. |
| `vfx.now(realtime = false)` | Seconds on the VFX game clock (or real clock) since the last `clear()`. |
| `vfx.clock` | `{ game, real, now(realtime) }` (getters). |
| `vfx.schedule(delay, fn, { realtime })` | See [Scheduler](#scheduler-and-presets). |
| `vfx.define(name, fn)` / `vfx.play(name, at, opts)` / `vfx.presets()` | Composed presets; the library of ~50 presets in `presets/` is registered by `createVfx` (see [Preset catalogue](#preset-catalogue)). |
| `vfx.presetDefs` | The particle definitions the library presets use (registered by `vfx.prewarm()`). |
| `vfx.burst`, `vfx.emitter`, `vfx.particleDef` | [Particles](#particles-burst--emitter). |
| `vfx.trail`, `vfx.ribbon` | [Ribbons](#trails-and-ribbons). |
| `vfx.light`, `vfx.flare`, `vfx.distort` | Pooled point lights, flares, screen refraction. |
| `vfx.slash`, `vfx.ring`, `vfx.pillar`, `vfx.beam`, `vfx.bolt`, `vfx.spikes`, `vfx.debris`, `vfx.decal`, `vfx.speedlines`, `vfx.afterimage` | [Mesh effects](#mesh-effects). Look / kind tables: `vfx.slashLooks`, `ringLooks`, `pillarLooks`, `beamLooks`, `decalKinds`, `spikeKinds`, `debrisKinds`. |
| `vfx.lib`, `vfx.palette` | Tuned base particle layers and element palettes (`library.js`): `ember`, `frost`, `volt`, `eclipse` (gold-white corona around black), `dust` (ground dust / rubble). |
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
them at module scope anyway (an inline literal is hashed on every call): 384 definition rows exist (the preset library
uses 175, the game's generic set about 45) and the least recently used dead row is recycled when full.

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
| `kind` | `'glow'` | `'glow'` (white-hot pin + halo) · `'star'` (4 long + 4 short rays) · `'streak'` (anamorphic line) · `'ring'` · `'flash'` (wide soft bloom) · `'eclipse'` (a black disc, half the quad wide, that **occludes everything drawn before it** under a thin white-hot corona and uneven streamers: the black sun of KO / ultimate flashes; it is allocated in the last pool slot so it draws after the other flares, stays opaque for most of its life and lets the world back in as its envelope ends) |
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

Flares are premultiplied (`One, OneMinusSrcAlpha`): every kind writes alpha 0 (purely additive) except `'eclipse'`.
Capacity 64 (the oldest is stolen when full).

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

## Mesh effects

Shader-driven meshes (stage 2). Every type is **one pooled instanced mesh, one draw call for all its live
instances** (afterimage ghosts are the exception: one draw per ghost mesh), hidden when idle, animated analytically in
the shader from data written once at spawn (only following / moving ends are rewritten per frame). All run on game
time unless `realtime: true`, return a handle with `kill()` / `stop()` / `alive`, and are tracked into the running
preset group (anything they spawn themselves, such as a ring's refraction, a beam's end flares, a bolt's lights,
spike dust and shatter bursts, debris dust puffs, is killed with them).

**Colours** (slash, ring, pillar, beam, bolt, decal, afterimage): `palette` (a name in `vfx.palette`: `ember`,
`frost`, `volt`, `eclipse`, `dust`, or an object `{ core, mid, tail, smoke }`) picks three HDR colours: `core`
(white-hot edges, 1–3 frame heads), `mid` (the saturated body) and `tail` (where it cools to; looks marked *smoke*
take the palette's `smoke` instead). Override any of them with `core`, `color` (alias `mid`) and `tail` (colour-like:
`THREE.Color`, hex, or `[r, g, b]` linear HDR). `intensity` multiplies all three, `alpha` multiplies coverage.
`tailAdditive` (0..1) is how additive the cooled parts stay: 0 = they turn into occluding, alpha-blended dark matter.
Each effect has **looks / kinds**: named bundles of defaults; every field of a look can be overridden per call
(`vfx.slashLooks`, `vfx.ringLooks`, `vfx.pillarLooks`, `vfx.beamLooks`, `vfx.decalKinds`, `vfx.spikeKinds`,
`vfx.debrisKinds`). `scale` multiplies sizes (radius, width, height, travel).

**Orientation of planar effects** (slash, ring with `normal`): local X = `forward`, local Z = the plane `normal`,
local Y = Z × X. Pass `quat` (`THREE.Quaternion` or `[x, y, z, w]`), or `normal` + `forward` (+ `roll`, degrees
around `forward`); `facing: -1` mirrors across the fighter's YZ plane (P2). Angles in the plane are measured from
`forward` toward local Y, so with the default `normal [0, 0, 1]` (facing the camera) 0° is `forward`, 90° is up.

### `vfx.slash(opts) -> h`

Crescent slash arc: a band between the blade-tip path (the **cutting edge**, at `radius`) and an inner edge `width`
inside it, tapering to soft tips. The head sweeps from `arc[0]` to `arc[1]` in `sweep` seconds (outQuad); each point
of the arc is born when the head passes it, then cools (core → mid → tail) and erodes on its own clock, so the tail
breaks up first and the body thins toward the edge. The leading head is slanted (edge first) and hot.

| option | default | units | meaning |
|---|---|---|---|
| `pos` | `[0,0,0]` | m | arc centre (the pivot of the swing, e.g. the shoulder) |
| `look` | `'razor'` | | `'razor'` clean streaked arc, hot thin edge, breaks into lines · `'flame'` licking tongues off the edge, cools into dark smoke · `'ice'` crystalline cells, fracture lines, glints, shatters cell by cell · `'electric'` jagged filaments re-drawn at 30 Hz, flicker · `'eclipse'` near-opaque black body under a gold corona edge |
| `quat` / `normal`, `forward`, `roll`, `facing` | normal `[0,0,1]`, forward `[1,0,0]` | | plane (see above) |
| `arc` | `[-80, 80]` | deg | start → end angle of the sweep (either order: the sign sets the sweep direction) |
| `radius` | `1.4` | m | radius of the cutting edge |
| `width` | look (razor 0.42, flame 0.6, ice 0.45, electric 0.45, eclipse 0.5) | m | band width at its thickest |
| `sweep` | look (0.06–0.09) | s | time for the head to cross the arc (1–5 frames) |
| `life` | look (razor 0.34, flame 0.6, ice 0.62, electric 0.4, eclipse 0.5) | s | |
| `peak` / `taper` | look (~0.6 / 0.55–0.8) | 0..1 / power | where the crescent is thickest along the arc / tip softness |
| `thin` | look | 0..1 | how much the band thins toward the edge as it ages |
| `over` | look (0.2–0.75) | widths | extent drawn outside the edge (glow, flame tongues) |
| `edgeWidth` | look | widths | hot edge line width |
| `body` | look (1.2–1.6) | power | body density falloff toward the inner edge |
| `heat` | look | fraction of life | cooling time of each point (core → mid → tail) |
| `noise`, `noiseScale`, `scroll` | look | 0..1, 1/m, m/s | raggedness, pattern frequency, scroll speed along the arc |
| `cone` | `0` | widths | lifts the inner edge along the normal (a dished, 3D crescent) |
| `vel` | — | m/s | world velocity (travel) |
| `speed` | `0` | m/s | travel along the arc's middle direction (crescent projectiles / sword waves) |
| `expand` | `0` | 1/s | scale growth per second of travel (radius and width) |
| `drag` | `0` | 1/s | slows travel and expansion |
| `distort` | `0` | UV | refraction twin strength (0.015–0.04): a heat-bent band along the arc |
| colours, `intensity`, `alpha`, `tailAdditive`, `scale`, `follow`, `offset`, `realtime` | | | see above |

### `vfx.ring(opts) -> h`

Expanding shockwave band: the radius eases out (fast, then slow), the band widens, a hot leading edge and a soft
inner fade, seamless polar noise breakup and erosion. On the ground the outer part rises into a low curtain so the
ring still reads from the fight camera's grazing angle.

| option | default | units | meaning |
|---|---|---|---|
| `pos` | | m | centre (ground rings: lifted to `max(y, 0) + lift`) |
| `look` | `'shock'` | | `'shock'` energy · `'dust'` billowing alpha dust wave densest at its rolling front · `'fire'` tongues licking outward, cooling to smoke · `'frost'` crystalline cells and cracks · `'volt'` crackling filaments running around |
| `orient` | `'ground'` | | `'ground'` (normal up) · `'camera'` (billboard). Passing `normal` / `quat` gives any plane |
| `radius` | look (`[0.2, 3]` ...) | m `[start, end]` | |
| `width` | look | m `[start, end]` | band width (can exceed the radius: a filled disc with inner fade) |
| `life` | look (shock 0.45, dust 1.1, fire 0.7, frost 0.75, volt 0.4) | s | |
| `ease` | look (3–4) | power | radius ease `1 - (1-t)^ease` (4 = outQuart) |
| `height` | look (shock 0.12 … dust 0.5, fire 0.55) | m | curtain height of the outer part (ground looks) |
| `fill` | look | power | inner fade falloff (higher = thinner inside) |
| `over`, `noise`, `tiles`, `edgeWidth`, `erodeStart` | look | | outer extent (widths), raggedness, noise tiles around (integer), edge width, life fraction where erosion starts |
| `lift` | `0.025` | m | ground lift |
| `distort` | `0` | UV | adds a matching `vfx.distort` shock (same plane, radius, ~life), killed with the ring |
| colours, `intensity`, `alpha`, `tailAdditive`, `scale`, `follow`, `offset`, `realtime` | | | |

### `vfx.pillar(opts) -> h`

Vertical energy column: a narrow core shell and a wide sheath shell, shaded volumetrically from the view-facing ratio
of the cylinder (bright core line, soft rim-lit sheath), vertical scrolling streaks, organic wobble, twist, flared
base, ragged top. It shoots up (or down from the sky) in `rise` seconds, holds, then the core thins and the sheath
swells and erodes. `stop()` jumps to the decay (0.3 s).

| option | default | units | meaning |
|---|---|---|---|
| `pos` | | m | base point |
| `look` | `'fire'` | | `'fire'` eruption with flame tongues and a smoky top · `'frost'` faceted crystalline sheath with glints · `'volt'` blinding thin core from the sky, crackling vertical filaments · `'eclipse'` black occluding core inside a gold corona |
| `dir` | `[0, 1, 0]` | | column axis |
| `radius` / `height` | look (fire 0.55 / 4.5, volt 0.3 / 9) | m | core radius, column height |
| `sheath` | look (~2) | × radius | sheath radius |
| `from` | look (`'ground'`, volt `'sky'`) | | grows up from the base, or descends from the top |
| `rise` | look (0.05–0.15) | s | |
| `fade` | look (0.25–0.55) | life fraction | when the decay starts |
| `flare`, `twist`, `spin` | look | ×, rad/m, rad/s | base widening, helical twist, rotation |
| `noise`, `scroll` | look | 0..1, m/s | wobble / ragged top, streak scroll speed |
| `life` | look (fire 1.0, frost 1.1, volt 0.55, eclipse 1.4) | s | |
| colours, `intensity`, `alpha`, `tailAdditive`, `scale`, `follow`, `offset`, `realtime` | | | |

### `vfx.beam(opts) -> h`

Beam between two points: a strip turned around its axis to face the camera, a hot core inside a streaky scrolling
sheath, travelling pulses, lateral wiggle, width pulse and taper. It extends from the source with an eased head,
sustains, then releases (width collapses while noise erodes it). A glow flare sits on the muzzle and rides the head.

| option | default | units | meaning |
|---|---|---|---|
| `from`, `to` | | position, `Object3D` or function | end points; `Object3D` / functions are followed every frame |
| `look` | `'energy'` | | `'energy'` · `'fire'` (turbulent flame sheath, smoky) · `'frost'` (crystalline sheath) · `'volt'` (crackling filaments) · `'eclipse'` (black core, gold corona) |
| `life` | `Infinity` | s | sustain until `stop()`; a finite life releases by itself at the end |
| `width` | look (0.45–0.7) | m | |
| `coreWidth` | look (0.1–0.3) | fraction | core gaussian width (of the half-width) |
| `extend` / `release` | look | s | head travel time / release time |
| `wiggle` | look | m | lateral wander (zero at both ends) |
| `taper` | look | `[start, end]` m | narrower muzzle / tapered head |
| `noise`, `scroll` | look | | sheath density, scroll speed (m/s, source → target) |
| `flares`, `flareSize` | `true`, `1` | | muzzle and head glow flares (follow the live ends) |
| colours, `intensity`, `alpha`, `tailAdditive`, `scale`, `realtime` | | | |

Handle: `setEnds(a, b)` (pass `null` to keep one end; positions or live `Object3D` / functions), `stop()` (release),
`kill()`, `alive`.

### `vfx.bolt(opts) -> h`

Lightning: a main channel by 3D midpoint displacement (2^`detail` segments, each midpoint's offset proportional to its
segment length) plus forked branches and sub-branches that taper to their tips, as camera-facing strips with a thin
white-hot core and a wide glow. Stroke 1 grows from `from` as a stepped leader (`leader` s); its flash, impact flare
and light fire when it connects. Return strokes re-flash the same channel (coarse shape kept, fine detail and branches
re-drawn). Brightness flickers per frame; after the last stroke the channel cools and erodes along its length.

| option | default | units | meaning |
|---|---|---|---|
| `from`, `to` | | position, `Object3D` or function | sampled at every stroke |
| `palette` / colours | `'volt'` | | `core` = channel, `mid` = glow |
| `width` | `0.32` | m | strip width of the main channel (the glow); branches 0.5×, sub-branches 0.28× |
| `core` | `0.11` | fraction | core width within the strip |
| `glow` | `1` | | glow strength |
| `detail` | `7` | 4..8 | 2^detail segments in the main channel |
| `roughness` | `0.24` | | displacement / segment length |
| `branches` | `5` | | forks per stroke (about half get a sub-branch) |
| `strikes` | `3` | | strokes; with a long `life` and many strikes it becomes a crackling arc |
| `interval` | `[0.05, 0.11]` | s | gap between strokes |
| `leader` | `0.035` | s | stepped leader time of stroke 1 (0 = instant) |
| `flicker` | `0.55` | 0..1 | per-frame brightness flicker |
| `cool` | `0.25` | s | afterglow cooling time |
| `life` | `0.5` | s | |
| `light`, `lightRange` | `0`, `8` | cd, m | pooled light flash at `to` on every stroke (0 = none) |
| `impact` | `true` | | glow flare at `to` per stroke (+ a wide flash on the first) |
| `intensity`, `scale`, `realtime` | | | |

### `vfx.spikes(opts) -> h`

Lit shards erupting from the floor with a staggered, overshooting punch, a hold, then a **shatter** (cracks flare, the
shard dissolves from noise, debris, shard sprites and glints fly) or a **sink** back into the ground; a dust puff at
every base. The material is a `MeshStandardMaterial` (scene lights, the pooled VFX lights and `scene.environment`
reflections) with flat-shaded facets, a fresnel rim, parallax interior fractures, a glowing base, stylised per-facet
sky light, and, when `scene.environment` is set, environment "refraction" through the crystal.

| option | default | units | meaning |
|---|---|---|---|
| `pos` | | m | line start / cluster or ring centre (on the floor; `y` option, default 0) |
| `kind` | `'ice'` | | `'ice'` (shatters) · `'rock'` (sinks) · `'crystal'` violet magic crystal (shatters) · `'magma'` rock with glowing fissures (sinks) |
| `pattern` | `'line'` | | `'line'` along `dir` · `'cluster'` big centre spike, smaller ones leaning out · `'ring'` around `pos`, leaning out |
| `dir`, `facing` | `[1, 0, 0]` | | line direction on the floor (`facing: -1` mirrors x) |
| `length` / `radius` | `4` / cluster 0.7, ring 1.2 | m | |
| `count` | line 7, cluster 7, ring 10 | | |
| `height` | line `[0.7, 1.5]`, else `[0.8, 1.8]` | m range | |
| `grow` | line `[0.55, 1.15]` | | height ramp from the first to the last spike of a line |
| `width` | `0.2` | × height | base radius |
| `stagger` | line 0.04, else 0.025 | s | delay between spikes |
| `rise`, `overshoot` | `0.09`, `2.2` | s, outBack | |
| `hold` | `0.7` | s | |
| `end`, `endTime` | kind, shatter 0.22 / sink 0.45 | `'shatter'`/`'sink'`, s | |
| `tilt` | `16` | deg | lean away from the line / centre |
| `albedo`, `emissive`, `glow`, `roughness` | kind | linear, HDR, 0..1 | material overrides |
| `dust`, `debris`, `shards` | `true` | | ground puffs at the base, shatter debris, shatter sprites |
| `scale`, `realtime` | | | |

Handle: `kill()`, `stop()` (end the hold now; shatter bursts are rescheduled to match), `alive`.

### `vfx.debris(opts) -> h`

Chunky lit fragments (three irregular faceted shapes, random proportions): ballistic flight with drag, exact bounces
on the floor (the chunk's centre rests one radius above it), spin that dies on landing, pop-in and shrink-out. Same lit
material approach as spikes. Dust puffs (alpha particles) where the bigger chunks first land.

| option | default | units | meaning |
|---|---|---|---|
| `pos`, `dir` (up), `side`, `vel`, `scale` | | | as for particle `at` |
| `kind` | `'rock'` | | `'rock'` · `'ice'` (cold fresnel rim) · `'ember'` (glowing fissures cooling to black) · `'crystal'` (inner glow) |
| `count` | `12` | | × `quality.particleScale` |
| `shape` | `{ type: 'disc', radius: 0.25 }` | | `'disc'` / `'sphere'` / `'point'` spawn volume |
| `spread` | `50` | deg | cone around `dir` |
| `size` | `[0.05, 0.2, 2]` | m range | chunk diameter |
| `speed` | `[3, 8, 1.3]` | m/s range | (× √scale) |
| `life` | kind (`[1.6, 2.6]` …) | s range | |
| `spin` | `[3, 14]` | rad/s range | |
| `gravity`, `drag`, `bounce`, `friction` | kind, `0.4`, kind, `0.55` | m/s², 1/s, 0..1, 0..1 | |
| `albedo`, `emissive`, `heat`, `roughness` | kind | | material overrides |
| `stagger` | `0.02` | s | spawn spread |
| `dust` | kind (rock, ember) | | dust puffs on first landing |
| `realtime` | | | |

### `vfx.decal(opts) -> h`

Procedural floor decal on `y = 0` (lifted 6 mm, polygon offset; all decals one draw call). Dark parts are alpha
blended (they darken the floor), hot parts are additive, in the same fragment.

| option | default | units | meaning |
|---|---|---|---|
| `pos` | | m | centre (x, z); `y` option (default 0) for raised floors |
| `kind` | `'crack'` | | `'crack'` branching ground cracks propagating from the centre, lit lips, shattered crater, optional `magma` · `'scorch'` burnt blast mark, radial streaks, smouldering embers · `'frost'` frost spreading with a glowing front, crystal lines, twinkles, melting away · `'rune'` magic circle: layered rings rotating at different speeds, a glyph band, heptagram, ticks, spokes, drawn on layer by layer · `'glow'` soft flickering light pool |
| `radius` | kind (crack 1.8, scorch 1.4, frost 2, rune 1.6, glow 2) | m | |
| `life`, `fadeIn`, `fadeOut` | kind | s | fade-out is a noise erosion (rune and glow also dim) |
| `reveal` | kind (crack 0.14, frost 0.45, rune 0.45) | s | crack propagation / frost spread / rune draw-on time |
| `magma` | crack 0, scorch 1 | 0..1 or bool | emissive magma in the cracks / embers in the scorch |
| `cool` | crack 2.2, scorch 1.4 | s | magma / ember cooling time (white-yellow → orange → deep red → black) |
| `spin` | rune 0.7 | rad/s | rune ring rotation (layers turn at different rates and directions) |
| `density` | `1` | | crack count / rune line weight |
| `dark` | kind | colour | colour of the alpha-blended parts (cracks, scorch, frost milk) |
| `rotation` | random | rad | |
| colours, `intensity`, `alpha`, `scale`, `follow`, `offset`, `realtime` | rune default palette `eclipse` | | |

`stop()` starts the fade-out now.

### `vfx.speedlines(opts) -> h`

Full-screen anime speed lines, camera attached (built in clip space; depth test off; render order 40). Each line has
its own width, start radius / length and brightness, re-drawn ("boiling") at `boil` Hz.

| option | default | units | meaning |
|---|---|---|---|
| `mode` | `'focus'` | | `'focus'` radial wedges converging on a point with a clear centre (drawn on an annulus: the centre costs no fill) · `'directional'` parallel scrolling streaks |
| `screen` | `[0.5, 0.5]` | screen fraction | focus centre (0,0 bottom left) |
| `pos` | — | world position / `Object3D` / function | focus on a world point, re-projected every frame |
| `life` | `0.45` | s | `Infinity` until `stop()` |
| `style` | `'light'` | | `'light'` additive HDR lines · `'ink'` dark alpha-blended lines (bright scenes, manga) |
| `color`, `intensity`, `alpha` | light `[1.25,1.22,1.18]` / ink near-black | | |
| `density` | focus 150, directional 26 | | angular bins / lines across |
| `inner` | `0.55` | screen half-heights | clear radius |
| `boil` | `20` | Hz | re-draw rate |
| `dir`, `speed` | `[1, 0]`, `6` | screen direction, half-heights/s | directional mode |
| `attack`, `release` | `0.03`, `0.18` | s | |
| `thickness` | `1` | × | line width |
| `realtime` | `false` | | (game time: lines freeze in hit-stop; pass true to keep them boiling) |

### `vfx.afterimage(object3D, opts) -> h`

Fading ghost copies of a hierarchy. A snapshot copies every visible `Mesh`'s world matrix and, for a `SkinnedMesh`,
its current bone matrices into a frozen skeleton (the pose of that instant), sharing the source geometry. Look:
additive fresnel shell (rim-lit silhouette, faint fill), core → mid colours, drifting, eroding with world-space noise.
Slots (a plain and a skinned mesh, a preallocated 64-bone frozen skeleton and a material instance of one shared
program each) are pooled: 10 high / 8 mid / 4 low ghost meshes, and one afterimage copies at most 4 / 3 / 2 of a hero's meshes (in traversal order): a ghost re-draws whole character meshes (~58k triangles per hero), so the pool is the per-tier geometry cap (the oldest ghost mesh is recycled first).

| option | default | units | meaning |
|---|---|---|---|
| `life` | `0.35` | s | per ghost |
| `count`, `interval` | `1`, `0.045` | , s | ghosts snapshotted over time (a dash trail) |
| `palette` / colours | `'frost'` | | |
| `intensity`, `alpha` | `1` | | |
| `fill`, `fresnel` | `0.05`, `2.6` | , power | inner fill, rim sharpness |
| `drift`, `swell` | `[0,0,0]`, `0.03` | m/s, m | ghost drift, outward growth over life |
| `erodeScale` | `1.6` | 1/m | erosion noise frequency |
| `maxMeshes` | `8` | | meshes per snapshot (draw calls) |
| `filter` | — | `(mesh) => bool` | which meshes to copy (the mesh list is cached per object at the first call) |
| `realtime` | `false` | | |

Handle: `stop()` cancels pending snapshots (existing ghosts fade), `kill()` removes all its ghosts, `alive`.
Cost: one draw call per ghost mesh (a 6-mesh character with 4 ghosts alive = 24 draws): keep `count` × meshes small,
or `filter` to the main body meshes.

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

A preset function may **return an object of extra members**; they are merged onto the group handle. Getters stay live
(a projectile's `pos`), functions run inside the group (what they spawn is killed with it), and a returned `stop` runs
before the default `stop` (which stops every handle of the group). The library presets below use this for projectile
`impact()` and loop `stop()`.

---

## Preset catalogue

`src/vfx/presets/` (one file per family: `combat.js`, `ember.js`, `frost.js`, `volt.js`; shared kits and helpers in
`common.js`, pooled moving anchors in `motion.js`) is installed by `createVfx` itself: every name below is registered
before your own code runs, and `vfx.prewarm()` uploads all of their particle definitions (`vfx.presetDefs`) and
compiles every program they use. Presets spawn **world-space VFX only**: no camera moves, no post pulses, no sound;
the presentation layer adds those.

```js
vfx.play('hit.heavy', { pos: contact, dir: strikeDir, facing: 1, scale: 1 }, { element: 'ember' });
const w = vfx.play('ember.wave', { pos: [x, 0, 0], facing: -1 }, { follow: projectileProxy });  // game-driven
w.impact();                                     // on the hit event: fire flower where the wave is now
const aura = vfx.play('volt.aura', { pos: feet, target: fighter.root });   // loops until stopped
aura.stop();
```

**`at` conventions.** `pos` is what the table says (a contact point, a swing pivot, a floor point ...). `dir` is the
direction of the action (strike direction for hits, thrust axis, travel direction); it defaults to the fighter's
forward `(facing, 0, 0)`. `facing` (±1) mirrors every arc and offset for P2. `scale` scales sizes, distances and speeds
(1 = the 1.9 m fighter; a 7–9 m colossus uses 4). `target` is a follow object (auras, trails, dash ghosts) or an end
point (chain lightning). `color` is accepted but the element palettes are authored, not tinted.

**Common options** (every preset): `intensity` (default 1; brightness and particle counts, 0.5–2), `realtime` (true:
everything runs on real time — KO slow motion, super-freeze; `ult.flash` defaults to real time). Hits and guards also
take `flashRealtime` (default true: the white core, glints, the cut crescent, rings and the light run on real time, so they bloom
**during** hit-stop while sparks, smoke and debris wait for game time and burst out when it resumes; false puts
everything on game time).

**Handles.** `vfx.play` returns the group handle (`kill()`, `stop()`, `alive`). Loops (`*.aura`, `charge.gather`,
`dust.slide` with a follow target) run until `stop()` or `opts.duration`. Projectiles (`ember.wave`, `frost.shard`,
`volt.javelin`) add `impact(pos?, dir?)`, `pos` (live `Vector3`) and `anchor` (the `Object3D` the body follows); their
motion comes from `opts.follow` / an `Object3D` or function in `at.target` (the game moves it), else `opts.to` (flies
there and impacts by itself), else `opts.speed` along `at.dir` for `opts.life` seconds (then fizzles).
Each projectile also has its impact as a preset of its own (`ember.wave.impact`, `frost.shard.impact`,
`volt.javelin.impact`, at = the burst point).

**Aliases for the presentation layer.** Every combat preset is also registered as `combat.<name>`
(`combat.hit.light` ...); `combat.hit.launch` / `crumple` / `knockdown` play `hit.heavy`. `ember.hit`, `frost.hit` and
`volt.hit` pick `hit.light` / `hit.heavy` / `hit.crit` / `hit.pierce` from `opts.k` (< 0.75 light, ≥ 1.3 crit),
`opts.level` (`'heavy'`, `'crit'`, `'pierce'`) and `opts.counter`, in their element.

### Combat (element-neutral steel white-gold; `opts.element`: `'ember' | 'frost' | 'volt' | 'steel'`)

| name | `at.pos` | what it is | options |
|---|---|---|---|
| `hit.light` | contact point | 2-frame flash, radial impact lines, a quick cut crescent through the contact (in front of the body), short directional spark spray, streak glint, a wisp of lingering dust, small light | `element` |
| `hit.heavy` | contact point | flash, star glint, impact lines, thick cut crescent, a shock disc around the strike axis, sparks with floor bounces, motes, element accent (fire licks / ice shards / crackle arcs / hot steel chips), a lingering puff (lit dust, dark smoke with an underglow, pale mist, ozone), refraction shock | `element` |
| `hit.crit` | contact point | X-cut (two crescents 40 ms apart, both on the flash clock), flash, star, many impact lines, axial shock disc, heavy spark shower, element debris (ember licks, frost shards, volt bolts, steel chips), lingering puff and smoke, floor dust under a low hit, shock | `element` |
| `hit.pierce` | contact point (`dir` = thrust axis) | a line of light through the body, an exit cone of long sparks, impact lines, two shock discs along the axis, lingering puff, axial shock | `element` |
| `guard.block` | guard contact | glancing steel spark fan, impact lines, a parry shock disc facing the attacker, star glint, hot steel chips, light | `perfect` (bigger cold glint, hex flakes lighting up the guard plane, glitter, refraction pulse) |
| `guard.break` | guard contact | the barrier shatters: a pane of crystalline cells cracks apart in a few frames, crystal shards and hex flakes spin, fall and bounce, flash, shock disc, impact lines, steel sparks, lingering dust, shock | |
| `dust.step` | foot (floor) | small dust puff and motes | |
| `dust.dash` | feet (floor) | low dust cloud blown backward (−facing), grit, motes | |
| `dust.land` | feet (floor) | dust ring (mesh) and puffs, pebbles | `heavy` (floor shock, rocks, small crack) |
| `dust.slide` | foot (floor) | skid dust and grit. With `follow` (or an `Object3D` `at.target`) it emits while the foot moves, until `stop()` / `duration`; otherwise lays a skid of `length` (1.6 m) behind `pos` | `follow`, `offset`, `duration`, `length` |
| `whoosh.light` / `whoosh.heavy` | swing pivot (shoulder) | faint pale air crescent with a refraction twin and wind streaks; heavy adds wake dust and floor dust when low | `arc` ([120, −30] / [140, −50] deg), `radius` (1.3 / 1.7), `normal`, `forward`, `roll` (vfx.slash plane) |
| `charge.gather` | gather point (hand / weapon) | **loop**: converging streaks and motes, imploding ring pulses, a growing glow and star, lens pinch, rising light | `element` (+ `'eclipse'`), `follow`, `offset`, `rune` (floor circle), `duration` (default until `stop()`), `release` (play `charge.release` at the end of `duration`) |
| `charge.release` | release point | flash, streak, ring snapping outward, radial sparks, glitter, smoke, double shock | `element` |
| `ko.burst` | victim chest | the black sun: an `'eclipse'` flare (a black disc that occludes the flash behind it, gold-white corona) after a 2-frame flash, star and streak, cut crescent, crit sparks both ways, rising light embers, floor blast (soft shock ring, dust, cracks, rocks, glow), smoke column | `element` |
| `ult.flash` | user chest | super-freeze activation (real time by default): flash, the black-sun `'eclipse'` flare, long star rays, ring, backlight column behind the fighter, rune circle under the feet, sparks, shock | `element` (default `'eclipse'`) |

### Ember — Kael, the Cinder Warden

Heavy, slow, huge arcs of flame that cool into black smoke; magma bleeding through split stone; buoyant flames,
embers and smoke columns rise while molten rock falls and bounces; burning ash flutters down; heat haze.

| name | `at.pos` | what it is | options |
|---|---|---|---|
| `ember.slash` | swing pivot (shoulder) | flame crescent with a razor-hot edge; embers, flames and dark wisps peel off along the arc as the head passes; sparks off the end; heat haze; bites the floor when the arc reaches it | `arc` ([135, −35]), `radius` (1.55), `width` (0.65), `sweep` (0.08 s), `normal` ([0, 0.2, 1]), `forward`, `roll` |
| `ember.slash.heavy` | swing pivot | two-layer flame arc (2 m), big end burst, falling ash; floor bite: magma crack, scorch, fire ring, molten debris, flame petals, smoke | as `ember.slash` (`arc` [150, −42], `radius` 2.0, `width` 0.95, `sweep` 0.11) |
| `ember.trail` | weapon tip | weapon trail that glows, then cools into a smoky occluding tail, with heat refraction; embers, sparks, flames and smoke shed per metre from the tip | `a` (base socket), `b` (tip socket), `life` (0.26 s), `duration` (auto stop) |
| `ember.aura` | feet | **loop**: flames licking up the body and around the feet, rising embers and burning ash, dark smoke over the shoulders, heat haze, floor glow, flickering light | `follow` (or `at.target`), `duration` |
| `ember.eruption` | floor point | the floor splits (magma crack, spitting sparks, pebbles), then a magma column with a fireball plume, molten and stone debris, fire and dust rings, rising embers, smoke column and ash | `count` (> 1: a crack races forward and `count` columns erupt along it), `spacing` (1.5 m), `interval` (0.08 s) |
| `ember.wave` | its foot on the floor | **projectile**: a 2.2 m burning crescent travels along `dir` (11 m/s), streaming flames, falling cinders, a molten groove that cools to black scorch, heat haze; `impact()` = fire flower | `follow`, `to`, `speed`, `life` (0.9 s) |
| `ember.explosion` | body (hips / chest) | flash, clustered fireball cooling to smoke, flame petals, sparks, molten debris, 360° floor fire ring, scorch and magma cracks, double shock, smoke column, ash | |
| `ember.meteor` | impact point (floor) | a fireball falls from high behind the user trailing flames, smoke and embers while a glow grows on the floor, then craters: magma rim rocks (spikes), cracks, fire column splash, fire and dust rings, debris, smoke | `height` (8 m), `fall` (0.5 s) |
| `ember.inferno` | centre (floor) | **ultimate**, ~3.4 s: rune of the black sun, racing fire ring, fire pillars erupting around the centre one by one, a swirling firestorm under a smoke ceiling, then the centre detonates (explosion + huge column) | `radius` (3 m), `duration` (3 s) |

### Frost — Iska, the Froststar Oracle

Fast, precise, airy: thin crisp crescents and hard crystal geometry, four-point star glints, glitter that hangs and
drifts down, snowflakes, pale cold mist that sinks and creeps along the floor (never dark smoke).

| name | `at.pos` | what it is | options |
|---|---|---|---|
| `frost.slash` | swing pivot | crystalline crescent with a starlight edge and a faint sheen; glints and snow hang in its wake; a star glints at the tip; mist sinks below | `arc` ([−150, 30], rising), `radius` (1.25), `width` (0.38), `sweep` (0.05), `normal` ([0, −0.3, 1]), `twin` (second, reversed blade), `forward`, `roll` |
| `frost.slash.heavy` | swing pivot | two concentric crescents (both blades), shard spray and a star ring off the tip, ice chips, frost on the floor when low | as `frost.slash` (`arc` [−160, 40], `radius` 1.5) |
| `frost.trail` | weapon tip | thin starlight trail with a hard white edge; glints, snow and a breath of mist from the tip | `a`, `b`, `life` (0.17 s), `duration` |
| `frost.aura` | feet | **loop**: slow snowfall from above the head, star glints orbiting the body, cold mist pooling from the feet over a frost patch, cool light | `follow`, `duration` |
| `frost.spikes` | start (floor) | a line of ice spikes races forward along `facing`, each larger than the last, ending in a huge cluster with a frost ring and star; frost, mist and glints run along the line with a travelling cold light; spikes hold, then shatter | `length` (7 m), `count` (8), `hold` (0.6 s) |
| `frost.shard` | launch point | **projectile**: a crystal lance of starlight with a star at its head, thin frost ribbon, glints shed behind (14 m/s); `impact()` shatters it (shards, glints, ring, frost on the floor) | `follow`, `to`, `speed`, `life` (1 s) |
| `frost.nova` | floor point | radial freeze: a frost rune snaps open, crystalline ring and frost sweep outward, a ring of ice spikes erupts and a crystal cluster encases the target, low mist, glitter, snow, floor shock | `encase` (true) |
| `frost.shatter` | crystal centre | star flash, 80 shards and lit ice / crystal chunks flying and bouncing, sparkling glitter and snow, mist, frost and a ring on the floor below, shock | |
| `frost.blizzard` | the caster's feet (floor) | **ultimate**, ~3.4 s: a tall crescent wall of ice light rolls forward along `facing` trailing luminous mist, rimes the floor and raises a growing field of crystal clusters behind it, while a gale of snow streaks and flakes blows across the arena; at the end the crystals shatter and glitter hangs in the air | `length` (12 m), `travel` (1.6 s), `duration` (3.2 s) |
| `frost.starfall` | floor point | star lances: a star kindles high above, a lance of starlight streaks down, a crystal stabs the floor with a frost ring, shards, glints and a shock | `count` (1), `radius` (scatter, 1.6 m), `interval` (0.08 s), `height` (9 m) |

### Volt — Vorn, the Stormcaller Lancer

Instantaneous and straight: lines along the thrust axis, jagged branching bolts, rings punched around the spear's
axis, strobing flicker, gold sparks that bounce, dark scorch and thin ozone wisps. It strikes, crackles and is gone.

| name | `at.pos` | what it is | options |
|---|---|---|---|
| `volt.thrust` | hand / thrust origin (`dir` = thrust axis) | a lightning line to the tip, three rings punched around the axis in sequence, bolts forking ahead of the tip, gold spark cone, axial shock | `reach` (2.4 m) |
| `volt.slash` | swing pivot | electric crescent with a white edge, gold sparks and arcs off the tip, crackle along the arc, a small bolt grounding to the floor | `arc` ([160, −20]), `radius` (1.55), `width` (0.45), `sweep` (0.07), `normal` ([0, 0.45, 1]), `forward`, `roll` |
| `volt.trail` | weapon tip | thin crackling violet trail with a white edge; gold sparks and arcs from the tip | `a`, `b`, `life` (0.14 s), `duration` |
| `volt.aura` | feet | **loop**: small bolts jump between points on the body every 70–160 ms, arcs crawl, ionised motes rise, gold sparks drip and bounce, strobing light | `follow`, `duration` |
| `volt.strike` | floor point | sky bolt with return strokes, column of light, scorch and cracks, crackling ring, gold sparks, arcs, rocks, ozone wisps | `huge` (×1.5, side bolts, big shock), `warn` (s: a rune marks the spot and crackles first) |
| `volt.chain` | start point (`at.target` = end, default 3 m along `dir`) | chain lightning: a main arc with return strokes plus a thinner companion, glowing contacts, gold sparks and arcs at both ends | `strikes` (4), `life` (0.42 s) |
| `volt.dash` | start (floor) | the body becomes a streak of lightning (beam at chest height), ghosts of `at.target` (`Object3D`), a bolt racing along the floor, scattered scorch, gold sparks and arcs, bursts at both ends | `to` (end) or `length` (4 m), `ghosts` (6), `speedlines` (screen lines, off) |
| `volt.burst` | centre | radial lightning: bolts lash out (grounding when they reach the floor), gold sparks, arcs, motes, a tilted crackling ring, shock, scorch when low | |
| `volt.storm` | centre (floor) | **ultimate**, ~3.6 s: a rune spreads and crackles, storm clouds lit from inside, rain lashes down, energy is drawn up, eight bolts strike around in a stutter, then a huge strike plus a lightning burst at the centre (2.7 s) | `radius` (3.4 m), `strikes` (8) |
| `volt.javelin` | launch point | **projectile**: a 1.7 m lance of lightning with a white head streak, crackling ribbon, gold sparks and arcs shed behind (20 m/s); `impact()` = lightning burst with arcs chaining into the floor | `follow`, `to`, `speed`, `life` (0.8 s) |

### Writing presets with the library helpers

Fighter choreography can register its own presets with `vfx.define` and build them from the same parts the library
uses. `src/vfx/presets/common.js` exports (all plain ES exports):

| export | what it is |
|---|---|
| `def(d)` | register a module-scope particle definition (collected in `DEFS` = `vfx.presetDefs`, uploaded by `vfx.prewarm()`); never pass inline definition literals in a preset body |
| `KIT[el]` | hit kit per element (`'steel' 'ember' 'frost' 'volt'`): `flash` (2–3 frame burst), `lines` (radial impact lines), `splash`, `sparks`, `fine`, `puff` (dim glow), `dust` (lingering puff along the strike), `accent` (fire licks / ice shards / crackle arcs / hot steel chips), `motes` (embers / glitter / arcs / steel motes), `smoke` |
| `EL`, `STEEL`, `GOLD` | palettes by element (`{ core, mid, tail, smoke }`, linear HDR) |
| `SLASH_LOOK[el]`, `MESH_PAL[el]` | the `vfx.slash` look and mesh palette name for an element |
| `meshColors(P, extra)` | `{ core, color, tail }` mesh-effect colour options from a palette |
| `cutThrough(pos, dir, facing, r, half, roll)` | slash options for a crescent of radius `r` whose middle crosses `pos` across the strike `dir` |
| `arcPoint(pos, plane, deg, r)`, `arcTangent(plane, deg, sign)` | points and sweep tangents on a `vfx.slash` arc (spawn-time helpers, they allocate) |
| `lightAt(p, dz = 1.5, dy = 0.2)` | where to put an event light: toward the camera, off the bodies |
| `floor(p, lift)`, `vec(v)`, `key(t, c, a, k)`, `mul(c, k)` | small coercion helpers (ramp keys from palette colours) |
| `DUST`, `DUST_SMALL`, `PEBBLES`, `SMOKE_COLUMN`, `DUST_MOTES` | shared ground / smoke layers |
| `realtimeView(vfx)` | a view of `vfx` whose spawns and schedules default to real time (KO slow motion, super-freeze) |

```js
import { def, KIT, EL, meshColors, cutThrough, lightAt } from '../vfx/presets/common.js';
const SHOCK_SPARKS = def({ ...KIT.volt.sparks, count: 30, spread: 12 });           // module scope
vfx.define('vorn.counter', (v, at) => {
  const E = EL.volt, p = at.pos, d = at.dir;
  v.burst(KIT.volt.flash, { pos: p, scale: 0.5, realtime: true });
  v.burst(KIT.volt.lines, { pos: p, count: 12, realtime: true });
  v.slash({ ...cutThrough(p, d, at.facing, 0.6, 40, 0), look: 'electric', ...meshColors(E), width: 0.22, realtime: true });
  v.burst(SHOCK_SPARKS, { pos: p, dir: d });
  v.burst(KIT.volt.dust, { pos: p, dir: d, count: 3 });
  v.light({ pos: lightAt(p), color: E.core, intensity: 45, duration: 0.25, decay: 'outExpo', realtime: true });
});
```

The projectile and travelling-front machinery (`presets/motion.js`: pooled anchors, `launch()`) is internal to the
presets module; reuse it through the library projectiles (`ember.wave`, `frost.shard`, `volt.javelin`) or drive your
own `Object3D` and pass it as `follow` to the spawn functions.

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
| `EffectPool` | pooled-effect base: fixed slots, birth time on either clock, life, follow (`pool.place(slot)`), stale-safe handles, oldest-steal; `alloc({ life, realtime, last })` (`last: true` takes the highest free slot: drawn after the others in an instanced layer) |
| `InstanceRing`, `makeQuadGeometry` | instanced quad + interleaved per-instance buffer with partial uploads (`alloc`, `dirty`, `commit`) |
| `ParamTable`, `tableGlsl(sampler, prefix)` | definition rows in a float texture (ramp + curves + params) and their GLSL accessors (`<p>Ramp(t,row)`, `<p>Curve`, `<p>Param`) |
| `InstanceRing(capacity, layout, baseGeometry?)` | pass your own `InstancedBufferGeometry` template (arc strip, cylinder grid, chunk) to instance it instead of the quad |
| `track(handle)` | add a handle to the running preset group (EffectPool handles are tracked automatically) |
| `currentGroup()`, `runInGroup(group, fn)` | group plumbing for deferred work |

Render-order bands (`util.RENDER_ORDER`): alpha particles 10, alpha meshes (decals) 12, rings 14, pillars 15, beams and
afterimages 16, slashes 17, bolts 19, additive particles 20, ribbons 22, flares 30, speed lines 40. Every VFX mesh sits
at the origin, so three orders same-band meshes by creation order: the mesh bands put big volumes first and blade
effects last, so occluding parts (eclipse looks, flame smoke) darken what lies behind them. Lit mesh effects (spikes,
debris) are opaque `MeshStandardMaterial`s (depth writes, dissolve by `discard`) and render in the opaque pass.

Mesh-effect helpers (stage 2):
- `meshfx.js`: `gridGeometry(nu, nv, layers)` (instanced template grid, `position = (u, v, layer)`), `MeshLayer`
  (EffectPool slot i ↔ instance i of an InstanceRing, signed life float zeroed on free, optional refraction twin in
  `post.distortionScene`, `visit(slot, age)` hook, `follow()`, `setLife()`), `PREMUL` / `ADDITIVE` blending presets,
  `resolveColors(opts, look, out)`, `planeQuat(opts, out)`, `axisQuat(dir, out)`.
- `glsl.js`: `GLSL_COMMON` (hashes, value noise, jagged `lnoise`, eases, `qrot`, `heat3` core → mid → tail ramp),
  `GLSL_VORONOI` (`voronoi`, periodic `voronoiP`, periodic `lnoiseP`), `GLSL_BALLISTIC` (exact drag + floor bounce),
  `CULL`.
- Lit effects extend `MeshStandardMaterial` in `onBeforeCompile` (motion at `<beginnormal_vertex>` /
  `<begin_vertex>`, emissive at `<emissivemap_fragment>`) and set `customProgramCacheKey`. All VFX materials are `transparent`, `depthWrite: false`, premultiplied
(`blendSrc: One, blendDst: OneMinusSrcAlpha`, output `vec4(rgb * a, a * (1 - additive))`), so one material can be
additive, alpha-blended or anything in between.

---

## Performance

- Draw calls: one per layer / effect type: particles (alpha, add, distortion), flares, distortion sprites, ribbons (+
  refraction), slash (+ refraction), ring, pillar, beam, bolt, decal, debris, spikes, speed lines: about 17 if every
  type is alive at once, plus one per afterimage ghost mesh; **zero when idle** (every layer hides itself).
- Triangles: the mesh-effect templates are dense (slash 1.5k, ring 1.5k, beam 0.8k, pillar 3.1k triangles per
  instance) and the vertex shader culls dead instances, so each layer draws only up to its **highest live slot**
  (slots are taken lowest-first), recomputed every frame: an idle-then-busy history never leaves 24 dead slashes in
  the draw.
- Programs: 26 for the whole library (high and low tier); `vfx.prewarm()` compiles all of them, and the count does
  not change after playing every effect (verified). Create the environment (which sets `scene.environment`) **before**
  `vfx.prewarm()`, or the lit spikes / debris compile an env-mapped variant on first use.
- Mesh-effect capacities: slash 24, ring 32, pillar 16, beam 12, bolt 24 (360 points each), decal 48, spikes 96
  shards, debris 256 / 192 / 128 chunks (high / mid / low), speed lines 4, afterimage 10 / 8 / 4 ghost meshes. The
  oldest instance is stolen when full.
- **Preset library** (measured, `node tools/shot.mjs vfx --scenario ...`, lab stage of 15 draw calls): a hit costs
  50–200 live particles and 3–8 VFX draw calls; skills 40–290; ultimates 500–1050 at their peak. Worst case, all three
  ultimates overlapping (`overlap` scenario, peak over 4.4 s): **high 1665 additive + 241 alpha + 16 distortion
  particles** (capacities 8192 / 4096 / 512), **12 VFX draw calls**, 68k triangles for the whole frame; **mid**
  1134 / 187 / 11, 12 calls, 62k triangles; **low** 736 / 95 / 7, 12 calls, 56k triangles. 26 programs before and after
  playing everything (nothing compiles on first use). The presets register 175 particle definitions; a full game uses
  about 220 of the 384 rows.
- Soak (measured): 300 random preset plays with random `kill()` / `stop()` / `clear()`, hit-stops and slow motion,
  rendering every step, return to the idle baseline (no visible VFX mesh, every pooled light at 0, no live particle,
  emitter or ribbon, same draw calls, geometries, textures and programs) within the longest decal life.
- Preset CPU: everything is computed at spawn (and in the few scheduled callbacks); per frame only the pooled motion
  anchors (24, projectiles / meteors / travelling fronts), followed emitters and the aura bolt ticks run. Spawning
  allocates a little (`at` objects, closures for scheduled layers); nothing allocates per frame.
- Per-frame CPU for mesh effects: none per instance except following / `setEnds` positions, bolt re-strokes (one slot
  rewrite per stroke) and speed lines tracking a world point. No per-frame allocations.
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
- **Dissolve, do not fade**: `erode` curves on smoke, flames and trails; every mesh effect erodes with noise.
- **HDR occluders need full alpha.** Alpha-blending black at 75% over an HDR 10 fire still leaves 2.5, which tonemaps
  bright, and bloom from around it washes back in. The eclipse looks reach alpha 1 in their cores, but they read
  best where the world is dimmed (ultimates: `env.setMood`) or next to, not on top of, the hottest light.
- **Grazing angles.** The fight camera sees the floor at ~10°: ground rings rise into a curtain (`height`), decals
  should be large and high-contrast, spikes and debris carry the ground read.
- **Mesh effects carry direction**: slash planes and arcs follow the blade, beams and bolts follow their axis, spike
  lines lean along their travel.
- **Lights stay off the bodies.** A pooled light 0.3 m from armour whites it out (irradiance ~ 1/d²): put event lights
  about 1.5 m toward the camera (`presets/common.js` `lightAt(p)`, default 1.5 m), 25–90 cd for hits and skills,
  150–250 only for ultimate climaxes, and give impact lights `decay: 'outExpo'` (or `'outCubic'`) so the bright part
  lasts 1–2 frames and the rest is a dim tail; the default `'outQuad'` keeps a hit light near full for 3–4 frames,
  which reads as both fighters turning white.
- **No flat camera-facing rings.** A camera-facing ring reads as a UI circle or a bubble. Tilt shock rings around the
  action axis (`normal: strikeDir`: an ellipse that carries the direction), lay them on the floor, or let distortion
  carry the shock. A big axial disc seen edge-on from the fight camera becomes a tall glowing loop: keep axial discs
  small (≤ 1 m) and short (≤ 0.2 s); for radial releases tilt the disc toward the ground (`normal [0.15, 1, 0.5]`).
- **Minimum size at fight distance.** At 8–12 m, sprites under ~0.03 m vanish; use ≥ 0.04 m or velocity stretch.
- **First frames.** The hit kits' flash sprite lives 2–3 frames (0.03–0.05 s); keep its `scale` ≤ 0.8 and any
  `flare` `'flash'` ≤ 0.2 intensity and ≤ 0.07 s. A glow puff, a flash flare and a long light stacked on the same 3–4
  frames read as a white ball. Let shaped elements carry frames 2–6 instead: impact lines, the cut crescent, a star.
- **No hoops.** An axial or camera-facing ring with a thin band reads as a UI circle or a soap bubble. Shock rings use
  a wide band with a soft inside (`width` close to the radius, `fill` 2–2.6, short `life`), or lie on the floor; the
  `'shock'` look defaults to a wide band (`width [0.55, 1.5]`).
- **Fire bodies sit on the mid colour.** The slash shader keeps large areas on the saturated `mid` and reserves
  `core` for the cutting edge, the head and tongue tips; cooled parts break up as dark matter (no glowing confetti).
- **Every effect lingers.** Hits leave a puff (`KIT[el].dust`) and motes; skills leave smoke, scorch, glitter or
  crackle; ultimates end on a climax frame (blizzard: the whole field rings out and shatters; storm: a final strike,
  then the ground keeps crackling).

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

**4. A heavy greatsword cleave (mesh effects layered with stage-1 layers; the lab's `demo.cleave`)**

```js
vfx.define('ember.cleave', (v, at) => {
  const hit = at.local(1.7, 0, 0.05);   // where the blade bites the floor
  // smear: a flame crescent and a thin razor-hot inner edge, in a plane tilted slightly toward the camera
  v.slash({ look: 'flame', pos: at.local(0.55, 1.15, 0.1), normal: [0, 0.18, 1], facing: at.facing, arc: [125, -62], radius: 1.75, width: 0.75, sweep: 0.09, life: 0.62, distort: 0.025 });
  v.slash({ look: 'razor', pos: at.local(0.55, 1.15, 0.12), normal: [0, 0.18, 1], facing: at.facing, arc: [118, -60], radius: 1.68, width: 0.22, sweep: 0.085, life: 0.3, intensity: 1.2 });
  v.schedule(0.075, (v2) => {           // impact when the head reaches the floor
    const g = [hit.x, 0.02, hit.z];
    v2.burst(vfx.lib.flashCore, { pos: [hit.x, 0.25, hit.z], scale: 1.4 });
    v2.decal({ kind: 'crack', pos: g, radius: 2.0, magma: 1, cool: 2.4 });
    v2.decal({ kind: 'scorch', pos: g, radius: 1.3, magma: 0.6 });
    v2.ring({ look: 'fire', pos: g, radius: [0.3, 2.6], life: 0.6, distort: 0.03 });
    v2.ring({ look: 'dust', pos: g, radius: [0.4, 3.2], life: 1.2 });
    v2.debris({ kind: 'ember', pos: [hit.x, 0.1, hit.z], count: 16, speed: [3, 8.5, 1.3], spread: 40 });
    v2.burst({ ...vfx.lib.sparks, count: 110, spread: [70, 30] }, { pos: [hit.x, 0.15, hit.z], dir: [at.facing * 0.4, 1, 0.15] });
    v2.light({ pos: [hit.x, 0.6, hit.z + 0.6], color: vfx.palette.ember.core, intensity: 220, range: 9, duration: 0.55 });
  });
});
```

**5. A beam held while a button is held, a bolt and a dash trail**

```js
const beam = vfx.beam({ look: 'volt', from: spearTip, to: () => target.position, life: Infinity });
// ... on release:
beam.stop();
vfx.bolt({ from: [x - 1, 9, -2], to: [x, 0.05, 0], light: 260, strikes: 3 });
vfx.afterimage(fighter.root, { count: 6, interval: 0.04, life: 0.35, palette: 'volt', drift: [0, 0.2, 0] });
vfx.speedlines({ pos: target, life: 0.3, intensity: 0.6 });
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
| `slash(look, opts)` `slashes()` `slashWave(look)` | one slash (with refraction); all five looks side by side; a travelling, growing crescent wave |
| `ring(look, opts)` `rings()` `ringsAir()` | one ground ring; all looks; camera-facing and tilted rings |
| `pillar(look, opts)` `pillars()` | one column; all looks |
| `beam(look, opts)` `beams()` | a beam whose end sweeps (`setEnds` every frame), released at 1.2 s; all looks, released at 0.9 s |
| `bolt(opts)` `bolts()` | a sky strike lighting the stage; palettes side by side plus a long crackling arc |
| `decal(kind, opts)` `decals()` | one decal; every kind (dry and magma cracks, scorch, frost, two rune palettes, glow) |
| `debris(kind, opts)` `debrisAll()` | one burst; rock, ember, ice, crystal |
| `spikes(kind, pattern, opts)` `spikesAll()` | one set; an ice line, crystal cluster, rock ring and magma cluster |
| `speedlines(mode, opts)` `speedlinesAll(which)` | 0 focus on a tracked world point, 1 directional, 2 ink |
| `afterimage(opts)` | a skinned figure (3-bone SkinnedMesh + rigid head and blade) dashes, ghosts every 50 ms |
| `cleave(facing)` `frostLine(facing)` `skyStrike(facing)` | composed set pieces: Kael's flame cleave into the floor, Iska's racing ice spikes, Vorn's rune-marked sky strike |
| `slowmo(scale, dur)` `hitstop(sec)` `clear()` | time controls |
| `preset(name, x = 0, facing = 1, extra = {})` | **stage 3 gallery**: plays any preset by name at scene origin `x` with `facing`; DEMOS entries (also variants such as `'hit.crit:frost'`, `'guard.block:perfect'`, `'dust.land:heavy'`, `'volt.strike:huge'`) place the two grey 1.9 m capsule dummies (A = user, B = target) and pick a sensible `at` (contact point, shoulder pivot, floor point, projectile `to` ...); unknown names play at `[x, 1.2, 0.1]` |
| `presetView(name, which = 'fight', x, facing)` | camera for a demo: `'fight'` (yaw 0, pitch 6, 8 m; 12 m for ultimates) or `'near'` (a closer dramatic angle) |
| `families(names)` | one preset per family side by side (default `hit.crit`, `ember.eruption`, `frost.nova`, `volt.strike`), camera pulled back |
| `overlap(names)` | three ultimates at once (default `ember.inferno`, `frost.blizzard`, `volt.storm`) for performance checks |
| `stats()` | live particles per layer, draw calls and triangles of the last render, program count |
| `idle()` | what is still drawing: visible VFX meshes, lit pooled lights, live particles, emitters and ribbons (all empty / 0 when idle) |
| `soak(n = 300, seed = 7)` | robustness soak: `n` random preset plays with random `kill()` / `stop()` / `clear()`, hit-stop and slow motion, rendering every step; returns counts, errors and peak calls / triangles / programs. Advance ~8 s, then `idle()` must be empty |

```
node tools/shot.mjs vfx --do "__ED.lab.play('swordImpact')" --at 0,0.033,0.083,0.15,0.3,0.5,0.8 --sheet-only --out shots/vfx/impact
node tools/shot.mjs vfx --do "__ED.lab.play('presetView','ember.eruption','fight'); __ED.lab.play('preset','ember.eruption')" --at 0.05,0.25,0.6,1.3 --sheet-only --out shots/vfx/s3/eruption
node tools/shot.mjs vfx --size 480x270 --do "__ED.lab.play('soak', 300)" --at 8 --eval "__ED.lab.play('idle')" --out shots/vfx/soak
```
