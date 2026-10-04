--!nocheck
-- GwangalliGarageShared (GS): data + pure functions of the 정비소 / 중고차 system (docs/GARAGE.md).
-- Required by the server (GwangalliGameplay/Garage.luau), the drive system (GwangalliVehicles/Spawn,
-- GwangalliDrive/UI), the client (GwangalliGarage) and the Lune builder (build/venues/garage.luau:
-- prices on the board). Nothing here touches the DataModel at require time, so it loads in plain Lune.
--
--   local GS = require(ReplicatedStorage.GwangalliGarageShared)
--   GS.CATALOG[kind]                 label / glyph / blurb / new / used prices (6 kinds, generic names)
--   GS.price(kind, grade)            grade = "new" | "used"
--   GS.loanQuote(price)              할부: { down, principal, total, daily, days }
--   GS.repairCost(kind, cond)        정비비 by damage (0 when the car is fine)
--   GS.sellValue(car)                되팔기 60 % of what was paid
--   GS.band(cond) / GS.bandInfo(cond)  "good" | "worn" | "bad" | "dead" (+ label / colour / icon)
--   GS.plate(rand) / GS.newId(rand)  "부산12가 3456" style plate, record id (rand() -> [0, 1))
--   GS.sanitizeCars(raw) -> list     safe copy of d.cars (used by Garage.onLoaded; Profiles may call it too)
--   GS.paintParts(model) / GS.applyColor(model, color3) / GS.applyPlate(model, text)  model edits
--   GS.dirtColor(base, dirt)         body colour darkened by dirt 0..1 (client, no textures)
--
-- PROFILE (d.cars, server authoritative):
--   { id, kind, color (GS.COLORS id), plate, cond 0..100, dirt 0..1, bought (won paid), grade, t (unix),
--     studs (distance driven), loan = { remaining, daily, lastDay, missed } | nil, rental = { until } | nil }
-- Rental cars are 큐비 (compact) for one in-game day (G.DAY_SECONDS real seconds); they do not count toward
-- GS.MAX_CARS and only one can be active.
--
-- REMOTES (ReplicatedStorage.GwangalliRemotes, created by Garage.luau):
--   GarageRequest RemoteFunction (op, payload?) -> { ok, code?, message?, ... }
--     ops: list | quote {kind, grade, color, loan} | buy {kind, grade, color, loan} | sell {id} | rent
--          | testdrive {kind} | repair {id?} | wash | tow {id} | status
--   GarageEvent RemoteEvent server -> client { kind = "open" (display car prompt: kind, display model),
--     "zone" (zone = "service" | "wash" | nil, quote), "repair" (stage), "wash", "cars" (list changed),
--     "toast" }
-- ATTRIBUTES on a spawned owned car (Garage / Spawn write, everyone reads): GS.Attr.*

local GS = {}

GS.VERSION = 1
GS.NAME = "광안 오토 정비소 & 중고차"
GS.PLACE = "광안정비소" -- Destination DisplayName (quick travel / waypoint)

GS.Remotes = { Request = "GarageRequest", Event = "GarageEvent" }
GS.API = "GwangalliGarageAPI" -- ServerStorage BindableFunction (server only): Invoke(op, userId, ...)
GS.VEHICLES_API = "GwangalliVehiclesAPI" -- ServerStorage BindableFunction created by GwangalliVehicles/Spawn

