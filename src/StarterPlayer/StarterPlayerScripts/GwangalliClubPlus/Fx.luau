-- GwangalliClubPlus.Fx: the show's world effects (client, local parts in Workspace.GwangalliClubPlusLocal).
-- Layered over ClubLights (never touches its CO2 / confetti / sparkler / mirror-ball instances): our own
-- emitters sit at the same nozzles / cannons so a cue looks like the room's machines firing.
--   one-shots   co2 · confetti (cannons) · tableConfetti · fountain (cold sparks) · fireworks · burst
--               strobe (LED-wall top bars + lights) · flash (screen) · ripple / floorFlash (LED floor)
--               mirror (mirror-ball rays) · hazeBoost
--   ambient     haze volume · LED dance-floor overlay (beat patterns, very light so ClubLights' tiles
--               still read) · DJ booth glow (beat pulse; magenta + ON AIR while a guest DJ plays)
--   followers   sparkle trail + optional SpotLight that the Director moves over a rig (staff / 합석 guests)
-- Built the first time the player is in a show room of the club, torn down 30 s after leaving.
-- Budgets from Config.Quality (GwangalliQuality tier, saver); reduced motion -> no strobe flicker / flashes.

local Fx = {}

local Core: any
local S: any

local built = false
local outsideSince = 0
local rig: any = {}
local NSK = NumberSequenceKeypoint.new
local CSK = ColorSequenceKeypoint.new

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 194, 71)
local MAGENTA = Color3.fromRGB(255, 60, 190)
local CYAN = Color3.fromRGB(40, 220, 255)
local VIOLET = Color3.fromRGB(150, 60, 255)

local function set(inst: Instance, props: { [string]: any })
	for k, v in props do
		pcall(function()
			(inst :: any)[k] = v
		end)
	end
end

-- an attachment whose +Y axis points along `dir` (ParticleEmitters emit along it)
local function aimed(parent: BasePart, world: Vector3, dir: Vector3): Attachment
	local a = Instance.new("Attachment")
	local up = if dir.Magnitude > 1e-3 then dir.Unit else Vector3.yAxis
	local ref = if math.abs(up.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis
	local right = ref:Cross(up).Unit
	local world_cf = CFrame.fromMatrix(world, right, up)
	a.CFrame = parent.CFrame:ToObjectSpace(world_cf)
	a.Parent = parent
	return a
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local pe = Instance.new("ParticleEmitter")
	pe.Rate = 0
	pe.Enabled = true
	pe.LockedToPart = false
	set(pe, props)
	pe.Parent = parent
	return pe
end

local function q(): any
	return Core.q()
end

local function holder(name: string, pos: Vector3): Part
	local p = Core.part(name, Vector3.new(0.4, 0.4, 0.4), CFrame.new(pos))
	p.Transparency = 1
	return p
end

-------------------------------------------------------------------------------------------------
-- build
-------------------------------------------------------------------------------------------------
local function buildCO2()
	rig.co2 = {}
	local fb = S.Config.Fallback
	for i, pos in Core.spots("CO2Nozzle", fb.CO2, Vector3.new(0, 0.45, 0)) do
		if i > 6 then
			break
		end
		local h = holder("PlusCO2", pos)
		local a = aimed(h, pos, Vector3.yAxis)
		local pe = emitter(a, {
			Texture = SMOKE,
			Color = ColorSequence.new(Color3.fromRGB(236, 242, 255)),
			LightEmission = 0.35,
			LightInfluence = 0.6,
			Size = NumberSequence.new({ NSK(0, 0.7), NSK(0.25, 3.2), NSK(1, 6.8) }),
			Transparency = NumberSequence.new({ NSK(0, 0.2), NSK(0.55, 0.55), NSK(1, 1) }),
			Lifetime = NumberRange.new(1.0, 1.7),
			Speed = NumberRange.new(36, 50),
			SpreadAngle = Vector2.new(6, 6),
			Acceleration = Vector3.new(0, -4, 0),
			Drag = 2.3,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-70, 70),
			EmissionDirection = Enum.NormalId.Top,
		})
		table.insert(rig.co2, pe)
	end
end

