export const meta = {
  name: 'gw-hospital-plus',
  description: 'Hospital (광안 메디컬 의원): working doors, real restrooms, elevator 1F/2F/roof, exits, ER entrance, rooftop garden — research, build, test, review, fix',
  phases: [
    { title: 'Research', detail: 'geometry of every door/wall/stair/roof, server contracts, anti-teleport checks' },
    { title: 'Build', detail: 'HospitalPlus modules' },
    { title: 'Test', detail: 'sim previews + studio walkthrough with screenshots' },
    { title: 'Review', detail: 'correctness + experience lenses' },
    { title: 'Fix', detail: 'fix and re-verify' },
  ],
}
const S = '/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad'
const D = `${S}/feat/hospital`
const BI = '/home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliBuildingInterior'
const COMMON = `
# Context (read carefully)
Team project: Roblox game "광안리 (Gwangalli, Busan)", owner speaks Korean (all in-game text natural Korean). The owner asked (Korean): "병원도 내부 구현해 나갈수 있는 문이랑 등등 다 구현해서 AAA급 시설 퀄리티" = the hospital must have a fully realised interior with doors you can actually go through/exit by, everything implemented, AAA facility quality. Target building: 광안 메디컬 의원 = Workspace.Gwangalli.hospital['광안 메디컬 의원'] (2 floors, static map, rotated ~178.1 deg about Y, facade faces -Z at z~264).

## What already exists / who does what
- Client LocalScript GwangalliBuildingInterior (folder ${BI}/): builds AAA decor near the player under Workspace.GwInteriorDetailLocal using Kit.luau (part builder in a room frame; parts overlapping keep-zones are dropped), Look.luau (materials/palette), Props.luau (furniture/fixtures), Interact.luau (client ProximityPrompts "GwInteriorPrompt", R key, toggle/cycle/swing/lightSwitch helpers, anim at 10 Hz), Scan.luau (room fitting, keep zones, local hiding of map parts: Scan.hide/reapply/restore), Venues.luau (room specs from tools/venues/rooms.json, incl. 11 hospital rooms), Common.luau. READ these files to reuse their helpers.
- ANOTHER agent is concurrently writing ${BI}/T_clinic.luau (the furniture/fixture dressing of the 11 hospital rooms: lobby, waiting, consult, pharmacy, treat, hall, ward, nurse, lounge, checkup). You must NOT edit T_clinic.luau (read it for awareness). Your work is the "facility" layer: doors, passages, elevator, new rooms, exits, roof.
- Addon hook (already in init.client.luau): modules named "HospitalPlus" (and "Reskin") in ${BI}/ are required at startup and A.start(ctx) is called with ctx = { root (Folder GwInteriorDetailLocal), focus() -> Vector3? (player/camera position), limits() -> (maxVenues, maxParts, maxLights), dbg(...), script, Scan }. HospitalPlus must register its world keep-zones synchronously at module top level (no yields before) with Scan.addWorldKeep(minWorld: Vector3, maxWorld: Vector3, kind) so that T_clinic and other room builders keep those spaces clear.
- Survey of the hospital by an earlier agent: ${S}/bld/hospital_garage.json (read the 3 hospital venue entries + notes: exact parts, gameplay contracts that must not break, NPC SPOTS/corridors, door positions: restrooms 남/여 x -564/-570, STAFF ONLY x -528, 창고 x -538 on the 1F back wall (z~337-340), fake elevator x -548 z 337.6 (no 2F door), fire exit x -456.8 z 331.5, stair 1F->2F x -497..-519 z 325-336, roof (Roof y~32.1, parapet, Penthouse 9.5x9x10 with solid RoofDoor), ambulance bay east of the building (x -453..-431, z 268..306) with no door). Raw per-instance dump: ${S}/bld/hg/dump.json (pos/rot/size/material/colour/attrs/tags/parent), trees hosp_tree.txt/h2f.txt.
- Dumped place scripts: ${S}/bld/src/<Service>/<Path>.<Class>.luau (index ${S}/bld/scriptlist.txt). Relevant: ServerScriptService/GwangalliDoors (AutoDoor contract), Law/Hospital NPC life (walk grid built from SERVER parts; teleports NPCs to lift1/lift2), GwangalliGameplay/Health (HospitalPrompt, HospitalBed, nearClinic), any anti-exploit / position checks.
- Place file: ${S}/v7place/place.bin (python: sys.path.insert(0,'${S}/tools'); from gwpb import GWPB; G=GWPB(path); G.inst list of dicts). Workspace/StreamingEnabled and other properties can be read there.

## Repo rules
- Repo /home/user/- (branch claude/car-interior-window-rendering-6i5i62). NEVER git commit/push/checkout/stash/reset/clean (the orchestrator commits).
- You may create/edit ONLY: ${BI}/HospitalPlus.luau and new files ${BI}/Hosp_*.luau (sub-modules, required via require(script.Parent:WaitForChild("Hosp_X"))), plus your scratch dir ${D}/ and preview fixtures under ${S}/bprev/fx/hosp_* if needed. Do not edit any other file in the repo (if you truly need a change in Kit/Props/Scan/Interact/init, describe the exact patch in your final answer instead).
- Luau: --!strict style like the other modules; must pass ${S}/luau/luau-compile --binary <file>.

## Design rules for this facility layer
- Client-only (LocalScript world), like the rest of the building interior: other players/server unaffected. EXCEPTION vs the decor rule: real rooms/walls you build here MAY be CanCollide=true locally (the local character is client-simulated so it collides) — needed for real rooms. Never block server gameplay parts, prompts, NPC SPOT corridors (listed in the survey), or the stairs.
- Map is read-only: never destroy/move/rename map parts; to replace a fake door, hide it locally (Scan.hide) and draw your own door leaves; keep its collision unless you provide the passage.
- Passages: (a) IN-PLACE rooms where space exists inside the building (the west end of the 1F back hall x -575..-555, z ~323..338 is empty — ideal for real 남/여 화장실 with doors facing the hall), (b) PORTAL rooms: door opens → short fade (ScreenGui in PlayerGui) → the local character is moved (HumanoidRootPart CFrame / PivotTo) into a client-built room at a hidden location → the room's door brings you back in front of the original door. Use (b) for STAFF ONLY 직원 휴게실 and 창고 and the elevator cabin. Pick hidden locations that cannot collide with anything (check place.bin bounds and the Annex interiors at Y>2500 used by GwangalliBuildings/Annex — choose a unique area, e.g. far below/above, and document it). (c) THROUGH-WALL exits: 비상구 (fire exit) and a new 응급실 출입구 on the east wall facing the ambulance bay (into the 주사실/처치실, near TreatBed1 at -465.3,308.6): matching door leaves inside and outside, push-bar animation, then step the character through the wall thickness to the other side; outside door has its own prompt.
- Before relying on client teleports, grep ALL server scripts for anti-teleport/speed/noclip checks or position validation; if something would flag it, design around it (and report).
- Elevator: real working 엘리베이터 at the 1F fake elevator (x -548, back wall) with a NEW 2F elevator door on the checkup-centre back wall above it (x~-548, z~336, 2F floor y 21.08) and a roof stop at the Penthouse/RoofDoor: call buttons (▲▼ lit), floor indicator above doors, chime, doors slide, cabin interior (portal cabin: mirror, handrail, floor buttons 1·2·R, 열림/닫힘, emergency button, inspection certificate, CCTV dome, indicator), ride 2-4 s with sound/indicator count, arrive and doors open. Keep-zones for the 2F door must be registered so T_clinic leaves it clear.
- Roof: 옥상 정원 / 휴게 공간 built client-side on the real roof (y~32.1): deck, planters, benches, pergola with string lights, no-smoking sign, safety rails, 망원경 '광안대교 보기' (camera focus on the bridge direction), maybe vending; reached by elevator 'R' and by a new door from the 2F stair hall if a real stair can't fit (portal stair landing is fine).
- Restrooms (in-place, AAA): tiled floor/walls, stalls with doors (local swing, 사용중 indicator), urinals with dividers (남), vanity with sinks, faucets, mirrors, soap/towel/hand-dryer, 기저귀 교환대, 장애인 화장실 sign, motion-sensor light, interactions: 물 내리기 (flush sound/visual), 손 씻기 (water stream particles + sound), 핸드드라이어 (sound + air), stall door lock 사용중/비어있음.
- 직원 휴게실 (STAFF ONLY, portal): lockers, sofa, kitchenette with coffee machine/microwave/fridge, notice board, shift schedule, uniforms on hooks. Entry is allowed for everyone (game), but show "관계자 외 출입금지" sign and a confirm text. 창고: metal shelves with labelled supply boxes (거즈, 주사기, 수액, 마스크...), linen cart, wheelchairs, oxygen cylinders.
- Glass room doors of the map (Door_* models: 진료실, 주사실, 입원실 201/202, 건강검진센터 ...) should visibly open when the local player approaches (they are non-colliding already per survey; hide the map leaf and animate your own copy, or animate the hidden-safe way) with a door-closer feel; plus '진료 중' lamp over the consult door.
- Wayfinding: 층별 안내, 비상구 유도등 (green running-man exit signs), floor numbers at elevator/stairs, room name plates.
- Performance: build lazily when the player is within ~140 studs of the hospital centre (-515,7,300); portal rooms built on first entry and destroyed when you leave the hospital; total parts for the facility layer ≤ ~2500 at a time; lights budget (SurfaceLight/PointLight) ≤ 10 extra; update loops at ≤ 10 Hz; disconnect everything on stop.
- UI: fade overlay + small toast texts in Korean; prompts use the existing Interact.prompt helper (KeyCode R, gamepad ButtonY) so it matches the rest.

## Tools
- Luau CLI ${S}/luau/luau, ${S}/luau/luau-compile.
- Offline preview pipeline in ${S}/bprev/: fixtures fx/<key>.luau (+ .scene.json) exported from place.bin (export.py / export_rooms.py), sim.luau runs the building-interior modules on a mock runtime (lib/rbx.luau ...), preview.js renders three.js shots (node preview.js --help / read its header; global render semaphore = max 3 renders at once, it waits automatically). There are hospital fixtures already (ls ${S}/bprev/fx | grep -i hosp; shots in ${S}/bprev/shots/hospital_*). Read run.sh / sim.luau to see how a fixture is simulated and rendered.
- Temp studio (browser re-implementation of Roblox running the owner's place): base HTML ${S}/v7zip/x/Gwangalli_Studio_v7-1.html; injection: /home/user/-/tools/build_studio_cabin.py (env BLD_SRC = the building interior folder) builds an HTML with the building-interior LocalScript injected; ${S}/harness/bld.js drives it (teleport, FocusPoint, screenshots). Run any chromium/studio process under "flock ${S}/.studio.lock timeout 1500 <cmd>", one at a time, and kill leftovers.
`

