# PLAN_V2 — Implementation plan for 「존재와 공허 — 하늘의 기억」

> Companion to `docs/DESIGN_V2.md` (the canonical design, in Korean). This document turns that design into work for **8 parallel AI agents** on the existing codebase: milestones, waves, exclusive file ownership, frozen shared interfaces, save migration, acceptance criteria with headless-harness scenarios, per-tier budgets and risks.
> Section references written `D§n` point into DESIGN_V2.

---

## 0. How to use this plan

* The **lead** runs Wave 0 alone, then starts 8 agents per wave with the ownership table of that wave (§4). Each agent receives: this plan, DESIGN_V2, the polish brief conventions (one owner per file, no commits, no edits to other files), and its stream card (§4.3–§4.5).
* Every interface in §5 exists as a **stub with the correct return shape** at the end of Wave 0. Agents code against the stubs; owners replace them with real implementations. Changing a frozen signature needs the lead's approval and an edit to §5.
* Every milestone (§3) ends in a **shippable build**: title → act 1 → as far as the content goes, with all common regressions green (§7.4). Nothing is merged that breaks act 1.

---

## 1. Starting point

### 1.1 What exists (measured 2026-11-07, while the polish pass was still running)

| File | Lines | What it holds | Shared names other files use |
|---|---|---|---|
| `00_core.js` | 1204 | renderer, composer (GTAO → bloom → final pass), `Post`, `applyQuality`, `renderScene`, `Time`/`hitStop`, `Tw`, toon helpers `M`/`E`/`patchToon`, `voidMat`, outlines, `GEO`, `Particles`, `Input`, `Snd`, `SONGS` | `Settings{high,ultra,sound}`, `isTouch`, `mulberry32`, `vnoise`, `fbm`, `Shared.time`, `Cams` |
| `00b_assets.js` | 103 | **in-flight, uncommitted** glTF/PBR asset library (`GLTFLoader`, `Assets.loadAll`) | `Assets`, `assetTex`, `pbrSet`, `triplanarPBR` — consumed only by `05_game.js` boot and `window.__game` |
| `01_data.js` | 204 | `TYPES`(10), `CHART`, `typeEff`, `TYPE_ICON`, `MOVES`(45), `SPECIES`(20), `ITEMS`, stat math, `makeMon`, `POOLS`, `rollPool` | all |
| `02_models.js` | 641 | `newRig`, `rigUpdate`, `makeSpiritModel`, `Icons`, SD person toon builder | 03, 04, 05 |
| `02b_sculpt.js` | 182 | `SDF`, `sculptMesh(prims, bounds, cell)` (dense grid + surface nets), `spinePath` | 02d, 02f, 02g |
| `02c`–`02e` | 917 | dragon designs, `dragonGeometry(key, design, cellHi, cellLo)`, `dragonMaterial`, wings, `envFromSky`, `animeEye`, `sculptOutline`, six legends | 02f, 02g, 04 |
| `02f_critters.js` | 848 | `critterEye`, `critterSkin`, `paintCritter`, `critterKit`, `buildCritter`, 13 critter designs | 02_models |
| `02g_people.js` | 142 | `designPersonBody`, `designHair`, `clothRibbon`, `buildPerson` (≈2.8-head SD people) | 03, 05 |
| `03_world.js` | 1112 | `SITES`, `ZONES`, `heightAt`, `World`, `groundY`, `buildWorld`, `ATMOS`/`applyAtmos`, `updateWorld`, legend sites, NPC placement | 05 |
| `03b_town.js` / `03c_nature.js` | 467 / 240 | `StaticKit` merge tool, town, `Puffs`, nature kit, polish hooks `build/updateTownExtras`, `build/updateNatureExtras` | 03 |
| `04_battle.js` | 1059 | `Battle`, arenas `THEMES`, `playFx` (17 FX), `calcDamage`, `aiPick`, `useMove` (rules **and** presentation mixed), `throwCrystal`, `runBattle`, exp, evolution | 05 |
| `05_game.js` | 928 | `SAVE_KEY 'void-being-save-v1'`, `S`, `save`/`loadSave`, `G.encDist/encNext` (step encounters), dialogue, `NPC_DEFS`, story, `battleFlow`, menus, `frame`, `boot`, `window.__game` | harness |
| `template.html` | — | HUD/DOM/CSS, importmap (`three@0.160.0`), **Google Fonts `<link>` (lines 3–5)**, `/* battle-polish */` CSS block | — |

Outside `src/`: `build.py` (concatenates `src/*.js` in name order into one ES module inside `index.html`), and **untracked** `assets/` (`*.glb`, `*.jpg`, `*.png`) and `tools/blender`, `tools/tex` (offline asset pipeline). The screenshot harness (`shot.js`, `check.sh`, ~40 `scen_*.js`) currently lives in the session scratchpad.

### 1.2 A polish pass is still editing `src/` — start from whatever lands

Wave 0 does not start until the polish workflow has committed its final checkpoint and no agent is writing `src/`. Then the lead **rebaselines**:

1. `git log` shows the polish checkpoints closed; `git status` clean for `src/`.
2. Run the existing scenario set (`smoke`, `story`, `zoo`, `battle`, `town`, `mobile_smoke`, `LOW=1 smoke`) → each `ERRORS: none`. A failure here is fixed before anything else.
3. Capture the **act-1 regression baseline**: `scen_regress_look` (village plaza at dusk, east rift, altar, field battle) → `harness/baseline/regress_look.json` (`probe` mean luminance, mean saturation, 8-bin histogram per shot). Capture `scen_creatures_act1` (13 critters contact sheet) and `scen_dragons_sheet` (6 legends) baselines too.
4. **Signature inventory**: for every name in §5.8, grep that it still exists with the same parameters. If the polish pass renamed or split something, the lead updates §5 *before* Wave 1 and notes it in `docs/HOOKS.md`.
5. Keep every hook the polish pass added (`buildTownExtras`, `updateNatureExtras`, the battle-polish CSS block …).

### 1.3 Rule violations removed first (Wave 0)

| Violation | Fix |
|---|---|
| Offline asset pipeline: `src/00b_assets.js` (GLTFLoader), `Assets.loadAll` in `boot()`, `assets/`, `tools/blender`, `tools/tex` | **KEEP (lead decision, overrides the judges).** The user explicitly asked us to author our own assets ("정 안되면 니가 직접 에셋들 만들어서 활용해"). Assets made by our own reproducible scripts in `tools/` are first-party, not external downloads. Rules: every consumer keeps a procedural fallback (file:// or missing files → null), per-workstream size budgets, phones load the `_512` variants, no files downloaded from the internet. |
| Google Fonts in `template.html` (`fonts.googleapis.com`, `fonts.gstatic.com`) | Remove the three `<link>` lines; CSS variables `--f-ui` / `--f-display` with system stacks (D§15.1); the title logo becomes an inline SVG path. |
| Nothing enforces the rules | `build.py --check` (§5.1) fails the build on duplicate top-level identifiers, on any external URL other than `https://cdn.jsdelivr.net/npm/three@0.160.0/`, and on `</script` in the bundle. The harness fails any scenario that requests another host (§7.2). |

---

## 2. Rules of engagement

1. **One file, one owner per wave.** The ownership table is re-issued at the start of every wave (§4). Never edit, revert or "fix" a file you do not own; report the problem instead.
2. **Cross-file needs go through**: (a) Bus events (§5.3), (b) registries (§5.4), (c) frozen function signatures (§5.6, §5.8), (d) a **hook request** row in `docs/HOOKS.md` (`requester · file · wanted change · reason · status`). The owner implements requests inside the same wave; the lead arbitrates.
3. **No top-level cross-file calls.** All files share one module scope; function declarations hoist, but top-level `const/let/class` exist only after their file ran. Top level only *defines*; everything is constructed in `boot()` or lazily. GLSL chunks cross files only through functions (`Atmos.chunk.obl()`).
4. **New behaviour is opt-in with old defaults** until its milestone gate passes (`Battle.v2`, `Eco.enabled`, `World.playerV2`, LD features per asset). Act 1 must keep working at every commit.
5. **Determinism.** Rules, ecology decisions, capture, field paint and AI draw from `RNG.stream(name)` (§5.5). `Math.random` only for decoration. Every real-time input has a deterministic path (`autoTiming`, `Flight.autopilot`, `Capture.auto`).
6. **Own your tests.** Each stream adds `tests/t_<stream>.mjs` and `harness/scen_<stream>_<topic>.js`, writes shots to `harness/shots_<stream>/`. Shared scenarios belong to the lead.
7. **Verification before reporting**: `harness/check.sh <own files>` → `BUNDLE OK` and `CHECK OK`; `node tests/run.mjs <stream>` → pass; own scenarios once with fixed seed/tier/tod → `ERRORS: none` and auto criteria met. Report = what changed in player terms, 2–4 shots, any Bus/registry/hook changes.
8. **No commits, pushes or resets by agents.** The lead commits at milestone gates.
9. **No new globals outside your prefix** (§5.1). No `new THREE.Vector3()` inside per-frame loops. Anything expensive is gated by `Q.f` (tier features), never by ad-hoc `isTouch` checks.

---

## 3. Milestones

Three waves, two milestones each. Every milestone is a shippable, verified build.

| M | Name | Wave | Player-visible content | Ships when |
|---|---|---|---|---|
| **M0** | Foundation | W1 (checkpoint) | None new — act 1 looks and plays exactly as before, on new plumbing: save v2, Region facade, 4 quality tiers + auto-detect + DRS, sculpt v2 (drop-in), rules engine (behind `Battle.v2=false`), no external requests | §20-style interfaces all real or stubbed; `scen_game_migrate`; `scen_regress_look` within ±8 % meanL / ±10 % meanSat; `scen_creatures_act1` within ±5 %; `scen_ext_requests` = 0; `scen_render_tiers` budgets; node `t_data`, `t_save`, `t_rules` (parity) pass; `scen_lookdev_sculpt` (Worker = sync = cache, `failWorker` still builds); `scen_people_walk` foot slide < 0.03u |
| **M1** | Act 1 on the new rules + first flight | W1 (end) | **Resonance turns** in all act-1 battles (timeline, locked intents, poise/break, attack/guard timing, field + 8 reactions, partner combo, assist options); **visible ecology** on the boundary island (no step encounters, awareness, crouch, ambush, subdue, 4 vignettes); **memory cards** with snapshots + album; hero M/F, 루아, 소하 at 6.8 heads with eye v2 and anime face shading; act 2 chapters 0–1: memory snow → sky pillar → **ascent (load gate)** → open sky (cloud sea, cumulus, rings, updrafts) → glide to **구름나루** (full hub), 소하 + lantern, 이음, 루아 friendly battle; "다음 이야기는 준비 중" marker | node: 10k starter mirror win 45–55 %, 8–14 turns; `autoTiming perfect` vs `off` −30–40 % turns vs a keeper; all W1 scenarios (§4.3) green on desktop + `mobile_` + `LOW=1`; `scen_game_region` memory round-trip ±5 %; common regression |
| **M2** | First trial | W2 (checkpoint) | 천폭섬 (24 falls, rainbow, mirror terraces, crystallized falls), ch 2 (updraft stepping-stone glide, trial 「공중전」, island goals 2/3, **first island rise**, harness + mount flight tiers 1–2, ring tutorial); **skilled capture** (aimed throw, throw timing, resonance pulse, new crystals); **observation** zoom + records; bond tiers widen timing windows; memory moves of the 3 starters; let-go memory respec; 10 sky species; materials fur/feather/paper/crystal-lite; arena `falls`; FX gust/cyclone/ring | W2-M2 scenarios green; `t_capture` ±1 pp; island rise visible (+30u) |
| **M3** | Three engravings | W2 (end) | 회상림, 무채원 (**OBL complete**, lantern circle, note-dropping music), 뇌운첨탑 (storm ring, rain, race, factory); ch 3; trials 「잔상 · 안개 · 뇌운」; **왕도 rises** (18 s set piece); all 21 sky species; **레코르디아 model** finished; 5 abilities + 3 puzzle templates; 「무색」; memory-condition evolutions; rest scene with petting; named cast (여울 · 아린 · 무명/도해 · 카이랑 · 이음 · 필 · 연); FX recall/whiteout | `scen_world_grey` saturation gate; program counts ≤ budget in all 4 islands; W2-M3 scenarios green |
| **M4** | Apex and Eye | W3 (checkpoint) | 잊힌 왕도 / 기억의 정점 (vertical, 72 platforms), 망각의 눈 / 뒤집힌 섬 (descent cinematic, upward falls); ch 4–9; **legend events** 레코르디아, 레테온 (UI erase), 단하 act-2; heart UI; ch 5 「백지」 quiz from save data + ribbon; 이음's choice; ending (memory rain over the boundary island, credits with the player's postcards); starter branch forms (6); 세오람 with crystal reveal | `scen_game_ending` start→credits with `tim=perfect` and no errors; boss scenarios (phase 2, UI erase/restore, no soft-lock); W3-M4 scenarios green |
| **M5** | Finish | W3 (end) | Postgame (festival, rematches, dragon flight, 세오람 atonement, 리미나 dawn), photo mode + 22 postcards, 60 memory fragments, 10 side quests, variants, act-1 people v2, perf/thermal pass, accessibility pass, README | **every** scenario green; real-device checks (§7.5); boot-time targets (§9.4); stress save ≤ 64 KB |

---

## 4. Waves and file ownership

### 4.1 Wave 0 — lead only (≈ 1 day, before any agent starts)