local CONF_COLS = {
	{ GOLD, Color3.fromRGB(255, 236, 160) },
	{ MAGENTA, Color3.fromRGB(255, 150, 220) },
	{ CYAN, WHITE },
}
local function confettiEmitter(parent: Instance, col: { Color3 }, small: boolean): ParticleEmitter
	return emitter(parent, {
		Color = ColorSequence.new({ CSK(0, col[1]), CSK(1, col[2]) }),
		LightEmission = 0.45,
		LightInfluence = 0.3,
		Size = NumberSequence.new(if small then 0.16 else 0.26, if small then 0.2 else 0.32),
		Transparency = NumberSequence.new({ NSK(0, 0), NSK(0.85, 0.05), NSK(1, 1) }),
		Lifetime = if small then NumberRange.new(2.6, 3.6) else NumberRange.new(5.5, 7.5),
		Speed = if small then NumberRange.new(13, 21) else NumberRange.new(26, 38),
		SpreadAngle = if small then Vector2.new(32, 32) else Vector2.new(38, 38),
		Acceleration = Vector3.new(0, if small then -16 else -5.5, 0),
		Drag = if small then 1.1 else 1.5,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-320, 320),
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		EmissionDirection = Enum.NormalId.Top,
	})
end

local function buildConfetti()
	rig.conf = {}
	local cf = Core.roomBox()
	for i, pos in Core.spots("ConfettiCannon", S.Config.Fallback.Confetti) do
		if i > 4 then
			break
		end
		local toRoom = Vector3.new(cf.Position.X - pos.X, 0, cf.Position.Z - pos.Z)
		if toRoom.Magnitude < 1 then
			toRoom = Vector3.new(-1, 0, 0)
		end
		local dir = (toRoom.Unit + Vector3.new(0, 0.35, 0)).Unit
		local h = holder("PlusConfetti", pos)
		local a = aimed(h, pos, dir)
		for _, col in CONF_COLS do
			table.insert(rig.conf, confettiEmitter(a, col, false))
		end
	end
	-- one movable small cannon for table bursts (짠 / arrivals)
	local th = holder("PlusTableConfetti", cf.Position)
	local ta = aimed(th, cf.Position, Vector3.yAxis)
	rig.tableConf = { part = th, list = {} }
	for _, col in CONF_COLS do
		table.insert(rig.tableConf.list, confettiEmitter(ta, col, true))
	end
	rig.tableConf.att = ta
end

local function sparkEmitter(parent: Instance, col: Color3, burst: boolean): ParticleEmitter
	return emitter(parent, {
		Texture = SPARK,
		Color = ColorSequence.new({ CSK(0, WHITE), CSK(0.25, col), CSK(1, col) }),
		LightEmission = 1,
		LightInfluence = 0,
		Size = NumberSequence.new({ NSK(0, if burst then 0.55 else 0.4), NSK(1, 0) }),
		Transparency = NumberSequence.new({ NSK(0, 0), NSK(0.8, 0.2), NSK(1, 1) }),
		Lifetime = if burst then NumberRange.new(1.1, 1.8) else NumberRange.new(0.8, 1.4),
		Speed = if burst then NumberRange.new(10, 17) else NumberRange.new(17, 26),
		SpreadAngle = if burst then Vector2.new(180, 180) else Vector2.new(11, 11),
		Acceleration = Vector3.new(0, if burst then -7 else -26, 0),
		Drag = if burst then 1.8 else 0.4,
		EmissionDirection = Enum.NormalId.Top,
	})
end

local function buildSparks()
	rig.fount = {}
	for i, pos in Core.spots("SparkNozzle", S.Config.Fallback.Sparks, Vector3.new(0, 0.2, 0)) do
		if i > 4 then
			break
		end
		local h = holder("PlusSpark", pos)
		table.insert(rig.fount, sparkEmitter(aimed(h, pos, Vector3.yAxis), GOLD, false))
	end
	local cf = Core.roomBox()
	local bh = holder("PlusBurst", cf.Position)
	local ba = aimed(bh, cf.Position, Vector3.yAxis)
	rig.burst = { part = bh, att = ba, pe = sparkEmitter(ba, GOLD, true) }
end

