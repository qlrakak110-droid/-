--!nocheck
-- GwangalliGameplay/WorkProps: the PHYSICAL things of the 알바 simulation — cups, pitchers, boxes,
-- products, dishes, bags — built from plain parts on the server so every player sees them.
--   * every item is a Model whose PrimaryPart "Base" is the bottom centre; the other parts are welded
--     to it, never collide, never query (they can't trap a character)
--   * in a hand: Base is unanchored and welded to the RightHand (R15) / Right Arm (R6) with a grip
--     offset per item kind, so it moves with the arm; on a station it is anchored at the slot CFrame
--   * item visuals are rebuilt from the item state (Props.refresh) whenever the state changes:
--     cup liquid height / colour, ice cubes, lid, the order number sticker
-- Asset swap: replace the builders below with MeshParts (docs/WORK_SIM.md "필요한 자산"); keep the
-- Base part contract and the attribute ItemId.

local Debris = game:GetService("Debris")

local Props = {}

local C: any
local WS: any

function Props.init(cfg: any, ws: any)
	C = cfg
	WS = ws
end

local function rgb(t: { number }?): Color3
	if not t then
		return Color3.new(1, 1, 1)
	end
	return Color3.fromRGB(t[1], t[2], t[3])
end
Props.rgb = rgb

-- a plain non-colliding part
function Props.part(parent: Instance?, name: string, size: Vector3, cf: CFrame, color: Color3, opts: any?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = (opts and opts.material) or Enum.Material.SmoothPlastic
	p.Transparency = (opts and opts.transparency) or 0
	p.Anchored = if opts and opts.anchored ~= nil then opts.anchored else true
	p.CanCollide = opts and opts.collide or false
	p.CanQuery = opts and opts.query or false
	p.CanTouch = false
	p.CastShadow = opts and opts.shadow or false
	p.Massless = true
	if opts and opts.shape then
		p.Shape = opts.shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if parent then
		p.Parent = parent
	end
	return p
end

-- vertical cylinder centred at `center` (Roblox cylinders run along X)
function Props.cylinder(parent: Instance?, name: string, height: number, diameter: number, center: Vector3, color: Color3, opts: any?): Part
	local o = opts or {}
	o.shape = Enum.PartType.Cylinder
	return Props.part(parent, name, Vector3.new(height, diameter, diameter), CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2), color, o)
end

-- billboard label (order numbers, station names, stock counts)
function Props.label(adornee: BasePart, text: string, opts: any?): TextLabel
	local o = opts or {}
	local bb = adornee:FindFirstChild(o.name or "WorkLabel") :: BillboardGui?
	if not bb then
		bb = Instance.new("BillboardGui")
		bb.Name = o.name or "WorkLabel"
		bb.Size = o.size or UDim2.fromOffset(64, 22)
		bb.StudsOffset = o.offset or Vector3.new(0, 1, 0)
		bb.MaxDistance = o.maxDistance or 30
		bb.AlwaysOnTop = o.onTop == true
		bb.LightInfluence = 0
		local t = Instance.new("TextLabel")
		t.Name = "Text"
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundColor3 = o.bg or Color3.fromRGB(20, 24, 34)
		t.BackgroundTransparency = if o.bg == false then 1 else (o.bgTransparency or 0.2)
		t.TextColor3 = o.color or Color3.new(1, 1, 1)
		t.Font = Enum.Font.GothamBold
		t.TextScaled = true
		t.Parent = bb
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = t
		bb.Parent = adornee
	end
	local t = (bb :: BillboardGui):FindFirstChild("Text") :: TextLabel
	t.Text = text
	if o.color then
		t.TextColor3 = o.color
	end
	(bb :: BillboardGui).Enabled = text ~= ""
	return t
end

-- a surface text on a part face (screens, signs)
function Props.screen(part: BasePart, text: string, opts: any?): TextLabel
	local o = opts or {}
	local gui = part:FindFirstChild("WorkScreen") :: SurfaceGui?
	if not gui then
		gui = Instance.new("SurfaceGui")
		gui.Name = "WorkScreen"
		gui.Face = o.face or Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = o.ppu or 50
		gui.MaxDistance = o.maxDistance or 45
		gui.LightInfluence = 0
		local t = Instance.new("TextLabel")
		t.Name = "Text"
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.TextScaled = true
		t.TextWrapped = true
		t.Font = Enum.Font.GothamBold
		t.TextColor3 = o.color or Color3.new(1, 1, 1)
		t.Parent = gui
		gui.Parent = part
	end
	local t = (gui :: SurfaceGui):FindFirstChild("Text") :: TextLabel
	t.Text = text
	if o.color then
		t.TextColor3 = o.color
	end
	return t
end

-------------------------------------------------------------------------------------------------
-- Sounds (one-shot, on a part so they are 3D and everyone nearby hears them)
-------------------------------------------------------------------------------------------------
function Props.sound(at: Instance?, key: string, volume: number?, speed: number?)
	if not at or not C or not C.SOUNDS[key] or C.SOUNDS[key] == "" then
		return
	end
	local s = Instance.new("Sound")
	s.Name = "WorkSfx_" .. key
	s.SoundId = C.SOUNDS[key]
	s.Volume = volume or 0.6
	s.PlaybackSpeed = speed or 1
	s.RollOffMaxDistance = 60
	s.RollOffMinDistance = 6
	s.Parent = at
	s:Play()
	Debris:AddItem(s, 4)
end

-- a looping sound while a machine runs (returns a stop function)
function Props.loop(at: Instance, key: string, volume: number?, speed: number?): () -> ()
	if not C or not C.SOUNDS[key] or C.SOUNDS[key] == "" then
		return function() end
	end
	local s = Instance.new("Sound")
	s.Name = "WorkLoop_" .. key
	s.SoundId = C.SOUNDS[key]
	s.Volume = volume or 0.4
	s.PlaybackSpeed = speed or 1
	s.Looped = true
	s.RollOffMaxDistance = 50
	s.RollOffMinDistance = 6
	s.Parent = at
	s:Play()
	return function()
		if s.Parent then
			s:Stop()
			s:Destroy()
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Item models
-------------------------------------------------------------------------------------------------
local function newModel(item: any): (Model, BasePart)
	local m = Instance.new("Model")
	m.Name = "WorkItem_" .. tostring(item.kind)
	m:SetAttribute("ItemId", item.id)
	m:SetAttribute("WorkItem", item.kind)
	local base = Props.part(m, "Base", Vector3.new(0.2, 0.05, 0.2), CFrame.new(), Color3.new(1, 1, 1), { transparency = 1 })
	m.PrimaryPart = base
	return m, base
end

-- weld every other part to Base, keeping the current relative placement. Only Base is ever anchored:
-- an assembly with several anchored members is undefined (and hangs the studio's assembly solver).
local function weldAll(m: Model)
	local base = m.PrimaryPart
	if not base then
		return
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and d ~= base then
			if not d:FindFirstChild("WorkWeld") then
				local w = Instance.new("WeldConstraint")
				w.Name = "WorkWeld"
				w.Part0 = base
				w.Part1 = d
				w.Parent = d
			end
			d.Anchored = false
			d.Massless = true
		end
	end
end

-- clears the visual parts (keeps Base and the sticker label)
local function clearVisual(m: Model)
	for _, c in m:GetChildren() do
		if c:IsA("BasePart") and c.Name ~= "Base" then
			c:Destroy()
		end
	end
end

local CUP_DIM = { tall = { h = 1.0, d = 0.66 }, grande = { h = 1.22, d = 0.74 } }

-- liquid colour of the cup contents (shots weigh more)
local function mixColor(parts: { string }): (Color3?, number)
	local r, g, b, w = 0, 0, 0, 0
	local liquids = 0
	for _, id in parts do
		local ing = WS.INGREDIENTS[id]
		if ing and ing.liquid then
			local weight = if id == "shot" then 1.6 elseif ing.syrup then 0.4 else 1
			r += ing.color[1] * weight
			g += ing.color[2] * weight
			b += ing.color[3] * weight
			w += weight
			liquids += if ing.syrup then 0.3 else 1
		end
	end
	if w == 0 then
		return nil, 0
	end
	return Color3.fromRGB(math.floor(r / w), math.floor(g / w), math.floor(b / w)), liquids
end

local function buildCup(item: any, m: Model, base: BasePart)
	local dim = CUP_DIM[item.size] or CUP_DIM.tall
	local o = base.CFrame.Position
	local iced = item.temp == "ice"
	local body = Props.cylinder(m, "Body", dim.h, dim.d, o + Vector3.new(0, dim.h / 2, 0), if iced then Color3.fromRGB(225, 238, 245) else Color3.fromRGB(244, 240, 230), { transparency = if iced then 0.55 else 0, material = if iced then Enum.Material.Glass else Enum.Material.SmoothPlastic, anchored = false })
	if not iced then
		Props.cylinder(m, "Sleeve", dim.h * 0.36, dim.d + 0.03, o + Vector3.new(0, dim.h * 0.48, 0), Color3.fromRGB(150, 105, 62), { anchored = false, material = Enum.Material.Cardboard })
	end
	local color, liquids = mixColor(item.parts or {})
	local expected = 3
	if item.spec then
		expected = 0
		for id, n in WS.cafeRecipe(item.spec).need do
			local ing = WS.INGREDIENTS[id]
			if ing and ing.liquid then
				expected += if ing.syrup then 0.3 * n else n
			end
		end
		expected = math.max(1, expected)
	end
	if color and liquids > 0 then
		local frac = math.clamp(liquids / expected, 0.12, 1)
		local fh = (dim.h - 0.08) * frac
		Props.cylinder(m, "Fill", fh, dim.d - 0.08, o + Vector3.new(0, 0.04 + fh / 2, 0), color, { anchored = false, transparency = if iced then 0.1 else 0 })
	end
	local ice = 0
	for _, id in item.parts or {} do
		if id == "ice" then
			ice += 1
		end
	end
	if ice > 0 then
		for i = 1, 3 do
			local a = i * 2.1
			Props.part(m, "Ice", Vector3.new(0.2, 0.2, 0.2), CFrame.new(o + Vector3.new(math.cos(a) * 0.14, dim.h * (0.55 + i * 0.1), math.sin(a) * 0.14)) * CFrame.Angles(a, a * 0.7, 0), Color3.fromRGB(235, 248, 255), { anchored = false, transparency = 0.25, material = Enum.Material.Glass })
		end
	end
	if item.lid then
		Props.cylinder(m, "Lid", 0.08, dim.d + 0.06, o + Vector3.new(0, dim.h + 0.04, 0), if iced then Color3.fromRGB(235, 240, 245) else Color3.fromRGB(255, 255, 255), { anchored = false, transparency = if iced then 0.3 else 0 })
		if iced then
			Props.cylinder(m, "Straw", 0.7, 0.07, o + Vector3.new(0.12, dim.h + 0.3, 0), Color3.fromRGB(20, 110, 70), { anchored = false })
		end
	end
	if item.spilled then
		local bc = m:FindFirstChild("Body") :: BasePart?
		if bc then
			bc.Color = Color3.fromRGB(150, 120, 90)
		end
	end
end

local function buildPitcher(item: any, m: Model, base: BasePart)
	local o = base.CFrame.Position
	Props.cylinder(m, "Body", 0.8, 0.55, o + Vector3.new(0, 0.4, 0), Color3.fromRGB(200, 205, 210), { material = Enum.Material.Metal, anchored = false })
	Props.part(m, "PitcherHandle", Vector3.new(0.08, 0.45, 0.25), CFrame.new(o + Vector3.new(0.34, 0.45, 0)), Color3.fromRGB(180, 185, 190), { material = Enum.Material.Metal, anchored = false })
	if item.milk and item.milk ~= "empty" then
		local c = if item.milk == "burnt" then Color3.fromRGB(200, 170, 120) else Color3.fromRGB(250, 248, 240)
		Props.cylinder(m, "Milk", 0.06, 0.5, o + Vector3.new(0, 0.62, 0), c, { anchored = false })
		if item.milk == "foam" then
			Props.cylinder(m, "Foam", 0.12, 0.5, o + Vector3.new(0, 0.72, 0), Color3.fromRGB(255, 255, 255), { anchored = false, material = Enum.Material.Sand })
		end
	end
end

local function buildBox(item: any, m: Model, base: BasePart)
	local o = base.CFrame.Position
	local size = item.boxSize or Vector3.new(1.6, 1.0, 1.1)
	Props.part(m, "Body", size, CFrame.new(o + Vector3.new(0, size.Y / 2, 0)), rgb(item.color or { 196, 160, 110 }), { material = Enum.Material.Cardboard, anchored = false })
	Props.part(m, "Tape", Vector3.new(0.25, size.Y + 0.02, size.Z + 0.02), CFrame.new(o + Vector3.new(0, size.Y / 2, 0)), Color3.fromRGB(150, 110, 60), { anchored = false })
	local top = Props.part(m, "Top", Vector3.new(size.X * 0.9, 0.02, size.Z * 0.9), CFrame.new(o + Vector3.new(0, size.Y + 0.011, 0)), rgb(item.color or { 196, 160, 110 }), { anchored = false, transparency = 1 })
	if item.text then
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Top
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.MaxDistance = 30
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.TextScaled = true
		t.Font = Enum.Font.GothamBold
		t.TextColor3 = Color3.fromRGB(40, 30, 20)
		t.Text = item.text
		t.Parent = gui
		gui.Parent = top
	end
end

local function buildSmall(item: any, m: Model, base: BasePart)
	-- products / rags / receipts / generic small things
	local o = base.CFrame.Position
	local size = item.size3 or Vector3.new(0.5, 0.7, 0.35)
	local color = rgb(item.color or { 220, 220, 220 })
	if item.shape == "can" then
		Props.cylinder(m, "Body", size.Y, size.X, o + Vector3.new(0, size.Y / 2, 0), color, { anchored = false, material = Enum.Material.Metal })
	elseif item.shape == "bottle" then
		Props.cylinder(m, "Body", size.Y * 0.75, size.X, o + Vector3.new(0, size.Y * 0.375, 0), color, { anchored = false, transparency = 0.2 })
		Props.cylinder(m, "Cap", size.Y * 0.2, size.X * 0.45, o + Vector3.new(0, size.Y * 0.85, 0), Color3.fromRGB(240, 240, 240), { anchored = false })
	else
		Props.part(m, "Body", size, CFrame.new(o + Vector3.new(0, size.Y / 2, 0)), color, { anchored = false, material = item.material or Enum.Material.SmoothPlastic })
	end
end

local function buildDish(item: any, m: Model, base: BasePart)
	local o = base.CFrame.Position
	local plate = item.plate or "plate"
	if plate == "pot" then
		Props.cylinder(m, "Body", 0.7, 1.3, o + Vector3.new(0, 0.35, 0), Color3.fromRGB(60, 60, 64), { anchored = false, material = Enum.Material.Metal })
		if item.food then
			Props.cylinder(m, "Food", 0.08, 1.15, o + Vector3.new(0, 0.62, 0), rgb(item.foodColor or { 200, 60, 30 }), { anchored = false })
		end
	elseif plate == "pan" then
		Props.cylinder(m, "Body", 0.12, 1.4, o + Vector3.new(0, 0.06, 0), Color3.fromRGB(45, 45, 48), { anchored = false, material = Enum.Material.Metal })
		if item.food then
			Props.cylinder(m, "Food", 0.1, 1.1, o + Vector3.new(0, 0.17, 0), rgb(item.foodColor or { 230, 190, 110 }), { anchored = false })
		end
	elseif plate == "board" then
		Props.part(m, "Body", Vector3.new(1.6, 0.12, 1.0), CFrame.new(o + Vector3.new(0, 0.06, 0)), Color3.fromRGB(196, 160, 112), { anchored = false, material = Enum.Material.Wood })
		for i = 1, math.clamp(item.slices or 0, 0, 8) do
			Props.part(m, "Slice", Vector3.new(0.16, 0.06, 0.55), CFrame.new(o + Vector3.new(-0.6 + i * 0.15, 0.15, 0)), Color3.fromRGB(240, 150, 140), { anchored = false })
		end
		if item.fish then
			Props.part(m, "Fish", Vector3.new(math.max(0.2, 1.2 - (item.slices or 0) * 0.15), 0.22, 0.45), CFrame.new(o + Vector3.new(0.25, 0.23, 0)), Color3.fromRGB(235, 140, 130), { anchored = false })
		end
	else
		local dirty = item.dirty == true
		Props.cylinder(m, "Body", 0.08, 1.2, o + Vector3.new(0, 0.04, 0), if dirty then Color3.fromRGB(205, 200, 190) else Color3.fromRGB(250, 250, 248), { anchored = false })
		if item.food then
			Props.cylinder(m, "Food", 0.18, 0.85, o + Vector3.new(0, 0.17, 0), rgb(item.foodColor or { 230, 130, 120 }), { anchored = false })
		end
		if item.garnish then
			Props.part(m, "Garnish", Vector3.new(0.3, 0.12, 0.3), CFrame.new(o + Vector3.new(0.25, 0.3, 0.15)), Color3.fromRGB(60, 160, 70), { anchored = false })
		end
	end
end

local function buildBag(item: any, m: Model, base: BasePart)
	local o = base.CFrame.Position
	local c = rgb(item.color or { 245, 245, 245 })
	Props.part(m, "Body", Vector3.new(0.9, 1.1, 0.5), CFrame.new(o + Vector3.new(0, 0.55, 0)), c, { anchored = false, material = Enum.Material.Fabric, transparency = 0.1 })
	Props.part(m, "BagHandle", Vector3.new(0.5, 0.35, 0.05), CFrame.new(o + Vector3.new(0, 1.25, 0)), c, { anchored = false, transparency = 0.1 })
	if item.sealed then
		Props.part(m, "Seal", Vector3.new(0.3, 0.12, 0.52), CFrame.new(o + Vector3.new(0, 1.0, 0)), Color3.fromRGB(230, 60, 60), { anchored = false })
	end
end

local BUILDERS = { cup = buildCup, pitcher = buildPitcher, box = buildBox, supply = buildBox, small = buildSmall, product = buildSmall, rag = buildSmall, dish = buildDish, bag = buildBag }

-- (re)build the visual of an item at its current place
function Props.refresh(item: any)
	local m = item.model
	if not m or not m.Parent then
		return
	end
	local base = m.PrimaryPart
	clearVisual(m)
	local b = BUILDERS[item.kind] or buildSmall
	b(item, m, base)
	weldAll(m)
	-- order sticker
	local sticker = item.sticker
	Props.label(base, if sticker then sticker else "", { name = "Sticker", size = UDim2.fromOffset(46, 18), offset = Vector3.new(0, (CUP_DIM[item.size] and CUP_DIM[item.size].h or 1) + 0.5, 0), maxDistance = 22, bg = Color3.fromRGB(255, 214, 90), color = Color3.fromRGB(30, 30, 30), bgTransparency = 0 })
end

function Props.create(item: any, parent: Instance, cf: CFrame): Model
	local m, base = newModel(item)
	base.CFrame = cf
	base.Anchored = true
	m.Parent = parent
	item.model = m
	Props.refresh(item)
	return m
end

function Props.destroy(item: any)
	if item.model then
		item.model:Destroy()
		item.model = nil
	end
end

-- grips (hand-relative CFrame of the item's bottom centre)
local GRIP = {
	cup = CFrame.new(0, -0.55, -0.15),
	pitcher = CFrame.new(0, -0.5, -0.2),
	box = CFrame.new(-0.9, -0.2, -0.75),
	supply = CFrame.new(-0.9, -0.2, -0.75),
	dish = CFrame.new(0, -0.15, -0.45),
	bag = CFrame.new(0, -1.25, 0),
	product = CFrame.new(0, -0.3, -0.2),
	rag = CFrame.new(0, -0.2, -0.1),
	small = CFrame.new(0, -0.3, -0.2),
}

local function handOf(char: Model?): BasePart?
	if not char then
		return nil
	end
	local h = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
	return if h and h:IsA("BasePart") then h else nil
end

-- put an item in a player's hand (slot 1 = right hand, slot 2 = tray / left hand)
function Props.hold(item: any, player: Player, slot: number?): boolean
	local m = item.model
	local hand = handOf(player.Character)
	if not m or not hand then
		return false
	end
	if slot == 2 then
		local left = player.Character:FindFirstChild("LeftHand") or player.Character:FindFirstChild("Left Arm")
		if left and left:IsA("BasePart") then
			hand = left
		end
	end
	local base = m.PrimaryPart :: BasePart
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.Massless = true
			d.CanCollide = false
		end
	end
	local old = base:FindFirstChild("HandWeld")
	if old then
		old:Destroy()
	end
	m:PivotTo(hand.CFrame * (GRIP[item.kind] or GRIP.small))
	local w = Instance.new("WeldConstraint")
	w.Name = "HandWeld"
	w.Part0 = hand
	w.Part1 = base
	w.Parent = base
	m.Parent = player.Character
	return true
end

-- set an item down on a station slot (cf = where its bottom centre goes)
function Props.put(item: any, parent: Instance, cf: CFrame)
	local m = item.model
	if not m then
		return
	end
	local base = m.PrimaryPart :: BasePart
	local w = base:FindFirstChild("HandWeld")
	if w then
		w:Destroy()
	end
	m.Parent = parent
	base.Anchored = true
	m:PivotTo(cf)
end

return Props
