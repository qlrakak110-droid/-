-- GwangalliFeatures/TaxiCall: calling 광안콜택시 like a real phone call (owner: taxi_call;
-- docs/features_contract.md §4). Built only with the GwangalliUI kit, on the shared GwangalliFeatures
-- ScreenGui, drawn as a phone in the "sheetRight" slot (the same place as the phone itself).
--
-- Flows (F.open / LocalPlayer.GwangalliFeaturesOpen:Fire(flow, args)):
--   "taxiCall"   {via = "contact"|"dial"|"redial"|"favorite"}  ring ring -> connect after 1-2 rings ->
--                the dispatcher talks (typed subtitles) -> destination choices (home / work / recent /
--                night club / popular, 🔎 검색, 🗺️ 지도에서 선택, 🎲 근처 아무 데나) -> quote -> book ->
--                driver + plate + ETA -> hang up (the TaxiRide card takes over)
--   "taxiDialer" {number?}  keypad with the 광안콜택시 speed dial and 최근 기록 (redial)
--   "taxiDest"   {}         destination picker for a taxi that is already here (seated, no destination)
-- Every call ends in the call log: LocalPlayer.GwangalliTaxiCallLog (BindableEvent) fires
-- {number, name, status = "booked"|"ended"|"missed"|"invalid", seconds, destination?, at} so the phone's
-- 전화 > 최근 tab can list it; M.recents() returns this session's log (newest first).
--
-- Server: ReplicatedStorage.GwangalliRemotes.TaxiCall (RemoteFunction) ops hello / quote / book /
-- setDest (the server decides every fare; this screen only shows what it answers).

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local M = {}
M.flows = { "taxiCall", "taxiDialer", "taxiDest" }

local F: any
local K: any
local Layout: any
local player: Player

local NUMBER = "1588-5252"
local COMPANY = "광안콜택시"
local DISPATCHER = "상담원 이수진"
local GOLD1 = Color3.fromRGB(255, 206, 84)
local GOLD2 = Color3.fromRGB(240, 140, 30)

-- UI
local dim: Frame
local device: Frame
local deviceScale: UIScale
local screen: Frame
local statusTime: TextLabel
local pages: { [string]: Frame } = {}
local current = "call"
local compact = false
local L = { statusH = 24, w = 300, h = 600 }

-- call page widgets
local avatar: Frame
local avatarGlyph: TextLabel
local rings: { Frame } = {}
local nameLabel: TextLabel
local numberLabel: TextLabel
local stateLabel: TextLabel
local timerLabel: TextLabel
local speakBars: Frame
local subtitle: Frame
local meLine: TextLabel
local dispLabel: TextLabel
local dispWho: TextLabel
local choiceScroll: ScrollingFrame
local hangBtn: TextButton
local controls: Frame
local header: Frame

-- dest page / map page / dial page widgets
local destSearch: any
local destList: ScrollingFrame
local destTitle: TextLabel
local mapCanvas: Frame
local mapWorld: Frame
local mapCard: Frame
local mapCardTitle: TextLabel
local mapCardSub: TextLabel
local mapGo: TextButton
local mapMe: Frame
local dialDisplay: TextLabel
local recentBox: Frame

-- state
local isOpen = false
local serial = 0 -- bumps on every hang-up / close: every waiting step checks it
local callStart: number? = nil
local inCall = false
local picked: any = nil
local destPicked: any = nil
local mode = "call" -- call | dest (taxiDest flow: pick for the waiting taxi)
local calls: { any } = {}
local logEvent: BindableEvent? = nil
local sounds: { [string]: Sound } = {}
local speakerOn = true
local dialNumber = ""
local hello: any = nil
local speaker = "🎧 " .. DISPATCHER

-------------------------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------------------------
local function remote(): RemoteFunction?
	local G = F.G
	local name = (G and G.Remote and G.Remote.TaxiCall) or "TaxiCall"
	local r = F.remote(name, 8)
	if r and r:IsA("RemoteFunction") then
		return r
	end
	return nil
end

-- Yields. Always returns a table.
local function call(op: string, payload: any?): { [string]: any }
	local r = remote()
	if not r then
		return { ok = false, code = "offline", message = "택시 회사와 연결할 수 없어요" }
	end
	local ok, res = pcall(r.InvokeServer, r, op, payload)
	if ok and type(res) == "table" then
		return res
	end
	return { ok = false, code = "offline", message = "연결이 불안정해요. 다시 걸어 주세요" }
end

local function rootPos(): Vector3?
	local c = player.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r.Position else nil
end

local function gameClock(): number
	local ok, v = pcall(function()
		return game:GetService("Lighting").ClockTime
	end)
	return if ok and type(v) == "number" then v else 12
end

local function fmtDur(s: number): string
	s = math.max(0, math.floor(s))
	return string.format("%02d:%02d", s // 60, s % 60)
end

local function ro(word: string): string
	if K.ro then
		return K.ro(word)
	end
	return word .. "(으)로"
end

local function won(n: any): string
	return K.won(n)
end

local function dist(studs: number): string
	return K.meters(studs)
end

local function sound(kind: string, speed: number?, volume: number?)
	if not K.settings.sound then
		return
	end
	local ids = { ring = "rbxasset://sounds/electronicpingshort.wav", click = "rbxasset://sounds/clickfast.wav" }
	local key = kind .. tostring(speed)
	local s = sounds[key]
	if not (s and s.Parent) then
		local snd = Instance.new("Sound")
		snd.Name = "GwangalliTaxiCall_" .. kind
		snd.SoundId = ids[kind] or ids.click
		snd.PlaybackSpeed = speed or 1
		snd.Volume = volume or 0.3
		snd.Parent = SoundService
		sounds[key] = snd
		s = snd
	end
	local snd = s :: Sound
	snd.Volume = (volume or 0.3) * (if speakerOn then 1 else 0.45)
	pcall(snd.Play, snd)
end

local function iconFor(name: string): string
	local rules = {
		{ "CLUB", "🎉" }, { "클럽", "🎉" }, { "출구", "🚇" }, { "역", "🚇" }, { "스타벅스", "☕" }, { "카페", "☕" },
		{ "호텔", "🏨" }, { "해수욕장", "🏖️" }, { "해변", "🏖️" }, { "비치", "🏖️" }, { "공원", "🌳" }, { "마켓", "🛍️" },
		{ "시장", "🛍️" }, { "회", "🐟" }, { "볼링", "🎳" }, { "노래", "🎤" }, { "PC", "🖥️" }, { "은행", "🏦" }, { "병원", "🏥" },
		{ "GS25", "🏪" }, { "CU", "🏪" }, { "편의점", "🏪" }, { "헬스", "💪" }, { "자이", "🏠" }, { "아파트", "🏠" }, { "광장", "📍" },
	}
	for _, r in rules do
		if string.find(name, r[1], 1, true) then
			return r[2]
		end
	end
	return "📍"
end

-------------------------------------------------------------------------------------------------
-- Destination catalogue (quick-travel list with positions + GwangalliNav named places)
-------------------------------------------------------------------------------------------------
type Place = { name: string, pos: Vector3?, icon: string }
local navModule: any = nil
local navTried = false
local function nav(): any
	if navTried then
		return navModule
	end
	navTried = true
	local m = ReplicatedStorage:FindFirstChild("GwangalliNav")
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			navModule = res
		end
	end
	return navModule
end

local function catalogue(): { Place }
	local out: { Place } = {}
	local seen: { [string]: boolean } = {}
	local travel = ReplicatedStorage:FindFirstChild("GwangalliTravel")
	local json = travel and travel:GetAttribute("Destinations")
	if type(json) == "string" then
		local ok, list = pcall(HttpService.JSONDecode, HttpService, json)
		if ok and type(list) == "table" then
			for _, e in list do
				local n = type(e) == "table" and (e.id or e.name)
				if type(n) == "string" and not seen[n] then
					seen[n] = true
					local pos = if type(e.x) == "number" and type(e.z) == "number" then Vector3.new(e.x, 6, e.z) else nil
					table.insert(out, { name = n, pos = pos, icon = iconFor(n) })
				end
			end
		end
	end
	for _, inst in CollectionService:GetTagged("Destination") do
		if inst:IsA("BasePart") then
			local n = inst:GetAttribute("DisplayName")
			n = if type(n) == "string" and n ~= "" then n else inst.Name
			if not seen[n] then
				seen[n] = true
				table.insert(out, { name = n, pos = inst.Position, icon = iconFor(n) })
			end
		end
	end
	local Nav = nav()
	if Nav and type(Nav.places) == "table" then
		for _, e in Nav.places do
			if type(e) == "table" and type(e.name) == "string" and seen[e.name] then
				for _, p in out do
					if p.name == e.name and not p.pos then
						p.pos = Vector3.new(e.x, e.y, e.z)
					end
				end
			end
		end
	end
	return out
end

local function placeByName(name: string): Place?
	for _, p in catalogue() do
		if p.name == name then
			return p
		end
	end
	return nil
end

-------------------------------------------------------------------------------------------------
-- Call log
-------------------------------------------------------------------------------------------------
local function logCall(status: string, dest: string?, number: string?)
	local secs = if callStart then os.clock() - callStart else 0
	local entry = { number = number or NUMBER, name = if (number or NUMBER) == NUMBER then COMPANY else (number or ""), status = status, seconds = math.floor(secs), destination = dest, at = os.time() }
	table.insert(calls, 1, entry)
	while #calls > 20 do
		table.remove(calls)
	end
	if logEvent then
		logEvent:Fire(entry)
	end
	F.emit("taxiCallLogged", entry)
end

function M.recents(): { any }
	return table.clone(calls)
end

-------------------------------------------------------------------------------------------------
-- Device shell
-------------------------------------------------------------------------------------------------
local function applyLayout()
	if not device then
		return
	end
	local ok, rect = pcall(Layout.rect, "sheetRight")
	if not ok or type(rect) ~= "table" then
		rect = { x = 40, y = 20, w = 320, h = 600 }
	end
	local cls = "phoneL"
	pcall(function()
		cls = Layout.deviceClass()
	end)
	local s = 1
	if cls == "tablet" or cls == "pc" then
		s = math.max(0.5, rect.w / 360)
	end
	L.w, L.h = math.floor(rect.w / s), math.floor(rect.h / s)
	deviceScale.Scale = s
	device.Position = UDim2.fromOffset(rect.x, rect.y)
	device.Size = UDim2.fromOffset(L.w, L.h)
	local bezel = if cls == "phoneL" then 4 else 7
	local radius = if cls == "phoneL" then 24 else 36
	K.corner(device, radius + bezel)
	screen.Position = UDim2.fromOffset(bezel, bezel)
	screen.Size = UDim2.new(1, -2 * bezel, 1, -2 * bezel)
	K.corner(screen, radius)
	local sh = L.h - 2 * bezel
	compact = sh < 420
	L.statusH = if compact then 22 else 30
	M._relayout()
end

local function statusBar(parent: Frame)
	local bar = K.frame(parent, { Name = "StatusBar", Size = UDim2.new(1, 0, 0, 24), ZIndex = 30 })
	statusTime = K.text(bar, { Name = "Time", Position = UDim2.fromOffset(18, 0), Size = UDim2.new(0, 70, 1, 0), Text = "9:41", Font = K.Font.bold, TextSize = 12, ZIndex = 30 })
	K.text(bar, { Name = "Signal", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 0), Size = UDim2.new(0, 90, 1, 0), Text = "LTE ▮▮▮  🔋", TextSize = 11, Font = K.Font.bold, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 30 })
	local punch = K.frame(bar, { Name = "Punch", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.fromOffset(10, 10), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 31 })
	K.corner(punch, UDim.new(0.5, 0))
	return bar
