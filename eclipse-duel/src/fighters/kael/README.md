# KAEL 카엘 — 잿불의 집행자 · Cinder Warden

Two-handed greatsword, element `ember`. Slow, enormous arcs, hyper-armour on the heavies. Palette: magma core → ember
orange → black smoke. Design brief and storyboard: `src/fighters/MOVES.md`; frame data and markers:
`src/fighters/BALANCE.md` §§ 7–9 and `./moves.js`.

| file | what | owner |
|---|---|---|
| `index.js` | the fighter module `{ id, element, design, def, clips, present }`; imports `./clips/index.js` and maps every registered `kael.*` clip | content |
| `clips/` | the motion library (29 clips + 5 poses, `clips/NAMES.md`) | content |
| `present.js` | choreography of every move, the projectiles, the ultimate's lock direction, fighter-wide hooks | content |
| `fx.js` | Kael's signature presets (`kael.*`) and their particle definitions (module scope, compiled in `present.setup`) | content |
| `design.js` | 염무강's look: the Blender asset `assets/chars/kael` (+ rig data, materials, springs, glow) — section *Look* below | art |
| `kit.js` | the earlier kit-built pieces (unused by the design since the Blender asset) | art |
| `moves.js` | rules definition (balance team) | balance |

## Look — 염무강 炎武剛 (Blender asset)

MURIM.md: a broad, heavy master of the Red Sun Gate. Modelled entirely by code in headless Blender
(`tools/blender/heroes/kael.py` + `kael_parts.py` (mask, pauldron, saber) + `kael_lib.py` (SDF tools, garment helpers),
library `tools/blender/edlib`) on the exported game rig `tools/blender/rigs/kael.json`; loaded by `design.js` through
`src/char/assets.js`. **Proportions, bones, sockets, colliders, weapon length / grips are unchanged** (the design keeps
them verbatim; the saber is built on `WEAPON_SPECS.greatsword`: ring end −0.334, point 1.6, grips 0 / −0.17 / −0.27 /
0.17 / 0.56, base 0.12).

| part (EDM) | slot | tris | what |
|---|---|---|---|
| `body` | gear | 4.9k | SDF anatomical body (heavy build), culled to what shows: open chest with three raised sword scars (`scar` look), hands |
| `boots` | gear | 4.1k | leather uppers over the feet, turned cuffs, two strapped bronze buckles, thick soles |
| `bracers` | gear | 4.0k | moulded leather shells over the wraps, rolled rims, 3 x 5 domed bronze studs, laced inner seam (rigid on `foreArmTwist*`) |
| `armour` | gear | 9.9k | the 귀면 iron demon half-mask (facetted shell, prism brows with flame tufts, cheekbones with a hard ridge, flat-sided nose, snarl lip, carved wrinkles / frown furrows, swept horns, bone fangs, ember eyes) + the beast-face pauldron on `deltoidR` (snarling guardian, faceted flame-tongue mane, back ruff, bronze ring in the jaws, saber cradle carved from the idle / walk blade path) — baked maps `kael_gear_n` / `kael_gear_m` |
| `hairHard` | gear | 1.3k | hair cap, topknot (상투) with red cord tie and bronze pin |
| `robe` | cloth | 19.7k | open charred-black coat (red facing + flame brocade trim, Red Sun emblem on the back, red lining), sleeves, red inner sleeves with cuffs, hemp chest bands, pauldron strap + boss, triple-wound crimson sash + tied knot, forearm / palm wraps, banded rust-red face scarf, headband + knot, hemp trousers |
| `tailFL/FR` | cloth | 1.05k each | front coat tails (Blender cloth drape, skinned to hips / thighs) |
| `tailBL/BR` | cloth (`cloth`) | 1.25k each | back coat tails: runtime verlet panels (4 x 8) from the drape |
| `sashEnds`, `bandTails` | cloth | 0.9k / 0.2k | sash ends on springs `sashA/B`, headband tails on `band` |
| `mane` | hair (cutout) | 3.4k | 39 strand locks over springs `maneA/B/C` |
| `saber`, `strip` | blade | 6.3k / 0.2k | 참마대도: faceted blade (wide honed bevel, chamfered spine, clip point / false edge), blood groove with an ember seam, charred spine, bronze collar with flame tongues, lobed iron guard + bronze rims, oval hilt with a two-cord diamond wrap and ferrules, ring pommel with flame spurs; red strip on `strip` |

