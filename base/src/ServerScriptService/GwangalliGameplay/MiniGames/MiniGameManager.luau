--!strict
-- MiniGames/MiniGameManager: stations, seats and the life of every match (server only).
--
-- A station is free, WAITING (one player seated with a chosen stake: 게임 참가 / 상대 찾기 / a sent
-- challenge) or busy with a MATCH. Match states:
--   seating   both players sit down / step onto their pads, cameras move (MS.T.seatWalk)
--   countdown "3 2 1" on every screen (MS.T.countdown)
--   playing   the game module runs (input / tick / NPC); only now can a game be won or lost
--   result    winner card, money, record; 재대결 votes for MS.T.result seconds, then everyone stands up
-- Money: BetService.hold when the match is created (both stakes checked + taken, rolled back if one
-- fails), BetService.settle exactly once in finish(), BetService.refund for anything cancelled before
-- `playing`. Leaving rules (server decides, never the client):
--   before playing (seating / countdown)        -> cancelled, both stakes back
--   during playing: 기권 button, leaving the server, dying / respawning, walking away from the table
--   (> 22 studs for MS.T.leaveGrace s)           -> the other side wins the pot
--   result                                         -> nothing changes (already settled)
--   server shutdown (BindToClose)                  -> every open escrow is refunded
-- Players are seated with Seat:Sit (the stools are not touch-seatable) and jumping is blocked while
-- seated; the client disables its movement controls for stand games and moves its camera
-- (CameraDirector). Nobody is teleported to a lobby: the match happens at the table in the world.

local Players = game:GetService("Players")

local Manager = {}

local M: any = nil
local MS: any = nil

local stations: { [string]: any } = {}
local stationList: { any } = {}
local matches: { [number]: any } = {}
local nextMatch = 0
type PState = { kind: string, station: any, match: any?, side: number }
local pstate: { [Player]: PState } = {}
local spect: { [Player]: any } = {} -- player -> match they watch
local saved: { [Player]: { jp: number, jh: number } } = {}

function Manager.init(m: any)
	M = m
	MS = m.MS
end

function Manager.setStations(list: { any })
	stationList = list
	for _, s in list do
		stations[s.id] = s
		s.match = nil
		s.waiting = nil
	end
end

function Manager.station(id: any): any?
	if type(id) ~= "string" then
		return nil
	end
	return stations[id]
end

function Manager.stations(): { any }
	return stationList
end

function Manager.isBusy(player: Player): boolean
	return pstate[player] ~= nil
end

function Manager.stateOf(player: Player): PState?
	return pstate[player]
end

-------------------------------------------------------------------------------------------------
-- station public attributes
-------------------------------------------------------------------------------------------------
local function setA(model: Instance, k: string, v: any)
	if model:GetAttribute(k) ~= v then
		model:SetAttribute(k, v)
	end
end

function Manager.publishStation(st: any)
	local m = st.model
	local match = st.match
	if match then
		setA(m, "State", if match.state == "result" then "result" else "playing")
		for i = 1, 2 do
			local s = match.sides[i]
			setA(m, "P" .. i, s.name)
			setA(m, "P" .. i .. "Id", if s.kind == "player" then s.userId else -1)
		end
		setA(m, "Stake", match.stake)
		setA(m, "Pot", match.stake * 2)
		setA(m, "MatchId", match.id)
		setA(m, "WaitStake", -1)
		local n = 0
		for _ in match.spectators do
			n += 1
		end
		setA(m, "Spectators", n)
	elseif st.waiting then
		local w = st.waiting
		setA(m, "State", "waiting")
		setA(m, "P1", w.player.DisplayName)
		setA(m, "P1Id", w.player.UserId)
		setA(m, "P2", if w.reservedFor then w.reservedFor.DisplayName else "")
		setA(m, "P2Id", if w.reservedFor then w.reservedFor.UserId else 0)
		setA(m, "WaitStake", w.stake)
		setA(m, "Stake", w.stake)
		setA(m, "Pot", 0)
		setA(m, "Score", "")
		setA(m, "Turn", 0)
		setA(m, "MatchId", 0)
		setA(m, "Spectators", 0)
	else
		setA(m, "State", "idle")
		setA(m, "P1", "")
		setA(m, "P2", "")
		setA(m, "P1Id", 0)
		setA(m, "P2Id", 0)
		setA(m, "WaitStake", -1)
		setA(m, "Stake", 0)
		setA(m, "Pot", 0)
		setA(m, "Score", "")
		setA(m, "Turn", 0)
		setA(m, "MatchId", 0)
		setA(m, "Spectators", 0)
	end
