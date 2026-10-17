-- GwangalliCarDealerShared/Config: every tunable of the 광안 오토 딜러 add-on. Prices, the 3-car limit, 할부
-- rules, plates and saving stay the garage's (GwangalliGarageShared / Garage.luau); this file only tunes our
-- dealer layer (NPCs, catalog, cash-back benefits, test drive of showroom models, UI).

local C = {}

C.Debug = false

-------------------------------------------------------------------------------------------------
-- Sales NPCs
-------------------------------------------------------------------------------------------------
-- Our own consultant(s) on the showroom floor. `spots` are tried in order: each must stand on the floor
-- (ray), be free of map parts (box test), stay off the turntable sweeps and ≥ 8 studs from the garage's
-- prompts. y is taken from the floor ray (0 here). face = the direction the NPC looks (toward the door).
C.NPCS = {
	{
		id = "consult",
		enabled = true,
		name = "한서윤 대리",
		role = "영업 컨설턴트",
		icon = "👩‍💼",
		voice = "consult",
		look = { body = "f", age = "young", style = "suit", hair = "bob" },
		spots = {
			{ pos = Vector3.new(-568.2, 0, 426.8), face = Vector3.new(0, 0, 1) }, -- 브랜드 월 앞, 상담 테이블 두 세트 사이
			{ pos = Vector3.new(-577.4, 0, 449.8), face = Vector3.new(0, 0, 1) }, -- 1번 통로 교차점
			{ pos = Vector3.new(-570.8, 0, 468.6), face = Vector3.new(0, 0, 1) }, -- 입구 왼쪽
		},
	},
	{
		id = "used",
		enabled = false, -- a second desk for 중고차 · 렌트 (off: one consultant reads better in v7's showroom)
		name = "정우진 과장",
		role = "중고차 · 렌트 담당",
		icon = "🧑‍💼",
		voice = "consult",
		tab = "used",
		look = { body = "m", age = "adult", style = "suit" },
		spots = {
			{ pos = Vector3.new(-553.3, 0, 449.6), face = Vector3.new(0, 0, 1) },
		},
	},
}

-- Map staff rigs that become dealers too (their pose / look is never touched; a prompt is added next to
-- them on its own anchor part in our folder, the rig only gets attribute GwDealerNpc = true).
C.HOOK_STAFF = {
	enabled = true,
	tags = { "GarageStaff" },
	-- Role attribute -> how the dealer presents himself (roles not listed are skipped: 김기사 is a mechanic)
	roles = {
		owner = { id = "boss", name = "박사장", role = "광안 오토 대표", icon = "👨‍💼", voice = "boss" },
		sales = { id = "sales", name = nil, role = "영업 담당", icon = "🧑‍💼", voice = "consult" },
		dealer = { id = "dealer", name = nil, role = "영업 담당", icon = "🧑‍💼", voice = "consult" },
	},
	-- the owner stands behind his desk, whose own prompt (E) opens the garage panel: ours uses another key
	key = Enum.KeyCode.F,
	gamepadKey = Enum.KeyCode.ButtonY,
	range = 13,
}

C.PROMPT = {
	action = "딜러와 상담하기",
	range = 10,
	height = 1.4, -- above the NPC's root
}

C.SPOT_RULES = {
	footprint = Vector3.new(2.6, 5.6, 2.6),
	turntableClear = 9.4, -- from a GarageTurntable centre (disc r 8.5 + spinning car)
	promptClear = 8,
	showroomPad = 1.5,
	maxFloorDrop = 14, -- the floor must be within this many studs below the spot's ray start
}

C.WAIT = {
	venue = 90, -- s to wait for the GarageShop venue (tag)
	showroomSettle = 8, -- s: GwangalliShowroom places its display cars ~6 s after start
	showroomPlaced = 45, -- s to wait for Workspace.GwangalliShowroom.Placed when its models exist
}

-- Buying / test driving / renting need the player within this many studs of a dealer NPC (browsing works
-- anywhere: the phone opens a read-only catalog). The garage still applies its own 160-stud check.
C.CONTRACT_RANGE = 75

-------------------------------------------------------------------------------------------------
-- Catalog
-------------------------------------------------------------------------------------------------
-- The 13 named showroom models (GS.MODELS) have no 3D templates in v7 (ServerStorage.GwangalliCarModels is
-- missing): bought, they arrive as the kit car of their kind. false = list a model only when its template
-- exists; true = list them all (detail says "출고 차량: 동급 …").
C.SHOW_MODELS_WITHOUT_TEMPLATE = false

-- Real brand names (기아 / 현대 / 제네시스) are shown only when GS.SHOW_REAL_NAMES is on; otherwise the
-- brand filter groups by line-up.
C.LINEUPS = {
	compact = "시티 라인",
	sedan = "시티 라인",
	suv = "아웃도어 라인",
	van = "비즈니스 라인",
	truck = "비즈니스 라인",
	luxury = "시그니처 라인",
	rent = "렌터카",
}

-- "NEW" ribbon (신규 입고) on these entry ids
C.NEW_ARRIVALS = { "kit:suv:new", "kit:luxury:new", "model:ioniq5n", "model:ev6" }

-- Power-train / economy flavour per kind (no brands). Models with 하이브리드 / 전기 in their label override.
C.POWERTRAIN = {
	compact = { fuel = "1.0 가솔린", eff = "복합 13.8km/L", comfort = 2, utility = 3 },
	sedan = { fuel = "2.0 가솔린", eff = "복합 12.6km/L", comfort = 4, utility = 3 },
	suv = { fuel = "2.5 가솔린 터보", eff = "복합 10.8km/L", comfort = 4, utility = 4 },
	van = { fuel = "3.5 가솔린", eff = "복합 9.1km/L", comfort = 4, utility = 5 },
	truck = { fuel = "2.5 디젤", eff = "복합 9.9km/L", comfort = 2, utility = 5 },
	luxury = { fuel = "3.5 가솔린 터보", eff = "복합 8.6km/L", comfort = 5, utility = 3 },
}
C.POWERTRAIN_HYBRID = { fuel = "1.6 하이브리드", eff = "복합 19.8km/L" }
C.POWERTRAIN_EV = { fuel = "전기 모터 · 77kWh", eff = "1회 충전 450km" }

-- Weight shown in the spec table (VS mass is in RMU; × this ≈ kg)
C.MASS_TO_KG = 9.5

-------------------------------------------------------------------------------------------------
-- Benefits (paid by our server after the garage's purchase succeeded, as a refund-labelled bank credit,
-- so they never count as earnings). Capped at MAX_CASHBACK_RATE of the price.
-------------------------------------------------------------------------------------------------
C.SPECIALS = { enabled = true, count = 2, rate = 0.07, minPrice = 140000 }
C.USED_DISCOUNT_CASHBACK = true -- 레벨 혜택 "중고차 5% 할인" (level 3, GwangalliProgressShared)
C.USED_DISCOUNT_FALLBACK = { level = 3, rate = 0.05 }
C.MAX_CASHBACK_RATE = 0.12
C.CASHBACK_LABELS = {
	special = "광안 오토 이달의 특가 · %d%% 할인 환불",
	used = "광안 오토 레벨 혜택 · 중고차 %d%% 할인 환불",
	trade = "광안 오토 보상판매 추가 정산금",
}

-- 보상판매 (trade-in): the garage buys the old car (its sell value: 60 % of what was paid, minus any 할부
-- left), we add this share of that value on top, then the new contract runs.
C.TRADEIN = { enabled = true, bonusRate = 0.05 }

-- Level gates advertised by the level UI (할부 at 8, 플래그십 신차 at 18). The garage's own panel does not
-- check them, so enforcing them only on our path would be inconsistent: false shows them as advice only.
C.ENFORCE_LEVEL_GATES = false

-------------------------------------------------------------------------------------------------
-- Test drive
-------------------------------------------------------------------------------------------------
-- Kit cars use the garage's own 60 s test drive (its HUD, route and return). Showroom models whose 3D
-- template exists use our dealer test drive (the model itself, same rules):
C.TEST = {
	seconds = 75,
	cooldown = 45,
	grace = 4, -- s before "left the car" counts
	leftLimit = 5, -- s out of the car -> the test ends
	returnRadius = 40, -- teleported back to GarageReturn only when farther than this
}

-------------------------------------------------------------------------------------------------
-- Server limits
-------------------------------------------------------------------------------------------------
C.RATE = { perSecond = 3, burst = 6 }
C.COOLDOWN = { hello = 1, catalog = 0.8, buy = 2, sell = 2, testdrive = 3, endtest = 1, rent = 2, deliver = 2, wish = 0.4, waypoint = 2 }
C.WISH_MAX = 12
C.STORE = { name = "GwangalliCarDealer_v1", saveEvery = 60, visitGap = 300 }

-------------------------------------------------------------------------------------------------
-- Previews / UI
-------------------------------------------------------------------------------------------------
C.PREVIEW = {
	maxParts = 420,
	minPartSize = 0.12, -- smaller parts are dropped first when a model is over maxParts
	thumbsDesktop = 10, -- live 3D card thumbnails at once (others show the glyph tile)
	thumbsPhone = 5,
	spinDegPerSec = 16,
}

C.UI = {
	order = { hud = 30, catalog = 33, dialog = 36, contract = 38, ceremony = 40 },
	signHold = 0.8, -- s: "길게 눌러 서명하기"
	typeSpeed = 42, -- graphemes per second (dialog typewriter)
	greetRadius = 12, -- our NPC waves when the player first comes this close
	lookRadius = 16,
	bubbleCooldown = 300,
}

return C
