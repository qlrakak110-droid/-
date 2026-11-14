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

## 0. UPDATE 2026-11-14 — character modelling finished (Blender pipeline)

After the first handoff the owner asked for "the modelling only" to be completed. Done, with Opus workers (the Fable
window was at ~92 %):

* **Blender asset pipeline is complete** (`tools/blender/`, read its README): rig export (`export_rig.mjs`), the
  `edlib` library (body, garments, cloth draping, lamellar / weave / hair generators, decimation, UVs, Cycles
  bakes, auto-skinning), the compact `.edm` asset format, the runtime loader `src/char/assets.js`, baked-map support
  in the shared character shader, `build_assets.sh <hero|all>`.
* **All three heroes are now Blender-built murim masters in the game** (`tools/blender/heroes/{kael,iska,vorn}*.py`
  -> `assets/chars/<hero>/` -> `src/fighters/<hero>/design.js`): 59.6k / 59.4k / 58.7k triangles, 4 draw calls
  each, `char.update` 0.4-0.6 ms, assets 2.12 / 1.58 / 1.73 MB. Proportions, bones, sockets, weapon lengths and
  grips are unchanged, so the 108 clips still fit. Reports: `handoff/reports/blender.json`.
* The game page is now **~9.6 MB** (`dist/heukil-murim.html`); budget 12 MB.
* Known art gaps (from the art director): hands are blocky up close (`ed.hand()` in `tools/blender/ed/body.py`
  needs a sculpt pass, then a rebuild of all three); ISKA's sleeves hug the arms instead of floating and her veil
  covers the lower face as a net; VORN's face under the hat is a featureless dark head; KAEL's face scarf reads as a
  black hood with a jagged neck edge. Triangles in a duel are ~426k on high (budget 350k).
* Operational notes: the container was killed twice during Blender work (probably memory). Always run Blender
  through `tools/blender/bl.sh` (memory cap) and keep a watchdog like the one in section 5 of the pipeline README /
  this session (kill the largest Blender / Chromium process when MemAvailable < 1.5 GB). Blender must be reinstalled
  on a fresh container (section 2).
* Everything else in the table of section 3 is unchanged (motion pass, VFX / camera, arena, audio, RPG boss /
  enemies / HUD are still interrupted or not started). In section 3, read the "Characters" and "Blender" rows as DONE.

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
