# src/char/kit — armour kit, material library, weapons

Procedural, parametric building blocks for flagship-quality armoured characters, used inside a design's
`build(kit, S, rig)` (see `src/char/README.md` section 6 for the design format). Everything is code: no external assets.

```
src/char/kit/geo.js        geometry core: plate(), sweep(), lathe(), extrude(), strip(), studs(), put() / putPair() ...
src/char/kit/armor.js      armour builders: helms, gorget, cuirass, pauldrons, arms, gauntlets, faulds, tassets, legs ...
src/char/kit/cloth.js      clothSpec() (verlet cloth specs) + clothEdges() (torn / burnt hems)
src/char/kit/looks.js      LOOKS: generic surface presets
src/char/kit/textures.js   procedural PBR texture sets (DataArrayTexture), SET ids, tiling / bump tables
src/char/kit/static.js     createStaticKit(): the same API into plain Meshes (weapon / prop / catalogue displays)
src/char/kit/index.js      re-exports all of the above
src/char/materials.js      createKitMaterial() (the shared character shader), surfDetail(), glow control
src/char/weapons.js        KAEL greatsword, ISKA twin crescents, VORN war spear: builders, sockets, grip points
src/fighters/kael/design.js   KAEL, the Cinder Warden (reference design using everything here)
src/labs/art.js            look-dev lab (lighting rig, turntable, bust, weapons, combat pose, silhouette, QA)
```