local function buildStrobes()
	rig.strobes = {}
	local n = q().strobes
	if n <= 0 then
		return
	end
	local cf, size = Core.ledFrame()
	local topY = size.Y * 0.5 + 0.7
	for i = 1, n do
		local x = (i - (n + 1) / 2) * (size.X / (n + 0.5))
		local pcf = cf * CFrame.new(x, topY, -0.6)
		local p = Core.part("PlusStrobe", Vector3.new(2.6, 0.32, 0.32), pcf, WHITE, Enum.Material.Neon)
		p.Transparency = 1
		local l = Instance.new("PointLight")
		l.Range = 42
		l.Brightness = 0
		l.Color = Color3.fromRGB(235, 240, 255)
		l.Shadows = false
		l.Parent = p
		table.insert(rig.strobes, { part = p, light = l })
	end
end

local function buildHaze()
	if not q().haze then
		return
	end
	local cf, size = Core.roomBox()
	local box = Core.part("PlusHaze", Vector3.new(size.X * 0.86, size.Y * 0.5, size.Z * 0.86), cf * CFrame.new(0, size.Y * 0.18, 0))
	box.Transparency = 1
	local pe = emitter(box, {
		Texture = SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(150, 135, 215)),
		LightEmission = 0.06,
		LightInfluence = 1,
		Size = NumberSequence.new({ NSK(0, 9), NSK(1, 15) }),
		Transparency = NumberSequence.new({ NSK(0, 1), NSK(0.25, 0.935), NSK(0.75, 0.945), NSK(1, 1) }),
		Lifetime = NumberRange.new(14, 20),
		Speed = NumberRange.new(0.2, 0.6),
		SpreadAngle = Vector2.new(180, 180),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-6, 6),
	})
	pcall(function()
		(pe :: any).Shape = Enum.ParticleEmitterShape.Box;
		(pe :: any).ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	end)
	pe.Rate = if q().name == "high" then 2.6 else 1.6
	rig.haze = { part = box, pe = pe, base = pe.Rate }
	-- warm start: the room is already hazy when you walk in
	pcall(function()
		pe:Emit(math.floor(pe.Rate * 10))
	end)
end

-------------------------------------------------------------------------------------------------
-- LED dance floor overlay (SurfaceGui on a local plane just above the tiles)
-------------------------------------------------------------------------------------------------
local FLOOR_COLS, FLOOR_ROWS = 6, 12
local function buildFloor()
	if not q().floor then
		return
	end
	local bed = Core.mainPart("TileBed")
	local cf: CFrame, size: Vector3
	local topY = -1e9
	for _, t in Core.clubParts("FloorTile") do
		topY = math.max(topY, t.Position.Y + t.Size.Y * 0.5)
	end
	if bed then
		cf = bed.CFrame.Rotation + bed.Position
		size = Vector3.new(bed.Size.X, 0.02, bed.Size.Z)
		topY = math.max(topY, bed.Position.Y + bed.Size.Y * 0.5)
	else
		local fb = S.Config.Fallback.DanceFloor
		cf = CFrame.new(fb.pos)
		size = fb.size
		topY = math.max(topY, fb.pos.Y)
	end
	cf = CFrame.new(cf.X, topY + 0.035, cf.Z) * cf.Rotation
	local p = Core.part("PlusFloor", size, cf)
	p.Transparency = 1
	local long = math.max(size.X, size.Z)
	local gui = Core.surface("GwClubPlusFloor", p, Enum.NormalId.Top, math.clamp(math.floor(360 / long), 8, 18), { Brightness = 1.6, MaxDistance = 140 })
	local root = Core.frame(gui, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	local cells = {}
	-- the canvas' long side follows the part's long axis
	local wide = size.X >= size.Z
	local cols = if wide then FLOOR_ROWS else FLOOR_COLS
	local rows = if wide then FLOOR_COLS else FLOOR_ROWS
	for r = 0, rows - 1 do
		for c = 0, cols - 1 do
			local f = Core.frame(root, {
				Position = UDim2.fromScale(c / cols + 0.006, r / rows + 0.006),
				Size = UDim2.fromScale(1 / cols - 0.012, 1 / rows - 0.012),
				BackgroundColor3 = WHITE,
				BackgroundTransparency = 1,
				ZIndex = 2,
			})
			table.insert(cells, { f = f, c = c, r = r, a = 1 })
		end
	end
	local rings = {}
	for i = 1, 5 do
		local ring = Core.frame(root, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromScale(0, 0),
			BackgroundTransparency = 1,
			ZIndex = 4,
			corner = UDim.new(0.5, 0),
		})
		local st = Instance.new("UIStroke")
		st.Thickness = 7
		st.Transparency = 1
		st.Color = WHITE
		st.Parent = ring
		local ar = Instance.new("UIAspectRatioConstraint")
		ar.AspectRatio = 1
		ar.Parent = ring
		table.insert(rings, { f = ring, s = st })
	end
	rig.floor = { part = p, gui = gui, cells = cells, rings = rings, ringN = 0, cols = cols, rows = rows, size = size, lastBeat = -1 }
