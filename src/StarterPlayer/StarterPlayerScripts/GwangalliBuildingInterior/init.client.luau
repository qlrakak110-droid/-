--!strict
-- GwangalliBuildingInterior (LocalScript, StarterPlayerScripts): 광안리 매장 실내 AAA 디테일.
-- 맵의 모든 들어갈 수 있는 매장(거리 상점 · GwShop 7곳 · Annex 매장)에, 플레이어가 가까이 가면 이 클라이언트에서만
-- 실제 한국 매장처럼 꾸민 실내를 짓고 멀어지면 지웁니다. 서버 · 다른 플레이어 · 게임 판정에는 영향 없음.
--   Scan      매장 치수 · 방향 · 기존 가구 묶음 · 비워 둘 공간(자동문 앞 · 직원 자리 · 테이블 위 · 통로 ...)
--   Kit       파트 조립 (매장 프레임, 시간 분할, 비워 둘 공간 자동 회피)
--   Props     의자 · 스툴 · 테이블 · 카운터 리스킨, 조명, 액자 · 메뉴판 · TV · 시계 · 선반 · 냉장고 · 화분 ...
--   Common    모든 매장 공통 마감 (천장 · 벽 · 바닥 · 설비 · 스위치 · 시계)
--   T_*       유형별 실내 (카페 · 펍 · 한식 · 구이/포차 · 횟집 · 치킨/버거/분식 · 편의점/상점/약국 · 로비/사무 · 미용/옷/서프)
--   Interact  이 클라이언트 전용 상호작용 (R 키: 조명 · TV · 냉장고 문 · ...) + 애니메이션 (시계 · 화면)
-- 규칙 (맵 시스템 조사 결과 R1-R15): 맵 파트는 지우거나 옮기지 않고 이 클라이언트에서 보이지만 않게 하며,
-- 좌석 · 테이블 · 계산대 같은 게임플레이 파트는 같은 자리에 덮어씌우는 리스킨만 합니다.
-- 스크립트 속성: Enabled (false = 끔), MaxVenues (동시에 지을 매장 수), Debug (true = 로그), FocusPoint (Vector3, 테스트용)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Scan = require(script:WaitForChild("Scan"))
local Build = require(script:WaitForChild("Build"))
local Venues = require(script:WaitForChild("Venues"))
local Homes = require(script:WaitForChild("Homes"))

local player = Players.LocalPlayer

local CFG = {
	buildR = 22, -- 매장 바닥 상자에서 이만큼 안이면 짓기
	dropR = 46, -- 이만큼 멀어지면 지우기
	maxVenues = 2,
	maxParts = 2600,
	maxLights = 8,
	tick = 0.35,
	scanBatch = 3000,
	retry = 25,
}

-- 품질 단계 (GwangalliQuality 가 있으면): 저사양은 1곳 · 파트 적게
local Quality: any = nil
task.spawn(function()
	local m = ReplicatedStorage:WaitForChild("GwangalliQuality", 10)
	if m and m:IsA("ModuleScript") then
		local ok, q = pcall(require, m)
		if ok and type(q) == "table" then
			Quality = q
		end
	end
end)
local function tier(): string
	if Quality then
		local ok, t = pcall(function()
			return if type(Quality.get) == "function" then Quality.get() elseif type(Quality.pick) == "function" then Quality.pick() else nil
		end)
		if ok and type(t) == "string" then
			return t
		elseif ok and type(t) == "table" and type(t.name) == "string" then
			return t.name
		end
	end
	local UIS = game:GetService("UserInputService")
	return if UIS.TouchEnabled and not UIS.KeyboardEnabled then "low" else "high"
end
local function limits(): (number, number, number)
	local t = tier()
	local mv = script:GetAttribute("MaxVenues")
	if t == "low" or t == "saver" then
		return (if type(mv) == "number" then mv else 1), 1300, 4
	elseif t == "mid" then
		return (if type(mv) == "number" then mv else 2), 2100, 6
	end
	return (if type(mv) == "number" then mv else CFG.maxVenues), CFG.maxParts, CFG.maxLights
end

local function dbg(...)
	if script:GetAttribute("Debug") then
		print("[GwangalliBuildingInterior]", ...)
	end
end

-- 우리 루트 (R2): 맵 밖 폴더, LOD = near (GwangalliTextures 가 우리 파트에 텍스처를 안 붙임)
local root = Instance.new("Folder")
root.Name = "GwInteriorDetailLocal"
root:SetAttribute("LOD", "near")
root.Parent = Workspace

