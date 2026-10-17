-- GwangalliClinic/Site: the map clinic on the server. Resolves the map parts (read-only), builds our own
-- objects in Workspace.GwangalliClinic (never inside the map):
--   Anchors (Model, ModelStreamingMode Persistent): invisible non-colliding parts the client puts its
--     local ProximityPrompts on (attributes ClinicKind / ClinicLabel / ClinicStation)
--   Staff   (Folder of Anim.buildR15 rigs, Atomic): 원무과 x2, 주사실 간호사, 약사, 검진센터 직원
-- and owns the zone test, distance checks, seat / bed placement (Seat:Sit, or lying on a mattress with
-- the root anchored for IV / ECG) and bed reservations. All our parts: CanCollide / CanTouch / CanQuery
-- false, so the NPC walk grid (Law/Hospital) and the interior team's decor are unaffected.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Site = {}

local K: any
local S: any
local C: any

Site.venue = nil :: Model?
Site.anchors = {} :: { [string]: BasePart }
Site.seats = {} :: { [string]: Seat }
Site.parts = {} :: { [string]: BasePart }
Site.staff = {} :: { [string]: Model }
Site.zoneCF = nil :: CFrame?
Site.zoneSize = nil :: Vector3?

local reserved: { [string]: Player } = {}
local lying: { [Player]: { anchor: string, root: BasePart } } = {}
local worldFolder: Folder

local function log(...)
	if C.Debug then
		print("[GwangalliClinic/Site]", ...)
	end
end

-------------------------------------------------------------------------------------------------
-- map lookup
-------------------------------------------------------------------------------------------------
local function findVenue(): Model?
	local cur: Instance? = workspace
	for _, name in C.Venue.Path do
		cur = cur and cur:FindFirstChild(name)
	end
	if cur and cur:IsA("Model") then
		return cur
	end
	for _, d in workspace:GetDescendants() do
		if d:IsA("Model") and d.Name == C.Venue.Name then
			return d
		end
	end
	return nil
end

local function byPath(path: string): Instance?
	local v = Site.venue
	if not v then
		return nil
	end
	local cur: Instance? = v
	for seg in string.gmatch(path, "[^/]+") do
		cur = cur and cur:FindFirstChild(seg)
	end
	return cur
end
Site.byPath = byPath

local function partOf(inst: Instance?): BasePart?
	if not inst then
		return nil
	end
	if inst:IsA("BasePart") then
		return inst
	end
	if inst:IsA("Model") then
		return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

function Site.floorY(n: number?): number
	return if n == 2 then C.Venue.Floor2 else C.Venue.Floor1
end

-------------------------------------------------------------------------------------------------
-- anchors
-------------------------------------------------------------------------------------------------
local function makeAnchor(parent: Instance, name: string, pos: Vector3, spec: any): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(1.2, 1.2, 1.2)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.CFrame = CFrame.new(pos)
	p:SetAttribute(S.NAMES.AttrKind, spec.kind)
	p:SetAttribute(S.NAMES.AttrLabel, spec.label)
	if spec.station then
		p:SetAttribute(S.NAMES.AttrStation, spec.station)
	end
	if spec.ward then
		p:SetAttribute("ClinicWard", spec.ward)
	end
	p.Parent = parent
	return p
end

local function nearestPart(root: Instance, className: string, near: Vector3, name: string?, maxDist: number): BasePart?
	local best, bestD = nil, maxDist
	for _, d in root:GetDescendants() do
		if d:IsA(className) and (name == nil or d.Name == name) then
			local dist = ((d :: BasePart).Position - near).Magnitude
			if dist < bestD then
				best, bestD = d, dist
			end
		end
	end
	return best
end

local function resolveAnchor(name: string, spec: any): (Vector3, Seat?)
	local inst = byPath(spec.path)
	local part = partOf(inst)
	local seat: Seat? = nil
	local pos: Vector3
	if spec.panelNear and inst then
		local panel = nearestPart(inst, "BasePart", spec.panelNear, "CallPanel", 6)
		part = panel or nil
	end
	if spec.seat == "self" and part and part:IsA("Seat") then
		seat = part
	elseif spec.seat == "near" and part and Site.venue then
		local s = nearestPart(part.Parent or Site.venue, "Seat", part.Position, nil, 9)
		if s and s:IsA("Seat") then
			seat = s
			part = s
		end
	end
	if part then
		pos = part.Position + (spec.at or Vector3.zero)
		if spec.floor then
			pos = Vector3.new(pos.X, Site.floorY(spec.floor) + (spec.y or 2.6), pos.Z)
		end
	else
		pos = spec.fallback
		log("anchor", name, "uses its fallback position")
	end
	return pos, seat
