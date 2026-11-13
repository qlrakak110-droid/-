# src/char/kit — murim kit, material library, weapons

Procedural, parametric building blocks for the heroes of 「흑일무림」 (read `MURIM.md` first): cloth-first martial masters
in layered robes, with armour only as accents. Used inside a design's `build(kit, S, rig)` (design format:
`src/char/README.md` section 6). Everything is code: no external assets.

```
src/char/kit/geo.js        geometry core: plate(), sweep(), lathe(), extrude(), strip(), studs(), band(), ribbon(), put() ...
src/char/kit/murim.js      robes, sash, skirt panels, sleeves, wraps, boots, gloves, lamellar, beast pauldron, ornaments,
                           spring-chain hooks (hang, skirtRig)
src/char/kit/head.js       head wrap, demon / silver half-masks, face wrap, headband, bamboo hats, veil, hair
src/char/kit/cloth.js      clothSpec() (verlet cloth), clothEdges() (torn / burnt hems), clothSurface() + clothBorder() (tailoring)
src/char/kit/looks.js      MURIM (cloth-first material library), MOTIF (brocade motifs), LOOKS (older plate presets)
src/char/kit/textures.js   procedural PBR texture sets (DataArrayTexture, generated on first use), SET ids
src/char/kit/mannequin.js  three reference outfits built only from the kit (worked examples; lab: #design=heavy|slender|tall)
src/char/kit/swatch.js     material swatches for the lab
src/char/kit/armor.js      plate-armour builders (hoop() and friends are still the workhorses for rigid shells)
src/char/kit/static.js     createStaticKit(): the same API into plain Meshes (weapon / prop / catalogue displays)
src/char/materials.js      createKitMaterial() (the shared character shader), surfDetail(), glow control
src/char/weapons.js        참마대도 (greatsword), 월아쌍도 (crescents), 뇌룡창 (spear): builders, sockets, grip points, rigs
src/labs/art.js            look-dev lab: heroes, reference outfits, swatches, parts, weapons, budgets
```

