-- GwangalliGarage/Fx: everything the 정비소 shows in the world (client only, no server cost):
--   * repair choreography (GarageEvent "repair"): the lift's moving parts (attribute LiftMoves) and the
--     car rise LiftHeight in 2 s (TweenService on a NumberValue applied with BulkMoveTo; a rigged owned car
--     moves through its anchored DriveBase), sparks + wrench clanks at the wheels, the LED blinks, then the
--     lift comes down. On the display lift (remote repair) the raised car is lowered and lifted back.
--   * wash choreography ("wash"): the gantry slides over the car and back (TravelOffset), the brushes spin,
--     foam particles for 3 s, then the body shines (Reflectance up, kept while DriveShineUntil > now)
--   * owned cars in Workspace.GwangalliPlayerCars: dirt darkens the paint (GS.dirtColor of DriveColor by
--     DriveDirt, no textures), a cheap smoke ParticleEmitter under the hood when DriveCondition < 30
--     (not on the low quality tier; thicker when the engine is dead)
--   * staff rigs (GarageStaff): Roblox's default idle animation through GwangalliAnim

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Fx = {}

local K: any, GS: any, Net: any = nil, nil, nil
local Quality: any = nil
local Anim: any = nil

local SPARK_TEX = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEX = "rbxasset://textures/particles/smoke_main.dds"
local CLANK = "rbxasset://sounds/clickfast.wav"
local WHIR = "rbxasset://sounds/swoosh.wav"

local function lowTier(): boolean
	if Quality then
		local ok, v = pcall(Quality.isLow)
		return ok and v == true
	end
	return false
end

---------------------------------------------------------------------------------------------------
-- Moving groups of anchored parts (BulkMoveTo) by a world offset driven by a tweened NumberValue
---------------------------------------------------------------------------------------------------
type Group = { parts: { BasePart }, orig: { CFrame } }

local function group(list: { Instance }): Group
	local g: Group = { parts = {}, orig = {} }
	for _, inst in list do
		if inst:IsA("BasePart") then
			table.insert(g.parts, inst)
			table.insert(g.orig, inst.CFrame)
		elseif inst:IsA("Model") then
			for _, d in inst:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(g.parts, d)
					table.insert(g.orig, d.CFrame)
				end
			end
		end
	end
	return g
end

local function applyOffset(g: Group, off: Vector3)
	local parts, cfs = {}, {}
	for i, p in g.parts do
		if p.Parent then
			table.insert(parts, p)
			table.insert(cfs, g.orig[i] + off)
		end
	end
	pcall(function()
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameNotChanged)
	end)
end

-- Tweens alpha 0 -> 1 (or 1 -> 0) over `t` s and calls step(alpha) each change. Yields until done.
local function animate(t: number, from: number, to: number, style: Enum.EasingStyle, step: (number) -> ())
	local v = Instance.new("NumberValue")
	v.Value = from
	local conn = v:GetPropertyChangedSignal("Value"):Connect(function()
		step(v.Value)
	end)
	local tw = TweenService:Create(v, TweenInfo.new(t, style, Enum.EasingDirection.InOut), { Value = to })
	tw:Play()
	local done = false
	tw.Completed:Connect(function()
		done = true
	end)
	local t0 = os.clock()
	while not done and os.clock() - t0 < t + 1 do
		task.wait()
	end
	step(to)
	conn:Disconnect()
	v:Destroy()
end

local function sound(parent: Instance, id: string, volume: number, speed: number): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.PlaybackSpeed = speed
	s.RollOffMaxDistance = 120
	s.Parent = parent
	s:Play()
	task.delay(3, function()
		s:Destroy()
	end)
	return s
end

local function emitter(parent: BasePart, props: { [string]: any }): ParticleEmitter
	local pe = Instance.new("ParticleEmitter")
	for k, v in props do
		(pe :: any)[k] = v
	end
	pe.Parent = parent
	return pe
end

-- An invisible local anchor part at a world position (particles / sounds).
local function anchorAt(pos: Vector3, size: Vector3?): Part
	local p = Instance.new("Part")
	p.Name = "GarageFxAnchor"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = size or Vector3.new(1, 1, 1)
	p.CFrame = CFrame.new(pos)
	p.Parent = workspace
	return p
end

local function bboxOf(m: Model): (CFrame, Vector3)
	local ok, cf, size = pcall(function()
		return m:GetBoundingBox()
	end)
	if ok then
		return cf, size
	end
	return m:GetPivot(), Vector3.new(6, 5, 16)
