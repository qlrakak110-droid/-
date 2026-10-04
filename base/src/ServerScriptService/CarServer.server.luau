-- Integrated Gwangalli mode: reuse the single existing ownership/economy/traffic server.
do
 local rs = game:GetService("ReplicatedStorage")
 if workspace:FindFirstChild("Gwangalli") and rs:FindFirstChild("GwangalliVehiclesShared") then
  local cfg = require(rs:WaitForChild("CarConfig"))
  local city = require(script.Parent:WaitForChild("CityBuilder")).Build(cfg)
  rs:SetAttribute("GWCarIntegration", "2.0")
  workspace:SetAttribute("GWCarIntegrationReady", city.integrated == true)
  print("[Gwangalli] CarConfig + CarBuilder linked to existing driving, garage and taxi systems")
  return
 end
end
--[[
	📁 위치: ServerScriptService  >  Script  (이름: CarServer)
	서버 담당:
	  - 도시 생성, 차량 스폰(내 차 / 매장 / NPC / 택시)
	  - 승하차 (걸어가기 → 문 열림 → 앉으면서 미끄러져 들어가기 → 문 닫힘)
	  - 교통 NPC (교차로 양보, 앞차/사람 감지 정지)
	  - 택시 호출 → 택시가 실제로 도로를 달려와서 정차 → 뒷문 탑승 → 목적지 선택 → 요금
	  - 구매/소유(저장), 연료, 주유, 손상(찌그러짐/라이트 깨짐/범퍼 떨어짐/연기), 수리, 주차 보상
]]

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local Debris = game:GetService("Debris")

local Config = require(RS:WaitForChild("CarConfig"))
local CarBuilder = require(RS:WaitForChild("CarBuilder"))
local CityBuilder = require(script.Parent:WaitForChild("CityBuilder"))

---------------------------------------------------------------- 리모트
local remotes = Instance.new("Folder")
remotes.Name = "CarRemotes"
local function newRemote(name)
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local ActionRE = newRemote("Action")
local NotifyRE = newRemote("Notify")
local StateRE = newRemote("State")
remotes.Parent = RS

local function notify(plr, text)
	NotifyRE:FireClient(plr, text)
end

---------------------------------------------------------------- 도시
local city = CityBuilder.Build(Config)

local CarsFolder = Instance.new("Folder")
CarsFolder.Name = "Cars"
CarsFolder.Parent = workspace

local carInfo = {} -- [model] = { kind, owner, busy, driver, orig, ... }

local SIDE = { DriverSeat = -1, RearLeft = -1, PassengerSeat = 1, RearRight = 1 }

---------------------------------------------------------------- 플레이어 데이터
local store
pcall(function()
	store = DataStoreService:GetDataStore("CarGame_v1")
end)

local pdata = {}
local activeCar = {}

local function setMoney(plr, v)
	local d = pdata[plr]
	if not d then
		return
	end
	d.money = math.max(0, math.floor(v))
	local ls = plr:FindFirstChild("leaderstats")
	if ls and ls:FindFirstChild("Money") then
		ls.Money.Value = d.money
	end
end
local function addMoney(plr, delta)
	local d = pdata[plr]
	if d then
		setMoney(plr, d.money + delta)
	end
end

local function refreshOwned(plr)
	local d = pdata[plr]
	local list = {}
	for _, t in ipairs(Config.SHOP_ORDER) do
		if d.owned[t] then
			table.insert(list, t)
		end
	end
	plr:SetAttribute("Owned", table.concat(list, ","))
end

local function snapshotCar(plr)
	local car = activeCar[plr]
	local d = pdata[plr]
	if car and car.Parent and d then
		d.carState[car:GetAttribute("CarType")] = { fuel = car:GetAttribute("Fuel"), health = car:GetAttribute("Health") }
	end
end

local function save(plr)
	local d = pdata[plr]
	if not (d and store) then
		return
	end
	snapshotCar(plr)
	local owned = {}
	for t in pairs(d.owned) do
		table.insert(owned, t)
	end
	pcall(function()
		store:SetAsync("u" .. plr.UserId, { money = d.money, owned = owned, carState = d.carState })
	end)
end

