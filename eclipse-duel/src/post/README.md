# src/post — renderer: HDR scene, depth, AO, atmosphere, light shafts, DOF, bloom, grade, shadows

Owner: rendering lead. Files: `index.js` (pipeline + API), `shaders.js` (GLSL), `grade.js` (grade presets),
`shadows.js` (shadow-frustum manager, `ctx.shadows`). Lab: `src/labs/post.js` (`node tools/shot.mjs post ...`).
Art direction: `MURIM.md` (ink-wash night: deep blacks, restrained hues, warm lantern pools, the pale cold corona).

`createApp()` creates both: `ctx.shadows = createShadows(ctx)` then `ctx.post = createPost(ctx)`. Everything below is
reachable as `ctx.post.*` / `ctx.shadows.*`. Nothing here needs to be called for the game to look right: the defaults
are tuned for the arena, the sun follows `ctx.env.sunDir`, fog lights follow the scene's point lights and the shadow
window follows the shadow casters.

## Frame (per tier)

```
shadow fit (inside the scene render: scene.onBeforeRender)          ctx.shadows.update      high / mid
scene -> HDR target (half float, MSAA x4 on high) + DepthTexture     MSAA colour + depth resolved by three
onAfterScene hooks (env puddle reflection ...)
distortion buffer (half res, only when a distortion mesh is visible)
depth  -> half-res linear depth (R16F, metres)                        1 pass, 4 taps        high / mid
AO     -> half res (RG16F: ao, depth) + bilateral blur H + V          3 passes              high (10+7 taps) / mid (6+5)
shafts -> quarter res: mask + radial blur (x2 on high)                2-3 passes            high (2x16) / mid (1x20)
DOF    -> half res: prep (colour + CoC) + bokeh gather                2 passes, only while post.dof is active
bloom  -> prefilter + down chain + additive tent up chain             as before (4/5/6 levels low/mid/high)
composite (full res): distortion / radial / chroma / sharpen -> DOF mix -> AO -> fog + sun lobe + fog lights ->
          shafts -> bloom -> exposure / tint / lift -> ACES -> sRGB -> grade -> impact frame (ink) -> flash ->
          vignette -> grain + triangular dither -> letterbox
```

Every program is compiled in `createPost` (`post.prewarm()`); runtime switches are uniforms, so nothing compiles
mid-fight. Low has no depth texture: only the composite (grade, dither, DRS sharpening) and bloom.

## Quality knobs (`ctx.quality`, `src/core/util.js`)

| key | low | mid | high | meaning |
|---|---|---|---|---|
| `msaa` | 0 | 0 | 4 | samples of the HDR scene target |
| `shadows` / `shadowSize` | off | 1024 | 2048 | key-light shadow map (window fitted to the casters: ~3-5 mm texels at 2048) |
| `depth` | false | true | true | scene DepthTexture (+ half-res linear depth) |
| `ao` | 0 | 1 | 2 | 1: 6 taps + 5-tap blur, 2: 10 taps + 7-tap blur (half res) |
| `fog` | 0 | 1 | 2 | post height fog + sun lobe; fog lights: 2 (mid) / 4 (high) |
| `shafts` | 0 | 1 | 2 | 1: one 20-tap radial pass, 2: two 16-tap passes (quarter res) |
| `dof` | 0 | 1 | 2 | gather taps 16 / 32 (half res); max bokeh radius 14 / 22 half-res px |
| `bloomLevels` | 4 | 5 | 6 | |

URL overrides for A/B checks: `#ao=0..2 #fog=0..2 #shafts=0..2 #dof=0..2 #msaa=0|4 #shadow=0|512..4096`.

## API

### Live parameters: `post.fx`, `post.to`, `post.pulse`, `post.setBaseline`, `post.reset`

`post.fx` numeric keys (all can be `pulse`d and tweened with `to`):