end

-------------------------------------------------------------------------------------------------
-- seats / pads
-------------------------------------------------------------------------------------------------
local function humanoidOf(player: Player): Humanoid?
	local c = player.Character
	return c and c:FindFirstChildOfClass("Humanoid")
end

local function lockJump(player: Player)
	local h = humanoidOf(player)
	if not h or saved[player] then
		return
	end
	saved[player] = { jp = h.JumpPower, jh = h.JumpHeight }
	h.JumpPower = 0
	h.JumpHeight = 0
end

local function unlockJump(player: Player)
	local s = saved[player]
	saved[player] = nil
	local h = humanoidOf(player)
	if s and h then
		h.JumpPower = s.jp
		h.JumpHeight = s.jh
	end
end

local function seatPart(st: any, side: number): BasePart?
	local name = if st.info.kind == "table" then (if side == 1 then "SeatA" else "SeatB") else (if side == 1 then "SpotA" else "SpotB")
	local p = st.model:FindFirstChild(name)
	return if p and p:IsA("BasePart") then p else nil
end

local function placePlayer(player: Player, st: any, side: number)
	local h = humanoidOf(player)
	local spot = seatPart(st, side)
	if not h or not spot then
		return
	end
	lockJump(player)
	if spot:IsA("Seat") then
		local seat = spot :: Seat
		if seat.Occupant and seat.Occupant ~= h then
			return
		end
		seat.CanTouch = false
		pcall(function()
			seat:Sit(h)
		end)
	else
		-- stand games: walk the last few steps onto the pad, then square up
		h:MoveTo(spot.Position)
		task.delay(MS.T.seatWalk * 0.8, function()
			local c = player.Character
			if c and pstate[player] and pstate[player].station == st and c:FindFirstChild("HumanoidRootPart") then
				local root = c:FindFirstChild("HumanoidRootPart") :: BasePart
				local hip = (h :: Humanoid).HipHeight + root.Size.Y / 2
				c:PivotTo(CFrame.new(spot.Position + Vector3.new(0, hip + 0.05, 0)) * spot.CFrame.Rotation)
			end
		end)
	end
	if M.ctx.allowTeleport then
		pcall(M.ctx.allowTeleport, player, 5)
	end
end

local function standUp(player: Player)
	unlockJump(player)
	local h = humanoidOf(player)
	if h and h.SeatPart then
		local seat = h.SeatPart
		for _, st in stationList do
			if seat:IsDescendantOf(st.model) then
				local weld = seat:FindFirstChild("SeatWeld")
				if weld then
					weld:Destroy()
				end
				h.Sit = false
				break
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- views
-------------------------------------------------------------------------------------------------
local function sideView(s: any): any
	return {
		name = s.name,
		userId = if s.kind == "player" then s.userId else -1,
		npc = s.kind == "npc",
		npcId = if s.npc then s.npc.id else nil,
		role = if s.npc then s.npc.role else nil,
		difficulty = if s.npc then MS.DIFFICULTY[s.npc.difficulty] else nil,
		rank = if s.player then (s.player:GetAttribute("MiniRank") or "브론즈") else (if s.npc then MS.DIFFICULTY[s.npc.difficulty] else ""),
		rankIcon = if s.player then (s.player:GetAttribute("MiniRankIcon") or "🥉") else "🤖",
	}
end

local function matchView(match: any, forSide: number): any
	local st = match.station
	local g = nil
	if match.gs and match.def.view then
		local ok, v = pcall(match.def.view, match.gs, forSide)
		g = if ok then v else nil
	end
	return {
		id = match.id,
		game = match.gameId,
		station = st.id,
		state = match.state,
		you = forSide,
		sides = { sideView(match.sides[1]), sideView(match.sides[2]) },
		stake = match.stake,
		pot = match.stake * 2,
		t0 = match.stateAt,
		tEnd = match.stateEnd,
		result = match.result,
		votes = { match.votes[1] == true, match.votes[2] == true },
		drawOffer = match.drawOffer or 0,
		g = g,
	}
end

local function recipients(match: any): { [Player]: number }
	local out: { [Player]: number } = {}
	for i, s in match.sides do
		if s.kind == "player" and s.player and s.player.Parent == Players and not s.gone then
			out[s.player] = i
		end
	end
	for p in match.spectators do
		if p.Parent == Players then
			out[p] = 0
		end
	end
	return out
