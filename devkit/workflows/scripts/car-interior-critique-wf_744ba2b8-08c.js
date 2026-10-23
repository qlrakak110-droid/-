export const meta = {
  name: 'car-interior-critique',
  description: 'Per-car critique of rendered Roblox part-built interiors vs the real car, with concrete Luau fixes',
  phases: [
    { title: 'Critique', detail: 'one agent per car model: renders + real-car spec + code -> ranked fixes' },
    { title: 'Verify', detail: 'adversarially check each car\'s proposed code against the Kit API and measured dims' },
  ],
}

const ROOT = '/home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior'
const PAD = '/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad'

const ISSUES = {
  type: 'object',
  properties: {
    car: { type: 'string' },
    summary: { type: 'string', description: 'two sentences: how close the render is to the real interior and the biggest gaps' },
    issues: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          rank: { type: 'number' },
          severity: { type: 'string', enum: ['high', 'medium', 'low'] },
          area: { type: 'string', description: 'wheel | cluster | center screen | vents | climate | shifter | console | dash | garnish | doors | seats | headliner | lights | other' },
          observed: { type: 'string', description: 'what the render shows (cite the shot file name)' },
          real: { type: 'string', description: 'what the real car looks like (from the spec / your knowledge)' },
          fix: { type: 'string', description: 'precise change: file, function, gating (style field or key), coordinates relative to F fields' },
          code: { type: 'string', description: 'Luau code to add or the exact replacement (old -> new), ready to paste' },
          partsDelta: { type: 'number', description: 'approximate change in part count' },
        },
        required: ['rank', 'severity', 'area', 'observed', 'real', 'fix', 'code', 'partsDelta'],
      },
    },
  },
  required: ['car', 'summary', 'issues'],
}

const VERDICT = {
  type: 'object',
  properties: {
    car: { type: 'string' },
    checked: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          rank: { type: 'number' },
          ok: { type: 'boolean' },
          problem: { type: 'string', description: 'empty if ok; else what is wrong (API misuse, wrong axis, nil field, collides with other part, breaks another car)' },
          correctedCode: { type: 'string', description: 'corrected Luau if not ok, else empty' },
        },
        required: ['rank', 'ok', 'problem', 'correctedCode'],
      },
    },
  },
  required: ['car', 'checked'],
}

const COMMON = `
You are reviewing an AAA-quality car INTERIOR for a Roblox game (Gwangalli, Busan). The interior is built at runtime by a client
LocalScript purely out of Roblox Parts (no meshes, no uploads): code in ${ROOT}
  - Kit.luau: part builder. Methods (all coordinates are in the car frame = the Underbody part's local frame: +X right, +Y up, -Z toward
    the front; the driver sits at -X, F.side = -1; screens/panels face +Z toward the occupants):
    box(name,size,cf,look) wedge cyl(name,len,d,cf,look) [cylinder axis = cf X] ball(name,d,cf,look) ell(name,size,cf,look) [ellipsoid]
    seg(name,a,b,d,look) [cylinder between two points] ring(name,frame,R,d,n,look,a0,a1,fat) rbox(name,size,r,cf,look) [rounds the 4 edges
    parallel to cf X] panel(name,w,h,d,r,cf,look) [rounded corners seen from +Z] slab(name,w,len,t,r,cf,look) [horizontal plate, corners
    rounded seen from above] zbox(name,size,r,cf,look) [long Z edges rounded] capsule(name,a,b,d,look) vent(name,frame,w,h,look,n) pivot(...)
  - Styles.luau: per-model spec table (wheel spokes, cluster/hood, center screen kind, vents, climate, shifter, console, garnish, speaker,
    seat insert, colors). Cockpit.luau (wheel, column, cluster, center screen), Gauges.luau (physical dials, needles, 7-seg digits),
    Screens.luau (nav map from neon parts + text plates), Dash.luau (dash body, garnish, vents, center stack, climate, extras),
    Console.luau (console + shifter variants), Seats.luau, Trim.luau (doors, pillars, headliner, mirror, pedals), Lights.luau,
    init.client.luau (palette P = look table per material role; LOD manager).
  - F = measured fit of the existing car model (see the dims for your car below). P = palette (look tables).
Renders come from a browser emulator of Roblox ("temporary studio"). Emulator limitations, NOT bugs: SurfaceGui text renders as a blurry
low-res sign; Neon glows strongly; reflectance is exaggerated on flat faces; the studio's own car-skin may overlay a few body parts.
Known issues ALREADY FIXED after these renders (do not report): see ${PAD}/wf/known.txt (read it). Also fixed: large leather/pad
surfaces now have zero reflectance (white glare on flat airbag/seat faces under bright ceilings is gone).
Part budget: a cabin is currently ~1000-1200 parts; up to ~3 cabins exist at once. Prefer high-impact changes; propose removing
low-value parts where it helps. Changes for one model must be gated by its style (S.key or a style field) or be a generic improvement
that does not break other models (sonata, sonata_taxi, g80, tucson, ray, carnival, porter, solati). The user's request: every car must
look like ITS REAL interior (researched), AAA quality, NOT boxy ("네모모양 싫음"), with real details (instrument cluster, gear selector,
vents, climate, steering wheel, doors, seats, interior lights).`

