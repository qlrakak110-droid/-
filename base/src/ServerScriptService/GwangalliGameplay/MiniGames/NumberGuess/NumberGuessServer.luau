--!strict
-- NumberGuess/NumberGuessServer: 숫자 맞히기 (업다운), server only. The server picks 1..100 and
-- never sends it before the end. Players take turns (TURN_TIME s): every guess must be inside the
-- range that is still open ("23 ~ 61"), the answer is UP / DOWN for everyone; the exact number wins.
-- A timeout passes the turn; the second timeout loses.
-- NPC: 초보 guesses anywhere in the open range, 일반 near the middle, 고수 splits it exactly.
-- Move payload: { n = integer }.

local NumberGuessServer = {}

local M: any = nil

local LO, HI = 1, 100
local TURN_TIME = 12

function NumberGuessServer.init(m: any)
	M = m
end

function NumberGuessServer.new(_match: any, api: any): any
	return {
		secret = api.rng:NextInteger(LO, HI),
		lo = LO,
		hi = HI,
		turn = api.rng:NextInteger(1, 2),
		deadline = 0,
		npcAt = 0,
		history = {} :: { { s: number, n: number, r: string } },
		strikes = { 0, 0 },
		over = false,
	}
end

local function startTurn(gs: any, side: number, api: any)
	gs.turn = side
	gs.deadline = os.clock() + TURN_TIME
	gs.npcAt = if api.isNpc(side) then os.clock() + 1.4 + api.rng:NextNumber() * 2.2 else 0
	api.turn(side)
	api.score(string.format("%d ~ %d", gs.lo, gs.hi))
	api.push()
end

function NumberGuessServer.begin(gs: any, api: any)
	startTurn(gs, gs.turn, api)
end

local function guess(gs: any, side: number, n: number, api: any)
	local r
	if n == gs.secret then
		r = "정답"
	elseif n < gs.secret then
		r = "UP"
		gs.lo = n + 1
	else
		r = "DOWN"
		gs.hi = n - 1
	end
	table.insert(gs.history, { s = side, n = n, r = r })
	api.say(side, tostring(n) .. "!", 1.8)
	api.event("guess", { side = side, n = n, r = r, lo = gs.lo, hi = gs.hi })
	if r == "정답" then
		gs.over = true
		api.attr("NumberSecret", gs.secret)
		api.finish(side, "exact")
		return
	end
	local other = if side == 1 then 2 else 1
	if api.isNpc(other) and api.rng:NextNumber() < 0.2 then
		api.line(other, "good")
	end
	startTurn(gs, other, api)
end

function NumberGuessServer.input(gs: any, side: number, p: any, api: any)
	if gs.over or gs.turn ~= side then
		return
	end
	local n = M.Anti.int(p.n, LO, HI)
	if not n then
		return
	end
	if n < gs.lo or n > gs.hi then
		local pl = api.player(side)
		if pl then
			M.toast(pl, "info", "범위 밖이에요", string.format("%d ~ %d 사이에서 골라 주세요", gs.lo, gs.hi))
		end
		return
	end
	guess(gs, side, n, api)
end

local function npcGuess(gs: any, side: number, api: any): number
	local d = api.difficulty(side)
	local lo, hi = gs.lo, gs.hi
	if d == "hard" then
		return (lo + hi) // 2
	elseif d == "normal" then
		local mid = (lo + hi) / 2
		local spread = math.max(1, (hi - lo) * 0.2)
		return math.clamp(math.floor(mid + (api.rng:NextNumber() * 2 - 1) * spread + 0.5), lo, hi)
	end
	return api.rng:NextInteger(lo, hi)
end

function NumberGuessServer.tick(gs: any, now: number, api: any)
	if gs.over then
		return
	end
	local side = gs.turn
	if api.isNpc(side) then
		if gs.npcAt > 0 and now >= gs.npcAt then
			gs.npcAt = 0
			guess(gs, side, npcGuess(gs, side, api), api)
		end
		return
	end
	if now >= gs.deadline then
		gs.strikes[side] += 1
		if gs.strikes[side] >= 2 then
			gs.over = true
			api.attr("NumberSecret", gs.secret)
			api.finish(if side == 1 then 2 else 1, "timeout")
			return
		end
		local pl = api.player(side)
		if pl then
			M.toast(pl, "warn", "시간 초과!", "차례가 넘어갔어요. 한 번 더 넘기면 패배예요")
		end
		startTurn(gs, if side == 1 then 2 else 1, api)
	end
end

function NumberGuessServer.view(gs: any, _side: number): any
	local hist = {}
	for k = math.max(1, #gs.history - 7), #gs.history do
		table.insert(hist, gs.history[k])
	end
	return {
		lo = gs.lo,
		hi = gs.hi,
		turn = gs.turn,
		deadline = workspace:GetServerTimeNow() + math.max(0, gs.deadline - os.clock()),
		turnTime = TURN_TIME,
		history = hist,
		secret = if gs.over then gs.secret else nil,
	}
end

function NumberGuessServer.cleanup(_gs: any, api: any)
	api.attr("NumberSecret", 0)
end

return NumberGuessServer