end

function Manager.broadcast(match: any)
	for p, side in recipients(match) do
		M.fire(p, MS.Kinds.match, matchView(match, side))
	end
end

function Manager.pushGame(match: any)
	if not match.gs or not match.def.view then
		return
	end
	for p, side in recipients(match) do
		local ok, v = pcall(match.def.view, match.gs, side)
		if ok then
			M.fire(p, MS.Kinds.game, { id = match.id, g = v })
		end
	end
end

-- one-shot game event to the match AND passers-by within 100 studs (they see the hands move)
function Manager.event(match: any, e: string, data: { [string]: any }?)
	local pl = data or {}
	pl.id = match.id
	pl.e = e
	pl.station = match.station.id
	local sent: { [Player]: boolean } = {}
	for p in recipients(match) do
		sent[p] = true
		M.fire(p, MS.Kinds.event, pl)
	end
	local pos = match.station.frame.Position
	for _, p in Players:GetPlayers() do
		if not sent[p] and M.Anti.near(p, pos, 100) then
			M.fire(p, MS.Kinds.event, pl)
		end
	end
end

-------------------------------------------------------------------------------------------------
-- game api
-------------------------------------------------------------------------------------------------
local function headOf(match: any, side: number): BasePart?
	local s = match.sides[side]
	if s.kind == "npc" then
		return M.Npc.head(match.station.id)
	end
	local c = s.player and s.player.Character
	local h = c and c:FindFirstChild("Head")
	return if h and h:IsA("BasePart") then h else nil
end

local function makeApi(match: any): any
	local st = match.station
	local api = {}
	api.match = match
	api.rng = Random.new()
	api.now = os.clock
	api.serverNow = function()
		return workspace:GetServerTimeNow()
	end
	-- clock conversion: an os.clock() deadline -> server time (clients count down in server time)
	api.toServer = function(t: number): number
		return workspace:GetServerTimeNow() + (t - os.clock())
	end
	api.finish = function(winner: number, reason: string)
		Manager.finish(match, winner, reason)
	end
	api.push = function()
		Manager.pushGame(match)
	end
	api.event = function(e: string, data: any?)
		Manager.event(match, e, data)
	end
	api.attr = function(k: string, v: any)
		setA(st.model, k, v)
	end
	api.score = function(s: string)
		setA(st.model, "Score", s)
	end
	api.turn = function(side: number)
		setA(st.model, "Turn", side)
	end
	api.isNpc = function(side: number): boolean
		return match.sides[side].kind == "npc"
	end
	api.npc = function(side: number): any?
		return match.sides[side].npc
	end
	api.difficulty = function(side: number): string
		local n = match.sides[side].npc
		return if n then n.difficulty else "normal"
	end
	api.name = function(side: number): string
		return match.sides[side].name
	end
	api.player = function(side: number): Player?
		return match.sides[side].player
	end
	api.rtt = function(side: number): number
		return M.Anti.rtt(match.sides[side].player)
	end
	-- speech bubble over a side (NPC line kinds: think / good / ... ; or literal text)
	api.say = function(side: number, text: string, dur: number?)
		local head = headOf(match, side)
		if head then
			M.say(head, text, dur or 3)
		end
	end
	api.line = function(side: number, kind: string)
		local n = match.sides[side].npc
		if n then
			M.Npc.say(st.id, kind)
		end
	end
	api.emote = function(side: number, name: string)
		local s = match.sides[side]
		if s.kind == "npc" then
			M.Npc.emote(st.id, name)
		else
			Manager.event(match, "emote", { userId = s.userId, name = name })
		end
	end
	return api
end

-------------------------------------------------------------------------------------------------
-- match lifecycle
-------------------------------------------------------------------------------------------------
local function setState(match: any, state: string, duration: number?)
	match.state = state
	match.stateAt = workspace:GetServerTimeNow()
	match.stateEnd = if duration then match.stateAt + duration else 0
	match.stateClock = os.clock()
	match.stateClockEnd = if duration then os.clock() + duration else 0
	Manager.publishStation(match.station)
	Manager.broadcast(match)
end

local function playerSide(player: Player): any
	return { kind = "player", player = player, userId = player.UserId, name = player.DisplayName }
end