-- 후보 매장 ----------------------------------------------------------------------------------------
type Rec = {
	model: Model,
	spec: any?, -- 큰 시설의 방 (Venues) · 집의 방 (Homes): Scan.fitRoom 용 spec
	room: any?,
	home: boolean?,
	center: Vector3?,
	half: Vector3?,
	built: any?,
	folder: Model?,
	building: boolean,
	failed: string?,
	failedAt: number,
	nParts: number,
	conns: { RBXScriptConnection },
}
local recs: { [any]: Rec } = {} -- 매장: Model 키, 큰 시설의 방: spec.key 문자열 키
local SKIP_ROOTS = { "club", "bowling", "garage", "hospital", "homes", "npcnav", "zones" }

local function skipped(m: Instance): boolean
	if m:GetAttribute("GwInterior") == false or m:GetAttribute("ShopLife") == false then
		return true
	end
	if m:GetAttribute("OwnerUserId") ~= nil or CollectionService:HasTag(m, "GwB_Unit") then
		return true
	end
	local g = Workspace:FindFirstChild("Gwangalli")
	if g then
		for _, n in SKIP_ROOTS do
			local r = g:FindFirstChild(n)
			if r and m:IsDescendantOf(r) then
				return true
			end
		end
	end
	local homes = Workspace:FindFirstChild("GwangalliHomeInstances")
	if homes and m:IsDescendantOf(homes) then
		return true
	end
	return false
end

local function isShop(m: Instance): boolean
	if not m:IsA("Model") then
		return false
	end
	if m:FindFirstChild("ShopFloor") and (m:FindFirstChild("Interior") or m:GetAttribute("AnnexRoom")) then
		return true
	end
	if CollectionService:HasTag(m, "GwShop") or m:GetAttribute("ShopId") ~= nil then
		return m:FindFirstChild("ShopBounds", true) ~= nil
	end
	return false
end

local function addCandidate(m: Instance?)
	if not m or recs[m :: Model] or not isShop(m) or skipped(m) then
		return
	end
	local model = m :: Model
	local rec: Rec = { model = model, building = false, failedAt = -1e9, nParts = 0, conns = {} }
	recs[model] = rec
	table.insert(rec.conns, model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			local r = recs[model]
			if r then
				r.center = nil
			end
		end
	end))
end

local function fromTagged(inst: Instance)
	if inst:IsA("Model") then
		if CollectionService:HasTag(inst, "GwShop") then
			addCandidate(inst)
			return
		end
		local p = inst.Parent
		if p then
			addCandidate(p)
		end
	end
end

for _, tag in { "AutoDoor", "NearLOD", "ZoneLOD", "GwShop" } do
	for _, inst in CollectionService:GetTagged(tag) do
		fromTagged(inst)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(fromTagged)
end

-- 태그가 없는 환경(임시 스튜디오 등)을 위한 한 번의 분할 스캔
task.spawn(function()
	task.wait(2)
	local n = 0
	for _ in recs do
		n += 1
	end
	if n > 20 then
		return
	end
	local g = Workspace:FindFirstChild("Gwangalli")
	if not g then
		return
	end
	local stack = { g }
	local count = 0
	while #stack > 0 do
		local node = table.remove(stack) :: Instance
		for _, c in node:GetChildren() do
			count += 1
			if c:IsA("Model") and isShop(c) then
				addCandidate(c)
			elseif c:IsA("Model") or c:IsA("Folder") then
				table.insert(stack, c)
			end
			if count % CFG.scanBatch == 0 then
				task.wait()
			end
		end
	end
	dbg("fallback scan", count)
end)

-- Annex 매장 (y ~3000 대역): 플레이어가 그 안에 있을 때만
local function annexScan(pos: Vector3)
	if pos.Y < 2500 then
		return
	end
	local gb = Workspace:FindFirstChild("GwangalliBuildings")
	if not gb then
		return
	end
	for _, d in gb:GetDescendants() do
		if d:IsA("Model") and d:FindFirstChild("ShopFloor") then
			local f = d:FindFirstChild("ShopFloor") :: BasePart
			if f:IsA("BasePart") and (f.Position - pos).Magnitude < 90 then
				addCandidate(d)
			end
		end
	end
end

-- 큰 시설 (PC방 · 노래방 · GS25 본점 · 딜리버리 ...): 방마다 후보 하나 (스트리밍으로 늦게 오면 다음 검사 때)
local function venueScan()
	for _, f in Venues.find() do
		local spec = Venues.spec(f.model, f.venue, f.room)
		if not recs[spec.key] and not skipped(f.model) then
			local r = f.room
			local rec: Rec = { model = f.model, spec = spec, room = r, building = false, failedAt = -1e9, nParts = 0, conns = {} }
			rec.center = r.center + Vector3.new(0, 4, 0)
			rec.half = Vector3.new(r.size.X / 2, 6, r.size.Z / 2)
			recs[spec.key] = rec
		end
	end
