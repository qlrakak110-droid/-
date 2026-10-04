--!strict
-- Quiz/QuizServer: 퀴즈 대결 (server only). QUESTIONS questions from QuizBank (choices shuffled per
-- match, the answer index never leaves the server before the reveal). Each question: QTIME seconds,
-- one answer per player; a wrong answer locks you out of that question. The faster CORRECT answer
-- scores 1 point. Speeds are compared after latency compensation (like TimingServer: the client's
-- own elapsed time is used when it is within the allowance of the server's estimate), and the server
-- waits SETTLE seconds after the first correct answer so a laggier but faster player can still win.
-- Tie after QUESTIONS -> up to 3 sudden-death questions, then a draw.
-- NPC: accuracy by difficulty and question difficulty, answers after 2-7 s.
-- Move payload: { q = question number, choice = 1..4, t = seconds since the question appeared }.

local QuizServer = {}

local M: any = nil
local BANK: { any } = {}

local QUESTIONS = 5
local QTIME = 10
local SETTLE = 0.45
local SHOW = 2.6
local MAX_EXTRA = 3

function QuizServer.init(m: any)
	M = m
	local ok, bank = pcall(require, script.Parent:WaitForChild("QuizBank"))
	if ok and type(bank) == "table" then
		BANK = bank
	else
		warn("[MiniGames] QuizBank failed to load: " .. tostring(bank))
	end
end

local function pickQuestions(api: any, n: number): { any }
	local idx = {}
	for i = 1, #BANK do
		idx[i] = i
	end
	for i = #idx, 2, -1 do
		local j = api.rng:NextInteger(1, i)
		idx[i], idx[j] = idx[j], idx[i]
	end
	local out = {}
	for k = 1, math.min(n, #idx) do
		local q = BANK[idx[k]]
		-- shuffle the choices, remember where the answer went
		local order = { 1, 2, 3, 4 }
		for i = 4, 2, -1 do
			local j = api.rng:NextInteger(1, i)
			order[i], order[j] = order[j], order[i]
		end
		local choices = {}
		local answer = 1
		for pos, from in order do
			choices[pos] = q.c[from]
			if from == q.a then
				answer = pos
			end
		end
		table.insert(out, { q = q.q, c = choices, a = answer, d = q.d, tag = q.tag })
	end
	return out
end

function QuizServer.new(_match: any, api: any): any
	return {
		list = pickQuestions(api, QUESTIONS + MAX_EXTRA),
		qi = 0,
		phase = "idle",
		startAt = 0,
		deadline = 0,
		settleAt = 0,
		nextAt = 0,
		answers = {} :: { [number]: { c: number, t: number, ok: boolean } },
		npcPlan = {} :: { [number]: { at: number, c: number } },
		score = { 0, 0 },
		last = nil :: any,
		over = false,
	}
end

local function startQuestion(gs: any, api: any)
	gs.qi += 1
	local q = gs.list[gs.qi]
	if not q then
		gs.over = true
		api.finish(if gs.score[1] > gs.score[2] then 1 elseif gs.score[2] > gs.score[1] then 2 else 0, "points")
		return
	end
	gs.phase = "q"
	gs.answers = {}
	gs.settleAt = 0
	gs.startAt = os.clock()
	gs.deadline = gs.startAt + QTIME
	gs.last = nil
	for side = 1, 2 do
		if api.isNpc(side) then
			local d = api.difficulty(side)
			local acc = (if d == "hard" then 0.9 elseif d == "normal" then 0.72 else 0.52) - (q.d - 1) * 0.07
			local c = q.a
			if api.rng:NextNumber() > acc then
				c = (q.a % 4) + 1
			end
			local lo = if d == "hard" then 1.8 elseif d == "normal" then 2.6 else 3.4
			gs.npcPlan[side] = { at = gs.startAt + lo + api.rng:NextNumber() * 4.0, c = c }
		end
	end
	api.score(string.format("%d : %d", gs.score[1], gs.score[2]))
	api.event("quizQ", { qi = gs.qi, q = q.q, c = q.c, deadline = api.toServer(gs.deadline), extra = gs.qi > QUESTIONS })
	api.push()
end

function QuizServer.begin(gs: any, api: any)
	startQuestion(gs, api)
end

local function reveal(gs: any, api: any)
	local q = gs.list[gs.qi]
	local best, bestT = 0, math.huge
	for side = 1, 2 do
		local a = gs.answers[side]
		if a and a.ok and a.t < bestT then
			best, bestT = side, a.t
		end
	end
	if best > 0 then
		gs.score[best] += 1
		api.emote(best, "mg_fist")
		if api.isNpc(best) and api.rng:NextNumber() < 0.5 then
			api.line(best, "win")
		end
	end
	gs.phase = "show"
	gs.nextAt = os.clock() + SHOW
	gs.last = { a = q.a, w = best, c1 = gs.answers[1] and gs.answers[1].c, c2 = gs.answers[2] and gs.answers[2].c }
	api.event("quizReveal", { qi = gs.qi, a = q.a, w = best, c1 = gs.last.c1, c2 = gs.last.c2, s1 = gs.score[1], s2 = gs.score[2] })
	api.score(string.format("%d : %d", gs.score[1], gs.score[2]))
	api.push()
end

local function answer(gs: any, side: number, c: number, t: number, api: any)
	local q = gs.list[gs.qi]
	local ok = c == q.a
	gs.answers[side] = { c = c, t = t, ok = ok }
	local pl = api.player(side)
	if pl then
		M.fire(pl, M.MS.Kinds.event, { id = api.match.id, e = "quizLocked", c = c })
	end
	if ok and gs.settleAt == 0 then
		gs.settleAt = os.clock() + SETTLE
	end
end

function QuizServer.input(gs: any, side: number, p: any, api: any)
	if gs.phase ~= "q" or gs.answers[side] or M.Anti.int(p.q, 1, 100) ~= gs.qi then
		return
	end
	local c = M.Anti.int(p.choice, 1, 4)
	if not c then
		return
	end
	local rtt = api.rtt(side)
	local est = os.clock() - gs.startAt - rtt
	local t = est
	if M.Anti.finite(p.t) and math.abs(p.t - est) <= 0.1 + rtt * 0.5 then
		t = p.t
	end
	answer(gs, side, c, math.max(0, t), api)
end

function QuizServer.tick(gs: any, now: number, api: any)
	if gs.over then
		return
	end
	if gs.phase == "q" then
		for side = 1, 2 do
			local plan = gs.npcPlan[side]
			if api.isNpc(side) and plan and not gs.answers[side] and now >= plan.at then
				answer(gs, side, plan.c, plan.at - gs.startAt, api)
			end
		end
		local both = gs.answers[1] and gs.answers[2]
		if both or now >= gs.deadline or (gs.settleAt > 0 and now >= gs.settleAt) then
			reveal(gs, api)
		end
	elseif gs.phase == "show" and now >= gs.nextAt then
		local a, b = gs.score[1], gs.score[2]
		if gs.qi >= QUESTIONS and a ~= b then
			gs.over = true
			api.finish(if a > b then 1 else 2, "points")
		elseif gs.qi >= QUESTIONS + MAX_EXTRA then
			gs.over = true
			api.finish(0, "points")
		else
			if gs.qi == QUESTIONS then
				api.event("quizSudden", {})
			end
			startQuestion(gs, api)
		end
	end
end

function QuizServer.view(gs: any, side: number): any
	local q = gs.list[gs.qi]
	return {
		qi = gs.qi,
		total = QUESTIONS,
		phase = gs.phase,
		q = q and q.q,
		c = q and q.c,
		deadline = workspace:GetServerTimeNow() + math.max(0, gs.deadline - os.clock()),
		qtime = QTIME,
		score = gs.score,
		mine = if side > 0 and gs.answers[side] then gs.answers[side].c else nil,
		last = gs.last,
	}
end

return QuizServer
