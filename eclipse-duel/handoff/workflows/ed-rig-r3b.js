export const meta = {
  name: 'ed-rig-r3',
  description: 'ECLIPSE DUEL rig round 3: finish the round-2 fixes (fighter clips protected), re-audit / fix until clean, then the motion QA toolkit over all 108 fighter clips',
  phases: [
    { title: 'Audit', detail: 'independent rig audits, each lens measured' },
    { title: 'Fix', detail: 'apply fixes, build regression suite' },
    { title: 'Motion QA', detail: 'clip naturalness metrics + CLI for animators' },
  ],
}

const RIG_REPORT = '(see the files in the scratchpad rig3 folder)'
const R3 = '/tmp/claude-0/-home-user--/8256de2b-7eff-573b-8afc-504b52b3c9af/scratchpad/rig3/'

const FINDINGS = {
  type: 'object',
  properties: {
    findings: { type: 'array', items: { type: 'object', properties: {
      id: { type: 'string', description: 'short unique id, prefix with your lens, e.g. SKIN-03' },
      severity: { type: 'string', enum: ['critical', 'major', 'minor'] },
      title: { type: 'string' },
      detail: { type: 'string', description: 'what is wrong, where (file:line / bone / clip / pose), how to reproduce' },
      evidence: { type: 'string', description: 'measurement values and/or capture paths' },
      suggestedFix: { type: 'string' },
    }, required: ['id', 'severity', 'title', 'detail', 'evidence'] } },
    measurements: { type: 'string', description: 'table of the metrics you measured with values and thresholds' },
    labFile: { type: 'string', description: 'your audit lab file with the reusable measurement code' },
    verdict: { type: 'string', description: 'one paragraph: how close is this lens to AAA-perfect' },
  },
  required: ['findings', 'measurements', 'verdict'],
}
const FIXREPORT = {
  type: 'object',
  properties: {
    summary: { type: 'string' },
    fixed: { type: 'array', items: { type: 'string' }, description: 'finding ids fixed AND re-verified with the same measurement' },
    deferred: { type: 'array', items: { type: 'string' }, description: 'id: reason' },
    regression: { type: 'string', description: 'how to run the rig regression suite and its current results' },
    apiChanges: { type: 'string', description: 'any change to the public char API or clip format (should be none or additive)' },
    files: { type: 'array', items: { type: 'string' } },
  },
  required: ['summary', 'fixed', 'deferred', 'regression'],
}
const REPORT = {
  type: 'object',
  properties: { summary: { type: 'string' }, files: { type: 'array', items: { type: 'string' } }, screenshots: { type: 'array', items: { type: 'string' } }, apiNotes: { type: 'string' }, issues: { type: 'array', items: { type: 'string' } } },
  required: ['summary', 'files', 'issues'],
}

const HEAD = `You work on ECLIPSE DUEL, an original dark-fantasy 1v1 3D fighting game (three.js r170, single-file WebGL2 build, 60 fps on phones). Project root: /home/user/-/eclipse-duel .
FIRST read CONTRACT.md fully (note the flagship quality standard, the 60 fps rule and the colossal-boss roadmap), then src/char/README.md, every file in src/char/, src/char/designs/knight.js, src/char/clips/demo.js, src/labs/char.js, src/core/lab.js, tools/shot.mjs and src/fighters/MOVES.md.
The client's words: "rigging must be perfect first" and "make it natural through hundreds of rigging tasks". The character runtime (skeleton, smooth-skinned under-suit + rigid plates, clip mixer, IK, grip, foot planting, spring bones, verlet cloth) was just written by one engineer. Dozens of fighters' worth of animation (about 150-200 clips: locomotion, guard, dodge, hit reactions, knockdown and get-up, attack chains, skills, ultimate cinematics) will be authored on top of it next, for three body types: KAEL (heavy greatsword knight ~1.95 m), ISKA (slender agile twin-blade oracle ~1.78 m, female proportions), VORN (tall spear lancer ~2.02 m), and later a colossal ~8 m boss. Every defect in the rig multiplies across all of that.
Rules: never run git commands that change repository state; never install packages; deterministic (no Math.random); other engineers are concurrently editing src/vfx, src/env, src/audio, src/ui, src/input, src/game, src/cam and the ART files (src/char/materials.js, src/char/kit/, src/char/weapons.js, src/fighters/*/design*.js, src/labs/art.js) - never touch those. Captures go under shots/char/rig/.
Use node tools/shot.mjs <lab> ... to capture (contact sheets with --sheet-only; --at times are snapped to whole 1/60 s frames) and --eval "<js>" to get numbers out of the page. Prefer numbers to opinions: every claim needs a measurement or a capture you looked at with the Read tool.`

