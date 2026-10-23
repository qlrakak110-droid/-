--!nocheck
local R = require("./lib/rbx")
local E = R.env
local game, workspace, Instance, Enum, CFrame, Vector3, Color3, UDim2, UDim, Vector2 = E.game, E.workspace, E.Instance, E.Enum, E.CFrame, E.Vector3, E.Color3, E.UDim2, E.UDim, E.Vector2
local NumberSequence, NumberSequenceKeypoint, ColorSequence, ColorSequenceKeypoint, Random, typeof = E.NumberSequence, E.NumberSequenceKeypoint, E.ColorSequence, E.ColorSequenceKeypoint, E.Random, E.typeof
local CarBodies = (function()
-- GwangalliPassesShared/CarBodies: part-built premium car bodies + body kits (pure instance builders).
-- Used by the server for the drive templates (ServerStorage.GwangalliPassesTemplates) and by the client for the
-- phone's 3D previews. Everything follows the vehicles contract the rigger reads by NAME (GwangalliVehicles/
-- Analyze): Tyre (Cylinder, axis X), Underbody, BodySide (paint reference: every part with its exact colour is
-- paint), Grille / HeadlampLens / PlateFront in front (-Z), TailLamp / PlateRear behind (+Z), SeatCushion parts
-- inside a Model "Interior" (attribute LOD = "near"). All parts anchored; the rigger welds and unanchors.
-- Kit part names avoid the wheel words (tyre / tire) and the lamp words except where a lamp is meant.
--   CarBodies.build(key, paint: Color3, glow: Color3) -> Model    "hyper" | "super"
--   CarBodies.kitVip(model, glow) / CarBodies.kitOffroad(model, car)   on a clone of a map car
--   CarBodies.plateGui(part, text, face)   the SurfaceGui + TextLabel a plate part carries

local CarBodies = {}

local CARBON = Color3.fromRGB(24, 25, 28)
local TRIM = Color3.fromRGB(14, 15, 17)
local GLASS = Color3.fromRGB(22, 28, 36)
local RUBBER = Color3.fromRGB(26, 26, 28)
local CHROME = Color3.fromRGB(205, 208, 214)
local LENS = Color3.fromRGB(220, 230, 240)
local TAIL = Color3.fromRGB(170, 14, 24)

local function mk(className: string, parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?): BasePart
	local p = Instance.new(className) :: BasePart
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function box(parent: Instance, name: string, sx: number, sy: number, sz: number, x: number, y: number, z: number, color: Color3, mat: Enum.Material?): BasePart
	return mk("Part", parent, name, Vector3.new(sx, sy, sz), CFrame.new(x, y, z), color, mat)
end

-- a box between two z values and two y values (sx wide, centred on x)
local function slab(parent: Instance, name: string, sx: number, y0: number, y1: number, z0: number, z1: number, x: number, color: Color3, mat: Enum.Material?): BasePart
	return box(parent, name, sx, y1 - y0, z1 - z0, x, (y0 + y1) / 2, (z0 + z1) / 2, color, mat)
end

-- WedgePart rising toward +Z (low edge at z0, full height at z1)
local function rampUp(parent: Instance, name: string, sx: number, y0: number, y1: number, z0: number, z1: number, x: number, color: Color3, mat: Enum.Material?): BasePart
	return mk("WedgePart", parent, name, Vector3.new(sx, y1 - y0, z1 - z0), CFrame.new(x, (y0 + y1) / 2, (z0 + z1) / 2), color, mat)
end

-- WedgePart falling toward +Z (full height at z0, low edge at z1)
local function rampDown(parent: Instance, name: string, sx: number, y0: number, y1: number, z0: number, z1: number, x: number, color: Color3, mat: Enum.Material?): BasePart
	return mk("WedgePart", parent, name, Vector3.new(sx, y1 - y0, z1 - z0), CFrame.new(x, (y0 + y1) / 2, (z0 + z1) / 2) * CFrame.Angles(0, math.pi, 0), color, mat)
end

local function glass(p: BasePart, t: number?)
	p.Material = Enum.Material.Glass
	p.Transparency = t or 0.3
	p.Reflectance = 0.12
	p.CastShadow = false
end

local function neon(p: BasePart)
	p.Material = Enum.Material.Neon
	p.CastShadow = false
end

---------------------------------------------------------------------------------------------------
-- plates
---------------------------------------------------------------------------------------------------
function CarBodies.plateGui(part: BasePart, text: string, face: Enum.NormalId): SurfaceGui
	local g = Instance.new("SurfaceGui")
	g.Name = "PlateGui"
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 44
	g.LightInfluence = 0.6
	g.Parent = part
	local t = Instance.new("TextLabel")
	t.Name = "PlateText"
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(18, 18, 20)
	t.Text = text
	t.Parent = g
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.PaddingBottom = UDim.new(0.08, 0)
	pad.Parent = t
	return g
end

local function plates(m: Model, zf: number, zr: number, yf: number, yr: number)
	local f = box(m, "PlateFront", 1.74, 0.37, 0.08, 0, yf, zf, Color3.fromRGB(244, 244, 240))
	CarBodies.plateGui(f, "", Enum.NormalId.Front)
	local r = box(m, "PlateRear", 1.74, 0.37, 0.08, 0, yr, zr, Color3.fromRGB(244, 244, 240))
	CarBodies.plateGui(r, "", Enum.NormalId.Back)
end

---------------------------------------------------------------------------------------------------
-- wheels: tyre + rim + 5 spokes + disc + centre cap (all inside the wheel circle: they spin)
---------------------------------------------------------------------------------------------------
local function wheel(m: Model, x: number, z: number, d: number, w: number, rimColor: Color3)
	local s = if x < 0 then -1 else 1
	local t = box(m, "Tyre", w, d, d, x, d / 2, z, RUBBER, Enum.Material.Rubber)
	t.Shape = Enum.PartType.Cylinder
	local rd = d * 0.68
	local rim = box(m, "Rim", w + 0.04, rd, rd, x, d / 2, z, rimColor, Enum.Material.Metal)
	rim.Shape = Enum.PartType.Cylinder
	rim.Reflectance = 0.15
	local disc = box(m, "BrakeDisc", 0.14, d * 0.56, d * 0.56, x - s * (w * 0.18), d / 2, z, Color3.fromRGB(92, 94, 98), Enum.Material.Metal)
	disc.Shape = Enum.PartType.Cylinder
	local face = x + s * (w / 2 + 0.035)
	for k = 0, 4 do
		local a = k * (2 * math.pi / 5)
		local sp = mk("Part", m, "RimSpoke", Vector3.new(0.07, rd * 0.44, 0.2), CFrame.new(face, d / 2, z) * CFrame.Angles(a, 0, 0) * CFrame.new(0, rd * 0.24, 0), rimColor, Enum.Material.Metal)
		sp.Reflectance = 0.15
	end
	local cap = box(m, "RimCap", 0.1, rd * 0.22, rd * 0.22, face + s * 0.03, d / 2, z, TRIM, Enum.Material.Metal)
	cap.Shape = Enum.PartType.Cylinder
end

