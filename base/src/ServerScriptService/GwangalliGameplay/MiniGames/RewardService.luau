--!strict
-- MiniGames/RewardService: records, rating, ranks and the "명성" side of the minigames (server only).
--
-- Per player: MS.emptyRecord() shape (per-game W / L / D, streak, best streak, one Elo rating for
-- every minigame, earned / lost totals, today's NPC net). Persisted in DataStore MS.DATASTORE key
-- "u_<UserId>" with UpdateAsync (memory only in Studio / unpublished places, like Profiles), saved on
-- leave and every AUTOSAVE seconds when dirty. The record is NOT part of the life-game profile, so
-- Profiles.sanitize never drops it.
-- Public face: player attributes MiniRating (number), MiniRank ("골드"), MiniRankIcon ("🥇"),
-- MiniWins (total wins) - the VS cards, challenge popups and the HUD read these.
-- Life-game hooks: a win gives 행복 +1 (PvP also 인기 +1) through ctx.addStats (silent).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local RewardService = {}

local M: any = nil
local MS: any = nil

local AUTOSAVE = 150
type Entry = { rec: any, dirty: boolean, loaded: boolean, persistent: boolean, lastSave: number }
local entries: { [Player]: Entry } = {}
local store: any = nil
local storeOk = false

function RewardService.init(m: any)
	M = m
	MS = m.MS
	local ok, s = pcall(function()
		return DataStoreService:GetDataStore(MS.DATASTORE)
	end)
	if ok and s then
		store = s
		storeOk = true
	else
		print("[MiniGames] DataStore unavailable: minigame records are kept in memory only this session.")
	end
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE)
			for player, e in entries do
				if e.dirty and e.persistent then
					task.spawn(RewardService.save, player, false)
				end
			end
		end
	end)
end

local function keyOf(player: Player): string
	return MS.KEY_PREFIX .. tostring(player.UserId)
end

local function publish(player: Player, rec: any)
	if player.Parent ~= Players then
		return
	end
	local w, l = MS.totals(rec)
	local rank = MS.rankOf(rec.rating, w + l)
	player:SetAttribute("MiniRating", rec.rating)
	player:SetAttribute("MiniRank", rank.name)
	player:SetAttribute("MiniRankIcon", rank.icon)
	player:SetAttribute("MiniWins", w)
end

function RewardService.load(player: Player)
	if entries[player] then
		return
	end
	local e: Entry = { rec = MS.emptyRecord(), dirty = false, loaded = false, persistent = false, lastSave = 0 }
	entries[player] = e
	publish(player, e.rec)
	if not storeOk or player.UserId <= 0 then
		e.loaded = true
		return
	end
	task.spawn(function()
		for attempt = 1, 3 do
			local ok, raw = pcall(function()
				return store:GetAsync(keyOf(player))
			end)
			if ok then
				if entries[player] ~= e then
					return
				end
				-- merge: games played before the load finished (rare) are kept on top of the saved record
				local saved = MS.sanitizeRecord(raw)
				if e.dirty then
					for id, g in e.rec.games do
						local s = saved.games[id]
						s.w += g.w
						s.l += g.l
						s.d += g.d
					end
					saved.rating = e.rec.rating
					saved.earned += e.rec.earned
					saved.lost += e.rec.lost
					saved.played += e.rec.played
				end
				e.rec = saved
				e.loaded = true
				e.persistent = true
				publish(player, e.rec)
				return
			end
			local msg = string.lower(tostring(raw))
			if string.find(msg, "studio", 1, true) or string.find(msg, "publish", 1, true) or string.find(msg, "api", 1, true) then
				storeOk = false
				break
			end
			task.wait(2 ^ attempt)
		end
		e.loaded = true -- memory only for this player (never overwrites the saved record)
	end)
end

function RewardService.save(player: Player, release: boolean): boolean
	local e = entries[player]
	if not e then
		return false
	end
	if release then
		entries[player] = nil
	end
	if not e.persistent or not e.dirty or not store then
		return false
	end
	e.dirty = false
	local snapshot = table.clone(e.rec)
	local ok, err = pcall(function()
		store:UpdateAsync(keyOf(player), function(_old: any)
			return snapshot
		end)
	end)
	if not ok then
		e.dirty = true
		warn("[MiniGames] record save failed for " .. player.Name .. ": " .. tostring(err))
	end
	e.lastSave = os.clock()
	return ok
end

function RewardService.release(player: Player)
	task.spawn(RewardService.save, player, true)
end

function RewardService.get(player: Player): any
	local e = entries[player]
	if not e then
		RewardService.load(player)
		e = entries[player]
	end
	return (e :: Entry).rec
end

function RewardService.rating(player: Player): number
	return RewardService.get(player).rating
end

function RewardService.rank(player: Player): any
	local rec = RewardService.get(player)
	local w, l = MS.totals(rec)
	return MS.rankOf(rec.rating, w + l)
end

