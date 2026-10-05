-- GwangalliLaw (LocalScript, StarterPlayerScripts; owner: law): the client of 광안리 치안
-- (ServerScriptService.GwangalliGameplay.Law). The server decides everything; this script shows it:
--   * WANTED card (top centre): ★ stars, the tier ("순찰차 출동"), a 추적 회피 bar (LawSearch: how close
--     the stars are to dropping while no officer sees you), red / blue flashing while chased, 🙌 손들기.
--   * RADIO ticker (무전), toasts, the STOP order dialog (순순히 응하기 / 변명 / 도망), the ARREST summary
--     (crimes, 벌금 paid / 미납, 압수, the sentence) and the 유치장 panel ([남은 시간], 앉기 / 수감자와 대화 /
--     인사 / 팔굽혀펴기 / 공기놀이 (a timing mini-game) / 보석금, the cell chat).
--   * 👮 POLICE panel (the police job): 근무 시작 / 종료, 신고 목록, 수배자 (last known area + 추적),
--     순찰, 순찰차, 차량 조회, and context buttons near a target (수갑 / 범칙금 / NPC 검거, 인계 / 자동 이송).
--   * 🕶️ CRIME panel: crime level / XP, the petty crimes (locks, cooldowns, risks), the organised jobs and
--     the live job tracker; the 👛 소매치기 button behind a pedestrian (GwangalliMindAPI "nearest").
--   * World MARKERS (Workspace BillboardGuis) for cop waypoints, contraband drops and job steps.
--   * CUFFS: the arms go behind the back while LawCuffed is set.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local LSm = ReplicatedStorage:WaitForChild("GwangalliLawShared", 30)
if not LSm then
	return
end
local LS = require(LSm) :: any
local folder = ReplicatedStorage:WaitForChild(LS.Folder, 60)
if not folder then
	return
end
local Action = folder:WaitForChild(LS.Remote.Action, 30) :: RemoteFunction
local Event = folder:WaitForChild(LS.Remote.Event, 30) :: RemoteEvent
local A = LS.Attr

local state: any = { stars = 0 }
local copView: any = nil
local jailView: any = nil
local bigState: any = nil

local function call(op: string, payload: any?): any
	local ok, res = pcall(function()
		return Action:InvokeServer(op, payload)
	end)
	return if ok and type(res) == "table" then res else { ok = false, err = "net" }
end

-------------------------------------------------------------------------------------------------
-- UI kit (plain instances; dark navy glass like the rest of the HUD)
-------------------------------------------------------------------------------------------------
local NAVY = Color3.fromRGB(16, 22, 44)
local INK = Color3.fromRGB(236, 240, 255)
local SUB = Color3.fromRGB(160, 172, 205)
local RED = Color3.fromRGB(255, 72, 88)
local BLUE = Color3.fromRGB(70, 130, 255)
local GOLD = Color3.fromRGB(255, 206, 84)
local GREEN = Color3.fromRGB(80, 220, 140)

local function new(cls: string, props: { [string]: any }, parent: Instance?): any
	local i = Instance.new(cls)
	for k, v in props do
		(i :: any)[k] = v
	end
	if parent then
		i.Parent = parent
	end
	return i
end

local function corner(p: Instance, r: number?)
	new("UICorner", { CornerRadius = UDim.new(0, r or 12) }, p)
end

local function stroke(p: Instance, c: Color3?, t: number?)
	new("UIStroke", { Color = c or Color3.new(1, 1, 1), Transparency = t or 0.85, Thickness = 1 }, p)
end

local function pad(p: Instance, x: number, y: number)
	new("UIPadding", { PaddingLeft = UDim.new(0, x), PaddingRight = UDim.new(0, x), PaddingTop = UDim.new(0, y), PaddingBottom = UDim.new(0, y) }, p)
end

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local t = new("TextLabel", {
		BackgroundTransparency = 1,
		TextColor3 = INK,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		RichText = true,
	}, parent)
	for k, v in props do
		(t :: any)[k] = v
	end
	return t
end

local function button(parent: Instance, text: string, color: Color3?, onClick: () -> ()): TextButton
	local b = new("TextButton", {
		Text = text,
		Size = UDim2.fromOffset(120, 40),
		BackgroundColor3 = color or Color3.fromRGB(44, 56, 96),
		TextColor3 = INK,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		AutoButtonColor = true,
		TextWrapped = true,
	}, parent)
	corner(b, 10)
	b.Activated:Connect(function()
		onClick()
	end)
	return b
end

local gui = new("ScreenGui", { Name = "GwangalliLaw", ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = 30, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))

