export const meta = {
  name: 'research-car-interiors',
  description: 'Research real interior specs per car model for the Roblox AAA cabin styles',
  phases: [
    { title: 'Research', detail: 'one agent per model pair: web research of the real interior' },
  ],
}

const SPEC = {
  type: 'object',
  properties: {
    models: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          key: { type: 'string', description: 'short style id, e.g. sonata_dn8' },
          label: { type: 'string' },
          match: { type: 'array', items: { type: 'string' }, description: 'lowercase substrings that identify this car in a CarModel / model name (English + Korean), e.g. ["sonata","쏘나타"]' },
          wheel: { type: 'object', properties: {
            spokes: { type: 'number', description: '2, 3 or 4 (count visible spokes)' },
            layout: { type: 'string', description: 'exact spoke geometry: e.g. "two horizontal spokes + one lower", "4-spoke H shape", "wide flat lower spoke"' },
            logo: { type: 'string', enum: ['hyundai', 'genesis', 'kia', 'mercedes', 'none'] },
            hub: { type: 'string', description: 'hub/airbag cover shape' },
            buttons: { type: 'string' },
            paddles: { type: 'boolean' },
            rimColor: { type: 'string' },
          }, required: ['spokes', 'layout', 'logo', 'paddles'] },
          cluster: { type: 'object', properties: {
            type: { type: 'string', enum: ['panoramic', 'hooded', 'floating', 'analog', 'center'] },
            sizeIn: { type: 'number' },
            notes: { type: 'string' },
          }, required: ['type'] },
          center: { type: 'object', properties: {
            type: { type: 'string', enum: ['joined', 'integrated', 'floating', 'portrait', 'widescreen', 'none'] },
            sizeIn: { type: 'number' },
            notes: { type: 'string' },
          }, required: ['type'] },
          vents: { type: 'object', properties: {
            center: { type: 'string', description: 'e.g. "slim horizontal full-width line", "two vertical rectangles beside the screen", "four rectangular chrome-ringed", "two round"' },
            side: { type: 'string', description: 'e.g. "round chrome turbine", "rectangular", "integrated in the horizontal line"' },
          }, required: ['center', 'side'] },
          shifter: { type: 'object', properties: {
            type: { type: 'string', enum: ['buttons', 'crystal_dial', 'dial', 'lever', 'column', 'dash_lever', 'manual'] },
            notes: { type: 'string' },
          }, required: ['type'] },
          dash: { type: 'string', description: 'overall dashboard shape and layering, trim band material/position, special features (e.g. waterfall centre fascia, hidden-type vents, wing shape)' },
          console: { type: 'string', description: 'centre console layout: high/low, floating bridge, wireless charger, cupholders, rotary controllers, armrest' },
          climate: { type: 'string', description: 'climate control panel: touch panel, physical knobs, toggle switches' },
          doors: { type: 'string', description: 'door card: handles, speaker (brand/shape), seat-control buttons on door (Mercedes), ambient line, trim' },
          seats: { type: 'object', properties: {
            front: { type: 'string', description: 'bolsters, quilting/perforation pattern, headrest type' },
            rear: { type: 'string', enum: ['bench3', 'bench2', 'captain2', 'captain2_bench3', 'bench3_cab', 'none'] },
            material: { type: 'string', description: 'leather / nappa / cloth etc. and typical color' },
          }, required: ['front', 'rear', 'material'] },
          colors: { type: 'object', properties: {
            dash: { type: 'string', description: 'hex like #1c1c1e' },
            seat: { type: 'string' }, trim: { type: 'string', description: 'trim band color hex' },
            trimMaterial: { type: 'string', enum: ['wood', 'aluminium', 'piano_black', 'carbon', 'fabric', 'plastic'] },
            headliner: { type: 'string' }, ambient: { type: 'string', description: 'typical ambient light hex or "none"' },
            stitch: { type: 'string' },
          }, required: ['dash', 'seat', 'trim', 'trimMaterial', 'headliner', 'ambient'] },
          signature: { type: 'array', items: { type: 'string' }, description: '3-8 distinctive details that make this interior recognisable (each one buildable from simple parts)' },
          sources: { type: 'array', items: { type: 'string' } },
        },
        required: ['key', 'label', 'match', 'wheel', 'cluster', 'center', 'vents', 'shifter', 'dash', 'console', 'climate', 'doors', 'seats', 'colors', 'signature'],
      },
    },
  },
  required: ['models'],
}

const GROUPS = [
  ['Hyundai Sonata DN8 (2020-2023, pre-facelift, Korean domestic market incl. taxi/police versions)', 'Genesis G80 RG3 (2021-2024)'],
  ['Hyundai Tucson NX4 (2021-2023)', 'Kia Ray (2nd generation TAM, 2022 facelift)'],
  ['Kia Carnival KA4 (2021-2023, 9-seat and 7-seat)', 'Hyundai Porter II (1-ton truck, 2020s) and Hyundai Solati H350 ambulance (driver cab)'],
  ['Mercedes-Benz S-Class W223 (2021+)', 'Kia Morning / Picanto JA (2023 facelift)'],
  ['Hyundai Grandeur GN7 (2023+)', 'Hyundai Avante / Elantra CN7 (2021+)'],
  ['Kia K5 DL3 (2020+)', 'Hyundai Santa Fe MX5 (2024+) and BMW 5 Series G60 (2024+)'],
]

phase('Research')
const results = await parallel(GROUPS.map((g, i) => () => agent(
  `Research the REAL interiors of these cars with web search (press photos, reviews, brochures): ${g.join(' ; ')}.
For each car return one spec in the schema. Be concrete and accurate about what a driver sees: steering wheel spoke count and layout,
logo, buttons; instrument cluster type (hooded / floating / joined with the centre screen in one glass panel) and size; centre screen
type and size; air vent shapes and positions; gear selector type (push buttons, rotary dial, crystal sphere, column stalk, lever, dash-mounted
lever, manual); climate controls; console layout; door cards (speaker brand/shape, seat buttons); seat design; typical interior colours as
hex; ambient lighting; and 3-8 signature details that make it recognisable. The output drives a Roblox interior built from simple parts
(boxes, cylinders, wedges, ellipsoids) placed on an existing car's dashboard/seat anchors, so prefer details that are buildable that way.
Include 'match' substrings (lowercase English and Korean names, e.g. "sonata", "쏘나타", "dn8") so the game can pick the style from a model
name like "Hyundai Sonata (DN8)" or "Kia Morning". Cite 1-3 sources per car.`,
  { label: 'research:' + i, phase: 'Research', schema: SPEC })))
const models = results.filter(Boolean).flatMap((r) => r.models || [])
log(models.length + ' model specs')
return { models }
