-- GwangalliClubShow/Show (client): plays the bottle-service show from ONE server write (folder
-- attribute Show) and keeps the table life (folder attribute Tables). Everything is local.
--   * staff: pooled GwangalliNPCLooks rigs (black outfits + earpieces) come out of the staff door
--     one by one, walk the server's path (ClubShared.encodePath) at Show.Speed with a bottle held
--     high and a sparkler fountain (ParticleEmitter, rate capped by GwangalliQuality tier), peel into
--     a line in front of the table (ShowShared.lineup), sway with the sparklers for Show.Hold
--     seconds, present + bow, and walk back; the middle one carries a lit name board (filtered name)
--   * the room: ColorCorrection dim, a spotlight beam + floor pool following the line leader then the
--     table, the LED wall overlay (SurfaceGui on the Show_LEDWall anchor: "G2 테이블 감사합니다 🥂"),
--     the DJ shout-out bubble, the crowd's cheer (ClubShared.Bus.playerDanceAt -> ClubLights), and
--     for the top tier confetti + CO2 bursts on the next music beat
--   * table life: per owned table a cloned prop set (LED ice bucket with glow, bottles, glasses,
--     fruit, a sparkler once) placed on the table top with a soft drop-in; removed when it expires
-- Exported for Booking: Show.led, Show.spotTo, Show.spotOff, Show.confetti, Show.pulse.
-- Cost: one driver job while a show runs (path math + one BulkMoveTo + rig steps); nothing when far.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local Show = {}

local C: any
local S: any
local Club: any
local player = Players.LocalPlayer

local active: any = nil
local lastId = -1
local fx: any = { led = nil, spot = nil, cc = nil, ledSerial = 0, dimSerial = 0 }

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

-- custom poses (GwangalliAnim pose tables: degrees, see GwangalliAnim header)
local POSE_HIGH = { RightShoulder = { 168, 0, -8 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 26, 0, 10 }, LeftElbow = { 40, 0, 0 }, Neck = { 6, 0, 0 } }
local POSE_SIGN = { RightShoulder = { 158, 0, -16 }, RightElbow = { 24, 0, 0 }, LeftShoulder = { 158, 0, 16 }, LeftElbow = { 24, 0, 0 }, Neck = { 8, 0, 0 } }
local POSE_PRESENT = { RightShoulder = { 72, 0, -24 }, RightElbow = { 18, 0, 0 }, LeftShoulder = { 30, 0, 14 }, LeftElbow = { 40, 0, 0 }, Waist = { -6, 0, 0 } }

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function v3(t: any): Vector3?
	if type(t) == "table" and type(t[1]) == "number" then
		return Vector3.new(t[1], t[2] or 0, t[3] or 0)
	end
	return nil
end

---------------------------------------------------------------------------------------------------
-- Room effects (shared with Booking)
---------------------------------------------------------------------------------------------------
local function ledEnsure(): any?
	local led = fx.led
	if led and led.part.Parent then
		return led
	end
	local anchor = C.anchor("Show_LEDWall")
	if not anchor then
		return nil
	end
	local part = C.part("ClubShowLED", anchor.Size, anchor.CFrame, Color3.new(0, 0, 0))
	part.Transparency = 1
	local sg = Instance.new("SurfaceGui")
	sg.Name = "LED"
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 9
	sg.LightInfluence = 0
	sg.Brightness = 2.6
	sg.MaxDistance = 230
	sg.ZOffset = 1
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromRGB(8, 6, 20)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Parent = sg
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 20, 120)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(10, 8, 30)), ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 70, 110)) })
	grad.Rotation = 10
	grad.Parent = root
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.fromScale(0.5, 0.12)
	title.Size = UDim2.fromScale(0.92, 0.46)
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextStrokeColor3 = Color3.fromRGB(255, 60, 170)
	title.TextStrokeTransparency = 0.2
	title.TextTransparency = 1
	title.Text = ""
	title.Parent = root
	local shimmer = Instance.new("UIGradient")
	shimmer.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 214, 110)), ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255, 255, 255)), ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 255, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 230, 255)) })
	shimmer.Parent = title
	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.BackgroundTransparency = 1
	sub.AnchorPoint = Vector2.new(0.5, 0)
	sub.Position = UDim2.fromScale(0.5, 0.62)
	sub.Size = UDim2.fromScale(0.86, 0.24)
	sub.Font = Enum.Font.GothamBold
	sub.TextScaled = true
	sub.TextColor3 = Color3.fromRGB(120, 230, 255)
	sub.TextTransparency = 1
	sub.Text = ""
	sub.Parent = root
	local scale = Instance.new("UIScale")
	scale.Parent = root
	sg.Parent = part
	led = { part = part, root = root, title = title, sub = sub, scale = scale, shimmer = shimmer, grad = grad }
	fx.led = led
	-- endless shimmer sweep (engine tweens, no Lua per frame)
	pcall(function()
		local TweenService = game:GetService("TweenService")
		shimmer.Offset = Vector2.new(-0.6, 0)
		TweenService:Create(shimmer, TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Offset = Vector2.new(0.6, 0) }):Play()
		TweenService:Create(grad, TweenInfo.new(6, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false), { Rotation = 370 }):Play()
	end)
	return led
