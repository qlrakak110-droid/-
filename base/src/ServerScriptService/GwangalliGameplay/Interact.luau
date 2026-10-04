-- GwangalliGameplay/Interact (feature module; owner: interactions): the server side of the WORLD
-- INTERACTION LAYER (docs/INTERACTIONS.md, data in ReplicatedStorage.GwangalliInteractShared = IS).
--
--   * SITTABLES: one chunked walk over the Workspace at start tags every surface that makes sense
--     (IS.classify + context rules: owned venues / vehicles / homes / the club are skipped) with
--     "GwSittable" + SitKind (+ SitFace from a sibling back rest). Tags replicate with the parts, so
--     clients bind them as they stream in (StreamingEnabled-safe, no client scan).
--   * SIT / LIE / LEAN: Seat:Sit on a real Seat (re-enabled for the sit, disabled again after, as the
--     build's optimise pass expects), else one pooled invisible Seat per player placed by IS.sitFrame.
--     Lying / sunbathing / leaning are GwPose character attributes every client renders through
--     GwangalliAnim. Resting slowly lowers 피로도; sunbathing (day, towel / lounger) raises 행복 and
--     tints the skin (GwTan 0..1, fades back when out of the sun).
--   * POSES / EMOTES: validated GwPose / GwEmote attributes (default Roblox emotes are played by the
--     owner's Animate script through Humanoid:PlayEmote and replicate by themselves).
--   * HELD PROPS: one small welded part per player (food, cans, plush, rod, sparkler, balls).
--   * PURCHASES (server-authoritative, ctx.spend): street-food carts, food trucks, vending machines,
--     busker tips, fireworks, sparklers, 인형뽑기. Eating plays GwPose eat / drink, then ctx.addStats
--     (IS.FOOD_DAILY_STATS per item per in-game day).
--   * FISHING (민락항 방파제): start -> cast (server picks the bite time) -> hook (timing window
--     validated here) -> species roll by game clock -> cooler -> 수산시장 sale (rolling cap).
--   * BEACH: pooled balls / frisbees (max 4, server physics, network owner = holder / thrower, catch by
--     players and by two beach-friend NPCs who throw it back), sandcastles (5 pieces, max 6, 10 min),
--     fireworks shows (beach, night, rate-limited, broadcast to clients that render them), lifeguard
--     whistle past the buoy line (then a gentle teleport back).
--   * PHOTO SPOTS: popularity +1 the first time a player takes a photo at each of IS.PHOTO_SPOTS.
--   * PROPS: carts, vending machines, stalls, NPC rigs etc. are built here at start (small counts,
--     tagged, inside workspace.GwangalliInteract); existing food trucks and the 12 claw machines of
--     광안 게임랜드 are tagged in place.
--   * DATA: own DataStore IS.STORE (photo spots, fish dex / cooler, fireworks, plush), written on
--     leave / every 3 min when dirty / BindToClose; memory-only when the profile is.
-- Remotes (GwangalliRemotes): InteractRequest (RemoteFunction op, payload -> {ok, code, message, ...})
-- and InteractEvent (RemoteEvent both ways: fire-and-forget ops up, broadcasts down).
-- Server API: ctx.interact = { isBusy(player), standUp(player), setHeld(player, id, color?, seconds?),
-- clearHeld(player), sitOn(player, part, mode?) }.

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Interact = {}

local ctx: any = nil
local G: any = nil
local Util: any = nil
local Profiles: any = nil
local IS: any = nil
local Anim: any = nil
local Looks: any = nil

local requestFn: RemoteFunction? = nil
local eventRe: RemoteEvent? = nil
local propFolder: Folder? = nil
local store: any = nil
local storeEnabled = false
local rng = Random.new()

local DEG = math.pi / 180

---------------------------------------------------------------------------------------------------
-- Per-player state
---------------------------------------------------------------------------------------------------
type State = {
	data: any,
	loaded: boolean,
	canSave: boolean,
	dirty: boolean,
	tokens: number,
	tokT: number,
	cool: { [string]: number },
	seat: Seat?, -- pooled invisible seat
	sit: any?, -- { seat, native, kind, mode, since, wasDisabled, conn }
	heldPart: BasePart?,
	heldId: string?,
	heldUntil: number,
	fish: any?, -- { spot, biteAt?, castAt? }
	claw: any?, -- { machine, bed, t0 }
	build: any?, -- { castle, n }
	ball: any?, -- ball record held
	tan: number,
	tanBase: { [BasePart]: Color3 }?,
	sunGain: number,
	restGain: number,
	restWindow: number,
	whistle: number, -- 0 none, else os.clock of the first whistle
	emoteSeq: number,
	sales: { { t: number, amount: number } },
}
local states: { [Player]: State } = {}

local function defaultData(): any
	return { v = 1, photos = {}, dex = {}, best = {}, cooler = {}, fireworks = 0, plush = {}, dexDone = false, food = { day = -1, counts = {} }, castles = 0 }
end

local function S(player: Player): State
	local s = states[player]
	if not s then
		s = {
			data = defaultData(),
			loaded = false,
			canSave = false,
			dirty = false,
			tokens = 10,
			tokT = os.clock(),
			cool = {},
			seat = nil,
			sit = nil,
			heldPart = nil,
			heldId = nil,
			heldUntil = 0,
			fish = nil,
			claw = nil,
			build = nil,
			ball = nil,
			tan = 0,
			tanBase = nil,
			sunGain = 0,
			restGain = 0,
			restWindow = os.clock(),
			whistle = 0,
			emoteSeq = 0,
			sales = {},
		}
		states[player] = s
	end
	return s
end

local function cooldown(s: State, key: string, interval: number): boolean
	local now = os.clock()
	local last = s.cool[key]
	if last and now - last < interval then
		return false
	end
	s.cool[key] = now
	return true
end

local function bucket(s: State): boolean
	local now = os.clock()
	s.tokens = math.min(12, s.tokens + (now - s.tokT) * 6)
	s.tokT = now
	if s.tokens < 1 then
		return false
	end
	s.tokens -= 1
	return true
end

local function fail(code: string, message: string): any
	return { ok = false, code = code, message = message }
end

local function alive(player: Player): (Model?, Humanoid?, BasePart?)
	return Util.alive(player)
end

local function fire(player: Player, payload: any)
	if eventRe and player.Parent == Players then
		(eventRe :: RemoteEvent):FireClient(player, payload)
	end
end

local function fireAll(payload: any)
	if eventRe then
		(eventRe :: RemoteEvent):FireAllClients(payload)
	end
end

local function fireNear(pos: Vector3, radius: number, payload: any)
	for _, p in Players:GetPlayers() do
		local rp = Util.rootPosition(p)
		if rp and (rp - pos).Magnitude <= radius then
			fire(p, payload)
		end
	end
end

local function notify(player: Player, kind: string, title: string, body: string?)
	pcall(ctx.notify, player, kind, title, body or "")
end

local function setBusy(player: Player, what: string?)
	player:SetAttribute(IS.Attr.Busy, what or "")
end

local function busyOf(player: Player): string
	local b = player:GetAttribute(IS.Attr.Busy)
	return if type(b) == "string" then b else ""
end

local function setPose(player: Player, pose: string?)
	local char = player.Character
	if char then
		char:SetAttribute(IS.Attr.Pose, pose or "")
	end
end

local function clockNow(): number
	local ok, env = pcall(ctx.env)
	if ok and type(env) == "table" and type(env.clock) == "number" then
		return env.clock
	end
	return 12
end

local function lifeDay(player: Player): number
	local d = Profiles.get(player)
	return if d and type(d.lifeDay) == "number" then d.lifeDay else 1
end

-- Distance from a point to a part's box (0 inside).
local function distToPart(pos: Vector3, p: BasePart): number
	local lp = p.CFrame:PointToObjectSpace(pos)
	local h = p.Size / 2
	local c = Vector3.new(math.clamp(lp.X, -h.X, h.X), math.clamp(lp.Y, -h.Y, h.Y), math.clamp(lp.Z, -h.Z, h.Z))
	return (lp - c).Magnitude
end

local function near(player: Player, p: Instance?, maxD: number): boolean
	if typeof(p) ~= "Instance" or not (p :: Instance):IsA("BasePart") or not (p :: Instance):IsDescendantOf(Workspace) then
		return false
	end
	local rp = Util.rootPosition(player)
	return rp ~= nil and distToPart(rp, p :: BasePart) <= maxD
end

local function kindOf(p: Instance?): string?
	if typeof(p) ~= "Instance" or not CollectionService:HasTag(p :: Instance, IS.Tags.Interact) then
		return nil
	end
	local k = (p :: Instance):GetAttribute(IS.Attr.Kind)
	return if type(k) == "string" then k else nil
end

local function itemsOf(p: Instance): { string }
	local list = {}
	local s = p:GetAttribute("GwItems")
	if type(s) == "string" then
		for id in string.gmatch(s, "[^,]+") do
			if IS.FOOD[id] then
				table.insert(list, id)
			end
		end
	end
	return list
end

---------------------------------------------------------------------------------------------------
-- Persistence
---------------------------------------------------------------------------------------------------
local function sanitize(raw: any): any
	local d = defaultData()
	if type(raw) ~= "table" then
		return d
	end
	if type(raw.photos) == "table" then
		for id, v in raw.photos do
			if IS.PHOTO_BY_ID[id] and v then
				d.photos[id] = true
			end
		end
	end
	if type(raw.dex) == "table" then
		for id, c in raw.dex do
			if IS.FISH_BY_ID[id] and type(c) == "number" and c > 0 then
				d.dex[id] = math.min(99999, math.floor(c))
			end
		end
	end
	if type(raw.best) == "table" then
		for id, c in raw.best do
			if IS.FISH_BY_ID[id] and type(c) == "number" and c > 0 then
				d.best[id] = math.min(200, c)
			end
		end
	end
	if type(raw.cooler) == "table" then
		for _, f in raw.cooler do
			if type(f) == "table" and IS.FISH_BY_ID[f.id] and type(f.size) == "number" and type(f.price) == "number" and #d.cooler < IS.FISHING.cooler then
				table.insert(d.cooler, { id = f.id, size = math.clamp(f.size, 1, 200), price = math.clamp(math.floor(f.price), 0, 20000) })
			end
		end
	end
	if type(raw.fireworks) == "number" then
		d.fireworks = math.clamp(math.floor(raw.fireworks), 0, IS.FIREWORKS.maxOwned)
	end
	if type(raw.plush) == "table" then
		for _, pz in IS.CLAW.prizes do
			local c = raw.plush[pz.id]
			if type(c) == "number" and c > 0 then
				d.plush[pz.id] = math.min(999, math.floor(c))
			end
		end
	end
	d.dexDone = raw.dexDone == true
	if type(raw.castles) == "number" then
		d.castles = math.max(0, math.floor(raw.castles))
	end
	return d
end

local function keyOf(player: Player): string
	return IS.STORE_KEY .. tostring(player.UserId)
end

local function saveNow(player: Player): boolean
	local s = states[player]
	if not s or not s.canSave or not storeEnabled or not store then
		if s then
			s.dirty = false
		end
		return false
	end
	local okP, persistent = pcall(Profiles.persistent, player)
	if okP and persistent == false then
		s.dirty = false
		return false
	end
	local snapshot = Util.deepCopy(s.data)
	snapshot.food = nil
	s.dirty = false
	local ok, err = pcall(function()
		store:UpdateAsync(keyOf(player), function(_old: any)
			return snapshot
		end)
	end)
	if not ok then
		s.dirty = true
		warn("[Interact] save failed for " .. player.Name .. ": " .. tostring(err))
	end
	return ok
end

local function summary(player: Player): any
	local s = S(player)
	local d = s.data
	local photos, dex = 0, 0
	for _ in d.photos do
		photos += 1
	end
	for _ in d.dex do
		dex += 1
	end
	local coolerValue = 0
	for _, f in d.cooler do
		coolerValue += f.price
	end
	return {
		photos = d.photos,
		photoCount = photos,
		photoTotal = #IS.PHOTO_SPOTS,
		dex = d.dex,
		dexCount = dex,
		dexTotal = #IS.FISH,
		best = d.best,
		cooler = d.cooler,
		coolerValue = coolerValue,
		fireworks = d.fireworks,
		plush = d.plush,
	}
end

local function pushData(player: Player)
	fire(player, { kind = "data", data = summary(player) })
end

local function markDirty(player: Player)
	S(player).dirty = true
end

---------------------------------------------------------------------------------------------------
-- Held props
---------------------------------------------------------------------------------------------------
local function rightHand(char: Model): BasePart?
	local h = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
	return if h and h:IsA("BasePart") then h else nil
end

local function chest(char: Model): BasePart?
	local t = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	return if t and t:IsA("BasePart") then t else nil
end

local HELD_C0: { [string]: CFrame } = {
	cup = CFrame.new(0, -0.35, -0.15),
	skewer = CFrame.new(0, -0.2, -0.45) * CFrame.Angles(-math.pi / 2.4, 0, 0),
	disc = CFrame.new(0, -0.3, -0.2),
	fish = CFrame.new(0, -0.3, -0.3),
	can = CFrame.new(0, -0.35, -0.1),
	box = CFrame.new(0, -0.35, -0.25),
	rod = CFrame.new(0, -0.25, -3.1) * CFrame.Angles(math.rad(18), 0, 0),
	sparkler = CFrame.new(0, -0.2, -0.6) * CFrame.Angles(-math.pi / 2.3, 0, 0),
	fireworks = CFrame.new(0, -0.4, -0.3),
}

local function clearHeld(player: Player)
	local s = states[player]
	if not s then
		return
	end
	if s.heldPart then
		s.heldPart:Destroy()
		s.heldPart = nil
	end
	s.heldId = nil
	s.heldUntil = 0
	local char = player.Character
	if char then
		char:SetAttribute(IS.Attr.Held, "")
	end
end

-- Welds a small prop to the right hand (or the chest for "plush"). seconds = auto-clear (nil = keep).
local function setHeld(player: Player, id: string, color: Color3?, seconds: number?): BasePart?
	local char, humanoid = alive(player)
	if not char or not humanoid then
		return nil
	end
	local def = IS.HELD[id]
	if not def then
		return nil
	end
	clearHeld(player)
	local s = S(player)
	local onChest = id == "plush"
	local anchor = if onChest then chest(char) else rightHand(char)
	if not anchor then
		return nil
	end
	local p = Instance.new("Part")
	p.Name = "GwHeld"
	p.Size = Vector3.new(def.size[1], def.size[2], def.size[3])
	if def.shape == "cyl" then
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(def.size[2], def.size[1], def.size[3])
	elseif def.shape == "ball" then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
	end
	p.Color = color or Color3.fromRGB(240, 240, 236)
	p.Material = if id == "plush" then Enum.Material.Fabric else Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.Anchored = false
	local c0 = if onChest then CFrame.new(0, -0.15, -1.0) else (HELD_C0[id] or CFrame.new(0, -0.3, -0.2))
	if def.shape == "cyl" then
		c0 = c0 * CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis is X: stand it upright
	end
	p.CFrame = anchor.CFrame * c0
	local w = Instance.new("Weld")
	w.Part0 = anchor
	w.Part1 = p
	w.C0 = c0
	w.Parent = p
	if def.top then
		local t = Instance.new("Part")
		t.Name = "Top"
		t.Size = Vector3.new(def.top[1], def.top[2], def.top[3])
		t.Color = color or p.Color
		t.Material = Enum.Material.SmoothPlastic
		t.CanCollide, t.CanQuery, t.CanTouch, t.Massless, t.CastShadow = false, false, false, true, false
		t.CFrame = p.CFrame * CFrame.new(0, def.size[2] / 2 - def.top[2] / 2, 0)
		local w2 = Instance.new("Weld")
		w2.Part0 = p
		w2.Part1 = t
		w2.C0 = CFrame.new(0, def.size[2] / 2 - def.top[2] / 2, 0)
		w2.Parent = t
		t.Parent = p
		p.Color = Color3.fromRGB(214, 190, 150) -- the stick
	end
	if id == "sparkler" then
		local a = Instance.new("Attachment")
		a.Position = Vector3.new(0, def.size[2] / 2, 0)
		a.Parent = p
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Color = ColorSequence.new(Color3.fromRGB(255, 236, 170), Color3.fromRGB(255, 160, 60))
		pe.LightEmission = 1
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
		pe.Lifetime = NumberRange.new(0.25, 0.5)
		pe.Rate = 30
		pe.Speed = NumberRange.new(3, 6)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Parent = a
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(255, 210, 140)
		l.Range = 10
		l.Brightness = 1.4
		l.Shadows = false
		l.Parent = a
	end
	p.Parent = char
	s.heldPart = p
	s.heldId = id
	s.heldUntil = if seconds then os.clock() + seconds else 0
	char:SetAttribute(IS.Attr.Held, id)
	return p
end

---------------------------------------------------------------------------------------------------
-- Sit / lie / lean
---------------------------------------------------------------------------------------------------
local function endSit(player: Player)
	local s = states[player]
	if not s or not s.sit then
		return
	end
	local st = s.sit
	s.sit = nil
	if st.conn then
		st.conn:Disconnect()
	end
	if st.native and st.seat and st.seat.Parent then
		if st.wasDisabled then
			(st.seat :: Seat).Disabled = true
		end
	elseif st.seat and st.seat.Parent then
		st.seat.Parent = nil -- pooled: kept on the state for the next sit
	end
	if busyOf(player) == IS.BUSY.sit then
		setBusy(player, nil)
	end
	local char = player.Character
	if char then
		local cur = char:GetAttribute(IS.Attr.Pose)
		if cur == "lie" or cur == "sunbathe" or cur == "sit_edge" or cur == "sit_relax" then
			char:SetAttribute(IS.Attr.Pose, "")
		end
	end
end

local function standUp(player: Player)
	local _, humanoid = alive(player)
	if humanoid and humanoid.SeatPart then
		local sp = humanoid.SeatPart
		humanoid.Sit = false
		local weld = sp and sp:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end
	endSit(player)
end

local function pooledSeat(s: State): Seat
	local seat = s.seat
	if not seat then
		local n = Instance.new("Seat")
		n.Name = "GwTempSeat"
		n.Size = Vector3.new(1.8, 0.2, 1.8)
		n.Transparency = 1
		n.Anchored = true
		n.CanCollide = false
		n.CanTouch = false
		n.CanQuery = false
		n.CastShadow = false
		n.Disabled = false
		n:AddTag(IS.Tags.Prop)
		s.seat = n
		seat = n
	end
	return seat :: Seat
end

local function poseForSit(kind: string, mode: string): string
	if mode == "lie" then
		return if kind == "towel" or kind == "lounger" then "sunbathe" else "lie"
	end
	if kind == "edge" then
		return "sit_edge"
	end
	return ""
end

local function sitOn(player: Player, part: BasePart, mode: string?): any
	local char, humanoid, root = alive(player)
	if not char or not humanoid or not root then
		return fail("dead", "지금은 할 수 없어요")
	end
	if not part:IsDescendantOf(Workspace) then
		return fail("gone", "자리가 사라졌어요")
	end
	if player:GetAttribute(G.Attr.InTaxi) == true then
		return fail("busy", "탑승 중이에요")
	end
	local sp = humanoid.SeatPart
	if sp and sp:IsA("VehicleSeat") then
		return fail("busy", "운전 중이에요")
	end
	local kindA = part:GetAttribute(IS.Attr.SitKind)
	local kind: string = if type(kindA) == "string" then kindA else (IS.classify(part.Name, part.ClassName, part.Size) or "")
	if kind == "" or kind == "rail" then
		return fail("nosit", "여기엔 앉을 수 없어요")
	end
	local m = if mode == "lie" then "lie" else "sit"
	if m == "lie" and not (kind == "bench" or kind == "sofa" or kind == "towel" or kind == "lounger") then
		m = "sit"
	end
	local b = busyOf(player)
	if b ~= "" and b ~= IS.BUSY.sit then
		return fail("busy", "지금 하던 걸 먼저 끝내요")
	end
	if distToPart(root.Position, part) > IS.SIT.reach then
		return fail("far", "조금 더 가까이 가요")
	end
	-- already seated somewhere: stand first
	if sp then
		standUp(player)
	end
	local s = S(player)
	local seat: Seat
	local native = false
	local wasDisabled = false
	if part:IsA("Seat") and m == "sit" then
		local ps = part :: Seat
		if ps.Occupant and ps.Occupant ~= humanoid then
			return fail("taken", "누가 앉아 있어요")
		end
		native = true
		wasDisabled = ps.Disabled
		ps.Disabled = false
		seat = ps
	else
		local faceA = part:GetAttribute(IS.Attr.SitFace)
		local face = if typeof(faceA) == "Vector3" then faceA else nil
		local cf = IS.sitFrame(part.CFrame, part.Size, kind, m, root.Position, root.CFrame.LookVector, face)
		if not cf then
			return fail("nosit", "여기엔 앉기 어려워요")
		end
		-- edge: the top must be at sitting height above the feet
		if kind == "edge" then
			local feet = root.Position.Y - Util.standHeight(humanoid, root)
			local h = cf.Position.Y - feet
			if h < IS.SIT.edgeMin - 0.4 or h > IS.SIT.edgeMax + 0.4 then
				return fail("height", "높이가 안 맞아요")
			end
		end
		-- another player already on this spot
		for other, os2 in states do
			if other ~= player and os2.sit and os2.sit.seat and not os2.sit.native and os2.sit.seat.Parent then
				if ((os2.sit.seat :: Seat).Position - cf.Position).Magnitude < 1.6 then
					return fail("taken", "누가 앉아 있어요")
				end
			end
		end
		seat = pooledSeat(s)
		seat.CFrame = cf * CFrame.new(0, -seat.Size.Y / 2, 0)
		seat.Parent = propFolder
	end
	local ok, err = pcall(function()
		(seat :: any):Sit(humanoid)
	end)
	if not ok then
		if native and wasDisabled then
			seat.Disabled = true
		elseif not native then
			seat.Parent = nil
		end
		warn("[Interact] Seat:Sit failed: " .. tostring(err))
		return fail("error", "앉지 못했어요")
	end
	local rec: any = { seat = seat, native = native, kind = kind, mode = m, since = os.clock(), wasDisabled = wasDisabled, conn = nil, part = part }
	s.sit = rec
	rec.conn = seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if seat.Occupant ~= humanoid and s.sit == rec then
			endSit(player)
		end
	end)
	setBusy(player, IS.BUSY.sit)
	setPose(player, poseForSit(kind, m))
	return { ok = true, kind = kind, mode = m, sunbathe = (m == "lie" and (kind == "towel" or kind == "lounger")) }
end

-- Lean: the client walks the character to the spot; the server validates and sets the pose.
local function lean(player: Player, part: BasePart, back: boolean): any
	local char, humanoid, root = alive(player)
	if not char or not humanoid or not root then
		return fail("dead", "지금은 할 수 없어요")
	end
	if humanoid.SeatPart then
		return fail("busy", "앉아 있어요")
	end
	local kind = part:GetAttribute(IS.Attr.SitKind)
	if kind ~= "rail" and part:GetAttribute(IS.Attr.SitLean) ~= true then
		return fail("nolean", "기댈 수 없는 곳이에요")
	end
	if distToPart(root.Position, part) > 4.5 then
		return fail("far", "조금 더 가까이 가요")
	end
	local b = busyOf(player)
	if b ~= "" and b ~= IS.BUSY.lean then
		return fail("busy", "지금 하던 걸 먼저 끝내요")
	end
	setBusy(player, IS.BUSY.lean)
	setPose(player, if back then "lean_back" else "lean_rail")
	return { ok = true }
end

---------------------------------------------------------------------------------------------------
-- Tan (sunbathing) + rest
---------------------------------------------------------------------------------------------------
local TAN_TARGET = Color3.fromRGB(150, 96, 62)
local SKIN_PARTS = { Head = true, LeftHand = true, RightHand = true, LeftLowerArm = true, RightLowerArm = true, LeftUpperArm = true, RightUpperArm = true, LeftFoot = true, RightFoot = true, LeftLowerLeg = true, RightLowerLeg = true, LeftUpperLeg = true, RightUpperLeg = true, UpperTorso = true, LowerTorso = true, ["Left Arm"] = true, ["Right Arm"] = true, ["Left Leg"] = true, ["Right Leg"] = true, Torso = true }

local function applyTan(player: Player)
	local s = states[player]
	local char = player.Character
	if not s or not char then
		return
	end
	if not s.tanBase then
		local base = {}
		for _, c in char:GetChildren() do
			if c:IsA("BasePart") and SKIN_PARTS[c.Name] then
				base[c] = c.Color
			end
		end
		s.tanBase = base
	end
	local k = math.clamp(s.tan, 0, 1) * 0.42
	for p, c in s.tanBase :: { [BasePart]: Color3 } do
		if p.Parent == char then
			p.Color = c:Lerp(TAN_TARGET, k)
		end
	end
	char:SetAttribute(IS.Attr.Tan, math.floor(s.tan * 100) / 100)
end

---------------------------------------------------------------------------------------------------
-- Prop builders (server, small counts, inside workspace.GwangalliInteract)
---------------------------------------------------------------------------------------------------
local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function mk(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function box(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, name: string?, collide: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name or "Part"
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = collide == true
	p.CanTouch = false
	p.CastShadow = size.Magnitude > 4
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function cyl(parent: Instance, length: number, dia: number, cf: CFrame, color: Color3, material: Enum.Material?, name: string?): Part
	local p = box(parent, Vector3.new(length, dia, dia), cf, color, material, name, false)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(parent: Instance, dia: number, cf: CFrame, color: Color3, material: Enum.Material?, name: string?): Part
	local p = box(parent, Vector3.new(dia, dia, dia), cf, color, material, name, false)
	p.Shape = Enum.PartType.Ball
	return p
end

local function sign(parent: Instance, size: Vector3, cf: CFrame, text: string, sub: string?, bg: Color3, fg: Color3?): Part
	local p = box(parent, size, cf, bg, Enum.Material.SmoothPlastic, "Sign", false)
	local g = Instance.new("SurfaceGui")
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 40
	g.MaxDistance = 90
	g.LightInfluence = 0.2
	g.Parent = p
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, if sub then 0.62 else 1)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = fg or Color3.new(1, 1, 1)
	t.Text = text
	t.Parent = g
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.PaddingTop = UDim.new(0.06, 0)
	pad.Parent = t
	if sub then
		local t2 = t:Clone()
		t2.Position = UDim2.fromScale(0, 0.6)
		t2.Size = UDim2.fromScale(1, 0.38)
		t2.Font = Enum.Font.GothamMedium
		t2.Text = sub
		t2.Parent = g
	end
	return p
end

local function propModel(name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	m:AddTag(IS.Tags.Prop)
	return m
end

local function tagInteract(p: BasePart, kind: string, id: string, label: string, items: { string }?)
	p:SetAttribute(IS.Attr.Kind, kind)
	p:SetAttribute(IS.Attr.Id, id)
	p:SetAttribute(IS.Attr.Label, label)
	if items then
		p:SetAttribute("GwItems", table.concat(items, ","))
	end
	p:AddTag(IS.Tags.Interact)
end

-- Ground below a point (parts with collision + terrain; water ignored).
local function groundAt(pos: Vector3, fromY: number?): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ex: { Instance } = {}
	if propFolder then
		table.insert(ex, propFolder)
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ex, p.Character)
		end
	end
	params.FilterDescendantsInstances = ex
	params.IgnoreWater = true
	params.RespectCanCollide = true
	local y0 = fromY or (pos.Y + 30)
	local r = Workspace:Raycast(Vector3.new(pos.X, y0, pos.Z), Vector3.new(0, -(y0 - pos.Y) - 40, 0), params)
	return r and r.Position or nil
end

local function halfHeight(p: BasePart): number
	local cf, s = p.CFrame, p.Size
	return 0.5 * (math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z)
end

-- True when nothing above the ground occupies the footprint box at cf (cf at ground level).
local function spotFree(cf: CFrame, size: Vector3): boolean
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = if propFolder then { propFolder } else {}
	op.RespectCanCollide = false
	local ok, parts = pcall(function()
		return Workspace:GetPartBoundsInBox(cf * CFrame.new(0, size.Y / 2 + 0.3, 0), size, op)
	end)
	if not ok then
		return true
	end
	for _, p in parts :: { BasePart } do
		if p.Transparency < 0.95 and not p:IsA("Terrain") then
			local top = p.Position.Y + halfHeight(p)
			if top > cf.Position.Y + 0.4 then
				return false
			end
		end
	end
	return true
end

local NUDGE = { 0, 5, -5, 10, -10, 15, -15, 20, -20, 26, -26, 32, -32, 40, -40 }

-- Station-based placement: (x, n) on the promenade / beach, footprint size; faceSea = LookVector
-- toward the sea. Returns a ground-level CFrame or nil.
local function findSpot(x: number, n: number, size: Vector3, faceSea: boolean, sand: boolean?): CFrame?
	local fallback: CFrame? = nil
	for _, dx in NUDGE do
		local xx = x + dx
		local guess = IS.point(xx, n, if sand then 3 else IS.WALK)
		local g = groundAt(guess, if sand then 12 else 24)
		if g and ((sand and g.Y > 0.4 and g.Y < 5) or (not sand and math.abs(g.Y - IS.WALK) < 1.2)) then
			local nrm = IS.normal(xx)
			local look = if faceSea then -nrm else nrm
			local cf = CFrame.lookAt(g, g + look)
			fallback = fallback or cf
			if spotFree(cf, size) then
				return cf
			end
		end
	end
	return fallback
end

-- World-point placement within `radius` of `center` (rings of probes), facing `look`.
local function findSpotWorld(center: Vector3, size: Vector3, look: Vector3, radius: number): CFrame?
	local fallback: CFrame? = nil
	for ring = 0, 4 do
		local r = radius * ring / 4
		local steps = if ring == 0 then 1 else 8
		for i = 0, steps - 1 do
			local a = i / steps * math.pi * 2
			local p = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			local g = groundAt(p, center.Y + 20)
			if g and math.abs(g.Y - center.Y) < 3 then
				local cf = CFrame.lookAt(g, g + Vector3.new(look.X, 0, look.Z))
				fallback = fallback or cf
				if spotFree(cf, size) then
					return cf
				end
			end
		end
	end
	return fallback
end

-- NPC rig (GwangalliNPCLooks when available, else a GwangalliAnim block rig). act = client act.
local function buildRig(parent: Instance, name: string, cf: CFrame, look: any, act: string, seed: string): Model?
	local model: Model? = nil
	local ground = 3
	if Looks then
		local ok, res = pcall(function()
			local spec = Looks.random(seed, look)
			return Looks.build(spec, { name = name, anchored = true })
		end)
		if ok and type(res) == "table" and res.model then
			model = res.model
			ground = res.ground or 3
		end
	end
	if not model and Anim then
		local ok, res = pcall(function()
			return Anim.buildR15({ name = name, body = look and look.body or "m" })
		end)
		if ok and res then
			model = res
		end
	end
	if not model then
		return nil
	end
	local m = model :: Model
	m.Name = name
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	m:SetAttribute(IS.Attr.Act, act)
	m:AddTag(IS.Tags.Rig)
	m.Parent = parent
	pcall(function()
		m:PivotTo(cf * CFrame.new(0, ground, 0))
	end)
	return m
end

local function vendorBehind(parent: Instance, cf: CFrame, dist: number, act: string, seed: string, style: string?)
	-- cf: counter frame looking toward the customers; the vendor stands behind it facing them
	local p = cf * CFrame.new(0, 0, dist)
	buildRig(parent, "Vendor", CFrame.lookAt(p.Position, p.Position + cf.LookVector), { style = style or "apron" }, act, seed)
end

-- 포장마차 cart (frame at ground; LookVector = customer side)
local function buildCart(def: any, cf: CFrame)
	local m = propModel("포장마차 " .. def.name)
	local accent = rgb(def.color)
	local wood = Color3.fromRGB(150, 104, 66)
	box(m, Vector3.new(6.4, 3.2, 3.4), cf * CFrame.new(0, 1.9, 0), Color3.fromRGB(236, 232, 224), Enum.Material.SmoothPlastic, "CartBody", true)
	box(m, Vector3.new(6.6, 0.3, 3.8), cf * CFrame.new(0, 3.6, -0.15), Color3.fromRGB(196, 196, 200), Enum.Material.Metal, "Counter", false)
	box(m, Vector3.new(6.42, 0.5, 3.42), cf * CFrame.new(0, 0.55, 0), accent, Enum.Material.SmoothPlastic, "Skirt", false)
	for _, sx in { -2.6, 2.6 } do
		cyl(m, 0.4, 1.3, cf * CFrame.new(sx, 0.65, 1.75), Color3.fromRGB(40, 40, 44), Enum.Material.Metal, "Wheel")
		box(m, Vector3.new(0.2, 4.4, 0.2), cf * CFrame.new(sx * 1.15, 5.8, -1.6), wood, Enum.Material.Wood, "AwningPost", false)
		box(m, Vector3.new(0.2, 4.4, 0.2), cf * CFrame.new(sx * 1.15, 5.8, 1.6), wood, Enum.Material.Wood, "AwningPost", false)
	end
	-- striped awning (two-tone)
	for i = 0, 5 do
		local c = if i % 2 == 0 then accent else Color3.fromRGB(250, 248, 240)
		box(m, Vector3.new(1.3, 0.22, 4.6), cf * CFrame.new(-3.25 + 0.65 + i * 1.3, 8.05, 0) * CFrame.Angles(math.rad(-6), 0, 0), c, Enum.Material.Fabric, "Awning", false)
	end
	-- the food: a red pan of 떡볶이 / a pot of 어묵 / a griddle of 호떡 / a 붕어빵 mould
	local food = rgb(IS.FOOD[def.items[1]].color)
	box(m, Vector3.new(3, 0.3, 1.8), cf * CFrame.new(-1.2, 3.9, -0.4), Color3.fromRGB(70, 70, 74), Enum.Material.Metal, "Griddle", false)
	box(m, Vector3.new(2.7, 0.18, 1.5), cf * CFrame.new(-1.2, 4.08, -0.4), food, Enum.Material.SmoothPlastic, "Food", false)
	local pot = cyl(m, 1.1, 1.6, cf * CFrame.new(1.9, 4.3, -0.4) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(190, 190, 196), Enum.Material.Metal, "Pot")
	local steam = Instance.new("ParticleEmitter")
	steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
	steam.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.75), NumberSequenceKeypoint.new(1, 1) })
	steam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.2) })
	steam.Lifetime = NumberRange.new(1.6, 2.4)
	steam.Rate = 3
	steam.Speed = NumberRange.new(1.5, 2.5)
	steam.SpreadAngle = Vector2.new(12, 12)
	steam.EmissionDirection = Enum.NormalId.Right
	steam.Parent = pot
	local priceText = {}
	for _, id in def.items do
		local f = IS.FOOD[id]
		table.insert(priceText, f.name .. " " .. G.format.won(f.price))
	end
	sign(m, Vector3.new(6.2, 1.5, 0.15), cf * CFrame.new(0, 7.1, -2.3), def.name, table.concat(priceText, " · "), accent, Color3.new(1, 1, 1))
	local counter = m:FindFirstChild("Counter") :: BasePart
	tagInteract(counter, "food", def.id, def.name, def.items)
	m.Parent = propFolder
	vendorBehind(m, cf, 2.6, "cook", def.id, "apron")
