--!strict
-- GwangalliBuildingInterior/Scan: 맵 매장(Model)을 읽어 실내 치수 V 를 만듭니다 (읽기만, 맵 파트는 절대 안 바꿈).
--
-- V (매장 프레임 = 바닥 윗면 가운데, -Z = 뒷벽, +Z = 입구/유리, +X = 뒷벽을 볼 때 오른쪽):
--   V.model, V.name, V.key ("<이름>@<x>,<z>" = ShopLife 키), V.kind ("street" | "gwshop" | "annex" | "venue")
--   V.type / V.menu (StreetShops 유형: cafe, pub, soup ...), V.cf (CFrame), V.W, V.D, V.H (안쪽 폭 · 깊이 · 천장 높이)
--   V.x0 < 0 < V.x1 (옆벽 안쪽 면), V.z0 (뒷벽 안쪽 면, 음수), V.z1 (앞 유리 안쪽 면, 양수), V.ceil (= V.H)
--   V.door = { x, w, z } 입구 (없으면 nil), V.doors = 모든 출입문
--   V.parts = { { part, name, min, max, c (중심), size, lcf } } 모든 BasePart 의 로컬 AABB
--   V.byName[name] = { rec ... }, V.has(name) -> 개수
--   V.solid = 바닥 가구 상자들 (새 바닥 소품이 피할 것), V.hang = 천장에 달린 것들, V.wallItems = 벽에 붙은 것들
--   V.chairs / V.stools / V.tables / V.counters / V.shelves  (리스킨용 묶음, Scan.families)
--   V.keep = { { min, max, kind } } 비워 둘 공간 (자동문 앞 · 직원 자리 · 테이블 위 · 좌석 위 · 통로 · 유리창 앞 ·
--            쓰레기통/정수기 예정 자리 · 게임 포인트 · NPC 주변)
--   V:wall(name, u, y, off) -> dcf    벽 표시면 프레임 (name = "back" | "left" | "right" | "front"; u = 벽 가운데 기준
--                                   보는 사람 오른쪽 +, y = 바닥 기준 높이, off = 벽에서 띄우는 거리)
--   V.walls[name] = { len, a, b (u 범위), n (안쪽 법선), depth }
--   V:spans(name, y0, y1, depth?) -> { {a, b} } 벽면에서 기존 물건 · 문 · keep 에 안 걸리는 빈 구간 (u 좌표)
--   V:toLocal(worldCF) / V:toWorld(lcf), V:lpos(part) -> 로컬 중심

local CollectionService = game:GetService("CollectionService")

local Scan = {}

local PI = math.pi

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function laabb(lcf: CFrame, size: Vector3): (Vector3, Vector3)
	local h = size / 2
	local ex = math.abs(lcf.XVector.X) * h.X + math.abs(lcf.YVector.X) * h.Y + math.abs(lcf.ZVector.X) * h.Z
	local ey = math.abs(lcf.XVector.Y) * h.X + math.abs(lcf.YVector.Y) * h.Y + math.abs(lcf.ZVector.Y) * h.Z
	local ez = math.abs(lcf.XVector.Z) * h.X + math.abs(lcf.YVector.Z) * h.Y + math.abs(lcf.ZVector.Z) * h.Z
	local p = lcf.Position
	return Vector3.new(p.X - ex, p.Y - ey, p.Z - ez), Vector3.new(p.X + ex, p.Y + ey, p.Z + ez)
end
Scan.laabb = laabb

-- 이름 분류 ----------------------------------------------------------------------------------------
local SHELL = {
	ShopFloor = true, ShopBackWall = true, ShopPartition = true, ShopWall = true, ShopCeiling = true, ShopWindow = true,
	Sill = true, Transom = true, Fascia = true, Column = true, Mullion = true, DoorHead = true, Awning = true, AwningValance = true,
	AFrameBack = true, DoorPlanter = true, DoorShrub = true, Skirting = true, Wainscot = true, GoldRail = true, Baseboard = true,
	LightHost = true, ShopLight = true, ShopBounds = true, Threshold = true, ShutterBox = true, DoorMullion = true, ShopGlass = true,
	Partition = true, Ceiling = true, Floor = true, Wall = true, BackWall = true, SideWall = true, FrontWall = true,
}
Scan.SHELL = SHELL
-- 문 (자동문 · 출입문)
local DOORS = { Door = true, GlassDoor = true, ShopDoor = true, LobbyDoor = true, EntranceDoor = true, FrontDoor = true, Handle = true }
-- 계산대 앵커 (ShopStaff 가 직원을 세우는 순서)
local CASHIER = { "PosBase", "CashierPanel", "OrderKiosk", "FrontDesk", "BackBar", "POS", "BarCounter", "Counter" }
local SEATS = { ChairSeat = true, StoolSeat = true, Stool = true, Cushion = true, SeatCushion = true, StoolTop = true, BarStool = true, SofaSeat = true, WashSeat = true, SalonChair = true }
local TABLES = { TableTop = true, LowTableTop = true, LowTable = true, CommunalTable = true, Table = true, BarTop = true, WindowBar = true, Ledge = true, PlasticTable = true, Top = true, GrillTable = true }
Scan.SEATS, Scan.TABLES, Scan.CASHIER = SEATS, TABLES, CASHIER
-- 게임 포인트 · NPC (주변 2.5 스터드 비움)
local POINT_PREFIX = { "Point_", "StylistSpot", "Spot_", "Station_", "Destination_", "UsePoint", "ServePos", "AislePos", "RamenCF" }

