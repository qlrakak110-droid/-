export const meta = {
  name: 'ed-fighter-content',
  description: 'ECLIPSE DUEL fighter content for one fighter: motion clips + skill/ultimate choreography (VFX, camera, audio) in parallel, then a director review pass',
  phases: [
    { title: 'Author', detail: 'animator (clips) and choreographer (present.js + index.js) in parallel' },
    { title: 'Direct', detail: 'director: capture every skill + the ultimate, fix, perf, README' },
  ],
}
const F = args
const SP = '/tmp/claude-0/-home-user--/8256de2b-7eff-573b-8afc-504b52b3c9af/scratchpad'
const REPORT = {
  type: 'object',
  properties: { summary: { type: 'string' }, files: { type: 'array', items: { type: 'string' } }, clipNames: { type: 'array', items: { type: 'string' } }, issues: { type: 'array', items: { type: 'string' } }, keyCaptures: { type: 'array', items: { type: 'string' } } },
  required: ['summary', 'files', 'issues'],
}
const HEAD = `You are a senior member of the AAA content team of ECLIPSE DUEL, an ORIGINAL dark-fantasy 1v1 3D fighting game (three.js, everything procedural, one self-contained HTML). Project root: /home/user/-/eclipse-duel . Your fighter: ${F.name} (id '${F.id}', element '${F.element}', weapon: ${F.weapon}).
The bar is flagship AAA action-RPG/fighting-game quality: every skill must read as a designed set piece with weight, anticipation, impact and aftermath; the ultimate must be a breathtaking cinematic. Originality is mandatory: never reference or imitate any existing game's names, characters, designs or moves.
READ FIRST (fully): CONTRACT.md, src/fighters/MOVES.md (your fighter's section: every move, the WIND-UP / RELEASE / IMPACT / AFTERMATH / SETTLE beats and the ultimate storyboard shot table), src/fighters/BALANCE.md (sections 7-9: storyboard convention, frame data, the timeline markers of every move and the ultimate lock clock), src/game/README.md (the fighter content API: module shape, clips map, present handlers, helper h, ultimates, time model, test API), src/fighters/${F.id}/moves.js and src/fighters/${F.id}/design.js.
HARD RULES:
- Never run git commands that change repository state; never install packages.
- Other teams are editing other files concurrently (src/char/** rig team, src/vfx/** VFX team, src/game/** integration team, src/env/** arena team, the other two fighters' folders). Never edit files outside the ones you own (listed in your task); if you need something from another module, work around it in your own files and report it in issues.
- Builds and captures: ALWAYS build/capture with a private copy so you never race other teams on dist/: add --as ${F.id}-<yourrole> to every tools/shot.mjs call (it builds and loads build/${F.id}-<yourrole>.html), never run plain "node tools/build.mjs game". The machine has 4 cores shared by ~8 agents: keep captures small (960x540 or 640x360, --sheet-only contact sheets, a handful of frames each) and look at every sheet you make with the Read tool. Put scratch scripts in ${SP}/${F.id}/ and captures in shots/${F.id}/.
- Useful: __ED.game.start('${F.id}', '<opponent>', { mode: 'training' }), skipIntro(), forceMove(0, '<moveId>'), place(i, x, facing), meters(...), pose(i, clip, t), controller(i, 'idle'); the scenarios in src/game/tests/ (moves.mjs with FIGHTERS=${F.id}, capture.mjs with SECTIONS=ult ULT=${F.id}, profile.mjs) are your templates.
- 60 fps is a hard requirement: respect the VFX/particle and lights budgets in CONTRACT.md; no per-frame allocations; no white-outs (the frame must stay readable at every instant, bloom must not wash the fighters out).
- TIME BOX: run \`date -u\` regularly. ${F.deadlineNote}`

