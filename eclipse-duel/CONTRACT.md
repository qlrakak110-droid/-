# ECLIPSE DUEL (일식결투) — engineering contract

An **original** dark-fantasy 1v1 3D fighting game that runs from a single HTML file (WebGL2, three.js r170 bundled,
no network, no external assets). The point of the project is spectacle: weighty weapon motion, layered skill VFX,
cinematic camera work, hit-stop / slow-motion / impact frames, and detailed armoured characters — the feel of a
modern AAA action RPG boss duel, played on a 2D fighting-game line.

**Originality rule.** Everything is our own design: names, characters, armour, weapons, skills, arena, UI, music.
Do not recreate or reference any existing game's characters, named skills, items, locations, logos, UI or music.
"Dark-fantasy action RPG" is a genre, not a template to copy.

**Quality bar.** Judge every visual against shipped AAA games, not against "good for a browser demo". Timing matters
as much as pixels: anticipation → smear → impact → follow-through → settle. If a screenshot looks like a tech demo
(flat lighting, uniform particle sizes, single-layer effects, mannequin poses), it is not done.

## Roster and setting (fixed)

| id | name | title | weapon | element / palette (linear HDR hints) | feel |
|---|---|---|---|---|---|
| `kael` | 카엘 KAEL | 잿불의 집행자 · Cinder Warden | greatsword (two-handed) | ember / magma: core `(8,3,0.6)` → `(3,0.5,0.05)` → smoke | heavy, slow, huge arcs |
| `iska` | 이스카 ISKA | 서릿별 무녀 · Froststar Oracle | twin crescent blades | frost / starlight: core `(1.5,4,8)` → `(0.3,1.2,3)` → white mist | fast, precise, airy |
| `vorn` | 볼른 VORN | 뇌명의 창기사 · Stormcaller Lancer | war spear | lightning: core `(5,3.5,9)` violet-white → gold sparks `(8,5,1)` | mid speed, long reach, dashes |

Arena: **일식의 폐허 · Eclipse Ruins** — a ruined circular colosseum on a sea cliff under a total solar eclipse.

## Project layout and ownership

```
eclipse-duel/
  CONTRACT.md            this file
  tools/build.mjs        node tools/build.mjs game|<lab>  -> dist/eclipse-duel.html | build/<lab>.html (single file)
  tools/shot.mjs         headless capture harness (see "Visual verification")
  src/index.html         page shell (fragment)                      owner: lead
  src/main.js            game entry                                 owner: integration
  src/core/              app loop, time, math, lab scaffold         owner: lead   (FROZEN — do not edit)
  src/post/              HDR + bloom + screen FX                    owner: lead   (FROZEN — do not edit)
  src/vfx/               particles, ribbons, mesh FX, presets       owner: vfx
  src/char/              rig, skinned build, animation, IK, cloth, armour kit, weapons
  src/env/               arena, sky, lighting
  src/cam/               fight camera, shake, cinematic sequencer
  src/audio/             procedural WebAudio SFX + music
  src/ui/  src/input/    DOM HUD / menus / touch controls, input mapping
  src/game/logic/        pure-JS deterministic fighting rules (no three.js, no DOM)
  src/game/              presentation binding (logic <-> char/vfx/cam/audio/ui)
  src/fighters/<id>/     per-fighter look, clips, moves, skill choreography
  src/labs/<name>.js     sandbox pages, one per module
```

**Stay inside the directory you own** (plus your own `src/labs/<name>.js`). If you need a change in someone else's
directory (especially `core/`, `post/`, `tools/`), do not make it — describe it in your final report.
**Do not run git commands that change repository state** (no add/commit/checkout/stash); the lead commits.
Every module directory must contain a `README.md`: the API reference downstream authors will code against
(signatures, option tables with defaults and units, conventions, 2-3 usage examples). Keep it accurate.

## Conventions

- **Units / axes.** Metres, seconds, Y up, right-handed. The fight line is the X axis at `z = 0`; the floor is the
  plane `y = 0`. P1 starts at `x = -2.5` facing `+X`, P2 at `x = +2.5` facing `-X`. Arena limits `|x| <= 9`.
  The camera always stays on the `+Z` side (`z > 0.5`) looking toward `-Z`; nothing needs to look good from behind.
