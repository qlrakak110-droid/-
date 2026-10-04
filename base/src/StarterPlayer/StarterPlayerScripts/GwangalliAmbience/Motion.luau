-- GwangalliAmbience/Motion (client): wind on the beach near the camera.
--   * SeaSway (Models: rental / personal / thatch parasols, the SUP bar wind banners; attrs
--     SwayPivot, SwayAmp): lean downwind by a gust-driven angle and rock slowly about the pivot
--     on the sand. Pole and canopy move together as one rigid body (a real parasol pole barely
--     bends, the canopy's small rocking is what reads).
--   * SeaFlag (strips of the lifeguard / swim-zone flags; attrs FlagGroup, FlagHinge, FlagIndex,
--     FlagSeg, FlagDy): each flag streams downwind from its pole as a chain of strips with a
--     travelling flutter wave that grows toward the free end and quickens with the wind speed.
-- The wind is Workspace.GlobalWind (Env.windDir / windSpeed, NightSea blends day / night breezes).
-- Only the nearest instances within the tier radius move; others keep their place-file pose
-- (restored when they leave the radius).

local Motion = {}

local TIERS = {
	low = { swayRadius = 0, swayMax = 0, flagRadius = 80, hz = 5 },
	saver = { swayRadius = 0, swayMax = 0, flagRadius = 50, hz = 3 }, -- weak phones (GwangalliQuality saver)
	mid = { swayRadius = 110, swayMax = 18, flagRadius = 140, hz = 10 },
	high = { swayRadius = 170, swayMax = 40, flagRadius = 210, hz = 15 },
}

function Motion.start(Env: any)
	local cfg = Env.pick(TIERS)
	Env.onTier(function()
		cfg = Env.pick(TIERS)
	end)

	local partsOut: { BasePart } = {}
	local cfOut: { CFrame } = {}

	-----------------------------------------------------------------------------------------------
	-- Sway
	-----------------------------------------------------------------------------------------------
	type SwayRec = { inst: Instance, parts: { BasePart }, base: { [BasePart]: CFrame }, rel: { [BasePart]: CFrame }, pivot: Vector3, amp: number, phase: number, period: number, active: boolean, conns: { RBXScriptConnection } }
	local sways: { [Instance]: SwayRec } = {}
	local activeSway: { SwayRec } = {}

	local function restore(rec: SwayRec)
		for _, p in rec.parts do
			local b = rec.base[p]
			if b then
				table.insert(partsOut, p)
				table.insert(cfOut, b)
			end
		end
	end
	local function addPart(rec: SwayRec, d: Instance)
		if d:IsA("BasePart") and not rec.base[d] then
			rec.base[d] = d.CFrame
			rec.rel[d] = CFrame.new(-rec.pivot) * d.CFrame
			table.insert(rec.parts, d)
		end
	end

	Env.watchTag(Env.TAG.Sway, function(inst)
		if sways[inst] or not inst:IsA("Model") then
			return
		end
		local pv = inst:GetAttribute("SwayPivot")
		local pivot = if typeof(pv) == "Vector3" then pv else inst:GetPivot().Position
		local rec: SwayRec = {
			inst = inst,
			parts = {},
			base = {},
			rel = {},
			pivot = pivot,
			amp = math.rad(tonumber(inst:GetAttribute("SwayAmp")) or 1.2),
			phase = Env.hash(pivot.X, pivot.Z) * 6.28,
			period = 2.6 + Env.hash(pivot.Z, pivot.X) * 1.8,
			active = false,
			conns = {},
		}
		for _, d in inst:GetDescendants() do
			addPart(rec, d)
		end
		table.insert(rec.conns, inst.DescendantAdded:Connect(function(d)
			addPart(rec, d)
		end))
		sways[inst] = rec
	end, function(inst)
		local rec = sways[inst]
		if rec then
			sways[inst] = nil
			for _, c in rec.conns do
				c:Disconnect()
			end
			local k = table.find(activeSway, rec)
			if k then
				table.remove(activeSway, k)
			end
		end
	end)

	-----------------------------------------------------------------------------------------------
	-- Flags
	-----------------------------------------------------------------------------------------------
	type Strip = { part: BasePart, hinge: Vector3, index: number, seg: number, dy: number, base: CFrame, phase: number, active: boolean }
	local strips: { [BasePart]: Strip } = {}
	local activeStrips: { Strip } = {}
	Env.watchTag(Env.TAG.Flag, function(inst)
		if not inst:IsA("BasePart") or strips[inst] then
			return
		end
		local hinge = inst:GetAttribute("FlagHinge")
		if typeof(hinge) ~= "Vector3" then
			return
		end
		strips[inst] = {
			part = inst,
			hinge = hinge,
			index = tonumber(inst:GetAttribute("FlagIndex")) or 0,
			seg = tonumber(inst:GetAttribute("FlagSeg")) or 1,
			dy = tonumber(inst:GetAttribute("FlagDy")) or 0,
			base = inst.CFrame,
			phase = Env.hash(hinge.X, hinge.Z) * 6.28,
			active = false,
		}
	end, function(inst)
		local s = strips[inst :: BasePart]
		if s then
			strips[inst :: BasePart] = nil
			local k = table.find(activeStrips, s)
			if k then
				table.remove(activeStrips, k)
			end
		end
	end)

	-----------------------------------------------------------------------------------------------
	-- Update
	-----------------------------------------------------------------------------------------------
	local scanAcc = 1
	local cand: { SwayRec } = {}
	local dist: { [any]: number } = {}
	Env.every("motion", function()
		return cfg.hz
	end, function(now: number, dt: number)
		local cam = Env.focus()
		scanAcc += dt
		if scanAcc >= 0.8 then
			scanAcc = 0
			-- sway set: nearest within the radius
			table.clear(cand)
			for _, rec in sways do
				local d = (rec.pivot - cam).Magnitude
				if d < cfg.swayRadius then
					dist[rec] = d
					table.insert(cand, rec)
				end
			end
			table.sort(cand, function(a, b)
				return dist[a] < dist[b]
			end)
			local keep: { [SwayRec]: boolean } = {}
			for i = 1, math.min(#cand, cfg.swayMax) do
				keep[cand[i]] = true
			end
			for i = #activeSway, 1, -1 do
				local rec = activeSway[i]
				if not keep[rec] then
					rec.active = false
					table.remove(activeSway, i)
					restore(rec)
				end
			end
			for rec in keep do
				if not rec.active then
					rec.active = true
					table.insert(activeSway, rec)
				end
			end
			table.clear(dist)
			-- flags within the radius
			for _, s in strips do
				local want = (s.hinge - cam).Magnitude < cfg.flagRadius
				if want ~= s.active then
					s.active = want
					if want then
						table.insert(activeStrips, s)
					else
						local k = table.find(activeStrips, s)
						if k then
							table.remove(activeStrips, k)
						end
						table.insert(partsOut, s.part)
						table.insert(cfOut, s.base)
					end
				end
			end
		end

		local wd = Env.windDir
		local ws = Env.windSpeed
		local axis = Vector3.new(0, 1, 0):Cross(wd) -- rotating about this leans the top downwind
		if axis.Magnitude < 1e-3 then
			axis = Vector3.xAxis
		else
			axis = axis.Unit
		end
		local windK = math.clamp(ws / 10, 0.25, 1.8)
		for _, rec in activeSway do
			if Env.behind(rec.pivot, 8) then
				continue
			end
			local g = Env.gust(now, rec.pivot.X, rec.pivot.Z)
			local lean = rec.amp * windK * (0.45 * g + 0.55 * math.sin(now * 6.283 / rec.period + rec.phase) * g)
			local side = rec.amp * 0.35 * windK * math.sin(now * 6.283 / (rec.period * 1.37) + rec.phase * 2)
			local off = CFrame.new(rec.pivot) * CFrame.fromAxisAngle(axis, lean) * CFrame.fromAxisAngle(wd, side)
			local rel = rec.rel
			for _, p in rec.parts do
				table.insert(partsOut, p)
				table.insert(cfOut, off * rel[p])
			end
		end

		-- flags: yaw of strip j = wind heading + flutter(j); strip i sits at the end of strips 0..i-1
		local heading = math.atan2(wd.X, wd.Z) -- yaw of the downwind direction (around +Y, from +Z)
		local freq = 1.2 + 0.28 * ws -- flutter frequency (rad/s scale)
		local ampBase = math.clamp(0.55 - 0.02 * ws, 0.18, 0.55) -- stiff wind = flatter flag, bigger ripple speed
		local droop = math.clamp(0.55 - 0.05 * ws, 0.04, 0.5) -- light wind: the flag hangs down a bit
		for _, s in activeStrips do
			if Env.behind(s.hinge, 6) then
				continue -- behind the camera: the flutter is a function of time, nothing to keep
			end
			local pos = s.hinge
			local yaw = heading
			for j = 0, s.index do
				local a = ampBase * (0.3 + 0.35 * j)
				yaw = heading + a * math.sin(now * freq * 3 - j * 1.15 + s.phase)
				local dir = Vector3.new(math.sin(yaw), -droop * (0.4 + 0.3 * j), math.cos(yaw)).Unit
				if j < s.index then
					pos += dir * s.seg
				else
					local c = pos + dir * (s.seg * 0.5) + Vector3.new(0, s.dy, 0)
					table.insert(partsOut, s.part)
					table.insert(cfOut, CFrame.lookAt(c, c + dir))
				end
			end
		end
		Env.move(partsOut, cfOut)
		table.clear(partsOut)
		table.clear(cfOut)
	end)
end

return Motion
