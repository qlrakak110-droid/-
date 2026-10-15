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
--   Styles   차종별 실제 실내 사양 (쏘나타 DN8 · 택시 · G80 · 투싼 · 레이 · 카니발 · 포터 · 쏠라티 119)
--   Gauges   실물 계기판 (눈금 · 링 · 회전 바늘 · 7세그먼트 숫자), Screens 지도 · 글자판
--   Lights   실내등 (밤: 앰비언트 발밑 조명 · 화면 빛, 정차 중: 천장등 · 맵램프)
-- 성능: 카메라 근처 차 3대 + 내가 탄 차만 실내를 만들고(차당 약 400 파트, 프레임당 70개씩), 멀어지면 지웁니다.
-- 기존 Interior 파트는 지우지 않고 이 클라이언트에서만 Transparency = 1 로 숨깁니다 (좌석 Seat·스크립트 영향 없음).
-- GwangalliWorld/DetailLOD 가 차 실내(LOD = "near")를 LocalTransparencyModifier 로 켜고 끄기 때문에 그 값은 건드리지
-- 않고, 옛 화면 SurfaceGui 는 MaxDistance 로 끕니다 (DetailLOD 가 Enabled 를 되돌려도 안 보이게).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(script:WaitForChild("Kit"))
local Fit = require(script:WaitForChild("Fit"))
local Glass = require(script:WaitForChild("Glass"))
local Cockpit = require(script:WaitForChild("Cockpit"))
local Dash = require(script:WaitForChild("Dash"))
local Console = require(script:WaitForChild("Console"))
local Seats = require(script:WaitForChild("Seats"))
local Trim = require(script:WaitForChild("Trim"))
local Styles = require(script:WaitForChild("Styles"))
local Lights = require(script:WaitForChild("Lights"))

local player = Players.LocalPlayer

-- 그래픽 품질 단계 (GwangalliQuality 가 있으면): 저사양 폰은 실내 1대, 절전 모드는 0대
local Quality: any = nil
task.spawn(function()
	local m = ReplicatedStorage:WaitForChild("GwangalliQuality", 10)
	if m and m:IsA("ModuleScript") then
		local ok, q = pcall(require, m)
		if ok and type(q) == "table" and type(q.pick) == "function" then
			Quality = q
		end
	end
end)

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
	lastPos: Vector3?,
	lastT: number?,
	still: number, -- 연속으로 멈춰 있던 LOD 단계 수 (지나가는 차에는 실내를 만들지 않음)
	intN: number, -- Interior 자손 수 (스트리밍이 끝났는지)
}

local cars: { [Model]: Rec } = {}

