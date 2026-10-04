--!strict
-- MiniGames/AntiCheat: request hygiene for the minigame remotes (server only).
--   * per-player token buckets per action family (spam never reaches a game module)
--   * payload shape checks (tables only, bounded key count / string length / numbers finite)
--   * distance checks against stations (a remote from across the map is ignored)
--   * latency estimate per player (Update "ping" -> Request "ping" round trips, smoothed, and
--     Player:GetNetworkPing() when the engine has it) for the timing games: the server judges with
--     server time and only ever SUBTRACTS a bounded latency allowance, so a lying client can never
--     claim a faster reaction than the server measured minus the player's own measured round trip.
--   * a strike counter: suspicious requests are logged (once per kind per player) and dropped.
-- Nothing here touches money; BetService is the only money path.

local Players = game:GetService("Players")

local AntiCheat = {}

local M: any = nil

type Bucket = { tokens: number, t: number }
local buckets: { [Player]: { [string]: Bucket } } = {}
local rtts: { [Player]: { rtt: number, n: number, sent: { [number]: number }, seq: number } } = {}
local strikes: { [Player]: { [string]: number } } = {}

function AntiCheat.init(m: any)
	M = m
end

-- true when the action may run now (rate tokens per second, burst size)
function AntiCheat.allow(player: Player, key: string, rate: number, burst: number): boolean
	local per = buckets[player]
	if not per then
		per = {}
		buckets[player] = per
	end
	local now = os.clock()
	local b = per[key]
	if not b then
		b = { tokens = burst, t = now }
		per[key] = b
	end
	b.tokens = math.min(burst, b.tokens + (now - b.t) * rate)
	b.t = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end
AntiCheat.finite = finite

-- Shallow payload check: a table with at most 12 keys, string keys, values that are booleans,
-- finite numbers, short strings, or Instances (stations are sent as ids, never as Instances).
function AntiCheat.payload(p: any): boolean
	if type(p) ~= "table" then
		return false
	end
	local n = 0
	for k, v in p do
		n += 1
		if n > 12 or type(k) ~= "string" or #k > 24 then
			return false
		end
		local t = type(v)
		if t == "number" then
			if not finite(v) then
				return false
			end
		elseif t == "string" then
			if #v > 200 then
				return false
			end
		elseif t ~= "boolean" then
			return false
		end
	end
	return true
end

function AntiCheat.int(v: any, lo: number, hi: number): number?
	if not finite(v) or v % 1 ~= 0 or v < lo or v > hi then
		return nil
	end
	return v
end

function AntiCheat.rootPos(player: Player): Vector3?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

function AntiCheat.near(player: Player, pos: Vector3, dist: number): boolean
	local p = AntiCheat.rootPos(player)
	return p ~= nil and (p - pos).Magnitude <= dist
end

function AntiCheat.alive(player: Player): boolean
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

-- Logged once per (player, kind); returns the strike count.
function AntiCheat.strike(player: Player, kind: string, detail: string?): number
	local s = strikes[player]
	if not s then
		s = {}
		strikes[player] = s
	end
	s[kind] = (s[kind] or 0) + 1
	if s[kind] == 1 then
		warn(string.format("[MiniGames] suspicious %s from %s (%d): %s", kind, player.Name, player.UserId, detail or ""))
	end
	return s[kind]
end

-------------------------------------------------------------------------------------------------
-- latency
-------------------------------------------------------------------------------------------------
function AntiCheat.sendPing(player: Player)
	local r = rtts[player]
	if not r then
		r = { rtt = 0.15, n = 0, sent = {}, seq = 0 }
		rtts[player] = r
	end
	r.seq += 1
	r.sent[r.seq] = os.clock()
	-- forget unanswered probes
	for k in r.sent do
		if k < r.seq - 4 then
			r.sent[k] = nil
		end
	end
	M.fire(player, M.MS.Kinds.ping, { s = r.seq })
end

function AntiCheat.onPong(player: Player, p: any)
	local r = rtts[player]
	local seq = AntiCheat.int(p.s, 1, 1e9)
	if not r or not seq then
		return
	end
	local t0 = r.sent[seq]
	if not t0 then
		return
	end
	r.sent[seq] = nil
	local sample = math.clamp(os.clock() - t0, 0.005, 1.5)
	r.n += 1
	-- fast start, then an exponential average that trusts lower samples more (spikes are not latency)
	if r.n == 1 then
		r.rtt = sample
	else
		local a = if sample < r.rtt then 0.4 else 0.15
		r.rtt += (sample - r.rtt) * a
	end
end

-- Round trip in seconds (clamped). Engine ping wins when it is available and plausible.
function AntiCheat.rtt(player: Player?): number
	if not player then
		return 0
	end
	local own = rtts[player]
	local v = if own then own.rtt else 0.15
	local ok, np = pcall(function()
		return (player :: any):GetNetworkPing()
	end)
	if ok and finite(np) and np > 0 and np < 2 then
		-- GetNetworkPing is the one-way-ish isolated latency; our probe is a full round trip
		v = math.min(v, np * 2 + 0.03)
	end
	return math.clamp(v, 0.01, 0.6)
end

function AntiCheat.forget(player: Player)
	buckets[player] = nil
	rtts[player] = nil
	strikes[player] = nil
end

Players.PlayerRemoving:Connect(function(p)
	task.defer(AntiCheat.forget, p)
end)

return AntiCheat
