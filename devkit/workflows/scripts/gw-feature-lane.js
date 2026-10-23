export const meta = {
  name: 'gw-feature-lane',
  description: 'Resume/finish Gwangalli add-on features one by one (2 at a time): build from the saved design doc (research first if missing), test, two-lens review, fix',
  phases: [
    { title: 'Research', detail: 'only for features without a saved design doc' },
    { title: 'Build', detail: 'implement / continue the add-on' },
    { title: 'Test', detail: 'compile, offline tests, studio smoke test + screenshots' },
    { title: 'Review', detail: 'correctness + experience lenses' },
    { title: 'Fix', detail: 'fix confirmed issues, re-test' },
  ],
}
const S = '/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad'
const commonFor = (F, D) => `
# Context (read carefully)
You are one agent in a team building a Roblox game "광안리 (Gwangalli, Busan)". The owner talks Korean; ALL in-game UI text must be natural Korean. The owner's place is "v7". Goal of the whole team: AAA, real-world-like, fun gameplay. Quality bar: what a top Korean Roblox life-sim would ship.

## Repo / rules
- Repo: /home/user/- (git branch claude/car-interior-window-rendering-6i5i62). NEVER run git commit/push/checkout/stash/reset/clean — the orchestrator commits.
- Other agents are concurrently editing other folders. You may ONLY create/edit these paths: ${F.paths.join(', ')} and your scratch dir ${D}/ . Never touch src/StarterPlayer/StarterPlayerScripts/GwangalliBuildingInterior/, README.md, tools/*.py, build/, dist/.
- Rojo layout: folder with init.server.luau = Script, init.client.luau = LocalScript, init.luau = ModuleScript; sibling x.luau files = child ModuleScripts. Require children with require(script:WaitForChild("X")) / require(script.Parent:WaitForChild("X")).
- Everything must be an ADD-ON the owner drops into their existing place: do not require editing existing place scripts. Integrate with existing systems by finding their instances/remotes/modules at runtime (with pcall + timeouts + graceful fallback when missing). Server-authoritative for anything involving money, ownership, saving, other players. Validate all RemoteEvent input (types, ranges, distance, rate limits). Mobile + PC + gamepad friendly UI.
- Use only built-in Roblox content (Parts, UI, built-in rbxasset:// content, and asset ids that already appear in the owner's place). Don't invent random marketplace asset ids — make any external asset id a config field with a working fallback.

## Reference material (read-only)
- Dumped scripts of the owner's v7 place: ${S}/bld/src/<Service>/<Path>.<ClassName>.luau (523 scripts). Index with class + line counts: ${S}/bld/scriptlist.txt.
- The place file itself: ${S}/v7place/place.bin, parsed by python: sys.path.insert(0,'${S}/tools'); from gwpb import GWPB; G=GWPB('${S}/v7place/place.bin'); G.inst is a list of dicts (id, parent, name, class, props...). See ${S}/bld/load.py, tree.py, wsprops.py, shopdump.py for working examples of walking the instance tree and reading properties (CFrame/Size/attributes/tags).
- Map survey notes from earlier agents: ${S}/bld/systems.json (rules: map is read-only, which parts are gameplay, prompts, keep zones), ${S}/bld/shops.json, ${S}/bld/pcbang_karaoke.json, ${S}/bld/hospital_garage.json, ${S}/bld/tags_static.json, ${S}/bld/inv.json. Venue room frames: /home/user/-/tools/venues/rooms.json.
- Our client-side building interior (another team, for awareness only): a LocalScript "GwangalliBuildingInterior" builds AAA decor parts near the player under Workspace.GwInteriorDetailLocal, and LOCALLY hides some map furniture parts it replaces (LocalTransparencyModifier / Transparency=1) and disables SurfaceGuis that are DESCENDANTS of hidden parts. It keeps clear: doors, aisles, table tops (it overlays tables at the exact same top height), seats, counters' staff spot, NPC spots, prompts. So: never parent your GUIs under map parts — put SurfaceGuis/BillboardGuis in PlayerGui with Adornee set. Put your own world models in your own Workspace folder, not inside map shop models. Food/props you place on map table tops will still sit right.

## Tools
- Luau CLI: ${S}/luau/luau (run scripts), ${S}/luau/luau-compile (syntax check: luau-compile --binary file >/dev/null), ${S}/luau/luau-analyze (types; Roblox globals unknown so expect noise).
- A mock Roblox runtime for offline logic tests exists at ${S}/bprev/lib/rbx.luau + datatypes.luau + enums.luau (used by ${S}/bprev/sim.luau — read it to see how to load). Extend copies of it in ${D}/ if you need more API.
- Temp studio = a browser re-implementation of the Roblox engine running the owner's v7 place: base HTML ${S}/v7zip/x/Gwangalli_Studio_v7-1.html (33 MB). Injection pattern: see /home/user/-/tools/build_studio.py (walk(), to_luau(), BUILD with put(tree,parent) using GW.engine.eval) and ${S}/harness/bld.js (playwright: launch chromium with --use-gl=angle --use-angle=swiftshader --enable-unsafe-swiftshader, wait GW.engine.running, eval Luau in server ctx via Sched.runIn(Env.serverCtx, fn), teleport character, page.screenshot). Node + playwright are installed in ${S}/harness (node_modules). Boot takes ~75-120 s. The machine is heavily loaded: ALWAYS run any studio/chromium process under "flock ${S}/.studio.lock <cmd>" with a hard timeout (timeout 1500), only one studio run at a time per your agent, and kill it when done. The engine may lack some newer APIs (new Audio API, TextChatService details): pcall-guard them; test logic there but don't overfit to engine quirks.
`


