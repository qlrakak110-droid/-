-- GwangalliAmbience/Birds (client): black-tailed gulls (괭이갈매기) near the camera.
--
-- Zones: the beach around the camera (gulls circle over the swash zone and land on the wet sand),
-- 민락항 (the harbour basin; perches on the wave wall, the lighthouse caps, the quay edge) and the fish
-- market quay (GwangalliSeaData.gulls). Each gull is 8 small parts (body, head, beak, tail, two-piece
-- wings) posed with one BulkMoveTo per update: it soars in banked circles with bursts of flapping,
-- glides down to a perch, flares and lands, stands with small head bobs and turns, then takes off
-- with fast wingbeats. Fewer gulls fly at night. Zones only hold gulls while the camera is near;
-- a gull is only moved to another zone while it is out of sight (> 160 studs from the camera).
-- Env.gulls = { center = Vector3?, count = n } feeds the gull sound position (Soundscape).

local Birds = {}

local TIERS = {
	low = { count = 3, hz = 8 },
	saver = { count = 2, hz = 6 }, -- weak phones (GwangalliQuality saver)
	mid = { count = 6, hz = 18 },
	high = { count = 9, hz = 24 },
}
local rgb = Color3.fromRGB
local WHITE = rgb(238, 240, 238)
local GREY = rgb(160, 168, 178)
local TIP = rgb(52, 54, 58)
local BEAK = rgb(232, 190, 56)

