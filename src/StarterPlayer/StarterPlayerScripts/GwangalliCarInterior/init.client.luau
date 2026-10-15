--!strict
-- GwangalliCarInterior (LocalScript, StarterPlayerScripts): AAA급 차량 실내 + 검은 반투명 틴팅 유리.
-- 메쉬 업로드 없이 파트로만 만들고, 전부 이 클라이언트에만 생깁니다 (서버·네트워크 부담 없음).
--   Glass    맵의 모든 차 유리를 틴팅 (앞유리 스모크 / 옆·뒤 검은 틴팅 + 반사)
--   Fit      기존 Interior 파트(핸들 림·대시·좌석·도어 트림…)에서 차마다 실내 치수를 읽음
--   Cockpit  핸들(실시간 조향 회전)·컬럼·레버·파노라믹 디스플레이(계기판+내비)·차양·HUD·시동 버튼
--   Dash     대시보드·송풍구·트림 띠·앰비언트·공조·글로브박스·A필러
--   Console  센터 콘솔·변속기(버튼/다이얼/레버)·컵홀더·무선충전·팔걸이·뒷좌석 송풍구
--   Seats    앞좌석(볼스터·퀼팅·헤드레스트·벨트) + 뒷좌석 3인 벤치
--   Trim     도어 트림·필러·헤드라이너·오버헤드 콘솔·선바이저·룸미러·매트·페달
--   Screens  계기판(속도·RPM 바늘)·내비·공조 화면 (SurfaceGui), 타는 차는 실시간 갱신
-- 성능: 카메라 근처 차 3대 + 내가 탄 차만 실내를 만들고(차당 약 400 파트, 프레임당 70개씩), 멀어지면 지웁니다.
-- 기존 Interior 파트는 지우지 않고 이 클라이언트에서만 Transparency = 1 로 숨깁니다 (좌석 Seat·스크립트 영향 없음).
-- GwangalliWorld/DetailLOD 가 차 실내(LOD = "near")를 LocalTransparencyModifier 로 켜고 끄기 때문에 그 값은 건드리지
-- 않고, 옛 화면 SurfaceGui 는 MaxDistance 로 끕니다 (DetailLOD 가 Enabled 를 되돌려도 안 보이게).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Kit = require(script:WaitForChild("Kit"))
local Fit = require(script:WaitForChild("Fit"))
local Glass = require(script:WaitForChild("Glass"))
local Cockpit = require(script:WaitForChild("Cockpit"))
local Dash = require(script:WaitForChild("Dash"))
local Console = require(script:WaitForChild("Console"))
local Seats = require(script:WaitForChild("Seats"))
local Trim = require(script:WaitForChild("Trim"))
local Screens = require(script:WaitForChild("Screens"))

local player = Players.LocalPlayer

local CFG = {
	buildRadius = 52, -- 이 안의 가까운 차부터 실내 생성
	dropRadius = 72, -- 이 밖으로 나가면 실내 제거
	maxCabins = 3, -- 동시에 유지할 실내 수 (+ 내가 탄 차). 스크립트 속성 MaxCabins 로 바꿀 수 있음
	tintRadius = 180, -- 이 안에 들어온 차부터 유리 틴팅 (한 번만)
	liveRadius = 34, -- 이 안이면 핸들·계기판 실시간
	scanBatch = 2500, -- 처음 맵 스캔: 프레임당 인스턴스 수
	steerRatio = 14, -- 앞바퀴 각도 x 조향비 = 핸들 각도
	kinds = { sedan = true, taxi = true, taxi_service = true, police = true, luxury = true, suv = true, compact = true, van = true, truck = true, ambulance = true },
}

type Rec = {
	model: Model,
	base: BasePart?,
	cabin: any?,
	building: boolean,
	failed: string?,
	failedAt: number,
	tinted: boolean,
	moving: boolean, -- 고정(Anchored)인데 CFrame 으로 움직이는 차 (클라이언트 교통 등) -> 용접 방식
}

