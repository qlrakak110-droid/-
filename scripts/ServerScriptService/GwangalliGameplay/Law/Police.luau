-- GwangalliGameplay/Law/Police (server; owner: law): the NPC police of 광안지구대 — officers on foot,
-- patrol cars, road closures and the idle patrol. GTA-like but deliberately imperfect.
--
--   CASE (one per wanted player): 신고 접수 (Law.report) -> dispatch: units appear out of the suspect's
--   sight 70-130 studs from the REPORTED spot (cars ~300 studs up the road) and head for that spot.
--   The dispatcher only knows what was reported or radioed: for a while after a report / a sighting /
--   a fresh witness call it posts the suspect's AREA every few seconds (radioFix, LS.TIERS radio),
--   then the units only have the last known spot (an unseen suspect still gets away). On arrival
--   they search (random nav nodes 8-28 studs around the last known spot, looking around), and only a
--   real SIGHTING (range + view cone + a raycast, a reaction delay before they "see" you) gives them
--   the live position: 발견 -> "거기 서!" -> 추격 -> grab attempts -> 체포 (Law.arrest). A 1-star minor
--   offence gets a stop order first ("멈추세요") and a ticket if you comply.
--   IMPERFECT on purpose (TIERS tune it per star level): they lose you behind corners / in alleys (no
--   line of sight = no live position; they run to where they last saw you, then search), they sometimes
--   take a wrong branch at a junction ("어? 막다른 길이네"), they hesitate at alley steps / stairs /
--   crossings, a grab can slip, cars sometimes pick the wrong side road. They are never omniscient and
--   never as quick as a sprinting player at 1-2 stars, but get faster, sharper and more numerous with
--   every star (reinforcements, several cars, road closures and 검문 at 4+).
--   CARS: server-owned scenery clones of the map's Car_Police (anchored root + welds, light bar, siren)
--   moved along the traffic lanes (TaxiDispatch). When the suspect drives, cars chase on the lanes,
--   re-planning every couple of seconds; a car within reach of a stopped / crawling suspect car ends it.
--   OFFICERS are anchored rigs in workspace.GwangalliNPCs (NpcId / NpcLeg / NpcAct ... = the
--   GwangalliNPCClient contract): the server keeps an analytic position (polyline + speed + start time)
--   and every client interpolates the walk.
--   PATROL: with no case the city still has a few officers / cars around the players (more at night);
--   they notice wanted players and NPC incidents (Law/City).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Police = {}

local Law: any
local ctx: any
local LS: any
local Nav: any = nil
local dec: any = nil
local D: any = nil -- TaxiDispatch (lane routing)
local graph: any = nil
local Looks: any = nil

local npcFolder: Folder
local carsFolder: Folder
local officers: { any } = {}
local cars: { any } = {}
local blocks: { any } = {}
local cases: { [Player]: any } = {}
local seq = 0
local carTemplate: Model? = nil
local demoCar: any = nil -- test only (debugDemo)
local carOffsetY = 2.6
local CREW_SCALE = 0.84 -- officers' build scale: seated in a patrol car (3.45 studs floor to roof) the cap stays under the roof
local rng = Random.new()

local function now(): number
	return os.clock()
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function rnd(): number
	return rng:NextNumber()
end

local function flat(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function pick(list: { string }?, last: string?): string
	return LS.pick(list, rnd, last)
end

-------------------------------------------------------------------------------------------------
-- Geometry
-------------------------------------------------------------------------------------------------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local lastFilter = 0

local function refreshFilter()
	if now() - lastFilter < 2 then
		return
	end
	lastFilter = now()
	local ex: { Instance } = { npcFolder, carsFolder }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ex, p.Character)
		end
	end
	for _, n in { "GwangalliStreetLife", "GwangalliTaxis", "GwangalliPlayerCars", "GwangalliWork_starbucks" } do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(ex, f)
		end
	end
	rayParams.FilterDescendantsInstances = ex
end

local function groundAt(p: Vector3, fallback: number?): number
	refreshFilter()
	local ok, hit = pcall(function()
		return workspace:Raycast(Vector3.new(p.X, p.Y + 8, p.Z), Vector3.new(0, -40, 0), rayParams)
	end)
	if ok and hit then
		return hit.Position.Y
	end
	return fallback or p.Y
end

-- a walk goal on the floor: goals taken from a HumanoidRootPart (the suspect, Law.posOf) sit ~3 studs
-- over it and the officer's feet would climb to that height. The ray starts just over the point (never
-- an awning / a ceiling); a point already on the floor comes back unchanged, and a drop deeper than a
-- jump is ignored (never under a floor the filter skips)
local function feetAt(p: Vector3): Vector3
	refreshFilter()
	local ok, hit = pcall(function()
		return workspace:Raycast(p + Vector3.new(0, 0.5, 0), Vector3.new(0, -9, 0), rayParams)
	end)
	if ok and hit and hit.Position.Y < p.Y - 0.3 then
		return Vector3.new(p.X, hit.Position.Y, p.Z)
	end
	return p
end

local function losClear(a: Vector3, b: Vector3): boolean
	refreshFilter()
	local dir = b - a
	if dir.Magnitude < 1 then
		return true
	end
	local ok, hit = pcall(function()
		return workspace:Raycast(a, dir, rayParams)
	end)
	return ok and hit == nil
end

-- the first thing on the line a -> b (tests / tools)
local function rayHit(a: Vector3, b: Vector3): RaycastResult?
	refreshFilter()
	local ok, hit = pcall(function()
		return workspace:Raycast(a, b - a, rayParams)
	end)
	return if ok then hit else nil
end

local function loadNav(): boolean
	if dec then
		return true
	end
	local N, d = Law.nav()
	if not N or not d then
		return false
	end
	Nav, dec = N, d
	local tm = script.Parent and script.Parent.Parent and script.Parent.Parent:FindFirstChild("TaxiDispatch")
	if tm and tm:IsA("ModuleScript") then
		local ok, res = pcall(require, tm)
		if ok and type(res) == "table" then
			D = res
			local okG, g = pcall(D.graph, Nav)
			graph = if okG then g else nil
		end
	end
	return true
end

local function nodePos(i: number): Vector3
	return dec.pos[i]
end

