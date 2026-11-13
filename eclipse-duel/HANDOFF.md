# HANDOFF — 「흑일무림 黑日武林」 (code name ECLIPSE DUEL)

Written 2026-11-13 ~10:00 UTC, when every work team was stopped because the Fable usage limit reached ~92 %
(the owner asked for a stop at 95 %). This file is what the next session (or person) needs to continue.

* Repository: `qlrakak110-droid/-`, branch **`ccr-ef47419d-m8730x`** (everything is committed and pushed).
* Project folder: `eclipse-duel/`. Playable build: `eclipse-duel/dist/heukil-murim.html` (same as `dist/eclipse-duel.html`).
* Published page (private): https://claude.ai/artifact/B4C3pYGNipDugPLq5VER3D
* Owner's language: Korean. Owner's wishes so far, in order: spectacular skill VFX and motion "at Elden-Ring level, AAA";
  a NEW original game (fighting-game base); rigging perfect and motion natural ("hundreds of rigging tasks"); 60 fps;
  then an **RPG feel**, a **murim (무림) restyle**, precise modelling / motion ("use Blender or whatever"), and
  finally: stop at 95 % of the Fable limit, integrate, deliver a downloadable file and this handoff.
* Originality rule (hard): nothing from an existing game / novel / comic — names, characters, designs, UI, sects.

## 0. Session 2 update (2026-11-13, after this file was first written)

Branch is now **`ccr-030f3ed5-ileijo`** (fast-forwarded from `ccr-ef47419d-m8730x`; push there). Published page (private,
new URL: the old artifact could not be opened from the new session): https://claude.ai/artifact/8oCd4M7m2dRjBXZxNqUWiG
(republish `dist/eclipse-duel.artifact.html` from the same session to keep the URL).
Usage reading at the end of this session: `seven_day_overage_included.utilization` ≈ 0.76 (single agent ≈ +1 % per 8 min).

Done in session 2 (one agent, no fan-out):

| area | what changed |
|---|---|
| RPG boss `src/rpg/boss/` | **「흑일마신상」 is in**: `design.js` (husk rig + crown helm, black-sun halo, skirts, great saber), `clips.js` (`rpg.idol.*`: idle, walk, sweep, cleave, thrust, stomp, eclipse, combo, enrage, wake, kneel, death; key times = frame data, shared table `T`), `index.js` (attacks with travelling hit sectors, AI by distance / bearing, phase 2 at 55 % HP, poise break = 3.4 s kneel, marker VFX, intro camera, death). |
| RPG enemies `src/rpg/foes/` | 흑일교 무사 (`cultist`) and 호법 (`protector`): husk rig + bamboo / iron hat, robe, sash; two encounters. They still use the `demo.*` clips (no bespoke motion yet). |
| RPG world `src/rpg/world/` | 정심석 (boulder, cairn, incense wisp, motes) and a low boundary-stone gate with ground mist (nothing tall: it never hides the fight). The arena itself is still the duel's 250° set. |
| RPG HUD `src/rpg/ui/` | The core's debug HUD wrapped with **touch controls** (move stick, camera drag, ink-seal buttons; portrait and landscape). `.rpgt` needs `pointer-events:auto` (`#ui` is `none`). A real brush HUD, progression screen art and banners are still the debug ones. |
| Post `src/post` | **Glare limiter** (`tLum` = smallest bloom level, `uGlare`): bloom compression + exposure dip when HDR light floods the frame; the ultimates no longer burn out. |
| **Mobile GPU** | A real Android phone showed a hero-shaped white blob with black specks: NaN pixels (GLSL `pow(x, y)` with `x < 0` is NaN on mobile, not on SwiftShader) clamped to 48 by the bloom prefilter. Fixed blind: `tools/safepow.py` rewrote all 73 GLSL `pow()` calls (`pow(X, 2.0)` -> `X * X`, others `pow(max(X, 0.0), Y)`), NaN scrubs in the bloom prefilter, the composite, the character material (`opaque_fragment`) and the ghost shader. **Not yet confirmed on the device.** New shaders must follow the same rule. |
| Tests | `src/rpg/tests/boss.mjs` (sheets per attack: `SECTION=sweep SIDE=1`), `loop.mjs` (whole expedition with the bot: passes, victory at ~400 s in god mode), `touch.mjs` (touch smoke test, run with `--touch --size 844x390`). |