local function npcSide(npc: any): any
	return { kind = "npc", npc = npc, name = npc.name, difficulty = npc.difficulty }
end

-- Creates and starts a match. sides = { side1, side2 } (side tables above). -> match | nil, err
function Manager.start(st: any, sides: { any }, stake: number, rematch: boolean?): (any?, string?)
	if st.match then
		return nil, "이미 게임 중인 테이블이에요"
	end
	local def = M.games[st.game]
	if not def then
		return nil, "준비 중인 게임이에요"
	end
	nextMatch += 1
	local match = {
		id = nextMatch,
		gameId = st.game,
		def = def,
		station = st,
		sides = sides,
		stake = stake,
		state = "new",
		stateAt = 0,
		stateEnd = 0,
		stateClock = 0,
		stateClockEnd = 0,
		spectators = {} :: { [Player]: boolean },
		votes = {} :: { [number]: boolean },
		drawOffer = 0,
		result = nil :: any,
		escrow = nil :: any,
		gs = nil :: any,
		api = nil :: any,
		away = {} :: { [number]: number },
	}
	local ok, failed = M.Bet.hold(match)
	if not ok then
		local who = if failed then sides[failed] else nil
		return nil, if who then who.name .. "님의 게임머니가 부족해요 (" .. MS.won(stake) .. ")" else "참가비 처리 실패"
	end
	match.api = makeApi(match)
	st.waiting = nil
	st.match = match
	matches[match.id] = match
	for i, s in sides do
		if s.kind == "player" then
			pstate[s.player] = { kind = "match", station = st, match = match, side = i }
			M.Match.cancelFrom(s.player, "started")
		end
	end
	-- NPC host: plays (its own seat) or steps aside for two players
	if st.host then
		local npcPlays = sides[2].kind == "npc"
		M.Npc.setMode(st.id, if npcPlays then "play" else "aside")
		if npcPlays then
			M.Npc.look(st.id, sides[1].userId)
		end
	end
	local okNew, gs = pcall(def.new, match, match.api)
	if not okNew then
		warn("[MiniGames] " .. st.game .. ".new failed: " .. tostring(gs))
		M.Bet.refund(match, "오류")
		Manager.close(match)
		return nil, "게임을 시작하지 못했어요"
	end
	match.gs = gs
	for i, s in sides do
		if s.kind == "player" then
			placePlayer(s.player, st, i)
		end
	end
	setState(match, "seating", if rematch then 0.8 else MS.T.seatWalk)
	if sides[2].kind == "npc" then
		M.Npc.say(st.id, "start")
	end
	return match, nil
end

function Manager.finish(match: any, winner: number, reason: string)
	if match.state ~= "playing" then
		return
	end
	local net = M.Bet.settle(match, winner)
	if not net then
		return -- already settled: never twice
	end
	local recs = M.Reward.apply(match, winner, net)
	local loser = if winner == 1 then 2 elseif winner == 2 then 1 else 0
	match.result = {
		winner = winner,
		reason = reason,
		net = { net[1] or 0, net[2] or 0 },
		records = { recs[1], recs[2] },
		capped = match.capped == true,
		winnerName = if winner > 0 then match.sides[winner].name else "",
	}
	-- NPC reaction
	for i, s in match.sides do
		if s.kind == "npc" then
			if winner == 0 then
				M.Npc.say(match.station.id, "draw")
				M.Npc.emote(match.station.id, "shrug")
			elseif winner == i then
				M.Npc.say(match.station.id, "win")
				M.Npc.emote(match.station.id, if math.random() < 0.5 then "cheer" else "laugh")
			else
				M.Npc.say(match.station.id, "lose")
				M.Npc.emote(match.station.id, if math.random() < 0.5 then "facepalm" else "clap")
			end
		end
	end
	if winner > 0 then
		match.api.emote(winner, "cheer")
		if loser > 0 and match.sides[loser].kind == "player" then
			match.api.emote(loser, "shrug")
		end
	end
	setState(match, "result", MS.T.result)
	Manager.pushGame(match)
end

-- Before `playing`: cancel with full refund.
function Manager.cancel(match: any, reason: string)
	if match.state == "playing" or match.state == "result" or match.state == "closed" then
		return
	end
	M.Bet.refund(match, reason)
	for _, s in match.sides do
		if s.kind == "player" and s.player.Parent == Players and not s.gone then
			M.toast(s.player, "info", "게임 취소", reason .. " · 참가비는 돌려드렸어요")
		end
	end
	Manager.close(match)
