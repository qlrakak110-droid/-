-- GwangalliKaraokePlus/Playback: the 예약 queue and the song state machine of each room.
--   open -> play (Clock running; intro, lyrics, 간주 are all derived from the chart) -> settle -> score
--   -> next reservation (auto) or open.
-- Ops: reserve / reserveNo / cancel / first (우선예약) / start / stop (취소, refund inside the window) /
--      restart (처음부터) / pause (일시정지) / set (에코 · 키 · 템포 · 멜로디 · 점수).

local Players = game:GetService("Players")

local Playback = {}

local K: any
local S: any
local C: any
local Net: any
local Rooms: any

local function now(): number
	return S.now()
end

local function rateOf(r: any): number
	return S.tempoRate(r.tempo)
end

local function songTime(r: any, t: number): number
	return S.songTime(r.clock, t)
end
Playback.songTime = songTime

-- who may control the current song: its reserver, a mic holder, or the renter
local function canControl(r: any, p: Player): boolean
	if r.renterId == p.UserId then
		return true
	end
	if r.entry and r.entry.by == p.UserId then
		return true
	end
	return r.mics[1] == p.UserId or r.mics[2] == p.UserId
end

local function mineCount(r: any, uid: number): number
	local n = 0
	for _, e in r.queue do
		if e.by == uid then
			n += 1
		end
	end
	return n
end

local function findEntry(r: any, qid: any): (number?, any?)
	local id = S.int(qid, 1, 2 ^ 31)
	if not id then
		return nil, nil
	end
	for i, e in r.queue do
		if e.q == id then
			return i, e
		end
	end
	return nil, nil
end

-------------------------------------------------------------------------------------------------
-- song lifecycle
-------------------------------------------------------------------------------------------------
local function begin(r: any): boolean
	while #r.queue > 0 do
		local e = table.remove(r.queue, 1)
		local song = S.Songs.byId[e.s]
		if not song then
			continue
		end
		local chart = S.Chart.get(song, S.Songs)
		if not chart then
			continue
		end
		local t = now()
		if r.unlimited then
			r.consumed = false
		else
			if r.credits <= 0 then
				table.insert(r.queue, 1, e)
				return false
			end
			r.credits -= 1
			r.consumed = true
		end
		r.serial += 1
		r.song = song
		r.chart = chart
		r.entry = e
		r.clock = { serial = r.serial, anchorT = t + C.LeadIn, anchorS = 0, rate = rateOf(r) }
		r.startT = r.clock.anchorT
		r.paused = false
		r.pausedAt = 0
		r.restarts = 0
		r.state = "play"
		r.nextT = 0
		r.autoAt = nil
		r.idleSince = nil
		r.vibe = math.max(r.vibe * 0.5, 0)
		local by = Players:GetPlayerByUserId(e.by)
		if by and Rooms.of(by) == r then
			K.Mics.autoGrab(r, by)
		end
		K.Scoring.begin(r, e)
		K.Store.countPlay(song.id)
		Rooms.publish(r)
		return true
	end
	return false
end
Playback.begin = begin

local function clearSong(r: any)
	r.song = nil
	r.chart = nil
	r.entry = nil
	r.clock = nil
	r.paused = false
	r.consumed = false
end

-- ends the current song without a score; returns true when the credit was refunded
local function stopSong(r: any, refundOk: boolean): boolean
	if r.state ~= "play" and r.state ~= "settle" then
		return false
	end
	local refunded = false
	if refundOk and r.consumed and now() - (r.startT or 0) < C.RefundWindow then
		r.credits = math.min(C.MaxCredits, r.credits + 1)
		refunded = true
	end
	K.Scoring.clear(r)
	clearSong(r)
	r.state = "open"
	r.holdUntil = now() + C.StopGap
	r.nextT = 0
	Rooms.publish(r)
	return refunded
end

function Playback.abort(r: any)
	K.Scoring.clear(r)
	clearSong(r)
	table.clear(r.queue)
	r.state = "free"
	r.nextT = 0
	r.autoAt = nil
	r.holdUntil = nil
end

local function reanchor(r: any, t: number, rate: number)
	local st = songTime(r, t)
	r.clock = { serial = r.serial, anchorT = t, anchorS = st, rate = rate }
end