---------------------------------------------------------------- 문 / 슬라이드 애니메이션
local function setDoor(model, doorName, open, dur)
	local hinge = model:FindFirstChild(doorName)
	if not hinge then
		return
	end
	local w = hinge:FindFirstChild("Hinge")
	if not w then
		return
	end
	local closed = hinge:GetAttribute("ClosedC0")
	if not closed then
		closed = w.C0
		hinge:SetAttribute("ClosedC0", closed)
	end
	local target = open and (closed * CFrame.Angles(0, math.rad(hinge:GetAttribute("OpenAngle") or 70), 0)) or closed
	local info = open and TweenInfo.new(dur or 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		or TweenInfo.new(dur or 0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	TweenService:Create(w, info, { C0 = target }):Play()
	model:SetAttribute(doorName .. "Open", open)
end

local function waitWeld(seat, timeout)
	local t0 = os.clock()
	repeat
		local w = seat:FindFirstChild("SeatWeld")
		if w then
			return w
		end
		task.wait()
	until os.clock() - t0 > (timeout or 1.5)
	return nil
end

-- 키프레임: { pos = 좌석기준 위치, yaw = 회전 }
local function playKeys(weld, finalC0, keys, dur)
	local t0 = os.clock()
	while true do
		if not weld.Parent then
			return false
		end
		local a = math.clamp((os.clock() - t0) / dur, 0, 1)
		local n = #keys - 1
		local f = a * n
		local i = math.min(math.floor(f), n - 1)
		local u = f - i
		u = u * u * (3 - 2 * u)
		local k0, k1 = keys[i + 1], keys[i + 2]
		local pos = k0.pos:Lerp(k1.pos, u)
		local yaw = k0.yaw + (k1.yaw - k0.yaw) * u
		weld.C0 = CFrame.new(pos) * finalC0 * CFrame.Angles(0, yaw, 0)
		if a >= 1 then
			return true
		end
		RunService.Heartbeat:Wait()
	end
end

local function seatKeys(s)
	return {
		{ pos = Vector3.new(s * 4.0, 0.25, 0.6), yaw = -s * math.rad(90) },
		{ pos = Vector3.new(s * 2.2, 0.35, 0.25), yaw = -s * math.rad(45) },
		{ pos = Vector3.zero, yaw = 0 },
	}
end

local function updatePrompts(model)
	local info = carInfo[model]
	if not info then
		return
	end
	for _, pr in ipairs(model:GetDescendants()) do
		if pr:IsA("ProximityPrompt") then
			local seat = model:FindFirstChild(pr:GetAttribute("Seat") or "")
			local ok = seat and not seat.Occupant and not info.busy
			if pr:GetAttribute("TaxiOnly") then
				ok = ok and info.taxiWaiting == true
			end
			pr.Enabled = ok and true or false
		end
	end
end

---------------------------------------------------------------- 차량 스폰
local function groundY(pos, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	local r = workspace:Raycast(pos + Vector3.new(0, 30, 0), Vector3.new(0, -80, 0), params)
	return r and r.Position.Y or city.roadY
end

local enterCar -- forward

local function addPrompt(model, seatName, action, objectText, taxiOnly)
	local doorName = CarBuilder.SEAT_DOOR[seatName]
	local host = model:FindFirstChild(doorName) or model.PrimaryPart
	local pr = Instance.new("ProximityPrompt")
	pr.ActionText = action
	pr.ObjectText = objectText
	pr.KeyboardKeyCode = Enum.KeyCode.E
	pr.HoldDuration = 0
	pr.MaxActivationDistance = 9
	pr.RequiresLineOfSight = false
	pr:SetAttribute("Seat", seatName)
	if taxiOnly then
		pr:SetAttribute("TaxiOnly", true)
		pr.Enabled = false
	end
	pr.Parent = host
	pr.Triggered:Connect(function(plr)
		local info = carInfo[model]
		if not info then
			return
		end
		if info.kind == "player" then
			if model:GetAttribute("Owner") ~= plr.UserId then
				notify(plr, "🔒 다른 사람의 차입니다")
				return
			end
		elseif info.kind == "taxi" then
			if info.caller ~= plr then
				notify(plr, "🚕 다른 사람이 부른 택시입니다")
				return
			end
		end
		task.spawn(enterCar, plr, model, seatName)
	end)
	return pr
end

local function spawnCar(carType, groundCF, opts)
	opts = opts or {}
	local st = CarBuilder.STYLES[Config.Cars[carType].Style]
	local cf = groundCF + Vector3.new(0, st.rideH, 0)
	local model = CarBuilder.Build(carType, { CFrame = cf, Color = opts.Color })
	local root = model.PrimaryPart
	root.Anchored = true
	model.Parent = CarsFolder
	local info = { kind = opts.kind or "player", owner = opts.owner, orig = { welds = {}, parts = {}, clones = {} }, lastImpact = 0 }
	carInfo[model] = info
	if opts.owner then
		model:SetAttribute("Owner", opts.owner.UserId)
	end
	model:SetAttribute("Kind", info.kind)
	for _, d in ipairs(model:GetChildren()) do
		if d:GetAttribute("IsDoor") then
			d:SetAttribute("ClosedC0", d.Hinge.C0)
		end
	end
	for _, s in ipairs(model:GetChildren()) do
		if s:IsA("Seat") then
			s:GetPropertyChangedSignal("Occupant"):Connect(function()
				if s.Name == "DriverSeat" and not s.Occupant and info.kind == "player" then
					info.driver = nil
				end
				updatePrompts(model)
			end)
		end
	end
	if info.kind == "player" then
		addPrompt(model, "DriverSeat", "운전하기", Config.Cars[carType].Name)
	elseif info.kind == "taxi" then
		addPrompt(model, "RearRight", "택시 타기", "🚕 택시", true)
	end
	model.Destroying:Connect(function()
		carInfo[model] = nil
	end)
	return model
end

---------------------------------------------------------------- 커브(도로 가장자리) 계산
local function curbStop(pos, laneOff)
	laneOff = laneOff or city.LANE
	local N, X, S, RW = city.N, city.X, city.S, city.RW
	local best
	for j = 0, N do
		local z = X(j)
		local x = math.clamp(pos.X, X(0), X(N))
		local dd = math.abs(pos.Z - z) + math.abs(pos.X - x)
		if not best or dd < best.dist then
			local dirx = (pos.Z > z) and 1 or -1
			local i = math.clamp(math.floor((x - X(0)) / S), 0, N - 1)
			local from, to
			if dirx == 1 then
				from, to = { i, j }, { i + 1, j }
			else
				from, to = { i + 1, j }, { i, j }
			end
			local sx = math.clamp(x, X(i) + RW / 2 + 8, X(i + 1) - RW / 2 - 8)
			local dir = Vector3.new(dirx, 0, 0)
			local right = Vector3.new(-dir.Z, 0, dir.X)
			best = { dist = dd, from = from, to = to, dir = dir, pos = Vector3.new(sx, city.roadY, z) + right * laneOff }
		end
	end
	for i = 0, N do
		local x = X(i)
		local z = math.clamp(pos.Z, X(0), X(N))
		local dd = math.abs(pos.X - x) + math.abs(pos.Z - z)
		if dd < best.dist then
			local dirz = (pos.X > x) and -1 or 1
			local j = math.clamp(math.floor((z - X(0)) / S), 0, N - 1)
			local from, to
			if dirz == 1 then
				from, to = { i, j }, { i, j + 1 }
			else
				from, to = { i, j + 1 }, { i, j }
			end
			local sz = math.clamp(z, X(j) + RW / 2 + 8, X(j + 1) - RW / 2 - 8)
			local dir = Vector3.new(0, 0, dirz)
			local right = Vector3.new(-dir.Z, 0, dir.X)
			best = { dist = dd, from = from, to = to, dir = dir, pos = Vector3.new(x, city.roadY, sz) + right * laneOff }
		end
	end
	return best
end

---------------------------------------------------------------- 내 차 스폰
local function spawnPlayerCar(plr, carType, groundCF)
	local old = activeCar[plr]
	if old and old.Parent then
		for _, s in ipairs(old:GetChildren()) do
			if s:IsA("Seat") and s.Occupant then
				notify(plr, "차에 사람이 타고 있어서 바꿀 수 없어요")
				return nil
			end
		end
		snapshotCar(plr)
		old:Destroy()
	end
	local d = pdata[plr]
	local model = spawnCar(carType, groundCF, { kind = "player", owner = plr })
	local cs = d and d.carState[carType]
	if cs then
		model:SetAttribute("Fuel", math.clamp(tonumber(cs.fuel) or 100, 0, 100))
		model:SetAttribute("Health", math.clamp(tonumber(cs.health) or 100, 0, 100))
	end
	activeCar[plr] = model
	plr:SetAttribute("ActiveCar", carType)
	return model
end

---------------------------------------------------------------- 승차 / 하차
local taxis = {} -- [plr] = { agent, model, state, fare }
local onTaxiBoarded, finishTaxiRide, onTaxiExit -- forward

enterCar = function(plr, model, seatName)
	local info = carInfo[model]
	if not info or info.busy then
		return
	end
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hum and hrp) or hum.Health <= 0 or hum.SeatPart then
		return
	end
	local seat = model:FindFirstChild(seatName)
	if not seat or seat.Occupant then
		return
	end
	info.busy = true
	updatePrompts(model)
	local s = SIDE[seatName] or -1
	local doorName = CarBuilder.SEAT_DOOR[seatName]

	-- 1) 문 앞으로 걸어가기
	local stand = (seat.CFrame * CFrame.new(s * 4.4, 0, 0.6)).Position
	local standPos = Vector3.new(stand.X, hrp.Position.Y, stand.Z)
	if (hrp.Position - standPos).Magnitude > 1.5 then
		local done = false
		local conn = hum.MoveToFinished:Connect(function()
			done = true
		end)
		hum:MoveTo(standPos)
		local t0 = os.clock()
		while not done and os.clock() - t0 < 2.5 do
			task.wait()
		end
		conn:Disconnect()
	end
	if (hrp.Position - standPos).Magnitude > 9 or hum.Health <= 0 then
		info.busy = false
		updatePrompts(model)
		return
	end

	-- 2) 문 열기
	if not model:GetAttribute(doorName .. "Open") then
		setDoor(model, doorName, true)
		task.wait(0.4)
	end

	-- 3) 앉으면서 안으로 미끄러져 들어가기
	if seat.Occupant or not seat.Parent then
		info.busy = false
		updatePrompts(model)
		return
	end
	seat:Sit(hum)
	local weld = waitWeld(seat, 1.5)
	if weld then
		local finalC0 = weld.C0
		local keys = seatKeys(s)
		weld.C0 = CFrame.new(keys[1].pos) * finalC0 * CFrame.Angles(0, keys[1].yaw, 0)
		playKeys(weld, finalC0, keys, 0.9)
	end

	-- 4) 문 닫기
	setDoor(model, doorName, false, 0.4)
	task.wait(0.1)
	info.busy = false

	if not seat.Occupant then
		updatePrompts(model)
		return
	end
	if seatName == "DriverSeat" and info.kind == "player" then
		local root = model.PrimaryPart
		root.Anchored = false
		pcall(function()
			root:SetNetworkOwner(plr)
		end)
		info.driver = plr
	end
	updatePrompts(model)
	StateRE:FireClient(plr, { type = "Entered", car = model, seat = seatName, kind = info.kind })
	if info.kind == "taxi" then
		onTaxiBoarded(plr, model)
	end
