-- GwangalliProgress/Panel: the progress sheet (right side sheet on landscape / tablet / PC, bottom sheet
-- on portrait phones). Header = 인생 레벨 ring + title + progress to the next level; tabs:
--   목표  today's 3 goals (progress, reward, 🔄 reroll from Lv2), 올클리어 bonus, the weekly goal
--   업적  badge wall by category (tier medals, progress for locked ones, tap = details)
--   레벨  unlock ladder (what each 인생 레벨 opens) + how far the next level is
--   정산  today's 번 돈 / 쓴 돈 / 남은 돈, 7-day chart, category breakdown, records
-- Built from the GwangalliUI kit (BottomSheet, Segmented, ProgressBar, Ring, iconTile). While open it
-- carries HideGwangalliHUD (the HUD steps aside) and the touch controls are off (restored on close).

local UserInputService = game:GetService("UserInputService")

local Panel = {}

local C: any = nil
local K: any = nil
local P: any = nil

local sheet: any = nil
local sheetSide = ""
local host: Frame
local tabs: any = nil
local scroll: ScrollingFrame
local header: Frame
local tab = "goals"
local openState = false
local controlsOff = false
local selectedAch: string? = nil
local rerollBusy = false

local TAB_ITEMS = {
	{ id = "goals", label = "목표" },
	{ id = "ach", label = "업적" },
	{ id = "level", label = "레벨" },
	{ id = "pay", label = "정산" },
}

-------------------------------------------------------------------------------------------------
-- Controls / modal
-------------------------------------------------------------------------------------------------
local function setControls(enabled: boolean)
	local ps = C.player:FindFirstChild("PlayerScripts")
	local pm = ps and ps:FindFirstChild("PlayerModule")
	if not (pm and pm:IsA("ModuleScript")) then
		return
	end
	pcall(function()
		local mod = require(pm) :: any
		local controls = mod:GetControls()
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end)
end

local function setModal(on: boolean)
	C.panelGui:SetAttribute("HideGwangalliHUD", on)
	if on and UserInputService.TouchEnabled then
		controlsOff = true
		setControls(false)
	elseif not on and controlsOff then
		controlsOff = false
		setControls(true)
	end
end

-------------------------------------------------------------------------------------------------
-- Small builders
-------------------------------------------------------------------------------------------------
local function txt(parent: Instance, props: { [string]: any }): TextLabel
	local p = table.clone(props)
	p.ZIndex = p.ZIndex or 45
	return K.text(parent, p)
end

local function section(parent: Instance, title: string, order: number, right: string?): Frame
	local f = K.frame(parent, { Name = "Section_" .. order, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = order, ZIndex = 45 })
	txt(f, { Name = "Title", Size = UDim2.new(0.6, 0, 1, 0), Text = title, Font = K.Font.bold, TextSize = 14 })
	if right then
		txt(f, { Name = "Right", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.4, 0, 1, 0), Text = right, TextSize = 11, TextColor3 = K.Color.faint, TextXAlignment = Enum.TextXAlignment.Right })
	end
	return f
end

local function card(parent: Instance, name: string, h: number, order: number, stroke: Color3?): Frame
	local f = K.frame(parent, { Name = name, Size = UDim2.new(1, 0, 0, h), BackgroundTransparency = 0, BackgroundColor3 = K.Color.card, LayoutOrder = order, ZIndex = 45 })
	K.corner(f, K.Radius.md)
	K.stroke(f, stroke or K.Color.line, 1, if stroke then 0.55 else 0.92)
	return f
end

local function tierColor(tier: string?): Color3
	local t = tier and P.TIERS[tier]
	if not t then
		return K.Color.gold
	end
	return Color3.fromRGB(t.color[1], t.color[2], t.color[3])
end

local function clearScroll()
	for _, ch in scroll:GetChildren() do
		if not ch:IsA("UIListLayout") and not ch:IsA("UIPadding") then
			ch:Destroy()
		end
	end
	scroll.CanvasPosition = Vector2.zero
end

local function resetIn(): string
	local t = os.time()
	local left = 86400 - ((t + 9 * 3600) % 86400)
	local h = left // 3600
	local m = (left % 3600) // 60
	if h > 0 then
		return string.format("초기화까지 %d시간 %d분", h, m)
	end
	return string.format("초기화까지 %d분", math.max(1, m))
