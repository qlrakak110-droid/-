export const meta = {
  name: 'review-car-cabin-luau',
  description: 'Adversarially review the Roblox Luau AAA car interior module for API, geometry and lifecycle bugs',
  phases: [
    { title: 'Review', detail: '3 lenses: Roblox API/runtime, geometry/fit, performance/lifecycle' },
    { title: 'Verify', detail: 'one skeptic re-checks every finding' },
  ],
}

const S = '/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad'
const SRC = '/home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior'
const CONTEXT = `
Context: a Roblox game (Korean city "Gwangalli"). We wrote a client-only LocalScript in StarterPlayerScripts that builds an AAA-looking
car interior out of Parts (no uploaded meshes) for the ~3 cars nearest the camera/character plus the car the local player sits in, and
tints every car's glass black and reflective. Source (read every file): ${SRC}/init.client.luau (manager: workspace scan, LOD,
glass tint, live steering wheel / cluster), Kit.luau (part helpers + Weld to the car frame part "Underbody"), Fit.luau (reads the
existing Interior parts of each car to get anchor positions), Cockpit.luau, Dash.luau, Console.luau, Seats.luau, Trim.luau, Screens.luau
(SurfaceGui screens), Glass.luau. A single-file bundle of the same code is generated at /home/user/-/build/GwangalliCarInterior.client.luau.
Car models follow a build contract; dumps of real cars from the place (part names, sizes, positions in Underbody-local studs, +X right,
+Y up, -Z front, driver on the left) are in ${S}/car51933.txt (Sonata sedan, full tree), ${S}/car_44149.txt (Genesis G80),
${S}/car_44799.txt (Tucson SUV), ${S}/car_43395.txt (Kia Ray), ${S}/car_42373.txt (Carnival van), ${S}/car_14415.txt (Porter truck,
frame part is "Chassis"), ${S}/car_304603.txt (Solati ambulance), ${S}/car_41563.txt (taxi). Existing interior parts are hidden with
LocalTransparencyModifier (never destroyed). Cars are rigged by a server script (GwangalliVehicles/Rig): every visual part gets welded to a
base part with Weld; front wheels steer through Motor6D (Part1 named "DriveHub<i>") whose Transform the client Visuals module sets to
CFrame.Angles(0, -steer, 0). Parked cars are Anchored. The code also runs inside a browser Roblox emulator for previews, but judge it
against REAL Roblox behaviour. A Luau compiler is available at ${S}/luau/luau-compile and ${S}/luau/luau-analyze (no Roblox type
definitions installed) if you want to check syntax.
`
const FINDINGS = {
  type: 'object',
  properties: { findings: { type: 'array', items: { type: 'object', properties: {
    title: { type: 'string' }, file: { type: 'string' }, where: { type: 'string' },
    severity: { type: 'string', enum: ['critical', 'major', 'minor'] },
    failure: { type: 'string', description: 'concrete scenario -> runtime error / wrong placement / visible defect / cost' },
    fix: { type: 'string', description: 'minimal concrete fix (code)' },
  }, required: ['title', 'file', 'where', 'severity', 'failure', 'fix'] } } },
  required: ['findings'],
}
const LENSES = [
  { key: 'api', prompt: `Lens: real-Roblox API and runtime correctness. Check every Instance class, property, enum and method used
(SurfaceGui props incl. Brightness / LightInfluence / SizingMode / PixelsPerStud / ClipsDescendants, UIStroke, UIGradient Transparency,
TextLabel props, SpecialMesh MeshType Sphere sizing with the part size, Part.Shape Cylinder axis = X, WedgePart slope orientation,
Enum.Material names Leather/Carpet/Rubber/Fabric/DiamondPlate/Foil/Neon, Weld C0/C1 semantics with Part0 = car base and parts parented
later, welding client-created parts to server-owned / anchored assemblies, Massless, LocalTransparencyModifier on BasePart only,
Motor6D.Transform read on the client, CFrame:ToOrientation, AssemblyLinearVelocity, Humanoid.SeatPart, Instance:SetAttribute on
replicated parts from the client, task.wait inside RenderStepped-free coroutines, 'continue' in Luau, string patterns). Any line that
errors at runtime in real Roblox or silently does nothing is a finding.` },
  { key: 'geometry', prompt: `Lens: geometry and fitting. Using the car dumps, mentally place the generated parts for the Sonata (and spot-check
G80, Tucson, Kia Ray, Porter): CFrame math (CFrame.fromMatrix axis order, CFrame.Angles signs for recline / tilt, ROT_X_TO_Z / ROT_X_TO_Y
helpers, Kit:rbox axis mapping, Kit:ring segment placement, Kit:seg orientation, seat belt fromMatrix), and whether pieces end up where
intended: steering wheel centred on the old WheelRim octagon and facing the driver, display in front of the wheel and not inside the
dashboard, dash not poking through the windshield or door trims, seats on the floor and reclined backwards (top toward +Z), headrests on
top of the backs, door cards inside the doors (inner face at DoorTrim's inner x), pedals in the footwell, mirror under the headliner.
Report concrete misplacements with the numbers.` },
  { key: 'lifecycle', prompt: `Lens: performance and lifecycle in a real server with ~300 cars, StreamingEnabled possibly on, mobile clients.
Check the workspace scan, DescendantAdded handler cost, the LOD loop (build one at a time, destroy/restore of hidden parts and disabled
SurfaceGuis, cars that are destroyed / respawned / re-parented mid-build, a car whose Interior streams out), the RenderStepped loop
(iterating all cars every frame, per-frame allocations, Screens.update cost), part counts per cabin, memory leaks (connections never
disconnected, tables keyed by destroyed instances), re-entrancy of buildCabin, and the glass tint (server later changing the glass
props, cars without glass, LotCar opaque wedges). Report only real problems with a concrete scenario.` },
]
phase('Review')
const reviews = await parallel(LENSES.map((l) => () => agent(CONTEXT + '\n' + l.prompt + '\n\nOnly real, concrete defects (no style nits). Each needs a failure scenario and a minimal fix. Empty list if nothing real.', { label: 'review:' + l.key, phase: 'Review', schema: FINDINGS })))
const all = reviews.filter(Boolean).flatMap((r, i) => (r.findings || []).map((f) => ({ ...f, lens: LENSES[i].key })))
log(all.length + ' raw findings')
if (!all.length) return { confirmed: [], rejected: [] }
phase('Verify')
const VERDICTS = { type: 'object', properties: { verdicts: { type: 'array', items: { type: 'object', properties: {
  index: { type: 'number' }, real: { type: 'boolean' }, reason: { type: 'string' }, fix: { type: 'string' } }, required: ['index', 'real', 'reason'] } } }, required: ['verdicts'] }
const list = all.map((f, i) => `#${i} [${f.lens}/${f.severity}] ${f.title}\n  ${f.file} @ ${f.where}\n  failure: ${f.failure}\n  fix: ${f.fix}`).join('\n\n')
const v = await agent(CONTEXT + `\nYou are a skeptical verifier. For EACH finding, re-read the code (and car dumps) and decide whether the failure really
happens in real Roblox. Default real=false when the claim is speculative or wrong about the Roblox API. When real, give the corrected minimal fix.\n\n` + list, { label: 'verify:all', phase: 'Verify', schema: VERDICTS })
const by = new Map(((v && v.verdicts) || []).map((x) => [x.index, x]))
const confirmed = [], rejected = []
all.forEach((f, i) => { const x = by.get(i); (x && x.real ? confirmed : rejected).push({ ...f, verdict: x || null }) })
return { confirmed, rejected }
