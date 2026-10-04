-- GwangalliProgress/Celebrate: 인생 레벨 UP fanfare and the big-purchase milestones (첫 차 / 내 집 /
-- VIP 테이블 ...). A gold banner drops into the top band (the toast slot: never the centre of the
-- screen), unlock chips slide in under it, confetti bursts from it, and a milestone adds a short camera
-- pull-back. One banner at a time; they wait (up to 12 s) while the HUD is hidden.

local Celebrate = {}

local C: any = nil
local K: any = nil
local P: any = nil

local banner: Frame? = nil
local bannerScale: UIScale
local chips: Frame
local queue: { any } = {}
local busy = false
local BANNER_W, BANNER_H = 330, 66

local function build()
	local b = K.frame(C.fx, { Name = "CelebrateBanner", AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(BANNER_W, BANNER_H), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), Visible = false, ZIndex = 40 })
	bannerScale = K.make("UIScale", { Scale = 1 }, b)
	K.corner(b, K.Radius.lg)
	K.gradient(b, { Color3.fromRGB(58, 40, 8), Color3.fromRGB(26, 20, 10) }, 90)
	K.stroke(b, K.Color.gold, 2, 0.1)
	local glow = K.frame(b, { Name = "Glow", Size = UDim2.new(1, 0, 0.5, 0), BackgroundTransparency = 0.82, BackgroundColor3 = K.Color.gold, ZIndex = 40 })
	K.corner(glow, K.Radius.lg)
	local medal = K.frame(b, { Name = "Medal", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(46, 46), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 41 })
	K.corner(medal, UDim.new(0.5, 0))
	K.gradient(medal, K.Grad.gold, 125)
	K.stroke(medal, Color3.fromRGB(255, 240, 190), 2, 0.2)
	K.make("UIScale", { Scale = 1 }, medal)
	K.text(medal, { Name = "Glyph", Size = UDim2.fromScale(1, 1), Text = "⭐", TextSize = 22, Font = K.Font.heavy, TextColor3 = K.Color.onGold, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 42 })
	K.text(b, { Name = "Kicker", Position = UDim2.fromOffset(66, 9), Size = UDim2.new(1, -76, 0, 14), Text = "인생 레벨 UP!", Font = K.Font.heavy, TextSize = 12, TextColor3 = K.Color.gold, ZIndex = 41 })
	K.text(b, { Name = "Title", Position = UDim2.fromOffset(66, 24), Size = UDim2.new(1, -76, 0, 22), Text = "", Font = K.Font.heavy, TextSize = 18, ZIndex = 41, TextTruncate = Enum.TextTruncate.AtEnd })
	K.text(b, { Name = "Sub", Position = UDim2.fromOffset(66, 46), Size = UDim2.new(1, -76, 0, 14), Text = "", TextSize = 11, TextColor3 = Color3.fromRGB(255, 226, 170), ZIndex = 41, TextTruncate = Enum.TextTruncate.AtEnd })
	chips = K.frame(b, { Name = "Unlocks", Position = UDim2.new(0, 0, 1, 6), Size = UDim2.new(1, 0, 0, 26), ZIndex = 40 })
	K.list(chips, true, 6, Enum.HorizontalAlignment.Center)
	banner = b
end

local function place()
	if not banner then
		return
	end
	local m = C.Layout.metrics()
	local r = C.Layout.rect("toasts")
	local w = math.min(r.w, math.floor(BANNER_W * m.s))
	local scale = math.min(m.s, w / BANNER_W)
	bannerScale.Scale = scale
	banner.Position = UDim2.fromOffset(r.x + r.w / 2, r.y + 2)
end

local function unlockChip(u: any, i: number): Frame
	local f = K.frame(chips, { Name = "Unlock" .. i, Size = UDim2.fromOffset(10, 24), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 0.06, BackgroundColor3 = K.Color.glass2, LayoutOrder = i, ZIndex = 41 })
	K.corner(f, UDim.new(0.5, 0))
	K.stroke(f, K.Color.gold, 1, 0.4)
	K.pad(f, 10, 10, 0, 0)
	K.text(f, { Name = "Text", Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Text = string.format("🔓 %s %s", tostring(u.icon or ""), tostring(u.name or "")), TextSize = 12, Font = K.Font.bold, ZIndex = 42 })
	local sc = K.make("UIScale", { Scale = 0.92 }, f)
	f.BackgroundTransparency = 1
	K.tweenD(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0.45 + i * 0.16)
	K.tweenD(f, 0.2, { BackgroundTransparency = 0.06 }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0.45 + i * 0.16)
	return f