const LENSES = [
  { key: 'SKIN', title: 'skinning, deformation and range of motion', body: `Build src/labs/rigaudit_skin.js. Drive every joint through its full human range one at a time AND in hard combinations (elbow 0-150, knee 0-155, shoulder raise forward/side to 175 and behind 60, arm across chest, wrist twist +-90 with the forearm twist helpers, hip flexion 125 (lunge / high knee) and extension 30, deep squat with heels down, side lunge, spine twist +-60 and side bend +-30, neck +-70, a full overhead two-handed greatsword wind-up and the follow-through low behind the back). For each: close-up captures from front, 3/4 and side, plus numeric checks you design (for example: minimum distance from suit vertices to the bone axis vs rest = volume loss at elbows/knees/shoulders; plate-to-plate and plate-to-suit interpenetration depth by sampling vertices against the other mesh's bone-space capsules; suit poking through plates; visible gaps/cracks at the waist, armpit, groin, neck, wrists, ankles; normals and shading seams; candy-wrapper twist). Also check the deformation of the three body types by changing proportions (slender/female for ISKA, tall for VORN, and a 4.2x scaled giant) - nothing may break or detach.` },
  { key: 'MATH', title: 'skeleton math, conventions, IK, grip and ground contact', body: `Build src/labs/rigaudit_math.js. (1) Conventions: for every animated bone and every axis, apply +30 degrees and measure where the child joint / end effector moves in fighter space; compare with the README axis table and report every mismatch or ambiguity exactly. (2) Mirroring: mirrorPose/mirrorClip produce exact mirror images (numeric comparison of joint positions with z negated); facing flip (+1/-1) gives exact mirror positions. (3) IK: two-bone IK end-effector error over 500 random reachable targets per limb (report max/mean mm), behaviour at and beyond full reach (no snapping, soft clamp), pole stability (sweep targets across the body: does the elbow/knee ever flip sides or pop?), wrist/ankle orientation targets honoured, IK in each target space (root/origin/hips/chest) correct during root motion and spins. (4) Two-handed grip: hand-to-grip-socket distance every frame through every demo clip (should be ~0 mm) and fingers wrapped on the grip. (5) Ground contact: planted-foot world drift per clip (mm per planted interval), floor penetration of soles/toes, automatic pelvis drop behaviour, heel/toe roll. (6) Proportions and scale: same tests with ISKA-like, VORN-like and a 4.2x giant proportion set: IK, grip and contact still exact.` },
  { key: 'ANIM', title: 'animation runtime and motion naturalness metrics', body: `Build src/labs/rigaudit_anim.js and a NEW pure module src/char/qa.js (you may create this one file in src/char) exporting reusable metric functions that sample a clip on a character at 120 Hz and return numbers: weapon-tip path (arc-ness: curvature continuity, jerk spikes, straight-line segments during swings), max per-frame angular velocity and acceleration per bone (pops), joint-limit violations against a human range-of-motion table you define per bone (degrees, documented), centre-of-mass vs support polygon (balance: time spent unsupported while both feet are planted), planted-foot drift, floor penetration, loop-seam continuity (pose and velocity), crossfade pops between pairs of clips, root-motion vs foot-contact consistency (moon-walking), self-intersection proxies (capsule overlap between limbs/torso, weapon blade through the body). Use it on every demo clip and report. Also test the runtime: setClipTime scrubbing forward/backward is deterministic and frame-rate independent, events fire exactly once (including across loop boundaries, at dt 1/30, during hit-stop dt=0 and slow-mo), crossfade from every clip to every other clip, speed changes, additive / masked layers, flinch impulses spring back without drift, 1/30 vs 1/60 vs 1/120 stepping gives the same pose at the same time.` },
  { key: 'SIM', title: 'cloth, springs, robustness and performance', body: `Build src/labs/rigaudit_sim.js. Cloth and spring bones under: the spin finisher and the overhead slam, facing flips mid-swing, a 3 m teleport, a dt spike of 1/15, dt = 0 for 2 s (hit-stop) then resume, slow-motion 0.1x for 3 s, 120 Hz stepping, two characters overlapping. Measure: cape/tabard penetration into legs, torso and the floor (count of particles inside body capsules per frame), stretching (max edge length ratio), jitter at rest, energy blow-ups, NaN. Robustness: play() spam, unknown clip names, dispose() then renderer.info.memory deltas (geometries / textures must return to baseline), creating and disposing 20 characters. Performance (60 fps rule): CPU ms per char.update over 2000 updates for the high and low tiers, allocation hunting (read the hot paths for new / closures / array literals per frame), draw calls and triangles per character, shadow pass cost; budget is <= 1.0 ms per character on desktop.` },
]