-------------------------------------------------------------------------------------------------
-- Toasts + radio
-------------------------------------------------------------------------------------------------
local toastHolder = new("Frame", { Name = "Toasts", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -210), Size = UDim2.fromOffset(420, 160), BackgroundTransparency = 1 }, gui)
new("UIListLayout", { VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, toastHolder)
local toastN = 0

local function toast(text: string, tone: string?)
	toastN += 1
	local color = if tone == "warn" then Color3.fromRGB(80, 24, 34) elseif tone == "crime" then Color3.fromRGB(40, 24, 70) elseif tone == "good" then Color3.fromRGB(18, 60, 40) else NAVY
	local f = new("TextLabel", {
		Text = text,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = color,
		BackgroundTransparency = 0.12,
		TextColor3 = INK,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextWrapped = true,
		LayoutOrder = toastN,
	}, toastHolder)
	corner(f, 12)
	pad(f, 12, 8)
	stroke(f, nil, 0.8)
	task.delay(4.2, function()
		f:Destroy()
	end)
	local kids = toastHolder:GetChildren()
	if #kids > 6 then
		for _, k in kids do
			if k:IsA("TextLabel") and k.LayoutOrder < toastN - 4 then
				k:Destroy()
			end
		end
	end
end

local radio = label(gui, { Name = "Radio", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 194), Size = UDim2.fromOffset(460, 26), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Color3.fromRGB(180, 220, 255), Font = Enum.Font.Code, TextSize = 14, Visible = false, BackgroundColor3 = Color3.fromRGB(8, 14, 30), BackgroundTransparency = 0.25 })
corner(radio, 8)
local radioSeq = 0
local function showRadio(text: string)
	radioSeq += 1
	local mine = radioSeq
	radio.Text = "📻 " .. text
	radio.Visible = true
	task.delay(5, function()
		if radioSeq == mine then
			radio.Visible = false
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- Wanted card
-------------------------------------------------------------------------------------------------
local wanted = new("Frame", { Name = "Wanted", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 124), Size = UDim2.fromOffset(330, 64), BackgroundColor3 = NAVY, BackgroundTransparency = 0.1, Visible = false }, gui)
corner(wanted, 14)
local wStroke = new("UIStroke", { Color = RED, Thickness = 2, Transparency = 0.3 }, wanted)
local wStars = label(wanted, { Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -120, 0, 30), Text = "", TextSize = 24, Font = Enum.Font.GothamBlack, TextColor3 = GOLD })
local wTier = label(wanted, { Position = UDim2.fromOffset(12, 32), Size = UDim2.new(1, -120, 0, 16), Text = "", TextSize = 12, TextColor3 = SUB })
local wBarBg = new("Frame", { Position = UDim2.new(0, 12, 1, -10), Size = UDim2.new(1, -124, 0, 5), BackgroundColor3 = Color3.fromRGB(40, 48, 80) }, wanted)
corner(wBarBg, 3)
local wBar = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = GREEN }, wBarBg)
corner(wBar, 3)
local handsBtn = button(wanted, "🙌 손들기", Color3.fromRGB(70, 60, 30), function()
	local r = call("surrender")
	if r.ok then
		toast("🙌 손을 들었어요. 경찰이 다가와요…")
	else
		toast("근처에 경찰이 없어요", "warn")
	end
end)
handsBtn.AnchorPoint = Vector2.new(1, 0.5)
handsBtn.Position = UDim2.new(1, -10, 0.5, 0)
handsBtn.Size = UDim2.fromOffset(96, 40)

local function refreshWanted()
	local stars = player:GetAttribute(A.Wanted) or 0
	local jailed = (player:GetAttribute(A.Jail) or 0) > 0
	wanted.Visible = stars > 0 and not jailed
	if stars <= 0 then
		return
	end
	wStars.Text = "🚨 " .. LS.stars(stars)
	local t = LS.TIERS[math.clamp(stars, 1, 5)]
	local chase = player:GetAttribute(A.Chase) == true
	wTier.Text = (if chase then "<font color='#ff6070'>추격 중!</font> · " else "수색 중 · ") .. t.label
	local search = player:GetAttribute(A.Search) or 0
	wBar.Size = UDim2.fromScale(math.clamp(search, 0, 1), 1)
	handsBtn.Visible = not (player:GetAttribute(A.Cuffed) == true)
end

-- flashing border while chased
task.spawn(function()
	local on = false
	while true do
		task.wait(0.35)
		if wanted.Visible then
			on = not on
			local chase = player:GetAttribute(A.Chase) == true
			wStroke.Color = if chase then (if on then RED else BLUE) else Color3.fromRGB(120, 130, 170)
			wStroke.Transparency = if chase then 0 else 0.5
		end
	end
end)

for _, n in { A.Wanted, A.Chase, A.Search, A.Jail, A.Cuffed } do
	player:GetAttributeChangedSignal(n):Connect(refreshWanted)
end
refreshWanted()

-------------------------------------------------------------------------------------------------
-- Modal helpers
-------------------------------------------------------------------------------------------------
local function modal(name: string, w: number, h: number): Frame
	local old = gui:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local f = new("Frame", { Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(w, h), BackgroundColor3 = NAVY, BackgroundTransparency = 0.04 }, gui)
	corner(f, 16)
	stroke(f, nil, 0.75)
	pad(f, 14, 12)
	return f
end

local function closeBtn(f: Frame, onClose: (() -> ())?)
	local b = button(f, "✕", Color3.fromRGB(60, 40, 50), function()
		f:Destroy()
		if onClose then
			onClose()
		end
	end)
	b.AnchorPoint = Vector2.new(1, 0)
	b.Position = UDim2.new(1, 4, 0, -4)
	b.Size = UDim2.fromOffset(36, 32)
	b.ZIndex = 5
end

local function row(parent: Instance, h: number, order: number): Frame
	local r = new("Frame", { Size = UDim2.new(1, 0, 0, h), BackgroundTransparency = 1, LayoutOrder = order }, parent)
	return r
end

local function hlist(parent: Instance, gap: number?)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, gap or 8), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center, Wraps = true }, parent)
end

local function vlist(parent: Instance, gap: number?)
	new("UIListLayout", { Padding = UDim.new(0, gap or 8), SortOrder = Enum.SortOrder.LayoutOrder }, parent)
end

local function scroller(parent: Instance, y: number): ScrollingFrame
	local s = new("ScrollingFrame", { Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 1, -y), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, parent)
	vlist(s, 8)
	return s
end