local function isPoint(name: string): boolean
	for _, p in POINT_PREFIX do
		if string.sub(name, 1, #p) == p then
			return true
		end
	end
	return false
end

-- 유형 분류 (StreetShops 공유 모듈이 있으면 그걸 씀) --------------------------------------------------
local SS: any = nil
local function shared(): any
	if SS ~= nil then
		return SS
	end
	SS = false
	local rs = game:GetService("ReplicatedStorage")
	local f = rs:FindFirstChild("GwangalliBuildingsShared")
	local m = f and f:FindFirstChild("StreetShops")
	if m and m:IsA("ModuleScript") then
		local ok, mod = pcall(require, m)
		if ok and type(mod) == "table" and type(mod.classify) == "function" then
			SS = mod
		end
	end
	return SS
end
Scan.shared = shared

-- 공유 모듈이 없을 때의 최소 규칙 (StreetShops.RULES 요약)
local FALLBACK = {
	{ "해장국", "soup" }, { "국밥", "soup" }, { "복국", "soup" }, { "밀면", "noodle" }, { "칼국수", "noodle" }, { "라멘", "noodle" },
	{ "돈카츠", "katsu" }, { "조개구이", "grill" }, { "곱창", "grill" }, { "갈비", "grill" }, { "고기", "grill" }, { "조개찜", "seafood" },
	{ "대게", "seafood" }, { "오징어", "seafood" }, { "횟집", "rawfish" }, { "수산", "rawfish" }, { "초장집", "rawfish" }, { "스시", "rawfish" },
	{ "포장마차", "pocha" }, { "포차", "pocha" }, { "새벽집", "pocha" }, { "탭하우스", "pub" }, { "PUB", "pub" }, { "BEER", "pub" },
	{ "비어", "pub" }, { "WILD WAVE", "pub" }, { "HAPPY MONK", "pub" }, { "FUZZY NAVEL", "pub" }, { "THURSDAY PARTY", "pub" },
	{ "MAD DOGS", "pub" }, { "WORKING HOLIDAY", "pub" }, { "SUNSET", "pub" }, { "치킨", "chicken" }, { "통닭", "chicken" },
	{ "떡볶이", "snack" }, { "분식", "snack" }, { "어묵", "snack" }, { "오뎅", "snack" }, { "SUBWAY", "burger" }, { "버거", "burger" },
	{ "타코", "burger" }, { "BINGBING", "dessert" }, { "탕후루", "dessert" }, { "츄러스", "dessert" }, { "와플", "dessert" },
	{ "젤라또", "dessert" }, { "GELATO", "dessert" }, { "호떡", "dessert" }, { "베이커리", "bakery" }, { "BAKERY", "bakery" },
	{ "로스터리", "cafe" }, { "COFFEE", "cafe" }, { "커피", "cafe" }, { "CAFE", "cafe" }, { "카페", "cafe" }, { "라운지", "cafe" },
	{ "STARBUCKS", "cafe" }, { "PASCUCCI", "cafe" }, { "TWOSOME", "cafe" }, { "GS25", "cvs" }, { "7-ELEVEn", "cvs" },
	{ "emart24", "cvs" }, { "슈퍼", "cvs" }, { "편의점", "cvs" }, { "OLIVE YOUNG", "retail" }, { "기념품", "retail" },
	{ "I AM BUSAN", "retail" }, { "비치용품", "retail" }, { "튜브", "retail" }, { "돗자리", "retail" }, { "약국", "pharmacy" },
	{ "세탁", "laundry" }, { "공인중개사", "realty" }, { "부동산", "realty" }, { "HOTEL", "lobby" }, { "호텔", "lobby" },
	{ "MOTEL", "lobby" }, { "OCEAN STAY", "lobby" }, { "맨션", "residence" }, { "RESIDENCE", "residence" }, { "TOWER", "residence" },
	{ "A-PARK", "residence" }, { "JIWELL", "residence" }, { "CITY NINE", "residence" }, { "TERRASTAR", "residence" },
	{ "BEACH STUDIO", "residence" }, { "인형뽑기", "play" }, { "PHOTO", "play" }, { "미용", "salon" }, { "HAIR", "salon" },
}
local CONTENT = {
	{ "TapPost", "pub" }, { "TankWater", "rawfish" }, { "GrillTable", "grill" }, { "CharcoalPot", "grill" }, { "EspressoBody", "cafe" },
	{ "Gondola", "cvs" }, { "IceCreamChest", "cvs" }, { "PastryCase", "bakery" }, { "BreadShelf", "bakery" }, { "GelatoTub", "dessert" },
	{ "WaffleIron", "dessert" }, { "OrderKiosk", "burger" }, { "Tester", "retail" }, { "WallRack", "retail" }, { "FrontDesk", "lobby" },
	{ "Mailboxes", "residence" }, { "WorkDesk", "realty" }, { "KitchenPass", "soup" }, { "Noren", "noodle" }, { "ClawBase", "play" },
}
local GWSHOP = { gukbap = "soup", chicken = "chicken", snack = "snack", pharmacy = "pharmacy", surf = "surf", clothing = "clothing", salon = "salon" }

function Scan.classify(model: Instance, names: { string }, counts: { [string]: number }): (string?, string?)
	local forced = model:GetAttribute("ShopLifeType")
	if type(forced) == "string" and forced ~= "" then
		return forced, model:GetAttribute("ShopLifeMenu") :: any
	end
	local sid = model:GetAttribute("ShopId")
	if type(sid) == "string" and GWSHOP[sid] then
		return GWSHOP[sid], sid
	end
	local ss = shared()
	if ss then
		local t, m = ss.classify(names)
		if not t then
			t, m = ss.classifyContents(counts)
		end
		if t then
			return t, m
		end
	end
	for _, r in FALLBACK do
		for _, n in names do
			if string.find(n, r[1], 1, true) then
				return r[2], nil
			end
		end
	end
	for _, r in CONTENT do
		for k, c in counts do
			if c > 0 and string.sub(k, 1, #r[1]) == r[1] then
				return r[2], nil
			end
		end
	end
	return nil, nil
end

-- 벽 프레임 ----------------------------------------------------------------------------------------
-- dcf: +X = 보는 사람 오른쪽, +Y = 위, +Z = 보는 사람 쪽 (벽 안쪽 법선)
local WALL_AXES = {
	back = { u = Vector3.new(1, 0, 0), n = Vector3.new(0, 0, 1) },
	left = { u = Vector3.new(0, 0, -1), n = Vector3.new(1, 0, 0) },
	right = { u = Vector3.new(0, 0, 1), n = Vector3.new(-1, 0, 0) },
	front = { u = Vector3.new(-1, 0, 0), n = Vector3.new(0, 0, -1) },
}
Scan.WALL_AXES = WALL_AXES

local Vm = {}
Vm.__index = Vm

function Vm:wallOrigin(name: string): Vector3
	local cx, cz = (self.x0 + self.x1) / 2, (self.z0 + self.z1) / 2
	if name == "back" then
		return Vector3.new(cx, 0, self.z0)
	elseif name == "front" then
		return Vector3.new(cx, 0, self.z1)
	elseif name == "left" then
		return Vector3.new(self.x0, 0, cz)
	else
		return Vector3.new(self.x1, 0, cz)
	end
end

function Vm:wall(name: string, u: number, y: number, off: number?): CFrame
	local ax = WALL_AXES[name]
	local o = self:wallOrigin(name) + ax.u * u + Vector3.new(0, y, 0) + ax.n * (off or 0)
	return CFrame.fromMatrix(o, ax.u, Vector3.yAxis, ax.n)
end

-- 로컬 점 p 의 벽 좌표 (u, 벽까지 거리)
function Vm:wallCoord(name: string, p: Vector3): (number, number)
	local ax = WALL_AXES[name]
	local o = self:wallOrigin(name)
	local d = p - o
	return d:Dot(ax.u), d:Dot(ax.n)
end

function Vm:toLocal(cf: CFrame): CFrame
	return self.cf:ToObjectSpace(cf)
end
function Vm:toWorld(lcf: CFrame): CFrame
	return self.cf * lcf
end
function Vm:lpos(p: BasePart): Vector3
	return self.cf:PointToObjectSpace(p.Position)
end
function Vm:has(name: string): number
	local l = self.byName[name]
	return if l then #l else 0
end
function Vm:first(name: string): any?
	local l = self.byName[name]
	return l and l[1]
end

-- 벽면 빈 구간: 높이 y0..y1 에서 벽으로부터 depth 안에 있는 기존 물건 · 문 · 창 · keep 을 뺀 u 구간들
function Vm:spans(name: string, y0: number, y1: number, depth: number?): { { number } }
	local w = self.walls[name]
	if not w then
		return {}
	end
	local dep = depth or 1.6
	local cuts: { { number } } = {}
	local function cutBox(mn: Vector3, mx: Vector3, pad: number)
		if mx.Y < y0 or mn.Y > y1 then
			return
		end
		-- 상자의 8 꼭짓점을 벽 좌표로
		local umin, umax, dmin = math.huge, -math.huge, math.huge
		for _, x in { mn.X, mx.X } do
			for _, z in { mn.Z, mx.Z } do
				local u, d = self:wallCoord(name, Vector3.new(x, 0, z))
				umin = math.min(umin, u)
				umax = math.max(umax, u)
				dmin = math.min(dmin, d)
			end
		end
		if dmin > dep then
			return
		end
		table.insert(cuts, { umin - pad, umax + pad })
	end
	for _, r in self.parts do
		if not r.shell or r.door then
			cutBox(r.min, r.max, 0.25)
		elseif string.sub(r.name, 1, 5) == "Sign_" and r.size.Y < 6 then
			cutBox(r.min, r.max, 0.2) -- 맵 메뉴판 · 간판 위에 벽 소품이 덮이지 않게
		end
	end
	for _, k in self.keep do
		if k.kind ~= "table" and k.kind ~= "seat" then
			cutBox(k.min, k.max, 0)
		end
	end
	table.sort(cuts, function(a, b)
		return a[1] < b[1]
	end)
	local out = {}
	local cur = w.a + 0.3
	for _, c in cuts do
		if c[1] > cur then
			table.insert(out, { cur, math.min(c[1], w.b - 0.3) })
		end
		cur = math.max(cur, c[2])
	end
	if cur < w.b - 0.3 then
		table.insert(out, { cur, w.b - 0.3 })
	end
	local res = {}
	for _, s in out do
		if s[2] - s[1] > 0.6 then
			table.insert(res, s)
		end
	end
	return res
end

-- keep 공간 추가 (로컬 AABB)
function Vm:addKeep(mn: Vector3, mx: Vector3, kind: string)
	table.insert(self.keep, { min = mn, max = mx, kind = kind })
end

-- 원기둥 근사 (점 주변 반지름 r, 높이 h)
function Vm:keepAround(p: Vector3, r: number, h: number, kind: string)
	self:addKeep(Vector3.new(p.X - r, 0.1, p.Z - r), Vector3.new(p.X + r, h, p.Z + r), kind)
end

-- 찾기 ----------------------------------------------------------------------------------------------
local function findFloor(model: Instance): (BasePart?, BasePart?)
	local floor = model:FindFirstChild("ShopFloor")
	if not (floor and floor:IsA("BasePart")) then
		local f2 = model:FindFirstChild("ShopFloor", true)
		floor = if f2 and f2:IsA("BasePart") then f2 else nil
	end
	local b = model:FindFirstChild("ShopBounds", true)
	local bounds = if b and b:IsA("BasePart") then b else nil
	return floor :: BasePart?, bounds
end
Scan.findFloor = findFloor

local function isDoorModel(m: Instance): boolean
	return m:IsA("Model") and (m.Name == "AutoDoor" or string.sub(m.Name, 1, 9) == "AutoDoor_" or CollectionService:HasTag(m, "AutoDoor"))
end

-- fit 공통 뒷부분: 역할 분류 · NPC · 출입문 · 묶음 · 비울 공간 · 벽 정보
local function finishFit(V: any, model: Instance, frame: CFrame, doorsM: { Model }): (any?, string?)
	-- 역할: 가구 · 천장 · 벽 부착 · 문 · 포인트
	local inside = function(r): boolean
		return r.c.X > V.x0 - 0.3 and r.c.X < V.x1 + 0.3 and r.c.Z > V.z0 - 0.3 and r.c.Z < V.z1 + 0.3
	end
	for _, r in V.parts do
		local p: BasePart = r.part
		local anc = p.Parent
		local isDoorLeaf = DOORS[r.name] or (anc ~= nil and isDoorModel(anc))
		r.door = isDoorLeaf
		if isPoint(r.name) or CollectionService:HasTag(p, "GwShopPoint") or CollectionService:HasTag(p, "GwShopSpot") or CollectionService:HasTag(p, "GwJobStation") then
			r.point = true
			table.insert(V.points, r)
		elseif r.shell or isDoorLeaf then
			-- 쉘
		elseif inside(r) and p.Transparency < 0.99 then
			local nearWall = math.min(r.min.X - V.x0, V.x1 - r.max.X, r.min.Z - V.z0) < 1.4
			if r.min.Y > V.H - 3.2 and r.min.Y > 4.5 then
				table.insert(V.hang, r)
			elseif r.min.Y > 2.2 and nearWall and r.size.Y < 6 then
				table.insert(V.wallItems, r)
			elseif r.size.X * r.size.Z > 0.02 or r.size.Y > 0.5 then
				table.insert(V.solid, r)
			end
		end
	end
	-- NPC 모형 (Humanoid · 이름)
	for _, d in (V.npcScope or model):GetDescendants() do
		if d:IsA("Model") and (d:FindFirstChildOfClass("Humanoid") or CollectionService:HasTag(d, "GwShopClerk") or d.Name == "VenueStaff" or d.Name == "Staff") then
			local cf, s = d:GetBoundingBox()
			local lc = frame:ToObjectSpace(cf)
			local mn, mx = laabb(lc, s)
			if not V.roomBox or (lc.X > V.x0 - 2 and lc.X < V.x1 + 2 and lc.Z > V.z0 - 2 and lc.Z < V.z1 + 2 and lc.Y > -2 and lc.Y < V.H + 2) then
				table.insert(V.npcs, { model = d, min = mn, max = mx })
			end
		end
	end

	-- 출입문
	for _, dm in doorsM do
		local cf, s = dm:GetBoundingBox()
		local mn, mx = laabb(frame:ToObjectSpace(cf), s)
		table.insert(V.doors, { model = dm, x = (mn.X + mx.X) / 2, z = (mn.Z + mx.Z) / 2, w = math.max(mx.X - mn.X, mx.Z - mn.Z), min = mn, max = mx, auto = true })
	end
	if #V.doors == 0 then
		for _, r in V.parts do
			if (r.name == "Door" or r.name == "GlassDoor" or r.name == "ShopDoor" or r.name == "LobbyDoor" or r.name == "EntranceDoor") and r.size.Y > 5 then
				table.insert(V.doors, { x = r.c.X, z = r.c.Z, w = math.max(r.size.X, r.size.Z), min = r.min, max = r.max })
			end
		end
	end
	local best = nil
	for _, d in V.doors do
		if d.z > 0 and (not best or d.z > best.z) then
			best = d
		end
	end
	V.door = best or V.doors[1]
	if not V.door and V.doorSpec then
		local d = V.doorSpec
		V.door = { x = d.x, z = d.z, w = d.w or 5, min = Vector3.new(d.x - (d.w or 5) / 2, 0, d.z - 0.2), max = Vector3.new(d.x + (d.w or 5) / 2, 8, d.z + 0.2), guessed = true }
		table.insert(V.doors, V.door)
	end
	if not V.door and not V.noDoorGuess then
		-- 자동문이 없는 매장 (GwShop · 셔터 · 개방형 포차): 앞면 가운데를 입구로 보고 비워 둠
		local w = math.clamp(V.W * 0.35, 4.8, 9)
		V.door = { x = (V.x0 + V.x1) / 2, z = V.z1, w = w, min = Vector3.new(-w / 2, 0, V.z1 - 0.2), max = Vector3.new(w / 2, 8, V.z1 + 0.2), guessed = true }
		table.insert(V.doors, V.door)
	end

	Scan.families(V)
	Scan.keepouts(V)
	-- 벽 정보
	V.walls = {
		back = { len = V.W, a = V.x0 - (V.x0 + V.x1) / 2, b = V.x1 - (V.x0 + V.x1) / 2, n = WALL_AXES.back.n },
		front = { len = V.W, a = -(V.x1 - (V.x0 + V.x1) / 2), b = -(V.x0 - (V.x0 + V.x1) / 2), n = WALL_AXES.front.n },
		left = { len = V.D, a = -(V.z1 - (V.z0 + V.z1) / 2), b = -(V.z0 - (V.z0 + V.z1) / 2), n = WALL_AXES.left.n },
		right = { len = V.D, a = V.z0 - (V.z0 + V.z1) / 2, b = V.z1 - (V.z0 + V.z1) / 2, n = WALL_AXES.right.n },
	}
	return V, nil
end

-- 한 매장 맞추기 -------------------------------------------------------------------------------------
function Scan.fit(model: Model, opts: any?): (any?, string?)
	local o: any = opts or {}
	local floor, bounds = findFloor(model)
	if not floor and not bounds then
		return nil, "no ShopFloor/ShopBounds"
	end
	local src = (floor or bounds) :: BasePart
	-- 바닥 높이: 바닥 윗면 (없으면 bounds 아랫면)
	local floorY: number
	if floor then
		local _, mx = laabb(floor.CFrame, floor.Size)
		floorY = mx.Y
	else
		local mn = laabb((bounds :: BasePart).CFrame, (bounds :: BasePart).Size)
		floorY = mn.Y
	end
	local fwd = flat(src.CFrame.LookVector)
	if fwd.Magnitude < 0.1 then
		fwd = Vector3.new(0, 0, -1)
	end
	local centerSrc = bounds or floor :: BasePart
	local center = Vector3.new(centerSrc.Position.X, floorY, centerSrc.Position.Z)
	local slFrame = CFrame.lookAt(center, center + fwd.Unit) -- ShopLife 의 hframe (키 · 쓰레기통 예측용)
	local sizeSrc = (bounds or floor) :: BasePart
	local sx, sz = sizeSrc.Size.X, sizeSrc.Size.Z

	-- 모든 파트 (로컬 AABB 는 방향이 정해진 뒤 다시 계산)
	local all: { BasePart } = {}
	local doorsM: { Model } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(all, d)
		elseif isDoorModel(d) then
			table.insert(doorsM, d :: Model)
		end
	end
	if isDoorModel(model) then
		return nil, "door model"
	end
	-- 방향: 입구(자동문 · 유리)가 +Z, 뒷벽이 -Z
	local frame = slFrame
	local back = model:FindFirstChild("ShopBackWall", true)
	local flip = false
	if back and back:IsA("BasePart") then
		flip = frame:PointToObjectSpace(back.Position).Z > 0
	elseif #doorsM > 0 then
		flip = frame:PointToObjectSpace(doorsM[1]:GetPivot().Position).Z < 0
	else
		local sum, n = 0, 0
		for _, p in all do
			if p.Name == "ShopWindow" or p.Name == "ShopGlass" or DOORS[p.Name] then
				sum += frame:PointToObjectSpace(p.Position).Z
				n += 1
			end
		end
		flip = n > 0 and sum < 0
	end
	if flip then
		frame = frame * CFrame.Angles(0, PI, 0)
	end

	local V: any = setmetatable({}, Vm)
	V.model = model
	V.name = (model:GetAttribute("DisplayName") :: any) or model.Name
	V.cf = frame
	V.slFrame = slFrame
	V.key = string.format("%s@%d,%d", model.Name, math.floor(slFrame.X + 0.5), math.floor(slFrame.Z + 0.5))
	V.kind = o.kind or (if CollectionService:HasTag(model, "GwShop") or model:GetAttribute("ShopId") then "gwshop" else "street")
	V.keep = {}
	V.parts = {}
	V.byName = {}
	V.solid = {}
	V.hang = {}
	V.wallItems = {}
	V.points = {}
	V.npcs = {}
	V.doors = {}
	local hx, hz = sx / 2, sz / 2
	V.x0, V.x1, V.z0, V.z1 = -hx, hx, -hz, hz
	V.H = 10

	local counts: { [string]: number } = {}
	local names = { model.Name }
	for _, p in all do
		local lcf = frame:ToObjectSpace(p.CFrame)
		local mn, mx = laabb(lcf, p.Size)
		local rec = { part = p, name = p.Name, min = mn, max = mx, c = (mn + mx) / 2, size = mx - mn, lcf = lcf }
		rec.shell = SHELL[p.Name] == true or string.sub(p.Name, 1, 5) == "Sign_" or string.sub(p.Name, 1, 6) == "Awning"
		table.insert(V.parts, rec)
		local l = V.byName[p.Name]
		if not l then
			l = {}
			V.byName[p.Name] = l
		end
		table.insert(l, rec)
		counts[p.Name] = (counts[p.Name] or 0) + 1
		if string.sub(p.Name, 1, 5) == "Sign_" then
			table.insert(names, string.sub(p.Name, 6))
		end
	end

	-- 안쪽 경계: 옆벽 · 뒷벽 · 앞 유리 · 천장
	local function inner(list: { any }?, axis: string, side: number, best: number): number
		if not list then
			return best
		end
		for _, r in list do
			if r.size.Y > 4 then
				local c = if axis == "X" then r.c.X else r.c.Z
				local lim = if axis == "X" then hx else hz
				if side * c > lim * 0.35 then
					local face = if axis == "X" then (if side > 0 then r.min.X else r.max.X) else (if side > 0 then r.min.Z else r.max.Z)
					if side > 0 then
						best = math.min(best, face)
					else
						best = math.max(best, face)
					end
				end
			end
		end
		return best
	end
	for _, nm in { "ShopPartition", "ShopWall", "Partition", "SideWall", "Wall" } do
		V.x0 = inner(V.byName[nm], "X", -1, V.x0)
		V.x1 = inner(V.byName[nm], "X", 1, V.x1)
	end
	if V.x0 < -hx - 0.5 then
		V.x0 = -hx
	end
	if V.x1 > hx + 0.5 then
		V.x1 = hx
	end
	V.z0 = inner(V.byName.ShopBackWall or V.byName.BackWall, "Z", -1, -hz)
	-- 앞: 유리 · 문틀 · 창틀 안쪽 면 (없으면 바닥 끝)
	local front = hz
	for _, nm in { "ShopWindow", "ShopGlass", "Sill", "Door", "GlassDoor", "ShopDoor", "Transom" } do
		local l = V.byName[nm]
		if l then
			for _, r in l do
				if r.c.Z > hz * 0.35 then
					front = math.min(front, r.min.Z)
				end
			end
		end
	end
	V.z1 = math.max(front, V.z0 + 4)
	local ceil = V.byName.ShopCeiling or V.byName.Ceiling
	if ceil then
		local low = math.huge
		for _, r in ceil do
			low = math.min(low, r.min.Y)
		end
		V.H = low
	elseif bounds then
		V.H = math.max(7, (bounds.Size.Y))
	end
	V.ceil = V.H
	V.W = V.x1 - V.x0
	V.D = V.z1 - V.z0
	V.type, V.menu = Scan.classify(model, names, counts)
	if o.type then
		V.type = o.type
	end
	V.counts = counts

	return finishFit(V, model, frame, doorsM)
end


-- 큰 시설의 방 하나 맞추기 (ShopFloor 가 없는 PC방 · 노래방 · 편의점 본점 · 볼링장 층 ...).
-- spec = { cf (방 바닥 윗면 가운데, -Z = 뒷벽 쪽, +Z = 입구 쪽), size = Vector3(W, H, D) 안쪽 크기,
--   type, name, key, room (방 이름), kind ("venue"), margin (상자 밖 포함 여유, 기본 0.6), door = { x, z, w } (로컬, 선택),
--   noDoorGuess (true = 입구를 추측하지 않음), parts = { BasePart }? (기본: model 자손 중 상자 안) }
function Scan.fitRoom(model: Instance, spec: any): (any?, string?)
	local frame: CFrame = spec.cf
	local W, H, D = spec.size.X, spec.size.Y, spec.size.Z
	local m = spec.margin or 0.6
	local V: any = setmetatable({}, Vm)
	V.model = model
	V.name = spec.name or (model:GetAttribute("DisplayName") :: any) or model.Name
	V.cf = frame
	V.slFrame = frame
	V.key = spec.key or string.format("%s#%s@%d,%d", model.Name, tostring(spec.room or "room"), math.floor(frame.X + 0.5), math.floor(frame.Z + 0.5))
	V.kind = spec.kind or "venue"
	V.room = spec.room
	V.tier = spec.tier
	V.roomBox = true
	V.noBin = true
	V.noDoorGuess = spec.noDoorGuess
	V.doorSpec = spec.door
	V.keep, V.parts, V.byName, V.solid, V.hang, V.wallItems, V.points, V.npcs, V.doors = {}, {}, {}, {}, {}, {}, {}, {}, {}
	V.x0, V.x1, V.z0, V.z1 = -W / 2, W / 2, -D / 2, D / 2
	V.H, V.ceil, V.W, V.D = H, H, W, D
	V.type, V.menu = spec.type, spec.menu
	local counts: { [string]: number } = {}
	local doorsM: { Model } = {}
	local list = spec.parts
	if not list then
		list = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(list, d)
			elseif isDoorModel(d) then
				local p = frame:PointToObjectSpace(d:GetPivot().Position)
				if p.X > V.x0 - 2 and p.X < V.x1 + 2 and p.Z > V.z0 - 2 and p.Z < V.z1 + 2 then
					table.insert(doorsM, d :: Model)
				end
			end
		end
	end
	for _, p in list do
		local lcf = frame:ToObjectSpace(p.CFrame)
		local c = lcf.Position
		if c.X > V.x0 - m and c.X < V.x1 + m and c.Z > V.z0 - m and c.Z < V.z1 + m and c.Y > -1.5 and c.Y < H + 1.5 then
			local mn, mx = laabb(lcf, p.Size)
			local rec = { part = p, name = p.Name, min = mn, max = mx, c = (mn + mx) / 2, size = mx - mn, lcf = lcf }
			rec.shell = SHELL[p.Name] == true or string.sub(p.Name, 1, 5) == "Sign_" or string.sub(p.Name, 1, 6) == "Awning"
				or (mx.X - mn.X > W * 0.8 and mx.Y - mn.Y < 0.8) or (mx.Z - mn.Z > D * 0.8 and mx.Y - mn.Y < 0.8)
				or (mx.Y - mn.Y > H * 0.7 and (mx.X - mn.X > W * 0.6 or mx.Z - mn.Z > D * 0.6))
			table.insert(V.parts, rec)
			local l = V.byName[p.Name]
			if not l then
				l = {}
				V.byName[p.Name] = l
			end
			table.insert(l, rec)
			counts[p.Name] = (counts[p.Name] or 0) + 1
		end
	end
	V.counts = counts
	V.npcScope = spec.npcScope or model
	return finishFit(V, model, frame, doorsM)
end

-- 리스킨용 묶음 -------------------------------------------------------------------------------------
-- V.chairs = { { seat, back?, parts = {rec}, top (좌판 윗면 y), c (좌판 중심), face (앉은 사람이 보는 방향 단위벡터), kind } }
-- V.tables = { { top (rec), parts, y (윗면), min, max, kind } }
-- V.counters = { { body?, top?, parts, min, max, y (윗면) } }
local CHAIR_PARTS = { ChairBack = true, ChairLeg = true, ChairFoot = true, ChairBase = true, ChairPost = true, ChairBody = true, ChairArm = true, Backrest = true, Arm = true, Base = true, Plinth = true }
local STOOL_PARTS = { StoolPost = true, FootRing = true, StoolLeg = true, StoolBase = true }
local TABLE_PARTS = { TableLeg = true, TableFoot = true, TableBase = true, LowTableLeg = true, BarLeg = true, TableFrame = true }
local COUNTER_PARTS = { Counter = true, CounterTop = true, ToeKick = true, CounterBand = true, CounterFront = true }

function Scan.families(V: any)
	local claimed: { [any]: boolean } = {}
	local function near2(a: Vector3, b: Vector3): number
		local d = a - b
		return d.X * d.X + d.Z * d.Z
	end
	-- 테이블 먼저 (의자 방향을 정할 때 씀)
	V.tables = {}
	for _, r in V.parts do
		if TABLES[r.name] and not r.shell and r.size.X * r.size.Z >= 0.8 and r.max.Y > 1 and r.max.Y < 5.6 then
			local t = { top = r, parts = { r }, y = r.max.Y, min = r.min, max = r.max, kind = if r.name == "LowTableTop" or r.name == "LowTable" then "low" elseif r.name == "GrillTable" then "grill" elseif r.name == "BarTop" or r.name == "WindowBar" or r.name == "Ledge" then "bar" else "table" }
			claimed[r] = true
			table.insert(V.tables, t)
		end
	end
	for _, t in V.tables do
		for _, r in V.parts do
			if not claimed[r] and TABLE_PARTS[r.name] and r.c.X >= t.min.X - 0.3 and r.c.X <= t.max.X + 0.3 and r.c.Z >= t.min.Z - 0.3 and r.c.Z <= t.max.Z + 0.3 and r.max.Y <= t.y + 0.05 then
				table.insert(t.parts, r)
				claimed[r] = true
			end
		end
	end
	local function nearestTable(p: Vector3): any?
		local best, bd = nil, 9
		for _, t in V.tables do
			local cx = math.clamp(p.X, t.min.X, t.max.X)
			local cz = math.clamp(p.Z, t.min.Z, t.max.Z)
			local d = (Vector3.new(cx, 0, cz) - Vector3.new(p.X, 0, p.Z)).Magnitude
			if d < bd then
				best, bd = t, d
			end
		end
		return best
	end
	V.chairs, V.stools = {}, {}
	for _, r in V.parts do
		if (SEATS[r.name] or (r.part:IsA("Seat") and r.part.Transparency < 0.99)) and not claimed[r] and r.max.Y < 5 then
			claimed[r] = true
			local stool = r.name == "StoolSeat" or r.name == "Stool" or r.name == "StoolTop" or r.name == "BarStool"
			local ch = { seat = r, parts = { r }, top = r.max.Y, c = r.c, kind = if stool then "stool" else "chair" }
			for _, q in V.parts do
				if not claimed[q] and (CHAIR_PARTS[q.name] or STOOL_PARTS[q.name]) and near2(q.c, r.c) < 1.7 * 1.7 and q.max.Y < r.max.Y + 3.4 then
					table.insert(ch.parts, q)
					claimed[q] = true
					if q.name == "ChairBack" or q.name == "Backrest" then
						ch.back = q
					end
				end
			end
			-- 바라보는 방향: 등받이 반대쪽, 없으면 가까운 테이블 쪽, 그것도 없으면 +Z
			local face: Vector3
			if ch.back then
				local d = flat(r.c - ch.back.c)
				face = if d.Magnitude > 0.05 then d.Unit else Vector3.new(0, 0, 1)
			else
				local t = nearestTable(r.c)
				if t then
					local tc = (t.min + t.max) / 2
					local d = flat(tc - r.c)
					face = if d.Magnitude > 0.05 then d.Unit else Vector3.new(0, 0, 1)
				else
					face = Vector3.new(0, 0, 1)
				end
			end
			-- 축에 맞춤 (맵 가구는 거의 0/90/180/270 도)
			if math.abs(face.X) > math.abs(face.Z) * 2.5 then
				face = Vector3.new(math.sign(face.X), 0, 0)
			elseif math.abs(face.Z) > math.abs(face.X) * 2.5 then
				face = Vector3.new(0, 0, math.sign(face.Z))
			end
			ch.face = face
			ch.table = nearestTable(r.c)
			table.insert(if stool then V.stools else V.chairs, ch)
		end
	end
	V.counters = {}
	for _, r in V.parts do
		if (r.name == "Counter" or r.name == "CounterTop") and not claimed[r] then
			local grp = nil
			for _, g in V.counters do
				if r.c.X >= g.min.X - 0.2 and r.c.X <= g.max.X + 0.2 and r.c.Z >= g.min.Z - 0.4 and r.c.Z <= g.max.Z + 0.4 then
					grp = g
					break
				end
			end
			if not grp then
				grp = { parts = {}, min = r.min, max = r.max }
				table.insert(V.counters, grp)
			end
			table.insert(grp.parts, r)
			grp.min = grp.min:Min(r.min)
			grp.max = grp.max:Max(r.max)
			if r.name == "CounterTop" then
				grp.top = r
			else
				grp.body = r
			end
			claimed[r] = true
		end
	end
	for _, g in V.counters do
		g.c = (g.min + g.max) / 2
	end
	for _, g in V.counters do
		for _, r in V.parts do
			if not claimed[r] and COUNTER_PARTS[r.name] and r.c.X >= g.min.X - 0.3 and r.c.X <= g.max.X + 0.3 and r.c.Z >= g.min.Z - 0.6 and r.c.Z <= g.max.Z + 0.6 then
				table.insert(g.parts, r)
				claimed[r] = true
			end
		end
		g.y = if g.top then g.top.max.Y else g.max.Y
	end
	V.claimed = claimed
end

-- 비워 둘 공간 ---------------------------------------------------------------------------------------
function Scan.keepouts(V: any)
	local H = math.max(V.H, 8)
	-- 1) 출입문: 슬라이드 공간 (문 폭 + 양쪽 2) + 안쪽 4x4 현관
	for _, d in V.doors do
		local w = d.w or 4.8
		if math.abs(d.z) > math.abs(d.x) * 0.5 or d.z > 0 then
			local zIn = if d.z > 0 then -1 else 1
			local z0 = math.min(d.z, d.z + zIn * 4.4)
			local z1 = math.max(d.z, d.z + zIn * 4.4)
			V:addKeep(Vector3.new(d.x - w / 2 - 2, 0.1, z0 - 0.6), Vector3.new(d.x + w / 2 + 2, H, z1 + 0.6), "door")
		else
			V:addKeep(Vector3.new(d.x - 4.4, 0.1, d.z - w / 2 - 2), Vector3.new(d.x + 4.4, H, d.z + w / 2 + 2), "door")
		end
	end
	-- 화장실 · 직원 문 앞 (문짝 앞 3.2)
	for _, nm in { "DoorLeaf", "DoorCasing" } do
		for _, r in V.byName[nm] or {} do
			local cx, cz = r.c.X, r.c.Z
			if math.abs(r.size.X) >= math.abs(r.size.Z) then
				local dir = if cz < (V.z0 + V.z1) / 2 then 1 else -1
				V:addKeep(Vector3.new(r.min.X - 0.4, 0.1, math.min(cz, cz + dir * 3.4)), Vector3.new(r.max.X + 0.4, r.max.Y + 0.3, math.max(cz, cz + dir * 3.4)), "restroom")
			else
				local dir = if cx < 0 then 1 else -1
				V:addKeep(Vector3.new(math.min(cx, cx + dir * 3.4), 0.1, r.min.Z - 0.4), Vector3.new(math.max(cx, cx + dir * 3.4), r.max.Y + 0.3, r.max.Z + 0.4), "restroom")
			end
		end
	end
	-- 2) 직원 자리: 계산대 앵커 뒤 (뒷벽 쪽) 폭 5, 깊이 4, 높이 6.5
	local anchors = {}
	for _, nm in Scan.CASHIER do
		for _, r in V.byName[nm] or {} do
			if not r.shell then
				table.insert(anchors, r)
			end
		end
		if #anchors > 0 and nm ~= "Counter" then
			break
		end
	end
	for _, a in anchors do
		local wide = a.size.X >= a.size.Z
		-- 앵커가 올려진 계산대(있으면)의 뒷면 기준
		local backEdge = a.min.Z
		local cnt = nil
		for _, g in V.counters do
			if a.c.X >= g.min.X - 0.5 and a.c.X <= g.max.X + 0.5 and a.c.Z >= g.min.Z - 0.8 and a.c.Z <= g.max.Z + 0.8 then
				cnt = g
				break
			end
		end
		if cnt then
			wide = (cnt.max.X - cnt.min.X) >= (cnt.max.Z - cnt.min.Z)
		end
		if wide then
			backEdge = if cnt then cnt.min.Z else a.min.Z
			V:addKeep(Vector3.new(a.c.X - 2.5, 0.1, math.max(V.z0, backEdge - 4)), Vector3.new(a.c.X + 2.5, 6.5, backEdge), "staff")
		else
			local side = if a.c.X < 0 then -1 else 1
			local edge = if cnt then (if side < 0 then cnt.min.X else cnt.max.X) else a.c.X
			V:addKeep(Vector3.new(math.min(edge, edge + side * 4), 0.1, a.c.Z - 2.5), Vector3.new(math.max(edge, edge + side * 4), 6.5, a.c.Z + 2.5), "staff")
		end
	end
	V.cashiers = anchors
	-- 3) 테이블 윗면 (R7) · 좌석 위 (앉은 아바타)
	for _, t in V.tables do
		V:addKeep(Vector3.new(t.min.X - 0.05, t.y - 0.02, t.min.Z - 0.05), Vector3.new(t.max.X + 0.05, t.y + 3.4, t.max.Z + 0.05), "table")
	end
	for _, list in { V.chairs, V.stools } do
		for _, ch in list do
			local s = ch.seat
			V:addKeep(Vector3.new(s.min.X - 0.25, ch.top - 0.02, s.min.Z - 0.25), Vector3.new(s.max.X + 0.25, ch.top + 4, s.max.Z + 0.25), "seat")
		end
	end
	-- 4) 통로: 주문/패스 지점 -> 각 테이블 (폭 2.5)
	local svc = nil
	for _, nm in { "KitchenPass", "PassLedge", "PassTray", "PosBase", "OrderKiosk", "CounterTop" } do
		local r = V:first(nm)
		if r then
			svc = r
			break
		end
	end
	if svc then
		local a = Vector3.new(svc.c.X, 0, svc.c.Z)
		for _, t in V.tables do
			local b = Vector3.new((t.min.X + t.max.X) / 2, 0, (t.min.Z + t.max.Z) / 2)
			local len = (b - a).Magnitude
			local n = math.max(1, math.floor(len / 1.5))
			for i = 1, n - 1 do
				local p = a:Lerp(b, i / n)
				V:addKeep(Vector3.new(p.X - 1.25, 0.1, p.Z - 1.25), Vector3.new(p.X + 1.25, 6, p.Z + 1.25), "aisle")
			end
		end
	end
	-- 5) 앞 유리 안쪽 띠: 낮게만 (시트지 · 포스터가 보이게)
	if V.kind ~= "home" then -- 집의 +Z 는 방문 쪽 (가게 앞 유리 아님)
		V:addKeep(Vector3.new(V.x0 - 1, 3.4, V.z1 - 1.8), Vector3.new(V.x1 + 1, H, V.z1 + 0.5), "window")
	end
	-- 6) ShopLife 쓰레기통 · 정수기 예정 자리 (Scan.freeSpot 과 같은 계산, ShopLife 프레임 +Z 쪽)
	if not V.noBin and not V:first("Bin") and not V:first("TrashBin") then
		for _, f in { 0.38, -0.38 } do
			local w = V.slFrame * CFrame.new(V.W * f, 0, V.D / 2 - 0.9)
			local l = V.cf:PointToObjectSpace(w.Position)
			V:addKeep(Vector3.new(l.X - 1.1, 0.1, l.Z - 1.1), Vector3.new(l.X + 1.1, 4.2, l.Z + 1.1), "bin")
		end
	end
	-- 7) 게임 포인트 · NPC
	for _, r in V.points do
		V:keepAround(r.c, 2.5, 6.5, "point")
	end
	for _, n in V.npcs do
		V:addKeep(n.min - Vector3.new(2, 0, 2), n.max + Vector3.new(2, 0.5, 2), "npc")
	end
	-- 8) 다른 시스템이 맡은 월드 공간 (Scan.addWorldKeep: 병원 화장실 · 엘리베이터 문 · 응급실 출입문 ...)
	for _, w in Scan.worldKeeps do
		local c = (w.min + w.max) / 2
		local mn, mx = laabb(V.cf:ToObjectSpace(CFrame.new(c)), w.max - w.min)
		if mx.X > V.x0 - 1 and mn.X < V.x1 + 1 and mx.Z > V.z0 - 1 and mn.Z < V.z1 + 1 and mx.Y > -1 and mn.Y < (V.H or 12) + 1 then
			V:addKeep(mn, mx, w.kind)
		end
	end
