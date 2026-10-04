-- GwangalliFeatures/FeatureKit (owner: money): shared building blocks for the feature flows, made
-- only from GwangalliUI kit components / tokens / motion (docs/UI_DESIGN_SPEC.md). Not a feature module
-- itself (not in the Registry); feature modules require it and call FK.bind(F) once.
--
--   FK.Flow(key, opts)          modal flow card (two panes on landscape phones, one column elsewhere),
--                               header with back / close, page stack with push / pop motion
--   FK.holdButton(parent, o)    "꾹 눌러서 보내기": fills over o.duration (0.8 s), cancels on release
--   FK.keypad(parent, o)        3 x 4 number pad (00, 0, ⌫; long-press ⌫ clears)
--   FK.amountView(parent, o)    big won amount + hint line (Korean reading or an error), pop / shake
--   FK.checkmark(parent, size)  animated success check (spring circle + stroke reveal)
--   FK.confetti(host)           light confetti burst (skipped on reduced motion)
--   FK.incoming(o)              interactive banner under the toast row (accept / decline, timer ring)
--   FK.avatar(parent, size, userId?, name, color?)   kit avatar tile + Roblox headshot
--   FK.bill(fromUserId, toUserId)                    a banknote flying between two characters (3D, local)
--   FK.call(op, payload, timeout?)                   BankRequest with a timeout -> result table
--   FK.rid()  FK.koreanWon(n)  FK.dayTitle(t)  FK.timeOfDay(t)  FK.shake(gui)  FK.row(...)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local FK = {}

local F: any = nil
local K: any = nil

function FK.bind(ctx: any)
	if F then
		return
	end
	F = ctx
	K = ctx.K
end

-------------------------------------------------------------------------------------------------
-- Utils
-------------------------------------------------------------------------------------------------
local ridSeq = 0
function FK.rid(): string
	ridSeq += 1
	local ok, g = pcall(HttpService.GenerateGUID, HttpService, false)
	local base = if ok and type(g) == "string" then string.gsub(g, "[^%w]", "") else tostring(math.floor(os.clock() * 1000))
	return string.sub(base, 1, 20) .. "x" .. ridSeq
end

-- 1234500 -> "123만 4,500원" ; 30000 -> "3만원" ; 150000000 -> "1억 5,000만원"
function FK.koreanWon(n: number): string
	local v = math.floor(tonumber(n) or 0)
	if v <= 0 then
		return "0원"
	end
	local eok = v // 100000000
	local man = (v % 100000000) // 10000
	local rest = v % 10000
	local parts = {}
	if eok > 0 then
		table.insert(parts, K.commas(eok) .. "억")
	end
	if man > 0 then
		table.insert(parts, K.commas(man) .. "만")
	end
	if rest > 0 then
		table.insert(parts, K.commas(rest))
	end
	return table.concat(parts, " ") .. "원"
end

local WDAY = { "일", "월", "화", "수", "목", "금", "토" }
local function kst(t: number): any
	return os.date("!*t", math.floor(t) + 9 * 3600)
end
local function serverNow(): number
	local ok, n = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return if ok and type(n) == "number" then n else os.time()
end
FK.now = serverNow

function FK.dayKey(t: number): number
	return math.floor((t + 9 * 3600) / 86400)
end

function FK.dayTitle(t: number): string
	local today = FK.dayKey(serverNow())
	local d = FK.dayKey(t)
	local dt = kst(t)
	local base = string.format("%d월 %d일 (%s)", dt.month, dt.day, WDAY[dt.wday] or "")
	if d == today then
		return "오늘 · " .. base
	elseif d == today - 1 then
		return "어제 · " .. base
	end
	return base
end

function FK.timeOfDay(t: number): string
	local dt = kst(t)
	local h = dt.hour
	local ampm = if h < 12 then "오전" else "오후"
	local h12 = h % 12
	if h12 == 0 then
		h12 = 12
	end
	return string.format("%s %d:%02d", ampm, h12, dt.min)
end

function FK.ago(t: number): string
	local d = serverNow() - t
	if d < 60 then
		return "방금"
	elseif d < 3600 then
		return string.format("%d분 전", math.floor(d / 60))
	elseif d < 86400 then
		return string.format("%d시간 전", math.floor(d / 3600))
	end
	return string.format("%d일 전", math.floor(d / 86400))
end

-- studs -> "바로 옆" / "4m" / "25m" / "1.2km" (1 stud = 0.3 m)
function FK.distText(studs: number): string
	local m = (tonumber(studs) or 0) * 0.3
	if m < 3 then
		return "바로 옆"
	elseif m < 20 then
		return string.format("%dm", math.floor(m + 0.5))
	end
	return K.meters(studs)
end

function FK.shake(g: GuiObject, amp: number?)
	local a = amp or 8
	local base = g.Position
	task.spawn(function()
		for i, dx in { a, -a, a * 0.6, -a * 0.6, a * 0.25, 0 } do
			local _ = i
			g.Position = base + UDim2.fromOffset(dx, 0)
			task.wait(0.035)
		end
		g.Position = base
	end)
end

-- Walks a kit frame tree and sets every GuiObject's ZIndex >= z (for pieces parented under a dim).
function FK.raise(root: Instance, z: number)
	if root:IsA("GuiObject") and root.ZIndex < z then
		root.ZIndex = z
	end
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") and d.ZIndex < z then
			d.ZIndex = z
		end
	end
