export const meta = {
  name: 'ed-graphics-r3',
  description: 'ECLIPSE DUEL graphics round 3 toward flagship action-RPG quality: render pipeline (depth, AO, fog, light shafts, DOF, grading, shadows) -> atmosphere + VFX + cinematic camera on top of it -> graphics director review',
  phases: [
    { title: 'Render', detail: 'post pipeline + shadows + quality tiers' },
    { title: 'Layer', detail: 'env atmosphere, VFX depth/readability, cinematic camera' },
    { title: 'Direct', detail: 'before/after review in game, fixes, perf, final build' },
  ],
}
const SP = '/tmp/claude-0/-home-user--/8256de2b-7eff-573b-8afc-504b52b3c9af/scratchpad/r3'
const REPORT = { type: 'object', properties: { summary: { type: 'string' }, files: { type: 'array', items: { type: 'string' } }, api: { type: 'string' }, perf: { type: 'string' }, issues: { type: 'array', items: { type: 'string' } }, keyCaptures: { type: 'array', items: { type: 'string' } } }, required: ['summary', 'files', 'issues'] }
const HEAD = `You are a senior graphics engineer / technical artist on ECLIPSE DUEL, an ORIGINAL dark-fantasy 1v1 3D fighting game (three.js r170 bundled, everything procedural, one self-contained HTML, 60 fps target on desktop and phones). Project root: /home/user/-/eclipse-duel . The owner wants the look, effects and motion pushed to the level of a flagship dark-fantasy action-RPG (think the mood of a AAA soulslike: heavy atmosphere, volumetric light, mist, embers, weighty impacts, cinematic framing) — but everything must stay ORIGINAL: never imitate any existing game's names, characters, locations, designs or UI.
READ FIRST: CONTRACT.md (conventions, budgets, quality tiers, 60 fps rules, module contracts), src/game/README.md (time model, content API), and the README of every module you touch.
HARD RULES:
- Never run git commands that change repository state; never install packages; no network assets (everything procedural / in code).
- Work only in the files you own (listed in your task). Other teams edit other files concurrently (the rig team: src/char/{index,anim,skeleton,ik,build,shapes,cloth,spring,collide,rigmath,qa}.js, src/char/clips, src/labs/rig*.js, src/labs/char.js; the character-look team: src/char/materials.js, src/char/kit/**, src/char/weapons.js, src/fighters/*/design.js and kit*.js). If you need something from another module, work around it in your files and report it in issues.
- Builds and captures: always use a private copy: add --as r3-<yourlabel> to every tools/shot.mjs game call (it builds and loads build/r3-<yourlabel>.html); never run plain "node tools/build.mjs game" (only the director builds dist/). Labs (node tools/shot.mjs <lab>) build build/<lab>.html. The 4-core machine is shared by ~5 agents: keep captures at 960x540 or 1280x720 with --sheet-only contact sheets and read every image you make with the Read tool. Captures in shots/r3/<yourlabel>/, scratch files in ${SP}/<yourlabel>/.
- Useful game hooks: #demo=kael,iska,hard&seed=N (deterministic CPU match), #training=kael,vorn, __ED.game.{start, skipIntro, forceMove(i, id), moveFor(i, slot), place, meters, controller, pose}; src/game/tests/capture.mjs (SECTIONS=ult ULT=kael,iska,vorn), moves.mjs (FIGHTERS=...), profile.mjs (#prof per-group CPU ms, draw calls, triangles), q=low|mid|high.
- 60 fps is a hard requirement: every new pass must have a per-tier cost plan (off on low unless nearly free; half resolution where possible; no per-frame allocations; no shader compiles mid-fight — prewarm). Measure draw calls / triangles / JS ms with profile.mjs before and after; GPU time can't be measured on SwiftShader, so also reason about fill cost and say so.
- Readability first: fighters must always read clearly against the background; no white-outs; atmosphere adds depth, it never hides the fight.`

