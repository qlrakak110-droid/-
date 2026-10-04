--!strict
-- TimingGame/TimingServer: 타이밍 게임 (server only). A marker sweeps across a bar (triangle wave,
-- faster every round); press once to stop it as close to the centre as possible. Score per round =
-- 100 - |position - 0.5| x 200 (0..100), 3 rounds summed, higher total wins (equal = draw).
-- Both players play every round at the same time. Each client starts its bar when the round event
-- arrives and reports the elapsed time on its own clock (`t`): that is the fair number on a laggy
-- connection. The server checks it against its own estimate (receive time - start - round trip) and
-- uses the server estimate whenever the claim is off by more than the latency allowance.
-- NPC: centre error by difficulty.
-- Move payload: { round = n, t = seconds since the bar started on the client }.

local TimingServer = {}

local M: any = nil

local ROUNDS = 3
local PERIODS = { 1.7, 1.35, 1.05 } -- seconds for one sweep (left -> right)
local WINDOW = 6
local READY = 1.2
local SHOW = 2.2
local NPC_ERR = { easy = 0.17, normal = 0.08, hard = 0.035 }

function TimingServer.init(m: any)
	M = m
end

local function posAt(t: number, period: number): number
	local u = (t / period) % 2
	return if u <= 1 then u else 2 - u
end
TimingServer.posAt = posAt

function TimingServer.new(_match: any, _api: any): any
	return {
		round = 0,
		phase = "idle",
		startAt = 0,
		endAt = 0,
		nextAt = 0,
		period = PERIODS[1],
		press = {} :: { [number]: number },
		npcPos = {} :: { [number]: number },
		npcAt = {} :: { [number]: number },
		total = { 0, 0 },
		rounds = {} :: { { number } },
		over = false,
	}
end

local function points(pos: number): number
	return math.max(0, math.floor(100 - math.abs(pos - 0.5) * 200 + 0.5))
end

local function startRound(gs: any, api: any)
	gs.round += 1
	gs.phase = "ready"
	gs.period = PERIODS[gs.round] or PERIODS[#PERIODS]
	gs.press = {}
	gs.startAt = os.clock() + READY
	gs.endAt = gs.startAt + WINDOW
	for side = 1, 2 do
		if api.isNpc(side) then
			local err = NPC_ERR[api.difficulty(side)] or 0.08
			local g = 0
			for _ = 1, 3 do
				g += api.rng:NextNumber() * 2 - 1
			end
			gs.npcPos[side] = math.clamp(0.5 + g / 3 * err * 1.8, 0, 1)
			gs.npcAt[side] = gs.startAt + 1.0 + api.rng:NextNumber() * 2.5
		end
	end
	api.score(string.format("%d : %d", gs.total[1], gs.total[2]))
	api.event("timingReady", { round = gs.round, period = gs.period, startAt = api.toServer(gs.startAt), window = WINDOW })
	api.push()
end

function TimingServer.begin(gs: any, api: any)
	startRound(gs, api)
end

local function decide(gs: any, api: any)
	local s = { points(gs.press[1] or -1), points(gs.press[2] or -1) }
	if not gs.press[1] then
		s[1] = 0
	end
	if not gs.press[2] then
		s[2] = 0
	end
	gs.total[1] += s[1]
	gs.total[2] += s[2]
	table.insert(gs.rounds, s)
	gs.phase = "show"
	gs.nextAt = os.clock() + SHOW
	api.event("timingResult", { round = gs.round, p1 = gs.press[1], p2 = gs.press[2], s1 = s[1], s2 = s[2], t1 = gs.total[1], t2 = gs.total[2] })
	api.score(string.format("%d : %d", gs.total[1], gs.total[2]))
	for side = 1, 2 do
		if s[side] >= 95 then
			api.emote(side, "cheer")
		end
	end
	api.push()
end

function TimingServer.input(gs: any, side: number, p: any, api: any)
	if gs.phase ~= "run" or gs.press[side] or M.Anti.int(p.round, 1, 100) ~= gs.round then
		return
	end
	local now = os.clock()
	local rtt = api.rtt(side)
	local est = now - gs.startAt - rtt
	local t = est
	if M.Anti.finite(p.t) and math.abs(p.t - est) <= 0.08 + rtt * 0.5 then
		t = p.t
	elseif M.Anti.finite(p.t) then
		M.Anti.strike(api.player(side) :: Player, "timing", string.format("claim %.3f est %.3f", p.t, est))
	end
	t = math.clamp(t, 0, WINDOW)
	gs.press[side] = posAt(t, gs.period)
	api.emote(side, "mg_press")
	if gs.press[1] and gs.press[2] then
		decide(gs, api)
	end
end

function TimingServer.tick(gs: any, now: number, api: any)
	if gs.over then
		return
	end
	if gs.phase == "ready" and now >= gs.startAt then
		gs.phase = "run"
		gs.startAt = os.clock() -- the moment the go event leaves (clients start their bars on it)
		gs.endAt = gs.startAt + WINDOW
		api.event("timingGo", { round = gs.round })
	elseif gs.phase == "run" then
		for side = 1, 2 do
			if api.isNpc(side) and not gs.press[side] and now >= (gs.npcAt[side] or math.huge) then
				gs.press[side] = gs.npcPos[side]
				api.emote(side, "mg_press")
			end
		end
		if (gs.press[1] and gs.press[2]) or now >= gs.endAt then
			decide(gs, api)
		end
	elseif gs.phase == "show" and now >= gs.nextAt then
		if gs.round >= ROUNDS then
			gs.over = true
			local a, b = gs.total[1], gs.total[2]
			api.finish(if a > b then 1 elseif b > a then 2 else 0, "points")
		else
			startRound(gs, api)
		end
	end
end

function TimingServer.view(gs: any, side: number): any
	return {
		round = gs.round,
		rounds = ROUNDS,
		phase = gs.phase,
		period = gs.period,
		total = gs.total,
		history = gs.rounds,
		pressed = if side > 0 then gs.press[side] ~= nil else false,
	}
end

return TimingServer
