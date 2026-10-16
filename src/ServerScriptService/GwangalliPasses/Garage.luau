-- GwangalliPasses/Garage (server): pass #1 프리미엄 차고.
--   * four premium VehicleKinds (Shared/Cars) added to the server VS tables; their templates live in
--     ServerStorage.GwangalliPassesTemplates and are handed to GwangalliVehicles by wrapping Spawn.template
--     (prepare() calls it through the module table). Premium cars are never written into the Garage's d.cars:
--     the 3-car cap, saving, selling and loans stay untouched; ownership = owning the pass.
--   * 원격 차고 lock: Spawn.callOwned is wrapped. Without the pass an OWNED / rented car is called only inside the
--     정비소 zone (GarageShop venue pivot + radius, or the 차량 호출 kiosk). Exempt: 시승 (testDrive), the Law test
--     car, premium ids, and other add-ons that pass opts.gwAnywhere = true. Enforced here, on the server.
--   * the 차량 호출 kiosk on the 정비소 forecourt (our own Workspace folder): its prompt opens the 차 부르기 sheet.
--   * 바로 내 옆 summon: a ground frame next to the player (raycast + box check), else the nearest road lane.
--   * 출장 정비: GarageAPI "cars" -> GS.repairCost x mult -> GameplayAPI "spend" -> GarageAPI "setCondition" 100.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local Garage = {}

local ctx: any
local P: any, Config: any, Util: any, Lines: any, Cars: any, CarBodies: any
local VS: any, GS: any, Spawn: any
local templates: { [string]: Model } = {}
local lastSummon: { [Player]: number } = {}
local zoneState: { [Player]: boolean } = {}
local stationPart: BasePart? = nil
local worldFolder: Folder? = nil
local zoneCache: { pos: Vector3?, t: number } = { pos = nil, t = -1e9 }

Garage.ready = false
Garage.gateReady = false

local function vapi(op: string, ...: any): ...any
	local f = ServerStorage:FindFirstChild("GwangalliVehiclesAPI")
	if not f or not f:IsA("BindableFunction") then
		return nil
	end
	local r = table.pack(pcall((f :: BindableFunction).Invoke, f, op, ...))
	if not r[1] then
		Util.warnOnce("vehicles api " .. op, r[2])
		return nil
	end
	return table.unpack(r, 2, r.n)
end

local function garageApi(op: string, ...: any): ...any
	local f = ServerStorage:FindFirstChild("GwangalliGarageAPI")
	if not f or not f:IsA("BindableFunction") then
		return nil
	end
	local r = table.pack(pcall((f :: BindableFunction).Invoke, f, op, ...))
	if not r[1] then
		Util.warnOnce("garage api " .. op, r[2])
		return nil
	end
	return table.unpack(r, 2, r.n)
end

local function money(op: string, player: Player, amount: number, label: string): any
	local f = ServerStorage:FindFirstChild("GwangalliGameplayAPI")
	if not f or not f:IsA("BindableFunction") then
		return false
	end
	local ok, res = pcall((f :: BindableFunction).Invoke, f, op, player, amount, label)
	return ok and res
end

---------------------------------------------------------------------------------------------------
-- zone (정비소)
---------------------------------------------------------------------------------------------------
local function zoneCenter(): Vector3
	if os.clock() - zoneCache.t < 30 and zoneCache.pos then
		return zoneCache.pos :: Vector3
	end
	local pos: Vector3? = nil
	for _, s in CollectionService:GetTagged("GarageShop") do
		if s:IsA("Model") and s:IsDescendantOf(workspace) then
			pos = s:GetPivot().Position
			break
		elseif s:IsA("BasePart") then
			pos = s.Position
			break
		end
	end
	zoneCache.pos = pos or Config.GARAGE.ZONE_FALLBACK
	zoneCache.t = os.clock()
	return zoneCache.pos :: Vector3
end

function Garage.gateActive(): boolean
	return Config.GARAGE.REMOTE_LOCK == true and P.available("PremiumGarage") and Garage.gateReady
end

function Garage.inZone(player: Player): boolean
	local r = Util.root(player)
	if not r then
		return false
	end
	local pos = Util.flat(r.Position)
	if (pos - Util.flat(zoneCenter())).Magnitude <= Config.GARAGE.ZONE_RADIUS then
		return true
	end
	local st = stationPart
	if st and st.Parent and (pos - Util.flat(st.Position)).Magnitude <= Config.GARAGE.STATION_RADIUS then
		return true
	end
	return false