Conventions: metres, degrees in options, radians inside the code. Rigid pieces are authored in a bone's **zero-pose
frame** (+X forward, +Y up, +Z the fighter's right / camera side); right-side limb pieces are authored for the `...R`
bone and mirrored with `putPair()`. Head pieces: origin at the skull base, head top ~ +0.22, eye line ~ +0.085.
"curve" options take a number, `[[t, value], ...]` (Catmull-Rom) or `fn(t)`. Sizes are for body scale 1: pass
`scale: rig.k` (heads) or multiply by `kit.rig.k` yourself.

**What must not change** (108 clips depend on it): proportions, skeleton and bone names, sockets, weapon lengths, grip
points, `gripAngle`, the main body colliders. Redesign what is worn and held.

---

## 1. Quick start: a murim hero in 60 lines

```js
import { attachGlow } from '../../char/materials.js';
import { put, putPair, putSkinned, weightsOf, mirror } from '../../char/kit/geo.js';
import { MURIM, MOTIF } from '../../char/kit/looks.js';
import * as M from '../../char/kit/murim.js';
import * as H from '../../char/kit/head.js';
import { buildWeapon, WEAPON_SPECS, WEAPON_MATERIALS, saberStripRig } from '../../char/weapons.js';

const GLOW = { inlay: [6.2, 2.0, 0.34], vein: [3.2, 0.8, 0.09], eye: [5.5, 1.7, 0.3] };   // HDR, linear
// everything that swings is a spring chain declared here and skinned in build()
const SASH = M.hang('sash', 'hips', [0.09, 0.06, 0.15], { n: 3, len: 0.46 });
const SKIRT = { fr: M.skirtRig('skFr', { a0: 3, a1: 96, len: 0.56, follow: 'thighR' }), fl: M.skirtRig('skFl', { a0: -96, a1: -3, len: 0.56, follow: 'thighL' }),
                br: M.skirtRig('skBr', { a0: 92, a1: 181, len: 0.58, n: 3 }), bl: M.skirtRig('skBl', { a0: -181, a1: -92, len: 0.58, n: 3 }) };
const STRIP = saberStripRig();
const RIGS = [SASH, ...Object.values(SKIRT), STRIP];

export const hero = {
  id: 'hero', idle: 'hero.idle', proportions: { /* unchanged */ }, gripAngle: 40, glow: GLOW,
  materials: {
    robe: { cutout: true, glow: GLOW, thread: [0.5, 0.26, 0.07], rim: [0.3, 0.38, 0.6, 3] },   // cloth, hair, veils: double sided
    gear: { glow: GLOW, lace: [0.3, 0.03, 0.012], rim: [0.3, 0.38, 0.6, 3] },                  // masks, armour, boots, ornaments
    blade: WEAPON_MATERIALS.greatsword,
  },
  bones: RIGS.flatMap((r) => r.bones), springs: RIGS.flatMap((r) => r.springs),
  colliders: [/* unchanged */], weapon: WEAPON_SPECS.greatsword,
  attach(char) { return attachGlow(char, GLOW); },
  build(kit, S, rig) {
    const K = rig.k, SILK = { ...MURIM.silk, color: [0.016, 0.014, 0.014] }, TRIM = { ...MURIM.trim, color: [0.02, 0.012, 0.01] };
    const T = M.tailor(kit, { width: 1.12, depth: 1.1 });                 // the torso's garment frame + skin weights
    M.trousers(kit, 'robe', { ...MURIM.hemp, color: [0.03, 0.026, 0.024] });
    const R = M.robe(T, { motif: MOTIF.flame + 0.12 });                   // crossed collar, flame brocade glowing at 12%
    T.put('robe', R.body, SILK); T.put('robe', R.bandOver, TRIM); T.put('robe', R.bandUnder, TRIM);
    const sash = M.sash(T, {});
    T.put('robe', sash, { ...MURIM.silk, color: [0.1, 0.008, 0.006] });
    T.put('robe', M.knot(sash.userData.frame(52)), { ...MURIM.silk, color: [0.1, 0.008, 0.006] });
    const tail = M.sashTail(kit, SASH, {});
    putSkinned(kit, 'robe', tail, { ...MURIM.silk, color: [0.1, 0.008, 0.006] }, weightsOf(tail.userData.W));
    for (const Rg of Object.values(SKIRT)) {
      const p = M.skirtPanel(kit, Rg, { motif: MOTIF.flame + 0.12 });
      putSkinned(kit, 'robe', p.panel, SILK, weightsOf(p.panel.userData.W)); putSkinned(kit, 'robe', p.hem, TRIM, weightsOf(p.hem.userData.W));
    }
    M.sleeve(kit, 'robe', SILK, { to: 'wrist' });
    const boot = M.clothBoot({ P: rig.P });
    for (const [bone, g] of [['foot', boot.upper], ['foot', boot.heel], ['toe', boot.toe], ['shin', boot.shaft]]) putPair(kit, 'gear', bone, g, MURIM.leatherBlack);
    putPair(kit, 'gear', 'foot', boot.sole, MURIM.hemp); putPair(kit, 'gear', 'toe', boot.toeSole, MURIM.hemp);
    const hw = H.headWrap({ scale: K }), dm = H.demonMask({ scale: K });
    put(kit, 'gear', 'head', hw.wrap, MURIM.hempInk); put(kit, 'gear', 'head', dm.face, MURIM.ironCharred);
    put(kit, 'gear', 'head', dm.pits, MURIM.dark); put(kit, 'gear', 'head', dm.eyes, MURIM.eye);   // glowing eyes: the `eye` channel
    buildWeapon(kit, 'greatsword', { strip: STRIP });
  },
};
// runtime: char.glow.flare('vein', 3, 0.6) lets the embroidery, the lacquer cracks and the blade's back blaze
```

`src/char/kit/mannequin.js` is the long version: three complete outfits (heavy / slender / tall) on the heroes' rigs.

---

## 2. Geometry core (`geo.js`)

Every builder returns an **indexed** `BufferGeometry` with `position`, `normal` and two kit attributes:

| attribute | meaning | goes to |
||||
| `cav` (float) | 1 neutral, `< 1` occluded crevice / inner surface (darker, grimier), `1..2` convex edge (edge wear) | material `surf.w` |
| `uvw` (vec3, optional) | cloth / fur surfaces: `(u, v, edge code)` | material `glow` |

`cav` is derived from the mesh (discrete mean curvature: rolled rims, bevels and ridges wear; folds collect grime) and
from builder knowledge (inner skins 0.42, lames darken where they tuck under the plate above).

| function | notes |
|||
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

### Bands and ribbons (new)

| function | notes |
|---|---|
| `band(frames, o)` | **Flat uv-mapped band along surface frames** `[{ p, n, w? }]`: embroidered trims, collars, cuffs, hems, belts, headbands. `width` (m or `fn(t)`), `lift`, `thick`, `crown`, `closed`, `shift` (-0.5 .. 0.5: which edge follows the path), `side` (across-direction hint), `code` (brocade motif + glow), `repeat`, `flipV`, `flat` (3 vertices across, for borders lying on cloth). `uvw` = (u along in band widths, v across, code); `userData.W` = skin weights when the frames carry `w`. |
| `ribbon(pts, o)` | **Bowed strip along a 3D path**: hair locks, sash tails, cords, tassel strands. `width`, `normal` (face hint, vector or `fn(t)`), `camber`, `nu`, `u0`, `du`, `code`, `twist(t)`, `solid` (closed lens for single-sided slots), `weights(t, across)`. Winding follows the normal (double-sided slots shade it correctly). |
| `withUvw(geo, fn(p, n, i))` | set the `uvw` attribute of any geometry |
| `weightsOf(W)` | `weightFn` for `putSkinned()` from per-vertex weights (`geo.userData.W`); `merge()` keeps `userData.W` when every part has it |
| `plate(S, { uvw(u, v) })` | `plate()` / `hoop()` now emit `uvw` for every vertex (edges and rims included): lamellar rows, woven hats |

```js
// a brocade cuff around the right wrist, cloud motif, glowing at 20%
putPair(kit, 'robe', 'foreArm', M.cuff({ y: -0.25, rx: 0.045, w: 0.03, motif: MOTIF.cloud + 0.2 }), { ...MURIM.trim, color: [0.02, 0.03, 0.1] });
```

`put()` hands a geometry's `uvw` to the shader only when the look's set is a UV set (fur, hair, brocade, lamellar,
bamboo, gauze, blade) or the look says `torn: true` (cut-out cloth with tear codes); any other look keeps its glow masks,
so a `band()` can also be used as a plain leather strap.

---

## 3. Plate armour catalogue (`armor.js`)

The pre-murim plate builders: still valid, and `hoop()`, `sweepPlate()`, `dome()` remain the workhorses for any rigid
shell (bracers, caps, hat crowns). The helms and full plate sets are no longer part of the heroes' look (MURIM.md).

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
| `sabaton(o)` | `foot` / `toe` | `{ lames, heel, sole (foot), toe, toeSole (toe) }`, fitted to the rig's foot: pass `P: rig.P` (ankleHeight, footLength, footDrop, toeLength, heelLength; default rig otherwise). Arched lames over the instep, each tucked under the one behind (rolled front edge, medial ridge), heel cup, ridged toe cap tapering to a prow point, thin soles following the outline (bottom 1 mm above the floor; the plates stand on the soles). Options `width=0.046` (half width at the ball), `count=3`, `point=0.55` (0 round .. 1 sharp toe), `ridge=0.004`, `scale=1` (widths / heights only). ~1k tris per foot |

### Helms (`head` frame; pivot at the skull base, head top ~+0.22)

| builder | returns | options |
|---|---|---|
| `greatHelm(o)` | `{ crown, brow, face, back, slit, eye, breaths, crest, rivets, S }` | `rx=0.128, rz=0.112, top=0.29, bottom=-0.07, ox=0.018, slitY=0.075, slitH=0.016, prow=0.022` (face crease height), `prowW=18` (deg half width of the keel: 40-50 gives two angled cheek planes instead of a flat front), `muzzle=0` (m, forward swell over the mouth), `flare` (skirt), `crest` (false = none), `crestH, teeth, crestT`, `crestRidge`. Ogival crown with a front-back crease, engraved-ready brow band projecting over the visor slit, angular prow face plate (pointed superellipse), dark slit recess + `eye` strip (put it with an `eye` look; KAEL modulates it with two hot spots), breath holes in flame-shaped clusters, notched comb crest swept front to back. ~6.5k tris with rivets. |
| `stormHelm(o)` | `{ skull, visor, slits, horns, wings, rivets }` | `r=0.118`: first-pass close helm with a ridged visor, three slits, horns, wings. Catalogue / prop use only: VORN ships his own `stormHelm` in `src/fighters/vorn/kit.js` |
| `hoodedMask(o)` | `{ hood, mask, circlet, gem }` | `r=0.125`: first-pass cowl, half-mask and circlet. Catalogue / prop use only: ISKA ships her own hood, oracle mask and circlet in `src/fighters/iska/kit.js` |

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

## 4. Murim catalogue (`murim.js`, `head.js`, `cloth.js`)

Slots used below: `robe` = a `cutout: true` material (double sided: cloth sheets, hair, veils), `gear` = an opaque
material (masks, armour, boots, hats, ornaments). `T` = a `tailor()`, `K = rig.k`.

### 4.1 Spring-chain hooks

| function | returns | notes |
|---|---|---|
| `hang(name, parent, at, o)` | `{ names, bones, springs, seg, len, dir, n }` | chain of `n` spring bones from `parent` (`at` in its zero frame): `n=3, len=0.3, dir=[0,-1,0], stiffness=24, damping=2.8, gravity=0.9, limit=70, radius=0.02, collide=true`. Spread `.bones` / `.springs` into the design. |
| `skirtRig(name, o)` | `{ names, bones, springs, a0, a1, len, root }` | panel that follows a leg: follower bone at the waist (`follow: 'thighR'`, `k=0.62`, like a tasset) + spring chain for the hem. `a0, a1` (deg sector, 0 = front, 90 = right), `y=0.03` (hips frame), `len=0.7`, `rx=0.15, rz=0.185`, `n=2`, `rigid=0.34`. Without `follow`: a plain chain (back panels, coat tails). |
| `chainWeights(H, s, rootBlend)` / `chainPath(kit, H)` | weights / bind-space points | for your own pieces on a chain (`s` = 0 root .. 1 tip) |
| `H.veilRig(name, o)` | `{ chains, bones, springs }` | `chains=6` hang() chains around a hat brim: `R, y, len, a0, a1` (a parted veil), `tilt` |
| `saberStripRig()`, `crescentTasselRigs()`, `spearTasselRig()` (`weapons.js`) | hang() chain(s) on the weapon bones | cloth strip of the ring pommel, pommel tassels, 창영 |

```js
const TAIL = M.hang('tail', 'head', [-0.1, 0.17, 0], { n: 5, len: 0.78, dir: [-0.5, -1, 0], stiffness: 20 });
design.bones.push(...TAIL.bones); design.springs.push(...TAIL.springs);
```

CPU: a spring bone costs ~0.01 ms; the reference outfits carry 16-39 of them and stay near 0.3 ms per `update()`
(desktop). Keep verlet cloth to at most 3 panels per hero; measure with the lab's `cpu` scenario (budget 1.0 ms).

### 4.2 Robes, sash, skirt

| builder | notes |
|---|---|
| `tailor(kit, { body, width=1, depth=1, shoulder=0.55 })` | **Garment frame of the torso**: cross-section by chest-frame height (`body: { rx, rz, ox, n }` curves, or the default athletic torso scaled by `width` / `depth`: 1.12 heavy, 0.86 slender) and the skin weights every torso garment shares (hips / spine / chest / neck by height, clavicles near the armholes). `T.at(aDeg, y, grow) -> { p, n }`, `T.weights(x, y, z)`, `T.ring(y, grow, n)`, `T.path([[a, y]...], grow)` (frames with weights, for `band()`), `T.put(slot, geo, look)`. Heights `y` are metres above the chest pivot at this body's scale. |
| `robe(T, o)` -> `{ body, bandOver, bandUnder }` | **Crossed-collar robe torso**, left over right: `yTop=0.285, yBot=-0.33, grow=0.014`, `cross: { y, a, spread }` (the crossing point and where the V meets the neck), `lapel: { a, y }` (where the over edge reaches the waist), `blouse` (pleats gathered above the sash), `bandW=0.044`, `motif` (brocade code of the collar bands). Layer two: an inner robe (`grow: 0.006, yBot: -0.02, cross: { y: 0.125 }`, pale band) under the outer one. ~2.5k tris. |
| `sash(T, o)` | wide sash with wrap folds: `y=-0.2, h=0.115, grow=0.026, wraps=3`. `sash.userData.frame(aDeg, dy)` gives a frame (with weights) for the knot / plaques / pendants. |
| `knot(frame, { size=0.05, loops=2, droop })` | wrapped centre + two drooping loops at a surface frame (sash, headband) |
| `sashTail(kit, H, { width=0.085, normal, camber, wave })` | hanging cloth end on a `hang()` chain (also sleeve drapes, headband ends, banners) |
| `skirtPanel(kit, R, o)` -> `{ panel, hem, edgeL, edgeR }` | skirt / coat panel on a `skirtRig()`: `flare=0.1, pleats=3, pleat=0.016`, `hem(u)` (shaped hems: points, diagonals, tatters), `bandW=0.05, motif` (hem band), `sideW` (bands along the slits), `wrap` (overlap in deg). |
| `clothSpec({ ..., mesh: false })` + `clothSurface(kit, rig, name, { anchor })` + `clothBorder(kit, S, { body, lining, border, code, hemW, sideW, hem(a) })` | a **verlet** coat tail / cape / long skirt with a tailored surface, lining and brocade hem (max 3 verlet panels per hero) |
| `clothEdges(kit, rig, { name: { burn, sides } })` | torn / charred hems for the rig's own cloth meshes (cut-out slot): unchanged |

```js
const T = M.tailor(kit, { width: 0.86, depth: 0.86 });
const inner = M.robe(T, { grow: 0.006, yBot: -0.02, cross: { y: 0.125, a: 3, spread: 58 }, blouse: 0, bandW: 0.026, motif: MOTIF.lattice });
T.put('robe', inner.body, { ...MURIM.silk, color: [0.014, 0.02, 0.085] }); T.put('robe', inner.bandOver, { ...MURIM.trim, color: [0.5, 0.52, 0.56] });
const outer = M.robe(T, { grow: 0.017, motif: MOTIF.wave + 0.1 });
T.put('robe', outer.body, MURIM.silkMoon); T.put('robe', outer.bandOver, MURIM.trim); T.put('robe', outer.bandUnder, MURIM.trim);
```

```js
// verlet coat tail with a thunder-emblem hem (design.cloth: clothSpec({ name: 'coat', slot: 'robe', mesh: false, top: [...], length: 0.8 }))
const cs = clothSurface(kit, rig, 'coat', { anchor: 'hips' });
clothBorder(kit, cs, { slot: 'robe', body: SILK, lining: INNER, border: MURIM.trim, code: MOTIF.thunder + 0.3, hemW: 0.07, sideW: 0.035 });
```

### 4.3 Sleeves, trousers, wraps, boots, gloves

| builder | frame | notes |
|---|---|---|
| `sleeve(kit, slot, look, { to, r, folds })` | (skinned loft, both arms) | `to: 'wrist'` fitted, `'mid'` / `'elbow'` for a wide sleeve that ends under a bell; `r: [shoulder, biceps, elbow, forearm, wrist]`; ring folds bunch around the elbow |
| `sleeveBell({ len, r0, r1, drop, back, bandW, motif })` -> `{ bell, trim }` | `foreArmR` | bell of a wide sleeve (광수): the mouth hangs lower at the back. `putPair(kit, 'robe', 'foreArm', ...)`; add a `sashTail()` on a `hang('drape', 'foreArmR', [-0.05, -0.2, 0])` chain for the gravity-driven fall |
| `cuff({ y, rx, rz, w, motif })` | any limb bone | closed brocade band (sleeve cuffs, trouser hems, boot tops) |
| `trousers(kit, slot, look, { r, folds, to })` | (skinned loft, both legs) | loose trousers gathered at the ankle |
| `limbWrap({ y0, y1, r0, r1, turns, width })` | `foreArmTwistR` / `shinR` | shingled bandage wraps (감발 / 행전) |
| `bracer({ r, splints, open })` -> `{ plate, straps, studs }` | `foreArmTwistR` | lacquered / leather bracer with splints, strap bands and studs |
| `clothBoot({ P: rig.P, width, upturn, shaft, shaftR })` -> `{ upper, heel, sole (foot), toe, toeSole (toe), shaft, top (shin) }` | foot / toe / shin | soft boot with an upturned toe and a pale layered sole, fitted to the rig's foot (soles 1 mm above the floor: check with the lab's `contact`) |
| `glove({ scale })` -> `{ wrist, palm (hand), fingers, tips, thumb }` | hand bones | soft glove / wrapped hand, ~0.5k tris |