const EFF = `
## Working efficiently (important)
A session-wide token budget applies to the whole team (an earlier run was stopped by it). Read big files with grep -n and sed -n ranges instead of whole-file dumps, avoid re-reading the same file, keep studio runs few and purposeful (each boots ~2 min), and keep your reasoning focused. Quality is still the priority.
`
const RESUME = `
## Resuming
A previous agent may already have written part of this add-on (an earlier run was cut off by the usage limit). Before writing, list the files under the allowed paths and read what exists; keep and build on good work, finish what is missing, never restart from scratch without reason.
`
const LENSES = [
  { k: 'correctness', p: 'Roblox API correctness (every property/method/event/enum actually exists and is used right, client/server boundaries, replication, memory leaks, connections cleaned up, performance with 30+ players), server security (exploitable remotes, money/ownership duplication, DataStore failure handling, rate limits), and integration safety with the existing place scripts (read the relevant dumped scripts and confirm names/paths/APIs really match).' },
  { k: 'experience', p: "player experience vs the owner's request and a real-world reference: is it fun, rich, AAA, Korean-natural, does every flow actually work end to end (enter → use → leave, mobile touch, PC keys, gamepad), are UI layouts sane at 1280x720 and phone sizes, missing obvious features compared to the real thing, visual quality of built models. Read the screenshots in the feature's shots/ folder too." },
]