function critiquePrompt(c) {
  return `${COMMON}

YOUR CAR: ${c.label} (style key "${c.key}").
1. Read the real-interior research spec: ${PAD}/specs/${c.key}.json — and use your own knowledge of this exact model/generation.
2. Look at EVERY render of this car (Read each PNG): ${c.shots.join(', ')}
   Shot names: _1_driver = driver's eye view, _2_wheel = wheel + cluster close-up, _3_center = center stack/console from the passenger
   side, _4_dash = whole dash from the passenger rear, _5_night = night driver view (if present).
3. Read the measured dims for this car in ${PAD}/specs/fit_dims.txt (section "=== ${c.dimsKey} ::") and the relevant code
   (Styles.luau entry "${c.key}", and the branches of Cockpit/Dash/Console/Seats/Trim that this style takes).
4. Produce up to 12 issues ranked by visual impact: where the render differs from the REAL ${c.label} interior (missing signature
   features, wrong layout/proportions/positions, wrong colors/materials, boxy shapes that should be rounded, floating or intersecting
   parts, clutter, things that look cheap). For each issue give a precise, minimal, paste-ready Luau fix using the existing Kit API and F
   fields, with coordinates derived from the dims (state the numbers you used). Gate per-model changes by S.key or a style field.
Be concrete and correct; do not propose anything you cannot place with the given dims.`
}

function verifyPrompt(c, crit) {
  return `${COMMON}

Adversarially verify the proposed fixes for ${c.label} (style "${c.key}"). For each issue below, read the code it touches in ${ROOT}
and the dims in ${PAD}/specs/fit_dims.txt (section "=== ${c.dimsKey} ::"). Check: correct Kit method signatures and argument order;
correct axis/rotation (cyl axis = X; rbox rounds edges parallel to X; panel faces +Z); fields it reads exist on F/S/P for this car
(P keys are defined in init.client.luau palette()); the part actually lands where intended (inside the cabin, not buried in or floating
off the dash/console, not colliding with the wheel/cluster/screen); it is gated so other models are unaffected; Luau syntax. Default to
ok=false when unsure, and give corrected code.

Proposed fixes (JSON):
${JSON.stringify(crit.issues, null, 1)}`
}

const cars = args.cars
const results = await pipeline(
  cars,
  (c) => agent(critiquePrompt(c), { label: `critique:${c.key}`, phase: 'Critique', schema: ISSUES }),
  (crit, c) => crit ? agent(verifyPrompt(c, crit), { label: `verify:${c.key}`, phase: 'Verify', schema: VERDICT }).then((v) => ({ crit, verdict: v })) : null,
)
return results.filter(Boolean)
