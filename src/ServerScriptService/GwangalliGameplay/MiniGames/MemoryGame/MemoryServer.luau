--!strict
-- MemoryGame/MemoryServer: 기억력 대결 (server only). Both players see the same digits for 2-3 s,
-- the digits disappear and both type them in order at the same time.
--   round 1: 3 digits, +1 per round both pass (up to MAX_LEN).
--   one right / one wrong -> the right one wins. both wrong -> same length again (3 double fails in a
--   row = draw). Both still right at MAX_LEN -> the faster total typing time wins.
-- The answer is checked on the server only; the digits are sent when they are shown (everyone sees
-- the same thing, so there is nothing to gain from reading the packet).
-- NPC accuracy falls with the length per difficulty.
-- Move payload: { round = n, answer = "38271" }.

local MemoryServer = {}

local M: any = nil

local START_LEN = 3
local MAX_LEN = 12
local SHOW_GAP = 1.0

function MemoryServer.init(m: any)
	M = m
end

function MemoryServer.new(_match: any, _api: any): any
	return {
		round = 0,
		len = START_LEN,
		seq = "",
		phase = "idle",
		showUntil = 0,
		deadline = 0,
		answers = {} :: { [number]: { ok: boolean, t: number } },
		npcAt = {} :: { [number]: number },
		total = { 0, 0 },
		fails = 0,
		last = nil :: any,
		nextAt = 0,
		over = false,
	}
end

local function showTime(len: number): number
	return math.min(3.0, 1.8 + 0.15 * len)
end

local function startRound(gs: any, api: any)
	gs.round += 1
	local digits = table.create(gs.len)
	local prev = -1
	for i = 1, gs.len do
		local d = api.rng:NextInteger(0, 9)
		if d == prev then
			d = (d + api.rng:NextInteger(1, 9)) % 10
		end
		digits[i] = tostring(d)
		prev = d
	end
	gs.seq = table.concat(digits)
	gs.phase = "show"
	gs.answers = {}
	gs.showUntil = os.clock() + showTime(gs.len)
	gs.deadline = gs.showUntil + 6 + 0.8 * gs.len
	for side = 1, 2 do
		if api.isNpc(side) then
			gs.npcAt[side] = gs.showUntil + 1.2 + gs.len * (0.35 + api.rng:NextNumber() * 0.3)
		end
	end
	api.score(string.format("%d자리", gs.len))
	api.event("memShow", { round = gs.round, seq = gs.seq, len = gs.len, until_ = api.toServer(gs.showUntil), deadline = api.toServer(gs.deadline) })
	api.push()
end

function MemoryServer.begin(gs: any, api: any)
	startRound(gs, api)
end

local function npcCorrect(api: any, side: number, len: number): boolean
	local d = api.difficulty(side)
	local p
	if d == "easy" then
		p = 1 - (len - 3) * 0.2
	elseif d == "hard" then
		p = 1 - (len - 7) * 0.13
	else
		p = 1 - (len - 4) * 0.16
	end
	return api.rng:NextNumber() < math.clamp(p, 0.05, 0.99)
end

local function judge(gs: any, api: any)
	local a1, a2 = gs.answers[1], gs.answers[2]
	local ok1 = a1 ~= nil and a1.ok
	local ok2 = a2 ~= nil and a2.ok
	gs.last = { ok1 = ok1, ok2 = ok2, seq = gs.seq }
	gs.phase = "judge"
	gs.nextAt = os.clock() + 2.4
	api.event("memJudge", { ok1 = ok1, ok2 = ok2, seq = gs.seq })
	if ok1 ~= ok2 then
		gs.over = true
		gs.winner = if ok1 then 1 else 2
	elseif not ok1 then
		gs.fails += 1
		if gs.fails >= 3 then
			gs.over = true
			gs.winner = 0
		end
	else
		gs.fails = 0
		gs.total[1] += a1.t
		gs.total[2] += a2.t
		if gs.len >= MAX_LEN then
			gs.over = true
			gs.winner = if math.abs(gs.total[1] - gs.total[2]) < 0.05 then 0 elseif gs.total[1] < gs.total[2] then 1 else 2
		else
			gs.len += 1
		end
	end
	for side = 1, 2 do
		local ok = if side == 1 then ok1 else ok2
		api.emote(side, if ok then "nod" else "facepalm")
	end
	api.push()
end

function MemoryServer.input(gs: any, side: number, p: any, api: any)
	if gs.phase ~= "input" and gs.phase ~= "show" then
		return
	end
	if gs.answers[side] or M.Anti.int(p.round, 1, 1000) ~= gs.round then
		return
	end
	if type(p.answer) ~= "string" or #p.answer > MAX_LEN + 2 or not string.match(p.answer, "^%d*$") then
		return
	end
	local now = os.clock()
	if now < gs.showUntil then
		return -- typing while the digits are still shown is not allowed
	end
	gs.answers[side] = { ok = p.answer == gs.seq, t = now - gs.showUntil }
	local pl = api.player(side)
	if pl then
		M.fire(pl, M.MS.Kinds.event, { id = api.match.id, e = "memSent" })
	end
	if gs.answers[1] and gs.answers[2] then
		judge(gs, api)
	end
end

function MemoryServer.tick(gs: any, now: number, api: any)
	if gs.phase == "show" and now >= gs.showUntil then
		gs.phase = "input"
		api.event("memHide", { round = gs.round })
		api.push()
	elseif gs.phase == "input" then
		for side = 1, 2 do
			local at = gs.npcAt[side]
			if api.isNpc(side) and not gs.answers[side] and at and now >= at then
				gs.answers[side] = { ok = npcCorrect(api, side, gs.len), t = now - gs.showUntil }
			end
		end
		if (gs.answers[1] and gs.answers[2]) or now >= gs.deadline then
			judge(gs, api)
		end
	elseif gs.phase == "judge" and now >= gs.nextAt then
		if gs.over then
			gs.phase = "done"
			api.finish(gs.winner or 0, "memory")
		else
			startRound(gs, api)
		end
	end
end

function MemoryServer.view(gs: any, side: number): any
	return {
		round = gs.round,
		len = gs.len,
		phase = gs.phase,
		seq = if gs.phase == "show" or gs.phase == "judge" then gs.seq else nil,
		showUntil = workspace:GetServerTimeNow() + (gs.showUntil - os.clock()),
		deadline = workspace:GetServerTimeNow() + (gs.deadline - os.clock()),
		sent = if side > 0 then gs.answers[side] ~= nil else false,
		last = gs.last,
		gap = SHOW_GAP,
	}
end

return MemoryServer