---------------------------------------------------------------------------------------------------- 팔레트
-- 차종 스타일(Styles)의 실제 색. 가죽은 SmoothPlastic (Leather 재질 무늬는 가까이서 파충류 비늘처럼 보임).
-- 실내 파트는 그림자를 드리우지 않음 (지붕 · 차체가 이미 실내에 그림자를 드리우고, 큰 면의 그림자 계단 현상도 없앰)
local M = Enum.Material
local function lighten(c: Color3, k: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), k)
end
local function darken(c: Color3, k: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), k)
end
local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
local function palette(F: any): any
	local S = F.style
	local C = S.colors
	local seat: Color3 = C.seat
	local dash: Color3 = C.dash
	local accent: Color3 = C.ambient
	local SP = M.SmoothPlastic
	local trim = if S.trimMat == "wood"
		then { c = C.trim, m = M.Wood }
		elseif S.trimMat == "alu" then { c = C.trim, m = M.Metal, r = 0.05 }
		elseif S.trimMat == "black" then { c = C.trim, m = SP, r = 0.15 }
		else { c = C.trim, m = SP }
	return {
		leather = { c = seat, m = SP },
		leatherInsert = { c = C.insert or darken(seat, 0.18), m = SP },
		fabricSeat = { c = C.insert or lighten(seat, 0.05), m = M.Fabric },
		fabricSide = { c = seat, m = SP },
		wheelLeather = { c = C.wheel, m = SP },
		wheelHub = { c = lighten(C.wheel, 0.05), m = SP },
		soft = { c = lighten(dash, 0.04), m = SP },
		lower = { c = C.lower or dash, m = SP },
		doorSoft = { c = C.door or lighten(dash, 0.07), m = SP },
		hard = { c = dash, m = SP },
		hardDark = { c = darken(dash, 0.5), m = SP },
		panel = { c = lighten(dash, 0.1), m = SP },
		gloss = { c = rgb(7, 7, 9), m = SP, r = 0.12 },
		screen = { c = rgb(4, 6, 10), m = M.Glass, r = 0.06 },
		lcd = { c = rgb(10, 18, 28), m = SP, r = 0.05 },
		dialFace = { c = rgb(14, 15, 18), m = SP },
		dialBack = { c = rgb(8, 9, 11), m = SP, r = 0.04 },
		satin = { c = rgb(150, 153, 158), m = M.Metal },
		chrome = { c = rgb(184, 188, 194), m = M.Metal, r = 0.14 },
		alloy = { c = rgb(176, 179, 184), m = M.Metal },
		metalDark = { c = rgb(58, 60, 64), m = M.Metal },
		trim = trim,
		wood = { c = C.wood or rgb(74, 58, 46), m = M.Wood },
		stitch = { c = C.stitch, m = SP },
		fabric = { c = C.liner, m = M.Fabric },
		pillar = { c = darken(C.liner, 0.38), m = M.Fabric },
		rubber = { c = rgb(20, 20, 22), m = M.Rubber },
		mat = { c = rgb(24, 24, 26), m = M.Carpet },
		duct = { c = rgb(6, 6, 7), m = SP },
		button = { c = rgb(34, 36, 40), m = SP, r = 0.04 },
		buttonLit = { c = rgb(225, 236, 255), m = M.Neon, t = 0.35 },
		hazard = { c = rgb(196, 28, 28), m = SP },
		startBtn = { c = rgb(170, 22, 24), m = SP, r = 0.08 },
		paddle = { c = rgb(72, 74, 78), m = M.Metal },
		grille = { c = rgb(16, 16, 18), m = M.DiamondPlate },
		mesh = { c = rgb(120, 124, 130), m = M.DiamondPlate },
		reflector = { c = rgb(200, 30, 20), m = M.Neon, t = 0.5 },
		lampLens = { c = rgb(176, 174, 166), m = SP, r = 0.05 },
		mirror = { c = rgb(34, 38, 44), m = M.Glass, r = 0.22 },
		belt = { c = rgb(20, 20, 22), m = M.Fabric },
		ambient = if S.ambient then { c = accent, m = M.Neon, t = 0.45 } else nil,
		accentColor = accent,
		-- 계기판 · 화면 (빛나는 부분)
		seg = { c = rgb(236, 242, 250), m = M.Neon, t = 0.05 },
		segAccent = { c = accent, m = M.Neon },
		turn = { c = rgb(16, 46, 26), m = SP },
		gaugeMark = { c = rgb(222, 230, 240), m = M.Neon, t = 0.1 },
		gaugeRed = { c = rgb(255, 58, 48), m = M.Neon },
		gaugeRing = { c = accent, m = M.Neon, t = 0.15 },
		needle = { c = rgb(255, 92, 36), m = M.Neon },
		needleCap = { c = rgb(28, 30, 34), m = SP, r = 0.1 },
		markWhite = { c = rgb(215, 222, 232), m = M.Neon, t = 0.35 },
		mapUI = { c = rgb(14, 18, 25), m = M.Neon },
		mapIcon = { c = rgb(58, 72, 92), m = M.Neon },
		mapLand = { c = rgb(30, 37, 47), m = M.Neon },
		mapSea = { c = rgb(16, 46, 84), m = M.Neon },
		mapBeach = { c = rgb(120, 104, 72), m = M.Neon },
		mapBridge = { c = rgb(190, 196, 206), m = M.Neon },
		mapRoad = { c = rgb(78, 90, 106), m = M.Neon },
		mapRoute = { c = accent, m = M.Neon },
		mapMe = { c = rgb(255, 255, 255), m = M.Neon },
		lampBlue = { c = rgb(40, 90, 230), m = SP },
		lampAmber = { c = rgb(230, 150, 30), m = SP },
		ledRed = { c = rgb(255, 40, 40), m = M.Neon },
		ledGreen = { c = rgb(60, 255, 110), m = M.Neon },
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
	local rec: Rec = { model = m, base = Fit.frameOf(m), cabin = nil, building = false, failed = nil, failedAt = 0, tinted = false, moving = false, still = 0, intN = -1 }
	-- 실내가 있던 차에서 복제된 모델(교통 시스템 템플릿)은 숨김 값을 원래대로 + 따라온 옛 실내 제거
	local old = m:FindFirstChild("CabinAAA")
	if old then
		old:Destroy()
	end
	local int = m:FindFirstChild("Interior")
	if int then
		for _, d in int:GetDescendants() do
			local t = d:GetAttribute("GwCabinT")
			if type(t) == "number" and d:IsA("BasePart") then
				d.Transparency = t
				d:SetAttribute("GwCabinT", nil)
			end
			local md = d:GetAttribute("GwCabinMD")
			if type(md) == "number" and d:IsA("SurfaceGui") then
				d.MaxDistance = md
				d:SetAttribute("GwCabinMD", nil)
			end
			if d:GetAttribute("GwCabinV") == true and d:IsA("GuiObject") then
				d.Visible = true
				d:SetAttribute("GwCabinV", nil)
			end
		end
	end
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
	elseif Glass.NAMES[d.Name] then
		-- 나중에 붙는 유리 (스트리밍 / 문 리빌드): 그 유리 한 장만
		local p = d.Parent
		local rec = p and (cars[p :: any] or (p.Parent and cars[p.Parent :: any]))
		if rec and rec.tinted then
			task.defer(Glass.tintOne, d)
		end
	end
end)

