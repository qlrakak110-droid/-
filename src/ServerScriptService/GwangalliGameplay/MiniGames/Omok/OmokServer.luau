--!strict
-- Omok/OmokServer: 오목 on the 3D board (server only; rules + board logic in the shared OmokConfig).
--   * 흑 / 백 random, 흑 first. One move per turn, OmokConfig.MOVE_TIME seconds each; the first
--     timeout plays a random move for the sleeper, the second loses the game (OmokConfig.TIMEOUT_STRIKES).
--   * Korean rule by default (흑: 쌍삼 / 4-4 / 장목 금지 - the move is refused with the reason).
--   * Win = five in a row (OmokConfig.winLine), board full = draw, 기권 / 무승부 합의 via the manager.
-- Public broadcast (station attributes, so passers-by watch the real board): OmokBoard (225 chars),
-- OmokLast (cell), OmokSeq, OmokBlack (side 1 | 2), OmokWin ("i,j,k,l,m").
-- NPC: pattern-scoring AI. 초보 picks among the top moves at random and sometimes misses a block,
-- 일반 adds noise, 고수 always takes the best scored point (and never misses a win or a forced block).
-- Move payload: { cell = 1..225 }.

local OmokServer = {}

local M: any = nil
local OC: any = nil

function OmokServer.init(m: any)
	M = m
	OC = m.OC
end

local SIZE = 15
local DIRS = { { 1, 0 }, { 0, 1 }, { 1, 1 }, { 1, -1 } }

-------------------------------------------------------------------------------------------------
-- AI
-------------------------------------------------------------------------------------------------
-- value of the line through (x, y) for `color` if it played there: run length + open ends
local function lineValue(b: { number }, x: number, y: number, color: number): number
	local total = 0
	for _, d in DIRS do
		local dx, dy = d[1], d[2]
		local n = 1
		local open = 0
		local cx, cy = x + dx, y + dy
		while OC.at(b, cx, cy) == color do
			n += 1
			cx += dx
			cy += dy
		end
		if OC.at(b, cx, cy) == 0 then
			open += 1
			-- a gap then more stones (X_XX patterns) count a little
			if OC.at(b, cx + dx, cy + dy) == color then
				n += 0.6
			end
		end
		cx, cy = x - dx, y - dy
		while OC.at(b, cx, cy) == color do
			n += 1
			cx -= dx
			cy -= dy
		end
		if OC.at(b, cx, cy) == 0 then
			open += 1
			if OC.at(b, cx - dx, cy - dy) == color then
				n += 0.6
			end
		end
		local v = 0
		if n >= 5 then
			v = 1000000
		elseif n >= 4 then
			v = if open == 2 then 50000 elseif open == 1 then 6000 else 0
		elseif n >= 3 then
			v = if open == 2 then 5000 elseif open == 1 then 400 else 0
		elseif n >= 2 then
			v = if open == 2 then 300 elseif open == 1 then 40 else 0
		else
			v = if open == 2 then 10 elseif open == 1 then 2 else 0
		end
		total += v
	end
	return total
end

local function candidates(b: { number }): { number }
	local out = {}
	local any = false
	for i = 1, SIZE * SIZE do
		if b[i] ~= 0 then
			any = true
			break
		end
	end
	if not any then
		return { OC.idx(8, 8) }
	end
	for i = 1, SIZE * SIZE do
		if b[i] == 0 then
			local x, y = OC.xy(i)
			local near = false
			for dy = -2, 2 do
				for dx = -2, 2 do
					local v = OC.at(b, x + dx, y + dy)
					if v == 1 or v == 2 then
						near = true
						break
					end
				end
				if near then
					break
				end
			end
			if near then
				table.insert(out, i)
			end
		end
	end
	return out
end