GS.Tags = {
	Display = "GarageDisplayCar", -- showroom car Model (attribute GarageKind), NoDrive = true
	Zone = "GarageZone", -- invisible BasePart, attribute Zone = "service" | "wash"
	Lift = "GarageLift", -- Model: the 2-post lift (its "LiftArm*" parts + the car on it rise)
	LiftCar = "GarageLiftCar", -- the display car standing on the lift
	Brush = "GarageWashBrush", -- wash arch brushes (spun by the client while washing)
	Staff = "GarageStaff", -- static NPC rigs (attribute Role = owner | mechanic)
	LED = "GarageLED", -- "정비 중" LED sign part
	Spawn = "GarageSpawn", -- BasePart: where test-drive / towed cars appear (LookVector = heading)
	Desk = "GarageDesk", -- BasePart with a ProximityPrompt (attribute Kind = service | wash)
	Prompt = "GaragePrompt", -- invisible anchor beside a showroom car with the "구매 / 시승" prompt (attribute GarageKind)
	Turntable = "GarageTurntable", -- the disc under a showroom car (attribute GarageKind)
	RoutePoint = "GarageRoutePoint", -- invisible marker of the 시승 loop (attribute Index 1..n)
	Return = "GarageReturn", -- BasePart in front of the showroom: where a finished test driver stands
	Gantry = "GarageWashGantry", -- the moving wash arch (Model; its parts slide along the bay)
	Shop = "GarageShop", -- the venue root Model (attribute Place = GS.PLACE)
}

GS.Attr = {
	CarId = "DriveCarId", -- the d.cars record id
	Condition = "DriveCondition", -- 0..100
	Dirt = "DriveDirt", -- 0..1
	Plate = "DrivePlate", -- "부산12가 3456"
	Color = "DriveColor", -- Color3 of the body paint
	ColorId = "DriveColorId", -- GS.COLORS id
	Rental = "DriveRental", -- true on the rental 큐비
	TestDrive = "DriveTestDrive", -- unix time the test drive ends
	DisplayKind = "GarageKind", -- showroom car: its VehicleKind (also on the prompt anchor)
	ZoneKind = "Zone",
	Washing = "GarageWashing", -- true while the wash choreography runs on this car
	Repairing = "GarageRepairing",
	ShineUntil = "DriveShineUntil", -- unix time: freshly washed (clients add a little reflectance)
	JobKind = "DriveJobKind", -- SpawnJobVehicle kind ("parcel_truck" ...) on a job vehicle
	Owned = "DriveOwnedCar", -- true on a car spawned from d.cars (owner-only driver seat)
}

-- Server-only persistence of d.cars (Profiles.sanitize drops unknown keys, so the garage keeps its own
-- copy; when Profiles starts keeping raw.cars the profile copy wins, see Garage.onLoaded).
GS.STORE = "GwangalliGarage_v1"
GS.STORE_KEY = "u_"

-- Job vehicles (ServerStorage.GwangalliEvents.SpawnJobVehicle, docs/careers_contract.md). base = the
-- drivable kit kind it is cloned from; livery = body colour; box = a cargo box on the bed (parcel truck).
GS.JOB_VEHICLES = {
	parcel_truck = { base = "truck", label = "택배 탑차", rgb = { 236, 237, 236 }, box = { 214, 216, 220 }, boxText = "광안 택배" },
	police = { base = "sedan", label = "순찰차", rgb = { 240, 242, 242 }, stripe = { 30, 60, 140 } },
	swat = { base = "van", label = "특임대 차량", rgb = { 26, 28, 32 }, stripe = { 220, 180, 40 } },
	limo = { base = "luxury", label = "리무진", rgb = { 14, 15, 17 } },
	armored = { base = "suv", label = "방탄차", rgb = { 58, 62, 58 } },
}

GS.MAX_CARS = 3
GS.SELL_RATE = 0.6

