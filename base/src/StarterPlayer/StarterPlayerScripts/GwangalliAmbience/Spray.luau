-- GwangalliAmbience/Spray (client): breaking-wave spray where the swell meets hard edges near the
-- camera: the rock groynes at both ends of the sand, the 민락항 breakwater tetrapods, the Millak
-- terraces / land edge and the 삼익비치 sea-wall riprap (GwangalliSeaData.spray).
--
-- Each active point is an Attachment on the Terrain with two ParticleEmitters (Rate 0, Emit only):
-- a burst of droplets thrown up and landward (gravity, drag) and a slower mist puff that drifts
-- with Workspace.GlobalWind. Bursts fire when the shared swell (Env.wavePhase) reaches the point,
-- scaled by the set size and the point's strength, skipping some waves so it never looks
-- mechanical. Texture: the engine's built-in smoke puff (no uploaded assets).
-- Only the nearest `max` points within `radius` of the camera hold emitters; the rest cost nothing.

local Spray = {}

local TIERS = {
	low = { radius = 220, max = 3, burst = 5, hz = 6 },
	saver = { radius = 150, max = 2, burst = 3, hz = 4 }, -- weak phones (GwangalliQuality saver)
	mid = { radius = 300, max = 6, burst = 8, hz = 15 },
	high = { radius = 380, max = 10, burst = 12, hz = 20 },
}
local TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local IMPACT = 0.04 -- phase at which the breaker reaches the rocks
local KIND_SCALE = { groyne = 1, tetrapod = 1.15, riprap = 0.9, wall = 0.8, terrace = 0.45 }

local function seq(points: { { number } }): NumberSequence
	local kps = {}
	for _, p in points do
		table.insert(kps, NumberSequenceKeypoint.new(p[1], p[2], p[3] or 0))
	end
	return NumberSequence.new(kps)
end

function Spray.start(Env: any)
	local list = Env.D.spray
	if type(list) ~= "table" or #list == 0 then
		return
	end
	local points = {}
	for i, sp in list do
		local pos, nrm = sp[1], sp[2]
		if typeof(pos) == "Vector3" and typeof(nrm) == "Vector3" then
			table.insert(points, {
				i = i,
				pos = pos,
				nrm = Vector3.new(nrm.X, 0, nrm.Z).Unit,
				w = (tonumber(sp[3]) or 1) * (KIND_SCALE[sp[4]] or 1),
				jitter = (Env.hash(i, 1.7) - 0.5) * 1.2,
			})
		end
	end
	local cfg = Env.pick(TIERS)
	Env.onTier(function()
		cfg = Env.pick(TIERS)
	end)
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if not terrain then
		return
	end

	type Holder = { att: Attachment, drops: ParticleEmitter, mist: ParticleEmitter, point: any?, lastWave: number }
	local free: { Holder } = {}
	local byPoint: { [any]: Holder } = {}

	local function makeHolder(): Holder
		local att = Instance.new("Attachment")
		att.Name = "GwangalliSpray"
		local drops = Instance.new("ParticleEmitter")
		drops.Name = "SprayDroplets"
		drops.Texture = TEXTURE
		drops.Rate = 0
		drops.Enabled = true
		drops.Color = ColorSequence.new(Color3.fromRGB(240, 246, 248))
		drops.LightEmission = 0.05
		drops.LightInfluence = 1
		drops.Size = seq({ { 0, 0.5 }, { 0.3, 1.8, 0.4 }, { 1, 3.2, 0.6 } })
		drops.Transparency = seq({ { 0, 0.2 }, { 0.45, 0.45 }, { 1, 1 } })
		drops.Lifetime = NumberRange.new(0.8, 1.5)
		drops.Speed = NumberRange.new(13, 24)
		drops.SpreadAngle = Vector2.new(20, 32)
		drops.Acceleration = Vector3.new(0, -42, 0)
		drops.Drag = 0.9
		drops.Rotation = NumberRange.new(0, 360)
		drops.RotSpeed = NumberRange.new(-50, 50)
		drops.EmissionDirection = Enum.NormalId.Top
		drops.ZOffset = 0.4
		drops.Parent = att
		local mist = Instance.new("ParticleEmitter")
		mist.Name = "SprayMist"
		mist.Texture = TEXTURE
		mist.Rate = 0
		mist.Enabled = true
		mist.Color = ColorSequence.new(Color3.fromRGB(232, 240, 244))
		mist.LightEmission = 0
		mist.LightInfluence = 1
		mist.Size = seq({ { 0, 2.2 }, { 1, 8, 1 } })
		mist.Transparency = seq({ { 0, 0.6 }, { 0.3, 0.7 }, { 1, 1 } })
		mist.Lifetime = NumberRange.new(2, 3.6)
		mist.Speed = NumberRange.new(3, 8)
		mist.SpreadAngle = Vector2.new(45, 45)
		mist.Acceleration = Vector3.new(0, 0.6, 0)
		mist.Drag = 0.7
		pcall(function()
			mist.WindAffectsDrag = true
		end)
		mist.Rotation = NumberRange.new(0, 360)
		mist.RotSpeed = NumberRange.new(-15, 15)
		mist.EmissionDirection = Enum.NormalId.Top
		mist.Parent = att
		att.Parent = terrain
		return { att = att, drops = drops, mist = mist, point = nil, lastWave = -1 }
	end

	local function bind(h: Holder, p: any)
		h.point = p
		-- +Y tilted landward (spray is thrown up and over the rocks)
		h.att.CFrame = CFrame.lookAt(p.pos, p.pos + p.nrm) * CFrame.Angles(0.38, 0, 0)
		h.lastWave = Env.waveIndex(Env.now() + p.jitter, p.pos.X)
		byPoint[p] = h
	end

	local function release(p: any)
		local h = byPoint[p]
		if h then
			byPoint[p] = nil
			h.point = nil
			h.att.CFrame = Env.HIDDEN_CF
			table.insert(free, h)
		end
	end

	local rng = Random.new()
	local order: { any } = {}
	local dist: { [any]: number } = {}

	Env.every("spray", function()
		return cfg.hz
	end, function(now: number)
		local cam = Env.focus()
		local R = cfg.radius
		table.clear(order)
		for _, p in points do
			local d = (p.pos - cam).Magnitude
			dist[p] = d
			if d < R then
				table.insert(order, p)
			end
		end
		table.sort(order, function(a, b)
			return dist[a] < dist[b]
		end)
		local want: { [any]: boolean } = {}
		for i = 1, math.min(#order, cfg.max) do
			want[order[i]] = true
		end
		for p in byPoint do
			if not want[p] then
				release(p)
			end
		end
		for p in want do
			if not byPoint[p] then
				local h = table.remove(free) or makeHolder()
				bind(h, p)
			end
		end
		for p, h in byPoint do
			local t = now + p.jitter
			local wi = Env.waveIndex(t, p.pos.X)
			local phase = Env.wavePhase(t, p.pos.X)
			if wi ~= h.lastWave and phase >= IMPACT then
				h.lastWave = wi
				if rng:NextNumber() > 0.22 then
					local set = Env.waveSet(t, p.pos.X)
					local near = math.clamp(1.4 - dist[p] / R, 0.5, 1)
					local n = math.floor(cfg.burst * p.w * set * near * rng:NextNumber(0.6, 1.25) + 0.5)
					if n > 0 and not Env.behind(p.pos, 10) then
						h.drops:Emit(n)
						h.mist:Emit(math.max(1, math.floor(n * 0.5)))
					end
				end
			end
		end
	end)
end

return Spray
