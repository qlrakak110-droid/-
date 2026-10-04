-- GwangalliLivingShared (LS): the NAME CONTRACT of the living city (docs/living_city_contract.md §B-§D).
-- Every CollectionService tag, attribute, remote and enum string the five builders share lives here, so
-- a typo becomes a nil-index instead of a silent mismatch. Pure: no instances, no services at require
-- time (Lune build modules and runtime scripts both require it).
--   local LS = require(ReplicatedStorage.GwangalliLivingShared)
--   part:AddTag(LS.TAG.Fixture); part:SetAttribute(LS.ATTR.Kind, "fridge")
-- Owner: the architect (names); append-only. Builders may ADD names in a marked block at the end with
-- their key in a comment; never rename or remove one.

local LS = {}
LS.VERSION = 1
LS.BUILDING_ID = "lc_tower"

-------------------------------------------------------------------------------------------------
-- CollectionService tags
-------------------------------------------------------------------------------------------------
LS.TAG = {
	Building = "LivingBuilding", -- the building root Model (attrs BuildingId, Frame (CFrame), Version)
	Unit = "LivingUnit", -- Model "Unit_<id>" (attrs UnitId, Floor, Type, BuildingId; runtime OwnerUserId, OwnerName, Mode, Claimed)
	Room = "LivingRoom", -- invisible marker Part per room (attrs RoomId, UnitId?, Kind, Label, Floor; runtime LightsOn, Mood)
	Door = "LivingDoor", -- door Model "Door_<DoorId>" (attrs DoorId, Kind, Lock, UnitId?, RoomA, RoomB, Hinge, Swing; runtime Open, Locked, OpenBy)
	Keypad = "LivingKeypad", -- door-lock keypad Part (attrs DoorId, UnitId?)
	Doorbell = "LivingDoorbell", -- doorbell button Part outside a unit door (attrs UnitId, DoorId)
	Intercom = "LivingIntercom", -- 공동현관 call panel (vestibule) / wallpad inside units (attrs DoorId | UnitId, Where = "lobby" | "unit")
	Switch = "LivingSwitch", -- wall light switch Part (attrs RoomIds = "302.room" or "a,b", UnitId?)
	Light = "LivingLight", -- Light instance (PointLight / SpotLight / SurfaceLight) (attrs RoomId, Group = "main" | "accent" | "night" | "shop" | "common")
	Lamp = "LivingLamp", -- visible lamp BasePart that glows when its room light is on (attrs RoomId, LampColor)
	Fixture = "LivingFixture", -- interactive fixture Model / Part (attrs FixtureId, Kind, RoomId, UnitId?, Label, Rights; kind attrs §B.4)
	Elevator = "LivingElevator", -- elevator Model (attrs ElevatorId; runtime state §B.5)
	ElevatorCar = "LivingElevatorCar", -- the car Model (Persistent streaming)
	ElevatorButton = "LivingElevatorButton", -- functional button Part (attrs ElevatorId, Where = "car" | "hall", Floor, Dir?, Action?)
	ElevatorDisplay = "LivingElevatorDisplay", -- Part with a SurfaceGui "Display" (attrs ElevatorId, Where, Floor?)
	Mailbox = "LivingMailbox", -- per-unit mailbox Part in the vestibule (attrs UnitId | Bay)
	Parcel = "LivingParcel", -- 무인택배함 in the lobby
	Directory = "LivingDirectory", -- floor directory board / floor guide (attrs Floor?)
	UnitSign = "LivingUnitSign", -- unit number plate Part ("301호") (attrs UnitId)
	FloorSign = "LivingFloorSign", -- floor number sign (hall / stair landing) (attrs Floor)
	ExitSign = "LivingExitSign", -- green 비상구 sign (always lit, Neon)
	Surface = "LivingSurface", -- editor surface Part (attrs Surface = floor | wall | ceiling, RoomId, UnitId, Editable)
	Finish = "LivingFinish", -- finish Part recoloured by wallpaper / flooring themes (attrs FinishKind = wall | floor, RoomId, UnitId, OrigColor, OrigMaterial)
	Blocked = "LivingBlocked", -- editor no-placement volume (attrs Reason, UnitId, RoomId?, DoorId?)
	Spawn = "LivingSpawn", -- unit spawn Part (attrs UnitId); LookVector = facing
	Parking = "LivingParking", -- parking stall Part (attrs Stall, UnitId?, Visitor?); CFrame = car ground frame (LookVector = out to the lane)
	Realtor = "LivingRealtor", -- 부동산 상담 point in 1F-C (homes_econ prompt)
	WindowGlow = "LivingWindowGlow", -- Neon card just inside a window, shown at night when the room light is on and the interior zone is hidden (attrs RoomId)
	Staging = "LivingStaging", -- runtime: staging furniture Model in a vacant unit (decor)
	Placed = "LivingPlaced", -- runtime: a player-placed furniture Model (decor) (attrs Uid, ItemId, Colorway, UnitId, OwnerUserId)
	Locker = "LivingLocker", -- 3F 세대 창고 locker (also a Fixture with Kind = "locker") (attrs UnitId)
	NpcAnchor = "NpcAnchor", -- NPC facility anchor Part (schema §D)
	StaffZone = "LivingStaffZone", -- invisible volume of a shop staff / storage zone (attrs Bay, Zone)
}

