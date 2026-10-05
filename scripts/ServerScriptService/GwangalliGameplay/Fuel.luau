-- GwangalliGameplay/Fuel (server, feature module; owner: fuel): 연료 for the player's own cars — one more
-- everyday cost next to 정비 / 세차 / 견인 (a money sink that makes driving a choice, not a given).
--   * the called OWNED car (GwangalliVehiclesAPI "current"; rentals, job cars, stolen cars and taxis have
--     no gauge) loses FUEL.drain % per stud while its owner drives it; the level lives in d.fuel[carId]
--     (kept by Profiles) and on the car as attribute DriveFuel (0..100): the controller
--     (GwangalliVehiclesShared.Ctl.stepRoblox) cuts the engine at 0 — the car rolls to a stop, brakes /
--     steering still work, 견인 (tow) or a walk to the station fixes it.
--   * warnings at 20 % and 5 %; the goals card shows the gauge when it is low (Goals reads Fuel.level).
--   * 주유소 (the "SK 광안셀프주유소" Destination): a prompt fills the called car parked within reach:
--     cost = missing % x FUEL.pricePerPct (cash first, then the card), a partial fill when money is short.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local Fuel = {}

local ctx: any
local G: any

local FUEL = {
	drain = 1 / 140, -- % per stud driven (a full tank ~ 14,000 studs, about 4 km)
	pricePerPct = 180, -- 원 per % (a full tank 18,000원)
	warnAt = { 20, 5 },
	stationReach = 34, -- studs from the pump to the car
	newCar = 100,
}
Fuel.FUEL = FUEL

local tracked: { [Player]: { car: Model?, id: string?, last: Vector3?, warned: { [number]: boolean } } } = {}

local function api(): BindableFunction?
	local a = ServerStorage:FindFirstChild("GwangalliVehiclesAPI")
	return if a and a:IsA("BindableFunction") then a else nil
end

local function currentCar(player: Player): Model?
	local a = api()
	if not a then
		return nil
	end
	local ok, m = pcall(function()
		return a:Invoke("current", player)
	end)
	return if ok and typeof(m) == "Instance" and m:IsA("Model") then m else nil
end

local function store(player: Player): { [string]: number }?
	local d = ctx.Profiles and ctx.Profiles.get(player)
	if not d then
		return nil
	end
	if type(d.fuel) ~= "table" then
		d.fuel = {}
	end
	return d.fuel
end

function Fuel.level(player: Player): (number?, string?)
	local t = tracked[player]
	if not t or not t.id then
		return nil, nil
	end
	local f = store(player)
	return f and (f[t.id] or FUEL.newCar) or nil, t.id
end

local function setLevel(player: Player, id: string, car: Model?, v: number)
	local f = store(player)
	if not f then
		return
	end
	v = math.clamp(v, 0, 100)
	f[id] = math.floor(v * 10 + 0.5) / 10
	if car then
		car:SetAttribute("DriveFuel", f[id])
	end
	if ctx.Profiles.markDirty then
		pcall(ctx.Profiles.markDirty, player)
	end
end

local function tick()
	for _, player in Players:GetPlayers() do
		local t = tracked[player]
		if not t then
			t = { warned = {} }
			tracked[player] = t
		end
		local car = currentCar(player)
		local id = car and car:GetAttribute("DriveCarId")
		local owned = car and car:GetAttribute("DriveOwnedCar") == true
		if not car or type(id) ~= "string" or not owned then
			t.car, t.id, t.last = nil, nil, nil
			continue
		end
		local f = store(player)
		if not f then
			continue
		end
		if t.car ~= car then
			t.car, t.id = car, id
			t.last = car:GetPivot().Position
			t.warned = {}
			car:SetAttribute("DriveFuel", f[id] or FUEL.newCar)
		end
		local pos = car:GetPivot().Position
		local driver = car:GetAttribute("DriveDriver")
		if driver == player.UserId and t.last then
			local d = Vector3.new(pos.X - t.last.X, 0, pos.Z - t.last.Z).Magnitude
			if d > 0.5 and d < 400 then
				local before = f[id] or FUEL.newCar
				local after = before - d * FUEL.drain
				setLevel(player, id, car, after)
				for _, w in FUEL.warnAt do
					if before > w and after <= w and not t.warned[w] then
						t.warned[w] = true
						if ctx.notify then
							pcall(ctx.notify, player, "warn", "⛽ 연료 " .. math.floor(after) .. "%", if w <= 5 then "곧 시동이 꺼져요! SK 광안셀프주유소로" else "주유소에 들러 주세요")
						end
					end
				end
				if before > 0 and after <= 0 and ctx.notify then
					pcall(ctx.notify, player, "warn", "⛽ 연료 없음", "엔진이 멈췄어요. 견인을 부르거나 주유소에서 기름을 사 오세요")
				end
			end
		end
		t.last = pos
	end
