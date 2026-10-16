-- GwangalliKaraokePlus/Rhythm (client): the singer HUD while I sing.
--   * lyric strip (current + next line) so phones can read along without looking at the TV;
--   * 박자 모드 (no voice device, or setting "박자"): a 3-lane note strip scrolling to the hit line, a big
--     "♪ 박자" touch button, keys F / K and gamepad R2. Presses are judged locally for instant feedback
--     and sent in batches {i, dt} to the server, which judges again (authoritative);
--   * 목소리 모드: a live mic level meter ("마이크를 가까이 · 가사 색을 따라 불러요").

local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")

local Rhythm = {}

local K: any
local S: any
local Kit: any
local player = Players.LocalPlayer

local hud: Frame
local lane: Frame
local hitLine: Frame
local noteFrames: { Frame } = {}
local tapBtn: TextButton
local meter: Frame
local meterFill: Frame
local lyricCur: TextLabel
local lyricNext: TextLabel
local judgeLbl: TextLabel
local hintLbl: TextLabel

local LANE_W, LANE_H = 600, 96
local HIT_X = 70
local AHEAD = 2.4
local active = false
local bound = false
local serial = -1
local judged: { [number]: string } = {}
local missShown: { [number]: boolean } = {}
local pending: { { i: number, dt: number } } = {}
local lastSend = 0
local combo = 0
local judgeT = -math.huge
local inflight = false
local lastSt = -math.huge

local function room(): any?
	local v = K.Rooms.current()
	if v and v.state == "play" and v.chart and K.Rooms.isSinger(v) then
		return v
	end
	return nil
end

local function showJudge(j: string)
	if j == "P" then
		judgeLbl.Text = "PERFECT"
		judgeLbl.TextColor3 = Kit.C.gold
	elseif j == "G" then
		judgeLbl.Text = "GOOD"
		judgeLbl.TextColor3 = Kit.C.cyan
	else
		judgeLbl.Text = "MISS"
		judgeLbl.TextColor3 = Kit.C.faint
	end
	judgeT = os.clock()
	K.TV.judge(j, combo, nil)
end

local function flush(v: any)
	if #pending == 0 or inflight then
		return
	end
	if os.clock() - lastSend < 0.2 and #pending < 8 then
		return
	end
	local batch = {}
	while #batch < 24 and #pending > 0 do
		table.insert(batch, table.remove(pending, 1))
	end
	lastSend = os.clock()
	inflight = true
	K.Net.call("hits", { room = v.no, serial = v.serial, hits = batch }, function(res)
		inflight = false
		if res.ok and type(res.combo) == "number" then
			combo = res.combo
		end
	end, true)
end

function Rhythm.tap()
	local v = room()
	if not v or v.paused then
		return
	end
	local c = v.chart
	local st = K.Rooms.songTime(v, S.now())
	local rate = math.max(v.clock and v.clock.rate or 1, 0.5)
	local win = S.Score.WIN.early * rate
	local best, bd = nil, math.huge
	for i, n in c.taps do
		if n.t > st + win then
			break
		end
		if not judged[i] then
			local d = math.abs(st - n.t)
			if d <= win and d < bd then
				best, bd = i, d
			end
		end
	end
	Kit.tween(tapBtn, 0.06, { BackgroundTransparency = 0.35 })
	task.delay(0.08, function()
		Kit.tween(tapBtn, 0.15, { BackgroundTransparency = 0 })
	end)
	if not best then
		return
	end
	local dt = st - c.taps[best].t
	local j = S.Score.judge(dt / rate) or "M"
	judged[best] = j
	if j == "M" then
		combo = 0
	else
		combo += 1
	end
	showJudge(j)
	table.insert(pending, { i = best, dt = math.floor(dt * 1000 + 0.5) / 1000 })
	-- a light tap sound on the beat
	K.Band.fx("tamb", false)
end