---------------------------------------------------------------------------------------------------
-- underglow: two neon strips under the sills + one light (a transparent core part)
---------------------------------------------------------------------------------------------------
local function underglow(m: Instance, xHalf: number, z0: number, z1: number, y: number, glow: Color3)
	for _, s in { -1, 1 } do
		local g = slab(m, "GlowStrip", 0.14, y - 0.05, y + 0.05, z0, z1, s * xHalf, glow)
		neon(g)
	end
	local core = slab(m, "GlowCore", 0.4, y - 0.1, y + 0.1, (z0 + z1) / 2 - 0.2, (z0 + z1) / 2 + 0.2, 0, glow)
	core.Transparency = 1
	core.CastShadow = false
	local l = Instance.new("PointLight")
	l.Name = "GlowLight"
	l.Color = glow
	l.Range = 11
	l.Brightness = 1.3
	l.Shadows = false
	l.Parent = core
end

---------------------------------------------------------------------------------------------------
-- the two coupe bodies (one parametric builder). Front = -Z, ground = y 0, origin between the axles.
---------------------------------------------------------------------------------------------------
local DEFS = {
	hyper = {
		L = 15.8, W = 6.7, dF = 2.35, dR = 2.5, wF = 0.95, wR = 1.15, zF = -4.85, zR = 4.75,
		belt = 2.2, roof = 3.6, wsBase = -2.7, roofF = -0.95, roofR = 1.55, deckZ = 4.3, deckY = 2.55,
		fenderF = 2.62, fenderR = 2.86, noseY = 1.45, rim = Color3.fromRGB(40, 42, 46), wing = true, scoop = true,
		exhaust = 2, label = "GT-X",
	},
	super = {
		L = 16.2, W = 6.5, dF = 2.3, dR = 2.4, wF = 0.9, wR = 1.05, zF = -5.3, zR = 4.6,
		belt = 2.15, roof = 3.72, wsBase = -1.85, roofF = -0.45, roofR = 1.9, deckZ = 5.35, deckY = 2.42,
		fenderF = 2.5, fenderR = 2.7, noseY = 1.4, rim = Color3.fromRGB(196, 160, 82), wing = false, scoop = false,
		exhaust = 4, label = "GT",
	},
}