-------------------------------------------------------------------------------------------------
-- Stop order
-------------------------------------------------------------------------------------------------
local function showStop(msg: any)
	local f = modal("LawStop", 380, 190)
	label(f, { Size = UDim2.new(1, 0, 0, 26), Text = "👮 " .. tostring(msg.officer or "경찰관") .. ": \"멈추세요, 경찰입니다.\"", Font = Enum.Font.GothamBold, TextSize = 16 })
	local cd = label(f, { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 20), Text = "", TextColor3 = SUB, TextSize = 13 })
	local holder = new("Frame", { Position = UDim2.fromOffset(0, 62), Size = UDim2.new(1, 0, 0, 100), BackgroundTransparency = 1 }, f)
	hlist(holder, 8)
	for _, c in (msg.choices or {}) do
		local b = button(holder, c.label, if c.id == "comply" then Color3.fromRGB(30, 90, 60) elseif c.id == "flee" then Color3.fromRGB(110, 40, 50) else Color3.fromRGB(60, 60, 100), function()
			f:Destroy()
			local r = call("stopAnswer", { choice = c.id })
			if r.result == "ticket" then
				toast("🧾 범칙금으로 끝났어요", "good")
			elseif r.result == "let_go" then
				toast("😮‍💨 이번엔 봐줬어요!", "good")
			elseif r.result == "flee" then
				toast("🏃 도망쳐! 수배가 올라갔어요", "warn")
			end
		end)
		b.Size = UDim2.fromOffset(110, 44)
	end
	local t0 = os.clock()
	task.spawn(function()
		while f.Parent do
			local left = (msg.grace or 6) - (os.clock() - t0)
			if left <= 0 then
				f:Destroy()
				break
			end
			cd.Text = string.format("⏳ %.0f초 안에 대답하세요 (멀어지면 도주로 처리)", left)
			task.wait(0.2)
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- Arrest summary
-------------------------------------------------------------------------------------------------
local function showArrest(msg: any)
	if msg.stage == "cuffs" then
		local f = modal("LawArrest", 400, 220)
		label(f, { Size = UDim2.new(1, 0, 0, 34), Text = "🚓 체포되었습니다", Font = Enum.Font.GothamBlack, TextSize = 24, TextColor3 = RED, TextXAlignment = Enum.TextXAlignment.Center })
		local lines = {
			"혐의: " .. (if msg.crimes and msg.crimes ~= "" then msg.crimes else "범죄"),
			"벌금 " .. LS.won(msg.fine or 0) .. " (납부 " .. LS.won(msg.paid or 0) .. (if (msg.owed or 0) > 0 then ", 미납 " .. LS.won(msg.owed) else "") .. ")",
		}
		if (msg.seized or 0) > 0 then
			table.insert(lines, "범죄 수익 압수 " .. LS.won(msg.seized))
		end
		table.insert(lines, "유치장 " .. LS.fmtTime(msg.seconds or 0) .. " · " .. tostring(msg.band or ""))
		if msg.surrender then
			table.insert(lines, "🙌 자수 참작: 벌금·형기 감경")
		end
		label(f, { Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 1, -42), Text = table.concat(lines, "\n"), TextSize = 15, TextYAlignment = Enum.TextYAlignment.Top })
		task.delay(5, function()
			if f.Parent then
				f:Destroy()
			end
		end)
	elseif msg.stage == "ride" then
		toast(msg.text or "🚓 이송 중…")
	elseif msg.stage == "escort" then
		toast("🔗 " .. tostring(msg.cop) .. " 경찰관이 지구대로 호송 중이에요", "warn")
	end
end

-------------------------------------------------------------------------------------------------
-- Jail panel + mini-game
-------------------------------------------------------------------------------------------------
local jailPanel: Frame? = nil
local jailTimer: TextLabel? = nil
local jailChat: Frame? = nil
local bailBtn: TextButton? = nil

local function jailAct(act: string, extra: any?)
	local p = extra or {}
	p.act = act
	local r = call("jail", p)
	if not r.ok and r.text then
		toast(r.text, "warn")
	end
	return r
end

local function cellChatLine(text: string)
	if not jailChat then
		return
	end
	local l = label(jailChat, { Size = UDim2.new(1, 0, 0, 18), Text = text, TextSize = 13, TextColor3 = SUB })
	l.LayoutOrder = math.floor(os.clock() * 10)
	local kids = {}
	for _, c in jailChat:GetChildren() do
		if c:IsA("TextLabel") then
			table.insert(kids, c)
		end
	end
	table.sort(kids, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #kids > 4 do
		table.remove(kids, 1):Destroy()
	end
end

local function playGonggi(msg: any)
	local f = modal("LawGame", 360, 170)
	label(f, { Size = UDim2.new(1, 0, 0, 24), Text = "🎯 공기놀이 — 초록 칸에서 잡아요!", Font = Enum.Font.GothamBold, TextSize = 16 })
	local bar = new("Frame", { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = Color3.fromRGB(40, 46, 70) }, f)
	corner(bar, 8)
	local zone = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(msg.zone, 0), Size = UDim2.fromScale(msg.width, 1), BackgroundColor3 = GREEN, BackgroundTransparency = 0.25 }, bar)
	corner(zone, 6)
	local marker = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.new(0, 6, 1, 6), Position = UDim2.new(0, 0, 0, -3), BackgroundColor3 = GOLD }, bar)
	corner(marker, 3)
	local x, dir = 0, 1
	local live = true
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		if not live then
			return
		end
		x += dir * dt * (msg.speed or 1)
		if x > 1 then
			x, dir = 1, -1
		elseif x < 0 then
			x, dir = 0, 1
		end
		marker.Position = UDim2.new(x, 0, 0, -3)
	end)
	local b = button(f, "✋ 잡기!", Color3.fromRGB(40, 110, 70), function() end)
	b.Position = UDim2.fromOffset(0, 84)
	b.Size = UDim2.new(1, 0, 0, 48)
	b.Activated:Connect(function()
		if not live then
			return
		end
		live = false
		conn:Disconnect()
		local r = jailAct("gameEnd", { hit = x })
		toast(if r.win then "🏆 이겼다! 형기 단축" else "😅 아깝다…", if r.win then "good" else nil)
		task.delay(0.6, function()
			f:Destroy()
		end)
	end)
end

local function closeJail()
	if jailPanel then
		jailPanel:Destroy()
		jailPanel = nil
		jailTimer = nil
		jailChat = nil
		bailBtn = nil
	end
end

