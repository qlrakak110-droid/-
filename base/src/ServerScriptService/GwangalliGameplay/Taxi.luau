-- GwangalliGameplay/Taxi: 광안콜택시 — phone-called taxis that really drive (owner: taxi_call;
-- docs/features_contract.md §4).
--
--   * booking: the phone call (client GwangalliFeatures/TaxiCall) asks the TaxiCall RemoteFunction
--     for a quote and books; the legacy PhoneAction "callTaxi" / "taxiDestination" / "cancelTaxi"
--     (phone 택시 app) map onto the same code
--   * the taxi is a server-owned car (anchored root + welded parts, cloned from the map's
--     VehicleKind = "taxi" car) that drives along the traffic lanes of ReplicatedStorage.GwangalliNav:
--     it appears ~420 studs up the road, drives to the kerb on the caller's side (passenger door
--     facing them), pulls over, blinks its hazards, honks and the driver waves; "탑승" (prompt or the
--     phone card) seats the player in the back; the ride follows the lanes to the kerb nearest the
--     destination (skip = fade to the last seconds after 5 s); on arrival the player pays by card
--     (bank) or cash, gets a receipt SMS and can rate the driver; the taxi drives away
--   * motion: the path (decimated points + times) is published on the model (TaxiPath / TaxiT0), the
--     server moves the root at ~15 Hz and every client re-samples it each frame (smooth on phones)
--   * money: the fare is decided here from the lane route length (GwangalliGameplayShared.taxiFare:
--     4,800원 flag fall, distance, 22-04 night surcharge, regulars discount) and locked at the start
--     of the ride; payments / cancel fees go through ctx.bank.post (audited) or ctx.ledger; a ride
--     is charged exactly once (state machine, no yield between the check and the write)
--   * edge cases: no money, no road nearby, all taxis busy, the caller walking away (re-route up to
--     3 times, then cancel), no-show / late cancel fee, the route blocked (teleport fallback), death /
--     respawn / leaving (leaving while paying still pays), several players calling at once (one taxi
--     each, TAXI_CALL.maxConcurrent in the world)
--   * no GwangalliNav (subset builds): the old road-slab kerb finder places the taxi and the ride
--     becomes a fade transfer
--   * VISIBILITY (bug "택시 타도 차가 안 보이는 경우"): the taxi model is PersistentPerPlayer and the
--     rider is added with Model:AddPersistentPlayer at booking, so StreamingEnabled never withholds
--     or streams out the car for its rider (it spawns ~420 studs away and the ride / skip moves the
--     player hundreds of studs at once). Before the rider is seated the server asks the client to
--     confirm it has the model (TaxiState {askSeen}; client -> TaxiCall "seen"; 3 s timeout, then it
--     seats anyway), RequestStreamAroundAsync runs before every teleport-like move and ahead of the
--     moving taxi, and the 1 Hz watchdog re-welds / re-seats a rider whose seat weld went missing.
--
-- REMOTES: TaxiCall RemoteFunction (created here) client -> server (op, payload?) -> result table
--   {ok, code?, message?, ...}. ops: hello | quote {dest? | x,z | nearby} | book {same, pay?} | cancel |
--   board | skip | pay {method = "card"|"cash"} | rate {rideId, stars 1..5} | setDest {dest} | state |
--   seen {ride} (client: "I have the taxi model")
-- TaxiState RemoteEvent (existing) server -> client {state = coming|arrived|riding|paying|done|
--   cancelled, eta?, fare?, destination?, boarded?, reason?, fee?, askSeen?, job = view (see viewOf)}

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local Taxi = {}

local ctx: any
local G: any
local Util: any
local Profiles: any
local T: any
local D: any -- TaxiDispatch
local graph: any = nil -- lane graph (nil: no GwangalliNav -> slab fallback)
local navState = "loading" -- loading | ready | none

local CALL = {
	company = "광안콜택시",
	number = "1588-5252",
	dispatcher = "상담원 이수진",
	approachWant = 420, -- studs of road the taxi drives to reach the caller
	approachMin = 170,
	pickupRadius = 260, -- a lane within this many studs of the caller
	pickupFallback = { 600, 1200, 2400, 6000 }, -- [택시 수정] no lane that close: widen the search, the caller walks to the kerb
	dropRadius = 340,
	cancelGrace = 10, -- seconds after booking: free cancel
	cancelFee = 1000,
	noShowFee = 1000,
	waitSeconds = 90, -- at the kerb, then the driver leaves (no-show fee)
	destWaitSeconds = 60, -- seated without a destination
	payTimeout = 25, -- then the fare is paid automatically (card, else cash)
	skipAfter = 5,
	rideMaxSeconds = 75,
	rideMaxScale = 2,
	maxConcurrent = 8,
	replanDistance = 110,
	maxReplans = 3,
	walkAway = 400,
	rateWindow = 300,
	bookCooldown = 3,
	motionHz = 15,
}
Taxi.CALL = CALL

-------------------------------------------------------------------------------------------------
-- Road slabs (fallback when the place has no GwangalliNav)
-------------------------------------------------------------------------------------------------
type Slab = { part: BasePart, cf: CFrame, longIsX: boolean, halfLen: number, halfWid: number, halfY: number, axis: Vector3 }
type RoadPt = { slab: Slab, s: number, pos: Vector3 }
local CELL = 64
local cells: { [string]: { RoadPt } } = {}
local slabCount = 0
local roadReady = false

local function cellKey(cx: number, cz: number): string
	return tostring(cx) .. "," .. tostring(cz)
end

local function slabPoint(slab: Slab, s: number, lat: number): Vector3
	local loc = if slab.longIsX then Vector3.new(s, slab.halfY, lat) else Vector3.new(lat, slab.halfY, s)
	return slab.cf:PointToWorldSpace(loc)
end

local function addSlab(part: BasePart)
	local size = part.Size
	local longIsX = size.X >= size.Z
	local halfLen = (if longIsX then size.X else size.Z) / 2
	local halfWid = (if longIsX then size.Z else size.X) / 2
	local axisW = part.CFrame:VectorToWorldSpace(if longIsX then Vector3.xAxis else Vector3.zAxis)
	local flatAxis = Vector3.new(axisW.X, 0, axisW.Z)
	if flatAxis.Magnitude < 0.5 then
		return
	end
	local slab: Slab = { part = part, cf = part.CFrame, longIsX = longIsX, halfLen = halfLen, halfWid = halfWid, halfY = size.Y / 2, axis = flatAxis.Unit }
	slabCount += 1
	local margin = math.min(8, halfLen)
	local s = -halfLen + margin
	repeat
		local pos = slabPoint(slab, s, 0)
		local key = cellKey(math.floor(pos.X / CELL), math.floor(pos.Z / CELL))
		local list = cells[key]
		if not list then
			list = {}
			cells[key] = list
		end
		table.insert(list, { slab = slab, s = s, pos = pos })
		s += 24
	until s > halfLen - margin + 0.01
end

local function isRoadSlab(inst: Instance, strict: boolean): boolean
	if inst.ClassName ~= "Part" then
		return false
	end
	local part = inst :: Part
	local name = part.Name
	if strict then
		if string.sub(name, 1, 4) ~= "Road" or string.find(name, "Uphill", 1, true) or name == "Road_Lower" then
			return false
		end
	end
	if part.Material ~= Enum.Material.Asphalt then
		return false
	end
	local s = part.Size
	local minH, maxH = math.min(s.X, s.Z), math.max(s.X, s.Z)
	if s.Y > 2 or minH < (if strict then 12 else 14) or maxH < (if strict then 30 else 40) then
		return false
	end
	return part.CFrame.UpVector.Y >= 0.985
end

local function buildRoads()
	local roots: { Instance } = {}
	local map = workspace:FindFirstChild("Gwangalli")
	if map then
		for _, n in { "roads", "bridge" } do
			local m = map:FindFirstChild(n)
			if m then
				table.insert(roots, m)
			end
		end
	end
	local count = 0
	for _, r in roots do
		for _, d in r:GetDescendants() do
			count += 1
			if count % 4000 == 0 then
				task.wait()
			end
			if isRoadSlab(d, true) then
				addSlab(d :: BasePart)
			end
		end
	end
	if slabCount == 0 then
		for _, d in workspace:GetDescendants() do
			count += 1
			if count % 4000 == 0 then
				task.wait()
			end
			if isRoadSlab(d, false) then
				addSlab(d :: BasePart)
			end
		end
	end
	roadReady = true
end

local function nearestRoad(pos: Vector3, maxDist: number): (Slab?, number)
	local best: RoadPt? = nil
	local bestScore = math.huge
	local r = math.ceil(maxDist / CELL)
	local cx, cz = math.floor(pos.X / CELL), math.floor(pos.Z / CELL)
	for dx = -r, r do
		for dz = -r, r do
			local list = cells[cellKey(cx + dx, cz + dz)]
			if list then
				for _, pt in list do
					local d = pt.pos - pos
					local score = math.sqrt(d.X * d.X + d.Z * d.Z) + math.abs(d.Y) * 1.5
					if score < bestScore then
						best, bestScore = pt, score
					end
				end
			end
		end
	end
	if not best or bestScore > maxDist or not best.slab.part:IsDescendantOf(workspace) then
		return nil, 0
	end
	local slab = best.slab
	local loc = slab.cf:PointToObjectSpace(pos)
	local s = if slab.longIsX then loc.X else loc.Z
	local margin = math.min(9, slab.halfLen)
	return slab, math.clamp(s, -slab.halfLen + margin, slab.halfLen - margin)
end

type Kerb = { slab: Slab, s: number, lat: number, dir: number, cf: CFrame }

local function kerbAt(slab: Slab, s: number, toward: Vector3): Kerb
	local center = slabPoint(slab, s, 0)
	local latW = slab.cf:VectorToWorldSpace(if slab.longIsX then Vector3.zAxis else Vector3.xAxis)
	local to = toward - center
	local latSign = if to:Dot(latW) >= 0 then 1 else -1
	local lat = if slab.halfWid >= 8 then latSign * (slab.halfWid - 5) else 0
	local dir = if slab.axis:Cross(Vector3.yAxis):Dot(to) >= 0 then 1 else -1
	local ground = slabPoint(slab, s, lat)
	local pos = ground + Vector3.new(0, 0.5, 0)
	return { slab = slab, s = s, lat = lat, dir = dir, cf = CFrame.lookAt(pos, pos + slab.axis * dir) }
end

local function alongKerb(k: Kerb, dist: number): CFrame
	local slab = k.slab
	local margin = math.min(6, slab.halfLen)
	local s2 = math.clamp(k.s + k.dir * dist, -slab.halfLen + margin, slab.halfLen - margin)
	local pos = slabPoint(slab, s2, k.lat) + Vector3.new(0, 0.5, 0)
	return CFrame.lookAt(pos, pos + slab.axis * k.dir)
end

-------------------------------------------------------------------------------------------------
-- Template (the map's taxi, welded to an invisible anchored root) + driver / hazards / plates
-------------------------------------------------------------------------------------------------
local template: Model? = nil
local seatLocal = CFrame.new(1.3, 1.9, 2.4)
local taxiFolder: Folder? = nil
local ROOT_LIFT = 0.5 -- root height above the road surface (the template root sits 0.5 above its lowest point)

-- PersistentPerPlayer: the model streams as one unit and is always replicated to the players
-- added with AddPersistentPlayer (the rider); Atomic is the fallback on an engine without it.
local function setStreamingMode(model: Model)
	local ok = pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.PersistentPerPlayer
	end)
	if not ok then
		pcall(function()
			model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		end)
	end
end

-- The rider always has the car, wherever it drives (pcall: Studio builds / test engines without the API).
local function pinToRider(model: Model, player: Player)
	pcall(function()
		(model :: any):AddPersistentPlayer(player)
	end)
end

local function unpinRider(model: Model, player: Player)
	pcall(function()
		(model :: any):RemovePersistentPlayer(player)
	end)
end