end

function Manager.close(match: any)
	if match.state == "closed" then
		return
	end
	-- safety net: a match must never close holding money
	M.Bet.refund(match, "종료")
	local prev = match.state
	match.state = "closed"
	matches[match.id] = nil
	local st = match.station
	if match.def.cleanup and match.gs then
		pcall(match.def.cleanup, match.gs, match.api)
	end
	for p in recipients(match) do
		M.fire(p, MS.Kinds.closed, { id = match.id })
	end
	for i, s in match.sides do
		if s.kind == "player" then
			local ps = pstate[s.player]
			if ps and ps.match == match then
				pstate[s.player] = nil
			end
			if s.player.Parent == Players then
				standUp(s.player)
			end
		end
		local _ = i
	end
	for p in match.spectators do
		spect[p] = nil
	end
	if st.match == match then
		st.match = nil
	end
	if st.host then
		M.Npc.setMode(st.id, "host")
		M.Npc.look(st.id, 0)
	end
	Manager.publishStation(st)
	local _ = prev
end

-- A player side leaves (button, server leave, death, walking away).
function Manager.sideLeft(match: any, side: number, why: string)
	local s = match.sides[side]
	if match.state == "playing" then
		local other = if side == 1 then 2 else 1
		s.gone = why == "left" -- left the server: no more updates for them
		Manager.finish(match, other, if why == "forfeit" then "forfeit" else "left")
		if s.player and s.player.Parent == Players then
			local ps = pstate[s.player]
			if ps and ps.match == match then
				pstate[s.player] = nil
			end
			standUp(s.player)
			M.fire(s.player, MS.Kinds.closed, { id = match.id, keepResult = why == "forfeit" })
		end
		s.gone = true
	elseif match.state == "result" then
		s.gone = true
		match.votes[side] = nil
		if s.player then
			local ps = pstate[s.player]
			if ps and ps.match == match then
				pstate[s.player] = nil
			end
			if s.player.Parent == Players then
				standUp(s.player)
				M.fire(s.player, MS.Kinds.closed, { id = match.id })
			end
		end
		-- everyone left the result screen: free the table now
		local anyone = false
		for _, o in match.sides do
			if o.kind == "player" and not o.gone then
				anyone = true
			end
		end
		if not anyone then
			Manager.close(match)
		else
			Manager.broadcast(match)
		end
	else
		Manager.cancel(match, s.name .. "님이 자리를 떠났어요")
	end
end

function Manager.rematch(match: any, side: number)
	if match.state ~= "result" or match.sides[side].gone then
		return
	end
	match.votes[side] = true
	local other = if side == 1 then 2 else 1
	if match.sides[other].kind == "npc" then
		match.votes[other] = true
	end
	Manager.broadcast(match)
	for i, s in match.sides do
		if not match.votes[i] or s.gone then
			if s.kind == "player" and not s.gone and s.player then
				M.toast(s.player, "info", "재대결 신청", match.sides[side].name .. "님이 재대결을 원해요")
			end
			return
		end
	end
	-- everyone wants another round: same seats, same stake
	local st = match.station
	local sides = { table.clone(match.sides[1]), table.clone(match.sides[2]) }
	for _, s in sides do
		s.gone = nil
	end
	local stake = match.stake
	-- keep the players seated: detach them from the old match without standing them up
	for _, s in match.sides do
		if s.kind == "player" then
			pstate[s.player] = nil
		end
	end
	local spectators = match.spectators
	match.spectators = {}
	match.sides = { { kind = "none", name = "" }, { kind = "none", name = "" } }
	Manager.close(match)
	local newMatch, err = Manager.start(st, sides, stake, true)
	if not newMatch then
		for _, s in sides do
			if s.kind == "player" and s.player.Parent == Players then
				standUp(s.player)
				M.toast(s.player, "warn", "재대결 불가", err or "")
			end
		end
		return
	end
	for p in spectators do
		if p.Parent == Players then
			newMatch.spectators[p] = true
			spect[p] = newMatch
		end
	end
	Manager.broadcast(newMatch)
end