end

-- world point -> floor canvas uv (0..1)
local function floorUV(world: Vector3?): Vector2
	local fl = rig.floor
	if not fl or not world then
		return Vector2.new(0.5, 0.5)
	end
	local lp = fl.part.CFrame:PointToObjectSpace(world)
	local u = math.clamp(lp.X / fl.size.X + 0.5, -0.4, 1.4)
	local v = math.clamp(lp.Z / fl.size.Z + 0.5, -0.4, 1.4)
	return Vector2.new(u, v)
end

local function floorStep(dt: number)
	local fl = rig.floor
	if not fl then
		return
	end
	local _phase, beat, _bpm, section, bar = Core.beat()
	local CS = Core.ClubShared
	local pal = (CS and CS.Palettes and CS.Palettes[({ intro = 1, build = 2, drop = 3, breakdown = 4, groove = 5 })[section] or 5]) or { VIOLET, CYAN, WHITE }
	if beat ~= fl.lastBeat then
		fl.lastBeat = beat
		for i, cell in fl.cells do
			local on = false
			local col = pal[1]
			if section == "drop" then
				on = S.hash(i, beat) > 0.74
				col = if S.hash(i, beat + 3) > 0.5 then pal[1] else pal[2]
			elseif section == "build" then
				-- rows chase toward the booth, faster as the build grows
				local k = (beat % 4)
				on = (cell.r % 4) == k and (bar % 8) >= 4
				col = pal[3]
			elseif section == "groove" then
				on = S.hash(i, beat) > 0.86
				col = pal[2]
			end
			if on then
				cell.a = 0.5
				cell.f.BackgroundColor3 = col
				cell.f.BackgroundTransparency = cell.a
			end
		end
	end
	-- slow sections: a soft wave; everything fades back between beats
	local slow = section == "intro" or section == "breakdown"
	local t = os.clock()
	for _, cell in fl.cells do
		if slow then
			local w = 0.5 + 0.5 * math.sin(t * 1.4 + cell.r * 0.55 + cell.c * 0.3)
			cell.a = 0.86 + 0.14 * (1 - w)
			cell.f.BackgroundColor3 = pal[1]:Lerp(pal[2], w)
			cell.f.BackgroundTransparency = cell.a
		elseif cell.a < 1 then
			cell.a = math.min(1, cell.a + dt * 1.7)
			cell.f.BackgroundTransparency = cell.a
		end
	end
end

-------------------------------------------------------------------------------------------------
-- mirror ball rays
-------------------------------------------------------------------------------------------------
local function buildMirror()
	local n = q().mirror
	if n <= 0 then
		return
	end
	local ball = Core.mainPart("MirrorBall")
	local pos = if ball then ball.Position else S.Config.Fallback.MirrorBall
	local h = holder("PlusMirror", pos)
	local a0 = Instance.new("Attachment")
	a0.Parent = h
	local rays = {}
	local golden = math.pi * (3 - math.sqrt(5))
	for i = 1, n do
		-- fibonacci directions, mostly sideways / downward (onto walls, floor and crowd)
		local y = -0.85 + 1.25 * ((i - 0.5) / n)
		local r = math.sqrt(math.max(0, 1 - y * y))
		local th = golden * i
		local dir = Vector3.new(math.cos(th) * r, y, math.sin(th) * r)
		local a1 = Core.sinkAttachment("MirrorEnd")
		local b = Instance.new("Beam")
		b.Attachment0 = a0
		b.Attachment1 = a1
		b.Width0 = 0.08
		b.Width1 = 0.42
		b.FaceCamera = true
		b.LightEmission = 1
		b.LightInfluence = 0
		b.Segments = 1
		b.Color = ColorSequence.new(if i % 3 == 0 then Color3.fromRGB(190, 230, 255) else WHITE)
		b.Transparency = NumberSequence.new({ NSK(0, 0.25), NSK(1, 0.8) })
		b.Enabled = false
		b.Parent = h
		table.insert(rays, { beam = b, a1 = a1, dir = dir })
	end
	rig.mirror = { part = h, pos = pos, rays = rays, untilT = 0, on = false, angle = 0 }
