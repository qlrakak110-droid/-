# src/fighters/vorn — VORN 볼른 · 뇌명의 창기사 · Stormcaller Lancer

```
design.js   the character design (src/char/README.md "Design format"): vorn (default export), vornLow (light variant)
kit.js      VORN-specific kit pieces built on the shared geometry core (src/char/kit/geo.js, armor.js hoop / se)
moves.js    rules definition (rules team; documented in its header)
index.js    fighter module stub (integration team)
src/labs/art_vorn.js   look-dev lab: lighting rig / arena, lab-only spear poses, grip / foot / QA scenarios
```

The design is a tall cavalry knight: storm-blued gunmetal plate, bronze secondary plates, gold rolled rims, violet-white
arc-runes, a horned storm helm with fanned storm-feather wings and a glowing T-visor, a heavy layered left pauldron
(spear bracing) crowned with jagged lightning fins, a compact right pauldron (spear arm) with a gold comb, a split mail
hauberk skirt, a storm-blue surcoat (front panel + two long back tails with lightning-scorched hems), rowel spurs and the
war spear of `src/char/weapons.js` (VORN looks: storm-blued head, blackened haft, storm-blue wraps).

## Usage

```js
import { vorn } from './fighters/vorn/design.js';
const c = createCharacter(ctx, vorn, { name: 'p2' });
const glow = vorn.attach(c);                 // c.glow: set / flare / gain / rim + storm crackle (advanced by c.update)
glow.flare('inlay', 3, 0.5);                 // arc-runes blaze (skill wind-up)
glow.flare('vein', 8, 1.0);                  // "charge": the engraved gold trim and the horns light up violet
glow.crackle = 0;                            // steady runes (cinematic hold); 1 = default crackle
glow.gain = 0.2;                             // KO: the storm dies down
c.play(name, { scale: c.bodyScale });        // shared clips authored for the 1.9 m knight: retarget positions
```

## Data

| field | value |
|---|---|
| slots / draw calls | `plate` (all rigid armour), `suit` (mail torso, quilted arms, leather legs, mail skirt), `cloth` (cut-out surcoat), `blade` (spear) = **4** |
| triangles (high) | **59.5k** (≤ 60k): arms + gauntlets 10.2k, legs + sabatons + spurs 10.1k, helm 8.3k, pauldrons 10.6k (left 7.1k), cuirass 4.2k, faulds / belt 3.3k, gorget 2.0k, mail skirt 0.8k, spear 5.0k, lofts 2.4k, cloth 2.6k |
| triangles (low) | **53.2k** (`vornLow`, or `build(kit, S, rig, { tier: 'low' })`): no rivets, 3 feathers per wing, fewer pauldron lames, coarser plates and rims |
| proportions | the rig team's VORN audit set (`src/labs/rigqa.js` body `vorn`): hipHeight 1.05, pelvisDrop 0.064, hipWidth 0.104, ankleHeight 0.09, footLength 0.145, footDrop 0.058, toeLength 0.086, heelLength 0.07, spine 0.116, chest 0.18, neck 0.265, head 0.11, shoulderHeight 0.21, clavicleRoot 0.032, clavicle 0.2, shoulderBack 0.016, upperArm 0.325, foreArm 0.29, hand 0.09, palm 0.023 (head top ~2.0 m, helm apex ~2.07 m, horn tips ~2.32 m; `bodyScale` 1.071) |
| weapon | `WEAPON_SPECS.spear`: sockets `weaponBase` [1.02,0,0], `weaponTip` [1.5,0,0]; grips `grip` -0.52, `choke` -0.26, `butt` -0.86, `head` +0.78 (weapon bone frame) |
| design sockets | `visor` (head, T-visor centre), `hornR` / `hornL` (horn tips: idle arcs), `finL` (top of the left pauldron fins), `runes` (sternum bolt) |
| cloth | `surcoatF` (front, 6 x 10, 0.64 m), `tailL` (5 x 12, 1.0 m), `tailR` (5 x 12, 0.9 m): 180 particles, torn hems via `clothEdges` (vein-lit edges) |
| colliders | torso r 0.19, pelvis 0.168, shoulders 0.13 / 0.15 (left: heavy pauldron), arms 0.074 / 0.065, thighs 0.118, shins 0.084 |

### Glow (`vorn.glow`, linear HDR)

| channel | colour | where |
|---|---|---|
| `inlay` | (3.4, 2.3, 8.6) | arc-runes: sternum bolt with forks, pauldron bolts, vambraces, cuisses, greaves, fins, feathers, horn seams, cheek "tears", belt plaque cores, plackart glyph |
| `vein` | (1.6, 0.8, 4.6) | charge: engraved grooves of the gold trim (0.06) and the bronze horns (0.08): near dark at rest, they light on a flare; the scorched surcoat hems |
| `eye` | (6.0, 4.9, 11.5) | T-visor (eye hot spots, dimmer breath slot), cheek breath slits (0.12) |