-------------------------------------------------------------------------------------------------
-- NPC allowance (MS.NPC_DAILY_PROFIT_CAP net per KST day)
-------------------------------------------------------------------------------------------------
local function npcDay(rec: any): any
	local today = MS.kstDay(os.time())
	if rec.npcDay.day ~= today then
		rec.npcDay = { day = today, net = 0 }
	end
	return rec.npcDay
end

function RewardService.npcRoom(player: Player): number
	local d = npcDay(RewardService.get(player))
	return math.max(0, MS.NPC_DAILY_PROFIT_CAP - d.net)
end

function RewardService.addNpcNet(player: Player, delta: number)
	local e = entries[player]
	if not e then
		return
	end
	local d = npcDay(e.rec)
	d.net += delta
	e.dirty = true
end

-------------------------------------------------------------------------------------------------
-- Results
-------------------------------------------------------------------------------------------------
-- Applies one finished match to the player sides' records. winner 1 | 2 | 0 (draw).
-- net = BetService.settle result. Returns { [side] = {rating, delta, rank, w, l, d, streak} }.
function RewardService.apply(match: any, winner: number, net: { [number]: number }?): { [number]: any }
	local out: { [number]: any } = {}
	local ratings: { [number]: number } = {}
	for i, side in match.sides do
		if side.kind == "player" and side.player then
			ratings[i] = RewardService.rating(side.player)
		else
			ratings[i] = MS.NPC_RATING[side.difficulty or "normal"] or 1100
		end
	end
	local pvp = match.sides[1].kind == "player" and match.sides[2].kind == "player"
	local friendly = match.stake <= 0
	for i, side in match.sides do
		if side.kind == "player" and side.player and entries[side.player] then
			local e = entries[side.player] :: Entry
			local rec = e.rec
			local g = rec.games[match.gameId]
			local score = if winner == 0 then 0.5 elseif winner == i then 1 else 0
			if winner == 0 then
				g.d += 1
			elseif winner == i then
				g.w += 1
				g.streak += 1
				g.best = math.max(g.best, g.streak)
			else
				g.l += 1
				g.streak = 0
			end
			rec.played += 1
			local opp = if i == 1 then 2 else 1
			local k = if pvp then MS.K_PVP else MS.K_NPC
			-- 친선전 counts in the record but moves the rating half as much
			if friendly then
				k = math.floor(k / 2)
			end
			local before = rec.rating
			rec.rating = MS.rated(before, ratings[opp], score, k)
			local n = net and net[i] or 0
			if n > 0 then
				rec.earned += n
			elseif n < 0 then
				rec.lost += -n
			end
			e.dirty = true
			publish(side.player, rec)
			local w, l, d = MS.totals(rec)
			local rank = MS.rankOf(rec.rating, w + l)
			local oldRank = MS.rankOf(before, w + l - (if winner == i then 1 elseif winner == 0 then 0 else 1))
			out[i] = {
				rating = rec.rating,
				delta = rec.rating - before,
				rank = rank.name,
				rankIcon = rank.icon,
				rankUp = rank.min > oldRank.min,
				w = g.w,
				l = g.l,
				d = g.d,
				streak = g.streak,
				totalW = w,
				totalL = l,
				totalD = d,
			}
			if winner == i then
				pcall(M.ctx.addStats, side.player, if pvp then { happiness = 1, popularity = 1 } else { happiness = 1 }, nil, true)
			end
			if out[i].rankUp then
				M.ctx.notify(side.player, "success", "미니게임 랭크 UP!", rank.icon .. " " .. rank.name .. " 달성")
			end
		end
	end
	return out
end

-- Snapshot for the client's 전적 card.
function RewardService.snapshot(player: Player): any
	local rec = RewardService.get(player)
	local w, l, d = MS.totals(rec)
	local rank = MS.rankOf(rec.rating, w + l)
	local games = {}
	for _, id in MS.GAME_ORDER do
		local g = rec.games[id]
		games[id] = { w = g.w, l = g.l, d = g.d, streak = g.streak, best = g.best, rate = MS.winRate(g.w, g.l) }
	end
	return {
		rating = rec.rating,
		rank = rank.name,
		rankIcon = rank.icon,
		rankId = rank.id,
		w = w,
		l = l,
		d = d,
		rate = MS.winRate(w, l),
		earned = rec.earned,
		lost = rec.lost,
		games = games,
		npcRoom = RewardService.npcRoom(player),
		persistent = entries[player] ~= nil and entries[player].persistent,
	}
end

-- Server leaderboard (players in this server, by rating).
function RewardService.board(limit: number): { any }
	local list = {}
	for player, e in entries do
		if player.Parent == Players then
			local w, l = MS.totals(e.rec)
			local rank = MS.rankOf(e.rec.rating, w + l)
			table.insert(list, { name = player.DisplayName, userId = player.UserId, rating = e.rec.rating, rank = rank.name, rankIcon = rank.icon, w = w, l = l })
		end
	end
	table.sort(list, function(a, b)
		return a.rating > b.rating
	end)
	while #list > limit do
		table.remove(list)
	end
	return list
end

return RewardService
