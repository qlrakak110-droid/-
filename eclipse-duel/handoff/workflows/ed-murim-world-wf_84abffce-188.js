export const meta = {
  name: 'ed-murim-world',
  description: '흑일무림 world + identity: the arena rebuilt as the ruined summit duelling terrace 천무대 (then atmosphere on the new post pipeline, then a fresh-eyes check), while naming/UI and the synthesised soundtrack are restyled in parallel',
  phases: [
    { title: 'Restyle', detail: 'arena architecture -> murim; names + UI; audio palette' },
    { title: 'Atmosphere', detail: 'mist, light shafts, fog, wind on the new post features' },
    { title: 'Check', detail: 'fresh-eyes review in game' },
  ],
}
const SP = '/tmp/claude-0/-home-user--/8256de2b-7eff-573b-8afc-504b52b3c9af/scratchpad/murim-world'
const REPORT = { type: 'object', properties: { summary: { type: 'string' }, files: { type: 'array', items: { type: 'string' } }, api: { type: 'string' }, perf: { type: 'string' }, issues: { type: 'array', items: { type: 'string' } }, keyCaptures: { type: 'array', items: { type: 'string' } } }, required: ['summary', 'files', 'issues'] }
const HEAD = `You are a senior member of the team making 「흑일무림 黑日武林」 (code name ECLIPSE DUEL): an ORIGINAL murim (Korean martial-arts fantasy) action game — three.js r170, everything procedural and built in code, one self-contained HTML, 60 fps on phones. Project root: /home/user/-/eclipse-duel . The owner wants flagship AAA quality "in murim form" with the ambition of the best dark action RPGs.
READ FIRST, fully: MURIM.md (the binding art direction; it supersedes older wording everywhere), CONTRACT.md (conventions, budgets, quality tiers, 60 fps rules, module contracts) and the README of the module you own.
HARD RULES:
- Never run git commands that change repository state; never install packages; no network assets or downloaded fonts (everything procedural).
- Edit only the files your task lists. Many teams work at the same time (rendering: src/post, src/core/app.js, src/core/util.js; rig: src/char runtime; characters: src/char/materials.js, src/char/kit, src/char/weapons.js, src/fighters/*/design.js; RPG mode: src/rpg/** plus small hooks in src/main.js, src/game/index.js, src/ui/screens.js, src/input; VFX / camera teams later: src/vfx, src/game/feel.js, src/fighters/*/present.js, src/cam). Treat other modules as read-only APIs and report what you need from them in issues.
- Public APIs and identifiers stay stable (additive changes only): code ids kael / iska / vorn, clip names, preset names, env API (setFocus, setContact, setMood, pulse, prewarm, captureReflection, wind ...).
- Builds and captures: labs via node tools/shot.mjs <lab> ...; the game always as a private copy: node tools/shot.mjs game --as mw-<label> --hash "..." (never build dist/). 960x540 / 1280x720 --sheet-only contact sheets; read every image you make with the Read tool. Captures in shots/murim/<label>/, scratch files in ${SP}/<label>/.
- Budgets and the 60 fps rule hold (measure before / after with the lab stats and src/game/tests/profile.mjs).
- Originality: invented names, emblems, calligraphy texts and designs only; nothing from a specific novel, comic, film or game; no real-world-derived famous sects.`

