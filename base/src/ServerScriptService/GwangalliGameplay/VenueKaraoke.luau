-- GwangalliGameplay/VenueKaraoke (owner: venues_detail): 광안 코인노래연습장 rooms, server side.
--   * KaraokeRoom models (Booth_NN): the KaraokePanel prompt rents the room (V.KARAOKE.fee per 30
--     in-game minutes, auto-extended while anyone is inside, released when it stays empty or the
--     renter cannot pay) and opens the song picker for everyone inside
--   * the song state lives in the room's attributes (KSong / KStart / KSerial ...), so every client in
--     the room renders the same TV (lyrics, pitch bar) at the same server time
--   * scores: each singer's client reports note judgements once per song; the server computes the
--     score (V.karaokeScore), keeps the room's best (KResult*), rewards 행복 / 인기도 with daily caps
--     and the lobby board "오늘의 노래왕"
-- Started by Venues.init through VenueLife (handlers kSong / kStop / kScore / kLeave).

local Players = game:GetService("Players")

local Karaoke = {}

local L: any -- VenueLife
local ctx: any
local G: any
local Util: any
local V: any

type Room = {
	model: Model,
	no: number,
	name: string,
	zone: BasePart?,
	panel: BasePart?,
	prompt: ProximityPrompt?,
	renter: Player?,
	paidUntil: number,
	emptySince: number?,
	song: string?,
	start: number,
	duration: number,
	serial: number,
	singer: Player?,
	scored: { [Player]: boolean },
	best: number,
	lastPick: number,
}
local rooms: { [number]: Room } = {}
local byModel: { [Instance]: Room } = {}
local kingTop: { any } = {}
local period = 30

local function now(): number
	return workspace:GetServerTimeNow()
end

local function members(r: Room): { Player }
	local out = {}
	if not r.zone or not r.zone.Parent then
		return out
	end
	for _, p in Players:GetPlayers() do
		local pos = Util.rootPosition(p)
		if pos and L.inside(r.zone, pos, 0.6) then
			table.insert(out, p)
		end
	end
	return out
end
Karaoke.members = members

local function isMember(r: Room, player: Player): boolean
	if not r.zone then
		return false
	end
	local pos = Util.rootPosition(player)
	return pos ~= nil and L.inside(r.zone, pos, 1.5)
end

local function refreshPrompt(r: Room)
	local pr = r.prompt
	if not pr then
		return
	end
	if r.renter then
		pr.ActionText = "노래 선택"
		pr.ObjectText = string.format("ROOM %s · %s님 이용 중", r.name, r.renter.DisplayName)
	else
		pr.ActionText = "방 잡기"
		pr.ObjectText = string.format("ROOM %s · 30분 %s", r.name, V.won(V.KARAOKE.fee))
	end
end

local function writeSong(r: Room)
	local m = r.model
	m:SetAttribute("KSong", r.song or "")
	m:SetAttribute("KStart", r.start)
	m:SetAttribute("KSerial", r.serial)
end

local function clearSinger(r: Room)
	local s = r.singer
	r.singer = nil
	if s and s.Parent == Players and s:GetAttribute(V.Attr.Act) == "sing" then
		L.clearAct(s)
	end
end

local function stopSong(r: Room)
	clearSinger(r)
	r.song = nil
	r.start = 0
	r.duration = 0
	writeSong(r)
end

local function release(r: Room, reason: string?)
	local renter = r.renter
	stopSong(r)
	r.renter = nil
	r.emptySince = nil
	r.paidUntil = 0
	r.best = 0
	local m = r.model
	m:SetAttribute("KRenter", 0)
	m:SetAttribute("KRenterName", "")
	m:SetAttribute("KPaidUntil", 0)
	m:SetAttribute("KResultName", "")
	m:SetAttribute("KResultScore", 0)
	refreshPrompt(r)
	if renter and renter.Parent == Players and reason then
		ctx.notify(renter, "info", string.format("🎤 ROOM %s 이용 종료", r.name), reason)
	end
end

local function roomOf(player: Player): Room?
	for _, r in rooms do
		if r.renter == player then
			return r
		end
	end
	return nil
end

