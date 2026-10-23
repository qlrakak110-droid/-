--!nocheck
local R = require("../../../bprev/lib/rbx")
local E = R.env
local game, workspace, Workspace, Instance, task, Enum, CFrame, Vector3, Color3, UDim2, UDim, Vector2, TweenInfo, typeof, warn = E.game, E.workspace, E.Workspace, E.Instance, E.task, E.Enum, E.CFrame, E.Vector3, E.Color3, E.UDim2, E.UDim, E.Vector2, E.TweenInfo, E.typeof, E.warn
local __CS = { AddTag = function(_, i, t) i:AddTag(t) end, HasTag = function(_, i, t) return i:HasTag(t) end, RemoveTag = function(_, i, t) i:RemoveTag(t) end }
local __Kit = (function()
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

local CollectionService = __CS

local Kit = {}

local V3, CF = Vector3.new, CFrame.new
local abs, max, min, floor, ceil = math.abs, math.max, math.min, math.floor, math.ceil

-------------------------------------------------------------------------------------------------
-- budget
-------------------------------------------------------------------------------------------------
local budgetN: number? = nil
local made = 0
local sliceT0 = 0
local SLICE = 0.004 -- [최적화] was 0.04: never hold an engine step longer than this while building
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
		if made >= budgetN or (made % 2 == 0 and os.clock() - sliceT0 > SLICE) then
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

end)()
local __Furniture = (function()
-- GwangalliBuildings/Furniture: the furniture CATALOG and the builders of every piece.
--
-- A piece is a Model whose pivot is the centre of its footprint on the floor, front = -Z (the side you
-- use it from). Every model has an invisible PrimaryPart "Base" (w x h x d, no collision, queryable) used
-- for selection, placement overlap tests and prompts. Interactive pieces carry tag GwB_Fixture with
-- attribute Kind (Furniture.KINDS: what the prompts do) and are wired by the server Interact service.
--
--   Furniture.build(itemId, parent, cf, colorway?, extraAttrs?) -> Model
--   Furniture.ITEMS[itemId] = { name, cat, price, w, d, h, kind?, wall?, colors = {...}, build = fn }
--   Furniture.KINDS[kind]   = { prompt, hold?, rights = "owner" | "guest" | "anyone" }
-- Built-in fixtures of the unit templates (kitchen counter, toilet, shower...) use the same builders with
-- `fixed = true` (not sellable / movable).

local CollectionService = __CS

local Kit = __Kit

local Furniture = {}

local V3, CF = Vector3.new, CFrame.new
local rad = math.rad

-------------------------------------------------------------------------------------------------
-- interaction kinds (prompt text, rights). rights: who may use it inside a home
--   owner  = the owner and invited guests; anyone = every player (shops, hotels, common areas use
--   "anyone" through the fixture attribute Public = true)
-------------------------------------------------------------------------------------------------
Furniture.KINDS = {
	bed = { prompt = "눕기", alt = "잠자기", rights = "guest" },
	seat = { prompt = "앉기", rights = "guest" },
	tv = { prompt = "TV 켜기", alt = "채널 변경", rights = "guest" },
	fridge = { prompt = "냉장고 열기", rights = "guest" },
	microwave = { prompt = "전자레인지", rights = "guest" },
	shower = { prompt = "샤워하기", rights = "guest" },
	bathtub = { prompt = "반신욕", rights = "guest" },
	toilet = { prompt = "사용하기", rights = "guest" },
	sink = { prompt = "손 씻기", rights = "guest" },
	washer = { prompt = "세탁 시작", rights = "owner" },
	lamp = { prompt = "스위치", rights = "guest" },
	aircon = { prompt = "에어컨 켜기", rights = "guest" },
	fan = { prompt = "선풍기 켜기", rights = "guest" },
	wardrobe = { prompt = "옷장 열기", rights = "owner" },
	pc = { prompt = "컴퓨터 하기", rights = "guest" },
	wallpad = { prompt = "월패드", rights = "owner" },
	massage = { prompt = "안마의자", rights = "guest" },
	cook = { prompt = "요리하기", rights = "owner" },
	exercise = { prompt = "운동하기", rights = "guest" },
	switch = { prompt = "불 켜기/끄기", rights = "guest" },
	window = { prompt = "창밖 보기", rights = "guest" },
	water = { prompt = "온수 받기", rights = "anyone" },
	dryer = { prompt = "핸드 드라이어", rights = "anyone" },
	vending = { prompt = "자판기", rights = "anyone" },
	-- 방 확장 (Grades.ROOMS)
	game = { prompt = "게임하기", rights = "guest" },
	cinema = { prompt = "영화 보기", rights = "guest" },
	popcorn = { prompt = "팝콘 만들기", rights = "guest" },
	lift = { prompt = "웨이트 운동", rights = "guest" },
	boxing = { prompt = "샌드백 치기", rights = "guest" },
	workbench = { prompt = "부품 손질", rights = "owner" },
	dress = { prompt = "코디하기", rights = "owner" },
	bar = { prompt = "칵테일 만들기", rights = "guest" },
	instrument = { prompt = "연주하기", rights = "guest" },
	office = { prompt = "재택 업무", rights = "owner" },
}

-------------------------------------------------------------------------------------------------
-- small builders
-------------------------------------------------------------------------------------------------
type Ctx = { m: Model, cf: CFrame, c: { any } }

local function B(x: Ctx, x0: number, y0: number, z0: number, x1: number, y1: number, z1: number, mat: string, color: any, opts: any?): BasePart
	local o = opts or {}
	if o.collide == nil and o.solid ~= true then
		o.collide = false -- furniture details never collide; the Base / Hit boxes do
	end
	return Kit.box(x.m, x.cf, x0, y0, z0, x1, y1, z1, mat, color, o)
end

-- collision box (invisible) so you cannot walk through big pieces
local function Hit(x: Ctx, x0: number, y0: number, z0: number, x1: number, y1: number, z1: number)
	Kit.box(x.m, x.cf, x0, y0, z0, x1, y1, z1, "SmoothPlastic", { 0, 0, 0 }, { tr = 1, name = "Hit", shadow = false })
end

local function Seat(x: Ctx, px: number, py: number, pz: number, yaw: number?, index: number?): BasePart
	local cf = x.cf * CF(px, py, pz) * CFrame.Angles(0, rad(yaw or 0), 0)
	local s = Kit.part(x.m, cf, V3(1.8, 0.3, 1.8), "SmoothPlastic", { 0, 0, 0 }, { seat = true, tr = 1, name = "Seat", shadow = false })
	s:SetAttribute("Index", index or 1)
	CollectionService:AddTag(s, "GwB_Seat")
	return s
end

local function Cyl(x: Ctx, px: number, py: number, pz: number, h: number, dia: number, mat: string, color: any, opts: any?): BasePart
	local o = opts or {}
	if o.collide == nil then
		o.collide = false
	end
	return Kit.vcyl(x.m, x.cf, px, py, pz, h, dia, mat, color, o)
end

local function Screen(x: Ctx, x0: number, y0: number, z0: number, x1: number, y1: number, z1: number, kind: string): BasePart
	local p = B(x, x0, y0, z0, x1, y1, z1, "SmoothPlastic", { 12, 12, 14 }, { name = "Screen" })
	p:SetAttribute("ScreenKind", kind)
	CollectionService:AddTag(p, "GwB_Screen")
	return p
end

local function Lamp(x: Ctx, part: BasePart, opts: any)
	part:SetAttribute("LampOff", part.Color)
	CollectionService:AddTag(part, "GwB_Lamp")
	local l = Kit.light(part, opts.kind or "point", opts)
	l.Enabled = opts.on == true
	return l
end

-------------------------------------------------------------------------------------------------
-- catalog
-------------------------------------------------------------------------------------------------
local ITEMS = {}
Furniture.ITEMS = ITEMS
Furniture.ORDER = {}

local function item(id: string, def: any)
	def.id = id
	ITEMS[id] = def
	table.insert(Furniture.ORDER, id)
end

Furniture.CATEGORIES = {
	{ id = "living", name = "거실" },
	{ id = "bedroom", name = "침실" },
	{ id = "kitchen", name = "주방" },
	{ id = "appliance", name = "가전" },
	{ id = "decor", name = "소품" },
	{ id = "hobby", name = "취미 · 운동" },
	{ id = "fixture", name = "설비", hidden = true },
}

-- 3인 소파 -------------------------------------------------------------------------------------
item("sofa3", {
	name = "패브릭 3인 소파",
	cat = "living",
	price = 450000,
	w = 8,
	d = 3.4,
	h = 3.2,
	wall = true,
	kind = "seat",
	colors = { { 120, 124, 132 }, { 196, 186, 168 }, { 52, 74, 96 }, { 150, 92, 70 } },
	build = function(x: Ctx)
		local c = x.c[1]
		B(x, -4, 0.4, -1.7, 4, 1.6, 1.7, "Fabric", c)
		B(x, -4, 1.6, 0.9, 4, 3.2, 1.7, "Fabric", c) -- back
		B(x, -4, 1.6, -1.7, -3.3, 2.4, 1.7, "Fabric", c) -- arms
		B(x, 3.3, 1.6, -1.7, 4, 2.4, 1.7, "Fabric", c)
		for i = -1, 1 do
			B(x, i * 2.2 - 1.05, 1.6, -1.6, i * 2.2 + 1.05, 2.05, 0.85, "Fabric", c:Lerp(Color3.new(1, 1, 1), 0.08))
		end
		for _, px in { -3.7, 3.7 } do
			for _, pz in { -1.4, 1.4 } do
				B(x, px - 0.15, 0, pz - 0.15, px + 0.15, 0.4, pz + 0.15, "Wood", { 60, 44, 32 })
			end
		end
		Hit(x, -4, 0, -1.7, 4, 2, 1.7)
		for i = -1, 1 do
			Seat(x, i * 2.2, 1.95, -0.3, 0, i + 2)
		end
	end,
})

item("armchair", {
	name = "라운지 암체어",
	cat = "living",
	price = 220000,
	w = 3.4,
	d = 3.4,
	h = 3.4,
	kind = "seat",
	colors = { { 176, 120, 74 }, { 70, 80, 90 }, { 210, 200, 186 } },
	build = function(x: Ctx)
		local c = x.c[1]
		B(x, -1.7, 0.6, -1.5, 1.7, 1.7, 1.5, "Leather", c)
		B(x, -1.7, 1.7, 0.9, 1.7, 3.4, 1.5, "Leather", c)
		B(x, -1.7, 1.7, -1.5, -1.3, 2.5, 1.5, "Leather", c)
		B(x, 1.3, 1.7, -1.5, 1.7, 2.5, 1.5, "Leather", c)
		Cyl(x, 0, 0.3, 0, 0.6, 1.4, "Metal", { 40, 40, 42 })
		Hit(x, -1.7, 0, -1.5, 1.7, 2, 1.5)
		Seat(x, 0, 2.0, -0.25, 0, 1)
	end,
})

item("coffee_table", {
	name = "원목 커피 테이블",
	cat = "living",
	price = 120000,
	w = 5,
	d = 2.6,
	h = 1.5,
	colors = { { 176, 136, 96 }, { 90, 62, 42 }, { 236, 236, 232 } },
	build = function(x: Ctx)
		B(x, -2.5, 1.2, -1.3, 2.5, 1.5, 1.3, "Wood", x.c[1])
		B(x, -2.2, 0.35, -1, 2.2, 0.5, 1, "Wood", x.c[1])
		for _, px in { -2.2, 2.2 } do
			for _, pz in { -1, 1 } do
				B(x, px - 0.15, 0, pz - 0.15, px + 0.15, 1.2, pz + 0.15, "Wood", x.c[1])
			end
		end
		Hit(x, -2.5, 0, -1.3, 2.5, 1.5, 1.3)
	end,
})

item("tv55", {
	name = "55인치 TV + 거실장",
	cat = "appliance",
	price = 890000,
	w = 7,
	d = 1.6,
	h = 5.6,
	wall = true,
	kind = "tv",
	colors = { { 236, 234, 230 }, { 70, 50, 36 }, { 34, 34, 36 } },
	build = function(x: Ctx)
		B(x, -3.5, 0, -0.8, 3.5, 1.5, 0.8, "Wood", x.c[1]) -- 거실장
		B(x, -3.4, 0.2, -0.82, 3.4, 1.3, -0.78, "SmoothPlastic", x.c[1]:Lerp(Color3.new(0, 0, 0), 0.15))
		B(x, -0.5, 1.5, -0.1, 0.5, 1.7, 0.4, "Metal", { 40, 40, 42 })
		B(x, -0.12, 1.7, 0.05, 0.12, 2.3, 0.2, "Metal", { 40, 40, 42 })
		B(x, -3.3, 2.2, 0.05, 3.3, 5.6, 0.35, "SmoothPlastic", { 22, 22, 24 }) -- bezel
		Screen(x, -3.15, 2.35, -0.0, 3.15, 5.45, 0.06, "tv")
		local led = B(x, 2.9, 2.28, -0.02, 3.0, 2.34, 0.02, "Neon", { 255, 60, 60 }, { name = "PowerLed" })
		led:SetAttribute("Led", true)
		Hit(x, -3.5, 0, -0.8, 3.5, 1.5, 0.8)
		Kit.sound(x.m.PrimaryPart or (x.m:FindFirstChild("Screen") :: BasePart), "tv_talk", { volume = 0.35, maxDist = 30, attrs = { Active = false } })
	end,
})

item("floor_lamp", {
	name = "아크 플로어 스탠드",
	cat = "decor",
	price = 98000,
	w = 1.6,
	d = 1.6,
	h = 6.2,
	kind = "lamp",
	colors = { { 245, 240, 228 }, { 30, 30, 32 } },
	build = function(x: Ctx)
		Cyl(x, 0, 0.1, 0, 0.2, 1.4, "Metal", { 40, 40, 42 })
		B(x, -0.08, 0.2, -0.08, 0.08, 5.2, 0.08, "Metal", { 40, 40, 42 })
		local shade = Cyl(x, 0, 5.6, 0, 1.0, 1.4, "Fabric", x.c[1], { name = "Shade" })
		Lamp(x, shade, { color = { 255, 214, 160 }, brightness = 1.1, range = 14 })
		Hit(x, -0.4, 0, -0.4, 0.4, 6, 0.4)
	end,
})

item("monstera", {
	name = "몬스테라 화분",
	cat = "decor",
	price = 59000,
	w = 2,
	d = 2,
	h = 4.6,
	colors = { { 236, 234, 228 }, { 120, 92, 70 }, { 60, 60, 62 } },
	build = function(x: Ctx)
		Cyl(x, 0, 0.8, 0, 1.6, 1.8, "Ceramic", x.c[1])
		Cyl(x, 0, 1.62, 0, 0.05, 1.6, "Ground", { 70, 52, 38 })
		for i = 1, 7 do
			local a = rad(i * 51)
			local r = 0.5 + (i % 3) * 0.25
			local leaf = Kit.part(x.m, x.cf * CF(math.cos(a) * r, 2.4 + (i % 4) * 0.55, math.sin(a) * r) * CFrame.Angles(rad(25 + (i % 3) * 15), a, 0), V3(1.4, 0.06, 1.0), "LeafyGrass", { 40, 110 + i * 6, 60 }, { collide = false, name = "Leaf" })
			leaf.CastShadow = false
		end
		Hit(x, -0.8, 0, -0.8, 0.8, 1.6, 0.8)
	end,
})

item("bookshelf", {
	name = "5단 책장",
	cat = "living",
	price = 130000,
	w = 4,
	d = 1.3,
	h = 6.4,
	wall = true,
	colors = { { 236, 234, 228 }, { 120, 86, 60 }, { 40, 40, 42 } },
	build = function(x: Ctx)
		local c = x.c[1]
		B(x, -2, 0, 0.5, 2, 6.4, 0.65, "Wood", c)
		B(x, -2, 0, -0.65, -1.85, 6.4, 0.65, "Wood", c)
		B(x, 1.85, 0, -0.65, 2, 6.4, 0.65, "Wood", c)
		for i = 0, 5 do
			B(x, -1.85, i * 1.25, -0.65, 1.85, i * 1.25 + 0.12, 0.5, "Wood", c)
		end
		local BOOK = { { 160, 40, 40 }, { 40, 80, 150 }, { 230, 200, 80 }, { 40, 120, 80 }, { 230, 230, 220 }, { 90, 60, 120 } }
		for s = 0, 4 do
			local px = -1.75
			local k = s * 3
			while px < 1.5 do
				k += 1
				local bw = 0.18 + (k % 3) * 0.06
				local bh = 0.8 + (k % 4) * 0.06
				B(x, px, s * 1.25 + 0.12, -0.45, px + bw, s * 1.25 + 0.12 + bh, 0.4, "SmoothPlastic", BOOK[(k % #BOOK) + 1])
				px += bw + 0.02
				if k % 7 == 0 then
					px += 0.5
				end
			end
		end
		Hit(x, -2, 0, -0.65, 2, 6.4, 0.65)
	end,
})

item("aircon", {
	name = "스탠드 에어컨",
	cat = "appliance",
	price = 1290000,
	w = 1.9,
	d = 1.5,
	h = 6,
	wall = true,
	kind = "aircon",
	colors = { { 244, 244, 242 } },
	build = function(x: Ctx)
		B(x, -0.95, 0, -0.75, 0.95, 6, 0.75, "SmoothPlastic", x.c[1])
		B(x, -0.8, 3.6, -0.77, 0.8, 5.5, -0.74, "SmoothPlastic", { 200, 202, 206 }, { name = "Vent" })
		Cyl(x, 0, 4.55, -0.76, 0.02, 1.2, "SmoothPlastic", { 190, 192, 196 })
		local d = B(x, -0.3, 2.9, -0.78, 0.3, 3.2, -0.74, "Neon", { 70, 150, 255 }, { name = "Display" })
		d.Transparency = 0.6
		Hit(x, -0.95, 0, -0.75, 0.95, 6, 0.75)
		Kit.sound(x.m:FindFirstChild("Vent") :: BasePart, "aircon_hum", { volume = 0.25, maxDist = 24, attrs = { Active = false } })
	end,
})

item("fan", {
	name = "스탠드 선풍기",
	cat = "appliance",
	price = 49000,
	w = 1.8,
	d = 1.8,
	h = 4.4,
	kind = "fan",
	colors = { { 240, 240, 240 }, { 120, 190, 230 } },
	build = function(x: Ctx)
		Cyl(x, 0, 0.1, 0, 0.2, 1.6, "SmoothPlastic", x.c[1])
		B(x, -0.1, 0.2, -0.1, 0.1, 3.3, 0.1, "SmoothPlastic", x.c[1])
		B(x, -0.35, 3.1, -0.1, 0.35, 3.7, 0.6, "SmoothPlastic", x.c[1])
		local hub = Kit.rod(x.m, x.cf, V3(0, 3.4, -0.25), V3(0, 3.4, -0.45), 0.4, "SmoothPlastic", x.c[1], { collide = false, name = "Hub" })
		hub:SetAttribute("Rpm", 0)
		hub:SetAttribute("Axis", "X")
		CollectionService:AddTag(hub, "GwB_Spin")
		Kit.rod(x.m, x.cf, V3(0, 3.4, -0.5), V3(0, 3.4, -0.56), 2.2, "Glass", { 220, 230, 240 }, { collide = false, tr = 0.7, name = "Guard" })
		Hit(x, -0.4, 0, -0.4, 0.4, 3.8, 0.4)
	end,
})

-- 침실 ------------------------------------------------------------------------------------------
local function bed(x: Ctx, w: number, d: number)
	local c = x.c[1]
	local hw, hd = w / 2, d / 2
	B(x, -hw, 0, -hd, hw, 1.2, hd, "Wood", c) -- frame
	B(x, -hw + 0.15, 1.2, -hd + 0.15, hw - 0.15, 2.1, hd - 0.4, "Fabric", { 246, 246, 244 }) -- mattress
	B(x, -hw + 0.1, 2.1, -hd + 0.1, hw - 0.1, 2.3, hd * 0.35, "Fabric", x.c[2] or { 214, 222, 232 }) -- duvet
	B(x, -hw, 0, hd - 0.4, hw, 4.2, hd, "Fabric", c:Lerp(Color3.new(1, 1, 1), 0.15)) -- headboard
	local n = if w > 6 then 2 else 1
	for i = 1, n do
		local px = if n == 1 then 0 else (i - 1.5) * (w * 0.45)
		B(x, px - (w / n) * 0.36, 2.1, hd - 2.1, px + (w / n) * 0.36, 2.65, hd - 0.6, "Fabric", { 250, 250, 250 })
	end
	Hit(x, -hw, 0, -hd, hw, 2.1, hd)
	-- lying spot (the server poses the character at this CFrame: on the mattress, head to the headboard)
	-- HumanoidRootPart pose: face up (look = +Y), head toward the headboard (+Z)
	local lie = Kit.anchor(x.m, x.cf * CF(0, 2.85, 0.4) * CFrame.Angles(rad(90), 0, 0), "LieSpot")
	lie:SetAttribute("LieSpot", true)
end

item("bed_single", {
	name = "슈퍼싱글 침대",
	cat = "bedroom",
	price = 320000,
	w = 4.2,
	d = 7,
	h = 4.2,
	wall = true,
	kind = "bed",
	colors = { { 196, 168, 132 }, { 232, 226, 214 }, { 70, 70, 74 } },
	build = function(x: Ctx)
		bed(x, 4.2, 7)
	end,
})

item("bed_queen", {
	name = "퀸 침대",
	cat = "bedroom",
	price = 690000,
	w = 5.6,
	d = 7.2,
	h = 4.2,
	wall = true,
	kind = "bed",
	colors = { { 176, 140, 104 }, { 214, 206, 196 }, { 60, 62, 70 }, { 120, 140, 160 } },
	build = function(x: Ctx)
		bed(x, 5.6, 7.2)
	end,
})

item("bed_king", {
	name = "킹 호텔식 침대",
	cat = "bedroom",
	price = 1290000,
	w = 6.6,
	d = 7.4,
	h = 4.4,
	wall = true,
	kind = "bed",
	colors = { { 90, 70, 56 }, { 230, 224, 214 }, { 40, 40, 44 } },
	build = function(x: Ctx)
		bed(x, 6.6, 7.4)
	end,
})

item("wardrobe", {
	name = "2도어 옷장",
	cat = "bedroom",
	price = 360000,
	w = 4.4,
	d = 2,
	h = 7,
	wall = true,
	kind = "wardrobe",
	colors = { { 240, 238, 232 }, { 176, 140, 104 }, { 90, 92, 96 } },
	build = function(x: Ctx)
		local c = x.c[1]
		B(x, -2.2, 0, -0.9, 2.2, 7, 1, "Wood", c)
		for i, px in { -1.1, 1.1 } do
			local door = B(x, px - 1.08, 0.1, -1, px + 1.08, 6.9, -0.92, "Wood", c:Lerp(Color3.new(1, 1, 1), 0.05), { name = "WardrobeDoor" .. i })
			door:SetAttribute("Hinge", if i == 1 then -1 else 1)
			B(x, px + (if i == 1 then 0.85 else -0.95), 3, -1.1, px + (if i == 1 then 0.95 else -0.85), 4.2, -1, "Metal", { 160, 160, 164 })
		end
		B(x, -2, 5.6, -0.6, 2, 5.7, 0.8, "Metal", { 160, 160, 164 }) -- hanging rail
		local CL = { { 40, 60, 110 }, { 220, 220, 214 }, { 150, 40, 40 }, { 60, 60, 60 }, { 200, 170, 120 } }
		for i = 1, 8 do
			B(x, -1.9 + i * 0.44, 2.8, -0.5, -1.7 + i * 0.44, 5.6, 0.6, "Fabric", CL[(i % #CL) + 1])
		end
		Hit(x, -2.2, 0, -0.9, 2.2, 7, 1)
	end,
})

item("desk", {
	name = "책상 + 의자",
	cat = "bedroom",
	price = 210000,
	w = 4.4,
	d = 4,
	h = 3.6,
	wall = true,
	kind = "seat",
	colors = { { 236, 234, 228 }, { 150, 112, 80 }, { 40, 40, 42 } },
	build = function(x: Ctx)
		local c = x.c[1]
		B(x, -2.2, 2.6, -0.2, 2.2, 2.8, 2, "Wood", c)
		B(x, -2.2, 0, 0, -2.0, 2.6, 2, "Wood", c)
		B(x, 2.0, 0, 0, 2.2, 2.6, 2, "Wood", c)
		B(x, -0.8, 2.8, 1.2, 0.8, 3.0, 1.6, "SmoothPlastic", { 60, 60, 62 }) -- laptop
		B(x, -0.8, 3.0, 1.55, 0.8, 4.0, 1.62, "SmoothPlastic", { 60, 60, 62 })
		local lampHead = B(x, 1.4, 3.9, 1.2, 1.9, 4.1, 1.7, "SmoothPlastic", { 240, 240, 236 }, { name = "DeskLamp" })
		B(x, 1.6, 2.8, 1.4, 1.7, 3.9, 1.5, "Metal", { 160, 160, 164 })
		Lamp(x, lampHead, { kind = "spot", face = "bottom", color = { 255, 236, 200 }, brightness = 1.2, range = 8, on = false })
		-- chair
		B(x, -0.9, 1.6, -1.8, 0.9, 1.9, -0.2, "Fabric", { 60, 64, 72 })
		B(x, -0.9, 1.9, -1.9, 0.9, 3.8, -1.7, "Fabric", { 60, 64, 72 })
		Cyl(x, 0, 0.8, -1, 1.6, 0.25, "Metal", { 40, 40, 42 })
		Cyl(x, 0, 0.08, -1, 0.16, 1.6, "Metal", { 40, 40, 42 })
		Hit(x, -2.2, 0, 0, 2.2, 2.8, 2)
		Seat(x, 0, 1.9, -1.0, 180, 1)
	end,
})

item("pc_desk", {
	name = "게이밍 PC 세트",
	cat = "appliance",
	price = 2490000,
	w = 5,
	d = 4.2,
	h = 4.4,
	wall = true,
	kind = "pc",
	colors = { { 30, 30, 34 }, { 240, 240, 240 } },
	build = function(x: Ctx)
		local c = x.c[1]
		B(x, -2.5, 2.6, -0.1, 2.5, 2.8, 2.1, "SmoothPlastic", c)
		B(x, -2.5, 0, 0, -2.3, 2.6, 2.1, "Metal", c)
		B(x, 2.3, 0, 0, 2.5, 2.6, 2.1, "Metal", c)
		B(x, -0.1, 2.8, 1.5, 0.1, 3.4, 1.7, "Metal", { 40, 40, 42 })
		B(x, -1.7, 3.2, 1.55, 1.7, 5.2, 1.7, "SmoothPlastic", { 20, 20, 22 })
		Screen(x, -1.6, 3.3, 1.54, 1.6, 5.1, 1.56, "pc")
		B(x, -1.1, 2.8, 0.3, 0.9, 2.9, 0.9, "SmoothPlastic", { 30, 30, 32 }) -- keyboard
		local rgb = B(x, -1.1, 2.9, 0.3, 0.9, 2.92, 0.9, "Neon", { 120, 60, 255 }, { name = "RGB" })
		rgb:SetAttribute("Rgb", true)
		B(x, 1.2, 2.8, 0.4, 1.6, 2.9, 0.9, "SmoothPlastic", { 30, 30, 32 }) -- mouse
		B(x, 1.9, 0.1, 0.5, 2.3, 2.4, 2.0, "Glass", { 60, 60, 70 }, { tr = 0.2 }) -- tower
		local fanGlow = B(x, 1.88, 0.8, 0.8, 1.9, 2.0, 1.7, "Neon", { 0, 200, 255 }, { name = "RGB2" })
		fanGlow:SetAttribute("Rgb", true)
		-- gaming chair
		B(x, -0.9, 1.6, -2.0, 0.9, 1.9, -0.3, "Leather", { 30, 30, 32 })
		B(x, -0.9, 1.9, -2.1, 0.9, 4.6, -1.8, "Leather", { 200, 30, 40 })
		Cyl(x, 0, 0.8, -1.1, 1.6, 0.25, "Metal", { 40, 40, 42 })
		Hit(x, -2.5, 0, 0, 2.5, 2.8, 2.1)
		Seat(x, 0, 1.9, -1.1, 180, 1)
		Kit.sound(x.m:FindFirstChild("Screen") :: BasePart, "pc_hum", { volume = 0.2, maxDist = 18, attrs = { Active = false } })
	end,
})

-- 주방 ------------------------------------------------------------------------------------------
item("fridge", {
	name = "양문형 냉장고",
	cat = "kitchen",
	price = 1890000,
	w = 3.2,
	d = 2.6,
	h = 6.4,
	wall = true,
	kind = "fridge",
	colors = { { 220, 222, 226 }, { 40, 40, 44 }, { 230, 214, 200 } },
	build = function(x: Ctx)
		local c = x.c[1]
		B(x, -1.6, 0, -1.1, 1.6, 6.4, 1.3, "Metal", c)
		B(x, -1.6, 0, -1.3, -0.02, 6.4, -1.1, "Metal", c, { name = "FridgeDoorL" }):SetAttribute("Hinge", -1)
		B(x, 0.02, 0, -1.3, 1.6, 6.4, -1.1, "Metal", c, { name = "FridgeDoorR" }):SetAttribute("Hinge", 1)
		B(x, -0.25, 2.6, -1.42, -0.15, 4.6, -1.3, "Metal", { 150, 150, 154 })
		B(x, 0.15, 2.6, -1.42, 0.25, 4.6, -1.3, "Metal", { 150, 150, 154 })
		local inner = B(x, -1.45, 0.3, -1.05, 1.45, 6.1, 1.1, "SmoothPlastic", { 246, 248, 250 }, { name = "Inside" })
		Lamp(x, inner, { color = { 230, 240, 255 }, brightness = 0.8, range = 6 })
		local FOOD = { { 255, 255, 255 }, { 220, 60, 50 }, { 90, 170, 80 }, { 250, 200, 60 }, { 120, 80, 50 } }
		for row = 0, 3 do
			B(x, -1.4, 0.8 + row * 1.3, -1.0, 1.4, 0.85 + row * 1.3, 1.0, "Glass", { 220, 230, 240 }, { tr = 0.4 })
			for k = 0, 3 do
				B(x, -1.2 + k * 0.7, 0.85 + row * 1.3, -0.6, -0.8 + k * 0.7, 1.4 + row * 1.3 - (k % 2) * 0.2, 0.2, "SmoothPlastic", FOOD[((row + k) % #FOOD) + 1])
			end
		end
		Hit(x, -1.6, 0, -1.3, 1.6, 6.4, 1.3)
		Kit.sound(x.m:FindFirstChild("Inside") :: BasePart, "fridge_hum", { volume = 0.18, maxDist = 16 })
	end,
})

item("kimchi_fridge", {
	name = "스탠드 김치냉장고",
	cat = "kitchen",
	price = 1290000,
	w = 2.4,
	d = 2.4,
	h = 5.8,
	wall = true,
	kind = "fridge",
	colors = { { 236, 220, 206 }, { 220, 222, 226 } },
	build = function(x: Ctx)
		local c = x.c[1]
		B(x, -1.2, 0, -1.2, 1.2, 5.8, 1.2, "Metal", c)
		for i = 0, 2 do
			B(x, -1.15, 0.2 + i * 1.9, -1.24, 1.15, 1.95 + i * 1.9, -1.2, "Metal", c:Lerp(Color3.new(0, 0, 0), 0.04))
			B(x, -0.5, 1.6 + i * 1.9, -1.32, 0.5, 1.7 + i * 1.9, -1.24, "Metal", { 160, 160, 164 })
		end
		local inner = B(x, -1.05, 0.3, -1.1, 1.05, 5.5, 1.1, "SmoothPlastic", { 246, 248, 250 }, { name = "Inside", tr = 1 })
		Lamp(x, inner, { color = { 230, 240, 255 }, brightness = 0.5, range = 4 })
		Hit(x, -1.2, 0, -1.2, 1.2, 5.8, 1.2)
		Kit.sound(inner, "fridge_hum", { volume = 0.12, maxDist = 12 })
	end,
})

item("microwave", {
	name = "전자레인지",
	cat = "kitchen",
	price = 129000,
	w = 1.8,
	d = 1.3,
	h = 1.1,
	kind = "microwave",
	colors = { { 236, 236, 236 }, { 40, 40, 44 } },
	build = function(x: Ctx)
		local c = x.c[1]
		B(x, -0.9, 0, -0.65, 0.9, 1.1, 0.65, "SmoothPlastic", c)
		B(x, -0.85, 0.08, -0.68, 0.35, 1.02, -0.64, "Glass", { 30, 30, 30 }, { tr = 0.3, name = "MwDoor" }):SetAttribute("Hinge", -1)
		local inner = B(x, -0.75, 0.15, -0.6, 0.3, 0.95, 0.55, "SmoothPlastic", { 250, 236, 200 }, { name = "Inside" })
		Lamp(x, inner, { color = { 255, 220, 150 }, brightness = 0.6, range = 3 })
		local plate = Cyl(x, -0.22, 0.18, -0.02, 0.04, 0.8, "Glass", { 230, 230, 230 }, { name = "Turntable", tr = 0.3 })
		plate:SetAttribute("Rpm", 0)
		plate:SetAttribute("Axis", "Y")
		CollectionService:AddTag(plate, "GwB_Spin")
		B(x, 0.45, 0.6, -0.68, 0.8, 0.95, -0.64, "Neon", { 40, 255, 120 }, { name = "Clock", tr = 0.4 })
		Kit.sound(inner, "microwave_hum", { volume = 0.35, maxDist = 18, attrs = { Active = false } })
	end,
})

item("dining4", {
	name = "4인 원목 식탁",
	cat = "kitchen",
	price = 380000,
	w = 6,
	d = 6.2,
	h = 3,
	kind = "seat",
	colors = { { 176, 136, 96 }, { 236, 234, 228 }, { 80, 60, 46 } },
	build = function(x: Ctx)
		local c = x.c[1]
		B(x, -2.6, 2.6, -1.6, 2.6, 2.85, 1.6, "Wood", c)
		for _, px in { -2.3, 2.3 } do
			for _, pz in { -1.3, 1.3 } do
				B(x, px - 0.15, 0, pz - 0.15, px + 0.15, 2.6, pz + 0.15, "Wood", c)
			end
		end
		local i = 0
		for _, pz in { -2.5, 2.5 } do
			for _, px in { -1.3, 1.3 } do
				i += 1
				local s = if pz < 0 then -1 else 1
				B(x, px - 0.8, 1.6, pz - 0.8, px + 0.8, 1.8, pz + 0.8, "Wood", c)
				B(x, px - 0.8, 1.8, pz + s * 0.65, px + 0.8, 3.6, pz + s * 0.8, "Wood", c)
				for _, lx in { -0.65, 0.65 } do
					for _, lz in { -0.65, 0.65 } do
						B(x, px + lx - 0.08, 0, pz + lz - 0.08, px + lx + 0.08, 1.6, pz + lz + 0.08, "Wood", c)
					end
				end
				Seat(x, px, 1.85, pz, if s < 0 then 0 else 180, i)
			end
		end
		Hit(x, -2.6, 0, -1.6, 2.6, 2.85, 1.6)
	end,
})

item("rice_cooker", {
	name = "전기밥솥",
	cat = "kitchen",
	price = 289000,
	w = 1.2,
	d = 1.3,
	h = 1.2,
	kind = "cook",
	colors = { { 240, 240, 240 }, { 200, 40, 50 } },
	build = function(x: Ctx)
		Cyl(x, 0, 0.5, 0, 1, 1.15, "SmoothPlastic", x.c[1])
		Cyl(x, 0, 1.05, 0, 0.15, 1.1, "SmoothPlastic", x.c[2] or { 200, 40, 50 })
		B(x, -0.25, 0.5, -0.6, 0.25, 0.8, -0.55, "Neon", { 255, 140, 60 }, { name = "Panel", tr = 0.3 })
	end,
})

item("washer", {
	name = "드럼 세탁기",
	cat = "appliance",
	price = 990000,
	w = 2.4,
	d = 2.4,
	h = 3.4,
	wall = true,
	kind = "washer",
	colors = { { 236, 236, 236 }, { 70, 72, 78 } },
	build = function(x: Ctx)
		local c = x.c[1]
		B(x, -1.2, 0, -1.2, 1.2, 3.4, 1.2, "SmoothPlastic", c)
		Kit.rod(x.m, x.cf, V3(0, 1.5, -1.2), V3(0, 1.5, -1.3), 1.7, "Metal", { 180, 182, 186 }, { collide = false })
		local drum = Kit.rod(x.m, x.cf, V3(0, 1.5, -1.25), V3(0, 1.5, -1.33), 1.3, "Glass", { 40, 60, 80 }, { collide = false, tr = 0.3, name = "Drum" })
		drum:SetAttribute("Rpm", 0)
		drum:SetAttribute("Axis", "X")
		CollectionService:AddTag(drum, "GwB_Spin")
		B(x, -1.0, 2.8, -1.22, 1.0, 3.2, -1.18, "SmoothPlastic", { 30, 30, 34 })
		Hit(x, -1.2, 0, -1.2, 1.2, 3.4, 1.2)
		Kit.sound(drum, "washer", { volume = 0.35, maxDist = 20, attrs = { Active = false } })
	end,
})

item("massage_chair", {
	name = "안마의자",
	cat = "living",
	price = 3290000,
	w = 3,
	d = 5,
	h = 4.6,
	kind = "massage",
	colors = { { 60, 52, 48 }, { 236, 230, 220 } },
	build = function(x: Ctx)
		local c = x.c[1]
		B(x, -1.5, 0.2, -1.5, 1.5, 1.9, 1.8, "Leather", c)
		Kit.ramp(x.m, x.cf, V3(0, 1.9, 0.8), V3(0, 4.6, 2.5), 2.6, { tr = 0, thick = 0.8, collide = false, material = "Leather", color = c, name = "Back" })
		B(x, -1.5, 1.9, -1.5, -1.0, 3.0, 1.8, "Leather", c:Lerp(Color3.new(1, 1, 1), 0.2))
		B(x, 1.0, 1.9, -1.5, 1.5, 3.0, 1.8, "Leather", c:Lerp(Color3.new(1, 1, 1), 0.2))
		Kit.ramp(x.m, x.cf, V3(0, 1.4, -1.5), V3(0, 0.3, -2.5), 1.8, { tr = 0, thick = 0.6, collide = false, material = "Leather", color = c, name = "Leg" })
		Hit(x, -1.5, 0, -1.5, 1.5, 1.9, 1.8)
		Seat(x, 0, 2.1, 0.2, 0, 1)
	end,
})

item("treadmill", {
	name = "러닝머신",
	cat = "appliance",
	price = 890000,
	w = 2.8,
	d = 6,
	h = 4.6,
	kind = "exercise",
	colors = { { 40, 40, 44 } },
	build = function(x: Ctx)
		local c = x.c[1]
		B(x, -1.4, 0, -3, 1.4, 0.6, 3, "Rubber", c, { collide = true })
		B(x, -1.1, 0.6, -2.7, 1.1, 0.65, 2.6, "Rubber", { 30, 30, 32 }, { name = "Belt" })
		B(x, -1.4, 0.6, -3, -1.2, 4.2, -2.6, "Metal", { 120, 120, 124 })
		B(x, 1.2, 0.6, -3, 1.4, 4.2, -2.6, "Metal", { 120, 120, 124 })
		B(x, -1.4, 4.0, -3.1, 1.4, 4.6, -2.5, "SmoothPlastic", { 30, 30, 34 })
		Screen(x, -0.7, 4.1, -2.52, 0.7, 4.5, -2.5, "treadmill")
	end,
})

item("rug", {
	name = "라운드 러그",
	cat = "decor",
	price = 89000,
	w = 7,
	d = 7,
	h = 0.1,
	flat = true,
	colors = { { 214, 206, 192 }, { 90, 100, 120 }, { 180, 120, 100 } },
	build = function(x: Ctx)
		Cyl(x, 0, 0.04, 0, 0.08, 7, "Fabric", x.c[1])
		Cyl(x, 0, 0.05, 0, 0.08, 5.6, "Fabric", x.c[1]:Lerp(Color3.new(1, 1, 1), 0.2))
	end,
})

item("frame_art", {
	name = "광안대교 야경 액자",
	cat = "decor",
	price = 69000,
	w = 3.6,
	d = 0.3,
	h = 2.6,
	wall = true,
	mountY = 3.6,
	colors = { { 30, 30, 30 }, { 200, 170, 110 } },
	build = function(x: Ctx)
		B(x, -1.8, 0, 0, 1.8, 2.6, 0.15, "Wood", x.c[1])
		local art = B(x, -1.6, 0.2, -0.02, 1.6, 2.4, 0.02, "SmoothPlastic", { 20, 30, 60 }, { name = "Art" })
		Kit.text(art, "front", "광안대교", { color = { 120, 200, 255 }, bg = { 14, 20, 46 }, font = Enum.Font.GothamBlack, light = 1 })
	end,
})

item("mood_light", {
	name = "무드등",
	cat = "decor",
	price = 39000,
	w = 0.9,
	d = 0.9,
	h = 1.4,
	kind = "lamp",
	colors = { { 255, 200, 230 }, { 200, 230, 255 }, { 255, 230, 180 } },
	build = function(x: Ctx)
		Cyl(x, 0, 0.1, 0, 0.2, 0.8, "Wood", { 176, 136, 96 })
		local globe = Kit.ball(x.m, x.cf, 0, 0.75, 0, 1.0, "Glass", x.c[1], { collide = false, tr = 0.15, name = "Globe" })
		Lamp(x, globe, { color = x.c[1], brightness = 0.9, range = 10 })
	end,
})

item("aquarium", {
	name = "열대어 어항",
	cat = "decor",
	price = 259000,
	w = 3.4,
	d = 1.6,
	h = 4.6,
	wall = true,
	colors = { { 30, 30, 32 }, { 236, 236, 232 } },
	build = function(x: Ctx)
		B(x, -1.7, 0, -0.8, 1.7, 2.4, 0.8, "Wood", x.c[1])
		local tank = B(x, -1.6, 2.4, -0.7, 1.6, 4.4, 0.7, "Glass", { 90, 170, 210 }, { tr = 0.55, name = "Tank" })
		Kit.light(tank, "point", { color = { 120, 200, 255 }, brightness = 0.6, range = 6, tag = false })
		for i = 1, 5 do
			B(x, -1.2 + i * 0.4, 2.9 + (i % 3) * 0.4, -0.2 + (i % 2) * 0.3, -1.0 + i * 0.4, 3.05 + (i % 3) * 0.4, -0.1 + (i % 2) * 0.3, "Neon", if i % 2 == 0 then { 255, 140, 40 } else { 60, 140, 255 }, { name = "Fish" })
		end
		B(x, -1.6, 2.4, -0.7, 1.6, 2.7, 0.7, "Pebble", { 200, 190, 170 })
		Hit(x, -1.7, 0, -0.8, 1.7, 4.4, 0.8)
		Kit.sound(tank, "bubbles", { volume = 0.15, maxDist = 12 })
	end,
})

item("vanity", {
	name = "화장대",
	cat = "bedroom",
	price = 260000,
	w = 3.6,
	d = 1.8,
	h = 5.6,
	wall = true,
	kind = "seat",
	colors = { { 246, 244, 240 }, { 214, 190, 170 } },
	build = function(x: Ctx)
		local c = x.c[1]
		B(x, -1.8, 0, 0, 1.8, 2.6, 1.8, "Wood", c)
		B(x, -1.2, 2.6, 1.6, 1.2, 5.6, 1.75, "Wood", c)
		B(x, -1.0, 2.8, 1.58, 1.0, 5.4, 1.6, "Glass", { 220, 230, 236 }, { refl = 0.6, name = "Mirror" })
		B(x, -0.7, 1.4, -1.4, 0.7, 1.7, -0.2, "Fabric", { 240, 220, 220 })
		Hit(x, -1.8, 0, 0, 1.8, 2.6, 1.8)
		Seat(x, 0, 1.75, -0.8, 180, 1)
	end,
})

item("shoe_rack", {
	name = "신발장",
	cat = "living",
	price = 150000,
	w = 3.2,
	d = 1.3,
	h = 3.6,
	wall = true,
	colors = { { 236, 234, 228 }, { 120, 92, 70 } },
	build = function(x: Ctx)
		B(x, -1.6, 0, -0.65, 1.6, 3.6, 0.65, "Wood", x.c[1])
		B(x, -0.02, 0.2, -0.68, 0.02, 3.4, -0.65, "SmoothPlastic", { 140, 140, 140 })
		Hit(x, -1.6, 0, -0.65, 1.6, 3.6, 0.65)
	end,
})

item("tv_small", {
	name = "32인치 TV",
	cat = "appliance",
	price = 290000,
	w = 3.4,
	d = 1.2,
	h = 4.2,
	wall = true,
	kind = "tv",
	colors = { { 240, 240, 236 }, { 30, 30, 32 } },
	build = function(x: Ctx)
		B(x, -1.7, 0, -0.6, 1.7, 2.2, 0.6, "Wood", x.c[1])
		B(x, -1.6, 2.4, 0, 1.6, 4.2, 0.2, "SmoothPlastic", { 22, 22, 24 })
		Screen(x, -1.5, 2.5, -0.02, 1.5, 4.1, 0.02, "tv")
		B(x, -0.1, 2.2, 0.0, 0.1, 2.4, 0.2, "Metal", { 40, 40, 42 })
		Hit(x, -1.7, 0, -0.6, 1.7, 2.2, 0.6)
		Kit.sound(x.m:FindFirstChild("Screen") :: BasePart, "tv_talk", { volume = 0.3, maxDist = 24, attrs = { Active = false } })
	end,
})

item("dining2", {
	name = "2인 카페 테이블",
	cat = "kitchen",
	price = 160000,
	w = 3,
	d = 5.4,
	h = 3,
	kind = "seat",
	colors = { { 236, 234, 228 }, { 176, 136, 96 }, { 40, 40, 42 } },
	build = function(x: Ctx)
		local c = x.c[1]
		Cyl(x, 0, 2.7, 0, 0.15, 2.6, "Wood", c)
		B(x, -0.1, 0, -0.1, 0.1, 2.7, 0.1, "Metal", { 40, 40, 42 })
		Cyl(x, 0, 0.05, 0, 0.1, 1.2, "Metal", { 40, 40, 42 })
		for i, pz in { -1.9, 1.9 } do
			local s = if pz < 0 then -1 else 1
			B(x, -0.75, 1.6, pz - 0.7, 0.75, 1.8, pz + 0.7, "Wood", c)
			B(x, -0.75, 1.8, pz + s * 0.6, 0.75, 3.4, pz + s * 0.72, "Wood", c)
			Seat(x, 0, 1.85, pz, if s < 0 then 0 else 180, i)
		end
		Hit(x, -1.3, 0, -1.3, 1.3, 2.8, 1.3)
	end,
})

item("minibar", {
	name = "미니 냉장고",
	cat = "kitchen",
	price = 240000,
	w = 1.8,
	d = 1.8,
	h = 2.8,
	wall = true,
	kind = "fridge",
	colors = { { 30, 30, 32 }, { 236, 236, 236 } },
	build = function(x: Ctx)
		B(x, -0.9, 0, -0.9, 0.9, 2.8, 0.9, "SmoothPlastic", x.c[1], { collide = true })
		B(x, 0.5, 0.6, -0.95, 0.6, 2.2, -0.9, "Metal", { 160, 160, 164 })
		local inner = B(x, -0.75, 0.2, -0.8, 0.75, 2.6, 0.8, "SmoothPlastic", { 246, 248, 250 }, { name = "Inside", tr = 1 })
		Kit.sound(inner, "fridge_hum", { volume = 0.1, maxDist = 10 })
	end,
})

item("kitchen_island", {
	name = "아일랜드 식탁",
	cat = "kitchen",
	price = 980000,
	w = 8,
	d = 3,
	h = 3.1,
	kind = "seat",
	colors = { { 236, 236, 232 }, { 40, 40, 42 } },
	build = function(x: Ctx)
		B(x, -4, 0, -1, 4, 2.9, 1.5, "SmoothPlastic", x.c[2] or { 40, 40, 42 }, { collide = true })
		B(x, -4.1, 2.9, -1.5, 4.1, 3.1, 1.5, "Marble", x.c[1])
		for i = -1, 1 do
			Cyl(x, i * 2.4, 1.0, -2.2, 2.0, 0.2, "Metal", { 40, 40, 42 })
			Cyl(x, i * 2.4, 2.0, -2.2, 0.2, 1.3, "Leather", { 160, 120, 90 })
			Seat(x, i * 2.4, 2.15, -2.2, 0, i + 2)
		end
		local pend = B(x, -0.4, 7.4, -0.4, 0.4, 8.0, 0.4, "Glass", { 255, 230, 190 }, { name = "Pendant", tr = 0.2 })
		Lamp(x, pend, { color = { 255, 214, 160 }, brightness = 1, range = 12, on = true })
	end,
})

item("drying_rack", {
	name = "빨래 건조대",
	cat = "decor",
	price = 39000,
	w = 5,
	d = 2.2,
	h = 3.6,
	colors = { { 236, 236, 236 }, { 150, 200, 230 } },
	build = function(x: Ctx)
		local c = x.c[1]
		for _, px in { -2.4, 2.4 } do
			Kit.rod(x.m, x.cf, V3(px, 0, -1), V3(px, 3.4, 0), 0.12, "Metal", c, { collide = false })
			Kit.rod(x.m, x.cf, V3(px, 0, 1), V3(px, 3.4, 0), 0.12, "Metal", c, { collide = false })
		end
		for k = -2, 2 do
			Kit.rod(x.m, x.cf, V3(-2.4, 3.3, k * 0.3), V3(2.4, 3.3, k * 0.3), 0.06, "Metal", c, { collide = false })
		end
		local CL = { { 240, 240, 236 }, { 60, 90, 150 }, { 230, 120, 120 }, { 90, 90, 94 } }
		for i = 1, 5 do
			B(x, -2.2 + i * 0.75, 1.8, -0.1, -1.6 + i * 0.75, 3.3, 0.1, "Fabric", CL[(i % #CL) + 1])
		end
		Hit(x, -2.5, 0, -1, 2.5, 3.4, 1)
	end,
})

item("jacuzzi", {
	name = "월풀 자쿠지",
	cat = "decor",
	price = 4900000,
	w = 7,
	d = 7,
	h = 2.6,
	kind = "bathtub",
	colors = { { 236, 236, 236 }, { 60, 60, 64 } },
	build = function(x: Ctx)
		local c = x.c[1]
		Cyl(x, 0, 1.2, 0, 2.4, 7, "SmoothPlastic", c, { collide = true })
		local water = Cyl(x, 0, 2.3, 0, 0.3, 6.2, "Glass", { 90, 180, 230 }, { name = "Water", tr = 0.35 })
		water:SetAttribute("Fill", 1)
		Kit.light(water, "point", { color = { 120, 200, 255 }, brightness = 0.8, range = 10, tag = false })
		local head = B(x, -0.2, 2.5, 3.0, 0.2, 2.8, 3.3, "Metal", { 200, 200, 204 }, { name = "Head" })
		CollectionService:AddTag(head, "GwB_Water")
		Kit.sound(water, "bubbles", { volume = 0.3, maxDist = 18 })
		Seat(x, 0, 1.6, 1.2, 180, 1)
		Seat(x, -1.6, 1.6, -0.8, 0, 2)
		Seat(x, 1.6, 1.6, -0.8, 0, 3)
	end,
})

item("sunbed", {
	name = "선베드",
	cat = "decor",
	price = 290000,
	w = 2.6,
	d = 7,
	h = 2.6,
	kind = "bed",
	colors = { { 250, 250, 246 }, { 40, 90, 140 } },
	build = function(x: Ctx)
		local c = x.c[1]
		B(x, -1.3, 0.8, -3.5, 1.3, 1.3, 1.2, "Fabric", c)
		Kit.ramp(x.m, x.cf, V3(0, 1.3, 1.2), V3(0, 2.6, 3.4), 2.6, { tr = 0, thick = 0.5, collide = false, material = "Fabric", color = c, name = "Back" })
		for _, px in { -1.1, 1.1 } do
			for _, pz in { -3.2, 2.8 } do
				B(x, px - 0.1, 0, pz - 0.1, px + 0.1, 0.8, pz + 0.1, "Wood", { 150, 110, 76 })
			end
		end
		Hit(x, -1.3, 0, -3.5, 1.3, 1.3, 3.5)
		local lie = Kit.anchor(x.m, x.cf * CF(0, 2.0, 0.2) * CFrame.Angles(rad(70), 0, 0), "LieSpot")
		lie:SetAttribute("LieSpot", true)
	end,
})

-------------------------------------------------------------------------------------------------
-- built-in fixtures (unit templates, public restrooms): fixed = true
-------------------------------------------------------------------------------------------------
item("kitchen_counter", {
	name = "싱크대 (인덕션 · 후드)",
	cat = "fixture",
	fixed = true,
	price = 0,
	w = 9,
	d = 2.2,
	h = 9,
	wall = true,
	kind = "cook",
	colors = { { 246, 246, 244 }, { 70, 74, 80 } },
	build = function(x: Ctx)
		local c = x.c[1]
		local hw = x.m:GetAttribute("W") or 9
		local w2 = hw / 2
		B(x, -w2, 0, -1.1, w2, 2.8, 1.1, "SmoothPlastic", c, { solid = true, collide = true })
		B(x, -w2, 2.8, -1.15, w2, 3.0, 1.1, "Marble", { 236, 236, 232 }, { name = "Top" })
		B(x, -w2, 0, -1.12, w2, 0.3, -1.05, "SmoothPlastic", { 50, 50, 52 })
		for i = 0, math.floor(hw / 1.5) - 1 do
			local px = -w2 + 0.1 + i * 1.5
			B(x, px, 0.4, -1.14, px + 1.4, 2.7, -1.1, "SmoothPlastic", c:Lerp(Color3.new(0, 0, 0), 0.03))
		end
		-- sink + faucet
		B(x, -w2 + 1, 2.4, -0.8, -w2 + 3, 3.02, 0.6, "Metal", { 190, 192, 196 }, { name = "Sink" })
		B(x, -w2 + 1.9, 3.0, 0.7, -w2 + 2.1, 3.9, 0.9, "Metal", { 200, 200, 204 })
		local spout = B(x, -w2 + 1.9, 3.7, 0.2, -w2 + 2.1, 3.85, 0.9, "Metal", { 200, 200, 204 }, { name = "Spout" })
		CollectionService:AddTag(spout, "GwB_Water")
		-- induction cooktop
		B(x, w2 - 3.4, 3.0, -0.8, w2 - 0.6, 3.05, 0.8, "Glass", { 20, 20, 22 }, { name = "Cooktop", refl = 0.2 })
		for _, ox in { -0.7, 0.7 } do
			Cyl(x, w2 - 2 + ox, 3.06, 0, 0.02, 1.0, "SmoothPlastic", { 70, 70, 74 }, { name = "Burner" })
		end
		-- hood + upper cabinets
		B(x, w2 - 3.4, 6.6, -0.6, w2 - 0.6, 7.4, 1.1, "Metal", { 200, 202, 206 }, { name = "Hood" })
		B(x, -w2, 6.2, 0, w2 - 3.6, 8.6, 1.1, "SmoothPlastic", c)
		B(x, -w2, 3.0, 1.05, w2, 6.2, 1.1, "CeramicTiles", { 236, 236, 232 })
		local strip = B(x, -w2, 6.1, 0.1, w2 - 3.6, 6.2, 0.9, "Neon", { 255, 240, 220 }, { name = "UnderLight", tr = 0.3 })
		Lamp(x, strip, { kind = "surface", face = "bottom", color = { 255, 236, 210 }, brightness = 0.8, range = 6 })
		Kit.sound(x.m:FindFirstChild("Hood") :: BasePart, "vent_fan", { volume = 0.2, maxDist = 14, attrs = { Active = false } })
	end,
})

item("toilet", {
	name = "양변기",
	cat = "fixture",
	fixed = true,
	price = 0,
	w = 1.8,
	d = 3,
	h = 3.2,
	wall = true,
	kind = "toilet",
	colors = { { 250, 250, 250 } },
	build = function(x: Ctx)
		local c = x.c[1]
		B(x, -0.6, 0, -0.6, 0.6, 1.4, 0.8, "SmoothPlastic", c)
		Cyl(x, 0, 1.45, -0.4, 0.15, 1.5, "SmoothPlastic", c)
		B(x, -0.85, 1.4, 0.8, 0.85, 3.2, 1.5, "SmoothPlastic", c, { name = "Tank" })
		B(x, 0.3, 3.2, 1.0, 0.6, 3.25, 1.3, "Metal", { 200, 200, 204 })
		Hit(x, -0.6, 0, -0.9, 0.6, 1.5, 1.5)
		Seat(x, 0, 1.45, -0.1, 0, 1)
	end,
})

item("washbasin", {
	name = "세면대",
	cat = "fixture",
	fixed = true,
	price = 0,
	w = 2.4,
	d = 1.6,
	h = 6,
	wall = true,
	kind = "sink",
	colors = { { 250, 250, 250 } },
	build = function(x: Ctx)
		B(x, -1.2, 2.4, -0.8, 1.2, 2.9, 0.8, "SmoothPlastic", x.c[1], { name = "Basin" })
		B(x, -0.2, 0, 0.2, 0.2, 2.4, 0.6, "SmoothPlastic", x.c[1])
		B(x, -0.08, 2.9, 0.4, 0.08, 3.5, 0.55, "Metal", { 200, 200, 204 })
		local spout = B(x, -0.08, 3.35, 0.0, 0.08, 3.5, 0.55, "Metal", { 200, 200, 204 }, { name = "Spout" })
		CollectionService:AddTag(spout, "GwB_Water")
		B(x, -1.1, 3.8, 0.72, 1.1, 6.0, 0.8, "Glass", { 220, 230, 236 }, { refl = 0.6, name = "Mirror" })
	end,
})

item("shower", {
	name = "샤워부스",
	cat = "fixture",
	fixed = true,
	price = 0,
	w = 3.6,
	d = 3.6,
	h = 7.6,
	kind = "shower",
	colors = { { 236, 238, 240 } },
	build = function(x: Ctx)
		B(x, -1.8, 0, -1.8, 1.8, 0.2, 1.8, "Slate", { 150, 152, 156 })
		B(x, -1.8, 0.2, -1.8, 1.8, 7.4, -1.7, "Glass", { 200, 220, 230 }, { tr = 0.7, collide = false, name = "GlassFront" })
		B(x, -0.1, 1, 1.6, 0.1, 6.8, 1.7, "Metal", { 200, 200, 204 })
		local head = Cyl(x, 0, 6.9, 1.0, 0.1, 1.0, "Metal", { 200, 200, 204 }, { name = "Head" })
		CollectionService:AddTag(head, "GwB_Water")
		Kit.sound(head, "shower", { volume = 0.5, maxDist = 20, attrs = { Active = false } })
	end,
})

item("bathtub", {
	name = "욕조",
	cat = "fixture",
	fixed = true,
	price = 0,
	w = 6,
	d = 3,
	h = 2.2,
	wall = true,
	kind = "bathtub",
	colors = { { 250, 250, 250 } },
	build = function(x: Ctx)
		local c = x.c[1]
		B(x, -3, 0, -1.5, 3, 2.2, -1.2, "SmoothPlastic", c, { collide = true })
		B(x, -3, 0, 1.2, 3, 2.2, 1.5, "SmoothPlastic", c, { collide = true })
		B(x, -3, 0, -1.2, -2.7, 2.2, 1.2, "SmoothPlastic", c, { collide = true })
		B(x, 2.7, 0, -1.2, 3, 2.2, 1.2, "SmoothPlastic", c, { collide = true })
		B(x, -2.7, 0, -1.2, 2.7, 0.4, 1.2, "SmoothPlastic", c)
		local water = B(x, -2.7, 0.4, -1.2, 2.7, 1.6, 1.2, "Glass", { 150, 200, 230 }, { tr = 1, name = "Water" })
		water:SetAttribute("Fill", 0)
		local head = B(x, 2.2, 2.2, 1.1, 2.4, 2.9, 1.3, "Metal", { 200, 200, 204 }, { name = "Head" })
		CollectionService:AddTag(head, "GwB_Water")
		Seat(x, 0, 0.9, 0.2, 90, 1)
	end,
})

item("urinal", {
	name = "소변기",
	cat = "fixture",
	fixed = true,
	price = 0,
	w = 1.6,
	d = 1.4,
	h = 4.2,
	wall = true,
	kind = "toilet",
	colors = { { 250, 250, 250 } },
	build = function(x: Ctx)
		B(x, -0.7, 1.4, -0.4, 0.7, 4.0, 0.7, "SmoothPlastic", x.c[1])
		B(x, -0.5, 1.6, -0.45, 0.5, 3.6, -0.3, "SmoothPlastic", { 230, 232, 234 })
	end,
})

item("hand_dryer", {
	name = "핸드 드라이어",
	cat = "fixture",
	fixed = true,
	price = 0,
	w = 1.2,
	d = 0.8,
	h = 1.4,
	wall = true,
	mountY = 3.6,
	kind = "dryer",
	colors = { { 236, 236, 236 } },
	build = function(x: Ctx)
		B(x, -0.6, 0, -0.3, 0.6, 1.4, 0.4, "SmoothPlastic", x.c[1], { name = "Body" })
		B(x, -0.4, -0.02, -0.25, 0.4, 0.05, 0.2, "SmoothPlastic", { 50, 50, 54 })
		Kit.sound(x.m:FindFirstChild("Body") :: BasePart, "hand_dryer", { volume = 0.45, maxDist = 18, attrs = { Active = false } })
	end,
})

item("wallpad", {
	name = "월패드",
	cat = "fixture",
	fixed = true,
	price = 0,
	w = 1.4,
	d = 0.2,
	h = 1.0,
	wall = true,
	mountY = 4.4,
	kind = "wallpad",
	colors = { { 240, 240, 240 } },
	build = function(x: Ctx)
		B(x, -0.7, 0, 0, 0.7, 1.0, 0.12, "SmoothPlastic", x.c[1])
		local s = Screen(x, -0.55, 0.12, -0.02, 0.55, 0.88, 0.0, "wallpad")
		s.Material = Kit.mat("Neon")
		s.Color = Color3.fromRGB(40, 90, 150)
		s.Transparency = 0.2
	end,
})

item("water_dispenser", {
	name = "온수기",
	cat = "fixture",
	fixed = true,
	price = 0,
	w = 1.4,
	d = 1.4,
	h = 4,
	wall = true,
	kind = "water",
	colors = { { 236, 236, 236 } },
	build = function(x: Ctx)
		B(x, -0.7, 0, -0.7, 0.7, 3.2, 0.7, "SmoothPlastic", x.c[1])
		B(x, -0.5, 3.2, -0.5, 0.5, 4.0, 0.5, "Glass", { 150, 200, 240 }, { tr = 0.4 })
		B(x, -0.35, 1.9, -0.75, -0.15, 2.1, -0.65, "SmoothPlastic", { 220, 40, 40 }, { name = "Hot" })
		B(x, 0.15, 1.9, -0.75, 0.35, 2.1, -0.65, "SmoothPlastic", { 40, 90, 220 })
		Hit(x, -0.7, 0, -0.7, 0.7, 4, 0.7)
	end,
})

item("vending", {
	name = "음료 자판기",
	cat = "fixture",
	fixed = true,
	price = 0,
	w = 3.6,
	d = 2.6,
	h = 6.4,
	wall = true,
	kind = "vending",
	colors = { { 200, 30, 40 }, { 30, 90, 180 } },
	build = function(x: Ctx)
		B(x, -1.8, 0, -1.3, 1.8, 6.4, 1.3, "SmoothPlastic", x.c[1], { collide = true })
		local win = B(x, -1.6, 2.4, -1.32, 0.8, 6.0, -1.28, "Glass", { 230, 236, 240 }, { tr = 0.25, name = "Window" })
		Kit.light(win, "surface", { face = "front", color = { 240, 248, 255 }, brightness = 0.8, range = 8, tag = false })
		local CANS = { { 220, 30, 30 }, { 40, 120, 220 }, { 250, 210, 40 }, { 60, 180, 90 }, { 240, 240, 240 } }
		for row = 0, 3 do
			for k = 0, 5 do
				Cyl(x, -1.35 + k * 0.4, 2.8 + row * 0.85, -1.1, 0.5, 0.28, "SmoothPlastic", CANS[((row + k) % #CANS) + 1])
			end
		end
		B(x, 1.0, 3.6, -1.34, 1.6, 4.2, -1.3, "Neon", { 60, 255, 120 }, { name = "Coin", tr = 0.4 })
		B(x, -1.4, 0.6, -1.34, 0.6, 1.4, -1.3, "SmoothPlastic", { 20, 20, 22 })
		Kit.sound(win, "fridge_hum", { volume = 0.2, maxDist = 16 })
	end,
})

-------------------------------------------------------------------------------------------------
-- build
-------------------------------------------------------------------------------------------------
-- cf: the pivot on the floor (front = -Z). colorway: 1-based index into def.colors (or a Color3 list)
-------------------------------------------------------------------------------------------------
-- 취미 · 방 확장 (Grades.ROOMS sets; also sold one by one in the 취미 tab)
-------------------------------------------------------------------------------------------------
item("gaming_setup", {
	name = "게이밍 PC 책상",
	cat = "hobby",
	price = 1650000,
	w = 5,
	d = 2.6,
	h = 5.2,
	wall = true,
	kind = "pc",
	colors = { { 30, 30, 34 }, { 236, 236, 238 } },
	build = function(x: Ctx)
		local c = x.c[1]
		B(x, -2.5, 2.4, -1.3, 2.5, 2.6, 1.3, "SmoothPlastic", c, { collide = true })
		B(x, -2.4, 0, -1.2, -2.2, 2.4, 1.2, "Metal", c)
		B(x, 2.2, 0, -1.2, 2.4, 2.4, 1.2, "Metal", c)
		Screen(x, -1.6, 3.0, 0.5, 0.4, 4.3, 0.6, "pc")
		Screen(x, 0.6, 3.0, 0.5, 2.2, 4.1, 0.6, "pc")
		B(x, -0.8, 2.6, 0.55, -0.4, 3.0, 0.75, "Metal", { 60, 60, 64 })
		B(x, -1.4, 2.62, -0.6, 0.6, 2.7, -0.1, "SmoothPlastic", { 20, 20, 22 }, { name = "Keyboard" })
		local rgb = B(x, -2.5, 2.38, 1.25, 2.5, 2.44, 1.3, "Neon", { 120, 60, 255 }, { name = "RGB" })
		rgb:SetAttribute("Rgb", true)
		B(x, 1.5, 0, -0.2, 2.2, 2.0, 1.0, "SmoothPlastic", { 24, 24, 28 }, { name = "Tower" })
		-- gaming chair
		B(x, -0.9, 1.6, -2.6, 0.9, 1.9, -1.0, "Leather", { 200, 40, 40 })
		B(x, -0.9, 1.9, -2.7, 0.9, 4.6, -2.4, "Leather", { 30, 30, 34 })
		Hit(x, -2.5, 0, -1.3, 2.5, 2.6, 1.3)
		Seat(x, 0, 1.95, -1.8, 180, 1)
		Kit.sound(x.m:FindFirstChild("Screen") :: BasePart, "pc_hum", { volume = 0.2, maxDist = 18, attrs = { Active = false } })
	end,
})

item("console_set", {
	name = "콘솔 게임 세트 (TV장 + 65인치)",
	cat = "hobby",
	price = 1450000,
	w = 7,
	d = 1.6,
	h = 5.8,
	wall = true,
	kind = "game",
	colors = { { 34, 34, 36 }, { 236, 234, 230 } },
	build = function(x: Ctx)
		local c = x.c[1]
		B(x, -3.5, 0, -0.8, 3.5, 1.4, 0.8, "Wood", c)
		B(x, -3.3, 2.0, 0.1, 3.3, 5.8, 0.4, "SmoothPlastic", { 18, 18, 20 })
		Screen(x, -3.15, 2.15, 0.05, 3.15, 5.65, 0.1, "game")
		B(x, -1.2, 1.4, -0.3, -0.2, 1.75, 0.4, "SmoothPlastic", { 240, 240, 242 }, { name = "Console" })
		B(x, 0.4, 1.4, -0.4, 0.9, 1.55, -0.1, "SmoothPlastic", { 30, 30, 34 }, { name = "Pad" })
		B(x, 1.1, 1.4, -0.4, 1.6, 1.55, -0.1, "SmoothPlastic", { 200, 40, 40 }, { name = "Pad" })
		Hit(x, -3.5, 0, -0.8, 3.5, 1.4, 0.8)
		Kit.sound(x.m:FindFirstChild("Screen") :: BasePart, "tv_talk", { volume = 0.3, maxDist = 26, attrs = { Active = false } })
	end,
})

item("projector_screen", {
	name = "홈시네마 스크린 + 프로젝터",
	cat = "hobby",
	price = 1900000,
	w = 9,
	d = 1,
	h = 7.2,
	wall = true,
	kind = "cinema",
	colors = { { 240, 240, 240 } },
	build = function(x: Ctx)
		B(x, -4.5, 6.8, 0, 4.5, 7.2, 0.5, "Metal", { 40, 40, 44 })
		Screen(x, -4.3, 1.6, 0.2, 4.3, 6.8, 0.3, "cinema")
		B(x, -1.2, 0, -0.4, 1.2, 1.2, 0.4, "Wood", { 30, 30, 32 }) -- speaker bar stand
		B(x, -4.4, 0, -0.3, -3.6, 4, 0.3, "SmoothPlastic", { 24, 24, 26 }, { name = "Speaker" })
		B(x, 3.6, 0, -0.3, 4.4, 4, 0.3, "SmoothPlastic", { 24, 24, 26 }, { name = "Speaker" })
		Hit(x, -4.5, 0, -0.4, 4.5, 1.2, 0.5)
		Kit.sound(x.m:FindFirstChild("Screen") :: BasePart, "tv_talk", { volume = 0.45, maxDist = 30, attrs = { Active = false } })
	end,
})

item("recliner_row", {
	name = "전동 리클라이너 3인",
	cat = "hobby",
	price = 2100000,
	w = 8.4,
	d = 3.4,
	h = 3.4,
	kind = "seat",
	colors = { { 40, 30, 28 }, { 120, 24, 30 } },
	build = function(x: Ctx)
		local c = x.c[1]
		for i = -1, 1 do
			local cx = i * 2.8
			B(x, cx - 1.3, 0.3, -1.7, cx + 1.3, 1.5, 1.7, "Leather", c)
			B(x, cx - 1.3, 1.5, 0.8, cx + 1.3, 3.4, 1.7, "Leather", c)
			B(x, cx - 1.4, 0.3, -1.7, cx - 1.25, 2.2, 1.7, "Leather", c:Lerp(Color3.new(0, 0, 0), 0.2))
			Seat(x, cx, 1.85, -0.3, 0, i + 2)
		end
		B(x, 4.2, 0.3, -1.7, 4.2, 2.2, 1.7, "Leather", c)
		Hit(x, -4.2, 0, -1.7, 4.2, 1.8, 1.7)
	end,
})

item("popcorn_machine", {
	name = "팝콘 기계",
	cat = "hobby",
	price = 250000,
	w = 2,
	d = 2,
	h = 4.4,
	kind = "popcorn",
	colors = { { 200, 30, 30 } },
	build = function(x: Ctx)
		B(x, -1, 0, -1, 1, 2.0, 1, "SmoothPlastic", x.c[1], { collide = true })
		B(x, -0.9, 2.0, -0.9, 0.9, 3.9, 0.9, "Glass", { 250, 240, 200 }, { tr = 0.4, name = "Bowl" })
		B(x, -0.8, 2.0, -0.8, 0.8, 2.8, 0.8, "SmoothPlastic", { 250, 236, 170 }, { name = "Corn" })
		B(x, -1, 3.9, -1, 1, 4.4, 1, "SmoothPlastic", x.c[1])
	end,
})

item("bench_press", {
	name = "벤치프레스 세트",
	cat = "hobby",
	price = 780000,
	w = 3,
	d = 6,
	h = 4.4,
	kind = "lift",
	colors = { { 30, 30, 34 } },
	build = function(x: Ctx)
		B(x, -0.7, 1.2, -2.6, 0.7, 1.6, 1.4, "Leather", { 40, 40, 44 }, { collide = true })
		B(x, -0.2, 0, -2.2, 0.2, 1.2, 1.0, "Metal", { 90, 90, 94 })
		for _, sx in { -1.4, 1.4 } do
			B(x, sx - 0.1, 0, 1.6, sx + 0.1, 4.0, 1.8, "Metal", { 90, 90, 94 })
		end
		Kit.rod(x.m, x.cf, V3(-2.4, 3.6, 1.7), V3(2.4, 3.6, 1.7), 0.18, "Metal", { 180, 180, 186 }, { collide = false })
		for _, sx in { -2.0, 2.0 } do
			Kit.rod(x.m, x.cf, V3(sx - 0.15, 3.6, 1.7), V3(sx + 0.15, 3.6, 1.7), 1.6, "Metal", { 30, 30, 34 }, { collide = false, name = "Plate" })
		end
		Hit(x, -1.5, 0, -2.6, 1.5, 1.6, 1.8)
		Seat(x, 0, 1.8, -0.6, 0, 1)
	end,
})

item("punching_bag", {
	name = "스탠드 샌드백",
	cat = "hobby",
	price = 320000,
	w = 2.6,
	d = 2.6,
	h = 6.6,
	kind = "boxing",
	colors = { { 160, 30, 30 }, { 30, 30, 34 } },
	build = function(x: Ctx)
		Cyl(x, 0, 0.3, 0, 0.6, 2.6, "Rubber", { 30, 30, 34 }, { collide = true })
		Cyl(x, 0, 2.2, 0, 4.4, 1.5, "Leather", x.c[1], { collide = true, name = "Bag" })
		Cyl(x, 0, 0.6, 0, 1.6, 0.3, "Metal", { 90, 90, 94 })
	end,
})

item("dumbbell_rack", {
	name = "덤벨 랙",
	cat = "hobby",
	price = 420000,
	w = 4,
	d = 1.6,
	h = 3,
	wall = true,
	kind = "lift",
	colors = { { 40, 40, 44 } },
	build = function(x: Ctx)
		B(x, -2, 0, -0.8, 2, 0.2, 0.8, "Metal", x.c[1], { collide = true })
		for _, sy in { 1.1, 2.3 } do
			B(x, -2, sy, -0.6, 2, sy + 0.1, 0.6, "Metal", { 90, 90, 94 })
			for i = 0, 4 do
				Kit.rod(x.m, x.cf, V3(-1.6 + i * 0.8, sy + 0.35, -0.3), V3(-1.6 + i * 0.8, sy + 0.35, 0.3), 0.5, "Metal", { 30, 30, 34 }, { collide = false })
			end
		end
		B(x, -2, 0, -0.1, -1.9, 2.8, 0.1, "Metal", x.c[1])
		B(x, 1.9, 0, -0.1, 2, 2.8, 0.1, "Metal", x.c[1])
		Hit(x, -2, 0, -0.8, 2, 2.8, 0.8)
	end,
})

item("workbench", {
	name = "정비 작업대",
	cat = "hobby",
	price = 680000,
	w = 7,
	d = 2.6,
	h = 3.4,
	wall = true,
	kind = "workbench",
	colors = { { 60, 90, 140 }, { 180, 60, 40 } },
	build = function(x: Ctx)
		local c = x.c[1]
		B(x, -3.5, 2.8, -1.3, 3.5, 3.1, 1.3, "Wood", { 150, 110, 70 }, { collide = true })
		B(x, -3.4, 0, -1.2, 3.4, 2.8, 1.2, "Metal", c)
		for i = 0, 3 do
			B(x, -3.3 + i * 1.7, 0.4, -1.25, -1.7 + i * 1.7, 2.6, -1.22, "Metal", c:Lerp(Color3.new(1, 1, 1), 0.15))
		end
		B(x, 1.6, 3.1, -0.4, 3.0, 3.6, 0.6, "Metal", { 200, 30, 30 }, { name = "Vise" })
		Kit.rod(x.m, x.cf, V3(-2.5, 3.2, -0.5), V3(-1.5, 3.2, -0.3), 0.15, "Metal", { 160, 160, 166 }, { collide = false })
		Hit(x, -3.5, 0, -1.3, 3.5, 3.1, 1.3)
	end,
})

item("tool_wall", {
	name = "공구 타공판",
	cat = "hobby",
	price = 190000,
	w = 6,
	d = 0.4,
	h = 6,
	wall = true,
	mountY = 2.5,
	colors = { { 220, 210, 190 } },
	build = function(x: Ctx)
		B(x, -3, 0, 0, 3, 3.5, 0.2, "Wood", x.c[1])
		local TOOLS = { { 200, 30, 30 }, { 40, 40, 44 }, { 230, 180, 40 }, { 60, 120, 200 } }
		for i = 0, 7 do
			local col = TOOLS[(i % #TOOLS) + 1]
			B(x, -2.6 + i * 0.7, 1.0 + (i % 2) * 0.9, -0.1, -2.35 + i * 0.7, 2.4 + (i % 2) * 0.9, 0, "SmoothPlastic", col)
		end
	end,
})

item("parts_shelf", {
	name = "부품 선반",
	cat = "hobby",
	price = 240000,
	w = 5,
	d = 1.6,
	h = 6,
	wall = true,
	colors = { { 90, 90, 94 } },
	build = function(x: Ctx)
		local c = x.c[1]
		for i = 0, 3 do
			B(x, -2.5, i * 1.8, -0.8, 2.5, i * 1.8 + 0.12, 0.8, "Metal", c)
		end
		for _, sx in { -2.45, 2.45 } do
			B(x, sx - 0.05, 0, -0.8, sx + 0.05, 5.6, 0.8, "Metal", c)
		end
		local BOX = { { 186, 146, 96 }, { 200, 40, 40 }, { 40, 40, 44 }, { 60, 120, 200 } }
		for i = 0, 2 do
			for k = 0, 2 do
				B(x, -2.2 + k * 1.5, i * 1.8 + 0.12, -0.6, -1.1 + k * 1.5, i * 1.8 + 1.0, 0.6, "SmoothPlastic", BOX[((i + k) % #BOX) + 1])
			end
		end
		Hit(x, -2.5, 0, -0.8, 2.5, 5.6, 0.8)
	end,
})

item("closet_wall", {
	name = "시스템 드레스룸 행거",
	cat = "hobby",
	price = 1100000,
	w = 9,
	d = 2.2,
	h = 7.4,
	wall = true,
	kind = "wardrobe",
	colors = { { 236, 232, 224 }, { 60, 50, 44 } },
	build = function(x: Ctx)
		local c = x.c[1]
		B(x, -4.5, 0, 0.9, 4.5, 7.4, 1.1, "Wood", c)
		for _, sx in { -4.5, -1.5, 1.5, 4.4 } do
			B(x, sx, 0, -1.1, sx + 0.1, 7.4, 1.1, "Wood", c)
		end
		Kit.rod(x.m, x.cf, V3(-4.4, 5.8, 0), V3(4.4, 5.8, 0), 0.12, "Metal", { 190, 190, 196 }, { collide = false })
		local CLOTH = { { 30, 40, 70 }, { 230, 230, 226 }, { 160, 40, 50 }, { 60, 60, 64 }, { 200, 180, 140 }, { 90, 120, 90 } }
		for i = 0, 13 do
			B(x, -4.2 + i * 0.6, 3.0 + (i % 3) * 0.3, -0.5, -3.85 + i * 0.6, 5.7, 0.5, "Fabric", CLOTH[(i % #CLOTH) + 1])
		end
		B(x, -4.4, 0.2, -1.0, 4.4, 1.6, 0.8, "Wood", c:Lerp(Color3.new(0, 0, 0), 0.1)) -- drawers
		Hit(x, -4.5, 0, -1.1, 4.5, 7.4, 1.1)
	end,
})

item("closet_island", {
	name = "드레스룸 아일랜드장",
	cat = "hobby",
	price = 690000,
	w = 4.6,
	d = 2.6,
	h = 3.2,
	colors = { { 236, 232, 224 }, { 40, 40, 44 } },
	build = function(x: Ctx)
		local c = x.c[1]
		B(x, -2.3, 0, -1.3, 2.3, 3.0, 1.3, "Wood", c, { collide = true })
		B(x, -2.35, 3.0, -1.35, 2.35, 3.2, 1.35, "Glass", { 230, 236, 240 }, { tr = 0.3 })
		for i = 0, 5 do
			B(x, -2.0 + i * 0.7, 3.05, -0.3, -1.6 + i * 0.7, 3.15, 0.3, "Metal", { 220, 190, 120 }) -- watches
		end
	end,
})

item("full_mirror", {
	name = "LED 전신거울",
	cat = "hobby",
	price = 290000,
	w = 2.6,
	d = 0.6,
	h = 6.6,
	wall = true,
	kind = "dress",
	colors = { { 230, 230, 232 } },
	build = function(x: Ctx)
		B(x, -1.3, 0, 0.1, 1.3, 6.6, 0.3, "Metal", x.c[1])
		B(x, -1.15, 0.15, 0.05, 1.15, 6.45, 0.1, "Glass", { 220, 230, 240 }, { refl = 0.6, name = "Mirror" })
		local led = B(x, -1.3, 6.5, 0.05, 1.3, 6.6, 0.3, "Neon", { 255, 250, 240 })
		Lamp(x, led, { color = { 255, 246, 230 }, brightness = 0.6, range = 8, on = true })
	end,
})

item("bar_counter", {
	name = "홈바 카운터",
	cat = "hobby",
	price = 1600000,
	w = 7,
	d = 2.4,
	h = 3.8,
	kind = "bar",
	colors = { { 50, 36, 30 }, { 20, 20, 22 } },
	build = function(x: Ctx)
		local c = x.c[1]
		B(x, -3.5, 0, -0.9, 3.5, 3.5, 0.9, "Wood", c, { collide = true })
		B(x, -3.7, 3.5, -1.2, 3.7, 3.8, 1.2, "Marble", { 236, 232, 226 })
		local strip = B(x, -3.5, 0.2, -0.95, 3.5, 0.3, -0.9, "Neon", { 255, 170, 60 })
		Lamp(x, strip, { color = { 255, 180, 90 }, brightness = 0.6, range = 9, on = true })
		for i = 0, 3 do
			Cyl(x, -2.5 + i * 1.6, 3.8, -0.2, 0.9, 0.35, "Glass", { 200, 230, 240 }, { tr = 0.4 }) -- glasses
		end
		Hit(x, -3.5, 0, -1.2, 3.5, 3.8, 1.2)
	end,
})

item("bar_stool", {
	name = "바 스툴",
	cat = "hobby",
	price = 120000,
	w = 1.8,
	d = 1.8,
	h = 3.2,
	kind = "seat",
	colors = { { 40, 40, 44 }, { 160, 110, 70 } },
	build = function(x: Ctx)
		Cyl(x, 0, 0.05, 0, 0.1, 1.6, "Metal", { 40, 40, 44 })
		Cyl(x, 0, 1.5, 0, 2.8, 0.25, "Metal", { 160, 160, 166 })
		Cyl(x, 0, 2.95, 0, 0.3, 1.6, "Leather", x.c[1], { collide = true })
		Seat(x, 0, 3.0, 0, 0, 1)
	end,
})

item("liquor_shelf", {
	name = "술장 (백바)",
	cat = "hobby",
	price = 980000,
	w = 7,
	d = 1.4,
	h = 7.6,
	wall = true,
	colors = { { 40, 30, 26 } },
	build = function(x: Ctx)
		local c = x.c[1]
		B(x, -3.5, 0, 0.5, 3.5, 7.6, 0.7, "Wood", c)
		local BOTTLE = { { 120, 60, 20 }, { 40, 90, 50 }, { 220, 200, 160 }, { 150, 30, 40 }, { 200, 220, 230 } }
		for i = 0, 3 do
			local y = 1.2 + i * 1.6
			B(x, -3.4, y, -0.7, 3.4, y + 0.1, 0.5, "Glass", { 230, 236, 240 }, { tr = 0.3 })
			for k = 0, 9 do
				Cyl(x, -3.0 + k * 0.66, y + 0.65, -0.1, 1.1, 0.35, "Glass", BOTTLE[((i + k) % #BOTTLE) + 1], { tr = 0.15 })
			end
		end
		local glow = B(x, -3.4, 7.3, -0.6, 3.4, 7.4, 0.5, "Neon", { 255, 190, 110 })
		Lamp(x, glow, { color = { 255, 190, 110 }, brightness = 0.5, range = 8, on = true })
		Hit(x, -3.5, 0, -0.7, 3.5, 7.6, 0.7)
	end,
})

item("piano", {
	name = "업라이트 피아노",
	cat = "hobby",
	price = 3200000,
	w = 5,
	d = 2.2,
	h = 4.4,
	wall = true,
	kind = "instrument",
	colors = { { 18, 18, 20 }, { 236, 232, 224 } },
	build = function(x: Ctx)
		local c = x.c[1]
		B(x, -2.5, 0, -0.2, 2.5, 4.4, 1.1, "SmoothPlastic", c, { collide = true, refl = 0.2 })
		B(x, -2.5, 2.2, -1.1, 2.5, 2.5, -0.2, "SmoothPlastic", c)
		B(x, -2.3, 2.5, -1.05, 2.3, 2.6, -0.4, "SmoothPlastic", { 245, 245, 240 }, { name = "Keys" })
		for i = 0, 15 do
			B(x, -2.2 + i * 0.29, 2.6, -0.8, -2.08 + i * 0.29, 2.68, -0.4, "SmoothPlastic", { 20, 20, 22 })
		end
		B(x, -1.4, 0, -2.2, 1.4, 1.6, -1.5, "SmoothPlastic", c) -- bench
		Hit(x, -2.5, 0, -1.1, 2.5, 4.4, 1.1)
		Seat(x, 0, 1.75, -1.85, 0, 1)
	end,
})

item("drum_kit", {
	name = "드럼 세트",
	cat = "hobby",
	price = 1700000,
	w = 5,
	d = 4.4,
	h = 4.6,
	kind = "instrument",
	colors = { { 160, 20, 30 }, { 30, 60, 140 } },
	build = function(x: Ctx)
		local c = x.c[1]
		Kit.rod(x.m, x.cf, V3(0, 1.2, -0.3), V3(0, 1.2, 0.9), 2.2, "SmoothPlastic", c, { collide = false, name = "Kick" })
		for _, d in { { -1.5, 2.2, -0.6, 1.2 }, { 1.4, 2.2, -0.7, 1.3 }, { -0.6, 2.9, 0.2, 0.9 }, { 0.6, 2.9, 0.2, 0.9 } } do
			Cyl(x, d[1], d[2], d[3], 0.8, d[4], "SmoothPlastic", c)
		end
		for _, cy in { { -2.0, 4.2, 0.4 }, { 2.0, 4.4, 0.6 } } do
			Cyl(x, cy[1], cy[2], cy[3], 0.05, 1.8, "Metal", { 220, 190, 90 }, { name = "Cymbal" })
			Cyl(x, cy[1], cy[2] / 2, cy[3], cy[2], 0.12, "Metal", { 160, 160, 166 })
		end
		Cyl(x, 0, 0.9, -1.6, 1.8, 1.2, "Leather", { 30, 30, 34 }, { collide = true })
		Hit(x, -2.2, 0, -0.9, 2.2, 2.6, 1.5)
		Seat(x, 0, 1.95, -1.6, 0, 1)
	end,
})

item("guitar_stand", {
	name = "기타 + 스탠드",
	cat = "hobby",
	price = 560000,
	w = 1.6,
	d = 1.6,
	h = 4,
	kind = "instrument",
	colors = { { 180, 110, 50 }, { 20, 20, 22 } },
	build = function(x: Ctx)
		local c = x.c[1]
		B(x, -0.6, 0, -0.2, 0.6, 0.2, 0.2, "Metal", { 40, 40, 44 })
		Cyl(x, 0, 1.2, 0, 0.35, 1.5, "Wood", c)
		Cyl(x, 0, 1.9, 0, 0.35, 1.2, "Wood", c)
		B(x, -0.1, 2.3, -0.1, 0.1, 3.9, 0.1, "Wood", { 60, 40, 30 })
	end,
})

item("office_desk", {
	name = "듀얼 모니터 업무 책상",
	cat = "hobby",
	price = 880000,
	w = 6,
	d = 2.8,
	h = 5,
	wall = true,
	kind = "office",
	colors = { { 236, 234, 228 }, { 90, 64, 46 } },
	build = function(x: Ctx)
		local c = x.c[1]
		B(x, -3, 2.4, -1.4, 3, 2.6, 1.4, "Wood", c, { collide = true })
		B(x, -2.9, 0, -1.3, -2.7, 2.4, 1.3, "Metal", { 60, 60, 64 })
		B(x, 2.7, 0, -1.3, 2.9, 2.4, 1.3, "Metal", { 60, 60, 64 })
		Screen(x, -2.2, 3.0, 0.6, -0.2, 4.3, 0.7, "office")
		Screen(x, 0.2, 3.0, 0.6, 2.2, 4.3, 0.7, "office")
		B(x, -1.0, 2.62, -0.6, 1.0, 2.7, -0.1, "SmoothPlastic", { 230, 230, 232 }, { name = "Keyboard" })
		B(x, -0.9, 1.6, -2.7, 0.9, 1.9, -1.2, "Fabric", { 40, 40, 44 })
		B(x, -0.9, 1.9, -2.8, 0.9, 4.4, -2.55, "Fabric", { 40, 40, 44 })
		Hit(x, -3, 0, -1.4, 3, 2.6, 1.4)
		Seat(x, 0, 1.95, -1.95, 180, 1)
	end,
})

function Furniture.build(itemId: string, parent: Instance?, cf: CFrame, colorway: number?, extra: { [string]: any }?): Model?
	local def = ITEMS[itemId]
	if not def then
		warn("[GwangalliBuildings] unknown furniture " .. tostring(itemId))
		return nil
	end
	local m = Instance.new("Model")
	m.Name = itemId
	local idx = math.clamp(math.floor(colorway or 1), 1, #def.colors)
	local colors = {}
	for i = idx, #def.colors do
		table.insert(colors, Kit.col(def.colors[i]))
	end
	for i = 1, idx - 1 do
		table.insert(colors, Kit.col(def.colors[i]))
	end
	local mountY = def.mountY or 0
	local base = Kit.part(m, cf * CF(0, mountY + def.h / 2, 0), V3(def.w, math.max(def.h, 0.2), def.d), "SmoothPlastic", { 255, 255, 255 }, {
		tr = 1,
		collide = false,
		name = "Base",
		shadow = false,
	})
	m.PrimaryPart = base
	if extra then
		Kit.attrs(m, extra)
	end
	local x = { m = m, cf = cf * CF(0, mountY, 0), c = colors }
	def.build(x)
	m:SetAttribute("ItemId", itemId)
	m:SetAttribute("Colorway", idx)
	m:SetAttribute("Label", def.name)
	if def.kind then
		m:SetAttribute("Kind", def.kind)
		CollectionService:AddTag(m, "GwB_Fixture")
	end
	m.Parent = parent
	return m
end

-- footprint of an item rotated by yaw (degrees, multiples of 45 use the bounding box)
function Furniture.footprint(itemId: string, yaw: number?): (number, number)
	local def = ITEMS[itemId]
	if not def then
		return 1, 1
	end
	local a = math.rad(yaw or 0)
	local c, s = math.abs(math.cos(a)), math.abs(math.sin(a))
	return def.w * c + def.d * s, def.w * s + def.d * c
end

function Furniture.shopList(): { any }
	local out = {}
	for _, id in Furniture.ORDER do
		local d = ITEMS[id]
		if not d.fixed then
			table.insert(out, { id = id, name = d.name, cat = d.cat, price = d.price, w = d.w, d = d.d, h = d.h, colors = #d.colors, kind = d.kind })
		end
	end
	return out
end

return Furniture

end)()
return { Kit = __Kit, Furniture = __Furniture, R = R }