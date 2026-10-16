-- GwangalliKaraokePlus/Mic (client): singing with real voice (Roblox Audio API voice chat).
-- If the engine created an AudioDeviceInput for me (VoiceChatService.UseAudioApi on + voice enabled),
-- a local AudioAnalyzer listens to my own mic while I sing. Per lyric line it measures
--   v = share of syllables I voiced, r = share of the rest after the line I kept quiet,
--   o = share of syllables whose onset I hit (level rising near the syllable start)
-- and sends those three numbers when the line is due (the server judges and scores; no score is sent).
-- Mic.level (0..1) feeds the HUD meter. Without a device nothing is created and the HUD falls back to
-- the rhythm-tap game.

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local Mic = {}

local K: any
local S: any
local player = Players.LocalPlayer

local device: Instance? = nil
local analyzer: Instance? = nil
local wire: Instance? = nil
Mic.level = 0
Mic.live = false
local reported: boolean? = nil
local lastReport = -math.huge
local floor = 0.004
local session: any = nil

local function findDevice(): Instance?
	local ok, d = pcall(function()
		return player:FindFirstChildOfClass("AudioDeviceInput")
	end)
	return if ok then d else nil
end

local function muted(): boolean
	if not device then
		return true
	end
	local ok, m = pcall(function()
		return (device :: any).Muted
	end)
	return ok and m == true
end

local function ensureAnalyzer(): boolean
	if analyzer and analyzer.Parent and wire and wire.Parent then
		return true
	end
	device = findDevice()
	if not device then
		return false
	end
	local okA, a = pcall(Instance.new, "AudioAnalyzer")
	if not okA or not a then
		return false
	end
	a.Name = "GwKP_Mic"
	local folder = SoundService:FindFirstChild(K.S.NAMES.SoundFolder) or SoundService
	a.Parent = folder
	local okW, w = pcall(Instance.new, "Wire")
	if not okW or not w then
		a:Destroy()
		return false
	end
	local ok = pcall(function()
		(w :: any).SourceInstance = device;
		(w :: any).TargetInstance = a
	end)
	if not ok then
		a:Destroy()
		w:Destroy()
		return false
	end
	w.Parent = a
	analyzer, wire = a, w
	return true
end

local function rms(): number
	if not analyzer then
		return 0
	end
	local ok, v = pcall(function()
		return (analyzer :: any).RmsLevel
	end)
	return if ok and type(v) == "number" then v else 0
end

local function report(live: boolean)
	if reported == live then
		return
	end
	if os.clock() - lastReport < 5 then
		return
	end
	lastReport = os.clock()
	reported = live
	K.Net.call("voiceStatus", { live = live }, nil, true)
end

-------------------------------------------------------------------------------------------------
-- per-line measurement
-------------------------------------------------------------------------------------------------
local function newSession(v: any): any
	local lines = {}
	for li, l in v.chart.lines do
		local syl = {}
		for k, s in l.syl do
			syl[k] = { t = s.t, e = s.e, on = 0, n = 0, onset = false }
		end
		lines[li] = { syl = syl, rq = 0, rn = 0, sent = false, prev = 0 }
	end
	return { serial = v.serial, lines = lines, pending = {}, lastSend = 0 }
end

local function sample(v: any, st: number, level: number)
	local c = v.chart
	local thr = math.max(0.018, floor * 3.2)
	local voiced = level > thr
	for li, l in c.lines do
		local L = session.lines[li]
		if L.sent then
			continue
		end
		if st >= l.t0 - 0.2 and st <= l.e + 0.1 then
			for k, s in l.syl do
				local m = L.syl[k]
				if st >= s.t - 0.05 and st <= s.e + 0.05 then
					m.n += 1
					if voiced then
						m.on += 1
					end
				end
				if not m.onset and math.abs(st - s.t) <= 0.16 and voiced and L.prev <= thr then
					m.onset = true
				end
			end
		end
		if st >= l.rest.a and st <= l.rest.b then
			L.rn += 1
			if not voiced then
				L.rq += 1
			end
		end
		if st >= l.due and not L.sent then
			L.sent = true
			local nv, no = 0, 0
			for _, m in L.syl do
				if m.n > 0 and m.on / m.n >= 0.3 then
					nv += 1
				end
				if m.onset then
					no += 1
				end
			end
			local ns = math.max(1, #L.syl)
			table.insert(session.pending, {
				li = li,
				v = math.floor(nv / ns * 100 + 0.5) / 100,
				r = if L.rn > 0 then math.floor(L.rq / L.rn * 100 + 0.5) / 100 else 1,
				o = math.floor(no / ns * 100 + 0.5) / 100,
			})
		end
		L.prev = level
	end
	if #session.pending > 0 and os.clock() - session.lastSend > 0.3 then
		local batch = {}
		while #batch < 3 and #session.pending > 0 do
			table.insert(batch, table.remove(session.pending, 1))
		end
		session.lastSend = os.clock()
		K.Net.call("voice", { room = v.no, serial = v.serial, lines = batch }, nil, true)
	end
end

-- called every frame by the client loop
function Mic.update(dt: number)
	local v = K.Rooms.current()
	local wantMode = (K.me and K.me.settings and K.me.settings.mode) or "auto"
	local d = findDevice()
	if d ~= device then
		device = d
		if analyzer then
			analyzer:Destroy()
			analyzer, wire = nil, nil
		end
	end
	local can = device ~= nil and S.Config.Voice ~= "off" and wantMode ~= "tap" and not muted()
	Mic.live = can
	report(can and v ~= nil and K.Rooms.allowedMe(v))
	if not can or not v or v.state ~= "play" or not v.chart or v.paused or not K.Rooms.isSinger(v) then
		Mic.level = math.max(0, Mic.level - dt * 2)
		if session and (not v or v.serial ~= session.serial) then
			session = nil
		end
		return
	end
	if not ensureAnalyzer() then
		Mic.live = false
		return
	end
	local st = K.Rooms.songTime(v, S.now())
	-- a new song, or 처음부터 (the clock jumped back): measure from scratch
	if not session or session.serial ~= v.serial or st < (session.lastSt or -math.huge) - 1.5 then
		session = newSession(v)
	end
	session.lastSt = st
	local level = rms()
	-- slow noise floor (minimum tracker)
	floor = if level < floor then level else floor + (level - floor) * dt * 0.05
	Mic.level = math.clamp(level * 6, 0, 1)
	sample(v, st, level)
end

function Mic.hasDevice(): boolean
	return device ~= nil
end

-- 처음부터: measurements restart with the song
function Mic.reset()
	session = nil
end

function Mic.init(k: any)
	K = k
	S = k.S
end

return Mic
