# src/fighters/iska — ISKA 이스카, 서릿별 무녀 · Froststar Oracle (design, motion, choreography)

The character design of ISKA (format: `src/char/README.md` section 6) plus the pieces only she uses. The fighter
registry loads `index.js` (the full fighter module); her motion, choreography and ultimate are documented in
"Fighter content" at the end of this file.

```
design.js   iska: proportions, materials (3 slots), extra bones, springs, colliders, cloth, weapons, sockets, glow, build()
kit.js      her kit pieces: head base, oracle mask, frost eyes, hood + mantle, circlet, high collar, lamellar rows, scale
            rows, crystals, crescent spaulder, crescent vambrace, slim greave, star shapes
tailor.js   tailored cloth: shaped double-sided cloth panels with embroidered borders, star stitches and charms skinned to
            the rig's cloth particles (replaces the rig's rectangular cloth mesh)
index.js    the fighter module: { id 'iska', element 'frost', design, def, clips, present } (see "Fighter content" below)
moves.js    rules definition: frame data, timeline markers, the ultimate's lock clock (BALANCE.md sections 7-9)
clips/      her motion library: 38 clips + 4 poses (iska.*), registered on import; names and timings in clips/NAMES.md
present.js  choreography: per-move marker handlers, projectile bodies, ceremony hooks, the ultimate's shot table
fxlib.js    her particle rows (module scope, registered in setup before prewarm) and 7 composed presets (iska.*)
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

~1.78 m, slender and long-legged (narrow shoulders, defined waist). Fitted cool pearl-silver armour over a dark indigo
bodysuit; frost / starlight glow (roster palette: core `(1.5, 4, 8)` -> `(0.3, 1.2, 3)` -> white mist).

**Silhouette (black-on-grey read).** Head: a soft cowl rounded low over the crown that falls back over the occiput into
a swept-back teardrop point and tucks in at the nape (no vertical back wall, no standing peak), crowned by the crescent
crest - in front silhouette the moon's two fine points and the eight-point star between them stand clear of the cowl
(crescent - star - crescent, not a pair of horns). Shoulders: tall crescent spaulders whose points sweep up front and
back. Waist cinched, long legs, twin swallow-tail cape tails and a long pointed tabard hanging with rest folds.

**Metal read.** Pearl-silver = a bright, faintly blue colour (`silver [0.62, 0.67, 0.76]`, crescents
`[0.66, 0.7, 0.79]`) at a satin roughness (0.38-0.42) with a partly dielectric response (metal 0.72 on the plates and
crescents, 0.78 on the engraved trims, lamellae and scales) and `envMapIntensity 0.95`: the plates keep a light, cool
base instead of going dark mirroring the arena's night floor, with a metal sheen on top; the mask is a near-dielectric
pearl (`[0.64, 0.7, 0.82]`, metal 0.06).
Blued steel stays dark for the value contrast. The studio key is warm and its ember bounce tints the lower mask gold:
judge colour with `#arena`.