phase('Render')
const render = await agent(`${HEAD}

YOUR ROLE: rendering lead. You own src/post/** , src/core/app.js , src/core/util.js (quality tiers), src/labs/post.js and the post / quality sections of CONTRACT.md.
TASK: upgrade the renderer to flagship quality while holding 60 fps per tier:
1. Scene depth: expose the scene depth as a texture (post.depthTexture, plus camera near/far/projection uniforms helpers) that works with the MSAA scene target (resolve depth correctly) so other modules can use it (soft particles, fog, mist). Keep onAfterScene working (the env puddle pass uses it).
2. Ambient occlusion: a cheap half-resolution SSAO/GTAO-style pass with bilateral blur (high: on, mid: reduced, low: off) that grounds the fighters and the carved architecture; it must not darken emissive or VFX.
3. Atmosphere in post: height + distance fog with in-scattering toward a light direction (the eclipse corona) using the depth texture, and screen-space light shafts (god rays) from the eclipse / any bright source position the env reports (API e.g. post.setSun(worldPos, color, strength) / post.fog params; env will call it). Quality-tiered.
4. Cinematic depth of field: post.dof({ focus, aperture, ... }) with a fast bokeh-ish gather at half res, off by default, meant for camera cinematic shots (the camera team will drive it); tiered.
5. Colour grading: a filmic grade on top of ACES (lift/gamma/gain, split toning shadows/highlights, per-mood presets reachable via post.to / a grade API) so the arena reads as a moody night with warm brazier pools and a cold eclipse rim; keep the impact frame / flash / mono features.
6. Shadows: improve character/arena shadow quality and stability (shadow map size per tier, a tight fight-area shadow frustum that follows the fighters, soft PCF, no acne/peter-panning), owned via app.js / renderer settings + a small API the env can call to aim the key-light shadow frustum (env owns its lights; coordinate through an API, document it).
7. Optional if cheap: sharpening after the dynamic-resolution upscale; dithering against banding in the fog and dark gradients.
Verify each feature in src/labs/post.js (add scenarios) and in game (a #demo match and an ultimate at q=high/mid/low), before/after sheets. Measure per-tier cost (draw calls, render passes, JS ms) and document budgets and the API in CONTRACT.md + a header comment in src/post/index.js. Return the report; api = the exact API other teams should use.`, { label: 'render', phase: 'Render', schema: REPORT })