function CarBodies.build(key: string, paint: Color3, glow: Color3): Model
	local D = DEFS[key] or DEFS.hyper
	local m = Instance.new("Model")
	m.Name = "Car_GwPremium_" .. key
	local L, W = D.L, D.W
	local hz = L / 2
	local fF0, fF1 = D.zF - D.dF / 2 - 0.3, D.zF + D.dF / 2 + 0.3 -- front wheel opening (z)
	local fR0, fR1 = D.zR - D.dR / 2 - 0.3, D.zR + D.dR / 2 + 0.3
	local tx = W / 2 - 0.62 -- tyre centre x (inset under the fenders)

	-- floor / tub ---------------------------------------------------------------------------------
	slab(m, "Underbody", W - 1.1, 0.55, 0.86, -hz + 0.7, hz - 0.7, 0, TRIM)
	slab(m, "BodySide", W, 0.66, D.belt, fF1, fR0, 0, paint) -- door section (the paint reference)
	slab(m, "NoseSection", W - 0.15, 0.6, D.noseY, -hz + 0.25, fF0, 0, paint)
	slab(m, "TailSection", W - 0.1, 0.72, D.deckY - 0.15, fR1, hz - 0.15, 0, paint)
	-- inner wheel wells: dark blocks between the tyres so nothing is see-through above them
	slab(m, "WheelWellF", W - 2 * (D.wF + 0.3), 0.6, D.fenderF - 0.1, fF0 + 0.1, fF1 - 0.1, 0, TRIM)
	slab(m, "WheelWellR", W - 2 * (D.wR + 0.3), 0.66, D.fenderR - 0.1, fR0 + 0.1, fR1 - 0.1, 0, TRIM)
	-- fender humps over the wheels (both sides) + their arch liners
	for _, s in { -1, 1 } do
		slab(m, "FenderF", D.wF + 0.55, D.dF + 0.08, D.fenderF, fF0, fF1, s * (W / 2 - (D.wF + 0.55) / 2), paint)
		slab(m, "FenderR", D.wR + 0.6, D.dR + 0.08, D.fenderR, fR0, fR1, s * (W / 2 - (D.wR + 0.6) / 2), paint)
		slab(m, "ArchLinerF", D.wF + 0.45, D.dF - 0.05, D.dF + 0.1, fF0 + 0.05, fF1 - 0.05, s * (W / 2 - (D.wF + 0.45) / 2 - 0.04), TRIM)
		slab(m, "ArchLinerR", D.wR + 0.5, D.dR - 0.05, D.dR + 0.1, fR0 + 0.05, fR1 - 0.05, s * (W / 2 - (D.wR + 0.5) / 2 - 0.04), TRIM)
		-- side skirt (carbon) + side intake ahead of the rear wheel
		slab(m, "SideSkirt", 0.18, 0.6, 0.9, fF1 + 0.1, fR0 - 0.1, s * (W / 2 + 0.03), CARBON)
		slab(m, "SideIntake", 0.12, 1.05, D.belt - 0.35, fR0 - 2.1, fR0 - 0.25, s * (W / 2 + 0.02), TRIM)
	end

	-- nose / hood -----------------------------------------------------------------------------------
	rampUp(m, "Hood", W - 0.6, D.noseY, D.belt + 0.08, -hz + 0.35, D.wsBase, 0, paint)
	slab(m, "Splitter", W - 0.3, 0.55, 0.62, -hz - 0.25, -hz + 0.9, 0, CARBON)
	slab(m, "Grille", W * 0.56, 0.62, 1.12, -hz - 0.04, -hz + 0.1, 0, TRIM)
	if key == "super" then
		rampUp(m, "HoodBulge", 1.6, D.belt - 0.15, D.belt + 0.22, -hz + 2.2, D.wsBase - 0.2, 0, paint)
		for _, s in { -1, 1 } do
			slab(m, "HoodVent", 0.7, D.belt - 0.02, D.belt + 0.06, -hz + 3.4, -hz + 4.6, s * 1.55, TRIM)
		end
	end
	-- lamps: two thin lens blades + a DRL line per side
	for _, s in { -1, 1 } do
		local hx = s * (W / 2 - 1.05)
		local lens = slab(m, "HeadlampLens", 1.35, D.noseY - 0.2, D.noseY - 0.04, -hz + 0.12, -hz + 0.36, hx, LENS, Enum.Material.Glass)
		lens.Reflectance = 0.2
		local drl = slab(m, "DrlBlade", 1.5, D.noseY - 0.3, D.noseY - 0.24, -hz + 0.16, -hz + 0.3, hx, Color3.fromRGB(210, 240, 255))
		neon(drl)
		slab(m, "Mirror", 0.55, D.belt + 0.25, D.belt + 0.52, D.wsBase + 0.15, D.wsBase + 0.55, s * (W / 2 + 0.1), paint)
	end

	-- cabin -----------------------------------------------------------------------------------------
	local cw = W - 1.35
	local ws = rampUp(m, "Windshield", cw, D.belt, D.roof, D.wsBase, D.roofF, 0, GLASS)
	glass(ws, 0.32)
	slab(m, "Roof", cw - 0.1, D.roof - 0.16, D.roof, D.roofF, D.roofR, 0, CARBON)
	for _, s in { -1, 1 } do
		local win = slab(m, "SideWindow", 0.12, D.belt + 0.06, D.roof - 0.14, D.roofF - 0.6, D.roofR - 0.35, s * (cw / 2 + 0.02), GLASS)
		glass(win, 0.35)
		slab(m, "PillarA", 0.16, D.belt, D.roof - 0.05, D.roofF - 0.25, D.roofF, s * (cw / 2), TRIM)
		slab(m, "PillarC", 0.2, D.belt, D.roof - 0.05, D.roofR - 0.4, D.roofR, s * (cw / 2 - 0.04), paint)
		slab(m, "BeltChrome", 0.06, D.belt + 0.01, D.belt + 0.06, D.roofF - 0.6, D.roofR - 0.35, s * (cw / 2 + 0.09), CHROME, Enum.Material.Metal)
	end
	local rg = rampDown(m, "RearGlass", cw - 0.2, D.deckY, D.roof - 0.02, D.roofR, D.deckZ, 0, GLASS)
	glass(rg, 0.38)
	slab(m, "EngineCover", W - 0.7, D.deckY - 0.18, D.deckY, D.deckZ, hz - 0.35, 0, paint)
	if key == "hyper" then
		for i = 0, 3 do
			slab(m, "DeckLouver", W - 1.6, D.deckY + 0.01, D.deckY + 0.07, D.deckZ + 0.3 + i * 0.55, D.deckZ + 0.55 + i * 0.55, 0, TRIM)
		end
	end
	if D.scoop then
		slab(m, "RoofScoop", 1.0, D.roof, D.roof + 0.3, D.roofR - 1.2, D.roofR - 0.1, 0, CARBON)
	end

	-- rear ------------------------------------------------------------------------------------------
	local tail = slab(m, "TailLamp", W - 0.5, D.deckY - 0.42, D.deckY - 0.3, hz - 0.2, hz - 0.02, 0, TAIL, Enum.Material.Glass)
	tail.Reflectance = 0.1
	for _, s in { -1, 1 } do
		local tl = slab(m, "TailLamp", 1.1, D.deckY - 0.75, D.deckY - 0.45, hz - 0.18, hz - 0.02, s * (W / 2 - 0.8), TAIL, Enum.Material.Glass)
		tl.Reflectance = 0.1
	end
	slab(m, "RearPanel", W - 0.4, 0.62, 1.15, hz - 0.3, hz + 0.02, 0, TRIM)
	for i = -2, 2 do
		slab(m, "Diffuser", 0.08, 0.56, 0.98, hz - 1.2, hz + 0.1, i * 0.85, CARBON)
	end
	local nEx = D.exhaust
	for i = 1, nEx do
		local ex = (if nEx == 2 then (i - 1.5) * 0.9 else (if i <= 2 then -1 else 1) * (W / 2 - 1.3) + (if i % 2 == 0 then 0.42 else 0))
		local e = mk("Part", m, "Exhaust", Vector3.new(0.5, 0.42, 0.42), CFrame.new(ex, 0.88, hz + 0.05) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(70, 66, 62), Enum.Material.Metal)
		e.Shape = Enum.PartType.Cylinder
	end
	if D.wing then
		slab(m, "Spoiler", W - 0.9, D.roof - 0.12, D.roof, hz - 1.6, hz - 0.45, 0, CARBON)
		for _, s in { -1, 1 } do
			slab(m, "WingStay", 0.12, D.deckY, D.roof - 0.1, hz - 1.3, hz - 0.8, s * (W / 2 - 1.5), CARBON)
			slab(m, "WingPlate", 0.08, D.roof - 0.5, D.roof + 0.1, hz - 1.7, hz - 0.35, s * (W / 2 - 0.45), CARBON)
		end
	else
		slab(m, "Spoiler", W - 0.8, D.deckY, D.deckY + 0.18, hz - 0.6, hz - 0.15, 0, paint) -- ducktail
	end
	plates(m, -hz - 0.08, hz + 0.07, 0.86, 1.32)

	-- wheels ----------------------------------------------------------------------------------------
	for _, s in { -1, 1 } do
		wheel(m, s * tx, D.zF, D.dF, D.wF, D.rim)
		wheel(m, s * (tx + (D.wR - D.wF) / 2), D.zR, D.dR, D.wR, D.rim)
	end
	underglow(m, W / 2 - 0.55, fF1 + 0.2, fR0 - 0.2, 0.58, glow)

	-- interior (near LOD): two bucket seats, dash, wheel ring, tunnel, floor ------------------------
	local int = Instance.new("Model")
	int.Name = "Interior"
	int:SetAttribute("LOD", "near")
	int.Parent = m
	local seatZ = (D.roofF + D.roofR) / 2 + 0.25
	local leather = Color3.fromRGB(30, 30, 33)
	local stitch = if key == "hyper" then Color3.fromRGB(150, 90, 255) else Color3.fromRGB(196, 40, 44)
	for _, s in { -1, 1 } do
		local sx = s * 1.12
		box(int, "SeatCushion", 1.5, 0.42, 1.55, sx, 1.08, seatZ, leather, Enum.Material.Fabric)
		mk("Part", int, "SeatBack", Vector3.new(1.45, 1.75, 0.34), CFrame.new(sx, 1.95, seatZ + 0.92) * CFrame.Angles(math.rad(-14), 0, 0), leather, Enum.Material.Fabric)
		mk("Part", int, "SeatStripe", Vector3.new(0.18, 1.6, 0.36), CFrame.new(sx, 1.97, seatZ + 0.93) * CFrame.Angles(math.rad(-14), 0, 0), stitch, Enum.Material.Fabric)
	end
	slab(int, "Floor", W - 1.4, 0.78, 0.86, D.wsBase + 0.3, D.roofR + 0.4, 0, Color3.fromRGB(20, 20, 22), Enum.Material.Fabric)
	slab(int, "Dash", W - 1.6, D.belt - 0.35, D.belt + 0.12, D.wsBase + 0.2, D.wsBase + 1.15, 0, Color3.fromRGB(28, 28, 31))
	slab(int, "Tunnel", 0.62, 0.86, 1.55, D.wsBase + 1.0, seatZ + 0.8, 0, CARBON)
	local scr = slab(int, "DashScreen", 1.1, D.belt + 0.12, D.belt + 0.42, D.wsBase + 0.95, D.wsBase + 1.02, -1.12, Color3.fromRGB(40, 140, 255))
	neon(scr)
	local ring = mk("Part", int, "SteerRing", Vector3.new(0.1, 1.0, 1.0), CFrame.new(-1.12, D.belt + 0.05, D.wsBase + 1.55) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, math.rad(-20)), TRIM)
	ring.Shape = Enum.PartType.Cylinder

	m:SetAttribute("GwBodyLabel", D.label)
	return m
end

---------------------------------------------------------------------------------------------------
-- kits on a clone of a map car (VIP / offroad). The car frame: front from the tail-lamp -> head-lamp
-- direction, centre / extents from the parts' bounding box in that frame.
---------------------------------------------------------------------------------------------------
local function centroid(parts: { BasePart }): Vector3?
	if #parts == 0 then
		return nil
	end
	local s = Vector3.zero
	for _, p in parts do
		s += p.Position
	end
	return s / #parts
end

local function named(model: Instance, frags: { string }): { BasePart }
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local low = string.lower(d.Name)
			for _, f in frags do
				if string.find(low, f, 1, true) then
					table.insert(out, d)
					break
				end
			end
		end
	end
	return out
end

