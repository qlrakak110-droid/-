-- GwangalliTransitShared: shared data + pure helpers for GET AROUND + WEATHER (owner: transit_weather).
--   * 부산 도시철도 2호선 (Busan Metro Line 2) between 수영 · 광안 · 금련산 · 남천: street entrances (the
--     stairwells built by build/districts/roads_metro.luau), the station interiors (built on the client
--     at a "slot" high above the map, see LAYOUT), one timetable both sides compute from server time.
--   * 광안 바이크: public bicycle / kickboard racks, prices per 10 in-game minutes, the parts-built
--     bicycle and kickboard (the server welds them to the rider, the clients show docked ones).
--   * Weather: the server schedule's states (ReplicatedStorage attribute GwWeather = "clear" |
--     "cloudy" | "rain"), intensities, client look / particle caps; umbrellas (stands + the Tool).
-- Pure module: no instances at require time, nothing yields, safe on server and client (the bike /
-- umbrella builders create instances only when called).
--
-- ATTRIBUTES (single source of truth: T.Attr)
--   ReplicatedStorage  GwWeather (string), GwWeatherIntensity (0..1 target), GwWeatherSince (server time),
--                      GwWeatherNext (string), GwWeatherNextAt (server time), GwRoadWet (0..1, server:
--                      rises while it rains, dries afterwards), GwMetroOpen (bool)
--   Player             GwTransit (scene key, "" = street; see T.sceneKey), GwTransitSlot (number, 0 = none),
--                      GwRideGroup (riders in my car group), GwBike ("" | "bike" | "kick"),
--                      GwBikeUntil (server time the rental ends), GwBikeRack (rack id it came from)
--   Character          GwUmbrella (bool, holding an umbrella Tool), GwWet (0..1, server)
--   Folder ReplicatedStorage.GwangalliTransitState: attribute Rack_<id> = docked count per rack
-- REMOTES (ReplicatedStorage.GwangalliRemotes, created by the server module Transit):
--   TransitRequest  RemoteFunction (op, payload) -> {ok, code, msg, ...}
--   TransitEvent    RemoteEvent server -> client {kind = ...}
-- See docs/TRANSIT.md for the full contract and the hooks other owners can use.

local T = {}
T.VERSION = 1