local function choose(gs: any, color: number, difficulty: string, rng: Random): number?
	local b = gs.board
	local opp = if color == 1 then 2 else 1
	local scored = {}
	for _, i in candidates(b) do
		local x, y = OC.xy(i)
		if not OC.forbidden(b, x, y, color, gs.rule) then
			local attack = lineValue(b, x, y, color)
			local defend = lineValue(b, x, y, opp)
			local s = attack * 1.1 + defend * (if difficulty == "hard" then 1.0 elseif difficulty == "normal" then 0.85 else 0.6)
			-- prefer the centre a little
			s += (8 - math.max(math.abs(x - 8), math.abs(y - 8))) * 0.5
			table.insert(scored, { i = i, s = s, attack = attack, defend = defend })
		end
	end
	if #scored == 0 then
		return nil
	end
	table.sort(scored, function(a, c)
		return a.s > c.s
	end)
	local best = scored[1]
	-- never miss a win (all levels); forced blocks: hard always, normal mostly, easy sometimes
	if best.attack >= 1000000 then
		return best.i
	end
	if best.defend >= 50000 then
		local p = if difficulty == "hard" then 1 elseif difficulty == "normal" then 0.92 else 0.6
		if rng:NextNumber() < p then
			return best.i
		end
	end
	if difficulty == "hard" then
		return best.i
	end
	local top = if difficulty == "normal" then 3 else 7
	top = math.min(top, #scored)
	-- weighted pick among the top moves
	local sum = 0
	for k = 1, top do
		sum += 1 / k
	end
	local r = rng:NextNumber() * sum
	for k = 1, top do
		r -= 1 / k
		if r <= 0 then
			return scored[k].i
		end
	end
	return scored[1].i
end
OmokServer._choose = choose

-------------------------------------------------------------------------------------------------
-- game
-------------------------------------------------------------------------------------------------
function OmokServer.new(match: any, api: any): any
	local black = api.rng:NextInteger(1, 2)
	return {
		board = OC.empty(),
		rule = OC.RULE,
		black = black,
		colorOf = { [black] = 1, [if black == 1 then 2 else 1] = 2 },
		turn = black,
		last = 0,
		seq = 0,
		deadline = 0,
		strikes = { 0, 0 },
		npcAt = 0,
		moves = 0,
		winLine = nil :: { number }?,
	}
end

local function publish(gs: any, api: any)
	api.attr("OmokBoard", OC.encode(gs.board))
	api.attr("OmokLast", gs.last)
	api.attr("OmokSeq", gs.seq)
	api.attr("OmokBlack", gs.black)
	api.attr("OmokWin", if gs.winLine then table.concat(gs.winLine, ",") else "")
	api.turn(if gs.winLine then 0 else gs.turn)
	api.score(string.format("%d수", gs.moves))
end

local function npcDelay(api: any, side: number): number
	local d = api.difficulty(side)
	local lo, hi = 1.2, 2.6
	if d == "normal" then
		lo, hi = 1.6, 3.4
	elseif d == "hard" then
		lo, hi = 2.0, 4.2
	end
	return lo + api.rng:NextNumber() * (hi - lo)
end

local function startTurn(gs: any, side: number, api: any)
	gs.turn = side
	gs.deadline = os.clock() + OC.MOVE_TIME
	gs.npcAt = if api.isNpc(side) then os.clock() + npcDelay(api, side) else 0
	if api.isNpc(side) and api.rng:NextNumber() < 0.25 then
		api.line(side, "think")
	end
end

function OmokServer.begin(gs: any, api: any)
	for i = 1, #gs.board do
		gs.board[i] = 0
	end
	startTurn(gs, gs.black, api)
	publish(gs, api)
	api.event("omokStart", { black = gs.black })
end

local function place(gs: any, side: number, cell: number, api: any, auto: boolean?): (boolean, string?)
	if gs.turn ~= side then
		return false, "상대 차례예요"
	end
	if gs.board[cell] ~= 0 then
		return false, "이미 돌이 있어요"
	end
	local color = gs.colorOf[side]
	local x, y = OC.xy(cell)
	local bad = OC.forbidden(gs.board, x, y, color, gs.rule)
	if bad then
		return false, OC.FORBIDDEN_TEXT[bad]
	end
	gs.board[cell] = color
	gs.last = cell
	gs.seq += 1
	gs.moves += 1
	api.emote(side, "mg_place")
	local line = OC.winLine(gs.board, x, y, color, gs.rule)
	if line then
		gs.winLine = line
		publish(gs, api)
		api.event("omokMove", { side = side, cell = cell, color = color, seq = gs.seq, auto = auto == true })
		api.finish(side, "five")
		return true, nil
	end
	if OC.full(gs.board) then
		publish(gs, api)
		api.finish(0, "full")
		return true, nil
	end
	local other = if side == 1 then 2 else 1
	-- an NPC reacts to a strong player move now and then
	if api.isNpc(other) and api.rng:NextNumber() < 0.18 then
		local opp = gs.colorOf[other]
		local _ = opp
		api.line(other, "good")
	end
	startTurn(gs, other, api)
	publish(gs, api)
	api.event("omokMove", { side = side, cell = cell, color = color, seq = gs.seq, auto = auto == true })
	api.push()
	return true, nil
end

function OmokServer.input(gs: any, side: number, p: any, api: any)
	local cell = M.Anti.int(p.cell, 1, SIZE * SIZE)
	if not cell then
		return
	end
	local ok, err = place(gs, side, cell, api, false)
	if not ok and err then
		local pl = api.player(side)
		if pl then
			M.toast(pl, "warn", "둘 수 없는 자리", err)
		end
	end
end

local function randomMove(gs: any, side: number, api: any): number?
	return choose(gs, gs.colorOf[side], "easy", api.rng)
end

function OmokServer.tick(gs: any, now: number, api: any)
	if gs.winLine then
		return
	end
	local side = gs.turn
	if api.isNpc(side) then
		if gs.npcAt > 0 and now >= gs.npcAt then
			gs.npcAt = 0
			local cell = choose(gs, gs.colorOf[side], api.difficulty(side), api.rng)
			if cell then
				place(gs, side, cell, api, false)
			else
				api.finish(0, "full")
			end
		end
		return
	end
	if now >= gs.deadline then
		gs.strikes[side] += 1
		local pl = api.player(side)
		if gs.strikes[side] >= OC.TIMEOUT_STRIKES then
			api.finish(if side == 1 then 2 else 1, "timeout")
			return
		end
		if pl then
			M.toast(pl, "warn", "시간 초과!", "한 번 더 시간을 넘기면 패배예요")
		end
		local cell = randomMove(gs, side, api)
		if cell then
			place(gs, side, cell, api, true)
		end
	end
end

function OmokServer.view(gs: any, side: number): any
	return {
		board = OC.encode(gs.board),
		black = gs.black,
		turn = gs.turn,
		color = if side > 0 then gs.colorOf[side] else 0,
		last = gs.last,
		seq = gs.seq,
		deadline = workspace:GetServerTimeNow() + math.max(0, gs.deadline - os.clock()),
		moveTime = OC.MOVE_TIME,
		strikes = gs.strikes,
		rule = gs.rule,
		win = gs.winLine,
	}
end

function OmokServer.cleanup(gs: any, api: any)
	-- leave the final position on the table for a while (passers-by see how it ended), then clear it
	local seq = gs.seq
	task.delay(12, function()
		local model = api.match.station.model
		if model:GetAttribute("OmokSeq") == seq and not api.match.station.match then
			model:SetAttribute("OmokBoard", "")
			model:SetAttribute("OmokLast", 0)
			model:SetAttribute("OmokWin", "")
			model:SetAttribute("OmokSeq", 0)
		end
	end)
end

return OmokServer