---------------------------------------------------------------------------------------------------- 실내 만들기 / 지우기
local REPLACES: { [string]: boolean } = { WheelRim = true, WheelHub = true, WheelSpoke = true, WheelBadge = true, WingBadge = true, KiaLogo = true }
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

local function hideOld(cab: any, d: Instance)
	if d:IsA("BasePart") and REPLACES[d.Name] and not d:IsA("Seat") and not d:IsA("VehicleSeat") then
		if cab.hidden[d] == nil then
			cab.hidden[d] = d.Transparency
			d:SetAttribute("GwCabinT", d.Transparency) -- 복제되어도 원래 값을 알 수 있게
		end
		d.Transparency = 1
	elseif d:IsA("SurfaceGui") and d.Parent and REPLACES[d.Parent.Name] and cab.guis[d] == nil then
		-- 옛 화면 글자: 보이는 거리를 0 으로 + 안의 글자 · 판을 Visible = false (Enabled 를 다루는 DetailLOD 와 겹치지 않고,
		-- 게임 스크립트가 글자를 계속 바꿔도 오류 없음). 복제되어도 원래 값을 알 수 있게 속성으로도 남김
		local g = d :: SurfaceGui
		cab.guis[g] = { g.MaxDistance }
		g:SetAttribute("GwCabinMD", g.MaxDistance)
		g.MaxDistance = 0.01
		for _, e in g:GetDescendants() do
			if e:IsA("GuiObject") and e.Visible then
				cab.guiVis[e] = true
				e:SetAttribute("GwCabinV", true)
				e.Visible = false
			end
		end
		-- 품질 설정 등이 MaxDistance 를 되돌리면 다시 끔
		table.insert(cab.conns, g:GetPropertyChangedSignal("MaxDistance"):Connect(function()
			if g.MaxDistance ~= 0.01 and cab.alive then
				cab.guis[g][1] = g.MaxDistance
				g:SetAttribute("GwCabinMD", g.MaxDistance)
				g.MaxDistance = 0.01
			end
		end))
	end
end

local function destroyCabin(rec: Rec)
	local cab = rec.cabin
	if not cab then
		return
	end
	rec.cabin = nil
	cab.alive = false
	for _, c in cab.conns do
		c:Disconnect()
	end
	for p, old in cab.hidden do
		if p.Parent then
			p.Transparency = old
			p:SetAttribute("GwCabinT", nil)
		end
	end
	for g, old in cab.guis do
		if g.Parent then
			g.MaxDistance = old[1]
			g:SetAttribute("GwCabinMD", nil)
		end
	end
	for e in cab.guiVis do
		if e.Parent then
			e.Visible = true
			e:SetAttribute("GwCabinV", nil)
		end
	end
	cab.folder:Destroy()
end