- **Fighter-local frame** `(f, u, s)`: forward (the way the fighter faces along X), up (Y), side (toward the camera,
  always `+Z`). world = `(x + f * facing, u, s)`. Author every per-move offset in this frame so P2 mirrors for free.
- **Height reference.** Fighters are ~1.9 m tall; chest ~1.35 m, head ~1.75 m, hips ~1.0 m.
- **Colour.** three.js colour management is on (hex / CSS colours are sRGB and get converted to linear). The scene is
  rendered to a linear HDR (half-float) target. Tone mapping (ACES) + sRGB encoding happen once, in the post composite.
  Bloom starts at luminance ~1.0, so emissive/VFX colours are HDR: `new THREE.Color(r, g, b)` with components 2–10
  for hot cores, <1 for smoke. ACES turns very hot cores white with a coloured bloom halo — use that.
  Canvas textures holding colour: `texture.colorSpace = THREE.SRGBColorSpace`; data textures (noise, masks, normals) stay linear.
- **Lights.** three r170 uses physical light units: point lights need intensities of tens to hundreds (candela) to
  matter at a few metres. **Never add or remove lights at runtime** (it recompiles every lit shader → hitch). Use a
  fixed pool sized `ctx.quality.maxLights` whose unused lights sit at intensity 0.
- **Time.** `ctx.time` has two clocks. Game time (`dtGame`) is scaled by slow-motion and frozen by hit-stop: fighters,
  animation and most VFX use it. Real time (`dtReal`) drives UI, camera shake and post pulses. Never read
  `performance.now()` / `Date.now()` for simulation.
- **Determinism.** No `Math.random()` — use `ctx.rng` (or `makeRng(seed)` from `core/math.js`). In test mode the
  harness advances fixed 1/60 s frames, and the same inputs must produce the same picture.
- **Performance (phones matter).** Budget for the whole game on the `high` tier: <= 160 draw calls, <= 350k triangles.
  Characters: <= 60k triangles and <= 6 draw calls each (merge into few skinned meshes). Environment: <= 45 draw
  calls. VFX: one draw call per particle layer / effect type (instancing), and watch overdraw — a few big soft
  sprites cost more than hundreds of small sparks. No per-frame allocations in hot paths (pool vectors, reuse
  buffers). Scale counts with `ctx.quality.particleScale`, detail with `ctx.quality.envDetail`. Compile materials up
  front (`renderer.compile` / a `prewarm()`), never on first use mid-fight. Dispose what you create.
- **No external anything.** No fetch, no images, no fonts files, no CDN. Textures are generated on canvas / in
  shaders, models are built from code, sound is synthesised.
- **Code style.** ES modules, plain JS (no TypeScript), JSDoc on public functions, 2-space indent, no dead code.

## Core API (read `src/core/*.js` and `src/post/index.js` — they are short)

`createApp()` → `ctx`:

| field | meaning |
|---|---|
| `ctx.renderer / scene / camera` | THREE.WebGLRenderer, Scene, PerspectiveCamera (fov 40, near 0.1, far 800) |
| `ctx.quality` | `{tier:'low'|'mid'|'high', mobile, pixelRatio, msaa, shadows, shadowSize, bloomLevels, particleScale, envDetail, cloth, maxLights}` |
| `ctx.time` | `{real, game, dtReal, dtGame, scale, baseScale, hitstop(sec), slowmo(scale, dur, {easeIn, easeOut})}` |
| `ctx.onUpdate(fn(dtGame, dtReal), order)` | per-frame callback; `ctx.ORDER = {INPUT:0, GAME:10, CHAR:20, VFX:30, CAM:40, ENV:50, UI:60, POST:70}` |
| `ctx.rng` | seeded RNG: `rng()`, `.range(a,b)`, `.int(a,b)`, `.sign()`, `.pick(arr)`, `.chance(p)`, `.of(numberOr[min,max])` |
| `ctx.events` | `on(name, fn)` → off, `emit(name, ...args)` |
| `ctx.viewport` | `{w, h, cssW, cssH, pr, aspect}`; event `'resize'` |
| `ctx.flags`, `ctx.test` | URL flags (`#test&q=low...`), test mode boolean |
| `ctx.vfx / audio / cam / env / ui / input / game` | set by the module factories below (`null` until created — guard optional peers) |
| `ctx.post` | `fx` (live params), `to(params, dur, ease)`, `pulse(key, amount, {attack, hold, release})`, `flash(color, amount, opts)`, `impactFrame({duration, invert, mono})`, `radialAt(worldPos)`, `setBaseline(params)`, `reset(dur)`, `distortionScene` |

