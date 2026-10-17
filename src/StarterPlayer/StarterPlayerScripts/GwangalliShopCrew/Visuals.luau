-- GwangalliShopCrew client / Visuals: what the server only describes with attributes.
--   * NAME TAGS over crew rigs (title in the shop's accent colour + name), nearest Config.CLIENT.maxTags within
--     tagDistance. BillboardGuis live in PlayerGui with Adornee = Head (never under map parts).
--   * CARRY (attribute CrewCarry): the tray with real dish replicas (GwangalliBuildingsShared.FoodKit, the same
--     builders ShopLife's tables use), a water pitcher, the menu board, stacked empty bowls, a stock box. Welded
--     to the upper torso (level, like a real tray), built only within propDistance; non-colliding, no shadows.
--   * KITCHEN FX ("cook"): steam / smoke / sparks at the cook's hands + a 조리 중 chip with the countdown.
--   * POINT ("point"): a pin + live distance over a free table or a place (길 묻기), pulsing ring on tables.
--   * KEEPS: our GwCrewSpot parts are registered with the client building interior (GwangalliBuildingInterior
--     Scan.addWorldKeep) so its decor never lands where the staff stands.
--   Visuals.init(ctx)   ctx = { player, gui, Shared, K?, find(id) -> Model?, Net }

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Visuals = {}

local ctx: any = nil
local Shared: any = nil
local Config: any = nil
local Util: any = nil
local FoodKit: any = nil
local SS: any = nil

local rigs: { [Model]: any } = {}
local localRoot: Folder? = nil

local function lroot(): Folder
	if localRoot and localRoot.Parent then
		return localRoot
	end
	local f = workspace:FindFirstChild("GwShopCrewLocal")
	if not f then
		f = Instance.new("Folder")
		f.Name = "GwShopCrewLocal"
		f.Parent = workspace
	end
	localRoot = f :: Folder
	return f :: Folder
end

local function myPos(): Vector3?
	local c = ctx.player.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r.Position else (workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position)
end

local function rgb(s: any, fallback: Color3): Color3
	if type(s) == "string" then
		local r, g, b = string.match(s, "^(%d+),(%d+),(%d+)$")
		if r then
			return Color3.fromRGB(tonumber(r) :: number, tonumber(g) :: number, tonumber(b) :: number)
		end
	end
	return fallback
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-------------------------------------------------------------------------------------------------
-- name tags
-------------------------------------------------------------------------------------------------
local function makeTag(m: Model, head: BasePart): BillboardGui
	local g = Instance.new("BillboardGui")
	g.Name = "CrewTag"
	g.Size = UDim2.fromOffset(170, 38)
	g.StudsOffsetWorldSpace = Vector3.new(0, 1.9, 0)
	g.LightInfluence = 0
	g.MaxDistance = Config.CLIENT.tagDistance
	g.AlwaysOnTop = false
	g.Adornee = head
	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.AnchorPoint = Vector2.new(0.5, 0.5)
	pill.Position = UDim2.fromScale(0.5, 0.5)
	pill.Size = UDim2.new(1, 0, 1, 0)
	pill.BackgroundColor3 = Color3.fromRGB(16, 20, 36)
	pill.BackgroundTransparency = 0.28
	pill.Parent = g
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = pill
	local stroke = Instance.new("UIStroke")
	stroke.Color = rgb(m:GetAttribute(Shared.ATTR.Color), Color3.fromRGB(61, 214, 245))
	stroke.Transparency = 0.35
	stroke.Thickness = 1.5
	stroke.Parent = pill
	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromOffset(32, 38)
	icon.Position = UDim2.fromOffset(4, 0)
	icon.Font = Enum.Font.GothamBold
	icon.TextSize = 18
	icon.Text = tostring(m:GetAttribute(Shared.ATTR.Icon) or "🙂")
	icon.TextColor3 = Color3.new(1, 1, 1)
	icon.Parent = pill
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(36, 3)
	title.Size = UDim2.new(1, -44, 0, 18)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 14
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = stroke.Color:Lerp(Color3.new(1, 1, 1), 0.35)
	title.Text = tostring(m:GetAttribute(Shared.ATTR.Title) or "직원")
	title.Parent = pill
	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromOffset(36, 20)
	name.Size = UDim2.new(1, -44, 0, 14)
	name.Font = Enum.Font.Gotham
	name.TextSize = 11
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextColor3 = Color3.fromRGB(200, 206, 222)
	name.Text = tostring(m:GetAttribute(Shared.ATTR.Name) or "")
	name.Parent = pill
	g.Enabled = false
	g.Parent = ctx.gui
	return g
end

-------------------------------------------------------------------------------------------------
-- carried props
-------------------------------------------------------------------------------------------------
local function anchorPart(m: Model): BasePart?
	local t = m:FindFirstChild("UpperTorso") or m:FindFirstChild("Torso") or m:FindFirstChild("HumanoidRootPart")
	return if t and t:IsA("BasePart") then t else nil
end

local function dishModel(menu: string, id: string, cf: CFrame, parent: Instance): boolean
	if not FoodKit or not SS then
		return false
	end
	local ok, it = pcall(SS.item, menu, id)
	if not ok or type(it) ~= "table" then
		return false
	end
	local ok2, dm = pcall(FoodKit.dish, it, cf, {}, nil)
	if not ok2 or not dm then
		return false
	end
	for _, d in dm:GetDescendants() do
		if d:IsA("BasePart") then
			d.Parent = parent
		end
	end
	dm:Destroy()
	return true
end

-- the carried model, built around `base` (a world CFrame in front of the chest)
local function buildCarry(list: { any }, base: CFrame): (Model?, BasePart?)
	if #list == 0 then
		return nil, nil
	end
	local m = Instance.new("Model")
	m.Name = "CrewCarryProp"
	local kind = list[1].kind
	local holder: BasePart
	if kind == "dish" then
		local n = #list
		local wide = n > 1 or (list[1].qty or 1) > 1
		if wide then
			holder = part(m, "Tray", Vector3.new(2.5, 0.1, 1.5), base, Color3.fromRGB(122, 84, 52), Enum.Material.Wood)
			part(m, "TrayRim", Vector3.new(2.5, 0.16, 0.06), base * CFrame.new(0, 0.05, -0.72), Color3.fromRGB(98, 66, 42), Enum.Material.Wood)
			part(m, "TrayRim", Vector3.new(2.5, 0.16, 0.06), base * CFrame.new(0, 0.05, 0.72), Color3.fromRGB(98, 66, 42), Enum.Material.Wood)
		else
			holder = part(m, "Tray", Vector3.new(0.1, 1.7, 1.7), base * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(70, 52, 40), Enum.Material.Wood, Enum.PartType.Cylinder)
		end
		local slots: { CFrame } = if wide then { base * CFrame.new(-0.62, 0.05, 0), base * CFrame.new(0.62, 0.05, 0), base * CFrame.new(0, 0.05, 0.1) } else { base * CFrame.new(0, 0.05, 0) }
		local k = 0
		for _, c in list do
			if c.kind == "dish" then
				for _ = 1, math.min(c.qty or 1, 2) do
					k += 1
					local slot = slots[k]
					if not slot then
						break
					end
					-- the dish faces whoever the waiter walks toward: lookvector = the waiter's forward
					if not dishModel(c.menu, c.item, slot * CFrame.Angles(0, math.pi, 0), m) then
						part(m, "Bowl", Vector3.new(0.5, 0.95, 0.95), slot * CFrame.new(0, 0.25, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(245, 244, 238), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
					end
				end
			end
		end
	elseif kind == "water" then
		holder = part(m, "Tray", Vector3.new(0.1, 1.5, 1.5), base * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(70, 52, 40), Enum.Material.Wood, Enum.PartType.Cylinder)
		part(m, "Pitcher", Vector3.new(0.95, 0.55, 0.55), base * CFrame.new(-0.3, 0.52, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(205, 210, 214), Enum.Material.Metal, Enum.PartType.Cylinder)
		part(m, "Handle", Vector3.new(0.08, 0.5, 0.18), base * CFrame.new(-0.62, 0.55, 0), Color3.fromRGB(190, 196, 200), Enum.Material.Metal)
		for i, x in { 0.3, 0.42 } do
			part(m, "Cup", Vector3.new(0.4, 0.28, 0.28), base * CFrame.new(x, 0.25, if i == 1 then -0.3 else 0.3) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(198, 200, 204), Enum.Material.Metal, Enum.PartType.Cylinder)
		end
	elseif kind == "menu" then
		holder = part(m, "Menu", Vector3.new(1.1, 1.5, 0.08), base * CFrame.new(0, 0.6, 0.2) * CFrame.Angles(math.rad(-15), 0, 0), Color3.fromRGB(150, 104, 62), Enum.Material.Wood)
		part(m, "Paper", Vector3.new(0.95, 1.3, 0.02), holder.CFrame * CFrame.new(0, 0, -0.05), Color3.fromRGB(246, 238, 220), Enum.Material.SmoothPlastic)
	elseif kind == "empty" then
		holder = part(m, "Tray", Vector3.new(2.2, 0.1, 1.4), base, Color3.fromRGB(122, 84, 52), Enum.Material.Wood)
		for i = 0, 2 do
			part(m, "Bowl", Vector3.new(0.32, 0.85, 0.85), base * CFrame.new(-0.4, 0.2 + i * 0.22, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(240, 238, 232), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		end
		part(m, "Plate", Vector3.new(0.08, 0.9, 0.9), base * CFrame.new(0.55, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(236, 236, 230), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	elseif kind == "box" then
		holder = part(m, "Box", Vector3.new(1.5, 1.0, 1.1), base * CFrame.new(0, 0.35, 0.1), Color3.fromRGB(196, 158, 110), Enum.Material.Cardboard)
		part(m, "Tape", Vector3.new(1.52, 0.04, 0.2), holder.CFrame * CFrame.new(0, 0.5, 0), Color3.fromRGB(170, 140, 96), Enum.Material.SmoothPlastic)
	else
		m:Destroy()
		return nil, nil
	end
	m.PrimaryPart = holder
	return m, holder
end

local OFFSET = {
	dish1 = CFrame.new(-0.35, -0.55, -1.2),
	dish2 = CFrame.new(0, -0.6, -1.25),
	water = CFrame.new(-0.35, -0.55, -1.15),
	menu = CFrame.new(0.35, -0.6, -0.95),
	empty = CFrame.new(0, -0.6, -1.2),
	box = CFrame.new(0, -0.75, -1.05),
}

local function dropCarry(r: any)
	if r.prop then
		r.prop:Destroy()
		r.prop = nil
	end
	r.carryKey = nil
end

local function applyCarry(r: any)
	local m: Model = r.model
	local s = m:GetAttribute(Shared.ATTR.Carry)
	local key = if type(s) == "string" then s else ""
	if key == r.carryKey then
		return
	end
	dropCarry(r)
	r.carryKey = key
	if key == "" or not r.near then
		return
	end
	local list = Util.decodeCarry(key)
	if #list == 0 then
		return
	end
	local anchor = anchorPart(m)
	if not anchor then
		return
	end
	local k = list[1].kind
	local off = if k == "dish" then (if #list > 1 or (list[1].qty or 1) > 1 then OFFSET.dish2 else OFFSET.dish1) else (OFFSET[k] or OFFSET.dish1)
	local base = anchor.CFrame * off
	local prop, holder = buildCarry(list, base)
	if not prop or not holder then
		return
	end
	for _, d in prop:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.Massless = true
			if d ~= holder then
				local w = Instance.new("WeldConstraint")
				w.Part0 = holder
				w.Part1 = d
				w.Parent = d
			end
		end
	end
	local w = Instance.new("WeldConstraint")
	w.Part0 = anchor
	w.Part1 = holder
	w.Parent = holder
	prop.Parent = m
	r.prop = prop
end

-------------------------------------------------------------------------------------------------
-- rigs
-------------------------------------------------------------------------------------------------
local function headOf(m: Model): BasePart?
	local h = m:FindFirstChild("Head")
	return if h and h:IsA("BasePart") then h else nil
end

local function addRig(m: Instance)
	if not m:IsA("Model") or rigs[m] then
		return
	end
	local r: any = { model = m, near = false, carryKey = nil }
	rigs[m] = r
	r.conn = m:GetAttributeChangedSignal(Shared.ATTR.Carry):Connect(function()
		applyCarry(r)
	end)
end

local function removeRig(m: Instance)
	local r = rigs[m :: Model]
	if not r then
		return
	end
	rigs[m :: Model] = nil
	if r.conn then
		r.conn:Disconnect()
	end
	dropCarry(r)
	if r.tag then
		r.tag:Destroy()
	end
end

local function lodStep()
	local me = myPos()
	if not me then
		return
	end
	local list = {}
	for m, r in rigs do
		local root = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
		if root and root:IsA("BasePart") then
			local d = (root.Position - me).Magnitude
			table.insert(list, { r = r, d = d })
		end
	end
	table.sort(list, function(a, b)
		return a.d < b.d
	end)
	local tags, props = 0, 0
	for _, e in list do
		local r = e.r
		local m: Model = r.model
		-- props
		local wantNear = e.d <= Config.CLIENT.propDistance and props < Config.CLIENT.maxProps
		if wantNear then
			props += 1
		end
		if wantNear ~= r.near then
			r.near = wantNear
			r.carryKey = "\0" -- force a rebuild / drop
			applyCarry(r)
		end
		-- tags (crew only: diners have no title)
		local title = m:GetAttribute(Shared.ATTR.Title)
		if type(title) == "string" and title ~= "" then
			local want = e.d <= Config.CLIENT.tagDistance and tags < Config.CLIENT.maxTags
			if want then
				tags += 1
				if not r.tag then
					local head = headOf(m)
					if head then
						r.tag = makeTag(m, head)
					end
				end
				if r.tag then
					r.tag.Enabled = true
				end
			elseif r.tag then
				r.tag.Enabled = false
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- kitchen fx
-------------------------------------------------------------------------------------------------
local FX_STYLE = {
	boil = "steam",
	steam = "steam",
	pot = "steam",
	soup = "steam",
	espresso = "steam",
	pour = "steam",
	fry = "smoke",
	wok = "smoke",
	grill = "sparks",
	flip = "sparks",
	toast = "smoke",
}

local cookChips: { [string]: any } = {}

local function emitter(parent: Instance, style: string): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.LightEmission = 0.05
	e.Rate = 7
	e.Lifetime = NumberRange.new(1.4, 2.2)
	e.Speed = NumberRange.new(1.2, 2.2)
	e.SpreadAngle = Vector2.new(12, 12)
	e.Acceleration = Vector3.new(0, 1.2, 0)
	e.RotSpeed = NumberRange.new(-30, 30)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1.6) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(0.6, 0.8), NumberSequenceKeypoint.new(1, 1) })
	e.Color = ColorSequence.new(Color3.fromRGB(245, 245, 245))
	e.EmissionDirection = Enum.NormalId.Top
	if style == "smoke" then
		e.Color = ColorSequence.new(Color3.fromRGB(150, 146, 140))
		e.Rate = 9
	elseif style == "sparks" then
		e.Color = ColorSequence.new(Color3.fromRGB(160, 150, 140))
		local sp = Instance.new("ParticleEmitter")
		sp.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sp.LightEmission = 0.9
		sp.Rate = 6
		sp.Lifetime = NumberRange.new(0.3, 0.7)
		sp.Speed = NumberRange.new(2, 4)
		sp.SpreadAngle = Vector2.new(30, 30)
		sp.Size = NumberSequence.new(0.12)
		sp.Color = ColorSequence.new(Color3.fromRGB(255, 160, 60))
		sp.EmissionDirection = Enum.NormalId.Top
		sp.Parent = parent
	end
	e.Parent = parent
	return e
end

local function onCook(d: any)
	local m = ctx.find(tostring(d.id))
	if not m then
		return
	end
	local head = headOf(m)
	local root = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
	if not head or not root then
		return
	end
	local secs = math.clamp(tonumber(d.seconds) or 8, 1, 120)
	local look = (root :: BasePart).CFrame.LookVector
	local at = head.Position + Vector3.new(look.X, 0, look.Z).Unit * 1.3 - Vector3.new(0, 1.3, 0)
	local holder = part(lroot(), "CookFx", Vector3.new(0.6, 0.2, 0.6), CFrame.new(at), Color3.new(1, 1, 1))
	holder.Transparency = 1
	emitter(holder, FX_STYLE[tostring(d.fx)] or "steam")
	task.delay(secs + 0.5, function()
		for _, e in holder:GetChildren() do
			if e:IsA("ParticleEmitter") then
				e.Enabled = false
			end
		end
		task.delay(2.5, function()
			holder:Destroy()
		end)
	end)
	-- the 조리 중 chip (one per cook, the newest order wins)
	local id = tostring(d.id)
	local old = cookChips[id]
	if old then
		old.gui:Destroy()
	end
	local g = Instance.new("BillboardGui")
	g.Name = "CrewCookChip"
	g.Size = UDim2.fromOffset(150, 30)
	g.StudsOffsetWorldSpace = Vector3.new(0, 4.4, 0)
	g.LightInfluence = 0
	g.MaxDistance = 36
	g.Adornee = head
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = Color3.fromRGB(28, 22, 18)
	f.BackgroundTransparency = 0.2
	f.Parent = g
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = f
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BackgroundColor3 = Color3.fromRGB(255, 176, 32)
	bar.BackgroundTransparency = 0.15
	bar.Size = UDim2.new(0, 0, 0, 3)
	bar.Position = UDim2.new(0, 10, 1, -5)
	bar.Parent = f
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, -12, 1, -4)
	t.Position = UDim2.fromOffset(6, 0)
	t.Font = Enum.Font.GothamBold
	t.TextSize = 12
	t.TextColor3 = Color3.fromRGB(255, 240, 220)
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Parent = f
	g.Parent = ctx.gui
	local chip = { gui = g }
	cookChips[id] = chip
	local t0 = os.clock()
	local item = tostring(d.item or "")
	task.spawn(function()
		while g.Parent do
			local left = math.max(0, secs - (os.clock() - t0))
			t.Text = string.format("%s %s 조리 중 · %d초", tostring(d.icon or "🍳"), item, math.ceil(left))
			bar.Size = UDim2.new((1 - left / secs) * (1 - 20 / 150), 0, 0, 3)
			if left <= 0 then
				t.Text = string.format("%s %s 완성!", tostring(d.icon or "🍳"), item)
				task.wait(1.6)
				break
			end
			task.wait(0.25)
		end
		if cookChips[id] == chip then
			cookChips[id] = nil
		end
		g:Destroy()
	end)
end

-------------------------------------------------------------------------------------------------
-- point markers
-------------------------------------------------------------------------------------------------
local pointSerial = 0
local function onPoint(d: any)
	local pos = d.pos
	if typeof(pos) ~= "Vector3" then
		return
	end
	pointSerial += 1
	local mine = pointSerial
	for _, ch in lroot():GetChildren() do
		if ch.Name == "CrewPoint" then
			ch:Destroy()
		end
	end
	local secs = math.clamp(tonumber(d.seconds) or 8, 2, 60)
	local p = part(lroot(), "CrewPoint", Vector3.new(0.2, 0.2, 0.2), CFrame.new(pos + Vector3.new(0, 0.2, 0)), Color3.new(1, 1, 1))
	p.Transparency = 1
	local ring: Part? = nil
	if d.kind == "table" then
		ring = part(p, "Ring", Vector3.new(0.06, 4.2, 4.2), CFrame.new(pos + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(61, 214, 245), Enum.Material.Neon, Enum.PartType.Cylinder)
		ring.Transparency = 0.55
	end
	local g = Instance.new("BillboardGui")
	g.Name = "CrewPointGui"
	g.Size = UDim2.fromOffset(150, 52)
	g.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
	g.AlwaysOnTop = true
	g.LightInfluence = 0
	g.Adornee = p
	local pin = Instance.new("TextLabel")
	pin.BackgroundTransparency = 1
	pin.Size = UDim2.new(1, 0, 0, 26)
	pin.Font = Enum.Font.GothamBold
	pin.TextSize = 24
	pin.Text = "📍"
	pin.Parent = g
	local lab = Instance.new("TextLabel")
	lab.Position = UDim2.fromOffset(0, 26)
	lab.Size = UDim2.new(1, 0, 0, 24)
	lab.BackgroundColor3 = Color3.fromRGB(16, 20, 36)
	lab.BackgroundTransparency = 0.25
	lab.Font = Enum.Font.GothamBold
	lab.TextSize = 13
	lab.TextColor3 = Color3.new(1, 1, 1)
	lab.Parent = g
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = lab
	g.Parent = ctx.gui
	local t0 = os.clock()
	task.spawn(function()
		while os.clock() - t0 < secs and mine == pointSerial and p.Parent do
			local me = myPos()
			local dist = if me then (me - pos).Magnitude else 0
			lab.Text = string.format("%s · %s", tostring(d.label or "여기"), Util.meters(dist))
			local k = 0.5 + 0.5 * math.sin((os.clock() - t0) * 5)
			pin.Position = UDim2.fromOffset(0, -4 * k)
			if ring then
				ring.Transparency = 0.35 + 0.4 * k
			end
			task.wait(0.05)
		end
		g:Destroy()
		p:Destroy()
	end)
end

-------------------------------------------------------------------------------------------------
-- interior keep zones
-------------------------------------------------------------------------------------------------
local keepScan: any = nil
local kept: { [Instance]: boolean } = {}
local function interiorScan(): any?
	if keepScan ~= nil then
		return keepScan or nil
	end
	local ps = ctx.player:FindFirstChildOfClass("PlayerScripts")
	local li = ps and ps:FindFirstChild("GwangalliBuildingInterior")
	local sm = li and li:FindFirstChild("Scan")
	if sm and sm:IsA("ModuleScript") then
		local ok, S = pcall(require, sm)
		if ok and type(S) == "table" and type(S.addWorldKeep) == "function" then
			keepScan = S
			return S
		end
	end
	keepScan = false
	return nil
end

local function keepSpot(p: Instance)
	if kept[p] or not p:IsA("BasePart") or not Config.CLIENT.keeps then
		return
	end
	local S = interiorScan()
	if not S then
		return
	end
	kept[p] = true
	local r = tonumber(p:GetAttribute("Radius")) or 1.2
	local c = p.Position
	pcall(S.addWorldKeep, Vector3.new(c.X - r, c.Y - 0.2, c.Z - r), Vector3.new(c.X + r, c.Y + 5.5, c.Z + r), "crew")
end

-------------------------------------------------------------------------------------------------
function Visuals.init(c: any)
	ctx = c
	Shared = c.Shared
	Config = Shared.Config
	Util = Shared.Util
	local shared = ReplicatedStorage:FindFirstChild("GwangalliBuildingsShared")
	if shared and shared:IsA("ModuleScript") then
		local ok, S = pcall(require, shared)
		if ok and type(S) == "table" then
			FoodKit = S.FoodKit
			SS = S.StreetShops
		end
	end
	for _, m in CollectionService:GetTagged(Shared.TAG) do
		addRig(m)
	end
	CollectionService:GetInstanceAddedSignal(Shared.TAG):Connect(addRig)
	CollectionService:GetInstanceRemovedSignal(Shared.TAG):Connect(removeRig)
	c.Net.on("cook", onCook)
	c.Net.on("point", onPoint)
	-- keep zones: the interior script may start after us; retry for a while
	task.spawn(function()
		for _ = 1, 30 do
			if interiorScan() then
				break
			end
			keepScan = nil
			task.wait(4)
		end
		for _, p in CollectionService:GetTagged(Shared.SPOT_TAG) do
			keepSpot(p)
		end
		CollectionService:GetInstanceAddedSignal(Shared.SPOT_TAG):Connect(keepSpot)
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.5 then
			acc = 0
			local ok, err = pcall(lodStep)
			if not ok then
				warn("[GwangalliShopCrew] visuals: " .. tostring(err))
			end
		end
	end)
end

return Visuals
