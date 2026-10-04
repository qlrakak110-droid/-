--!strict
-- ReactionGame/ReactionServer: 순발력 대결, 3판 2선승 (server only, server clock decides).
--   준비 ... 준비 ... (random 2-5 s) ... 지금!
-- Fairness / anti-cheat:
--   * The server never announces WHEN "지금!" comes: it fires the go event at that moment, so a
--     client cannot pre-schedule a press.
--   * A press that reaches the server before "지금!" was sent, or so soon after it that it must have
--     been sent before the go event could have arrived (server delta < half the player's measured
--     round trip), is a 부정 출발 (false start) and loses the round.
--   * Ping compensation: presses are collected until both sides pressed (or WINDOW seconds); each
--     side's reaction = the server-measured delay minus that player's own round trip (AntiCheat.rtt,
--     bounded). The client's own measurement is only used when it is SLOWER than that (a client can
--     make itself slower, never faster). Equal within 10 ms = 무승부 round (replayed).
-- NPC reaction times per difficulty, with an occasional false start for 초보.
-- Move payload: { round = n, early = bool, rt = seconds measured on the client }.

local ReactionServer = {}

local M: any = nil

local WIN_TO = 2
local WINDOW = 2.0
local SHOW = 2.2
local MAX_ROUNDS = 7
local MIN_HUMAN = 0.1 -- faster than this after compensation = anticipation, treated as a false start

local NPC_RT = { easy = { 0.42, 0.62 }, normal = { 0.30, 0.42 }, hard = { 0.21, 0.29 } }
local NPC_FOUL = { easy = 0.08, normal = 0.03, hard = 0.01 }

function ReactionServer.init(m: any)
	M = m
end

function ReactionServer.new(_match: any, _api: any): any
	return {
		round = 0,
		score = { 0, 0 },
		phase = "idle",
		goAt = 0,
		goSent = 0,
		nextAt = 0,
		press = {} :: { [number]: any },
		npcPress = {} :: { [number]: number },
		last = nil :: any,
		over = false,
	}
end

local function startRound(gs: any, api: any)
	gs.round += 1
	gs.phase = "ready"
	gs.press = {}
	gs.npcPress = {}
	gs.last = nil
	gs.goAt = os.clock() + 2.0 + api.rng:NextNumber() * 3.0
	gs.goSent = 0
	for side = 1, 2 do
		if api.isNpc(side) then
			local d = api.difficulty(side)
			if api.rng:NextNumber() < (NPC_FOUL[d] or 0.03) then
				-- jumps the gun somewhere in the waiting time
				gs.npcPress[side] = os.clock() + 0.8 + api.rng:NextNumber() * math.max(0.2, gs.goAt - os.clock() - 1)
			else
				local r = NPC_RT[d] or NPC_RT.normal
				gs.npcPress[side] = gs.goAt + r[1] + api.rng:NextNumber() * (r[2] - r[1])
			end
		end
	end
	api.score(string.format("%d : %d", gs.score[1], gs.score[2]))
	api.event("reactReady", { round = gs.round })
	api.push()
end

function ReactionServer.begin(gs: any, api: any)
	startRound(gs, api)
end

