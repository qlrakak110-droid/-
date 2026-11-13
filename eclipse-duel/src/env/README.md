# src/env — 「천무대 天武臺」

The arena of 「흑일무림」: the ruined summit duelling terrace of the fallen Heaven-Martial Sect (천무문), under a total
eclipse. A great round stone terrace carved with the sect's formation diagram, its north rim broken away into a sea of
cloud; around it a raised court with a carved retaining wall and balustrade, the remains of a timber gallery, a
collapsed hall on the west, the mountain gate with its hanging name board on the south, stone lanterns, incense
braziers, banners and talisman ropes, pines and bamboo; two colossal guardian statues and ink-painting peaks in the
haze. Everything is procedural (geometry built from code, textures baked on the GPU at start-up, sky and atmosphere
in shaders), deterministic, and original (see MURIM.md: invented sect, emblems, glyphs and designs).

```js
import { createEnvironment } from './env/index.js';
const env = createEnvironment(ctx);          // stores itself on ctx.env, registers ctx.onUpdate(..., ORDER.ENV)
env.prewarm();                               // call again once every module has added its lights / materials
// every frame (game binding):
env.setFocus((p1.x + p2.x) / 2);             // a free-roaming mode: env.setFocus(hero.x, hero.z)
env.setContact(0, p1.root.position);         // ground each fighter (contact occlusion + blob shadow on low)
env.setContact(1, p2.root.position);
```

Ring convention used everywhere below: `theta` is measured from −Z toward +X, so 0° is the vista behind the duel line
(north), +90° = +X (east), −90° = −X (west, the hall), 180° = +Z (south, the gate); a ring point is
`(r sin θ, y, −r cos θ)`.

## API

### `createEnvironment(ctx, opts?) -> env`

| option   | default                     | meaning |
|----------|-----------------------------|---------|
| `detail` | `ctx.quality.envDetail`     | 0..2 detail tier override (see *Tiers*) |
| `seed`   | `0xec1195`                  | layout seed. The arena is authored with the default; other seeds move rubble, damage and dressing |
| `post`   | `true`                      | apply the arena's post baseline via `ctx.post.setBaseline(env.baseline)` |

