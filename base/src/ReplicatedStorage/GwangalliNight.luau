-- GwangalliNight: the CLUB OCEAN night "hype" (0..1) from the in-game clock, the crowd / street
-- budgets that follow it, and the club entrance lookup (owner: npc_ambient).
--
--   local Night = require(ReplicatedStorage.GwangalliNight)
--   Night.hype(clock?)            -> 0..1   ~0 by day, rising from 18:00, 0.6 at 21:00, 1.0 from 22:30
--                                          to 02:00, back to 0 at 05:00 (piecewise linear, Night.CURVE)
--   Night.clock()                 -> the in-game clock 0..24 (GwangalliShared.clockNow on a client /
--                                    server, Lighting.ClockTime as a fallback, 12 outside Roblox)
--   Night.phase(clock?)           -> "day" (05-17) | "evening" (17-21) | "night" (21-02) | "late" (02-05)
--   Night.isLureTime(clock?)      -> true 17:00-23:30: people on the street talk the player into the club
--   Night.crowdVisible(hype)      -> club crowd rigs to show: 10 + 30 * hype (rounded)
--   Night.streetScale(hype)       -> 1 - 0.6 * hype (street pedestrians away from the club)
--   Night.streetCap(base, hype, nearClub?) -> pedestrian cap: base near the club, base * streetScale elsewhere
--   Night.clubEntrance()          -> { door, rope, tail, head, hangCenter: Vector3, queue = {Vector3}
--                                    (head -> tail), hang = {Vector3}, queueFace: Vector3,
--                                    staticQueue, doorNode, tailNode } or nil (from GwangalliNav, cached;
--                                    falls back to the "CLUB OCEAN 광안" Destination part)
--   Night.clubDistance(pos)       -> flat studs from pos to the club door (math.huge when unknown)
--   Night.NEAR_CLUB               -> studs from the door that count as "at the club" for the budgets
-- Pure at require time (no instances, no yields); Lune tests can load it and call hype / phase /
-- crowdVisible / streetCap without any Roblox globals.

local Night = {}

Night.VERSION = 1
Night.NEAR_CLUB = 260

-- { clock, hype } knots, linear in between (00:00 and 24:00 are the same point)
Night.CURVE = {
	{ 0, 1 },
	{ 2, 1 },
	{ 5, 0 },
	{ 18, 0 },
	{ 21, 0.6 },
	{ 22.5, 1 },
	{ 24, 1 },
}

local CURVE = Night.CURVE

