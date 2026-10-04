-- GwangalliVenues/Karaoke: 광안 코인노래연습장 on the client (owner: venues_detail).
--   * room status for every room streamed in: corridor StatusLight green / red, door panel 빈 방 / 이용 중
--   * inside a rented room: compact action bar (노래 선택 / 탬버린 / 나가기) in the bottom-centre band
--   * the room TV (SurfaceGui "KaraokeTV" on KaraokeScreen, the room's attributes = server state, so
--     everyone in the room sees the same screen): countdown, song card, scrolling ORIGINAL lyrics
--     with a karaoke wipe, a pitch lane with the notes, live score + combo, the result fanfare
--     (count-up, comment, confetti for 90+), idle screen with the remaining paid time
--   * rhythm taps ('♪ 박자' button / Space / F): perfect / good / miss per note, note judgements sent
--     once per song (kScore; the server computes the score)
--   * chiptune backing (built-in rbxasset sounds, original melody from the chart), mirror ball spin
--     + one local PointLight while a song plays (client-only light: no place light budget)
-- Server: GwangalliGameplay/VenueKaraoke (kSong / kStop / kScore / kLeave, events kOpen / kResult).

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Karaoke = {}

local C: any
local K: any
local V: any

type Room = { model: Model, no: number, zone: BasePart?, screen: BasePart?, panel: BasePart?, status: BasePart?, ball: BasePart? }
local rooms: { [Model]: Room } = {}
local cur: Room? = nil -- the room the local player stands in

-- song state of the current room (rebuilt when KSerial changes)
type Song = { serial: number, id: string, song: any, chart: any, start: number, judged: { [number]: string }, perfect: number, good: number, combo: number, best: number, submitted: boolean, nextNote: number, nextBeat: number, wasInside: boolean }
local song: Song? = nil

local tv: any = nil -- SurfaceGui pieces for the current room
local bar: any = nil -- ScreenGui action bar
local strip: any = nil -- ScreenGui lyric strip + tap button
local picker: any = nil
local resultShownSerial = -1
local discoLight: PointLight? = nil
local ballBase: CFrame? = nil
local ballRoom: Room? = nil

local NOTE_POOL = 14
local PX_PER_SEC = 250
local HIT_X = 190

-------------------------------------------------------------------------------------------------
-- helpers
-------------------------------------------------------------------------------------------------
local function attr(r: Room, name: string): any
	return r.model:GetAttribute(name)
end

local function rented(r: Room): boolean
	local u = attr(r, "KRenter")
	return type(u) == "number" and u ~= 0
end

local function inside(r: Room, pos: Vector3): boolean
	local z = r.zone
	if not z or not z.Parent then
		return false
	end
	local lp = z.CFrame:PointToObjectSpace(pos)
	local h = z.Size / 2
	return math.abs(lp.X) <= h.X + 0.5 and math.abs(lp.Y) <= h.Y + 3 and math.abs(lp.Z) <= h.Z + 0.5
end

local function setup(m: Instance)
	if not m:IsA("Model") or rooms[m] then
		return
	end
	local r: Room = { model = m, no = tonumber(m:GetAttribute("RoomNo")) or 0, zone = nil, screen = nil, panel = nil, status = nil, ball = nil }
	local function find(name: string): BasePart?
		local p = m:FindFirstChild(name, true)
		return if p and p:IsA("BasePart") then p else nil
	end
	r.zone = find("KaraokeZone")
	r.screen = find("KaraokeScreen")
	r.panel = find("KaraokePanel")
	r.status = find("StatusLight")
	r.ball = find("MirrorBall")
	rooms[m] = r
	local function paint()
		local busy = rented(r)
		if r.status then
			r.status.Color = if busy then Color3.fromRGB(255, 60, 60) else Color3.fromRGB(60, 255, 120)
		end
		local g = r.panel and r.panel:FindFirstChild("SignGui")
		local sub = g and g:FindFirstChild("Sub", true)
		if sub and sub:IsA("TextLabel") then
			sub.Text = if busy then "이용 중 · " .. tostring(attr(r, "KRenterName") or "") else "빈 방 · 터치"
		end
	end
	m:GetAttributeChangedSignal("KRenter"):Connect(paint)
	paint()
end