-------------------------------------------------------------------------------------------------
-- Catalog. Prices are tuned against G.JOBS: one shift (about 6 minutes) pays about 2.8 x the
-- hourly wage (10,320원 at level 1) ~= 29,000원, so a 중고 큐비 (150,000원) is 5-6 shifts = 30-40 min
-- of 알바; a 신차 플래그십 (3,200,000원) is a long-term goal (about 110 shifts at level 1, ~70 at level 3).
-------------------------------------------------------------------------------------------------
GS.KIND_ORDER = { "compact", "sedan", "suv", "truck", "van", "luxury" }
-- Generic names only (no real brands / model names): the kit cars are modelled on common Korean
-- street cars, but the game never names them.
GS.CATALOG = {
	compact = { label = "큐비", full = "큐비 박스카", glyph = "🚙", blurb = "작고 귀여운 박스형 경차 · 첫 차로 딱", new = 390000, used = 150000, seats = 4, tag = "첫 차 추천" },
	sedan = { label = "미드 세단", full = "미드 세단", glyph = "🚗", blurb = "무난하고 편한 중형 세단", new = 780000, used = 320000, seats = 5 },
	suv = { label = "트레일 SUV", full = "트레일 SUV", glyph = "🚙", blurb = "사륜구동 · 넉넉한 실내", new = 980000, used = 420000, seats = 5 },
	truck = { label = "1톤 트럭", full = "든든 1톤 트럭", glyph = "🛻", blurb = "짐 싣는 무거운 1톤 트럭", new = 640000, used = 280000, seats = 3 },
	van = { label = "패밀리 밴", full = "패밀리 9인승 밴", glyph = "🚐", blurb = "9인승 · 친구들 다 태우는 밴", new = 1250000, used = 520000, seats = 9 },
	luxury = { label = "플래그십", full = "플래그십 세단", glyph = "🏎️", blurb = "가장 빠른 후륜 세단 · 드림카", new = 3200000, used = 1400000, seats = 5, tag = "드림카" },
}
GS.USED_COND = { 55, 80 } -- a 중고차 arrives with this much condition (uniform)
GS.GRADES = { new = "신차", used = "중고" }

-- 렌트: a 큐비 (box car) for one in-game day so new players can drive early.
GS.RENTAL = { kind = "compact", fee = 20000, seconds = 1440, label = "큐비 하루 렌트" }

-- 할부 (instalment): down payment now, the rest (+ interest) in equal daily charges from the bank.
-- Missed days (not enough money) are retried the next day; after `missLimit` misses the car is
-- repossessed (removed from d.cars, no refund). Every charge is a normal G.ledger entry.
GS.LOAN = { down = 0.3, rate = 0.05, days = 10, missLimit = 3, minPrice = 300000 }

-- 8 paint colours (ids are saved in the profile; rgb = the body paint).
GS.COLORS = {
	{ id = "white", name = "화이트", rgb = { 238, 239, 238 } },
	{ id = "black", name = "블랙", rgb = { 18, 19, 21 } },
	{ id = "silver", name = "실버", rgb = { 178, 182, 186 } },
	{ id = "grey", name = "그레이", rgb = { 96, 100, 104 } },
	{ id = "navy", name = "네이비", rgb = { 30, 48, 88 } },
	{ id = "red", name = "레드", rgb = { 150, 30, 34 } },
	{ id = "beige", name = "베이지", rgb = { 192, 182, 162 } },
	{ id = "mint", name = "민트", rgb = { 142, 170, 160 } },
}
GS.DEFAULT_COLOR = "white"

-------------------------------------------------------------------------------------------------
-- Condition (0..100). Keep the band thresholds equal to VS.Condition (GwangalliVehiclesShared), which
-- applies the physics effects in the controller; this table is the gameplay / UI side.
-------------------------------------------------------------------------------------------------
GS.COND = {
	max = 100,
	worn = 60, -- below: engine stutter (torque dips)
	bad = 30, -- below: top speed -40 %, smoke
	hitSpeed = 18, -- studs/s: relative speed a touch must exceed to count as a hard collision (~19 km/h)
	hitDebounce = 1, -- s between two hits on one car
	hitBase = 2, -- damage = hitBase + (speed - hitSpeed) * hitPerStud, capped
	hitPerStud = 0.3,
	hitMax = 15,
	wearStuds = 1200, -- -1 condition per this many studs driven (~360 m)
	dirtStuds = 3500, -- +1.0 dirt per this many studs (full dirt after ~1 km)
	dirtDark = 0.38, -- how much a fully dirty body is darkened toward the dust colour
}
GS.BANDS = {
	good = { id = "good", label = "양호", icon = "🟢", color = { 61, 220, 132 } },
	worn = { id = "worn", label = "점검 필요", icon = "🟡", color = { 255, 176, 32 } },
	bad = { id = "bad", label = "고장 직전", icon = "🟠", color = { 255, 110, 60 } },
	dead = { id = "dead", label = "엔진 정지", icon = "🔴", color = { 255, 80, 90 } },
}