| key | default | meaning |
|---|---|---|
| `bloom, bloomThreshold, bloomKnee, bloomRadius` | 1, 1.0, 0.6, 1 | bloom strength / HDR threshold / knee / up-sample radius |
| `exposure` | 1 | linear multiplier before ACES |
| `chroma` | 0 | chromatic aberration 0..1 |
| `radial` (+ `radialCenter`, `radialAt(worldPos)`) | 0 | radial blur 0..1 |
| `vignette, grain` | 0.32, 0.03 | |
| `saturation, contrast` | 1, 1 | display-referred, after the grade |
| `flash` (+ `flashColor`) | 0 | 0..1 mix toward the flash colour |
| `invert, mono` | 0 | impact frame mixes |
| `ink` | 1 | impact-frame style: 0 black / white, 1 ink on paper (dry-brush edge, paper fibre) |
| `letterbox` | 0 | 0..1 cinematic bars |
| `distortion` | 1 | scale of the distortion buffer |
| `ao` | 1 | AO strength 0..1.5 (0 skips the AO passes) |
| `fog` | 1 | post-fog density / opacity scale 0..2 (0 = off) |
| `shafts` | 1 | light-shaft strength scale 0..3 (0 skips the passes) |
| `sharpen` | 0 | extra sharpening 0..1 (below 100 % dynamic resolution adds `(1 - scale) * 1.8`; -1 disables it) |
| `toneAmount, toneBalance` | 0.05, 0.1 | split-toning strength / crossover (-1..1) |

Colour keys (`THREE.Color`; `to()` / `setBaseline()` accept `THREE.Color`, `[r, g, b]` linear, hex / css sRGB):
`tint`, `lift` (linear, before ACES), `gradeLift`, `gradeGamma`, `gradeGain`, `toneShadows`, `toneHighlights`
(display-referred grade).

```js
post.to({ exposure: 0.45, saturation: 0.5, letterbox: 1, tint: 0x9fb4ff }, 0.3);  // persistent, real seconds
post.pulse('chroma', 0.6, { attack: 0.015, hold: 0, release: 0.3 });             // transient, additive
post.setBaseline({ exposure: 1.1, vignette: 0.4 });   // the neutral look (env calls it once); reset() returns to it
post.reset(0.4);
post.flash(0xffffff, 0.3, { release: 0.2 });
post.impactFrame({ duration: 0.05, invert: 0, mono: 0.7 });   // 3 frames of ink on paper
```

### Grade: `post.grade(nameOrParams, duration = 0.6, easing = 'inOutSine')`

Presets (`grade.js`, also exported as `GRADES`): `night` (default: ink-black shadows with a breath of blue, warm
paper-toned highlights), `ink` (stronger ink-wash: saturation 0.72, contrast 1.1), `eclipse` (ultimate darkness: cold
steel), `ember` / `frost` / `storm` (per element), `victory`, `neutral` (ACES only). A named preset without its own
saturation / contrast tweens them back to the baseline. An object can carry any grade key:

```js
post.grade('ember', 0.4);                       // KAEL's ultimate
post.grade({ toneAmount: 0.12, gradeGain: [1.08, 1.0, 0.9] }, 0.3);
post.grade('night', 0.8);                       // back (post.reset() also returns the grade to the baseline)
```

### Atmosphere: `post.setSun`, `post.fog`, `post.fogLights`, `post.shafts`

```js
post.setSun(dirOrPos, color = keep, strength = 1, { point = false })
```
The light the fog scatters (Henyey-Greenstein forward lobe) and the light shafts radiate from. `dirOrPos` is a unit
direction **toward** the light (default) or a world position with `{ point: true }`. Until it is called, the sun follows
`ctx.env.sunDir` (the eclipse) with a cold corona colour `(0.82, 0.9, 1.0)`.

```js
post.fog(params, duration = 0)   // returns the live fog object; numbers and color tween when duration > 0
```