end

-- BankRequest with a timeout. Never errors; returns {ok, code, message, ...}.
local bankRF: Instance? = nil
function FK.call(op: string, payload: any?, timeout: number?): any
	local rf = bankRF
	if not (rf and rf.Parent) then
		rf = F.remote("BankRequest", 8)
		bankRF = rf
	end
	if not (rf and rf:IsA("RemoteFunction")) then
		return { ok = false, code = "net", message = "은행 서버에 연결하는 중이에요. 잠시 후 다시 시도해 주세요" }
	end
	local done, result = false, nil
	task.spawn(function()
		local ok, r = pcall(function()
			return (rf :: RemoteFunction):InvokeServer(op, payload)
		end)
		if ok and type(r) == "table" then
			result = r
		else
			result = { ok = false, code = "net", message = "연결이 원활하지 않아요. 잠시 후 다시 시도해 주세요" }
		end
		done = true
	end)
	local t0 = os.clock()
	local limit = timeout or 10
	while not done and os.clock() - t0 < limit do
		task.wait(0.05)
	end
	if not done then
		return { ok = false, code = "timeout", message = "응답이 늦어요. 거래내역에서 결과를 꼭 확인해 주세요" }
	end
	if type(result.message) ~= "string" then
		result.message = if result.ok then "완료됐어요" else "처리하지 못했어요"
	end
	return result
end