local function decide(gs: any, api: any)
	local p1, p2 = gs.press[1], gs.press[2]
	local foul1 = p1 and p1.foul or false
	local foul2 = p2 and p2.foul or false
	local w = 0
	if foul1 and not foul2 then
		w = 2
	elseif foul2 and not foul1 then
		w = 1
	elseif not foul1 and not foul2 then
		local t1 = if p1 then p1.t else math.huge
		local t2 = if p2 then p2.t else math.huge
		if t1 == math.huge and t2 == math.huge then
			w = 0
		elseif math.abs(t1 - t2) <= 0.01 then
			w = 0
		else
			w = if t1 < t2 then 1 else 2
		end
	end
	if w > 0 then
		gs.score[w] += 1
	end
	gs.phase = "show"
	gs.nextAt = os.clock() + SHOW
	gs.last = {
		w = w,
		t1 = if p1 and not p1.foul then math.floor(p1.t * 1000) else nil,
		t2 = if p2 and not p2.foul then math.floor(p2.t * 1000) else nil,
		foul1 = foul1,
		foul2 = foul2,
	}
	api.event("reactResult", { w = w, t1 = gs.last.t1, t2 = gs.last.t2, foul1 = foul1, foul2 = foul2, s1 = gs.score[1], s2 = gs.score[2] })
	api.score(string.format("%d : %d", gs.score[1], gs.score[2]))
	if w > 0 then
		api.emote(w, "mg_fist")
	end
	for side = 1, 2 do
		if api.isNpc(side) and w ~= 0 then
			api.line(side, if w == side then "win" else "good")
		end
	end
	api.push()
end

local function record(gs: any, side: number, foul: boolean, t: number)
	if gs.press[side] then
		return
	end
	gs.press[side] = { foul = foul, t = t }
end

function ReactionServer.input(gs: any, side: number, p: any, api: any)
	if gs.press[side] then
		return
	end
	local round = M.Anti.int(p.round, 1, 1000)
	if round ~= gs.round then
		return
	end
	local now = os.clock()
	if gs.phase == "ready" then
		record(gs, side, true, 0)
		api.event("reactFoul", { side = side })
		decide(gs, api)
		return
	end
	if gs.phase ~= "go" then
		return
	end
	local rtt = api.rtt(side)
	local serverDelta = now - gs.goSent
	if p.early == true or serverDelta < rtt * 0.5 then
		record(gs, side, true, 0)
		api.event("reactFoul", { side = side })
		decide(gs, api)
		return
	end
	local est = serverDelta - math.min(rtt, 0.5)
	local claimed = if M.Anti.finite(p.rt) then p.rt else est
	local t = math.max(est, claimed)
	if t < MIN_HUMAN then
		record(gs, side, true, 0)
		M.Anti.strike(api.player(side) :: Player, "reaction", string.format("%.3f", t))
		api.event("reactFoul", { side = side })
		decide(gs, api)
		return
	end
	record(gs, side, false, t)
	if gs.press[1] and gs.press[2] then
		decide(gs, api)
	end
end

function ReactionServer.tick(gs: any, now: number, api: any)
	if gs.over then
		return
	end
	if gs.phase == "ready" then
		for side = 1, 2 do
			local at = gs.npcPress[side]
			if at and now >= at and now < gs.goAt then
				record(gs, side, true, 0)
				api.event("reactFoul", { side = side })
				decide(gs, api)
				return
			end
		end
		if now >= gs.goAt then
			gs.phase = "go"
			gs.goSent = os.clock()
			api.event("reactGo", { round = gs.round })
		end
	elseif gs.phase == "go" then
		for side = 1, 2 do
			local at = gs.npcPress[side]
			if at and not gs.press[side] and now >= at then
				record(gs, side, false, at - gs.goAt)
			end
		end
		if (gs.press[1] and gs.press[2]) or now - gs.goSent > WINDOW then
			decide(gs, api)
		end
	elseif gs.phase == "show" and now >= gs.nextAt then
		if gs.score[1] >= WIN_TO or gs.score[2] >= WIN_TO then
			gs.over = true
			api.finish(if gs.score[1] > gs.score[2] then 1 else 2, "score")
		elseif gs.round >= MAX_ROUNDS then
			gs.over = true
			api.finish(if gs.score[1] > gs.score[2] then 1 elseif gs.score[2] > gs.score[1] then 2 else 0, "rounds")
		else
			startRound(gs, api)
		end
	end
end

function ReactionServer.view(gs: any, _side: number): any
	return { round = gs.round, score = gs.score, phase = gs.phase, last = gs.last, winTo = WIN_TO }
end

return ReactionServer