local function inInterior(p: Instance, model: Instance): boolean
	local n = p.Parent
	while n and n ~= model do
		if n.Name == "Interior" then
			return true
		end
		n = n.Parent
	end
	return false
end

-- -> frame (CFrame at the ground centre, LookVector = front), half extents (x, top y, z)
function CarBodies.frameOf(model: Model): (CFrame, Vector3)
	local head = centroid(named(model, { "headlamp", "headlight", "grille", "platefront" }))
	local tail = centroid(named(model, { "taillamp", "taillight", "platerear" }))
	local fwd = Vector3.new(0, 0, -1)
	if head and tail then
		local d = head - tail
		local flat = Vector3.new(d.X, 0, d.Z)
		if flat.Magnitude > 0.5 then
			fwd = flat.Unit
		end
	end
	-- snap to the body panel's own axes (lamps are not always symmetric)
	local ref = model:FindFirstChild("BodySide", true) or model:FindFirstChild("Underbody", true)
	if ref and ref:IsA("BasePart") then
		local best, bestDot = fwd, -2
		for _, axis in { ref.CFrame.LookVector, -ref.CFrame.LookVector, ref.CFrame.RightVector, -ref.CFrame.RightVector } do
			local a = Vector3.new(axis.X, 0, axis.Z)
			if a.Magnitude > 0.5 then
				local dot = a.Unit:Dot(fwd)
				if dot > bestDot then
					best, bestDot = a.Unit, dot
				end
			end
		end
		fwd = best
	end
	local cf0 = CFrame.lookAt(Vector3.zero, fwd)
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = -minV
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 and not inInterior(d, model) then
			-- the part's 8 corners in the car frame (an exact box, rotated parts included)
			local rel = cf0:ToObjectSpace(d.CFrame)
			local h = d.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local l = rel * Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)
						minV = Vector3.new(math.min(minV.X, l.X), math.min(minV.Y, l.Y), math.min(minV.Z, l.Z))
						maxV = Vector3.new(math.max(maxV.X, l.X), math.max(maxV.Y, l.Y), math.max(maxV.Z, l.Z))
					end
				end
			end
		end
	end
	if minV.X == math.huge then
		return CFrame.new(), Vector3.new(3, 4, 8)
	end
	local c = Vector3.new((minV.X + maxV.X) / 2, minV.Y, (minV.Z + maxV.Z) / 2)
	local frame = cf0 * CFrame.new(c)
	return frame, Vector3.new((maxV.X - minV.X) / 2, maxV.Y - minV.Y, (maxV.Z - minV.Z) / 2)
end

local function kitPart(parent: Instance, frame: CFrame, name: string, size: Vector3, lx: number, ly: number, lz: number, color: Color3, mat: Enum.Material?, rot: CFrame?): BasePart
	return mk("Part", parent, name, size, frame * CFrame.new(lx, ly, lz) * (rot or CFrame.new()), color, mat)
end

local function tint(model: Model, color: Color3, transparency: number)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and not inInterior(d, model) then
			local low = string.lower(d.Name)
			if d.Material == Enum.Material.Glass or string.find(low, "window", 1, true) or string.find(low, "windshield", 1, true) or string.find(low, "glass", 1, true) then
				if not (string.find(low, "lamp", 1, true) or string.find(low, "light", 1, true) or string.find(low, "lens", 1, true)) then
					d.Color = color
					d.Transparency = math.min(d.Transparency, transparency)
					d.Reflectance = math.max(d.Reflectance, 0.18)
				end
			end
		end
	end
end

-- VIP: dark tint, chrome trunk emblem, underglow (the gold plate frame comes from the plate style)
function CarBodies.kitVip(model: Model, glow: Color3)
	local frame, ext = CarBodies.frameOf(model)
	tint(model, Color3.fromRGB(8, 9, 12), 0.18)
	local kit = Instance.new("Model")
	kit.Name = "GwKit"
	kit.Parent = model
	local rear = model:FindFirstChild("PlateRear", true)
	local ey = if rear and rear:IsA("BasePart") then frame:PointToObjectSpace(rear.Position).Y + 0.75 else ext.Y * 0.45
	local emb = kitPart(kit, frame, "VipEmblem", Vector3.new(1.1, 0.32, 0.06), 0, ey, ext.Z + 0.02, Color3.fromRGB(196, 160, 82), Enum.Material.Metal)
	emb.Reflectance = 0.3
	local g = Instance.new("SurfaceGui")
	g.Name = "EmblemGui"
	g.Face = Enum.NormalId.Back
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 60
	g.LightInfluence = 0.5
	g.Parent = emb
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.Text = "V I P"
	t.TextColor3 = Color3.fromRGB(40, 28, 6)
	t.Parent = g
	for _, s in { -1, 1 } do
		local strip = kitPart(kit, frame, "GlowStrip", Vector3.new(0.14, 0.1, ext.Z * 0.95), s * (ext.X - 0.75), 0.55, 0, glow)
		neon(strip)
	end
	local core = kitPart(kit, frame, "GlowCore", Vector3.new(0.4, 0.2, 0.4), 0, 0.5, 0, glow)
	core.Transparency = 1
	local l = Instance.new("PointLight")
	l.Name = "GlowLight"
	l.Color = glow
	l.Range = 11
	l.Brightness = 1.1
	l.Shadows = false
	l.Parent = core
end