end

local function mirrorStep(dt: number)
	local m = rig.mirror
	if not m then
		return
	end
	local want = os.clock() < m.untilT
	if want ~= m.on then
		m.on = want
		for _, r in m.rays do
			r.beam.Enabled = want
		end
	end
	if not want then
		return
	end
	m.angle = (m.angle + dt * 0.4) % (math.pi * 2)
	local rot = CFrame.Angles(0, m.angle, 0)
	local left = m.untilT - os.clock()
	local fade = math.clamp(left / 0.8, 0, 1)
	for _, r in m.rays do
		local d = rot:VectorToWorldSpace(r.dir)
		Core.place(r.a1, Core.clipToRoom(m.pos, d, 80, 0.4))
		if fade < 1 then
			r.beam.Transparency = NumberSequence.new({ NSK(0, 1 - 0.75 * fade), NSK(1, 1 - 0.2 * fade) })
		end
	end
end

-------------------------------------------------------------------------------------------------
-- DJ booth glow + ON AIR sign
-------------------------------------------------------------------------------------------------
local function buildBooth()
	local led = Core.mainPart("DeskLED")
	local fb = S.Config.Fallback.BoothFront
	local pos = if led then led.Position else fb.pos
	local length = if led then math.max(led.Size.X, led.Size.Z) else fb.length
	local floor = Core.anchor("Show_Floor")
	local fpos = if floor then floor.Position else S.Config.Fallback.Floor
	local n = Vector3.new(fpos.X - pos.X, 0, fpos.Z - pos.Z)
	n = if n.Magnitude > 0.1 then n.Unit else Vector3.new(-1, 0, 0)
	local at = pos + n * 0.35
	local cf = CFrame.lookAt(at, at + n)
	local p = Core.part("PlusBooth", Vector3.new(length, 0.4, 0.1), cf)
	p.Transparency = 1
	local light = Instance.new("SurfaceLight")
	light.Face = Enum.NormalId.Front
	light.Range = 18
	light.Angle = 80
	light.Brightness = 1.2
	light.Color = VIOLET
	light.Shadows = false
	light.Parent = p
	-- two uplight ribbons at the desk ends
	local glows = {}
	for _, side in { -1, 1 } do
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(side * length * 0.5, -0.6, 0)
		a0.Parent = p
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(side * length * 0.5, 8.5, 0)
		a1.Parent = p
		local b = Instance.new("Beam")
		b.Attachment0 = a0
		b.Attachment1 = a1
		b.Width0 = 1.6
		b.Width1 = 4.2
		b.FaceCamera = true
		b.LightEmission = 1
		b.LightInfluence = 0
		b.Segments = 1
		b.Transparency = NumberSequence.new({ NSK(0, 0.55), NSK(1, 1) })
		b.Color = ColorSequence.new(VIOLET)
		b.Parent = p
		table.insert(glows, b)
	end
	-- ON AIR sign (BillboardGui in PlayerGui, adorned to our booth part)
	local bb = Core.billboard("GwClubPlusOnAir", p, UDim2.new(9, 0, 2, 0), Vector3.new(0, 6.8, 0), { MaxDistance = 140, Enabled = false, LightInfluence = 0 })
	local plate = Core.frame(bb, {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(25, 6, 22),
		BackgroundTransparency = 0.15,
		corner = UDim.new(0.3, 0),
		strokeColor = Color3.fromRGB(255, 60, 110),
		strokeT = 0,
	})
	local dot = Core.frame(plate, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.05, 0.5), Size = UDim2.fromScale(0.08, 0.36), BackgroundColor3 = Color3.fromRGB(255, 50, 70), corner = UDim.new(0.5, 0) })
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 1
	ar.Parent = dot
	local label = Core.text(plate, { Position = UDim2.fromScale(0.16, 0.12), Size = UDim2.fromScale(0.8, 0.76), Text = "", TextXAlignment = Enum.TextXAlignment.Left })
	rig.booth = { part = p, light = light, glows = glows, bb = bb, dot = dot, label = label, onAir = false, name = "" }
