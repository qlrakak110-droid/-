# src/env — Eclipse Ruins (일식의 폐허)

The arena: a ruined circular colosseum on a sea cliff under a total solar eclipse. Everything is procedural (geometry
built from code, textures baked on the GPU at start-up, sky and atmosphere in shaders) and deterministic.

```js
import { createEnvironment } from './env/index.js';
const env = createEnvironment(ctx);          // stores itself on ctx.env, registers ctx.onUpdate(..., ORDER.ENV)
env.prewarm();                               // call again once every module has added its lights / materials
// every frame (game binding):
env.setFocus((p1.x + p2.x) / 2);
env.setContact(0, p1.root.position);         // ground each fighter (contact occlusion + blob shadow on low)
env.setContact(1, p2.root.position);
```

## API

### `createEnvironment(ctx, opts?) -> env`

| option   | default                     | meaning |
|----------|-----------------------------|---------|
| `detail` | `ctx.quality.envDetail`     | 0..2 detail tier override (see *Tiers*) |
| `seed`   | `0xec1195`                  | layout seed. The arena is authored with the default; other seeds give a different rubble / block layout |
| `post`   | `true`                      | apply the arena's post baseline via `ctx.post.setBaseline(env.baseline)` |

Creation bakes textures and the PMREM (a few ms on a GPU), adds `env.root` to `ctx.scene`, sets `scene.environment`,
`scene.fog` (FogExp2, very light: other modules' materials barely fog at fight distance) and `scene.background`.

### Fields

| field | type | meaning |
|---|---|---|
| `env.root` | `THREE.Group` | everything the env added (named `env.*`) |
| `env.envMap` | `Texture` | PMREM of the sky + ring silhouette + light cards; also `scene.environment` |
| `env.sun` | `DirectionalLight` | shadow-casting key (front-left, high). **Directional light #0** |
| `env.rim` | `DirectionalLight` | cold rim from behind-right (raised above the eclipse, see `rimDir`). **Directional light #1** |
| `env.hemi` | `HemisphereLight` | sky / ground fill |
| `env.points` | `PointLight[]` | brazier lights (fixed count per tier, flicker by intensity only) |
| `env.bounds` | `{minX: -9, maxX: 9}` | fight limits on X (m) |
| `env.floorY` | `0` | floor height (m) |
| `env.sunDir` | `Vector3` | unit vector toward the eclipse (≈ `(0.035, 0.108, -0.994)`: azimuth 2°, elevation 6.2°; upper third of every fight framing) |
| `env.rimDir` | `Vector3` | unit vector toward the rim light (≈ `(0.429, 0.407, -0.807)`: azimuth 28°, elevation 24°) |
| `env.keyDir` | `Vector3` | unit vector toward the key light |
| `env.wind` | `Vector3` | ambient wind, m/s (`(0.9, 0, 0.25)`): drift smoke / cloth with it to match banners, ash, embers |
| `env.braziers` | `Vector3[]` | the four brazier bowl centres (world) |
| `env.baseline` | object | the post baseline this arena uses (see *Art guide*) |
| `env.focusX` | number (get) | current shadow focus |
| `env.mood` | `{darken, tint}` (get) | current (tweened) mood |
| `env.tier` | object | resolved tier settings |
| `env.uniforms` | object | shared shader uniforms (read-only for other modules) |

### Methods

| method | meaning |
|---|---|
| `setFocus(x)` | centre the key light's shadow frustum (and the floor's key-light pool) on world X. Clamped to ±12.5 m, texel-snapped so shadows never crawl. Cheap; call every frame with the fighters' midpoint. Frustum: ±8.5 m (light space, ≈ ±11 m along X), 0..~4 m tall casters |
| `setMood({ darken = 0.75, tint = 0xffffff, duration = 0.3 })` | dim and tint the world together: key ×(1−0.62d), hemi ×(1−0.8d), braziers / baked glow ×(1−0.75d), rim ×(1−0.1d) and tinted toward `tint`, `scene.environmentIntensity` ×(1−0.65d), sky / fog / far layers / particles darkened and tinted in their shaders. The corona stays bright on purpose (the black sun is the ultimate's backdrop). Fighters keep their rim + part of the key, so silhouettes read. Tweens on **real time** (runs through hit-stop / slow-mo). `tint`: hex, CSS, `THREE.Color` or `[r,g,b]` |
| `setMood(null)` | restore over 0.45 s (or `setMood(null)` after a custom tween, any time) |
| `setContact(i, pos, radius = 0.35, height = 1.9)` | ground a body (slot `i` 0..3): soft contact occlusion on the floor under `pos` (dims the floor's hemisphere / env / key light, kills the wet sheen) and, on tiers without a shadow map, a soft blob shadow cast away from the key, `height`·0.8 m long. `pos`: `Vector3` or `[x, y, z]`, the body's root on the floor; as `pos.y` rises (jumps) the contact widens and fades (`exp(-1.4·y)`). `setContact(i, null)` clears the slot. Call every frame per fighter (four uniform writes, no allocation). Scale `radius` / `height` for a giant |
| `pulse(pos, color = [3, 1.3, 0.35], strength = 1)` | floor reaction to a big impact: a glow core plus a ring expanding at 9.5 m/s that ripples the puddles, and a shove of nearby ash / embers. `pos`: `Vector3` or `[x, y, z]` (y ignored). `color`: linear HDR like VFX colours (normalised internally, only hue + strength matter). `strength` 0..2. Four slots, oldest recycled. Runs on game time |
| `prewarm(camera?)` | `renderer.compile(scene, camera)` |
| `captureReflection(renderFirst = false)` | high tier: copy the last rendered HDR frame for the puddle reflection. Called automatically every frame; tests that render single frames call it with `true` (renders once first) — see the lab's `prime` scenario |
| `stats()` | `{calls, tris, tier, pointLights}` the env submits per frame |
| `update(dtGame, dtReal)` | already registered at `ORDER.ENV`; exposed for custom loops |
| `dispose()` | remove from the scene, free every geometry / material / render target it created and restore the scene's previous `fog`, `background` and `environmentIntensity` |

### Conventions other modules rely on

- **Directional light order.** The env's lit materials mask directional light #0 (key) and #1 (rim) per fragment
  (backdrop: key falls off beyond ~9 m from the centre; floor: key pool on the fight line, rim specular suppressed).
  Shadow casters sort first in three.js, then scene order; the env adds key then rim. **Other modules must not add
  shadow-casting directional lights**, and should not add directional lights at all (use the VFX point-light pool).
- **Lights per tier** (fixed, created once): 2 directional + 1 hemisphere + `env.points.length` point lights
  (high 4, mid 2, low 0). Add `ctx.quality.maxLights` for the VFX pool when counting per-fragment light cost.
- **Time.** Ambient animation (fire, embers, ash, banners, clouds, corona, puddle ripples, pulses) runs on game
  time — hit-stop freezes the world with the fighters, slow-mo slows it. Mood tweens run on real time.
- **No env shadow casters.** The ruins are far outside the shadow frustum; fighters / VFX cast onto the floor only.
- **Determinism.** Layout uses `makeRng(seed)`; nothing reads wall-clock time.

## Tiers (`ctx.quality.envDetail`)

| | low (0) | mid (1) | high (2) |
|---|---|---|---|
| shadows (from `ctx.quality`) | off | 1024 | 2048 |
| brazier point lights | 0 (baked warm glow + floor pools) | 2 | 4 |
| floor bake | 1024² | 1024² | 2048² |
| stone detail bake | 512² | 1024² | 1024² |
| puddle reflection | PMREM | PMREM | PMREM + previous-frame screen reflection (fighters / VFX reflect in puddles in front of the fight line) |
| banners | 5 | 8 | 8 |
| rubble pieces | ×0.45 | ×0.75 | ×1 |
| ash / embers | 135 / 63 | 336 / 154 | 650 / 300 (× `particleScale` already applied) |
| mist sheets / shafts | – / 3 | ✓ / 7 | ✓ / 7 |
| sky cloud octaves | 3 | 5 | 5 |
| contact blob shadow (`setContact`) | 0.8 (no shadow map) | 0.25 (deepens PCF contact) | 0.25 |
| **env draw calls** (main pass) | **10** | **10** | **11 + 1 copy** |
| **env triangles** | **~80k** | **~85k** | **~87k** |

Draw calls: sky, ruins (stone), iron, floor, far silhouettes, cloud sea, banners, fire, atmosphere, particles
(+ reflection copy). The env casts no shadows, so it adds nothing to the shadow pass. Measured in the lab with
`__ED.lab.play('stats')`; the lab's total (2 capsules + their shadows + post) is 20 / 24 / 26 calls, 83k / 90k / 93k
triangles.

## Art guide (for character, VFX and camera artists)

**Composition from the fight camera** (`src/cam`: +Z looking −Z, fov 34–40°, tilted down 4.5–8.5°, so the frame
ends only ~12° above the horizon). The eclipse sits at azimuth 2°, elevation 6.2°: in the upper third of every fight
framing, just above the fighters' heads, and between them on a close clinch. Two colossal hooded statues with broken
halos stand waist-deep in the cloud sea at azimuth −13.5° / +15.5° (230 m), flanking it inside the vista window
framed by two broken piers. Directly behind the fight line the colosseum has collapsed to a knee-high broken kerb, so
the fighters' heads and shoulders sit against a calm band: hazed cloud sea, a muted amber horizon glow and small
spires. Keep effects that must read (projectiles, slashes) in front of that band. The colonnade, arches, banners,
buttressed podium wall and seating tier frame the sides; braziers sit on the flanks (±37°, ±63°): **cool centre,
warm sides**. The floor carries history: damp hollows and dry dusty stones, long settlement cracks, and an old
shattered, scorched impact behind the fight line at (−4.4, −6.2).

**Light directions** (world, toward the light): key `(-0.42, 0.78, 0.50)` cool white `#dbe5ff`-ish, intensity 3.0,
shadows fall to the back-right; rim `env.rimDir` ≈ `(0.43, 0.41, -0.81)` cold blue `(0.55, 0.68, 1.0)`, 4.2: it rims
heads, shoulders and the right edge opposite the key (metal gets a cold specular top-right); hemisphere sky
`(0.10, 0.12, 0.19)` / ground `(0.06, 0.04, 0.03)`, 0.5; braziers warm `(1.0, 0.5, 0.18)`, 20 cd, 16 m range
(≈13.7 m from the fight centre: a warm back-side kiss on the fighters).

**Palette and value ranges** (linear HDR, before exposure 1.1 / ACES):

| element | value |
|---|---|
| zenith / mid sky / horizon | 0.001 / 0.004 / 0.015 (blue-black) |
| horizon "eclipse sunset" band | ≤ 0.17, 0.08, 0.04 (muted amber, ±3° of the horizon) |
| corona limb / body / streamers | 2.1 / 0.2–1.2 / ≤ 0.3, cold white `(0.82, 0.9, 1.0)` |
| black disc | 0.0004, minus a small bloom-occlusion offset (the HDR target is signed: the disc cancels the corona's bloom spill so it stays black, sRGB ≈ 0–3) |
| diamond-ring bead | 26 (tiny: blooms into a star) |
| ruins, lit | 0.005–0.03 (stone albedo ≈ 0.08, key masked to 12% on the backdrop) |
| floor | 0.02–0.06 lit; dry stones matt (roughness ≈ 0.85–0.95), damp hollows darker and satin (≈ 0.5), puddles mirror the sky; key pooled on the fighters (falls to 24% away from them) |
| brazier fire cores | 4–7; embers 2–6 |
| near fog / mist | `(0.0105, 0.0125, 0.018)` |
| **fighters should sit at** | 0.1–0.5 mid-tones (key-lit), rims to ~1 |
| **VFX** | cores 2–10 as in CONTRACT.md — anything ≥ 1 blooms and will dominate this backdrop |

Saturation: the backdrop stays desaturated (blue-grey stone, oxblood banners at albedo 0.085, muted amber). Saturated
colour belongs to the fighters and their effects. Avoid amber / orange VFX directly against the braziers on the flanks;
frost and violet read strongest against the centre.

**Post baseline** (`env.baseline`): exposure 1.1, bloom 0.95 (threshold 1.0, knee 0.55, radius 1.0), vignette 0.40,
grain 0.032, saturation 0.94, contrast 1.05, tint `(1, 0.985, 1)`, lift `(0.0025, 0.003, 0.0055)` (cool blacks).
Return to it with `ctx.post.reset()`.

## Lab

`src/labs/env.js` — the arena plus two 1.9 m grey capsules at x = ±2.5, grounded with `env.setContact` every frame.
URL flag `detail=0..2` overrides the env tier (`--hash "q=low"` changes the whole quality tier). Judge the arena
through the `game*` scenarios first: they use the real fight camera, which frames very differently from a hand-placed
lab view (it tilts down and sees ~12° above the horizon).

```
node tools/shot.mjs env --do "__ED.lab.play('gameMid')" --each "__ED.lab.play('prime')" --at 1.2 --out shots/env/gameMid
node tools/shot.mjs env --size 800x500 --do "__ED.lab.play('far')" --each "__ED.lab.play('prime')" --at 1 --out shots/env/far800
node tools/shot.mjs env --do "__ED.lab.play('mid'); __ED.lab.play('vfx'); __ED.lab.play('mood')" --at 0.05,0.4,1 --sheet-only --out shots/env/mood
```

Scenarios: `gameNear` `gameMid` `gameFar` `gameAt(x)` (the game's own fight camera from `src/cam` framing the dummies
1.4 / 4.5 / 9 m apart; `gameAt` = 4.5 m apart centred on `x`; let it settle ~1 s), `near` `mid` `far` (fixed lab
fight views at 6 / 8.5 / 11 m), `edgeL` `edgeR` `close` `reset` (fighter placements),
`low` `lowWide` `high` `ots` `sideL` `sideR` `sideLowL` (cinematic angles), `overview`, `colossus` (telephoto on a
far statue), `mood` `moodWarm` `moodOff`, `pulse` `pulseFrost`, `metal` (chrome dummies to judge the env map),
`vfx` (hot HDR spheres), `prime` (render + copy for the puddle reflection before a capture), `stats`.

## Files

| file | contents |
|---|---|
| `index.js` | `createEnvironment`: assembly, lights, shadow focus, PMREM, mood, pulse, reflection copy, update |
| `config.js` | layout radii, light directions, palette, tier table |
| `glsl.js` | shared noise, sky gradient, height fog |
| `bake.js` | GPU-baked floor maps (flagstones, inlays, damp / dust / cracks, the old impact), tiling stone detail, banner cloth |
| `sky.js` | sky dome: eclipse, corona, chromosphere, diamond ring, crepuscular rays, clouds, stars |
| `geometry.js` | merging builder + primitives (chamfered blocks, lathe grids, rocks) |
| `ruins.js` | buttressed podium wall, colonnade + arches, collapsed tier, vista kerb + cliff edge, rubble, brazier / banner fittings |
| `materials.js` | MeshStandardMaterial patches: key / rim masks, sky-matched fog, baked glow |
| `floor.js` | floor material: wetness, puddles, contact band, ground contacts, pulses, brazier pools, screen reflection |
| `far.js` | colossi, spires, cloud sea |
| `atmosphere.js` | haze planes, light shafts, mist sheets |
| `particles.js` | ash and embers (GPU-animated, one draw call) |
| `props.js` | banners (vertex-shader cloth) and brazier fire |
