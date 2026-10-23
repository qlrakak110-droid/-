# review-car-glass (wf_c66355a3-3a5)

- status: completed
- failed agents (never finished, usually the usage limit): none

## review:render

```json
{
 "findings": [
  {
   "title": "The inside (BackSide) glass pass never takes its inside branch because gl_FrontFacing is always true for single-sided materials in three r147",
   "file": "/home/user/-/studio/car_glass.js",
   "where": "FRAG_MAIN line 76: `bool cgIn = ! gl_FrontFacing;`, used by GWCarGlass.inner() (make(..., THREE.BackSide, 'in'), line 261). The taxi_model.js 'inside glass pass' hook adds this inner mesh to every high-detail glass piece.",
   "severity": "major",
   "failure": "In three r147, WebGLState.setMaterial calls frontFace(CW) for side === BackSide (minified: `let i=1===t.side;e&&(i=!i),q(i)` with q(true) -> t.frontFace(2304)), and back-face culling stays on. Every fragment the BackSide material draws is therefore GL-front-facing, so gl_FrontFacing == true and cgIn == false. The same is true for FrontSide. Only DoubleSide (the legacy 'both' material) ever sees gl_FrontFacing == false. This is also why three's own normal_fragment_begin applies faceDirection only under DOUBLE_SIDED and handles BackSide with FLIP_SIDED in the vertex shader. Result for every native car (sonata, g80, tucson, porter2, solati) seen from the driver seat: (1) the windows use the outside VLT (side 0.2, windshield 0.4) instead of the eye-adapted pow(VLT, 0.72) values (0.31 / 0.52), so the cabin view is much darker than designed; (2) the outside branch runs on the inward normal, so the inside of the side windows mirrors the sky and the skyline band, with strong Fresnel at grazing angles; the dim cabin reflection and the night instrument glow (cgCab / cgWs) never appear. From outside, the far windows seen through the near ones (also drawn by the inner pass) get a second set of sky and skyline reflections instead of the cabin tint. The geometry, sort order and normals are all correct; only this flag is wrong.",
   "fix": "Choose the side from three's defines, not from gl_FrontFacing:\n```glsl\n#if defined( FLIP_SIDED )\n\tbool cgIn = true;               // BackSide: three flips frontFace, gl_FrontFacing is always true\n#elif defined( DOUBLE_SIDED )\n\tbool cgIn = ! gl_FrontFacing;\n#else\n\tbool cgIn = false;\n#endif\n```\nFLIP_SIDED and DOUBLE_SIDED are both emitted in the r147 fragment prefix and are already part of the program cache key, so nothing else needs to change. Optional, since it only matters once this branch is live: `cgWs = step( 0.4, cgT0 )` compares an interpolated varying against its exact stored value (0.4). Use `step( 0.3, cgT0 )` so the windshield test cannot flicker per pixel when interpolation rounds 0.4 down."
  }
 ]
}
```

## review:glsl

```json
{
 "findings": [
  {
   "title": "The inside-glass branch never runs: gl_FrontFacing is true for BackSide passes in three r147",
   "file": "/home/user/-/studio/car_glass.js",
   "where": "FRAG_MAIN, line 76: `bool cgIn = ! gl_FrontFacing;`",
   "severity": "major",
   "failure": "In the bundled three.min.js (REVISION 147), WebGLState.setMaterial calls frontFace(CW) for side===BackSide (`let i=1===t.side; ... q(i)` → `t.frontFace(2304)`) and keeps CULL_FACE BACK. That makes the triangles you see from inside the cabin the front-facing ones, so gl_FrontFacing is TRUE for every fragment of GWCarGlass.inner(). (three handles the normal with FLIP_SIDED in defaultnormal_vertex; faceDirection is only applied under DOUBLE_SIDED.) As a result cgIn is false in the inner pass. Its compiled program has `#define FLIP_SIDED` and no DOUBLE_SIDED; I checked this by building the real program sources with a stub GL context and compiling all 24 variants with glslang. From the driver seat of every taxi_model car (detail != 'low'), the windows are shaded as exterior glass. The tint is not eye-adapted (0.2 instead of 0.31). The windows show IBL/skyline/road reflections instead of the dim cabin. At oblique angles the side windows become Fresnel sky mirrors: at N·V=0.2 the reflection is about 0.53x sky and transmission is about 5%. The night instrument glow (cgWs branch) never shows. Seen from outside, the far windows' inner faces drawn by the inner pass also get sky reflections. The 'established fact' that r147 draws transparent DoubleSide in one pass is also wrong for this build. renderObject (zt) and compile both do `transparent && side===DoubleSide ? (side=BackSide; draw; side=FrontSide; draw)`, so GWCarGlass.both() (the legacy sedan) is two passes. DOUBLE_SIDED is never defined, and its BackSide sub-pass hits the same bug, so the legacy sedan cabin never gets the inside branch either.",
   "fix": "Derive inside-ness from the side define instead of gl_FrontFacing alone: `#ifdef FLIP_SIDED\n\tbool cgIn = gl_FrontFacing;\n#else\n\tbool cgIn = ! gl_FrontFacing;\n#endif` (or `#if defined(FLIP_SIDED) bool cgIn = true; #elif defined(DOUBLE_SIDED) bool cgIn = !gl_FrontFacing; #else bool cgIn = false; #endif`, which also makes the branch static so the fwidth calls are no longer under a dynamic branch). FLIP_SIDED is already in both the program cache key and the fragment prefix, so no key change is needed. Also fix the both() doc comment ('one DoubleSide pass'): in this three build it is a forced BackSide+FrontSide pair."
  },
  {
   "title": "cgHash collapses to {0, 0.25} on mediump-precision fragment shaders: flat skyline, no lit windows",
   "file": "/home/user/-/studio/car_glass.js",
   "where": "FRAG_PARS line 67: `float cgHash( float n ) { return fract( sin( n ) * 43758.5453123 ); }` (used at lines 107, 111, 115)",
   "severity": "minor",
   "failure": "When the GPU has no highp float in fragment shaders (old Mali-400/SGX-class phones), three r147 falls back to `precision mediump float` (capabilities.getMaxPrecision). In fp16, sin(n)*43758 has 16–32 ULP spacing, so fract() is almost always 0. I emulated this in fp16 for all 58 building indices and got only {0.0, 0.25}. The result: every building has height 0.03 (a thin uniform band), every facade has the same brightness, and step(0.68, hash) is always 0, so there are never lit windows at night. On highp devices it works.",
   "fix": "Use a multiplier small enough to keep fractional bits in fp16, e.g. `return fract( sin( n ) * 43.7585453 );`. In fp16 this gives 42 distinct values over the building indices, and the highp distribution is still fine. Alternatively, use an arithmetic small-integer hash."
  },
  {
   "title": "Legacy sedan glass never gets the 'cgw' attribute: no windshield tint or shade band",
   "file": "/home/user/-/tools/patch_car_glass.py",
   "where": "carskin_model.js hook 'legacy glass material' (MAT.glass = GWCarGlass.both('glass')); no prepare() call for the geometries built at carskin_model.js lines 329/394",
   "severity": "minor",
   "failure": "The program always declares `attribute vec3 cgw`, but carskin_model's glass geometries (gh.build / gm.build) are never passed to GWCarGlass.prepare. The attribute array is disabled and the shader reads the generic attribute value (0,0,0,1), so vCgw.x == 0 → cgT0 = cgVlt = 0.2 everywhere. On the legacy sedan (used for kinds not in GWVehicleSkins indices, or when taxi_model is absent) the windshield is privacy-dark (0.2 instead of 0.4), has no top shade band, and cgWs = 0, so the night instrument glow is never drawn. Correctness also depends on nothing ever setting a non-zero generic value at that attribute location.",
   "fix": "Call GWCarGlass.prepare on the legacy glass geometry in the carskin hook. Note that the legacy model's front is +Z (carskin header says so), and gh.build returns one multi-group geometry. Either give prepare() a front-sign/role option (windshield test `nz > 0.3 && cz > zMid` for +Z-front models) and run it only on the glass group's triangles, or explicitly set a constant cgw attribute (windshield-less) so the fallback is intentional rather than implicit."
  }
 ]
}
```

## review:patcher

```json
{
 "findings": [
  {
   "title": "Re-patching a build that an earlier or later revision of the patcher already patched applies 3 hooks a second time (idempotency claim broken)",
   "file": "/home/user/-/tools/patch_car_glass.py",
   "where": "main(): `if repl in text: ...already patched` / `n = text.count(anchor)`; HOOKS 'inside glass pass' (repl ends with the anchor), 'LOD glass mesh' and 'LOD glass matrices' (repl starts with the anchor)",
   "severity": "major",
   "failure": "For these 3 hooks the replacement contains the anchor word for word, so after patching the anchor is still in the file exactly once. Any change to a hook's text (for example, a fix coming out of this review) makes `repl in text` false on an already-patched build, and `count(anchor)==1` lets the hook go in again. I reproduced this: I edited only the 'inside glass pass' and 'LOD glass mesh' strings in a copy of the patcher and ran it on dist/Gwangalli_Studio_v5_CarGlass.html. It exited 0, printed '+ js/taxi_model.js: inside glass pass' and '+ js/render3d.js: LOD glass mesh', and the output contains `GWCarGlass.inner(` 2 times and `glass: geos.glass` 2 times. At runtime every near-car glass piece gets two BackSide inner meshes, so the cabin view is tinted twice with doubled reflections and costs extra draw calls. ensureLow also builds a second orphan InstancedMesh per car kind and adds it to the scene. For hooks whose replacement does not contain the anchor, the same version change gives the opposite result: a refusal with the misleading 'anchor found 0 times / do not match this studio build'. The docstring promises that running on an already patched file changes nothing, and the '~ js/car_glass.js (updated)' path shows that re-running on patched builds is an intended workflow.",
   "fix": "Before applying any hook, keep a copy of each target file's original text. If that copy contains MARK and not every hook's `repl` for that file is in it, stop with 'already patched by a different patch_car_glass version - run it on the unpatched studio build'. Alternatively, record a hook hash in manifest['carGlass'] and refuse when it differs from the current HOOKS. Separately, check the anchor count before the `repl in text` short-circuit, or require that the anchor's occurrence is not already preceded or followed by MARK."
  },
  {
   "title": "Module order is not enforced: a missing 'modules' list, or car_glass.js already listed after carskin_model.js, still gets written as success while the glass hooks stay inactive",
   "file": "/home/user/-/tools/patch_car_glass.py",
   "where": "main(): `mods = manifest.get(\"modules\") or []` / `if MODULE not in mods: at = ... else len(mods)`",
   "severity": "minor",
   "failure": "carskin_model.js evaluates `MAT.glass = root.GWCarGlass ? ... : legacy` once, at load time, so car_glass.js has to run before it. (1) If js/car_glass.js is already in modules but after carskin_model.js, the `MODULE not in mods` guard skips it and leaves it there. I tested this by putting it before js/render3d.js: the patcher exited 0 with order [..., carskin_model, taxi_model, car_glass, render3d]. The legacy sedan then keeps the old 0.4-opacity glass. It is not GWCarGlass, so it is not in the LOD glass bucket either, yet all hooks report '+'. (2) If the manifest has no 'modules' key, as in a build whose loader lists modules another way, the patcher writes `\"modules\":[\"js/car_glass.js\"]` and exits 0 (tested). The module is never wired before carskin, every `root.GWCarGlass` guard is false, and the 'patched' build looks exactly like the original. A loader that does `MANIFEST.modules || DEFAULT_LIST` would instead load only car_glass.js.",
   "fix": "Refuse when 'modules' is not a list or does not contain 'js/carskin_model.js'. Always remove MODULE from mods and re-insert it at `min(index(carskin_model), index(taxi_model))`, so it sits before carskin_model.js even when it was already present."
  },
  {
   "title": "The module's hidden dependencies on the target build's rblx_gfx shader (GLASS_LINE and rbx* GLSL names) are not checked, so a newer or older build can be patched into broken or degraded glass",
   "file": "/home/user/-/tools/patch_car_glass.py",
   "where": "HOOKS / main(): only taxi_model.js, carskin_model.js and render3d.js are verified; car_glass.js also depends on js/rblx_gfx/20_materials.js",
   "severity": "minor",
   "failure": "car_glass.js swaps its shader in by exact text match on RblxGfx's line `outgoingLight = ( totalDiffuse + totalEmissiveRadiance ) * diffuseColor.a + totalSpecular * 1.6;`. Under CG_RBX, which is defined whenever G.adopt succeeds, it also uses the GLSL symbols rbxSkyZen, rbxEnvSpec, rbxSV, rbxSkyGrad, rbxHemiGround, rbxAmbIn, rbxAmbOut and rbxSunCol. All of these exist in v5 and in the older v2.0 build, whose 20_materials.js is identical. In a build whose 20_materials.js changes that line (even the 1.6 factor), the patcher still writes. FRAG_MAIN is then placed after Roblox fog and glass renders without fog (only a console.warn). If any rbx* name is renamed or removed, the glass program fails to compile under three r147 and no car windows draw at all. This is exactly the half-working build the docstring says the script prevents.",
   "fix": "Add a read-only check entry: decode files['js/rblx_gfx/20_materials.js'] and refuse unless it contains the GLASS_LINE string and each of the rbx* identifiers above. Read the line from car_glass.js itself, or share one constant, so the two cannot drift apart."
  },
  {
   "title": "Output is written in place without a temp file; an in-place run that is interrupted destroys the input build",
   "file": "/home/user/-/tools/patch_car_glass.py",
   "where": "main(): `open(dst, \"w\", encoding=\"utf-8\").write(html)`",
   "severity": "minor",
   "failure": "Because the docstring promises idempotency, `python3 tools/patch_car_glass.py studio.html studio.html` is a natural way to run it. open('w') truncates the only copy of the roughly 28.6 MB HTML before writing. A Ctrl-C, a full disk, or an antivirus lock on Windows partway through leaves a truncated file: the base64 pack is cut off, and the loader's atob/gunzip fails at boot. There is no backup.",
   "fix": "Write to `dst + '.tmp'` (in the same directory), close it, then `os.replace(tmp, dst)`."
  }
 ]
}
```

## review:look

```json
{
 "findings": [
  {
   "title": "Inner (BackSide) pass never takes the inside branch: gl_FrontFacing is true for BackSide in three r147",
   "file": "/home/user/-/studio/car_glass.js",
   "where": "FRAG_MAIN line 76: `bool cgIn = ! gl_FrontFacing;` (used by GWCarGlass.inner(), which taxi_model.js adds for every hi-detail glass mesh)",
   "severity": "major",
   "failure": "In three r147, WebGLState.setMaterial calls gl.frontFace(CW) for side === BackSide and keeps cullFace(BACK). The triangles a BackSide material draws are therefore front-facing to GL, so gl_FrontFacing is true and cgIn is false. I confirmed this in headless Chromium (ANGLE/SwiftShader, WebGL2, RblxGfx adopted). A BackSide ShaderMaterial seen from inside a box outputs the gl_FrontFacing=true colour. A GWCarGlass.inner('glass') box seen from inside gives the same pixel (4,5,6) whether cgCabin is 0 or 50, so the cabin branch never runs. After the fix below the same test gives (1,1,1) vs (255,255,255). Visible result in the driver-seat view: every window shows the outside sky, skyline and road mirror (Fresnel x1.5, bright on the oblique side windows) instead of the dim cabin. The tint stays at 0.2/0.4 instead of the eye-adapted 0.31/0.52. The dashboard haze and the night instrument glow never appear. Seen from outside, the far windows' inner faces add a second, ghost sky/skyline reflection.",
   "fix": "Choose the branch at compile time from three's side defines instead of gl_FrontFacing:\n#if defined( FLIP_SIDED )\n\tbool cgIn = true;\n#elif defined( DOUBLE_SIDED )\n\tbool cgIn = ! gl_FrontFacing;\n#else\n\tbool cgIn = false;\n#endif\n(verified to switch the inner pass to the cabin branch). This also lets the compiler drop the unused skyline branch in each variant."
  },
  {
   "title": "On the direct (no-post) path, which phones use, the premultiplied blend runs on sRGB values: glass is much darker than the tuned VLT",
   "file": "/home/user/-/studio/car_glass.js",
   "where": "FRAG_MAIN lines 84-85, 141: `cgA = 1 - cgTr` output with blend One / OneMinusSrcAlpha",
   "severity": "major",
   "failure": "Touch devices default to the low tier (90_api.js: `touch ? 'low' : 'high'`, low = post:false). Phones without a half-float render target also lose post. On that path renderDirect draws to the canvas with outputEncoding sRGB, so three encodes in the shader and the framebuffer blend multiplies the sRGB-encoded background by (1-a). The effective linear transmittance is then about VLT^2.2: side glass from outside 0.2 becomes ~0.03, so the cabin is invisible. From the driver seat, side windows go from 0.31 to ~0.08 and the windshield from 0.52 to ~0.24. In display terms the view out of the windows is 0.31x / 0.52x instead of the 0.59x / 0.74x seen on mid/high (linear HDR target, correct blend). The same scene is roughly twice as dark through the glass on phones as on the PC tier where it was tuned.",
   "fix": "Add a uniform `cgAlphaPow` (1.0 when RblxGfx renders through the linear post target, 1.0/2.2 when it renders directly to the canvas) and use `float cgA = clamp( 1.0 - pow( cgTr, cgAlphaPow ), 0.0, 1.0 );`. Set it from render3d/RblxGfx whenever usePost changes, e.g. GWCarGlass.setDirect(!G._.usePost) setting shared.cgAlphaPow.value. The reflection term can stay as is."
  },
  {
   "title": "Reflection exceeds 100% near grazing angles because cgReflGain also scales the F->1 limit",
   "file": "/home/user/-/studio/car_glass.js",
   "where": "FRAG_MAIN line 75 `cgF = 0.04 + 0.96*pow(1-NV,5)` and line 126 `cgRefl = cgF * cgEnv * cgReflGain` (gain 1.5)",
   "severity": "minor",
   "failure": "For NV < 0.08 (about 85 deg), 1.5*F > 1. At NV = 0.05 the reflection is 1.17x the reflected sky, and at the clamped NV = 1e-3 it is 1.44x, while transmission goes to 0. The silhouette and curved rims of every window (windshield top edge, A-pillar wrap, where interpolated normals push NV to 0) reflect a horizon sky of ~0.7-0.9 as 1.0-1.3. That is above the default bloom threshold 0.95, so the glass outlines glow brighter than the sky they mirror.",
   "fix": "Apply the coating gain to F0 only: `float cgF0 = 0.04 * cgReflGain; float cgF = cgF0 + ( 1.0 - cgF0 ) * pow( 1.0 - cgNV, 5.0 );`. Use it for transmission ((1-cgF)^2) and drop `* cgReflGain` from both cgRefl lines, so the reflection tends to exactly 1x the environment at grazing."
  },
  {
   "title": "Per-channel glint cap turns coloured sun / street-lamp glints and their bloom halos white",
   "file": "/home/user/-/studio/car_glass.js",
   "where": "FRAG_MAIN line 139: `vec3 cgGlint = min( reflectedLight.directSpecular, vec3( cgGlintMax ) );`",
   "severity": "minor",
   "failure": "With the ~0.05 roughness floor, the GGX peak for the sun or a nearby point light is in the thousands per channel. An orange sunset sun or sodium lamp (e.g. 2000/1100/400) is clamped to (24,24,24). Every capped glint therefore has a pure white core, and the bloom chain spreads a white halo around reflections of orange lights on car windows.",
   "fix": "Cap the magnitude and keep the hue: `vec3 cgG = reflectedLight.directSpecular; vec3 cgGlint = cgG * min( 1.0, cgGlintMax / max( max( cgG.r, cgG.g ), max( cgG.b, 1e-4 ) ) );`"
  },
  {
   "title": "Night lit-window grid in the skyline aliases horizontally: the fade only uses the vertical frequency",
   "file": "/home/user/-/studio/car_glass.js",
   "where": "FRAG_MAIN lines 110-116: cgLit / cgRows faded by `fwidth( cgWin.y )` only, with cgWin.x = fract(cgPhi)*7",
   "severity": "minor",
   "failure": "Window columns repeat 63 times per radian of azimuth, and nothing filters that frequency. Where the reflected azimuth changes quickly across the screen but elevation does not (windshield and rear-glass wrap corners, curved side glass, a car at 60-85 studs), the columns become 1-2 px or smaller. fwidth(cgWin.y) stays small, so step(0.3, fract(cgWin.x)) and the per-column hash alias. At night the lit windows sparkle and crawl on moving cars.",
   "fix": "Build the fade from both axes, using an azimuth derivative that has no atan wrap: `float cgDPhi = 9.0 * length( fwidth( cgRw.xz ) ) / max( length( cgRw.xz ), 1e-3 ); float cgGridAa = max( fwidth( cgWin.y ), cgDPhi * 7.0 );`. Then use `1.0 - smoothstep( 0.25, 0.6, cgGridAa )` in both the cgLit and cgRows lines."
  },
  {
   "title": "both() (legacy sedan): inside/outside chosen per triangle by gl_FrontFacing on a mesh whose winding flips at the centre line, plus order-dependent single-pass blending",
   "file": "/home/user/-/studio/car_glass.js",
   "where": "both() line 262 + FRAG_MAIN `cgIn = !gl_FrontFacing`; used by carskin_model.js line 41 `MAT.glass = GWCarGlass.both('glass')` (ghMesh glass group and door glass)",
   "severity": "minor",
   "failure": "I built the legacy CarSkinModel (detail high) in node. All 580 left-side glass triangles are wound outward, and all 580 right-side ones (x>0, made by the q.reverse() mirroring) are wound inward. From outside, the right half (right side windows and the right half of the windshield and rear window) is back-facing, so it gets the cabin shading: no sky or skyline mirror and the lighter eye-adapted tint. The windshield is visibly split down the middle, and from the driver seat the right half shows the outside sky mirror. Also, three r147 draws a transparent DoubleSide mesh in one pass in index order. The rear-window quads come first (gzs ascending), so from behind the windshield's inner face is composited over the rear window and scales its sky reflection by ~0.31.",
   "fix": "In carskin_model.js, before using the legacy glass, orient its triangles outward: swap two indices of any glass triangle whose normal dot (centroid - cabin centre) < 0, then computeVertexNormals. Render it like taxi_model: a mesh with GWCarGlass.inner('glass') added before a mesh with GWCarGlass.material('glass'), and stop using both() for it."
  },
  {
   "title": "Low tier: far-LOD glass is flat black while near glass mirrors the sky, causing a pop at the 60-stud LOD switch",
   "file": "/home/user/-/studio/car_glass.js",
   "where": "lowMaterial() lines 249-256 (opaque MeshStandardMaterial adopted by RblxGfx, used for the InstancedMesh far LOD in render3d.js ensureLow)",
   "severity": "minor",
   "failure": "On the low tier scene.environment is null, so lowMaterial has no USE_ENVMAP and gets no indirect specular at all. Only the tiny direct sun lobe remains and the far glass renders black. Inside 60 studs the same windows switch to the near material, which reflects rbxSkyGrad with Fresnel x1.5 (a strong sky sheen on rear and side glass seen obliquely). Every car crossing the NEAR boundary visibly flips its windows between matte black and a bright reflection.",
   "fix": "Give lowMaterial the same analytic reflection when there is no env map. In an onBeforeCompile chained after adopt, insert before `#include <output_fragment>`: `#ifndef USE_ENVMAP` vec3 V = normalize(vViewPosition); float f = 0.06 + 0.94*pow(1.0 - clamp(dot(normal, V), 0.0, 1.0), 5.0); outgoingLight += f * rbxSkyGrad( inverseTransformDirection( reflect( -V, normal ), viewMatrix ) ) * rbxEnvSpec; `#endif`. Alternatively, have near glass on the low tier fade its reflection to match beyond a distance."
  },
  {
   "title": "Inner pass pays full PBR lighting, shadow and height-map cost over most of the screen in the driver view for terms that are not visible",
   "file": "/home/user/-/studio/car_glass.js",
   "where": "FRAG_MAIN line 140 `outgoingLight = totalDiffuse * cgA * 0.5 + cgRefl + cgGlint;` for the inner material; render3d skinShadows sets receiveShadow=true on the inner meshes too",
   "severity": "minor",
   "failure": "From the driver seat the inner glass covers roughly 40-60% of the screen. Because the inside output still reads totalDiffuse and directSpecular, each glass fragment evaluates the whole MeshStandard light loop: sun plus 3+2 (low) or 6+3 (mid) pooled lights. It also runs shadow-map PCF (mid/high), the 5-tap height-map shadow and the sky-visibility tap (rbxHeightShadow/rbxSkyVis), and the IBL irradiance fetch. All of that is for a film term with ~0.002 albedo and an inner-surface glint, while the visible output is just F * cabin colour over the transmitted background. On low-end phones this is an extra near-full-screen PBR layer every frame in cockpit view.",
   "fix": "After the compile-time cgIn fix, emit only the cabin reflection for the inner variant: `#ifdef FLIP_SIDED outgoingLight = cgRefl; #else outgoingLight = totalDiffuse * cgA * 0.5 + cgRefl + cgGlint; #endif`. The compiler can then dead-strip the light loop, shadow and height-map taps and the IBL fetches. Also set receiveShadow=false and castShadow=false on the inner meshes (gi) in taxi_model.js."
  }
 ]
}
```

## verify:all

```json
{
 "verdicts": [
  {
   "index": 0,
   "real": true,
   "reason": "Checked against the bundled three.min.js (REVISION \"147\"). setMaterial does `2===t.side?V(2884):G(2884);let i=1===t.side;e&&(i=!i),q(i)`, and q(true) calls frontFace(2304=CW) while cullFace stays BACK. So every fragment a single-sided material draws, BackSide included, has gl_FrontFacing==true, and `cgIn = !gl_FrontFacing` is always false in GWCarGlass.inner(). three's own normal_fragment_begin applies faceDirection only under DOUBLE_SIDED, and the BackSide flip is FLIP_SIDED in defaultnormal_vertex. The claim that DoubleSide is drawn as two passes is also right for this build. Both zt (renderObject) and compile do `!0===r.transparent&&2===r.side?(r.side=1,...render...,r.side=0,...render...,r.side=2)`. Parameters are `doubleSided:2===s.side, flipSided:1===s.side`, so both() never gets DOUBLE_SIDED and its BackSide sub-pass has FLIP_SIDED. The 'established fact' (one pass, no forceSinglePass) is wrong for r147. flipSided is cache-key bit 12 and is emitted in both prefixes.",
   "fix": "In FRAG_MAIN replace `bool cgIn = ! gl_FrontFacing;` with:\n#if defined( FLIP_SIDED )\n\tbool cgIn = true;\n#elif defined( DOUBLE_SIDED )\n\tbool cgIn = ! gl_FrontFacing;\n#else\n\tbool cgIn = false;\n#endif\nNo cache-key change is needed, because flipSided/doubleSided are already in three's program key. This also makes the branch static, so the fwidth() calls are no longer under a non-uniform branch. Fix the header comment for both(): in r147 a transparent DoubleSide material is drawn as a BackSide pass and then a FrontSide pass, not 'one DoubleSide pass'."
  },
  {
   "index": 1,
   "real": true,
   "reason": "three r147 getMaxPrecision returns 'mediump' when getShaderPrecisionFormat(FRAGMENT, HIGH_FLOAT).precision is 0, and the whole program then compiles as `precision mediump float`. With fp16 intermediates, sin(n)*43758 is >=1024 in magnitude unless |sin n|<0.023, so fract() returns 0 almost every time. Building heights, facade brightness and the lit-window step(0.68, hash) all collapse. This only affects GPUs without highp fragment floats (Mali-400/450, SGX-class). They are rare, but the project targets phones and the fix costs nothing and changes nothing on highp.",
   "fix": "`float cgHash( float n ) { return fract( sin( n ) * 43.7585453 ); }`. A small multiplier keeps fractional bits in fp16, and the highp distribution is still fine for these building and window indices."
  },
  {
   "index": 2,
   "real": true,
   "reason": "carskin_model's legacy glass (ghMesh glass group, line 329, and door glass, line 394) is never given a 'cgw' attribute. The disabled attribute reads the generic (0,0,0,1), so `vCgw.x > 0 ? vCgw.x : cgVlt` falls back to 0.2 everywhere: no windshield tint (0.4), no shade band, and cgWs=0, so there is no instrument glow. The legacy model really is used: GWVehicleSkins.key() returns 'legacy' for kinds outside `indices`, for example VehicleKind 'police', which the place uses. Before the patch these windows had 0.4-opacity glass, so police windshields get much darker. Impact is minor. Note that prepare() as written cannot simply be called: gh.build shares vertices between the paint, trim and glass groups, so its islands would merge glass with body, and the model faces +Z, not -Z.",
   "fix": "Add a carskin hook after `const ghMesh = gh.build({ paint, glass: hi ? MAT.glass : MAT.trimGloss, trim: MAT.trimGloss }, ['paint', 'trim', 'glass']);` that writes cgw directly when `hi && root.GWCarGlass`. Over the vertices used by the glass group, take the windshield y-range of vertices with z >= -1e-4 (front is +Z). For every vertex of ghMesh.geometry set cgw = z >= -1e-4 ? [TINT.windshield, y1-0.24*h, y1-0.05*h] : [TINT.glass, 0, 0]. Paint and trim ignore the attribute, so the shared vertices are harmless. Also set an explicit constant cgw [TINT.glass,0,0] on each door-glass geometry from gm.build, so no draw depends on generic attribute state."
  },
  {
   "index": 3,
   "real": true,
   "reason": "Same root cause as #0, which I verified in three.min.js r147. BackSide sets frontFace(CW) with BACK culling, so gl_FrontFacing is always true and cgIn is always false in the inner pass. The consequences listed (outside VLT instead of pow(VLT,0.72), sky, skyline and Fresnel mirror from the driver seat, no cgCab/cgWs glow, ghost sky reflections on far windows seen from outside) follow directly. The optional cgWs point is also valid. vCgw.x is a perspective-interpolated constant 0.4, which can come out 1 ulp below the 0.4 literal, so step(0.4, ...) can drop out per pixel once the inside branch is live.",
   "fix": "Same compile-time selection as #0: `#if defined( FLIP_SIDED ) bool cgIn = true; #elif defined( DOUBLE_SIDED ) bool cgIn = ! gl_FrontFacing; #else bool cgIn = false; #endif`. Also change `float cgWs = step( 0.4, cgT0 );` to `step( 0.3, cgT0 )`."
  },
  {
   "index": 4,
   "real": true,
   "reason": "Confirmed by reading the hook loop. 'inside glass pass' (repl ends with the anchor), 'LOD glass mesh' and 'LOD glass matrices' (repl starts with the anchor) leave the anchor in the file exactly once. When the hook text changes, `repl in text` is false and `text.count(anchor)==1`, so the new hook is inserted next to the old one. That gives two BackSide inner meshes per near glass piece and two InstancedMesh glass buckets, which are added to the scene by ensureLow. Hooks whose repl does not contain the anchor instead fail with the misleading 'anchor found 0 times'. This is a realistic workflow here: dist/Gwangalli_Studio_v5_CarGlass.html is already patched, its manifest records carGlass.hooks, and tools/build_studio_cabin.py re-runs pcg.patch on studio builds. Any hook fix coming out of this review (e.g. #15/#13) would double-apply.",
   "fix": "In patch(), read `prev = set(((manifest.get('carGlass') or {}).get('hooks')) or [])` before the hook loop. In the loop, after the `if repl in text: ... continue` short-circuit, add `if name in prev: missing.append('%s: %s (applied by a different patch_car_glass version - run on the unpatched studio build)' % (fn, name)); continue`. This still lets new hooks (for example the cabin extra_hooks) layer onto a glass-patched build. Optionally record a hash of each repl in manifest['carGlass'] and compare it instead of the name."
  },
  {
   "index": 5,
   "real": false,
   "reason": "Speculative. Both builds in dist have a 'modules' list. The v5 build has js/car_glass.js correctly before js/carskin_model.js, which is the order the patcher itself inserts. No tool in the repo (patch_car_glass.py, build_studio_cabin.py, which passes no extra_modules) can produce car_glass.js after carskin_model.js or a manifest with no modules key. The failure needs a hand-edited or foreign manifest. Refusing when 'modules' is missing or when car_glass.js comes after carskin_model.js is cheap hardening, but it is not a defect that occurs in this codebase."
  },
  {
   "index": 6,
   "real": false,
   "reason": "Speculative. The only 20_materials.js variants in play (v5 and v2.0) are identical and contain GLASS_LINE and every rbx* symbol. v2.0 has no carskin_model.js in the pack, so the patcher already refuses it. car_glass.js already handles a missing GLASS_LINE by falling back to inserting before output_fragment, with a console.warn. Renamed rbx* symbols would be a future-build hypothetical. A read-only check on js/rblx_gfx/20_materials.js would be reasonable hardening, but no current build hits the failure."
  },
  {
   "index": 7,
   "real": false,
   "reason": "Speculative hardening. main() reads the whole input into memory before `open(dst,'w')`, so a normal run with src==dst is safe. The failure needs an interruption or a full disk during a sub-second write. The docstring usage is <input> <output>, and nothing in the repo runs it in place. Writing to dst+'.tmp' and then os.replace() is a good cheap improvement, but this is not an actual defect."
  },
  {
   "index": 8,
   "real": true,
   "reason": "Duplicate of #0 and #3. The minified r147 setMaterial (`let i=1===t.side;e&&(i=!i),q(i)` → frontFace(2304)) confirms that BackSide-drawn fragments are GL-front-facing, so `!gl_FrontFacing` never selects the cabin branch in GWCarGlass.inner(). The reported headless-Chromium result matches this.",
   "fix": "#if defined( FLIP_SIDED )\n\tbool cgIn = true;\n#elif defined( DOUBLE_SIDED )\n\tbool cgIn = ! gl_FrontFacing;\n#else\n\tbool cgIn = false;\n#endif"
  },
  {
   "index": 9,
   "real": true,
   "reason": "Verified in rblx_gfx: TIERS.low has post:false, touch devices default to 'low' (90_api.js:198), and `_.usePost` also needs caps.halfFloatRT. renderDirect renders to target null with renderer.outputEncoding=sRGB, so encodings_fragment encodes before the fixed-function blend. With blend One/OneMinusSrcAlpha, the background is multiplied in display space by (1-a)=Tr. On the post path the blend happens in the linear HDR target and is tone-mapped/encoded afterwards. For VLT 0.2 the direct path shows the background at about 0.2x display brightness, against roughly 0.46x on mid/high, so phones see the glass about 2x darker than the tier it was tuned on.",
   "fix": "Add `uniform float cgAlphaPow;` to FRAG_PARS and `cgAlphaPow: { value: 1 }` to `shared`. Change `float cgA = clamp( 1.0 - pow( cgTr, cgAlphaPow ), 0.0, 1.0 );`. In make(), set it per render: `m.onBeforeRender = function (renderer) { shared.cgAlphaPow.value = renderer.getRenderTarget() === null ? 1.0 / 2.2 : 1.0; };`. r147 calls material.onBeforeRender before renderBufferDirect, and the shared uniform is uploaded when the material binds, like cgNightU. The reflection term stays as it is."
  },
  {
   "index": 10,
   "real": true,
   "reason": "cgRefl = cgF*env*1.5 with cgF→1 at grazing incidence gives reflection >1x the environment whenever 1.5F>1, which is NV<~0.08 (≈85°). At NV=0.05 that is 1.17x, and up to ~1.49x at the 1e-3 clamp, while transmission (1-F)^2 → 0. Rims and edge-on side windows (e.g. the car ahead) therefore mirror a horizon sky above its real brightness and cross the default Bloom Threshold of 0.95 (40_lighting.js). The CFG comment says the intent is ~6% head-on, so the over-unity grazing behaviour is unintended. Minor.",
   "fix": "Keep the physical F for transmission and scale only F0 for the reflection: `float cgP = pow( 1.0 - cgNV, 5.0 ); float cgF = 0.04 + 0.96 * cgP; float cgF0r = 0.04 * cgReflGain; float cgFr = cgF0r + ( 1.0 - cgF0r ) * cgP;`. Use cgF in cgTr as now, and change both reflection lines to `cgRefl = cgFr * cgEnv;` / `cgRefl = cgFr * cgCab;` without the `* cgReflGain`."
  },
  {
   "index": 11,
   "real": true,
   "reason": "three r147 clamps roughness to at least 0.0525 (roughness 0.035 here), which gives a GGX peak D≈4e4. directSpecular for the sun or a nearby lamp is then hundreds per channel. min(spec, vec3(24)) clamps every channel to 24, so any warm glint becomes (24,24,24). The tone-mapped core would saturate to white anyway, but the bloom chain works on the HDR value, so the halo turns white instead of keeping the light's hue. Minor but real.",
   "fix": "`vec3 cgG = reflectedLight.directSpecular; vec3 cgGlint = cgG * min( 1.0, cgGlintMax / max( max( cgG.r, cgG.g ), max( cgG.b, 1e-4 ) ) );`"
  },
  {
   "index": 12,
   "real": true,
   "reason": "The window grid uses cgWin.x = fract(cgPhi)*7 with cgPhi = atan(z,x)*9, which is 63 columns per radian of reflected azimuth. The fade uses only fwidth(cgWin.y). Where the normal turns about a near-vertical axis (windshield and A-pillar wrap, curved side and rear glass), reflected azimuth sweeps fast across pixels while elevation barely changes. Many columns then fall inside one pixel, the fade stays at 1, and step(0.3, fract(x)) plus the per-column hash alias, so lit windows sparkle at night. Minor.",
   "fix": "`float cgDPhi = 9.0 * length( fwidth( cgRw.xz ) ) / max( length( cgRw.xz ), 1e-3 ); float cgGridAa = max( fwidth( cgWin.y ), cgDPhi * 7.0 );` then use `1.0 - smoothstep( 0.25, 0.6, cgGridAa )` in both the cgLit line and the cgRows line. This avoids the atan wrap, and after the #0 fix the branch is static, so the derivatives are well-defined."
  },
  {
   "index": 13,
   "real": true,
   "reason": "The winding defect is real. I built CarSkinModel high detail in node with three r147: all 580 glass triangles on x>0 (isLeft, not reversed) face inward, and all 580 on x<0 (made by `if (!isLeft) q.reverse()`) face outward. ghRingAt is a continuous 23-point ring, so the un-reversed quads are inward on both halves; the finding swaps the side labels. The sub-claim 'one pass in index order' is wrong for r147, which splits a transparent DoubleSide material into a BackSide pass then a FrontSide pass. The order bug is still real through that split. From behind, the near rear window's inward half is drawn in the BackSide pass, before the far windshield's inward half (front-facing from that view), so far glass is composited over near glass on one half and that half's reflection is attenuated. Once the #0 fix makes FLIP_SIDED select the cabin branch, the inward half would also get cabin shading from outside, which is the split windshield.",
   "fix": "In carskin_model.js (a new anchored hook) change `if (!isLeft) q.reverse();` (unique) to `q.reverse();`. Verified in node: all 1160 cabin and door glass triangles then face outward. The paint and trim in the same GridMesh are DoubleSide and unaffected, and computeVertexNormals no longer cancels at the centre seam. With consistent outward winding, keep GWCarGlass.both('glass'): r147's automatic BackSide→FrontSide split of transparent DoubleSide is then exactly the inner (cabin, FLIP_SIDED) pass followed by the outer pass in the right order, so no separate inner mesh is needed."
  },
  {
   "index": 14,
   "real": true,
   "reason": "On the low tier envSize=0, and 30_sky.js sets scene.environment=null, so lowMaterial (adopted MeshStandardMaterial, color 0x07090c) has no USE_ENVMAP and no indirect specular. With albedo ≈0.002 it renders black apart from a tiny sun lobe. Near glass on the same tier takes the `#elif defined( CG_RBX )` branch and reflects rbxSkyGrad with Fresnel x1.5. At NEAR=60 (low tier), oblique windows therefore pop between a sky sheen and matte black. Mid/high are fine because both materials get the PMREM env. Minor.",
   "fix": "In lowMaterial(), after G.adopt(low), chain the shader and change the key. Do: `const base = low.onBeforeCompile, bk = low.customProgramCacheKey; low.onBeforeCompile = function (s, r) { base.call(this, s, r); s.fragmentShader = s.fragmentShader.replace('#ifdef RBX_GLASS\\n\\toutgoingLight = rbxAtmos(', '#ifndef USE_ENVMAP\\n\\t{ vec3 cgV = normalize( vViewPosition ); float cgF = 0.06 + 0.94 * pow( 1.0 - clamp( dot( normal, cgV ), 0.0, 1.0 ), 5.0 ); outgoingLight += cgF * rbxSkyGrad( inverseTransformDirection( reflect( - cgV, normal ), viewMatrix ) ) * rbxEnvSpec * mix( 0.15, 1.0, rbxSV ); }\\n#endif\\n#ifdef RBX_GLASS\\n\\toutgoingLight = rbxAtmos('); }; low.customProgramCacheKey = function () { return 'gwcarglass-low|' + (bk ? bk.call(low) : ''); };`. Only do this when adopted. Inserting before RblxGfx's fog block (rather than before output_fragment) keeps the reflection fogged. The distinct cache key is needed because every adopted MeshStandardMaterial otherwise shares 'rbxgfx1|physical|adopt|'."
  },
  {
   "index": 15,
   "real": false,
   "reason": "This is an unmeasured optimisation, not a defect. From inside, the outer FrontSide pass is culled, so the inner pass is the only glass layer. Any lit transparent glass, including three's own, costs one PBR layer there. The terms are not strictly invisible either: directSpecular can carry a real sun glint off the inner surface, and the output is otherwise correct. No frame-time problem is shown. Once #0 makes FLIP_SIDED static, emitting only cgRefl for the inner variant and setting receiveShadow=false on the inner meshes is a reasonable optional optimisation, but it is not a correctness issue."
  }
 ]
}
```