local function buildCabin(rec: Rec)
	rec.building = true
	rec.failed = nil
	local building_folder: Instance? = nil
	local ok, err = pcall(function()
		local F, why = Fit.run(rec.model)
		if not F then
			rec.failed = why
			rec.failedAt = os.clock()
			rec.model:SetAttribute("GwCabinError", why)
			return
		end
		F.style = Styles.resolve(rec.model, F.kind)
		rec.model:SetAttribute("GwCabinStyle", F.style.key)
		if script:GetAttribute("Debug") == true then
			rec.model:SetAttribute("GwCabinFit", Fit.summary(F))
		end
		local P = palette(F)
		local folder = Instance.new("Model")
		folder.Name = "CabinAAA"
		folder.Archivable = false -- 차가 복제되어도(교통 · 리그) 따라가지 않게
		folder:SetAttribute("GwSkinKeep", true) -- 임시 스튜디오: 실사 차체 스킨이 이 실내를 가리지 않게
		folder.Parent = rec.model -- 먼저 넣어서 70개씩 나눠 들어감 (한 프레임에 몰리지 않게)
		building_folder = folder
		-- 주차된(고정) 차는 용접 없이 고정 파트로: 가장 가볍고(물리 어셈블리를 건드리지 않음) 실제 로블록스에서도 싸요
		local anchored = F.base.Anchored and not rec.moving
		local K = Kit.new(F.base, folder, anchored)
		local cockpit = Cockpit.build(K, F, P)
		Dash.build(K, F, P)
		Console.build(K, F, P)
		Seats.build(K, F, P)
		Trim.build(K, F, P)
		local lights = Lights.build(K, F, P)
		if not rec.model.Parent or cars[rec.model] ~= rec then
			folder:Destroy()
			return
		end
		local ambient = {}
		for _, p in K.parts do
			if string.find(p.Name, "Ambient") then
				table.insert(ambient, p)
			end
		end
		local cab: any = {
			alive = true,
			folder = folder,
			fit = F,
			base = F.base,
			interior = F.interior,
			cockpit = cockpit,
			lights = lights,
			guiVis = {},
			hidden = {},
			guis = {},
			conns = {},
			ambient = ambient,
			anchored = anchored,
			builtCF = F.base.CFrame,
			motors = steerMotors(rec.model),
			steer = 0,
			lastScreen = 0,
			night = nil,
			parts = #K.parts,
		}
		-- 바뀐 기존 실내 파트 숨기기 (지우지 않음, 이 클라이언트에서만) + 나중에 들어오는 파트도
		for _, d in F.interior:GetDescendants() do
			hideOld(cab, d)
		end
		table.insert(cab.conns, F.interior.DescendantAdded:Connect(function(d)
			if cab.alive then
				hideOld(cab, d)
			end
		end))
		rec.cabin = cab
	end)
	if not ok then
		if building_folder then
			building_folder:Destroy()
		end
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
local lastRp: Vector3?, lastT = nil, 0
local function maxCabins(): number
	local a = tonumber(script:GetAttribute("MaxCabins"))
	if a then
		return a
	end
	if Quality then
		local ok, v = pcall(Quality.pick, { low = 1, mid = 2, high = CFG.maxCabins, saver = 0 })
		if ok and type(v) == "number" then
			return v
		end
	end
	return CFG.maxCabins