phase('Layer')
const API = JSON.stringify({ summary: render && render.summary, api: render && render.api, issues: render && render.issues }).slice(0, 14000)
const MURIM = `
NEW BINDING ART DIRECTION (it supersedes the dark-fantasy wording above): the game is now 「흑일무림 黑日武林」, a murim (Korean martial-arts fantasy) action game. READ MURIM.md in the project root first and follow it: heroes are martial masters in layered robes (염무강 / 설리화 / 뇌진천; code ids kael / iska / vorn unchanged), the arena is the ruined summit terrace 천무대, power is inner energy (기): blade-energy crescents with dry-brush ink edges, flowing energy wisps, formation diagrams (진법) instead of western rune circles, ink-splash impact frames, leaves / petals / snow / embers. Other teams are restyling the characters (src/char/materials.js, kit, weapons, src/fighters/*/design.js), the arena + atmosphere (src/env/** is NOT yours in this round), UI / names (src/ui, moves.js display names, MOVES.md) and audio (src/audio) at the same time; an RPG mode team works in src/rpg/**. Stay inside your own files.`
const layers = await parallel([
  () => agent(`${HEAD}
${MURIM}

The rendering lead just upgraded the post pipeline. Their report and API: ${API}

YOUR ROLE: lead VFX artist. You own src/vfx/** , src/labs/vfx.js , src/game/feel.js and the fighters' choreography files src/fighters/{kael,iska,vorn}/present.js and fx*.js / fxlib.js (not their clips, design, moves data or index.js).
TASK: take every hit, skill and ultimate to flagship weight and readability, in the murim idiom:
- Restyle the element libraries and signature effects per MURIM.md section 5: 검기 / 도기 crescents (slash meshes) with a dry-brush, ink-like trailing edge and a bright honed core; inner-energy auras as flowing wisps along the body and weapon; formation diagrams (rings of trigram-like bar groups, star points, seal-script bands — procedural decals, replacing every western rune circle in wind-ups, ground telegraphs and the ultimates); stomp (진각) dust rings; light-foot (경공) afterimage trails; talisman scraps, leaves, petals, snow crystals, sparks and embers as accent particles; fire = red-gold 열양 (KAEL: molten, crushing, charred), frost = moon-white 한빙 (ISKA: crystalline, precise, snow-crystal bursts), lightning = violet-white 뇌기 (VORN: piercing bolts, thunder rings). Impact frames read as ink splashes (monochrome, brush-stroke radial lines), never an inverted white frame.
- Soft particles and mist / smoke that fade against scene depth (post depth texture), heat haze / shock distortion that respects depth.
- Fix the known white-outs: ISKA's crystal_procession spike-line hit (a near-white frame for 2-3 frames in a #demo=kael,iska,hard&seed=7 match around t = 16 s), VORN's thunder javelin impact, any remaining near-white frames in the three ultimates (SECTIONS=ult ULT=kael,iska,vorn src/game/tests/capture.mjs and a few #demo matches). Rule: a bright core for 1-2 frames is fine; the fighters' silhouettes must stay readable; no full-frame white.
- Weight: every heavy hit has a layered impact (hot core 1-2 frames, sparks with gravity and floor bounces, lingering embers / frost / ozone, dust and debris kicked off the floor, a ground scorch / frost / char mark when it lands low).
- Afterimage cost: ghosts copy whole characters (~58k triangles each); add a cheap proxy (body mesh only or a decimated silhouette) and cap ghosts per fighter, so ultimates stop spiking triangles; bring each ultimate's triangle and overdraw peaks down (profile.mjs during each ult) without losing spectacle.
The character designs are being rebuilt while you work (sockets and weapon lengths are unchanged), so judge effects on whatever the heroes look like in your build. Before / after sheets of every skill and every ultimate (in game), and a perf table. Return the report.`, { label: 'vfx-murim', phase: 'Layer', schema: REPORT }),
  () => agent(`${HEAD}
${MURIM}

The rendering lead upgraded the post pipeline (report: ${API}).
YOUR ROLE: cinematographer. You own src/cam/** and src/labs/cam.js.
TASK: make every cinematic moment look directed, with wuxia flourishes:
- Drive the new depth of field from the camera: shots in the vocabulary (heroPushIn, faceCloseUp, weaponFollow, overShoulder, impactPunchIn, orbitSweep, crashZoom ...) set focus on their subject (auto-focus on the anchored fighter / the victim) with an aperture per shot type; fight framing keeps DOF off (or a very subtle far-background blur only if it is free on high).
- Cinematic exposure / grade hints per shot through the post API so dark angles lift a little; letterbox stays.
- Wuxia vocabulary additions (additive API, documented in src/cam/README.md): a low sweeping orbit that passes behind a foreground element, a held wide "duel" frame with the eclipse between the two masters (for round intros), a fast push-in on a drawn blade, a rising crane on a leap; subtle handheld micro-motion and lens breathing on cinematic shots (not in fight framing); whip-pan blur via the radial / directional blur if the post supports it.
- Fight framing: both fighters always readable at every aspect ratio (desktop, portrait 390x844, landscape 844x390); slight dynamic zoom on big hits only.
Verify with the cam lab and in game (all three ultimates, K.O., round intro) before / after sheets. Return the report.`, { label: 'cinematography', phase: 'Layer', schema: REPORT }),
])
const cam = layers[1]

phase('Direct')
const director = await agent(`${HEAD}
${MURIM}

YOUR ROLE: graphics director, final review of this round. Reports: ${JSON.stringify({ render, layers }).slice(0, 40000)}
(The arena restyle + atmosphere, the character redesign, UI / names and audio are handled by other teams that may still be running: review the image as a whole but only edit this round's files.)
1. Build a private copy of the game and review it like a player and an art director: title, select, VS, round intro, a full #demo match of each pairing (frames every 3-5 s), each fighter's skills (moves.mjs), all three ultimates, a K.O., at q=high, q=mid and q=low, desktop 1280x720 and portrait 390x844. Read every sheet.
2. Judge against the flagship bar and MURIM.md: depth and atmosphere, readability of the fighters, no white-outs, no banding / acne / flicker, consistent grading (ink-wash night, warm lantern pools, cold eclipse rim), cinematic DOF on the right subjects, effects reading as inner energy and ink rather than western magic.
3. Fix what is wrong in the files this round owned (src/post/**, src/core/app.js, src/core/util.js, src/vfx/**, src/game/feel.js, src/fighters/*/present.js, fx*.js, src/cam/**), most visible first.
4. Perf verdict per tier with profile.mjs (fight + every ultimate): draw calls, triangles, JS ms per group; reason about GPU fill per pass; adjust tiers so 60 fps is credible on a mid phone (low / mid) and an integrated-GPU laptop (mid / high).
5. Write a short "Graphics round 3" section in CONTRACT.md (what exists, tiers, budgets). Do not build dist/ (the lead does the final build). Return the report with keyCaptures = the 4-6 best before / after sheets.`, { label: 'gfx-director', phase: 'Direct', schema: REPORT })

return { render, layers, cam, director }
