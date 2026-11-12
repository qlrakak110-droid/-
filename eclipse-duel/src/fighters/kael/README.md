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
| `design.js`, `kit.js` | armour, greatsword, half-cape (art team) | art |
| `moves.js` | rules definition (balance team) | balance |

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
| 1.00 | 0 | impact punch-in on the victim (5.0 → 3.7 m) | — | `combat.hit.crit` 0.35 + flower, monochrome impact frame 0.05 s, flash 0.14, chroma 0.5, radial 0.5, shake 0.6, hit-stop 0.2 |
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

## Performance

See the report numbers in the section below (profile.mjs, ultimate peak, q=high).

## Known issues

See the end of this file (kept current by the director pass).