local function openJail(v: any)
	jailView = v
	if not jailPanel then
		local f = new("Frame", { Name = "LawJail", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(560, 172), BackgroundColor3 = NAVY, BackgroundTransparency = 0.08 }, gui)
		corner(f, 16)
		stroke(f, GOLD, 0.6)
		pad(f, 14, 10)
		jailTimer = label(f, { Size = UDim2.new(1, 0, 0, 28), Text = "", Font = Enum.Font.GothamBlack, TextSize = 20 })
		local sub = label(f, { Name = "Sub", Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 16), Text = "", TextSize = 12, TextColor3 = SUB })
		sub.Name = "Sub"
		local bar = new("Frame", { Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1 }, f)
		hlist(bar, 6)
		for _, spec in {
			{ "🪑 앉기", "sit" },
			{ "💬 수감자와 대화", "talk" },
			{ "👋 인사", "greet" },
			{ "💪 팔굽혀펴기", "workout" },
			{ "🎯 공기놀이", "gameStart" },
		} do
			local b = button(bar, spec[1], nil, function()
				local r = jailAct(spec[2])
				if spec[2] == "workout" and r.ok then
					toast("💪 팔굽혀펴기 " .. tostring(r.sets) .. "세트! (근력 +1)", "good")
				end
			end)
			b.Size = UDim2.fromOffset(98, 40)
			b.TextSize = 13
		end
		bailBtn = button(f, "💸 보석금", Color3.fromRGB(90, 70, 20), function()
			local r = jailAct("bail")
			if r.ok then
				toast("💸 보석금 " .. LS.won(r.paid or 0) .. " 납부", "good")
			end
		end)
		bailBtn.AnchorPoint = Vector2.new(1, 0)
		bailBtn.Position = UDim2.new(1, 0, 0, 0)
		bailBtn.Size = UDim2.fromOffset(150, 34)
		jailChat = new("Frame", { Position = UDim2.fromOffset(0, 100), Size = UDim2.new(1, 0, 0, 56), BackgroundTransparency = 1 }, f)
		vlist(jailChat, 0)
		jailPanel = f
	end
end

local function updateJail()
	local endsAt = player:GetAttribute(A.Jail) or 0
	if endsAt <= 0 then
		closeJail()
		return
	end
	if not jailPanel then
		openJail(jailView or {})
	end
	local left = math.max(0, endsAt - workspace:GetServerTimeNow())
	if jailTimer then
		jailTimer.Text = "🔒 광안지구대 유치장 · 남은 시간 " .. LS.fmtTime(left)
	end
	local sub = jailPanel and jailPanel:FindFirstChild("Sub") :: TextLabel?
	if sub and jailView then
		sub.Text = tostring(jailView.label or "") .. (if jailView.crimes and jailView.crimes ~= "" then " · " .. jailView.crimes else "") .. "  ·  공기 " .. tostring(jailView.games or 0) .. "/3 · 운동 " .. tostring(jailView.workouts or 0) .. "/4"
	end
	if bailBtn and jailView then
		local total = math.max(1, jailView.total or 60)
		local bail = LS.bailFor(jailView.sev or 1, left, total)
		if jailView.bail then
			-- the server's figure at the last update, scaled down as time passes
			bail = math.max(5000, math.floor(jailView.bail * (left / math.max(1, jailView.left or left)) / 1000 + 0.5) * 1000)
		end
		bailBtn.Text = "💸 보석금 " .. LS.won(bail)
	end
end

task.spawn(function()
	while true do
		task.wait(0.5)
		pcall(updateJail)
	end
end)

-------------------------------------------------------------------------------------------------
-- World markers
-------------------------------------------------------------------------------------------------
local markers: { [string]: any } = {}
local function setMarker(key: string, pos: any?, text: string?, color: Color3?)
	local m = markers[key]
	if not pos then
		if m then
			m.part:Destroy()
			markers[key] = nil
		end
		return
	end
	local v = if typeof(pos) == "Vector3" then pos else Vector3.new(pos[1], pos[2], pos[3])
	if not m then
		local p = new("Part", { Name = "LawMarker_" .. key, Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Transparency = 1, Size = Vector3.new(1, 1, 1) }, workspace)
		local bb = new("BillboardGui", { Size = UDim2.fromOffset(200, 50), AlwaysOnTop = true, MaxDistance = 2000, LightInfluence = 0, Adornee = p }, p)
		local t = label(bb, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Font = Enum.Font.GothamBold, TextSize = 15, BackgroundColor3 = color or Color3.fromRGB(30, 50, 110), BackgroundTransparency = 0.15 })
		corner(t, 10)
		m = { part = p, label = t, text = text or "" }
		markers[key] = m
	end
	m.part.Position = v + Vector3.new(0, 6, 0)
	m.text = text or m.text
end

task.spawn(function()
	while true do
		task.wait(0.4)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		for _, m in markers do
			local d = root and math.floor((m.part.Position - (root :: BasePart).Position).Magnitude * 0.3) or 0
			m.label.Text = "📍 " .. m.text .. "  " .. d .. "m"
		end
	end
end)

-------------------------------------------------------------------------------------------------
-- Dock buttons (👮 / 🕶️)
-------------------------------------------------------------------------------------------------
local dock = new("Frame", { Name = "LawDock", Position = UDim2.new(0, 16, 0, 436), Size = UDim2.fromOffset(56, 120), BackgroundTransparency = 1 }, gui)
vlist(dock, 8)

local function dockBtn(text: string, order: number, onClick: () -> ()): TextButton
	local b = button(dock, text, Color3.fromRGB(26, 32, 60), onClick)
	b.Size = UDim2.fromOffset(56, 56)
	b.LayoutOrder = order
	b.TextSize = 13
	return b
end

-------------------------------------------------------------------------------------------------
-- Police panel
-------------------------------------------------------------------------------------------------
local openPolice: () -> ()

local function copToolRow(parent: Instance, order: number)
	local r = row(parent, 92, order)
	hlist(r, 6)
	local function tool(text: string, act: string, payload: any?, after: ((any) -> ())?)
		local b = button(r, text, nil, function()
			local p = payload or {}
			p.act = act
			local res = call("cop", p)
			if res.text then
				toast(res.text, if res.ok then "good" else "warn")
			end
			if after then
				after(res)
			end
		end)
		b.Size = UDim2.fromOffset(112, 40)
		b.TextSize = 13
	end
	tool("🚶 순찰 시작", "patrol", nil, function(res)
		if res.ok then
			toast("🚶 순찰 경로를 받았어요", "good")
		end
	end)
	tool("🚓 순찰차", "car")
	tool("🔎 차량 조회", "lookup", nil, function(res)
		if res.ok and res.car then
			local c = res.car
			toast(string.format("🔎 %s · %s · 소유: %s%s%s", tostring(c.label), tostring(c.plate), tostring(c.owner), if c.driver then " · 운전자 " .. c.driver else "", if c.stolen then " · 🚨 도난 차량" .. (if c.stolenBy then " (" .. c.stolenBy .. ")" else "") else ""), if c.stolen then "warn" else nil)
		end
	end)
	tool("🏢 인계", "handover")
	tool("🚐 자동 이송", "transfer")