**Total 59.6k triangles, 4 draw calls** (gear, cloth, hair, blade).

**Materials** (Blender looks, linear, `kael.py` `LK`; retune in JS with `LOOKS` in design.js): `coat` damask black silk,
`lining` / `robe` deep-red silk, `trim` flame brocade (gold thread), `sash` / `strip` crimson silk, `trousers` /
`wrap` / `band` / `scarf` hemp, `leather` / `leatherDark`, `bronze` (verdigris damped in the slot materials: `AGED`),
`iron` / `ironDark` scorched iron, `fang` old bone, `hair`, `steel` blade, `groove` (ember seam), `saberBack`, `skin`,
`scar`, `eye`, `pit`.

**Glow** (`kael.glow`, `attach()` returns `char.glow`): `inlay` = brocade embroidery + the saber's blood-groove seam +
a few thin cracks on the mask and pauldron; `vein` = hot patches of the scorched iron (mask, pauldron) and the saber
spine; `eye` = mask and pauldron eyes. Per-vertex masks come from the asset (`ed_glow`).

**Springs / cloth:** `maneA/B/C` (3 x 3 bones), `band` (2), `sashA/B` (3 each), `strip` (saber) in `design.js`;
cloth panels `tailBL` / `tailBR` from `assetCloth(kaelAsset)`; colliders unchanged (+ `head` / `neck`, which clips do
not read).

**Rebuild:** `tools/blender/bl.sh tools/blender/heroes/kael.py` (~2.5 min, previews in `shots/blender/kael/`);
`--no-preview` (asset only, ~2 min), `--stage 1|2|3` (block-out / garments / high-poly sheet, then exit),
`--only mask|pauldron|saber` (close-up sheet of one piece), `--pose idle` (sheets in a sampled game pose). Re-export
the rig first if springs / panels change (`node tools/blender/export_rig.mjs`, or `tools/blender/build_assets.sh kael`).
Engine review: `node tools/shot.mjs kael_asset --do "__ED.lab.play('bust')" ...` (scenarios in `src/labs/kael_asset.js`),
game: `node tools/shot.mjs game --as bl-kael --hash "training=kael,iska&seed=7" ...`.

**Numbers** (high tier, this machine): asset 2.12 MB (1.59 MB geometry, 0.54 MB maps; page `build/bl-kael.html`
7.5 MB); header decode 1.4 ms, part decode 15–19 ms, a second Kael builds in 49 ms; the first Kael of a page takes
~600 ms, dominated by the kit's one-time texture-set generation (not split out); `char.update` median 0.3–0.4 ms
(p90 0.4–0.7) in idle / walk / light1; low tier 0.3 ms; 3 create / dispose cycles leave geometries, textures and
programs unchanged.

**Roster review (art direction pass, 2026-11-14).** The "broken chrome" on the mask and the pauldron was not the
material: the baked atlas reached one side of every UV seam with the other island's texels (fixed in
`src/char/assets.js`, see tools/blender/README.md section 8); both now read as matte, fire-blackened iron with the
baked relief and ember cracks. JS retunes in `design.js` (no Blender rebuild): `LOOKS` iron / ironDark (rough 0.8 /
0.84, metal 0.55 / 0.5), saberBack, hair (ink black, rough 0.7), skin (darker, weathered, rough 0.68), scar, scarf
(rust red, brighter); gear material env 0.6, polish 0.1, edge wear 0.22 with a dark bare-metal colour (bronze and iron
edges no longer flash white); hair material env 0.12, strand anisotropy 0.1 and a dimmer rim (`RIM_HAIR`): the mane was
silver-grey. `attach(char)` without a quality (the game) now reads the tier from the cloth grid, so the low tier
skips the maps in the game too. Numbers unchanged: 59,621 triangles, 4 draw calls, 2.12 MB; `char.update` 0.39 ms
median (art lab `cpu`, 240 frames x 5); dispose clean (12 / 22 / 17). Captures: `shots/blender/review/`.

