-- GwangalliBuildings/Kit: the part-building toolkit every building template uses (server builders and
-- client previews). All "local" helpers take a frame CFrame (the building / unit / room frame) and
-- coordinates in that frame, so templates are written once and placed anywhere.
--
--   Kit.part(parent, cf, size, material, color, opts)              -> Part (world CFrame)
--   Kit.box(parent, frame, x0, y0, z0, x1, y1, z1, mat, col, opts)   -> Part (local axis-aligned box)
--   Kit.wallX / Kit.wallZ (walls with door / window holes)           -> { Part }
--   Kit.ramp(parent, frame, p0, p1, width, opts)                     -> invisible walkable plank
--   Kit.flight(parent, frame, x0, x1, z0, z1, y0, y1, mat, col)      -> visual steps + collider
--   Kit.text(part, face, text, opts)                                 -> SurfaceGui, TextLabel
--   Kit.light(part, kind, opts)                                      -> Light
-- opts: { name, tr, collide, query, touch, shadow, refl, shape, tags = {..}, attrs = {..} }
--
-- Build budget: Kit.setBudget(n) makes every n created parts call task.wait() (server builders run in
-- their own thread), so generating a building never freezes a frame. Kit.setBudget(nil) = no yields.

local CollectionService = game:GetService("CollectionService")

local Kit = {}

local V3, CF = Vector3.new, CFrame.new
local abs, max, min, floor, ceil = math.abs, math.max, math.min, math.floor, math.ceil

-------------------------------------------------------------------------------------------------
-- budget
-------------------------------------------------------------------------------------------------
local budgetN: number? = nil
local made = 0
local sliceT0 = 0
local SLICE = 0.04 -- never hold a frame longer than this while building (slow phones)
Kit.created = 0

function Kit.setBudget(n: number?)
	budgetN = n
	made = 0
	sliceT0 = os.clock()
end

local function tick()
	Kit.created += 1
	if budgetN then
		made += 1
		if made >= budgetN or (made % 16 == 0 and os.clock() - sliceT0 > SLICE) then
			made = 0
			task.wait()
			sliceT0 = os.clock()
		end
	end
end
Kit.tick = tick

-------------------------------------------------------------------------------------------------
-- materials (guarded: unknown names fall back so an older engine never errors)
-------------------------------------------------------------------------------------------------
local matCache: { [string]: Enum.Material } = {}
function Kit.mat(name: any): Enum.Material
	if typeof(name) == "EnumItem" then
		return name :: any
	end
	local m = matCache[name]
	if m then
		return m
	end
	local ok, v = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	local FALLBACK = {
		CeramicTiles = "Slate",
		Plaster = "SmoothPlastic",
		Carpet = "Fabric",
		Leather = "Fabric",
		RoofShingles = "Slate",
		ClayRoofTiles = "Brick",
		Rubber = "Plastic",
		Cardboard = "Wood",
	}
	if not ok or v == nil then
		local fb = FALLBACK[name] or "SmoothPlastic"
		v = (Enum.Material :: any)[fb]
	end
	matCache[name] = v
	return v
end

local function col(c: any): Color3
	if typeof(c) == "Color3" then
		return c
	elseif type(c) == "table" then
		return Color3.fromRGB(c[1], c[2], c[3])
	end
	return Color3.fromRGB(200, 200, 200)
end
Kit.col = col

-------------------------------------------------------------------------------------------------
-- tags / attributes
-------------------------------------------------------------------------------------------------
function Kit.tag(inst: Instance, tag: string)
	CollectionService:AddTag(inst, tag)
end

function Kit.attrs(inst: Instance, attrs: { [string]: any }?)
	if attrs then
		for k, v in attrs do
			inst:SetAttribute(k, v)
		end
	end
end

function Kit.model(parent: Instance?, name: string, attrs: { [string]: any }?, tags: { string }?): Model
	local m = Instance.new("Model")
	m.Name = name
	Kit.attrs(m, attrs)
	if tags then
		for _, t in tags do
			CollectionService:AddTag(m, t)
		end
	end
	m.Parent = parent
	return m
end