-------------------------------------------------------------------------------------------------
-- TV (SurfaceGui on the room's screen)
-------------------------------------------------------------------------------------------------
local function label(parent: Instance, props: any): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextScaled = false
	for k, v in props do
		(l :: any)[k] = v
	end
	l.Parent = parent
	return l
end

local function frame(parent: Instance, props: any): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for k, v in props do
		(f :: any)[k] = v
	end
	f.Parent = parent
	return f
end

local function destroyTv()
	if tv then
		if tv.gui then
			tv.gui:Destroy()
		end
		if tv.sign then
			tv.sign.Enabled = true
		end
		tv = nil
	end
end

local function buildTv(r: Room)
	if tv and tv.room == r then
		return tv
	end
	destroyTv()
	local scr = r.screen
	if not scr then
		return nil
	end
	local sg = Instance.new("SurfaceGui")
	sg.Name = "KaraokeTV"
	sg.Face = Enum.NormalId.Back
	sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	sg.CanvasSize = Vector2.new(1024, 580)
	sg.LightInfluence = 0
	sg.Brightness = 1.4
	sg.MaxDistance = 80
	sg.ResetOnSpawn = false
	local bg = frame(sg, { Name = "BG", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1) })
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 10, 60)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(40, 12, 90)), ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 30, 80)) })
	grad.Rotation = 20
	grad.Parent = bg
	-- top bar
	local top = frame(bg, { Name = "Top", Size = UDim2.new(1, 0, 0, 70), BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.45 })
	local num = label(top, { Name = "Num", Position = UDim2.fromOffset(18, 0), Size = UDim2.fromOffset(170, 70), Text = "", TextSize = 30, Font = Enum.Font.RobotoMono, TextColor3 = Color3.fromRGB(120, 255, 170), TextXAlignment = Enum.TextXAlignment.Left })
	local title = label(top, { Name = "Title", Position = UDim2.fromOffset(190, 4), Size = UDim2.new(1, -460, 0, 38), Text = "", TextSize = 32, Font = Enum.Font.GothamBlack })
	local artist = label(top, { Name = "Artist", Position = UDim2.fromOffset(190, 40), Size = UDim2.new(1, -460, 0, 24), Text = "", TextSize = 20, TextColor3 = Color3.fromRGB(200, 200, 230), Font = Enum.Font.GothamMedium })
	local score = label(top, { Name = "Score", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 2), Size = UDim2.fromOffset(250, 40), Text = "SCORE 00", TextSize = 32, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 214, 70), TextXAlignment = Enum.TextXAlignment.Right })
	local combo = label(top, { Name = "Combo", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 42), Size = UDim2.fromOffset(250, 24), Text = "", TextSize = 20, TextColor3 = Color3.fromRGB(120, 230, 255), TextXAlignment = Enum.TextXAlignment.Right })
	-- pitch lane
	local lane = frame(bg, { Name = "Lane", Position = UDim2.fromOffset(0, 104), Size = UDim2.new(1, 0, 0, 200), BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.6, ClipsDescendants = true })
	for i = 1, 4 do
		frame(lane, { Name = "Guide", Position = UDim2.fromOffset(0, i * 40), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.88 })
	end
	local hit = frame(lane, { Name = "HitLine", Position = UDim2.fromOffset(HIT_X - 2, 0), Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = Color3.fromRGB(255, 80, 170) })
	local hitGlow = frame(lane, { Name = "HitGlow", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(HIT_X, 0), Size = UDim2.new(0, 26, 1, 0), BackgroundColor3 = Color3.fromRGB(255, 80, 170), BackgroundTransparency = 0.8 })
	local notes = {}
	for i = 1, NOTE_POOL do
		local n = frame(lane, { Name = "Note", Size = UDim2.fromOffset(46, 16), BackgroundColor3 = Color3.fromRGB(255, 220, 90), Visible = false })
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = n
		notes[i] = n
	end
	local judge = label(lane, { Name = "Judge", Position = UDim2.fromOffset(HIT_X + 20, 10), Size = UDim2.fromOffset(260, 40), Text = "", TextSize = 34, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left })
	-- lyrics
	local lyr = frame(bg, { Name = "Lyrics", Position = UDim2.fromOffset(0, 330), Size = UDim2.new(1, 0, 0, 200), BackgroundTransparency = 1 })
	local line1 = label(lyr, { Name = "Line", Position = UDim2.fromOffset(40, 0), Size = UDim2.new(1, -80, 0, 80), Text = "", TextSize = 60, Font = Enum.Font.GothamBlack, TextStrokeTransparency = 0.3 })
	local wipe = frame(lyr, { Name = "Wipe", Position = UDim2.fromOffset(40, 0), Size = UDim2.new(0, 0, 0, 80), BackgroundTransparency = 1, ClipsDescendants = true })
	local line1hi = label(wipe, { Name = "LineHi", Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(944, 80), Text = "", TextSize = 60, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 214, 70), TextStrokeTransparency = 0.3 })
	local line2 = label(lyr, { Name = "Next", Position = UDim2.fromOffset(40, 96), Size = UDim2.new(1, -80, 0, 56), Text = "", TextSize = 40, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(190, 190, 220), TextStrokeTransparency = 0.6 })
	-- centre messages (countdown / idle) and the result overlay
	local big = label(bg, { Name = "Big", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(900, 160), Text = "", TextSize = 110, Font = Enum.Font.GothamBlack, TextStrokeTransparency = 0.2, ZIndex = 5 })
	local small = label(bg, { Name = "Small", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.52, 70), Size = UDim2.fromOffset(900, 50), Text = "", TextSize = 34, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(220, 220, 255), ZIndex = 5 })
	local result = frame(bg, { Name = "Result", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(10, 4, 30), BackgroundTransparency = 0.15, Visible = false, ZIndex = 8, ClipsDescendants = true })
	local rTitle = label(result, { Name = "RTitle", Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 50), Text = "점수", TextSize = 40, ZIndex = 9 })
	local rScore = label(result, { Name = "RScore", Position = UDim2.fromOffset(0, 110), Size = UDim2.new(1, 0, 0, 220), Text = "0", TextSize = 210, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 214, 70), TextStrokeTransparency = 0.1, ZIndex = 9 })
	local rHead = label(result, { Name = "RHead", Position = UDim2.fromOffset(0, 350), Size = UDim2.new(1, 0, 0, 60), Text = "", TextSize = 50, Font = Enum.Font.GothamBlack, ZIndex = 9 })
	local rSub = label(result, { Name = "RSub", Position = UDim2.fromOffset(0, 420), Size = UDim2.new(1, 0, 0, 44), Text = "", TextSize = 32, TextColor3 = Color3.fromRGB(210, 210, 240), ZIndex = 9 })
	local confetti = {}
	local cols = { Color3.fromRGB(255, 80, 170), Color3.fromRGB(80, 220, 255), Color3.fromRGB(255, 214, 70), Color3.fromRGB(120, 255, 140), Color3.fromRGB(190, 120, 255) }
	for i = 1, 40 do
		local cf = frame(result, { Name = "Confetti", Size = UDim2.fromOffset(14, 22), BackgroundColor3 = cols[(i % #cols) + 1], Visible = false, ZIndex = 10 })
		confetti[i] = { f = cf, x = 0, y = 0, vx = 0, vy = 0, rot = 0, vr = 0 }
	end
	local sign = scr:FindFirstChild("SignGui")
	if sign and sign:IsA("SurfaceGui") then
		sign.Enabled = false
	end
	sg.Parent = scr
	tv = {
		room = r, gui = sg, sign = sign, grad = grad, num = num, title = title, artist = artist, score = score, combo = combo,
		lane = lane, hit = hit, hitGlow = hitGlow, notes = notes, judge = judge, judgeT = 0, line1 = line1, line1hi = line1hi, wipe = wipe,
		line2 = line2, big = big, small = small, result = result, rTitle = rTitle, rScore = rScore, rHead = rHead, rSub = rSub,
		confetti = confetti, confettiOn = false, resultUntil = 0,
	}
	return tv
end

local function showJudge(text: string, color: Color3)
	if tv then
		tv.judge.Text = text
		tv.judge.TextColor3 = color
		tv.judgeT = os.clock()
	end
	if strip then
		C.pop(strip.frame, text, color, UDim2.new(0.5, 0, 0, -12), 20, 0.6)
	end
end

local function startConfetti()
	if not tv then
		return
	end
	tv.confettiOn = true
	local rnd = Random.new()
	for _, c in tv.confetti do
		c.x = rnd:NextNumber(0, 1024)
		c.y = rnd:NextNumber(-400, -10)
		c.vx = rnd:NextNumber(-60, 60)
		c.vy = rnd:NextNumber(160, 320)
		c.rot = rnd:NextNumber(0, 360)
		c.vr = rnd:NextNumber(-360, 360)
		c.f.Visible = true
	end
end

local function fanfare(scoreN: number)
	local seq = if scoreN >= 90 then { 0, 4, 7, 12, 7, 12, 16, 19 } elseif scoreN >= 70 then { 0, 4, 7, 12 } else { 7, 4, 0 }
	for i, semi in seq do
		task.delay((i - 1) * 0.12, function()
			C.note(semi + 5, 0.32)
		end)
	end
end

local function showResult(r: Room)
	local serial = attr(r, "KResultSerial")
	local sc = tonumber(attr(r, "KResultScore")) or 0
	local name = tostring(attr(r, "KResultName") or "")
	if not tv or tv.room ~= r or type(serial) ~= "number" then
		return
	end
	resultShownSerial = serial
	local head, sub = V.scoreComment(sc)
	tv.result.Visible = true
	tv.rTitle.Text = name .. " 님의 점수"
	tv.rHead.Text = head
	tv.rSub.Text = sub
	tv.rScore.Text = "0"
	tv.resultUntil = os.clock() + 7
	fanfare(sc)
	if sc >= 90 then
		startConfetti()
		-- confetti burst from the mirror ball too (client-only emitter, default sparkle texture)
		local ball = r.ball
		if ball then
			local pe = Instance.new("ParticleEmitter")
			pe.Name = "GwConfetti"
			pe.Rate = 0
			pe.Lifetime = NumberRange.new(1.4, 2.2)
			pe.Speed = NumberRange.new(6, 12)
			pe.SpreadAngle = Vector2.new(180, 180)
			pe.Acceleration = Vector3.new(0, -12, 0)
			pe.Size = NumberSequence.new(0.25)
			pe.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 170)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 220, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 214, 70)) })
			pe.LightEmission = 0.6
			pe.Parent = ball
			pe:Emit(80)
			task.delay(3, function()
				pe:Destroy()
			end)
		end
	end
	task.spawn(function()
		local t0 = os.clock()
		while tv and os.clock() - t0 < 1.4 do
			local u = (os.clock() - t0) / 1.4
			tv.rScore.Text = tostring(math.floor(sc * (1 - (1 - u) ^ 3)))
			if math.floor(u * 20) % 2 == 0 then
				C.sound("tap", 1.6, 0.12)
			end
			task.wait(0.05)
		end
		if tv then
			tv.rScore.Text = tostring(sc)
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- Screen UI: action bar, lyric strip + tap button, song picker
-------------------------------------------------------------------------------------------------
local function placeBar()
	if not bar then
		return
	end
	local ok, r = pcall(C.Layout.rect, "bottomCenter")
	local w, x, yb = 360, C.gui.AbsoluteSize.X / 2, C.gui.AbsoluteSize.Y - 8
	if ok and r then
		w = math.clamp(r.w, 260, 380)
		x = r.x + r.w / 2
		yb = r.y + r.h
	end
	bar.frame.Size = UDim2.fromOffset(w, 52)
	bar.frame.Position = UDim2.fromOffset(x, yb)
	if strip then
		strip.frame.Size = UDim2.fromOffset(w, 58)
		strip.frame.Position = UDim2.fromOffset(x, yb - 60)
		local okc, col = pcall(C.Layout.rect, "rightColumn.sprint")
		if okc and col then
			strip.tap.Position = UDim2.fromOffset(col.x + col.w / 2, col.y + col.h / 2 - 20)
		else
			strip.tap.Position = UDim2.new(1, -60, 1, -150)
		end
	end
end

function Karaoke.tap()
	local s = song
	if not s or not cur then
		return
	end
	local t = C.serverNow() - s.start
	local W = V.KARAOKE.scoreWindow
	local best, bd = nil, math.huge
	for i, n in s.chart.notes do
		if not s.judged[i] then
			local d = math.abs(t - n.t)
			if d < bd then
				best, bd = i, d
			end
			if n.t > t + W.good then
				break
			end
		end
	end
	if strip then
		K.pop(strip.tap)
	end
	if best and bd <= W.perfect then
		s.judged[best] = "perfect"
		s.perfect += 1
		s.combo += 1
		showJudge("PERFECT", Color3.fromRGB(120, 255, 150))
		C.sound("tap", 1.4, 0.3)
	elseif best and bd <= W.good then
		s.judged[best] = "good"
		s.good += 1
		s.combo += 1
		showJudge("GOOD", Color3.fromRGB(110, 220, 255))
		C.sound("tap", 1.1, 0.3)
	else
		showJudge("MISS", Color3.fromRGB(170, 170, 190))
		C.sound("tap", 0.7, 0.2)
	end
	s.best = math.max(s.best, s.combo)
end

local function buildBar()
	if bar then
		return
	end
	local f = K.make("Frame", { Name = "KaraokeBar", AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = K.Color.glass, BackgroundTransparency = 0.15, BorderSizePixel = 0, Visible = false, ZIndex = 30 }, C.gui)
	K.corner(f, K.Radius.lg)
	K.stroke(f, K.Color.magenta, 1, 0.7)
	K.list(f, true, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	K.pad(f, 6, 6, 4, 4)
	local pick = K.Button(f, { name = "KaraokePick", text = "노래 선택", icon = "🎵", style = "primary", size = UDim2.new(0.42, 0, 0, 44), order = 1, zIndex = 31, textSize = 13 })
	local tam = K.Button(f, { name = "KaraokeTambourine", text = "탬버린", icon = "🪇", style = "secondary", size = UDim2.new(0.3, 0, 0, 44), order = 2, zIndex = 31, textSize = 13 })
	local leave = K.Button(f, { name = "KaraokeStop", text = "그만", style = "secondary", size = UDim2.new(0.22, 0, 0, 44), order = 3, zIndex = 31, textSize = 13 })
	bar = { frame = f, pick = pick, tam = tam, leave = leave }
	pick.Activated:Connect(function()
		if cur then
			Karaoke.openPicker(cur)
		end
	end)
	tam.Activated:Connect(function()
		C.sound("tap", 1.8, 0.3)
		task.spawn(C.request, "emote", { name = "tambourine" })
	end)
	leave.Activated:Connect(function()
		if not cur then
			return
		end
		local room = cur
		task.spawn(function()
			if song and song.start + song.chart.duration > C.serverNow() then
				C.request("kStop", { room = room.no })
			elseif attr(room, "KRenter") == C.player.UserId then
				C.request("kLeave", { room = room.no })
			end
		end)
	end)
	-- lyric strip + big tap button
	local sf = K.make("Frame", { Name = "KaraokeStrip", AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = Color3.fromRGB(10, 8, 30), BackgroundTransparency = 0.2, BorderSizePixel = 0, Visible = false, ZIndex = 30, ClipsDescendants = true }, C.gui)
	K.corner(sf, K.Radius.md)
	local sLine = K.text(sf, { Name = "Line", Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 28), Text = "", Font = K.Font.heavy, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 31 })
	local sNext = K.text(sf, { Name = "Next", Position = UDim2.fromOffset(10, 32), Size = UDim2.new(1, -20, 0, 16), Text = "", Font = K.Font.medium, TextSize = 12, TextColor3 = K.Color.sub, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 31 })
	local sProg = K.frame(sf, { Name = "Progress", Position = UDim2.new(0, 0, 1, -4), Size = UDim2.new(0, 0, 0, 4), BackgroundTransparency = 0, BackgroundColor3 = K.Color.gold, ZIndex = 31 })
	local tap = K.Button(C.gui, { name = "KaraokeTap", text = "박자", icon = "♪", style = "primary", size = UDim2.fromOffset(76, 76), anchor = Vector2.new(0.5, 0.5), zIndex = 32, textSize = 14, radius = 38 })
	tap.Visible = false
	tap.Activated:Connect(Karaoke.tap)
	strip = { frame = sf, line = sLine, nextLine = sNext, prog = sProg, tap = tap }
	placeBar()
	pcall(function()
		C.Layout.onChanged(placeBar)
	end)
end

function Karaoke.openPicker(r: Room)
	if picker then
		picker.close(true)
		picker.frame:Destroy()
		picker = nil
	end
	local paid = tonumber(attr(r, "KPaidUntil")) or 0
	local left = math.max(0, paid - C.serverNow())
	local sh, scroll = C.sheet("KaraokePicker", string.format("🎤 ROOM %02d · 노래 선택", r.no), string.format("남은 시간 %s · 30분마다 %s 자동 연장", V.mmss(left), V.won(V.KARAOKE.fee)), nil)
	for i, s in V.SONGS do
		local ch = V.chart(s)
		C.row(scroll, {
			name = "Song_" .. s.id,
			icon = "🎵",
			iconColor = if i % 2 == 0 then K.Color.magenta else K.Color.violet,
			title = s.title,
			subtitle = string.format("%s · %s · ♩%d · %s", s.artist, s.genre, s.bpm, V.mmss(ch.duration)),
			trailing = tostring(s.number),
			trailingWidth = 64,
			height = 60,
			order = i,
			onClick = function()
				C.sound("tap")
				sh.close()
				task.spawn(function()
					local res = C.request("kSong", { room = r.no, song = s.id })
					if not res.ok then
						C.toast("warn", "노래방", res.message or "지금은 예약할 수 없어요")
					end
				end)
			end,
		})
	end
	K.text(scroll, { Name = "Hint", Size = UDim2.new(1, 0, 0, 34), Text = "노래가 나오면 ♪ 박자 버튼을 음표에 맞춰 눌러요 · 친구도 같은 방에서 함께 불러요", TextColor3 = K.Color.faint, TextSize = K.Type.micro, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 50, ZIndex = 43 })
	if attr(r, "KRenter") == C.player.UserId then
		local leave = K.Button(scroll, { name = "KaraokeLeave", text = "방 나가기 (이용 종료)", style = "secondary", order = 60, zIndex = 43 })
		leave.Activated:Connect(function()
			sh.close()
			task.spawn(C.request, "kLeave", { room = r.no })
		end)
	end
	picker = sh
	sh.open()
end

-------------------------------------------------------------------------------------------------
-- per-frame update (only while the local player is inside a room)
-------------------------------------------------------------------------------------------------
local function lineAt(chart: any, t: number): (number, any)
	for i, l in chart.lines do
		if t < l.t0 + (chart.bar * 2) then
			return i, l
		end
	end
	return #chart.lines, chart.lines[#chart.lines]
end

local function syncSong(r: Room)
	local id = attr(r, "KSong")
	local serial = tonumber(attr(r, "KSerial")) or 0
	if type(id) ~= "string" or id == "" or not V.SONG_BY_ID[id] then
		if song then
			song = nil
		end
		return
	end
	if song and song.serial == serial then
		return
	end
	local def = V.SONG_BY_ID[id]
	song = { serial = serial, id = id, song = def, chart = V.chart(def), start = tonumber(attr(r, "KStart")) or C.serverNow(), judged = {}, perfect = 0, good = 0, combo = 0, best = 0, submitted = false, nextNote = 1, nextBeat = 0, wasInside = true }
end

local function disco(r: Room?, on: boolean)
	if on and r and r.ball then
		if ballRoom ~= r then
			disco(nil, false)
			ballRoom = r
			ballBase = r.ball.CFrame
			local l = Instance.new("PointLight")
			l.Name = "GwDiscoLight"
			l.Range = 16
			l.Brightness = 1.6
			l.Shadows = false
			l.Parent = r.ball
			discoLight = l
		end
	elseif not on and ballRoom then
		if ballRoom.ball and ballBase then
			ballRoom.ball.CFrame = ballBase
		end
		if discoLight then
			discoLight:Destroy()
			discoLight = nil
		end
		ballRoom = nil
		ballBase = nil
	end
end

local function step()
	local r = cur
	if not r then
		return
	end
	local now = C.serverNow()
	local t = tv
	syncSong(r)
	local s = song
	local playing = s ~= nil and now < s.start + s.chart.duration + 1
	-- action bar / strip visibility
	if bar then
		bar.frame.Visible = rented(r)
		bar.leave.Text = if playing then "취소" elseif attr(r, "KRenter") == C.player.UserId then "나가기" else "그만"
	end
	if strip then
		strip.frame.Visible = playing
		strip.tap.Visible = playing and s ~= nil and now >= s.start - 1
	end
	C.hideHud("karaoke", playing)
	disco(r, playing)
	if not t then
		return
	end
	-- background shimmer
	t.grad.Rotation = (os.clock() * 12) % 360
	if os.clock() - t.judgeT > 0.5 then
		t.judge.Text = ""
	end
	-- result overlay
	if t.result.Visible then
		if os.clock() > t.resultUntil then
			t.result.Visible = false
			t.confettiOn = false
			for _, c in t.confetti do
				c.f.Visible = false
			end
		elseif t.confettiOn then
			local dt = 1 / 30
			for _, c in t.confetti do
				c.y += c.vy * dt
				c.x += c.vx * dt
				c.rot += c.vr * dt
				if c.y > 600 then
					c.y = -20
				end
				c.f.Position = UDim2.fromOffset(c.x, c.y)
				c.f.Rotation = c.rot
			end
		end
	end
	local resSerial = attr(r, "KResultSerial")
	if type(resSerial) == "number" and resSerial ~= resultShownSerial and (tonumber(attr(r, "KResultScore")) or 0) > 0 and s and resSerial == s.serial then
		showResult(r)
	end
	if not s then
		-- idle screen
		for _, n in t.notes do
			n.Visible = false
		end
		t.num.Text = string.format("ROOM %02d", r.no)
		t.title.Text = if rented(r) then "노래를 선택해 주세요 🎤" else "방을 잡아 주세요"
		t.artist.Text = if rented(r) then string.format("남은 시간 %s", V.mmss(math.max(0, (tonumber(attr(r, "KPaidUntil")) or 0) - now))) else "문 옆 패널 · 30분 " .. V.won(V.KARAOKE.fee)
		t.score.Text = ""
		t.combo.Text = ""
		t.line1.Text = ""
		t.line1hi.Text = ""
		t.line2.Text = ""
		t.big.Text = if rented(r) then "♪ SING SING ♪" else "ROOM " .. string.format("%02d", r.no)
		t.small.Text = if rented(r) then "아래 '🎵 노래 선택'을 눌러요" else "빈 방 · 문 옆 패널을 터치하세요"
		return
	end
	local st = now - s.start
	local ch = s.chart
	t.num.Text = "♪ " .. tostring(s.song.number)
	t.title.Text = s.song.title
	t.artist.Text = s.song.artist .. " · " .. s.song.genre
	t.score.Text = string.format("SCORE %02d", V.karaokeScore(s.perfect, s.good, #ch.notes))
	t.combo.Text = if s.combo >= 3 then string.format("%d COMBO", s.combo) else ""
	-- countdown / intro / outro text
	if st < 0 then
		t.big.Text = tostring(math.ceil(-st))
		t.small.Text = s.song.title
	elseif st < ch.intro then
		t.big.Text = ""
		t.small.Text = ""
		t.line1.Text = "♪ 전주 중 ♪"
	elseif st > ch.duration then
		t.big.Text = ""
		t.small.Text = ""
	else
		t.big.Text = ""
		t.small.Text = ""
	end
	-- lyrics + wipe
	if st >= ch.intro - ch.bar and st <= ch.duration then
		local i, l = lineAt(ch, st)
		t.line1.Text = l.text
		t.line1hi.Text = l.text
		local nxt = ch.lines[i + 1]
		t.line2.Text = if nxt then nxt.text else ""
		local p = math.clamp((st - l.t0) / (l.t1 - l.t0), 0, 1)
		-- the wipe covers the text width (TextBounds of the centred label)
		local bounds = t.line1.TextBounds.X
		local x0 = (944 - bounds) / 2
		t.wipe.Position = UDim2.fromOffset(40 + x0, 0)
		t.line1hi.Position = UDim2.fromOffset(-x0, 0)
		t.wipe.Size = UDim2.fromOffset(bounds * p, 80)
		if strip then
			strip.line.Text = l.text
			strip.nextLine.Text = if nxt then nxt.text else ""
			strip.prog.Size = UDim2.new(math.clamp(st / ch.duration, 0, 1), 0, 0, 4)
		end
	elseif strip then
		strip.line.Text = if st < 0 then string.format("%s · %d", s.song.title, math.ceil(-st)) else "♪ " .. s.song.title
		strip.nextLine.Text = s.song.artist
	end
	-- notes
	local W = V.KARAOKE.scoreWindow
	local k = 1
	for i, n in ch.notes do
		local dtn = n.t - st
		if not s.judged[i] and dtn < -W.good then
			s.judged[i] = "miss"
			s.combo = 0
		end
		if dtn > -0.8 and dtn < 3.2 and k <= NOTE_POOL then
			local f = t.notes[k]
			k += 1
			f.Visible = true
			f.Position = UDim2.fromOffset(HIT_X + dtn * PX_PER_SEC - 23, 184 - (n.p / V.PITCH_MAX) * 168)
			local j = s.judged[i]
			f.BackgroundColor3 = if j == "perfect" then Color3.fromRGB(120, 255, 150) elseif j == "good" then Color3.fromRGB(110, 220, 255) elseif j == "miss" then Color3.fromRGB(110, 110, 130) else Color3.fromRGB(255, 220, 90)
		end
		-- chiptune: play each note as it crosses the line
		if i >= s.nextNote and dtn <= 0 and dtn > -0.25 then
			s.nextNote = i + 1
			C.note(n.p, 0.2)
		elseif i >= s.nextNote and dtn <= -0.25 then
			s.nextNote = i + 1
		end
	end
	for j = k, NOTE_POOL do
		t.notes[j].Visible = false
	end
	-- soft metronome on every beat
	if st >= 0 and st < ch.duration then
		local beatIdx = math.floor(st / ch.beat)
		if beatIdx >= s.nextBeat then
			s.nextBeat = beatIdx + 1
			C.sound("tap", if beatIdx % 4 == 0 then 0.9 else 1.3, 0.08)
			t.hitGlow.BackgroundTransparency = 0.55
		else
			t.hitGlow.BackgroundTransparency = math.min(0.85, t.hitGlow.BackgroundTransparency + 0.04)
		end
	end
	-- mirror ball spin + light colour cycle
	if ballRoom and ballRoom.ball and ballBase then
		ballRoom.ball.CFrame = ballBase * CFrame.Angles(0, os.clock() * 1.4, 0)
		if discoLight then
			discoLight.Color = Color3.fromHSV((os.clock() * 0.15) % 1, 0.7, 1)
		end
	end
	-- submit the judgements once the song is over
	if st >= ch.duration and not s.submitted then
		s.submitted = true
		local room = r
		task.spawn(function()
			local res = C.request("kScore", { room = room.no, serial = s.serial, perfect = s.perfect, good = s.good })
			if res and res.ok and res.score then
				C.toast("stat", string.format("🎤 내 점수 %d점", res.score), (V.scoreComment(res.score)))
			end
		end)
	end
end

local function leaveRoom()
	if song and not song.submitted and cur then
		song.submitted = true -- left the room before the end: no score
	end
	song = nil
	disco(nil, false)
	destroyTv()
	cur = nil
	if bar then
		bar.frame.Visible = false
	end
	if strip then
		strip.frame.Visible = false
		strip.tap.Visible = false
	end
	C.hideHud("karaoke", false)
	if picker then
		picker.close(true)
	end
end

function Karaoke.init(ctx: any)
	C = ctx
	K = ctx.K
	V = ctx.V
	buildBar()
	CollectionService:GetInstanceAddedSignal(V.Tags.KaraokeRoom):Connect(setup)
	CollectionService:GetInstanceRemovedSignal(V.Tags.KaraokeRoom):Connect(function(m)
		if cur and cur.model == m then
			leaveRoom()
		end
		rooms[m :: Model] = nil
	end)
	for _, m in CollectionService:GetTagged(V.Tags.KaraokeRoom) do
		setup(m)
	end
	C.on("kOpen", function(p)
		for _, r in rooms do
			if r.no == p.room then
				Karaoke.openPicker(r)
				return
			end
		end
	end)
	C.on("kResult", function(p)
		if p.mine then
			C.sound("ping", 1.2, 0.3)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not song then
			return
		end
		if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.F then
			Karaoke.tap()
		end
	end)
	local acc, scan = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		scan += dt
		if scan >= 0.25 then
			scan = 0
			local root = C.root()
			local found: Room? = nil
			if root then
				for _, r in rooms do
					if inside(r, root.Position) then
						found = r
						break
					end
				end
			end
			if found ~= cur then
				leaveRoom()
				cur = found
				if found then
					buildTv(found)
				end
			end
		end
		if cur and acc >= 1 / 30 then
			acc = 0
			local ok, err = pcall(step)
			if not ok then
				warn("[GwangalliVenues] karaoke: " .. tostring(err))
			end
		end
	end)
end

return Karaoke