**Blender asset path (works end to end, session 2):** `/opt/blender-env/venv/bin/python tools/blender/heroes/idol.py [--preview]`
models the boss on the exported rig (`node tools/blender/export_rig.mjs idol --design src/rpg/boss/rigdesign.js#idolRig --no-poses`)
and writes `src/rpg/boss/idol.edb` (EDB1: rigid pieces per bone, per-vertex colour / cavity (ray-cast AO) / glow; 137 pieces,
78k triangles, 1.2 MB; esbuild loader `.edb: binary`), decoded in `src/rpg/boss/design.js` into `kit.add` pieces. 8 s per
run; `src/rpg/tests/bossmodel.mjs` = in-engine review sheet. The same path (rigid pieces + the kit's skinned under-body)
is the cheapest way to re-dress the cultists and, with `ed/skin.py` for soft parts, the heroes. `ed/cloth.py`, `ed/bake.py`
and the older EDM1 loader still do not exist.

The Blender code is now `tools/blender/rigidkit.py` (helpers + decimate + bake + EDB1 writer) with one script per
character in `tools/blender/heroes/` (`idol.py`, `cultist.py [--elite]` -> `src/rpg/foes/cultist.edb` / `protector.edb`,
12.5k / 14k triangles, rig `cult`); the decoder is `src/rpg/edb.js`; `src/rpg/tests/foemodel.mjs` reviews the enemies.

**Cinematics (session 2):** `src/rpg/cine.js` (`sequence(ctx, world, shots, opts)`: cut-based world shots, letterbox,
depth of field, blend back) drives the boss intro (blade tip -> mask as the eyes kindle -> low from behind the hero),
the phase-2 roar, the boss death (slow arc, then a low wide shot) in `src/rpg/boss/index.js`, and the hero-death lift in
`src/rpg/world/index.js`. Sheets: `SECTION=intro|enrage|death` of `src/rpg/tests/boss.mjs` (+ `CAM="back,h,z,lookH,fov"`
for a fixed three-quarter view of any attack).

**Motion capture (session 2):** `python3 tools/mocap/extract_run.py tools/mocap/09_01.bvh` turns a CMU run capture
(mocap.cs.cmu.edu, subject 9; free for any use; the database was created with funding from NSF EIA-0196217) into phase
curves `src/rpg/core/clips/mocap_run.js`; `locomotion.js` drives pelvis bounce / sway / surge / list / twist, trunk
counter-rotation, head and the free arm of every hero's run and sprint from them (phase-warped onto the hero's own
planted foot keys; gait test: worst slide 1.6 cm). `src/rpg/tests/runsheet.mjs` = side / rear run sheets. The CMU mirror
`raw.githubusercontent.com/una-dinosauria/cmu-mocap` is reachable from the cloud environment: walks, turns, hit
reactions and deaths can be extracted the same way. The 108 duel clips are still hand-keyed. `extract_run.py <bvh> walk` (subject 7) gives `mocap_walk.js`;
`locomotion.js` exports its gait builder `run()` (params `mocap`, `mocapStance`, `rootScale` for scaled actors, `kick`), and
`src/rpg/foes/index.js` builds the cultists' stalking walk and run with it (`rpg.cult.*`, `rpg.prot.*`; sheet: `foegait.mjs`).
Boss / enemy `plate` materials are `side: 'double'` (open shells are seen from inside).

Still open, in the order I would take them: confirm the phone rendering; bespoke clips for the cultists; a real RPG HUD;
360° arena; murim hero models (Blender pipeline) and the 108-clip motion pass; audio re-voice; per-tier performance on
real hardware. Sections 3-4 below are the state BEFORE session 2 (the RPG rows are superseded by the table above).

## 1. Read these first