-------------------------------------------------------------------------------------------------
-- Attributes
-------------------------------------------------------------------------------------------------
LS.ATTR = {
	-- identity
	BuildingId = "BuildingId",
	Frame = "Frame", -- CFrame attribute on the building root: the site frame (LP.frameCFrame)
	UnitId = "UnitId",
	RoomId = "RoomId",
	RoomIds = "RoomIds",
	Floor = "Floor", -- number: the level (1..10)
	Kind = "Kind",
	Label = "Label",
	Type = "Type",
	DoorId = "DoorId",
	FixtureId = "FixtureId",
	ElevatorId = "ElevatorId",
	Bay = "Bay",
	Zone = "Zone",
	Stall = "Stall",
	-- doors
	Lock = "Lock", -- "none" | "unit" | "building" | "resident" | "resident_stair" | "staff" | "shop"
	Hinge = "Hinge", -- "low" | "high" (plan coordinate end of the hinge)
	Swing = "Swing", -- room id the leaf opens into
	RoomA = "RoomA",
	RoomB = "RoomB",
	OpenYaw = "OpenYaw", -- number, degrees: rotate the Leaf about HingePivot's Y axis by this to open
	OpenOffset = "OpenOffset", -- Vector3 (world): slide offset when open (sliding doors, elevator panels, drawers)
	SlideOffset = "SlideOffset", -- alias used on drawers (Vector3, world)
	OpenScale = "OpenScale", -- number: curtain panel X scale when open (0..1)
	OpenScaleY = "OpenScaleY", -- number: blind Y scale when open
	AutoClose = "AutoClose", -- number seconds (door closer); 0 = stays open
	-- runtime state (server writes; clients render)
	Open = "Open",
	OpenT = "OpenT", -- workspace:GetServerTimeNow() of the last change
	Locked = "Locked",
	OpenBy = "OpenBy",
	LightsOn = "LightsOn",
	Mood = "Mood", -- lighting mood id (HS.LIGHTS keys + "off")
	On = "On",
	Channel = "Channel",
	State = "State",
	T0 = "T0",
	Occupied = "Occupied", -- seat / bed point occupied (string of user ids "1,2")
	OwnerUserId = "OwnerUserId",
	OwnerName = "OwnerName",
	Mode = "Mode", -- unit mode: "vacant" | "rent" | "buy" | "tour" | "overflow"
	Claimed = "Claimed",
	-- fixtures
	Rights = "Rights", -- "public" | "basic" | "private" | "owner" | "staff"
	Pose = "Pose", -- on SitAt / LieAt points: "sit" | "lie"
	Machine = "Machine", -- machine type (LS.MACHINES)
	Cycle = "Cycle", -- seconds
	Motion = "Motion", -- "spin" | "shake" | "slide" | "none"
	WaterKind = "WaterKind", -- "sink" | "basin" | "shower" | "bath" | "jacuzzi" | "toilet"
	Capacity = "Capacity", -- storage slots / seats / anchor capacity
	Decorative = "Decorative", -- true: looks like a control but does nothing (never tagged as functional)
	-- editor
	Surface = "Surface",
	FinishKind = "FinishKind",
	OrigColor = "OrigColor",
	OrigMaterial = "OrigMaterial",
	Editable = "Editable",
	Reason = "Reason",
	Uid = "Uid",
	ItemId = "ItemId",
	Colorway = "Colorway",
	-- elevator (on the LivingElevator model, server writes)
	ElState = "ElState", -- "idle" | "moving" | "opening" | "open" | "closing" | "stopped"
	ElLevel = "ElLevel", -- number: current / last passed level
	ElDir = "ElDir", -- -1 | 0 | 1
	ElFromV = "ElFromV", -- motion profile: start height (v above the 1F floor)
	ElToV = "ElToV",
	ElT0 = "ElT0", -- server time the motion started
	ElU0 = "ElU0", -- initial speed of the motion profile (studs/s, >= 0; non-zero only after a mid-travel retarget)
	ElSpeed = "ElSpeed",
	ElAccel = "ElAccel",
	ElDoor = "ElDoor", -- "closed" | "opening" | "open" | "closing"
	ElDoorT0 = "ElDoorT0",
	ElDoorLevel = "ElDoorLevel",
	ElHall = "ElHall", -- string "3U,5D" lit hall calls
	ElCar = "ElCar", -- string "7,9" lit car calls
	ElSeq = "ElSeq", -- increments on every change
	Where = "Where",
	Dir = "Dir",
	Action = "Action",
	-- NPC anchors (§D)
	AnchorId = "AnchorId",
	Building = "Building",
	Room = "Room",
	Radius = "Radius",
	Group = "Group",
	Shop = "Shop",
	Use = "Use",
	LinkedFixture = "LinkedFixture", -- anchor -> FixtureId of the seat / machine it stands for (players using it mark the anchor in_use)
	Owner = "Owner",
	ReservedUntil = "ReservedUntil",
	-- misc
	LampColor = "LampColor",
	Visitor = "Visitor",
	LOD = "LOD", -- "zone" | "near" (GwangalliWorld/DetailLOD contract)
	LODRadius = "LODRadius",
	LODCenter = "LODCenter",
}

