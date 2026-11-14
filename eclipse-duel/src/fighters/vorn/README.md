# 뇌진천 雷震天 (id `vorn`) — 천뢰신창 天雷神槍, the Heaven-Thunder Spear of 뇌운보 雷雲堡

The whole visible surface of the hero is a Blender asset, made by `tools/blender/heroes/vorn.py` and loaded
through `src/char/assets.js`. These are VORN's and were not changed: proportions, skeleton, colliders, the weapon
(`WEAPON_SPECS.spear`: butt -0.975 to tip 1.5, grips), and the socket names and positions (`visor`, `hornR`, `hornL`,
`finL`, `runes`, which `present.js` and `fx.js` use as anchors). The 108+ clips run unchanged.

## Rebuild

```sh
tools/blender/build_assets.sh vorn --preview          # rigs + heroes/vorn.py -> assets/chars/vorn + shots/blender/vorn/final.png
tools/blender/bl.sh tools/blender/heroes/vorn.py --stage 3   # stop after a stage (1 body, 2 robe, 3 garments, 4 armour/hat/head, 5 spear, 6 skinned) + sheet
node tools/blender/export_rig.mjs vorn                # after the asset changes its cloth panels
node tools/shot.mjs vorn_asset --do "__ED.lab.play('turntable')" --at 0,0.25,0.5,0.75,1,1.25,1.5,1.75 --sheet 4 --sheet-only --out shots/blender/vorn/eng_turn
node tools/shot.mjs vorn_asset --at 0 --eval "({ s: __ED.lab.play('stats'), d: __ED.lab.play('dispose', 3) })"
```

A full build takes about 55 s (the fused SDF body is cached in `build/blender-cache/`) and peaks at about 2 GB.
Lab: `src/labs/vorn_asset.js` (full, turntable, bust, face, back, waist, hands, feet, pose, clip, the line-up in `sil`
or `lit` mode, stats, dispose, glow). Game review scenario: `shots/blender/vorn/game/*_sheet.png`.

## Parts (asset `assets/chars/vorn/vorn.edm`)

| part | slot | tris | what |
|---|---|---|---|
| body | gear | 3.8k | anatomical base body culled to what shows: hands closed on the haft, the eye band, the neck |
| eyes | gear | 0.2k | glowing eyes under the brim (`eye` channel) |
| robe | cloth | 19.2k | storm-violet silk torso and bound sleeves; crossed ink-black collars with a pale 동정 strip and old-gold thunder-fret brocade; ink hemp trousers; black hemp sash with a tied knot; hemp forearm, palm and tall boot wraps; brocade cuff rings, leather garters; shoulder strap; cuirass top binding (brocade); smoke-violet face wrap with horizontal folds, a nape knot and two tails |
| armour | gear | 15.0k | black lacquered lamellar cuirass (8 x 32 plates) and left shoulder piece (4 x 9), old-gold lacing; lamellar waist guard (요갑, 2 x 13 plates); leather boots |
| hat | gear (rigid head) | 4.7k | deep conical 삿갓 (r 0.30, h 0.32): a low cone that carries the real over-under bamboo plait as baked maps, plus a dark lining, inner crown, bound double rim, bronze finial, headband and chin cords |
| hair | gear | 3.5k | combed hair cap and a long braided queue with a brocade tie |
| queueTassel | hair (cut-out) | 0.2k | the queue's end |
| spear | blade (rigid weaponR) | 4.5k | the 뇌룡창: leaf head with raised midrib and honed bevels (16-point lens sections), an inlaid lightning bolt on both flats (`inlay`), bronze socket, crossguard, tassel collar, bands and butt cap, lacquered shaft, two violet hemp grip wraps |
| spearTassel | hair (cut-out) | 0.4k | violet horsehair tassel on the `tassel` spring chain |
| skirtF / skirtBL / skirtBR | cloth | 3.1k / 2.05k / 2.05k | three-panel split skirt draped by Blender cloth over the hip and leg hull, with turned hems and embroidered hem bands; the sash ends ride skirtF |

Total: **58,702 triangles, 4 draw calls** (cloth, gear, hair, blade), 39.2k vertices.

## Materials (looks, `vorn.py` LK; retune in JS through `LOOKS` in `design.js`)

