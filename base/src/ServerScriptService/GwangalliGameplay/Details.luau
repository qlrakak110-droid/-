-- GwangalliGameplay/Details (owner: korean_details): server side of the "이것도 만들었다고?" Korean-life
-- details (docs/DETAILS.md; data + texts in ReplicatedStorage.GwangalliDetailsShared). Feature module
-- loaded by GwangalliGameplay.server.luau (FEATURE_MODULES): init(ctx) / onLoaded / onCharacter /
-- onLeave.
--
-- What the server owns (everything else is client-only decoration):
--   * 네컷사진관: the booth model (runtime parts), sessions (owner pays, friends join), the 4-shot timeline
--     (attributes on the booth model; every client poses / renders locally), the album (10 strips,
--     own DataStore D.DATASTORE since Profiles keeps only the keys it knows)
--   * 갈매기 매점: buying 새우과자 (cash -> bank fallback), pieces, the "hold it up" timestamp the
--     clients animate the swooping gulls from (character attributes GwFeedAt / GwFeedSeed)
--   * 배달: orders paid from the bank, the timeline (접수 -> 조리 -> 배달 -> 도착 -> 문 앞 보관), the ride
--     path to the home entrance (one Configuration per ride under ReplicatedStorage.GwangalliDetails.
--     Rides: Path / Start / Speed / State ... ; clients build and animate the rider), taking the bag,
--     eating it at home (ctx.addStats + ctx.health.rest)
--   * 불꽃축제: in-game weekday (workspace GwWeekday), the schedule (Saturday 17:00 in-game), the show
--     start / seed (clients play the deterministic choreography D.festivalCues(seed)), beach mats
--   * 동전 / 지갑: spawns near players on sidewalks (GwangalliNav pedestrian edges), rate-limited pick-ups,
--     the lost-wallet quest returned at the 관광안내소 분실물 센터
--   * 버스킹: 3 stages (found in the map), performer state, instrument + case props, NPC tips scaled by
--     the reported rhythm accuracy (capped), player tips (cash -> cash, rate-limited)
-- Remotes: ReplicatedStorage.GwangalliDetails { DetailsRequest (RemoteFunction), DetailsEvent }.
-- Test hook: ServerStorage.GwangalliDetailsAPI (BindableFunction: op, player, ...) for the simulator.

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Details = {}

local ctx: any = nil
local G: any = nil
local D: any = nil
local Util: any = nil
local Profiles: any = nil
local Clock: any = nil
local Nav: any = nil
local Looks: any = nil

local folder: Folder = nil :: any
local ridesFolder: Folder = nil :: any
local world: Folder = nil :: any
local reqFn: RemoteFunction = nil :: any
local evRe: RemoteEvent = nil :: any
local store: any = nil

local rng = Random.new()

---------------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------------
local function now(): number
	return workspace:GetServerTimeNow()
end

local function fire(player: Player, payload: any)
	if player.Parent == Players then
		evRe:FireClient(player, payload)
	end
end

local function fireNear(pos: Vector3, radius: number, payload: any)
	for _, p in Players:GetPlayers() do
		local rp = Util.rootPosition(p)
		if rp and (rp - pos).Magnitude <= radius then
			evRe:FireClient(p, payload)
		end
	end
end

local function fireAll(payload: any)
	evRe:FireAllClients(payload)
end

local function notify(player: Player, kind: string, title: string, body: string?)
	pcall(ctx.notify, player, kind, title, body or "")
end

local function res(ok: boolean, code: string, msg: string?, extra: { [string]: any }?): any
	local r: { [string]: any } = { ok = ok, code = code, message = msg or "" }
	if extra then
		for k, v in extra do
			r[k] = v
		end
	end
	return r
end

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, props: { [string]: any }?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function deco(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, props: { [string]: any }?): BasePart
	local p = part(parent, name, size, cf, color, material, props)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

local function cyl(parent: Instance, name: string, length: number, dia: number, cf: CFrame, color: Color3, material: Enum.Material?, solid: boolean?): BasePart
	local p = (if solid then part else deco)(parent, name, Vector3.new(length, dia, dia), cf, color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	local p = deco(parent, name, size, cf, color, material)
	p.Shape = Enum.PartType.Ball
	return p
end

-- A SurfaceGui with lines of text on one face of `p`.
local function signText(p: BasePart, face: Enum.NormalId, lines: { { text: string, size: number, color: Color3, font: Enum.Font? } }, bg: Color3?, ppu: number?)
	local sg = Instance.new("SurfaceGui")
	sg.Name = "Sign"
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = ppu or 40
	sg.LightInfluence = 0
	sg.MaxDistance = 180
	sg.Parent = p
	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = if bg then 0 else 1
	root.BackgroundColor3 = bg or Color3.new()
	root.BorderSizePixel = 0
	root.Parent = sg
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = root
	local total = 0
	for _, l in lines do
		total += l.size
	end
	for i, l in lines do
		local t = Instance.new("TextLabel")
		t.Name = "Line" .. i
		t.LayoutOrder = i
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, l.size / math.max(total, 1) * 0.92)
		t.Text = l.text
		t.TextScaled = true
		t.Font = l.font or Enum.Font.GothamBold
		t.TextColor3 = l.color
		t.Parent = root
	end
	return sg
end

local function prompt(parentPart: BasePart, action: string, object: string, hold: number?, dist: number?): ProximityPrompt
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = action
	pp.ObjectText = object
	pp.HoldDuration = hold or 0.25
	pp.MaxActivationDistance = dist or 9
	pp.RequiresLineOfSight = false
	pp.Parent = parentPart
	return pp
end

local function character(player: Player): (Model?, Humanoid?, BasePart?)
	return Util.alive(player)
end

local function handOf(char: Model, left: boolean?): BasePart?
	local names = if left then { "LeftHand", "Left Arm", "LeftLowerArm", "UpperTorso", "Torso", "HumanoidRootPart" } else { "RightHand", "Right Arm", "RightLowerArm", "UpperTorso", "Torso", "HumanoidRootPart" }
	for _, n in names do
		local p = char:FindFirstChild(n)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	return nil
end

-- Welds a small prop model (built at the origin) to a body part. Returns the model.
local function weldProp(char: Model, name: string, build: (Model) -> (), anchorPart: BasePart, offset: CFrame): Model
	local old = char:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local m = Instance.new("Model")
	m.Name = name
	build(m)
	local primary: BasePart? = nil
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			if not primary then
				primary = d
			end
		end
	end
	if primary then
		m.PrimaryPart = primary
		local base = anchorPart.CFrame * offset
		-- build() placed parts relative to the origin: move them to the hand, then weld each to it
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.CFrame = base * d.CFrame
				local w = Instance.new("WeldConstraint")
				w.Part0 = anchorPart
				w.Part1 = d
				w.Parent = d
			end
		end
	end
	m.Parent = char
	return m
end

local function removeProp(char: Model?, name: string)
	if char then
		local m = char:FindFirstChild(name)
		if m then
			m:Destroy()
		end
	end
end

local function clockNow(): number
	if Clock then
		local ok, c = pcall(Clock.clockNow)
		if ok and type(c) == "number" then
			return c
		end
	end
	return game:GetService("Lighting").ClockTime
end

local function clockRate(): number
	local r = workspace:GetAttribute("GwangalliClockRate")
	if type(r) == "number" and r > 0 then
		return r
	end
	return 1 / 60
end

local function displayName(p: Player): string
	local n = p.DisplayName
	if type(n) ~= "string" or n == "" then
		n = p.Name
	end
	return n
end

---------------------------------------------------------------------------------------------------
-- Per-player state + persistence (own DataStore)
---------------------------------------------------------------------------------------------------
type PS = {
	data: any,
	loaded: boolean,
	dirty: boolean,
	lastSave: number,
	snack: number,
	lastFeed: number,
	joyDay: number,
	joy: number,
	nextCoin: number,
	coinDay: number,
	coins: number,
	lastCoin: number,
	nextWallet: number,
	walletDay: number,
	wallets: number,
	wallet: any?,
	order: any?,
	food: string?,
	lastEat: number,
	boothCooldown: number,
	buskCooldown: number,
	tips: { [number]: number },
	lastTip: number,
	bucket: number,
	bucketT: number,
}
local states: { [Player]: PS } = {}

local function defaultData(): any
	return { v = 1, strips = {}, best = 0, returned = 0, coinsTotal = 0, feeds = 0, orders = 0, shows = 0 }
end

local function S(player: Player): PS
	local s = states[player]
	if not s then
		local t = os.clock()
		s = {
			data = defaultData(),
			loaded = false,
			dirty = false,
			lastSave = t,
			snack = 0,
			lastFeed = -100,
			joyDay = -1,
			joy = 0,
			nextCoin = t + rng:NextNumber(12, 30),
			coinDay = -1,
			coins = 0,
			lastCoin = -100,
			nextWallet = t + rng:NextNumber(90, 200),
			walletDay = -1,
			wallets = 0,
			wallet = nil,
			order = nil,
			food = nil,
			lastEat = -100,
			boothCooldown = 0,
			buskCooldown = 0,
			tips = {},
			lastTip = -100,
			bucket = 10,
			bucketT = t,
		}
		states[player] = s
	end
	return s
end

local function sanitizeStrip(st: any): any?
	if type(st) ~= "table" then
		return nil
	end
	local frame = if type(st.frame) == "string" and D.FRAME_BY_ID[st.frame] then st.frame else "white"
	local seq = if type(st.seq) == "number" and D.POSE_SEQS[st.seq] then st.seq else 1
	local members = {}
	if type(st.members) == "table" then
		for _, m in st.members do
			if type(m) == "table" and type(m.id) == "number" and #members < D.BOOTH.maxMembers then
				table.insert(members, {
					id = math.floor(m.id),
					name = if type(m.name) == "string" then string.sub(m.name, 1, 40) else "친구",
					prop = if type(m.prop) == "string" and D.PROP_BY_ID[m.prop] then m.prop else "none",
				})
			end
		end
	end
	return {
		id = if type(st.id) == "string" then string.sub(st.id, 1, 40) else ("s" .. tostring(math.random(1, 1e9))),
		t = if type(st.t) == "number" then st.t else os.time(),
		frame = frame,
		seq = seq,
		place = if type(st.place) == "string" then string.sub(st.place, 1, 60) else D.BOOTH.spots[1].name,
		clock = if type(st.clock) == "string" then string.sub(st.clock, 1, 8) else "",
		members = members,
	}
end

local function sanitizeData(raw: any): any
	local d = defaultData()
	if type(raw) ~= "table" then
		return d
	end
	if type(raw.strips) == "table" then
		for _, st in raw.strips do
			local s = sanitizeStrip(st)
			if s then
				table.insert(d.strips, s)
			end
		end
		while #d.strips > D.BOOTH.albumMax do
			table.remove(d.strips, 1)
		end
	end
	for _, k in { "best", "returned", "coinsTotal", "feeds", "orders", "shows" } do
		if type(raw[k]) == "number" and raw[k] == raw[k] then
			d[k] = math.max(0, math.floor(raw[k]))
		end
	end
	return d
end

local function persistent(player: Player): boolean
	if Profiles and type(Profiles.persistent) == "function" then
		local ok, r = pcall(Profiles.persistent, player)
		return ok and r == true
	end
	return true
end

local function loadData(player: Player)
	local s = S(player)
	if not store or not persistent(player) then
		s.loaded = true
		return
	end
	local ok, raw = pcall(function()
		return store:GetAsync(D.KEY .. tostring(player.UserId))
	end)
	if player.Parent ~= Players then
		return
	end
	if ok then
		s.data = sanitizeData(raw)
	else
		warn("[Details] load failed for " .. player.Name .. ": " .. tostring(raw))
	end
	s.loaded = true
end

local function saveData(player: Player): boolean
	local s = states[player]
	if not s or not s.loaded or not store or not persistent(player) then
		if s then
			s.dirty = false
		end
		return false
	end
	local snapshot = sanitizeData(s.data)
	s.dirty = false
	s.lastSave = os.clock()
	local ok, err = pcall(function()
		store:SetAsync(D.KEY .. tostring(player.UserId), snapshot)
	end)
	if not ok then
		s.dirty = true
		warn("[Details] save failed for " .. player.Name .. ": " .. tostring(err))
	end
	return ok
end

-- own token bucket for DetailsRequest (8 / s, burst 14)
local function allow(player: Player): boolean
	local s = S(player)
	local t = os.clock()
	s.bucket = math.min(14, s.bucket + (t - s.bucketT) * 8)
	s.bucketT = t
	if s.bucket < 1 then
		return false
	end
	s.bucket -= 1
	return true
end

local function gameDay(): number
	local v = workspace:GetAttribute(D.WS.DayIndex)
	return if type(v) == "number" then v else 0
end

---------------------------------------------------------------------------------------------------
-- Navigation data (sidewalk spawn points) -- GwangalliNav, decoded lazily
---------------------------------------------------------------------------------------------------
type Seg = { a: Vector3, b: Vector3, w: number }
local segGrid: { [number]: { Seg } }? = nil
local SEG_CELL = 64
local function gkey(x: number, z: number): number
	return (math.floor(x / SEG_CELL) + 512) * 2048 + (math.floor(z / SEG_CELL) + 512)
end