end

openPolice = function()
	local f = modal("LawPolice", 520, 440)
	closeBtn(f)
	local head = label(f, { Size = UDim2.new(1, -40, 0, 26), Text = "👮 광안지구대", Font = Enum.Font.GothamBlack, TextSize = 20 })
	local info = label(f, { Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 34), Text = "불러오는 중…", TextSize = 13, TextColor3 = SUB, TextYAlignment = Enum.TextYAlignment.Top })
	local body = scroller(f, 66)
	task.spawn(function()
		local v = call("cop", { act = "view" })
		local view = v.view or {}
		copView = view
		local rankLine = string.format("%s · XP %d%s · 평판 %d", tostring(view.title or "순경"), view.xp or 0, if view.nextXp then " / " .. view.nextXp .. " (" .. tostring(view.nextTitle) .. ")" else "", view.rep or 60)
		if view.locked then
			rankLine ..= " · ⛔ 체포 제한 " .. LS.fmtTime(view.lockLeft or 0)
		end
		if not view.pass then
			info.Text = "경찰 직업 패스가 필요해요."
			return
		end
		info.Text = rankLine .. (if view.on then "\n근무 중 · 오늘 " .. LS.won(view.earned or 0) else "\n광안지구대 입구에서 근무를 시작할 수 있어요")
		head.Text = if view.on then "👮 근무 중 — " .. tostring(view.title) else "👮 광안지구대"
		local r0 = row(body, 44, 1)
		hlist(r0, 8)
		local dutyB = button(r0, if view.on then "근무 종료" else "근무 시작", if view.on then Color3.fromRGB(110, 40, 50) else Color3.fromRGB(30, 90, 60), function()
			local r = call("cop", { act = "duty", on = not view.on })
			if r.text then
				toast(r.text, if r.ok then "good" else "warn")
			end
			f:Destroy()
			if r.ok then
				task.delay(0.3, openPolice)
			end
		end)
		dutyB.Size = UDim2.fromOffset(140, 40)
		if not view.on then
			return
		end
		copToolRow(body, 2)
		local board = call("cop", { act = "board" })
		label(body, { Size = UDim2.new(1, 0, 0, 20), Text = "📋 신고 목록", Font = Enum.Font.GothamBold, LayoutOrder = 3 })
		local n = 0
		for i, c in (board.calls or {}) do
			n += 1
			local rr = row(body, 40, 3 + i)
			local t = label(rr, { Size = UDim2.new(1, -110, 1, 0), Text = string.format("%s %s · %s · %d초 전%s", c.icon or "🚨", c.label or "", c.area or "", c.ago or 0, if c.suspect then " · " .. c.suspect else ""), TextSize = 13 })
			local _ = t
			if c.pos then
				local b = button(rr, "📍 출동", Color3.fromRGB(40, 70, 130), function()
					setMarker("cop", c.pos, c.label)
					toast("📍 " .. tostring(c.area) .. "로 출동!", "good")
				end)
				b.AnchorPoint = Vector2.new(1, 0.5)
				b.Position = UDim2.new(1, 0, 0.5, 0)
				b.Size = UDim2.fromOffset(100, 34)
			end
		end
		if n == 0 then
			label(body, { Size = UDim2.new(1, 0, 0, 18), Text = "조용한 밤이에요… (새 신고 없음)", TextSize = 13, TextColor3 = SUB, LayoutOrder = 4 })
		end
		label(body, { Size = UDim2.new(1, 0, 0, 20), Text = "🚨 수배자", Font = Enum.Font.GothamBold, LayoutOrder = 50 })
		local m = 0
		for i, w in (board.wanted or {}) do
			m += 1
			local rr = row(body, 40, 50 + i)
			label(rr, { Size = UDim2.new(1, -110, 1, 0), Text = string.format("%s %s · 마지막 목격: %s%s", if w.warrant then "📄 수배 기록" else LS.stars(w.stars), w.name, w.area or "?", if w.seenAgo then " (" .. w.seenAgo .. "초 전)" else ""), TextSize = 13 })
			local b = button(rr, "🎯 추적", Color3.fromRGB(110, 50, 40), function()
				local r = call("cop", { act = "track", userId = w.userId })
				toast(if r.ok then "🎯 마지막 목격 위치: " .. tostring(r.area) else (r.text or "위치를 모르겠어요"), if r.ok then "good" else "warn")
			end)
			b.AnchorPoint = Vector2.new(1, 0.5)
			b.Position = UDim2.new(1, 0, 0.5, 0)
			b.Size = UDim2.fromOffset(100, 34)
		end
		if m == 0 then
			label(body, { Size = UDim2.new(1, 0, 0, 18), Text = "현재 수배자 없음", TextSize = 13, TextColor3 = SUB, LayoutOrder = 51 })
		end
	end)
end

-- context buttons for cops near a target (수갑 / 범칙금 / 검거)
local ctxHolder = new("Frame", { Name = "LawContext", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -150, 1, -150), Size = UDim2.fromOffset(170, 160), BackgroundTransparency = 1 }, gui)
new("UIListLayout", { Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Bottom, SortOrder = Enum.SortOrder.LayoutOrder }, ctxHolder)
local ctxButtons: { [string]: TextButton } = {}
local function ctxButton(key: string, text: string, color: Color3, order: number, onClick: () -> ()): TextButton
	local b = ctxButtons[key]
	if not b then
		b = button(ctxHolder, text, color, onClick)
		b.Size = UDim2.fromOffset(170, 46)
		b.LayoutOrder = order
		ctxButtons[key] = b
	end
	b.Text = text
	b.Visible = true
	return b
end
local function hideCtx(key: string)
	local b = ctxButtons[key]
	if b then
		b.Visible = false
	end
end

