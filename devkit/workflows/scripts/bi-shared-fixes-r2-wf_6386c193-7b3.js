export const meta = {
  name: 'bi-shared-fixes-r2',
  description: 'Apply the shared-module fixes the shop/club reviewers asked for (Scan/Kit/Props/Common + preview tooling), then adversarially verify with full regression sims',
  phases: [
    { title: 'Fix', detail: 'implement the requested shared patches + baseline/after sims' },
    { title: 'Verify', detail: 'independent diff review + full regression, fix or revert regressions' },
  ],
}
const S = '/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad'
const BI = '/home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliBuildingInterior'
const COMMON = `
# Context
Roblox game "광안리 (Gwangalli, Busan)". A client-only LocalScript folder ${BI}/ builds AAA interior decor (Parts only) for every shop / venue / home near the player. Shared foundation modules: Kit.luau (part factory, K:spot / K:free placement, keeps), Scan.luau (room scan, keep zones, Vm:spans wall spans, aisles, hide), Props.luau (shared furniture), Common.luau (shared finishing passes: walls, baseboards, fixtures, wallSpot, pendants), Look.luau (materials/colours), Interact.luau (prompts, canPrompt). Per-type builders are T_*.luau.
Offline pipeline: ${S}/bprev — fixtures in fx/, simulator sim.luau, simall.sh [keys...] (prints #V/#K summary lines incl. parts, blocked, prompts, errors; with no keys it runs every fixture in batch_all.txt), run.sh <key> renders a contact sheet to bprev/shots/<key>.jpg (heavy: the machine is loaded; render only a few, each takes minutes; use a global 3-slot semaphore already built into preview.js). Luau CLI: ${S}/luau/luau, ${S}/luau/luau-compile (luau-compile --binary f >/dev/null for syntax).
Rules: NEVER git commit/push/checkout/stash/reset (the orchestrator commits). Other agents are concurrently editing T_bowling.luau, T_facility.luau, T_club.luau, T_clubmain.luau and folders outside GwangalliBuildingInterior — do NOT edit those files. You MAY edit Scan.luau, Kit.luau, Props.luau, Common.luau, Look.luau, Interact.luau, and T_pub.luau / T_seafood.luau / T_korean.luau / T_cafe.luau / T_grill.luau only to remove a local workaround that a shared fix makes redundant (keep behaviour identical or better). Preview tooling under ${S}/bprev and ${S}/v7pack/core/js may be edited for the preview-only items. Keep code style (tabs, short Korean/English comments). Read files with grep -n / sed -n ranges, not whole-file dumps.
Policy reminder for any text you add: all ages, no '장애인' or ♿, no romance wording.
`
const FIXES = `
# Requested shared fixes (from 9 reviewer reports; each names the file/line area and a proposed patch — verify the claim in the code first, then implement the best version)
1. Props.frame: FrameGlass always built -> make it optional (\`pick(o, "glass", true)\`), and Props.license passes glass=false. Remove T_pub's local FrameGlass-transparency workaround if it becomes redundant.
2. Common.wallSpot: add an optional 7th parameter test(wn, u) -> boolean; for each span wide enough, try candidate u positions (span start+w/2 stepping 0.5 to end-w/2, plus the clamped target), sorted by |u - target|, return the first passing test. Common.fixtures then places the 실내 조명 스위치 with test = Interact.canPrompt at the would-be prompt position, so shops whose entrance spot is near host anchors still get a light switch somewhere valid (else none). Today every grill/pocha/횟집 logs 'prompt skipped near host: 실내 조명 스위치'.
3. Common.upgrades pendants: \`local drop = math.min(topY - r.min.Y, ps.maxDrop or math.huge)\` and document pendant.maxDrop in the S header comment (T_cafe may then set S.pendant.maxDrop = 1.6 for mega/compose/busan to keep pendants from hanging in front of the map Sign_ brand sign; do that in T_cafe's style table only).
4. Scan aisle keeps (section 4, ~line 812-840): the service-to-table aisle starts at the service point (KitchenPass/PassLedge/CounterTop centre) behind the counter and runs straight through the counter, so nothing can stand on 4-5 studs of counter top / BarUpstand. Fix: when the service point is inside or behind a counter group (relative to the customer side = door side), start the aisle 1.3 studs outside the counter's customer face (T_korean reviewer's patch), and/or clip the first boxes against the CounterTop (T_seafood reviewer's patch). Make sure staff-side keeps (staff spot, NPC spots) are untouched. Then remove T_korean's barOver K:free workaround and T_seafood's 'slim items hug the back wall' workaround ONLY if the shared fix makes them redundant and the sims stay clean.
5. Props.counterOver builds only customer front + kick + top while the map Counter is hidden, so counters are hollow at the open end / staff side and mounted things float. Add end caps + back panel + back kick inside the hidden Counter's exact extent (T_pub's local counterShell is a working reference at T_pub.luau ~3109). Then make T_pub stop calling its local counterShell (no duplicate panels). Check other T_* files for their own end/back skins (e.g. T_pc CounterEndSkin) and avoid z-fighting duplicates (option flag shell=false for callers that build their own).
6. Props.menuStand: card hovers 0.05 above base after the 10 degree tilt: CF(0, 0.5, 0) -> CF(0, 0.05 + 0.4 * math.cos(math.rad(10)), 0) (verify geometry).
7. Props.baseboard: plate spans 0.01-0.07 off the wall, buried inside the map's own Baseboard (0-0.1 deep) -> z-fight. Make ours sit just proud of the map baseboard (e.g. depth 0.12 from the wall) or hide map Baseboard records in Common.walls when we draw ours. Pick the safer option.
8. Scan.hide: return false when it refuses (Screen/TVScreen/Backdrop/WindowView/Room+Surface guards) and true after hiding; add a Kit/Scan doc line: build TV screens in front of the map screen's front face.
9. Scan.keepouts step 5 'window' keep across the whole +Z wall is added to every non-home room. For venue rooms whose +Z side is an inner wall (club rooms) it blocks murals/signs. Gate it: for V.kind == "venue" only add it when the room actually has window/glass parts near the +Z wall (ShopWindow/ShopGlass/Window/Glass named parts, or Glass material parts on that wall) — keep the current behaviour for shops. T_club strips window keeps locally and T_clubmain uses P:free: leave their code alone (they are being edited by others); just make sure your change can't break them.
10. Scan / V.solid: parts sitting on a counter top (e.g. CuttingBoard, non-shell parts whose min.Y is within 0.1 of a counter group's top) are not in V.solid, so type code checking V.solid puts props on gameplay items. Add them to V.solid (verify no side effects on prompts/keeps).
11. Look: add L.steelFlat = matte stainless for wide upward-facing tops (SmoothPlastic ~192,196,200, low reflectance) and mention it in Props.counterOver docs.
12. Scan Vm:spans optional extra boxes param (K.reserved) so Common.wallSpot doesn't hang wall items behind tall new floor props: \`function Vm:spans(name, y0, y1, depth, extra)\` cutting extra boxes too; Common.wallSpot passes K.reserved.
Preview-only (improves the images we show the owner; no game impact):
13. ${S}/v7pack/core/js/render3d.js sign canvases: set tex.colorSpace = SRGBColorSpace (or tex.encoding = sRGBEncoding, depending on the three.js version used) so dark/saturated TextLabel backgrounds don't come out pale/pink.
14. render3d.js night-window rule (thin Glass, area >= 3, world y > 4 becomes a lit window half the time) also hits generated parts (ids >= 50000000): skip generated ids.
15. preview.html SHOT warm-up 16 -> 40 frames (or raise per-frame sign builds while in preview); preview.js --lcams must pass k.warm through; run.sh --lcams must not mix stale default-cam PNGs into the sheet (rm old pngs for that key before rendering).
Items 13-15: first find where the preview actually loads render3d.js from (bprev/preview.html) and edit THAT copy.
`
phase('Fix')
const fix = await agent(`${COMMON}${FIXES}
# Your job: implement all 15 items.
Before editing, run a BASELINE: cd ${S}/bprev && TAG=base ./simall.sh > ${S}/bprev/out/shared_r2_base.txt 2>&1 (all fixtures; takes a while — start it in the background right away and keep working; if your edits land before it finishes, copy the module dir to ${S}/bprev/base_src first and point SRC= at that copy so the baseline is of the original code). After the edits, run the same with TAG=after into shared_r2_after.txt and compare per fixture: parts, blocked, prompts, ghosts/errors. Any fixture that gains blocked>0, loses prompts it had, errors, or changes part count by more than ~5% must be explained or fixed. Render 4 contact sheets for visual sanity (one pub, one 횟집, one grill/pocha, one cafe) after the fixes, at night where relevant. All edited .luau must pass luau-compile.
Return: per item what you changed (file:line) or why you skipped it, the regression table summary (counts of fixtures changed and why), the sheet paths, and anything risky.`, { label: 'fix:shared-r2', phase: 'Fix' })
phase('Verify')
const ver = await agent(`${COMMON}${FIXES}
# Your job: ADVERSARIAL VERIFICATION of the implementation below. Assume it has bugs.
Implementer's report:
-----
${fix}
-----
1. Read the actual diff: cd /home/user/- && git diff -- src/StarterPlayer/StarterPlayerScripts/GwangalliBuildingInterior ; plus the preview tooling files it lists. For every hunk ask: does it really do what the item asked, can it error at runtime in Roblox (nil index, wrong types, Luau syntax that the Roblox parser rejects), can it change behaviour for room kinds it shouldn't (homes! venue rooms! hospital rooms!), does it double-build panels (z-fighting) anywhere, does it free space that must stay clear (doors, aisles customers/NPCs actually walk, staff spots, prompts, seats, table tops).
2. Re-run the full regression yourself (TAG=verify ./simall.sh > ${S}/bprev/out/shared_r2_verify.txt) and compare against ${S}/bprev/out/shared_r2_base.txt independently; also run the home fixtures and hospital fixtures explicitly.
3. Fix every real problem you find directly (minimal edits), or revert a hunk that is not worth its risk. Re-compile and re-sim after your changes.
Return: verdict per item (OK / fixed-by-me / reverted), concrete regressions found with fixture keys, final regression numbers, and remaining risks.`, { label: 'verify:shared-r2', phase: 'Verify' })
return { fix, ver }
