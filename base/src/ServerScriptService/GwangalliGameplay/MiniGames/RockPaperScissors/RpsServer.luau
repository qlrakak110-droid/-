--!strict
-- RockPaperScissors/RpsServer: 가위바위보, 3판 2선승 (draws are replayed). Server only.
-- Round: "3 · 2 · 1 · 가위바위보!" (server time tShoot), choices are accepted from the start of the
-- count until tShoot + GRACE; nobody ever receives the other side's choice before the reveal.
-- A side that did not choose gets a random hand (marked "늦음"). Both characters pump their fists
-- during the count and show the hand at the reveal (client emotes + a hand glyph over the hand).
-- NPC: 초보 random, 일반 slightly rock-heavy, 고수 counters the player's most frequent hand.
-- Move payload: { hand = 1 (✊ 바위) | 2 (✋ 보) | 3 (✌️ 가위) }.

local RpsServer = {}

local M: any = nil

local WIN_TO = 2
local COUNT = 3.0
local GRACE = 0.8
local SHOW = 2.4
local MAX_ROUNDS = 9

-- beats[a] = the hand that a beats (rock 1 beats scissors 3, paper 2 beats rock 1, scissors 3 beats paper 2)
local BEATS = { [1] = 3, [2] = 1, [3] = 2 }
local NAMES = { "바위", "보", "가위" }

function RpsServer.init(m: any)
	M = m
end

function RpsServer.new(_match: any, _api: any): any
	return {
		round = 0,
		score = { 0, 0 },
		phase = "idle",
		tShoot = 0,
		revealAt = 0,
		nextAt = 0,
		choice = {} :: { [number]: number },
		late = {} :: { [number]: boolean },
		last = nil :: any,
		history = {} :: { [number]: { number } },
		npcAt = 0,
		over = false,
	}
end

local function npcHand(gs: any, side: number, api: any): number
	local d = api.difficulty(side)
	local opp = if side == 1 then 2 else 1
	if d == "hard" and api.rng:NextNumber() < 0.7 then
		local h = gs.history[opp] or {}
		local counts = { 0, 0, 0 }
		for k = math.max(1, #h - 5), #h do
			counts[h[k]] += 1
		end
		local fav, best = api.rng:NextInteger(1, 3), -1
		for hand = 1, 3 do
			if counts[hand] > best then
				fav, best = hand, counts[hand]
			end
		end
		-- play what beats their favourite
		for hand = 1, 3 do
			if BEATS[hand] == fav then
				return hand
			end
		end
	elseif d == "normal" and api.rng:NextNumber() < 0.25 then
		return 1
	end
	return api.rng:NextInteger(1, 3)
end

local function startRound(gs: any, api: any)
	gs.round += 1
	gs.phase = "count"
	gs.choice = {}
	gs.late = {}
	gs.last = nil
	gs.tShoot = os.clock() + COUNT
	gs.revealAt = gs.tShoot + GRACE
	for side = 1, 2 do
		if api.isNpc(side) then
			gs.npcAt = os.clock() + 0.6 + api.rng:NextNumber() * (COUNT - 0.4)
		end
		api.emote(side, "mg_rps_pump")
	end
	api.score(string.format("%d : %d", gs.score[1], gs.score[2]))
	api.event("rpsRound", { round = gs.round, tShoot = api.toServer(gs.tShoot), grace = GRACE })
	api.push()
end

function RpsServer.begin(gs: any, api: any)
	startRound(gs, api)
end

function RpsServer.input(gs: any, side: number, p: any, api: any)
	if gs.phase ~= "count" or gs.choice[side] then
		return
	end
	local hand = M.Anti.int(p.hand, 1, 3)
	if not hand then
		return
	end
	if os.clock() > gs.revealAt then
		return
	end
	gs.choice[side] = hand
	-- confirm to that player only
	local pl = api.player(side)
	if pl then
		M.fire(pl, M.MS.Kinds.event, { id = api.match.id, e = "rpsPicked", hand = hand })
	end
end

local function reveal(gs: any, api: any)
	for side = 1, 2 do
		if not gs.choice[side] then
			gs.choice[side] = api.rng:NextInteger(1, 3)
			gs.late[side] = not api.isNpc(side)
		end
		local h = gs.history[side]
		if not h then
			h = {}
			gs.history[side] = h
		end
		table.insert(h, gs.choice[side])
	end
	local c1, c2 = gs.choice[1], gs.choice[2]
	local w = 0
	if c1 ~= c2 then
		w = if BEATS[c1] == c2 then 1 else 2
	end
	if w > 0 then
		gs.score[w] += 1
	end
	gs.phase = "show"
	gs.last = { c1 = c1, c2 = c2, w = w, late1 = gs.late[1] == true, late2 = gs.late[2] == true }
	gs.nextAt = os.clock() + SHOW
	for side = 1, 2 do
		api.emote(side, "mg_rps_show")
	end
	api.event("rpsReveal", { c1 = c1, c2 = c2, w = w, s1 = gs.score[1], s2 = gs.score[2], late1 = gs.late[1] == true, late2 = gs.late[2] == true })
	api.score(string.format("%d : %d", gs.score[1], gs.score[2]))
	for side = 1, 2 do
		if api.isNpc(side) and w ~= 0 then
			if w == side then
				api.say(side, NAMES[gs.choice[side]] .. "! 이겼다~", 2)
			elseif api.rng:NextNumber() < 0.5 then
				api.line(side, "good")
			end
		end
	end
	api.push()
end

function RpsServer.tick(gs: any, now: number, api: any)
	if gs.over then
		return
	end
	if gs.phase == "count" then
		for side = 1, 2 do
			if api.isNpc(side) and not gs.choice[side] and now >= gs.npcAt then
				gs.choice[side] = npcHand(gs, side, api)
			end
		end
		if now >= gs.revealAt or (now >= gs.tShoot and gs.choice[1] and gs.choice[2]) then
			reveal(gs, api)
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

function RpsServer.view(gs: any, side: number): any
	return {
		round = gs.round,
		score = gs.score,
		phase = gs.phase,
		tShoot = workspace:GetServerTimeNow() + (gs.tShoot - os.clock()),
		grace = GRACE,
		mine = if side > 0 then gs.choice[side] else nil,
		last = gs.last,
		winTo = WIN_TO,
	}
end

return RpsServer