end

local function refuel(player: Player, pump: BasePart)
	local car = currentCar(player)
	local id = car and car:GetAttribute("DriveCarId")
	if not car or type(id) ~= "string" or car:GetAttribute("DriveOwnedCar") ~= true then
		if ctx.notify then
			pcall(ctx.notify, player, "info", "⛽ 주유소", "내 차를 주유기 옆에 세워 주세요")
		end
		return
	end
	if (car:GetPivot().Position - pump.Position).Magnitude > FUEL.stationReach then
		if ctx.notify then
			pcall(ctx.notify, player, "info", "⛽ 주유소", "차를 주유기 가까이 세워 주세요")
		end
		return
	end
	local f = store(player)
	if not f then
		return
	end
	local cur = f[id] or FUEL.newCar
	local want = math.floor(100 - cur)
	if want < 1 then
		if ctx.notify then
			pcall(ctx.notify, player, "info", "⛽ 가득", "이미 연료가 가득해요")
		end
		return
	end
	local d = ctx.Profiles.get(player)
	local money = (d and d.cash or 0) + (d and d.bank or 0)
	local pct = math.min(want, math.floor(money / FUEL.pricePerPct))
	if pct < 1 then
		if ctx.notify then
			pcall(ctx.notify, player, "warn", "⛽ 잔액 부족", "기름값이 없어요 (1% = " .. FUEL.pricePerPct .. "원)")
		end
		return
	end
	local cost = pct * FUEL.pricePerPct
	if not ctx.spend(player, cost, "⛽ 주유 " .. pct .. "%") then
		return
	end
	setLevel(player, id, car, cur + pct)
	local t = tracked[player]
	if t then
		t.warned = {}
	end
	if ctx.notify then
		pcall(ctx.notify, player, "money", "⛽ 주유 완료 " .. math.floor(cur + pct) .. "%", "-" .. cost .. "원")
	end
end

local function buildStations()
	local tag = (G and G.Tags and G.Tags.Destination) or "Destination"
	for _, inst in CollectionService:GetTagged(tag) do
		if inst:IsA("BasePart") then
			local n = inst:GetAttribute("DisplayName")
			n = if type(n) == "string" then n else inst.Name
			if string.find(n, "주유소", 1, true) then
				local pump = Instance.new("Part")
				pump.Name = "FuelPump"
				pump.Size = Vector3.new(1.4, 4.2, 1)
				pump.CFrame = inst.CFrame * CFrame.new(4, 2.1, -6)
				pump.Anchored = true
				pump.Color = Color3.fromRGB(230, 70, 40)
				pump.Material = Enum.Material.SmoothPlastic
				local g = Instance.new("SurfaceGui")
				g.Face = Enum.NormalId.Front
				local t = Instance.new("TextLabel")
				t.Size = UDim2.fromScale(1, 1)
				t.BackgroundTransparency = 1
				t.Text = "⛽\n" .. FUEL.pricePerPct .. "원/%"
				t.TextScaled = true
				t.TextColor3 = Color3.new(1, 1, 1)
				t.Font = Enum.Font.GothamBold
				t.Parent = g
				g.Parent = pump
				local pr = Instance.new("ProximityPrompt")
				pr.ActionText = "주유하기"
				pr.ObjectText = n
				pr.HoldDuration = 1.2
				pr.MaxActivationDistance = 14
				pr.RequiresLineOfSight = false
				pr.Parent = pump
				pr.Triggered:Connect(function(p)
					refuel(p, pump)
				end)
				pump.Parent = workspace
			end
		end
	end
end

function Fuel.init(context: any)
	ctx = context
	G = context.G
	ctx.fuel = Fuel
	Players.PlayerRemoving:Connect(function(p)
		tracked[p] = nil
	end)
	task.delay(10, function()
		pcall(buildStations)
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(tick)
			if not ok then
				warn("[GwangalliFuel] " .. tostring(err))
			end
		end
	end)
end

return Fuel