end

---------------------------------------------------------------------------------------------------
-- LED sign
---------------------------------------------------------------------------------------------------
local ledBusy = 0
local function blinkLED(seconds: number)
	ledBusy += 1
	local my = ledBusy
	task.spawn(function()
		local t0 = os.clock()
		local on = true
		while os.clock() - t0 < seconds and my == ledBusy do
			on = not on
			for _, led in CollectionService:GetTagged(GS.Tags.LED) do
				local tl = led:FindFirstChild("Text", true)
				if tl and tl:IsA("TextLabel") then
					tl.TextTransparency = if on then 0 else 0.7
				end
			end
			task.wait(0.35)
		end
		for _, led in CollectionService:GetTagged(GS.Tags.LED) do
			local tl = led:FindFirstChild("Text", true)
			if tl and tl:IsA("TextLabel") then
				tl.TextTransparency = 0
			end
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Repair choreography
---------------------------------------------------------------------------------------------------
local function liftFor(role: string): Model?
	for _, l in CollectionService:GetTagged(GS.Tags.Lift) do
		if l:IsA("Model") and l:GetAttribute("Role") == role and l:IsDescendantOf(workspace) then
			return l
		end
	end
	return nil
end

local function movingParts(lift: Model): { Instance }
	local out = {}
	for _, d in lift:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("LiftMoves") == true then
			table.insert(out, d)
		end
	end
	return out
end

local running: { [Instance]: boolean } = {}

local function sparks(car: Model, seconds: number)
	local cf, size = bboxOf(car)
	local low = lowTier()
	for _, s in { -1, 1 } do
		local pos = (cf * CFrame.new(s * size.X * 0.45, -size.Y * 0.25, size.Z * 0.25)).Position
		local a = anchorAt(pos)
		local pe = emitter(a, {
			Texture = SPARK_TEX,
			Color = ColorSequence.new(Color3.fromRGB(255, 220, 140), Color3.fromRGB(255, 140, 40)),
			LightEmission = 1,
			Size = NumberSequence.new(0.35, 0),
			Lifetime = NumberRange.new(0.25, 0.5),
			Speed = NumberRange.new(8, 14),
			SpreadAngle = Vector2.new(70, 70),
			Acceleration = Vector3.new(0, -60, 0),
			Rate = if low then 18 else 45,
		})
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < seconds do
				sound(a, CLANK, 0.5, 0.55 + math.random() * 0.25)
				task.wait(0.45 + math.random() * 0.3)
			end
			pe.Enabled = false
			task.wait(0.6)
			a:Destroy()
		end)
	end
end

-- payload = { stage = "start" | "done", car = Model, lift = Model?, onLift = bool, seconds }
function Fx.repair(payload: any)
	if payload.stage ~= "start" then
		return
	end
	local car = payload.car
	if typeof(car) ~= "Instance" or not car:IsA("Model") then
		return
	end
	if running[car] then
		return
	end
	running[car] = true
	local onLift = payload.onLift == true
	local lift = liftFor(if onLift then "display" else "drivein")
	local height = (lift and lift:GetAttribute("LiftHeight")) or 5.2
	local seconds = tonumber(payload.seconds) or GS.REPAIR.seconds
	blinkLED(seconds)
	task.spawn(function()
		local liftG = group(if lift then movingParts(lift) else {})
		if onLift then
			-- the display car is already up: down, work, up again
			local carG = group({ car })
			animate(1.6, 0, -height, Enum.EasingStyle.Quad, function(a)
				local off = Vector3.new(0, a, 0)
				applyOffset(liftG, off)
				applyOffset(carG, off)
			end)
			sound(car, WHIR, 0.35, 0.6)
			sparks(car, math.max(1, seconds - 3.6))
			task.wait(math.max(0.2, seconds - 3.6))
			animate(1.8, -height, 0, Enum.EasingStyle.Quad, function(a)
				local off = Vector3.new(0, a, 0)
				applyOffset(liftG, off)
				applyOffset(carG, off)
			end)
		else
			-- the player's car: its anchored DriveBase carries every welded part
			local base = car:FindFirstChild("DriveBase")
			local baseCF = if base and base:IsA("BasePart") then base.CFrame else nil
			local carG = if baseCF then nil else group({ car })
			local function move(a: number)
				local off = Vector3.new(0, a, 0)
				applyOffset(liftG, off)
				if baseCF and base and base.Parent then
					(base :: BasePart).CFrame = baseCF + off
				elseif carG then
					applyOffset(carG, off)
				end
			end
			sound(car, WHIR, 0.35, 0.6)
			animate(2, 0, height, Enum.EasingStyle.Quad, move)
			sparks(car, math.max(1, seconds - 4))
			task.wait(math.max(0.2, seconds - 4.2))
			animate(1.8, height, 0, Enum.EasingStyle.Quad, move)
		end
		running[car] = nil
	end)