end

local function exitCar(plr, force)
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hum and hrp) then
		return
	end
	local seat = hum.SeatPart
	if not seat then
		return
	end
	local model = seat.Parent
	local info = carInfo[model]
	if not info then
		local sw = seat:FindFirstChild("SeatWeld")
		if sw then
			sw:Destroy()
		end
		return
	end
	if info.busy then
		return
	end
	local root = model.PrimaryPart
	if info.kind == "taxi" and not force then
		local t = taxis[plr]
		if t and t.agent and t.agent.speed > 1.5 then
			notify(plr, "🚕 택시가 멈춘 후에 내릴 수 있어요")
			return
		end
		if t and t.state == "riding" then
			finishTaxiRide(plr, true)
			return
		end
	end
	if not force and root.AssemblyLinearVelocity.Magnitude > 12 then
		notify(plr, "⚠️ 속도를 줄인 뒤 내리세요")
		return
	end
	info.busy = true
	updatePrompts(model)
	local s = SIDE[seat.Name] or -1
	local doorName = CarBuilder.SEAT_DOOR[seat.Name]
	if seat.Name == "DriverSeat" and info.kind == "player" then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.Anchored = true
		info.driver = nil
	end
	StateRE:FireClient(plr, { type = "Exiting" })
	setDoor(model, doorName, true)
	task.wait(0.4)
	local weld = seat:FindFirstChild("SeatWeld")
	if weld then
		local finalC0 = weld.C0
		local k = seatKeys(s)
		playKeys(weld, finalC0, { k[3], k[2], k[1] }, 0.8)
	end
	local outPos = (seat.CFrame * CFrame.new(s * 4.6, 0, 0.6)).Position
	local gy = groundY(outPos, { model, char })
	outPos = Vector3.new(outPos.X, gy + 3.2, outPos.Z)
	local look = outPos + seat.CFrame.LookVector * Vector3.new(1, 0, 1)
	weld = seat:FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
	end
	hum.Sit = false
	task.wait()
	if hrp.Parent then
		hrp.CFrame = CFrame.lookAt(outPos, look)
	end
	task.wait(0.15)
	setDoor(model, doorName, false, 0.4)
	task.wait(0.1)
	info.busy = false
	updatePrompts(model)
	StateRE:FireClient(plr, { type = "Exited" })
	if info.kind == "taxi" and not force then
		onTaxiExit(plr)
	end
end

---------------------------------------------------------------- 손상 시스템
local function saveOrigWeld(info, w)
	if info.orig.welds[w] == nil then
		info.orig.welds[w] = w.C0
	end
end
local function saveOrigPart(info, p)
	if info.orig.parts[p] == nil then
		info.orig.parts[p] = { Color = p.Color, Material = p.Material, Transparency = p.Transparency }
	end
end

local function ensureEmitter(model, name, props)
	local att = model.PrimaryPart:FindFirstChild("SmokeAtt")
	if not att then
		return
	end
	local e = att:FindFirstChild(name)
	if not e then
		e = Instance.new("ParticleEmitter")
		e.Name = name
		for k, v in pairs(props) do
			e[k] = v
		end
		e.Parent = att
	end
	return e
end

local function applyDamage(model, dmg, dir)
	local info = carInfo[model]
	if not info then
		return
	end
	local zone
	if math.abs(dir.Z) >= math.abs(dir.X) then
		zone = dir.Z < 0 and "F" or "R"
	else
		zone = dir.X < 0 and "L" or "Rt"
	end
	local hp = math.max(0, (model:GetAttribute("Health") or 100) - dmg)
	model:SetAttribute("Health", hp)
	local zd = (model:GetAttribute("Dmg" .. zone) or 0) + dmg
	model:SetAttribute("Dmg" .. zone, zd)
	local inward = -dir.Unit

	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p:GetAttribute("Zone") == zone then
			local w = p:FindFirstChild("W")
			-- 찌그러짐
			if w and w:IsA("Weld") and w.Part0 then
				saveOrigWeld(info, w)
				local orig = info.orig.welds[w]
				if (w.C0.Position - orig.Position).Magnitude < 0.55 then
					local amt = math.min(0.02 * dmg, 0.22) * (0.4 + math.random() * 0.6)
					local r = math.rad(math.min(dmg * 0.15, 4))
					w.C0 = (w.C0 + inward * amt) * CFrame.Angles((math.random() - 0.5) * r, (math.random() - 0.5) * r, (math.random() - 0.5) * r)
				end
			end
			-- 라이트 깨짐
			local light = p:GetAttribute("Light")
			if light and zd > 20 and not p:GetAttribute("Broken") then
				saveOrigPart(info, p)
				p:SetAttribute("Broken", true)
				p.Material = Enum.Material.Glass
				p.Color = Color3.fromRGB(40, 40, 45)
				p.Transparency = 0.3
				local sl = p:FindFirstChildOfClass("SpotLight")
				if sl then
					sl.Enabled = false
				end
			end
			-- 유리 금감 / 깨짐
			if p:GetAttribute("Glass") then
				if p:GetAttribute("Windshield") and zd > 28 and not p:GetAttribute("Cracked") then
					saveOrigPart(info, p)
					p:SetAttribute("Cracked", true)
					p.Color = Color3.fromRGB(200, 210, 220)
					p.Transparency = 0.25
				elseif not p:GetAttribute("Windshield") and zd > 40 and p.Transparency < 1 then
					saveOrigPart(info, p)
					p.Transparency = 1
					for _ = 1, 6 do
						local shard = Instance.new("Part")
						shard.Size = Vector3.new(0.3, 0.05, 0.3)
						shard.Material = Enum.Material.Glass
						shard.Color = Color3.fromRGB(200, 220, 235)
						shard.Transparency = 0.3
						shard.CFrame = p.CFrame * CFrame.new((math.random() - 0.5) * p.Size.X, (math.random() - 0.5) * p.Size.Y, (math.random() - 0.5) * p.Size.Z)
						shard.CanQuery = false
						shard.Parent = workspace
						shard.AssemblyLinearVelocity = Vector3.new(math.random(-8, 8), math.random(4, 12), math.random(-8, 8))
						Debris:AddItem(shard, 6)
					end
				end
			end
			-- 범퍼 떨어짐
			if p:GetAttribute("Bumper") and zd > 55 and p.Parent == model and w then
				saveOrigWeld(info, w)
				local clone = p:Clone()
				table.insert(info.orig.clones, { part = clone, c0 = info.orig.welds[w] })
				w:Destroy()
				p.CanCollide = true
				p.CanQuery = true
				p.Massless = false
				p.Parent = workspace
				p.AssemblyLinearVelocity = model.PrimaryPart.AssemblyLinearVelocity * 0.5 + Vector3.new(0, 10, 0)
				Debris:AddItem(p, 20)
			end
			-- 보닛 들림
			if p:GetAttribute("Hood") and zd > 45 and w and not p:GetAttribute("Popped") then
				saveOrigWeld(info, w)
				p:SetAttribute("Popped", true)
				w.C0 = w.C0 * CFrame.new(0, 0.35, 0) * CFrame.Angles(math.rad(-7), 0, 0)
			end
		end
	end

	-- 연기 / 불
	if hp < 45 then
		local e = ensureEmitter(model, "Smoke", {
			Texture = "rbxasset://textures/particles/smoke_main.dds", Rate = 8, Lifetime = NumberRange.new(1.5, 2.5),
			Speed = NumberRange.new(3, 6), SpreadAngle = Vector2.new(20, 20), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 6) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }),
			Color = ColorSequence.new(Color3.fromRGB(150, 150, 150)), Acceleration = Vector3.new(0, 4, 0),
		})
		if e then
			e.Rate = hp < 20 and 25 or 8
			e.Color = ColorSequence.new(hp < 20 and Color3.fromRGB(50, 50, 50) or Color3.fromRGB(150, 150, 150))
		end
	end
	if hp < 20 then
		ensureEmitter(model, "Flame", {
			Texture = "rbxasset://textures/particles/fire_main.dds", Rate = 30, Lifetime = NumberRange.new(0.4, 0.8),
			Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(15, 15), LightEmission = 1,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0.2) }),
			Color = ColorSequence.new(Color3.fromRGB(255, 160, 40), Color3.fromRGB(255, 60, 20)),
		})
	end
	if hp <= 0 and info.driver then
		notify(info.driver, "💥 엔진 고장! 정비소에서 수리하세요 (📱 → 내 차 부르기로 재배치 가능)")
	end
