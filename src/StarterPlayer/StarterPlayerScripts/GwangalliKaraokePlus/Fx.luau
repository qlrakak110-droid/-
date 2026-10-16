-- GwangalliKaraokePlus/Fx (client): the booth light show and the effect bursts, only in the room I am
-- in, all in Workspace.GwKaraokePlusLocal (never inside map models; the map's own MirrorBall is left alone).
--   * 2 lights max (a beat-pulsing colour PointLight at the mirror ball, a sweeping SpotLight), lasers
--     (Beams from the laser projector sweeping the floor in 후렴 / 간주), neon colour from the genre;
--   * bursts: 폭죽 sparks, 꽃가루 petals, 환호 confetti, 100점 gold rain (ParticleEmitters, built-in texture);
--   * my own emotes (cheer / dance / clap) through the game's GwangalliAnim when it is available.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fx = {}

local K: any
local S: any
local player = Players.LocalPlayer

local folder: Folder
local ballAnchor: Part
local laserAnchor: Part
local burstAnchor: Part
local point: PointLight
local spot: SpotLight
local beams: { any } = {}
local emitters: { [string]: ParticleEmitter } = {}
local Anim: any = nil
local room: any = nil
local lastState = ""

local function anchor(name: string): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = folder
	return p
end

local function emitter(name: string, colors: { Color3 }, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Enabled = false
	local kp = {}
	for i, c in colors do
		table.insert(kp, ColorSequenceKeypoint.new((i - 1) / math.max(1, #colors - 1), c))
	end
	if #kp == 1 then
		table.insert(kp, ColorSequenceKeypoint.new(1, colors[1]))
	end
	e.Color = ColorSequence.new(kp)
	e.LightEmission = 0.6
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = burstAnchor
	emitters[name] = e
	return e
end

local function hsv(h: number, s: number, v: number): Color3
	return Color3.fromHSV(h % 1, s, v)
end

local GENRE_HUE = { ballad = 0.62, acoustic = 0.1, rnb = 0.78, pop = 0.9, citypop = 0.85, dance = 0.88, edm = 0.55, trot = 0.12, hiphop = 0.75, rock = 0.0, kids = 0.3, folk = 0.08, ost = 0.6 }

local function place(v: any)
	local parts = v.parts or {}
	local zone = v.zone
	if not zone then
		return
	end
	local ceilingY = zone.Position.Y + zone.Size.Y * 0.5 - 0.6
	local ball = parts.ball
	local bpos = if ball then ball.Position - Vector3.new(0, 0.9, 0) else Vector3.new(zone.Position.X, ceilingY, zone.Position.Z)
	ballAnchor.CFrame = CFrame.new(bpos)
	local laser = parts.laser
	laserAnchor.CFrame = CFrame.new(if laser then laser.Position - Vector3.new(0, 0.4, 0) else bpos)
	local tbl = parts.table
	local center = if tbl then tbl.Position else zone.Position
	burstAnchor.CFrame = CFrame.new(Vector3.new(center.X, ceilingY - 0.3, center.Z))
end

local function setLights(on: boolean)
	point.Enabled = on
	spot.Enabled = on
	for _, b in beams do
		b.beam.Enabled = false
	end
end

function Fx.burst(kind: string)
	local v = room
	if not v or (K.me and K.me.settings and K.me.settings.fx == false) then
		return
	end
	if kind == "fire" then
		emitters.sparks:Emit(60)
		point.Color = Color3.fromRGB(255, 170, 70)
		point.Brightness = 6
	elseif kind == "petal" then
		emitters.petals:Emit(70)
	elseif kind == "cheer" then
		emitters.confetti:Emit(80)
	elseif kind == "gold" then
		emitters.gold:Emit(120)
		emitters.confetti:Emit(80)
	elseif kind == "tamb" then
		emitters.sparks:Emit(6)
	elseif kind == "clap" then
		emitters.confetti:Emit(12)
	elseif kind == "dance" then
		emitters.confetti:Emit(24)
	end
end

-- my own emote (replicates through my character's Animator)
function Fx.emote(kind: string)
	if not Anim then
		return
	end
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	local name = if kind == "dance" then "dance" .. tostring(math.random(1, 3)) elseif kind == "cheer" or kind == "fire" or kind == "petal" then "cheer" else nil
	if name then
		pcall(Anim.play, hum, name, { looped = false })
	end
end

function Fx.update(_dt: number)
	local v = K.Rooms.current()
	if v ~= room then
		room = v
		lastState = ""
		if v then
			place(v)
		end
	end
	if not v or not v.zone then
		setLights(false)
		return
	end
	local fxOn = not (K.me and K.me.settings and K.me.settings.fx == false)
	local st = v.state
	if st ~= lastState then
		if st == "score" then
			local res = v.result
			local top = 0
			for _, r in (type(res) == "table" and res.sc) or {} do
				if type(r) == "table" and type(r.s) == "number" then
					top = math.max(top, r.s)
				end
			end
			if top >= 100 then
				Fx.burst("gold")
			end
		end
		lastState = st
	end
	local playing = st == "play" and v.chart ~= nil and not v.paused
	if not fxOn or not (playing or st == "score" or st == "settle") then
		setLights(false)
		return
	end
	local t = os.clock()
	local hue = GENRE_HUE[(v.song and v.song.preset) or ""] or 0.6
	if playing then
		local sNow = K.Rooms.songTime(v, S.now()) - (K.Band.localDelay or 0)
		local beatPhase = (sNow / v.chart.beat) % 1
		local sect = S.Chart.sectAt(v.chart, sNow)
		local hot = sect ~= nil and (sect.kind == "chorus" or sect.kind == "inter")
		point.Enabled = true
		spot.Enabled = true
		point.Color = hsv(hue + 0.08 * math.sin(t * 0.7) + (if hot then (math.floor(sNow / v.chart.beat) % 4) * 0.12 else 0), 0.75, 1)
		point.Brightness = (if hot then 2.4 else 1.3) + (1 - beatPhase) * (if hot then 2.5 else 1)
		point.Range = 16
		spot.Color = hsv(hue + 0.5, 0.6, 1)
		spot.Brightness = if hot then 3 else 1.6
		ballAnchor.CFrame = CFrame.new(ballAnchor.Position) * CFrame.Angles(0, t * 0.8, 0) * CFrame.Angles(math.rad(-65 + 20 * math.sin(t * 0.9)), 0, 0)
		for i, b in beams do
			b.beam.Enabled = hot
			if hot then
				local ang = t * (0.9 + i * 0.15) + i * 1.57
				local zone = v.zone
				local floorY = zone.Position.Y - zone.Size.Y * 0.5 + 0.1
				local rx = math.min(zone.Size.X, zone.Size.Z) * 0.35
				local target = Vector3.new(zone.Position.X + math.cos(ang) * rx, floorY, zone.Position.Z + math.sin(ang * 1.3) * rx)
				b.a1.WorldPosition = target
				b.beam.Color = ColorSequence.new(hsv(hue + i * 0.18 + t * 0.05, 0.8, 1))
			end
		end
	else
		-- settle / score: slow gold or soft white
		local res = v.result
		point.Enabled = true
		spot.Enabled = false
		for _, b in beams do
			b.beam.Enabled = false
		end
		local gold = false
		for _, r in (type(res) == "table" and res.sc) or {} do
			if type(r) == "table" and type(r.s) == "number" and r.s >= 100 then
				gold = true
			end
		end
		point.Color = if gold then Color3.fromRGB(255, 200, 80) else hsv(hue, 0.3, 1)
		point.Brightness = if st == "settle" then 1 + 1.5 * math.abs(math.sin(t * 9)) else (if gold then 3 + math.sin(t * 6) else 1.4)
	end
end

function Fx.init(k: any)
	K = k
	S = k.S
	local old = workspace:FindFirstChild(S.NAMES.ClientFolder)
	if old then
		old:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = S.NAMES.ClientFolder
	folder:SetAttribute("LOD", "near")
	folder.Parent = workspace
	ballAnchor = anchor("BallLight")
	laserAnchor = anchor("Laser")
	burstAnchor = anchor("Burst")
	point = Instance.new("PointLight")
	point.Shadows = false
	point.Range = 16
	point.Enabled = false
	point.Parent = ballAnchor
	spot = Instance.new("SpotLight")
	spot.Shadows = false
	spot.Angle = 55
	spot.Range = 22
	spot.Face = Enum.NormalId.Front
	spot.Enabled = false
	spot.Parent = ballAnchor
	for i = 1, 4 do
		local a0 = Instance.new("Attachment")
		a0.Parent = laserAnchor
		local holder = anchor("LaserTarget" .. i)
		local a1 = Instance.new("Attachment")
		a1.Parent = holder
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Width0 = 0.08
		beam.Width1 = 0.12
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Transparency = NumberSequence.new(0.15)
		beam.Enabled = false
		beam.Parent = laserAnchor
		beams[i] = { beam = beam, a0 = a0, a1 = a1 }
	end
	emitter("sparks", { Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 120, 40) }, {
		Lifetime = NumberRange.new(0.6, 1.2), Speed = NumberRange.new(10, 18), SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) }),
		Acceleration = Vector3.new(0, -14, 0), Drag = 2, Rate = 0,
	})
	emitter("petals", { Color3.fromRGB(255, 170, 200), Color3.fromRGB(255, 230, 240) }, {
		Lifetime = NumberRange.new(2.5, 4), Speed = NumberRange.new(1, 4), SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new(0.28), Acceleration = Vector3.new(0, -2.2, 0), Drag = 1.2, Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-120, 120), Rate = 0,
	})
	emitter("confetti", { Color3.fromRGB(255, 80, 170), Color3.fromRGB(80, 220, 255), Color3.fromRGB(255, 214, 70), Color3.fromRGB(120, 255, 140) }, {
		Lifetime = NumberRange.new(2, 3.5), Speed = NumberRange.new(3, 8), SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new(0.22), Acceleration = Vector3.new(0, -4, 0), Drag = 1, Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-200, 200), Rate = 0,
	})
	emitter("gold", { Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 180, 40) }, {
		Lifetime = NumberRange.new(2.5, 4), Speed = NumberRange.new(2, 6), SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new(0.26), Acceleration = Vector3.new(0, -3, 0), Drag = 0.8, Rate = 0,
	})
	local okA, mod = pcall(function()
		local m = ReplicatedStorage:FindFirstChild("GwangalliAnim")
		return if m and m:IsA("ModuleScript") then require(m) :: any else nil
	end)
	if okA and type(mod) == "table" and type(mod.play) == "function" then
		Anim = mod
	end
	K.Net.onLive("fx", function(p)
		-- my own presses already played locally (instant feedback)
		if room and p.room == room.no and p.u ~= player.UserId then
			Fx.burst(p.fx)
			K.Band.fx(p.fx, true)
		end
	end)
end

return Fx