1. Rebaseline (§1.2).
2. Keep the asset pipeline (see §1.3 — user-requested first-party assets); remove Google Fonts (§1.3); add `build.py --check` (§5.1) and make the default build run it.
3. Add to `00_core.js`: `Bus` and `RNG` (§5.3, §5.5) — ~40 lines.
4. Create **every new file** in §4.2 with: an owner header comment, the frozen stubs of §5.6 returning correctly shaped values, and no behaviour. Wire the stubs into `boot()`/`frame()` in the order of §5.2 (calls are no-ops) so later waves never touch `boot()` ordering.
5. `tests/`: `run.mjs` (loads `stub.js` + pure files into a `vm` context, runs `t_*.mjs`), `stub.js` (copies of the pure helpers from `00_core.js`: `clamp lerp smooth rand randi pick mulberry32 hash2 vnoise fbm` + seeded `Math.random`), `t_smoke.mjs`.
6. `harness/`: move `shot.js`, `check.sh` and the existing `scen_*.js` from the scratchpad; add `serve.sh` (static server on :8765), the external-request FAIL, seed init script, `TIER`/`LOW`/`VW`/`VH` env, `baseline/` folder (§7.2).
7. `docs/HOOKS.md` (empty table), ownership block comments in `template.html`: `/* ===== battle ===== */` (BATTLE), `/* ===== gfx-dev ===== */` and `/* ===== photo ===== */` (RENDER), everything else GAME.
8. Commit "Wave 0: foundation stubs" — this is the base all 8 agents branch from.

### 4.2 File map v2 and owners per wave

Build order is file-name order (`_` sorts before letters, so `04_battle.js` < `04a_rules.js` < `04b_…`).

| File | Status | Contents | W1 | W2 | W3 |
|---|---|---|---|---|---|
| `00_core.js` | existing | renderer, composer, `Post`, `Particles` (+`streak`), `Snd`/`SONGS` (+audio-clock scheduling), `Input`, `Bus`, `RNG` | RENDER | RENDER | RENDER |
| `00b_quality.js` | new | `Q` tiers, auto-detect, DRS, 30 fps pacing, budgets, `LODMgr`, `IDB`, `window.__gfx`, dev overlay | RENDER | RENDER | RENDER |
| `00c_atmos.js` | new | `Atmos` (sky LUT, TOD, FOGX/CSHADOW/OBL chunks, wipe, cloud-in), `LightShaft`, `Snap`, `PhotoCap` | RENDER | RENDER | RENDER |
| `01_data.js` | existing | +3 types, chart cells, `normMove`, v2 fields of the 20 act-1 species, items | BATTLE | BATTLE | BATTLE |
| `01b_data_sky.js` | new | 23 new species, 32 moves, new items, 6 starter branch forms | BATTLE | BATTLE | BATTLE |
| `01c_mem_data.js` | new | memory definitions, text templates, memory moves table | GAME | GAME | GAME |
| `01d_eco_data.js` | new | habitats (boundary + act 2), species `eco` fields, vignette definitions | SPIRITS | CREATURES | CREATURES |
| `02_models.js` | existing | rigs, `setPose`, `Icons`, `makeSpiritModel` | SPIRITS | CREATURES | CREATURES |
| `02b_sculpt.js` | existing | sculpt v2 (bricks, parts, det, crease, Taubin) — pure JS | LOOKDEV | LOOKDEV | LOOKDEV |
| `02c_dragon_designs.js` | existing | + `designCrane` | SPIRITS | DRAGONS | DRAGONS |
| `02d_dragons.js` | existing | `dragonGeometry` v2 delegate, wings v2, jewel eye adoption, `setFlight` | SPIRITS | DRAGONS | DRAGONS |
| `02e_legends.js` | existing | legend remasters | SPIRITS | DRAGONS | DRAGONS |
| `02f_critters.js` | existing | 13 act-1 critters, poses, eye upgrades, branch-form overlays | SPIRITS | CREATURES | CREATURES |
| `02g_people.js` | existing | SD people (fallback until v2 is ready) | PEOPLE | PEOPLE | PEOPLE |
| `02h_sky_critters.js` | new | 21 sky species | SPIRITS | CREATURES | CREATURES |
| `02i_sky_legends.js` | new | 레코르디아, 레테온, saddles, boss part sockets | SPIRITS | DRAGONS | DRAGONS |
| `02j_people_v2.js` | new | `PROPORTIONS`, skeleton, body/face generators, auto weights, IK, gait, `POSES`, springs, face/mouth, cast, crowds | PEOPLE | PEOPLE | PEOPLE |
| `02k_lookdev.js` | new | `LD` uber patch, material table, skin/cloth/paper/fur/feather/crystal/stone/ghost, outline v2, ink, face proxy | LOOKDEV | LOOKDEV | LOOKDEV |
| `02l_eyes.js` | new | `makeEye` v2 (person / critter / dragon) | LOOKDEV | LOOKDEV | LOOKDEV |
| `02m_bake.js` | new | bake, Worker, IDB mesh cache, `sculptAsync/Sync`, LOD chain, `Bake` | LOOKDEV | LOOKDEV | LOOKDEV |
| `02n_hair.js` | new | hair locks, ring band, tip backlight, edge cards | PEOPLE | PEOPLE | PEOPLE |
| `03_world.js` | existing | boundary island + `buildBoundaryRegion` adapter + `groundY/heightAt` dispatcher | WORLD | ISLES | ISLES |
| `03b_town.js` · `03c_nature.js` | existing | town (+ glazed-tile parameters), nature kit | WORLD | ISLES | ISLES |
| `03d_sky.js` | new | open-sky region, cloud sea, cumulus, rings, updrafts, flocks, fog banks, cloud-hole | SKY | ISLES | ISLES |
| `03e_islands.js` | new | island generator, `buildIsland`, `islandTop`, `islandMidLOD`, `Isle.raise` | WORLD | ISLES | ISLES |
| `03f_skykit.js` | new | landmark kits (lighthouse, rope bridges, engraving stones, crystal pillars, ruins …) | WORLD | ISLES | ISLES |
| `03g_water.js` | new | `Waterfall`, rivers, terraces, rainbow | SKY | ISLES | ISLES |
| `03h_flight.js` | new | `Flight` (glide, ride, camera, landing, rescue, autopilot) | SKY | ISLES | ISLES |
| `04_battle.js` | existing | **presentation layer**: event player, arenas `THEMES`, `playFx`, ring driving, exp/evolution UI | BATTLE | BATTLE | BATTLE |
| `04a_rules.js` | new | pure rules engine (no DOM/THREE) | BATTLE | BATTLE | BATTLE |
| `04b_battle_fx.js` | new | new FX, phase cut-ins, UI-erase visuals | (stub) | RENDER | RENDER |
| `04c_stages.js` | new | new arenas via `Stages.register` | WORLD | DRAGONS | DRAGONS |
| `04d_battle_ui.js` | new | timeline, intents, poise, resonance, rings, part markers, phone layout | BATTLE | BATTLE | BATTLE |
| `05_game.js` | existing | main loop, dialogue, act-1 story, legacy menus | GAME | GAME | GAME |
| `05b_story2.js` | new | act-2 chapters, `QUESTS`, `MEMFRAG`, `POSTCARDS`, island goals, legend events, side quests | GAME | GAME | GAME |
| `05c_regions.js` | new | `Region`, `REGIONS`, `SaveV2` (load/migrate/validate), ascent gate | GAME | GAME | GAME |
| `05d_menus.js` | new | album, spirit detail v2, map, settings v2 UI, heart UI, whiteout quiz UI, rest scene UI | GAME | GAME | GAME |
| `05e_photo.js` | new | photo mode UI, postcard judging | (stub) | (stub) | RENDER |
| `06_ecology.js` | new | `Eco`, `Habitats` runtime | SPIRITS | CREATURES | CREATURES |
| `07_capture.js` | new | `Capture` (aim, throw, pulse, field capture) | (stub) | BATTLE | BATTLE |
| `08_arts.js` | new | `Arts`, `WorldObj`, prompts, wheel, ghost replays | (stub) | GAME | GAME |
| `09_bond.js` | new | `Bond`, `Mem`, `Memories` (pure core + snapshot glue) | GAME | GAME | GAME |
| `template.html` | existing | DOM/CSS. Blocks: `battle` → BATTLE; `gfx-dev`, `photo` → RENDER; rest → GAME | split | split | split |
| `build.py`, `README.md`, `docs/HOOKS.md` | existing/new | `--check`; docs | GAME (lead edits HOOKS) | GAME | GAME |
| `tests/` · `harness/` | new | runners owned by lead; each stream owns its `t_*` / `scen_*` files | per file | per file | per file |

Wave rosters (always 8): **W1** RENDER · LOOKDEV · PEOPLE · SPIRITS (creatures + dragons + ecology) · SKY · WORLD · BATTLE · GAME. **W2 and W3** RENDER · LOOKDEV · PEOPLE · CREATURES (+ ecology) · DRAGONS (+ arenas) · ISLES (sky + world) · BATTLE (+ capture) · GAME (+ abilities). In W1 the creature/dragon work is light (two new species, sockets, no bulk remaster), which frees a slot to split battle rules/presentation from story/region/save/UI; in W2–W3 the sky and world files merge into ISLES so creatures and dragons can run separately.

### 4.3 Wave 1 stream cards (M0 → M1)

Each card: **M0** deliverables (mid-wave sync), **M1** deliverables, **acceptance** (scenarios in §7.3), **valve** (what slips to the next milestone if late).

**RENDER** — `00_core.js`, `00b_quality.js`, `00c_atmos.js`, template `gfx-dev` block
* M0: `Q` with 4 tiers and the feature table of §9.1; settings v2 + `migrateSettings` (§6.4) with `Settings.high/ultra` kept in sync; `Q.apply()` reproduces today's `applyQuality()` (which becomes a wrapper); auto-detect (signals + 1.5 s hidden bench run after the title is visible); DRS + fixed 30 fps pacing (`Q.frameBegin/End`); `Q.budget()`/`__gfx.budget()`; `LODMgr`; `IDB`; full `window.__gfx` (§7.2); dev overlay (`?dev=1` / F9); `Atmos.U` object and `Atmos.chunk.*` present with identity defaults (old look).
* M1: sky LUT + 4 TOD presets (boundary dawn/day/dusk/night, sky, ferry); FOGX + CSHADOW live in LD materials and on boundary terrain/foliage/houses (regress-safe); cloud wipe (composer `uWipe`; DOM canvas overlay on low) and `cloudIn`; `LightShaft`; `Snap.capture` (offscreen 128² → JPEG blob); `Snd.at(t, name)` audio-clock scheduling, timing SFX (perfect bell C6, guard hex, break glass, resonance chord), songs `sky`, `ferry`, act-2 title arrangement; `Particles` `streak` mode; `Post` presets `sky`, `ferry`.
* Acceptance: `scen_render_tiers`, `scen_render_atmos`, `scen_render_drs`, `scen_regress_look`, `scen_ext_requests`.
* Valve: boundary TOD presets stay on legacy `ATMOS` until M2.

**LOOKDEV** — `02b_sculpt.js`, `02k_lookdev.js`, `02l_eyes.js`, `02m_bake.js`
* M0: brick sculpt v2 **inside** `sculptMesh` (same return fields + `bake`, `mat`, `skin`, `lod`; parity with v1: vertex count ±3 %, act-1 sheets within ±5 %); parts, `det`, `crease`, `sharp`, Taubin, Uint16 indices; bake (`aBake` AO/curvature/thickness/cavity, `aMat`, skin weights from `bone` tags); Worker built from an explicit `SCULPT_SRC` list of self-contained functions with a self-test at init, main-thread time-sliced fallback (6 ms/frame play, 14 ms in wipes); IDB mesh cache (quantised, 80 MB LRU, `SCULPT_VER`); LOD chain; `dragonGeometry(…, {v2:true})` path available; `LD.patch` skeleton with `SCULPT SKIN BAKE MATID FOGX CSHADOW OBL FACE`.
* M1: skin (wrap, terminator red, transmission, colour AO, blush), cloth (sheen, weave micro-normal, seams), paper; `LD.outline` v2 (screen-space width, tinted ink, SkinnedMesh) + crease ink; `makeEye` v2 for people (parallax, iris layers, caustic, cornea cap, physical/anime highlight blend, lid-covers-highlight, wet line, lash cards, saccades, pupil response) and the critter variant API; `LD.faceProxy` (proxy normals + `aFace`; face-shadow threshold map on high/ultra); character rim; `LD.ghost`.
* Acceptance: `scen_lookdev_sculpt`, `scen_lookdev_bake`, `scen_lookdev_eye`, `scen_lookdev_face`, `scen_lookdev_outline`, `scen_lookdev_mats` (skin/cloth/paper subset), `scen_creatures_act1` (parity).
* Valve: face-shadow threshold map and paper → M2.

**PEOPLE** — `02g_people.js`, `02j_people_v2.js`, `02n_hair.js`
* M0: `PROPORTIONS` (D§13.1), `SKELETON_HUMAN_V2` computed from proportions, body generator (25 anatomical masses + outfit inflate + hem rims), auto weights + joint helper prims, 2-bone foot IK, procedural gait; one hero proven on the lookdev stage.
* M1: hero M, hero F (classic + 「바람 여행복」), 루아, 소하 at hero tier; hair locks + ring band + tip backlight + edge cards (0/0/8/12); mouth jamo (6 shapes) + brows (4) + emotion presets; `POSES` (idle, talkA/B, point, bow, cheer, think, ride, glide, fall, land, kneel, crouch, throw, command, observe); springs (scarf, braid, coat); `bustCam(rig, side)`; `World.makePlayer` hook implementation (WORLD calls it behind `World.playerV2`); `addNpc` uses `buildPersonV2` when `def.body` is present (GAME adds the fields).
* Acceptance: `scen_people_cast`, `scen_people_bust`, `scen_people_walk`, `scen_people_talk`, `mobile_people_low`.
* Valve: hero F → M2 (hero M ships first).