end

-- may this player call an owned car from where they stand?
function Garage.canCallAnywhere(player: Player): boolean
	return not Garage.gateActive() or ctx.Ownership.owns(player, "PremiumGarage")
end

---------------------------------------------------------------------------------------------------
-- templates
---------------------------------------------------------------------------------------------------
local function holder(): Folder
	local f = ServerStorage:FindFirstChild(P.TEMPLATES)
	if not f then
		f = Instance.new("Folder")
		f.Name = P.TEMPLATES
		f.Parent = ServerStorage
	end
	return f :: Folder
end

local function tagTemplate(m: Model, car: any)
	m:SetAttribute("VehicleKind", car.kind)
	m:SetAttribute(P.Attr.Premium, car.key)
	m:SetAttribute("DriveLabel", car.label)
	if car.interior then
		m:SetAttribute("InteriorStyle", car.interior)
	end
	for _, a in { "DriveRigged", "DriveRig", "DriveDriver", "NoDrive", "DriveUnlocked" } do
		m:SetAttribute(a, nil)
	end
end

local function buildTemplate(car: any, origTemplate: (string) -> Model): Model?
	local paint = Cars.paintColor(Cars.paint(car.paint))
	local m: Model? = nil
	if car.body then
		local ok, res = pcall(CarBodies.build, car.body, paint, car.glow)
		if ok then
			m = res
		else
			Util.warnOnce("body " .. car.key, res)
		end
	elseif car.base then
		local okT, base = pcall(origTemplate, car.base)
		if okT and base then
			local clone = base:Clone()
			local okK, err = pcall(function()
				if car.key == "vip" then
					CarBodies.kitVip(clone, car.glow)
				elseif car.key == "offroad" then
					CarBodies.kitOffroad(clone, car)
				end
			end)
			if not okK then
				Util.warnOnce("kit " .. car.key, err)
			end
			pcall(GS.applyColor, clone, paint, Cars.paint(car.paint).gs)
			m = clone
		else
			Util.warnOnce("base " .. car.key, base)
		end
	end
	if not m then
		return nil
	end
	m.Name = "Car_GwPremium_" .. car.key
	tagTemplate(m, car)
	m.Parent = holder()
	return m
end

local function makePreviews()
	if not Config.GARAGE.PREVIEWS then
		return
	end
	local f = ReplicatedStorage:FindFirstChild(P.PREVIEWS)
	if f then
		f:Destroy()
	end
	f = Instance.new("Folder")
	f.Name = P.PREVIEWS
	for key, t in templates do
		local c = t:Clone()
		c.Name = key
		for _, d in c:GetDescendants() do
			if d:IsA("BaseScript") or d:IsA("ProximityPrompt") or d:IsA("ClickDetector") or d:IsA("Sound") or d:IsA("Light") then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.CastShadow = false
			end
		end
		for _, a in { "VehicleKind", P.Attr.Premium } do
			c:SetAttribute(a, nil) -- never mistaken for a drivable car
		end
		c:SetAttribute("GwPreviewOf", key)
		c.Parent = f
	end
	f.Parent = ReplicatedStorage
end

---------------------------------------------------------------------------------------------------
-- paint
---------------------------------------------------------------------------------------------------
local function applyPaint(model: Model, paintId: string)
	local p = Cars.paint(paintId)
	local col = Cars.paintColor(p)
	local okC, parts = pcall(GS.applyColor, model, col, p.gs)
	if not okC or type(parts) ~= "table" then
		return
	end
	local mat = if p.mat then (Enum.Material :: any)[p.mat] else nil
	for _, part in parts do
		if part:IsA("BasePart") then
			if mat then
				part.Material = mat
			end
			part.Reflectance = p.refl or 0.05
		end
	end
	model:SetAttribute("GwPaint", p.id)
end

local function paintOf(player: Player, key: string): string
	local prof = ctx.Data.get(player)
	local id = prof.garage and prof.garage.paint and prof.garage.paint[key]
	local car = Cars.get(key)
	if type(id) == "string" and Cars.PAINT_BY_ID[id] then
		return id
	end
	return car and car.paint or "black"
end

---------------------------------------------------------------------------------------------------
-- summon
---------------------------------------------------------------------------------------------------
local function excludeList(): { Instance }
	local ex: { Instance } = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ex, p.Character)
		end
	end
	for _, n in { "GwangalliPlayerCars", P.WORLD, "GwInteriorDetailLocal" } do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(ex, f)
		end
	end
	return ex
