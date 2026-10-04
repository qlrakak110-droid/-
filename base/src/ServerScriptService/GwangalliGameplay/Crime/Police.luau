-- GwangalliGameplay/Crime/Police (server, child module of Crime): the officers of the 광안지구대.
-- One squad per wanted player (CONFIG.OFFICERS by stars). Officers appear out of sight on the
-- pedestrian nav graph (GwangalliNav, never inside buildings), run to the suspect along routed
-- polylines (far / no line of sight) or straight legs (close, clear line), see the suspect (distance +
-- a throttled workspace:Raycast line of sight), give the stop order, tackle, fight back when assaulted,
-- cuff, search the last known position and walk off when the chase is over.
--
-- Rigs: GwangalliNPCLooks (uniform: navy, cap) + a fluorescent 경찰 vest, under workspace.GwangalliNPCs
-- with the key NPC attribute contract (NpcId "police_<n>", NpcKind "police", NpcAct, NpcLeg, NpcYaw,
-- NpcEmote, NpcGround, NpcKnock, NpcLook, NpcTalk) so GwangalliNPCClient animates them on every client,
-- plus PoliceTarget (UserId), PoliceState and GwEmuFK = true (emulator FK rendering), all set before
-- parenting. The server is only the brain (4 Hz from Crime's loop; nothing per frame): it writes
-- attributes and, at most once a second, the anchored root's CFrame.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Police = {}

local env: any -- { ctx, Util, Combat, BumpShared, crime, send, sendAll }
local Util: any
local Combat: any
local CFG: any
local BumpShared: any
local Crime: any
local Looks: any = nil
local Nav: any = nil

type Officer = {
	id: string,
	n: number,
	model: Model,
	root: BasePart,
	ground: number,
	target: Player,
	squad: any,
	pos: Vector3,
	yaw: number,
	leg: any?,
	state: string,
	hp: number,
	attrs: { [string]: any },
	emoteSeq: number,
	stunUntil: number,
	ko: boolean,
	koUntil: number,
	sees: boolean,
	losAt: number,
	lastSeenAt: number,
	routeAt: number,
	routeGoal: Vector3?,
	routeFail: number,
	nextPunch: number,
	punchN: number,
	lastLine: number,
	lastRootWrite: number,
	spawnedAt: number,
	leaving: boolean,
	leaveGoalAt: number,
	leaveUntil: number,
	searchAt: number,
	act: string,
	nearCheckAt: number,
}

local officers: { [string]: Officer } = {}
local squads: { [Player]: any } = {}
local leaving: { [Officer]: boolean } = {}
local nextN = 0
local folder: Folder? = nil
local stat = { spawned = 0, despawned = 0, routes = 0, routeMs = 0, los = 0, thinkN = 0 }

local MAX_TOTAL = 14 -- officers on the whole server
local SPAWN_GAP = 0.8 -- s between two officers of one squad appearing
local STRAIGHT_MAX = 34 -- straight legs within this (clear line of sight), routed beyond
local ROUTE_EVERY = 1.6
local LOS_EVERY = 0.45
local LINE_GAP = 2.4 -- one bubble per officer per this
local SQUAD_LINE_GAP = 1.2
local LEAVE_MAX = 40 -- s a leaving officer may take before it is removed anyway
local VEST = Color3.fromRGB(204, 255, 46)
local STRIPE = Color3.fromRGB(206, 210, 216)

-------------------------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------------------------
local function serverNow(): number
	local ok, t = pcall(workspace.GetServerTimeNow, workspace)
	return if ok and type(t) == "number" then t else os.clock()
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function flatDist(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function yawOf(v: Vector3): number
	return math.deg(math.atan2(-v.X, -v.Z))
end

local function yawCF(yaw: number): CFrame
	return CFrame.Angles(0, math.rad(yaw), 0)
end

local function optional(name: string): any
	local m = ReplicatedStorage:FindFirstChild(name) or ReplicatedStorage:WaitForChild(name, 5)
	if not m or not m:IsA("ModuleScript") then
		return nil
	end
	local ok, res = pcall(require, m)
	if ok and type(res) == "table" then
		return res
	end
	warn("[GwangalliPolice] " .. name .. " failed to load: " .. tostring(res))
	return nil
end

local navTried = false
local function nav(): any
	if not navTried then
		navTried = true
		Nav = optional("GwangalliNav")
		if Nav then
			local ok = pcall(Nav.decode)
			if not ok then
				Nav = nil
			end
		end
	end
	return Nav
end

local function ensureFolder(): Folder
	if not folder or not folder.Parent then
		local f = workspace:FindFirstChild("GwangalliNPCs")
		if not f or not f:IsA("Folder") then
			f = Instance.new("Folder")
			f.Name = "GwangalliNPCs"
			f.Parent = workspace
		end
		folder = f :: Folder
	end
	return folder :: Folder
end

local function setAttr(o: Officer, key: string, value: any)
	if o.attrs[key] ~= value then
		o.attrs[key] = value
		o.model:SetAttribute(key, value)
	end
end

local function setState(o: Officer, st: string)
	if o.state ~= st then
		o.state = st
		setAttr(o, Combat.Attr.PoliceState, st)
	end
end

local function setAct(o: Officer, act: string)
	if o.act ~= act then
		o.act = act
		setAttr(o, "NpcAct", act)
	end
end

local function emote(o: Officer, name: string)
	o.emoteSeq = (o.emoteSeq % 9999) + 1
	setAttr(o, "NpcEmote", string.format("%s#%d#%.1f", name, o.emoteSeq, serverNow()))
end

local function line(o: Officer, kind: string, force: boolean?)
	local now = os.clock()
	local sq = o.squad
	if not force then
		if now - o.lastLine < LINE_GAP then
			return
		end
		if sq and now - (sq.lastLine or 0) < SQUAD_LINE_GAP then
			return
		end
	end
	local text = Combat.line("police", kind)
	if text then
		o.lastLine = now
		if sq then
			sq.lastLine = now
		end
		Crime.say(o.id, text, "police", 2.4)
	end
end

-------------------------------------------------------------------------------------------------
-- Legs (the GwangalliNPCs NpcLeg contract: clients interpolate from the server clock)
-------------------------------------------------------------------------------------------------
local function polyAt(poly: any, dist: number): Vector3
	local pts, cum = poly.pts, poly.cum
	if dist <= 0 then
		return pts[1]
	end
	for i = 2, #pts do
		if dist <= cum[i] then
			local seg = cum[i] - cum[i - 1]
			local u = if seg > 1e-4 then (dist - cum[i - 1]) / seg else 1
			return pts[i - 1]:Lerp(pts[i], u)
		end
	end
	return pts[#pts]
end

local function currentPos(o: Officer): Vector3
	local leg = o.leg
	if not leg then
		return o.pos
	end
	local a = math.clamp((serverNow() - leg.t0) / leg.dur, 0, 1)
	if leg.poly then
		return polyAt(leg.poly, a * leg.poly.total)
	end
	return leg.from:Lerp(leg.to, a)
end

local function legDone(o: Officer): boolean
	local leg = o.leg
	return leg == nil or serverNow() >= leg.t0 + leg.dur
end

local function legAttr(from: Vector3, to: Vector3, t0: number, dur: number): string
	return string.format("%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f", from.X, from.Y, from.Z, to.X, to.Y, to.Z, t0, dur)
end

local function writeRoot(o: Officer, feet: Vector3)
	o.lastRootWrite = os.clock()
	o.root.CFrame = CFrame.new(feet + Vector3.new(0, o.ground, 0)) * yawCF(o.yaw)
end

local function setYaw(o: Officer, yaw: number)
	yaw = (yaw + 180) % 360 - 180
	if math.abs(((yaw - o.yaw + 180) % 360) - 180) < 3 then
		return
	end
	o.yaw = yaw
	setAttr(o, "NpcYaw", math.floor(yaw * 10 + 0.5) / 10)
end

local function face(o: Officer, at: Vector3, cur: Vector3?)
	local from = cur or currentPos(o)
	local d = flat(at - from)
	if d.Magnitude > 0.4 then
		setYaw(o, yawOf(d))
	end
end

local function halt(o: Officer)
	if not o.leg then
		return
	end
	local p = currentPos(o)
	o.leg = nil
	o.pos = p
	setAttr(o, "NpcLeg", legAttr(p, p, serverNow(), 0.01))
	writeRoot(o, p)
end

local function startLeg(o: Officer, to: Vector3, speed: number)
	local from = currentPos(o)
	local d = flatDist(to, from)
	if d < 0.35 then
		halt(o)
		return
	end
	local dur = d / math.max(speed, 1)
	local t0 = serverNow() + 0.1
	o.leg = { from = from, to = to, t0 = t0, dur = dur }
	o.pos = from
	o.yaw = yawOf(flat(to - from))
	setAttr(o, "NpcYaw", math.floor(o.yaw * 10 + 0.5) / 10)
	setAttr(o, "NpcLeg", legAttr(from, to, t0, dur))
end

local function startPath(o: Officer, raw: { Vector3 }, speed: number)
	local pts: { Vector3 } = {}
	for _, p in raw do
		local q = Vector3.new(math.round(p.X * 10) / 10, math.round(p.Y * 100) / 100, math.round(p.Z * 10) / 10)
		if #pts == 0 or (q - pts[#pts]).Magnitude > 0.05 then
			table.insert(pts, q)
		end
		if #pts >= 32 then
			break -- re-routed long before the end anyway; keeps the attribute small
		end
	end
	if #pts < 2 then
		halt(o)
		return
	end
	local cum = { 0 }
	for i = 2, #pts do
		cum[i] = cum[i - 1] + (pts[i] - pts[i - 1]).Magnitude
	end
	local total = cum[#pts]
	local sp = math.round(math.max(speed, 1) * 1000) / 1000
	local dur = total / sp
	local t0 = math.round((serverNow() + 0.1) * 100) / 100
	o.leg = { from = pts[1], to = pts[#pts], t0 = t0, dur = dur, poly = { pts = pts, cum = cum, total = total } }
	o.pos = pts[1]
	local d = flat(pts[2] - pts[1])
	if d.Magnitude > 0.05 then
		o.yaw = yawOf(d)
		setAttr(o, "NpcYaw", math.floor(o.yaw * 10 + 0.5) / 10)
	end
	local buf = { "P", string.format("%.2f", t0), string.format("%.3f", sp) }
	for _, p in pts do
		table.insert(buf, string.format("%.1f,%.2f,%.1f", p.X, p.Y, p.Z))
	end
	setAttr(o, "NpcLeg", table.concat(buf, ";"))
end

-------------------------------------------------------------------------------------------------
-- Navigation (the pedestrian graph: sidewalks, crossings, promenade, sand; never indoors)
-------------------------------------------------------------------------------------------------
local function edgeOf(c: any, a: number, b: number): number?
	local l = c.adj[a]
	for k = 1, #l, 2 do
		if l[k] == b then
			return l[k + 1]
		end
	end
	return nil
end

local function routePts(from: Vector3, to: Vector3): { Vector3 }?
	local N = nav()
	if not N or type(N.route) ~= "function" or type(N.nearest) ~= "function" then
		return nil
	end
	local t0 = os.clock()
	local c = N.decode()
	local a, b = N.nearest(from, 40), N.nearest(to, 40)
	if not a or not b then
		return nil
	end
	local nodes = if a == b then { a } else N.route(a, b, false)
	stat.routes += 1
	stat.routeMs += (os.clock() - t0) * 1000
	if not nodes or #nodes == 0 then
		return nil
	end
	-- starting / ending between two nodes: skip a first node behind and a last one beyond
	if #nodes >= 2 and flat(c.pos[nodes[2]] - from).Magnitude <= flat(c.pos[nodes[2]] - c.pos[nodes[1]]).Magnitude then
		table.remove(nodes, 1)
	end
	if #nodes >= 2 and flat(c.pos[nodes[#nodes - 1]] - to).Magnitude <= flat(c.pos[nodes[#nodes - 1]] - c.pos[nodes[#nodes]]).Magnitude then
		table.remove(nodes)
	end
	local KX = N.KIND and N.KIND.xwalk
	local KG = N.KIND and N.KIND.xing
	local pts = { from }
	for k, n in nodes do
		local p = c.pos[n]
		table.insert(pts, p)
		local nxt = nodes[k + 1]
		local e = nxt and edgeOf(c, n, nxt)
		if e then
			local _, _, _, kind = N.pedEdge(e)
			if kind == KX or kind == KG then
				-- crossings follow the asphalt (0.5 below the kerbs)
				local q = c.pos[nxt]
				local dv = q - p
				local len = dv.Magnitude
				if len > 3 then
					table.insert(pts, p + dv * (1.2 / len) - Vector3.new(0, 0.5, 0))
					table.insert(pts, q - dv * (1.2 / len) - Vector3.new(0, 0.5, 0))
				end
			end
		end
		if #pts > 34 then
			break
		end
	end
	if #pts <= 34 then
		table.insert(pts, to)
	end
	return pts
end

local GRID = 64
local function gkey(x: number, z: number): number
	return (math.floor(x / GRID) + 512) * 2048 + (math.floor(z / GRID) + 512)
end

-- nav nodes in the ring [minR, maxR] around `center` on its level
local function ringNodes(center: Vector3, minR: number, maxR: number, dyMax: number): { Vector3 }
	local N = nav()
	local out = {}
	if not N then
		return out
	end
	local c = N.decode()
	if not c or not c.grid then
		return out
	end
	local lo, hi = minR * minR, maxR * maxR
	local x0, x1 = math.floor((center.X - maxR) / GRID), math.floor((center.X + maxR) / GRID)
	local z0, z1 = math.floor((center.Z - maxR) / GRID), math.floor((center.Z + maxR) / GRID)
	for gx = x0, x1 do
		for gz = z0, z1 do
			local cell = c.grid[(gx + 512) * 2048 + (gz + 512)]
			if cell then
				for _, i in cell do
					local p = c.pos[i]
					local dx, dz = p.X - center.X, p.Z - center.Z
					local d2 = dx * dx + dz * dz
					if d2 >= lo and d2 <= hi and math.abs(p.Y - center.Y) <= dyMax then
						table.insert(out, p)
					end
				end
			end
		end
	end
	return out
end
local _ = gkey

-------------------------------------------------------------------------------------------------
-- Line of sight
-------------------------------------------------------------------------------------------------
local rayParams: RaycastParams? = nil
local rayParamsAt = -1e9
local function losParams(): RaycastParams
	local now = os.clock()
	if rayParams and now - rayParamsAt < 3 then
		return rayParams :: RaycastParams
	end
	rayParamsAt = now
	local ignore: { Instance } = { ensureFolder() }
	local sl = workspace:FindFirstChild("GwangalliStreetLife")
	if sl then
		table.insert(ignore, sl)
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = ignore
	rp.IgnoreWater = true
	pcall(function()
		(rp :: any).RespectCanCollide = true
	end)
	rayParams = rp
	return rp
end

local function clearLine(a: Vector3, b: Vector3): boolean
	local dir = b - a
	if dir.Magnitude < 0.5 then
		return true
	end
	stat.los += 1
	local ok, hit = pcall(workspace.Raycast, workspace, a, dir, losParams())
	if not ok then
		return true
	end
	return hit == nil
end

-------------------------------------------------------------------------------------------------
-- Rigs
-------------------------------------------------------------------------------------------------
local function extraPart(model: Model, attach: BasePart, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = attach.CFrame * cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Massless = true
	local w = Instance.new("WeldConstraint")
	w.Part0 = attach
	w.Part1 = p
	w.Parent = p
	p.Parent = model
	return p
end

local function dressOfficer(model: Model, parts: { [string]: BasePart }, s: number)
	local ut, lt, head = parts.UpperTorso, parts.LowerTorso, parts.Head
	if ut then
		local sz = ut.Size
		local vest = extraPart(model, ut, "PoliceVest", Vector3.new(sz.X + 0.12 * s, sz.Y * 0.86, sz.Z + 0.14 * s), CFrame.new(0, -0.06 * sz.Y, 0), VEST)
		extraPart(model, ut, "VestStripe", Vector3.new(sz.X + 0.16 * s, 0.16 * s, sz.Z + 0.18 * s), CFrame.new(0, -0.18 * sz.Y, 0), STRIPE)
		local sg = Instance.new("SurfaceGui")
		sg.Name = "VestText"
		sg.Face = Enum.NormalId.Back
		sg.CanvasSize = Vector2.new(200, 120)
		sg.LightInfluence = 0.4
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 0.55)
		t.Position = UDim2.fromScale(0, 0.06)
		t.Font = Enum.Font.GothamBlack
		t.TextScaled = true
		t.TextColor3 = Color3.fromRGB(24, 32, 70)
		t.Text = "경찰"
		t.Parent = sg
		local t2 = Instance.new("TextLabel")
		t2.BackgroundTransparency = 1
		t2.Size = UDim2.fromScale(1, 0.26)
		t2.Position = UDim2.fromScale(0, 0.64)
		t2.Font = Enum.Font.GothamBold
		t2.TextScaled = true
		t2.TextColor3 = Color3.fromRGB(24, 32, 70)
		t2.Text = "POLICE"
		t2.Parent = sg
		sg.Parent = vest
	end
	if lt then
		local sz = lt.Size
		extraPart(model, lt, "DutyBelt", Vector3.new(sz.X + 0.08 * s, 0.2 * s, sz.Z + 0.08 * s), CFrame.new(0, sz.Y * 0.32, 0), Color3.fromRGB(20, 20, 24))
	end
	if head then
		extraPart(model, head, "CapBadge", Vector3.new(0.26 * s, 0.22 * s, 0.06 * s), CFrame.new(0, 0.68 * s, -0.66 * s), Color3.fromRGB(236, 196, 70))
	end
end

local function nameTag(head: BasePart?)
	if not head then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "NameTag"
	bb.Size = UDim2.fromOffset(150, 40)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
	bb.MaxDistance = 60
	bb.LightInfluence = 0
	bb.ResetOnSpawn = false
	bb.Adornee = head
	local n = Instance.new("TextLabel")
	n.Name = "Name"
	n.BackgroundTransparency = 1
	n.Size = UDim2.new(1, 0, 0.55, 0)
	n.Font = Enum.Font.GothamBold
	n.TextScaled = true
	n.TextColor3 = Color3.new(1, 1, 1)
	n.TextStrokeTransparency = 0.4
	n.Text = "👮 경찰관"
	n.Parent = bb
	local r = Instance.new("TextLabel")
	r.Name = "Role"
	r.BackgroundTransparency = 1
	r.Position = UDim2.fromScale(0, 0.55)
	r.Size = UDim2.new(1, 0, 0.45, 0)
	r.Font = Enum.Font.Gotham
	r.TextScaled = true
	r.TextColor3 = Color3.fromRGB(170, 196, 255)
	r.TextStrokeTransparency = 0.5
	r.Text = "광안지구대"
	r.Parent = bb
	bb.Parent = head
end

local function buildOfficer(n: number, feet: Vector3, yaw: number, target: Player): Officer?
	if not Looks then
		return nil
	end
	local id = Combat.POLICE_PREFIX .. n
	local female = (n % 5) == 3
	local okS, spec = pcall(Looks.resolve, {
		body = if female then "f" else "m",
		age = "adult",
		style = "uniform",
		acc = "cap",
		build = "avg",
		hair = if female then "bun" else "short",
		hc = "black",
		height = 1.02,
	}, "police#" .. n, false)
	if not okS or type(spec) ~= "table" then
		warn("[GwangalliPolice] look failed: " .. tostring(spec))
		return nil
	end
	local okB, rig = pcall(Looks.build, spec, { name = "Police_" .. n, anchored = true, shadow = false })
	if not okB or type(rig) ~= "table" or not rig.model then
		warn("[GwangalliPolice] rig build failed: " .. tostring(rig))
		return nil
	end
	local model: Model = rig.model
	local root: BasePart = rig.root
	local ground = rig.ground or 3
	pcall(dressOfficer, model, rig.parts, rig.scale or 1)
	nameTag(rig.parts.Head)
	-- the GwangalliNPCs contract, complete before the model is parented
	local attrs = {
		NpcId = id,
		NpcKind = Combat.POLICE_KIND,
		NpcAct = "idle",
		NpcYaw = math.floor(yaw * 10 + 0.5) / 10,
		NpcLook = target.UserId,
		NpcTalk = 0,
		NpcLeg = "",
		NpcEmote = "",
		NpcGround = ground,
		NpcKnock = "",
		[Combat.Attr.PoliceTarget] = target.UserId,
		[Combat.Attr.PoliceState] = "dispatch",
		[Combat.Attr.EmuFK] = true,
	}
	for k, v in attrs do
		model:SetAttribute(k, v)
	end
	model:PivotTo(CFrame.new(feet + Vector3.new(0, ground, 0)) * yawCF(yaw))
	pcall(function()
		(model :: any).ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	local o: Officer = {
		id = id,
		n = n,
		model = model,
		root = root,
		ground = ground,
		target = target,
		squad = nil,
		pos = feet,
		yaw = yaw,
		leg = nil,
		state = "dispatch",
		hp = CFG.POLICE_HP,
		attrs = attrs,
		emoteSeq = 0,
		stunUntil = 0,
		ko = false,
		koUntil = 0,
		sees = false,
		losAt = 0,
		lastSeenAt = -1e9,
		routeAt = 0,
		routeGoal = nil,
		routeFail = 0,
		nextPunch = 0,
		punchN = 0,
		lastLine = -1e9,
		lastRootWrite = os.clock(),
		spawnedAt = os.clock(),
		leaving = false,
		leaveGoalAt = 0,
		leaveUntil = 0,
		searchAt = 0,
		act = "idle",
		nearCheckAt = 0,
	}
	model.Parent = ensureFolder()
	officers[id] = o
	stat.spawned += 1
	return o
end

local function destroyOfficer(o: Officer)
	officers[o.id] = nil
	leaving[o] = nil
	stat.despawned += 1
	pcall(function()
		o.model:Destroy()
	end)
end

-------------------------------------------------------------------------------------------------
-- Squads
-------------------------------------------------------------------------------------------------
local function squadOf(player: Player, create: boolean): any?
	local sq = squads[player]
	if not sq and create then
		sq = { player = player, list = {}, want = 0, nextSpawn = 0, lastKnown = nil, radioUntil = 0, lastLine = 0, cuffer = nil, arrestBy = nil }
		squads[player] = sq
	end
	return sq
end

local function totalOfficers(): number
	local n = 0
	for _ in officers do
		n += 1
	end
	return n
end

local function playerFeet(player: Player): (Vector3?, BasePart?, Humanoid?)
	local _, hum, root = Util.alive(player)
	if not hum or not root then
		return nil, nil, nil
	end
	return root.Position - Vector3.new(0, Util.standHeight(hum, root), 0), root, hum
end

-- out of sight (behind a building from the suspect's eyes), 45..70 studs away, preferably behind
local function spawnSpot(player: Player): (Vector3?, Vector3?)
	local feet, root = playerFeet(player)
	if not feet or not root then
		return nil, nil
	end
	local cands = ringNodes(feet, CFG.SPAWN_MIN, CFG.SPAWN_MAX, 6)
	if #cands == 0 then
		cands = ringNodes(feet, 30, CFG.SPAWN_MAX + 20, 8)
	end
	if #cands == 0 then
		return nil, feet
	end
	local look = flat(root.CFrame.LookVector)
	look = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
	local others = {}
	for _, p in Players:GetPlayers() do
		if p ~= player then
			local pp = Util.rootPosition(p)
			if pp then
				table.insert(others, pp)
			end
		end
	end
	local scored = {}
	for _, p in cands do
		local to = flat(p - feet)
		local d = to.Magnitude
		local score = -math.abs(d - 55) * 0.5
		if d > 1e-3 and look:Dot(to / d) < -0.2 then
			score += 15
		end
		for _, q in others do
			if flatDist(p, q) < 30 then
				score -= 40
			end
		end
		-- other officers of the squad should not pop out of the same spot
		for _, o in officers do
			if flatDist(o.pos, p) < 6 then
				score -= 20
			end
		end
		table.insert(scored, { p = p, s = score + math.random() * 4 })
	end
	table.sort(scored, function(a, b)
		return a.s > b.s
	end)
	-- out of the suspect's sight AND a sensible run to them (a node across a wall / on another level
	-- can be 50 studs away in a straight line but 300 along the sidewalks)
	local eye = root.Position + Vector3.new(0, 1.5, 0)
	local fallback: Vector3? = nil
	for k = 1, math.min(#scored, 5) do
		local p = scored[k].p
		local pts = routePts(p, feet)
		local okRoute = false
		if pts then
			local len = 0
			for i = 2, #pts do
				len += (pts[i] - pts[i - 1]).Magnitude
			end
			okRoute = len <= flatDist(p, feet) * 1.8 + 20
		end
		if okRoute then
			if not clearLine(eye, p + Vector3.new(0, 4.5, 0)) then
				return p, feet
			end
			fallback = fallback or p
		end
	end
	return fallback, feet
end

local function spawnOne(sq: any, at: Vector3?): Officer?
	local player = sq.player
	if totalOfficers() >= MAX_TOTAL then
		return nil
	end
	local spot, feet = at, nil
	if not spot then
		spot, feet = spawnSpot(player)
	else
		feet = playerFeet(player)
	end
	if not spot then
		return nil
	end
	nextN += 1
	local yaw = if feet then yawOf(flat(feet - spot)) else 0
	local o = buildOfficer(nextN, spot, yaw, player)
	if not o then
		return nil
	end
	o.squad = sq
	table.insert(sq.list, o)
	setState(o, "dispatch")
	if os.clock() - (sq.lastLine or 0) > 3 then
		line(o, "dispatch")
	end
	return o
end

local function activeOf(sq: any): { Officer }
	local out = {}
	for _, o in sq.list do
		if not o.leaving and not o.ko then
			table.insert(out, o)
		end
	end
	return out
end

-- the officer walks off (out of sight) and is removed
local function sendAway(o: Officer)
	if o.leaving then
		return
	end
	o.leaving = true
	o.leaveUntil = os.clock() + LEAVE_MAX
	o.leaveGoalAt = 0
	setState(o, "leave")
	setAct(o, "idle")
	setAttr(o, "NpcLook", 0)
	leaving[o] = true
	local sq = o.squad
	if sq then
		local i = table.find(sq.list, o)
		if i then
			table.remove(sq.list, i)
		end
	end
end

-------------------------------------------------------------------------------------------------
-- API used by Crime
-------------------------------------------------------------------------------------------------
function Police.init(e: any)
	env = e
	Util = e.Util
	Combat = e.Combat
	CFG = Combat.CONFIG
	BumpShared = e.BumpShared
	Crime = e.crime
	Looks = optional("GwangalliNPCLooks")
	if not Looks then
		warn("[GwangalliPolice] GwangalliNPCLooks missing: no officers")
	end
	task.defer(nav)
end

-- a crime was reported here: dispatch knows the suspect's exact position for a while (radio)
function Police.alert(player: Player, pos: Vector3?)
	local sq = squadOf(player, true)
	if sq then
		sq.lastKnown = pos or sq.lastKnown
		sq.radioUntil = os.clock() + 8
	end
end

function Police.ensure(player: Player, stars: number)
	local sq = squadOf(player, stars > 0)
	if not sq then
		return
	end
	sq.want = Combat.officersFor(stars)
	local act = activeOf(sq)
	if #act > sq.want then
		local feet = playerFeet(player)
		table.sort(act, function(a, b)
			if not feet then
				return a.n > b.n
			end
			return flatDist(currentPos(a), feet) > flatDist(currentPos(b), feet)
		end)
		for k = 1, #act - sq.want do
			line(act[k], "lost", true)
			sendAway(act[k])
		end
	end
end

-- the chase is over (escaped / arrested): every officer of the squad walks off
function Police.release(player: Player, why: string?)
	local sq = squads[player]
	squads[player] = nil
	if not sq then
		return
	end
	local first = true
	for _, o in table.clone(sq.list) do
		if o.ko then
			-- lies until the KO is over, then gets up and walks off (the leaving loop runs its timer)
			local i = table.find(sq.list, o)
			if i then
				table.remove(sq.list, i)
			end
			o.squad = nil
			leaving[o] = true
		else
			if first and why == "escaped" then
				line(o, "lost", true)
				first = false
			end
			sendAway(o)
		end
	end
end

-- removes the squad at once (the suspect left the server)
function Police.clear(player: Player)
	local sq = squads[player]
	squads[player] = nil
	for _, o in officers do
		if o.target == player then
			destroyOfficer(o)
		end
	end
	local _ = sq
end

function Police.get(id: any): Officer?
	if type(id) ~= "string" then
		return nil
	end
	local o = officers[id]
	if o and o.model.Parent then
		return o
	end
	return nil
end

function Police.position(o: Officer): Vector3?
	if not o or not o.model.Parent then
		return nil
	end
	return currentPos(o)
end

function Police.nearest(player: Player): (Officer?, number)
	local feet = playerFeet(player)
	local sq = squads[player]
	if not feet or not sq then
		return nil, math.huge
	end
	local best, bd = nil, math.huge
	for _, o in sq.list do
		if not o.ko and not o.leaving then
			local d = flatDist(currentPos(o), feet)
			if d < bd then
				best, bd = o, d
			end
		end
	end
	return best, bd
end

-- the suspect raised their hands: the nearest officer comes to cuff, the others cover
function Police.surrendered(player: Player)
	local sq = squads[player]
	local o = Police.nearest(player)
	if not sq or not o then
		return
	end
	sq.cuffer = o.id
	line(o, "cuff", true)
end

-- the arrest started: the cuffing officer plays the cuffing act, the others cover
function Police.cuffing(player: Player, officerId: string?)
	local sq = squads[player]
	if not sq then
		return
	end
	local feet = playerFeet(player)
	local by = officerId and officers[officerId]
	if not by and feet then
		local o, d = Police.nearest(player)
		if o and d < 14 then
			by = o
		end
	end
	sq.arrestBy = by and by.id or nil
	if by then
		halt(by)
		if feet then
			face(by, feet)
		end
		setState(by, "cuff")
		setAct(by, "cb_cuffing")
		line(by, "cuff", true)
	end
end

-- the car (PoliceCar) unloads officers at `at` (feet); returns how many appeared
function Police.spawnAt(player: Player, at: Vector3, n: number): number
	local sq = squadOf(player, true)
	if not sq or typeof(at) ~= "Vector3" then
		return 0
	end
	local made = 0
	for k = 1, math.clamp(math.floor(tonumber(n) or 1), 1, 3) do
		local offs = Vector3.new((k - 2) * 1.8, 0, 0)
		if spawnOne(sq, at + offs) then
			made += 1
		end
	end
	return made
end

-- a punch / 어깨빵 landed on an officer. Returns hp, outcome (nil: already down)
function Police.hit(o: Officer, dmg: number, combo: number, dx: number, dz: number, attacker: Player?): (number?, string)
	if not o or o.ko or not o.model.Parent then
		return nil, "down"
	end
	local now = os.clock()
	o.hp = math.max(0, o.hp - dmg)
	local outcome = Combat.outcome(combo, o.hp)
	halt(o)
	if outcome == "hit" then
		emote(o, "cb_flinchF")
		o.stunUntil = math.max(o.stunUntil, now + 0.35)
	elseif outcome == "ko" then
		-- out cold: the cb_ko act pose lays the body down on every client (no fall timeline to refresh)
		emote(o, "cb_flinchB")
		setAct(o, "cb_ko")
	elseif BumpShared then
		local down = outcome ~= "stagger"
		setAttr(o, "NpcKnock", BumpShared.encodeKnock(serverNow(), dx, dz, if down then "knockdown" else "stagger"))
		o.stunUntil = math.max(o.stunUntil, now + (if down then BumpShared.KNOCK_DUR + BumpShared.GETUP_DUR else BumpShared.STAGGER_DUR))
	end
	if outcome == "ko" then
		o.ko = true
		o.koUntil = now + CFG.NPC_KO_TIME
		o.stunUntil = o.koUntil
		setState(o, "ko")
		setAttr(o, "NpcLook", 0)
		task.delay(0.6, function()
			if o.model.Parent then
				Crime.say(o.id, "크윽…", "police", 2)
			end
		end)
	else
		line(o, if outcome == "hit" then "hit" else "fight", true)
	end
	-- the attacker is the one to deal with now
	if attacker and o.squad and attacker == o.target and not o.ko then
		setState(o, "fight")
	end
	return o.hp, outcome
end

function Police.stats(): any
	return {
		officers = totalOfficers(),
		spawned = stat.spawned,
		despawned = stat.despawned,
		routes = stat.routes,
		routeMsAvg = if stat.routes > 0 then stat.routeMs / stat.routes else 0,
		los = stat.los,
		thinks = stat.thinkN,
	}
end

-- an officer that can still give / enforce orders (not KO, not walking off)
function Police.active(id: any): boolean
	local o = Police.get(id)
	return o ~= nil and not o.ko and not o.leaving
end

function Police.officersOf(player: Player): { Officer }
	local sq = squads[player]
	return if sq then table.clone(sq.list) else {}
end

-------------------------------------------------------------------------------------------------
-- Brain
-------------------------------------------------------------------------------------------------
local function moveToward(o: Officer, cur: Vector3, goal: Vector3, speed: number, stop: number, clear: boolean, now: number)
	local d = flatDist(cur, goal)
	if d <= stop + 0.3 then
		halt(o)
		return
	end
	local dir = flat(goal - cur).Unit
	local aim = goal - dir * stop
	if clear and d <= STRAIGHT_MAX and math.abs(goal.Y - cur.Y) <= 3.5 then
		local leg = o.leg
		if not leg or leg.poly or legDone(o) or flatDist(leg.to, aim) > 1.6 or math.abs((leg.speed or 0) - speed) > 0.5 then
			startLeg(o, aim, speed)
			if o.leg then
				o.leg.speed = speed
			end
		end
		o.routeGoal = nil
		return
	end
	-- routed walk along the nav graph
	local leg = o.leg
	local stale = not leg or not leg.poly or legDone(o) or (o.routeGoal and flatDist(o.routeGoal, goal) > 10) or math.abs((leg.speed or 0) - speed) > 0.5
	if stale and now >= o.routeAt then
		o.routeAt = now + ROUTE_EVERY
		local pts = if now >= o.routeFail then routePts(cur, aim) else nil
		if pts and #pts >= 2 then
			startPath(o, pts, speed)
			if o.leg then
				o.leg.speed = speed
			end
			o.routeGoal = goal
		else
			o.routeFail = now + 3
			-- no route: close in straight only when it is short and clear
			if clear and d <= 50 then
				startLeg(o, aim, speed)
			else
				halt(o)
			end
		end
	end
end

local function punch(o: Officer, player: Player, feet: Vector3, cur: Vector3, now: number)
	halt(o)
	face(o, feet, cur)
	setAct(o, "cb_guard")
	o.punchN = (o.punchN % 3) + 1
	local combo = o.punchN
	emote(o, "cb_" .. Combat.clipOf(combo))
	o.nextPunch = now + CFG.POLICE_PUNCH.cadence + math.random() * 0.25
	if combo == 1 then
		line(o, "fight")
	end
	task.delay(CFG.PUNCH.hitDelay[combo] or 0.16, function()
		if not o.model.Parent or o.ko or os.clock() < o.stunUntil then
			return
		end
		local f2 = playerFeet(player)
		local p = currentPos(o)
		if f2 and flatDist(p, f2) <= CFG.POLICE_PUNCH.range + 1.5 and math.abs(f2.Y - p.Y) < 5 then
			local dx, dz = Combat.flatDir(p, f2)
			Crime.policePunch(player, o.id, combo, dx, dz)
		end
	end)
end

local function koUpdate(o: Officer, now: number)
	if now < o.koUntil then
		return
	end
	-- gets up (the act pose blends back) and walks off; a replacement comes if the chase goes on
	o.ko = false
	o.hp = CFG.POLICE_HP
	setAct(o, "idle")
	emote(o, "shake")
	o.stunUntil = now + 0.8
	sendAway(o)
end

local function leaveUpdate(o: Officer, now: number)
	local cur = currentPos(o)
	if now >= o.leaveUntil then
		destroyOfficer(o)
		return
	end
	if now < o.stunUntil then
		return
	end
	-- nobody near (or nobody can see it): gone (checked once a second)
	local near = true
	if now >= o.nearCheckAt then
		o.nearCheckAt = now + 1
		near = false
	end
	for _, p in if near then {} else Players:GetPlayers() do
		local pp = Util.rootPosition(p)
		if pp and (pp - cur).Magnitude < 70 then
			if (pp - cur).Magnitude < 40 or clearLine(pp + Vector3.new(0, 1.5, 0), cur + Vector3.new(0, 4.5, 0)) then
				near = true
				break
			end
		end
	end
	if not near and now - (o.leaveUntil - LEAVE_MAX) > 1.5 then
		destroyOfficer(o)
		return
	end
	if legDone(o) and now >= o.leaveGoalAt then
		o.leaveGoalAt = now + 6
		-- a node away from the players
		local away = o.target and Util.rootPosition(o.target)
		local cands = ringNodes(cur, 25, 60, 6)
		local best, bs = nil, -math.huge
		for _, p in cands do
			local s = math.random() * 5
			if away then
				s += flatDist(p, away) * 0.5
			end
			if s > bs then
				best, bs = p, s
			end
		end
		if best then
			local pts = routePts(cur, best)
			if pts and #pts >= 2 then
				startPath(o, pts, CFG.POLICE_SPEED.walk)
			else
				startLeg(o, best, CFG.POLICE_SPEED.walk)
			end
		end
	end
	if o.leg and os.clock() - o.lastRootWrite > 1 then
		writeRoot(o, cur)
	end
end

local function think(o: Officer, sq: any, s: any, player: Player, feet: Vector3?, root: BasePart?, now: number)
	stat.thinkN += 1
	if o.ko then
		koUpdate(o, now)
		return
	end
	if now < o.stunUntil then
		return
	end
	local cur = currentPos(o)
	if o.leg and now - o.lastRootWrite > 1 then
		writeRoot(o, cur)
	end
	if not feet or not root then
		halt(o)
		o.sees = false
		return
	end
	local d = flatDist(cur, feet)
	local dy = math.abs(feet.Y - cur.Y)
	-- hopelessly far (a detour, the suspect sped off): walk off, a closer one is sent instead
	if d > 150 and now - o.spawnedAt > 6 and now - o.lastSeenAt > 6 and not s.arresting then
		sendAway(o)
		return
	end
	-- sight (throttled ray)
	if now >= o.losAt then
		o.losAt = now + LOS_EVERY + math.random() * 0.1
		local eye = cur + Vector3.new(0, o.ground + 1.5, 0)
		o.sees = d <= CFG.SIGHT and dy < 14 and clearLine(eye, root.Position + Vector3.new(0, 1.2, 0))
		if o.sees then
			if now - o.lastSeenAt > 6 and o.state ~= "order" and o.state ~= "fight" then
				emote(o, "point_proc")
				line(o, "chase")
			end
			o.lastSeenAt = now
		end
	end
	if o.sees then
		sq.lastKnown = feet
	end
	local runSpeed = Combat.policeRunSpeed(math.max(1, s.stars))
	local walkSpeed = CFG.POLICE_SPEED.walk
	-- the arrest is running: cover / cuff
	if s.arresting then
		if sq.arrestBy == o.id then
			halt(o)
			face(o, feet, cur)
			setAct(o, "cb_cuffing")
		else
			if d > 7 and d < 40 then
				moveToward(o, cur, feet, walkSpeed, 5.5, o.sees, now)
			else
				halt(o)
			end
			face(o, feet, cur)
			setAct(o, "cb_guard")
			setState(o, "cuff")
		end
		return
	end
	-- the suspect is KO: walk up (Crime arrests a moment later)
	if s.ko then
		setState(o, "cuff")
		setAct(o, "idle")
		moveToward(o, cur, feet, walkSpeed, 2.2, true, now)
		return
	end
	-- surrendered: the cuffer walks up, the others cover
	if s.surrender then
		setState(o, "cuff")
		if sq.cuffer == nil or not officers[sq.cuffer] or officers[sq.cuffer].ko then
			sq.cuffer = o.id
		end
		if sq.cuffer == o.id then
			setAct(o, "idle")
			if d <= CFG.GRAB_RANGE + 0.4 then
				halt(o)
				face(o, feet, cur)
				Crime.grab(player, o.id, false)
			else
				moveToward(o, cur, feet, walkSpeed, 1.8, true, now)
			end
		else
			setAct(o, "cb_guard")
			if d > 7 then
				moveToward(o, cur, feet, walkSpeed, 5.5, o.sees, now)
			else
				halt(o)
				face(o, feet, cur)
			end
		end
		return
	end
	-- just tackled: the arrest follows in a moment
	if now - (s.tackleAt or -1e9) < 3 then
		halt(o)
		face(o, feet, cur)
		setAct(o, "cb_guard")
		return
	end
	local fight = now < (s.fightUntil or 0)
	-- the stop order is out
	if s.order and not fight then
		setState(o, "order")
		setAct(o, "cb_guard")
		if s.order.officer == o.id then
			local vel = root.AssemblyLinearVelocity
			local speedP = Vector3.new(vel.X, 0, vel.Z).Magnitude
			if d > CFG.ORDER_RANGE + 4 or speedP > 14 then
				Crime.fled(player, o.id, "run")
				setState(o, "chase")
				return
			end
			if d > 4.5 then
				moveToward(o, cur, feet, 5, 4, true, now)
			else
				halt(o)
				face(o, feet, cur)
			end
		else
			if d > 7 then
				moveToward(o, cur, feet, if d > 15 then runSpeed else walkSpeed, 6, o.sees, now)
			else
				halt(o)
				face(o, feet, cur)
			end
		end
		return
	end
	-- assaulted: fists up
	if fight then
		setState(o, "fight")
		if o.sees and d <= CFG.POLICE_PUNCH.range and dy < 5 then
			if now >= o.nextPunch then
				punch(o, player, feet, cur, now)
			else
				halt(o)
				face(o, feet, cur)
				setAct(o, "cb_guard")
			end
		else
			setAct(o, "idle")
			moveToward(o, cur, feet, runSpeed, 2.6, o.sees, now)
		end
		return
	end
	if o.sees then
		local riding = env.ctx and env.ctx.isRiding and env.ctx.isRiding(player)
		if d <= CFG.GRAB_RANGE and dy < 4 and not riding and now >= (s.downUntil or 0) then
			halt(o)
			face(o, feet, cur)
			emote(o, "cb_cross")
			setState(o, "cuff")
			local dx, dz = Combat.flatDir(cur, feet)
			Crime.grab(player, o.id, true, dx, dz)
			return
		end
		if d <= CFG.ORDER_RANGE and dy < 4 and now - (s.orderAt or -1e9) > 25 then
			halt(o)
			face(o, feet, cur)
			setState(o, "order")
			setAct(o, "cb_guard")
			emote(o, "stop_hand")
			line(o, "order", true)
			Crime.ordered(player, o.id)
			return
		end
		setState(o, "chase")
		setAct(o, "idle")
		-- aim a little ahead of a running suspect; before the stop order the officer pulls up at
		-- talking distance (so a slow tick never skips the order and tackles straight away)
		local vel = root.AssemblyLinearVelocity
		local lead = Vector3.new(vel.X, 0, vel.Z) * 0.35
		if lead.Magnitude > 8 then
			lead = lead.Unit * 8
		end
		local orderDue = now - (s.orderAt or -1e9) > 25
		moveToward(o, cur, feet + lead, runSpeed, if orderDue then CFG.ORDER_RANGE - 2.5 else 1.4, true, now)
		return
	end
	-- not seen: dispatch (radio knows where) / search the last known position
	local radio = now < sq.radioUntil
	local goal = if radio then feet else (sq.lastKnown or feet)
	local gd = flatDist(cur, goal)
	if radio or gd > 6 then
		setState(o, if radio or now - o.lastSeenAt > 20 and o.state == "dispatch" then "dispatch" else "search")
		setAct(o, "idle")
		moveToward(o, cur, goal, runSpeed, 1.5, false, now)
		return
	end
	-- at the last known spot: look around nearby
	setState(o, "search")
	if legDone(o) and now >= o.searchAt then
		o.searchAt = now + 3 + math.random() * 2
		local cands = ringNodes(goal, 8, 26, 5)
		if #cands > 0 then
			local p = cands[math.random(#cands)]
			setAct(o, "look")
			local pts = routePts(cur, p)
			if pts and #pts >= 2 then
				startPath(o, pts, walkSpeed)
			else
				startLeg(o, p, walkSpeed)
			end
			line(o, "search")
		end
	end
end

function Police.tick()
	local now = os.clock()
	for player, sq in squads do
		if player.Parent ~= Players then
			Police.clear(player)
			continue
		end
		local s = Crime.stateOf(player)
		if not s or (s.stars <= 0 and not s.arresting) then
			Police.release(player, "clear")
			continue
		end
		-- drop officers that vanished
		for i = #sq.list, 1, -1 do
			local o = sq.list[i]
			if not o.model.Parent then
				table.remove(sq.list, i)
				officers[o.id] = nil
			end
		end
		-- reinforcements (staggered: one rig at a time)
		if not s.arresting and not s.ko and now >= sq.nextSpawn and #activeOf(sq) < sq.want then
			sq.nextSpawn = now + SPAWN_GAP
			local ok, res = pcall(spawnOne, sq)
			if not ok then
				warn("[GwangalliPolice] spawn failed: " .. tostring(res))
				sq.nextSpawn = now + 5
			elseif not res then
				sq.nextSpawn = now + 3 -- no good spot right now (indoors / far from the sidewalks): retry later
			end
		end
		local feet, root = playerFeet(player)
		local seen = false
		for _, o in table.clone(sq.list) do
			local ok, err = pcall(think, o, sq, s, player, feet, root, now)
			if not ok then
				warn("[GwangalliPolice] officer brain failed: " .. tostring(err))
			end
			if o.sees and not o.ko then
				seen = true
			end
		end
		Crime.sighted(player, seen, if seen then feet else nil)
	end
	for o in leaving do
		local ok, err = pcall(function()
			if o.ko then
				koUpdate(o, now)
			else
				leaveUpdate(o, now)
			end
		end)
		if not ok then
			warn("[GwangalliPolice] leaving officer failed: " .. tostring(err))
			destroyOfficer(o)
		end
	end
end

return Police
