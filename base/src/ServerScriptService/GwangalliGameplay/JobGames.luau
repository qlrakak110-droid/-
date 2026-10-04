--!nocheck
-- GwangalliGameplay/JobGames: server side of the 알바 mini-game ROUNDS (docs/JOBS.md).
--   * one active round per player: the answer key (`secret`) never leaves the server, the client
--     only gets `view`;
--   * timing windows: a round opens when the server sends it (os.clock), the answer must arrive
--     within timeLimit + JS.NET_SLACK and not faster than JS.MIN_ROUND_SECONDS;
--   * one answer per round (duplicates / stale taskIds are dropped), results are scores 0..1 from
--     JS.check[game] — the pay is applied by Jobs.luau (combo, speed bonus, health multiplier).
-- Pure except for os.clock and the Random injected by Jobs.init, so the Lune unit test can drive it.

local JobGames = {}

local JS: any
local rng: any
local clock: () -> number = os.clock

type Round = {
	taskId: string,
	game: string,
	secret: any,
	view: any,
	timeLimit: number,
	startedAt: number,
	answered: boolean,
}

-- active rounds by player (exported so the simulator / tests can read them; server only)
JobGames.active = {} :: { [any]: Round }

function JobGames.init(opts: any)
	JS = opts.JS
	rng = opts.rng or Random.new()
	if type(opts.clock) == "function" then
		clock = opts.clock
	end
end

local function rand(n: number): number
	return rng:NextInteger(1, math.max(1, n))
end

-- Starts a round for `player`. info: extra generator input (today, pickups / drops, basePay).
-- Returns the round, or nil + reason when the game id is unknown.
function JobGames.start(player: any, taskId: string, game: string, info: any?, timeLimit: number?): (Round?, string?)
	local def = JS.GAMES[game]
	local gen = JS.gen[game]
	if not def or not gen then
		return nil, "unknown game " .. tostring(game)
	end
	local ok, res = pcall(gen, rand, info or {})
	if not ok or type(res) ~= "table" or not res.secret or not res.view then
		return nil, "generator failed: " .. tostring(res)
	end
	local round: Round = {
		taskId = taskId,
		game = game,
		secret = res.secret,
		view = res.view,
		timeLimit = tonumber(timeLimit) or def.timeLimit,
		startedAt = clock(),
		answered = false,
	}
	JobGames.active[player] = round
	return round, nil
end

function JobGames.current(player: any): Round?
	return JobGames.active[player]
end

-- Seconds left (negative = expired, slack included).
function JobGames.timeLeft(player: any): number?
	local r = JobGames.active[player]
	if not r then
		return nil
	end
	return r.timeLimit + JS.NET_SLACK - (clock() - r.startedAt)
end

-- Validates and scores an answer. Returns nil when the answer is not for the active round,
-- otherwise { score, elapsed, timedOut, tooFast, round }.
function JobGames.answer(player: any, taskId: any, answer: any, forced: boolean?): any?
	local r = JobGames.active[player]
	if not r or r.answered then
		return nil
	end
	if not forced and (type(taskId) ~= "string" or taskId ~= r.taskId) then
		return nil
	end
	local elapsed = clock() - r.startedAt
	r.answered = true
	JobGames.active[player] = nil
	local out = { score = 0, elapsed = elapsed, timedOut = false, tooFast = false, round = r }
	if elapsed > r.timeLimit + JS.NET_SLACK then
		out.timedOut = true
		return out
	end
	if not forced and elapsed < JS.MIN_ROUND_SECONDS and r.game ~= "order" then
		out.tooFast = true
		return out
	end
	local check = JS.check[r.game]
	local ok, score = pcall(check, r.secret, r.view, answer)
	if ok and type(score) == "number" and score == score then
		out.score = math.clamp(score, 0, 1)
	end
	return out
end

function JobGames.cancel(player: any)
	JobGames.active[player] = nil
end

-- The payload the client needs to show the round (no secret).
function JobGames.payload(r: Round): any
	local def = JS.GAMES[r.game]
	return {
		taskId = r.taskId,
		game = r.game,
		title = def and def.title or r.game,
		icon = def and def.icon or "🎮",
		hint = def and def.hint or "",
		view = r.view,
		timeLimit = r.timeLimit,
		timeLeft = math.max(0, r.timeLimit - (clock() - r.startedAt)),
	}
end

return JobGames
