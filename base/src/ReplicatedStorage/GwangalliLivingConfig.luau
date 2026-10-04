-- GwangalliLivingConfig (LC): every tunable number of the living city in one file (spec §7: "가격과 성장
-- 속도는 설정 파일에서 조정"). Pure data + tiny pure helpers; no services at require time.
-- OWNER: homes_econ (ECON / GROWTH / TEST / STARTER / INCOME / PARKING sections). Section owners may edit
-- ONLY their marked section: systems (ACCESS / ELEVATOR / FIXTURES / FOOTSTEPS / LIGHTING), decor (DECOR),
-- shops (SHOPS). Read it everywhere with  local LC = require(ReplicatedStorage.GwangalliLivingConfig).
-- Money is in 원 (KRW, integers). Time: "day" = one in-game day = GwangalliGameplayShared.DAY_SECONDS
-- (1440 real seconds); "clock" = in-game hour 0..24.

local LC = {}
LC.VERSION = 1

-------------------------------------------------------------------------------------------------
-- ECON (owner: homes_econ): per-unit offers. rent = { deposit, perDay }, buy = { price }.
-- Units without `rent` cannot be rented; without `buy` cannot be bought. 관리비 (maintenance) of an
-- owned home = price * UPKEEP_RATE per day (rounded to 100). Rent already includes 관리비.
-------------------------------------------------------------------------------------------------
LC.UPKEEP_RATE = 0.0011 -- 0.11 % of the price per in-game day (12,000,000 → 13,200원/일)
LC.DEPOSIT_REFUND = 1.0 -- deposit returned on a clean move-out (minus arrears)
LC.SELL_RATE = 0.92 -- selling an owned home back to the market: current value x 0.92 (중개수수료 · 세금)
LC.EVICT_AFTER = 3 -- missed daily payments before eviction (same as G.EVICT_AFTER)

LC.UNITS = {
	["301"] = { rent = { deposit = 300000, perDay = 12000 }, buy = { price = 4200000 } },
	["302"] = { rent = { deposit = 300000, perDay = 13000 }, buy = { price = 4500000 } },
	["303"] = { rent = { deposit = 300000, perDay = 12500 }, buy = { price = 4400000 } },
	["304"] = { rent = { deposit = 400000, perDay = 15000 }, buy = { price = 5200000 } },
	["401"] = { rent = { deposit = 400000, perDay = 15500 }, buy = { price = 5600000 } },
	["402"] = { rent = { deposit = 800000, perDay = 22000 }, buy = { price = 8200000 } },
	["403"] = { rent = { deposit = 900000, perDay = 24000 }, buy = { price = 8800000 } },
	["404"] = { rent = { deposit = 900000, perDay = 21000 }, buy = { price = 8000000 } },
	["501"] = { rent = { deposit = 1000000, perDay = 26000 }, buy = { price = 9800000 } },
	["502"] = { rent = { deposit = 2000000, perDay = 42000 }, buy = { price = 15500000 } },
	["503"] = { rent = { deposit = 1600000, perDay = 34000 }, buy = { price = 12800000 } },
	["601"] = { buy = { price = 24000000 } },
	["602"] = { rent = { deposit = 1500000, perDay = 32000 }, buy = { price = 12500000 } },
	["701"] = { buy = { price = 26500000 } },
	["702"] = { rent = { deposit = 1800000, perDay = 38000 }, buy = { price = 14800000 } },
	["703"] = { rent = { deposit = 500000, perDay = 16000 }, buy = { price = 5800000 } },
	["801"] = { buy = { price = 52000000 } },
}

-- Comparison labels for the realty UI (view keys come from GwangalliLivingPlan.UNITS[].view)
LC.VIEW_LABEL = {
	sea = "바다 전망 (광안대교 정면)",
	sea_corner = "바다 + 골목 2면 전망 (코너)",
	sea_panorama = "파노라마 바다 전망 + 루프 테라스",
	city = "도심 · 금련산 전망",
	city_corner = "도심 2면 전망 (코너)",
}
LC.VIEW_STARS = { sea = 4, sea_corner = 5, sea_panorama = 5, city = 2, city_corner = 3 }

-------------------------------------------------------------------------------------------------
-- GROWTH (owner: homes_econ): how fast things grow
-------------------------------------------------------------------------------------------------
LC.GROWTH = {
	homeValuePerDay = 0.002, -- owned home market value +0.2 % per in-game day of ownership ...
	homeValueCap = 1.4, -- ... up to +40 % of the purchase price
	furnitureResale = 0.5, -- selling furniture back: 50 % (undo within DECOR.FRESH_SECONDS refunds 100 %)
	incomeMultiplier = 1.0, -- global multiplier on every income credited through the income interface (§E)
	rentRaise = { everyDays = 14, rate = 0.03, cap = 1.15 }, -- rent +3 % every 14 in-game days of tenancy, max +15 %
	-- progression gates (net worth = G.netWorth) so a fresh player cannot buy the penthouse on day 1
	unlock = {
		rent = 0, -- anyone with the deposit
		buySmall = 0, -- 원룸 / 투룸 purchase
		buyFamily = 8000000, -- 가족형 (502 / 503 / 601 / 701)
		buyPenthouse = 30000000, -- 801
	},
	familyUnits = { ["502"] = true, ["503"] = true, ["601"] = true, ["701"] = true },
	penthouseUnits = { ["801"] = true },
}

-------------------------------------------------------------------------------------------------
-- STARTER (owner: homes_econ): temporary lodging -> rented 원룸 -> move -> buy
-------------------------------------------------------------------------------------------------
LC.STARTER = {
	lodgingListing = "goshiwon", -- existing instanced listing used as 임시 숙소 (GwangalliGameplayShared.LISTINGS)
	lodgingFreeDays = 1, -- the first in-game day in the lodging is free for a new player
	firstRentSuggestion = "301", -- the realty app highlights this unit first
	tourMinutes = 5, -- tour pass length (real minutes)
	tourCooldownSeconds = 30,
	moveCooldownSeconds = 120, -- between two contracts (no flip spam)
}

-------------------------------------------------------------------------------------------------
-- TEST (owner: homes_econ): test balance kept SEPARATE from the real cash / bank (spec §7)
-------------------------------------------------------------------------------------------------
LC.TEST = {
	enabled = "auto", -- "auto": on in Roblox Studio (RunService:IsStudio()) and in the HTML studio
	--                   (workspace attribute GwWebStudio = true, fallback JobId prefix "gw-"); off on live
	--                   servers unless the player's UserId is in allowUserIds. true / false force it.
	balance = 100000000, -- 1억원 test wallet per player
	allowUserIds = {}, -- live-server testers (UserIds)
	badge = "테스트 잔액",
	-- test purchases are flagged test = true in the save; on a live server (TEST off) a load drops them
	purgeOnLive = true,
}

-------------------------------------------------------------------------------------------------
-- INCOME (owner: homes_econ): the common income interface for other sessions (§E)
-------------------------------------------------------------------------------------------------
LC.INCOME = {
	-- source id -> { label (ledger text), maxPerCall, maxPerDay (per player, in-game day) }
	sources = {
		job = { label = "알바 급여", maxPerCall = 200000, maxPerDay = 2000000 },
		npc_reward = { label = "NPC 사례금", maxPerCall = 100000, maxPerDay = 500000 },
		quest = { label = "퀘스트 보상", maxPerCall = 300000, maxPerDay = 1000000 },
		sale = { label = "판매 대금", maxPerCall = 5000000, maxPerDay = 20000000 },
		event = { label = "이벤트 보상", maxPerCall = 500000, maxPerDay = 1000000 },
		misc = { label = "기타 수입", maxPerCall = 50000, maxPerDay = 200000 },
	},
	defaultAccount = "bank", -- wages go to the bank (G convention); "cash" allowed per call
	ridTtl = 300, -- seconds a request id is remembered (no double credit on retries)
}

-------------------------------------------------------------------------------------------------
-- PARKING (owner: homes_econ)
-------------------------------------------------------------------------------------------------
LC.PARKING = {
	callCooldown = 20, -- seconds between two "내 차 꺼내기"
	visitorMinutes = 30, -- visitor stall P7 reservation length
}

-------------------------------------------------------------------------------------------------
-- ACCESS (owner: systems)
-------------------------------------------------------------------------------------------------
LC.ACCESS = {
	publicFloors = { [1] = true, [2] = true }, -- elevator buttons / stair doors open to everyone
	publicHours = { 9, 22 }, -- clock range when the 공동현관 opens for everyone (2F shops / 1F restrooms)
	guestPassMinutes = 30, -- a visitor let in by a resident (intercom / doorbell / invite)
	buildingPassMinutes = 10, -- building-only pass after the 공동현관 intercom
	doorAutoClose = 6, -- seconds a unit / room door stays open after use (door closer); 0 = stays open
	interiorAutoClose = 0, -- interior room doors stay where you leave them
	ringTimeout = 20, -- seconds a doorbell / intercom ring waits for an answer
	ringCooldown = 6,
	kickToCorridor = true, -- a player found inside a unit without the right is moved out (exploit guard)
	guardInterval = 0.5, -- seconds between server checks of who is inside claimed units
}

-------------------------------------------------------------------------------------------------
-- ELEVATOR (owner: systems)
-------------------------------------------------------------------------------------------------
LC.ELEVATOR = {
	speed = 8, -- studs/s cruise (2.4 m/s)
	accel = 5, -- studs/s^2
	doorTime = 1.4, -- seconds to open / close
	dwellHall = 3.5, -- seconds open after a hall call stop
	dwellCar = 2.5, -- seconds open after a car call stop
	dwellExtendOnHold = 2.0, -- each "open" press / sensor trip adds this
	reopenMax = 4, -- sensor reopens before a slow "nudge" close
	nudgeDoorTime = 3.0, -- slow close after reopenMax (sensor still reopens if a body is IN the doorway)
	idleParkLevel = 1, -- park at 1F after idleParkSeconds without calls (0 = stay)
	idleParkSeconds = 90,
	restrictedFloors = true, -- 3F-9F buttons only for residents / pass holders (LivingAccess)
	riderCarry = true, -- client carries its own character with the locally moved car (contract §B.5)
	maxRiders = 8,
}

-------------------------------------------------------------------------------------------------
-- FIXTURES (owner: systems)
-------------------------------------------------------------------------------------------------
LC.FIXTURES = {
	reach = 9, -- studs from the character to use a fixture (server check)
	waterAutoOff = 20, -- faucets / showers turn themselves off after this many seconds
	bathFillSeconds = 25,
	cooktopAutoOff = 600,
	tvChannels = {
		{ id = "news", name = "광안 뉴스 24", color = { 30, 60, 120 } },
		{ id = "weather", name = "부산 날씨", color = { 40, 120, 180 } },
		{ id = "drama", name = "주말 드라마", color = { 120, 40, 70 } },
		{ id = "sports", name = "프로야구 중계", color = { 30, 110, 60 } },
		{ id = "music", name = "뮤직 채널", color = { 90, 40, 130 } },
	},
	tvAutoOff = 0, -- 0 = stays on until turned off or the owner leaves the server
	sitCooldown = 0.6,
}

-------------------------------------------------------------------------------------------------
-- LIGHTING (owner: systems; decor reads the moods)
-------------------------------------------------------------------------------------------------
LC.LIGHTING = {
	maxPerRoom = 4,
	maxShadowedPerUnit = 1, -- only the main light of the main room casts shadows
	defaultOnAtNight = true, -- vacant / staging units: lights follow the NightWindows schedule
	moods = { -- decor's "lighting mood" per room: colour + brightness multiplier (HS.LIGHTS ids reused)
		warm = { color = { 255, 214, 160 }, brightness = 1.0, label = "따뜻한 전구색" },
		neutral = { color = { 255, 238, 214 }, brightness = 1.05, label = "주백색" },
		cool = { color = { 236, 244, 255 }, brightness = 1.1, label = "주광색" },
		amber = { color = { 255, 176, 96 }, brightness = 0.7, label = "무드 앰버" },
		violet = { color = { 190, 160, 255 }, brightness = 0.6, label = "네온 바이올렛" },
	},
}

-------------------------------------------------------------------------------------------------
-- FOOTSTEPS (owner: systems): Humanoid.FloorMaterial -> pitch / volume of the default Running sound
-- (rbxasset://sounds/action_footsteps_plastic.mp3 is the only footstep asset; see NEEDED EXTERNAL ASSETS)
-------------------------------------------------------------------------------------------------
LC.FOOTSTEPS = {
	WoodPlanks = { pitch = 0.92, volume = 0.55 },
	Wood = { pitch = 0.92, volume = 0.55 },
	CeramicTiles = { pitch = 1.18, volume = 0.6 },
	Marble = { pitch = 1.22, volume = 0.6 },
	Granite = { pitch = 1.12, volume = 0.6 },
	Slate = { pitch = 1.1, volume = 0.6 },
	Concrete = { pitch = 1.0, volume = 0.55 },
	Pavement = { pitch = 1.0, volume = 0.55 },
	Carpet = { pitch = 0.8, volume = 0.22 },
	Fabric = { pitch = 0.8, volume = 0.22 },
	Metal = { pitch = 1.3, volume = 0.5 },
	DiamondPlate = { pitch = 1.3, volume = 0.55 },
	SmoothPlastic = { pitch = 1.05, volume = 0.45 },
	default = { pitch = 1.0, volume = 0.5 },
}

-------------------------------------------------------------------------------------------------
-- DECOR (owner: decor)
-------------------------------------------------------------------------------------------------
LC.DECOR = {
	grids = { 0.5, 1.0, 2.0 }, -- snap steps offered (studs)
	gridDefault = 0.5,
	rotSteps = { 15, 45, 90 }, -- rotation steps offered (degrees)
	rotDefault = 45,
	placedCap = 120, -- placed items per home (tower units)
	partCap = 1500, -- parts of placed items per home (mobile budget)
	lightsCap = 3, -- real Light instances placed items may add per home
	undoDepth = 20,
	overlapMax = 0.35, -- HS.DECOR.OVERLAP_MAX
	wallGap = 0.05, -- wall items sit this far off the wall face
	maxHeightAboveFloor = 9.0, -- nothing above the ceiling underside (residential clear height 9.3)
	freshRefundSeconds = 600, -- undo / sell within 10 min of buying refunds 100 %
	pathWidth = 3.6, -- minimum free path kept through hall rooms and from every door
	finishTenantAllowed = false, -- tenants cannot change wallpaper / flooring (원상복구)
	previewValid = { 90, 220, 140 }, -- ghost colours
	previewInvalid = { 235, 80, 80 },
	-- placement kinds per catalog item come from GwangalliHomesShared.placeKind (floor | wall | rug | small);
	-- decor adds "ceiling" (ceiling lights) and maps "small" -> "table" (tabletop on a placed table / desk / shelf / counter)
}

-------------------------------------------------------------------------------------------------
-- SHOPS (owner: shops)
-------------------------------------------------------------------------------------------------
LC.SHOPS = {
	hours = { -- clock open..close (closed shops lock their doors for non-staff, lights dim)
		["1F-A"] = { 8, 23 },
		["1F-B"] = { 0, 24 }, -- 24h
		["1F-C"] = { 9, 20 },
		["2F-A"] = { 11, 22 },
		["2F-B"] = { 9, 19 },
	},
}

-------------------------------------------------------------------------------------------------
-- Helpers (pure)
-------------------------------------------------------------------------------------------------
function LC.round100(v: number): number
	return math.floor(v / 100 + 0.5) * 100
end

function LC.offer(unitId: string): any
	return LC.UNITS[unitId]
end

function LC.upkeepPerDay(unitId: string): number
	local o = LC.UNITS[unitId]
	if not o or not o.buy then
		return 0
	end
	return LC.round100(o.buy.price * LC.UPKEEP_RATE)
end

-- market value of an owned unit after `days` in-game days of ownership
function LC.valueAfter(unitId: string, purchasePrice: number?, days: number): number
	local o = LC.UNITS[unitId]
	local base = purchasePrice or (o and o.buy and o.buy.price) or 0
	local g = LC.GROWTH
	local mult = math.min(g.homeValueCap, 1 + g.homeValuePerDay * math.max(0, days))
	return LC.round100(base * mult)
end

-- rent per day after `days` of tenancy
function LC.rentAfter(unitId: string, days: number): number
	local o = LC.UNITS[unitId]
	if not o or not o.rent then
		return 0
	end
	local r = LC.GROWTH.rentRaise
	local steps = math.floor(math.max(0, days) / r.everyDays)
	local mult = math.min(r.cap, (1 + r.rate) ^ steps)
	return LC.round100(o.rent.perDay * mult)
end

-- net-worth gate for buying a unit: returns required net worth
function LC.buyGate(unitId: string): number
	local g = LC.GROWTH
	if g.penthouseUnits[unitId] then
		return g.unlock.buyPenthouse
	elseif g.familyUnits[unitId] then
		return g.unlock.buyFamily
	end
	return g.unlock.buySmall
end

return LC
