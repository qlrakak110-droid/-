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
			kitPart(kit, frame, "MudFlap", Vector3.new(t.Size.X, 1.0, 0.08), l.X, 0.55 + lift * 0.5, l.Z + t.Size.Y / 2 + 0.25, Color3.fromRGB(20, 20, 20), Enum.Material.Rubber)
		end
	end
end

return CarBodies