let prevFindings = []
let prevFix = null

const LATE = `
IMPORTANT CONTEXT SINCE THE AUDITS (round 2+): three fighters now ship 108 authored clips that use this rig: src/fighters/kael/clips (29), src/fighters/iska/clips (38), src/fighters/vorn/clips (41), each loaded through its clips/index.js, with their real designs src/fighters/<id>/design.js (do NOT edit those folders; they belong to the animators / art team). Your fixes must not regress them: before changing behaviour, audit every fighter clip with src/char/qa.js auditClip on its own design (write the script in /tmp/claude-0/-home-user--/8256de2b-7eff-573b-8afc-504b52b3c9af/scratchpad/rig3/), and re-run it after: foot drift, floor penetration, intersections, pops must stay equal or improve; check a few in game too (node tools/shot.mjs game --as r3-rig --hash "training=kael,iska" ... __ED.game.pose(0, '<clip>', t) or forceMove). Never rebuild dist/.
The animators also reported these rig problems; treat them as findings (major unless noted):
- anim.js: an IK effector whose keys all have w:0 throws 'IK <foot> has no pos key' at compile (weight-only keys must be allowed).
- solveGrip: the off-hand arm holding a grip point is solved with no pole and ignores the clip's ik.handL.pole; its elbow flips in one frame (10-20k deg/s) when the grip passes behind the hip or the weapon rotates through backward aims. Honour handL.pole during grip and cap its swivel speed like the main arm.
- Arm IK: with the arm bent close to the shoulder, the wrist clamp moves the weapon 30-45 deg off the keyed aim; with gripAngle 40 a two-handed blade has a narrow feasible roll so chops/overheads deviate up to 60 deg silently. Make the solver honour aims better (distribute roll into forearm twist / clavicle) and expose a helper or document it.
- Foot IK in 'hips' space while the pelvis is inverted (backflips) twists both thighs ~180 deg (pole/orientation evaluated in the wrong frame).
- An effector blending between 'hips' and 'root' space while hips yaw differs by >90 deg between keys sweeps its target through the body (legs cross in spins): blend resolved world targets instead.
- qa.js jointLimits: arms raised near vertical report upperArm.z ~ -170 and twist ~ +-150 (Euler decomposition flip near 180 deg elevation) — use a swing-twist decomposition.
- The startup warning 'design has a weapon but no gripAngle' fires for KAEL and ISKA, whose clips were authored and verified with their current grips (VORN's clips use a 42 deg weapon-bone tilt key instead); keep the default behaviour identical for existing designs (a warning only, no behaviour change).
`