-------------------------------------------------------------------------------------------------
-- Remotes (children of ReplicatedStorage.GwangalliRemotes; each owner creates its own at init)
-------------------------------------------------------------------------------------------------
LS.REMOTE = {
	Sys = "LivingSys", -- RemoteFunction (systems): queries + acknowledged ops
	SysEvent = "LivingSysEvent", -- RemoteEvent (systems): button presses / fixture use up; notifications down
	Home = "LivingHome", -- RemoteFunction (homes_econ): listings, tour, contract, move, storage, access, parking, invites
	HomeEvent = "LivingHomeEvent", -- RemoteEvent (homes_econ): handover, rights changed, rent events, invitations
	Decor = "LivingDecor", -- RemoteFunction (decor): catalog, buy, place, move, rotate, retrieve, sell, themes, undo
	DecorEvent = "LivingDecorEvent", -- RemoteEvent (decor): editor state pushes
	Shop = "LivingShop", -- RemoteEvent (shops, optional): shop-only machine flows
}

-- Server-side APIs for scripts outside the GwangalliGameplay folder (other sessions: NPC, jobs ...)
LS.API = {
	Anchors = "GwangalliAnchorsAPI", -- ServerStorage BindableFunction (systems): Invoke(op, ...) §D
	AnchorsChanged = "GwangalliAnchorsChanged", -- ServerStorage BindableEvent (systems): Fire(anchorId, state, owner)
	Income = "GwangalliIncomeAPI", -- ServerStorage BindableFunction (homes_econ): Invoke(op, ...) §E
	Living = "GwangalliLivingAPI", -- ServerStorage BindableFunction (homes_econ): Invoke(op, ...) §C.5
}

-------------------------------------------------------------------------------------------------
-- Enums
-------------------------------------------------------------------------------------------------
LS.LOCKS = { "none", "unit", "building", "resident", "resident_stair", "staff", "shop" }