local ctxTarget: any = {}
task.spawn(function()
	while true do
		task.wait(0.3)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local onDuty = player:GetAttribute(A.Cop) == true
		if not root or not onDuty then
			hideCtx("cuff")
			hideCtx("ticket")
			hideCtx("npc")
		else
			-- the nearest other player within reach
			local best, bd = nil, LS.CUFF_RANGE
			for _, p in Players:GetPlayers() do
				if p ~= player then
					local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
					if r then
						local d = (r.Position - root.Position).Magnitude
						if d < bd then
							best, bd = p, d
						end
					end
				end
			end
			ctxTarget.player = best
			if best then
				local stars = best:GetAttribute(A.Wanted) or 0
				ctxButton("cuff", "🔗 수갑 · " .. best.DisplayName .. (if stars > 0 then " " .. string.rep("★", stars) else ""), Color3.fromRGB(110, 40, 50), 1, function()
					local t = ctxTarget.player
					if t then
						local r = call("cop", { act = "cuff", userId = t.UserId })
						toast(if r.ok then "🔗 체포! 지구대로 호송하세요 (" .. tostring(r.reason) .. ")" else (r.text or "체포할 수 없어요"), if r.ok then "good" else "warn")
					end
				end)
				if stars == 1 then
					ctxButton("ticket", "🧾 범칙금 발부", Color3.fromRGB(70, 70, 30), 2, function()
						local t = ctxTarget.player
						if t then
							local r = call("cop", { act = "ticket", userId = t.UserId })
							toast(if r.ok then "🧾 범칙금 발부 완료" else (r.text or "안 돼요"), if r.ok then "good" else "warn")
						end
					end)
				else
					hideCtx("ticket")
				end
			else
				hideCtx("cuff")
				hideCtx("ticket")
			end
			-- an NPC incident suspect
			local npcs = workspace:FindFirstChild("GwangalliNPCs")
			local sBest, sd = nil, LS.CUFF_RANGE
			if npcs then
				for _, m in npcs:GetChildren() do
					local sid = m:GetAttribute("LawSuspect")
					if sid then
						local r = m:FindFirstChild("HumanoidRootPart") :: BasePart?
						if r then
							local d = (r.Position - root.Position).Magnitude
							if d < sd then
								sBest, sd = sid, d
							end
						end
					end
				end
			end
			ctxTarget.npc = sBest
			if sBest then
				ctxButton("npc", "🔗 용의자 검거", Color3.fromRGB(110, 40, 50), 3, function()
					local id = ctxTarget.npc
					if id then
						local r = call("cop", { act = "cuffNpc", id = id })
						toast(if r.ok then "🔗 검거 성공! (" .. tostring(r.label) .. ")" else (r.text or "안 돼요"), if r.ok then "good" else "warn")
					end
				end)
			else
				hideCtx("npc")
			end
		end
	end
end)

-------------------------------------------------------------------------------------------------
-- Crime panel + pickpocket + live job
-------------------------------------------------------------------------------------------------
local openCrime: () -> ()

local function bigMenu(data: any)
	local f = modal("LawBig", 540, 460)
	closeBtn(f)
	label(f, { Size = UDim2.new(1, -40, 0, 26), Text = "🕶️ 조직 임무 — 행동대장", Font = Enum.Font.GothamBlack, TextSize = 19 })
	label(f, { Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 34), Text = string.format("범죄 등급 Lv.%d %s · XP %d%s · 조직 신뢰 %d\n준비가 길고 실패하면 손해가 커요. 대신 크게 벌어요.", data.level or 1, tostring(data.title or ""), data.xp or 0, if data.nextXp then " / " .. data.nextXp else "", data.trust or 0), TextSize = 12, TextColor3 = SUB, TextYAlignment = Enum.TextYAlignment.Top })
	local body = scroller(f, 68)
	if data.live then
		local rr = row(body, 44, 0)
		label(rr, { Size = UDim2.new(1, -110, 1, 0), Text = string.format("진행 중: %s %s (%d/%d) — %s", data.live.icon, data.live.label, data.live.step, data.live.steps, data.live.stepLabel), TextSize = 13 })
		local q = button(rr, "포기", Color3.fromRGB(110, 40, 50), function()
			call("crime", { act = "bigQuit" })
			f:Destroy()
		end)
		q.AnchorPoint = Vector2.new(1, 0.5)
		q.Position = UDim2.new(1, 0, 0.5, 0)
		q.Size = UDim2.fromOffset(90, 34)
	end
	for i, b in (data.list or {}) do
		local card = new("Frame", { Size = UDim2.new(1, 0, 0, 92), BackgroundColor3 = Color3.fromRGB(28, 34, 64), LayoutOrder = i }, body)
		corner(card, 12)
		pad(card, 10, 8)
		label(card, { Size = UDim2.new(1, -110, 0, 20), Text = b.icon .. " " .. b.label .. string.format("  <font color='#ffd054'>%s~%s</font>", LS.won(b.reward[1]), LS.won(b.reward[2])), Font = Enum.Font.GothamBold, TextSize = 14 })
		label(card, { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, -110, 0, 52), Text = table.concat(b.steps, " → ") .. (if b.open then "" else "\n🔒 " .. tostring(b.why)), TextSize = 12, TextColor3 = SUB, TextYAlignment = Enum.TextYAlignment.Top })
		local go = button(card, if b.open then "시작" else "잠김", if b.open then Color3.fromRGB(110, 60, 140) else Color3.fromRGB(50, 50, 60), function()
			if not b.open then
				return
			end
			local r = call("crime", { act = "bigStart", id = b.id })
			toast(if r.ok then "🕶️ " .. b.label .. " 시작" else (r.text or "지금은 안 돼요"), if r.ok then "crime" else "warn")
			if r.ok then
				f:Destroy()
			end
		end)
		go.AnchorPoint = Vector2.new(1, 0.5)
		go.Position = UDim2.new(1, 0, 0.5, 0)
		go.Size = UDim2.fromOffset(96, 40)
	end
end