end
task.spawn(function()
	for _ = 1, 40 do
		pcall(venueScan)
		task.wait(6)
	end
end)

-- 생활 게임 집 (방문 · 내 집): 집에 들어가 있을 때 (y 900 이상 대역) 방마다 후보
local function homeScan()
	for _, f in Homes.find() do
		local spec = f.spec
		if not recs[spec.key] then
			local rec: Rec = { model = f.model, spec = spec, room = nil, building = false, failedAt = -1e9, nParts = 0, conns = {} }
			rec.home = true
			local half = Vector3.new(spec.size.X / 2, 6, spec.size.Z / 2)
			rec.center = spec.cf.Position + Vector3.new(0, 4, 0)
			-- 월드 축 상자 (방 프레임이 돌아가 있으면 X/Z 를 바꿈)
			if math.abs(spec.cf.LookVector.X) > 0.7 then
				half = Vector3.new(half.Z, half.Y, half.X)
			end
			rec.half = half
			recs[spec.key] = rec
		end
	end
end

-- 거리 계산용 바닥 상자
local function boxOf(rec: Rec): (Vector3?, Vector3?)
	if rec.center then
		return rec.center, rec.half
	end
	local floor, bounds = Scan.findFloor(rec.model)
	local p = bounds or floor
	if not p then
		return nil, nil
	end
	local s = p.Size
	local r = p.CFrame
	local hx = (math.abs(r.XVector.X) * s.X + math.abs(r.YVector.X) * s.Y + math.abs(r.ZVector.X) * s.Z) / 2
	local hz = (math.abs(r.XVector.Z) * s.X + math.abs(r.YVector.Z) * s.Y + math.abs(r.ZVector.Z) * s.Z) / 2
	rec.center = Vector3.new(p.Position.X, p.Position.Y + 4, p.Position.Z)
	rec.half = Vector3.new(hx, 6, hz)
	return rec.center, rec.half
end

local function distTo(rec: Rec, pos: Vector3): number
	local c, h = boxOf(rec)
	if not c or not h then
		return math.huge
	end
	local d = pos - c
	local dx = math.max(0, math.abs(d.X) - h.X)
	local dy = math.max(0, math.abs(d.Y) - h.Y)
	local dz = math.max(0, math.abs(d.Z) - h.Z)
	return math.sqrt(dx * dx + dy * dy * 2 + dz * dz)
end

-- 짓기 / 지우기 ------------------------------------------------------------------------------------
local active: { Rec } = {}
local busy = false

local function destroy(rec: Rec)
	local K = rec.built
	if K then
		for _, c in K.conns or {} do
			c:Disconnect()
		end
		Scan.restore(K.hidden)
		rec.built = nil
	end
	if rec.folder then
		rec.folder:Destroy()
		rec.folder = nil
	end
	for i, a in active do
		if a == rec then
			table.remove(active, i)
			break
		end
	end
end

local function onShift(): boolean
	return player:GetAttribute("OnShift") == true or player:GetAttribute("GwWorkShift") ~= nil or player:GetAttribute("GwMgrDuty") == true
end
local SHIFT_WORDS = { "STARBUCKS", "스타벅스", "GS25 광안리점", "행복 돼지국밥" }