`robe` silk (storm violet), `robeIn` and `collar` (ink black), `dongjeong` silk, `trim` brocade (thunder motif with
old-gold thread; uv code = motif 6 + glow), `sash`, `trousers`, `wrap` and `face` hemp, `leather`, `lamellar`
lacquer (JS retune: rough 0.4, so the plates make no bloom stars), `lace` hemp (old gold, vein 0.12), `bamboo` /
`bambooDark`, `hair`, `shaft` lacquer, `bronze` (verdigris 0.4 in the hollows), `steel` (`blade` set: temper band,
honed edge), `grip` hemp (violet), `bolt` (inlay 1), `horsehair`, `eye`. Baked maps: `vorn_hat_n` (object-space
normal, 34 KB) and `vorn_hat_m` (AO, curvature and strip tones, 101 KB) on the gear slot. The low tier skips them.

## Glow channels (`vorn.glow`, `vorn.attach(char)` -> `char.glow` with the arc crackle)

| channel | colour (HDR linear) | lights |
|---|---|---|
| `inlay` | (2.6, 1.75, 6.6) | the lightning bolt on the spear head (flared by present.js `runes()`); crackle surges |
| `vein` | (1.6, 0.8, 4.6) | the thunder brocade thread (collars, cuffs, hem bands, cuirass binding, queue tie), the old-gold lacing, the spear's material glow |
| `eye` | (6.0, 4.9, 11.5) | the eyes under the hat |

`glow.crackle` (0..1) scales the storm flicker. `set` / `flare` / `gain` / `rim` work as in `attachGlow`.

## Cloth and springs

* Cloth panels (from the Blender drape, `assetCloth`): `skirtF` 6x9, `skirtBL` 4x9, `skirtBR` 4x9, anchored on the
  hips, damping 0.045, margin 0.02, thickness 0.01, wind 0.7, bend 0.35. The upper skirt rides hips, thighs and helper
  bones by weight; the cloth share rises from v 0.1 to v 0.42. The rig adds its default head and neck capsules (warning
  logged, the same as with the knight's surcoat).
* Spring chains (`design.js`, `murim.hang`): `queue1..4` (head; stiffness 26, damping 3, limit 70), `wrapTail1..2`
  (head; the face-wrap tails), `tassel1..2` (weaponR at x 0.93, no collision).

## Numbers (high tier, this machine, shared and loaded)

* Asset 1.73 MB (geometry 1.60 MB plus 135 KB of maps). Header decode 1.1 ms, part decode 14-16 ms; a second VORN
  builds in 37-49 ms. The first VORN takes 470-535 ms, most of it the kit's one-time texture-set generation (the
  pilot measured the same).
* `char.update`: idle, walkF and ninefold_storm all have a median of 0.5 ms and a p90 of 0.7 ms on high (0.3 / 0.4 ms
  on low).
* Dispose: geometries, textures and programs are unchanged after 3 create / dispose cycles (12 / 22 / 17).
* Game page (private build `bl-vorn`): 9.8 MB.

## Roster review (art direction pass, 2026-11-14)

* The storm-violet silk read as bright lavender satin, the loudest and least murim colour of the roster (worst on the
  skirt panels from behind). `LOOKS.robe` is now a deep, dusky violet (0.026, 0.012, 0.048), rough 0.72; the cloth
  material's silk lustre is lower (`sheen: [0.8, 0.6, 1, 0.5]`); the horsehair tassel and grip wraps follow; the eye band
  under the hat is rougher (no wet sheen). Ink black and old gold now carry the contrast; in the game the violet reads
  as storm shadow, and his energy (violet-white) stays the brightest violet on screen.
* The hat's grid-UV bake was never affected by the baked-map seam bug fixed in `src/char/assets.js`.
* Numbers unchanged (58,702 triangles, 4 draw calls, 1.73 MB); `char.update` 0.58 ms median in the art lab `cpu`
  scenario (240 frames x 5, idle pose, shared machine); dispose clean (12 / 22 / 17; the first cycle can show the hat
  maps' async upload once).

## Known limits / next steps

* Up close the hands are the stock `ed.hand()` mitts under tan hemp wraps: they read as paddles on the haft in the
  `hands` view (fine at fight distance). A sculpted, gripping hand in `ed/body.py` would lift all three heroes.
* The face under the hat reads as a black, featureless mannequin head with a sheen line; the smoke-violet face wrap is
  hard to find in the hat's shadow.

* The waist guard reads as a belt-height band more than as hanging tassets. A third row, or a drop below the sash
  knot, would separate it from the sash.
* The torso robe shell and the sleeve caps meet with a visible seam at the right shoulder in close-ups. The left one
  is covered by the shoulder piece.
* The thunder brocade reads as fine sparkle at fight distance. The motif only resolves in the bust and close-ups.
