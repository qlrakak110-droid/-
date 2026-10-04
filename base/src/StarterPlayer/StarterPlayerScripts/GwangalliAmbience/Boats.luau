-- GwangalliAmbience/Boats (client): life on the bay.
--
-- 1. Cruising boats (client-only parts, GwangalliSeaData.routes): two 민락항 fishing boats that leave
--    the harbour through the breakwater entrance, run out under the main span of 광안대교 and come
--    back; the harbour tour boat (유람선) circling the bay with colour-cycling LED strips at night; a
--    sailing yacht heeling to the breeze (day); the leports jet boat with its rooster tail (10-18 h);
--    SUP paddlers and a kayak in the SUP zone (day). Closed Catmull-Rom loops, constant arc-length
--    speed (slow inside the harbour), V wakes / prop wash / bow wave that fade with speed, swell
--    heave / pitch / roll, navigation lights (red port, green starboard, white masthead) and the
--    fishing lamps (집어등) glowing at night. Far boats update rarely; beyond ~5000 studs they are
--    unparented. A boat out of service (night / hours) only appears or disappears while it is far
--    from the camera, so nothing pops in view.
-- 2. SeaBob: anchored / moored props of the coast module (tag SeaBob: boats, the swim-zone buoy
--    line, SUP boards on the water, the leports boats) ride the swell near the camera: heave and
--    a little pitch / roll about BobPivot, phased by a travelling swell (waves come in from the
--    open sea), restored exactly when they leave the radius or stream out.

local Boats = {}

local TIERS = {
	low = { hz = 6, max = 3, bobRadius = 160, bobMax = 12, bobHz = 5 },
	saver = { hz = 4, max = 2, bobRadius = 110, bobMax = 6, bobHz = 3 }, -- weak phones (GwangalliQuality saver)
	mid = { hz = 15, max = 6, bobRadius = 280, bobMax = 34, bobHz = 12 },
	high = { hz = 20, max = 8, bobRadius = 380, bobMax = 60, bobHz = 15 },
}
local PRIORITY = { "tour", "fishingA", "yacht", "fishingB", "jet", "sup1", "kayak", "sup3" }
local MOTION = {
	fishing = { heave = 0.35, pitch = 1.3, roll = 2.2 },
	tour = { heave = 0.22, pitch = 0.4, roll = 0.7 },
	yacht = { heave = 0.3, pitch = 1.0, roll = 1.4, heel = 7 },
	jet = { heave = 0.14, pitch = 0.8, roll = 1.2, trim = 4 },
	sup = { heave = 0.1, pitch = 1.2, roll = 2.4 },
	kayak = { heave = 0.1, pitch = 1.2, roll = 2.8 },
}
local OPEN_L = 367 -- deep-water wavelength of an ~8.4 s swell (110 m), studs

local function kindOf(name: string): string
	if string.sub(name, 1, 7) == "fishing" then
		return "fishing"
	elseif string.sub(name, 1, 3) == "sup" then
		return "sup"
	end
	return name
end

