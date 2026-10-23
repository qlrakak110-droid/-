export const meta = {
  name: 'car-logo-design',
  description: 'Design part-built steering-wheel emblems (Hyundai, Kia, Genesis, fictional brand) as primitive lists, preview, critique, refine',
  phases: [{ title: 'Design' }, { title: 'Critique' }, { title: 'Refine' }],
}
const DIR = '/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/logo'
const TOOL = `Preview tool: python3 ${DIR}/render.py <emblem.json> <out.png> [px_per_stud=4000] [bg=hub|white]. Read ${DIR}/render.py first: its docstring defines the JSON format and the exact primitive semantics (stroke s, box b, ellipse e, ring/arc r, triangle tri, convex polygon poly; looks chrome|dark|gloss|satin|white|red; later primitives draw on top). It prints the primitive and Roblox part count. Open the PNG with the Read tool to look at it. The Luau builder builds exactly these primitives as Roblox parts, so the preview is what the game shows.`
const CTX = `Context: a Roblox game (Gwangalli, Busan) builds realistic car interiors from parts. The steering-wheel airbag pad carries the brand emblem, built from flat chrome parts lying on the dark leather pad (colour 'hub' = the preview background). In game it is seen from the driver's seat about 1.5 studs away, roughly 40-90 px wide on screen, so silhouette, proportions, stroke weights and spacing matter far more than tiny details. It must be clearly recognisable as the real logo, "even if not exactly the same, at least similar" (the user's words). Constraints: total Roblox parts <= 60 (the tool prints the count); no stroke or gap thinner than 0.004 studs; keep everything inside the declared w x h box; use 'chrome' for the logo, optionally 'dark'/'gloss' for a field; coordinates in studs, origin at the emblem centre, +y up.`
const BRANDS = [
  { key: 'hyundai', w: 0.17, h: 0.105, spec: 'Hyundai Motor Company emblem (current, used on the Sonata DN8, Tucson NX4, Porter II and Solati steering wheels): a horizontally elongated chrome oval OUTLINE (about 1.6:1, fairly thin ring) around a stylised italic "H". The H is not a block letter: its two uprights lean right and are gently curved (like two people shaking hands), and the crossbar is a slanted stroke rising to the right that joins them. On the steering wheel it is chrome on the black pad with no filled background.' },
  { key: 'kia', w: 0.16, h: 0.058, spec: 'Kia 2021+ logo (used on the Ray and Carnival KA4 steering wheels): the "KIA" wordmark written as one rhythmic, handwritten-like line. Distinctive traits: no oval; the K, I and A are made of thin uniform strokes; the A has no crossbar (an inverted V); letters sit very close, with the strokes connected so the word looks like a single continuous signature. Get the stroke angles right: the K\'s arms, the A\'s steep legs.' },
  { key: 'genesis', w: 0.26, h: 0.075, spec: 'Genesis winged emblem (G80 RG3 steering wheel): a central crest/shield (chrome outline, flat top, sides curving down to a rounded point at the bottom, with a dark inner field and a tiny "GENESIS" text band suggested by a thin chrome bar) flanked by a pair of horizontal wings. Each wing is a stack of horizontal chrome feather stripes (roughly 6-8), longest at the top and shortening toward the bottom, outer ends cut at a slant so the wing tapers. Overall about 3.5:1 wide.' },
  { key: 'generic', w: 0.13, h: 0.13, spec: 'An ORIGINAL badge for fictional showroom cars of the in-game brand "광안 모터스" (Gwangan Motors). It must not resemble any real carmaker\'s logo. Suggested idea: a chrome circle ring containing two or three stylised sea waves (Gwangalli beach) or the outline of the Gwangan Bridge arc; clean, premium, readable at small size.' },
]
const DESIGN = { type: 'object', properties: { json_path: { type: 'string' }, png_path: { type: 'string' }, parts: { type: 'number' }, notes: { type: 'string' } }, required: ['json_path', 'png_path', 'parts', 'notes'] }
const CRIT = { type: 'object', properties: { score: { type: 'number' }, recognisable: { type: 'boolean' }, defects: { type: 'array', items: { type: 'string' } } }, required: ['score', 'recognisable', 'defects'] }

const critique = (b, d, round) => parallel([0, 1].map(i => () => agent(
  `${CTX}\n\nYou are an independent, skeptical brand-design critic (critic ${i + 1}, round ${round}). Brand: ${b.key}. Target: ${b.spec}\nLook at the preview ${d.png_path} (also read the JSON ${d.json_path} and ${DIR}/render.py for the format). You may render it again at other scales (e.g. px_per_stud 600 to see the in-game size) with the tool. Judge how recognisable and how close to the real logo it is at the in-game size and up close. Score 1-10 (10 = unmistakably the real logo). List concrete defects with exact coordinates/values to change. Do not edit files.`,
  { label: `crit:${b.key}:${round}:${i}`, phase: 'Critique', schema: CRIT })))

const results = await pipeline(
  BRANDS,
  b => agent(`${CTX}\n\n${TOOL}\n\nDesign the ${b.key} emblem. Target: ${b.spec}\nDeclared box: w=${b.w}, h=${b.h}. You may use WebSearch to check details of the real logo. Write ${DIR}/${b.key}_v1.json (fields name, w, h, prims), render it, look at the PNG, and iterate at least 3 times (save each as _v2, _v3...), checking it also at px_per_stud 600 (in-game size). Finish with the best version saved as ${DIR}/${b.key}_best.json and its PNG ${DIR}/${b.key}_best.png.`, { label: `design:${b.key}`, phase: 'Design', schema: DESIGN }),
  async (d, b) => {
    let cur = d
    let history = []
    for (let round = 1; round <= 3; round++) {
      const cs = (await critique(b, cur, round)).filter(Boolean)
      const avg = cs.reduce((s, c) => s + c.score, 0) / Math.max(1, cs.length)
      history.push({ round, avg, defects: cs.flatMap(c => c.defects) })
      log(`${b.key} round ${round}: critic avg ${avg.toFixed(1)}`)
      if (avg >= 8.5 && cs.every(c => c.recognisable)) break
      if (round === 3) break
      cur = await agent(`${CTX}\n\n${TOOL}\n\nRefine the ${b.key} emblem. Target: ${b.spec}\nCurrent: ${cur.json_path} (preview ${cur.png_path}). Independent critics scored it ${avg.toFixed(1)}/10 and listed:\n- ${cs.flatMap(c => c.defects).join('\n- ')}\nFix every valid point (ignore any that contradict the real logo, and say which). Render and look at the result, iterate until it is clearly better, check it at px_per_stud 600 too. Save as ${DIR}/${b.key}_r${round}.json and .png, and also overwrite ${DIR}/${b.key}_best.json / ${DIR}/${b.key}_best.png with it.`, { label: `refine:${b.key}:${round}`, phase: 'Refine', schema: DESIGN })
    }
    return { brand: b.key, final: cur, history }
  }
)
return results.filter(Boolean)