end

-- LED wall overlay: title + sub for `seconds` (a newer call replaces it)
function Show.led(title: string, sub: string, seconds: number)
	local led = ledEnsure()
	if not led then
		return
	end
	fx.ledSerial += 1
	local serial = fx.ledSerial
	led.title.Text = title
	led.sub.Text = sub
	led.scale.Scale = 0.82
	C.tween(led.scale, 0.55, { Scale = 1 }, Enum.EasingStyle.Back)
	C.tween(led.root, 0.45, { BackgroundTransparency = 0.12 }, Enum.EasingStyle.Quad)
	C.tween(led.title, 0.45, { TextTransparency = 0 }, Enum.EasingStyle.Quad)
	C.tween(led.sub, 0.6, { TextTransparency = 0 }, Enum.EasingStyle.Quad, nil, 0.25)
	task.delay(seconds, function()
		if fx.ledSerial ~= serial or not led.part.Parent then
			return
		end
		C.tween(led.root, 0.7, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
		C.tween(led.title, 0.5, { TextTransparency = 1 }, Enum.EasingStyle.Quad)
		C.tween(led.sub, 0.5, { TextTransparency = 1 }, Enum.EasingStyle.Quad)
	end)
end

local function spotEnsure(): any?
	local sp = fx.spot
	if sp and sp.target.Parent then
		return sp
	end
	local rigAnchor = C.anchor("Show_SpotRig")
	if not rigAnchor then
		return nil
	end
	local warm = Color3.fromRGB(255, 244, 222)
	local rig = C.part("ClubShowSpotRig", Vector3.new(0.4, 0.4, 0.4), CFrame.new(rigAnchor.Position), warm)
	rig.Transparency = 1
	local target = C.part("ClubShowSpotTarget", Vector3.new(0.2, 0.2, 0.2), CFrame.new(rigAnchor.Position - Vector3.new(0, 15, 0)), warm)
	target.Transparency = 1
	local a0 = Instance.new("Attachment")
	a0.Parent = rig
	local a1 = Instance.new("Attachment")
	a1.Parent = target
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 0.8
	beam.Width1 = 7.5
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Segments = 1
	beam.Color = ColorSequence.new(warm)
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0.82) })
	beam.Enabled = false
	beam.Parent = rig
	local pool = C.part("ClubShowSpotPool", Vector3.new(0.06, 7.5, 7.5), target.CFrame, warm, Enum.Material.Neon, nil, Enum.PartType.Cylinder)
	pool.Transparency = 1
	local light: SpotLight? = nil
	if C.caps().spotLight then
		local l = Instance.new("SpotLight")
		l.Face = Enum.NormalId.Front
		l.Angle = 16
		l.Range = 60
		l.Brightness = 5
		l.Color = warm
		l.Shadows = false
		l.Enabled = false
		l.Parent = rig
		light = l
	end
	sp = { rig = rig, target = target, beam = beam, pool = pool, light = light, pos = nil :: Vector3?, goal = nil :: Vector3?, on = false, floorY = 0 }
	fx.spot = sp
	return sp
end

-- aim the spot at a floor point (smoothly: the driver eases toward the goal)
function Show.spotTo(pos: Vector3, floorY: number?)
	local sp = spotEnsure()
	if not sp then
		return
	end
	sp.goal = pos
	sp.floorY = floorY or (pos.Y - 3)
	if not sp.on then
		sp.on = true
		sp.pos = sp.pos or pos
		sp.beam.Enabled = true
		if sp.light then
			sp.light.Enabled = true
		end
		C.tween(sp.pool, 0.4, { Transparency = 0.8 }, Enum.EasingStyle.Quad)
	end
	if not C.hasJob("showSpot") then
		C.addJob("showSpot", function(dt: number)
			local s = fx.spot
			if not s or not s.on or not s.goal then
				return false
			end
			local cur = s.pos or s.goal
			local a = 1 - math.exp(-dt * 6)
			cur = cur:Lerp(s.goal, a)
			s.pos = cur
			local floor = Vector3.new(cur.X, s.floorY + 0.06, cur.Z)
			C.queueMove(s.target, CFrame.new(floor))
			C.queueMove(s.pool, CFrame.new(floor) * CFrame.Angles(0, 0, math.pi / 2))
			C.queueMove(s.rig, CFrame.lookAt(s.rig.Position, floor))
			return true
		end)
	end
end

function Show.spotOff()
	local sp = fx.spot
	if not sp or not sp.on then
		return
	end
	sp.on = false
	sp.beam.Enabled = false
	if sp.light then
		sp.light.Enabled = false
	end
	C.tween(sp.pool, 0.4, { Transparency = 1 }, Enum.EasingStyle.Quad)
	C.removeJob("showSpot")
end