```js
M.sleeve(kit, 'robe', SILK, { to: 'elbow' });
const B = M.sleeveBell({ len: 0.25 * K, r1: 0.12 * K, drop: 0.2 * K, motif: MOTIF.wave });
putPair(kit, 'robe', 'foreArm', B.bell, SILK); putPair(kit, 'robe', 'foreArm', B.trim, MURIM.trim);
```

### 4.4 Heads (`head.js`; all rigid on `head` unless noted)

| builder | returns | notes |
|---|---|---|
| `headWrap({ scale, grow, yBot })` | `{ wrap, turns, slot }` | cloth-wrapped head and neck: the base under every hat and mask; `slot` = dark eye slot (look `MURIM.dark`) |
| `eyes({ scale, y, a, w, h, slant, grow })` | `{ pits, glow }` | glowing almond eyes (look `MURIM.eye`: the `eye` glow channel) for heads without a mask |
| `demonMask({ scale, stand, relief, horns, fangs })` | `{ face, pits, eyes, fangs, horns }` | **귀면**: snarling iron half-mask, scowling brows, flat nose, fangs, horns (~3.6k tris) |
| `silverMask({ scale, stand, nose })` | `{ face, pits, eyes, ridge }` | plain silver half-mask with long slanted eye slots |
| `faceWrap({ scale, yTop, yBot })` | geometry | cloth over nose and mouth, wound round the neck (복면) |
| `headband({ scale, y, yBack, w, motif })` | `{ band, knotAt, knotN }` | tie the ends with `sashTail()` on a chain rooted at `knotAt` |
| `bambooHat({ scale, R, h, y, bell, crown, dip, code, tiles, cords })` | `{ shell, knob, cords, brimR, brimY }` | **죽립 / 삿갓**: cone (`bell`) or wide hat with a low crown (`crown: 0.34, dip`); woven inside and out; tilt with `put(..., { rot: [0, 0, -8] })` |
| `veil(kit, V, { opacity, pleat, hem })` | skinned geometry | **면사** on a `veilRig()`: `gauze` look on the cut-out slot |
| `hairCap({ scale, knot, front, side, nape })` | geometry | hair combed back to a knot point (`hair` uv set) |
| `topknot({ scale, at, r, h, lean, pin })` | `{ bun, tie, pin }` | 상투 with a pin (비녀); `hairpin({ len })` standalone |
| `hairTail(kit, H, { width, tip, thin, ribbons })` | `{ tail, tie }` (skinned) | bound tail on a `hang()` chain |
| `queue(kit, H, { width, pitch, taper, brush })` | `{ braid, tie }` (skinned) | braided queue |
| `mane(kit, chains, { scale, locks, a0, a1, width, spread, layers })` | skinned geometry | loose mane shared between a few chains |
| `headAt(aDeg, y, grow, scale)` | `{ p, n }` | point on the head surface, for your own ornaments |