phase('Author')
const [anim, chor] = await parallel([
  () => agent(`${HEAD}

YOUR ROLE: lead animator for ${F.name}. Also read src/char/README.md fully (bones, clip format, IK, weapons, grips, authoring workflow section 8), src/char/clips/demo.js and the generic clips in src/game/clips.js (style references and the clip API in use), and any motion-QA tooling that exists (src/char/qa.js, tools/clipqa.mjs, src/labs/clipqa.js — may or may not exist yet; use it if it does).
TASK: author ${F.name}'s own motion library in src/fighters/${F.id}/clips/ (index.js registering everything with defineClip / definePose / mirrorClip from src/char/index.js; split into several files, e.g. locomotion.js, moves.js, ult.js, ceremony.js). Clip names are '${F.id}.<name>'. Deliver, in this priority order:
 1. Every move of moves.js as '${F.id}.<moveId>' (light chain, heavy, f+heavy, d+heavy, skill1-3 and follow-ups, the ultimate opener) with an 'impact' event at the first impact frame (so the game can retime it with { clip, hit }), matching MOVES.md's motion description and the frame data (startup / active / recovery from BALANCE.md section 8), trailOn/trailOff-consistent swing arcs, weapon-correct grips (${F.gripNote}).
 2. Locomotion and stance: ${F.id}.idle (weapon-specific guard stance with breathing and weight), walkF / walkB whose root motion matches def.stats walkSpeed / backSpeed with planted feet (no foot slide), dash, backstep, dodge, guard.
 3. Ultimate lock beat clips '${F.id}.ult.<beat>' for the beats of the lock clock in BALANCE.md section 9 (cuts, hurl/lift, leap, finish, rise/settle ... whatever your storyboard has) — the choreographer will play them with h.play() during the lock and checks hasClip, so name them exactly after the lock markers / ticks and LIST them early in src/fighters/${F.id}/clips/NAMES.md (write that file within your first 20 minutes with every planned clip name + one line each, then keep it updated: the choreographer reads it).
 4. intro, victory, defeat; then hitLight / hitHeavy if time remains.
Motion quality bar (this is the heart of the user's request "수백가지의 리깅작업으로 자연스럽게"): readable silhouettes, anticipation before every strike, hips lead the shoulders lead the weapon, overshoot and follow-through, weight shift onto the front foot, feet planted by IK (no sliding, no floating), no limb/weapon intersection with the body, believable balance, recovery back into the exact idle stance. Review EVERY clip visually: in-game with __ED.game.pose(0, '${F.id}.<clip>', t) or forceMove, contact sheets at 6-9 times across the clip from the camera side and at least once from an orthogonal view; iterate until each one looks right. Report rig bugs (src/char/**) in issues instead of editing them.
You own ONLY src/fighters/${F.id}/clips/** . Return the report with clipNames = every clip you registered.`, { label: `${F.id}-animator`, phase: 'Author', schema: REPORT }),
  () => agent(`${HEAD}

YOUR ROLE: VFX / cinematic choreographer for ${F.name}. Also read src/vfx/README.md (primitives, presets — combat.*, ${F.element}.*, motion.* — and vfx.define for custom effects), src/cam/README.md (shots, sequencer, shake/kick/zoom), src/audio (index exports and sound names) and src/game/present.js + src/game/feel.js (what the generic layer already does, so you layer on top or replace it with return false).
TASK: write src/fighters/${F.id}/present.js and replace the stub src/fighters/${F.id}/index.js with the real module: export default { id: '${F.id}', element: '${F.element}', design, def, clips, present }.
- clips: write it as a FUNCTION ({ hasClip }) => map, mapping every state slot and move id to '${F.id}.<name>' ONLY when hasClip(name) (the animator is authoring them concurrently in src/fighters/${F.id}/clips/ — read src/fighters/${F.id}/clips/NAMES.md for the planned names; import './clips/index.js' guarded so the module still loads if that file does not exist yet: check existence with the file system before adding the import, and re-check later — the final module MUST import it once it exists). Use { clip, hit } entries for strikes so they retime onto the frame data (hit = the clip's impact event time; read it from the clip definition rather than hard-coding when possible).
- present: a designed set piece for EVERY move per its MOVES.md beats: wind-up tells (glows, gathering particles, ground runes/cracks), release (trails, smears, launch flashes, camera kick), impact (custom ${F.element} impact flowers, sparks, distortion, light, post pulse, shake scaled to the hit), aftermath (lingering embers / frost mist / static, floor decals) and settle. Use setup() + vfx.define for the fighter's signature effects; projectile handlers for every projectile kind in moves.js; ambient() aura; on.* hooks (intro, victory, KO flourish).
- ult: implement the MOVES.md storyboard shot table exactly on the lock clock (BALANCE.md section 7 convention): mood, freeze, shots, at[] beats with h.play('${F.id}.ult.<beat>') when hasClip else a sensible fallback, offsets for leaps/lifts, ticks with stutter hit-stops, the finish, end/whiff restores. It must be the most spectacular 5 seconds in the game while staying readable (no white frames, the fighters remain visible).
- Review: capture every skill (start -> aftermath, 6-9 frames per sheet) and the whole ultimate (12-16 frames from super-freeze to blend-back) at 960x540, read every sheet, iterate until each is a designed, readable, spectacular set piece. Check the browser console output for '[ed] choreography ... threw' and page errors: zero allowed. Check the ultimate peak with src/game/tests/profile.mjs (draw calls <= 160, no JS spikes from your handlers).
You own ONLY src/fighters/${F.id}/present.js, src/fighters/${F.id}/index.js and new files src/fighters/${F.id}/fx*.js if you want to split. Return the report with keyCaptures = the best sheets.`, { label: `${F.id}-choreo`, phase: 'Author', schema: REPORT }),
])

phase('Direct')
const director = await agent(`${HEAD}

YOUR ROLE: director / final reviewer of ${F.name}'s content. The animator and the choreographer just finished. Their reports: ${JSON.stringify({ anim, chor }).slice(0, 24000)}
1. Make sure the module is wired: src/fighters/${F.id}/index.js imports ./clips/index.js and maps every authored clip (registry source shows '${F.id}/...' in __ED.game.roster()), the game builds and runs with zero page errors and zero '[ed] ... threw' lines.
2. Watch it as a player would: a training sequence of every move (FIGHTERS=${F.id} src/game/tests/moves.mjs), each skill start -> aftermath, the full ultimate (SECTIONS=ult ULT=${F.id} capture.mjs) and a #demo AI match of ${F.id} vs another fighter (a few frames at 5-30 s). Read every sheet. Judge against MOVES.md and the flagship bar: animation sync with VFX (impact effects exactly on the impact frame, trails following the blade), camera readability, timing/weight, no white-outs, no clipping, feet planted, the ultimate's shot table respected.
3. Fix what is wrong directly in src/fighters/${F.id}/clips/**, present.js, index.js (you own all of them now). Prioritise the most visible problems first.
4. Perf: profile.mjs during the ultimate peak (draw calls, JS ms of the VFX / CHAR groups) — must stay inside CONTRACT.md budgets.
5. Write src/fighters/${F.id}/README.md: clip list, choreography per move, the ultimate's shot/beat table as implemented, known issues.
You own src/fighters/${F.id}/clips/**, src/fighters/${F.id}/present.js, src/fighters/${F.id}/index.js, src/fighters/${F.id}/fx*.js and src/fighters/${F.id}/README.md. Return the report; keyCaptures = the 3-5 best sheets (paths) showing skills and the ultimate.`, { label: `${F.id}-director`, phase: 'Direct', schema: REPORT })

return { fighter: F.id, anim, chor, director }