const rounds = []
const MAX_ROUNDS = 4
for (let round = 2; round <= MAX_ROUNDS; round++) {
  const fromFile = round === 2
  phase('Audit')
  log(`rig audit round ${round}`)
  const lenses = round === 1 ? LENSES : [
    { key: 'R' + round + 'A', title: 'deformation, range of motion, cloth and contact (re-audit)', body: `Re-run and extend the measurements of src/labs/rigaudit_skin.js, src/labs/rigaudit_sim.js and the regression suite. Verify each previously reported SKIN-/SIM- finding marked fixed really is fixed (same measurement), then hunt for anything the earlier auditors missed or that the fixes broke. Look at close-up captures with fresh eyes.` },
    { key: 'R' + round + 'B', title: 'math, IK, grip, runtime and naturalness metrics (re-audit)', body: `Re-run and extend the measurements of src/labs/rigaudit_math.js, src/labs/rigaudit_anim.js, src/char/qa.js and the regression suite. Verify each previously reported MATH-/ANIM- finding marked fixed really is fixed (same measurement), then hunt for anything the earlier auditors missed or that the fixes broke.` },
  ]
  if (fromFile) {
    phase('Fix')
    const fix2 = await agent(`${HEAD}

YOUR ROLE: rig fixer, round 2. Independent auditors measured the character runtime in two rounds. Their findings are in files (read them fully first):
- round 1 findings: ${R3}round1_findings.json
- the round-1 fixer's report: ${R3}round1_fix.json
- round 2 findings (27: 7 critical, 14 major) plus each auditor's measurement summary, lab file and verdict: ${R3}round2_findings.json
A previous round-2 fixer was interrupted part-way: its partial edits are already in src/char (committed). Check what is already done (git diff HEAD~3 -- src/char is NOT allowed to modify the repo, but reading git log / git diff is fine), then finish the job.
You own the rig files: src/char/{index,anim,skeleton,ik,build,shapes,cloth,spring,collide,rigmath,qa}.js, src/char/designs/knight.js, src/char/clips/demo.js, src/char/README.md, src/labs/char.js and src/labs/rigqa.js. Do not touch the art files (src/char/materials.js, src/char/kit/**, src/char/weapons.js, src/fighters/**, src/labs/art.js) — another team is upgrading the character materials right now.
1. Fix every critical and major finding of round 2, and every minor one that is cheap. Fix root causes in the runtime rather than hiding symptoms in the demo clips. If a finding is wrong, say so with evidence instead of fixing it.
2. After each fix, re-run the auditor's own measurement (their lab files are named in the round-2 file) and record before -> after numbers. Look at before/after captures for the visual ones.
3. Keep the public API and the clip format stable; only additive changes. If you must change behaviour authors rely on, update README.md precisely.
4. src/labs/rigqa.js scenario 'all' (node tools/shot.mjs rigqa --eval "__ED.lab.play('all')") must pass at the end; extend it with checks for what you fixed. Keep its runtime under ~60 s.
5. Keep the 60 fps budget: char.update <= 1.0 ms desktop per character, no per-frame allocations.
${LATE}
Return the fix report.`, { label: 'rig-fix-2', phase: 'Fix', schema: FIXREPORT })
    prevFindings = 'round-2 findings: see ' + R3 + 'round2_findings.json (27 findings: 7 critical, 14 major)'
    prevFix = fix2
    rounds.push({ round: 2, counts: { total: 27, critical: 7, major: 14 }, fix: fix2 ? { fixed: fix2.fixed, deferred: fix2.deferred, regression: fix2.regression } : null })
    continue
  }
  const audits = await parallel(lenses.map((L) => () => agent(`${HEAD}

YOUR ROLE: independent rig auditor, lens "${L.title}" (finding id prefix ${L.key}), round ${round}. You did not write this code; assume it has defects and find them. You are READ-ONLY on src/char/ (the only exceptions: your own lab file named below${L.key === 'ANIM' ? ', and the new file src/char/qa.js' : ''}). Do not fix the runtime yourself: report precisely so a fixer can act.
${round > 1 ? `Previous round findings: ${JSON.stringify(prevFindings).slice(0, 30000)}
Fixer report from the previous round: ${JSON.stringify(prevFix).slice(0, 12000)}
` : `Rig engineer's own report: ${RIG_REPORT.slice(0, 12000)}
`}
WHAT TO DO: ${L.body}

Severity guide: critical = visibly broken in normal play or will break clip authoring (wrong axis docs, IK flips, grip loss, detaching geometry, cloth through the body in common moves, NaN, >1 ms CPU); major = noticeable to a player in a close-up or in common moves, or a clear deviation from AAA motion quality; minor = polish. Return the findings object (every finding with evidence).`, { label: `audit-${L.key}`, phase: 'Audit', schema: FINDINGS })))
  const ok = audits.filter(Boolean)
  const all = ok.flatMap((a) => a.findings || [])
  const crit = all.filter((f) => f.severity === 'critical').length
  const major = all.filter((f) => f.severity === 'major').length
  log(`round ${round}: ${all.length} findings (${crit} critical, ${major} major) from ${ok.length} auditors`)
  rounds.push({ round, counts: { total: all.length, critical: crit, major }, verdicts: ok.map((a) => a.verdict) })
  if (round > 1 && crit === 0 && major <= 1) { prevFindings = all; break }

  phase('Fix')
  const fix = await agent(`${HEAD}

YOUR ROLE: rig fixer, round ${round}. Independent auditors measured the character runtime and reported the findings below. You own the rig files: src/char/{index,anim,skeleton,ik,build,shapes,cloth,spring,collide,rigmath,qa}.js, src/char/designs/knight.js, src/char/clips/demo.js, src/char/README.md, src/labs/char.js and src/labs/rigqa.js (create it). Do not touch the art files listed above.

Findings (all auditors, round ${round}): ${JSON.stringify(all).slice(0, 60000)}
Auditor measurement summaries: ${JSON.stringify(ok.map((a) => ({ measurements: a.measurements, labFile: a.labFile }))).slice(0, 20000)}

1. Fix every critical and major finding, and every minor one that is cheap. Fix root causes in the runtime (math, weights, helper bones, IK, solver order, cloth collision) rather than hiding symptoms in the demo clips. If a finding is wrong, say so with evidence instead of fixing it.
2. After each fix, re-run the auditor's own measurement (their lab files are listed above) and record before -> after numbers. Look at before/after captures for the visual ones.
3. Keep the public API and the clip format stable; only additive changes. If you must change behaviour authors rely on (axis docs, IK spaces), update README.md precisely.
4. Build/extend the rig regression suite in src/labs/rigqa.js: one scenario 'all' that runs every important measurement from the auditors' labs (and src/char/qa.js metrics on every demo clip, for the knight proportions plus ISKA-like, VORN-like and 4.2x giant proportions) and returns JSON {checks:[{name, value, limit, pass}], passed, failed}. Document in README how to run it: node tools/shot.mjs rigqa --eval "__ED.lab.play('all')". It must pass at the end of your work. Keep runtime under ~60 s.
5. Keep the 60 fps budget: char.update <= 1.0 ms desktop per character, no per-frame allocations.
${round >= 2 ? LATE : ''}
Return the fix report.`, { label: `rig-fix-${round}`, phase: 'Fix', schema: FIXREPORT })
  prevFindings = all
  prevFix = fix
  rounds[rounds.length - 1].fix = fix ? { fixed: fix.fixed, deferred: fix.deferred, regression: fix.regression } : null
}