LS.FIXTURE_KINDS = {
	-- kind = { interactive, action (prompt ActionText), rights, note }
	drawer = { true, "열기", "basic", "Drawer parts + SlideOffset" },
	cabinet = { true, "열기", "basic", "Leaf + HingePivot + OpenYaw" },
	base_cabinet = { true, "열기", "basic", "kitchen base doors (Leaf) + drawers (Drawer)" },
	upper_cabinet = { true, "열기", "basic", "kitchen wall cabinet leaves" },
	shoe_cabinet = { true, "열기", "basic", "신발장 leaves" },
	mirror_cabinet = { true, "열기", "basic", "욕실 거울장 leaf" },
	wardrobe = { true, "열기", "private", "붙박이장 leaves (contents = storage UI when Capacity > 0)" },
	fridge = { true, "열기", "basic", "door leaves + inner light" },
	curtain = { true, "열기", "basic", "Panel parts: OpenScale + OpenOffset" },
	blind = { true, "올리기", "basic", "Slats part: OpenScaleY + OpenOffset" },
	faucet = { true, "물 틀기", "basic", "Water part + Splash emitter + water sound; WaterKind" },
	shower = { true, "샤워기 틀기", "basic", "Water part (falling) + steam-free; WaterKind = shower" },
	bathtub = { true, "물 받기", "basic", "Water fill part rises; WaterKind = bath" },
	jacuzzi = { true, "자쿠지 켜기", "basic", "terrace: bubbling water part" },
	toilet = { true, "물 내리기", "basic", "flush sound + lid" },
	tv = { true, "TV 켜기", "basic", "Screen part + SurfaceGui TVGui; On + Channel" },
	doorbell = { true, "초인종", "public", "rings the unit owner (LivingAccess)" },
	wallpad = { true, "월패드", "basic", "unit intercom: visitor list, open the 공동현관 / door" },
	intercom = { true, "호출", "public", "공동현관 call panel: dial a unit" },
	keypad = { true, "도어락", "public", "door lock: opens for allowed players, else offers the doorbell" },
	storage = { true, "보관함", "private", "item storage UI (homes_econ): Capacity slots" },
	locker = { true, "세대 창고", "private", "3F locker of one unit (UnitId)" },
	seat = { true, "앉기", "basic", "SitAt points (Pose = sit)" },
	sofa = { true, "앉기", "basic", "several SitAt points" },
	bed = { true, "눕기", "basic", "LieAt points (Pose = lie); 잠자기 in your own home (Life.sleep)" },
	lamp = { true, "조명", "basic", "a standing / desk lamp with its own Light (RoomId group accent)" },
	machine = { true, "작동", "basic", "Machine + Cycle + Indicator + Motion (+ Moving part)" },
	washer = { true, "세탁 시작", "basic", "machine: Machine = washer" },
	dryer = { true, "건조 시작", "basic", "machine: Machine = dryer" },
	cooktop = { true, "불 켜기", "basic", "machine: Machine = cooktop (burner glow)" },
	hood = { true, "후드 켜기", "basic", "machine: Machine = hood (fan + light)" },
	mailbox = { true, "우편함 열기", "private", "per-unit mailbox: bills / letters (homes_econ)" },
	parcel_locker = { true, "택배함", "public", "무인택배함: honest message when empty" },
	-- static (no prompt): sinks / basins (their faucet is the interactive part), signs
	sink = { false, nil, nil, "kitchen sink bowl" },
	basin = { false, nil, nil, "washbasin bowl" },
	aircon = { false, nil, nil, "wall AC indoor unit (static)" },
	switch = { false, nil, nil, "tagged LivingSwitch instead" },
	exit_sign = { false, nil, nil, "tagged LivingExitSign" },
	floor_sign = { false, nil, nil, "tagged LivingFloorSign" },
	directory = { false, nil, nil, "tagged LivingDirectory" },
	fire_hydrant_box = { false, nil, nil, "소화전 함 (static)" },
	desk_builtin = { false, nil, nil, "management desk (seat via a separate seat fixture)" },
	sofa_builtin = { true, "앉기", "public", "lobby / lounge benches (seat)" },
	seat_builtin = { true, "앉기", "public", "built-in benches (terrace, lounge)" },
	locker_bank = { false, nil, nil, "3F locker bank frame; each locker is a Fixture kind locker" },
}