```js
const hat = H.bambooHat({ scale: K, R: 0.285, h: 0.2, y: 0.118, bell: 0.92 });
put(kit, 'gear', 'head', hat.shell, MURIM.bambooDark, { rot: [0, 0, -9] });
const VEIL = H.veilRig('veil', { R: 0.27 * K, y: 0.12 * K, len: 0.24 * K, a0: 44, a1: 316 });   // module level: design.bones / springs
const v = H.veil(kit, VEIL, { opacity: 0.46 }); putSkinned(kit, 'robe', v, MURIM.gauze, weightsOf(v.userData.W));
const q = H.queue(kit, QUEUE, {}); putSkinned(kit, 'robe', q.braid, MURIM.hair, weightsOf(q.braid.userData.W));
```

### 4.5 Armour accents and ornaments

| builder | frame | returns / notes |
|---|---|---|
| `beastPauldron({ R, tilt, relief, mane, fangs, ring })` | `deltoidR` (`mirror()` for the left) | `{ cop, pits, eyes, fangs, ring }`: **수면 견갑**, a guardian beast's face on the shoulder (scowl, snout, fangs, mane lappets, ring in the jaws, glowing eyes). ~2.2k tris |
| `lamellarRows({ rows, rowH, lap, y0, a0, a1, rx, rz, flare, lean, plateW, scallop, code })` | any (around +Y) | geometry per row with the `lamellar` uv set; `code` 0..0.95 = glow through the lacing |
| `lamellarCuirass(T, { yTop, yBot, breast, back, gap, code })` | (skinned, `T.put`) | laced rows around the torso + breast rows |
| `lamellarSpaulder({ R, rows, code, cap })` | `deltoidR` | `{ rows, cap }` |
| `waistGuard({ rows, a0, a1, r, code, motif })` | a `tasset*` bone | `{ rows, head, trim }`: 요갑 hanging panel |
| `tassel({ len, r, strands, thin })`, `pendant({ ring, cord, tassel })`, `gourd({ size })` | hang down -Y from the origin: put them on the last bone of a `hang()` chain | 술 / 노리개 / 호리병 |
| `spearTassel(kit, H, { r, strands, layers, flare })` | weapon frame | `{ collar, strands }`: 창영 (used by `spear(kit, { tassel })`) |