**Known issues:** the face scarf's band
relief reads only up close; the back tails' rest grid sits a little inside the pelvis / thigh capsules (runtime
warning, harmless: the particles settle at the capsule surface).

## Wiring

`index.js` imports `./clips/index.js` (which registers every clip and pose) and builds the state / move → clip map
with `clips({ hasClip })`: a slot is mapped only when its clip is registered (anything missing falls back to the
generic clip), strikes as `{ clip, hit }` with `hit` = the clip's first `impact` / `hit` event (the clips are authored
on the move clock, so the retime is the identity). `__ED.game.roster()` reports
`{ id: 'kael', design: 'index', def: 'index', stub: false }`.

## Clips (clips/NAMES.md has the full table)

- **Poses:** `kael.stance` (blade resting on the right pauldron, both hands on the grip, wide left-foot-forward
  crouch), `kael.l1end`, `kael.l2end` (chain links), `kael.block`, `kael.planted`, `kael.vigil`.
- **Locomotion:** `kael.idle` (2.8 s breathing loop), `kael.walkF` / `kael.walkB` (root motion exactly
  walkSpeed 2.1 / backSpeed 1.55 m/s, planted feet), `kael.dash`, `kael.backstep`, `kael.dodge`, `kael.guard`.
- **Moves (clip time = move time):** `kael.light1` 0.14, `kael.light2` 0.13, `kael.light3` 0.24, `kael.sweep` 0.32,
  `kael.lunge` 0.26, `kael.vent` 0.22, `kael.crescent` 0.28, `kael.eruption` 0.40, `kael.bulwark`,
  `kael.bulwark_burst` 0.05, `kael.pyre` 0.85 (first impact times = first active frames).
- **Ultimate lock beats:** `kael.ult.cuts` (lock 0.10), `kael.ult.hurl` (0.95), `kael.ult.leapAfter` (1.80),
  `kael.ult.spin` (2.40), `kael.ult.meteor` (2.70), `kael.ult.rise` (4.20, ends in the stance at 5.20).
- **Ceremony / reactions:** `kael.intro`, `kael.victory`, `kael.defeat`, `kael.hitLight`, `kael.hitHeavy`.

Every clip starts from and returns to `kael.stance`; rules travel (light2 / light3 / lunge / dash / backstep / the
pyre leap) is keyed as clip root motion so the feet stay planted while the rules slide the root.

## Choreography per move (present.js)

Every move uses the ember library trail (`ember.trail`, glows → cools into smoky tail, sheds embers) on the moves.js
`trailOn` / `trailOff` markers instead of the generic ribbon; every `end` (cancel, interrupt, round end) stops
whatever the move left running.