phase('Research')
const research = await agent(`${COMMON}
# Your job: RESEARCH + DETAILED DESIGN
Produce ${D}/design.md (mkdir -p) with: exact world coordinates (and the hospital's local frame) of every relevant wall/door/stair/roof/penthouse/elevator part (from dump.json / place.bin, with sizes and which faces are inside/outside), wall thicknesses at each door, the 1F back hall west-end free volume, the 2F checkup back wall at x~-548, the east wall at the 주사실 for the ER door and the ambulance bay outside it, the fire-exit door and what is outside it; the roof walkable area; stair geometry; StreamingEnabled; anti-teleport/position checks in server scripts (quote file:line or state none found); Law/Hospital NPC corridors to avoid; GwangalliDoors contract; Health contracts; a chosen hidden location for portal rooms (prove it is empty). Then the full design: module split (HospitalPlus.luau + Hosp_*.luau), keep boxes (world AABBs) to register, every door/portal/room with its coordinates and behaviour, the elevator state machine, roof garden layout, restroom layout (per-part list at real scale: 1 stud ≈ 0.28 m, character ~5 studs), lifecycle/performance plan. Also read T_clinic.luau as it stands now and list what it already covers (so you don't duplicate) and where its builds could collide with your plan. Return the whole design doc as your final answer.`, { label: 'research:hospital', phase: 'Research' })