local function buildSegGrid()
	if segGrid then
		return
	end
	segGrid = {}
	if not Nav or type(Nav.ped) ~= "table" then
		return
	end
	local P = Nav.ped
	local kindName: { [number]: string } = {}
	if type(Nav.KIND) == "table" then
		for k, v in Nav.KIND do
			if type(k) == "string" and type(v) == "number" then
				kindName[v] = k
			elseif type(k) == "number" and type(v) == "string" then
				kindName[k] = v
			end
		end
	end
	local okKinds = { walk = true, prom = true, plaza = true, park = true, deck = true }
	local nE = math.floor(#P.edges / 4)
	for e = 0, nE - 1 do
		local a, b, w, kind = P.edges[e * 4 + 1], P.edges[e * 4 + 2], P.edges[e * 4 + 3], P.edges[e * 4 + 4]
		local kn = kindName[kind]
		if kn == nil or okKinds[kn] then
			local pa = Vector3.new(P.pos[(a - 1) * 3 + 1], P.pos[(a - 1) * 3 + 2], P.pos[(a - 1) * 3 + 3])
			local pb = Vector3.new(P.pos[(b - 1) * 3 + 1], P.pos[(b - 1) * 3 + 2], P.pos[(b - 1) * 3 + 3])
			if (pb - pa).Magnitude > 3 and math.abs(pb.Y - pa.Y) < 2 and pa.Y > 2 then
				local mid = (pa + pb) / 2
				local key = gkey(mid.X, mid.Z)
				local cell = (segGrid :: any)[key]
				if not cell then
					cell = {}
					(segGrid :: any)[key] = cell
				end
				table.insert(cell, { a = pa, b = pb, w = w or 3 })
			end
		end
	end
end

-- A random sidewalk point between rMin and rMax studs from `pos` (or nil).
local function sidewalkPoint(pos: Vector3, rMin: number, rMax: number): Vector3?
	buildSegGrid()
	local grid = segGrid
	if not grid or next(grid) == nil then
		return nil
	end
	local cands = {}
	local c = math.ceil(rMax / SEG_CELL)
	local cx, cz = math.floor(pos.X / SEG_CELL), math.floor(pos.Z / SEG_CELL)
	for dx = -c, c do
		for dz = -c, c do
			local cell = grid[(cx + dx + 512) * 2048 + (cz + dz + 512)]
			if cell then
				for _, sg in cell do
					local mid = (sg.a + sg.b) / 2
					local d = (Vector3.new(mid.X, pos.Y, mid.Z) - pos).Magnitude
					if d >= rMin and d <= rMax then
						table.insert(cands, sg)
					end
				end
			end
		end
	end
	if #cands == 0 then
		return nil
	end
	local sg = cands[rng:NextInteger(1, #cands)]
	local t = rng:NextNumber(0.15, 0.85)
	local p = sg.a:Lerp(sg.b, t)
	local dir = (sg.b - sg.a)
	local side = Vector3.new(-dir.Z, 0, dir.X)
	if side.Magnitude > 0.01 then
		side = side.Unit
		p += side * rng:NextNumber(-1, 1) * math.max(0, sg.w / 2 - 0.8)
	end
	return p
end

---------------------------------------------------------------------------------------------------
-- (1) 네컷사진관
---------------------------------------------------------------------------------------------------
type Booth = {
	id: string,
	model: Model,
	frame: CFrame,
	spot: any,
	prompt: ProximityPrompt,
	state: string,
	owner: Player?,
	members: { Player },
	props: { [Player]: string },
	frameId: string,
	seq: number,
	setupUntil: number,
	shotStart: number,
	serial: number,
	paid: number,
}
local booths: { [string]: Booth } = {}

local BW, BD, BH = 10, 8, 8.4

local function boothMarks(b: Booth): { CFrame }
	local out = {}
	local xs = { -0.9, 0.9, -2.6, 2.6 }
	for i = 1, D.BOOTH.maxMembers do
		local x = xs[i] or 0
		-- characters face the camera at the front (the booth frame's LookVector)
		out[i] = b.frame * CFrame.new(x, 3.1, 1.5)
	end
	return out
end

local function buildBooth(spot: any): Booth
	local base = CFrame.new(spot.x, spot.y, spot.z) * CFrame.Angles(0, math.rad(spot.yaw or 0), 0)
	local m = Instance.new("Model")
	m.Name = "네컷사진관 (" .. spot.id .. ")"
	local function L(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x, y, z)
	end
	local white = Color3.fromRGB(246, 244, 246)
	local ink = Color3.fromRGB(28, 28, 34)
	local pink = Color3.fromRGB(255, 108, 156)
	part(m, "Floor", Vector3.new(BW, 0.4, BD), L(0, 0.2, 0), Color3.fromRGB(52, 50, 58), Enum.Material.SmoothPlastic)
	deco(m, "FloorSticker", Vector3.new(BW - 1.2, 0.02, BD - 1.2), L(0, 0.41, 0.2), Color3.fromRGB(255, 226, 236), Enum.Material.SmoothPlastic)
	-- backdrop (the photo background) + side walls with an outside accent stripe
	local backdrop = part(m, "Backdrop", Vector3.new(BW, BH, 0.4), L(0, BH / 2, BD / 2 - 0.2), Color3.fromRGB(252, 238, 244), Enum.Material.SmoothPlastic)
	backdrop:SetAttribute("BoothBackdrop", true)
	part(m, "WallL", Vector3.new(0.4, BH, BD), L(-BW / 2 + 0.2, BH / 2, 0), white, Enum.Material.SmoothPlastic)
	part(m, "WallR", Vector3.new(0.4, BH, BD), L(BW / 2 - 0.2, BH / 2, 0), white, Enum.Material.SmoothPlastic)
	deco(m, "StripeL", Vector3.new(0.06, 0.6, BD), L(-BW / 2 - 0.03, BH - 2.4, 0), pink, Enum.Material.Neon)
	deco(m, "StripeR", Vector3.new(0.06, 0.6, BD), L(BW / 2 + 0.03, BH - 2.4, 0), pink, Enum.Material.Neon)
	part(m, "Roof", Vector3.new(BW + 0.6, 0.5, BD + 0.6), L(0, BH + 0.25, 0), ink, Enum.Material.SmoothPlastic)
	-- entrance pillars + sign fascia
	local openW = BW - 4.4
	part(m, "PillarL", Vector3.new(2.2, BH - 1.8, 0.4), L(-(BW / 2 - 1.1), (BH - 1.8) / 2, -BD / 2 + 0.2), white, Enum.Material.SmoothPlastic)
	part(m, "PillarR", Vector3.new(2.2, BH - 1.8, 0.4), L(BW / 2 - 1.1, (BH - 1.8) / 2, -BD / 2 + 0.2), white, Enum.Material.SmoothPlastic)
	local fascia = part(m, "Fascia", Vector3.new(BW + 0.2, 1.8, 0.5), L(0, BH - 0.9, -BD / 2 + 0.25), ink, Enum.Material.SmoothPlastic)
	signText(fascia, Enum.NormalId.Front, {
		{ text = D.BOOTH.name, size = 3, color = Color3.fromRGB(255, 255, 255), font = Enum.Font.GothamBlack },
		{ text = D.BOOTH.sub, size = 1.2, color = Color3.fromRGB(255, 150, 190) },
	}, nil, 50)
	fascia:AddTag("NightGlow")
	-- curtain (two halves; the clients slide them open / closed from the State attribute)
	cyl(m, "CurtainRod", openW + 0.6, 0.14, L(0, BH - 1.95, -BD / 2 + 0.7) * CFrame.Angles(0, 0, 0), Color3.fromRGB(200, 200, 205), Enum.Material.Metal)
	for i, sx in { -1, 1 } do
		local c = deco(m, "Curtain" .. i, Vector3.new(openW / 2, BH - 2.2, 0.12), L(sx * openW / 4, (BH - 2.2) / 2 + 0.25, -BD / 2 + 0.7), pink, Enum.Material.Fabric)
		c:SetAttribute("Side", sx)
		c:SetAttribute("ClosedX", sx * openW / 4)
		c:SetAttribute("OpenX", sx * (openW / 2 - 0.35))
		c.Size = Vector3.new(0.6, BH - 2.2, 0.16)
		c.CFrame = L(sx * (openW / 2 - 0.35), (BH - 2.2) / 2 + 0.25, -BD / 2 + 0.7)
	end
	-- the camera unit hanging inside the entrance, facing the backdrop
	local camBox = part(m, "CameraUnit", Vector3.new(3.4, 1.7, 0.9), L(0, BH - 2.9, -BD / 2 + 1.25), ink, Enum.Material.SmoothPlastic, { CanCollide = false })
	cyl(m, "Lens", 0.5, 0.7, L(0, BH - 2.85, -BD / 2 + 1.75) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(14, 14, 18), Enum.Material.Glass)
	for k = 0, 9 do
		local a = k / 10 * math.pi * 2
		local ring = deco(m, "RingLight", Vector3.new(0.28, 0.28, 0.12), L(math.cos(a) * 0.75, BH - 2.85 + math.sin(a) * 0.75, -BD / 2 + 1.72), Color3.fromRGB(255, 246, 236), Enum.Material.Neon)
		ring:AddTag("NeonTube")
	end
	local screen = deco(m, "Screen", Vector3.new(2.6, 1.3, 0.06), L(0, BH - 4.3, -BD / 2 + 1.72), Color3.fromRGB(10, 12, 20), Enum.Material.SmoothPlastic)
	local ssg = Instance.new("SurfaceGui")
	ssg.Name = "BoothScreen"
	ssg.Face = Enum.NormalId.Back
	ssg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	ssg.PixelsPerStud = 60
	ssg.LightInfluence = 0
	ssg.MaxDistance = 60
	ssg.Parent = screen
	local st = Instance.new("TextLabel")
	st.Name = "Text"
	st.Size = UDim2.fromScale(1, 1)
	st.BackgroundColor3 = Color3.fromRGB(16, 18, 30)
	st.BorderSizePixel = 0
	st.TextScaled = true
	st.Font = Enum.Font.GothamBold
	st.TextColor3 = Color3.fromRGB(255, 255, 255)
	st.Text = "📸 4컷 · " .. D.won(D.BOOTH.price)
	st.Parent = ssg
	local light = Instance.new("PointLight")
	light.Brightness = 1.4
	light.Range = 13
	light.Color = Color3.fromRGB(255, 240, 230)
	light.Shadows = false
	light.Parent = camBox
	light:AddTag("InteriorLight")
	light:SetAttribute("AlwaysOn", true)
	-- props box on the left wall (decor: headbands, glasses, crown)
	part(m, "PropsShelf", Vector3.new(0.9, 0.2, 2.8), L(-BW / 2 + 0.85, 3.7, 1.6), Color3.fromRGB(240, 200, 214), Enum.Material.Wood, { CanCollide = false })
	local box = deco(m, "PropsBox", Vector3.new(0.8, 0.6, 1.2), L(-BW / 2 + 0.85, 4.1, 1.0), Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic)
	signText(box, Enum.NormalId.Right, { { text = "PROPS", size = 1, color = pink } }, nil, 60)
	deco(m, "Prop_CatEarL", Vector3.new(0.3, 0.35, 0.12), L(-BW / 2 + 0.85, 4.05, 2.1) * CFrame.Angles(0, 0, math.rad(20)), Color3.fromRGB(30, 30, 34), Enum.Material.SmoothPlastic)
	deco(m, "Prop_CatEarR", Vector3.new(0.3, 0.35, 0.12), L(-BW / 2 + 0.85, 4.05, 2.5) * CFrame.Angles(0, 0, math.rad(-20)), Color3.fromRGB(30, 30, 34), Enum.Material.SmoothPlastic)
	deco(m, "Prop_Crown", Vector3.new(0.5, 0.3, 0.5), L(-BW / 2 + 0.85, 3.95, 2.9), Color3.fromRGB(255, 206, 70), Enum.Material.Metal)
	cyl(m, "Prop_Glasses", 0.08, 0.3, L(-BW / 2 + 0.85, 3.85, 0.4) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(255, 80, 140), Enum.Material.SmoothPlastic)
	-- standing marks
	local tmp: any = { frame = base }
	for i, cf in boothMarks(tmp) do
		local mark = deco(m, "Mark" .. i, Vector3.new(0.04, 1.4, 1.4), CFrame.new(cf.Position.X, spot.y + 0.43, cf.Position.Z) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 160, 196), Enum.Material.SmoothPlastic)
		mark.Shape = Enum.PartType.Cylinder
	end
	-- outside: sample strips poster on the left pillar, OPEN neon, queue sticker
	local poster = deco(m, "SamplePoster", Vector3.new(1.7, 4.4, 0.06), L(-(BW / 2 - 1.1), 3.6, -BD / 2 - 0.03), Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic)
	do
		local sg = Instance.new("SurfaceGui")
		sg.Name = "Samples"
		sg.Face = Enum.NormalId.Front
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 50
		sg.LightInfluence = 0.3
		sg.MaxDistance = 90
		sg.Parent = poster
		local lay = Instance.new("UIListLayout")
		lay.Padding = UDim.new(0, 6)
		lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
		lay.SortOrder = Enum.SortOrder.LayoutOrder
		lay.Parent = sg
		local cols = { { 255, 196, 214 }, { 178, 222, 255 }, { 22, 22, 26 }, { 214, 200, 255 } }
		for i, c in cols do
			local f = Instance.new("Frame")
			f.LayoutOrder = i
			f.Size = UDim2.new(0.8, 0, 0.22, -6)
			f.BackgroundColor3 = rgb(c)
			f.BorderSizePixel = 0
			f.Parent = sg
			local inner = Instance.new("Frame")
			inner.AnchorPoint = Vector2.new(0.5, 0.5)
			inner.Position = UDim2.fromScale(0.5, 0.5)
			inner.Size = UDim2.fromScale(0.82, 0.78)
			inner.BackgroundColor3 = Color3.fromRGB(120 + i * 20, 160, 200 - i * 15)
			inner.BorderSizePixel = 0
			inner.Parent = f
		end
	end
	local open = deco(m, "OpenSign", Vector3.new(1.8, 0.5, 0.08), L(BW / 2 - 1.1, BH - 2.6, -BD / 2 - 0.05), Color3.fromRGB(255, 120, 170), Enum.Material.Neon)
	open:AddTag("NeonTube")
	signText(open, Enum.NormalId.Front, { { text = "OPEN 24H", size = 1, color = Color3.fromRGB(255, 255, 255) } }, nil, 60)
	deco(m, "QueueSticker", Vector3.new(3.2, 0.02, 1.2), L(0, 0.02, -BD / 2 - 2.2), Color3.fromRGB(255, 196, 214), Enum.Material.SmoothPlastic)
	local pp = part(m, "PromptPart", Vector3.new(2, 4, 1), L(0, 2.5, -BD / 2 - 0.9), Color3.new(), Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	local pr = prompt(pp, "네컷 찍기", D.BOOTH.name .. " · " .. D.won(D.BOOTH.price), 0.3, 9)
	m:SetAttribute("BoothId", spot.id)
	m:SetAttribute("State", "idle")
	m:SetAttribute("Members", "")
	m:SetAttribute("Props", "")
	m:SetAttribute("Frame", "white")
	m:SetAttribute("Seq", 1)
	m:SetAttribute("ShotStart", 0)
	m:SetAttribute("Serial", 0)
	m:SetAttribute("Owner", 0)
	m:SetAttribute("PlaceName", spot.name)
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	m.WorldPivot = base
	m.Parent = world
	m:AddTag(D.Tags.Booth)
	return {
		id = spot.id,
		model = m,
		frame = base,
		spot = spot,
		prompt = pr,
		state = "idle",
		owner = nil,
		members = {},
		props = {},
		frameId = "white",
		seq = 1,
		setupUntil = 0,
		shotStart = 0,
		serial = 0,
		paid = 0,
	}
end

local function boothPublish(b: Booth)
	local ids, props = {}, {}
	for _, p in b.members do
		table.insert(ids, tostring(p.UserId))
		table.insert(props, tostring(p.UserId) .. ":" .. (b.props[p] or "none"))
	end
	local m = b.model
	m:SetAttribute("State", b.state)
	m:SetAttribute("Members", table.concat(ids, ","))
	m:SetAttribute("Props", table.concat(props, ","))
	m:SetAttribute("Frame", b.frameId)
	m:SetAttribute("Seq", b.seq)
	m:SetAttribute("ShotStart", b.shotStart)
	m:SetAttribute("Owner", if b.owner then b.owner.UserId else 0)
	b.prompt.Enabled = b.state == "idle" or (b.state == "setup" and #b.members < D.BOOTH.maxMembers)
	b.prompt.ActionText = if b.state == "setup" then "같이 찍기" else "네컷 찍기"
	b.prompt.ObjectText = if b.state == "setup" then (D.BOOTH.name .. " · 친구 무료") else (D.BOOTH.name .. " · " .. D.won(D.BOOTH.price))
end

local function boothView(b: Booth): any
	local members = {}
	for _, p in b.members do
		table.insert(members, { id = p.UserId, name = displayName(p), prop = b.props[p] or "none" })
	end
	return { id = b.id, state = b.state, owner = if b.owner then b.owner.UserId else 0, members = members, frame = b.frameId, seq = b.seq, shotStart = b.shotStart, setupUntil = b.setupUntil, place = b.spot.name }
end

local function boothBroadcast(b: Booth, extra: any?)
	local v = boothView(b)
	for _, p in b.members do
		local payload = { kind = "booth", booth = v }
		if extra then
			for k, val in extra do
				payload[k] = val
			end
		end
		fire(p, payload)
	end
end

local function boothOf(player: Player): Booth?
	for _, b in booths do
		if table.find(b.members, player) then
			return b
		end
	end
	return nil
end

local function placeInBooth(b: Booth, player: Player, index: number)
	local marks = boothMarks(b)
	local cf = marks[index] or marks[1]
	pcall(ctx.allowTeleport, player, 3)
	local char = player.Character
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Sit then
			hum.Sit = false
		end
		pcall(function()
			char:PivotTo(CFrame.lookAt(cf.Position, cf.Position + b.frame.LookVector))
		end)
		char:SetAttribute(D.Char.Booth, b.id)
	end
end

local function boothReset(b: Booth)
	for _, p in b.members do
		local char = p.Character
		if char then
			char:SetAttribute(D.Char.Booth, nil)
		end
	end
	b.state = "idle"
	b.owner = nil
	b.members = {}
	b.props = {}
	b.frameId = "white"
	b.shotStart = 0
	b.paid = 0
	boothPublish(b)
end

local function boothRemove(b: Booth, player: Player, reason: string?)
	local i = table.find(b.members, player)
	if not i then
		return
	end
	table.remove(b.members, i)
	b.props[player] = nil
	local char = player.Character
	if char then
		char:SetAttribute(D.Char.Booth, nil)
	end
	fire(player, { kind = "boothClosed", reason = reason or "left" })
	if b.state == "setup" and b.owner == player then
		-- the payer left before shooting: refund and close the session for everyone
		if b.paid > 0 then
			pcall(ctx.addMoney, player, b.paid, "네컷사진관 환불", true)
		end
		for _, p in table.clone(b.members) do
			fire(p, { kind = "boothClosed", reason = "owner" })
			local c = p.Character
			if c then
				c:SetAttribute(D.Char.Booth, nil)
			end
		end
		boothReset(b)
		return
	end
	if #b.members == 0 then
		boothReset(b)
	else
		boothPublish(b)
		boothBroadcast(b)
	end
end

local function boothFinish(b: Booth)
	local seqIdx = b.seq
	local members = {}
	for _, p in b.members do
		table.insert(members, { id = p.UserId, name = displayName(p), prop = b.props[p] or "none" })
	end
	local strip = sanitizeStrip({
		id = string.format("s%d%04d", os.time(), rng:NextInteger(0, 9999)),
		t = os.time(),
		frame = b.frameId,
		seq = seqIdx,
		place = b.spot.name,
		clock = D.clockText(clockNow()),
		members = members,
	})
	for _, p in b.members do
		local s = S(p)
		table.insert(s.data.strips, strip)
		while #s.data.strips > D.BOOTH.albumMax do
			table.remove(s.data.strips, 1)
		end
		s.dirty = true
		s.boothCooldown = os.clock() + D.BOOTH.cooldown
		fire(p, { kind = "strip", strip = strip, count = #s.data.strips })
		pcall(ctx.addStats, p, { happiness = 4, popularity = if #members > 1 then 1 else 0.5 }, "네컷 인생샷 📸", true)
		local c = p.Character
		if c then
			c:SetAttribute(D.Char.Booth, nil)
		end
	end
	b.state = "done"
	boothPublish(b)
	task.delay(2.5, function()
		if b.state == "done" then
			b.members = {}
			boothReset(b)
		end
	end)
end

local function boothStart(b: Booth)
	if b.state ~= "setup" then
		return
	end
	b.state = "shooting"
	b.serial += 1
	b.seq = rng:NextInteger(1, #D.POSE_SEQS)
	b.shotStart = now() + 1.2
	for i, p in b.members do
		placeInBooth(b, p, i)
	end
	boothPublish(b)
	b.model:SetAttribute("Serial", b.serial)
	boothBroadcast(b, { start = true })
	local per = D.BOOTH.countdown + D.BOOTH.shotGap
	local total = 1.2 + 4 * per + 0.6
	local serial = b.serial
	task.delay(total, function()
		if b.state == "shooting" and b.serial == serial then
			boothFinish(b)
		end
	end)
end

local function boothTriggered(b: Booth, player: Player)
	local s = S(player)
	if boothOf(player) then
		return
	end
	if b.state == "shooting" or b.state == "done" then
		notify(player, "info", "📸 촬영 중이에요", "잠시 후에 이용해 주세요")
		return
	end
	if b.state == "setup" then
		if #b.members >= D.BOOTH.maxMembers then
			notify(player, "info", "📸 자리가 꽉 찼어요", "최대 " .. D.BOOTH.maxMembers .. "명까지 함께 찍을 수 있어요")
			return
		end
		table.insert(b.members, player)
		b.props[player] = "none"
		placeInBooth(b, player, #b.members)
		boothPublish(b)
		boothBroadcast(b, { joined = player.UserId })
		return
	end
	if os.clock() < s.boothCooldown then
		notify(player, "info", "📸 잠깐만요", "사진 인화 중이에요")
		return
	end
	if not ctx.spend(player, D.BOOTH.price, D.BOOTH.name .. " 4컷", false) then
		notify(player, "warn", "잔액이 부족해요", D.BOOTH.name .. " · " .. D.won(D.BOOTH.price))
		return
	end
	b.state = "setup"
	b.owner = player
	b.members = { player }
	b.props = { [player] = "none" }
	b.frameId = "white"
	b.paid = D.BOOTH.price
	b.setupUntil = os.clock() + D.BOOTH.setupTimeout
	b.serial += 1
	placeInBooth(b, player, 1)
	boothPublish(b)
	b.model:SetAttribute("Serial", b.serial)
	boothBroadcast(b, { opened = true })
end

local function boothTick()
	local t = os.clock()
	for _, b in booths do
		if b.state == "setup" then
			-- members who walked away leave the session
			local centre = b.frame.Position
			for _, p in table.clone(b.members) do
				local rp = Util.rootPosition(p)
				if not rp or (rp - centre).Magnitude > D.BOOTH.joinRadius then
					boothRemove(b, p, "far")
				end
			end
			if b.state == "setup" and t >= b.setupUntil then
				boothStart(b)
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- (2) 갈매기 매점 + feeding
---------------------------------------------------------------------------------------------------
local stallPart: BasePart? = nil

local function buildStall()
	local cfg = D.SNACK.stall
	local y = D.sandHeight(cfg.x, cfg.z)
	local base = CFrame.new(cfg.x, y, cfg.z) * CFrame.Angles(0, math.rad(cfg.yaw or 0), 0)
	local m = Instance.new("Model")
	m.Name = D.SNACK.stallName
	local function L(x: number, yy: number, z: number): CFrame
		return base * CFrame.new(x, yy, z)
	end
	local cart = part(m, "Cart", Vector3.new(5, 2.8, 2.4), L(0, 1.9, 0), Color3.fromRGB(240, 240, 236), Enum.Material.SmoothPlastic)
	deco(m, "CartStripe", Vector3.new(5.04, 0.5, 2.44), L(0, 2.6, 0), Color3.fromRGB(40, 150, 220), Enum.Material.SmoothPlastic)
	part(m, "Counter", Vector3.new(5.4, 0.25, 2.8), L(0, 3.4, 0), Color3.fromRGB(196, 150, 100), Enum.Material.WoodPlanks)
	for _, sx in { -1.9, 1.9 } do
		cyl(m, "Wheel", 0.4, 1.0, L(sx, 0.5, -1.25) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(40, 40, 44), Enum.Material.SmoothPlastic)
	end
	cyl(m, "UmbrellaPole", 6.2, 0.18, L(2.2, 5.0, 0.6) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(200, 200, 200), Enum.Material.Metal)
	local umb = deco(m, "Parasol", Vector3.new(0.5, 7, 7), L(2.2, 8.1, 0.6) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 214, 70), Enum.Material.Fabric)
	umb.Shape = Enum.PartType.Cylinder
	deco(m, "ParasolTop", Vector3.new(0.6, 3.6, 3.6), L(2.2, 8.4, 0.6) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 255, 255), Enum.Material.Fabric).Shape = Enum.PartType.Cylinder
	-- snack bags on the counter (orange / red boxes with a shrimp drawing = a tiny pink ball)
	for k = 0, 5 do
		local bx = -2.1 + k * 0.62
		local bag = deco(m, "SnackBag", Vector3.new(0.5, 0.8, 0.22), L(bx, 3.95, -0.5 + (k % 2) * 0.4), if k % 2 == 0 then Color3.fromRGB(255, 120, 40) else Color3.fromRGB(230, 50, 40), Enum.Material.SmoothPlastic)
		bag.CFrame = bag.CFrame * CFrame.Angles(math.rad(-12), 0, 0)
		ball(m, "Shrimp", Vector3.new(0.22, 0.18, 0.06), bag.CFrame * CFrame.new(0, 0.05, -0.13), Color3.fromRGB(255, 170, 160), Enum.Material.SmoothPlastic)
	end
	local sign = deco(m, "Sign", Vector3.new(4.6, 1.3, 0.12), L(-0.3, 5.0, -1.0), Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic)
	signText(sign, Enum.NormalId.Front, {
		{ text = "🐦 " .. D.SNACK.stallName, size = 1.6, color = Color3.fromRGB(30, 110, 190), font = Enum.Font.GothamBlack },
		{ text = D.SNACK.name .. " " .. D.won(D.SNACK.price) .. " · 갈매기 밥 주기", size = 1, color = Color3.fromRGB(230, 70, 40) },
	}, Color3.fromRGB(255, 255, 255), 40)
	cyl(m, "SignPost", 1.2, 0.12, L(-2.4, 4.5, -1.0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(180, 180, 180), Enum.Material.Metal)
	cyl(m, "SignPost", 1.2, 0.12, L(1.8, 4.5, -1.0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(180, 180, 180), Enum.Material.Metal)
	-- a gull figure standing on the parasol
	local g = L(2.2, 8.85, 0.6)
	ball(m, "GullBody", Vector3.new(0.7, 0.55, 1.1), g, Color3.fromRGB(240, 242, 240), Enum.Material.SmoothPlastic)
	ball(m, "GullHead", Vector3.new(0.42, 0.42, 0.42), g * CFrame.new(0, 0.35, -0.5), Color3.fromRGB(245, 245, 245), Enum.Material.SmoothPlastic)
	deco(m, "GullBeak", Vector3.new(0.1, 0.1, 0.3), g * CFrame.new(0, 0.32, -0.8), Color3.fromRGB(236, 190, 56), Enum.Material.SmoothPlastic)
	deco(m, "GullWing", Vector3.new(0.8, 0.12, 0.8), g * CFrame.new(0, 0.12, 0.15), Color3.fromRGB(160, 168, 178), Enum.Material.SmoothPlastic)
	local pp = part(m, "PromptPart", Vector3.new(3, 3, 1), L(0, 2.5, -2.0), Color3.new(), Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	local pr = prompt(pp, D.SNACK.name .. " 사기", D.SNACK.stallName .. " · " .. D.won(D.SNACK.price), 0.25, 9)
	pp:AddTag(D.Tags.Stall)
	m.WorldPivot = base
	m.Parent = world
	stallPart = pp
	pr.Triggered:Connect(function(player: Player)
		local okS, err = pcall(function()
			local s = S(player)
			if s.snack >= 10 then
				notify(player, "info", "🦐 이미 충분해요", "갈매기에게 먼저 나눠 주세요")
				return
			end
			if not ctx.spend(player, D.SNACK.price, D.SNACK.stallName .. " · " .. D.SNACK.name, false) then
				notify(player, "warn", "잔액이 부족해요", D.SNACK.name .. " " .. D.won(D.SNACK.price))
				return
			end
			s.snack = math.min(10, s.snack + D.SNACK.pieces)
			local char = player.Character
			if char then
				char:SetAttribute(D.Char.Snack, s.snack)
				local hand = handOf(char, true)
				if hand then
					weldProp(char, "SnackBag", function(mm)
						local b = Instance.new("Part")
						b.Name = "Bag"
						b.Size = Vector3.new(0.55, 0.85, 0.25)
						b.CFrame = CFrame.new()
						b.Color = Color3.fromRGB(255, 120, 40)
						b.Material = Enum.Material.SmoothPlastic
						b.Parent = mm
						local s2 = Instance.new("Part")
						s2.Name = "Shrimp"
						s2.Shape = Enum.PartType.Ball
						s2.Size = Vector3.new(0.22, 0.2, 0.06)
						s2.CFrame = CFrame.new(0, 0.08, -0.14)
						s2.Color = Color3.fromRGB(255, 170, 160)
						s2.Parent = mm
					end, hand, CFrame.new(0, -0.45, -0.2))
				end
			end
			fire(player, { kind = "snack", pieces = s.snack, bought = true })
		end)
		if not okS then
			warn("[Details] stall: " .. tostring(err))
		end
	end)
end

local function nearSea(pos: Vector3): boolean
	local x0, x1 = D.beachRange()
	if pos.X >= x0 - 40 and pos.X <= x1 + 40 then
		local pz = D.promZ(pos.X)
		return pos.Z <= pz + 50 and pos.Z >= D.edgeZ(pos.X) - 30
	end
	-- 민락항 / 수변공원 quay
	return pos.X < x0 and pos.Z < 0 and pos.Z > -700
end

local function feed(player: Player): any
	local s = S(player)
	if s.snack <= 0 then
		return res(false, "nosnack", "새우과자가 없어요 · 해변 '" .. D.SNACK.stallName .. "'에서 사요")
	end
	local t = os.clock()
	if t - s.lastFeed < D.SNACK.feedCooldown then
		return res(false, "cooldown", "")
	end
	local char, hum, root = character(player)
	if not char or not hum or not root then
		return res(false, "dead", "")
	end
	if not nearSea(root.Position) then
		return res(false, "far", "갈매기는 바닷가에 있어요 🌊")
	end
	s.lastFeed = t
	s.snack -= 1
	char:SetAttribute(D.Char.Snack, s.snack)
	char:SetAttribute(D.Char.FeedSeed, rng:NextInteger(1, 999999))
	char:SetAttribute(D.Char.FeedAt, now())
	s.data.feeds += 1
	s.dirty = true
	local day = gameDay()
	if s.joyDay ~= day then
		s.joyDay = day
		s.joy = 0
	end
	local gain = nil
	if s.joy < D.SNACK.dailyJoy then
		s.joy += 1
		gain = pcall(ctx.addStats, player, { happiness = D.SNACK.happiness }, nil, true)
	end
	if s.snack <= 0 then
		task.delay(D.SNACK.swoop + 0.4, function()
			if S(player).snack <= 0 then
				removeProp(player.Character, "SnackBag")
				local c = player.Character
				if c then
					c:SetAttribute(D.Char.Snack, nil)
				end
			end
		end)
	end
	return res(true, "ok", "", { pieces = s.snack, joy = gain ~= nil })
end

---------------------------------------------------------------------------------------------------
-- (5) 배달
---------------------------------------------------------------------------------------------------
local Housing: any = nil
local function housing(): any
	if Housing ~= nil then
		return Housing or nil
	end
	Housing = false
	local fold = script.Parent
	local m = fold and fold:FindFirstChild("Housing")
	if m and m:IsA("ModuleScript") then
		local ok, r = pcall(require, m)
		if ok and type(r) == "table" then
			Housing = r
		end
	end
	return Housing or nil
end

local function isAtHome(player: Player): boolean
	local H = housing()
	if H and type(H.isAtHome) == "function" then
		local ok, r = pcall(H.isAtHome, player)
		return ok and r == true
	end
	return false
end

local function homeEntrance(player: Player): BasePart?
	local d = Profiles.get(player)
	if not d or not d.home then
		return nil
	end
	local key = G.homeTierKey and G.homeTierKey(d.home.tier) or nil
	if not key and type(d.home.listingId) == "string" and G.LISTINGS and G.LISTINGS[d.home.listingId] then
		key = G.LISTINGS[d.home.listingId].tierKey
	end
	local tag = (G.HomeTags and G.HomeTags.Entrance) or "HomeEntrance"
	local best: BasePart? = nil
	for _, inst in CollectionService:GetTagged(tag) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) then
			local tk = G.homeTierKey and G.homeTierKey(inst:GetAttribute("Tier")) or inst:GetAttribute("Tier")
			if tk == key then
				if inst:GetAttribute("Fallback") ~= true or best == nil then
					best = inst
				end
			end
		end
	end
	if not best and type(d.home.listingId) == "string" and G.LISTINGS and G.LISTINGS[d.home.listingId] then
		best = ctx.dest(G.LISTINGS[d.home.listingId].place)
	end
	return best
end

local function groundBelow(part: BasePart): Vector3
	return part.Position - Vector3.new(0, part.Size.Y / 2, 0)
end

-- Ride polyline to the entrance: back along the traffic lanes from the lane node nearest the door
-- (GwangalliNav lanes), then the kerb point. Fallback: a straight run toward the door.
local laneRev: { { number } }? = nil
local function ridePath(door: Vector3, look: Vector3): { Vector3 }
	local pts: { Vector3 } = {}
	local okNav = false
	if Nav and type(Nav.lanes) == "table" and type(Nav.nearestLane) == "function" then
		okNav = pcall(function()
			local L = Nav.lanes
			if not laneRev then
				local rev = table.create(L.n)
				for i = 1, L.n do
					rev[i] = {}
				end
				local nE = math.floor(#L.edges / 4)
				for e = 0, nE - 1 do
					local from, to = L.edges[e * 4 + 1], L.edges[e * 4 + 2]
					if rev[to] then
						table.insert(rev[to], from)
					end
				end
				laneRev = rev
			end
			local start = Nav.nearestLane(door, 160)
			if not start then
				error("no lane")
			end
			local function lp(i: number): Vector3
				return Vector3.new(L.pos[(i - 1) * 2 + 1], 6.0, L.pos[(i - 1) * 2 + 2])
			end
			local chain = { start }
			local seen = { [start] = true }
			local dist = 0
			local cur = start
			while dist < D.DELIVERY.rideStuds and #chain < 60 do
				local preds = (laneRev :: any)[cur]
				local nextN = nil
				if preds and #preds > 0 then
					-- prefer the predecessor that keeps the heading (least turning)
					local bestScore = -math.huge
					for _, pnode in preds do
						if not seen[pnode] then
							local dir = (lp(cur) - lp(pnode))
							local score = rng:NextNumber(0, 0.4)
							if #chain >= 2 then
								local prevDir = lp(chain[#chain - 1]) - lp(cur)
								if prevDir.Magnitude > 0.1 and dir.Magnitude > 0.1 then
									score += prevDir.Unit:Dot(dir.Unit)
								end
							end
							if score > bestScore then
								bestScore = score
								nextN = pnode
							end
						end
					end
				end
				if not nextN then
					break
				end
				dist += (lp(cur) - lp(nextN)).Magnitude
				seen[nextN] = true
				table.insert(chain, nextN)
				cur = nextN
			end
			for i = #chain, 1, -1 do
				table.insert(pts, lp(chain[i]))
			end
		end)
	end
	if not okNav or #pts < 2 then
		pts = {}
		local away = Vector3.new(look.X, 0, look.Z)
		if away.Magnitude < 0.1 then
			away = Vector3.new(0, 0, -1)
		end
		away = away.Unit
		local side = Vector3.new(-away.Z, 0, away.X)
		local y = door.Y
		local kerb = door + away * 10
		table.insert(pts, Vector3.new(kerb.X, y, kerb.Z) + side * 160)
		table.insert(pts, Vector3.new(kerb.X, y, kerb.Z) + side * 30)
	end
	-- kerb stop next to the door: 6 studs from the door toward the last lane point
	local last = pts[#pts]
	local toLane = Vector3.new(last.X - door.X, 0, last.Z - door.Z)
	local kerb = door
	if toLane.Magnitude > 1 then
		kerb = door + toLane.Unit * math.min(7, toLane.Magnitude)
	end
	table.insert(pts, Vector3.new(kerb.X, math.max(door.Y, last.Y), kerb.Z))
	return pts
end

local function encodePath(pts: { Vector3 }): string
	local parts = table.create(#pts)
	for i, p in pts do
		parts[i] = string.format("%.1f,%.1f,%.1f", p.X, p.Y, p.Z)
	end
	return table.concat(parts, ";")
end

local function pathLength(pts: { Vector3 }): number
	local L = 0
	for i = 2, #pts do
		L += (pts[i] - pts[i - 1]).Magnitude
	end
	return L
end

local function orderView(o: any?): any
	if not o then
		return false
	end
	local m = D.MENU_BY_ID[o.menu]
	return {
		id = o.id,
		menu = o.menu,
		state = o.state,
		total = o.total,
		placedAt = o.placedAt,
		cookAt = o.cookAt,
		rideAt = o.rideAt,
		arriveAt = o.arriveAt,
		etaMin = o.etaMin,
		rider = o.rider,
		shop = m and m.shop or "",
		item = m and m.item or "",
		icon = m and m.icon or "🍱",
		leaveAt = o.leaveAt,
	}
end

local function pushOrder(player: Player)
	local s = S(player)
	fire(player, { kind = "order", order = orderView(s.order) })
end

local function destroyRide(o: any, delay: number?)
	local cfg = o.ride
	o.ride = nil
	if cfg then
		if delay and delay > 0 then
			task.delay(delay, function()
				cfg:Destroy()
			end)
		else
			cfg:Destroy()
		end
	end
end

local function giveFoodBag(player: Player, menuId: string)
	local s = S(player)
	s.food = menuId
	local char = player.Character
	if not char then
		return
	end
	char:SetAttribute(D.Char.Food, menuId)
	local hand = handOf(char, false)
	if not hand then
		return
	end
	local m = D.MENU_BY_ID[menuId]
	local col = m and rgb(m.color) or Color3.fromRGB(255, 255, 255)
	weldProp(char, "FoodBag", function(mm)
		local bag = Instance.new("Part")
		bag.Name = "Bag"
		bag.Size = Vector3.new(1.0, 0.9, 0.7)
		bag.CFrame = CFrame.new()
		bag.Color = Color3.fromRGB(250, 250, 248)
		bag.Material = Enum.Material.SmoothPlastic
		bag.Parent = mm
		local band = Instance.new("Part")
		band.Name = "Label"
		band.Size = Vector3.new(1.02, 0.25, 0.72)
		band.CFrame = CFrame.new(0, 0.1, 0)
		band.Color = col
		band.Material = Enum.Material.SmoothPlastic
		band.Parent = mm
		for _, sx in { -0.3, 0.3 } do
			local h = Instance.new("Part")
			h.Name = "Handle"
			h.Size = Vector3.new(0.08, 0.5, 0.08)
			h.CFrame = CFrame.new(sx, 0.65, 0)
			h.Color = Color3.fromRGB(250, 250, 248)
			h.Parent = mm
		end
	end, hand, CFrame.new(0, -0.75, 0))
end

local function clearFood(player: Player)
	local s = S(player)
	s.food = nil
	local char = player.Character
	if char then
		char:SetAttribute(D.Char.Food, nil)
		removeProp(char, "FoodBag")
	end
end

local function placeOrder(player: Player, payload: any): any
	local s = S(player)
	local id = Util.str(payload.menu, 20)
	local m = id and D.MENU_BY_ID[id]
	if not m then
		return res(false, "menu", "메뉴를 찾을 수 없어요")
	end
	if s.order and s.order.state ~= "done" and s.order.state ~= "cancelled" then
		return res(false, "busy", "이미 주문한 음식이 오고 있어요 🛵")
	end
	if s.food then
		return res(false, "food", "받은 음식부터 먹어요 😋")
	end
	local door = homeEntrance(player)
	if not door then
		return res(false, "nohome", "집이 있어야 배달을 받을 수 있어요 · 부동산 앱에서 집을 구해요")
	end
	local tip = D.deliveryTip(m.price)
	local total = m.price + tip
	local d = Profiles.get(player)
	if not d or (d.bank or 0) < total then
		return res(false, "money", "통장 잔액이 부족해요 · " .. D.won(total))
	end
	if not ctx.ledger(player, "bank", -total, D.DELIVERY.brand .. " · " .. m.shop, true) then
		return res(false, "money", "결제에 실패했어요")
	end
	local t = now()
	local rate = clockRate()
	local etaMin = m.prepMin + 25
	local arriveIn = D.gameMinutes(etaMin, rate)
	local rideTime = math.min(arriveIn * 0.45, D.DELIVERY.rideStuds / D.DELIVERY.rideSpeed + 2)
	s.order = {
		id = string.format("o%d%03d", os.time(), rng:NextInteger(0, 999)),
		menu = m.id,
		state = "accepted",
		total = total,
		tip = tip,
		placedAt = t,
		cookAt = t + math.min(4, arriveIn * 0.1),
		rideAt = t + arriveIn - rideTime,
		arriveAt = t + arriveIn,
		etaMin = etaMin,
		rider = D.DELIVERY.riders[rng:NextInteger(1, #D.DELIVERY.riders)],
		door = door,
		ride = nil,
		leaveAt = 0,
	}
	s.data.orders += 1
	s.dirty = true
	notify(player, "money", "주문 완료 🛵 -" .. D.won(total), m.shop .. " · " .. m.item .. " (약 " .. etaMin .. "분)")
	pushOrder(player)
	return res(true, "ok", "", { order = orderView(s.order) })
end

local function cancelOrder(player: Player): any
	local s = S(player)
	local o = s.order
	if not o or o.state ~= "accepted" then
		return res(false, "late", "이미 조리가 시작돼서 취소할 수 없어요")
	end
	o.state = "cancelled"
	pcall(ctx.ledger, player, "bank", o.total, D.DELIVERY.brand .. " 주문 취소 (환불)", true)
	notify(player, "money", "주문 취소 · 환불 +" .. D.won(o.total), "")
	pushOrder(player)
	s.order = nil
	return res(true, "ok", "")
end

local function startRide(player: Player, o: any)
	local door: BasePart = o.door
	if not door or not door.Parent then
		door = homeEntrance(player) :: any
		o.door = door
	end
	if not door then
		return
	end
	local ground = groundBelow(door)
	local look = door.CFrame.LookVector
	local pts = ridePath(ground, look)
	local len = pathLength(pts)
	local speed = math.max(12, len / math.max(4, o.arriveAt - now() - 3.5))
	speed = math.min(speed, 60)
	local cfg = Instance.new("Configuration")
	cfg.Name = "Ride_" .. o.id
	cfg:SetAttribute("Owner", player.UserId)
	cfg:SetAttribute("OwnerName", displayName(player))
	cfg:SetAttribute("Path", encodePath(pts))
	cfg:SetAttribute("Start", now())
	cfg:SetAttribute("Speed", speed)
	cfg:SetAttribute("Length", len)
	cfg:SetAttribute("Menu", o.menu)
	cfg:SetAttribute("Rider", o.rider)
	cfg:SetAttribute("Door", ground)
	cfg:SetAttribute("State", "riding")
	cfg:SetAttribute("Seed", rng:NextInteger(1, 99999))
	cfg.Parent = ridesFolder
	o.ride = cfg
	o.arriveAt = now() + len / speed + 3.5 -- park, get off, walk to the door, ring
end

local function takeFood(player: Player): any
	local s = S(player)
	local o = s.order
	if not o or (o.state ~= "arrived" and o.state ~= "left") then
		return res(false, "none", "받을 음식이 없어요")
	end
	local okWhere = isAtHome(player)
	if not okWhere and o.door and o.door.Parent then
		local rp = Util.rootPosition(player)
		okWhere = rp ~= nil and (rp - o.door.Position).Magnitude <= 22
	end
	if not okWhere then
		return res(false, "far", "집이나 현관 앞에서 받을 수 있어요")
	end
	o.state = "done"
	giveFoodBag(player, o.menu)
	if o.ride then
		o.ride:SetAttribute("State", "leaving")
		o.ride:SetAttribute("LeaveStart", now())
		destroyRide(o, 9)
	end
	local m = D.MENU_BY_ID[o.menu]
	notify(player, "home", "음식 받았어요 🛍️", (m and m.item or "") .. " · 집에서 '먹기'")
	pushOrder(player)
	s.order = nil
	return res(true, "ok", "", { food = s.food })
end

local function eat(player: Player): any
	local s = S(player)
	if not s.food then
		return res(false, "none", "먹을 음식이 없어요")
	end
	if not isAtHome(player) then
		return res(false, "home", "집에 가서 먹어요 🏠 (현관에서 들어가기)")
	end
	if os.clock() - s.lastEat < D.DELIVERY.eatCooldown then
		return res(false, "full", "배불러요 😌 조금 있다가요")
	end
	local m = D.MENU_BY_ID[s.food]
	clearFood(player)
	s.lastEat = os.clock()
	local applied = {}
	if m then
		local okA, a = pcall(ctx.addStats, player, m.stats, nil, true)
		if okA and type(a) == "table" then
			applied = a
		end
		if ctx.health and type(ctx.health.rest) == "function" then
			pcall(ctx.health.rest, player, 6, "meal")
		end
		local desc = ""
		if G.describeStats then
			local okD, txt = pcall(G.describeStats, applied)
			if okD and type(txt) == "string" then
				desc = txt
			end
		end
		notify(player, "stat", "맛있다! " .. m.icon, m.item .. (if desc ~= "" then " · " .. desc else ""))
	end
	return res(true, "ok", "", { menu = m and m.id or "" })
end

local function deliveryTick()
	local t = now()
	for player, s in states do
		local o = s.order
		if o and player.Parent == Players then
			if o.state == "accepted" and t >= o.cookAt then
				o.state = "cooking"
				pushOrder(player)
			elseif o.state == "cooking" and t >= o.rideAt then
				o.state = "riding"
				local okR, err = pcall(startRide, player, o)
				if not okR then
					warn("[Details] ride: " .. tostring(err))
				end
				notify(player, "home", "배달 출발 🛵", "라이더 " .. o.rider .. "님이 출발했어요")
				pushOrder(player)
			elseif o.state == "riding" and t >= o.arriveAt then
				o.state = "arrived"
				o.leaveAt = t + D.DELIVERY.waitAtDoor
				if o.ride then
					o.ride:SetAttribute("State", "arrived")
					o.ride:SetAttribute("ArriveAt", t)
				end
				local m = D.MENU_BY_ID[o.menu]
				notify(player, "home", "띵동~ 배달 왔습니다! 🛵", (m and m.shop or "") .. " · 현관에서 받아 주세요")
				fire(player, { kind = "doorbell", menu = o.menu, home = isAtHome(player) })
				pushOrder(player)
			elseif o.state == "arrived" and t >= o.leaveAt then
				o.state = "left"
				if o.ride then
					o.ride:SetAttribute("State", "left")
					o.ride:SetAttribute("LeaveStart", t)
				end
				notify(player, "home", "문 앞에 두고 갔어요 🛍️", "현관 앞이나 집에서 받을 수 있어요")
				pushOrder(player)
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- (7) 불꽃축제 + weekday
---------------------------------------------------------------------------------------------------
local fest = {
	weekday = 0,
	dayIndex = 0,
	lastClock = -1,
	running = false,
	startAt = 0,
	mats = nil :: Folder?,
	announced = -1,
	nextPublished = 0,
}

local function kstWeekday(): number
	local days = math.floor((os.time() + 9 * 3600) / 86400)
	return (days + 3) % 7 -- 1970-01-01 was a Thursday (Monday = 0)
end

local function buildMats()
	if fest.mats and fest.mats.Parent then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "FestivalMats"
	local palette = { { 40, 120, 220 }, { 60, 190, 120 }, { 240, 90, 120 }, { 255, 190, 60 }, { 150, 110, 240 } }
	for i, mp in D.FESTIVAL.mats do
		local x = mp[1]
		local z = D.promZ(x) - mp[2]
		local y = D.sandHeight(x, z)
		local cf = CFrame.new(x, y + 0.06, z) * CFrame.Angles(0, math.rad(D.rand(i, 3) * 30 - 15), 0)
		local m = Instance.new("Model")
		m.Name = "돗자리_" .. i
		local c = palette[(i - 1) % #palette + 1]
		deco(m, "Mat", Vector3.new(6, 0.08, 4.6), cf, rgb(c), Enum.Material.Fabric)
		for k = 0, 2 do
			deco(m, "Check", Vector3.new(6.02, 0.09, 0.7), cf * CFrame.new(0, 0, -1.6 + k * 1.6), Color3.fromRGB(255, 255, 255), Enum.Material.Fabric)
		end
		-- a cooler / snack bag on some mats
		if i % 3 == 0 then
			deco(m, "Cooler", Vector3.new(1.2, 0.9, 0.8), cf * CFrame.new(2.3, 0.5, 1.6), Color3.fromRGB(70, 140, 230), Enum.Material.SmoothPlastic)
		end
		local seatCf = cf * CFrame.new(0, 0.5, 0) -- seats face the bridge (-Z)
		local seat = Instance.new("Seat")
		seat.Name = "MatSeat"
		seat.Size = Vector3.new(2, 0.4, 2)
		seat.CFrame = CFrame.lookAt(seatCf.Position, seatCf.Position + Vector3.new(0, 0, -1))
		seat.Anchored = true
		seat.CanTouch = false
		seat.Transparency = 1
		seat.TopSurface = Enum.SurfaceType.Smooth
		seat.BottomSurface = Enum.SurfaceType.Smooth
		seat:SetAttribute("GwDetailsSeat", true)
		seat.Parent = m
		local pr = prompt(seat, "돗자리에 앉기", "불꽃축제 명당 🎆", 0.2, 8)
		pr.Triggered:Connect(function(player: Player)
			local _, hum = character(player)
			if hum and not seat.Occupant then
				pcall(function()
					seat:Sit(hum)
				end)
			end
		end)
		m:AddTag(D.Tags.Mat)
		m.Parent = f
	end
	f.Parent = world
	fest.mats = f
end

local function clearMats()
	if fest.mats then
		fest.mats:Destroy()
		fest.mats = nil
	end
end

local function startFestival(reason: string)
	if fest.running then
		return false
	end
	fest.running = true
	fest.startAt = now()
	workspace:SetAttribute(D.WS.FestivalSeed, rng:NextInteger(1, 999999))
	workspace:SetAttribute(D.WS.FestivalStart, fest.startAt)
	workspace:SetAttribute(D.WS.FestivalDay, true)
	buildMats()
	for _, p in Players:GetPlayers() do
		notify(p, "info", "🎆 " .. D.FESTIVAL.name .. " 시작!", "광안대교 위 하늘을 보세요 · 해변 돗자리 명당")
	end
	print("[Details] fireworks festival started (" .. reason .. ")")
	task.delay(D.FESTIVAL.duration, function()
		fest.running = false
		for _, p in Players:GetPlayers() do
			notify(p, "info", "🎆 " .. D.FESTIVAL.name .. " 끝!", "다음 주 토요일 17:00에 또 만나요 · 이어서 드론쇼!")
		end
		task.delay(D.FESTIVAL.matsAfter, function()
			if not fest.running then
				clearMats()
				workspace:SetAttribute(D.WS.FestivalDay, false)
			end
		end)
	end)
	return true
end

local function festivalTick()
	local clock = clockNow()
	if fest.lastClock >= 0 and clock < fest.lastClock - 12 then
		fest.dayIndex += 1
		fest.weekday = (fest.weekday + 1) % 7
		workspace:SetAttribute(D.WS.Weekday, fest.weekday)
		workspace:SetAttribute(D.WS.DayIndex, fest.dayIndex)
	end
	local F = D.FESTIVAL
	if fest.weekday == F.weekday and fest.lastClock >= 0 then
		local prev = fest.lastClock
		if prev < F.clock and clock >= F.clock and clock - prev < 1 then
			startFestival("schedule")
		end
		-- announce window (2 in-game hours before): mats + banner flag + one toast
		local a0 = F.clock - F.announceHours
		if clock >= a0 and clock < F.clock and fest.announced ~= fest.dayIndex then
			fest.announced = fest.dayIndex
			workspace:SetAttribute(D.WS.FestivalDay, true)
			buildMats()
			for _, p in Players:GetPlayers() do
				notify(p, "info", "🎆 오늘 " .. D.clockText(F.clock) .. " " .. F.name, "광안리 해변 돗자리 명당을 잡으세요!")
			end
		end
	end
	fest.lastClock = clock
	local nxt = D.nextFestival(now(), fest.weekday, clock, clockRate())
	if nxt and math.abs(nxt - fest.nextPublished) > 3 then
		fest.nextPublished = nxt
		workspace:SetAttribute(D.WS.FestivalNext, nxt)
	end
end

---------------------------------------------------------------------------------------------------
-- (8) coins + lost wallet
---------------------------------------------------------------------------------------------------
type Coin = { id: string, part: BasePart, amount: number, born: number, owner: Player? }
local coins: { [string]: Coin } = {}
local coinCount = 0
local coinFolder: Folder = nil :: any

local function spawnCoin(player: Player, pos: Vector3?): Coin?
	if coinCount >= D.COIN.maxTotal then
		return nil
	end
	local rp = Util.rootPosition(player)
	local p = pos
	if not p and rp then
		p = sidewalkPoint(rp, D.COIN.near[1], D.COIN.near[2])
	end
	if not p then
		return nil
	end
	local r = rng:NextNumber()
	local amount = D.COIN.amounts[1][1]
	local acc = 0
	for _, a in D.COIN.amounts do
		acc += a[2]
		if r <= acc then
			amount = a[1]
			break
		end
	end
	local id = string.format("c%d%04d", os.time() % 100000, rng:NextInteger(0, 9999))
	local dia = if amount >= 500 then 0.95 else 0.85
	local c = Instance.new("Part")
	c.Name = "Coin_" .. amount
	c.Shape = Enum.PartType.Cylinder
	c.Size = Vector3.new(0.09, dia, dia)
	c.CFrame = CFrame.new(p + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), math.rad(90))
	c.Anchored = true
	c.CanCollide = false
	c.CanQuery = false
	c.CanTouch = false
	c.CastShadow = false
	c.Material = Enum.Material.Metal
	c.Reflectance = 0.25
	c.Color = if amount >= 500 then Color3.fromRGB(214, 214, 206) else Color3.fromRGB(196, 198, 202)
	c:SetAttribute("CoinId", id)
	c:SetAttribute("Amount", amount)
	c:AddTag(D.Tags.Coin)
	c.Parent = coinFolder
	local coin = { id = id, part = c, amount = amount, born = os.clock(), owner = player }
	coins[id] = coin
	coinCount += 1
	return coin
end

local function removeCoin(id: string)
	local c = coins[id]
	if c then
		coins[id] = nil
		coinCount -= 1
		c.part:Destroy()
	end
end

local function pickCoin(player: Player, payload: any): any
	local id = Util.str(payload.id, 24)
	local c = id and coins[id]
	if not c then
		return res(false, "gone", "")
	end
	local s = S(player)
	local t = os.clock()
	if t - s.lastCoin < D.COIN.cooldown then
		return res(false, "cooldown", "")
	end
	local rp = Util.rootPosition(player)
	if not rp or (rp - c.part.Position).Magnitude > D.COIN.serverReach then
		return res(false, "far", "")
	end
	local day = gameDay()
	if s.coinDay ~= day then
		s.coinDay = day
		s.coins = 0
	end
	if s.coins >= D.COIN.dailyMax then
		removeCoin(c.id)
		return res(false, "limit", "")
	end
	s.lastCoin = t
	s.coins += 1
	s.data.coinsTotal += 1
	s.dirty = true
	local amount = c.amount
	local pos = c.part.Position
	removeCoin(c.id)
	pcall(ctx.addMoney, player, amount, "길에서 주운 동전 🪙", true)
	fireNear(pos, 80, { kind = "coinPicked", id = id, by = player.UserId, amount = amount, pos = pos })
	return res(true, "ok", "", { amount = amount, total = s.data.coinsTotal })
end

type Wallet = { id: string, part: BasePart, born: number, owner: string, items: { string }, reward: number, forPlayer: Player? }
local wallets: { [string]: Wallet } = {}

local function spawnWallet(player: Player, pos: Vector3?): Wallet?
	local rp = Util.rootPosition(player)
	local p = pos
	if not p and rp then
		p = sidewalkPoint(rp, 25, 80)
	end
	if not p then
		return nil
	end
	local id = string.format("w%d%03d", os.time() % 100000, rng:NextInteger(0, 999))
	local w = Instance.new("Part")
	w.Name = "LostWallet"
	w.Size = Vector3.new(0.95, 0.22, 0.65)
	w.CFrame = CFrame.new(p + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
	w.Anchored = true
	w.CanCollide = false
	w.CanTouch = false
	w.CastShadow = false
	w.Material = Enum.Material.Leather
	w.Color = Color3.fromRGB(120, 72, 44)
	w:SetAttribute("WalletId", id)
	w:AddTag(D.Tags.Wallet)
	local strap = Instance.new("Part")
	strap.Name = "Strap"
	strap.Size = Vector3.new(0.3, 0.24, 0.67)
	strap.CFrame = w.CFrame * CFrame.new(0.25, 0.005, 0)
	strap.Anchored = true
	strap.CanCollide = false
	strap.CanQuery = false
	strap.CanTouch = false
	strap.Color = Color3.fromRGB(90, 52, 30)
	strap.Material = Enum.Material.Leather
	strap.Parent = w
	local owner = D.WALLET.owners[rng:NextInteger(1, #D.WALLET.owners)]
	local items = {}
	local pool = table.clone(D.WALLET.items)
	for _ = 1, 3 do
		if #pool == 0 then
			break
		end
		table.insert(items, table.remove(pool, rng:NextInteger(1, #pool)))
	end
	local lo, hi = D.WALLET.reward[1] / 1000, D.WALLET.reward[2] / 1000
	local wallet: Wallet = { id = id, part = w, born = os.clock(), owner = owner, items = items, reward = rng:NextInteger(lo, hi) * 1000, forPlayer = player }
	local pr = prompt(w, "지갑 줍기", "누군가 떨어뜨린 지갑 👛", 0.4, 7)
	pr.Triggered:Connect(function(who: Player)
		local s = S(who)
		if s.wallet or not wallets[id] then
			if s.wallet then
				notify(who, "info", "👛 이미 지갑을 들고 있어요", "먼저 분실물 센터에 맡겨 주세요")
			end
			return
		end
		wallets[id] = nil
		w:Destroy()
		s.wallet = { owner = owner, items = items, reward = wallet.reward, t = os.clock() }
		local char = who.Character
		if char then
			char:SetAttribute(D.Char.Wallet, true)
		end
		pcall(ctx.setWaypoint, who, "광안리 관광안내소")
		fire(who, { kind = "wallet", owner = owner, items = items, counter = D.WALLET.counterName })
	end)
	w.Parent = coinFolder
	wallets[id] = wallet
	return wallet
end

local counterPart: BasePart? = nil
local function buildCounter()
	local cfg = D.WALLET.counter
	local base = CFrame.new(cfg.x, 6.5, cfg.z) * CFrame.Angles(0, math.rad(cfg.yaw or 0), 0)
	local m = Instance.new("Model")
	m.Name = "분실물 센터 (관광안내소)"
	local function L(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x, y, z)
	end
	part(m, "Desk", Vector3.new(4.6, 3.2, 1.6), L(0, 1.6, 0), Color3.fromRGB(236, 236, 232), Enum.Material.SmoothPlastic)
	part(m, "DeskTop", Vector3.new(4.9, 0.18, 1.9), L(0, 3.29, 0), Color3.fromRGB(70, 140, 220), Enum.Material.SmoothPlastic)
	deco(m, "DeskStripe", Vector3.new(4.62, 0.4, 1.62), L(0, 2.6, 0), Color3.fromRGB(70, 140, 220), Enum.Material.SmoothPlastic)
	local sign = deco(m, "Sign", Vector3.new(4.4, 1.2, 0.12), L(0, 5.6, 0.6), Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic)
	signText(sign, Enum.NormalId.Front, {
		{ text = "분실물 센터", size = 1.5, color = Color3.fromRGB(30, 90, 170), font = Enum.Font.GothamBlack },
		{ text = "LOST & FOUND · 광안리 관광안내소", size = 0.9, color = Color3.fromRGB(90, 100, 120) },
	}, Color3.fromRGB(255, 255, 255), 40)
	sign:AddTag("NightGlow")
	for _, sx in { -2.0, 2.0 } do
		cyl(m, "SignPost", 2.3, 0.12, L(sx, 4.4, 0.6) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(180, 180, 180), Enum.Material.Metal)
	end
	-- a basket of found items + a bell
	deco(m, "Basket", Vector3.new(1.2, 0.5, 0.8), L(-1.5, 3.65, 0.1), Color3.fromRGB(196, 160, 110), Enum.Material.Fabric)
	deco(m, "Umbrella", Vector3.new(0.12, 0.12, 1.6), L(-1.6, 3.95, 0.1) * CFrame.Angles(0.3, 0.4, 0), Color3.fromRGB(240, 80, 90), Enum.Material.SmoothPlastic)
	ball(m, "Bell", Vector3.new(0.4, 0.3, 0.4), L(1.6, 3.55, -0.3), Color3.fromRGB(230, 200, 90), Enum.Material.Metal)
	local cp = part(m, "CounterPoint", Vector3.new(2, 2, 1), L(0, 2, -1.6), Color3.new(), Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	cp:AddTag(D.Tags.Counter)
	cp:SetAttribute("StaffYaw", (cfg.yaw or 0) + 180)
	m.WorldPivot = base
	m.Parent = world
	counterPart = cp
end

local function returnWallet(player: Player): any
	local s = S(player)
	local w = s.wallet
	if not w then
		return res(false, "none", "맡길 지갑이 없어요")
	end
	local rp = Util.rootPosition(player)
	if not counterPart or not rp or (rp - counterPart.Position).Magnitude > 16 then
		return res(false, "far", "관광안내소 분실물 센터에서 맡길 수 있어요")
	end
	s.wallet = nil
	local char = player.Character
	if char then
		char:SetAttribute(D.Char.Wallet, nil)
	end
	local day = gameDay()
	if s.walletDay ~= day then
		s.walletDay = day
		s.wallets = 0
	end
	s.wallets += 1
	s.data.returned += 1
	s.dirty = true
	local reward = if s.wallets <= D.WALLET.daily then w.reward else 0
	if reward > 0 then
		pcall(ctx.addMoney, player, reward, "분실물 사례금 · " .. w.owner .. "님", true)
	end
	pcall(ctx.addStats, player, D.WALLET.stats, nil, true)
	pcall(ctx.setWaypoint, player, nil)
	local inPerson = rng:NextNumber() < 0.35
	fire(player, { kind = "walletThanks", owner = w.owner, reward = reward, inPerson = inPerson, returned = s.data.returned })
	notify(player, "money", "👛 착한 일 했어요! +" .. D.won(reward), w.owner .. "님이 고맙다고 사례금을 맡기셨어요 · 행복 +" .. D.WALLET.stats.happiness)
	return res(true, "ok", "", { reward = reward })
end

local function surprisesTick()
	local t = os.clock()
	-- expire
	for id, c in coins do
		if t - c.born > D.COIN.life or not c.part.Parent then
			removeCoin(id)
		end
	end
	for id, w in wallets do
		if t - w.born > D.WALLET.life or not w.part.Parent then
			wallets[id] = nil
			w.part:Destroy()
		end
	end
	for _, player in Players:GetPlayers() do
		local s = states[player]
		if s and Util.rootPosition(player) then
			if t >= s.nextCoin then
				s.nextCoin = t + rng:NextNumber(D.COIN.interval[1], D.COIN.interval[2])
				local mine = 0
				for _, c in coins do
					if c.owner == player then
						mine += 1
					end
				end
				local day = gameDay()
				if s.coinDay ~= day then
					s.coinDay = day
					s.coins = 0
				end
				if mine < D.COIN.maxPerPlayer and s.coins < D.COIN.dailyMax then
					spawnCoin(player)
				end
			end
			if t >= s.nextWallet then
				s.nextWallet = t + rng:NextNumber(D.WALLET.interval[1], D.WALLET.interval[2])
				local has = s.wallet ~= nil
				for _, w in wallets do
					if w.forPlayer == player then
						has = true
					end
				end
				local day = gameDay()
				if s.walletDay ~= day then
					s.walletDay = day
					s.wallets = 0
				end
				if not has and s.wallets < D.WALLET.daily and rng:NextNumber() < D.WALLET.chance then
					spawnWallet(player)
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- (9) 버스킹
---------------------------------------------------------------------------------------------------
type Stage = { id: string, cfg: any, anchor: BasePart, face: Vector3, prompt: ProximityPrompt, show: any? }
local stages: { [string]: Stage } = {}

local function findStageModel(cfg: any): Model?
	local root = workspace:FindFirstChild("Gwangalli")
	if not root then
		return nil
	end
	local best: Model? = nil
	local bestD = math.huge
	for _, key in { "coast", "millak" } do
		local r = root:FindFirstChild(key)
		if r then
			for _, d in r:GetDescendants() do
				if d:IsA("Model") and string.find(d.Name, cfg.find, 1, true) then
					local ok, cf = pcall(function()
						return d:GetBoundingBox()
					end)
					if ok then
						local dd = (Vector3.new(cf.Position.X, 0, cf.Position.Z) - Vector3.new(cfg.x, 0, cfg.z)).Magnitude
						if dd < bestD then
							bestD = dd
							best = d
						end
					end
				end
			end
		end
	end
	if best and bestD < 120 then
		return best
	end
	return nil
end

local function stageTop(model: Model?, cfg: any): Vector3
	if model then
		-- the largest flat part is the platform
		local bestA, top = 0, nil
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Size.Y < 2.5 then
				local a = d.Size.X * d.Size.Z
				if a > bestA and a > 20 then
					bestA = a
					top = d.Position + Vector3.new(0, d.Size.Y / 2, 0)
				end
			end
		end
		if top then
			return top
		end
		local cf, size = model:GetBoundingBox()
		return Vector3.new(cf.Position.X, cf.Position.Y - size.Y / 2 + 1, cf.Position.Z)
	end
	return Vector3.new(cfg.x, 6.5, cfg.z)
end

local function buildInstrument(m: Model, id: string)
	local function p(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?)
		local q = Instance.new("Part")
		q.Name = name
		q.Size = size
		q.CFrame = cf
		q.Color = color
		q.Material = mat or Enum.Material.SmoothPlastic
		if shape then
			q.Shape = shape
		end
		q.Parent = m
		return q
	end
	if id == "guitar" then
		p("Body", Vector3.new(1.5, 1.9, 0.45), CFrame.new(0, 0, 0), Color3.fromRGB(196, 132, 70), Enum.Material.Wood)
		p("Hole", Vector3.new(0.05, 0.5, 0.5), CFrame.new(0, 0.2, -0.24) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(30, 20, 14), nil, Enum.PartType.Cylinder)
		p("Neck", Vector3.new(0.28, 2.2, 0.16), CFrame.new(0, 2.0, 0), Color3.fromRGB(90, 56, 30), Enum.Material.Wood)
		p("Head", Vector3.new(0.4, 0.5, 0.14), CFrame.new(0, 3.3, 0), Color3.fromRGB(40, 30, 24), Enum.Material.Wood)
	elseif id == "violin" then
		p("Body", Vector3.new(0.8, 1.3, 0.3), CFrame.new(0, 0, 0), Color3.fromRGB(150, 70, 30), Enum.Material.Wood)
		p("Neck", Vector3.new(0.14, 0.9, 0.1), CFrame.new(0, 1.05, 0), Color3.fromRGB(30, 22, 18), Enum.Material.Wood)
		p("Bow", Vector3.new(0.05, 2.4, 0.05), CFrame.new(0.5, 0.3, -0.3) * CFrame.Angles(0, 0, math.rad(70)), Color3.fromRGB(80, 50, 30), Enum.Material.Wood)
	elseif id == "keys" then
		p("Board", Vector3.new(3.4, 0.35, 1.1), CFrame.new(0, 0, 0), Color3.fromRGB(30, 30, 34))
		p("Keys", Vector3.new(3.1, 0.06, 0.55), CFrame.new(0, 0.2, -0.2), Color3.fromRGB(245, 245, 245))
		p("Stand", Vector3.new(0.15, 2.2, 0.15), CFrame.new(0, -1.2, 0) * CFrame.Angles(0, 0, math.rad(20)), Color3.fromRGB(60, 60, 64), Enum.Material.Metal)
	else -- cajon
		p("Box", Vector3.new(1.3, 1.9, 1.3), CFrame.new(0, 0, 0), Color3.fromRGB(176, 120, 70), Enum.Material.WoodPlanks)
		p("Front", Vector3.new(1.1, 1.7, 0.05), CFrame.new(0, 0, -0.66), Color3.fromRGB(60, 40, 26), Enum.Material.Wood)
	end
end

local function buildCase(parent: Instance, cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "TipCase"
	deco(m, "Case", Vector3.new(3.2, 0.35, 1.3), cf, Color3.fromRGB(30, 30, 34), Enum.Material.Leather)
	deco(m, "Lining", Vector3.new(2.9, 0.06, 1.05), cf * CFrame.new(0, 0.18, 0), Color3.fromRGB(150, 30, 50), Enum.Material.Fabric)
	deco(m, "Lid", Vector3.new(3.2, 1.3, 0.12), cf * CFrame.new(0, 0.6, 0.66) * CFrame.Angles(math.rad(-15), 0, 0), Color3.fromRGB(30, 30, 34), Enum.Material.Leather)
	local card = deco(m, "Card", Vector3.new(1.4, 0.7, 0.04), cf * CFrame.new(0, 0.62, 0.58) * CFrame.Angles(math.rad(-15), 0, 0), Color3.fromRGB(255, 250, 236), Enum.Material.SmoothPlastic)
	signText(card, Enum.NormalId.Front, { { text = "감사합니다 ♪", size = 1, color = Color3.fromRGB(60, 40, 30), font = Enum.Font.GothamBold } }, Color3.fromRGB(255, 250, 236), 60)
	m.Parent = parent
	return m
end

local function stageView(st: Stage): any
	local sh = st.show
	return {
		id = st.id,
		name = st.cfg.name,
		performer = sh and sh.player.UserId or 0,
		performerName = sh and displayName(sh.player) or "",
		instrument = sh and sh.instrument or "",
		song = sh and sh.song or "",
		start = sh and sh.start or 0,
		earned = sh and sh.earned or 0,
	}
end

local function publishStage(st: Stage)
	local a = st.anchor
	local sh = st.show
	a:SetAttribute("Performer", sh and sh.player.UserId or 0)
	a:SetAttribute("PerformerName", sh and displayName(sh.player) or "")
	a:SetAttribute("Instrument", sh and sh.instrument or "")
	a:SetAttribute("Song", sh and sh.song or "")
	a:SetAttribute("Start", sh and sh.start or 0)
	a:SetAttribute("Earned", sh and sh.earned or 0)
	st.prompt.Enabled = sh == nil
end

local function endShow(st: Stage, reason: string)
	local sh = st.show
	if not sh then
		return
	end
	st.show = nil
	local player: Player = sh.player
	if sh.case then
		sh.case:Destroy()
	end
	local char = player.Character
	if char then
		removeProp(char, "Instrument")
		char:SetAttribute(D.Char.Busk, nil)
		char:SetAttribute(D.Char.BuskStage, nil)
	end
	publishStage(st)
	local s = states[player]
	if s then
		s.buskCooldown = os.clock() + D.BUSK.cooldown
		local acc = if sh.notes > 0 then sh.hits / sh.notes else 0
		local score = math.floor(acc * 1000 + sh.combo * 3)
		if score > s.data.best then
			s.data.best = score
		end
		s.data.shows += 1
		s.dirty = true
		if reason ~= "left" then
			pcall(ctx.addStats, player, { happiness = 5, popularity = if acc >= 0.8 then 2 else 1 }, nil, true)
		end
		fire(player, {
			kind = "buskEnd",
			reason = reason,
			stage = st.id,
			acc = acc,
			grade = D.grade(acc),
			npcTips = sh.npcTips,
			playerTips = sh.playerTips,
			earned = sh.earned,
			audience = sh.audience,
			best = s.data.best,
			score = score,
		})
	end
	fireNear(st.anchor.Position, 160, { kind = "buskStage", stage = stageView(st) })
end

local function startShow(player: Player, payload: any): any
	local s = S(player)
	local st = stages[Util.str(payload.stage, 20) or ""]
	if not st then
		return res(false, "stage", "무대를 찾을 수 없어요")
	end
	if st.show then
		return res(false, "busy", "다른 버스커가 공연 중이에요 🎶")
	end
	for _, other in stages do
		if other.show and other.show.player == player then
			return res(false, "already", "이미 공연 중이에요")
		end
	end
	if os.clock() < s.buskCooldown then
		return res(false, "cooldown", "목 좀 풀고요… " .. math.ceil(s.buskCooldown - os.clock()) .. "초 뒤에 다시 해요")
	end
	local inst = D.INSTRUMENT_BY_ID[Util.str(payload.instrument, 20) or ""]
	local song = D.SONG_BY_ID[Util.str(payload.song, 30) or ""]
	if not inst or not song then
		return res(false, "pick", "악기와 곡을 골라요")
	end
	local char, hum, root = character(player)
	if not char or not hum or not root then
		return res(false, "dead", "")
	end
	if (root.Position - st.anchor.Position).Magnitude > 16 then
		return res(false, "far", "무대 가까이 가서 시작해요")
	end
	-- stand on the stage facing the audience
	local spot = st.anchor.Position + Vector3.new(0, 3.1, 0)
	pcall(ctx.allowTeleport, player, 3)
	pcall(function()
		char:PivotTo(CFrame.lookAt(spot, spot + st.face))
	end)
	local hand = handOf(char, false) or root
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or root
	local offset = if inst.id == "keys" then CFrame.new(0, -0.6, -1.6) elseif inst.id == "cajon" then CFrame.new(0, -2.0, -1.4) elseif inst.id == "violin" then CFrame.new(-0.4, 0.9, -0.5) * CFrame.Angles(0, 0, math.rad(-60)) else CFrame.new(0, -0.3, -0.75) * CFrame.Angles(0, 0, math.rad(-55))
	weldProp(char, "Instrument", function(m)
		buildInstrument(m, inst.id)
	end, (if inst.id == "violin" then hand else torso) :: BasePart, offset)
	local caseCf = CFrame.lookAt(st.anchor.Position + st.face.Unit * 3.6 + Vector3.new(0, 0.18, 0), st.anchor.Position + st.face.Unit * 10 + Vector3.new(0, 0.18, 0))
	local case = buildCase(world, caseCf)
	case:SetAttribute("Stage", st.id)
	char:SetAttribute(D.Char.Busk, inst.id)
	char:SetAttribute(D.Char.BuskStage, st.id)
	local chart = D.songChart(song.id, D.BUSK.length)
	st.show = {
		player = player,
		instrument = inst.id,
		song = song.id,
		start = now() + 1.5,
		ends = os.clock() + D.BUSK.length + 1.5,
		case = case,
		notes = 0,
		hits = 0,
		combo = 0,
		maxNotes = #chart,
		lastReport = os.clock(),
		nextTip = os.clock() + 6,
		npcTips = 0,
		playerTips = 0,
		earned = 0,
		audience = 0,
		tippers = {},
	}
	publishStage(st)
	fireNear(st.anchor.Position, 160, { kind = "buskStage", stage = stageView(st) })
	return res(true, "ok", "", { stage = stageView(st), start = st.show.start })
end

local function buskReport(player: Player, payload: any): any
	for _, st in stages do
		local sh = st.show
		if sh and sh.player == player then
			local t = os.clock()
			local dt = math.max(0.5, t - sh.lastReport)
			sh.lastReport = t
			local hits = Util.int(payload.hits, 0, 200) or 0
			local misses = Util.int(payload.misses, 0, 200) or 0
			-- at most ~5 notes per second can exist in any chart
			local cap = math.ceil(dt * 5) + 2
			hits = math.min(hits, cap)
			misses = math.min(misses, cap)
			sh.notes = math.min(sh.maxNotes, sh.notes + hits + misses)
			sh.hits = math.min(sh.notes, sh.hits + hits)
			sh.combo = Util.int(payload.combo, 0, 500) or sh.combo
			return res(true, "ok", "")
		end
	end
	return res(false, "none", "")
end

local function stopShow(player: Player): any
	for _, st in stages do
		if st.show and st.show.player == player then
			endShow(st, "stop")
			return res(true, "ok", "")
		end
	end
	return res(false, "none", "")
end

local function tipPerformer(player: Player, payload: any): any
	local st = stages[Util.str(payload.stage, 20) or ""]
	local sh = st and st.show
	if not st or not sh then
		return res(false, "none", "공연이 끝났어요")
	end
	if sh.player == player then
		return res(false, "self", "")
	end
	local s = S(player)
	local t = os.clock()
	if t - s.lastTip < D.BUSK.tipCooldown then
		return res(false, "cooldown", "")
	end
	local rp = Util.rootPosition(player)
	if not rp or (rp - st.anchor.Position).Magnitude > D.BUSK.radius + 6 then
		return res(false, "far", "공연 가까이에서 팁을 줄 수 있어요")
	end
	local count = sh.tippers[player] or 0
	if count >= D.BUSK.tipMaxPerShow then
		return res(false, "max", "이번 공연에는 충분히 응원했어요 👏")
	end
	if not ctx.ledger(player, "cash", -D.BUSK.tip, "버스킹 팁 · " .. displayName(sh.player), true) then
		return res(false, "money", "현금이 부족해요 (팁 " .. D.won(D.BUSK.tip) .. ")")
	end
	s.lastTip = t
	sh.tippers[player] = count + 1
	pcall(ctx.addMoney, sh.player, D.BUSK.tip, "버스킹 팁 · " .. displayName(player), true)
	sh.playerTips += D.BUSK.tip
	sh.earned += D.BUSK.tip
	st.anchor:SetAttribute("Earned", sh.earned)
	fireNear(st.anchor.Position, 160, { kind = "buskTip", stage = st.id, from = "player", fromId = player.UserId, fromName = displayName(player), amount = D.BUSK.tip })
	return res(true, "ok", "", { amount = D.BUSK.tip })
end

local function buskTick()
	local t = os.clock()
	for _, st in stages do
		local sh = st.show
		if sh then
			local player: Player = sh.player
			local rp = Util.rootPosition(player)
			if player.Parent ~= Players then
				endShow(st, "left")
			elseif not rp or (rp - st.anchor.Position).Magnitude > 14 then
				endShow(st, "moved")
			elseif t >= sh.ends then
				endShow(st, "done")
			else
				-- audience: players near + virtual passers-by
				local near = 0
				for _, p in Players:GetPlayers() do
					local pp = Util.rootPosition(p)
					if p ~= player and pp and (pp - st.anchor.Position).Magnitude <= D.BUSK.radius then
						near += 1
					end
				end
				local acc = if sh.notes > 0 then sh.hits / sh.notes else 0.6
				sh.audience = math.max(sh.audience, near + math.floor(2 + acc * 5))
				if t >= sh.nextTip and sh.npcTips < D.BUSK.npcTipMax and now() >= sh.start + 3 then
					local lo, hi = D.BUSK.npcTipEvery[1], D.BUSK.npcTipEvery[2]
					sh.nextTip = t + hi - (hi - lo) * math.clamp(acc, 0, 1) + rng:NextNumber(-1, 1)
					if acc >= 0.25 then
						local amount = if rng:NextNumber() < 0.08 * acc then 5000 else 1000
						amount = math.min(amount, D.BUSK.npcTipMax - sh.npcTips)
						if amount > 0 then
							sh.npcTips += amount
							sh.earned += amount
							pcall(ctx.addMoney, player, amount, "버스킹 팁 (관객)", true)
							st.anchor:SetAttribute("Earned", sh.earned)
							fireNear(st.anchor.Position, 160, { kind = "buskTip", stage = st.id, from = "npc", amount = amount, k = rng:NextInteger(1, 6) })
						end
					end
				end
			end
		end
	end
end

local function buildStages()
	local f = Instance.new("Folder")
	f.Name = "BuskStages"
	f.Parent = world
	for _, cfg in D.BUSK.stages do
		local model = findStageModel(cfg)
		local top = stageTop(model, cfg)
		local faceT = cfg.face
		local face = Vector3.new(0, 0, 1)
		if cfg.id == "millac" then
			face = Vector3.new(-3197 - top.X, 0, -500 - top.Z)
		elseif cfg.id == "meeting" then
			face = Vector3.new(0, 0, 1)
		end
		if faceT then
			face = Vector3.new(faceT[1] - top.X, 0, faceT[2] - top.Z)
		end
		if face.Magnitude < 0.1 then
			face = Vector3.new(0, 0, 1)
		end
		face = face.Unit
		local a = part(f, "Stage_" .. cfg.id, Vector3.new(3, 0.2, 3), CFrame.lookAt(top + Vector3.new(0, 0.1, 0), top + Vector3.new(0, 0.1, 0) + face), Color3.fromRGB(255, 210, 90), Enum.Material.Neon, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
		a:SetAttribute("StageId", cfg.id)
		a:SetAttribute("StageName", cfg.name)
		a:SetAttribute("FaceX", face.X)
		a:SetAttribute("FaceZ", face.Z)
		a:AddTag(D.Tags.Stage)
		local pr = prompt(a, "버스킹 하기 🎸", cfg.name, 0.3, 10)
		local st: Stage = { id = cfg.id, cfg = cfg, anchor = a, face = face, prompt = pr, show = nil }
		stages[cfg.id] = st
		publishStage(st)
		pr.Triggered:Connect(function(player: Player)
			if st.show then
				return
			end
			fire(player, { kind = "buskSetup", stage = st.id, name = cfg.name })
		end)
	end
end

---------------------------------------------------------------------------------------------------
-- Fish tanks: tag the 수족관 models once (clients animate them as they stream in)
---------------------------------------------------------------------------------------------------
local function tagFishTanks()
	local root = workspace:FindFirstChild("Gwangalli")
	if not root then
		return 0
	end
	local n = 0
	for _, key in { "millak", "beachfront", "city" } do
		local r = root:FindFirstChild(key)
		if r then
			for _, d in r:GetDescendants() do
				if d:IsA("Model") and string.sub(d.Name, 1, #"수족관") == "수족관" then
					d:AddTag(D.Tags.FishTank)
					n += 1
				end
			end
			task.wait()
		end
	end
	return n
end

---------------------------------------------------------------------------------------------------
-- Request dispatch
---------------------------------------------------------------------------------------------------
local function stateView(player: Player): any
	local s = S(player)
	local stageList = {}
	for _, st in stages do
		table.insert(stageList, stageView(st))
	end
	return {
		ok = true,
		code = "ok",
		message = "",
		album = s.data.strips,
		order = orderView(s.order),
		snack = s.snack,
		food = s.food or false,
		wallet = if s.wallet then { owner = s.wallet.owner, items = s.wallet.items } else false,
		coinsTotal = s.data.coinsTotal,
		returned = s.data.returned,
		best = s.data.best,
		stages = stageList,
		booth = (function()
			local b = boothOf(player)
			return if b then boothView(b) else false
		end)(),
	}
end

local function isAdmin(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	return player.UserId == game.CreatorId and game.CreatorType == Enum.CreatorType.User
end

local handlers: { [string]: (Player, any) -> any } = {
	state = function(player)
		return stateView(player)
	end,
	album = function(player)
		return res(true, "ok", "", { album = S(player).data.strips })
	end,
	boothConfig = function(player, p)
		local b = boothOf(player)
		if not b or b.state ~= "setup" then
			return res(false, "none", "")
		end
		local prop = Util.str(p.prop, 20)
		if prop and D.PROP_BY_ID[prop] then
			b.props[player] = prop
		end
		local frame = Util.str(p.frame, 20)
		if frame and D.FRAME_BY_ID[frame] and b.owner == player then
			b.frameId = frame
		end
		boothPublish(b)
		boothBroadcast(b)
		return res(true, "ok", "", { booth = boothView(b) })
	end,
	boothStart = function(player)
		local b = boothOf(player)
		if not b or b.state ~= "setup" or b.owner ~= player then
			return res(false, "none", "")
		end
		boothStart(b)
		return res(true, "ok", "", { booth = boothView(b) })
	end,
	boothLeave = function(player)
		local b = boothOf(player)
		if b and b.state == "setup" then
			boothRemove(b, player, "leave")
		end
		return res(true, "ok", "")
	end,
	feed = function(player)
		return feed(player)
	end,
	coin = function(player, p)
		return pickCoin(player, p)
	end,
	walletReturn = function(player)
		return returnWallet(player)
	end,
	order = function(player, p)
		return placeOrder(player, p)
	end,
	orderCancel = function(player)
		return cancelOrder(player)
	end,
	takeFood = function(player)
		return takeFood(player)
	end,
	eat = function(player)
		return eat(player)
	end,
	buskStart = function(player, p)
		return startShow(player, p)
	end,
	buskReport = function(player, p)
		return buskReport(player, p)
	end,
	buskStop = function(player)
		return stopShow(player)
	end,
	tip = function(player, p)
		return tipPerformer(player, p)
	end,
	festival = function(player)
		if not isAdmin(player) then
			return res(false, "admin", "")
		end
		return res(startFestival("admin " .. player.Name), "ok", "")
	end,
}

local function handle(player: Player, op: any, payload: any): any
	if type(op) ~= "string" or not handlers[op] then
		return res(false, "op", "")
	end
	if payload ~= nil and type(payload) ~= "table" then
		return res(false, "payload", "")
	end
	if not allow(player) then
		return res(false, "rate", "")
	end
	if not Profiles.get(player) then
		return res(false, "loading", "프로필을 불러오는 중이에요")
	end
	local ok, r = pcall(handlers[op], player, payload or {})
	if not ok then
		warn("[Details] " .. op .. " from " .. player.Name .. " failed: " .. tostring(r))
		return res(false, "error", "잠시 후 다시 시도해 주세요")
	end
	return r
end

---------------------------------------------------------------------------------------------------
-- Feature module hooks
---------------------------------------------------------------------------------------------------
local function optional(name: string, wait: number?): any
	local m = ReplicatedStorage:FindFirstChild(name) or (wait and ReplicatedStorage:WaitForChild(name, wait))
	if m and m:IsA("ModuleScript") then
		local ok, r = pcall(require, m)
		if ok and type(r) == "table" then
			return r
		end
	end
	return nil
end

function Details.init(context: any)
	ctx = context
	G = ctx.G
	Util = ctx.Util
	Profiles = ctx.Profiles
	Clock = ctx.Clock
	local dm = ReplicatedStorage:WaitForChild("GwangalliDetailsShared", 10)
	D = require(dm :: ModuleScript)
	D.setSeaData(optional("GwangalliSeaData"))
	Looks = optional("GwangalliNPCLooks")

	folder = ReplicatedStorage:FindFirstChild(D.FOLDER) :: any
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = D.FOLDER
	end
	local function remote(name: string, cls: string): any
		local r = folder:FindFirstChild(name)
		if r and r.ClassName ~= cls then
			r:Destroy()
			r = nil
		end
		if not r then
			r = Instance.new(cls)
			r.Name = name
			r.Parent = folder
		end
		return r
	end
	reqFn = remote(D.Remote.Request, "RemoteFunction")
	evRe = remote(D.Remote.Event, "RemoteEvent")
	ridesFolder = folder:FindFirstChild(D.RIDES) :: any
	if not ridesFolder then
		ridesFolder = Instance.new("Folder")
		ridesFolder.Name = D.RIDES
		ridesFolder.Parent = folder
	end
	folder.Parent = ReplicatedStorage
	reqFn.OnServerInvoke = function(player: Player, op: any, payload: any)
		return handle(player, op, payload)
	end

	world = Instance.new("Folder")
	world.Name = "GwangalliDetailsWorld"
	world.Parent = workspace
	coinFolder = Instance.new("Folder")
	coinFolder.Name = "Finds"
	coinFolder.Parent = world

	local okStore, st = pcall(function()
		return DataStoreService:GetDataStore(D.DATASTORE)
	end)
	store = if okStore then st else nil

	fest.weekday = kstWeekday()
	workspace:SetAttribute(D.WS.Weekday, fest.weekday)
	workspace:SetAttribute(D.WS.DayIndex, 0)
	workspace:SetAttribute(D.WS.FestivalDay, false)

	for _, spot in D.BOOTH.spots do
		local okB, b = pcall(buildBooth, spot)
		if okB then
			booths[spot.id] = b
			b.prompt.Triggered:Connect(function(player: Player)
				local okT, err = pcall(boothTriggered, b, player)
				if not okT then
					warn("[Details] booth: " .. tostring(err))
				end
			end)
		else
			warn("[Details] booth build failed: " .. tostring(b))
		end
	end
	local okS, errS = pcall(buildStall)
	if not okS then
		warn("[Details] stall build failed: " .. tostring(errS))
	end
	local okC, errC = pcall(buildCounter)
	if not okC then
		warn("[Details] counter build failed: " .. tostring(errC))
	end

	ctx.details = {
		startFestival = startFestival,
		spawnCoin = spawnCoin,
		spawnWallet = spawnWallet,
		orderOf = function(player: Player)
			return orderView(S(player).order)
		end,
		-- jobs hook (integration_todo): pending orders a rider player could take over
		pendingOrders = function()
			local out = {}
			for p, s in states do
				if s.order and (s.order.state == "accepted" or s.order.state == "cooking") then
					table.insert(out, { player = p, order = orderView(s.order) })
				end
			end
			return out
		end,
	}

	-- test / tooling hook (Studio command bar, simulator)
	local api = ServerStorage:FindFirstChild("GwangalliDetailsAPI")
	if not api then
		api = Instance.new("BindableFunction")
		api.Name = "GwangalliDetailsAPI"
		api.Parent = ServerStorage
	end
	(api :: BindableFunction).OnInvoke = function(op: string, player: Player?, a: any, b: any): any
		if op == "festival" then
			return startFestival("api")
		elseif op == "coin" and player then
			local c = spawnCoin(player, a)
			return c and { id = c.id, amount = c.amount, pos = c.part.Position } or nil
		elseif op == "wallet" and player then
			local w = spawnWallet(player, a)
			return w and { id = w.id, pos = w.part.Position, reward = w.reward } or nil
		elseif op == "state" and player then
			return stateView(player)
		elseif op == "snack" and player then
			S(player).snack = a or 5
			local c = player.Character
			if c then
				c:SetAttribute(D.Char.Snack, S(player).snack)
			end
			return true
		elseif op == "fastOrder" and player then
			local o = S(player).order
			if o then
				local t = now()
				o.cookAt = math.min(o.cookAt, t)
				o.rideAt = math.min(o.rideAt, t + 0.5)
				o.arriveAt = math.min(o.arriveAt, t + 4)
				return true
			end
			return false
		elseif op == "home" and player then
			return isAtHome(player)
		elseif op == "stages" then
			local out = {}
			for id, st in stages do
				out[id] = { pos = st.anchor.Position, face = st.face, busy = st.show ~= nil }
			end
			return out
		elseif op == "booth" then
			local out = {}
			for id, bb in booths do
				out[id] = { pos = bb.frame.Position, look = bb.frame.LookVector, state = bb.state }
			end
			return out
		elseif op == "counter" then
			return counterPart and counterPart.Position or nil
		elseif op == "stall" then
			return stallPart and stallPart.Position or nil
		end
		return nil
	end

	-- admin start from Studio / LiveOps: workspace.GwStartFestival = true
	workspace:GetAttributeChangedSignal(D.WS.StartFestival):Connect(function()
		if workspace:GetAttribute(D.WS.StartFestival) == true then
			workspace:SetAttribute(D.WS.StartFestival, false)
			startFestival("attribute")
		end
	end)

	-- heavy one-time scans after start (nav data, stages, tanks)
	task.spawn(function()
		local navM = ReplicatedStorage:FindFirstChild("GwangalliNav") or ReplicatedStorage:WaitForChild("GwangalliNav", 20)
		if navM and navM:IsA("ModuleScript") then
			local okN, r = pcall(require, navM)
			if okN and type(r) == "table" then
				Nav = r
			end
		end
		local okSt, errSt = pcall(buildStages)
		if not okSt then
			warn("[Details] stages: " .. tostring(errSt))
		end
		task.wait(1)
		local okT, n = pcall(tagFishTanks)
		if not okT then
			warn("[Details] fish tanks: " .. tostring(n))
		end
	end)

	-- ONE server loop: 4 Hz booth / delivery / busking, 1 Hz festival / finds / saves
	task.spawn(function()
		local k = 0
		while true do
			task.wait(0.25)
			k += 1
			for _, fn in { boothTick, deliveryTick } do
				local okF, err = pcall(fn)
				if not okF then
					warn("[Details] tick: " .. tostring(err))
				end
			end
			if k % 4 == 0 then
				for _, fn in { festivalTick, surprisesTick, buskTick } do
					local okF, err = pcall(fn)
					if not okF then
						warn("[Details] tick: " .. tostring(err))
					end
				end
			end
			if k % 480 == 0 then
				for player, s in states do
					if s.dirty and player.Parent == Players then
						task.spawn(saveData, player)
					end
				end
			end
		end
	end)
end

function Details.onLoaded(player: Player)
	S(player)
	task.spawn(function()
		loadData(player)
		fire(player, { kind = "ready" })
	end)
end

function Details.onCharacter(player: Player, char: Model)
	local s = S(player)
	-- a respawn drops what the hands held (the snack bag stays counted, the food bag comes back)
	task.defer(function()
		if player.Character ~= char then
			return
		end
		if s.snack > 0 then
			char:SetAttribute(D.Char.Snack, s.snack)
		end
		if s.food then
			giveFoodBag(player, s.food)
		end
		if s.wallet then
			char:SetAttribute(D.Char.Wallet, true)
		end
	end)
	for _, st in stages do
		if st.show and st.show.player == player then
			endShow(st, "respawn")
		end
	end
	local b = boothOf(player)
	if b then
		boothRemove(b, player, "respawn")
	end
end

function Details.onLeave(player: Player)
	local s = states[player]
	for _, st in stages do
		if st.show and st.show.player == player then
			endShow(st, "left")
		end
	end
	local b = boothOf(player)
	if b then
		boothRemove(b, player, "left")
	end
	if s then
		local o = s.order
		if o and o.state ~= "done" and o.state ~= "cancelled" then
			-- not delivered yet: refund to the bank before the profile is saved
			pcall(ctx.ledger, player, "bank", o.total, D.DELIVERY.brand .. " 미수령 환불", true)
			destroyRide(o)
		end
		s.order = nil
		for id, c in coins do
			if c.owner == player then
				removeCoin(id)
			end
		end
		for id, w in wallets do
			if w.forPlayer == player then
				wallets[id] = nil
				w.part:Destroy()
			end
		end
		if s.dirty then
			saveData(player)
		end
	end
	states[player] = nil
end

return Details
