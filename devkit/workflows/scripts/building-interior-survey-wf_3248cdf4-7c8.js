export const meta = {
  name: 'building-interior-survey',
  description: 'Survey every enterable building interior in Gwangalli v7 (geometry, props, gameplay dependencies) to plan AAA interior upgrades',
  phases: [{ title: 'Survey' }],
}
const SP = '/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad'
const CTX = `Context: Roblox game "Gwangalli" (광안리, Busan). The user wants every building interior upgraded to AAA quality: every detail real-world accurate, interactive, nothing empty or shoddy. We previously did this for car interiors with a client LocalScript that reads existing parts, hides crude ones and builds detailed part-based replacements near the player.
Data available (read-only, do NOT modify anything outside ${SP}/bld):
- Static place (v7): ${SP}/v7place/place.bin. Parse with python: sys.path.insert(0, '${SP}/tools'); from gwpb import GWPB; G = GWPB(path). G.inst is a list of dicts {id, name, cls, parent, attrs}; G.prop(inst, 'CFrame') -> ('CF', x, y, z, [r00..r22]) world; G.prop(inst, 'Size') -> ('V3', x, y, z); also 'Color', 'Material', 'Transparency'. See ${SP}/geo/ana.py for a worked example (children map, walking a model, part listing).
- Runtime scripts of v7 (Luau, gameplay add-ons that may build or modify interiors at runtime): ${SP}/v7all/gen/addons/** (e.g. zip/ServerScriptService/GwangalliBuildings.luau, zip/ReplicatedStorage/GwangalliBuildingsShared/*, GwangalliHomesShared, GwangalliStaff, GwangalliGameplay/{ShopStaff,Details,JobCvs,Jobs,JobWorld}.luau, GwangalliWorkSpots, GwangalliCustomerShared, GwangalliPlayShared/Arcade, Career/{Cafe,Gukbap}, JobCvsPlus.luau). The workspace root is Workspace.Gwangalli.<district>.
Write your full findings as JSON to ${SP}/bld/<your key>.json and return the same structured summary. Coordinates in world studs. Be concrete (names, counts, sizes, positions). Quality notes must say what looks crude (boxy, missing, empty walls/floor) versus a real Korean venue of that type.`
const VENUE = { type: 'object', properties: {
  name: { type: 'string' }, path: { type: 'string' },
  bounds: { type: 'string', description: 'world AABB of the interior space min..max' },
  rooms: { type: 'array', items: { type: 'object', properties: { name: { type: 'string' }, center: { type: 'array', items: { type: 'number' } }, size: { type: 'array', items: { type: 'number' } }, floorY: { type: 'number' }, ceilingY: { type: 'number' } }, required: ['name', 'center', 'size'] } },
  props: { type: 'array', items: { type: 'string' }, description: 'existing props: name x count, shape, quality' },
  gameplay: { type: 'array', items: { type: 'string' }, description: 'runtime systems that use/modify this interior: points, NPC staff, job spots, prompts, attributes; what must not be blocked or renamed' },
  emptyOrCrude: { type: 'array', items: { type: 'string' } },
  realWorld: { type: 'array', items: { type: 'string' }, description: 'what a real Korean venue of this type contains (layout, fixtures, signage, products, lighting), as a checklist' },
  interactionIdeas: { type: 'array', items: { type: 'string' } },
  enterable: { type: 'boolean' },
}, required: ['name', 'path', 'bounds', 'rooms', 'props', 'gameplay', 'emptyOrCrude', 'realWorld', 'interactionIdeas', 'enterable'] }
const OUT = { type: 'object', properties: { venues: { type: 'array', items: VENUE }, notes: { type: 'string' } }, required: ['venues', 'notes'] }
const SYS = { type: 'object', properties: { systems: { type: 'array', items: { type: 'object', properties: { script: { type: 'string' }, role: { type: 'string' }, buildsAtRuntime: { type: 'string' }, dependsOn: { type: 'string' }, interactions: { type: 'string' }, constraintsForNewProps: { type: 'string' } }, required: ['script', 'role', 'buildsAtRuntime', 'dependsOn', 'interactions', 'constraintsForNewProps'] } }, rules: { type: 'array', items: { type: 'string' } }, notes: { type: 'string' } }, required: ['systems', 'rules', 'notes'] }
const GROUPS = [
  { key: 'cvs_delivery', what: 'Workspace.Gwangalli.convenience (GS25 광안리점 + 광안로 상가 building) and Workspace.Gwangalli.delivery (광안 딜리버리 office + 차고)' },
  { key: 'pcbang_karaoke', what: 'Workspace.Gwangalli.pcbang (광안 PC방 + 광안타워) and Workspace.Gwangalli.karaoke (광안 코인노래연습장 + 광안빌딩)' },
  { key: 'arcade_club', what: 'Workspace.Gwangalli.arcade (광안 게임랜드) and Workspace.Gwangalli.club (CLUB OCEAN 광안: Lobby, Restrooms, Corridor, VIPStair, dance floor, bar, etc.)' },
  { key: 'bowling', what: 'Workspace.Gwangalli.bowling (광안 락볼링클럽: 1층 interior 실내 (로비 카운터, 오락코너, 라운지, 분식코너, 화장실, ROCK_BOWL_BAR, 레인홀), 볼링레인, and 상층_2F-4F: 2F 광안당구클럽, 3F 헤어살롱 편집숍, 4F 광안휘트니스24, elevator halls)' },
  { key: 'hospital_garage', what: 'Workspace.Gwangalli.hospital (광안 메디컬 의원 + building) and Workspace.Gwangalli.garage (광안 오토 정비소 & 중고차: showroom, service bay with lift)' },
  { key: 'shops', what: 'Workspace.Gwangalli.shops: 바다옷장 (clothing), 광안 서프 & SUP, 광안 떡볶이, 행복 돼지국밥, 광안 치킨, 헤어살롱 물결, 바다약국 (each has Shell, Interior, Points, ShopBounds)' },
  { key: 'hotels_homes', what: 'Workspace.Gwangalli.landmarks (호메르스호텔, 호텔 아쿠아펠리스, 켄트호텔 + lobby, 수영구 생활문화센터 · 광안리 관광안내소) and Workspace.Gwangalli.homes (HomeEntrance_goshiwon/oneroom/officetel/apartment/penthouse) plus where home interiors actually live (GwangalliHomesShared)' },
]
const tasks = [
  () => agent(`${CTX}\n\nYour key: systems. Read the runtime scripts and explain, for each one that touches building interiors: what it builds or changes at runtime (props, NPC staff, counters, customers, work spots, ProximityPrompts, signs), which part/model names or attributes it depends on (e.g. Points, ShopBounds, Interior), what interactions already exist, and concrete rules a new client-side interior-detail script must follow so it never breaks gameplay (what not to hide, move, block, or collide with; streaming; names). Also say whether shop interiors are filled at runtime (so the static place looks emptier than the game).`, { label: 'survey:systems', phase: 'Survey', schema: SYS }),
  () => agent(`${CTX}\n\nYour key: districts. Scan Workspace.Gwangalli.{city, uptown, beachfront, millak, namcheon, coast, skyline, bridge, roads, landmarks} for buildings that have an enterable interior (interior floors/rooms, an Interior model, ShopBounds, doors you can walk through, furniture) versus facade-only blocks. List every enterable one as a venue (name, path, bounds, rooms, existing props, quality), and give counts of facade-only buildings per district. Skip the dedicated venue folders (convenience, pcbang, karaoke, arcade, club, bowling, hospital, garage, delivery, shops, homes).`, { label: 'survey:districts', phase: 'Survey', schema: OUT }),
  ...GROUPS.map(gp => () => agent(`${CTX}\n\nYour key: ${gp.key}. Survey: ${gp.what}. For each venue/room: interior bounds and rooms (floor/ceiling heights), every existing prop (by name, count, size, how crude), which gameplay systems use it (grep the runtime scripts for its names), what is empty or crude, a real-world checklist of what that kind of Korean venue contains (research from your knowledge; WebSearch allowed), and good interaction ideas (ProximityPrompt-level: open fridge, pick snack, karaoke song select, PC on, arcade play, bowling ball rack, etc.).`, { label: `survey:${gp.key}`, phase: 'Survey', schema: OUT })),
]
const res = await parallel(tasks)
return res
