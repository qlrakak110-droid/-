# src/fighters/iska — ISKA 이스카, 서릿별 무녀 · Froststar Oracle (character design)

The character design of ISKA (format: `src/char/README.md` section 6) plus the pieces only she uses. The fighter
registry picks `design.js` up automatically (default export) until `index.js` replaces the stub.

```
design.js   iska: proportions, materials (3 slots), extra bones, springs, colliders, cloth, weapons, sockets, glow, build()
kit.js      her kit pieces: head base, oracle mask, frost eyes, hood + mantle, circlet, high collar, lamellar rows, scale
            rows, crystals, crescent spaulder, crescent vambrace, slim greave, star shapes
tailor.js   tailored cloth: shaped double-sided cloth panels with embroidered borders, star stitches and charms skinned to
            the rig's cloth particles (replaces the rig's rectangular cloth mesh)
src/labs/art_iska.js   her look-dev lab (lab-only poses with the twin crescents, spins, line-up with KAEL, rig QA)
```

```js
import { iska } from '../fighters/iska/design.js';
const c = createCharacter(ctx, iska);
iska.attach(c);                      // c.glow: frost glow channels (flares for skills / ULT), advanced by c.update()
c.glow.flare('eye', 3, 0.8);         // ULT opening: "eyes open, irises glowing"
c.glow.flare('all', 1.5, 0.4);       // skill wind-up: runes, stars and crystals blaze
```

## Look

~1.78 m, slender and long-legged (narrow shoulders, defined waist). Fitted silver-white armour over a dark indigo
bodysuit; frost / starlight glow (roster palette: core `(1.5, 4, 8)` -> `(0.3, 1.2, 3)` -> white mist).

| area | pieces |
|---|---|
| head | peaked indigo hood with a rolled hem framing the face in a pointed arch, embroidered silver bands along the opening and the mantle hem; pearl-silver oracle half-mask (brow plate + nose / cheek plate meeting around almond eye openings), glowing frost eyes behind the openings, frost liners and starlight "tears" (inlay); a fine veil under the nose; crescent-and-star circlet: thin engraved band, a standing crescent crest (horns up) leaning on the hood brim with a glowing eight-point star in its hollow, crystal drops at the temples |
| neck | high silver collar up to the nose (notch at the throat, swept points behind the jaw, flutes, engraved band), gorget flare over the collarbones, crystal clasp |
| torso | sculpted bodice (bust form, medial line, armholes), engraved neckline and lower bands, star medallion on the sternum with frost vines; blued-steel backplate; four laced lamellar rows cinching the waist (hourglass), leather belt with a star buckle and crystal |
| shoulders / arms | crescent spaulders (a crescent moon over each shoulder, horns rising front and back; engraved, frost-lit grooves) over a blued cap and two lames; crystal cluster on the right (camera side); silver arm bands; small pointed couters; slim vambraces rising into a crescent point over the elbow, frost inlay line + star; slim articulated gauntlets |
| hips / legs | scale tassets on spring bones; slim lower-thigh cuisses with a pointed top; pointed knee cops; slim greaves with a point over the knee; sabatons (silver / blued lames) |
| cloth | twin cape tails (swallow-tail hems, outer edges longest) hung under the mantle; a long front tabard with a pointed hem; indigo outer, pale frost-silk lining (flashes in spins), silver embroidered borders (engraved, vein-lit), glowing four-point star stitches, crystal weights at the points |
| ribbons | four frost-blue silk ribbons on spring chains (two from the belt sides, 0.75 m; two from the arm bands, 0.4 m) weighted with crystals |
| weapons | twin crescent blades (`src/char/weapons.js`, `WEAPON_SPECS.crescents`): right on `weaponR`, left on `weaponL` |

## Design data

