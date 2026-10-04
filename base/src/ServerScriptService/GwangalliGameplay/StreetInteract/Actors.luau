-- Interact/Actors (server): the bodies of the Interact NPCs (걸렁뱅이 김씨, 동네바보 만복이, the police)
-- and how they move. The server is only the brain: a rig is an anchored GwangalliNPCLooks R15 in
-- workspace.GwangalliInteractNPCs; its motion is a set of model attributes every client renders
-- (StarterPlayerScripts.GwangalliInteractClient, the Actors renderer):
--   GiLeg  "P;t0;speed;x,y,z;x,y,z;..."  feet polyline walked at `speed` studs/s from server time t0
--          (one point = standing there); GiYaw (degrees, facing while standing); GiPose (a held pose:
--          fight / handsup / cuffed / cower / beg / ko ...); GiEmote "name#seq#time" (one-shot move:
--          punch / shove / hurt / laugh / cheer / wave / point); GiDown "t0|dx|dz|outcome|dur"
--          (stagger / knockdown / ko); GiHP / GiMax (the name tag's bar); GiFace (UserId to face).
-- Walking routes follow ReplicatedStorage.GwangalliNav (sidewalks / crossings) when the straight line is
-- long or blocked; positions are computed here from the same polyline (hit checks, sight, arrests).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Actors = {}

local I: any -- Interact
local C: any
local Looks: any
local Anim: any
local Nav: any
local navCache: any
local folder: Folder

local list: { [string]: any } = {}
Actors.list = list

local function snow(): number
	return workspace:GetServerTimeNow()
end

local function req(name: string): any
	local m = ReplicatedStorage:FindFirstChild(name) or ReplicatedStorage:WaitForChild(name, 15)
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok then
			return res
		end
		warn("[GwangalliInteract] " .. name .. ": " .. tostring(res))
	end
	return nil
end

---------------------------------------------------------------------------------------------------
-- ground + sight queries (rigs, the street pedestrians and characters are never obstacles)
---------------------------------------------------------------------------------------------------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function refreshFilter()
	local ignore: { Instance } = { folder }
	for _, name in { "GwangalliNPCs", "GwangalliStreetLife", "GwangalliTaxis" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(ignore, f)
		end
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = ignore
end
local lastFilter = 0
local function ray(origin: Vector3, dir: Vector3): RaycastResult?
	local t = os.clock()
	if t - lastFilter > 1 then
		lastFilter = t
		refreshFilter()
	end
	local ok, r = pcall(workspace.Raycast, workspace, origin, dir, rayParams)
	return if ok then r else nil
end
Actors.ray = ray

-- the walkable height under p (cast from p + 5 down 14: never the roof of a building above)
function Actors.groundAt(p: Vector3, fallbackY: number?): number
	local r = ray(p + Vector3.new(0, 5, 0), Vector3.new(0, -14, 0))
	if r and r.Instance and r.Instance.CanCollide then
		return r.Position.Y
	end
	return fallbackY or p.Y
end

-- nothing solid between two points (eye height)
function Actors.clear(a: Vector3, b: Vector3): boolean
	local d = b - a
	if d.Magnitude < 0.5 then
		return true
	end
	local r = ray(a, d)
	return r == nil or not r.Instance.CanCollide
end

---------------------------------------------------------------------------------------------------
-- routes (GwangalliNav)
---------------------------------------------------------------------------------------------------
function Actors.route(from: Vector3, to: Vector3): { Vector3 }?
	if not Nav or not navCache then
		return nil
	end
	local okA, a = pcall(Nav.nearest, from, 40)
	local okB, b = pcall(Nav.nearest, to, 40)
	if not okA or not okB or not a or not b then
		return nil
	end
	if a == b then
		return { to }
	end
	local okR, nodes = pcall(Nav.route, a, b, false)
	if not okR or type(nodes) ~= "table" or #nodes == 0 then
		return nil
	end
	local pts = {}
	for _, n in nodes do
		local p = navCache.pos[n]
		if p then
			table.insert(pts, p)
		end
	end
	if #pts >= 2 and (pts[2] - from).Magnitude < (pts[2] - pts[1]).Magnitude then
		table.remove(pts, 1)
	end
	if #pts >= 2 and (pts[#pts - 1] - to).Magnitude < (pts[#pts - 1] - pts[#pts]).Magnitude then
		table.remove(pts)
	end
	table.insert(pts, to)
	return pts
end

-- random walkable nav nodes within r of a centre (areas = Nav area names; nil = any)
function Actors.nodesAround(center: Vector3, r: number, minY: number?, maxY: number?): { Vector3 }
	local out = {}
	if not navCache then
		return out
	end
	for _, p in navCache.pos do
		local dx, dz = p.X - center.X, p.Z - center.Z
		if dx * dx + dz * dz <= r * r and p.Y >= (minY or -1e9) and p.Y <= (maxY or 1e9) then
			table.insert(out, p)
		end
	end
	return out
end

---------------------------------------------------------------------------------------------------
-- attributes
---------------------------------------------------------------------------------------------------
local function setAttr(a: any, k: string, v: any)
	if a.attrs[k] ~= v then
		a.attrs[k] = v
		if a.model and a.model.Parent then
			a.model:SetAttribute(k, v)
		end
	end
end
Actors.setAttr = setAttr

local function encodePath(t0: number, speed: number, pts: { Vector3 }): string
	local parts = { "P", string.format("%.3f", t0), string.format("%.3f", speed) }
	for _, p in pts do
		table.insert(parts, string.format("%.2f,%.2f,%.2f", p.X, p.Y, p.Z))
	end
	return table.concat(parts, ";")
end

-- feet position of an actor now (or at server time t)
function Actors.pos(a: any, t: number?): Vector3
	local path = a.path
	if not path then
		return a.feet
	end
	local now = t or snow()
	local dist = math.max(0, (now - path.t0) * path.speed)
	if dist >= path.len then
		return path.pts[#path.pts]
	end
	local cum = path.cum
	for i = 2, #path.pts do
		if cum[i] >= dist then
			local seg = cum[i] - cum[i - 1]
			local u = if seg > 1e-4 then (dist - cum[i - 1]) / seg else 1
			return path.pts[i - 1]:Lerp(path.pts[i], u)
		end
	end
	return path.pts[#path.pts]
end

-- is the actor still walking (and where to)
function Actors.moving(a: any): boolean
	local path = a.path
	return path ~= nil and (snow() - path.t0) * path.speed < path.len - 0.05
end

local function yawOf(dx: number, dz: number): number
	return math.deg(math.atan2(-dx, -dz))
end
Actors.yawOf = yawOf

-- walk the polyline pts (feet) at speed from where the actor is now
function Actors.walkPts(a: any, pts: { Vector3 }, speed: number)
	local start = Actors.pos(a)
	local all = { start }
	for _, p in pts do
		if (p - all[#all]).Magnitude > 0.05 then
			table.insert(all, p)
		end
	end
	local t0 = snow() + 0.05
	if #all < 2 then
		a.path = nil
		a.feet = start
		setAttr(a, "GiLeg", encodePath(t0, 1, { start }))
		return
	end
	local cum = { 0 }
	for i = 2, #all do
		cum[i] = cum[i - 1] + (all[i] - all[i - 1]).Magnitude
	end
	a.path = { pts = all, cum = cum, len = cum[#cum], t0 = t0, speed = math.max(0.5, speed) }
	a.feet = all[#all]
	local last = all[#all] - all[#all - 1]
	if last.Magnitude > 0.05 then
		setAttr(a, "GiYaw", math.floor(yawOf(last.X, last.Z) + 0.5))
	end
	setAttr(a, "GiLeg", encodePath(t0, a.path.speed, all))
end

-- walk to a point: straight when short / clear, else along the nav graph (straight as the fallback)
function Actors.walkTo(a: any, target: Vector3, speed: number, straight: boolean?)
	local from = Actors.pos(a)
	local flat = Vector3.new(target.X - from.X, 0, target.Z - from.Z).Magnitude
	if flat < 0.3 then
		Actors.stop(a)
		return
	end
	local eye = Vector3.new(0, 2.5, 0)
	if not straight and (flat > 28 or not Actors.clear(from + eye, target + eye)) then
		local pts = Actors.route(from, target)
		if pts and #pts >= 1 then
			Actors.walkPts(a, pts, speed)
			return
		end
	end
	Actors.walkPts(a, { target }, speed)
end

function Actors.stop(a: any)
	local p = Actors.pos(a)
	a.path = nil
	a.feet = p
	setAttr(a, "GiLeg", encodePath(snow(), 1, { p }))
end

function Actors.place(a: any, feet: Vector3, yaw: number?)
	a.path = nil
	a.feet = feet
	if yaw then
		setAttr(a, "GiYaw", math.floor(yaw + 0.5))
	end
	setAttr(a, "GiLeg", encodePath(snow(), 1, { feet }))
end

function Actors.face(a: any, pos: Vector3)
	local p = Actors.pos(a)
	local dx, dz = pos.X - p.X, pos.Z - p.Z
	if dx * dx + dz * dz > 0.01 then
		setAttr(a, "GiYaw", math.floor(yawOf(dx, dz) + 0.5))
	end
end

function Actors.pose(a: any, name: string?)
	setAttr(a, "GiPose", name or "")
end

function Actors.emote(a: any, name: string)
	a.emoteSeq = (a.emoteSeq or 0) + 1
	setAttr(a, "GiEmote", string.format("%s#%d#%.2f", name, a.emoteSeq, snow()))
end

-- fall / stagger / KO for dur seconds (the actor stands still meanwhile)
function Actors.down(a: any, dx: number, dz: number, outcome: string, dur: number?)
	Actors.stop(a)
	local d = if outcome == "stagger" then 0.8 else (dur or 1.4)
	a.downUntil = os.clock() + (if outcome == "stagger" then 0.8 else d + 0.8)
	a.downKind = outcome
	setAttr(a, "GiDown", C.encodeDown(snow(), dx, dz, outcome, d))
end

function Actors.isDown(a: any): boolean
	return a.downUntil ~= nil and os.clock() < a.downUntil
end

function Actors.say(a: any, text: string?, dur: number?)
	if not text or text == "" then
		return
	end
	I.fireAll({ kind = "say", actor = a.id, text = text, dur = dur or 3, typeId = a.typeId or "plain" })
end

function Actors.setHP(a: any)
	setAttr(a, "GiHP", math.max(0, math.floor((a.hp or 0) + 0.5)))
	setAttr(a, "GiMax", a.max or 100)
	local bar = a.hpFill
	if bar and bar.Parent then
		local k = math.clamp((a.hp or 0) / math.max(1, a.max or 100), 0, 1)
		bar.Size = UDim2.fromScale(k, 1)
		bar.BackgroundColor3 = if k > 0.5 then Color3.fromRGB(61, 220, 132) elseif k > 0.25 then Color3.fromRGB(255, 176, 32) else Color3.fromRGB(255, 90, 95)
		if a.hpBack then
			a.hpBack.Visible = k < 0.999
		end
	end
end

function Actors.get(id: string): any?
	return list[id]
end

---------------------------------------------------------------------------------------------------
-- rigs
---------------------------------------------------------------------------------------------------
local function weldPart(rig: any, partName: string, name: string, size: Vector3, offset: CFrame, rgb: { number }, material: Enum.Material?)
	local to = rig.parts and rig.parts[partName]
	if not to then
		return nil
	end
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = false
	p.CastShadow = false
	p.CFrame = to.CFrame * offset
	if Anim and Anim.weld then
		Anim.weld(to, p)
	else
		local w = Instance.new("WeldConstraint")
		w.Part0 = to
		w.Part1 = p
		w.Parent = p
	end
	p.Parent = rig.model
	return p
end

local function nameTag(a: any, head: BasePart, name: string, role: string, color: { number })
	local bb = Instance.new("BillboardGui")
	bb.Name = "NameTag"
	bb.Size = UDim2.fromOffset(170, 54)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0)
	bb.MaxDistance = 70
	bb.LightInfluence = 0
	bb.AlwaysOnTop = false
	bb.Adornee = head
	local n = Instance.new("TextLabel")
	n.Name = "Name"
	n.BackgroundTransparency = 1
	n.Size = UDim2.new(1, 0, 0, 22)
	n.Font = Enum.Font.GothamBold
	n.TextSize = 17
	n.TextColor3 = Color3.new(1, 1, 1)
	n.TextStrokeTransparency = 0.45
	n.Text = name
	n.Parent = bb
	local r = Instance.new("TextLabel")
	r.Name = "Role"
	r.BackgroundTransparency = 1
	r.Position = UDim2.fromOffset(0, 21)
	r.Size = UDim2.new(1, 0, 0, 16)
	r.Font = Enum.Font.Gotham
	r.TextSize = 13
	local c3 = Color3.fromRGB(color[1], color[2], color[3]):Lerp(Color3.new(1, 1, 1), 0.35)
	r.TextColor3 = c3
	r.TextStrokeTransparency = 0.6
	r.Text = role
	r.Parent = bb
	-- the HP bar (shown once hurt)
	local back = Instance.new("Frame")
	back.Name = "HP"
	back.AnchorPoint = Vector2.new(0.5, 0)
	back.Position = UDim2.new(0.5, 0, 0, 41)
	back.Size = UDim2.fromOffset(84, 7)
	back.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
	back.BackgroundTransparency = 0.25
	back.BorderSizePixel = 0
	back.Visible = false
	back.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = back
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(61, 220, 132)
	fill.BorderSizePixel = 0
	fill.Parent = back
	local c2 = Instance.new("UICorner")
	c2.CornerRadius = UDim.new(0, 4)
	c2.Parent = fill
	bb.Parent = head
	a.hpFill = fill
	a.hpBack = back
	a.tag = bb
end

-- police extras: a reflective vest, a belt, a baton in the right hand, "POLICE" on the back
local function dressPolice(rig: any, baton: boolean)
	local ut = rig.parts and rig.parts.UpperTorso
	local s = (rig.scale or 1)
	if ut then
		local vest = weldPart(rig, "UpperTorso", "Vest", ut.Size * Vector3.new(1.06, 0.82, 1.14), CFrame.new(0, -0.08 * s, 0), { 196, 232, 52 })
		if vest then
			local sg = Instance.new("SurfaceGui")
			sg.Name = "PoliceText"
			sg.Face = Enum.NormalId.Back
			sg.LightInfluence = 0
			sg.CanvasSize = Vector2.new(200, 120)
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.Size = UDim2.fromScale(1, 1)
			t.Font = Enum.Font.GothamBlack
			t.TextScaled = true
			t.TextColor3 = Color3.fromRGB(24, 34, 70)
			t.Text = "POLICE\n경찰"
			t.Parent = sg
			sg.Parent = vest
		end
	end
	local lt = rig.parts and rig.parts.LowerTorso
	if lt then
		weldPart(rig, "LowerTorso", "Belt", lt.Size * Vector3.new(1.05, 0.45, 1.08), CFrame.new(0, 0.05 * s, 0), { 22, 22, 26 })
	end
	if baton then
		weldPart(rig, "RightHand", "Baton", Vector3.new(0.22, 0.22, 2.1) * s, CFrame.new(0, -0.15 * s, -0.75 * s), { 18, 18, 20 })
	end
end

-- def = { id, kind, name, role, color {r,g,b}, look (roster look), type (citizen type for the outfit),
--         feet, yaw, hp, typeId, police = bool, baton = bool }
function Actors.spawn(def: any): any?
	if list[def.id] then
		Actors.remove(list[def.id])
	end
	local rig = nil
	if Looks then
		local ok, res = pcall(function()
			local spec
			if def.type and def.type ~= "plain" and Looks.forCitizen then
				spec = Looks.forCitizen({ id = def.id, type = def.type, look = def.look }, false)
			else
				spec = Looks.resolve(def.look or {}, def.id, false)
			end
			return Looks.build(spec, { name = "GI_" .. def.id, anchored = true, shadow = false })
		end)
		if ok and type(res) == "table" and res.model then
			rig = res
		else
			warn("[GwangalliInteract] look build failed for " .. def.id .. ": " .. tostring(res))
		end
	end
	if not rig and Anim and Anim.buildR15 then
		local ok, m, parts = pcall(Anim.buildR15, { name = "GI_" .. def.id, shirt = Color3.fromRGB(40, 60, 120), pants = Color3.fromRGB(30, 30, 40), sleeves = "short", build = "avg", body = "m" })
		if ok and m then
			m:PivotTo(CFrame.new(0, -(Anim.R15 and Anim.R15.rootY or 3), 0) * m:GetPivot())
			rig = { model = m, root = m:FindFirstChild("HumanoidRootPart"), head = m:FindFirstChild("Head"), parts = parts or {}, ground = (Anim.R15 and Anim.R15.rootY) or 3, scale = 1 }
		end
	end
	if not rig or not rig.root then
		return nil
	end
	local a = {
		id = def.id,
		kind = def.kind,
		name = def.name,
		role = def.role,
		typeId = def.typeId or def.type or "plain",
		model = rig.model,
		root = rig.root,
		ground = rig.ground or 3,
		scale = rig.scale or 1,
		hp = def.hp or 60,
		max = def.hp or 60,
		attrs = {},
		feet = def.feet,
		path = nil,
		gone = false,
		color = def.color or { 120, 120, 140 },
	}
	if def.police then
		dressPolice(rig, def.baton == true)
	end
	local head = rig.head or rig.model:FindFirstChild("Head")
	if head then
		nameTag(a, head, def.name, def.role, a.color)
	end
	local m = rig.model
	m:SetAttribute("GiId", def.id)
	m:SetAttribute("GiKind", def.kind)
	m:SetAttribute("GiName", def.name)
	m:SetAttribute("GiType", a.typeId)
	m:SetAttribute("GiGround", a.ground)
	m:SetAttribute("GiScale", a.scale)
	local yaw = def.yaw or 0
	a.attrs.GiYaw = math.floor(yaw + 0.5)
	m:SetAttribute("GiYaw", a.attrs.GiYaw)
	a.attrs.GiLeg = encodePath(snow(), 1, { def.feet })
	m:SetAttribute("GiLeg", a.attrs.GiLeg)
	for _, k in { "GiPose", "GiEmote", "GiDown" } do
		a.attrs[k] = ""
		m:SetAttribute(k, "")
	end
	a.attrs.GiHP = a.hp
	a.attrs.GiMax = a.max
	m:SetAttribute("GiHP", a.hp)
	m:SetAttribute("GiMax", a.max)
	m:PivotTo(CFrame.new(def.feet + Vector3.new(0, a.ground, 0)) * CFrame.Angles(0, math.rad(yaw), 0))
	pcall(function()
		(m :: any).ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	m.Parent = folder
	list[def.id] = a
	return a
end

function Actors.remove(a: any)
	if not a then
		return
	end
	a.gone = true
	if list[a.id] == a then
		list[a.id] = nil
	end
	if a.model then
		a.model:Destroy()
	end
end

-- the closest player to a point (and the distance)
function Actors.closestPlayer(pos: Vector3, maxD: number): (Player?, number)
	local best, bd = nil, maxD
	for _, p in Players:GetPlayers() do
		local f = I.feetOf(p)
		if f then
			local d = I.flatDist(f, pos)
			if d < bd and math.abs(f.Y - pos.Y) < 10 then
				best, bd = p, d
			end
		end
	end
	return best, bd
end

function Actors.init(interact: any)
	I = interact
	C = I.C
	Looks = req("GwangalliNPCLooks")
	Anim = req("GwangalliAnim")
	Nav = req("GwangalliNav")
	if Nav and Nav.decode then
		local ok, cache = pcall(Nav.decode)
		if ok then
			navCache = cache
		end
	end
	local f = workspace:FindFirstChild(C.NpcFolder)
	if f and not f:IsA("Folder") then
		f:Destroy()
		f = nil
	end
	if not f then
		f = Instance.new("Folder")
		f.Name = C.NpcFolder
		f.Parent = workspace
	end
	folder = f :: Folder
	refreshFilter()
end

return Actors
