-- GwangalliVehicles/Spawn: cars that appear for a player.
--   * OWNED cars ("차 부르기" lists only the player's own / rented cars): Garage.luau (GwangalliGameplay)
--     validates the d.cars record and asks for the car through the server API below; the car is the kit
--     model of its kind with the record's paint colour and plate, attributes DriveOwnedCar / DriveCarId /
--     DriveCondition (the controller reads the condition: VS.enginePower) and an owner-only driver seat
--   * FREE spawn of any of the six kinds (the old 차 부르기 list): only with the dev switch
--     workspace.GwangalliDriveUnlockAll or for admins (Player attribute GwangalliAdmin, set by LiveOps)
--   * JOB vehicles (docs/careers_contract.md): ServerStorage.GwangalliEvents.SpawnJobVehicle
--     (player, kind, cframe?) -> Model? ("parcel_truck" = a truck-kind car with a box body, "police",
--     "swat", "limo", "armored"); owned by that player while the job lasts, despawned when the job ends
--     (GwJob attribute changes, DespawnJobVehicle(player), or SpawnJobVehicle(player, nil)) or the player
--     leaves; bypasses car ownership
--   * templates: one clone per kind of a PARKED map car (never moving traffic, never a taxi, never a
--     NoDrive car) in ServerStorage.GwangalliDriveTemplates; else a 정비소 showroom car of that kind
--     (tag GarageDisplayCar, cloned without its NoDrive flag); else a simple contract-compliant box car
--   * placement: the nearest road lane node of ReplicatedStorage.GwangalliNav within the call radius of
--     the player (or of opts.near), heading along the lane, snapped to the ground, clear of parts / people
--   * limits: one called car per player (+ one job vehicle), per-player cooldown, global spawn gap, cap
--
-- SERVER API (ServerStorage.GwangalliVehiclesAPI, BindableFunction; Invoke(op, ...)):
--   "spawnOwned" (player, spec, opts?) -> ok, msg, model     spec = { id, kind, color (Color3), colorId,
--        plate, cond, dirt, label, rental, testDrive (unix end) }; opts = { near: Vector3?, cframe:
--        CFrame? (ground frame), radius?, force? (skip the cooldown), seat? (put the player in the
--        driver's seat) }; msg = "label|meters" on success
--   "despawn" (player, reason?) -> ok          the called car
--   "current" (player) -> Model?               the called car
--   "eject" (model) -> ok                      everyone out
--   "park" (model) -> ok                       driverless car: stop + anchor now
--   "seat" (player, model) -> ok, msg          into the driver's seat (character moved to the door)
--   "occupants" (model) -> { Player }
--   "spawnJob" (player, kind, cframe?) -> Model?   / "despawnJob" (player) -> ok / "jobCar" (player) -> Model?

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local Spawn = {}

local VS: any = nil
local Rig: any = nil
local Cars: any = nil
local GS: any = nil

local templates: { [string]: Model } = {}
local lastCall: { [Player]: number } = {}
local lastGlobal = -math.huge
local Nav: any = nil
local navTried = false
local folder: Folder? = nil

local function garageShared(): any
	if GS then
		return GS
	end
	local m = ReplicatedStorage:FindFirstChild("GwangalliGarageShared")
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			GS = res
		end
	end
	return GS
end

local function nav(): any
	if navTried then
		return Nav
	end
	navTried = true
	local m = ReplicatedStorage:FindFirstChild("GwangalliNav") or ReplicatedStorage:WaitForChild("GwangalliNav", 5)
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" and res.lanes then
			Nav = res
		else
			warn("[GwangalliVehicles] GwangalliNav failed to load: " .. tostring(res))
		end
	end
	return Nav
end

local function carsFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = workspace:FindFirstChild("GwangalliPlayerCars")
	if not (f and f:IsA("Folder")) then
		f = Instance.new("Folder")
		f.Name = "GwangalliPlayerCars"
		f.Parent = workspace
	end
	folder = f :: Folder
	return folder :: Folder
end

---------------------------------------------------------------------------------------------------
-- Templates
---------------------------------------------------------------------------------------------------
local function isTraffic(m: Instance): boolean
	local node = m.Parent
	while node and node ~= workspace do
		if node.Name == "TrafficVehicles" then
			return true
		end
		node = node.Parent
	end
	return false
end

-- Box car that follows docs/vehicles_contract.md (used when the map lacks a model of that kind).
local function fallbackCar(kind: string): Model
	local spec = VS.spec(kind)
	local m = Instance.new("Model")
	m.Name = "Car_" .. kind
	m:SetAttribute("VehicleKind", kind)
	local L, W = if kind == "compact" then 12 else 16, if kind == "compact" then 5.3 else 6.2
	local function box(name: string, size: Vector3, pos: Vector3, color: Color3, parent: Instance?)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = CFrame.new(pos)
		p.Color = color
		p.Anchored = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = parent or m
		return p
	end
	local paint = Color3.fromRGB(236, 237, 236)
	box("Underbody", Vector3.new(W - 0.7, 0.5, L - 2), Vector3.new(0, 0.75, 0), Color3.fromRGB(26, 26, 28))
	box("BodySide", Vector3.new(W, 1.9, L), Vector3.new(0, 1.95, 0), paint)
	box("Roof", Vector3.new(W - 0.6, 1.4, L * 0.5), Vector3.new(0, 3.6, 0.8), paint)
	box("Windshield", Vector3.new(W - 0.8, 1.2, 0.2), Vector3.new(0, 3.6, -L * 0.25 + 0.9), Color3.fromRGB(36, 46, 52)).Transparency = 0.5
	box("Grille", Vector3.new(W * 0.5, 0.6, 0.2), Vector3.new(0, 1.8, -L / 2 - 0.05), Color3.fromRGB(20, 20, 22))
	box("HeadlampLens", Vector3.new(1, 0.4, 0.2), Vector3.new(-W / 2 + 0.9, 2.3, -L / 2 - 0.05), Color3.fromRGB(208, 216, 226))
	box("HeadlampLens", Vector3.new(1, 0.4, 0.2), Vector3.new(W / 2 - 0.9, 2.3, -L / 2 - 0.05), Color3.fromRGB(208, 216, 226))
	box("TailLamp", Vector3.new(1.2, 0.4, 0.2), Vector3.new(-W / 2 + 0.9, 2.4, L / 2 + 0.05), Color3.fromRGB(150, 14, 22))
	box("TailLamp", Vector3.new(1.2, 0.4, 0.2), Vector3.new(W / 2 - 0.9, 2.4, L / 2 + 0.05), Color3.fromRGB(150, 14, 22))
	local int = Instance.new("Model")
	int.Name = "Interior"
	int:SetAttribute("LOD", "near")
	int.Parent = m
	box("SeatCushion", Vector3.new(1.7, 0.48, 1.75), Vector3.new(-1.25, 1.75, 0), Color3.fromRGB(32, 32, 34), int)
	box("SeatCushion", Vector3.new(1.7, 0.48, 1.75), Vector3.new(1.25, 1.75, 0), Color3.fromRGB(32, 32, 34), int)
	box("SeatCushion", Vector3.new(4.5, 0.48, 1.6), Vector3.new(0, 1.8, 2.8), Color3.fromRGB(32, 32, 34), int)
	box("Dash", Vector3.new(W - 1, 0.8, 1), Vector3.new(0, 2.8, -2.2), Color3.fromRGB(24, 24, 26), int)
	local d, fz, rz = 2.2, -L * 0.3, L * 0.28
	for _, z in { fz, rz } do
		for _, s in { -1, 1 } do
			local t = box("Tyre", Vector3.new(0.78, d, d), Vector3.new(s * (W / 2 - 0.45), d / 2, z), Color3.fromRGB(30, 30, 32))
			t.Shape = Enum.PartType.Cylinder
			t.Material = Enum.Material.Rubber
		end
	end
	m:SetAttribute("DriveLabel", spec.label)
	return m
end

-- Strips what must not travel with a template clone (scripts, prompts, garage display tags).
local function cleanClone(model: Model)
	for _, x in model:GetDescendants() do
		if x:IsA("BaseScript") or x:IsA("ProximityPrompt") or x:IsA("ClickDetector") or (x:IsA("Attachment") and string.sub(x.Name, 1, #VS.Parts.Prompt) == VS.Parts.Prompt) then
			x:Destroy()
		end
	end
	for _, a in { VS.Attr.Unlocked, VS.Attr.Rigged, VS.Attr.Rig, VS.Attr.Driver, VS.Attr.NoDrive, "GarageKind", "GarageLiftCar" } do
		model:SetAttribute(a, nil)
	end
	for _, tag in model:GetTags() do
		model:RemoveTag(tag)
	end
end

function Spawn.template(kind: string): Model
	local t = templates[kind]
	if t and t.Parent then
		return t
	end
	local holder = ServerStorage:FindFirstChild("GwangalliDriveTemplates")
	if not holder then
		holder = Instance.new("Folder")
		holder.Name = "GwangalliDriveTemplates"
		holder.Parent = ServerStorage
	end
	local source: Model? = nil
	local map = workspace:FindFirstChild("Gwangalli") or workspace
	local n = 0
	for _, d in map:GetDescendants() do
		n += 1
		if n % 5000 == 0 then
			task.wait()
		end
		if d:IsA("Model") and d:GetAttribute("VehicleKind") == kind and not d:GetAttribute(VS.Attr.Rigged) and not isTraffic(d) and not d:GetAttribute(VS.Attr.NoDrive) then
			source = d
			break
		end
	end
	if not source then
		-- a 정비소 showroom car of that kind (subset builds, or kinds the streets lack)
		local tagName = (garageShared() and GS.Tags.Display) or "GarageDisplayCar"
		for _, d in CollectionService:GetTagged(tagName) do
			if d:IsA("Model") and d:GetAttribute("GarageKind") == kind then
				source = d
				break
			end
		end
	end
	local model: Model
	if source then
		model = source:Clone()
		cleanClone(model)
		model:SetAttribute("VehicleKind", kind)
	else
		model = fallbackCar(kind)
	end
	model.Parent = holder
	templates[kind] = model
	return model
end

---------------------------------------------------------------------------------------------------
-- Decoration (paint, plate, job liveries)
---------------------------------------------------------------------------------------------------
local function rgb3(t: { number }?): Color3?
	if type(t) ~= "table" then
		return nil
	end
	return Color3.fromRGB(t[1], t[2], t[3])
end

-- Reference frame of the model's body: Underbody (LookVector = front) or the pivot.
local function bodyFrame(model: Model): CFrame
	local under = model:FindFirstChild("Underbody")
	if under and under:IsA("BasePart") then
		return under.CFrame
	end
	return model:GetPivot()
end

local function addPart(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function sideText(part: BasePart, face: Enum.NormalId, text: string, fg: Color3)
	local sg = Instance.new("SurfaceGui")
	sg.Name = "Livery"
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 24
	sg.MaxDistance = 160
	sg.LightInfluence = 1
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(0.9, 0.5)
	l.Position = UDim2.fromScale(0.05, 0.25)
	l.Text = text
	l.TextScaled = true
	l.Font = Enum.Font.GothamBlack
	l.TextColor3 = fg
	l.Parent = sg
	sg.Parent = part
end

-- Parcel truck: the open cargo bed becomes a closed box body (탑차) with the company name.
local function addCargoBox(model: Model, def: any)
	local bed = model:FindFirstChild("BedFloor", true)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and (d.Name == "Cargo" or d.Name == "DropSide" or d.Name == "DropSideRail" or d.Name == "Tailgate") then
			d:Destroy()
		end
	end
	if not (bed and bed:IsA("BasePart")) then
		return
	end
	local cf = bed.CFrame
	local sz = bed.Size
	local h = 5.2
	local col = rgb3(def.box) or Color3.fromRGB(214, 216, 220)
	local box = addPart(model, "CargoBox", Vector3.new(sz.X + 0.1, h, sz.Z - 0.1), cf * CFrame.new(0, sz.Y / 2 + h / 2, 0), col)
	addPart(model, "CargoBoxRoofRail", Vector3.new(sz.X + 0.2, 0.15, sz.Z), cf * CFrame.new(0, sz.Y / 2 + h + 0.07, 0), Color3.fromRGB(176, 180, 184), Enum.Material.Metal)
	-- rear doors (two leaves + a lock bar) on the back face
	local back = cf * CFrame.new(0, sz.Y / 2 + h / 2, sz.Z / 2 - 0.02)
	addPart(model, "CargoDoorLine", Vector3.new(0.08, h - 0.4, 0.06), back * CFrame.new(0, 0, 0.04), Color3.fromRGB(120, 124, 128))
	addPart(model, "CargoDoorBar", Vector3.new(0.12, h - 0.8, 0.12), back * CFrame.new(-0.6, 0, 0.08), Color3.fromRGB(160, 164, 168), Enum.Material.Metal)
	addPart(model, "CargoDoorBar", Vector3.new(0.12, h - 0.8, 0.12), back * CFrame.new(0.6, 0, 0.08), Color3.fromRGB(160, 164, 168), Enum.Material.Metal)
	local txt = def.boxText or "택배"
	local fg = Color3.fromRGB(30, 90, 170)
	sideText(box, Enum.NormalId.Left, txt, fg)
	sideText(box, Enum.NormalId.Right, txt, fg)
	sideText(box, Enum.NormalId.Back, "📦 " .. txt, fg)
	-- a blue stripe along the bottom of the box
	addPart(model, "CargoStripe", Vector3.new(sz.X + 0.14, 0.5, sz.Z - 0.06), cf * CFrame.new(0, sz.Y / 2 + 0.6, 0), Color3.fromRGB(30, 90, 170))
end

-- Body stripe + roof light bar (police / swat) - light bars are left out of the collision box by name.
local function addLivery(model: Model, def: any)
	local stripe = rgb3(def.stripe)
	if not stripe then
		return
	end
	local frame = bodyFrame(model)
	local ok, size = pcall(function()
		local _, s = model:GetBoundingBox()
		return s
	end)
	if not ok then
		return
	end
	local roofY = 0
	local minY = math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local top = d.Position.Y + d.Size.Y / 2
			if top > roofY then
				roofY = top
			end
			minY = math.min(minY, d.Position.Y - d.Size.Y / 2)
		end
	end
	local base = frame.Position
	local W = math.min(size.X, size.Z)
	local L = math.max(size.X, size.Z)
	local look = frame.LookVector
	local flat = CFrame.lookAt(Vector3.new(base.X, roofY, base.Z), Vector3.new(base.X, roofY, base.Z) + Vector3.new(look.X, 0, look.Z))
	addPart(model, "LightBarBase", Vector3.new(W * 0.62, 0.22, 0.9), flat * CFrame.new(0, 0.11, 0), Color3.fromRGB(30, 30, 32))
	local red = addPart(model, "LightBarRed", Vector3.new(W * 0.3, 0.3, 0.8), flat * CFrame.new(-W * 0.16, 0.37, 0), Color3.fromRGB(230, 40, 50), Enum.Material.Neon)
	local blue = addPart(model, "LightBarBlue", Vector3.new(W * 0.3, 0.3, 0.8), flat * CFrame.new(W * 0.16, 0.37, 0), Color3.fromRGB(40, 90, 240), Enum.Material.Neon)
	red.CastShadow, blue.CastShadow = false, false
	-- a thin stripe along both flanks at belt height
	local beltY = minY + (roofY - minY) * 0.42
	for _, s in { -1, 1 } do
		local p = addPart(model, "LiveryStripe", Vector3.new(0.06, 0.45, L * 0.82), CFrame.lookAt(Vector3.new(base.X, beltY, base.Z), Vector3.new(base.X, beltY, base.Z) + Vector3.new(look.X, 0, look.Z)) * CFrame.new(s * (W / 2 + 0.02), 0, 0), stripe)
		p.CastShadow = false
	end
end

local function decorate(model: Model, o: any)
	local G = garageShared()
	if o.color and G then
		G.applyColor(model, o.color, o.colorId)
	end
	if o.plate and G then
		G.applyPlate(model, o.plate)
	end
	if o.job then
		local def = o.job
		if def.box then
			addCargoBox(model, def)
		end
		addLivery(model, def)
	end
end

---------------------------------------------------------------------------------------------------
-- Placement
---------------------------------------------------------------------------------------------------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true
rayParams.IgnoreWater = true

local function exclusions(): { Instance }
	local list = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	return list
end

-- Candidate ground frames near `pos` (nearest lane nodes first, several nodes along each lane).
local function laneFrames(pos: Vector3, radius: number): { CFrame }
	local N = nav()
	if not N then
		return {}
	end
	local ok, dec = pcall(N.decode)
	if not ok or type(dec) ~= "table" or not dec.lanePos then
		return {}
	end
	local near = {}
	for i, p in dec.lanePos do
		local dx, dz = p.X - pos.X, p.Z - pos.Z
		local d2 = dx * dx + dz * dz
		if d2 < radius * radius then
			table.insert(near, { i = i, d2 = d2 })
		end
	end
	table.sort(near, function(a, b)
		return a.d2 < b.d2
	end)
	local frames = {}
	local seen = {}
	local function heading(i: number): Vector3?
		local out = dec.laneOut[i]
		if out and out[1] then
			local d = dec.lanePos[out[1]] - dec.lanePos[i]
			local h = Vector3.new(d.X, 0, d.Z)
			if h.Magnitude > 0.5 then
				return h.Unit
			end
		end
		return nil
	end
	for k = 1, math.min(#near, 10) do
		local node = near[k].i
		-- walk forward along the lane: the node itself, then up to 5 successors
		for _ = 1, 6 do
			if not node or seen[node] then
				break
			end
			seen[node] = true
			local h = heading(node)
			if h then
				local p = dec.lanePos[node]
				table.insert(frames, CFrame.lookAt(p, p + h))
			end
			local out = dec.laneOut[node]
			node = out and out[1]
		end
	end
	return frames
end
Spawn.laneFrames = laneFrames

local function clearAt(groundCF: CFrame, rig: any, exclude: { Instance }): boolean
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = exclude
	overlap.RespectCanCollide = true
	local size = Vector3.new(rig.W + 1.2, math.max(2, rig.H - 0.6), rig.L + 1.5)
	local centre = groundCF * CFrame.new(0, 0.7 + size.Y / 2, 0)
	local parts = workspace:GetPartBoundsInBox(centre, size, overlap)
	if #parts > 0 then
		return false
	end
	-- no player standing there either
	for _, p in Players:GetPlayers() do
		local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			local l = groundCF:PointToObjectSpace(hrp.Position)
			if math.abs(l.X) < size.X / 2 + 1.5 and math.abs(l.Z) < size.Z / 2 + 1.5 and l.Y < rig.H + 4 then
				return false
			end
		end
	end
	return true
end

-- Snap a lane frame to the ground (road y = 6 in the nav data; bridge decks / slopes via raycast
-- from just above the reference height, so a deck overhead is never picked from the street).
local function snap(cf: CFrame, exclude: { Instance }, refY: number): CFrame?
	rayParams.FilterDescendantsInstances = exclude
	local p = cf.Position
	local top = math.max(p.Y, refY) + 12
	local hit = workspace:Raycast(Vector3.new(p.X, top, p.Z), Vector3.new(0, -(top - p.Y + 20), 0), rayParams)
	if hit then
		if hit.Material == Enum.Material.Water then
			return nil
		end
		return CFrame.lookAt(hit.Position, hit.Position + cf.LookVector)
	end
	return cf
end

-- Builds, rigs and places one car. o = { kind, near?, cframe?, radius?, color?, colorId?, plate?, job?,
-- name?, refY? }. Returns ok, msg, model, rec, distance (studs).
local function build(player: Player, o: any): (boolean, string, Model?, any?, number?)
	local L = VS.Limits
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local origin: Vector3? = o.near
	if not origin and hrp and hrp:IsA("BasePart") then
		origin = hrp.Position
	end
	if not origin then
		return false, "캐릭터가 없어요", nil, nil, nil
	end
	local exclude = exclusions()
	local frames: { CFrame } = {}
	if o.cframe then
		table.insert(frames, o.cframe)
	end
	for _, f in laneFrames(origin :: Vector3, o.radius or L.CallRadius) do
		table.insert(frames, f)
	end
	if #frames == 0 then
		return false, "근처에 도로가 없어요. 도로 가까이에서 불러 주세요", nil, nil, nil
	end
	local template = Spawn.template(o.kind)
	local model = template:Clone()
	model.Name = o.name or ("PlayerCar_" .. player.UserId)
	decorate(model, o)
	local rec, why = Rig.rig(model)
	if not rec then
		model:Destroy()
		warn("[GwangalliVehicles] template rig failed (" .. tostring(o.kind) .. "): " .. tostring(why))
		return false, "차를 준비하지 못했어요", nil, nil, nil
	end
	local chosen: CFrame? = nil
	local refY = o.refY or (origin :: Vector3).Y
	for i, f in frames do
		local g = if i == 1 and o.cframe then f else snap(f, exclude, refY)
		if g and clearAt(g, rec.rig, exclude) then
			chosen = g
			break
		end
	end
	if not chosen then
		model:Destroy()
		return false, "차를 세울 빈자리가 없어요. 조금 이동해서 다시 불러 주세요", nil, nil, nil
	end
	model:PivotTo(Rig.baseFor(rec, chosen :: CFrame))
	model:SetAttribute(VS.Attr.Owner, player.UserId)
	local dist = if hrp and hrp:IsA("BasePart") then ((chosen :: CFrame).Position - hrp.Position).Magnitude else 0
	return true, "", model, rec, dist
end

local function checkCallLimits(player: Player, force: boolean?): (boolean, string?)
	local L = VS.Limits
	local t = os.clock()
	if Cars.driving[player] then
		return false, "운전 중에는 차를 부를 수 없어요"
	end
	if not force and lastCall[player] and t - lastCall[player] < L.CallCooldown then
		return false, string.format("%d초 뒤에 다시 부를 수 있어요", math.ceil(L.CallCooldown - (t - lastCall[player])))
	end
	if t - lastGlobal < L.GlobalCallGap then
		return false, "잠시 후 다시 시도해 주세요"
	end
	local old = Cars.called[player]
	if old then
		local others = Cars.occupants(old)
		if #others > 0 then
			return false, "지금 내 차에 누가 타고 있어요"
		end
	end
	if not old and Cars.awakeCount() >= L.MaxActive then
		return false, "지금은 차가 너무 많아요. 잠시 후 다시 해 보세요"
	end
	return true, nil
end

---------------------------------------------------------------------------------------------------
-- Call (free spawn: dev switch / admin) / owned cars / dismiss
---------------------------------------------------------------------------------------------------
function Spawn.call(player: Player, kind: any): (boolean, string, Model?)
	if not VS.freeSpawnAllowed(player) then
		return false, "정비소에서 산 내 차만 부를 수 있어요 · '차 부르기'에서 내 차를 고르세요", nil
	end
	if type(kind) ~= "string" or not VS.Drivable[kind] then
		kind = VS.DEFAULT_KIND
	end
	local okL, why = checkCallLimits(player, false)
	if not okL then
		return false, why :: string, nil
	end
	local t = os.clock()
	lastCall[player] = t
	lastGlobal = t
	local ok, msg, model, rec, dist = build(player, { kind = kind })
	if not ok or not model or not rec then
		lastCall[player] = nil
		return false, msg, nil
	end
	local old = Cars.called[player]
	if old then
		Cars.despawn(old)
	end
	model.Parent = carsFolder()
	Cars.register(rec, { owner = player, parked = false })
	Cars.called[player] = rec
	return true, string.format("%s|%d", rec.spec.label, math.floor((dist or 0) * 0.3 + 0.5)), model
end

-- An owned / rented / test-drive car (Garage.luau validated the record). spec: see the API header.
function Spawn.callOwned(player: Player, spec: any, opts: any?): (boolean, string, Model?)
	local o = opts or {}
	if type(spec) ~= "table" or type(spec.kind) ~= "string" or not VS.Drivable[spec.kind] then
		return false, "잘못된 차 정보예요", nil
	end
	local okL, why = checkCallLimits(player, o.force == true)
	if not okL then
		return false, why :: string, nil
	end
	local t = os.clock()
	lastCall[player] = t
	lastGlobal = t
	local color = if typeof(spec.color) == "Color3" then spec.color else nil
	local ok, msg, model, rec, dist = build(player, {
		kind = spec.kind,
		near = if typeof(o.near) == "Vector3" then o.near else nil,
		cframe = if typeof(o.cframe) == "CFrame" then o.cframe else nil,
		radius = if type(o.radius) == "number" then o.radius else nil,
		refY = if typeof(o.near) == "Vector3" then o.near.Y else nil,
		color = color,
		colorId = spec.colorId,
		plate = if type(spec.plate) == "string" then spec.plate else nil,
	})
	if not ok or not model or not rec then
		lastCall[player] = nil
		return false, msg, nil
	end
	local old = Cars.called[player]
	if old then
		Cars.despawn(old)
	end
	local label = if type(spec.label) == "string" then spec.label else rec.spec.label
	model:SetAttribute(VS.Attr.OwnedCar, true)
	model:SetAttribute(VS.Attr.CarId, if type(spec.id) == "string" then spec.id else "")
	model:SetAttribute(VS.Attr.Condition, if type(spec.cond) == "number" then math.clamp(spec.cond, 0, 100) else 100)
	model:SetAttribute("DriveDirt", if type(spec.dirt) == "number" then math.clamp(spec.dirt, 0, 1) else 0)
	model:SetAttribute(VS.Attr.Label, label)
	if spec.rental then
		model:SetAttribute("DriveRental", true)
	end
	if type(spec.testDrive) == "number" then
		model:SetAttribute(VS.Attr.TestDrive, spec.testDrive)
	end
	model.Parent = carsFolder()
	Cars.register(rec, {
		owner = player,
		parked = false,
		ownerOnly = true,
		carId = spec.id,
		label = if type(spec.plate) == "string" then label .. " · " .. spec.plate else label,
		testDrive = type(spec.testDrive) == "number",
	})
	Cars.called[player] = rec
	if o.seat then
		task.defer(function()
			Spawn.seat(player, model)
		end)
	end
	return true, string.format("%s|%d", label, math.floor((dist or 0) * 0.3 + 0.5)), model
end

function Spawn.dismiss(player: Player): (boolean, string)
	local rec = Cars.called[player]
	if not rec then
		return false, "부른 차가 없어요"
	end
	local occ = Cars.occupants(rec)
	for _, p in occ do
		if p ~= player then
			return false, "지금 내 차에 누가 타고 있어요"
		end
	end
	Cars.despawn(rec)
	return true, "차를 돌려보냈어요"
end

function Spawn.status(player: Player): { [string]: any }
	local rec = Cars.called[player]
	local out: { [string]: any } = { hasCar = rec ~= nil, free = VS.freeSpawnAllowed(player) }
	if rec then
		out.kind = rec.kind
		out.label = rec.label or rec.spec.label
		out.model = rec.model
		out.carId = rec.carId
		out.cond = rec.model:GetAttribute(VS.Attr.Condition)
		out.plate = rec.model:GetAttribute(VS.Attr.Plate)
		out.testDrive = rec.testDrive == true
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			out.meters = math.floor((rec.base.Position - hrp.Position).Magnitude * 0.3 + 0.5)
		end
	end
	local t = os.clock()
	out.cooldown = if lastCall[player] then math.max(0, VS.Limits.CallCooldown - (t - lastCall[player])) else 0
	return out
end

-- Puts the player into the driver's seat of `model` (moves the character to the driver's door first).
function Spawn.seat(player: Player, model: Model): (boolean, string?)
	local rec = Cars.recs[model]
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not rec or not (hrp and hrp:IsA("BasePart")) then
		return false, "차를 찾을 수 없어요"
	end
	local door = rec.base.CFrame * CFrame.new(rec.doors.driver)
	local stand = door.Position + Vector3.new(0, 1.5, 0)
	pcall(function()
		(char :: Model):PivotTo(CFrame.lookAt(stand, stand + rec.base.CFrame.LookVector))
	end)
	return Cars.enter(player, model, "driver")
end

---------------------------------------------------------------------------------------------------
-- Job vehicles (careers contract: SpawnJobVehicle / DespawnJobVehicle)
---------------------------------------------------------------------------------------------------
local jobWatch: { [Player]: RBXScriptConnection } = {}

function Spawn.despawnJob(player: Player, reason: string?): boolean
	local c = jobWatch[player]
	if c then
		c:Disconnect()
		jobWatch[player] = nil
	end
	local rec = Cars.jobCars[player]
	if not rec then
		return false
	end
	Cars.despawn(rec, reason)
	return true
end

-- A pad tagged GwVehiclePad with attribute Kind == kind near the player (venue garages).
local function padFor(kind: string, pos: Vector3): CFrame?
	local best, bestD = nil, 600
	for _, p in CollectionService:GetTagged("GwVehiclePad") do
		if p:IsA("BasePart") and p:GetAttribute("Kind") == kind then
			local d = (p.Position - pos).Magnitude
			if d < bestD then
				best, bestD = p, d
			end
		end
	end
	if best then
		local cf = best.CFrame
		local top = cf.Position + Vector3.new(0, best.Size.Y / 2, 0)
		local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
		if look.Magnitude < 0.1 then
			look = Vector3.zAxis
		end
		return CFrame.lookAt(top, top + look.Unit)
	end
	return nil
end

function Spawn.spawnJob(player: Player, kind: any, cframe: any?): Model?
	if kind == nil or kind == "none" then
		Spawn.despawnJob(player, "업무가 끝나서 차량을 반납했어요")
		return nil
	end
	local G = garageShared()
	local def = G and G.JOB_VEHICLES[kind]
	if type(kind) ~= "string" or not def then
		warn("[GwangalliVehicles] SpawnJobVehicle: unknown kind " .. tostring(kind))
		return nil
	end
	if player.Parent ~= Players then
		return nil
	end
	if Cars.driving[player] and Cars.driving[player] ~= Cars.jobCars[player] then
		Cars.exit(player)
	end
	local old = Cars.jobCars[player]
	if old then
		Cars.despawn(old)
		Cars.jobCars[player] = nil
	end
	if Cars.awakeCount() >= VS.Limits.MaxActive + 4 then
		warn("[GwangalliVehicles] SpawnJobVehicle: server car cap reached")
		return nil
	end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local pos = if hrp and hrp:IsA("BasePart") then hrp.Position else nil
	local at: CFrame? = if typeof(cframe) == "CFrame" then cframe elseif pos then padFor(kind, pos) else nil
	-- the police kit car is the patrol car itself; everything else is the base kind + livery
	local baseKind = def.base
	if kind == "police" then
		local hasPolice = false
		local map = workspace:FindFirstChild("Gwangalli")
		if map then
			for _, d in map:GetDescendants() do
				if d:IsA("Model") and d:GetAttribute("VehicleKind") == "police" and not isTraffic(d) then
					hasPolice = true
					break
				end
			end
		end
		if hasPolice then
			baseKind = "police"
		end
	end
	local ok, msg, model, rec = build(player, {
		kind = baseKind,
		cframe = at,
		near = if at then at.Position else nil,
		color = if baseKind == "police" then nil else rgb3(def.rgb),
		job = if baseKind == "police" then nil else def,
		name = "JobCar_" .. player.UserId,
		radius = 320,
	})
	if not ok or not model or not rec then
		warn("[GwangalliVehicles] SpawnJobVehicle failed: " .. tostring(msg))
		return nil
	end
	model:SetAttribute(VS.Attr.JobKind, kind)
	model:SetAttribute(VS.Attr.OwnedCar, true)
	model:SetAttribute(VS.Attr.Label, def.label)
	model.Parent = carsFolder()
	Cars.register(rec, { owner = player, parked = false, ownerOnly = true, job = kind, label = def.label, idleLimit = 900 })
	Cars.jobCars[player] = rec
	-- the job ends -> the vehicle goes back
	local startJob = player:GetAttribute("GwJob")
	local c = jobWatch[player]
	if c then
		c:Disconnect()
	end
	jobWatch[player] = player:GetAttributeChangedSignal("GwJob"):Connect(function()
		if player:GetAttribute("GwJob") ~= startJob then
			Spawn.despawnJob(player, "업무가 끝나서 차량을 반납했어요")
		end
	end)
	return model
end

---------------------------------------------------------------------------------------------------
-- Server API (BindableFunctions)
---------------------------------------------------------------------------------------------------
local function bindable(parent: Instance, name: string): BindableFunction
	local f = parent:FindFirstChild(name)
	if f and not f:IsA("BindableFunction") then
		f:Destroy()
		f = nil
	end
	if not f then
		f = Instance.new("BindableFunction")
		f.Name = name
		f.Parent = parent
	end
	return f :: BindableFunction
end

local function eventsFolder(): Folder
	local f = ServerStorage:FindFirstChild("GwangalliEvents")
	if f and not f:IsA("Folder") then
		f = nil
	end
	if not f then
		f = Instance.new("Folder")
		f.Name = "GwangalliEvents"
		f.Parent = ServerStorage
	end
	return f :: Folder
end

local function isPlayer(p: any): boolean
	return typeof(p) == "Instance" and p:IsA("Player") and p.Parent == Players
end

function Spawn.bindApi()
	local api = bindable(ServerStorage, "GwangalliVehiclesAPI")
	api.OnInvoke = function(op: any, a: any, b: any, c: any)
		if op == "spawnOwned" then
			if not isPlayer(a) then
				return false, "no player", nil
			end
			return Spawn.callOwned(a, b, c)
		elseif op == "despawn" then
			local rec = isPlayer(a) and Cars.called[a]
			if rec then
				Cars.despawn(rec, if type(b) == "string" then b else nil)
				return true
			end
			return false
		elseif op == "current" then
			local rec = isPlayer(a) and Cars.called[a]
			return rec and rec.model or nil
		elseif op == "eject" then
			local rec = typeof(a) == "Instance" and Cars.recs[a]
			if rec then
				for _, p in Cars.occupants(rec) do
					Cars.exit(p)
				end
				return true
			end
			return false
		elseif op == "park" then
			local rec = typeof(a) == "Instance" and Cars.recs[a]
			if rec and not rec.driver then
				if not rec.sleeping then
					Cars.sleep(rec)
				end
				return true
			end
			return false
		elseif op == "seat" then
			if not isPlayer(a) or typeof(b) ~= "Instance" then
				return false, "bad args"
			end
			return Spawn.seat(a, b)
		elseif op == "occupants" then
			local rec = typeof(a) == "Instance" and Cars.recs[a]
			return if rec then Cars.occupants(rec) else {}
		elseif op == "spawnJob" then
			return if isPlayer(a) then Spawn.spawnJob(a, b, c) else nil
		elseif op == "despawnJob" then
			return if isPlayer(a) then Spawn.despawnJob(a) else false
		elseif op == "jobCar" then
			local rec = isPlayer(a) and Cars.jobCars[a]
			return rec and rec.model or nil
		elseif op == "status" then
			return if isPlayer(a) then Spawn.status(a) else nil
		end
		return nil
	end
	local ev = eventsFolder()
	bindable(ev, "SpawnJobVehicle").OnInvoke = function(player: any, kind: any, cframe: any)
		if not isPlayer(player) then
			return nil
		end
		local ok, res = pcall(Spawn.spawnJob, player, kind, cframe)
		if not ok then
			warn("[GwangalliVehicles] SpawnJobVehicle: " .. tostring(res))
			return nil
		end
		return res
	end
	bindable(ev, "DespawnJobVehicle").OnInvoke = function(player: any)
		if not isPlayer(player) then
			return false
		end
		return Spawn.despawnJob(player, "업무가 끝나서 차량을 반납했어요")
	end
end

function Spawn.init(shared: any, rig: any, cars: any)
	VS, Rig, Cars = shared, rig, cars
	garageShared()
	Spawn.bindApi()
end

function Spawn.playerRemoving(player: Player)
	lastCall[player] = nil
	local c = jobWatch[player]
	if c then
		c:Disconnect()
		jobWatch[player] = nil
	end
end

return Spawn