`vorn.attach(char)` = `attachGlow` + a deterministic crackle (game time; no randomness): a fast low flicker and sparse
surges on `inlay` (full), `vein` (60 %) and `eye` (25 %). `glow.set(channel, colour, k)` keeps working: `k` is the base the
crackle modulates. The spear has its own slot material (`char.weapon.material`, `WEAPON_MATERIALS.spear`).

## Kit pieces (`kit.js`)

Frames: a bone's zero-pose frame (+X forward, +Y up, +Z right / camera side); right-side pieces mirror with `mirror()` /
`putPair()`.

| builder | notes |
|---|---|
| `stormHelm(o)` | head frame. `{ skull, comb, brow, browTrim, cheeks, cheekTrim, breaths, chin, chinTrim, nape, recess, eye, horns, hornRoots, feathers (userData.edge), runes, rivets, hornTips }`. Options `rx, rz, top, bottom, ox, eyeY, eyeH, slotW, slotY, prow, hornH, wings, runes, rivets`. ~8.3k tris as used |
| `stormHornTips(o)` | horn tip positions `[R, L]` in the head frame (sockets) |
| `stormFins(o)` | jagged lightning fins for a pauldron (deltoid frame, R side): `at, h, len, lean, yaw, count, gap, depth` -> `{ fins (userData.edge), runes }` |
| `feather(o)`, `blade2d(outline, o)` | bevelled flat blades with an outline mask (`userData.edge`) for gold edging by vertex index |
| `arcPath(u0, v0, u1, v1, o)`, `arcRune(plate, u0, v0, u1, v1, o)` | deterministic zig-zag lightning paths / glowing strips (+ `forks: [[index, deg, length]]`) in a plate's (u, v) space |
| `rim(plate, side, r, o)` | gold rolled bead along a plate edge (`v0 / v1 / u0 / u1`), framed by the plate normal, 10 tris per sample |
| `combAlong(plate, uv, o)` | forged comb standing on a plate surface along a (u, v) path |
| `gorget, rerebrace, vambrace, cuisse, greave, couterLames, poleynLames` | the shared shapes at VORN's segment budget (the shared builders fix their segment counts) |
| `mailSkirt(o)` | one half of the split hauberk skirt (hips frame, R side), skinned hips -> thigh by the design |
| `spur(o)` | rowel spur on the heel (foot frame) |
| `crackle(t, seed)` | the arc flicker multiplier (0.82 .. ~2.0) |

## Rig checks (VORN proportions)

* `src/labs/rigqa.js`: the `vorn` body has exactly these proportions; it fails no check that the knight body passes (the
  open failures are shared runtime items the rig team is working on: twist helper steps, pelvis drop, crossfades).
* Grip (`art_vorn` scenario `grip`, off-hand distance to the grip point after settling): `grip` and `choke` 0 mm in the guard,
  thrust, overhead and brace poses; `butt` reachable in the thrust / overhead poses; `head` (+0.78 m) only in close holds.
* Feet (`feetContact`): sole and toe within ±1.5 mm of the floor in the rest, guard and lunge poses (the shared sabaton toe
  cap is lifted 6.5 mm: its drooping tip would sink 7 mm).
* Pauldron lames are rigid but shared between the deltoid helper and the upper-arm twist bone (lower lames follow the
  arm), so the overhead pose does not leave rings floating around the shoulder.

## Lab

```
node tools/shot.mjs art_vorn --do "__ED.lab.play('bust')" --at 0.5 --out shots/art/vorn_bust
node tools/shot.mjs art_vorn --do "__ED.lab.play('turntable')" --at 0,0.25,0.5,0.75,1,1.25,1.5,1.75 --sheet-only --out shots/art/vorn_turn
node tools/shot.mjs art_vorn --hash arena --do "__ED.lab.play('fight')" --at 1 --out shots/art/vorn_arena
node tools/shot.mjs art_vorn --do "__ED.lab.play('full')" --at 0 --eval "__ED.lab.play('grip')"
```

Flags `#design=vorn|vornLow|kael`, `#arena`, `#tex=256|512`. Scenarios: `full, bust, face, front, turntable, back, side,
fight, pose(name, yaw, dist, ty), clip, silhouette, lineup(sil) (KAEL - VORN - ISKA), glow, joints, feet, hands, stats, grip,
feetContact, qa`. Lab-only poses (not game clips): `vornlab.rest` (spear upright, forward-right), `vornlab.portrait` (spear
at the side, clear of the face), `vornlab.guard`, `vornlab.thrust`, `vornlab.sky` (Stormfall), `vornlab.brace` (choke grip).

## Requests to other teams

* Rig: call `design.attach?.(char)` in `createCharacter`, and pass `ctx.quality` as the 4th `build` argument (VORN's
  `build(kit, S, rig, quality)` already switches to the light variant on `quality.tier === 'low'`).
* Rig: a `customDepthMaterial` with the cut-out discard for the `cloth` slot (torn surcoat hems cast full-quad shadows).
* Game: generic / shared clips should be played with `{ scale: char.bodyScale }` on VORN (positions authored for the
  1.04 m pelvis); the greatsword demo clips put the off hand 0.52 m down the haft, so the off arm crosses the torso in them —
  VORN's own clips must use the spear grips.
