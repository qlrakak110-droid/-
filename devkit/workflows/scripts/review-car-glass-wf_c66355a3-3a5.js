export const meta = {
  name: 'review-car-glass',
  description: 'Adversarially review the AAA tinted car glass shader module and its studio patch hooks',
  phases: [
    { title: 'Review', detail: '4 lenses: GLSL/three r147, render integration, patcher, look/perf' },
    { title: 'Verify', detail: 'one skeptic re-checks every finding against the code' },
  ],
}

const S = '/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad'
const CONTEXT = `
Context: a browser "Roblox studio" player (three.js r147, classic scripts) renders cars with js/taxi_model.js (5 car models, decoded
from embedded binary meshes; glass roles 'glass'/'glass_dark') and js/carskin_model.js (legacy sedan + mergeLow far-LOD merger), drawn by
js/render3d.js (near cars = cloned hi-detail templates, far cars = InstancedMesh per material bucket). Materials are opted into a Roblox
lighting model via RblxGfx.adopt (js/rblx_gfx/20_materials.js: install()/patch() chain onBeforeCompile; Roblox glass output line
"outgoingLight = ( totalDiffuse + totalEmissiveRadiance ) * diffuseColor.a + totalSpecular * 1.6;" under #ifdef RBX_GLASS, then Roblox fog
rbxAtmos with alpha). We added a new module js/car_glass.js (window.GWCarGlass) that makes tinted, premultiplied, Fresnel-reflective
glass (outer FrontSide pass + inner BackSide pass for the driver-seat camera, per-window VLT attribute 'cgw' from mesh islands,
windshield shade band, skyline reflections, far-LOD opaque gloss glass), and a Python patcher that inserts the module into the
embedded pack and adds anchored hooks to taxi_model.js / carskin_model.js / render3d.js.

Files (read them):
  ${S}/review/patched_car_glass.js        the new module (source of truth: /home/user/-/studio/car_glass.js)
  ${S}/review/patched_taxi_model.js       patched taxi_model.js (MODELS JSON line elided); hooks marked /*gw-carglass*/
  ${S}/review/patched_carskin_model.js    patched carskin_model.js; hooks marked /*gw-carglass*/
  ${S}/review/patched_render3d.js         patched render3d.js; hooks marked /*gw-carglass*/ (car skin section ~line 1866-2095)
  ${S}/review/orig_20_materials.js        RblxGfx material/adopt/patch code (unchanged)
  /home/user/-/tools/patch_car_glass.py   the patcher
  ${S}/unpack/core/vendor/three.min.js    three r147 (minified; grep ShaderChunk names like meshphysical_frag, lights_fragment_begin)
Facts already established: glass meshes are single outward-facing shells (normals agree with winding); model front is -Z; three r147
has no forceSinglePass (transparent DoubleSide = one pass); transparent sort = groupOrder, renderOrder, z, then id; the renderer may be
WebGL1 or WebGL2 (mobile phones are a target); scene.environment is a PMREM cube-UV texture on mid/high tiers and null on the low tier.
`

const FINDINGS = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          title: { type: 'string' },
          file: { type: 'string' },
          where: { type: 'string', description: 'function / line / snippet' },
          severity: { type: 'string', enum: ['critical', 'major', 'minor'] },
          failure: { type: 'string', description: 'concrete scenario: inputs/state -> wrong output, compile error or crash' },
          fix: { type: 'string', description: 'minimal concrete fix' },
        },
        required: ['title', 'file', 'where', 'severity', 'failure', 'fix'],
      },
    },
  },
  required: ['findings'],
}