| file | what it is |
|---|---|
| `MURIM.md` | **Binding art direction** (supersedes older wording everywhere): world, heroes, names, arena, VFX / audio language, the RPG mode's vocabulary. |
| `CONTRACT.md` | Engineering contract: conventions, budgets, quality tiers, 60 fps rules, module APIs and ownership, the RPG mode section, the post pipeline section. |
| `src/fighters/MOVES.md`, `BALANCE.md` | Move design, frame data, markers, ultimate storyboards (names already murim). |
| `src/fighters/MOTION.md` | Motion bible draft + per-clip notes (the motion director was interrupted: incomplete). |
| module READMEs | `src/{post,char,char/kit,vfx,cam,env,audio,ui,input,game,game/logic,rpg}/README.md`. |
| `handoff/reports/*.json` | Final reports of every agent that finished in round 3 and the list of interrupted ones; rig audit findings (round 1 / 2). |
| `handoff/workflows/*.js` | The exact orchestration scripts (briefs) of the round-3 teams, ready to relaunch. |

## 2. Build, run, test

```sh
cd eclipse-duel
npm install                                   # esbuild 0.24, three 0.170 (already vendored in node_modules on the old container)
node tools/build.mjs game                     # -> dist/eclipse-duel.html (+ .artifact.html fragment); copy to dist/heukil-murim.html
node tools/build.mjs game --as mine           # private copy build/mine.html (parallel teams must use this)
node tools/shot.mjs game --no-build --hash "demo=kael,iska,hard&seed=7" --at 5,10,15,20 --sheet 2 --sheet-only --out shots/x/demo
node tools/shot.mjs game --hash "rpg=kael&rpgbot" --at 4,9 --sheet 2 --sheet-only --out shots/x/rpg   # RPG mode, autoplaying hero
node src/game/logic/test/run.mjs               # rules engine: 95 tests + fuzz + soak
node tools/shot.mjs rigqa --eval "__ED.lab.play('all')"   # rig regression suite (476 checks passed at the last run)
```

URL flags: `#demo=a,b[,diff]`, `#fight=a,b`, `#training=a,b`, `#rpg=kael|iska|vorn`, `#rpgbot`, `#seed=N`, `#q=low|mid|high`,
`#fps=`, `#fpsmeter`, `#prof`, `#test`. Test APIs: `window.__ED`, `__ED.game`, `__ED.rpg`.
Captures run in headless Chromium with SwiftShader (CPU): **GPU frame time has never been measured**; 60 fps on real
devices is unverified (use `#fpsmeter` on a phone / laptop).

Blender (optional, for the precision character pipeline): `python3 -m venv /opt/blender-env/venv &&
/opt/blender-env/venv/bin/pip install bpy==5.3.0` (Python 3.13; ~1.1 GB). Verified headless: modifiers, cloth
simulation, bone-heat auto weights, Cycles CPU baking high -> low (≈15 s per 1024 px map), glTF export. No GPU: no EEVEE.

## 3. State of the game (what the integrated build contains)

Verified at integration: the build boots with no page errors; title, a seeded CPU duel and the RPG mode were captured
(`shots/integ/`). Human-input tests were not re-run after integration.

| area | state |
|---|---|
| Duel game (title → select → VS → rounds → K.O. → result) | Complete and playable (keyboard / mouse / touch); 3 fighters with full move sets, 108 clips, skill + ultimate choreography. |
| Murim names + UI (`src/ui`, registry, moves display names, MOVES.md) | **Done** (team finished): title 「흑일무림」, hero cards (염무강 / 설리화 / 뇌진천), VS, brush HUD, announcer cards. |
| Render pipeline round 3 (`src/post`, `src/core/app.js`) | **Done**: scene depth, AO, height / distance fog, light shafts, DOF API, grading presets, ink impact frames, fitted shadows, per-tier costs. |
| Rig (`src/char` runtime) | Round-2 fixes **done** (rigqa 476 / 0). Round-3 re-audit interrupted. Open: body-capsule intersections of the fighter clips rose 5–18 % after the fixes; ISKA blade aim off its keys in many frames (needs `gripAngle` / `edgeRoll`). |
| Arena → 「천무대」 (`src/env`) | **In progress, interrupted**: stone lanterns, tile roofs, guardian statues partly in; atmosphere stage (mist, shafts hooks, wind) not started. Review every angle before trusting it. |
| VFX murim restyle + white-out fixes (`src/vfx`, `src/game/feel.js`, `src/fighters/*/present.js`) | **Interrupted** mid-way. Known: over-strong chroma fringing on some heavy hits; ISKA crystal_procession hit near-white frame. |
| Cinematography (`src/cam`) | **Interrupted**: DOF-driven shots and wuxia shots partly in (K.O. focus works). |
| Audio murim re-voice (`src/audio`) | **Not started** (was queued). Audio has never been listened to by a human. |
| Characters | **Still the old knight designs in game.** Murim material library + kit pieces (`src/char/materials.js`, `src/char/kit`) interrupted near the end (mannequin line-ups in `shots/murim/chars/kit/`). |
| Blender character pipeline (`tools/blender`, `assets/`, `src/char/assets.js`) | **Interrupted early**: `edlib.py`, `export_rig.mjs`, `rigs/`, first assets exist; loader / pilot not verified. Heroes not started. |
| Motion pass (`src/fighters/MOTION.md`, `src/game/clips.js`, `src/game/actor.js`) | **Interrupted** in the director stage (bible, harness, variant system partly written; one reference clip reworked). The 108-clip rework did not start. |
| RPG mode 「강호행」 (`src/rpg`) | Core **interrupted late**: third-person lock-on combat, hero controller for 3 heroes (chain, heavy, skills, ultimate, roll, pills), test enemies, bot, debug HUD work. Boss, cult enemies + encounters, 360° world, real HUD + progression: **not started**. |

