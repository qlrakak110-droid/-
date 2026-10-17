-- GwangalliKaraokePlus/TV (client): the booth TV, a SurfaceGui in PlayerGui adorned to the room's
-- KaraokeScreen (never parented under map parts), drawn over the legacy screen (ZOffset).
-- Screens (all Korean): idle 동전을 넣어 주세요 (TOP 5 · 신곡 · 오늘의 노래왕 slideshow) / ready 곡을 선택해
-- 주세요 (예약 목록, 다음 곡 카운트다운) / title card (번호 · 제목 · 가수 · 작사작곡 · KEY · TEMPO · 1P 2P) /
-- singing (genre background, two-line wipe lyrics, 간주중, next-song ticker, ECHO · KEY · TEMPO, live
-- judgements, 분위기 meter, emoji rain) / pause / score (두구두구 -> count-up -> grade + comment, 100점
-- celebration, 서비스 1곡) . Other booths get a light "attract" screen (ROOM 03 · 이용 중 · ♪ 제목).

local Players = game:GetService("Players")

local TV = {}

local K: any
local S: any
local Kit: any
local Rooms: any
local Lyrics: any
local Background: any

local W, H = 1280, 730
local player = Players.LocalPlayer
local gui: SurfaceGui
local root: Frame
local bg: any
local lyr: any
local room: any = nil
local L: { [string]: any } = {}
local emojis: { any } = {}
local confetti: { any } = {}
local lite: { [number]: any } = {}
local acc = 0
local lastState = ""
local scoreT0 = 0
local judgeT = -math.huge
local mine: any = nil
local mineSerial = -1
local slideT = 0
local slideI = 0

local function new(class: string, props: { [string]: any }, parent: Instance?): any
	local i = Instance.new(class)
	for k, v in props do
		(i :: any)[k] = v
	end
	if parent then
		i.Parent = parent
	end
	return i
end

-- SurfaceGui with the newer properties set defensively (older engines / test runtimes)
local function surface(props: { [string]: any }): SurfaceGui
	local sg = Instance.new("SurfaceGui")
	for k, v in props do
		pcall(function()
			(sg :: any)[k] = v
		end)
	end
	return sg
end

