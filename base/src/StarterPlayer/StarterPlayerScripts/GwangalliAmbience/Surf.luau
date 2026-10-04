-- GwangalliAmbience/Surf (client): the living water's edge of 광안리해수욕장 near the camera.
--
-- Along the waterline, in a window of +-R studs around the camera (stations every `seg` studs), each
-- station runs the shared swell (Env.wavePhase / waveSet: T ~ 8.4 s, crests sweeping along the
-- beach, every ~3rd wave bigger) and poses up to five thin parts on the real sand plane:
--   breaker  a spilling foam line that forms 10-20 studs out and rolls in (on the water)
--   foam     the bright foam edge of the swash: runs up the beach, then thins out and dissolves
--   film     the thin glassy water sheet behind the foam edge (uprush and backwash)
--   sheen    the glossy dark wet sand the backwash leaves behind, drying until the next wave
--   ripples  static ripple marks on the wet sand (high tier)
-- The sand plane per station is measured once by raycasting the terrain (after the fill) and never
-- taken below the static wet-sand slabs of build/districts/coast_shore.luau, so nothing sinks into
-- the voxels or under the slabs. The static foam lines inside the window are hidden locally
-- (LocalTransparencyModifier) while the animated ones run, and shown again outside it.
--
-- Cost: at most (2R / seg) stations x 4 parts moved with one BulkMoveTo per update; Size /
-- Transparency are written only when they change noticeably. Inactive (no parts parented) when the
-- camera is more than ~450 studs from the waterline or high above it.

local Surf = {}

local TIERS = {
	low = { radius = 110, seg = 40, hz = 7, layers = { foam = true, sheen = true } },
	saver = { radius = 80, seg = 44, hz = 5, layers = { foam = true } }, -- weak phones (GwangalliQuality saver)
	mid = { radius = 170, seg = 26, hz = 18, layers = { foam = true, film = true, sheen = true, breaker = true } },
	high = { radius = 240, seg = 22, hz = 24, layers = { foam = true, film = true, sheen = true, breaker = true, ripples = true } },
}

local UP = 0.3 -- share of the wave period spent running up the beach
local R0 = -2.5 -- the backwash pulls the edge this far seaward of the still-water edge
local FOAM_C = Color3.fromRGB(242, 246, 244)
local FILM_C = Color3.fromRGB(186, 220, 214)
local SHEEN_C = Color3.fromRGB(116, 104, 84)
local RIPPLE_C = Color3.fromRGB(146, 131, 104)

