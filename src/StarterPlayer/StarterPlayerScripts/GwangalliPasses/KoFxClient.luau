-- GwangalliPasses/KoFxClient (client): draws KO 피니시 이펙트 (pass #4) sent by the server
-- (Event { kind = "kofx", fx, pos, by, victim, char?, self, preview? }). Stylised only, no gore.
-- Everything lives in Workspace.GwPassesFxLocal (anchored, no collide / query / touch, no shadows) and is
-- cleaned up after the effect. Built-in content only (rbxasset:// particles + sounds the place already uses).
-- The attacker (self = true) also gets a "K.O.!" banner, a small camera punch (not with reduced motion)
-- and a short 승리 포즈 (Roblox's default cheer / point emote) when standing. At most MAX_LIVE at once;
-- the low quality tier halves particles and drops the lights.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KoFxClient = {}

local P: any, K: any, KoFx: any, Neon: any, Config: any
local folder: Folder? = nil
local live = 0
local rng = Random.new()

local function fxFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = P.FX
	f.Parent = workspace
	folder = f
	return f
end

local function low(): boolean
	local ok, t = pcall(K.tier)
	return ok and t == "low"
end

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.Neon
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = fxFolder()
	return p
end

local function tween(inst: Instance, t: number, goals: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goals)
	tw:Play()
	return tw
end

local function later(t: number, inst: Instance)
	task.delay(t, function()
		if inst.Parent then
			inst:Destroy()
		end
	end)
end

local function sound(def: any, at: Vector3)
	if not def then
		return
	end
	local holder = part({ Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, Position = at })
	local s = Instance.new("Sound")
	s.SoundId = def.id
	s.Volume = def.vol or 0.6
	s.PlaybackSpeed = def.speed or 1
	s.RollOffMaxDistance = 140
	s.RollOffMinDistance = 12
	s.Parent = holder
	s:Play()
	if def.fb then
		task.delay(0.6, function()
			if s.Parent and not s.IsLoaded then
				s.SoundId = def.fb
				s:Play()
			end
		end)
	end
	later(4, holder)
end

local function emitter(at: Vector3, props: { [string]: any }, count: number): Part
	local holder = part({ Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, Position = at })
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.LightEmission = 0.8
	e.Texture = KoFx.TEX.sparkle
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = holder
	e:Emit(if low() then math.ceil(count / 2) else count)
	later(4, holder)
	return holder
end

local function flash(at: Vector3, color: Color3, range: number, t: number)
	if low() then
		return
	end
	local holder = part({ Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, Position = at })
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = 6
	l.Shadows = false
	l.Parent = holder
	tween(l, t, { Brightness = 0 })
	later(t + 0.1, holder)
end

local function ring(at: Vector3, color: Color3, size: number, t: number)
	local r = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 1.5, 1.5), CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)), Color = color, Transparency = 0.15 })
	tween(r, t, { Size = Vector3.new(0.12, size, size), Transparency = 1 })
	later(t + 0.05, r)
end

local function billboard(at: Vector3, text: string, colors: { Color3 }, size: number, t: number, rise: number?): BillboardGui
	local anchor = part({ Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, Position = at })
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(size, size * 0.5)
	bb.LightInfluence = 0
	bb.AlwaysOnTop = true
	bb.MaxDistance = 200
	bb.Adornee = anchor
	bb.Parent = anchor
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Font = Enum.Font.GothamBlack
	l.TextScaled = true
	l.Text = text
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Parent = bb
	if #colors >= 2 then
		local g = Instance.new("UIGradient")
		local kps = {}
		for i, c in colors do
			table.insert(kps, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c))
		end
		g.Color = ColorSequence.new(kps)
		g.Rotation = 90
		g.Parent = l
	end
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(20, 10, 30)
	st.Thickness = 3
	st.Parent = l
	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = l
	tween(scale, 0.22, { Scale = 1.15 }, Enum.EasingStyle.Back)
	task.delay(0.22, function()
		if scale.Parent then
			tween(scale, 0.15, { Scale = 1 })
		end
	end)
	if rise then
		tween(anchor, t, { Position = at + Vector3.new(0, rise, 0) }, Enum.EasingStyle.Sine)
	end
	task.delay(t * 0.65, function()
		if l.Parent then
			tween(l, t * 0.35, { TextTransparency = 1 })
			tween(st, t * 0.35, { Transparency = 1 })
		end
	end)
	later(t + 0.1, anchor)
	return bb
end