local function bind(on: boolean)
	if on == bound then
		return
	end
	bound = on
	if on then
		ContextActionService:BindAction("GwKP_Tap", function(_, state)
			if state == Enum.UserInputState.Begin then
				Rhythm.tap()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.F, Enum.KeyCode.K, Enum.KeyCode.ButtonR2)
	else
		ContextActionService:UnbindAction("GwKP_Tap")
	end
end

function Rhythm.update(_dt: number)
	local v = room()
	local voice = K.Mic.live and not (K.me and K.me.settings and K.me.settings.mode == "tap")
	local want = v ~= nil
	if want ~= active then
		active = want
		hud.Visible = want
	end
	if not v then
		bind(false)
		return
	end
	if v.serial ~= serial then
		serial = v.serial
		table.clear(judged)
		table.clear(missShown)
		table.clear(pending)
		combo = 0
	end
	local c = v.chart
	local st = K.Rooms.songTime(v, S.now())
	if st < lastSt - 1.5 then
		-- 처음부터
		table.clear(judged)
		table.clear(missShown)
		table.clear(pending)
		combo = 0
	end
	lastSt = st
	lane.Visible = not voice
	tapBtn.Visible = not voice
	meter.Visible = voice
	local how = if Kit.touch() then "노트가 선에 닿을 때 ♪ 박자 버튼!" else "노트가 선에 닿을 때 F · K (패드 R2)"
	hintLbl.Text = if voice then "🎤 마이크를 가까이 · 가사 색을 따라 불러요" elseif not K.Mic.hasDevice() then "음성 채팅이 꺼져 있어 박자 모드로 채점해요 · " .. how else how
	bind(not voice)
	-- lyric strip
	local li = S.Chart.lineAt(c, st)
	local l = c.lines[li]
	local nl = c.lines[li + 1]
	if l and st >= l.show - 0.5 then
		lyricCur.Text = l.text
		lyricCur.TextColor3 = K.Lyrics.PART[l.part] or Kit.C.text
		lyricNext.Text = if nl then nl.text else ""
	else
		lyricCur.Text = ""
		lyricNext.Text = ""
	end
	if voice then
		meterFill.Size = UDim2.fromScale(math.clamp(K.Mic.level, 0, 1), 1)
		meterFill.BackgroundColor3 = if K.Mic.level > 0.25 then Kit.C.green else Kit.C.cyan
	else
		-- notes
		local rate = math.max(v.clock and v.clock.rate or 1, 0.5)
		local good = S.Score.WIN.good * rate
		local k = 0
		for i, n in c.taps do
			local ahead = n.t - st
			if ahead > AHEAD then
				break
			end
			if ahead < -0.4 then
				if not judged[i] and not missShown[i] and ahead < -good then
					missShown[i] = true
					judged[i] = "M"
					combo = 0
					showJudge("M")
				end
				continue
			end
			k += 1
			local f = noteFrames[k]
			if not f then
				break
			end
			f.Visible = judged[i] == nil or (judged[i] ~= "M" and ahead > -0.15)
			local x = HIT_X + (ahead / AHEAD) * (LANE_W - HIT_X - 20)
			f.Position = UDim2.fromOffset(x, 14 + (3 - n.lane) * 26)
			f.BackgroundColor3 = if judged[i] == "P" then Kit.C.gold elseif judged[i] == "G" then Kit.C.cyan elseif n.lane == 3 then Kit.C.magenta elseif n.lane == 2 then Kit.C.violet else Kit.C.cyan
		end
		for j = k + 1, #noteFrames do
			noteFrames[j].Visible = false
		end
		flush(v)
	end
	local a = math.clamp((os.clock() - judgeT - 0.35) / 0.3, 0, 1)
	judgeLbl.TextTransparency = a
end