end

-- 월드 AABB 를 모든 매장 · 방 fit 의 비울 공간으로 등록 (다른 모듈이 실제 구조물을 세우는 곳)
Scan.worldKeeps = {} :: { { min: Vector3, max: Vector3, kind: string } }
function Scan.addWorldKeep(mn: Vector3, mx: Vector3, kind: string?)
	table.insert(Scan.worldKeeps, { min = mn:Min(mx), max = mx:Max(mn), kind = kind or "facility" })
end

-- 숨기기 (R3) -------------------------------------------------------------------------------------
-- DetailLOD 가 쓰는 속성과 다른 쪽으로 숨김: GwArrive=true 루트 안 -> LocalTransparencyModifier,
-- 그 밖(NearLOD/ZoneLOD) -> 로컬 Transparency = 1 + SurfaceGui · Decal · Texture 끄기
local function lodRoot(p: Instance, stop: Instance?): Instance?
	local best = nil
	local a = p.Parent
	while a and a ~= stop and a ~= workspace do
		if a:GetAttribute("GwArrive") ~= nil or a:GetAttribute("LOD") ~= nil or CollectionService:HasTag(a, "NearLOD") or CollectionService:HasTag(a, "ZoneLOD") then
			best = a
		end
		a = a.Parent
	end
	return best