---------------------------------------------------------------------------------------------------
-- the six effects (pos = the victim's feet / body; top = above the head)
---------------------------------------------------------------------------------------------------
local FX = {}

function FX.lightning(d: any, pos: Vector3)
	local top = pos + Vector3.new(rng:NextNumber(-3, 3), 46, rng:NextNumber(-3, 3))
	local function bolt()
		local pts = { top }
		local n = 7
		for i = 1, n - 1 do
			local t = i / n
			local p = top:Lerp(pos, t)
			table.insert(pts, p + Vector3.new(rng:NextNumber(-2.4, 2.4), 0, rng:NextNumber(-2.4, 2.4)))
		end
		table.insert(pts, pos)
		local segs = {}
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local len = (b - a).Magnitude
			table.insert(segs, part({ Size = Vector3.new(0.32, 0.32, len), CFrame = CFrame.lookAt((a + b) / 2, b), Color = d.color2, Transparency = 0 }))
			table.insert(segs, part({ Size = Vector3.new(0.9, 0.9, len), CFrame = CFrame.lookAt((a + b) / 2, b), Color = d.color, Transparency = 0.7 }))
		end
		return segs
	end
	sound(KoFx.SND[d.sounds[1]], pos)
	for k = 1, 3 do
		local segs = bolt()
		flash(pos + Vector3.new(0, 6, 0), d.color, 40, 0.25)
		task.wait(0.07)
		for _, s in segs do
			tween(s, 0.12, { Transparency = 1 })
			later(0.15, s)
		end
		if k == 1 then
			sound(KoFx.SND[d.sounds[2]], pos)
			ring(pos + Vector3.new(0, 0.1, 0), d.color, 26, 0.6)
			emitter(pos + Vector3.new(0, 1, 0), { Color = ColorSequence.new(d.color, d.color2), Size = NumberSequence.new(0.5, 0), Speed = NumberRange.new(14, 26), SpreadAngle = Vector2.new(180, 180), Lifetime = NumberRange.new(0.4, 0.8), Drag = 4 }, 50)
		end
		task.wait(0.09)
	end
end

function FX.fireworks(d: any, pos: Vector3)
	local cols = { d.color, d.color2, Color3.fromRGB(80, 220, 255), Color3.fromRGB(150, 110, 255) }
	for i = 1, 3 do
		task.spawn(function()
			task.wait((i - 1) * 0.28)
			local start = pos + Vector3.new(rng:NextNumber(-2, 2), 0.5, rng:NextNumber(-2, 2))
			local burst = pos + Vector3.new(rng:NextNumber(-7, 7), rng:NextNumber(16, 24), rng:NextNumber(-7, 7))
			local c = cols[(i - 1) % #cols + 1]
			local rocket = part({ Size = Vector3.new(0.3, 0.3, 1.2), CFrame = CFrame.lookAt(start, burst), Color = c })
			sound(KoFx.SND[d.sounds[1]], start)
			local trail = Instance.new("ParticleEmitter")
			trail.Texture = KoFx.TEX.sparkle
			trail.Color = ColorSequence.new(c)
			trail.Size = NumberSequence.new(0.35, 0)
			trail.Lifetime = NumberRange.new(0.3, 0.5)
			trail.Rate = if low() then 30 else 60
			trail.Speed = NumberRange.new(0.5, 1)
			trail.LightEmission = 1
			trail.Parent = rocket
			tween(rocket, 0.55, { CFrame = CFrame.lookAt(burst, burst + (burst - start).Unit) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			task.wait(0.55)
			trail.Enabled = false
			rocket.Transparency = 1
			later(1, rocket)
			sound(KoFx.SND[d.sounds[2]], burst)
			sound(KoFx.SND[d.sounds[3]], burst)
			flash(burst, c, 50, 0.6)
			emitter(burst, { Color = ColorSequence.new(c, Color3.new(1, 1, 1)), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) }), Speed = NumberRange.new(18, 26), SpreadAngle = Vector2.new(180, 180), Lifetime = NumberRange.new(1.0, 1.6), Drag = 2.6, Acceleration = Vector3.new(0, -8, 0), LightEmission = 1 }, 80)
		end)
	end
	task.wait(1.6)
end

function FX.skull(d: any, pos: Vector3)
	sound(KoFx.SND[d.sounds[1]], pos)
	ring(pos + Vector3.new(0, 0.1, 0), d.color2, 18, 0.55)
	emitter(pos + Vector3.new(0, 2, 0), { Texture = KoFx.TEX.smoke, Color = ColorSequence.new(d.color2, Color3.fromRGB(40, 20, 70)), Size = NumberSequence.new(2, 4), Transparency = NumberSequence.new(0.3, 1), Speed = NumberRange.new(3, 6), SpreadAngle = Vector2.new(180, 180), Lifetime = NumberRange.new(0.8, 1.3), LightEmission = 0.3 }, 24)
	billboard(pos + Vector3.new(0, 4.6, 0), "☠", { d.color, d.color2 }, 4.2, d.dur, 2.2)
	task.wait(0.3)
	sound(KoFx.SND[d.sounds[2]], pos)
	task.wait(d.dur - 0.3)
end

function FX.stars(d: any, pos: Vector3, char: Instance?)
	sound(KoFx.SND[d.sounds[1]], pos)
	emitter(pos + Vector3.new(0, 2, 0), { Color = ColorSequence.new(d.color, d.color2), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) }), Speed = NumberRange.new(16, 28), SpreadAngle = Vector2.new(180, 180), Lifetime = NumberRange.new(0.5, 0.9), Drag = 3, LightEmission = 1 }, 60)
	flash(pos + Vector3.new(0, 3, 0), d.color, 30, 0.4)
	-- dizzy stars circling over the head
	local head = char and char:FindFirstChild("Head")
	local centre = if head and head:IsA("BasePart") then head.Position + Vector3.new(0, 1.4, 0) else pos + Vector3.new(0, 3.2, 0)
	local stars = {}
	for i = 1, 5 do
		local bb = billboard(centre, "★", { d.color, Color3.fromRGB(255, 160, 40) }, 1.1, d.dur, nil)
		table.insert(stars, { bb = bb, a = i * (2 * math.pi / 5) })
	end
	sound(KoFx.SND[d.sounds[2]], pos)
	local t0 = os.clock()
	while os.clock() - t0 < d.dur do
		local t = os.clock() - t0
		for _, s in stars do
			local a = s.a + t * 5
			local anchor = s.bb.Adornee
			if anchor and anchor:IsA("BasePart") then
				anchor.Position = centre + Vector3.new(math.cos(a) * 1.5, math.sin(t * 6 + s.a) * 0.15, math.sin(a) * 1.5)
			end
		end
		task.wait()
	end