end

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
	local fp = script:GetAttribute("FocusPoint") -- 디버그 / 미리보기: 이 위치도 '내 위치'로 취급
	if typeof(fp) == "Vector3" then
		rp = fp
	end
	local t = os.clock()
	-- 빠르게 지나가는 중이면(차를 몰고 달릴 때) 길가 차 실내는 새로 만들지 않음
	local camV = if lastRp and t > lastT then (rp - lastRp).Magnitude / (t - lastT) else 0
	lastRp, lastT = rp, t
	local mine = myCar()
	local list = {}
	for m, rec in cars do
		if not m.Parent then
			destroyCabin(rec)
			cars[m] = nil
			continue
		end
		-- 클라이언트 교통이 숨긴 정적 차 (TrafficCars 가 복제본을 대신 몰고 다님)
		local hs = m:GetAttribute("GwHideState")
		if hs == "hidden" or hs == "mixed" then
			destroyCabin(rec)
			continue
		end
		local base = rec.base
		if not base or not base.Parent or not base:IsDescendantOf(m) then
			rec.base = Fit.frameOf(m)
			base = rec.base
		end
		local cab = rec.cabin
		if cab and (cab.base ~= base or not cab.interior.Parent or cab.interior.Parent ~= m) then
			-- 탈 때 서버가 Interior 를 새로 복제했거나(Rig) 차체 파트가 바뀜: 다음 단계에 다시 만듦
			destroyCabin(rec)
			cab = nil
		elseif cab and #cab.motors == 0 then
			cab.motors = steerMotors(m) -- 조향 모터는 서버가 리그를 만들 때 생김
		end
		if base then
			local p = base.Position
			local d = math.min((p - cp).Magnitude, (p - rp).Magnitude)
			local v = if rec.lastPos and rec.lastT and t > rec.lastT then (p - rec.lastPos).Magnitude / (t - rec.lastT) else 0
			rec.lastPos, rec.lastT = p, t
			rec.still = if v < 8 then rec.still + 1 else 0
			if rec == mine then
				d = 0
			end
			if not rec.tinted and d < CFG.tintRadius then
				rec.tinted = true
				Glass.tint(m)
			end
			if cab and cab.anchored and (not base.Anchored or (p - cab.builtCF.Position).Magnitude > 0.05) then
				-- 고정 실내를 만든 뒤 차가 풀리거나(타서 운전 시작) 움직이면 용접 방식으로 다시
				rec.moving = rec.moving or base.Anchored
				destroyCabin(rec)
				cab = nil
			end
			if cab and d > CFG.dropRadius then
				destroyCabin(rec)
				cab = nil
			end
			-- 스트리밍 중인 Interior 는 다 들어온 뒤에 (자손 수가 두 번 연속 같을 때)
			local int = m:FindFirstChild("Interior")
			local n = if int then #int:GetDescendants() else 0
			local settled = n > 0 and n == rec.intN
			rec.intN = n
			local canBuild = rec == mine or (settled and rec.still >= 2 and camV < 25)
			if cab or (d < CFG.buildRadius and canBuild and (not rec.failed or t - rec.failedAt > 8)) then
				-- 이미 있는 실내는 순위 다툼에서 8 스터드 이득 (3·4등이 엎치락뒤치락해도 다시 만들지 않게)
				table.insert(list, { rec = rec, d = if cab then d - 8 else d })
			end
		elseif cab then
			destroyCabin(rec) -- 차체 파트가 스트리밍으로 빠짐
		end
	end
	table.sort(list, function(a, b)
		return a.d < b.d
	end)
	if list[1] then
		script:SetAttribute("Nearest", string.format("%s %.0f", list[1].rec.model.Name, list[1].d))
	end
	-- 가까운 순으로 maxCabins 개만 유지
	local maxC = maxCabins()
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
		if d:IsA("BasePart") and (d.Name == "Repeater" or d.Name == "TurnLamp") and d.Material == Enum.Material.Neon then
			if base.CFrame:PointToObjectSpace(d.Position).X < 0 then
				l = true
			else
				r = true
			end
		end
	end
	return l, r
end

RunService.RenderStepped:Connect(function(dt: number)
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
		-- 실내등: 밤 = 앰비언트 발밑 · 화면 빛, 내가 탄 차가 서 있으면 천장등 · 맵램프 (속성 DomeLights = 미리보기용 강제 켜기)
		local stopped = rec == mine and base.AssemblyLinearVelocity.Magnitude < 1.5
		Lights.set(cab.lights, night and (near or rec == mine), night and (stopped or script:GetAttribute("DomeLights") == true))
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
		local angle = math.clamp(yaw * CFG.steerRatio, -7.5, 7.5)
		if math.abs(angle - cab.steer) > 0.002 then
			cab.steer = angle
			local ck = cab.cockpit
			if ck.wheelWeld then
				ck.wheelWeld.C0 = ck.wheelCF * CFrame.Angles(0, 0, angle)
			else
				ck.wheelPivot.CFrame = base.CFrame * ck.wheelCF * CFrame.Angles(0, 0, angle)
			end
		end
		-- 계기판: 바늘은 매 프레임 부드럽게, 숫자 · 방향지시 · 시계는 10 Hz. 주차된 차는 시동 꺼짐 (P, 0 rpm)
		local slow = now - cab.lastScreen > 0.1
		if slow then
			cab.lastScreen = now
		end
		local running = rec == mine
		local kmh = if running then base.AssemblyLinearVelocity:Dot(base.CFrame.LookVector) * 1.08 else 0 -- 1 stud = 0.3 m
		local gear = if running then (if kmh < -0.8 then "R" else "D") else "P"
		local spd = math.abs(kmh)
		local rpm = if not running then 0 elseif spd < 0.5 then 780 else 900 + (spd % 40) / 40 * 3600 + math.min(spd, 40) * 18
		local tl, tr = false, false
		if slow and running then
			tl, tr = turnState(rec.model, base)
		end
		Cockpit.live(cab.cockpit, { kmh = kmh, rpm = rpm, gear = gear, turnL = tl, turnR = tr }, math.min(1, dt * 8), slow)
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