| field | value |
|---|---|
| `proportions` | `hipHeight 0.95, pelvisDrop 0.055, hipWidth 0.088, thighRatio 0.515, ankleHeight 0.078, footLength 0.125, footDrop 0.05, toeLength 0.07, heelLength 0.058, spine 0.1, chest 0.155, neck 0.24, head 0.09, shoulderHeight 0.19, clavicleRoot 0.028, clavicle 0.162, shoulderBack 0.012, upperArm 0.295, foreArm 0.255, hand 0.078, palm 0.02` |
| heights (zero pose) | hips pivot 1.005, hip joints 0.95 (`s = ±0.088`), waist (spine) 1.105, chest 1.26, shoulder joints 1.45 (`s = ±0.19`), neck base 1.50, head pivot 1.59, head top ~1.78 (hood point 1.86), fist centre ~0.82, knees 0.50 |
| slots | `plate` (silver armour, embroidery, crystals, every glow), `suit` (bodysuit, hood, veil, cloth bodies, ribbons), `blade` (crescents, `WEAPON_MATERIALS.crescents`) = **3 draw calls** (+3 in the shadow pass) |
| `glow` | `{ inlay: [1.0, 2.7, 5.8], vein: [0.3, 1.05, 2.7], eye: [2.2, 5.2, 9.4] }` HDR: `inlay` = stars, tears, liners, inlay lines, crystals (partial mask), `vein` = engraved grooves of the crescents, embroidery, trims, `eye` = the frost eyes |
| `bones` | `tassetR/L` (hips), `ribbonR1..5` / `ribbonL1..5` (hips, belt sides), `armRibbonR1..3` / `armRibbonL1..3` (`upperArmTwist`) |
| `springs` | tassets (stiff, 34 deg cone), belt ribbons (soft: stiffness 20, damping 2.4, gravity 0.85, 72 deg), arm ribbons (26 / 2.8 / 0.8, 70 deg) |
| `colliders` | torso r 0.13, pelvis r 0.13, shoulders r 0.095, upper arms 0.055, forearms 0.048, thighs 0.088, shins 0.06 |
| `cloth` | `tailL` / `tailR` (5 x 13, length 1.0, chest-pinned under the mantle), `tabard` (5 x 10, length 0.66, hips-pinned at the belt) - slot `suit`, rendered by `tailor.js` |
| `weapons` | `WEAPON_SPECS.crescents` (sockets `weaponBase/weaponTip` right, `weaponBase2/weaponTip2` left; tip `[0.449, 0.263, 0]`) |
| `sockets` | `eyes` (head, between the eyes on the mask), `crest` (head, the circlet star), `crystal` (deltoidR, tip of the crystal cluster), `heart` (chest, the star medallion) |
| `idle` | `demo.idle` until her clips exist |

## Budgets

| tier | triangles | draw calls | cloth particles | notes |
|---|---|---|---|---|
| high / mid (`quality.cloth` 1) | **~59.2k** | 3 | 180 (tails 2 x 65, tabard 50) + 18 spring tips | crescents 5.8k, lamellar waist 4.1k, cloth panels 3.2k, hood 2.4k + trims 1.5k, spaulders 4.4k, bodice 3.5k, mask 2.1k, gauntlets 3.5k, vambraces / greaves with bands 4.6k |
| low (`quality.cloth` 0.5) | **~50.8k** | 3 | 76 (tails 2 x 4 x 7, tabard 4 x 5) | lighter variant (below) |

**Low-tier variant.** The design format passes no quality to `build()`, but the rig scales cloth grids by
`ctx.quality.cloth` before building, so `build()` reads the tail grid it was given (`clothGrid(rig, 'tailL')`): fewer
rows than authored = low tier. It then builds coarser hood / collar / spaulder / cloth panels, 11 instead of 16
lamellae per row without lacing, two tasset rows, fewer star stitches, no rivets / studs, no bodice vines, no
vambrace / greave bands. If the rig
starts passing `quality` to `build()`, switch the test to `quality.tier === 'low'` (see requests below).

## Tailored cloth (`tailor.js`)

| function | notes |
|---|---|
| `clothSurface(kit, rig, name, { anchor, thickness })` | sampler of a simulated cloth's rest surface from its particle bones (`<name>_<i>_<j>`, rest offset = grid position, rest rotation = particle frame). `at(u, v)` -> `{ p, n (outward), du, dv, w (bilinear bone weights) }`. `u` 0 = the fighter's left end of the pinned edge, `v` 0 = pinned row .. 1 = hem |
| `panelCloth(kit, S, o)` | shaped double-sided panel: `hem(a) -> v` (pointed / diagonal hems), `sides(b) -> [uL, uR]`, `hemBand`, `sideBand`, `bandSides`, `na`, `nb`, looks `body` / `lining` (slot `slots.body`, default `suit`) and `border` (embroidered bands + cut edges, slot `slots.border`, default `plate`), `stars: [{ a, b, r, width, both }]` (four-point star stitches, tapered rays), `lines: [{ pts, width, look }]` |
| `clothCharm(kit, S, u, v, geo, look, { slot, offset })` | rigid ornament following one cloth point (crystal weights at the tail points) |
| `clothGrid(rig, name)` | `{ C, R }` of a cloth in this build (quality inference) |
| `suppressRigCloth(kit, rig, names)` | call **last** in `build()`: drops the rig's own rectangular meshes of those cloths (recognised by their first skin bone, added through `kit.addSkinned` after `build()` returns) |

Everything is skinned bilinearly to the particle bones exactly like the rig's own cloth mesh: no CPU cost, no draw call.

## Kit pieces (`kit.js`)

All in bone zero-pose frames (+X forward, +Y up, +Z the fighter's right / camera side). `HEAD` (head cross-section
curves) and `EYE` (eye line / opening angles) are exported for pieces that must fit the face.