end
Scan.lodRoot = lodRoot

-- hidden[part] = { t, ltm, mode, guis }
function Scan.hide(store: { [BasePart]: any }, p: BasePart)
	if store[p] then
		return
	end
	-- 숨기면 안 되는 파트: TV 화면 · 테마로 칠하는 집 벽/바닥 · 창밖 풍경
	if p.Name == "Screen" or p.Name == "TVScreen"
		or (p:GetAttribute("Room") ~= nil and p:GetAttribute("Surface") ~= nil)
		or p:FindFirstAncestor("Backdrop") or p:FindFirstAncestor("WindowView") then
		return
	end
	local root = lodRoot(p, nil)
	local arrive = root ~= nil and root:GetAttribute("GwArrive") == true
	local rec: any = { mode = if arrive then "ltm" else "t", t = p.Transparency, ltm = p.LocalTransparencyModifier, guis = {} }
	if arrive then
		p.LocalTransparencyModifier = 1
	else
		p.Transparency = 1
	end
	for _, c in p:GetChildren() do
		if c:IsA("SurfaceGui") then
			table.insert(rec.guis, { c, c.Enabled })
			c.Enabled = false
		elseif c:IsA("Decal") then
			table.insert(rec.guis, { c, c.Transparency })
			c.Transparency = 1
		end
	end
	store[p] = rec
end

-- 다시 숨김이 풀렸으면 다시 적용 (스트리밍 · DetailLOD)
function Scan.reapply(store: { [BasePart]: any })
	for p, rec in store do
		if p.Parent then
			if rec.mode == "ltm" then
				if p.LocalTransparencyModifier < 1 then
					p.LocalTransparencyModifier = 1
				end
			elseif p.Transparency < 1 then
				p.Transparency = 1
			end
		end
	end
end

function Scan.restore(store: { [BasePart]: any })
	for p, rec in store do
		if p.Parent then
			if rec.mode == "ltm" then
				p.LocalTransparencyModifier = 0
			else
				p.Transparency = rec.t
			end
			for _, g in rec.guis do
				local inst, v = g[1], g[2]
				if inst.Parent then
					if inst:IsA("SurfaceGui") then
						inst.Enabled = v
					else
						(inst :: Decal).Transparency = v
					end
				end
			end
		end
		store[p] = nil
	end
end

return Scan