openCrime = function()
	local f = modal("LawCrime", 520, 440)
	closeBtn(f)
	label(f, { Size = UDim2.new(1, -40, 0, 26), Text = "🕶️ 뒷골목", Font = Enum.Font.GothamBlack, TextSize = 20 })
	local info = label(f, { Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 34), Text = "", TextSize = 12, TextColor3 = SUB, TextYAlignment = Enum.TextYAlignment.Top })
	local body = scroller(f, 66)
	task.spawn(function()
		local st = call("state").state or {}
		info.Text = string.format("범죄 등급 Lv.%d %s · XP %d%s · 전과 %d범%s\n알바보다 빨리 벌지만, 잡히면 벌금 + 압수 + 유치장이에요.", st.crimeLevel or 1, tostring(st.crimeTitle or ""), st.crimeXp or 0, if st.crimeNext then " / " .. st.crimeNext .. " (" .. tostring(st.crimeNextTitle) .. ")" else "", st.record or 0, if (st.debt or 0) > 0 then " · 미납 벌금 " .. LS.won(st.debt) else "")
		local list = call("crime", { act = "list" })
		for i, c in (list.list or {}) do
			local rr = row(body, 46, i)
			label(rr, { Size = UDim2.new(1, -10, 1, 0), Text = string.format("%s <b>%s</b>  %s%s\n<font color='#a0acd0'>%s</font>", c.icon, c.label, if c.pay and c.pay[2] > 0 then LS.won(c.pay[1]) .. "~" .. LS.won(c.pay[2]) else "", if not c.open then "  🔒 Lv." .. c.level elseif (c.cool or 0) > 0 then "  ⏳ " .. c.cool .. "초" else "", c.risk), TextSize = 13 })
		end
		local hint = label(body, { Size = UDim2.new(1, 0, 0, 60), Text = "💡 편의점: 매장 안에서 [G] 슬쩍하기 / [H] 털기 · 소매치기: 행인 뒤에서 👛 버튼 · 불법 배달: 뒷골목 수상한 남자 · 훔친 차: 광안 공영주차장 폐차장 · 조직 임무: 민락항 아지트의 행동대장", TextSize = 12, TextColor3 = SUB, LayoutOrder = 99 })
		local _ = hint
		local b = button(body, "🕶️ 조직 임무 보기", Color3.fromRGB(80, 50, 120), function()
			local data = call("crime", { act = "bigList" })
			f:Destroy()
			bigMenu(data)
		end)
		b.LayoutOrder = 100
		b.Size = UDim2.new(1, 0, 0, 40)
	end)
end

dockBtn("👮\n경찰", 1, function()
	openPolice()
end)
dockBtn("🕶️\n뒷골목", 2, function()
	openCrime()
end)

-- live organised job tracker
local bigCard = new("Frame", { Name = "LawBigTracker", Position = UDim2.new(0, 80, 0, 436), Size = UDim2.fromOffset(300, 58), BackgroundColor3 = Color3.fromRGB(40, 24, 70), BackgroundTransparency = 0.1, Visible = false }, gui)
corner(bigCard, 12)
pad(bigCard, 10, 6)
local bigText = label(bigCard, { Size = UDim2.fromScale(1, 1), Text = "", TextSize = 13 })
local function showBig(st: any, text: string?)
	bigState = st
	if not st then
		bigCard.Visible = false
		setMarker("big", nil)
		if text then
			toast("🕶️ " .. text, "crime")
		end
		return
	end
	bigCard.Visible = true
	bigText.Text = string.format("%s <b>%s</b> %d/%d\n%s%s%s", st.icon, st.label, st.step, st.steps, st.stepLabel, if st.need then string.format(" (%d/%d)", st.n or 0, st.need) else "", if st.timer then " · ⏱ " .. LS.fmtTime(st.timer) else "")
	setMarker("big", st.pos, st.stepLabel, Color3.fromRGB(90, 40, 130))
	if text then
		toast("🕶️ " .. text, "crime")
	end
end

-- 👛 pickpocket button
local pickBtn = button(gui, "👛 소매치기 (T)", Color3.fromRGB(80, 40, 110), function() end)
pickBtn.AnchorPoint = Vector2.new(1, 1)
pickBtn.Position = UDim2.new(1, -150, 1, -100)
pickBtn.Size = UDim2.fromOffset(170, 46)
pickBtn.Visible = false
local pickTarget: any = nil
local function doPick()
	local t = pickTarget
	if not t then
		return
	end
	pickBtn.Visible = false
	local r = call("crime", { act = "pickpocket", id = t.id, arch = t.arch, pos = { t.x, t.y, t.z } })
	if r.ok and r.success then
		toast("👛 슬쩍! +" .. LS.won(r.money or 0), "crime")
	elseif r.ok then
		toast("😱 \"" .. tostring(r.line or "도둑이야!") .. "\"", "warn")
	elseif r.text then
		toast(r.text, "warn")
	end
end
pickBtn.Activated:Connect(doPick)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or UserInputService:GetFocusedTextBox() then
		return
	end
	if input.KeyCode == Enum.KeyCode.T and pickBtn.Visible then
		doPick()
	end
end)
task.spawn(function()
	local api: BindableFunction? = nil
	while true do
		task.wait(0.3)
		if not api or not api.Parent then
			local f = player:FindFirstChild("GwangalliMindAPI")
			api = if f and f:IsA("BindableFunction") then f else nil
		end
		local show = false
		local blockedNow = player:GetAttribute(A.Cop) == true or (player:GetAttribute(A.Jail) or 0) > 0 or player:GetAttribute(A.Cuffed) == true
		if api and not blockedNow then
			local ok, n = pcall(function()
				return (api :: BindableFunction):Invoke("nearest", 3.4)
			end)
			if ok and type(n) == "table" and n.behind and not n.talking then
				pickTarget = n
				show = true
			end
		end
		pickBtn.Visible = show
	end
end)

-- crime prompts are not for cops on duty (local only)
task.spawn(function()
	while true do
		task.wait(1.5)
		local cop = player:GetAttribute(A.Cop) == true
		local props = workspace:FindFirstChild("GwangalliLawProps")
		if props then
			for _, d in props:GetDescendants() do
				if d:IsA("ProximityPrompt") and d:GetAttribute("LawCrime") then
					d.Enabled = not cop
				end
			end
		end
	end
end)