| fog key | default | unit / meaning |
|---|---|---|
| `density` | 0.018 | 1/m extinction at `floorY` |
| `falloff` | 0.6 | 1/m exponential height falloff (ground mist) |
| `haze` | 0.0012 | 1/m height-independent haze |
| `maxOpacity` | 0.45 | cap of the fog opacity |
| `floorY` | 0 | m |
| `start` | 3 | m: no fog closer than this |
| `far` | 36 | m: the fog integrates up to here (the env shaders fog the far distance) |
| `skyDistance`, `sky` | 60, 0.25 | sky pixels count as this far and get this fraction (keeps the black sun black) |
| `color` | `[0.0045, 0.0055, 0.0085]` | ambient in-scatter, linear HDR |
| `sunPhase`, `sunScatter` | 0.8, 0.006 | HG g of the sun lobe; lobe = sun colour * strength * sunScatter * phase |
| `lightScale`, `lightRadius` | 0.8, 0.35 | point-light glow (candela * density / 4π, closed-form airlight), core radius m |
| `dim` | 0 | 0..1 manual dimming, added to the env mood darkness (`env.setMood`) |

Fog is applied in the composite from the full-res depth: `col = col * (1 - op) + inscatter * op`, with bright pixels
(emitters, VFX) kept unattenuated so the fight never disappears into it. While `env.setMood` darkens the world the fog
colour, sun lobe, fog lights and shafts dim with it.

```js
post.fogLights([{ pos: [x, y, z], color: [1, 0.55, 0.25], intensity: 30, radius: 0.4 }, ...])   // explicit
post.fogLights(null)                                                                              // auto (default)
```
Auto: the strongest visible `PointLight`s of the scene (brazier pool, VFX light pool) by `intensity * max(color)`,
rescanned every 120 frames; 4 on high, 2 on mid.

```js
post.shafts(params, duration = 0)   // returns the live object
```

| shafts key | default | meaning |
|---|---|---|
| `strength` | 0.9 | HDR multiplier (also `fx.shafts`) |
| `threshold` | 0.25 | far / sky brightness above which a pixel radiates |
| `radius` | 0.3 | uv radius around the sun that radiates (the corona; keeps VFX from radiating) |
| `length`, `decay` | 0.9, 0.965 | fraction of the way to the sun sampled; per-sample decay |
| `glow` | 0 | synthetic glow around the sun (for a source the scene does not draw bright) |
| `skyDepth` | 26 | m: pixels farther than this (to 2x) count as backdrop |

Shafts fade out when the sun leaves the screen and are weaker over near geometry (40 % at 3 m).

### Ambient occlusion: `fx.ao` (strength) and `post.ao(params)` (shape)

Half-res obscurance from the depth buffer (normals rebuilt from depth), bilateral blur, edge-aware upsample in the
composite; bright pixels (emitters / VFX) are not darkened. `post.ao({ radius: 0.4, intensity: 1.25, bias: 0.002,
fadeFar: 40 })` (m, -, m per m of depth, m) returns the current values; scale `radius` with the subject (a 9 m colossus
wants ~1.2). Returns `null` on tiers without AO.

### Depth of field: `post.dof(opts | null, duration = 0.35)`

Off by default; meant for cinematic shots (the camera team drives it). Half-res bokeh gather; the composite mixes it
by the full-res circle of confusion (far field + near-field spill).

| opt | default | meaning |
|---|---|---|
| `focus` | 6 | metres along the view axis, or a `Vector3` / `[x, y, z]` / `Object3D` / `() => pos` kept in focus every frame |
| `aperture` | 1 | 0..1.5 blur strength (1 = bokeh radius ~2.8 % of the screen height in the far distance) |
| `range` | 0.6 | m in front of / behind the focus that stay sharp |
| `near` | 1 | foreground blur scale (0 = none) |

```js
post.dof({ focus: actor.char.sockets.head, aperture: 1, range: 0.4 }, 0.3);   // rack focus onto a face
post.dof(null, 0.5);                                                           // fade out
post.dofActive                                                                 // true while it costs anything
```

### Scene depth for other modules

* `post.depthTexture` — `THREE.DepthTexture` of the **current** frame (raw [0, 1], nearest). Valid in `onAfterScene`
  and later passes. Re-created on resize / dynamic-resolution changes: read the getter every frame. `null` on low.