-- 오프로더: lift the body, grow the tyres, bull bar, roof rack + light bar, snorkel, mud flaps
function CarBodies.kitOffroad(model: Model, car: any)
	local frame, ext = CarBodies.frameOf(model)
	local lift = tonumber(car and car.lift) or 0.9
	local grow = tonumber(car and car.tyreGrow) or 0.5
	local tyres = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and (d.Name == "Tyre" or d.Name == "Tire") then
			table.insert(tyres, d)
		end
	end
	local function nearWheel(p: BasePart): BasePart?
		for _, t in tyres do
			local l = t.CFrame:PointToObjectSpace(p.Position)
			local r = math.max(t.Size.Y, t.Size.Z) / 2
			if math.abs(l.X) <= t.Size.X / 2 + 0.35 and Vector2.new(l.Y, l.Z).Magnitude <= r + 0.05 then
				return t
			end
		end
		return nil
	end
	if #tyres >= 4 then
		local up = frame.UpVector
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				if d.Name == "Tyre" or d.Name == "Tire" then
					continue
				end
				local w = nearWheel(d)
				d.CFrame = d.CFrame + up * (if w then grow / 2 else lift + grow / 2)
			end
		end
		for _, t in tyres do
			t.Size = Vector3.new(t.Size.X + 0.28, t.Size.Y + grow, t.Size.Z + grow)
			t.CFrame = t.CFrame + up * (grow / 2)
		end
	end
	local top = ext.Y + lift + grow / 2
	local kit = Instance.new("Model")
	kit.Name = "GwKit"
	kit.Parent = model
	local steel = Color3.fromRGB(34, 35, 38)
	local fz = -ext.Z - 0.35
	local by = 1.0 + lift + grow / 2
	-- bull bar
	for _, s in { -1, 1 } do
		kitPart(kit, frame, "BullBarPost", Vector3.new(0.22, 1.7, 0.22), s * (ext.X * 0.55), by + 0.55, fz, steel, Enum.Material.Metal)
	end
	kitPart(kit, frame, "BullBar", Vector3.new(ext.X * 1.25, 0.22, 0.22), 0, by + 1.38, fz, steel, Enum.Material.Metal)
	kitPart(kit, frame, "BullBarPlate", Vector3.new(ext.X * 1.3, 0.5, 0.12), 0, by - 0.15, fz + 0.05, steel, Enum.Material.DiamondPlate)
	-- roof rack + light bar
	local rackY = top + 0.18
	for _, s in { -1, 1 } do
		kitPart(kit, frame, "RoofRackRail", Vector3.new(0.14, 0.14, ext.Z * 0.8), s * (ext.X - 0.9), rackY, ext.Z * 0.05, steel, Enum.Material.Metal)
	end
	for i = -1, 1 do
		kitPart(kit, frame, "RoofRackBar", Vector3.new(ext.X * 2 - 1.8, 0.1, 0.16), 0, rackY + 0.08, i * ext.Z * 0.3 + ext.Z * 0.05, steel, Enum.Material.Metal)
	end
	local barZ = -ext.Z * 0.32
	kitPart(kit, frame, "RoofLightBar", Vector3.new(ext.X * 2 - 2.0, 0.34, 0.34), 0, rackY + 0.3, barZ, steel, Enum.Material.Metal)
	for i = 1, 4 do
		local lx = (i - 2.5) * ((ext.X * 2 - 2.6) / 4)
		local lamp = kitPart(kit, frame, "SpotLamp", Vector3.new(0.1, 0.3, 0.3), lx, rackY + 0.3, barZ - 0.2, Color3.fromRGB(235, 240, 245), Enum.Material.Glass, CFrame.Angles(0, math.pi / 2, 0))
		lamp.Shape = Enum.PartType.Cylinder
	end
	-- snorkel on the right A-pillar
	local ws = model:FindFirstChild("Windshield", true)
	local sz = if ws and ws:IsA("BasePart") then frame:PointToObjectSpace(ws.Position).Z else -ext.Z * 0.2
	local sn = kitPart(kit, frame, "Snorkel", Vector3.new(0.34, top - 1.6, 0.34), ext.X + 0.12, (top + 1.6) / 2, sz + 0.2, steel)
	sn.Material = Enum.Material.SmoothPlastic
	kitPart(kit, frame, "SnorkelCap", Vector3.new(0.4, 0.4, 0.7), ext.X + 0.12, top + 0.15, sz - 0.05, steel)
	-- mud flaps behind the rear wheels
	for _, t in tyres do
		local l = frame:PointToObjectSpace(t.Position)
		if l.Z > 0 then
			kitPart(kit, frame, "MudFlap", Vector3.new(t.Size.X, 0.9, 0.08), l.X, 1.35 + lift * 0.4, l.Z + t.Size.Y / 2 + 0.25, Color3.fromRGB(20, 20, 20), Enum.Material.Rubber)
		end
	end
end