function Manager.offerDraw(match: any, side: number, offer: boolean)
	if match.state ~= "playing" or not (MS.GAMES[match.gameId] and MS.GAMES[match.gameId].turn) then
		return
	end
	local other = if side == 1 then 2 else 1
	if not offer then
		if match.drawOffer == other then
			match.drawOffer = 0
			Manager.broadcast(match)
		end
		return
	end
	if match.drawOffer == other then
		match.drawOffer = 0
		Manager.finish(match, 0, "agreed")
		return
	end
	if match.drawOffer ~= 0 then
		return
	end
	match.drawOffer = side
	if match.sides[other].kind == "npc" then
		-- NPCs politely decline (they always believe they can still win)
		match.drawOffer = 0
		match.api.say(other, "아직 승부 안 끝났다!", 2.5)
		match.api.emote(other, "shake")
	end
	Manager.broadcast(match)
end

-------------------------------------------------------------------------------------------------
-- waiting tables
-------------------------------------------------------------------------------------------------
-- 게임 참가 / 상대 찾기 / before a challenge: sit at the free seat A and wait.
function Manager.sit(player: Player, st: any, stake: number): (boolean, string?)
	if pstate[player] then
		return false, "이미 다른 게임에 참가 중이에요"
	end
	if st.match or st.waiting then
		return false, "이미 사용 중인 자리예요"
	end
	if not M.Bet.canPay(player, stake) then
		return false, "게임머니가 부족해요 (" .. MS.won(stake) .. ")"
	end
	Manager.unspectate(player)
	st.waiting = { player = player, stake = stake, since = os.clock(), reservedFor = nil }
	pstate[player] = { kind = "wait", station = st, side = 1 }
	placePlayer(player, st, 1)
	Manager.publishStation(st)
	if st.host then
		M.Npc.setMode(st.id, "aside")
	end
	return true, nil
end

function Manager.standFromWait(player: Player, reason: string?)
	local ps = pstate[player]
	if not ps or ps.kind ~= "wait" then
		return
	end
	local st = ps.station
	pstate[player] = nil
	if st.waiting and st.waiting.player == player then
		st.waiting = nil
	end
	M.Match.cancelFrom(player, reason or "stood")
	standUp(player)
	if st.host and not st.match then
		M.Npc.setMode(st.id, "host")
	end
	Manager.publishStation(st)
	M.fire(player, MS.Kinds.closed, { id = 0, station = st.id })
end

-- 도전하기 (walk up and take the free seat) and accepted challenges.
function Manager.joinWaiting(st: any, player: Player): (boolean, string?)
	local w = st.waiting
	if not w or st.match then
		return false, "기다리는 사람이 없어요"
	end
	if w.player == player then
		return false, nil
	end
	if w.reservedFor and w.reservedFor ~= player then
		return false, "다른 사람이 오기로 한 자리예요"
	end
	if pstate[player] then
		return false, "이미 다른 게임에 참가 중이에요"
	end
	Manager.unspectate(player)
	local host = w.player
	pstate[host] = nil
	local match, err = Manager.start(st, { playerSide(host), playerSide(player) }, w.stake)
	if not match then
		-- the host keeps waiting
		pstate[host] = { kind = "wait", station = st, side = 1 }
		st.waiting = w
		w.reservedFor = nil
		Manager.publishStation(st)
		M.toast(player, "warn", "시작할 수 없어요", err or "")
		M.toast(host, "warn", "시작할 수 없어요", err or "")
		return false, err
	end
	return true, nil
end

function Manager.practice(player: Player, st: any, stake: number): (boolean, string?)
	if not st.npc or not st.host then
		return false, "여기는 NPC가 없어요"
	end
	if pstate[player] then
		return false, "이미 다른 게임에 참가 중이에요"
	end
	if st.match or st.waiting then
		return false, "지금은 다른 사람이 쓰고 있어요"
	end
	Manager.unspectate(player)
	local match, err = Manager.start(st, { playerSide(player), npcSide(st.npc) }, stake)
	if not match then
		return false, err
	end
	return true, nil
end

-------------------------------------------------------------------------------------------------
-- spectators (관전: no betting, by design)
-------------------------------------------------------------------------------------------------
function Manager.spectate(player: Player, st: any): (boolean, string?)
	local match = st.match
	if not match then
		return false, "지금은 경기가 없어요"
	end
	if pstate[player] then
		return false, nil
	end
	Manager.unspectate(player)
	match.spectators[player] = true
	spect[player] = match
	Manager.publishStation(st)
	M.fire(player, MS.Kinds.match, matchView(match, 0))
	return true, nil
end

