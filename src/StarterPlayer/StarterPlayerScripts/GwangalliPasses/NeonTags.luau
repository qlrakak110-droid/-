-- GwangalliPasses/NeonTags (client): the overhead neon nickname of every player whose server attribute
-- GwNeonName names a palette (pass #4). Each viewer draws its own BillboardGui in PlayerGui (Adornee = Head;
-- never parented under a character or map part): the display name in a bold font with an animated UIGradient
-- sweep, a dark outline and a soft glow copy behind it. The server hides the default Humanoid name meanwhile.
-- GwangalliLabelDeclutter hooks: GwLabelClass = "named", GwLabelFocus = true.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local NeonTags = {}

local P: any, K: any, Neon: any, Config: any
local holder: ScreenGui? = nil
local tags: { [Player]: { gui: BillboardGui, grads: { UIGradient }, pal: any, conns: { RBXScriptConnection } } } = {}

local function container(): ScreenGui
	if holder and holder.Parent then
		return holder
	end
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui")
	g.Name = "GwangalliPassesTags"
	g.ResetOnSpawn = false
	g.Parent = pg
	holder = g
	return g
end

local function drop(p: Player)
	local t = tags[p]
	if t then
		for _, c in t.conns do
			c:Disconnect()
		end
		t.gui:Destroy()
		tags[p] = nil
	end
end

local function label(parent: Instance, text: string, pal: any, glow: boolean): (TextLabel, UIGradient)
	local l = Instance.new("TextLabel")
	l.Name = if glow then "Glow" else "Name"
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Font = Enum.Font.GothamBlack
	l.TextScaled = true
	l.Text = text
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextTransparency = if glow then 0.55 else 0
	l.ZIndex = if glow then 1 else 2
	local g = Instance.new("UIGradient")
	g.Color = Neon.sequence(pal)
	g.Parent = l
	local s = Instance.new("UIStroke")
	s.Color = if glow then pal.colors[1] else pal.stroke
	s.Thickness = if glow then 4 else 1.6
	s.Transparency = if glow then 0.75 else 0.15
	s.Parent = l
	l.Parent = parent
	return l, g
end

local function build(p: Player)
	drop(p)
	local id = p:GetAttribute(P.Attr.Neon)
	local pal = Neon.get(id)
	local ch = p.Character
	local head = ch and ch:FindFirstChild("Head")
	if not pal or not head or not head:IsA("BasePart") then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "GwNeonTag_" .. p.UserId
	bb.Adornee = head
	bb.Size = UDim2.fromOffset(230, 30)
	bb.StudsOffset = Vector3.new(0, Config.NEON.TAG_OFFSET, 0)
	bb.MaxDistance = Config.NEON.TAG_DISTANCE
	bb.LightInfluence = 0
	bb.AlwaysOnTop = false
	bb.ResetOnSpawn = false
	bb:SetAttribute("GwLabelClass", "named")
	bb:SetAttribute("GwLabelFocus", true)
	local text = "✦ " .. p.DisplayName
	local _, g1 = label(bb, text, pal, true)
	local _, g2 = label(bb, text, pal, false)
	bb.Parent = container()
	local rec = { gui = bb, grads = { g1, g2 }, pal = pal, conns = {} }
	tags[p] = rec
	table.insert(rec.conns, head.AncestryChanged:Connect(function()
		if not head:IsDescendantOf(workspace) then
			task.defer(function()
				if tags[p] == rec then
					drop(p)
				end
			end)
		end
	end))
end

local function watch(p: Player)
	p:GetAttributeChangedSignal(P.Attr.Neon):Connect(function()
		build(p)
	end)
	p.CharacterAdded:Connect(function(ch: Model)
		ch:WaitForChild("Head", 10)
		build(p)
	end)
	if p.Character then
		task.spawn(function()
			p.Character:WaitForChild("Head", 10)
			build(p)
		end)
	end
end

function NeonTags.start(ctx: any)
	P, K, Config = ctx.P, ctx.K, ctx.P.Config
	Neon = P.mod("Neon")
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(drop)
	RunService.RenderStepped:Connect(function()
		if next(tags) == nil then
			return
		end
		local t = os.clock()
		local reduced = K.reduced()
		for _, rec in tags do
			if not reduced then
				local off = ((t * rec.pal.speed) % 2) - 1
				for _, g in rec.grads do
					g.Offset = Vector2.new(off, 0)
				end
			end
		end
	end)
end

return NeonTags