**SPIRITS** (creatures + dragons + ecology) — `02_models.js`, `02c`, `02d`, `02e`, `02f`, `02h_sky_critters.js`, `02i_sky_legends.js`, `06_ecology.js`, `01d_eco_data.js`
* M0: `makeSpiritModel(sp, opts)` (optional `opts`), `setPose` no-op safe, `rig.sockets`; `dragonGeometry` v2 delegate (off by default); boundary habitats converted 1:1 from `ZONES`/`POOLS` (data only); `Eco.enabled = false` keeps step encounters for the M0 ship.
* M1: `Eco` on the boundary island (tier spawn radii, 9-state machine D§8.2, awareness D§8.3, crouch noise, start conditions ambush/ambushed/subdue D§8.6, LOD0/1 rigs + LOD2 instanced per species, sleeping rigs update every other frame on low); 4 act-1 vignettes; poses for the 13 act-1 critters (sleep, eat, alert, flee, happy, guard-crouch, break-recoil); `uLook`/`uPupil`/emotion presets in `critterEye`; 깃톨 and 연깃 on the new pipeline (`sculptAsync` + `LD.creature` + `makeEye` critter) with `saddle` on 연깃 and 단하; boundary act-2 habitat with 깃톨.
* Acceptance: `scen_eco_day`, `scen_eco_night`, `scen_eco_encounter`, `scen_creatures_new` (2 species), `scen_creatures_act1`, `mobile_eco_low`, node `t_eco`.
* Valve: 4 vignettes → 2.

**SKY** — `03d_sky.js`, `03g_water.js`, `03h_flight.js`
* M0: minimal `buildOpenSky()` (flat cloud sea + LUT hookup) so GAME can prove `Region.go('sky')` round trips; `cloudSeaH`.
* M1: cloud sea (polar grid, 4u snap, self-shadow, Beer-powder, HG, thickness layers, horizon blend), cumulus impostor clusters, wind rings (2 courses), updraft columns incl. the ferry→falls stepping-stone route, `Flight` (glide equipment; ride tiers 1–2 drivable via `__game.flight.mount`; flight camera with FOV by speed and speed lines; landing rings + E-to-land; take-off; fall rescue; ceiling y 480; oblivion-sea timeout; `autopilot` for ascent and fast travel), 깃톨 flock (instanced, 1 DC), ascent camera path, cloud-hole render target showing the boundary island, 3 mini waterfalls for ferry via `Waterfall.build`.
* Acceptance: `scen_sky_postcard`, `scen_sky_flight`, `scen_sky_cloudin`, node `t_flight`.
* Valve: cloud-hole render target → M2.

**WORLD** — `03_world.js`, `03b_town.js`, `03c_nature.js`, `03e_islands.js`, `03f_skykit.js`, `04c_stages.js`
* M0: `groundY/heightAt` dispatcher (signatures unchanged); `buildBoundaryRegion()` adapter; `Region.adoptBoundary(World)` at the end of `buildWorld()`; act-1-only routines guarded by `Region.id === 'boundary'`; island generator prototype (top heightfield + cliff skirt + underside SDF) and `islandMidLOD` for all 7 islands (placeholder recipes) for SKY.
* M1: **구름나루** complete (D§3.7: five rocks, terraces, rope bridges, glazed-tile houses via `03b` parameters, lighthouse lens + beam with brightness levels, landing ring, kite-workshop street, sky-gate platform, records office, 60 instanced kites + ribbon tails, lantern strings, 3 mini falls); boundary 0장 changes (memory snow particles, sky pillar from the altar beam, 루아 relocation from GAME data); FOGX/CSHADOW on boundary materials (regress-safe); arenas `sky` and `ferryDusk` via `Stages.register`; player rig through `World.makePlayer` behind `World.playerV2`.
* Acceptance: `scen_world_ferry`, `scen_world_midlod`, `scen_world_collide` (ferry), `scen_stages_w1`, `scen_regress_look`.
* Valve: records office interior → M2.

**BATTLE** — `01_data.js`, `01b_data_sky.js`, `04a_rules.js`, `04_battle.js`, `04d_battle_ui.js`, template `battle` block, `tests/t_data.mjs`, `tests/t_rules.mjs`
* M0: 13 types, chart cells, icons; `normMove` for the 45 moves; `04a` skeleton (`create next timeline plan commit endAction aiAction isOver`) with **damage parity** to `calcDamage`; `Battle.v2 = false` keeps the old flow.
* M1: full rules (CTB and weights, locked intents N by kind, poise/break, grades, guard stance, 7 field states + 8 reactions + start conditions, resonance + partner combo + pair table + bond-move data, frost, assist options, `captureChance` in rules with `throwCrystal` as wrapper); `04_battle` becomes the event player (existing `playFx`, `hitReact`, `animHp`, `popAt`, `hitStop`, `Post.shock`, dust kept), timing rings on real time + audio clock, guard ring, partner two-shot, break slow-mo; `04d` timeline (10 PC / 8 phone) with ghost preview, intent badges, poise diamonds, resonance pips, partner card, field icons, phone 2×2 + tap-anywhere timing; `01b` data for 깃톨/연깃 and the 32 moves; `battle:*` events; `Battle.v2 = true` at the M1 gate.
* Acceptance: node `t_data`, `t_rules`; `scen_battle_timeline` (desktop + mobile), `scen_battle_timing`, `scen_battle_break`, `scen_battle_react`, `scen_battle_combo`, existing `scen_battle` + `LOW=1`.
* Valve: reactions limited to 감전 · 증기 · 개임 · 반향 in M1, the other four in M2.

**GAME** — `05_game.js`, `05b_story2.js`, `05c_regions.js`, `05d_menus.js`, `09_bond.js`, `01c_mem_data.js`, template (non-battle, non-gfx blocks), `build.py`, `README.md`
* M0: `SaveV2` (load/migrate/validate/save; v1 key read-only) + settings link to `Q`; `Region` (`init go adoptBoundary track pump preload state onEnter onLeave current`) with wipes via `Atmos.wipe`; round trip boundary ↔ minimal sky; `boot()`/`frame()` order of §5.2; system font stack + SVG logo; README.
* M1: step encounters retired (`onPlayerMoved` stops rolling when `Eco.enabled`); `Bond` + `Mem` core with 10 memories (`first_meet first_win first_flight first_evo protect_night guard_shield endure home legend_seen rest_night`; `isle_lit`, `farewell`, `ribbon` defined dormant), snapshots through `Snap` → `IDB`, faded fallback; album tab + spirit detail v2 (bond bar, tier, cards; lean bar hidden in act 1); toasts; **story ch 0–1** (D§3.5, D§14.1) incl. ascent with gate (`Region.go('sky')` during the cloud tunnel), title card, glide landing, 소하 (바람샘 heal + lantern key), 이음, 루아 friendly battle; act-1 text fixes and foreshadow lines (D§3.3); flight HUD + phone flight controls; title screen act-2 variant; end-of-content marker; map v1 (stops, regions).
* Acceptance: `scen_game_migrate`, `scen_game_region`, `scen_game_gate`, `scen_game_ch01`, `scen_game_flighthud` (desktop + mobile), `scen_game_album` (+ `failIDB`), `scen_ext_requests`, node `t_save`, `t_bond`.
* Valve: map v1 → M2.

### 4.4 Wave 2 stream cards (M2 → M3)

**RENDER** — + `04b_battle_fx.js`
* M2: FX `gust`, `cyclone`, `ring` via `BattleFX.register`; `Post` presets `falls`; DOF (bust + photo, high/ultra); `PhotoCap` (super-sampled capture, thumbnail); songs `falls`; atmosphere presets for falls.
* M3: OBL complete (spheres, lantern circle with noise rim, outline fade, `uOblMode` whiteout); `Snd.dropNotes(p)` driven by colour recovery; songs `grove`, `grey`, `storm`; rain audio; FX `recall`, `whiteout`; presets `grove`, `grey`, `storm`; program audits per island.
* Acceptance: `scen_render_obl`, `scen_render_fx`, `scen_render_photo`, `scen_render_tiers` (new regions).

**LOOKDEV**
* M2: fur shells on designated species (0/4/6/8, 1 DC each), feathers (instanced per wing), crystal-lite (env refraction + Beer absorption; emissive on low), paper final, critter eye v2 rollout API, face-shadow threshold map (if slipped).
* M3: crystal interior "frozen memories" (3 parallax planes, 12 silhouettes) + sparkle, stone (triplanar + strata; baked on low), scale v2 (curvature-modulated scales, wear, cavity), program-count cleanup.
* Acceptance: `scen_lookdev_mats` (7 spheres × 3 lights), `scen_lookdev_fur`, `scen_lookdev_crystal`.

**PEOPLE**
* M2: hero F (if slipped); 여울 (water-veil scarf), 물비, 연 (named tier, 3 face templates); gameplay poses tuned on mounts (rider on tier 1/2 sockets).
* M3: 아린 (monocle refraction plate), 무명/도해 (colour recovery sequence), 카이랑, 이음 (grey → colour via `setSat`/`setHL` + hair colour uniform), 필 (mirrored 연), 고은 (elder stoop); `crowdMesh` for ferry residents, grey villagers, factory workers.
* Acceptance: `scen_people_cast` (W2 cast), `scen_people_bust` (여울, 아린, 이음 grey + colour), `scen_people_crowd`, `scen_people_ride`.