-- the room dims for the moment (ColorCorrection, local); pulse = a short flash for the 합석 swell
local function dim(on: boolean)
	fx.dimSerial += 1
	local serial = fx.dimSerial
	local cc = fx.cc
	if on then
		if not cc or not cc.Parent then
			local n = Instance.new("ColorCorrectionEffect")
			n.Name = "ClubShowDim"
			n.Parent = Lighting
			cc = n
			fx.cc = n
		end
		C.tween(cc, 1.2, { Brightness = -0.07, Contrast = 0.14, Saturation = 0.12, TintColor = Color3.fromRGB(236, 226, 255) }, Enum.EasingStyle.Sine)
	elseif cc then
		C.tween(cc, 1.4, { Brightness = 0, Contrast = 0, Saturation = 0, TintColor = Color3.new(1, 1, 1) }, Enum.EasingStyle.Sine)
		task.delay(1.5, function()
			if fx.dimSerial == serial and fx.cc then
				fx.cc:Destroy()
				fx.cc = nil
			end
		end)
	end
end
Show.dim = dim

function Show.pulse()
	local cc = fx.cc
	if not cc or not cc.Parent then
		return
	end
	cc.Brightness = 0.12
	C.tween(cc, 0.5, { Brightness = -0.07 }, Enum.EasingStyle.Quad)
end

-- confetti (and CO2 jets for the top tier) over a point
function Show.confetti(pos: Vector3, n: number, co2: boolean?)
	local caps = C.caps()
	local count = math.max(0, math.floor(n * (caps.confetti / 140)))
	if count <= 0 then
		return
	end
	local host = C.part("ClubShowConfetti", Vector3.new(0.2, 0.2, 0.2), CFrame.new(pos + Vector3.new(0, 11, 0)), Color3.new(1, 1, 1))
	host.Transparency = 1
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = SPARK
	pe.Rate = 0
	pe.Lifetime = NumberRange.new(2.8, 4.6)
	pe.Speed = NumberRange.new(9, 19)
	pe.SpreadAngle = Vector2.new(75, 75)
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Acceleration = Vector3.new(0, -8, 0)
	pe.Drag = 1.3
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.42), NumberSequenceKeypoint.new(1, 0.28) })
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-260, 260)
	pe.LightEmission = 0.6
	pe.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 79, 163)), ColorSequenceKeypoint.new(0.33, Color3.fromRGB(61, 214, 245)), ColorSequenceKeypoint.new(0.66, Color3.fromRGB(255, 194, 71)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)) })
	pe.Parent = host
	pcall(pe.Emit, pe, count)
	if co2 then
		for _, side in { -1, 1 } do
			local jet = C.part("ClubShowCO2", Vector3.new(0.2, 0.2, 0.2), CFrame.new(pos + Vector3.new(side * 3.2, 0.5, 0)), Color3.new(1, 1, 1))
			jet.Transparency = 1
			local sm = Instance.new("ParticleEmitter")
			sm.Texture = SMOKE
			sm.Rate = 0
			sm.Lifetime = NumberRange.new(0.7, 1.2)
			sm.Speed = NumberRange.new(26, 38)
			sm.SpreadAngle = Vector2.new(8, 8)
			sm.EmissionDirection = Enum.NormalId.Top
			sm.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 5) })
			sm.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
			sm.Color = ColorSequence.new(Color3.fromRGB(240, 246, 255))
			sm.Drag = 2
			sm.Parent = jet
			pcall(sm.Emit, sm, math.max(6, math.floor(count / 5)))
			task.delay(2.5, function()
				jet:Destroy()
			end)
		end
	end
	task.delay(6, function()
		host:Destroy()
	end)
end

---------------------------------------------------------------------------------------------------
-- Staff
---------------------------------------------------------------------------------------------------
local function staffSpec(i: number): any
	local Looks = C.Looks
	local body = if i % 2 == 0 then "f" else "m"
	local spec = Looks.resolve({ body = body, age = "young", style = "black", night = "black", acc = "earpiece", hair = if body == "f" then "ponytail" else "twoblock", hc = "black" }, "club_ocean_staff_" .. i, true)
	return spec
end

local function sparkler(parent: BasePart, offset: CFrame, rate: number): ParticleEmitter
	local att = Instance.new("Attachment")
	att.Name = "SparkTip"
	att.CFrame = offset
	att.Parent = parent
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "Sparkler"
	pe.Texture = SPARK
	pe.Rate = rate
	pe.Lifetime = NumberRange.new(0.35, 0.8)
	pe.Speed = NumberRange.new(4, 9)
	pe.SpreadAngle = Vector2.new(24, 24)
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Acceleration = Vector3.new(0, -14, 0)
	pe.Drag = 1.5
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.32), NumberSequenceKeypoint.new(1, 0.04) })
	pe.Color = ColorSequence.new(Color3.fromRGB(255, 246, 214), Color3.fromRGB(255, 166, 60))
	pe.LightEmission = 1
	pe.LightInfluence = 0
	pe.Enabled = false
	pe.Parent = att
	return pe
end

