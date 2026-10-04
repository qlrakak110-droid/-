--!strict
-- MiniGames (server feature module of GwangalliGameplay; docs/MINIGAMES.md): 광안리 해변 미니게임 거리.
-- Players meet other players or NPCs on the promenade, put up in-game 원 and play 오목 / 끝말잇기 /
-- 가위바위보 / 순발력 / 기억력 / 숫자 맞히기 / 타이밍 / 퀴즈 at real tables in the world.
--
-- Wiring: GwangalliGameplay.server's FEATURE_MODULES list contains "MiniGames"; it requires this
-- module and calls init(ctx), onLoaded(player), onCharacter(player, character), onLeave(player)
-- (onLeave runs BEFORE the profile is saved, so a match settled there is saved with the profile).
-- ctx gives the money API (ctx.spend / ctx.ledger / ctx.canAfford), notifications and stats.
--
-- Children (one job each; new games are one more module in M.GAME_MODULES):
--   MiniGameManager    stations, seats, match life cycle, leave / forfeit rules, rematch, spectators
--   MatchmakingService challenges, open calls (상대 찾기), walking to an accepted table
--   BetService         escrow: the only money path (in-game 원 only, no Robux, settle exactly once)
--   RewardService      records, Elo rating, 브론즈..다이아 ranks, DataStore
--   AntiCheat          rate limits, payload checks, distance checks, latency for timing games
--   StationBuilder     the tables / machines on the promenade
--   NpcHosts           the NPCs who wait at the tables
--   <Game>/<Game>Server  one module per game: new / begin / input / tick / view / cleanup
--
-- Remotes (ReplicatedStorage.GwangalliMiniGames): Request (client -> server: action, payload),
-- Update (server -> client: kind, payload), Query (RemoteFunction: "record" | "board").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiniGames = {}

local function child(path: { string }): Instance
	local node: Instance = script
	for _, n in path do
		local c = node:FindFirstChild(n)
		if not c then
			error("[MiniGames] missing module " .. table.concat(path, "/"))
		end
		node = c
	end
	return node
end

local M: any = {}
M.GAME_MODULES = {
	omok = { "Omok", "OmokServer" },
	wordchain = { "WordChain", "WordChainServer" },
	rps = { "RockPaperScissors", "RpsServer" },
	reaction = { "ReactionGame", "ReactionServer" },
	memory = { "MemoryGame", "MemoryServer" },
	numberguess = { "NumberGuess", "NumberGuessServer" },
	timing = { "TimingGame", "TimingServer" },
	quiz = { "Quiz", "QuizServer" },
}

local started = false

local ACTION_RATE: { [string]: { number } } = {
	-- tokens per second, burst
	move = { 8, 12 },
	ping = { 2, 4 },
	default = { 2, 5 },
}