end

local function boothStep(_dt: number)
	local b = rig.booth
	if not b then
		return
	end
	local phase, _, _, section = Core.beat()
	local kick = (1 - phase) ^ 2.4
	local col = if b.onAir then MAGENTA:Lerp(Color3.fromRGB(255, 70, 90), 0.5 + 0.5 * math.sin(os.clock() * 3)) elseif section == "drop" then VIOLET:Lerp(CYAN, kick) else VIOLET
	b.light.Color = col
	b.light.Brightness = (if b.onAir then 2.6 else 1.2) + kick * (if section == "drop" or b.onAir then 3 else 1.2)
	local alpha = (if b.onAir then 0.35 else 0.58) - 0.15 * kick
	for _, g in b.glows do
		g.Color = ColorSequence.new(col)
		g.Transparency = NumberSequence.new({ NSK(0, alpha), NSK(1, 1) })
	end
	if b.onAir then
		b.dot.BackgroundTransparency = 0.6 * (0.5 + 0.5 * math.sin(os.clock() * 6))
	end
end

-------------------------------------------------------------------------------------------------
-- lifecycle
-------------------------------------------------------------------------------------------------
local function teardown()
	built = false
	for _, key in { "co2", "conf", "fount", "strobes", "tableConf", "burst", "haze", "floor", "mirror", "booth" } do
		rig[key] = nil
	end
	for _, name in { "PlusCO2", "PlusConfetti", "PlusTableConfetti", "PlusSpark", "PlusBurst", "PlusStrobe", "PlusHaze", "PlusFloor", "PlusMirror", "PlusBooth" } do
		for _, ch in Core.folder():GetChildren() do
			if ch.Name == name then
				ch:Destroy()
			end
		end
	end
	local pg = Core.player:FindFirstChildOfClass("PlayerGui")
	if pg then
		for _, n in { "GwClubPlusFloor", "GwClubPlusOnAir" } do
			local g = pg:FindFirstChild(n)
			if g then
				g:Destroy()
			end
		end
	end
	if Core.sinkPart then
		for _, a in Core.sinkPart:GetChildren() do
			if a.Name == "MirrorEnd" then
				a:Destroy()
			end
		end
	end
end

local builtQuality = ""
local function build()
	built = true
	builtQuality = q().name
	for _, fn in { buildCO2, buildConfetti, buildSparks, buildStrobes, buildHaze, buildFloor, buildMirror, buildBooth } do
		local ok, err = pcall(fn)
		if not ok then
			warn("[GwangalliClubPlus] fx build failed:", err)
		end
	end
	local dj = Core.state.DJ
	if type(dj) == "table" then
		Fx.booth(dj.on == true, tostring(dj.n or ""))
	end
end

function Fx.ready(): boolean
	return built and Core.inside and Core.showRoom
end

function Fx.init(core: any)
	Core = core
	S = core.S
	Core.job("fxlife", 2, function()
		local here = Core.inside and Core.showRoom
		if here then
			outsideSince = os.clock()
			if not built then
				build()
			elseif builtQuality ~= q().name then
				teardown()
				build()
			end
		elseif built and os.clock() - outsideSince > 30 then
			teardown()
		end
		return true
	end)
	Core.job("fxstep", 20, function(dt: number)
		if not Fx.ready() then
			return true
		end
		floorStep(dt)
		mirrorStep(dt)
		boothStep(dt)
		return true
	end)
	Core.on("DJ", function(dj: any)
		Fx.booth(type(dj) == "table" and dj.on == true, if type(dj) == "table" then tostring(dj.n or "") else "")
	end)
end

-------------------------------------------------------------------------------------------------
-- one-shots
-------------------------------------------------------------------------------------------------
local function pulses(list: { ParticleEmitter }?, count: number, n: number, gap: number)
	if not list or #list == 0 or count <= 0 then
		return
	end
	local per = math.max(1, math.floor(count / n))
	for k = 0, n - 1 do
		task.delay(k * gap, function()
			for _, pe in list do
				if pe.Parent then
					pe:Emit(per)
				end
			end
		end)
	end
end

-- CO2 jets on the booth (strength 1..3)
function Fx.co2(strength: number?)
	if not Fx.ready() then
		return
	end
	pulses(rig.co2, math.floor(q().co2 * (strength or 1)), 4, 0.1)