-- bottle in the right hand: neck along the hand's -Y (up while the arm is raised)
local function giveBottle(rec: any, tier: number, rate: number): ParticleEmitter?
	local color = if tier >= 4 then Color3.fromRGB(150, 120, 40) elseif tier == 3 then Color3.fromRGB(210, 220, 230) else Color3.fromRGB(30, 70, 40)
	local b = C.part("ShowBottle", Vector3.new(1.25, 0.42, 0.42), CFrame.new(), color, Enum.Material.Glass, rec.model, Enum.PartType.Cylinder)
	b.Transparency = 0.06
	C.attach(rec, "RightHand", b, CFrame.new(0, -0.75, 0) * CFrame.Angles(0, 0, math.pi / 2))
	local foil = C.part("ShowFoil", Vector3.new(0.3, 0.2, 0.2), CFrame.new(), Color3.fromRGB(230, 190, 90), Enum.Material.Foil, rec.model, Enum.PartType.Cylinder)
	C.attach(rec, "RightHand", foil, CFrame.new(0, -1.45, 0) * CFrame.Angles(0, 0, math.pi / 2))
	if rate <= 0 then
		return nil
	end
	-- the sparkler stick out of the neck; emitter on its tip pointing along the neck
	return sparkler(foil, CFrame.new(-0.25, 0, 0) * CFrame.Angles(0, 0, math.pi / 2), rate)
end

local function giveSign(rec: any, text: string, sub: string)
	local head = rec.rig.parts and rec.rig.parts.Head
	if not head then
		return
	end
	local board = C.part("ShowSign", Vector3.new(3.4, 1.3, 0.12), CFrame.new(), Color3.fromRGB(10, 8, 20), Enum.Material.SmoothPlastic, rec.model)
	C.attach(rec, "Head", board, CFrame.new(0, 2.1, -0.35))
	local rim = C.part("ShowSignRim", Vector3.new(3.55, 1.45, 0.08), CFrame.new(), Color3.fromRGB(255, 60, 170), Enum.Material.Neon, rec.model)
	C.attach(rec, "Head", rim, CFrame.new(0, 2.1, -0.32))
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 40
		sg.LightInfluence = 0
		sg.Brightness = 2.4
		sg.MaxDistance = 90
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 0.62)
		t.Font = Enum.Font.GothamBlack
		t.TextScaled = true
		t.TextColor3 = Color3.fromRGB(255, 236, 246)
		t.Text = text
		t.Parent = sg
		local s2 = Instance.new("TextLabel")
		s2.BackgroundTransparency = 1
		s2.Position = UDim2.fromScale(0, 0.6)
		s2.Size = UDim2.fromScale(1, 0.36)
		s2.Font = Enum.Font.GothamBold
		s2.TextScaled = true
		s2.TextColor3 = Color3.fromRGB(110, 230, 255)
		s2.Text = sub
		s2.Parent = sg
		sg.Parent = board
	end
end

local function truncated(pts: { Vector3 }, cum: { number }, d: number): { Vector3 }
	local out: { Vector3 } = {}
	for i, p in pts do
		if cum[i] < d then
			table.insert(out, p)
		else
			break
		end
	end
	local p, _ = S.sample(pts, cum, d)
	table.insert(out, p)
	return out
end

local function reversed(pts: { Vector3 }): { Vector3 }
	local out = {}
	for i = #pts, 1, -1 do
		table.insert(out, pts[i])
	end
	return out
end

local function stopShow()
	local a = active
	if not a then
		return
	end
	active = nil
	for _, st in a.staff do
		if st.rec then
			C.release(st.rec)
			st.rec = nil
		end
	end
	C.removeJob("showStaff")
	if a.dimmed then
		dim(false)
	end
	if a.spotOn then
		Show.spotOff()
	end
end