const out = await pipeline(args.features,
  async (F) => {
    const D = `${S}/feat/${F.key}`
    const COMMON = commonFor(F, D) + (F.extra || '') + EFF
    if (F.doc) return { F, D, COMMON, design: `The design doc for this feature is ${F.doc} (written by the research agent; read it fully, it has the integration points, contracts and the planned module/remote/UI design).` }
    const r = await agent(`${COMMON}
# Your job: RESEARCH + DESIGN for feature "${F.title}"
${F.research}

Write a thorough design doc to ${D}/research.md (mkdir -p first) containing: (1) exact existing integration points with instance paths, remote names, module APIs and their function signatures you will call, attributes/tags, data-saving and money functions (quote the relevant code lines with file:line), (2) what already exists for this feature in the place and what is missing vs the target, (3) conflicts/risks with existing systems and how to avoid them, (4) the concrete add-on design: file list (under the allowed paths), responsibilities of each module, remotes and their payloads, data schemas, UI screens, and step-by-step player flows. Return a 30-line summary (the doc itself stays in the file).`, { label: `research:${F.key}`, phase: 'Research' })
    return { F, D, COMMON, design: `The design doc for this feature is ${D}/research.md (read it fully). Researcher's summary:\n${r}` }
  },
  async (x) => {
    const { F, D, COMMON } = x
    const build = await agent(`${COMMON}${RESUME}
# Your job: IMPLEMENT feature "${F.title}"
${x.design}
Target (owner's request + orchestrator's spec):
${F.build}

Write complete, production-quality Luau (no TODO stubs, no placeholders) under the allowed paths. Keep files readable (split into modules), with brief Korean or English header comments matching the repo style. When done: every file must pass luau-compile. Return: the file list with one-line purpose each, the install steps for the owner (which folder goes where in Studio, which game settings must be on), config knobs, and anything you knowingly left out.`, { label: `build:${F.key}`, phase: 'Build' })
    return { ...x, build }
  },
  async (x) => {
    const { F, D, COMMON } = x
    const test = await agent(`${COMMON}
# Your job: TEST feature "${F.title}"
The implementer reported:
-----
${x.build}
-----
${x.design}
1. Syntax-check every file you are allowed to touch with luau-compile.
2. Write offline logic tests in ${D}/tests/ using the mock runtime (extend it as needed) for the pure logic: data/serialization, validation, queues/timers, catalog integrity, etc. Run them.
3. Studio smoke test (under flock, see Tools): inject the add-on (server parts into ServerScriptService, shared into ReplicatedStorage, client into the player's PlayerScripts — copy the injection approach of tools/build_studio.py / harness/bld.js into ${D}/studio/), let it boot, check console for errors from your scripts, teleport the character to the relevant place, drive the main flows through remotes/eval, and take at least 6 screenshots of the feature in action (world + UI) to ${D}/shots/NN_name.png. Look at your screenshots (Read tool) and judge them honestly.
4. FIX every bug you find directly in the source (allowed paths only), re-run.
Return: what you tested, results, bugs fixed (file:line), remaining issues, and the list of screenshot paths with one-line captions.`, { label: `test:${F.key}`, phase: 'Test' })
    return { ...x, test }
  },
  async (x) => {
    const { F, D, COMMON } = x
    const reviews = await parallel(LENSES.map((L) => () => agent(`${COMMON}
# Your job: ADVERSARIAL REVIEW of feature "${F.title}" — lens: ${L.k}
Read all files under: ${F.paths.join(', ')}; ${x.design} Test report:
-----
${x.test}
-----
Review strictly through this lens: ${L.p} (screenshots: ${D}/shots/)
Do NOT edit source files. For every issue give: severity (blocker/major/minor), file:line, concrete failure scenario, and the exact fix. Verify each claim against the code before reporting it (no speculative findings). Return the findings list.`, { label: `review:${F.key}:${L.k}`, phase: 'Review' })))
    return { ...x, reviews }
  },
  async (x) => {
    const { F, D, COMMON } = x
    const fix = await agent(`${COMMON}
# Your job: FIX review findings for feature "${F.title}"
Reviews:
-----
${x.reviews.filter(Boolean).join('\n\n=====\n\n')}
-----
For each blocker/major finding: verify it against the code; if real, fix it. Fix minor ones when cheap and clearly right. Then re-run luau-compile on all files and the offline tests in ${D}/tests/. If you changed visuals or core flows, re-run the studio smoke test (under flock) and refresh the screenshots in ${D}/shots/. Return: per finding — fixed / rejected (why); final test status; final file list; final install steps for the owner (Korean); screenshot paths with captions.`, { label: `fix:${F.key}`, phase: 'Fix' })
    return { key: F.key, build: x.build, test: x.test, fix }
  },
)
return out