end

function Fx.confetti(strength: number?)
	if not Fx.ready() then
		return
	end
	pulses(rig.conf, math.floor(q().confetti / 3 * (strength or 1)), 3, 0.12)
end

function Fx.tableConfetti(pos: Vector3?, strength: number?)
	local tc = rig.tableConf
	if not Fx.ready() or not tc or not pos then
		return
	end
	tc.part.CFrame = CFrame.new(pos + Vector3.new(0, 0.6, 0))
	pulses(tc.list, math.floor(q().confetti / 6 * (strength or 1)), 2, 0.1)
end

-- cold-spark fountains on the booth front for `seconds`
function Fx.fountain(seconds: number)
	if not Fx.ready() or not rig.fount then
		return
	end
	local rate = math.max(8, q().sparks)
	for _, pe in rig.fount do
		pe.Rate = rate
	end
	task.delay(seconds, function()
		for _, pe in rig.fount or {} do
			pe.Rate = 0
		end
	end)
end

local BURST_COLS = { GOLD, MAGENTA, CYAN, WHITE, VIOLET }
function Fx.burst(pos: Vector3, color: Color3?, n: number?)
	local b = rig.burst
	if not Fx.ready() or not b then
		return
	end
	b.part.CFrame = CFrame.new(pos)
	b.pe.Color = ColorSequence.new({ CSK(0, WHITE), CSK(0.2, color or GOLD), CSK(1, color or GOLD) })
	b.pe:Emit(n or q().sparks)
end

