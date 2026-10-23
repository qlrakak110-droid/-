export const meta = {
  name: 'gw-furniture-reskin',
  description: 'AAA client reskin of the shared Furniture catalog used by runtime-built buildings (광안 종합병원, district/Annex units): research, core, per-chunk builders, test, review, fix',
  phases: [
    { title: 'Research', detail: 'catalog, Builder buildings, 종합병원 rooms, contracts' },
    { title: 'Core', detail: 'Reskin.luau scanner/lifecycle + builder API' },
    { title: 'Items', detail: 'per-chunk AAA builders' },
    { title: 'Test', detail: 'side-by-side previews + studio check' },
    { title: 'Review', detail: 'two lenses' },
    { title: 'Fix', detail: 'fix + re-verify' },
  ],
}
const S = '/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad'
const D = `${S}/feat/reskin`
const BI = '/home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliBuildingInterior'
const COMMON = `
# Context
Team project: Roblox game "광안리 (Gwangalli, Busan)"; owner speaks Korean and wants EVERY building interior (shops, hospitals, homes, offices) at AAA quality with item-level detail ("디테일 하나하나 물건 나열된 물건부터 하나하나"), real-world-like, interactive.
Many buildings are built AT RUNTIME by the server (ServerScriptService/GwangalliBuildings: Builder/Core, Builder/Plan, Builder/Units, Builder/Archetypes, Builder/Shops, Builder/Hospital = 광안 종합병원 4F + heliport at site x -704 z 1236, Annex + Annex/Rooms = interiors at Y>2500, Decor, MapIndex) from the shared furniture catalog ReplicatedStorage/GwangalliBuildingsShared/Furniture (Models with attributes ItemId / Colorway, PrimaryPart "Base", front = -Z, tag GwB_Fixture; Interact fixtures with Seats/prompts; Public attribute) plus Kit/Config/Palette/Grades/SignStyles. These look primitive (box furniture). Your team builds a CLIENT-ONLY AAA reskin: for each catalog item near the player, hide the original locally and build a detailed real-world version at the same pose/footprint, keeping every gameplay part working.

## Existing client system you plug into (read these files)
- ${BI}/ = LocalScript GwangalliBuildingInterior: Kit.luau (part builder: K:box/wedge/cyl/vcyl/ball/rbox/slab/panel/text/light..., frame-relative, budget), Look.luau (palette/materials), Props.luau (chairs, stools, tables, counters, lamps, shelves, rows of products, plants, TVs, clocks, fridges, signs ...), Interact.luau (client prompts "GwInteriorPrompt": toggle/cycle/swing/lightSwitch, anim), Scan.luau (Scan.hide(store, part) / Scan.reapply / Scan.restore for LOCAL hiding of map/runtime parts; Scan.laabb; Scan.addWorldKeep), init.client.luau (streams shop interiors; an ADDONS hook requires a ModuleScript named "Reskin" in this folder and calls Reskin.start(ctx) with ctx = { root (Folder Workspace.GwInteriorDetailLocal), focus() -> Vector3?, limits() -> (maxVenues, maxParts, maxLights), dbg, script, Scan }).
- Rules learned from the map survey (keep them): never destroy/move/rename server parts; hide locally only; Seats and table tops get exact-pose overlays (seat top ±0.1 stud, table top same Y and XZ); never cover ProximityPrompts / their anchors; your parts are Anchored, CanCollide=false, CanQuery=false, CanTouch=false; give lights attribute GwIndoorDim=0 and respect a light budget; 1 stud ≈ 0.28 m, character ~5 studs tall.
- Shop interiors built by the main system (T_*.luau) may ALSO cover some runtime shops: if a fixture lies inside a venue currently built by the main system (check Workspace.GwInteriorDetailLocal children's attributes/bounds or a registry the core exposes), skip it to avoid double work.

## Reference material (read-only)
- Dumped place scripts: ${S}/bld/src/<Service>/<Path>.<Class>.luau (index ${S}/bld/scriptlist.txt). Place file ${S}/v7place/place.bin (python: sys.path.insert(0,'${S}/tools'); from gwpb import GWPB). Map survey notes: ${S}/bld/systems.json, shops.json, hospital_garage.json (notes mention 광안 종합병원), hotels_homes.json, districts.json, inv.json.

## Repo rules
- Repo /home/user/- (branch claude/car-interior-window-rendering-6i5i62). NEVER git commit/push/checkout/stash/reset/clean.
- You may create/edit ONLY ${BI}/Reskin.luau and ${BI}/RS_*.luau, plus scratch ${D}/. Other agents edit other files concurrently. If you need a change elsewhere, put the exact diff in your final answer.
- Every file must pass ${S}/luau/luau-compile --binary <file>.

## Tools
- Luau CLI ${S}/luau/luau. Mock Roblox runtime for offline runs: ${S}/bprev/lib/rbx.luau (+ datatypes/enums), see ${S}/bprev/sim.luau. Renderer: ${S}/bprev/preview.js (three.js headless, global semaphore of 3 renders; read its header/usage) — you can render a scene JSON of parts; see how sim.luau exports scenes.
- Temp studio: /home/user/-/tools/build_studio_cabin.py (env BLD_SRC) + ${S}/harness/bld.js on base ${S}/v7zip/x/Gwangalli_Studio_v7-1.html; run under "flock ${S}/.studio.lock timeout 1500 <cmd>" only.
`