local cars: { [Model]: Rec } = {}

---------------------------------------------------------------------------------------------------- 팔레트
local M = Enum.Material
local function lighten(c: Color3, k: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), k)
end
local function darken(c: Color3, k: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), k)
end
local function palette(F: any): any
	local C = F.colors
	local lux = F.kind == "luxury"
	local seat: Color3 = C.seat
	local dash: Color3 = C.dash
	return {
		leather = { c = seat, m = M.Leather, shadow = true },
		leatherInsert = { c = if lux then lighten(seat, 0.06) else darken(seat, 0.22), m = M.Leather },
		fabricSeat = { c = seat, m = M.Fabric, shadow = true },
		wheelLeather = { c = if lux then darken(seat, 0.25) else Color3.fromRGB(24, 24, 26), m = M.Leather },
		wheelHub = { c = Color3.fromRGB(28, 28, 31), m = M.Leather },
		soft = { c = lighten(dash, 0.05), m = M.Leather, shadow = true },
		doorSoft = { c = C.trim, m = M.Leather },
		hard = { c = dash, m = M.SmoothPlastic },
		hardDark = { c = darken(dash, 0.5), m = M.SmoothPlastic },
		gloss = { c = Color3.fromRGB(7, 7, 9), m = M.SmoothPlastic, r = 0.12 },
		screen = { c = Color3.fromRGB(3, 4, 6), m = M.Glass, r = 0.05 },
		satin = { c = Color3.fromRGB(150, 153, 158), m = M.Metal },
		chrome = { c = Color3.fromRGB(208, 211, 216), m = M.Metal, r = 0.3 },
		alloy = { c = Color3.fromRGB(176, 179, 184), m = M.Metal },
		metalDark = { c = Color3.fromRGB(58, 60, 64), m = M.Metal },
		trim = if F.wood then { c = C.wood, m = M.Wood } else { c = Color3.fromRGB(112, 115, 120), m = M.Metal },
		stitch = { c = lighten(seat, if lux then 0.55 else 0.32), m = M.SmoothPlastic },
		fabric = { c = C.liner, m = M.Fabric },
		rubber = { c = Color3.fromRGB(20, 20, 22), m = M.Rubber },
		mat = { c = Color3.fromRGB(24, 24, 26), m = M.Carpet },
		duct = { c = Color3.fromRGB(6, 6, 7), m = M.SmoothPlastic },
		button = { c = Color3.fromRGB(34, 36, 40), m = M.SmoothPlastic },
		buttonLit = { c = Color3.fromRGB(225, 236, 255), m = M.Neon, t = 0.35 },
		hazard = { c = Color3.fromRGB(196, 28, 28), m = M.SmoothPlastic },
		startBtn = { c = Color3.fromRGB(170, 22, 24), m = M.SmoothPlastic, r = 0.08 },
		paddle = { c = Color3.fromRGB(72, 74, 78), m = M.Metal },
		grille = { c = Color3.fromRGB(16, 16, 18), m = M.DiamondPlate },
		reflector = { c = Color3.fromRGB(200, 30, 20), m = M.Neon, t = 0.5 },
		lampLens = { c = Color3.fromRGB(236, 233, 222), m = M.Glass, t = 0.15 },
		mirror = { c = Color3.fromRGB(190, 198, 206), m = M.Glass, r = 0.75 },
		belt = { c = Color3.fromRGB(20, 20, 22), m = M.Fabric },
		ambient = { c = C.accent, m = M.Neon, t = 0.45 },
		accentColor = C.accent,
	}
end

---------------------------------------------------------------------------------------------------- 차 찾기
local function track(m: Instance)
	if not m:IsA("Model") or cars[m] then
		return
	end
	local kind = m:GetAttribute("VehicleKind")
	if not CFG.kinds[kind] then
		return
	end
	local rec: Rec = { model = m, base = Fit.frameOf(m), cabin = nil, building = false, failed = nil, failedAt = 0, tinted = false, moving = false }
	cars[m] = rec
end