end

local function sideFrame(player: Player): CFrame?
	local r = Util.root(player)
	if not r then
		return nil
	end
	local look = Util.flat(r.CFrame.LookVector)
	look = if look.Magnitude > 0.1 then look.Unit else Vector3.new(0, 0, -1)
	local right = look:Cross(Vector3.yAxis)
	local side = Config.GARAGE.SUMMON_SIDE
	local ex = excludeList()
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = ex
	rp.IgnoreWater = false
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = ex
	local feetY = r.Position.Y - 3
	for _, off in { right * side, -right * side, look * (side + 4), -look * (side + 4) } do
		local at = r.Position + off
		local hit = workspace:Raycast(at + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), rp)
		if hit and hit.Normal.Y > 0.86 and hit.Material ~= Enum.Material.Water and math.abs(hit.Position.Y - feetY) < 5 and hit.Position.Y > (VS.WATER_Y or 0) + 0.4 then
			local frame = CFrame.lookAt(hit.Position, hit.Position + look)
			local parts = workspace:GetPartBoundsInBox(frame * CFrame.new(0, 3.3, 0), Vector3.new(7.4, 5, 17.5), op)
			local blocked = false
			for _, part in parts do
				if part.CanCollide and part.Transparency < 0.95 and part ~= hit.Instance then
					blocked = true
					break
				end
			end
			-- the line from the player to the spot must be clear (no summoning through a wall)
			if not blocked then
				local wall = workspace:Raycast(r.Position, (hit.Position + Vector3.new(0, 2.5, 0)) - r.Position, rp)
				if wall and wall.Instance ~= hit.Instance and (wall.Position - r.Position).Magnitude < off.Magnitude - 1.5 then
					blocked = true
				end
			end
			if not blocked then
				return frame
			end
		end
	end
	return nil
end

local function stateWhy(player: Player): string?
	local why = Util.blockedState(player)
	if why == "seated" then
		return Lines.t("summon_driving")
	elseif why then
		return Lines.t("summon_state")
	end
	return nil
end

-- -> { ok, message, meters, side, car }
function Garage.summon(player: Player, key: any, mode: any): { [string]: any }
	if not Garage.ready then
		return { ok = false, code = "off", message = Lines.t("feature_off") }
	end
	if not ctx.Ownership.owns(player, "PremiumGarage") then
		return { ok = false, code = "locked", message = Lines.t("locked_tab", Config.PASSES.PremiumGarage.Title) }
	end
	local car = Cars.get(key)
	if not car or not templates[car.kind] then
		return { ok = false, code = "bad", message = Lines.t("summon_fail") }
	end
	local why = stateWhy(player)
	if why then
		return { ok = false, code = "state", message = why }
	end
	local t = os.clock()
	local cd = Config.GARAGE.SUMMON_COOLDOWN - (t - (lastSummon[player] or -1e9))
	if cd > 0 then
		return { ok = false, code = "cooldown", message = Lines.t("summon_cooldown", math.ceil(cd)) }
	end
	lastSummon[player] = t
	local r = Util.root(player) :: BasePart
	local frame = if mode == "road" then nil else sideFrame(player)
	local paintId = paintOf(player, car.key)
	local paint = Cars.paint(paintId)
	local plate = (ctx.Plate and ctx.Plate.textFor(player)) or Cars.defaultPlate(player.UserId, car.key)
	local ok, msg, model = vapi("spawnOwned", player, {
		id = Cars.carId(car.key),
		kind = car.kind,
		color = Cars.paintColor(paint),
		colorId = paint.gs,
		plate = plate,
		cond = 100,
		dirt = 0,
		label = car.label,
	}, { near = r.Position, cframe = frame, radius = Config.GARAGE.SUMMON_RADIUS, force = true })
	if not ok or typeof(model) ~= "Instance" then
		lastSummon[player] = nil
		return { ok = false, code = "spawn", message = if type(msg) == "string" then msg else Lines.t("summon_fail") }
	end
	local m = model :: Model
	m:SetAttribute(P.Attr.Premium, car.key)
	applyPaint(m, paintId)
	if ctx.Plate then
		pcall(ctx.Plate.applyTo, m, player, if car.key == "vip" then "gold" else nil)
	end
	local meters = tonumber(string.match(tostring(msg), "|(%d+)$")) or 0
	local side = frame ~= nil and meters <= 8
	ctx.Net.send(player, { kind = "garage", out = car.key })
	return { ok = true, message = if side then Lines.t("summon_side", math.max(meters, 2)) else Lines.t("summon_lane", meters), title = Lines.t("summon_arrived", car.label), meters = meters, side = side, car = m }