function Surf.start(Env: any)
	local root = Env.sub("Surf")
	root.Parent = nil -- parented while the camera is near the waterline
	local cfg = Env.pick(TIERS)
	Env.onTier(function()
		cfg = Env.pick(TIERS)
	end)

	type Station = {
		k: number,
		x: number,
		seg: number,
		E: Vector3, -- still-water edge (y = 0 crossing of the measured plane)
		t: Vector3,
		n: Vector3,
		yA: number, -- plane height at r = -4 (relative to E)
		slope: number,
		pitch: number,
		rotSlope: CFrame, -- rotation only: look inland, pitched to the sand slope
		rotFlat: CFrame, -- rotation only: look inland, level (on the water)
		psi: number, -- per-station phase jitter (seconds)
		amp: number,
		parts: { [string]: BasePart },
		ripples: { BasePart },
		layers: { [string]: boolean },
		pending: boolean?,
	}
	local active: { [number]: Station } = {}
	local pool: { Station } = {}
	local sizeCache: { [BasePart]: Vector3 } = {}
	local trCache: { [any]: number } = {}
	local shown = false

	local function makeParts(layers: { [string]: boolean }, seg: number): ({ [string]: BasePart }, { BasePart })
		local parts = {}
		if layers.sheen then
			local p = Env.part(root, Vector3.new(seg, 0.05, 4), SHEEN_C, Enum.Material.SmoothPlastic, 0.6, "WetSheen")
			p.Reflectance = 0.2
			parts.sheen = p
		end
		if layers.film then
			local p = Env.part(root, Vector3.new(seg, 0.05, 4), FILM_C, Enum.Material.SmoothPlastic, 0.55, "SwashFilm")
			p.Reflectance = 0.3
			parts.film = p
		end
		if layers.foam then
			parts.foam = Env.part(root, Vector3.new(seg, 0.06, 2.5), FOAM_C, Enum.Material.SmoothPlastic, 0.2, "SwashFoam")
		end
		if layers.breaker then
			parts.breaker = Env.part(root, Vector3.new(seg, 0.06, 1.5), FOAM_C, Enum.Material.SmoothPlastic, 0.9, "BreakerFoam")
		end
		local ripples = {}
		if layers.ripples then
			for i = 1, 3 do
				ripples[i] = Env.part(root, Vector3.new(seg * 0.8, 0.04, 0.32), RIPPLE_C, Enum.Material.Sand, 0.55, "SandRipple")
			end
		end
		return parts, ripples
	end

	local function sameLayers(a: { [string]: boolean }, b: { [string]: boolean }): boolean
		for k in a do
			if not b[k] then
				return false
			end
		end
		for k in b do
			if not a[k] then
				return false
			end
		end
		return true
	end

	local function destroyStation(st: Station)
		for _, p in st.parts do
			sizeCache[p] = nil
			trCache[p] = nil
			p:Destroy()
		end
		for _, p in st.ripples do
			p:Destroy()
		end
	end

	-- plane of the sand along the normal at station x (terrain measured, never below the slabs)
	local function measure(st: Station)
		local x = st.x
		local t, n = Env.shoreFrame(x)
		local E0 = Vector3.new(x, 0, Env.edgeZ(x))
		local complete = true
		local function height(r: number): number
			local p = E0 + n * r
			local analytic = Env.sandHeight(p.X, p.Z)
			local measured, ok = Env.groundY(p.X, p.Z, analytic)
			if not ok then
				complete = false
			end
			return math.max(measured, analytic + 0.1)
		end
		local yA, yB = height(-4), height(12)
		-- terrain filled but the ray budget ran out: measure again on a later update
		st.pending = not complete and workspace:GetAttribute("GwangalliTerrainReady") == true
		local slope = math.clamp((yB - yA) / 16, 0.012, 0.09)
		-- y = 0 crossing
		local d0 = math.clamp(-4 - yA / slope, -6, 6)
		st.t, st.n = t, n
		st.E = E0 + n * d0
		-- plane height at r = -4 measured from the new edge E (yA was measured at E0 - 4n)
		st.yA = yA + slope * d0
		st.slope = slope
		st.pitch = math.atan(slope)
		st.rotFlat = CFrame.lookAt(Vector3.zero, n)
		st.rotSlope = st.rotFlat * CFrame.Angles(st.pitch, 0, 0)
	end

	local function assign(st: Station, k: number)
		st.k = k
		st.x = k * st.seg
		st.psi = (Env.hash(k, 3.1) - 0.5) * 0.9
		st.amp = 0.85 + 0.3 * Env.hash(k, 7.7)
		measure(st)
		-- ripples: fixed marks on the wet sand
		for i, p in st.ripples do
			local r = 2.5 + i * 3.6 + (Env.hash(k, i) - 0.5) * 1.4
			local y = st.yA + st.slope * (r + 4) + 0.1
			local pos = st.E + st.n * r + st.t * ((Env.hash(k, i + 9) - 0.5) * st.seg * 0.2) + Vector3.new(0, y, 0)
			p.CFrame = CFrame.lookAt(pos, pos + st.n) * CFrame.Angles(st.pitch, (Env.hash(k, i + 4) - 0.5) * 0.16, 0)
		end
	end

	local function newStation(k: number): Station
		local seg = cfg.seg
		local st: Station
		local reuse = pool[#pool]
		if reuse and reuse.seg == seg and sameLayers(reuse.layers, cfg.layers) then
			pool[#pool] = nil
			st = reuse
		else
			local parts, ripples = makeParts(cfg.layers, seg)
			st = {
				k = k, x = 0, seg = seg, E = Vector3.zero, t = Vector3.xAxis, n = Vector3.zAxis, yA = 0,
				slope = 0.035, pitch = 0.035, rotSlope = CFrame.new(), rotFlat = CFrame.new(), psi = 0, amp = 1, parts = parts, ripples = ripples, layers = cfg.layers,
			}
		end
		assign(st, k)
		return st
	end

	-- static foam registry (hidden inside the animated window)
	local staticFoam: { [BasePart]: { x0: number, x1: number, hidden: boolean } } = {}
	local winLo, winHi = math.huge, -math.huge
	local function applyStatic(p: BasePart, rec: any)
		local hide = shown and rec.x1 > winLo - 6 and rec.x0 < winHi + 6
		if hide ~= rec.hidden then
			rec.hidden = hide
			p.LocalTransparencyModifier = if hide then 1 else 0
		end
	end
	Env.watchTag(Env.TAG.StaticFoam, function(inst)
		if inst:IsA("BasePart") then
			local x0 = inst:GetAttribute("X0")
			local x1 = inst:GetAttribute("X1")
			local c = inst.Position.X
			local rec = { x0 = if type(x0) == "number" then x0 else c - 60, x1 = if type(x1) == "number" then x1 else c + 60, hidden = false }
			staticFoam[inst] = rec
			applyStatic(inst, rec)
		end
	end, function(inst)
		staticFoam[inst :: BasePart] = nil
	end)
	local function refreshStatic()
		for p, rec in staticFoam do
			applyStatic(p, rec)
		end
	end

	local function setShown(on: boolean)
		if on == shown then
			return
		end
		shown = on
		root.Parent = if on then Env.folder else nil
		refreshStatic()
	end

	local function releaseAll()
		for k, st in active do
			active[k] = nil
			table.insert(pool, st)
		end
	end

	local lastTerrainReady = workspace:GetAttribute("GwangalliTerrainReady") == true

	-- pose one station at time `now`; appends to the move lists
	local partsOut: { BasePart } = {}
	local cfOut: { CFrame } = {}
	-- Thin slab on the station's sand plane between offsets r0..r1 (along the inland normal). The
	-- inland / seaward edges may differ at the two ends of the station (dL / dR added to r1 at the
	-- left / right end): the slab is yawed so neighbouring stations meet in a continuous line instead
	-- of steps. `k` alternates a tiny lift so the small overlaps between neighbours never z-fight.
	local function slab(p: BasePart, st: Station, r0: number, r1: number, dEdge: number, lift: number, thick: number, onWater: boolean)
		local len = r1 - r0
		if len < 0.3 then
			len = 0.3
		end
		local rc = (r0 + r1) / 2
		local y = st.yA + st.slope * (rc + 4)
		local l = lift + (st.k % 2) * 0.012
		local E, n = st.E, st.n
		local py = if onWater or y < 0 then math.max(y, 0) + l else y + l
		local cf = CFrame.new(E.X + n.X * rc, py, E.Z + n.Z * rc) * (if onWater then st.rotFlat else st.rotSlope)
		if dEdge > 0.05 or dEdge < -0.05 then
			cf *= CFrame.Angles(0, -math.atan2(dEdge, st.seg), 0)
		end
		table.insert(partsOut, p)
		table.insert(cfOut, cf)
		local wx = math.sqrt(st.seg * st.seg + dEdge * dEdge) + 0.25
		local have = sizeCache[p]
		if not have or math.abs(have.Z - len) > 0.08 or math.abs(have.X - wx) > 0.08 then
			local want = Vector3.new(wx, thick, len)
			sizeCache[p] = want
			p.Size = want
		end
	end

	-- per-station wave state (first pass), rendered with the neighbours' values (second pass)
	type WaveState = { r: number, wf: number, uprush: boolean, u: number, rmax: number, prevMax: number, P: number, rb: number?, wb: number }
	local states: { [number]: WaveState } = {}
	local statePool: { WaveState } = {}
	local function compute(st: Station, now: number, out: WaveState): WaveState
		local x = st.x
		local tt = now + st.psi
		local P = Env.wavePhase(tt, x)
		local set = Env.waveSet(tt, x)
		local rmax = (6 + 11 * (set - 0.7)) * st.amp
		local prevMax = (6 + 11 * (Env.waveSet(tt - Env.WAVE_T, x) - 0.7)) * st.amp
		local r, u, uprush
		if P < UP then
			uprush = true
			u = P / UP
			r = R0 + (rmax - R0) * (1 - (1 - u) ^ 2.3)
		else
			uprush = false
			u = (P - UP) / (1 - UP)
			local c = math.cos(u * math.pi) * 0.5 + 0.5
			r = R0 + (rmax - R0) * c ^ 1.35
		end
		local wf = if uprush then 2.2 + 1.3 * u else 3.5 * (1 - 0.65 * u)
		local rb, wb = nil, 0
		if P > 0.72 then
			local v = (P - 0.72) / 0.28
			local nextSet = Env.waveSet(tt + Env.WAVE_T, x)
			local dB = (10 + 12 * (nextSet - 0.7)) * st.amp
			rb = R0 - dB * (1 - v)
			wb = 1.1 + 2.1 * v
		end
		out.r, out.wf, out.uprush, out.u, out.rmax, out.prevMax, out.P, out.rb, out.wb = r, wf, uprush, u, rmax, prevMax, P, rb, wb
		return out
	end

	-- difference between the right-end and left-end values of a quantity (halfway to the neighbours)
	local function delta(c: number?, l: number?, r: number?): number
		if not c then
			return 0
		end
		local left = if l then (l + c) / 2 else c
		local right = if r then (r + c) / 2 else c
		return right - left
	end

	local function pose(st: Station, w: WaveState, wl: WaveState?, wr: WaveState?)
		local parts = st.parts
		local r, wf, u, uprush = w.r, w.wf, w.u, w.uprush
		-- foam edge
		local foam = parts.foam
		if foam then
			local d = delta(r, wl and wl.r, wr and wr.r)
			slab(foam, st, r - wf * 0.5, r + wf * 0.5, d, 0.18, 0.06, false)
			Env.setNum(foam, "Transparency", if uprush then 0.08 + 0.12 * u else math.min(0.96, 0.2 + 1.5 * u), trCache, 0.02)
		end
		-- film behind the foam edge
		local film = parts.film
		local re = r - wf * 0.3
		if film then
			local len = re + 5
			if len > 1.5 then
				local d = delta(re, wl and (wl.r - wl.wf * 0.3), wr and (wr.r - wr.wf * 0.3))
				slab(film, st, -5, re, d * 0.5, 0.14, 0.05, false)
				Env.setNum(film, "Transparency", if uprush then 0.5 else 0.5 + 0.42 * u, trCache, 0.02)
			else
				Env.setNum(film, "Transparency", 1, trCache, 0.02)
			end
		end
		-- glossy wet sand between the water and the highest reach (dries until the next wave)
		local sheen = parts.sheen
		if sheen then
			local top = if uprush then w.prevMax else w.rmax
			local from = math.max(if uprush then r + wf * 0.5 else re, -0.5)
			if top - from > 1 then
				slab(sheen, st, from, top + 0.6, 0, 0.09, 0.05, false)
				local dry = if uprush then 0.35 + 0.55 * u else 0.45 * u
				Env.setNum(sheen, "Transparency", 0.5 + 0.42 * math.clamp(dry, 0, 1), trCache, 0.02)
			else
				Env.setNum(sheen, "Transparency", 1, trCache, 0.02)
			end
		end
		-- spilling breaker rolling in (last 28 % of the cycle)
		local br = parts.breaker
		if br then
			if w.rb then
				local rb, wb = w.rb :: number, w.wb
				local d = delta(rb, wl and wl.rb, wr and wr.rb)
				slab(br, st, rb - wb * 0.5, rb + wb * 0.5, d, 0.14, 0.06, true)
				Env.setNum(br, "Transparency", 0.92 - 0.66 * (w.P - 0.72) / 0.28, trCache, 0.02)
			else
				Env.setNum(br, "Transparency", 1, trCache, 0.02)
			end
		end
	end

	Env.every("surf", function()
		return cfg.hz
	end, function(now: number)
		local cam = Env.focus()
		local cx = cam.X
		local R = cfg.radius
		local seg = cfg.seg
		local inRange = cx > Env.beachX0 - R and cx < Env.beachX1 + R
		local edgeZ = Env.edgeZ(math.clamp(cx, Env.beachX0, Env.beachX1))
		local near = inRange and math.abs(cam.Z - edgeZ) < 450 and cam.Y < 150
		-- the terrain fill finished: re-measure the planes once
		local ready = workspace:GetAttribute("GwangalliTerrainReady") == true
		if ready ~= lastTerrainReady then
			lastTerrainReady = ready
			for _, st in active do
				assign(st, st.k)
			end
		end
		if not near then
			if shown then
				releaseAll()
				winLo, winHi = math.huge, -math.huge
				setShown(false)
			end
			return
		end
		-- tier change: rebuild with the new layout
		local anyStale = false
		for _, st in active do
			if st.seg ~= seg or not sameLayers(st.layers, cfg.layers) then
				anyStale = true
				break
			end
		end
		if anyStale then
			for k, st in active do
				active[k] = nil
				destroyStation(st)
			end
			for _, st in pool do
				destroyStation(st)
			end
			table.clear(pool)
		end
		local lo = math.max(cx - R, Env.beachX0 + seg * 0.5)
		local hi = math.min(cx + R, Env.beachX1 - seg * 0.5)
		local kLo, kHi = math.ceil(lo / seg), math.floor(hi / seg)
		for k, st in active do
			if k < kLo or k > kHi then
				active[k] = nil
				table.insert(pool, st)
			end
		end
		for k = kLo, kHi do
			if not active[k] then
				active[k] = newStation(k)
			end
		end
		local nlo, nhi = kLo * seg - seg * 0.5, kHi * seg + seg * 0.5
		if nlo ~= winLo or nhi ~= winHi then
			winLo, winHi = nlo, nhi
			setShown(true)
			refreshStatic()
		end
		setShown(true)
		-- parked pool stations: out of sight
		for _, st in pool do
			for _, p in st.parts do
				if p.CFrame ~= Env.HIDDEN_CF then
					table.insert(partsOut, p)
					table.insert(cfOut, Env.HIDDEN_CF)
				end
			end
			for _, p in st.ripples do
				if p.CFrame ~= Env.HIDDEN_CF then
					p.CFrame = Env.HIDDEN_CF
				end
			end
		end
		local remeasure = 2
		for k, w in states do
			states[k] = nil
			table.insert(statePool, w)
		end
		for k, st in active do
			if st.pending and remeasure > 0 then
				remeasure -= 1
				assign(st, st.k)
			end
			local w = table.remove(statePool) or ({} :: any)
			states[k] = compute(st, now, w)
		end
		for k, st in active do
			-- (a station well behind the camera keeps its state for its neighbours, but is not moved)
			if not Env.behind(st.E, st.seg) then
				pose(st, states[k], states[k - 1], states[k + 1])
			end
		end
		Env.move(partsOut, cfOut)
		table.clear(partsOut)
		table.clear(cfOut)
	end)
end

return Surf