function Manager.unspectate(player: Player)
	local match = spect[player]
	spect[player] = nil
	if match then
		match.spectators[player] = nil
		if match.state ~= "closed" then
			Manager.publishStation(match.station)
		end
		M.fire(player, MS.Kinds.closed, { id = match.id, spectator = true })
	end
end

-------------------------------------------------------------------------------------------------
-- input routing
-------------------------------------------------------------------------------------------------
function Manager.input(player: Player, payload: any)
	local ps = pstate[player]
	if not ps or ps.kind ~= "match" then
		return
	end
	local match = ps.match
	if match.state ~= "playing" or not match.def.input then
		return
	end
	local ok, err = pcall(match.def.input, match.gs, ps.side, payload, match.api)
	if not ok then
		warn("[MiniGames] " .. match.gameId .. ".input failed: " .. tostring(err))
	end
end

function Manager.leave(player: Player, why: string)
	local ps = pstate[player]
	if not ps then
		Manager.unspectate(player)
		return
	end
	if ps.kind == "wait" then
		Manager.standFromWait(player, why)
	elseif ps.match then
		Manager.sideLeft(ps.match, ps.side, why)
	end
end

function Manager.onCharacter(player: Player)
	-- a respawn (death / reset) during a match counts as leaving the table
	local ps = pstate[player]
	if ps then
		Manager.leave(player, "respawn")
	end
	saved[player] = nil
end

function Manager.onLeave(player: Player)
	Manager.unspectate(player)
	Manager.leave(player, "left")
	pstate[player] = nil
	saved[player] = nil
end

-------------------------------------------------------------------------------------------------
-- tick (10 Hz)
-------------------------------------------------------------------------------------------------
local AWAY_DIST = 22

function Manager.tick(now: number)
	for _, match in matches do
		local st = match.station
		if match.state == "seating" and now >= match.stateClockEnd then
			setState(match, "countdown", MS.T.countdown)
		elseif match.state == "countdown" and now >= match.stateClockEnd then
			setState(match, "playing", nil)
			local ok, err = pcall(match.def.begin, match.gs, match.api)
			if not ok then
				warn("[MiniGames] " .. match.gameId .. ".begin failed: " .. tostring(err))
				match.state = "countdown"
				Manager.cancel(match, "게임 오류")
			else
				Manager.pushGame(match)
			end
		elseif match.state == "playing" then
			local ok, err = pcall(match.def.tick, match.gs, now, match.api)
			if not ok then
				warn("[MiniGames] " .. match.gameId .. ".tick failed: " .. tostring(err))
			end
		elseif match.state == "result" and now >= match.stateClockEnd then
			Manager.close(match)
		end
		-- walking away / not seated any more
		if match.state ~= "closed" and match.state ~= "result" then
			for i, s in match.sides do
				if s.kind == "player" and not s.gone then
					local near = M.Anti.near(s.player, st.frame.Position, AWAY_DIST) and M.Anti.alive(s.player)
					if near then
						match.away[i] = nil
					else
						match.away[i] = match.away[i] or now
						if now - match.away[i] > MS.T.leaveGrace then
							match.away[i] = nil
							Manager.sideLeft(match, i, "away")
							break
						end
					end
				end
			end
		end
		-- spectators who walked off
		for p in match.spectators do
			if not M.Anti.near(p, st.frame.Position, MS.T.spectate) then
				Manager.unspectate(p)
			end
		end
	end
	for _, st in stationList do
		local w = st.waiting
		if w then
			local p = w.player
			if not M.Anti.near(p, st.frame.Position, AWAY_DIST) or now - w.since > MS.T.waitTTL then
				Manager.standFromWait(p, "timeout")
				if p.Parent == Players then
					M.toast(p, "info", "자리에서 일어났어요", "상대가 오지 않았어요")
				end
			end
		end
	end
end

-- Slow tick (1 Hz): NPC hosts greet passers-by, latency probes for players in timing games.
function Manager.slowTick()
	local players = Players:GetPlayers()
	for _, st in stationList do
		if st.host and not st.match and not st.waiting then
			local best, bestD = nil, math.huge
			for _, p in players do
				local pos = M.Anti.rootPos(p)
				if pos then
					local d = (pos - st.frame.Position).Magnitude
					if d < bestD then
						best, bestD = p, d
					end
				end
			end
			M.Npc.idleTick(st.id, best, bestD)
		end
	end
end

function Manager.activeMatches(): { [number]: any }
	return matches
end

return Manager