end

function Garage.dismiss(player: Player): { [string]: any }
	local cur = vapi("current", player)
	if typeof(cur) ~= "Instance" or not cur:GetAttribute(P.Attr.Premium) then
		return { ok = false, code = "none", message = Lines.t("summon_none") }
	end
	local ok = vapi("despawn", player, Lines.t("summon_dismissed"))
	ctx.Net.send(player, { kind = "garage", out = nil })
	return { ok = ok == true, message = if ok then Lines.t("summon_dismissed") else Lines.t("summon_fail") }
end

function Garage.setPaint(player: Player, key: any, paintId: any): { [string]: any }
	if not ctx.Ownership.owns(player, "PremiumGarage") then
		return { ok = false, code = "locked" }
	end
	local car = Cars.get(key)
	if not car or type(paintId) ~= "string" or not Cars.PAINT_BY_ID[paintId] then
		return { ok = false, code = "bad" }
	end
	ctx.Data.update(player, function(prof)
		prof.garage.paint[car.key] = paintId
	end)
	local cur = vapi("current", player)
	if typeof(cur) == "Instance" and cur:GetAttribute(P.Attr.Premium) == car.key then
		applyPaint(cur :: Model, paintId)
	end
	return { ok = true, message = Lines.t("paint_saved") }
end

---------------------------------------------------------------------------------------------------
-- 출장 정비
---------------------------------------------------------------------------------------------------
local function myCars(player: Player): { any }
	local views = garageApi("cars", player)
	local out = {}
	if type(views) ~= "table" then
		return out
	end
	for _, v in views do
		if type(v) == "table" and type(v.id) == "string" then
			local cost = 0
			if not v.rental then
				local okC, c = pcall(GS.repairCost, v.kind, v.cond, v.model)
				cost = if okC and type(c) == "number" then math.floor(c * Config.GARAGE.REPAIR_FEE_MULT + 0.5) else 0
			end
			table.insert(out, { id = v.id, label = v.label, glyph = v.glyph, plate = v.plate, cond = v.cond, band = v.band, rental = v.rental == true, color = v.color, repair = cost })
		end
	end
	return out
end

function Garage.repair(player: Player, id: any): { [string]: any }
	if not ctx.Ownership.owns(player, "PremiumGarage") then
		return { ok = false, code = "locked" }
	end
	if type(id) ~= "string" or #id > 40 then
		return { ok = false, code = "bad" }
	end
	local target = nil
	for _, v in myCars(player) do
		if v.id == id then
			target = v
		end
	end
	if not target then
		return { ok = false, code = "none", message = Lines.t("repair_none") }
	end
	if target.rental then
		return { ok = false, code = "rental", message = Lines.t("repair_rental") }
	end
	if target.repair <= 0 or (tonumber(target.cond) or 100) >= 100 then
		return { ok = false, code = "full", message = Lines.t("repair_full") }
	end
	local label = Lines.t("repair_title") .. " · " .. tostring(target.plate or target.label)
	if not money("spend", player, target.repair, label) then
		return { ok = false, code = "money", message = Lines.t("repair_money", P.won(target.repair)) }
	end
	local okSet = garageApi("setCondition", player, id, 100)
	if okSet ~= true then
		money("earn", player, target.repair, "출장 정비 환불")
		return { ok = false, code = "fail", message = Lines.t("busy") }
	end
	return { ok = true, message = Lines.t("repair_done", tostring(target.plate or target.label), P.won(target.repair)), cost = target.repair }
end

---------------------------------------------------------------------------------------------------
-- status for the phone app
---------------------------------------------------------------------------------------------------
function Garage.status(player: Player): { [string]: any }
	local owns = ctx.Ownership.owns(player, "PremiumGarage")
	local cur = vapi("current", player)
	local outKey = if typeof(cur) == "Instance" then cur:GetAttribute(P.Attr.Premium) else nil
	local cars = {}
	for _, c in Cars.LIST do
		local spec = VS and VS.Specs[c.kind]
		table.insert(cars, {
			key = c.key,
			label = c.label,
			class = c.class,
			glyph = c.glyph,
			blurb = c.blurb,
			topKmh = spec and spec.topKmh or c.spec.topKmh,
			drive = spec and spec.drive or c.spec.drive,
			seats = c.seats,
			paint = paintOf(player, c.key),
			out = outKey == c.key,
			ready = templates[c.kind] ~= nil,
		})
	end
	return {
		ok = true,
		owns = owns,
		ready = Garage.ready,
		cars = cars,
		out = outKey,
		mine = if owns then myCars(player) else {},
		gate = Garage.gateActive(),
		atGarage = Garage.inZone(player),
	}