phase('Build')
const build = await agent(`${COMMON}
# Your job: IMPLEMENT the facility layer from this design (also at ${D}/design.md):
-----
${research}
-----
Write complete production-quality code (no stubs). Reuse Kit/Look/Props/Interact helpers wherever they fit (read them first) so style matches. Make the rooms genuinely AAA: real-scale fixtures with item-level detail (soap bottles, paper towels, tile grout lines, signage, lockers with name tags, labelled supply boxes...). Every file must pass luau-compile. Return: file list + purpose, how each feature works, coordinates used, keep boxes registered, part/light counts per area, and anything you could not do.`, { label: 'build:hospital', phase: 'Build' })

phase('Test')
const test = await agent(`${COMMON}
# Your job: TEST + VISUAL CHECK of the facility layer
Implementer's report:
-----
${build}
-----
1. luau-compile every HospitalPlus/Hosp_* file.
2. Offline: extend the bprev sim (in ${D}/sim/ copies, don't break the shared pipeline) so HospitalPlus.start can run against the hospital fixtures/mock runtime; render previews of: restrooms (남/여, from the hall and inside), elevator doors 1F and 2F (closed/open), elevator cabin, staff lounge, storage, roof garden, fire exit inside/outside, ER entrance inside/outside, glass doors opening. Fix bugs you find in the source.
3. Studio (under flock): build a studio HTML with the building interior (tools/build_studio_cabin.py with BLD_SRC, output into ${D}/studio/), walk the flows by eval: teleport near the hospital, trigger the prompts' callbacks (find the ProximityPrompts named GwInteriorPrompt in your built models and call their Triggered handlers via InputHoldEnd/ fire, or call your module's internal functions), ride the elevator 1F→2F→R→1F, enter/exit each portal room, go out the fire exit and back, use the ER door; take ≥ 12 screenshots to ${D}/shots/NN_name.png and LOOK at them (Read tool). Judge honestly vs AAA; fix what looks wrong (scale, z-fighting, floating parts, dark rooms, wrong orientation, doors facing wrong way) and re-shoot.
Return: results, bugs fixed (file:line), remaining issues, screenshot list with captions.`, { label: 'test:hospital', phase: 'Test' })