local function txt(parent: Instance, props: { [string]: any }): TextLabel
	local p: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 40,
		Size = UDim2.fromOffset(W, 60),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 40,
		Text = "",
	}
	for k, v in props do
		if k ~= "stroke" and k ~= "strokeT" then
			p[k] = v
		end
	end
	local l = new("TextLabel", p, parent)
	if props.stroke ~= false then
		new("UIStroke", { Color = Color3.fromRGB(8, 8, 20), Thickness = props.strokeT or 2.5, Transparency = 0.1, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, l)
	end
	return l
end

local function panel(parent: Instance, x: number, y: number, w: number, h: number, transp: number?, z: number?): Frame
	local f = new("Frame", { Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundColor3 = Color3.fromRGB(8, 10, 24), BackgroundTransparency = transp or 0.35, BorderSizePixel = 0, ZIndex = z or 35 }, parent)
	new("UICorner", { CornerRadius = UDim.new(0, 18) }, f)
	return f
end

local function layer(name: string): Frame
	return new("Frame", { Name = name, BackgroundTransparency = 1, Size = UDim2.fromOffset(W, H), Visible = false, ZIndex = 35 }, root)
end

local function stars(n: number): string
	return string.rep("★", n) .. string.rep("☆", 3 - n)
end

local function songLine(s: any): string
	return string.format("%d  %s", s.no, s.title)
end

local function faceOf(scr: BasePart): Enum.NormalId
	local f = scr:GetAttribute("GuiFace")
	if type(f) == "string" then
		local ok, e = pcall(function()
			return (Enum.NormalId :: any)[f]
		end)
		if ok and e then
			return e
		end
	end
	return Enum.NormalId.Back
end

-- Roblox ignores PixelsPerStud under SizingMode FixedSize; previews that size a SurfaceGui by it
-- (the temp studio) then match the screen face too
local function fitPps(sg: SurfaceGui, scr: BasePart, canvasW: number)
	local face = sg.Face
	local w = if face == Enum.NormalId.Left or face == Enum.NormalId.Right then scr.Size.Z else scr.Size.X
	if w > 0.1 then
		pcall(function()
			(sg :: any).PixelsPerStud = canvasW / w
		end)
	end
end

-------------------------------------------------------------------------------------------------
-- build
-------------------------------------------------------------------------------------------------
local function buildIdle()
	local f = layer("Idle")
	L.idle = f
	L.idleRoom = txt(f, { Text = "ROOM 01", TextSize = 34, TextColor3 = Color3.fromRGB(255, 200, 70), Position = UDim2.fromOffset(40, 22), Size = UDim2.fromOffset(300, 44), TextXAlignment = Enum.TextXAlignment.Left })
	L.idleClock = txt(f, { Text = "", TextSize = 30, Position = UDim2.fromOffset(W - 340, 22), Size = UDim2.fromOffset(300, 44), TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.GothamBold })
	L.idleBig = txt(f, { Text = "동전을 넣어 주세요 🪙", TextSize = 84, Position = UDim2.fromOffset(0, 150), Size = UDim2.fromOffset(W, 110), strokeT = 4 })
	L.idleSub = txt(f, { Text = "1곡 500원 · 4곡 1,000원 · 8곡 2,000원", TextSize = 38, TextColor3 = Color3.fromRGB(255, 220, 120), Position = UDim2.fromOffset(0, 262), Size = UDim2.fromOffset(W, 56), Font = Enum.Font.GothamBold })
	L.idleHint = txt(f, { Text = "문 옆 패널이나 반주기 동전 투입구에서 방을 잡아요", TextSize = 26, TextColor3 = Color3.fromRGB(200, 210, 235), Position = UDim2.fromOffset(0, 318), Size = UDim2.fromOffset(W, 40), Font = Enum.Font.GothamBold })
	local box = panel(f, 240, 400, 800, 280, 0.3)
	L.slideTitle = txt(box, { Text = "", TextSize = 34, TextColor3 = Color3.fromRGB(255, 200, 70), Position = UDim2.fromOffset(0, 16), Size = UDim2.fromOffset(800, 44) })
	L.slideRows = {}
	for i = 1, 5 do
		L.slideRows[i] = txt(box, { Text = "", TextSize = 28, Font = Enum.Font.GothamBold, Position = UDim2.fromOffset(40, 64 + (i - 1) * 40), Size = UDim2.fromOffset(720, 38), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
	end
end

local function buildReady()
	local f = layer("Ready")
	L.ready = f
	L.readyRoom = txt(f, { Text = "", TextSize = 32, TextColor3 = Color3.fromRGB(255, 200, 70), Position = UDim2.fromOffset(40, 22), Size = UDim2.fromOffset(600, 44), TextXAlignment = Enum.TextXAlignment.Left })
	L.readyCredits = txt(f, { Text = "", TextSize = 32, Position = UDim2.fromOffset(W - 440, 22), Size = UDim2.fromOffset(400, 44), TextXAlignment = Enum.TextXAlignment.Right })
	L.readyBig = txt(f, { Text = "곡을 선택해 주세요 🎤", TextSize = 80, Position = UDim2.fromOffset(0, 120), Size = UDim2.fromOffset(W, 110), strokeT = 4 })
	L.readySub = txt(f, { Text = "리모컨 · 노래책으로 예약 · 곡 번호로도 예약돼요", TextSize = 30, TextColor3 = Color3.fromRGB(210, 220, 240), Position = UDim2.fromOffset(0, 232), Size = UDim2.fromOffset(W, 44), Font = Enum.Font.GothamBold })
	L.readyWarn = txt(f, { Text = "", TextSize = 28, TextColor3 = Color3.fromRGB(255, 160, 90), Position = UDim2.fromOffset(0, 284), Size = UDim2.fromOffset(W, 40), Font = Enum.Font.GothamBold })
	local box = panel(f, 240, 340, 800, 350, 0.3)
	L.queueTitle = txt(box, { Text = "📋 예약 목록", TextSize = 32, TextColor3 = Color3.fromRGB(120, 220, 255), Position = UDim2.fromOffset(0, 14), Size = UDim2.fromOffset(800, 44) })
	L.queueRows = {}
	for i = 1, 6 do
		L.queueRows[i] = txt(box, { Text = "", TextSize = 28, Font = Enum.Font.GothamBold, Position = UDim2.fromOffset(40, 64 + (i - 1) * 44), Size = UDim2.fromOffset(720, 40), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
	end
	-- next-song countdown overlay
	L.next = new("Frame", { BackgroundColor3 = Color3.fromRGB(5, 6, 16), BackgroundTransparency = 0.25, Size = UDim2.fromOffset(W, H), Visible = false, ZIndex = 45 }, f)
	L.nextNum = txt(L.next, { Text = "", TextSize = 200, TextColor3 = Color3.fromRGB(255, 200, 70), Position = UDim2.fromOffset(0, 150), Size = UDim2.fromOffset(W, 220), ZIndex = 46, strokeT = 5 })
	L.nextTitle = txt(L.next, { Text = "", TextSize = 52, Position = UDim2.fromOffset(0, 400), Size = UDim2.fromOffset(W, 70), ZIndex = 46 })
	L.nextHead = txt(L.next, { Text = "다음 곡", TextSize = 40, TextColor3 = Color3.fromRGB(150, 220, 255), Position = UDim2.fromOffset(0, 90), Size = UDim2.fromOffset(W, 60), ZIndex = 46 })
end

local function chip(parent: Instance, text: string, color: Color3, x: number, y: number): TextLabel
	local l = txt(parent, { Text = text, TextSize = 26, Font = Enum.Font.GothamBold, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 0.15, BackgroundColor3 = color, TextColor3 = Color3.fromRGB(10, 10, 20), stroke = false })
	new("UICorner", { CornerRadius = UDim.new(0, 20) }, l)
	new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, l)
	return l
end

local function buildTitle()
	local f = layer("Title")
	L.title = f
	local card = panel(f, 140, 110, 1000, 470, 0.25)
	L.titleCard = card
	L.tNo = txt(card, { Text = "", TextSize = 44, TextColor3 = Color3.fromRGB(255, 200, 70), Position = UDim2.fromOffset(0, 26), Size = UDim2.fromOffset(1000, 56) })
	L.tTitle = txt(card, { Text = "", TextSize = 92, Position = UDim2.fromOffset(20, 86), Size = UDim2.fromOffset(960, 116), strokeT = 4, TextScaled = false, TextTruncate = Enum.TextTruncate.AtEnd })
	L.tArtist = txt(card, { Text = "", TextSize = 44, TextColor3 = Color3.fromRGB(200, 215, 240), Position = UDim2.fromOffset(0, 200), Size = UDim2.fromOffset(1000, 60), Font = Enum.Font.GothamBold })
	L.tCredit = txt(card, { Text = "", TextSize = 24, TextColor3 = Color3.fromRGB(170, 180, 210), Position = UDim2.fromOffset(20, 262), Size = UDim2.fromOffset(960, 34), Font = Enum.Font.GothamMedium, stroke = false, TextTruncate = Enum.TextTruncate.AtEnd })
	L.tChips = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 312), Size = UDim2.fromOffset(1000, 44), ZIndex = 40 }, card)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, L.tChips)
	L.tSingers = txt(card, { Text = "", TextSize = 32, TextColor3 = Color3.fromRGB(255, 255, 255), Position = UDim2.fromOffset(0, 380), Size = UDim2.fromOffset(1000, 50), Font = Enum.Font.GothamBold })
end