phase('Motion QA')
const qa = await agent(`${HEAD}

YOUR ROLE: motion QA tooling engineer. The rig just went through ${rounds.length} audit/fix rounds (${JSON.stringify(rounds).slice(0, 8000)}). Three fighters already ship 108 clips (src/fighters/{kael,iska,vorn}/clips/index.js register them; each fighter folder has its real design.js) and more will follow; every clip must be checked for naturalness automatically before a human-style visual review. Build that tool on top of src/char/qa.js and src/labs/rigqa.js. You own src/char/qa.js, src/labs/clipqa.js, tools/clipqa.mjs (new), src/char/QA_REPORT.md (new) and the 'Motion QA' section of src/char/README.md. Never edit src/fighters/**.

Deliverables:
1. src/labs/clipqa.js: a lab that loads ALL registered clips (import every clip module via a generated index or a glob-free registry file src/char/clips/index.js that clip authors append one import line to - create it and document the convention; include demo.js) and a design chosen by URL flag (#design=knight|kael|iska|vorn when those exist, falling back to knight with matching proportions presets), with scenarios: qa(clipName) -> metrics JSON with pass/fail per check and an overall grade, sheet(clipName) for capture use, and pair(clipA, clipB) for crossfade checks.
1b. Use the fighters' real designs (src/fighters/<id>/design.js) for their clips: #design=kael|iska|vorn.
2. tools/clipqa.mjs: CLI. node tools/clipqa.mjs <clip> [<clip>...] [--design kael] [--all] [--fighter kael] -> builds once, prints a compact table per clip (each metric value vs limit, PASS/FAIL), writes JSON to shots/char/qa/<clip>.json and ONE contact sheet per clip (fight camera, 8-12 frames spread over the clip, with the hit/trailOn events marked in the labels) to shots/char/qa/<clip>_sheet.png plus an optional 3/4-view sheet (--angles). Exit code 1 on any FAIL. It must handle 20+ clips per invocation efficiently (one browser session).
3. Metrics (each with a documented default limit and per-clip overrides through a clip's def.qa = {...} field): planted-foot drift, floor penetration (soles, toes, weapon tip unless allowed), joint range-of-motion violations, balance (COM vs support polygon while grounded, with allowance for authored lunges/falls), per-bone angular velocity/acceleration pops, weapon-tip arc quality in event-marked swing windows (trailOn..trailOff), grip separation for two-handed clips, self-intersection (limb/torso capsules, blade through body), loop seam continuity for looping clips, root motion vs foot contact consistency, event sanity (required events present: attacks need trailOn/hit/trailOff, steps on plants), timing sanity (anticipation, strike speed, recovery durations vs the clip's declared role), and a 'stiffness' metric (spine/hips/shoulder counter-rotation amplitude during attacks; flags puppet-like arm-only swings).
4. A short authoring checklist in README: how an animator writes a clip, runs clipqa, reads the sheet, and what each FAIL usually means and how to fix it.
5. Run it on every existing clip (demo + all 108 fighter clips, each on its own fighter design), write the summary table to src/char/QA_REPORT.md (worst offenders first), and make sure the limits are calibrated: good clips pass, deliberately broken test clips (create a few in your lab) fail for the right reason.
Return the report object.`, { label: 'motion-qa', phase: 'Motion QA', schema: REPORT })

return { rounds, finalFindings: prevFindings.filter((f) => f.severity !== 'minor'), lastFix: prevFix, qa }