end

---------------------------------------------------------------------------------------------------
-- Wash choreography
---------------------------------------------------------------------------------------------------
local function shine(car: Model)
	local paint = GS.paintParts(car)
	for _, p in paint do
		local base = p:GetAttribute("GarageBaseRefl")
		if base == nil then
			base = p.Reflectance
			p:SetAttribute("GarageBaseRefl", base)
		end
		K.tween(p, 1.2, { Reflectance = math.min(0.6, base + 0.18) }, Enum.EasingStyle.Quad)
	end
end

-- payload = { stage, car, gantry, zone, seconds }
function Fx.wash(payload: any)
	if payload.stage ~= "start" then
		return
	end
	local car = payload.car
	local gantry = payload.gantry
	if typeof(car) ~= "Instance" or running[car] then
		return
	end
	running[car] = true
	local seconds = tonumber(payload.seconds) or GS.WASH.seconds
	task.spawn(function()
		local brushes = {}
		local travel: Vector3 = Vector3.zero
		local gG: Group? = nil
		if typeof(gantry) == "Instance" and gantry:IsA("Model") then
			local off = gantry:GetAttribute("TravelOffset")
			travel = if typeof(off) == "Vector3" then off else Vector3.zero
			gG = group({ gantry })
			for _, d in gantry:GetDescendants() do
				if d:IsA("BasePart") and CollectionService:HasTag(d, GS.Tags.Brush) then
					table.insert(brushes, d)
				end
			end
		end
		-- brush spin: each brush turns about its own long axis on top of the gantry travel
		local spin = 0
		local spinning = true
		local brushIdx: { [BasePart]: number } = {}
		if gG then
			for i, p in (gG :: Group).parts do
				brushIdx[p] = i
			end
		end
		local alpha = 0
		local function apply()
			if not gG then
				return
			end
			local g = gG :: Group
			local parts, cfs = {}, {}
			local off = travel * alpha
			for i, p in g.parts do
				if p.Parent then
					local cf = g.orig[i] + off
					if brushIdx[p] and table.find(brushes, p) then
						cf = cf * CFrame.Angles(spin, 0, 0) -- cylinders spin about their X axis
					end
					table.insert(parts, p)
					table.insert(cfs, cf)
				end
			end
			pcall(function()
				workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameNotChanged)
			end)
		end
		local hb = RunService.RenderStepped:Connect(function(dt: number)
			if spinning then
				spin += dt * 9
			end
			apply()
		end)
		-- foam
		local cf, size = bboxOf(car)
		local foamA = anchorAt(cf.Position + Vector3.new(0, size.Y * 0.5 + 1, 0), Vector3.new(size.X, 0.5, size.Z))
		local foam = emitter(foamA, {
			Texture = SMOKE_TEX,
			Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 230, 255)),
			LightEmission = 0.2,
			Transparency = NumberSequence.new(0.15, 1),
			Size = NumberSequence.new(1.2, 2.6),
			Lifetime = NumberRange.new(0.8, 1.4),
			Speed = NumberRange.new(1, 3),
			SpreadAngle = Vector2.new(180, 30),
			Acceleration = Vector3.new(0, -4, 0),
			Rate = if lowTier() then 14 else 40,
		})
		sound(foamA, WHIR, 0.4, 0.45)
		local half = math.max(0.6, seconds / 2)
		animate(half, 0, 1, Enum.EasingStyle.Sine, function(a)
			alpha = a
		end)
		animate(half, 1, 0, Enum.EasingStyle.Sine, function(a)
			alpha = a
		end)
		foam.Enabled = false
		spinning = false
		alpha = 0
		apply()
		hb:Disconnect()
		if gG then
			applyOffset(gG :: Group, Vector3.zero)
		end
		shine(car)
		task.delay(1.5, function()
			foamA:Destroy()
		end)
		running[car] = nil
	end)
end