function MiniGames.init(ctx: any)
	if started then
		return
	end
	started = true
	local sharedModule = ReplicatedStorage:WaitForChild("GwangalliMiniGamesShared", 30)
	assert(sharedModule and sharedModule:IsA("ModuleScript"), "ReplicatedStorage.GwangalliMiniGamesShared missing")
	local MS = require(sharedModule) :: any
	M.MS = MS
	M.OC = require(sharedModule:WaitForChild("OmokConfig")) :: any
	M.WR = require(sharedModule:WaitForChild("WordRules")) :: any
	M.ctx = ctx
	M.G = ctx.G

	-- remotes (folder parented last so clients that find it find every remote)
	local old = ReplicatedStorage:FindFirstChild(MS.FolderName)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = MS.FolderName
	local request = Instance.new("RemoteEvent")
	request.Name = MS.Remote.Request
	request.Parent = folder
	local update = Instance.new("RemoteEvent")
	update.Name = MS.Remote.Update
	update.Parent = folder
	local query = Instance.new("RemoteFunction")
	query.Name = MS.Remote.Query
	query.Parent = folder
	folder.Parent = ReplicatedStorage

	function M.fire(player: Player, kind: string, payload: any)
		if player.Parent == Players then
			update:FireClient(player, kind, payload)
		end
	end
	function M.toast(player: Player, kind: string, title: string, body: string?)
		M.fire(player, MS.Kinds.toast, { kind = kind, title = title, body = body or "" })
	end
	-- speech bubble over a head part, sent to the players who can see it
	function M.say(head: BasePart, text: string, dur: number?)
		for _, p in Players:GetPlayers() do
			if M.Anti.near(p, head.Position, 90) then
				update:FireClient(p, MS.Kinds.say, { part = head, text = text, dur = dur or 3 })
			end
		end
	end

	M.Anti = require(child({ "AntiCheat" }) :: ModuleScript) :: any
	M.Bet = require(child({ "BetService" }) :: ModuleScript) :: any
	M.Reward = require(child({ "RewardService" }) :: ModuleScript) :: any
	M.Builder = require(child({ "StationBuilder" }) :: ModuleScript) :: any
	M.Npc = require(child({ "NpcHosts" }) :: ModuleScript) :: any
	M.Match = require(child({ "MatchmakingService" }) :: ModuleScript) :: any
	M.Manager = require(child({ "MiniGameManager" }) :: ModuleScript) :: any
	for _, svc in { M.Anti, M.Bet, M.Reward, M.Builder, M.Npc, M.Match, M.Manager } do
		svc.init(M)
	end
	M.games = {}
	for id, path in M.GAME_MODULES do
		local ok, res = pcall(function()
			return require(child(path) :: ModuleScript)
		end)
		if ok and type(res) == "table" then
			if type(res.init) == "function" then
				res.init(M)
			end
			M.games[id] = res
		else
			warn("[MiniGames] game " .. id .. " failed to load: " .. tostring(res))
		end
	end

	-- world (deferred: the place's own parts are in by now, but let the other features settle first)
	task.defer(function()
		local list = M.Builder.build()
		M.Manager.setStations(list)
		local npcs = 0
		for _, st in list do
			if st.npc and M.Npc.spawn(st) then
				npcs += 1
			end
			M.Manager.publishStation(st)
		end
		print(string.format("[MiniGames] ready: %d stations, %d NPC hosts, %d games", #list, npcs, (function()
			local n = 0
			for _ in M.games do
				n += 1
			end
			return n
		end)()))
	end)

	request.OnServerEvent:Connect(function(player: Player, action: any, payload: any)
		MiniGames.handle(player, action, payload)
	end)
	query.OnServerInvoke = function(player: Player, what: any): any
		if not M.Anti.allow(player, "query", 1, 4) then
			return nil
		end
		if what == "record" then
			return M.Reward.snapshot(player)
		elseif what == "board" then
			return M.Reward.board(10)
		end
		return nil
	end

	-- loops
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.1)
			local now = os.clock()
			local ok, err = pcall(M.Manager.tick, now)
			if not ok then
				warn("[MiniGames] tick: " .. tostring(err))
			end
			local ok2, err2 = pcall(M.Match.tick, now)
			if not ok2 then
				warn("[MiniGames] matchmaking tick: " .. tostring(err2))
			end
			if now - last >= 1 then
				last = now
				pcall(M.Manager.slowTick)
				-- latency probes for everyone in a match (cheap: one event per player per 3 s)
				for _, match in M.Manager.activeMatches() do
					if (match.stateAt :: number) > 0 then
						for _, s in match.sides do
							if s.kind == "player" and s.player and (math.floor(now) % 3 == 0) then
								M.Anti.sendPing(s.player)
							end
						end
					end
				end
			end
		end
	end)

	game:BindToClose(function()
		-- every stake held by a running match goes back before the profiles are saved
		M.Bet.refundAll("서버 종료")
	end)
end

-- Request router: shape + rate checks here, rules in the services.
function MiniGames.handle(player: Player, action: any, payload: any)
	local MS = M.MS
	if not MS or type(action) ~= "string" or not MS.Actions[action] then
		return
	end
	if payload == nil then
		payload = {}
	end
	if not M.Anti.payload(payload) then
		M.Anti.strike(player, "payload", action)
		return
	end
	local rate = ACTION_RATE[action] or ACTION_RATE.default
	if not M.Anti.allow(player, action == "move" and "move" or (action == "ping" and "ping" or "act"), rate[1], rate[2]) then
		return
	end
	if action == "ping" then
		M.Anti.onPong(player, payload)
		return
	end
	if action == "move" then
		M.Manager.input(player, payload)
		return
	end
	if not M.ctx.Profiles.get(player) then
		M.toast(player, "info", "잠시만요", "프로필을 불러오는 중이에요")
		return
	end
	local ok, err = pcall(MiniGames.act, player, action, payload)
	if not ok then
		warn(string.format("[MiniGames] %s from %s failed: %s", action, player.Name, tostring(err)))
	end
end

local function needStation(player: Player, p: any): any?
	local st = M.Manager.station(p.station)
	if not st then
		return nil
	end
	if not M.Anti.near(player, st.frame.Position, M.MS.T.nearStation + 4) then
		M.toast(player, "info", "너무 멀어요", "테이블 가까이 가서 눌러 주세요")
		return nil
	end
	return st
end

local function busyVehicle(player: Player): boolean
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	local seat = h and h.SeatPart
	return seat ~= nil and seat:IsA("VehicleSeat")