phase('Review')
const LENSES = [
  { k: 'correctness', p: 'Roblox API correctness (every API/property/enum real and used right), client teleport safety (PivotTo vs CFrame, sitting/vehicle states, falling through floors, StreamingEnabled), never breaking server contracts (HospitalPrompt anchors, HospitalBed seats, rigs, NPC corridors, AutoDoor), keep zones registered before builds, lifecycle cleanup (connections, parts, hidden map parts restored), performance budgets.' },
  { k: 'experience', p: 'AAA facility realism and fun vs a real Korean 의원 (restroom details, elevator behaviour, signage, exit signs, roof), every door/passage actually usable end-to-end on PC/mobile/gamepad, nothing looks fake or floating, scale right, lighting good; read the screenshots in ' + D + '/shots/.' },
]
const reviews = await parallel(LENSES.map((L) => () => agent(`${COMMON}
# Your job: ADVERSARIAL REVIEW — lens: ${L.k}
Read ${BI}/HospitalPlus.luau and all ${BI}/Hosp_*.luau, ${D}/design.md, and this test report:
-----
${test}
-----
Lens: ${L.p}
Do not edit source. Report verified findings only: severity (blocker/major/minor), file:line, failure scenario, exact fix.`, { label: `review:hospital:${L.k}`, phase: 'Review' })))

phase('Fix')
const fix = await agent(`${COMMON}
# Your job: FIX review findings, then re-verify
Reviews:
-----
${reviews.filter(Boolean).join('\n\n=====\n\n')}
-----
Verify each finding; fix real blockers/majors and cheap minors. Re-run compile, sim previews and (if flows/visuals changed) the studio walkthrough under flock; refresh ${D}/shots/. Return: per-finding outcome, final status, final screenshot list with Korean captions, and any patch you need the orchestrator to apply to files outside your allowed set (exact diff).`, { label: 'fix:hospital', phase: 'Fix' })

return { research: research && research.slice(0, 4000), build, test, fix }