return CarBodies
end)()
local Analyze = (function()
-- ModuleScript @ ServerScriptService.GwangalliVehicles.Analyze
-- GwangalliVehicles/Analyze: reads a car Model built by build/kit/vehicles.luau (or anything that
-- follows docs/vehicles_contract.md) and returns its driving layout WITHOUT changing it:
--   frame (car frame on the ground: LookVector = front, UpVector = up, origin = centre between the
--   axles at tyre-contact height), body box, wheel clusters (+ the parts that spin with them), seats,
--   lamps, door / camera points. Names first (Tyre, SeatCushion, Underbody, Grille ...), geometry as
--   the fallback (cylinder parts low in the model, bench-like parts in the cabin), so later look
--   changes of the car models keep working.
-- Pure reads: only CFrame / Size / Name / Shape / attributes, so the same code runs in Lune tests.

local Analyze = {}

local TYRE_NAMES = { Tyre = true, Tire = true, Tyres = true, Tires = true, WheelTyre = true, WheelTire = true }
local SEAT_NAMES = { SeatCushion = true, Seat = true, BusSeat = true, DriverSeat = true, SeatBase = true }
-- parts that never belong to a wheel even when they sit inside the wheel circle
local NOT_WHEEL = { "well", "housing", "arch", "fender", "mudguard", "flap", "clad", "sill", "bumper", "step", "body" }
local FRONT_NAMES = { "grille", "headlamp", "headlight", "frontbumper", "platefront", "windshield", "hood", "drl", "nose", "bonnet" }
local REAR_NAMES = { "taillamp", "taillight", "platerear", "rearbumper", "tailgate", "trunk", "rearglass", "diffuser", "tailbar" }
local HEAD_LAMPS = { "headlamp", "headlight", "drl" }
local TAIL_LAMPS = { "taillamp", "taillight", "tailbar", "tailline", "brakelamp", "brakelight" }
local TURN_LAMPS = { "repeater", "turnlamp", "indicator", "blinker" }
local ANY_LAMP = { "lamp", "light", "led" } -- other lamps: front half -> head, rear half -> tail
local NOT_LAMP = { "wrap", "bezel", "housing", "trim", "arm", "base", "pod", "cover", "ceiling", "interior", "ambient" }
local NO_COLLIDE_BOX = { "mirror", "antenna", "sharkfin", "wiper", "flag", "sign", "lightbar", "beacon", "repeater", "handle" }

local function hasAny(lower: string, list: { string }): boolean
	for _, frag in list do
		if string.find(lower, frag, 1, true) then
			return true
		end
	end
	return false
end

local function insideInterior(p: Instance, model: Instance): boolean
	local node = p.Parent
	while node and node ~= model do
		if node.Name == "Interior" then
			return true
		end
		node = node.Parent
	end
	return false
end

-- Half extent of an oriented part along a world direction.
local function halfAlong(cf: CFrame, size: Vector3, dir: Vector3): number
	return 0.5 * (math.abs(cf.RightVector:Dot(dir)) * size.X + math.abs(cf.UpVector:Dot(dir)) * size.Y + math.abs(cf.LookVector:Dot(dir)) * size.Z)
end

local function isCylinder(p: BasePart): boolean
	local ok, shape = pcall(function()
		return (p :: any).Shape
	end)
	return ok and shape == Enum.PartType.Cylinder
end

-- Tyre axis (world) for a tyre part: cylinders spin about their X axis; a block / mesh tyre about
-- its thinnest axis.
local function tyreAxis(p: BasePart): (Vector3, number, number)
	local cf, s = p.CFrame, p.Size
	if isCylinder(p) then
		return cf.RightVector, math.min(s.Y, s.Z) / 2, s.X
	end
	if s.X <= s.Y and s.X <= s.Z then
		return cf.RightVector, math.max(s.Y, s.Z) / 2, s.X
	elseif s.Z <= s.Y then
		return cf.LookVector, math.max(s.X, s.Y) / 2, s.Z
	end
	return cf.UpVector, math.max(s.X, s.Z) / 2, s.Y
end

function Analyze.parts(model: Instance): { BasePart }
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

-- Returns info or nil, reason.
function Analyze.run(model: Model): (any?, string?)
	local parts = Analyze.parts(model)
	if #parts == 0 then
		return nil, "no parts"
	end
	local kind = model:GetAttribute("VehicleKind")

	-- 1) tyres: by name (outside the Interior), attribute DriveWheel, else low cylinders ---------------
	local tyres = {}
	for _, p in parts do
		if (TYRE_NAMES[p.Name] or p:GetAttribute("DriveWheel") == true) and not insideInterior(p, model) then
			table.insert(tyres, p)
		end
	end
	if #tyres < 3 then
		-- geometry fallback: cylinders 1.2-4.5 studs across, thinner than wide, in the lower part
		-- (two named tyres stay: a scooter / motorbike, checked below)
		local minY, maxY = math.huge, -math.huge
		for _, p in parts do
			local y = p.CFrame.Position.Y
			minY, maxY = math.min(minY, y), math.max(maxY, y)
		end
		local named = tyres
		tyres = {}
		for _, p in parts do
			if isCylinder(p) and not insideInterior(p, model) then
				local s = p.Size
				local d = math.min(s.Y, s.Z)
				if d >= 1.2 and d <= 4.5 and s.X <= d * 0.75 and p.CFrame.Position.Y <= minY + (maxY - minY) * 0.45 then
					table.insert(tyres, p)
				end
			end
		end
		if #tyres < 3 and #named == 2 then
			tyres = named
		end
	end
	-- two tyres in one line = a two-wheeler (scooter / motorbike): same axis, (almost) no sideways offset, apart
	local bike = false
	if #tyres == 2 then
		local a1, _, w1 = tyreAxis(tyres[1])
		local a2 = tyreAxis(tyres[2])
		local d = tyres[2].CFrame.Position - tyres[1].CFrame.Position
		if math.abs(a1:Dot(a2)) > 0.9 and math.abs(d:Dot(a1)) < math.max(0.6, w1) and (d - a1 * d:Dot(a1)).Magnitude > 2 then
			bike = true
		else
			return nil, "two tyres that are not in one line"
		end
	elseif #tyres < 3 then
		return nil, "fewer than 3 tyres"
	end

	-- 2) frame --------------------------------------------------------------------------------------
	local up = Vector3.yAxis
	local axis = tyreAxis(tyres[1])
	axis = (axis - up * axis:Dot(up))
	if axis.Magnitude < 0.3 then
		return nil, "tyres not upright"
	end
	local right = axis.Unit
	local fwd = up:Cross(right) -- sign fixed below
	local function horiz(v: Vector3): Vector3
		local h = v - up * v:Dot(up)
		return if h.Magnitude > 1e-4 then h.Unit else v
	end
	local sign = 0
	local under = model:FindFirstChild("Underbody")
	if under and under:IsA("BasePart") then
		sign = if horiz(under.CFrame.LookVector):Dot(fwd) >= 0 then 1 else -1
	end
	if sign == 0 then
		local fSum, fN, rSum, rN = Vector3.zero, 0, Vector3.zero, 0
		for _, p in parts do
			if not insideInterior(p, model) then
				local lower = string.lower(p.Name)
				if hasAny(lower, FRONT_NAMES) then
					fSum += p.CFrame.Position
					fN += 1
				elseif hasAny(lower, REAR_NAMES) then
					rSum += p.CFrame.Position
					rN += 1
				end
			end
		end
		if fN > 0 and rN > 0 then
			local d = fSum / fN - rSum / rN
			if math.abs(d:Dot(fwd)) > 0.5 then
				sign = if d:Dot(fwd) > 0 then 1 else -1
			end
		end
	end
	if sign == 0 then
		-- steering wheel (Interior WheelRim / SteeringWheel) sits ahead of the seats' centre
		local sw, swN, seat, seatN = Vector3.zero, 0, Vector3.zero, 0
		for _, p in parts do
			local n = p.Name
			if n == "WheelRim" or n == "SteeringWheel" or n == "WheelHub" then
				sw += p.CFrame.Position
				swN += 1
			elseif SEAT_NAMES[n] then
				seat += p.CFrame.Position
				seatN += 1
			end
		end
		if swN > 0 and seatN > 0 then
			sign = if (sw / swN - seat / seatN):Dot(fwd) >= 0 then 1 else -1
		end
	end
	if sign == 0 then
		sign = 1
	end
	fwd *= sign
	right = fwd:Cross(up) -- Roblox: RightVector = LookVector x UpVector

	-- tyre metrics in a provisional frame (origin = tyre centroid)
	local c0 = Vector3.zero
	for _, t in tyres do
		c0 += t.CFrame.Position
	end
	c0 /= #tyres
	local frame0 = CFrame.fromMatrix(c0, right, up, -fwd)
	local tyreInfo = {}
	local groundY = math.huge
	for _, t in tyres do
		local _, r, w = tyreAxis(t)
		local l = frame0:PointToObjectSpace(t.CFrame.Position)
		table.insert(tyreInfo, { part = t, l = l, r = r, w = w })
		groundY = math.min(groundY, l.Y - r)
	end

	-- 3) wheel clusters: same side, same axle (dual rear tyres merge) -----------------------------
	local clusters = {}
	for _, t in tyreInfo do
		local side = if bike then 0 elseif t.l.X >= 0 then 1 else -1
		local found = nil
		for _, c in clusters do
			if c.side == side and math.abs(c.z - t.l.Z) < math.max(c.r, t.r) then
				found = c
				break
			end
		end
		if found then
			table.insert(found.tyres, t)
			local n = #found.tyres
			found.z = (found.z * (n - 1) + t.l.Z) / n
			found.r = math.max(found.r, t.r)
		else
			table.insert(clusters, { side = side, z = t.l.Z, r = t.r, tyres = { t } })
		end
	end
	if #clusters < (if bike then 2 else 3) then
		return nil, "fewer than 3 wheel positions"
	end
	local minZ, maxZ = math.huge, -math.huge
	for _, c in clusters do
		minZ, maxZ = math.min(minZ, c.z), math.max(maxZ, c.z)
	end
	local midZ = (minZ + maxZ) / 2
	local wheelbase = maxZ - minZ
	if wheelbase < 2 then
		return nil, "wheelbase too short"
	end
	-- final frame: origin between the axles, laterally centred, on the ground
	local xs, xn = 0, 0
	for _, c in clusters do
		local x0, x1 = math.huge, -math.huge
		for _, t in c.tyres do
			x0 = math.min(x0, t.l.X - t.w / 2)
			x1 = math.max(x1, t.l.X + t.w / 2)
		end
		c.x0, c.x1 = x0, x1
		xs += (x0 + x1) / 2
		xn += 1
	end
	local centreLocal = Vector3.new(0, groundY, midZ) -- keep x = 0 (tyre centroid is centred)
	local frame = frame0 * CFrame.new(centreLocal)
	local shift = -centreLocal
	local wheels = {}
	for _, c in clusters do
		local y = 0
		for _, t in c.tyres do
			y += t.l.Y
		end
		y = y / #c.tyres
		local ctr = Vector3.new((c.x0 + c.x1) / 2, y, c.z) + shift
		table.insert(wheels, {
			center = ctr,
			r = c.r,
			x0 = c.x0 + shift.X,
			x1 = c.x1 + shift.X,
			side = c.side,
			front = ctr.Z < 0, -- -Z = forward
			tyres = c.tyres,
			parts = {},
			calipers = {},
		})
	end
	table.sort(wheels, function(a, b)
		if a.front ~= b.front then
			return a.front
		end
		return a.side < b.side
	end)

	-- 4) parts that spin with a wheel (tyre, rim, disc, spokes, cap) / steer only (caliper) ---------
	local owner: { [BasePart]: boolean } = {}
	for _, p in parts do
		if insideInterior(p, model) then
			continue
		end
		local lower = string.lower(p.Name)
		if hasAny(lower, NOT_WHEEL) then
			continue
		end
		local l = frame:PointToObjectSpace(p.CFrame.Position)
		local s = p.Size
		local big = math.max(s.X, s.Y, s.Z)
		for _, wh in wheels do
			if big <= 2 * wh.r + 0.35 and l.X >= wh.x0 - 0.35 and l.X <= wh.x1 + 0.35 then
				local dy, dz = l.Y - wh.center.Y, l.Z - wh.center.Z
				if math.sqrt(dy * dy + dz * dz) <= wh.r * 1.02 then
					if string.find(lower, "caliper", 1, true) then
						table.insert(wh.calipers, p)
					else
						table.insert(wh.parts, p)
					end
					owner[p] = true
					break
				end
			end
		end
	end
	for _, wh in wheels do
		for _, t in wh.tyres do
			if not owner[t.part] then
				owner[t.part] = true
				table.insert(wh.parts, t.part)
			end
		end
	end

	-- 5) body box (collider), lamps --------------------------------------------------------------------
	local bb = { x0 = math.huge, x1 = -math.huge, y0 = math.huge, y1 = -math.huge, z0 = math.huge, z1 = -math.huge }
	local body = {}
	local lamps = { head = {}, tail = {}, turn = {} }
	local frontTop = -math.huge
	local frontAxleZ = math.huge
	local rearAxleZ = -math.huge
	for _, wh in wheels do
		if wh.front then
			frontAxleZ = math.min(frontAxleZ, wh.center.Z)
		else
			rearAxleZ = math.max(rearAxleZ, wh.center.Z)
		end
	end
	if frontAxleZ == math.huge then
		frontAxleZ = minZ - midZ
	end
	local fX, fY, fZ = frame.RightVector, frame.UpVector, frame.LookVector
	for _, p in parts do
		if owner[p] then
			continue
		end
		table.insert(body, p)
		local lower = string.lower(p.Name)
		local interior = insideInterior(p, model)
		local cf, s = p.CFrame, p.Size
		local l = frame:PointToObjectSpace(cf.Position)
		if not interior then
			if hasAny(lower, TURN_LAMPS) then
				table.insert(lamps.turn, p)
			elseif hasAny(lower, HEAD_LAMPS) then
				table.insert(lamps.head, p)
			elseif hasAny(lower, TAIL_LAMPS) then
				table.insert(lamps.tail, p)
			elseif hasAny(lower, ANY_LAMP) and not hasAny(lower, NOT_LAMP) then
				table.insert(if l.Z < 0 then lamps.head else lamps.tail, p)
			end
		end
		if interior or hasAny(lower, NO_COLLIDE_BOX) or p.Transparency >= 0.99 or math.max(s.X, s.Y, s.Z) < 0.5 then
			continue
		end
		if p.Parent and p.Parent:IsA("Model") and p.Parent ~= model and p.Parent:GetAttribute("LOD") == "near" then
			continue -- fine exterior detail (handles, badges, wipers)
		end
		local hx, hy, hz = halfAlong(cf, s, fX), halfAlong(cf, s, fY), halfAlong(cf, s, fZ)
		bb.x0, bb.x1 = math.min(bb.x0, l.X - hx), math.max(bb.x1, l.X + hx)
		bb.y0, bb.y1 = math.min(bb.y0, l.Y - hy), math.max(bb.y1, l.Y + hy)
		bb.z0, bb.z1 = math.min(bb.z0, l.Z - hz), math.max(bb.z1, l.Z + hz)
		if math.abs(l.Z - frontAxleZ) < 1.6 and math.abs(l.X) < 1.5 and p.Transparency < 0.3 then
			frontTop = math.max(frontTop, l.Y + hy)
		end
	end
	if bb.x0 == math.huge then
		return nil, "no body parts"
	end
	local roofY = bb.y1
	if frontTop == -math.huge then
		frontTop = roofY * 0.7
	end

	-- 6) seats ------------------------------------------------------------------------------------------
	local cushions = {}
	for _, p in parts do
		if SEAT_NAMES[p.Name] and not owner[p] then
			local l = frame:PointToObjectSpace(p.CFrame.Position)
			local hx = halfAlong(p.CFrame, p.Size, fX)
			local hy = halfAlong(p.CFrame, p.Size, fY)
			if l.Y > 0.3 and l.Y < roofY - 1 then
				table.insert(cushions, { l = l, w = 2 * hx, top = l.Y + hy, part = p })
			end
		end
	end
	local seats = {}
	if #cushions > 0 then
		local frontZ = math.huge
		for _, c in cushions do
			frontZ = math.min(frontZ, c.l.Z)
		end
		local driver, driverX = nil, math.huge
		for _, c in cushions do
			if c.l.Z <= frontZ + 1.0 and c.l.X < driverX then
				driver, driverX = c, c.l.X
			end
		end
		local function seatAt(x: number, c: any, role: string)
			table.insert(seats, { pos = Vector3.new(x, c.top, c.l.Z), role = role, width = c.w })
		end
		if driver then
			if driver.w >= 3 then -- front bench: driver on its left half
				seatAt(driver.l.X - driver.w / 4, driver, "driver")
				seatAt(driver.l.X + driver.w / 4, driver, "front")
			else
				seatAt(driver.l.X, driver, "driver")
			end
		end
		table.sort(cushions, function(a, b)
			if math.abs(a.l.Z - b.l.Z) > 0.5 then
				return a.l.Z < b.l.Z
			end
			return a.l.X > b.l.X
		end)
		for _, c in cushions do
			if c ~= driver then
				local role = if c.l.Z <= frontZ + 1.0 then "front" else "rear"
				if c.w >= 3 then
					seatAt(c.l.X + c.w / 4, c, role)
					seatAt(c.l.X - c.w / 4, c, role)
				else
					seatAt(c.l.X, c, role)
				end
			end
		end
	end
	if bike and #seats == 1 then
		-- one long saddle: the rider a little forward, a pillion seat behind
		local drvSeat = seats[1]
		table.insert(seats, { pos = drvSeat.pos + Vector3.new(0, 0.05, 0.6), role = "rear", width = drvSeat.width })
		drvSeat.pos += Vector3.new(0, 0, -0.2)
	end
	if #seats == 0 then
		-- geometry fallback: a driver seat behind the front axle on the left
		local z = frontAxleZ + wheelbase * 0.42
		table.insert(seats, { pos = Vector3.new((bb.x0 + bb.x1) / 2 - (bb.x1 - bb.x0) * 0.2, math.min(2.1, roofY * 0.45), z), role = "driver", width = 1.6 })
		table.insert(seats, { pos = Vector3.new((bb.x0 + bb.x1) / 2 + (bb.x1 - bb.x0) * 0.2, math.min(2.1, roofY * 0.45), z), role = "front", width = 1.6 })
	end

	-- 7) camera / door points ------------------------------------------------------------------------------
	local drv = seats[1]
	local halfW = math.max(math.abs(bb.x0), math.abs(bb.x1))
	local info = {
		kind = kind,
		bike = bike,
		frame = frame,
		L = bb.z1 - bb.z0,
		W = bb.x1 - bb.x0,
		H = roofY,
		box = bb,
		clearance = math.max(0, bb.y0),
		wheels = wheels,
		wheelbase = wheelbase,
		seats = seats,
		lamps = lamps,
		body = body,
		frontTop = frontTop,
		eye = drv.pos + Vector3.new(0, math.clamp(roofY - drv.pos.Y - 0.55, 1.6, 2.45), 0.15),
		hood = Vector3.new(0, frontTop + 1.05, math.max(bb.z0 + 1.5, frontAxleZ + 1.2)),
		doorDriver = Vector3.new(-(halfW + 0.4), drv.pos.Y + 0.4, drv.pos.Z),
		doorPassenger = Vector3.new(halfW + 0.4, drv.pos.Y + 0.4, (seats[2] and seats[2].pos.Z) or drv.pos.Z),
		lod = {},
	}
	for _, ch in model:GetChildren() do
		if ch:IsA("Model") and ch:GetAttribute("LOD") == "near" then
			table.insert(info.lod, ch)
		end
	end
	return info, nil
