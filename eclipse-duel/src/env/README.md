# src/env — Eclipse Ruins (일식의 폐허)

The arena: a ruined circular colosseum on a sea cliff under a total solar eclipse. Everything is procedural (geometry
built from code, textures baked on the GPU at start-up, sky and atmosphere in shaders) and deterministic. The
architecture is carved: mouldings are swept profiles, relief (friezes, roundels, keystone masks, dentils, flutes) is a
GPU-baked relief atlas applied as normal + cavity detail, and the stone weathers in the shader (cracks, rain streaks,
lichen, moss).

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
| `env.root` | `THREE.Group` | everything the env added (named `env.*`: `env.ruins`, `env.iron`, `env.props`, `env.floor`, `env.far`, `env.cloudsea`, `env.banners`, `env.fire`, `env.atmosphere`, `env.particles`, `env.sky`) |
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
| `captureReflection()` | kept for compatibility, does nothing: the high-tier puddle reflection is taken from the **current** frame through `ctx.post.onAfterScene` (no lag, correct on cuts, nothing to prime in tests) |
| `stats()` | `{calls, tris, tier, pointLights, sections}` the env submits per frame (`calls` / `tris` include the reflection copy + puddle pass on high; `sections`: ruins triangles per part, e.g. `columns`, `tier`, `iron.chains`, `props.candles`) |
| `update(dtGame, dtReal)` | already registered at `ORDER.ENV`; exposed for custom loops |
| `dispose()` | remove from the scene, free every geometry / material / render target it created and restore the scene's previous `fog`, `background` and `environmentIntensity` |

### Conventions other modules rely on

- **Directional light order.** The env's lit materials mask directional light #0 (key) and #1 (rim) per fragment
  (backdrop: key falls off beyond ~9 m from the centre; the floor and everything resting on it, below ~2.5 m inside
  the wall, share one key pool around the fight line (`envFloorKey` in materials.js), so rubble, drums, impact slabs
  and props are never lit brighter than the stones under them; the floor keeps 9% of the rim, a glisten toward the
  eclipse).
  Shadow casters sort first in three.js, then scene order; the env adds key then rim. **Other modules must not add
  shadow-casting directional lights**, and should not add directional lights at all (use the VFX point-light pool).
- **Lights per tier** (fixed, created once): 2 directional + 1 hemisphere + `env.points.length` point lights
  (high 4, mid 2, low 0). Add `ctx.quality.maxLights` for the VFX pool when counting per-fragment light cost.
- **Time.** Ambient animation (fire, embers, ash, banners, clouds, corona, puddle ripples, pulses) runs on game
  time — hit-stop freezes the world with the fighters, slow-mo slows it. Mood tweens run on real time.
- **No env shadow casters.** The ruins are far outside the shadow frustum; fighters / VFX cast onto the floor only.
- **Determinism.** Layout uses `makeRng(seed)`; nothing reads wall-clock time.
- **Environment map binding.** The env binds its PMREM on its own materials (`material.envMap`) so their authored
  `envMapIntensity` applies (stone 0.7, iron 0.8, props 0.3, floor 0.85, banners 0.4) — with only `scene.environment`,
  three r170 silently replaces every material's `envMapIntensity` by `scene.environmentIntensity`. Other modules'
  materials keep using `scene.environment` (mood-scaled through `scene.environmentIntensity`).
- **Puddle reflection pass (high).** `post.onAfterScene` copies the resolved HDR frame (half resolution, mips) and
  re-draws the floor disc into the same scene target (MSAA renderbuffer; post resolves again before bloom),
  depth-tested `LessEqual` against the frame, adding *(this frame re-projected through the floor mirror − the sky
  reflection the floor already had) × the floor's specular weight* on wet stone in front of the fight line (on
  puddles only the mirror share: 40% of a puddle's reflection is scattered by wind ripples into a blurred PMREM sheen
  on every tier). Fighters in front occlude it. Known limit: transparent VFX drawn over a puddle get that (small,
  ≤ ~15 %) delta on top.