local function buildSing()
	local f = layer("Sing")
	L.sing = f
	local top = new("Frame", { BackgroundColor3 = Color3.fromRGB(4, 6, 16), BackgroundTransparency = 0.3, Size = UDim2.fromOffset(W, 58), BorderSizePixel = 0, ZIndex = 36 }, f)
	L.top = top
	L.topSong = txt(top, { Text = "", TextSize = 28, Font = Enum.Font.GothamBold, Position = UDim2.fromOffset(24, 9), Size = UDim2.fromOffset(620, 40), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 37 })
	L.topNext = txt(top, { Text = "", TextSize = 24, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(150, 220, 255), Position = UDim2.fromOffset(650, 11), Size = UDim2.fromOffset(420, 36), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 37 })
	L.topCredits = txt(top, { Text = "", TextSize = 24, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(255, 210, 100), Position = UDim2.fromOffset(W - 220, 11), Size = UDim2.fromOffset(196, 36), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 37 })
	-- indicators
	L.badges = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(W - 24, 70), Size = UDim2.fromOffset(600, 36), AnchorPoint = Vector2.new(1, 0), ZIndex = 37 }, f)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, L.badges)
	local function badge(order: number): TextLabel
		local b = txt(L.badges, { Text = "", TextSize = 20, Font = Enum.Font.GothamBold, Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 0.35, BackgroundColor3 = Color3.fromRGB(10, 12, 30), LayoutOrder = order, stroke = false, ZIndex = 38 })
		new("UICorner", { CornerRadius = UDim.new(0, 10) }, b)
		new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, b)
		return b
	end
	L.bVoice = badge(1)
	L.bEcho = badge(2)
	L.bKey = badge(3)
	L.bTempo = badge(4)
	-- 분위기 meter
	L.vibeBox = panel(f, 24, 70, 300, 36, 0.35, 37)
	L.vibeLabel = txt(L.vibeBox, { Text = "분위기", TextSize = 20, Font = Enum.Font.GothamBold, Position = UDim2.fromOffset(12, 0), Size = UDim2.fromOffset(80, 36), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 38, stroke = false })
	local track = new("Frame", { BackgroundColor3 = Color3.fromRGB(40, 44, 70), Position = UDim2.fromOffset(92, 12), Size = UDim2.fromOffset(196, 12), BorderSizePixel = 0, ZIndex = 38 }, L.vibeBox)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, track)
	L.vibeFill = new("Frame", { BackgroundColor3 = Color3.fromRGB(255, 100, 180), Size = UDim2.fromScale(0, 1), BorderSizePixel = 0, ZIndex = 39 }, track)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, L.vibeFill)
	new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 200, 70), Color3.fromRGB(255, 70, 170)) }, L.vibeFill)
	-- lyrics
	lyr = Lyrics.new(f, W, 430, "M")
	-- 간주중
	L.inter = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 220), Size = UDim2.fromOffset(W, 200), Visible = false, ZIndex = 40 }, f)
	L.interText = txt(L.inter, { Text = "♬ 간주중 ♬", TextSize = 96, Size = UDim2.fromOffset(W, 120), TextColor3 = Color3.fromRGB(255, 220, 120), strokeT = 4 })
	local itrack = new("Frame", { BackgroundColor3 = Color3.fromRGB(30, 34, 60), BackgroundTransparency = 0.2, Position = UDim2.fromOffset(390, 140), Size = UDim2.fromOffset(500, 14), BorderSizePixel = 0, ZIndex = 41 }, L.inter)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, itrack)
	L.interFill = new("Frame", { BackgroundColor3 = Color3.fromRGB(255, 200, 70), Size = UDim2.fromScale(0, 1), BorderSizePixel = 0, ZIndex = 42 }, itrack)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, L.interFill)
	-- intro / outro caption
	L.caption = txt(f, { Text = "", TextSize = 40, Position = UDim2.fromOffset(0, 300), Size = UDim2.fromOffset(W, 60), Font = Enum.Font.GothamBold, Visible = false })
	-- judgements
	L.judge = txt(f, { Text = "", TextSize = 64, Position = UDim2.fromOffset(40, 300), Size = UDim2.fromOffset(520, 80), TextXAlignment = Enum.TextXAlignment.Left, strokeT = 4 })
	L.combo = txt(f, { Text = "", TextSize = 30, Position = UDim2.fromOffset(44, 372), Size = UDim2.fromOffset(520, 40), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(150, 230, 255) })
	-- progress
	local ptrack = new("Frame", { BackgroundColor3 = Color3.fromRGB(20, 22, 40), BackgroundTransparency = 0.2, Position = UDim2.fromOffset(0, H - 10), Size = UDim2.fromOffset(W, 10), BorderSizePixel = 0, ZIndex = 40 }, f)
	L.progress = new("Frame", { BackgroundColor3 = Color3.fromRGB(61, 214, 245), Size = UDim2.fromScale(0, 1), BorderSizePixel = 0, ZIndex = 41 }, ptrack)
	-- pause
	L.pause = new("Frame", { BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.45, Size = UDim2.fromOffset(W, H), Visible = false, ZIndex = 48 }, f)
	txt(L.pause, { Text = "⏸ 일시정지", TextSize = 110, Position = UDim2.fromOffset(0, 230), Size = UDim2.fromOffset(W, 140), ZIndex = 49 })
	txt(L.pause, { Text = "리모컨에서 다시 재생할 수 있어요", TextSize = 34, Position = UDim2.fromOffset(0, 380), Size = UDim2.fromOffset(W, 50), ZIndex = 49, Font = Enum.Font.GothamBold })
end