phase('Research')
const research = await agent(`${COMMON}
# Your job: RESEARCH
1. Read the Furniture catalog module fully: list EVERY ItemId with what it is, footprint/size, parts it creates, which ones carry Seats / prompts / Interact roles / lights / screens, colourways. 2. Read Builder (Core, Plan, Units, Archetypes, Shops, Hospital) + Annex/Rooms + Decor + MapIndex: how/where buildings and rooms are generated at runtime, which Workspace folders they live in, room names/types (e.g. 원무과, 응급실, 병동 6인실, ICU, 수술실, 사무실, 원룸 ...), how streaming interiors appear/disappear, what attributes identify rooms (so the reskin can also add room-level dressing: ceiling panels, wall rails, signage), which shop types are runtime ShopLife shops. 3. Decide the client discovery strategy (CollectionService GwB_Fixture tag + ItemId attribute, GetInstanceAddedSignal, distance culling) and the builder API. 4. Group the ItemIds into chunks of 10-16 related items (e.g. hospital medical, hospital beds/wards, office, kitchen/restaurant, retail shelves, living room, bedroom, bathroom, lighting, outdoor ...), hospital chunks first.
Write ${D}/research.md and return JSON via the schema: summary (markdown, complete: everything the core and chunk agents need: discovery, folders, attributes, contracts, room dressing plan, per-item notes), and chunks (name, items: [{id, what, notes}]).`, {
  label: 'research:reskin', phase: 'Research',
  schema: { type: 'object', properties: {
    summary: { type: 'string' },
    chunks: { type: 'array', items: { type: 'object', properties: {
      name: { type: 'string' },
      items: { type: 'array', items: { type: 'object', properties: { id: { type: 'string' }, what: { type: 'string' }, notes: { type: 'string' } }, required: ['id', 'what'] } },
    }, required: ['name', 'items'] } },
  }, required: ['summary', 'chunks'] },
})
if (!research) return { error: 'research failed' }
log(`${research.chunks.length} chunks, ${research.chunks.reduce((a, c) => a + c.items.length, 0)} items`)

phase('Core')
const core = await agent(`${COMMON}
# Your job: write ${BI}/Reskin.luau (the core)
Research:
-----
${research.summary}
-----
Implement: start(ctx); discovery of catalog fixtures near ctx.focus() (radius ~60 studs build / 90 drop, re-check at ~2 Hz, budget-aware via ctx.limits(), skip fixtures inside venues the main system has built), per-fixture lifecycle (hide originals with ctx.Scan.hide into a per-fixture store, build replacement in a Model under ctx.root named "Reskin_<ItemId>", restore on drop or when the original is destroyed/changes), exact-pose overlays for Seats and table tops, prompt safety, Colorway → palette mapping, a builder registry: Reskin.register(itemId, fn) where fn(K, info) builds with a Kit instance whose frame = the fixture's Base pivot (front = -Z of the catalog → convert to Kit's convention, document it), info = { model, base, size, colorway, itemId, detail = 'high'|'mid'|'low', interact = Interact module, look = Look, props = Props }; it auto-loads every sibling ModuleScript whose name starts with "RS_" (each returns { [itemId] = fn }). Also room-level dressing hooks if the research found room identities (Reskin.registerRoom(kind, fn)). Fallback: items without a builder are left as-is. Write a short API section at the top of the file. Must compile. Return the API contract text exactly (to be given to the chunk agents).`, { label: 'core:reskin', phase: 'Core' })