end

local function buildVending(def: any, cf: CFrame)
	local m = propModel("자판기 " .. def.id)
	local body = box(m, Vector3.new(3.4, 6.4, 2.8), cf * CFrame.new(0, 3.2, 0), Color3.fromRGB(200, 40, 50), Enum.Material.SmoothPlastic, "VendingBody", true)
	box(m, Vector3.new(2.6, 3.4, 0.1), cf * CFrame.new(-0.25, 4.1, -1.42), Color3.fromRGB(190, 220, 240), Enum.Material.Glass, "Window", false).Transparency = 0.35
	for row = 0, 2 do
		for col = 0, 3 do
			local id = def.items[(col % #def.items) + 1]
			box(m, Vector3.new(0.4, 0.75, 0.4), cf * CFrame.new(-1.15 + col * 0.6, 3.0 + row * 1.05, -1.1), rgb(IS.FOOD[id].color), Enum.Material.SmoothPlastic, "Can", false)
		end
	end
	local panel = box(m, Vector3.new(0.5, 3.4, 0.1), cf * CFrame.new(1.35, 4.1, -1.42), Color3.fromRGB(30, 30, 34), Enum.Material.SmoothPlastic, "ButtonPanel", false)
	local glow = box(m, Vector3.new(2.6, 0.4, 0.06), cf * CFrame.new(-0.25, 6.0, -1.43), Color3.fromRGB(255, 250, 230), Enum.Material.Neon, "Glow", false)
	glow:AddTag("NightNeon")
	local slot = box(m, Vector3.new(2.2, 0.7, 0.3), cf * CFrame.new(-0.25, 1.1, -1.35), Color3.fromRGB(20, 20, 22), Enum.Material.SmoothPlastic, "Slot", false)
	local _ = panel
	local _b = body
	tagInteract(slot, "vending", def.id, "음료 자판기", def.items)
	m.Parent = propFolder
end

local function buildFireworksStall(cf: CFrame)
	local def = IS.FIREWORKS.stall
	local m = propModel("불꽃놀이 판매대")
	box(m, Vector3.new(6, 3, 3), cf * CFrame.new(0, 1.5, 0), Color3.fromRGB(40, 44, 70), Enum.Material.SmoothPlastic, "StallBody", true)
	local top = box(m, Vector3.new(6.2, 0.25, 3.2), cf * CFrame.new(0, 3.12, 0), Color3.fromRGB(230, 230, 236), Enum.Material.SmoothPlastic, "Counter", false)
	local colors = { Color3.fromRGB(255, 70, 120), Color3.fromRGB(70, 200, 255), Color3.fromRGB(255, 200, 60), Color3.fromRGB(150, 90, 255), Color3.fromRGB(90, 230, 140) }
	for i = 0, 7 do
		local c = colors[(i % #colors) + 1]
		local h = 0.8 + (i % 3) * 0.35
		box(m, Vector3.new(0.6, h, 0.6), cf * CFrame.new(-2.4 + i * 0.68, 3.25 + h / 2, -0.4), c, Enum.Material.SmoothPlastic, "FireworkBox", false)
	end
	for _, sx in { -2.9, 2.9 } do
		box(m, Vector3.new(0.18, 5, 0.18), cf * CFrame.new(sx, 5.6, -1.4), Color3.fromRGB(230, 230, 236), Enum.Material.Metal, "Post", false)
		box(m, Vector3.new(0.18, 5, 0.18), cf * CFrame.new(sx, 5.6, 1.4), Color3.fromRGB(230, 230, 236), Enum.Material.Metal, "Post", false)
	end
	box(m, Vector3.new(6.6, 0.3, 3.6), cf * CFrame.new(0, 8.2, 0), Color3.fromRGB(150, 90, 255), Enum.Material.Fabric, "Canopy", false)
	sign(m, Vector3.new(6.4, 1.4, 0.15), cf * CFrame.new(0, 7.2, -1.7), "🎆 불꽃놀이", "세트 " .. G.format.won(IS.FIREWORKS.price) .. " · 스파클러 " .. G.format.won(IS.FIREWORKS.sparkler.price) .. " · 밤에 해변에서!", Color3.fromRGB(30, 26, 60), Color3.fromRGB(255, 220, 120))
	tagInteract(top, "fireworks", def.id, "불꽃놀이 판매대")
	m.Parent = propFolder
	vendorBehind(m, cf, 2.4, "idle", def.id, "casual")
end

local function buildRentalStand(cf: CFrame)
	local def = IS.RENTAL.stand
	local m = propModel("비치볼 · 원반 대여소")
	box(m, Vector3.new(5.2, 2.8, 2.6), cf * CFrame.new(0, 1.4, 0), Color3.fromRGB(250, 250, 246), Enum.Material.WoodPlanks, "StandBody", true)
	local top = box(m, Vector3.new(5.4, 0.25, 2.8), cf * CFrame.new(0, 2.92, 0), Color3.fromRGB(40, 150, 220), Enum.Material.SmoothPlastic, "Counter", false)
	ball(m, 1.8, cf * CFrame.new(-1.6, 3.95, 0), Color3.fromRGB(255, 90, 90), Enum.Material.SmoothPlastic, "DisplayBall")
	ball(m, 1.6, cf * CFrame.new(-0.2, 3.85, 0.3), Color3.fromRGB(255, 220, 60), Enum.Material.SmoothPlastic, "DisplayBall")
	cyl(m, 0.22, 2.0, cf * CFrame.new(1.6, 3.2, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(70, 200, 255), Enum.Material.SmoothPlastic, "DisplayFrisbee")
	local pole = box(m, Vector3.new(0.25, 9, 0.25), cf * CFrame.new(2.2, 4.5, 0.8), Color3.fromRGB(230, 230, 230), Enum.Material.Metal, "UmbrellaPole", false)
	local _p = pole
	cyl(m, 0.4, 9, cf * CFrame.new(2.2, 9.0, 0.8) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(255, 120, 60), Enum.Material.Fabric, "Umbrella")
	sign(m, Vector3.new(5.2, 1.2, 0.15), cf * CFrame.new(0, 2.0, -1.36), "🏐 비치볼 · 원반 무료 대여", "10분 · 다 놀면 반납해 주세요", Color3.fromRGB(40, 150, 220))
	tagInteract(top, "rental", def.id, "비치볼 · 원반 대여소")
	m.Parent = propFolder
end

local function buildFishSpot(id: string, cf: CFrame)
	-- cf at deck level, LookVector toward the water
	local m = propModel("낚시 포인트 " .. id)
	local plate = cyl(m, 0.12, 2.6, cf * CFrame.new(0, 0.06, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(255, 200, 40), Enum.Material.SmoothPlastic, "SpotMark")
	plate.CanQuery = true
	box(m, Vector3.new(0.2, 3.4, 0.2), cf * CFrame.new(1.6, 1.7, 0.6), Color3.fromRGB(60, 60, 64), Enum.Material.Metal, "SignPost", false)
	sign(m, Vector3.new(1.8, 1.0, 0.12), cf * CFrame.new(1.6, 3.6, 0.6) * CFrame.Angles(0, math.pi, 0), "🎣 낚시", "포인트", Color3.fromRGB(20, 90, 160))
	box(m, Vector3.new(1.4, 0.9, 1.0), cf * CFrame.new(-1.6, 0.45, 0.8), Color3.fromRGB(60, 140, 220), Enum.Material.SmoothPlastic, "Cooler", false)
	tagInteract(plate, "fish", id, "낚시 포인트")
	m.Parent = propFolder
end

local function buildFishMarket(cf: CFrame)
	local def = IS.FISHING.market
	local m = propModel("수산시장 매입 코너")
	box(m, Vector3.new(7, 3, 3.2), cf * CFrame.new(0, 1.5, 0), Color3.fromRGB(60, 120, 200), Enum.Material.SmoothPlastic, "StallBody", true)
	local top = box(m, Vector3.new(7.2, 0.3, 3.4), cf * CFrame.new(0, 3.15, 0), Color3.fromRGB(200, 200, 206), Enum.Material.Metal, "Counter", false)
	box(m, Vector3.new(6.4, 0.3, 2.6), cf * CFrame.new(0, 3.4, 0), Color3.fromRGB(230, 244, 255), Enum.Material.Ice, "IceBed", false)
	local fishColors = { Color3.fromRGB(150, 170, 190), Color3.fromRGB(200, 120, 110), Color3.fromRGB(120, 130, 120) }
	for i = 0, 5 do
		local f = box(m, Vector3.new(0.5, 0.3, 1.6), cf * CFrame.new(-2.6 + i * 1.05, 3.7, 0.1) * CFrame.Angles(0, 0.3 * ((i % 2) * 2 - 1), 0), fishColors[(i % 3) + 1], Enum.Material.SmoothPlastic, "Fish", false)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = f
	end
	for _, sx in { -3.4, 3.4 } do
		box(m, Vector3.new(0.2, 5, 0.2), cf * CFrame.new(sx, 5.6, 1.5), Color3.fromRGB(230, 230, 230), Enum.Material.Metal, "Post", false)
	end
	box(m, Vector3.new(7.6, 0.3, 3.8), cf * CFrame.new(0, 8.2, 0.2), Color3.fromRGB(240, 240, 240), Enum.Material.Fabric, "Canopy", false)
	sign(m, Vector3.new(7, 1.4, 0.15), cf * CFrame.new(0, 7.2, -1.75), "🐟 수산시장 매입 코너", "잡은 생선 삽니다 · 시세대로 바로 정산", Color3.fromRGB(20, 90, 160))
	tagInteract(top, "fishsell", def.id, "수산시장 매입 코너")
	m.Parent = propFolder
	vendorBehind(m, cf, 2.6, "wipe", def.id, "fisher")
end

local function buildSandSpot(cf: CFrame)
	local def = IS.SAND.spot
	local m = propModel("모래성 만들기")
	box(m, Vector3.new(0.25, 3.6, 0.25), cf * CFrame.new(0, 1.8, 0), Color3.fromRGB(150, 104, 66), Enum.Material.Wood, "SignPost", false)
	sign(m, Vector3.new(3.4, 1.6, 0.15), cf * CFrame.new(0, 3.8, -0.1), "🏰 모래성 만들기", "삽 들고 5단계 완성!", Color3.fromRGB(240, 170, 60))
	local bucket = cyl(m, 1.0, 1.1, cf * CFrame.new(1.4, 0.5, -1.2) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(255, 80, 80), Enum.Material.SmoothPlastic, "Bucket")
	local shovel = box(m, Vector3.new(0.6, 0.12, 1.4), cf * CFrame.new(2.1, 0.1, -0.4) * CFrame.Angles(0, 0.6, 0), Color3.fromRGB(60, 160, 255), Enum.Material.SmoothPlastic, "Shovel", false)
	local _s = shovel
	local mark = box(m, Vector3.new(4, 0.2, 4), cf * CFrame.new(0, 0.1, -2.6), Color3.fromRGB(226, 200, 150), Enum.Material.Sand, "BuildArea", false)
	mark.Transparency = 0.6
	tagInteract(bucket, "sandcastle", def.id, "모래성 만들기")
	m.Parent = propFolder
end

local function buildPhotoFrame(cf: CFrame)
	-- cf at sand level, LookVector INLAND (the photographer's side); the bridge is behind the frame
	local def = IS.PHOTO_FRAME
	local m = propModel("광안대교 뷰 포토존")
	local white = Color3.fromRGB(250, 250, 250)
	local pink = Color3.fromRGB(255, 80, 150)
	for _, sx in { -4.2, 4.2 } do
		box(m, Vector3.new(0.8, 10, 0.8), cf * CFrame.new(sx, 5, 0), white, Enum.Material.SmoothPlastic, "FramePost", true)
	end
	box(m, Vector3.new(9.2, 0.8, 0.8), cf * CFrame.new(0, 10.2, 0), white, Enum.Material.SmoothPlastic, "FrameTop", true)
	local h1 = ball(m, 1.5, cf * CFrame.new(-0.55, 11.45, 0), pink, Enum.Material.Neon, "Heart")
	local h2 = ball(m, 1.5, cf * CFrame.new(0.55, 11.45, 0), pink, Enum.Material.Neon, "Heart")
	box(m, Vector3.new(1.55, 1.55, 0.6), cf * CFrame.new(0, 10.85, 0) * CFrame.Angles(0, 0, math.rad(45)), pink, Enum.Material.Neon, "HeartTip", false)
	h1:AddTag("NightNeon")
	h2:AddTag("NightNeon")
	sign(m, Vector3.new(6.4, 1.1, 0.15), cf * CFrame.new(0, 9.0, -0.45) * CFrame.Angles(0, math.pi, 0), "I ♥ 광안리", "GWANGALLI BEACH", Color3.fromRGB(20, 30, 70), Color3.fromRGB(255, 220, 240))
	local spot = box(m, Vector3.new(5, 0.2, 3), cf * CFrame.new(0, 0.1, 3.4), Color3.fromRGB(255, 180, 210), Enum.Material.SmoothPlastic, "PhotoSpot", false)
	spot.Transparency = 0.25
	tagInteract(spot, "photozone", def.id, "광안대교 뷰 포토존")
	m.Parent = propFolder
end

local function buildBusker(def: any, cf: CFrame)
	-- cf: performer at ground, LookVector toward the audience
	local m = propModel("버스커 " .. def.id)
	box(m, Vector3.new(0.12, 5.2, 0.12), cf * CFrame.new(0, 2.6, -1.3), Color3.fromRGB(30, 30, 34), Enum.Material.Metal, "MicStand", false)
	ball(m, 0.36, cf * CFrame.new(0, 5.35, -1.25), Color3.fromRGB(60, 60, 64), Enum.Material.Metal, "Mic")
	box(m, Vector3.new(1.8, 1.6, 1.1), cf * CFrame.new(-2.3, 0.8, 0.6), Color3.fromRGB(28, 28, 30), Enum.Material.Fabric, "Amp", true)
	local case = box(m, Vector3.new(1.6, 0.35, 3.4), cf * CFrame.new(0.9, 0.18, -3.4) * CFrame.Angles(0, 0.3, 0), Color3.fromRGB(30, 30, 34), Enum.Material.Leather, "GuitarCase", false)
	box(m, Vector3.new(1.35, 0.1, 3.1), cf * CFrame.new(0.9, 0.38, -3.4) * CFrame.Angles(0, 0.3, 0), Color3.fromRGB(150, 30, 40), Enum.Material.Fabric, "CaseLining", false)
	box(m, Vector3.new(0.15, 3.4, 0.15), cf * CFrame.new(-3.4, 1.7, -2.6), Color3.fromRGB(30, 30, 34), Enum.Material.Metal, "SignStand", false)
	sign(m, Vector3.new(2.8, 1.6, 0.1), cf * CFrame.new(-3.4, 4.1, -2.6) * CFrame.Angles(0, math.pi, 0), "🎵 BUSKING", "「" .. def.song .. "」", Color3.fromRGB(24, 24, 26), Color3.fromRGB(255, 230, 90))
	tagInteract(case, "busker", def.id, "버스커 · " .. def.song)
	case:SetAttribute("GwSong", def.song)
	m.Parent = propFolder
	local rig = buildRig(m, "Busker", cf, def.look, "guitar", def.id)
	if rig then
		local torso = rig:FindFirstChild("UpperTorso")
		if torso and torso:IsA("BasePart") then
			local body = box(rig, Vector3.new(1.3, 1.7, 0.35), torso.CFrame * CFrame.new(0.15, -0.55, -0.7) * CFrame.Angles(0, 0, math.rad(-28)), Color3.fromRGB(190, 130, 70), Enum.Material.WoodPlanks, "GuitarBody", false)
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = body
			local neck = box(rig, Vector3.new(0.18, 2.1, 0.12), body.CFrame * CFrame.new(0, 1.75, 0), Color3.fromRGB(70, 44, 30), Enum.Material.WoodPlanks, "GuitarNeck", false)
			for _, p in { body, neck } do
				local w = Instance.new("WeldConstraint")
				w.Part0 = torso
				w.Part1 = p
				w.Parent = p
				p.Anchored = false
				p.Massless = true
			end
		end
		rig:SetAttribute("GwSong", def.song)
		rig:SetAttribute(IS.Attr.Id, def.id)
	end
end

---------------------------------------------------------------------------------------------------
-- Sittable discovery (one chunked walk at start)
---------------------------------------------------------------------------------------------------
local EXCL_TAGS = { ClubVenue = true, ClubTable = true, HospitalBed = true, SalonChair = true, GymStation = true, BowlingLane = true, ShopCounter = true, ClubZone = true }
local EXCL_TOP = { homes = true, npcnav = true, club = true }

local function excluded(d: Instance, mapRoot: Instance?): boolean
	for _, t in d:GetTags() do
		if EXCL_TAGS[t] then
			return true
		end
	end
	local p = d.Parent
	local depth = 0
	while p and p ~= Workspace and depth < 14 do
		local n = p.Name
		if p:IsA("Model") then
			if string.sub(n, 1, 4) == "Car_" or string.find(n, "CLUB OCEAN", 1, true) or n == "볼링레인" or string.find(n, "Vehicle", 1, true) or string.find(n, "Taxi", 1, true) then
				return true
			end
			for _, t in p:GetTags() do
				if EXCL_TAGS[t] then
					return true
				end
			end
			if p:FindFirstChildOfClass("VehicleSeat") then
				return true
			end
		end
		if EXCL_TOP[n] and (p.Parent == Workspace or p.Parent == mapRoot) then
			return true
		end
		if p == propFolder then
			return true
		end
		p = p.Parent
		depth += 1
	end
	return false
end

-- Object-space direction a sitter faces on `part`, from the nearest sibling back rest (nil = none).
local function backFace(part: BasePart): Vector3?
	local parent = part.Parent
	if not parent then
		return nil
	end
	local best: BasePart? = nil
	local bestD = 4.5
	for _, c in parent:GetChildren() do
		if c ~= part and c:IsA("BasePart") then
			local n = string.lower(c.Name)
			if string.find(n, "back", 1, true) then
				local d = (c.Position - part.Position).Magnitude
				if d < bestD then
					best, bestD = c, d
				end
			end
		end
	end
	if not best then
		return nil
	end
	local lp = part.CFrame:PointToObjectSpace((best :: BasePart).Position)
	-- away from the back, along the dominant horizontal object axis
	local v = Vector3.new(-lp.X, 0, -lp.Z)
	if math.abs(v.X) > math.abs(v.Z) then
		return Vector3.new(math.sign(v.X), 0, 0)
	elseif math.abs(v.Z) > 0.05 then
		return Vector3.new(0, 0, math.sign(v.Z))
	end
	return nil
end

local scanStats = { tagged = 0, byKind = {} :: { [string]: number }, seconds = 0 }

local function tagSittable(d: BasePart, kind: string)
	if d:HasTag(IS.Tags.Sittable) then
		return
	end
	d:SetAttribute(IS.Attr.SitKind, kind)
	if kind == "bench" or kind == "sofa" or kind == "chair" then
		local f = backFace(d)
		if f then
			d:SetAttribute(IS.Attr.SitFace, f)
		end
	end
	if kind == "edge" then
		-- sea-wall parapets are railing height from the promenade: offer 기대기 too
		local n = string.lower(d.Name)
		if string.find(n, "parapet", 1, true) then
			d:SetAttribute(IS.Attr.SitLean, true)
		end
	end
	d:AddTag(IS.Tags.Sittable)
	scanStats.tagged += 1
	scanStats.byKind[kind] = (scanStats.byKind[kind] or 0) + 1
end

local function scanSittables()
	local t0 = os.clock()
	local mapRoot = Workspace:FindFirstChild("Gwangalli")
	local list = Workspace:GetDescendants()
	local chunk = IS.SIT.scanChunk
	for i, d in list do
		if d:IsA("BasePart") then
			local ok, kind = pcall(IS.classify, d.Name, d.ClassName, d.Size)
			if ok and kind and not excluded(d, mapRoot) then
				-- a Seat another system keeps for itself (attribute Sittable = false) is left alone
				if not (d:IsA("Seat") and d:GetAttribute("Sittable") == false) then
					tagSittable(d, kind)
				end
			end
		end
		if i % chunk == 0 then
			task.wait()
		end
	end
	scanStats.seconds = os.clock() - t0
	local parts = {}
	for k, n in scanStats.byKind do
		table.insert(parts, k .. " " .. n)
	end
	print(string.format("[Interact] sittables: %d tagged in %.2f s (%s)", scanStats.tagged, scanStats.seconds, table.concat(parts, ", ")))
end

---------------------------------------------------------------------------------------------------
-- Beach balls / frisbees
---------------------------------------------------------------------------------------------------
type BallRec = {
	part: BasePart,
	kind: string,
	holder: Player?,
	renter: Player?,
	rentedAt: number,
	thrower: Player?,
	thrownAt: number,
	flying: boolean,
	restT: number,
	waterT: number,
	weld: Weld?,
	lift: VectorForce?,
	npc: any?,
}
local balls: { BallRec } = {}
local standCF: CFrame? = nil
local friends: { { id: string, model: Model, cf: CFrame, busy: boolean } } = {}
local flyingCount = 0

local function ballHome(i: number): CFrame
	local base = standCF or CFrame.new(IS.point(IS.RENTAL.stand.x, IS.RENTAL.stand.n, 3.5))
	return base * CFrame.new(-2 + (i - 1) * 1.3, 5.2, 0.6)
end

local function setBallFree(rec: BallRec, interact: boolean)
	rec.part:SetAttribute(IS.Attr.Holder, 0)
	if interact then
		if not rec.part:HasTag(IS.Tags.Interact) then
			tagInteract(rec.part, "ball", rec.kind, if rec.kind == "frisbee" then "원반" else "비치볼")
		end
	elseif rec.part:HasTag(IS.Tags.Interact) then
		rec.part:RemoveTag(IS.Tags.Interact)
	end
end

local function detachBall(rec: BallRec)
	if rec.weld then
		rec.weld:Destroy()
		rec.weld = nil
	end
	if rec.holder then
		local s = states[rec.holder]
		if s and s.ball == rec then
			s.ball = nil
		end
		local char = rec.holder.Character
		if char and char:GetAttribute(IS.Attr.Held) == "ball" then
			char:SetAttribute(IS.Attr.Held, "")
			char:SetAttribute(IS.Attr.Pose, "")
		end
	end
	rec.holder = nil
	rec.part.Massless = false
	rec.part.CanCollide = true
end

local function returnBall(i: number)
	local rec = balls[i]
	if not rec then
		return
	end
	detachBall(rec)
	if rec.flying then
		rec.flying = false
		flyingCount = math.max(0, flyingCount - 1)
	end
	if rec.lift then
		rec.lift.Enabled = false
	end
	rec.renter = nil
	rec.thrower = nil
	rec.npc = nil
	rec.part.Anchored = true
	rec.part.CFrame = ballHome(i)
	rec.part.AssemblyLinearVelocity = Vector3.zero
	rec.part.Transparency = 1
	rec.part.CanCollide = false
	rec.part.CanQuery = false
	setBallFree(rec, false)
end

local function indexOf(rec: BallRec): number
	for i, r in balls do
		if r == rec then
			return i
		end
	end
	return 0
end

local function attachBall(rec: BallRec, player: Player): boolean
	local char, humanoid = alive(player)
	if not char or not humanoid then
		return false
	end
	local anchor = if rec.kind == "frisbee" then rightHand(char) else chest(char)
	if not anchor then
		return false
	end
	detachBall(rec)
	if rec.flying then
		rec.flying = false
		flyingCount = math.max(0, flyingCount - 1)
	end
	if rec.lift then
		rec.lift.Enabled = false
	end
	clearHeld(player)
	local p = rec.part
	p.Anchored = false
	p.Transparency = 0
	p.CanCollide = false
	p.CanQuery = true
	p.Massless = true
	local c0 = if rec.kind == "frisbee" then CFrame.new(0, -0.45, -0.3) * CFrame.Angles(0, 0, math.pi / 2) else CFrame.new(0, -0.2, -1.55)
	p.CFrame = anchor.CFrame * c0
	p.AssemblyLinearVelocity = Vector3.zero
	local w = Instance.new("Weld")
	w.Part0 = anchor
	w.Part1 = p
	w.C0 = c0
	w.Parent = p
	rec.weld = w
	rec.holder = player
	rec.restT = os.clock()
	p:SetAttribute(IS.Attr.Holder, player.UserId)
	setBallFree(rec, false)
	S(player).ball = rec
	char:SetAttribute(IS.Attr.Held, "ball")
	char:SetAttribute(IS.Attr.Pose, if rec.kind == "frisbee" then "hold_one" else "hold_front")
	return true
end

local function makeBalls()
	for i, kind in IS.RENTAL.pool do
		local p = Instance.new("Part")
		p.Name = if kind == "frisbee" then "Frisbee" else "BeachBall"
		if kind == "frisbee" then
			p.Shape = Enum.PartType.Cylinder
			p.Size = Vector3.new(0.28, 2.2, 2.2)
			p.Color = if i % 2 == 0 then Color3.fromRGB(70, 200, 255) else Color3.fromRGB(255, 120, 60)
			p.CustomPhysicalProperties = PhysicalProperties.new(0.35, 0.6, 0.25, 1, 1)
			local att = Instance.new("Attachment")
			att.Parent = p
			local vf = Instance.new("VectorForce")
			vf.Attachment0 = att
			vf.RelativeTo = Enum.ActuatorRelativeTo.World
			vf.ApplyAtCenterOfMass = true
			vf.Enabled = false
			vf.Parent = p
		else
			p.Shape = Enum.PartType.Ball
			p.Size = Vector3.new(2.2, 2.2, 2.2)
			p.Color = if i % 2 == 0 then Color3.fromRGB(255, 220, 60) else Color3.fromRGB(255, 90, 110)
			p.CustomPhysicalProperties = PhysicalProperties.new(0.12, 0.5, 0.7, 1, 1)
		end
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CastShadow = true
		p:SetAttribute(IS.Attr.BallKind, kind)
		p:SetAttribute(IS.Attr.Holder, 0)
		p:AddTag(IS.Tags.Ball)
		p:AddTag(IS.Tags.Prop)
		p.Parent = propFolder
		local vf = p:FindFirstChildOfClass("VectorForce")
		table.insert(balls, { part = p, kind = kind, holder = nil, renter = nil, rentedAt = 0, thrower = nil, thrownAt = 0, flying = false, restT = os.clock(), waterT = 0, weld = nil, lift = vf, npc = nil })
		returnBall(#balls)
	end
end

local function ballistic(p0: Vector3, p1: Vector3, t: number): Vector3
	local g = Workspace.Gravity
	return (p1 - p0) / t + Vector3.new(0, 0.5 * g * t, 0)
end

local function throwBall(rec: BallRec, from: Vector3, vel: Vector3, thrower: Player?)
	local p = rec.part
	detachBall(rec)
	p.Anchored = false
	p.Transparency = 0
	p.CanCollide = true
	p.CanQuery = true
	p.CFrame = CFrame.new(from) * (if rec.kind == "frisbee" then CFrame.Angles(0, 0, math.pi / 2) else CFrame.new())
	rec.thrower = thrower
	rec.thrownAt = os.clock()
	if not rec.flying then
		rec.flying = true
		flyingCount += 1
	end
	rec.restT = os.clock()
	if rec.lift then
		local mass = p.AssemblyMass
		rec.lift.Force = Vector3.new(0, mass * Workspace.Gravity * 0.72, 0)
		rec.lift.Enabled = true
	end
	if thrower and thrower.Parent == Players then
		pcall(function()
			p:SetNetworkOwner(thrower)
		end)
	else
		pcall(function()
			p:SetNetworkOwner(nil)
		end)
	end
	p.AssemblyLinearVelocity = vel
	if rec.kind == "frisbee" then
		p.AssemblyAngularVelocity = Vector3.new(0, 18, 0)
	end
	setBallFree(rec, false)
	if thrower then
		fire(thrower, { kind = "throw", ball = p, vel = vel })
	end
end

local function nearestFriend(pos: Vector3, maxD: number): any?
	local best, bestD = nil, maxD
	for _, f in friends do
		if not f.busy and f.model.Parent then
			local d = (f.cf.Position - pos).Magnitude
			if d < bestD then
				best, bestD = f, d
			end
		end
	end
	return best
end

local function friendCatch(rec: BallRec, f: any)
	f.busy = true
	if rec.flying then
		rec.flying = false
		flyingCount = math.max(0, flyingCount - 1)
	end
	if rec.lift then
		rec.lift.Enabled = false
	end
	local p = rec.part
	local hands = f.cf * CFrame.new(0, 4.2, -1.3)
	p.Anchored = true
	p.AssemblyLinearVelocity = Vector3.zero
	p.CFrame = hands
	rec.npc = f
	fireNear(hands.Position, 250, { kind = "friend", id = f.id, act = "catch", pos = hands.Position })
	local target = rec.thrower
	task.delay(1.3, function()
		if rec.npc ~= f then
			f.busy = false
			return
		end
		rec.npc = nil
		local tp = target and Util.rootPosition(target)
		if tp and (tp - hands.Position).Magnitude < 110 then
			local dist = (tp - hands.Position).Magnitude
			local t = math.clamp(dist / 34, 0.9, 2.4)
			local aim = tp + Vector3.new(rng:NextNumber(-1.5, 1.5), 1.2, rng:NextNumber(-1.5, 1.5))
			fireNear(hands.Position, 250, { kind = "friend", id = f.id, act = "throw", pos = hands.Position })
			throwBall(rec, hands.Position, ballistic(hands.Position, aim, t), nil)
			rec.thrower = nil
		else
			-- nobody to throw to: back to the stand
			local i = indexOf(rec)
			if i > 0 then
				returnBall(i)
			end
		end
		task.delay(1.2, function()
			f.busy = false
		end)
	end)
end

-- 10 Hz while anything flies: catches by players and beach friends, landing.
local function stepBalls()
	local now = os.clock()
	for i, rec in balls do
		if rec.flying then
			local p = rec.part
			local pos = p.Position
			local v = p.AssemblyLinearVelocity
			local caught = false
			-- players
			for _, pl in Players:GetPlayers() do
				if pl ~= rec.thrower or now - rec.thrownAt > 1.2 then
					local s = states[pl]
					if s and not s.ball and not s.sit and busyOf(pl) == "" then
						local rp = Util.rootPosition(pl)
						if rp and (rp + Vector3.new(0, 1, 0) - pos).Magnitude <= IS.RENTAL.catchRadius and now - rec.thrownAt > 0.25 then
							local thrower = rec.thrower
							if attachBall(rec, pl) then
								caught = true
								fireNear(rp, 200, { kind = "catch", by = pl.UserId, pos = rp })
								notify(pl, "success", "나이스 캐치! 🙌", if thrower then (thrower.DisplayName .. "님이 던진 공을 받았어요") else "공을 받았어요")
								if thrower and thrower ~= pl then
									notify(thrower, "success", "패스 성공! 🏐", pl.DisplayName .. "님이 받았어요")
								end
							end
							break
						end
					end
				end
			end
			if not caught and v.Magnitude < 40 and now - rec.thrownAt > 0.4 then
				local f = nearestFriend(pos, 13)
				if f and pos.Y < f.cf.Position.Y + 9 then
					friendCatch(rec, f)
					caught = true
				end
			end
			if not caught then
				if v.Magnitude < 2.5 then
					if now - rec.restT > 0.6 then
						rec.flying = false
						flyingCount = math.max(0, flyingCount - 1)
						if rec.lift then
							rec.lift.Enabled = false
						end
						rec.restT = now
						setBallFree(rec, true)
						pcall(function()
							p:SetNetworkOwner(nil)
						end)
					end
				else
					rec.restT = now
				end
				if now - rec.thrownAt > 9 then
					rec.flying = false
					flyingCount = math.max(0, flyingCount - 1)
					if rec.lift then
						rec.lift.Enabled = false
					end
					rec.restT = now
					setBallFree(rec, true)
				end
				-- frisbee: drop the lift once it is falling fast or near the ground
				if rec.lift and rec.lift.Enabled and (v.Y < -25 or now - rec.thrownAt > 2.6) then
					rec.lift.Enabled = false
				end
			end
		end
		local _ = i
	end
end

-- 1 Hz housekeeping: idle / water / rental expiry.
local function tickBalls()
	local now = os.clock()
	for i, rec in balls do
		local p = rec.part
		if rec.holder then
			if rec.holder.Parent ~= Players or not rec.holder.Character or not p:IsDescendantOf(rec.holder.Character or Workspace) and not rec.weld then
				returnBall(i)
			elseif rec.renter == rec.holder and now - rec.rentedAt > IS.RENTAL.rentSeconds then
				notify(rec.holder, "info", "대여 시간 끝!", "공을 대여소에 돌려놨어요")
				returnBall(i)
			end
		elseif not rec.flying and not rec.npc and not p.Anchored then
			local pos = p.Position
			if pos.Y < -20 then
				returnBall(i)
			elseif IS.inBay(pos) and pos.Y < 1.5 then
				rec.waterT += 1
				if rec.waterT > 18 then
					rec.waterT = 0
					returnBall(i)
				end
			elseif now - rec.restT > IS.RENTAL.idleReturn then
				returnBall(i)
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Sandcastles
---------------------------------------------------------------------------------------------------
local castles: { { model: Model, t: number, owner: number, n: number, cf: CFrame } } = {}
local sandSpotCF: CFrame? = nil
local SAND = Color3.fromRGB(222, 196, 148)

local function castlePiece(c: any, n: number)
	local cf = c.cf
	local m = c.model
	local p: Part
	if n == 1 then
		p = box(m, Vector3.new(6, 1.2, 6), cf * CFrame.new(0, 0.6, 0), SAND, Enum.Material.Sand, "Mound", true)
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(1.2, 6, 6)
		p.CFrame = cf * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.pi / 2)
	elseif n == 2 then
		p = box(m, Vector3.new(2.6, 2.4, 2.6), cf * CFrame.new(0, 2.4, 0), SAND, Enum.Material.Sand, "Keep", true)
	elseif n == 3 then
		p = cyl(m, 3.4, 1.4, cf * CFrame.new(-2.1, 2.9, 0.4) * CFrame.Angles(0, 0, math.pi / 2), SAND, Enum.Material.Sand, "TowerL")
	elseif n == 4 then
		p = cyl(m, 3.4, 1.4, cf * CFrame.new(2.1, 2.9, 0.4) * CFrame.Angles(0, 0, math.pi / 2), SAND, Enum.Material.Sand, "TowerR")
	else
		box(m, Vector3.new(0.12, 2.2, 0.12), cf * CFrame.new(0, 4.7, 0), Color3.fromRGB(150, 104, 66), Enum.Material.Wood, "FlagPole", false)
		p = box(m, Vector3.new(1.1, 0.7, 0.06), cf * CFrame.new(0.6, 5.45, 0), Color3.fromRGB(255, 70, 90), Enum.Material.Fabric, "Flag", false)
	end
	-- pop in (tween from a flat scale)
	local goal = p.Size
	p.Size = goal * Vector3.new(1, 0.15, 1)
	pcall(function()
		TweenService:Create(p, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = goal }):Play()
	end)
end

local function removeCastle(i: number)
	local c = castles[i]
	if c then
		c.model:Destroy()
		table.remove(castles, i)
	end
end

---------------------------------------------------------------------------------------------------
-- Fireworks shows
---------------------------------------------------------------------------------------------------
local shows: { { t: number, pos: Vector3 } } = {}

---------------------------------------------------------------------------------------------------
-- Request handlers
---------------------------------------------------------------------------------------------------
local handlers: { [string]: (Player, any) -> any } = {}

handlers.sit = function(player, p)
	local part = p.part
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return fail("bad", "")
	end
	if not part:HasTag(IS.Tags.Sittable) and not part:IsA("Seat") then
		return fail("nosit", "여기엔 앉을 수 없어요")
	end
	if part:IsA("Seat") and not part:HasTag(IS.Tags.Sittable) then
		return fail("nosit", "여기엔 앉을 수 없어요")
	end
	return sitOn(player, part, if p.mode == "lie" then "lie" else "sit")
end

handlers.stand = function(player, _p)
	standUp(player)
	if busyOf(player) == IS.BUSY.lean then
		setBusy(player, nil)
		setPose(player, "")
	end
	return { ok = true }
end

handlers.lean = function(player, p)
	local part = p.part
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") or not part:HasTag(IS.Tags.Sittable) then
		return fail("bad", "")
	end
	return lean(player, part, p.back == true)
end

handlers.pose = function(player, p)
	local name = p.name
	if not IS.validPose(name) then
		return fail("bad", "")
	end
	local s = S(player)
	if not cooldown(s, "pose", 0.25) then
		return fail("rate", "")
	end
	local b = busyOf(player)
	if name ~= "" and (b == IS.BUSY.sit or b == IS.BUSY.fish or b == IS.BUSY.claw or b == IS.BUSY.eat) then
		return fail("busy", "")
	end
	if b == IS.BUSY.lean and name == "" then
		setBusy(player, nil)
	end
	setPose(player, name)
	return { ok = true }
end

handlers.emote = function(player, p)
	local id = p.id
	local def = type(id) == "string" and IS.EMOTE_BY_ID[id]
	if not def or def.kind ~= "proc" then
		return fail("bad", "")
	end
	local s = S(player)
	if not cooldown(s, "emote", 0.6) then
		return fail("rate", "")
	end
	local char = player.Character
	if char then
		s.emoteSeq += 1
		char:SetAttribute(IS.Attr.Emote, id .. "#" .. s.emoteSeq)
	end
	return { ok = true }
end

local function eat(player: Player, id: string)
	local f = IS.FOOD[id]
	local s = S(player)
	local color = rgb(f.color)
	setHeld(player, f.prop, color, f.eat + 0.6)
	setBusy(player, IS.BUSY.eat)
	setPose(player, if f.drink then "drink" else "eat")
	local day = lifeDay(player)
	local food = s.data.food
	if food.day ~= day then
		s.data.food = { day = day, counts = {} }
		food = s.data.food
	end
	local n = (food.counts[id] or 0) + 1
	food.counts[id] = n
	task.delay(f.eat, function()
		if player.Parent ~= Players then
			return
		end
		if busyOf(player) == IS.BUSY.eat then
			setBusy(player, nil)
			local char = player.Character
			if char then
				local cur = char:GetAttribute(IS.Attr.Pose)
				if cur == "eat" or cur == "drink" then
					char:SetAttribute(IS.Attr.Pose, "")
				end
			end
		end
		if n <= IS.FOOD_DAILY_STATS then
			local applied = ctx.addStats(player, f.stats, nil, true)
			local desc = if applied and next(applied) then G.describeStats(applied) else ""
			notify(player, "stat", f.icon .. " " .. f.name, f.line .. (if desc ~= "" then ("\n" .. desc) else ""))
		else
			notify(player, "info", f.icon .. " " .. f.name, "배불러요! 오늘은 이 음식 효과가 더 없어요 😋")
		end
	end)
end

handlers.buy = function(player, p)
	local part = p.part
	local kind = kindOf(part)
	if kind ~= "food" and kind ~= "truck" and kind ~= "vending" then
		return fail("bad", "")
	end
	if not near(player, part, 12) then
		return fail("far", "조금 더 가까이 가요")
	end
	local id = p.item
	if type(id) ~= "string" or not IS.FOOD[id] or not table.find(itemsOf(part), id) then
		return fail("bad", "메뉴에 없어요")
	end
	local s = S(player)
	if not cooldown(s, "buy", 1.2) then
		return fail("rate", "잠깐만요")
	end
	local b = busyOf(player)
	if b ~= "" and b ~= IS.BUSY.lean then
		return fail("busy", "지금 하던 걸 먼저 끝내요")
	end
	if alive(player) == nil then
		return fail("dead", "")
	end
	local f = IS.FOOD[id]
	if not ctx.spend(player, f.price, (part:GetAttribute(IS.Attr.Label) or "길거리 음식") .. " · " .. f.name) then
		return fail("money", "돈이 모자라요 (" .. G.format.won(f.price) .. ")")
	end
	if b == IS.BUSY.lean then
		setBusy(player, nil)
	end
	eat(player, id)
	return { ok = true, item = id, seconds = f.eat }
end

handlers.tip = function(player, p)
	local part = p.part
	if kindOf(part) ~= "busker" or not near(player, part, 16) then
		return fail("far", "버스커 가까이에서 팁을 줘요")
	end
	local s = S(player)
	local id = part:GetAttribute(IS.Attr.Id)
	if not cooldown(s, "tip:" .. tostring(id), IS.BUSKER.tipCooldown) then
		return fail("rate", "방금 팁을 줬어요. 한 곡 더 듣고 줘요 🎶")
	end
	if not ctx.spend(player, IS.BUSKER.tip, "버스킹 팁") then
		return fail("money", "현금이 모자라요")
	end
	fireNear(part.Position, 220, { kind = "busker", id = id, act = "fanfare", by = player.UserId })
	if cooldown(s, "tipHappy", IS.BUSKER.happinessCooldown) then
		ctx.addStats(player, { happiness = 1 }, "버스킹 감상 🎸", false)
	end
	return { ok = true }
end

handlers.fireworksBuy = function(player, p)
	local part = p.part
	if kindOf(part) ~= "fireworks" or not near(player, part, 12) then
		return fail("far", "판매대 가까이에서 사요")
	end
	local s = S(player)
	if not cooldown(s, "buy", 1) then
		return fail("rate", "")
	end
	if p.sparkler == true then
		local sp = IS.FIREWORKS.sparkler
		if not ctx.spend(player, sp.price, sp.name) then
			return fail("money", "돈이 모자라요")
		end
		setHeld(player, "sparkler", Color3.fromRGB(200, 200, 200), sp.seconds)
		notify(player, "success", "✨ 스파클러 점화!", "반짝반짝 " .. sp.seconds .. "초 동안 들고 다닐 수 있어요")
		return { ok = true, sparkler = true }
	end
	if s.data.fireworks >= IS.FIREWORKS.maxOwned then
		return fail("full", "불꽃놀이 세트는 " .. IS.FIREWORKS.maxOwned .. "개까지 가질 수 있어요")
	end
	if not ctx.spend(player, IS.FIREWORKS.price, IS.FIREWORKS.name) then
		return fail("money", "돈이 모자라요 (" .. G.format.won(IS.FIREWORKS.price) .. ")")
	end
	s.data.fireworks += 1
	markDirty(player)
	pushData(player)
	return { ok = true, fireworks = s.data.fireworks }
end

handlers.fireworksLight = function(player, _p)
	local s = S(player)
	local _, _, root = alive(player)
	if not root then
		return fail("dead", "")
	end
	if s.data.fireworks <= 0 then
		return fail("none", "불꽃놀이 세트가 없어요. 해변 판매대에서 사요 🎆")
	end
	if not IS.onBeachSand(root.Position) then
		return fail("place", "불꽃놀이는 해변 모래사장에서만 할 수 있어요")
	end
	if not IS.isFireworksTime(clockNow()) then
		return fail("time", "불꽃놀이는 밤(18:30~05:00)에만 할 수 있어요 🌙")
	end
	if not cooldown(s, "fireworks", IS.FIREWORKS.cooldown) then
		return fail("rate", "잠깐! 불꽃이 다 꺼진 뒤에 다시 쏴요")
	end
	local now = os.clock()
	for i = #shows, 1, -1 do
		if now - shows[i].t > IS.FIREWORKS.showSeconds then
			table.remove(shows, i)
		end
	end
	if #shows >= IS.FIREWORKS.maxShows then
		s.cool.fireworks = nil
		return fail("busy", "하늘이 이미 불꽃으로 가득해요! 조금 뒤에 쏴요")
	end
	s.data.fireworks -= 1
	markDirty(player)
	local look = root.CFrame.LookVector
	local pos = root.Position + Vector3.new(look.X, 0, look.Z).Unit * 4 - Vector3.new(0, 2.5, 0)
	table.insert(shows, { t = now, pos = pos })
	fireAll({ kind = "fireworks", pos = pos, seed = rng:NextInteger(1, 1e6), t0 = Workspace:GetServerTimeNow(), dur = IS.FIREWORKS.showSeconds, by = player.UserId, name = player.DisplayName })
	if cooldown(s, "fwHappy", 120) then
		ctx.addStats(player, { happiness = 2, popularity = 0.5 }, "광안리 밤하늘 불꽃놀이 🎆", false)
	end
	pushData(player)
	return { ok = true, fireworks = s.data.fireworks }
end

-- Fishing -----------------------------------------------------------------------------------------
handlers.fishStart = function(player, p)
	local part = p.part
	if kindOf(part) ~= "fish" or not near(player, part, 9) then
		return fail("far", "낚시 포인트에 서서 해요")
	end
	local _, humanoid = alive(player)
	if not humanoid or humanoid.SeatPart then
		return fail("busy", "")
	end
	local b = busyOf(player)
	if b ~= "" and b ~= IS.BUSY.lean then
		return fail("busy", "지금 하던 걸 먼저 끝내요")
	end
	local s = S(player)
	s.fish = { spot = part, biteAt = nil, castAt = nil, last = 0 }
	setBusy(player, IS.BUSY.fish)
	setHeld(player, "rod", Color3.fromRGB(40, 40, 46), nil)
	setPose(player, "fish_hold")
	return { ok = true, cooler = #s.data.cooler, coolerMax = IS.FISHING.cooler }
end

handlers.fishCast = function(player, _p)
	local s = S(player)
	local f = s.fish
	if not f or busyOf(player) ~= IS.BUSY.fish then
		return fail("bad", "")
	end
	if not near(player, f.spot, 10) then
		return fail("far", "낚시 포인트에서 멀어졌어요")
	end
	local now = os.clock()
	if f.castAt and now - f.castAt < 2 then
		return fail("rate", "")
	end
	if #s.data.cooler >= IS.FISHING.cooler then
		return fail("full", "아이스박스가 가득 찼어요! 수산시장에 팔고 와요 🐟")
	end
	f.castAt = now
	local wait = rng:NextNumber(IS.FISHING.biteMin, IS.FISHING.biteMax)
	f.biteAt = now + wait
	return { ok = true, biteIn = wait }
end

handlers.fishHook = function(player, p)
	local s = S(player)
	local f = s.fish
	if not f or not f.biteAt or busyOf(player) ~= IS.BUSY.fish then
		return fail("bad", "")
	end
	local now = os.clock()
	local biteAt = f.biteAt
	f.biteAt = nil
	local early = now < biteAt - 0.25
	local late = now > biteAt + IS.FISHING.hookWindow + IS.FISHING.latency
	if early then
		return { ok = true, result = "early", message = "너무 빨랐어요! 입질이 오면 챔질해요" }
	elseif late then
		return { ok = true, result = "late", message = "놓쳤어요… 미끼만 따 먹고 갔어요" }
	end
	local q = tonumber(p.quality) or 0
	q = math.clamp(q, 0, 1)
	if rng:NextNumber() < IS.FISHING.junkChance then
		ctx.addStats(player, { happiness = 1 }, nil, true)
		return { ok = true, result = "junk", fish = { id = IS.FISH_JUNK.id, name = IS.FISH_JUNK.name, icon = IS.FISH_JUNK.icon, size = 0, price = 0 }, message = "바다를 깨끗하게! 행복 +1" }
	end
	local species, size, price = IS.rollFish(clockNow(), rng:NextNumber(), rng:NextNumber())
	local zone = IS.FISHING.zone[species.diff] or 0.2
	local chance = if q >= 0.5 then 0.92 else (0.35 + q * 0.9)
	local _ = zone
	if rng:NextNumber() > chance then
		return { ok = true, result = "escaped", message = species.name .. "(이)가 바늘을 털고 도망갔어요!", fish = { id = species.id, name = species.name, icon = species.icon } }
	end
	local d = s.data
	local isNew = (d.dex[species.id] or 0) == 0
	d.dex[species.id] = (d.dex[species.id] or 0) + 1
	local record = size > (d.best[species.id] or 0)
	if record then
		d.best[species.id] = size
	end
	table.insert(d.cooler, { id = species.id, size = size, price = price })
	markDirty(player)
	if isNew then
		ctx.addStats(player, { happiness = 2 }, nil, true)
		local count = 0
		for _ in d.dex do
			count += 1
		end
		if count >= #IS.FISH and not d.dexDone then
			d.dexDone = true
			ctx.addStats(player, { popularity = 3 }, "🎣 어종 도감 완성! 광안리 강태공", false)
		end
	end
	pushData(player)
	return { ok = true, result = "catch", fish = { id = species.id, name = species.name, icon = species.icon, size = size, price = price, new = isNew, record = record, diff = species.diff }, cooler = #d.cooler, coolerMax = IS.FISHING.cooler }
end

handlers.fishStop = function(player, _p)
	local s = S(player)
	if s.fish then
		s.fish = nil
		if s.heldId == "rod" then
			clearHeld(player)
		end
		if busyOf(player) == IS.BUSY.fish then
			setBusy(player, nil)
		end
		setPose(player, "")
	end
	return { ok = true }
end

handlers.fishSell = function(player, p)
	local part = p.part
	if kindOf(part) ~= "fishsell" or not near(player, part, 12) then
		return fail("far", "매입 코너 앞에서 팔아요")
	end
	local s = S(player)
	if not cooldown(s, "sell", 2) then
		return fail("rate", "")
	end
	local d = s.data
	if #d.cooler == 0 then
		return fail("empty", "팔 생선이 없어요. 민락항 방파제에서 낚아 와요 🎣")
	end
	local now = os.clock()
	local window = 0
	for i = #s.sales, 1, -1 do
		if now - s.sales[i].t > IS.FISHING.sellWindow then
			table.remove(s.sales, i)
		else
			window += s.sales[i].amount
		end
	end
	local room = IS.FISHING.sellCap - window
	if room <= 0 then
		return fail("cap", "오늘 매입 물량이 다 찼대요. 조금 있다 다시 와요")
	end
	local total, count = 0, 0
	local keep = {}
	for _, f in d.cooler do
		if total + f.price <= room then
			total += f.price
			count += 1
		else
			table.insert(keep, f)
		end
	end
	if count == 0 then
		return fail("cap", "오늘 매입 물량이 다 찼대요. 조금 있다 다시 와요")
	end
	if not ctx.addMoney(player, total, string.format("민락 수산시장 생선 판매 (%d마리)", count)) then
		return fail("error", "정산에 실패했어요")
	end
	d.cooler = keep
	table.insert(s.sales, { t = now, amount = total })
	markDirty(player)
	pushData(player)
	return { ok = true, total = total, count = count, left = #keep }
end

-- Beach balls -------------------------------------------------------------------------------------
handlers.rent = function(player, p)
	local part = p.part
	if kindOf(part) ~= "rental" or not near(player, part, 12) then
		return fail("far", "대여소 앞에서 빌려요")
	end
	local s = S(player)
	if s.ball then
		return fail("have", "이미 들고 있어요")
	end
	if busyOf(player) ~= "" then
		return fail("busy", "지금 하던 걸 먼저 끝내요")
	end
	local want = if p.kind == "frisbee" then "frisbee" else "ball"
	local pick: BallRec? = nil
	for _, rec in balls do
		if not rec.holder and not rec.renter and not rec.flying and rec.part.Anchored and rec.part.Transparency >= 1 then
			if rec.kind == want then
				pick = rec
				break
			end
			pick = pick or rec
		end
	end
	if not pick then
		return fail("none", "지금은 모두 대여 중이에요. 조금 뒤에 와요")
	end
	local rec = pick :: BallRec
	if not attachBall(rec, player) then
		return fail("error", "")
	end
	rec.renter = player
	rec.rentedAt = os.clock()
	return { ok = true, kind = rec.kind, ball = rec.part, minutes = math.floor(IS.RENTAL.rentSeconds / 60) }
end

handlers.pickup = function(player, p)
	local part = p.part
	if typeof(part) ~= "Instance" then
		return fail("bad", "")
	end
	local s = S(player)
	if s.ball or busyOf(player) ~= "" then
		return fail("busy", "")
	end
	for _, rec in balls do
		if rec.part == part then
			if rec.holder or rec.flying or rec.npc then
				return fail("taken", "")
			end
			if not near(player, part, 9) then
				return fail("far", "")
			end
			if not attachBall(rec, player) then
				return fail("error", "")
			end
			rec.renter = rec.renter or player
			if rec.rentedAt == 0 then
				rec.rentedAt = os.clock()
			end
			return { ok = true, kind = rec.kind, ball = rec.part }
		end
	end
	return fail("bad", "")
end

handlers.throw = function(player, p)
	local s = S(player)
	local rec = s.ball
	if not rec or rec.holder ~= player then
		return fail("bad", "")
	end
	local vel = p.vel
	if typeof(vel) ~= "Vector3" or vel ~= vel then
		return fail("bad", "")
	end
	local _, _, root = alive(player)
	if not root then
		return fail("dead", "")
	end
	local speed = vel.Magnitude
	if speed > IS.RENTAL.maxSpeed then
		vel = vel.Unit * IS.RENTAL.maxSpeed
	elseif speed < 4 then
		vel = (root.CFrame.LookVector + Vector3.new(0, 0.6, 0)).Unit * 20
	end
	local look = root.CFrame.LookVector
	local from = root.Position + Vector3.new(look.X, 0, look.Z).Unit * 2.4 + Vector3.new(0, 1.6, 0)
	throwBall(rec, from, vel, player)
	return { ok = true }
end

handlers.returnBall = function(player, _p)
	local s = S(player)
	local rec = s.ball
	if rec then
		local i = indexOf(rec)
		if i > 0 then
			returnBall(i)
		end
	end
	return { ok = true }
end

-- Sandcastle --------------------------------------------------------------------------------------
handlers.castle = function(player, _p)
	local _, humanoid, root = alive(player)
	if not root or not humanoid then
		return fail("dead", "")
	end
	if humanoid.SeatPart then
		return fail("busy", "")
	end
	local s = S(player)
	if not cooldown(s, "castle", 0.9) then
		return fail("rate", "")
	end
	local spot = sandSpotCF
	if not spot or (root.Position - spot.Position).Magnitude > IS.SAND.radius then
		return fail("far", "모래성 만들기 표지판 근처 모래밭에서 만들어요")
	end
	local b = s.build
	if b and (not b.castle.model.Parent or b.n >= IS.SAND.pieces) then
		s.build = nil
		b = nil
	end
	if not b then
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
		local at = root.Position + flat * 4.5
		local g = groundAt(at, at.Y + 6)
		if not g or not IS.onBeachSand(g) then
			return fail("place", "모래 위에서 만들어요")
		end
		for _, c in castles do
			if (c.cf.Position - g).Magnitude < 7 then
				return fail("place", "다른 모래성이랑 너무 가까워요")
			end
		end
		while #castles >= IS.SAND.maxCastles do
			removeCastle(1)
		end
		local m = propModel("모래성 · " .. player.DisplayName)
		m:SetAttribute(IS.Attr.Castle, player.UserId)
		m.Parent = propFolder
		local c = { model = m, t = os.clock(), owner = player.UserId, n = 0, cf = CFrame.lookAt(g, g - flat) }
		table.insert(castles, c)
		b = { castle = c, n = 0 }
		s.build = b
	end
	local bb = b :: any
	bb.n += 1
	bb.castle.n = bb.n
	castlePiece(bb.castle, bb.n)
	setPose(player, "build_sand")
	task.delay(0.8, function()
		local char = player.Character
		if char and char:GetAttribute(IS.Attr.Pose) == "build_sand" then
			char:SetAttribute(IS.Attr.Pose, "")
		end
	end)
	fireNear(bb.castle.cf.Position, 160, { kind = "castle", pos = bb.castle.cf.Position, n = bb.n })
	if bb.n >= IS.SAND.pieces then
		s.build = nil
		s.data.castles += 1
		markDirty(player)
		if cooldown(s, "castleReward", 300) then
			ctx.addStats(player, { happiness = 3, popularity = 0.5 }, "🏰 모래성 완성!", false)
		else
			notify(player, "success", "🏰 모래성 완성!", "멋진 작품이에요")
		end
		return { ok = true, n = bb.n, done = true }
	end
	return { ok = true, n = bb.n, done = false }
end

-- Photo spots / pets ----------------------------------------------------------------------------------
handlers.photo = function(player, _p)
	local s = S(player)
	if not cooldown(s, "photo", 2) then
		return fail("rate", "")
	end
	local rp = Util.rootPosition(player)
	if not rp then
		return fail("dead", "")
	end
	local spot = IS.photoSpotAt(rp)
	local area = IS.areaName(rp)
	local res: any = { ok = true, area = area, spot = spot and spot.id, spotName = spot and spot.name, new = false }
	if spot and not s.data.photos[spot.id] then
		s.data.photos[spot.id] = true
		markDirty(player)
		res.new = true
		ctx.addStats(player, { popularity = 1 }, "📸 새로운 포토 스팟: " .. spot.name, false)
		pushData(player)
	elseif cooldown(s, "photoHappy", 60) then
		ctx.addStats(player, { happiness = 0.5 }, nil, true)
	end
	local count = 0
	for _ in s.data.photos do
		count += 1
	end
	res.count = count
	res.total = #IS.PHOTO_SPOTS
	return res
end

handlers.pet = function(player, _p)
	local s = S(player)
	if not cooldown(s, "pet", 2) then
		return fail("rate", "")
	end
	if cooldown(s, "petHappy", IS.ANIMALS.petCooldown) then
		ctx.addStats(player, { happiness = 1 }, nil, true)
		return { ok = true, happy = true }
	end
	return { ok = true, happy = false }
end

-- Claw machine ------------------------------------------------------------------------------------
local function clawParts(machine: Instance): (BasePart?, { BasePart })
	local bed: BasePart? = nil
	local plush: { BasePart } = {}
	for _, c in machine:GetDescendants() do
		if c:IsA("BasePart") then
			if c.Name == "PrizeBed" then
				bed = c
			elseif c.Name == "Plush" then
				table.insert(plush, c)
			end
		end
	end
	return bed, plush
end

handlers.clawStart = function(player, p)
	local part = p.part
	if kindOf(part) ~= "claw" or not near(player, part, 9) then
		return fail("far", "기계 앞에서 해요")
	end
	local s = S(player)
	if busyOf(player) ~= "" then
		return fail("busy", "지금 하던 걸 먼저 끝내요")
	end
	if not cooldown(s, "claw", 2) then
		return fail("rate", "")
	end
	local machine = part.Parent
	if not machine then
		return fail("bad", "")
	end
	for other, os2 in states do
		if other ~= player and os2.claw and os2.claw.machine == machine then
			return fail("taken", "다른 사람이 하고 있어요")
		end
	end
	local bed = clawParts(machine)
	if not bed then
		return fail("bad", "고장 난 기계예요")
	end
	if not ctx.spend(player, IS.CLAW.price, "광안 게임랜드 인형뽑기") then
		return fail("money", "현금이 모자라요 (" .. G.format.won(IS.CLAW.price) .. ")")
	end
	s.claw = { machine = machine, bed = bed, t0 = os.clock() }
	setBusy(player, IS.BUSY.claw)
	setPose(player, "claw_play")
	return { ok = true, seconds = IS.CLAW.moveSeconds }
end

handlers.clawDrop = function(player, p)
	local s = S(player)
	local c = s.claw
	if not c then
		return fail("bad", "")
	end
	s.claw = nil
	local u = math.clamp(tonumber(p.u) or 0, -1, 1)
	local w = math.clamp(tonumber(p.w) or 0, -1, 1)
	local bed: BasePart = c.bed
	local _, plush = clawParts(c.machine)
	local half = bed.Size / 2
	local target = bed.CFrame * Vector3.new(u * (half.X - 0.3), half.Y, w * (half.Z - 0.3))
	local best: BasePart? = nil
	local bestD = math.huge
	for _, pz in plush do
		local d = Vector3.new(pz.Position.X - target.X, 0, pz.Position.Z - target.Z).Magnitude
		if d < bestD then
			best, bestD = pz, d
		end
	end
	local k = math.clamp(bestD / 1.5, 0, 1)
	local chance = IS.CLAW.bestChance + (IS.CLAW.baseChance - IS.CLAW.bestChance) * k
	if os.clock() - c.t0 > IS.CLAW.moveSeconds + 3 then
		chance *= 0.8
	end
	local win = best ~= nil and rng:NextNumber() < chance
	local res: any = { ok = true, win = win, target = target, plush = best }
	if win then
		local prize = IS.CLAW.prizes[rng:NextInteger(1, #IS.CLAW.prizes)]
		-- the plush under the claw decides the colour family when it matches one of the prizes
		res.prize = prize.id
		res.prizeName = prize.name
		res.icon = prize.icon
		s.data.plush[prize.id] = (s.data.plush[prize.id] or 0) + 1
		markDirty(player)
		task.delay(3.2, function()
			if player.Parent == Players then
				setHeld(player, "plush", rgb(prize.color), IS.CLAW.holdSeconds)
				ctx.addStats(player, { happiness = 2 }, prize.icon .. " " .. prize.name .. " 득템!", false)
			end
		end)
	end
	task.delay(3.4, function()
		if player.Parent == Players and busyOf(player) == IS.BUSY.claw then
			setBusy(player, nil)
			setPose(player, if win then "hold_front" else "")
			if win then
				task.delay(4, function()
					local char = player.Character
					if char and char:GetAttribute(IS.Attr.Pose) == "hold_front" and states[player] and states[player].heldId == "plush" then
						char:SetAttribute(IS.Attr.Pose, "hold_one")
					end
				end)
			end
		end
	end)
	return res
end

handlers.clawCancel = function(player, _p)
	local s = S(player)
	if s.claw then
		s.claw = nil
	end
	if busyOf(player) == IS.BUSY.claw then
		setBusy(player, nil)
		setPose(player, "")
	end
	return { ok = true }
end

handlers.busy = function(player, p)
	-- the client's own UI states (photo mode) so the hub of other systems can read them
	local what = p.what
	if what ~= "photo" and what ~= "" then
		return fail("bad", "")
	end
	local b = busyOf(player)
	if what == "photo" and b == "" then
		setBusy(player, IS.BUSY.photo)
	elseif what == "" and b == IS.BUSY.photo then
		setBusy(player, nil)
	end
	return { ok = true }
end

handlers.data = function(player, _p)
	return { ok = true, data = summary(player) }
end

handlers.drop = function(player, _p)
	local s = S(player)
	if s.ball then
		local i = indexOf(s.ball)
		if i > 0 then
			-- drop it at the feet (others can pick it up)
			local rec = s.ball
			local _, _, root = alive(player)
			detachBall(rec)
			rec.part.Anchored = false
			rec.part.CanCollide = true
			if root then
				rec.part.CFrame = CFrame.new(root.Position + root.CFrame.LookVector * 2.5)
			end
			rec.restT = os.clock()
			setBallFree(rec, true)
		end
	elseif s.heldId and s.heldId ~= "rod" then
		clearHeld(player)
		local char = player.Character
		if char then
			local cur = char:GetAttribute(IS.Attr.Pose)
			if cur == "hold_front" or cur == "hold_one" then
				char:SetAttribute(IS.Attr.Pose, "")
			end
		end
	end
	return { ok = true }
end

local function handle(player: Player, op: any, payload: any): any
	if type(op) ~= "string" then
		return fail("bad", "")
	end
	local h = handlers[op]
	if not h then
		return fail("bad", "")
	end
	if payload ~= nil and type(payload) ~= "table" then
		return fail("bad", "")
	end
	local s = S(player)
	if not bucket(s) then
		return fail("rate", "잠깐만요")
	end
	local ok, res = pcall(h, player, payload or {})
	if not ok then
		warn(string.format("[Interact] %s from %s failed: %s", op, player.Name, tostring(res)))
		return fail("error", "잠시 후 다시 해 주세요")
	end
	return res
end

---------------------------------------------------------------------------------------------------
-- World setup (props, tags) after the sittable scan
---------------------------------------------------------------------------------------------------
local function tagExisting()
	local root = Workspace:FindFirstChild("Gwangalli") or Workspace
	local trucks, claws = 0, 0
	for _, d in root:GetDescendants() do
		if d:IsA("Model") then
			local n = d.Name
			if string.sub(n, 1, #"푸드트럭 ") == "푸드트럭 " then
				local name = string.sub(n, #"푸드트럭 " + 1)
				local shelf = d:FindFirstChild("ServingShelf")
				if shelf and shelf:IsA("BasePart") then
					tagInteract(shelf, "truck", "truck_" .. tostring(trucks + 1), name, IS.TRUCK_MENUS[name] or IS.TRUCK_DEFAULT)
					trucks += 1
				end
			elseif string.match(n, "^ClawMachine_%d+$") then
				local door = d:FindFirstChild("PrizeDoor")
				if door and door:IsA("BasePart") then
					tagInteract(door, "claw", n, "인형뽑기")
					claws += 1
				end
			end
		end
	end
	print(string.format("[Interact] food trucks %d, claw machines %d", trucks, claws))
end

local function fishSpots(): { CFrame }
	local out: { CFrame } = {}
	local basin = IS.point(-2758, -150, 4)
	local root = Workspace:FindFirstChild("Gwangalli") or Workspace
	local decks = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "BreakwaterDeck" then
			table.insert(decks, d)
		end
	end
	table.sort(decks, function(a, b)
		return a.Position.X < b.Position.X
	end)
	for _, d in decks do
		local cf, sz = d.CFrame, d.Size
		local longIsX = sz.X >= sz.Z
		local hl = (if longIsX then sz.X else sz.Z) / 2
		local hs = (if longIsX then sz.Z else sz.X) / 2
		if hl >= 30 then
			local longAxis = if longIsX then cf.RightVector else cf.LookVector
			local shortAxis = if longIsX then cf.LookVector else cf.RightVector
			local topY = d.Position.Y + halfHeight(d)
			-- the side away from the harbour basin
			local side = if (d.Position - basin):Dot(shortAxis) >= 0 then 1 else -1
			for _, f in { -0.4, 0.4 } do
				if #out >= IS.FISHING.spotsMax then
					break
				end
				local pos = d.Position + longAxis * (hl * f) + shortAxis * side * (hs - 2)
				pos = Vector3.new(pos.X, topY, pos.Z)
				local out2 = shortAxis * side
				table.insert(out, CFrame.lookAt(pos, pos + Vector3.new(out2.X, 0, out2.Z)))
			end
		end
	end
	if #out == 0 then
		-- subset builds without the Millak port: two spots on the breakwater line anyway
		for _, x in { -2800, -2600 } do
			local p = IS.point(x, -276, 4.25)
			table.insert(out, CFrame.lookAt(p, p - IS.normal(x)))
		end
	end
	return out
end

local function buildWorld()
	local f = propFolder :: Folder
	-- street-food carts
	for _, def in IS.CARTS do
		local cf = findSpot(def.x, def.n, Vector3.new(7.5, 8, 6), false, false)
		if cf then
			buildCart(def, cf)
		end
	end
	for _, def in IS.VENDING do
		local cf = findSpot(def.x, def.n, Vector3.new(4, 7, 3.6), false, false)
		if cf then
			buildVending(def, cf)
		end
	end
	do
		local def = IS.FIREWORKS.stall
		local cf = findSpot(def.x, def.n, Vector3.new(7, 8, 4), false, false)
		if cf then
			buildFireworksStall(cf)
		end
	end
	for _, def in IS.BUSKER.spots do
		local cf = findSpot(def.x, def.n, Vector3.new(8, 6, 7), true, false)
		if cf then
			-- performer faces inland (the promenade crowd): flip the frame
			buildBusker(def, cf * CFrame.Angles(0, math.pi, 0))
		end
	end
	-- beach: rental stand + friends, sandcastle spot, photo frame
	do
		local def = IS.RENTAL.stand
		local cf = findSpot(def.x, def.n, Vector3.new(6, 4, 4), false, true)
		if cf then
			standCF = cf
			buildRentalStand(cf)
		end
		for _, fd in IS.RENTAL.friends do
			local fcf = findSpot(fd.x, fd.n, Vector3.new(2, 4, 2), true, true)
			if fcf then
				local rig = buildRig(f, "비치볼 친구 " .. fd.id, fcf, fd.look, "beach", fd.id)
				if rig then
					rig:SetAttribute(IS.Attr.Id, fd.id)
					table.insert(friends, { id = fd.id, model = rig, cf = fcf, busy = false })
				end
			end
		end
		-- the two friends face each other
		if #friends == 2 then
			for i, fr in friends do
				local other = friends[3 - i]
				local p0 = fr.cf.Position
				local p1 = Vector3.new(other.cf.Position.X, p0.Y, other.cf.Position.Z)
				fr.cf = CFrame.lookAt(p0, p1)
				pcall(function()
					fr.model:PivotTo(fr.cf * CFrame.new(0, 3, 0))
				end)
			end
		end
	end
	do
		local def = IS.SAND.spot
		local cf = findSpot(def.x, def.n, Vector3.new(6, 4, 6), false, true)
		if cf then
			sandSpotCF = cf
			buildSandSpot(cf)
		end
	end
	do
		local def = IS.PHOTO_FRAME
		local cf = findSpot(def.x, def.n, Vector3.new(10, 12, 3), false, true)
		if cf then
			-- LookVector inland: the photographer stands inland, the bridge (south) behind the frame
			buildPhotoFrame(cf * CFrame.Angles(0, math.pi, 0))
		end
	end
	-- fishing spots + the market stall
	for i, cf in fishSpots() do
		buildFishSpot("fish_" .. i, cf)
	end
	do
		local def = IS.FISHING.market
		local cf = findSpotWorld(def.near, Vector3.new(8, 8, 4.5), Vector3.new(0, 0, 1), 26)
		if cf then
			buildFishMarket(cf)
		end
	end
	makeBalls()
	tagExisting()
end

---------------------------------------------------------------------------------------------------
-- Driver loops
---------------------------------------------------------------------------------------------------
local function tickPlayers(dt: number)
	local now = os.clock()
	local clock = clockNow()
	local day = clock >= 6.5 and clock < 18
	for player, s in states do
		if player.Parent ~= Players then
			continue
		end
		local char, humanoid, root = alive(player)
		if not char or not humanoid or not root then
			continue
		end
		-- held prop expiry
		if s.heldPart and s.heldUntil > 0 and now > s.heldUntil then
			local id = s.heldId
			clearHeld(player)
			local cur = char:GetAttribute(IS.Attr.Pose)
			if (id == "plush" and (cur == "hold_front" or cur == "hold_one")) then
				char:SetAttribute(IS.Attr.Pose, "")
			end
		end
		-- sunbathing / resting
		local st = s.sit
		if st and humanoid.SeatPart == st.seat then
			local sunbathing = st.mode == "lie" and (st.kind == "towel" or st.kind == "lounger") and day
			if sunbathing then
				local before = s.tan
				s.tan = math.min(1, s.tan + dt * 0.012)
				if math.floor(before * 20) ~= math.floor(s.tan * 20) then
					applyTan(player)
				end
				s.sunGain += dt
				if s.sunGain >= 30 then
					s.sunGain = 0
					ctx.addStats(player, { happiness = 1 }, "☀️ 일광욕 중", false)
				end
			end
			if now - s.restWindow > 3600 then
				s.restWindow = now
				s.restGain = 0
			end
			if now - st.since > 30 and s.restGain < 6 then
				st.since = now
				s.restGain += 0.5
				ctx.addStats(player, { fatigue = -0.5 }, nil, true)
			end
		elseif s.tan > 0 then
			local before = s.tan
			s.tan = math.max(0, s.tan - dt * 0.004)
			if math.floor(before * 20) ~= math.floor(s.tan * 20) or s.tan == 0 then
				applyTan(player)
			end
		end
		-- sit record lost (seat gone, character moved away)
		if st and humanoid.SeatPart ~= st.seat and now - (st.since or now) > 1 then
			endSit(player)
		end
		-- fishing: walked away from the spot
		if s.fish and not near(player, s.fish.spot, 14) then
			handlers.fishStop(player, {})
			fire(player, { kind = "fishEnd" })
		end
		-- claw: abandoned
		if s.claw and now - s.claw.t0 > IS.CLAW.moveSeconds + 25 then
			handlers.clawCancel(player, {})
		end
	end
end

local function tickLifeguard()
	local now = os.clock()
	for player, s in states do
		if player.Parent ~= Players then
			continue
		end
		local _, humanoid, root = alive(player)
		if not humanoid or not root or humanoid.SeatPart then
			s.whistle = 0
			continue
		end
		local pos = root.Position
		local d = Profiles.get(player)
		local sup = d and d.buffs and d.buffs.sup and (d.buffs.sup.untilT or 0) > os.time()
		if not sup and IS.pastBuoys(pos) then
			if s.whistle == 0 then
				s.whistle = now
				fire(player, { kind = "whistle", stage = 1 })
			elseif now - s.whistle > 4.5 then
				s.whistle = now + 6 -- grace after the teleport
				fire(player, { kind = "whistle", stage = 2 })
				local target = IS.backInside(pos)
				task.spawn(function()
					ctx.allowTeleport(player, 6)
					pcall(Util.fade, player, true, 0.35, "안전요원이 안쪽으로 데려다줬어요 🛟")
					local look = Vector3.new(0, 0, 1)
					pcall(Util.placeCharacter, player, CFrame.lookAt(target, target + look))
					task.wait(0.25)
					pcall(Util.fade, player, false, 0.5)
				end)
			end
		elseif s.whistle ~= 0 and now > s.whistle + 2 then
			s.whistle = 0
		end
	end
end

local function tickWorld()
	tickBalls()
	local now = os.clock()
	for i = #castles, 1, -1 do
		if now - castles[i].t > IS.SAND.lifetime then
			removeCastle(i)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Feature hooks
---------------------------------------------------------------------------------------------------
local function remote(name: string, className: string): any
	local folder = ReplicatedStorage:FindFirstChild(G.RemotesFolder)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = G.RemotesFolder
		folder.Parent = ReplicatedStorage
	end
	local r = folder:FindFirstChild(name)
	if r and r.ClassName ~= className then
		r:Destroy()
		r = nil
	end
	if not r then
		r = Instance.new(className)
		r.Name = name
		r.Parent = folder
	end
	return r
end

function Interact.init(context: any)
	ctx = context
	G = context.G
	Util = context.Util
	Profiles = context.Profiles
	IS = require(ReplicatedStorage:WaitForChild("GwangalliInteractShared", 20) :: ModuleScript)
	do
		local m = ReplicatedStorage:FindFirstChild("GwangalliAnim")
		if m and m:IsA("ModuleScript") then
			local ok, res = pcall(require, m)
			if ok then
				Anim = res
			end
		end
		local l = ReplicatedStorage:FindFirstChild("GwangalliNPCLooks")
		if l and l:IsA("ModuleScript") then
			local ok, res = pcall(require, l)
			if ok then
				Looks = res
			end
		end
	end

	local old = Workspace:FindFirstChild(IS.FOLDER)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = IS.FOLDER
	folder.Parent = Workspace
	propFolder = folder

	requestFn = remote(IS.Remote.Request, "RemoteFunction")
	eventRe = remote(IS.Remote.Event, "RemoteEvent");
	(requestFn :: RemoteFunction).OnServerInvoke = function(player: Player, op: any, payload: any)
		return handle(player, op, payload)
	end;
	(eventRe :: RemoteEvent).OnServerEvent:Connect(function(player: Player, op: any, payload: any)
		handle(player, op, payload)
	end)

	local okStore, st = pcall(function()
		return DataStoreService:GetDataStore(IS.STORE)
	end)
	if okStore and st then
		store = st
		storeEnabled = true
	end

	ctx.interact = {
		isBusy = function(player: Player): boolean
			return busyOf(player) ~= ""
		end,
		standUp = standUp,
		setHeld = setHeld,
		clearHeld = clearHeld,
		sitOn = sitOn,
	}

	task.spawn(function()
		local ok, err = pcall(scanSittables)
		if not ok then
			warn("[Interact] sittable scan failed: " .. tostring(err))
		end
		local ok2, err2 = pcall(buildWorld)
		if not ok2 then
			warn("[Interact] world setup failed: " .. tostring(err2))
		end
	end)

	-- 10 Hz ball physics checks only while something flies
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		if flyingCount <= 0 then
			return
		end
		acc += dt
		if acc >= 0.1 then
			acc = 0
			local ok, err = pcall(stepBalls)
			if not ok then
				warn("[Interact] balls: " .. tostring(err))
			end
		end
	end)
	task.spawn(function()
		local n = 0
		while true do
			task.wait(0.5)
			n += 1
			local ok, err = pcall(tickLifeguard)
			if not ok then
				warn("[Interact] lifeguard: " .. tostring(err))
			end
			if n % 2 == 0 then
				local ok2, err2 = pcall(tickPlayers, 1)
				if not ok2 then
					warn("[Interact] players: " .. tostring(err2))
				end
				local ok3, err3 = pcall(tickWorld)
				if not ok3 then
					warn("[Interact] world: " .. tostring(err3))
				end
			end
			if n % 360 == 0 then
				for player, s in states do
					if s.dirty and player.Parent == Players then
						task.spawn(saveNow, player)
					end
				end
			end
		end
	end)
	game:BindToClose(function()
		for player, s in states do
			if s.dirty and player.Parent == Players then
				pcall(saveNow, player)
			end
		end
	end)
end

function Interact.onLoaded(player: Player)
	local s = S(player)
	if not storeEnabled or not store then
		s.loaded = true
		pushData(player)
		return
	end
	task.spawn(function()
		local ok, raw = pcall(function()
			return store:GetAsync(keyOf(player))
		end)
		if player.Parent ~= Players or states[player] ~= s then
			return
		end
		if ok then
			local d = sanitize(raw)
			-- anything earned while loading is kept
			for id in s.data.photos do
				d.photos[id] = true
			end
			for id, c in s.data.dex do
				d.dex[id] = math.max(d.dex[id] or 0, c)
			end
			for _, f in s.data.cooler do
				if #d.cooler < IS.FISHING.cooler then
					table.insert(d.cooler, f)
				end
			end
			d.fireworks = math.min(IS.FIREWORKS.maxOwned, d.fireworks + s.data.fireworks)
			s.data = d
			s.canSave = true
		else
			warn("[Interact] load failed for " .. player.Name .. ": " .. tostring(raw))
			s.canSave = false
		end
		s.loaded = true
		pushData(player)
	end)
end

function Interact.onCharacter(player: Player, character: Model)
	local s = S(player)
	endSit(player)
	s.heldPart = nil
	s.heldId = nil
	s.heldUntil = 0
	s.fish = nil
	s.claw = nil
	s.build = nil
	s.tanBase = nil
	s.whistle = 0
	if s.ball then
		local i = indexOf(s.ball)
		if i > 0 then
			returnBall(i)
		end
	end
	setBusy(player, nil)
	character:SetAttribute(IS.Attr.Pose, "")
	character:SetAttribute(IS.Attr.Held, "")
	if s.tan > 0 then
		task.delay(2, function()
			if player.Character == character then
				applyTan(player)
			end
		end)
	end
end

function Interact.onLeave(player: Player)
	local s = states[player]
	if not s then
		return
	end
	endSit(player)
	if s.ball then
		local i = indexOf(s.ball)
		if i > 0 then
			returnBall(i)
		end
	end
	for i, rec in balls do
		if rec.renter == player then
			rec.renter = nil
		end
		if rec.thrower == player then
			rec.thrower = nil
		end
		local _ = i
	end
	if s.seat then
		s.seat:Destroy()
		s.seat = nil
	end
	if s.dirty then
		saveNow(player)
	end
	states[player] = nil
end

-- Test hooks (sim scenarios)
Interact._states = states
Interact._balls = balls
Interact._castles = castles
Interact._scan = scanStats
Interact._handle = function(player: Player, op: string, payload: any)
	return handle(player, op, payload)
end

return Interact