end

local function repairCar(model)
	local info = carInfo[model]
	if not info then
		return
	end
	for w, c0 in pairs(info.orig.welds) do
		if w.Parent then
			w.C0 = c0
		end
	end
	for p, props in pairs(info.orig.parts) do
		if p.Parent then
			for k, v in pairs(props) do
				p[k] = v
			end
			p:SetAttribute("Broken", nil)
			p:SetAttribute("Cracked", nil)
			local sl = p:FindFirstChildOfClass("SpotLight")
			if sl then
				sl.Enabled = model:GetAttribute("Lights") == true
			end
		end
	end
	for _, c in ipairs(info.orig.clones) do
		local p = c.part
		local w = p:FindFirstChild("W")
		if w then
			w.Part0 = model.PrimaryPart
			w.Part1 = p
			w.C0 = c.c0
		end
		p.Parent = model
	end
	for _, p in ipairs(model:GetDescendants()) do
		if p:GetAttribute("Popped") then
			p:SetAttribute("Popped", nil)
		end
	end
	info.orig = { welds = {}, parts = {}, clones = {} }
	local att = model.PrimaryPart:FindFirstChild("SmokeAtt")
	if att then
		att:ClearAllChildren()
	end
	for _, z in ipairs({ "F", "R", "L", "Rt" }) do
		model:SetAttribute("Dmg" .. z, 0)
	end
	model:SetAttribute("Health", 100)
end

---------------------------------------------------------------- NPC 운전자
local SIT_ANIM = "rbxassetid://2506281703"
local SKIN = { Color3.fromRGB(234, 192, 160), Color3.fromRGB(204, 160, 120), Color3.fromRGB(160, 115, 80), Color3.fromRGB(245, 210, 180) }
local SHIRT = { Color3.fromRGB(30, 60, 120), Color3.fromRGB(200, 200, 200), Color3.fromRGB(40, 40, 40), Color3.fromRGB(120, 30, 40), Color3.fromRGB(60, 100, 60) }