end

local function present(item: any)
	if not banner then
		build()
	end
	local b = banner :: Frame
	place()
	for _, ch in chips:GetChildren() do
		if ch:IsA("Frame") then
			ch:Destroy()
		end
	end
	local kicker = b:FindFirstChild("Kicker") :: TextLabel
	local title = b:FindFirstChild("Title") :: TextLabel
	local sub = b:FindFirstChild("Sub") :: TextLabel
	local medal = b:FindFirstChild("Medal") :: Frame
	local glyph = medal:FindFirstChild("Glyph") :: TextLabel
	local dur = 3.6
	if item.kind == "level" then
		local d = item.data
		kicker.Text = "인생 레벨 UP!"
		title.Text = string.format("Lv.%d  %s", tonumber(d.level) or 1, tostring(d.title or ""))
		local unlocks = d.unlocks or {}
		sub.Text = if #unlocks > 0 then "새로 열린 혜택이 있어요" else "계속 벌면 다음 레벨!"
		glyph.Text = tostring(d.level or "")
		glyph.TextSize = 20
		for i, u in unlocks do
			if i > 2 then
				break
			end
			unlockChip(u, i)
		end
		dur = if #unlocks > 0 then 4.2 else 3.4
	else
		local d = item.data
		kicker.Text = "🎉 축하해요!"
		title.Text = tostring(d.title or "")
		sub.Text = tostring(d.body or "")
		glyph.Text = tostring(d.icon or "🎉")
		glyph.TextSize = 22
		dur = 4.2
	end
	-- enter: drop + overshoot
	local target = bannerScale.Scale
	bannerScale.Scale = target * 0.7
	local pos = b.Position
	b.Position = pos - UDim2.fromOffset(0, 30)
	b.Visible = true
	K.tween(b, 0.3, { Position = pos }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	K.tween(bannerScale, 0.34, { Scale = target }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local ms = medal:FindFirstChildOfClass("UIScale") :: UIScale
	ms.Scale = 0.6
	K.tweenD(ms, 0.4, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0.12)
	K.sheen(b, { duration = 1.0, delay = 0.3, strength = 0.45 })
	C.Sfx.fanfare()
	pcall(K.haptic, "success")
	local cx = pos.X.Offset
	local cy = pos.Y.Offset + BANNER_H * target * 0.5
	if C.Fx then
		task.delay(0.15, function()
			C.Fx.confetti(cx, cy, if item.kind == "level" then 26 else 40, if item.kind == "level" then 150 else 200)
			C.Sfx.confetti()
		end)
		if item.kind == "ms" and item.data.camera then
			C.Fx.pullBack()
		end
	end
	if C.Chip then
		C.Chip.bump(true)
	end
	task.delay(dur, function()
		K.tween(b, 0.22, { Position = pos - UDim2.fromOffset(0, 24) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		K.tween(bannerScale, 0.22, { Scale = target * 0.9 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		task.delay(0.24, function()
			b.Visible = false
			b.Position = pos
			busy = false
			Celebrate.next()
		end)
	end)
end

function Celebrate.next()
	if busy then
		return
	end
	local item = queue[1]
	if not item then
		return
	end
	if not C.visible() and os.clock() - item.t < 12 then
		task.delay(1, Celebrate.next)
		return
	end
	table.remove(queue, 1)
	busy = true
	local ok, err = pcall(present, item)
	if not ok then
		warn("[GwangalliProgress] celebrate: " .. tostring(err))
		busy = false
	end
end

local function push(kind: string, data: any)
	table.insert(queue, { kind = kind, data = data, t = os.clock() })
	while #queue > 4 do
		table.remove(queue, 1)
	end
	Celebrate.next()
end

function Celebrate.init(c: any)
	C = c
	K = c.K
	P = c.P
	c.on("level", function(msg)
		push("level", msg)
	end)
	c.on("ms", function(msg)
		push("ms", msg)
	end)
	c.on("layout", place)
	c.on("visible", function(v)
		if v then
			task.delay(0.6, Celebrate.next)
		end
	end)
end

return Celebrate