```js
const bp = M.beastPauldron({ R: 0.128 * K });
put(kit, 'gear', 'deltoidR', bp.cop, { ...MURIM.ironCharred, vein: 0.5 }); put(kit, 'gear', 'deltoidR', bp.eyes, MURIM.eye);
put(kit, 'gear', 'deltoidR', bp.pits, MURIM.dark); put(kit, 'gear', 'deltoidR', bp.fangs, MURIM.bronze); put(kit, 'gear', 'deltoidR', bp.ring, MURIM.bronze);
T.put('gear', M.lamellarCuirass(T, { yTop: 0.06, yBot: -0.13, breast: 2, code: 0.1 }), MURIM.lamellar);
const PEND = M.hang('pend', 'hips', [0.03, 0.02, 0.2], { n: 2, len: 0.12, stiffness: 40 });   // module level
const pd = M.pendant({}); put(kit, 'gear', PEND.names[1], pd.jade, MURIM.jade, { at: [0, 0.05, 0] });
```

---

## 5. Looks and the material library

A **look** is `{ color, rough, metal, set, amt, inlay, vein, eye, occ, wear, tint, torn }`: `color` sRGB hex or linear
`[r,g,b]` (for metals: F0), `set` + `amt` the texture set and its detail amount, `inlay / vein / eye` the glow channel
masks (0..1), `occ` / `wear` scale crevice occlusion and edge wear. Copy a preset and tint it:
`{ ...MURIM.silk, color: [0.2, 0.012, 0.01] }`.

### 5.1 `MURIM` presets (`looks.js`) and their sets

| preset | set | what you get | usage |
|---|---|---|---|
| `silk`, `silkCrimson`, `silkIndigo`, `silkMoon`, `silkViolet` | `silk` | matte silk: five-harness satin whose weave only a close-up resolves; anisotropic sheen across the warp, lustre tinted by the dye, soft wrapped terminator, light through thin sheets | `T.put('robe', R.body, MURIM.silkIndigo)` |
| `damask` | `damask` | figured silk: tone-on-tone woven clouds; the **`vein` channel glows through the figure** | `{ ...MURIM.damask, color, vein: 0.14 }` |
| `hemp`, `hempInk`, `wrap`, `cord` | `hemp` | coarse plain weave of uneven threads, fuzz sheen | trousers, wraps, cords |
| `cotton` | `cloth` | 2/2 twill (the older cloth set; also the torn / burnt hem fabric) | |
| `trim` | `brocade` (UV) | embroidered band: metal thread (`thread` material colour) on a ribbed tape in the look's colour. uv code = `MOTIF.x + glow` (`cloud, wave, flame, fret, sun` 적양문, `moon` 한월궁, `thunder` 뇌운보, `lattice`; glow 0..0.95 = **inner energy seeping through the thread**) | `band(frames, { code: MOTIF.flame + 0.2 })` |
| `gauze`, `gauzeInk` | `gauze` (UV) | open-weave veil; uv code = opacity; needs the cut-out slot (weave up close, screen-door dither at distance) | `H.veil(kit, V, { opacity: 0.46 })` |
| `leather`, `leatherBlack` | `leather` | worn leather: pebbled grain, creases, waxed sheen | bracers, boots, straps |
| `lacquer`, `lacquerRed`, `wood` | `lacquer` | 옻칠: deep clear coat, wiped streaks, undercoat on worn rims (`undercoat` colour); **`vein` glows through the craquelure** | masks, bracers, hafts, gourds |
| `lamellar`, `lamellarIron` | `lamellar` (UV) | 찰갑: small domed plates, braided lacing (`lace` material colour), rim wear; uv code = glow through the cords | `lamellarRows({ code: 0.15 })` |
| `bamboo`, `bambooDark` | `bamboo` (UV) | twill plait of split bamboo strips; uv code = glow through the pinholes | `H.bambooHat({})` |
| `steel` | `blade` (UV) | forged blade: pale satin temper band along the edge, misty undulating boundary, mirror-honed cutting edge, flowing grain on the dark body. uv = (metres along, 0 edge .. 1 back, temper height) | weapons |
| `steelDark`, `iron`, `ironCharred` | `hammered` / `scorched` | dark forged iron; `ironCharred` cracks glow on `vein` | demon mask, pauldron |
| `bronze`, `bronzeEngraved`, `gilt` | `bronze` / `engraved` | aged bronze with verdigris creeping out of the hollows (`verdigris` colour / amount); engraved fittings glow in their grooves on `vein` | fittings, rings, finials |
| `silver`, `silverPlain` | `engraved` / `hammered` | | half-mask, hairpin |
| `jade`, `jadeWhite` | `jade` | clouded, veined, waxy gloss, light sinks in | pendants, beads |
| `hair`, `hairGrey`, `horsehair` | `hair` (UV) | strand ribbons / cards with anisotropic highlights; uv code = where the lock thins out (cut-out slot) | hair pieces, tassels |
| `dark`, `eye`, `energy` | — | eye slots / glowing eyes (`eye` channel) / glowing inlay (`inlay` channel) | |