function Birds.start(Env: any)
	local cfg = Env.pick(TIERS)
	Env.onTier(function()
		cfg = Env.pick(TIERS)
	end)
	local root = Env.sub("Gulls")
	Env.gulls = { center = nil, count = 0 }
	local rng = Random.new()

	-- zones -----------------------------------------------------------------------------------------
	type Zone = { name: string, center: Vector3, radius: number, height: number, perches: { Vector3 }, dynamic: boolean, active: boolean, share: number }
	local zones: { Zone } = {}
	local beach: Zone = { name = "beach", center = Vector3.zero, radius = 70, height = 22, perches = {}, dynamic = true, active = false, share = 1 }
	table.insert(zones, beach)
	local gd = Env.D.gulls
	if type(gd) == "table" then
		for _, key in { "harbour", "market" } do
			local z = gd[key]
			if type(z) == "table" and typeof(z.center) == "Vector3" then
				local perches = {}
				for _, p in (if type(z.perches) == "table" then z.perches else {}) do
					if typeof(p) == "Vector3" then
						table.insert(perches, p)
					end
				end
				table.insert(zones, {
					name = key,
					center = z.center,
					radius = tonumber(z.radius) or 150,
					height = tonumber(z.height) or 24,
					perches = perches,
					dynamic = false,
					active = false,
					share = if key == "harbour" then 0.65 else 0.35,
				})
			end
		end
	end

	-- a sand perch near the camera on the beach (wet sand just above the water's edge)
	local function beachPerch(cam: Vector3): Vector3
		local x = math.clamp(cam.X + rng:NextNumber(-70, 70), Env.beachX0 + 20, Env.beachX1 - 20)
		local _, n = Env.shoreFrame(x)
		local p = Vector3.new(x, 0, Env.edgeZ(x)) + n * rng:NextNumber(3, 24)
		local y = Env.sandHeight(p.X, p.Z)
		y = math.max(Env.groundY(p.X, p.Z, y), y + 0.1)
		return Vector3.new(p.X, y, p.Z)
	end

	-- gulls -----------------------------------------------------------------------------------------
	type Gull = {
		parts: { BasePart },
		zone: Zone?,
		state: string,
		stateT: number,
		pos: Vector3,
		yaw: number,
		pitch: number,
		bank: number,
		flap: number,
		flapRate: number,
		flapUntil: number,
		center: Vector3,
		radius: number,
		dir: number,
		theta: number,
		alt: number,
		speed: number,
		target: Vector3?,
		nextTurn: number,
		tick: number,
		shown: boolean,
		phase: number,
	}
	local gulls: { Gull } = {}

	local function makeGull(): Gull
		local f = root
		local parts = {
			Env.part(f, Vector3.new(0.75, 0.7, 2.0), WHITE, Enum.Material.SmoothPlastic, 0, "GullBody", "Ellipsoid"),
			Env.part(f, Vector3.new(0.56, 0.56, 0.56), WHITE, Enum.Material.SmoothPlastic, 0, "GullHead", "Ball"),
			Env.part(f, Vector3.new(0.12, 0.1, 0.42), BEAK, Enum.Material.SmoothPlastic, 0, "GullBeak"),
			Env.part(f, Vector3.new(0.7, 0.1, 0.75), WHITE, Enum.Material.SmoothPlastic, 0, "GullTail", "Wedge"),
			Env.part(f, Vector3.new(1.35, 0.08, 0.8), GREY, Enum.Material.SmoothPlastic, 0, "GullWingL"),
			Env.part(f, Vector3.new(1.35, 0.08, 0.8), GREY, Enum.Material.SmoothPlastic, 0, "GullWingR"),
			Env.part(f, Vector3.new(1.25, 0.06, 0.58), TIP, Enum.Material.SmoothPlastic, 0, "GullTipL"),
			Env.part(f, Vector3.new(1.25, 0.06, 0.58), TIP, Enum.Material.SmoothPlastic, 0, "GullTipR"),
		}
		return {
			parts = parts, zone = nil, state = "soar", stateT = 0, pos = Vector3.zero, yaw = 0, pitch = 0, bank = 0,
			flap = 0.2, flapRate = 3.2, flapUntil = 0, center = Vector3.zero, radius = 40, dir = 1, theta = 0,
			alt = 20, speed = 20, target = nil, nextTurn = 0, tick = 0, shown = false, phase = rng:NextNumber(0, 10),
		}
	end

	local function startSoar(g: Gull, z: Zone, now: number, fromPos: Vector3?)
		g.zone = z
		g.state = "soar"
		g.stateT = now + rng:NextNumber(8, 22)
		g.radius = rng:NextNumber(22, math.max(30, z.radius * 0.6))
		g.dir = if rng:NextNumber() < 0.5 then 1 else -1
		g.alt = z.height + rng:NextNumber(-8, 12)
		local c = z.center
		if z.dynamic then
			c = z.center
		end
		g.center = c + Vector3.new(rng:NextNumber(-z.radius, z.radius) * 0.5, 0, rng:NextNumber(-z.radius, z.radius) * 0.5)
		if fromPos then
			local d = fromPos - g.center
			g.theta = math.atan2(d.Z, d.X)
		else
			g.theta = rng:NextNumber(0, math.pi * 2)
		end
		g.speed = rng:NextNumber(17, 24)
	end

	local function perchFor(z: Zone, cam: Vector3): Vector3?
		if z.dynamic then
			return beachPerch(cam)
		end
		if #z.perches == 0 then
			return nil
		end
		return z.perches[rng:NextInteger(1, #z.perches)]
	end

	-- wing / body pose -> part CFrames
	local cfOut: { CFrame } = {}
	local partsOut: { BasePart } = {}
	-- fixed offsets (built once)
	local HEAD = CFrame.new(0, 0.24, -1.02)
	local BEAK = CFrame.new(0, 0.2, -1.44)
	local TAIL = CFrame.new(0, 0.04, 1.24) * CFrame.Angles(0, math.pi, 0)
	local FOLD = {
		[-1] = CFrame.new(-0.3, 0.14, -0.1) * CFrame.Angles(0, 1.47, -0.08),
		[1] = CFrame.new(0.3, 0.14, -0.1) * CFrame.Angles(0, -1.47, 0.08),
	}
	local FOLD_IN = { [-1] = CFrame.new(-0.64, 0, 0), [1] = CFrame.new(0.64, 0, 0) }
	local FOLD_OUT = { [-1] = CFrame.new(-1.2, 0.05, 0.02), [1] = CFrame.new(1.2, 0.05, 0.02) }
	local SHOULDER = { [-1] = CFrame.new(-0.3, 0.12, -0.12), [1] = CFrame.new(0.3, 0.12, -0.12) }
	local INNER = { [-1] = CFrame.new(-0.675, 0, 0), [1] = CFrame.new(0.675, 0, 0) }
	local ELBOW = { [-1] = CFrame.new(-1.35, 0, 0), [1] = CFrame.new(1.35, 0, 0) }
	local OUTER = { [-1] = CFrame.new(-0.6, 0, 0.1), [1] = CFrame.new(0.6, 0, 0.1) }
	local function place(g: Gull, folded: boolean)
		local body = CFrame.new(g.pos) * CFrame.Angles(0, g.yaw, 0) * CFrame.Angles(g.pitch, 0, g.bank)
		local p = g.parts
		table.insert(partsOut, p[1])
		table.insert(cfOut, body)
		table.insert(partsOut, p[2])
		table.insert(cfOut, body * HEAD)
		table.insert(partsOut, p[3])
		table.insert(cfOut, body * BEAK)
		table.insert(partsOut, p[4])
		table.insert(cfOut, body * TAIL)
		-- parts 5/6 = inner wing L/R, 7/8 = wingtip L/R
		for side = -1, 1, 2 do
			local iw = if side < 0 then 5 else 6
			if folded then
				local sh = body * FOLD[side]
				table.insert(partsOut, p[iw])
				table.insert(cfOut, sh * FOLD_IN[side])
				table.insert(partsOut, p[iw + 2])
				table.insert(cfOut, sh * FOLD_OUT[side])
			else
				local a = g.flap
				local sh = body * SHOULDER[side] * CFrame.Angles(0, 0, side * a)
				table.insert(partsOut, p[iw])
				table.insert(cfOut, sh * INNER[side])
				local elbow = sh * ELBOW[side] * CFrame.Angles(0, -side * 0.12, side * a * 0.55)
				table.insert(partsOut, p[iw + 2])
				table.insert(cfOut, elbow * OUTER[side])
			end
		end
	end

	local function setShown(g: Gull, on: boolean)
		if g.shown == on then
			return
		end
		g.shown = on
		if not on then
			for _, pt in g.parts do
				table.insert(partsOut, pt)
				table.insert(cfOut, Env.HIDDEN_CF)
			end
		end
	end

	local function stepGull(g: Gull, now: number, dt: number, cam: Vector3)
		local z = g.zone :: Zone
		local t = now + g.phase
		if g.state == "soar" then
			local w = g.speed / g.radius
			g.theta += g.dir * w * dt
			local y = z.center.Y + g.alt + 3 * math.sin(t * 0.27)
			local c = g.center
			local np = Vector3.new(c.X + math.cos(g.theta) * g.radius, y, c.Z + math.sin(g.theta) * g.radius)
			local d = np - g.pos
			if d.Magnitude > 0.01 then
				local desiredYaw = math.atan2(-d.X, -d.Z)
				local dy = (desiredYaw - g.yaw + math.pi) % (2 * math.pi) - math.pi
				g.yaw += dy * math.min(1, dt * 4)
				g.pitch = math.clamp(math.atan2(d.Y, math.sqrt(d.X * d.X + d.Z * d.Z)), -0.4, 0.4)
			end
			-- smooth approach to the circle after a zone change
			g.pos = g.pos:Lerp(np, math.min(1, dt * 2.5))
			g.bank = g.bank + ((-g.dir) * 0.38 - g.bank) * math.min(1, dt * 2)
			if now < g.flapUntil then
				g.flap = 0.15 + 0.62 * math.sin(t * g.flapRate * math.pi * 2)
			else
				g.flap = g.flap + (0.16 - g.flap) * math.min(1, dt * 6)
				if rng:NextNumber() < dt * 0.18 then
					g.flapUntil = now + rng:NextNumber(0.8, 2.2)
					g.flapRate = rng:NextNumber(2.8, 3.6)
				end
			end
			if now > g.stateT then
				local perch = if rng:NextNumber() < 0.45 then perchFor(z, cam) else nil
				if perch then
					g.state = "approach"
					g.target = perch
					g.stateT = now + 25
				else
					startSoar(g, z, now, g.pos)
				end
			end
		elseif g.state == "approach" then
			local target = (g.target :: Vector3) + Vector3.new(0, 0.45, 0)
			local d = target - g.pos
			local dist = d.Magnitude
			local v = math.clamp(dist * 0.9, 4, 20)
			if dist < 0.8 or now > g.stateT then
				g.pos = target
				g.state = "perch"
				g.stateT = now + rng:NextNumber(6, 18)
				g.nextTurn = now + rng:NextNumber(2, 5)
				g.pitch, g.bank = 0.12, 0
			else
				local step = d.Unit * math.min(dist, v * dt)
				g.pos += step
				local desiredYaw = math.atan2(-d.X, -d.Z)
				local dy = (desiredYaw - g.yaw + math.pi) % (2 * math.pi) - math.pi
				g.yaw += dy * math.min(1, dt * 3)
				g.bank = g.bank * (1 - math.min(1, dt * 3))
				if dist < 10 then
					-- flare: nose up, big fast wingbeats
					g.pitch = 0.45
					g.flap = 0.35 + 0.75 * math.sin(t * 4.5 * math.pi * 2)
				else
					g.pitch = math.clamp(math.atan2(d.Y, math.sqrt(d.X * d.X + d.Z * d.Z)), -0.35, 0.2)
					g.flap = 0.1
				end
			end
		elseif g.state == "perch" then
			-- small head bobs and turns
			g.pitch = 0.12 + 0.05 * math.sin(t * 2.3)
			if now > g.nextTurn then
				g.nextTurn = now + rng:NextNumber(2.5, 6)
				g.yaw += rng:NextNumber(-0.9, 0.9)
			end
			if now > g.stateT then
				g.state = "takeoff"
				g.stateT = now + 1.6
			end
		elseif g.state == "takeoff" then
			local fwd = Vector3.new(-math.sin(g.yaw), 0, -math.cos(g.yaw))
			g.pos += (fwd * 9 + Vector3.new(0, 7, 0)) * dt
			g.pitch = -0.35
			g.flap = 0.2 + 0.8 * math.sin(t * 4.2 * math.pi * 2)
			if now > g.stateT then
				startSoar(g, z, now, g.pos)
				g.flapUntil = now + 1.5
			end
		end
	end

	-- zone management -----------------------------------------------------------------------------
	local function refreshZones(cam: Vector3)
		-- beach: follows the camera along the waterline
		local inBeach = cam.X > Env.beachX0 - 60 and cam.X < Env.beachX1 + 60
		local bx = math.clamp(cam.X, Env.beachX0 + 40, Env.beachX1 - 40)
		local _, n = Env.shoreFrame(bx)
		local edge = Vector3.new(bx, 0, Env.edgeZ(bx))
		beach.center = edge - n * 22
		beach.active = inBeach and math.abs(cam.Z - edge.Z) < 420 and cam.Y < 160
		for _, z in zones do
			if not z.dynamic then
				z.active = (Vector3.new(cam.X, 0, cam.Z) - Vector3.new(z.center.X, 0, z.center.Z)).Magnitude < 420 and cam.Y < 200
			end
		end
	end

	local function pickZone(): Zone?
		-- weighted by share among active zones, harbour first
		local best, total = nil, 0
		for _, z in zones do
			if z.active then
				total += z.share
			end
		end
		if total <= 0 then
			return nil
		end
		local r = rng:NextNumber() * total
		for _, z in zones do
			if z.active then
				r -= z.share
				if r <= 0 then
					return z
				end
				best = z
			end
		end
		return best
	end

	local zoneAcc = 1
	Env.every("gulls", function()
		return cfg.hz
	end, function(now: number, dt: number)
		dt = math.min(dt, 0.5)
		local cam = Env.focus()
		zoneAcc += dt
		if zoneAcc >= 0.5 then
			zoneAcc = 0
			refreshZones(cam)
		end
		local want = cfg.count
		if Env.isNight() then
			want = math.max(1, math.floor(want * 0.35))
		end
		local anyActive = false
		for _, z in zones do
			if z.active then
				anyActive = true
			end
		end
		if not anyActive then
			want = 0
		end
		while #gulls < want do
			table.insert(gulls, makeGull())
		end
		local sx, sy, sz, cnt = 0, 0, 0, 0
		for i, g in gulls do
			local dist = (g.pos - cam).Magnitude
			if i > want then
				-- surplus: park when out of sight
				if not g.shown or dist > 160 then
					setShown(g, false)
					g.zone = nil
				end
			end
			local z = g.zone
			-- a zone that went inactive, or the beach zone that moved on with the camera (quick travel,
			-- a long walk): re-home the gull while it is out of sight
			local stale = z == nil or not z.active or (z.dynamic and (g.center - z.center).Magnitude > z.radius * 2.2)
			if i <= want and stale and (not g.shown or dist > 160) then
				local nz = pickZone()
				if nz then
					-- enter from off-screen: start on the far side of the circle
					startSoar(g, nz, now, nil)
					local c = g.center
					g.pos = Vector3.new(c.X + math.cos(g.theta) * g.radius, nz.center.Y + g.alt, c.Z + math.sin(g.theta) * g.radius)
					z = nz
				else
					setShown(g, false)
					g.zone = nil
					z = nil
				end
			end
			if z and (i <= want or g.shown) then
				stepGull(g, now, dt, cam)
				local d2 = (g.pos - cam).Magnitude
				if d2 < 420 then
					if not g.shown then
						g.shown = true
					end
					g.tick += 1
					if (d2 < 70 or g.tick >= (if d2 < 200 then 2 else 3)) and not Env.behind(g.pos, 3) then
						g.tick = 0
						place(g, g.state == "perch")
					end
					sx += g.pos.X
					sy += g.pos.Y
					sz += g.pos.Z
					cnt += 1
				else
					setShown(g, false)
				end
			end
		end
		Env.gulls.count = cnt
		Env.gulls.center = if cnt > 0 then Vector3.new(sx / cnt, sy / cnt, sz / cnt) else nil
		Env.move(partsOut, cfOut)
		table.clear(partsOut)
		table.clear(cfOut)
	end)
end

return Birds