end

-------------------------------------------------------------------------------------------------
-- staff rigs
-------------------------------------------------------------------------------------------------
local function rgb(t: { number }?, def: Color3): Color3
	if type(t) == "table" then
		return Color3.fromRGB(t[1], t[2], t[3])
	end
	return def
end

local function accessory(model: Model, parts: { [string]: BasePart }, name: string, size: Vector3, attach: string, offset: CFrame, color: Color3, material: Enum.Material?)
	local to = parts[attach]
	if not to then
		return
	end
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Massless = true
	p.CFrame = to.CFrame * offset
	p.Parent = model
	local w = Instance.new("WeldConstraint")
	w.Part0 = to
	w.Part1 = p
	w.Parent = p
end

local function buildStaff(Anim: any, id: string, look: any, spot: any)
	local ok, model, parts = pcall(Anim.buildR15, {
		name = look.name,
		skin = rgb(look.skin, Color3.fromRGB(234, 196, 164)),
		shirt = rgb(look.shirt, Color3.fromRGB(240, 240, 240)),
		pants = rgb(look.pants, Color3.fromRGB(50, 54, 66)),
		shoes = Color3.fromRGB(236, 236, 236),
		sleeves = if look.role == "pharm" then "long" else "short",
		body = look.body,
		build = if look.body == "f" then "slim" else "avg",
		height = if look.body == "f" then 0.96 else 1.02,
	})
	if not ok or not model then
		warn("[GwangalliClinic] staff rig failed:", model)
		return
	end
	local m = model :: Model
	local P = parts :: { [string]: BasePart }
	local s = tonumber(m:GetAttribute("RigScale")) or 1
	-- dressing (welded, non-colliding)
	if look.role == "desk" then
		accessory(m, P, "Lanyard", Vector3.new(0.08, 0.7, 0.04), "UpperTorso", CFrame.new(0, 0.25 * s, -0.52 * s), Color3.fromRGB(15, 163, 163))
		accessory(m, P, "IdCard", Vector3.new(0.36, 0.48, 0.04), "UpperTorso", CFrame.new(0, -0.2 * s, -0.53 * s), Color3.fromRGB(250, 250, 250))
		accessory(m, P, "Vest", Vector3.new(1.95 * s, 1.0 * s, 1.04 * s), "UpperTorso", CFrame.new(0, -0.15 * s, 0), Color3.fromRGB(26, 40, 74), Enum.Material.Fabric)
	elseif look.role == "nurse" then
		accessory(m, P, "NurseCap", Vector3.new(0.95, 0.24, 0.7), "Head", CFrame.new(0, 0.66 * s, 0.05), Color3.fromRGB(250, 250, 250))
		accessory(m, P, "CapCross", Vector3.new(0.22, 0.05, 0.05), "Head", CFrame.new(0, 0.7 * s, -0.37), Color3.fromRGB(15, 163, 163))
		accessory(m, P, "NameTag", Vector3.new(0.36, 0.14, 0.04), "UpperTorso", CFrame.new(0.42 * s, 0.35 * s, -0.52 * s), Color3.fromRGB(250, 250, 250))
	elseif look.role == "pharm" then
		accessory(m, P, "GownHem", Vector3.new(1.98 * s, 1.1 * s, 1.06 * s), "LowerTorso", CFrame.new(0, -0.45 * s, 0), Color3.fromRGB(248, 248, 248), Enum.Material.Fabric)
		accessory(m, P, "NameTag", Vector3.new(0.4, 0.16, 0.04), "UpperTorso", CFrame.new(0.45 * s, 0.35 * s, -0.53 * s), Color3.fromRGB(15, 163, 163))
		accessory(m, P, "Glasses", Vector3.new(0.9, 0.12, 0.05), "Head", CFrame.new(0, 0.12 * s, -0.6 * s), Color3.fromRGB(30, 30, 34))
	elseif look.role == "check" then
		accessory(m, P, "NameTag", Vector3.new(0.36, 0.14, 0.04), "UpperTorso", CFrame.new(0.42 * s, 0.35 * s, -0.52 * s), Color3.fromRGB(250, 250, 250))
		accessory(m, P, "Hair", Vector3.new(1.22, 0.4, 1.22), "Head", CFrame.new(0, 0.5 * s, 0.08), Color3.fromRGB(40, 30, 26))
	end
	m:SetAttribute(S.NAMES.AttrStaff, id)
	m:SetAttribute("ClinicRole", look.role)
	m:SetAttribute("NpcName", look.name)
	pcall(function()
		(m :: any).ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	local feet = Vector3.new(spot.at.X, Site.floorY(spot.floor), spot.at.Z)
	local pos = feet + Vector3.new(0, 3 * s, 0)
	m:PivotTo(CFrame.lookAt(pos, pos + spot.look))
	m.Parent = worldFolder:FindFirstChild(S.NAMES.Staff)
	Site.staff[id] = m
end

-------------------------------------------------------------------------------------------------
-- zone / distance
-------------------------------------------------------------------------------------------------
function Site.inZone(pos: Vector3): boolean
	local margin = C.Venue.ZoneMargin or 3
	if Site.zoneCF and Site.zoneSize then
		local lp = (Site.zoneCF :: CFrame):PointToObjectSpace(pos)
		local half = (Site.zoneSize :: Vector3) / 2
		if math.abs(lp.X) > half.X + margin or math.abs(lp.Z) > half.Z + margin then
			return false
		end
		return pos.Y >= C.Venue.Floor1 - 4 and pos.Y <= C.Venue.Floor2 + 16
	end
	local mn, mx = C.Venue.ZoneMin, C.Venue.ZoneMax
	return pos.X >= mn.X - margin and pos.X <= mx.X + margin and pos.Y >= mn.Y and pos.Y <= mx.Y and pos.Z >= mn.Z - margin and pos.Z <= mx.Z + margin
end

function Site.rootPos(player: Player): Vector3?
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

function Site.playerInZone(player: Player): boolean
	local p = Site.rootPos(player)
	return p ~= nil and Site.inZone(p :: Vector3)
end

function Site.dist(player: Player, anchor: string): number
	local p = Site.rootPos(player)
	local a = Site.anchors[anchor]
	if not p or not a then
		return math.huge
	end
	return (a.Position - (p :: Vector3)).Magnitude
end

function Site.near(player: Player, anchor: string, reach: number): boolean
	return Site.dist(player, anchor) <= reach
end

-- nearest of several anchors (e.g. Win1 / Win2) within reach
function Site.nearestOf(player: Player, names: { string }, reach: number): string?
	local best, bestD = nil, reach
	for _, n in names do
		local d = Site.dist(player, n)
		if d <= bestD then
			best, bestD = n, d
		end
	end
	return best
end

-------------------------------------------------------------------------------------------------
-- seats / beds
-------------------------------------------------------------------------------------------------
local function alive(player: Player): (Model?, Humanoid?, BasePart?)
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if not ch or not hum or hum.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return ch, hum, root
end
Site.alive = alive

function Site.unseat(player: Player)
	local _, hum = alive(player)
	if hum and hum.SeatPart then
		hum.Sit = false
		local weld = hum.SeatPart:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end
end

function Site.isSeatedOn(player: Player, anchor: string): boolean
	local seat = Site.seats[anchor]
	local _, hum = alive(player)
	return seat ~= nil and hum ~= nil and hum.SeatPart == seat
end

function Site.occupant(anchor: string): Player?
	local seat = Site.seats[anchor]
	local occ = seat and seat.Occupant
	if occ and occ.Parent then
		return Players:GetPlayerFromCharacter(occ.Parent)
	end
	return nil
end

function Site.reserve(anchor: string, player: Player): boolean
	local cur = reserved[anchor]
	if cur and cur ~= player and cur.Parent == Players then
		return false
	end
	local occ = Site.occupant(anchor)
	if occ and occ ~= player then
		return false
	end
	local seat = Site.seats[anchor]
	if seat and seat.Occupant and not occ then
		return false -- an NPC / something else sits there
	end
	reserved[anchor] = player
	return true
end

function Site.release(anchor: string, player: Player?)
	if player == nil or reserved[anchor] == player then
		reserved[anchor] = nil
	end
end

function Site.reservedBy(anchor: string): Player?
	return reserved[anchor]
end

function Site.free(anchor: string, player: Player?): boolean
	local cur = reserved[anchor]
	if cur and cur ~= player and cur.Parent == Players then
		return false
	end
	local seat = Site.seats[anchor]
	if seat and seat.Occupant then
		local occ = Site.occupant(anchor)
		return occ ~= nil and occ == player
	end
	return true
end

-- Seats the player on the map seat behind `anchor` (Seat:Sit, the game's own safe path).
function Site.sit(player: Player, anchor: string): boolean
	local seat = Site.seats[anchor]
	local ch, hum, root = alive(player)
	if not seat or not ch or not hum or not root then
		return false
	end
	if hum.SeatPart == seat then
		return true
	end
	if seat.Occupant and seat.Occupant ~= hum then
		return false
	end
	Site.unlie(player)
	Site.unseat(player)
	K.Bridge.allowTeleport(player, 6)
	-- Seat:Sit snaps the humanoid onto the seat by itself; only a far-away patient is moved first
	if (root.Position - seat.Position).Magnitude > 10 then
		local rot = seat.CFrame - seat.CFrame.Position
		local target = CFrame.new(seat.Position + Vector3.new(0, 2.6, 0)) * rot
		pcall(function()
			ch:PivotTo(target * root.CFrame:ToObjectSpace(ch:GetPivot()))
			root.AssemblyLinearVelocity = Vector3.zero
		end)
	end
	local ok = pcall(function()
		seat:Sit(hum)
	end)
	return ok
end

-- Lies the player on a mattress (IV / ECG): root anchored, body flat, head toward the pillow.
function Site.lie(player: Player, anchor: string, mattressKey: string, pillowKey: string): boolean
	local ch, hum, root = alive(player)
	local mattress = Site.parts[mattressKey]
	local pillow = Site.parts[pillowKey]
	if not ch or not hum or not root then
		return false
	end
	local center: Vector3
	local top: number
	if mattress then
		center = mattress.Position
		top = mattress.Position.Y + mattress.Size.Y / 2
	else
		local seat = Site.seats[anchor]
		if not seat then
			return false
		end
		center = seat.Position
		top = seat.Position.Y + seat.Size.Y / 2
	end
	local headDir: Vector3
	if pillow then
		local d = pillow.Position - center
		headDir = Vector3.new(d.X, 0, d.Z)
	else
		local seat = Site.seats[anchor]
		headDir = if seat then -seat.CFrame.LookVector else Vector3.zAxis
		headDir = Vector3.new(headDir.X, 0, headDir.Z)
	end
	if headDir.Magnitude < 0.01 then
		headDir = Vector3.zAxis
	end
	headDir = headDir.Unit
	Site.unseat(player)
	K.Bridge.allowTeleport(player, 8)
	local hip = hum.HipHeight + root.Size.Y / 2
	local p = Vector3.new(center.X, top + root.Size.Z / 2 + 0.25, center.Z) + headDir * math.clamp((hip - 2.2) * 0.5, -0.6, 1.2)
	local cf = CFrame.lookAt(p, p + Vector3.yAxis, headDir)
	local ok = pcall(function()
		root.Anchored = true
		ch:PivotTo(cf * root.CFrame:ToObjectSpace(ch:GetPivot()))
	end)
	if not ok then
		pcall(function()
			root.Anchored = false
		end)
		return false
	end
	ch:SetAttribute(S.NAMES.AttrPose, "lie")
	lying[player] = { anchor = anchor, root = root }
	return true
end

-- Gets up from lying: back on the floor at the foot of the bed.
function Site.unlie(player: Player)
	local rec = lying[player]
	if not rec then
		return
	end
	lying[player] = nil
	local root = rec.root
	local ch = root.Parent
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local anchor = Site.anchors[rec.anchor]
	pcall(function()
		if ch and ch:IsA("Model") then
			ch:SetAttribute(S.NAMES.AttrPose, "")
			local seat = Site.seats[rec.anchor]
			local base = if seat then seat.Position elseif anchor then anchor.Position else root.Position
			local look = if seat then seat.CFrame.LookVector else Vector3.new(0, 0, -1)
			look = Vector3.new(look.X, 0, look.Z)
			if look.Magnitude < 0.01 then
				look = Vector3.new(0, 0, -1)
			end
			look = look.Unit
			local floorY = base.Y - 1.9
			local stand = (hum and hum.HipHeight or 2) + root.Size.Y / 2
			local pos = Vector3.new(base.X, floorY + stand + 0.1, base.Z) + look * 4.8
			K.Bridge.allowTeleport(player, 6)
			ch:PivotTo(CFrame.lookAt(pos, pos + look) * root.CFrame:ToObjectSpace(ch:GetPivot()))
		end
		root.Anchored = false
		root.AssemblyLinearVelocity = Vector3.zero
	end)
end

function Site.isLying(player: Player): boolean
	return lying[player] ~= nil
end

-------------------------------------------------------------------------------------------------
-- shared staff acts (client Staff.luau animates from these)
-------------------------------------------------------------------------------------------------
function Site.setAct(staffId: string, act: string, userId: number?)
	local st = K.state
	if st then
		st:SetAttribute("Act_" .. staffId, string.format("%s|%d|%.2f", act, userId or 0, S.now()))
	end
end

function Site.setBed(anchor: string, value: string)
	local st = K.state
	if st then
		st:SetAttribute("Bed_" .. anchor, value)
	end
end

-------------------------------------------------------------------------------------------------
-- build
-------------------------------------------------------------------------------------------------
function Site.build(): boolean
	local t0 = os.clock()
	local v = findVenue()
	while not v and os.clock() - t0 < 30 do
		task.wait(1)
		v = findVenue()
	end
	Site.venue = v
	if not v then
		warn("[GwangalliClinic] clinic model not found; using fallback positions")
	end
	-- zone from the 1F floor slab
	local floor = byPath("1F/Floor")
	if floor and floor:IsA("BasePart") then
		Site.zoneCF = floor.CFrame
		Site.zoneSize = floor.Size
	end
	local old = workspace:FindFirstChild(S.NAMES.World)
	if old then
		old:Destroy()
	end
	worldFolder = Instance.new("Folder")
	worldFolder.Name = S.NAMES.World
	local anchorsModel = Instance.new("Model")
	anchorsModel.Name = S.NAMES.Anchors
	pcall(function()
		(anchorsModel :: any).ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)
	anchorsModel.Parent = worldFolder
	local staffFolder = Instance.new("Folder")
	staffFolder.Name = S.NAMES.Staff
	staffFolder.Parent = worldFolder
	for name, spec in S.Sites.ANCHORS do
		local pos, seat = resolveAnchor(name, spec)
		Site.anchors[name] = makeAnchor(anchorsModel, name, pos, spec)
		if seat then
			Site.seats[name] = seat
		end
	end
	for name, spec in S.Sites.PARTS do
		local p = partOf(byPath(spec.path))
		if p then
			Site.parts[name] = p
		end
	end
	worldFolder.Parent = workspace
	if C.Staff.Enabled then
		local m = ReplicatedStorage:FindFirstChild("GwangalliAnim")
		local okA, Anim = false, nil
		if m and m:IsA("ModuleScript") then
			okA, Anim = pcall(require, m)
		end
		if okA and type(Anim) == "table" and type(Anim.buildR15) == "function" then
			for id, spot in S.Sites.STAFF do
				local look = C.Staff[id]
				if look then
					buildStaff(Anim, id, look, spot)
					Site.setAct(id, spot.act or "idle", 0)
				end
			end
		else
			warn("[GwangalliClinic] GwangalliAnim missing; no extra staff")
		end
	end
	Players.PlayerRemoving:Connect(function(p)
		for a, who in reserved do
			if who == p then
				reserved[a] = nil
			end
		end
		lying[p] = nil
	end)
	log("site built", if v then v:GetFullName() else "(fallback)")
	return true
end

function Site.init(k: any)
	K = k
	S = k.S
	C = S.Config
end

return Site