local function play(rec: any)
	stopShow()
	local pts = Club.decodePath(rec.path, rec.y)
	if not pts then
		return
	end
	local cum, total = S.polyline(pts)
	local P = S.Show
	local speed = if rec.tier <= 1 then P.BasicSpeed else P.Speed
	local caps = C.caps()
	local n = math.clamp(rec.staff or 1, 1, 5)
	if C.tier() == "low" or C.tier() == "saver" then
		n = math.min(n, 3)
	end
	local stopD = math.max(0, total - P.Stand)
	local front, dir = S.sample(pts, cum, stopD)
	local serve = v3(rec.serve) or pts[#pts]
	local spots = S.lineup(front, dir, n, P.Spread)
	local base = rec.at + P.LeadIn
	local staff = {}
	local allArrive = base
	for i = 1, n do
		local outPts = truncated(pts, cum, stopD)
		table.insert(outPts, spots[i])
		local oc, ot = S.polyline(outPts)
		local d0 = base + (i - 1) * P.Gap / speed
		local arrive = d0 + ot / speed
		allArrive = math.max(allArrive, arrive)
		staff[i] = { i = i, outPts = outPts, outCum = oc, outTotal = ot, d0 = d0, arrive = arrive, spot = spots[i], rec = nil, phase = "wait", sign = (n >= 3 and i == math.ceil(n / 2)) and rec.tier >= 2 }
	end
	local hold = if rec.tier <= 1 then 3 else P.Hold
	local holdEnd = allArrive + hold
	for i, st in staff do
		st.backPts = reversed(st.outPts)
		st.backCum, st.backTotal = S.polyline(st.backPts)
		st.back0 = holdEnd + 0.9 + (n - i) * 0.35
		st.done = st.back0 + st.backTotal / speed
	end
	local a = {
		rec = rec,
		staff = staff,
		speed = speed,
		allArrive = allArrive,
		holdEnd = holdEnd,
		serve = serve,
		endAt = math.max(rec.endAt or 0, holdEnd + 2),
		events = {},
		dimmed = false,
		spotOn = false,
		floorY = rec.y - 3,
	}
	active = a
	local aa = rec.aa == true
	local now = C.now()
	-- one-shot moments (skipped when joined more than a moment late)
	local function at(t: number, fn: () -> ())
		table.insert(a.events, { t = t, fn = fn, done = false })
	end
	if rec.tier >= 2 then
		at(rec.at, function()
			if C.inside() then
				dim(true)
				a.dimmed = true
			end
			Show.led(S.thanksTitle(rec.table, aa), string.format("%s님 · %s", rec.name or "손님", rec.label or ""), math.max(6, holdEnd - C.now() + 2))
		end)
	end
	if rec.dj then
		at(rec.at + 1.5, function()
			local dj = C.anchor("Show_DJ")
			if dj then
				C.bubble(dj, S.djLine(rec.table, rec.name or "손님"), 7, Color3.fromRGB(255, 194, 71))
			end
			C.Bus.playerDanceAt = os.clock() -- the crowd around cheers (ClubLights)
		end)
	end
	at(allArrive, function()
		if rec.tier >= 3 then
			C.Bus.playerDanceAt = os.clock()
		end
		if rec.confetti then
			C.onBeat(0.6, function()
				Show.confetti(serve, 140, true)
				Show.pulse()
			end)
		end
		if rec.owner == player.UserId then
			C.toast("서빙 완료 ✨", string.format("%s · %s", rec.table, rec.label or ""), "🍾", "club")
		end
	end)
	at(holdEnd + 1.5, function()
		if a.dimmed then
			dim(false)
			a.dimmed = false
		end
	end)
	for _, e in a.events do
		if now > e.t + 1.5 then
			e.done = true -- missed (late join)
		end
	end
	-- the per-frame job
	C.addJob("showStaff", function(_dt: number, tnow: number): boolean
		if active ~= a then
			return false
		end
		if tnow > a.endAt then
			stopShow()
			return false
		end
		for _, e in a.events do
			if not e.done and tnow >= e.t then
				e.done = true
				pcall(e.fn)
			end
		end
		local near = C.nearClub()
		-- spotlight: the line leader, then the table
		if rec.tier >= 2 and near then
			local s1 = staff[1]
			local target: Vector3? = nil
			if tnow < a.allArrive and s1 then
				local d = math.clamp((tnow - s1.d0) * speed, 0, s1.outTotal)
				target = S.sample(s1.outPts, s1.outCum, d)
				if tnow < s1.d0 then
					target = s1.outPts[1]
				end
			elseif tnow < a.holdEnd + 1 then
				target = a.serve
			end
			if target then
				Show.spotTo(target, a.floorY)
				a.spotOn = true
			elseif a.spotOn then
				Show.spotOff()
				a.spotOn = false
			end
		end
		local camPos = C.cameraPos()
		for _, st in staff do
			local live = near and tnow >= st.d0 - 0.4 and tnow < st.done
			if not live then
				if st.rec then
					C.release(st.rec)
					st.rec = nil
				end
				continue
			end
			local r = st.rec
			if not r then
				r = C.rig(staffSpec(st.i), "ClubShowStaff" .. st.i)
				if not r then
					continue
				end
				st.rec = r
				st.phase = "wait"
				if st.sign then
					giveSign(r, string.format("%s님 감사합니다", rec.name or "손님"), string.format("%s · THANK YOU", rec.table))
					st.spark = nil
				else
					local rate = if st.i <= 2 or caps.spark >= 20 then caps.spark else 0
					st.spark = giveBottle(r, rec.tier, rate)
				end
			end
			local pos, face
			local phase
			if tnow < st.d0 then
				pos, face = st.outPts[1], st.outPts[2] and (st.outPts[2] - st.outPts[1]) or Vector3.new(0, 0, 1)
				phase = "wait"
			elseif tnow < st.arrive then
				pos, face = S.sample(st.outPts, st.outCum, (tnow - st.d0) * speed)
				phase = "out"
			elseif tnow < st.back0 then
				pos = st.spot
				face = a.serve - st.spot
				phase = if tnow < a.holdEnd - 2.2 then "hold" elseif tnow < a.holdEnd then "present" else "bow"
			else
				pos, face = S.sample(st.backPts, st.backCum, (tnow - st.back0) * speed)
				phase = "back"
			end
			if phase ~= st.phase then
				st.phase = phase
				local ctl = r.ctl
				pcall(function()
					if phase == "out" then
						ctl:setMoving(speed)
						ctl:pose(if st.sign then POSE_SIGN else (if rec.tier <= 1 then "tray" else POSE_HIGH), 0.35)
						if st.spark then
							st.spark.Enabled = true
						end
					elseif phase == "hold" then
						ctl:setMoving(nil)
						ctl:gesture("sway")
					elseif phase == "present" then
						ctl:gesture(nil)
						ctl:pose(POSE_PRESENT, 0.5)
					elseif phase == "bow" then
						if st.spark then
							st.spark.Enabled = false
						end
						ctl:pose(nil, 0.3)
						ctl:emote("bow")
						-- the bottles are on the table now
						for _, p in r.props do
							if p.Name == "ShowBottle" or p.Name == "ShowFoil" then
								p.Transparency = 1
							end
						end
					elseif phase == "back" then
						ctl:pose(if st.sign then POSE_SIGN else nil, 0.3)
						ctl:setMoving(speed)
					end
				end)
			end
			C.queueMove(r.root, C.rootCF(pos, face))
			if (camPos - pos).Magnitude < 110 then
				C.step(r.ctl)
			end
		end
		return true
	end)
end

function Show.onShow(rec: any)
	if type(rec) ~= "table" or type(rec.id) ~= "number" or rec.id == 0 then
		return
	end
	if rec.id == lastId then
		return
	end
	lastId = rec.id
	if C.now() >= (rec.endAt or 0) then
		return
	end
	local ok, err = pcall(play, rec)
	if not ok then
		warn("[GwangalliClubShow] show:", err)
	end
end

function Show.current(): any?
	return active
end

---------------------------------------------------------------------------------------------------
-- Table life (props on owned tables)
---------------------------------------------------------------------------------------------------
local tableEntries: { [string]: any } = {} -- tableId -> { set, at, untilT, model?, built, sparkUntil }
local tableModels: { [string]: Model } = {}
local templates: { [string]: Model } = {}

local SETS = {
	basic = { rim = Color3.fromRGB(61, 214, 245), bottles = { { Color3.fromRGB(120, 70, 30), 0.9 }, { Color3.fromRGB(120, 70, 30), 0.9 }, { Color3.fromRGB(40, 120, 60), 0.9 } }, glasses = 4, flute = false, fruit = true, tower = 0 },
	champagne = { rim = Color3.fromRGB(255, 79, 163), bottles = { { Color3.fromRGB(30, 70, 40), 1.25 }, { Color3.fromRGB(30, 70, 40), 1.25 } }, glasses = 4, flute = true, fruit = false, tower = 0 },
	vodka = { rim = Color3.fromRGB(139, 108, 255), bottles = { { Color3.fromRGB(215, 225, 235), 1.3 }, { Color3.fromRGB(215, 225, 235), 1.3 } }, glasses = 5, flute = false, fruit = true, tower = 0, mixers = true },
	gold = { rim = Color3.fromRGB(255, 194, 71), bottles = { { Color3.fromRGB(150, 120, 40), 1.3 }, { Color3.fromRGB(150, 120, 40), 1.3 }, { Color3.fromRGB(150, 120, 40), 1.3 } }, glasses = 0, flute = true, fruit = false, tower = 2 },
	royal = { rim = Color3.fromRGB(255, 79, 163), rim2 = Color3.fromRGB(61, 214, 245), bottles = { { Color3.fromRGB(150, 120, 40), 1.6 }, { Color3.fromRGB(30, 70, 40), 1.25 }, { Color3.fromRGB(215, 225, 235), 1.3 }, { Color3.fromRGB(150, 120, 40), 1.3 } }, glasses = 0, flute = true, fruit = true, tower = 3, big = true },
}

local function upright(cf: CFrame): CFrame
	return cf * CFrame.Angles(0, 0, math.pi / 2)
end

local function buildTemplate(setId: string): Model
	local def = SETS[setId] or SETS.basic
	local m = Instance.new("Model")
	m.Name = "ClubTableSet_" .. setId
	local function p(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?): Part
		return C.part(name, size, cf, color, mat, m, shape)
	end
	local bigK = if def.big then 1.25 else 1
	-- LED ice bucket (back-left), glowing rim, ice, bottles leaning out
	local bc = CFrame.new(-0.95, 0, 0.42)
	local bucket = p("IceBucket", Vector3.new(0.9 * bigK, 1.0 * bigK, 1.0 * bigK), upright(bc * CFrame.new(0, 0.45 * bigK, 0)), Color3.fromRGB(200, 214, 226), Enum.Material.Glass, Enum.PartType.Cylinder)
	bucket.Transparency = 0.35
	bucket.Reflectance = 0.2
	p("BucketRim", Vector3.new(0.08, 1.08 * bigK, 1.08 * bigK), upright(bc * CFrame.new(0, 0.9 * bigK, 0)), def.rim, Enum.Material.Neon, Enum.PartType.Cylinder)
	p("BucketBase", Vector3.new(0.06, 1.0 * bigK, 1.0 * bigK), upright(bc * CFrame.new(0, 0.03, 0)), def.rim2 or def.rim, Enum.Material.Neon, Enum.PartType.Cylinder)
	p("Ice", Vector3.new(0.12, 0.86 * bigK, 0.86 * bigK), upright(bc * CFrame.new(0, 0.82 * bigK, 0)), Color3.fromRGB(230, 244, 255), Enum.Material.Ice, Enum.PartType.Cylinder)
	for i, b in def.bottles do
		local ang = (i - (#def.bottles + 1) / 2) * 0.55
		local len = b[2]
		local tilt = bc * CFrame.new(math.sin(ang) * 0.22, 0.5 * bigK, math.cos(ang) * 0.12) * CFrame.Angles(math.cos(ang) * 0.22, 0, -math.sin(ang) * 0.3)
		local body = p("Bottle", Vector3.new(len, 0.36, 0.36), upright(tilt * CFrame.new(0, len / 2, 0)), b[1], Enum.Material.Glass, Enum.PartType.Cylinder)
		body.Transparency = 0.08
		p("BottleNeck", Vector3.new(0.4, 0.16, 0.16), upright(tilt * CFrame.new(0, len + 0.18, 0)), b[1], Enum.Material.Glass, Enum.PartType.Cylinder)
		p("BottleFoil", Vector3.new(0.18, 0.18, 0.18), upright(tilt * CFrame.new(0, len + 0.42, 0)), Color3.fromRGB(230, 190, 90), Enum.Material.Foil, Enum.PartType.Cylinder)
		p("BottleLabel", Vector3.new(0.3, 0.37, 0.37), upright(tilt * CFrame.new(0, len * 0.42, 0)), if i == 1 and def.big then Color3.fromRGB(20, 20, 26) else Color3.fromRGB(236, 226, 200), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	end
	-- a sparkler stick in the ice (lit once, for a few seconds after the set lands)
	local stick = p("SparklerStick", Vector3.new(0.05, 0.9, 0.05), bc * CFrame.new(0.25, 1.35 * bigK, -0.1), Color3.fromRGB(255, 236, 190), Enum.Material.Neon)
	local att = Instance.new("Attachment")
	att.Name = "SparkTip"
	att.Position = Vector3.new(0, 0.45, 0)
	att.Parent = stick
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "SetSparkler"
	pe.Texture = SPARK
	pe.Rate = 30
	pe.Lifetime = NumberRange.new(0.3, 0.7)
	pe.Speed = NumberRange.new(3, 7)
	pe.SpreadAngle = Vector2.new(35, 35)
	pe.Acceleration = Vector3.new(0, -10, 0)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.04) })
	pe.Color = ColorSequence.new(Color3.fromRGB(255, 244, 210), Color3.fromRGB(255, 170, 60))
	pe.LightEmission = 1
	pe.Enabled = false
	pe.Parent = att
	-- glasses: an arc at the front (toward the guests), flutes or tumblers
	local gcount = def.glasses
	for i = 1, gcount do
		local x = (i - (gcount + 1) / 2) * 0.42
		local cf = CFrame.new(x, 0, -0.62 + math.abs(x) * 0.2)
		if def.flute then
			p("Flute", Vector3.new(0.55, 0.2, 0.2), upright(cf * CFrame.new(0, 0.35, 0)), Color3.fromRGB(235, 245, 255), Enum.Material.Glass, Enum.PartType.Cylinder).Transparency = 0.45
			p("FluteStem", Vector3.new(0.3, 0.06, 0.06), upright(cf * CFrame.new(0, 0.1, 0)), Color3.fromRGB(235, 245, 255), Enum.Material.Glass, Enum.PartType.Cylinder).Transparency = 0.4
		else
			p("Glass", Vector3.new(0.42, 0.3, 0.3), upright(cf * CFrame.new(0, 0.21, 0)), Color3.fromRGB(235, 245, 255), Enum.Material.Glass, Enum.PartType.Cylinder).Transparency = 0.5
		end
	end
	-- flute tower (gold / royal): 2-3 rings stacked at the front centre
	if def.tower > 0 then
		local levels = { { 6, 0.5 }, { 3, 0.27 }, { 1, 0 } }
		for lv = 1, def.tower do
			local ring = levels[lv]
			for k = 1, ring[1] do
				local ang = (k / ring[1]) * math.pi * 2
				local cf = CFrame.new(math.cos(ang) * ring[2] + 0.15, (lv - 1) * 0.58, -0.45 + math.sin(ang) * ring[2])
				p("TowerFlute", Vector3.new(0.55, 0.2, 0.2), upright(cf * CFrame.new(0, 0.3, 0)), Color3.fromRGB(255, 236, 190), Enum.Material.Glass, Enum.PartType.Cylinder).Transparency = 0.4
			end
		end
	end
	if def.fruit then
		local fc = CFrame.new(0.95, 0, 0.4)
		p("FruitPlate", Vector3.new(0.06, 1.0, 1.0), upright(fc * CFrame.new(0, 0.03, 0)), Color3.fromRGB(245, 245, 245), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		local cols = { Color3.fromRGB(230, 60, 70), Color3.fromRGB(255, 190, 40), Color3.fromRGB(120, 200, 70), Color3.fromRGB(150, 60, 160), Color3.fromRGB(255, 140, 40) }
		for k, col in cols do
			local ang = k / #cols * math.pi * 2
			p("Fruit", Vector3.new(0.22, 0.22, 0.22), fc * CFrame.new(math.cos(ang) * 0.25, 0.15, math.sin(ang) * 0.25), col, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		end
	end
	if def.mixers then
		for k = 1, 2 do
			p("Mixer", Vector3.new(0.45, 0.22, 0.22), upright(CFrame.new(0.55 + k * 0.28, 0.23, -0.05)), if k == 1 then Color3.fromRGB(40, 140, 220) else Color3.fromRGB(230, 230, 236), Enum.Material.Metal, Enum.PartType.Cylinder)
		end
	end
	pcall(function()
		m.WorldPivot = CFrame.new()
	end)
	m:SetAttribute("LOD", "near")
	return m
end

local function tableTop(model: Model, servePart: Instance?): (Vector3?, Vector3?)
	for _, name in { "BottleSpot", "TableTop", "MarbleTop", "Tabletop", "Top" } do
		local p = model:FindFirstChild(name, true)
		if p and p:IsA("BasePart") then
			local cf, sz = p.CFrame, p.Size
			local halfY = 0.5 * (math.abs(cf.RightVector.Y) * sz.X + math.abs(cf.UpVector.Y) * sz.Y + math.abs(cf.LookVector.Y) * sz.Z)
			return p.Position + Vector3.new(0, halfY, 0), (if servePart and servePart:IsA("BasePart") then servePart.Position else nil)
		end
	end
	local sp = servePart
	if sp and sp:IsA("BasePart") then
		local look = flat(sp.CFrame.LookVector)
		local ahead = if look.Magnitude > 0.5 then look.Unit * 2.4 else Vector3.zero
		return sp.Position + ahead - Vector3.new(0, 0.6, 0), sp.Position
	end
	return nil, nil
end

local function buildProps(id: string, e: any)
	local model = tableModels[id]
	if not model or not model.Parent then
		return
	end
	local top, servePos = tableTop(model, model:FindFirstChild("ServePoint", true))
	if not top then
		return
	end
	local tpl = templates[e.set]
	if not tpl then
		tpl = buildTemplate(e.set)
		templates[e.set] = tpl
	end
	local m = tpl:Clone()
	m.Name = "ClubTableSet_" .. id
	local face = if servePos then flat(servePos - top) else Vector3.new(0, 0, -1)
	if face.Magnitude < 0.1 then
		face = Vector3.new(0, 0, -1)
	end
	local base = CFrame.lookAt(top, top + face.Unit)
	local glow: PointLight? = nil
	if C.caps().spotLight then
		local rim = m:FindFirstChild("BucketRim")
		if rim and rim:IsA("BasePart") then
			local l = Instance.new("PointLight")
			l.Range = 6
			l.Brightness = 1.3
			l.Color = rim.Color
			l.Shadows = false
			l.Parent = rim
			glow = l
		end
	end
	m.Parent = C.folder()
	-- soft drop-in onto the table (short tween driver)
	local drop = Instance.new("NumberValue")
	drop.Value = 0
	local function apply()
		local a = drop.Value
		pcall(function()
			m:PivotTo(base * CFrame.new(0, (1 - a) * 0.9, 0))
		end)
	end
	apply()
	drop.Changed:Connect(apply)
	C.tween(drop, 0.5, { Value = 1 }, Enum.EasingStyle.Back)
	task.delay(0.6, function()
		drop:Destroy()
	end)
	-- the sparkler burns for a few seconds after the set lands
	if C.now() - e.at < 8 then
		for _, d in m:GetDescendants() do
			if d:IsA("ParticleEmitter") and d.Name == "SetSparkler" then
				d.Rate = math.max(6, math.floor(C.caps().spark * 0.9))
				d.Enabled = true
				task.delay(math.max(1, 8 - (C.now() - e.at)), function()
					d.Enabled = false
				end)
			end
		end
	end
	e.model = m
	e.glow = glow
	e.built = true
end

local function clearProps(e: any)
	if e.model then
		e.model:Destroy()
	end
	e.model = nil
	e.built = false
end

function Show.onTables(map: any)
	if type(map) ~= "table" then
		return
	end
	for id, e in tableEntries do
		local n = map[id]
		if not n or n.set ~= e.set or n.at ~= e.at then
			clearProps(e)
			tableEntries[id] = nil
		end
	end
	for id, n in map do
		if type(n) == "table" and type(n.at) == "number" and n.at > 0 and not tableEntries[id] then
			tableEntries[id] = { set = n.set or "basic", at = n.at, untilT = n.untilT or (n.at + 480), owner = n.owner, built = false }
		end
	end
end

function Show.tableEntry(id: string): any?
	return tableEntries[id]
end

local function tablesTick()
	local now = C.now()
	local cam = C.cameraPos()
	for id, e in tableEntries do
		if now >= e.untilT then
			clearProps(e)
			tableEntries[id] = nil
			continue
		end
		local model = tableModels[id]
		local d = math.huge
		if model and model.Parent then
			local ok, pos = pcall(function()
				return model:GetPivot().Position
			end)
			if ok then
				d = (pos - cam).Magnitude
			end
		end
		if not e.built and now >= e.at - 0.15 and d < 95 then
			buildProps(id, e)
		elseif e.built and d > 150 then
			clearProps(e)
		end
	end
end

function Show.init(core: any)
	C = core
	S = core.S
	Club = core.Club
	local tag = (Club.Tags and Club.Tags.Table) or "ClubTable"
	local function addTable(m: Instance)
		if m:IsA("Model") then
			local id = m:GetAttribute("TableId")
			tableModels[if type(id) == "string" and id ~= "" then id else m.Name] = m
		end
	end
	for _, m in CollectionService:GetTagged(tag) do
		addTable(m)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(addTable)
	task.spawn(function()
		while true do
			task.wait(0.5)
			local ok, err = pcall(tablesTick)
			if not ok then
				warn("[GwangalliClubShow] tables:", err)
				task.wait(2)
			end
		end
	end)
end

return Show
