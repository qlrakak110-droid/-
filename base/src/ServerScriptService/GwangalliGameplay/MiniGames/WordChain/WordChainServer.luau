--!strict
-- WordChain/WordChainServer: 끝말잇기 at a beach table (server only; rules in the shared WordRules).
--   * The server opens with a friendly start word ("바다"), a random side answers first.
--   * Each answer: WordRules.TURN_TIME (10 s). Valid = Hangul, 2+ syllables, starts with the last
--     syllable of the current word (or its 두음법칙 form), not used in this game, in the dictionary
--     (WordDictionary), not blocked, and unchanged by Roblox text filtering (TextService, fails
--     closed on live servers). A wrong answer is refused with the reason and the clock keeps running;
--     no valid answer in time = 패배.
--   * Accepted words appear as a speech bubble over the speaker's head for everyone nearby.
-- NPC: answers from the dictionary after a "thinking" pause; 초보 sometimes cannot think of one
-- (and loses on time), 고수 likes 한방 words (few followers).
-- Move payload: { word = string }.

local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local WordChainServer = {}

local M: any = nil
local WR: any = nil
local Dict: any = nil

function WordChainServer.init(m: any)
	M = m
	WR = m.WR
	Dict = require(script.Parent:WaitForChild("WordDictionary")) :: any
	Dict.init(WR, script.Parent:FindFirstChild("WordList") :: ModuleScript?)
	WordChainServer.Dict = Dict
end

-- Roblox text filtering. true = safe to show. Studio (where filtering is often unavailable) falls back
-- to the local dictionary + block list; live servers fail closed.
local function filtered(text: string, userId: number): boolean
	local ok, res = pcall(function()
		local r = TextService:FilterStringAsync(text, userId, Enum.TextFilterContext.PublicChat)
		return r:GetNonChatStringForBroadcastAsync()
	end)
	if ok and type(res) == "string" then
		return res == text
	end
	return RunService:IsStudio() and Dict.hasLocal(text)
end

function WordChainServer.new(match: any, api: any): any
	return {
		current = "",
		chain = {} :: { { w: string, side: number } },
		used = {} :: { [string]: boolean },
		turn = api.rng:NextInteger(1, 2),
		deadline = 0,
		npcAt = 0,
		npcGiveUp = false,
		busy = {} :: { [number]: boolean },
		seq = 0,
		over = false,
	}
end

local function npcPlan(gs: any, side: number, api: any)
	local d = api.difficulty(side)
	local lo, hi = 2.0, 5.5
	if d == "normal" then
		lo, hi = 1.8, 4.5
	elseif d == "hard" then
		lo, hi = 1.2, 3.2
	end
	gs.npcAt = os.clock() + lo + api.rng:NextNumber() * (hi - lo)
	-- the longer the game, the harder it is to think of one (easy NPCs tire first)
	local giveUp = if d == "easy" then 0.08 + #gs.chain * 0.02 elseif d == "normal" then 0.03 + #gs.chain * 0.008 else 0.005 * #gs.chain
	gs.npcGiveUp = api.rng:NextNumber() < giveUp
	if api.rng:NextNumber() < 0.3 then
		api.line(side, "think")
	end
end