---------------------------------------------------------------------------------------------------
-- Owned cars: dirt / shine / smoke
---------------------------------------------------------------------------------------------------
local watched: { [Model]: { conns: { RBXScriptConnection }, smoke: ParticleEmitter? } } = {}

local function refreshLook(car: Model)
	local w = watched[car]
	if not w then
		return
	end
	local base = car:GetAttribute(GS.Attr.Color)
	local dirt = car:GetAttribute(GS.Attr.Dirt)
	if typeof(base) == "Color3" then
		local c = GS.dirtColor(base, if type(dirt) == "number" then dirt else 0)
		for _, p in GS.paintParts(car) do
			p.Color = c
		end
	end
	local shineUntil = car:GetAttribute(GS.Attr.ShineUntil)
	if type(shineUntil) == "number" and shineUntil > os.time() then
		shine(car)
	end
	-- smoke under the hood
	local cond = car:GetAttribute(GS.Attr.Condition)
	local want = type(cond) == "number" and cond < GS.COND.bad and not lowTier()
	if want and not w.smoke then
		local hood = car:FindFirstChild("Hood", true) or car:FindFirstChild("DriveCollider")
		if hood and hood:IsA("BasePart") then
			w.smoke = emitter(hood, {
				Name = "GarageSmoke",
				Texture = SMOKE_TEX,
				Color = ColorSequence.new(Color3.fromRGB(70, 70, 74), Color3.fromRGB(150, 150, 154)),
				Transparency = NumberSequence.new(0.35, 1),
				Size = NumberSequence.new(0.8, 3.2),
				Lifetime = NumberRange.new(1.2, 2.2),
				Speed = NumberRange.new(1.5, 3.5),
				SpreadAngle = Vector2.new(20, 20),
				Acceleration = Vector3.new(0, 3, 0),
				Rate = 6,
			})
		end
	elseif not want and w.smoke then
		w.smoke:Destroy()
		w.smoke = nil
	end
	if w.smoke then
		w.smoke.Rate = if type(cond) == "number" and cond <= 0 then 16 else 6
	end
end

local function watch(car: Instance)
	if not car:IsA("Model") or watched[car] then
		return
	end
	if car:GetAttribute(GS.Attr.Owned) ~= true and car:GetAttribute(GS.Attr.CarId) == nil then
		return
	end
	local w = { conns = {}, smoke = nil }
	watched[car] = w
	for _, a in { GS.Attr.Dirt, GS.Attr.Condition, GS.Attr.ShineUntil, GS.Attr.Color } do
		table.insert(w.conns, car:GetAttributeChangedSignal(a):Connect(function()
			refreshLook(car)
		end))
	end
	table.insert(w.conns, car.AncestryChanged:Connect(function()
		if not car:IsDescendantOf(workspace) then
			for _, c in w.conns do
				c:Disconnect()
			end
			watched[car] = nil
		end
	end))
	task.defer(refreshLook, car)
end

---------------------------------------------------------------------------------------------------
-- Staff idle
---------------------------------------------------------------------------------------------------
local function staffIdle(rig: Instance)
	if not Anim or not rig:IsA("Model") then
		return
	end
	task.defer(function()
		pcall(Anim.play, rig, "idle", { offset = true })
	end)
end

---------------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------------
function Fx.start(ctx: any)
	K, GS, Net = ctx.K, ctx.GS, ctx.Net
	local q = ReplicatedStorage:FindFirstChild("GwangalliQuality")
	if q and q:IsA("ModuleScript") then
		local ok, res = pcall(require, q)
		if ok then
			Quality = res
		end
	end
	local a = ReplicatedStorage:FindFirstChild("GwangalliAnim")
	if a and a:IsA("ModuleScript") then
		local ok, res = pcall(require, a)
		if ok then
			Anim = res
		end
	end
	Net.on("repair", Fx.repair)
	Net.on("wash", Fx.wash)
	task.spawn(function()
		local folder = workspace:WaitForChild("GwangalliPlayerCars", 600)
		if not folder then
			return
		end
		for _, c in folder:GetChildren() do
			watch(c)
		end
		folder.ChildAdded:Connect(function(c)
			task.defer(watch, c)
		end)
	end)
	for _, r in CollectionService:GetTagged(GS.Tags.Staff) do
		staffIdle(r)
	end
	CollectionService:GetInstanceAddedSignal(GS.Tags.Staff):Connect(staffIdle)
end

return Fx