`LOOKS` keeps the older plate presets (`blackSteel`, `scorchedSteel`, `mail`, `gambeson`, `fur` ...).

### 5.2 Texture sets (`textures.js`)

One `DataArrayTexture` (sampler2DArray, repeat + mips per layer), two RGBA8 layers per generated set: A = albedo
variation, roughness variation, height / proximity, wear noise; B = tangent normal, micro cavity, set mask.
**Sets are generated on first use** (`surfDetail()` -> `requireTextureSet()`): a duel only pays for what its two heroes
wear; later sets upload just their two layers.

| id | set | tiles/m | content (mask) |
|---|---|---|---|
| 1 | `hammered` | 4.2 | planished facets, polish streaks, scratches (always generated: base grain and noise source) |
| 2 | `scorched` | 3.4 | soot, pitting, warped fissures (mask = crack cores, blue = heat halo) |
| 3 | `engraved` | 7.5 | scrolls, leaves, glyph bands cut into the metal (mask = grooves) |
| 4 | `leather` | 9 | pebbled grain, creases, pores |
| 5 | `cloth` | 22 | 2/2 twill (mask = gaps) |
| 6 | `fur` | uv | clumped strands (mask = strand coverage) |
| 7, 8 | `mail`, `quilted` | 7.5, 6.5 | riveted rings; diamond quilting (legacy knights) |
| 9 | `silk` | 55 | five-harness satin: fine ribs, slubs, staggered binding points |
| 10 | `hemp` | 26 | plain weave of uneven threads (blue = weave height, mask = gaps) |
| 11 | `damask` | 6.5 | scattered cloud wisps and florets as satin figure (mask = figure) |
| 12 | `brocade` | uv | **motif atlas**: 8 embroidery bands, one height field per channel (A: cloud 운문, wave 파도문, flame 화염문, fret 뇌문; B: sun, moon, thunder emblems, tortoise-shell lattice 귀갑문); embossed in the shader |
| 13 | `lacquer` | 5 | orange peel, wiped streaks, dust pits, sparse craquelure (mask = cracks) |
| 14 | `lamellar` | uv | 4 plates x 2 rows per tile, braided lacing (mask = cords, blue = rim) |
| 15 | `bamboo` | uv | 8 x 8 twill plait of flat strips with nodes (mask = pinholes) |
| 16-20 | `gauze`, `hair`, `blade`, `bronze`, `jade` | uv / 5.5 / 4.6 / 3.2 | **shader modes** reusing the hemp / fur / hammered layers: no texture cost |

Size 256² by default (~10.5 MB of GPU memory with mips when all 15 are generated); `configureTextureSets({ size: 512 })`
before the first character for cinematic close-ups. `prewarmTextureSets(names?)`, `textureSetTimings()`. Measured on
the (heavily loaded: load average 8-37 on 4 cores) build machine, Node, 256²: 15-100 ms of CPU per set; all 15 sets
0.75-1.2 s of CPU where the previous 8 sets took 0.5-0.9 s under the same load; a murim outfit uses 9-11 sets. Use the
lab's `texgen` scenario to measure on your machine.

### 5.3 Shader (onBeforeCompile on `MeshStandardMaterial`)

All characters share **one program** (two with cut-out): `customProgramCacheKey` `'edkit-v4'` / `'edkit-v4-cut'`;
nothing recompiles at runtime.

* **Triplanar sampling in bind-pose space** (sticks to skinned surfaces) for the tiling sets, **mesh uv** for the UV
  sets; whiteout-blended normal maps; detail that falls below a pixel fades (weave, dents) and turns into roughness.
* **Cloth**: anisotropic satin highlight across the warp (`aniso[3]`), dyed lustre (`sheen[3]`), Charlie fuzz sheen,
  wrapped diffuse (`cloth[0]`), light through thin cut-out sheets (`cloth[1]`) and gauze (`cloth[2]`), uneven dye from a
  low-frequency field. **Brocade**: emboss of the chosen motif (3 taps), satin-stitch hatch in close-ups, metal thread.
* **Lacquer / jade**: a sharp clear-coat lobe over the base lobe (`lacquer`), undercoat on worn rims (`undercoat`).
  **Blade**: temper band, misty boundary, honed edge (`wearColor`), forge grain. **Bronze**: verdigris.
* **Edge wear** on convex edges (`cav > 1`), **crevice grime** from vertex occlusion + micro cavity, heat tint around
  cracks (scorched), optional frost / pearl / patina finishes.
* **Emissive channels** (`glow` option) read as inner energy (기): `inlay` and `eye` take per-vertex masks through a
  hot-core ramp (deep colour at the fringe, the channel colour, a whiter core where the mask is high: author a mask
  gradient across a seam for core + halo); `vein` is multiplied by the set mask (cracks, grooves, woven figure, weave
  gaps) or, for UV sets, driven by the uv code (thread, lacing, pinholes), with a blurred halo and pulses that climb
  the body (`pulse`). All three breathe slowly at rest and flare on demand (glow control below).
* **Fresnel rim** `rim: [r, g, b, power]` (faded in from the floor, weighted by occlusion) and the **hit flash**.
* **Cut-out** (`cutout: true`, double sided): torn / charred hems (`clothEdges`), fur and hair strand alpha, gauze.

### 5.4 `createKitMaterial(o)` options