function Rhythm.init(k: any)
	K = k
	S, Kit = k.S, k.Kit
	hud = Kit.new("Frame", { Name = "SingerHud", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -92), Size = UDim2.fromOffset(LANE_W, 200), Visible = false, ZIndex = 10 }, Kit.gui)
	local strip = Kit.new("Frame", { BackgroundColor3 = Kit.C.glass, BackgroundTransparency = 0.25, Size = UDim2.fromOffset(LANE_W, 78), ZIndex = 10 }, hud)
	Kit.corner(strip, 16)
	lyricCur = Kit.text(strip, { Text = "", Font = Kit.F.black, TextSize = 26, Position = UDim2.fromOffset(16, 6), Size = UDim2.new(1, -32, 0, 34), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 11, TextTruncate = Enum.TextTruncate.AtEnd })
	lyricNext = Kit.text(strip, { Text = "", Font = Kit.F.bold, TextSize = 18, TextColor3 = Kit.C.sub, Position = UDim2.fromOffset(16, 42), Size = UDim2.new(1, -32, 0, 26), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 11, TextTruncate = Enum.TextTruncate.AtEnd })
	lane = Kit.new("Frame", { BackgroundColor3 = Color3.fromRGB(8, 10, 22), BackgroundTransparency = 0.2, Position = UDim2.fromOffset(0, 86), Size = UDim2.fromOffset(LANE_W, LANE_H), ClipsDescendants = true, ZIndex = 10 }, hud)
	Kit.corner(lane, 16)
	for r = 0, 2 do
		Kit.new("Frame", { BackgroundColor3 = Kit.C.card3, BackgroundTransparency = 0.6, BorderSizePixel = 0, Position = UDim2.fromOffset(12, 24 + r * 26), Size = UDim2.new(1, -24, 0, 2), ZIndex = 10 }, lane)
	end
	hitLine = Kit.new("Frame", { BackgroundColor3 = Kit.C.gold, BorderSizePixel = 0, Position = UDim2.fromOffset(HIT_X + 10, 8), Size = UDim2.fromOffset(4, LANE_H - 16), ZIndex = 12 }, lane)
	for i = 1, 24 do
		local f = Kit.new("Frame", { BackgroundColor3 = Kit.C.cyan, Size = UDim2.fromOffset(20, 20), Visible = false, ZIndex = 13 }, lane)
		Kit.corner(f, 10)
		Kit.stroke(f, Kit.C.white, 2, 0.3)
		noteFrames[i] = f
	end
	judgeLbl = Kit.text(hud, { Text = "", Font = Kit.F.black, TextSize = 28, Position = UDim2.fromOffset(0, 86 + LANE_H + 4), Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 12 })
	hintLbl = Kit.text(hud, { Text = "", Font = Kit.F.medium, TextSize = 13, TextColor3 = Kit.C.sub, Position = UDim2.fromOffset(0, -20), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 12 })
	meter = Kit.new("Frame", { BackgroundColor3 = Color3.fromRGB(8, 10, 22), BackgroundTransparency = 0.2, Position = UDim2.fromOffset(60, 100), Size = UDim2.fromOffset(LANE_W - 120, 22), Visible = false, ZIndex = 10 }, hud)
	Kit.corner(meter, 11)
	meterFill = Kit.new("Frame", { BackgroundColor3 = Kit.C.green, Size = UDim2.fromScale(0, 1), BorderSizePixel = 0, ZIndex = 11 }, meter)
	Kit.corner(meterFill, 11)
	tapBtn = Kit.btn(Kit.gui, { name = "GwKP_Tap", text = "♪\n박자", style = "magenta", size = UDim2.fromOffset(96, 96), anchor = Vector2.new(1, 1), pos = UDim2.new(1, -24, 1, -200), textSize = 20, radius = 48, sound = false, onClick = function()
		Rhythm.tap()
	end })
	tapBtn.Visible = false
	tapBtn.ZIndex = 12
	hud:GetPropertyChangedSignal("Visible"):Connect(function()
		if not hud.Visible then
			tapBtn.Visible = false
		end
	end)
	Kit.onLayout(function()
		local W = Kit.size()
		local w = math.min(LANE_W, W - 40)
		hud.Size = UDim2.fromOffset(w, 200)
	end)
end

return Rhythm