local function rent(r: Room, player: Player)
	local cur = roomOf(player)
	if cur and cur ~= r then
		ctx.notify(player, "info", "노래방", string.format("이미 ROOM %s을 이용 중이에요", cur.name))
		return
	end
	if not L.pay(player, V.KARAOKE.fee, string.format("코인노래방 ROOM %s (30분)", r.name)) then
		return
	end
	r.renter = player
	r.paidUntil = now() + period
	r.emptySince = nil
	r.best = 0
	local m = r.model
	m:SetAttribute("KRenter", player.UserId)
	m:SetAttribute("KRenterName", player.DisplayName)
	m:SetAttribute("KPaidUntil", r.paidUntil)
	refreshPrompt(r)
	L.fire(player, { kind = "kOpen", room = r.no })
end

local function onPanel(r: Room, player: Player)
	if not r.renter then
		rent(r, player)
		return
	end
	if r.renter == player or isMember(r, player) then
		L.fire(player, { kind = "kOpen", room = r.no })
	else
		ctx.notify(player, "info", string.format("ROOM %s", r.name), "다른 손님이 이용 중인 방이에요 🎤 빈 방(초록불)을 찾아보세요")
	end
end

local function setup(inst: Instance)
	if not inst:IsA("Model") or byModel[inst] then
		return
	end
	local no = inst:GetAttribute("RoomNo")
	if type(no) ~= "number" then
		return
	end
	local r: Room = {
		model = inst,
		no = no,
		name = tostring(inst:GetAttribute("RoomName") or string.format("%02d", no)),
		zone = nil,
		panel = nil,
		prompt = nil,
		renter = nil,
		paidUntil = 0,
		emptySince = nil,
		song = nil,
		start = 0,
		duration = 0,
		serial = 0,
		singer = nil,
		scored = {},
		best = 0,
		lastPick = 0,
	}
	local z = inst:FindFirstChild("KaraokeZone", true)
	if z and z:IsA("BasePart") then
		r.zone = z
	end
	local panel = inst:FindFirstChild("KaraokePanel", true)
	if panel and panel:IsA("BasePart") then
		r.panel = panel
		local pr = L.prompt(panel, "방 잡기", "", 0.3, 8, Enum.KeyCode.E)
		pr.Name = "GwangalliKaraokePrompt"
		r.prompt = pr
		pr.Triggered:Connect(function(player: Player)
			if not Util.cooldown(player, "karaokePanel", 0.8) then
				return
			end
			onPanel(r, player)
		end)
	end
	rooms[no] = r
	byModel[inst] = r
	release(r, nil)
end

local function getRoom(player: Player, p: any): (Room?, string?)
	local no = type(p) == "table" and Util.int(p.room, 1, 64) or nil
	local r = no and rooms[no]
	if not r then
		return nil, "방을 찾을 수 없어요"
	end
	if not r.renter then
		return nil, "먼저 방을 잡아 주세요 (문 옆 패널)"
	end
	if r.renter ~= player and not isMember(r, player) then
		return nil, "방 안에서만 할 수 있어요"
	end
	return r, nil
end

local function kingRows()
	L.setBoard("karaoke", L.rowsOf(kingTop, function(e, i)
		return string.format("%d. %s  %d점 · %s", i, e.name, e.score, e.title)
	end))
end