local function isNum(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- In-game clock -----------------------------------------------------------------------------------
local sharedMod: any = nil
local sharedTried = 0
local function shared(): any
	if sharedMod then
		return sharedMod
	end
	local t = os.clock()
	if t < sharedTried then
		return nil
	end
	sharedTried = t + 5
	local ok, res = pcall(function()
		local g: any = game
		local rs = g:GetService("ReplicatedStorage")
		local m = rs:FindFirstChild("GwangalliShared")
		if m and m:IsA("ModuleScript") then
			return require(m) :: any
		end
		return nil
	end)
	if ok and type(res) == "table" then
		sharedMod = res
	end
	return sharedMod
end

function Night.clock(): number
	local S = shared()
	if S and type(S.clockNow) == "function" then
		local ok, c = pcall(S.clockNow)
		if ok and isNum(c) then
			return c % 24
		end
	end
	local ok, c = pcall(function()
		local g: any = game
		return g:GetService("Lighting").ClockTime
	end)
	if ok and isNum(c) then
		return c % 24
	end
	return 12
end

-- Hype -----------------------------------------------------------------------------------------------
function Night.hype(clock: number?): number
	local c = if isNum(clock) then (clock :: number) % 24 else Night.clock()
	for i = 2, #CURVE do
		local a, b = CURVE[i - 1], CURVE[i]
		if c <= b[1] then
			local span = b[1] - a[1]
			if span <= 0 then
				return b[2]
			end
			return a[2] + (b[2] - a[2]) * (c - a[1]) / span
		end
	end
	return CURVE[#CURVE][2]
end

function Night.phase(clock: number?): string
	local c = if isNum(clock) then (clock :: number) % 24 else Night.clock()
	if c >= 5 and c < 17 then
		return "day"
	elseif c >= 17 and c < 21 then
		return "evening"
	elseif c >= 21 or c < 2 then
		return "night"
	end
	return "late"
end

function Night.isLureTime(clock: number?): boolean
	local c = if isNum(clock) then (clock :: number) % 24 else Night.clock()
	return c >= 17 and c < 23.5
end

function Night.crowdVisible(hype: number): number
	local h = if isNum(hype) then math.clamp(hype, 0, 1) else 0
	return math.floor(10 + 30 * h + 0.5)
end

function Night.streetScale(hype: number): number
	local h = if isNum(hype) then math.clamp(hype, 0, 1) else 0
	return 1 - 0.6 * h
end

function Night.streetCap(base: number, hype: number, nearClub: boolean?): number
	if nearClub then
		return base
	end
	return math.max(1, math.floor(base * Night.streetScale(hype) + 0.5))
end

-- Club entrance ---------------------------------------------------------------------------------------
local entrance: any = nil
local entranceTried = 0

local function v3(t: any): any
	if type(t) == "table" and isNum(t[1]) and isNum(t[2]) and isNum(t[3]) then
		return Vector3.new(t[1], t[2], t[3])
	end
	return nil
end

local function list3(flat: any): { any }
	local out = {}
	if type(flat) == "table" then
		for i = 1, #flat - 2, 3 do
			table.insert(out, Vector3.new(flat[i], flat[i + 1], flat[i + 2]))
		end
	end
	return out
end

function Night.clubEntrance(): any?
	if entrance then
		return entrance
	end
	local t = os.clock()
	if t < entranceTried then
		return nil
	end
	entranceTried = t + 5
	local ok, res = pcall(function()
		local g: any = game
		local rs = g:GetService("ReplicatedStorage")
		local m = rs:FindFirstChild("GwangalliNav")
		if m and m:IsA("ModuleScript") then
			local Nav: any = require(m)
			local c = Nav.club
			if type(c) == "table" then
				local queue = list3(c.queue)
				local nodes = c.nodes or {}
				local tailP = Nav.places and Nav.places.club_ocean
				return {
					door = v3(c.door),
					rope = v3(c.rope),
					guard = v3(c.guard),
					hangCenter = v3(c.hangCenter),
					queueFace = v3(c.queueFace) or Vector3.new(0, 0, 1),
					queue = queue,
					head = queue[1],
					tail = queue[#queue] or (tailP and Vector3.new(tailP.x, tailP.y, tailP.z)),
					hang = list3(c.hang),
					staticQueue = if isNum(c.staticQueue) then c.staticQueue else 0,
					doorNode = nodes.door or 0,
					tailNode = nodes.tail or 0,
					headNode = nodes.head or 0,
					hangNode = nodes.hang or 0,
				}
			end
		end
		-- fallback: the Destination part (may be streamed out on a client)
		local CS = g:GetService("CollectionService")
		for _, d in CS:GetTagged("Destination") do
			if d:IsA("BasePart") and d:GetAttribute("DisplayName") == "CLUB OCEAN 광안" then
				local p = d.Position
				return { door = p, tail = p, head = p, hangCenter = p, queue = {}, hang = {}, queueFace = Vector3.new(0, 0, 1), staticQueue = 0, doorNode = 0, tailNode = 0, headNode = 0, hangNode = 0 }
			end
		end
		return nil
	end)
	if ok and type(res) == "table" and res.door then
		entrance = res
	end
	return entrance
end

function Night.clubDistance(pos: any): number
	local e = Night.clubEntrance()
	if not e or not e.door or pos == nil then
		return math.huge
	end
	local dx, dz = pos.X - e.door.X, pos.Z - e.door.Z
	return math.sqrt(dx * dx + dz * dz)
end

return Night