end

function FX.money(d: any, pos: Vector3)
	sound(KoFx.SND[d.sounds[1]], pos)
	sound(KoFx.SND[d.sounds[2]], pos)
	local n = if low() then 10 else 20
	for _ = 1, n do
		local from = pos + Vector3.new(rng:NextNumber(-5, 5), rng:NextNumber(9, 13), rng:NextNumber(-5, 5))
		local bill = part({ Size = Vector3.new(0.06, 0.62, 1.25), CFrame = CFrame.new(from) * CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28)), Color = d.color, Material = Enum.Material.SmoothPlastic })
		local face = part({ Size = Vector3.new(0.07, 0.26, 0.3), CFrame = bill.CFrame, Color = Color3.fromRGB(70, 140, 80), Material = Enum.Material.SmoothPlastic })
		local land = Vector3.new(from.X + rng:NextNumber(-2, 2), pos.Y + 0.1, from.Z + rng:NextNumber(-2, 2))
		local t = rng:NextNumber(1.3, 2.0)
		local goal = CFrame.new(land) * CFrame.Angles(math.rad(90), rng:NextNumber(0, 6.28), 0)
		tween(bill, t, { CFrame = goal }, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
		tween(face, t, { CFrame = goal }, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
		task.delay(t + 0.4, function()
			tween(bill, 0.4, { Transparency = 1 })
			tween(face, 0.4, { Transparency = 1 })
		end)
		later(t + 0.9, bill)
		later(t + 0.9, face)
	end
	emitter(pos + Vector3.new(0, 6, 0), { Color = ColorSequence.new(d.color2), Size = NumberSequence.new(0.4, 0), Speed = NumberRange.new(4, 9), SpreadAngle = Vector2.new(180, 180), Lifetime = NumberRange.new(0.6, 1.2), Acceleration = Vector3.new(0, -10, 0), LightEmission = 1 }, 40)
	billboard(pos + Vector3.new(0, 5, 0), "💸", {}, 2.6, 1.4, 1.5)
	task.wait(d.dur)
end

function FX.stamp(d: any, pos: Vector3)
	sound(KoFx.SND[d.sounds[1]], pos)
	billboard(pos + Vector3.new(0, 4.4, 0), "K.O.!", { d.color2, d.color }, 6, d.dur, 0.6)
	task.wait(0.12)
	sound(KoFx.SND[d.sounds[2]], pos)
	ring(pos + Vector3.new(0, 0.1, 0), d.color, 16, 0.45)
	emitter(pos + Vector3.new(0, 0.6, 0), { Texture = KoFx.TEX.smoke, Color = ColorSequence.new(Color3.fromRGB(220, 210, 200)), Size = NumberSequence.new(1.2, 2.6), Transparency = NumberSequence.new(0.4, 1), Speed = NumberRange.new(8, 12), SpreadAngle = Vector2.new(5, 180), Lifetime = NumberRange.new(0.5, 0.9), Drag = 5, LightEmission = 0 }, 28)
	task.wait(d.dur)
end

---------------------------------------------------------------------------------------------------
-- the attacker's own extras
---------------------------------------------------------------------------------------------------
local bannerGui: ScreenGui? = nil
local function banner(d: any, neonId: any)
	local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return
	end
	if not bannerGui or not bannerGui.Parent then
		local g = Instance.new("ScreenGui")
		g.Name = "GwangalliPassesKOBanner"
		g.ResetOnSpawn = false
		g.DisplayOrder = 40
		g.IgnoreGuiInset = true
		g.Parent = pg
		bannerGui = g
	end
	local g = bannerGui :: ScreenGui
	for _, c in g:GetChildren() do
		c:Destroy()
	end
	local pal = Neon.get(neonId)
	local cols = if pal then pal.colors else { d.color2, d.color }
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.fromScale(0.5, 0.3)
	l.Size = UDim2.fromScale(0.5, 0.11)
	l.Font = Enum.Font.GothamBlack
	l.TextScaled = true
	l.Text = P.Lines.t("kofx_banner")
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Parent = g
	local gr = Instance.new("UIGradient")
	local kps = {}
	for i, c in cols do
		table.insert(kps, ColorSequenceKeypoint.new((i - 1) / math.max(1, #cols - 1), c))
	end
	if #kps == 1 then
		table.insert(kps, ColorSequenceKeypoint.new(1, cols[1]))
	end
	gr.Color = ColorSequence.new(kps)
	gr.Parent = l
	local st = Instance.new("UIStroke")
	st.Thickness = 3
	st.Color = Color3.fromRGB(20, 10, 30)
	st.Parent = l
	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.AnchorPoint = Vector2.new(0.5, 0)
	sub.Position = UDim2.fromScale(0.5, 0.36)
	sub.Size = UDim2.fromScale(0.4, 0.035)
	sub.Font = Enum.Font.GothamBold
	sub.TextScaled = true
	sub.Text = d.glyph .. "  " .. d.name .. " 피니시"
	sub.TextColor3 = Color3.fromRGB(255, 236, 200)
	sub.Parent = g
	local sc = Instance.new("UIScale")
	sc.Scale = 1.8
	sc.Parent = l
	tween(sc, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(1.1, function()
		tween(l, 0.35, { TextTransparency = 1 })
		tween(st, 0.35, { Transparency = 1 })
		tween(sub, 0.35, { TextTransparency = 1 })
	end)
	task.delay(1.6, function()
		if l.Parent then
			l:Destroy()
			sub:Destroy()
		end
	end)
end

local function punch()
	if K.reduced() then
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local fov = cam.FieldOfView
	tween(cam, 0.08, { FieldOfView = fov + 5 })
	task.delay(0.1, function()
		tween(cam, 0.3, { FieldOfView = fov }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end)
end

local function emote(fxId: string)
	if not Config.KOFX.EMOTE then
		return
	end
	local ch = Players.LocalPlayer.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if not hum or hum.SeatPart or hum.Health <= 0 or (ch :: Model):GetAttribute("GwKO") == true then
		return
	end
	if hum.MoveDirection.Magnitude > 0.1 then
		return -- running: no pose
	end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local rig = if hum.RigType == Enum.HumanoidRigType.R15 then "R15" else "R6"
	local which = KoFx.EMOTE_FOR[fxId] or "cheer"
	local ids = KoFx.EMOTES[rig]
	-- the place's own animation table when present (same Roblox ids)
	local am = ReplicatedStorage:FindFirstChild("GwangalliAnim")
	if am and am:IsA("ModuleScript") then
		local ok, A = pcall(require, am)
		local list = ok and type(A) == "table" and A.IDS and A.IDS[rig] and A.IDS[rig][which]
		if type(list) == "table" and type(list[1]) == "string" then
			ids = table.clone(ids)
			ids[which] = list[1]
		end
	end
	local id = ids[which]
	if not id then
		return
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action
		track:Play(0.12)
		task.delay(1.5, function()
			pcall(function()
				track:Stop(0.25)
			end)
		end)
	end
end

local function play(payload: any)
	local d = KoFx.get(payload.fx)
	if not d or typeof(payload.pos) ~= "Vector3" then
		return
	end
	if live >= Config.KOFX.MAX_LIVE then
		return
	end
	live += 1
	if payload.self then
		task.spawn(banner, d, payload.neon)
		task.spawn(punch)
		task.spawn(emote, d.id)
	end
	local fn = FX[d.id]
	local ok, err = pcall(fn, d, payload.pos, if typeof(payload.char) == "Instance" then payload.char else nil)
	if not ok then
		warn("[GwangalliPasses] kofx " .. tostring(d.id) .. ": " .. tostring(err))
	end
	live -= 1
end

function KoFxClient.start(ctx: any)
	P, K, Config = ctx.P, ctx.K, ctx.P.Config
	KoFx, Neon = P.mod("KoFx"), P.mod("Neon")
	ctx.Net.on("kofx", function(payload: any)
		play(payload)
	end)
end

return KoFxClient