| function | frame | returns |
|---|---|---|
| `headBase()` | head | dark under-face / skull form |
| `oracleMask()` | head | `{ brow, lower, eyes, veil, tears, arcs, browS, lowerS }`; `eyeGlow(k)` = eye-channel mask for `eyes` |
| `hood({ nu, nv })` | head (skin with `hoodWeights(kit)`) | `{ hood, hem, S, vArch }` |
| `circlet({ tilt })` | head | `{ band, crest, star, starPos, drops, studs }` |
| `highCollar({ top, bottom, nu })` | neck (skin chest -> neck) | `{ collar, flare, clasp, claspGem, collarS }` |
| `lamellarRow(o)` | any (around local Y) | `{ plates, lace }`: `y0, h, count, a0, a1, rx(y), rz(y), ox(y), gap, cover, point, lift, flare, lace` |
| `scaleRows(o)` | any | merged roof-tile scales: `rows, perRow, y0, rowStep, h, a0, a1, rx/rz/ox/oz(y), gap, flare, ridge` |
| `crystal(o)`, `crystalCluster(list)` | any (+Y) | hexagonal frost crystals |
| `crescentSpaulder({ R, nu })` | deltoidR | `{ crescent, cap, lames, trim, rivets, crescentS }` |
| `crescentVambrace({ r, y0, y1 })` | foreArmTwistR | tube with a crescent point over the elbow |
| `oracleGreave({ r, y0, y1 })` | shinR | slim greave with a point over the knee |
| `starShape(ro, ri, n)` | — | star outline for `extrude()` |

## Notes for clip authors (her move set)

* Twin blades: `grip: 0` on every key (the demo clips grip the left hand onto the right crescent's fist, so both fists
  overlap); `mirrorClip(..., { hands: 'swap' })` for left / right variants. The crescent curves toward the IK `up`
  vector (the blade's back); the true edge is the outside of the curve.
* Spins: put the feet in `'hips'` space during the turn (pivot foot under the hip) so the legs do not wrap; the tails,
  tabard and ribbons need ~0.2 s of rotation to flare (see `artiska.spin` in the lab).
* Her reach is shorter than the knight's (fist ~0.82 m in the zero pose, arm 0.55 m): knight-authored hand targets
  are softened by the IK; author hers against these proportions.

## Rig QA (src/char/qa.js, demo clips, same metrics as KAEL / the knight)

`auditClip` over `demo.idle / guard / walkF / walkB / combo1-3 / slam / hit` with her proportions and crescents (headless,
120 Hz; re-run after the rig update of this stage): no NaN; feet never below the 5 mm tolerance (walks dip 3-4 mm like
every design), planted-foot drift identical to the knight (max 2.3 cm, the clips' own); the crescents never reach the
floor (lowest 0.41 m; the greatswords go to -0.69 m); torso / arm proxy intersections at or below KAEL / the knight
except `demo.combo2` (torso|upperArmR 0.17 vs 0.15); joint-limit violations equal or fewer except `demo.combo2`
(6 vs 4: her shorter arms reach the knight-authored hand targets). Deformation: `__ED.lab.play('joints')` shows no
candy-wrapping and no plate gaps. Her own clips will not have the combo2 reach problem.

**Rig regression suite** (`src/labs/rigqa.js`, clip group, run on her exact proportions as an extra body next to the
suite's own ISKA-like body): 79 / 80 checks pass (hand swing / twist, twist-helper steps, grip error, pelvis-drop steps,
NaN over all ten demo clips). The one failure, `demo.walkF` auto pelvis drop 2nd difference (0.0138 m/frame^2 raw vs
0.012), fails on every body including the knight's default proportions (0.0148) and the VORN-like body (0.0158): a
rig / clip item, not a proportion one. Leg-length variants (hip height 0.96 / 0.97, thigh ratio 0.5, narrower hips)
left that value unchanged and two of them added a `demo.combo1M` grip failure, so her proportions stay as they are.
`design.clipScale` (shared-clip retargeting, new in the rig) changes nothing measurable at her 0.966 body scale and is
left unset, so her own clips play unscaled.

## Requested rig changes

1. `design.build(kit, S, rig, quality)` - an explicit quality hook (today the low tier is inferred from the cloth grid).
2. A supported way for a design to provide its own cloth render geometry (or a `surface.mesh(u, v)` callback): today
   `suppressRigCloth()` relies on cloth meshes being added through `kit.addSkinned` after `build()` and on the cloth
   bone naming `<name>_<i>_<j>` (same internals KAEL's torn hems use).
3. Call `design.attach?.(char)` in `createCharacter` so the game gets `char.glow` (flares for skills / ULT).
4. Document the new helper bones (`hipJoint`, `thighTwist`, `elbowVol`, `kneeVol`) so the suit lofts can weight onto them.