phase('Restyle')
const [world, ident, audio] = await parallel([
  () => agent(`${HEAD}

YOUR ROLE: lead environment artist. You own src/env/** and src/labs/env.js.
TASK: rebuild the arena as 「천무대 天武臺」 per MURIM.md section 4, on the existing env architecture (geometry toolkit, relief/ornament atlas baked on the GPU, weathering stone shader, floor with puddles + same-frame reflection pass, far backdrop, sky with the eclipse, cloud sea, particles, moods, tiers) with the same footprint, API and budgets (env <= 45 draw calls; ~80k / 100k / 110k triangles low / mid / high):
- Floor: the great round terrace with OUR carved formation diagram (eclipse disc at the centre, rings of trigram-like bar groups, star points, seal-script-like bands of our own invented glyph shapes), cracks, puddles, an old duel's scars; a broken rim open to the cloud sea on the vista side.
- Architecture around it: stone lanterns (standing, leaning, toppled) with warm light pools (they can replace or join the braziers: keep the light count and the fixed light pool rules), bronze incense braziers with thin smoke, broken red timber columns on stone bases, a collapsed hall and a ruined mountain gate (산문) with curved tile roofs (기와: ridge, eave tiles, upturned corners), bracket sets (공포) simplified, faded 단청 bands as relief + colour, a hanging name board with brush characters (e.g. 天武), stone stairs and balustrades, tattered sect banners and paper talisman ropes moving in the wind, weapon racks, fallen roof tiles and timber. The relief atlas motifs become East Asian (clouds, waves, lotus / peony rosettes, thunder-pattern meanders, tiger / dragon-scale bands of our own drawing).
- Vegetation as ink silhouettes: twisted pines on rocks, bamboo clumps swaying, dry grass in the cracks, falling leaves.
- The two colossal figures in the haze become armoured guardian martial deities (수호무신상): stern masked faces under flared helmets or crowns, layered armour skirts, one hand on a planted glaive / great saber, the other in a warding gesture; weathered, one damaged. Document their exact positions, sizes and the plinth of the one nearest the terrace in src/env/README.md (the RPG boss team animates one of them).
- Backdrop: jagged ink-painting peaks rising from the cloud sea in layered haze, a distant pagoda silhouette, the eclipse and corona unchanged as the central motif.
- Keep the fight view calm and readable behind the fighters (dark, desaturated, low contrast directly behind the duel line), detail in the cinematic angles. The arena must not look like a western colosseum anywhere any more; it must not look like a theme park either: ruined, wet, cold, grand.
- The RPG mode walks the terrace in third person and turns 360 degrees: make every direction hold up (close the side that faced the old fixed camera with the collapsed hall / gate / stairs), with colliders data exported for solid things (additive export, e.g. env.colliders or a documented list) so src/rpg can use it.
Work in passes with before / after sheets: fight views (near / mid / far at 1280x720 and 1600x720), the lab's cinematic angles (cine scenarios), a 360-degree turnaround from the terrace centre and from two edge spots, all three tiers, then in game (a #demo match). Update src/env/README.md. Return the report.`, { label: 'murim-arena', phase: 'Restyle', schema: REPORT }),
  () => agent(`${HEAD}

YOUR ROLE: UI art director + narrative designer. You own src/ui/** (screens, hud, roster, icons, anim, css, touch, README), src/fighters/registry.js (roster / menu data), the display-name fields and comments of src/fighters/{kael,iska,vorn}/moves.js (names only: never change frame data, ids, markers or numbers), src/fighters/MOVES.md, src/fighters/BALANCE.md (names only), src/index.html (title / tokens) and the user-facing strings in src/game/*.js (announce texts, cards) — in src/game touch strings only, with small exact edits.
CAUTION: the RPG team adds ONE title-menu entry and small hooks in src/ui/screens.js, src/game/index.js and src/main.js while you work: always make small targeted edits (never rewrite those files wholesale), re-read a file right before editing it, and preserve anything of theirs you find.
TASK:
1. Names: apply MURIM.md sections 2-3 everywhere the player reads text: game title 「흑일무림 黑日武林」 (subtitle ECLIPSE DUEL), hero names / titles / sects / weapon and inner-art lines on the select screen and HUD, difficulty names, and a full 초식 name table for every move of the three heroes (Korean reading + Hanja + a short English gloss): normals as plain forms, skills as 절기, ultimates as 오의 (kael 「흑일분천 黑日焚天」, iska 「빙성낙월 氷星落月」, vorn 「구천뇌벌 九天雷罰」), each name matching what the move does (read MOVES.md and the move data). Write them into moves.js display fields, MOVES.md (keep the mechanics text, rename and re-flavour the beats: runes -> formation diagrams, armour -> robes etc.) and wherever the UI shows move names (skill slots, the ultimate cut-in).
2. UI restyle in the murim / ink-wash idiom while keeping layout logic, input handling and performance: title screen (brush-stroke title with a seal 낙관, the eclipse, ink mountains), character select (vertical name cartouches, sect emblem of our own design per hero, weapon line art redrawn: great saber / twin crescents / tasselled spear), VS screen, HUD (기혈 HP bars as ink-brushed bands with element inner glow, 내공 and 오의 gauges, the round timer as a burning incense stick or an eclipse dial with numerals, round pips as small seals), announcer cards (제 n 합, 겨뤄라!, 결 決, 무결 無缺, 향이 다 탔다, 승 勝 / 패 敗) with brush-in animations (transform / opacity only), the ultimate cut-in as a vertical calligraphy banner that does not cover the hero (lower third or side), result screen, pause, quality menu, the touch pad glyphs. System fonts only: build the brush feeling with procedural SVG / canvas strokes, dry-brush dividers, seals and paper / ink textures, and a serif (myeongjo) font stack for Korean + Hanja.
3. Check every screen at 1280x720, 844x390 --touch and 390x844 --touch (src/ui/tests + game flow captures): no clipped or overlapping text (the old portrait bugs: cropped title, overlapping names, overflowing select text must be gone), Hanja renders, contrast is readable over bright VFX.
4. Update src/ui/README.md and the roster docs. Return the report with the full name table in api.`, { label: 'murim-identity', phase: 'Restyle', schema: REPORT }),
  () => agent(`${HEAD}

YOUR ROLE: composer + sound designer (everything synthesised with WebAudio, no samples). You own src/audio/** and its lab / tests.
TASK: re-voice the game per MURIM.md section 5 while keeping the audio API, sound names, music cue names and mixer behaviour stable (other modules call play('ult_start'), music('battle'), etc.):
- Music: pentatonic modal writing (계면조 / 평조 feeling, our own melodies): title (sparse, wind, a lone breathy bamboo flute over a low drone), battle (driving 북 / 장구-like drum patterns, plucked zither ostinatos, flute calls, rising intensity layers the game already drives), ultimate overlay (taiko-weight drums, a struck gong, tremolo strings / zither rolls), victory / defeat stingers, an exploration / tension bed and a boss theme for the RPG mode (new cue names are additive: document them).
- Instruments by synthesis: breathy flute (noise + filtered pulse with vibrato and breath attack), plucked zither (Karplus-Strong with pitch bends / 농현 vibrato), bowed fiddle-like lead (optional), frame drums and big drums (pitched noise + sine thump), gongs / small gongs (inharmonic partials), wood clappers, wind and pine ambience.
- SFX re-voicing where it sells the genre: steel rings and blade-energy whooshes, heavy cloth / robe swishes on dashes, stomps (진각), paper-talisman / formation-diagram charge-ups instead of rune hums, thunder cracks, frost crystal chimes, fire roars, the round-call gong and the K.O. drum + gong, UI brush / seal sounds.
- Mix: headroom, ducking on ultimates and K.O., no clipping with many simultaneous hits (limiter), mobile-safe voice counts; first-gesture unlock unchanged.
Verify by rendering cues offline (OfflineAudioContext in the page via tools/shot.mjs --eval, or the audio lab) and inspecting numbers: peak / RMS per cue, spectral centroid, no NaN / clipping, loop seams continuous, voice count caps; plus a waveform / spectrogram sheet per music cue you actually look at. Update src/audio/README.md. Return the report (list any new cue / sound names in api).`, { label: 'murim-audio', phase: 'Restyle', schema: REPORT }),
])