end

function MiniGames.act(player: Player, action: string, p: any)
	local MS = M.MS
	local Manager = M.Manager
	if action == "sit" or action == "open" or action == "practice" or action == "challenge" then
		local st = needStation(player, p)
		if not st then
			return
		end
		if busyVehicle(player) or not M.Anti.alive(player) then
			M.toast(player, "info", "지금은 안 돼요", "차에서 내려서 해 주세요")
			return
		end
		local stake = p.stake
		if action == "practice" then
			if not st.npc or not MS.isNpcStake(st.npc.difficulty, stake) then
				M.Anti.strike(player, "stake", tostring(stake))
				return
			end
			local ok, err = Manager.practice(player, st, stake)
			if not ok and err then
				M.toast(player, "warn", "시작할 수 없어요", err)
			end
			return
		end
		if not MS.isStake(stake) then
			M.Anti.strike(player, "stake", tostring(stake))
			return
		end
		-- already waiting at this very table (e.g. 게임 참가, then 친구에게 신청): keep the seat
		local ps = Manager.stateOf(player)
		local waitingHere = ps and ps.kind == "wait" and ps.station == st
		if waitingHere and st.waiting.stake ~= stake then
			M.toast(player, "info", "참가비가 달라요", "앉은 자리의 참가비는 " .. MS.stakeLabel(st.waiting.stake) .. "예요")
			return
		end
		if not waitingHere then
			local ok, err = Manager.sit(player, st, stake)
			if not ok then
				if err then
					M.toast(player, "warn", "앉을 수 없어요", err)
				end
				return
			end
		end
		if action == "open" then
			local n = M.Match.openCall(player, st, stake)
			M.toast(player, "info", "상대 찾는 중", if n > 0 then n .. "명에게 알렸어요. 지나가는 사람도 도전할 수 있어요" else "지금은 접속한 사람이 없어요. 지나가는 사람을 기다려요")
		elseif action == "challenge" then
			local target = if type(p.target) == "number" then Players:GetPlayerByUserId(p.target) else nil
			if not target then
				M.toast(player, "warn", "신청 실패", "상대를 찾을 수 없어요")
				return
			end
			local ok, err = M.Match.challenge(player, target, st, stake)
			if ok then
				M.toast(player, "info", "대결 신청", target.DisplayName .. "님에게 " .. MS.GAMES[st.game].name .. " 대결을 신청했어요")
			else
				M.toast(player, "warn", "신청 실패", err or "")
			end
		else
			M.toast(player, "info", MS.GAMES[st.game].name .. " 자리에 앉았어요", "지나가는 사람이 도전할 수 있어요 · " .. MS.stakeLabel(stake))
		end
	elseif action == "join" then
		local st = needStation(player, p)
		if st then
			local ok, err = Manager.joinWaiting(st, player)
			if not ok and err then
				M.toast(player, "warn", "도전할 수 없어요", err)
			end
		end
	elseif action == "respond" then
		local id = M.Anti.int(p.id, 1, 1e9)
		if id then
			M.Match.respond(player, id, p.accept == true)
		end
	elseif action == "spectate" then
		local st = M.Manager.station(p.station)
		if st and M.Anti.near(player, st.frame.Position, MS.T.spectate) then
			local ok, err = Manager.spectate(player, st)
			if not ok and err then
				M.toast(player, "info", "관전", err)
			end
		end
	elseif action == "unspectate" then
		Manager.unspectate(player)
	elseif action == "leave" then
		Manager.leave(player, "leave")
	elseif action == "forfeit" then
		local ps = Manager.stateOf(player)
		if ps and ps.match then
			Manager.sideLeft(ps.match, ps.side, "forfeit")
		end
	elseif action == "rematch" then
		local ps = Manager.stateOf(player)
		if ps and ps.match then
			Manager.rematch(ps.match, ps.side)
		end
	elseif action == "draw" then
		local ps = Manager.stateOf(player)
		if ps and ps.match then
			Manager.offerDraw(ps.match, ps.side, p.offer == true)
		end
	end
end

function MiniGames.onLoaded(player: Player)
	if M.Reward then
		M.Reward.load(player)
	end
end

function MiniGames.onCharacter(player: Player, _character: Model)
	if M.Manager then
		M.Manager.onCharacter(player)
	end
end

function MiniGames.onLeave(player: Player)
	if not M.Manager then
		return
	end
	pcall(M.Match.onLeave, player)
	pcall(M.Manager.onLeave, player)
	M.Reward.release(player)
end

-- for tests / admin tools
MiniGames._M = M

return MiniGames