local function resume(r: any)
	if not r.paused then
		return
	end
	local t = now()
	r.paused = false
	r.clock = { serial = r.serial, anchorT = t, anchorS = r.clock.anchorS, rate = rateOf(r) }
	Rooms.publish(r)
end

-------------------------------------------------------------------------------------------------
-- step (10 Hz)
-------------------------------------------------------------------------------------------------
function Playback.step(r: any)
	local t = now()
	if r.state == "play" then
		if r.paused then
			if t - r.pausedAt >= C.PauseMax then
				resume(r)
			end
		elseif songTime(r, t) >= r.chart.duration then
			r.state = "settle"
			r.settleAt = t
			Rooms.publish(r)
		end
	elseif r.state == "settle" then
		if t >= r.settleAt + C.SettleTime then
			K.Scoring.finish(r)
			clearSong(r)
			r.state = "score"
			r.nextT = t + C.ScoreHold
			Rooms.publish(r)
		end
	elseif r.state == "score" then
		if t >= r.nextT then
			r.state = "open"
			r.nextT = 0
			r.holdUntil = t
			if #r.queue > 0 and (r.unlimited or r.credits > 0) then
				begin(r)
			end
			Rooms.publish(r)
		end
	end
	if r.state == "open" and r.renter then
		if #r.queue > 0 and (r.unlimited or r.credits > 0) and t >= (r.holdUntil or 0) then
			if not r.autoAt then
				r.autoAt = t + C.AutoStartDelay
				r.nextT = r.autoAt
				Rooms.publish(r)
			elseif t >= r.autoAt then
				r.autoAt = nil
				begin(r)
			end
		elseif r.autoAt then
			r.autoAt = nil
			r.nextT = 0
			Rooms.publish(r)
		end
	end
end

-------------------------------------------------------------------------------------------------
-- ops
-------------------------------------------------------------------------------------------------
local function addEntry(r: any, p: Player, song: any, first: boolean, duet: boolean): any
	if #r.queue >= C.QueueMax then
		return Net.fail("queueFull", C.QueueMax)
	end
	if mineCount(r, p.UserId) >= C.QueuePerPlayer then
		return Net.fail("mine", C.QueuePerPlayer)
	end
	r.qSerial += 1
	local e = { q = r.qSerial, s = song.id, by = p.UserId, n = p.DisplayName, d = duet }
	if first then
		table.insert(r.queue, 1, e)
	else
		table.insert(r.queue, e)
	end
	r.idleSince = nil
	Rooms.publish(r)
	local pos = table.find(r.queue, e) or #r.queue
	return { ok = true, qid = e.q, song = song.id, pos = pos, credits = r.credits, playing = r.state ~= "open" }
end

local function reserve(p: Player, a: any): any
	local r, err = Rooms.guard(p, a, "allowed")
	if not r then
		return err
	end
	local id = S.str(a.song, 8)
	local song = id and S.Songs.byId[id]
	if not song then
		return Net.fail("nosong")
	end
	return addEntry(r, p, song, a.first == true, a.duet == true)
end

local function reserveNo(p: Player, a: any): any
	local r, err = Rooms.guard(p, a, "allowed")
	if not r then
		return err
	end
	local no = S.int(a.no, 10000, 99999)
	local song = no and S.Songs.byNo[no]
	if not song then
		return Net.fail("nosong")
	end
	return addEntry(r, p, song, a.first == true, a.duet == true)
end

local function cancel(p: Player, a: any): any
	local r, err = Rooms.guard(p, a, "allowed")
	if not r then
		return err
	end
	local i, e = findEntry(r, a.qid)
	if not i then
		return Net.fail("bad")
	end
	if e.by ~= p.UserId and r.renterId ~= p.UserId then
		return Net.fail("renter")
	end
	table.remove(r.queue, i)
	Rooms.publish(r)
	return { ok = true }
end

local function first(p: Player, a: any): any
	local r, err = Rooms.guard(p, a, "allowed")
	if not r then
		return err
	end
	local i, e = findEntry(r, a.qid)
	if not i then
		return Net.fail("bad")
	end
	if e.by ~= p.UserId and r.renterId ~= p.UserId then
		return Net.fail("renter")
	end
	table.remove(r.queue, i)
	table.insert(r.queue, 1, e)
	Rooms.publish(r)
	return { ok = true }
end