-- feet points along the pedestrian graph from `from` to `to` (nil when no route)
local function routePts(from: Vector3, to: Vector3, opts: any?): ({ Vector3 }?, { number }?)
	if not loadNav() then
		return nil, nil
	end
	local o = opts or {}
	-- close and visible: straight there
	if flat(from, to) < 26 and losClear(from + Vector3.new(0, 2.5, 0), to + Vector3.new(0, 2.5, 0)) then
		return { from, to }, nil
	end
	local okA, a = pcall(Nav.nearest, from, 50)
	local okB, b = pcall(Nav.nearest, to, 70)
	if not (okA and okB and a and b) then
		return nil, nil
	end
	local okR, nodes = pcall(Nav.route, a, b, false)
	if not okR or type(nodes) ~= "table" or #nodes == 0 then
		return nil, nil
	end
	-- a wrong turn: at an early junction take a branch off the route, then come back (opts.wrong chance)
	if o.wrong and rnd() < o.wrong and #nodes >= 4 then
		for k = 2, math.min(#nodes - 1, 7) do
			local adj = dec.adj[nodes[k]]
			if adj and #adj >= 6 then -- 3+ neighbours (pairs of node, edge)
				local options = {}
				for j = 1, #adj, 2 do
					local nb = adj[j]
					if nb ~= nodes[k - 1] and nb ~= nodes[k + 1] then
						table.insert(options, nb)
					end
				end
				if #options > 0 then
					local wrongNode = options[rng:NextInteger(1, #options)]
					-- go 1-2 nodes down the wrong branch
					local far = wrongNode
					local adj2 = dec.adj[wrongNode]
					if adj2 and #adj2 >= 2 and rnd() < 0.6 then
						local nb2 = adj2[1]
						if nb2 ~= nodes[k] then
							far = nb2
						end
					end
					local okR2, back = pcall(Nav.route, far, b, false)
					if okR2 and type(back) == "table" and #back > 0 then
						local out = {}
						for i = 1, k do
							table.insert(out, nodes[i])
						end
						table.insert(out, wrongNode)
						if far ~= wrongNode then
							table.insert(out, far)
						end
						for i = 1, #back do
							table.insert(out, back[i])
						end
						nodes = out
						o.wrongAt = (k + (if far ~= wrongNode then 2 else 1))
					end
					break
				end
			end
		end
	end
	local pts = { from }
	for _, n in nodes do
		table.insert(pts, nodePos(n))
	end
	if flat(pts[#pts], to) > 1.5 and flat(pts[#pts], to) < 30 then
		table.insert(pts, to)
	end
	return pts, nodes
end

local function ringNode(center: Vector3, rMin: number, rMax: number, awayFrom: Vector3?): Vector3?
	if not loadNav() then
		return nil
	end
	for _ = 1, 14 do
		local a = rnd() * math.pi * 2
		local r = rMin + rnd() * (rMax - rMin)
		local p = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local ok, n = pcall(Nav.nearest, p, 30)
		if ok and n then
			local q = nodePos(n)
			if flat(q, center) >= rMin * 0.6 and (not awayFrom or flat(q, awayFrom) > 30) then
				return q
			end
		end
	end
	return nil
end

local function playersNear(p: Vector3, r: number): boolean
	for _, pl in Players:GetPlayers() do
		local pp = Law.posOf(pl)
		if pp and flat(pp, p) < r then
			return true
		end
	end
	return false
end

-- could any player see a figure standing at q? (within 160 studs: closer than 35 or a clear line)
local function spotSeen(q: Vector3): boolean
	for _, p in Players:GetPlayers() do
		local pp = Law.posOf(p)
		if pp and flat(pp, q) < 160 and (flat(pp, q) < 35 or losClear(pp + Vector3.new(0, 4, 0), q + Vector3.new(0, 4, 0))) then
			return true
		end
	end
	return false
end

-- a car start / roadblock spot: at least minFlat from every player and out of their sight within losR
local function unseenStart(p0: Vector3, minFlat: number, losR: number): (boolean, number, boolean)
	local minD, seen = math.huge, false
	for _, p in Players:GetPlayers() do
		local pp = Law.posOf(p)
		if pp then
			local d = flat(pp, p0)
			minD = math.min(minD, d)
			if d < losR and losClear(pp + Vector3.new(0, 4.5, 0), p0 + Vector3.new(0, 2.5, 0)) then
				seen = true
			end
		end
	end
	return minD >= minFlat and not seen, minD, seen
end

-- a spawn spot rMin..rMax from `center`, on the nav graph, out of every player's sight. Never a seen
-- spot (nobody pops up in view): nil when every try is seen; `wide` = then a second ring just past the
-- 160-stud seen radius (the unit walks in from farther away instead; within LOST_FAR + 50 of a
-- player: the straggler despawn, LOST_FAR + 60, is measured from the players, not from `center`)
local function hiddenSpot(center: Vector3, rMin: number, rMax: number, wide: boolean?): Vector3?
	for _ = 1, 10 do
		local q = ringNode(center, rMin, rMax, nil)
		if q and not spotSeen(q) then
			return q
		end
	end
	if wide then
		local r0 = math.max(rMax, 165)
		for _ = 1, 6 do
			local q = ringNode(center, r0, r0 + 35, nil)
			if q and flat(q, center) <= r0 + 40 and playersNear(q, LS.LOST_FAR + 50) and not spotSeen(q) then
				return q
			end
		end
	end
	return nil
end

-------------------------------------------------------------------------------------------------
-- Officers (rigs + analytic motion)
-------------------------------------------------------------------------------------------------
local NAMES = { "김 순경", "이 경장", "박 순경", "최 경사", "정 순경", "강 경장", "조 순경", "윤 경사", "장 순경", "임 경위", "한 순경", "오 경장" }

local function polyLen(pts: { Vector3 }): { number }
	local cum = { 0 }
	for i = 2, #pts do
		cum[i] = cum[i - 1] + (pts[i] - pts[i - 1]).Magnitude
	end
	return cum
end

local function legPos(o: any, t: number): (Vector3, Vector3?)
	local pts = o.path
	if not pts or #pts == 0 then
		return o.pos, nil
	end
	if #pts == 1 or o.speed <= 0 then
		return pts[#pts], nil
	end
	local dist = math.max(0, (t - o.t0) * o.speed)
	local cum = o.cum
	local total = cum[#cum]
	if dist >= total then
		return pts[#pts], (pts[#pts] - pts[#pts - 1])
	end
	local lo = 1
	for i = 2, #cum do
		if cum[i] >= dist then
			lo = i - 1
			break
		end
	end
	local seg = cum[lo + 1] - cum[lo]
	local u = if seg > 1e-4 then (dist - cum[lo]) / seg else 1
	return pts[lo]:Lerp(pts[lo + 1], u), (pts[lo + 1] - pts[lo])
end

local function writeLeg(o: any)
	local m = o.model
	if not m or not m.Parent then
		return
	end
	local pts = o.path
	if not pts or #pts < 2 or o.speed <= 0 then
		local p = o.pos
		m:SetAttribute("NpcLeg", string.format("%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.2f,0", p.X, p.Y, p.Z, p.X, p.Y, p.Z, serverNow()))
		return
	end
	local parts = table.create(#pts + 3)
	parts[1] = "P"
	parts[2] = string.format("%.2f", o.t0Server)
	parts[3] = string.format("%.2f", o.speed)
	for i, p in pts do
		parts[i + 3] = string.format("%.1f,%.1f,%.1f", p.X, p.Y, p.Z)
	end
	m:SetAttribute("NpcLeg", table.concat(parts, ";"))
end

local function setAct(o: any, act: string)
	if o.act ~= act and o.model then
		o.act = act
		o.model:SetAttribute("NpcAct", act)
	end
end

local function faceTo(o: any, p: Vector3)
	local d = p - o.pos
	if Vector3.new(d.X, 0, d.Z).Magnitude > 0.2 then
		local yaw = math.deg(math.atan2(-d.X, -d.Z))
		o.yaw = yaw
		if o.model then
			o.model:SetAttribute("NpcYaw", yaw)
		end
	end
end

local function standAt(o: any, p: Vector3?)
	o.pos = p or o.pos
	o.path = nil
	o.speed = 0
	o.cum = nil
	writeLeg(o)
	setAct(o, o.idleAct or "idle")
	if o.model then
		o.model:PivotTo(CFrame.new(o.pos + Vector3.new(0, o.ground, 0)) * CFrame.Angles(0, math.rad(o.yaw or 0), 0))
		o.rootSyncT, o.rootSyncP = now(), o.pos
	end
end

local function moveAlong(o: any, pts: { Vector3 }, speed: number)
	if #pts < 2 then
		standAt(o, pts[1])
		return
	end
	o.path = pts
	o.cum = polyLen(pts)
	o.speed = speed
	o.t0 = now()
	o.t0Server = serverNow()
	o.pos = pts[1]
	writeLeg(o)
	setAct(o, "idle") -- the client walks / runs the rig by the leg speed
	if o.model then
		o.model:PivotTo(CFrame.new(pts[1] + Vector3.new(0, o.ground, 0)) * CFrame.Angles(0, math.rad(o.yaw or 0), 0))
		o.rootSyncT, o.rootSyncP = now(), pts[1]
	end
end

local function arrived(o: any): boolean
	if not o.path then
		return true
	end
	return (now() - o.t0) * o.speed >= o.cum[#o.cum] - 0.05
end

-- StreamingEnabled: the server copy of a walking / running rig follows its leg at ~1 Hz (it used to stay
-- at the leg start, up to 130 studs off), so it streams in where the officer really is and Fight's
-- server-side reach check sees him there. Clients draw the walk every frame from NpcLeg as before.
local function syncRoot(o: any)
	if o.gone or o.seated or not o.path or o.speed <= 0 or not o.model or not o.model.Parent then
		return
	end
	local t = now()
	if t - (o.rootSyncT or 0) < 1 then
		return
	end
	o.rootSyncT = t
	local p, dir = legPos(o, t)
	if o.rootSyncP and (p - o.rootSyncP).Magnitude < 2 then
		return -- arrived / barely moved: nothing to send
	end
	o.rootSyncP = p
	local yaw = if dir and Vector3.new(dir.X, 0, dir.Z).Magnitude > 0.05 then math.atan2(-dir.X, -dir.Z) else math.rad(o.yaw or 0)
	o.model:PivotTo(CFrame.new(p + Vector3.new(0, o.ground, 0)) * CFrame.Angles(0, yaw, 0))
end

-- speech bubble over the head (Workspace BillboardGui: every client renders it)
local function say(o: any, text: string, seconds: number?)
	if text == "" or not o.model or not o.model.Parent then
		return
	end
	if text == o.lastLine and now() - (o.lastSayT or 0) < 12 then
		return
	end
	o.lastLine = text
	o.lastSayT = now()
	local head = o.model:FindFirstChild("Head")
	if not head then
		return
	end
	local bb = o.bubble
	if not bb or not bb.Parent then
		bb = Instance.new("BillboardGui")
		bb.Name = "LawSay"
		bb.Size = UDim2.fromOffset(240, 46)
		bb.StudsOffset = Vector3.new(0, 2.4, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 90
		bb.LightInfluence = 0
		local t = Instance.new("TextLabel")
		t.Name = "Text"
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundColor3 = Color3.fromRGB(18, 28, 60)
		t.BackgroundTransparency = 0.12
		t.TextColor3 = Color3.fromRGB(235, 242, 255)
		t.Font = Enum.Font.GothamBold
		t.TextScaled = true
		t.TextWrapped = true
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 10)
		c.Parent = t
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 8)
		pad.PaddingRight = UDim.new(0, 8)
		pad.PaddingTop = UDim.new(0, 4)
		pad.PaddingBottom = UDim.new(0, 4)
		pad.Parent = t
		local lim = Instance.new("UITextSizeConstraint")
		lim.MaxTextSize = 18
		lim.Parent = t
		t.Parent = bb
		bb.Adornee = head
		bb.Parent = o.model
		o.bubble = bb
	end
	local label = bb:FindFirstChild("Text") :: TextLabel
	label.Text = "👮 " .. text
	bb.Enabled = true
	local stamp = now()
	o.bubbleT = stamp
	task.delay(seconds or 3.2, function()
		if o.bubbleT == stamp and bb.Parent then
			bb.Enabled = false
		end
	end)
end
Police.say = say

local function emote(o: any, name: string)
	if o.model then
		seq += 1
		o.model:SetAttribute("NpcEmote", name .. "#" .. seq .. "#" .. string.format("%.2f", serverNow()))
	end
end

local function buildRig(id: string, hint: any?, crewHint: any?): (Model?, BasePart?, number)
	if not Looks then
		return nil, nil, 3
	end
	local ok, rig = pcall(function()
		local spec = Looks.random(id, hint or crewHint or { style = "police", body = if rnd() < 0.22 then "f" else "m", age = if rnd() < 0.7 then "adult" else "young" })
		if not hint then
			spec.scale = CREW_SCALE
		end
		if crewHint and type(crewHint.acc) == "table" then
			spec.acc = table.clone(crewHint.acc) -- the unit's own gear (helmet, rifle, kit bag)
		end
		return Looks.build(spec, { name = (if hint then "Npc_" else "Police_") .. id, anchored = true, shadow = false })
	end)
	if not ok or type(rig) ~= "table" or not rig.model then
		warn("[GwangalliLaw] rig failed: " .. tostring(rig))
		return nil, nil, 3
	end
	-- police cap (a dark navy block with a gold badge) so officers read at a glance
	local head = rig.parts and rig.parts.Head
	if head and not hint and not crewHint then
		local s = head.Size.X
		local cap = Instance.new("Part")
		cap.Name = "PoliceCap"
		cap.Size = Vector3.new(s * 1.08, s * 0.32, s * 1.12)
		cap.Color = Color3.fromRGB(24, 34, 70)
		cap.Material = Enum.Material.SmoothPlastic
		cap.CanCollide, cap.CanQuery, cap.CanTouch, cap.Massless, cap.CastShadow = false, false, false, true, false
		cap.Anchored = false
		cap.CFrame = head.CFrame * CFrame.new(0, s * 0.56, 0)
		local brim = Instance.new("Part")
		brim.Name = "PoliceBrim"
		brim.Size = Vector3.new(s * 1.1, s * 0.08, s * 0.4)
		brim.Color = Color3.fromRGB(14, 18, 34)
		brim.CanCollide, brim.CanQuery, brim.CanTouch, brim.Massless, brim.CastShadow = false, false, false, true, false
		brim.CFrame = head.CFrame * CFrame.new(0, s * 0.42, -s * 0.66)
		local badge = Instance.new("Part")
		badge.Name = "PoliceBadge"
		badge.Size = Vector3.new(s * 0.24, s * 0.2, s * 0.06)
		badge.Color = Color3.fromRGB(240, 196, 60)
		badge.Material = Enum.Material.Neon
		badge.CanCollide, badge.CanQuery, badge.CanTouch, badge.Massless, badge.CastShadow = false, false, false, true, false
		badge.CFrame = head.CFrame * CFrame.new(0, s * 0.58, -s * 0.57)
		for _, p in { cap, brim, badge } do
			local w = Instance.new("WeldConstraint")
			w.Part0 = head
			w.Part1 = p
			w.Parent = p
			p.Parent = rig.model
		end
	end
	-- StreamingEnabled: the rig arrives whole (root + limbs together) or not at all
	pcall(function()
		(rig.model :: any).ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	return rig.model, rig.root, rig.ground or 3
end

local function newOfficer(at: Vector3, role: string, case: any?, unit: any?): any?
	if #officers >= LS.MAX_OFFICERS + (if unit and unit.extraCap then unit.extraCap else 0) then
		return nil
	end
	seq += 1
	local id = (if unit and unit.prefix then unit.prefix else "police_") .. seq
	local model, root, ground = buildRig(id, nil, unit and unit.look)
	if not model or not root then
		return nil
	end
	local name = NAMES[(seq - 1) % #NAMES + 1]
	local o = {
		id = id,
		name = name,
		model = model,
		root = root,
		ground = ground,
		pos = at,
		yaw = 0,
		path = nil,
		speed = 0,
		cum = nil,
		t0 = now(),
		t0Server = serverNow(),
		role = role, -- "case" | "patrol" | "post" | "crew"
		case = case,
		state = "idle",
		act = "",
		nextThink = 0,
		nextSight = 0,
		nextRepath = 0,
		pauseUntil = 0,
		glimpse = nil,
		seeing = false,
		lastSeenPos = nil,
		goalT = -1e9,
		searchLeft = 0,
		grabAt = 0,
		burstUntil = 0,
		burstReady = 0,
		stopIssued = false,
		orderGiven = false, -- the 2+ star "손 들어!" (one per officer)
		created = now(),
		incident = nil,
	}
	model:SetAttribute("NpcId", id)
	model:SetAttribute("NpcKind", "police")
	model:SetAttribute("NpcGround", ground)
	model:SetAttribute("NpcAct", "idle")
	model:SetAttribute("NpcYaw", 0)
	model:SetAttribute("NpcLook", 0)
	model:SetAttribute("NpcTalk", 0)
	model:SetAttribute("LawOfficer", not (unit and unit.civil))
	model:SetAttribute("LawName", name)
	if unit then
		-- 특임대 / 119: their own brains (Law/Swat, Law/Rescue) through Police.unitThink[kind]
		o.unit = unit.kind
		o.civil = unit.civil == true
		o.name = if unit.names then unit.names[(seq - 1) % #unit.names + 1] else name
		model:SetAttribute("NpcKind", unit.kind)
		model:SetAttribute("LawName", o.name)
	end
	-- the whole rig (PivotTo), never the root alone: the engine records each limb's offset from the root
	-- when the rig enters the Workspace and limbs left at the build origin never follow (invisible NPC)
	model:PivotTo(CFrame.new(at + Vector3.new(0, ground, 0)))
	writeLeg(o)
	model.Parent = npcFolder
	table.insert(officers, o)
	return o
end

-- a non-police actor with the same motion contract (Law/City suspects / victims); not in `officers`
local function newActor(at: Vector3, id: string, hint: any, kind: string): any?
	local model, root, ground = buildRig(id, hint)
	if not model or not root then
		return nil
	end
	local o = { id = id, name = "", model = model, root = root, ground = ground, pos = at, yaw = 0, path = nil, speed = 0, cum = nil, t0 = now(), t0Server = serverNow(), act = "", role = kind }
	model:SetAttribute("NpcId", id)
	model:SetAttribute("NpcKind", kind)
	model:SetAttribute("NpcGround", ground)
	model:SetAttribute("NpcAct", "idle")
	model:SetAttribute("NpcYaw", 0)
	model:PivotTo(CFrame.new(at + Vector3.new(0, ground, 0)))
	writeLeg(o)
	model.Parent = npcFolder
	return o
end
Police.newActor = newActor
Police.moveAlong = moveAlong
Police.setAct = setAct

function Police.removeActor(o: any)
	o.gone = true
	if o.model then
		o.model:Destroy()
		o.model = nil
	end
end

local function removeOfficer(o: any)
	o.gone = true
	if o.model then
		o.model:Destroy()
		o.model = nil
	end
	local i = table.find(officers, o)
	if i then
		table.remove(officers, i)
	end
	if o.case then
		local j = table.find(o.case.units, o)
		if j then
			table.remove(o.case.units, j)
		end
	end
end

-- an officer / 특임대 / 119 crew member who went down (GwangalliGameplay/Fight: HP 0, Fight calls this):
-- out of every brain and every officer loop at once (gone; the case's staffing sends somebody else),
-- the body stays where he fell (NpcDown: every client keeps it lying, GwangalliNPCClient) until the
-- ambulance carries him off (Fight.tell "ems" pickup -> downHold 0) or the time is up; then the rig goes
local downed: { any } = {}
function Police.knocked(id: string, dx: number, dz: number, downS: number): boolean
	local o = nil
	for _, x in officers do
		if x.id == id and not x.gone then
			o = x
			break
		end
	end
	if not o or not o.model or o.seated then
		return false -- (one sitting in a car is not knocked out: Fight floors his HP)
	end
	local case = o.case
	if case and case.stopBy == o and case.player then
		case.stopBy = nil
		Law.push(case.player, { kind = "stopEnd" })
	end
	if o.incident then
		o.incident.officer = nil -- (Law/City lets the incident go on without him)
		o.incident = nil
	end
	standAt(o, legPos(o, now()))
	local m = o.model
	m:SetAttribute("NpcKnock", string.format("%.2f|%.3f|%.3f|%s", serverNow(), dx or 0, dz or -1, "knockdown"))
	m:SetAttribute("NpcDown", serverNow() + downS)
	m:SetAttribute("NpcLook", 0)
	m:SetAttribute("LawOfficer", false)
	m:SetAttribute("LawState", "down")
	if o.bubble then
		o.bubble.Enabled = false -- (a body says nothing)
	end
	o.bubbleT = nil
	o.gone = true
	o.state = "down"
	o.downUntil = now() + downS
	local i = table.find(officers, o)
	if i then
		table.remove(officers, i)
	end
	if case then
		local j = table.find(case.units, o)
		if j then
			table.remove(case.units, j)
		end
	end
	table.insert(downed, o)
	-- (performance: at most 6 bodies, the one down longest goes first)
	if #downed > 6 then
		local old = table.remove(downed, 1)
		if old.model then
			old.model:Destroy()
			old.model = nil
		end
	end
	return true
end

-- the ambulance is coming (secs: he lies there that long at most) / took him (0: gone now)
function Police.downHold(id: string, secs: number)
	for _, o in downed do
		if o.id == id then
			if secs <= 0 then
				o.downUntil = now()
			else
				o.downUntil = math.max(o.downUntil, now() + secs)
				if o.model then
					o.model:SetAttribute("NpcDown", serverNow() + (o.downUntil - now()))
				end
			end
			return
		end
	end
end

local function downedTick()
	for i = #downed, 1, -1 do
		local o = downed[i]
		if now() >= o.downUntil then
			table.remove(downed, i)
			if o.model then
				o.model:Destroy()
				o.model = nil
			end
		end
	end
end

local function assignGoal(o: any, pos: Vector3, speed: number, wrong: number?)
	-- (feet on the floor: a goal from the suspect's root is ~3 studs up)
	pos = feetAt(pos)
	-- from where the officer is right now (a stale position would make the new leg start with a jump)
	o.pos = legPos(o, now())
	local pts = routePts(o.pos, pos, { wrong = wrong })
	if pts then
		moveAlong(o, pts, speed)
	else
		moveAlong(o, { o.pos, pos }, speed)
	end
	o.goal = pos
end

-------------------------------------------------------------------------------------------------
-- Patrol cars
-------------------------------------------------------------------------------------------------
-- The template is the map's Car_Police. Its nose points along the model's -X (the map's car
-- convention), so CarRoot is turned until ITS -Z is the nose: D.cframe(pos, heading) and the client
-- sampler (GwangalliLawCars) then drive the car nose first. The car has no Seat parts: the front
-- seats are measured from the interior (steering wheel side = the driver, Korea: left).
-- Officers are built at CREW_SCALE so a seated officer's head stays under the roof.
local seatOffsets: { Vector3 } = {} -- seated officer ROOT positions in CarRoot space (1 driver, 2 passenger)
local doorOffsets: { Vector3 } = {} -- just outside each front door, on the road (CarRoot space)
local sillOffsets: { Vector3 } = {} -- in the door opening, at floor height (CarRoot space)
local carHalfW = 3.6

local function buildTemplate(src: Instance?): Model?
	if not src then
		return nil
	end
	local ok, clone = pcall(function()
		return (src :: Model):Clone()
	end)
	if not ok or not clone then
		return nil
	end
	for _, d in clone:GetDescendants() do
		if d:IsA("ProximityPrompt") or d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Sound") or d:IsA("Weld") or d:IsA("WeldConstraint") or d:IsA("Motor6D") then
			d:Destroy()
		elseif d:IsA("Seat") or d:IsA("VehicleSeat") then
			pcall(function()
				(d :: any).Disabled = true
			end)
		end
	end
	local pv = clone:GetPivot()
	-- the nose: the Nose / FrontBumper part seen from the pivot (fallback: the model's -X)
	local noseL = Vector3.new(-1, 0, 0)
	local nose = clone:FindFirstChild("Nose") or clone:FindFirstChild("FrontBumper")
	if nose and nose:IsA("BasePart") then
		local l = pv:PointToObjectSpace(nose.Position)
		local f = Vector3.new(l.X, 0, l.Z)
		if f.Magnitude > 1 then
			noseL = f.Unit
		end
	end
	local noseW = pv:VectorToWorldSpace(noseL)
	local rootCF = if D then D.cframe(pv.Position, noseW) else CFrame.lookAt(pv.Position, pv.Position + noseW)
	-- height of the root above the road: the bottom of the bounding box (the tyres)
	local okB, bcf, bsize = pcall(function()
		return clone:GetBoundingBox()
	end)
	if okB then
		local lb = rootCF:PointToObjectSpace(bcf.Position)
		carOffsetY = math.clamp(-(lb.Y - bsize.Y * 0.5), 0.5, 5)
		carHalfW = math.clamp(math.min(bsize.X, bsize.Z) * 0.5, 2.4, 4.5)
	end
	-- front seats from the interior: the steering wheel (WheelRim parts) and the floor (Carpet)
	local wheel, wheelN, floorY = Vector3.zero, 0, nil
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			if d.Name == "WheelRim" or d.Name == "SteeringWheel" then
				wheel += rootCF:PointToObjectSpace(d.Position)
				wheelN += 1
			elseif d.Name == "Carpet" then
				local l = rootCF:PointToObjectSpace(d.Position)
				floorY = l.Y + d.Size.Y * 0.5
			end
		end
	end
	local dx, dz = -carHalfW * 0.32, -0.3
	if wheelN > 0 then
		wheel /= wheelN
		dx = if math.abs(wheel.X) > 0.3 then wheel.X else dx
		dz = wheel.Z + 1.15 -- behind the wheel (+Z = towards the back)
	end
	local fy = floorY or (-carOffsetY + 1.1)
	-- sitting (the R15 sit track bends the legs, the torso stays where the root puts it): thighs level
	-- with the hips (1.0 below the root) and 1.0 thick -> the seat of the trousers is 1.5 x scale under
	-- the root; just over the floor so cap + head (2.6 x scale above the root) stay under the roof
	local rootY = fy + 0.1 + 1.5 * CREW_SCALE
	seatOffsets = { Vector3.new(dx, rootY, dz), Vector3.new(-dx, rootY, dz) }
	sillOffsets = { Vector3.new(dx * 1.9, fy, dz + 0.2), Vector3.new(-dx * 1.9, fy, dz + 0.2) }
	local sideOut = carHalfW + 1.5
	doorOffsets = { Vector3.new(math.sign(dx) * sideOut, -carOffsetY, dz + 0.6), Vector3.new(-math.sign(dx) * sideOut, -carOffsetY, dz + 0.6) }

	local root = Instance.new("Part")
	root.Name = "CarRoot"
	root.Size = Vector3.new(1, 1, 1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = rootCF
	root.Parent = clone
	-- welded to the anchored root with fixed offsets (like the taxi): moving the root moves the car
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") and d ~= root then
			local w = Instance.new("Weld")
			w.Name = "LawWeld"
			w.Part0 = root
			w.Part1 = d
			w.C0 = root.CFrame:ToObjectSpace(d.CFrame)
			w.C1 = CFrame.new()
			w.Parent = d
			d.Anchored = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
		end
		for _, tag in CollectionService:GetTags(d) do
			CollectionService:RemoveTag(d, tag)
		end
	end
	for _, tag in CollectionService:GetTags(clone) do
		CollectionService:RemoveTag(clone, tag)
	end
	clone.PrimaryPart = root
	clone:SetAttribute("VehicleKind", nil)
	clone:SetAttribute("NoDrive", true)
	-- the light bar: the template's own LightRed / LightBlue get a glow (the client flashes them);
	-- a car without one gets a small bar on the roof
	local lamps = 0
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") and (d.Name == "LightRed" or d.Name == "LightBlue") then
			lamps += 1
			d:SetAttribute("LawLamp", if d.Name == "LightRed" then "r" else "b")
			d.Material = Enum.Material.Neon
			local l = Instance.new("PointLight")
			l.Name = "LawGlow"
			l.Color = d.Color
			l.Range = 22
			l.Brightness = 4
			l.Shadows = false
			l.Parent = d
		end
	end
	if lamps == 0 and okB then
		local top = rootCF * CFrame.new(0, -carOffsetY + bsize.Y + 0.15, 0.4)
		for _, spec in { { "LightRed", Color3.fromRGB(255, 40, 50), -0.7, "r" }, { "LightBlue", Color3.fromRGB(40, 90, 255), 0.7, "b" } } do
			local p = Instance.new("Part")
			p.Name = spec[1]
			p.Size = Vector3.new(1.2, 0.32, 0.55)
			p.Material = Enum.Material.Neon
			p.Color = spec[2]
			p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow, p.Massless = false, false, false, false, true
			p.CFrame = top * CFrame.new(spec[3], 0, 0)
			p:SetAttribute("LawLamp", spec[4])
			local l = Instance.new("PointLight")
			l.Name = "LawGlow"
			l.Color = p.Color
			l.Range = 22
			l.Brightness = 4
			l.Parent = p
			local w = Instance.new("Weld")
			w.Part0 = root
			w.Part1 = p
			w.C0 = root.CFrame:ToObjectSpace(p.CFrame)
			w.C1 = CFrame.new()
			w.Parent = p
			p.Parent = clone
		end
	end
	-- every client sees a patrol car from afar (siren lights up the road before it arrives)
	pcall(function()
		(clone :: any).ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)
	return clone
end

-- car templates by kind: "police" (the map's Car_Police), "swat" (the same car, dark paint, four seats),
-- "ambulance" (the hospital bay's Car_Ambulance, four seats). Each keeps its own seat / door geometry
-- (c.T); the police one is also the module's default (seatOffsets ...).
local templates: { [string]: any } = {}
local function tplData(kind: string?): any?
	kind = kind or "police"
	local T = templates[kind]
	if T then
		return T
	end
	local map = workspace:FindFirstChild("Gwangalli")
	local src = nil
	if kind == "ambulance" then
		local h = map and map:FindFirstChild("hospital")
		local cl = h and h:FindFirstChild("광안 메디컬 의원")
		local bay = cl and cl:FindFirstChild("AmbulanceBay")
		src = bay and bay:FindFirstChild("Car_Ambulance")
		if not src and map then
			for _, d in map:GetDescendants() do
				if d:IsA("Model") and d.Name == "Car_Ambulance" then
					src = d
					break
				end
			end
		end
	else
		local roads = map and map:FindFirstChild("roads")
		local parked = roads and roads:FindFirstChild("ParkedVehicles")
		src = parked and parked:FindFirstChild("Car_Police")
	end
	-- the builder writes the module's geometry globals: keep the police ones as they were
	local keep = { seatOffsets, sillOffsets, doorOffsets, carHalfW, carOffsetY }
	local model = buildTemplate(src)
	if not model then
		return nil
	end
	T = { kind = kind, model = model, seats = seatOffsets, sills = sillOffsets, doors = doorOffsets, halfW = carHalfW, offY = carOffsetY, nSeats = 2 }
	if kind ~= "police" then
		-- the rear bench (+Z = towards the back) for the team / the crew
		local back = Vector3.new(0, 0, 3.3)
		T.seats = { T.seats[1], T.seats[2], T.seats[1] + back, T.seats[2] + back }
		T.sills = { T.sills[1], T.sills[2], T.sills[1] + back, T.sills[2] + back }
		T.doors = { T.doors[1], T.doors[2], T.doors[1] + back, T.doors[2] + back }
		T.nSeats = 4
	end
	if kind == "swat" then
		-- 특임대: charcoal body (the light bar and glass keep their colour)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and not d:GetAttribute("LawLamp") and d.Transparency < 0.3 then
				local c = d.Color
				if c.R + c.G + c.B > 1.6 or (c.B > 0.45 and c.B > c.R + 0.15) then
					d.Color = Color3.fromRGB(34, 36, 42)
				end
			end
		end
	end
	if kind ~= "police" then
		seatOffsets, sillOffsets, doorOffsets, carHalfW, carOffsetY = keep[1], keep[2], keep[3], keep[4], keep[5]
	else
		carTemplate = model
	end
	templates[kind] = T
	return T
end

local function findTemplate(): Model?
	local T = tplData("police")
	return T and T.model or nil
end

local function seatsOf(c: any): any
	return (c and c.T) or templates.police or { seats = seatOffsets, sills = sillOffsets, doors = doorOffsets, halfW = carHalfW, offY = carOffsetY, nSeats = 2 }
end

local function carHeights(q: Vector3): number?
	return groundAt(Vector3.new(q.X, 9, q.Z), 6) + carOffsetY
end

-- the path goes out on the model (LawPath "x,y,z,t;..." + LawT0 = server time of t = 0): every
-- client re-samples it each frame (GwangalliLawCars) and the server moves the root every Heartbeat
local function setCarPath(c: any, path: any)
	c.path = path
	c.t0 = now()
	c.done = false
	-- a U-turn in this path: no route re-plan before the arc is through (carRoute's uturnT)
	c.planHold = if path.uturnT then now() + path.uturnT else nil
	c.serial = (c.serial or 0) + 1
	local m = c.model
	m:SetAttribute("LawPath", D.encode(path.pts, path.times))
	m:SetAttribute("LawT0", serverNow())
	m:SetAttribute("LawSerial", c.serial)
	m:SetAttribute("LawCarMoving", true)
end

-- the car is standing where it is (no path): clients hold the root where the server put it
local function clearCarPath(c: any)
	if c.path then
		local p, dir = D.sample(c.path.pts, c.path.times, math.min(now() - c.t0, c.path.total))
		c.restCF = D.cframe(p, dir)
	end
	c.path = nil
	c.done = true
	c.serial = (c.serial or 0) + 1
	local m = c.model
	m:SetAttribute("LawPath", nil)
	m:SetAttribute("LawSerial", c.serial)
	m:SetAttribute("LawCarMoving", false)
end

local function carPos(c: any): (Vector3, Vector3)
	if c.path then
		local t = math.min(now() - c.t0, c.path.total)
		return D.sample(c.path.pts, c.path.times, t)
	end
	local cf = c.restCF or c.model:GetPivot()
	return cf.Position, cf.LookVector
end

-- current speed along the path (studs/s)
local function carSpeed(c: any): number
	if not c.path or c.done then
		return 0
	end
	local t = now() - c.t0
	if t >= c.path.total then
		return 0
	end
	local a = D.posAt(c.path.pts, c.path.times, math.max(0, t - 0.1))
	local b = D.posAt(c.path.pts, c.path.times, math.min(c.path.total, t + 0.1))
	local dt = math.min(c.path.total, t + 0.1) - math.max(0, t - 0.1)
	return if dt > 1e-3 then flat(a, b) / dt else 0
end

-- a lane location near `p` running the way the car is heading (no U-turn / wrong-way merge)
local function headingLoc(p: Vector3, dir: Vector3, maxDist: number): any?
	local best, bestD = nil, math.huge
	for _, e in D.edgesNear(graph, p, maxDist) do
		local k = graph.eKind[e]
		if (k == D.KIND.lane or k == D.KIND.bus or k == D.KIND.straight or k == D.KIND.turn) and graph.eLen[e] > 2 then
			local ed = D.edgeDir(graph, e)
			if ed:Dot(dir) > 0.55 then
				local a = graph.pos[graph.eFrom[e]]
				local s = math.clamp(Vector3.new(p.X - a.X, 0, p.Z - a.Z):Dot(ed), 0.5, graph.eLen[e] - 0.5)
				local q = D.pointOn(graph, e, s)
				local d = flat(p, q)
				if d < bestD and d <= maxDist then
					best, bestD = { edge = e, s = s, point = q, dist = d }, d
				end
			end
		end
	end
	return best
end

-- lanes from the car (or a far start up the road when c = nil) to the kerb nearest `pos`.
-- From a moving car the new path starts at the car, keeps its heading for a few studs and merges
-- into a lane AHEAD of it at its current speed: a re-plan never jerks the heading or the speed.
local function carRoute(c: any?, pos: Vector3, opts: any?): any?
	if not D or not graph then
		return nil
	end
	local o = opts or {}
	local okL, toLoc = pcall(D.nearestLocation, graph, pos, { maxDist = 90, side = pos, kerbOnly = o.kerb ~= false })
	if not okL or not toLoc then
		okL, toLoc = pcall(D.nearestLocation, graph, pos, { maxDist = 150 })
	end
	if not okL or not toLoc then
		return nil
	end
	-- stop short of the spot (never on top of the suspect) and behind the cars already there; a short
	-- lane piece continues on the lane that leads into it
	if o.stopBack and o.stopBack > 0 then
		local e, sv = toLoc.edge, toLoc.s - o.stopBack
		local guard = 0
		while sv < 4 and guard < 6 do
			guard += 1
			local prev = nil
			local ed = D.edgeDir(graph, e)
			for _, ie in graph.inn[graph.eFrom[e]] or {} do
				local k = graph.eKind[ie]
				if (k == D.KIND.lane or k == D.KIND.bus or k == D.KIND.straight) and D.edgeDir(graph, ie):Dot(ed) > 0.7 then
					prev = ie
					break
				end
			end
			if not prev then
				break
			end
			sv += graph.eLen[prev]
			e = prev
		end
		sv = math.clamp(sv, math.min(4, graph.eLen[e] * 0.5), math.max(graph.eLen[e] - 4, graph.eLen[e] * 0.5))
		toLoc = { edge = e, s = sv, point = D.pointOn(graph, e, sv), dist = toLoc.dist }
	end
	local pts
	local v0 = o.v0 or 26
	local uturnLen: number? = nil -- the U-turn arc's length (cp -> the lane the other way) when one is taken
	if c then
		local cp, dir = carPos(c)
		local v = carSpeed(c)
		v0 = v
		local lead = math.clamp(v * 0.6, 5, 22)
		local fromLoc = headingLoc(cp + dir * lead, dir, 26)
		if not fromLoc then
			local okF, fl = pcall(D.nearestLocation, graph, cp + dir * lead, { maxDist = 60 })
			fromLoc = okF and fl or nil
		end
		local bestLen = math.huge
		if fromLoc then
			local okR, rp = pcall(D.route, graph, fromLoc, toLoc)
			if okR and rp and #rp >= 2 then
				pts = { cp, cp + dir * math.min(3, lead * 0.5) }
				for _, q in rp do
					table.insert(pts, q)
				end
				bestLen = D.polyLength(pts)
			end
		end
		-- the target is behind (or the lanes only reach it the long way round): a police U-turn —
		-- slow, a half circle over to the lane running the other way, then the route from there
		local toT = Vector3.new(toLoc.point.X - cp.X, 0, toLoc.point.Z - cp.Z)
		local straight = toT.Magnitude
		if straight > 1 and (toT.Unit:Dot(dir) < -0.15 or bestLen > straight * 2.2 + 120) then
			local left = -D.rightOf(dir)
			-- (braking distance first: the speed never drops in a jump)
			local a0 = cp + dir * math.clamp(v * v / 22, 3, 60)
			-- the lane running the other way: right across, or past a wider median
			local opp = headingLoc(a0 + left * 9, -dir, 16) or headingLoc(a0 + left * 18, -dir, 16) or headingLoc(a0 + dir * 25 + left * 12, -dir, 22)
			if opp then
				local w = math.clamp((opp.point - a0):Dot(left), 4, 30)
				local back = opp.point - dir * 2
				local okU, ru = pcall(D.route, graph, opp, toLoc)
				if okU and ru and #ru >= 2 then
					local up = { cp, cp:Lerp(a0, 0.5), a0, a0 + dir * (w * 0.45) + left * (w * 0.35), a0 + dir * (w * 0.5) + left * (w * 0.75), a0 + dir * (w * 0.2) + left * w, back }
					for _, q in ru do
						table.insert(up, q)
					end
					local ulen = D.polyLength(up)
					if ulen < bestLen then
						pts = up
						bestLen = ulen
						uturnLen = D.polyLength({ up[1], up[2], up[3], up[4], up[5], up[6], up[7] })
					end
				end
			end
		end
	else
		local okA, ap = pcall(D.approach, graph, toLoc, o.want or (LS.CAR_SPAWN[1] + rnd() * (LS.CAR_SPAWN[2] - LS.CAR_SPAWN[1])), 140)
		if okA and ap and #ap >= 2 then
			pts = ap
		end
	end
	if not pts then
		return nil
	end
	local okP, path = pcall(D.buildPath, pts, { cruise = (o.cruise or 40), v0 = v0, v1 = o.v1 or 0, pullOver = if o.kerb ~= false then { offset = 2.2, len = 24 } else nil, heights = carHeights })
	if okP and path and uturnLen then
		-- when the arc is done (setCarPath holds re-plans until then: a re-plan mid-arc would swing
		-- the car back to the lane it is turning away from). 0.9: the smoothing shortens the arc a bit
		local acc = 0
		for i = 2, #path.pts do
			acc += flat(path.pts[i - 1], path.pts[i])
			if acc >= uturnLen * 0.9 then
				path.uturnT = path.times[i] + 0.3
				break
			end
		end
	end
	return if okP then path else nil
end

-- a dispatch start far up the road and out of every player's sight (never in front of the player)
-- (fallback: the farthest start nobody has a line on; a seen start only for a unit car, 119 /
-- 특임대, which must come; police / patrol cars wait for staff()'s next pass instead)
local function spawnRoute(pos: Vector3, cruise: number, back: number?, allowSeen: boolean?): any?
	local best, bestScore = nil, -math.huge
	for try = 1, 5 do
		local want = if try == 1 then nil else ({ 420, 520, 330, 600 })[try - 1]
		local path = carRoute(nil, pos, { cruise = cruise, v0 = 30, want = want, stopBack = back })
		if path then
			local ok, minD, seen = unseenStart(path.pts[1], 220, 360)
			if ok then
				return path
			end
			local score = minD - (if seen then 400 else 0)
			if (allowSeen or not seen) and score > bestScore then
				best, bestScore = path, score
			end
		end
	end
	return best
end

-- crew seats ------------------------------------------------------------------------------------
local function carRootOf(c: any): BasePart?
	local m = c.model
	local r = m and m.PrimaryPart
	return if r and r.Parent then r else nil
end

local function carCF(c: any): CFrame
	local r = carRootOf(c)
	if r then
		return r.CFrame
	end
	local p, dir = carPos(c)
	return D.cframe(p, dir)
end

-- the whole rig to the seat (PivotTo, see newOfficer)
local function placeSeated(o: any)
	local c = o.car
	if not c or not o.seated or not o.model then
		return
	end
	local cf = carCF(c) * CFrame.new(seatsOf(c).seats[o.seated] or Vector3.zero)
	o.model:PivotTo(cf)
	o.pos = cf.Position - Vector3.new(0, o.ground, 0)
end

-- StreamingEnabled: a seated crew streams like its Persistent car (seen in the cabin from the car's
-- first frame at any distance); back to Atomic (buildRig's mode) once on foot
local function crewStreaming(o: any, seated: boolean)
	if o.model then
		pcall(function()
			(o.model :: any).ModelStreamingMode = if seated then Enum.ModelStreamingMode.Persistent else Enum.ModelStreamingMode.Atomic
		end)
	end
end

local function seatOfficer(c: any, o: any, slot: number)
	o.car = c
	o.seated = slot
	o.role = "crew"
	o.state = "seated"
	o.path, o.speed, o.cum = nil, 0, nil
	if not table.find(c.crew, o) then
		table.insert(c.crew, o)
	end
	if o.case then
		local i = table.find(o.case.units, o)
		if i then
			table.remove(o.case.units, i)
		end
	end
	local off = seatsOf(c).seats[slot] or Vector3.zero
	-- NpcSeat = "<car model name>|x,y,z": the client keeps the rig on the seat of the moving car
	o.model:SetAttribute("NpcSeat", string.format("%s|%.2f,%.2f,%.2f", c.model.Name, off.X, off.Y, off.Z))
	crewStreaming(o, true)
	setAct(o, "sit")
	placeSeated(o)
end

local function freeSlot(c: any): number?
	for slot = 1, seatsOf(c).nSeats or 2 do
		local used = false
		for _, o in c.crew do
			if not o.gone and (o.seated == slot or o.boardSlot == slot) then
				used = true
			end
		end
		if not used then
			return slot
		end
	end
	return nil
end

local function seatedCount(c: any): number
	local n = 0
	for _, o in c.crew do
		if not o.gone and o.seated then
			n += 1
		end
	end
	return n
end

-- world points of a door (CarRoot space -> world, the road height under the door)
local function doorWorld(c: any, slot: number): (Vector3, Vector3, Vector3)
	local cf = carCF(c)
	local T = seatsOf(c)
	local seatFeet = (cf * CFrame.new((T.seats[slot] or Vector3.zero) - Vector3.new(0, 3 * CREW_SCALE, 0))).Position
	local sill = (cf * CFrame.new(T.sills[slot] or Vector3.zero)).Position
	local out = (cf * CFrame.new(T.doors[slot] or Vector3.new(T.halfW + 1.5, -T.offY, 0))).Position
	out = Vector3.new(out.X, groundAt(out, out.Y), out.Z)
	return seatFeet, sill, out
end

-- getting out: seat -> door opening -> the road beside the door, at a step's pace, then a beat
-- standing there before running (the exit is always seen, never a teleport)
local function exitOfficer(o: any)
	local c = o.car
	if not c or not o.seated then
		return
	end
	local slot = o.seated
	local seatFeet, sill, out = doorWorld(c, slot)
	o.seated = nil
	o.boardSlot = nil
	o.pos = seatFeet
	moveAlong(o, { seatFeet, sill, out }, 3.2)
	o.model:SetAttribute("NpcSeat", nil)
	crewStreaming(o, false)
	o.state = "exiting"
	-- out of the door, then a look toward the suspect's last known spot (body + head) before the run
	local case = c.case
	local look = (case and case.knownPos) or c.dismountTarget
	o.exitDone = now() + (flat(seatFeet, sill) + flat(sill, out)) / 3.2 + (if look then 0.8 + rnd() * 0.4 else 0.45)
	faceTo(o, if look and flat(out, look) > 1.5 then look else out + (out - seatFeet))
	if look and case and case.player then
		o.model:SetAttribute("NpcLook", case.player.UserId)
	end
end

-- getting in: walk to the door, step in, sit (boarding officers keep their slot); speed = a run back
-- to the car when the suspect drives off (default: a brisk walk)
local function boardOfficer(o: any, c: any, speed: number?)
	if o.state == "board" and o.car == c then
		return true
	end
	o.boardSpeed = speed or 9.5
	local slot = freeSlot(c)
	if not slot then
		return false
	end
	o.car = c
	o.boardSlot = slot
	o.role = "crew"
	o.state = "board"
	if not table.find(c.crew, o) then
		table.insert(c.crew, o)
	end
	if o.case then
		local i = table.find(o.case.units, o)
		if i then
			table.remove(o.case.units, i)
		end
	end
	local _, _, out = doorWorld(c, slot)
	assignGoal(o, out, o.boardSpeed, nil)
	o.boardStep = "walk"
	o.boardT = now()
	return true
end

-- the place in the line of parked case cars: the lowest index nobody uses (cars are 16.6 long)
local CAR_GAP = 19
local function nextSlot(case: any?): number
	if not case then
		return 0
	end
	local used = {}
	for _, c in case.cars do
		if not c.gone and c.state ~= "leave" and c.slotIdx then
			used[c.slotIdx] = true
		end
	end
	local k = 0
	while used[k] do
		k += 1
	end
	return k
end

-- the light bar (LawSiren: the client flashes the lamps) and the siren sound together; a patrol car
-- (made without a case) gets its Sound when it joins one
local function setSiren(model: Model, on: boolean)
	model:SetAttribute("LawSiren", on)
	local host = model.PrimaryPart
	local snd = host and host:FindFirstChild("LawSiren")
	if on and host and not snd then
		local s = Instance.new("Sound")
		s.Name = "LawSiren"
		s.SoundId = "rbxassetid://5736468541"
		s.Looped = true
		s.Volume = 0.55
		s.RollOffMaxDistance = 420
		s.RollOffMinDistance = 24
		s.Parent = host
		snd = s
	end
	if snd and snd:IsA("Sound") then
		pcall(function()
			if on then
				if not snd.IsPlaying then
					snd:Play()
				end
			else
				snd:Stop()
			end
		end)
	end
end

local function newCar(case: any?, pos: Vector3, role: string, unit: any?): any?
	if #cars >= LS.MAX_CARS + (if unit and unit.extraCars then unit.extraCars else 0) or not loadNav() or not D or not graph then
		return nil
	end
	local wantCrew = if unit and unit.crew then unit.crew elseif case then 2 else 1
	if #officers + 1 > LS.MAX_OFFICERS + (if unit and unit.extraCap then unit.extraCap else 0) then
		return nil -- never a car without a driver
	end
	local T = tplData(if unit and unit.car then unit.car else "police")
	local tpl = T and T.model
	if not tpl then
		return nil
	end
	local slotIdx = nextSlot(case)
	local path = spawnRoute(pos, 44 * (if case then LS.TIERS[math.max(1, case.stars)].carSpeed else 0.8), 9 + CAR_GAP * slotIdx, unit ~= nil)
	if not path then
		return nil
	end
	seq += 1
	local car = tpl:Clone()
	car.Name = "LawPatrolCar_" .. seq
	car:SetAttribute("LawCar", true)
	car:SetAttribute("LawUnit", if unit and unit.label then unit.label .. " " .. (1 + seq % 9) else "광안" .. (10 + seq % 80))
	if unit then
		car:SetAttribute("LawCarKind", unit.kind)
	end
	local p0, d0 = D.sample(path.pts, path.times, 0)
	-- the whole model (PivotTo): every welded part and lamp moves with the root before it is parented
	car:PivotTo(D.cframe(p0, d0))
	setSiren(car, case ~= nil)
	car.Parent = carsFolder
	local c = { id = "car_" .. seq, model = car, path = nil, t0 = now(), done = false, case = case, role = role, state = "respond", crew = {}, nextPlan = now() + 2.5, nextSight = 0, glimpse = nil, slowT = 0, created = now(), dismounted = false, goal = pos, slotIdx = slotIdx, T = T, unit = unit and unit.kind or nil }
	setCarPath(c, path)
	table.insert(cars, c)
	if case then
		table.insert(case.cars, c)
	end
	-- the crew is in the car from the first frame: driver (and partner)
	for slot = 1, wantCrew do
		if #officers >= LS.MAX_OFFICERS then
			break
		end
		local o = newOfficer(p0, if case then "case" else "patrol", case, unit)
		if o then
			seatOfficer(c, o, slot)
		end
	end
	return c
end

local function removeCar(c: any)
	c.gone = true
	for _, o in c.crew do
		if not o.gone and (o.seated or o.state == "board" or o.state == "exiting" or o.role == "crew") then
			removeOfficer(o)
		elseif not o.gone then
			o.car = nil
		end
	end
	if c.model then
		c.model:Destroy()
	end
	local i = table.find(cars, c)
	if i then
		table.remove(cars, i)
	end
	if c.case then
		local j = table.find(c.case.cars, c)
		if j then
			table.remove(c.case.cars, j)
		end
	end
end

local function driveAway(c: any)
	c.state = "leave"
	setSiren(c.model, false)
	local cp, dir = carPos(c)
	local loc = headingLoc(cp + dir * 6, dir, 30)
	if not loc then
		local okL, l = pcall(D.nearestLocation, graph, cp, { maxDist = 60 })
		loc = okL and l or nil
	end
	if loc then
		local okF, pts = pcall(D.forward, graph, loc, 300)
		if okF and pts and #pts >= 2 then
			table.insert(pts, 1, cp)
			local parkedNow = c.done or not c.path
			local okP, path = pcall(D.buildPath, pts, { cruise = 34, v0 = carSpeed(c), v1 = 30, pullOut = if parkedNow then { offset = 2.2, len = 22 } else nil, heights = carHeights })
			if okP and path then
				setCarPath(c, path)
				c.leaveAt = now() + path.total
				return
			end
		end
	end
	removeCar(c)
end

-- leaving: the crew outside walks back and gets in first (up to 20 s), then the car drives off
local function carLeave(c: any)
	if c.state == "leave" or c.state == "recall" or c.state == "transport" then
		return
	end
	local out = false
	for _, o in c.crew do
		if not o.gone and not o.seated and o.state ~= "board" then
			if o.state ~= "cuffwalk" and boardOfficer(o, c) then
				out = true
			end
		elseif not o.gone and o.state == "board" then
			out = true
		end
	end
	if out then
		c.state = "recall"
		c.recallUntil = now() + 20
		setSiren(c.model, false)
		return
	end
	driveAway(c)
end

-------------------------------------------------------------------------------------------------
-- Cases
-------------------------------------------------------------------------------------------------
local function caseOf(player: Player, create: boolean): any?
	local c = cases[player]
	if not c and create then
		c = { player = player, units = {}, cars = {}, stars = 0, created = now(), knownPos = nil, knownT = -1e9, lastReinforce = now(), lastBlock = 0, stopBy = nil }
		cases[player] = c
	end
	return c
end

local function tierOf(case: any): any
	return LS.TIERS[math.clamp(case.stars, 1, 5)]
end

-- the dispatcher's position feed: for a while after a report / a sighting / a fresh witness call
-- (case.radioUntil, LS.TIERS[*].radio) the units get the suspect's area every few seconds, not only
-- the first reported spot. An area, not the exact spot (jitter), and never while out of that window
-- (a suspect who stays unseen long enough still gets away)
local function radioFix(case: any, player: Player)
	if not case.radioUntil or now() >= case.radioUntil or now() < (case.nextRadio or 0) then
		return
	end
	local t = tierOf(case)
	case.nextRadio = now() + math.max(2, t.repath * 3)
	local pp = Law.posOf(player)
	if not pp or (case.knownPos and flat(pp, case.knownPos) < 20) then
		return
	end
	local j = math.max(8, 30 - case.stars * 4)
	case.knownPos = pp + Vector3.new((rnd() - 0.5) * j, 0, (rnd() - 0.5) * j)
	case.knownT = now()
	for _, o in case.units do
		if not o.gone and not o.seeing and o.state ~= "chase" and o.state ~= "stop" and o.state ~= "cuffwalk" and not o.radioAt then
			o.radioAt = now() + 1 + rnd() * 1.5
		end
	end
end

-- keep the dispatcher's feed open (secs; default: the tier's radio x3)
function Police.radioRefresh(player: Player, secs: number?)
	local case = cases[player]
	if case then
		case.radioUntil = math.max(case.radioUntil or 0, now() + (secs or tierOf(case).radio * 3))
	end
end

local function suspectInCar(player: Player): boolean
	if Police.testInCar then
		return true -- test only (Law debug "fakeCar"): the suspect counts as driving
	end
	local ch = player.Character
	local h = ch and ch:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.SeatPart ~= nil
end

-- a suspect who hit an officer: until when the officers go for the takedown (제압) instead of
-- ordering / watching (Fight.hitHooks "police_" -> onOfficerHit)
local violent: { [Player]: number } = {}
local function isViolent(player: Player): boolean
	return (violent[player] or 0) > now()
end

-- the suspect's speed (studs/s), tracked per tick
local speeds: { [Player]: { p: Vector3, t: number, v: number } } = {}
local function suspectSpeed(player: Player): number
	local r = speeds[player]
	return r and r.v or 0
end

-- a 1-star suspect seen driving off = 도주: +1 star, so staff() sends a patrol car and the road chase
-- (2+ stars) can start. A cooldown, not a one-shot (the stars can decay back to 1 in the same case)
local function carFlee(case: any, player: Player, pp: Vector3?)
	-- (not while an officer's stop order is open: the stop branch counts that flight itself)
	if case.stars == 1 and case.stopBy == nil and suspectInCar(player) and suspectSpeed(player) > 12 and now() - (case.carFleeT or -1e9) > 45 then
		case.carFleeT = now()
		Law.crime(player, "flee", { police = true, pos = pp })
	end
end

local function trackSpeeds()
	for _, p in Players:GetPlayers() do
		local pos = Law.posOf(p)
		if pos then
			local r = speeds[p]
			if r then
				local dt = now() - r.t
				if dt > 0.05 then
					local v = flat(pos, r.p) / dt
					r.v = r.v * 0.4 + v * 0.6
					r.p, r.t = pos, now()
				end
			else
				speeds[p] = { p = pos, t = now(), v = 0 }
			end
		end
	end
end

local function spawnFootUnits(case: any, n: number)
	local t = tierOf(case)
	for _ = 1, n do
		local at = hiddenSpot(case.knownPos, LS.SPAWN_RING[1], LS.SPAWN_RING[2], true)
		if not at then
			return
		end
		local o = newOfficer(at, "case", case)
		if not o then
			return
		end
		table.insert(case.units, o)
		o.state = "respond"
		o.goalT = case.knownT
		assignGoal(o, case.knownPos, 12.5 + case.stars * 0.6, t.wrongTurn)
	end
end

local function spawnCars(case: any, n: number)
	for _ = 1, n do
		local c = newCar(case, case.knownPos, "case")
		if not c then
			return
		end
	end
end

-- bring the case's units up to the tier's numbers
local function staff(case: any)
	if not case.knownPos then
		return
	end
	local t = tierOf(case)
	local foot = 0
	for _, o in case.units do
		if not o.gone and o.state ~= "leave" and o.role == "case" then
			foot += 1
		end
	end
	local carsN = 0
	for _, c in case.cars do
		if not c.gone and c.state ~= "leave" and c.role == "case" then
			carsN += 1
		end
	end
	-- an idle patrol officer nearby joins first (the radio call)
	if foot < t.foot and not Police.testCarsOnly then
		for _, o in officers do
			if foot >= t.foot then
				break
			end
			if o.role == "patrol" and not o.gone and flat(o.pos, case.knownPos) < 170 then
				o.role = "case"
				o.case = case
				o.state = "respond"
				o.goalT = case.knownT
				table.insert(case.units, o)
				say(o, "무전 받았다, 출동한다!")
				assignGoal(o, case.knownPos, 12.5 + case.stars * 0.6, t.wrongTurn)
				foot += 1
			end
		end
	end
	if foot < t.foot and not Police.testCarsOnly then
		spawnFootUnits(case, t.foot - foot)
	end
	if carsN < t.cars then
		spawnCars(case, t.cars - carsN)
	end
end

function Police.dispatch(player: Player, s: any, pos: Vector3?, kind: string?, by: string?)
	if not loadNav() then
		return
	end
	local case = caseOf(player, true)
	case.stars = s.stars
	case.knownPos = pos or s.knownPos or Law.posOf(player)
	case.knownT = now()
	-- the caller stays on the line for a while: the dispatcher keeps the units posted (radioFix)
	case.radioUntil = math.max(case.radioUntil or 0, now() + tierOf(case).radio * 5)
	case.kind = kind
	case.searchCenter = case.knownPos
	-- the dispatch line on the player's screen
	local area = Law.areaName(case.knownPos)
	local def = kind and LS.CRIMES[kind]
	Law.push(player, { kind = "radio", text = LS.fill(pick(LS.LINES.dispatch), { area = area, crime = def and def.label or "사건" }) })
	-- the units already on the case re-target after a short radio delay (1-2.5 s)
	for _, o in case.units do
		if not o.gone and o.state ~= "chase" and o.state ~= "stop" then
			o.radioAt = now() + 1 + rnd() * 1.5
		end
	end
	staff(case)
end

function Police.retier(player: Player, s: any, before: number, after: number)
	local case = caseOf(player, false)
	if not case then
		return
	end
	case.stars = after
	if after <= 0 then
		Police.standDown(player, s, "lost")
		return
	end
	if after > before then
		staff(case)
	end
end

function Police.standDown(player: Player, s: any, why: string)
	local case = cases[player]
	if not case then
		return
	end
	cases[player] = nil
	if why == "arrest" then
		violent[player] = nil
	end
	for _, o in table.clone(case.units) do
		if not o.gone then
			o.case = nil
			o.state = "leave"
			o.leaveAt = now() + 25
			if why == "lost" then
				say(o, pick(LS.LINES.give_up))
			end
			local away = ringNode(o.pos, 40, 80, Law.posOf(player))
			if away then
				assignGoal(o, away, 7.5, nil)
			end
		end
	end
	for _, c in table.clone(case.cars) do
		if not c.gone then
			c.case = nil
			if why ~= "arrest" then
				carLeave(c)
			else
				c.state = "hold" -- the arrest scene may use it for the transfer (Jail)
				c.holdUntil = now() + 20
			end
		end
	end
	for _, b in table.clone(blocks) do
		if b.case == case then
			b.expire = now() + 4
		end
	end
	if player.Parent then
		player:SetAttribute(LS.Attr.Chase, false)
	end
end

function Police.hunting(player: Player): boolean
	local case = cases[player]
	if not case then
		return false
	end
	for _, o in case.units do
		if not o.gone and o.state ~= "leave" then
			return true
		end
	end
	for _, c in case.cars do
		if not c.gone and c.state ~= "leave" then
			return true
		end
	end
	return false
end

function Police.sees(player: Player): boolean
	local pp = Law.posOf(player)
	if not pp then
		return false
	end
	for _, o in officers do
		if not o.gone and not o.civil and flat(o.pos, pp) < 45 and losClear(o.pos + Vector3.new(0, 4.6, 0), pp + Vector3.new(0, 1.5, 0)) then
			return true
		end
	end
	return false
end

-- the nearest live officer (for the arrest scene / transport)
function Police.nearestOfficer(pos: Vector3, maxDist: number): any?
	local best, bd = nil, maxDist
	for _, o in officers do
		if not o.gone and not o.civil then
			local d = flat(o.pos, pos)
			if d < bd then
				best, bd = o, d
			end
		end
	end
	return best
end

function Police.nearestCar(pos: Vector3, maxDist: number): any?
	local best, bd = nil, maxDist
	for _, c in cars do
		if not c.gone and c.model and c.model.Parent then
			local d = flat(carPos(c), pos)
			if d < bd then
				best, bd = c, d
			end
		end
	end
	return best
end

function Police.carModel(c: any): Model?
	return c and c.model or nil
end

function Police.releaseCar(c: any)
	if c and not c.gone then
		if c.state == "transport" then
			c.state = "hold" -- the ride is over: the crew gets back in and it drives off
		end
		carLeave(c)
	end
end

function Police.surrender(player: Player, s: any)
	local pp = Law.posOf(player)
	if not pp then
		return
	end
	local o = Police.nearestOfficer(pp, 40)
	if o then
		o.cuffSurrender = nil -- (a real surrender: never a stale stop-answer flag)
	end
	if o and o.case and o.case.player == player then
		o.state = "cuffwalk"
		say(o, "좋아요, 손 그대로 두세요.")
		assignGoal(o, pp, 9, nil)
	elseif o then
		o.role = "case"
		local case = caseOf(player, true)
		o.case = case
		table.insert(case.units, o)
		o.state = "cuffwalk"
		assignGoal(o, pp, 9, nil)
	else
		Law.push(player, { kind = "toast", text = "근처에 경찰이 없어요. 광안지구대에서 자수할 수도 있어요." })
	end
end

-- an answer that ends in handcuffs: the officer walks up first (thinkCase "cuffwalk" grabs at
-- GRAB_RANGE + 1), never cuffs from where the stop order was given
local function walkUpArrest(o: any, player: Player, pp: Vector3, surrender: boolean)
	if flat(pp, legPos(o, now())) <= LS.GRAB_RANGE + 1 then
		Law.arrest(player, { by = "npc", officer = o, surrender = surrender })
		return
	end
	o.state = "cuffwalk"
	o.cuffSurrender = surrender
	o.nextRepath = now() + 0.8
	assignGoal(o, pp, 9, nil)
end

function Police.stopAnswer(player: Player, s: any, choice: any): any
	local case = cases[player]
	local o = case and case.stopBy
	if not o or o.gone or o.state ~= "stop" then
		return { ok = false, err = "nostop" }
	end
	local pp = Law.posOf(player)
	if not pp or flat(pp, o.pos) > 16 then
		return { ok = false, err = "far" }
	end
	case.stopBy = nil
	if choice == "comply" then
		if Law.ticketable(player) then
			say(o, pick(LS.LINES.ticket))
			emote(o, "nod")
			Law.ticket(player, o.name)
			o.state = "leave"
			o.leaveAt = now() + 20
			return { ok = true, result = "ticket" }
		end
		say(o, pick(LS.LINES.grab))
		walkUpArrest(o, player, pp, true)
		return { ok = true, result = "arrest" }
	elseif choice == "excuse" then
		-- talking your way out: a small chance at 1 star (never twice in a row), else a ticket
		if Law.ticketable(player) and rnd() < 0.3 and not case.excused then
			case.excused = true
			say(o, "흠… 이번만 봐드립니다. 조심하세요.")
			Law.setStars(player, 0, "경찰이 이번엔 봐줬어요")
			return { ok = true, result = "let_go" }
		end
		say(o, "변명은 됐고요.")
		if Law.ticketable(player) then
			Law.ticket(player, o.name)
			return { ok = true, result = "ticket" }
		end
		walkUpArrest(o, player, pp, false)
		return { ok = true, result = "arrest" }
	end
	-- flee
	o.state = "chase"
	o.stopIssued = true
	say(o, pick(LS.LINES.chase))
	if now() - (case.carFleeT or -1e9) > 10 then
		Law.crime(player, "flee", { police = true, pos = pp })
	end
	return { ok = true, result = "flee" }
end

-------------------------------------------------------------------------------------------------
-- Officer brain
-------------------------------------------------------------------------------------------------
local function facingOf(o: any): Vector3
	local _, dir = legPos(o, now())
	if dir and Vector3.new(dir.X, 0, dir.Z).Magnitude > 0.1 then
		return Vector3.new(dir.X, 0, dir.Z).Unit
	end
	local yaw = math.rad(o.yaw or 0)
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

-- can officer `o` see `player` (range, cone, line of sight)
local function canSee(o: any, player: Player, t: any): (boolean, Vector3?, number)
	local root = Law.rootOf(player)
	if not root then
		return false, nil, math.huge
	end
	local pp = root.Position
	local d = flat(o.pos, pp)
	local range = t.sight * (if Law.isNight() then 0.85 else 1)
	if d > range then
		return false, pp, d
	end
	if d > 7 then
		local f = facingOf(o)
		local to = Vector3.new(pp.X - o.pos.X, 0, pp.Z - o.pos.Z)
		if to.Magnitude > 0.1 then
			local cosA = f:Dot(to.Unit)
			if cosA < math.cos(math.rad(t.fov * 0.5)) then
				return false, pp, d
			end
		end
	end
	local eye = o.pos + Vector3.new(0, 4.6, 0)
	if not losClear(eye, pp + Vector3.new(0, 1.2, 0)) then
		return false, pp, d
	end
	return true, pp, d
end

local function chaseSpeed(o: any, case: any, d: number): number
	local t = tierOf(case)
	local sv = suspectSpeed(case.player)
	local f = ({ 0.86, 0.9, 0.94, 0.98, 1.02 })[math.clamp(case.stars, 1, 5)]
	local v = math.clamp(sv * f, t.run, 28)
	-- (an officer was hit: no breather between bursts while they close in for the takedown)
	if d < 18 and (now() >= o.burstReady or isViolent(case.player)) then
		o.burstUntil = now() + t.burst
		o.burstReady = now() + 6
	end
	if now() < o.burstUntil then
		v += 3.5
	end
	return v
end

local function thinkCase(o: any, case: any)
	local player = case.player
	if not player.Parent then
		o.state = "leave"
		return
	end
	local s = Law.sess(player)
	if not s or s.stars <= 0 or s.cuffed or s.jail then
		o.state = "leave"
		return
	end
	local t = tierOf(case)
	-- hesitation (an obstacle / the stairs / out of breath)
	if now() < o.pauseUntil then
		return
	end
	-- sight
	local seeing, pp, d = false, nil, math.huge
	if now() >= o.nextSight then
		o.nextSight = now() + 0.35
		local ok, p, dist = canSee(o, player, t)
		pp, d = p, dist
		if ok then
			o.glimpse = o.glimpse or now()
			if now() - o.glimpse >= t.react or dist < 9 then
				seeing = true
			end
		else
			o.glimpse = nil
		end
		o.seeing = seeing
	else
		seeing = o.seeing
		pp = Law.posOf(player)
		d = pp and flat(o.pos, pp) or math.huge
	end
	if seeing and pp then
		local was = o.state
		o.radioAt = nil -- (a pending dispatcher update is stale once the officer sees the suspect)
		o.lastSeenPos = pp
		o.lastSeenT = now()
		Law.seen(player, pp, o.name)
		case.knownPos = pp
		case.knownT = now()
		case.radioUntil = math.max(case.radioUntil or 0, now() + t.radio * 2) -- (radioed in: the others follow)
		carFlee(case, player, pp)
		if was ~= "chase" and was ~= "stop" and was ~= "cuffwalk" then
			o.state = "chase"
			say(o, pick(LS.LINES.spot))
			emote(o, "point_proc")
			o.nextRepath = 0
		end
	end
	-- radio: a newer sighting by another unit
	if not seeing and o.radioAt and now() >= o.radioAt and o.state ~= "chase" and o.state ~= "stop" and o.state ~= "cuffwalk" then
		o.radioAt = nil
		if case.knownT > o.goalT and case.knownPos then
			o.goalT = case.knownT
			o.state = "respond"
			assignGoal(o, case.knownPos, 12.5 + case.stars * 0.6, t.wrongTurn)
		end
	end
	if o.state == "cuffwalk" then
		-- walking up to a surrendering suspect (or one who answered the stop order: cuffSurrender)
		if pp and d <= LS.GRAB_RANGE + 1 then
			local surrender = o.cuffSurrender ~= false
			o.cuffSurrender = nil
			standAt(o, legPos(o, now()))
			faceTo(o, pp)
			say(o, pick(LS.LINES.grab))
			Law.arrest(player, { by = "npc", officer = o, surrender = surrender })
		elseif o.cuffSurrender ~= nil and pp and d > 15 then
			-- answered the stop order, then ran for it
			o.cuffSurrender = nil
			o.state = "chase"
			o.stopIssued = true
			o.nextRepath = 0
			say(o, pick(LS.LINES.chase))
			if now() - (case.carFleeT or -1e9) > 10 then -- (a drive-off carFlee already counted is one 도주)
				Law.crime(player, "flee", { police = true, pos = pp })
			end
		elseif now() >= o.nextRepath and pp then
			o.nextRepath = now() + 0.8
			assignGoal(o, pp, 9, nil)
		end
		return
	end
	if o.state == "stop" then
		if not pp then
			return
		end
		faceTo(o, pp)
		if isViolent(player) then
			-- hit an officer during the stop: the stop is over, the takedown starts (no extra 도주)
			if case.stopBy == o then
				case.stopBy = nil
				Law.push(player, { kind = "stopEnd" })
			end
			o.state = "chase"
			o.stopIssued = true
			o.orderGiven = true
			o.nextRepath = 0
			say(o, pick(LS.LINES.subdue), 3)
			return
		end
		if d > 15 or now() - (o.stopT or now()) > LS.STOP_GRACE then
			-- walked off / ignored the order
			case.stopBy = nil
			o.state = "chase"
			o.stopIssued = true
			say(o, pick(LS.LINES.chase))
			Law.crime(player, "flee", { police = true, pos = pp })
			Law.push(player, { kind = "stopEnd" })
		end
		return
	end
	if o.state == "chase" then
		if seeing and pp then
			-- stop order for a minor 1-star case
			if not o.stopIssued and not case.stopBy and Law.ticketable(player) and d <= LS.ORDER_RANGE and suspectSpeed(player) < 12 and not suspectInCar(player) then
				o.stopIssued = true
				o.state = "stop"
				o.stopT = now()
				case.stopBy = o
				standAt(o, legPos(o, now()))
				faceTo(o, pp)
				say(o, pick(LS.LINES.order), 4)
				emote(o, "stop_hand")
				Law.push(player, { kind = "stop", officer = o.name, grace = LS.STOP_GRACE, choices = {
					{ id = "comply", label = "🙋 순순히 응하기" },
					{ id = "excuse", label = "🤥 변명하기" },
					{ id = "flee", label = "🏃 도망치기" },
				} })
				return
			end
			local violentNow = isViolent(player)
			-- on foot, beyond a ticket: the order first ("손 들어!"), then a moment watching what the suspect
			-- does (stops / hands up / runs) before any grab. One order per officer; the case-level
			-- watchUntil keeps a crowd of officers from shouting at once. A suspect who hit an officer
			-- gets no order (the takedown, below)
			if not o.orderGiven and not violentNow and not Law.ticketable(player) and not suspectInCar(player) and d <= LS.ORDER_RANGE and now() >= (case.watchUntil or 0) and now() - (case.orderT or -1e9) >= 8 then
				o.orderGiven = true
				case.orderT = now() -- (one order per encounter: the others do not shout it again in turn)
				case.watchUntil = now() + LS.ORDER_WATCH
				case.watchBy = o
				o.pos = legPos(o, now())
				faceTo(o, pp)
				say(o, pick(LS.LINES.order_hard), 3)
				emote(o, "stop_hand")
				assignGoal(o, pp, 7, nil) -- closes the last studs at a walk
				return
			end
			if case.watchBy == o and case.watchUntil then
				local handsUp = now() - (s.handsUp or -1e9) < 6
				local v = suspectSpeed(player)
				if now() < case.watchUntil and d <= 15 and v <= 12 and not handsUp and not violentNow then
					if o.path and d <= LS.GRAB_RANGE + 1 then
						standAt(o, legPos(o, now())) -- (never walks into the suspect while watching)
						faceTo(o, pp)
					end
					return -- still watching (keeps the walk goal: no grab, no sprint re-path)
				end
				case.watchUntil, case.watchBy = nil, nil
				if handsUp then
					o.state = "cuffwalk"
					o.cuffSurrender = true
					o.nextRepath = now() + 0.8
					say(o, "좋아, 손 그대로!")
					assignGoal(o, pp, 9, nil)
					return
				elseif v < 3 then
					o.grabAt = 0 -- stood still: the grab below (LS.grabChance = 1 under 3 studs/s)
				else
					say(o, pick(LS.LINES.chase)) -- ran: the chase re-paths at chase speed now
					o.nextRepath = 0
				end
			end
			-- grab (not while another officer's order is being watched)
			if d <= LS.GRAB_RANGE and now() >= o.grabAt and now() >= (case.watchUntil or 0) then
				o.grabAt = now() + 1.2
				local handsUp = now() - (s.handsUp or -1e9) < 6
				local chance = if handsUp then 1 else LS.grabChance(case.stars, suspectSpeed(player), suspectInCar(player))
				if violentNow and not handsUp and not suspectInCar(player) then
					chance = math.max(chance, 0.7) -- 제압: hitting an officer up close ends on the ground (on foot)
				end
				if Police.testNoGrab then
					chance = 0 -- test only: watch the chase without it ending
				end
				if rnd() < chance then
					standAt(o, legPos(o, now()))
					faceTo(o, pp)
					say(o, pick(if violentNow and not handsUp then LS.LINES.subdue else LS.LINES.grab))
					Law.arrest(player, { by = "npc", officer = o, forced = not handsUp, surrender = handsUp })
					return
				end
				say(o, pick(LS.LINES.grab_fail))
				emote(o, "stagger")
				o.pauseUntil = now() + 0.6 + rnd() * 0.6 -- the slip: a window to get away
				standAt(o, legPos(o, now()))
				-- slipping out of a grab is 체포 불응 once per chase, not once per officer per second
				-- (several officers grabbing at once used to stack it up to 5 stars with a toast each)
				if now() - (case.lastResist or -1e9) > 45 then
					case.lastResist = now()
					Law.crime(player, "resist", { police = true, pos = pp, silent = true })
				end
				return
			end
			if now() >= o.nextRepath then
				o.nextRepath = now() + t.repath * (0.8 + rnd() * 0.4)
				local cur = legPos(o, now())
				o.pos = cur
				assignGoal(o, pp, chaseSpeed(o, case, d), nil)
				if rnd() < 0.18 then
					say(o, pick(LS.LINES.chase))
				end
			end
			return
		end
		-- lost sight
		if o.lastSeenT and now() - o.lastSeenT > 1.3 then
			o.state = "lost"
			local cur = legPos(o, now())
			o.pos = cur
			say(o, pick(LS.LINES.lost))
			assignGoal(o, o.lastSeenPos or case.knownPos, 13 + case.stars * 0.5, t.wrongTurn)
			o.goalT = now()
		end
		return
	end
	if o.state == "respond" or o.state == "lost" then
		-- stairs / alleys: a stall now and then
		if o.path and rnd() < t.hesitate * 0.08 then
			o.pos = legPos(o, now())
			o.pauseUntil = now() + 0.6 + rnd() * 0.8
			standAt(o, o.pos)
			if rnd() < 0.5 then
				say(o, pick(LS.LINES.stumble))
			end
			o.resumeGoal = o.goal
			return
		end
		if o.resumeGoal then
			local g = o.resumeGoal
			o.resumeGoal = nil
			assignGoal(o, g, 12.5 + case.stars * 0.6, nil)
			return
		end
		if arrived(o) then
			local wasLost = o.state == "lost"
			o.pos = legPos(o, now())
			o.state = "search"
			o.searchLeft = 3 + case.stars
			o.searchCenter = case.knownPos or o.pos
			say(o, pick(if wasLost then LS.LINES.search else LS.LINES.arrive))
			standAt(o, o.pos)
			setAct(o, "look") -- (the look_around act; an emote "look" does not exist)
			o.pauseUntil = now() + 1.2 + rnd() * 1.4
		end
		return
	end
	if o.state == "search" then
		if arrived(o) then
			o.pos = legPos(o, now())
			if o.searchLeft <= 0 then
				-- widen the search a little around the last known spot
				o.searchLeft = 2 + case.stars
				o.searchCenter = case.knownPos or o.pos
			end
			o.searchLeft -= 1
			local q = ringNode(o.searchCenter or o.pos, 8, 28 + case.stars * 4, nil)
			if q then
				if rnd() < 0.3 then
					say(o, pick(LS.LINES.search))
				end
				assignGoal(o, q, 7.5 + case.stars * 0.6, nil)
				o.pauseUntil = now() + 0.4 + rnd() * 1.6
			end
		end
	end
end

local function thinkPatrol(o: any)
	-- a wanted player in sight joins the case
	for _, p in Players:GetPlayers() do
		local s = Law.sess(p)
		if s and s.stars > 0 and not s.cuffed and not s.jail then
			local ok, pp = canSee(o, p, LS.TIERS[s.stars])
			if ok and pp then
				local case = caseOf(p, true)
				case.stars = s.stars
				case.knownPos = pp
				case.knownT = now()
				case.radioUntil = math.max(case.radioUntil or 0, now() + LS.TIERS[s.stars].radio * 2)
				o.role = "case"
				o.case = case
				if not table.find(case.units, o) then
					table.insert(case.units, o)
				end
				o.state = "chase"
				o.lastSeenPos = pp
				o.lastSeenT = now()
				say(o, pick(LS.LINES.spot))
				Law.seen(p, pp, o.name)
				return
			end
		end
	end
	if o.incident then
		return -- Law/City drives incident responders
	end
	if arrived(o) and now() >= o.pauseUntil then
		o.pos = legPos(o, now())
		local q = ringNode(o.pos, 20, 55, nil)
		if q then
			assignGoal(o, q, 6.2, nil)
		end
		o.pauseUntil = now() + 2 + rnd() * 5
	end
end

-- crew officers (role "crew"): seated, getting out, walking back / getting in
local function thinkCrew(o: any)
	local c = o.car
	if not c or c.gone then
		-- the car is gone: a plain officer again
		o.car, o.seated, o.boardSlot = nil, nil, nil
		if o.model then
			o.model:SetAttribute("NpcSeat", nil)
		end
		crewStreaming(o, false)
		o.role = if o.case then "case" else "patrol"
		o.state = if o.case then "respond" else "leave"
		o.leaveAt = now() + 30
		return
	end
	if o.seated then
		local cf = carCF(c) * CFrame.new(seatsOf(c).seats[o.seated] or Vector3.zero)
		o.pos = cf.Position - Vector3.new(0, o.ground, 0)
		return
	end
	if o.state == "exiting" then
		if now() >= (o.exitDone or 0) then
			if o.model then
				o.model:SetAttribute("NpcLook", 0) -- (the look toward the suspect after the exit is over)
			end
			local case = c.case
			if o.unit and Police.unitThink[o.unit] then
				o.role = o.unit
				o.state = "deploy"
			elseif case and case.player.Parent then
				o.role = "case"
				o.case = case
				if not table.find(case.units, o) then
					table.insert(case.units, o)
				end
				o.state = "respond"
				o.goalT = case.knownT
				o.nextSight = 0
				o.glimpse = nil
				assignGoal(o, case.knownPos or c.dismountTarget or o.pos, 12 + case.stars * 0.6, tierOf(case).wrongTurn)
			else
				o.role = "patrol"
				o.state = "patrol"
				o.pauseUntil = now() + 3 + rnd() * 4
			end
		end
		return
	end
	if o.state == "board" then
		local slot = o.boardSlot
		if not slot then
			o.role = if o.case then "case" else "patrol"
			o.state = "leave"
			return
		end
		if o.boardStep == "walk" then
			local _, _, out = doorWorld(c, slot)
			if arrived(o) and flat(legPos(o, now()), out) < 2.5 then
				local seatFeet, sill = doorWorld(c, slot)
				o.pos = legPos(o, now())
				faceTo(o, sill)
				moveAlong(o, { o.pos, sill, seatFeet }, 3.2)
				o.boardStep = "in"
			elseif (arrived(o) or now() - (o.boardRe or o.boardT) > 3) and now() - (o.boardRe or 0) > 1.5 then
				-- re-aim at the door (the route ended short / the car moved a little)
				o.boardRe = now()
				o.pos = legPos(o, now())
				assignGoal(o, out, o.boardSpeed or 9.5, nil)
			end
		elseif o.boardStep == "in" and arrived(o) then
			o.boardSlot = nil
			o.boardStep = nil
			seatOfficer(c, o, slot)
		end
	end
end

local function thinkOfficer(o: any)
	if o.gone then
		return
	end
	if o.model and o.model:GetAttribute("LawState") ~= o.state then
		o.model:SetAttribute("LawState", o.state) -- read-only mirror (tests / tools)
	end
	if o.role == "crew" then
		thinkCrew(o)
		return
	end
	o.pos = legPos(o, now())
	if o.unit and o.role == o.unit and o.state ~= "leave" then
		local f = Police.unitThink[o.unit]
		if f then
			f(o)
			return
		end
	end
	if o.state == "leave" then
		-- officers who came by car walk back to it and ride off
		local c = o.car
		if c and not c.gone and c.state ~= "leave" and c.state ~= "abandoned" and c.state ~= "transport" and c.state ~= "hold" and flat(o.pos, carPos(c)) < 120 then
			if c.state == "recall" then
				boardOfficer(o, c)
			else
				carLeave(c)
			end
			if o.state == "board" then
				return
			end
		end
		local far = true
		for _, p in Players:GetPlayers() do
			local pp = Law.posOf(p)
			if pp and flat(pp, o.pos) < 70 then
				far = false
				break
			end
		end
		if far or now() > (o.leaveAt or now()) then
			removeOfficer(o)
		end
		return
	end
	if o.role == "case" and o.case then
		thinkCase(o, o.case)
	elseif o.role == "patrol" then
		thinkPatrol(o)
	elseif o.role == "post" then
		-- roadblock / checkpoint officers: look out for the case's suspect
		local b = o.block
		if b and b.case and b.case.player then
			local t = tierOf(b.case)
			local ok, pp = canSee(o, b.case.player, t)
			if ok and pp then
				Law.seen(b.case.player, pp, o.name)
				if flat(pp, o.pos) < 30 and now() - (o.lastSayT or 0) > 5 then
					say(o, pick(LS.LINES.roadblock))
				end
				-- a suspect on foot near the block: they leave the post and chase
				if not suspectInCar(b.case.player) and flat(pp, o.pos) < 40 then
					o.role = "case"
					o.case = b.case
					table.insert(b.case.units, o)
					o.state = "chase"
					o.lastSeenPos = pp
					o.lastSeenT = now()
				end
			end
		end
	end
	-- despawn stragglers far from everyone
	if o.role ~= "post" then
		local near = false
		for _, p in Players:GetPlayers() do
			local pp = Law.posOf(p)
			if pp and flat(pp, o.pos) < LS.LOST_FAR + 60 then
				near = true
				break
			end
		end
		if not near then
			removeOfficer(o)
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Car brain
-------------------------------------------------------------------------------------------------
-- the car stops at the kerb: the crew gets out one by one (driver first, partner a moment later)
local function startExits(c: any, target: Vector3?)
	c.state = "parked"
	c.parkT = now()
	c.boxedAt = nil -- (the boxed-in stop is over: the crew walks up and grabs, never the car alone)
	c.dismountTarget = target
	c.dismounted = true
	local k = 0
	for _, o in c.crew do
		if not o.gone and o.seated then
			o.exitAt = now() + 0.55 + k * 0.6
			k += 1
		end
	end
	c.model:SetAttribute("LawCarMoving", false)
end

local function processExits(c: any)
	for _, o in c.crew do
		if not o.gone and o.seated and o.exitAt and now() >= o.exitAt then
			o.exitAt = nil
			exitOfficer(o)
		end
	end
end

-- the free road ahead of a car: the nearest other patrol car / player in its lane (along the heading,
-- within a lane's width of its line); math.huge when clear
local function aheadGap(c: any, cp: Vector3, dir: Vector3): number
	local best = math.huge
	local right = D.rightOf(dir)
	local function test(p: Vector3)
		local d = Vector3.new(p.X - cp.X, 0, p.Z - cp.Z)
		local along = d:Dot(dir)
		if along > 0 and along < best and math.abs(d:Dot(right)) < 3.4 then
			best = along
		end
	end
	for _, o in cars do
		if o ~= c and not o.gone and o.model and o.model.Parent then
			local b0 = best
			test((carPos(o)))
			if best < b0 then
				c.yieldWhy = tostring(o.role) .. ":" .. tostring(o.state)
			end
		end
	end
	for _, pl in Players:GetPlayers() do
		local pp = Law.posOf(pl)
		if pp and not (c.case and pl == c.case.player and c.state == "chase") then
			local b0 = best
			test(pp)
			if best < b0 then
				c.yieldWhy = "player"
			end
		end
	end
	return best
end

-- brake smoothly to stand `gap` short of what is ahead (keeps the car behind the one in front)
local function yieldTo(c: any, cp: Vector3, dir: Vector3, gap: number)
	local v = carSpeed(c)
	local dist = math.max(0.5, gap - 11)
	local okP, path = pcall(D.buildPath, { cp, cp + dir * (dist * 0.5), cp + dir * dist }, { cruise = math.max(v, 26), v0 = v, v1 = 0, heights = carHeights })
	if okP and path then
		setCarPath(c, path)
	end
	c.yieldUntil = now() + 1.2
	c.needReplan = true
end

-- brake to a stop on the lane ahead (boxed-in suspect, a blocked road)
local function stopPath(c: any): any?
	local cp, dir = carPos(c)
	local v = carSpeed(c)
	local dist = math.max(2, v * v / (2 * 11) + 1)
	local gap = aheadGap(c, cp, dir)
	if gap < dist + 11 then
		dist = math.max(0.5, gap - 11) -- (never into the back of the car in front)
	end
	local okP, path = pcall(D.buildPath, { cp, cp + dir * (dist * 0.5), cp + dir * dist }, { cruise = math.max(v, 26), v0 = v, v1 = 0, heights = carHeights })
	return if okP then path else nil
end

-- brake to a stop from full respond / chase speed: along the lane ahead, ending at the kerb (never a
-- 100+ stud straight line through a bend or a T junction); straight (stopPath) only from a crawl or
-- close behind the car in front
local function laneStopPath(c: any): any?
	local cp, dir = carPos(c)
	local v = carSpeed(c)
	local need = v * v / 22 + 8
	if v < 12 or aheadGap(c, cp, dir) < need + 11 then
		return stopPath(c)
	end
	local loc = headingLoc(cp + dir * math.clamp(v * 0.6, 5, 22), dir, 26)
	if not loc then
		return nil
	end
	local okF, fwd = pcall(D.forward, graph, loc, need)
	if not okF or not fwd or #fwd < 2 then
		return nil
	end
	table.insert(fwd, 1, cp)
	-- (cut at the braking distance: D.forward runs on to the end of the edge)
	local pts, acc = { fwd[1] }, 0
	for i = 2, #fwd do
		local seg = flat(fwd[i - 1], fwd[i])
		if acc + seg >= need then
			if seg > 1e-3 then
				table.insert(pts, fwd[i - 1]:Lerp(fwd[i], (need - acc) / seg))
			end
			break
		end
		acc += seg
		table.insert(pts, fwd[i])
	end
	local okP, path = pcall(D.buildPath, pts, { cruise = math.max(v, 26), v0 = v, v1 = 0, pullOver = { offset = 2.2, len = 24 }, heights = carHeights })
	return if okP then path else nil
end

-- a lane route that loops far round the block (one-way streets) to reach a spot close by is not worth
-- driving (the dispatcher feed re-plans often): the car brakes to a stop where it is and the crew goes
-- on foot, as for an alley. true = it stops (c.goal = target)
local function detourStop(c: any, path: any, target: Vector3): boolean
	local straight = flat((carPos(c)), target)
	if straight >= 160 or (path.length or 0) <= straight * 4 + 300 then
		return false
	end
	local sp = laneStopPath(c)
	if not sp then
		return false -- (no brake along the lane: the long route is driven after all)
	end
	setCarPath(c, sp)
	c.goal = target
	return true
end

local function boardingCount(c: any): number
	local n = 0
	for _, o in c.crew do
		if not o.gone and o.state == "board" then
			n += 1
		end
	end
	return n
end

-- nobody of the crew can get back in (chased too far off on foot): the car stays at the kerb, out of
-- the case (staff() spawns a fresh, unseen car for the road chase on its next pass); the crew on foot
-- keeps chasing and walks off when the case ends (the leave branch skips an abandoned car)
local function strand(c: any, case: any)
	c.state = "abandoned"
	c.parkT = now()
	setSiren(c.model, false)
	local j = table.find(case.cars, c)
	if j then
		table.remove(case.cars, j)
	end
	case.lastStaff = 0
end

-- cruising (no case): the next stretch is planned just before this one ends, at the current speed
local function cruiseOn(c: any)
	local cp, dir = carPos(c)
	local v = carSpeed(c)
	local loc = headingLoc(cp + dir * math.clamp(v * 0.6, 5, 20), dir, 26)
	if not loc then
		local okL, l = pcall(D.nearestLocation, graph, cp, { maxDist = 60 })
		loc = okL and l or nil
	end
	if not loc then
		return
	end
	local okF, pts = pcall(D.forward, graph, loc, 160 + rnd() * 200)
	if okF and pts and #pts >= 2 then
		table.insert(pts, 1, cp)
		local okP, path = pcall(D.buildPath, pts, { cruise = 30, v0 = v, v1 = 0, heights = carHeights })
		if okP and path then
			setCarPath(c, path)
		end
	end
end

local function thinkCar(c: any)
	if c.gone or not c.model or not c.model.Parent then
		removeCar(c)
		return
	end
	if c.model:GetAttribute("LawState") ~= c.state then
		c.model:SetAttribute("LawState", c.state) -- read-only mirror (tests / tools)
	end
	if c.state == "transport" then
		return -- Law/Jail drives it
	end
	if c.state == "demo" then
		processExits(c)
		return
	end
	-- a unit car with its own driver brain (119 구급차: Law/Rescue) -> true = handled
	if c.unit and Police.unitCarThink[c.unit] then
		processExits(c)
		if Police.unitCarThink[c.unit](c) then
			return
		end
	end
	local cp = carPos(c)
	if c.path and not c.done and now() - c.t0 >= c.path.total then
		c.done = true
		c.model:SetAttribute("LawCarMoving", false)
	end
	processExits(c)
	-- keep the distance to whatever is in the lane ahead (another patrol car, a player): brake
	-- smoothly, then carry on (re-planned from where it stopped)
	if c.path and not c.done and (c.state == "respond" or c.state == "chase" or c.state == "patrol") and now() >= (c.yieldUntil or 0) then
		local cp2, dir2 = carPos(c)
		local v = carSpeed(c)
		if v > 5 then
			local gap = aheadGap(c, cp2, dir2)
			if gap < math.max(15, v * 0.9) then
				c.yields = (c.yields or 0) + 1
				yieldTo(c, cp2, dir2, gap)
			end
		end
	end
	if c.state == "leave" then
		if c.done or now() > (c.leaveAt or now()) + 2 then
			removeCar(c)
		end
		return
	end
	if c.state == "recall" then
		if boardingCount(c) == 0 or now() > (c.recallUntil or 0) then
			-- stragglers stay behind on foot and walk off
			for _, o in c.crew do
				if not o.gone and o.state == "board" then
					o.boardSlot, o.boardStep, o.car = nil, nil, nil
					o.role = "patrol"
					o.state = "leave"
					o.leaveAt = now() + 30
				end
			end
			if seatedCount(c) == 0 then
				c.state = "abandoned" -- nobody to drive: it goes when nobody is around to see it
			else
				driveAway(c)
			end
		end
		return
	end
	if c.state == "abandoned" then
		if not playersNear(cp, 170) or now() - (c.parkT or c.created) > 240 then
			removeCar(c)
		end
		return
	end
	if c.state == "hold" then
		if now() > (c.holdUntil or now()) then
			carLeave(c)
		end
		return
	end
	if c.role == "patrol" then
		-- cruising: the next stretch before this one ends; spot wanted players
		local left = if c.path then c.path.total - (now() - c.t0) else 0
		if (c.done or left < 1.2) and now() >= (c.nextPlan or 0) then
			cruiseOn(c)
			c.nextPlan = now() + 1
		end
		for _, p in Players:GetPlayers() do
			local s = Law.sess(p)
			local pp = Law.posOf(p)
			local existing = cases[p]
			local enough = existing ~= nil and #existing.cars >= LS.TIERS[math.max(1, s and s.stars or 1)].cars + 1
			if s and pp and s.stars > 0 and not s.cuffed and not s.jail and not enough and flat(pp, cp) < LS.TIERS[s.stars].sight and losClear(cp + Vector3.new(0, 4, 0), pp + Vector3.new(0, 1.2, 0)) then
				local case = caseOf(p, true)
				case.stars = s.stars
				case.knownPos = pp
				case.knownT = now()
				case.radioUntil = math.max(case.radioUntil or 0, now() + LS.TIERS[s.stars].radio * 2)
				Law.seen(p, pp, "순찰차")
				c.role = "case"
				c.case = case
				c.state = "respond"
				c.slotIdx = nextSlot(case)
				table.insert(case.cars, c)
				-- head for the suspect from where it is (smooth re-plan at the cruising speed)
				local path = carRoute(c, pp, { cruise = 44 * LS.TIERS[math.max(1, s.stars)].carSpeed, v1 = 0, stopBack = 9 + CAR_GAP * c.slotIdx })
				if path and not detourStop(c, path, pp) then
					setCarPath(c, path)
				end
				c.goal = pp
				for _, o in c.crew do
					if not o.gone then
						o.case = case
					end
				end
				setSiren(c.model, true)
				c.nextPlan = 0
				break
			end
		end
		-- far from every player: retire (it starts far away on purpose: give it time to come closer)
		if not playersNear(cp, 560) and now() - c.created > 20 then
			removeCar(c)
		end
		return
	end
	local case = c.case
	if not case or not case.player.Parent then
		carLeave(c)
		return
	end
	local player = case.player
	local s = Law.sess(player)
	if not s or s.stars <= 0 or s.jail or s.cuffed then
		carLeave(c)
		return
	end
	local t = tierOf(case)
	local inCar = suspectInCar(player)
	local pp = Law.posOf(player)
	-- sight from the car
	if pp and now() >= c.nextSight then
		c.nextSight = now() + 0.4
		local d = flat(cp, pp)
		if d < t.sight * 1.1 and losClear(cp + Vector3.new(0, 4.2, 0), pp + Vector3.new(0, 1.2, 0)) then
			c.glimpse = c.glimpse or now()
			if now() - c.glimpse >= t.react * 0.8 or d < 14 then
				Law.seen(player, pp, "순찰차")
				case.knownPos = pp
				case.knownT = now()
				case.radioUntil = math.max(case.radioUntil or 0, now() + t.radio * 2)
				c.seeing = true
				carFlee(case, player, pp)
			end
		else
			c.glimpse = nil
			c.seeing = false
		end
	end
	-- where can a car not follow? (no driving lane within 28 studs of the suspect: an alley, the
	-- beach, a park, a building)
	if pp and now() >= (c.nextRoadCheck or 0) then
		c.nextRoadCheck = now() + 0.8
		local okL, loc = pcall(D.nearestLocation, graph, pp, { maxDist = 28 })
		c.offRoad = not (okL and loc)
	end
	local roadChase = inCar and case.stars >= 2 and not c.offRoad
	if c.state == "parked" then
		-- the suspect drove off: the crew runs back, gets in, and the road chase starts
		if roadChase and pp and flat(cp, pp) > 22 then
			-- (at a run, from up to 150 studs; nobody able to get back in = the car is left behind.
			-- Crew still stepping out are waited for: they can run back once they are out)
			for _, o in c.crew do
				if not o.gone and o.state == "exiting" then
					return
				end
			end
			local n = 0
			for _, o in c.crew do
				if not o.gone and not o.seated and o.state ~= "board" and o.state ~= "exiting" and o.state ~= "cuffwalk" and flat(o.pos, cp) < 150 and boardOfficer(o, c, 13 + case.stars * 0.6) then
					n += 1
				end
			end
			if n > 0 or seatedCount(c) > 0 or boardingCount(c) > 0 then
				c.state = "remount"
				c.remountUntil = now() + 14
			else
				strand(c, case)
			end
		end
		return
	end
	if c.state == "remount" then
		if boardingCount(c) == 0 or now() > (c.remountUntil or 0) then
			for _, o in c.crew do
				if not o.gone and o.state == "board" then
					-- too slow: back to the foot chase
					o.boardSlot, o.boardStep = nil, nil
					o.role = if o.unit then o.unit else "case"
					o.state = if o.unit then "pursue" else "respond"
					if not table.find(case.units, o) then
						table.insert(case.units, o)
					end
					if case.knownPos then
						assignGoal(o, case.knownPos, 12 + case.stars * 0.6, t.wrongTurn)
					end
				end
			end
			if seatedCount(c) > 0 then
				c.state = "chase"
				c.nextPlan = 0
				c.dismounted = false
				for _, o in c.crew do
					o.exitAt = nil -- (whoever is still in stays in: nobody steps out of a car driving off)
				end
			else
				strand(c, case) -- (no parked <-> remount loop holding the case's car quota)
			end
		end
		return
	end
	if c.state == "chase" then
		if not roadChase then
			if now() < (c.planHold or 0) then
				return -- (finish the U-turn first, then pull over)
			end
			-- the suspect got out / went where no car can go: pull over at the kerb nearest them,
			-- the crew gets out and the chase goes on on foot
			local goal = pp or case.knownPos
			if goal then
				local path = carRoute(c, goal, { cruise = 40, v1 = 0, stopBack = 9 + CAR_GAP * (c.slotIdx or 0) })
				if path and not detourStop(c, path, goal) then
					setCarPath(c, path)
				end
				c.goal = goal
			end
			c.state = "respond"
			c.nextPlan = now() + 2.5
			return
		end
		-- road chase: re-plan along the lanes every 1.2-2 s from where the car is, at its speed
		-- (never mid U-turn: a re-plan on the arc would swing the car back to the lane it is leaving;
		-- nor while it is still on its way to a last-seen spot it has nearly reached)
		local nearLast = not c.seeing and c.path and not c.done and case.knownPos ~= nil and flat(cp, case.knownPos) < 30
		if pp and now() >= c.nextPlan and now() >= (c.yieldUntil or 0) and now() >= (c.planHold or 0) and not nearLast then
			c.nextPlan = now() + 1.2 + rnd() * 0.8
			local goal = if c.seeing then pp else case.knownPos
			if goal then
				-- a wrong side street now and then while it does not see the suspect: kept for a few
				-- seconds (not re-rolled each re-plan) and always ahead of the car, never a fake U-turn
				local target = goal
				if c.seeing then
					c.wrongTarget = nil
				elseif c.wrongTarget and now() < (c.wrongUntil or 0) then
					target = c.wrongTarget
				elseif rnd() < t.wrongTurn * 1.5 then
					local _, hd = carPos(c)
					local off = Vector3.new((rnd() - 0.5) * 140, 0, (rnd() - 0.5) * 140)
					if off:Dot(hd) < 0 then
						off -= hd * (2 * off:Dot(hd))
					end
					c.wrongTarget = goal + off
					c.wrongUntil = now() + 5 + rnd() * 3
					target = c.wrongTarget
				end
				local sv = math.max(suspectSpeed(player), 30)
				-- (the end of the road is short of the suspect, in this car's place in the line: several cars
				-- closing in never pile onto one spot)
				local path = carRoute(c, target, { cruise = math.clamp(sv * (0.82 + 0.05 * case.stars), 34, 62), v1 = 12, kerb = false, stopBack = 12 + CAR_GAP * (c.slotIdx or 0) })
				if path then
					setCarPath(c, path)
				end
			end
		end
		-- boxed in: the suspect car crawls next to the patrol car -> brake, get out, arrest
		if pp and flat(cp, pp) < 13 and suspectSpeed(player) < 5 then
			c.slowT += 0.25
			if c.slowT > 1.6 then
				c.slowT = 0
				local sp = stopPath(c)
				if sp then
					setCarPath(c, sp)
				end
				c.state = "respond"
				c.goal = pp
				c.boxedAt = now()
				c.needReplan = false -- (the stop replaces a pending give-way re-plan: brake, park, get out)
				c.nextPlan = now() + 3
			end
		else
			c.slowT = 0
		end
		return
	end
	-- responding: drive to the kerb nearest the reported / last known spot, following newer sightings
	if c.state == "respond" then
		if roadChase and seatedCount(c) > 0 and not c.boxedAt then
			c.state = "chase"
			c.nextPlan = 0
			return
		end
		if c.boxedAt then
			-- braking to a stop next to the boxed-in suspect: the crew gets out (startExits) and walks up
			-- for the grab (warn / approach / grab); the car itself never arrests anybody
			if now() - c.boxedAt > 2.6 then
				c.boxedAt = nil -- (only held off the re-chase while the car stopped)
			end
		elseif c.needReplan and case.knownPos and now() >= (c.yieldUntil or 0) then
			-- it gave way to somebody: on to the spot again
			c.needReplan = false
			local path = carRoute(c, case.knownPos, { cruise = 44 * t.carSpeed, v1 = 0, stopBack = 9 + CAR_GAP * (c.slotIdx or 0) })
			if path and not detourStop(c, path, case.knownPos) then
				setCarPath(c, path)
				c.goal = case.knownPos
			end
		elseif not c.done and case.knownPos and now() >= c.nextPlan and now() >= (c.planHold or 0) and flat(c.goal or case.knownPos, case.knownPos) > 35 then
			c.nextPlan = now() + 2.5
			local path = carRoute(c, case.knownPos, { cruise = 44 * t.carSpeed, v1 = 0, stopBack = 9 + CAR_GAP * (c.slotIdx or 0) })
			if path and not detourStop(c, path, case.knownPos) then
				setCarPath(c, path)
				c.goal = case.knownPos
			end
		end
		if c.done and not c.needReplan then
			if seatedCount(c) > 0 then
				startExits(c, case.knownPos)
			else
				c.state = "parked"
				c.parkT = now()
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Road closures / checkpoints (4+ stars, a suspect in a car)
-------------------------------------------------------------------------------------------------
local function barrier(parent: Instance, cf: CFrame)
	local p = Instance.new("Part")
	p.Name = "LawBarrier"
	p.Size = Vector3.new(7, 2.2, 0.8)
	p.CFrame = cf
	p.Anchored = true
	p.Color = Color3.fromRGB(235, 235, 235)
	p.Material = Enum.Material.SmoothPlastic
	local stripe = Instance.new("Part")
	stripe.Name = "Stripe"
	stripe.Size = Vector3.new(7.02, 0.6, 0.82)
	stripe.CFrame = cf * CFrame.new(0, 0.35, 0)
	stripe.Anchored = true
	stripe.CanCollide = false
	stripe.Color = Color3.fromRGB(230, 60, 40)
	stripe.Material = Enum.Material.Neon
	stripe.Parent = p
	p.Parent = parent
end

local function placeBlock(case: any, kind: string)
	if not D or not graph or #cars >= LS.MAX_CARS then
		return
	end
	local player = case.player
	local pp = Law.posOf(player)
	local root = Law.rootOf(player)
	if not pp or not root then
		return
	end
	local v = root.AssemblyLinearVelocity
	local dir = Vector3.new(v.X, 0, v.Z)
	if dir.Magnitude < 5 then
		dir = root.CFrame.LookVector
	end
	dir = Vector3.new(dir.X, 0, dir.Z).Unit
	-- ahead on the suspect's road, but never set up in plain view (the car, the barriers and the two
	-- post officers appear where nobody sees them: round a corner, or past the 360-stud sight check)
	local loc = nil
	for _, dist in { 260, 320, 400 } do
		local okL, l = pcall(D.nearestLocation, graph, pp + dir * dist, { maxDist = 70 })
		if okL and l and l.point and unseenStart(l.point, 220, 360) then
			loc = l
			break
		end
	end
	if not loc then
		return -- (blocksTick already stamped lastBlock: it tries again later)
	end
	local at = loc.point
	local laneDir = D.edgeDir(graph, loc.edge)
	local cf = D.cframe(Vector3.new(at.X, groundAt(at, 6), at.Z), laneDir)
	local folder = Instance.new("Folder")
	folder.Name = "LawRoadblock"
	folder.Parent = carsFolder
	-- a patrol car across the lane + barriers either side
	local tpl = findTemplate()
	if tpl then
		local car = tpl:Clone()
		car.Name = "LawBlockCar"
		car:PivotTo(cf * CFrame.new(0, carOffsetY, 0) * CFrame.Angles(0, math.rad(90), 0)) -- across the lane
		car.Parent = folder
	end
	if kind == "block" then
		barrier(folder, cf * CFrame.new(-7, 1.1, 2))
		barrier(folder, cf * CFrame.new(7, 1.1, 2))
	end
	local b = { case = case, folder = folder, pos = at, expire = now() + (if kind == "block" then 70 else 90), kind = kind, posts = {} }
	for i = 1, 2 do
		local spot = (cf * CFrame.new(if i == 1 then -4 else 4, 0, -5)).Position
		local o = newOfficer(Vector3.new(spot.X, groundAt(spot, 6), spot.Z), "post", nil)
		if o then
			o.block = b
			o.idleAct = "work"
			faceTo(o, pp)
			standAt(o, o.pos)
			table.insert(b.posts, o)
		end
	end
	table.insert(blocks, b)
	Law.push(player, { kind = "radio", text = if kind == "block" then "무전: " .. Law.areaName(at) .. " 방면 도로 차단 완료." else "무전: " .. Law.areaName(at) .. " 검문 실시 중." })
end

local function blocksTick()
	for i = #blocks, 1, -1 do
		local b = blocks[i]
		if now() > b.expire or not b.case or not b.case.player.Parent then
			for _, o in b.posts do
				if not o.gone and o.role == "post" then
					removeOfficer(o)
				end
			end
			if b.folder then
				b.folder:Destroy()
			end
			table.remove(blocks, i)
		end
	end
	for player, case in cases do
		local t = tierOf(case)
		if t.roadblocks > 0 and suspectInCar(player) and now() - case.lastBlock > 22 then
			local n = 0
			for _, b in blocks do
				if b.case == case and b.kind == "block" then
					n += 1
				end
			end
			if n < t.roadblocks then
				case.lastBlock = now()
				placeBlock(case, "block")
			end
		elseif t.checkpoint and not suspectInCar(player) and now() - case.lastBlock > 40 then
			case.lastBlock = now()
			placeBlock(case, "check")
		end
		-- reinforcements when the case goes cold at 4+
		if case.stars >= 4 and now() - case.knownT > 15 and now() - case.lastReinforce > 25 then
			case.lastReinforce = now()
			local foot = 0
			for _, o in case.units do
				if not o.gone then
					foot += 1
				end
			end
			if foot < t.foot * 2 and case.knownPos then
				spawnFootUnits(case, 2)
				Law.push(player, { kind = "radio", text = "무전: 지원 병력 투입, " .. Law.areaName(case.knownPos) .. " 일대 수색." })
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Idle patrol (no case): a few units around the players, more at night
-------------------------------------------------------------------------------------------------
local nextPatrol = 0
local function patrolTick()
	if now() < nextPatrol then
		return
	end
	nextPatrol = now() + 6
	local plist = Players:GetPlayers()
	if #plist == 0 then
		return
	end
	local want = if Law.isNight() then LS.PATROL.night else LS.PATROL.day
	local foot, carsN = 0, 0
	for _, o in officers do
		if o.role == "patrol" and not o.gone then
			foot += 1
		end
	end
	for _, c in cars do
		if c.role == "patrol" and not c.gone then
			carsN += 1
		end
	end
	local anchor = plist[rng:NextInteger(1, #plist)]
	local pp = Law.posOf(anchor)
	if not pp then
		return
	end
	-- a player in the 유치장 / inside does not need street patrols around them
	if anchor:GetAttribute(LS.Attr.Jail) and (anchor:GetAttribute(LS.Attr.Jail) :: number) > 0 then
		return
	end
	if foot < want.foot * math.min(2, #plist) and not Police.testCarsOnly then
		local at = hiddenSpot(pp, 90, 150) -- (nil when every spot is seen: no patrol this round)
		if at then
			local o = newOfficer(at, "patrol", nil)
			if o then
				o.state = "patrol"
				local q = ringNode(at, 20, 60, nil)
				if q then
					assignGoal(o, q, 6.2, nil)
				end
			end
		end
	end
	if carsN < want.cars * math.min(2, #plist) and loadNav() and D and graph then
		local c = newCar(nil, pp + Vector3.new((rnd() - 0.5) * 200, 0, (rnd() - 0.5) * 200), "patrol")
		if c then
			c.state = "patrol"
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Tick (4 Hz from Law)
-------------------------------------------------------------------------------------------------
-- a hit on an officer (GwangalliGameplay/Fight: Fight.hitHooks["police_"], called before Fight notes
-- the 공무집행방해): he staggers, and once the case exists (deferred) he and the other officers stop
-- ordering and go for the takedown (제압) for LS.SUBDUE_S. Returns nil: Fight keeps its "arrest" reaction
local function onOfficerHit(player: Player, id: string, info: any): (string?, string?)
	local o = nil
	for _, x in officers do
		if x.id == id and not x.gone then
			o = x
			break
		end
	end
	if not o or o.civil or o.unit then
		return nil -- (119 / 특임대: their own modules)
	end
	violent[player] = now() + LS.SUBDUE_S
	o.hitT = now()
	if o.seated or not o.model then
		return nil
	end
	if info and info.outcome == "ko" then
		return nil, "" -- (he goes down: Fight -> Police.knocked; the others are on the attacker: violent)
	end
	o.model:SetAttribute("NpcKnock", string.format("%.2f|%.3f|%.3f|%s", serverNow(), info and info.dx or 0, info and info.dz or -1, "stagger"))
	o.pauseUntil = math.max(o.pauseUntil or 0, now() + 0.4)
	if now() - (o.hitSayT or -1e9) > 3 then
		o.hitSayT = now()
		say(o, pick(LS.LINES.subdue), 3)
	end
	task.defer(function()
		local case = cases[player]
		if not case or o.gone or o.seated or o.role == "crew" then
			return
		end
		-- (another officer's stop order ends on his own next think: isViolent)
		if case.stopBy == o then
			case.stopBy = nil
			Law.push(player, { kind = "stopEnd" })
		end
		if o.incident then
			o.incident.officer = nil -- (Law/City lets the incident go on without him)
			o.incident = nil
		end
		if o.case ~= case or o.role ~= "case" then
			o.role = "case"
			o.case = case
			o.block = nil
			if not table.find(case.units, o) then
				table.insert(case.units, o)
			end
		end
		o.state = "chase"
		o.stopIssued = true
		o.orderGiven = true
		-- (where the attacker is: info.pos is the hit officer's own spot)
		local ap = Law.posOf(player) or (info and info.pos)
		o.lastSeenPos = ap
		o.lastSeenT = now()
		if ap then
			case.knownPos = ap
			case.knownT = now()
		end
		o.seeing = true
		o.nextRepath = 0
	end)
	return nil, "" -- (his own bubble already shows the line)
end

local carAcc = 0
local hookSet = false
function Police.tick(dt: number)
	if not loadNav() then
		return
	end
	if not hookSet and ctx and ctx.fight and type(ctx.fight.hitHooks) == "table" then
		hookSet = true -- (Fight sets ctx.fight after Law is initialised)
		ctx.fight.hitHooks["police_"] = onOfficerHit
	end
	trackSpeeds()
	pcall(downedTick)
	for _, o in table.clone(officers) do
		local ok, err = pcall(thinkOfficer, o)
		if not ok then
			warn("[GwangalliLaw] officer: " .. tostring(err))
			removeOfficer(o)
		elseif not o.gone then
			pcall(syncRoot, o)
		end
	end
	for _, c in table.clone(cars) do
		local ok, err = pcall(thinkCar, c)
		if not ok then
			warn("[GwangalliLaw] car: " .. tostring(err))
			removeCar(c)
		end
	end
	pcall(blocksTick)
	pcall(patrolTick)
	-- keep the case staffed (units lost / despawned)
	for player, case in cases do
		local s = Law.sess(player)
		if not s or s.stars <= 0 then
			Police.standDown(player, s, "lost")
		else
			if now() - (case.lastStaff or 0) > 8 then
				case.lastStaff = now()
				case.stars = s.stars
				staff(case)
			end
			if not s.cuffed and not s.jail then
				radioFix(case, player)
			end
		end
	end
	local _ = dt
	carAcc += dt
end

-- motion: every Heartbeat each moving car's root goes to the path sample at that instant (the
-- welded body follows), so the car advances and turns every frame — corners slow down, steer and
-- speed up again from the path's speed profile (D.buildPath). Clients re-sample the same path each
-- rendered frame (GwangalliLawCars). Seated officers ride along at 10 Hz on the server (the client
-- keeps them on the seat every frame from NpcSeat).
local seatAcc = 0
local function carMotionStep(dt: number)
	for _, c in cars do
		if c.path and c.model and c.model.Parent and c.state ~= "gone" then
			local t = math.min(now() - c.t0, c.path.total)
			if t < c.path.total + 0.5 then
				local p, dir = D.sample(c.path.pts, c.path.times, t)
				local root = c.model.PrimaryPart
				if root and p == p then
					root.CFrame = D.cframe(p, dir)
				end
			end
		end
	end
	seatAcc += dt
	if seatAcc >= 0.1 then
		seatAcc = 0
		for _, o in officers do
			if o.seated and not o.gone then
				placeSeated(o)
			end
		end
	end
end

-- test only (Law debug "carDemo"): a crewed patrol car parked on the kerb near `pos`, no AI
-- ("demo" state); op "exit" puts the crew out (the normal exit), "drive" sends it down the road
function Police.debugDemo(player: Player, op: string, pos: Vector3?): any
	if op == "spawn" and pos and loadNav() then
		local tpl = findTemplate()
		local okL, loc = pcall(D.nearestLocation, graph, pos, { maxDist = 90, side = pos, kerbOnly = true })
		if not tpl or not okL or not loc then
			return { ok = false }
		end
		seq += 1
		local car = tpl:Clone()
		car.Name = "LawPatrolCar_" .. seq
		car:SetAttribute("LawCar", true)
		car:SetAttribute("LawSiren", true)
		local dir = D.edgeDir(graph, loc.edge)
		local at = loc.point + D.rightOf(dir) * 2.2
		at = Vector3.new(at.X, carHeights(at) or at.Y, at.Z)
		car:PivotTo(D.cframe(at, dir))
		car.Parent = carsFolder
		local c = { id = "car_" .. seq, model = car, path = nil, t0 = now(), done = true, case = nil, role = "demo", state = "demo", crew = {}, nextPlan = 0, nextSight = 0, slowT = 0, created = now(), restCF = D.cframe(at, dir) }
		table.insert(cars, c)
		for slot = 1, 2 do
			local o = newOfficer(at, "patrol", nil)
			if o then
				seatOfficer(c, o, slot)
			end
		end
		demoCar = c
		return { ok = true, name = car.Name, x = at.X, y = at.Y, z = at.Z }
	elseif op == "exit" and demoCar then
		local k = 0
		for _, o in demoCar.crew do
			if not o.gone and o.seated then
				o.exitAt = now() + 0.2 + k * 0.6
				k += 1
			end
		end
		return { ok = true, n = k }
	elseif op == "board" and demoCar then
		for _, o in demoCar.crew do
			if not o.gone and not o.seated then
				boardOfficer(o, demoCar)
			end
		end
		return { ok = true }
	elseif op == "drive" and demoCar then
		demoCar.role = "patrol"
		demoCar.state = "patrol"
		cruiseOn(demoCar)
		return { ok = true }
	end
	return { ok = false }
end

-- Law/City, Jail and Fight use these
Police.unitCarThink = {} -- [unit kind] = function(c): boolean (true = this car is fully driven by the unit module)
Police.unitThink = {} -- [unit kind] = function(o): the brain of a unit member on foot (Law/Swat, Law/Rescue)
Police.newOfficer = newOfficer
Police.canSee = canSee
Police.tierOf = tierOf
Police.boardOfficer = boardOfficer
Police.startExits = startExits
Police.carLeave = carLeave
Police.removeCar = removeCar
Police.suspectInCar = suspectInCar
Police.suspectSpeed = suspectSpeed
Police.caseOf = caseOf
Police.ringNode = ringNode
Police.routePts = routePts
Police.tplData = tplData
Police.CREW_SCALE = CREW_SCALE
Police.rayHit = rayHit
Police.setCarPath = setCarPath
Police.clearCarPath = clearCarPath
Police.carSpeed = carSpeed
Police.seatedCount = seatedCount
Police.boardingCount = boardingCount
Police.driveAway = driveAway
Police.exitOfficer = exitOfficer
Police.doorWorld = doorWorld
Police.removeOfficer = removeOfficer
Police.assignGoal = assignGoal
Police.standAt = standAt
Police.faceTo = faceTo
Police.emote = emote
Police.legPos = legPos
Police.arrived = arrived
Police.ringNode = ringNode
Police.hiddenSpot = hiddenSpot
Police.groundAt = groundAt
Police.syncRoot = syncRoot
Police.setSiren = setSiren
Police.losClear = losClear
Police.carPos = carPos
Police.newCar = newCar
Police.carRoute = carRoute
Police.setCarPath = setCarPath
Police.laneStopPath = laneStopPath -- (tests: the lane brake of detourStop)
Police.officers = function()
	return officers
end
Police.cars = function()
	return cars
end
Police.cases = function()
	return cases
end

function Police.onLeave(player: Player, s: any)
	speeds[player] = nil
	violent[player] = nil
	if cases[player] then
		Police.standDown(player, s, "lost")
	end
end

function Police.init(law: any, context: any)
	Law = law
	ctx = context
	LS = Law.shared()
	local lm = ReplicatedStorage:FindFirstChild("GwangalliNPCLooks")
	if lm and lm:IsA("ModuleScript") then
		local ok, res = pcall(require, lm)
		if ok then
			Looks = res
		end
	end
	local f = workspace:FindFirstChild("GwangalliNPCs")
	if not f then
		f = Instance.new("Folder")
		f.Name = "GwangalliNPCs"
		f.Parent = workspace
	end
	npcFolder = f :: Folder
	local cf = workspace:FindFirstChild("GwangalliLawCars")
	if not cf then
		cf = Instance.new("Folder")
		cf.Name = "GwangalliLawCars"
		cf.Parent = workspace
	end
	carsFolder = cf :: Folder
	task.spawn(function()
		loadNav()
		if D then
			RunService.Heartbeat:Connect(function(dt: number)
				local ok, err = pcall(carMotionStep, dt)
				if not ok then
					warn("[GwangalliLaw] car motion: " .. tostring(err))
				end
			end)
		end
	end)
end

return Police