LS.MACHINES = {
	espresso = { cycle = 8, motion = "none", label = "에스프레소 머신" },
	grinder = { cycle = 4, motion = "shake", label = "그라인더" },
	microwave = { cycle = 10, motion = "spin", label = "전자레인지" },
	washer = { cycle = 20, motion = "spin", label = "세탁기" },
	dryer = { cycle = 20, motion = "spin", label = "건조기" },
	dishwasher = { cycle = 15, motion = "none", label = "식기세척기" },
	cooktop = { cycle = 0, motion = "none", label = "인덕션 · 가스레인지" }, -- toggle (on until turned off / 10 min)
	hood = { cycle = 0, motion = "spin", label = "레인지 후드" },
	pos = { cycle = 2, motion = "none", label = "포스기" },
	card_terminal = { cycle = 3, motion = "none", label = "카드 단말기" },
	hot_water = { cycle = 5, motion = "none", label = "온수기" },
	capsule = { cycle = 6, motion = "none", label = "캡슐 커피머신" },
	fryer = { cycle = 12, motion = "shake", label = "튀김기" },
	rice_cooker = { cycle = 15, motion = "none", label = "밥솥" },
	printer = { cycle = 4, motion = "slide", label = "프린터" },
}

-- Child names inside fixtures / doors that the systems client understands (no per-prop scripts):
LS.PART = {
	Leaf = "Leaf", -- hinged leaf (BasePart or Model); attribute OpenYaw; rotates about the sibling HingePivot
	HingePivot = "HingePivot", -- invisible anchored Part: its CFrame Y axis is the hinge axis
	Panel = "Panel", -- sliding panel (doors, curtains): OpenOffset (+ OpenScale for curtains)
	Drawer = "Drawer", -- sliding drawer: SlideOffset
	Slats = "Slats", -- blind slats: OpenScaleY + OpenOffset
	Water = "Water", -- water stream / fill part (Transparency 1 when off)
	Splash = "Splash", -- ParticleEmitter (default texture only) under Water
	Screen = "Screen", -- TV screen part with SurfaceGui "TVGui"
	Indicator = "Indicator", -- machine status lamp (Neon colour by state)
	Moving = "Moving", -- machine part animated by Motion (spin / shake / slide)
	ShowWhenRunning = "ShowWhenRunning", -- visible only while State = running (steam, glow ...)
	ShowWhenDone = "ShowWhenDone", -- visible only while State = done (the coffee cup, the warm lunch box ...)
	SitAt = "SitAt", -- seat point (Attachment or invisible Part): CFrame = HumanoidRootPart target while seated; attribute Pose = sit
	LieAt = "LieAt", -- bed point: CFrame = HumanoidRootPart target while lying, LookVector = head direction; Pose = lie
	UseAt = "UseAt", -- where the character stands to use a fixture (faces the fixture)
	Sensor = "Sensor", -- elevator door safety volume (per landing)
	CarZone = "CarZone", -- elevator rider volume inside the car
}

LS.SURFACES = { "floor", "wall", "ceiling", "table" }
LS.BLOCK_REASONS = { "door_swing", "door_path", "entry", "path", "elevator", "stair", "fixture", "window_door", "balcony" }

LS.ANCHOR_KINDS = {
	order_counter = "주문 · 계산대 (손님이 서는 자리)",
	pickup = "픽업대 (음료 · 음식 받는 자리)",
	seat = "좌석 (Pose sit; Group = 테이블)",
	workstation = "직원 작업 자리 (머신 · 화구 · 계산 · 책상)",
	queue = "줄 서는 자리 (순서 = Group 안의 번호)",
	wait = "대기 자리 (로비 소파 · 식당 대기석)",
	browse = "진열대 앞 둘러보는 자리",
	use = "기기 사용 자리 (전자레인지 · 우편함 · 세탁기, Use = 이름)",
	elevator_wait = "엘리베이터 승강장 대기 자리",
	door_wait = "세대 현관 앞 (배달 · 방문 대기)",
	entrance = "출입구 안쪽",
	service = "서빙 동선 지점",
}
LS.ANCHOR_STATES = { "free", "reserved", "in_use" }

