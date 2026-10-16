-- GwangalliKaraokePlus/Scoring: server-authoritative scores, effects and rewards.
-- Clients never send a score: singers send rhythm hits {i, dt} (박자 모드) and per-line voice numbers
-- {li, v, r, o} (목소리 모드, Audio API); the server checks timing against the room clock, judges,
-- and at the end of the song computes 0..100, rewards (daily-capped stats shared with the legacy
-- karaoke, Progress "karaoke_song", Journey, companion affinity, optional small prize, 100점 서비스곡),
-- the 오늘의 노래왕 board, the lobby LED and the personal records.
-- Effects (탬버린 · 박수 · 환호 · 폭죽 · 꽃가루 · 춤) are broadcast to the room with per-kind cooldowns;
-- on-beat tambourine shakes fill the 분위기 meter and give the singers a small bonus.

local Players = game:GetService("Players")

local Scoring = {}

local K: any
local S: any
local C: any
local Net: any
local Rooms: any
local Bridge: any
local Score: any

local fxLast: { [Player]: { [string]: number } } = {}
local voiceLive: { [Player]: boolean } = {}
local voiceStatusAt: { [Player]: number } = {}
local lastBatch: { [Player]: number } = {}

local function now(): number
	return S.now()
end

local function newSinger(p: Player, slot: number): any
	return {
		uid = p.UserId,
		name = p.DisplayName,
		slot = slot,
		judged = {},
		P = 0,
		G = 0,
		M = 0,
		combo = 0,
		maxCombo = 0,
		lastI = 0,
		voice = {},
		voiceSum = 0,
		voiced = 0,
		voiceN = 0,
	}
end

function Scoring.singersJSON(r: any): string
	local s = r.session
	if not s then
		return "[]"
	end
	local out = {}
	for _, g in s.list do
		table.insert(out, { u = g.uid, n = g.name, s = g.slot, m = if voiceLive[Players:GetPlayerByUserId(g.uid) :: any] then "voice" else "tap" })
	end
	return S.encode(out)
end

function Scoring.begin(r: any, entry: any)
	r.session = { serial = r.serial, singers = {}, list = {}, cheer = {}, onBeat = 0, entry = entry }
	local by = Players:GetPlayerByUserId(entry.by)
	if by and Rooms.of(by) == r then
		Scoring.addSinger(r, by, K.Mics.slotOf(r, by.UserId))
	end
	for i = 1, 2 do
		local uid = r.mics[i]
		local p = uid ~= 0 and Players:GetPlayerByUserId(uid)
		if p then
			Scoring.addSinger(r, p, i)
		end
	end
end

function Scoring.addSinger(r: any, p: Player, slot: number)
	local s = r.session
	if not s or s.serial ~= r.serial then
		return
	end
	local g = s.singers[p.UserId]
	if g then
		if slot > 0 then
			g.slot = slot
		end
		return
	end
	if #s.list >= 3 then
		return
	end
	g = newSinger(p, slot)
	s.singers[p.UserId] = g
	table.insert(s.list, g)
	Rooms.publish(r)
end

function Scoring.clear(r: any)
	r.session = nil
end

-- 처음부터: same singers, fresh counts
function Scoring.reset(r: any)
	local s = r.session
	if not s then
		return
	end
	for i, g in s.list do
		local p = Players:GetPlayerByUserId(g.uid)
		local fresh = if p then newSinger(p, g.slot) else g
		s.list[i] = fresh
		s.singers[g.uid] = fresh
	end
	s.cheer = {}
	s.onBeat = 0
end

-------------------------------------------------------------------------------------------------
-- intake
-------------------------------------------------------------------------------------------------
local function currentRoom(p: Player, a: any): (any?, any?, any?)
	local r, err = Rooms.guard(p, a, "allowed")
	if not r then
		return nil, nil, err
	end
	local s = r.session
	if r.state ~= "play" or not s or not r.chart or r.paused then
		return nil, nil, Net.fail("notPlaying")
	end
	local serial = S.int(a.serial, 0, 2 ^ 31)
	if serial ~= r.serial then
		return nil, nil, Net.fail("notPlaying")
	end
	local g = s.singers[p.UserId]
	if not g then
		-- a mic holder joining mid-song becomes a singer
		local slot = K.Mics.slotOf(r, p.UserId)
		if slot > 0 then
			Scoring.addSinger(r, p, slot)
			g = s.singers[p.UserId]
		end
	end
	if not g then
		return nil, nil, Net.fail("role")
	end
	return r, g, nil