-- 차 찾기 1: 서버가 붙이는 태그 (GwangalliEnvironment discovery: 가장 바깥 LOD = "near" 모델 = 차의 Interior 에 "NearLOD").
-- 맵 전체를 훑지 않아서 가볍고, 스트리밍으로 들어오는 차도 태그 신호로 잡힙니다.
local function fromInterior(inst: Instance)
	if inst.Name == "Interior" and inst.Parent and inst.Parent:IsA("Model") then
		track(inst.Parent)
	end
end

local function scan()
	local stack: { Instance } = { Workspace }
	local n = 0
	while #stack > 0 do
		local node = table.remove(stack) :: Instance
		for _, c in node:GetChildren() do
			n += 1
			if c:IsA("Model") then
				if c:GetAttribute("VehicleKind") ~= nil then
					track(c)
				else
					table.insert(stack, c)
				end
			elseif c:IsA("Folder") then
				table.insert(stack, c)
			end
			if n % CFG.scanBatch == 0 then
				task.wait()
			end
		end
	end
end

for _, inst in CollectionService:GetTagged("NearLOD") do
	fromInterior(inst)
end
CollectionService:GetInstanceAddedSignal("NearLOD"):Connect(fromInterior)

-- 차 찾기 2: 새로 생기는 차 (내 차 호출, 택시 등)
Workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") then
		task.defer(function()
			if d.Parent and d:GetAttribute("VehicleKind") ~= nil then
				track(d)
			end
		end)
	elseif d:IsA("BasePart") and Glass.roleOf(d) then
		-- 나중에 붙는 유리 (문 열고 닫기 리빌드 등)
		local m = d:FindFirstAncestorWhichIsA("Model")
		while m and not cars[m] do
			m = m.Parent and m.Parent:FindFirstAncestorWhichIsA("Model")
		end
		if m then
			task.defer(Glass.tint, m)
		end
	end
end)

---------------------------------------------------------------------------------------------------- 실내 만들기 / 지우기
local REPLACES: { [string]: boolean } = { WheelRim = true, WheelHub = true, WheelSpoke = true, WheelBadge = true, WingBadge = true }
for _, list in { Dash.REPLACES, Console.REPLACES, Seats.REPLACES, Trim.REPLACES } do
	for _, n in list do
		REPLACES[n] = true
	end
end

local function steerMotors(model: Model): { Motor6D }
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and d.Part1 and string.find(d.Part1.Name, "^DriveHub") and d.C0.Position.Z < 0 then
			table.insert(out, d)
		end
	end
	return out
end

local function destroyCabin(rec: Rec)
	local cab = rec.cabin
	if not cab then
		return
	end
	rec.cabin = nil
	for p, old in cab.hidden do
		if p.Parent then
			p.Transparency = old
		end
	end
	for g, old in cab.guis do
		if g.Parent then
			g.MaxDistance = old
		end
	end
	cab.folder:Destroy()
end

