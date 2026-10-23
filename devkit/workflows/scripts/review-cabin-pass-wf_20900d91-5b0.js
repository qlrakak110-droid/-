export const meta = {
  name: 'review-cabin-pass',
  description: 'Review the latest car-interior Luau commits for runtime errors and gating bugs, then verify each finding',
  phases: [{ title: 'Review' }, { title: 'Verify' }],
}
const DIFF = 'cd /home/user/- && git diff 724c72d HEAD -- src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior'
const CTX = `Repo /home/user/- (Roblox Luau, client-side car interior built from parts). Module dir: src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior.
Get the change with: ${DIFF}
Car frame: Underbody-local, +X right, +Y up, -Z front; driver at -X. Styles.luau LIST holds per-car styles (sonata, sonata_taxi, g80, tucson, ray, carnival, porter, solati).
Kit API: box/wedge/cyl/ball/ell/seg/ring/rbox/panel/slab/zbox/capsule (see Kit.luau). Offline check exists: /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/porterrev (gen.py + sim/run.luau, luau binary at scratchpad/luau/luau) - you may use it to execute the Porter build.
Only report REAL defects introduced by this diff that would (a) throw a Luau runtime error for some car (nil field, wrong arg type, nil arithmetic), (b) apply a change to the wrong cars (gating mistakes), or (c) create clearly misplaced/overlapping geometry. Do not report style nits. Do not edit files.`
const DIMS = [
  { key: 'runtime', prompt: 'Focus: runtime errors. Check every new field access (F.*, S.*, ws.*, C.*, st.*, P.*) exists for ALL styles and for cars missing optional parts (no DoorTrim, no CabDoor, no WheelBadge, no console, F.doorZ0 nil?). Check Fit.luau frontOf, CabHeader/CabDoor blocks, Trim kick panel/toe floor, Cockpit manual gear (ck.manual numeric), Seats rear2/manual, init destroyCabin.' },
  { key: 'gating', prompt: 'Focus: gating/logic. Verify each car-specific change only affects the intended cars (ray, solati, porter, sonata, tucson) and that shared code paths (vent(), cupholders, glovebox now rounded for all cars, toe floor/kick panels for all cars, hubPush/spokePush for all wheels, th 0.15->0.16) do not break other cars. Check Screens.plate call signature for GearLetters, Gauges usage, and manual gear mapping.' },
  { key: 'geometry', prompt: 'Focus: geometry. Using fit dims in /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/specs/fit_dims.txt, check new parts for obvious clashes: Ray StackFoot vs pedals/LowTray, KickPanel vs pedals/footrest/doors/KneePanel, ToeBoard vs pedal arms, Solati GearPod vs wheel rim/SirenBox, partition window vs seats/headrests, Solati headliner after CabHeader change (visors, mirror), Porter SeatRiser vs pedals/lever.' },
]
const FIND = { type: 'object', properties: { findings: { type: 'array', items: { type: 'object', properties: { file: { type: 'string' }, line: { type: 'number' }, title: { type: 'string' }, detail: { type: 'string' }, fix: { type: 'string' } }, required: ['file', 'title', 'detail', 'fix'] } } }, required: ['findings'] }
const VERDICT = { type: 'object', properties: { real: { type: 'boolean' }, reason: { type: 'string' }, fix: { type: 'string' } }, required: ['real', 'reason'] }
const results = await pipeline(
  DIMS,
  d => agent(`${CTX}\n\n${d.prompt}\nReturn findings (empty array if none).`, { label: `review:${d.key}`, phase: 'Review', schema: FIND }),
  r => parallel((r ? r.findings : []).map(f => () =>
    agent(`${CTX}\n\nAdversarially verify this claimed defect. Read the actual code; trace a concrete car/style where it fails. Default real=false if you cannot show a concrete failing case.\nCLAIM: ${f.title}\nFILE: ${f.file}:${f.line || ''}\nDETAIL: ${f.detail}\nPROPOSED FIX: ${f.fix}`, { label: `verify:${f.title.slice(0, 40)}`, phase: 'Verify', schema: VERDICT })
      .then(v => ({ ...f, verdict: v }))))
)
const all = results.flat().filter(Boolean)
return { confirmed: all.filter(f => f.verdict && f.verdict.real), rejected: all.filter(f => !(f.verdict && f.verdict.real)).map(f => f.title) }