end

---------------------------------------------------------------------------------------------------
-- the 정비소 차량 호출 kiosk
---------------------------------------------------------------------------------------------------
local function kioskText(parent: Instance, props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.TextColor3 = Color3.new(1, 1, 1)
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	for k, v in props do
		(t :: any)[k] = v
	end
	t.Parent = parent
	return t
end

local function buildStation()
	local S = Config.GARAGE.STATION
	if not S.ENABLED then
		return
	end
	local f = workspace:FindFirstChild(P.WORLD)
	if not f then
		f = Instance.new("Folder")
		f.Name = P.WORLD
		f.Parent = workspace
	end
	worldFolder = f :: Folder
	local pos: Vector3 = S.FALLBACK
	for _, part in CollectionService:GetTagged(S.FROM_TAG) do
		if part:IsA("BasePart") and part:IsDescendantOf(workspace) then
			pos = part.Position + S.OFFSET
			break
		end
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = excludeList()
	local hit = workspace:Raycast(pos + Vector3.new(0, 8, 0), Vector3.new(0, -30, 0), rp)
	local ground = if hit then hit.Position else Vector3.new(pos.X, pos.Y, pos.Z)
	local frame = CFrame.lookAt(ground, ground + S.FACING)
	local m = Instance.new("Model")
	m.Name = "VehicleCallStation"
	local function part(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = mat
		p.Anchored = true
		p.CanCollide = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = m
		return p
	end
	local navy = Color3.fromRGB(20, 26, 46)
	part("Plinth", Vector3.new(3.2, 0.3, 1.8), frame * CFrame.new(0, 0.15, 0), Color3.fromRGB(70, 72, 78), Enum.Material.Concrete)
	local body = part("Body", Vector3.new(2.4, 5.4, 1.0), frame * CFrame.new(0, 3.0, 0), navy, Enum.Material.Metal)
	body:SetAttribute(P.Attr.Station, true)
	local cap = part("Cap", Vector3.new(2.6, 0.35, 1.2), frame * CFrame.new(0, 5.85, 0), Color3.fromRGB(30, 34, 52), Enum.Material.Metal)
	cap.CanCollide = false
	local strip = part("GlowBand", Vector3.new(2.5, 0.12, 1.1), frame * CFrame.new(0, 5.62, 0), Color3.fromRGB(61, 214, 245), Enum.Material.Neon)
	strip.CanCollide = false
	strip.CastShadow = false
	local screen = part("Screen", Vector3.new(2.0, 3.0, 0.06), frame * CFrame.new(0, 3.35, -0.53), Color3.fromRGB(8, 12, 22), Enum.Material.Glass)
	screen.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(110, 220, 255)
	light.Range = 9
	light.Brightness = 1.2
	light.Shadows = false
	light.Parent = screen
	local g = Instance.new("SurfaceGui")
	g.Name = "StationGui"
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 80
	g.LightInfluence = 0
	g.Brightness = 1.4
	g.Parent = screen
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.new(1, 1, 1)
	bg.BorderSizePixel = 0
	bg.Parent = g
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(22, 40, 84), Color3.fromRGB(10, 14, 30))
	grad.Rotation = 90
	grad.Parent = bg
	kioskText(bg, { Text = "🚗", Size = UDim2.fromScale(1, 0.3), Position = UDim2.fromScale(0, 0.08) })
	kioskText(bg, { Text = Lines.t("station_title"), Size = UDim2.fromScale(0.9, 0.17), Position = UDim2.fromScale(0.05, 0.42), Font = Enum.Font.GothamBlack })
	kioskText(bg, { Text = Lines.t("station_sub"), Size = UDim2.fromScale(0.86, 0.09), Position = UDim2.fromScale(0.07, 0.62), TextColor3 = Color3.fromRGB(170, 200, 230), Font = Enum.Font.GothamMedium })
	kioskText(bg, { Text = "광안 오토", Size = UDim2.fromScale(0.6, 0.07), Position = UDim2.fromScale(0.2, 0.84), TextColor3 = Color3.fromRGB(61, 214, 245) })
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GwPassesCallPrompt"
	prompt.ActionText = Lines.t("station_title")
	prompt.ObjectText = Lines.t("station_object")
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Parent = body
	prompt.Triggered:Connect(function(player: Player)
		if Util.isPlayer(player) then
			zoneState[player] = true
			player:SetAttribute(P.Attr.AtGarage, true)
			ctx.Net.send(player, { kind = "station" })
		end
	end)
	m.Parent = f
	stationPart = body
end

---------------------------------------------------------------------------------------------------
-- start
---------------------------------------------------------------------------------------------------
local function watchCars()
	task.spawn(function()
		local f = Util.waitChild(workspace, "GwangalliPlayerCars", "Folder", 600)
		if not f then
			return
		end
		f.ChildRemoved:Connect(function(m: Instance)
			local key = m:GetAttribute(P.Attr.Premium)
			local uid = m:GetAttribute("DriveOwner")
			if key and type(uid) == "number" then
				local owner = Players:GetPlayerByUserId(uid)
				if owner then
					ctx.Net.send(owner, { kind = "garage", out = nil })
				end
			end
		end)
	end)
end

function Garage.start(c: any): boolean
	ctx = c
	P, Config, Util, Lines = c.P, c.Config, c.Util, c.P.Lines
	Cars, CarBodies = P.mod("Cars"), P.mod("CarBodies")
	VS = Util.requireShared(ReplicatedStorage, "GwangalliVehiclesShared", 90)
	GS = Util.requireShared(ReplicatedStorage, "GwangalliGarageShared", 90)
	if not VS or not GS then
		Util.warnOnce("garage", "GwangalliVehiclesShared / GwangalliGarageShared missing: 프리미엄 차고 off")
		return false
	end
	Cars.install(VS, true)
	-- the station and the zone work without the vehicles hook (they only need the map)
	pcall(buildStation)
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, p in Players:GetPlayers() do
				local inside = Garage.inZone(p)
				if zoneState[p] ~= inside then
					zoneState[p] = inside
					p:SetAttribute(P.Attr.AtGarage, inside)
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p: Player)
		zoneState[p] = nil
		lastSummon[p] = nil
	end)

	local api = Util.waitChild(ServerStorage, "GwangalliVehiclesAPI", "BindableFunction", 150)
	if not api then
		Util.warnOnce("garage", "ServerStorage.GwangalliVehiclesAPI not found: 프리미엄 차고 off")
		return false
	end
	local S, why = Util.requirePath("GwangalliVehicles", { "Spawn" }, 30)
	if not S then
		Util.warnOnce("garage", "GwangalliVehicles/Spawn: " .. tostring(why))
		return false
	end
	Spawn = S
	local origTemplate = Spawn.template
	for _, car in Cars.LIST do
		local m = buildTemplate(car, origTemplate)
		if m then
			templates[car.kind] = m
		end
	end
	Util.wrap(Spawn, "template", function(orig)
		return function(kind: string): Model
			local t = templates[kind]
			if t and t.Parent then
				return t
			end
			return orig(kind)
		end
	end)
	-- 원격 차고 lock
	Util.wrap(Spawn, "callOwned", function(orig)
		return function(player: any, spec: any, opts: any?)
			if Garage.gateActive() and Util.isPlayer(player) and type(spec) == "table" then
				local o = if type(opts) == "table" then opts else {}
				local exempt = spec.testDrive ~= nil or spec.id == "test" or o.gwAnywhere == true or Cars.keyOfId(spec.id) ~= nil
				if not exempt and not ctx.Ownership.owns(player, "PremiumGarage") and not Garage.inZone(player) then
					ctx.Net.send(player, { kind = "gate" })
					return false, Lines.t("gate_refuse"), nil
				end
			end
			return orig(player, spec, opts)
		end
	end)
	Garage.gateReady = true
	pcall(makePreviews)
	watchCars()
	-- losing the pass (admin switch off, Studio test off) sends a premium car home
	c.Ownership.onChanged(function(player: Player, key: string, owned: boolean)
		if key == "PremiumGarage" and not owned then
			local cur = vapi("current", player)
			if typeof(cur) == "Instance" and cur:GetAttribute(P.Attr.Premium) then
				vapi("despawn", player, Lines.t("summon_dismissed"))
			end
		end
	end)
	Garage.ready = next(templates) ~= nil
	return Garage.ready
end

return Garage