`post.fx` keys: `bloom, bloomThreshold, bloomKnee, bloomRadius, exposure, chroma, radial (+radialCenter), vignette,
grain, saturation, contrast, flash (+flashColor), invert, mono, letterbox, distortion, tint, lift`.
`post.distortionScene`: meshes placed here are drawn with the main camera into a half-res buffer; their fragment
output `.rg` is a signed screen-space UV offset (additive, typical magnitude 0.005–0.05). Hide them when idle.

`core/math.js`: `clamp, saturate, lerp, invLerp, remap, smoothstep, damp, Ease.* (name or fn via ease()), curve(points), makeRng, TAU, DEG`.

## Module contracts

Each factory takes `ctx`, stores itself on `ctx.<name>`, registers its own `ctx.onUpdate` at the right order, and
returns the object. Names and signatures below are binding; add more, but do not rename these. Options not listed are
yours to design — document them in your README.

### `src/vfx/index.js` — `createVfx(ctx)` → `ctx.vfx`

Positions accept `THREE.Vector3` or `[x, y, z]`. Colours accept `THREE.Color`, hex, or `[r, g, b]` linear HDR.
Every spawn call returns a handle with at least `kill()`; continuous things also have `stop()` (stop emitting, let
existing particles finish). All effects run on game time unless `realtime: true`.

```
vfx.prewarm()                      compile every program now
vfx.clear()                        kill everything (round reset)
vfx.schedule(delay, fn)            run fn after `delay` game-seconds (honours hit-stop / slow-mo)

vfx.burst(def, at)                 one-shot particle burst.   at = { pos, dir?, scale?, color?, count?, vel? }
vfx.emitter(def, at) -> h          continuous emitter: h.pos (Vector3), h.dir, h.rate, h.follow(object3D, offset?), h.stop(), h.kill()
     def = { tex, blend:'add'|'alpha', count | rate, life:[a,b], shape:{type:'point'|'sphere'|'disc'|'ring'|'cone'|'box'|'line', ...},
             speed:[a,b], spread, gravity, drag, turbulence:{amp,freq}, size:[a,b], sizeOverLife, stretch, spin,
             color: [[t, r,g,b,a], ...]  (HDR ramp over life), groundFade, collide:'ground', ... }
     Particles are simulated on the GPU (analytic motion in the vertex shader, instanced quads, ring buffer):
     no per-particle CPU work after spawn. Soft intersection with the floor is analytic (fade near y = 0).

vfx.trail({ a, b, ... }) -> h      weapon trail ribbon between two sockets (Object3D): h.start(), h.stop(), h.kill()
vfx.ribbon({ ... }) -> h           ribbon that follows one moving point (projectile tails): h.setPosition(v) / h.follow(obj)
vfx.slash({ pos, ... })            crescent slash arc (shader mesh: scrolling noise, erosion, hot edge)
vfx.ring({ pos, ... })             expanding shockwave ring (ground / camera-facing / arbitrary normal)
vfx.pillar({ pos, ... })           vertical column of energy
vfx.beam({ from, to, ... }) -> h   beam between two points: h.setEnds(a, b)
vfx.bolt({ from, to, ... })        lightning bolt with branches and flicker
vfx.spikes({ pos, ... })           lit crystal / rock shards that grow from the ground, hold, then shatter
vfx.debris({ pos, ... })           chunky lit fragments with gravity and floor bounce
vfx.decal({ pos, kind, ... })      floor decal (crack / scorch / frost / rune circle / glow), fades out
vfx.flare({ pos, kind, ... })      camera-facing glow / star / anamorphic streak
vfx.light({ pos, color, intensity, range, duration, ... }) -> h    pooled point-light flash (h.follow(obj))
vfx.distort({ pos, kind:'shock'|'heat'|'lens', ... })   screen-space refraction via ctx.post.distortionScene
vfx.speedlines({ ... })            full-screen anime speed / focus lines
vfx.afterimage(object3D, { ... })  fading ghost copies of a (skinned) character pose

vfx.define(name, fn(vfx, at, opts))   register a composed preset
vfx.play(name, at, opts) -> h         play a preset   (at = { pos, dir?, facing?, scale?, color?, target? })
```