local function buildCabin(rec: Rec)
	rec.building = true
	rec.failed = nil
	local ok, err = pcall(function()
		local F, why = Fit.run(rec.model)
		if not F then
			rec.failed = why
			rec.failedAt = os.clock()
			rec.model:SetAttribute("GwCabinError", why)
			return
		end
		local P = palette(F)
		local folder = Instance.new("Model")
		folder.Name = "CabinAAA"
		folder:SetAttribute("GwSkinKeep", true) -- 임시 스튜디오: 실사 차체 스킨이 이 실내를 가리지 않게
		-- 주차된(고정) 차는 용접 없이 고정 파트로: 가장 가볍고(물리 어셈블리를 건드리지 않음) 실제 로블록스에서도 싸요
		local anchored = F.base.Anchored and not rec.moving
		local K = Kit.new(F.base, folder, anchored)
		local cockpit = Cockpit.build(K, F, P)
		Dash.build(K, F, P)
		Console.build(K, F, P)
		Seats.build(K, F, P)
		Trim.build(K, F, P)
		if not rec.model.Parent or cars[rec.model] ~= rec then
			folder:Destroy()
			return
		end
		-- 바뀐 기존 실내 파트 숨기기 (지우지 않음, 이 클라이언트에서만)
		local hidden, guis = {}, {}
		for _, d in F.interior:GetDescendants() do
			if d:IsA("BasePart") and REPLACES[d.Name] and not d:IsA("Seat") and not d:IsA("VehicleSeat") then
				hidden[d] = d.Transparency
				d.Transparency = 1
			elseif d:IsA("SurfaceGui") and d.Parent and REPLACES[d.Parent.Name] then
				guis[d] = d.MaxDistance
				d.MaxDistance = 0.01
			end
		end
		local ambient = {}
		for _, p in K.parts do
			if string.find(p.Name, "Ambient") then
				table.insert(ambient, p)
			end
		end
		folder.Parent = rec.model
		rec.cabin = {
			folder = folder,
			fit = F,
			cockpit = cockpit,
			hidden = hidden,
			guis = guis,
			ambient = ambient,
			anchored = anchored,
			builtCF = F.base.CFrame,
			motors = steerMotors(rec.model),
			steer = 0,
			lastScreen = 0,
			night = nil,
			parts = #K.parts,
		}
	end)
	if not ok then
		rec.failed = tostring(err)
		rec.failedAt = os.clock()
		rec.model:SetAttribute("GwCabinError", tostring(err))
		warn("[CarInterior] " .. rec.model:GetFullName() .. ": " .. tostring(err))
	elseif rec.cabin then
		rec.model:SetAttribute("GwCabinParts", rec.cabin.parts)
	end
	rec.building = false
end

---------------------------------------------------------------------------------------------------- 내가 탄 차
local function myCar(): Rec?
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if not seat then
		return nil
	end
	local node: Instance? = seat
	while node and node ~= Workspace do
		if node:IsA("Model") and cars[node :: Model] then
			return cars[node :: Model]
		end
		node = node.Parent
	end
	return nil
end

---------------------------------------------------------------------------------------------------- LOD 루프
local building = false
local function lodStep()
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local cp = cam.CFrame.Position
	-- 카메라와 내 캐릭터 중 가까운 쪽 기준 (카메라를 멀리 돌려도 옆 차 실내가 사라지지 않게)
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local rp = if root and root:IsA("BasePart") then root.Position else cp
	local mine = myCar()
	local list = {}
	for m, rec in cars do
		if not m.Parent then
			destroyCabin(rec)
			cars[m] = nil
			continue
		end
		local base = rec.base
		if not base or not base.Parent then
			rec.base = Fit.frameOf(m)
			base = rec.base
		end
		if base then
			local d = math.min((base.Position - cp).Magnitude, (base.Position - rp).Magnitude)
			if not rec.tinted and d < CFG.tintRadius then
				rec.tinted = true
				Glass.tint(m)
			end
			if rec == mine then
				d = 0
			end
			local cab = rec.cabin
			if cab and cab.anchored and (not base.Anchored or (base.Position - cab.builtCF.Position).Magnitude > 0.05) then
				-- 고정 실내를 만든 뒤 차가 풀리거나(타서 운전 시작) 움직이면 용접 방식으로 다시
				rec.moving = rec.moving or base.Anchored
				destroyCabin(rec)
			end
			if rec.cabin and d > CFG.dropRadius then
				destroyCabin(rec)
			elseif d < CFG.buildRadius and (not rec.failed or os.clock() - rec.failedAt > 8) then
				table.insert(list, { rec = rec, d = d })
			end
		end
	end
	table.sort(list, function(a, b)
		return a.d < b.d
	end)
	if list[1] then
		script:SetAttribute("Nearest", string.format("%s %.0f", list[1].rec.model.Name, list[1].d))
	end
	-- 가까운 순으로 maxCabins 개만 유지
	local maxC = tonumber(script:GetAttribute("MaxCabins")) or CFG.maxCabins
	for i, e in list do
		if i > maxC + (if mine then 1 else 0) then
			if e.rec.cabin and e.rec ~= mine then
				destroyCabin(e.rec)
			end
		elseif not e.rec.cabin and not e.rec.building and not building then
			building = true
			task.spawn(function()
				buildCabin(e.rec)
				building = false
			end)
		end
	end