**Hit feel.** The heavy hits (Cinder Drop, Furnace Sweep, Molten Lunge, Vent Launcher, the crescent wave) replace the
generic hit feel with `hitFeel()`: the same beats (library hit preset, flinch, body flash, shake, kick, chroma, sound,
the strike's hit-stop, result-screen stats and combo counter) at a tempered intensity. The generic star flash at
~0.95 intensity stacked with an ember slash frozen at peak heat during the hit-stop washed the frame white. A KO hit
keeps the generic feel. Kael's ember accent flower (`kael.flower`, accent mode: no flash / star / light) is layered on
every hit.

| move | WIND-UP | RELEASE | IMPACT | AFTERMATH / SETTLE |
|---|---|---|---|---|
| light1 재가르기 Ash Cleave | blade glow | `ember.slash` diagonal down-right (0.32) + trail | accent flower along the cut | ember drip off the tip |
| light2 역날베기 Back Edge | — | rising backhand `ember.slash` (0.3), trail continues the arc | accent flower | — |
| light3 잿불내려찍기 Cinder Drop | blade glow + tip flare | overhead `ember.slash` (0.32) | `kael.bite` at 1.65 m (magma crack, molten spray, dust, light), floor pulse; tempered knockdown hit | `kael.ashfall` |
| heavy 용광로 휘두르기 Furnace Sweep | armour cracks blaze (hyper-armour tell: `kael.shell` lite) | 300° flat `ember.slash` (0.3), fov kick | wall of sparks, shock distortion, fire ring; tempered hit + kick | ashfall |
| f+heavy 돌진 찌르기 Molten Lunge | body glow | magma streak ribbon on the hips, dash dust, focus speedlines; thrust streak + spear sparks, push-in kick | tempered crumple hit | streak cleanup |
| d+heavy 분화 올려베기 Vent Launcher | blade glow | own magma crack + spit at `split`; rising `ember.slash` | `kael.geyser` 0.05 s after the hit (after the hit-stop, never stacked with the flash); tempered launch hit | — |
| skill1 잿불 초승달 Ember Crescent | `kael.groove` (molten groove + scraping sparks following the dragged tip) | rising slash, floor spit; `ember.wave` projectile (library body) + launch flare / fire ring | flower + scorch decal, 0.12 hit-stop, shake 0.3, tempered heavy hit | — |
| skill2 균열 분출 Fault Eruption | blade glow, ember rune + glow decal, `ember.aura` | `kael.bite` k 1.15, fov kick, floor pulse | `kael.fault` racing fissure (5.4 m at 18.75 m/s); 4 `kael.column`s timed from the projectile delays (crack spits 0.04 s before each column); ground-skim camera 4.5–4.9 m off the line, slowmo 0.6 for 0.42 s; juggle hits with a monochrome impact frame on the first only | dust + cinders on `recover` |
| skill3 화염 갑주 Pyre Bulwark | `kael.bite` k 0.4 as the blade is planted | `kael.shell` (flame tongues, cracks, orbiting motes, heat ring, halo, light) | counter: white-hot body flash, monochrome impact frame, chroma, shake 0.5; `bulwark_burst`: crash-zoom onto Kael (0.25 s), `ember.explosion`, 360° fire ring, ashfall, floor pulse | whiff: `kael.shed` (shell falls away harmlessly) |
| ult opener (pyre, move clock) | super-freeze: `kael.updraft` + `kael.corona`, rune; `ignite` white-hot blade + star | `leap`: ULT card dissolves, wide side orbit cut, speedlines, afterimages, magma streak; `release`: `ember.slash.heavy` | (lock below) | whiff: `kael.bite` + `kael.geyser` at the landing |

Projectiles: `ember.wave` (crescent) keeps the library body; `ember.column` (eruption) owns its spawn timing.
Fighter-wide: ambient ember drip from the armour cracks + a few embers rising off the shoulders; intro (planted blade
wrenched free in a floor bite), victory (aura + ashfall), KO flourish (flower + ashfall).

## The ultimate — 일식의 장작 Pyre of the Black Sun (as implemented)

Lock clock: storyboard t = 1.00 + lock t (BALANCE.md § 7). Victim held 1.7 m in front; mood darken 0.75 tint 0xff5020.

| storyboard t | lock t | shot (camera) | Kael clip | VFX / post |
|---|---|---|---|---|
| 0.00 | (move 0) | engine hero push-in (dutch 5°) + weapon follow | `kael.pyre` (blade raised to the eclipse) | `kael.updraft` (embers sucked up), `kael.corona` on the blade, rune, eclipse flash behind; ULT cut-in card |
| 0.60 | (move 0.6) | cut: wide side orbit −6° → 8°, held | `kael.pyre` leap | ULT card dissolves (0.22 s), speedlines, dash dust, 3 afterimages, magma streak, `ember.slash.heavy` on `release` |
| 1.00 | 0 | impact punch-in on the victim (5.0 → 3.7 m) | — | `combat.hit.crit` 0.3 + flower, monochrome impact frame 0.05 s, flash 0.07, chroma 0.5, radial 0.5, shake 0.6, hit-stop 0.2; the trigger's generic ult hit (crit at full intensity + inverted frame) is replaced by `pyre.hit` → tempered `hitFeel` |
| 1.25 | 0.25 / 0.40 / 0.55 | cut: orbit sweep −40° → 30° (70°) around both, handheld | `kael.ult.cuts` at 0.10 | 3 × `ember.slash` in an X + flower, 0.06 hit-stop each, chroma, trail |
| 2.30 | 1.30 | cut: top-down slam view (6.8 → 6.0 m) | `kael.ult.hurl` at 0.95 | crack + glow under the victim from 0.95 (anticipation), spit at 1.18; `kael.geyser` k 1.1, heavy hit, launch, hit-stop 0.1 |
| 2.80 | 1.80 | cut: ground-level skim looking up, slowmo 0.3 | `kael.ult.leapAfter` | sky to crimson (darken 0.86), `kael.inferno` (rune, ring, 4 pillars behind, firestorm, smoke ceiling; no centre detonation), afterimages |
| 3.40 | 2.40 | (same shot) | `kael.ult.spin` | `kael.ringOfFire`, afterimages, huge trail |
| 3.74 | 2.74 | cut: crash zoom from far (14 → 7.6 m) | `kael.ult.meteor` at 2.70 | floor glow under the pair, speedlines, magma streak |
| 3.90 | 2.90 | (crash zoom lands) | meteor slam | `kael.crater` (flash, star, short fire splash, cracks + scorch, fire / dust rings, radial sparks, debris, rolling smoke, ash), monochrome impact frame, flash 0.08, chroma, radial, shake 0.8, hit-stop 0.14 |
| 4.30 | 3.30 | cut: wide establishing (11.5 → 12.5 m) | (meteor hold) | `kael.shockwave` (fire / dust / shock rings across the arena, distortion, 5 pillars behind), exposure pulse, letterbox out, generic shake 1.0 + `ult_impact` |
| 5.20 | 4.20 | blend back to the fight camera (1.0 s) | `kael.ult.rise` (stance at 5.20) | lingering embers (3 s), ashfall + smoke |

Deviations from the storyboard, on purpose: the crash-zoom cut comes at lock 2.74 (storyboard 3.74) so the meteor's
descent reads before the 3.90 impact; the opener's chroma 1 / radial 0.8 are tempered to 0.5 / 0.5 and its impact
frame is monochrome only (no inverted white frame); the finish's presentation hit-stop is 0.14 s (the rules hold
the bodies 0.22 s); the library `ember.meteor` / `ember.inferno` were replaced by `kael.crater` / `kael.inferno`
(their lit magma spikes read as pale cones under the ult's orange key light, and the inferno's 8 m centre
detonation buried the rise).

