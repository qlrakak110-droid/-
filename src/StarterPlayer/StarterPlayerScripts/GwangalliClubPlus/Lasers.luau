-- GwangalliClubPlus.Lasers: our laser fans + moving heads (client), layered over ClubLights' house rig.
-- ClubLights re-aims its own 32 ClubLaser beams at 30 Hz; we never touch them. Our beams start at the
-- same laser apertures (MainRoom/Lasers) and at our own moving heads (hung from the ceiling where the
-- map has free space), live in Workspace.GwangalliClubPlusLocal and end on attachments in Core.sink().
--   section program  drop: fans / tunnels / crossfire / scans alternating every 4 bars (dimmed during
--                    ClubLights' post-drop fan) · build: rising scan in the 2nd half · breakdown: a slow
--                    sheet over the heads · intro: "OCEAN LASER SHOW" on bars 4..12 every Nth cycle
--   cues             Lasers.cue(kind, opts): flash (tier colour burst -> lock on a table), lock, show
--                    (DJ pad), hands (high sheet), laserShow; Lasers.follow(getPos, colour, seconds)
--                    points the moving heads at a walking rig (합석 MD / guests, bottle staff)
-- Every beam is clipped to the main room box; budgets from Config.Quality (emitters, beams, heads, hz).

local Lasers = {}

local Core: any
local S: any
local Led: any = nil

local NSK = NumberSequenceKeypoint.new
local WHITE = Color3.new(1, 1, 1)
local TAU = math.pi * 2

local built = false
local outsideSince = 0
local builtQuality = ""
local emitters: { any } = {}
local heads: { any } = {}
local floorY = 7.2
local override: any = nil
local followers: { any } = {}
local lastShowNote = -1
local burstFrom = 0

-- cached sequences (no per-frame allocation)
local alphaSeq: { NumberSequence } = {}
for i = 0, 20 do
	local k = i / 20
	alphaSeq[i] = NumberSequence.new({ NSK(0, 1 - 0.95 * k), NSK(1, 1 - 0.7 * k) })
end
local headSeq: { NumberSequence } = {}
for i = 0, 20 do
	local k = i / 20
	headSeq[i] = NumberSequence.new({ NSK(0, 1 - 0.55 * k), NSK(1, 1 - 0.1 * k) })
end
local colourCache: { [string]: ColorSequence } = {}
local function cseq(c: Color3): ColorSequence
	local key = string.format("%d,%d,%d", c.R * 255, c.G * 255, c.B * 255)
	local s = colourCache[key]
	if not s then
		s = ColorSequence.new(c)
		colourCache[key] = s
	end
	return s
end

local function q(): any
	return Core.q()
end

-------------------------------------------------------------------------------------------------
-- build
-------------------------------------------------------------------------------------------------
local function newBeam(a0: Attachment, a1: Attachment, w0: number, w1: number, parent: Instance): Beam
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.Width0 = w0
	b.Width1 = w1
	b.FaceCamera = true
	b.LightEmission = 1
	b.LightInfluence = 0
	b.Segments = 1
	b.Transparency = alphaSeq[0]
	b.Enabled = false
	pcall(function()
		(b :: any).Brightness = 2
	end)
	b.Parent = parent
	return b
end

local function buildEmitters()
	local list = Core.spots("LaserAperture", S.Config.Fallback.Lasers, Vector3.new(0, -0.1, 0))
	-- the booth's two (lower) first, then the LED wall's top ones
	table.sort(list, function(a, b)
		return a.Y < b.Y
	end)
	local roomCf = Core.roomBox()
	local n = math.min(q().lasers, #list)
	local beams = q().beams
	local width = S.Config.Show.LaserWidth
	for i = 1, n do
		local pos = list[i]
		local h = Core.part("PlusLaser", Vector3.new(0.3, 0.3, 0.3), CFrame.new(pos))
		h.Transparency = 1
		local a0 = Instance.new("Attachment")
		a0.Parent = h
		local f = Vector3.new(roomCf.Position.X - pos.X, 0, roomCf.Position.Z - pos.Z)
		f = if f.Magnitude > 1 then f.Unit else Vector3.new(-1, 0, 0)
		local e = { pos = pos, f = f, r = f:Cross(Vector3.yAxis).Unit, beams = {}, side = if i % 2 == 0 then 1 else -1, idx = i }
		for j = 1, beams do
			local a1 = Core.sinkAttachment("LaserEnd")
			local b = newBeam(a0, a1, width, width * 1.7, h)
			table.insert(e.beams, { beam = b, a1 = a1, on = false, k = -1, col = nil })
		end
		table.insert(emitters, e)
	end
end

-- candidate spots for our heads: free air below the ceiling, away from every map fixture
local function freeSpot(pos: Vector3, exclude: { Instance }): (boolean, number)
	for _, part in game:GetService("CollectionService"):GetTagged("ClubLight") do
		if part:IsA("BasePart") and (part.Position - pos).Magnitude < S.Config.Show.HeadClear + 1 then
			return false, 0
		end
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local ok, hits = pcall(function()
		return workspace:GetPartBoundsInBox(CFrame.new(pos), Vector3.new(2.6, 2.6, 2.6), params)
	end)
	if ok and type(hits) == "table" then
		for _, h in hits do
			if h.Transparency < 0.95 then
				return false, 0
			end
		end
	end
	-- something to hang from within 6 studs above
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = exclude
	local okR, hit = pcall(function()
		return workspace:Raycast(pos + Vector3.new(0, 0.8, 0), Vector3.new(0, 6, 0), rp)
	end)
	if okR and hit then
		return true, hit.Distance + 0.8
	end
	if not okR then
		return true, 2.5 -- (no raycasts here: a short rod)
	end
	return false, 0
end

local function buildHeads()
	local want = q().heads
	if want <= 0 then
		return
	end
	local cfg = S.Config.Show
	local exclude: { Instance } = { Core.folder() }
	local detail = workspace:FindFirstChild("GwInteriorDetailLocal")
	if detail then
		table.insert(exclude, detail)
	end
	local showLocal = workspace:FindFirstChild(S.Names.ShowLocal)
	if showLocal then
		table.insert(exclude, showLocal)
	end
	for _, p in game:GetService("Players"):GetPlayers() do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	local cands = {}
	for _, z in cfg.HeadRowsZ do
		local x = cfg.HeadX[1]
		while x <= cfg.HeadX[2] do
			local pos = Vector3.new(x, cfg.HeadY, z)
			local ok, rod = freeSpot(pos, exclude)
			if ok then
				table.insert(cands, { pos = pos, rod = rod })
			end
			x += 4
		end
	end
	if #cands == 0 then
		return
	end
	-- spread them: start near the dance floor, then always the farthest from the chosen ones
	local fl = Core.anchor("Show_Floor")
	local centre = if fl then fl.Position else S.Config.Fallback.Floor
	table.sort(cands, function(a, b)
		return (a.pos - centre).Magnitude < (b.pos - centre).Magnitude
	end)
	local chosen = { table.remove(cands, 1) }
	while #chosen < want and #cands > 0 do
		local bestI, bestD = 1, -1
		for i, c in cands do
			local d = math.huge
			for _, o in chosen do
				d = math.min(d, (c.pos - o.pos).Magnitude)
			end
			if d > bestD then
				bestI, bestD = i, d
			end
		end
		table.insert(chosen, table.remove(cands, bestI))
	end
	local metal = Color3.fromRGB(22, 22, 28)
	for i, c in chosen do
		local base = c.pos
		local rod = Core.part("PlusHeadRod", Vector3.new(0.18, c.rod, 0.18), CFrame.new(base + Vector3.new(0, c.rod * 0.5, 0)), metal, Enum.Material.Metal)
		local yoke = Core.part("PlusHeadYoke", Vector3.new(1.5, 0.3, 0.6), CFrame.new(base + Vector3.new(0, -0.1, 0)), metal, Enum.Material.Metal)
		local body = Core.part("PlusHead", Vector3.new(0.9, 0.9, 1.25), CFrame.new(base + Vector3.new(0, -0.8, 0)), Color3.fromRGB(14, 14, 18), Enum.Material.SmoothPlastic)
		local lens = Core.part("PlusHeadLens", Vector3.new(0.62, 0.62, 0.06), body.CFrame * CFrame.new(0, 0, -0.66), WHITE, Enum.Material.Neon)
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0, -0.7)
		a0.Parent = body
		local a1 = Core.sinkAttachment("HeadEnd")
		local beam = newBeam(a0, a1, 0.5, 5.5, body)
		beam.Transparency = headSeq[0]
		local light: SpotLight? = nil
		if i <= q().headLights then
			local l = Instance.new("SpotLight")
			l.Face = Enum.NormalId.Front
			l.Angle = 24
			l.Range = 42
			l.Brightness = 0
			l.Shadows = false
			l.Parent = body
			light = l
		end
		table.insert(heads, { base = base, rod = rod, yoke = yoke, body = body, lens = lens, beam = beam, a1 = a1, light = light, i = i, k = -1, col = nil, aim = centre })
	end
end

local function teardown()
	built = false
	for _, e in emitters do
		for _, b in e.beams do
			b.a1:Destroy()
		end
	end
	for _, h in heads do
		h.a1:Destroy()
	end
	table.clear(emitters)
	table.clear(heads)
	for _, ch in Core.folder():GetChildren() do
		if string.sub(ch.Name, 1, 9) == "PlusLaser" or string.sub(ch.Name, 1, 8) == "PlusHead" then
			ch:Destroy()
		end
	end
end

local function build()
	built = true
	builtQuality = q().name
	local fl = Core.anchor("Show_Floor")
	floorY = if fl then fl.Position.Y - 2.8 else S.Config.Fallback.Floor.Y - 2.8
	for _, fn in { buildEmitters, buildHeads } do
		local ok, err = pcall(fn)
		if not ok then
			warn("[GwangalliClubPlus] laser build failed:", err)
		end
	end
end

-------------------------------------------------------------------------------------------------
-- patterns: direction of beam j (0..1 across the fan) of emitter e
-------------------------------------------------------------------------------------------------
local function dirOf(e: any, yaw: number, pitch: number): Vector3
	local h = e.f * math.cos(yaw) + e.r * math.sin(yaw)
	return (h * math.cos(pitch) + Vector3.yAxis * math.sin(pitch)).Unit
end

local PATTERNS: { [string]: (e: any, u: number, j: number, n: number, t: number, beat: number) -> (Vector3?, boolean) } = {}

PATTERNS.fan = function(e, u, _j, _n, t, _beat)
	local yaw = (u - 0.5) * 1.15 + 0.3 * math.sin(t * 0.9 + e.idx)
	return dirOf(e, yaw, -0.1 + 0.06 * math.sin(t * 1.3)), true
end
PATTERNS.sheet = function(e, u, _j, _n, t, _beat)
	local yaw = (u - 0.5) * 1.55
	return dirOf(e, yaw, -0.2 + 0.13 * math.sin(t * 0.55 + e.idx * 0.7)), true
end
PATTERNS.high = function(e, u, _j, _n, t, _beat)
	local yaw = (u - 0.5) * 1.5 + 0.12 * math.sin(t * 2)
	return dirOf(e, yaw, 0.02 + 0.05 * math.sin(t * 2.4)), true
end
PATTERNS.tunnel = function(e, u, _j, _n, t, _beat)
	local phi = u * TAU + t * 1.6 * e.side
	local a = 0.2 + 0.06 * math.sin(t * 0.8)
	local axis = dirOf(e, 0.12 * math.sin(t * 0.4) * e.side, -0.12)
	local side = axis:Cross(Vector3.yAxis).Unit
	local up = side:Cross(axis).Unit
	return (axis * math.cos(a) + (side * math.cos(phi) + up * math.sin(phi)) * math.sin(a)).Unit, true
end
PATTERNS.scan = function(e, u, _j, _n, t, _beat)
	local yaw = (u - 0.5) * 0.35 + 0.75 * math.sin(t * 1.1 + e.idx * 1.3)
	return dirOf(e, yaw, -0.16), true
end
PATTERNS.cross = function(e, u, _j, _n, t, _beat)
	local yaw = (u - 0.5) * 0.7 + e.side * (0.35 + 0.3 * math.sin(t * 1.4))
	return dirOf(e, yaw, -0.13 + 0.04 * math.sin(t * 3)), true
end
-- beats light the fan one beam at a time (left -> right -> left)
PATTERNS.chase = function(e, u, j, n, t, beat)
	local yaw = (u - 0.5) * 1.3
	local step = beat % (2 * n)
	local lit = if step < n then step + 1 else 2 * n - step
	return dirOf(e, yaw, -0.1), math.abs(j - lit) <= 1
end
PATTERNS.burst = function(e, u, _j, _n, t, _beat)
	local yaw = (u - 0.5) * (0.2 + 1.7 * math.clamp((t - burstFrom) / 0.6, 0, 1))
	return dirOf(e, yaw, -0.08), true
end

local SHOW_ORDER = { "tunnel", "fan", "cross", "chase", "sheet", "scan", "burst", "high" }

-------------------------------------------------------------------------------------------------
-- program
-------------------------------------------------------------------------------------------------
local clk: any = {}
local function pal(i: number): Color3
	local P = S.Config.Show.LaserPalette
	return P[((i - 1) % #P) + 1]
end

-- -> pattern, colour, intensity 0..1, target?, colour2?
local function program(now: number): (string?, Color3, number, Vector3?, Color3?)
	local t = os.clock()
	local phase, beat, bpm, section, bar, energy = Core.beat()
	local period = 60 / bpm
	if override and t < override.untilT then
		local o = override
		local el = t - o.from
		local pattern = o.pattern
		if pattern == "show" then
			pattern = SHOW_ORDER[(math.floor(el / (period * 4)) % #SHOW_ORDER) + 1]
		end
		local k = o.k * math.clamp((o.untilT - t) / 0.4, 0, 1) * (0.82 + 0.18 * (1 - phase) ^ 2)
		local col = o.color or pal(math.floor(el / (period * 2)) + 1)
		if o.cycle then
			col = pal(math.floor(el / period) + 1)
		end
		if o.target and el > (o.lockAfter or 0) then
			return "lock", col, k, o.target, o.color2
		end
		return pattern, col, k, nil, o.color2
	elseif override then
		override = nil
	end
	local bus = Core.Bus
	local sinceDrop = t - (tonumber(bus.dropAt) or -1e9)
	local barIn = bar % 8
	if section == "drop" then
		local k = (0.75 + 0.25 * (1 - phase) ^ 2) * math.clamp(energy + 0.2, 0.5, 1)
		if sinceDrop < period * 4 then
			k *= 0.35 -- ClubLights' own post-drop fan owns these beats
		end
		local idx = math.floor(bar / 4)
		local pattern = ({ "fan", "tunnel", "cross", "scan" })[(idx % 4) + 1]
		return pattern, pal(bar % 2 + 1), k, nil, nil
	elseif section == "build" then
		if barIn >= 4 then
			return "scan", pal(3):Lerp(WHITE, (barIn - 4) / 6), 0.35 + 0.15 * (barIn - 4), nil, nil
		end
		return nil, WHITE, 0, nil, nil
	elseif section == "breakdown" then
		return "sheet", pal(4):Lerp(pal(1), 0.5 + 0.5 * math.sin(t * 0.4)), 0.45, nil, nil
	elseif section == "intro" then
		-- OCEAN LASER SHOW: bars 4..12 of every Nth show cycle (clock mode)
		local CS = Core.ClubShared
		if CS and type(CS.clock) == "function" and not bus.live then
			pcall(CS.clock, now, Core.epoch(), bpm, clk)
			local cycle = math.floor((clk.beat or 0) / 256)
			if cycle % math.max(1, S.Config.Show.LaserShowEvery) == 0 and bar >= 4 and bar < 12 then
				if lastShowNote ~= cycle and Led then
					lastShowNote = cycle
					local left = (12 - bar) * 4 * period - (clk.beatInBar or 0) * period
					pcall(Led.note, "lasershow" .. cycle, Core.L.Show.laserShow, math.clamp(left, 4, 20), Color3.fromRGB(150, 60, 255))
				end
				local idx = math.floor((bar - 4) / 2)
				return ({ "tunnel", "sheet", "chase", "fan" })[(idx % 4) + 1], pal(idx + 1), 0.85, nil, nil
			end
		end
		return nil, WHITE, 0, nil, nil
	end
	-- groove / unknown (LIVE music without sections)
	return "fan", pal(math.floor(beat / 8) + 1), 0.4 + 0.4 * math.clamp(energy, 0, 1), nil, nil
end

local function setBeam(b: any, on: boolean, k: number, col: Color3, seqs: { NumberSequence })
	if on and k > 0.02 then
		local ki = math.clamp(math.floor(k * 20 + 0.5), 0, 20)
		if ki ~= b.k then
			b.k = ki
			b.beam.Transparency = seqs[ki]
		end
		if b.col ~= col then
			b.col = col
			b.beam.Color = cseq(col)
		end
		if not b.on then
			b.on = true
			b.beam.Enabled = true
		end
	elseif b.on then
		b.on = false
		b.beam.Enabled = false
	end
end

local function aimLasers(now: number)
	local pattern, col, k, target, col2 = program(now)
	local t = os.clock()
	local _, beat = Core.beat()
	local reach = S.Config.Show.LaserReach
	for _, e in emitters do
		local n = #e.beams
		for j, b in e.beams do
			local u = if n > 1 then (j - 1) / (n - 1) else 0.5
			local c = if col2 and j % 2 == 0 then col2 else col
			if not pattern then
				setBeam(b, false, 0, c, alphaSeq)
			elseif pattern == "lock" and target then
				-- converge with a breathing ring around the target
				local ang = u * TAU + t * 2.2 * e.side
				local rad = 0.6 + 1.1 * (0.5 + 0.5 * math.sin(t * 3))
				local p = target + Vector3.new(math.cos(ang) * rad, 0.2 + 0.4 * math.sin(t * 4 + j), math.sin(ang) * rad)
				Core.place(b.a1, p)
				setBeam(b, true, k, c, alphaSeq)
			else
				local fn = PATTERNS[pattern] or PATTERNS.fan
				local d, lit = fn(e, u, j, n, t, beat)
				if d then
					Core.place(b.a1, Core.clipToRoom(e.pos, d, reach, 0.5))
				end
				setBeam(b, lit, k, c, alphaSeq)
			end
		end
	end
	return pattern, col, k, target
end

-- moving heads: idle choreography or a cue / follow target
local function aimHeads(pattern: string?, col: Color3, k: number, target: Vector3?)
	if #heads == 0 then
		return
	end
	local t = os.clock()
	local phase, _, _, section = Core.beat()
	local fl = Core.anchor("Show_Floor")
	local centre = if fl then Vector3.new(fl.Position.X, floorY, fl.Position.Z) else Vector3.new(S.Config.Fallback.Floor.X, floorY, S.Config.Fallback.Floor.Z)
	-- live followers win
	local fol = nil
	for i = #followers, 1, -1 do
		local f = followers[i]
		if t > f.untilT then
			table.remove(followers, i)
		elseif not fol then
			local ok, p = pcall(f.get)
			if ok and typeof(p) == "Vector3" then
				fol = { pos = p, col = f.col }
			end
		end
	end
	local headK = if fol then 0.9 elseif target then 0.85 elseif section == "drop" then 0.75 elseif section == "build" then 0.5 elseif pattern then 0.4 else 0.22
	headK *= (0.85 + 0.15 * (1 - phase) ^ 2)
	for _, h in heads do
		local aim: Vector3
		local c = col
		if fol then
			aim = fol.pos + Vector3.new(math.sin(t * 2 + h.i) * 0.6, 0, math.cos(t * 2 + h.i) * 0.6)
			c = fol.col
		elseif target then
			aim = target + Vector3.new(math.sin(t * 2.5 + h.i) * 1.2, 0, math.cos(t * 2.5 + h.i) * 1.2)
		elseif section == "drop" then
			local a = t * 1.6 + h.i * 0.9
			aim = centre + Vector3.new(math.cos(a) * 9, 0, math.sin(a * 1.3) * 14)
		elseif section == "build" then
			local a = t * 0.8 + h.i * 0.6
			aim = centre + Vector3.new(math.sin(a) * 18 - 10, 0, math.sin(a * 2) * 16)
		else
			-- slow ballyhoo over the crowd
			local a = t * 0.35 + h.i * 1.1
			aim = centre + Vector3.new(math.sin(a) * 22 - 14, 0, math.cos(a * 0.7) * 22)
			c = pal(h.i)
		end
		-- smooth the aim (heads move, they don't teleport)
		h.aim = h.aim:Lerp(aim, if fol or target then 0.25 else 0.12)
		local cf = CFrame.lookAt(h.base + Vector3.new(0, -0.8, 0), h.aim)
		h.body.CFrame = cf
		h.lens.CFrame = cf * CFrame.new(0, 0, -0.66)
		h.lens.Color = c
		Core.place(h.a1, h.aim)
		local ki = math.clamp(math.floor(headK * 20 + 0.5), 0, 20)
		if ki ~= h.k then
			h.k = ki
			h.beam.Transparency = headSeq[ki]
		end
		if h.col ~= c then
			h.col = c
			h.beam.Color = cseq(c)
		end
		if not h.beam.Enabled then
			h.beam.Enabled = true
		end
		if h.light then
			h.light.Color = c
			h.light.Brightness = 2.5 * headK
		end
	end
end

function Lasers.init(core: any, led: any?)
	Core = core
	S = core.S
	Led = led
	Core.job("laserlife", 2, function()
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
	local acc = 0
	Core.job("lasers", 30, function(dt: number, now: number)
		if not built or not (Core.inside and Core.showRoom) then
			return true
		end
		local hz = q().hz
		if hz <= 0 then
			return true
		end
		acc += dt
		if acc < 1 / hz - 0.004 then
			return true
		end
		acc = 0
		local r = Core.root()
		if r and (r.Position - Core.roomBox().Position).Magnitude > 170 then
			return true
		end
		local pattern, col, k, target = aimLasers(now)
		aimHeads(pattern, col, k, target)
		return true
	end)
end

-- cues ------------------------------------------------------------------------------------------
-- kind: "flash" | "lock" | "show" | "hands" | "laserShow"
-- opts: { beats?, color?, color2?, target? (Vector3), k? }
function Lasers.cue(kind: string, opts: { [string]: any }?)
	local o = opts or {}
	local _, _, bpm = Core.beat()
	local period = 60 / bpm
	local beats = o.beats or 8
	local now = os.clock()
	-- a weaker cue never cuts a stronger running one short
	local pri = ({ flash = 2, lock = 2, hands = 2, show = 3, laserShow = 1 })[kind] or 1
	if override and now < override.untilT and override.pri > pri then
		return
	end
	local pattern = ({ flash = "burst", lock = "fan", show = "show", hands = "high", laserShow = "show" })[kind] or "fan"
	burstFrom = now
	override = {
		pattern = pattern,
		color = o.color,
		color2 = o.color2,
		target = o.target,
		lockAfter = if kind == "flash" then period * 2 else 0,
		k = o.k or 1,
		from = now,
		untilT = now + beats * period,
		cycle = kind == "show" and o.color == nil,
		pri = pri,
	}
end

-- point the moving heads at a moving thing for `seconds` (getPos returns a world position or nil)
function Lasers.follow(getPos: () -> Vector3?, color: Color3, seconds: number)
	table.insert(followers, { get = getPos, col = color, untilT = os.clock() + seconds })
	while #followers > 4 do
		table.remove(followers, 1)
	end
end

function Lasers.floorY(): number
	return floorY
end

return Lasers