local function makeNPCDriver(model, seatName)
	local seat = model:FindFirstChild(seatName)
	if not seat then
		return
	end
	local ok, rig = pcall(function()
		local desc = Instance.new("HumanoidDescription")
		local skin = SKIN[math.random(#SKIN)]
		desc.HeadColor = skin
		desc.LeftArmColor = skin
		desc.RightArmColor = skin
		desc.TorsoColor = SHIRT[math.random(#SHIRT)]
		local pants = Color3.fromRGB(35, 40, 55)
		desc.LeftLegColor = pants
		desc.RightLegColor = pants
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not rig or not model.Parent then
		return
	end
	rig.Name = "NPCDriver"
	for _, p in ipairs(rig:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Massless = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
		end
	end
	local hum = rig:FindFirstChildOfClass("Humanoid")
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	rig:PivotTo(seat.CFrame * CFrame.new(0, 3, 0))
	rig.Parent = model
	seat:Sit(hum)
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	local anim = Instance.new("Animation")
	anim.AnimationId = SIT_ANIM
	pcall(function()
		local tr = animator:LoadAnimation(anim)
		tr.Looped = true
		tr:Play()
	end)
end

---------------------------------------------------------------- 교통 AI (NPC 차 + 택시 공용)
local agents = {}
local reserved = {}
local CLR = city.RW / 2 + 2
local function nkey(i, j)
	return i * 1000 + j
end
local function inRange(i, j)
	return i >= 0 and j >= 0 and i <= city.N and j <= city.N
end
local function rightOf(d)
	return Vector3.new(-d.Z, 0, d.X)
end
local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function pushPt(a, pos, flags)
	local p = flags or {}
	p.pos = pos
	table.insert(a.pts, p)
end

local function bezier2(p0, c, p2, t)
	local u = 1 - t
	return p0 * (u * u) + c * (2 * u * t) + p2 * (t * t)
end
local function bezier3(p0, c1, c2, p3, t)
	local u = 1 - t
	return p0 * (u * u * u) + c1 * (3 * u * u * t) + c2 * (3 * u * t * t) + p3 * (t * t * t)
end

local function appendLeg(a, ni, nj)
	local node = city.nodePos(a.ci, a.cj)
	local dIn = a.dir
	local dOut = (city.nodePos(ni, nj) - node).Unit
	local rIn, rOut = rightOf(dIn), rightOf(dOut)
	local p0 = node - dIn * CLR + rIn * city.LANE
	local p2 = node + dOut * CLR + rOut * city.LANE
	local k = nkey(a.ci, a.cj)
	local dot = dIn:Dot(dOut)
	local pts = {}
	if dot > 0.9 then
		for n = 1, 4 do
			table.insert(pts, p0:Lerp(p2, n / 4))
		end
	elseif dot < -0.9 then
		local c1 = p0 + dIn * CLR * 1.4
		local c2 = p2 - dOut * CLR * 1.4
		for n = 1, 10 do
			table.insert(pts, bezier3(p0, c1, c2, p2, n / 10))
		end
	else
		local c = node + rIn * city.LANE + rOut * city.LANE
		for n = 1, 7 do
			table.insert(pts, bezier2(p0, c, p2, n / 7))
		end
	end
	for idx, p in ipairs(pts) do
		pushPt(a, p, { slow = dot < 0.9, exit = (idx == #pts) and k or nil })
	end
	if a.stop and a.stop.from[1] == a.ci and a.stop.from[2] == a.cj and a.stop.to[1] == ni and a.stop.to[2] == nj then
		pushPt(a, a.stop.pos, { stop = true })
		a.stop = nil
	end
	local b = city.nodePos(ni, nj) - dOut * CLR + rOut * city.LANE
	pushPt(a, b, { enter = nkey(ni, nj) })
	a.ci, a.cj, a.dir = ni, nj, dOut
end

local function extend(a)
	local guard = 0
	while #a.pts < 5 and guard < 3 do
		guard += 1
		local ni, nj
		if a.route and #a.route > 0 then
			local n = table.remove(a.route, 1)
			ni, nj = n[1], n[2]
		elseif a.mode == "taxi" then
			return
		else
			local opts = {}
			for _, d in ipairs(DIRS) do
				local ti, tj = a.ci + d[1], a.cj + d[2]
				local isBack = (d[1] == -math.round(a.dir.X) and d[2] == -math.round(a.dir.Z))
				if inRange(ti, tj) and not isBack then
					table.insert(opts, { ti, tj })
				end
			end
			if #opts == 0 then
				opts = { { a.ci - math.round(a.dir.X), a.cj - math.round(a.dir.Z) } }
			end
			local pick = opts[math.random(#opts)]
			ni, nj = pick[1], pick[2]
		end
		appendLeg(a, ni, nj)
	end
end

local function bfs(si, sj, gi, gj)
	if si == gi and sj == gj then
		return {}
	end
	local prev = {}
	local q = { { si, sj } }
	prev[nkey(si, sj)] = false
	local head = 1
	while head <= #q do
		local cur = q[head]
		head += 1
		if cur[1] == gi and cur[2] == gj then
			break
		end
		for _, d in ipairs(DIRS) do
			local ti, tj = cur[1] + d[1], cur[2] + d[2]
			if inRange(ti, tj) and prev[nkey(ti, tj)] == nil then
				prev[nkey(ti, tj)] = cur
				table.insert(q, { ti, tj })
			end
		end
	end
	local path = {}
	local c = { gi, gj }
	while c and not (c[1] == si and c[2] == sj) do
		table.insert(path, 1, c)
		c = prev[nkey(c[1], c[2])]
	end
	return path
end

local function newAgent(model, from, to, t, mode, maxSpeed)
	local fromP, toP = city.nodePos(from[1], from[2]), city.nodePos(to[1], to[2])
	local dir = (toP - fromP).Unit
	local a0 = fromP + dir * CLR + rightOf(dir) * city.LANE
	local b = toP - dir * CLR + rightOf(dir) * city.LANE
	local a = {
		model = model, root = model.PrimaryPart, mode = mode, alive = true,
		pos = a0:Lerp(b, t), heading = dir, speed = 0, maxSpeed = maxSpeed,
		pts = {}, ci = to[1], cj = to[2], dir = dir, waitT = 0, stuckT = 0, odo = 0,
		rideH = model:GetAttribute("RideH") or 2.6,
	}
	pushPt(a, b, { enter = nkey(to[1], to[2]) })
	table.insert(agents, a)
	return a
end

local function removeAgent(a)
	a.alive = false
	for k, v in pairs(reserved) do
		if v == a then
			reserved[k] = nil
		end
	end
	local i = table.find(agents, a)
	if i then
		table.remove(agents, i)
	end
	if a.model and a.model.Parent then
		a.model:Destroy()
	end
end

local function spawnTraffic()
	for _ = 1, 10 do
		local i, j = math.random(0, city.N), math.random(0, city.N)
		local d = DIRS[math.random(4)]
		local ti, tj = i + d[1], j + d[2]
		if inRange(ti, tj) then
			local fromP, toP = city.nodePos(i, j), city.nodePos(ti, tj)
			local t = math.random() * 0.8 + 0.1
			local pos = fromP:Lerp(toP, t)
			local clear = true
			for _, o in ipairs(agents) do
				if (o.pos - pos).Magnitude < 40 then
					clear = false
					break
				end
			end
			for _, p in ipairs(Players:GetPlayers()) do
				local h = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				if h and (h.Position - pos).Magnitude < 40 then
					clear = false
				end
			end
			if clear then
				local types = { "Sedan", "Hatch", "SUV", "Sedan", "Hatch" }
				local ct = types[math.random(#types)]
				local col = Config.TRAFFIC_COLORS[math.random(#Config.TRAFFIC_COLORS)]
				local dir = (toP - fromP).Unit
				local model = spawnCar(ct, CFrame.lookAt(pos, pos + dir), { kind = "traffic", Color = col })
				local a = newAgent(model, { i, j }, { ti, tj }, t, "traffic", Config.TRAFFIC_SPEED * (0.8 + math.random() * 0.3))
				a.root.CFrame = CFrame.lookAt(a.pos + Vector3.new(0, a.rideH, 0), a.pos + Vector3.new(0, a.rideH, 0) + a.heading)
				if Config.TRAFFIC_DRIVERS then
					task.spawn(makeNPCDriver, model, "DriverSeat")
				end
				return a
			end
		end
	end
end

local obstacles = {}
local function gatherObstacles()
	table.clear(obstacles)
	for _, a in ipairs(agents) do
		table.insert(obstacles, { pos = a.pos, w = a.hold and 4 or 5.5, gap = 14, agent = a })
	end
	for _, m in ipairs(CarsFolder:GetChildren()) do
		local info = carInfo[m]
		if info and info.kind == "player" and m.PrimaryPart then
			table.insert(obstacles, { pos = m.PrimaryPart.Position, w = 5, gap = 15 })
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		local c = p.Character
		local h = c and c:FindFirstChild("HumanoidRootPart")
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		if h and hum and not hum.SeatPart then
			table.insert(obstacles, { pos = h.Position, w = 4.5, gap = 9, person = true })
		end
	end
end

local function updateAgent(a, dt)
	extend(a)
	local tv = a.maxSpeed
	if a.hold then
		tv = 0
	end
	for n = 1, math.min(5, #a.pts) do
		local p = a.pts[n]
		if p.slow and (p.pos - a.pos).Magnitude < 28 then
			tv = math.min(tv, 24)
			break
		end
	end
	-- 교차로 진입 예약 (한 번에 한 대만)
	for n = 1, math.min(3, #a.pts) do
		local p = a.pts[n]
		if p.enter then
			local d = (p.pos - a.pos).Magnitude
			local r = reserved[p.enter]
			if r ~= a and d < 16 then
				if r == nil or not r.alive then
					reserved[p.enter] = a
				elseif a.waitT < 15 then
					tv = math.min(tv, math.max(0, (d - 1.5) * 2))
				end
			end
			break
		end
		if p.stop then
			break
		end
	end
	-- 정차 지점 (택시)
	for n = 1, math.min(3, #a.pts) do
		local p = a.pts[n]
		if p.stop then
			local d = (p.pos - a.pos).Magnitude
			tv = math.min(tv, math.sqrt(2 * 35 * math.max(0, d - 0.2)) + 0.5)
			break
		end
	end
	-- 앞차 / 사람 감지
	local fwd = a.heading
	local personBlock = false
	for _, o in ipairs(obstacles) do
		if o.agent ~= a then
			local rel = o.pos - a.pos
			rel = Vector3.new(rel.X, 0, rel.Z)
			local along = rel:Dot(fwd)
			if along > 0 and along < 32 then
				local lat = (rel - fwd * along).Magnitude
				if lat < o.w then
					local lim = math.max(0, (along - o.gap) * 1.6)
					if o.person and lim < 1 then
						personBlock = true
					end
					tv = math.min(tv, lim)
				end
			end
		end
	end
	if tv < 1 and not a.hold then
		a.waitT += dt
	else
		a.waitT = 0
	end
	if a.waitT > 15 and not personBlock and not a.hold then
		tv = 10 -- 교착 상태 해소
	end
	-- 가감속
	local acc = tv > a.speed and 22 or 55
	a.speed += math.clamp(tv - a.speed, -acc * dt, acc * dt)
	-- 이동
	local remain = a.speed * dt
	a.odo += remain
	while remain > 0 and a.pts[1] do
		local p = a.pts[1]
		local d = p.pos - a.pos
		local dist = d.Magnitude
		if dist <= remain then
			a.pos = p.pos
			remain -= dist
			if p.exit and reserved[p.exit] == a then
				reserved[p.exit] = nil
			end
			table.remove(a.pts, 1)
			if p.stop then
				a.speed = 0
				remain = 0
				a.hold = true
				if a.onStop then
					task.spawn(a.onStop, a)
				end
			end
		else
			a.pos += d / dist * remain
			remain = 0
		end
	end
	local nxt = a.pts[1]
	if nxt then
		local d = Vector3.new(nxt.pos.X - a.pos.X, 0, nxt.pos.Z - a.pos.Z)
		if d.Magnitude > 0.4 then
			a.heading = a.heading:Lerp(d.Unit, math.clamp(dt * 7, 0, 1)).Unit
		end
	end
	if a.root and a.root.Parent then
		local p = a.pos + Vector3.new(0, a.rideH, 0)
		a.root.CFrame = CFrame.lookAt(p, p + a.heading)
	end
	if a.speed < 0.5 and not a.hold then
		a.stuckT += dt
	else
		a.stuckT = 0
	end
end

---------------------------------------------------------------- 택시
local function taxiDests()
	local list = {}
	for _, p in ipairs(city.pois) do
		table.insert(list, p.name)
	end
	return list
end

local function sendTaxiState(plr, state, model)
	StateRE:FireClient(plr, { type = "Taxi", state = state, car = model })
end

local function taxiLeave(t)
	if not t or not t.agent then
		return
	end
	local a = t.agent
	local info = carInfo[t.model]
	if info then
		info.taxiWaiting = false
		info.caller = nil
	end
	if t.model.Parent then
		setDoor(t.model, "Door_RR", false)
		t.model:SetAttribute("Hazard", false)
		updatePrompts(t.model)
	end
	a.mode = "traffic"
	a.route = nil
	a.stop = nil
	a.hold = false
	task.delay(35, function()
		if a.alive then
			removeAgent(a)
		end
	end)
end

local function cancelTaxi(plr, silent)
	local t = taxis[plr]
	if not t then
		return
	end
	if t.state ~= "coming" and t.state ~= "waiting" then
		if not silent then
			notify(plr, "🚕 탑승 중에는 취소할 수 없어요 (정차 후 [E]로 하차)")
		end
		return
	end
	taxis[plr] = nil
	taxiLeave(t)
	sendTaxiState(plr, "gone")
	if not silent then
		notify(plr, "🚕 택시 호출을 취소했습니다")
	end
end

local function setTaxiScreen(model, text)
	local scr = model:FindFirstChild("Screen")
	local gui = scr and scr:FindFirstChild("Gui")
	if gui and gui:FindFirstChild("Text") then
		gui.Text.Text = text
	end
end

local function callTaxi(plr)
	if taxis[plr] then
		notify(plr, "🚕 이미 택시를 불렀어요")
		return
	end
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or (hum and hum.SeatPart) then
		notify(plr, "차에서 내린 후 택시를 부르세요")
		return
	end
	local stop = curbStop(hrp.Position, city.LANE + 7.5)
	local fi, fj = stop.from[1], stop.from[2]
	local pi, pj = fi - math.round(stop.dir.X), fj - math.round(stop.dir.Z)
	if not inRange(pi, pj) then
		for _, d in ipairs(DIRS) do
			local ti, tj = fi + d[1], fj + d[2]
			if inRange(ti, tj) and not (ti == stop.to[1] and tj == stop.to[2]) then
				pi, pj = ti, tj
				break
			end
		end
	end
	local fromP, toP = city.nodePos(pi, pj), city.nodePos(fi, fj)
	local dir = (toP - fromP).Unit
	local pos = fromP:Lerp(toP, 0.15)
	local model = spawnCar("Taxi", CFrame.lookAt(pos, pos + dir), { kind = "taxi" })
	local info = carInfo[model]
	info.caller = plr
	local a = newAgent(model, { pi, pj }, { fi, fj }, 0.15, "taxi", 62)
	a.root.CFrame = CFrame.lookAt(a.pos + Vector3.new(0, a.rideH, 0), a.pos + Vector3.new(0, a.rideH, 0) + a.heading)
	a.route = { { stop.to[1], stop.to[2] } }
	a.stop = stop
	local t = { agent = a, model = model, state = "coming" }
	taxis[plr] = t
	task.spawn(makeNPCDriver, model, "DriverSeat")
	setTaxiScreen(model, "🚕 예약")
	a.onStop = function()
		if taxis[plr] ~= t then
			return
		end
		if t.state == "coming" then
			t.state = "waiting"
			info.taxiWaiting = true
			model:SetAttribute("Hazard", true)
			setDoor(model, "Door_RR", true)
			updatePrompts(model)
			notify(plr, "🚕 택시 도착! 오른쪽 뒷문으로 가서 [E] 탑승")
			sendTaxiState(plr, "waiting", model)
			task.delay(90, function()
				if taxis[plr] == t and t.state == "waiting" then
					cancelTaxi(plr, true)
					notify(plr, "🚕 기다리다 택시가 떠났어요")
				end
			end)
		elseif t.state == "riding" then
			finishTaxiRide(plr, false)
		end
	end
	notify(plr, "🚕 택시를 호출했어요! 곧 도착합니다")
	sendTaxiState(plr, "coming", model)
end

onTaxiBoarded = function(plr, model)
	local t = taxis[plr]
	if not t or t.model ~= model then
		return
	end
	t.state = "boarded"
	local info = carInfo[model]
	info.taxiWaiting = false
	model:SetAttribute("Hazard", false)
	updatePrompts(model)
	setTaxiScreen(model, "🚕 목적지를 선택하세요")
	StateRE:FireClient(plr, { type = "TaxiMenu", dests = taxiDests() })
end

local function taxiGo(plr, idx)
	local t = taxis[plr]
	if not t or (t.state ~= "boarded") then
		return
	end
	local poi = city.pois[idx]
	if not poi then
		return
	end
	local a = t.agent
	local stop = curbStop(poi.pos, city.LANE + 7.5)
	local route = bfs(a.ci, a.cj, stop.from[1], stop.from[2])
	table.insert(route, { stop.to[1], stop.to[2] })
	a.route = route
	a.stop = stop
	a.hold = false
	a.odo = 0
	t.state = "riding"
	t.dest = poi.name
	notify(plr, "🚕 " .. poi.name .. "(으)로 출발합니다")
	sendTaxiState(plr, "riding", t.model)
end

finishTaxiRide = function(plr, early)
	local t = taxis[plr]
	if not t then
		return
	end
	local a = t.agent
	a.hold = true
	a.route = {}
	t.state = "arrived"
	local fare = math.floor(Config.TAXI_BASE + a.odo * Config.TAXI_PER_STUD)
	local d = pdata[plr]
	local paid = math.min(fare, d and d.money or 0)
	addMoney(plr, -paid)
	notify(plr, (early and "🚕 여기서 내립니다. " or "🚕 도착했습니다! ") .. "요금 ₩" .. paid)
	setTaxiScreen(t.model, "🚕 ₩" .. fare .. " 감사합니다")
	sendTaxiState(plr, "arrived", t.model)
	task.wait(0.3)
	exitCar(plr, true)
	taxis[plr] = nil
	task.wait(1)
	taxiLeave(t)
	sendTaxiState(plr, "gone")
end

-- 목적지 고르기 전에 내린 경우
onTaxiExit = function(plr)
	local t = taxis[plr]
	if t and t.state == "boarded" then
		taxis[plr] = nil
		taxiLeave(t)
		sendTaxiState(plr, "gone")
	end
end

---------------------------------------------------------------- 매장 (진열차 + 구매)
local displayCars = {}
local function buildDealer()
	if not city.dealerSlots then
		return
	end
	for k, carType in ipairs(Config.SHOP_ORDER) do
		local slot = city.dealerSlots[k]
		if slot then
			local spec = Config.Cars[carType]
			local model = spawnCar(carType, slot, { kind = "display" })
			local root = model.PrimaryPart
			local pr = Instance.new("ProximityPrompt")
			pr.ActionText = "구매하기  ₩" .. spec.Price
			pr.ObjectText = spec.Name
			pr.HoldDuration = 0.6
			pr.MaxActivationDistance = 14
			pr.RequiresLineOfSight = false
			pr.KeyboardKeyCode = Enum.KeyCode.E
			pr.Parent = root
			local bb = Instance.new("BillboardGui")
			bb.Size = UDim2.new(0, 200, 0, 70)
			bb.StudsOffset = Vector3.new(0, 8, 0)
			bb.MaxDistance = 90
			bb.LightInfluence = 0
			local t = Instance.new("TextLabel")
			t.Size = UDim2.fromScale(1, 1)
			t.BackgroundColor3 = Color3.fromRGB(15, 18, 25)
			t.BackgroundTransparency = 0.2
			t.TextColor3 = Color3.new(1, 1, 1)
			t.Font = Enum.Font.GothamBold
			t.TextScaled = true
			t.Text = string.format("%s\n₩%s · 최고 %dkm/h", spec.Name, tostring(spec.Price), spec.MaxSpeed)
			Instance.new("UICorner", t).CornerRadius = UDim.new(0, 12)
			t.Parent = bb
			bb.Parent = root
			pr.Triggered:Connect(function(plr)
				local d = pdata[plr]
				if not d then
					return
				end
				if d.owned[carType] then
					notify(plr, "이미 보유한 차입니다. 📱 → 내 차 부르기")
					return
				end
				if d.money < spec.Price then
					notify(plr, "💸 돈이 부족합니다 (₩" .. (spec.Price - d.money) .. " 부족)")
					return
				end
				addMoney(plr, -spec.Price)
				d.owned[carType] = true
				refreshOwned(plr)
				local car = spawnPlayerCar(plr, carType, city.deliverCF)
				if car then
					notify(plr, "🎉 " .. spec.Name .. " 구매 완료! 매장 앞에 준비했어요")
				else
					notify(plr, "🎉 구매 완료! 📱 → 내 차 부르기로 꺼내세요")
				end
				save(plr)
			end)
			table.insert(displayCars, { model = model, base = slot + Vector3.new(0, CarBuilder.STYLES[spec.Style].rideH, 0), angle = math.random() * 360 })
		end
	end
end

---------------------------------------------------------------- 리모트 처리
local lastSummon, lastPark, lastAction = {}, {}, {}

local function driverCar(plr)
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if seat and seat.Name == "DriverSeat" then
		local m = seat.Parent
		if carInfo[m] and carInfo[m].kind == "player" then
			return m
		end
	end
	return nil
end

local function inZone(part, pos)
	local rel = part.CFrame:PointToObjectSpace(pos)
	return math.abs(rel.X) <= part.Size.X / 2 and math.abs(rel.Z) <= part.Size.Z / 2
end

ActionRE.OnServerEvent:Connect(function(plr, action, a1, a2)
	if typeof(action) ~= "string" then
		return
	end
	local now = os.clock()
	if action == "Exit" then
		task.spawn(exitCar, plr, false)
	elseif action == "Impact" then
		local car = driverCar(plr)
		if car and typeof(a1) == "number" and typeof(a2) == "Vector3" and a2.Magnitude > 0.1 then
			local info = carInfo[car]
			if now - info.lastImpact > 0.3 then
				info.lastImpact = now
				local dmg = math.clamp((a1 - 28) * 0.7, 0, 40)
				if dmg >= 1 then
					applyDamage(car, dmg, a2.Unit)
				end
			end
		end
	elseif action == "FuelSync" then
		local car = driverCar(plr)
		if car and typeof(a1) == "number" then
			car:SetAttribute("Fuel", math.clamp(math.min(a1, car:GetAttribute("Fuel")), 0, 100))
		end
	elseif action == "Lights" then
		local car = driverCar(plr)
		if car then
			local on = not car:GetAttribute("Lights")
			car:SetAttribute("Lights", on)
			for _, p in ipairs(car:GetDescendants()) do
				if p:IsA("SpotLight") then
					p.Enabled = on and not p.Parent:GetAttribute("Broken")
				end
			end
		end
	elseif action == "Horn" then
		local car = driverCar(plr)
		if car and Config.HORN_SOUND_ID ~= "" and now - (lastAction[plr] or 0) > 0.5 then
			lastAction[plr] = now
			local s = Instance.new("Sound")
			s.SoundId = Config.HORN_SOUND_ID
			s.Volume = 1
			s.Parent = car.PrimaryPart
			s:Play()
			Debris:AddItem(s, 3)
		end
	elseif action == "Flip" then
		local car = driverCar(plr)
		if car then
			local root = car.PrimaryPart
			local look = root.CFrame.LookVector
			look = Vector3.new(look.X, 0, look.Z)
			if look.Magnitude < 0.1 then
				look = Vector3.new(0, 0, -1)
			end
			local pos = root.Position + Vector3.new(0, 4, 0)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			root.CFrame = CFrame.lookAt(pos, pos + look.Unit)
		end
	elseif action == "Refuel" then
		local car = driverCar(plr)
		if not car then
			return
		end
		local ok = false
		for _, z in ipairs(workspace.CityZones:GetChildren()) do
			if z.Name == "Pump" and inZone(z, car.PrimaryPart.Position) then
				ok = true
			end
		end
		if not ok then
			notify(plr, "⛽ 주유기 옆에 정차하세요")
			return
		end
		local d = pdata[plr]
		local fuel = car:GetAttribute("Fuel")
		local need = 100 - fuel
		if need < 1 then
			notify(plr, "⛽ 이미 가득 찼어요")
			return
		end
		local amount = math.min(need, math.floor(d.money / Config.FUEL_PRICE))
		if amount < 1 then
			notify(plr, "💸 주유할 돈이 없어요")
			return
		end
		local cost = math.ceil(amount * Config.FUEL_PRICE)
		addMoney(plr, -cost)
		notify(plr, "⛽ 주유 중...")
		task.wait(1.5)
		if car.Parent then
			car:SetAttribute("Fuel", math.min(100, car:GetAttribute("Fuel") + amount))
			notify(plr, "⛽ 주유 완료! (₩" .. cost .. ")")
		end
	elseif action == "Repair" then
		local car = driverCar(plr)
		if not car then
			return
		end
		local pad
		for _, z in ipairs(workspace.CityZones:GetChildren()) do
			if z.Name == "RepairPad" and inZone(z, car.PrimaryPart.Position) then
				pad = z
			end
		end
		if not pad then
			notify(plr, "🔧 정비소 리프트 위에 정차하세요")
			return
		end
		local hp = car:GetAttribute("Health")
		local missing = #carInfo[car].orig.clones
		local cost = math.ceil((100 - hp) * Config.REPAIR_PRICE) + missing * 500
		if cost <= 0 then
			notify(plr, "🔧 수리할 곳이 없어요")
			return
		end
		if pdata[plr].money < cost then
			notify(plr, "💸 수리비 ₩" .. cost .. " 가 필요해요")
			return
		end
		addMoney(plr, -cost)
		notify(plr, "🔧 수리 중...")
		task.wait(2)
		if car.Parent then
			repairCar(car)
			notify(plr, "✨ 수리 완료! (₩" .. cost .. ")")
		end
	elseif action == "Parked" then
		local car = driverCar(plr) or activeCar[plr]
		if not car or not car.Parent or typeof(a1) ~= "number" then
			return
		end
		if now - (lastPark[plr] or -999) < Config.PARK_COOLDOWN then
			return
		end
		for _, z in ipairs(workspace.CityZones:GetChildren()) do
			if z.Name == "ParkSpace" and z:GetAttribute("Index") == a1 then
				local root = car.PrimaryPart
				local align = math.abs(root.CFrame.LookVector:Dot(z.CFrame.LookVector))
				if inZone(z, root.Position) and align > 0.95 and root.AssemblyLinearVelocity.Magnitude < 2 then
					lastPark[plr] = now
					addMoney(plr, Config.PARK_REWARD)
					notify(plr, "🅿️ 주차 성공! +₩" .. Config.PARK_REWARD)
				end
			end
		end
	elseif action == "CallTaxi" then
		callTaxi(plr)
	elseif action == "CancelTaxi" then
		cancelTaxi(plr)
	elseif action == "TaxiDest" then
		if typeof(a1) == "number" then
			taxiGo(plr, a1)
		end
	elseif action == "Summon" then
		if typeof(a1) ~= "string" or not Config.Cars[a1] or not pdata[plr] or not pdata[plr].owned[a1] then
			return
		end
		if now - (lastSummon[plr] or -999) < Config.SUMMON_COOLDOWN then
			notify(plr, "잠시 후 다시 시도하세요")
			return
		end
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hrp or (hum and hum.SeatPart) then
			notify(plr, "차에서 내린 후 부르세요")
			return
		end
		lastSummon[plr] = now
		local stop = curbStop(hrp.Position, city.LANE + 7.5)
		local car = spawnPlayerCar(plr, a1, CFrame.lookAt(stop.pos, stop.pos + stop.dir))
		if car then
			notify(plr, "🚗 " .. Config.Cars[a1].Name .. " 을(를) 가까운 도로에 가져왔어요")
		end
	end
end)

---------------------------------------------------------------- 플레이어 접속
local spaceUsed = {}
local function freeSpace()
	for i, cf in ipairs(city.spaces or {}) do
		if not spaceUsed[i] then
			return i, cf
		end
	end
	return nil
end

Players.PlayerAdded:Connect(function(plr)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local money = Instance.new("IntValue")
	money.Name = "Money"
	money.Parent = ls
	ls.Parent = plr

	local d = { money = Config.START_MONEY, owned = { [Config.STARTER_CAR] = true }, carState = {} }
	if store then
		local ok, saved = pcall(function()
			return store:GetAsync("u" .. plr.UserId)
		end)
		if ok and type(saved) == "table" then
			d.money = tonumber(saved.money) or d.money
			if type(saved.owned) == "table" then
				for _, t in ipairs(saved.owned) do
					if Config.Cars[t] then
						d.owned[t] = true
					end
				end
			end
			if type(saved.carState) == "table" then
				d.carState = saved.carState
			end
		end
	end
	pdata[plr] = d
	setMoney(plr, d.money)
	refreshOwned(plr)

	plr.CharacterAdded:Connect(function()
		task.wait(1)
		if not activeCar[plr] or not activeCar[plr].Parent then
			local idx, cf = freeSpace()
			if idx then
				spaceUsed[idx] = plr
				local ground = CFrame.new(cf.Position.X, 0.45, cf.Position.Z) * cf.Rotation
				spawnPlayerCar(plr, Config.STARTER_CAR, ground)
			end
		end
		notify(plr, "🚗 주차장에 내 차가 있어요! 문 앞에서 [E]  ·  📱 폰으로 택시/차 부르기")
	end)
end)

Players.PlayerRemoving:Connect(function(plr)
	save(plr)
	cancelTaxi(plr, true)
	if activeCar[plr] then
		activeCar[plr]:Destroy()
		activeCar[plr] = nil
	end
	for i, p in pairs(spaceUsed) do
		if p == plr then
			spaceUsed[i] = nil
		end
	end
	pdata[plr] = nil
end)

game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do
		save(plr)
	end
end)

---------------------------------------------------------------- 루프
buildDealer()

for _ = 1, Config.TRAFFIC_COUNT do
	spawnTraffic()
end

RunService.Heartbeat:Connect(function(dt)
	dt = math.min(dt, 0.1)
	gatherObstacles()
	for i = #agents, 1, -1 do
		local a = agents[i]
		if a.alive then
			if not a.model.Parent then
				removeAgent(a)
			else
				updateAgent(a, dt)
				if a.mode == "traffic" and a.stuckT > 40 then
					removeAgent(a)
				end
			end
		end
	end
	for _, dc in ipairs(displayCars) do
		if dc.model.Parent then
			dc.angle += dt * 12
			dc.model.PrimaryPart.CFrame = dc.base * CFrame.Angles(0, math.rad(dc.angle), 0)
		end
	end
end)

-- 교통량 유지 / 주차 상태 고정 / 월급
task.spawn(function()
	local salaryT = 0
	while true do
		task.wait(1)
		local traffic = 0
		for _, a in ipairs(agents) do
			if a.mode == "traffic" then
				traffic += 1
			end
		end
		if traffic < Config.TRAFFIC_COUNT then
			spawnTraffic()
		end
		for model, info in pairs(carInfo) do
			if info.kind == "player" and model.Parent then
				local root = model.PrimaryPart
				local ds = model:FindFirstChild("DriverSeat")
				if not root.Anchored and not (ds and ds.Occupant) and root.AssemblyLinearVelocity.Magnitude < 4 then
					root.Anchored = true
				end
				if root.Position.Y < -50 then
					model:Destroy()
				end
			end
		end
		salaryT += 1
		if salaryT >= Config.SALARY_INTERVAL then
			salaryT = 0
			for _, plr in ipairs(Players:GetPlayers()) do
				addMoney(plr, Config.SALARY)
				notify(plr, "💰 월급 +₩" .. Config.SALARY)
			end
		end
	end
end)

-- 자동 저장
task.spawn(function()
	while true do
		task.wait(90)
		for _, plr in ipairs(Players:GetPlayers()) do
			save(plr)
		end
	end
end)

print("✅ CarServer 준비 완료")