Budgets at integration (high tier, duel): 68 draw calls, ~424k triangles (budget 350k: over), 60 shader programs,
24 post passes. Ultimates peak higher (afterimage ghosts copy whole characters; capped per tier).

## 4. How to continue (recommended order)

Each step has a ready brief in `handoff/workflows/`. They were written for the Workflow tool (agent / parallel /
phase); the prompts are self-contained and can also be given to single agents. Completed stages are in
`handoff/reports/` (cached results do not survive a new session: skip those stages by hand or let them re-run).

1. **Stabilise**: build, run the rules tests, rigqa, a `#demo` capture per pairing and `#rpg` for each hero; fix any
   half-finished edit left by an interrupted team (most likely in `src/env`, `src/vfx`, `src/game/clips.js` /
   `actor.js`, `src/char/materials.js`, `src/rpg/core`).
2. **Characters via Blender** — `ed-blender-chars-*.js`: finish the pipeline stage (rig export, asset format,
   runtime loader, pilot on the vorn rig), then one artist per hero, then review. Never change proportions, bones,
   sockets, weapon lengths or grips (108 clips depend on them). The older `ed-murim-chars-*.js` (kit-code heroes) is
   superseded by this, except its material-library stage.
3. **Motion** — `ed-murim-motion-*.js`: director (bible, harness, variants) → one animator per hero reworks all
   clips and adds ≥15 each → review. Frame data and timings are law.
4. **World** — `ed-murim-world-*.js`: finish the 천무대 arena (360° for the RPG mode, exported colliders), the audio
   re-voice, then the atmosphere stage on the new post features, then the check. (The identity / UI stage is done.)
5. **Effects + camera** — `ed-graphics-r3b.js` from its Layer phase (murim VFX, cinematography), then the
   graphics director.
6. **RPG mode** — `ed-rpg-b.js` (murim override included): finish the core, then boss 「흑일마신상」, cult enemies +
   world, HUD + progression in parallel, then the playtest director.
7. **Rig** — `ed-rig-r3b.js` from the round-3 audit; then the motion-QA tool over all clips (`tools/clipqa.mjs`,
   `src/char/QA_REPORT.md` do not exist yet).
8. Final: per-tier performance pass on real hardware, final build, republish the artifact (same URL: publish
   `dist/eclipse-duel.artifact.html`).

## 5. Working rules that mattered

* One owner per file set; parallel teams never edit another team's files (see CONTRACT.md ownership + each brief).
* Parallel teams must build with `--as <name>` (private `build/<name>.html`), never plain `build.mjs game`.
* The container has 4 cores: more than ~6 agents with headless-Chromium captures saturates it (load 50–90, captures
  take minutes). Prefer fewer concurrent teams.
* Usage: with ~10 Fable agents running, the Fable weekly window rose ~2 % per minute. The reading is in the session
  metadata: `rate_limit_event` → `unifiedWindows.seven_day_overage_included.utilization` (list this session's events
  filtered to `rate_limit_event`). Check it before launching anything large.
* Commit messages end with the `Co-Authored-By` + `Claude-Session` lines; push only to `ccr-ef47419d-m8730x`; no PR
  unless the owner asks.