Conventions: metres, degrees in options, radians inside the code. Pieces are authored in a bone's **zero-pose frame**
(+X forward, +Y up, +Z the fighter's right / camera side). Right-side limb pieces are authored for the `...R` bone and
mirrored with `putPair()`. "curve" options take a number, `[[t, value], ...]` control points (Catmull-Rom) or `fn(t)`.

---

## 1. Quick start

```js
import * as A from '../../char/kit/armor.js';
import { put, putPair, strip } from '../../char/kit/geo.js';
import { clothSpec, clothEdges } from '../../char/kit/cloth.js';
import { greatsword, WEAPON_SPECS, WEAPON_MATERIALS } from '../../char/weapons.js';
import { attachGlow } from '../../char/materials.js';

const STEEL = { color: [0.05, 0.046, 0.045], rough: 0.56, metal: 0.8, set: 'scorched', amt: 1 };
const EMBER = { color: [0.02, 0.008, 0.004], rough: 0.5, metal: 0, set: 'hammered', amt: 0, inlay: 1 };

export const hero = {
  id: 'hero', idle: 'demo.idle',
  materials: {
    plate: { bump: 1, glow: { inlay: [6, 2, 0.35], vein: [2.6, 0.6, 0.07], eye: [9.5, 3.6, 0.8] }, rim: [0.32, 0.42, 0.66, 3] },
    cloth: { cutout: true, glow: { inlay: [0, 0, 0], vein: [2.6, 0.6, 0.07], eye: [0, 0, 0] } },
    blade: WEAPON_MATERIALS.greatsword,
    suit: {},
  },
  cloth: [clothSpec({ name: 'cape', top: [['chest', [-0.15, 0.2, -0.15]], ['chest', [-0.17, 0.2, 0.15]]], length: 1, outer: { color: [0.04, 0.013, 0.01] } })],
  weapon: WEAPON_SPECS.greatsword,
  glow: { inlay: [6, 2, 0.35], vein: [2.6, 0.6, 0.07], eye: [9.5, 3.6, 0.8] },
  build(kit, S, rig) {
    clothEdges(kit, rig, { cape: { burn: 0.8, sides: 'both' } });          // torn + burnt hem
    const H = A.greatHelm({ slitH: 0.019 });
    for (const k of ['crown', 'brow', 'face', 'back', 'crest']) put(kit, 'plate', 'head', H[k], STEEL);
    put(kit, 'plate', 'head', H.eye, { ...EMBER, inlay: 0, eye: 1 });       // glowing visor
    const P = A.pauldron({ R: 0.13, flare: 0.05, lames: 4 });
    for (const g of [P.cop, P.over, ...P.lames]) put(kit, 'plate', 'deltoidR', g, STEEL);
    putPair(kit, 'plate', 'shin', A.greave({ r: 0.075 }), STEEL);
    greatsword(kit);                                                         // on weaponR, slot 'blade'
  },
};
// at runtime
const c = createCharacter(ctx, hero);
const glow = attachGlow(c);            // c.glow; flares / colours without recompiling
glow.flare('vein', 3, 0.6);
```

---

## 2. Geometry core (`geo.js`)

Every builder returns an **indexed** `BufferGeometry` with `position`, `normal` and two kit attributes:

| attribute | meaning | goes to |
|---|---|---|
| `cav` (float) | 1 neutral, `< 1` occluded crevice / inner surface (darker, grimier), `1..2` convex edge (edge wear) | material `surf.w` |
| `uvw` (vec3, optional) | cloth / fur surfaces: `(u, v, edge code)` | material `glow` |

`cav` is derived from the mesh (discrete mean curvature: rolled rims, bevels and ridges wear; folds collect grime) and
from builder knowledge (inner skins 0.42, lames darken where they tuck under the plate above).

| function | notes |
|---|---|
| `plate(S, o)` | **Thick plate over a parametric outer surface** `S(u, v) -> [x,y,z]` (u across, v along). Outer skin + optional inner skin + a profiled edge ring swept around the boundary (half-round bead, smooth normals, rounded corners) + optional rolled rim tubes. Options: `nu=16, nv=8, thick=0.006, closeU` (hoop), `edge` (`'round'` or per side `{u0,u1,v0,v1}: 'round'\|'none'`), `edgeR` (bead radius; > thick/2 = swollen forged edge), `edgeSegs=3`, `roll: {u0\|u1\|v0\|v1: radius}`, `rollSegs=5`, `creaseU / creaseV` (hard normal lines = ridges, duplicated vertices), `ridgeWear=0.7`, `axis=[x,z]` or `out(p)` (orientation), `flip`, `inner=false`, `innerCav=0.42`, `occ(u,v)` (occlusion), `curv=0.004`, `edgeWear=0.85`. The result carries `userData.S`, `userData.normalAt(u, v) -> {p, n, du, dv}` for rivets / inlays placed on the surface. |
| `sweep(path, section, o)` | Closed 2D section (`[[x,y]...]`, x along the frame normal, y along the binormal, or `fn(t)` for varying shapes) swept along a polyline with parallel-transport frames. `scale` (number, `[sx,sy]` or fn), `twist(t)`, `up` (first normal hint), `closed`, `caps=true`, `hard: [section indices]` (hard corners), `cavScale`. |
| `lathe(profile, o)` | Surface of revolution around +Y, `[[r,y]...]`, analytic normals, `hard: [indices]`, `a0/a1`, `segs`, `auto=true` (orientation by average; `false` = outside on the right of the walking direction, for folded profiles). |
| `extrude(shape, o)` | Bevelled extrusion along Z (centred) of a `THREE.Shape` or `[[x,y]...]`: `depth, bevel, bevelSegs, curveSegs, crease=40` (deg, hard / smooth split via `creased()` with a 0.01 mm position hash). |
| `strip(surf, uvPath, o)` | Raised ribbon following a `(u, v)` path on a plate's surface: inlays, engraved bands, rune strokes. `width, lift, bead, smooth`. |
| `studs(list, o)` | Rivets / bosses `[{p, n, s?}]`: `r=0.006, h=0.004, segs=7, flange=true`. `onSurface(surf, uvs, inset)` gives `{p, n}` on a plate. |
| `circle(n)`, `rrect(w,h,r,cs)`, `lozenge(w,h)`, `curve(ctrl, n, closed)` | section / path helpers |
| `merge(geos)`, `mk(pos, nor, idx, cav, uvw)`, `place(g, {at,rot,scale})`, `mirror(g)` | utilities (`merge` keeps `cav` / `uvw`) |
| `autoCav(g, scale)`, `occlude(g, fn(p))`, `creased(g, angle)`, `fixWinding(g)` | per-vertex data / normals |
| `put(kit, slot, bone, geo, look, o)` | add a rigid piece: `o = { at, rot, scale, glow: fn(p,n,i) -> [inlay, vein, eye], color: override \| fn, tint: fn(p) -> k \| [r,g,b], cav: fn(p) -> k }` |
| `putPair(kit, slot, base, geo, look, o)` | `base+'R'` and its z-mirror on `base+'L'`; per-vertex data and functions are mirrored (unlike `kit.addPair`, which drops the vertex index) |
| `putSkinned(kit, slot, geo, look, weightFn, { frame })` | smooth-skinned piece (gorget between chest and neck) |
| `kitOpts(geo, look, o, mirror)` | the kit options `put()` builds (color / rough / metal / detail / cavity / glow) |

---

## 3. Armour catalogue (`armor.js`)

Frames are the bone frames named in each entry. Defaults are tuned for the default rig (1.9 m); KAEL's values are in
his design. Triangle counts are for the defaults.

### Generic shapes

| builder | frame / notes |
|---|---|
| `hoop(o)` | plate around the local Y axis: `y0, y1`, `a0, a1` (deg, 0 = +X front) or `closed`, `rx, rz, ox, oz, n` (curves over v), `top(a) / bot(a)` (shaped edges: necklines, points, scallops), `ridge(s) {at, h, w, pow, crease}`, `flutes {n, h, a0, a1, fade}`, `bulge(u,v)` + every `plate()` option. The workhorse for cuirasses, faulds, limb tubes, helm shells. |
| `sweepPlate(o)` | plate swept along X around the X axis: `x0, x1` (curves over v), `al0, al1` (deg around X: 0 = +Y, 90 = +Z), `r`, `taper`, `dome`, `cy, cz, xc`, `ridges`. Sabaton lames, toe caps. |
| `dome(o)` | thick cop (lathe): `r, h, thick, rim, lip, segs, sx, sz, point` (`point` > 0 = ogival / pointed). Elbow / knee cops, bosses. |
| `fan(o)` | cupped fluted wing facing +Z: `r0, r1, a0, a1, cup, flutes, fluteH, scallop`. Couter / poleyn wings. |
| `se(a, rx, rz, n)` | superellipse point helper |

### Torso

| builder | frame | notes |
|---|---|---|
| `torsoShape({ rx, rz, ox, n })` | chest | torso cross-section as curves of the chest-frame height (`[[y, r]...]`), shared by every torso plate so layers stay concentric |
| `torsoPlate(o)` | chest | plate following the torso shape between `yTop`, `yBot`: `grow` (m outward), `neck {dip, k}`, `arm {drop, from, to}` (armholes), `point`, `topPoint`, `botBack` + hoop options |
| `breastplate(o)` | chest | medial ridge (hard crease, `ridgeH`), pigeon-breast `swell`, neckline + armholes, rolled neck edge. ~1.4k tris |
| `plackart(o)` | chest | belly plate over the breastplate with a pointed top (rune seat), `grow`, `topPoint` |
| `backplate(o)` | chest | back half with a spine ridge |
| `faulds(o)` | spine / hips | hooped lames below the waist: `y0, lame, overlap, count, rx, rz, ox, a0, a1, point, flare, grow, roll` -> array |
| `tasset(o)` | tasset bone (spring) | thigh guard lames curving round the thigh: `count, h, overlap, r, cx, cz, a0, a1, point` -> array |
| `gorget(o)` | neck (skin with `putSkinned` chest -> neck) | 2-3 flaring collar lames: `count, rTop, rBot, y0, y1, point` -> array |
| `belt(o)`, `buckle(o)`, `strap(path, o)` | any | leather band on an ellipse (`y, rx, rz, ox, h, t, tilt`), buckle frame + prong + plate (`w, h, r`, faces +Z), strap along a path (`w, t, up`) |
| `rivets(plate, uvs, o)` | — | studs on a plate at `(u, v)` positions |

### Shoulders and arms

| builder | frame | returns |
|---|---|---|
| `pauldron(o)` | `deltoidR` (origin = shoulder joint) | `{ cop, boss, over, trim, lames, haute, rivets }`. **cop**: spherical cap over the shoulder (axis tilted `tilt=32` deg outward, `elong` front-back, rim at `cover=74` deg), closed by an apex **boss**; **over** (`flare` > 0): flared over-plate with three forged ridges and pointed lappets, plus an engraved **trim** band; **lames**: hoops around the arm, open toward the body (`lames, lameH, lameStep, lameNu`); **haute** (`haute` = height): standing neck-side fin. Options `R, cy, cz, nu, nv, ridgeH`. Asymmetric designs build two different pauldrons and `mirror()` the left one. |
| `rerebrace(o)` | `upperArmTwist` | tube with ridge and rolled bottom: `r, y0, y1` |
| `couter(o)` | `elbow` | `{ cop (pointed, -X), wing (fan, +Z), lames }`: `r, wing` |
| `vambrace(o)` | `foreArmTwist` | tapered tube, outer ridge, wrist flare: `r, y0, y1` |
| `gauntlet(o)` | `hand`, `fingers`, `fingerTips`, `thumb` | `{ cuff, back, palm, fingers, tips, thumb, rivets }` — two lames per finger segment on the finger bones |

### Legs

| builder | frame | returns |
|---|---|---|
| `cuisse(o)` | `thigh` | open shell over front / outside with a ridge: `r, y0, y1` |
| `poleyn(o)` | `knee` | `{ cop (pointed, +X), wing (fan on the outside, fanning back), lames }`: `r, wing` |
| `greave(o)` | `shin` | closed tube, calf swell, shin ridge (crease), ankle flare: `r, y0, y1` |
| `sabaton(o)` | `foot` / `toe` | `{ lames (foot), toe (toe), sole (foot), toeSole (toe) }`: `scale` |

### Helms (`head` frame; pivot at the skull base, head top ~+0.22)

| builder | returns | options |
|---|---|---|
| `greatHelm(o)` | `{ crown, brow, face, back, slit, eye, breaths, crest, rivets, S }` | `rx=0.128, rz=0.112, top=0.29, bottom=-0.07, ox=0.018, slitY=0.075, slitH=0.016, prow=0.022` (face crease height), `flare` (skirt), `crest` (false = none), `crestH, teeth, crestT`, `crestRidge`. Ogival crown with a front-back crease, engraved-ready brow band projecting over the visor slit, angular prow face plate (pointed superellipse), dark slit recess + `eye` strip (put it with an `eye` look; KAEL modulates it with two hot spots), breath holes in flame-shaped clusters, notched comb crest swept front to back. ~6.5k tris with rivets. |
| `stormHelm(o)` | `{ skull, visor, slits, horns, wings, rivets }` | `r=0.118`: close helm with a ridged visor, three glowing slits, swept twisted horns, feathered wings (VORN) |
| `hoodedMask(o)` | `{ hood, mask, circlet, gem }` | `r=0.125`: cloth cowl with a face opening and a peak (carries `uvw`, cloth set), sculpted half-mask, thin circlet with a star mount (ISKA) |

### Soft layers

| builder / spec | notes |
|---|---|
| `kit.loft(...)` (rig) with a `look` -> `{ color, rough, metal, detail: surfDetail(set, amt) }` | under-suit: `mail`, `quilted` (gambeson), `leather` sets |
| `furRing(o)` | fur mantle: rings of alpha-cut cards with `uvw` (u across, v root -> tip): `center, rx, rz, a0, a1, count, len, width, droop, layers, lift`. Use the `fur` set on a `cutout` material. |
| `clothSpec(o)` (`cloth.js`) | rig verlet cloth spec with kit surfaces: `name, top, length, cols, rows, drape, flare, offset(u,v)` (rest folds), `outer / inner: look`, `slot='cloth'` + any rig cloth option |
| `clothEdges(kit, rig, { name: { burn, sides } })` | call inside `build()`: the cloth meshes the rig adds get `(u, v, code)`; the `cutout` material tears the hem with noise-driven rips, burns holes, chars a band and lights an ember edge (`vein` colour). `burn` 0..1 = depth / char width; `sides`: `'none' \| 'left' \| 'right' \| 'both'` (u = 0 is the fighter's left end of the pinned edge). |

### Inlays and engraving

| function | notes |
|---|---|
| `runes(plate, { u0, u1, v0, v1, glyphs, width, gap })` | strokes of the original angular glyph alphabet `GLYPHS` laid out in a `(u, v)` box on a plate |
| `inlayLine(plate, uvPts, { width })` | smooth flowing inlay strip |
| `strip(plate.userData, uvPath, { width: 0.016 })` + an `engraved` look | engraved trim band (grooves glow on the `vein` channel when the look has `vein` > 0) |

---

## 4. Looks and per-vertex surface encoding

A **look** is `{ color, rough, metal, set, amt, inlay, vein, eye, occ, wear, tint }`:

| key | meaning |
|---|---|
| `color` | sRGB hex or linear `[r,g,b]` (or `fn(p, n, i)`) — for metals this is F0 |
| `rough`, `metal` | 0..1 (multiplied by texture variation, edge wear, grime) |
| `set`, `amt` | texture set name / id and detail amount 0..1 -> `surf.z = surfDetail(set, amt)` |
| `inlay`, `vein`, `eye` | glow channel masks 0..1 (material `glow` mode); per vertex with `o.glow(p, n, i)` |
| `occ`, `wear` | occlusion multiplier for crevices (< 1 darker), edge-wear scale for convex edges |

`surf.z` encoding: `0..1` = legacy detail texture (the knight demo), set `k >= 1` -> `2k + 0.25 + 0.5 * amount`
(robust to interpolation). `decodeDetail(z)` inverts it. `LOOKS` (`looks.js`) holds generic presets
(`blackSteel, scorchedSteel, brightSteel, blueSteel, bronze, silver, gold, leather, darkLeather, mail, gambeson, cloth,
fur, slit, emberInlay`).

---

## 5. Material library (`src/char/materials.js`)

One `createKitMaterial(options)` per material slot = one draw call. All characters share **one program** (two with
cut-out cloth): `customProgramCacheKey` `'edkit-v2'` / `'edkit-v2-cut'`; nothing recompiles at runtime.

### Texture sets (`kit/textures.js`)

A `DataArrayTexture` (sampler2DArray: no atlas bleeding, repeat + mipmaps per layer), 2 RGBA8 layers per set:
layer A = albedo variation, roughness variation, height / proximity, wear-chip noise; layer B = tangent normal (from the
height field, Sobel), micro cavity, set mask.

| id | set | tiles/m | content (mask) |
|---|---|---|---|
| 1 | `hammered` | 4.2 | shallow hammer dents, grain, scratches |
| 2 | `scorched` | 3.4 | soot flakes, sparse pitting, warped fissure network (mask = crack cores, B = heat halo) |
| 3 | `engraved` | 7.5 | interlaced scrolls, leaves and angular glyph bands cut into the metal (mask = groove cores) |
| 4 | `leather` | 9 | pebbled grain, creases, pores |
| 5 | `cloth` | 22 | 2/2 twill of slubbed threads with fibre streaks (mask = gaps) |
| 6 | `fur` | uv | clumped strands (mask = strand coverage; cards sample with their `uvw`) |
| 7 | `mail` | 7.5 | riveted 4-in-1 rings (mask = ring coverage) |
| 8 | `quilted` | 6.5 | diamond-quilted gambeson with stitches (mask = stitch lines) |

Default resolution 256² (~0.5 s to generate on desktop, 5.3 MB GPU with mips). `configureTextureSets({ size: 512 })`
before the first character for crisper cinematic close-ups (~2 s, 21 MB). Generated once, deterministic.

### Shader (onBeforeCompile on `MeshStandardMaterial`)

* **Triplanar sampling in bind-pose space** (sticks to skinned surfaces), per-set tiling `SET_SCALE x detailMul`;
  **whiteout-blended normal maps** mapped to view space through the per-vertex skinning rotation.
* **Edge wear**: convex edges (`cav > 1`) reveal brighter, smoother bare metal (`wearColor`), chipped by noise;
  dielectrics scuff lighter. **Crevice grime**: vertex occlusion + micro cavity darken (`grimeColor`) and roughen.
* **Heat tint** around cracks (scorched set, `heatColor`).
* **Emissive channels** (`glow` option): `inlay` (direct), `vein` (x the set mask: cracks / engraved grooves, slow
  flicker on `uEmber.x` time), `eye` (direct). Glowing fissures go dark, rough and non-metallic.
* **Fresnel rim** `rim: [r, g, b, power]` weighted toward up-facing normals and by occlusion: silhouettes pop against
  the dark arena. **Hit flash** `uFlash` (fresnel weighted; driven by `char.flash()`).
* **Cut-out** (`cutout: true`, double sided): cloth hems tear / char / burn (see `clothEdges`), fur cards alpha-test
  their strands. Shadows of cut-out pieces are full quads (see rig requests).

### `createKitMaterial(o)` options

| option | default | meaning |
|---|---|---|
| `color` | `0xffffff` | multiplies the vertex colour |
| `roughness`, `metalness` | 1, 1 | multiplied by the per-vertex values |
| `envMapIntensity` | 1 | |
| `bump` | 0.6 | normal strength (all sets; legacy bump for set 0) |
| `detailScale` | 9 | legacy set-0 tiling (tiles/m) |
| `detailMul` | 1 | scales every set's tiling |
| `glow` | — | `{ inlay, vein, eye }` HDR linear colours -> channel mode (vertex glow = masks). Without it vertex glow is HDR radiance (legacy) |
| `glowScale` | 1 | emissive multiplier |
| `rim` | `[0,0,0,3]` | fresnel rim colour (HDR) + power |
| `wear` | `[0.9, 0.8, 0.35, 0.6]` | strengths: edge wear, crevice grime, albedo variation, heat tint |
| `wearColor`, `grimeColor`, `heatColor` | `[0.26,0.27,0.29]`, `[0.28,0.24,0.21]`, `[0.16,0.1,0.18]` | bare metal / crevice multiplier / temper tint (linear `[r,g,b]` or hex) |
| `ember` | `[0, 2.2, 0, 0.05]` | `[time, flicker speed, -, vein halo]` |
| `cutout` | false | torn cloth / fur alpha test (separate program), forces double-sided |
| `side` | `'front'` | `'double'` for two-sided shells |

Uniforms live on `material.userData.kit` (`uGlowA/B/C`, `uRim`, `uWear`, `uEmber`, `uFlash`, `uGlowScale` ...).

### Glow control (per character, animatable, no recompiles)

```js
import { attachGlow, createGlowControl } from '../char/materials.js';
const glow = attachGlow(char);                    // char.glow; spec = char.design.glow; char.update() advances it
glow.set('eye', [12, 4.5, 1.0], 1.2);             // colour (HDR / hex / Color), intensity
glow.flare('all', 2.5, 0.6, { attack: 0.06 });    // x(1 + 2.5 * env) for 0.6 game-seconds, quadratic release
glow.flare('vein', 4, 0.3);                       // skill wind-up: cracks blaze
glow.gain = 0.3;                                  // master (e.g. KO: embers cool down)
glow.rim([0.4, 0.5, 0.8], 3.0);                   // rim of every material (arena mood)
glow.update(dtGame);                              // only when not attached (attachGlow wraps char.update)
// design shortcut: kael.attach(char) === attachGlow(char, kael.glow)
```

`createGlowControl(materials, spec)` works on any `{ slot: material }` map or array (weapon displays, props). The blade
has its own slot material (`char.weapon.material`), so `createGlowControl([char.weapon.material], ...)` drives the
sword alone (white-hot ultimate blade).

---

## 6. Weapons (`src/char/weapons.js`)

Authored in the **weapon bone frame**: origin = centre of the main fist on the grip axis, +X toward the tip, -Y the
true edge (spear: the lower wing), +-Z the flats. Builders add pieces to `slot` (default `'blade'`) on `bone`
(default `weaponR`) and return the spec. `WEAPON_SPECS.<name>` goes into `design.weapon` / `design.weapons`.

| weapon | builder | spec |
|---|---|---|
| KAEL greatsword (~1.9 m: peen -0.3 .. tip 1.6) | `greatsword(kit, { bone, slot, looks })` | `WEAPON_SPECS.greatsword` |
| ISKA twin crescents (one per hand) | `crescents(kit, { slot, looks })` -> right on `weaponR`, mirror on `weaponL` | `WEAPON_SPECS.crescents` (array `[R, L]` -> `design.weapons`) |
| VORN war spear (~2.5 m: butt spike -0.98 .. tip 1.5) | `spear(kit, { bone, slot, looks })` | `WEAPON_SPECS.spear` |

`buildWeapon(kit, name, o)` dispatches by name. `WEAPON_LOOKS` / `WEAPON_MATERIALS` hold the default looks and slot
material options (glow colours from the roster palette). `helixWrap(o)` (shingled leather grip wrap) and
`bladeSweep(o)` (faceted / hollow-ground blade with fuller, curved paths) are exported for new weapons.

### Sockets (weapon bone frame, metres)

| weapon | socket | position | meaning |
|---|---|---|---|
| greatsword | `weaponBase` | `[0.12, 0, 0]` | blade root above the ricasso lugs (trail start) |
| | `weaponTip` | `[1.6, 0, 0]` | point (trail end, hit sparks) |
| crescents | `weaponBase` / `weaponBase2` | `[0.07, 0, 0]` on `weaponR` / `weaponL` | blade root at the guard |
| | `weaponTip` / `weaponTip2` | `[0.449, 0.263, 0]` (= `CRESCENT_TIP`) | crescent point (the blade curves toward +Y, the back) |
| spear | `weaponBase` | `[1.02, 0, 0]` | head root above the socket |
| | `weaponTip` | `[1.5, 0, 0]` | point |

Twin blades: `design.weapons = WEAPON_SPECS.crescents` creates `weaponBase/weaponTip` (right) and
`weaponBase2/weaponTip2` (left). Extra sockets for VFX go into `design.sockets` (KAEL: `visor`, `pauldron`, `cracks`).

### Grip points (`grips`, weapon bone frame; off-hand IK target, chosen by a clip's `gripAt`)

| weapon | grip | position | use |
|---|---|---|---|
| greatsword | `grip` | `[-0.17, 0, 0]` | off hand below the main hand (two-handed, default) |
| | `pommel` | `[-0.27, 0, 0]` | hand on the pommel (levered swings) |
| | `ricasso` | `[0.17, 0, 0]` | choked grip on the ricasso |
| | `blade` | `[0.56, 0, 0]` | half-swording on the flat (guards, binds; `demo.guard`) |
| crescents | `grip` | `[0, 0, 0]` | own fist (twin blades never two-hand) |
| | `pommel` | `[-0.075, 0, 0]` | pommel strike hold |
| spear | `grip` | `[-0.52, 0, 0]` | rear hand (two-handed default) |
| | `choke` | `[-0.26, 0, 0]` | short grip |
| | `butt` | `[-0.86, 0, 0]` | hand at the counterweight (long reach) |
| | `head` | `[0.78, 0, 0]` | hand under the socket (close thrusts / binds) |

---

## 7. Static kit (`kit/static.js`)

`createStaticKit()` has the kit's `add / addPair / addSkinned` API and the same surface encoding, but merges into plain
`Mesh`es per slot (bones ignored): `sk.finish({ slot: createKitMaterial(...) }) -> THREE.Group` (`userData.triangles`).
Use it for weapon / armour displays, dropped weapons, racks and catalogue renders.

```js
const sk = createStaticKit();
spear(sk);                                                      // pieces in the weapon frame
const prop = sk.finish({ blade: createKitMaterial(WEAPON_MATERIALS.spear) });
scene.add(prop);
```

---

## 8. Budgets (high tier)

| design | draw calls | triangles | notes |
|---|---|---|---|
| KAEL | 4 (`plate`, `suit`, `cloth`, `blade`) | ~58.4k | helm 6.5k, torso (cuirass, gorget, faulds, belt, tassets) 10.5k, pauldrons + fur mantle 11.6k, arms + gauntlets 10.5k, legs 8.5k, greatsword 4.7k, under-suit lofts ~3.3k, cape + waist cloth ~2.6k |

Cost drivers: plate edge rings (`edgeSegs`), rolled rims (`roll` x `rollSegs`), inner skins (`inner: true` only where
the inside shows), small closed hoops (fingers: keep `nu` 6). Profile with the art lab (`stats`) or by wrapping
`kit.add` in Node (the kit modules run headless).

---

## 9. Art lab (`src/labs/art.js`)

```
node tools/shot.mjs art --do "__ED.lab.play('bust')" --at 0.5 --out shots/art/kael_bust
node tools/shot.mjs art --do "__ED.lab.play('turntable')" --at 0,0.25,0.5,0.75,1,1.25,1.5,1.75 --sheet-only --out shots/art/kael_turn
node tools/shot.mjs art --hash arena --do "__ED.lab.play('fight')" --at 1 --out shots/art/kael_arena_fight
node tools/shot.mjs art --do "__ED.lab.play('weapon','greatsword','hilt')" --at 0.5 --out shots/art/w_hilt
node tools/shot.mjs art --do "__ED.lab.play('full')" --at 0 --eval "__ED.lab.play('qa')"     # rig QA (src/char/qa.js)
```

Flags: `#design=kael|iska|vorn|knight` (iska / vorn = the knight body holding their weapons until their designs exist),
`#arena` (the Eclipse Ruins backdrop and lights), `#tex=256|512`. Lighting rig: warm key (shadowed), two cold rims, warm
ember bounce, dim sky, procedural studio environment (PMREM of a dark dome with softboxes). Scenarios: `full`, `bust`,
`face`, `turntable(every)`, `back`, `fight`, `combat(clip, t, yaw)`, `clip(name)`, `silhouette` (lights off, cut-outs
kept), `glow` (flare), `weapon(name, 'all'|'hilt'|'tip')` (sockets: blue base, red tip, yellow grips), `weapons`, `kit`
(helm catalogue), `stats`, `qa(clips)`.

---

## 10. Requested rig changes (owned by the rig team)

1. **Design hooks on the Character**: call `design.attach?.(char)` at the end of `createCharacter` and let designs
   register per-frame updates (today `attachGlow` wraps `char.update`).
2. **Cloth surface data**: let `cloth[i].surface` take `glow` / uv data (or pass `(u, v)` to colour / glow functions) so
   torn hems need no `clothEdges()` wrapper around `kit.addSkinned`.
3. **Quality for build**: pass `ctx.quality` as the 4th argument of `design.build(kit, S, rig, quality)` so designs can
   ship a lighter low-tier variant (drop rivets / trims / fur layers / inner skins).
4. **Cut-out shadows**: give the `cloth` slot mesh a `customDepthMaterial` running the same discard so torn hems and fur
   cast torn shadows (the kit can provide the material).
5. `kit.addPair` drops the vertex index when mirroring function options (`(p, n) => f(...)`); `putPair()` works around it.