-------------------------------------------------------------------------------------------------
-- Rights (pure). Roles of a player toward a unit: computed server-side by homes_econ / access.
-------------------------------------------------------------------------------------------------
LS.ROLES = { "owner", "tenant", "guest", "touring", "visitor", "staff" }
LS.RIGHTS = {
	-- right = roles that have it
	enter = { owner = true, tenant = true, guest = true, touring = true, staff = true },
	lights = { owner = true, tenant = true, guest = true, touring = true, staff = true },
	fixtures = { owner = true, tenant = true, guest = true, touring = true, staff = true }, -- Rights = "basic"
	storage = { owner = true, tenant = true, staff = true }, -- Rights = "private"
	decor_place = { owner = true, tenant = true, staff = true }, -- movable furniture
	decor_finish = { owner = true, staff = true }, -- wallpaper / flooring / built-in colours (tenants: 원상복구 의무)
	lighting_mood = { owner = true, tenant = true, staff = true },
	access_manage = { owner = true, tenant = true, staff = true }, -- grant / revoke visitors
	invite = { owner = true, tenant = true, staff = true },
	parking = { owner = true, tenant = true, staff = true },
	sleep = { owner = true, tenant = true, staff = true },
	doorbell = { owner = true, tenant = true, guest = true, touring = true, visitor = true, staff = true },
}
function LS.can(role: string?, right: string): boolean
	local set = LS.RIGHTS[right]
	return set ~= nil and role ~= nil and set[role] == true
end
-- fixture Rights attribute -> the right it needs
LS.FIXTURE_RIGHT = { public = "doorbell", basic = "fixtures", private = "storage", owner = "decor_finish", staff = "decor_finish" }

-------------------------------------------------------------------------------------------------
-- Sounds: ONLY these verified built-in paths exist (contract §8). Anything else = NEEDED EXTERNAL ASSET.
-------------------------------------------------------------------------------------------------
LS.SOUND_PATHS = {
	ping = "rbxasset://sounds/electronicpingshort.wav",
	click = "rbxasset://sounds/clickfast.wav",
	swoosh = "rbxasset://sounds/swoosh.wav",
	footsteps = "rbxasset://sounds/action_footsteps_plastic.mp3",
	land = "rbxasset://sounds/action_jump_land.mp3",
	falling = "rbxasset://sounds/action_falling.mp3",
	water = "rbxasset://sounds/impact_water.mp3",
	swim = "rbxasset://sounds/action_swim.mp3",
}
function LS.isAllowedSound(id: string): boolean
	for _, p in LS.SOUND_PATHS do
		if p == id then
			return true
		end
	end
	return false
end

-------------------------------------------------------------------------------------------------
-- NPC anchor schema check (pure; used by LivingAnchors and the build checks)
-------------------------------------------------------------------------------------------------
-- rec = { id, kind, building, floor, room, position = {x,y,z}, facing = {x,y,z}, radius, capacity?, group?, shop?, use? }
function LS.validAnchor(rec: any): (boolean, string?)
	if type(rec) ~= "table" then
		return false, "not a table"
	end
	if type(rec.id) ~= "string" or #rec.id < 3 then
		return false, "id"
	end
	if LS.ANCHOR_KINDS[rec.kind] == nil then
		return false, "kind " .. tostring(rec.kind)
	end
	if type(rec.floor) ~= "number" or rec.floor < 1 or rec.floor > 10 then
		return false, "floor"
	end
	if type(rec.room) ~= "string" then
		return false, "room"
	end
	if type(rec.radius) ~= "number" or rec.radius <= 0 or rec.radius > 12 then
		return false, "radius"
	end
	return true, nil
end

-- Anchor id convention: "lc.<floor>.<room>.<kind>.<n>" e.g. "lc.1.1F-A.order_counter.1"
function LS.anchorId(level: number, roomId: string, kind: string, n: number): string
	return string.format("lc.%d.%s.%s.%d", level, roomId, kind, n)
end

-------------------------------------------------------------------------------------------------
-- Extension hook (owner: homes_econ). GwangalliGameplayShared calls LS.extend(G) at the end of its
-- require (same pattern as GwangalliHomesShared.extend) to register the listing "lc_tower" and wrap
-- G.homeDaily / G.homePrices / G.homeValue for it. Until homes_econ fills it in, it does nothing.
-------------------------------------------------------------------------------------------------
function LS.extend(_g: any)
	-- homes_econ: implement here (see docs/living_city_contract.md §C.4)
end

-------------------------------------------------------------------------------------------------
-- Appended names (builders: add below with your key in a comment; never rename the ones above)
-------------------------------------------------------------------------------------------------

return LS