- **Puddles.** Mirror reflection (IBL; plus this frame's screen reflection on high) with a 40% ripple-scattered
  share, and the stone under the water film keeps 75% of the key light's broad sheen (shadowed like everything else):
  seen from above or against the dark walls a puddle reads as dark wet stone, never as a hole in the floor.

## Tiers (`ctx.quality.envDetail`)

| | low (0) | mid (1) | high (2) |
|---|---|---|---|
| shadows (from `ctx.quality`) | off | 1024 | 2048 |
| brazier point lights | 0 (baked warm glow + floor pools) | 2 | 4 |
| floor bake | 1024² | 1024² | 2048² |
| stone detail bake | 512² | 1024² | 1024² |
| relief atlas / weather map | 512² / 256² | 1024² / 512² | 1024² / 512² |
| stone weathering (cracks, streaks) | ×0.7 | ×1 | ×1 |
| puddle reflection | PMREM | PMREM | PMREM + this frame's screen reflection (fighters / VFX reflect in puddles in front of the fight line) |
| banners | 5 | 8 | 8 |
| rubble pieces / wall-base chips | ×0.45 | ×0.75 | ×1 (170 / 160) |
| votive candles per brazier (lit ones add a flame) | 4 | 8 | 12 |
| offerings: bowl + coins, urn / carved stele | 2 braziers / – | 2 braziers / ✓ | 4 braziers / ✓ |
| chains: draped + hanging / gibbet cage / fallen cage | – + – / ✓ / – | ✓ / ✓ / – | ✓ / ✓ / ✓ |
| dead trees on the wall top (roots down the face) / hanging vines | 1 / – | 2 / ✓ | 3 / ✓ |
| broken weapons and shields | 5 | 9 | 14 |
| heaved slabs at the old impact / shards | 7 / 14 | 10 / 14 | 14 / 30 |
| facade string courses | – | ✓ | ✓ |
| colossus tessellation (robe rows × segs) | 20 × 30 | 34 × 46 | 34 × 46 |
| ash / embers | 135 / 63 | 336 / 154 | 650 / 300 (× `particleScale` already applied) |
| mist sheets / shafts | – / 3 | ✓ / 7 | ✓ / 7 |
| sky cloud octaves | 3 | 5 | 5 |
| contact blob shadow (`setContact`) | 0.8 (no shadow map) | 0.25 (deepens PCF contact) | 0.25 |
| **env draw calls** (main pass) | **11** | **11** | **11 + reflection copy + puddle pass = 13** |
| **env triangles** | **~78k** | **~97k** | **~106k** |

Draw calls: sky, ruins (stone), iron, props (wax / wood / dead vegetation), floor, far silhouettes, cloud sea, banners,
fire (brazier + candle flames), atmosphere, particles (+ reflection copy and puddle pass on high). The env casts no
shadows, so it adds nothing to the shadow pass. Measured in the lab with `__ED.lab.play('stats')` (whole quality tier
via `--hash "q=low|mid|high"`); the lab's total (2 capsules + their shadows + post) is 21 / 25 / 29 calls,
81k / 103k / 112k triangles. High-tier ruins triangles by part (`stats().sections`): columns 15.6k, tier 9.4k, rubble
and chips 8.7k, podium 7.2k, arches 4.3k, fallen pieces 3.8k, ground + cliff 3k, vaults 2k, cornice 1.4k, braziers
1.3k, impact 1.1k; iron 9.7k (bowls / poles 3.2k, chains 3.4k, cage 1.7k, arms 1.4k); props 8k (candles 3.4k,
vegetation 4.6k); far layer 21k (two colossi ~15k, spires 5.4k).

## Art guide (for character, VFX and camera artists)

**Carved architecture (close-ups and cinematics).** Podium wall: an inscribed plinth (a band of the cult's glyphs),
a torus base moulding wrapped in laurel, ashlar courses (a few blocks with sunk panels), the **frieze course** — a
procession of hooded figures carrying eclipse staves, walking toward the vista from both sides, an eclipse roundel every
fourth block and an orant (arms raised holding the eclipse) every seventh — and a cornice of egg-and-dart fascia,
dentils, corona and cyma crown, laid in block-length runs that stop where the wall has fallen (fallen runs lie on their
backs in the gutter). Pilasters carry sunk panels and egg-and-dart caps. Colonnade: twenty-flute shafts (geometry
alternates arris / channel, the shader carves the concave channels and the V-jointed drum ends) on Attic bases;
capitals with a laurel astragal, an egg-and-dart echinus and an abacus banded with eclipse phases. Arches: voussoirs, a
projecting keystone carved with the guardian's hooded mask, an archivolt band, spandrel rosettes and an entablature
(architrave inscribed with glyphs, a frieze of eclipse phases, dentils, corona), some broken and sagging. Seating tier:
settled irregular seats (low triangle "seat" blocks), stairways every ~9.5°, a walkway with an inscribed parapet,
robbed-out holes, slumped sections and tumbled blocks at the ragged collapse edge, and exposed radial vaults (arched
substructure) where the tier has fallen toward the vista. Dressing: votive candles (melted rims, drips, wax pools;
lit wax glows from inside) with offerings at the braziers; chains draped across two arches and hanging from a keystone;
a gibbet cage hanging from an arch (another burst open on the floor by the left wall); dead trees rooted in the
standing wall top whose roots grip down the inner face; dead vines hanging in clumps from surviving cornice runs;
broken greatswords driven into the floor, shields, snapped spears and a helm near the ring edge (always behind the
fight line, never on it); a toppled column by the left wall (its drums roughly in line, settled at different depths,
the last one the broken top of the shaft) with its capital lying upside down behind them, clear of the fight line;
fallen drums by the right wall (one landed on its end, its top shattered) and in the vista shoulders. Fallen drums
carry the standing shafts' 20 flutes (same scale), worn shallow with a chunk knocked off an arris, and lie broadside
to the fight camera so it sees their flanks, not their ends. Broken column tops are sheared fracture planes (the
slanted silhouette), never a sliver of drum. Stone weathering (shader): sparse long cracks, rain streaks on vertical
faces, pale lichen rosettes, moss on tops / at the base / in carved recesses.

**Nothing floats.** Masonry is laid course by course: a podium block or a moulding run exists only where the course
under it is solid (blocks actually laid, not a height estimate), and a block whose upper neighbour is missing keeps its
top face; tumbled tier blocks rest on a surviving seat row or the ground of the collapse; second-storey fragments
stand only on a surviving entablature; facade string courses run on each block's inner face below its broken top.

**The colossi.** Draped robes with heavy pleats fanning down from the clasped hands and broad folds behind (fold
valleys darkened in the vertex colour), a cape over sloping shoulders with a tattered hem, a deep forward-bowed cowl
with a rolled rim, the face a void with two faint ember eyes (HDR ≈ 1.9, they smoulder rather than shine), both hands on
the hilt of a sword planted point-down (eclipse-ring pommel, wrapped grip, drooping quillons, long blade into the
plinth), a broken spiked halo on spokes; rain streaks and lichen in the far shader. Left: the cowl's peak and a third of
the halo gone, the right forearm broken off (the stone hand still holds the hilt); right: a shoulder sheared away, one
quillon snapped. They read in a 6–15° telephoto from the vista edge (lab `colossusL` / `colossusR` / `colossusHead`)
and stay a calm, hazed silhouette from the fight camera.

**Ground storytelling (floor bake).** Old blade gouges weathered into the stone (some in threes, like claws), three
old scorch blooms, ash drifted in dunes against the wall base and spilled around the brazier bases, and the **old
impact** at (−4.4, −6.2): a fused black core (a puddle collects there), shattered flagstones with ash in the gaps,
radial fractures and a ring fracture at the lip, a wide soot halo, pale ejecta rays beyond it, plus heaved, scorched
slab geometry around the rim so it reads from the fight camera.

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
| ruins, lit | 0.005–0.03 (stone albedo ≈ 0.08, key masked to 12% on the backdrop; relief cavities darker, lichen up to ×1.45) |
| colossi | ≈ 0.006–0.02 before haze (key response ×2.9 on the statues so the drapery reads in telephoto); ember eyes 1.9 |
| candle flames / lit wax | cores ≈ 2–4 (small tongues) / wax glow ≈ 0.2 |
| floor | 0.02–0.06 lit; dry stones matt (roughness ≈ 0.85–0.95), damp hollows darker and satin (≈ 0.5), puddles mirror the sky (see *Puddles*); key pooled on the fighters (falls to 24% away from them, shared by everything resting on the floor), 9% of the rim |
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
node tools/shot.mjs env --do "__ED.lab.play('gameMid')" --at 1.2 --out shots/env/gameMid
node tools/shot.mjs env --size 800x500 --do "__ED.lab.play('far')" --at 1 --out shots/env/far800
node tools/shot.mjs env --do "__ED.lab.play('mid'); __ED.lab.play('vfx'); __ED.lab.play('mood')" --at 0.05,0.4,1 --sheet-only --out shots/env/mood
```

Scenarios: `gameNear` `gameMid` `gameFar` `gameAt(x)` (the game's own fight camera from `src/cam` framing the dummies
1.4 / 4.5 / 9 m apart; `gameAt` = 4.5 m apart centred on `x`; let it settle ~1 s), `near` `mid` `far` (fixed lab
fight views at 6 / 8.5 / 11 m), `edgeL` `edgeR` `close` `reset` (fighter placements),
**`cine(name)`** — the real cinematic vocabulary (`src/cam/shots.js`) played on the dummies by the camera director,
held on its last frame, returning the sample time to advance: `heroL` `heroR` (heroPushIn, anchored on P1 / P2),
`otsL` `otsR` (overShoulder), `sideL` `sideR` (68° orbit, 7.2 m), `sideLow` (55°, 0.45 m high looking up), `crane`
(wideEstablishing), `craneHigh` (topDownSlam), `orbit` (orbitSweep), `skim` (groundSkim), `face` (faceCloseUp),
`dutch` (dutchDrift); `cineList()`. Close inspection: `inspWall` `inspCapital` `inspTier` `inspTierHigh(side)`
`inspBrazier` `inspImpact` `inspImpactTop` `inspVista`, `inspTopple` (toppled column + capital), `inspFallenR`
(fallen drums), `inspKerb` (the vista kerb: nothing may bridge a fallen course), `topDown` (puddles from above);
telephoto: `colossusL` `colossusR` `colossusHead` `colossusStudy(yaw)` (75 m from the left statue); hand-placed lab angles `low` `lowWide` `high` `ots` `sideL` `sideR`
`sideLowL`, `overview`, `colossus`, `mood` `moodWarm` `moodOff`, `pulse` `pulseFrost`, `metal` (chrome dummies to
judge the env map), `vfx` (hot HDR spheres), `prime` (no-op, kept for old capture commands), `stats`.

```
node tools/shot.mjs env --do "__ED.lab.play('cine', 'otsR')" --at 1.0 --out shots/env/otsR
node tools/shot.mjs env --do "__ED.lab.play('colossusHead')" --at 0.1 --out shots/env/colossus
```

## Files

| file | contents |
|---|---|
| `index.js` | `createEnvironment`: assembly, lights, shadow focus, PMREM (bound on the env materials), mood, pulse, puddle reflection (post.onAfterScene), update |
| `config.js` | layout radii, light directions, palette, tier table |
| `glsl.js` | shared noise, sky gradient, height fog |
| `bake.js` | GPU-baked floor maps (flagstones, inlays, damp / dust / cracks, blade gouges, scorches, ash drifts, the old impact), tiling stone detail, banner cloth |
| `ornament.js` | relief atlas bake (16 cells: `ORN.*`, `panel(cell)`), weather map bake, stone-shader relief / weathering chunks |
| `sky.js` | sky dome: eclipse, corona, chromosphere, diamond ring, crepuscular rays, clouds, stars |
| `geometry.js` | merging builder (+ relief channel, per-section triangle accounting) + primitives (chamfered / face-only ashlar blocks, broken blocks, profile sweeps, lathe grids incl. partial arcs, tubes, rocks) |
| `ruins.js` | podium wall (plinth, mouldings, frieze, cornice), pilasters, colonnade + capitals, arches + entablatures, broken tier + vaults, facade, vista kerb + cliff edge, fallen pieces, rubble, braziers, banner fittings |
| `dressing.js` | candles + offerings, chains, cages, dead trees / roots / vines, broken weapons and shields, the heaved impact slabs |
| `materials.js` | MeshStandardMaterial patches: key / rim masks (`envFloorKey`: the floor's key pool, shared by everything resting on it), a per-directional-light hook, sky-matched fog, baked glow; stone (relief + weathering), iron, props |
| `floor.js` | floor material: wetness, puddles (mirror + ripple scatter + the key's sheen under the film), contact band, ground contacts, pulses, brazier pools; the puddle reflection pass |
| `far.js` | colossi (sculpted), spires, cloud sea |
| `atmosphere.js` | haze planes, light shafts, mist sheets |
| `particles.js` | ash and embers (GPU-animated, one draw call) |
| `props.js` | banners (vertex-shader cloth) and brazier + candle fire |