| option | default | meaning |
|---|---|---|
| `color`, `roughness`, `metalness`, `envMapIntensity` | white, 1, 1, 1 | multiply the per-vertex values |
| `bump`, `detailMul`, `detailScale` | 0.6, 1, 9 | normal strength (all sets), tiling of every set, legacy set-0 tiling |
| `glow` | — | `{ inlay, vein, eye }` HDR linear colours -> channel mode (vertex glow = masks) |
| `glowScale`, `ember`, `pulse` | 1, `[0, 2.2, 0, 0.05]`, `[0.12, 1.3, 4, 0]` | emissive multiplier; `[time, flicker speed, -, vein halo]`; `[amount, speed rad/s, climb rad/m, -]` |
| `rim`, `rimFade` | `[0,0,0,3]`, `[0.1, 0.62]` | fresnel rim colour + power; heights over which it fades in from the floor |
| `wear`, `wearColor`, `grimeColor`, `heatColor` | `[0.9, 0.8, 0.35, 0.6]`, steel, brown, violet | edge wear / grime / albedo variation / heat tint; `wearColor` is also the honed edge of blades |
| `thread`, `threadMetal` | `[0.5, 0.33, 0.1]`, 1 | embroidery thread of `brocade` (gold; silver for 한월궁 ...) |
| `lace` | `[0.25, 0.02, 0.015]` | lacing cords of `lamellar` |
| `undercoat`, `lacquer` | `[0.16, 0.03, 0.014]`, 0.85 | colour under worn lacquer rims; gloss of the clear coat |
| `verdigris`, `verdigrisAmount` | `[0.07, 0.2, 0.15]`, 1 | patina of the `bronze` set |
| `aniso` | `[0.45, 0.3, 0.75, 0.5]` | anisotropy: brushed metal, worn edges, fur / hair strands, silk |
| `sheen` | `[1, 0.55, 1, 1]` | cloth / fur fuzz, its roughness, leather wax, silk lustre |
| `cloth` | `[0.3, 0.3, 0.45]` | wrapped diffuse of cloth, light through thin cut-out cloth, through gauze |
| `polish`, `dust`, `frost`, `pearl`, `patina` (+ colours) | 0.35, 0, 0, 0, 0 | metal polish lobe; optional finishes |
| `shadowBias` | 0.004 | extra shadow normal bias of this material's receivers |
| `cutout`, `side` | false, `'front'` | alpha-tested + double sided (separate program); `'double'` for two-sided shells |

Uniforms live on `material.userData.kit`.

### 5.5 Glow control (per character, animatable, no recompiles)

```js
import { attachGlow, createGlowControl } from '../char/materials.js';
const glow = attachGlow(char);                    // char.glow; spec = char.design.glow; char.update() advances it
glow.set('eye', [12, 4.5, 1.0], 1.2);             // colour (HDR / hex / Color), intensity
glow.flare('all', 2.5, 0.6, { attack: 0.06 });    // x(1 + 2.5 * env) for 0.6 game-seconds, quadratic release
glow.flare('vein', 4, 0.3);                       // 운기: embroidery, lacing, lacquer cracks, engraved fittings blaze
glow.gain = 0.3;                                  // master (KO: the energy ebbs)
glow.breath = 0;                                  // steady glow (default 1: each channel breathes slowly at rest)
glow.rim([0.4, 0.5, 0.8], 3.0);                   // rim of every material (arena mood)
```

`createGlowControl(materials, spec)` works on any `{ slot: material }` map or array; the blade has its own slot
material (`char.weapon.material`). `spec.breathe = { inlay: [amount, period s], vein: [...], eye: [...] }` tunes the
rest breathing (default `BREATHE`: 7-16%, 3-5 s periods).

---

## 6. Weapons (`src/char/weapons.js`)

Authored in the **weapon bone frame**: origin = centre of the main fist on the grip axis, +X toward the tip, -Y the
true edge, +-Z the flats. Builders add pieces to `slot` (default `'blade'`) on `bone` (default `weaponR`) and return the
spec. **Lengths, sockets, grips and hand alignment are unchanged from the weapons they replace.**

| weapon | builder | spec | options |
|---|---|---|---|
| 참마대도 (염무강; ~1.93 m: ring -0.334 .. point 1.6) | `greatsword(kit, { bone, slot, looks, strip, temper })` | `WEAPON_SPECS.greatsword` | `strip: saberStripRig()` (cloth strip of the ring pommel on a spring chain) |
| 월아쌍도 (설리화; one per hand) | `crescents(kit, { slot, looks, tassels })` | `WEAPON_SPECS.crescents` (`[R, L]` -> `design.weapons`) | `tassels: crescentTasselRigs()` |
| 뇌룡창 (뇌진천; ~2.5 m: butt -0.975 .. point 1.5) | `spear(kit, { bone, slot, looks, wings, tassel })` | `WEAPON_SPECS.spear` | `tassel: spearTasselRig()` (창영), `wings: false` |

`buildWeapon(kit, name, o)` dispatches by name. `WEAPON_LOOKS` / `WEAPON_MATERIALS` hold the default looks and slot
material options (the weapon slot is cut-out / double sided: cloth strip, tassels). The great saber: broad blade with
a curved back, a spur and a hollow clip to the point, wide honed bevel (`blade` set), blood groove with an **ember
seam** (`inlay` channel), a charred back whose cracks carry the **`vein` channel**, bronze collar with flame tongues,
lobed guard, cord-wrapped two-handed hilt, ring pommel (환두) with a cloth strip. `helixWrap(o)` and `bladeSweep(o)` are
exported for new weapons.

```js
const STRIP = saberStripRig();                       // module level: design.bones.push(...STRIP.bones); design.springs.push(...STRIP.springs)
buildWeapon(kit, 'greatsword', { strip: STRIP });    // in build()
```

### Sockets (weapon bone frame, metres) — unchanged

| weapon | socket | position | meaning |
|---|---|---|---|
| greatsword | `weaponBase` | `[0.12, 0, 0]` | blade root above the collar (trail start) |
| | `weaponTip` | `[1.6, 0, 0]` | point (trail end, hit sparks) |
| crescents | `weaponBase` / `weaponBase2` | `[0.07, 0, 0]` on `weaponR` / `weaponL` | blade root at the guard |
| | `weaponTip` / `weaponTip2` | `[0.449, 0.263, 0]` (= `CRESCENT_TIP`) | crescent point (the blade curves toward +Y, the back) |
| spear | `weaponBase` | `[1.02, 0, 0]` | head root above the socket |
| | `weaponTip` | `[1.5, 0, 0]` | point |

### Grip points (off-hand IK targets, chosen by a clip's `gripAt`) — unchanged