end

local function page(name: string): Frame
	local p = K.frame(screen, { Name = "Page_" .. name, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0, BackgroundColor3 = K.Color.bg, Visible = false, ZIndex = 2 })
	K.corner(p, 24)
	pages[name] = p
	return p
end

local function show(name: string, push: boolean?)
	local old = pages[current]
	local new = pages[name]
	if not new or name == current then
		if new then
			new.Visible = true
		end
		current = name
		return
	end
	if push and K.pushPage then
		K.pushPage(new, old)
	elseif push == false and K.popPage then
		K.popPage(old, new)
	else
		if old then
			old.Visible = false
		end
		new.Visible = true
		new.Position = UDim2.fromScale(0, 0)
	end
	current = name
end

local function backButton(parent: Frame, onClick: () -> ()): TextButton
	local b = K.Button(parent, { name = "Back", style = "ghost", text = "‹", size = UDim2.fromOffset(44, 44), textSize = 26 })
	b.Activated:Connect(function()
		if not b:GetAttribute("Disabled") then
			onClick()
		end
	end)
	return b
end

-------------------------------------------------------------------------------------------------
-- Call page
-------------------------------------------------------------------------------------------------
local function setAvatar(glyph: string, c1: Color3, c2: Color3)
	avatarGlyph.Text = glyph
	local g = avatar:FindFirstChildOfClass("UIGradient")
	if g then
		g.Color = ColorSequence.new(c1, c2)
	end
end