local function weldAll(model: Model, root: BasePart)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p ~= root then
			local w = Instance.new("Weld")
			w.Name = "TaxiWeld"
			w.Part0 = root
			w.Part1 = p
			w.C0 = root.CFrame:ToObjectSpace(p.CFrame)
			w.C1 = CFrame.new()
			w.Parent = p
			p.Anchored = false
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
			p.Massless = true
		end
	end
end

local function makeRoot(model: Model, cf: CFrame): BasePart
	local root = Instance.new("Part")
	root.Name = "TaxiRoot"
	root.Size = Vector3.new(2, 1, 2)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.CastShadow = false
	root.CFrame = cf
	root.Parent = model
	return root
end

local function newPart(model: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	if shape then
		p.Shape = shape
	end
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function buildFallbackTaxi(): Model
	local m = Instance.new("Model")
	m.Name = "GwangalliTaxi"
	local root = makeRoot(m, CFrame.new(0, 0.5, 0))
	local orange = Color3.fromRGB(236, 128, 36)
	newPart(m, "Body", Vector3.new(6.2, 2.2, 15.4), CFrame.new(0, 2.3, 0), orange, Enum.Material.SmoothPlastic)
	newPart(m, "Cabin", Vector3.new(5.6, 1.9, 7.4), CFrame.new(0, 4.35, 0.8), Color3.fromRGB(28, 34, 40), Enum.Material.Glass)
	newPart(m, "Roof", Vector3.new(5.4, 0.3, 6.6), CFrame.new(0, 5.45, 0.9), orange, Enum.Material.SmoothPlastic)
	local sign = newPart(m, "TaxiSign", Vector3.new(2.6, 0.8, 1.1), CFrame.new(0, 6.0, 0.9), Color3.fromRGB(255, 214, 40), Enum.Material.Neon)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.CanvasSize = Vector2.new(120, 40)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "개인택시"
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = Color3.fromRGB(30, 30, 30)
	label.Parent = sg
	sg.Parent = sign
	for _, x in { -3.0, 3.0 } do
		for _, z in { -4.8, 4.8 } do
			newPart(m, "Tyre", Vector3.new(1.0, 2.4, 2.4), CFrame.new(x, 1.2, z) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(28, 28, 30), Enum.Material.Rubber, Enum.PartType.Cylinder)
		end
	end
	newPart(m, "SeatCushion", Vector3.new(2.2, 0.6, 2.2), CFrame.new(-1.3, 1.9, -1.4), Color3.fromRGB(40, 40, 44), Enum.Material.Fabric)
	newPart(m, "SeatCushion", Vector3.new(2.2, 0.6, 2.2), CFrame.new(1.3, 1.9, 2.4), Color3.fromRGB(40, 40, 44), Enum.Material.Fabric)
	m.PrimaryPart = root
	return m
end

-- Local (root space) bounds of every part: {minX, maxX, minY, maxY, minZ, maxZ}.
local function localBounds(model: Model, root: BasePart): { number }
	local b = { math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge }
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p ~= root and p.Transparency < 0.95 then
			local l = root.CFrame:PointToObjectSpace(p.Position)
			b[1], b[2] = math.min(b[1], l.X), math.max(b[2], l.X)
			b[3], b[4] = math.min(b[3], l.Y), math.max(b[4], l.Y)
			b[5], b[6] = math.min(b[5], l.Z), math.max(b[6], l.Z)
		end
	end
	if b[1] == math.huge then
		return { -3, 3, 0, 5, -7.5, 7.5 }
	end
	return b
end

-- Driver figure (front-left seat), hazard lamps, plate labels, horn. All anchored parts here; the
-- template is welded afterwards.
local function decorate(model: Model, root: BasePart)
	local b = localBounds(model, root)
	local driverLocal = CFrame.new(-1.3, 1.9, -1.2)
	local bestScore = -math.huge
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Name == "SeatCushion" then
			local l = root.CFrame:PointToObjectSpace(p.Position)
			local score = -l.Z * 10 - l.X -- front (-Z) and left (-X)
			if score > bestScore then
				bestScore = score
				driverLocal = CFrame.new(l.X, l.Y, l.Z)
			end
		end
	end
	local skin = Color3.fromRGB(234, 192, 160)
	local shirt = Color3.fromRGB(150, 196, 236) -- 하늘색 기사님 셔츠
	local driver = Instance.new("Model")
	driver.Name = "TaxiDriver"
	driver.Parent = model
	local function at(off: Vector3): CFrame
		return root.CFrame * driverLocal * CFrame.new(off)
	end
	newPart(driver, "DriverTorso", Vector3.new(1.7, 1.8, 0.9), at(Vector3.new(0, 1.35, 0.35)), shirt, Enum.Material.SmoothPlastic)
	local head = newPart(driver, "DriverHead", Vector3.new(1.15, 1.2, 1.15), at(Vector3.new(0, 2.85, 0.25)), skin, Enum.Material.SmoothPlastic)
	head.Shape = Enum.PartType.Ball
	newPart(driver, "DriverHair", Vector3.new(1.2, 0.45, 1.2), at(Vector3.new(0, 3.35, 0.32)), Color3.fromRGB(46, 40, 38), Enum.Material.SmoothPlastic)
	newPart(driver, "DriverArmL", Vector3.new(0.5, 1.5, 0.5), at(Vector3.new(-1.05, 1.3, 0.2)), shirt, Enum.Material.SmoothPlastic)
	-- the waving arm hangs from a shoulder pivot so the client can swing it (attribute WaveArm)
	local arm = newPart(driver, "DriverArmR", Vector3.new(0.5, 1.5, 0.5), at(Vector3.new(1.05, 1.3, 0.2)), shirt, Enum.Material.SmoothPlastic)
	arm:SetAttribute("WaveArm", true)
	newPart(driver, "DriverHand", Vector3.new(0.45, 0.45, 0.45), at(Vector3.new(1.05, 0.4, 0.2)), skin, Enum.Material.SmoothPlastic):SetAttribute("WaveHand", true)
	-- hazard lamps at the four corners (amber neon, hidden until the client blinks them)
	local amber = Color3.fromRGB(255, 170, 30)
	for i, c in { { b[1] + 0.25, b[5] + 0.3 }, { b[2] - 0.25, b[5] + 0.3 }, { b[1] + 0.25, b[6] - 0.3 }, { b[2] - 0.25, b[6] - 0.3 } } do
		local lamp = newPart(model, "HazardLamp", Vector3.new(0.5, 0.35, 0.3), root.CFrame * CFrame.new(c[1], b[3] + 2.1, c[2]), amber, Enum.Material.Neon)
		lamp.Transparency = 1
		lamp:SetAttribute("HazardLamp", i)
	end
	-- plates: a label on the outward face of PlateFront / PlateRear (text set per taxi)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and (p.Name == "PlateFront" or p.Name == "PlateRear") then
			local want = if p.Name == "PlateFront" then root.CFrame.LookVector else -root.CFrame.LookVector
			local bestFace, bestDot = Enum.NormalId.Front, -2
			for _, face in Enum.NormalId:GetEnumItems() do
				local n = p.CFrame:VectorToWorldSpace(Vector3.FromNormalId(face))
				local dot = n:Dot(want)
				if dot > bestDot then
					bestFace, bestDot = face, dot
				end
			end
			local sg = Instance.new("SurfaceGui")
			sg.Name = "PlateGui"
			sg.Face = bestFace
			sg.CanvasSize = Vector2.new(200, 50)
			sg.LightInfluence = 1
			sg.MaxDistance = 80
			local bg = Instance.new("Frame")
			bg.Size = UDim2.fromScale(1, 1)
			bg.BackgroundColor3 = Color3.fromRGB(250, 206, 40) -- 영업용 노란 번호판
			bg.BorderSizePixel = 0
			bg.Parent = sg
			local tl = Instance.new("TextLabel")
			tl.Name = "PlateText"
			tl.Size = UDim2.fromScale(1, 1)
			tl.BackgroundTransparency = 1
			tl.Text = "부산 00바 0000"
			tl.TextScaled = true
			tl.Font = Enum.Font.GothamBold
			tl.TextColor3 = Color3.fromRGB(20, 20, 24)
			tl.Parent = bg
			sg.Parent = p
		end
	end
	-- horn (built-in sound, pitched down into a short double beep)
	local horn = Instance.new("Sound")
	horn.Name = "Horn"
	horn.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	horn.PlaybackSpeed = 0.42
	horn.Volume = 0.9
	horn.RollOffMaxDistance = 160
	horn.Parent = root
end

local function findTaxiSource(): Model?
	local map = workspace:FindFirstChild("Gwangalli")
	local roads = map and map:FindFirstChild("roads")
	local candidates: { Model } = {}
	local function scan(root: Instance)
		local n = 0
		for _, d in root:GetDescendants() do
			n += 1
			if n % 4000 == 0 then
				task.wait()
			end
			if d:IsA("Model") and d:GetAttribute("VehicleKind") == "taxi" then
				table.insert(candidates, d)
				if d.Parent and d.Parent.Name == "TrafficVehicles" then
					return
				end
			end
		end
	end
	if roads then
		scan(roads)
	end
	if #candidates == 0 then
		scan(workspace)
	end
	for _, c in candidates do
		if c.Parent and c.Parent.Name == "TrafficVehicles" then
			return c
		end
	end
	return candidates[1]
end

local function prepareTemplate()
	local src = findTaxiSource()
	local model: Model
	local root: BasePart
	if src then
		model = src:Clone()
		for _, x in model:GetDescendants() do
			if x:IsA("BaseScript") or x:IsA("ProximityPrompt") or x:IsA("ClickDetector") or x:IsA("Sound") then
				x:Destroy()
			end
		end
		local parts: { BasePart } = {}
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				table.insert(parts, p)
			end
		end
		if #parts == 0 then
			model:Destroy()
			model = buildFallbackTaxi()
			root = model.PrimaryPart :: BasePart
		else
			local minY = math.huge
			local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
			local front, rear
			for _, p in parts do
				local pos = p.Position
				local hy = 0.5 * (math.abs(p.CFrame.RightVector.Y) * p.Size.X + math.abs(p.CFrame.UpVector.Y) * p.Size.Y + math.abs(p.CFrame.LookVector.Y) * p.Size.Z)
				minY = math.min(minY, pos.Y - hy)
				minX, maxX = math.min(minX, pos.X), math.max(maxX, pos.X)
				minZ, maxZ = math.min(minZ, pos.Z), math.max(maxZ, pos.Z)
				if p.Name == "Grille" or (p.Name == "FrontBumper" and not front) then
					front = p
				elseif p.Name == "RearBumper" or (p.Name == "TrunkLid" and not rear) then
					rear = p
				end
			end
			local center = Vector3.new((minX + maxX) / 2, minY + ROOT_LIFT, (minZ + maxZ) / 2)
			local fwd: Vector3
			if front and rear then
				local d = front.Position - rear.Position
				fwd = Vector3.new(d.X, 0, d.Z)
			else
				fwd = if maxX - minX >= maxZ - minZ then Vector3.xAxis else Vector3.zAxis
			end
			if fwd.Magnitude < 0.1 then
				fwd = Vector3.zAxis
			end
			root = makeRoot(model, D.cframe(center, fwd.Unit))
			model.PrimaryPart = root
		end
	else
		model = buildFallbackTaxi()
		root = model.PrimaryPart :: BasePart
	end
	-- rear-right cushion = the passenger seat on the kerb side
	local bestSeat: BasePart? = nil
	local bestScore = -math.huge
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Name == "SeatCushion" then
			local loc = root.CFrame:PointToObjectSpace(p.Position)
			local score = loc.Z * 10 + loc.X
			if score > bestScore then
				bestSeat, bestScore = p, score
			end
		end
	end
	if bestSeat then
		local loc = root.CFrame:PointToObjectSpace(bestSeat.Position)
		seatLocal = CFrame.new(loc.X, loc.Y + 1.7, loc.Z)
	end
	pcall(decorate, model, root)
	weldAll(model, root)
	model.Name = "GwangalliTaxi"
	model:SetAttribute("VehicleKind", "taxi_service")
	setStreamingMode(model)
	local holder = ServerStorage:FindFirstChild("GwangalliTaxiTemplate")
	if not holder then
		holder = Instance.new("Folder")
		holder.Name = "GwangalliTaxiTemplate"
		holder.Parent = ServerStorage
	end
	model.Parent = holder
	template = model
end

-------------------------------------------------------------------------------------------------
-- Ground heights / kerb offset (raycasts against the built road)
-------------------------------------------------------------------------------------------------
local rayParams: RaycastParams? = nil
local vehicleFolders: { Instance } = {}

-- Include-filter on the built map (roads, kerbs, pavements); vehicles are skipped after the hit.
local function rays(): RaycastParams
	if rayParams then
		return rayParams
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { workspace:FindFirstChild("Gwangalli") or workspace }
	rp.IgnoreWater = true
	pcall(function()
		(rp :: any).RespectCanCollide = true
	end)
	rayParams = rp
	return rp
end

local function isVehiclePart(inst: Instance): boolean
	local node: Instance? = inst.Parent
	for _ = 1, 4 do
		if not node then
			return false
		end
		if node:GetAttribute("VehicleKind") ~= nil then
			return true
		end
		for _, f in vehicleFolders do
			if node == f then
				return true
			end
		end
		node = node.Parent
	end
	return false
end

-- Road surface height at p (nil when nothing solid is below within reach).
local function surfaceAt(p: Vector3, rp: RaycastParams): number?
	local ok, hit = pcall(function()
		return workspace:Raycast(Vector3.new(p.X, p.Y + 10, p.Z), Vector3.new(0, -26, 0), rp)
	end)
	if ok and hit and hit.Normal.Y > 0.6 and hit.Position.Y < p.Y + 3.5 and not isVehiclePart(hit.Instance) then
		return hit.Position.Y
	end
	return nil
end

-- Studs to shift right from the lane centre so the car stops against the kerb (0 = no kerb found:
-- stop in the lane).
local function kerbOffset(point: Vector3, dir: Vector3): number
	local rp = rays()
	local right = D.rightOf(dir)
	local road = surfaceAt(point, rp) or point.Y
	for k = 2, 13 do
		local y = surfaceAt(point + right * k, rp)
		if y and y > road + 0.25 then
			return math.clamp(k - 3.9, 0, 6)
		end
	end
	return 0
end

local function heightFn(): (Vector3) -> number?
	local rp = rays()
	return function(p: Vector3): number?
		return surfaceAt(p, rp)
	end
end

-------------------------------------------------------------------------------------------------
-- Destinations (server list, tag Destination)
-------------------------------------------------------------------------------------------------
local destParts: { [Instance]: string } = {}

local function destNameOf(inst: Instance): string
	local n = inst:GetAttribute(G.Attr.DisplayName)
	if type(n) == "string" and n ~= "" then
		return n
	end
	return inst.Name
end

local function trackDest(inst: Instance)
	if inst:IsA("BasePart") then
		destParts[inst] = destNameOf(inst)
	end
end

local function resolveDest(name: any): (string?, BasePart?)
	local n = Util.str(name, 120)
	if not n then
		return nil, nil
	end
	local part = ctx.dest(n)
	if not part then
		local base = string.match(n, "^(.-) %(%d+%)$")
		if base then
			part = ctx.dest(base)
			n = base
		end
	end
	if not part then
		return nil, nil
	end
	return n, part
end

-- Nearest destination name to p within maxDist (studs), and its distance.
local function nearestDestName(p: Vector3, maxDist: number): (string?, number)
	local best, bestD = nil, maxDist
	for part, name in destParts do
		if part.Parent and part:IsDescendantOf(workspace) then
			local d = (part.Position - p)
			local dd = math.sqrt(d.X * d.X + d.Z * d.Z)
			if dd < bestD then
				best, bestD = name, dd
			end
		end
	end
	return best, bestD
end

local function placeLabel(p: Vector3): string
	local name = nearestDestName(p, 260)
	if name then
		return name .. " 근처"
	end
	return "현재 위치"
end

-------------------------------------------------------------------------------------------------
-- Jobs
-------------------------------------------------------------------------------------------------
type Motion = { pts: { Vector3 }, times: { number }, t0: number, total: number, length: number, done: boolean, onDone: (() -> ())?, serial: number }
type Job = {
	id: string,
	player: Player,
	model: Model,
	root: BasePart,
	state: string, -- coming | arrived | riding | paying | leaving
	driver: { [string]: any },
	dest: string?, -- Destination name (nil: map point / not chosen yet)
	destLabel: string?,
	destPos: Vector3?,
	fare: number?,
	lines: { [string]: any }?,
	pickupLoc: any?, -- lane location where the taxi stops (nil: slab fallback)
	pickupPos: Vector3, -- caller position the pickup was planned for
	walkTo: number?, -- [택시 수정] studs the caller walks to a far kerb (nil: normal pickup)
	stopCF: CFrame?, -- where the taxi stands at the kerb
	kerbOff: number,
	dropLoc: any?,
	dropKerb: number,
	motion: Motion?,
	boarded: boolean,
	character: Model?,
	weld: Weld?,
	prompt: ProximityPrompt?,
	bookedAt: number,
	arriveAt: number,
	waitUntil: number,
	rideStart: number,
	rideEnd: number,
	skipAt: number,
	payUntil: number,
	replans: number,
	token: number,
	paid: boolean,
	skipping: boolean,
	conns: { RBXScriptConnection },
	serial: number,
	seenAt: number?, -- server time when the rider's client confirmed it has the model (op "seen")
	streamAt: number?, -- next look-ahead RequestStreamAroundAsync while riding
	boarding: boolean?, -- board() is waiting for the client's "seen" ack
	reseats: number?, -- watchdog re-seat count (diagnostics)
}

local jobs: { [Player]: Job } = {}
local leavingModels: { [Model]: boolean } = {}
local lastRide: { [Player]: { [string]: any } } = {}
local recentDests: { [Player]: { string } } = {}
local rideSeq = 0
local rng = Random.new()
local auditRing: { any } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function send(player: Player, payload: any)
	if player.Parent == Players then
		ctx.remotes.TaxiState:FireClient(player, payload)
	end
end

local function activeCount(): number
	local n = 0
	for _ in jobs do
		n += 1
	end
	for m in leavingModels do
		if m.Parent then
			n += 1
		else
			leavingModels[m] = nil
		end
	end
	return n
end

local function clockNow(): number
	local ok, env = pcall(ctx.env)
	return if ok and env then env.clock else 12
end

local function popularity(player: Player): number
	local d = Profiles.get(player)
	return d and d.stats and d.stats.popularity or 0
end

local function audit(player: Player, kind: string, data: { [string]: any })
	local rec = { t = os.time(), uid = player.UserId, kind = kind }
	for k, v in data do
		rec[k] = v
	end
	table.insert(auditRing, rec)
	while #auditRing > 300 do
		table.remove(auditRing, 1)
	end
	if type(ctx.audit) == "function" then
		pcall(ctx.audit, player, "taxi", rec)
	end
end

-- The one money write of this module: -amount from account, audited (bank.post) when available.
local function charge(player: Player, account: string, amount: number, label: string, ref: string, place: string?): boolean
	if amount <= 0 then
		return true
	end
	local d = Profiles.get(player)
	if not d or (d[account] or 0) < amount then
		return false
	end
	local ok = false
	local bank = ctx.bank
	if type(bank) == "table" and type(bank.post) == "function" then
		local okCall, res = pcall(bank.post, player, account, -amount, label, { memo = CALL.company, ref = ref, place = place, peer = CALL.company })
		ok = okCall and res == true
	else
		ok = ctx.ledger(player, account, -amount, label, true) == true
	end
	if ok then
		audit(player, "charge", { account = account, amount = amount, label = label, ref = ref })
	end
	return ok
end

-- Pays `amount` the best way: preferred account, then the other, then split (cash first). Returns
-- paid amount + the account label ("card" | "cash" | "split"). Never more than the player has.
local function chargeAuto(player: Player, amount: number, label: string, ref: string, place: string?, prefer: string?): (number, string)
	local d = Profiles.get(player)
	if not d or amount <= 0 then
		return 0, "none"
	end
	local first = if prefer == "cash" then "cash" else "bank"
	local second = if first == "bank" then "cash" else "bank"
	if (d[first] or 0) >= amount and charge(player, first, amount, label, ref, place) then
		return amount, if first == "bank" then "card" else "cash"
	end
	if (d[second] or 0) >= amount and charge(player, second, amount, label, ref, place) then
		return amount, if second == "bank" then "card" else "cash"
	end
	local cash = math.min(amount, math.max(0, math.floor(d.cash or 0)))
	local paid = 0
	if cash > 0 and charge(player, "cash", cash, label .. " (현금)", ref, place) then
		paid += cash
	end
	local rest = math.min(amount - paid, math.max(0, math.floor(d.bank or 0)))
	if rest > 0 and charge(player, "bank", rest, label .. " (카드)", ref, place) then
		paid += rest
	end
	return paid, "split"
end

local function viewOf(job: Job): { [string]: any }
	local dr = job.driver
	local m = job.motion
	return {
		id = job.id,
		state = job.state,
		driver = dr.name,
		driverTitle = dr.title,
		rating = dr.rating,
		years = dr.years,
		car = dr.car,
		color = dr.color,
		plate = dr.plate,
		phone = dr.phone,
		destination = job.destLabel,
		destName = job.dest,
		fare = job.fare,
		lines = job.lines,
		boarded = job.boarded,
		needDest = job.boarded and job.destLabel == nil or nil,
		pickup = if job.stopCF then job.stopCF.Position else job.pickupPos,
		dropoff = job.destPos,
		arriveAt = job.arriveAt,
		waitUntil = job.waitUntil,
		rideStart = job.rideStart,
		rideEnd = job.rideEnd,
		rideLength = if job.state == "riding" and m then m.length else nil,
		skipAt = job.skipAt,
		payUntil = job.payUntil,
		freeCancelUntil = job.bookedAt + CALL.cancelGrace,
		cancelFee = CALL.cancelFee,
		now = now(),
		model = job.model,
		serial = job.serial,
		company = CALL.company,
		number = CALL.number,
	}
end

local function sendState(job: Job, extra: { [string]: any }?)
	local legacy = job.state
	if legacy == "leaving" then
		legacy = "done"
	end
	local eta: number? = nil
	if job.state == "coming" then
		eta = math.max(0, math.ceil(job.arriveAt - now()))
	elseif job.state == "riding" then
		eta = math.max(0, math.ceil(job.rideEnd - now()))
	end
	local payload: { [string]: any } = { state = legacy, eta = eta, fare = job.fare, destination = job.destLabel, boarded = job.boarded or nil, job = viewOf(job) }
	if extra then
		for k, v in extra do
			payload[k] = v
		end
	end
	send(job.player, payload)
end

local function sms(player: Player, text: string)
	if type(ctx.sendMessage) == "function" then
		pcall(ctx.sendMessage, player, "taxi", text)
	end
end

local function newRideId(): string
	rideSeq += 1
	local t = os.date("!*t", os.time() + 9 * 3600)
	return string.format("TX%02d%02d-%04d", t.month, t.day, rideSeq % 10000)
end

-------------------------------------------------------------------------------------------------
-- Motion
-------------------------------------------------------------------------------------------------
local function applyMotion(job: Job, t: number)
	local m = job.motion
	if not m or not job.root.Parent then
		return
	end
	local p, dir = D.sample(m.pts, m.times, t)
	job.root.CFrame = D.cframe(p + Vector3.new(0, ROOT_LIFT, 0), dir)
end

local function setMotion(job: Job, path: any, t0: number, onDone: (() -> ())?)
	job.serial += 1
	local m: Motion = { pts = path.pts, times = path.times, t0 = t0, total = path.total, length = path.length, done = false, onDone = onDone, serial = job.serial }
	job.motion = m
	local model = job.model
	model:SetAttribute("TaxiPath", D.encode(path.pts, path.times))
	model:SetAttribute("TaxiT0", t0)
	model:SetAttribute("TaxiSerial", job.serial)
	applyMotion(job, now() - t0)
end

local function retimeMotion(job: Job, t0: number)
	local m = job.motion
	if not m then
		return
	end
	m.t0 = t0
	job.model:SetAttribute("TaxiT0", t0)
	applyMotion(job, now() - t0)
end

local motionAcc = 0
local function motionStep(dt: number)
	motionAcc += dt
	if motionAcc < 1 / CALL.motionHz then
		return
	end
	motionAcc = 0
	local tNow = now()
	for _, job in jobs do
		local m = job.motion
		if m and not m.done then
			local t = tNow - m.t0
			applyMotion(job, math.min(t, m.total))
			if t >= m.total then
				m.done = true
				local fn = m.onDone
				if fn then
					task.defer(function()
						local ok, err = pcall(fn)
						if not ok then
							warn("[GwangalliGameplay] taxi motion end failed: " .. tostring(err))
						end
					end)
				end
			end
		end
	end
	for model in leavingModels do
		local m = model:GetAttribute("TaxiLeaveUntil")
		if model.Parent and type(m) == "number" and tNow > m then
			model:Destroy()
			leavingModels[model] = nil
		end
	end
end

-- Server-side sampler for a leaving taxi (it is no longer in `jobs`).
local function driveAway(job: Job)
	local model = job.model
	if not model.Parent then
		return
	end
	local pts: { Vector3 }
	local offset = 0
	local atDrop = job.state == "paying" or job.state == "leaving"
	local from = if atDrop then job.dropLoc else job.pickupLoc
	local cur = job.root.Position - Vector3.new(0, ROOT_LIFT, 0)
	if graph and from and (from.point - cur).Magnitude < 14 then
		-- from the lane centre next to the kerb spot; the pull-out blends from the kerb back in
		pts = D.forward(graph, from, 260)
		offset = if atDrop then job.dropKerb else job.kerbOff
	else
		local look = job.root.CFrame.LookVector
		pts = { cur, cur + Vector3.new(look.X, 0, look.Z).Unit * 220 }
	end
	local path = D.buildPath(pts, { cruise = 34, v0 = 0, v1 = 26, pullOut = { offset = offset, len = 22 }, heights = heightFn() })
	model:SetAttribute("TaxiHazard", false)
	if not path then
		model:Destroy()
		return
	end
	-- the lateral pull-out above shifts from the kerb back to the lane: start point = current spot
	local t0 = now() + 0.6
	model:SetAttribute("TaxiPath", D.encode(path.pts, path.times))
	model:SetAttribute("TaxiT0", t0)
	model:SetAttribute("TaxiSerial", (model:GetAttribute("TaxiSerial") or 0) + 1)
	model:SetAttribute("TaxiLeaveUntil", t0 + path.total + 0.5)
	model:SetAttribute("TaxiState", "leaving")
	leavingModels[model] = true
	-- server copy of the root motion for the leaving car
	local root = job.root
	task.spawn(function()
		while model.Parent and root.Parent do
			local t = now() - t0
			local p, dir = D.sample(path.pts, path.times, t)
			root.CFrame = D.cframe(p + Vector3.new(0, ROOT_LIFT, 0), dir)
			if t > path.total then
				break
			end
			task.wait(1 / CALL.motionHz)
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- Seating
-------------------------------------------------------------------------------------------------
local function unseat(job: Job, placeBeside: boolean)
	local player = job.player
	if job.weld then
		job.weld:Destroy()
		job.weld = nil
	end
	if job.boarded then
		job.boarded = false
		local character, humanoid, root = Util.alive(player)
		if character ~= job.character then
			character, humanoid, root = nil, nil, nil
		end
		if humanoid then
			humanoid.Sit = false
		end
		if root then
			pcall(function()
				root:SetNetworkOwner(player)
			end)
			if placeBeside and job.root.Parent then
				local cf = job.root.CFrame
				local side = cf * Vector3.new(5.5, -ROOT_LIFT, 1.5)
				local target = Util.safeAt(side, -cf.RightVector, Util.standHeight(humanoid :: Humanoid, root), Util.charactersIgnore({ job.model }))
				if not target then
					target = Util.safeAt(cf * Vector3.new(-5.5, -ROOT_LIFT, 1.5), cf.RightVector, Util.standHeight(humanoid :: Humanoid, root), Util.charactersIgnore({ job.model }))
				end
				if target then
					ctx.allowTeleport(player, 3)
					Util.placeCharacter(player, target)
				end
			end
		end
	end
	if player.Parent == Players then
		player:SetAttribute(G.Attr.InTaxi, nil)
	end
end

-- Removes the job; the car drives away (or vanishes). No money here.
local function release(job: Job, drive: boolean)
	job.token += 1
	if job.prompt then
		job.prompt:Destroy()
		job.prompt = nil
	end
	for _, c in job.conns do
		c:Disconnect()
	end
	table.clear(job.conns)
	if jobs[job.player] == job then
		jobs[job.player] = nil
	end
	job.motion = nil
	if drive and job.model.Parent then
		unpinRider(job.model, job.player) -- the leaving car may stream out like any other
		driveAway(job)
		job.state = "leaving"
	else
		job.state = "leaving"
		job.model:Destroy()
	end
end

local NO_PLACE = { respawn = true, died = true, left = true, gone = true }

local function cancelJob(job: Job, reason: string, message: string?, fee: number?)
	local player = job.player
	local wasBoarded = job.boarded
	if job.skipping then
		Util.clearFade(player)
	end
	unseat(job, wasBoarded and not NO_PLACE[reason])
	send(player, { state = "cancelled", reason = reason, fee = fee, job = viewOf(job) })
	if message then
		ctx.notify(player, "taxi", CALL.company, message)
	end
	audit(player, "cancel", { ride = job.id, reason = reason, fee = fee or 0 })
	release(job, reason ~= "gone" and reason ~= "left")
end

-- Late-cancel / no-show fee (cash first, then card; waived when the player has neither).
local function takeFee(job: Job, amount: number, label: string): number
	local paid = chargeAuto(job.player, amount, label, job.id, CALL.company, "cash")
	return paid
end

-------------------------------------------------------------------------------------------------
-- Path helpers
-------------------------------------------------------------------------------------------------
local function cruiseFor(len: number): number
	-- longer trips use the bigger roads' speed; 30 km/h streets feel right for short hops
	return math.clamp(34 + len / 250, 34, 52)
end

-- [택시 수정] flat studs from the caller to the stop, nil when the stop is close (normal kerb pickup)
local function walkDistance(pos: Vector3, stopCF: CFrame?): number?
	if not stopCF then
		return nil
	end
	local d = stopCF.Position - pos
	local dd = math.sqrt(d.X * d.X + d.Z * d.Z)
	return if dd > CALL.replanDistance then dd else nil
end

-- Pickup plan for a caller at `pos`: lane location + kerb offset + stop CFrame, or slab fallback.
local function planPickup(pos: Vector3): (any?, number, CFrame?)
	if graph then
		local loc = D.nearestLocation(graph, pos, { maxDist = CALL.pickupRadius, side = pos, kerbOnly = true })
		if not loc then
			-- [택시 수정] 큰길이 멀어도 호출 실패 대신 가장 가까운 차선으로 배차 (손님이 걸어감)
			for _, r in CALL.pickupFallback do
				loc = D.nearestLocation(graph, pos, { maxDist = r, side = pos, kerbOnly = true })
				if loc then
					break
				end
			end
		end
		if loc then
			local dir = D.edgeDir(graph, loc.edge)
			local off = kerbOffset(loc.point, dir)
			local p = loc.point + D.rightOf(dir) * off
			local y = surfaceAt(p, rays()) or p.Y
			return loc, off, D.cframe(Vector3.new(p.X, y + ROOT_LIFT, p.Z), dir)
		end
		return nil, 0, nil
	end
	local slab, s = nearestRoad(pos, T.searchRadius)
	if not slab then
		for _, r in CALL.pickupFallback do -- [택시 수정]
			slab, s = nearestRoad(pos, r)
			if slab then
				break
			end
		end
	end
	if slab then
		local k = kerbAt(slab, s, pos)
		return { kerb = k }, 0, k.cf
	end
	return nil, 0, nil
end

-- Destination plan: lane location near destPos (kerb side toward it) + kerb offset.
local function planDrop(destPos: Vector3): (any?, number)
	if not graph then
		return nil, 0
	end
	local loc = D.nearestLocation(graph, destPos, { maxDist = CALL.dropRadius, side = destPos, kerbOnly = true })
	if not loc then
		return nil, 0
	end
	return loc, kerbOffset(loc.point, D.edgeDir(graph, loc.edge))
end

-- Road length from a pickup location to a destination (nil route = straight line x 1.35).
local function rideLength(pickupLoc: any?, pickupPos: Vector3, destPos: Vector3): (number, { Vector3 }?, any?, number)
	if graph and pickupLoc and pickupLoc.edge then
		local drop, dropKerb = planDrop(destPos)
		if drop then
			local pts, len = D.route(graph, pickupLoc, drop)
			if pts then
				return len, pts, drop, dropKerb
			end
		end
	end
	local d = destPos - pickupPos
	return math.sqrt(d.X * d.X + d.Z * d.Z) * 1.35, nil, nil, 0
end

-------------------------------------------------------------------------------------------------
-- Destination requests (validated)
-------------------------------------------------------------------------------------------------
type DestReq = { name: string?, label: string, pos: Vector3 }

local function finiteCoord(v: any): number?
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge or math.abs(v) > 20000 then
		return nil
	end
	return v
end

local function parseDest(player: Player, p: any, from: Vector3?): (DestReq?, string?)
	if type(p) ~= "table" then
		return nil, "dest"
	end
	local nameArg = p.dest
	if nameArg == nil then
		nameArg = p.name
	end
	if nameArg == nil then
		nameArg = p.destination
	end
	if nameArg ~= nil then
		local n, part = resolveDest(nameArg)
		if not n or not part then
			return nil, "dest"
		end
		return { name = n, label = n, pos = part.Position }, nil
	end
	if p.x ~= nil or p.z ~= nil then
		local x, z = finiteCoord(p.x), finiteCoord(p.z)
		if not x or not z then
			return nil, "dest"
		end
		local pos = Vector3.new(x, 6, z)
		if graph and not D.nearestLocation(graph, pos, { maxDist = CALL.dropRadius }) then
			return nil, "noroadDest"
		end
		local near = nearestDestName(pos, 200)
		return { name = nil, label = if near then near .. " 근처" else "지도에서 고른 곳", pos = pos }, nil
	end
	if p.nearby == true and from then
		-- a short hop: a destination 250-1100 studs away, the driver's pick
		local options: { { string } } = {}
		for part, name in destParts do
			if part.Parent and part:IsDescendantOf(workspace) then
				local d = part.Position - from
				local dd = math.sqrt(d.X * d.X + d.Z * d.Z)
				if dd >= 250 and dd <= 1100 then
					table.insert(options, { name })
				end
			end
		end
		if #options == 0 then
			for part, name in destParts do
				if part.Parent and (part.Position - from).Magnitude >= 150 then
					table.insert(options, { name })
				end
			end
		end
		if #options == 0 then
			return nil, "dest"
		end
		local pick = options[rng:NextInteger(1, #options)][1]
		local n, part = resolveDest(pick)
		if not n or not part then
			return nil, "dest"
		end
		return { name = n, label = n, pos = part.Position }, nil
	end
	return nil, "dest"
end

local MESSAGES = {
	bad = "요청을 처리할 수 없어요",
	rate = "잠시 후 다시 시도해 주세요",
	loading = "택시 회사 연결 중이에요. 잠시 후 다시 전화해 주세요",
	noroad = "근처에 차가 들어갈 수 있는 도로가 없어요. 큰길로 나가서 다시 불러 주세요",
	noroadDest = "그곳 근처에는 차가 들어갈 수 없어요",
	busy = "지금은 주변에 빈 차가 없어요. 잠시 후 다시 불러 주세요",
	money = "잔액이 부족해요",
	dest = "목적지를 찾을 수 없어요",
	active = "이미 배차된 택시가 있어요",
	none = "호출한 택시가 없어요",
	dead = "지금은 택시를 부를 수 없어요",
	profile = "프로필을 불러오는 중이에요",
	cooldown = "잠시 후 다시 불러 주세요",
	riding = "운행 중에는 취소할 수 없어요",
	state = "지금은 할 수 없어요",
	far = "택시에 조금 더 가까이 가 주세요",
	soon = "곧 도착해요",
	insufficient = "잔액이 부족해요",
	same = "이미 그 근처예요",
}

local function fail(code: string, extra: { [string]: any }?): { [string]: any }
	local r: { [string]: any } = { ok = false, code = code, message = MESSAGES[code] or MESSAGES.bad }
	if extra then
		for k, v in extra do
			r[k] = v
		end
	end
	return r
end

local function available(): (boolean, string?)
	if navState == "loading" or not template or (not graph and not roadReady) then
		return false, "loading"
	end
	if not graph and slabCount == 0 then
		return false, "noroad"
	end
	if activeCount() >= CALL.maxConcurrent then
		return false, "busy"
	end
	return true, nil
end

-------------------------------------------------------------------------------------------------
-- Quote
-------------------------------------------------------------------------------------------------
local function quote(player: Player, dest: DestReq, pickupLoc: any?, pickupPos: Vector3): { [string]: any }
	local len, _, _, _ = rideLength(pickupLoc, pickupPos, dest.pos)
	local lines = D.fareBreakdown(G, len, clockNow(), popularity(player))
	local d = Profiles.get(player)
	local secs = len / cruiseFor(len)
	return {
		ok = true,
		destName = dest.name,
		destination = dest.label,
		fare = lines.total,
		lines = lines,
		meters = math.floor(len * 0.3 + 0.5),
		rideSeconds = math.ceil(math.min(secs, CALL.rideMaxSeconds)),
		pickupEta = math.ceil(CALL.approachWant / 40 + 3),
		pickupLabel = placeLabel(pickupPos),
		canAfford = d ~= nil and G.canAfford(d, lines.total),
		cash = d and d.cash or 0,
		bank = d and d.bank or 0,
		night = lines.isNight,
	}
end

-------------------------------------------------------------------------------------------------
-- Arrival at the pickup / boarding
-------------------------------------------------------------------------------------------------
local startRide: (Job) -> ()

-- Puts the character on the rear seat: pivot into place, one Weld taxi root -> HumanoidRootPart
-- (the taxi root is anchored, so the whole character rides the server-moved root on every peer),
-- Humanoid.Sit for the pose. Also the watchdog's re-seat (an old weld is replaced).
local function seatCharacter(job: Job, character: Model, humanoid: Humanoid, root: BasePart)
	if job.weld then
		job.weld:Destroy()
		job.weld = nil
	end
	if humanoid.SeatPart then
		humanoid.Sit = false
		local sw = humanoid.SeatPart:FindFirstChild("SeatWeld")
		if sw then
			sw:Destroy()
		end
	end
	ctx.allowTeleport(job.player, 5)
	local seatCF = job.root.CFrame * seatLocal
	character:PivotTo(seatCF * root.CFrame:ToObjectSpace(character:GetPivot()))
	pcall(function()
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end)
	local weld = Instance.new("Weld")
	weld.Name = "GwangalliTaxiSeat"
	weld.Part0 = job.root
	weld.Part1 = root
	weld.C0 = seatLocal
	weld.C1 = CFrame.new()
	weld.Parent = job.root
	job.weld = weld
	job.character = character
	humanoid.Sit = true
end

-- Waits (<= timeout s) until the rider's client confirmed it has the taxi model ("seen" op). The
-- model is PersistentPerPlayer for the rider, so normally the ack is already there; a client that
-- never answers (old client, very slow phone) is seated anyway after the timeout.
local function awaitSeen(job: Job, timeout: number): boolean
	if job.seenAt and job.seenAt >= job.bookedAt then
		return true
	end
	local player = job.player
	pcall(player.RequestStreamAroundAsync, player, job.root.Position, 1)
	if jobs[player] ~= job then
		return false
	end
	sendState(job, { askSeen = true })
	local t0 = now()
	while now() - t0 < timeout do
		task.wait(0.1)
		if jobs[player] ~= job or job.state ~= "arrived" then
			return false
		end
		if job.seenAt and job.seenAt >= job.bookedAt then
			return true
		end
	end
	return false
end

local function board(job: Job): { [string]: any }
	if job.state ~= "arrived" or job.boarded or job.boarding then
		return fail("state")
	end
	local player = job.player
	local character, humanoid, root = Util.alive(player)
	if not character or not humanoid or not root then
		return fail("dead")
	end
	if (root.Position - job.root.Position).Magnitude > T.boardDistance + 6 then
		return fail("far")
	end
	-- the client must have the car before it is welded into it (yields <= 3 s)
	job.boarding = true
	local seen = awaitSeen(job, 3)
	job.boarding = false
	if jobs[player] ~= job or job.state ~= "arrived" or job.boarded then
		return fail("state")
	end
	character, humanoid, root = Util.alive(player)
	if not character or not humanoid or not root then
		return fail("dead")
	end
	if (root.Position - job.root.Position).Magnitude > T.boardDistance + 10 then
		return fail("far")
	end
	if not seen then
		warn(string.format("[GwangalliGameplay] taxi %s: %s boarded without the client's model ack", job.id, player.Name))
		audit(player, "blindboard", { ride = job.id })
	end
	seatCharacter(job, character, humanoid, root)
	job.boarded = true
	player:SetAttribute(G.Attr.InTaxi, true)
	if job.prompt then
		job.prompt.Enabled = false
	end
	job.model:SetAttribute("TaxiBoarded", true)
	table.insert(job.conns, humanoid.Died:Connect(function()
		if jobs[player] == job then
			cancelJob(job, "died", nil)
		end
	end))
	audit(player, "board", { ride = job.id })
	if job.destPos then
		startRide(job)
	else
		job.waitUntil = now() + CALL.destWaitSeconds
		sendState(job, { needDest = true })
	end
	return { ok = true, job = viewOf(job) }
end

local function addPrompt(job: Job)
	local att = Instance.new("Attachment")
	att.Name = "TaxiPromptPoint"
	att.Position = Vector3.new(2.6, 3.2, 1.2)
	att.Parent = job.root
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GwangalliTaxiPrompt"
	prompt.ActionText = "탑승"
	prompt.ObjectText = CALL.company .. " · " .. job.driver.plate
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.ClickablePrompt = true
	prompt.Parent = att
	job.prompt = prompt
	table.insert(job.conns, prompt.Triggered:Connect(function(who: Player)
		if who ~= job.player then
			ctx.notify(who, "info", CALL.company, "다른 손님이 부른 택시예요")
			return
		end
		local res = board(job)
		if not res.ok and res.message then
			ctx.notify(who, "taxi", CALL.company, res.message)
		end
	end))
end

local function onArrived(job: Job)
	if jobs[job.player] ~= job or job.state ~= "coming" then
		return
	end
	job.state = "arrived"
	local t = now()
	job.arriveAt = t
	job.waitUntil = t + CALL.waitSeconds + math.min(120, (job.walkTo or 0) / 10) -- [택시 수정] 걸어오는 시간만큼 더 기다림
	local model = job.model
	model:SetAttribute("TaxiState", "arrived")
	model:SetAttribute("TaxiHazard", true)
	model:SetAttribute("TaxiWave", (model:GetAttribute("TaxiWave") or 0) + 1)
	model:SetAttribute("TaxiHonk", (model:GetAttribute("TaxiHonk") or 0) + 1)
	local horn = job.root:FindFirstChild("Horn")
	if horn and horn:IsA("Sound") then
		task.spawn(function()
			pcall(horn.Play, horn)
			task.wait(0.28)
			pcall(horn.Play, horn)
		end)
	end
	addPrompt(job)
	sendState(job)
	local dr = job.driver
	sms(job.player, string.format("[%s] 택시가 도착했습니다. %s %s %s, 비상등 켜고 기다릴게요 🚕", CALL.company, dr.color, dr.car, dr.plate))
	audit(job.player, "arrived", { ride = job.id })
end

-- Motion for the approach from `startPts` (road points ending at the pickup).
local function driveToPickup(job: Job, pts: { Vector3 }, v0: number)
	local path = D.buildPath(pts, { cruise = 40, v0 = v0, v1 = 0, pullOver = { offset = job.kerbOff, len = 30 }, heights = heightFn() })
	if not path then
		-- blocked: appear at the kerb (teleport fallback)
		local cf = job.stopCF or job.root.CFrame
		path = { pts = { cf.Position - Vector3.new(0, ROOT_LIFT, 0) - cf.LookVector * 0.5, cf.Position - Vector3.new(0, ROOT_LIFT, 0) }, times = { 0, 0.5 }, total = 0.5, length = 0.5 }
	end
	local t0 = now()
	job.arriveAt = t0 + path.total
	setMotion(job, path, t0, function()
		onArrived(job)
	end)
end

-------------------------------------------------------------------------------------------------
-- Booking
-------------------------------------------------------------------------------------------------
local function book(player: Player, p: any, silentFail: boolean?): { [string]: any }
	local existing = jobs[player]
	if existing then
		sendState(existing)
		return fail("active", { job = viewOf(existing) })
	end
	local ok, why = available()
	if not ok then
		return fail(why or "busy")
	end
	local _, humanoid, root = Util.alive(player)
	if not humanoid or not root then
		return fail("dead")
	end
	local d = Profiles.get(player)
	if not d then
		return fail("profile")
	end
	local left = Util.cooldownLeft(player, "taxiBookOk", CALL.bookCooldown)
	if left > 0 then
		return fail("cooldown")
	end
	local pos = root.Position
	local dest: DestReq? = nil
	if type(p) == "table" and (p.dest ~= nil or p.name ~= nil or p.destination ~= nil or p.x ~= nil or p.nearby == true) then
		local dr, err = parseDest(player, p, pos)
		if not dr then
			return fail(err or "dest")
		end
		dest = dr
	end
	local pickupLoc, kerbOff, stopCF = planPickup(pos)
	if not stopCF then
		return fail("noroad")
	end
	local fare, lines = nil, nil
	if dest then
		local flat = dest.pos - pos
		if math.sqrt(flat.X * flat.X + flat.Z * flat.Z) < 60 then
			return fail("same")
		end
		local q = quote(player, dest, if pickupLoc and pickupLoc.edge then pickupLoc else nil, pos)
		fare, lines = q.fare, q.lines
		if not q.canAfford then
			return fail("money", { fare = fare, cash = d.cash, bank = d.bank })
		end
	elseif not G.canAfford(d, T.baseFare) then
		return fail("money", { fare = T.baseFare, cash = d.cash, bank = d.bank })
	end
	-- approach road
	local approachPts: { Vector3 }? = nil
	if graph and pickupLoc and pickupLoc.edge then
		approachPts = D.approach(graph, pickupLoc, CALL.approachWant, CALL.approachMin)
	elseif pickupLoc and pickupLoc.kerb then
		local k = pickupLoc.kerb
		approachPts = { alongKerb(k, -T.approachStuds).Position - Vector3.new(0, 0.5, 0), k.cf.Position - Vector3.new(0, 0.5, 0) }
	end
	local model = (template :: Model):Clone()
	local taxiRoot = model.PrimaryPart
	if not taxiRoot then
		model:Destroy()
		return fail("loading")
	end
	Util.cooldown(player, "taxiBookOk", 0)
	local driver = D.driver(rng)
	for _, g in model:GetDescendants() do
		if g:IsA("TextLabel") and g.Name == "PlateText" then
			g.Text = driver.plate
		end
	end
	taxiRoot.CFrame = if approachPts then D.cframe(approachPts[1] + Vector3.new(0, ROOT_LIFT, 0), approachPts[math.min(2, #approachPts)] - approachPts[1]) else stopCF :: CFrame
	model:SetAttribute("TaxiOwner", player.UserId)
	model:SetAttribute("TaxiState", "coming")
	model:SetAttribute("TaxiPlate", driver.plate)
	model:SetAttribute("TaxiDriver", driver.name)
	model:SetAttribute("TaxiHazard", false)
	model:SetAttribute("TaxiSpawnFade", true)
	model.Name = "GwangalliTaxi_" .. player.UserId
	model.Parent = taxiFolder
	pinToRider(model, player)
	local t = now()
	local job: Job = {
		id = newRideId(),
		player = player,
		model = model,
		root = taxiRoot,
		state = "coming",
		driver = driver,
		dest = dest and dest.name,
		destLabel = dest and dest.label,
		destPos = dest and dest.pos,
		fare = fare,
		lines = lines,
		pickupLoc = if pickupLoc and pickupLoc.edge then pickupLoc else nil,
		pickupPos = pos,
		walkTo = walkDistance(pos, stopCF),
		stopCF = stopCF,
		kerbOff = kerbOff,
		dropLoc = nil,
		dropKerb = 0,
		motion = nil,
		boarded = false,
		character = nil,
		weld = nil,
		prompt = nil,
		bookedAt = t,
		arriveAt = t + 15,
		waitUntil = 0,
		rideStart = 0,
		rideEnd = 0,
		skipAt = 0,
		payUntil = 0,
		replans = 0,
		token = 0,
		paid = false,
		skipping = false,
		conns = {},
		serial = 0,
		seenAt = nil,
		streamAt = 0,
		boarding = false,
		reseats = 0,
	}
	jobs[player] = job
	model:SetAttribute("TaxiRide", job.id)
	driveToPickup(job, approachPts or { (stopCF :: CFrame).Position - Vector3.new(0, ROOT_LIFT, 0) }, 40)
	local eta = math.max(1, math.ceil(job.arriveAt - t))
	sendState(job)
	sms(player, string.format("[%s] 배차 완료! %s %s(%s) · %s · 약 %d초 후 도착 · 안심번호 %s", CALL.company, driver.color, driver.car, driver.plate, driver.title, eta, driver.phone))
	if job.walkTo then -- [택시 수정] 승차 지점이 멀면 걸어가라고 안내
		ctx.notify(player, "taxi", CALL.company, string.format("근처 큰길(약 %dm)에 택시가 서요. 지도 표시를 따라 걸어가 주세요", math.floor(job.walkTo * 0.3 + 0.5)))
	end
	audit(player, "book", { ride = job.id, dest = job.destLabel, fare = fare or 0, plate = driver.plate })
	local _ = silentFail
	return { ok = true, job = viewOf(job) }
end

-------------------------------------------------------------------------------------------------
-- Ride
-------------------------------------------------------------------------------------------------
local function arriveAtDest(job: Job)
	if jobs[job.player] ~= job or job.state ~= "riding" then
		return
	end
	job.state = "paying"
	local t = now()
	job.rideEnd = t
	job.payUntil = t + CALL.payTimeout
	job.skipping = false
	job.model:SetAttribute("TaxiState", "paying")
	job.model:SetAttribute("TaxiHazard", true)
	local d = Profiles.get(job.player)
	sendState(job, { cash = d and d.cash or 0, bank = d and d.bank or 0 })
	audit(job.player, "dropoff", { ride = job.id, dest = job.destLabel })
end

-- Fade transfer when no lane route exists (or the place has no lanes): short drive-off, fade, the
-- taxi pulls up at the destination.
local function transferRide(job: Job)
	local player = job.player
	local token = job.token
	local look = job.root.CFrame.LookVector
	local p0 = job.root.Position - Vector3.new(0, ROOT_LIFT, 0)
	local off = D.buildPath({ p0, p0 + Vector3.new(look.X, 0, look.Z).Unit * 80 }, { cruise = 30, v0 = 0, v1 = 26 })
	local t0 = now() + 1
	job.rideStart = t0
	job.rideEnd = t0 + 12
	job.skipAt = t0 + 1000
	if off then
		setMotion(job, off, t0)
	end
	sendState(job)
	task.spawn(function()
		task.wait(2.6)
		if job.token ~= token or jobs[player] ~= job then
			return
		end
		job.skipping = true
		Util.fade(player, true, 0.7, "🚕 " .. (job.destLabel or "목적지") .. " 가는 중…")
		if job.token ~= token or jobs[player] ~= job then
			return
		end
		local destPos = job.destPos :: Vector3
		ctx.allowTeleport(player, 15)
		pcall(player.RequestStreamAroundAsync, player, destPos, 5)
		if job.token ~= token or jobs[player] ~= job then
			return
		end
		local pts: { Vector3 }? = nil
		local slab, s = nearestRoad(destPos, 260)
		if slab then
			local k = kerbAt(slab, s, destPos)
			pts = { alongKerb(k, -60).Position - Vector3.new(0, 0.5, 0), k.cf.Position - Vector3.new(0, 0.5, 0) }
		else
			local tp = destPos + Vector3.new(0, 0, 0)
			pts = { tp - Vector3.new(0, 0, 40), tp }
		end
		local path = D.buildPath(pts :: { Vector3 }, { cruise = 30, v0 = 26, v1 = 0 })
		if not path then
			arriveAtDest(job)
			return
		end
		local t1 = now()
		job.rideEnd = t1 + path.total
		setMotion(job, path, t1, function()
			arriveAtDest(job)
		end)
		task.spawn(Util.fade, player, false, 0.8)
		job.skipping = false
		sendState(job)
	end)
end

startRide = function(job: Job)
	local player = job.player
	local destPos = job.destPos
	if not destPos then
		return
	end
	local d = Profiles.get(player)
	local stopPos = if job.stopCF then (job.stopCF :: CFrame).Position - Vector3.new(0, ROOT_LIFT, 0) else job.root.Position
	local pickupLoc = job.pickupLoc
	if graph and pickupLoc then
		pickupLoc = { edge = pickupLoc.edge, s = pickupLoc.s, point = pickupLoc.point, dist = 0 }
	end
	local len, pts, drop, dropKerb = rideLength(pickupLoc, stopPos, destPos)
	local lines = D.fareBreakdown(G, len, clockNow(), popularity(player))
	if not d or not G.canAfford(d, lines.total) then
		job.dest, job.destLabel, job.destPos = nil, nil, nil
		job.waitUntil = now() + CALL.destWaitSeconds
		sendState(job, { needDest = true, reason = "money", fare = lines.total })
		ctx.notify(player, "taxi", "잔액 부족", string.format("예상 요금 %s · 현금 %s · 통장 %s", G.format.won(lines.total), G.format.won(d and d.cash or 0), G.format.won(d and d.bank or 0)))
		return
	end
	job.fare = lines.total
	job.lines = lines
	job.dropLoc = drop
	job.dropKerb = dropKerb
	job.state = "riding"
	job.token += 1
	job.model:SetAttribute("TaxiState", "riding")
	job.model:SetAttribute("TaxiHazard", false)
	if job.prompt then
		job.prompt:Destroy()
		job.prompt = nil
	end
	audit(player, "ride", { ride = job.id, dest = job.destLabel, fare = lines.total, meters = math.floor(len * 0.3) })
	if not pts then
		transferRide(job)
		return
	end
	pts[1] = pickupLoc.point
	local path = D.buildPath(pts, {
		cruise = cruiseFor(len),
		v0 = 0,
		v1 = 0,
		pullOut = { offset = job.kerbOff, len = 24 },
		pullOver = { offset = dropKerb, len = 30 },
		maxSeconds = CALL.rideMaxSeconds,
		maxScale = CALL.rideMaxScale,
		heights = heightFn(),
	})
	if not path then
		transferRide(job)
		return
	end
	local t0 = now() + 1.2 -- "출발하겠습니다" beat before the car moves
	job.rideStart = t0
	job.rideEnd = t0 + path.total
	job.skipAt = t0 + CALL.skipAfter
	setMotion(job, path, t0, function()
		arriveAtDest(job)
	end)
	sendState(job, { rideLength = path.length })
end

local function skipRide(job: Job): { [string]: any }
	if job.state ~= "riding" or job.skipping then
		return fail("state")
	end
	local m = job.motion
	local t = now()
	if not m or t < job.skipAt then
		return fail("state", { skipAt = job.skipAt })
	end
	local remaining = m.t0 + m.total - t
	if remaining < 4 then
		return fail("soon")
	end
	job.skipping = true
	local token = job.token
	local player = job.player
	task.spawn(function()
		Util.fade(player, true, 0.45, "🚕 " .. (job.destLabel or "목적지") .. " 가는 중…")
		if job.token ~= token or jobs[player] ~= job or job.motion ~= m then
			return
		end
		if job.destPos then
			ctx.allowTeleport(player, 10)
			pcall(player.RequestStreamAroundAsync, player, job.destPos, 4)
		end
		if job.token ~= token or jobs[player] ~= job or job.motion ~= m then
			Util.clearFade(player)
			return
		end
		local t2 = now()
		local newT0 = t2 - (m.total - 3.2)
		retimeMotion(job, newT0)
		job.rideEnd = newT0 + m.total
		job.skipping = false
		sendState(job, { skipped = true })
		Util.fade(player, false, 0.5)
	end)
	audit(player, "skip", { ride = job.id })
	return { ok = true }
end

-------------------------------------------------------------------------------------------------
-- Payment / receipt / rating
-------------------------------------------------------------------------------------------------
local function finishRide(job: Job, method: string, paid: number)
	local player = job.player
	local t = now()
	local receipt = {
		id = job.id,
		destination = job.destLabel,
		fare = job.fare,
		paid = paid,
		method = method, -- card | cash | split | none
		lines = job.lines,
		driver = job.driver.name,
		driverTitle = job.driver.title,
		plate = job.driver.plate,
		car = job.driver.car,
		color = job.driver.color,
		meters = if job.motion then math.floor(job.motion.length * 0.3 + 0.5) else nil,
		startedClock = nil :: number?,
		endedClock = clockNow(),
		seconds = math.max(0, math.floor(t - job.rideStart)),
		at = os.time(),
		rateUntil = t + CALL.rateWindow,
		company = CALL.company,
	}
	lastRide[player] = { receipt = receipt, rated = false, until_ = t + CALL.rateWindow }
	if job.dest then
		local list = recentDests[player] or {}
		for i = #list, 1, -1 do
			if list[i] == job.dest then
				table.remove(list, i)
			end
		end
		table.insert(list, 1, job.dest)
		while #list > 4 do
			table.remove(list)
		end
		recentDests[player] = list
	end
	unseat(job, true)
	ctx.questsResetPosition(player)
	send(player, { state = "done", destination = job.destLabel, fare = paid, receipt = receipt, job = viewOf(job) })
	local how = if method == "card" then "카드(통장)" elseif method == "cash" then "현금" elseif method == "split" then "현금+카드" else "미결제"
	sms(player, string.format("[%s] %s 결제 %s · %s · %s · 이용해 주셔서 감사합니다 🙏", CALL.company, how, G.format.won(paid), job.destLabel or "목적지", job.driver.plate))
	if paid < (job.fare or 0) then
		ctx.notify(player, "taxi", job.driver.title, string.format("부족한 %s은 다음에 주세요~ (이번만이에요!)", G.format.won((job.fare or 0) - paid)))
	end
	pcall(ctx.questEvent, player, { type = "taxi", dest = job.destLabel })
	audit(player, "paid", { ride = job.id, method = method, paid = paid, fare = job.fare or 0 })
	release(job, true)
end

local function payRide(job: Job, method: string, auto: boolean?): { [string]: any }
	if job.state ~= "paying" or job.paid then
		return fail("state")
	end
	local fare = job.fare or 0
	local player = job.player
	local label = "택시비 · " .. (job.destLabel or "택시")
	if auto then
		job.paid = true
		local paid, how = chargeAuto(player, fare, label, job.id, job.destLabel, if method == "cash" then "cash" else "bank")
		finishRide(job, if paid <= 0 then "none" else how, paid)
		return { ok = true }
	end
	local account = if method == "card" then "bank" else "cash"
	local d = Profiles.get(player)
	if not d then
		return fail("profile")
	end
	if (d[account] or 0) < fare then
		return fail("insufficient", { cash = d.cash, bank = d.bank, fare = fare })
	end
	job.paid = true -- before the write: a second tap finds the ride paid
	if not charge(player, account, fare, label, job.id, job.destLabel) then
		job.paid = false
		return fail("insufficient", { cash = d.cash, bank = d.bank, fare = fare })
	end
	finishRide(job, method, fare)
	local r = lastRide[player]
	return { ok = true, receipt = r and r.receipt }
end

local function rateRide(player: Player, p: any): { [string]: any }
	local stars = Util.int(p.stars, 1, 5)
	local rideId = Util.str(p.rideId, 40)
	local r = lastRide[player]
	if not stars or not rideId or not r or r.receipt.id ~= rideId then
		return fail("bad")
	end
	if r.rated or now() > r.until_ then
		return fail("state")
	end
	r.rated = true
	audit(player, "rate", { ride = rideId, stars = stars })
	if stars == 5 then
		ctx.addStats(player, { happiness = 1 }, "친절한 기사님 덕분에 기분 좋아요 🚕", true)
	end
	return { ok = true, stars = stars }
end

-------------------------------------------------------------------------------------------------
-- Cancel
-------------------------------------------------------------------------------------------------
local function cancelByPlayer(player: Player): { [string]: any }
	local job = jobs[player]
	if not job then
		send(player, { state = "cancelled", reason = "none" })
		return fail("none")
	end
	if job.state == "riding" or job.state == "paying" then
		return fail("riding")
	end
	local fee = 0
	if now() > job.bookedAt + CALL.cancelGrace then
		fee = takeFee(job, CALL.cancelFee, "택시 호출 취소 수수료")
	end
	cancelJob(job, "player", if fee > 0 then string.format("호출을 취소했어요 · 취소 수수료 %s", G.format.won(fee)) else "호출을 취소했어요", fee)
	return { ok = true, fee = fee }
end

-------------------------------------------------------------------------------------------------
-- Watchdog: walking away (re-route), timeouts, stuck motion
-------------------------------------------------------------------------------------------------
local function replan(job: Job, pos: Vector3)
	local pickupLoc, kerbOff, stopCF = planPickup(pos)
	if not stopCF then
		cancelJob(job, "noroad", "근처에 차가 다니는 도로가 없어서 호출이 취소됐어요")
		return
	end
	job.replans += 1
	job.pickupPos = pos
	job.walkTo = walkDistance(pos, stopCF)
	job.pickupLoc = if pickupLoc and pickupLoc.edge then pickupLoc else nil
	job.kerbOff = kerbOff
	job.stopCF = stopCF
	local pts: { Vector3 }? = nil
	local v0 = 30
	if graph and job.pickupLoc then
		-- from where the car is now, heading the way it is heading
		local cur = job.root.Position - Vector3.new(0, ROOT_LIFT, 0)
		local look = job.root.CFrame.LookVector
		local best, bestD = nil, math.huge
		for _, e in D.edgesNear(graph, cur, 60) do
			local k = graph.eKind[e]
			if (k == D.KIND.lane or k == D.KIND.bus or k == D.KIND.straight) and D.edgeDir(graph, e):Dot(look) > 0.6 then
				local a = graph.pos[graph.eFrom[e]]
				local dir = D.edgeDir(graph, e)
				local s = math.clamp((cur - a):Dot(dir), 0, graph.eLen[e])
				local q = a + dir * s
				local dd = (Vector3.new(cur.X, 0, cur.Z) - Vector3.new(q.X, 0, q.Z)).Magnitude
				if dd < bestD then
					best, bestD = { edge = e, s = s, point = q, dist = dd }, dd
				end
			end
		end
		if best then
			local route = D.route(graph, best, job.pickupLoc)
			if route then
				route[1] = cur
				pts = route
			end
		end
		if not pts then
			-- blocked: come down the road again from behind (teleport fallback)
			pts = D.approach(graph, job.pickupLoc, CALL.approachWant * 0.6, 120)
			v0 = 40
		end
	end
	if not pts then
		pts = { (stopCF :: CFrame).Position - Vector3.new(0, ROOT_LIFT, 0) }
	end
	driveToPickup(job, pts :: { Vector3 }, v0)
	sendState(job, { replanned = true })
	ctx.notify(job.player, "taxi", job.driver.title, "위치가 바뀌셨네요~ 그쪽으로 갈게요!")
end

-- Seat watchdog: a boarded rider must still hang on the taxi root (the weld can be destroyed by a
-- seat change, a respawn race or a stray SeatWeld cleanup); re-weld and re-pivot when it is gone or
-- the character drifted away from the seat.
local function checkSeat(job: Job)
	if not job.boarded or not job.root.Parent then
		return
	end
	local character, humanoid, root = Util.alive(job.player)
	if not character or not humanoid or not root or character ~= job.character then
		return -- death / respawn are handled by forceEnd / Died
	end
	local weld = job.weld
	local weldOk = weld ~= nil and weld.Parent ~= nil and weld.Part0 == job.root and weld.Part1 == root
	local seatPos = (job.root.CFrame * seatLocal).Position
	local drift = (root.Position - seatPos).Magnitude
	if not weldOk or drift > 6 then
		job.reseats = (job.reseats or 0) + 1
		if job.reseats <= 3 or job.reseats % 10 == 0 then
			warn(string.format("[GwangalliGameplay] taxi %s: re-seating %s (weld %s, drift %.1f)", job.id, job.player.Name, if weldOk then "ok" else "missing", drift))
		end
		seatCharacter(job, character, humanoid, root)
	elseif not humanoid.Sit then
		humanoid.Sit = true
	end
	if job.model.Parent ~= taxiFolder then
		job.model.Parent = taxiFolder -- never let the rider sit in a car that left the Workspace
	end
end

-- While riding, ask the engine for the road ahead of the taxi (the area the rider is about to
-- enter) every 2.5 s, like the drive system does for fast cars.
local function streamAhead(job: Job, tNow: number)
	local m = job.motion
	if not m or m.done or tNow < (job.streamAt or 0) then
		return
	end
	job.streamAt = tNow + 2.5
	local t = math.min(m.total, tNow - m.t0 + 4)
	local ok, ahead = pcall(D.sample, m.pts, m.times, t)
	if ok and typeof(ahead) == "Vector3" then
		local player = job.player
		task.spawn(function()
			pcall(player.RequestStreamAroundAsync, player, ahead, 1)
		end)
	end
end

local function watch(job: Job, tNow: number)
	local player = job.player
	if player.Parent ~= Players or not job.model.Parent then
		cancelJob(job, "gone", nil)
		return
	end
	if job.boarded then
		local okSeat, errSeat = pcall(checkSeat, job)
		if not okSeat then
			Util.warnOnce("taxiSeatWatch", "[GwangalliGameplay] taxi seat watchdog: " .. tostring(errSeat))
		end
	end
	local _, humanoid, root = Util.alive(player)
	if job.state == "coming" then
		if not humanoid or not root then
			return -- respawn is handled by forceEnd
		end
		local d = root.Position - job.pickupPos
		local flatD = math.sqrt(d.X * d.X + d.Z * d.Z)
		local limit = CALL.walkAway
		if job.walkTo and job.stopCF then
			-- [택시 수정] 멀리 있는 승차 지점으로 걸어가는 중: 취소·재배차하지 않음
			local sd = root.Position - job.stopCF.Position
			flatD = math.min(flatD, math.sqrt(sd.X * sd.X + sd.Z * sd.Z))
			limit = math.max(CALL.walkAway, job.walkTo + 150)
		end
		if flatD > limit then
			cancelJob(job, "walkaway", "너무 멀리 가셔서 택시 호출이 취소됐어요")
		elseif flatD > CALL.replanDistance and not job.walkTo then
			if job.replans < CALL.maxReplans then
				replan(job, root.Position)
			end
		end
		if jobs[player] == job and job.state == "coming" and tNow > job.arriveAt + 12 then
			-- stuck (should not happen): snap to the kerb
			local m = job.motion
			if m then
				m.done = true
			end
			if job.stopCF then
				job.root.CFrame = job.stopCF
			end
			onArrived(job)
		end
	elseif job.state == "arrived" then
		if not humanoid or not root then
			return
		end
		if job.boarded then
			if tNow > job.waitUntil then
				cancelJob(job, "timeout", "목적지를 고르지 않아서 기사님이 내려 드렸어요")
			end
		elseif tNow > job.waitUntil then
			local fee = takeFee(job, CALL.noShowFee, "택시 노쇼 수수료")
			cancelJob(job, "timeout", if fee > 0 then string.format("기사님이 기다리다 떠났어요 😢 · 노쇼 수수료 %s", G.format.won(fee)) else "기사님이 기다리다 떠났어요 😢", fee)
		elseif (root.Position - job.root.Position).Magnitude > math.max(CALL.walkAway, (job.walkTo or 0) + 150) then
			local fee = takeFee(job, CALL.noShowFee, "택시 노쇼 수수료")
			cancelJob(job, "walkaway", if fee > 0 then string.format("너무 멀어져서 택시가 떠났어요 · 노쇼 수수료 %s", G.format.won(fee)) else "너무 멀어져서 택시가 떠났어요", fee)
		end
	elseif job.state == "riding" then
		streamAhead(job, tNow)
		if tNow > job.rideEnd + 20 and not job.skipping then
			local m = job.motion
			if m and not m.done then
				m.done = true
				applyMotion(job, m.total)
			end
			arriveAtDest(job)
		end
	elseif job.state == "paying" then
		if tNow > job.payUntil then
			payRide(job, "card", true)
		end
	end
end

local function watchdog()
	local tNow = now()
	for _, job in jobs do
		local ok, err = pcall(watch, job, tNow)
		if not ok then
			warn("[GwangalliGameplay] taxi watchdog: " .. tostring(err))
		end
	end
	for player, r in lastRide do
		if player.Parent ~= Players or tNow > r.until_ + 5 then
			lastRide[player] = nil
		end
	end
end

-------------------------------------------------------------------------------------------------
-- TaxiCall remote
-------------------------------------------------------------------------------------------------
local buckets: { [Player]: { tokens: number, t: number } } = {}
local function bucketOk(player: Player): boolean
	local t = os.clock()
	local b = buckets[player]
	if not b then
		b = { tokens = 6, t = t }
		buckets[player] = b
	end
	b.tokens = math.min(6, b.tokens + (t - b.t) * 2.5)
	b.t = t
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

local OP_COOLDOWN = { hello = 0.3, quote = 0.25, book = 1, cancel = 0.6, board = 0.4, skip = 0.8, pay = 0.4, rate = 0.5, setDest = 0.5, state = 0.2, seen = 0.15 }

local function homeAndWork(player: Player): (string?, string?)
	local d = Profiles.get(player)
	if not d then
		return nil, nil
	end
	local home, work = nil, nil
	if d.home and d.home.listingId and G.LISTINGS and G.LISTINGS[d.home.listingId] then
		local place = G.LISTINGS[d.home.listingId].place
		if place and ctx.dest(place) then
			home = place
		end
	end
	if d.job and d.job.id and G.JOBS and G.JOBS[d.job.id] then
		local place = G.JOBS[d.job.id].place
		if place and ctx.dest(place) then
			work = place
		end
	end
	return home, work
end

local handlers: { [string]: (Player, any) -> { [string]: any } } = {}

handlers.hello = function(player)
	local ok, why = available()
	local _, _, root = Util.alive(player)
	local pickupLabel = if root then placeLabel(root.Position) else "현재 위치"
	if ok and root and not jobs[player] then
		local _, _, stopCF = planPickup(root.Position)
		if not stopCF then
			ok, why = false, "noroad"
		end
	end
	local home, work = homeAndWork(player)
	local d = Profiles.get(player)
	local env = (pcall(ctx.env) and ctx.env()) or { night = false, clock = 12 }
	local suggestions = {}
	if env.night and ctx.dest("CLUB OCEAN 광안") then
		table.insert(suggestions, "CLUB OCEAN 광안")
	end
	local job = jobs[player]
	return {
		ok = true,
		open = ok,
		code = why,
		message = if why then MESSAGES[why] else nil,
		company = CALL.company,
		number = CALL.number,
		dispatcher = CALL.dispatcher,
		pickupLabel = pickupLabel,
		home = home,
		work = work,
		recent = recentDests[player] or {},
		suggestions = suggestions,
		night = env.night == true,
		clock = env.clock,
		cash = d and d.cash or 0,
		bank = d and d.bank or 0,
		cancelFee = CALL.cancelFee,
		cancelGrace = CALL.cancelGrace,
		active = job and viewOf(job),
	}
end

handlers.quote = function(player, p)
	local _, _, root = Util.alive(player)
	if not root then
		return fail("dead")
	end
	local ok, why = available()
	if not ok and why == "loading" then
		return fail(why)
	end
	local dest, err = parseDest(player, p, root.Position)
	if not dest then
		return fail(err or "dest")
	end
	local flat = dest.pos - root.Position
	if math.sqrt(flat.X * flat.X + flat.Z * flat.Z) < 60 then
		return fail("same")
	end
	local job = jobs[player]
	local loc, _, stopCF
	if job and job.pickupLoc then
		loc = job.pickupLoc
	else
		loc, _, stopCF = planPickup(root.Position)
		if not stopCF and not job then
			return fail("noroad")
		end
	end
	return quote(player, dest, if loc and loc.edge then loc else nil, root.Position)
end

handlers.book = function(player, p)
	return book(player, p)
end

handlers.cancel = function(player)
	return cancelByPlayer(player)
end

handlers.board = function(player)
	local job = jobs[player]
	if not job then
		return fail("none")
	end
	return board(job)
end

handlers.skip = function(player)
	local job = jobs[player]
	if not job then
		return fail("none")
	end
	return skipRide(job)
end

handlers.pay = function(player, p)
	local job = jobs[player]
	if not job then
		return fail("none")
	end
	local method = p.method
	if method ~= "card" and method ~= "cash" then
		return fail("bad")
	end
	return payRide(job, method, false)
end

handlers.rate = function(player, p)
	return rateRide(player, p)
end

handlers.setDest = function(player, p)
	local job = jobs[player]
	if not job then
		return book(player, p)
	end
	if job.state == "riding" or job.state == "paying" or job.state == "leaving" then
		return fail("state")
	end
	local from = if job.stopCF then job.stopCF.Position else job.pickupPos
	local dest, err = parseDest(player, p, from)
	if not dest then
		return fail(err or "dest")
	end
	local q = quote(player, dest, job.pickupLoc, from)
	if not q.canAfford then
		return fail("money", { fare = q.fare, cash = q.cash, bank = q.bank })
	end
	job.dest, job.destLabel, job.destPos = dest.name, dest.label, dest.pos
	job.fare, job.lines = q.fare, q.lines
	if job.boarded and job.state == "arrived" then
		startRide(job)
	else
		sendState(job)
	end
	return { ok = true, job = viewOf(job), fare = q.fare }
end

handlers.state = function(player)
	local job = jobs[player]
	local r = lastRide[player]
	return { ok = true, job = job and viewOf(job), last = r and not r.rated and r.receipt or nil }
end

-- The rider's client confirms it has the taxi model (and its TaxiRoot) replicated.
handlers.seen = function(player, p)
	local job = jobs[player]
	if not job then
		return fail("none")
	end
	if p.ride ~= nil and p.ride ~= job.id then
		return fail("state")
	end
	job.seenAt = now()
	return { ok = true }
end

local function onInvoke(player: Player, op: any, payload: any): { [string]: any }
	if type(op) ~= "string" or not handlers[op] then
		return fail("bad")
	end
	if payload ~= nil and type(payload) ~= "table" then
		return fail("bad")
	end
	if not bucketOk(player) then
		return fail("rate")
	end
	if not Util.cooldown(player, "taxiop:" .. op, OP_COOLDOWN[op] or 0.3) then
		return fail("rate")
	end
	if not Profiles.get(player) then
		return fail("profile")
	end
	local ok, res = pcall(handlers[op], player, payload or {})
	if not ok then
		warn(string.format("[GwangalliGameplay] TaxiCall %s from %s failed: %s", op, player.Name, tostring(res)))
		return fail("bad")
	end
	return res
end

-------------------------------------------------------------------------------------------------
-- Legacy phone actions (PhoneAction callTaxi / taxiDestination / cancelTaxi)
-------------------------------------------------------------------------------------------------
local function legacyFail(player: Player, res: { [string]: any })
	if res.ok then
		return
	end
	if res.code == "active" then
		ctx.notify(player, "taxi", CALL.company, "이미 택시를 불렀어요")
		return
	end
	local body = res.message or MESSAGES.bad
	if res.code == "money" and res.fare then
		body = string.format("요금 %s이 필요해요 (현금 %s · 통장 %s)", G.format.won(res.fare), G.format.won(res.cash or 0), G.format.won(res.bank or 0))
	end
	ctx.notify(player, "taxi", if res.code == "money" then "잔액 부족" else CALL.company, body)
	local reason = res.code
	if reason == "money" or reason == "busy" or reason == "noroad" then
		send(player, { state = "cancelled", reason = reason })
	end
end

function Taxi.call(player: Player, payload: any)
	local p = if type(payload) == "table" then payload else {}
	local want = if p.name ~= nil then p.name else p.destination
	local res = book(player, if want ~= nil then { dest = want } else {})
	legacyFail(player, res)
end

function Taxi.setDestination(player: Player, payload: any)
	if type(payload) ~= "table" then
		return
	end
	local want = if payload.name ~= nil then payload.name else payload.destination
	local res = handlers.setDest(player, { dest = want })
	legacyFail(player, res)
	-- [택시 수정] 휴대폰 택시 앱의 '탑승 · ○○ 출발' 버튼이 목적지만 보내고 태우지 않던 문제:
	-- 택시가 도착해 있으면 목적지 설정과 함께 바로 탑승시킴 (멀면 가까이 오라고 안내)
	local job = jobs[player]
	if res.ok and job and job.state == "arrived" and not job.boarded and not job.boarding then
		task.spawn(function()
			local r2 = board(job)
			if not r2.ok and r2.code == "far" then
				ctx.notify(player, "taxi", CALL.company, MESSAGES.far)
			end
		end)
	end
end

function Taxi.cancel(player: Player)
	local res = cancelByPlayer(player)
	if not res.ok and res.code == "riding" then
		ctx.notify(player, "taxi", CALL.company, MESSAGES.riding)
	end
end

-- Respawn / leave / death: no fee; a finished ride that is still unpaid is paid now.
function Taxi.forceEnd(player: Player, reason: string)
	local job = jobs[player]
	if not job then
		return
	end
	if job.state == "paying" and not job.paid then
		payRide(job, "card", true)
		return
	end
	cancelJob(job, reason, nil)
end

function Taxi.isRiding(player: Player): boolean
	local job = jobs[player]
	return job ~= nil and (job.boarded or job.state == "riding" or job.state == "paying")
end

-- Server API for other modules (NPC dispatcher lines, tests).
function Taxi.jobOf(player: Player): { [string]: any }?
	local job = jobs[player]
	return job and viewOf(job)
end

function Taxi.handle(player: Player, op: string, payload: any): { [string]: any }
	return onInvoke(player, op, payload)
end

function Taxi.auditLog(): { any }
	return auditRing
end

-------------------------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------------------------
local function loadNav()
	local m = ReplicatedStorage:WaitForChild("GwangalliNav", 20)
	if not (m and m:IsA("ModuleScript")) then
		navState = "none"
		return
	end
	local ok, Nav = pcall(require, m)
	if not ok or type(Nav) ~= "table" then
		warn("[GwangalliGameplay] taxi: GwangalliNav failed to load: " .. tostring(Nav))
		navState = "none"
		return
	end
	local ok2, g = pcall(D.graph, Nav)
	if ok2 and g then
		graph = g
		navState = "ready"
	else
		warn("[GwangalliGameplay] taxi: lane graph unavailable (" .. tostring(g) .. "); using road slabs")
		navState = "none"
	end
end

function Taxi.init(context: any)
	ctx = context
	G = context.G
	Util = context.Util
	Profiles = context.Profiles
	T = G.TAXI
	local dm = script.Parent and script.Parent:FindFirstChild("TaxiDispatch")
	if not (dm and dm:IsA("ModuleScript")) then
		error("[GwangalliGameplay] TaxiDispatch module missing next to Taxi")
	end
	D = require(dm) :: any
	local folder = workspace:FindFirstChild("GwangalliTaxis")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "GwangalliTaxis"
		folder.Parent = workspace
	end
	taxiFolder = folder :: Folder
	local map = workspace:FindFirstChild("Gwangalli")
	local roadsModel = map and map:FindFirstChild("roads")
	if roadsModel then
		for _, n in { "TrafficVehicles", "ParkedVehicles" } do
			local f = roadsModel:FindFirstChild(n)
			if f then
				table.insert(vehicleFolders, f)
			end
		end
	end
	-- remote
	local rf = ReplicatedStorage:FindFirstChild(G.RemotesFolder)
	if not rf then
		rf = Instance.new("Folder")
		rf.Name = G.RemotesFolder
		rf.Parent = ReplicatedStorage
	end
	local remoteName = (G.Remote and G.Remote.TaxiCall) or "TaxiCall"
	local r = rf:FindFirstChild(remoteName)
	if r and not r:IsA("RemoteFunction") then
		r:Destroy()
		r = nil
	end
	if not r then
		r = Instance.new("RemoteFunction")
		r.Name = remoteName
		r.Parent = rf
	end
	(r :: RemoteFunction).OnServerInvoke = function(player: Player, op: any, payload: any)
		local ok, res = pcall(onInvoke, player, op, payload)
		return if ok then res else fail("bad")
	end
	-- destinations
	local tag = G.Tags.Destination
	CollectionService:GetInstanceAddedSignal(tag):Connect(trackDest)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst)
		destParts[inst] = nil
	end)
	for _, inst in CollectionService:GetTagged(tag) do
		trackDest(inst)
	end
	task.spawn(function()
		local ok, err = pcall(loadNav)
		if not ok then
			navState = "none"
			warn("[GwangalliGameplay] taxi nav failed: " .. tostring(err))
		end
		if navState ~= "ready" then
			local ok1, err1 = pcall(buildRoads)
			if not ok1 then
				roadReady = true
				warn("[GwangalliGameplay] taxi road grid failed: " .. tostring(err1))
			end
		end
		local ok2, err2 = pcall(prepareTemplate)
		if not ok2 then
			warn("[GwangalliGameplay] taxi template failed: " .. tostring(err2))
			local ok3, fallback = pcall(buildFallbackTaxi)
			if ok3 then
				local root = fallback.PrimaryPart :: BasePart
				pcall(decorate, fallback, root)
				weldAll(fallback, root)
				setStreamingMode(fallback)
				fallback.Parent = ServerStorage
				template = fallback
			end
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(motionStep, dt)
		if not ok then
			Util.warnOnce("taxiMotion", "[GwangalliGameplay] taxi motion failed: " .. tostring(err))
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			watchdog()
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
		recentDests[player] = nil
		lastRide[player] = nil
	end)
end

-- test hooks
Taxi._kerbAt = kerbAt
Taxi._slabPoint = slabPoint
function Taxi._probe(p: Vector3, dir: Vector3): (number?, number)
	return surfaceAt(p, rays()), kerbOffset(p, dir)
end

return Taxi