-------------------------------------------------------------------------------------------------
-- Cuffs pose (arms behind the back while LawCuffed)
-------------------------------------------------------------------------------------------------
local CUFF_R = CFrame.Angles(math.rad(-32), 0, math.rad(-20))
local CUFF_L = CFrame.Angles(math.rad(-32), 0, math.rad(20))
local function cuffPose()
	if player:GetAttribute(A.Cuffed) ~= true then
		return
	end
	local ch = player.Character
	if not ch then
		return
	end
	local ru = ch:FindFirstChild("RightUpperArm")
	local lu = ch:FindFirstChild("LeftUpperArm")
	local rs = ru and ru:FindFirstChild("RightShoulder")
	local lsh = lu and lu:FindFirstChild("LeftShoulder")
	if rs and rs:IsA("Motor6D") then
		rs.Transform = CUFF_R
	end
	if lsh and lsh:IsA("Motor6D") then
		lsh.Transform = CUFF_L
	end
end
RunService.Stepped:Connect(cuffPose)
RunService.RenderStepped:Connect(cuffPose)

-------------------------------------------------------------------------------------------------
-- Server events
-------------------------------------------------------------------------------------------------
Event.OnClientEvent:Connect(function(msg: any)
	if type(msg) ~= "table" then
		return
	end
	local k = msg.kind
	if k == "state" then
		state = msg
		if msg.big then
			showBig(msg.big, nil)
		end
	elseif k == "wanted" then
		refreshWanted()
		if (msg.stars or 0) > (msg.before or 0) then
			toast("🚨 수배 " .. LS.stars(msg.stars) .. " · " .. tostring(msg.tier or ""), "warn")
		end
	elseif k == "reported" then
		toast("📞 " .. tostring(msg.label) .. " 신고가 접수됐어요 (" .. tostring(msg.area) .. ")", "warn")
	elseif k == "radio" then
		showRadio(msg.text or "")
	elseif k == "seen" then
		refreshWanted()
	elseif k == "escaped" then
		toast("😎 경찰을 따돌렸어요!", "good")
	elseif k == "stop" then
		showStop(msg)
	elseif k == "stopEnd" then
		local f = gui:FindFirstChild("LawStop")
		if f then
			f:Destroy()
		end
	elseif k == "ticket" then
		toast("🧾 범칙금 " .. LS.won(msg.fine or 0) .. (if (msg.owed or 0) > 0 then " (미납 " .. LS.won(msg.owed) .. ")" else ""), "warn")
	elseif k == "arrest" then
		showArrest(msg)
	elseif k == "jail" then
		jailView = msg.state
		openJail(msg.state or {})
		updateJail()
		if msg.toast then
			toast(msg.toast, "good")
		end
	elseif k == "jailGame" then
		playGonggi(msg)
	elseif k == "cellChat" then
		cellChatLine("💬 " .. tostring(msg.from) .. ": " .. tostring(msg.text))
	elseif k == "release" then
		closeJail()
		toast(if msg.why == "bail" then "💸 보석으로 풀려났어요" else "🚪 출소! 착하게 삽시다", "good")
	elseif k == "toast" then
		toast(msg.text or "", msg.tone)
	elseif k == "crimeLevel" then
		toast("🕶️ 범죄 등급 Lv." .. tostring(msg.level) .. " " .. tostring(msg.title), "crime")
	elseif k == "crimeDone" then
		-- (the toast came with it)
	elseif k == "mission" then
		if msg.done then
			setMarker("mission", nil)
		else
			setMarker("mission", msg.pos, msg.text, Color3.fromRGB(70, 40, 30))
			toast(msg.text or "", "crime")
		end
	elseif k == "big" then
		showBig(msg.state, msg.text)
	elseif k == "bigMenu" then
		bigMenu(msg.data or {})
	elseif k == "cop" then
		if msg.ev == "waypoint" then
			setMarker("cop", msg.pos, msg.label, Color3.fromRGB(30, 60, 140))
		elseif msg.ev == "call" and msg.call then
			toast("📻 신고: " .. tostring(msg.call.label) .. " · " .. tostring(msg.call.area), nil)
		elseif msg.ev == "pay" then
			toast("👮 " .. tostring(msg.label) .. " +" .. LS.won(msg.amount or 0) .. " · XP +" .. tostring(msg.xp or 0), "good")
		elseif msg.ev == "rank" then
			toast("🎖️ 진급: " .. tostring(msg.title), "good")
		elseif msg.ev == "duty" then
			copView = msg.view
			if not msg.on then
				setMarker("cop", nil)
			end
		elseif msg.ev == "patrolDone" then
			setMarker("cop", nil)
			toast("✅ 순찰 완료!", "good")
		elseif msg.ev == "escort" then
			toast("🔗 " .. tostring(msg.name) .. " 호송 중 · 광안지구대로", "good")
		end
	end
end)

task.spawn(function()
	local r = call("state")
	if r.ok and r.state then
		state = r.state
		if r.state.big then
			showBig(r.state.big, nil)
		end
	end
end)

-- test hook (only with workspace.GwangalliStreetLifeDebug): LocalPlayer.GwangalliLawAPI
do
	local api = Instance.new("BindableFunction")
	api.Name = "GwangalliLawAPI"
	local queue: { () -> () } = {}
	local last: any = nil
	api.OnInvoke = function(method: string, op: string?, payload: any?): any
		if workspace:GetAttribute("GwangalliStreetLifeDebug") ~= true then
			return nil
		end
		if method == "last" then
			return last
		elseif method == "ui" then
			local out = {}
			for _, c in gui:GetChildren() do
				if c:IsA("GuiObject") and c.Visible then
					table.insert(out, c.Name)
				end
			end
			return table.concat(out, ",")
		end
		table.insert(queue, function()
			if method == "call" and op then
				last = call(op, payload)
			elseif method == "open" then
				if op == "police" then
					openPolice()
				else
					openCrime()
				end
			end
		end)
		return true
	end
	api.Parent = player
	task.spawn(function()
		while api.Parent do
			task.wait(0.25)
			while #queue > 0 do
				task.spawn(table.remove(queue, 1))
			end
		end
	end)
end