local ringSerial = 0
local function pulseRings(on: boolean)
	ringSerial += 1
	local mine = ringSerial
	for _, r in rings do
		r.BackgroundTransparency = 1
	end
	if not on or K.reduced() then
		return
	end
	task.spawn(function()
		while ringSerial == mine and isOpen do
			for i, r in rings do
				if ringSerial ~= mine then
					return
				end
				local s0 = avatar.AbsoluteSize.X / math.max(0.01, deviceScale.Scale)
				r.Size = UDim2.fromOffset(s0, s0)
				r.BackgroundTransparency = 0.55
				K.tween(r, 1.2, { Size = UDim2.fromOffset(s0 * 1.9, s0 * 1.9), BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
				task.wait(0.4 + (i - 1) * 0.05)
			end
			task.wait(0.35)
		end
	end)
end

local speakSerial = 0
local function speaking(on: boolean)
	speakSerial += 1
	local mine = speakSerial
	speakBars.Visible = on
	if not on then
		return
	end
	task.spawn(function()
		local bars = speakBars:GetChildren()
		while speakSerial == mine and isOpen do
			for i, b in bars do
				if b:IsA("Frame") then
					local h = 4 + math.abs(math.sin(os.clock() * 9 + i * 1.3)) * 10
					K.tween(b, 0.12, { Size = UDim2.fromOffset(3, h) })
				end
			end
			task.wait(0.12)
		end
	end)
end

local function setState(text: string, color: Color3?)
	stateLabel.Text = text
	stateLabel.TextColor3 = color or K.Color.sub
end

local function clearChoices()
	for _, c in choiceScroll:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

-- Dispatcher line: typed like live subtitles. Yields until typed (or the call ended).
local function say(text: string, mine: number, pace: number?)
	if serial ~= mine then
		return
	end
	dispWho.Text = speaker
	dispLabel.Text = text
	dispLabel.MaxVisibleGraphemes = 0
	speaking(true)
	local n = utf8.len(text) or #text
	local cps = pace or 26
	local t0 = os.clock()
	if K.reduced() then
		dispLabel.MaxVisibleGraphemes = -1
	else
		while serial == mine do
			local shown = math.floor((os.clock() - t0) * cps)
			if shown >= n then
				break
			end
			dispLabel.MaxVisibleGraphemes = shown
			task.wait(0.03)
		end
	end
	dispLabel.MaxVisibleGraphemes = -1
	speaking(false)
	if serial == mine then
		task.wait(0.25)
	end
end

local function me(text: string)
	meLine.Text = text
	meLine.TextTransparency = 1
	K.tween(meLine, 0.25, { TextTransparency = 0 })
end

type Choice = { id: string, label: string, icon: string?, style: string?, data: any? }

-- Shows reply buttons; yields until one is tapped. Returns the choice (nil when the call ended).
local function ask(choices: { Choice }, mine: number): Choice?
	clearChoices()
	picked = nil
	local rows = {}
	for i, c in choices do
		local b = K.Button(choiceScroll, {
			name = "Choice_" .. c.id,
			text = c.label,
			icon = c.icon,
			style = c.style or "glass",
			size = UDim2.new(1, 0, 0, if compact then 40 else 44),
			order = i,
			textSize = K.Type.bodySm,
		})
		b.TextXAlignment = if c.style == "gold" or c.style == "primary" or c.style == "danger" then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left
		if b.TextXAlignment == Enum.TextXAlignment.Left then
			K.pad(b, 14, 10, 0, 0)
		end
		b.Activated:Connect(function()
			if serial == mine and picked == nil then
				picked = c
			end
		end)
		table.insert(rows, b)
	end
	choiceScroll.CanvasPosition = Vector2.zero
	if K.stagger then
		K.stagger(rows, K.Color.bg)
	end
	while serial == mine and picked == nil do
		task.wait(0.05)
	end
	clearChoices()
	if serial ~= mine then
		return nil
	end
	return picked
end

local function buildCallPage()
	local p = page("call")
	K.gradient(p, { Color3.fromRGB(34, 40, 92), Color3.fromRGB(16, 16, 36), Color3.fromRGB(8, 8, 16) }, 90)
	p.BackgroundColor3 = Color3.new(1, 1, 1)
	header = K.frame(p, { Name = "Header", Size = UDim2.new(1, 0, 0, 180), ZIndex = 3 })
	for i = 1, 2 do
		local ring = K.frame(header, { Name = "Ring" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(84, 84), BackgroundTransparency = 1, BackgroundColor3 = GOLD1, ZIndex = 3 })
		K.corner(ring, UDim.new(0.5, 0))
		rings[i] = ring
	end
	avatar = K.avatar(header, 84, "🚕", GOLD1)
	avatar.AnchorPoint = Vector2.new(0.5, 0.5)
	avatar.ZIndex = 4
	avatarGlyph = avatar:FindFirstChild("Glyph") :: TextLabel
	K.stroke(avatar, Color3.new(1, 1, 1), 2, 0.6)
	speakBars = K.frame(header, { Name = "Speaking", AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(34, 16), Visible = false, ZIndex = 5 })
	K.list(speakBars, true, 3, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	for i = 1, 5 do
		local b = K.frame(speakBars, { Name = "Bar" .. i, Size = UDim2.fromOffset(3, 6), BackgroundTransparency = 0, BackgroundColor3 = K.Color.green, LayoutOrder = i, ZIndex = 5 })
		K.corner(b, UDim.new(0.5, 0))
	end
	nameLabel = K.text(header, { Name = "Name", Text = COMPANY, Font = K.Font.bold, TextSize = K.Type.title, ZIndex = 4, TextTruncate = Enum.TextTruncate.AtEnd })
	numberLabel = K.text(header, { Name = "Number", Text = NUMBER, TextColor3 = K.Color.faint, TextSize = K.Type.caption, ZIndex = 4 })
	K.mono(numberLabel, Enum.FontWeight.Medium)
	stateLabel = K.text(header, { Name = "State", Text = "", Font = K.Font.bold, TextSize = K.Type.bodySm, TextColor3 = K.Color.sub, ZIndex = 4, TextTruncate = Enum.TextTruncate.AtEnd })
	timerLabel = K.text(header, { Name = "Timer", Text = "", TextSize = K.Type.bodySm, ZIndex = 4 })
	K.mono(timerLabel)

	subtitle = K.frame(p, { Name = "Subtitle", BackgroundTransparency = 0.35, BackgroundColor3 = Color3.fromRGB(10, 12, 26), ZIndex = 3 })
	K.corner(subtitle, K.Radius.md)
	K.stroke(subtitle, nil, 1, 0.9)
	meLine = K.text(subtitle, { Name = "Me", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8), Size = UDim2.new(1, -24, 0, 16), Text = "", TextColor3 = K.Color.cyan, TextSize = K.Type.caption, TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4 })
	dispWho = K.text(subtitle, { Name = "Who", Position = UDim2.fromOffset(12, 26), Size = UDim2.new(1, -24, 0, 14), Text = "", TextColor3 = K.Color.gold, Font = K.Font.bold, TextSize = K.Type.micro, ZIndex = 4 })
	dispLabel = K.text(subtitle, { Name = "Line", Position = UDim2.fromOffset(12, 42), Size = UDim2.new(1, -24, 1, -48), Text = "", TextSize = K.Type.bodySm, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 4 })
	pcall(function()
		dispLabel.LineHeight = 1.15
	end)

	choiceScroll = K.make("ScrollingFrame", {
		Name = "Choices",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageTransparency = 0.6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 3,
	}, p)
	K.list(choiceScroll, false, 6)
	K.pad(choiceScroll, 2, 6, 2, 2)

	controls = K.frame(p, { Name = "Controls", AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(200, 48), ZIndex = 3 })
	K.list(controls, true, 26, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	for i, def in { { "Speaker", "🔊" }, { "Mute", "🔇" } } do
		local b = K.Button(controls, { name = def[1], style = "glass", icon = def[2], size = UDim2.fromOffset(48, 48), order = i, textSize = 18, zIndex = 4 })
		K.corner(b, UDim.new(0.5, 0))
		local on = def[1] == "Speaker"
		local function paint()
			b.BackgroundColor3 = if on then K.Color.text else K.Color.glass
			b.BackgroundTransparency = if on then 0.1 else K.GLASS_T
		end
		paint()
		b.Activated:Connect(function()
			on = not on
			if def[1] == "Speaker" then
				speakerOn = on
			end
			paint()
		end)
	end
	hangBtn = K.Button(p, { name = "HangUp", style = "destructive", icon = "📞", size = UDim2.fromOffset(60, 60), textSize = 24, sound = "close", zIndex = 5 })
	K.corner(hangBtn, UDim.new(0.5, 0))
	hangBtn.Rotation = 135
	hangBtn.Activated:Connect(function()
		M.hangUp("ended")
	end)
end

function M._relayout()
	if not header then
		return
	end
	local sH = L.statusH
	local w = L.w - 8
	local hScreen = L.h - 8
	if compact then
		-- one row: avatar | name + state | timer, hang-up top right
		header.Position = UDim2.fromOffset(0, sH)
		header.Size = UDim2.new(1, 0, 0, 58)
		avatar.Size = UDim2.fromOffset(44, 44)
		avatar.Position = UDim2.fromOffset(12 + 22, 29)
		for _, r in rings do
			r.Position = avatar.Position
		end
		speakBars.Position = UDim2.fromOffset(34, 48)
		nameLabel.Position = UDim2.fromOffset(64, 6)
		nameLabel.Size = UDim2.new(1, -64 - 60, 0, 22)
		nameLabel.TextSize = K.Type.title2
		numberLabel.Visible = false
		stateLabel.Position = UDim2.fromOffset(64, 29)
		stateLabel.Size = UDim2.new(1, -64 - 110, 0, 18)
		timerLabel.AnchorPoint = Vector2.new(1, 0)
		timerLabel.Position = UDim2.new(1, -58, 0, 29)
		timerLabel.Size = UDim2.fromOffset(48, 18)
		timerLabel.TextXAlignment = Enum.TextXAlignment.Right
		hangBtn.Size = UDim2.fromOffset(44, 44)
		hangBtn.AnchorPoint = Vector2.new(1, 0)
		hangBtn.Position = UDim2.new(1, -8, 0, sH + 7)
		controls.Visible = false
		local top = sH + 60
		local subH = math.clamp(math.floor((hScreen - top) * 0.36), 70, 96)
		subtitle.Position = UDim2.fromOffset(10, top)
		subtitle.Size = UDim2.new(1, -20, 0, subH)
		choiceScroll.Position = UDim2.fromOffset(10, top + subH + 6)
		choiceScroll.Size = UDim2.new(1, -20, 1, -(top + subH + 6 + 8))
	else
		header.Position = UDim2.fromOffset(0, sH)
		header.Size = UDim2.new(1, 0, 0, 196)
		avatar.Size = UDim2.fromOffset(84, 84)
		avatar.Position = UDim2.new(0.5, 0, 0, 62)
		for _, r in rings do
			r.Position = avatar.Position
		end
		speakBars.Position = UDim2.new(0.5, 0, 0, 108)
		nameLabel.Position = UDim2.new(0, 12, 0, 126)
		nameLabel.Size = UDim2.new(1, -24, 0, 26)
		nameLabel.TextSize = K.Type.title
		nameLabel.TextXAlignment = Enum.TextXAlignment.Center
		numberLabel.Visible = true
		numberLabel.Position = UDim2.new(0, 12, 0, 152)
		numberLabel.Size = UDim2.new(1, -24, 0, 14)
		numberLabel.TextXAlignment = Enum.TextXAlignment.Center
		stateLabel.Position = UDim2.new(0, 12, 0, 168)
		stateLabel.Size = UDim2.new(0.5, -16, 0, 18)
		stateLabel.TextXAlignment = Enum.TextXAlignment.Right
		timerLabel.AnchorPoint = Vector2.zero
		timerLabel.Position = UDim2.new(0.5, 6, 0, 168)
		timerLabel.Size = UDim2.new(0.5, -18, 0, 18)
		timerLabel.TextXAlignment = Enum.TextXAlignment.Left
		hangBtn.Size = UDim2.fromOffset(60, 60)
		hangBtn.AnchorPoint = Vector2.new(0.5, 1)
		hangBtn.Position = UDim2.new(0.5, 0, 1, -18)
		controls.Visible = true
		controls.Position = UDim2.new(0.5, 0, 1, -88)
		local top = sH + 200
		local subH = 104
		subtitle.Position = UDim2.fromOffset(12, top)
		subtitle.Size = UDim2.new(1, -24, 0, subH)
		choiceScroll.Position = UDim2.fromOffset(12, top + subH + 8)
		choiceScroll.Size = UDim2.new(1, -24, 1, -(top + subH + 8 + 146))
	end
	nameLabel.TextXAlignment = if compact then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
	stateLabel.TextXAlignment = if compact then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right
	local _ = w
	-- dest / map / dial pages share a header row
	for _, name in { "dest", "map", "dial" } do
		local pg = pages[name]
		local hdr = pg and pg:FindFirstChild("Head")
		if hdr and hdr:IsA("Frame") then
			hdr.Position = UDim2.fromOffset(0, sH)
		end
		local body = pg and pg:FindFirstChild("Body")
		if body and body:IsA("GuiObject") then
			body.Position = UDim2.fromOffset(0, sH + 46)
			body.Size = UDim2.new(1, 0, 1, -(sH + 46))
		end
	end
	if M._relayoutDial then
		M._relayoutDial()
	end
end

-------------------------------------------------------------------------------------------------
-- Destination search page
-------------------------------------------------------------------------------------------------
local function pageHead(pg: Frame, title: string, onBack: () -> ()): TextLabel
	local head = K.frame(pg, { Name = "Head", Size = UDim2.new(1, 0, 0, 46), ZIndex = 3 })
	local b = backButton(head, onBack)
	b.Position = UDim2.fromOffset(4, 1)
	local t = K.text(head, { Name = "Title", Position = UDim2.fromOffset(52, 0), Size = UDim2.new(1, -60, 1, 0), Text = title, Font = K.Font.bold, TextSize = K.Type.title2, ZIndex = 3 })
	return t
end

local function fillDestList(query: string?)
	for _, c in destList:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local here = rootPos()
	local list = catalogue()
	local q = if query and query ~= "" then string.lower(query) else nil
	local rows = {}
	local items = {}
	for _, pl in list do
		if not q or string.find(string.lower(pl.name), q, 1, true) then
			local d = if here and pl.pos then (Vector3.new(pl.pos.X, 0, pl.pos.Z) - Vector3.new(here.X, 0, here.Z)).Magnitude else nil
			table.insert(items, { pl = pl, d = d })
		end
	end
	table.sort(items, function(a, b)
		if (a.d == nil) ~= (b.d == nil) then
			return a.d ~= nil
		end
		if a.d and b.d and a.d ~= b.d then
			return a.d < b.d
		end
		return a.pl.name < b.pl.name
	end)
	for i, it in items do
		if i > 80 then
			break
		end
		local r = K.ListRow(destList, {
			name = "Dest_" .. i,
			icon = it.pl.icon,
			iconColor = K.Color.gold,
			title = it.pl.name,
			subtitle = if it.d then (dist(it.d) .. " · " .. (if it.d < 180 then "바로 근처" else "택시 약 " .. math.max(1, math.floor(it.d / 45 / 60 + 0.5)) .. "분")) else nil,
			trailing = "›",
			trailingColor = K.Color.faint,
			trailingWidth = 20,
			height = 54,
			order = i,
			onClick = function()
				destPicked = { kind = "name", name = it.pl.name, label = it.pl.name }
			end,
		})
		table.insert(rows, r.row)
	end
	if #items == 0 then
		K.text(destList, { Name = "Empty", Size = UDim2.new(1, 0, 0, 60), Text = if q then "'" .. query .. "' 검색 결과가 없어요" else "목적지 목록을 불러오는 중…", TextColor3 = K.Color.faint, TextXAlignment = Enum.TextXAlignment.Center })
	end
	if K.stagger then
		K.stagger(rows, K.Color.bg)
	end
end

local function buildDestPage()
	local p = page("dest")
	destTitle = pageHead(p, "목적지 검색", function()
		destPicked = { kind = "back" }
	end)
	local body = K.frame(p, { Name = "Body", ZIndex = 2 })
	destSearch = K.SearchBar(body, {
		name = "Search",
		placeholder = "장소 이름 (예: 광안역, 클럽)",
		onChange = function(t)
			fillDestList(t)
		end,
	})
	destSearch.frame.Position = UDim2.fromOffset(12, 0)
	destSearch.frame.Size = UDim2.new(1, -24, 0, 44)
	destList = K.make("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(12, 52),
		Size = UDim2.new(1, -24, 1, -60),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageTransparency = 0.6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, body)
	K.list(destList, false, 6)
end

-- Opens the search page and yields until a place is picked (or back / hang-up). Returns the pick.
local function pickFromList(mine: number, title: string?): any
	destPicked = nil
	destTitle.Text = title or "목적지 검색"
	destSearch.clear()
	fillDestList(nil)
	show("dest", true)
	while serial == mine and destPicked == nil do
		task.wait(0.05)
	end
	destSearch.release()
	show("call", false)
	if serial ~= mine then
		return nil
	end
	return destPicked
end

-------------------------------------------------------------------------------------------------
-- Map picker page (roads from GwangalliNav lanes, pins, tap to choose)
-------------------------------------------------------------------------------------------------
local mapBuilt = false
local mapSegs: { { number } } = {} -- {x1, z1, x2, z2}
local mapBounds = { minX = -4300, maxX = 4100, minZ = -900, maxZ = 1600 }
local mapScale = 0.08 -- px per stud
local mapCenter = Vector3.new(0, 0, 200) -- world point at the canvas centre
local mapLines: { Frame } = {}
local mapPins: { { frame: GuiObject, pos: Vector3 } } = {}
local mapSel: any = nil
local mapSelDot: Frame? = nil

local function buildMapSegments()
	local Nav = nav()
	if not Nav or type(Nav.lanes) ~= "table" then
		return
	end
	local Ln = Nav.lanes
	local Q = 20
	local seen: { [string]: boolean } = {}
	local adj: { [string]: { string } } = {}
	local ptOf: { [string]: { number } } = {}
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	local function key(x: number, z: number): string
		local qx, qz = math.floor(x / Q + 0.5), math.floor(z / Q + 0.5)
		local k = qx .. "," .. qz
		if not ptOf[k] then
			ptOf[k] = { qx * Q, qz * Q }
		end
		return k
	end
	local E = Ln.edges
	for e = 1, #E // 4 do
		local k = (e - 1) * 4
		local a, b, kind = E[k + 1], E[k + 2], E[k + 4]
		if kind == 1 or kind == 2 or kind == 3 or kind == 4 then
			local ax, az = Ln.pos[(a - 1) * 2 + 1], Ln.pos[(a - 1) * 2 + 2]
			local bx, bz = Ln.pos[(b - 1) * 2 + 1], Ln.pos[(b - 1) * 2 + 2]
			if ax and bx then
				minX, maxX = math.min(minX, ax, bx), math.max(maxX, ax, bx)
				minZ, maxZ = math.min(minZ, az, bz), math.max(maxZ, az, bz)
				local ka, kb = key(ax, az), key(bx, bz)
				if ka ~= kb then
					local id = if ka < kb then ka .. "|" .. kb else kb .. "|" .. ka
					if not seen[id] then
						seen[id] = true
						adj[ka] = adj[ka] or {}
						adj[kb] = adj[kb] or {}
						table.insert(adj[ka], kb)
						table.insert(adj[kb], ka)
					end
				end
			end
		end
	end
	if minX == math.huge then
		return
	end
	mapBounds = { minX = minX - 150, maxX = maxX + 150, minZ = minZ - 250, maxZ = maxZ + 150 }
	-- merge straight chains through degree-2 nodes
	local used: { [string]: boolean } = {}
	local function segId(a: string, b: string): string
		return if a < b then a .. "|" .. b else b .. "|" .. a
	end
	for a, list in adj do
		for _, b in list do
			local id = segId(a, b)
			if not used[id] then
				used[id] = true
				local start, prev, cur = a, a, b
				local pa = ptOf[a]
				while true do
					local nb = adj[cur]
					if #nb ~= 2 then
						break
					end
					local nxt = if nb[1] == prev then nb[2] else nb[1]
					local id2 = segId(cur, nxt)
					if used[id2] then
						break
					end
					local p0, p1, p2 = ptOf[start], ptOf[cur], ptOf[nxt]
					local d1 = Vector3.new(p1[1] - p0[1], 0, p1[2] - p0[2])
					local d2 = Vector3.new(p2[1] - p1[1], 0, p2[2] - p1[2])
					if d1.Magnitude < 1 or d2.Magnitude < 1 or d1.Unit:Dot(d2.Unit) < 0.985 then
						break
					end
					used[id2] = true
					prev, cur = cur, nxt
				end
				local pb = ptOf[cur]
				table.insert(mapSegs, { pa[1], pa[2], pb[1], pb[2] })
				if #mapSegs > 900 then
					return
				end
			end
		end
	end
end

local function worldToPx(p: Vector3): Vector2
	return Vector2.new((p.X - mapBounds.minX) * mapScale, (mapBounds.maxZ - p.Z) * mapScale)
end

local function pxToWorld(px: Vector2): Vector3
	return Vector3.new(px.X / mapScale + mapBounds.minX, 6, mapBounds.maxZ - px.Y / mapScale)
end

local function layoutMap()
	if not mapWorld then
		return
	end
	local W = (mapBounds.maxX - mapBounds.minX) * mapScale
	local H = (mapBounds.maxZ - mapBounds.minZ) * mapScale
	mapWorld.Size = UDim2.fromOffset(W, H)
	for i, seg in mapSegs do
		local f = mapLines[i]
		if f then
			local a = worldToPx(Vector3.new(seg[1], 0, seg[2]))
			local b = worldToPx(Vector3.new(seg[3], 0, seg[4]))
			local mid = (a + b) / 2
			local len = (b - a).Magnitude
			f.Position = UDim2.fromOffset(mid.X, mid.Y)
			f.Size = UDim2.fromOffset(len + 2, if mapScale > 0.12 then 3 else 2)
			f.Rotation = math.deg(math.atan2(b.Y - a.Y, b.X - a.X))
		end
	end
	for _, pin in mapPins do
		local px = worldToPx(pin.pos)
		pin.frame.Position = UDim2.fromOffset(px.X, px.Y)
		pin.frame.Visible = mapScale >= 0.05 or pin.frame.Name == "Pin_me"
	end
	if mapSelDot and mapSel then
		local px = worldToPx(mapSel.pos)
		mapSelDot.Position = UDim2.fromOffset(px.X, px.Y)
	end
	-- keep mapCenter in the middle of the canvas
	local c = worldToPx(mapCenter)
	local cs = mapCanvas.AbsoluteSize / math.max(0.01, deviceScale.Scale)
	mapWorld.Position = UDim2.fromOffset(cs.X / 2 - c.X, cs.Y / 2 - c.Y)
end

local function selectMapPoint(pos: Vector3, name: string?)
	local here = rootPos()
	local d = if here then (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(here.X, 0, here.Z)).Magnitude else nil
	mapSel = { pos = pos, name = name }
	mapCardTitle.Text = if name then (iconFor(name) .. " " .. name) else "📍 지도에서 고른 곳"
	mapCardSub.Text = if d then ("여기서 " .. dist(d)) else ""
	K.setButtonEnabled(mapGo, true)
	if not mapSelDot then
		local dot = K.frame(mapWorld, { Name = "Selected", AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(28, 34), ZIndex = 8 })
		K.text(dot, { Size = UDim2.fromScale(1, 1), Text = "📍", TextSize = 26, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 8 })
		mapSelDot = dot
	end
	local px = worldToPx(pos)
	local sel = mapSelDot :: Frame
	sel.Position = UDim2.fromOffset(px.X, px.Y)
	if K.pop then
		K.pop(sel, 0.6)
	end
	K.feedback("tap")
end

local function buildMapPage()
	local p = page("map")
	pageHead(p, "지도에서 선택", function()
		destPicked = { kind = "back" }
	end)
	local body = K.frame(p, { Name = "Body", ZIndex = 2 })
	mapCanvas = K.frame(body, { Name = "Canvas", Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, -82), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(14, 22, 40), ClipsDescendants = true, Active = true, ZIndex = 2 })
	K.corner(mapCanvas, K.Radius.md)
	K.stroke(mapCanvas, nil, 1, 0.88)
	-- sea band hint (the sea is south, toward the bottom)
	local sea = K.frame(mapCanvas, { Name = "SeaHint", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 0.6, BackgroundColor3 = Color3.fromRGB(20, 70, 130), ZIndex = 2 })
	K.text(sea, { Size = UDim2.fromScale(1, 1), Text = "🌊 바다 · 광안대교 쪽", TextColor3 = Color3.fromRGB(150, 200, 255), TextSize = K.Type.micro, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 2 })
	mapWorld = K.frame(mapCanvas, { Name = "World", ZIndex = 3 })
	-- zoom / locate buttons
	local tools = K.frame(mapCanvas, { Name = "Tools", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromOffset(44, 144), ZIndex = 9 })
	K.list(tools, false, 6)
	local function zoom(f: number)
		mapScale = math.clamp(mapScale * f, 0.03, 0.4)
		layoutMap()
	end
	for i, def in { { "ZoomIn", "＋", 1.6 }, { "ZoomOut", "－", 1 / 1.6 }, { "Locate", "◎", 0 } } do
		local b = K.Button(tools, { name = def[1], style = "glass", text = def[2], size = UDim2.fromOffset(44, 44), order = i, textSize = 18, zIndex = 10 })
		K.corner(b, UDim.new(0.5, 0))
		b.Activated:Connect(function()
			if def[3] == 0 then
				local here = rootPos()
				if here then
					mapCenter = here
				end
				layoutMap()
			else
				zoom(def[3] :: number)
			end
		end)
	end
	-- selection card
	mapCard = K.Card(body, { Name = "SelCard", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -8), Size = UDim2.new(1, -20, 0, 66), ZIndex = 4 })
	mapCardTitle = K.text(mapCard, { Name = "Title", Position = UDim2.fromOffset(12, 10), Size = UDim2.new(1, -130, 0, 22), Text = "지도를 눌러 목적지를 고르세요", Font = K.Font.bold, TextSize = K.Type.bodySm, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 })
	mapCardSub = K.text(mapCard, { Name = "Sub", Position = UDim2.fromOffset(12, 34), Size = UDim2.new(1, -130, 0, 18), Text = "핀을 누르면 그 장소로", TextColor3 = K.Color.sub, TextSize = K.Type.caption, ZIndex = 5 })
	mapGo = K.Button(mapCard, { name = "Go", style = "gold", text = "여기로", size = UDim2.fromOffset(100, 44), anchor = Vector2.new(1, 0.5), position = UDim2.new(1, -10, 0.5, 0), zIndex = 6 })
	K.setButtonEnabled(mapGo, false)
	mapGo.Activated:Connect(function()
		if mapGo:GetAttribute("Disabled") or not mapSel then
			return
		end
		if mapSel.name then
			destPicked = { kind = "name", name = mapSel.name, label = mapSel.name }
		else
			destPicked = { kind = "point", x = math.floor(mapSel.pos.X + 0.5), z = math.floor(mapSel.pos.Z + 0.5), label = "지도에서 고른 곳" }
		end
	end)
	-- pan (drag) / tap (select a point)
	local dragInput: InputObject? = nil
	local dragStart: Vector2? = nil
	local centerStart: Vector3? = nil
	local moved = false
	mapCanvas.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			dragInput = input
			dragStart = Vector2.new(input.Position.X, input.Position.Y)
			centerStart = mapCenter
			moved = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if not dragInput or not dragStart or not centerStart then
			return
		end
		local ok = input == dragInput or (dragInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement)
		if not ok then
			return
		end
		local delta = (Vector2.new(input.Position.X, input.Position.Y) - dragStart) / math.max(0.01, deviceScale.Scale)
		if delta.Magnitude > 6 then
			moved = true
		end
		if moved then
			mapCenter = (centerStart :: Vector3) - Vector3.new(delta.X / mapScale, 0, -delta.Y / mapScale)
			layoutMap()
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if not dragInput then
			return
		end
		if input == dragInput or (dragInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1) then
			if not moved and dragStart then
				local s = math.max(0.01, deviceScale.Scale)
				local local2 = (dragStart - mapWorld.AbsolutePosition) / s
				local world = pxToWorld(local2)
				-- snap to a pin within 22 px
				local best, bestD = nil, 22
				for _, pin in mapPins do
					if pin.frame.Name ~= "Pin_me" and pin.frame.Visible then
						local pp = worldToPx(pin.pos)
						local dd = (pp - local2).Magnitude
						if dd < bestD then
							best, bestD = pin, dd
						end
					end
				end
				if best then
					selectMapPoint(best.pos, (best.frame :: any):GetAttribute("PlaceName"))
				else
					selectMapPoint(world, nil)
				end
			end
			dragInput, dragStart, centerStart = nil, nil, nil
		end
	end)