Creation bakes textures and the PMREM (a few ms on a GPU), adds `env.root` to `ctx.scene`, sets `scene.environment`,
`scene.fog` (FogExp2, very light: other modules' materials barely fog at fight distance) and `scene.background`.

### Fields

| field | type | meaning |
|---|---|---|
| `env.root` | `THREE.Group` | everything the env added (named `env.*`: `env.ruins` (stone + roof tiles), `env.metal`, `env.timber`, `env.foliage`, `env.floor`, `env.far`, `env.cloudsea`, `env.banners`, `env.fire`, `env.atmosphere`, `env.particles`, `env.sky`) |
| `env.envMap` | `Texture` | PMREM of the sky + the summit's skyline + light cards; also `scene.environment` |
| `env.sun` | `DirectionalLight` | shadow-casting key (front-left, high). **Directional light #0** |
| `env.rim` | `DirectionalLight` | cold rim from behind-right (raised above the eclipse, see `rimDir`). **Directional light #1** |
| `env.hemi` | `HemisphereLight` | sky / ground fill |
| `env.points` | `PointLight[]` | fire lights (fixed count per tier, flicker by intensity only): the first `points.length` of `env.braziers` |
| `env.bounds` | `{minX: -9, maxX: 9}` | duel limits on X (m) |
| `env.floorY` | `0` | terrace floor height (m) |
| `env.sunDir` | `Vector3` | unit vector toward the eclipse (≈ `(0.035, 0.108, -0.994)`: azimuth 2°, elevation 6.2°; upper third of every fight framing) |
| `env.rimDir` | `Vector3` | unit vector toward the rim light (≈ `(0.429, 0.407, -0.807)`: azimuth 28°, elevation 24°) |
| `env.keyDir` | `Vector3` | unit vector toward the key light |
| `env.wind` | `Vector3` | ambient wind, m/s (`(0.9, 0, 0.25)`): drift smoke / cloth with it to match banners, talismans, bamboo, leaves |
| `env.braziers` | `Vector3[4]` | the four fire sources (world): the flames of the two lit stone lanterns on the vista shoulders (θ = ∓37°, r = 13.7), then the bowls of the two bronze censers (θ = ∓63°, r = 13.6) |
| `env.lamps` | `Vector3[]` | flames of the other lit stone lanterns (baked glow + floor pool, no real light): the feet of the gate stairs (θ = ±166°, r = 14.25), the hall steps (on the court), the east wall (θ = 112°, mid / high) |
| `env.colliders` | object | solid things for modes that leave the fight line (see *Colliders*) |
| `env.landmarks` | object | named places (see *Landmarks*) |
| `env.statues` | `object[2]` | the guardian statues (see *The guardian statues*) |
| `env.baseline` | object | the post baseline this arena uses (see *Art guide*) |
| `env.focusX` | number (get) | current focus on X |
| `env.mood` | `{darken, tint}` (get) | current (tweened) mood |
| `env.tier` | object | resolved tier settings |
| `env.uniforms` | object | shared shader uniforms (read-only for other modules) |

### Methods

| method | meaning |
|---|---|
| `setFocus(x, z = 0)` | centre the key light (and the floor's key-light pool) on the action. `x` clamped to ±12.5 m, `z` to ±14 m, texel-snapped so shadows never crawl. Cheap; the duel calls it every frame with the fighters' midpoint (`z` stays 0); a free-roaming mode passes the hero's `x, z` |
| `setMood({ darken = 0.75, tint = 0xffffff, duration = 0.3 })` | dim and tint the world together: key ×(1−0.62d), hemi ×(1−0.8d), fires / baked glow ×(1−0.75d), rim ×(1−0.1d) and tinted toward `tint`, `scene.environmentIntensity` ×(1−0.65d), sky / fog / far layers / foliage / particles darkened and tinted in their shaders. The corona stays bright on purpose (the black sun is the ultimate's backdrop). Fighters keep their rim + part of the key, so silhouettes read. Tweens on **real time** (runs through hit-stop / slow-mo). `tint`: hex, CSS, `THREE.Color` or `[r,g,b]` |
| `setMood(null)` | restore over 0.45 s (or `setMood(null)` after a custom tween, any time) |
| `setContact(i, pos, radius = 0.35, height = 1.9)` | ground a body (slot `i` 0..3): soft contact occlusion on the floor under `pos` (dims the floor's hemisphere / env / key light, kills the wet sheen) and, on tiers without a shadow map, a soft blob shadow cast away from the key, `height`·0.8 m long. `pos`: `Vector3` or `[x, y, z]`, the body's root on the floor; as `pos.y` rises (jumps) the contact widens and fades (`exp(-1.4·y)`). `setContact(i, null)` clears the slot. Call every frame per fighter (four uniform writes, no allocation). Scale `radius` / `height` for a giant |
| `pulse(pos, color = [3, 1.3, 0.35], strength = 1)` | floor reaction to a big impact: a glow core plus a ring expanding at 9.5 m/s that ripples the puddles, and a shove of nearby motes, sparks and leaves. `pos`: `Vector3` or `[x, y, z]` (y ignored). `color`: linear HDR like VFX colours (normalised internally, only hue + strength matter). `strength` 0..2. Four slots, oldest recycled. Runs on game time |
| `prewarm(camera?)` | `renderer.compile(scene, camera)` |
| `captureReflection()` | kept for compatibility, does nothing: the high-tier puddle reflection is taken from the **current** frame through `ctx.post.onAfterScene` (no lag, correct on cuts, nothing to prime in tests) |
| `stats()` | `{calls, tris, tier, pointLights, sections}` the env submits per frame (`calls` / `tris` include the reflection copy + puddle pass on high; `sections`: triangles per part, e.g. `wall`, `roofs`, `wood.hall`, `metal.censers`, `foliage`) |
| `update(dtGame, dtReal)` | already registered at `ORDER.ENV`; exposed for custom loops |
| `dispose()` | remove from the scene, free every geometry / material / render target it created and restore the scene's previous `fog`, `background` and `environmentIntensity` |

### Conventions other modules rely on

- **Directional light order.** The env's lit materials mask directional light #0 (key) and #1 (rim) per fragment
  (backdrop: key falls off beyond ~9 m from the centre; the floor and everything resting on it, below ~2.5 m inside
  the wall, share one key pool around the focus (`envFloorKey` in materials.js), so rubble, lanterns, racks and
  impact slabs are never lit brighter than the stones under them; the floor keeps 9% of the rim, a glisten toward the
  eclipse).
  Shadow casters sort first in three.js, then scene order; the env adds key then rim. **Other modules must not add
  shadow-casting directional lights**, and should not add directional lights at all (use the VFX point-light pool).
- **Lights per tier** (fixed, created once): 2 directional + 1 hemisphere + `env.points.length` point lights
  (high 4: both lanterns + both censers; mid 2: the lanterns; low 0). Add `ctx.quality.maxLights` for the VFX pool when
  counting per-fragment light cost. Every other fire (and every fire on low) is baked: a per-vertex warm glow on the
  architecture around it and a pool on the floor, flickering with the same signal as the real lights.
- **Time.** Ambient animation (flames, smoke, sparks, leaves, cloth, bamboo, clouds, corona, puddle ripples, pulses)
  runs on game time — hit-stop freezes the world with the fighters, slow-mo slows it. Mood tweens run on real time.
- **No env shadow casters.** The architecture is outside the shadow frustum; fighters / VFX cast onto the floor only.
- **Determinism.** Layout uses `makeRng(seed)`; nothing reads wall-clock time.
- **Environment map binding.** The env binds its PMREM on its own materials (`material.envMap`) so their authored
  `envMapIntensity` applies (stone 0.7, metal 0.85, timber 0.45, floor 0.85, cloth 0.4) — with only
  `scene.environment`, three r170 silently replaces every material's `envMapIntensity` by
  `scene.environmentIntensity`. Other modules' materials keep using `scene.environment` (mood-scaled through
  `scene.environmentIntensity`).
- **Puddle reflection pass (high).** `post.onAfterScene` copies the resolved HDR frame (half resolution, mips) and
  re-draws the floor disc into the same scene target (MSAA renderbuffer; post resolves again before bloom),
  depth-tested `LessEqual` against the frame, adding *(this frame re-projected through the floor mirror − the sky
  reflection the floor already had) × the floor's specular weight* on wet stone in front of the fight line (on
  puddles only the mirror share: 40% of a puddle's reflection is scattered by wind ripples into a blurred PMREM sheen
  on every tier). Fighters in front occlude it. Known limit: transparent VFX drawn over a puddle get that (small,
  ≤ ~15 %) delta on top; the mirror assumes reflected content stands on the duel line plane (z = 0).
- **Puddles.** Mirror reflection (IBL; plus this frame's screen reflection on high) with a 40% ripple-scattered
  share, and the stone under the water film keeps 75% of the key light's broad sheen (shadowed like everything else):
  seen from above or against the dark walls a puddle reads as dark wet stone, never as a hole in the floor.

## Layout (metres; what stands where)

| what | where |
|---|---|
| terrace floor | disc, radius 15.6 at y = 0, carved with the formation diagram (see *The floor*). Across the vista (\|θ\| < 27°) the rim has broken away: the edge follows `env.colliders.rim(θ)` (14.1 – 15.2 m), a cliff drops to the cloud sea (y = −11) |
| raised court | all round except the vista: retaining wall face at r = 15.6, top at y = 1.44, a 1 m balustrade on its edge; paved back to r = 36. Wall ends broken at θ = ±30°; breached at θ ≈ 97 – 109° (east) |
| stairs | two recessed flights of 8 risers (run 2.64 m) from the floor up to the court: the gate stairs at θ = 180° (5.2 m wide), the hall stairs at θ = −78° (4.8 m wide) |
| gallery (회랑) | columns on lotus bases every 12°: inner row r = 17.5, outer row r = 20.5; roofed bays at θ = 45 – 69° (the second torn) and −129 – −153°, a bay whose roof has slid down whole at 129 – 141°, broken shafts elsewhere |
| hall (천무전) | west, centred on θ = −78°: plinth front 20.2 m from the centre, five bays × 3.2 m, hipped tile roof (eaves ≈ 7.6 m, ridge ≈ 12.2 m above the terrace floor); its south end has collapsed (rafters and tiles down to the court) |
| gate (산문) | south, column line at z = +20.7: four posts, centre bay 3.7 m clear × 4.2 m, gable tile roof (eaves ≈ 8.3 m, ridge ≈ 11.4 m), the name board 「天武」 hanging askew over the doorway, a boundary wall (담장) running from its wings round to θ = ±124° at r ≈ 23 |
| fires | lit stone lanterns at θ = ∓37° r = 13.7 (`env.braziers[0..1]`), bronze censers at θ = ∓63° r = 13.6 (`[2..3]`), more lit lanterns in `env.lamps`; a toppled lantern at θ = −104.5° r = 13.6, a dark one at θ = 141° r = 14.35 |
| stele, racks, drum | the sect's stele at θ = 72° r = 14.25; weapon racks at θ = 84° / 121° r ≈ 14.5 and a thrown-down one at θ = −129° r = 13.9; a war drum on the court at θ = 87° r = 18.9 |
| banners | eight poles on the court edge (r = 16.85): θ = ±41°, 74°, ±124° (sect banners, 天 over 武), ±158°, −109° (jade pennants) |
| trees | pines on rock outcrops at θ = 41° r = 22.2 and θ = −37° r = 23 (leaning out over the vista), a third at θ = 116° r = 25.8; bamboo clumps behind the gallery and the boundary wall |
| old impact | crater centred (−4.4, −6.2), radius 2.9 (heaved slabs around it: do not stage low effects inside it) |

Everything taller than a kerb stays outside the duel's camera volume (|x| < 12, 0 < z < 13): from the fight camera the
south half is behind the lens. The stairs are recessed into the court so they do not eat into the floor.

## Colliders (`env.colliders`)

Data for modes that leave the fight line (the action-RPG). All positions are world x / z; `y0` is the base height
(0 = standing on the terrace floor, 1.44 = on the raised court), `h` the height, `tag` what it is.

| field | meaning |
|---|---|
| `circles` | `[{ x, z, r, y0, h, tag }]` — lanterns, censers, rim posts, breach rubble, gallery / gate columns, banner poles, pine rocks, bamboo clumps, the drum |
| `boxes` | `[{ x, z, hx, hz, yaw, y0, h, tag }]` — oriented boxes (half extents along the box's local x / z; `yaw` as in `Object3D.rotation.y`): weapon racks, the stele, the hall plinth, the boundary wall segments |
| `radius`, `platformY` | 15.6, 1.44 |
| `rim(theta)` | radius of the terrace floor's edge at ring angle `theta` (radians): 15.6 along the wall, less across the broken rim |
| `stairs` | `[{ id: 'gate' \| 'hall', x, z, dirX, dirZ, width, run, rise, steps }]` — foot centre of each flight on the floor edge, the unit direction it climbs, its width, run and rise (1.44) |
| `resolve(x, z, r = 0.4, out?, margin = 0.15)` | keeps a body of radius `r` on the terrace floor out of every solid thing that reaches the floor and inside the wall / the rim; returns `out` (`{x, z}`; pass a `Vector3` to avoid allocation). The stair mouths count as wall: a mode that lets the hero climb them handles `stairs` itself |

## Landmarks (`env.landmarks`)

`hall` / `gate`: `{ x, z, theta, eaveY, ridgeY }` (gate also `clearWidth`, `clearHeight` of the doorway: the place for
the RPG mode's mist curtain; a talisman rope already hangs across it), `stele: { x, z }`, `impact: { x, z, r }`.

## The guardian statues (`env.statues`)

Two colossal armoured martial deities (수호무신상) stand in the cloud sea either side of the eclipse, facing the
terrace. They are part of the far layer (cheap shader, aerial perspective) and are drawn as their own groups, so one
can be hidden when the RPG boss "wakes".

| | `statues[0]` — west (the nearer one) | `statues[1]` — east |
|---|---|---|
| azimuth / distance from the terrace centre | −13.5°, 205 m | +15.5°, 250 m |
| `position` (centre of its base, world) | (−47.86, −15.5, −199.34) | (66.81, −16.5, −240.91) |
| `scale` (world metres per model unit) | 1.2 | 1.4 |
| `height` (base to the top of the crest / crown) | 46.1 m (crest top at y ≈ 30.6) | 50.8 m (crown top at y ≈ 34.3) |
| weapon | a great glaive planted at its right side (viewer's left), blade top at y ≈ 38.4 | a great sabre planted point-down before its left foot, one hand on the ring pommel |
| other hand | raised, palm out (warding) | broken off above the wrist |
| head | flared, brimmed helmet with a bud-and-spike crest, a lamellar neck guard, a long beard | a flame crown (two points snapped), topknot, lappets |
| damage | weathering only | forearm, half of the scarf, crown points, a shoulder of the cuirass |
| `plinth` | lotus pedestal: `center` (−47.86, −13.1, −199.34), `radius` 7.2 m, `topY` −13.1; on a rock stack rising from the cloud sea (the rock stays when the statue is hidden) | `center` (66.81, −13.7, −240.91), `radius` 8.4 m, `topY` −13.7 |

Each entry: `{ id, azimuth, distance, scale, yaw, position, height, weapon: 'glaive' | 'sabre', weaponSide: ±1,
damaged, plinth: { center, radius, topY }, head, eyes, chest, palm, weaponTop, weaponFoot (world Vector3), triangles,
visible (get / set), eyeGlow (get / set) }`. `yaw` turns the model's +Z toward the terrace centre.
`visible = false` removes the figure (not its rock); `eyeGlow` scales the smoulder in the mask's eye slits (default
0.4 ≈ HDR 0.75, below the bloom threshold; ≥ 1.5 blooms).

Model proportions in units (× `scale`; `far.js` `STATUE`): plinth top 2.0, hem of the lowest skirt 3.4, belt 17.6,
shoulders 26.4, eye slits 30.2, helmet brim 30.5 – 32, crest top 38.4 (crown top 36.3), glaive top 44.9; stance width
≈ 11, shoulder width with pauldrons ≈ 17.5. Design language for anything that must match them: three flaring tiers
of lamellar skirt with scalloped hems, an apron with a boss, a broad belt with a disc buckle, a cuirass with the
black-sun mirror (ring + dark disc) on the chest, three rounded pauldron lames with rolled edges, flared bracers, a
stern mask (heavy V brow, long nose wedge, downturned mouth), a celestial scarf arching behind the head with its
ends trailing past the hips.

## Tiers (`ctx.quality.envDetail`)

| | low (0) | mid (1) | high (2) |
|---|---|---|---|
| shadows (from `ctx.quality`) | off | 1024 | 2048 |
| fire point lights | 0 (baked warm glow + floor pools) | 2 | 4 |
| floor bake | 1024² | 1024² | 2048² |
| stone detail / timber detail / foliage atlas | 512² / 256² / 256² | 1024² / 512² / 512² | 1024² / 512² / 512² |
| relief atlas (8 × 4 cells) / weather map | 1024×512 / 256² | 2048×1024 / 512² | 2048×1024 / 512² |
| stone weathering (cracks, streaks) | ×0.7 | ×1 | ×1 |
| puddle reflection | PMREM | PMREM | PMREM + this frame's screen reflection |
| banner poles | 5 | 8 | 8 |
| lit lanterns (`env.braziers` + `env.lamps`) / dark, toppled ones | 2 + 4 / 1 | 2 + 5 / 2 | 2 + 5 / 3 |
| rubble pieces / chips | ×0.45 | ×0.75 | ×1 |
| weapon racks / loose arms / war drum | 2 / 4 / – | 3 / 6 / ✓ | 3 / 9 / ✓ |
| talisman ropes | gate, hall, one rim rope | + gate wing, both rim ropes | + rope squares round the censers |
| roof tile rows (pitch) / rafters | 0.5 m / every 3rd | 0.36 m / every 2nd | 0.36 m / every 2nd |
| pines / bamboo clumps (culms) / grass tufts | 2 / 3 (5) / 50 | 3 / 5 (7) / 100 | 3 / 6 (9) / 150 |
| statue tessellation | coarse | full | full |
| motes / sparks / leaves | 240 / 50 / 36 | 380 / 80 / 64 | 520 / 110 / 90 (× `particleScale`) |
| mist sheets / shafts | – / 3 | ✓ / 7 | ✓ / 7 |
| sky cloud octaves | 3 | 5 | 5 |
| contact blob shadow (`setContact`) | 0.8 (no shadow map) | 0.25 (deepens PCF contact) | 0.25 |
| **env draw calls** (main pass) | **14** | **14** | **14 + reflection copy + puddle pass = 16** |
| **env triangles** | **~TBD** | **~TBD** | **~TBD** |

Draw calls: sky, stone (+ roof tiles), metal, timber, foliage, floor, far backdrop + statue + statue, cloud sea,
cloth, fire, atmosphere, particles (+ reflection copy and puddle pass on high). The env casts no shadows, so it adds
nothing to the shadow pass. Measured in the lab with `__ED.lab.play('stats')` (whole quality tier via
`--hash "q=low|mid|high"`).

## Art guide (for character, VFX, camera and RPG artists)

**Composition from the fight camera** (`src/cam`: +Z looking −Z, fov 34–40°, tilted down 4.5–8.5°, so the frame
ends only ~12° above the horizon). The eclipse sits at azimuth 2°, elevation 6.2°: in the upper third of every fight
framing, just above the fighters' heads, and between them on a close clinch. Directly behind the duel line the rim
has fallen away, so the fighters' heads and shoulders sit against a calm band: hazed cloud sea, a muted amber horizon
glow, small ink peaks, the two guardian statues (az −13.5° / +15.5°) and a far pagoda left of the corona. Only knee-
to waist-high remains break that band: a few posts of the rim's balustrade, slabs at the lip, dry grass. Keep effects
that must read (projectiles, slashes) in front of that band. The flanks carry the place: the lit stone lanterns
(∓37°), sect banners (±41°), broken gallery columns, the pines leaning in over the vista, then the censers (∓63°),
the hall's eave corner on the far left and the roofed gallery and stele on the far right: **cool centre, warm
sides**. The floor carries history: the diagram's rings, damp hollows and dry dusty stones, long settlement cracks,
three crescent blade gashes, two stamped footprints behind the line right of centre, and the old shattered,
scorched impact behind the line at (−4.4, −6.2).

**All the way round (the action-RPG mode).** North: the vista. West: the hall (천무전) above its stairs — the best
preserved three bays stand open and dark behind their lattice doors, the south end is a fan of fallen rafters and a
scree of tiles; a censer smokes in front of it. South: the gate (산문) at the head of its stairs, lanterns at their
feet, the name board over the doorway, the boundary wall and bamboo behind. East: the roofed gallery, the stele, the
weapon racks, the breach in the wall, the war drum; the darkest side (it faces away from the rim light), lit by a
censer and one lantern.

**The floor (formation diagram, 진법도).** From the centre: the black-sun disc (r < 1.18, polished black), a bronze
limb, an engraved corona of 24 flame tongues (to r = 2.25), two rows of flagstones, the inner formation ring
(r 3.45–4.55: eight marks of three stacked bars — whole, split in two or split in three; our own set, not the
classical trigrams — bronze-edged, star studs between them), the star chart (r 4.6–8.1: 24 bronze studs joined into
six constellations by cut lines), the seal band (r 8.2–9.06: 70 characters of our invented seal script), eight
paired-hairline spokes across the outer field, the outer formation ring (r 12.3–13.3: sixteen marks), a gutter at
the wall. Vector-drawn in the bake shader, so it is as sharp as the bake resolution (1.6 cm / texel on high).

**Architecture (close-ups and cinematics).** *Retaining wall:* a footing course, carved panels between pilaster
stones (cloud scrolls, wave scales, lotus and peony rosettes, a dragon band, the sect crest; the pilasters carry
formation marks), a cap stone with a thunder-meander fascia; *balustrade:* square posts with lotus-bud finials, a
hexagonal top rail, a carved slab (clouds, meander, waves, bars) over a bottom rail; posts and spans are missing,
snapped or leaning where the wall has suffered. *Stairs:* eight worn risers between sloped cheek stones carved with
clouds, newel posts at head and foot. *Timber:* columns of faded red lacquer on lotus bases, a jade band with a petal
collar under the head; lintels in jade with painted fan ends (머리초) and a cloud / dragon / meander band; bracket
sets (공포) reduced to a capital block, crossed arms and ox-tongue ends in two tiers; round eave purlins; rafters under
the eaves; lattice door leaves (창살) with torn paper; the paint has flaked to grey wood in patches (more toward the
foot). *Roofs:* concave slopes that steepen to the ridge and lift at the corners, half-round cover tiles in rows
(real geometry) over pan tiles (relief), round end tiles at the eaves, ridges of stacked tiles ending in upswept
horn tiles. *The name board:* a tall ink-black board in a jade frame, 天 over 武 carved and once gilded, hanging by
one chain. *Stone lanterns (석등):* lotus foot, octagonal shaft with a girdle, lotus bowl, a four-post fire chamber,
a hipped roof stone with lifted corners, a bud. *Censers (향로):* three-legged bronze cauldrons with upright ears and
a band of flames, verdigris in the recesses, on octagonal lotus drums; incense sticks with glowing tips, thin smoke.

**Relief atlas (`ORN.*`, ornament.js).** 8 × 4 cells baked on the GPU, our own drawing: `sunDisc`, `cloud`, `wave`,
`lotus`, `petal`, `meander`, `peony`, `phases`, `mask` (guardian mask), `tile`, `seal` / `seal2`, `panel`, `scales`,
`lattice`, `bars`, `tiger`, `tian` (天), `mu` (武), `dragon`, `cloudPanel`, `studs`, `rope`, `crest`, `flame`,
`danHead`, `brocade`, `plank`. Stone and metal use them as carving; on timber a positive relief amount also paints
them (ochre lines, red or jade bodies on the opposite ground): the faded 단청.

**Light directions** (world, toward the light): key `(-0.42, 0.78, 0.50)` cool white `#dbe5ff`-ish, intensity 3.0,
shadows fall to the back-right; rim `env.rimDir` ≈ `(0.43, 0.41, -0.81)` cold blue `(0.55, 0.68, 1.0)`, 4.2: it rims
heads, shoulders and the right edge opposite the key (metal gets a cold specular top-right), and it is what lights
the north-facing fronts of the gate and the hall; hemisphere sky `(0.10, 0.12, 0.19)` / ground
`(0.06, 0.04, 0.03)`, 0.5; fires warm `(1.0, 0.5, 0.18)`, 20 cd, 16 m range (≈ 13.7 m from the duel centre: a warm
back-side kiss on the fighters).

**Palette and value ranges** (linear HDR, before exposure 1.1 / ACES):

| element | value |
|---|---|
| zenith / mid sky / horizon | 0.001 / 0.004 / 0.015 (blue-black) |
| horizon "eclipse sunset" band | ≤ 0.17, 0.08, 0.04 (muted amber, ±3° of the horizon) |
| corona limb / body / streamers | 2.1 / 0.2–1.2 / ≤ 0.3, cold white `(0.82, 0.9, 1.0)` |
| black disc | 0.0004, minus a small bloom-occlusion offset (the HDR target is signed: the disc cancels the corona's bloom spill so it stays black, sRGB ≈ 0–3) |
| diamond-ring bead | 26 (tiny: blooms into a star) |
| stone, lit | 0.005–0.03 (albedo ≈ 0.08, key masked to 12% on the backdrop; relief cavities darker, lichen up to ×1.45); roof tiles a little bluer and darker |
| timber albedo | lacquer red `(0.20, 0.034, 0.024)`, jade `(0.03, 0.078, 0.064)`, bare wood `(0.05, 0.043, 0.036)`, ochre lines `(0.36, 0.25, 0.08)`: under the cold light they stay dark and desaturated; they open up only in the lantern pools |
| statues | ≈ 0.006–0.02 before haze (key response ×2.9 on the statues so the armour reads in telephoto); eye slits 0.75 |
| lantern flame cores / glow | 3–6 / ≈ 0.3; censer coals ≈ 1–2; incense tips ≈ 2.9 (pin points) |
| floor | 0.02–0.06 lit; dry stones matt (roughness ≈ 0.85–0.95), damp hollows darker and satin (≈ 0.5), puddles mirror the sky (see *Puddles*); key pooled on the fighters (falls to 24% away from them), 9% of the rim |
| near fog / mist | `(0.0105, 0.0125, 0.018)` |
| **fighters should sit at** | 0.1–0.5 mid-tones (key-lit), rims to ~1 |
| **VFX** | cores 2–10 as in CONTRACT.md — anything ≥ 1 blooms and will dominate this backdrop |

Saturation: three or four hues per frame — blue-black stone and sky, amber fire, oxblood cloth and lacquer, ink-green
foliage — all of them far below the fighters. Saturated colour belongs to the fighters and their effects. Avoid amber
/ orange VFX directly against the lanterns on the flanks; frost and violet read strongest against the centre.

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
node tools/shot.mjs env --do "__ED.lab.play('cine', 'otsR')" --at 1.0 --out shots/env/otsR
node tools/shot.mjs env --do "__ED.lab.play('turn', 0, 0, 180)" --at 0.2 --out shots/env/gate
node tools/shot.mjs env --do "__ED.lab.play('statueHead', 0)" --at 0.1 --out shots/env/statue
```

Scenarios: `gameNear` `gameMid` `gameFar` `gameAt(x)` (the game's own fight camera from `src/cam` framing the dummies
1.4 / 4.5 / 9 m apart; `gameAt` = 4.5 m apart centred on `x`; let it settle ~1 s), `near` `mid` `far` (fixed lab
fight views at 6 / 8.5 / 11 m), `edgeL` `edgeR` `close` `reset` (fighter placements),
**`cine(name)`** — the real cinematic vocabulary (`src/cam/shots.js`) played on the dummies by the camera director,
held on its last frame, returning the sample time to advance: `heroL` `heroR` (heroPushIn, anchored on P1 / P2),
`otsL` `otsR` (overShoulder), `sideL` `sideR` (68° orbit, 7.2 m), `sideLow` (55°, 0.45 m high looking up), `crane`
(wideEstablishing), `craneHigh` (topDownSlam), `orbit` (orbitSweep), `skim` (groundSkim), `face` (faceCloseUp),
`dutch` (dutchDrift); `cineList()`.
360°: **`turn(x, z, yaw, eye = 1.7, fov = 60, pitch = 4)`** stands at (x, z) and looks along `yaw` (0 = the vista,
90 = east, 180 = the gate, −90 = the hall); **`rpg(x, z, yaw, dist = 4.6, height = 2.3, fov = 50)`** frames a dummy
at (x, z) in third person.
Close inspection: `inspGate` `inspBoard` `inspGateSide` `inspHall` `inspHallWreck` `inspHallEave` `inspGallery`
`inspGalleryFallen` `inspLantern` `inspCenser` `inspWall` `inspStairs` `inspStele` `inspRack` `inspRim` `inspPine`
`inspImpact` `inspImpactTop` `inspVista`, `topDown` `diagram` `diagramNear` (the floor from above), `overview`
`overviewN` `overviewW`; statues: `statue(i)` `statueHead(i)` `statueStudy(i, yaw, dist)` `statueHide(i, on)`;
hand-placed lab angles `low` `lowWide` `high` `ots` `sideL` `sideR` `sideLowL`; `mood` `moodWarm` `moodOff`,
`pulse` `pulseFrost`, `metal` (chrome dummies to judge the env map), `vfx` (hot HDR spheres), `prime` (no-op, kept
for old capture commands), `stats`.

## Files

| file | contents |
|---|---|
| `index.js` | `createEnvironment`: assembly, lights, focus, PMREM (bound on the env materials), mood, pulse, colliders, puddle reflection (post.onAfterScene), update |
| `config.js` | layout radii, stairs / hall / gate placement, `rimR(θ)`, light directions, palette, tier table |
| `glsl.js` | shared noise, sky gradient, height fog; `GLYPHS`: 天 / 武 brush strokes, the seal-script generator, formation bar groups |
| `bake.js` | GPU-baked maps: the floor's formation diagram (+ damp / dust / cracks, the old duel's scars, the breaking rim), tiling stone and timber detail, the cloth atlas (banner, pennant, hemp, talismans), the foliage atlas |
| `ornament.js` | relief atlas bake (32 cells: `ORN.*`, `panel(cell)`), weather map bake, the relief / weathering / 단청 paint shader chunks for stone, timber and metal |
| `sky.js` | sky dome: eclipse, corona, chromosphere, diamond ring, crepuscular rays, clouds, stars |
| `geometry.js` | merging builder (+ relief channel, per-section triangle accounting) + primitives (chamfered / face-only ashlar blocks, broken blocks, profile sweeps, lathe grids incl. partial arcs, tubes, rocks, `beam`, `prism`, `ringM`) |
| `roof.js` | tile roofs: curved slope patches with cover-tile rows, ridges, rafters, eave boards |
| `ruins.js` | the build context shared by the sub-builders; merged geometries, fire sources, colliders, landmarks |
| `terrace.js` | retaining wall + balustrade, stairs, the court's paving, cliff, the rim's last posts, rubble, the old impact's slabs |
| `timber.js` | columns, lintels, bracket sets; the gallery, the hall, the gate + name board, the boundary wall |
| `dressing.js` | stone lanterns, censers, weapon racks, loose arms, stele, war drum, banner poles, talisman ropes, spilled tiles |
| `flora.js` | pines on rocks, bamboo clumps, dry grass (the foliage mesh) |
| `materials.js` | MeshStandardMaterial patches: key / rim masks (`envFloorKey`), a per-directional-light hook, sky-matched fog, baked glow; stone, timber, metal; the foliage shader |
| `floor.js` | floor material: wetness, puddles (mirror + ripple scatter + the key's sheen under the film), contact band, ground contacts, pulses, warm pools; the broken-rim fan geometry; the puddle reflection pass |
| `far.js` | the guardian statues, ink peaks, the pagoda, cloud sea |
| `atmosphere.js` | haze planes, light shafts, mist sheets, incense smoke |
| `particles.js` | motes, sparks, censer embers, falling leaves (GPU-animated, one draw call) |
| `props.js` | hanging cloth (vertex-shader banners, pennants, talismans) and the fires |