function Kit.folder(parent: Instance?, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-------------------------------------------------------------------------------------------------
-- parts
-------------------------------------------------------------------------------------------------
local SHAPES = {
	block = Enum.PartType.Block,
	cyl = Enum.PartType.Cylinder,
	ball = Enum.PartType.Ball,
}

function Kit.part(parent: Instance?, cf: CFrame, size: Vector3, material: any?, color: any?, opts: any?): BasePart
	local o = opts or {}
	local p: BasePart
	if o.wedge then
		p = Instance.new("WedgePart")
	elseif o.seat then
		local s = Instance.new("Seat")
		s.Disabled = true
		p = s
	else
		local q = Instance.new("Part")
		if o.shape then
			q.Shape = SHAPES[o.shape] or Enum.PartType.Block
		end
		p = q
	end
	p.Anchored = true
	p.Size = V3(max(size.X, 0.05), max(size.Y, 0.05), max(size.Z, 0.05))
	p.CFrame = cf
	p.Material = Kit.mat(material or "SmoothPlastic")
	p.Color = col(color)
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if o.tr then
		p.Transparency = o.tr
	end
	if o.refl then
		p.Reflectance = o.refl
	end
	if o.collide == false then
		p.CanCollide = false
	end
	if o.query == false then
		p.CanQuery = false
	end
	if o.touch == false or o.collide == false then
		p.CanTouch = false
	end
	if o.shadow == false then
		p.CastShadow = false
	end
	p.Name = o.name or "Part"
	if o.attrs then
		Kit.attrs(p, o.attrs)
	end
	if o.tags then
		for _, t in o.tags do
			CollectionService:AddTag(p, t)
		end
	end
	p.Parent = parent
	tick()
	return p
end

function Kit.at(frame: CFrame, x: number, y: number, z: number): CFrame
	return frame * CF(x, y, z)
end

-- local axis-aligned box between two corners
function Kit.box(parent: Instance?, frame: CFrame, x0: number, y0: number, z0: number, x1: number, y1: number, z1: number, material: any?, color: any?, opts: any?): BasePart
	local sx, sy, sz = abs(x1 - x0), abs(y1 - y0), abs(z1 - z0)
	return Kit.part(parent, frame * CF((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), V3(sx, sy, sz), material, color, opts)
end

-- local box from a centre and a size, rotated by yaw degrees about Y
function Kit.cbox(parent: Instance?, frame: CFrame, cx: number, cy: number, cz: number, sx: number, sy: number, sz: number, material: any?, color: any?, opts: any?, yaw: number?): BasePart
	local cf = frame * CF(cx, cy, cz)
	if yaw and yaw ~= 0 then
		cf *= CFrame.Angles(0, math.rad(yaw), 0)
	end
	return Kit.part(parent, cf, V3(sx, sy, sz), material, color, opts)
end

-- cylinder between two local points (Roblox cylinders run along their X axis)
function Kit.rod(parent: Instance?, frame: CFrame, a: Vector3, b: Vector3, dia: number, material: any?, color: any?, opts: any?): BasePart
	local wa, wb = frame * a, frame * b
	local len = (wb - wa).Magnitude
	local mid = (wa + wb) / 2
	local cf = CFrame.lookAt(mid, wb) * CFrame.Angles(0, math.rad(90), 0)
	local o = table.clone(opts or {})
	o.shape = "cyl"
	return Kit.part(parent, cf, V3(len, dia, dia), material, color, o)
end

-- vertical cylinder (a round table top, a column, a pot) centred at local (x, y, z)
function Kit.vcyl(parent: Instance?, frame: CFrame, x: number, y: number, z: number, height: number, dia: number, material: any?, color: any?, opts: any?): BasePart
	local o = table.clone(opts or {})
	o.shape = "cyl"
	return Kit.part(parent, frame * CF(x, y, z) * CFrame.Angles(0, 0, math.rad(90)), V3(height, dia, dia), material, color, o)
end

function Kit.ball(parent: Instance?, frame: CFrame, x: number, y: number, z: number, dia: number, material: any?, color: any?, opts: any?): BasePart
	local o = table.clone(opts or {})
	o.shape = "ball"
	return Kit.part(parent, frame * CF(x, y, z), V3(dia, dia, dia), material, color, o)
end

-------------------------------------------------------------------------------------------------
-- walls with holes
-------------------------------------------------------------------------------------------------
-- holes: { {a0, a1, b0, b1}, ... } along the wall (a) and in height (b). Returns the pieces.
local function wallPieces(a0: number, a1: number, y0: number, y1: number, holes: { any }?): { { number } }
	local out = {}
	local hs = {}
	for _, h in (holes or {}) :: { any } do
		local ha0, ha1 = max(a0, min(h[1], h[2])), min(a1, max(h[1], h[2]))
		local hb0, hb1 = max(y0, h[3]), min(y1, h[4])
		if ha1 - ha0 > 0.01 and hb1 - hb0 > 0.01 then
			table.insert(hs, { ha0, ha1, hb0, hb1 })
		end
	end
	table.sort(hs, function(p, q)
		return p[1] < q[1]
	end)
	-- cut points
	local cuts = { a0, a1 }
	for _, h in hs do
		table.insert(cuts, h[1])
		table.insert(cuts, h[2])
	end
	table.sort(cuts)
	local runStart: number? = nil
	local runEnd = a0
	for i = 1, #cuts - 1 do
		local s, e = cuts[i], cuts[i + 1]
		if e - s > 0.001 then
			local mid = (s + e) / 2
			-- vertical spans blocked by holes covering this interval
			local spans = {}
			for _, h in hs do
				if h[1] <= mid and mid <= h[2] then
					table.insert(spans, { h[3], h[4] })
				end
			end
			if #spans == 0 then
				runStart = runStart or s
				runEnd = e
			else
				if runStart then
					table.insert(out, { runStart, runEnd, y0, y1 })
					runStart = nil
				end
				table.sort(spans, function(p, q)
					return p[1] < q[1]
				end)
				local y = y0
				for _, sp in spans do
					if sp[1] - y > 0.01 then
						table.insert(out, { s, e, y, sp[1] })
					end
					y = max(y, sp[2])
				end
				if y1 - y > 0.01 then
					table.insert(out, { s, e, y, y1 })
				end
			end
		end
	end
	if runStart then
		table.insert(out, { runStart, runEnd, y0, y1 })
	end
	return out
end
Kit.wallPieces = wallPieces

-- wall along local X (from x0 to x1) centred at z = zc, thickness t, from y0 to y1
function Kit.wallX(parent: Instance?, frame: CFrame, x0: number, x1: number, zc: number, t: number, y0: number, y1: number, holes: { any }?, material: any?, color: any?, opts: any?): { BasePart }
	local out = {}
	for _, pc in wallPieces(min(x0, x1), max(x0, x1), y0, y1, holes) do
		table.insert(out, Kit.box(parent, frame, pc[1], pc[3], zc - t / 2, pc[2], pc[4], zc + t / 2, material, color, opts))
	end
	return out
end

-- wall along local Z (from z0 to z1) centred at x = xc
function Kit.wallZ(parent: Instance?, frame: CFrame, z0: number, z1: number, xc: number, t: number, y0: number, y1: number, holes: { any }?, material: any?, color: any?, opts: any?): { BasePart }
	local out = {}
	for _, pc in wallPieces(min(z0, z1), max(z0, z1), y0, y1, holes) do
		table.insert(out, Kit.box(parent, frame, xc - t / 2, pc[3], pc[1], xc + t / 2, pc[4], pc[2], material, color, opts))
	end
	return out
end

-------------------------------------------------------------------------------------------------
-- ramps and stairs
-------------------------------------------------------------------------------------------------
-- a thin plank whose TOP surface runs from local point p0 to p1 (width across). Invisible by default:
-- the walkable collider under visual steps, parking ramps, wheelchair ramps.
function Kit.ramp(parent: Instance?, frame: CFrame, p0: Vector3, p1: Vector3, width: number, opts: any?): BasePart
	local o = opts or {}
	local th = o.thick or 0.6
	local w0, w1 = frame * p0, frame * p1
	local d = w1 - w0
	local mid = (w0 + w1) / 2
	local cf = CFrame.lookAt(mid, mid + d.Unit)
	cf = cf - cf.UpVector * (th / 2)
	local po = table.clone(o)
	if po.tr == nil then
		po.tr = 1
	end
	po.name = po.name or "Ramp"
	po.shadow = false
	return Kit.part(parent, cf, V3(width, th, d.Magnitude), o.material or "SmoothPlastic", o.color or { 120, 120, 120 }, po)
end

-- one straight flight of steps in local space: across x0..x1, climbing from (z0, y0) to (z1, y1)
-- (z1 may be smaller than z0: the flight then runs toward -z). Visual treads + risers do not collide;
-- one invisible ramp through the nosings does (smooth walking for every avatar / camera).
function Kit.flight(parent: Instance?, frame: CFrame, x0: number, x1: number, z0: number, z1: number, y0: number, y1: number, material: any?, color: any?, opts: any?)
	local o = opts or {}
	local rise = y1 - y0
	local n = max(2, ceil(abs(rise) / (o.maxRise or 0.78)))
	local r = rise / n
	-- n risers: the first at z0, the last at z1 (the upper landing's edge); n - 1 treads in between
	local run = (z1 - z0) / (n - 1)
	local dirz = if run > 0 then 1 else -1
	local nose = o.noseColor
	for k = 1, n - 1 do
		local za, zb = z0 + (k - 1) * run, z0 + k * run
		local top = y0 + k * r
		Kit.box(parent, frame, x0, top - r, min(za, zb), x1, top, max(za, zb), material, color, { collide = false, name = "Step" })
		if nose then
			Kit.box(parent, frame, x0, top - 0.1, za - 0.04 * dirz, x1, top + 0.02, za + 0.2 * dirz, "SmoothPlastic", nose, { collide = false, name = "Nosing" })
		end
	end
	-- soffit (the underside slab of the flight)
	if o.soffit ~= false then
		local th = 0.8
		local p0 = V3((x0 + x1) / 2, y0 - th * 0.5, z0)
		local p1 = V3((x0 + x1) / 2, y1 - r - th * 0.5, z1)
		Kit.ramp(parent, frame, p0, p1, abs(x1 - x0), { tr = 0, thick = th, collide = false, material = material, color = color, name = "Soffit" })
	end
	-- walkable collider through every nosing, from one run before the first riser (on the lower
	-- landing, flush with it) to the upper landing's edge
	Kit.ramp(parent, frame, V3((x0 + x1) / 2, y0, z0 - run), V3((x0 + x1) / 2, y1, z1), abs(x1 - x0), { name = "StairRamp" })
end

-- handrail along a straight line (local points), on posts every ~3 studs
function Kit.rail(parent: Instance?, frame: CFrame, a: Vector3, b: Vector3, height: number, material: any?, color: any?, opts: any?)
	local o = opts or {}
	local up = V3(0, height, 0)
	Kit.rod(parent, frame, a + up, b + up, o.dia or 0.22, material, color, { collide = false })
	local len = (b - a).Magnitude
	local n = max(1, floor(len / (o.spacing or 3)))
	for i = 0, n do
		local p = a:Lerp(b, i / n)
		Kit.rod(parent, frame, p, p + up, o.postDia or 0.16, material, color, { collide = false })
	end
	if o.solid then
		-- glass / metal panel below the rail (also a collider so nobody walks off a balcony)
		local mid = (a + b) / 2 + up / 2
		local cf = frame * CFrame.lookAt(mid, mid + (b - a).Unit)
		Kit.part(parent, cf, V3(0.12, height, len), o.panelMat or "Glass", o.panelColor or { 170, 200, 210 }, { tr = o.panelTr or 0.55, name = "RailPanel" })
	elseif o.collide ~= false then
		local mid = (a + b) / 2 + up / 2
		local cf = frame * CFrame.lookAt(mid, mid + (b - a).Unit)
		Kit.part(parent, cf, V3(0.2, height + 0.4, len), "SmoothPlastic", { 0, 0, 0 }, { tr = 1, name = "RailBlock", shadow = false })
	end
end

-------------------------------------------------------------------------------------------------
-- text, lights, sounds
-------------------------------------------------------------------------------------------------
local FACES = {
	front = Enum.NormalId.Front,
	back = Enum.NormalId.Back,
	left = Enum.NormalId.Left,
	right = Enum.NormalId.Right,
	top = Enum.NormalId.Top,
	bottom = Enum.NormalId.Bottom,
}

-- SurfaceGui with one TextLabel. opts: { color, bg, bgTr, font, bold, ppS (pixels per stud), light (0..),
-- stroke, align, wrap }
function Kit.text(part: BasePart, face: string, text: string, opts: any?): (SurfaceGui, TextLabel)
	local o = opts or {}
	local g = Instance.new("SurfaceGui")
	g.Name = o.name or "Text"
	g.Face = FACES[face] or Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = o.ppS or 40
	g.LightInfluence = o.light or 0
	g.Brightness = o.brightness or 1
	g.AlwaysOnTop = false
	g.MaxDistance = o.maxDist or 260
	local t = Instance.new("TextLabel")
	t.Name = "Label"
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundColor3 = col(o.bg or { 0, 0, 0 })
	t.BackgroundTransparency = if o.bg then (o.bgTr or 0) else 1
	t.Text = text
	t.TextColor3 = col(o.color or { 255, 255, 255 })
	t.TextScaled = true
	t.TextWrapped = o.wrap ~= false
	t.Font = o.font or (if o.bold == false then Enum.Font.GothamMedium else Enum.Font.GothamBold)
	if o.stroke then
		t.TextStrokeTransparency = 0.2
		t.TextStrokeColor3 = col(o.stroke)
	end
	if o.align == "left" then
		t.TextXAlignment = Enum.TextXAlignment.Left
	elseif o.align == "right" then
		t.TextXAlignment = Enum.TextXAlignment.Right
	end
	local pad = Instance.new("UIPadding")
	local px = o.pad or 0.06
	pad.PaddingLeft = UDim.new(px, 0)
	pad.PaddingRight = UDim.new(px, 0)
	pad.PaddingTop = UDim.new(px * 0.8, 0)
	pad.PaddingBottom = UDim.new(px * 0.8, 0)
	pad.Parent = t
	t.Parent = g
	g.Parent = part
	tick()
	return g, t
end

-- light on a part. kind = "point" | "spot" | "surface". opts: { color, brightness, range, face, angle,
-- shadows, tag = true (GwB_Light), attrs }
function Kit.light(part: BasePart, kind: string, opts: any?): Light
	local o = opts or {}
	local l: Light
	if kind == "spot" then
		local s = Instance.new("SpotLight")
		s.Face = FACES[o.face or "bottom"]
		s.Angle = o.angle or 90
		s.Range = o.range or 16
		l = s
	elseif kind == "surface" then
		local s = Instance.new("SurfaceLight")
		s.Face = FACES[o.face or "bottom"]
		s.Angle = o.angle or 90
		s.Range = o.range or 14
		l = s
	else
		local s = Instance.new("PointLight")
		s.Range = o.range or 16
		l = s
	end
	l.Color = col(o.color or { 255, 236, 210 })
	l.Brightness = o.brightness or 1.2
	l.Shadows = o.shadows == true
	if o.attrs then
		Kit.attrs(l, o.attrs)
	end
	if o.tag ~= false then
		CollectionService:AddTag(l, "GwB_Light")
	end
	if o.tags then
		for _, t in o.tags do
			CollectionService:AddTag(l, t)
		end
	end
	l.Parent = part
	tick()
	return l
end

-- ambient sound emitter: an Attachment carrying the contract attributes (the client creates the Sound
-- when the camera is near and the sound library has an id for the key)
function Kit.sound(part: BasePart, key: string, opts: any?): Attachment
	local o = opts or {}
	local a = Instance.new("Attachment")
	a.Name = "Snd_" .. key
	if o.offset then
		a.Position = o.offset
	end
	a:SetAttribute("SoundKey", key)
	a:SetAttribute("Volume", o.volume or 0.4)
	a:SetAttribute("MaxDist", o.maxDist or 40)
	a:SetAttribute("Loop", o.loop ~= false)
	if o.attrs then
		Kit.attrs(a, o.attrs)
	end
	CollectionService:AddTag(a, "GwB_Sound")
	a.Parent = part
	return a
end

-- ProximityPrompt helper (server)
function Kit.prompt(parent: Instance, action: string, object: string?, opts: any?): ProximityPrompt
	local o = opts or {}
	local p = Instance.new("ProximityPrompt")
	p.Name = o.name or "Prompt"
	p.ActionText = action
	p.ObjectText = object or ""
	p.MaxActivationDistance = o.dist or 7
	p.HoldDuration = o.hold or 0
	p.RequiresLineOfSight = o.los == true
	p.KeyboardKeyCode = o.key or Enum.KeyCode.E
	p.Style = Enum.ProximityPromptStyle.Default
	if o.exclusivity then
		p.Exclusivity = o.exclusivity
	end
	p.Parent = parent
	return p
end

-- invisible anchor part (prompts, spots) at a local CFrame
function Kit.anchor(parent: Instance?, cf: CFrame, name: string, attrs: any?, tags: { string }?, size: Vector3?): BasePart
	return Kit.part(parent, cf, size or V3(1, 1, 1), "SmoothPlastic", { 255, 255, 255 }, {
		tr = 1,
		collide = false,
		name = name,
		attrs = attrs,
		tags = tags,
		shadow = false,
	})
end

return Kit