-- indoor 폭죽: aerial bursts over the dance floor + the fountains
function Fx.fireworks(count: number?)
	if not Fx.ready() then
		return
	end
	local fl = Core.anchor("Show_Floor")
	local centre = if fl then fl.Position else S.Config.Fallback.Floor
	local k = count or 3
	for i = 1, k do
		task.delay((i - 1) * 0.38, function()
			local p = centre + Vector3.new((S.hash(i, os.clock()) - 0.5) * 16, 11 + S.hash(i, 2) * 4, (S.hash(i, 5 + os.clock()) - 0.5) * 22)
			Fx.burst(p, BURST_COLS[((i + math.floor(os.clock())) % #BURST_COLS) + 1])
		end)
	end
	Fx.fountain(2.2)
end

-- screen flash for the local viewer (very short; skipped with reduced motion)
local flashGui: ScreenGui? = nil
function Fx.flash(color: Color3?, strength: number?)
	if not Fx.ready() or q().reduced then
		return
	end
	local g = flashGui
	if not (g and g.Parent) then
		g = Instance.new("ScreenGui")
		g.Name = "GwClubPlusFlash"
		g.IgnoreGuiInset = true
		g.ResetOnSpawn = false
		g.DisplayOrder = 30
		g.Parent = Core.playerGui()
		flashGui = g
	end
	local f = Core.frame(g :: ScreenGui, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = color or WHITE, BackgroundTransparency = 1 - 0.35 * math.clamp(strength or 1, 0, 1.5), Active = false })
	Core.tween(f, 0.45, { BackgroundTransparency = 1 })
	task.delay(0.5, function()
		f:Destroy()
	end)
end

-- strobe: our bars on the LED wall's top edge flash (max 8 Hz; reduced motion -> two soft flashes)
local strobeUntil = 0
function Fx.strobe(seconds: number)
	if not Fx.ready() or not rig.strobes or #rig.strobes == 0 then
		return
	end
	local reduced = q().reduced
	local hz = if reduced then 2 else 8
	seconds = if reduced then math.min(seconds, 1) else math.min(seconds, 2.5)
	strobeUntil = os.clock() + seconds
	if Core.running("strobe") then
		return
	end
	local on = false
	Core.job("strobe", hz * 2, function()
		local list = rig.strobes
		if not list then
			return false
		end
		local live = os.clock() < strobeUntil
		on = live and not on
		for _, s in list do
			s.part.Transparency = if on then 0 else 1
			s.light.Brightness = if on then (if reduced then 3 else 9) else 0
		end
		return live
	end)
end

function Fx.hazeBoost(seconds: number)
	local h = rig.haze
	if not Fx.ready() or not h then
		return
	end
	h.pe.Rate = h.base * 3
	pcall(function()
		h.pe:Emit(6)
	end)
	task.delay(seconds, function()
		if h.pe.Parent then
			h.pe.Rate = h.base
		end
	end)
end

-- LED floor ring ripple from a world point (default: the floor centre)
function Fx.ripple(color: Color3?, from: Vector3?, rings: number?)
	local fl = rig.floor
	if not Fx.ready() or not fl then
		return
	end
	local uv = floorUV(from)
	local period = 60 / (select(3, Core.beat()) or 126)
	for k = 1, math.clamp(rings or 1, 1, 4) do
		task.delay((k - 1) * period * 0.5, function()
			fl.ringN = (fl.ringN % #fl.rings) + 1
			local r = fl.rings[fl.ringN]
			r.f.Position = UDim2.fromScale(uv.X, uv.Y)
			r.f.Size = UDim2.fromScale(0.05, 0.05)
			r.s.Color = color or CYAN
			r.s.Transparency = 0.05
			Core.tween(r.f, period * 3, { Size = UDim2.fromScale(2.6, 2.6) }, Enum.EasingStyle.Quad)
			Core.tween(r.s, period * 3, { Transparency = 1 }, Enum.EasingStyle.Quad)
		end)
	end
end

function Fx.floorFlash(color: Color3?)
	local fl = rig.floor
	if not Fx.ready() or not fl then
		return
	end
	for _, cell in fl.cells do
		cell.a = 0.25
		cell.f.BackgroundColor3 = color or WHITE
		cell.f.BackgroundTransparency = cell.a
	end
end

function Fx.mirror(seconds: number)
	local m = rig.mirror
	if not Fx.ready() or not m then
		return
	end
	local wasOff = os.clock() >= m.untilT
	m.untilT = math.max(m.untilT, os.clock() + seconds)
	if wasOff then
		for _, r in m.rays do
			r.beam.Transparency = NumberSequence.new({ NSK(0, 0.25), NSK(1, 0.8) })
		end
	end
end

function Fx.booth(onAir: boolean, name: string)
	local b = rig.booth
	if not b then
		return
	end
	b.onAir = onAir
	b.name = name
	b.bb.Enabled = onAir
	b.label.Text = if onAir then string.format(Core.L.Show.onAir, name) else ""
end

-------------------------------------------------------------------------------------------------
-- followers: a sparkle trail (+ optional SpotLight from above) the Director moves over a rig
-------------------------------------------------------------------------------------------------
function Fx.follower(name: string, color: Color3, withSpot: boolean, withTrail: boolean): any
	local p = Core.part("PlusFollow_" .. name, Vector3.new(0.3, 0.3, 0.3), CFrame.new(Core.roomBox().Position))
	p.Transparency = 1
	local obj: any = { part = p }
	if withTrail then
		local a = Instance.new("Attachment")
		a.Position = Vector3.new(0, -2.4, 0)
		a.Parent = p
		obj.pe = emitter(a, {
			Texture = SPARK,
			Color = ColorSequence.new({ CSK(0, WHITE), CSK(1, color) }),
			LightEmission = 1,
			LightInfluence = 0,
			Size = NumberSequence.new({ NSK(0, 0.38), NSK(1, 0) }),
			Transparency = NumberSequence.new({ NSK(0, 0.1), NSK(1, 1) }),
			Lifetime = NumberRange.new(0.9, 1.5),
			Speed = NumberRange.new(0.5, 2),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, 1.2, 0),
			Rate = 14,
		})
	end
	if withSpot then
		-- the light hangs 11 studs above the rig, pointing down: a pool of light walks with them
		local sa = Instance.new("Attachment")
		sa.Position = Vector3.new(0, 11, 0)
		sa.Orientation = Vector3.new(-90, 0, 0)
		sa.Parent = p
		local sp = Instance.new("SpotLight")
		sp.Face = Enum.NormalId.Front
		sp.Angle = 38
		sp.Range = 20
		sp.Brightness = 5
		sp.Color = color:Lerp(WHITE, 0.55)
		sp.Shadows = false
		sp.Parent = sa
		obj.spot = sp
	end
	return obj
end

function Fx.release(obj: any)
	if obj and obj.part then
		if obj.pe then
			obj.pe.Rate = 0
		end
		local part = obj.part
		obj.part = nil
		task.delay(1.6, function()
			part:Destroy()
		end)
	end
end

return Fx