local function start(p: Player, a: any): any
	local r, err = Rooms.guard(p, a, "allowed")
	if not r then
		return err
	end
	if r.state == "play" or r.state == "settle" then
		return Net.fail("playing")
	end
	if #r.queue == 0 then
		return Net.fail("bad")
	end
	if not r.unlimited and r.credits <= 0 then
		return Net.fail("credits")
	end
	if r.state == "score" then
		r.state = "open"
	end
	r.holdUntil = nil
	r.autoAt = nil
	if not begin(r) then
		return Net.fail("credits")
	end
	return { ok = true, serial = r.serial }
end

local function stop(p: Player, a: any): any
	local r, err = Rooms.guard(p, a, "allowed")
	if not r then
		return err
	end
	if r.state == "score" then
		-- skip the score screen
		r.nextT = now()
		return { ok = true }
	end
	if r.state ~= "play" and r.state ~= "settle" then
		return Net.fail("notPlaying")
	end
	if not canControl(r, p) then
		return Net.fail("role")
	end
	local refunded = stopSong(r, true)
	for _, m in Rooms.memberPlayers(r) do
		Net.fire(m, { kind = "stopped", room = r.no, by = p.DisplayName, refunded = refunded })
	end
	return { ok = true, refunded = refunded }
end

local function restart(p: Player, a: any): any
	local r, err = Rooms.guard(p, a, "allowed")
	if not r then
		return err
	end
	if r.state ~= "play" then
		return Net.fail("notPlaying")
	end
	if not canControl(r, p) then
		return Net.fail("role")
	end
	if (r.restarts or 0) >= C.RestartMax then
		return Net.fail("disabled")
	end
	r.restarts = (r.restarts or 0) + 1
	local t = now()
	r.paused = false
	r.clock = { serial = r.serial, anchorT = t + C.LeadIn, anchorS = 0, rate = rateOf(r) }
	K.Scoring.reset(r)
	Rooms.publish(r)
	return { ok = true }
end

local function pause(p: Player, a: any): any
	local r, err = Rooms.guard(p, a, "allowed")
	if not r then
		return err
	end
	if r.state ~= "play" then
		return Net.fail("notPlaying")
	end
	if not canControl(r, p) then
		return Net.fail("role")
	end
	if r.paused then
		resume(r)
		return { ok = true, paused = false }
	end
	local t = now()
	if songTime(r, t) < 0 then
		return Net.fail("disabled")
	end
	reanchor(r, t, 0)
	r.paused = true
	r.pausedAt = t
	Rooms.publish(r)
	return { ok = true, paused = true }
end

local function set(p: Player, a: any): any
	local r, err = Rooms.guard(p, a, "allowed")
	if not r then
		return err
	end
	local changed = false
	if a.echo ~= nil then
		local v = S.int(a.echo, 0, C.EchoMax)
		if not v then
			return Net.fail("bad")
		end
		r.echo = v
		K.Voice.echo(r)
		changed = true
	end
	if a.key ~= nil then
		local v = S.int(a.key, C.KeyMin, C.KeyMax)
		if not v then
			return Net.fail("bad")
		end
		r.key = v
		changed = true
	end
	if a.tempo ~= nil then
		local v = S.int(a.tempo, C.TempoMin, C.TempoMax)
		if not v then
			return Net.fail("bad")
		end
		r.tempo = v
		if r.state == "play" and r.clock and not r.paused then
			reanchor(r, now(), rateOf(r))
		end
		changed = true
	end
	if a.guide ~= nil then
		local v = S.bool(a.guide)
		if v == nil then
			return Net.fail("bad")
		end
		r.guide = v
		changed = true
	end
	if a.score ~= nil then
		local v = S.bool(a.score)
		if v == nil then
			return Net.fail("bad")
		end
		r.scoreOn = v
		changed = true
	end
	if changed then
		Rooms.publish(r)
	end
	return { ok = true }
end

function Playback.init(k: any)
	K = k
	S, C, Net, Rooms = k.S, k.S.Config, k.Net, k.Rooms
	Net.handle("reserve", "ui", reserve)
	Net.handle("reserveNo", "ui", reserveNo)
	Net.handle("cancel", "ui", cancel)
	Net.handle("first", "ui", first)
	Net.handle("start", "ui", start)
	Net.handle("stop", "ui", stop)
	Net.handle("restart", "ui", restart)
	Net.handle("pause", "ui", pause)
	Net.handle("set", "ui", set)
end

return Playback