end

local function openMap()
	if not mapBuilt then
		mapBuilt = true
		pcall(buildMapSegments)
		for i, seg in mapSegs do
			local long = (Vector2.new(seg[3], seg[4]) - Vector2.new(seg[1], seg[2])).Magnitude > 400
			local f = K.frame(mapWorld, { Name = "Road" .. i, AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = if long then 0.25 else 0.45, BackgroundColor3 = if long then Color3.fromRGB(120, 140, 180) else Color3.fromRGB(86, 100, 136), ZIndex = 3 })
			mapLines[i] = f
		end
		for _, pl in catalogue() do
			if pl.pos then
				local pin = K.frame(mapWorld, { Name = "Pin", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 0.1, BackgroundColor3 = Color3.fromRGB(34, 38, 60), ZIndex = 5 })
				K.corner(pin, UDim.new(0.5, 0))
				K.stroke(pin, K.Color.gold, 1, 0.3)
				K.text(pin, { Size = UDim2.fromScale(1, 1), Text = pl.icon, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 })
				pin:SetAttribute("PlaceName", pl.name)
				table.insert(mapPins, { frame = pin, pos = pl.pos })
			end
		end
		local meDot = K.frame(mapWorld, { Name = "Pin_me", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 0, BackgroundColor3 = K.Color.cyan, ZIndex = 7 })
		K.corner(meDot, UDim.new(0.5, 0))
		K.stroke(meDot, Color3.new(1, 1, 1), 2, 0)
		mapMe = meDot
		table.insert(mapPins, { frame = meDot, pos = rootPos() or mapCenter })
	end
	local here = rootPos()
	if here then
		mapCenter = here
		for _, pin in mapPins do
			if pin.frame == mapMe then
				pin.pos = here
			end
		end
	end
	mapScale = 0.09
	mapSel = nil
	if mapSelDot then
		mapSelDot:Destroy()
		mapSelDot = nil
	end
	mapCardTitle.Text = "지도를 눌러 목적지를 고르세요"
	mapCardSub.Text = "핀을 누르면 그 장소로"
	K.setButtonEnabled(mapGo, false)
	task.defer(layoutMap)