## Review method (director pass)

In-game, private builds (`tools/build.mjs game --as kael-dir<N>`), 640×360 contact sheets, all read:
`FIGHTERS=kael src/game/tests/moves.mjs` (every slot: wind-up / first active frame / follow-through), the full
ultimate as P1 (28 frames on every storyboard beat) and mirrored as P2, a `#demo` AI match Kael vs Vorn (1–29 s),
and a forced counter hit. No page errors, no exceptions, no `[ed] … threw` lines in any run. Sheets:
`shots/kael/dir/moves_sheet.png` (every slot, before the hit-feel pass), `shots/kael/dir2/moves_sheet.png` (heavy
slots after it), `shots/kael/dir2/ult_sheet.png` (dense P1 ultimate, before the opener fix), `shots/kael/dir3/ult_sheet.png`
(P1 + mirrored P2 ultimate + demo match), `shots/kael/dir4/c_sheet.png` (counter), `shots/kael/dir5/ult_sheet.png`
(final build smoke).

## Performance

`src/game/tests/profile.mjs`, q=high, 640×360, measured at load average ~20–25 on a shared 4-core box (JS ms are
inflated by contention; GPU time is meaningless under SwiftShader):

| phase | draw calls avg / peak | triangles avg / peak | JS ms avg | CHAR ms | VFX ms | GAME ms |
|---|---|---|---|---|---|---|
| fight (120 frames, hard AI, Kael vs Iska) | 43 / 47 | 346k / 353k | 5.4 | 4.3 | 0.55 | 0.39 |
| ultimate (420 frames, whole lock) | 50 / 61 | 403k / 505k | 4.6 | 3.9 | 0.34 | 0.11 |

