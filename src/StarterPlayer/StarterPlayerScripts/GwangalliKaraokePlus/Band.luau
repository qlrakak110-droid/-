-- GwangalliKaraokePlus/Band (client): the 반주기. One sequencer per client plays the room I am in (or,
-- muffled through the wall, a playing room next to me in the corridor), synced to the room Clock
-- (workspace:GetServerTimeNow()), so everyone in the room hears the same bar at the same time.
--   * generated band from a few built-in samples (Config.Samples, pitch = PlaybackSpeed): kick, snare,
--     hats, bass, pad, arpeggio per genre preset (발라드 / 댄스 / EDM / 트로트 / 록 / 힙합 / 시티팝 / R&B /
--     동요 / 민요 세마치 / OST), fills and crashes at section changes;
--   * 멜로디 가이드 (the chart's melody), 키 ±  (every pitched note x 2^(key/12)), 템포 (the Clock rate);
--   * optional licensed backing track per song (Songs soundId / Config.SongAudio): a Sound kept in sync
--     (PlaybackSpeed = tempo, PitchShift = key / tempo); the generated band then plays only the guide;
--   * 에코: without the Audio API voice rig the echo level colours the guide melody (local effects);
--   * effect sounds for 탬버린 · 박수 · 환호 · 폭죽 · 꽃가루 · 춤.

local SoundService = game:GetService("SoundService")

local Band = {}

local K: any
local S: any
local C: any

local folder: Folder
local master: SoundGroup
local bandGroup: SoundGroup
local guideGroup: SoundGroup
local fxGroup: SoundGroup
local muffle: EqualizerSoundEffect
local echoFx: EchoSoundEffect
local reverbFx: ReverbSoundEffect
local track: Sound
local trackPitch: PitchShiftSoundEffect

type Pool = { list: { Sound }, i: number, base: number, gain: number }
local pools: { [string]: Pool } = {}

local events: { any } = {}
local eventsKey = ""
local idx = 1
local lastSt = -math.huge
local target: any = nil
local targetSerial = -1
local muffled = false
local settings = { bandVol = 0.8, guideVol = 0.6 }
Band.localDelay = 0

-------------------------------------------------------------------------------------------------
-- samples
-------------------------------------------------------------------------------------------------
local function makePool(name: string, id: string, n: number, base: number?, gain: number?, group: SoundGroup)
	local p: Pool = { list = {}, i = 1, base = base or 0, gain = gain or 1 }
	for i = 1, n do
		local s = Instance.new("Sound")
		s.Name = name .. i
		s.SoundId = id
		s.Volume = 0.5
		s.SoundGroup = group
		s.Parent = folder
		p.list[i] = s
	end
	pools[name] = p
end

local function play(pool: Pool?, speed: number, vol: number)
	if not pool or vol <= 0.001 then
		return
	end
	local s = pool.list[pool.i]
	pool.i = pool.i % #pool.list + 1
	s.PlaybackSpeed = math.clamp(speed, 0.05, 8)
	s.Volume = math.clamp(vol * pool.gain, 0, 2)
	s.TimePosition = 0
	s:Play()
end

local function tone(poolName: string, midi: number, vol: number)
	local p = pools[poolName]
	if not p then
		return
	end
	local key = if target then S.keyRatio(target.key or 0) else 1
	play(p, 2 ^ ((midi - p.base) / 12) * key, vol)
end

-------------------------------------------------------------------------------------------------
-- patterns (16 steps per 4/4 bar, 12 per 3/4 bar); bass letters: r root, f fifth, o octave, 3 third
-------------------------------------------------------------------------------------------------
local P4 = {
	ballad = {
		verse = { k = "x.........x.....", s = "........x.......", h = "x...x...x...x...", b = "r.......f.......", pad = "x.......x.......", gain = 0.75 },
		chorus = { k = "x.....x...x.....", s = "....x.......x...", h = "x.x.x.x.x.x.x.x.", b = "r.....r.f.......", pad = "x.......x.......", arp = "x...x...x...x..." },
	},
	acoustic = {
		verse = { k = "x.......x.......", s = "....x.......x...", h = "x.x.x.x.x.x.x.x.", b = "r.......f.......", arp = "x.xx.xx.x.xx.xx.", gain = 0.7 },
		chorus = { k = "x.....x.x.......", s = "....x.......x...", h = "x.x.x.x.x.x.x.x.", b = "r.....r.f...f...", arp = "x.xx.xx.x.xx.xx.", pad = "x..............." },
	},
	rnb = {
		verse = { k = "x......x..x.....", s = "....x.......x...", h = "x.xxx.xxx.xxx.xx", b = "r......r..f.....", pad = "x.......x.......", swing = 0.08, gain = 0.8 },
		chorus = { k = "x......x..x..x..", s = "....x.......x...", h = "x.xxx.xxx.xxx.xx", b = "r......r..f..r..", pad = "x.......x.......", arp = "..x...x...x...x.", swing = 0.08 },
	},
	pop = {
		verse = { k = "x.......x.x.....", s = "....x.......x...", h = "x.x.x.x.x.x.x.x.", b = "r.r.r.r.r.r.r.r.", pad = "x...............", gain = 0.85 },
		chorus = { k = "x...x...x...x...", s = "....x.......x...", h = "x.x.x.x.x.x.x.x.", oh = "..x...x...x...x.", b = "r.r.r.r.f.f.f.f.", pad = "x.......x.......", arp = "x.x.x.x.x.x.x.x." },
	},
	citypop = {
		verse = { k = "x......x..x.....", s = "....x.......x...", h = "xxxxxxxxxxxxxxxx", b = "r..r..o.r..r.f..", arp = "..x...x...x...x.", pad = "x.......x.......", gain = 0.8 },
		chorus = { k = "x......x..x.....", s = "....x.......x...", h = "xxxxxxxxxxxxxxxx", oh = "..x...x...x...x.", b = "r..r..o.r..r.f.o", arp = "x.x.x.x.x.x.x.x.", pad = "x.......x......." },
	},
	dance = {
		verse = { k = "x...x...x...x...", s = "....x.......x...", h = "..x...x...x...x.", b = ".r.r.r.r.r.r.r.r", pad = "x...............", gain = 0.85 },
		chorus = { k = "x...x...x...x...", s = "....x.......x...", h = "xxxxxxxxxxxxxxxx", oh = "..x...x...x...x.", b = ".r.r.r.r.o.o.f.f", pad = "x.......x.......", arp = "x.x.x.x.x.x.x.x." },
	},
	edm = {
		verse = { k = "x...x...x...x...", s = "....x.......x...", h = "..x...x...x...x.", b = ".r.r.r.r.r.r.r.r", arp = "x.x.x.x.x.x.x.x.", gain = 0.85 },
		chorus = { k = "x...x...x...x...", s = "....x.......x...", h = "xxxxxxxxxxxxxxxx", oh = "..x...x...x...x.", b = ".o.o.o.o.o.o.o.o", arp = "xxxxxxxxxxxxxxxx", pad = "x.......x......." },
	},
	trot = {
		verse = { k = "x.......x.......", s = "....x.......x...", h = "x.x.x.x.x.x.x.x.", b = "r.......f.......", pad = "x...............", gain = 0.85 },
		chorus = { k = "x.......x.......", s = "....x..x....x..x", h = "x.x.x.x.x.x.x.x.", b = "r...o...f...o...", pad = "x.......x.......", arp = "..x...x...x...x." },
	},
	hiphop = {
		verse = { k = "x......x..x.....", s = "....x.......x...", h = "x.x.x.x.x.x.x.x.", b = "r......r..r.....", swing = 0.1, gain = 0.85 },
		chorus = { k = "x......x..x..x..", s = "....x.......x...", h = "x.x.x.x.x.x.x.x.", oh = "..............x.", b = "r......r..r..f..", pad = "x...............", swing = 0.1 },
	},
	rock = {
		verse = { k = "x.......x.x.....", s = "....x.......x...", h = "x.x.x.x.x.x.x.x.", b = "r.r.r.r.r.r.r.r.", gain = 0.9 },
		chorus = { k = "x.x.....x.x.....", s = "....x.......x...", h = "x.x.x.x.x.x.x.x.", oh = "x...x...x...x...", b = "r.r.r.r.f.f.f.f.", pad = "x.......x......." },
	},
	kids = {
		verse = { k = "x.......x.......", s = "....x.......x...", h = "x...x...x...x...", b = "r...f...r...f...", pad = "x.......x.......", gain = 0.75 },
		chorus = { k = "x.......x.......", s = "....x.......x...", h = "x.x.x.x.x.x.x.x.", b = "r...f...r...f...", pad = "x.......x.......", arp = "x...x...x...x..." },
	},
	folk = {
		verse = { k = "x.......x.......", s = "....x.......x...", h = "x...x...x...x...", b = "r.......f.......", pad = "x...............", gain = 0.75 },
		chorus = { k = "x.......x.......", s = "....x.......x...", h = "x.x.x.x.x.x.x.x.", b = "r.......f.......", pad = "x.......x......." },
	},
	ost = {
		verse = { k = "x.........x.....", s = "........x.......", h = "x...x...x...x...", b = "r.......f.......", pad = "x.......x.......", arp = "x.x.x.x.x.x.x.x.", gain = 0.7 },
		chorus = { k = "x.....x...x.....", s = "....x.......x...", h = "x.x.x.x.x.x.x.x.", b = "r.....r.f.......", pad = "x.......x.......", arp = "x.x.x.x.x.x.x.x." },
	},
}
-- 3/4: waltz for pop-like presets, 세마치 for 민요
local P3 = {
	folk = {
		verse = { k = "x...x.......", s = "........x...", h = "x...x...x...", b = "r.......f...", pad = "x...........", gain = 0.8 },
		chorus = { k = "x...x...x...", s = "........x.x.", h = "x.x.x.x.x.x.", b = "r...r...f...", pad = "x...........", arp = "x...x...x..." },
	},
	default = {
		verse = { k = "x...........", s = "....x...x...", h = "x...x...x...", b = "r...........", pad = "x...........", gain = 0.75 },
		chorus = { k = "x...........", s = "....x...x...", h = "x.x.x.x.x.x.", b = "r.......f...", pad = "x...........", arp = "x...x...x..." },
	},
}

local function patternFor(preset: string, meter: number, kind: string): any
	local set
	if meter == 3 then
		set = P3[preset] or P3.default
	else
		set = P4[preset] or P4.pop
	end
	if kind == "chorus" or kind == "inter" then
		return set.chorus
	end
	return set.verse
end

local function sectAt(chart: any, t: number): string
	for _, s in chart.sects do
		if t >= s.t - 1e-6 and t < s.e - 1e-6 then
			return s.kind
		end
	end
	return "outro"
end

local function bassNote(chord: any, ch: string): number
	local b = chord.bass + 12
	if b > 60 then
		b -= 12
	end
	if ch == "f" then
		return b + 7
	elseif ch == "o" then
		return b + 12
	elseif ch == "3" then
		return b + (if chord.q == "m" or chord.q == "m7" or chord.q == "dim" then 3 else 4)
	end
	return b
end

local function chordNotes(chord: any): { number }
	local tones = S.Chart.chordTones(chord.q)
	local out = {}
	local root = 60 + chord.root
	if root > 66 then
		root -= 12
	end
	for _, o in tones do
		table.insert(out, root + o)
	end
	return out
end

-- builds the sorted event list of a chart (cached per chart)
local function build(chart: any): { any }
	local ev = {}
	local meter = chart.meter
	local steps = meter * 4
	local stepT = chart.beat / 4
	local nBars = #chart.chords
	local prevKind = nil
	for bar = 0, nBars - 1 do
		local chord = chart.chords[bar + 1]
		local t0 = bar * chart.bar
		local kind = sectAt(chart, t0 + 0.001)
		local pat = patternFor(chart.preset, meter, kind)
		local swing = pat.swing or 0
		local g = pat.gain or 1
		local lastBar = bar == nBars - 1
		local introFirst = kind == "intro" and bar == 0
		local preFill = (sectAt(chart, t0 + chart.bar + 0.001) ~= kind) and not lastBar
		-- crash at section changes
		if kind ~= prevKind and (kind == "chorus" or kind == "inter" or kind == "outro") then
			table.insert(ev, { t = t0, v = "noise", sp = 0.55, g = 0.32, ch = "drum" })
			table.insert(ev, { t = t0, v = "thud", sp = 0.8, g = 0.9, ch = "drum" })
		end
		prevKind = kind
		if lastBar then
			-- final hit + held chord
			table.insert(ev, { t = t0, v = "thud", sp = 0.75, g = 1, ch = "drum" })
			table.insert(ev, { t = t0, v = "noise", sp = 0.5, g = 0.35, ch = "drum" })
			table.insert(ev, { t = t0, v = "tone", p = bassNote(chord, "r"), g = 0.6, ch = "bass" })
			for _, n in chordNotes(chord) do
				table.insert(ev, { t = t0, v = "tone", p = n, g = 0.2, ch = "pad" })
				table.insert(ev, { t = t0 + chart.beat, v = "tone", p = n + 12, g = 0.1, ch = "pad" })
			end
			continue
		end
		local notes = chordNotes(chord)
		for st = 0, steps - 1 do
			local ch = st + 1
			local tt = t0 + st * stepT
			if swing > 0 and st % 2 == 1 then
				tt += chart.beat * swing
			end
			local fill = preFill and st >= steps - 4
			if not introFirst then
				if string.sub(pat.k, ch, ch) == "x" and not fill then
					table.insert(ev, { t = tt, v = "thud", sp = 0.82, g = 0.85 * g, ch = "drum" })
				end
				local sn = string.sub(pat.s, ch, ch) == "x"
				if sn or (fill and st % 1 == 0) then
					local fg = if fill then 0.45 + 0.1 * (st - (steps - 4)) else 0.7
					table.insert(ev, { t = tt, v = "click", sp = 0.78, g = fg * g, ch = "drum" })
					table.insert(ev, { t = tt, v = "noise", sp = 1.9, g = 0.16 * g, ch = "drum" })
				end
			end
			if string.sub(pat.h, ch, ch) == "x" then
				table.insert(ev, { t = tt, v = "click", sp = 2.35, g = (if st % 4 == 0 then 0.2 else 0.13) * g, ch = "drum" })
			end
			if pat.oh and string.sub(pat.oh, ch, ch) == "x" and not introFirst then
				table.insert(ev, { t = tt, v = "noise", sp = 2.7, g = 0.1 * g, ch = "drum" })
			end
			local bc = string.sub(pat.b, ch, ch)
			if bc ~= "." and bc ~= "" and not introFirst then
				table.insert(ev, { t = tt, v = "tone", p = bassNote(chord, bc), g = 0.5 * g, ch = "bass" })
			end
			if pat.pad and string.sub(pat.pad, ch, ch) == "x" then
				for _, n in notes do
					table.insert(ev, { t = tt, v = "tone", p = n, g = 0.13 * g, ch = "pad" })
				end
			end
			if pat.arp and string.sub(pat.arp, ch, ch) == "x" then
				local n = notes[(st % #notes) + 1] + 12
				table.insert(ev, { t = tt, v = "tone", p = n, g = 0.1 * g, ch = "arp" })
			end
		end
	end
	-- guide melody (long notes re-struck softly so they sustain)
	for _, m in chart.mel do
		table.insert(ev, { t = m.t, v = "tone", p = m.p, g = 0.5, ch = "mel" })
		local k = 1
		while m.d > chart.beat * (k + 0.4) and k < 4 do
			table.insert(ev, { t = m.t + chart.beat * k, v = "tone", p = m.p, g = 0.22, ch = "mel" })
			k += 1
		end
	end
	table.sort(ev, function(a, b)
		return a.t < b.t
	end)
	return ev
end

local function seek(st: number)
	local lo, hi = 1, #events + 1
	while lo < hi do
		local mid = (lo + hi) // 2
		if events[mid].t < st then
			lo = mid + 1
		else
			hi = mid
		end
	end
	idx = lo
end

-------------------------------------------------------------------------------------------------
-- licensed backing track
-------------------------------------------------------------------------------------------------
local function trackOf(song: any): (string?, number, number)
	if not song then
		return nil, 0, 0.5
	end
	local cfg = C.SongAudio[song.id]
	if type(cfg) == "table" and type(cfg.id) == "string" and cfg.id ~= "" then
		return cfg.id, tonumber(cfg.offset) or 0, tonumber(cfg.gain) or 0.5
	end
	if type(song.soundId) == "string" and song.soundId ~= "" then
		return song.soundId, song.soundOffset or 0, 0.5
	end
	return nil, 0, 0.5
end

local trackGain = 0.5
local trackOffset = 0
local function syncTrack(v: any?, st: number)
	local id = v and v.song and trackOf(v.song)
	if not id or not v or not v.chart or st < -0.2 or st > v.chart.duration or v.paused then
		if track.IsPlaying then
			track:Stop()
		end
		return false
	end
	local want = id
	if track.SoundId ~= want then
		local _, off, gain = trackOf(v.song)
		track.SoundId = want
		trackOffset, trackGain = off, gain
	end
	local rate = if v.clock then v.clock.rate else 1
	track.PlaybackSpeed = math.max(rate, 0.05)
	pcall(function()
		trackPitch.Octave = math.clamp(S.keyRatio(v.key or 0) / math.max(rate, 0.05), 0.5, 2)
	end)
	track.Volume = trackGain * 2
	local pos = st + trackOffset
	if pos < 0 then
		return true
	end
	if not track.IsPlaying then
		track.TimePosition = pos
		track:Play()
	elseif math.abs(track.TimePosition - pos) > 0.12 then
		track.TimePosition = pos
	end
	return true
end

-------------------------------------------------------------------------------------------------
-- echo on the guide (fallback when there is no voice rig)
-------------------------------------------------------------------------------------------------
local ECHO = {
	[0] = { on = false },
	[1] = { on = true, delay = 0.08, fb = 0.15, wet = -18, rdecay = 0.8, rwet = -20 },
	[2] = { on = true, delay = 0.12, fb = 0.25, wet = -14, rdecay = 1.2, rwet = -16 },
	[3] = { on = true, delay = 0.16, fb = 0.35, wet = -11, rdecay = 1.6, rwet = -13 },
	[4] = { on = true, delay = 0.22, fb = 0.45, wet = -8, rdecay = 2.2, rwet = -10 },
	[5] = { on = true, delay = 0.3, fb = 0.6, wet = -5, rdecay = 3.5, rwet = -7 },
}
local lastEcho = -1
local function applyEcho(level: number)
	if level == lastEcho then
		return
	end
	lastEcho = level
	local e = ECHO[math.clamp(level, 0, 5)] or ECHO[3]
	echoFx.Enabled = e.on
	reverbFx.Enabled = e.on
	if e.on then
		echoFx.Delay = e.delay
		echoFx.Feedback = e.fb
		echoFx.WetLevel = e.wet
		echoFx.DryLevel = 0
		reverbFx.DecayTime = e.rdecay
		reverbFx.WetLevel = e.rwet
		reverbFx.DryLevel = 0
	end
end

-------------------------------------------------------------------------------------------------
-- effects (탬버린 · 박수 · 환호 · 폭죽 · 꽃가루 · 춤)
-------------------------------------------------------------------------------------------------
local function custom(name: string, vol: number): boolean
	local id = C.Instruments[name]
	if type(id) == "string" and id ~= "" then
		local p = pools["custom_" .. name]
		if not p then
			makePool("custom_" .. name, id, 2, 0, 1, fxGroup)
			p = pools["custom_" .. name]
		end
		play(p, 1, vol)
		return true
	end
	return false
end

function Band.fx(kind: string, near: boolean?)
	local vol = if near == false then 0.5 else 1
	if kind == "tamb" then
		if custom("tamb", vol) then
			return
		end
		play(pools.fxclick, 2.6, 0.5 * vol)
		play(pools.fxnoise, 2.2, 0.22 * vol)
		task.delay(0.045, function()
			play(pools.fxclick, 3.1, 0.35 * vol)
		end)
	elseif kind == "clap" then
		if custom("clap", vol) then
			return
		end
		for i = 0, 5 do
			task.delay(i * 0.07 + math.random() * 0.03, function()
				play(pools.fxclick, 0.95 + math.random() * 0.25, 0.4 * vol)
				play(pools.fxnoise, 1.7 + math.random() * 0.3, 0.12 * vol)
			end)
		end
	elseif kind == "cheer" then
		if custom("cheer", vol) then
			return
		end
		play(pools.fxnoise, 0.8, 0.35 * vol)
		for i, m in { 72, 76, 79, 84 } do
			task.delay(i * 0.07, function()
				play(pools.fxtone, 2 ^ ((m - pools.fxtone.base) / 12), 0.35 * vol)
			end)
		end
	elseif kind == "fire" then
		if custom("firework", vol) then
			return
		end
		play(pools.fxnoise, 0.55, 0.3 * vol)
		task.delay(0.55, function()
			play(pools.fxthud, 0.45, 1 * vol)
			play(pools.fxsplash, 1.3, 0.4 * vol)
			for i = 1, 5 do
				task.delay(0.08 * i + math.random() * 0.05, function()
					play(pools.fxclick, 1.6 + math.random(), 0.25 * vol)
				end)
			end
		end)
	elseif kind == "petal" then
		for i = 1, 6 do
			task.delay(i * 0.09, function()
				local m = 84 + ({ 0, 4, 7, 12, 7, 4 })[i]
				play(pools.fxtone, 2 ^ ((m - pools.fxtone.base) / 12), 0.18 * vol)
			end)
		end
	elseif kind == "dance" then
		for i = 0, 3 do
			task.delay(i * 0.12, function()
				play(pools.fxthud, 0.8, 0.6 * vol)
				play(pools.fxclick, 0.8, 0.4 * vol)
			end)
		end
	elseif kind == "coin" then
		play(pools.fxtone, 1.5, 0.4)
		task.delay(0.09, function()
			play(pools.fxtone, 2, 0.4)
		end)
	elseif kind == "drum" then
		-- 두구두구 (score drumroll)
		for i = 0, 15 do
			task.delay(i * 0.09, function()
				play(pools.fxthud, 0.7 + i * 0.01, 0.35 + i * 0.03)
			end)
		end
	elseif kind == "fanfare" then
		for i, m in { 72, 76, 79, 84, 79, 84, 88 } do
			task.delay((i - 1) * 0.12, function()
				play(pools.fxtone, 2 ^ ((m - pools.fxtone.base) / 12), 0.45)
			end)
		end
		play(pools.fxnoise, 0.6, 0.3)
	elseif kind == "count" then
		play(pools.fxclick, 1.4, 0.4)
	end
end

-------------------------------------------------------------------------------------------------
-- frame update
-------------------------------------------------------------------------------------------------
local function chooseTarget(): (any?, boolean)
	local cur = K.Rooms.current()
	if cur then
		return cur, false
	end
	-- corridor: the nearest playing room, muffled
	local pos = K.Rooms.rootPos()
	if not pos then
		return nil, false
	end
	local best, bd = nil, 15
	for _, v in K.Rooms.views do
		if v.state == "play" and v.panel and v.panel.Parent then
			local d = (v.panel.Position - pos).Magnitude
			if d < bd then
				best, bd = v, d
			end
		end
	end
	return best, best ~= nil
end

function Band.setSettings(st: any)
	if type(st) ~= "table" then
		return
	end
	settings.bandVol = tonumber(st.bandVol) or settings.bandVol
	settings.guideVol = tonumber(st.guideVol) or settings.guideVol
end

function Band.update(_dt: number)
	local v, muf = chooseTarget()
	if v ~= target or muf ~= muffled then
		target = v
		muffled = muf
		lastSt = -math.huge
		muffle.Enabled = muf
	end
	local mute = K.Kit.muted()
	master.Volume = if mute then 0 elseif muffled then 0.28 else 1
	if not v or v.state ~= "play" or not v.chart or not v.clock then
		if track.IsPlaying then
			track:Stop()
		end
		lastSt = -math.huge
		return
	end
	local chart = v.chart
	local key = chart.id .. ":" .. chart.preset
	if key ~= eventsKey then
		events = build(chart)
		eventsKey = key
		lastSt = -math.huge
	end
	if v.serial ~= targetSerial then
		targetSerial = v.serial
		lastSt = -math.huge
	end
	applyEcho(if v.voiceRig then 0 else (v.echo or 0))
	local hasTrack = false
	local st = K.Rooms.songTime(v, S.now()) - Band.localDelay
	hasTrack = syncTrack(v, st)
	bandGroup.Volume = settings.bandVol * (if hasTrack then 0 else 1)
	guideGroup.Volume = if v.guide and not muffled then settings.guideVol else 0
	if v.paused then
		lastSt = st
		return
	end
	-- jumps (join mid-song, restart, tempo change, pause) re-seek without replaying the past
	if st < lastSt - 0.05 or st > lastSt + 0.6 then
		seek(st - 0.02)
	end
	local horizon = st + 0.015
	while idx <= #events and events[idx].t <= horizon do
		local e = events[idx]
		idx += 1
		if e.t < st - 0.15 then
			continue
		end
		if e.ch == "mel" then
			if v.guide and not muffled then
				tone("guide", e.p, e.g)
			end
		elseif not hasTrack then
			if e.v == "tone" then
				tone(if e.ch == "bass" then "bass" else "tone", e.p, e.g)
			else
				play(pools[e.v], e.sp, e.g)
			end
		end
	end
	lastSt = st
end

function Band.init(k: any)
	K = k
	S, C = k.S, k.S.Config
	local old = SoundService:FindFirstChild(S.NAMES.SoundFolder)
	if old then
		old:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = S.NAMES.SoundFolder
	folder.Parent = SoundService
	master = Instance.new("SoundGroup")
	master.Name = "Master"
	master.Volume = 1
	master.Parent = folder
	muffle = Instance.new("EqualizerSoundEffect")
	muffle.HighGain = -40
	muffle.MidGain = -14
	muffle.LowGain = 2
	muffle.Enabled = false
	muffle.Parent = master
	bandGroup = Instance.new("SoundGroup")
	bandGroup.Name = "Band"
	bandGroup.Parent = master
	guideGroup = Instance.new("SoundGroup")
	guideGroup.Name = "Guide"
	guideGroup.Parent = master
	fxGroup = Instance.new("SoundGroup")
	fxGroup.Name = "Fx"
	fxGroup.Volume = 0.9
	fxGroup.Parent = master
	echoFx = Instance.new("EchoSoundEffect")
	echoFx.Enabled = false
	echoFx.Parent = guideGroup
	reverbFx = Instance.new("ReverbSoundEffect")
	reverbFx.Enabled = false
	reverbFx.Parent = guideGroup
	-- 소리 샘플 (Config.Samples) + 선택 악기 (Config.Instruments)
	local smp = C.Samples
	local inst = C.Instruments
	local function sid(name: string, fallback: string): string
		local v = inst[name]
		return if type(v) == "string" and v ~= "" then v else fallback
	end
	makePool("tone", smp.tone.id, 14, smp.tone.midi, smp.tone.gain, bandGroup)
	makePool("bass", smp.tone.id, 4, smp.tone.midi, smp.tone.gain, bandGroup)
	makePool("guide", smp.tone.id, 6, smp.tone.midi, smp.tone.gain, guideGroup)
	makePool("click", sid("hat", smp.click.id), 10, 0, smp.click.gain, bandGroup)
	makePool("thud", sid("kick", smp.thud.id), 4, 0, smp.thud.gain, bandGroup)
	makePool("noise", sid("snare", smp.noise.id), 5, 0, smp.noise.gain, bandGroup)
	makePool("fxclick", smp.click.id, 6, 0, smp.click.gain, fxGroup)
	makePool("fxnoise", smp.noise.id, 3, 0, smp.noise.gain, fxGroup)
	makePool("fxthud", smp.thud.id, 3, 0, smp.thud.gain, fxGroup)
	makePool("fxtone", smp.tone.id, 6, smp.tone.midi, smp.tone.gain, fxGroup)
	makePool("fxsplash", smp.splash.id, 2, 0, smp.splash.gain, fxGroup)
	track = Instance.new("Sound")
	track.Name = "Track"
	track.Looped = false
	track.SoundGroup = master
	track.Parent = folder
	trackPitch = Instance.new("PitchShiftSoundEffect")
	trackPitch.Octave = 1
	trackPitch.Parent = track
end

return Band
