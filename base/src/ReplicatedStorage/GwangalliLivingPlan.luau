-- GwangalliLivingPlan (LP): THE PLAN of the representative living-city building
-- "광안 오션뷰 레지던스" (광안해변로 215). Binding data for every builder of docs/living_city_contract.md:
--   shell      builds every wall / slab / door / window / balcony / core part FROM THIS DATA (so the facade
--              and the interior can never disagree), plus the unit fixtures listed per room kind;
--   systems    reads doors, rooms, the elevator and the stair from here (ids, hinge, swing, levels);
--   shops      fits out the shop bays inside the zones given here;
--   homes_econ reads the unit list (area, rooms, view, floor, balcony, parking) for listings / contracts;
--   decor      reads rooms (room ids, surfaces) and doors (swing arcs = no-placement zones).
-- Pure data + pure helpers. No instances, no Roblox services at require time: Lune (build) and Roblox
-- (runtime) both require it. Owner after the architect: shell (append-only changes, keep ids stable).
--
-- COORDINATES (building-local, studs, 1 stud = 0.3 m):
--   u = along the sea facade. u = -29 is the EAST facade (on 광안해변로209번길, windows), u = +29 is the
--       WEST party wall against 호메르스호텔 (blank, no openings).  (u follows the kit's SITE FRAME:
--       RightVector of Plan.frame(323, 107) = viewer's right standing on the beach looking at the facade.)
--   w = depth, into the building. w = 0 is the SEA facade (front, 광안해변로 / beach), w = 64 the REAR
--       facade (parking yard, back lane). Front balconies project to w = -4 (inside the lot).
--   v = height above the 1F finished floor (world y = 6.5 + v).
--   K.at(frame, u, v, w) with frame = Plan.frame(LP.FRAME.station, LP.FRAME.n) maps these to the world.
--   Runtime code (no Plan module): LP.toWorld / LP.fromWorld below use the precomputed frame.
-- ROOM RECTS are CLEAR interior rectangles {u0, u1, w0, w1} (inner faces of the walls). Walls are the
--   GAPS between rects: 0 = open (same space, no wall), 0.5 = partition inside a unit / shop,
--   0.8 = unit divider / corridor / core wall, 1.0 = exterior wall (envelope). Any other gap is a bug
--   (LP.validate reports it). Envelope inner faces: u = -28 / +28, w = 1 / 63 (9F: w = 18 for the
--   enclosed part, the 9F front w 1..17 is the PH roof terrace).
-- DOORS sit on the wall between rooms a and b. `at` = centre coordinate along that wall (u for a wall
--   running along u, w for a wall running along w). hinge = "low" | "high": the hinge is at the lower /
--   higher coordinate end of the opening. swing = the room id the leaf opens INTO (nil for slide,
--   opening, glass_auto, elevator). The swing arc (quarter square width x width on the swing side) is
--   checked by LP.validate to stay inside the swing room.
-- WINDOWS: side = "front" (w = 0) | "east" (u = -29) | "rear" (w = 64) | "terrace" (9F wall at w = 17..18);
--   a, b = range along that facade (u for front / rear / terrace, w for east); sill / head relative to
--   the floor's FFL (defaults by kind: LP.WINDOW_KINDS). Jambs are on a 0.2 grid, >= 0.6 from the room
--   edge. The west facade has no openings (party wall).

local LP = {}
LP.VERSION = 1
LP.M_PER_STUD = 0.3
LP.SQ_M_PER_SQ_STUD = 0.09

-------------------------------------------------------------------------------------------------
-- Building, site, frame
-------------------------------------------------------------------------------------------------
LP.BUILDING = {
	id = "lc_tower",
	name = "광안 오션뷰 레지던스",
	nameEn = "GWANGAN OCEAN VIEW RESIDENCE",
	address = "광안해변로 215",
	use = "주상복합 (근린생활시설 1-2층 + 공동주택 3-9층)",
	width = 58, -- u in [-29, 29]
	depth = 64, -- w in [0, 64]
	floorsAbove = 9,
	-- what this building REPLACES (the shell removes it: see docs/living_city_contract.md §A.1)
	replaces = {
		file = "build/data/beachfront.luau",
		addr = "광안해변로 215",
		name = "광안 오션뷰 레지던스 (13층 판상형 + 1층 바다곁 파스타, real = false)",
		seg = 6,
	},
}
-- Site frame: Plan.frame(323, 107) at y = Plan.WALK = 6.5 (rowA n0 = 103 + a 4-stud forecourt).
LP.FRAME = { station = 323, n = 107, y = 6.5 }
-- Precomputed from build/kit/plan.luau (the shell asserts these match Plan.frame within 0.01 stud):
LP.ORIGIN = { 325.23907, 6.5, 103.596306 } -- world position of (u, v, w) = (0, 0, 0)
LP.RIGHT = { -0.9997809, 0, 0.020935103 } -- world direction of +u
LP.LOOK = { 0.020935103, 0, 0.9997809 } -- world direction of +w (inland)

-- Site extents (building-local)
LP.SITE = {
	forecourt = { u0 = -29, u1 = 29, w0 = -4, w1 = 0 }, -- n 103..107: entrance canopies, cafe terrace, under the balconies
	yard = { u0 = -29, u1 = 29, w0 = 64, w1 = 125.5 }, -- n 171..232.5: rear courtyard + parking (back lane starts at n 235 = w 128)
	eastStrip = { u0 = -33, u1 = -29, w0 = -4, w1 = 125.5 }, -- 4-stud strip to the 209번길 cross street (x 358): entrances face it
}

-- Thicknesses (studs) and level rules ------------------------------------------------------------
LP.WALL = { exterior = 1.0, core = 0.8, unit = 0.8, partition = 0.5, glass = 0.5 }
LP.SLAB = 1.0 -- structural slab 0.8 + finish 0.2; slab top = the floor's FFL
LP.CEILING_DROP = 1.2 -- ceiling underside = FFL + h - 1.2 (a 0.2 ceiling board under the slab)
LP.PARAPET = 3.6 -- roof parapet / terrace rail height
LP.BALCONY = { depth = 4.0, rail = 3.6, drop = 0.15 } -- balcony floor 0.15 below the room FFL (drainage)

-------------------------------------------------------------------------------------------------
-- Floors (v = FFL above the 1F floor; world y = 6.5 + v)
-------------------------------------------------------------------------------------------------
LP.FLOORS = {
	{ id = "1F", level = 1, v = 0, h = 14, kind = "commercial", band = "상가 (카페 · 편의점 · 부동산) + 주거 로비 · 관리사무소" },
	{ id = "2F", level = 2, v = 14, h = 12, kind = "commercial", band = "식당 (오션뷰 한식당) + 사무실 + 공용 화장실" },
	{ id = "3F", level = 3, v = 26, h = 10.5, kind = "residential", band = "원룸 층 (301-304) + 입주민 커뮤니티 (세탁실 · 라운지 · 세대 창고)" },
	{ id = "4F", level = 4, v = 36.5, h = 10.5, kind = "residential", band = "분리형 원룸 · 투룸 층 (401-404)" },
	{ id = "5F", level = 5, v = 47, h = 10.5, kind = "residential", band = "투룸 · 쓰리룸 층 (501-503)" },
	{ id = "6F", level = 6, v = 57.5, h = 10.5, kind = "residential", band = "가족형 4-bay + 후면 투룸 (601-602)" },
	{ id = "7F", level = 7, v = 68, h = 10.5, kind = "residential", band = "코너 가족형 + 오션 와이드 + 후면 1.5룸 (701-703)" },
	{ id = "8F", level = 8, v = 78.5, h = 10.5, kind = "penthouse", band = "펜트하우스 801 하층 (거실 · 주방 · 안방 · 게스트)" },
	{ id = "9F", level = 9, v = 89, h = 10.5, kind = "penthouse", band = "펜트하우스 801 상층 + 루프 테라스" },
	{ id = "RF", level = 10, v = 99.5, h = 0, kind = "roof", band = "옥상: 설비 공간 (물탱크 · 실외기 · 태양광) + 계단실 · 승강기 상부" },
}
LP.FLOOR_BY_ID = {}
LP.FLOOR_BY_LEVEL = {}
for _, f in LP.FLOORS do
	f.y = 6.5 + f.v
	f.ceiling = if f.h > 0 then f.h - LP.CEILING_DROP else 0 -- ceiling underside relative to FFL
	LP.FLOOR_BY_ID[f.id] = f
	LP.FLOOR_BY_LEVEL[f.level] = f
end

-------------------------------------------------------------------------------------------------
-- Vertical core (identical XZ on 1F-9F; the stair continues to RF)
-------------------------------------------------------------------------------------------------
LP.CORE = {
	elevatorShaft = { u0 = 9.0, u1 = 17.6, w0 = 37.6, w1 = 45.8 }, -- clear; walls 0.8 all round
	stair = { u0 = 18.4, u1 = 28.0, w0 = 37.6, w1 = 63.0 }, -- clear; west = party wall, north = rear wall
	eps = { u0 = 21.6, u1 = 24.4, w0 = 27.4, w1 = 30.0 }, -- 전기·통신 (EPS/TPS), access hatch from the corridor
	ps = { u0 = 24.9, u1 = 28.0, w0 = 27.4, w1 = 30.0 }, -- 배관 (PS), access hatch from the corridor
	-- the hall in front of elevator + stair, common to every floor (part of the corridor / lobby / hall room)
	hall = { u0 = 8.2, u1 = 28.0, w0 = 30.8, w1 = 36.8 },
}

LP.ELEVATOR = {
	id = "lc_tower.E1",
	name = "승강기 1호기",
	stops = { 1, 2, 3, 4, 5, 6, 7, 8, 9 }, -- levels served (RF: stair only)
	shaft = LP.CORE.elevatorShaft,
	pit = 4.0, -- shaft floor 4 studs below the 1F FFL (y = 2.5)
	overrunTop = 108.0, -- v of the overrun box top (RF v 99.5 + 8.5): machine-room-less
	car = {
		outer = { u0 = 9.3, u1 = 17.3, w0 = 37.8, w1 = 45.4 }, -- car floor plate (top flush with the stop's FFL)
		inner = { u0 = 9.6, u1 = 17.0, w0 = 38.1, w1 = 45.1 }, -- 7.4 x 7.0 clear: 6-8 avatars
		wall = 0.3,
		height = 8.8, -- clear inside
		roof = 9.6, -- top of the car roof above the car floor
		-- the car operating panel (COP) on the front wall, right of the door seen from inside
		cop = { u0 = 15.6, u1 = 16.9, w = 38.1, v0 = 2.8, v1 = 6.4 },
		display = { u0 = 11.6, u1 = 15.0, w = 38.1, v0 = 7.9, v1 = 8.6 }, -- above the door inside
	},
	door = {
		center = 13.3, -- u of the opening centre
		width = 4.4, -- clear opening u 11.1..15.5
		height = 7.6,
		panels = 2, -- centre opening; each panel 2.3 wide (0.1 overlap at the meeting edge)
		travel = 2.25, -- each panel slides 2.25 studs along u (left panel -u, right panel +u)
		landingPlane = { w0 = 37.15, w1 = 37.35 }, -- landing panels (in the 0.8 shaft-front wall w 36.8..37.6)
		carPlane = { w0 = 37.85, w1 = 38.05 }, -- car panels
		landingSill = { w0 = 36.8, w1 = 37.75 }, -- top flush with FFL
		carSill = { w0 = 37.8, w1 = 38.1 }, -- gap to the landing sill 0.05 stud
		sensor = { u0 = 11.1, u1 = 15.5, w0 = 36.4, w1 = 38.6, v0 = 0.5, v1 = 6.5 }, -- safety edge volume
	},
	-- landing equipment on the corridor face of the shaft wall (w = 36.8), per stop
	callPanel = { u0 = 16.0, u1 = 16.8, v0 = 3.2, v1 = 4.6 }, -- ▲ / ▼ (1F: ▲ only, 9F: ▼ only)
	hallDisplay = { u0 = 11.9, u1 = 14.7, v0 = 7.9, v1 = 8.7 }, -- floor number + direction arrow above the door
	lanterns = { u0 = 15.7, u1 = 16.5, v0 = 7.0, v1 = 8.4 }, -- ▲▼ arrival lanterns
}

-- Dog-leg stair: flight A (west, rises from the floor landing northward), mid landing at the rear,
-- flight B (east, rises back southward to the next floor landing). Walking surface = one invisible
-- wedge per flight (named StairRamp, CanCollide); visible treads CanCollide = false (no snagging).
LP.STAIR = {
	box = LP.CORE.stair,
	flightA = { u0 = 23.5, u1 = 28.0 }, -- 4.5 wide (west, along the party wall)
	flightB = { u0 = 18.4, u1 = 22.9 }, -- 4.5 wide (east)
	well = { u0 = 22.9, u1 = 23.5 }, -- 0.6 low wall + balustrade + handrails both sides
	floorLanding = { w0 = 37.6, w1 = 42.0 }, -- at every FFL, full width; the floor slab is solid here
	slabOpening = { u0 = 18.4, u1 = 28.0, w0 = 42.0, w1 = 63.0 }, -- opening in every floor slab above 1F
	flightStart = 42.0, -- both flights meet the floor landing at w = 42
	tread = 0.95, -- 28.5 cm
	maxRiser = 0.6, -- 18 cm
	door = { u0 = 19.2, u1 = 22.6 }, -- fire door in the stair's south wall (w 36.8..37.6), every floor + RF
	railHeight = 3.0,
	window = { u0 = 20.0, u1 = 26.4 }, -- rear facade window at every mid landing
}

-- Per-storey stair geometry (pure): returns risers, riser height, run length, mid landing w0.
function LP.stairFlight(h: number): (number, number, number, number)
	local half = h / 2
	local n = math.ceil(half / LP.STAIR.maxRiser - 1e-6)
	local r = half / n
	local run = (n - 1) * LP.STAIR.tread
	return n, r, run, LP.STAIR.flightStart + run
end

-------------------------------------------------------------------------------------------------
-- Room kinds: finishes, required fixtures (shell builds them, systems makes them work), light cap.
-- fixtures = kinds from GwangalliLivingShared.FIXTURE_KINDS (see the contract §B.4)
-------------------------------------------------------------------------------------------------
LP.FINISHES = {
	-- key = { material (Enum.Material name), colour {r,g,b}, note }
	wood_oak = { "WoodPlanks", { 178, 140, 100 }, "강마루 오크 (거실·방·주방)" },
	wood_grey = { "WoodPlanks", { 160, 146, 128 }, "그레이지 강마루 (오피스텔풍 유닛)" },
	wood_walnut = { "WoodPlanks", { 112, 80, 56 }, "월넛 원목 (펜트하우스)" },
	tile_entry = { "Slate", { 92, 90, 88 }, "현관 포쉐린 (다크)" },
	tile_bath_floor = { "CeramicTiles", { 120, 118, 114 }, "욕실 바닥 논슬립 타일" },
	tile_bath_wall = { "CeramicTiles", { 226, 224, 218 }, "욕실 벽 타일" },
	tile_porch = { "CeramicTiles", { 176, 168, 156 }, "발코니 · 다용도실 · 세탁실 타일" },
	marble_white = { "Marble", { 232, 230, 226 }, "로비 · 펜트하우스 대리석" },
	granite_stair = { "Granite", { 150, 146, 140 }, "계단 디딤판 · 공용복도 테라조" },
	terrazzo = { "Granite", { 196, 192, 186 }, "공용 복도 바닥" },
	carpet_office = { "Carpet", { 96, 100, 108 }, "사무실 카펫" },
	vinyl = { "SmoothPlastic", { 186, 176, 160 }, "데코타일 (창고 · 관리실)" },
	epoxy = { "SmoothPlastic", { 128, 134, 138 }, "에폭시 (전기실 · 분리수거장 · 주차장 바닥)" },
	deck = { "WoodPlanks", { 140, 104, 72 }, "테라스 데크" },
	silk = { "Plaster", { 236, 232, 224 }, "실크 벽지" },
	paint_common = { "Plaster", { 226, 222, 214 }, "공용부 도장 + 하부 걸레받이" },
	stone_panel = { "Limestone", { 214, 206, 192 }, "로비 석재 패널" },
	concrete_exposed = { "Concrete", { 168, 166, 160 }, "노출 콘크리트 (계단실 · 설비)" },
	brick = { "Brick", { 156, 92, 70 }, "벽돌 (1-2층 파사드 하부)" },
}

LP.ROOM_KINDS = {
	-- residential
	entry = { label = "현관", floor = "tile_entry", wall = "silk", fixtures = { "shoe_cabinet", "wallpad", "switch" }, lights = 1 },
	hall = { label = "복도", floor = "wood_oak", wall = "silk", fixtures = { "switch" }, lights = 2 },
	living = { label = "거실", floor = "wood_oak", wall = "silk", fixtures = { "curtain", "switch", "aircon" }, lights = 3, view = true },
	kitchen = { label = "주방", floor = "wood_oak", wall = "silk", fixtures = { "sink", "faucet", "base_cabinet", "drawer", "upper_cabinet", "cooktop", "hood", "fridge", "switch" }, lights = 2 },
	ldk = { label = "거실 겸 주방", floor = "wood_oak", wall = "silk", fixtures = { "sink", "faucet", "base_cabinet", "drawer", "upper_cabinet", "cooktop", "hood", "fridge", "curtain", "switch" }, lights = 3, view = true },
	room = { label = "원룸", floor = "wood_oak", wall = "silk", fixtures = { "wardrobe", "curtain", "switch", "aircon" }, lights = 2, view = true },
	bedroom = { label = "침실", floor = "wood_oak", wall = "silk", fixtures = { "wardrobe", "curtain", "switch" }, lights = 2, view = true },
	master = { label = "안방", floor = "wood_oak", wall = "silk", fixtures = { "wardrobe", "curtain", "switch", "aircon" }, lights = 3, view = true },
	alpha = { label = "알파룸", floor = "wood_oak", wall = "silk", fixtures = { "blind", "switch" }, lights = 1, view = true },
	study = { label = "서재", floor = "wood_oak", wall = "silk", fixtures = { "blind", "switch", "storage" }, lights = 2, view = true },
	dress = { label = "드레스룸", floor = "wood_oak", wall = "silk", fixtures = { "wardrobe", "drawer", "storage", "switch" }, lights = 1 },
	storage = { label = "창고·팬트리", floor = "vinyl", wall = "silk", fixtures = { "storage", "switch" }, lights = 1 },
	utility = { label = "다용도실", floor = "tile_porch", wall = "tile_bath_wall", fixtures = { "washer", "faucet", "storage", "switch" }, lights = 1 },
	bath = { label = "욕실", floor = "tile_bath_floor", wall = "tile_bath_wall", fixtures = { "basin", "faucet", "mirror_cabinet", "toilet", "shower", "switch" }, lights = 1, wet = true },
	master_bath = { label = "안방 욕실", floor = "tile_bath_floor", wall = "tile_bath_wall", fixtures = { "basin", "faucet", "mirror_cabinet", "toilet", "bathtub", "shower", "switch" }, lights = 2, wet = true },
	stair_private = { label = "내부 계단", floor = "wood_walnut", wall = "silk", fixtures = { "switch" }, lights = 1 },
	void = { label = "계단 오픈 (보이드)", floor = "none", wall = "silk", fixtures = {}, lights = 0 },
	terrace = { label = "루프 테라스", floor = "deck", wall = "none", fixtures = { "faucet", "seat_builtin" }, lights = 2, outdoor = true, view = true },
	-- common (공용부)
	corridor = { label = "공용 복도", floor = "terrazzo", wall = "paint_common", fixtures = { "exit_sign", "fire_hydrant_box" }, lights = 4, common = true },
	lobby = { label = "로비", floor = "marble_white", wall = "stone_panel", fixtures = { "parcel_locker", "sofa_builtin", "directory", "exit_sign" }, lights = 4, common = true },
	vestibule = { label = "전실 (공동현관 밖)", floor = "granite_stair", wall = "stone_panel", fixtures = { "mailbox", "intercom", "directory" }, lights = 2, common = true },
	hall_common = { label = "승강장 홀", floor = "terrazzo", wall = "paint_common", fixtures = { "exit_sign", "directory" }, lights = 2, common = true },
	mgmt = { label = "관리사무소", floor = "vinyl", wall = "paint_common", fixtures = { "desk_builtin", "storage", "switch" }, lights = 2, common = true },
	wc = { label = "공용 화장실", floor = "tile_bath_floor", wall = "tile_bath_wall", fixtures = { "basin", "faucet", "toilet" }, lights = 1, common = true, wet = true },
	laundry = { label = "공용 세탁실", floor = "tile_porch", wall = "tile_bath_wall", fixtures = { "washer", "dryer", "faucet", "switch" }, lights = 2, common = true },
	lounge = { label = "입주민 라운지", floor = "wood_oak", wall = "paint_common", fixtures = { "sink", "faucet", "fridge", "base_cabinet", "seat_builtin", "switch" }, lights = 4, common = true },
	lockers = { label = "세대 창고", floor = "vinyl", wall = "paint_common", fixtures = { "locker_bank", "switch" }, lights = 2, common = true },
	service = { label = "설비실", floor = "epoxy", wall = "concrete_exposed", fixtures = {}, lights = 1, common = true },
	rear_corridor = { label = "후면 복도", floor = "terrazzo", wall = "paint_common", fixtures = { "exit_sign" }, lights = 2, common = true },
	stair = { label = "계단실", floor = "granite_stair", wall = "concrete_exposed", fixtures = { "exit_sign", "floor_sign" }, lights = 2, common = true },
	elevator = { label = "승강로", floor = "none", wall = "concrete_exposed", fixtures = {}, lights = 0, common = true },
	shaft = { label = "PS / EPS", floor = "none", wall = "concrete_exposed", fixtures = {}, lights = 0, common = true },
	-- shop bays (interiors: shops builder; zones below)
	bay = { label = "상가", floor = "shop", wall = "shop", fixtures = {}, lights = 8, shop = true },
}

-------------------------------------------------------------------------------------------------
-- Rooms
-------------------------------------------------------------------------------------------------
LP.ROOMS = {} :: { [string]: any }
LP.ROOM_ORDER = {} :: { string }
LP.ROOMS_BY_FLOOR = {} :: { [string]: { string } }

local UNIT_IDS = {
	["301"] = true, ["302"] = true, ["303"] = true, ["304"] = true,
	["401"] = true, ["402"] = true, ["403"] = true, ["404"] = true,
	["501"] = true, ["502"] = true, ["503"] = true,
	["601"] = true, ["602"] = true,
	["701"] = true, ["702"] = true, ["703"] = true,
	["801"] = true,
}

local function room(floor: string, id: string, kind: string, label: string?, rects: { { number } }, opt: { [string]: any }?)
	assert(LP.ROOMS[id] == nil, "duplicate room id " .. id)
	assert(LP.ROOM_KINDS[kind], "unknown room kind " .. kind .. " (" .. id .. ")")
	local r: any = { id = id, floor = floor, kind = kind, label = label or LP.ROOM_KINDS[kind].label, rects = {} }
	for _, q in rects do
		table.insert(r.rects, { u0 = q[1], u1 = q[2], w0 = q[3], w1 = q[4] })
	end
	local dot = string.find(id, ".", 1, true)
	local prefix = if dot then string.sub(id, 1, dot - 1) else id
	if UNIT_IDS[prefix] then
		r.unit = prefix
	elseif kind == "bay" then
		r.bay = id
	else
		r.common = true
	end
	if opt then
		for k, v in opt do
			r[k] = v
		end
	end
	local kd = LP.ROOM_KINDS[kind]
	r.floorFinish = r.floorFinish or kd.floor
	r.wallFinish = r.wallFinish or kd.wall
	LP.ROOMS[id] = r
	table.insert(LP.ROOM_ORDER, id)
	LP.ROOMS_BY_FLOOR[floor] = LP.ROOMS_BY_FLOOR[floor] or {}
	table.insert(LP.ROOMS_BY_FLOOR[floor], id)
	return r
end

-- core rooms on every floor 1F-9F
for level = 1, 9 do
	local f = LP.FLOOR_BY_LEVEL[level].id
	local c = LP.CORE
	room(f, f .. ".elevator", "elevator", "승강로", { { c.elevatorShaft.u0, c.elevatorShaft.u1, c.elevatorShaft.w0, c.elevatorShaft.w1 } })
	room(f, f .. ".stair", "stair", "계단실", { { c.stair.u0, c.stair.u1, c.stair.w0, c.stair.w1 } })
	room(f, f .. ".eps", "shaft", "EPS·TPS", { { c.eps.u0, c.eps.u1, c.eps.w0, c.eps.w1 } })
	room(f, f .. ".ps", "shaft", "PS", { { c.ps.u0, c.ps.u1, c.ps.w0, c.ps.w1 } })
end

-- 1F (FFL v 0, h 14) ------------------------------------------------------------------------------
room("1F", "1F-A", "bay", "오션브루 커피 (카페)", { { -28.0, 3.6, 1.0, 30.0 } })
room("1F", "1F-B", "bay", "바다마트24 광안오션점 (편의점)", { { 4.4, 20.8, 1.0, 30.0 }, { 20.8, 28.0, 1.0, 26.6 } })
room("1F", "1F.vestibule", "vestibule", "전실 (우편함 · 공동현관 인터폰)", { { -28.0, -21.4, 30.8, 42.4 } })
room("1F", "1F.lobby", "lobby", "주거 로비 · 승강장", { { -20.9, 8.2, 30.8, 42.4 }, { 8.2, 28.0, 30.8, 36.8 } })
room("1F", "1F.mgmt", "mgmt", "관리사무소", { { -28.0, -14.6, 43.2, 50.2 } })
room("1F", "1F-C", "bay", "오션뷰 공인중개사사무소 (부동산)", { { -28.0, -14.6, 51.0, 63.0 } })
room("1F", "1F.rear", "rear_corridor", "후면 복도 (주차장 출입)", { { -13.8, -8.0, 43.2, 63.0 } })
room("1F", "1F.cvs_store", "storage", "편의점 창고", { { -7.2, 8.2, 43.2, 52.0 }, { 8.2, 17.6, 46.6, 52.0 } }, { bayOf = "1F-B" })
room("1F", "1F.wc_m", "wc", "상가 화장실 (남)", { { -7.2, 0.4, 52.8, 57.6 } })
room("1F", "1F.wc_f", "wc", "상가 화장실 (여)", { { -7.2, 0.4, 58.1, 63.0 } })
room("1F", "1F.electric", "service", "전기실", { { 1.2, 7.8, 52.8, 63.0 } })
room("1F", "1F.recycle", "service", "분리수거장", { { 8.6, 17.6, 52.8, 63.0 } }, { floorFinish = "epoxy" })

-- 2F (FFL v 14, h 12) -----------------------------------------------------------------------------
room("2F", "2F-A", "bay", "바다곁 밥상 (오션뷰 한식당)", { { -28.0, 20.8, 1.0, 30.0 }, { 20.8, 28.0, 1.0, 26.6 } })
room("2F", "2F.corridor", "corridor", "2층 복도", { { -28.0, 28.0, 30.8, 36.8 } })
room("2F", "2F.wc_m", "wc", "2층 화장실 (남)", { { -28.0, -24.0, 37.6, 46.0 } })
room("2F", "2F.wc_f", "wc", "2층 화장실 (여)", { { -23.5, -19.5, 37.6, 46.0 } })
room("2F", "2F-B", "bay", "광안 스튜디오 오피스 (디자인 사무소)", { { -18.7, 8.2, 37.6, 63.0 }, { -28.0, -18.7, 46.8, 63.0 }, { 8.2, 17.6, 46.6, 63.0 } })

-- 3F 원룸 층 (FFL v 26) ------------------------------------------------------------------------------
room("3F", "3F.corridor", "corridor", "3층 복도", { { -28.0, 28.0, 30.8, 36.8 } })
room("3F", "301.room", "room", "원룸 (침실 겸 거실)", { { 15.0, 28.0, 1.0, 18.5 } })
room("3F", "301.kitchen", "kitchen", "주방 (현관형 갤리)", { { 15.0, 20.8, 18.5, 24.1 } })
room("3F", "301.entry", "entry", nil, { { 15.0, 20.8, 24.6, 30.0 } })
room("3F", "301.bath", "bath", nil, { { 21.3, 28.0, 19.0, 26.6 } })
room("3F", "302.room", "room", "원룸 (침실 겸 거실)", { { 1.4, 14.2, 1.0, 17.9 } })
room("3F", "302.kitchen", "kitchen", "분리형 주방", { { 1.4, 8.1, 18.4, 30.0 } })
room("3F", "302.bath", "bath", nil, { { 8.6, 14.2, 18.4, 24.5 } })
room("3F", "302.entry", "entry", nil, { { 8.6, 14.2, 25.0, 30.0 } })
room("3F", "303.room", "room", "원룸 (주방 포함)", { { -12.2, 0.6, 1.0, 18.7 } }, { kitchenette = true })
room("3F", "303.hall", "hall", "복도 + 붙박이장", { { -12.2, -6.4, 19.2, 24.8 } })
room("3F", "303.entry", "entry", nil, { { -12.2, -6.4, 24.8, 30.0 } })
room("3F", "303.bath", "bath", "욕실 (욕조형)", { { -5.9, 0.6, 19.2, 30.0 } }, { bathtub = true })
room("3F", "304.room", "room", "코너 원룸 (2면 창)", { { -28.0, -13.0, 1.0, 14.1 } })
room("3F", "304.kitchen", "kitchen", "주방 · 식탁", { { -18.6, -13.0, 14.1, 24.9 } })
room("3F", "304.entry", "entry", nil, { { -18.6, -13.0, 25.4, 30.0 } })
room("3F", "304.alpha", "alpha", "작은방 (0.5룸)", { { -28.0, -19.1, 14.6, 22.9 } })
room("3F", "304.bath", "bath", "욕실 (창 있음)", { { -28.0, -19.1, 23.4, 30.0 } })
room("3F", "3F.laundry", "laundry", nil, { { -28.0, -16.4, 37.6, 50.0 } })
room("3F", "3F.study", "lounge", "스터디룸", { { -28.0, -16.4, 50.5, 63.0 } }, { label2 = "study" })
room("3F", "3F.lounge", "lounge", "입주민 라운지 · 공유 주방", { { -15.6, 8.2, 37.6, 63.0 } })
room("3F", "3F.lockers", "lockers", nil, { { 8.7, 17.6, 46.6, 63.0 } })

-- 4F (FFL v 36.5) -----------------------------------------------------------------------------------
room("4F", "4F.corridor", "corridor", "4층 복도", { { -28.0, 28.0, 30.8, 36.8 } })
room("4F", "401.room", "room", "원룸 (침실 겸 거실)", { { 12.4, 28.0, 1.0, 17.7 } })
room("4F", "401.bath", "bath", nil, { { 12.4, 17.4, 18.2, 24.9 } })
room("4F", "401.entry", "entry", nil, { { 12.4, 17.4, 25.4, 30.0 } })
room("4F", "401.kitchen", "kitchen", "분리형 주방 (L형 + 식탁)", { { 17.9, 28.0, 18.2, 26.6 }, { 17.9, 20.8, 26.6, 30.0 } })
room("4F", "402.living", "living", nil, { { 0.5, 11.6, 1.0, 17.4 } })
room("4F", "402.bed1", "bedroom", nil, { { -8.0, 0.0, 1.0, 17.4 } })
room("4F", "402.dress", "dress", "드레스룸 · 수납", { { -8.0, 0.0, 17.9, 30.0 } })
room("4F", "402.kitchen", "kitchen", "갤리 주방", { { 0.5, 6.1, 17.4, 30.0 } })
room("4F", "402.bath", "bath", nil, { { 6.6, 11.6, 17.9, 24.9 } })
room("4F", "402.entry", "entry", nil, { { 6.6, 11.6, 25.4, 30.0 } })
room("4F", "403.living", "living", "거실 (오션뷰)", { { -19.4, -8.8, 1.0, 17.0 } })
room("4F", "403.bed1", "bedroom", "침실 1 (코너)", { { -28.0, -19.9, 1.0, 14.6 } })
room("4F", "403.bed2", "bedroom", "침실 2 (동측창)", { { -28.0, -19.9, 15.1, 30.0 } })
room("4F", "403.kitchen", "kitchen", "주방 복도형", { { -19.4, -14.9, 17.0, 30.0 } })
room("4F", "403.bath", "bath", nil, { { -14.4, -8.8, 17.5, 24.9 } })
room("4F", "403.entry", "entry", nil, { { -14.4, -8.8, 25.4, 30.0 } })
room("4F", "404.entry", "entry", nil, { { -6.0, 0.0, 37.6, 42.0 } })
room("4F", "404.hall", "hall", nil, { { -6.0, 0.0, 42.0, 50.4 }, { -16.1, -6.0, 46.0, 50.4 } })
room("4F", "404.bath", "bath", "욕실 (욕조형)", { { -16.1, -6.5, 37.6, 45.5 } }, { bathtub = true })
room("4F", "404.bed1", "bedroom", "침실 1 (동측창)", { { -28.0, -16.6, 37.6, 50.4 } })
room("4F", "404.living", "ldk", "거실 · 주방 (후면 시티뷰)", { { -28.0, 0.0, 50.9, 63.0 } })
room("4F", "404.dress", "dress", "드레스룸", { { 0.5, 8.2, 37.6, 45.0 } })
room("4F", "404.storage", "storage", "대형 창고", { { 0.5, 8.2, 45.5, 50.4 }, { 8.2, 17.6, 46.6, 50.4 } })
room("4F", "404.bed2", "bedroom", "침실 2 (후면)", { { 0.5, 17.6, 50.9, 63.0 } })

-- 5F (FFL v 47) -------------------------------------------------------------------------------------
room("5F", "5F.corridor", "corridor", "5층 복도", { { -28.0, 28.0, 30.8, 36.8 } })
room("5F", "501.living", "living", "거실 (오션뷰 · 발코니)", { { 14.9, 28.0, 1.0, 18.4 } })
room("5F", "501.bed1", "bedroom", nil, { { 6.6, 14.4, 1.0, 17.9 } })
room("5F", "501.bath", "bath", nil, { { 6.6, 12.0, 18.4, 24.9 } })
room("5F", "501.entry", "entry", nil, { { 6.6, 12.0, 25.4, 30.0 } })
room("5F", "501.kitchen", "kitchen", "주방 · 다이닝", { { 12.5, 20.8, 18.4, 30.0 }, { 20.8, 28.0, 18.4, 26.6 } })
room("5F", "502.bed1", "master", "안방", { { -4.4, 5.8, 1.0, 15.6 } })
room("5F", "502.mbath", "master_bath", nil, { { 0.9, 5.8, 16.1, 24.9 } }, { bathtub = false })
room("5F", "502.dress", "dress", "안방 드레스룸", { { -4.4, 0.4, 16.1, 21.8 } })
room("5F", "502.hall", "hall", nil, { { -4.4, 0.4, 22.3, 30.0 } })
room("5F", "502.entry", "entry", nil, { { 0.9, 5.8, 25.4, 30.0 } })
room("5F", "502.living", "living", "거실 (오션뷰 · 발코니)", { { -18.5, -4.9, 1.0, 18.4 } })
room("5F", "502.kitchen", "kitchen", "주방 · 식탁", { { -18.5, -4.9, 18.4, 30.0 } })
room("5F", "502.bed2", "bedroom", "침실 2 (코너)", { { -28.0, -19.0, 1.0, 14.0 } })
room("5F", "502.bed3", "bedroom", "침실 3 (동측창)", { { -28.0, -19.0, 14.5, 24.0 } })
room("5F", "502.bath", "bath", "공용 욕실 (창 있음)", { { -28.0, -19.0, 24.5, 30.0 } })
room("5F", "503.bed2", "master", "안방 (동측창)", { { -28.0, -17.0, 37.6, 49.0 } })
room("5F", "503.bath2", "master_bath", "안방 욕실", { { -16.5, -10.5, 37.6, 44.0 } })
room("5F", "503.entry", "entry", nil, { { -10.0, -4.0, 37.6, 42.0 } })
room("5F", "503.hall", "hall", nil, { { -10.0, -4.0, 42.0, 44.5 }, { -16.5, 8.2, 44.5, 49.0 } })
room("5F", "503.bath1", "bath", nil, { { -3.5, 3.0, 37.6, 44.0 } })
room("5F", "503.utility", "utility", nil, { { 3.5, 8.2, 37.6, 44.0 } })
room("5F", "503.ldk", "ldk", "거실 · 주방 (후면 시티뷰)", { { -16.5, 8.2, 49.5, 63.0 } })
room("5F", "503.bed1", "bedroom", "침실 (후면)", { { 8.7, 17.6, 46.6, 63.0 } })
room("5F", "503.bed3", "bedroom", "침실 (코너 후면)", { { -28.0, -17.0, 49.5, 63.0 } })

-- 6F (FFL v 57.5) -----------------------------------------------------------------------------------
room("6F", "6F.corridor", "corridor", "6층 복도", { { -28.0, 28.0, 30.8, 36.8 } })
room("6F", "601.bed3", "bedroom", "침실 3 (코너)", { { -28.0, -19.0, 1.0, 16.0 } })
room("6F", "601.bed2", "bedroom", "침실 2", { { -18.5, -9.6, 1.0, 16.0 } })
room("6F", "601.living", "living", "거실 (4-bay 전면 오션뷰)", { { -9.1, 9.5, 1.0, 18.4 } })
room("6F", "601.bed1", "master", "안방 (오션뷰)", { { 10.0, 28.0, 1.0, 15.6 } })
room("6F", "601.hall", "hall", "침실 복도", { { -28.0, -9.6, 16.5, 22.5 } })
room("6F", "601.bath", "bath", "공용 욕실", { { -18.5, -9.6, 23.0, 30.0 } })
room("6F", "601.utility", "utility", "다용도실 (세탁)", { { -28.0, -19.0, 23.0, 30.0 } })
room("6F", "601.kitchen", "kitchen", "주방 · 다이닝 (아일랜드)", { { -9.1, 9.5, 18.4, 23.9 }, { -9.1, 3.0, 23.9, 30.0 } })
room("6F", "601.entry", "entry", "현관 (중문)", { { 3.5, 9.5, 24.4, 30.0 } })
room("6F", "601.dress", "dress", "안방 드레스룸", { { 10.0, 15.6, 16.1, 24.0 } })
room("6F", "601.mbath", "master_bath", "안방 욕실 (욕조)", { { 16.1, 28.0, 16.1, 24.0 } }, { bathtub = true })
room("6F", "601.storage", "storage", "팬트리 · 현관 창고", { { 10.0, 20.8, 24.5, 30.0 }, { 20.8, 28.0, 24.5, 26.6 } })
room("6F", "602.bed2", "bedroom", "작은방 (동측창)", { { -28.0, -16.0, 37.6, 45.5 } })
room("6F", "602.bath", "bath", nil, { { -15.5, -9.0, 37.6, 45.5 } })
room("6F", "602.entry", "entry", nil, { { -8.5, -2.5, 37.6, 42.0 } })
room("6F", "602.util", "utility", "다용도실", { { -2.0, 8.2, 37.6, 45.5 } })
room("6F", "602.hall", "hall", nil, { { -8.5, -2.5, 42.0, 46.0 }, { -28.0, 8.2, 46.0, 50.5 }, { 8.2, 17.6, 46.6, 50.5 } })
room("6F", "602.living", "ldk", "거실 · 주방 (코너 후면)", { { -28.0, -9.0, 51.0, 63.0 } })
room("6F", "602.bed1", "bedroom", "침실 (후면)", { { -8.5, 3.0, 51.0, 63.0 } })
room("6F", "602.study", "study", "서재 (후면)", { { 3.5, 17.6, 51.0, 63.0 } })

-- 7F (FFL v 68): the corridor stops at u = -6 (701 takes the east end) -----------------------------
room("7F", "7F.corridor", "corridor", "7층 복도", { { -6.0, 28.0, 30.8, 36.8 } })
room("7F", "701.living", "living", "거실 (오션뷰 · 발코니)", { { -18.5, -2.0, 1.0, 18.4 } })
room("7F", "701.bed3", "bedroom", "침실 3 (코너)", { { -28.0, -19.0, 1.0, 15.0 } })
room("7F", "701.bed4", "study", "서재 (동측창)", { { -28.0, -19.0, 15.5, 27.0 } })
room("7F", "701.kitchen", "kitchen", "주방 · 다이닝 (아일랜드)", { { -18.5, -2.0, 18.4, 30.0 } })
room("7F", "701.bath", "bath", "공용 욕실 (창 있음)", { { -28.0, -19.0, 27.5, 34.0 } })
room("7F", "701.gallery", "hall", "갤러리 복도", { { -18.5, -13.3, 30.0, 51.0 } })
room("7F", "701.entry", "entry", "현관 (복도 끝)", { { -12.8, -6.8, 30.5, 36.5 } })
room("7F", "701.bed2", "bedroom", "침실 2 (동측창)", { { -28.0, -19.0, 34.5, 46.0 } })
room("7F", "701.bed1", "master", "안방 (코너 후면)", { { -28.0, -19.0, 46.5, 63.0 } })
room("7F", "701.dress", "dress", "워크인 드레스룸", { { -12.8, -6.8, 37.0, 51.0 } })
room("7F", "701.mbath", "master_bath", "안방 욕실 (욕조 · 창)", { { -18.5, -6.8, 51.5, 63.0 } }, { bathtub = true })
room("7F", "702.living", "living", "거실 (와이드 오션뷰)", { { -1.2, 15.0, 1.0, 18.4 } })
room("7F", "702.bed1", "master", "침실 (오션뷰)", { { 15.5, 28.0, 1.0, 16.0 } })
room("7F", "702.kitchen", "kitchen", nil, { { -1.2, 9.0, 18.4, 30.0 } })
room("7F", "702.entry", "entry", nil, { { 9.5, 15.0, 25.4, 30.0 } })
room("7F", "702.bath", "bath", nil, { { 9.5, 15.0, 18.9, 24.9 } })
room("7F", "702.dress", "dress", "드레스 · 파우더룸 (세면대)", { { 15.5, 28.0, 16.5, 26.6 }, { 15.5, 20.8, 26.6, 30.0 } }, { vanity = true })
room("7F", "703.entry", "entry", nil, { { -6.0, -0.5, 37.6, 42.0 } })
room("7F", "703.kitchen", "kitchen", nil, { { -6.0, -0.5, 42.0, 50.5 }, { -0.5, 8.2, 44.5, 50.5 } })
room("7F", "703.bath", "bath", nil, { { 0.0, 8.2, 37.6, 44.0 } })
room("7F", "703.room", "room", "방 (후면)", { { -6.0, 8.2, 51.0, 63.0 } })
room("7F", "703.alpha", "alpha", "알파룸 (후면)", { { 8.7, 17.6, 46.6, 63.0 } })

-- 8F penthouse lower level (FFL v 78.5) ------------------------------------------------------------
room("8F", "8F.hall", "hall_common", "8층 승강장 홀", { { 8.2, 28.0, 30.8, 36.8 } })
room("8F", "801.foyer", "entry", "포이어 (현관 · 갤러리)", { { 1.4, 7.4, 30.5, 37.1 }, { 1.4, 6.0, 22.0, 30.5 } }, { floorFinish = "marble_white" })
room("8F", "801.stair", "stair_private", "내부 계단 (8F→9F)", { { -14.5, 0.9, 32.6, 36.6 } })
room("8F", "801.living", "living", "거실 (파노라마 오션뷰)", { { -14.5, 10.0, 1.0, 21.5 } }, { floorFinish = "wood_walnut" })
room("8F", "801.family", "living", "가족실", { { -14.5, 0.9, 21.5, 32.1 } }, { floorFinish = "wood_walnut" })
room("8F", "801.dining", "living", "다이닝 (오션뷰)", { { 10.0, 28.0, 1.0, 15.0 } }, { floorFinish = "wood_walnut" })
room("8F", "801.kitchen", "kitchen", "주방 (아일랜드 · 와인셀러)", { { 10.0, 20.8, 15.0, 30.0 }, { 20.8, 28.0, 15.0, 26.6 }, { 6.5, 10.0, 21.5, 30.0 } }, { floorFinish = "marble_white" })
room("8F", "801.guest", "bedroom", "게스트룸 (코너)", { { -28.0, -15.0, 1.0, 16.0 } })
room("8F", "801.gbath", "bath", "게스트 욕실 (창)", { { -28.0, -19.0, 16.5, 25.5 } })
room("8F", "801.closet", "dress", "게스트 워크인", { { -18.5, -15.0, 16.5, 25.5 } })
room("8F", "801.media", "study", "미디어룸 (동측창)", { { -28.0, -15.0, 26.0, 41.5 } })
room("8F", "801.hallR", "hall", "후면 복도", { { -14.5, 8.2, 37.1, 41.5 } })
room("8F", "801.master", "master", "마스터 침실 (코너)", { { -28.0, -10.0, 42.0, 63.0 } })
room("8F", "801.mdress", "dress", "마스터 드레스룸", { { -9.5, -1.0, 42.0, 51.5 } })
room("8F", "801.mbath", "master_bath", "마스터 욕실 (욕조 · 창)", { { -9.5, -1.0, 52.0, 63.0 } }, { bathtub = true })
room("8F", "801.study", "study", "라이브러리 서재", { { -0.5, 8.2, 42.0, 63.0 }, { 8.2, 17.6, 46.6, 63.0 } })

-- 9F penthouse upper level (FFL v 89) --------------------------------------------------------------
room("9F", "9F.hall", "hall_common", "9층 승강장 홀", { { 8.2, 28.0, 30.8, 36.8 } })
room("9F", "801.terrace", "terrace", "루프 테라스 (자쿠지 · 오션뷰)", { { -28.0, 28.0, 1.0, 17.0 } })
room("9F", "801.lounge9", "living", "스카이 라운지 (테라스 연결)", { { -19.0, 7.4, 18.0, 32.1 }, { 7.4, 20.8, 18.0, 30.0 }, { 20.8, 28.0, 18.0, 26.6 } }, { floorFinish = "wood_walnut" })
room("9F", "801.bed2", "bedroom", "침실 2 (테라스 · 동측)", { { -28.0, -19.5, 18.0, 31.0 } })
room("9F", "801.bed3", "bedroom", "침실 3 (동측)", { { -28.0, -19.5, 31.5, 50.0 } })
room("9F", "801.hall9", "hall", "계단 홀", { { -19.0, -14.5, 32.6, 41.5 }, { -14.5, -10.0, 37.1, 41.5 } })
room("9F", "801.void9", "void", "계단 오픈 (보이드)", { { -14.5, 0.9, 32.6, 36.6 } })
room("9F", "801.foyer9", "entry", "9층 보조 현관", { { 1.4, 7.4, 32.6, 36.6 } })
room("9F", "801.bath9", "bath", "9층 욕실", { { -19.0, -10.0, 42.0, 50.0 } })
room("9F", "801.rear9", "study", "패밀리 서재 · 홈오피스", { { -9.5, 8.2, 37.1, 63.0 }, { 8.2, 17.6, 46.6, 63.0 } })
room("9F", "801.gym9", "alpha", "홈짐 (코너 후면)", { { -28.0, -10.0, 50.5, 63.0 } })

-------------------------------------------------------------------------------------------------
-- Envelope per floor (inner faces); outdoor rooms (terrace) are not bounded by exterior walls
-------------------------------------------------------------------------------------------------
LP.ENVELOPE = {
	default = { u0 = -28.0, u1 = 28.0, w0 = 1.0, w1 = 63.0 },
	["9F"] = { u0 = -28.0, u1 = 28.0, w0 = 18.0, w1 = 63.0, terrace = { u0 = -28.0, u1 = 28.0, w0 = 1.0, w1 = 17.0 } },
}
function LP.envelope(floorId: string): any
	return LP.ENVELOPE[floorId] or LP.ENVELOPE.default
end

-------------------------------------------------------------------------------------------------
-- Doors
-------------------------------------------------------------------------------------------------
LP.DOOR_KINDS = {
	unit_entry = { width = 3.6, height = 7.4, leaf = "steel", label = "세대 현관문 (도어락)", lockDefault = "unit" },
	room = { width = 3.2, height = 7.2, leaf = "wood", label = "방문" },
	bath = { width = 3.0, height = 7.0, leaf = "wood", label = "욕실문" },
	slide = { width = 3.6, height = 7.2, leaf = "glass_wood", label = "중문 · 미닫이 (슬라이딩)" },
	opening = { width = 3.6, height = 7.4, leaf = "none", label = "개구부 (문 없음, 문틀만)" },
	glass = { width = 3.6, height = 7.6, leaf = "glass", label = "유리 여닫이" },
	double = { width = 6.0, height = 7.6, leaf = "glass", label = "유리 양여닫이" },
	glass_auto = { width = 5.2, height = 8.0, leaf = "glass", label = "자동문 (양개 슬라이딩)" },
	fire = { width = 3.4, height = 7.4, leaf = "steel", label = "방화문 (계단실, 자동 닫힘)" },
	staff = { width = 3.2, height = 7.4, leaf = "steel", label = "직원 전용문", lockDefault = "staff" },
	service = { width = 2.2, height = 7.0, leaf = "steel", label = "점검구 (PS/EPS)", lockDefault = "staff" },
	external = { width = 3.6, height = 7.6, leaf = "steel", label = "외부 출입문" },
	elevator = { width = 4.4, height = 7.6, leaf = "steel", label = "승강장 문 (승강기 시스템 소유)" },
}

LP.DOORS = {} :: { any }
LP.DOOR_BY_ID = {} :: { [string]: any }
local function door(floor: string, id: string, a: string, b: string, at: number, kind: string, opt: { [string]: any }?)
	assert(LP.DOOR_BY_ID[id] == nil, "duplicate door id " .. id)
	local k = LP.DOOR_KINDS[kind]
	assert(k, "unknown door kind " .. kind)
	local d: any = { id = id, floor = floor, a = a, b = b, at = at, kind = kind, width = k.width, height = k.height }
	if opt then
		for key, v in opt do
			d[key] = v
		end
	end
	d.lock = d.lock or k.lockDefault or "none"
	table.insert(LP.DOORS, d)
	LP.DOOR_BY_ID[id] = d
	return d
end
LP.door = door

-- core doors on every floor (the corridor / lobby / hall room of that floor)
for level = 1, 9 do
	local f = LP.FLOOR_BY_LEVEL[level].id
	local hall = if level == 1 then "1F.lobby" elseif level >= 8 then f .. ".hall" else f .. ".corridor"
	-- stair fire door: swings toward the escape direction (into the stair on upper floors, out to the lobby on 1F)
	door(f, f .. ".D_stair", hall, f .. ".stair", 20.9, "fire", {
		hinge = "low",
		swing = if level == 1 then hall else f .. ".stair",
		lock = if level >= 3 then "resident_stair" else "none", -- residents-only from the stair side; free egress from the corridor
	})
	door(f, f .. ".D_elev", hall, f .. ".elevator", 13.3, "elevator", { lock = "none" })
	door(f, f .. ".D_eps", hall, f .. ".eps", 23.0, "service", { width = 2.2, hinge = "low", swing = hall })
	door(f, f .. ".D_ps", hall, f .. ".ps", 26.45, "service", { width = 2.4, hinge = "high", swing = hall })
end

-- 1F
door("1F", "1F.D_east", "outside", "1F.vestibule", 33.8, "glass_auto", { side = "east", label = "주출입구 (209번길)" })
door("1F", "1F.D_inner", "1F.vestibule", "1F.lobby", 33.8, "glass_auto", { lock = "building", label = "공동현관 (비밀번호 · 인터폰)" })
door("1F", "1F.D_mgmt", "1F.lobby", "1F.mgmt", -17.8, "room", { hinge = "low", swing = "1F.mgmt", lock = "staff", label = "관리사무소" })
door("1F", "1F.D_rear", "1F.lobby", "1F.rear", -10.9, "glass", { width = 4.0, hinge = "low", swing = "1F.rear" })
door("1F", "1F.D_store", "1F.rear", "1F.cvs_store", 47.6, "staff", { hinge = "low", swing = "1F.cvs_store", lock = "shop", shop = "1F-B" })
door("1F", "1F.D_wcm", "1F.rear", "1F.wc_m", 55.2, "bath", { hinge = "low", swing = "1F.wc_m" })
door("1F", "1F.D_wcf", "1F.rear", "1F.wc_f", 60.55, "bath", { hinge = "low", swing = "1F.wc_f" })
door("1F", "1F.D_back", "1F.rear", "outside", -10.9, "external", { side = "rear", hinge = "low", swing = "outside", lock = "building", label = "후문 (주차장)" })
door("1F", "1F.D_elec", "1F.electric", "outside", 4.5, "external", { side = "rear", width = 3.2, hinge = "low", swing = "outside", lock = "staff" })
door("1F", "1F.D_recy", "1F.recycle", "outside", 13.1, "external", { side = "rear", width = 5.0, hinge = "high", swing = "outside", lock = "none", label = "분리수거장" })
door("1F", "1F-A.D_front", "outside", "1F-A", -9.0, "double", { side = "front", swing = "1F-A", lock = "shop", shop = "1F-A", label = "카페 정문" })
door("1F", "1F-A.D_side", "outside", "1F-A", 13.8, "glass", { side = "east", hinge = "high", swing = "1F-A", lock = "shop", shop = "1F-A", label = "카페 측문 (209번길)" })
door("1F", "1F-A.D_staff", "1F-A", "1F.lobby", -1.6, "staff", { hinge = "low", swing = "1F-A", lock = "shop", shop = "1F-A" })
door("1F", "1F-B.D_front", "outside", "1F-B", 8.0, "glass_auto", { side = "front", width = 5.0, lock = "shop", shop = "1F-B", label = "편의점 자동문" })
door("1F", "1F-B.D_staff", "1F-B", "1F.lobby", 6.3, "staff", { hinge = "low", swing = "1F-B", lock = "shop", shop = "1F-B" })
door("1F", "1F-C.D_front", "outside", "1F-C", 56.4, "glass", { side = "east", hinge = "high", swing = "1F-C", lock = "shop", shop = "1F-C", label = "부동산 출입문" })

-- 2F
door("2F", "2F-A.D_main", "2F.corridor", "2F-A", -8.5, "double", { width = 5.0, swing = "2F-A", lock = "shop", shop = "2F-A", label = "식당 입구" })
door("2F", "2F-A.D_staff", "2F.corridor", "2F-A", -21.0, "staff", { hinge = "low", swing = "2F-A", lock = "shop", shop = "2F-A" })
door("2F", "2F-A.D_kitchen", "2F.corridor", "2F-A", 14.0, "staff", { hinge = "high", swing = "2F-A", lock = "shop", shop = "2F-A", label = "주방 반입문" })
door("2F", "2F.D_wcm", "2F.corridor", "2F.wc_m", -26.0, "bath", { hinge = "low", swing = "2F.wc_m" })
door("2F", "2F.D_wcf", "2F.corridor", "2F.wc_f", -21.5, "bath", { hinge = "high", swing = "2F.wc_f" })
door("2F", "2F-B.D_main", "2F.corridor", "2F-B", -10.0, "glass", { hinge = "low", swing = "2F-B", lock = "shop", shop = "2F-B", label = "사무실 입구" })

-- 3F
door("3F", "301.D1", "3F.corridor", "301.entry", 17.9, "unit_entry", { hinge = "high", swing = "3F.corridor", unit = "301" })
door("3F", "301.D2", "301.kitchen", "301.bath", 21.3, "bath", { hinge = "low", swing = "301.bath" })
door("3F", "301.O1", "301.kitchen", "301.entry", 17.9, "opening", { width = 4.0 })
door("3F", "302.D1", "3F.corridor", "302.entry", 11.4, "unit_entry", { hinge = "high", swing = "3F.corridor", unit = "302" })
door("3F", "302.D2", "302.entry", "302.bath", 11.4, "bath", { hinge = "low", swing = "302.bath" })
door("3F", "302.O1", "302.entry", "302.kitchen", 27.5, "opening", { width = 3.6 })
door("3F", "302.D3", "302.kitchen", "302.room", 4.75, "slide", { width = 3.2, label = "분리형 중문 (미닫이)" })
door("3F", "303.D1", "3F.corridor", "303.entry", -9.3, "unit_entry", { hinge = "low", swing = "3F.corridor", unit = "303" })
door("3F", "303.D2", "303.hall", "303.bath", 22.0, "bath", { hinge = "low", swing = "303.bath" })
door("3F", "303.D3", "303.hall", "303.room", -9.3, "room", { hinge = "low", swing = "303.room" })
door("3F", "304.D1", "3F.corridor", "304.entry", -15.8, "unit_entry", { hinge = "low", swing = "3F.corridor", unit = "304" })
door("3F", "304.O1", "304.entry", "304.kitchen", -15.8, "opening", { width = 4.0 })
door("3F", "304.D2", "304.entry", "304.bath", 27.7, "bath", { hinge = "high", swing = "304.bath" })
door("3F", "304.D3", "304.kitchen", "304.alpha", 18.75, "room", { hinge = "low", swing = "304.alpha" })
door("3F", "3F.D_laundry", "3F.corridor", "3F.laundry", -22.2, "glass", { hinge = "low", swing = "3F.laundry", lock = "resident" })
door("3F", "3F.D_lounge", "3F.corridor", "3F.lounge", -3.7, "double", { swing = "3F.lounge", lock = "resident" })
door("3F", "3F.D_study", "3F.lounge", "3F.study", 56.0, "glass", { width = 3.4, hinge = "low", swing = "3F.study" })
door("3F", "3F.D_lockers", "3F.lounge", "3F.lockers", 54.0, "room", { hinge = "low", swing = "3F.lockers", lock = "resident" })

-- 4F
door("4F", "401.D1", "4F.corridor", "401.entry", 14.9, "unit_entry", { hinge = "high", swing = "4F.corridor", unit = "401" })
door("4F", "401.D2", "401.entry", "401.bath", 14.9, "bath", { hinge = "low", swing = "401.bath" })
door("4F", "401.D3", "401.entry", "401.kitchen", 27.8, "room", { hinge = "high", swing = "401.entry" })
door("4F", "401.D4", "401.kitchen", "401.room", 22.0, "slide", { width = 3.2, label = "분리형 중문 (미닫이)" })
door("4F", "402.D1", "4F.corridor", "402.entry", 9.1, "unit_entry", { hinge = "high", swing = "4F.corridor", unit = "402" })
door("4F", "402.D2", "402.entry", "402.bath", 9.1, "bath", { hinge = "low", swing = "402.bath" })
door("4F", "402.O1", "402.entry", "402.kitchen", 27.7, "opening", { width = 3.6 })
door("4F", "402.D3", "402.living", "402.bed1", 13.4, "room", { hinge = "high", swing = "402.bed1" })
door("4F", "402.D4", "402.bed1", "402.dress", -4.0, "room", { hinge = "low", swing = "402.dress" })
door("4F", "403.D1", "4F.corridor", "403.entry", -11.6, "unit_entry", { hinge = "low", swing = "4F.corridor", unit = "403" })
door("4F", "403.O1", "403.entry", "403.kitchen", 27.7, "opening", { width = 3.6 })
door("4F", "403.D2", "403.kitchen", "403.bath", 21.2, "bath", { hinge = "low", swing = "403.bath" })
door("4F", "403.D3", "403.living", "403.bed1", 11.0, "room", { hinge = "high", swing = "403.bed1" })
door("4F", "403.D4", "403.kitchen", "403.bed2", 20.0, "room", { hinge = "low", swing = "403.bed2" })
door("4F", "404.D1", "4F.corridor", "404.entry", -3.0, "unit_entry", { hinge = "low", swing = "4F.corridor", unit = "404" })
door("4F", "404.D2", "404.entry", "404.dress", 39.8, "room", { hinge = "low", swing = "404.dress" })
door("4F", "404.D3", "404.hall", "404.bath", 43.75, "bath", { width = 2.8, hinge = "high", swing = "404.bath" })
door("4F", "404.D4", "404.hall", "404.storage", 48.0, "room", { width = 3.0, hinge = "low", swing = "404.storage" })
door("4F", "404.D5", "404.hall", "404.bed1", 48.2, "room", { hinge = "low", swing = "404.bed1" })
door("4F", "404.D6", "404.hall", "404.living", -10.0, "slide", { width = 4.0, label = "거실 유리 중문" })
door("4F", "404.D7", "404.living", "404.bed2", 55.0, "room", { hinge = "low", swing = "404.bed2" })

-- 5F
door("5F", "501.D1", "5F.corridor", "501.entry", 9.3, "unit_entry", { hinge = "high", swing = "5F.corridor", unit = "501" })
door("5F", "501.D2", "501.entry", "501.bath", 9.3, "bath", { hinge = "low", swing = "501.bath" })
door("5F", "501.O1", "501.entry", "501.kitchen", 27.7, "opening", { width = 3.6 })
door("5F", "501.D3", "501.living", "501.bed1", 14.0, "room", { hinge = "high", swing = "501.bed1" })
door("5F", "502.D1", "5F.corridor", "502.entry", 3.35, "unit_entry", { hinge = "high", swing = "5F.corridor", unit = "502" })
door("5F", "502.O1", "502.entry", "502.hall", 27.7, "opening", { width = 3.6 })
door("5F", "502.O2", "502.hall", "502.kitchen", 26.0, "opening", { width = 4.0 })
door("5F", "502.D2", "502.living", "502.bed1", 12.0, "room", { hinge = "high", swing = "502.bed1" })
door("5F", "502.D3", "502.bed1", "502.mbath", 3.35, "bath", { hinge = "high", swing = "502.mbath" })
door("5F", "502.D4", "502.bed1", "502.dress", -2.0, "room", { width = 3.0, hinge = "low", swing = "502.dress" })
door("5F", "502.D5", "502.living", "502.bed2", 10.0, "room", { hinge = "high", swing = "502.bed2" })
door("5F", "502.D6", "502.living", "502.bed3", 16.4, "room", { hinge = "low", swing = "502.bed3" })
door("5F", "502.D7", "502.kitchen", "502.bath", 27.2, "bath", { hinge = "low", swing = "502.bath" })
door("5F", "503.D1", "5F.corridor", "503.entry", -7.0, "unit_entry", { hinge = "low", swing = "5F.corridor", unit = "503" })
door("5F", "503.D2", "503.hall", "503.bed2", 46.75, "room", { hinge = "low", swing = "503.bed2" })
door("5F", "503.D3", "503.bed2", "503.bath2", 41.0, "bath", { hinge = "low", swing = "503.bath2" })
door("5F", "503.D4", "503.hall", "503.bath1", -0.25, "bath", { hinge = "low", swing = "503.bath1" })
door("5F", "503.D5", "503.hall", "503.utility", 5.85, "room", { width = 3.0, hinge = "high", swing = "503.utility" })
door("5F", "503.O1", "503.hall", "503.ldk", -6.0, "opening", { width = 6.0 })
door("5F", "503.D6", "503.ldk", "503.bed1", 52.0, "room", { hinge = "low", swing = "503.bed1" })
door("5F", "503.D7", "503.ldk", "503.bed3", 53.0, "room", { hinge = "low", swing = "503.bed3" })

-- 6F
door("6F", "601.D1", "6F.corridor", "601.entry", 6.5, "unit_entry", { hinge = "high", swing = "6F.corridor", unit = "601" })
door("6F", "601.O1", "601.entry", "601.kitchen", 6.5, "slide", { width = 4.0, label = "현관 중문 (유리 슬라이딩)" })
door("6F", "601.D2", "601.entry", "601.storage", 27.2, "room", { width = 3.0, hinge = "low", swing = "601.storage" })
door("6F", "601.O2", "601.hall", "601.kitchen", 20.45, "opening", { width = 3.4 })
door("6F", "601.D3", "601.hall", "601.bed3", -23.5, "room", { hinge = "low", swing = "601.bed3" })
door("6F", "601.D4", "601.hall", "601.bed2", -14.0, "room", { hinge = "high", swing = "601.bed2" })
door("6F", "601.D5", "601.hall", "601.bath", -14.0, "bath", { hinge = "low", swing = "601.bath" })
door("6F", "601.D6", "601.hall", "601.utility", -23.5, "room", { width = 3.0, hinge = "low", swing = "601.utility" })
door("6F", "601.D7", "601.living", "601.bed1", 12.5, "room", { hinge = "high", swing = "601.bed1" })
door("6F", "601.D8", "601.bed1", "601.dress", 12.8, "room", { width = 3.0, hinge = "low", swing = "601.dress" })
door("6F", "601.D9", "601.bed1", "601.mbath", 22.0, "bath", { hinge = "low", swing = "601.mbath" })
door("6F", "602.D1", "6F.corridor", "602.entry", -5.5, "unit_entry", { hinge = "low", swing = "6F.corridor", unit = "602" })
door("6F", "602.D2", "602.entry", "602.util", 39.8, "room", { width = 3.0, hinge = "low", swing = "602.util" })
door("6F", "602.D3", "602.hall", "602.bath", -12.25, "bath", { hinge = "low", swing = "602.bath" })
door("6F", "602.D4", "602.hall", "602.bed2", -22.0, "room", { hinge = "low", swing = "602.bed2" })
door("6F", "602.D5", "602.hall", "602.living", -16.0, "slide", { width = 4.0, label = "거실 유리 중문" })
door("6F", "602.D6", "602.hall", "602.bed1", -3.0, "room", { hinge = "low", swing = "602.bed1" })
door("6F", "602.D7", "602.hall", "602.study", 10.5, "room", { hinge = "low", swing = "602.study" })

-- 7F
door("7F", "701.D1", "7F.corridor", "701.entry", 33.5, "unit_entry", { hinge = "low", swing = "7F.corridor", unit = "701" })
door("7F", "701.O1", "701.entry", "701.gallery", 33.5, "opening", { width = 4.0 })
door("7F", "701.D2", "701.gallery", "701.bath", 32.0, "bath", { hinge = "high", swing = "701.bath" })
door("7F", "701.D3", "701.gallery", "701.bed2", 40.0, "room", { hinge = "low", swing = "701.bed2" })
door("7F", "701.D4", "701.gallery", "701.bed1", 48.7, "room", { hinge = "low", swing = "701.bed1" })
door("7F", "701.D5", "701.gallery", "701.dress", 44.0, "room", { width = 3.0, hinge = "low", swing = "701.dress" })
door("7F", "701.D6", "701.bed1", "701.mbath", 55.0, "bath", { hinge = "low", swing = "701.mbath" })
door("7F", "701.D7", "701.living", "701.bed3", 10.0, "room", { hinge = "high", swing = "701.bed3" })
door("7F", "701.D8", "701.kitchen", "701.bed4", 22.0, "room", { hinge = "low", swing = "701.bed4" })
door("7F", "702.D1", "7F.corridor", "702.entry", 12.25, "unit_entry", { hinge = "high", swing = "7F.corridor", unit = "702" })
door("7F", "702.O1", "702.entry", "702.kitchen", 27.7, "opening", { width = 3.6 })
door("7F", "702.D2", "702.entry", "702.bath", 12.25, "bath", { hinge = "low", swing = "702.bath" })
door("7F", "702.D3", "702.living", "702.bed1", 12.0, "room", { hinge = "high", swing = "702.bed1" })
door("7F", "702.D4", "702.bed1", "702.dress", 24.0, "slide", { width = 3.2, label = "드레스룸 미닫이" })
door("7F", "703.D1", "7F.corridor", "703.entry", -3.25, "unit_entry", { hinge = "low", swing = "7F.corridor", unit = "703" })
door("7F", "703.D2", "703.kitchen", "703.bath", 4.1, "bath", { hinge = "low", swing = "703.bath" })
door("7F", "703.O1", "703.kitchen", "703.room", 1.1, "opening", { width = 4.0 })
door("7F", "703.D3", "703.room", "703.alpha", 55.0, "room", { hinge = "low", swing = "703.alpha" })

-- 8F
door("8F", "801.D1", "8F.hall", "801.foyer", 33.8, "unit_entry", { width = 3.8, hinge = "low", swing = "8F.hall", unit = "801", label = "펜트하우스 현관 (8F)" })
door("8F", "801.O1", "801.foyer", "801.stair", 34.6, "opening", { width = 3.4, label = "내부 계단 입구" })
door("8F", "801.D2", "801.foyer", "801.living", 3.7, "slide", { width = 3.6, label = "거실 유리 중문" })
door("8F", "801.O2", "801.foyer", "801.family", 27.0, "opening", { width = 4.0 })
door("8F", "801.D3", "801.living", "801.guest", 12.0, "room", { width = 3.4, hinge = "high", swing = "801.guest" })
door("8F", "801.D4", "801.guest", "801.gbath", -23.5, "bath", { hinge = "low", swing = "801.gbath" })
door("8F", "801.D5", "801.guest", "801.closet", -16.75, "slide", { width = 2.6 })
door("8F", "801.D6", "801.family", "801.media", 29.0, "room", { width = 3.4, hinge = "low", swing = "801.media" })
door("8F", "801.D7", "801.hallR", "801.media", 39.3, "room", { hinge = "low", swing = "801.media" })
door("8F", "801.D8", "801.hallR", "801.master", -12.25, "room", { width = 3.4, hinge = "low", swing = "801.master" })
door("8F", "801.D9", "801.master", "801.mdress", 46.0, "room", { hinge = "low", swing = "801.mdress" })
door("8F", "801.D10", "801.master", "801.mbath", 57.0, "bath", { width = 3.2, hinge = "low", swing = "801.mbath" })
door("8F", "801.D11", "801.hallR", "801.study", 3.5, "room", { width = 3.4, hinge = "low", swing = "801.study" })

-- 9F
door("9F", "801.D12", "9F.hall", "801.foyer9", 34.6, "unit_entry", { width = 3.4, hinge = "low", swing = "9F.hall", unit = "801", label = "펜트하우스 보조 현관 (9F)" })
door("9F", "801.D13", "801.foyer9", "801.rear9", 4.4, "room", { hinge = "low", swing = "801.rear9" })
door("9F", "801.O4", "801.foyer9", "801.lounge9", 4.4, "opening", { width = 4.0 })
door("9F", "801.O5", "801.hall9", "801.lounge9", -16.75, "opening", { width = 3.6 })
door("9F", "801.D14", "801.lounge9", "801.bed2", 24.0, "room", { hinge = "low", swing = "801.bed2" })
door("9F", "801.D15", "801.hall9", "801.bed3", 37.0, "room", { hinge = "low", swing = "801.bed3" })
door("9F", "801.D16", "801.hall9", "801.bath9", -15.0, "bath", { hinge = "low", swing = "801.bath9" })
door("9F", "801.D17", "801.hall9", "801.rear9", 39.3, "room", { hinge = "low", swing = "801.rear9" })
door("9F", "801.D18", "801.rear9", "801.gym9", 56.0, "room", { width = 3.4, hinge = "low", swing = "801.gym9" })

-- RF: roof door at the top of the stair (south wall of the stair box, onto the roof over the 9F hall)
LP.ROOF_DOOR = { id = "RF.D_roof", u = 20.9, width = 3.4, kind = "fire", lock = "resident", label = "옥상 출입문" }

-------------------------------------------------------------------------------------------------
-- Windows
-------------------------------------------------------------------------------------------------
LP.WINDOW_KINDS = {
	window = { sill = 3.0, head = 7.8, label = "창 (PVC 이중창 · 커튼/블라인드)" },
	small = { sill = 5.0, head = 7.4, label = "소형 창 (욕실 · 화장실, 반투명)" },
	door_balcony = { sill = 0.15, head = 7.8, label = "발코니 슬라이딩 도어 (2연동)" },
	corridor = { sill = 3.0, head = 7.8, label = "복도 끝 창" },
	storefront = { sill = 0.6, head = 11.6, label = "1층 상가 쇼윈도 (전면 유리)" },
	restaurant = { sill = 1.2, head = 10.0, label = "2층 식당 통창" },
	office = { sill = 3.0, head = 9.6, label = "사무실 창" },
	full = { sill = 0.4, head = 8.4, label = "펜트하우스 통창" },
	door_terrace = { sill = 0.15, head = 8.4, label = "테라스 폴딩 도어" },
	stair = { sill = 3.0, head = 7.4, label = "계단실 창 (층참)" }, -- relative to the mid landing (FFL + h/2)
}

LP.WINDOWS = {} :: { any }
local function win(floor: string, id: string, roomId: string, side: string, a: number, b: number, kind: string, opt: { [string]: any }?)
	local k = LP.WINDOW_KINDS[kind]
	assert(k, "unknown window kind " .. kind)
	local wd: any = { id = id, floor = floor, room = roomId, side = side, a = a, b = b, kind = kind, sill = k.sill, head = k.head }
	if opt then
		for key, v in opt do
			wd[key] = v
		end
	end
	table.insert(LP.WINDOWS, wd)
	return wd
end
LP.window = win

-- stair windows (rear facade, at every mid landing 1F..9F)
for level = 1, 9 do
	local f = LP.FLOOR_BY_LEVEL[level]
	win(f.id, f.id .. ".Wstair", f.id .. ".stair", "rear", LP.STAIR.window.u0, LP.STAIR.window.u1, "stair", { atMidLanding = true, sill = f.h / 2 + 3.0, head = f.h / 2 + 7.4 })
end

-- 1F
win("1F", "1F-A.W1", "1F-A", "front", -26.6, -12.6, "storefront")
win("1F", "1F-A.W2", "1F-A", "front", -5.4, 2.4, "storefront")
win("1F", "1F-A.W3", "1F-A", "east", 2.4, 11.0, "storefront")
win("1F", "1F-A.W4", "1F-A", "east", 16.6, 28.6, "storefront")
win("1F", "1F-B.W1", "1F-B", "front", 11.0, 26.6, "storefront")
win("1F", "1F.Wvest", "1F.vestibule", "east", 37.0, 41.6, "window", { sill = 0.6, head = 9.0, label = "전실 유리" })
win("1F", "1F.Wmgmt", "1F.mgmt", "east", 44.4, 49.0, "window")
win("1F", "1F-C.W1", "1F-C", "east", 51.8, 54.0, "storefront")
win("1F", "1F-C.W2", "1F-C", "east", 58.8, 62.2, "storefront")
win("1F", "1F.Wwcf", "1F.wc_f", "rear", -6.0, -0.8, "small")
win("1F", "1F.Welec", "1F.electric", "rear", 1.8, 2.8, "small", { note = "louvre vent" })

-- 2F
win("2F", "2F-A.W1", "2F-A", "front", -26.6, -15.6, "restaurant")
win("2F", "2F-A.W2", "2F-A", "front", -14.2, -2.2, "restaurant")
win("2F", "2F-A.W3", "2F-A", "front", -0.8, 11.0, "restaurant")
win("2F", "2F-A.W4", "2F-A", "front", 12.4, 19.6, "restaurant")
win("2F", "2F-A.W5", "2F-A", "front", 21.4, 26.8, "restaurant")
win("2F", "2F-A.W6", "2F-A", "east", 2.4, 14.0, "restaurant")
win("2F", "2F-A.W7", "2F-A", "east", 15.4, 28.6, "restaurant")
win("2F", "2F.Wcor", "2F.corridor", "east", 31.6, 36.0, "corridor")
win("2F", "2F.Wwcm", "2F.wc_m", "east", 39.0, 44.6, "small")
win("2F", "2F-B.W1", "2F-B", "east", 48.0, 61.6, "office")
win("2F", "2F-B.W2", "2F-B", "rear", -26.6, -19.6, "office")
win("2F", "2F-B.W3", "2F-B", "rear", -17.4, -2.4, "office")
win("2F", "2F-B.W4", "2F-B", "rear", -0.6, 6.8, "office")
win("2F", "2F-B.W5", "2F-B", "rear", 9.6, 16.2, "office")

-- 3F
win("3F", "301.W1", "301.room", "front", 16.4, 26.6, "window")
win("3F", "302.W1", "302.room", "front", 2.8, 12.8, "window")
win("3F", "303.W1", "303.room", "front", -10.8, -0.8, "window")
win("3F", "304.W1", "304.room", "front", -26.6, -14.4, "window")
win("3F", "304.W2", "304.room", "east", 2.4, 12.6, "window")
win("3F", "304.W3", "304.alpha", "east", 15.8, 21.8, "window")
win("3F", "304.W4", "304.bath", "east", 25.2, 28.0, "small")
win("3F", "3F.Wcor", "3F.corridor", "east", 31.6, 36.0, "corridor")
win("3F", "3F.Wlaundry", "3F.laundry", "east", 39.6, 48.0, "window")
win("3F", "3F.Wstudy1", "3F.study", "east", 52.0, 61.6, "window")
win("3F", "3F.Wstudy2", "3F.study", "rear", -26.6, -17.8, "window")
win("3F", "3F.Wlounge", "3F.lounge", "rear", -14.2, 6.8, "window")
win("3F", "3F.Wlockers", "3F.lockers", "rear", 10.0, 16.2, "small")

-- 4F
win("4F", "401.W1", "401.room", "front", 13.8, 26.6, "window")
win("4F", "402.W1", "402.living", "front", 2.0, 10.2, "door_balcony")
win("4F", "402.W2", "402.bed1", "front", -6.6, -1.4, "window")
win("4F", "403.W1", "403.living", "front", -18.0, -10.2, "door_balcony")
win("4F", "403.W2", "403.bed1", "front", -26.6, -21.4, "window")
win("4F", "403.W3", "403.bed1", "east", 2.4, 13.2, "window")
win("4F", "403.W4", "403.bed2", "east", 16.6, 28.6, "window")
win("4F", "4F.Wcor", "4F.corridor", "east", 31.6, 36.0, "corridor")
win("4F", "404.W1", "404.bed1", "east", 39.0, 49.0, "window")
win("4F", "404.W2", "404.living", "east", 52.4, 61.6, "window")
win("4F", "404.W3", "404.living", "rear", -26.6, -1.4, "window")
win("4F", "404.W4", "404.bed2", "rear", 1.8, 16.2, "window")

-- 5F
win("5F", "501.W1", "501.living", "front", 16.4, 26.6, "door_balcony")
win("5F", "501.W2", "501.bed1", "front", 8.0, 13.0, "window")
win("5F", "502.W1", "502.bed1", "front", -3.0, 4.4, "window")
win("5F", "502.W2", "502.living", "front", -17.0, -6.4, "door_balcony")
win("5F", "502.W3", "502.bed2", "front", -26.6, -20.4, "window")
win("5F", "502.W4", "502.bed2", "east", 2.4, 12.6, "window")
win("5F", "502.W5", "502.bed3", "east", 15.8, 22.6, "window")
win("5F", "502.W6", "502.bath", "east", 25.6, 29.0, "small")
win("5F", "5F.Wcor", "5F.corridor", "east", 31.6, 36.0, "corridor")
win("5F", "503.W1", "503.bed2", "east", 39.0, 47.6, "window")
win("5F", "503.W2", "503.bed3", "east", 51.0, 61.6, "window")
win("5F", "503.W3", "503.bed3", "rear", -26.6, -18.4, "window")
win("5F", "503.W4", "503.ldk", "rear", -15.0, 6.8, "window")
win("5F", "503.W5", "503.bed1", "rear", 10.0, 16.2, "window")

-- 6F
win("6F", "601.W1", "601.bed3", "front", -26.6, -20.4, "window")
win("6F", "601.W2", "601.bed3", "east", 2.4, 14.6, "window")
win("6F", "601.W3", "601.bed2", "front", -17.0, -11.0, "window")
win("6F", "601.W4", "601.living", "front", -7.6, 8.0, "door_balcony")
win("6F", "601.W5", "601.bed1", "front", 11.4, 26.6, "door_balcony")
win("6F", "601.W6", "601.utility", "east", 24.4, 28.6, "small")
win("6F", "6F.Wcor", "6F.corridor", "east", 31.6, 36.0, "corridor")
win("6F", "602.W1", "602.bed2", "east", 39.0, 44.0, "window")
win("6F", "602.W2", "602.living", "east", 52.4, 61.6, "window")
win("6F", "602.W3", "602.living", "rear", -26.6, -10.4, "window")
win("6F", "602.W4", "602.bed1", "rear", -7.0, 1.6, "window")
win("6F", "602.W5", "602.study", "rear", 5.0, 16.2, "window")

-- 7F
win("7F", "701.W1", "701.bed3", "front", -26.6, -20.4, "window")
win("7F", "701.W2", "701.bed3", "east", 2.4, 13.6, "window")
win("7F", "701.W3", "701.living", "front", -17.0, -3.4, "door_balcony")
win("7F", "701.W4", "701.bed4", "east", 17.0, 25.6, "window")
win("7F", "701.W5", "701.bath", "east", 29.0, 32.6, "small")
win("7F", "701.W6", "701.bed2", "east", 36.0, 44.6, "window")
win("7F", "701.W7", "701.bed1", "east", 48.0, 61.6, "window")
win("7F", "701.W8", "701.bed1", "rear", -26.6, -20.4, "window")
win("7F", "701.W9", "701.mbath", "rear", -17.0, -8.2, "small")
win("7F", "702.W1", "702.living", "front", 0.2, 13.6, "door_balcony")
win("7F", "702.W2", "702.bed1", "front", 17.0, 26.6, "window")
win("7F", "703.W1", "703.room", "rear", -4.6, 6.8, "window")
win("7F", "703.W2", "703.alpha", "rear", 10.0, 16.2, "window")

-- 8F
win("8F", "801.W1", "801.guest", "front", -26.6, -16.4, "full")
win("8F", "801.W2", "801.guest", "east", 2.4, 14.6, "full")
win("8F", "801.W3", "801.living", "front", -13.0, 8.6, "door_balcony", { head = 8.4 })
win("8F", "801.W4", "801.dining", "front", 11.4, 26.6, "door_balcony", { head = 8.4 })
win("8F", "801.W5", "801.gbath", "east", 18.0, 24.0, "small")
win("8F", "801.W6", "801.media", "east", 27.4, 40.0, "window")
win("8F", "801.W7", "801.master", "east", 43.4, 61.6, "full")
win("8F", "801.W8", "801.master", "rear", -26.6, -11.4, "full")
win("8F", "801.W9", "801.mbath", "rear", -8.0, -2.4, "small")
win("8F", "801.W10", "801.study", "rear", 1.0, 16.2, "window")

-- 9F (terrace-side windows are on the 9F front wall at w 17..18)
win("9F", "801.W11", "801.lounge9", "terrace", -17.6, 6.0, "door_terrace")
win("9F", "801.W12", "801.lounge9", "terrace", 8.8, 26.6, "door_terrace")
win("9F", "801.W13", "801.bed2", "terrace", -26.6, -21.0, "window")
win("9F", "801.W14", "801.bed2", "east", 19.4, 29.6, "window")
win("9F", "801.W15", "801.bed3", "east", 33.0, 48.6, "window")
win("9F", "801.W16", "801.gym9", "east", 52.0, 61.6, "window")
win("9F", "801.W17", "801.gym9", "rear", -26.6, -11.4, "full")
win("9F", "801.W18", "801.rear9", "rear", -8.0, 6.8, "window")
win("9F", "801.W19", "801.rear9", "rear", 9.6, 16.2, "window")

-------------------------------------------------------------------------------------------------
-- Balconies (front, projecting to w = -4, glass balustrade) and the 9F roof terrace
-------------------------------------------------------------------------------------------------
LP.BALCONIES = {
	{ id = "402.B", floor = "4F", unit = "402", room = "402.living", u0 = -6.8, u1 = 10.4 },
	{ id = "403.B", floor = "4F", unit = "403", room = "403.living", u0 = -26.8, u1 = -10.0 },
	{ id = "501.B", floor = "5F", unit = "501", room = "501.living", u0 = 8.0, u1 = 26.8 },
	{ id = "502.B", floor = "5F", unit = "502", room = "502.living", u0 = -26.8, u1 = 4.6 },
	{ id = "601.B", floor = "6F", unit = "601", room = "601.living", u0 = -26.8, u1 = 26.8 },
	{ id = "701.B", floor = "7F", unit = "701", room = "701.living", u0 = -26.8, u1 = -3.2 },
	{ id = "702.B", floor = "7F", unit = "702", room = "702.living", u0 = 0.0, u1 = 26.8 },
	{ id = "801.B", floor = "8F", unit = "801", room = "801.living", u0 = -26.8, u1 = 26.8 },
}
for _, b in LP.BALCONIES do
	b.w0, b.w1 = -LP.BALCONY.depth, 0
	b.rail = "glass"
end
LP.TERRACE = { id = "801.T", floor = "9F", unit = "801", room = "801.terrace", u0 = -28.0, u1 = 28.0, w0 = 1.0, w1 = 17.0, rail = "glass", jacuzzi = { u0 = 14.0, u1 = 22.0, w0 = 4.0, w1 = 10.0 } }

-------------------------------------------------------------------------------------------------
-- Units (homes). Prices live in GwangalliLivingConfig, not here.
-------------------------------------------------------------------------------------------------
LP.UNIT_ORDER = { "301", "302", "303", "304", "401", "402", "403", "404", "501", "502", "503", "601", "602", "701", "702", "703", "801" }
LP.UNITS = {
	["301"] = { floor = "3F", type = "oneroom_open", typeKo = "원룸 (오픈형)", bedrooms = 1, view = "sea", entry = "301.D1", spawn = { 17.9, 27.0, 180 } },
	["302"] = { floor = "3F", type = "oneroom_split", typeKo = "분리형 원룸", bedrooms = 1, view = "sea", entry = "302.D1", spawn = { 11.4, 27.4, 180 } },
	["303"] = { floor = "3F", type = "oneroom_closet", typeKo = "원룸 (복도 · 붙박이장형)", bedrooms = 1, view = "sea", entry = "303.D1", spawn = { -9.3, 27.2, 180 } },
	["304"] = { floor = "3F", type = "room15_corner", typeKo = "1.5룸 (코너 · 2면 창)", bedrooms = 1, alpha = 1, view = "sea_corner", entry = "304.D1", spawn = { -15.8, 27.6, 180 } },
	["401"] = { floor = "4F", type = "oneroom_split_l", typeKo = "분리형 원룸 (L형 주방)", bedrooms = 1, view = "sea", entry = "401.D1", spawn = { 14.9, 27.6, 180 } },
	["402"] = { floor = "4F", type = "tworoom_dress", typeKo = "투룸 (거실 + 침실 + 드레스룸)", bedrooms = 1, living = true, view = "sea", entry = "402.D1", spawn = { 9.1, 27.6, 180 } },
	["403"] = { floor = "4F", type = "tworoom_corner", typeKo = "투룸 코너 (침실 2 + 거실)", bedrooms = 2, living = true, view = "sea_corner", entry = "403.D1", spawn = { -11.6, 27.6, 180 } },
	["404"] = { floor = "4F", type = "tworoom_rear_storage", typeKo = "투룸 후면 (드레스룸 · 대형 창고)", bedrooms = 2, living = true, view = "city_corner", entry = "404.D1", spawn = { -3.0, 39.8, 0 } },
	["501"] = { floor = "5F", type = "tworoom_ocean", typeKo = "투룸 오션 (거실 + 침실)", bedrooms = 1, living = true, view = "sea", entry = "501.D1", spawn = { 9.3, 27.6, 180 } },
	["502"] = { floor = "5F", type = "threeroom_corner", typeKo = "쓰리룸 코너 (안방 욕실 · 드레스룸)", bedrooms = 3, living = true, view = "sea_corner", entry = "502.D1", spawn = { 3.35, 27.6, 180 } },
	["503"] = { floor = "5F", type = "threeroom_rear", typeKo = "쓰리룸 후면 (안방 욕실 · 다용도실)", bedrooms = 3, living = true, view = "city_corner", entry = "503.D1", spawn = { -7.0, 39.8, 0 } },
	["601"] = { floor = "6F", type = "family_4bay", typeKo = "가족형 4-bay 판상형 (방 3 · 욕실 2)", bedrooms = 3, living = true, view = "sea_corner", entry = "601.D1", spawn = { 6.5, 27.2, 180 } },
	["602"] = { floor = "6F", type = "tworoom_study_rear", typeKo = "투룸 + 서재 후면", bedrooms = 2, study = 1, living = true, view = "city_corner", entry = "602.D1", spawn = { -5.5, 39.8, 0 } },
	["701"] = { floor = "7F", type = "family_corner", typeKo = "가족형 코너 (방 4 · 욕실 2 · 워크인)", bedrooms = 3, study = 1, living = true, view = "sea_corner", entry = "701.D1", spawn = { -9.8, 33.5, 90 } },
	["702"] = { floor = "7F", type = "tworoom_wide", typeKo = "투룸 와이드 (드레스 · 파우더룸)", bedrooms = 1, living = true, view = "sea", entry = "702.D1", spawn = { 12.25, 27.6, 180 } },
	["703"] = { floor = "7F", type = "room15_rear", typeKo = "1.5룸 후면", bedrooms = 1, alpha = 1, view = "city", entry = "703.D1", spawn = { -3.25, 39.8, 0 } },
	["801"] = { floor = "8F", floors = { "8F", "9F" }, type = "penthouse_duplex", typeKo = "펜트하우스 복층 (루프 테라스 · 자쿠지)", bedrooms = 4, study = 2, living = true, view = "sea_panorama", entry = "801.D1", entry2 = "801.D12", spawn = { 4.4, 33.8, 90 } },
}
-- spawn = { u, w, yaw° } inside the entry, v = the unit floor's FFL. CFrame = frame * CFrame.new(u, v, -w)
-- * CFrame.Angles(0, math.rad(yaw), 0): yaw 0 = facing +w (inland), 90 = facing -u (east),
-- 180 = facing -w (the sea), 270 = facing +u (west / party wall).
LP.PARKING = {
	-- stall frames: centre at (u, w), ground v = 0, facing +w (out to the back lane); 8.2 x 16.8 studs
	{ stall = "P1", unit = "801", u = 24.6, w = 113.4 },
	{ stall = "P2", unit = "801", u = 16.4, w = 113.4 },
	{ stall = "P3", unit = "701", u = 8.2, w = 113.4 },
	{ stall = "P4", unit = "601", u = 0.0, w = 113.4 },
	{ stall = "P5", unit = "503", u = -8.2, w = 113.4 },
	{ stall = "P6", unit = "502", u = -16.4, w = 113.4 },
	{ stall = "P7", unit = nil, u = -24.6, w = 113.4, visitor = true },
}
LP.PARKING_STALL = { width = 8.2, depth = 16.8 }

-- 3F community: one storage locker per unit (세대 창고), placed by the shell in 3F.lockers
LP.LOCKERS = { room = "3F.lockers", units = LP.UNIT_ORDER }

-------------------------------------------------------------------------------------------------
-- Shop bays (interiors by the shops builder). Zones are BINDING: anchors / staff areas / walkability.
-------------------------------------------------------------------------------------------------
LP.SHOP_BAYS = {
	["1F-A"] = {
		shop = "cafe", name = "오션브루 커피", nameEn = "OCEAN BREW COFFEE", floor = "1F", room = "1F-A",
		zones = {
			customer = { { -28.0, 3.6, 1.0, 18.6 } }, -- seating, sea + street windows, terrace door
			counter = { { -20.0, 3.6, 18.6, 22.0 } }, -- order counter + showcase + pickup counter line (customer side at w 18.6)
			staff = { { -20.0, 3.6, 22.0, 30.0 } }, -- bar: espresso machine, grinder, sink, fridge, cup storage, dishwasher
			storage = { { -28.0, -20.5, 25.0, 30.0 } }, -- 창고 (door from staff)
			restroom = { { -28.0, -20.5, 18.6, 24.5 } }, -- customer restroom (door from customer zone)
		},
		terrace = { u0 = -26.0, u1 = -12.0, w0 = -3.6, w1 = -0.4 }, -- 3 outdoor tables in the forecourt
		anchors = { order_counter = 1, pickup = 1, workstation = 3, seat = 14, queue = 3, wait = 2 },
	},
	["1F-B"] = {
		shop = "convenience", name = "바다마트24 광안오션점", nameEn = "BADAMART 24", floor = "1F", room = "1F-B",
		zones = {
			customer = { { 4.4, 28.0, 1.0, 8.0 }, { 9.4, 28.0, 8.0, 21.0 } }, -- entrance path + aisles: shelves by category, chilled showcase (west party wall), ice-cream / frozen case
			counter = { { 7.4, 9.4, 8.0, 19.0 } }, -- checkout counter on the east side just inside the door (customer side at u 9.4): POS, card terminal, hot case
			staff = { { 4.4, 7.4, 8.0, 21.0 } }, -- behind the counter: cigarette / lotto wall, fryer, staff passage to the back room
			storage = { { 4.4, 20.8, 21.5, 30.0 } }, -- back room (partition at w 21..21.5 with a staff door): stock shelves, walk-in cooler door, staff desk; + 1F.cvs_store at the rear
			eating = { { 20.0, 28.0, 1.0, 7.0 } }, -- 취식 공간: window counter + stools, microwave + hot water
		},
		anchors = { order_counter = 1, workstation = 3, browse = 6, seat = 4, use = 1, queue = 3 },
	},
	["1F-C"] = {
		shop = "realty", name = "오션뷰 공인중개사사무소", nameEn = "OCEAN VIEW REALTY", floor = "1F", room = "1F-C",
		zones = {
			customer = { { -28.0, -14.6, 51.0, 58.4 } }, -- reception counter, client chairs, listings board + the 부동산 상담 kiosk (homes_econ, tag LivingRealtor)
			staff = { { -28.0, -14.6, 58.4, 63.0 } }, -- 2 agent desks, file cabinets
		},
		anchors = { order_counter = 1, workstation = 2, seat = 2 },
	},
	["2F-A"] = {
		shop = "restaurant", name = "바다곁 밥상", nameEn = "BADAGYEOT KOREAN DINING", floor = "2F", room = "2F-A",
		zones = {
			customer = { { -28.0, 28.0, 1.0, 20.0 } }, -- hall: tables of 4 / 2, window bar seats
			entry = { { -14.0, -3.0, 20.5, 30.0 } }, -- waiting bench + cashier counter (order_counter)
			kitchen = { { 4.0, 20.8, 20.5, 30.0 }, { 20.8, 28.0, 20.5, 26.6 } }, -- burners + hood (north wall), prep, washing, fridge, dish racks, pass window at w 20.5
			storage = { { -2.5, 3.5, 20.5, 30.0 } }, -- 식재료 창고 (shelves + reach-in fridge), door from the kitchen
			staff = { { -28.0, -14.5, 20.5, 30.0 } }, -- 직원 휴게 · 락커 (staff door from the corridor)
		},
		anchors = { order_counter = 1, pickup = 1, workstation = 5, seat = 24, wait = 3, queue = 2 },
	},
	["2F-B"] = {
		shop = "office", name = "광안 스튜디오 오피스", nameEn = "GWANGAN STUDIO", floor = "2F", room = "2F-B",
		zones = {
			customer = { { -18.7, -8.0, 37.6, 46.0 } }, -- reception + waiting
			staff = { { -18.7, 8.2, 46.0, 63.0 }, { -28.0, -18.7, 46.8, 63.0 } }, -- open office: 8 desks
			meeting = { { 8.2, 17.6, 46.6, 63.0 } }, -- glass meeting room, 6 seats
			pantry = { { -7.5, 8.2, 37.6, 45.5 } }, -- 탕비실: sink, fridge, coffee machine
		},
		anchors = { order_counter = 1, workstation = 8, seat = 6, use = 1 },
	},
}

-- Common-area anchors the shell must place (NPC anchor schema: contract §D)
LP.COMMON_ANCHORS = {
	{ room = "1F.lobby", kind = "wait", count = 3 },
	{ room = "1F.vestibule", kind = "use", count = 1, use = "mailbox" },
	{ room = "1F.lobby", kind = "use", count = 1, use = "parcel_locker" },
	{ room = "1F.mgmt", kind = "workstation", count = 1 },
	{ room = "1F.mgmt", kind = "order_counter", count = 1 },
	{ room = "3F.lounge", kind = "seat", count = 6 },
	{ room = "3F.laundry", kind = "use", count = 3, use = "washer" },
	-- one elevator_wait anchor in front of the landing door on every floor 1F-9F, one door_wait at every unit entry
}

-------------------------------------------------------------------------------------------------
-- Helpers (pure)
-------------------------------------------------------------------------------------------------
function LP.floor(id: string): any
	return LP.FLOOR_BY_ID[id]
end

function LP.levelOf(floorId: string): number
	local f = LP.FLOOR_BY_ID[floorId]
	return if f then f.level else 0
end

-- v (height above the 1F floor) of a level's FFL
function LP.fflV(level: number): number
	local f = LP.FLOOR_BY_LEVEL[level]
	return if f then f.v else 0
end

-- The floor whose storey contains height v (above the 1F floor); nil below 1F or above RF.
function LP.levelAtV(v: number): number?
	for i = #LP.FLOORS, 1, -1 do
		local f = LP.FLOORS[i]
		if v >= f.v - 0.6 then
			return f.level
		end
	end
	return nil
end

function LP.room(id: string): any
	return LP.ROOMS[id]
end

function LP.roomsOf(floorId: string): { string }
	return LP.ROOMS_BY_FLOOR[floorId] or {}
end

function LP.unit(id: string): any
	return LP.UNITS[id]
end

function LP.unitRooms(unitId: string): { string }
	local out = {}
	for _, id in LP.ROOM_ORDER do
		if LP.ROOMS[id].unit == unitId then
			table.insert(out, id)
		end
	end
	return out
end

function LP.rectArea(q: any): number
	return (q.u1 - q.u0) * (q.w1 - q.w0)
end

function LP.roomArea(id: string): number -- square studs
	local a = 0
	for _, q in LP.ROOMS[id].rects do
		a += LP.rectArea(q)
	end
	return a
end

-- 전용면적 (m², rooms only: no balcony / terrace / void)
function LP.unitAreaM2(unitId: string): number
	local a = 0
	for _, id in LP.unitRooms(unitId) do
		local r = LP.ROOMS[id]
		if r.kind ~= "terrace" and r.kind ~= "void" then
			a += LP.roomArea(id)
		end
	end
	return math.floor(a * LP.SQ_M_PER_SQ_STUD * 10 + 0.5) / 10
end

function LP.unitBaths(unitId: string): number
	local n = 0
	for _, id in LP.unitRooms(unitId) do
		local k = LP.ROOMS[id].kind
		if k == "bath" or k == "master_bath" then
			n += 1
		end
	end
	return n
end

function LP.unitStorageRooms(unitId: string): number
	local n = 0
	for _, id in LP.unitRooms(unitId) do
		local k = LP.ROOMS[id].kind
		if k == "dress" or k == "storage" or k == "utility" then
			n += 1
		end
	end
	return n
end

function LP.unitBalconyM2(unitId: string): number
	local a = 0
	for _, b in LP.BALCONIES do
		if b.unit == unitId then
			a += (b.u1 - b.u0) * (b.w1 - b.w0)
		end
	end
	if LP.TERRACE.unit == unitId then
		a += (LP.TERRACE.u1 - LP.TERRACE.u0) * (LP.TERRACE.w1 - LP.TERRACE.w0)
	end
	return math.floor(a * LP.SQ_M_PER_SQ_STUD * 10 + 0.5) / 10
end

function LP.unitParking(unitId: string): { string }
	local out = {}
	for _, p in LP.PARKING do
		if p.unit == unitId then
			table.insert(out, p.stall)
		end
	end
	return out
end

-- Summary row for listings / comparison UIs (homes_econ adds prices from the config).
function LP.unitSummary(unitId: string): any
	local u = LP.UNITS[unitId]
	if not u then
		return nil
	end
	local f = LP.FLOOR_BY_ID[u.floor]
	return {
		unit = unitId,
		label = unitId .. "호",
		floor = f.level,
		floors = u.floors,
		type = u.type,
		typeKo = u.typeKo,
		areaM2 = LP.unitAreaM2(unitId),
		pyeong = math.floor(LP.unitAreaM2(unitId) / 3.3058 * 10 + 0.5) / 10,
		bedrooms = u.bedrooms,
		baths = LP.unitBaths(unitId),
		storageRooms = LP.unitStorageRooms(unitId),
		balconyM2 = LP.unitBalconyM2(unitId),
		view = u.view,
		parking = LP.unitParking(unitId),
	}
end

-- Which room contains (u, w) on a floor (clear rects only; walls return nil).
function LP.roomAt(floorId: string, u: number, w: number): string?
	for _, id in LP.roomsOf(floorId) do
		for _, q in LP.ROOMS[id].rects do
			if u >= q.u0 and u <= q.u1 and w >= q.w0 and w <= q.w1 then
				return id
			end
		end
	end
	return nil
end

-- World <-> building coordinates (numbers only: works in Lune and Roblox).
function LP.toWorld(u: number, v: number, w: number): (number, number, number)
	local o, r, l = LP.ORIGIN, LP.RIGHT, LP.LOOK
	return o[1] + r[1] * u + l[1] * w, o[2] + v, o[3] + r[3] * u + l[3] * w
end
function LP.fromWorld(x: number, y: number, z: number): (number, number, number)
	local o, r, l = LP.ORIGIN, LP.RIGHT, LP.LOOK
	local dx, dz = x - o[1], z - o[3]
	return dx * r[1] + dz * r[3], y - o[2], dx * l[1] + dz * l[3]
end
-- The exact site frame as a CFrame (LookVector = +w inland, RightVector = +u, origin at v = 0).
-- Pass the CFrame / Vector3 libraries (Roblox globals at runtime, the kit's K.CF / K.V3 in Lune).
-- K.at(frame, u, v, w) == frame * CFrame.new(u, v, -w) works with it exactly like with Plan.frame.
function LP.frameCFrame(CFrameLib: any, Vector3Lib: any): any
	local o, l = LP.ORIGIN, LP.LOOK
	local p = Vector3Lib.new(o[1], o[2], o[3])
	local look = Vector3Lib.new(l[1], l[2], l[3])
	local up = Vector3Lib.new(0, 1, 0)
	local right = look:Cross(up) -- = LP.RIGHT
	return CFrameLib.fromMatrix(p, right, up) -- LookVector = -(right x up) = look
end

-------------------------------------------------------------------------------------------------
-- Validator (pure). Returns ok, problems { string }. Run: lune run build/living_check.luau
-------------------------------------------------------------------------------------------------
local GAPS = { 0, 0.5, 0.8, 1.0 }
local EPS = 0.02

local function approx(a: number, b: number): boolean
	return math.abs(a - b) <= EPS
end

local function isGap(g: number): boolean
	for _, x in GAPS do
		if approx(g, x) then
			return true
		end
	end
	return false
end

-- edge samples: does any other rect sit across this edge at a legal gap?
local function covered(floorId: string, selfId: string, axis: string, fixed: number, outward: number, t: number): (boolean, number?)
	-- axis "u": the edge runs along u at w = fixed; outward = +1 (toward +w) / -1. t = u sample.
	-- gap 1.0 (exterior wall) is legal only between an outdoor room (terrace) and an indoor room.
	local best: number? = nil
	local selfOutdoor = LP.ROOM_KINDS[LP.ROOMS[selfId].kind].outdoor == true
	for _, id in LP.roomsOf(floorId) do
		local otherOutdoor = LP.ROOM_KINDS[LP.ROOMS[id].kind].outdoor == true
		if id ~= selfId then
			for _, q in LP.ROOMS[id].rects do
				local lo, hi, near
				if axis == "u" then
					lo, hi = q.u0, q.u1
					near = if outward > 0 then q.w0 - fixed else fixed - q.w1
				else
					lo, hi = q.w0, q.w1
					near = if outward > 0 then q.u0 - fixed else fixed - q.u1
				end
				local legal = isGap(near) and (not approx(near, 1.0) or selfOutdoor ~= otherOutdoor)
				if t >= lo - 0.85 and t <= hi + 0.85 and near >= -EPS and near <= 1.0 + EPS and legal then
					if best == nil or near < best then
						best = near
					end
				end
			end
		end
	end
	return best ~= nil, best
end

local function envelopeCovers(floorId: string, axis: string, fixed: number, outward: number, t: number, roomKind: string): boolean
	local e = LP.envelope(floorId)
	local function inside(lo: number, hi: number): boolean
		return t >= lo - 0.85 and t <= hi + 0.85
	end
	if axis == "u" then
		if outward < 0 and approx(fixed, e.w0) and inside(e.u0, e.u1) then
			return true
		end
		if outward > 0 and approx(fixed, e.w1) and inside(e.u0, e.u1) then
			return true
		end
		if e.terrace and roomKind == "terrace" then
			local tq = e.terrace
			if (outward < 0 and approx(fixed, tq.w0)) or (outward > 0 and approx(fixed, tq.w1)) then
				return true
			end
		end
	else
		if outward < 0 and approx(fixed, e.u0) then
			return true
		end
		if outward > 0 and approx(fixed, e.u1) then
			return true
		end
	end
	return false
end

-- the wall between rooms a and b: returns axis ("u" wall runs along u), fixed coordinate (centre of
-- the wall), lo, hi (overlap along the wall), gap. Collinear segments of L-shaped rooms are merged;
-- with `at` (and optional `axis`) the segment containing that coordinate wins, else the longest.
local function wallBetween(aId: string, bId: string, at: number?, wantAxis: string?): (string?, number?, number?, number?, number?)
	local A, B = LP.ROOMS[aId], LP.ROOMS[bId]
	if not A or not B then
		return nil
	end
	local segs = {}
	local function add(axis: string, fixed: number, lo: number, hi: number, g: number)
		if hi - lo <= EPS then
			return
		end
		for _, sg in segs do
			if sg.axis == axis and approx(sg.fixed, fixed) and approx(sg.gap, g) and lo <= sg.hi + EPS and hi >= sg.lo - EPS then
				sg.lo, sg.hi = math.min(sg.lo, lo), math.max(sg.hi, hi)
				return
			end
		end
		table.insert(segs, { axis = axis, fixed = fixed, lo = lo, hi = hi, gap = g })
	end
	for _, p in A.rects do
		for _, q in B.rects do
			for _, sd in { { p.w1, q.w0 }, { q.w1, p.w0 } } do
				local g = sd[2] - sd[1]
				if g >= -EPS and g <= 1.0 + EPS then
					add("u", (sd[1] + sd[2]) / 2, math.max(p.u0, q.u0), math.min(p.u1, q.u1), g)
				end
			end
			for _, sd in { { p.u1, q.u0 }, { q.u1, p.u0 } } do
				local g = sd[2] - sd[1]
				if g >= -EPS and g <= 1.0 + EPS then
					add("w", (sd[1] + sd[2]) / 2, math.max(p.w0, q.w0), math.min(p.w1, q.w1), g)
				end
			end
		end
	end
	-- a second merge pass (segments added in different orders)
	local merged = true
	while merged do
		merged = false
		for i = 1, #segs do
			for j = i + 1, #segs do
				local x, y = segs[i], segs[j]
				if x and y and x.axis == y.axis and approx(x.fixed, y.fixed) and approx(x.gap, y.gap) and y.lo <= x.hi + EPS and y.hi >= x.lo - EPS then
					x.lo, x.hi = math.min(x.lo, y.lo), math.max(x.hi, y.hi)
					table.remove(segs, j)
					merged = true
					break
				end
			end
			if merged then
				break
			end
		end
	end
	local best = nil
	for _, sg in segs do
		local contains = at ~= nil and at >= sg.lo - EPS and at <= sg.hi + EPS and (wantAxis == nil or wantAxis == sg.axis)
		local score = (if contains then 1000 else 0) + (sg.hi - sg.lo)
		if wantAxis and wantAxis ~= sg.axis then
			score -= 2000
		end
		if best == nil or score > best.score then
			best = { axis = sg.axis, fixed = sg.fixed, lo = sg.lo, hi = sg.hi, gap = sg.gap, score = score }
		end
	end
	if not best then
		return nil
	end
	return best.axis, best.fixed, best.lo, best.hi, best.gap
end
LP.wallBetween = wallBetween

-- facade wall of a room for an outside door / window: axis, fixed (outer face side), lo, hi
local SIDE_AXIS = { front = "u", rear = "u", terrace = "u", east = "w", west = "w" }
local function facadeSpan(roomId: string, side: string): (number?, number?)
	local r = LP.ROOMS[roomId]
	local e = LP.envelope(r.floor)
	local lo, hi = nil, nil
	for _, q in r.rects do
		local touches = false
		if side == "front" then
			touches = approx(q.w0, e.w0) or (r.kind == "terrace")
		elseif side == "rear" then
			touches = approx(q.w1, e.w1)
		elseif side == "east" then
			touches = approx(q.u0, e.u0)
		elseif side == "west" then
			touches = approx(q.u1, e.u1)
		elseif side == "terrace" then
			touches = e.terrace ~= nil and approx(q.w0, e.w0)
		end
		if touches then
			local a, b
			if SIDE_AXIS[side] == "u" then
				a, b = q.u0, q.u1
			else
				a, b = q.w0, q.w1
			end
			lo = if lo then math.min(lo, a) else a
			hi = if hi then math.max(hi, b) else b
		end
	end
	return lo, hi
end
LP.facadeSpan = facadeSpan

-- Door geometry: returns { axis, fixed, lo, hi, gap, hingeAt, swingDir } or nil + reason.
-- swingDir = +1 if the leaf swings toward +w (axis "u") / +u (axis "w"), -1 otherwise.
function LP.doorGeometry(d: any): (any?, string?)
	if d.a == "outside" or d.b == "outside" then
		local inside = if d.a == "outside" then d.b else d.a
		local r = LP.ROOMS[inside]
		if not r then
			return nil, "unknown room " .. tostring(inside)
		end
		local side = d.side
		if not side then
			return nil, "outside door without side"
		end
		local lo, hi = facadeSpan(inside, side)
		if not lo then
			return nil, "room " .. inside .. " does not touch the " .. side .. " facade"
		end
		local e = LP.envelope(r.floor)
		local axis = SIDE_AXIS[side]
		local fixed = if side == "front" then e.w0 - 0.5 elseif side == "rear" then e.w1 + 0.5 elseif side == "east" then e.u0 - 0.5 else e.u1 + 0.5
		local inward = if side == "front" or side == "east" then 1 else -1
		return { axis = axis, fixed = fixed, lo = lo :: number, hi = hi :: number, gap = 1.0, inward = inward, inside = inside }, nil
	end
	local axis, fixed, lo, hi, gap = wallBetween(d.a, d.b, d.at, d.axis)
	if not axis then
		return nil, "rooms " .. d.a .. " / " .. d.b .. " share no wall"
	end
	return { axis = axis, fixed = fixed, lo = lo, hi = hi, gap = gap }, nil
end

-- which side of the wall (sign along the wall normal) room `id` lies on
local function sideOf(id: string, axis: string, fixed: number): number
	local r = LP.ROOMS[id]
	if not r then
		return 0
	end
	local s = 0
	for _, q in r.rects do
		local c = if axis == "u" then (q.w0 + q.w1) / 2 else (q.u0 + q.u1) / 2
		if c > fixed then
			s += LP.rectArea(q)
		else
			s -= LP.rectArea(q)
		end
	end
	return if s >= 0 then 1 else -1
end

local function pointInRoom(id: string, u: number, w: number, tol: number): boolean
	local r = LP.ROOMS[id]
	if not r then
		return false
	end
	for _, q in r.rects do
		if u >= q.u0 - tol and u <= q.u1 + tol and w >= q.w0 - tol and w <= q.w1 + tol then
			return true
		end
	end
	return false
end

-- Swing arc square of a door (for decor no-placement zones and validation):
-- returns u0, u1, w0, w1 or nil (slide / opening / auto / elevator have no arc).
function LP.doorSwingRect(d: any): (number?, number?, number?, number?)
	if not d.swing or not d.hinge then
		return nil
	end
	local g = LP.doorGeometry(d)
	if not g then
		return nil
	end
	local half = d.width / 2
	local a0, a1 = d.at - half, d.at + half
	local faceGap = (g.gap or 0.8) / 2
	local dir
	if d.swing == "outside" then
		dir = -(g.inward or 1)
	else
		dir = sideOf(d.swing, g.axis, g.fixed)
	end
	local n0 = g.fixed + dir * faceGap
	local n1 = n0 + dir * d.width
	if g.axis == "u" then
		return a0, a1, math.min(n0, n1), math.max(n0, n1)
	else
		return math.min(n0, n1), math.max(n0, n1), a0, a1
	end
end

function LP.validate(): (boolean, { string })
	local problems = {}
	local function bad(msg: string)
		table.insert(problems, msg)
	end
	-- 1. rect sanity + overlaps per floor
	for _, f in LP.FLOORS do
		local ids = LP.roomsOf(f.id)
		for i, id in ids do
			local r = LP.ROOMS[id]
			for _, q in r.rects do
				if q.u1 <= q.u0 or q.w1 <= q.w0 then
					bad(id .. ": empty rect")
				end
				local e = LP.envelope(f.id)
				local wMin = if r.kind == "terrace" then 1.0 else e.w0
				if q.u0 < e.u0 - EPS or q.u1 > e.u1 + EPS or q.w0 < wMin - EPS or q.w1 > e.w1 + EPS then
					bad(string.format("%s: rect [%.1f %.1f %.1f %.1f] outside the %s envelope", id, q.u0, q.u1, q.w0, q.w1, f.id))
				end
			end
			for j = i + 1, #ids do
				local o = LP.ROOMS[ids[j]]
				for _, p in r.rects do
					for _, q in o.rects do
						local du = math.min(p.u1, q.u1) - math.max(p.u0, q.u0)
						local dw = math.min(p.w1, q.w1) - math.max(p.w0, q.w0)
						if du > EPS and dw > EPS then
							bad(string.format("%s overlaps %s by %.2f x %.2f", id, ids[j], du, dw))
						end
					end
				end
			end
		end
		-- 2. every edge closed (wall gap to a neighbour or the envelope)
		for _, id in ids do
			local r = LP.ROOMS[id]
			for _, q in r.rects do
				local edges = {
					{ "u", q.w0, -1, q.u0, q.u1 },
					{ "u", q.w1, 1, q.u0, q.u1 },
					{ "w", q.u0, -1, q.w0, q.w1 },
					{ "w", q.u1, 1, q.w0, q.w1 },
				}
				for _, ed in edges do
					local axis, fixed, outward, lo, hi = ed[1], ed[2], ed[3], ed[4], ed[5]
					local t = lo + 0.25
					while t < hi - 0.2 do
						local ok = covered(f.id, id, axis, fixed, outward, t)
						-- the same room's other rects (L shapes) also close an edge
						if not ok then
							for _, q2 in r.rects do
								if q2 ~= q then
									local lo2, hi2, near
									if axis == "u" then
										lo2, hi2 = q2.u0, q2.u1
										near = if outward > 0 then q2.w0 - fixed else fixed - q2.w1
									else
										lo2, hi2 = q2.w0, q2.w1
										near = if outward > 0 then q2.u0 - fixed else fixed - q2.u1
									end
									if t >= lo2 - EPS and t <= hi2 + EPS and approx(near, 0) then
										ok = true
									end
								end
							end
						end
						if not ok and not envelopeCovers(f.id, axis, fixed, outward, t, r.kind) then
							bad(string.format("%s: open edge (%s = %.2f, side %+d) at %.2f", id, if axis == "u" then "w" else "u", fixed, outward, t))
							break
						end
						t += 0.5
					end
				end
			end
		end
	end
	-- 3. doors
	for _, d in LP.DOORS do
		local g, why = LP.doorGeometry(d)
		if not g then
			bad("door " .. d.id .. ": " .. tostring(why))
		else
			local half = d.width / 2
			if d.at - half < g.lo + 0.3 - EPS or d.at + half > g.hi - 0.3 + EPS then
				bad(string.format("door %s: opening %.2f..%.2f does not fit the wall %.2f..%.2f (0.3 jamb margin)", d.id, d.at - half, d.at + half, g.lo, g.hi))
			end
			if d.a ~= "outside" and d.b ~= "outside" and approx(g.gap, 0) then
				bad("door " .. d.id .. ": rooms are open to each other (gap 0): remove the door or add a wall")
			end
			if d.kind == "opening" or d.kind == "slide" or d.kind == "glass_auto" or d.kind == "elevator" or d.kind == "double" then
				-- no single-leaf arc
			elseif not d.hinge or not d.swing then
				bad("door " .. d.id .. ": swing door without hinge / swing")
			else
				local u0, u1, w0, w1 = LP.doorSwingRect(d)
				if u0 and d.swing ~= "outside" then
					local okArc = true
					for _, c in { { u0, w0 }, { u1, w0 }, { u0, w1 }, { u1, w1 } } do
						if not pointInRoom(d.swing, c[1], c[2], 0.05) then
							okArc = false
						end
					end
					if not okArc then
						bad(string.format("door %s: swing arc [%.1f %.1f %.1f %.1f] leaves room %s", d.id, u0 :: number, u1 :: number, w0 :: number, w1 :: number, d.swing))
					end
				end
			end
		end
	end
	-- 4. windows on the facade of their room
	for _, wd in LP.WINDOWS do
		local r = LP.ROOMS[wd.room]
		if not r then
			bad("window " .. wd.id .. ": unknown room " .. wd.room)
		else
			local lo, hi = facadeSpan(wd.room, wd.side)
			if not lo then
				bad("window " .. wd.id .. ": room " .. wd.room .. " does not touch the " .. wd.side .. " facade")
			elseif wd.a < (lo :: number) + 0.6 - EPS or wd.b > (hi :: number) - 0.6 + EPS then
				bad(string.format("window %s: %.2f..%.2f outside the room span %.2f..%.2f (0.6 pier)", wd.id, wd.a, wd.b, lo :: number, hi :: number))
			end
			if math.abs(wd.a * 5 - math.floor(wd.a * 5 + 0.5)) > 0.01 or math.abs(wd.b * 5 - math.floor(wd.b * 5 + 0.5)) > 0.01 then
				bad("window " .. wd.id .. ": jambs not on the 0.2 facade grid")
			end
			if wd.side == "west" then
				bad("window " .. wd.id .. ": the west facade is a party wall")
			end
		end
	end
	-- 5. units: every unit has an entry door, rooms, a bath, a kitchen (or ldk / kitchenette), a window room
	for _, uid in LP.UNIT_ORDER do
		local u = LP.UNITS[uid]
		if not LP.DOOR_BY_ID[u.entry] then
			bad("unit " .. uid .. ": entry door " .. tostring(u.entry) .. " missing")
		end
		local kinds = {}
		for _, id in LP.unitRooms(uid) do
			kinds[LP.ROOMS[id].kind] = true
		end
		if not (kinds.bath or kinds.master_bath) then
			bad("unit " .. uid .. ": no bathroom")
		end
		if not (kinds.kitchen or kinds.ldk or kinds.room) then
			bad("unit " .. uid .. ": no kitchen")
		end
		local hasWindow = false
		for _, wd in LP.WINDOWS do
			if LP.ROOMS[wd.room] and LP.ROOMS[wd.room].unit == uid then
				hasWindow = true
			end
		end
		if not hasWindow then
			bad("unit " .. uid .. ": no window")
		end
	end
	-- 6. every bedroom-like room has a window (Korean code + the spec: views)
	local needWindow = { room = true, bedroom = true, master = true, living = true, ldk = true }
	for _, id in LP.ROOM_ORDER do
		local r = LP.ROOMS[id]
		if r.unit and needWindow[r.kind] then
			local has = false
			for _, wd in LP.WINDOWS do
				if wd.room == id then
					has = true
				end
			end
			if not has and id ~= "801.family" then
				bad("room " .. id .. " (" .. r.kind .. ") has no window")
			end
		end
	end
	-- 7. reachability: every room on a floor is reachable from the floor's common circulation (1F: the
	--    street) through doors, openings, open (gap 0) boundaries and balcony / terrace doors
	for _, f in LP.FLOORS do
		local ids = LP.roomsOf(f.id)
		if #ids > 0 then
			local adj: { [string]: { [string]: boolean } } = {}
			local function link(a: string, b: string)
				adj[a] = adj[a] or {}
				adj[b] = adj[b] or {}
				adj[a][b] = true
				adj[b][a] = true
			end
			for _, d in LP.DOORS do
				if d.floor == f.id then
					link(d.a, d.b)
				end
			end
			for _, wd in LP.WINDOWS do
				if wd.floor == f.id and (wd.kind == "door_terrace") then
					link(wd.room, LP.TERRACE.room)
				end
			end
			local function openBetween(a: string, b: string): boolean
				for _, p in LP.ROOMS[a].rects do
					for _, q in LP.ROOMS[b].rects do
						local du = math.min(p.u1, q.u1) - math.max(p.u0, q.u0)
						local dw = math.min(p.w1, q.w1) - math.max(p.w0, q.w0)
						if (approx(p.w1, q.w0) or approx(q.w1, p.w0)) and du >= 1.0 then
							return true
						end
						if (approx(p.u1, q.u0) or approx(q.u1, p.u0)) and dw >= 1.0 then
							return true
						end
					end
				end
				return false
			end
			for i, a in ids do
				for j = i + 1, #ids do
					local b = ids[j]
					if openBetween(a, b) then
						link(a, b)
					end
				end
			end
			local start = if f.id == "1F" then "outside" elseif f.level >= 8 then f.id .. ".hall" else f.id .. ".corridor"
			local seen: { [string]: boolean } = { [start] = true }
			local queue = { start }
			while #queue > 0 do
				local cur = table.remove(queue, 1) :: string
				for nb in adj[cur] or {} do
					if not seen[nb] then
						seen[nb] = true
						table.insert(queue, nb)
					end
				end
			end
			for _, id in ids do
				if not seen[id] then
					bad("room " .. id .. " is not reachable from " .. start .. " (no door / opening path)")
				end
			end
		end
	end
	return #problems == 0, problems
end

-- ASCII plan of a floor (1 char = 1 stud; for the check script and reviews)
function LP.ascii(floorId: string): string
	local W, D = 58, 64
	local grid = {}
	for row = 0, D + 4 do
		local line = {}
		for col = 0, W do
			line[col] = "#"
		end
		grid[row] = line
	end
	local letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	local legend = {}
	for i, id in LP.roomsOf(floorId) do
		local ch = string.sub(letters, ((i - 1) % #letters) + 1, ((i - 1) % #letters) + 1)
		local r = LP.ROOMS[id]
		if r.kind == "elevator" then
			ch = "E"
		elseif r.kind == "stair" then
			ch = "S"
		elseif r.kind == "shaft" then
			ch = "P"
		end
		table.insert(legend, ch .. "=" .. id)
		for _, q in r.rects do
			for row = math.ceil(q.w0), math.floor(q.w1) - 1 do
				for colU = math.ceil(q.u0), math.floor(q.u1) - 1 do
					local col = 28 - colU -- print with east (u = -29) on the RIGHT as seen from the sea? no: plan view from above, sea at the top, east at the right
					col = colU + 29
					if row >= 0 and row <= D + 4 and col >= 0 and col <= W then
						grid[row + 2][col] = ch
					end
				end
			end
		end
	end
	for _, d in LP.DOORS do
		if d.floor == floorId then
			local g = LP.doorGeometry(d)
			if g then
				local a0, a1 = math.floor(d.at - d.width / 2 + 0.5), math.floor(d.at + d.width / 2 - 0.5)
				for t = a0, a1 do
					local row, col
					if g.axis == "u" then
						row, col = math.floor(g.fixed) + 2, t + 29
					else
						row, col = math.floor(d.at) + 2, math.floor(g.fixed) + 29
						row = t + 2
					end
					if grid[row] and col >= 0 and col <= W then
						grid[row][col] = if d.kind == "opening" then " " else "+"
					end
				end
			end
		end
	end
	local out = { "plan " .. floorId .. "  (top = SEA facade w=0, bottom = rear w=64; left = u -29 EAST street side, right = u +29 WEST party wall)" }
	for row = 0, D + 4 do
		local s = {}
		for col = 0, W do
			table.insert(s, grid[row][col])
		end
		table.insert(out, table.concat(s))
	end
	table.insert(out, table.concat(legend, "  "))
	return table.concat(out, "\n")
end

return LP