end

local function progressText(g: any): string
	if g.money then
		return string.format("%s / %s", P.wonShort(g.have or 0), P.wonShort(g.n or 0))
	end
	return string.format("%d / %d", math.floor(g.have or 0), math.floor(g.n or 0))
end

-------------------------------------------------------------------------------------------------
-- Header
-------------------------------------------------------------------------------------------------
local function renderHeader()
	for _, ch in header:GetChildren() do
		ch:Destroy()
	end
	local s = C.snap
	local lv = if s then s.level else (C.player:GetAttribute(P.Attr.Level) or 1)
	local ring = K.Ring(header, { name = "Ring", size = 52, thickness = 4, color = K.Color.gold, text = tostring(lv) })
	ring.frame.Position = UDim2.fromOffset(0, 2)
	ring.label.Font = K.Font.heavy
	ring.label.TextSize = 18
	for _, d in ring.frame:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 46
		end
	end
	ring.set(0)
	task.defer(function()
		ring.set(if s then (s.lp or 0) else 0)
	end)
	local title = if s then s.title else P.titleFor(lv)
	txt(header, { Name = "Level", Position = UDim2.fromOffset(62, 2), Size = UDim2.new(1, -62, 0, 18), Text = string.format("인생 레벨 %d", lv), TextSize = 12, TextColor3 = K.Color.gold, Font = K.Font.bold })
	txt(header, { Name = "Title", Position = UDim2.fromOffset(62, 19), Size = UDim2.new(1, -62, 0, 22), Text = title, TextSize = 18, Font = K.Font.heavy, TextTruncate = Enum.TextTruncate.AtEnd })
	local sub = "누적 수입 " .. K.won(s and s.earned or 0)
	if s and s.nextAt then
		sub ..= string.format(" · 다음 레벨까지 %s", P.wonShort(math.max(0, s.nextAt - s.earned)))
	elseif s then
		sub ..= " · 최고 레벨!"
	end
	txt(header, { Name = "Sub", Position = UDim2.fromOffset(62, 41), Size = UDim2.new(1, -62, 0, 14), Text = sub, TextSize = 11, TextColor3 = K.Color.sub, TextTruncate = Enum.TextTruncate.AtEnd })
end

-------------------------------------------------------------------------------------------------
-- 목표
-------------------------------------------------------------------------------------------------
local renderTab: (string) -> ()

local function doReroll(index: number)
	if rerollBusy then
		return
	end
	rerollBusy = true
	task.spawn(function()
		local res = C.request("reroll", { index = index })
		rerollBusy = false
		if type(res) == "table" and res.ok then
			K.feedback("success")
			if C.snap then
				C.snap.goals = res.goals or C.snap.goals
				C.snap.rerolls = res.rerolls or C.snap.rerolls
			end
			if openState and tab == "goals" then
				renderTab("goals")
			end
		else
			K.feedback("error")
			K.toast({ kind = "warn", title = "목표 새로고침", body = (type(res) == "table" and res.message) or "잠시 후 다시 해 주세요" })
		end
	end)
end