local function build(rec: Rec)
	busy = true
	rec.building = true
	local t0 = os.clock()
	local ok, err = pcall(function()
		local name = rec.model.Name
		if onShift() then
			for _, w in SHIFT_WORDS do
				if string.find(name, w, 1, true) then
					error("on shift", 0)
				end
			end
		end
		local V, why
		if rec.spec then
			V, why = Scan.fitRoom(rec.model, rec.spec)
			if V and rec.home then
				Homes.post(V, rec.model)
			elseif V then
				Venues.post(V, rec.room)
			end
		else
			V, why = Scan.fit(rec.model)
		end
		if not V then
			error(why or "fit failed", 0)
		end
		local mv, mp, ml = limits()
		V.maxParts, V.maxLights = mp, ml
		local folder = Instance.new("Model")
		folder.Name = V.name
		folder:SetAttribute("ShopKey", V.key)
		folder:SetAttribute("ShopType", V.type or "generic")
		folder.Parent = root
		rec.folder = folder
		local K = Build.run(V, folder)
		rec.built = K
		rec.nParts = 0
		for _ in rec.model:GetDescendants() do
			rec.nParts += 1
		end
		dbg(string.format("built %s [%s] %d parts, %d hidden, %d lights, %d prompts, %d blocked, %.0f ms", V.key, tostring(V.type), #K.parts, (function()
			local n = 0
			for _ in K.hidden do
				n += 1
			end
			return n
		end)(), #K.lights, #K.prompts, K.blocked, (os.clock() - t0) * 1000))
		for _, l in K.log do
			dbg("  " .. l)
		end
		local _ = mv
	end)
	rec.building = false
	busy = false
	if not ok then
		rec.failed = tostring(err)
		rec.failedAt = os.clock()
		dbg("skip", rec.model.Name, err)
		destroy(rec)
		return
	end
	table.insert(active, rec)
end

local function focus(): Vector3?
	local fp = script:GetAttribute("FocusPoint")
	if typeof(fp) == "Vector3" then
		return fp :: Vector3
	end
	local ch = player.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp.Position
	end
	local cam = Workspace.CurrentCamera
	return cam and cam.CFrame.Position
end

local lastAnnex = 0
local lastHome = 0
local function step()
	if script:GetAttribute("Enabled") == false then
		for _, a in table.clone(active) do
			destroy(a)
		end
		return
	end
	local pos = focus()
	if not pos then
		return
	end
	if pos.Y > 2500 and os.clock() - lastAnnex > 2 then
		lastAnnex = os.clock()
		annexScan(pos)
	end
	if pos.Y > 900 and os.clock() - lastHome > 3 then
		lastHome = os.clock()
		pcall(homeScan)
	end
	local maxV = limits()
	-- 지우기: 멀어졌거나 모델이 사라졌거나 (스트리밍으로) 크게 바뀐 매장
	for _, a in table.clone(active) do
		if not a.model.Parent or distTo(a, pos) > CFG.dropR then
			destroy(a)
		else
			local K = a.built
			if K then
				Scan.reapply(K.hidden)
			end
		end
	end
	if busy then
		return
	end
	-- 가장 가까운 후보 찾기
	local best, bd = nil, CFG.buildR
	local now = os.clock()
	for _, rec in recs do
		if not rec.model.Parent then
			continue
		end
		if rec.built or rec.building then
			continue
		end
		if rec.failed and now - rec.failedAt < CFG.retry then
			continue
		end
		local d = distTo(rec, pos)
		if d < bd then
			best, bd = rec, d
		end
	end
	if not best then
		return
	end
	if #active >= maxV then
		-- 더 가까운 매장이면 가장 먼 것을 내림
		local far, fd = nil, -1
		for _, a in active do
			local d = distTo(a, pos)
			if d > fd then
				far, fd = a, d
			end
		end
		if far and fd > bd + 4 then
			destroy(far)
		else
			return
		end
	end
	task.spawn(build, best)
end

-- 애니메이션 (10 Hz, 활성 매장만)
local animT = 0
RunService.Heartbeat:Connect(function(dt)
	animT += dt
	if animT < 0.1 then
		return
	end
	local t = os.clock()
	for _, a in active do
		local K = a.built
		if K and K.anims then
			for _, f in K.anims do
				local ok, err = pcall(f, t, animT)
				if not ok then
					dbg("anim", err)
				end
			end
		end
	end
	animT = 0
end)

-- 시설 애드온 (같은 폴더의 ModuleScript, 있으면): 매장 실내와 따로 도는 큰 시설 기능 (병원 문 · 엘리베이터 · 화장실 ...)
--   모듈은 start(ctx) 를 내보냄. ctx = { root, focus, limits, dbg, script, Scan }
local ADDONS = { "HospitalPlus", "Reskin" }
for _, nm in ADDONS do
	local m = script:FindFirstChild(nm)
	if m and m:IsA("ModuleScript") then
		task.spawn(function()
			local ok, err = pcall(function()
				local A = require(m) :: any
				if type(A) == "table" and type(A.start) == "function" then
					A.start({ root = root, focus = focus, limits = limits, dbg = dbg, script = script, Scan = Scan })
				end
			end)
			if not ok then
				warn("[GwangalliBuildingInterior] " .. nm .. ": " .. tostring(err))
			end
		end)
	end
end

task.spawn(function()
	while true do
		local ok, err = pcall(step)
		if not ok then
			warn("[GwangalliBuildingInterior] " .. tostring(err))
		end
		task.wait(CFG.tick)
	end
end)