GS.REPAIR = { rate = 0.08, min = 5000, seconds = 5.5 } -- 정비비 = new price x rate x damage share (>= min)
GS.WASH = { fee = 5000, happiness = 3, seconds = 3.2 }
GS.TOW = { fee = 15000 }
GS.TEST_DRIVE = { seconds = 60, cooldown = 45 }

-------------------------------------------------------------------------------------------------
-- Pure helpers
-------------------------------------------------------------------------------------------------
local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end
GS.isFinite = finite

local function round100(v: number): number
	return math.floor(v / 100 + 0.5) * 100
end
GS.round100 = round100

function GS.kindInfo(kind: any): any?
	return GS.CATALOG[kind]
end

function GS.price(kind: string, grade: string?): number?
	local c = GS.CATALOG[kind]
	if not c then
		return nil
	end
	return if grade == "used" then c.used else c.new
end

function GS.loanQuote(price: number): any
	local L = GS.LOAN
	local down = round100(price * L.down)
	local principal = price - down
	local total = round100(principal * (1 + L.rate))
	local daily = math.ceil(total / L.days / 100) * 100
	return { price = price, down = down, principal = principal, total = total, daily = daily, days = L.days }
end

function GS.canLoan(price: number): boolean
	return price >= GS.LOAN.minPrice
end

function GS.clampCond(v: any): number
	if not finite(v) then
		return GS.COND.max
	end
	return math.clamp(math.floor(v + 0.5), 0, GS.COND.max)
end

function GS.band(cond: any): string
	local c = GS.clampCond(cond)
	if c <= 0 then
		return "dead"
	elseif c < GS.COND.bad then
		return "bad"
	elseif c < GS.COND.worn then
		return "worn"
	end
	return "good"
end

function GS.bandInfo(cond: any): any
	return GS.BANDS[GS.band(cond)]
end

-- Hard collision damage for a relative speed (studs/s); 0 below the threshold.
function GS.hitDamage(speed: number): number
	local C = GS.COND
	if speed < C.hitSpeed then
		return 0
	end
	return math.min(C.hitMax, C.hitBase + (speed - C.hitSpeed) * C.hitPerStud)
end

function GS.repairCost(kind: string, cond: any): number
	local c = GS.CATALOG[kind]
	local damage = GS.COND.max - GS.clampCond(cond)
	if not c or damage <= 0 then
		return 0
	end
	return math.max(GS.REPAIR.min, round100(c.new * GS.REPAIR.rate * damage / GS.COND.max))
end

function GS.sellValue(car: any): number
	if type(car) ~= "table" or not finite(car.bought) then
		return 0
	end
	return round100(car.bought * GS.SELL_RATE)
end

function GS.colorEntry(id: any): any
	for _, c in GS.COLORS do
		if c.id == id then
			return c
		end
	end
	return GS.COLORS[1]
end

function GS.colorRGB(id: any): { number }
	return GS.colorEntry(id).rgb
end