local function goalCard(parent: Instance, g: any, index: number, order: number, weekly: boolean, canReroll: boolean)
	local accent = if weekly then K.Color.violet elseif g.done then K.Color.green else K.Color.cyan
	local f = card(parent, "Goal" .. index, 82, order, if g.done then K.Color.green else (if weekly then K.Color.violet else nil))
	local icon = K.iconTile(f, 40, tostring(g.icon or "🎯"), accent, false)
	icon.Position = UDim2.fromOffset(12, 12)
	for _, d in icon:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 46
		end
	end
	icon.ZIndex = 46
	local rightW = if canReroll and not g.done then 64 else 12
	txt(f, { Name = "Text", Position = UDim2.fromOffset(62, 10), Size = UDim2.new(1, -(62 + rightW), 0, 18), Text = tostring(g.text or ""), Font = K.Font.bold, TextSize = 14, TextTruncate = Enum.TextTruncate.AtEnd, TextColor3 = if g.done then K.Color.sub else K.Color.text })
	local rewardText = "+" .. K.won(g.cash or 0)
	if (tonumber(g.pop) or 0) > 0 then
		rewardText ..= string.format(" · 인기 +%d", g.pop)
	end
	if g.live == false then
		rewardText = "🔒 곧 열려요 · " .. rewardText
	end
	local rw = txt(f, { Name = "Reward", Position = UDim2.fromOffset(62, 29), Size = UDim2.new(1, -(62 + rightW), 0, 14), Text = rewardText, TextSize = 11, TextColor3 = if g.done then K.Color.faint else K.Color.gold })
	K.mono(rw)
	local bar = K.ProgressBar(f, { height = 8, color = accent })
	bar.frame.Position = UDim2.fromOffset(62, 52)
	bar.frame.Size = UDim2.new(1, -(62 + rightW + 56), 0, 8)
	bar.frame.ZIndex = 46
	bar.fill.ZIndex = 46
	bar.set(0, true)
	local p = if (g.n or 0) > 0 then math.clamp((g.have or 0) / g.n, 0, 1) else 0
	task.delay(0.05 + order * 0.04, function()
		bar.set(p)
	end)
	local pt = txt(f, { Name = "Progress", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -(rightW + 2), 0, 46), Size = UDim2.fromOffset(54, 20), Text = if g.done then "달성!" else progressText(g), TextSize = 11, Font = K.Font.bold, TextColor3 = if g.done then K.Color.green else K.Color.sub, TextXAlignment = Enum.TextXAlignment.Right })
	K.mono(pt)
	if g.done then
		local check = K.frame(f, { Name = "Done", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(52, 14), Size = UDim2.fromOffset(18, 18), BackgroundTransparency = 0, BackgroundColor3 = K.Color.green, ZIndex = 47 })
		K.corner(check, UDim.new(0.5, 0))
		txt(check, { Name = "Mark", Size = UDim2.fromScale(1, 1), Text = "✓", TextSize = 12, Font = K.Font.heavy, TextColor3 = K.Color.onAccent, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 48 })
	end
	if canReroll and not g.done then
		local b = K.Button(f, { name = "Reroll" .. index, style = "secondary", text = "🔄", size = UDim2.fromOffset(56, 56), anchor = Vector2.new(1, 0.5), position = UDim2.new(1, -6, 0.5, 0), zIndex = 47, textSize = 18, radius = 14 })
		b.Activated:Connect(function()
			doReroll(index)
		end)
	end
end

