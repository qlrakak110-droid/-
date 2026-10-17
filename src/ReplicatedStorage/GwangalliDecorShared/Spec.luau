--!strict
-- GwangalliDecorShared/Spec: turns a catalog spec (Kit format) into a Model. Used for the server's placed
-- pieces, the client's ghost and the ViewportFrame thumbnails, so every view has the same geometry.
--   Spec.build(spec, pivot, parent?, name, opts?) -> (Model, extra)
--     opts = { ghost, maxLights (default all), on (lamp state, default true), open (pose), seats (bool),
--              hit (adds the DPHit selection box; needs id), id, thumb (no lights, no seats) }
--     extra = { lights, glow, screens, seats, pose = { {part, closed, open, size, openSize} }, speaker,
--               fire, tank, hit }
--   Spec.setLamp(extra, on) / Spec.setPose(extra, pivot, open, tween?)

local Palette = require(script.Parent:WaitForChild("Palette"))
local Catalog = require(script.Parent:WaitForChild("Catalog"))

local Spec = {}

local SHAPE = { Block = Enum.PartType.Block, Cylinder = Enum.PartType.Cylinder, Ball = Enum.PartType.Ball }
local RESERVED = { Screen = true, TVScreen = true, DPHit = true }

local function color3(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

function Spec.build(spec: any, pivot: CFrame, parent: Instance?, name: string, opts: any?): (Model, any)
	local o = opts or {}
	local model = Instance.new("Model")
	model.Name = name
	local extra: any = { lights = {}, glow = {}, screens = {}, seats = {}, pose = {}, parts = {} }
	local ghost = o.ghost == true
	local on = o.on ~= false
	local maxLights = if ghost or o.thumb then 0 else (o.maxLights or math.huge)
	local partsByIndex: { [number]: BasePart } = {}
	for i, p in spec.parts do
		local part = Instance.new("Part")
		local nm = p.n or "Part"
		if p.screen then
			nm = "Screen"
		elseif RESERVED[nm] then
			nm = nm .. "Panel"
		end
		part.Name = nm
		part.Shape = SHAPE[p.shape] or Enum.PartType.Block
		part.Size = p.size
		local local_ = if o.open and p.open then p.open else p.cf
		part.CFrame = pivot * local_
		if o.open and p.openSize then
			part.Size = p.openSize
		end
		part.Color = color3(p.rgb)
		local mat = Palette.enumOf(p.mat)
		if mat then
			part.Material = mat
		end
		part.Transparency = if ghost then math.max(p.t or 0, 0.42) else (p.t or 0)
		part.Reflectance = p.rf or 0
		part.Anchored = true
		part.CanTouch = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		if ghost or o.thumb then
			part.CanCollide = false
			part.CanQuery = false
			part.CastShadow = false
		else
			part.CanCollide = p.solid == true
			part.CanQuery = p.solid == true
			part.CastShadow = p.cast == true
		end
		if p.glow then
			table.insert(extra.glow, { part = part, rgb = p.rgb })
			if not on and not ghost then
				part.Material = Enum.Material.SmoothPlastic
				part.Color = color3(Palette.shade(p.rgb, 0.55))
			end
		end
		if p.screen then
			table.insert(extra.screens, part)
		end
		if p.open then
			table.insert(extra.pose, { part = part, closed = p.cf, open = p.open, size = p.size, openSize = p.openSize })
		end
		part.Parent = model
		partsByIndex[i] = part
		table.insert(extra.parts, part)
	end
	-- lights
	local nl = 0
	for _, l in spec.lights do
		if nl >= maxLights then
			break
		end
		local host = partsByIndex[l.p]
		if host then
			local light: Light
			if l.spot then
				local s = Instance.new("SpotLight")
				s.Angle = l.angle or 70
				local okFace, face = pcall(function()
					return (Enum.NormalId :: any)[l.face or "Bottom"]
				end)
				s.Face = if okFace and face then face else Enum.NormalId.Bottom
				light = s
			else
				light = Instance.new("PointLight")
			end
			light.Range = l.range
			light.Brightness = l.bright
			light.Color = color3(l.rgb or spec.parts[l.p].rgb)
			light.Shadows = false
			light.Enabled = on
			light.Parent = host
			table.insert(extra.lights, light)
			nl += 1
		end
	end
	extra.lightCount = nl
	-- seats
	if o.seats and not ghost and not o.thumb then
		for i, s in spec.seats do
			local seat = Instance.new("Seat")
			seat.Name = if s.lie then "DPBed" else "DPSeat"
			seat.Size = Vector3.new(1.6, 0.2, 1.6)
			local cf = pivot * s.cf * CFrame.new(0, -0.1, 0)
			if s.lie then
				cf *= CFrame.Angles(math.rad(90), 0, 0)
			end
			seat.CFrame = cf
			seat.Transparency = 1
			seat.Anchored = true
			seat.CanCollide = false
			seat.CanTouch = false
			seat.CanQuery = false
			seat.CastShadow = false
			seat:SetAttribute("SeatIndex", i)
			seat.Parent = model
			table.insert(extra.seats, seat)
		end
	end
	-- interaction anchors
	if spec.speaker then
		extra.speaker = partsByIndex[spec.speaker]
	end
	if spec.fire and not ghost and not o.thumb then
		local fb = Instance.new("Part")
		fb.Name = "DPFire"
		fb.Size = spec.fire.size
		fb.CFrame = pivot * spec.fire.cf
		fb.Transparency = 1
		fb.Anchored = true
		fb.CanCollide = false
		fb.CanQuery = false
		fb.CanTouch = false
		fb.CastShadow = false
		local fire = Instance.new("Fire")
		fire.Size = math.clamp(math.max(spec.fire.size.X, spec.fire.size.Z) * 1.6, 2, 8)
		fire.Heat = 4
		fire.Color = Color3.fromRGB(255, 140, 50)
		fire.SecondaryColor = Color3.fromRGB(255, 60, 20)
		fire.Enabled = on
		fire.Parent = fb
		fb.Parent = model
		extra.fire = fire
		extra.fireBox = fb
	end
	if spec.tank then
		extra.tank = spec.tank
	end
	if o.hit and o.id then
		local cf, half = Catalog.box(o.id)
		local hit = Instance.new("Part")
		hit.Name = "DPHit"
		hit.Size = half * 2 + Vector3.new(0.04, 0.04, 0.04)
		hit.CFrame = pivot * cf
		hit.Transparency = 1
		hit.Anchored = true
		hit.CanCollide = false
		hit.CanTouch = false
		hit.CanQuery = true
		hit.CastShadow = false
		hit.Parent = model
		model.PrimaryPart = hit
		extra.hit = hit
	end
	if parent then
		model.Parent = parent
	end
	return model, extra
end

-- lamp on / off: real lights, glowing parts (Neon <-> dim plastic), fire
function Spec.setLamp(extra: any, on: boolean, budgeted: boolean?)
	for _, l in extra.lights do
		l.Enabled = on and budgeted ~= false
	end
	for _, g in extra.glow do
		local p: BasePart = g.part
		if on then
			p.Material = Enum.Material.Neon
			p.Color = color3(g.rgb)
		else
			p.Material = Enum.Material.SmoothPlastic
			p.Color = color3(Palette.shade(g.rgb, 0.55))
		end
	end
	if extra.fire then
		extra.fire.Enabled = on
	end
end

-- open / close pose (fridge doors, curtains, recliner ...). pivot = the piece's world pivot.
function Spec.setPose(extra: any, pivot: CFrame, open: boolean, tween: boolean?)
	local TweenService = if tween then game:GetService("TweenService") else nil
	for _, e in extra.pose do
		local cf = pivot * (if open then e.open else e.closed)
		local size = if open and e.openSize then e.openSize else e.size
		if TweenService then
			local ok = pcall(function()
				TweenService:Create(e.part, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = cf, Size = size }):Play()
			end)
			if not ok then
				e.part.CFrame = cf
				e.part.Size = size
			end
		else
			e.part.CFrame = cf
			e.part.Size = size
		end
	end
end

-- recolours a placed model's light-coloured parts (빛 색 바꾸기)
function Spec.setLightColor(extra: any, rgb: { number })
	for _, l in extra.lights do
		l.Color = color3(rgb)
	end
	for _, g in extra.glow do
		g.rgb = rgb
		if g.part.Material == Enum.Material.Neon then
			g.part.Color = color3(rgb)
		end
	end
end

return Spec