const LENSES = [
  { key: 'glsl', prompt: `Lens: GLSL + three r147 shader integration of car_glass.js. Assemble (mentally or by actually concatenating the
three r147 chunks from three.min.js) the final fragment/vertex shader the material compiles to after RblxGfx.adopt's patch() and then
car_glass's patchShader(), for (a) adopted with USE_ENVMAP + ENVMAP_TYPE_CUBE_UV, (b) adopted without env map (low tier), (c) not adopted.
Look for: undeclared identifiers or wrong scope (geometry, rbxSV, rbxSkyGrad, getIBLRadiance, reflectedLight, totalDiffuse), redeclarations,
the attribute 'cgw' declared twice or missing, fwidth/derivatives on WebGL1 (is OES_standard_derivatives enabled for this material?),
precision issues on mediump mobile GPUs (pow of 0, atan, sin-hash on large args), gl_FrontFacing semantics for BackSide/DoubleSide
materials in r147 (FLIP_SIDED / DOUBLE_SIDED normal handling), whether the GLASS_LINE replacement actually matches the adopted shader text,
whether the program cache key / defines could make two different shaders share one program. You may write a small node script
under ${S}/review/ to build the shader strings with the real chunks (do not run browsers).` },
  { key: 'render', prompt: `Lens: rendering integration in render3d / taxi_model / carskin_model. Check: inner+outer mesh ordering for
transparent sorting (same position -> id order; does cloneCar preserve creation order / ids?), the BackSide inner mesh being cloned and
sharing materials, skinShadows (castShadow for transparent), interior visibility toggling, mergeLow for detail 'low' builds (does any inner
mesh exist there; does isInner skip work; is the 'glass' bucket geometry empty-safe; does ensureLow create it once per model key and do the
setMatrixAt / count loops handle a null glass entry), legacy CarSkinModel path (MAT.glass now GWCarGlass.both: door glass meshes, renderOrder 2,
gh.build material maps), the prepare() union-find on non-indexed geometry, attribute reuse across cached geometries and clones,
memory/perf per frame. Also: could anything throw when window.GWCarGlass is missing (module failed) — every hook must degrade to the
original behaviour.` },
  { key: 'patcher', prompt: `Lens: tools/patch_car_glass.py robustness and portability to OTHER (newer/older) studio HTML builds. Check:
GWPK pack read/write exactness (header offsets, order, gzip, base64, manifest raw/gz/files fields and whether the loader validates them —
read the loader in the HTML at /root/.claude/uploads/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/e22bf0d6-Gwangalli_Studio_v5_____.html around
lines 612-660 and 1654-1735 using offset/limit or grep, NOT whole-file reads: it is 27 MB with giant base64 lines),
regex on giant HTML (catastrophic backtracking? '</script>' inside JSON?), idempotency (re-running, running on a build that already has a
different car_glass.js), the 'repl in text' already-patched check vs a partially patched file, module insertion order in manifest.modules,
what happens if the manifest has no 'modules' or the core pack name differs, encoding of Korean text, Windows line endings, and that the
script refuses to write when a hook is missing. Run it on copies under ${S}/review/ if useful (input: ${S}/orig/studio_v5.html).` },
  { key: 'look', prompt: `Lens: physical plausibility, visual quality and mobile performance of the glass shading in car_glass.js. Check the
premultiplied blending math (One / OneMinusSrcAlpha; alpha = 1 - transmittance; colour = reflection + film scatter), Fresnel/transmission
formulas (n=1.52, path length), energy (can reflection + transmission exceed 1 badly?), the inside view (eye-adapted VLT, cabin
reflection), the skyline reflection pattern (aliasing, seams at atan wrap -pi/pi, banding, visible repetition), night detection via
rbxSkyZen luminance (day zen ~[0.21,0.32,0.70], night ~[0.004,0.006,0.016]), glint cap vs bloom, fog with alpha, and ALU/texture cost per
fragment on phones. Only report issues that would visibly look wrong or cost real performance, with the concrete fix.` },
]

phase('Review')
const reviews = await parallel(LENSES.map((l) => () =>
  agent(CONTEXT + '\n' + l.prompt + '\n\nReport only real, concrete defects (no style nits). Each finding needs a concrete failure scenario and a minimal fix. Empty list if nothing real.', { label: 'review:' + l.key, phase: 'Review', schema: FINDINGS })))
const all = reviews.filter(Boolean).flatMap((r, i) => (r.findings || []).map((f) => ({ ...f, lens: LENSES[i] ? LENSES[i].key : '?' })))
log(all.length + ' raw findings')
if (!all.length) return { confirmed: [], rejected: [] }

phase('Verify')
const VERDICTS = {
  type: 'object',
  properties: {
    verdicts: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          index: { type: 'number' },
          real: { type: 'boolean' },
          reason: { type: 'string' },
          fix: { type: 'string' },
        },
        required: ['index', 'real', 'reason'],
      },
    },
  },
  required: ['verdicts'],
}
const list = all.map((f, i) => `#${i} [${f.lens}/${f.severity}] ${f.title}\n  file: ${f.file} @ ${f.where}\n  failure: ${f.failure}\n  fix: ${f.fix}`).join('\n\n')
const v = await agent(CONTEXT + `\nYou are a skeptical verifier. For EACH finding below, re-read the actual code and decide if the failure
scenario really happens in this codebase (trace it concretely; for shader claims check the real r147 chunk text in three.min.js). Default to
real=false when the claim does not hold or is speculative. When real, give the corrected minimal fix.\n\n` + list, { label: 'verify:all', phase: 'Verify', schema: VERDICTS })
const byIdx = new Map((v && v.verdicts || []).map((x) => [x.index, x]))
const confirmed = [], rejected = []
all.forEach((f, i) => { const x = byIdx.get(i); (x && x.real ? confirmed : rejected).push({ ...f, verdict: x || null }) })
return { confirmed, rejected }