end

local function pickFromMap(mine: number): any
	destPicked = nil
	show("map", true)
	openMap()
	while serial == mine and destPicked == nil do
		task.wait(0.05)
	end
	show("call", false)
	if serial ~= mine then
		return nil
	end
	return destPicked
end

-------------------------------------------------------------------------------------------------
-- Dialer (keypad) page
-------------------------------------------------------------------------------------------------
local dialKeys: Frame
local dialCall: TextButton
local speed: Frame

local function normalizeNumber(s: string): string
	return (string.gsub(s, "[^%d]", ""))
end

local function formatDial(s: string): string
	local d = normalizeNumber(s)
	if #d == 8 and string.sub(d, 1, 2) == "15" then
		return string.sub(d, 1, 4) .. "-" .. string.sub(d, 5)
	elseif #d > 7 and string.sub(d, 1, 3) == "010" then
		return string.sub(d, 1, 3) .. "-" .. string.sub(d, 4, 7) .. "-" .. string.sub(d, 8)
	end
	return d
end

local function renderRecents()
	for _, c in recentBox:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local shown = 0
	for i, c in calls do
		if shown >= (if compact then 1 else 3) then
			break
		end
		shown += 1
		local ago = os.time() - c.at
		local when = if ago < 60 then "방금" elseif ago < 3600 then string.format("%d분 전", ago // 60) else string.format("%d시간 전", ago // 3600)
		local status = if c.status == "booked" then ("배차 · " .. (c.destination or "")) elseif c.status == "invalid" then "없는 번호" elseif c.status == "missed" then "연결 안 됨" else ("통화 " .. fmtDur(c.seconds))
		K.ListRow(recentBox, {
			name = "Recent" .. i,
			icon = if c.status == "invalid" then "❔" else "🚕",
			iconColor = K.Color.gold,
			round = true,
			title = c.name ~= "" and c.name or c.number,
			subtitle = "↗ " .. status,
			trailing = when,
			trailingColor = K.Color.faint,
			trailingWidth = 64,
			height = 48,
			order = i,
			onClick = function()
				M.open("taxiCall", { via = "redial", number = c.number })
			end,
		})
	end
	recentBox.Visible = shown > 0
end

local function buildDialPage()
	local p = page("dial")
	pageHead(p, "키패드", function()
		M.close()
	end)
	local body = K.frame(p, { Name = "Body", ZIndex = 2 })
	speed = K.make("TextButton", { Name = "SpeedDial", Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 0, 56), BackgroundColor3 = Color3.new(1, 1, 1), AutoButtonColor = false, Text = "", ZIndex = 3 }, body)
	K.corner(speed, K.Radius.md)
	K.gradient(speed, { GOLD1, GOLD2 }, 20)
	local ic = K.iconTile(speed, 38, "🚕", Color3.fromRGB(40, 30, 10), true)
	ic.AnchorPoint = Vector2.new(0, 0.5)
	ic.Position = UDim2.new(0, 10, 0.5, 0)
	K.text(speed, { Position = UDim2.fromOffset(58, 9), Size = UDim2.new(1, -120, 0, 20), Text = COMPANY, Font = K.Font.bold, TextSize = K.Type.body, TextColor3 = K.Color.onGold, ZIndex = 4 })
	local sub = K.text(speed, { Position = UDim2.fromOffset(58, 29), Size = UDim2.new(1, -120, 0, 16), Text = NUMBER .. " · 단축번호 1", TextSize = K.Type.caption, TextColor3 = Color3.fromRGB(80, 50, 0), ZIndex = 4 })
	K.mono(sub, Enum.FontWeight.Medium)
	local pill = K.frame(speed, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(40, 40), BackgroundTransparency = 0, BackgroundColor3 = K.Color.onGold, ZIndex = 4 })
	K.corner(pill, UDim.new(0.5, 0))
	K.text(pill, { Size = UDim2.fromScale(1, 1), Text = "📞", TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 })
	K.pressable(speed, { scale = 0.97 })
	speed.Activated:Connect(function()
		M.open("taxiCall", { via = "favorite" })
	end)
	recentBox = K.Card(body, { Name = "Recents", Position = UDim2.fromOffset(12, 62), Size = UDim2.new(1, -24, 0, 48), AutomaticSize = Enum.AutomaticSize.Y, ClipsDescendants = true, ZIndex = 3 })
	K.list(recentBox, false, 0)
	dialDisplay = K.text(body, { Name = "Display", Size = UDim2.new(1, -24, 0, 34), Position = UDim2.fromOffset(12, 118), Text = "", Font = K.Font.bold, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3 })
	K.mono(dialDisplay)
	dialKeys = K.frame(body, { Name = "Keys", AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(240, 240), ZIndex = 3 })
	local grid = K.make("UIGridLayout", { CellSize = UDim2.fromOffset(64, 50), CellPadding = UDim2.fromOffset(12, 8), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, dialKeys)
	local keys = { { "1", "" }, { "2", "ABC" }, { "3", "DEF" }, { "4", "GHI" }, { "5", "JKL" }, { "6", "MNO" }, { "7", "PQRS" }, { "8", "TUV" }, { "9", "WXYZ" }, { "*", "" }, { "0", "+" }, { "#", "" } }
	for i, k in keys do
		local b = K.Button(dialKeys, { name = "Key" .. k[1], style = "glass", text = k[1], order = i, textSize = 22, zIndex = 4 })
		K.corner(b, UDim.new(0.5, 0))
		b.Activated:Connect(function()
			if #dialNumber < 14 then
				dialNumber ..= k[1]
				dialDisplay.Text = formatDial(dialNumber)
			end
			sound("click", 1.6 + (i % 4) * 0.08, 0.18)
		end)
	end
	dialCall = K.Button(body, { name = "Dial", style = "success", icon = "📞", size = UDim2.fromOffset(60, 60), anchor = Vector2.new(0.5, 1), textSize = 24, zIndex = 4 })
	K.corner(dialCall, UDim.new(0.5, 0))
	dialCall.Activated:Connect(function()
		local d = normalizeNumber(dialNumber)
		if d == "" then
			-- empty: redial the last number like a real phone
			dialNumber = normalizeNumber(calls[1] and calls[1].number or NUMBER)
			dialDisplay.Text = formatDial(dialNumber)
			return
		end
		M.open("taxiCall", { via = "dial", number = formatDial(d) })
	end)
	local del = K.Button(body, { name = "Delete", style = "ghost", text = "⌫", size = UDim2.fromOffset(52, 52), anchor = Vector2.new(0.5, 1), textSize = 20, zIndex = 4 })
	del.Activated:Connect(function()
		dialNumber = string.sub(dialNumber, 1, math.max(0, #dialNumber - 1))
		dialDisplay.Text = formatDial(dialNumber)
	end)
	M._relayoutDial = function()
		local bodyH = L.h - 8 - L.statusH - 46
		local cell = if compact then 44 else 58
		local gap = if compact then 6 else 10
		grid.CellSize = UDim2.fromOffset(if compact then 58 else 66, cell)
		grid.CellPadding = UDim2.fromOffset(if compact then 10 else 14, gap)
		local keysH = 4 * cell + 3 * gap
		local callH = if compact then 48 else 60
		dialCall.Size = UDim2.fromOffset(callH, callH)
		del.Size = UDim2.fromOffset(if compact then 44 else 52, if compact then 44 else 52)
		local top = if compact then 0 else 118
		if compact then
			-- speed dial as a slim bar; recents hidden to fit the keypad
			speed.Size = UDim2.new(1, -24, 0, 48)
			recentBox.Visible = false
			dialDisplay.Position = UDim2.fromOffset(12, 50)
			dialDisplay.Size = UDim2.new(1, -24, 0, 28)
			dialDisplay.TextSize = 22
			top = 80
		else
			speed.Size = UDim2.new(1, -24, 0, 56)
			dialDisplay.TextSize = 26
			local rh = if #calls > 0 then math.min(3, #calls) * 48 else 0
			dialDisplay.Position = UDim2.fromOffset(12, 64 + rh + 6)
			top = 64 + rh + 44
		end
		local wKeys = 3 * (if compact then 58 else 66) + 2 * (if compact then 10 else 14)
		if not compact or bodyH >= top + keysH + callH + 12 then
			dialKeys.Visible = true
		end
		dialKeys.Size = UDim2.fromOffset(wKeys, keysH)
		dialKeys.Position = UDim2.new(0.5, 0, 0, top)
		dialCall.Position = UDim2.new(0.5, 0, 0, math.min(bodyH - 6, top + keysH + 8 + callH))
		del.Position = UDim2.new(0.5, wKeys / 2 - 22, 0, math.min(bodyH - 10, top + keysH + 8 + callH - 4))
	end
end

-------------------------------------------------------------------------------------------------
-- The call
-------------------------------------------------------------------------------------------------
local function startTimer(mine: number)
	callStart = os.clock()
	task.spawn(function()
		while serial == mine and inCall do
			timerLabel.Text = fmtDur(os.clock() - (callStart or os.clock()))
			task.wait(0.5)
		end
	end)
end

local function ringback(mine: number, rings_: number)
	for _ = 1, rings_ do
		if serial ~= mine then
			return
		end
		setState("뚜르르…", K.Color.sub)
		sound("ring", 0.62, 0.22)
		task.wait(0.34)
		if serial ~= mine then
			return
		end
		sound("ring", 0.62, 0.22)
		task.wait(1.6)
	end
end

local function fareLineText(q: any): string
	local km = if q.meters and q.meters >= 1000 then string.format("%.1fkm", q.meters / 1000) else string.format("%dm", q.meters or 0)
	local extra = ""
	if q.lines and q.lines.isNight then
		extra = " (심야 할증 포함)"
	elseif q.lines and q.lines.isRegular then
		extra = " (단골 할인 적용)"
	end
	return string.format("약 %s, 예상 요금은 %s이에요%s.", km, won(q.fare), extra)
end

-- Destination choices for the main question.
local function destChoices(h: any): { Choice }
	local out: { Choice } = {}
	local seen: { [string]: boolean } = {}
	local function add(name: string?, icon: string, label: string?)
		if type(name) ~= "string" or seen[name] or #out >= 4 then
			return
		end
		seen[name] = true
		table.insert(out, { id = "d:" .. name, label = label or name, icon = icon, data = { kind = "name", name = name, label = name } })
	end
	for _, s in (h and h.suggestions) or {} do
		add(s, "🎉", s .. (if h.night then " (오늘 밤 핫플)" else ""))
	end
	if h and h.home then
		add(h.home, "🏠", "집 · " .. h.home)
	end
	if h and h.work then
		add(h.work, "💼", "직장 · " .. h.work)
	end
	for _, r in (h and h.recent) or {} do
		add(r, "🕘", r)
	end
	for _, name in { "광안리 만남의 광장", "지하철 광안역 3번 출구", "CLUB OCEAN 광안", "민락회타운", "광안리해수욕장 (중앙)" } do
		if placeByName(name) then
			add(name, iconFor(name))
		end
	end
	table.insert(out, { id = "search", label = "목적지 검색", icon = "🔎" })
	table.insert(out, { id = "map", label = "지도에서 선택", icon = "🗺️" })
	table.insert(out, { id = "nearby", label = "근처 아무 데나 가 주세요", icon = "🎲" })
	return out
end

local function endAfter(mine: number, seconds: number, status: string, dest: string?)
	task.wait(seconds)
	if serial == mine then
		M.hangUp(status, dest)
	end
end

local destLoop: (number, any) -> ()

-- In the taxi, no destination yet: the driver asks in person (no ringing).
local function driverAsks(mine: number)
	local h = call("hello")
	if serial ~= mine then
		return
	end
	local job = h and h.active
	speaker = "🚖 " .. ((job and job.driverTitle) or "기사님")
	nameLabel.Text = (job and job.driverTitle) or "기사님"
	numberLabel.Text = (job and job.plate) or ""
	setAvatar("🧑‍✈️", Color3.fromRGB(150, 196, 236), Color3.fromRGB(60, 110, 170))
	setState("택시 안", K.Color.gold)
	inCall = true
	say("안녕하세요~ 어디로 모실까요?", mine)
	destLoop(mine, h or {})
end

-- The dispatcher conversation (runs in its own thread; every step checks `serial`).
local function conversation(mine: number, args: any)
	if mode == "dest" then
		driverAsks(mine)
		return
	end
	speaker = "🎧 " .. DISPATCHER
	local numberDialed = args.number
	if numberDialed and normalizeNumber(numberDialed) ~= normalizeNumber(NUMBER) then
		-- not the taxi company
		local d = normalizeNumber(numberDialed)
		nameLabel.Text = formatDial(d)
		numberLabel.Text = "휴대전화"
		setAvatar("👤", K.Color.violet, K.shade(K.Color.violet, 0.1, -0.25))
		ringback(mine, 1)
		if serial ~= mine then
			return
		end
		inCall = true
		startTimer(mine)
		setState("안내 음성", K.Color.orange)
		local line = if d == "112" or d == "119" then "긴급전화는 게임 속에서 연결되지 않아요. 실제 위급 상황이면 진짜 전화기로 걸어 주세요!" else "지금 거신 번호는 없는 번호입니다. 번호를 확인하시고 다시 걸어 주십시오."
		dispWho.Text = "📢 안내"
		say(line, mine, 20)
		dispWho.Text = "📢 안내"
		if serial == mine then
			endAfter(mine, 1.2, "invalid")
		end
		return
	end

	-- ring ring (1-2 rings) while the server is asked in parallel
	setState("통화 연결 중…", K.Color.sub)
	pulseRings(true)
	local helloDone = false
	task.spawn(function()
		hello = call("hello")
		helloDone = true
	end)
	task.wait(0.6)
	ringback(mine, if math.random() < 0.5 then 1 else 2)
	local t0 = os.clock()
	while serial == mine and not helloDone and os.clock() - t0 < 6 do
		ringback(mine, 1)
	end
	pulseRings(false)
	if serial ~= mine then
		return
	end
	local h = hello
	if not helloDone or not h or not h.ok then
		setState("연결 실패", K.Color.orange)
		say("…연결이 원활하지 않아요. 잠시 후 다시 걸어 주세요.", mine)
		endAfter(mine, 1.5, "missed")
		return
	end
	-- connected
	sound("click", 0.8, 0.3)
	K.haptic("notify")
	inCall = true
	startTimer(mine)
	setState("통화 중", K.Color.green)
	setAvatar("🎧", GOLD1, GOLD2)

	if h.active then
		local job = h.active
		local eta = math.max(0, math.floor((job.arriveAt or 0) - (job.now or 0)))
		local line = if job.state == "coming"
			then string.format("네, %s입니다. 고객님, 이미 배차된 차량이 있어요! %s %s %s, 약 %d초 후 도착 예정이에요.", COMPANY, job.color or "", job.car or "", job.plate or "", eta)
			elseif job.state == "arrived" then string.format("네, %s입니다. 고객님, 차량이 이미 도착해 있어요! %s %s %s, 비상등 켜고 기다리고 있어요.", COMPANY, job.color or "", job.car or "", job.plate or "")
			else string.format("네, %s입니다. 지금 운행 중이시네요! 편안한 이동 되세요.", COMPANY)
		say(line, mine)
		local choices: { Choice } = { { id = "ok", label = "네, 알겠어요", icon = "👌", style = "gold" } }
		if job.state == "coming" or job.state == "arrived" then
			table.insert(choices, { id = "cancel", label = "호출 취소할게요", icon = "✖️" })
		end
		local c = ask(choices, mine)
		if not c then
			return
		end
		if c.id == "cancel" then
			me("호출 취소해 주세요")
			local now = workspace:GetServerTimeNow()
			local fee = if now > (job.freeCancelUntil or 0) then (job.cancelFee or 1000) else 0
			say(if fee > 0 then string.format("배차 후 시간이 좀 지나서 취소 수수료 %s이 있어요. 그래도 취소할까요?", won(fee)) else "네, 지금 취소하시면 수수료는 없어요. 취소해 드릴까요?", mine)
			local c2 = ask({ { id = "yes", label = "네, 취소해 주세요", style = "danger" }, { id = "no", label = "아니요, 기다릴게요", icon = "🙂" } }, mine)
			if not c2 then
				return
			end
			if c2.id == "yes" then
				me("네, 취소해 주세요")
				local res = call("cancel")
				say(if res.ok then "취소 처리됐습니다. 다음에 또 이용해 주세요~" else (res.message or "취소하지 못했어요."), mine)
				endAfter(mine, 1.2, "ended")
				return
			end
			me("아니요, 기다릴게요")
		else
			me("네, 알겠어요")
		end
		say("네~ 감사합니다. 안전하게 모실게요!", mine)
		endAfter(mine, 1.0, "ended")
		return
	end

	if not h.open then
		local line = if h.code == "busy" then "네, " .. COMPANY .. "입니다. 죄송해요, 지금은 주변에 빈 차가 하나도 없네요. 잠시 후 다시 전화 주시겠어요?"
			elseif h.code == "noroad" then "네, " .. COMPANY .. "입니다. 고객님 계신 곳 근처에는 차가 들어갈 수 있는 길이 없어요. 큰길로 나오셔서 다시 전화 주세요!"
			else "네, " .. COMPANY .. "입니다. 지금 배차 시스템을 점검 중이에요. 잠깐 뒤에 다시 걸어 주세요."
		say(line, mine)
		local c = ask({ { id = "bye", label = "네, 알겠어요", icon = "👌", style = "gold" } }, mine)
		if c then
			me("네, 알겠어요")
			endAfter(mine, 0.6, "ended")
		end
		return
	end

	-- where to?
	local greet = if h.night then "네, 늦은 시간에도 " .. COMPANY .. "입니다!" else "네, " .. COMPANY .. "입니다."
	say(string.format("%s 지금 계신 곳이 %s 맞으시죠? 어디로 모실까요?", greet, h.pickupLabel or "현재 위치"), mine)
	destLoop(mine, h)
end

destLoop = function(mine: number, h: any)
	while serial == mine do
		local c = ask(destChoices(h), mine)
		if not c then
			return
		end
		local pickReq: any = nil
		local myLine = ""
		if c.id == "search" then
			me("잠깐만요, 찾아볼게요…")
			local pk = pickFromList(mine)
			if not pk then
				return
			end
			if pk.kind == "back" then
				say("천천히 말씀해 주세요~ 어디로 모실까요?", mine)
				continue
			end
			pickReq = { dest = pk.name }
			myLine = ro(pk.label) .. " 가 주세요"
		elseif c.id == "map" then
			me("지도로 보여 드릴게요")
			local pk = pickFromMap(mine)
			if not pk then
				return
			end
			if pk.kind == "back" then
				say("네~ 어디로 모실까요?", mine)
				continue
			end
			if pk.kind == "name" then
				pickReq = { dest = pk.name }
				myLine = ro(pk.label) .. " 가 주세요"
			else
				pickReq = { x = pk.x, z = pk.z }
				myLine = "지도에 찍은 곳으로 가 주세요"
			end
		elseif c.id == "nearby" then
			pickReq = { nearby = true }
			myLine = "근처 아무 데나 가 주세요"
		else
			pickReq = { dest = c.data.name }
			myLine = ro(c.data.label) .. " 가 주세요"
		end
		me(myLine)
		setState("통화 중 · 확인 중…", K.Color.green)
		task.wait(0.3)
		local q = call("quote", pickReq)
		setState("통화 중", K.Color.green)
		if serial ~= mine then
			return
		end
		if not q.ok then
			local line
			if q.code == "same" then
				line = "고객님, 거기는 바로 앞이에요! 걸어가셔도 되겠는데요? 😄 다른 곳으로 모실까요?"
			elseif q.code == "noroadDest" then
				line = "아이고, 그쪽은 차가 들어갈 수가 없어요. 근처 다른 곳은 어떠세요?"
			elseif q.code == "rate" then
				line = "잠시만요~ 다시 한번 말씀해 주세요."
			else
				line = (q.message or "잘 못 알아들었어요.") .. " 다시 말씀해 주세요."
			end
			say(line, mine)
			continue
		end
		local destLabel = q.destination or "목적지"
		if pickReq.nearby then
			say(string.format("그럼 기사님 추천으로 %s 어떠세요? %s", ro(destLabel), fareLineText(q)), mine)
		else
			say(string.format("%s요. %s", destLabel, fareLineText(q)), mine)
		end
		if not q.canAfford then
			say(string.format("그런데 고객님, 잔액이 조금 부족하신 것 같아요. (현금 %s · 통장 %s) 가까운 곳으로 하시겠어요?", won(q.cash), won(q.bank)), mine)
			continue
		end
		if mode == "dest" then
			-- the taxi is already here: just set the destination
			local c2 = ask({ { id = "go", label = "네, 그리로 가 주세요", icon = "🚕", style = "gold" }, { id = "other", label = "다른 곳으로 할게요", icon = "↩️" } }, mine)
			if not c2 then
				return
			end
			if c2.id == "other" then
				me("다른 곳으로 할게요")
				say("네, 어디로 모실까요?", mine)
				continue
			end
			local r = call("setDest", pickReq)
			if r.ok then
				M.close()
			else
				say(r.message or "지금은 바꿀 수 없어요.", mine)
			end
			return
		end
		local c2 = ask({ { id = "book", label = "네, 불러 주세요", icon = "🚕", style = "gold" }, { id = "other", label = "다른 곳으로 할게요", icon = "↩️" } }, mine)
		if not c2 then
			return
		end
		if c2.id == "other" then
			me("다른 곳으로 할게요")
			say("네, 어디로 모실까요?", mine)
			continue
		end
		me("네, 불러 주세요!")
		setState("배차 요청 중…", K.Color.gold)
		dispWho.Text = speaker
		dispLabel.Text = "주변 기사님께 배차 요청 중입니다… 잠시만 기다려 주세요 🚕"
		speaking(true)
		task.wait(1.1)
		local b = call("book", pickReq)
		speaking(false)
		if serial ~= mine then
			return
		end
		if not b.ok then
			setState("통화 중", K.Color.green)
			local line = if b.code == "busy" then "죄송해요, 방금 주변 차가 모두 배차됐어요. 잠시 후 다시 전화 주세요."
				elseif b.code == "money" then string.format("고객님, 예상 요금 %s이 잔액보다 많아요. 가까운 곳으로 하시겠어요?", won(b.fare or 0))
				elseif b.code == "active" then "이미 배차된 차량이 있어요! 문자로 차량 정보 다시 보내 드릴게요."
				else (b.message or "배차하지 못했어요.") .. " 다시 시도해 주세요."
			say(line, mine)
			if b.code == "money" then
				continue
			end
			endAfter(mine, 1.5, "ended")
			return
		end
		local job = b.job or {}
		local eta = math.max(1, math.floor((job.arriveAt or 0) - (job.now or 0) + 0.5))
		setState("배차 완료 🚕", K.Color.gold)
		K.feedback("success")
		say(string.format("배차됐습니다! %s %s, %s. %s이 약 %d초 후 도착해요. 도착하면 문자 드릴게요~ 감사합니다!", job.color or "", job.car or "택시", job.plate or "", job.driverTitle or "기사님", eta), mine)
		F.emit("taxiBooked", job)
		endAfter(mine, 1.2, "booked", destLabel)
		return
	end
end

function M.hangUp(status: string?, dest: string?)
	if not isOpen then
		return
	end
	local wasCall = current == "call" or current == "dest" or current == "map"
	serial += 1
	local mine = serial
	pulseRings(false)
	speaking(false)
	if wasCall and pages.call.Visible ~= false then
		logCall(status or "ended", dest, nameLabel.Text ~= COMPANY and nameLabel.Text or NUMBER)
		setState(if status == "booked" then "배차 완료 · 통화 종료" else "통화 종료", K.Color.faint)
		-- 뚜-뚜-뚜
		task.spawn(function()
			for _ = 1, 3 do
				sound("click", 0.55, 0.25)
				task.wait(0.22)
			end
		end)
	end
	inCall = false
	clearChoices()
	task.delay(0.7, function()
		if serial == mine then
			M.close()
		end
	end)
end

local function startCall(args: any)
	serial += 1
	local mine = serial
	inCall = false
	callStart = nil
	hello = nil
	nameLabel.Text = COMPANY
	numberLabel.Text = NUMBER
	timerLabel.Text = ""
	meLine.Text = ""
	dispWho.Text = ""
	dispLabel.Text = ""
	setAvatar("🚕", GOLD1, GOLD2)
	clearChoices()
	show("call")
	pages.call.Position = UDim2.fromScale(0, 0)
	task.spawn(function()
		local ok, err = pcall(conversation, mine, args or {})
		if not ok then
			warn("[TaxiCall] conversation failed: " .. tostring(err))
			if serial == mine then
				M.hangUp("missed")
			end
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- Open / close
-------------------------------------------------------------------------------------------------
local clockSerial = 0
local function showDevice()
	if isOpen then
		return
	end
	isOpen = true
	F.modal(true, "taxiCall")
	applyLayout()
	dim.Visible = true
	device.Visible = true
	dim.BackgroundTransparency = 1
	K.tween(dim, 0.25, { BackgroundTransparency = 0.55 })
	local s = device:FindFirstChild("Slide") :: UIScale?
	local _ = s
	device.Position = UDim2.new(device.Position.X.Scale, device.Position.X.Offset + 40, device.Position.Y.Scale, device.Position.Y.Offset)
	K.tween(device, 0.3, { Position = UDim2.new(device.Position.X.Scale, device.Position.X.Offset - 40, device.Position.Y.Scale, device.Position.Y.Offset) })
	K.feedback("open")
	clockSerial += 1
	local mine = clockSerial
	task.spawn(function()
		while clockSerial == mine and isOpen do
			local c = gameClock()
			local h = math.floor(c) % 24
			local m = math.floor((c % 1) * 60)
			statusTime.Text = string.format("%d:%02d", if h % 12 == 0 then 12 else h % 12, m)
			task.wait(2)
		end
	end)
end

function M.close()
	if not isOpen then
		return
	end
	serial += 1
	isOpen = false
	inCall = false
	pulseRings(false)
	speaking(false)
	clearChoices()
	K.tween(dim, 0.2, { BackgroundTransparency = 1 })
	local mine = serial
	task.delay(0.2, function()
		if serial == mine and not isOpen then
			dim.Visible = false
			device.Visible = false
		end
	end)
	F.modal(false, "taxiCall")
	K.feedback("close")
end

function M.isOpen(): boolean
	return isOpen
end

function M.open(flowId: string, args: any?)
	local a = if type(args) == "table" then args else {}
	if flowId == "taxiDialer" then
		showDevice()
		serial += 1
		mode = "call"
		dialNumber = if type(a.number) == "string" then normalizeNumber(a.number) else ""
		dialDisplay.Text = formatDial(dialNumber)
		renderRecents()
		if M._relayoutDial then
			M._relayoutDial()
		end
		for n, pg in pages do
			pg.Visible = n == "dial"
		end
		current = "dial"
		return
	end
	if flowId == "taxiDest" then
		showDevice()
		mode = "dest"
		startCall({})
		return
	end
	-- taxiCall
	showDevice()
	mode = "call"
	for n, pg in pages do
		pg.Visible = n == "call"
	end
	current = "call"
	startCall(a)
end

-------------------------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------------------------
function M.init(ctx: any)
	F = ctx
	K = ctx.K
	Layout = ctx.Layout
	player = ctx.player
	dim = K.frame(F.gui, { Name = "TaxiCallDim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, Active = true, Visible = false, ZIndex = 100 })
	device = K.frame(F.gui, { Name = "TaxiCallDevice", BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(6, 6, 10), Visible = false, Active = true, ZIndex = 101 })
	deviceScale = K.make("UIScale", { Name = "DeviceScale", Scale = 1 }, device)
	K.stroke(device, Color3.fromRGB(90, 96, 120), 1, 0.4)
	screen = K.frame(device, { Name = "Screen", BackgroundTransparency = 0, BackgroundColor3 = K.Color.bg, ClipsDescendants = true, ZIndex = 1 })
	statusBar(screen)
	buildCallPage()
	buildDestPage()
	buildMapPage()
	buildDialPage()
	pages.call.Visible = true
	-- status bar above the pages
	local sb = screen:FindFirstChild("StatusBar")
	if sb and sb:IsA("GuiObject") then
		sb.ZIndex = 40
	end
	Layout.onChanged(function()
		if isOpen then
			applyLayout()
		end
	end)
	-- call log for the phone's 최근 tab
	local old = player:FindFirstChild("GwangalliTaxiCallLog")
	if old then
		old:Destroy()
	end
	local ev = Instance.new("BindableEvent")
	ev.Name = "GwangalliTaxiCallLog"
	ev.Parent = player
	logEvent = ev
	player.CharacterAdded:Connect(function()
		if isOpen and mode == "dest" then
			M.close()
		end
	end)
end

return M