### `src/char/index.js` — `createCharacter(ctx, design)` → `Character`

A procedural armoured humanoid: one skeleton, few `SkinnedMesh`es (rigid armour plates bound to single bones plus a
smooth-skinned under-suit so joints never show gaps), cloth / cape simulation, weapon, sockets.

```
char.root                         Object3D to place on the fight line (the model's own forward is +X)
char.setFacing(+1 | -1)           face +X or -X
char.bones                        hips, spine, chest, neck, head, shoulderL/R, upperArmL/R, foreArmL/R, handL/R,
                                  thighL/R, shinL/R, footL/R, toeL/R (+ any extras)
char.sockets                      Object3D markers: weaponBase, weaponTip (one pair per blade: weaponBase2/weaponTip2 ...),
                                  handL, handR, chest, head, hips, footL, footR, back
char.play(clip, { fade = 0.1, speed = 1, loop, startAt = 0 })
char.clip / char.clipTime / char.clipDuration / char.finished ; char.setClipTime(t)
char.update(dtGame, dtReal)       advance animation, IK, secondary motion, cloth (call once per frame)
char.rootDelta                    {f, u} root motion consumed this update, in fighter-local metres
char.onEvent(fn(name, data))      clip event markers crossed this update
char.flash(color, amount, dur)    emissive hit flash on every material
char.impulse({ bone | 'body', dir: [f,u,s], amount })   additive physical flinch that springs back
char.setVisible(b), char.dispose()
```

Clips are data: `defineClip(name, { duration, loop, keys: [...], events: [...] })` (registry in `src/char/anim.js`).
A key holds FK rotations in degrees per bone **and/or** IK effector targets for hands and feet (fighter-local
positions relative to the root), hips offset / rotation, an ease per key, and optional root-motion displacement.
Two-handed weapons keep the off hand on the grip by IK. The README must document every bone's axis and sign
convention with worked examples, because many clips will be authored against it.

### `src/env/index.js` — `createEnvironment(ctx, opts)` → `ctx.env`

```
env.envMap                        PMREM environment for metals (also assigned to scene.environment)
env.sun                           the shadow-casting key light;  env.setFocus(x)  keeps the shadow frustum on the fighters
env.setMood({ darken: 0..1, tint?, duration })   dim / tint the whole world (lights, sky, fog) for ultimates; setMood(null) restores
env.pulse(pos, color, strength)   optional reaction of the floor / air to a big impact
env.bounds = { minX: -9, maxX: 9 }, env.floorY = 0
```
The environment must read as a rich backdrop while staying darker and less saturated than fighters and VFX.

### `src/cam/index.js` — `createCameraDirector(ctx)` → `ctx.cam`

```
cam.setTargets(a, b)              two things with a world position (Object3D or () => Vector3) at chest height
cam.fight                         framing params (distance range, height, look height, fov, lag ...)
cam.shake(amount, { duration, freq, decay, dir })      trauma shake on real time (keeps going through hit-stop)
cam.kick({ fov, push, roll, duration })                impulse: fov punch / dolly push / roll
cam.zoom(factor, duration)                             temporary push-in while in fight mode
cam.play(shots, { anchor, target, facing, onDone, blendOut }) -> h     cinematic sequence; h.stop()
     shot = { dur, from: { pos:[f,u,s], look:[f,u,s], fov, roll }, to: {...}, ease, cut: true | blendSeconds,
              space: 'anchor' | 'target' | 'world' | 'mid', shake, slowmo, letterbox }
     positions are in the anchor's fighter-local frame (f flips with facing; s stays toward +Z)
cam.stop(blend = 0.35)            back to fight framing
cam.letterbox(on, dur)            drives post.fx.letterbox
cam.mode                          'fight' | 'cine' | 'free'
```

### `src/audio/index.js` — `createAudio(ctx)` → `ctx.audio`

All sound is synthesised with WebAudio. Must be silent and error-free when no AudioContext is available.