phase('Items')
const items = await parallel(research.chunks.map((c, i) => () => agent(`${COMMON}
# Your job: AAA builders for chunk "${c.name}" → write ${BI}/RS_${String(i + 1).padStart(2, '0')}_${c.name.replace(/[^A-Za-z0-9]/g, '').slice(0, 24)}.luau
Core API contract (from ${BI}/Reskin.luau — read the file too):
-----
${core}
-----
Research notes: ${D}/research.md
Items in this chunk:
${c.items.map((it) => `- ${it.id}: ${it.what}${it.notes ? ' — ' + it.notes : ''}`).join('\n')}
For each item: read its original construction in the Furniture catalog (exact footprint, seat/top heights, prompt/seat parts), then build a real-world, item-level detailed version (e.g. a hospital bed = electric bed frame with side rails, bumper wheels with brakes, mattress with sheet + pillow, control pendant, IV pole hook, chart holder; a vending machine = lit product rows with labels and prices, coin/card slots, out tray...), at the same footprint, keeping seats/tops at exact heights, 3 detail levels (high/mid/low part counts, e.g. ≤ 120/60/25 parts), Colorway-aware materials, sensible client interactions where real (lamp on/off, drawer/door swing, TV channel, monitor screens animated) using Interact helpers. Render previews of at least the 4 most visible items (offline sim + preview.js) and look at them; iterate until they look right. Must compile. Return: item → status, part counts, preview image paths.`, { label: `items:${c.name}`, phase: 'Items' })))

phase('Test')
const test = await agent(`${COMMON}
# Your job: TEST the reskin end to end
Core: ${BI}/Reskin.luau; chunk modules ${BI}/RS_*.luau. Chunk reports:
-----
${items.filter(Boolean).join('\n\n---\n\n').slice(0, 60000)}
-----
1. Compile all. 2. Offline: build every catalog item original (run the Furniture catalog constructor on the mock runtime, extending it in ${D}/ as needed) and its reskin; check footprints/top heights/seat heights match, part counts within budget, no errors; render a contact sheet of before/after pairs to ${D}/shots/sheet_*.png and look at it. 3. Studio (under flock): inject the building interior (BLD_SRC) and visit 광안 종합병원 (site x -704 z 1236; find the built interior at runtime via eval) and one Annex/district unit; screenshots ≥ 8 to ${D}/shots/; check console for errors. Fix bugs directly in Reskin.luau / RS_*.luau. Return results, fixes, remaining issues, screenshot list.`, { label: 'test:reskin', phase: 'Test' })

phase('Review')
const LENSES = [
  { k: 'correctness', p: 'API correctness, never breaking server gameplay parts (Seats, prompts, Interact fixtures, ShopLife desks, beds used by hospital systems), hiding/restoring correctness with streaming and server rebuilds, performance (scan cost, parts, lights) on phones, memory leaks.' },
  { k: 'experience', p: 'AAA realism and item-level detail vs real-world references, scale/orientation errors, style consistency with the rest of the interiors, interaction quality; look at ' + D + '/shots/ and the chunk previews.' },
]
const reviews = await parallel(LENSES.map((L) => () => agent(`${COMMON}
# Your job: ADVERSARIAL REVIEW — lens ${L.k}
Read ${BI}/Reskin.luau and ${BI}/RS_*.luau and this test report:
-----
${test}
-----
Lens: ${L.p}. Do not edit. Verified findings only: severity, file:line, failure scenario, exact fix.`, { label: `review:reskin:${L.k}`, phase: 'Review' })))

phase('Fix')
const fix = await agent(`${COMMON}
# Your job: FIX review findings and re-verify
-----
${reviews.filter(Boolean).join('\n\n=====\n\n')}
-----
Fix real blockers/majors and cheap minors in Reskin.luau / RS_*.luau, re-compile, re-run the offline checks and (if visuals changed) refresh shots. Return per-finding outcome, final status, screenshot list with Korean captions, and any exact diff needed outside your allowed files.`, { label: 'fix:reskin', phase: 'Fix' })

return { chunks: research.chunks.map((c) => c.name), core: core && core.slice(0, 3000), test, fix }
