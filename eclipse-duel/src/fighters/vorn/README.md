# src/fighters/vorn — VORN 볼른 · 뇌명의 창기사 · Stormcaller Lancer

```
index.js      the fighter module: { id: 'vorn', element: 'volt', design, def, clips, present }
design.js     the character design (src/char/README.md "Design format"): vorn (default export), vornLow (light variant)
kit.js        VORN-specific kit pieces built on the shared geometry core (src/char/kit/geo.js, armor.js hoop / se)
moves.js      rules definition (rules team; documented in its header)
clips/        the vorn.* motion library (animator): index.js registers every clip; NAMES.md = one line per clip
present.js    skill choreography (src/game/README.md "Fighter content API" §3.3-3.5), VORN's own hit feel, the ultimate
fx.js         VORN's signature effects (vorn.*), registered in present.setup
src/labs/art_vorn.js   look-dev lab: lighting rig / arena, lab-only spear poses, grip / foot / QA scenarios
```

Contents: [Content (clips, choreography, ultimate)](#content) · [Review and test commands](#review-and-test-commands) ·
[Known issues](#known-issues) · [Design (art)](#design-art)

---

## Content

### Wiring (`index.js`)

* `import './clips/index.js'` registers 41 clips + 4 poses (`defineClip` / `definePose`). `clips({ hasClip })` maps
  every state slot to its `vorn.<slot>` clip and every move id to `vorn.<move id>`, **only when the clip is registered**
  (anything missing falls back to the generic clips).
* Move clips are authored 1:1 on the rules move clock; a strike clip whose `impact` event equals the move's first active
  instant is mapped as `{ clip, hit }`, so the impact pose stays locked to the frame data if a move is retuned. Arc
  Step's `impact` marks the blink (not a hit) and plays 1:1.
* Registry: `__ED.game.roster()` → `{ id: 'vorn', design: 'index', def: 'index', stub: false }` (module = this folder's
  index.js).

### Clips (`clips/`, details in `clips/NAMES.md`)

| group | clips |
|---|---|
| moves (1:1 on the move clock, `impact` / `trailOn` / `trailOff` / `step` events, root motion = rules motion) | `vorn.flash_jab` (impact 0.11) · `vorn.haft_spin` (0.12) · `vorn.thunder_pierce` (0.20, spike 0.25) · `vorn.gale_sweep` (0.28) · `vorn.lightning_charge` (0.20) · `vorn.skyward_lance` (0.18) · `vorn.thunder_javelin` (release 0.26) · `vorn.stormfall` (release 0.45) · `vorn.arc_step` (blink 0.08) · `vorn.ninefold_storm` (ult opener, 0.70) |
| locomotion / guard | `vorn.idle` (= `recovery`, low spear guard, breathing) · `vorn.walkF` / `vorn.walkB` (root motion = walkSpeed 2.6 / backSpeed 2.0, planted feet ≤ 7 mm) · `vorn.dash` · `vorn.backstep` · `vorn.dodge` (= `roll`) · `vorn.guard` (behind the heavy left pauldron, spear wall) |
| reactions / states | `vorn.hitLight` · `vorn.hitHeavy` · `vorn.guardBreak` · `vorn.crumple` · `vorn.launched` · `vorn.fall` · `vorn.down` · `vorn.getup` · `vorn.tech` · `vorn.ko` · `vorn.locked` (generic motion with VORN's grip, spear kept off the floor) |
| ceremony | `vorn.intro` (spear planted upright, wrenched into the guard) · `vorn.victory` · `vorn.defeat` (one knee on the spear) |
| ultimate lock beats | `vorn.ult.lift` · `.hurl` · `.throw` (release 0.08) · `.leap` · `.bolts` (loop) · `.catch` · `.storm` · `.slam` (`impact` 0.25 = lock 3.20) · `.land` · `.twirl` |
| poses | `vorn.stance` (every recovery's last frame) · `vorn.guardPose` · `vorn.sentinel` · `vorn.ult.skewerPose` |

Grip: right fist = the forward spear hand at the weapon origin; the left hand sits on `choke` (-0.26) in every clip
(blends never move the grip point) and lets go on the one-handed beats (jab, javelin, sweep, charge flight, Stormfall
point, ult air beats). Every clip keys a 42° tilt of the spear in the fist (`GRIP_TILT` in `clips/common.js`; the design
has no `gripAngle` — set `GRIP_TILT` to 0 if one is ever added).

### Choreography per move (`present.js`, beats on the moves.js markers)

Shared layers: every wind-up blazes the design's arc-runes (`design.attach` glow, attached in `ambient`); thrusts send
lightning down the spear (`vorn.spear`); impacts get a volt flower around the strike axis (`vorn.flower`: rings,
line of light through the body, gold sparks born one frame after the hit so they burst when the hit-stop releases,
forks, grounding bolt + scorch) on top of **VORN's own hit feel** (`on.hit` → `hitFeel`, below).

| move | WIND-UP | RELEASE | IMPACT | AFTERMATH |
|---|---|---|---|---|
| light1 섬광 찌르기 Flash Jab | crackle on the spear head | 0.08 one-handed snap thrust, lightning flick down the shaft | 0.11 needle flower (k 0.45) | arcs on guard |
| light2 회전 쳐올리기 Haft Spin | 0.02 arcs crawl on the butt | 0.09 rising electric crescent (spin) | 0.12 flower + gold sparks up the jaw line | — |
| light3 천둥 꿰기 Thunder Pierce | runes + tip charge, 0.04 lunge dust | 0.17 thrust lightning | 0.20 thrust flower; 0.25 **spike**: lance of light 0.7 m past the tip, forks ahead, streak, fov kick → pierce flower + victim seizes | crackle on the tip |
| heavy 폭풍 휩쓸기 Gale Sweep | runes, tip charge | 0.24 low floor crescent (r 2.2 m) | 0.28 sparks + scorch dragged along the floor, flower, ring under the tripped victim, static | scorch decal 3.5 s |
| f+heavy 번개 돌격 Lightning Charge | crouch crackle, gold kick-off sparks | 0.06 lightning dash (`volt.dash`, 2 ghosts), fov punch; 0.17 couched thrust | 0.20 pierce flower, victim seizes 0.7 s | 0.38 skid dust + sparks |
| d+heavy 하늘 꿰뚫기 Skyward Lance | rune decal under the feet, tip charge | 0.15 rising arc | 0.18 flower upward; 0.22 a bolt from just above the tip into the sky (delayed past the hit flash) | — |
| skill1 뇌창 투척 Thunder Javelin | 0.04 lightning wraps the spear, tip charge | 0.26 launch ring + gold cone + light; `volt.javelin` 20 m/s | pierce flower, static 0.9 s, scorch under the victim | — |
| skill2 낙뢰 Stormfall | runes; 0.04 spear to the sky, bolt from the tip to the clouds; **camera**: tilt up from behind him to the storm (0.41 s) then a cut crash-zoom onto the strike; 0.08 rune + scorch marker under the opponent, 0.10 clouds | 0.45 / 0.57 / 0.69 three sky strikes (`vorn.skystrike` + `vorn.strikeX`), the last huge (shake 0.6) | flower down the bolt axis | scorch, crackle |
| skill3 섬전 보법 Arc Step | runes, crackle body + floor | 0.08 blink: `volt.dash` bolt, body hidden (after the generic afterimage snapshot) | — | 0.18 re-form + charged floor line; 0.43 detonation ripple along the line (`vorn.detonate`) → flower + static |
| ult opener | 0.10 sky bolt into the spear tip, 0.20 charge (rune decal, crawling ground, motes) | 0.60 lightning dash-thrust (`volt.dash`, 1 ghost, rain) | → the lock (below); whiff / block: `volt.burst` + sky strike at the tip | — |

Fighter-wide: `ambient` (crackle + motes on the spear head, arcs on the helm horns, a small arc jumping along the
spear head every 0.7-1.8 s while idle / walking / guarding), `intro` (a bolt finds the planted spear, ring, scorch),
`victory` (sky bolt), `ko` (a bolt onto the fallen opponent), `dodge` (crackle).

**VORN's hit feel (`hitFeel`, `on.hit` returns false).** The generic `feel.hit` beats unchanged (hit-stop, flinch,
shake, fov kick, chroma / radial, sounds, combo HUD, stats), with the light event tamed: the shared hit preset at ~60 %
intensity / 85 % size (the volt flower carries the brightness), a violet-tinted body flash, a **monochrome
(non-inverted)** impact frame on finishers / ult hits and a 0.07 violet flash instead of the 0.18 white one. In this
dark arena the inverted impact frame and the stacked flashes read as white-outs (director review).

### Ultimate 천벌의 뇌창 Lance of the Ninefold Storm — as implemented

Super-freeze (move clock 0-0.6) then, on the opening hit (move 0.70), the 5.0 s lock. Lock clock t = 0 at the skewer;
storyboard time (MOVES.md) = 0.90 + t (BALANCE.md § 7).

| lock t (storyboard) | shot (camera) | action (clip) | VFX / post / audio |
|---|---|---|---|
| move 0-0.6 | low hero angle (own shot, cut in after the default freeze set-up), letterbox, then weapon-follow held on the dash | spear raised; `vorn.ninefold_storm` | frozen rain, sky bolt into the tip (0.10), tip charge + rune decal (0.20), dash 0.60 (`volt.dash`, rain), `ult_start` (default), mood darken 0.8 tint `0xa080ff` |
| 0.00 (0.90) | impact punch-in 0.30 s | skewer (`vorn.ult.skewerPose` via the opener) | own impact (replaces the default): pierce flower, spear lightning, violet flash, chroma, radial, hit-stop 0.2, victim seizes 2.3 s |
| 0.05 | — | `vorn.ult.lift`: victim levered up on the spear (+0.75 m) | lightning wraps the shaft |
| 0.30 (1.20) | orbit sweep rising 0.60 s | `vorn.ult.hurl`: victim flicked up (+3.4 m) | flower, sky bolt off the tip, shake |
| 0.45 | (orbit) | `vorn.ult.throw`: release at 0.53 → spear hidden, lightning javelin after the victim | `volt.javelin`, lodged lightning rod crackling in the victim until the catch |
| 0.90 (1.80) | over-the-shoulder looking up 1.40 s | `vorn.ult.leap` (+2.2 m), then `vorn.ult.bolts` loop from 1.30 | nine bolts (ticks 1.00-2.01): odd = sky bolts, even = bolts from his left hand, stutter hit-stops, the ninth a white strike + thin pillar |
| 2.30 (3.20) | wide low establishing 0.65 s, slow-mo 0.35 | `vorn.ult.catch`: a bolt tears the spear out of the victim back into his hand (+4.6 m) | arcs, gold cone, runes, blade glow |
| 2.40 | (wide) | `vorn.ult.storm`: the storm drains into the raised spear | `vorn.storm` (clouds, rain, streaks into the spear), mood darken 0.9, tip charge |
| 2.95 | crash zoom 0.25 s | `vorn.ult.slam` dive (offset down), victim `fall` | spear lightning, 2 ghosts, speedlines, `swing_huge` |
| 3.20 (4.10) | top-down slam 0.90 s | slam (`impact` 0.25 of `vorn.ult.slam`), victim `down` | `vorn.pillar` (one thin column + fat bolt + 3 side bolts, crack + scorch crater, ring of rock spikes, shock across the arena, ground bolts, smoke / static), violet flash, monochrome impact frame, shake 1, `ult_impact` |
| 3.75 / 3.95 | (top-down) | wrench free, vault back (+1.1 m) / down | re-form crackle |
| 4.10 (5.00) | blend back 0.9 s | `vorn.ult.land`; mood restored | landing dust |
| 4.40 | fight framing | `vorn.ult.twirl` → `vorn.stance` (settle 5.00) | arc crescent of the twirl, runes fade |

Damage 90 + 9 × 22 + 230 = 518 (rules). The lock's ticks keep the default bookkeeping (stats, combo HUD, hit-stop) via
`book()`; `end` / `whiff` restore the spear and kill the lodged rod.

---

## Review and test commands

Always build a private copy (`--as vorn-<role>`); scratch scenarios live in the session scratchpad.

```
# every move (wind-up / first active / follow-through)
FIGHTERS=vorn node tools/shot.mjs game --as vorn-dir --size 960x540 --scenario src/game/tests/moves.mjs --sheet --sheet-only --out shots/vorn/moves
# the full ultimate
SECTIONS=ult ULT=vorn node tools/shot.mjs game --as vorn-dir --size 960x540 --scenario src/game/tests/capture.mjs --sheet --sheet-only --out shots/vorn/ult
# cost of the ultimate peak (draw calls, programs, JS groups)
PAIR=vorn:kael node tools/shot.mjs game --as vorn-dir --size 960x540 --scenario src/game/tests/profile.mjs
```

---

## Known issues

See the end of this file's history in the director report; the ones that remain open:

* **Rig (not ours)**: the spear spec has no forward off-hand grip point, so the brief's "right hand at the rear, left hand
  forward" hold is impossible; VORN uses right-hand-forward + left hand on `choke`. The off-hand grip arm is solved
  without a pole (`ik.handL.pole` ignored) and can flip its elbow in one frame; the clips work around it (left hand
  released on the risky beats), small flips remain at grip release / re-grip (javelin 0.23-0.25, charge 0.09, dash 0.025).
  With the right arm bent close to the shoulder the wrist clamp moves the spear 30-45° off the keyed aim (javelin draw
  holds the spear ~45° up).
* **Design (not ours)**: no `gripAngle` (worked around with `GRIP_TILT`); the left upper arm sits inside the torso
  collider in the two-handed hold (QA depth 0.1-0.17, invisible from the fight camera).
* **UI (not ours)**: the ultimate cut-in banner covers the middle third of the frame for ~1.5 s (super-freeze, dash,
  skewer, start of the hurl) and hides the hero shot and the skewer impact.
* **Presentation API**: no way to replace only the default super-freeze camera; `ult.freeze` schedules its own shots with
  `h.after(0)` right after the default ones start.
* **moves.js cam names** (`tiltUp`, `crashDown`, `lowHero`, `orbitRising`, `overShoulderUp`, `wideLow`, `blendBack`) are
  not shot-vocabulary names; the generic layer ignores them and present.js implements every one by hand.
* Intended: the charge / ult flight trailing leg goes past hip-extension ROM (stylised glide); `vorn.ult.slam` drives the
  spear 0.4 m into the floor (pinning the victim).

---

## Design (art)

The design is a tall cavalry knight: storm-blued gunmetal plate, bronze secondary plates, gold rolled rims, violet-white
arc-runes, a horned storm helm with fanned storm-feather wings and a glowing T-visor, a heavy layered left pauldron
(spear bracing) crowned with jagged lightning fins, a compact right pauldron (spear arm) with a gold comb, a split mail
hauberk skirt, a storm-violet surcoat (front panel + two long back tails with lightning-scorched hems; violet keeps him
apart from ISKA's indigo), rowel spurs and the war spear of `src/char/weapons.js` (VORN looks: storm-blued head,
blackened haft, violet wraps).

No stovepipes: the greaves, cuisses and backplate are forged shapes (waisted profiles, a hard keel flanked by sunk
flutes and creased ridges, flared cuffs, pointed edges), and every body arc-rune is a glowing core sunk in a dark
engraved channel with edge-worn lips (`arcInlay`), not a line laid on the plate. The surcoat panel and the two back tails
carry rest pleats (held by the cloth's bend constraints), so they never hang as flat sheets.

Art pass 2 (art director's issues 3 and 4; body proportions, skeleton, sockets, weapon, grips untouched):

| area | before | after |
|---|---|---|
| greaves (`greave`) | closed tube, one shallow shin ridge | flared cuff under the poleyn, deep calf swell, pinched ankle flaring over the sabaton; 2 cm shin keel, sunk flutes at +-29 deg, creased side ridges at +-54 deg (fading toward the ankle), calf seam ridge; pointed knee tongue, instep arch |
| cuisses (`cuisse`) | open shell, one ridge | waisted (flared over the hip, pinched above the knee, kicking out over the poleyn), 1.7 cm keel, two sunk flutes, outer ridges, pointed top edge over the outside of the hip |
| backplate (`flutedBack`) | smooth half shell, low spine ridge | spine keel, a fan of creased flutes / ridges over the shoulder blades fading into the waist, pointed lower edge |
| runes (`arcInlay`) | glowing strip on the plate | glowing core inside a dark engraved channel (blackened floor, raised edge-worn lips; mitred zig-zag corners, tapered graver ends, adaptive sampling so no chord cuts into a curved plate); the greave and cuisse bolts run down the sunk flutes |
| cloth | tails: shallow 2.6 cm waves; front panel flat | tails: two deep pleats each (5 cm, opening toward the hem) + a slow wave and a sideways component; front panel: 2 cm pleats biased outward (clear of the thighs) |
| left pauldron fins | h 0.25 / len 0.26 | h 0.29 / len 0.29 (slightly taller spikes in the front and 3/4 silhouettes, a small change; `finL` socket unchanged, now mid-fin) |
| budget | rims 10 tris / sample | rims 8 tris / sample (5-point bead) pays for the flutes and channels: **+206 tris** net (58,420 -> 58,626 in today's lab) |

### Usage

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

### Data

| field | value |
|---|---|
| slots / draw calls | `plate` (all rigid armour), `suit` (mail torso, quilted arms, leather legs, mail skirt), `cloth` (cut-out surcoat), `blade` (spear) = **4** |
| triangles (high) | **58.6k** (≤ 60k, art lab `budget` 2026-11-12 after the art pass 2; 59.7k with the cloth grids of the earlier rig build): legs + sabatons + spurs ~10.6k (greaves 1.27k + channels / runes 0.67k + rims 0.45k per pair), arms + gauntlets ~10k, helm ~8.1k, pauldrons ~10.4k, cuirass ~4.5k (fluted backplate 1.05k), faulds / belt ~3.2k, gorget ~1.8k, mail skirt 0.8k, spear 5.0k, lofts, cloth |
| triangles (low) | ~**52k** (`vornLow`, or `build(kit, S, rig, { tier: 'low' })`; headless kit count 48.1k vs 54.7k high): no rivets, 3 feathers per wing, fewer pauldron lames, coarser plates, rims and flute columns |
| proportions | the rig team's VORN audit set (`src/labs/rigqa.js` body `vorn`): hipHeight 1.05, pelvisDrop 0.064, hipWidth 0.104, ankleHeight 0.09, footLength 0.145, footDrop 0.058, toeLength 0.086, heelLength 0.07, spine 0.116, chest 0.18, neck 0.265, head 0.11, shoulderHeight 0.21, clavicleRoot 0.032, clavicle 0.2, shoulderBack 0.016, upperArm 0.325, foreArm 0.29, hand 0.09, palm 0.023 (head top ~2.0 m, helm apex ~2.07 m, horn tips ~2.32 m; `bodyScale` 1.071) |
| weapon | `WEAPON_SPECS.spear`: sockets `weaponBase` [1.02,0,0], `weaponTip` [1.5,0,0]; grips `grip` -0.52, `choke` -0.26, `butt` -0.86, `head` +0.78 (weapon bone frame) |
| design sockets | `visor` (head, T-visor centre), `hornR` / `hornL` (horn tips: idle arcs), `finL` (top of the left pauldron fins), `runes` (sternum bolt) |
| cloth | `surcoatF` (front, 6 x 10, 0.64 m), `tailL` (5 x 12, 1.0 m), `tailR` (5 x 12, 0.9 m): 180 particles, torn hems via `clothEdges` (vein-lit edges); rest pleats in `offset` (`tailFolds(u, v, ph, ph2)` for the tails) |
| colliders | torso r 0.19, pelvis 0.168, shoulders 0.13 / 0.15 (left: heavy pauldron), arms 0.074 / 0.065, thighs 0.118, shins 0.084 |

### Glow (`vorn.glow`, linear HDR)

| channel | colour | where |
|---|---|---|
| `inlay` | (2.6, 1.75, 6.6) | arc-runes: sternum bolt with forks, pauldron bolts, vambraces, cuisses, greaves (all six in engraved channels: `L.groove`), fins, feathers, horn seams, cheek "tears", belt plaque cores, plackart glyph |
| `vein` | (1.6, 0.8, 4.6) | charge: engraved grooves of the gold trim (0.06) and the bronze horns (0.08): near dark at rest, they light on a flare; the scorched surcoat hems |
| `eye` | (6.0, 4.9, 11.5) | T-visor (eye hot spots, dimmer breath slot), cheek breath slits (0.12) |

`vorn.attach(char)` = `attachGlow` + a deterministic crackle (game time; no randomness): a fast low flicker and sparse
surges on `inlay` (full), `vein` (60 %) and `eye` (25 %). `glow.set(channel, colour, k)` keeps working: `k` is the base the
crackle modulates. The spear has its own slot material (`char.weapon.material`, `WEAPON_MATERIALS.spear`). The game does
not attach it: `present.ambient` calls `design.attach(char)` once per character (a no-op if `char.glow` exists).

### Kit pieces (`kit.js`)

Frames: a bone's zero-pose frame (+X forward, +Y up, +Z right / camera side); right-side pieces mirror with `mirror()` /
`putPair()`.

| builder | notes |
|---|---|
| `stormHelm(o)` | head frame. `{ skull, comb, brow, browTrim, cheeks, cheekTrim, breaths, chin, chinTrim, nape, recess, eye, horns, hornRoots, feathers (userData.edge), runes, rivets, hornTips }`. Options `rx, rz, top, bottom, ox, eyeY, eyeH, slotW, slotY, prow, hornH, wings, runes, rivets`. ~8.3k tris as used |
| `stormHornTips(o)` | horn tip positions `[R, L]` in the head frame (sockets) |
| `stormFins(o)` | jagged lightning fins for a pauldron (deltoid frame, R side): `at, h, len, lean, yaw, count, gap, depth` -> `{ fins (userData.edge), runes }` |
| `feather(o)`, `blade2d(outline, o)` | bevelled flat blades with an outline mask (`userData.edge`) for gold edging by vertex index |
| `arcPath(u0, v0, u1, v1, o)`, `arcRune(plate, u0, v0, u1, v1, o)` | deterministic zig-zag lightning paths / glowing strips (+ `forks: [[index, deg, length]]`) in a plate's (u, v) space (helm, fins, feathers) |
| `arcInlay(plate, u0, v0, u1, v1, o)` | engraved arc-rune: `{ rune, channel }` — glowing core (put with the inlay look) sunk in a dark channel with raised edge-worn lips (put with `L.groove`). Options: arcPath + `width` (core, 0.003), `channel` (full width, 5.5 x core), `lift` (0.0009), `lip` (0.0019), `forks`, `step` (0.022 m max chord) |
| `groove(surf, uv, o)` | one channel + core along a (u, v) polyline: adaptive sampling, mitred corners, tapered ends; 14 tris per sample |
| `rim(plate, side, r, o)` | gold rolled bead along a plate edge (`v0 / v1 / u0 / u1`), framed by the plate normal, 8 tris per sample |
| `combAlong(plate, uv, o)` | forged comb standing on a plate surface along a (u, v) path |
| `gorget, rerebrace, vambrace, couterLames, poleynLames` | the shared shapes at VORN's segment budget (the shared builders fix their segment counts) |
| `cuisse(o)`, `greave(o)` | VORN's forged leg shells (see the art pass table above): `r, y0, y1, nu, nv`; flutes are creased columns, so the plate mesh and the rune paths agree |
| `flutedBack(o)` | options for `A.backplate`: spine keel + fan of creased flutes / ridges fading into the waist, pointed lower edge (`nu`, `nv` + plate options) |
| `mailSkirt(o)` | one half of the split hauberk skirt (hips frame, R side), skinned hips -> thigh by the design |
| `spur(o)` | rowel spur on the heel (foot frame) |
| `crackle(t, seed)` | the arc flicker multiplier (0.82 .. ~2.0) |

### Rig checks (VORN proportions)

* `src/labs/rigqa.js`: the `vorn` body has exactly these proportions; it fails no check that the knight body passes (the
  open failures are shared runtime items the rig team is working on: twist helper steps, pelvis drop, crossfades).
* Grip (`art_vorn` scenario `grip`, off-hand distance to the grip point after settling): `grip` and `choke` 0 mm in the guard,
  thrust, overhead and brace poses; `butt` reachable in the thrust / overhead poses; `head` (+0.78 m) only in close holds.
* Feet (`feetContact`, or `contact` in the roster lab `art.js`): the fitted shared sabaton (`sabaton({ P: rig.P })`) keeps
  the soles 1 mm above the floor in the rest, guard and lunge poses.
* Pauldron lames are rigid but shared between the deltoid helper and the upper-arm twist bone (lower lames follow the
  arm), so the overhead pose does not leave rings floating around the shoulder.

### Lab

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

### Known issues (art)

* The rig's new cloth check reports `surcoatF` / `tailL` / `tailR` particles resting inside the torso, pelvis and thigh
  capsules in the bind pose (masked per particle). Same counts with the old flat offsets (12/8, 11/10, 10/11), so it is
  not caused by the pleats; the hip-pinned tails sit inside the pelvis capsule by design. The rig also adds default
  head / neck capsules for cloth: VORN could declare his own (`colliders`), left to the rig team's guidance.
* Silhouette: in pure side profile the left pauldron fins are hidden behind the torso (VORN reads there by the horned,
  feathered crown, the spear and the streaming tails); the fins carry the shoulder in front and 3/4 views.
* The helm, fin and feather runes still use `arcRune` (raised strips); the six body runes are the engraved ones.

### Requests to other teams (art)

* Rig: call `design.attach?.(char)` in `createCharacter`, and pass `ctx.quality` as the 4th `build` argument (VORN's
  `build(kit, S, rig, quality)` already switches to the light variant on `quality.tier === 'low'`).
* Rig: a `customDepthMaterial` with the cut-out discard for the `cloth` slot (torn surcoat hems cast full-quad shadows).
* Game: generic / shared clips should be played with `{ scale: char.bodyScale }` on VORN (positions authored for the
  1.04 m pelvis); VORN's own clips are authored at his proportions and play at scale 1.