```
audio.unlock()                    call from the first user gesture
audio.play(name, { volume, pitch, pan, delay })       one-shot
audio.loop(name, opts) -> h       h.setVolume(v, fade), h.stop(fade)
audio.music(track | null, { fade })                   'title' | 'battle' | 'ultimate' | 'victory'
audio.setVolume({ master, sfx, music }), audio.duck(amount, dur), audio.list()
```
Required names: `swing_light swing_heavy swing_huge hit_slash_light hit_slash_heavy hit_blunt hit_crit guard
guard_break dodge step land body_fall fire_ignite fire_burst fire_roar fire_loop explosion ice_form ice_shatter
ice_crack frost_wind volt_zap volt_strike volt_charge volt_loop charge_up release shockwave magic_cast rune
ult_start ult_impact slowmo_in slowmo_out ui_move ui_select ui_back announce_round announce_fight announce_ko bell`.

### `src/input/index.js` — `createInput(ctx)` → `ctx.input`,  `src/ui/index.js` — `createUI(ctx)` → `ctx.ui`

Actions: `left right up down light heavy skill1 skill2 skill3 ult guard dodge pause confirm back`.

```
input.held(action, player = 0), input.pressed(action, player = 0)   (pressed = went down this frame)
input.axis(player = 0)            -1 | 0 | +1 on X
input.on(fn(action, down, player))        event stream (menus)
input.setVirtual(action, down, player)    touch buttons / AI / tests feed the same path
Keyboard P1: A/D move, W/S up/down, J light, K heavy, U I O skills, P ult, L guard, Space dodge, Enter confirm, Esc pause/back.
Gamepad supported.

ui.show(screen, data)             'title' | 'select' | 'vs' | 'hud' | 'pause' | 'result' | 'movelist' | 'none'
ui.on(event, fn)                  'start' | 'pick' | 'rematch' | 'toTitle' | 'resume' | 'quality' ...
ui.hud.set({ time, p1: { name, hp, hpMax, fp, fpMax, ult, rounds, element }, p2: {...} })   every frame, cheap
ui.hud.skills(side, [{ id, name, key, cd: 0..1, ready, cost, icon }])
ui.hud.combo(side, hits, damage), ui.hud.announce(text, { sub, style, duration })
ui.hud.cinematic(on)              fade the HUD out / in around cinematics
ui.touch.setVisible(b)            virtual stick + action buttons (landscape overlay; portrait: stage on top, pad below)
```
Text is Korean first (short English subtitles are fine). The UI owns the `#stage` rectangle (CSS) — the canvas
follows it. It must work at 400 px wide portrait, 800x360 landscape phone, and desktop.

### `src/game/logic/` — pure deterministic rules (no three.js / DOM)

`createMatch({ fighters: [defA, defB], controllers, rules, rng })` → `match` with `match.step(dt)` (dt <= 1/60),
`match.fighters[i]` state (`x, y, facing, hp, fp, ult, state, move, moveTime, combo ...`), and an event stream
(`moveStart`, `moveEvent` (timeline markers for presentation), `hit`, `guard`, `guardBreak`, `ko`, `roundStart`,
`roundEnd`, `matchEnd`, `projectile*`, `cinematic*` ...). A fighter definition is data: stats + `moves` (duration,
hit windows with boxes in the fighter-local frame, damage, stun, knockback, hit-stop, cancels, armour / invulnerable
windows, cost, cooldown, motion, spawned projectiles, cinematic lock, named timeline markers). Presentation
(clips, VFX, camera, audio) hangs off the named markers, so rules stay testable in Node.

## Labs and visual verification

Each module has a sandbox page `src/labs/<name>.js` built on `createLab` (`src/core/lab.js`: neutral stage, orbit
view, named scenarios). Look at `src/labs/post.js` for the pattern.

```
node tools/build.mjs <lab>                                   # build/<lab>.html (open in a browser to play with it)
node tools/shot.mjs <lab> --do "__ED.lab.play('name')" --at 0.05,0.15,0.3,0.6 --sheet-only --out shots/<module>/name
node tools/shot.mjs <lab> --view "0,1.2,0,6,25,10" --at 0 --out shots/<module>/still
```
`--sheet` / `--sheet-only` writes one contact sheet (`*_sheet.png`) of all captured times — read that image to judge a
whole animation in one look; capture single full-size frames when you need detail. Shader compile errors and
exceptions are printed by the harness. Put captures under `shots/<module>/`.

**You must look at your own work.** Build, capture, read the PNGs, criticise them against the quality bar, fix,
repeat. Do not report something as done that you have not seen rendered. SwiftShader is slow but correct; a capture
run takes a few seconds.