local function startTurn(gs: any, side: number, api: any)
	gs.turn = side
	gs.deadline = os.clock() + WR.TURN_TIME
	gs.npcAt = 0
	if api.isNpc(side) then
		npcPlan(gs, side, api)
	end
	api.turn(side)
	api.score(string.format("%d단어", #gs.chain))
end

function WordChainServer.begin(gs: any, api: any)
	gs.current = Dict.startWord(api.rng)
	gs.used[gs.current] = true
	table.insert(gs.chain, { w = gs.current, side = 0 })
	startTurn(gs, gs.turn, api)
	api.attr("WordCurrent", gs.current)
	api.event("wordStart", { word = gs.current, first = gs.turn })
end

local function accept(gs: any, side: number, word: string, api: any)
	gs.used[word] = true
	gs.current = word
	gs.seq += 1
	table.insert(gs.chain, { w = word, side = side })
	api.say(side, word, 2.5)
	api.attr("WordCurrent", word)
	api.event("word", { side = side, word = word, n = #gs.chain })
	local other = if side == 1 then 2 else 1
	-- nobody (in the dictionary) can follow this word: the opponent still gets the full time, but the
	-- NPC knows it is lost
	startTurn(gs, other, api)
	api.push()
end

local function reject(gs: any, side: number, reason: string, api: any)
	local pl = api.player(side)
	if pl then
		M.fire(pl, M.MS.Kinds.event, { id = api.match.id, e = "wordReject", reason = reason })
	end
end

function WordChainServer.input(gs: any, side: number, p: any, api: any)
	if gs.over or gs.turn ~= side or gs.busy[side] then
		return
	end
	local word = WR.normalize(p.word)
	local okShape, why = WR.shape(word)
	if not okShape then
		reject(gs, side, why or "올바른 단어가 아니에요", api)
		return
	end
	if not WR.follows(gs.current, word) then
		reject(gs, side, "'" .. WR.hint(gs.current) .. "'(으)로 시작해야 해요", api)
		return
	end
	if gs.used[word] then
		reject(gs, side, "이미 나온 단어예요", api)
		return
	end
	gs.busy[side] = true
	local seq = gs.seq
	local userId = if api.player(side) then (api.player(side) :: Player).UserId else 0
	task.spawn(function()
		local known = Dict.has(word)
		local clean = known and filtered(word, userId)
		gs.busy[side] = nil
		-- the world may have moved on while we were checking (time out, forfeit)
		if gs.over or gs.seq ~= seq or gs.turn ~= side or api.match.state ~= "playing" or os.clock() > gs.deadline + 0.3 then
			return
		end
		if not known then
			reject(gs, side, "사전에 없는 단어예요", api)
		elseif not clean then
			reject(gs, side, "사용할 수 없는 단어예요", api)
		else
			accept(gs, side, word, api)
		end
	end)
end

local function npcAnswer(gs: any, side: number, api: any): string?
	local list = Dict.starting(WR.starts(gs.current))
	local options = {}
	for _, w in list do
		if not gs.used[w] then
			table.insert(options, w)
		end
	end
	if #options == 0 then
		return nil
	end
	if api.difficulty(side) == "hard" and api.rng:NextNumber() < 0.7 then
		-- 한방 hunting: the word that leaves the fewest answers
		local best, bestN = options[1], math.huge
		for k = 1, math.min(#options, 60) do
			local w = options[api.rng:NextInteger(1, #options)]
			local n = Dict.followers(w)
			if n < bestN then
				best, bestN = w, n
			end
			local _ = k
		end
		return best
	end
	return options[api.rng:NextInteger(1, #options)]
end

function WordChainServer.tick(gs: any, now: number, api: any)
	if gs.over then
		return
	end
	local side = gs.turn
	if now >= gs.deadline and not gs.busy[side] then
		gs.over = true
		api.event("wordTimeout", { side = side })
		if api.isNpc(side) then
			api.say(side, "아... 모르겠다!", 2.5)
		end
		api.finish(if side == 1 then 2 else 1, "timeout")
		return
	end
	if api.isNpc(side) and gs.npcAt > 0 and now >= gs.npcAt then
		gs.npcAt = 0
		if gs.npcGiveUp then
			api.say(side, "음... 음...", 3)
			return
		end
		local w = npcAnswer(gs, side, api)
		if w then
			accept(gs, side, w, api)
		else
			api.say(side, "그걸로 시작하는 단어가... 없는데?", 3)
		end
	end
end

function WordChainServer.view(gs: any, side: number): any
	local chain = {}
	for k = math.max(1, #gs.chain - 9), #gs.chain do
		local c = gs.chain[k]
		table.insert(chain, { w = c.w, s = c.side })
	end
	return {
		current = gs.current,
		hint = WR.hint(gs.current),
		starts = WR.starts(gs.current),
		turn = gs.turn,
		deadline = workspace:GetServerTimeNow() + math.max(0, gs.deadline - os.clock()),
		turnTime = WR.TURN_TIME,
		chain = chain,
		count = #gs.chain - 1,
	}
end

function WordChainServer.cleanup(_gs: any, api: any)
	api.attr("WordCurrent", "")
end

return WordChainServer