end

---------------------------------------------------------------------------------------------------- 실시간 (핸들 · 계기판 · 앰비언트)
local function isNight(): boolean
	local t = Lighting.ClockTime
	return t >= 18.25 or t < 5.75
end

local function turnState(model: Model, base: BasePart): (boolean, boolean)
	local l, r = false, false
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and d.Name == "Repeater" and d.Material == Enum.Material.Neon then
			if base.CFrame:PointToObjectSpace(d.Position).X < 0 then
				l = true
			else
				r = true
			end
		end
	end
	return l, r
end

RunService.RenderStepped:Connect(function()
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local cp = cam.CFrame.Position
	local now = os.clock()
	local night = isNight()
	local mine = myCar()
	for _, rec in cars do
		local cab = rec.cabin
		local base = rec.base
		if not cab or not base then
			continue
		end
		local near = rec == mine or (base.Position - cp).Magnitude < CFG.liveRadius
		-- 앰비언트: 밤에 밝게
		if cab.night ~= night then
			cab.night = night
			for _, p in cab.ambient do
				p.Transparency = if night then 0.1 else 0.55
			end
		end
		if not near then
			continue
		end
		-- 핸들: 앞바퀴 조향 모터의 실제 각도 x 조향비
		local yaw = 0
		for _, m in cab.motors do
			if m.Parent then
				local _, ry = m.Transform:ToOrientation()
				yaw += ry
			end
		end
		if #cab.motors > 0 then
			yaw /= #cab.motors
		end
		local angle = math.clamp(-yaw * CFG.steerRatio, -7.5, 7.5)
		if math.abs(angle - cab.steer) > 0.002 then
			cab.steer = angle
			local ck = cab.cockpit
			if ck.wheelWeld then
				ck.wheelWeld.C0 = ck.wheelCF * CFrame.Angles(0, 0, angle)
			else
				ck.wheelPivot.CFrame = base.CFrame * ck.wheelCF * CFrame.Angles(0, 0, angle)
			end
		end
		-- 계기판 10 Hz
		if now - cab.lastScreen > 0.1 then
			cab.lastScreen = now
			local v = base.AssemblyLinearVelocity:Dot(base.CFrame.LookVector)
			local kmh = v * 1.08 -- 1 stud = 0.3 m
			local gear = if rec == mine then (if kmh < -0.8 then "R" elseif math.abs(kmh) < 0.5 then "N" else "D") else "P"
			local rpm = if gear == "P" or gear == "N" then 780 else 900 + (math.abs(kmh) % 40) / 40 * 3600 + math.min(math.abs(kmh), 40) * 18
			local tl, tr = turnState(rec.model, base)
			Screens.update(cab.cockpit.screens, { kmh = kmh, rpm = rpm, gear = gear, turnL = tl, turnR = tr })
		end
	end
end)

---------------------------------------------------------------------------------------------------- 시작
task.spawn(function()
	-- 태그가 없는 빌드(서버 discovery 가 꺼진 place)에서만 맵을 나눠서 훑음
	local t0 = os.clock()
	while next(cars) == nil and os.clock() - t0 < 20 do
		task.wait(1)
	end
	if next(cars) == nil then
		scan()
	end
	local n = 0
	for _ in cars do
		n += 1
	end
	print(string.format("[CarInterior] ready: %d cars (tinted glass, AAA cabins near the camera)", n))
	while true do
		local ok, err = pcall(lodStep)
		if not ok then
			warn("[CarInterior] " .. tostring(err))
		end
		local nc = 0
		for _, rec in cars do
			if rec.cabin then
				nc += 1
			end
		end
		script:SetAttribute("Cabins", nc)
		task.wait(0.35)
	end
end)