local function buildScore()
	local f = layer("Score")
	L.score = f
	L.scoreDim = new("Frame", { BackgroundColor3 = Color3.fromRGB(4, 4, 14), BackgroundTransparency = 0.25, Size = UDim2.fromOffset(W, H), BorderSizePixel = 0, ZIndex = 50 }, f)
	L.scoreGold = new("Frame", { BackgroundColor3 = Color3.fromRGB(255, 190, 60), BackgroundTransparency = 1, Size = UDim2.fromOffset(W, H), BorderSizePixel = 0, ZIndex = 51 }, f)
	L.scoreHead = txt(f, { Text = "", TextSize = 46, Position = UDim2.fromOffset(0, 60), Size = UDim2.fromOffset(W, 60), ZIndex = 55, TextColor3 = Color3.fromRGB(200, 220, 255) })
	L.scoreNum = txt(f, { Text = "", TextSize = 240, Position = UDim2.fromOffset(0, 130), Size = UDim2.fromOffset(W, 250), ZIndex = 55, TextColor3 = Color3.fromRGB(255, 206, 70), strokeT = 6 })
	L.scoreGrade = txt(f, { Text = "", TextSize = 40, Position = UDim2.fromOffset(0, 384), Size = UDim2.fromOffset(W, 56), ZIndex = 55 })
	L.scoreComment = txt(f, { Text = "", TextSize = 42, Position = UDim2.fromOffset(0, 446), Size = UDim2.fromOffset(W, 60), ZIndex = 55, Font = Enum.Font.GothamBold })
	L.scoreExtra = txt(f, { Text = "", TextSize = 30, Position = UDim2.fromOffset(0, 512), Size = UDim2.fromOffset(W, 44), ZIndex = 55, TextColor3 = Color3.fromRGB(150, 230, 255), Font = Enum.Font.GothamBold })
	L.scoreBonus = txt(f, { Text = "🎉 100점! 서비스 1곡!", TextSize = 46, Position = UDim2.fromOffset(0, 566), Size = UDim2.fromOffset(W, 64), ZIndex = 56, TextColor3 = Color3.fromRGB(255, 220, 90), Visible = false })
	L.cards = {}
	for i = 1, 3 do
		local c = panel(f, 0, 360, 360, 250, 0.2, 54)
		c.Visible = false
		local name = txt(c, { Text = "", TextSize = 30, Position = UDim2.fromOffset(0, 16), Size = UDim2.fromOffset(360, 40), ZIndex = 56, Font = Enum.Font.GothamBold })
		local num = txt(c, { Text = "", TextSize = 120, Position = UDim2.fromOffset(0, 56), Size = UDim2.fromOffset(360, 130), ZIndex = 56, TextColor3 = Color3.fromRGB(255, 206, 70), strokeT = 4 })
		local sub = txt(c, { Text = "", TextSize = 24, Position = UDim2.fromOffset(0, 190), Size = UDim2.fromOffset(360, 40), ZIndex = 56, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(200, 215, 240) })
		L.cards[i] = { f = c, name = name, num = num, sub = sub }
	end
	local cols = { Color3.fromRGB(255, 80, 170), Color3.fromRGB(80, 220, 255), Color3.fromRGB(255, 214, 70), Color3.fromRGB(120, 255, 140), Color3.fromRGB(190, 120, 255) }
	for i = 1, 48 do
		local c = new("Frame", { Size = UDim2.fromOffset(16, 26), BackgroundColor3 = cols[(i % #cols) + 1], BorderSizePixel = 0, Visible = false, ZIndex = 58 }, f)
		confetti[i] = { f = c, x = 0, y = 0, vx = 0, vy = 0, r = 0, vr = 0 }
	end
end

local function buildEmojis()
	for i = 1, 24 do
		local l = txt(root, { Text = "", TextSize = 72, Size = UDim2.fromOffset(120, 90), Visible = false, ZIndex = 60, stroke = false })
		local n = txt(l, { Text = "", TextSize = 20, Size = UDim2.fromOffset(160, 26), Position = UDim2.fromOffset(-20, 84), ZIndex = 61, Font = Enum.Font.GothamBold })
		emojis[i] = { l = l, n = n, t0 = -math.huge, x = 0 }
	end
end

-------------------------------------------------------------------------------------------------
-- dynamic content
-------------------------------------------------------------------------------------------------
-- a shown layer is attached to the TV root and a hidden one is parked (Parent nil, kept in L), so
-- renderers that lay a SurfaceGui out only on structural changes draw it at once; Roblox is unaffected
local function setLayer(n: string, on: boolean)
	local f = L[n]
	if f.Visible ~= on then
		f.Visible = on
	end
	local want = if on then root else nil
	if f.Parent ~= want then
		f.Parent = want
	end
end

local function showLayer(name: string)
	for _, n in { "idle", "ready", "title", "sing", "score" } do
		setLayer(n, n == name or (name == "title" and n == "sing"))
	end
end

local function decodeAttr(name: string): any
	local f = K.stateFolder :: Instance
	return S.decode(f:GetAttribute(name))
end

local function fillSlide()
	local kind = slideI % 3
	local rows = {}
	if kind == 0 then
		L.slideTitle.Text = "🔥 이번 주 인기차트 TOP 5"
		local ids = decodeAttr("Chart") or S.Songs.SEED_CHART
		for i = 1, 5 do
			local s = ids[i] and S.Songs.byId[ids[i]]
			rows[i] = if s then string.format("%d위   %d  %s · %s", i, s.no, s.title, s.artist) else ""
		end
	elseif kind == 1 then
		L.slideTitle.Text = "✨ 이달의 신곡"
		local k = 0
		for _, s in S.Songs.LIST do
			if s.tagSet.new and k < 5 then
				k += 1
				rows[k] = string.format("%d  %s · %s", s.no, s.title, s.artist)
			end
		end
	else
		L.slideTitle.Text = "👑 오늘의 노래왕"
		local king = decodeAttr("King") or {}
		for i = 1, 5 do
			local e = king[i]
			rows[i] = if e then string.format("%d.  %s · %d점 · %s", i, e.n, e.s, e.t or "") else (if i == 1 then "아직 기록이 없어요 · 첫 노래왕에 도전!" else "")
		end
	end
	for i = 1, 5 do
		L.slideRows[i].Text = rows[i] or ""
	end
end

local function updateIdle(v: any, t: number)
	L.idleRoom.Text = "ROOM " .. v.name
	L.idleClock.Text = os.date("%H:%M") :: string
	local C = S.Config
	if C.Billing == "free" then
		L.idleBig.Text = "누구나 무료! 🎤"
		L.idleSub.Text = "오늘은 무료 이벤트 · 방을 잡고 마음껏 불러요"
	elseif K.trial then
		L.idleBig.Text = "무료 체험 중 🎤"
		L.idleSub.Text = "패널에서 방을 잡으면 바로 불러요"
	else
		L.idleBig.Text = "동전을 넣어 주세요 🪙"
		local parts = {}
		for _, p in C.Packs do
			table.insert(parts, string.format("%s %s", p.label, S.won(p.price)))
		end
		L.idleSub.Text = table.concat(parts, " · ")
	end
	if t - slideT > 5 then
		slideT = t
		slideI += 1
		fillSlide()
	end
end

local function updateReady(v: any, now: number)
	L.readyRoom.Text = string.format("ROOM %s · %s님의 방", v.name, v.renterName)
	L.readyCredits.Text = if v.unlimited then "남은 곡 ∞" else string.format("남은 곡 %d곡", v.credits)
	local q = v.queue or {}
	if not v.unlimited and v.credits <= 0 then
		L.readyBig.Text = if #q > 0 then "남은 곡이 없어요 🪙" else "동전을 넣어 주세요 🪙"
		L.readySub.Text = "반주기 동전 투입구 · 리모컨에서 곡을 추가할 수 있어요"
	else
		L.readyBig.Text = if #q > 0 then "곧 시작해요 🎤" else "곡을 선택해 주세요 🎤"
		L.readySub.Text = "리모컨 · 노래책으로 예약 · 곡 번호로도 예약돼요"
	end
	if v.idleT and v.idleT > 0 and v.idleT - now < 35 then
		L.readyWarn.Text = string.format("곡을 추가하지 않으면 %d초 뒤 방이 비워져요", math.max(0, math.ceil(v.idleT - now)))
	elseif v.emptyT and v.emptyT > 0 then
		L.readyWarn.Text = string.format("방이 비어 있어요 · %d초 뒤 퇴실돼요", math.max(0, math.ceil(v.emptyT - now)))
	else
		L.readyWarn.Text = ""
	end
	L.queueTitle.Text = string.format("📋 예약 목록 %d곡", #q)
	for i = 1, 6 do
		local e = q[i]
		local s = e and S.Songs.byId[e.s]
		L.queueRows[i].Text = if s then string.format("%d.  %d  %s · %s님", i, s.no, s.title, e.n) else (if i == 1 and #q == 0 then "예약된 곡이 없어요" else "")
	end
	local nextIn = (v.nextT or 0) - now
	local first = q[1] and S.Songs.byId[q[1].s]
	if first and v.nextT > 0 and nextIn > -0.5 and nextIn < 6 then
		L.next.Visible = true
		L.nextNum.Text = tostring(math.max(1, math.ceil(nextIn)))
		L.nextTitle.Text = songLine(first)
	else
		L.next.Visible = false
	end
end

local chipsFor = ""
local function updateTitle(v: any, st: number)
	local s = v.song
	local c = v.chart
	if not (s and c) then
		return
	end
	local key = s.id .. ":" .. tostring(v.key) .. ":" .. tostring(v.tempo)
	if chipsFor ~= key then
		chipsFor = key
		L.tNo.Text = string.format("♪ %d", s.no)
		L.tTitle.Text = s.title
		L.tArtist.Text = s.artist
		L.tCredit.Text = s.credit .. (if s.origin then " · " .. s.origin else "")
		for _, ch in L.tChips:GetChildren() do
			if ch:IsA("TextLabel") then
				ch:Destroy()
			end
		end
		local g = nil
		for _, gg in S.GENRES do
			if gg.id == s.genre then
				g = gg
			end
		end
		local gc = if g then Kit.rgb(g.color) else Color3.fromRGB(200, 200, 220)
		local items = {
			{ (if g then g.emoji .. " " else "") .. s.style, gc },
			{ string.format("BPM %d", s.bpm), Color3.fromRGB(150, 220, 255) },
			{ string.format("KEY %s%s", s.key, if v.key ~= 0 then string.format(" (%s%d)", if v.key > 0 then "♯" else "♭", math.abs(v.key)) else ""), Color3.fromRGB(255, 220, 120) },
			{ string.format("TEMPO %s", if v.tempo == 0 then "0" else string.format("%+d", v.tempo)), Color3.fromRGB(180, 255, 180) },
			{ "난이도 " .. stars(c.stars), Color3.fromRGB(255, 180, 220) },
			{ S.Songs.partLabel(s), Color3.fromRGB(220, 200, 255) },
		}
		for i, it in items do
			local l = chip(L.tChips, it[1], it[2], 0, 0)
			l.LayoutOrder = i
		end
	end
	local names = {}
	for _, g in v.singers or {} do
		table.insert(names, string.format("%s %s", if g.s == 2 then "2P" else "1P", g.n))
	end
	L.tSingers.Text = if #names > 0 then "🎤 " .. table.concat(names, "   ") else "🎤 마이크를 잡고 함께 불러요"
	-- fade the card as the first line comes in
	local first = c.lines[1]
	local fadeAt = if first then first.show else c.intro
	local a = math.clamp((st - (fadeAt - 0.5)) / 0.5, 0, 1)
	L.titleCard.BackgroundTransparency = 0.25 + 0.75 * a
	setLayer("title", a < 1)
	for _, d in L.titleCard:GetDescendants() do
		if d:IsA("TextLabel") then
			d.TextTransparency = a
			if d.Parent == L.tChips then
				d.BackgroundTransparency = 0.15 + 0.85 * a
			end
		elseif d:IsA("UIStroke") then
			d.Transparency = 0.1 + 0.9 * a
		end
	end
end

local function updateSing(v: any, st: number, t: number)
	local s, c = v.song, v.chart
	if not (s and c) then
		return
	end
	L.topSong.Text = string.format("♪ %d  %s · %s", s.no, s.title, s.artist)
	local q1 = v.queue and v.queue[1]
	local ns = q1 and S.Songs.byId[q1.s]
	L.topNext.Text = if ns then string.format("다음 ▶ %d %s", ns.no, ns.title) else ""
	L.topCredits.Text = if v.unlimited then "남은 곡 ∞" else string.format("남은 곡 %d", v.credits)
	L.bVoice.Visible = v.voiceRig == true
	L.bVoice.Text = "🎤 LIVE VOICE"
	L.bVoice.TextColor3 = Color3.fromRGB(255, 120, 180)
	local e = v.echo or 0
	L.bEcho.Text = "ECHO " .. string.rep("■", e) .. string.rep("□", S.Config.EchoMax - e)
	L.bEcho.TextColor3 = Color3.fromRGB(150, 220, 255)
	L.bKey.Text = if v.key == 0 then "KEY 원키" else string.format("KEY %s%d", if v.key > 0 then "♯" else "♭", math.abs(v.key))
	L.bKey.TextColor3 = Color3.fromRGB(255, 220, 120)
	L.bTempo.Text = if v.tempo == 0 then "TEMPO 0" else string.format("TEMPO %+d", v.tempo)
	L.bTempo.TextColor3 = Color3.fromRGB(180, 255, 180)
	L.vibeFill.Size = UDim2.fromScale(math.clamp((v.vibe or 0) / 100, 0, 1), 1)
	lyr.update(st)
	-- 간주중 / intro / outro captions
	local sect = S.Chart.sectAt(c, st)
	local last = c.lines[#c.lines]
	local inter = sect and sect.kind == "inter"
	L.inter.Visible = inter == true
	if inter and sect then
		L.interFill.Size = UDim2.fromScale(math.clamp((st - sect.t) / math.max(0.1, sect.e - sect.t), 0, 1), 1)
		L.interText.Rotation = math.sin(t * 3) * 2
	end
	if last and st > last.hide then
		L.caption.Visible = true
		L.caption.Text = "♬ 수고하셨습니다 ♬"
	else
		L.caption.Visible = false
	end
	L.progress.Size = UDim2.fromScale(math.clamp(st / math.max(1, c.duration), 0, 1), 1)
	L.pause.Visible = v.paused == true
	-- judgement fade
	local a = math.clamp((t - judgeT - 0.5) / 0.4, 0, 1)
	L.judge.TextTransparency = a
	L.combo.TextTransparency = a
	for _, d in { L.judge, L.combo } do
		local stroke = d:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 0.1 + 0.9 * a
		end
	end
end

local function startConfetti()
	for _, c in confetti do
		c.x = math.random(0, W)
		c.y = -math.random(0, 400)
		c.vx = math.random(-60, 60)
		c.vy = math.random(140, 320)
		c.r = math.random(0, 360)
		c.vr = math.random(-240, 240)
		c.f.Visible = true
	end
end

local function stepConfetti(dt: number)
	for _, c in confetti do
		if c.f.Visible then
			c.x += c.vx * dt
			c.y += c.vy * dt
			c.r += c.vr * dt
			if c.y > H + 40 then
				c.y = -30
				c.x = math.random(0, W)
			end
			c.f.Position = UDim2.fromOffset(c.x, c.y)
			c.f.Rotation = c.r
		end
	end
end

local function stopConfetti()
	for _, c in confetti do
		c.f.Visible = false
	end
end

local function updateScore(v: any, t: number, dt: number)
	local res = v.result
	local elapsed = t - scoreT0
	if v.state == "settle" then
		L.scoreHead.Text = "채점 중"
		L.scoreNum.Text = "두구두구" .. string.rep(".", 1 + math.floor(t * 3) % 3)
		L.scoreNum.TextSize = 120
		L.scoreGrade.Text = "🥁 🥁 🥁"
		L.scoreComment.Text = ""
		L.scoreExtra.Text = ""
		L.scoreBonus.Visible = false
		L.scoreGold.BackgroundTransparency = 1
		for _, c in L.cards do
			c.f.Visible = false
		end
		return
	end
	if type(res) ~= "table" then
		return
	end
	local rows = {}
	for _, r in res.sc or {} do
		if type(r) == "table" and type(r.s) == "number" then
			table.insert(rows, r)
		end
	end
	local scored = {}
	for _, r in rows do
		if r.s >= 0 then
			table.insert(scored, r)
		end
	end
	local song = S.Songs.byId[res.s or ""]
	L.scoreHead.Text = if song then string.format("♪ %s", song.title) else ""
	if res.on == false then
		L.scoreNum.TextSize = 110
		L.scoreNum.Text = "수고하셨습니다 👏"
		L.scoreGrade.Text = "점수 표시가 꺼져 있어요"
		L.scoreComment.Text = ""
		L.scoreExtra.Text = ""
		return
	end
	if #scored == 0 then
		L.scoreNum.TextSize = 96
		L.scoreNum.Text = "채점 없음"
		L.scoreGrade.Text = "마이크로 부르거나 ♪ 박자 버튼을 눌러야 점수가 나와요"
		L.scoreComment.Text = "그래도 즐거웠다면 100점! 😄"
		L.scoreExtra.Text = ""
		for _, c in L.cards do
			c.f.Visible = false
		end
		return
	end
	local count = math.clamp(elapsed / 1.6, 0, 1)
	local eased = 1 - (1 - count) ^ 3
	if #scored == 1 then
		local r = scored[1]
		for _, c in L.cards do
			c.f.Visible = false
		end
		L.scoreNum.TextSize = 240
		L.scoreNum.Text = tostring(math.floor(r.s * eased + 0.5))
		local g = S.Score.grade(r.s)
		L.scoreGrade.Text = if count >= 1 then string.format("%s  ·  %s", g.id, g.label) else ""
		L.scoreGrade.TextColor3 = Kit.rgb(g.color)
		L.scoreComment.Text = if count >= 1 then S.Score.comment(r.s, res.serial or 0) else ""
		local extra = {}
		if r.m == "voice" then
			table.insert(extra, "🎤 목소리 채점")
		else
			table.insert(extra, string.format("PERFECT %d · GOOD %d · MISS %d · 최대 콤보 %d", r.p or 0, r.gd or 0, r.ms or 0, r.c or 0))
		end
		if (r.v or 0) > 0 then
			table.insert(extra, string.format("분위기 보너스 +%d", r.v))
		end
		L.scoreExtra.Text = if count >= 1 then table.concat(extra, "  ·  ") .. "  ·  " .. r.n .. "님" else ""
	else
		-- duet / several singers: one card each
		L.scoreNum.Text = ""
		L.scoreGrade.Text = ""
		L.scoreComment.Text = if count >= 1 then "환상의 호흡! 👏" else ""
		L.scoreExtra.Text = ""
		local n = math.min(3, #scored)
		local cw = 360
		local gap = 40
		local x0 = (W - (n * cw + (n - 1) * gap)) / 2
		for i, c in L.cards do
			local r = scored[i]
			c.f.Visible = r ~= nil and i <= n
			if r and i <= n then
				c.f.Position = UDim2.fromOffset(x0 + (i - 1) * (cw + gap), 150)
				c.name.Text = string.format("%s %s", if r.sl == 2 then "2P" else "1P", r.n)
				c.num.Text = tostring(math.floor(r.s * eased + 0.5))
				c.sub.Text = if count >= 1 then string.format("%s · %s", S.Score.grade(r.s).id, if r.m == "voice" then "🎤 목소리" else string.format("콤보 %d", r.c or 0)) else ""
			end
		end
		L.scoreComment.Position = UDim2.fromOffset(0, 430)
	end
	if #scored == 1 then
		L.scoreComment.Position = UDim2.fromOffset(0, 446)
	end
	-- personal lines (best / rank) for me
	if mine and mineSerial == res.serial and count >= 1 then
		local lines = {}
		if mine.isBest then
			table.insert(lines, "🏅 내 최고 기록 갱신!")
		end
		if (mine.rank or 0) > 0 then
			table.insert(lines, string.format("👑 오늘의 노래왕 %d위", mine.rank))
		end
		if #lines > 0 then
			L.scoreExtra.Text = table.concat(lines, "  ·  ")
		end
	end
	local top = 0
	for _, r in scored do
		top = math.max(top, r.s)
	end
	L.scoreBonus.Visible = count >= 1 and res.b == true
	if top >= 100 and count >= 1 then
		L.scoreGold.BackgroundTransparency = 0.75 + 0.15 * math.sin(t * 6)
		stepConfetti(dt)
	else
		L.scoreGold.BackgroundTransparency = 1
	end
end

-------------------------------------------------------------------------------------------------
-- events
-------------------------------------------------------------------------------------------------
local FX_EMOJI = { tamb = "🪇", clap = "👏", cheer = "🙌", fire = "🎆", petal = "🌸", dance = "💃" }
local emojiI = 0
local function spawnEmoji(kind: string, name: string?)
	emojiI = emojiI % #emojis + 1
	local e = emojis[emojiI]
	e.t0 = os.clock()
	e.x = math.random(80, W - 200)
	e.l.Text = FX_EMOJI[kind] or "✨"
	e.n.Text = name or ""
	e.l.Visible = true
end

local function stepEmojis()
	local t = os.clock()
	for _, e in emojis do
		if e.l.Visible then
			local u = (t - e.t0) / 1.8
			if u >= 1 then
				e.l.Visible = false
			else
				e.l.Position = UDim2.fromOffset(e.x + math.sin(u * 7) * 20, H - 140 - u * 420)
				e.l.TextTransparency = math.max(0, u * 1.4 - 0.4)
				e.n.TextTransparency = e.l.TextTransparency
			end
		end
	end
end

function TV.judge(j: string, combo: number, name: string?)
	if j == "P" then
		L.judge.Text = "PERFECT"
		L.judge.TextColor3 = Color3.fromRGB(255, 206, 70)
	elseif j == "G" then
		L.judge.Text = "GOOD"
		L.judge.TextColor3 = Color3.fromRGB(120, 220, 255)
	else
		L.judge.Text = "MISS"
		L.judge.TextColor3 = Color3.fromRGB(160, 165, 185)
	end
	L.combo.Text = (if combo >= 2 then string.format("%d COMBO", combo) else "") .. (if name then "  " .. name else "")
	judgeT = os.clock()
end

-------------------------------------------------------------------------------------------------
-- lite screens of the other booths
-------------------------------------------------------------------------------------------------
local function liteFor(v: any): any?
	local scr = v.screen
	if not (scr and scr.Parent) then
		return nil
	end
	local l = lite[v.no]
	if l and l.scr == scr then
		return l
	end
	if l then
		l.gui:Destroy()
	end
	local sg = surface({
		Name = "GwKP_TVLite_" .. v.name,
		Adornee = scr,
		Face = faceOf(scr),
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = Vector2.new(640, 365),
		LightInfluence = 0,
		Brightness = 1.4,
		ZOffset = 4,
		MaxDistance = 60,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	fitPps(sg, scr, 640)
	local f = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(10, 12, 30), BorderSizePixel = 0 }, sg)
	new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(30, 20, 70), Color3.fromRGB(6, 10, 26)), Rotation = 90 }, f)
	local t1 = new("TextLabel", { BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 200, 70), TextSize = 40, Size = UDim2.new(1, 0, 0, 60), Position = UDim2.fromOffset(0, 50), Text = "" }, f)
	local t2 = new("TextLabel", { BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextColor3 = Color3.new(1, 1, 1), TextSize = 44, Size = UDim2.new(1, -40, 0, 70), Position = UDim2.fromOffset(20, 140), Text = "", TextWrapped = true }, f)
	local t3 = new("TextLabel", { BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(190, 200, 230), TextSize = 26, Size = UDim2.new(1, -40, 0, 40), Position = UDim2.fromOffset(20, 240), Text = "", TextWrapped = true }, f)
	sg.Parent = player:WaitForChild("PlayerGui")
	l = { gui = sg, scr = scr, t1 = t1, t2 = t2, t3 = t3 }
	lite[v.no] = l
	return l
end

local function paintLite(v: any)
	local l = liteFor(v)
	if not l then
		return
	end
	l.gui.Enabled = room ~= v
	l.t1.Text = "ROOM " .. v.name
	if v.renter == 0 then
		l.t2.Text = "동전을 넣어 주세요 🪙"
		l.t3.Text = "1곡 500원 · 4곡 1,000원"
	elseif v.state == "play" and v.song then
		l.t2.Text = "♪ " .. v.song.title
		l.t3.Text = string.format("%s · %s님 이용 중", v.song.artist, v.renterName)
	else
		l.t2.Text = "이용 중 🎤"
		l.t3.Text = v.renterName .. "님의 방"
	end
end

-------------------------------------------------------------------------------------------------
-- room binding + frame update
-------------------------------------------------------------------------------------------------
local function setRoom(v: any?)
	room = v
	if v and v.screen and v.screen.Parent then
		if gui.Adornee ~= v.screen then
			-- re-parent around the Adornee change so every renderer places it on the new part
			local pg = gui.Parent
			gui.Parent = nil
			gui.Adornee = v.screen
			gui.Face = faceOf(v.screen)
			fitPps(gui, v.screen, W)
			gui.Parent = pg or player:FindFirstChildOfClass("PlayerGui")
		end
		gui.Enabled = true
	else
		gui.Enabled = false
	end
	lastState = ""
	for _, rv in Rooms.views do
		paintLite(rv)
	end
end

function TV.update(dt: number)
	acc += dt
	stepEmojis()
	if acc < 1 / 30 then
		return
	end
	local fdt = acc
	acc = 0
	local v = room
	if not v then
		return
	end
	if v.screen and gui.Adornee ~= v.screen then
		setRoom(v)
	end
	if not gui.Enabled then
		return
	end
	local t = os.clock()
	local now = S.now()
	local stName = if v.renter == 0 then "free" else v.state
	if stName ~= lastState then
		if stName == "score" then
			scoreT0 = t
			startConfetti()
			task.delay(0.05, function()
				local res = v.result
				local top = 0
				for _, r in (type(res) == "table" and res.sc) or {} do
					if type(r) == "table" and type(r.s) == "number" then
						top = math.max(top, r.s)
					end
				end
				if top >= 90 then
					K.Band.fx("fanfare")
				end
			end)
		elseif stName == "settle" then
			stopConfetti()
			K.Band.fx("drum")
		else
			stopConfetti()
		end
		if stName == "play" then
			lyr.setChart(v.chart)
			chipsFor = ""
		end
		lastState = stName
	end
	local st = Rooms.songTime(v, now) - (K.Band.localDelay or 0)
	-- background scene
	local preset = if v.song then v.song.preset else nil
	bg.setScene(if stName == "play" or stName == "settle" or stName == "score" then Background.sceneFor(preset) else "night")
	local phase, energy = 0, 0.3
	if v.chart and stName == "play" then
		phase = (st / v.chart.beat) % 1
		local sect = S.Chart.sectAt(v.chart, st)
		energy = if sect and (sect.kind == "chorus" or sect.kind == "inter") then 1 else 0.45
	end
	bg.update(t, phase, energy)
	if stName == "free" then
		showLayer("idle")
		updateIdle(v, t)
	elseif stName == "open" then
		showLayer("ready")
		updateReady(v, now)
	elseif stName == "play" then
		if lyr.chart ~= v.chart then
			lyr.setChart(v.chart)
		end
		local first = v.chart and v.chart.lines[1]
		local titleOn = first and st < first.show
		showLayer(if titleOn then "title" else "sing")
		setLayer("sing", true)
		if titleOn or (first and st < first.show + 0.1) then
			setLayer("title", true)
			updateTitle(v, st)
		else
			setLayer("title", false)
		end
		updateSing(v, st, t)
	else
		showLayer("score")
		updateScore(v, t, fdt)
	end
end

-- one-line summary of what the TV shows (studio tests)
function TV.debug(): string
	local vis = {}
	for _, n in { "idle", "ready", "title", "sing", "score" } do
		if L[n] and L[n].Visible then
			table.insert(vis, n)
		end
	end
	local lines = {}
	if lyr then
		for s = 1, 2 do
			local sl = lyr.slots[s]
			if sl.frame.Visible then
				table.insert(lines, string.format("%d:%s(%.0f/%.0f)", s, sl.base.Text, sl.clip.Size.X.Offset, sl.w))
			end
		end
	end
	return string.format("enabled=%s adornee=%s layers=%s scene=%s big=%s ready=%s title=%s score=%s/%s lyrics=%s inter=%s", tostring(gui.Enabled), tostring(gui.Adornee and gui.Adornee:GetFullName()), table.concat(vis, ","), tostring(bg and bg.scene), L.idleBig.Text, L.readyBig.Text, L.tTitle.Text, L.scoreNum.Text, L.scoreGrade.Text, table.concat(lines, " | "), tostring(L.inter.Visible))
end

function TV.setLyricSize(name: string)
	if lyr then
		lyr.setSize(name)
	end
end

function TV.init(k: any)
	K = k
	S, Kit, Rooms = k.S, k.Kit, k.Rooms
	Lyrics = k.Lyrics
	Background = k.Background
	gui = surface({
		Name = S.NAMES.TV,
		Face = Enum.NormalId.Back,
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = Vector2.new(W, H),
		LightInfluence = 0,
		Brightness = 1.6,
		ZOffset = 5,
		MaxDistance = 90,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ClipsDescendants = true,
		Enabled = false,
	})
	root = new("Frame", { Name = "Root", Size = UDim2.fromOffset(W, H), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ClipsDescendants = true }, gui)
	bg = Background.new(root, W, H)
	bg.setScene("night")
	buildIdle()
	buildReady()
	buildTitle()
	buildSing()
	buildScore()
	buildEmojis()
	gui.Parent = player:WaitForChild("PlayerGui")
	Rooms.entered(function(v)
		setRoom(v)
	end)
	Rooms.changed(function(v, attr)
		if attr == "Model" and v == room then
			setRoom(v)
		end
		if attr == "Model" or attr == "State" or attr == "Renter" or attr == "Song" or attr == "RenterName" then
			paintLite(v)
		end
	end)
	K.Net.onLive("fx", function(p)
		if room and p.room == room.no then
			spawnEmoji(p.fx, p.n)
		end
	end)
	K.Net.onLive("judge", function(p)
		if room and p.room == room.no and p.u ~= player.UserId then
			local other = Players:GetPlayerByUserId(p.u)
			TV.judge(p.j, p.c or 0, other and other.DisplayName or nil)
		end
	end)
	K.Net.on("result", function(p)
		mine = p.mine
		mineSerial = p.serial
	end)
	for _, v in Rooms.views do
		paintLite(v)
	end
	-- the lite screens follow streaming
	task.spawn(function()
		while true do
			task.wait(4)
			for _, v in Rooms.views do
				paintLite(v)
			end
		end
	end)
end

return TV