phase('Atmosphere')
const atmo = await agent(`${HEAD}

YOUR ROLE: environment / atmosphere artist. You own src/env/** and src/labs/env.js. The arena was just rebuilt as 천무대: ${JSON.stringify(world).slice(0, 9000)}
The rendering team has upgraded (or is finishing) the post pipeline: read the header of src/post/index.js and the post / quality sections of CONTRACT.md for what exists now (scene depth texture, ambient occlusion, height + distance fog with in-scattering, light shafts / sun API, depth of field, colour grading presets, shadow frustum API). Use what is there; where a feature is missing, keep your side ready behind a capability check.
TASK: make the terrace breathtaking while the duel stays readable:
- Report the eclipse position / colour to the post light shafts and fog in-scattering; fog density / height / colour per mood (env.setMood must drive them: the ultimates' tinted dark world, the RPG boss phase); aim the shadow frustum API at the fight area.
- Volumetric feel: layered ground mist that hugs the terrace and soft-intersects geometry using scene depth, incense smoke threads rising from the braziers, light shafts through the broken hall and gate toward the camera, drifting leaves / ash / embers and paper talisman scraps in the air (cheap instanced, tiered), the cloud sea moving slowly, the corona breathing.
- Lighting: cool moonlit fill from the eclipse side and warm lantern bounce so side / over-the-shoulder cinematic angles and the RPG third-person views are not near-black, without washing out the fight view; lantern flicker stable at 60 fps.
- Wind: gentle gusts on env.wind driving banners, talisman ropes, bamboo, pine tips (the game passes env.wind to the fighters' cloth).
Budgets and API as before. Before / after sheets from the fight camera, the cinematic angles, a third-person 360 turnaround, and in game. Return the report.`, { label: 'murim-atmosphere', phase: 'Atmosphere', schema: REPORT })

phase('Check')
const check = await agent(`${HEAD}

YOUR ROLE: fresh-eyes art director for the world and identity pass. Reports: ${JSON.stringify({ world, ident, audio, atmo }).slice(0, 30000)}
You may edit src/env/**, src/labs/env.js, src/ui/**, src/fighters/registry.js, display strings in src/game/*.js and src/fighters/*/moves.js (names only), src/audio/**.
Review in game with a private build: title, select, VS, round intro, a #demo match per pairing (frames every few seconds), an ultimate per hero, K.O., result; desktop 1280x720, phone landscape 844x390 --touch and portrait 390x844 --touch; q=high / mid / low for the arena. Judge against MURIM.md: does every screen and every camera angle read as grim, grand murim ink-wash fantasy at a glance, with no leftover western names, runes, colosseum pieces or knight wording; is the duel readable; is the typography clean (no clipped / overlapping text); do budgets hold. Fix the most visible problems, re-capture, and list what remains. Return the report with keyCaptures = the 5-6 best sheets.`, { label: 'murim-world-check', phase: 'Check', schema: REPORT })

return { world, ident, audio, atmo, check }