end

local function hits(p: Player, a: any): any
	local r, g, err = currentRoom(p, a)
	if not r then
		return err
	end
	local t0 = os.clock()
	if t0 - (lastBatch[p] or 0) < 0.12 then
		return Net.fail("rate")
	end
	lastBatch[p] = t0
	local list = a.hits
	if type(list) ~= "table" or #list == 0 or #list > 24 then
		return Net.fail("bad")
	end
	local taps = r.chart.taps
	local t = now()
	local st = S.songTime(r.clock, t)
	local rate = math.max(r.clock.rate, 0.5)
	local lastJ = nil
	for _, h in list do
		if type(h) ~= "table" then
			continue
		end
		local i = S.int(h.i, 1, #taps)
		local dt = S.num(h.dt, -1, 1)
		if not i or not dt or g.judged[i] then
			continue
		end
		local note = taps[i]
		if st < note.t - Score.LIVE_SLACK or st > note.t + Score.STALE then
			continue
		end
		-- the claimed offset must fit the arrival time (press -> batch -> network): no replaying old notes
		local lag = st - note.t - dt
		if lag < -0.3 or lag > 1.6 * rate then
			continue
		end
		local j = Score.judge(dt / rate)
		if not j then
			continue
		end
		g.judged[i] = j
		-- notes skipped between the last judged one and this one break the combo
		if i < g.lastI then
			-- late batch out of order: count it without touching the combo
			if j == "P" then
				g.P += 1
			elseif j == "G" then
				g.G += 1
			else
				g.M += 1
			end
		else
			local skipped = false
			for k = g.lastI + 1, i - 1 do
				if not g.judged[k] then
					skipped = true
					break
				end
			end
			if skipped then
				g.combo = 0
			end
			if j == "P" then
				g.P += 1
				g.combo += 1
			elseif j == "G" then
				g.G += 1
				g.combo += 1
			else
				g.M += 1
				g.combo = 0
			end
			g.lastI = i
		end
		g.maxCombo = math.max(g.maxCombo, g.combo)
		lastJ = j
	end
	if lastJ then
		Net.live(Rooms.memberPlayers(r), { kind = "judge", room = r.no, u = p.UserId, j = lastJ, c = g.combo })
	end
	return { ok = true, P = g.P, G = g.G, M = g.M, combo = g.combo }
end

local function voice(p: Player, a: any): any
	local r, g, err = currentRoom(p, a)
	if not r then
		return err
	end
	local list = a.lines
	if type(list) ~= "table" or #list == 0 or #list > 3 then
		return Net.fail("bad")
	end
	local lines = r.chart.lines
	local st = S.songTime(r.clock, now())
	local best = nil
	for _, l in list do
		if type(l) ~= "table" then
			continue
		end
		local li = S.int(l.li, 1, #lines)
		if not li or g.voice[li] ~= nil then
			continue
		end
		local line = lines[li]
		if st < line.due - Score.VOICE_EARLY or st > line.due + Score.VOICE_LATE then
			continue
		end
		local v = S.num(l.v, 0, 1) or 0
		local q = Score.voiceLine(v, S.num(l.r, 0, 1) or 0, S.num(l.o, 0, 1) or 0)
		g.voice[li] = q
		g.voiceSum += q
		g.voiceN += 1
		if v >= Score.VOICED_MIN then
			g.voiced += 1
		end
		best = q
	end
	if best then
		Net.live(Rooms.memberPlayers(r), { kind = "voice", room = r.no, u = p.UserId, q = math.floor(best * 100 + 0.5) })
	end
	return { ok = true, voiced = g.voiced }
end

local function voiceStatus(p: Player, a: any): any
	local t = os.clock()
	if t - (voiceStatusAt[p] or -math.huge) < 4 then
		return Net.fail("rate")
	end
	voiceStatusAt[p] = t
	local live = a.live == true
	voiceLive[p] = live or nil
	local r = Rooms.of(p)
	if r then
		K.Voice.refresh(r)
		Rooms.publish(r)
	end
	return { ok = true }
end

local function cheer(p: Player, a: any): any
	local r, err = Rooms.guard(p, a, "allowed")
	if not r then
		return err
	end
	local kind = a.kind
	if type(kind) ~= "string" or not S.FX_BY_ID[kind] then
		return Net.fail("bad")
	end
	local cd = C.EffectCooldown[kind] or 1
	local pl = fxLast[p]
	if not pl then
		pl = {}
		fxLast[p] = pl
	end
	local t = os.clock()
	if t - (pl[kind] or -math.huge) < cd * 0.85 then
		return Net.fail("cooldown")
	end
	pl[kind] = t
	local add = if kind == "tamb" then 1 elseif kind == "clap" then 2 elseif kind == "cheer" then 4 elseif kind == "fire" then 6 elseif kind == "petal" then 5 else 3
	local onBeat = 0
	local s = r.session
	if kind == "tamb" then
		-- hand prop (the mic holder keeps the mic; no prop clash)
		if K.Mics.slotOf(r, p.UserId) == 0 then
			Bridge.setAct(p, "tambourine", 2.6, "tambourine")
		end
		r.tambUntil = now() + 2.6
		K.Store.bump(p, "tamb", 1)
		-- on-beat shakes (client song times) while a song plays
		if s and r.state == "play" and r.chart and type(a.beats) == "table" and not r.paused then
			local st = S.songTime(r.clock, now())
			local beat = r.chart.beat
			local rate = math.max(r.clock.rate, 0.5)
			-- each half-beat slot counts once per player (monotonic), so repeats cannot farm the meter
			s.lastBeat = s.lastBeat or {}
			local lastSlot = s.lastBeat[p.UserId] or -math.huge
			for idx, bt in a.beats do
				if idx > 8 then
					break
				end
				local v = S.num(bt, -10, 1000)
				if not v or v < st - 4 or v > st + 0.6 or v < 0 then
					continue
				end
				local slotKey = math.floor(v / (beat / 2) + 0.5)
				if slotKey <= lastSlot then
					continue
				end
				lastSlot = slotKey
				if math.abs(Score.beatOffset(beat, v)) <= Score.BEAT_WIN * rate then
					onBeat += 1
				end
			end
			s.lastBeat[p.UserId] = lastSlot
			if onBeat > 0 then
				s.cheer[p.UserId] = (s.cheer[p.UserId] or 0) + onBeat
				s.onBeat += onBeat
				add += onBeat
			end
		end
	end
	r.vibe = math.clamp(r.vibe + add, 0, 100)
	Net.live(Rooms.memberPlayers(r), { kind = "fx", room = r.no, fx = kind, u = p.UserId, n = p.DisplayName })
	Rooms.publish(r)
	return { ok = true, vibe = math.floor(r.vibe + 0.5), onBeat = onBeat }
end

-------------------------------------------------------------------------------------------------
-- finish (at the end of settle)
-------------------------------------------------------------------------------------------------
local function grantRewards(r: any, p: Player, g: any, score: number, song: any): { string }
	local R = C.Rewards
	local got = {}
	if Bridge.capped(p, "venue_karaoke", R.daily, R.song) then
		for k, v in R.song do
			table.insert(got, string.format("%s +%d", if k == "happiness" then "행복" elseif k == "popularity" then "인기도" else k, v))
		end
	end
	if score >= R.highMin and Bridge.capped(p, "venue_karaoke90", R.highDaily, R.high) then
		for k, v in R.high do
			table.insert(got, string.format("%s +%d", if k == "popularity" then "인기도" elseif k == "happiness" then "행복" else k, v))
		end
	end
	local SC = C.ScoreCoins
	if SC and SC.Amount > 0 and score >= SC.MinScore and K.Store.coinAllowed(p) then
		if Bridge.earn(p, SC.Amount, SC.Label) then
			K.Store.coinUsed(p)
			table.insert(got, string.format("상금 +%s", S.won(SC.Amount)))
		end
	end
	Bridge.track(p, "karaoke_song", 1)
	Bridge.journey(p, { kind = "kResult", room = 0, serial = r.serial, name = song.title, score = score, mine = true })
	Bridge.joint(p, "karaoke")
	return got
end

function Scoring.finish(r: any)
	local s = r.session
	local song, chart = r.song, r.chart
	r.session = nil
	if not (s and song and chart) then
		return
	end
	local members = Rooms.memberPlayers(r)
	local vibeB = Score.vibeBonus(s.onBeat)
	local nTaps, nLines = #chart.taps, #chart.lines
	local rows = {}
	local bonus = false
	local personal: { [Player]: any } = {}
	for _, g in s.list do
		local p = Players:GetPlayerByUserId(g.uid)
		local judgedN = g.P + g.G + g.M
		local part = Score.participation(judgedN, nTaps, g.voiced, nLines)
		local tap = if judgedN > 0 then Score.tapScore(g.P, g.G, nTaps, g.maxCombo) else 0
		local vo = if g.voiceN > 0 then Score.voiceScore(g.voiceSum, nLines) else 0
		local mode = if vo > tap then "voice" else "tap"
		local scored = part >= C.Rewards.minParticipation and p ~= nil and Rooms.of(p :: Player) == r
		local final = if scored then Score.final(math.max(tap, vo), vibeB) else -1
		local grade = if final >= 0 then Score.grade(final).id else ""
		table.insert(rows, { u = g.uid, n = g.name, s = final, g = grade, m = mode, p = g.P, gd = g.G, ms = math.max(0, nTaps - g.P - g.G), c = g.maxCombo, v = vibeB, sl = g.slot })
		if scored and p then
			local pp = p :: Player
			local rewards = grantRewards(r, pp, g, final, song)
			local best, isBest = K.Store.record(pp, song.id, final, #s.list > 1)
			local rank = Bridge.submitKing({ name = g.name, userId = g.uid, score = final, title = song.title })
			local gotBonus = false
			if final >= C.BonusScore and not r.unlimited and r.bonusUsed < C.BonusSongsMax and r.renter then
				r.bonusUsed += 1
				r.credits = math.min(C.MaxCredits, r.credits + 1)
				bonus = true
				gotBonus = true
			end
			personal[pp] = { score = final, best = best, isBest = isBest, rank = rank, rewards = table.concat(rewards, " · "), bonus = gotBonus, mode = mode, grade = grade }
		end
	end
	-- listeners who kept the beat with the tambourine
	for uid, n in s.cheer do
		if n >= C.Rewards.cheerNeed and not s.singers[uid] then
			local p = Players:GetPlayerByUserId(uid)
			if p and Rooms.of(p) == r then
				if Bridge.capped(p, "kp_cheer", C.Rewards.cheerDaily, C.Rewards.cheer) then
					Net.toast(p, "🪇 탬버린 박자 최고!", "분위기 메이커 · 행복 +1", "success")
				end
			end
		end
	end
	r.result = S.encode({ serial = r.serial, s = song.id, b = bonus, sc = rows, on = r.scoreOn, at = now() })
	for _, m in members do
		local mine = personal[m]
		Net.fire(m, { kind = "result", room = r.no, serial = r.serial, song = song.id, mine = mine })
	end
	Bridge.writeBoard()
	K.refreshLED()
end

function Scoring.decayVibe(r: any, dt: number)
	if r.vibe > 0 then
		r.vibe = math.max(0, r.vibe - dt * (if r.state == "play" then 1.2 else 4))
	end
end

function Scoring.voiceLive(p: Player): boolean
	return voiceLive[p] == true
end

function Scoring.init(k: any)
	K = k
	S, C, Net, Rooms, Bridge = k.S, k.S.Config, k.Net, k.Rooms, k.Bridge
	Score = S.Score
	Net.handle("hits", "game", hits)
	Net.handle("voice", "game", voice)
	Net.handle("voiceStatus", "ui", voiceStatus)
	Net.handle("cheer", "fx", cheer)
	Players.PlayerRemoving:Connect(function(p)
		fxLast[p] = nil
		voiceLive[p] = nil
		voiceStatusAt[p] = nil
		lastBatch[p] = nil
	end)
end

return Scoring