* `post.linearDepth` — half-res linear view depth (metres, R16F) of the last rendered frame.
* `post.depthUniforms` — stable uniform objects for `ShaderMaterial`s: `tSceneDepth` (half-res linear depth of the
  **previous** frame: in-scene materials cannot read the depth buffer they are drawn into), `uSceneRes` (scene target
  size, the `gl_FragCoord` space), `uCamNearFar`, `uCamProj` (`P[0], P[5], P[8], P[9]`). On low `tSceneDepth` is a 1x1
  texture at 800 m (soft fades become 1).
* `post.DEPTH_GLSL` — `edSceneDepth()` (m), `edFragDepth()` (this fragment's view depth, m), `edSoftFade(softness)`.

```js
const mat = new THREE.ShaderMaterial({
  transparent: true, depthWrite: false,
  uniforms: { ...ctx.post.depthUniforms, uColor: { value: c } },        // spread: the same uniform objects, kept live
  vertexShader, fragmentShader: ctx.post.DEPTH_GLSL + `... gl_FragColor = vec4(uColor * a * edSoftFade(0.4), 1.0);`,
});
ctx.post.onAfterScene((renderer, target, camera) => { /* ctx.post.depthTexture is this frame's depth here */ });
```

### Debug and stats

`post.debugView('ao' | 'depth' | 'shafts' | 'dof' | 'off')`, `post.features` (`{ depth, ao, fog, shafts, dof }` compiled
for this tier), `post.stats.passes` (draw calls after the scene: post passes), `post.stats.msPost` (JS submit ms of the
post chain, with `#prof`), `__ED.info().post / .shadow`.

## Shadows: `ctx.shadows` (`shadows.js`)

The key light's orthographic shadow camera is fitted to the shadow casters every frame, inside the scene render
(`scene.onBeforeRender`: world matrices are fresh, the shadow pass has not run yet).

* `mode`: `'auto'` (default: every visible `castShadow` mesh; skinned meshes by up to 48 sampled bones + `bonePad`),
  `'manual'` (`focus(center, radius)`: a world sphere, kept until the next call), `'off'` (the light is left alone).
* `setKey(light | null)`: the managed `DirectionalLight` (auto: the first `castShadow` DirectionalLight in the scene,
  i.e. `env.sun`).
* The window is a square in light space sized `minExtent * step^k` (4.5 m .. 40 m), grows at once and shrinks after
  `shrinkDelay` s, and is snapped to a world-fixed texel grid: no crawling edges. near / far are fitted to the casters
  and the floor their shadows land on (`ctx.env.floorY`).
* Bias in texels of the window: `bias = -0.6 texel / depth range`, `normalBias = 1.4 texels` (crisp contact, no acne,
  no peter-panning). Filtering: three's PCFSoft (3x3 bilinear PCF).
* It owns only `light.shadow.camera` bounds / near / far and `light.shadow.bias / normalBias`. Position, target,
  colour, intensity and `mapSize` stay with the env (`env.setFocus(x)` keeps placing the light; it is harmless).
* `params` (`margin, minExtent, maxExtent, step, shrinkDelay, biasTexels, normalBiasTexels, bonePad, depthPad`),
  `info` (`{ mode, extent, texel, near, far, casters, fitted }`), `rescan()` after adding a new caster type.

```js
ctx.shadows.focus(boss.root.position, 6);   // a cinematic on the colossus: frame its shadow only
ctx.shadows.mode = 'auto';                   // back
```

## Budgets (measured, see CONTRACT.md "Post and quality")

Post passes after the scene (draw calls): low 8 (bloom 7 + composite; as before), mid 16 (was 10), high 19 (was 12;
+2 while DOF is active); +1 on any tier while a distortion mesh is visible. GPU fill:
high ≈ 1x full-res composite + ~2.2x half-res + ~0.6x quarter-res fullscreen equivalents on top of bloom; mid ≈ 2/3 of
that; low unchanged from before. JS submit of the post chain ~0.25-0.4 ms (high).
