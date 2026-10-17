-- GwangalliShopCrew client / Bubbles: speech bubbles over the crew, the diners and the shops' own staff.
-- Uses the place's shared bubble pool when it exists (LocalPlayer.GwangalliBubble, GwangalliBump: the same look as
-- every other NPC), else a small pool of its own BillboardGuis in PlayerGui (Adornee = the head; never parented
-- under map parts).
--   Bubbles.init(ctx)   ctx = { player, gui (PlayerGui), find (id) -> Model? }   Bubbles.say(id, text, dur, tone)

local TweenService = game:GetService("TweenService")

local Bubbles = {}

local ctx: any = nil
local pool: { BillboardGui } = {}
local active: { [Instance]: { gui: BillboardGui, serial: number } } = {}
local serial = 0
local MAX_OWN = 8

local TONE = {
	plain = Color3.fromRGB(255, 255, 255),
	happy = Color3.fromRGB(255, 248, 225),
	busy = Color3.fromRGB(232, 246, 255),
}

function Bubbles.init(c: any)
	ctx = c
end

local function headOf(m: Model): BasePart?
	local h = m:FindFirstChild("Head")
	if h and h:IsA("BasePart") then
		return h
	end
	local r = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
	return if r and r:IsA("BasePart") then r else nil
end

local function makeGui(): BillboardGui
	local g = Instance.new("BillboardGui")
	g.Name = "CrewBubble"
	g.Size = UDim2.fromOffset(230, 64)
	g.StudsOffsetWorldSpace = Vector3.new(0, 3.3, 0)
	g.LightInfluence = 0
	g.MaxDistance = 42
	g.AlwaysOnTop = false
	g.ResetOnSpawn = false
	local f = Instance.new("Frame")
	f.Name = "Box"
	f.AnchorPoint = Vector2.new(0.5, 1)
	f.Position = UDim2.new(0.5, 0, 1, -8)
	f.Size = UDim2.new(1, 0, 1, -8)
	f.AutomaticSize = Enum.AutomaticSize.None
	f.BackgroundColor3 = TONE.plain
	f.BackgroundTransparency = 0.04
	f.Parent = g
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 14)
	c.Parent = f
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(30, 34, 52)
	s.Transparency = 0.82
	s.Thickness = 1
	s.Parent = f
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, -16, 1, -8)
	t.Position = UDim2.fromOffset(8, 4)
	t.Font = Enum.Font.GothamMedium
	t.TextColor3 = Color3.fromRGB(28, 30, 42)
	t.TextWrapped = true
	t.TextScaled = true
	t.Parent = f
	local lim = Instance.new("UITextSizeConstraint")
	lim.MaxTextSize = 17
	lim.MinTextSize = 11
	lim.Parent = t
	local tail = Instance.new("Frame")
	tail.Name = "Tail"
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Position = UDim2.new(0.5, 0, 1, -8)
	tail.Size = UDim2.fromOffset(12, 12)
	tail.Rotation = 45
	tail.BackgroundColor3 = TONE.plain
	tail.BackgroundTransparency = 0.04
	tail.BorderSizePixel = 0
	tail.ZIndex = 0
	tail.Parent = g
	return g
end

local function own(head: BasePart, text: string, dur: number, tone: string?)
	local cur = active[head]
	local g: BillboardGui
	if cur then
		g = cur.gui
	else
		g = table.remove(pool) or makeGui()
		local n = 0
		for _ in active do
			n += 1
		end
		if n >= MAX_OWN then
			-- the oldest bubble makes room
			local oldest, os_ = nil, math.huge
			for k, v in active do
				if v.serial < os_ then
					oldest, os_ = k, v.serial
				end
			end
			if oldest then
				local v = active[oldest]
				active[oldest] = nil
				v.gui.Enabled = false
				v.gui.Adornee = nil
				table.insert(pool, v.gui)
			end
		end
	end
	serial += 1
	local mine = serial
	active[head] = { gui = g, serial = mine }
	local box = g:FindFirstChild("Box") :: Frame
	local col = TONE[tone or "plain"] or TONE.plain
	box.BackgroundColor3 = col
	local tail = g:FindFirstChild("Tail") :: Frame
	tail.BackgroundColor3 = col
	local label = box:FindFirstChild("Text") :: TextLabel
	label.Text = text
	-- width follows the text (one or two lines)
	local len = utf8.len(text) or #text
	g.Size = UDim2.fromOffset(math.clamp(36 + len * 11, 110, 250), if len > 18 then 64 else 44)
	g.Adornee = head
	g.Parent = ctx.gui
	g.Enabled = true
	box.Size = UDim2.new(1, 0, 0, 0)
	TweenService:Create(box, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(1, 0, 1, -8) }):Play()
	task.delay(dur, function()
		local a = active[head]
		if a and a.serial == mine then
			active[head] = nil
			g.Enabled = false
			g.Adornee = nil
			table.insert(pool, g)
		end
	end)
end

function Bubbles.say(id: string, text: string, dur: number?, tone: string?)
	if type(text) ~= "string" or text == "" then
		return
	end
	local m = ctx.find(id)
	if not m then
		return
	end
	local head = headOf(m)
	if not head then
		return
	end
	local secs = math.clamp(tonumber(dur) or 3.6, 1.5, 8)
	local ev = ctx.player:FindFirstChild("GwangalliBubble")
	if ev and ev:IsA("BindableEvent") then
		local ok = pcall(function()
			ev:Fire(head, text, "plain", secs, 3.2)
		end)
		if ok then
			return
		end
	end
	own(head, text, secs, tone)
end

return Bubbles
