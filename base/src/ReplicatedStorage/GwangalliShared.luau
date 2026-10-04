-- GwangalliShared: pure helpers used by both the server and the clients so everyone derives
-- the same answers (night window, phases, deterministic hashes, traffic-signal states) from
-- the same inputs. No instances are created here.

local configModule = script.Parent:WaitForChild("GwangalliConfig", 30)
if not configModule then
	error("[GwangalliShared] GwangalliConfig is missing next to GwangalliShared")
end
local Config = require(configModule)

local Shared = {}

-- Attribute names (single source of truth) ---------------------------------------------------
Shared.Attr = {
	TerrainBaked = "GwangalliTerrainBaked",
	TerrainReady = "GwangalliTerrainReady",
	Phase = "GwangalliPhase",
	IsNight = "GwangalliIsNight",
	ClockAnchorTime = "GwangalliClockAnchorTime", -- server time (GetServerTimeNow) of the anchor
	ClockAnchorClock = "GwangalliClockAnchorClock", -- clock at the anchor
	ClockRate = "GwangalliClockRate", -- in-game hours per real second (0 when paused)
	DroneShowStart = "GwangalliDroneShowStart", -- server time the current/last show started
	DroneShowDuration = "GwangalliDroneShowDuration",
	SignalPhase = "SignalPhase", -- 0/1 on TrafficSignal / PedSignal housings (set by the server)
}

-- Clock -------------------------------------------------------------------------------------------

-- True when `clock` (0-24) lies in the window [from, to) that may wrap past midnight.
function Shared.inWindow(clock: number, from: number, to: number): boolean
	if from <= to then
		return clock >= from and clock < to
	end
	return clock >= from or clock < to
end

function Shared.isNightClock(clock: number): boolean
	return Shared.inWindow(clock, Config.NightStart, Config.NightEnd)
end

function Shared.phaseForClock(clock: number): string
	for _, p in Config.Phases do
		if Shared.inWindow(clock, p.from, p.to) then
			return p.name
		end
	end
	return "Night"
end

-- In-game clock derived from the replicated anchor attributes (smooth on clients; falls back
-- to Lighting.ClockTime when the server has not published an anchor yet).
function Shared.clockNow(): number
	local ws = workspace
	local t0 = ws:GetAttribute(Shared.Attr.ClockAnchorTime)
	local c0 = ws:GetAttribute(Shared.Attr.ClockAnchorClock)
	local rate = ws:GetAttribute(Shared.Attr.ClockRate)
	if type(t0) == "number" and type(c0) == "number" and type(rate) == "number" then
		return (c0 + (ws:GetServerTimeNow() - t0) * rate) % 24
	end
	return game:GetService("Lighting").ClockTime
end

-- Drone show state from the replicated attributes: (active, elapsedSeconds, durationSeconds).
function Shared.droneShowState(now: number?): (boolean, number, number)
	local ws = workspace
	local start = ws:GetAttribute(Shared.Attr.DroneShowStart)
	local duration = ws:GetAttribute(Shared.Attr.DroneShowDuration)
	if type(duration) ~= "number" or duration <= 0 then
		duration = Config.DroneShow.Duration
	end
	if type(start) ~= "number" then
		return false, -1, duration
	end
	local elapsed = (now or ws:GetServerTimeNow()) - start
	return elapsed >= 0 and elapsed < duration, elapsed, duration
end

-- Next configured show start (clock) after `clock`, or nil when shows are disabled.
function Shared.nextShowClock(clock: number): number?
	local cfg = Config.DroneShow
	if not cfg.Enabled or #cfg.Times == 0 then
		return nil
	end
	local best, bestDelta = nil, math.huge
	for _, t in cfg.Times do
		local delta = (t - clock) % 24
		if delta < bestDelta then
			best, bestDelta = t, delta
		end
	end
	return best
end

function Shared.formatClock(clock: number): string
	local minutes = math.floor((clock % 24) * 60 + 1e-6)
	return string.format("%02d:%02d", minutes // 60, minutes % 60)
end

-- Hashes --------------------------------------------------------------------------------------------

-- Exact 32-bit multiply (a plain a * b would exceed the 53-bit double mantissa).
local function mul32(a: number, b: number): number
	local aLo, aHi = a % 65536, a // 65536
	local bLo, bHi = b % 65536, b // 65536
	return ((aHi * bLo + aLo * bHi) % 65536 * 65536 + aLo * bLo) % 4294967296
end
Shared.mul32 = mul32

-- 32-bit FNV-1a of a string (deterministic across server and clients).
function Shared.hashString(s: string): number
	local h = 2166136261
	for i = 1, #s do
		h = bit32.bxor(h, string.byte(s, i))
		h = mul32(h, 16777619)
	end
	return h
end

-- One mixing round of hash01 (kept separate so hash01 needs no temporary table).
local function mix(h: number, v: number): number
	local q = math.floor(v * 2 + 0.5) % 4294967296
	h = bit32.bxor(h, q)
	h = mul32(h, 0x85EBCA6B)
	return bit32.bxor(h, bit32.rshift(h, 15))
end

-- Integer mix -> [0, 1). Inputs are quantised to half studs so tiny float noise does not flip
-- results. Allocation-free (it runs per LED / per window on phones); results are identical to
-- the original table-loop version (same four rounds in the same order).
function Shared.hash01(a: number, b: number?, c: number?, d: number?): number
	local h = mix(0x9E3779B9, a)
	h = mix(h, b or 0)
	h = mix(h, c or 0)
	h = mix(h, d or 0)
	h = mul32(h, 0xC2B2AE35)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	return h / 4294967296
end

-- Traffic signals -------------------------------------------------------------------------------------
-- Two-phase cycle per Group: phase 0 green -> amber -> all red, then phase 1 the same.
-- Every group is offset by a hash of its name so intersections do not switch in lockstep.

local T = Config.Traffic
local HALF = T.Green + T.Amber + T.AllRed
local CYCLE = HALF * 2
Shared.SignalCycle = CYCLE

local offsetCache: { [string]: number } = {}
function Shared.signalOffset(group: string): number
	local o = offsetCache[group]
	if not o then
		o = Shared.hashString(group) % (CYCLE * 100) / 100
		offsetCache[group] = o
	end
	return o
end

-- Seconds into this phase's half-cycle: [0, Green) green, [Green, Green+Amber) amber, else red.
function Shared.signalTime(group: string, phase: number, serverTime: number): number
	local u = (serverTime + Shared.signalOffset(group) + (phase == 1 and HALF or 0)) % CYCLE
	return u
end

-- Returns "green" | "amber" | "red" for vehicles of `phase` (0 or 1) in `group`.
function Shared.vehicleState(group: string, phase: number, serverTime: number): string
	local u = Shared.signalTime(group, phase, serverTime)
	if u < T.Green then
		return "green"
	elseif u < T.Green + T.Amber then
		return "amber"
	end
	return "red"
end

-- Returns "walk" | "flash" | "stop" for pedestrians walking parallel to `phase` traffic.
function Shared.pedState(group: string, phase: number, serverTime: number): string
	local u = Shared.signalTime(group, phase, serverTime)
	if u < T.Green - T.PedFlash then
		return "walk"
	elseif u < T.Green then
		return "flash"
	end
	return "stop"
end

-- Direction bucket for a housing when the server has not assigned SignalPhase: the facing axis
-- (mod 180 degrees) closer to world X -> 0, closer to world Z -> 1.
function Shared.fallbackSignalPhase(cf: CFrame): number
	local look = cf.LookVector
	return math.abs(look.X) >= math.abs(look.Z) and 0 or 1
end

return Shared