| weapon | grip | position | use |
|---|---|---|---|
| greatsword | `grip` | `[-0.17, 0, 0]` | off hand below the main hand (two-handed, default) |
| | `pommel` | `[-0.27, 0, 0]` | hand at the ring |
| | `ricasso` | `[0.17, 0, 0]` | choked grip on the blade collar |
| | `blade` | `[0.56, 0, 0]` | hand on the flat (guards, binds) |
| crescents | `grip` / `pommel` | `[0, 0, 0]` / `[-0.075, 0, 0]` | own fist / pommel strike hold |
| spear | `grip` / `choke` / `butt` / `head` | `[-0.52, 0, 0]` / `[-0.26, 0, 0]` / `[-0.86, 0, 0]` / `[0.78, 0, 0]` | rear hand / short grip / butt cap / under the socket |

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

Contract: <= 60k triangles, <= 6 draw calls, `char.update` <= 1.0 ms per character on desktop.

| design | draw calls | triangles | spring bones / verlet | notes |
|---|---|---|---|---|
| reference `heavy` | 3 (`robe`, `gear`, `blade`) | 32.8k | 27 / 0 | head 7.0k (demon mask 3.6k), saber 4.3k, beast pauldron + spaulder rows 3.7k |
| reference `slender` | 3 | 30.7k | 39 / 0 | head 6.4k (hat, veil, mask, tail), crescents 6.0k |
| reference `tall` | 3 | 41.1k | 16 / 1 | lamellar cuirass + spaulders ~14k, spear 4.6k |

That leaves 19-29k triangles per hero for the artists' own sculpting. Cost drivers: lamellar rows with `scallop` (3
vertices per plate), `plate()` edge rings and rolled rims, the demon mask (`nu`, `nv`), closed finger hoops. Measure
with the lab: `budget` (every design at high / low), `cpu` (ms per update), `dispose` (GPU leaks), `stats`.

---

## 9. Art lab (`src/labs/art.js`)

Every framing follows the design's height (its head bone). A hero design that throws while it is being rewritten is
replaced by its reference outfit (the error is logged), so the lab keeps working.

```
node tools/shot.mjs art --hash design=kael --do "__ED.lab.play('turntable')" --at 0,0.25,0.5,0.75,1,1.25,1.5,1.75 --sheet 4 --sheet-only --out shots/murim/chars/kael/turn
node tools/shot.mjs art --hash design=iska --do "__ED.lab.play('bust',32)" --at 0.5 --out shots/murim/chars/iska/bust
node tools/shot.mjs art --do "__ED.lab.play('lineup','sil')" --at 0.5 --out shots/murim/chars/x/sil            # black silhouettes
node tools/shot.mjs art --hash arena --do "__ED.lab.play('lineup','fight')" --at 1 --out shots/murim/chars/x/arena
node tools/shot.mjs art --hash "arena&design=kael" --do "__ED.lab.play('duel','vorn')" --at 1 --out shots/murim/chars/x/duel
node tools/shot.mjs art --hash design=heavy --do "__ED.lab.play('sway')" --at 0.3,0.6,0.9,1.2 --sheet-only --out shots/murim/chars/x/sway
node tools/shot.mjs art --do "__ED.lab.play('swatches',0)" --at 0.2 --out shots/murim/chars/x/swatch
node tools/shot.mjs art --at 0 --eval "({ b: __ED.lab.play('budget'), c: __ED.lab.play('cpu'), d: __ED.lab.play('dispose') })"
```

Flags: `#design=kael|iska|vorn|heavy|slender|tall|knight`, `#kit` (line-ups and duels use the reference outfits),
`#arena`, `#tex=256|512`, `#q=low|mid|high`.

| scenario | what |
|---|---|
| `full(yaw)`, `turntable(every)`, `side`, `back(yaw)`, `hero(yaw)` | whole figure; the turntable steps 45 deg every `every` s (8 frames = one sheet) |
| `bust(yaw)`, `face(yaw)`, `waist(yaw)`, `feet(yaw, kind)`, `hands(yaw, kind)` | close-ups (face: yaw 90 = straight on) |
| `pose(name, yaw, dist, ty)`, `combat(clip \| 'combat' \| 'strike', t, yaw)`, `clip(name)`, `fight` | a held pose / clip time / the fight camera |
| `sway(yaw)` | the hero turns and steps side to side in a breeze: sleeves, sash ends, hair, veil, tassels |
| `sil` / `silhouette`, `lineup('sil' \| 'lit' \| 'fight', kind, 'kit')` (alias `roster`) | black on grey; the three heroes (or the reference outfits) side by side |
| `duel(other, kind)` | this hero at x = -2.5 facing a second one at +2.5 (fight-camera distance) |
| `glow(amount, dur)` | flare of every channel |
| `weapon(name, 'all' \| 'hilt' \| 'mid' \| 'tip')`, `weapons` | static displays (sockets: blue base, red tip, yellow grips) |
| `swatches(page, zoom, item)` | every material on a ball and a folded panel, 4 per page; the last page is the brocade sampler |
| `parts(page)` | kit parts on a rack: page 0 heads, page 1 armour accents and ornaments |
| `stats`, `budget`, `dispose` / `leaks(n)`, `cpu(frames, runs, ids)`, `texgen(all)` | numbers: this hero; every design at high / low; GPU objects before / after n create-dispose cycles; ms per `update()` (best of `runs`, robust on a loaded machine); ms per texture set |
| `contact`, `qa(clips)` | lowest y of the footwear in the lab poses; `src/char/qa.js` audit |

Lab-only poses `artlab.<id>.hero / .combat / .strike` exist to judge the designs; fighter clips belong to the content team.

---

## 10. Requested rig changes (owned by the rig team)

1. **Design hooks on the Character**: call `design.attach?.(char)` at the end of `createCharacter` and let designs
   register per-frame updates (today `attachGlow` wraps `char.update`).
2. **Quality for build**: pass `ctx.quality` as the 4th argument of `design.build(kit, S, rig, quality)` so designs can
   ship a lighter low-tier variant (fewer mane locks, plainer lamellar rows, no inner skins).
3. **Cut-out shadows**: give cut-out slot meshes a `customDepthMaterial` running the same discard so torn hems, hair,
   fur and veils cast their real shadows (the kit can provide the material).
4. `kit.addPair` drops the vertex index when mirroring function options; `putPair()` works around it.
5. **Spring chains**: a per-chain `wind` factor (like cloth) would let sash ends, veils and tassels answer `char.wind`;
   today they move with gravity, inertia and collision only.