local function renderGoals()
	local s = C.snap
	if not s then
		txt(scroll, { Name = "Loading", Size = UDim2.new(1, 0, 0, 40), Text = "불러오는 중…", TextColor3 = K.Color.sub, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1 })
		return
	end
	local re = s.rerolls or { used = 0, max = 0 }
	local canReroll = (re.max or 0) > (re.used or 0)
	section(scroll, "🎯 오늘의 목표", 1, resetIn())
	local done = 0
	for i, g in s.goals or {} do
		goalCard(scroll, g, i, 1 + i, false, canReroll)
		if g.done then
			done += 1
		end
	end
	-- 올클리어 row
	local row = card(scroll, "AllClear", 44, 10, if s.allDone then K.Color.gold else nil)
	local bonus = math.floor(P.ALL_DONE.cash * (P.BAND_CASH[P.band(s.level or 1)] or 1) / 100 + 0.5) * 100
	txt(row, { Name = "Text", Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -90, 1, 0), Text = if s.allDone then "🎉 오늘 올클리어 완료!" else string.format("3개 모두 달성하면 보너스 +%s", K.won(bonus)), TextSize = 12, Font = K.Font.bold, TextColor3 = if s.allDone then K.Color.gold else K.Color.sub })
	local dotsF = K.frame(row, { Name = "Dots", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(60, 12), ZIndex = 46 })
	K.list(dotsF, true, 6, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	for i = 1, P.DAILY_COUNT do
		local d = K.frame(dotsF, { Name = "Dot" .. i, Size = UDim2.fromOffset(12, 12), BackgroundTransparency = 0, BackgroundColor3 = if i <= done then K.Color.green else K.Color.card3, LayoutOrder = i, ZIndex = 46 })
		K.corner(d, UDim.new(0.5, 0))
	end
	if canReroll then
		txt(scroll, { Name = "RerollHint", Size = UDim2.new(1, 0, 0, 14), Text = string.format("🔄 목표 새로고침 %d번 남음", (re.max or 0) - (re.used or 0)), TextSize = 11, TextColor3 = K.Color.faint, LayoutOrder = 11 })
	elseif (s.level or 1) < 2 then
		txt(scroll, { Name = "RerollHint", Size = UDim2.new(1, 0, 0, 14), Text = "인생 레벨 2부터 목표를 바꿀 수 있어요", TextSize = 11, TextColor3 = K.Color.faint, LayoutOrder = 11 })
	end
	section(scroll, "🗓️ 이번 주 목표", 20, "월요일 초기화")
	if s.weekly then
		goalCard(scroll, s.weekly, 9, 21, true, false)
	end
	local st = s.stats or {}
	txt(scroll, { Name = "Totals", Size = UDim2.new(1, 0, 0, 30), Text = string.format("지금까지 일일 목표 %d개 · 주간 목표 %d번 달성", st.goalsDone or 0, st.weeklyDone or 0), TextSize = 11, TextColor3 = K.Color.faint, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 30 })
end

-------------------------------------------------------------------------------------------------
-- 업적
-------------------------------------------------------------------------------------------------
local detailLabel: TextLabel? = nil

local function showDetail(a: any)
	selectedAch = a.id
	local dl = detailLabel
	if not dl then
		return
	end
	local tier = P.TIERS[a.tier]
	local state = if a.done then "✅ 달성" elseif a.live == false then "🔒 준비 중인 콘텐츠" else string.format("진행 %s / %s", if a.n >= 10000 then P.wonShort(a.have) else tostring(math.floor(a.have)), if a.n >= 10000 then P.wonShort(a.n) else tostring(a.n))
	dl.Text = string.format("%s %s (%s) — %s\n%s · 보상 %s · 인기 +%d", tostring(a.icon or ""), tostring(a.name or ""), tier and tier.name or "", tostring(a.desc or ""), state, K.won(tier and tier.cash or 0), tier and tier.pop or 0)
	dl.TextColor3 = if a.done then K.Color.text else K.Color.sub
	K.sheen(dl.Parent :: GuiObject, { duration = 0.6, strength = 0.7 })
end

local function badge(parent: Instance, a: any, order: number)
	local b = K.make("TextButton", { Name = "Badge_" .. a.id, Size = UDim2.fromOffset(72, 92), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, LayoutOrder = order, ZIndex = 45 }, parent)
	local col = tierColor(a.tier)
	local medal = K.frame(b, { Name = "Medal", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.fromOffset(50, 50), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 46 })
	K.corner(medal, UDim.new(0.5, 0))
	if a.done then
		K.gradient(medal, { col:Lerp(Color3.new(1, 1, 1), 0.3), col:Lerp(Color3.new(0, 0, 0), 0.35) }, 125)
		K.stroke(medal, Color3.new(1, 1, 1), 1.5, 0.5)
	else
		medal.BackgroundColor3 = K.Color.card2
		K.stroke(medal, col, 1.5, 0.6)
	end
	local glyph = txt(medal, { Name = "Glyph", Size = UDim2.fromScale(1, 1), Text = tostring(a.icon or "🏅"), TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 47 })
	if not a.done then
		glyph.TextTransparency = 0.55
		local p = if (a.n or 0) > 0 then math.clamp((a.have or 0) / a.n, 0, 1) else 0
		if p > 0 and a.live ~= false then
			local r = K.Ring(medal, { name = "Prog", size = 50, thickness = 3, color = col })
			for _, d in r.frame:GetDescendants() do
				if d:IsA("GuiObject") then
					d.ZIndex = 47
				end
			end
			r.set(p)
		end
		if a.live == false then
			txt(medal, { Name = "Lock", AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(18, 18), Text = "🔒", TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 48 })
		end
	end
	txt(b, { Name = "Name", Position = UDim2.fromOffset(0, 58), Size = UDim2.new(1, 0, 0, 30), Text = tostring(a.name or ""), TextSize = 11, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextXAlignment = Enum.TextXAlignment.Center, Font = if a.done then K.Font.bold else K.Font.medium, TextColor3 = if a.done then K.Color.text else K.Color.faint })
	K.pressable(b, { scale = 0.93, veil = false })
	b.Activated:Connect(function()
		showDetail(a)
	end)
end

-- usable width of the scroll content (the sheet's own width minus its padding)
local function innerWidth(): number
	if scroll and scroll.AbsoluteSize.X > 40 then
		return scroll.AbsoluteSize.X - 6
	end
	if sheetSide == "right" then
		return math.max(300, C.Layout.rect("sheetRight").w) - 36
	end
	return C.Layout.metrics().W - 30
end

local function renderAch()
	local s = C.snap
	if not s then
		txt(scroll, { Name = "Loading", Size = UDim2.new(1, 0, 0, 40), Text = "불러오는 중…", TextColor3 = K.Color.sub, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1 })
		return
	end
	local list = s.achievements or {}
	local done = 0
	local tiers = { bronze = 0, silver = 0, gold = 0, platinum = 0 }
	for _, a in list do
		if a.done then
			done += 1
			tiers[a.tier] = (tiers[a.tier] or 0) + 1
		end
	end
	local top = card(scroll, "Summary", 62, 1, K.Color.gold)
	txt(top, { Name = "Count", Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 20), Text = string.format("🏆 업적 %d / %d", done, #list), Font = K.Font.bold, TextSize = 15 })
	txt(top, { Name = "Tiers", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8), Size = UDim2.new(0.5, 0, 0, 20), Text = string.format("🥉%d 🥈%d 🥇%d 💎%d", tiers.bronze, tiers.silver, tiers.gold, tiers.platinum), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right })
	local bar = K.ProgressBar(top, { height = 8, color = K.Color.gold })
	bar.frame.Position = UDim2.fromOffset(12, 38)
	bar.frame.Size = UDim2.new(1, -24, 0, 8)
	bar.frame.ZIndex = 46
	bar.fill.ZIndex = 46
	bar.set(0, true)
	task.delay(0.08, function()
		bar.set(if #list > 0 then done / #list else 0)
	end)
	local det = card(scroll, "Detail", 48, 2)
	detailLabel = txt(det, { Name = "Text", Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -24, 1, -8), Text = "배지를 눌러 자세히 보기", TextSize = 11, TextWrapped = true, TextColor3 = K.Color.sub })
	local order = 3
	for _, catId in P.ACH_CATS do
		local items = {}
		for _, a in list do
			if a.cat == catId then
				table.insert(items, a)
			end
		end
		if #items > 0 then
			local catDone = 0
			for _, a in items do
				if a.done then
					catDone += 1
				end
			end
			section(scroll, P.ACH_CAT_NAMES[catId] or catId, order, string.format("%d / %d", catDone, #items))
			order += 1
			-- explicit height (rows x cell): AutomaticSize with a grid is not reliable everywhere
			local cols = math.max(1, math.floor((innerWidth() + 4) / 76))
			local rows = math.ceil(#items / cols)
			local grid = K.frame(scroll, { Name = "Grid_" .. catId, Size = UDim2.new(1, 0, 0, rows * 92 + math.max(0, rows - 1) * 4), LayoutOrder = order, ZIndex = 45 })
			local gl = K.make("UIGridLayout", { CellSize = UDim2.fromOffset(72, 92), CellPadding = UDim2.fromOffset(4, 4), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Left }, grid)
			gl:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
				local h = gl.AbsoluteContentSize.Y
				if h > 0 then
					grid.Size = UDim2.new(1, 0, 0, h)
				end
			end)
			-- done first, then the closest ones
			table.sort(items, function(x, y)
				if x.done ~= y.done then
					return x.done
				end
				local px = if (x.n or 0) > 0 then (x.have or 0) / x.n else 0
				local py = if (y.n or 0) > 0 then (y.have or 0) / y.n else 0
				return px > py
			end)
			for i, a in items do
				badge(grid, a, i)
			end
			order += 1
		end
	end
	if selectedAch then
		for _, a in list do
			if a.id == selectedAch then
				showDetail(a)
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- 레벨
-------------------------------------------------------------------------------------------------
local function renderLevel()
	local s = C.snap
	if not s then
		txt(scroll, { Name = "Loading", Size = UDim2.new(1, 0, 0, 40), Text = "불러오는 중…", TextColor3 = K.Color.sub, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1 })
		return
	end
	local top = card(scroll, "Next", 64, 1, K.Color.gold)
	local nextText, hint
	if s.nextAt then
		local left = math.max(0, s.nextAt - s.earned)
		nextText = string.format("Lv.%d까지 %s 남았어요", s.level + 1, K.won(left))
		-- ~30,000원 per 6-minute shift at Lv1 jobs (docs/ECONOMY.md) -> about 5,000원 a minute
		hint = string.format("알바로 약 %d분 · 목표·업적 보상도 수입으로 쳐요", math.max(1, math.ceil(left / 5000)))
	else
		nextText = "최고 레벨 달성! 광안리의 전설"
		hint = string.format("누적 수입 %s", K.won(s.earned))
	end
	txt(top, { Name = "Next", Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 18), Text = nextText, Font = K.Font.bold, TextSize = 14 })
	local bar = K.ProgressBar(top, { height = 8, color = K.Color.gold })
	bar.frame.Position = UDim2.fromOffset(12, 30)
	bar.frame.Size = UDim2.new(1, -24, 0, 8)
	bar.frame.ZIndex = 46
	bar.fill.ZIndex = 46
	bar.set(0, true)
	task.delay(0.08, function()
		bar.set(s.lp or 0)
	end)
	txt(top, { Name = "Hint", Position = UDim2.fromOffset(12, 42), Size = UDim2.new(1, -24, 0, 14), Text = hint, TextSize = 11, TextColor3 = K.Color.sub })
	section(scroll, "🔓 레벨 혜택", 2, string.format("현재 Lv.%d", s.level))
	for i, u in s.unlocks or {} do
		local have = u.have == true
		local row = card(scroll, "Unlock" .. i, 56, 2 + i, if have then K.Color.gold else nil)
		local lvTile = K.frame(row, { Name = "Lv", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(40, 40), BackgroundTransparency = 0, BackgroundColor3 = if have then K.Color.gold else K.Color.card2, ZIndex = 46 })
		K.corner(lvTile, 12)
		txt(lvTile, { Name = "Text", Size = UDim2.fromScale(1, 1), Text = "Lv\n" .. tostring(u.level), TextSize = 11, Font = K.Font.heavy, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = if have then K.Color.onGold else K.Color.sub, ZIndex = 47 })
		txt(row, { Name = "Name", Position = UDim2.fromOffset(60, 8), Size = UDim2.new(1, -96, 0, 18), Text = string.format("%s %s", tostring(u.icon or ""), tostring(u.name or "")), Font = K.Font.bold, TextSize = 13, TextColor3 = if have then K.Color.text else K.Color.sub, TextTruncate = Enum.TextTruncate.AtEnd })
		txt(row, { Name = "Desc", Position = UDim2.fromOffset(60, 27), Size = UDim2.new(1, -96, 0, 14), Text = tostring(u.desc or ""), TextSize = 11, TextColor3 = K.Color.faint, TextTruncate = Enum.TextTruncate.AtEnd })
		txt(row, { Name = "State", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(28, 28), Text = if have then "✅" else "🔒", TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center })
	end
	section(scroll, "🏷️ 칭호", 40)
	local titles = {}
	for _, t in P.TITLES do
		table.insert(titles, string.format("%s Lv.%d %s", if s.level >= t[1] then "●" else "○", t[1], t[2]))
	end
	txt(scroll, { Name = "Titles", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = table.concat(titles, "\n"), TextSize = 12, TextColor3 = K.Color.sub, TextWrapped = true, LayoutOrder = 41 })
end

-------------------------------------------------------------------------------------------------
-- 정산
-------------------------------------------------------------------------------------------------
local function breakdown(parent: Instance, title: string, cats: any, names: any, order: number, color: Color3)
	local rows = {}
	local total = 0
	for k, v in cats or {} do
		if type(v) == "number" and v > 0 then
			table.insert(rows, { k = k, v = v })
			total += v
		end
	end
	table.sort(rows, function(a, b)
		return a.v > b.v
	end)
	section(parent, title, order, if total > 0 then K.won(total) else "없음")
	for i, r in rows do
		if i > 5 then
			break
		end
		local f = K.frame(parent, { Name = title .. i, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = order + i, ZIndex = 45 })
		txt(f, { Name = "Name", Size = UDim2.new(0, 64, 1, 0), Text = names[r.k] or r.k, TextSize = 12 })
		local rgb = P.CAT_COLORS[r.k]
		local c = if rgb then Color3.fromRGB(rgb[1], rgb[2], rgb[3]) else color
		local track = K.frame(f, { Name = "Track", Position = UDim2.new(0, 68, 0.5, -4), Size = UDim2.new(1, -150, 0, 8), BackgroundTransparency = 0, BackgroundColor3 = K.Color.card3, ZIndex = 45 })
		K.corner(track, UDim.new(0.5, 0))
		local fill = K.frame(track, { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundTransparency = 0, BackgroundColor3 = c, ZIndex = 46 })
		K.corner(fill, UDim.new(0.5, 0))
		K.tweenD(fill, 0.5, { Size = UDim2.fromScale(math.clamp(r.v / math.max(1, total), 0.02, 1), 1) }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, i * 0.04)
		local v = txt(f, { Name = "Value", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 76, 1, 0), Text = P.wonShort(r.v), TextSize = 11, TextColor3 = K.Color.sub, TextXAlignment = Enum.TextXAlignment.Right })
		K.mono(v)
	end
end

local function renderPay()
	local s = C.snap
	if not s then
		txt(scroll, { Name = "Loading", Size = UDim2.new(1, 0, 0, 40), Text = "불러오는 중…", TextColor3 = K.Color.sub, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1 })
		return
	end
	local today = s.today or { d = s.lifeDay or 1, e = 0, s = 0, cats = {}, ecats = {} }
	local top = card(scroll, "Today", 74, 1, K.Color.gold)
	txt(top, { Name = "Title", Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 16), Text = string.format("📱 오늘의 정산 · %d일차", tonumber(today.d) or 1), Font = K.Font.bold, TextSize = 13 })
	local function stat(x: number, title: string, value: number, color: Color3, prefix: string, name: string)
		local f = K.frame(top, { Name = name, Position = UDim2.new(x, 12, 0, 28), Size = UDim2.new(1 / 3, -12, 0, 40), ZIndex = 45 })
		txt(f, { Name = "T", Size = UDim2.new(1, 0, 0, 13), Text = title, TextSize = 11, TextColor3 = K.Color.sub })
		local v = txt(f, { Name = "V", Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 20), Text = "0", TextSize = 16, Font = K.Font.bold, TextColor3 = color, TextTruncate = Enum.TextTruncate.AtEnd })
		K.mono(v, Enum.FontWeight.Bold)
		K.countUp(v, value, { from = 0, prefix = prefix, format = K.wonShort, duration = 0.7 })
	end
	local e, sp = tonumber(today.e) or 0, tonumber(today.s) or 0
	stat(0, "번 돈", e, K.Color.green, "+", "Earned")
	stat(1 / 3, "쓴 돈", sp, Color3.fromRGB(255, 130, 130), "-", "Spent")
	stat(2 / 3, "남은 돈", math.abs(e - sp), if e >= sp then K.Color.gold else Color3.fromRGB(255, 130, 130), if e >= sp then "+" else "-", "Net")
	section(scroll, "📊 최근 7일", 2, "초록 = 번 돈 · 빨강 = 쓴 돈")
	local chartCard = card(scroll, "Chart", 120, 3)
	local inner = K.frame(chartCard, { Name = "Inner", Position = UDim2.fromOffset(10, 8), Size = UDim2.new(1, -20, 1, -14), ZIndex = 45 })
	if C.Payday then
		C.Payday.chart(inner, s.history or {}, { height = 106, highlight = today.d, zIndex = 46 })
	end
	breakdown(scroll, "💵 오늘 번 돈", today.ecats, P.EARN_NAMES, 10, K.Color.green)
	breakdown(scroll, "🧾 오늘 쓴 돈", today.cats, P.SPEND_NAMES, 20, K.Color.red)
	local st = s.stats or {}
	section(scroll, "🏅 기록", 30)
	local rec = card(scroll, "Records", 64, 31)
	txt(rec, { Name = "Text", Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 1, -12), Text = string.format("최고 일당 %s · 최고 한 방 %s\n누적 수입 %s · 누적 지출 %s", K.won(st.bestDay or 0), K.won(st.bestPay or 0), K.won(s.earned or 0), K.won(st.spent or 0)), TextSize = 12, TextWrapped = true, TextColor3 = K.Color.sub })