-- Closed uniform Catmull-Rom through `pts` sampled into an arc-length table.
local function buildSpline(pts: { Vector3 }): ({ Vector3 }, { number })
	local n = #pts
	local samples, cum = {}, {}
	local total = 0
	local last: Vector3? = nil
	local STEPS = 18
	for i = 1, n do
		local p0 = pts[(i - 2) % n + 1]
		local p1 = pts[i]
		local p2 = pts[i % n + 1]
		local p3 = pts[(i + 1) % n + 1]
		for k = 0, STEPS - 1 do
			local t = k / STEPS
			local t2, t3 = t * t, t * t * t
			local p = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
			p = Vector3.new(p.X, 0, p.Z)
			if last then
				total += (p - last).Magnitude
			end
			table.insert(samples, p)
			table.insert(cum, total)
			last = p
		end
	end
	-- close the loop
	total += (samples[1] - samples[#samples]).Magnitude
	table.insert(samples, samples[1])
	table.insert(cum, total)
	return samples, cum
end

function Boats.start(Env: any)
	local Models = require(script.Parent:WaitForChild("BoatModels")).new(Env)
	local cfg = Env.pick(TIERS)
	Env.onTier(function()
		cfg = Env.pick(TIERS)
	end)
	local root = Env.sub("Boats")

	-----------------------------------------------------------------------------------------------
	-- 1. Cruising boats
	-----------------------------------------------------------------------------------------------
	type Boat = {
		name: string,
		kind: string,
		route: any,
		samples: { Vector3 },
		cum: { number },
		total: number,
		s: number,
		cursor: number,
		speed: number,
		v: number,
		motion: any,
		phase: number,
		model: Folder?,
		rec: any,
		shown: boolean,
		tick: number,
		pos: Vector3,
		wakeF: number,
		inService: boolean,
		seed: number,
	}
	local boats: { Boat } = {}
	local routes = Env.D.routes
	if type(routes) == "table" then
		for idx, name in PRIORITY do
			local r = routes[name]
			if type(r) == "table" and type(r.points) == "table" and #r.points >= 3 then
				local samples, cum = buildSpline(r.points)
				local total = cum[#cum]
				local speed = tonumber(r.speed) or 10
				-- start where the loop would be if it had run since the server epoch
				local s = (Env.now() * speed + Env.hash(idx, 2.2) * total) % total
				table.insert(boats, {
					name = name,
					kind = kindOf(name),
					route = r,
					samples = samples,
					cum = cum,
					total = total,
					s = s,
					cursor = 1,
					speed = speed,
					v = speed,
					motion = MOTION[kindOf(name)] or MOTION.fishing,
					phase = Env.hash(idx, 5.5) * 20,
					model = nil,
					rec = nil,
					shown = false,
					tick = 0,
					pos = samples[1],
					wakeF = -1,
					inService = true,
					seed = idx * 101,
				})
			end
		end
	end

	local function sampleAt(b: Boat, s: number): (Vector3, Vector3)
		local cum, samples = b.cum, b.samples
		local n = #cum
		local i = b.cursor
		if cum[i] > s then
			i = 1
		end
		while i < n - 1 and cum[i + 1] < s do
			i += 1
		end
		b.cursor = i
		local a, c = cum[i], cum[i + 1]
		local f = if c > a then (s - a) / (c - a) else 0
		local p = samples[i]:Lerp(samples[i + 1], f)
		local d = samples[i + 1] - samples[i]
		if d.Magnitude < 1e-3 then
			d = Vector3.new(0, 0, -1)
		end
		return p, d.Unit
	end

	local function inService(b: Boat): boolean
		local r = b.route
		local night = Env.isNight()
		if night and r.night == false then
			return false
		end
		if not night and r.day == false then
			return false
		end
		if type(r.hours) == "table" and #r.hours == 2 then
			return Env.hourIn(r.hours[1], r.hours[2])
		end
		return true
	end

	local nightNow = Env.isNight()
	local function applyLights(b: Boat)
		if not b.rec then
			return
		end
		for _, l in b.rec.lights do
			l.part.Material = if nightNow then Enum.Material.Neon else Enum.Material.SmoothPlastic
			l.part.Color = if nightNow then l.night else l.day
		end
		for _, led in b.rec.leds do
			led.Material = if nightNow then Enum.Material.Neon else Enum.Material.SmoothPlastic
			if not nightNow then
				led.Color = Color3.fromRGB(200, 204, 206)
			end
		end
	end

	local function ensureModel(b: Boat)
		if b.model then
			return
		end
		local f = Instance.new("Folder")
		f.Name = b.name
		local rec
		if b.kind == "fishing" then
			rec = if b.name == "fishingB" then Models.fishing(f, Color3.fromRGB(232, 236, 238), Color3.fromRGB(190, 40, 40)) else Models.fishing(f)
		elseif b.kind == "yacht" then
			rec = Models.yacht(f)
		elseif b.kind == "tour" then
			rec = Models.tour(f)
		elseif b.kind == "jet" then
			rec = Models.jet(f)
		elseif b.kind == "kayak" then
			rec = Models.kayak(f, b.seed)
		else
			rec = Models.sup(f, b.seed)
		end
		b.model = f
		b.rec = rec
		b.wakeF = -1
		applyLights(b)
	end

	local function setShown(b: Boat, on: boolean)
		if on == b.shown then
			return
		end
		b.shown = on
		if on then
			ensureModel(b)
			;(b.model :: Folder).Parent = root
		elseif b.model then
			b.model.Parent = nil
		end
	end

	local partsOut: { BasePart } = {}
	local cfOut: { CFrame } = {}
	local trCache: { [any]: number } = {}

	local function pose(b: Boat, now: number, pos: Vector3, fwd: Vector3)
		local rec = b.rec
		if not rec then
			return
		end
		local m = b.motion
		local t = now + b.phase
		local heave = m.heave * math.sin(t * 0.75) + m.heave * 0.4 * math.sin(t * 1.9 + 1.1)
		local pitch = math.rad(m.pitch) * math.sin(t * 0.63 + 0.4) + math.rad(m.trim or 0) * math.clamp(b.v / b.speed, 0, 1)
		local roll = math.rad(m.roll) * math.sin(t * 0.52 + 2.1)
		local base = CFrame.lookAt(pos, pos + fwd)
		if m.heel then
			local side = Env.windDir:Dot(base.RightVector)
			roll += -math.rad(m.heel) * math.clamp(side * 1.6, -1, 1) * math.clamp(Env.windSpeed / 10, 0.3, 1.3)
		end
		local cf = base * CFrame.new(0, heave, 0) * CFrame.Angles(pitch, 0, roll)
		local pad = rec.paddle
		for i, p in rec.parts do
			local off = rec.offsets[i]
			if pad and i == pad.index then
				if pad.kind == "sup" then
					local cyc = (t / 1.5) % 1
					local strokeN = math.floor(t / 1.5)
					local side = if math.floor(strokeN / 3) % 2 == 0 then 1 else -1
					local z, y
					if cyc < 0.6 then
						z, y = -1.8 + 3.6 * (cyc / 0.6), 3.0
					else
						z, y = 1.8 - 3.6 * ((cyc - 0.6) / 0.4), 3.9
					end
					off = CFrame.new(side * 1.25, y, z) * CFrame.Angles(-0.25 + 0.5 * (z + 1.8) / 3.6, 0, side * 0.14)
				else
					local a = math.sin(t * 4.2)
					off = CFrame.new(0, 2.2, -0.3) * CFrame.Angles(0, 0.28 * a, 0.5 * a)
				end
			end
			table.insert(partsOut, p)
			table.insert(cfOut, cf * off)
		end
		-- wakes fade with speed
		local f = math.clamp(b.v / b.speed, 0, 1)
		if math.abs(f - b.wakeF) > 0.04 then
			b.wakeF = f
			for _, w in rec.wakes do
				Env.setNum(w.part, "Transparency", 1 - (1 - w.base) * f, trCache, 0.02)
			end
		end
	end

	local ledHue = 0
	local ledAcc = 0
	local ACTIVE_CENTER = Vector3.new(0, 0, -1600)

	Env.every("boats", function()
		return cfg.hz
	end, function(now: number, dt: number)
		dt = math.min(dt, 1)
		local cam = Env.focus()
		local bayNear = (Vector3.new(cam.X, 0, cam.Z) - ACTIVE_CENTER).Magnitude < 6200 and cam.Y < 1200
		local n = nightNow
		nightNow = Env.isNight()
		for i, b in boats do
			-- advance (always, so every boat keeps its place on the loop)
			local v = b.speed
			local r = b.route
			if typeof(r.slowCenter) == "Vector3" then
				local d = (b.pos - r.slowCenter).Magnitude
				local rad = tonumber(r.slowRadius) or 300
				if d < rad then
					local k = math.clamp((d - rad * 0.45) / (rad * 0.55), 0, 1)
					v = (tonumber(r.slowSpeed) or 5) + (b.speed - (tonumber(r.slowSpeed) or 5)) * k
				end
			end
			b.v = b.v + (v - b.v) * math.min(1, dt * 0.8)
			b.s = (b.s + b.v * dt) % b.total
			local pos, fwd = sampleAt(b, b.s)
			b.pos = pos
			local d = (pos - cam).Magnitude
			-- service window changes only while far from the camera
			local want = inService(b)
			if want ~= b.inService and d > 900 then
				b.inService = want
			end
			local show = bayNear and b.inService and i <= cfg.max and d < 5200
			setShown(b, show)
			if show then
				if nightNow ~= n then
					applyLights(b)
				end
				b.tick += 1
				local every = if d > 2400 then 6 elseif d > 1000 then 3 elseif d > 450 then 2 else 1
				if b.tick >= every and not Env.behind(pos, 40) then
					b.tick = 0
					pose(b, now, pos, fwd)
				end
			end
		end
		-- LED strips: slow colour cycle at night (2 Hz)
		ledAcc += dt
		if nightNow and ledAcc > 0.5 then
			ledAcc = 0
			ledHue = (ledHue + 0.02) % 1
			for _, b in boats do
				if b.shown and b.rec then
					for k, led in b.rec.leds do
						led.Color = Color3.fromHSV((ledHue + k * 0.18) % 1, 0.75, 1)
					end
				end
			end
		end
		Env.move(partsOut, cfOut)
		table.clear(partsOut)
		table.clear(cfOut)
	end)

	-----------------------------------------------------------------------------------------------
	-- 2. SeaBob (static coast props riding the swell)
	-----------------------------------------------------------------------------------------------
	type BobRec = {
		inst: Instance,
		parts: { BasePart },
		base: { [BasePart]: CFrame },
		rel: { [BasePart]: CFrame }, -- base relative to the pivot
		pivot: Vector3,
		amp: number,
		roll: number,
		phase: number,
		active: boolean,
		conns: { RBXScriptConnection },
	}
	local bobs: { [Instance]: BobRec } = {}
	local activeBobs: { BobRec } = {}

	local function restore(rec: BobRec)
		local ps, cs = {}, {}
		for _, p in rec.parts do
			local b = rec.base[p]
			if b and p.Parent then
				table.insert(ps, p)
				table.insert(cs, b)
			end
		end
		Env.move(ps, cs)
	end

	local function addPart(rec: BobRec, p: Instance)
		if p:IsA("BasePart") and not rec.base[p] then
			rec.base[p] = p.CFrame
			rec.rel[p] = CFrame.new(-rec.pivot) * p.CFrame
			table.insert(rec.parts, p)
		end
	end

	Env.watchTag(Env.TAG.Bob, function(inst)
		if bobs[inst] then
			return
		end
		local pv = inst:GetAttribute("BobPivot")
		local pivot: Vector3
		if typeof(pv) == "Vector3" then
			pivot = pv
		elseif inst:IsA("BasePart") then
			pivot = inst.Position
		elseif inst:IsA("Model") then
			pivot = inst:GetPivot().Position
		else
			return
		end
		local rec: BobRec = {
			inst = inst,
			parts = {},
			base = {},
			rel = {},
			pivot = pivot,
			amp = tonumber(inst:GetAttribute("BobAmp")) or 0.3,
			roll = math.rad(tonumber(inst:GetAttribute("BobRoll")) or 2),
			phase = Env.hash(pivot.X, pivot.Z) * 6.28,
			active = false,
			conns = {},
		}
		if inst:IsA("BasePart") then
			addPart(rec, inst)
		else
			for _, d in inst:GetDescendants() do
				addPart(rec, d)
			end
			table.insert(rec.conns, inst.DescendantAdded:Connect(function(d)
				-- a part streaming in arrives at its server CFrame: that is its base
				addPart(rec, d)
			end))
			table.insert(rec.conns, inst.DescendantRemoving:Connect(function(d)
				if rec.base[d :: any] then
					rec.base[d :: any] = nil
					rec.rel[d :: any] = nil
					local k = table.find(rec.parts, d :: any)
					if k then
						table.remove(rec.parts, k)
					end
				end
			end))
		end
		bobs[inst] = rec
	end, function(inst)
		local rec = bobs[inst]
		if rec then
			bobs[inst] = nil
			for _, c in rec.conns do
				c:Disconnect()
			end
			if rec.active then
				rec.active = false
				local k = table.find(activeBobs, rec)
				if k then
					table.remove(activeBobs, k)
				end
				if inst.Parent then
					restore(rec)
				end
			end
		end
	end)

	-- pick the nearest ones about once a second
	local scanAcc = 1
	local cand: { BobRec } = {}
	local dist: { [BobRec]: number } = {}
	Env.every("bob", function()
		return cfg.bobHz
	end, function(now: number, dt: number)
		scanAcc += dt
		if scanAcc >= 1 then
			scanAcc = 0
			local cam = Env.focus()
			table.clear(cand)
			for _, rec in bobs do
				local d = (rec.pivot - cam).Magnitude
				if d < cfg.bobRadius then
					dist[rec] = d
					table.insert(cand, rec)
				end
			end
			table.sort(cand, function(a, b)
				return dist[a] < dist[b]
			end)
			local keep: { [BobRec]: boolean } = {}
			for i = 1, math.min(#cand, cfg.bobMax) do
				keep[cand[i]] = true
			end
			for i = #activeBobs, 1, -1 do
				local rec = activeBobs[i]
				if not keep[rec] then
					rec.active = false
					table.remove(activeBobs, i)
					restore(rec)
				end
			end
			for rec in keep do
				if not rec.active then
					rec.active = true
					table.insert(activeBobs, rec)
				end
			end
			table.clear(dist)
		end
		local T = Env.WAVE_T
		for _, rec in activeBobs do
			if Env.behind(rec.pivot, 12) then
				continue -- behind the camera: keeps its last pose (the phase is a function of time)
			end
			local ph = (now / T - rec.pivot.Z / OPEN_L) * math.pi * 2 + rec.phase * 0.25
			local heave = rec.amp * math.sin(ph)
			local rx = rec.roll * 0.6 * math.cos(ph)
			local rz = rec.roll * math.sin(ph * 0.7 + rec.phase)
			local off = CFrame.new(rec.pivot.X, rec.pivot.Y + heave, rec.pivot.Z) * CFrame.Angles(rx, 0, rz)
			local rel = rec.rel
			for _, p in rec.parts do
				table.insert(partsOut, p)
				table.insert(cfOut, off * rel[p])
			end
		end
		Env.move(partsOut, cfOut)
		table.clear(partsOut)
		table.clear(cfOut)
	end)
end

return Boats