-------------------------------------------------------------------------------------------------
-- Avatar (kit tile + Roblox headshot; the tile stays as the placeholder / fallback)
-------------------------------------------------------------------------------------------------
local AV_COLORS = { Color3.fromRGB(139, 108, 255), Color3.fromRGB(61, 214, 245), Color3.fromRGB(255, 79, 163), Color3.fromRGB(255, 194, 71), Color3.fromRGB(61, 220, 132), Color3.fromRGB(84, 140, 255) }
function FK.avatar(parent: Instance, size: number, userId: number?, name: string?, color: Color3?): Frame
	local initial = "?"
	if type(name) == "string" and name ~= "" then
		for _, cp in utf8.codes(name) do
			initial = utf8.char(cp)
			break
		end
	end
	local c = color or AV_COLORS[((userId or 0) % #AV_COLORS) + 1]
	local tile = K.avatar(parent, size, initial, c)
	if userId and userId > 0 then
		local img = Instance.new("ImageLabel")
		img.Name = "Headshot"
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromScale(1, 1)
		img.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=150&h=150"
		img.ZIndex = tile.ZIndex + 2
		img.Parent = tile
		K.corner(img, UDim.new(0.5, 0))
	end
	return tile
end

-------------------------------------------------------------------------------------------------
-- Flow card
-------------------------------------------------------------------------------------------------
-- opts {title?, accent? (Color3), onClose?, dismissible? (tap outside closes, default false),
--       width? (narrow layout max width, default 420), wideWidth? (default 720)}
-- api: page(id, builder) ; open(id, args) ; go(id, args) (push) ; replace(id, args) ; back() ; close()
--      isOpen() ; wide() ; setTitle(t, sub?) ; setBack(visible) ; current() ; card ; body
-- builder(frame, flow) -> {layout = fn(wide, w, h)?, show = fn(args)?, title?, subtitle?, back? (bool)}
function FK.Flow(key: string, opts: { [string]: any }?): any
	local o = opts or {}
	local gui = F.gui
	local api: any = { open_ = false }
	local root = K.frame(gui, { Name = "Flow_" .. key, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 20 })
	local dim = K.dim(root, "Dim", 20, function()
		if o.dismissible then
			api.close()
		end
	end)
	local card = K.Panel(root, { Name = "Card", ZIndex = 22, BackgroundTransparency = 0.02, Radius = K.Radius.xl })
	card.BackgroundColor3 = K.Color.glass2
	card.ClipsDescendants = true
	K.shadow(card, K.Radius.xl, 8, "strong")
	local accent = K.frame(card, { Name = "Accent", Size = UDim2.new(1, 0, 0, 3), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 23 })
	K.gradient(accent, if o.accent then { o.accent, K.shade(o.accent, 0.1, -0.15) } else K.Grad.bridge, 0, NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(0.25, 0), NumberSequenceKeypoint.new(0.75, 0), NumberSequenceKeypoint.new(1, 0.9) }))
	local header = K.frame(card, { Name = "Header", Size = UDim2.new(1, 0, 0, 52), ZIndex = 23 })
	local back = K.IconButton(header, { name = "Back", icon = "‹", textSize = 26, zIndex = 24 })
	back.AnchorPoint = Vector2.new(0, 0.5)
	back.Position = UDim2.new(0, 6, 0.5, 2)
	back.BackgroundTransparency = 1
	back.Visible = false
	local title = K.text(header, { Name = "Title", Position = UDim2.fromOffset(16, 9), Size = UDim2.new(1, -110, 0, 22), Text = o.title or "", Font = K.Font.bold, TextSize = K.Type.title2, ZIndex = 24, TextTruncate = Enum.TextTruncate.AtEnd })
	local subtitle = K.text(header, { Name = "Subtitle", Position = UDim2.fromOffset(16, 31), Size = UDim2.new(1, -110, 0, 15), Text = "", TextColor3 = K.Color.sub, TextSize = K.Type.caption, ZIndex = 24, TextTruncate = Enum.TextTruncate.AtEnd })
	local close = K.IconButton(header, { name = "Close", icon = "✕", textSize = 14, zIndex = 24 })
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, -8, 0.5, 2)
	local body = K.frame(card, { Name = "Body", Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 1, -52), ClipsDescendants = true, ZIndex = 23 })

	api.root = root
	api.card = card
	api.body = body
	api.header = header
	local pages: { [string]: any } = {}
	local stack: { string } = {}
	local isWide = false
	local W, H = 0, 0

	local function headerFor(id: string)
		local p = pages[id]
		if not p then
			return
		end
		local hasBack = if p.api.back ~= nil then p.api.back else #stack > 1
		back.Visible = hasBack
		local x = if hasBack then 46 else 16
		title.Position = UDim2.fromOffset(x, if (p.subtitle or "") ~= "" then 9 else 15)
		title.Size = UDim2.new(1, -(x + 60), 0, 22)
		subtitle.Position = UDim2.fromOffset(x, 31)
		subtitle.Size = UDim2.new(1, -(x + 60), 0, 15)
		K.setText(title, p.title or "")
		K.setText(subtitle, p.subtitle or "")
		subtitle.Visible = (p.subtitle or "") ~= ""
	end

	function api.setTitle(t: string, sub: string?)
		local id = stack[#stack]
		local p = id and pages[id]
		if p then
			p.title = t
			p.subtitle = sub or ""
			headerFor(id)
		end
	end

	function api.wide(): boolean
		return isWide
	end

	function api.size(): (number, number)
		return W, H - 52
	end

	local function layoutCard()
		local m = F.Layout.metrics()
		local sw, sh = m.W or 800, m.H or 400
		isWide = sw >= 560 and sh < 560
		if isWide then
			-- landscape phones: nearly the whole safe area (the flow is modal: controls are off)
			W = math.min(sw - 16, o.wideWidth or 720)
			H = sh - 20
			card.AnchorPoint = Vector2.new(0.5, 0)
			card.Position = UDim2.new(0.5, 0, 0, 4)
		else
			W = math.min(sw - 16, o.width or 420)
			H = math.min(sh - 28, 760)
			card.AnchorPoint = Vector2.new(0.5, 0.5)
			card.Position = UDim2.fromScale(0.5, 0.5)
		end
		card.Size = UDim2.fromOffset(W, H)
		for _, p in pages do
			if p.api.layout then
				local ok, err = pcall(p.api.layout, isWide, W, H - 52)
				if not ok then
					warn("[GwangalliFeatures] page layout: " .. tostring(err))
				end
			end
		end
	end
	api.relayout = layoutCard

	function api.page(id: string, builder: (Frame, any) -> any)
		local frame = K.frame(body, { Name = "Page_" .. id, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 23, BackgroundTransparency = 1 })
		local p = { frame = frame, api = {}, title = "", subtitle = "" }
		pages[id] = p
		local ok, res = pcall(builder, frame, api)
		if ok and type(res) == "table" then
			p.api = res
			p.title = res.title or ""
			p.subtitle = res.subtitle or ""
		elseif not ok then
			warn("[GwangalliFeatures] page " .. id .. " build failed: " .. tostring(res))
		end
		return p
	end

	local function showPage(id: string, args: any?)
		local p = pages[id]
		if not p then
			return
		end
		if p.api.show then
			local ok, err = pcall(p.api.show, args or {})
			if not ok then
				warn("[GwangalliFeatures] page " .. id .. " show failed: " .. tostring(err))
			end
		end
		headerFor(id)
	end

	function api.current(): string?
		return stack[#stack]
	end

	function api.go(id: string, args: any?)
		local cur = stack[#stack]
		if cur == id then
			showPage(id, args)
			return
		end
		table.insert(stack, id)
		local p = pages[id]
		showPage(id, args)
		if cur and pages[cur] then
			K.pushPage(p.frame, pages[cur].frame)
		else
			p.frame.Position = UDim2.new()
			p.frame.Visible = true
		end
	end

	function api.replace(id: string, args: any?)
		local cur = stack[#stack]
		table.clear(stack)
		table.insert(stack, id)
		for pid, p in pages do
			if pid ~= id and pid ~= cur then
				p.frame.Visible = false
			end
		end
		local p = pages[id]
		showPage(id, args)
		if cur and cur ~= id and pages[cur] then
			K.pushPage(p.frame, pages[cur].frame)
		else
			p.frame.Position = UDim2.new()
			p.frame.Visible = true
		end
	end

	function api.back()
		if #stack <= 1 then
			api.close()
			return
		end
		local top = table.remove(stack)
		local under = stack[#stack]
		if top and under and pages[top] and pages[under] then
			K.popPage(pages[top].frame, pages[under].frame)
			local p = pages[under]
			if p.api.resume then
				pcall(p.api.resume)
			end
			headerFor(under)
		end
	end

	function api.isOpen(): boolean
		return api.open_
	end

	function api.open(id: string, args: any?)
		layoutCard()
		if not api.open_ then
			api.open_ = true
			root.Visible = true
			F.modal(true, "flow_" .. key)
			dim.BackgroundTransparency = 1
			K.tween(dim, 0.25, { BackgroundTransparency = 0.45 })
			K.springIn(card, 0.94)
			K.feedback("open")
		end
		table.clear(stack)
		for _, p in pages do
			p.frame.Visible = false
			p.frame.Position = UDim2.new()
		end
		table.insert(stack, id)
		local p = pages[id]
		if p then
			p.frame.Visible = true
		end
		showPage(id, args)
	end

	function api.close()
		if not api.open_ then
			return
		end
		api.open_ = false
		F.modal(false, "flow_" .. key)
		K.tween(dim, 0.18, { BackgroundTransparency = 1 })
		local s = K.scaleOf(card)
		K.tween(s, 0.18, { Scale = 0.95 })
		K.sound("close")
		task.delay(0.19, function()
			if not api.open_ then
				root.Visible = false
				s.Scale = 1
			end
		end)
		for _, p in pages do
			if p.api.hide then
				pcall(p.api.hide)
			end
		end
		if o.onClose then
			task.spawn(o.onClose)
		end
	end

	back.Activated:Connect(function()
		api.back()
	end)
	close.Activated:Connect(function()
		api.close()
	end)
	F.Layout.onChanged(function()
		if api.open_ then
			layoutCard()
		end
	end)
	return api
end

-- Two panes inside a page: A (left / top) and B (right / bottom). layout(wide, w, h, aHeight) places
-- them: wide -> side by side (A takes `split` of the width); narrow -> A on top (aHeight px), B below.
function FK.panes(page: Frame, split: number?): any
	local a = K.frame(page, { Name = "PaneA", ZIndex = 23 })
	local b = K.frame(page, { Name = "PaneB", ZIndex = 23 })
	local api = { a = a, b = b }
	function api.layout(wide: boolean, w: number, h: number, aHeight: number)
		local pad = 12
		if wide then
			local s = split or 0.46
			local aw = math.floor((w - pad * 3) * s)
			a.Position = UDim2.fromOffset(pad, 0)
			a.Size = UDim2.fromOffset(aw, h - pad)
			b.Position = UDim2.fromOffset(pad * 2 + aw, 0)
			b.Size = UDim2.fromOffset(w - aw - pad * 3, h - pad)
		else
			local ah = math.min(aHeight, h)
			a.Position = UDim2.fromOffset(pad, 0)
			a.Size = UDim2.fromOffset(w - pad * 2, ah)
			b.Position = UDim2.fromOffset(pad, ah)
			b.Size = UDim2.fromOffset(w - pad * 2, math.max(0, h - ah - pad))
		end
	end
	return api
end

-------------------------------------------------------------------------------------------------
-- Hold-to-confirm button
-------------------------------------------------------------------------------------------------
-- opts {text, holdText?, doneText?, duration = 0.8, grad? (colors), size?, order?, name?, onComplete}
function FK.holdButton(parent: Instance?, opts: { [string]: any }): any
	local dur = opts.duration or 0.8
	local b = K.make("TextButton", { Name = opts.name or "Hold", Size = opts.size or UDim2.new(1, 0, 0, 52), BackgroundColor3 = K.Color.card2, BorderSizePixel = 0, AutoButtonColor = false, Text = "", LayoutOrder = opts.order or 0, ZIndex = 24, ClipsDescendants = true }, nil)
	K.corner(b, 14)
	local st = K.stroke(b, K.Color.cyan, 1, 0.55)
	local fill = K.frame(b, { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 25 })
	K.corner(fill, 14)
	K.gradient(fill, opts.grad or K.Grad.primary, 0)
	local label = K.text(b, { Name = "Label", Size = UDim2.fromScale(1, 1), Text = opts.text or "꾹 눌러서 보내기", Font = K.Font.bold, TextSize = K.Type.body, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 26 })
	local hint = K.text(b, { Name = "Hint", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(40, 20), Text = "0.8초", TextColor3 = K.Color.faint, TextSize = K.Type.micro, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 26 })
	local api = { button = b, enabled = true, busy = false }
	local serial = 0
	local held = false
	local tween: Tween? = nil
	local ticker: thread? = nil

	local function idle()
		label.Text = opts.text or "꾹 눌러서 보내기"
		label.TextColor3 = K.Color.text
		hint.Visible = true
	end
	function api.reset()
		serial += 1
		held = false
		api.busy = false
		if tween then
			tween:Cancel()
		end
		fill.Size = UDim2.fromScale(0, 1)
		idle()
	end
	function api.setEnabled(on: boolean)
		api.enabled = on
		b.BackgroundTransparency = if on then 0 else 0.4
		label.TextTransparency = if on then 0 else 0.5
		st.Transparency = if on then 0.55 else 0.9
	end
	function api.setText(t: string)
		opts.text = t
		if not held and not api.busy then
			label.Text = t
		end
	end
	function api.setBusy(t: string?)
		api.busy = true
		fill.Size = UDim2.fromScale(1, 1)
		label.Text = t or opts.doneText or "보내는 중…"
		label.TextColor3 = K.Color.onAccent
		hint.Visible = false
	end

	local function start()
		if not api.enabled or api.busy or held then
			return
		end
		held = true
		serial += 1
		local mine = serial
		label.Text = opts.holdText or "계속 누르고 있어요…"
		hint.Visible = false
		K.feedback("tap")
		if tween then
			tween:Cancel()
		end
		local remaining = dur * (1 - fill.Size.X.Scale)
		local ok, tw = pcall(function()
			local t = TweenService:Create(fill, TweenInfo.new(math.max(0.05, remaining), Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) })
			t:Play()
			return t
		end)
		tween = if ok then tw else nil
		ticker = task.spawn(function()
			local ticks = 0
			while serial == mine and held and ticks < 12 do
				task.wait(0.2)
				ticks += 1
				if serial == mine and held then
					K.haptic("tap")
				end
			end
		end)
		task.delay(remaining, function()
			if serial == mine and held then
				held = false
				api.setBusy()
				K.feedback("success")
				if opts.onComplete then
					task.spawn(opts.onComplete)
				end
			end
		end)
	end
	local function stop()
		if not held then
			return
		end
		held = false
		serial += 1
		if tween then
			tween:Cancel()
		end
		K.tween(fill, 0.2, { Size = UDim2.fromScale(0, 1) })
		idle()
		label.Text = "끝까지 꾹 눌러 주세요"
		task.delay(1.2, function()
			if not held and not api.busy then
				idle()
			end
		end)
		FK.shake(b, 5)
	end
	b.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			start()
		elseif input.KeyCode == Enum.KeyCode.ButtonA or input.KeyCode == Enum.KeyCode.Return then
			start()
		end
	end)
	b.InputEnded:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonA or input.KeyCode == Enum.KeyCode.Return then
			stop()
		end
	end)
	b.MouseLeave:Connect(stop)
	b.Destroying:Connect(function()
		serial += 1
		local _ = ticker
	end)
	b.Parent = parent
	return api
end

-------------------------------------------------------------------------------------------------
-- Keypad
-------------------------------------------------------------------------------------------------
-- opts {onKey(k) (k = "0".."9" | "00" | "back" | "clear"), keys?}
function FK.keypad(parent: Instance, opts: { [string]: any }): any
	local frame = K.frame(parent, { Name = "Keypad", Size = UDim2.fromScale(1, 1), ZIndex = 24 })
	local keys = opts.keys or { "1", "2", "3", "4", "5", "6", "7", "8", "9", "00", "0", "back" }
	local buttons = {}
	for i, k in keys do
		local b = K.make("TextButton", { Name = "Key_" .. k, BackgroundColor3 = K.Color.card, BackgroundTransparency = 0.35, BorderSizePixel = 0, AutoButtonColor = false, Text = if k == "back" then "⌫" else k, TextColor3 = K.Color.text, Font = K.Font.bold, TextSize = 22, ZIndex = 25 }, frame)
		K.corner(b, 12)
		if k ~= "back" then
			K.mono(b)
		end
		K.pressable(b, { scale = 0.92, sound = "tap" })
		local downAt = 0
		b.MouseButton1Down:Connect(function()
			downAt = os.clock()
			local mine = downAt
			if k == "back" then
				task.delay(0.6, function()
					if downAt == mine then
						downAt = 0
						opts.onKey("clear")
						K.haptic("toggle")
					end
				end)
			end
		end)
		b.MouseButton1Up:Connect(function()
			downAt = 0
		end)
		b.Activated:Connect(function()
			opts.onKey(k)
		end)
		buttons[i] = b
	end
	local api = { frame = frame, buttons = buttons }
	function api.layout(w: number, h: number)
		local gap = 6
		local cols, rows = 3, math.ceil(#keys / 3)
		local bw = math.floor((w - gap * (cols - 1)) / cols)
		local bh = math.max(44, math.floor((h - gap * (rows - 1)) / rows))
		bh = math.min(bh, 64)
		local totalH = rows * bh + (rows - 1) * gap
		local y0 = math.max(0, math.floor((h - totalH) / 2))
		for i, b in buttons do
			local c = (i - 1) % cols
			local r = (i - 1) // cols
			b.Position = UDim2.fromOffset(c * (bw + gap), y0 + r * (bh + gap))
			b.Size = UDim2.fromOffset(bw, bh)
			b.TextSize = if bh >= 56 then 24 else 20
		end
	end
	return api
end

-------------------------------------------------------------------------------------------------
-- Amount view
-------------------------------------------------------------------------------------------------
function FK.amountView(parent: Instance, opts: { [string]: any }?): any
	local o = opts or {}
	local frame = K.frame(parent, { Name = "Amount", Size = UDim2.new(1, 0, 0, o.height or 74), LayoutOrder = o.order or 0, ZIndex = 24 })
	local label = K.text(frame, { Name = "Value", Size = UDim2.new(1, 0, 0, 44), Text = o.placeholder or "얼마를 보낼까요?", TextColor3 = K.Color.faint, Font = K.Font.bold, TextSize = o.textSize or 30, TextXAlignment = o.align or Enum.TextXAlignment.Left, ZIndex = 25, TextScaled = false, TextTruncate = Enum.TextTruncate.AtEnd })
	local hint = K.text(frame, { Name = "Hint", Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 18), Text = "", TextColor3 = K.Color.sub, TextSize = K.Type.caption, TextXAlignment = o.align or Enum.TextXAlignment.Left, ZIndex = 25, TextTruncate = Enum.TextTruncate.AtEnd })
	local scale = K.scaleOf(label)
	local api = { frame = frame, label = label, hint = hint, value = 0 }
	function api.set(n: number, pop: boolean?)
		api.value = n
		if n <= 0 then
			label.Text = o.placeholder or "얼마를 보낼까요?"
			label.TextColor3 = K.Color.faint
			label.TextSize = math.min(o.textSize or 30, 24)
			pcall(function()
				label.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
			end)
		else
			label.Text = K.commas(n) .. "원"
			label.TextColor3 = K.Color.text
			label.TextSize = o.textSize or 30
			K.mono(label)
			if pop then
				scale.Scale = 1.06
				K.tween(scale, 0.18, { Scale = 1 })
			end
		end
	end
	function api.setHint(t: string, color: Color3?)
		hint.Text = t
		hint.TextColor3 = color or K.Color.sub
	end
	function api.error(t: string)
		api.setHint(t, K.Color.red)
		FK.shake(label, 7)
		K.feedback("error")
	end
	return api
end

-------------------------------------------------------------------------------------------------
-- Success check
-------------------------------------------------------------------------------------------------
function FK.checkmark(parent: Instance, size: number, color: Color3?): any
	local c = color or K.Color.green
	local holder = K.frame(parent, { Name = "Check", Size = UDim2.fromOffset(size, size), ZIndex = 25 })
	local glow = K.frame(holder, { Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.5, 1.5), BackgroundTransparency = 0.85, BackgroundColor3 = c, ZIndex = 25 })
	K.corner(glow, UDim.new(0.5, 0))
	local circle = K.frame(holder, { Name = "Circle", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 26 })
	K.corner(circle, UDim.new(0.5, 0))
	K.gradient(circle, { K.shade(c, -0.05, 0.12), K.shade(c, 0.08, -0.12) }, 120)
	local th = math.max(4, math.floor(size * 0.09))
	local reveal = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.49, 0), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 1) })
	local function arm(x0: number, y0: number, x1: number, y1: number): (Frame, UIGradient)
		local dx, dy = (x1 - x0) * size, (y1 - y0) * size
		local len = math.sqrt(dx * dx + dy * dy)
		local f = K.frame(circle, { Name = "Arm", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset((x0 + x1) / 2 * size, (y0 + y1) / 2 * size), Size = UDim2.fromOffset(len + th * 0.6, th), Rotation = math.deg(math.atan2(dy, dx)), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 27 })
		K.corner(f, UDim.new(0.5, 0))
		local g = K.gradient(f, { Color3.new(1, 1, 1), Color3.new(1, 1, 1) }, 0, reveal)
		g.Offset = Vector2.new(-1, 0)
		return f, g
	end
	local _, g1 = arm(0.27, 0.52, 0.43, 0.68)
	local _, g2 = arm(0.43, 0.68, 0.75, 0.34)
	local api = { frame = holder }
	function api.play()
		local s = K.scaleOf(circle)
		s.Scale = 0.3
		g1.Offset = Vector2.new(-1, 0)
		g2.Offset = Vector2.new(-1, 0)
		glow.Size = UDim2.fromScale(0.9, 0.9)
		glow.BackgroundTransparency = 0.6
		K.spring(s, { Scale = 1 }, { duration = 0.45, amount = 0.18 })
		K.tweenD(g1, 0.16, { Offset = Vector2.new(0.5, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0.22)
		K.tweenD(g2, 0.22, { Offset = Vector2.new(0.5, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0.36)
		K.tweenD(glow, 0.8, { Size = UDim2.fromScale(1.7, 1.7), BackgroundTransparency = 1 }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0.2)
	end
	function api.setColor(col: Color3)
		c = col
		local g = circle:FindFirstChildOfClass("UIGradient")
		if g then
			g.Color = ColorSequence.new(K.shade(col, -0.05, 0.12), K.shade(col, 0.08, -0.12))
		end
		glow.BackgroundColor3 = col
	end
	return api
end

-------------------------------------------------------------------------------------------------
-- Confetti (light)
-------------------------------------------------------------------------------------------------
local CONFETTI = { Color3.fromRGB(61, 214, 245), Color3.fromRGB(255, 79, 163), Color3.fromRGB(255, 194, 71), Color3.fromRGB(139, 108, 255), Color3.fromRGB(61, 220, 132) }
function FK.confetti(host: GuiObject, count: number?)
	if K.reduced() then
		return
	end
	local n = count or 18
	local w = math.max(100, host.AbsoluteSize.X)
	local h = math.max(100, host.AbsoluteSize.Y)
	for i = 1, n do
		local piece = K.frame(host, { Name = "Confetti", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, math.random(-20, 20), 0, math.floor(h * 0.18)), Size = UDim2.fromOffset(math.random(5, 8), math.random(9, 13)), BackgroundTransparency = 0, BackgroundColor3 = CONFETTI[(i % #CONFETTI) + 1], Rotation = math.random(0, 180), ZIndex = 40 })
		if i % 3 == 0 then
			K.corner(piece, UDim.new(0.5, 0))
		end
		local tx = math.random(-math.floor(w * 0.45), math.floor(w * 0.45))
		local peak = math.random(20, 70)
		local dur = 0.9 + math.random() * 0.6
		-- burst up, then fall and fade
		TweenService:Create(piece, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, tx * 0.45, 0, math.floor(h * 0.18) - peak) }):Play()
		task.delay(0.28, function()
			if piece.Parent then
				TweenService:Create(piece, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(0.5, tx, 0, math.floor(h * (0.55 + math.random() * 0.35))), Rotation = piece.Rotation + math.random(180, 540), BackgroundTransparency = 1 }):Play()
			end
		end)
		task.delay(0.3 + dur, function()
			piece:Destroy()
		end)
	end
end

-------------------------------------------------------------------------------------------------
-- Incoming banners (money request, cash offer): below the toast row, interactive
-------------------------------------------------------------------------------------------------
local incomingHolder: Frame? = nil
local incomingList: { any } = {}
local function placeIncoming()
	local holder = incomingHolder
	if not holder then
		return
	end
	-- under the toast row; on landscape phones between the thumbstick zone and the right column so the
	-- card's buttons never sit where the thumb steers
	local r = F.Layout.rect("toasts")
	local m = F.Layout.metrics()
	local W = m.W or 800
	local x0, x1 = 8, W - 8
	local thumb = m.thumb
	local y = r.y + r.h + 4
	if m.class == "phoneL" then
		if thumb then
			x0 = math.max(x0, thumb.x + thumb.w + 8)
		end
		local col = F.Layout.rect("rightColumn")
		if col.w > 0 then
			x1 = math.min(x1, col.x - 8)
		end
	end
	local w = math.clamp(x1 - x0, 240, 400)
	local x = math.clamp(x0 + (x1 - x0 - w) / 2, 8, math.max(8, W - w - 8))
	holder.Position = UDim2.fromOffset(x, y)
	holder.Size = UDim2.fromOffset(w, 220)
end
local function reflowIncoming()
	local y = 0
	for i, e in incomingList do
		e.card.Visible = i <= 2
		if i <= 2 then
			K.tween(e.card, 0.25, { Position = UDim2.fromOffset(0, y) })
			y += e.h + 6
		end
	end
end

-- o {id, userId?, name?, icon?, color?, title, body, timeout?, primary = {text, style?, onClick},
--    secondary = {text, onClick}, onExpire?} -> {dismiss(), card}
function FK.incoming(o: { [string]: any }): any
	if not incomingHolder then
		incomingHolder = K.frame(F.gui, { Name = "Incoming", ZIndex = 30 })
		F.Layout.onChanged(placeIncoming)
	end
	placeIncoming()
	for _, e in incomingList do
		if e.id == o.id then
			e.dismiss()
		end
	end
	local color = o.color or K.Color.gold
	local h = 104
	local card = K.Panel(incomingHolder, { Name = "Card_" .. tostring(o.id), Size = UDim2.new(1, 0, 0, h), Position = UDim2.fromOffset(0, -h - 20), ZIndex = 31, BackgroundTransparency = 0.03, Radius = K.Radius.lg })
	card.BackgroundColor3 = K.Color.glass2
	local st = card:FindFirstChildOfClass("UIStroke")
	if st then
		st.Color = color
		st.Transparency = 0.45
	end
	local av: Frame
	if o.userId then
		av = FK.avatar(card, 38, o.userId, o.name, color)
	else
		av = K.iconTile(card, 38, o.icon or "💸", color, true)
	end
	av.Position = UDim2.fromOffset(12, 12)
	local ring: any = nil
	local tx = 60
	K.text(card, { Name = "Title", Position = UDim2.fromOffset(tx, 11), Size = UDim2.new(1, -(tx + 52), 0, 18), Text = o.title or "", Font = K.Font.bold, TextSize = K.Type.bodySm, ZIndex = 32, TextTruncate = Enum.TextTruncate.AtEnd })
	K.text(card, { Name = "Body", Position = UDim2.fromOffset(tx, 30), Size = UDim2.new(1, -(tx + 52), 0, 16), Text = o.body or "", TextColor3 = K.Color.sub, TextSize = K.Type.caption, ZIndex = 32, TextTruncate = Enum.TextTruncate.AtEnd })
	if o.timeout then
		ring = K.Ring(card, { size = 30, thickness = 3, color = color, text = tostring(math.ceil(o.timeout)) })
		ring.frame.AnchorPoint = Vector2.new(1, 0)
		ring.frame.Position = UDim2.new(1, -12, 0, 12)
		FK.raise(ring.frame, 32)
	end
	local row = K.frame(card, { Name = "Buttons", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -10), Size = UDim2.new(1, -24, 0, 44), ZIndex = 32 })
	local entry: any = { id = o.id, card = card, h = h, dead = false }
	function entry.dismiss()
		if entry.dead then
			return
		end
		entry.dead = true
		local idx = table.find(incomingList, entry)
		if idx then
			table.remove(incomingList, idx)
		end
		K.tween(card, 0.2, { Position = UDim2.fromOffset(0, -h - 20) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		task.delay(0.21, function()
			card:Destroy()
		end)
		reflowIncoming()
	end
	local function mk(def: any, i: number, n: number)
		local b = K.Button(row, { name = if i == n then "Primary" else "Secondary", text = def.text, style = def.style or (if i == n then "primary" else "secondary"), size = UDim2.new(1 / n, if n > 1 then -4 else 0, 1, 0), position = UDim2.new((i - 1) / n, if i > 1 then 4 else 0, 0, 0), zIndex = 33 })
		b.Activated:Connect(function()
			if entry.dead then
				return
			end
			if def.keep ~= true then
				entry.dismiss()
			end
			if def.onClick then
				task.spawn(def.onClick)
			end
		end)
		return b
	end
	local defs = {}
	if o.secondary then
		table.insert(defs, o.secondary)
	end
	if o.primary then
		table.insert(defs, o.primary)
	end
	for i, def in defs do
		mk(def, i, #defs)
	end
	table.insert(incomingList, 1, entry)
	reflowIncoming()
	K.feedback("notify")
	if o.timeout then
		local t0 = os.clock()
		task.spawn(function()
			while not entry.dead do
				local left = o.timeout - (os.clock() - t0)
				if left <= 0 then
					entry.dismiss()
					if o.onExpire then
						task.spawn(o.onExpire)
					end
					break
				end
				if ring then
					ring.set(left / o.timeout)
					K.setText(ring.label, tostring(math.ceil(left)))
				end
				task.wait(0.2)
			end
		end)
	end
	return entry
end

function FK.dismissIncoming(id: string)
	for _, e in table.clone(incomingList) do
		if e.id == id then
			e.dismiss()
		end
	end
end

-------------------------------------------------------------------------------------------------
-- A banknote flying from one character's hand to another's (client-local 3D effect)
-------------------------------------------------------------------------------------------------
local function handOf(p: Player?): BasePart?
	local ch = p and p.Character
	if not ch then
		return nil
	end
	local h = ch:FindFirstChild("RightHand") or ch:FindFirstChild("Right Arm") or ch:FindFirstChild("HumanoidRootPart")
	return if h and h:IsA("BasePart") then h else nil
end

function FK.bill(fromUserId: number, toUserId: number, count: number?)
	local a = handOf(Players:GetPlayerByUserId(fromUserId))
	local b = handOf(Players:GetPlayerByUserId(toUserId))
	if not a or not b then
		return
	end
	for i = 1, math.clamp(count or 3, 1, 5) do
		task.delay((i - 1) * 0.09, function()
			local pa, pb = a.Position, b.Position
			if (pa - pb).Magnitude > 60 then
				return
			end
			local bill = Instance.new("Part")
			bill.Name = "GwangalliBanknote"
			bill.Anchored = true
			bill.CanCollide = false
			bill.CanQuery = false
			bill.CanTouch = false
			bill.CastShadow = false
			bill.Size = Vector3.new(0.9, 0.04, 0.45)
			bill.Color = Color3.fromRGB(122, 182, 128)
			bill.Material = Enum.Material.SmoothPlastic
			local sg = Instance.new("SurfaceGui")
			sg.Face = Enum.NormalId.Top
			sg.CanvasSize = Vector2.new(180, 90)
			sg.LightInfluence = 0.5
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.Size = UDim2.fromScale(1, 1)
			t.Text = "₩ 10000"
			t.TextColor3 = Color3.fromRGB(30, 70, 40)
			t.Font = Enum.Font.GothamBold
			t.TextScaled = true
			t.Parent = sg
			sg.Parent = bill
			bill.CFrame = CFrame.new(pa)
			bill.Parent = workspace
			local mid = (pa + pb) / 2 + Vector3.new(0, 2.2, 0)
			local spin = math.random(0, 360)
			local ok = pcall(function()
				local t1 = TweenService:Create(bill, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(mid) * CFrame.Angles(0, math.rad(spin), math.rad(20)) })
				t1:Play()
				t1.Completed:Connect(function()
					local t2 = TweenService:Create(bill, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(b.Position) * CFrame.Angles(0, math.rad(spin + 180), 0), Size = Vector3.new(0.5, 0.03, 0.25) })
					t2:Play()
				end)
			end)
			task.delay(if ok then 0.55 else 0.05, function()
				bill:Destroy()
			end)
		end)
	end
end

-------------------------------------------------------------------------------------------------
-- A list row used by the statement / request lists (kit ListRow + a second trailing line)
-------------------------------------------------------------------------------------------------
function FK.row(parent: Instance, o: { [string]: any }): any
	local r = K.ListRow(parent, o)
	if o.trailing2 then
		r.trailing.Position = UDim2.new(1, -(12 + (if o.chevron then 18 else 0)), 0.5, -8)
		local t2 = K.text(r.row, { Name = "Trailing2", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -(12 + (if o.chevron then 18 else 0)), 0.5, 11), Size = UDim2.fromOffset(math.max(0, (o.trailingWidth or 96) - 4), 15), Text = o.trailing2, TextColor3 = K.Color.faint, TextSize = K.Type.micro, TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd })
		r.trailing2 = t2
	end
	return r
end

-- Frame (auto height) with a vertical list: the scroll content helper used by pages.
function FK.scroll(parent: Instance, name: string?): (ScrollingFrame, Frame)
	local s = K.make("ScrollingFrame", {
		Name = name or "Scroll",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = K.Color.faint,
		ScrollBarImageTransparency = 0.4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		ZIndex = 24,
	}, parent)
	local content = K.frame(s, { Name = "Content", Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 24 })
	K.list(content, false, 6)
	K.pad(content, 0, 0, 2, 12)
	return s, content
end

function FK.clear(frame: Instance)
	for _, c in frame:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

return FK