T.Remote = { Request = "TransitRequest", Event = "TransitEvent" }
T.STATE_FOLDER = "GwangalliTransitState"
T.Attr = {
	Weather = "GwWeather",
	WeatherIntensity = "GwWeatherIntensity",
	WeatherSince = "GwWeatherSince",
	WeatherNext = "GwWeatherNext",
	WeatherNextAt = "GwWeatherNextAt",
	RoadWet = "GwRoadWet",
	MetroOpen = "GwMetroOpen",
	Transit = "GwTransit",
	TransitSlot = "GwTransitSlot",
	RideGroup = "GwRideGroup",
	Bike = "GwBike",
	BikeUntil = "GwBikeUntil",
	BikeRack = "GwBikeRack",
	Umbrella = "GwUmbrella",
	Wet = "GwWet",
	-- workspace debug hook (Studio / tests / live ops): set to "clear" | "cloudy" | "rain" | "storm"
	SetWeather = "GwangalliSetWeather",
}
T.Tags = {
	BikeModel = "GwBikeModel", -- the bike / kickboard welded to a rider or parked (Model)
	Umbrella = "GwUmbrellaTool", -- the umbrella Tool's canopy model (clients open / close it)
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
T.rgb = rgb

---------------------------------------------------------------------------------------------------
-- Clock (in-game) helpers: GwangalliShared publishes the anchor on workspace
---------------------------------------------------------------------------------------------------
-- In-game hours per real second (default day: 24 real minutes -> 1/60).
function T.clockRate(): number
	local r = workspace:GetAttribute("GwangalliClockRate")
	if type(r) == "number" and r > 0 and r == r then
		return r
	end
	return 1 / 60
end

-- Real seconds per in-game minute.
function T.secondsPerGameMinute(): number
	return (1 / 60) / T.clockRate()
end

function T.clockNow(): number
	local ws = workspace
	local t0 = ws:GetAttribute("GwangalliClockAnchorTime")
	local c0 = ws:GetAttribute("GwangalliClockAnchorClock")
	local rate = ws:GetAttribute("GwangalliClockRate")
	if type(t0) == "number" and type(c0) == "number" and type(rate) == "number" then
		return (c0 + (ws:GetServerTimeNow() - t0) * rate) % 24
	end
	return game:GetService("Lighting").ClockTime
end

function T.won(n: number): string
	local s = tostring(math.floor(math.abs(n) + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return (if n < 0 then "-" else "") .. out .. "원"
end

---------------------------------------------------------------------------------------------------
-- METRO: 부산 도시철도 2호선
---------------------------------------------------------------------------------------------------
T.LINE2 = rgb(129, 191, 72) -- Line 2 green (the roads builder's roundel colour)
T.LINE2_DARK = rgb(62, 124, 38)
T.FARE = 1550 -- 교통카드 1구간 (adult card fare). Paid at the entry gate, check card (bank) first.
T.OPEN_FROM = 5.5 -- in-game clock: first train 05:30
T.OPEN_TO = 0.5 -- last train leaves ~00:30 (the gates close; riders already inside can finish)

function T.metroOpenAt(clock: number): boolean
	return clock >= T.OPEN_FROM or clock < T.OPEN_TO
end

-- The stations on the map, west -> east (index = order along the line).
T.STATIONS = {
	{
		id = "suyeong",
		name = "수영",
		en = "Suyeong",
		hanja = "水營",
		num = "208",
		note = "3호선 환승",
		exits = { { id = "7", entrance = "suyeong_7", hint = "수영로 · 광안 방면" } },
	},
	{
		id = "gwangan",
		name = "광안",
		en = "Gwangan",
		hanja = "廣安",
		num = "209",
		exits = {
			{ id = "3", entrance = "gwangan_3", hint = "광안리해수욕장 · 광안로 방면" },
			{ id = "6", entrance = "gwangan_6", hint = "광안자이 · BNK부산은행 방면" },
		},
	},
	{
		id = "geumnyeonsan",
		name = "금련산",
		en = "Geumnyeonsan",
		hanja = "金蓮山",
		num = "210",
		exits = { { id = "1", entrance = "geumnyeonsan_1", hint = "광안리해수욕장 · 광남로 방면" } },
	},
	{
		id = "namcheon",
		name = "남천",
		en = "Namcheon",
		hanja = "南川",
		num = "211",
		exits = { { id = "3", entrance = "namcheon_3", hint = "KBS부산 · 삼익비치 방면" } },
	},
}
T.STATION_INDEX = {} :: { [string]: number }
for i, s in T.STATIONS do
	T.STATION_INDEX[s.id] = i
end
-- The whole of Line 2 for the route maps (our four stations are highlighted).
T.LINE_MAP = {
	{ "206", "센텀시티" },
	{ "207", "민락" },
	{ "208", "수영" },
	{ "209", "광안" },
	{ "210", "금련산" },
	{ "211", "남천" },
	{ "212", "경성대·부경대" },
	{ "213", "대연" },
	{ "214", "못골" },
}

-- Street entrances (measured from the built place: build/districts/roads_metro.luau). landing = the
-- tiled floor at the bottom of the stairs (top y = T.LANDING_Y), shutter = the rolling shutter plane at
-- its far end, dir = horizontal unit vector from the landing toward the shutter (down the stairs).
T.LANDING_Y = -2.3
T.ENTRANCES = {
	gwangan_3 = { station = "gwangan", exit = "3", model = "Metro_광안역_3번출구", landing = { -204.70, 817.01 }, shutter = { -199.96, 817.07 }, dir = { 1.000, 0.013 } },
	gwangan_6 = { station = "gwangan", exit = "6", model = "Metro_광안역_6번출구", landing = { -348.62, 887.98 }, shutter = { -353.42, 887.88 }, dir = { -1.000, -0.021 } },
	geumnyeonsan_1 = { station = "geumnyeonsan", exit = "1", model = "Metro_금련산역_1번출구", landing = { 1388.26, 759.00 }, shutter = { 1393.02, 758.59 }, dir = { 0.996, -0.085 } },
	namcheon_3 = { station = "namcheon", exit = "3", model = "Metro_남천역_3번출구", landing = { 3153.32, 512.21 }, shutter = { 3148.46, 513.16 }, dir = { -0.982, 0.191 } },
	suyeong_7 = { station = "suyeong", exit = "7", model = "Metro_수영역_7번출구", landing = { -2317.70, 727.12 }, shutter = { -2312.84, 727.81 }, dir = { 0.990, 0.141 } },
}
T.ENTRANCE_ORDER = { "suyeong_7", "gwangan_6", "gwangan_3", "geumnyeonsan_1", "namcheon_3" }
T.ENTRANCE_REACH = 9 -- studs from the landing centre to use the doors

-- Landing frame: origin on the landing floor centre, LookVector = down the stairs (toward the doors).
function T.entranceFrame(id: string): CFrame?
	local e = T.ENTRANCES[id]
	if not e then
		return nil
	end
	local p = Vector3.new(e.landing[1], T.LANDING_Y, e.landing[2])
	local d = Vector3.new(e.dir[1], 0, e.dir[2]).Unit
	return CFrame.lookAt(p, p + d)
end

-- The doorway plane (where the shutter hangs): origin at floor level in the middle of the doorway.
function T.doorFrame(id: string): CFrame?
	local e = T.ENTRANCES[id]
	if not e then
		return nil
	end
	local p = Vector3.new(e.shutter[1], T.LANDING_Y, e.shutter[2])
	local d = Vector3.new(e.dir[1], 0, e.dir[2]).Unit
	return CFrame.lookAt(p, p + d)
end

-- Where a player coming out of the station stands: on the landing, 1.5 studs in front of the doors,
-- facing up the stairs.
function T.exitStreetCFrame(id: string): CFrame?
	local f = T.doorFrame(id)
	if not f then
		return nil
	end
	local p = f.Position - f.LookVector * 2.2 + Vector3.new(0, 3.2, 0)
	return CFrame.lookAt(p, p - f.LookVector)
end

---------------------------------------------------------------------------------------------------
-- Station interior LAYOUT (local frame of a scene: origin on the platform floor centre, +X along the
-- tracks toward 남천 (east, direction +1), +Y up, +Z across). One template for every station, built
-- on the client at a slot origin (only the signage differs), so the server can validate positions.
---------------------------------------------------------------------------------------------------
local L = {}
L.PLAT_HALF_LEN = 78 -- island platform x in [-78, 78]
L.PLAT_HALF_W = 11 -- z in [-11, 11] (platform screen doors on both edges)
L.TRACK_Z = 16.2 -- track centrelines at z = +/-16.2 (dir +1 -> +Z, dir -1 -> -Z)
L.TRACK_DEPTH = 3.9 -- rail top below the platform floor
L.BOX_HALF_LEN = 128 -- station box x in [-128, 128] (tunnel mouths at the ends)
L.BOX_HALF_W = 22 -- z in [-22, 22]
L.CEIL_Y = 11 -- platform ceiling
L.CONC_Y = 14 -- concourse floor (slab 11..14)
L.CONC_CEIL = 25
L.CONC_X0 = 43 -- concourse room x in [43, 90]
L.CONC_X1 = 90
L.GATE_X = 60 -- gate line (paid side x < 60)
L.GATE_LANES = { -7.6, -4.2, -0.8, 2.6, 6.6 } -- lane centres (z); the last one is the wide lane
L.GATE_WIDE = 5
L.STAIR_X0 = 17.5 -- stairs from the platform (x = 17.5, y = 0) up to the concourse (x = 42.5, y = 14)
L.STAIR_X1 = 42.5
L.STAIR_Z = { -0.6, 5.6 } -- stairs z range
L.ESC_Z = { -5.6, -1.6 } -- up escalator z range
L.CAR_LEN = 46
L.CAR_GAP = 1.2
L.CARS = 3
L.CAR_W = 9.2
L.CAR_H = 7.8 -- interior height above the car floor (= platform level)
L.DOOR_OFFSETS = { -15, 0, 15 } -- door centres per car (x from the car centre)
L.DOOR_W = 4.4
L.TRAIN_LEN = L.CARS * L.CAR_LEN + (L.CARS - 1) * L.CAR_GAP
-- exits (portals at the end of short exit corridors in the unpaid concourse). slot 1: the far wall,
-- slot 2: the north side wall. spawn = where you appear when you come in from the street.
L.EXIT_PORTALS = {
	{ center = Vector3.new(L.CONC_X1 + 9, L.CONC_Y, -11), look = Vector3.new(1, 0, 0), spawn = Vector3.new(L.CONC_X1 - 2.5, L.CONC_Y + 3.2, -11), width = 7 },
	{ center = Vector3.new(76, L.CONC_Y, L.BOX_HALF_W + 9), look = Vector3.new(0, 0, 1), spawn = Vector3.new(76, L.CONC_Y + 3.2, L.BOX_HALF_W - 2.5), width = 7 },
}
T.LAYOUT = L

function T.carCenters(): { number }
	local out = {}
	local first = -L.TRAIN_LEN / 2 + L.CAR_LEN / 2
	for c = 1, L.CARS do
		out[c] = first + (c - 1) * (L.CAR_LEN + L.CAR_GAP)
	end
	return out
end

-- Door centres (x, local) along a stopped train, 1-based car / door numbers.
function T.doorCenters(): { { x: number, car: number, door: number } }
	local out = {}
	for c, cx in T.carCenters() do
		for d, off in L.DOOR_OFFSETS do
			table.insert(out, { x = cx + off, car = c, door = d })
		end
	end
	return out
end

-- Exit slot of an exit id at a station (1 or 2).
function T.exitSlot(stationId: string, exitId: string): number
	local s = T.STATIONS[T.STATION_INDEX[stationId] or 0]
	if s then
		for i, e in s.exits do
			if e.id == exitId then
				return math.min(i, #L.EXIT_PORTALS)
			end
		end
	end
	return 1
end

-- Slots: every station scene lives at a slot origin far above the map (homes use y = 4000).
-- Home slot k (1..#STATIONS) is the station's own; ride slots (1..RIDE_SLOTS) carry riders' trains
-- and the station copies they arrive at. Box extents ~260 x 44 x 40 studs; slots 800 apart.
T.SLOT_Y = 5600
T.SLOT_SPACING = 800
T.RIDE_SLOTS = 24
function T.homeSlotOrigin(stationIndex: number): CFrame
	return CFrame.new(-9000 + (stationIndex - 1) * T.SLOT_SPACING, T.SLOT_Y, -9600)
end
function T.rideSlotOrigin(slot: number): CFrame
	local i = slot - 1
	return CFrame.new(-9000 + (i % 6) * T.SLOT_SPACING, T.SLOT_Y, -8800 + (i // 6) * T.SLOT_SPACING)
end
-- slot number used in attributes: 0 = none, 1..N = ride slots, 100 + k = home slot of station k
function T.slotOrigin(slotId: number): CFrame?
	if slotId >= 100 and slotId < 100 + #T.STATIONS + 1 then
		return T.homeSlotOrigin(slotId - 100)
	elseif slotId >= 1 and slotId <= T.RIDE_SLOTS then
		return T.rideSlotOrigin(slotId)
	end
	return nil
end
-- Is a world position anywhere near the slot band (y within 120 of SLOT_Y)?
function T.inSlotBand(p: Vector3): boolean
	return math.abs(p.Y - T.SLOT_Y) < 140
end

-- Scene keys (player attribute GwTransit): "" street, "st:<station>:<slot>" in a station scene,
-- "ride:<slot>" on a train. Two players are in the same scene when their keys are equal.
function T.sceneKey(kind: string, a: any?, b: any?): string
	if kind == "station" then
		return "st:" .. tostring(a) .. ":" .. tostring(b)
	elseif kind == "ride" then
		return "ride:" .. tostring(a)
	end
	return ""
end
function T.parseScene(key: any): (string, any, any)
	if type(key) ~= "string" or key == "" then
		return "street", nil, nil
	end
	local st, slot = string.match(key, "^st:([%w_]+):(%d+)$")
	if st then
		return "station", st, tonumber(slot)
	end
	local r = string.match(key, "^ride:(%d+)$")
	if r then
		return "ride", tonumber(r), nil
	end
	return "street", nil, nil
end

---------------------------------------------------------------------------------------------------
-- TIMETABLE (server time). Trains run 수영 <-> 남천 (구간 운행): direction +1 = 남천행 (east),
-- -1 = 수영행 (west). Train n of a direction arrives at station i at arr(dir, n, i).
---------------------------------------------------------------------------------------------------
local TT = {}
TT.HEADWAY = 96 -- seconds between trains of one direction (an island platform sees one every ~48 s)
TT.RUN = 30 -- seconds of motion between two stations
TT.DWELL = 20 -- seconds standing at a station
TT.APPROACH = 9 -- the last seconds of a run (decelerating into the station)
TT.LEAVE = 9 -- the first seconds of a run (accelerating out)
TT.DIST = 260 -- studs covered in APPROACH / LEAVE (quadratic: top speed 2*DIST/APPROACH = 58 studs/s)
TT.OFFSET = { [1] = 7, [-1] = 55 }
TT.DOOR_OPEN_AT = 1.6 -- after arrival
TT.DOOR_MOVE = 1.6 -- seconds to open / close
TT.DOOR_CLOSE_AT = 3.4 -- before departure (closing starts)
T.TT = TT
T.TERMINAL = { [1] = #T.STATIONS, [-1] = 1 }
T.ORIGIN = { [1] = 1, [-1] = #T.STATIONS }

function T.hopIndex(dir: number, i: number): number
	return if dir == 1 then i - 1 else #T.STATIONS - i
end

function T.arr(dir: number, n: number, i: number): number
	return n * TT.HEADWAY + TT.OFFSET[dir] + T.hopIndex(dir, i) * (TT.RUN + TT.DWELL)
end

function T.dep(dir: number, n: number, i: number): number
	return T.arr(dir, n, i) + TT.DWELL
end

-- The train of `dir` that is standing at / next arriving at station i at time `now` (smallest n whose
-- departure is still ahead or now).
function T.nextTrain(dir: number, i: number, now: number): number
	local base = TT.OFFSET[dir] + T.hopIndex(dir, i) * (TT.RUN + TT.DWELL)
	return math.ceil((now - TT.DWELL - base) / TT.HEADWAY)
end

-- Seconds until the next arrival of `dir` at station i (0 while a train is standing there) and that
-- train's number; also whether it is the terminal (no boarding) and what is next after it.
function T.nextArrival(dir: number, i: number, now: number): (number, number)
	local n = T.nextTrain(dir, i, now)
	return math.max(0, T.arr(dir, n, i) - now), n
end

-- Train centre offset along the platform's +X (local studs, 0 = stopped at the platform) and the door
-- opening (0..1) of train (dir, n) at station i, or nil when it is not inside the station box.
function T.trainState(dir: number, n: number, i: number, now: number): (number?, number)
	local a = T.arr(dir, n, i)
	local d = a + TT.DWELL
	if now < a - TT.APPROACH or now > d + TT.LEAVE then
		return nil, 0
	end
	if now <= a then
		local r = (a - now) / TT.APPROACH
		return -dir * TT.DIST * r * r, 0
	end
	if now >= d then
		local r = (now - d) / TT.LEAVE
		return dir * TT.DIST * r * r, 0
	end
	local open = 0
	local t = now - a
	local tc = d - now
	if t >= TT.DOOR_OPEN_AT then
		open = math.clamp((t - TT.DOOR_OPEN_AT) / TT.DOOR_MOVE, 0, 1)
	end
	if tc <= TT.DOOR_CLOSE_AT then
		open = math.min(open, math.clamp((tc - (TT.DOOR_CLOSE_AT - TT.DOOR_MOVE)) / TT.DOOR_MOVE, 0, 1))
	end
	return 0, open
end

-- Speed (studs/s) of a train `t` seconds after it left a station (RUN-long hop: accelerate, cruise,
-- brake), and how far it is from the next stop's stopping point.
function T.hopSpeed(t: number): number
	local top = 2 * TT.DIST / TT.LEAVE
	if t <= 0 then
		return 0
	elseif t < TT.LEAVE then
		return top * t / TT.LEAVE
	elseif t < TT.RUN - TT.APPROACH then
		return top
	elseif t < TT.RUN then
		return top * (TT.RUN - t) / TT.APPROACH
	end
	return 0
end

function T.hopStations(dir: number, fromIndex: number): number?
	local j = fromIndex + dir
	if j < 1 or j > #T.STATIONS then
		return nil
	end
	return j
end

function T.directionName(dir: number): string
	return if dir == 1 then "남천행" else "수영행"
end
function T.directionTowards(dir: number, i: number): string
	local j = i + dir
	local s = T.STATIONS[j]
	if s then
		return s.name .. " 방면"
	end
	return T.directionName(dir)
end

---------------------------------------------------------------------------------------------------
-- 광안 바이크: bicycle + kickboard rental
---------------------------------------------------------------------------------------------------
T.BIKE = {
	bike = {
		name = "광안 바이크 자전거",
		short = "자전거",
		icon = "🚲",
		per10 = 200, -- won per 10 in-game minutes
		unlock = 0,
		speed = 31.3, -- WalkSpeed while riding (non-integer: the HUD sprint never mistakes it for its own)
		hipExtra = 0,
	},
	kick = {
		name = "광안 바이크 전동킥보드",
		short = "킥보드",
		icon = "🛴",
		per10 = 350,
		unlock = 500, -- 잠금 해제
		speed = 35.7,
		hipExtra = 0.5,
	},
}
T.BIKE_ORDER = { "bike", "kick" }
-- Rental plans (in-game minutes; billed per 10-minute block up front, unused full blocks refunded
-- when returned at a rack, +10 min top-ups while riding).
T.BIKE_PLANS = { 30, 60, 120 }
T.BIKE_MAX_MINUTES = 240
T.BIKE_REACH = 12 -- studs from a rack to rent / return
T.BIKE_WARN_MIN = 10 -- warn when this many in-game minutes are left
-- Racks: ground point (top of the paving), yaw (degrees: 0 = docks in a row along +X), slots.
T.RACKS = {
	{ id = "gwangan3", name = "광안역 3번 출구", pos = Vector3.new(-186, 6.5, 822), yaw = 0, slots = 8, kick = 3 },
	{ id = "plaza", name = "광안리 만남의 광장", pos = Vector3.new(-240, 6.5, 36), yaw = 0, slots = 8, kick = 3 },
	{ id = "geum1", name = "금련산역 1번 출구", pos = Vector3.new(1413, 6.58, 758), yaw = -5, slots = 6, kick = 2 },
	{ id = "millak", name = "민락수변공원", pos = Vector3.new(-3660, 6.5, -500), yaw = 0, slots = 8, kick = 3 },
}
T.RACK_INDEX = {} :: { [string]: number }
for i, r in T.RACKS do
	T.RACK_INDEX[r.id] = i
end
function T.rackFrame(r: any): CFrame
	return CFrame.new(r.pos) * CFrame.Angles(0, math.rad(r.yaw or 0), 0)
end
-- Dock k (1..slots) of a rack: ground frame, bike facing -Z of the frame (into the rack).
function T.dockFrame(r: any, k: number): CFrame
	local n = r.slots
	local x = (k - (n + 1) / 2) * 1.9
	return T.rackFrame(r) * CFrame.new(x, 0, 0.6)
end
function T.nearestRack(p: Vector3, reach: number?): (any?, number)
	local best, bd = nil, math.huge
	for _, r in T.RACKS do
		local d = (Vector3.new(r.pos.X, p.Y, r.pos.Z) - p).Magnitude
		if d < bd then
			best, bd = r, d
		end
	end
	if reach and bd > reach then
		return nil, bd
	end
	return best, bd
end
function T.bikeCost(kind: string, minutes: number): number
	local spec = T.BIKE[kind]
	if not spec then
		return 0
	end
	local blocks = math.ceil(minutes / 10)
	return spec.unlock + blocks * spec.per10
end

---------------------------------------------------------------------------------------------------
-- Part helpers for the builders below (plain Instance.new; the caller parents the result)
---------------------------------------------------------------------------------------------------
local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = false
	p.Parent = parent
	return p
end
T.part = part

local function weld(a: BasePart, b: BasePart): WeldConstraint
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
	return w
end

-- Cylinder whose axis runs from p0 to p1 (Roblox cylinders run along their X axis).
local function cylBetween(parent: Instance, name: string, p0: Vector3, p1: Vector3, d: number, color: Color3, mat: Enum.Material?): Part
	local mid = (p0 + p1) / 2
	local v = p1 - p0
	local len = v.Magnitude
	local x = v.Unit
	local up = if math.abs(x.Y) > 0.95 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0)
	local z = x:Cross(up).Unit
	local y = z:Cross(x).Unit
	return part(parent, name, Vector3.new(len, d, d), CFrame.fromMatrix(mid, x, y, z), color, mat, Enum.PartType.Cylinder)
end
T.cylBetween = cylBetween

-- Two WedgeParts forming the triangle (a, b, c) (the classic two-wedge construction).
function T.triangle(parent: Instance, name: string, a: Vector3, b: Vector3, c: Vector3, thickness: number, color: Color3, mat: Enum.Material?, transparency: number?): (WedgePart?, WedgePart?)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local cr = ac:Cross(ab)
	if cr.Magnitude < 1e-6 or bc.Magnitude < 1e-6 then
		return nil, nil
	end
	local right = cr.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local function wedge(size: Vector3, cf: CFrame): WedgePart
		local w = Instance.new("WedgePart")
		w.Name = name
		w.Size = size
		w.CFrame = cf
		w.Color = color
		w.Material = mat or Enum.Material.SmoothPlastic
		w.Transparency = transparency or 0
		w.TopSurface = Enum.SurfaceType.Smooth
		w.BottomSurface = Enum.SurfaceType.Smooth
		w.Anchored = false
		w.CanCollide = false
		w.CanTouch = false
		w.CanQuery = false
		w.Massless = true
		w.CastShadow = false
		w.Parent = parent
		return w
	end
	local w1 = wedge(Vector3.new(thickness, math.max(height, 0.01), math.max(math.abs(ab:Dot(back)), 0.01)), CFrame.fromMatrix((a + b) / 2, right, up, back))
	local w2 = wedge(Vector3.new(thickness, math.max(height, 0.01), math.max(math.abs(ac:Dot(back)), 0.01)), CFrame.fromMatrix((a + c) / 2, -right, up, -back))
	return w1, w2
end

---------------------------------------------------------------------------------------------------
-- Bicycle / kickboard builders. Local frame: origin on the ground under the rider's HumanoidRootPart,
-- forward = -Z, up = +Y. Returns {model, root, joints = {name -> Motor6D}, ...}. Every part is
-- Massless, CanCollide / CanTouch / CanQuery false, unanchored (welded to `root`); the caller anchors
-- `root` (rack / parked bikes) or joints it to the HumanoidRootPart (Motor6D "BikeRoot").
-- detail: "full" (riders, parked) | "low" (docked display bikes: fewer parts)
---------------------------------------------------------------------------------------------------
T.BIKE_COLORS = {
	frame = rgb(38, 196, 186), -- 광안 바이크 mint teal
	frame2 = rgb(244, 246, 248),
	dark = rgb(30, 32, 36),
	tyre = rgb(24, 24, 26),
	metal = rgb(196, 200, 206),
	saddle = rgb(36, 36, 40),
	basket = rgb(236, 238, 240),
	kick = rgb(46, 50, 58),
	lamp = rgb(255, 248, 220),
	reflector = rgb(230, 40, 40),
}
T.BIKE_GEOM = {
	bike = { wheelR = 1.1, rearZ = 0.85, frontZ = -2.65, bbY = 0.95, bbZ = -0.6, crank = 0.55, saddleY = 2.45, saddleZ = 0.25, barY = 3.3, barZ = -1.95, gripX = 0.9 },
	kick = { wheelR = 0.42, rearZ = 1.35, frontZ = -1.75, deckY = 0.5, deckZ0 = -1.3, deckZ1 = 1.15, barY = 3.55, barZ = -1.6, gripX = 0.85, frontFootZ = -0.55, backFootZ = 0.45 },
}

local function motor(name: string, p0: BasePart, p1: BasePart, c0: CFrame, c1: CFrame): Motor6D
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = p0
	m.Part1 = p1
	m.C0 = c0
	m.C1 = c1
	m.Parent = p0
	return m
end

-- Wheel assembly around a hub part (rotating about the hub's X axis = the bike's lateral axis).
local function wheel(model: Model, name: string, hubCF: CFrame, r: number, detail: string, C: any): Part
	local hub = part(model, name .. "Hub", Vector3.new(0.34, 0.34, 0.34), hubCF, C.metal, Enum.Material.Metal)
	if detail == "low" then
		local tyre = part(model, name .. "Tyre", Vector3.new(0.16, r * 2, r * 2), hubCF, C.tyre, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		weld(hub, tyre)
		return hub
	end
	-- octagon tyre + rim, three spokes bars (six spokes), valve dot
	local seg = 8
	local segLen = 2 * r * math.tan(math.pi / seg) + 0.04
	for k = 0, seg - 1 do
		local a = k * 2 * math.pi / seg
		local cf = hubCF * CFrame.Angles(a, 0, 0) * CFrame.new(0, r - 0.09, 0)
		local t = part(model, name .. "Tyre", Vector3.new(0.17, 0.18, segLen), cf, C.tyre, Enum.Material.SmoothPlastic)
		weld(hub, t)
	end
	for k = 0, 2 do
		local a = k * math.pi / 3
		local sp = part(model, name .. "Spoke", Vector3.new(0.05, (r - 0.15) * 2, 0.05), hubCF * CFrame.Angles(a, 0, 0), C.metal, Enum.Material.Metal)
		weld(hub, sp)
	end
	local rim = part(model, name .. "Rim", Vector3.new(0.06, (r - 0.2) * 2, (r - 0.2) * 2), hubCF, C.metal, Enum.Material.Metal, Enum.PartType.Cylinder)
	rim.Transparency = 0.82
	weld(hub, rim)
	return hub
end

function T.buildBike(kind: string, detail: string?): any
	local det = detail or "full"
	local C = T.BIKE_COLORS
	local model = Instance.new("Model")
	model.Name = if kind == "kick" then "광안바이크_킥보드" else "광안바이크_자전거"
	local joints: { [string]: Motor6D } = {}
	local out: any = { model = model, kind = kind, joints = joints }
	if kind == "kick" then
		local g = T.BIKE_GEOM.kick
		local root = part(model, "BikeRoot", Vector3.new(0.2, 0.2, 0.2), CFrame.new(0, 0.1, 0), C.kick)
		root.Transparency = 1
		model.PrimaryPart = root
		out.root = root
		local deckLen = g.deckZ1 - g.deckZ0
		local deck = part(model, "Deck", Vector3.new(0.62, 0.16, deckLen), CFrame.new(0, g.deckY - 0.08, (g.deckZ0 + g.deckZ1) / 2), C.kick, Enum.Material.Metal)
		weld(root, deck)
		local grip = part(model, "DeckGrip", Vector3.new(0.54, 0.02, deckLen - 0.2), CFrame.new(0, g.deckY + 0.01, (g.deckZ0 + g.deckZ1) / 2), rgb(20, 20, 22), Enum.Material.Sand)
		weld(root, grip)
		local stripe = part(model, "DeckStripe", Vector3.new(0.64, 0.05, deckLen - 0.1), CFrame.new(0, g.deckY - 0.12, (g.deckZ0 + g.deckZ1) / 2), C.frame, Enum.Material.Neon)
		weld(root, stripe)
		-- rear mudguard + brake, kickstand
		local guard = part(model, "RearGuard", Vector3.new(0.3, 0.08, 0.9), CFrame.new(0, g.wheelR * 2 + 0.05, g.rearZ) * CFrame.Angles(math.rad(-10), 0, 0), C.kick, Enum.Material.Metal)
		weld(root, guard)
		local tail = part(model, "TailLight", Vector3.new(0.22, 0.06, 0.06), CFrame.new(0, g.wheelR * 2 + 0.02, g.rearZ + 0.46), C.reflector, Enum.Material.Neon)
		weld(root, tail)
		local stand = part(model, "Kickstand", Vector3.new(0.06, 0.06, 0.6), CFrame.new(-0.34, 0.2, 0.2) * CFrame.Angles(math.rad(20), 0, 0), C.dark, Enum.Material.Metal)
		weld(root, stand)
		-- steering column (stem + bar + front wheel turn together)
		local steerCF = CFrame.new(0, g.deckY, g.barZ + 0.05)
		local steer = part(model, "SteerHub", Vector3.new(0.2, 0.2, 0.2), steerCF, C.kick)
		steer.Transparency = 1
		joints.Steer = motor("Steer", root, steer, root.CFrame:ToObjectSpace(steerCF), CFrame.new())
		local stem = cylBetween(model, "Stem", Vector3.new(0, g.deckY - 0.05, g.barZ + 0.1), Vector3.new(0, g.barY, g.barZ), 0.22, C.kick, Enum.Material.Metal)
		weld(steer, stem)
		local bar = cylBetween(model, "Handlebar", Vector3.new(-g.gripX - 0.1, g.barY, g.barZ), Vector3.new(g.gripX + 0.1, g.barY, g.barZ), 0.14, C.dark, Enum.Material.Metal)
		weld(steer, bar)
		for _, sx in { -1, 1 } do
			local gp = cylBetween(model, "Grip", Vector3.new(sx * (g.gripX - 0.2), g.barY, g.barZ), Vector3.new(sx * (g.gripX + 0.12), g.barY, g.barZ), 0.2, rgb(18, 18, 20), Enum.Material.Rubber)
			weld(steer, gp)
		end
		local display = part(model, "Display", Vector3.new(0.4, 0.06, 0.3), CFrame.new(0, g.barY + 0.08, g.barZ) * CFrame.Angles(math.rad(25), 0, 0), rgb(16, 18, 22), Enum.Material.Glass)
		weld(steer, display)
		local led = part(model, "DisplayLED", Vector3.new(0.28, 0.02, 0.16), CFrame.new(0, g.barY + 0.12, g.barZ) * CFrame.Angles(math.rad(25), 0, 0), C.frame, Enum.Material.Neon)
		weld(steer, led)
		local lamp = part(model, "HeadLamp", Vector3.new(0.26, 0.16, 0.08), CFrame.new(0, g.barY - 0.55, g.barZ - 0.14), C.lamp, Enum.Material.Neon)
		weld(steer, lamp)
		local bell = part(model, "Bell", Vector3.new(0.12, 0.16, 0.16), CFrame.new(-g.gripX + 0.32, g.barY + 0.12, g.barZ), C.metal, Enum.Material.Metal, Enum.PartType.Cylinder)
		weld(steer, bell)
		out.bell = bell
		local fork = part(model, "Fork", Vector3.new(0.12, g.wheelR + 0.3, 0.12), CFrame.new(0.2, g.wheelR + 0.05, g.frontZ + 0.05), C.kick, Enum.Material.Metal)
		weld(steer, fork)
		local fhubCF = CFrame.new(0, g.wheelR, g.frontZ)
		local fh = wheel(model, "FrontWheel", fhubCF, g.wheelR, "low", C)
		joints.WheelF = motor("WheelF", steer, fh, steerCF:ToObjectSpace(fhubCF), CFrame.new())
		local rhubCF = CFrame.new(0, g.wheelR, g.rearZ)
		local rh = wheel(model, "RearWheel", rhubCF, g.wheelR, "low", C)
		joints.WheelR = motor("WheelR", root, rh, root.CFrame:ToObjectSpace(rhubCF), CFrame.new())
		-- name plate on the stem
		local plate = part(model, "Plate", Vector3.new(0.3, 0.5, 0.04), CFrame.new(0, g.barY - 1.1, g.barZ - 0.13), C.frame, Enum.Material.SmoothPlastic)
		weld(steer, plate)
		out.wheelR = g.wheelR
		return out
	end

	local g = T.BIKE_GEOM.bike
	local root = part(model, "BikeRoot", Vector3.new(0.2, 0.2, 0.2), CFrame.new(0, 0.1, 0), C.frame)
	root.Transparency = 1
	model.PrimaryPart = root
	out.root = root
	local bb = Vector3.new(0, g.bbY, g.bbZ)
	local rearHub = Vector3.new(0, g.wheelR, g.rearZ)
	local seatTop = Vector3.new(0, g.saddleY - 0.35, g.saddleZ + 0.15)
	local head = Vector3.new(0, 2.55, g.barZ + 0.25)
	local headLow = Vector3.new(0, 1.85, g.barZ + 0.05)
	local F = C.frame
	-- step-through frame: down tube (low, curved as two pieces), seat tube, stays, head tube
	local pieces = {
		{ "DownTube", headLow, Vector3.new(0, 1.05, -0.95) },
		{ "DownTube2", Vector3.new(0, 1.05, -0.95), bb + Vector3.new(0, 0.05, 0) },
		{ "SeatTube", bb, seatTop },
		{ "ChainStay", bb, rearHub },
		{ "SeatStay", seatTop - Vector3.new(0, 0.25, -0.05), rearHub },
		{ "TopTube", head - Vector3.new(0, 0.35, 0), Vector3.new(0, 1.55, -0.45) },
	}
	for _, pc in pieces do
		local tube = cylBetween(model, pc[1], pc[2], pc[3], 0.2, F, Enum.Material.SmoothPlastic)
		weld(root, tube)
	end
	if det == "full" then
		for _, sx in { -0.16, 0.16 } do
			local cs = cylBetween(model, "ChainStayR", bb + Vector3.new(sx, 0, 0), rearHub + Vector3.new(sx, 0, 0), 0.1, F)
			weld(root, cs)
		end
		local guard = part(model, "ChainGuard", Vector3.new(0.08, 0.5, 1.7), CFrame.new(0.26, g.bbY + 0.02, (g.bbZ + g.rearZ) / 2), rgb(60, 64, 70), Enum.Material.SmoothPlastic)
		weld(root, guard)
		local rack = part(model, "RearRack", Vector3.new(0.7, 0.06, 1.2), CFrame.new(0, g.wheelR * 2 + 0.25, g.rearZ + 0.1), C.dark, Enum.Material.Metal)
		weld(root, rack)
		local rguard = part(model, "RearFender", Vector3.new(0.34, 0.06, 1.4), CFrame.new(0, g.wheelR * 2 + 0.08, g.rearZ + 0.25) * CFrame.Angles(math.rad(-12), 0, 0), F, Enum.Material.SmoothPlastic)
		weld(root, rguard)
		local refl = part(model, "Reflector", Vector3.new(0.24, 0.12, 0.04), CFrame.new(0, g.wheelR * 2 + 0.16, g.rearZ + 0.72), C.reflector, Enum.Material.Neon)
		weld(root, refl)
		local stand = part(model, "Kickstand", Vector3.new(0.07, 1.0, 0.07), CFrame.new(-0.3, 0.55, g.rearZ - 0.4) * CFrame.Angles(0, 0, math.rad(18)), C.dark, Enum.Material.Metal)
		weld(root, stand)
		local lock = part(model, "RingLock", Vector3.new(0.14, 0.5, 0.5), CFrame.new(0.22, g.wheelR + 0.55, g.rearZ - 0.3), C.dark, Enum.Material.Metal, Enum.PartType.Cylinder)
		weld(root, lock)
		local tag = part(model, "FrameTag", Vector3.new(0.05, 0.32, 0.9), CFrame.new(0.12, 1.25, -0.75) * CFrame.Angles(math.rad(-28), 0, 0), C.frame2, Enum.Material.SmoothPlastic)
		weld(root, tag)
	end
	-- seat post + saddle
	local post = cylBetween(model, "SeatPost", seatTop, Vector3.new(0, g.saddleY - 0.1, g.saddleZ + 0.05), 0.13, C.metal, Enum.Material.Metal)
	weld(root, post)
	local saddle = part(model, "Saddle", Vector3.new(0.62, 0.18, 0.95), CFrame.new(0, g.saddleY - 0.05, g.saddleZ), C.saddle, Enum.Material.Leather)
	weld(root, saddle)
	local saddleNose = part(model, "SaddleNose", Vector3.new(0.3, 0.14, 0.5), CFrame.new(0, g.saddleY - 0.04, g.saddleZ - 0.6), C.saddle, Enum.Material.Leather)
	weld(root, saddleNose)
	-- steering assembly (head tube axis tilted 18 degrees)
	local steerCF = CFrame.new(head) * CFrame.Angles(math.rad(18), 0, 0)
	local steer = part(model, "SteerHub", Vector3.new(0.24, 0.24, 0.24), steerCF, F)
	steer.Transparency = 1
	joints.Steer = motor("Steer", root, steer, root.CFrame:ToObjectSpace(steerCF), CFrame.new())
	local headTube = cylBetween(model, "HeadTube", headLow, head + Vector3.new(0, 0.2, 0.06), 0.26, F)
	weld(steer, headTube)
	local frontHub = Vector3.new(0, g.wheelR, g.frontZ)
	for _, sx in { -0.17, 0.17 } do
		local blade = cylBetween(model, "Fork", headLow + Vector3.new(sx, 0, 0), frontHub + Vector3.new(sx, 0, 0), 0.1, C.metal, Enum.Material.Metal)
		weld(steer, blade)
	end
	local stem = cylBetween(model, "Stem", head + Vector3.new(0, 0.15, 0.05), Vector3.new(0, g.barY - 0.05, g.barZ + 0.15), 0.14, C.metal, Enum.Material.Metal)
	weld(steer, stem)
	-- swept-back city handlebar: centre bar + two grips angled back
	local barMid = cylBetween(model, "Handlebar", Vector3.new(-0.5, g.barY, g.barZ), Vector3.new(0.5, g.barY, g.barZ), 0.12, C.metal, Enum.Material.Metal)
	weld(steer, barMid)
	for _, sx in { -1, 1 } do
		local sweep = cylBetween(model, "BarSweep", Vector3.new(sx * 0.5, g.barY, g.barZ), Vector3.new(sx * g.gripX, g.barY - 0.02, g.barZ + 0.35), 0.12, C.metal, Enum.Material.Metal)
		weld(steer, sweep)
		local gp = cylBetween(model, "Grip", Vector3.new(sx * (g.gripX - 0.12), g.barY - 0.02, g.barZ + 0.3), Vector3.new(sx * (g.gripX + 0.12), g.barY - 0.03, g.barZ + 0.42), 0.18, rgb(30, 30, 32), Enum.Material.Rubber)
		weld(steer, gp)
	end
	local bell = part(model, "Bell", Vector3.new(0.12, 0.2, 0.2), CFrame.new(-0.62, g.barY + 0.11, g.barZ + 0.05), rgb(230, 200, 60), Enum.Material.Metal, Enum.PartType.Cylinder)
	weld(steer, bell)
	out.bell = bell
	if det == "full" then
		local fguard = part(model, "FrontFender", Vector3.new(0.32, 0.06, 1.2), CFrame.new(0, g.wheelR * 2 + 0.08, g.frontZ - 0.15) * CFrame.Angles(math.rad(14), 0, 0), F, Enum.Material.SmoothPlastic)
		weld(steer, fguard)
		local lamp = part(model, "HeadLamp", Vector3.new(0.24, 0.22, 0.12), CFrame.new(0, g.wheelR * 2 + 0.55, g.frontZ - 0.55), C.lamp, Enum.Material.Neon)
		weld(steer, lamp)
	end
	-- front basket (public-bike style, with the 광안 바이크 plate)
	local bz = g.barZ - 0.85
	local by = g.barY - 0.65
	local bottom = part(model, "BasketBase", Vector3.new(1.15, 0.06, 0.85), CFrame.new(0, by - 0.35, bz), C.basket, Enum.Material.SmoothPlastic)
	weld(steer, bottom)
	if det == "full" then
		local sides = {
			{ Vector3.new(1.15, 0.7, 0.05), CFrame.new(0, by, bz - 0.42) },
			{ Vector3.new(1.15, 0.7, 0.05), CFrame.new(0, by, bz + 0.42) },
			{ Vector3.new(0.05, 0.7, 0.85), CFrame.new(-0.57, by, bz) },
			{ Vector3.new(0.05, 0.7, 0.85), CFrame.new(0.57, by, bz) },
		}
		for _, sd in sides do
			local s = part(model, "BasketSide", sd[1], sd[2], C.basket, Enum.Material.SmoothPlastic)
			s.Transparency = 0.15
			weld(steer, s)
		end
		local plate = part(model, "BasketPlate", Vector3.new(0.9, 0.36, 0.05), CFrame.new(0, by, bz - 0.46), F, Enum.Material.SmoothPlastic)
		weld(steer, plate)
		local sg = Instance.new("SurfaceGui")
		sg.Name = "Brand"
		sg.Face = Enum.NormalId.Front
		sg.CanvasSize = Vector2.new(180, 72)
		sg.LightInfluence = 0.6
		sg.MaxDistance = 60
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.Text = "광안 바이크"
		lbl.TextColor3 = Color3.new(1, 1, 1)
		lbl.TextScaled = true
		lbl.Font = Enum.Font.GothamBold
		lbl.Parent = sg
		sg.Parent = plate
	end
	-- wheels
	local fhubCF = CFrame.new(frontHub)
	local fh = wheel(model, "FrontWheel", fhubCF, g.wheelR, det, C)
	joints.WheelF = motor("WheelF", steer, fh, steerCF:ToObjectSpace(fhubCF), CFrame.new())
	local rhubCF = CFrame.new(rearHub)
	local rh = wheel(model, "RearWheel", rhubCF, g.wheelR, det, C)
	joints.WheelR = motor("WheelR", root, rh, root.CFrame:ToObjectSpace(rhubCF), CFrame.new())
	-- crank + pedals
	local crankCF = CFrame.new(bb)
	local crank = part(model, "Chainring", Vector3.new(0.08, 0.75, 0.75), crankCF * CFrame.new(0.24, 0, 0), C.metal, Enum.Material.Metal, Enum.PartType.Cylinder)
	local crankHub = part(model, "CrankHub", Vector3.new(0.5, 0.2, 0.2), crankCF, C.dark, Enum.Material.Metal)
	weld(crankHub, crank)
	joints.Crank = motor("Crank", root, crankHub, root.CFrame:ToObjectSpace(crankCF), CFrame.new())
	for _, side in { { "L", -1 }, { "R", 1 } } do
		local sx = side[2]
		-- arm points down at angle 0 for the right side, up for the left
		local dirY = if sx == 1 then -1 else 1
		local armEnd = bb + Vector3.new(sx * 0.32, dirY * g.crank, 0)
		local arm = cylBetween(model, "CrankArm" .. side[1], bb + Vector3.new(sx * 0.32, 0, 0), armEnd, 0.1, C.metal, Enum.Material.Metal)
		weld(crankHub, arm)
		local pedalCF = CFrame.new(armEnd + Vector3.new(sx * 0.2, 0, 0))
		local pedal = part(model, "Pedal" .. side[1], Vector3.new(0.4, 0.08, 0.3), pedalCF, C.dark, Enum.Material.Rubber)
		joints["Pedal" .. side[1]] = motor("Pedal" .. side[1], crankHub, pedal, crankCF:ToObjectSpace(pedalCF), CFrame.new())
	end
	out.wheelR = g.wheelR
	return out
end

---------------------------------------------------------------------------------------------------
-- UMBRELLAS
---------------------------------------------------------------------------------------------------
T.UMBRELLAS = {
	vinyl = { name = "투명 비닐우산", price = 5000, canopy = rgb(232, 240, 246), transparency = 0.45, frame = rgb(240, 240, 240), handle = rgb(250, 250, 250), material = Enum.Material.Glass },
	navy = { name = "튼튼한 장우산 (네이비)", price = 12000, canopy = rgb(32, 44, 86), transparency = 0, frame = rgb(60, 60, 64), handle = rgb(96, 62, 38), material = Enum.Material.Fabric },
	yellow = { name = "노랑 장우산", price = 12000, canopy = rgb(250, 204, 40), transparency = 0, frame = rgb(60, 60, 64), handle = rgb(40, 40, 44), material = Enum.Material.Fabric },
	check = { name = "체크무늬 장우산", price = 15000, canopy = rgb(168, 44, 52), transparency = 0, frame = rgb(60, 60, 64), handle = rgb(96, 62, 38), material = Enum.Material.Fabric, trim = rgb(236, 220, 190) },
}
T.UMBRELLA_ORDER = { "vinyl", "navy", "yellow", "check" }
-- Where umbrellas are sold: stands appear outside when it is cloudy / raining (편의점 앞 우산 통,
-- 지하철역 출구 앞 우산 노점). Ground point + yaw (the stand faces its LookVector).
T.STANDS = {
	{ id = "gw3", name = "광안역 3번 출구 우산 노점", kind = "cart", pos = Vector3.new(-194, 6.56, 812), yaw = 180 },
	{ id = "gw6", name = "광안역 6번 출구 우산 노점", kind = "cart", pos = Vector3.new(-357.5, 6.66, 898.5), yaw = 0 },
	{ id = "geum1", name = "금련산역 1번 출구 우산 노점", kind = "cart", pos = Vector3.new(1401, 6.5, 765), yaw = 180 },
	{ id = "plaza", name = "만남의 광장 우산 노점", kind = "cart", pos = Vector3.new(-255, 6.5, 37), yaw = 180 },
	{ id = "cvs1", name = "편의점 앞 우산 통 (광안로)", kind = "bucket", pos = Vector3.new(-298, 6.5, 300), yaw = 90 },
	{ id = "cvs2", name = "편의점 앞 우산 통 (해변)", kind = "bucket", pos = Vector3.new(-181, 6.5, 100), yaw = 180 },
	{ id = "sy7", name = "수영역 7번 출구 우산 노점", kind = "cart", pos = Vector3.new(-2301.8, 6.5, 727.8), yaw = 0 },
	{ id = "nc3", name = "남천역 3번 출구 우산 노점", kind = "cart", pos = Vector3.new(3143, 6.5, 515), yaw = 180 },
}
T.STAND_REACH = 12
T.STAND_SHOW_RADIUS = 260 -- clients build a stand within this distance of the camera

-- Builds the umbrella Tool (Handle = the shaft's grip). Open canopy parts carry the attribute
-- "Canopy" = true; the furled sleeve "Furled" = true (clients swap them by weather, locally).
function T.buildUmbrella(kind: string): Tool
	local spec = T.UMBRELLAS[kind] or T.UMBRELLAS.vinyl
	local tool = Instance.new("Tool")
	tool.Name = spec.name
	tool.ToolTip = "☔ " .. spec.name
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("GwUmbrellaKind", kind)
	local R, H = 2.9, 0.9 -- canopy radius, canopy rise
	local SHAFT = 3.6 -- grip -> canopy apex
	-- Handle: the lower shaft the hand holds (part Y axis = shaft axis)
	local handle = part(tool, "Handle", Vector3.new(0.16, 1.0, 0.16), CFrame.new(0, 0, 0), spec.handle, Enum.Material.SmoothPlastic)
	handle.Massless = true
	-- The hand holds the handle 0.3 above its bottom; the shaft goes up (tilted slightly back over the
	-- head by the Grip): see docs/TRANSIT.md
	tool.Grip = CFrame.new(0, -0.2, 0) * CFrame.Angles(math.rad(78), 0, 0)
	local base = handle.CFrame
	local function at(y: number): CFrame
		return base * CFrame.new(0, y, 0)
	end
	-- J hook under the hand
	local hook = cylBetween(tool, "Hook", at(-0.5).Position, at(-0.95).Position + Vector3.new(0, 0, 0.0), 0.18, spec.handle, Enum.Material.SmoothPlastic)
	weld(handle, hook)
	local hook2 = part(tool, "HookCurve", Vector3.new(0.18, 0.18, 0.5), at(-1.0) * CFrame.new(0, 0, 0.2), spec.handle, Enum.Material.SmoothPlastic)
	weld(handle, hook2)
	local hook3 = part(tool, "HookTip", Vector3.new(0.18, 0.32, 0.18), at(-0.88) * CFrame.new(0, 0, 0.42), spec.handle, Enum.Material.SmoothPlastic)
	weld(handle, hook3)
	local shaft = cylBetween(tool, "Shaft", at(0.45).Position, at(SHAFT + 0.25).Position, 0.08, spec.frame, Enum.Material.Metal)
	weld(handle, shaft)
	local apexCF = at(SHAFT)
	local apex = apexCF.Position
	local tip = cylBetween(tool, "Tip", apex, at(SHAFT + 0.5).Position, 0.1, spec.frame, Enum.Material.Metal)
	weld(handle, tip)
	tip:SetAttribute("Canopy", true)
	-- canopy: octagonal pyramid (8 panels x 2 wedges), ribs under it, a runner on the shaft
	local verts = {}
	for k = 0, 7 do
		local a = k * math.pi / 4 + math.pi / 8
		verts[k] = (apexCF * CFrame.new(math.cos(a) * R, -H, math.sin(a) * R)).Position
	end
	local container = Instance.new("Model")
	container.Name = "Canopy"
	container.Parent = tool
	container:AddTag(T.Tags.Umbrella)
	for k = 0, 7 do
		local a, b = verts[k], verts[(k + 1) % 8]
		local color = spec.canopy
		if spec.trim and k % 2 == 1 then
			color = spec.trim
		end
		local w1, w2 = T.triangle(container, "Panel", apex, a, b, 0.05, color, spec.material, spec.transparency)
		for _, w in { w1, w2 } do
			if w then
				w:SetAttribute("Canopy", true)
				weld(handle, w)
			end
		end
		local rib = cylBetween(container, "Rib", apex - (apexCF.UpVector * 0.06), a - (apexCF.UpVector * 0.06), 0.04, spec.frame, Enum.Material.Metal)
		rib:SetAttribute("Canopy", true)
		weld(handle, rib)
		local tipEnd = part(container, "RibTip", Vector3.new(0.08, 0.12, 0.08), CFrame.new(a), spec.frame, Enum.Material.Metal)
		tipEnd:SetAttribute("Canopy", true)
		weld(handle, tipEnd)
	end
	local runner = cylBetween(container, "Runner", at(SHAFT - 1.0).Position, at(SHAFT - 0.75).Position, 0.16, spec.frame, Enum.Material.Metal)
	runner:SetAttribute("Canopy", true)
	weld(handle, runner)
	-- furled: a slim sleeve around the upper shaft (hidden while open)
	local furled = cylBetween(container, "Furled", at(1.2).Position, at(SHAFT + 0.1).Position, 0.42, spec.canopy, spec.material)
	furled.Transparency = math.min(spec.transparency, 0.3)
	furled:SetAttribute("Furled", true)
	weld(handle, furled)
	-- drip emitter at the rim (clients enable it while it rains)
	local drip = Instance.new("Attachment")
	drip.Name = "Drip"
	drip.CFrame = handle.CFrame:ToObjectSpace(apexCF * CFrame.new(0, -H - 0.05, 0))
	drip.Parent = handle
	return tool
end

---------------------------------------------------------------------------------------------------
-- WEATHER
---------------------------------------------------------------------------------------------------
T.WEATHER_STATES = { clear = true, cloudy = true, rain = true }
T.WEATHER = {
	-- server schedule (real seconds): clear spells, a cloudy build-up, rain, a cloudy clearing
	clearMin = 900,
	clearMax = 1800,
	cloudyBefore = { 90, 150 },
	rainMin = 300,
	rainMax = 540,
	cloudyAfter = { 60, 120 },
	stormChance = 0.25, -- share of rains that turn into a downpour (intensity ~1, thunder at night)
	firstRainAfter = { 420, 900 }, -- the first rain of a fresh server comes within ~7-15 minutes
	intensity = { drizzle = 0.4, rain = 0.7, storm = 1.0 },
	wetRise = 1 / 90, -- GwRoadWet per second while raining (fully wet after ~1.5 min)
	wetDry = 1 / 240, -- per second after the rain (dry ~4 min later)
	-- client particle caps per quality tier (drops / s of the camera emitter, splash / s, puddles)
	tier = {
		low = { rate = 140, splash = 30, puddles = 5, ripples = false, close = false },
		saver = { rate = 70, splash = 0, puddles = 0, ripples = false, close = false },
		mid = { rate = 260, splash = 70, puddles = 9, ripples = true, close = true },
		high = { rate = 420, splash = 120, puddles = 12, ripples = true, close = true },
	},
	-- the look laid over GwangalliWorld/DayNight (deltas / multipliers at full rain)
	look = {
		brightnessMul = 0.62,
		exposureAdd = -0.18,
		atmDensityAdd = 0.16,
		atmHazeAdd = 1.6,
		atmColor = rgb(150, 156, 166),
		cloudCover = 0.92,
		cloudDensity = 0.72,
		cloudColor = rgb(116, 120, 128),
		gradeSat = -0.28,
		gradeBright = -0.04,
		gradeTint = rgb(214, 224, 238),
	},
	cloudyLook = 0.45, -- share of the rain look applied while "cloudy"
	-- built-in sounds only (replace with licensed ids if you have them)
	sounds = {
		rain = "rbxasset://sounds/action_falling.mp3", -- a whoosh noise, slowed + EQ -> steady rain hiss
		patter = "rbxasset://sounds/action_swim.mp3", -- splashy strokes, quiet + fast -> drops on the umbrella
		splash = "rbxasset://sounds/impact_water.mp3",
		thunder = "rbxasset://sounds/action_falling.mp3", -- slowed right down -> distant rumble
	},
}

function T.weatherNow(): (string, number)
	local rs = game:GetService("ReplicatedStorage")
	local w = rs:GetAttribute(T.Attr.Weather)
	local i = rs:GetAttribute(T.Attr.WeatherIntensity)
	if type(w) ~= "string" or not T.WEATHER_STATES[w] then
		w = "clear"
	end
	if type(i) ~= "number" or i ~= i then
		i = if w == "rain" then 0.7 else 0
	end
	return w, math.clamp(i, 0, 1)
end

---------------------------------------------------------------------------------------------------
-- Sounds (built-in only)
---------------------------------------------------------------------------------------------------
T.SOUNDS = {
	ping = "rbxasset://sounds/electronicpingshort.wav", -- chimes / beeps / card tap / bell (pitched)
	click = "rbxasset://sounds/clickfast.wav",
	swoosh = "rbxasset://sounds/swoosh.wav",
	rumble = "rbxasset://sounds/action_falling.mp3", -- slowed: train rumble / tunnel roar
	step = "rbxasset://sounds/action_footsteps_plastic.mp3",
}

---------------------------------------------------------------------------------------------------
-- Validation (development): returns a list of problems
---------------------------------------------------------------------------------------------------
function T.validate(): { string }
	local bad = {}
	for id, e in T.ENTRANCES do
		if not T.STATION_INDEX[e.station] then
			table.insert(bad, "entrance " .. id .. ": unknown station " .. tostring(e.station))
		end
		local d = Vector3.new(e.dir[1], 0, e.dir[2])
		if math.abs(d.Magnitude - 1) > 0.05 then
			table.insert(bad, "entrance " .. id .. ": dir not unit")
		end
	end
	for _, s in T.STATIONS do
		for _, x in s.exits do
			if not T.ENTRANCES[x.entrance] then
				table.insert(bad, "station " .. s.id .. " exit " .. x.id .. ": no entrance " .. tostring(x.entrance))
			end
		end
	end
	for dir, _ in TT.OFFSET do
		for i = 1, #T.STATIONS do
			local now = 1000
			local n = T.nextTrain(dir, i, now)
			if T.dep(dir, n, i) < now or T.dep(dir, n - 1, i) >= now then
				table.insert(bad, "nextTrain wrong for dir " .. dir .. " station " .. i)
			end
		end
	end
	if TT.LEAVE + TT.APPROACH > TT.RUN then
		table.insert(bad, "timetable: LEAVE + APPROACH > RUN")
	end
	return bad
end

return T