-- Color3 for a colour id (Roblox only; the Lune builder uses colorRGB).
function GS.color3(id: any): any
	local rgb = GS.colorRGB(id)
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local HANGUL = { "가", "나", "다", "라", "마", "거", "너", "더", "러", "머", "버", "서", "어", "저", "고", "노", "도", "로", "모", "보", "소", "오", "조", "구", "누", "두", "루", "무", "부", "수", "우", "주" }
-- "부산12가 3456" (rand() -> [0, 1))
function GS.plate(rand: () -> number): string
	local a = 10 + math.floor(rand() * 90)
	local h = HANGUL[math.clamp(math.floor(rand() * #HANGUL) + 1, 1, #HANGUL)]
	local n = 1000 + math.floor(rand() * 9000)
	return string.format("부산%02d%s %04d", math.min(a, 99), h, math.min(n, 9999))
end

local ALNUM = "abcdefghjkmnpqrstuvwxyz23456789"
function GS.newId(rand: () -> number): string
	local out = { "c" }
	for _ = 1, 6 do
		local i = math.clamp(math.floor(rand() * #ALNUM) + 1, 1, #ALNUM)
		table.insert(out, string.sub(ALNUM, i, i))
	end
	return table.concat(out)
end

function GS.carLabel(car: any): string
	local c = car and GS.CATALOG[car.kind]
	local base = if c then c.label else "내 차"
	if car and car.rental then
		return base .. " (렌트)"
	end
	return base
end

-- Safe copy of a saved d.cars list (drops garbage, clamps numbers).
function GS.sanitizeCar(raw: any): any?
	if type(raw) ~= "table" or type(raw.id) ~= "string" or #raw.id > 16 or not GS.CATALOG[raw.kind] then
		return nil
	end
	local car: any = {
		id = raw.id,
		kind = raw.kind,
		color = GS.colorEntry(raw.color).id,
		plate = if type(raw.plate) == "string" and #raw.plate <= 24 then raw.plate else "부산00가 0000",
		cond = GS.clampCond(raw.cond),
		dirt = if finite(raw.dirt) then math.clamp(raw.dirt, 0, 1) else 0,
		bought = if finite(raw.bought) and raw.bought >= 0 then math.floor(raw.bought) else 0,
		grade = if raw.grade == "used" then "used" else "new",
		t = if finite(raw.t) then math.floor(raw.t) else 0,
		studs = if finite(raw.studs) and raw.studs >= 0 then math.floor(raw.studs) else 0,
	}
	if type(raw.loan) == "table" and finite(raw.loan.remaining) and raw.loan.remaining > 0 and finite(raw.loan.daily) and raw.loan.daily > 0 then
		car.loan = {
			remaining = math.floor(raw.loan.remaining),
			daily = math.floor(raw.loan.daily),
			lastDay = if finite(raw.loan.lastDay) then math.floor(raw.loan.lastDay) else 0,
			missed = if finite(raw.loan.missed) then math.clamp(math.floor(raw.loan.missed), 0, 99) else 0,
			total = if finite(raw.loan.total) then math.floor(raw.loan.total) else math.floor(raw.loan.remaining),
		}
	end
	if type(raw.rental) == "table" and finite(raw.rental["until"]) then
		car.rental = { ["until"] = math.floor(raw.rental["until"]) }
	end
	if raw.towed == true then
		car.towed = true -- towed to the 정비소 (engine dead); cleared by a repair
	end
	return car
end

function GS.sanitizeCars(raw: any): { any }
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	local seen = {}
	for _, r in raw do
		local car = GS.sanitizeCar(r)
		if car and not seen[car.id] then
			seen[car.id] = true
			table.insert(out, car)
			if #out >= GS.MAX_CARS + 1 then -- + one rental
				break
			end
		end
	end
	return out
end

function GS.owned(cars: { any }): number
	local n = 0
	for _, c in cars or {} do
		if not c.rental then
			n += 1
		end
	end
	return n
end

function GS.findCar(cars: { any }, id: any): (any?, number?)
	for i, c in cars or {} do
		if c.id == id then
			return c, i
		end
	end
	return nil, nil
end

-- What the client sees (no server-only fields).
function GS.carView(car: any, now: number?): any
	local c = GS.CATALOG[car.kind] or {}
	local v: any = {
		id = car.id,
		kind = car.kind,
		label = c.label or car.kind,
		glyph = c.glyph or "🚗",
		color = car.color,
		plate = car.plate,
		cond = car.cond,
		dirt = car.dirt,
		band = GS.band(car.cond),
		grade = car.grade,
		bought = car.bought,
		sell = GS.sellValue(car),
		repair = GS.repairCost(car.kind, car.cond),
		studs = car.studs,
	}
	if car.loan then
		v.loan = { remaining = car.loan.remaining, daily = car.loan.daily, missed = car.loan.missed, total = car.loan.total }
	end
	if car.rental then
		v.rental = true
		v.rentalLeft = math.max(0, car.rental["until"] - (now or 0))
	end
	if car.towed then
		v.towed = true
	end
	v.callable, v.why = GS.callable(car, now)
	return v
end

-- Can this record be called onto the road? -> ok, reason (Korean) when not.
function GS.callable(car: any, now: number?): (boolean, string?)
	if type(car) ~= "table" then
		return false, "없는 차예요"
	end
	if car.rental and now and car.rental["until"] <= now then
		return false, "렌트 기간이 끝났어요"
	end
	if GS.clampCond(car.cond) <= 0 then
		if car.towed then
			return false, "정비소에 견인돼 있어요 · 정비 후 탈 수 있어요"
		end
		return false, "엔진이 멈췄어요 · 견인해서 정비하세요"
	end
	return true, nil
end

-------------------------------------------------------------------------------------------------
-- Model helpers (run on the server when a car spawns, and on the client for previews)
-------------------------------------------------------------------------------------------------
local function near(a: any, b: any): boolean
	return math.abs(a.R - b.R) < 0.006 and math.abs(a.G - b.G) < 0.006 and math.abs(a.B - b.B) < 0.006
end

local function insideNamed(part: any, name: string, root: any): boolean
	local node = part.Parent
	while node and node ~= root do
		if node.Name == name then
			return true
		end
		node = node.Parent
	end
	return false
end

-- The body paint parts of a kit car: every part sharing the colour of the reference body panel
-- ("BodySide", else "CabSide" on the Porter, else "Hood"), outside the Interior sub-model.
function GS.paintParts(model: any): ({ any }, any?)
	local ref = model:FindFirstChild("BodySide", true) or model:FindFirstChild("CabSide", true) or model:FindFirstChild("Hood", true)
	if not ref or not ref:IsA("BasePart") then
		return {}, nil
	end
	local base = ref.Color
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and near(d.Color, base) and not insideNamed(d, "Interior", model) then
			table.insert(out, d)
		end
	end
	return out, base
end

-- Recolours the body paint and records the colour on the model. Returns the recoloured parts.
function GS.applyColor(model: any, color: any, colorId: string?): { any }
	local parts = GS.paintParts(model)
	for _, p in parts do
		p.Color = color
	end
	model:SetAttribute(GS.Attr.Color, color)
	if colorId then
		model:SetAttribute(GS.Attr.ColorId, colorId)
	end
	return parts
end

-- Writes the plate text on both plates (SurfaceGui TextLabels) and records it on the model.
function GS.applyPlate(model: any, text: string)
	for _, name in { "PlateFront", "PlateRear" } do
		local p = model:FindFirstChild(name, true)
		if p then
			for _, d in p:GetDescendants() do
				if d:IsA("TextLabel") then
					d.Text = text
				end
			end
		end
	end
	model:SetAttribute(GS.Attr.Plate, text)
end

-- Body colour darkened by dirt (0..1): lerp toward a dusty brown, no textures.
function GS.dirtColor(base: any, dirt: number): any
	local k = math.clamp(dirt or 0, 0, 1) * GS.COND.dirtDark
	return base:Lerp(Color3.fromRGB(96, 86, 72), k)
end

function GS.formatWon(n: any): string
	local v = math.floor(tonumber(n) or 0)
	local s = tostring(math.abs(v))
	local out = ""
	while #s > 3 do
		out = "," .. string.sub(s, -3) .. out
		s = string.sub(s, 1, -4)
	end
	return (if v < 0 then "-" else "") .. s .. out .. "원"
end

return GS