| area | pieces |
|---|---|
| head | soft indigo cowl draped over the skull: rounded low crown, the back falling over the occiput into a swept-back teardrop point (the hood's tip folded back, gathered narrow from above, drape folds radiating from it), tucked in under the skull at the nape, flaring into the shoulder mantle, a soft centre-back seam from the crown over the tip; a full rolled brim (turned back on itself) framing the face in a pointed arch, embroidered silver bands along the opening and the mantle hem; pearl oracle half-mask (brow plate + nose / cheek plate meeting around almond eye openings), glowing frost eyes behind the openings, frost liners and starlight "tears" (inlay); a fine veil under the nose; crescent-and-star circlet: thin engraved band, a standing crescent-moon crest (a true crescent: both arcs run to their intersections, so the points taper fine and curl toward each other) leaning back over the brim with a glowing eight-point star in its hollow, crystal drops at the temples |
| neck | high silver collar up to the nose (notch at the throat, swept points behind the jaw, flutes, engraved band), gorget flare over the collarbones, crystal clasp |
| torso | sculpted bodice (bust form, medial line, armholes), engraved neckline and lower bands, star medallion on the sternum with frost vines; blued-steel backplate; four laced lamellar rows cinching the waist (hourglass), leather belt with a star buckle and crystal |
| shoulders / arms | crescent spaulders (a crescent moon over each shoulder, tall points sweeping up front and back to blade-fine tips; engraved, frost-lit grooves) over a blued cap and two lames; crystal cluster on the right (camera side); silver arm bands over blued half-tube rerebraces (outer ridge); fitted indigo leather sleeves and leggings; small pointed couters; slim vambraces rising into a crescent point over the elbow, frost inlay line + star; slim articulated gauntlets |
| hips / legs | scale tassets on spring bones; slim lower-thigh cuisses with a pointed top; pointed knee cops; slim greaves with a point over the knee; fitted sabatons (`sabaton({ P: rig.P })`: silver / blued lames, blued heel cup, pointed toe) |
| cloth | twin cape tails (deep swallow-tail hems, outer edges longest: the inner edge is cut 28 % shorter) hung under the mantle; a long front tabard with a pointed hem (sides 22 % shorter); rest folds in the simulated shape (`tailFold`: one pleat wave across each tail, `tabardFold`: a box pleat, both zero at the pinned row and deepening toward the hem) so the cloth hangs with depth; indigo outer, pale frost-silk lining (flashes in spins), silver embroidered borders (engraved, vein-lit), glowing four-point star stitches, crystal weights at the points |
| ribbons | four frost-blue silk ribbons on spring chains (two from the belt sides, 0.75 m; two from the arm bands, 0.4 m) weighted with crystals |
| weapons | twin crescent blades (`src/char/weapons.js`, `WEAPON_SPECS.crescents`): right on `weaponR`, left on `weaponL` |

## Design data

| field | value |
|---|---|
| `proportions` | `hipHeight 0.95, pelvisDrop 0.055, hipWidth 0.088, thighRatio 0.515, ankleHeight 0.078, footLength 0.125, footDrop 0.05, toeLength 0.07, heelLength 0.058, spine 0.1, chest 0.155, neck 0.24, head 0.09, shoulderHeight 0.19, clavicleRoot 0.028, clavicle 0.162, shoulderBack 0.012, upperArm 0.295, foreArm 0.255, hand 0.078, palm 0.02` |
| heights (zero pose) | hips pivot 1.005, hip joints 0.95 (`s = ±0.088`), waist (spine) 1.105, chest 1.26, shoulder joints 1.45 (`s = ±0.19`), neck base 1.50, head pivot 1.59, head top ~1.78 (cowl crown ~1.82, its folded-back point ~1.74 high and ~17 cm behind the head pivot; crescent points ~1.84, star top ~1.83), spaulder points ~0.165 above the shoulder joints, fist centre ~0.82, knees 0.50 |
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
| high / mid (`quality.cloth` 1) | **59,164** | 3 | 180 (tails 2 x 65, tabard 50) + 18 spring tips | crescents 5.8k, lamellar waist 4.1k, cloth panels 3.2k, hood 2.4k + trims 1.5k, spaulders 4.4k, bodice 3.5k, mask 2.1k, gauntlets 3.5k, vambraces / greaves with bands 4.6k, circlet crest 0.64k |
| low (`quality.cloth` 0.5) | **51,096** | 3 | 76 (tails 2 x 4 x 7, tabard 4 x 5) | lighter variant (below) |

Measured with the art lab (`__ED.lab.play('budget')`); `__ED.lab.play('leaks')` (3 create / dispose cycles of the
roster) returns to the same GPU geometries / textures / programs (11 / 12 / 9).

**Low-tier variant.** The design format passes no quality to `build()`, but the rig scales cloth grids by
`ctx.quality.cloth` before building, so `build()` reads the tail grid it was given (`clothGrid(rig, 'tailL')`): fewer
rows than authored = low tier. It then builds coarser hood / collar / spaulder / cloth panels, 11 instead of 16
lamellae per row without lacing, two tasset rows, fewer star stitches, no rivets / studs, no bodice vines, no
vambrace / greave bands. The low-tier hood (22 x 12) gathers its rows harder toward the crown (`v^1.7` instead of
`v^1.45`) so the rounded top stays round. If the rig
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
| `hood({ nu, nv })` | head (skin with `hoodWeights(kit)`) | `{ hood, hem, S, vArch }`. Shape = side-view profiles by height (head frame): `hoodF` front extent, `hoodB` back extent (rounds over the crown, folds back into the tip at `HOOD_TIP` 0.146, tucks in at the nape), `hoodW` half width, `hoodC` widest point of each ring (front half keeps the fitted temple / brim shape, back half stretches into the tip). Mantle (y <= -0.05) unchanged |
| `circlet({ tilt })` | head | `{ band, crest, star, starPos, drops, studs }` |
| `highCollar({ top, bottom, nu })` | neck (skin chest -> neck) | `{ collar, flare, clasp, claspGem, collarS }` |
| `lamellarRow(o)` | any (around local Y) | `{ plates, lace }`: `y0, h, count, a0, a1, rx(y), rz(y), ox(y), gap, cover, point, lift, flare, lace` |
| `scaleRows(o)` | any | merged roof-tile scales: `rows, perRow, y0, rowStep, h, a0, a1, rx/rz/ox/oz(y), gap, flare, ridge` |
| `crystal(o)`, `crystalCluster(list)` | any (+Y) | hexagonal frost crystals |
| `crescentSpaulder({ R, nu })` | deltoidR | `{ crescent, cap, lames, trim, rivets, crescentS }`; points span x -0.126 .. 0.116, rise to y 0.165 |
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


---

# Fighter content (motion, choreography, ultimate)

## Module wiring (`index.js`)

`export default { id: 'iska', element: 'frost', design, def, clips, present }`.

* `import './clips/index.js'` registers every `iska.*` clip and pose before the clip resolver runs.
* `clips({ hasClip })` builds the slot / move -> clip map. Every state slot maps to its `iska.*` clip when it exists
  (missing ones fall back to the generic twin-blade clips: today only `locked`). Every move id maps to
  `iska.<moveId>`; strikes get `{ clip, hit }` with `hit` read from the clip's own `impact` event (`getClipDef`), so the
  impact pose always lands on the first active frame even if the frame data changes. Projectile skills (no `hits`:
  Starshard Volley, Crystal Procession, Moonlit Afterimage) play 1:1 on the move clock.
* `__ED.game.roster()` reports the live sources for her as `iska/...`.

## Clips (`clips/`, full table with timings in `clips/NAMES.md`)

| file | clips |
|---|---|
| `common.js` | poses `iska.stance` (every clip starts / ends here), `iska.block`, `iska.downPose`; shared helpers |
| `locomotion.js` | `iska.idle` (2.4 s loop, on the balls of the feet), `walkF` / `walkB` (root speed 3.1 / 2.4 m/s, playback 1), `dash`, `backstep`, `dodge`, `roll`, `guard` |
| `moves.js` | the 10 moves `iska.<moveId>`: duration = move duration, `impact` on the first active frame, swing inside trailOn / trailOff, ends on `iska.stance` |
| `ult.js` | lock beats `iska.ult.crystal / orbit / leap / constellation / starfall / land / frostWave / blendBack`, pose `iska.ult.snapPose` |
| `ceremony.js` | `intro`, `victory`, `defeat`, `hitLight`, `hitHeavy`, `guardBreak`, `crumple`, `getup` (also `tech`), `launched`, `fall`, `down`, `ko` |

Strikes go coil -> hang -> 2-4 frame smear -> long extension line -> follow-through -> settle. Both hands always hold
their own crescent (`grip: 0`, fists curled). Root keys copy the rules' motion so origin-space feet stay planted.

## Choreography per move (`present.js`, effects in `fxlib.js`)

Layering: Iska's handlers add to the generic feel (sound, hit-stop, shake, HUD, stats stay generic). Her signature
pieces are `iska.cut` (thin crystalline crescent with a starlight edge; point light only on heavy cuts), `iska.flower`
(frost impact flower on the contact point: cold flash, four-point star, shard fan, tilted ring, mist, optional floor
frost), `iska.gather` (wind-up tell), `iska.crystallise`, `iska.spike`, `iska.iceLine`, `iska.lance`.
Ambient (every round): snowfall over her, orbiting motes, glints on both blade tips, a pool of cold mist; no light.

| move | WIND-UP | RELEASE | IMPACT | AFTERMATH / SETTLE |
|---|---|---|---|---|
| light1 Rime Flick | glint on the right blade | forehand crescent (`swing`) | flower 0.55, slightly downward | — |
| light2 Twin Moons | glint on the left blade | left crescent (`slashL`), right crescent (`slashR`) | flower 0.5 / 0.62 per cut | trail-foot drag in the clip |
| light3 Star Fan | gather at chest | horizontal spin ring (`spin`), heavy twin crescent + shard fan + glints, FOV kick (`shards`) | flower 0.8 with floor frost + ice debris on the knockback hit | — |
| heavy Glacier Pirouette | frost decal + mist at her feet, gather | two spin rings (`spin1`, `spin2`); `frostRing`: wide low ring, ground ring, crown of 11 ice spikes, frost decal, glints, short light, shake | flower 0.55 / 0.95 (frost ring) | glint on `recover` |
| f+heavy Frostline Step | small frost decal, glint | racing ice line 3.7 m (`iceLine`), skid spray + mist on both feet, 3 afterimages (`slide`), heavy crescent (`swing`) | flower 0.7 + a thin streak | braking spray, mist, frost decal (`stop`) |
| d+heavy Rising Crescent | frost decal, gather low | floor ring + mist on `flip`, tall rising crescent drawn by the backflip (`swing`) | flower upward, shard burst, a thin frost pillar, FOV kick | mist + glint on `land` |
| skill1 Starshard Volley | weapon glow | three shards crystallise in a fan (kindle until 0.18 / 0.24 / 0.30), FOV kick | her own `frost.shard` bodies (dimmer, impact on hit / guard / clash); flower 0.6; third shard freezes: ice cage, crystal shell, floor frost, flower 1.2 | glints on both blades |
| skill2 Crystal Procession | gather at the floor | `stab`: flash, shards, ring, short light, vertical shake; `frost`: frost decal + turning rune + mist; `release`: ice line 6.6 m + side tracking shot along the spikes | five `iska.spike` clusters, each larger, the last one huge (+ chroma, slow-mo 0.7 from the rules' `spike5` set piece) | spikes hold, then shatter |
| skill3 Moonlit Afterimage | all glow channels flare | `blink`: afterimages + glints; `vanish`: glitter, star, she disappears; frozen statue (`frost.statue`) left behind | `reappear`: star, ring, glitter, FOV + roll kick; crescent (`swing`), flower 0.8 + kick; the statue bursts forward as a shard lance | — |
| ult opener Frozen Star | `aura`: glints, frost decal | `rune`: star rune + frost decal under the opponent, light; `release`: the circle closes | `snap`: flash, sparks, `ice_form` | whiff: the rune shatters harmlessly (spikes, glitter, mist) |

Ceremony hooks (`on`): intro (frost decal, turning rune, snow vortex, eye / inlay flare), victory (snow, blade glints,
star), KO flourish (frost shatter on the victim, skipped when the KO comes from the lock), perfect dodge, dodge glint,
block glint; the generic teleport burst is suppressed (Moonlit presents its own blink).

## Ultimate: 떨어지는 서릿별 Fall of the Frozen Star (as implemented)

Move clock 0 .. 0.75 (super-freeze + rune), then the lock clock (storyboard t = 0.75 + lock t). `ult.freeze` replaces
the default super-freeze; `ult.start` replaces the default trigger impact; `ult.tick` presents every tick itself
(returns false and books stats / HUD combo via `tickBook`).

| storyboard | lock t | shot (camera) | Iska (clip) | VFX / post / audio |
|---|---|---|---|---|
| 0.00 | (move 0 .. 0.6) | `faceCloseUp` (real-time clock, letterbox, slow push 1.3 -> 0.92 m, FOV 30 -> 26) | `iska.frozen_star`: head bowed, rises, blade twirls, points at the rune | silver-blue mood, eye + inlay flares, snow vortex, cold halo behind the head, exposure dip, `ult_start`, ultimate music |
| 0.60 | (move 0.6 .. 0.75) + 0 .. 0.45 | `topDownSlam` held on the rune (7.2 -> 6.6 m), continued after the trigger (6.4 -> 5.4 m, roll 6 -> 12) | blades overhead, snap pose (0.75); `iska.ult.crystal` at the trigger | rune decal, circle closes; on the trigger: frost ring, flash, sparks, glints, mist, light, shock distortion, ice cage (6 spikes) + crystal shell on the victim, victim held in its hit pose, impact frame, chroma, shake, hit-stop 0.16, `hit_crit` + `ice_form` |
| 1.20 | 0.45 .. 1.65 | two ground-skim orbit cuts around the crystal (0.6 s each, handheld) | `iska.ult.orbit` started at lock 0.42 (fade 0.03) so its six cuts (clip 0.03 + 0.2 k) land on slash1..slash6 (0.45 .. 1.45) | per slash: blink offset around the crystal (facing flips when behind it), afterimage, a short starlight beam, `iska.cut` across the crystal (last one twin), flower, victim impulse + flash, chroma, shake, `hit_slash_heavy` / `ice_crack` |
| 2.40 | 1.65 .. 2.65 | low angle looking up toward the eclipse as she rises (5.6 -> 5.2 m from the crystal, closer than a true wide so she reads against the night sky), slow-mo 0.42 | `iska.ult.leap` (takeoff 0.12 -> offset up 4.3 m over 0.55 s), `iska.ult.constellation` at 1.95 | floor ring, mist, afterimages, `frost_wind`; 9 stars + 7 beams joining them, sky dust, glow flare, light, `charge_up` |
| 3.40 | 2.65 .. 3.65 | over the shoulder from the air down onto the crystal (handheld) | `iska.ult.starfall` (a fling per lance) | 12 `iska.lance` star lances, each leaving an ice crystal stuck in the floor around the victim; flashes, chroma, shake, alternating `ice_crack` / `hit_slash_light` |
| 4.40 | 3.65 .. 4.15 | `impactPunchIn`, slow-mo 0.22, shake 0.9 | `iska.ult.land` started at 3.53 (impact 0.12 = the shatter at 3.65), offset back to the floor over 0.12 s | cage + shell shatter, `frost.shatter`, flower, frost + shock rings, frost decal, star, light, distortion, inverted impact frame, cold flash (0.07; star and light kept below a white-out at the 3 m punch-in), radial blur, chroma, shake 1.0, `ult_impact` + `ice_shatter`; victim thrown out and slammed down |
| 4.90 | 4.15 .. 4.65 | `wideEstablishing` (11 m, drifting) | `iska.ult.frostWave` | `frost.blizzard` frost wave, letterbox out, `frost_wind` |
| 5.40 | 4.65 .. 5.40 | blend back (0.75 s) | `iska.ult.blendBack` (flicks the frost off both blades), offset back to 0 | glitter on both blade tips, snow |

Whiff (dodged / airborne victim): the rune shatters harmlessly (`ult.whiff`).

## Budgets

* No per-frame code in the choreography: everything is spawned on markers / events (spawn-time allocations only); the
  ambient emitters are created once per round. Lights are short flashes from the pooled `h.light` (never added).
* Afterimage ghosts copy whole character meshes (about 59k triangles for Iska, 59k for VORN), so ghost counts are kept
  low: Frostline Step 2, Moonlit Afterimage 2 + the frozen statue + 1 on reappear, ultimate orbit 1 per slash (0.16 s),
  leap 1, landing 1, plus the crystal shell on the victim for the whole lock.
* Profile results: see "Known issues" (triangles) and the director report.

## Known issues / requests to other modules

* **Triangles (VFX / rig):** the fight alone already sits at about 344k triangles on `high` including the shadow pass
  (budget 350k). Every afterimage ghost adds a full character copy, so the ultimate (crystal shell on the victim + one
  ghost per blink) runs over the budget while ghosts are alive. A cheaper ghost (body mesh only, a decimated proxy) is a
  VFX afterimage change; note also that `meshesOf` caches the mesh list per object on first use, so a `filter` option
  passed later is ignored.
* **Generic hit feel (integration):** on heavy / skill / launch hits the generic `combat.hit.*` starburst, the victim's
  white flash and the hit light are the brightest layer; Iska only adds on top.
* **`design.attach` (integration):** the game actor does not call `design.attach(char)`; `present.js` calls it itself in
  `ambient()` (idempotent) so the glow channels (eye / inlay / vein flares) exist in-game.
* **`ult.tick` returning false** also skips the session's stats tick and HUD combo; `present.js` books them itself
  (`tickBook`). An `h.book(e)` helper would be cleaner.
* **HUD:** the ultimate banner covers the middle of the frame during the super-freeze close-up and the top-down shot.
* **design.js:** `design.idle` is still `'demo.idle'` (the lab / non-game idle); it should be `'iska.idle'`.
* **`locked`** (Iska as the victim of an opponent's lock) uses the generic fallback clip.
* **Rig (src/char), worked around in the clips:** foot IK in `'hips'` space with the pelvis inverted twists the thighs
  180 deg (Rising Crescent's tuck uses FK legs); blending a foot effector between `'hips'` and `'root'` space across a
  large hips yaw sweeps the target through the body (spins hold hips-space keys until 1-2 frames before landing);
  with `gripAngle 0` hand-IK aims beyond ~50 deg from the thumb-side perpendicular are clamped silently; a clip whose
  foot IK keys are all `{ w: 0 }` throws "IK footR has no pos key"; `qa.jointLimits` reports overhead arms as false
  violations (Euler wrap).
* **Stylisation:** during Star Fan / Glacier Pirouette the pivot foot rides the pelvis while the rules drift her 0.3 /
  0.54 m (the pivot glides on the frost); Frostline Step's feet glide 3.5 m by design. Arms touch where the blades cross
  (Star Fan tuck, guard, orbit) for 2-3 frames.