end

renderTab = function(id: string)
	if not sheet then
		return
	end
	tab = id
	clearScroll()
	detailLabel = nil
	local ok, err = pcall(function()
		if id == "goals" then
			renderGoals()
		elseif id == "ach" then
			renderAch()
		elseif id == "level" then
			renderLevel()
		else
			renderPay()
		end
	end)
	if not ok then
		warn("[GwangalliProgress] panel " .. id .. ": " .. tostring(err))
	end
end

-------------------------------------------------------------------------------------------------
-- Sheet
-------------------------------------------------------------------------------------------------
local function wantSide(): string
	return if C.Layout.deviceClass() == "phoneP" then "bottom" else "right"
end

local function build()
	local side = wantSide()
	if sheet and sheetSide == side then
		return
	end
	if sheet then
		pcall(function()
			sheet.close(true)
		end)
		if sheet.frame then
			sheet.frame:Destroy()
		end
		if sheet.dim then
			sheet.dim:Destroy()
		end
		sheet = nil
	end
	sheetSide = side
	local r = C.Layout.rect("sheetRight")
	local opts: { [string]: any } = { name = "ProgressSheet", title = "내 인생 기록", subtitle = "", side = side, zIndex = 40, onClose = function()
		openState = false
		setModal(false)
	end }
	if side == "right" then
		opts.width = math.max(300, r.w)
	else
		opts.height = 0.86
	end
	sheet = K.BottomSheet(host, opts)
	local content = sheet.content :: Frame
	header = K.frame(content, { Name = "Header", Size = UDim2.new(1, 0, 0, 58), ZIndex = 45 })
	tabs = K.Segmented(content, { items = TAB_ITEMS, value = tab, height = 50, onChange = function(id)
		renderTab(id)
	end })
	tabs.frame.Position = UDim2.fromOffset(0, 62)
	tabs.frame.ZIndex = 45
	for _, d in tabs.frame:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 46
		end
	end
	scroll = K.make("ScrollingFrame", {
		Name = "Scroll",
		Position = UDim2.fromOffset(0, 62 + 56 + 8),
		Size = UDim2.new(1, 0, 1, -(62 + 56 + 8)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = K.Color.sub,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 45,
	}, content)
	K.list(scroll, false, 8)
	K.pad(scroll, 0, 6, 2, 16)
end

function Panel.isOpen(): boolean
	return openState
end

function Panel.open(which: string?)
	build()
	if which and (which == "goals" or which == "ach" or which == "level" or which == "pay") then
		tab = which
	end
	if tabs then
		tabs.set(tab, true)
	end
	local s = C.snap
	sheet.setTitle("내 인생 기록", if s then string.format("인생 레벨 %d · %s", s.level or 1, s.title or "") else "")
	renderHeader()
	renderTab(tab)
	openState = true
	setModal(true)
	sheet.open()
	if C.Chip then
		C.Chip.clearUnseen()
	end
	C.refresh()
end

function Panel.close()
	if sheet and openState then
		sheet.close()
	end
end

function Panel.toggle()
	if openState then
		Panel.close()
	else
		Panel.open()
	end
end

function Panel.init(c: any)
	C = c
	K = c.K
	P = c.P
	host = K.frame(c.panelGui, { Name = "Host", Size = UDim2.fromScale(1, 1), ZIndex = 1 })
	c.on("snap", function()
		if openState and sheet then
			local s = C.snap
			sheet.setTitle("내 인생 기록", if s then string.format("인생 레벨 %d · %s", s.level or 1, s.title or "") else "")
			renderHeader()
			local y = scroll.CanvasPosition
			renderTab(tab)
			scroll.CanvasPosition = y
		end
	end)
	c.on("upd", function()
		if openState and sheet and tab == "goals" then
			local y = scroll.CanvasPosition
			renderTab("goals")
			scroll.CanvasPosition = y
		end
	end)
	c.on("layout", function()
		if openState and sheet and sheetSide ~= wantSide() then
			-- rotated between portrait and landscape: rebuild the sheet on the right side
			local t = tab
			pcall(function()
				sheet.close(true)
			end)
			openState = false
			setModal(false)
			task.delay(0.3, function()
				Panel.open(t)
			end)
		elseif sheet then
			pcall(sheet.relayout)
		end
	end)
end

return Panel