function Karaoke.init(life: any)
	L = life
	ctx = life.ctx
	G = ctx.G
	Util = ctx.Util
	V = life.V
	local dl = 24
	pcall(function()
		local cfg = require(game:GetService("ReplicatedStorage"):WaitForChild("GwangalliConfig", 5) :: any)
		if type(cfg) == "table" and type(cfg.DayLengthMinutes) == "number" then
			dl = cfg.DayLengthMinutes
		end
	end)
	period = math.max(10, V.gameMinutes(V.KARAOKE.periodMinutes, dl))

	L.handle("kSong", function(player, p)
		local r, err = getRoom(player, p)
		if not r then
			return { ok = false, code = "room", message = err }
		end
		local id = Util.str(p.song, 8)
		local song = id and V.SONG_BY_ID[id]
		if not song then
			return { ok = false, code = "song", message = "없는 노래예요" }
		end
		local t = now()
		if t - r.lastPick < 2 then
			return { ok = false, code = "busy", message = "잠시만요…" }
		end
		r.lastPick = t
		clearSinger(r)
		local chart = V.chart(song)
		r.song = id
		r.start = t + V.KARAOKE.countdown
		r.duration = chart.duration
		r.serial += 1
		r.scored = {}
		writeSong(r)
		-- the picker holds the mic for the song
		r.singer = player
		L.setAct(player, "sing", chart.duration + V.KARAOKE.countdown, "mic")
		local serial = r.serial
		task.delay(chart.duration + V.KARAOKE.countdown + 8, function()
			if r.serial == serial and r.song == id then
				stopSong(r)
			end
		end)
		return { ok = true, serial = r.serial, start = r.start }
	end)
	L.handle("kStop", function(player, p)
		local r, err = getRoom(player, p)
		if not r then
			return { ok = false, code = "room", message = err }
		end
		stopSong(r)
		return { ok = true }
	end)
	L.handle("kLeave", function(player, p)
		local no = type(p) == "table" and Util.int(p.room, 1, 64) or nil
		local r = no and rooms[no]
		if r and r.renter == player then
			release(r, "이용해 주셔서 감사합니다 🎶")
			return { ok = true }
		end
		return { ok = false, code = "room" }
	end)
	L.handle("kScore", function(player, p)
		local r, err = getRoom(player, p)
		if not r or not r.song then
			return { ok = false, code = "room", message = err }
		end
		if p.serial ~= r.serial or r.scored[player] then
			return { ok = false, code = "serial" }
		end
		local t = now()
		if t < r.start + r.duration - 3 or t > r.start + r.duration + 40 then
			return { ok = false, code = "time" }
		end
		local song = V.SONG_BY_ID[r.song]
		local total = #V.chart(song).notes
		local perfect = Util.int(p.perfect, 0, total) or 0
		local good = Util.int(p.good, 0, total) or 0
		good = math.min(good, total - perfect)
		local score = V.karaokeScore(perfect, good, total)
		r.scored[player] = true
		local m = r.model
		if score > r.best or (m:GetAttribute("KResultSerial") ~= r.serial) then
			r.best = score
			m:SetAttribute("KResultName", player.DisplayName)
			m:SetAttribute("KResultScore", score)
			m:SetAttribute("KResultSerial", r.serial)
		end
		-- rewards (daily caps)
		local notes = {}
		local applied = L.capped(player, "venue_karaoke", V.KARAOKE.dailyRewards, V.KARAOKE.reward)
		if applied then
			table.insert(notes, G.describeStats(applied))
		end
		if score >= 90 then
			local a2 = L.capped(player, "venue_karaoke90", V.KARAOKE.daily90, V.KARAOKE.reward90)
			if a2 then
				table.insert(notes, G.describeStats(a2))
			end
		end
		local rank = L.submit(kingTop, { name = player.DisplayName, score = score, userId = player.UserId, title = song.title }, 5)
		kingRows()
		for _, mem in members(r) do
			L.fire(mem, { kind = "kResult", room = r.no, serial = r.serial, name = player.DisplayName, score = score, mine = mem == player })
		end
		local head, sub = V.scoreComment(score)
		ctx.notify(player, "stat", string.format("🎤 %d점 · %s", score, head), sub .. (if #notes > 0 then " · " .. table.concat(notes, " · ") else "") .. (if rank == 1 then " · 오늘의 노래왕 👑" else ""))
		return { ok = true, score = score, rank = rank }
	end)

	L.watchTag(V.Tags.KaraokeRoom, setup)
	kingRows()

	L.onTick(function()
		local t = now()
		for _, r in rooms do
			if r.renter then
				if r.renter.Parent ~= Players then
					local mem = members(r)
					if #mem > 0 then
						r.renter = mem[1]
						r.model:SetAttribute("KRenter", mem[1].UserId)
						r.model:SetAttribute("KRenterName", mem[1].DisplayName)
						refreshPrompt(r)
					else
						release(r, nil)
						continue
					end
				end
				local mem = members(r)
				if #mem == 0 then
					r.emptySince = r.emptySince or t
					if t - (r.emptySince :: number) > V.KARAOKE.emptyGrace then
						release(r, "방을 나가서 이용이 끝났어요 🎶")
						continue
					end
				else
					r.emptySince = nil
				end
				if t >= r.paidUntil then
					if #mem == 0 then
						release(r, "이용 시간이 끝났어요")
					elseif L.pay(r.renter :: Player, V.KARAOKE.fee, string.format("코인노래방 ROOM %s 연장 (30분)", r.name)) then
						r.paidUntil += period
						r.model:SetAttribute("KPaidUntil", r.paidUntil)
					else
						for _, p in mem do
							ctx.notify(p, "info", string.format("ROOM %s", r.name), "잔액이 부족해서 이용이 끝났어요")
						end
						release(r, nil)
					end
				end
			end
		end
	end)

	L.onLeave(function(player: Player)
		for _, r in rooms do
			if r.singer == player then
				r.singer = nil
			end
			r.scored[player] = nil
		end
	end)
end

return Karaoke