Budgets (CONTRACT.md, high): draw calls ≤ 160 — met with a wide margin; Kael's character 59.4k triangles / 4 draw
calls (≤ 60k / 6) — met; shader programs 49 before and after the ultimate (nothing compiles mid-fight). **Triangles
exceed the 350k scene budget during the ultimate** (peak 505k incl. the shadow pass, down from 575k before this pass;
the plain fight already runs at 346k): the mesh FX (pillars, rings, debris) add up to ~160k at the shockwave. After
the measurement the shockwave pillars went 5 → 4, the firestorm pillars 4 → 3 and the crater rock debris 14 → 10 (not
re-profiled). Whether mesh FX render into the shadow pass is a VFX / integration question. JS per frame (4.6 ms
average under load ~27, CHAR dominant) needs re-measuring on a quiet machine against the 4 ms desktop budget; the
VFX (0.34 ms) and presentation (GAME 0.11 ms) groups are small.

Kael's presets use only the pooled primitives (instanced particles, mesh FX, pooled lights); every particle definition
is module scope and compiled in `present.setup` before prewarm, so nothing compiles mid-fight.

## Known issues

- **Hit feel is owned locally for the heavy moves** (`hitFeel()`): the generic layer (`src/game/feel.js`) plays the
  library hit at ~0.95 intensity and an *inverted* impact frame on counters / finishers / ult hits, which renders as a
  near-white frame over the dark arena. Kael tempers both for his moves (and for counters on light1 / light2 via
  `on.hit`); the integration team should consider monochrome-only impact frames and a lower default for every fighter.
- **ULT cut-in card**: the hud card runs a fixed 1.9 s from the super-freeze and sat over the 1.00 punch-in and the X
  cuts. `fadeUltCard()` fades its `.an-fit` wrapper on the 0.60 cut (a DOM workaround; a hud option or a card that
  ends with the freeze would be cleaner).
- **Brightness at the hit-stops** is now readable but still hot on: the ult punch-in (lock 0.04–0.2, by design a
  white-flash beat), the Fault Eruption columns (a wall of fire around the juggled victim), the sweep's 300° trail.
- **Animation (from the animator's audit)**: 5–16 cm residual self-intersections on a few frames (pyre right arm vs
  helm, lunge forearm vs helm in the thrust hold, bulwark re-grip, defeat, dash blade vs upper arm, sweep coil);
  back-foot dorsiflexion 16–29° past the 30° limit in deep crouches; feet dip 2–6 cm for single frames on the pyre
  landing, lunge, defeat, leapAfter; `kael.ult.spin` carries the blade ~33° off flat (the VFX ring of fire is placed
  in the camera plane, so it only shows in the blade itself).
- **Hand-placed data**: the lunge foot landings and light2's 0.25 m step are keyed by hand; the pyre / lunge / light3
  root keys come from moves.js motion data. If balance changes those motions, the foot keys need a matching touch.
- **Rig / design warnings** printed at load (not ours to fix): "kael: the design has a weapon but no gripAngle" and
  "cloth but no head / neck collider: default capsule(s) added" (design.js, art team).
- **Mirror match**: per-slot state (`S[h.index]`) keeps two Kaels apart; not captured in this pass.