end

-- A complete vehicle: a two-wheeler with its front and rear wheel, or a car with a wheel at every corner
-- (front left / right, rear left / right). Parked map cars missing a wheel stay scenery.
function Analyze.complete(info: any): boolean
	if type(info) ~= "table" or type(info.wheels) ~= "table" then
		return false
	end
	local fl, fr, rl, rr, f, r = false, false, false, false, false, false
	for _, wh in info.wheels do
		if wh.front then
			f = true
			if wh.side < 0 then
				fl = true
			elseif wh.side > 0 then
				fr = true
			end
		else
			r = true
			if wh.side < 0 then
				rl = true
			elseif wh.side > 0 then
				rr = true
			end
		end
	end
	if info.bike then
		return f and r
	end
	return fl and fr and rl and rr
end

return Analyze
end)()
local function dumpInfo(key, m, info, err)
	if not info then print(key, "ANALYZE FAILED", err) return end
	local keys = {}
	for k, v in info do table.insert(keys, k .. "=" .. typeof(v)) end
	table.sort(keys)
	print(key, "fields:", table.concat(keys, " "))
	print(key, "wheels", #(info.wheels or {}), "complete", Analyze.complete(info), "seats", info.seats and #info.seats)
	for i, w in info.wheels or {} do
		print("  wheel", i, "front", w.front, "side", w.side, "parts", w.parts and #w.parts or (w.spin and #w.spin), "r", w.radius)
	end
	local n = 0
	for _, d in m:GetDescendants() do if d:IsA("BasePart") then n += 1 end end
	print(key, "parts", n)
	if info.frame then print(key, "frame look", info.frame.LookVector, "pos", info.frame.Position) end
	print(key, "L W H", info.L, info.W, info.H, "clear", info.clearance, "wb", info.wheelbase, "box", info.box and (info.box.size or info.box.Size), "frontTop", info.frontTop)
	if info.lamps then for k, v in info.lamps do local names = {} if typeof(v) == "table" then for _, x in v do table.insert(names, if typeof(x) == "Instance" then x.Name else typeof(x)) end end print("  lamps", k, table.concat(names, ",")) end end
end
for _, key in { "hyper", "super" } do
	local m = CarBodies.build(key, Color3.fromRGB(196, 18, 36), Color3.fromRGB(170, 90, 255))
	m:SetAttribute("VehicleKind", "gw_" .. key)
	local ok, info, err = pcall(Analyze.run, m)
	if not ok then print(key, "ERROR", info) else dumpInfo(key, m, info, err) end
	local fr, ext = CarBodies.frameOf(m)
	print(key, "frameOf look", fr.LookVector, "ext", ext)
end
-- a kit-car-like sedan (Spawn.fallbackCar shape) for the VIP / offroad kits
local function kitCar()
	local m = Instance.new("Model")
	local function box(name, size, pos, color, parent)
		local p = Instance.new("Part"); p.Name = name; p.Size = size; p.CFrame = CFrame.new(pos); p.Color = color; p.Anchored = true; p.Parent = parent or m; return p
	end
	local L, W = 16, 6.2
	box("Underbody", Vector3.new(W - 0.7, 0.5, L - 2), Vector3.new(0, 0.75, 0), Color3.fromRGB(26, 26, 28))
	box("BodySide", Vector3.new(W, 1.9, L), Vector3.new(0, 1.95, 0), Color3.fromRGB(236, 237, 236))
	box("Roof", Vector3.new(W - 0.6, 1.4, L * 0.5), Vector3.new(0, 3.6, 0.8), Color3.fromRGB(236, 237, 236))
	box("Windshield", Vector3.new(W - 0.8, 1.2, 0.2), Vector3.new(0, 3.6, -L * 0.25 + 0.9), Color3.fromRGB(36, 46, 52)).Transparency = 0.5
	box("Grille", Vector3.new(W * 0.5, 0.6, 0.2), Vector3.new(0, 1.8, -L / 2 - 0.05), Color3.fromRGB(20, 20, 22))
	box("HeadlampLens", Vector3.new(1, 0.4, 0.2), Vector3.new(-W / 2 + 0.9, 2.3, -L / 2 - 0.05), Color3.fromRGB(208, 216, 226))
	box("TailLamp", Vector3.new(1.2, 0.4, 0.2), Vector3.new(W / 2 - 0.9, 2.4, L / 2 + 0.05), Color3.fromRGB(150, 14, 22))
	box("PlateRear", Vector3.new(1.74, 0.37, 0.1), Vector3.new(0, 1.4, L / 2 + 0.06), Color3.new(1, 1, 1))
	local int = Instance.new("Model"); int.Name = "Interior"; int.Parent = m
	box("SeatCushion", Vector3.new(1.7, 0.48, 1.75), Vector3.new(-1.25, 1.75, 0), Color3.new(), int)
	box("SeatCushion", Vector3.new(1.7, 0.48, 1.75), Vector3.new(1.25, 1.75, 0), Color3.new(), int)
	local d = 2.2
	for _, z in { -L * 0.3, L * 0.28 } do for _, s in { -1, 1 } do
		local t = box("Tyre", Vector3.new(0.78, d, d), Vector3.new(s * (W / 2 - 0.45), d / 2, z), Color3.new()); t.Shape = Enum.PartType.Cylinder
		box("Rim", Vector3.new(0.8, d * 0.6, d * 0.6), Vector3.new(s * (W / 2 - 0.45), d / 2, z), Color3.new(0.7,0.7,0.7)).Shape = Enum.PartType.Cylinder
	end end
	m:PivotTo(CFrame.new(100, 5, 50) * CFrame.Angles(0, math.rad(37), 0))
	return m
end
for _, which in { "vip", "offroad" } do
	local m = kitCar()
	local fr, ext = CarBodies.frameOf(m)
	print(which, "frameOf look", fr.LookVector, "pos", fr.Position, "ext", ext)
	if which == "vip" then CarBodies.kitVip(m, Color3.new(1, 1, 1)) else CarBodies.kitOffroad(m, { lift = 0.9, tyreGrow = 0.55 }) end
	m:SetAttribute("VehicleKind", "gw_" .. which)
	local ok, info, err = pcall(Analyze.run, m)
	if not ok then print(which, "ERROR", info) else print(which, "wheels", #(info.wheels or {}), "complete", Analyze.complete(info), "seats", #(info.seats or {}), "clear", info.clearance, "H", info.H, "L", info.L) end
	for _, w in info.wheels or {} do print("  wheel parts", #(w.parts or {})) end
end