**CREATURES** — `02_models.js`, `02f`, `02h`, `06_ecology.js`, `01d_eco_data.js`
* M2: 하늬연, 몽실소, 운해소, 쪽지새, 서신학, 메아리토, 씨날개, 뭉게산 (10 sky species with W1's two); saddles on all mounts; act-2 habitats for ferry/falls/open sky; airborne state (선회) and aerial encounters; observation behaviour emitters (`eco:observe`); vignettes 깃톨 꼬리 실, 몽실소 새끼.
* M3: 달메아리, 나이테곰, 흐림이, 너울새, 지움쥐, 빈투구, 무명기사, 두둥, 천둥고수, 풍등이, 풍등령 (21 total); habitats grove/grey/storm/royal(placeholder); vignettes 메아리토 합창, 흐림이 곁 물건, 두둥 북 원, 놀란 나이테곰; variants faded/vivid (uniforms); crystallized shell.
* Acceptance: `scen_creatures_new` (10 → 21), `scen_creatures_fur`, `scen_eco_sky`, `scen_eco_vignettes`, `mobile_eco_isle`.

**DRAGONS** — `02c`, `02d`, `02e`, `02i_sky_legends.js`, `04c_stages.js`
* M2: arena `falls`; 단하 remaster first (head split, scale v2, jewel eye, saddle, parts sockets `head/pearl/wingR`) — it is needed by the W3 event.
* M3: arenas `grove`, `grey`, `storm`, `library`; **레코르디아** complete (`designCrane`, three wing pairs with crystal feather cards, slate ring, chained/free states, ring iris, forehead gem `fx_core`, parts `chainL/chainR/gem`); `setFlight` + saddles on legends.
* Acceptance: `scen_dragons_sheet`, `scen_dragons_recordia`, `scen_dragons_saddle`, `scen_stages`.

**ISLES** (sky + world) — `03_world.js`, `03b`, `03c`, `03d`, `03e`, `03f`, `03g`, `03h`
* M2: 천폭섬 (island recipe, 24 falls on ballistic curves, rainbow ring, mirror terraces reflecting the sky function, 3 crystallized falls with thaw states, source spring, trial stage); ring tutorial course; tier 1/2 mount flight finalised with CREATURES' mounts; `Isle.raise` + oblivion-cloud scatter + underside reveal; cloud-hole RT (if slipped).
* M3: 회상림 (crystal pillars instanced, echo spots as `WorldObj` for recall, lake), 무채원 (12-house nameless village, lantern-circle hooks, sinking edge, 레테온 shadow-pass hook), 뇌운첨탑 (storm ring cylinder, rain, lightning, spire, factory, 12 race rings), updraft tier 2, oblivion fog banks, **왕도 rise** set piece (silhouette-level ruins; full royal content in W3).
* Acceptance: `scen_sky_falls`, `scen_world_falls`, `scen_sky_raise`, `scen_world_grove`, `scen_world_grey`, `scen_world_storm`, `scen_world_collide` (4 islands), `scen_world_midlod`.

**BATTLE** — + `07_capture.js`
* M2: skilled capture (aimed throw PC + phone lock-on/swipe, throw timing, `Rules.fieldCapture`, resonance pulse in field and battle, crystals calm/sky/echo); trial modifier `airborne`; data for the 10 M2 species; memory-move data (하트불꽃, 그리운 비, 새순 길); reactions completed (if slipped).
* M3: trial modifiers `afterimage`, `fog`, `thunder`; 「무색」; boss part framework (targeting, markers, `onBreak`, phase hooks) proven on 세오람's crystallized 하늬연; data for all 21 species; balance sims with 13 types.
* Acceptance: node `t_capture`, `t_rules` (trials, parts); `scen_capture_field`, `scen_capture_pulse`, `scen_battle_trial_falls|grove|grey|storm`, `scen_battle_parts`.

**GAME** — + `08_arts.js`
* M2: ch 2; island goals tracking + HUD lines; `isle:lit` → raise, colour, lighthouse level; quest DSL + side quests `s_kites`, `s_frozen`, `s_mirror`; `MEMFRAG` (ferry + falls); map full; bond tiers → timing windows (`Bond.windowMs`); memory moves unlock; let-go respec (detail screen); observation records → dex story pages; 깃전 + shop (구슬).
* M3: ch 3 complete (three islands, any order, royal rise trigger); `Arts` (lantern, recall ghost replays, ignite, veil; glide/ride wrap `Flight`), context prompts, wheel, 3 puzzle templates; memory-condition evolutions; **rest scene** (petting, album, relearn, let-go); side quests `s_whose`, `s_chorus`, `s_flower`, `s_race`; `MEMFRAG` for grove/grey/storm; lean bar + starter branch silhouettes (forms in W3).
* Acceptance: `scen_game_ch2`, `scen_game_ch3`, `scen_game_arts`, `scen_game_rest`, `scen_game_map`, node `t_story`, `t_bond`.

### 4.5 Wave 3 stream cards (M4 → M5)

| Stream | M4 | M5 | Acceptance |
|---|---|---|---|
| RENDER (+ `05e_photo.js`, `photo` block) | whiteout mode, 레테온 oblivion sphere following, UI-erase visuals, phase cut-ins, credits slideshow, songs `royal`, `recordia`, `letheon`, `ieum` | photo mode + postcard judging (`Photo.judge`), DRS/thermal tuning, perf pass all regions, final grading presets | `scen_render_photo`, `scen_game_postcards`, `scen_perf_tiers` |
| LOOKDEV | jewel eyes for all legends, erosion support for 레테온, LD program cleanup | cache versioning, perf, remaining eye LOD rules | `scen_lookdev_eye` (dragon), `scen_lookdev_mats` |
| PEOPLE | 세오람 hero (crystal arm/neck reveal on skinned mesh), 필 · 연 finals | act-1 people v2 (무연 · 하나 · 도윤 · 하람 · 이든 · 세레나), festival crowds, bust polish (brows through hair on all hero tier) | `scen_people_cast` (full), `scen_people_bust` (세오람) |
| CREATURES | 6 starter branch forms (overlays on `dFox`/`dSeal`/`dFawn`), act-1 critters to `makeEye` v2 + LOD chain | icons/portraits for 43 species + 6 forms, festival flocks, ecology polish | `scen_creatures_forms`, `scen_creatures_act1` |
| DRAGONS | **레테온** (moth wings, mask + seam, erosion, white iris, parts `mask/wingL/wingR`, 25u oblivion sphere), arenas `whiteout`, `royal` | ride poses + reaction lines for all legends, remaining remasters (엔시아 · 리미나 feather wings) as budget allows | `scen_dragons_letheon`, `scen_dragons_phase2`, `scen_dragons_saddle` |
| ISLES | 잊힌 왕도 / 기억의 정점 (floating ruins kit, 72 stair platform colliders, rest stops, HQ, colossus face states, library interior), 망각의 눈 (vortex descent cinematic, inverted isle, forgotten objects, upward falls, white-night altar) | boundary act-2 changes (horizon silhouettes, festival, memory rain + rainbow), ferry festival (kites, dance), tier-4 dragon flight polish | `scen_world_royal`, `scen_world_eye`, `scen_world_collide` (royal), `scen_world_festival` |
| BATTLE | boss scripts 단하 act-2, 세오람, 레코르디아 (chains, gem, `allrecall` replaying up to 3 FX), 레테온 (mask/wings, UI erase cadence, restore by 개임/반향, whiteout, assist auto-restore after 4 turns); heart proof rule | rematch scaling Lv 55–60, balance pass (node), assist edge cases | `scen_battle_boss_danha`, `_recordia`, `_letheon`, node `t_rules` (bosses) |
| GAME | ch 4–9, ch 5 「백지」 quiz + ribbon, heart UI (cards hand / carousel, eye close-up through legend `eyeL` socket), 3 legend events with retry hints, 이음's choice, ending + credits | postgame (festival, rematches, dragon flight, 세오람 atonement, 리미나 dawn), side quests `s_courier`, `s_face`, `s_kite_home`, fragment rewards, starter evolution ceremony UI, README | `scen_game_whiteout`, `scen_game_heart`, `scen_game_ending`, `scen_game_postgame`, node `t_story` |

### 4.6 Dependencies inside a wave

```
W1:  W0 stubs ─┬─ RENDER(Q, Atmos) ──────────────┬─ LOOKDEV(LD uses Atmos.chunk, Q.f) ── PEOPLE(v2 rigs) ─┐
               ├─ GAME(SaveV2, Region) ── SKY(buildOpenSky) ── WORLD(adapter, ferry, midLOD) ────────┤
               └─ BATTLE(rules, UI) ── SPIRITS(Eco start conditions → battleFlow cfg) ────────────────┴─ M1
     M0 sync point: every stream lands its M0 list; lead runs the M0 gate, commits, agents continue.
W2:  LOOKDEV materials → CREATURES/DRAGONS assets;  ISLES islands → GAME goals/quests;  BATTLE trials/parts → GAME ch2–3
W3:  DRAGONS 레테온/레코르디아 + BATTLE boss scripts → GAME legend events;  ISLES royal/eye → GAME ch4–9
```
Consumers never wait idle: they code against stubs and switch to the real implementation when the owner flips the feature flag.

---

## 5. Shared interfaces (frozen at the end of Wave 0)

### 5.1 Build, load order, naming

* `python3 build.py` = `--check` + bundle. `--check` fails on: a top-level identifier declared in two files (regex `^(?:export\s+)?(?:const|let|var|function\*?|async\s+function|class)\s+([A-Za-z_$][\w$]*)` per file, printing both file names); any `http(s)://` in `src/` or `template.html` other than `https://cdn.jsdelivr.net/npm/three@0.160.0/`; `</script` in the bundle; a `src/*.js` without an owner header line `//  owner: <STREAM>`.
* Load order = file-name order. Top level defines only (§2.3).
* New globals use the owner's prefix:

| Owner | Globals |
|---|---|
| RENDER | `Bus`, `RNG` (00_core); `Q`, `LODMgr`, `IDB`, `__gfx` (00b); `Atmos`, `LightShaft`, `Snap`, `PhotoCap` (00c); `BattleFX` (04b); `Photo` (05e) |
| LOOKDEV | `LD` (02k); `makeEye`, `EYE_*` (02l); `Bake`, `sculptAsync`, `sculptSync`, `SCULPT_VER`, `SCULPT_SRC` (02m) |
| PEOPLE | `PROPORTIONS`, `SKELETON_HUMAN_V2`, `POSES`, `buildPersonV2`, `crowdMesh`, `bustCam` (02j); `HAIR`, `buildHair` (02n) |
| SPIRITS / CREATURES | `setPose` (02_models); `Eco`, `Habitats` (06); `HABITATS`, `VIGNETTES` (01d) |
| SPIRITS / DRAGONS | `designCrane` (02c); `setFlight` (02d); `buildRecordia`, `buildLetheon` (02i); `Stages` (04c) |
| SKY / ISLES | `Sky`, `buildOpenSky`, `cloudSeaH` (03d); `Waterfall` (03g); `Flight` (03h); `Isle`, `islandTop`, `islandMidLOD`, `buildIsland`, `ISLANDS` (03e); `Kit*` (03f); `buildBoundaryRegion` (03_world) |
| BATTLE | `TYPES`/`CHART` additions, `normMove` (01); `SPECIES2`, `MOVES2`, `mergeSkyData` — merged into `SPECIES`/`MOVES` at boot (01b); `Rules` (04a); `BattleUI` (04d); `Capture` (07) |
| GAME | `MEMORIES` (01c); `Story2`, `QUESTS`, `MEMFRAG`, `POSTCARDS`, `ISLE_GOALS`, `LEGEND_EVENTS` (05b); `Region`, `REGIONS`, `SaveV2` (05c); `Menus2` (05d); `Arts`, `WorldObj` (08); `Bond`, `Mem`, `Memories` (09) |

### 5.2 Boot order and frame order (`05_game.js`, GAME; wired with stubs in Wave 0)

```js
async function boot() {
  await Q.init();                       // settings v2 (+migrate), URL params (Q.params), tier choice; bench deferred
  Atmos.init();                         // Atmos.U must exist before any LD material is built
  Bake.init();                          // Worker self-test + IDB open; failures fall back silently
  LD.init();                            // material table, chunk wiring
  mergeSkyData();                       // 01b: SPECIES2/MOVES2 into SPECIES/MOVES, normMove all (BATTLE)
  Region.init();                        // REGIONS registry (builders registered by SKY/WORLD/ISLES via Region.register)
  buildWorld(); Region.adoptBoundary(World);
  buildBattle();
  for (const d of NPC_DEFS) addNpc(d);  // v2 bodies when def.body && World.playerV2 (PEOPLE)
  Q.apply();                            // applyQuality() stays as a wrapper
  Eco.init(); Bond.init(); Capture.init(); Arts.init(); Story2.init(); BattleUI.init(); Menus2.init();   // Bus subscriptions only
  const existing = SaveV2.load();       // null | S v2 (migrated from v1 if needed)
  /* … title as today … */
  requestAnimationFrame(frame); window.__booted = true;
  Q.benchLater();                       // 1.5 s hidden bench behind the title when auto
}

function frame(now) {
  requestAnimationFrame(frame);
  if (!Q.frameBegin(now)) return;       // fixed 30 fps pacing on low; always true otherwise
  const rdt = Q.rdt, dt = rdt * timeScale();
  Post.update(rdt); Atmos.update(dt); Shared.time.value += dt; Tw.update(dt);
  Region.pump(); Bake.pump();
  try {
    if (G.mode === 'battle') { updateBattle(dt); BattleUI.update(rdt); renderScene(Battle.scene, Battle.camera); }
    else {
      if (G.mode === 'title' || G.mode === 'lore') titleCam(dt);
      updateTitleRig(dt, G.mode === 'title' || G.mode === 'lore');
      updateWorld(dt, canMove());       // first line delegates to Flight.update when World.flight (WORLD/ISLES)
      Eco.update(dt); Arts.update(dt); worldTick(dt);
      LODMgr.update(World.camera);
      renderScene(World.scene, World.camera);   // calls Q.beforeRender(scene, cam) inside (RENDER)
    }
  } catch (e) { console.error(e); }
  Q.frameEnd();
}
```

### 5.3 Bus and the event catalogue

```js
// 00_core.js (Wave 0)
const Bus = {
  h: {},
  on(e, f) { (this.h[e] ||= []).push(f); return () => this.off(e, f); },
  once(e, f) { const off = this.on(e, (d) => { off(); f(d); }); return off; },
  off(e, f) { const a = this.h[e]; if (a) { const i = a.indexOf(f); if (i >= 0) a.splice(i, 1); } },
  emit(e, d) { for (const f of (this.h[e] || []).slice()) { try { f(d); } catch (err) { console.error('[Bus]', e, err); } } },
};
```

| Event | Emitter | Payload | Main listeners |
|---|---|---|---|
| `battle:start` | 04 | `{ kind, foes:[sp], allies:[uid], where:{ region, hab, tod }, start }` | 09, 06, 05b |
| `battle:end` | 04 | `{ kind, res:'win'\|'lose'\|'run'\|'caught', foes:[sp], allies:[uid], turns, lowHp:[uid], where }` | 09 (first win, endure), 06 (despawn/respawn), 05b (quests, goals) |
| `battle:hit` | 04 | `{ by, to, mv, eff, crit, grade, react, dmg, broke }` | 09 (perfect → bond +1) |
| `battle:guard` | 04 | `{ uid, grade, saved }` | 09 (「등 뒤의 방패」) |
| `battle:break` · `battle:react` · `battle:combo` | 04 | `{ uid, part? }` · `{ k, side }` · `{ a, b, pair }` | 09, 05b (dex stats) |
| `battle:phase` | 04 | `{ boss, phase }` | 04b, 05b, 00c |
| `ui:erase` | 04 | `{ el:'timeline'\|'intent'\|'hpnum'\|'chip', on }` | 04d, 04b |
| `capture:result` | 07 / 04 | `{ sp, uid, how:'field'\|'battle'\|'ack', ok, grade }` | 09 (meet), 05 (dex), 06 (remove instance), 05b |
| `eco:notice` | 06 | `{ uid, sp, level:'?'\|'!', dir }` | 05 (edge arc HUD) |
| `eco:encounter` | 06 | `{ sp, uid, start:'normal'\|'ambush'\|'ambushed', hab }` | 05b |
| `eco:observe` | 06 | `{ sp, behaviour, newRecord }` | 05b (eco goals, dex), 09 |
| `eco:vignette` | 06 | `{ id, result:'saved'\|'failed', uid? }` | 09, 05b |
| `art:use` | 08 | `{ art, uid, obj }` | 09 (bond +2, lean), 05b (puzzles), 06 (noise 12u) |
| `region:leave` · `region:enter` | 05c | `{ id, from }` | 06, 08, 05b, 00c (presets), 03d |
| `world:area` | 05 | `{ id, name }` | 09 (home), 05b |
| `isle:goal` | 05b | `{ isle, goal:'trial'\|'eco'\|'mem', done }` | 05 HUD |
| `isle:lit` | 05b | `{ isle }` | 03e (`Isle.raise`), 00c (OBL), 09 (「떠오른 섬」), 03f (lighthouse level), 05 save |
| `isle:raised` | 03e | `{ isle }` | 05b |
| `flight:mount` · `flight:land` · `flight:rescue` | 03h | `{ uid?, tier, at }` | 09 (first flight), 05b |
| `bond:tier` · `mem:gain` · `mem:release` · `evo:ready` | 09 | `{ uid, tier }` · `{ uid, card }` · `{ uid, cardId }` · `{ uid, to \| choose:[a,b] }` | 05d (toasts, ceremony), 04d (window size) |
| `quest:step` | 05b | `{ id, step }` | 05 HUD, save |
| `photo:shot` · `postcard:new` | 05e | `{ blob }` · `{ id }` | 05b, 09 |
| `tier:change` | 00b | `{ tier, f }` | every owner that caches tier-dependent meshes/materials |

### 5.4 Registries

| Registry | Owner (runtime) | Fed by | Purpose |
|---|---|---|---|
| `Habitats.register(id, def)` | 06 | 01d | spawn areas, start fields, vignettes |
| `Memories.register(id, def)` | 09 | 01c | memory triggers, tags, unlocks |
| `Arts.register(id, impl)`, `WorldObj.add(def)` | 08 | 08, ISLES data in region builds | abilities and the objects they act on |
| `Rules.trial(id, mods)`, `Rules.bossScript(id, def)` | 04a | 04a, 05b data | trial modifiers, boss parts/phases/patterns |
| `Stages.register(id, build)` | 04c | 04c | new arenas; `setupTheme(name)` falls back to it for names not in `THEMES` |
| `BattleFX.register(name, fn)` | 04b | 04b | new FX; `playFx` falls back to it for unknown `fx` |
| `Region.register(id, def)` | 05c | 03_world, 03d, 03e | region builders (`REGIONS`) |
| `Atmos.preset(regionId, tod, p)` | 00c | region defs | TOD presets per region |
| `POSES[name]` / `setPose` names | 02j / 02_models | PEOPLE / CREATURES | pose layers by name |

### 5.5 Determinism

```js
const RNG = {   // 00_core.js (Wave 0); hashStr = FNV-1a string hash, added with it
  seed: 0, s: {},
  stream(name) { return this.s[name] ||= mulberry32((hashStr(name) ^ this.seed) >>> 0); },   // () => [0,1)
  reseed(n) { this.seed = n >>> 0; this.s = {}; },
};
```
* Streams: `battle`, `ai`, `field`, `capture`, `eco`, `evo`, `loot`. Decoration (particles, idle jitter) may keep `Math.random`.
* URL parameters (parsed by `Q.init` into `Q.params`): `seed`, `tier`, `tod` (0–3), `tim` (`off|good|perfect` → `Battle.autoTiming`, `Capture.auto`), `region`, `at` (`x,z`), `act2` (start ch 0), `dev`, `lookdev` (`kind:id`), `nosave`, `freeze` (seconds).
* `Flight.autopilot(path, secs)` and `Capture.auto` give deterministic paths for flight and capture timing.

### 5.6 Module APIs (frozen signatures)

```js
// ===== RENDER — 00b_quality.js
const Q = {
  tier: 'high',                                   // 'low'|'mid'|'high'|'ultra'
  f: {},                                          // feature table §9.1 for the current tier
  budget: { tris, calls, programs, gpuMB, fps },
  params: {}, rdt: 0,
  async init(), apply(), set(tier, opts = { auto: false }), on(fn), lodMul(),
  frameBegin(now) /* → bool */, frameEnd(), beforeRender(scene, cam), benchLater(),
};
const LODMgr = { add(obj, { levels: [m0, m1, m2], px: [260, 90, 28], onLevel(i) {} }), remove(obj), update(cam), force(obj, i /* null = auto */) };
const IDB = { ok: false, async open(), async get(store, key), async put(store, key, val), async del(store, key), async keys(store, prefix) };
// DB 'void-being' v1, stores 'mesh' | 'snap' | 'photo'  (§6.5)

// ===== RENDER — 00c_atmos.js
const Atmos = {
  U: { uSunDir, uSunCol, uSkyTop, uSkyHor, uFogCol, uFogSunCol, uFogD0, uFogH, uFogY0, uFogLin, uCloudShadow, uWind, uTime,
       uOblAmt, uOblH, uOblSph /* vec4[4] */, uOblMode, uCloudIn, uWipe, uDesat },        // every LD material references these objects
  init(), update(dt), preset(regionId, tod, p), setPreset(regionId, tod /* 0..4 */, { dur = 0 }),
  setOblivion({ amt, h, mode }), setSphere(i, x, y, z, r /* 0 = off */), lantern(pos /* Vector3|null */, r),
  chunk: { fogx(), cshadow(), obl() },            // GLSL strings, inserted by LD.patch
  skyLUT, envMap(), wipe(dur, mid /* async () => {} */) /* → Promise */, cloudIn(v),
};
const LightShaft = { add(scene, { pos, dir, len, r0, r1, col, a, dust, fade }) /* → Object3D */ };
const Snap = { capture(scene, cam, w = 128, h = 128, q = 0.8) /* → Promise<Blob|null> */ };
const PhotoCap = { capture(scale) /* → Promise<Blob> */, thumb(blob, w = 192, h = 108) /* → Promise<Blob> */ };
// 00_core.js additions: Particles mode 'streak'; Snd.at(audioTime, name); Snd.lowpass(v 0..1); Snd.dropNotes(p); Snd.layer(n); new Snd.fx names

// ===== RENDER — 04b_battle_fx.js / 05e_photo.js
const BattleFX = { register(name, fn /* (uRig, tRig, o) → Promise, calls o.onImpact() */), phaseCut(boss, phase) /* → Promise */, erase(el, on) };
const Photo = { open(), close(), judge(cam) /* → postcardId|null */ };

// ===== LOOKDEV — 02b / 02m / 02k / 02l
function sculptMesh(prims, bounds, cell)          // frozen; v2 adds fields { bake, mat, skin, lod } to the same return object
function sculptSync(key, design, opts)            // → { lod: [BufferGeometry ×3], parts?: { head, body, hands }, stats: { ms, nv, nt, cached } }
function sculptAsync(key, design, opts)           // → Promise<same>;  opts { cell: 'auto'|number, bake: true, lod: [1, 2, 4], priority: 0|1|2 }
const Bake = { init(), pump(), stats(), clearCache() };
const LD = {
  MATS, init(),
  creature(o), person(o), dragon(o), env(o),      // → THREE.Material with o.features (string[]) and o.mats (aMat ids)
  patch(mat, features, params) /* → mat */, outline(mesh, { px, tint = true }) /* → Mesh */, ink(mesh, o),
  fur(mesh, o) /* → InstancedMesh|null */, feathers(wingSpec, o) /* → InstancedMesh */,
  crystal(o), stone(o), cloth(o), paper(o), ghost(o),
  faceProxy(headGeo, { el: [cx, cy, cz, rx, ry, rz], jaw: [[ax, ay, az], [bx, by, bz], r] }) /* writes aFace + proxy normals */,
  programs() /* → count */,
};
function makeEye(o)
// o { kind: 'person'|'critter'|'dragon', r, iris, iris2, pattern: 'fibre'|'rings'|'swirl'|'star'|'mist'|'grey', depth, pupil: 'round'|'slit'|'star',
//     pupilR, limbal, style, lash: { up, low, col }, lidTilt, open, blink, sat, hl }
// → { group, setLook(v3|null), setBlink(v), setPupil(v), setEmotion(name), setSat(v), setHL(v), lod(px), update(dt) }

// ===== PEOPLE — 02j / 02n
const PROPORTIONS = { heroM, heroF, tall, regal, youth, girl12, child8, elder };   // D§13.1
const POSES = { idle, talkA, talkB, point, bow, cheer, think, ride, glide, fall, land, kneel, crouch, throw, command, observe };
async function buildPersonV2(spec, outfit, hair, eye)
// → RigV2 (superset of newRig()): { root, body, skeleton, size, sockets: { head, eyeL, eyeR, mouth, back, handL, handR, hip, rider },
//     face(name), pose(name, blend = 0.25), say(text) /* → Promise */, lookAt(v3|null), setMove(speed), setRide(mountRig|null),
//     setGlide(on), measure() /* → { height, headH, heads } */, lod(i) }
function crowdMesh(variants, n)                   // → InstancedMesh (LOD2, vertex-shader walk)
function bustCam(rig, side /* 'left'|'right' */)  // → { pos, look, fov: 30 } so the face fills 28–35 % of screen height
// NPC_DEFS entries gain optional body: { proportions, tier: 'hero'|'named'|'crowd', face: 'round'|'oval'|'square' }, outfit, hair, eye

// ===== SPIRITS / CREATURES — 02_models / 06 / 01d
function makeSpiritModel(sp, opts = {})           // existing + opts { lod: 0|1|2, variant: 'vivid'|'faded'|'restored'|null, crystal: 0..1, form: null }
// every spirit rig gains: rig.sockets { head, fx_core, ui_top, saddle? }, rig.setPose(name, w), rig.face(emotion), rig.look(v3|null), rig.setPupil(v), rig.lod(i)
function setPose(rig, name, w = 1)                // safe no-op when the rig lacks the pose
const Eco = { enabled: false, init(), enterRegion(id), leaveRegion(), update(dt), spawn(sp, x, z, state, lv) /* → inst */, list(),
              nearest(x, z, r), observeTarget(cam) /* → inst|null */, subdue(inst), setStealth(mul, secs), vignette(id), debug(on) };
const Habitats = { register(id, def), get(id), forRegion(id) };
// inst { uid, sp, lv, rig, state, aware, hab, x, z, asleep, unaware, leaderUid }

// ===== DRAGONS — 02d / 02i / 04c
function dragonGeometry(key, design, cellHi, cellLo, opts)    // existing + opts { v2: true } → delegates to sculptSync
function setFlight(rig, mode)                     // 'idle'|'cruise'|'boost'|'dive'|'bankL'|'bankR'|'land'
// legend rigs: rig.sockets.saddle, rig.parts { head, pearl, wingL, wingR, mask, chainL, chainR, gem } (Object3D for part markers / break FX)
const Stages = { register(id, build /* (scene) → { group, update(dt), dispose() } */), build(id, scene) };

// ===== SKY / WORLD / ISLES — 03_world / 03d / 03e / 03g / 03h
function groundY(x, z) / heightAt(x, z)           // frozen; dispatch to World.groundFn / World.heightFn when set
function buildBoundaryRegion()                    // RegionBuild generator wrapping today's buildWorld() result
function buildOpenSky()                           // RegionBuild generator
function cloudSeaH(x, z)                          // → y
const Sky = { setBanks(list), flock(spec) /* → handle */, rings(courseId) /* → [{ pos, radius }] */ };
function islandTop(id, x, z)                      // → y (island local)
function islandMidLOD(id)                         // → Mesh, merged, ≤ 6k tris
function buildIsland(id)                          // RegionBuild generator
const Isle = { raise(id, dy = 30, secs = 12) /* → Promise */, offset(id) /* → current y offset */ };
const Waterfall = { build({ edge, W, v0, depth, seed, rainbow, mist, up = false }) /* → Object3D */ };
const Flight = {
  state: { mode: 'walk'|'glide'|'ride', speed, alt, gauge, tier, inCloud, canLand, landTarget },
  glide(on), mount(riderRig, mountRig, mon, tier), dismount(), update(dt, controllable),
  autopilot(path /* [Vector3] */, secs) /* → Promise */, rescue(),
};
// RegionBuild: function* build(ctx) { …; yield; …; return RB }   ctx = { budgetMs, tier, track(obj) }
// RB = { scene, heightAt(x,z), groundY(x,z), platforms: [{ x, z, w, d, y, rot }], colliders, interact() /* → [{ x, z, r, label, verb, fn }] */,
//        habitats: [ids], areas: [{ n, sub, test(x, z) }], landmarks: { id: Object3D }, spawn: { x, z, yaw }, stops: [{ id, x, z }],
//        oblivion?: { amt, h, spheres }, lights, tod, post, programs: [keys], update(dt), dispose() }

// ===== BATTLE — 04a / 04 / 04d / 07
const Rules = {
  create(cfg),            // cfg { kind: 'wild'|'trainer'|'keeper'|'legend'|'boss', allies: [Mon], partnerIdx: 1, foes: [Mon], seed,
                          //       start: 'normal'|'ambush'|'ambushed', field: { ally: k|null, foe: k|null }, trial: id|null, boss: id|null,
                          //       assist: { autoUiRestore: false } }  → BState
  next(st) /* → unit */, timeline(st, n) /* → [{ uid, side, ct, intent? }] */, intents(st, n) /* → [{ uid, mv, part?, threat }] */,
  preview(st, uid, action) /* → { ctAfter, ghostIndex, dmg: [lo, hi], eff, poise, react } */,
  plan(st, uid, action)   /* → Plan { steps: [{ id, by, to, part?, mv, kind: 'hit'|'status'|'heal', timing: 'atk'|'guard'|null, fx }] } */,
  commit(st, plan, i, grade /* 'perfect'|'good'|'miss'|null */) /* → Event[] */,
  endAction(st, plan) /* → Event[] */, aiAction(st, uid) /* → Action */, isOver(st) /* → null|'win'|'lose'|'run'|'caught' */,
  captureChance(st, uid, crystalId, bonus) /* → { p, q } */, fieldCapture(mon, crystalId, ctx) /* → { p, q } */,
  heartProof(answers /* [{ tags, bondTier }] */, def) /* → number */,
  trial(id, mods), bossScript(id, def), normMove(id),
};
// Action = { t: 'move', mv } | { t: 'guard' } | { t: 'combo', mv, pmv } | { t: 'switch', idx } | { t: 'item', id, target }
//        | { t: 'crystal', id } | { t: 'run' } | { t: 'aim', part }
// Event  = { k: 'turn'|'msg'|'move'|'miss'|'hit'|'guard'|'counter'|'react'|'field'|'break'|'status'|'stage'|'heal'|'faint'
//               |'combo'|'charge'|'cancel'|'phase'|'part'|'ui'|'ct'|'reso', …fields }
// 04_battle.js keeps (frozen): runBattle(cfg), useMove(side, mv) (wrapper), throwCrystal(id) (wrapper → Capture.inBattle),
//   calcDamage(att, def, mv) (wrapper → Rules), aiPick(user, target) (wrapper); Battle.v2, Battle.autoTiming, Battle.speed
// battleFlow(cfg) (05_game, frozen) accepts new optional fields: start, field, trial, boss, where, partner
const BattleUI = { init(), show(st), hide(), update(rdt), menu(st) /* → Promise<Action> */,
                   ring(kind /* 'atk'|'guard'|'multi'|'hold'|'pulse' */, target, tImpactMs) /* → Promise<grade> */,
                   partMarkers(parts), erase(el, on) };
const Capture = { auto: 'off', init(), aimStart(), aimUpdate(dt), aimEnd(), throwAt(inst, crystalId) /* → Promise<bool> */,
                  inBattle(crystalId) /* → Promise<bool> */, pulse(sp) /* → ms[] */ };

// ===== GAME — 05c / 09 / 08 / 05b / 05d
const Region = { id, init(), register(id, def), go(id, at, opts) /* → Promise */, adoptBoundary(World), track(obj), preload(id), state(id),
                 pump(), onEnter(fn), onLeave(fn), current() /* → RB */ };
const SaveV2 = { KEY: 'void-being-save-v2', V1: 'void-being-save-v1', load() /* → S|null */, save(), fresh(), migrate(s), validate(s), size(), restoreV1(),
                 card(id, ctx), legacyWhere(sp), legendSite(sp) };
const Bond = { init(), give(m, n, why), tier(m) /* 0..4 */, windowMs(m) /* 0|10|20|30 */, lean(m, d), evoCheck(m) /* → null|{ to }|{ choose: [a, b] } */ };
const Mem = { grant(m, id, ctx) /* → card|null */, has(m, id), list(m), release(m, cardId) /* → true */, thumb(card) /* → Promise<url|null> */,
              hand(party, n) /* → cards for the heart UI */ };
const Memories = { register(id, def), get(id) };
const Arts = { init(), register(id, impl), available() /* → [{ id, uid }] */, use(id, target) /* → Promise */, prompt(obj), update(dt) };
const WorldObj = { add(def), get(id), set(id, state), near(x, z, r) };
const Story2 = { init(), chapter(), start(ch), questInfo() /* → [obj, sub] */, goal(isle, k, done), legend(id) /* → Promise */ };
const Menus2 = { init(), album(m), detail(m), map(), settings(), heart(def) /* → Promise<proof> */, whiteoutQuiz(m) /* → Promise */, rest() /* → Promise */ };
```

### 5.7 Data shapes

```js
// 01_data.js — additions only, existing cells unchanged (D§5.2)
Object.assign(TYPES, {
  wind:     { n: '바람', c: '#8fd8ff', hex: 0x8fd8ff },
  memory:   { n: '기억', c: '#f6c8ff', hex: 0xf0b8ff },
  oblivion: { n: '망각', c: '#c8c8d0', hex: 0xb8b8c4 },
});
Object.assign(CHART.grass, { wind: 0.5 }); Object.assign(CHART.thunder, { wind: 2 }); Object.assign(CHART.earth, { wind: 2 });
Object.assign(CHART.shadow, { memory: 2 }); Object.assign(CHART.being, { oblivion: 0.5 }); Object.assign(CHART.void, { memory: 0.5 });
CHART.wind     = { grass: 2, oblivion: 2, thunder: 0.5, earth: 0.5, wind: 0.5 };
CHART.memory   = { oblivion: 2, void: 2, memory: 0.5, shadow: 0.5 };
CHART.oblivion = { memory: 2, being: 2, oblivion: 0.5, light: 0.5 };

// MOVES v2 fields filled by normMove(id) (existing 45 untouched in source)
{ w: 0.75|1|1.35, tag: ['contact'|'proj'|'beam'|'sound'|'heavy'|'ground'], charge: 0|1,
  timing: 'ring'|'multi'|'hold'|null, field: null|{ k, ch, turns } }
// rules: w = sig||p>=90 ? 1.35 : (p>0 && p<=45) ? 0.75 : 1;  fx dash/slash → contact, bolt → proj, beam/genesis → beam,
//        roar/deepsong → sound, quake/sandwind → ground; sig → charge 1; p>0 → timing 'ring'

// SPECIES v2 optional fields (act-1 entries gain them in 01_data; new species in 01b)
{ size: 'S'|'M'|'L'|'XL',
  eco: { temper: 'shy'|'curious'|'territorial'|'herd'|'hunter', active: ['dawn','day','dusk','night'], view: 8..18, fov: 120, speed: [walk, run], fly: false },
  mount: { tier: 1|2|4, cruise, boost } | null, art: 'ignite'|'recall'|'veil'|null, pulse: [ms, …],
  evo: { to, lv } /* legacy */ | [{ to, lv, bond?, lean?: 'memory'|'oblivion', mem?, tod?, where?, act? }],
  formOf?: sp, branch?: 'memory'|'oblivion', fur?: { len, density } }

// Mon (persisted) — v1 fields untouched + v2 fields (§6.1)
// Card (persisted in Mon.mem / Mon.archive, compact keys)
{ i: 'first_meet', t: 1730960000000, r: 'boundary', p: 'south_meadow', d: 2 /* tod */, w: ['bandiru'], s: 1 /* has snapshot */ }
// text is rebuilt from MEMORIES[i].text at display time — never stored

// 01c — memory definition
MEMORIES.protect_night = { n: '지켜준 밤', tags: ['protect', 'night'], text: '{tod}, {place}에서 {name}{와/과} 함께 작은 빛을 지켰다.',
  who: 'lead' | 'party' | 'participants', on: 'eco:vignette', test: (e) => e.result === 'saved',
  bond: 40, lean: 3, unlock: null | { move: ['hwarr', 'heartflame'] } | { evo: ['somgu', 'moonge'] } };

// 01d — habitat (D§8.5)
{ region, area: { x, z, r }, slots, theme, start: { ally, foe }, spawns: [{ sp, lv: [a, b], w, tod?, flag?, group? }], hide, vignettes: [ids] }

// 05b — island goals, quests, legend events
ISLE_GOALS.falls = { keeper: 'yeoul', trial: 'airborne', required: 'trial',
  eco: { observe: [['mongsil', 'eat'], ['yeongit', 'fly'], ['gitol', 'play']] }, mem: { frags: 5, task: 'thaw1' } };
QUESTS.m2 = { main: true, ch: 2, n: '천 개의 폭포', req: () => S.flags.rival1, steps: [{ obj, sub, at: { r, x, z }, done: () => bool }] };
LEGEND_EVENTS.recordia = {
  omen: { from: 'ch3' }, trials: [{ id: 'memories3', art: 'recall', n: 3 }, { id: 'anchors', arts: ['ignite', 'veil', 'lantern'] }],
  boss: { parts: [{ id: 'chainL', hp: 0.2, poise: 4, onBreak: 'wingsFree' }, { id: 'chainR', hp: 0.2, poise: 4, onBreak: 'wingsFree' },
                  { id: 'gem', hp: 0.25, poise: 6, onBreak: 'cancelCharge' }],
          phases: [{ at: 1.0, script: 'chained' }, { at: 0.5, script: 'unbound' }], pattern: ['memlight', 'engrave', 'memshield', 'CHARGE:allrecall'] },
  heart: { need: 2, q: [{ text: '처음을 기억하느냐?', tags: ['meet', 'first'] },
                        { text: '무엇을 지켰느냐?', tags: ['protect', 'endure'] },
                        { text: '무엇을 놓아주었느냐?', tags: ['farewell'] }] },
};
POSTCARDS.falls1000 = { n: '천 개의 폭포', r: 'sky', at: { x: -440, y: 140, z: 250, r: 70 }, look: { x: -440, y: 110, z: 120 }, minDot: 0.92, tod: [2], req: () => S.q.s_frozen?.done };
MEMFRAG = [{ id: 'f01', r: 'ferry', x, y, z, who: '연 공방 막내', t: '…', cond?: () => bool }];

// 05c — region definition
REGIONS.falls = { n: '천폭섬', en: 'ISLE OF A THOUSAND FALLS', act: 2, kind: 'island', sky: { x: -440, z: 120, y: 140, r: 95 },
  build: buildIsland, music: 'falls', tod: 1, land: { x: 30, z: 40 }, stop: true, habitats: ['falls_steps', 'falls_mist'],
  tech: { post: 'falls', atmos: { fogD0: 0.004, fogH: 20, cloudCov: 0.45 }, lights: 3, programs: [/* feature-set keys */], prebuild: ['ferry'] } };
```

### 5.8 Existing functions whose signatures are frozen

Only optional trailing parameters may be added; old call sites must keep working.

`makeMon(sp, lv)` · `calcDamage(att, def, mv)` · `typeEff(atk, types)` · `monTypes(m)` · `stat(m, i)` · `maxHp(m)` · `learnedMoves(sp, lv)` · `rollPool(pool)` · `newRig()` · `rigUpdate(r, dt)` · `makeSpiritModel(sp)` · `disposeRig(r)` · `setFollower(sp)` · `addNpc(def)` · `buildPerson(o)` · `clothRibbon(parent, o)` · `sculptMesh(prims, bounds, cell)` · `dragonGeometry(key, design, cellHi, cellLo)` · `dragonMaterial(o, D)` · `critterEye(o)` · `animeEye(o)` · `sculptOutline(mesh, w, c)` · `envFromSky(U)` · `groundY(x, z)` · `heightAt(x, z)` · `walkable(x, z)` · `buildWorld()` · `updateWorld(dt, controllable)` · `applyAtmos()` · `battleFlow(cfg)` · `runBattle(cfg)` · `useMove(side, mv)` · `throwCrystal(id)` · `playFx(mv, uRig, tRig)` · `setupTheme(name)` · `say(lines, who, cls)` · `ask(text, options, who, cls)` · `banner(b1, b2, cls, hold)` · `toast(t)` · `save()` · `loadSave()` · `newState()` · `renderScene(scene, cam)` · `applyQuality()` · `hitStop(sec, slow)` · `Snd.fx(name)` · `Snd.play(song)` · `Particles` methods · `Puffs` · `StaticKit()` · `Icons.*` · `window.__game` existing members.

---

## 6. Save, settings and storage

### 6.1 S v2

```js
{
  v: 2, act: 1 | 2,
  party: [Mon], box: [Mon],
  items: { crystal, potion, elixir, origin, calmCrystal, skyCrystal, echoCrystal, clearwind, vivid, cloudFeather, lampIncense, forgetFlower, forgetShard },
  key: { glider, harness, lantern, lanternPlus, pass },
  flags: { /* every v1 flag unchanged */ act2Ready, act2, motesSeen, ferryArrived, metSoha, metIeum, rival1, firstFlight, royalRisen, twins, yeonJoins,
           whiteout, seoram, recordiaAck, eyeDescent, letheonAck, ieumChoice, act2End, migratedFrom },
  dex: { seen, caught, obs: { [sp]: 0b000000 /* 6 behaviours */ }, forms: { [formSp]: true } },
  region: 'boundary', pos: { [region]: { x, y?, z } }, yaw,
  isles: { falls: { trial: false, eco: false, mem: 0, lit: false, raised: 0 }, grove: {…}, grey: {…}, storm: {…} },
  colour: { ferry: 0, falls: 0, grove: 0, grey: 0, storm: 0, eye: 0, houses: {} },
  tod: { [region]: 0..3 },                       // set by 「쉬기」; absent = region default
  q: { [qid]: { step, done, n?, found? } },
  legends: { recordia: { step, tries }, letheon: { step, tries }, danha2: { step, tries } },
  frag: { [fragId]: 1 }, cards: { [postcardId]: { t, d, r } },      // thumbnails live in IDB
  money: 0, hero: { sex: 'm' | 'f', outfit: 'classic' | 'wind' }, ride: null,
  opts: { timing: 'manual' | 'auto', speed: 1, fxShort: false, diff: 'normal', latency: 0, invertPitch: false },
  stats: { battles: 0, perfects: 0, flightDist: 0, photos: 0 },
}
// Mon v2 = v1 { uid, sp, lv, exp, iv, moves, status, hp }
//        + { nick: null, bond: 0, lean: { mo: 0 }, mem: [Card], archive: [Card], met: { r, where, lv, t, legacy? },
//            log: { battles: 0, firstWin: null, firstMove: null, evoLv: null }, ribbon: false, var: null, form: null }
```

### 6.2 Migration chain

```js
const SAVE_VER = 2;
const MIGRATE = { 1: v1to2 };                    // future: 2: v2to3 …
SaveV2.load = function () {
  try {
    const s2 = JSON.parse(localStorage.getItem('void-being-save-v2') || 'null');
    if (s2 && s2.v === 2 && s2.party) return SaveV2.validate(s2);
    let s = JSON.parse(localStorage.getItem('void-being-save-v1') || 'null');     // read only — never written or removed
    if (!s || !s.party) return null;
    while (s.v < SAVE_VER) s = MIGRATE[s.v](s);
    return SaveV2.validate(s);                   // first save() writes the v2 key
  } catch (e) { console.error(e); toast('저장 데이터를 새 형식으로 옮기지 못했어요'); return null; }
};
function v1to2(s) {                             // helpers are SaveV2 methods to avoid new top-level names
  const n = SaveV2.fresh();                       // v2 defaults
  Object.assign(n, { party: s.party, box: s.box, flags: s.flags, yaw: s.yaw || 0 });
  Object.assign(n.items, s.items);
  n.dex.seen = s.dex.seen; n.dex.caught = s.dex.caught;
  n.region = 'boundary'; n.pos = { boundary: s.pos || { x: SITES.spawn.x, z: SITES.spawn.z } };
  n.act = 1; n.hero = { sex: 'm', outfit: 'classic' };
  for (const m of n.party.concat(n.box)) {
    m.bond ??= Math.min(450, 40 + m.lv * 12);    // long-time partners start near 신뢰 (Lv30 → 400)
    m.lean ??= { mo: 0 }; m.mem ??= []; m.archive ??= []; m.log ??= { battles: 0, firstWin: null, firstMove: null, evoLv: null };
    m.met ??= m.sp === s.flags.starter ? { r: 'boundary', where: '윤슬마을', lv: 5, t: 0, legacy: true }
                                      : { r: 'boundary', where: SaveV2.legacyWhere(m.sp), lv: m.lv, t: 0, legacy: true };   // first POOLS region of the species
    if (m.sp === s.flags.starter) m.mem.push(SaveV2.card('first_meet', { p: 'yunseul' }));
    if (s.flags.ending) m.mem.push(SaveV2.card('first_dawn', { p: 'altar' }));
    if (SPECIES[m.sp].legend) m.mem.push(SaveV2.card('acknowledged', { p: SaveV2.legendSite(m.sp) }));
  }
  if (s.flags.ending) n.flags.act2Ready = true;
  n.flags.migratedFrom = 1; n.v = 2;
  return n;
}
```

### 6.3 `validateS(s)`

Fills missing fields with defaults (damaged or partial saves); clamps `party` to 1–6 (extra → `box`); a `Mon.sp` missing from `SPECIES` moves to `box` with `flags.badMon`; NaN numbers → defaults; unknown `region` → `boundary`; unknown `pos` → region spawn; `mem` > 12 → oldest to `archive`; `archive` > 8 → oldest dropped. **Size**: if JSON > 56 KB, trim box archives, then box `mem` to 4 per spirit; hard cap 64 KB. A failed validation offers "1부 저장으로 되돌리기" (`restoreV1`, which only reads the untouched v1 key).

### 6.4 Settings v2

```js
// v1 { high: bool, ultra: bool, sound: bool }  →  v2
// { v: 2, tier: 'low'|'mid'|'high'|'ultra', auto: true, fps: 30|60, drs: true, sound: true, music: 0.8, sfx: 0.9,
//   feat: { fur: null, hairCards: null, dof: null } /* null = tier default */, photoScale: 1.5 }
function migrateSettings(o) {
  if (!o) return null;
  if (o.v === 2) return o;
  return { v: 2, tier: o.high === false ? 'low' : o.ultra ? 'high' : 'mid', auto: false, fps: o.high === false ? 30 : 60, drs: true,
           sound: o.sound !== false, music: 0.8, sfx: 0.9, feat: {}, photoScale: 1.5 };
}
// Back-compat kept every frame by Q.apply(): Settings.high = tier !== 'low'; Settings.ultra = tier === 'high' || tier === 'ultra'.
// The harness writes v1 { high:false } for LOW=1 — migrateSettings maps it to 'low'.
```

### 6.5 IndexedDB

One database `void-being` (version 1), opened by `IDB.open()`:

| Store | Key | Value | Limit | Without IDB |
|---|---|---|---|---|
| `mesh` | `SCULPT_VER\|key\|cell\|fnv1a(prims)` | quantised geometry (pos Uint16×3, oct normal Int8×2, colour/bake RGBA8, aMat, aS, indices) ≈ 20 B/vertex | 80 MB LRU; cleared when `SCULPT_VER` changes | rebuild every boot (phones show LOD1 first) |
| `snap` | `snap/<uid>/<cardIndex>` | JPEG 128² | 240 entries LRU | cards are "빛바랜 기억" (sepia, text) |
| `photo` | `card/<postcardId>`, `shot/<t>` | JPEG thumbnails 192×108 / user photos | 200 | photos download only, postcards without thumbnails |

### 6.6 What never goes into `localStorage`

Snapshots, thumbnails, photos, mesh caches, per-frame stats. `localStorage` holds exactly two keys written by the game: `void-being-save-v2` (≤ 64 KB) and `void-being-settings` (v2). `void-being-save-v1` is read, never written.

---

## 7. Verification

### 7.1 Node tests — `node tests/run.mjs [area]` (whole suite < 10 s)

`run.mjs` builds a `vm` context with `tests/stub.js` and loads the pure files: `01_data.js`, `01b_data_sky.js`, `01c_mem_data.js`, `01d_eco_data.js`, `04a_rules.js`, the pure part of `09_bond.js`, the pure step functions of `06_ecology.js` and `03h_flight.js`, `05b_story2.js` data, and `05c_regions.js` migration. These files must not touch DOM/THREE at top level or in the tested functions.

| Test | Owner | Pass criteria |
|---|---|---|
| `t_data` | BATTLE | 13 × 13 chart defined; every v1 cell equals the snapshot `tests/fixtures/chart_v1.json`; `normMove` passes for all 77 moves; every learnset move and evolution target exists; 43 species + 6 forms; unique names and ids |
| `t_rules` | BATTLE | seeded CTB order reproducible; intents stay locked when state changes; break cancels a charge; each of the 8 reactions table-driven; resonance accounting; combo pairs; **damage parity**: grade `miss`, no field/break/combo → mean within ±0.5 % of v1 `calcDamage` over 10k samples; **starter mirror 10k**: win 45–55 %, mean turns 8–14; **skill**: `perfect` vs `off` against a level-matched keeper team: −30–40 % turns; trial modifiers; boss parts & phases; 레테온 UI-erase cadence + restore events; no NaN |
| `t_capture` | BATTLE | Monte Carlo 100k reproduces D§6.3 table ±1 pp; bonus cap ×4 |
| `t_bond` | GAME | tier thresholds and windows; memory triggers from synthetic Bus events; release → shard + `farewell` trace; `evoCheck` table: starter Lv36 + bond 350 with lean +30 / −30 / 0 (choose); memory-condition and night evolutions |
| `t_save` | GAME | 5 v1 fixtures (`fresh`, `rift1`, `preNihilos`, `postEnding`, `box60`) → v2 → JSON → load → validate: party/box/dex/flags equal; `act2Ready` only for `postEnding`; stress fixture (6 + 60 spirits, full cards) ≤ 64 KB; v1 key untouched |
| `t_eco` | SPIRITS / CREATURES | 100 s sim per temper: sleeps in inactive TOD, flee distance 8–20u, awareness thresholds (crouch 1.2u / walk 3u / run 9u) |
| `t_flight` | SKY / ISLES | 60 s integration: gauge and speed ranges per tier (D§9.2), ceiling clamp, oblivion-sea rescue fires after 5 s |
| `t_story` | GAME | no unreachable quest step; every referenced flag is set somewhere; island goals 2-of-3 (falls requires trial); `POSTCARDS` ids unique; `MEMFRAG` counts per region = D§14.2 |

### 7.2 Screenshot harness — `harness/`

* `node harness/shot.js <scenario> [outDir]` — Playwright + SwiftShader (`--use-angle=swiftshader`), desktop 1280 × 760, `mobile_<scenario>` = 400 × 860 touch, `LOW=1` (settings v1 `{high:false}` → tier low), `TIER=mid|high|ultra`, `VW`/`VH`. three is served from `harness/deps` by route; **any request to another host fails the scenario** (`scen_ext_requests` additionally checks the boot sequence).
* Init script: seeds `Math.random`, sets `?seed=` and `?freeze=` where the scenario asks, so the same input gives the same image.
* Output: `ERRORS: none` (console errors and page errors) + the scenario's automatic criteria printed as `CHECK name: PASS|FAIL value`.
* `window.__gfx` (RENDER): `info()`, `budget()` (empty `over` = pass), `tier(name)`, `freeze(t)`, `seed(n)`, `lookdev(kind, id, o)` (neutral stage: grey floor, region sky LUT, 3-point light, 18 % grey sphere, procedural checker), `view(mode)` (`lit albedo normal ao curv thick matid silhouette value lod overdraw`), `contact(shots, cols)` (N renders on one canvas → one slow screenshot instead of N), `probe(rect, w, h)` → `{ meanL, maxL, minL, meanSat, nan, hist[8] }`, `scan(rect, rows)` → max light/dark transitions per row, `measure(rig)`, `footSlide(rig, sec)`, `frameStats(sec)` → `{ median, p95, max }`, `timings`, `slowBuild(k)`, `failWorker()`, `failIDB()`.
* Baselines: `harness/baseline/<scenario>.json` (probe stats). Regression scenarios compare against them with the tolerances below.
* Budget per scenario: ≤ 3 screenshots, ≤ 90 s of scene build. Asset checks run on the lookdev stage with contact sheets, not in full regions.

### 7.3 Scenario catalogue

| Scenario | Owner | From | What it does | Automatic pass |
|---|---|---|---|---|
| `scen_smoke` / `mobile_smoke` / `LOW=1 scen_smoke` | lead | W0 | boot → world | errors 0 |
| `scen_story` | lead | W0 | act 1 scripted to the ending (`tim=perfect`, seed) | errors 0, `flags.ending` |
| `scen_regress_look` | lead | W0 | plaza dusk, east rift, altar, field battle | each shot meanL ±8 %, meanSat ±10 % vs baseline |
| `scen_ext_requests` | lead | W0 | boot → title → world | 0 requests outside three CDN (fonts included) |
| `scen_render_tiers` | RENDER | W1 | same plaza cut × 4 tiers on one contact sheet | `budget().over` empty per tier; programs ≤ budget |
| `scen_render_atmos` | RENDER | W1 | lookdev island at dawn / dusk / night | dusk top-band R > B; night meanL < 0.25; far object within ±10 % of fog colour |
| `scen_render_drs` | RENDER | W1 | synthetic full-screen load on/off | pixel ratio drops within 3 s, recovers after load removed |
| `scen_render_obl` | RENDER | W2 | plane + 2 lantern spheres | outside meanSat < 0.12, inside > 0.30; OBL-free region programs contain no `oblAt` |
| `scen_render_fx` | RENDER | W2 | 5 new FX at peak frame, contact sheet | NaN 0, maxL > 0.9 |
| `scen_render_photo` | RENDER | W2 | capture in photo mode | blob > 0; size = viewport × tier scale; localStorage growth < 1 KB |
| `scen_perf_tiers` | RENDER | W3 | 10 s open-sky flight per tier | `budget().over` empty; p95 < 3 × median |
| `scen_lookdev_sculpt` | LOOKDEV | W1 | (no shot) Worker vs sync vs cache, then `failWorker` | equal vertex counts; cache hit < 15 % of first build; fallback builds |
| `scen_lookdev_bake` | LOOKDEV | W1 | dragon: ao / curv / thick / matid sheet | AO mean 0.55–0.9; NaN 0; head–body seam normal delta < 15° |
| `scen_lookdev_eye` | LOOKDEV | W1 | person eye close-up at yaw −25° / 0° / +25° + blink frame | iris centre shift > 2 px (parallax); highlight maxL > 0.95; blink frame highlight maxL < 0.8 |
| `scen_lookdev_face` | LOOKDEV | W1 | hero bust, light azimuth 30° / 90° / 150° | `scan(face, 12)` ≤ 2 transitions per row (clean terminator) |
| `scen_lookdev_outline` | LOOKDEV | W1 | one spirit at 3 distances | dark edge band 1–3 px at every distance |
| `scen_lookdev_mats` | LOOKDEV | W1→W2 | material spheres × 3 lights | program count = feature combinations; crystal centre shifts toward the opposite environment colour |
| `scen_lookdev_fur` · `scen_lookdev_crystal` | LOOKDEV | W2 | fur on/off; crystal interior | fur: edge luminance variance up, 1 DC per shell set; crystal: interior silhouettes visible (hist bimodal) |
| `scen_people_cast` | PEOPLE | W1→W3 | cast in a row + head-unit overlay | `measure` heads within ±0.15H of D§13.1 |
| `scen_people_bust` | PEOPLE | W1→W3 | bust contact sheet | face height 28–35 % of screen; eye maxL > 0.95 |
| `scen_people_walk` | PEOPLE | W1 | hero walking a slope 2 s | `footSlide` < 0.03u; knee 5–65° |
| `scen_people_talk` | PEOPLE | W1 | one line of dialogue | ≥ 4 of 6 mouth shapes; closed on '.' |
| `scen_people_crowd` · `scen_people_ride` | PEOPLE | W2 | 20+ crowd; rider on 3 mounts | crowd ≤ 3 DC; rider–saddle < 0.05u over 2 s |
| `mobile_people_low` | PEOPLE | W1 | LOW bust | errors 0; 0 hair cards |
| `scen_creatures_act1` | SPIRITS → CREATURES | W1 | 13 act-1 critters contact sheet | ±5 % meanL vs baseline; tris per tier budget |
| `scen_creatures_new` | SPIRITS → CREATURES | W1→W2 | new species sheet + silhouette sheet | all built; tris within budget; NaN 0 |
| `scen_creatures_forms` | CREATURES | W3 | 6 starter branch forms | built; tris within budget |
| `scen_eco_day` · `scen_eco_night` | SPIRITS → CREATURES | W1 | habitat at fixed TOD | state icons present; sleepers `uBlink` = 1; herd within leader radius |
| `scen_eco_encounter` | SPIRITS | W1 | crouch behind sleeper → talk | battle starts with foe broken, ally ct × 0.3 |
| `scen_eco_sky` · `scen_eco_vignettes` · `mobile_eco_*` | CREATURES | W2 | aerial flock + aerial battle; each vignette | flock 1 DC; `eco:vignette` emitted; LOW: animated rigs ≤ 6, p95 < 3 × median |
| `scen_dragons_sheet` · `scen_dragons_recordia` · `scen_dragons_letheon` | DRAGONS | W2→W3 | legend lookdev sheets | head part mesh present; tris budget; ring iris hist ≥ 2 peaks; 레테온 phase-2 meanSat < 0.15 |
| `scen_dragons_saddle` | DRAGONS | W2 | hero on 단하 saddle, 4 flight modes | rider–saddle < 0.05u |
| `scen_stages` | WORLD → DRAGONS | W1→W3 | all new arenas sheet | errors 0, DC ≤ 80 per arena |
| `scen_sky_postcard` | SKY → ISLES | W1 | 「운해 위를 나는 오후」 high + LOW | bottom third meanL 0.55–0.9; NaN 0 |
| `scen_sky_flight` | SKY → ISLES | W1 | 10 s autopilot through 3 rings | no NaN; y ≤ 480; p95 < 3 × median |
| `scen_sky_cloudin` | SKY → ISLES | W1 | fly into cumulus | `uCloudIn` > 0.8; meanL < 0.95 |
| `scen_sky_falls` · `scen_sky_raise` | ISLES | W2 | falls from open sky, sun behind camera; island lit | waterfall count = tier value; rainbow hue variance > baseline; island offset +30u, underside puffs gone |
| `scen_world_midlod` | WORLD → ISLES | W1 | 7 mid-LOD islands sheet | each ≤ 6k tris; top height = D§3.6 ±2u |
| `scen_world_ferry` · `_falls` · `_grove` · `_storm` · `_royal` · `_eye` · `_festival` | WORLD → ISLES | W1→W3 | each region's postcard cut | DC and tris ≤ tier budget; shadow-pass DC ≤ 60; grove pillar count = tier; storm rain = tier; royal 72 platform colliders; eye meanSat < 0.2 |
| `scen_world_grey` | ISLES | W2 | lantern circle from above | outside meanSat < 0.12, inside > 0.30; outlines fade |
| `scen_world_collide` | WORLD → ISLES | W1→W3 | bot walks region waypoints | 0 falls through, 0 stuck > 2 s |
| `scen_battle_timeline` (+ `mobile_`) | BATTLE | W1 | battle with intents | timeline/intent DOM present; no DOM rect overlap; phone buttons ≥ 56 px |
| `scen_battle_timing` | BATTLE | W1 | `tim=perfect` | "완벽" popup, hitstop frame, guard shield shot |
| `scen_battle_break` · `_react` · `_combo` | BATTLE | W1 | scripted seeds | event log has `cancel` after `break`; 감전 popup; both rigs inside frame on the two-shot |
| `scen_battle_trial_*` · `scen_battle_parts` | BATTLE | W2 | each trial rule; part targeting on phone | modifier events present; tapping a marker targets the part; `onBreak` fires |
| `scen_battle_boss_danha` · `_recordia` · `_letheon` | BATTLE | W3 | boss with `tim=perfect`, forced phase 2 | phase event at 50 %; 레테온 erase sequence; 개임 restores timeline 3 turns; with assist, auto-restore after 4 turns (no soft-lock) |
| `scen_capture_field` · `scen_capture_pulse` | BATTLE | W2 | throw at a sleeping 솜구름 from behind; battle crystal | lock-on + parabola + pulse ring + close-up shot; success with seed |
| `scen_game_migrate` | GAME | W1 | 3 v1 JSONs | `S.v === 2`; party/dex preserved; `act2Ready` after ending; v1 key unchanged |
| `scen_game_region` | GAME | W1 | boundary → sky → ferry → sky → boundary × 2 | geometries/textures within +5 % of baseline; errors 0 |
| `scen_game_gate` | GAME | W1 | ascent with `__gfx.slowBuild(3)` | tunnel extends; max frame gap < 5 × median |
| `scen_game_ch01` · `_ch2` · `_ch3` | GAME | W1→W2 | chapters with debug jumps + `tim=perfect` | quest steps advance; key shots (snow, title card, ferry / trial, rise / royal rise) |
| `scen_game_flighthud` (+ `mobile_`) | GAME | W1 | glide and ride HUDs | buttons inside viewport; no overlap |
| `scen_game_album` | GAME | W1 | album with snapshots; then `failIDB` | cards show snapshots; with `failIDB` faded cards, no errors |
| `scen_game_arts` · `_rest` · `_map` | GAME | W2 | each art on its object; rest scene; map | prompts visible; petting changes expression; stop list correct |
| `scen_game_whiteout` · `_heart` · `_ending` · `_postgame` · `_postcards` | GAME (+RENDER) | W3 | quiz from fixture save; heart UI PC + phone; ch 9 → credits; postgame loop; postcard pose | 3 answerable questions (legacy fallback works); proof ≥ 2 → acknowledgment; credits reached, errors 0; `S.cards[id]` written |

### 7.4 Common regression at every milestone (lead)

`scen_smoke` (desktop, `mobile_`, `LOW=1`), `scen_story`, `scen_zoo`, `scen_battle`, `scen_regress_look`, `scen_ext_requests`, `scen_game_region`, `scen_render_tiers`, all node tests. A milestone is not committed with a red regression.

### 7.5 Real-device checklist (lead, outside the harness)

Mid-range Android and an iPhone: 60 s open-sky flight frame pacing on low (30 fps, no hitch > 100 ms), 10 min thermal (tier step-down message at most once), first boot without/with cache (§9.4), timing-ring feel with touch +30 ms, phone layouts in portrait for battle, flight, heart UI, photo mode.

---

## 8. Acceptance summary per workstream

Acceptance is listed on each stream card (§4.3–§4.5) and defined in §7.3. In addition, every stream at every milestone must show: own files pass `check.sh`; own node tests pass; own scenarios `ERRORS: none` on desktop, `mobile_` and `LOW=1`; no new external request; no regression in §7.4 attributable to its files; `docs/HOOKS.md` rows it raised are closed or carried with the lead's approval.

---

## 9. Performance budgets

### 9.1 Tier table (`Q.f` and `Q.budget`)

| | low | mid | high | ultra |
|---|---|---|---|---|
| Target devices | low/mid phones | high-end phones, tablets, weak laptops | typical PC | strong GPU (opt-in) |
| Frame target | **30 fps fixed pacing** (60 selectable) | 45–60 | 60 | 60 |
| Render path | direct, grade folded into tone mapping (today's low path) | composer: bloom ¼ + final | + GTAO half-res + DOF (bust/photo) | same as high, larger counts |
| MSAA | default AA | 2 | 4 | 4 |
| Pixel ratio (DRS range) | 0.75–1.25 | 1.0–1.5 | 1.25–2.0 | device (≤ 2) |
| Shadows | 1024, 60u, lead + acting unit cast only | 1024, 90u | 2048, 120u, PCFSoft | 2048, 120u |
| Visible tris / draw calls | 150k / 140 | 250k / 180 | 450k / 260 | 900k / 400 |
| Shader programs per region | 45 | 55 | 70 | 90 |
| GPU memory est. / max texture | 256 MB / 512 | 320 MB / 1024 | 512 MB / 1024 | 768 MB / 2048 |
| Sculpt cell multiplier | × 1.45 | × 1.2 | × 1.0 | × 0.85 |
| Animated spirit rigs (LOD0/1) | 6 | 8 | 12 | 16 |
| Ecology spawn / despawn radius | 40 / 50u | 50 / 60u | 60 / 75u | 70 / 90u |
| Fur shells (designated species) | 0 (rim fuzz) | 4 | 6 | 8 |
| Hair edge cards (hero tier only) | 0 | 0 | 8 | 12 |
| Cornea mesh + lash cards | bust shot only | yes | yes | yes |
| Face-shadow threshold map, brows through hair | no | no | yes | yes |
| Cloud sea rings × azimuths / shadow steps / layers | 32 × 64 / 2 / 1 | 40 × 80 / 3 / 2 | 48 × 96 / 4 / 2 | 48 × 96 / 6 / 3 |
| Cumulus impostors | 12 | 18 | 24 | 40 |
| Waterfall ribbons (falls) | 12 | 16 | 20 | 24 |
| Crystal mode | emissive | env refraction | + interior parallax | + interior parallax + sparkle |
| Crystal pillars (grove) | 200 | 280 | 360 | 600 |
| Oblivion spheres (`OBL_N`) | 2 | 4 | 4 | 4 |
| Particle cap | 600 | 1,000 | 1,500 | 2,400 |
| Rain streaks / festival kites | 300 / 40 | 500 / 60 | 700 / 80 | 1,200 / 120 |
| Region build target | ≤ 2.5 s | ≤ 2.0 s | ≤ 1.8 s | ≤ 1.2 s |

### 9.2 Per-scene budgets (share of the tier total)

| Scene | low | high | Notes |
|---|---|---|---|
| Battle | ≤ 60k tris, ≤ 60 DC | ≤ 220k, ≤ 130 | arena merged static; only the acting unit at LOD0 on low; partner rig LOD1 on low |
| Open-sky flight | cloud sea ≤ 8k tris; 7 mid-LOD islands ≤ 42k; mount + rider ≤ 30k; ≤ 140 DC total | ×3 | shadows follow the player within 60/120u; far islands use baked AO only |
| Landed island | ≤ 150k, island static ≤ 60 DC (32u chunks) | ≤ 450k | point lights ≤ 4 per region + 1 dialogue key light |
| Hub (구름나루) | houses ≤ 6 DC, kites 2 DC, lanterns 1 DC | — | `StaticKit` per material |
| Bust shot | +0 DC on low (DOF off) | DOF ≤ 1 ms | face key light, cornea, lashes |
| CPU per frame | JS ≤ 8 ms (of 33 ms) | JS ≤ 6 ms | `Eco` ≤ 1.0 ms, springs ≤ 0.3 ms, `Region.pump` 3 ms in play / 12–16 ms in wipes, Bake fallback 6 / 14 ms |

### 9.3 Memory

GPU per tier as in §9.1; JS heap ≤ 200 MB on low. Residency: `Battle.scene` always (20–40 MB), boundary island **or** open sky (never both), one landed island at high detail (+ one prebuilt neighbour on high/ultra), shared caches with reference counts. `scen_game_region` enforces return to baseline ±5 % after round trips.

### 9.4 Boot and save

First boot: phone ≤ 12 s without cache, ≤ 5 s with cache; desktop ≤ 4 s / ≤ 2 s. `save()` ≤ 5 ms, JSON ≤ 64 KB. Shader warm-up only during wipes and the ascent tunnel.

---

## 10. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Polish pass still landing changes | interface drift on day 1 | Wave 0 waits for its final commit, rebaselines, re-greps §5.8 and edits this plan before agents start |
| Rules/presentation split in `04_battle.js` regresses act 1 | broken core loop | `Battle.v2` flag; damage parity test; old flow ships at M0; `scen_battle` + `scen_story` in every regression |
| `SkinnedMesh` + outline + hair + IK is the largest tech risk, owned by one stream | heroes late or broken | proven on one hero at M0 on the lookdev stage; `World.playerV2` flag keeps the SD hero as fallback; hero F may slip to M2 |
| Blob Worker from `Function.toString` breaks on `file://`, Safari, or closures | stalls on boot | explicit `SCULPT_SRC` list of self-contained functions + init self-test; immediate time-sliced fallback; paint closures applied on the main thread; `failWorker` scenario in every regression |
| IndexedDB unavailable (private mode, `file://`) | no cache, no snapshots | every feature degrades: rebuild meshes, faded cards, download-only photos; `failIDB` scenario |
| Shader compile hitches on phones | stutter on region entry | program budget per region, `compileAsync` in wipes and the ascent tunnel, "빛을 데우는 중" ring only if > 0.8 s |
| Uber-patch migration over polished materials | visual regressions | features are opt-in per asset; legacy materials untouched until their owner migrates them; `scen_regress_look` ±8/10 % |
| OBL chunk changes every material | colour shifts where oblivion is 0 | `#ifdef OBL` only in regions with oblivion; identity verified by regression baselines |
| Ecology cost on phones | frame drops | tier rig caps, LOD2 instancing, AI 8/2 Hz, sleepers every other frame, spawn behind the camera only, `mobile_eco_*` p95 gate |
| Global `World`/`SITES`/`ZONES` state survives region swaps | subtle bugs | `World` stays a façade swapped by `Region.go`; act-1 routines guarded by `Region.id`; round-trip memory test ×2 |
| Timing input on slow devices | unfair windows | rings on `performance.now()`, sounds on the audio clock, `Time.scale = 1` during windows, latency calibration, touch +30 ms, auto timing |
| Balance with 13 types, poise, timing, combos | too easy / too hard | node sims (10k mirror, skill delta), caps (hand ×2.2, defence floor 0.3), difficulty window multipliers |
| GAME stream overload (story, region, save, UI, bond, arts) | late chapters | data-driven quests/legend events; photo UI moved to RENDER in W3; map/side-quest valves; cut order §11 |
| ISLES stream in W2 builds four islands | late M3 | shared generator + kit; 뇌운첨탑 can shrink to ring + landing disc (cut order) |
| 6.8-head people look small on screen | heroes read poorly | hair volume, silhouette props, bust shots, camera 10u, screen-space outlines, face key light |
| Resemblance to existing creature IP | reputation/legal | D§20 checklist, silhouette review by 2 reviewers before a design is built |
| Save migration failure | lost progress | v1 key never written; validate + restore; 5 fixtures round-trip in node |
| Slow SwiftShader harness | verification bottleneck | lookdev stage, contact sheets, ≤ 3 shots per scenario, probes instead of pixel diffs, node for rules |

---

## 11. Cut and deferral order

If a milestone gate is at risk, cut from the top (matches D§19):

1. Postgame rematches → 4 opponents.
2. Side quests 10 → 6 (`s_courier`, `s_mirror`, `s_whose`, `s_kite_home` later).
3. New spirits 21 → 15 (달메아리, 나이테곰, 지움쥐, 두둥 line later).
4. Starter branch forms 6 → memory branches first, oblivion branches in a later patch.
5. 뇌운첨탑 → storm ring + small landing disc.
6. Named-tier people v2 → keep SD models for named NPCs; hero tier stays.

Never cut: the ascent sequence, oblivion colour-erase + island rise, chapter 5 「백지」, both new legends' phase 2 and heart, open timeline + locked intents + timing, memory-card snapshots, 6.8-head heroes with eye v2 and anime face shading, low-tier 30 fps.
