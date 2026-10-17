--!strict
-- GwangalliBuildingInterior/T_home: 생활 게임 집 (고시원 · 원룸 · 오피스텔 · 아파트 · 펜트하우스) 의 방 (Homes.luau, Scan.fitRoom).
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (집은 Common 마감을 쓰지 않음: 전부 이 파일이 실제 벽 · 천장을 읽어서 지음)
--   build(K, V, S) 방마다: 1) 실제 천장 높이 · 실제 벽면(쉘 벽 파트) · 바닥 소속(어느 방 바닥 위인가) 계산
--                         2) 모든 방 공통 마감: 걸레받이 · 몰딩 · 문선 · 경첩 · 도어스토퍼 · 스위치 · 콘센트 · 감지기 ·
--                            스프링클러 · 시스템 에어컨 · 창 핸들 · 방충망
--                         3) 가구 슬롯(FurnitureSlot) 기본 가구를 실제 가구로 덮어씌움 (ItemId 별, 같은 자리 · 같은 높이,
--                            슬롯이 바뀌면 그 슬롯만 다시 지음)
--                         4) 주방 · 욕실 · 현관은 HomeWet.build, 나머지 방(거실 · 방 · 침실 · 서재 · 드레스룸 · 복층 · 다이닝 ·
--                            베란다)은 이 파일이 생활감 있는 소품 · 붙박이 · 상호작용을 지음 (등급별: 고시원 → 펜트하우스)
--   방 프레임: 원점 = 그 방 바닥 윗면 가운데, +Z = 방 문 쪽 (Homes). 집 파트는 절대 안 바꿈 (숨김만, 테마 색 바뀌는 파트는 안 숨김).
--   keep 바로잡기 (C:fixKeeps, 이 방 빌드에서만): 다른 층 슬롯(복층 위 침대 · 아래층 주방)의 keep 은 빼고, 벽 너머 슬롯
--   자리는 벽면에서 자르고, 가게용 "window" 띠는 뺌 (문 · 슬롯 · 프롬프트 keep 은 그대로).
--   침대 슬롯이 바뀌면 (서버가 가구를 다시 지음) 슬롯 덮개 + 침대 러그 · 침대 밑 간접등도 새 침대에 맞춰 다시 지음.

local Look = require(script.Parent:WaitForChild("Look"))
local Props = require(script.Parent:WaitForChild("Props"))
local Interact = require(script.Parent:WaitForChild("Interact"))
local Scan = require(script.Parent:WaitForChild("Scan"))
local Homes = require(script.Parent:WaitForChild("Homes"))
-- 주방 · 욕실 · 현관 (다른 파일): 불러오다 실패해도 나머지 방은 지어지게
local okWet, wetMod = pcall(function()
	return require(script.Parent:WaitForChild("HomeWet"))
end)
local HomeWet: any = if okWet and type(wetMod) == "table" and type((wetMod :: any).rooms) == "table" then wetMod else { rooms = { kitchen = true, bath = true, entry = true }, build = function() end, broken = tostring(wetMod) }

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local CF, V3 = CFrame.new, Vector3.new
local ANG = CFrame.Angles
local PI = math.pi
local M = Enum.Material
local L = Look
local YA = Vector3.yAxis
local laabb = Scan.laabb

local T = {}
T.debug = true
T.dumpKeep = false -- DEBUG
T.types = { "home" }

-------------------------------------------------------------------------------------------------
-- 작은 도구
-------------------------------------------------------------------------------------------------
local function c3(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
local function lk(r: number, g: number, b: number, m: Enum.Material?, extra: any?): any
	return Look.of(r, g, b, m, extra)
end
local function tint(look: any, k: number): any
	-- k > 0: 어둡게, k < 0: 밝게
	local c: Color3 = look.c or c3(200, 200, 200)
	local t = if k >= 0 then c:Lerp(Color3.new(0, 0, 0), k) else c:Lerp(Color3.new(1, 1, 1), -k)
	return Look.with(look, { c = t })
end
local function withC(look: any, c: Color3): any
	return Look.with(look, { c = c })
end
local function hash(s: string): number
	local h = 7
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 1000003
	end
	return h
end
local function rnd(seed: number, i: number): number
	local s = math.sin(i * 12.9898 + seed * 78.233) * 43758.5453
	return s - math.floor(s)
end
local function inBox(p: Vector3, mn: Vector3, mx: Vector3, pad: number?): boolean
	local e = pad or 0
	return p.X >= mn.X - e and p.X <= mx.X + e and p.Y >= mn.Y - e and p.Y <= mx.Y + e and p.Z >= mn.Z - e and p.Z <= mx.Z + e
end
local function boxHit(amn: Vector3, amx: Vector3, bmn: Vector3, bmx: Vector3, eps: number?): boolean
	local e = eps or 0
	return amn.X < bmx.X - e and amx.X > bmn.X + e and amn.Y < bmx.Y - e and amx.Y > bmn.Y + e and amn.Z < bmx.Z - e and amx.Z > bmn.Z + e
end
-- dcf (+X 보는 사람 오른쪽, +Z 보는 사람 쪽) 를 표면 바깥 normal n 으로
local function faceCF(p: Vector3, n: Vector3): CFrame
	local t = (-n):Cross(YA)
	return CFrame.fromMatrix(p, t, YA, n)
end
-- 위에서 보는 수평 판 (글자를 위로): 바닥 · 상판 위 글자판용 dcf
local function upCF(p: Vector3, fwd: Vector3): CFrame
	-- +Y(판 위쪽 = 글자 위) = fwd, +Z = 위
	local x = fwd:Cross(YA)
	return CFrame.fromMatrix(p, -x, fwd, YA)
end
-- 부드럽게 바꾸기 (TweenService, 실패하면 바로 대입)
local function tween(p: Instance, t: number, props: any)
	local ok = pcall(function()
		TweenService:Create(p, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
	end)
	if not ok then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
end

local function isA(i: Instance, c: string): boolean
	return i:IsA(c)
end

-------------------------------------------------------------------------------------------------
-- 등급별 팔레트 (실제 한국 집 마감)
-------------------------------------------------------------------------------------------------
local PAL = {
	goshiwon = {
		base = lk(146, 108, 74), baseKind = "pvc", crown = lk(146, 108, 74), crownKind = "flat",
		plate = lk(244, 243, 238), rocker = lk(236, 235, 230), casing = nil, hinge = L.chrome,
		wood = lk(198, 168, 128, M.Wood), metal = L.chrome, fabric = lk(168, 184, 208, M.Fabric),
	},
	oneroom = {
		base = lk(246, 244, 240), baseKind = "pvc", crown = lk(246, 244, 240), crownKind = "step",
		plate = lk(248, 248, 245), rocker = lk(240, 240, 236), hinge = L.chrome,
		wood = lk(198, 168, 128, M.Wood), metal = L.chrome, fabric = lk(222, 210, 190, M.Fabric),
	},
	officetel = {
		base = lk(236, 236, 234), baseKind = "slim", crown = lk(60, 60, 64), crownKind = "gap",
		plate = lk(250, 250, 250), rocker = lk(244, 244, 242), hinge = L.brushed,
		wood = lk(176, 150, 118, M.Wood), metal = lk(54, 56, 60, M.Metal), fabric = lk(168, 162, 154, M.Fabric),
	},
	apartment = {
		base = lk(246, 244, 240), baseKind = "classic", crown = lk(246, 244, 240), crownKind = "step3",
		plate = lk(250, 250, 248), rocker = lk(244, 244, 240), hinge = L.brushed,
		wood = lk(198, 168, 128, M.Wood), metal = L.brushed, fabric = lk(214, 204, 188, M.Fabric),
	},
	penthouse = {
		base = lk(88, 76, 62, M.Metal), baseKind = "luxury", crown = lk(40, 38, 36), crownKind = "gap",
		plate = lk(52, 50, 48, M.Metal), rocker = lk(70, 66, 62, M.Metal), hinge = L.brass,
		wood = lk(110, 76, 52, M.Wood), metal = L.brass, fabric = lk(236, 230, 218, M.Fabric),
	},
}

-------------------------------------------------------------------------------------------------
-- 방 문맥 C: 바닥 소속 · 실제 천장 · 실제 벽면 · 빈 자리
-------------------------------------------------------------------------------------------------
local ROOM_OF = { FloorEntry = "entry", FloorBath = "bath" }
local function floorRoom(p: BasePart): string?
	local nm = p.Name
	local surface = p:GetAttribute("Surface")
	local isFloor = surface == "floor" or ROOM_OF[nm] ~= nil or string.sub(nm, 1, 5) == "Floor"
	if not isFloor then
		return nil
	end
	local r = p:GetAttribute("Room")
	return (if type(r) == "string" then r else nil) or ROOM_OF[nm] or "main"
end

local C = {}
C.__index = C

local function newCtx(K: any, V: any): any
	local self: any = setmetatable({}, C)
	self.K, self.V = K, V
	self.model = V.model
	self.tier = (V.tier or (V.model and V.model:GetAttribute("Tier")) or "oneroom") :: string
	if not PAL[self.tier] then
		self.tier = "oneroom"
	end
	self.pal = PAL[self.tier]
	self.room = V.room or "main"
	self.seed = hash(tostring(V.key or "home"))
	self.lux = ({ goshiwon = 1, oneroom = 2, officetel = 3, apartment = 4, penthouse = 5 })[self.tier] or 2
	self.used = {} -- 벽 · 바닥 · 천장에 이미 쓴 자리 (로컬 AABB)
	self.lightsMine = 0
	self.promptsMine = 0
	self.slotHidden = {} -- [slot] = { parts }
	self.extraInteract = {} -- 방 전용 상호작용 (interactions 끝에서 부름)
	self.shell = self.model and self.model:FindFirstChild("Shell")
	self.hostParts = {}
	self.interacts = {}
	-- 바닥 (Homes.rooms 와 같은 규칙)
	self.floors = {}
	self.walls = {}
	self.slabs = {}
	local cf: CFrame = V.cf
	if self.shell then
		for _, d in self.shell:GetDescendants() do
			if d:IsA("BasePart") then
				local mn, mx = laabb(cf:ToObjectSpace(d.CFrame), d.Size)
				local fr = floorRoom(d)
				local nm = d.Name
				if fr then
					table.insert(self.floors, { room = fr, mn = mn, mx = mx, part = d })
				elseif string.find(nm, "Ceiling") or string.find(nm, "Slab") then
					table.insert(self.slabs, { mn = mn, mx = mx, part = d })
				elseif string.sub(nm, 1, 9) ~= "Threshold" and nm ~= "StepNosing" then
					local sx, sz = mx.X - mn.X, mx.Z - mn.Z
					if mx.Y - mn.Y >= 0.35 and math.min(sx, sz) <= 1.7 and math.max(sx, sz) >= 0.12 then
						table.insert(self.walls, { mn = mn, mx = mx, part = d, name = nm })
					end
				end
			end
		end
	end
	-- 집 상호작용 파트 (서버 프롬프트) · 슬롯
	self.slots = {}
	if self.model then
		for _, d in self.model:GetDescendants() do
			if d:IsA("BasePart") and (CollectionService:HasTag(d, "HomeInteract") or string.sub(d.Name, 1, 9) == "Interact_" or d.Name == "ExitDoor") then
				table.insert(self.interacts, { part = d, p = cf:PointToObjectSpace(d.Position), kind = d:GetAttribute("Kind") })
			elseif d:IsA("Model") and (CollectionService:HasTag(d, "FurnitureSlot") or string.sub(d.Name, 1, 5) == "Slot_") then
				table.insert(self.slots, d)
			end
		end
	end
	-- 실제 천장 (복층 아래 주방 · 1층 방이 집 전체 천장 높이로 잡히는 것 바로잡기)
	self.Hbox = V.H
	local fc = self:floorCenter()
	local h = self:ceilAt(fc.X, fc.Z)
	if h < V.H - 0.4 and h > 5 then
		V.H = h
		V.ceil = h
	end
	self.H = V.H
	-- 이 방 파트 (V.parts 중 이 방 바닥 위에 있는 것)
	self.own = {}
	for _, r in V.parts do
		r.mine = self:mine(r.c)
		if r.mine then
			table.insert(self.own, r)
		end
	end
	self:buildSegments()
	return self
end

-- 시간 분할 (빌드 코루틴 안: 긴 검색 루프가 한 프레임을 오래 잡지 않게)
function C:yield()
	local now = os.clock()
	if now - (self._yt or 0) > 0.004 then
		task.wait()
		self._yt = os.clock()
	end
end

-- 점 p(로컬)의 바닥이 어느 방인가: 그 점 아래 가장 높은 바닥, 같으면 작은 바닥
function C:roomAt(p: Vector3): string?
	local best, bt, ba = nil, -math.huge, math.huge
	for _, f in self.floors do
		if p.X >= f.mn.X - 0.02 and p.X <= f.mx.X + 0.02 and p.Z >= f.mn.Z - 0.02 and p.Z <= f.mx.Z + 0.02 then
			local top = f.mx.Y
			if top <= p.Y + 0.75 and p.Y - top < 19 then
				local area = (f.mx.X - f.mn.X) * (f.mx.Z - f.mn.Z)
				if top > bt + 0.03 or (math.abs(top - bt) <= 0.03 and area < ba) then
					best, bt, ba = f.room, top, area
				end
			end
		end
	end
	return best
end
function C:mine(p: Vector3): boolean
	return self:roomAt(p) == self.room
end
-- 이 방 바닥들 중 가장 큰 것의 가운데
function C:floorCenter(): Vector3
	local best, ba = nil, -1
	for _, f in self.floors do
		if f.room == self.room and math.abs(f.mx.Y) < 1.2 then
			local a = (f.mx.X - f.mn.X) * (f.mx.Z - f.mn.Z)
			if a > ba then
				best, ba = f, a
			end
		end
	end
	if best then
		return V3((best.mn.X + best.mx.X) / 2, 0, (best.mn.Z + best.mx.Z) / 2)
	end
	return V3((self.V.x0 + self.V.x1) / 2, 0, (self.V.z0 + self.V.z1) / 2)
end
-- (x, z) 위 천장 아랫면 높이 (없으면 방 상자 높이)
function C:ceilAt(x: number, z: number): number
	local h = math.huge
	for _, s in self.slabs do
		if x >= s.mn.X - 0.05 and x <= s.mx.X + 0.05 and z >= s.mn.Z - 0.05 and z <= s.mx.Z + 0.05 and s.mn.Y > 4.5 then
			h = math.min(h, s.mn.Y)
		end
	end
	if h == math.huge then
		return self.Hbox or self.V.H
	end
	return h
end
function C:insideWall(q: Vector3): boolean
	for _, w in self.walls do
		if q.X > w.mn.X + 0.005 and q.X < w.mx.X - 0.005 and q.Z > w.mn.Z + 0.005 and q.Z < w.mx.Z - 0.005 and q.Y >= w.mn.Y and q.Y <= w.mx.Y then
			return true
		end
	end
	return false
end

-- 실제 벽면 구간: 쉘 벽 파트의 네 옆면 중 이 방 바닥에 닿는 부분
--   seg = { p0 (u=0 바닥 높이 점), t (보는 사람 오른쪽), n (방 안쪽), len, bot, top, part, a, b }
function C:buildSegments()
	self.segs = {}
	for _, w in self.walls do
		self:yield()
		local mn, mx = w.mn, w.mx
		local py = math.clamp((math.max(mn.Y, 0.2) + math.min(mx.Y, self.H - 0.2)) / 2, 0.2, self.H - 0.2)
		if mx.Y < 0.3 or mn.Y > self.H + 0.5 then
			continue
		end
		local faces = {
			{ n = V3(-1, 0, 0), f = mn.X, a = mn.Z, b = mx.Z, ax = "Z" },
			{ n = V3(1, 0, 0), f = mx.X, a = mn.Z, b = mx.Z, ax = "Z" },
			{ n = V3(0, 0, -1), f = mn.Z, a = mn.X, b = mx.X, ax = "X" },
			{ n = V3(0, 0, 1), f = mx.Z, a = mn.X, b = mx.X, ax = "X" },
		}
		for _, fc in faces do
			local len = fc.b - fc.a
			if len < 0.12 then
				continue
			end
			local function probe(s: number): boolean
				local q
				if fc.ax == "Z" then
					q = V3(fc.f + fc.n.X * 0.3, py, s)
				else
					q = V3(s, py, fc.f + fc.n.Z * 0.3)
				end
				if self:insideWall(q) then
					return false
				end
				return self:mine(V3(q.X, math.min(py, 1.0), q.Z))
			end
			local step = 0.2
			local n = math.max(1, math.floor(len / step))
			local runs = {}
			local cur = nil
			for i = 0, n do
				local s = fc.a + math.min(len, i * len / n)
				local ok = probe(math.clamp(s, fc.a + 0.01, fc.b - 0.01))
				if ok and not cur then
					cur = { s, s }
				elseif ok and cur then
					cur[2] = s
				elseif not ok and cur then
					table.insert(runs, cur)
					cur = nil
				end
			end
			if cur then
				table.insert(runs, cur)
			end
			for _, r in runs do
				-- 끝 다듬기 (이분 탐색)
				local function refine(good: number, bad: number): number
					for _ = 1, 8 do
						local m = (good + bad) / 2
						if probe(m) then
							good = m
						else
							bad = m
						end
					end
					return good
				end
				local s0, s1 = r[1], r[2]
				if s0 > fc.a + 0.02 then
					s0 = refine(s0, math.max(fc.a, s0 - len / n))
				else
					s0 = fc.a
				end
				if s1 < fc.b - 0.02 then
					s1 = refine(s1, math.min(fc.b, s1 + len / n))
				else
					s1 = fc.b
				end
				if s1 - s0 >= 0.12 then
					local nrm = fc.n
					local t = (-nrm):Cross(YA)
					local pa, pb
					if fc.ax == "Z" then
						pa, pb = V3(fc.f, 0, s0), V3(fc.f, 0, s1)
					else
						pa, pb = V3(s0, 0, fc.f), V3(s1, 0, fc.f)
					end
					local p0 = if (pb - pa):Dot(t) >= 0 then pa else pb
					table.insert(self.segs, {
						p0 = p0, t = t, n = nrm, len = s1 - s0, bot = mn.Y, top = mx.Y, part = w.part, name = w.name,
						openA = s0 <= fc.a + 0.001, openB = s1 >= fc.b - 0.001,
					})
				end
			end
		end
	end
end

-- 벽 구간 위 점의 dcf (u 는 구간 시작에서 보는 사람 오른쪽으로)
function C:segCF(s: any, u: number, y: number, off: number?): CFrame
	return CFrame.fromMatrix(s.p0 + s.t * u + V3(0, y, s.p0.Y * 0) + s.n * (off or 0), s.t, YA, s.n)
end

-- 이 방에서 숨기지 않은 · 보이는 (쉘이 아닌) 파트들 (자리 확인용 장애물)
function C:obstacles(): { any }
	if self._obs then
		return self._obs
	end
	local out = {}
	for _, r in self.V.parts do
		local p: BasePart = r.part
		if r.shell or not p.Parent then
			continue
		end
		if self.shell and p:IsDescendantOf(self.shell) then
			continue
		end
		if p.Transparency >= 0.95 then
			continue
		end
		if p.Name == "Baseboard" or p.Name == "Crown" or p.Name == "TexLine" then
			continue
		end
		table.insert(out, r)
	end
	self._obs = out
	return out
end

-- 로컬 상자가 비었나: 기존 파트 · keep(slot · point · door) · 이미 쓴 자리 · 벽 속
function C:boxFree(mn: Vector3, mx: Vector3, opts: any?): boolean
	local o: any = opts or {}
	for _, r in self:obstacles() do
		if not (o.ignore and o.ignore[r.part]) and boxHit(mn, mx, r.min, r.max, 0.01) then
			if not (o.skipHidden and self.K.hidden[r.part]) then
				return false
			end
		end
	end
	if not o.noKeep then
		for _, k in self.V.keep do
			if (k.kind == "slot" or k.kind == "point" or k.kind == "door" or k.kind == "restroom" or o.allKeep) and boxHit(mn, mx, k.min, k.max, 0.01) then
				return false
			end
		end
	end
	for _, u in self.used do
		if boxHit(mn, mx, u.mn, u.mx, 0.005) then
			return false
		end
	end
	return true
end
function C:use(mn: Vector3, mx: Vector3)
	table.insert(self.used, { mn = mn, mx = mx })
end

-- 벽면 빈 자리: w 폭 · y0..y1 높이 · dep 깊이. prefer = function(seg, u) -> 점수 (작을수록 좋음)
-- 반환 seg, u (구간 시작 기준), dcf (벽 표면, 가운데 높이)
function C:wallSpot(w: number, y0: number, y1: number, dep: number, opts: any?): (any?, number?, CFrame?)
	local o: any = opts or {}
	local best, bu, bs = nil, nil, math.huge
	for _, s in self.segs do
		if s.bot > y0 + 0.05 or s.top < y1 - 0.05 then
			continue
		end
		if o.filter and not o.filter(s) then
			continue
		end
		local margin = o.margin or 0.3
		if s.len < w + 2 * margin then
			continue
		end
		local stepU = o.step or 0.35
		local u = margin + w / 2
		self:yield()
		while u <= s.len - margin - w / 2 + 1e-3 do
			local cfm = self:segCF(s, u, (y0 + y1) / 2, dep / 2)
			local mn, mx = laabb(cfm, V3(w, y1 - y0, dep))
			local score = if o.score then o.score(s, u, cfm) else 0
			if score < bs and self:boxFree(mn, mx, o) and (not o.accept or o.accept(cfm)) then
				best, bu, bs = s, u, score
			end
			u += stepU
		end
	end
	if best then
		local cfm = self:segCF(best, bu :: number, (y0 + y1) / 2, dep / 2)
		local mn, mx = laabb(cfm, V3(w, y1 - y0, dep))
		self:use(mn, mx)
		return best, bu, self:segCF(best, bu :: number, (y0 + y1) / 2, 0)
	end
	return nil, nil, nil
end

-- 높이 건 벽 장식 (그림 · 선반, 바닥에서 4 이상): 문 앞 · 화장실 앞 통로 keep 은 머리 위라 상관없음 → 그 둘만 빼고 찾음
-- (벽 구간 = 막힌 벽이라 문 위에 걸리지 않음, 가구 · 슬롯 · 프롬프트 keep 은 그대로 봄)
function C:wallSpotHigh(w: number, y0: number, y1: number, dep: number, opts: any?): (any?, number?, CFrame?)
	local V = self.V
	local all = V.keep
	if y0 >= 4.0 then
		local f = {}
		for _, k in all do
			if k.kind ~= "door" and k.kind ~= "restroom" then
				table.insert(f, k)
			end
		end
		V.keep = f
	end
	local ok, a, b, c = pcall(function()
		return self:wallSpot(w, y0, y1, dep, opts)
	end)
	V.keep = all
	if not ok then
		return nil, nil, nil
	end
	return a, b, c
end

-- 바닥 소품 자리 (K:spot + 이 방 바닥 위인지 + 기존 파트 피하기)
function C:floorSpot(pcf: CFrame, size: Vector3, pad: number?): boolean
	local K, V = self.K, self.V
	if V.decorPlus then
		return false
	end
	local c = pcf * CF(0, size.Y / 2, 0)
	local mn, mx = laabb(c, size + V3(2 * (pad or 0), 0, 2 * (pad or 0)))
	-- 네 모서리 + 가운데가 이 방 바닥 위
	for _, q in { V3(mn.X, 0.5, mn.Z), V3(mx.X, 0.5, mn.Z), V3(mn.X, 0.5, mx.Z), V3(mx.X, 0.5, mx.Z), V3((mn.X + mx.X) / 2, 0.5, (mn.Z + mx.Z) / 2) } do
		if not self:mine(q) or self:insideWall(q) then
			return false
		end
	end
	for _, w in self.walls do
		if boxHit(mn, mx, w.mn, w.mx, 0.01) then
			return false
		end
	end
	if not self:boxFree(mn, mx, { allKeep = true }) then
		return false
	end
	if not K:spot(pcf, size, pad) then
		return false
	end
	self:use(mn, mx)
	return true
end

-- 천장 빈 자리 (x, z 둘레 r 안에 천장 근처 파트 · 이미 쓴 자리 없음)
function C:ceilFree(x: number, z: number, r: number): boolean
	local h = self:ceilAt(x, z)
	if not self:mine(V3(x, 0.5, z)) then
		return false
	end
	for _, rec in self.V.parts do
		if rec.max.Y > h - 1.6 and rec.min.Y < h + 0.2 and not (self.shell and rec.part:IsDescendantOf(self.shell)) and rec.part.Transparency < 0.95 then
			if x > rec.min.X - r and x < rec.max.X + r and z > rec.min.Z - r and z < rec.max.Z + r then
				return false
			end
		end
	end
	for _, s in self.slabs do
		-- 천장 높이가 바뀌는 경계 (단 · 트레이) 근처 피하기
		if s.mn.Y > 4.5 and math.abs(s.mn.Y - h) > 0.05 then
			local nearX = x > s.mn.X - r and x < s.mx.X + r
			local nearZ = z > s.mn.Z - r and z < s.mx.Z + r
			if nearX and nearZ then
				return false
			end
		end
	end
	for _, w in self.walls do
		if w.mx.Y > h - 0.3 and x > w.mn.X - r and x < w.mx.X + r and z > w.mn.Z - r and z < w.mx.Z + r then
			return false
		end
	end
	local mn, mx = V3(x - r, h - 1.0, z - r), V3(x + r, h, z + r)
	for _, u in self.used do
		if boxHit(mn, mx, u.mn, u.mx, 0.005) then
			return false
		end
	end
	for _, k in self.V.keep do
		if (k.kind == "slot") and boxHit(mn, mx, k.min, k.max, 0.01) then
			return false
		end
	end
	return true
end
function C:useCeil(x: number, z: number, r: number)
	local h = self:ceilAt(x, z)
	self:use(V3(x - r, h - 1.0, z - r), V3(x + r, h, z + r))
end

-- 불빛 (방마다 우리 불빛 3개까지: HS.FURNITURE_LIGHTS)
function C:light(part: BasePart?, kind: string, props: any): Light?
	if not part or self.lightsMine >= 3 then
		return nil
	end
	local l = self.K:light(part, kind, props)
	if l then
		self.lightsMine += 1
	end
	return l
end

-- 프롬프트 자리: 서버 프롬프트(집 상호작용 파트)와 2.6 스터드 이상
function C:promptOk(lp: Vector3): boolean
	for _, it in self.interacts do
		local p: BasePart = it.part
		local rel = p.CFrame:PointToObjectSpace(self.V.cf * lp)
		local h = p.Size / 2 + V3(1.3, 0.8, 1.3)
		if math.abs(rel.X) < h.X and math.abs(rel.Y) < h.Y and math.abs(rel.Z) < h.Z then
			return false
		end
	end
	return true
end
-- Interact 호출 (상점용 '주문대 근처 금지' 규칙 대신 집 규칙으로)
function C:withPrompt(part: BasePart?, fn: () -> any?): any?
	if not part or part.Parent == nil then
		return nil
	end
	if self.promptsMine >= 4 then
		return nil
	end
	local lp = self.V.cf:PointToObjectSpace(part.Position)
	if not self:promptOk(lp) then
		self.K:note("home prompt skipped near server prompt: " .. part.Name)
		return nil
	end
	local K = self.K
	local prev = K.hostPts
	K.hostPts = {}
	local ok, res = pcall(fn)
	K.hostPts = prev
	if not ok then
		K:note("prompt error: " .. tostring(res))
		return nil
	end
	if res then
		self.promptsMine += 1
	end
	return res
end

-- 숨기기 (장식용 엉성한 파트만)
function C:hide(p: Instance?)
	if p and p:IsA("BasePart") then
		Scan.hide(self.K.hidden, p)
	end
end
function C:hideAll(m: Instance?, except: ((BasePart) -> boolean)?)
	if not m then
		return
	end
	if m:IsA("BasePart") then
		if not (except and except(m)) then
			self:hide(m)
		end
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and not (except and except(d)) then
			self:hide(d)
		end
	end
end
-- 테마로 색이 바뀌거나 게임이 쓰는 파트 (숨기면 안 됨)
local function keepVisible(p: BasePart): boolean
	if p.Name == "Screen" or p.Name == "TVScreen" or p:GetAttribute("Screen") then
		return true
	end
	if p:GetAttribute("Room") ~= nil and p:GetAttribute("Surface") ~= nil then
		return true
	end
	if p:IsA("Seat") then
		return false
	end
	if CollectionService:HasTag(p, "HomeInteract") then
		return true
	end
	for _, c in p:GetChildren() do
		if c:IsA("SurfaceGui") or c:IsA("ProximityPrompt") then
			return true
		end
	end
	return false
end
T.keepVisible = keepVisible

-------------------------------------------------------------------------------------------------
-- 모델(가구 · 소품) 분석: 프레임 F (+Z = 정면) 안의 파트 AABB
-------------------------------------------------------------------------------------------------
local function yawOf(rel: CFrame): number
	local lv = rel.LookVector
	return math.atan2(-lv.X, -lv.Z)
end
local function quarter(a: number): number
	return math.floor(a / (PI / 2) + 0.5) % 4
end

-- parts 를 F (로컬 CFrame) 기준으로 분석
local function analyze(C_: any, F: CFrame, inst: Instance): any
	local cf: CFrame = C_.V.cf
	local Fw = cf * F
	local info: any = { F = F, by = {}, all = {}, min = V3(math.huge, math.huge, math.huge), max = V3(-math.huge, -math.huge, -math.huge) }
	local list = if inst:IsA("BasePart") then { inst } else inst:GetDescendants()
	if inst:IsA("Model") or inst:IsA("Folder") then
		list = inst:GetDescendants()
	end
	for _, d in list do
		if d:IsA("BasePart") then
			local p = d :: BasePart
			local mn, mx = laabb(Fw:ToObjectSpace(p.CFrame), p.Size)
			local r = { part = p, name = p.Name, min = mn, max = mx, c = (mn + mx) / 2, size = mx - mn, color = p.Color, mat = p.Material }
			table.insert(info.all, r)
			local l = info.by[p.Name]
			if not l then
				l = {}
				info.by[p.Name] = l
			end
			table.insert(l, r)
			if p.Transparency < 0.99 then
				info.min = info.min:Min(mn)
				info.max = info.max:Max(mx)
			end
		end
	end
	return info
end
local function first(info: any, ...: string): any?
	for _, n in { ... } do
		local l = info.by[n]
		if l and l[1] then
			return l[1]
		end
	end
	return nil
end
local function all(info: any, ...: string): { any }
	local out = {}
	for _, n in { ... } do
		for _, r in info.by[n] or {} do
			table.insert(out, r)
		end
	end
	return out
end

-- 슬롯 기본 가구의 프레임 (front = +Z). backNames 의 파트가 뒤(-Z)에 오도록 맞춤
local function slotFrame(C_: any, slot: Model, piece: Instance, backNames: { string }?): CFrame?
	local base = (slot.PrimaryPart or slot:FindFirstChild("SlotBase")) :: BasePart?
	if not (base and base:IsA("BasePart")) then
		return nil
	end
	local frame = base.CFrame * CF(0, -base.Size.Y / 2, 0)
	-- 회전: 부피 가중 다수결 (기본 가구 파트 대부분은 슬롯 방향 그대로)
	local votes = { 0, 0, 0, 0 }
	for _, d in piece:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.99 and not (d:IsA("Part") and (d :: Part).Shape ~= Enum.PartType.Block) and not d:FindFirstChildOfClass("SpecialMesh") then
			local rel = frame:ToObjectSpace(d.CFrame)
			if math.abs(rel.LookVector.Y) < 0.3 then
				local q = quarter(yawOf(rel)) + 1
				votes[q] += d.Size.X * d.Size.Y * d.Size.Z
			end
		end
	end
	local best, bv = 1, -1
	for i = 1, 4 do
		if votes[i] > bv then
			best, bv = i, votes[i]
		end
	end
	local pf = frame * ANG(0, (best - 1) * PI / 2, 0) * ANG(0, PI, 0) -- +Z = 정면
	local F = C_.V.cf:ToObjectSpace(pf)
	-- 의미 파트로 앞뒤 확인
	if backNames then
		local info = analyze(C_, F, piece)
		local ctr = (info.min + info.max) / 2
		local b = nil
		for _, n in backNames do
			b = first(info, n)
			if b then
				break
			end
		end
		if b then
			-- 앞뒤만 (옆 방향 어긋남은 다수결이 맞춤: 모니터가 옆에 있는 넓은 책상 등)
			local d = b.c - ctr
			if d.Z > 0.15 then
				F = F * ANG(0, PI, 0)
			end
		end
	end
	-- 벽 쪽 확인: 앞(+Z)이 벽이고 뒤(-Z)가 방이면 뒤집기 (템플릿마다 슬롯 앞 방향이 다름)
	local info = analyze(C_, F, piece)
	if info.min.X < math.huge then
		local cx = (info.min.X + info.max.X) / 2
		local cy = math.clamp((info.min.Y + info.max.Y) / 2, 0.5, C_.H - 0.5)
		local function open(z: number): boolean
			local q = (F * CF(cx, cy, z)).Position
			return C_:mine(V3(q.X, math.min(q.Y, 1.0), q.Z)) and not C_:insideWall(q)
		end
		local fOpen, bOpen = open(info.max.Z + 0.6), open(info.min.Z - 0.6)
		if not fOpen and bOpen then
			F = F * ANG(0, PI, 0)
		end
	end
	return F
end

-- 바닥이 수평인 소품 모델의 프레임: 뒤 = 가까운 벽 쪽 (또는 backPart 쪽)
local function propFrame(C_: any, m: Instance, backName: string?): (CFrame, any)
	local V = C_.V
	local mn, mx = V3(math.huge, math.huge, math.huge), V3(-math.huge, -math.huge, -math.huge)
	local parts = if m:IsA("BasePart") then { m } else m:GetDescendants()
	for _, d in parts do
		if d:IsA("BasePart") and d.Transparency < 0.99 then
			local a, b = laabb(V.cf:ToObjectSpace(d.CFrame), d.Size)
			mn, mx = mn:Min(a), mx:Max(b)
		end
	end
	local c = V3((mn.X + mx.X) / 2, mn.Y, (mn.Z + mx.Z) / 2)
	-- 가장 가까운 벽면 쪽이 뒤
	local bestN, bd = V3(0, 0, -1), math.huge
	for _, s in C_.segs do
		local rel = c - s.p0
		local u = rel:Dot(s.t)
		local dd = rel:Dot(s.n)
		if u > -0.5 and u < s.len + 0.5 and dd > -0.6 and dd < bd then
			bd = dd
			bestN = s.n
		end
	end
	local back = -bestN
	local F = CFrame.lookAt(c, c + back) -- -Z = 뒤 => +Z = 앞
	local info = analyze(C_, F, m)
	return F, info
end

T._ctx = newCtx
T._analyze = analyze

-------------------------------------------------------------------------------------------------
-- 공통 마감 1: 걸레받이 · 몰딩
-------------------------------------------------------------------------------------------------
-- 걸레받이를 끊을 것: 바닥에 닿은 붙박이(문틀 · 수납장 · 가전)
function C:trimCutters(): { any }
	if self._cut then
		return self._cut
	end
	local out = {}
	for _, r in self:obstacles() do
		local p: BasePart = r.part
		local inSlot = false
		local a = p.Parent
		while a and a ~= self.model do
			if a:IsA("Model") and (string.sub(a.Name, 1, 5) == "Slot_" or CollectionService:HasTag(a, "FurnitureSlot")) then
				inSlot = true
				break
			end
			a = a.Parent
		end
		if inSlot then
			continue
		end
		local isDoor = p.Name == "Casing" or p.Name == "DoorJamb" or (p.Parent and p.Parent.Name == "Door")
		if isDoor or (r.min.Y < 0.45 and r.max.Y - r.min.Y >= 0.6) then
			table.insert(out, r)
		end
	end
	self._cut = out
	return out
end

-- 구간 s 의 u 범위 [a, b] 에서 높이 y0..y1 · 깊이 dep 로 끊긴 빈 구간들
function C:segRuns(s: any, y0: number, y1: number, dep: number, cutters: { any }, pad: number?): { { number } }
	local cuts = {}
	local e = pad or 0.02
	for _, r in cutters do
		if r.max.Y < y0 or r.min.Y > y1 then
			continue
		end
		-- 상자 꼭짓점을 구간 좌표로
		local umin, umax, dmin = math.huge, -math.huge, math.huge
		for _, x in { r.min.X, r.max.X } do
			for _, z in { r.min.Z, r.max.Z } do
				local rel = V3(x, 0, z) - V3(s.p0.X, 0, s.p0.Z)
				umin = math.min(umin, rel:Dot(s.t))
				umax = math.max(umax, rel:Dot(s.t))
				dmin = math.min(dmin, rel:Dot(s.n))
			end
		end
		local dmax = -math.huge
		for _, x in { r.min.X, r.max.X } do
			for _, z in { r.min.Z, r.max.Z } do
				dmax = math.max(dmax, (V3(x, 0, z) - V3(s.p0.X, 0, s.p0.Z)):Dot(s.n))
			end
		end
		if dmin < dep and dmax > -0.05 and umax > 0 and umin < s.len then
			table.insert(cuts, { umin - e, umax + e })
		end
	end
	table.sort(cuts, function(a, b)
		return a[1] < b[1]
	end)
	local out = {}
	local cur = 0
	for _, c in cuts do
		if c[1] > cur then
			table.insert(out, { cur, math.min(c[1], s.len) })
		end
		cur = math.max(cur, c[2])
	end
	if cur < s.len then
		table.insert(out, { cur, s.len })
	end
	local res = {}
	for _, r in out do
		if r[2] - r[1] > 0.1 then
			table.insert(res, r)
		end
	end
	return res
end

local function baseboardRun(C_: any, s: any, u0: number, u1: number)
	local K = C_.K
	local pal = C_.pal
	local look = C_.baseLook or pal.base
	local kind = pal.baseKind
	-- 볼록 모서리 감싸기
	local e0 = if s.openA and u0 <= 0.001 then 0.07 else 0
	local e1 = if s.openB and u1 >= s.len - 0.001 then 0.07 else 0
	local a, b = u0 - e0, u1 + e1
	local len = b - a
	local mid = (a + b) / 2
	if len < 0.08 then
		return
	end
	local function plate(name: string, h: number, d: number, y: number, lk_: any)
		K:box(name, V3(len, h, d), C_:segCF(s, mid, y, d / 2 + 0.002), lk_)
	end
	if kind == "pvc" then
		plate("HomeBaseboard", 0.34, 0.05, 0.17, look)
		K:cyl("HomeBaseboardBead", len, 0.06, C_:segCF(s, mid, 0.33, 0.035) , look)
		plate("HomeBaseboardLine", 0.015, 0.052, 0.27, tint(look, 0.12))
	elseif kind == "classic" then
		plate("HomeBaseboard", 0.42, 0.06, 0.21, look)
		plate("HomeBaseboardCap", 0.06, 0.085, 0.39, look)
		plate("HomeBaseboardGroove", 0.02, 0.062, 0.3, tint(look, 0.16))
	elseif kind == "slim" then
		plate("HomeBaseboard", 0.24, 0.035, 0.12, look)
		plate("HomeBaseboardGap", 0.03, 0.02, 0.255, lk(70, 70, 74))
	else -- luxury: 매립형 금속 걸레받이 + 그림자 줄눈
		plate("HomeBaseboard", 0.3, 0.025, 0.15, look)
		plate("HomeBaseboardGap", 0.035, 0.012, 0.318, lk(24, 22, 20))
	end
end

local function crownRun(C_: any, s: any, u0: number, u1: number, h: number)
	local K = C_.K
	local pal = C_.pal
	local look = C_.crownLook or pal.crown
	local kind = pal.crownKind
	local e0 = if s.openA and u0 <= 0.001 then 0.1 else 0
	local e1 = if s.openB and u1 >= s.len - 0.001 then 0.1 else 0
	local a, b = u0 - e0, u1 + e1
	local len = b - a
	local mid = (a + b) / 2
	if len < 0.1 then
		return
	end
	if kind == "flat" then
		K:box("HomeCrown", V3(len, 0.16, 0.05), C_:segCF(s, mid, h - 0.08, 0.027), look)
		K:box("HomeCrownLip", V3(len, 0.04, 0.09), C_:segCF(s, mid, h - 0.02, 0.047), look)
	elseif kind == "step" then
		K:box("HomeCrown", V3(len, 0.22, 0.05), C_:segCF(s, mid, h - 0.11, 0.027), look)
		K:box("HomeCrownStep", V3(len, 0.09, 0.1), C_:segCF(s, mid, h - 0.045, 0.052), look)
		K:box("HomeCrownShadow", V3(len, 0.012, 0.052), C_:segCF(s, mid, h - 0.16, 0.028), tint(look, 0.1))
	elseif kind == "step3" then
		K:box("HomeCrown", V3(len, 0.3, 0.04), C_:segCF(s, mid, h - 0.15, 0.022), look)
		K:box("HomeCrownStep", V3(len, 0.18, 0.09), C_:segCF(s, mid, h - 0.09, 0.047), look)
		K:box("HomeCrownTop", V3(len, 0.07, 0.15), C_:segCF(s, mid, h - 0.035, 0.077), look)
		K:box("HomeCrownShadow", V3(len, 0.012, 0.042), C_:segCF(s, mid, h - 0.24, 0.023), tint(look, 0.1))
		K:box("HomeCrownShadow", V3(len, 0.01, 0.092), C_:segCF(s, mid, h - 0.12, 0.048), tint(look, 0.08))
	else -- gap: 무몰딩 (그림자 줄눈)
		K:box("HomeShadowGap", V3(len, 0.05, 0.012), C_:segCF(s, mid, h - 0.025, 0.007), look)
	end
end

function C:trims()
	local K, V = self.K, self.V
	-- 기존 엉성한 걸레받이 · 몰딩 색을 이어받고 숨김
	for _, r in self.own do
		if r.name == "Baseboard" then
			if not self.baseLook and self.tier ~= "penthouse" then
				self.baseLook = lk(math.floor(r.part.Color.R * 255), math.floor(r.part.Color.G * 255), math.floor(r.part.Color.B * 255))
			end
			self:hide(r.part)
		elseif r.name == "Crown" then
			if not self.crownLook and self.pal.crownKind ~= "gap" then
				self.crownLook = lk(math.floor(r.part.Color.R * 255), math.floor(r.part.Color.G * 255), math.floor(r.part.Color.B * 255))
			end
			self:hide(r.part)
		end
	end
	-- 벽 바깥 모서리에 걸친 이웃 방의 걸레받이 · 몰딩은 그 방이 맡음
	local cutters = self:trimCutters()
	K:free(function()
		for _, s in self.segs do
			if s.bot <= 0.35 and s.top >= 0.45 then
				for _, r in self:segRuns(s, 0, 0.45, 0.12, cutters) do
					baseboardRun(self, s, r[1], r[2])
				end
			end
			-- 몰딩: 천장까지 닿은 벽
			local mp = s.p0 + s.t * (s.len / 2) + s.n * 0.3
			local h = self:ceilAt(mp.X, mp.Z)
			if s.top >= h - 0.25 and s.bot <= h - 0.6 and h - 0.6 > 0 then
				local cutHigh = {}
				for _, r in self:obstacles() do
					if r.max.Y > h - 0.5 and r.min.Y < h then
						table.insert(cutHigh, r)
					end
				end
				for _, r in self:segRuns(s, h - 0.4, h, 0.2, cutHigh) do
					crownRun(self, s, r[1], r[2], h)
				end
			end
		end
	end)
end


-------------------------------------------------------------------------------------------------
-- 공통 마감 2: 스위치 · 콘센트 · 문 · 천장 설비 · 창 철물
-------------------------------------------------------------------------------------------------
-- 벽에 붙은 얇은 파트(스위치 · 콘센트 · 판)의 방 쪽 표면 dcf
function C:wallFace(p: BasePart): CFrame?
	local lc = self.V.cf:ToObjectSpace(p.CFrame)
	local axes = { { lc.ZVector, p.Size.Z }, { lc.XVector, p.Size.X } }
	table.sort(axes, function(a, b)
		return a[2] < b[2]
	end)
	local ax: Vector3 = axes[1][1]
	local th: number = axes[1][2]
	for _, sgn in { 1, -1 } do
		local n = ax * sgn
		n = V3(n.X, 0, n.Z)
		if n.Magnitude > 0.5 then
			n = n.Unit
			local q = lc.Position + n * (th / 2 + 0.3)
			if not self:insideWall(V3(q.X, q.Y, q.Z)) and self:mine(V3(q.X, 0.5, q.Z)) then
				local back = lc.Position - n * (th / 2)
				return faceCF(back, n)
			end
		end
	end
	return nil
end

local function switchPlate(C_: any, dcf: CFrame, w: number, n: number, name: string?): BasePart
	local K, pal = C_.K, C_.pal
	local h = 0.46
	local plate = K:box(name or "HomeSwitchPlate", V3(w, h, 0.045), dcf * CF(0, 0, 0.0225), pal.plate)
	K:box("HomeSwitchFrame", V3(w - 0.06, h - 0.06, 0.02), dcf * CF(0, 0, 0.055), tint(pal.plate, 0.04))
	local rw = (w - 0.1) / n
	for i = 1, n do
		local x = -w / 2 + 0.05 + rw * (i - 0.5)
		K:box("HomeSwitchRocker", V3(rw - 0.025, h - 0.12, 0.03), dcf * CF(x, 0, 0.07) * ANG(math.rad(-3), 0, 0), pal.rocker)
		K:box("HomeSwitchLED", V3(0.03, 0.03, 0.012), dcf * CF(x, -h / 2 + 0.1, 0.09), L.neon(c3(255, 150, 60)))
	end
	return plate
end
T.switchPlate = switchPlate

local function outletPlate(C_: any, dcf: CFrame, w: number?, plugs: number?): BasePart
	local K, pal = C_.K, C_.pal
	local ww = w or 0.46
	local n = plugs or 2
	local plate = K:box("HomeOutletPlate", V3(ww, 0.3, 0.045), dcf * CF(0, 0, 0.0225), pal.plate)
	for i = 1, n do
		local x = -ww / 2 + ww * (i - 0.5) / n
		K:cyl("HomeOutletSocket", 0.03, 0.17, dcf * CF(x, 0, 0.05) * ANG(0, PI / 2, 0), tint(pal.plate, 0.05))
		for _, sx in { -0.035, 0.035 } do
			K:box("HomeOutletPin", V3(0.018, 0.018, 0.012), dcf * CF(x + sx, 0, 0.068), lk(40, 40, 42))
		end
		K:box("HomeOutletGround", V3(0.02, 0.05, 0.01), dcf * CF(x, 0.075, 0.066), L.brushed)
	end
	return plate
end
T.outletPlate = outletPlate

-- 플러그 + 전선 (콘센트 dcf 에서 바닥 쪽으로)
local function plugCable(C_: any, dcf: CFrame, toward: Vector3?, look: any?)
	local K = C_.K
	local cl = look or lk(236, 236, 232)
	K:box("HomePlug", V3(0.12, 0.16, 0.14), dcf * CF(-0.11, 0, 0.12), cl)
	local a = (dcf * CF(-0.11, -0.08, 0.14)).Position
	local b = V3(a.X, 0.03, a.Z) + (dcf.ZVector * 0.06)
	K:seg("HomeCable", a, b, 0.035, cl)
	if toward then
		K:seg("HomeCable", b, V3(toward.X, 0.03, toward.Z), 0.035, cl)
	end
end
T.plugCable = plugCable

function C:fixtures()
	local K, V = self.K, self.V
	K:free(function()
		-- 기존 스위치 · 콘센트 리스킨
		for _, r in self.own do
			local p: BasePart = r.part
			if p.Name == "Switch" or p.Name == "Outlet" then
				local dcf = self:wallFace(p)
				if dcf then
					local w = math.max(p.Size.X, p.Size.Z)
					if math.min(p.Size.X, p.Size.Z) > 0.2 then
						w = math.max(p.Size.X, p.Size.Z)
					end
					local wide = if p.Size.Z <= 0.08 then p.Size.X else p.Size.Z
					if p.Name == "Switch" then
						local n = if wide >= 0.65 then 3 elseif wide >= 0.5 then 2 else 1
						local plate = switchPlate(self, dcf, math.max(0.3, wide + 0.04), n)
						self.switches = self.switches or {}
						table.insert(self.switches, plate)
					else
						outletPlate(self, dcf, math.max(0.42, wide + 0.04), 2)
					end
					self:hide(p)
					local mn, mx = laabb(dcf * CF(0, 0, 0.1), V3(w + 0.4, 0.6, 0.3))
					self:use(mn, mx)
				end
			elseif p.Name == "SmokeDetector" then
				local h = self:ceilAt(r.c.X, r.c.Z)
				self:smoke(r.c.X, r.c.Z, h)
				self:hide(p)
				self:useCeil(r.c.X, r.c.Z, 0.5)
			elseif p.Name == "Sprinkler" then
				local h = self:ceilAt(r.c.X, r.c.Z)
				self:sprinkler(r.c.X, r.c.Z, h)
				self:hide(p)
				self:useCeil(r.c.X, r.c.Z, 0.35)
			end
		end
	end)
	self:doors()
end

function C:smoke(x: number, z: number, h: number)
	local K = self.K
	K:disc("HomeSmokeBase", 0.56, 0.03, CF(x, h - 0.015, z), L.white)
	K:disc("HomeSmokeBody", 0.48, 0.1, CF(x, h - 0.08, z), lk(246, 246, 244))
	K:disc("HomeSmokeVent", 0.5, 0.025, CF(x, h - 0.09, z), lk(214, 214, 212))
	K:disc("HomeSmokeCap", 0.3, 0.04, CF(x, h - 0.145, z), lk(250, 250, 248))
	K:disc("HomeSmokeLED", 0.04, 0.012, CF(x + 0.14, h - 0.135, z), L.ledRed)
end
function C:sprinkler(x: number, z: number, h: number)
	local K = self.K
	if (self.lux or 1) >= 3 then
		-- 신축 아파트 · 오피스텔: 매립형 (컨실드) 스프링클러 — 천장에 붙은 하얀 덮개판 + 가는 틈
		K:disc("HomeSprinklerPlate", 0.32, 0.02, CF(x, h - 0.01, z), lk(244, 244, 242))
		K:disc("HomeSprinklerGap", 0.36, 0.008, CF(x, h - 0.004, z), lk(200, 200, 198))
		return
	end
	K:disc("HomeSprinklerCup", 0.34, 0.025, CF(x, h - 0.012, z), L.white)
	K:vcyl("HomeSprinklerBody", 0.12, 0.09, CF(x, h - 0.08, z), L.brass)
	K:vcyl("HomeSprinklerBulb", 0.08, 0.035, CF(x, h - 0.15, z), L.neon(c3(220, 40, 30), 0.2))
	K:disc("HomeSprinklerDeflector", 0.2, 0.015, CF(x, h - 0.2, z), L.brass)
end

-- 문: 경첩 · 말굽 도어스토퍼 · 문짝 홈 · 문선 몰딩
function C:doors()
	local K = self.K
	if not self.model then
		return
	end
	local cf: CFrame = self.V.cf
	for _, d in self.model:GetDescendants() do
		if not (d:IsA("Model") and d.Name == "Door") then
			continue
		end
		local leaf = d:FindFirstChild("DoorLeaf")
		if not (leaf and leaf:IsA("BasePart")) then
			continue
		end
		if leaf.Material == M.Metal then
			continue -- 현관 철문 (HomeWet 몫)
		end
		local lc = cf:ToObjectSpace(leaf.CFrame)
		if not self:mine(V3(lc.Position.X, 0.5, lc.Position.Z)) then
			continue
		end
		-- 경첩 쪽: 문틀(DoorJamb)에 가까운 끝
		local ends = { lc * V3(leaf.Size.X / 2, 0, 0), lc * V3(-leaf.Size.X / 2, 0, 0) }
		local hingeI, bd = 1, math.huge
		for i, e in ends do
			for _, j in d:GetChildren() do
				if j:IsA("BasePart") and j.Name == "DoorJamb" then
					local jp = cf:PointToObjectSpace(j.Position)
					local dd = (V3(jp.X, 0, jp.Z) - V3(e.X, 0, e.Z)).Magnitude
					if dd < bd then
						hingeI, bd = i, dd
					end
				end
			end
		end
		local sx = if hingeI == 1 then 1 else -1
		local hh = leaf.Size.Y
		local yb = lc.Position.Y - hh / 2
		K:free(function()
			for _, fy in { 0.12, 0.5, 0.88 } do
				local hp = lc * CF(sx * (leaf.Size.X / 2 + 0.02), -hh / 2 + hh * fy, 0)
				K:vcyl("HomeHinge", 0.36, 0.09, hp, self.pal.hinge)
				K:vcyl("HomeHingeCap", 0.04, 0.1, hp * CF(0, 0.2, 0), self.pal.hinge)
			end
			-- 말굽 도어스토퍼 (문 아래 손잡이 쪽, 양면 중 방 쪽)
			local free = lc * CF(-sx * (leaf.Size.X / 2 - 0.35), -hh / 2, 0)
			for _, side in { 1, -1 } do
				local sp = free * CF(0, 0, side * (leaf.Size.Z / 2 + 0.06))
				if self:mine(V3(sp.Position.X, 0.5, sp.Position.Z)) then
					K:box("HomeDoorStopBase", V3(0.22, 0.32, 0.08), sp * CF(0, 0.28, 0), self.pal.hinge)
					K:box("HomeDoorStopArm", V3(0.12, 0.2, 0.1), sp * CF(0, 0.12, side * 0.05), self.pal.hinge)
					K:box("HomeDoorStopFoot", V3(0.16, 0.04, 0.14), sp * CF(0, 0.02, side * 0.06), L.rubber)
					break
				end
			end
			-- 문짝 홈 (ABS 문: 가로 홈 3줄, 양면)
			if self.lux <= 4 and leaf.Material ~= M.Glass then
				for _, side in { 1, -1 } do
					for _, fy in { 0.28, 0.5, 0.72 } do
						K:box("HomeDoorGroove", V3(leaf.Size.X - 0.5, 0.025, 0.01), lc * CF(0, -hh / 2 + hh * fy, side * (leaf.Size.Z / 2 + 0.004)), tint(withC(L.white, leaf.Color), 0.08))
					end
				end
			end
			local _ = yb
		end)
		-- 문선 몰딩 (이 방 쪽 문선에 바깥 테 · 안쪽 비드)
		for _, cs in d:GetChildren() do
			if cs:IsA("BasePart") and cs.Name == "Casing" then
				local cc = cf:ToObjectSpace(cs.CFrame)
				local q = cc.Position
				local dcf = self:wallFace(cs)
				if dcf and self:mine(V3(q.X, 0.5, q.Z) + dcf.ZVector * 0.3) then
					local vertical = cs.Size.Y > math.max(cs.Size.X, cs.Size.Z)
					local long = if vertical then cs.Size.Y else math.max(cs.Size.X, cs.Size.Z)
					local wide = if vertical then math.max(cs.Size.X, cs.Size.Z) else cs.Size.Y
					local th = math.min(cs.Size.X, cs.Size.Z)
					local col = withC(L.white, cs.Color)
					K:free(function()
						local c = dcf * CF(0, 0, th)
						if vertical then
							K:box("HomeCasingBand", V3(0.05, long, 0.04), c * CF(0, 0, 0.02) * CF(0, 0, 0), tint(col, 0.04))
							K:box("HomeCasingEdge", V3(0.04, long, 0.03), c * CF(0, 0, 0.015) * CF((wide / 2 - 0.02) * 1, 0, 0), tint(col, 0.1))
						else
							K:box("HomeCasingBand", V3(long, 0.05, 0.04), c * CF(0, 0, 0.02), tint(col, 0.04))
						end
					end)
				end
			end
		end
	end
end

local function cf_point(V: any, wp: Vector3): Vector3
	local p = V.cf:PointToObjectSpace(wp)
	return V3(p.X, math.max(p.Y, 0.5), p.Z)
end

-- 천장 설비 보충: 감지기 · 스프링클러 · (등급별) 시스템 에어컨 · 라인 디퓨저
function C:ceilingKit()
	local K, V = self.K, self.V
	local fc = self:floorCenter()
	local hasSmoke, hasSprk, hasAC = false, false, false
	for _, r in self.own do
		if r.name == "SmokeDetector" then
			hasSmoke = true
		elseif r.name == "Sprinkler" then
			hasSprk = true
		elseif r.name == "CeilingAC" or r.name == "WallAC" or r.name == "StandAC" or r.name == "ACOutdoor" then
			hasAC = true
		end
	end
	for _, sl in self.slots do
		local cat = sl:GetAttribute("Category")
		local id = sl:GetAttribute("SlotId")
		if (cat == "appliance" and id == "aircon") then
			local b = sl:FindFirstChild("SlotBase")
			if b and b:IsA("BasePart") and self:mine(cf_point(V, b.Position)) then
				hasAC = true
			end
		end
	end
	-- 이 방 바닥 상자 (가장 큰 바닥)
	local bx0, bx1, bz0, bz1 = V.x0, V.x1, V.z0, V.z1
	local function tryAt(fx: number, fz: number, r: number, fn: (number, number, number) -> ()): boolean
		for k = 0, 6 do
			local x = fc.X + (bx1 - bx0) * fx * (1 - k * 0.12) + (if k % 2 == 1 then 0.7 else -0.4) * (k // 2)
			local z = fc.Z + (bz1 - bz0) * fz * (1 - k * 0.12) + (if k % 3 == 1 then 0.6 else 0) * (k // 2)
			if self:ceilFree(x, z, r) then
				local h = self:ceilAt(x, z)
				K:free(function()
					fn(x, z, h)
				end)
				self:useCeil(x, z, r)
				return true
			end
		end
		return false
	end
	if not hasSmoke then
		tryAt(0.12, -0.08, 0.5, function(x, z, h)
			self:smoke(x, z, h)
		end)
	end
	if not hasSprk and self.tier ~= "oneroom" then
		local area = (bx1 - bx0) * (bz1 - bz0)
		local n = math.clamp(math.floor(area / 70) + 1, 1, 4)
		local spots = { { -0.22, -0.2 }, { 0.22, 0.22 }, { 0.22, -0.22 }, { -0.22, 0.22 } }
		for i = 1, n do
			tryAt(spots[i][1], spots[i][2], 0.4, function(x, z, h)
				self:sprinkler(x, z, h)
			end)
		end
	end
	-- 시스템 에어컨 (오피스텔 · 아파트 거실 · 펜트하우스): 에어컨이 없는 방만
	if not hasAC and (self.tier == "officetel" or self.tier == "apartment" or self.tier == "penthouse") and self.room ~= "dress" and self.room ~= "main" then
		local h = self:ceilAt(fc.X, fc.Z)
		if self.tier == "penthouse" and h > 11 then
			return -- 복층 높은 천장: 창가 바닥 매립 (없음)
		end
		tryAt(0.0, -0.18, 1.4, function(x, z, hh)
			self:cassette(x, z, hh, if self.tier == "apartment" and self.room == "living" then 4 else 1)
		end)
	end
end


-- 천장형 에어컨 (n = 4 방향 카세트 | 1 방향 슬림)
function C:cassette(x: number, z: number, h: number, n: number)
	local K = self.K
	local body = lk(246, 246, 244)
	local grille = lk(226, 228, 228)
	local vanes = {}
	if n >= 4 then
		local s = 2.6
		K:box("HomeACPanel", V3(s, 0.1, s), CF(x, h - 0.05, z), body)
		K:box("HomeACGrille", V3(s * 0.48, 0.02, s * 0.48), CF(x, h - 0.11, z), grille)
		for i = 1, 6 do
			K:box("HomeACGrilleBar", V3(s * 0.46, 0.012, 0.02), CF(x, h - 0.122, z - s * 0.22 + i * s * 0.063), lk(200, 202, 204))
		end
		for k = 0, 3 do
			local a = k * PI / 2
			local p = CF(x, h - 0.1, z) * ANG(0, a, 0) * CF(0, 0, s * 0.36)
			table.insert(vanes, K:box("HomeACVane", V3(s * 0.62, 0.03, 0.22), p * ANG(math.rad(-20), 0, 0), lk(236, 236, 234)))
			K:box("HomeACSlot", V3(s * 0.66, 0.012, 0.3), p * CF(0, -0.002, 0), lk(60, 62, 66))
		end
		K:box("HomeACLED", V3(0.12, 0.012, 0.04), CF(x + s * 0.4, h - 0.11, z + s * 0.44), L.neon(c3(80, 200, 255)))
	else
		local w, d = 3.4, 1.2
		K:box("HomeACPanel", V3(w, 0.1, d), CF(x, h - 0.05, z), body)
		K:box("HomeACGrille", V3(w * 0.8, 0.02, d * 0.36), CF(x, h - 0.11, z - d * 0.2), grille)
		K:box("HomeACSlot", V3(w * 0.86, 0.012, d * 0.3), CF(x, h - 0.112, z + d * 0.22), lk(60, 62, 66))
		table.insert(vanes, K:box("HomeACVane", V3(w * 0.84, 0.03, d * 0.26), CF(x, h - 0.12, z + d * 0.22) * ANG(math.rad(-15), 0, 0), lk(236, 236, 234)))
		K:box("HomeACLED", V3(0.12, 0.012, 0.04), CF(x + w * 0.4, h - 0.11, z - d * 0.4), L.neon(c3(80, 200, 255)))
	end
	self.acVanes = vanes
	self.acAt = V3(x, h, z)
end

-- 창 철물: 크리센트 잠금 · 손잡이 · 방충망 (미닫이 창만)
function C:windows()
	local K = self.K
	if not self.model then
		return
	end
	local cf: CFrame = self.V.cf
	for _, w in self.model:GetDescendants() do
		if not (w:IsA("Model") and (w.Name == "Window" or w.Name == "VerandaWindow")) then
			continue
		end
		local glass = {}
		local mn, mx = V3(math.huge, math.huge, math.huge), V3(-math.huge, -math.huge, -math.huge)
		for _, p in w:GetDescendants() do
			if p:IsA("BasePart") then
				local a, b = laabb(cf:ToObjectSpace(p.CFrame), p.Size)
				mn, mx = mn:Min(a), mx:Max(b)
				if p.Name == "WindowGlass" then
					table.insert(glass, { a = a, b = b })
				end
			end
		end
		if #glass < 2 then
			continue
		end
		local c = (mn + mx) / 2
		local alongX = (mx.X - mn.X) >= (mx.Z - mn.Z)
		-- 방 쪽 법선
		local n = nil
		for _, cand in (if alongX then { V3(0, 0, 1), V3(0, 0, -1) } else { V3(1, 0, 0), V3(-1, 0, 0) }) do
			local q = c + cand * ((if alongX then mx.Z - mn.Z else mx.X - mn.X) / 2 + 0.6)
			if self:mine(V3(q.X, 0.5, q.Z)) then
				n = cand
			end
		end
		if not n then
			continue
		end
		local half = (if alongX then mx.Z - mn.Z else mx.X - mn.X) / 2
		-- 가장 안쪽 유리면
		local face = c + n * (half - 0.02)
		local inner = -math.huge
		for _, g in glass do
			local gc = (g.a + g.b) / 2
			local d = (gc - c):Dot(n)
			inner = math.max(inner, d)
		end
		local f = faceCF(V3(c.X, c.Y, c.Z) + n * (inner + 0.05), n)
		local width = if alongX then mx.X - mn.X else mx.Z - mn.Z
		local height = mx.Y - mn.Y
		K:free(function()
			-- 가운데 만나는 창살에 크리센트 + 양쪽 손잡이
			K:box("HomeCrescentBase", V3(0.22, 0.12, 0.05), f * CF(0, 0, 0.03), L.white)
			K:box("HomeCrescentLever", V3(0.26, 0.05, 0.05), f * CF(0.03, 0.03, 0.07) * ANG(0, 0, math.rad(-12)), L.chrome)
			for _, sx in { -1, 1 } do
				K:box("HomeSashGrip", V3(0.06, 0.6, 0.05), f * CF(sx * (width / 2 - 0.45), 0, 0.03), lk(214, 216, 218))
			end
			-- 방충망 (오른쪽 반, 바깥 레일)
			if self.tier ~= "penthouse" then
				local sf = faceCF(c - n * (half - 0.12), n)
				local sw, sh = width / 2 - 0.25, height - 0.6
				K:box("HomeScreenMesh", V3(sw, sh, 0.02), sf * CF(width / 4, 0, 0), { c = c3(60, 64, 68), m = M.Fabric, t = 0.62 })
				for _, sy in { -1, 1 } do
					K:box("HomeScreenFrame", V3(sw, 0.08, 0.05), sf * CF(width / 4, sy * sh / 2, 0), lk(196, 198, 200, M.Metal))
				end
				for _, sx in { -1, 1 } do
					K:box("HomeScreenFrame", V3(0.08, sh, 0.05), sf * CF(width / 4 + sx * sw / 2, 0, 0), lk(196, 198, 200, M.Metal))
				end
			end
		end)
	end
end

-------------------------------------------------------------------------------------------------
-- 가구 슬롯 덮어씌우기: 기본 가구(Default=true)를 같은 자리 · 같은 높이의 실제 가구로
--   info (analyze, F 공간: +Z = 가구 정면, -Z = 등 · 벽 쪽, y = 바닥 위 높이)
-------------------------------------------------------------------------------------------------
local SLOT: { [string]: (any, any) -> boolean? } = {}
local BACK = {
	bed = { "Headboard" }, sofa = { "SofaBack" }, desk = { "Monitor", "ModestyPanel", "MonitorArm" }, chair = { "ChairBack", "LoungeShell" },
	tv = { "TV" }, shelf = { "ShelfBack", "Bracket" }, curtain = { "CurtainRail" }, art = { "ArtFrame", "CorkFrame" },
}
-- 원래 색을 이어받은 재질
local function from(r: any?, base: any, mat: Enum.Material?): any
	if not r then
		return base
	end
	return Look.with(base, { c = r.color, m = mat or base.m })
end
local function fab(r: any?, def: Color3?): any
	return { c = (r and r.color) or def or c3(200, 196, 188), m = M.Fabric }
end

-- 둥근 쿠션 (F 공간 박스 mn..mx, 앞뒤 모서리 r 로 둥글게)
local function cushion(K: any, F: CFrame, mn: Vector3, mx: Vector3, r: number, look: any, name: string?, tilt: number?): { BasePart }
	local c = (mn + mx) / 2
	local s = mx - mn
	return K:rbox(name or "HomeCushion", V3(s.X, s.Y, s.Z), math.min(r, s.Y / 2 - 0.01, s.Z / 2 - 0.01), F * CF(c) * ANG(tilt or 0, 0, 0), look)
end
-- 옆으로 둥근 쿠션 (좌우 모서리 둥글게: 팔걸이)
local function cushionZ(K: any, F: CFrame, mn: Vector3, mx: Vector3, r: number, look: any, name: string?): { BasePart }
	local c = (mn + mx) / 2
	local s = mx - mn
	return K:rbox(name or "HomeArm", V3(s.Z, s.Y, s.X), math.min(r, s.Y / 2 - 0.01, s.X / 2 - 0.01), F * CF(c) * ANG(0, PI / 2, 0), look)
end
local function boxF(K: any, name: string, F: CFrame, mn: Vector3, mx: Vector3, look: any): BasePart
	return K:box(name, mx - mn, F * CF((mn + mx) / 2), look)
end

-- 침대 ------------------------------------------------------------------------------------------
SLOT.bed = function(C_: any, info: any): boolean?
	local K, F = C_.K, info.F
	local mat, frame, head = first(info, "Mattress"), first(info, "BedFrame"), first(info, "Headboard")
	local duvet, throw, fold = first(info, "Duvet"), first(info, "BedThrow"), first(info, "DuvetFold")
	if not (mat and frame) then
		return false
	end
	local item = tostring(info.item)
	local x0, x1, z0, z1 = frame.min.X, frame.max.X, frame.min.Z, frame.max.Z
	local mt, ft = mat.max.Y, frame.max.Y
	local hz = if head then head.max.Z else z0
	local style = if string.find(item, "goshiwon") then "drawer" elseif string.find(item, "platform") then "platform" elseif string.find(item, "king") then "wing" elseif string.find(item, "upholstered") then "uph" else "legs"
	local frameL = if frame.mat == M.Fabric then fab(frame) else from(frame, L.oak, M.Wood)
	local sheet = lk(246, 245, 240, M.Fabric)
	local duvL = fab(duvet, c3(240, 238, 232))
	local hi = K.detail ~= "low"
	-- 열린 쪽 (벽이 아닌 쪽)
	local function openSide(sx: number): boolean
		local q = (F * CF(if sx > 0 then x1 + 0.7 else x0 - 0.7, 1, (z0 + z1) / 2)).Position
		return C_:mine(V3(q.X, 0.5, q.Z)) and not C_:insideWall(q)
	end
	-- 1) 프레임
	if style == "drawer" then
		boxF(K, "HomeBedPlinth", F, V3(x0 + 0.12, 0, hz + 0.12), V3(x1 - 0.12, 0.26, z1 - 0.12), lk(34, 32, 30))
		boxF(K, "HomeBedFrame", F, V3(x0, 0.26, hz), V3(x1, ft, z1), frameL)
		for _, sx in { -1, 1 } do
			if openSide(sx) then
				local xf = if sx > 0 then x1 else x0
				local n = 2
				local len = (z1 - hz - 0.3) / n
				for i = 1, n do
					local zc = hz + 0.15 + len * (i - 0.5)
					local dcf = F * CF(xf + sx * 0.012, (0.26 + ft) / 2, zc) * ANG(0, sx * PI / 2, 0)
					K:box("HomeBedDrawer", V3(len - 0.06, ft - 0.36, 0.03), dcf, tint(frameL, -0.04))
					K:box("HomeBedDrawerPull", V3(len * 0.42, 0.06, 0.03), dcf * CF(0, (ft - 0.36) / 2 - 0.1, 0.02), lk(70, 62, 54))
				end
			end
		end
	elseif style == "platform" then
		boxF(K, "HomeBedPlinth", F, V3(x0 + 0.3, 0, hz + 0.3), V3(x1 - 0.3, 0.18, z1 - 0.3), lk(30, 30, 32))
		K:slab("HomeBedPlatform", x1 - x0, z1 - hz, ft - 0.18, 0.12, F * CF((x0 + x1) / 2, (ft + 0.18) / 2, (hz + z1) / 2), frameL)
		boxF(K, "HomeBedPlatformLED", F, V3(x0 + 0.32, 0.17, z1 - 0.34), V3(x1 - 0.32, 0.2, z1 - 0.3), L.neon(c3(255, 200, 150), 0.2))
	else
		local legH = if style == "legs" then 0.55 else 0.32
		local legL = if style == "legs" then tint(frameL, 0.08) else lk(40, 38, 36, M.Metal)
		for _, sx in { -1, 1 } do
			for _, zz in { hz + 0.25, z1 - 0.25 } do
				local x = if sx > 0 then x1 - 0.25 else x0 + 0.25
				if style == "legs" then
					K:box("HomeBedLeg", V3(0.2, legH, 0.2), F * CF(x, legH / 2, zz), legL)
				else
					K:vcyl("HomeBedLeg", legH, 0.14, F * CF(x, legH / 2, zz), legL)
				end
			end
		end
		if style == "legs" then
			-- 원목 사이드 레일 + 발판
			for _, sx in { -1, 1 } do
				local x = if sx > 0 then x1 - 0.09 else x0 + 0.09
				boxF(K, "HomeBedRail", F, V3(x - 0.09, legH, hz), V3(x + 0.09, ft, z1), frameL)
			end
			boxF(K, "HomeBedFootRail", F, V3(x0, legH, z1 - 0.18), V3(x1, ft + 0.08, z1), frameL)
			boxF(K, "HomeBedSlatBase", F, V3(x0 + 0.18, legH + 0.1, hz), V3(x1 - 0.18, ft - 0.1, z1 - 0.18), lk(60, 52, 44))
		else
			K:slab("HomeBedFrame", x1 - x0, z1 - hz, ft - legH, 0.18, F * CF((x0 + x1) / 2, (ft + legH) / 2, (hz + z1) / 2), frameL)
			if hi then
				K:slab("HomeBedFrameWelt", x1 - x0 + 0.02, z1 - hz + 0.02, 0.03, 0.19, F * CF((x0 + x1) / 2, ft - 0.03, (hz + z1) / 2), tint(frameL, 0.12))
			end
		end
	end
	-- 2) 매트리스 (+ 퀼팅 띠) · 침대 시트
	local mx0, mx1 = x0 + (if style == "legs" then 0.1 else 0.06), x1 - (if style == "legs" then 0.1 else 0.06)
	local mz0, mz1 = hz + 0.04, z1 - (if style == "legs" then 0.2 else 0.08)
	local mb = ft - 0.1
	K:slab("HomeMattress", mx1 - mx0, mz1 - mz0, mt - mb, 0.2, F * CF((mx0 + mx1) / 2, (mt + mb) / 2, (mz0 + mz1) / 2), sheet)
	if hi then
		K:slab("HomeMattressBand", mx1 - mx0 + 0.02, mz1 - mz0 + 0.02, 0.05, 0.21, F * CF((mx0 + mx1) / 2, mb + 0.1, (mz0 + mz1) / 2), lk(214, 212, 206, M.Fabric))
	end
	-- 3) 이불 (윗판 + 옆으로 늘어진 자락 + 발치 자락) · 접힌 끝단
	local dz0 = if duvet then math.max(duvet.min.Z, mz0 + 1.2) else mz0 + 1.8
	local dtop = if duvet then math.min(duvet.max.Y, mt + 0.3) else mt + 0.22
	local dw = (mx1 - mx0) + 0.18
	local dcx = (mx0 + mx1) / 2
	local dlen = (z1 + 0.04) - dz0
	K:slab("HomeDuvet", dw, dlen, 0.24, 0.12, F * CF(dcx, dtop - 0.12, dz0 + dlen / 2), duvL)
	local drop = math.max(0.35, dtop - ft + 0.05)
	for _, sx in { -1, 1 } do
		if openSide(sx) or style ~= "drawer" then
			local x = dcx + sx * (dw / 2 - 0.035)
			K:box("HomeDuvetSide", V3(0.07, drop, dlen - 0.1), F * CF(x, dtop - drop / 2 - 0.04, dz0 + dlen / 2), duvL)
			K:cyl("HomeDuvetRoll", dlen - 0.12, 0.2, F * CF(x - sx * 0.05, dtop - 0.12, dz0 + dlen / 2) * ANG(0, PI / 2, 0), duvL)
		end
	end
	K:box("HomeDuvetFoot", V3(dw - 0.1, drop, 0.07), F * CF(dcx, dtop - drop / 2 - 0.04, z1 + 0.04), duvL)
	K:cyl("HomeDuvetFold", dw - 0.04, 0.26, F * CF(dcx, dtop - 0.1, dz0 + 0.05), from(fold, sheet, M.Fabric))
	-- 4) 무릎 담요 (발치에 걸쳐서)
	if throw then
		local tz = math.clamp(throw.c.Z, dz0 + 0.8, z1 - 0.7)
		local tl = fab(throw)
		K:box("HomeThrow", V3(dw + 0.04, 0.07, 1.15), F * CF(dcx, dtop + 0.03, tz) * ANG(0, 0.03, 0), tl)
		for _, sx in { -1, 1 } do
			if openSide(sx) or style ~= "drawer" then
				K:box("HomeThrowDrop", V3(0.06, drop * 0.9, 1.1), F * CF(dcx + sx * (dw / 2 + 0.03), dtop - drop * 0.45, tz), tl)
			end
		end
		if hi then
			K:box("HomeThrowStripe", V3(dw + 0.06, 0.075, 0.08), F * CF(dcx, dtop + 0.032, tz - 0.4), tint(tl, 0.25))
			K:box("HomeThrowStripe", V3(dw + 0.06, 0.075, 0.08), F * CF(dcx, dtop + 0.032, tz + 0.4), tint(tl, 0.25))
		end
	end
	-- 5) 베개 (원래 자리) + 고급 등급 장식 쿠션
	local pillows = all(info, "Pillow")
	for i, p in pillows do
		local pw = math.min(p.size.X, (mx1 - mx0) / math.max(1, #pillows) - 0.1)
		local pd = math.min(p.size.Z, 1.25)
		local py = mt + 0.22
		K:ell("HomePillow", V3(pw, 0.44, pd), F * CF(p.c.X, py, math.max(p.c.Z, hz + pd / 2 + 0.05)) * ANG(math.rad(-6), (i - 1.5) * 0.06, 0), sheet)
		if hi then
			K:ell("HomePillowSeam", V3(pw + 0.04, 0.06, pd + 0.04), F * CF(p.c.X, py, math.max(p.c.Z, hz + pd / 2 + 0.05)) * ANG(math.rad(-6), (i - 1.5) * 0.06, 0), lk(232, 230, 224, M.Fabric))
		end
	end
	if C_.lux >= 4 and #pillows >= 2 then
		local cz = hz + 0.45
		K:rbox("HomeEuroSham", V3(math.min(2.2, (mx1 - mx0) * 0.42), 1.5, 0.35), 0.15, F * CF(dcx - (mx1 - mx0) * 0.24, mt + 0.75, cz) * ANG(math.rad(-12), 0, 0), tint(duvL, 0.08))
		K:rbox("HomeEuroSham", V3(math.min(2.2, (mx1 - mx0) * 0.42), 1.5, 0.35), 0.15, F * CF(dcx + (mx1 - mx0) * 0.24, mt + 0.75, cz) * ANG(math.rad(-12), 0, 0), tint(duvL, 0.08))
		K:rbox("HomeCushionAccent", V3(1.2, 0.8, 0.3), 0.12, F * CF(dcx, mt + 0.48, hz + 1.25) * ANG(math.rad(-18), 0, 0), if throw then fab(throw) else lk(150, 120, 90, M.Fabric))
	end
	-- 6) 헤드보드
	if head then
		local hx0, hx1, hy0, hy1, hz0, hz1 = head.min.X, head.max.X, head.min.Y, head.max.Y, head.min.Z, head.max.Z
		local hL = if head.mat == M.Fabric then fab(head) else from(head, L.oak, M.Wood)
		local hw = hx1 - hx0
		if style == "uph" or style == "wing" then
			local n = math.max(4, math.floor(hw / 0.55))
			local cw = hw / n
			boxF(K, "HomeHeadboardBack", F, V3(hx0, math.max(hy0, 0.3), hz0), V3(hx1, hy1, hz0 + 0.12), tint(hL, 0.1))
			for i = 1, n do
				local x = hx0 + cw * (i - 0.5)
				K:rbox("HomeHeadboardChannel", V3(hy1 - math.max(hy0, 0.3) - 0.1, cw - 0.03, 0.24), 0.11, F * CF(x, (hy1 + math.max(hy0, 0.3)) / 2, hz0 + 0.18) * ANG(0, 0, PI / 2), hL)
			end
			K:cyl("HomeHeadboardTop", hw, 0.3, F * CF((hx0 + hx1) / 2, hy1 - 0.1, hz0 + 0.16), hL)
			if style == "wing" then
				for _, sx in { -1, 1 } do
					local x = if sx > 0 then hx1 + 0.05 else hx0 - 0.05
					K:rbox("HomeHeadboardWing", V3(0.3, hy1 - 0.4, 0.9), 0.12, F * CF(x, (hy1 + 0.4) / 2, hz0 + 0.4) * ANG(0, sx * 0.25, 0), hL)
				end
			end
		elseif style == "platform" then
			boxF(K, "HomeHeadboard", F, V3(hx0, ft, hz0), V3(hx1, hy1, hz1), tint(hL, 0.05))
			local n = 3
			for i = 1, n do
				local x = hx0 + hw * (i - 0.5) / n
				K:rbox("HomeHeadboardPad", V3(hw / n - 0.08, hy1 - ft - 0.25, 0.16), 0.08, F * CF(x, (hy1 + ft) / 2, hz1 + 0.06), hL)
			end
		else
			boxF(K, "HomeHeadboard", F, V3(hx0, hy0, hz0), V3(hx1, hy1 - 0.12, hz1), hL)
			K:cyl("HomeHeadboardCap", hw, hz1 - hz0 + 0.04, F * CF((hx0 + hx1) / 2, hy1 - 0.12, (hz0 + hz1) / 2), hL)
			if hi then
				for _, sx in { -1, 1 } do
					K:box("HomeHeadboardInset", V3(hw / 2 - 0.35, (hy1 - hy0) * 0.42, 0.02), F * CF((hx0 + hx1) / 2 + sx * hw / 4, hy0 + (hy1 - hy0) * 0.62, hz1 + 0.006), tint(hL, 0.07))
				end
			end
		end
	end
	return true
end

-- 소파 ------------------------------------------------------------------------------------------
SLOT.sofa = function(C_: any, info: any): boolean?
	local K, F = C_.K, info.F
	local base, back = first(info, "SofaBase"), first(info, "SofaBack")
	if not base then
		return false
	end
	local item = tostring(info.item)
	local boucle = string.find(item, "boucle") ~= nil
	local fl = fab(base)
	if boucle then
		fl = { c = base.color, m = M.Fabric }
	end
	local seats = all(info, "SeatCushion", "Seat")
	local arms = all(info, "SofaArm")
	local backs = all(info, "BackCushion")
	local legs = all(info, "SofaLeg")
	local pillows = all(info, "ThrowPillow")
	local chaise = first(info, "Chaise")
	local x0, x1, z0, z1 = base.min.X, base.max.X, base.min.Z, base.max.Z
	local legH = base.min.Y
	local seatTop = base.max.Y + 0.4
	for _, s in seats do
		seatTop = math.max(seatTop, s.max.Y)
	end
	if seatTop > base.max.Y + 0.9 then
		seatTop = base.max.Y + 0.5
	end
	local hi = K.detail ~= "low"
	-- 프레임 (좌판 받침)
	K:rbox("HomeSofaBase", V3(x1 - x0, base.max.Y - legH, z1 - z0), if boucle then 0.22 else 0.08, F * CF((x0 + x1) / 2, (base.max.Y + legH) / 2, (z0 + z1) / 2), fl)
	if boucle then
		boxF(K, "HomeSofaPlinth", F, V3(x0 + 0.25, 0, z0 + 0.25), V3(x1 - 0.25, legH + 0.02, z1 - 0.25), lk(36, 34, 32))
	end
	-- 등받이 프레임
	if back then
		local by1 = back.max.Y
		K:rbox("HomeSofaBack", V3(back.size.X, by1 - back.min.Y - 0.08, back.size.Z), if boucle then 0.3 else 0.12, F * CF(back.c.X, (by1 + back.min.Y - 0.08) / 2, back.c.Z), fl)
		if boucle then
			K:cyl("HomeSofaBackRoll", back.size.X - 0.1, back.size.Z + 0.1, F * CF(back.c.X, by1 - 0.2, back.c.Z), fl)
		end
	end
	-- 좌석 쿠션 (사이 틈 + 파이핑)
	local seatFront = z1
	for _, s in seats do
		local mn = V3(s.min.X + 0.03, base.max.Y - 0.02, s.min.Z)
		local mx = V3(s.max.X - 0.03, seatTop, math.min(z1 + 0.04, s.max.Z + 0.04))
		cushion(K, F, mn, mx, if boucle then 0.22 else 0.12, fl, "HomeSofaSeat")
		if hi and not boucle then
			K:cyl("HomeSofaPiping", (mx.X - mn.X) - 0.08, 0.05, F * CF((mn.X + mx.X) / 2, mx.Y - 0.1, mx.Z - 0.04), tint(fl, 0.15))
		end
		seatFront = math.max(seatFront, mx.Z)
	end
	if chaise then
		local mn = V3(chaise.min.X + 0.03, legH, chaise.min.Z)
		local mx = V3(chaise.max.X - 0.03, chaise.max.Y, chaise.max.Z)
		cushion(K, F, mn, mx, 0.16, fl, "HomeSofaChaise")
		for _, sx in { mn.X + 0.2, mx.X - 0.2 } do
			K:box("HomeSofaLeg", V3(0.14, legH, 0.14), F * CF(sx, legH / 2, mx.Z - 0.25), lk(60, 44, 32, M.Wood))
		end
	end
	-- 등 쿠션 (뒤로 10도)
	for i, b in backs do
		local mn = V3(b.min.X + 0.04, seatTop - 0.05, b.min.Z - 0.05)
		local mx = V3(b.max.X - 0.04, b.max.Y + 0.15, b.max.Z + 0.08)
		cushion(K, F, mn, mx, 0.2, fl, "HomeSofaBackCushion", math.rad(-9))
		local _ = i
	end
	-- 팔걸이
	for _, a in arms do
		local mn = V3(a.min.X, legH, a.min.Z)
		local mx = V3(a.max.X, a.max.Y, a.max.Z)
		cushionZ(K, F, mn, mx, if boucle then 0.28 else 0.16, fl, "HomeSofaArm")
		if hi and not boucle then
			-- 팔걸이 앞면 테두리 (파이핑): 앞면 위 모서리를 따라 가로로
			K:cyl("HomeSofaArmPiping", (mx.X - mn.X) - 0.2, 0.05, F * CF((mn.X + mx.X) / 2, mx.Y - 0.1, mx.Z + 0.01), tint(fl, 0.15))
		end
	end
	-- 다리
	if not boucle then
		local legL = if #legs > 0 and legs[1].mat == M.Wood then from(legs[1], L.walnut, M.Wood) else lk(40, 40, 42, M.Metal)
		for _, l in legs do
			K:seg("HomeSofaLeg", F * V3(l.c.X, legH, l.c.Z), F * V3(l.c.X + (if l.c.X > (x0 + x1) / 2 then 0.06 else -0.06), 0.02, l.c.Z + (if l.c.Z > (z0 + z1) / 2 then 0.05 else -0.05)), 0.14, legL)
			K:disc("HomeSofaGlide", 0.12, 0.02, F * CF(l.c.X, 0.01, l.c.Z), L.rubber)
		end
	end
	-- 쿠션 (모서리 둥글고 가운데 오목: 두 겹)
	for i, p in pillows do
		local pl = fab(p)
		local w = math.min(1.35, p.size.X)
		local cfp = F * CF(p.c.X, seatTop + 0.62, math.max(p.c.Z, (back and back.max.Z or z0) + 0.32)) * ANG(math.rad(-14), (i % 2 == 0) and 0.18 or -0.18, (i % 2 == 0) and 0.08 or -0.08)
		K:rbox("HomeThrowPillow", V3(w, 1.15, 0.34), 0.16, cfp, pl)
		if hi then
			K:rbox("HomeThrowPillowFace", V3(w - 0.3, 0.85, 0.38), 0.14, cfp, tint(pl, -0.04))
		end
	end
	-- 거실 쿠션 위 니트 블랭킷 (고급 등급 · 팔걸이 위)
	if C_.lux >= 3 and #arms > 0 and hi then
		local a = arms[1]
		local bl = if C_.lux >= 5 then lk(196, 182, 160, M.Fabric) else lk(176, 168, 156, M.Fabric)
		K:box("HomeSofaBlanket", V3(a.size.X + 0.25, 0.08, 1.2), F * CF(a.c.X, a.max.Y + 0.04, a.c.Z + 0.3), bl)
		K:box("HomeSofaBlanketDrop", V3(0.07, 1.0, 1.1), F * CF(a.c.X + (if a.c.X > 0 then 1 else -1) * (a.size.X / 2 + 0.12), a.max.Y - 0.5, a.c.Z + 0.3), bl)
	end
	return true
end

-- 의자 ------------------------------------------------------------------------------------------
-- 사무용 의자 (pcf: 바닥, +Z = 앉은 사람이 보는 쪽), top = 좌판 윗면
local function officeChair(C_: any, pcf: CFrame, top: number, o: any)
	local K = C_.K
	local frame = o.frame or lk(36, 36, 40)
	local seatL = o.seat or lk(50, 52, 58, M.Fabric)
	local mesh = o.mesh
	local leather = o.leather
	local hi = K.detail ~= "low"
	-- 5발 받침 + 바퀴
	K:vcyl("HomeChairHub", 0.18, 0.34, pcf * CF(0, 0.33, 0), frame)
	for i = 0, 4 do
		local a = i * 2 * PI / 5 + PI / 2
		local tip = pcf * V3(math.cos(a) * 0.95, 0.24, math.sin(a) * 0.95)
		K:seg("HomeChairStar", pcf * V3(0, 0.32, 0), tip, 0.12, frame)
		if hi then
			K:ball("HomeChairCaster", 0.2, CF(tip - V3(0, 0.14, 0)), lk(30, 30, 32))
			K:box("HomeChairCasterFork", V3(0.08, 0.1, 0.12), CF(tip - V3(0, 0.04, 0)), frame)
		end
	end
	K:vcyl("HomeChairGasLift", top - 0.75, 0.16, pcf * CF(0, 0.33 + (top - 0.75) / 2, 0), L.chrome)
	K:vcyl("HomeChairGasCover", 0.5, 0.22, pcf * CF(0, 0.6, 0), frame)
	K:box("HomeChairMech", V3(0.7, 0.16, 0.6), pcf * CF(0, top - 0.36, 0), frame)
	if hi then
		K:box("HomeChairLever", V3(0.45, 0.04, 0.05), pcf * CF(0.45, top - 0.38, 0.2), frame)
		K:ball("HomeChairLeverKnob", 0.08, pcf * CF(0.68, top - 0.38, 0.2), frame)
	end
	-- 좌판
	K:slab("HomeChairSeat", 1.65, 1.6, 0.26, 0.28, pcf * CF(0, top - 0.13, 0.02), seatL)
	K:cyl("HomeChairSeatFront", 1.5, 0.22, pcf * CF(0, top - 0.12, 0.78), seatL)
	-- 등받이 (메쉬 프레임 / 가죽)
	local bcf = pcf * CF(0, top + 0.1, -0.78) * ANG(math.rad(-10), 0, 0)
	K:box("HomeChairSpine", V3(0.2, 0.9, 0.12), pcf * CF(0, top - 0.2, -0.78) * ANG(math.rad(-25), 0, 0), frame)
	if leather then
		K:rbox("HomeChairBack", V3(1.55, 2.1, 0.3), 0.14, bcf * CF(0, 1.05, 0), seatL)
		if hi then
			for i = 1, 3 do
				K:box("HomeChairBackStitch", V3(1.35, 0.025, 0.02), bcf * CF(0, 0.45 + i * 0.42, 0.16), tint(seatL, 0.25))
			end
			K:rbox("HomeChairHead", V3(1.1, 0.5, 0.32), 0.14, bcf * CF(0, 2.3, 0.02), seatL)
		end
	else
		K:panel("HomeChairBackFrame", 1.5, 1.95, 0.08, 0.3, bcf * CF(0, 1.05, -0.04), frame)
		K:panel("HomeChairBackMesh", 1.36, 1.8, 0.03, 0.25, bcf * CF(0, 1.05, 0.04), mesh or { c = c3(40, 42, 48), m = M.Fabric, t = 0.25 })
		if hi then
			K:box("HomeChairLumbar", V3(1.2, 0.28, 0.08), bcf * CF(0, 0.55, 0.09), frame)
		end
	end
	-- 팔걸이
	for _, sx in { -1, 1 } do
		K:box("HomeChairArmPost", V3(0.1, 0.75, 0.14), pcf * CF(sx * 0.9, top + 0.12, -0.05), frame)
		K:rbox("HomeChairArmPad", V3(0.22, 0.1, 0.85), 0.04, pcf * CF(sx * 0.9, top + 0.52, 0.02), lk(30, 30, 32))
	end
end
T.officeChair = officeChair

-- 라운지 체어 (월넛 셸 + 가죽 쿠션 + 회전 받침)
local function loungeChair(C_: any, pcf: CFrame, top: number, o: any)
	local K = C_.K
	local shell = o.shell or L.walnut
	local cushionL = o.cushion or L.leatherBlack
	K:disc("HomeLoungeBase", 1.6, 0.06, pcf * CF(0, 0.05, 0), lk(30, 30, 32, M.Metal))
	for i = 0, 4 do
		local a = i * 2 * PI / 5
		K:seg("HomeLoungeFoot", pcf * V3(0, 0.14, 0), pcf * V3(math.cos(a) * 0.85, 0.05, math.sin(a) * 0.85), 0.12, lk(30, 30, 32, M.Metal))
	end
	K:vcyl("HomeLoungeStem", top - 0.75, 0.18, pcf * CF(0, 0.14 + (top - 0.75) / 2, 0), lk(30, 30, 32, M.Metal))
	-- 좌판 셸 + 쿠션
	K:slab("HomeLoungeSeatShell", 2.1, 2.0, 0.14, 0.4, pcf * CF(0, top - 0.42, 0.05) * ANG(math.rad(-6), 0, 0), shell)
	K:slab("HomeLoungeSeatCushion", 1.95, 1.85, 0.3, 0.35, pcf * CF(0, top - 0.17, 0.05) * ANG(math.rad(-6), 0, 0), cushionL)
	-- 등 (두 단) + 팔걸이
	local bcf = pcf * CF(0, top - 0.2, -0.95) * ANG(math.rad(-16), 0, 0)
	K:panel("HomeLoungeBackShell", 2.1, 1.5, 0.12, 0.4, bcf * CF(0, 0.75, -0.14), shell)
	K:rbox("HomeLoungeBackCushion", V3(1.9, 1.35, 0.28), 0.14, bcf * CF(0, 0.75, 0.04), cushionL)
	K:panel("HomeLoungeHeadShell", 1.8, 0.9, 0.12, 0.35, bcf * CF(0, 1.95, -0.14), shell)
	K:rbox("HomeLoungeHeadCushion", V3(1.6, 0.75, 0.26), 0.12, bcf * CF(0, 1.95, 0.04), cushionL)
	for _, sx in { -1, 1 } do
		K:rbox("HomeLoungeArm", V3(0.3, 0.16, 1.4), 0.07, pcf * CF(sx * 1.0, top + 0.45, -0.05) * ANG(math.rad(-4), 0, 0), cushionL)
		K:box("HomeLoungeArmPost", V3(0.08, 0.5, 0.1), pcf * CF(sx * 1.0, top + 0.18, -0.15), lk(30, 30, 32, M.Metal))
	end
end

SLOT.chair = function(C_: any, info: any): boolean?
	local seat = first(info, "Seat")
	local item = tostring(info.item)
	local K, F = C_.K, info.F
	if string.find(item, "lounge") then
		local cushionR = first(info, "LoungeSeat", "LoungeCushion", "Cushion")
		local top = if seat then seat.max.Y elseif cushionR then cushionR.max.Y else 1.9
		local c = if seat then V3(seat.c.X, 0, seat.c.Z) else V3((info.min.X + info.max.X) / 2, 0, (info.min.Z + info.max.Z) / 2)
		loungeChair(C_, F * CF(c), top, { shell = L.walnut, cushion = if cushionR then from(cushionR, L.leatherBlack, M.Leather) else L.leatherBlack })
		return true
	end
	if not seat then
		return false
	end
	local top = seat.max.Y
	local seatL = from(seat, lk(50, 52, 58), if string.find(item, "leather") then M.Leather else M.Fabric)
	officeChair(C_, F * CF(seat.c.X, 0, seat.c.Z), top, {
		seat = seatL,
		leather = string.find(item, "leather") ~= nil,
		frame = if string.find(item, "study") then lk(40, 40, 44) else lk(32, 32, 36),
		mesh = { c = seatL.c, m = M.Fabric, t = 0.2 },
	})
	return true
end

-- 테이블 세트 · 테이블 ------------------------------------------------------------------------------
-- 테이블 세트 안의 의자 (Seat + ChairBack): 같은 좌판 높이 · 방향
local function setChairs(C_: any, info: any, style: string, o: any)
	local K, F = C_.K, info.F
	local backs = all(info, "ChairBack")
	for _, s in all(info, "Seat") do
		local best, bd = nil, 2.2
		for _, b in backs do
			local d = (V3(b.c.X, 0, b.c.Z) - V3(s.c.X, 0, s.c.Z)).Magnitude
			if d < bd then
				best, bd = b, d
			end
		end
		local top = s.max.Y
		local c = V3(s.c.X, 0, s.c.Z)
		if style == "bar" then
			-- 바 스툴 (원판 좌석, 위아래로 세운 원통 파트)
			Props.stool(K, F * CF(c), { seatTop = top, dia = math.max(s.size.X, s.size.Z, 1.2), style = "bar", frame = o.stoolFrame or L.blackMetal, seat = o.stoolSeat or from(s, L.leatherCream, M.Leather) })
			continue
		end
		local face = V3(0, 0, 1)
		if best then
			local d = V3(s.c.X - best.c.X, 0, s.c.Z - best.c.Z)
			if d.Magnitude > 0.05 then
				face = d.Unit
			end
		end
		local pcf = F * CFrame.lookAt(c, c - face)
		local w = math.clamp(math.min(s.size.X, s.size.Z) + 0.05, 1.3, 1.8)
		local backH = if best then math.clamp(best.max.Y - top, 1.2, 2.6) else 1.8
		Props.chair(K, pcf, { seatTop = top, w = w, d = w, backH = backH, style = style, frame = o.frame, seat = o.seat or from(s, L.fabricBeige, M.Fabric), back = o.back, detail = if K.detail == "high" then nil else K.detail })
	end
end

local function roundTop(K: any, F: CFrame, c: Vector3, dia: number, y: number, th: number, look: any, name: string?)
	K:disc(name or "HomeTableTop", dia, th, F * CF(c.X, y - th / 2, c.Z), look)
	K:disc("HomeTableTopEdge", dia - 0.04, 0.03, F * CF(c.X, y - th - 0.015, c.Z), tint(look, 0.15))
end

SLOT.table = function(C_: any, info: any): boolean?
	local K, F = C_.K, info.F
	local item = tostring(info.item)
	local tops = all(info, "TableTop", "BarTableTop")
	if #tops == 0 then
		return false
	end
	local hi = K.detail ~= "low"
	for _, t in tops do
		local y = t.max.Y
		local c = t.c
		local round = t.part:IsA("Part") and (t.part :: Part).Shape == Enum.PartType.Cylinder
		local topL
		if t.mat == M.Marble then
			topL = from(t, L.marbleWhite, M.Marble)
		elseif t.mat == M.Limestone then
			topL = { c = t.color, m = M.Limestone }
		elseif t.mat == M.Slate then
			topL = { c = t.color, m = M.Slate }
		else
			topL = from(t, L.oak, M.Wood)
		end
		if round then
			local dia = math.max(t.size.X, t.size.Z)
			roundTop(K, F, c, dia, y, 0.12, topL)
			if string.find(item, "travertine") then
				-- 트래버틴 원통 받침 (통짜 돌) + 홈 줄
				local baseD = dia * 0.5
				K:vcyl("HomeTableDrum", y - 0.14, baseD, F * CF(c.X, (y - 0.14) / 2, c.Z), topL)
				if hi then
					for i = 1, 3 do
						K:vcyl("HomeTableDrumGroove", 0.03, baseD + 0.02, F * CF(c.X, (y - 0.14) * i / 4, c.Z), tint(topL, 0.12))
					end
				end
			elseif string.find(item, "cafe") then
				-- 비스트로: 주물 받침 + 기둥
				K:vcyl("HomeTableColumn", y - 0.3, 0.2, F * CF(c.X, (y - 0.3) / 2 + 0.1, c.Z), L.blackMetal)
				for i = 0, 3 do
					local a = i * PI / 2 + PI / 4
					K:seg("HomeTableFoot", F * V3(c.X, 0.12, c.Z), F * V3(c.X + math.cos(a) * 0.85, 0.04, c.Z + math.sin(a) * 0.85), 0.12, L.blackMetal)
				end
				K:disc("HomeTableHub", 0.5, 0.1, F * CF(c.X, y - 0.2, c.Z), L.blackMetal)
			else
				-- 튤립 받침 (원판 + 원뿔 기둥)
				local baseD = math.min(dia * 0.6, 1.5)
				K:disc("HomeTableFoot", baseD, 0.08, F * CF(c.X, 0.04, c.Z), lk(30, 30, 32, M.Metal))
				local n = 5
				for i = 1, n do
					local yy = 0.08 + (y - 0.2) * (i - 0.5) / n
					local d = 0.18 + 0.18 * math.abs(i - n / 2 - 0.5) / n
					K:vcyl("HomeTableStem", (y - 0.2) / n + 0.01, d, F * CF(c.X, yy, c.Z), lk(30, 30, 32, M.Metal))
				end
			end
		else
			local w, l = t.size.X, t.size.Z
			local th = if y > 2 then 0.14 else 0.12
			K:slab("HomeTableTop", w, l, th, 0.08, F * CF(c.X, y - th / 2, c.Z), topL)
			if hi then
				K:slab("HomeTableTopEdge", w - 0.06, l - 0.06, 0.04, 0.08, F * CF(c.X, y - th - 0.02, c.Z), tint(topL, 0.18))
			end
			local legL = lk(30, 30, 32, M.Metal)
			local tlegs = all(info, "TableLeg")
			local shelf = first(info, "TableShelf")
			if string.find(item, "bartable") then
				local leg = first(info, "BarTableLeg")
				K:box("HomeBarTableColumn", V3(0.24, y - 0.3, 0.6), F * CF(c.X, (y - 0.3) / 2 + 0.1, c.Z), legL)
				K:slab("HomeBarTableFoot", 2.2, 1.3, 0.08, 0.2, F * CF(c.X, 0.04, c.Z), legL)
				K:box("HomeBarTableBrace", V3(1.2, 0.08, 0.5), F * CF(c.X, y - 0.22, c.Z), legL)
				local _ = leg
			elseif #tlegs >= 2 and tlegs[1].size.Z > 1.2 or (#tlegs >= 2 and tlegs[1].size.X > 1.2) then
				-- 판 다리 (썰매형 철제 프레임)
				for _, lg in tlegs do
					local alongZ = lg.size.Z >= lg.size.X
					local ll = if alongZ then lg.size.Z else lg.size.X
					local x, z = lg.c.X, lg.c.Z
					for _, sgn in { -1, 1 } do
						local off = sgn * (ll / 2 - 0.08)
						local px, pz = if alongZ then x else x + off, if alongZ then z + off else z
						K:box("HomeTableLegPost", V3(0.14, y - th, 0.14), F * CF(px, (y - th) / 2, pz), legL)
					end
					K:box("HomeTableLegBar", if alongZ then V3(0.14, 0.14, ll) else V3(ll, 0.14, 0.14), F * CF(x, 0.07, z), legL)
					K:box("HomeTableLegBar", if alongZ then V3(0.12, 0.12, ll) else V3(ll, 0.12, 0.12), F * CF(x, y - th - 0.06, z), legL)
				end
			else
				local woodLeg = from(t, L.oak, M.Wood)
				local useWood = t.mat == M.Wood and not shelf
				local lgL = if useWood then tint(woodLeg, 0.05) else legL
				for _, sx in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local px, pz = c.X + sx * (w / 2 - 0.22), c.Z + sz * (l / 2 - 0.22)
						if useWood then
							K:seg("HomeTableLeg", F * V3(px, y - th, pz), F * V3(px + sx * 0.08, 0.02, pz + sz * 0.08), 0.18, lgL)
						else
							K:box("HomeTableLeg", V3(0.12, y - th, 0.12), F * CF(px, (y - th) / 2, pz), lgL)
						end
					end
				end
				if shelf then
					K:slab("HomeTableShelf", shelf.size.X, shelf.size.Z, 0.08, 0.06, F * CF(shelf.c.X, shelf.c.Y, shelf.c.Z), topL)
					-- 아래 칸 잡지 · 리모컨 바구니
					if hi then
						K:box("HomeMagazine", V3(0.9, 0.04, 1.2), F * CF(shelf.c.X - 0.8, shelf.max.Y + 0.02, shelf.c.Z) * ANG(0, 0.15, 0), lk(220, 214, 200))
						K:box("HomeMagazine", V3(0.85, 0.04, 1.15), F * CF(shelf.c.X - 0.75, shelf.max.Y + 0.06, shelf.c.Z) * ANG(0, -0.1, 0), lk(60, 90, 120))
						K:rbox("HomeBasket", V3(1.0, 0.45, 0.8), 0.08, F * CF(shelf.c.X + 0.8, shelf.max.Y + 0.23, shelf.c.Z), L.rattan)
					end
				end
			end
		end
	end
	-- 세트 의자
	if #all(info, "Seat") > 0 then
		if string.find(item, "cafe") then
			setChairs(C_, info, "bentwood", { frame = lk(150, 118, 84, M.Wood), seat = lk(150, 118, 84, M.Wood) })
		elseif string.find(item, "bartable") then
			setChairs(C_, info, "bar", { stoolFrame = L.blackMetal })
		elseif string.find(item, "marble") then
			setChairs(C_, info, "padded", { frame = L.walnut, seat = lk(206, 196, 180, M.Leather), back = lk(206, 196, 180, M.Leather) })
		else
			setChairs(C_, info, "padded", { frame = lk(176, 140, 100, M.Wood), seat = lk(214, 206, 190, M.Fabric) })
		end
	end
	return true
end

-- 책상 ------------------------------------------------------------------------------------------
-- 모니터 (pcf = 받침 바닥, +Z = 화면 쪽). 반환: 화면 파트, 화면 글자
local function monitor(C_: any, pcf: CFrame, sw: number, sh: number, o: any?): (BasePart, TextLabel?)
	local K = C_.K
	local oo: any = o or {}
	local body = oo.body or lk(28, 28, 30)
	K:slab("HomeMonitorFoot", 0.9, 0.55, 0.05, 0.12, pcf * CF(0, 0.025, -0.05), body)
	K:box("HomeMonitorNeck", V3(0.12, sh * 0.55 + 0.3, 0.08), pcf * CF(0, 0.05 + (sh * 0.55 + 0.3) / 2, -0.2), body)
	local scf = pcf * CF(0, 0.35 + sh / 2 + 0.05, -0.12) * ANG(math.rad(-4), 0, 0)
	K:box("HomeMonitorBack", V3(sw * 0.5, sh * 0.5, 0.12), scf * CF(0, 0, -0.1), body)
	K:box("HomeMonitorBezel", V3(sw + 0.06, sh + 0.06, 0.05), scf, body)
	local scr = K:box("HomeMonitorScreen", V3(sw, sh, 0.01), scf * CF(0, 0, 0.03), L.screen(c3(16, 20, 28)))
	local label = nil
	if oo.text then
		local _, t = K:text("HomeMonitorText", sw * 0.92, sh * 0.86, scf * CF(0, 0, 0.036), oo.text, { fg = oo.fg or c3(200, 230, 255), bg = oo.bg or c3(24, 34, 52), glow = 1.1, font = Enum.Font.Code, wrap = true, align = "Left" })
		label = t
	end
	K:box("HomeMonitorLED", V3(0.04, 0.02, 0.01), scf * CF(sw / 2 - 0.12, -sh / 2 - 0.015, 0.03), L.neon(c3(255, 255, 255)))
	return scr, label
end
T.monitor = monitor

local function keyboard(K: any, pcf: CFrame, look: any?)
	local kl = look or lk(38, 38, 42)
	K:box("HomeKeyboard", V3(1.5, 0.05, 0.48), pcf * CF(0, 0.025, 0) * ANG(math.rad(3), 0, 0), kl)
	if K.detail == "high" then
		for i = 0, 3 do
			K:box("HomeKeyRow", V3(1.38, 0.02, 0.07), pcf * CF(0, 0.06 + i * 0.004, -0.16 + i * 0.105) * ANG(math.rad(3), 0, 0), lk(60, 60, 66))
		end
		K:box("HomeKeySpace", V3(0.6, 0.02, 0.06), pcf * CF(-0.1, 0.07, 0.2), lk(60, 60, 66))
	end
end
local function mouse(K: any, pcf: CFrame)
	K:box("HomeMousePad", V3(0.9, 0.02, 0.75), pcf * CF(0, 0.01, 0), lk(44, 46, 52, M.Fabric))
	K:ell("HomeMouse", V3(0.2, 0.09, 0.32), pcf * CF(0, 0.06, 0), lk(30, 30, 34))
end
local function mug(K: any, pcf: CFrame, look: any?)
	local ml = look or lk(240, 238, 232)
	K:vcyl("HomeMug", 0.34, 0.28, pcf * CF(0, 0.17, 0), ml)
	K:vcyl("HomeMugCoffee", 0.02, 0.24, pcf * CF(0, 0.3, 0), lk(70, 44, 30))
	K:ring("HomeMugHandle", pcf * CF(0.17, 0.18, 0) * ANG(0, 0, 0), 0.08, 0.04, 5, ml, -PI / 2, PI / 2)
end
local function penCup(K: any, pcf: CFrame)
	K:vcyl("HomePenCup", 0.4, 0.26, pcf * CF(0, 0.2, 0), lk(60, 62, 66, M.Metal))
	local cols = { c3(30, 60, 160), c3(200, 40, 40), c3(30, 30, 30), c3(240, 200, 40) }
	for i = 1, 4 do
		local a = i * 1.6
		K:seg("HomePen", pcf * V3(math.cos(a) * 0.05, 0.25, math.sin(a) * 0.05), pcf * V3(math.cos(a) * 0.1, 0.72, math.sin(a) * 0.1), 0.04, { c = cols[i], m = M.SmoothPlastic })
	end
end
local function phone(K: any, pcf: CFrame, up: boolean?)
	K:slab("HomePhone", 0.3, 0.6, 0.03, 0.05, pcf * CF(0, 0.015, 0), lk(26, 26, 30))
	if up then
		K:box("HomePhoneScreen", V3(0.26, 0.004, 0.54), pcf * CF(0, 0.032, 0), L.neon(c3(60, 90, 140), 0.4))
	end
end
local function bookStack(K: any, pcf: CFrame, n: number, seed: number)
	local cols = { c3(40, 70, 120), c3(170, 50, 46), c3(230, 220, 190), c3(60, 110, 80), c3(30, 30, 34), c3(200, 160, 70) }
	local y = 0
	for i = 1, n do
		local h = 0.1 + rnd(seed, i) * 0.08
		local w = 0.8 + rnd(seed, i + 3) * 0.35
		K:box("HomeBook", V3(w, h, 0.6 + rnd(seed, i + 7) * 0.2), pcf * CF(0, y + h / 2, 0) * ANG(0, (rnd(seed, i + 11) - 0.5) * 0.3, 0), { c = cols[(i + seed) % #cols + 1], m = M.SmoothPlastic })
		y += h
	end
end
T.mug, T.penCup, T.phone, T.bookStack, T.keyboard, T.mouse = mug, penCup, phone, bookStack, keyboard, mouse

SLOT.desk = function(C_: any, info: any): boolean?
	local K, F = C_.K, info.F
	local top = first(info, "DeskTop")
	if not top then
		return false
	end
	local item = tostring(info.item)
	local y = top.max.Y
	local topL = from(top, L.oak, M.Wood)
	local exec = string.find(item, "executive") ~= nil
	local builtin = string.find(item, "builtin") ~= nil
	local hi = K.detail ~= "low"
	local x0, x1, z0, z1 = top.min.X, top.max.X, top.min.Z, top.max.Z
	local th = if exec then 0.16 else 0.1
	K:slab("HomeDeskTop", x1 - x0, z1 - z0, th, 0.04, F * CF((x0 + x1) / 2, y - th / 2, (z0 + z1) / 2), topL)
	K:box("HomeDeskEdge", V3(x1 - x0 - 0.04, 0.03, 0.03), F * CF((x0 + x1) / 2, y - th - 0.015, z1 - 0.02), tint(topL, 0.2))
	-- 다리
	for _, lg in all(info, "DeskLeg") do
		if lg.mat == M.Metal and not builtin then
			local legL = lk(34, 34, 38, M.Metal)
			for _, sz in { -1, 1 } do
				K:box("HomeDeskLegPost", V3(0.12, y - th, 0.12), F * CF(lg.c.X, (y - th) / 2, lg.c.Z + sz * (lg.size.Z / 2 - 0.1)), legL)
			end
			K:box("HomeDeskLegFoot", V3(0.14, 0.08, lg.size.Z), F * CF(lg.c.X, 0.04, lg.c.Z), legL)
			K:box("HomeDeskLegTop", V3(0.12, 0.1, lg.size.Z - 0.1), F * CF(lg.c.X, y - th - 0.05, lg.c.Z), legL)
			K:disc("HomeDeskGlide", 0.12, 0.02, F * CF(lg.c.X, 0.005, lg.c.Z + lg.size.Z / 2 - 0.1), L.rubber)
		else
			boxF(K, "HomeDeskSide", F, V3(lg.min.X, 0, z0 + 0.02), V3(lg.max.X, y - th, z1 - 0.02), topL)
		end
	end
	if exec then
		-- 임원용: 양쪽 서랍장 + 가죽 데스크 매트
		boxF(K, "HomeDeskModesty", F, V3(x0 + 0.4, 0.6, z0 + 0.1), V3(x1 - 0.4, y - th, z0 + 0.2), topL)
	end
	local mp = first(info, "ModestyPanel")
	if mp and not exec then
		boxF(K, "HomeDeskModesty", F, mp.min, mp.max, lk(40, 40, 44, M.Metal))
		if hi then
			for i = 1, 6 do
				K:box("HomeDeskModestySlot", V3((mp.size.X - 0.4) / 6 - 0.08, 0.06, 0.01), F * CF(mp.min.X + 0.2 + (mp.size.X - 0.4) * (i - 0.5) / 6, mp.c.Y, mp.max.Z + 0.006), lk(20, 20, 22))
			end
		end
	end
	-- 서랍장 (서랍 3단 + 손잡이)
	for _, du in all(info, "DrawerUnit") do
		local dl = if du.color.R > 0.85 then lk(240, 238, 234) else from(du, L.oak, M.Wood)
		boxF(K, "HomeDeskDrawerBody", F, V3(du.min.X, 0.12, du.min.Z), V3(du.max.X, du.max.Y, du.max.Z - 0.03), dl)
		local n = 3
		local hh = (du.max.Y - 0.18) / n
		for i = 1, n do
			local yc = 0.15 + hh * (i - 0.5)
			K:box("HomeDeskDrawer", V3(du.size.X - 0.06, hh - 0.04, 0.04), F * CF(du.c.X, yc, du.max.Z - 0.01), tint(dl, -0.03))
			K:box("HomeDeskDrawerPull", V3(du.size.X * 0.4, 0.04, 0.05), F * CF(du.c.X, yc + hh / 2 - 0.12, du.max.Z + 0.02), if exec then L.brass else lk(60, 60, 64, M.Metal))
		end
		for _, sx in { -1, 1 } do
			K:ball("HomeDeskCaster", 0.12, F * CF(du.c.X + sx * (du.size.X / 2 - 0.12), 0.06, du.c.Z), lk(30, 30, 32))
		end
	end
	-- 모니터 (원래 자리) · 노트북 · 키보드 · 마우스 · 스탠드
	local mon = first(info, "Monitor")
	if mon then
		local scr = first(info, "MonitorScreen") or mon
		local texts = {
			goshiwon = "9급 공무원 기출 2025\n- 행정법 3회독\n- 한국사 오답노트\nD-87",
			oneroom = "광안리 맛집 정리.xlsx\n민락 회센터 · 밀면\n돼지국밥 · 조개구이",
			officetel = "def deploy():\n  build()\n  test()\n# 13:40 회의",
			apartment = "가계부 10월\n관리비 31만\n아이 학원비\n적금 50만",
			penthouse = "KOSPI 2,6xx ▲\n포트폴리오 리밸런싱\n부산 미팅 15:00",
		}
		local scrP, lab = monitor(C_, F * CF(mon.c.X, y, math.max(z0 + 0.45, mon.c.Z - 0.15)), math.min(scr.size.X, 2.4), math.min(scr.size.Y, 1.35), { text = texts[C_.tier] or texts.oneroom })
		C_.monitorScreen, C_.monitorText = scrP, lab
	end
	local kb = first(info, "Keyboard")
	if kb then
		keyboard(K, F * CF(kb.c.X, y, kb.c.Z))
	end
	local ms = first(info, "Mouse")
	if ms then
		mouse(K, F * CF(ms.c.X + (if ms.c.X > (kb and kb.c.X or 0) then 0.2 else -0.2), y, ms.c.Z))
	end
	local lb = first(info, "LaptopBase")
	if lb then
		K:slab("HomeLaptopBase", lb.size.X, lb.size.Z, 0.05, 0.04, F * CF(lb.c.X, y + 0.025, lb.c.Z), lk(186, 188, 192, M.Metal))
		local lid = F * CF(lb.c.X, y + 0.05, lb.min.Z + 0.02) * ANG(math.rad(-12), 0, 0)
		K:box("HomeLaptopLid", V3(lb.size.X, 0.9, 0.04), lid * CF(0, 0.45, 0), lk(186, 188, 192, M.Metal))
		K:box("HomeLaptopScreen", V3(lb.size.X - 0.1, 0.8, 0.01), lid * CF(0, 0.45, 0.025), L.neon(c3(70, 110, 160), 0.35))
		K:box("HomeLaptopKeys", V3(lb.size.X - 0.2, 0.01, lb.size.Z * 0.45), F * CF(lb.c.X, y + 0.055, lb.c.Z - 0.08), lk(40, 40, 44))
	end
	local lh = first(info, "LampHead")
	local lf = first(info, "LampFoot")
	if lh and lf then
		-- 스탠드: 원래 머리 자리 (원래 PointLight 가 그대로 비춤)
		local base = F * CF(lf.c.X, y, lf.c.Z)
		K:disc("HomeDeskLampBase", 0.55, 0.06, base * CF(0, 0.03, 0), lk(30, 30, 32, M.Metal))
		local j1 = (base * CF(0, 0.08, 0)).Position
		local headP = (F * CF(lh.c.X, lh.c.Y + 0.08, lh.c.Z)).Position
		local elbow = (j1 + headP) / 2 + V3(0, 0.45, 0) + (F.LookVector * 0.25)
		K:seg("HomeDeskLampArm", j1, elbow, 0.06, lk(30, 30, 32, M.Metal))
		K:seg("HomeDeskLampArm", elbow, headP, 0.06, lk(30, 30, 32, M.Metal))
		K:ball("HomeDeskLampJoint", 0.1, CF(elbow), lk(30, 30, 32, M.Metal))
		local hcf = CFrame.lookAt(headP, headP - YA * 0.8 + F.LookVector * 0.3)
		K:cyl("HomeDeskLampShade", 0.45, 0.42, hcf * CF(0, 0, -0.18) * ANG(0, PI / 2, 0), lk(30, 30, 32, M.Metal))
		K:disc("HomeDeskLampBulb", 0.34, 0.02, hcf * CF(0, 0, -0.41) * ANG(PI / 2, 0, 0), L.lampWarm)
	end
	-- 책상 위 생활 소품
	if hi then
		local left = x0 + 0.5
		local right = x1 - 0.5
		local kbx = if kb then kb.c.X else (x0 + x1) / 2
		local items = 0
		local function freeAt(x: number, z: number, r: number): boolean
			for _, rr in info.all do
				if rr.max.Y > y - 0.02 and math.abs(rr.c.X - x) < rr.size.X / 2 + r and math.abs(rr.c.Z - z) < rr.size.Z / 2 + r then
					return false
				end
			end
			return true
		end
		local spots = { { right - 0.1, z0 + 0.45 }, { left + 0.1, z1 - 0.55 }, { right - 0.25, z1 - 0.45 }, { left + 0.35, z0 + 0.5 } }
		for i, sp in spots do
			if freeAt(sp[1], sp[2], 0.3) and math.abs(sp[1] - kbx) > 1.1 then
				local p = F * CF(sp[1], y, sp[2])
				if i == 1 then
					penCup(K, p)
				elseif i == 2 then
					mug(K, p * ANG(0, 0.6, 0), if C_.lux >= 4 then lk(250, 248, 242) else lk(200, 220, 236))
				elseif i == 3 then
					phone(K, p * ANG(0, 0.3, 0), true)
				else
					bookStack(K, p, if C_.tier == "goshiwon" then 4 else 2, C_.seed)
				end
				items += 1
			end
		end
		if C_.tier == "goshiwon" or C_.tier == "oneroom" then
			-- 모니터 옆 포스트잇
			if mon then
				for i = 1, 3 do
					K:box("HomePostIt", V3(0.3, 0.3, 0.01), F * CF(mon.c.X + (mon.size.X / 2 + 0.05) * (if i == 3 then -1 else 1), y + 1.0 + i * 0.32, math.max(z0 + 0.45, mon.c.Z - 0.15) - 0.06) * ANG(0, 0, (i - 2) * 0.12), { c = ({ c3(255, 236, 120), c3(255, 180, 200), c3(170, 220, 255) })[i], m = M.SmoothPlastic })
				end
			end
		end
	end
	return true
end

-- TV · 거실장 -------------------------------------------------------------------------------------
-- TV 테두리 (화면 파트 TVScreen 은 그대로 보이게 두고 둘레만): scr = info rec (F 공간)
local function tvBezel(C_: any, F: CFrame, scr: any, o: any)
	local K = C_.K
	local w, h = scr.size.X, scr.size.Y
	local fz = scr.max.Z
	local c = scr.c
	local body = o.body or lk(22, 22, 24)
	local bz = o.bezel or 0.05
	local depth = o.depth or 0.1
	-- 뒷판 + 뒤 불룩한 부분
	K:box("HomeTVBack", V3(w + 2 * bz, h + 2 * bz, depth), F * CF(c.X, c.Y, scr.min.Z - depth / 2 + 0.005), body)
	K:box("HomeTVHump", V3(w * 0.55, h * 0.5, 0.14), F * CF(c.X, c.Y - h * 0.08, scr.min.Z - depth - 0.07), body)
	-- 테두리 (화면 앞면보다 살짝 앞)
	for _, sy in { -1, 1 } do
		K:box("HomeTVBezel", V3(w + 2 * bz, bz, 0.04), F * CF(c.X, c.Y + sy * (h / 2 + bz / 2), fz - 0.015), o.frame or body)
	end
	for _, sx in { -1, 1 } do
		K:box("HomeTVBezel", V3(bz, h, 0.04), F * CF(c.X + sx * (w / 2 + bz / 2), c.Y, fz - 0.015), o.frame or body)
	end
	if not o.frame then
		K:box("HomeTVLogo", V3(0.28, 0.025, 0.005), F * CF(c.X, c.Y - h / 2 - bz / 2, fz + 0.006), lk(150, 150, 154, M.Metal))
		K:box("HomeTVStandbyLED", V3(0.03, 0.015, 0.005), F * CF(c.X + w / 2 - 0.2, c.Y - h / 2 - bz / 2, fz + 0.006), L.neon(c3(255, 60, 40), 0.3))
	end
	return w, h
end

local function setTop(C_: any, F: CFrame, x: number, y: number, z: number, kind: string)
	local K = C_.K
	if kind == "stb" then
		K:slab("HomeSetTopBox", 1.0, 0.7, 0.14, 0.06, F * CF(x, y + 0.07, z), lk(30, 30, 34))
		K:box("HomeSetTopLED", V3(0.2, 0.04, 0.01), F * CF(x + 0.3, y + 0.08, z + 0.35), L.neon(c3(60, 220, 120)))
	elseif kind == "router" then
		K:box("HomeRouter", V3(0.8, 0.14, 0.55), F * CF(x, y + 0.07, z), lk(240, 240, 238))
		for i = -1, 1, 2 do
			K:seg("HomeRouterAntenna", F * V3(x + i * 0.3, y + 0.14, z - 0.22), F * V3(x + i * 0.34, y + 0.75, z - 0.26), 0.05, lk(230, 230, 228))
		end
		for i = 0, 3 do
			K:box("HomeRouterLED", V3(0.03, 0.02, 0.01), F * CF(x - 0.25 + i * 0.12, y + 0.08, z + 0.28), L.neon(c3(80, 220, 255)))
		end
	elseif kind == "remote" then
		K:slab("HomeRemote", 0.2, 0.75, 0.05, 0.08, F * CF(x, y + 0.025, z) * ANG(0, 0.35, 0), lk(30, 30, 32))
		K:box("HomeRemoteRed", V3(0.06, 0.012, 0.06), F * CF(x, y + 0.055, z) * ANG(0, 0.35, 0) * CF(0, 0, -0.28), L.ledRed)
	elseif kind == "console" then
		K:rbox("HomeConsole", V3(0.4, 1.3, 1.0), 0.08, F * CF(x, y + 0.65, z), lk(244, 244, 246))
		K:box("HomeConsoleCore", V3(0.26, 1.2, 0.9), F * CF(x, y + 0.65, z), lk(28, 28, 32))
		K:box("HomeConsoleLED", V3(0.02, 0.4, 0.01), F * CF(x + 0.1, y + 0.65, z + 0.5), L.neon(c3(80, 160, 255)))
	end
end

SLOT.tv = function(C_: any, info: any): boolean?
	local K, F = C_.K, info.F
	local scr = first(info, "TVScreen", "Screen")
	if not scr then
		return false
	end
	local item = tostring(info.item)
	local frameTV = string.find(item, "frame") ~= nil
	local cab = first(info, "TVCabinet")
	local hi = K.detail ~= "low"
	local w, h = tvBezel(C_, F, scr, { frame = if frameTV then lk(214, 200, 176, M.Wood) else nil, bezel = if frameTV then 0.2 else 0.045, depth = if frameTV then 0.12 else 0.09 })
	local onCab = string.find(item, "cabinet") ~= nil
	if onCab and cab then
		-- 스탠드 다리
		for _, sx in { -1, 1 } do
			K:wedge("HomeTVFoot", V3(0.12, 0.5, 0.7), F * CF(scr.c.X + sx * w * 0.38, cab.max.Y + 0.25, scr.c.Z + 0.1), lk(28, 28, 30))
		end
	else
		-- 벽걸이 브래킷 (뒤)
		K:box("HomeTVMount", V3(w * 0.4, h * 0.35, 0.06), F * CF(scr.c.X, scr.c.Y, scr.min.Z - 0.12), lk(40, 40, 44, M.Metal))
		-- 벽 속으로 숨긴 전선 대신 몰딩 (오피스텔 이하)
		if cab and C_.lux <= 3 then
			K:box("HomeCableCover", V3(0.16, scr.min.Y - cab.max.Y, 0.05), F * CF(scr.c.X + w * 0.2, (scr.min.Y + cab.max.Y) / 2, scr.min.Z - 0.1), lk(240, 240, 238))
		end
	end
	if cab then
		local cl = if cab.color.R > 0.8 then lk(240, 238, 234) else from(cab, L.walnut, M.Wood)
		local x0, x1, z0, z1 = cab.min.X, cab.max.X, cab.min.Z, cab.max.Z
		local y1 = cab.max.Y
		boxF(K, "HomeTVCabKick", F, V3(x0 + 0.1, 0, z0 + 0.1), V3(x1 - 0.1, 0.3, z1 - 0.12), lk(30, 30, 32))
		boxF(K, "HomeTVCabBody", F, V3(x0, 0.3, z0), V3(x1, y1 - 0.06, z1 - 0.02), cl)
		K:slab("HomeTVCabTop", x1 - x0 + 0.04, z1 - z0 + 0.03, 0.06, 0.03, F * CF((x0 + x1) / 2, y1 - 0.03, (z0 + z1) / 2), if C_.lux >= 4 then L.marbleWhite else cl)
		local n = math.max(2, math.floor((x1 - x0) / 1.8))
		local fw = (x1 - x0) / n
		for i = 1, n do
			local xc = x0 + fw * (i - 0.5)
			local center = (i == math.ceil(n / 2)) and n >= 3
			K:box(if center then "HomeTVCabOpen" else "HomeTVCabDoor", V3(fw - 0.05, y1 - 0.42, 0.03), F * CF(xc, (0.32 + y1 - 0.08) / 2, z1 - 0.005), if center then lk(40, 38, 36) else tint(cl, -0.03))
			if not center then
				K:box("HomeTVCabPull", V3(fw * 0.5, 0.03, 0.03), F * CF(xc, y1 - 0.18, z1 + 0.012), lk(70, 66, 60, M.Metal))
			end
		end
		-- 위: 셋톱박스 · 공유기 · 리모컨 (+ 게임기)
		local cz = (z0 + z1) / 2
		if hi then
			setTop(C_, F, x0 + 0.7, y1, cz, "stb")
			setTop(C_, F, x1 - 0.6, y1, cz - 0.1, "remote")
			if C_.lux <= 3 then
				setTop(C_, F, x1 - 1.4, y1, cz - 0.05, "router")
			end
			if C_.tier == "officetel" or C_.tier == "apartment" then
				setTop(C_, F, x0 + 1.8, y1, cz, "console")
			end
			if C_.lux >= 4 then
				-- 디퓨저 + 작은 화분
				K:vcyl("HomeDiffuser", 0.45, 0.28, F * CF(x1 - 1.2, y1 + 0.225, cz + 0.1), L.glass(c3(170, 120, 80), 0.35))
				for i = 0, 4 do
					K:seg("HomeDiffuserReed", F * V3(x1 - 1.2, y1 + 0.4, cz + 0.1), F * V3(x1 - 1.2 + math.cos(i * 1.3) * 0.25, y1 + 1.15, cz + 0.1 + math.sin(i * 1.3) * 0.2), 0.025, L.darkWood)
				end
			end
		end
		-- 사운드바 (원래 자리)
		local sb = first(info, "Soundbar")
		if sb then
			K:rbox("HomeSoundbar", V3(sb.size.X, 0.24, 0.42), 0.1, F * CF(sb.c.X, y1 + 0.12, sb.c.Z + 0.02), lk(34, 34, 36))
			K:box("HomeSoundbarGrille", V3(sb.size.X - 0.2, 0.18, 0.02), F * CF(sb.c.X, y1 + 0.12, sb.c.Z + 0.24), lk(52, 52, 56, M.Fabric))
			K:box("HomeSoundbarLED", V3(0.12, 0.02, 0.01), F * CF(sb.c.X + sb.size.X / 2 - 0.3, y1 + 0.07, sb.c.Z + 0.25), L.neon(c3(255, 255, 255), 0.3))
		end
	end
	-- 프레임 TV: 아래 콘솔 대신 바닥 스탠드 없음 · 액자 모드 그림 (꺼져 있을 때만 보이게 화면 앞 얇게는 안 함)
	return true
end

-- 책장 · 선반 ------------------------------------------------------------------------------------
local BOOK_COLS = {
	c3(36, 58, 96), c3(150, 44, 40), c3(226, 214, 186), c3(54, 96, 72), c3(28, 28, 32), c3(196, 150, 64),
	c3(236, 236, 230), c3(110, 70, 110), c3(80, 120, 150), c3(200, 96, 60), c3(160, 160, 150), c3(90, 60, 44),
}
-- 펜트하우스 서재: 가죽 · 천 양장본 (차분한 네이비 · 버건디 · 포레스트 · 코냑 · 크림) + 금박 띠
local BOOK_LUX = {
	c3(30, 40, 62), c3(96, 30, 34), c3(40, 62, 48), c3(140, 92, 56), c3(24, 22, 22), c3(222, 210, 186),
	c3(120, 110, 96), c3(64, 70, 80), c3(74, 30, 28), c3(176, 160, 132), c3(52, 44, 40), c3(200, 192, 176),
}
-- 책 한 줄: F 공간 x0..x1, 선반 윗면 y, 앞 z, 최대 높이 hmax, 깊이 dep. 기울어진 책 · 책 받침 포함
local function bookRow(C_: any, F: CFrame, x0: number, x1: number, y: number, zf: number, hmax: number, dep: number, seed: number, o: any?): number
	local K = C_.K
	local oo: any = o or {}
	local x = x0
	local i = 0
	local n = 0
	local lowDetail = K.detail == "low"
	while x < x1 - 0.12 and n < (oo.max or 40) do
		i += 1
		local r = rnd(seed, i)
		local t = 0.1 + rnd(seed, i + 50) * 0.12
		if lowDetail then
			t = t * 2.2
		end
		local h = math.min(hmax - 0.06, 0.7 + r * 0.5)
		local d = math.min(dep - 0.05, 0.55 + rnd(seed, i + 90) * 0.25)
		if x + t > x1 then
			break
		end
		local lux5 = (C_.lux or 1) >= 5
		local pal = if lux5 then BOOK_LUX else BOOK_COLS
		local col = pal[(seed + i * 7) % #pal + 1]
		local lean = 0
		if not oo.straight and r > 0.9 and x + t + 0.3 < x1 then
			lean = 0.22
		end
		local cx = x + t / 2
		local cf = F * CF(cx + (if lean > 0 then math.sin(lean) * h / 2 else 0), y + h / 2 * math.cos(lean), zf - d / 2) * ANG(0, 0, -lean)
		K:box("HomeBookSpine", V3(t, h, d), cf, { c = col, m = if lux5 then (if i % 3 == 0 then M.Fabric else M.Leather) else M.SmoothPlastic })
		if not lowDetail and r > 0.45 then
			if lux5 then
				-- 금박 띠 두 줄 (양장본 책등)
				for _, fy in { 0.36, 0.26 } do
					K:box("HomeBookBand", V3(t + 0.004, 0.02, 0.01), cf * CF(0, h * fy, d / 2), { c = c3(196, 164, 98), m = M.Metal })
				end
			else
				K:box("HomeBookBand", V3(t + 0.004, 0.04, 0.01), cf * CF(0, h * 0.3, d / 2), { c = col:Lerp(Color3.new(1, 1, 1), 0.55), m = M.SmoothPlastic })
			end
		end
		x += t + (if lean > 0 then h * math.sin(lean) + 0.02 else 0.005)
		n += 1
	end
	return x
end
T.bookRow = bookRow

-- 선반 칸 위 장식: kind = "plant" | "frame" | "box" | "vase" | "noodle" | "jar" | "cactus" | "trophy"
local function shelfDeco(C_: any, F: CFrame, x: number, y: number, z: number, kind: string, hmax: number, seed: number)
	local K = C_.K
	local hh = math.min(hmax - 0.05, 1.0)
	if kind == "plant" then
		Props.potPlant(K, F * CF(x, y, z), 0.42, math.min(hh - 0.35, 0.65), { pot = lk(236, 232, 224, M.Concrete) })
	elseif kind == "cactus" then
		K:vcyl("HomeCactusPot", 0.32, 0.36, F * CF(x, y + 0.16, z), L.terracotta)
		K:disc("HomeCactusSoil", 0.32, 0.02, F * CF(x, y + 0.31, z), L.soil)
		K:ell("HomeCactus", V3(0.22, math.min(0.55, hh - 0.35), 0.22), F * CF(x, y + 0.32 + math.min(0.55, hh - 0.35) / 2, z), lk(70, 120, 66, M.Grass))
		K:ell("HomeCactusArm", V3(0.12, 0.22, 0.12), F * CF(x + 0.12, y + 0.55, z), lk(70, 120, 66, M.Grass))
	elseif kind == "frame" then
		local w, h = 0.7, math.min(0.9, hh - 0.05)
		local cf = F * CF(x, y + h / 2, z - 0.1) * ANG(math.rad(-8), (rnd(seed, 3) - 0.5) * 0.4, 0)
		K:box("HomePhotoFrame", V3(w, h, 0.05), cf, if rnd(seed, 5) > 0.5 then L.walnut else lk(240, 240, 236))
		K:box("HomePhoto", V3(w - 0.14, h - 0.14, 0.01), cf * CF(0, 0, 0.026), { c = c3(120 + math.floor(rnd(seed, 7) * 90), 140, 170), m = M.SmoothPlastic })
		K:box("HomePhotoSky", V3(w - 0.14, (h - 0.14) * 0.45, 0.012), cf * CF(0, (h - 0.14) * 0.27, 0.026), lk(150, 190, 220))
	elseif kind == "box" then
		local h = math.min(0.8, hh - 0.05)
		K:rbox("HomeStorageBox", V3(1.0, h, 0.85), 0.04, F * CF(x, y + h / 2, z - 0.45), { c = ({ c3(200, 190, 170), c3(90, 96, 104), c3(230, 226, 216) })[seed % 3 + 1], m = M.Fabric })
		K:box("HomeStorageLabel", V3(0.4, 0.16, 0.01), F * CF(x, y + h * 0.6, z + 0.0), lk(250, 250, 246))
	elseif kind == "vase" then
		local h = math.min(0.95, hh - 0.05)
		K:vcyl("HomeVase", h * 0.75, 0.38, F * CF(x, y + h * 0.375, z - 0.3), { c = ({ c3(232, 228, 218), c3(60, 62, 66), c3(180, 140, 100) })[seed % 3 + 1], m = M.SmoothPlastic })
		K:ell("HomeVaseNeck", V3(0.28, 0.2, 0.28), F * CF(x, y + h * 0.78, z - 0.3), { c = c3(232, 228, 218), m = M.SmoothPlastic })
	elseif kind == "noodle" then
		for i = 0, 2 do
			local cx = x + (i - 1) * 0.42
			K:vcyl("HomeCupNoodle", 0.38, 0.36, F * CF(cx, y + 0.19, z - 0.3), { c = if i == 1 then c3(230, 120, 30) else c3(206, 40, 36), m = M.SmoothPlastic })
			K:disc("HomeCupNoodleLid", 0.37, 0.02, F * CF(cx, y + 0.385, z - 0.3), lk(240, 236, 226))
			K:box("HomeCupNoodleBand", V3(0.37, 0.1, 0.01), F * CF(cx, y + 0.2, z - 0.12), lk(250, 246, 236))
		end
	elseif kind == "jar" then
		K:vcyl("HomeJar", 0.5, 0.36, F * CF(x, y + 0.25, z - 0.3), L.glass(c3(230, 236, 236), 0.4))
		K:vcyl("HomeJarFill", 0.3, 0.3, F * CF(x, y + 0.17, z - 0.3), lk(150, 100, 60))
		K:vcyl("HomeJarLid", 0.06, 0.37, F * CF(x, y + 0.53, z - 0.3), L.walnut)
	elseif kind == "trophy" then
		K:box("HomeTrophyBase", V3(0.32, 0.12, 0.26), F * CF(x, y + 0.06, z - 0.3), L.walnut)
		K:vcyl("HomeTrophyStem", 0.25, 0.06, F * CF(x, y + 0.24, z - 0.3), L.goldMetal)
		K:ell("HomeTrophyCup", V3(0.3, 0.26, 0.3), F * CF(x, y + 0.48, z - 0.3), L.goldMetal)
	end
end

SLOT.shelf = function(C_: any, info: any): boolean?
	local K, F = C_.K, info.F
	local boards = all(info, "ShelfBoard")
	local sides = all(info, "ShelfSide")
	local backP = first(info, "ShelfBack")
	if #boards == 0 then
		return false
	end
	table.sort(boards, function(a, b)
		return a.c.Y < b.c.Y
	end)
	local item = tostring(info.item)
	local wood = boards[1].mat == M.Wood and boards[1].color.R < 0.75
	local bl = if wood then from(boards[1], L.walnut, M.Wood) elseif boards[1].color.R > 0.85 then lk(242, 240, 236) else from(boards[1], L.oak, M.Wood)
	local seed = C_.seed + hash(item)
	-- 벽 선반 (한 장): 받침 철물 + 소품
	if #sides == 0 then
		local b = boards[1]
		K:slab("HomeWallShelf", b.size.X, b.size.Z, 0.12, 0.03, F * CF(b.c.X, b.c.Y, b.c.Z), from(b, L.oak, M.Wood))
		for _, br in all(info, "Bracket") do
			-- ㄱ자 선반 받침 (벽 쪽 세로대 + 판 밑 가로대 + 사선 보강대, 가는 흰 철물)
			local bm = lk(236, 236, 232, M.Metal)
			local dz = b.size.Z * 0.78
			K:box("HomeShelfBracketV", V3(0.06, 0.5, 0.035), F * CF(br.c.X, b.min.Y - 0.25, b.min.Z + 0.018), bm)
			K:box("HomeShelfBracketH", V3(0.06, 0.035, dz), F * CF(br.c.X, b.min.Y - 0.018, b.min.Z + dz / 2), bm)
			K:seg("HomeShelfBracketBrace", F * V3(br.c.X, b.min.Y - 0.44, b.min.Z + 0.04), F * V3(br.c.X, b.min.Y - 0.04, b.min.Z + dz * 0.8), 0.03, bm)
		end
		local y = b.max.Y
		local x0, x1 = b.min.X + 0.12, b.max.X - 0.12
		local zf = b.max.Z - 0.05
		-- 왼쪽: 책, 가운데: 컵라면, 오른쪽: 선인장
		local xe = bookRow(C_, F, x0, x0 + (x1 - x0) * 0.38, y, zf, 1.1, b.size.Z, seed, { max = 10 })
		K:box("HomeBookend", V3(0.06, 0.5, 0.5), F * CF(xe + 0.04, y + 0.25, zf - 0.3), L.blackMetal)
		shelfDeco(C_, F, x0 + (x1 - x0) * 0.62, y, zf, "noodle", 1.2, seed)
		shelfDeco(C_, F, x1 - 0.25, y, zf, "cactus", 1.2, seed)
		return true
	end
	-- 책장: 옆판 · 뒤판 · 선반 판
	local sx0, sx1 = math.huge, -math.huge
	for _, s in sides do
		boxF(K, "HomeShelfSide", F, s.min, s.max, bl)
		sx0, sx1 = math.min(sx0, s.max.X), math.max(sx1, s.min.X)
	end
	if backP then
		boxF(K, "HomeShelfBack", F, backP.min, backP.max, tint(bl, 0.06))
	end
	local zf = info.max.Z
	for _, b in boards do
		boxF(K, "HomeShelfBoard", F, V3(sx0, b.min.Y, b.min.Z), V3(sx1, b.max.Y, zf - 0.02), bl)
		if K.detail == "high" then
			K:box("HomeShelfEdge", V3(sx1 - sx0, b.size.Y, 0.02), F * CF((sx0 + sx1) / 2, b.c.Y, zf - 0.01), tint(bl, 0.08))
		end
	end
	-- 칸마다 내용 (책 줄 · 눕힌 책 · 장식)
	local kinds = if C_.tier == "penthouse" then { "vase", "books", "frame", "books", "trophy", "books", "vase" } elseif C_.tier == "apartment" then { "box", "books", "books", "frame", "books", "plant" } else { "books", "plant", "books", "frame" }
	for i = 1, #boards - 1 do
		local b = boards[i]
		local gap = boards[i + 1].min.Y - b.max.Y
		local y = b.max.Y
		if gap < 0.6 then
			continue
		end
		local kind = kinds[(i - 1) % #kinds + 1]
		local x0, x1 = sx0 + 0.08, sx1 - 0.08
		local dep = zf - b.min.Z
		-- 넓은 칸은 2.6 폭 마디로 나눠서 마디마다 다른 구성 (꽉 찬 책 · 책+장식 · 눕힌 책+책 · 장식+책)
		local nSeg = math.max(1, math.floor((x1 - x0) / 2.6 + 0.5))
		local sw = (x1 - x0) / nSeg
		for j = 1, nSeg do
			local a, e = x0 + sw * (j - 1), x0 + sw * j
			local pat = if nSeg == 1 then (if kind == "books" then 0 else 1) else (i * 3 + j + seed) % 4
			local dk = kinds[(i + j) % #kinds + 1]
			if dk == "books" then
				dk = if C_.tier == "penthouse" then "vase" elseif C_.tier == "apartment" then "frame" else "plant"
			end
			if pat == 0 then
				local xe = bookRow(C_, F, a, e - 0.06, y, zf - 0.08, gap, dep, seed + i * 13 + j)
				if xe < e - 0.9 then
					bookStack(K, F * CF((xe + e) / 2, y, zf - 0.45), 3, seed + i + j)
				end
			elseif pat == 1 then
				local xe = bookRow(C_, F, a, a + sw * 0.58, y, zf - 0.08, gap, dep, seed + i * 17 + j, { max = 14 })
				K:box("HomeBookend", V3(0.05, math.min(0.55, gap - 0.1), 0.45), F * CF(xe + 0.05, y + math.min(0.55, gap - 0.1) / 2, zf - 0.35), if C_.lux >= 4 then L.brass else L.blackMetal)
				shelfDeco(C_, F, (xe + e) / 2 + 0.05, y, zf - 0.05, dk, gap, seed + i + j)
			elseif pat == 2 then
				bookStack(K, F * CF(a + 0.5, y, zf - 0.45), if gap > 1.2 then 4 else 3, seed + i * 5 + j)
				bookRow(C_, F, a + 1.05, e - 0.06, y, zf - 0.08, gap, dep, seed + i * 19 + j, { straight = true })
			else
				shelfDeco(C_, F, a + 0.5, y, zf - 0.05, dk, gap, seed + i * 7 + j)
				bookRow(C_, F, a + 1.05, e - 0.06, y, zf - 0.08, gap, dep, seed + i * 23 + j)
			end
		end
	end
	-- 맨 위 판 위 (낮은 것만)
	local topB = boards[#boards]
	if topB.max.Y < 6.2 and C_.tier ~= "penthouse" then
		shelfDeco(C_, F, (sx0 + sx1) / 2 + 0.4, topB.max.Y, zf - 0.05, if C_.tier == "apartment" then "box" else "plant", 1.0, seed + 99)
	end
	return true
end

-- 커튼 ------------------------------------------------------------------------------------------
-- 주름 커튼 한 폭 (F 공간 x0..x1, y0..y1, z 중심) : 세운 원통 주름 + 머리 테이프 + 밑단
local function pleatPanel(K: any, F: CFrame, x0: number, x1: number, y0: number, y1: number, z: number, look: any, pitch: number, name: string?): { BasePart }
	local out = {}
	local w = x1 - x0
	local n = math.max(3, math.floor(w / pitch + 0.5))
	local d = w / n * 1.3
	local h = y1 - y0 - 0.22
	for i = 1, n do
		local x = x0 + w * (i - 0.5) / n
		local zz = z + (if i % 2 == 0 then 0.06 else -0.06)
		table.insert(out, K:vcyl(name or "HomeCurtainPleat", h, d, F * CF(x, y0 + h / 2, zz), if i % 2 == 0 then look else tint(look, 0.07)))
	end
	table.insert(out, K:box("HomeCurtainHeader", V3(w, 0.24, d * 0.7), F * CF((x0 + x1) / 2, y1 - 0.12, z), tint(look, -0.04)))
	table.insert(out, K:box("HomeCurtainHem", V3(w, 0.12, d * 0.85), F * CF((x0 + x1) / 2, y0 + 0.06, z), tint(look, 0.06)))
	return out
end

SLOT.curtain = function(C_: any, info: any): boolean?
	local K, F = C_.K, info.F
	local panels = all(info, "Curtain")
	local rail = first(info, "CurtainRail")
	local sheer = first(info, "Sheer")
	if #panels == 0 then
		return false
	end
	local item = tostring(info.item)
	local look = fab(panels[1])
	local blackout = string.find(item, "blackout") ~= nil
	local hi = K.detail ~= "low"
	local pitch = if K.detail == "low" then 0.6 elseif blackout then 0.38 else 0.3
	local ry = if rail then rail.max.Y else panels[1].max.Y + 0.1
	local rx0 = if rail then rail.min.X else info.min.X
	local rx1 = if rail then rail.max.X else info.max.X
	local rz = if rail then rail.c.Z else panels[1].c.Z - 0.2
	-- 레일 / 봉
	if C_.lux <= 2 then
		K:cyl("HomeCurtainRod", rx1 - rx0, 0.1, F * CF((rx0 + rx1) / 2, ry - 0.08, rz + 0.1), L.blackMetal)
		for _, sx in { -1, 1 } do
			K:ball("HomeCurtainFinial", 0.2, F * CF(if sx > 0 then rx1 + 0.06 else rx0 - 0.06, ry - 0.08, rz + 0.1), L.blackMetal)
			K:box("HomeCurtainBracket", V3(0.08, 0.2, 0.4), F * CF(if sx > 0 then rx1 - 0.35 else rx0 + 0.35, ry - 0.02, rz - 0.05), L.blackMetal)
		end
	else
		K:box("HomeCurtainTrack", V3(rx1 - rx0, 0.12, 0.22), F * CF((rx0 + rx1) / 2, ry - 0.06, rz), lk(236, 236, 234, M.Metal))
		if C_.lux >= 3 then
			K:box("HomeCurtainMotor", V3(0.5, 0.22, 0.26), F * CF(rx1 - 0.4, ry - 0.17, rz), lk(236, 236, 234))
		end
		-- 커튼 박스 (천장 가까이 레일이 있으면)
		local wp = (C_.V.cf * (F * CF((rx0 + rx1) / 2, ry, rz))).Position
		local lp = C_.V.cf:PointToObjectSpace(wp)
		local ch = C_:ceilAt(lp.X, lp.Z)
		if ch - ry < 0.9 and C_.lux >= 4 then
			K:box("HomeCurtainBox", V3(rx1 - rx0 + 0.4, ch - ry + 0.45, 0.06), F * CF((rx0 + rx1) / 2, (ch + ry - 0.45) / 2, rz + 0.55), L.white)
			K:box("HomeCurtainBoxSoffit", V3(rx1 - rx0 + 0.4, 0.05, 0.6), F * CF((rx0 + rx1) / 2, ch - 0.025, rz + 0.25), L.white)
		end
	end
	-- 속커튼 (쉬폰): 반투명 + 세로 주름
	local sheerParts = {}
	if sheer then
		local sl = { c = sheer.color, m = M.Fabric, t = 0.58 }
		table.insert(sheerParts, K:box("HomeSheer", V3(sheer.size.X, sheer.size.Y, 0.03), F * CF(sheer.c.X, sheer.c.Y, sheer.c.Z), sl))
		if hi then
			local n = math.floor(sheer.size.X / 0.55)
			for i = 1, n do
				local x = sheer.min.X + sheer.size.X * (i - 0.5) / n
				table.insert(sheerParts, K:vcyl("HomeSheerFold", sheer.size.Y - 0.1, 0.12, F * CF(x, sheer.c.Y, sheer.c.Z + (if i % 2 == 0 then 0.04 else -0.03)), { c = sheer.color, m = M.Fabric, t = 0.66 }))
			end
		end
	end
	-- 열린 상태: 양옆에 모인 커튼 (원래 자리)
	local openParts = {}
	for _, p in panels do
		local w = math.max(p.size.X, 1.2)
		for _, q in pleatPanel(K, F, p.c.X - w / 2, p.c.X + w / 2, p.min.Y, math.min(ry - 0.1, p.max.Y + 0.05), p.c.Z, look, pitch) do
			table.insert(openParts, q)
		end
		-- 커튼 끈 (타이백)
		if hi and C_.lux <= 3 and not blackout then
			table.insert(openParts, K:box("HomeCurtainTie", V3(w + 0.06, 0.12, 0.35), F * CF(p.c.X, p.min.Y + (p.max.Y - p.min.Y) * 0.42, p.c.Z + 0.04), tint(look, 0.12)))
		end
	end
	-- 닫힌 상태 (처음엔 투명): 창 전체를 덮는 두 폭
	local closedParts = {}
	local cmid = (rx0 + rx1) / 2
	local y0 = panels[1].min.Y
	local y1 = math.min(ry - 0.1, panels[1].max.Y + 0.05)
	local cz = panels[1].c.Z
	for _, side in { { rx0 + 0.05, cmid - 0.02 }, { cmid + 0.02, rx1 - 0.05 } } do
		for _, q in pleatPanel(K, F, side[1], side[2], y0, y1, cz, look, if K.detail == "low" then 0.9 else 0.55, "HomeCurtainClosed") do
			table.insert(closedParts, q)
		end
	end
	local store = {}
	for _, q in closedParts do
		store[q] = q.Transparency
		q.Transparency = 1
	end
	for _, q in openParts do
		store[q] = q.Transparency
	end
	info.curtain = { open = openParts, closed = closedParts, t = store, at = F * CF(rx1, (y0 + y1) / 2, cz) }
	C_.curtains = C_.curtains or {}
	table.insert(C_.curtains, info.curtain)
	return true
end

-- 조명 (스탠드) -------------------------------------------------------------------------------------
SLOT.lamp = function(C_: any, info: any): boolean?
	local K, F = C_.K, info.F
	local shade = first(info, "LampShade")
	local base = first(info, "LampBase")
	if not shade then
		return false
	end
	local item = tostring(info.item)
	local arc = string.find(item, "arc") ~= nil
	local brass = string.find(item, "brass") ~= nil or not arc
	local poleL = if brass then L.brass else lk(40, 40, 42, M.Metal)
	local bx, bz = if base then base.c.X else shade.c.X, if base then base.c.Z else shade.c.Z
	local glow
	if arc then
		-- 대리석 받침 + 아치 + 돔 갓 (정면 쪽으로 휨)
		K:box("HomeLampMarble", V3(0.8, 0.45, 0.8), F * CF(bx, 0.225, bz), L.marbleWhite)
		local pts = {}
		local topY = shade.c.Y + 0.9
		local reach = 1.25
		for i = 0, 7 do
			local t = i / 7
			local a = t * PI * 0.62
			table.insert(pts, F * V3(bx, 0.45 + (topY - 0.45) * math.sin(math.min(PI / 2, a * 1.25)) , bz + reach * (1 - math.cos(a)) ))
		end
		for i = 1, #pts - 1 do
			K:seg("HomeLampArc", pts[i], pts[i + 1], 0.09, poleL, 0.04)
		end
		local tip = pts[#pts]
		K:seg("HomeLampDrop", tip, tip - V3(0, 0.5, 0), 0.04, L.black)
		local scf = CF(tip - V3(0, 0.75, 0))
		K:ell("HomeLampDome", V3(1.25, 0.8, 1.25), scf, if brass then L.brass else lk(40, 40, 42, M.Metal))
		glow = K:disc("HomeLampDiffuser", 1.05, 0.03, scf * CF(0, -0.28, 0), L.lampWarm)
	else
		K:disc("HomeLampBase", 0.95, 0.08, F * CF(bx, 0.04, bz), lk(30, 30, 32, M.Metal))
		K:disc("HomeLampBaseCap", 0.5, 0.06, F * CF(bx, 0.11, bz), poleL)
		local top = shade.min.Y + 0.15
		K:vcyl("HomeLampPole", top - 0.12, 0.08, F * CF(bx, 0.12 + (top - 0.12) / 2, bz), poleL)
		K:vcyl("HomeLampKnob", 0.08, 0.12, F * CF(bx, top * 0.55, bz), poleL)
		local sd = math.max(shade.size.X, shade.size.Z)
		local sh = shade.size.Y
		K:vcyl("HomeLampShade", sh, sd, F * CF(shade.c.X, shade.c.Y, shade.c.Z), { c = c3(246, 236, 214), m = M.Fabric, t = 0.15 })
		K:vcyl("HomeLampShadeTrim", 0.04, sd + 0.02, F * CF(shade.c.X, shade.max.Y - 0.02, shade.c.Z), poleL)
		K:vcyl("HomeLampShadeTrim", 0.04, sd + 0.02, F * CF(shade.c.X, shade.min.Y + 0.02, shade.c.Z), poleL)
		glow = K:vcyl("HomeLampBulb", sh * 0.6, sd * 0.5, F * CF(shade.c.X, shade.c.Y, shade.c.Z), L.lampWarm)
	end
	local l = C_:light(glow, "PointLight", { Range = 11, Brightness = 0.55, Color = c3(255, 206, 150) })
	info.lamp = { glow = glow, light = l, base = (F * CF(bx, 0, bz)).Position }
	C_.lamps = C_.lamps or {}
	table.insert(C_.lamps, info.lamp)
	return true
end

-- 식물 ------------------------------------------------------------------------------------------
SLOT.plant = function(C_: any, info: any): boolean?
	local K, F = C_.K, info.F
	local pot = first(info, "Pot")
	if not pot then
		return false
	end
	local item = tostring(info.item)
	local kind = if string.find(item, "monstera") then "monstera" elseif string.find(item, "olive") then "olive" elseif string.find(item, "sansev") then "snake" elseif string.find(item, "ficus") then "ficus" else "monstera"
	local pl = { c = pot.color, m = if pot.mat == M.Slate then M.Concrete else pot.mat }
	if pot.color.R < 0.35 then
		pl = { c = pot.color, m = M.Slate }
	end
	local dia = math.max(pot.size.X, pot.size.Z)
	local h = info.max.Y
	-- 받침 접시 + 화분 (Props.floorPlant)
	K:disc("HomePlantSaucer", dia + 0.15, 0.06, F * CF(pot.c.X, 0.03, pot.c.Z), tint(pl, 0.1))
	Props.floorPlant(K, F * CF(pot.c.X, 0.06, pot.c.Z), { kind = kind, h = h - 0.1, dia = dia, pot = pl })
	if K.detail == "high" then
		for i = 1, 5 do
			local a = i * 1.25 + C_.seed
			K:ball("HomePebble", 0.1 + rnd(C_.seed, i) * 0.06, F * CF(pot.c.X + math.cos(a) * dia * 0.32, dia * 0.9 - 0.02, pot.c.Z + math.sin(a) * dia * 0.32), lk(214, 210, 200, M.Slate))
		end
	end
	return true
end

-- 러그 ------------------------------------------------------------------------------------------
SLOT.rug = function(C_: any, info: any): boolean?
	local K, F = C_.K, info.F
	local rug = first(info, "Rug")
	if not rug then
		return false
	end
	local item = tostring(info.item)
	local col = rug.color
	local field = { c = col, m = M.Fabric }
	local border = { c = col:Lerp(Color3.new(0, 0, 0), 0.22), m = M.Fabric }
	local round = rug.part:IsA("Part") and (rug.part :: Part).Shape == Enum.PartType.Cylinder
	local t = rug.size.Y
	if round then
		local d = math.max(rug.size.X, rug.size.Z)
		K:disc("HomeRugBorder", d, t, F * CF(rug.c.X, t / 2, rug.c.Z), border)
		K:disc("HomeRugField", d - 0.5, t + 0.006, F * CF(rug.c.X, (t + 0.006) / 2, rug.c.Z), field)
		K:disc("HomeRugRing", d - 1.2, t + 0.008, F * CF(rug.c.X, (t + 0.008) / 2, rug.c.Z), { c = col:Lerp(Color3.new(1, 1, 1), 0.12), m = M.Fabric })
		K:disc("HomeRugCenter", d - 1.45, t + 0.01, F * CF(rug.c.X, (t + 0.01) / 2, rug.c.Z), field)
		return true
	end
	local w, l = rug.size.X, rug.size.Z
	local b = math.min(0.45, math.min(w, l) * 0.07)
	K:box("HomeRugField", V3(w - 2 * b, t, l - 2 * b), F * CF(rug.c.X, t / 2, rug.c.Z), field)
	K:box("HomeRugBorder", V3(w, t, b), F * CF(rug.c.X, t / 2, rug.min.Z + b / 2), border)
	K:box("HomeRugBorder", V3(w, t, b), F * CF(rug.c.X, t / 2, rug.max.Z - b / 2), border)
	K:box("HomeRugBorder", V3(b, t, l - 2 * b), F * CF(rug.min.X + b / 2, t / 2, rug.c.Z), border)
	K:box("HomeRugBorder", V3(b, t, l - 2 * b), F * CF(rug.max.X - b / 2, t / 2, rug.c.Z), border)
	if K.detail ~= "low" then
		if string.find(item, "silk") then
			-- 대리석 무늬 실크 러그: 비스듬한 결
			for i = 1, 6 do
				local zz = rug.min.Z + l * (i - 0.5) / 6
				K:box("HomeRugVein", V3(w * 0.7, 0.004, 0.08), F * CF(rug.c.X + (rnd(C_.seed, i) - 0.5) * w * 0.2, t + 0.002, zz) * ANG(0, (rnd(C_.seed, i + 3) - 0.5) * 0.5, 0), { c = col:Lerp(Color3.new(1, 1, 1), 0.25), m = M.Fabric })
			end
		else
			-- 울 러그: 안쪽 테 + 격자 결
			K:box("HomeRugInner", V3(w - 2 * b - 0.5, 0.004, 0.06), F * CF(rug.c.X, t + 0.002, rug.min.Z + b + 0.25), border)
			K:box("HomeRugInner", V3(w - 2 * b - 0.5, 0.004, 0.06), F * CF(rug.c.X, t + 0.002, rug.max.Z - b - 0.25), border)
			K:box("HomeRugInner", V3(0.06, 0.004, l - 2 * b - 0.5), F * CF(rug.min.X + b + 0.25, t + 0.002, rug.c.Z), border)
			K:box("HomeRugInner", V3(0.06, 0.004, l - 2 * b - 0.5), F * CF(rug.max.X - b - 0.25, t + 0.002, rug.c.Z), border)
		end
		-- 짧은 변 술 (프린지)
		local short = if w < l then "x" else "z"
		for _, sgn in { -1, 1 } do
			if short == "x" then
				K:box("HomeRugFringe", V3(w - 0.1, 0.02, 0.22), F * CF(rug.c.X, 0.012, rug.c.Z + sgn * (l / 2 + 0.11)), { c = c3(236, 230, 214), m = M.Fabric })
			else
				K:box("HomeRugFringe", V3(0.22, 0.02, l - 0.1), F * CF(rug.c.X + sgn * (w / 2 + 0.11), 0.012, rug.c.Z), { c = c3(236, 230, 214), m = M.Fabric })
			end
		end
	end
	return true
end

-- 그림 · 액자 -------------------------------------------------------------------------------------
-- 액자 틀 + 캔버스 (dcf: 벽 표면 위 가운데, +Z = 보는 쪽) 반환: 그림 면 dcf (캔버스 앞면)
local function artFrame(K: any, dcf: CFrame, w: number, h: number, o: any): CFrame
	local fr = o.frame or L.walnut
	local b = o.border or 0.1
	local dep = o.depth or 0.12
	if o.gallery then
		-- 갤러리 랩 캔버스 (틀 없음, 두꺼운 캔버스)
		K:box("HomeCanvasEdge", V3(w, h, dep), dcf * CF(0, 0, dep / 2), o.edge or lk(236, 232, 222, M.Fabric))
		return dcf * CF(0, 0, dep + 0.002)
	end
	K:box("HomeArtBack", V3(w - 0.04, h - 0.04, dep * 0.4), dcf * CF(0, 0, dep * 0.2), lk(60, 56, 52))
	for _, sy in { -1, 1 } do
		K:box("HomeArtFrame", V3(w, b, dep), dcf * CF(0, sy * (h / 2 - b / 2), dep / 2), fr)
	end
	for _, sx in { -1, 1 } do
		K:box("HomeArtFrame", V3(b, h - 2 * b, dep), dcf * CF(sx * (w / 2 - b / 2), 0, dep / 2), fr)
	end
	local mat = o.mat
	if mat then
		K:box("HomeArtMat", V3(w - 2 * b, h - 2 * b, 0.01), dcf * CF(0, 0, dep * 0.45), mat)
	end
	return dcf * CF(0, 0, dep * 0.45 + 0.012)
end
T.artFrame = artFrame

-- 그림 구성 (면 dcf, 폭 w, 높이 h): kind = "warm" | "sea" | "bridge" | "abstract" | "pair"
local function artPaint(K: any, f: CFrame, w: number, h: number, kind: string, seed: number, cols: { Color3 })
	local function blk(name: string, x: number, y: number, bw: number, bh: number, c: Color3, rot: number?, z: number?)
		K:box(name, V3(bw, bh, 0.008), f * CF(x * w / 2, y * h / 2, (z or 0) * 2.5 + 0.004) * ANG(0, 0, rot or 0), { c = c, m = M.SmoothPlastic })
	end
	if kind == "sea" then
		blk("HomePaintSky", 0, 0.45, w, h * 0.55, c3(170, 200, 222))
		blk("HomePaintSkyGlow", 0, 0.12, w, h * 0.12, c3(238, 214, 190), 0, 0.001)
		blk("HomePaintSea", 0, -0.35, w, h * 0.42, c3(46, 96, 140), 0, 0.001)
		blk("HomePaintSeaLight", 0.1, -0.18, w * 0.7, h * 0.05, c3(120, 170, 200), 0, 0.002)
		blk("HomePaintSand", 0, -0.86, w, h * 0.14, c3(226, 206, 168), 0, 0.002)
		K:disc("HomePaintSun", h * 0.16, 0.01, f * CF(w * 0.22, h * 0.2, 0.024) * ANG(PI / 2, 0, 0), { c = c3(250, 238, 210), m = M.SmoothPlastic })
		for i = 1, 4 do
			blk("HomePaintWave", (rnd(seed, i) - 0.5) * 1.4, -0.3 - i * 0.12, w * (0.15 + rnd(seed, i + 5) * 0.2), h * 0.012, c3(240, 246, 250), (rnd(seed, i + 9) - 0.5) * 0.1, 0.003)
		end
	elseif kind == "bridge" then
		blk("HomePaintNight", 0, 0.25, w, h * 0.5, c3(16, 22, 46))
		blk("HomePaintSea", 0, -0.5, w, h * 0.5, c3(10, 18, 34), 0, 0.001)
		-- 광안대교: 상판 + 주탑 2 + 케이블 + 조명 점
		blk("HomeBridgeDeck", 0, -0.05, w, h * 0.025, c3(200, 210, 230), 0, 0.003)
		for _, sx in { -0.35, 0.35 } do
			blk("HomeBridgeTower", sx, 0.12, w * 0.012, h * 0.4, c3(190, 200, 225), 0, 0.003)
			for j = 1, 4 do
				local dx = j * 0.07
				blk("HomeBridgeCable", sx - dx / 2, 0.12 - j * 0.02, w * dx * 0.5 * 2.2, h * 0.004, c3(150, 170, 220), math.rad(18 + j * 4), 0.002)
				blk("HomeBridgeCable", sx + dx / 2, 0.12 - j * 0.02, w * dx * 0.5 * 2.2, h * 0.004, c3(150, 170, 220), -math.rad(18 + j * 4), 0.002)
			end
		end
		for i = 1, 9 do
			local x = -0.9 + i * 0.18
			blk("HomeBridgeLight", x, -0.05, w * 0.01, h * 0.012, ({ c3(120, 200, 255), c3(255, 120, 200), c3(140, 255, 160) })[i % 3 + 1], 0, 0.005)
			blk("HomeBridgeReflect", x, -0.35, w * 0.006, h * 0.22, c3(60, 90, 150), 0, 0.002)
		end
	elseif kind == "abstract" then
		blk("HomePaintGround", 0, 0, w, h, cols[1] or c3(232, 226, 214))
		K:ell("HomePaintForm", V3(w * 0.42, h * 0.62, 0.01), f * CF(-w * 0.18, h * 0.05, 0.019), { c = cols[2] or c3(40, 70, 110), m = M.SmoothPlastic })
		K:ell("HomePaintForm", V3(w * 0.3, h * 0.45, 0.01), f * CF(w * 0.2, -h * 0.12, 0.024), { c = cols[3] or c3(196, 120, 80), m = M.SmoothPlastic })
		K:ell("HomePaintForm", V3(w * 0.16, h * 0.2, 0.01), f * CF(w * 0.3, h * 0.28, 0.029), { c = c3(214, 180, 110), m = M.SmoothPlastic })
		for i = 1, 5 do
			blk("HomePaintStroke", (rnd(seed, i) - 0.5) * 1.5, (rnd(seed, i + 7) - 0.5) * 1.5, w * 0.25, h * 0.012, c3(30, 30, 32), (rnd(seed, i + 3) - 0.5) * 2, 0.012)
		end
	elseif kind == "field" then
		-- 색면 회화 (로스코풍): 바탕 + 부드러운 가장자리의 큰 색면 2 (번진 테두리 = 반투명 한 겹 더)
		local g = cols[1] or c3(120, 40, 34)
		blk("HomePaintGround", 0, 0, w, h, g)
		local a = cols[2] or c3(196, 120, 60)
		local b = cols[3] or c3(60, 30, 30)
		for j, spec in { { 0.36, 0.5, a }, { -0.42, 0.34, b } } do
			local cy, hh, cc = spec[1], spec[2], spec[3]
			blk("HomePaintFieldEdge", 0, cy, w * 0.9, h * hh * 0.5 + h * 0.05, cc:Lerp(g, 0.45), 0, 0.002 + j * 0.0001)
			blk("HomePaintField", 0, cy, w * 0.84, h * hh * 0.5, cc, 0, 0.004)
		end
	elseif kind == "lines" then
		-- 미니멀 라인 드로잉 (먹선 원 · 아치 · 점)
		blk("HomePaintGround", 0, 0, w, h, cols[1] or c3(244, 240, 232))
		K:ell("HomePaintArch", V3(w * 0.46, h * 0.56, 0.01), f * CF(-w * 0.08, -h * 0.05, 0.019), { c = cols[2] or c3(214, 196, 170), m = M.SmoothPlastic })
		for i = 1, 3 do
			blk("HomePaintStroke", -0.5 + i * 0.28, -0.1 + (i % 2) * 0.3, w * 0.004 + 0.01, h * (0.35 + rnd(seed, i) * 0.2), c3(36, 34, 32), (rnd(seed, i + 2) - 0.5) * 0.6, 0.008)
		end
		K:disc("HomePaintSunDot", h * 0.12, 0.01, f * CF(w * 0.24, h * 0.26, 0.024) * ANG(PI / 2, 0, 0), { c = cols[3] or c3(176, 96, 60), m = M.SmoothPlastic })
	else -- warm
		blk("HomePaintGround", 0, 0, w, h, cols[1] or c3(236, 230, 218))
		K:ell("HomePaintArch", V3(w * 0.4, h * 0.75, 0.01), f * CF(-w * 0.15, -h * 0.12, 0.019), { c = cols[2] or c3(200, 120, 80), m = M.SmoothPlastic })
		blk("HomePaintArchCut", -0.3, -0.62, w * 0.42, h * 0.3, cols[1] or c3(236, 230, 218), 0, 0.007)
		K:disc("HomePaintSunDot", h * 0.28, 0.01, f * CF(w * 0.22, h * 0.18, 0.024) * ANG(PI / 2, 0, 0), { c = cols[3] or c3(60, 80, 120), m = M.SmoothPlastic })
		blk("HomePaintLine", 0.1, -0.55, w * 0.7, h * 0.02, c3(120, 90, 60), 0, 0.009)
	end
end
T.artPaint = artPaint

SLOT.art = function(C_: any, info: any): boolean?
	local K, F = C_.K, info.F
	local item = tostring(info.item)
	local cork = first(info, "CorkFrame")
	local frame = first(info, "ArtFrame")
	local canvas = first(info, "Canvas")
	local hi = K.detail ~= "low"
	if cork then
		local w, h = cork.size.X, cork.size.Y
		local back = cork.min.Z
		local dcf = F * CF(cork.c.X, cork.c.Y, back)
		local f = artFrame(K, dcf, w, h, { frame = from(cork, L.oak, M.Wood), border = 0.1, depth = 0.1, mat = lk(196, 150, 100, M.Fabric) })
		-- 메모 · 사진 · 달력 · 압정
		local memoC = { c3(255, 236, 120), c3(255, 186, 200), c3(170, 220, 255), c3(250, 250, 246), c3(190, 240, 170) }
		local texts = { "월세 25일", "토익 6/14", "택배 101호", "편의점\n18~24시", "엄마 생신" }
		for i = 1, 5 do
			local x = (rnd(C_.seed, i) - 0.5) * (w - 0.9)
			local y = (rnd(C_.seed, i + 10) - 0.5) * (h - 0.8)
			local rot = (rnd(C_.seed, i + 20) - 0.5) * 0.3
			local mcf = f * CF(x, y, 0) * ANG(0, 0, rot)
			K:box("HomeMemo", V3(0.6, 0.6, 0.01), mcf * CF(0, 0, 0.005), { c = memoC[i], m = M.SmoothPlastic })
			if hi then
				K:text("HomeMemoText", 0.5, 0.4, mcf * CF(0, -0.03, 0.011), texts[i], { fg = c3(40, 40, 60), font = Enum.Font.Gotham, d = 0.005, free = true })
			end
			K:ball("HomePushPin", 0.08, mcf * CF(0, 0.24, 0.04), { c = ({ c3(220, 40, 40), c3(40, 120, 220), c3(250, 200, 40) })[i % 3 + 1], m = M.SmoothPlastic })
		end
		-- 네컷 사진
		local pcf = f * CF(w / 2 - 0.45, 0.1, 0) * ANG(0, 0, 0.08)
		K:box("HomePhotoStrip", V3(0.32, 1.25, 0.01), pcf * CF(0, 0, 0.006), lk(30, 30, 34))
		for j = 0, 3 do
			K:box("HomePhotoStripCell", V3(0.26, 0.26, 0.01), pcf * CF(0, 0.45 - j * 0.3, 0.012), lk(200 - j * 20, 170, 150 + j * 15))
		end
		return true
	end
	if not (frame or canvas) then
		return false
	end
	local ref = frame or canvas
	local w, h = ref.size.X, ref.size.Y
	local dcf = F * CF(ref.c.X, ref.c.Y, ref.min.Z)
	local cols = {}
	if canvas then
		table.insert(cols, canvas.color)
	end
	for _, p in all(info, "Paint") do
		table.insert(cols, p.color)
	end
	if string.find(item, "pair") then
		-- 두 폭 (딥틱)
		local gw = (w - 0.3) / 2
		for i, sx in { -1, 1 } do
			local d = dcf * CF(sx * (gw / 2 + 0.15), 0, 0)
			local f = artFrame(K, d, gw, h, { frame = from(frame, L.oak, M.Wood), border = 0.08, mat = lk(246, 244, 238) })
			artPaint(K, f, gw - 0.5, h - 0.5, "warm", C_.seed + i, { c3(236, 230, 218), cols[i + 1] or c3(200, 120, 80), cols[4 - i] or c3(60, 80, 120) })
		end
		return true
	end
	local kind = if string.find(item, "sea") then "sea" elseif string.find(item, "bridge") then "bridge" elseif string.find(item, "large") then "abstract" else "warm"
	local gallery = kind == "abstract"
	local f = artFrame(K, dcf, w, h, { frame = if kind == "bridge" then lk(26, 26, 28, M.Metal) else from(frame, L.oak, M.Wood), border = if kind == "bridge" then 0.06 else 0.1, gallery = gallery, mat = if kind == "bridge" then lk(250, 250, 248) else nil })
	local inset = if gallery then 0 elseif kind == "bridge" then 0.5 else 0.22
	artPaint(K, f, w - inset * 2, h - inset * 2, kind, C_.seed, cols)
	-- 큰 그림: 위에 그림 조명 (불빛 없이 네온)
	if (gallery or kind == "bridge") and C_.lux >= 5 then
		local lcf = dcf * CF(0, h / 2 + 0.3, 0)
		K:box("HomePictureLightArm", V3(0.06, 0.3, 0.45), lcf * CF(0, 0, 0.22), L.brass)
		K:cyl("HomePictureLight", math.min(w * 0.5, 3), 0.18, lcf * CF(0, -0.08, 0.45), L.brass)
		K:box("HomePictureLightLED", V3(math.min(w * 0.5, 3) - 0.1, 0.02, 0.08), lcf * CF(0, -0.18, 0.45), L.neon(c3(255, 226, 180), 0.2))
	end
	return true
end

-- 가전 (공기청정기 · 스탠드 에어컨 · 선풍기) -----------------------------------------------------------
SLOT.appliance = function(C_: any, info: any): boolean?
	local K, F = C_.K, info.F
	local item = tostring(info.item)
	local hi = K.detail ~= "low"
	local pur = first(info, "AirPurifier")
	local ac = first(info, "StandAC")
	local fanBase = first(info, "FanBase")
	if pur then
		local bl = withC(L.plasticWhite, pur.color)
		local w, d, h = pur.size.X, pur.size.Z, pur.size.Y + 0.08
		K:rbox("HomePurifierBody", V3(w, h - 0.1, d), 0.14, F * CF(pur.c.X, 0.08 + (h - 0.1) / 2, pur.c.Z), bl)
		K:slab("HomePurifierFoot", w - 0.1, d - 0.1, 0.08, 0.1, F * CF(pur.c.X, 0.04, pur.c.Z), lk(200, 200, 198))
		K:disc("HomePurifierTop", math.min(w, d) - 0.12, 0.04, F * CF(pur.c.X, h - 0.01, pur.c.Z), lk(180, 184, 188))
		for i = 1, 3 do
			K:vcyl("HomePurifierGrille", 0.042, (math.min(w, d) - 0.12) * (1 - i * 0.22), F * CF(pur.c.X, h + 0.005, pur.c.Z), lk(120, 124, 128))
		end
		-- 앞면 360 흡입구 결 · 상태 LED 링 · 공기질 표시
		if hi then
			for i = 1, 6 do
				K:box("HomePurifierSlot", V3(w - 0.3, 0.025, 0.01), F * CF(pur.c.X, 0.4 + i * 0.22, pur.max.Z + 0.002), lk(214, 214, 212))
			end
		end
		local led = K:box("HomePurifierLED", V3(0.5, 0.05, 0.01), F * CF(pur.c.X, h - 0.45, pur.max.Z + 0.004), L.neon(c3(60, 140, 255)))
		local _, lab = K:text("HomePurifierAQ", 0.4, 0.14, F * CF(pur.c.X, h - 0.3, pur.max.Z + 0.006) * ANG(0, 0, 0), "좋음", { fg = c3(60, 140, 255), glow = 1.2, d = 0.005, free = true })
		info.purifier = { led = led, label = lab }
		C_.purifier = info.purifier
		return true
	end
	if ac then
		local bl = withC(L.plasticWhite, ac.color)
		local w, d, h = ac.size.X, ac.size.Z, ac.max.Y
		K:rbox("HomeStandACBody", V3(w, h - 0.12, d), 0.2, F * CF(ac.c.X, 0.12 + (h - 0.12) / 2, ac.c.Z), bl)
		K:slab("HomeStandACBase", w - 0.1, d - 0.1, 0.12, 0.12, F * CF(ac.c.X, 0.06, ac.c.Z), lk(70, 72, 76))
		-- 무풍 패널 (작은 구멍 띠) + 둥근 송풍구 + 디스플레이
		local fz = ac.max.Z + 0.003
		K:box("HomeStandACPanel", V3(w - 0.24, h * 0.42, 0.01), F * CF(ac.c.X, h * 0.72, fz), lk(222, 224, 226))
		if hi then
			for i = 1, 8 do
				K:box("HomeStandACHoles", V3(w - 0.34, 0.012, 0.012), F * CF(ac.c.X, h * 0.53 + i * h * 0.045, fz + 0.006), lk(200, 202, 206))
			end
		end
		K:cyl("HomeStandACFanRing", 0.03, w * 0.62, F * CF(ac.c.X, h * 0.82, fz + 0.01) * ANG(0, PI / 2, 0), lk(186, 190, 194))
		K:cyl("HomeStandACFan", 0.02, w * 0.5, F * CF(ac.c.X, h * 0.82, fz + 0.02) * ANG(0, PI / 2, 0), lk(60, 62, 66))
		K:box("HomeStandACDisplay", V3(0.42, 0.16, 0.01), F * CF(ac.c.X, h * 0.45, fz + 0.002), lk(30, 30, 34))
		K:text("HomeStandACTemp", 0.36, 0.13, F * CF(ac.c.X, h * 0.45, fz + 0.008), "24°", { fg = c3(80, 200, 255), glow = 1.4, d = 0.004, free = true })
		return true
	end
	if fanBase then
		local motor = first(info, "FanMotor")
		local guard = first(info, "FanGuard")
		local pole = first(info, "FanPole")
		local bc = F * CF(fanBase.c.X, fanBase.min.Y, fanBase.c.Z)
		K:disc("HomeFanBase", 0.95, 0.12, bc * CF(0, 0.06, 0), lk(240, 240, 236))
		K:disc("HomeFanButtons", 0.4, 0.03, bc * CF(0, 0.13, 0.22), lk(160, 200, 230))
		local topY = if motor then motor.c.Y else fanBase.min.Y + 1.2
		K:vcyl("HomeFanPole", topY - fanBase.min.Y - 0.12, 0.12, bc * CF(0, (topY - fanBase.min.Y) / 2, 0), lk(240, 240, 236))
		local hc = F * CF(fanBase.c.X, topY, fanBase.c.Z)
		K:ell("HomeFanMotor", V3(0.42, 0.42, 0.5), hc * CF(0, 0, -0.1), lk(240, 240, 236))
		local gd = if guard then math.max(guard.size.X, guard.size.Y) else 1.4
		local gcf = hc * CF(0, 0, 0.25)
		local rings = K:ring("HomeFanGuard", gcf, gd / 2, 0.04, 14, lk(230, 232, 236))
		K:ring("HomeFanGuardInner", gcf * CF(0, 0, 0.04), gd / 4, 0.03, 10, lk(230, 232, 236))
		local blades = {}
		for i = 0, 2 do
			table.insert(blades, K:ell("HomeFanBlade", V3(gd * 0.42, 0.26, 0.03), gcf * CF(0, 0, -0.04) * ANG(0, 0, i * 2 * PI / 3) * CF(gd * 0.2, 0, 0), { c = c3(170, 210, 240), m = M.SmoothPlastic, t = 0.2 }))
		end
		table.insert(blades, K:disc("HomeFanHub", 0.2, 0.08, gcf * CF(0, 0, -0.04) * ANG(PI / 2, 0, 0), lk(200, 210, 220)))
		info.fan = { blades = blades, center = (C_.V.cf * gcf).Position, axis = (C_.V.cf * gcf).LookVector }
		C_.fan = info.fan
		local _ = rings
		return true
	end
	return false
end

-- 장식 스탠드 (사이드 테이블 + 화병 + 책) ---------------------------------------------------------------
SLOT.deco = function(C_: any, info: any): boolean?
	local K, F = C_.K, info.F
	local top = first(info, "StandTop")
	if not top then
		return false
	end
	local y = top.max.Y
	local tl = from(top, L.walnut, M.Wood)
	K:disc("HomeSideTableTop", math.max(top.size.X, top.size.Z), 0.1, F * CF(top.c.X, y - 0.05, top.c.Z), tl)
	K:disc("HomeSideTableEdge", math.max(top.size.X, top.size.Z) - 0.06, 0.03, F * CF(top.c.X, y - 0.115, top.c.Z), tint(tl, 0.2))
	K:vcyl("HomeSideTableStem", y - 0.18, 0.1, F * CF(top.c.X, (y - 0.18) / 2 + 0.05, top.c.Z), L.blackMetal)
	K:disc("HomeSideTableFoot", 0.85, 0.05, F * CF(top.c.X, 0.025, top.c.Z), L.blackMetal)
	local vase = first(info, "Vase")
	local vx, vz = if vase then vase.c.X else top.c.X + 0.2, if vase then vase.c.Z else top.c.Z
	local vl = if vase then withC(L.white, vase.color) else L.white
	K:vcyl("HomeDecoVase", 0.55, 0.36, F * CF(vx, y + 0.275, vz), vl)
	K:ell("HomeDecoVaseShoulder", V3(0.36, 0.2, 0.36), F * CF(vx, y + 0.56, vz), vl)
	K:vcyl("HomeDecoVaseNeck", 0.16, 0.16, F * CF(vx, y + 0.7, vz), vl)
	-- 유칼립투스 가지
	for i = 0, 4 do
		local a = i * 1.26 + 0.3
		local tip = F * V3(vx + math.cos(a) * 0.3, y + 1.35 + rnd(C_.seed, i) * 0.3, vz + math.sin(a) * 0.25)
		K:seg("HomeDecoStem", F * V3(vx, y + 0.72, vz), tip, 0.025, lk(90, 110, 80))
		for j = 1, 3 do
			local p = (F * V3(vx, y + 0.72, vz)):Lerp(tip, 0.35 + j * 0.2)
			K:ell("HomeDecoLeaf", V3(0.14, 0.04, 0.12), CF(p) * ANG(0, a + j, 0.4), lk(120, 150, 130, M.Grass))
		end
	end
	-- 책 두 권 + 향초
	local books = all(info, "Book")
	if #books > 0 then
		local b = books[1]
		bookStack(K, F * CF(b.c.X, y, b.c.Z), 2, C_.seed + 3)
		K:vcyl("HomeCandle", 0.22, 0.2, F * CF(b.c.X, y + 0.3, b.c.Z), lk(244, 238, 226))
		K:vcyl("HomeCandleWick", 0.04, 0.02, F * CF(b.c.X, y + 0.43, b.c.Z), lk(30, 30, 30))
	end
	return true
end

-- 슬롯 하나 짓기 (기본 가구만: 산 가구(Variant)는 그대로 둠) --------------------------------------------
local function defaultPiece(slot: Instance): Model?
	for _, ch in slot:GetChildren() do
		if ch:IsA("Model") and ch:GetAttribute("Variant") == nil and (ch:GetAttribute("Default") == true or ch.Name == "Furniture") then
			return ch
		end
	end
	return nil
end

function C:overlaySlot(slot: Model)
	local K = self.K
	self.slotRec = self.slotRec or {}
	local piece = defaultPiece(slot)
	if not piece then
		return
	end
	local cat = tostring(slot:GetAttribute("Category") or "")
	local fn = SLOT[cat]
	if not fn then
		return
	end
	local F = slotFrame(self, slot, piece, BACK[cat])
	if not F then
		return
	end
	local info = analyze(self, F, piece)
	info.item = piece:GetAttribute("ItemId") or slot:GetAttribute("DefaultItem")
	if T.debug then
		local fz = F.ZVector
		K:note(string.format("slot %s %s front=(%.1f,%.1f) at (%.1f,%.1f)", cat, tostring(info.item), fz.X, fz.Z, F.Position.X, F.Position.Z))
	end
	info.cat = cat
	info.slot = slot
	local lights0 = self.lightsMine
	local nParts0 = #K.parts
	local ok, res = false, nil
	local g = K:group("HomeSlot_" .. tostring(slot:GetAttribute("SlotId") or slot.Name), function()
		K:free(function()
			ok, res = pcall(fn, self, info)
		end)
	end)
	if not ok or res == false then
		if not ok then
			K:note("slot " .. cat .. " " .. tostring(info.item) .. " error: " .. tostring(res))
		end
		g:Destroy()
		self.lightsMine = lights0
		return
	end
	-- 기본 가구 숨김 (화면 · 테마 파트 · 프롬프트 붙은 파트는 그대로)
	local hidden = {}
	for _, d in piece:GetDescendants() do
		if d:IsA("BasePart") and not keepVisible(d) and d.Transparency < 0.99 then
			if not K.hidden[d] then
				self:hide(d)
				table.insert(hidden, d)
			end
		end
	end
	local mn, mx = laabb(F * CF((info.min + info.max) / 2), info.max - info.min)
	self:use(mn, mx)
	self.slotRec[slot] = { group = g, hidden = hidden, lights = self.lightsMine - lights0, info = info, parts = #K.parts - nParts0, F = F }
end

-- 슬롯 가구가 바뀌면 (서버가 사고 · 돌리고 · 되돌림) 그 슬롯만 다시
function C:rebuildSlot(slot: Model)
	local K = self.K
	local rec = self.slotRec and self.slotRec[slot]
	if rec then
		if rec.group then
			rec.group:Destroy()
		end
		for _, p in rec.hidden do
			local h = K.hidden[p]
			if h then
				Scan.restore({ [p] = h })
				K.hidden[p] = nil
			end
		end
		self.lightsMine = math.max(0, self.lightsMine - (rec.lights or 0))
		self.slotRec[slot] = nil
	end
	-- 지운 파트 · 불빛 목록 정리
	local keepP = {}
	for _, p in K.parts do
		if p.Parent then
			table.insert(keepP, p)
		end
	end
	K.parts = keepP
	local keepL = {}
	for _, l in K.lights do
		if l.Parent then
			table.insert(keepL, l)
		end
	end
	K.lights = keepL
	-- 침대가 바뀌면 침대 따라 지은 것 (러그 · 침대 밑 간접등) 도 지우고 러그는 새 침대에 맞춰 다시
	local isBed = slot:GetAttribute("Category") == "bed"
	if isBed then
		for _, g in { self.bedRugGroup, self.bedGlowGroup } do
			if g then
				g:Destroy()
			end
		end
		self.bedRugGroup, self.bedGlowGroup = nil, nil
	end
	self:overlaySlot(slot)
	if isBed and self.bedRugArgs then
		local a = self.bedRugArgs
		pcall(function()
			self:bedRug(a[1], a[2], a[3])
		end)
	end
	if isBed and self.bedGlowRebuild then
		pcall(self.bedGlowRebuild)
	end
	K:finish()
end

function C:slotOverlays()
	local K = self.K
	for _, slot in self.slots do
		local base = slot:FindFirstChild("SlotBase") or slot.PrimaryPart
		if not (base and base:IsA("BasePart")) then
			continue
		end
		local lp = self.V.cf:PointToObjectSpace(base.Position)
		local cat = slot:GetAttribute("Category")
		-- 실제 높이로 (복층 아래 주방 슬롯을 위층 방이 가져가지 않게: 받침이 이 방 바닥보다 1 이상 낮으면 아래층 몫)
		local probe = V3(lp.X, (if lp.Y < -1 then lp.Y else math.max(lp.Y, 0)) + 0.5, lp.Z)
		local owner = self:roomAt(probe)
		if cat == "art" or cat == "curtain" or cat == "shelf" or cat == "tv" then
			-- 벽에 붙는 슬롯: 슬롯 앞뒤 1 스터드의 방. 양쪽 다 방이면 슬롯 규약(앞 = 슬롯 -Z) 쪽
			local zf = self.V.cf:VectorToObjectSpace(base.CFrame.ZVector)
			-- (슬롯이 놓인 실제 층 높이로: 복층 아래 서재 책장을 위층 침실이 가져가지 않게)
			local py = probe.Y
			local pf = V3(lp.X, py, lp.Z) - V3(zf.X, 0, zf.Z) * 1.0
			local pb = V3(lp.X, py, lp.Z) + V3(zf.X, 0, zf.Z) * 1.0
			local rf = if self:insideWall(V3(pf.X, py + 0.5, pf.Z)) then nil else self:roomAt(pf)
			local rb = if self:insideWall(V3(pb.X, py + 0.5, pb.Z)) then nil else self:roomAt(pb)
			owner = if rf and rb then rf else (rf or rb or owner)
			-- 벽에 붙은 쪽: 가구 가운데가 가까운 벽의 어느 쪽에 있나
			local piece = defaultPiece(slot)
			if piece and rf and rb then
				local pcf = (piece :: Model):GetBoundingBox()
				local pc = self.V.cf:PointToObjectSpace(pcf.Position)
				local best, bd = nil, math.huge
				for _, w in self.walls do
					if w.mx.Y - w.mn.Y > 2.5 then
						local dx = math.max(w.mn.X - pc.X, 0, pc.X - w.mx.X)
						local dz = math.max(w.mn.Z - pc.Z, 0, pc.Z - w.mx.Z)
						if dx + dz < bd and dx + dz < 0.9 and pc.Y >= w.mn.Y and pc.Y <= w.mx.Y then
							best, bd = w, dx + dz
						end
					end
				end
				if best then
					local wc = (best.mn + best.mx) / 2
					local thinX = (best.mx.X - best.mn.X) < (best.mx.Z - best.mn.Z)
					local axis = if thinX then V3(1, 0, 0) else V3(0, 0, 1)
					local side = if (pc - wc):Dot(axis) >= 0 then 1 else -1
					local half = if thinX then (best.mx.X - best.mn.X) / 2 else (best.mx.Z - best.mn.Z) / 2
					local q = wc + axis * side * (half + 1.0)
					owner = self:roomAt(V3(q.X, py, q.Z)) or owner
				end
			end
		end
		if owner ~= self.room then
			continue
		end
		-- 이 방 천장보다 높이 걸린 것 (복층 위 그림 등) 은 위층 방 몫
		do
			local piece = defaultPiece(slot)
			if piece then
				local _, sz = (piece :: Model):GetBoundingBox()
				local cfp = (piece :: Model):GetBoundingBox()
				local py = self.V.cf:PointToObjectSpace(cfp.Position).Y
				if py - sz.Y / 2 > self.H then
					continue
				end
			end
		end
		local ok, err = pcall(function()
			self:overlaySlot(slot)
		end)
		if not ok then
			K:note("slot error " .. slot.Name .. ": " .. tostring(err))
		end
		-- 바뀌면 다시 짓기 (0.4초 모아서)
		K.conns = K.conns or {}
		local pending = false
		local function changed()
			if pending then
				return
			end
			pending = true
			task.delay(0.4, function()
				pending = false
				if slot.Parent then
					local ok2, e2 = pcall(function()
						self:rebuildSlot(slot)
					end)
					if not ok2 then
						warn("[GwangalliBuildingInterior] home slot rebuild: " .. tostring(e2))
					end
				end
			end)
		end
		table.insert(K.conns, slot.ChildAdded:Connect(changed))
		table.insert(K.conns, slot.ChildRemoved:Connect(changed))
	end
end

-------------------------------------------------------------------------------------------------
-- 방 소품 리스킨 (템플릿 Props 모델: 같은 자리 · 같은 크기, 원본은 숨김)
-------------------------------------------------------------------------------------------------
-- 이름으로 이 방 소품 모델 찾기 (Props / Fixtures 아래)
function C:propModels(name: string): { Instance }
	local out = {}
	if not self.model then
		return out
	end
	for _, d in self.model:GetDescendants() do
		if d.Name == name and (d:IsA("Model") or d:IsA("BasePart")) then
			local p: Vector3
			if d:IsA("BasePart") then
				p = self.V.cf:PointToObjectSpace(d.Position)
			else
				local cf = (d :: Model):GetBoundingBox()
				p = self.V.cf:PointToObjectSpace(cf.Position)
			end
			if self:mine(V3(p.X, math.max(0.5, math.min(p.Y, 1.5)), p.Z)) then
				table.insert(out, d)
			end
		end
	end
	return out
end
-- 이 방 파트 이름별
function C:ownNamed(...: string): { any }
	local set = {}
	for _, n in { ... } do
		set[n] = true
	end
	local out = {}
	for _, r in self.own do
		if set[r.name] then
			table.insert(out, r)
		end
	end
	return out
end

-- 벽걸이 에어컨 (part rec = WallAC 본체). 배관 덮개 · 드레인 호스 · 리모컨 거치대
function C:wallAC(r: any, extra: any?)
	local K = self.K
	local p: BasePart = r.part
	local dcf = self:wallFace(p)
	if not dcf then
		return
	end
	local w = math.max(p.Size.X, p.Size.Z)
	local h = p.Size.Y
	local d = math.min(p.Size.X, p.Size.Z)
	local cy = self.V.cf:PointToObjectSpace(p.Position).Y
	local base = CFrame.fromMatrix(V3(dcf.Position.X, cy, dcf.Position.Z), dcf.XVector, YA, dcf.ZVector)
	local body = lk(246, 246, 244)
	K:free(function()
		K:rbox("HomeACBody", V3(w, h - 0.04, d - 0.04), 0.16, base * CF(0, 0, d / 2), body)
		K:box("HomeACFront", V3(w - 0.08, h * 0.62, 0.02), base * CF(0, h * 0.12, d - 0.01), lk(250, 250, 250))
		local vane = K:box("HomeACVane", V3(w - 0.3, 0.06, 0.26), base * CF(0, -h / 2 + 0.12, d - 0.12) * ANG(math.rad(25), 0, 0), lk(232, 232, 230))
		K:box("HomeACOutlet", V3(w - 0.25, 0.12, 0.3), base * CF(0, -h / 2 + 0.1, d / 2 + 0.1), lk(70, 72, 76))
		K:box("HomeACDisplay", V3(0.5, 0.12, 0.01), base * CF(w / 2 - 0.55, -h * 0.05, d + 0.002), lk(30, 30, 34))
		local led = K:box("HomeACLED", V3(0.16, 0.05, 0.01), base * CF(w / 2 - 0.55, -h * 0.05, d + 0.006), L.neon(c3(80, 200, 255)))
		K:box("HomeACBrand", V3(0.36, 0.05, 0.005), base * CF(-w / 2 + 0.5, h * 0.25, d + 0.003), lk(170, 172, 176, M.Metal))
		-- 배관 (왼쪽으로 벽 속) + 드레인 호스
		K:box("HomeACPipeCover", V3(0.28, 0.22, 0.24), base * CF(-w / 2 - 0.14, -h / 2 + 0.2, 0.12), body)
		self.acVanes = { vane }
		self.acLED = led
	end)
	self:hide(p)
	for _, q in (p.Parent and p.Parent:GetDescendants() or {}) do
		if q:IsA("BasePart") and (q.Name == "ACLouver" or q.Name == "ACLED") then
			self:hide(q)
		end
	end
	-- 리모컨 거치대 (스위치 근처 벽)
	local _, _, rd = self:wallSpot(0.35, 3.9, 4.6, 0.12, { score = function(s, u, cfm)
		return (cfm.Position - dcf.Position).Magnitude
	end })
	if rd then
		K:free(function()
			K:box("HomeRemoteHolder", V3(0.3, 0.6, 0.1), rd * CF(0, 0, 0.05), L.white)
			K:slab("HomeACRemote", 0.22, 0.12, 0.62, 0.05, rd * CF(0, 0.08, 0.13) * ANG(PI / 2, 0, 0), lk(244, 244, 242))
			K:box("HomeACRemoteLCD", V3(0.14, 0.14, 0.01), rd * CF(0, 0.22, 0.19), lk(160, 200, 190))
		end)
	end
end

-- 옷 (옷걸이 + 어깨 + 몸판). pcf: 걸이 고리 아래 점, +X = 옷 폭 방향, +Z = 옷 앞
local function garment(K: any, pcf: CFrame, w: number, len: number, look: any, kind: string?)
	K:seg("HomeHangerHook", (pcf * CF(0, 0.22, 0)).Position, (pcf * CF(0, 0.02, 0)).Position, 0.025, L.chrome)
	K:bar("HomeHangerL", (pcf * CF(0, 0.02, 0)).Position, (pcf * CF(-w * 0.45, -0.22, 0)).Position, 0.05, 0.04, L.walnut)
	K:bar("HomeHangerR", (pcf * CF(0, 0.02, 0)).Position, (pcf * CF(w * 0.45, -0.22, 0)).Position, 0.05, 0.04, L.walnut)
	if kind == "pants" then
		K:box("HomePantsBar", V3(w * 0.85, 0.04, 0.04), pcf * CF(0, -0.22, 0), L.walnut)
		K:box("HomePants", V3(w * 0.42, len, 0.12), pcf * CF(0, -0.22 - len / 2, 0), look)
		return
	end
	-- 옷: 둥근 어깨 + 옆선이 둥근 몸판 (상자 + 양옆 세로 원기둥) + 소매 + 밑단
	local th = if kind == "coat" then 0.2 else 0.13
	local bw = w * (if kind == "dress" then 0.9 else 0.82)
	K:ell("HomeGarmentShoulder", V3(w * 0.95, 0.3, th + 0.04), pcf * CF(0, -0.24, 0), look)
	K:box("HomeGarmentBody", V3(bw - th, len, th), pcf * CF(0, -0.3 - len / 2, 0), look)
	for _, sx in { -1, 1 } do
		K:vcyl("HomeGarmentSide", len, th, pcf * CF(sx * (bw - th) / 2, -0.3 - len / 2, 0), look)
	end
	K:box("HomeGarmentHem", V3(bw - th, 0.05, th + 0.01), pcf * CF(0, -0.3 - len + 0.05, 0), tint(look, -0.08))
	if kind ~= "dress" then
		for _, sx in { -1, 1 } do
			K:box("HomeGarmentSleeve", V3(0.16, len * 0.78, th * 0.9), pcf * CF(sx * (bw / 2 + 0.04), -0.34 - len * 0.39, 0) * ANG(0, 0, sx * 0.05), tint(look, -0.03))
		end
	end
	if kind == "shirt" then
		K:box("HomeGarmentPlacket", V3(0.05, len * 0.9, th + 0.012), pcf * CF(0, -0.3 - len * 0.45, 0), tint(look, -0.1))
		K:box("HomeGarmentCollar", V3(w * 0.3, 0.12, th + 0.06), pcf * CF(0, -0.18, 0), tint(look, -0.06))
	end
end
T.garment = garment

-- 옷걸이 봉 + 옷들: rail = 봉 rec (원통, 방 로컬), clothes = rec 목록 (원래 옷: 색 · 길이)
function C:clothesRail(railRec: any, clothes: { any }, opts: any?)
	local K = self.K
	local o: any = opts or {}
	local mn, mx = railRec.min, railRec.max
	local alongX = (mx.X - mn.X) >= (mx.Z - mn.Z)
	local a = if alongX then V3(mn.X, railRec.c.Y, railRec.c.Z) else V3(railRec.c.X, railRec.c.Y, mn.Z)
	local b = if alongX then V3(mx.X, railRec.c.Y, railRec.c.Z) else V3(railRec.c.X, railRec.c.Y, mx.Z)
	-- 문 앞 (벽이 뚫린 곳) 구간은 봉 · 옷을 비움: o.gaps = { { t0, t1 } } (봉 방향 좌표)
	local gaps = o.gaps or {}
	local function inGap(t: number, pad: number): boolean
		for _, g in gaps do
			if t > g[1] - pad and t < g[2] + pad then
				return true
			end
		end
		return false
	end
	local function coord(p: Vector3): number
		return if alongX then p.X else p.Z
	end
	K:free(function()
		local dir = (b - a).Unit
		-- 봉: 문 구간을 빼고 이어진 조각마다 + 끝 브래킷
		local runs = {}
		local ta, tb = coord(a), coord(b)
		local cur = ta
		table.sort(gaps, function(x, y)
			return x[1] < y[1]
		end)
		for _, g in gaps do
			if g[2] > cur and g[1] < tb then
				if g[1] - cur > 0.6 then
					table.insert(runs, { cur, g[1] })
				end
				cur = math.max(cur, g[2])
			end
		end
		if tb - cur > 0.6 then
			table.insert(runs, { cur, tb })
		end
		for _, rn in runs do
			local pa = a + dir * (rn[1] - ta)
			local pb = a + dir * (rn[2] - ta)
			K:seg("HomeRail", pa, pb, 0.1, L.chrome)
			if #gaps > 0 then
				for _, pe in { pa, pb } do
					K:box("HomeRailBracket", V3(0.16, 0.5, 0.16), CF(pe + V3(0, 0.2, 0)), L.chrome)
				end
			end
		end
		-- 옷: 봉 방향으로 줄지어, 옷 면은 봉과 직각
		local n = #clothes
		local kinds = { "shirt", "coat", "shirt", "pants", "dress", "shirt", "coat" }
		for i, c in clothes do
			local t = (i - 0.5) / n
			local p = a:Lerp(b, t)
			if inGap(coord(p), 0.45) then
				self:hide(c.part)
				continue
			end
			local len = math.clamp(c.size.Y - 0.35, 1.2, 3.4)
			local w = math.clamp(math.max(c.size.X, c.size.Z), 1.0, 1.5)
			local pcf = CFrame.fromMatrix(p, dir:Cross(YA) * -1, YA, dir) -- +X = 봉과 직각
			local look = { c = c.part.Color, m = M.Fabric }
			garment(K, pcf * ANG(0, (rnd(self.seed, i) - 0.5) * 0.25, 0), w, len, look, if len > 2.6 then (if i % 2 == 0 then "coat" else "dress") else kinds[(i + self.seed) % #kinds + 1])
			self:hide(c.part)
		end
	end)
	self:hide(railRec.part)
end

-- 투명 플라스틱 서랍장 (rec = 본체 상자)
function C:plasticDrawers(r: any)
	local K = self.K
	local F, info = propFrame(self, r.part)
	local x0, x1, y1, z0, z1 = info.min.X, info.max.X, info.max.Y, info.min.Z, info.max.Z
	local n = 4
	K:free(function()
		boxF(K, "HomeDrawerFrame", F, V3(x0, 0.08, z0), V3(x1, y1, z1 - 0.06), lk(246, 246, 244))
		for _, sx in { x0 + 0.06, x1 - 0.06 } do
			K:box("HomeDrawerCaster", V3(0.12, 0.08, 0.12), F * CF(sx, 0.04, z1 - 0.2), lk(40, 40, 42))
			K:box("HomeDrawerCaster", V3(0.12, 0.08, 0.12), F * CF(sx, 0.04, z0 + 0.2), lk(40, 40, 42))
		end
		local hh = (y1 - 0.2) / n
		local cols = { c3(220, 60, 60), c3(60, 90, 160), c3(240, 230, 210), c3(70, 70, 76) }
		for i = 1, n do
			local yc = 0.12 + hh * (i - 0.5)
			K:box("HomeDrawerFront", V3(x1 - x0 - 0.1, hh - 0.06, 0.04), F * CF((x0 + x1) / 2, yc, z1 - 0.03), { c = c3(240, 244, 246), m = M.Glass, t = 0.45 })
			K:box("HomeDrawerContent", V3(x1 - x0 - 0.3, hh - 0.25, 0.04), F * CF((x0 + x1) / 2, yc - 0.03, z1 - 0.12), { c = cols[(i + self.seed) % #cols + 1], m = M.Fabric })
			K:box("HomeDrawerGrip", V3((x1 - x0) * 0.4, 0.06, 0.05), F * CF((x0 + x1) / 2, yc + hh / 2 - 0.1, z1 + 0.0), lk(250, 250, 250))
		end
		boxF(K, "HomeDrawerTop", F, V3(x0 - 0.02, y1 - 0.04, z0), V3(x1 + 0.02, y1 + 0.02, z1 - 0.02), lk(250, 250, 248))
	end)
	self:hide(r.part)
	return F, info
end

-- 날개형 빨래 건조대 + 빨래 (원래 건조대 자리 상자)
function C:dryingRack(mn: Vector3, mx: Vector3, parts: { BasePart }, laundryCols: { Color3 })
	local K = self.K
	local alongX = (mx.X - mn.X) >= (mx.Z - mn.Z)
	local c = (mn + mx) / 2
	local len = if alongX then mx.X - mn.X else mx.Z - mn.Z
	local wid = math.max(0.9, if alongX then mx.Z - mn.Z else mx.X - mn.X)
	local F = CF(c.X, 0, c.Z) * (if alongX then CFrame.new() else ANG(0, PI / 2, 0))
	local top = math.max(2.6, mx.Y)
	local rl = lk(224, 226, 230, M.Metal)
	K:free(function()
		-- X 다리 (양 끝)
		for _, sx in { -1, 1 } do
			local x = sx * (len / 2 - 0.05)
			K:seg("HomeRackLeg", F * V3(x, 0.02, -wid / 2), F * V3(x, top, wid / 2 - 0.1), 0.06, rl)
			K:seg("HomeRackLeg", F * V3(x, 0.02, wid / 2), F * V3(x, top, -wid / 2 + 0.1), 0.06, rl)
			K:ball("HomeRackFoot", 0.08, F * CF(x, 0.03, -wid / 2), L.rubber)
			K:ball("HomeRackFoot", 0.08, F * CF(x, 0.03, wid / 2), L.rubber)
		end
		-- 윗 가로대 3 + 날개 (펼친 쪽)
		for i = -1, 1 do
			K:seg("HomeRackBar", F * V3(-len / 2, top, i * wid * 0.32), F * V3(len / 2, top, i * wid * 0.32), 0.05, rl)
		end
		for _, sz in { -1, 1 } do
			K:seg("HomeRackWing", F * V3(-len / 2, top, sz * wid * 0.32), F * V3(-len / 2, top - 0.9, sz * (wid * 0.32 + 0.55)), 0.04, rl)
			K:seg("HomeRackWing", F * V3(len / 2, top, sz * wid * 0.32), F * V3(len / 2, top - 0.9, sz * (wid * 0.32 + 0.55)), 0.04, rl)
			K:seg("HomeRackWingBar", F * V3(-len / 2, top - 0.9, sz * (wid * 0.32 + 0.55)), F * V3(len / 2, top - 0.9, sz * (wid * 0.32 + 0.55)), 0.04, rl)
		end
		-- 빨래: 수건 · 티셔츠 · 양말 (가로대에 걸침)
		local x = -len / 2 + 0.4
		local i = 0
		while x < len / 2 - 0.3 do
			i += 1
			local col = laundryCols[(i - 1) % #laundryCols + 1]
			local kind = i % 3
			local zz = ((i % 3) - 1) * wid * 0.32
			if kind == 0 then
				K:box("HomeLaundryTowel", V3(0.75, 1.2, 0.04), F * CF(x, top - 0.6, zz + 0.03), { c = col, m = M.Fabric })
				K:box("HomeLaundryTowelBand", V3(0.75, 0.08, 0.045), F * CF(x, top - 1.05, zz + 0.03), { c = col:Lerp(Color3.new(0, 0, 0), 0.2), m = M.Fabric })
				x += 0.85
			elseif kind == 1 then
				K:box("HomeLaundryShirt", V3(0.85, 0.95, 0.04), F * CF(x, top - 0.5, zz + 0.03), { c = col, m = M.Fabric })
				K:box("HomeLaundrySleeve", V3(1.2, 0.25, 0.04), F * CF(x, top - 0.15, zz + 0.03), { c = col, m = M.Fabric })
				x += 0.95
			else
				for j = 0, 1 do
					K:box("HomeLaundrySock", V3(0.16, 0.5, 0.04), F * CF(x + j * 0.22, top - 0.25, zz + 0.03), { c = col, m = M.Fabric })
					K:box("HomeLaundrySockClip", V3(0.08, 0.08, 0.06), F * CF(x + j * 0.22, top + 0.02, zz + 0.03), lk(90, 200, 230))
				end
				x += 0.5
			end
		end
	end)
	for _, p in parts do
		self:hide(p)
	end
end

-- 천장형 빨래 건조대 (창가): near = 창 쪽 점. 창에서 1.6~2.4 안쪽, 천장 브래킷 2 + 봉 2 + 줄 + 빨래
function C:ceilingRack(nearP: Vector3, cols: { Color3 })
	local K = self.K
	-- 창 앞 수평 방향: 가까운 벽 법선 쪽으로 안쪽
	local best, bd = nil, math.huge
	for _, sg in self.segs do
		if sg.len > 4 and sg.top > 6 then
			local q = sg.p0 + sg.t * math.clamp((nearP - sg.p0):Dot(sg.t), 0, sg.len)
			local d = (V3(q.X, 0, q.Z) - V3(nearP.X, 0, nearP.Z)).Magnitude
			if d < bd then
				best, bd = sg, d
			end
		end
	end
	if not best then
		return
	end
	local q = best.p0 + best.t * math.clamp((nearP - best.p0):Dot(best.t), 2.4, best.len - 2.4)
	local len = 4.2
	local h = self:ceilAt(q.X, q.Z)
	-- 침대 · 소파 위는 피해서 봉 길이 방향(벽 따라)으로 조금씩 밀어 봄
	local F = nil
	for _, du in { 0, -1.5, 1.5, -3, 3, -4.5, 4.5 } do
		local c = q + best.t * du + best.n * 1.9
		local cf = CFrame.fromMatrix(V3(c.X, 0, c.Z), best.t, YA, best.n)
		local mn, mx = laabb(cf * CF(0, h - 1.1, 0), V3(len + 0.2, 2.2, 1.6))
		local clear = self:mine(V3(c.X, 0.5, c.Z)) and self:ceilFree(c.X, c.Z, 0.3)
		if clear and self:boxFree(mn, mx, { noKeep = true }) then
			F = cf
			self:use(mn, mx)
			break
		end
	end
	if not F then
		return
	end
	local rl = lk(230, 232, 236, M.Metal)
	K:free(function()
		local y = h - 0.9
		for _, sx in { -len / 2 + 0.3, len / 2 - 0.3 } do
			K:box("HomeCeilRackBracket", V3(0.3, 0.06, 0.9), F * CF(sx, h - 0.03, 0), rl)
			for _, sz in { -0.3, 0.3 } do
				K:seg("HomeCeilRackCord", F * V3(sx, h - 0.06, sz), F * V3(sx, y, sz), 0.03, lk(200, 200, 204))
			end
			K:box("HomeCeilRackHanger", V3(0.06, 0.08, 0.7), F * CF(sx, y, 0), rl)
		end
		for _, sz in { -0.3, 0.3 } do
			K:cyl("HomeCeilRackBar", len, 0.07, F * CF(0, y, sz), rl)
		end
		-- 빨래 (봉 아래로): 수건 · 티셔츠 · 양말 걸이
		local x = -len / 2 + 0.55
		local i = 0
		while x < len / 2 - 0.4 do
			i += 1
			local col = cols[(i - 1) % #cols + 1]
			local sz = if i % 2 == 0 then 0.3 else -0.3
			if i % 3 == 1 then
				K:box("HomeLaundryTowel", V3(0.8, 1.0, 0.04), F * CF(x, y - 0.53, sz + 0.04), { c = col, m = M.Fabric })
				x += 0.95
			elseif i % 3 == 2 then
				K:ring("HomeLaundryHanger", F * CF(x, y - 0.02, sz) * ANG(0, 0, 0), 0.06, 0.02, 5, lk(240, 240, 240), PI * 0.1, PI * 1.9)
				K:box("HomeLaundryShirt", V3(0.85, 0.9, 0.04), F * CF(x, y - 0.6, sz + 0.03), { c = col, m = M.Fabric })
				K:box("HomeLaundrySleeve", V3(1.25, 0.24, 0.04), F * CF(x, y - 0.27, sz + 0.03), { c = col, m = M.Fabric })
				x += 1.0
			else
				-- 집게 원형 양말걸이
				K:ring("HomeSockHangerRing", F * CF(x, y - 0.35, sz) * ANG(PI / 2, 0, 0), 0.32, 0.03, 8, lk(110, 190, 230))
				K:seg("HomeSockHangerHook", F * V3(x, y - 0.02, sz), F * V3(x, y - 0.35, sz), 0.025, lk(110, 190, 230))
				for j = 0, 3 do
					local a = j * PI / 2
					K:box("HomeLaundrySock", V3(0.14, 0.42, 0.04), F * CF(x + math.cos(a) * 0.32, y - 0.58, sz + math.sin(a) * 0.32), { c = ({ c3(250, 250, 250), c3(40, 40, 44), c3(150, 150, 156) })[(j + i) % 3 + 1], m = M.Fabric })
				end
				x += 0.85
			end
		end
	end)
end

-- 소형 냉장고 (body rec · door rec)
function C:miniFridge(body: any, door: any?)
	local K = self.K
	local F, info = propFrame(self, body.part)
	local x0, x1, y1, z0, z1 = info.min.X, info.max.X, info.max.Y, info.min.Z, info.max.Z
	if door then
		local dmn, dmx = laabb(self.V.cf:ToObjectSpace(door.part.CFrame), door.part.Size)
		local _ = dmn
		z1 = math.max(z1, (F:PointToObjectSpace((dmx + dmn) / 2)).Z + door.part.Size.Z * 0.5)
	end
	local fl = withC(L.white, body.part.Color)
	K:free(function()
		K:rbox("HomeFridgeBody", V3(x1 - x0, y1 - 0.08, z1 - z0 - 0.16), 0.06, F * CF((x0 + x1) / 2, 0.08 + (y1 - 0.08) / 2, (z0 + z1 - 0.16) / 2), fl)
		K:rbox("HomeFridgeDoor", V3(x1 - x0 - 0.04, y1 - 0.14, 0.14), 0.05, F * CF((x0 + x1) / 2, 0.08 + (y1 - 0.08) / 2, z1 - 0.08), tint(fl, -0.02))
		K:box("HomeFridgeGasket", V3(x1 - x0 - 0.06, y1 - 0.16, 0.02), F * CF((x0 + x1) / 2, 0.08 + (y1 - 0.08) / 2, z1 - 0.16), lk(200, 200, 198))
		K:box("HomeFridgeHandle", V3(0.08, 0.6, 0.06), F * CF(x1 - 0.18, y1 * 0.62, z1 + 0.02), lk(200, 202, 206, M.Metal))
		K:box("HomeFridgeBadge", V3(0.3, 0.06, 0.005), F * CF((x0 + x1) / 2, y1 - 0.25, z1 + 0.002), lk(160, 162, 166, M.Metal))
		for _, sx in { x0 + 0.15, x1 - 0.15 } do
			K:box("HomeFridgeFoot", V3(0.14, 0.08, 0.14), F * CF(sx, 0.04, z1 - 0.3), lk(40, 40, 42))
		end
		-- 냉장고 자석 + 전단지 (배달 쿠폰)
		K:box("HomeFridgeMagnet", V3(0.22, 0.22, 0.03), F * CF(x0 + 0.35, y1 * 0.7, z1 + 0.012), lk(240, 120, 40))
		K:box("HomeFridgeFlyer", V3(0.5, 0.7, 0.008), F * CF(x0 + 0.42, y1 * 0.45, z1 + 0.006) * ANG(0, 0, 0.05), lk(250, 248, 236))
		K:text("HomeFridgeFlyerText", 0.44, 0.5, F * CF(x0 + 0.42, y1 * 0.45, z1 + 0.011) * ANG(0, 0, 0.05), "치킨\n배달\n☎ 051", { fg = c3(200, 40, 30), font = Enum.Font.GothamBold, d = 0.004, free = true })
	end)
	self:hide(body.part)
	if door then
		self:hide(door.part)
	end
	for _, q in (body.part.Parent and body.part.Parent:GetDescendants() or {}) do
		if q:IsA("BasePart") and (q.Name == "DoorGap" or q.Name == "Handle") then
			self:hide(q)
		end
	end
	return F, info
end

-- 전자레인지 (rec), 전기포트 (base rec, body rec)
function C:microwave(r: any, doorRec: any?)
	local K = self.K
	local F, info = propFrame(self, r.part)
	local x0, x1, y0, y1, z0, z1 = info.min.X, info.max.X, info.min.Y, info.max.Y, info.min.Z, info.max.Z
	local bl = withC(L.white, r.part.Color)
	K:free(function()
		K:rbox("HomeMicrowave", V3(x1 - x0, y1 - y0, z1 - z0), 0.05, F * CF((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), bl)
		local dw = (x1 - x0) * 0.68
		K:box("HomeMicrowaveDoor", V3(dw, (y1 - y0) - 0.14, 0.04), F * CF(x0 + dw / 2 + 0.05, (y0 + y1) / 2, z1 + 0.01), lk(40, 42, 46))
		K:box("HomeMicrowaveWindow", V3(dw - 0.3, (y1 - y0) - 0.36, 0.01), F * CF(x0 + dw / 2 + 0.05, (y0 + y1) / 2, z1 + 0.035), { c = c3(20, 22, 26), m = M.Glass, r = 0.2 })
		K:box("HomeMicrowaveHandle", V3(0.06, (y1 - y0) - 0.3, 0.06), F * CF(x0 + dw, (y0 + y1) / 2, z1 + 0.05), lk(210, 212, 216, M.Metal))
		local px = x1 - (x1 - x0 - dw) / 2
		K:box("HomeMicrowavePanel", V3((x1 - x0 - dw) - 0.1, (y1 - y0) - 0.14, 0.02), F * CF(px, (y0 + y1) / 2, z1 + 0.005), lk(230, 230, 228))
		K:box("HomeMicrowaveLCD", V3(0.28, 0.1, 0.01), F * CF(px, y1 - 0.18, z1 + 0.018), lk(30, 34, 30))
		K:text("HomeMicrowaveTime", 0.26, 0.09, F * CF(px, y1 - 0.18, z1 + 0.024), "12:30", { fg = c3(110, 230, 140), glow = 1.3, font = Enum.Font.Code, d = 0.004, free = true })
		K:cyl("HomeMicrowaveDial", 0.05, 0.22, F * CF(px, (y0 + y1) / 2 - 0.08, z1 + 0.03) * ANG(0, PI / 2, 0), lk(200, 200, 200))
		for i = 0, 2 do
			K:box("HomeMicrowaveBtn", V3(0.08, 0.05, 0.015), F * CF(px - 0.1 + i * 0.1, y0 + 0.14, z1 + 0.02), lk(180, 180, 182))
		end
	end)
	self:hide(r.part)
	if doorRec then
		self:hide(doorRec.part)
	end
end
function C:kettle(baseRec: any?, bodyRec: any)
	local K = self.K
	local c = bodyRec.c
	local y0 = if baseRec then baseRec.min.Y else bodyRec.min.Y
	local F = CF(c.X, y0, c.Z)
	K:free(function()
		K:disc("HomeKettleBase", 0.6, 0.07, F * CF(0, 0.035, 0), lk(40, 40, 44))
		K:vcyl("HomeKettleBody", 0.62, 0.48, F * CF(0, 0.07 + 0.31, 0), lk(206, 208, 212, M.Metal))
		K:disc("HomeKettleLid", 0.38, 0.05, F * CF(0, 0.72, 0), lk(40, 40, 44))
		K:box("HomeKettleHandle", V3(0.08, 0.5, 0.1), F * CF(-0.3, 0.42, 0), lk(40, 40, 44))
		K:bar("HomeKettleHandleTop", F * V3(-0.3, 0.66, 0), F * V3(-0.18, 0.7, 0), 0.08, 0.06, lk(40, 40, 44))
		K:wedge("HomeKettleSpout", V3(0.12, 0.14, 0.2), F * CF(0.27, 0.62, 0) * ANG(0, -PI / 2, 0), lk(206, 208, 212, M.Metal))
		K:box("HomeKettleWindow", V3(0.08, 0.36, 0.02), F * CF(0.12, 0.38, 0.23), { c = c3(170, 210, 230), m = M.Glass, t = 0.3 })
		K:box("HomeKettleLED", V3(0.05, 0.03, 0.01), F * CF(-0.3, 0.2, 0.06), L.neon(c3(80, 160, 255)))
	end)
	if baseRec then
		self:hide(baseRec.part)
	end
	self:hide(bodyRec.part)
end

-- 롤 블라인드 (BlindRoll + Blind). 상호작용: 올리고 내리기
function C:rollBlind(roll: any, blind: any)
	local K = self.K
	local rp: BasePart = roll.part
	local bp: BasePart = blind.part
	local dcf = self:wallFace(bp)
	local w = math.max(roll.size.X, roll.size.Z)
	local top = roll.c.Y
	local lc = self.V.cf:ToObjectSpace(bp.CFrame)
	local n = if dcf then dcf.ZVector else lc.ZVector
	n = V3(n.X, 0, n.Z).Unit
	local face = faceCF(V3(roll.c.X, top, roll.c.Z), n)
	local fabricL = { c = bp.Color, m = M.Fabric }
	local downLen = math.max(0.6, top - blind.min.Y)
	local fullLen = math.max(downLen, top - (self.sillY or (top - 2.2)))
	local parts = {}
	K:free(function()
		K:box("HomeBlindCassette", V3(w + 0.1, 0.32, 0.3), face * CF(0, 0, -0.02), lk(246, 244, 240))
		K:box("HomeBlindEndCap", V3(0.06, 0.34, 0.32), face * CF(-w / 2 - 0.07, 0, -0.02), lk(220, 220, 218))
		K:box("HomeBlindEndCap", V3(0.06, 0.34, 0.32), face * CF(w / 2 + 0.07, 0, -0.02), lk(220, 220, 218))
		local cloth = K:box("HomeBlindCloth", V3(w - 0.05, downLen, 0.02), face * CF(0, -0.16 - downLen / 2, -0.06), fabricL)
		local barP = K:box("HomeBlindBar", V3(w - 0.03, 0.08, 0.06), face * CF(0, -0.16 - downLen, -0.06), lk(236, 236, 232))
		local chain = K:box("HomeBlindChain", V3(0.03, 1.6, 0.03), face * CF(w / 2 - 0.1, -0.16 - 0.8, 0.04), lk(230, 230, 230))
		parts = { cloth = cloth, bar = barP, chain = chain }
	end)
	self:hide(rp)
	self:hide(bp)
	self.blind = { parts = parts, face = face, w = w, down = downLen, full = fullLen, state = "part" }
end

-- 협탁 (상자 + 서랍 선) : 원목 협탁 + 서랍 손잡이 + 스탠드 받침 (갓은 테마 파트라 그대로)
function C:nightstand(r: any)
	local K = self.K
	local F, info = propFrame(self, r.part)
	local x0, x1, y1, z0, z1 = info.min.X, info.max.X, info.max.Y, info.min.Z, info.max.Z
	local wl = if r.part.Material == M.Wood then from({ color = r.part.Color }, L.oak, M.Wood) else withC(L.white, r.part.Color)
	K:free(function()
		boxF(K, "HomeNightstandBody", F, V3(x0 + 0.03, 0.35, z0), V3(x1 - 0.03, y1 - 0.08, z1 - 0.03), wl)
		K:slab("HomeNightstandTop", x1 - x0, z1 - z0, 0.08, 0.04, F * CF((x0 + x1) / 2, y1 - 0.04, (z0 + z1) / 2), wl)
		for _, sx in { x0 + 0.12, x1 - 0.12 } do
			for _, sz in { z0 + 0.12, z1 - 0.12 } do
				K:seg("HomeNightstandLeg", F * V3(sx, 0.36, sz), F * V3(sx + (if sx < 0 then -0.03 else 0.03), 0.02, sz + (if sz < 0 then -0.03 else 0.03)), 0.09, tint(wl, 0.1))
			end
		end
		local hh = (y1 - 0.45) / 2
		for i = 1, 2 do
			local yc = 0.38 + hh * (i - 0.5)
			K:box("HomeNightstandDrawer", V3(x1 - x0 - 0.12, hh - 0.05, 0.03), F * CF((x0 + x1) / 2, yc, z1 - 0.015), tint(wl, -0.03))
			K:box("HomeNightstandPull", V3(0.3, 0.04, 0.04), F * CF((x0 + x1) / 2, yc, z1 + 0.01), L.brass)
		end
	end)
	self:hide(r.part)
	return F, info
end

-- 붙박이장 / 옷장 (본체 rec): 문짝 · 손잡이 · 몰딩 · 걸레받이
function C:wardrobe(r: any, doors: number?)
	local K = self.K
	local F, info = propFrame(self, r.part)
	local x0, x1, y1, z0, z1 = info.min.X, info.max.X, info.max.Y, info.min.Z, info.max.Z
	local wl = withC(L.white, r.part.Color)
	local n = doors or math.max(2, math.floor((x1 - x0) / 1.5 + 0.5))
	local dw = (x1 - x0 - 0.08) / n
	local h = math.min(y1, self.H) - 0.02
	K:free(function()
		boxF(K, "HomeWardrobeBody", F, V3(x0, 0.3, z0), V3(x1, h, z1 - 0.05), wl)
		boxF(K, "HomeWardrobeKick", F, V3(x0 + 0.05, 0, z0 + 0.05), V3(x1 - 0.05, 0.3, z1 - 0.12), lk(40, 40, 42))
		for i = 1, n do
			local xc = x0 + 0.04 + dw * (i - 0.5)
			K:box("HomeWardrobeDoor", V3(dw - 0.03, h - 0.36, 0.05), F * CF(xc, 0.3 + (h - 0.3) / 2, z1 - 0.025), tint(wl, -0.02))
			local hx = if i % 2 == 1 then xc + dw / 2 - 0.16 else xc - dw / 2 + 0.16
			K:box("HomeWardrobeHandle", V3(0.05, 1.6, 0.05), F * CF(hx, 3.9, z1 + 0.03), lk(60, 60, 64, M.Metal))
		end
		if self.lux <= 3 then
			K:box("HomeWardrobeCrown", V3(x1 - x0 + 0.06, 0.12, 0.08), F * CF((x0 + x1) / 2, h - 0.06, z1 - 0.02), tint(wl, 0.04))
		end
	end)
	self:hide(r.part)
	for _, q in (r.part.Parent and r.part.Parent:GetDescendants() or {}) do
		if q:IsA("BasePart") and (q.Name == "DoorSeam" or q.Name == "Handle") then
			self:hide(q)
		end
	end
	return F, info
end

-------------------------------------------------------------------------------------------------
-- 자리 찾기 도우미 (바닥: 벽에 등 대고 / 벽: 높이 범위)
-------------------------------------------------------------------------------------------------
-- 벽에 등을 대는 바닥 소품 자리: 반환 pcf (+Z = 방 쪽), seg
function C:floorAlongWall(w: number, d: number, h: number, opts: any?): (CFrame?, any?)
	local o: any = opts or {}
	local best, bs, bseg = nil, math.huge, nil
	for _, s in self.segs do
		if s.bot > 0.25 or s.top < math.min(h, 3) or s.len < w + 0.3 then
			continue
		end
		if o.filter and not o.filter(s) then
			continue
		end
		local u = w / 2 + 0.15
		self:yield()
		while u <= s.len - w / 2 - 0.15 do
			local center = s.p0 + s.t * u + s.n * ((o.gap or 0.08) + d / 2)
			local pcf = CFrame.fromMatrix(V3(center.X, 0, center.Z), s.t, YA, s.n)
			local score = if o.score then o.score(pcf, s) else 0
			if score < bs then
				-- 미리 검사 (예약 없이)
				local c = pcf * CF(0, h / 2, 0)
				local mn, mx = laabb(c, V3(w, h, d))
				local ok = true
				for _, q in { V3(mn.X, 0.5, mn.Z), V3(mx.X, 0.5, mn.Z), V3(mn.X, 0.5, mx.Z), V3(mx.X, 0.5, mx.Z) } do
					if not self:mine(q) or self:insideWall(q) then
						ok = false
						break
					end
				end
				if ok and self:boxFree(mn, mx, { allKeep = true }) then
					local wallHit = false
					for _, wl in self.walls do
						if boxHit(mn, mx, wl.mn, wl.mx, 0.01) then
							wallHit = true
							break
						end
					end
					if not wallHit then
						best, bs, bseg = pcf, score, s
					end
				end
			end
			u += o.step or 0.35
		end
	end
	if best and self:floorSpot(best, V3(w, h, d), o.pad) then
		return best, bseg
	end
	return nil, nil
end

-- 자유 바닥 자리 (후보 점 목록 중 처음 되는 곳)
function C:floorAt(cands: { CFrame }, size: Vector3, pad: number?): CFrame?
	for _, pcf in cands do
		if self:floorSpot(pcf, size, pad) then
			return pcf
		end
	end
	return nil
end

-- 어떤 점에서 가까울수록 좋은 점수
-- (바닥: score(pcf, seg) / 벽: score(seg, u, dcf) 둘 다 받음)
local function near(p: Vector3): (any, any?, any?) -> number
	return function(a: any, _b: any?, c: any?)
		local cf: CFrame = if typeof(a) == "CFrame" then a else c
		return (V3(cf.Position.X, 0, cf.Position.Z) - V3(p.X, 0, p.Z)).Magnitude
	end
end
local function far(p: Vector3): (any, any?, any?) -> number
	local f = near(p)
	return function(a: any, b: any?, c: any?)
		return -f(a, b, c)
	end
end
T.near, T.far = near, far

-------------------------------------------------------------------------------------------------
-- 생활 소품 (바닥 · 벽 · 가구 위)
-------------------------------------------------------------------------------------------------
local P = {}
T.P = P

-- 멀티탭 + 플러그 3개 + 전선 (pcf 바닥)
function P.powerStrip(K: any, pcf: CFrame, look: any?): BasePart
	local l = look or lk(244, 244, 240)
	local main = K:rbox("HomePowerStrip", V3(1.1, 0.16, 0.3), 0.05, pcf * CF(0, 0.08, 0), l)[1]
	for i = 0, 3 do
		K:box("HomePowerStripSwitch", V3(0.1, 0.02, 0.1), pcf * CF(-0.42 + i * 0.27, 0.165, -0.08), L.neon(c3(255, 80, 60), 0.25))
		K:cyl("HomePowerStripSocket", 0.012, 0.14, pcf * CF(-0.42 + i * 0.27, 0.166, 0.06) * ANG(0, 0, PI / 2), lk(220, 220, 216))
	end
	for i = 0, 1 do
		K:box("HomePowerStripPlug", V3(0.13, 0.16, 0.14), pcf * CF(-0.42 + i * 0.27, 0.24, 0.06), lk(30, 30, 32))
		K:seg("HomePowerStripCord", pcf * V3(-0.42 + i * 0.27, 0.3, 0.06), pcf * V3(-0.6 - i * 0.4, 0.03, 0.6 + i * 0.3), 0.035, lk(30, 30, 32))
	end
	K:seg("HomePowerStripCord", pcf * V3(0.55, 0.06, 0), pcf * V3(0.85, 0.03, -0.25), 0.04, l)
	return main
end
-- 휴지통 (페달식 / 원형)
function P.trashBin(K: any, pcf: CFrame, look: any?)
	local l = look or lk(236, 236, 232)
	K:vcyl("HomeTrashBin", 1.15, 0.85, pcf * CF(0, 0.575, 0), l)
	K:vcyl("HomeTrashLid", 0.08, 0.88, pcf * CF(0, 1.19, 0), tint(l, 0.08))
	K:vcyl("HomeTrashBag", 0.08, 0.8, pcf * CF(0, 1.14, 0), lk(80, 84, 90, M.Fabric))
	K:box("HomeTrashPedal", V3(0.25, 0.05, 0.16), pcf * CF(0, 0.06, 0.46), lk(80, 80, 84))
end
-- 빨래 바구니
function P.laundryBasket(K: any, pcf: CFrame, cols: { Color3 })
	K:rbox("HomeBasket", V3(1.4, 1.2, 1.0), 0.12, pcf * CF(0, 0.6, 0), { c = c3(200, 214, 226), m = M.Plastic })
	for i = 1, 4 do
		K:box("HomeBasketSlot", V3(0.9, 0.06, 0.01), pcf * CF(0, 0.3 + i * 0.18, 0.5), lk(170, 186, 200))
	end
	for i, c in cols do
		K:ell("HomeBasketLaundry", V3(0.8, 0.35, 0.6), pcf * CF((i - 2) * 0.3, 1.15 + i * 0.04, (i % 2) * 0.15 - 0.08) * ANG(0, i, 0.2), { c = c, m = M.Fabric })
	end
end
-- 소화기 (바닥 받침 + 본체)
function P.extinguisher(K: any, pcf: CFrame)
	K:box("HomeExtStand", V3(0.75, 0.1, 0.75), pcf * CF(0, 0.05, 0), lk(190, 30, 30))
	K:vcyl("HomeExtBody", 1.35, 0.55, pcf * CF(0, 0.1 + 0.675, 0), lk(206, 24, 28))
	K:ell("HomeExtDome", V3(0.55, 0.26, 0.55), pcf * CF(0, 1.45, 0), lk(206, 24, 28))
	K:vcyl("HomeExtValve", 0.14, 0.18, pcf * CF(0, 1.62, 0), lk(40, 40, 42))
	K:box("HomeExtHandle", V3(0.45, 0.05, 0.1), pcf * CF(0.07, 1.74, 0) * ANG(0, 0, -0.2), lk(40, 40, 42))
	K:ball("HomeExtGauge", 0.15, pcf * CF(0, 1.63, 0.1), L.white)
	K:seg("HomeExtHose", pcf * V3(-0.06, 1.62, -0.08), pcf * V3(-0.26, 0.5, -0.27), 0.07, lk(30, 30, 32))
	K:text("HomeExtLabel", 0.4, 0.46, pcf * CF(0, 0.9, 0.28), "소화기\nABC 3.3kg", { fg = c3(255, 255, 255), bg = c3(40, 40, 40), d = 0.01, free = true })
end
-- 슬리퍼 한 켤레 (바닥)
function P.slippers(K: any, pcf: CFrame, col: Color3)
	for _, sx in { -0.22, 0.22 } do
		K:slab("HomeSlipperSole", 0.38, 0.92, 0.07, 0.17, pcf * CF(sx, 0.035, 0) * ANG(0, sx * 0.3, 0), lk(40, 40, 44, M.Rubber))
		K:ell("HomeSlipperStrap", V3(0.4, 0.22, 0.38), pcf * CF(sx, 0.1, 0.18) * ANG(0, sx * 0.3, 0), { c = col, m = M.Fabric })
	end
end
-- 백팩 (바닥에 세워 둠)
function P.backpack(K: any, pcf: CFrame, col: Color3)
	K:rbox("HomeBackpack", V3(1.1, 1.5, 0.6), 0.22, pcf * CF(0, 0.75, 0) * ANG(math.rad(-6), 0, 0), { c = col, m = M.Fabric })
	K:rbox("HomeBackpackPocket", V3(0.8, 0.6, 0.2), 0.1, pcf * CF(0, 0.5, 0.33) * ANG(math.rad(-6), 0, 0), { c = col:Lerp(Color3.new(0, 0, 0), 0.15), m = M.Fabric })
	K:box("HomeBackpackZip", V3(0.7, 0.03, 0.03), pcf * CF(0, 0.82, 0.43) * ANG(math.rad(-6), 0, 0), lk(30, 30, 30))
	K:ring("HomeBackpackHandle", pcf * CF(0, 1.52, -0.05) * ANG(0, 0, 0), 0.15, 0.05, 5, lk(30, 30, 30), 0, PI)
end
-- 벽 달력 (dcf 벽 표면)
function P.calendar(K: any, dcf: CFrame, month: string?)
	K:box("HomeCalendar", V3(1.1, 1.5, 0.02), dcf * CF(0, 0, 0.01), lk(252, 252, 250))
	K:box("HomeCalendarPhoto", V3(1.0, 0.6, 0.005), dcf * CF(0, 0.38, 0.023), lk(120, 170, 200))
	K:box("HomeCalendarPhotoSea", V3(1.0, 0.25, 0.006), dcf * CF(0, 0.2, 0.024), lk(60, 110, 160))
	K:text("HomeCalendarMonth", 0.8, 0.16, dcf * CF(0, -0.03, 0.022), month or "10월 OCTOBER", { fg = c3(40, 40, 50), d = 0.004, free = true })
	for r = 0, 3 do
		for c = 0, 6 do
			local red = c == 0
			K:box("HomeCalendarDay", V3(0.1, 0.07, 0.004), dcf * CF(-0.42 + c * 0.14, -0.2 - r * 0.13, 0.024), if red then lk(220, 60, 60) else lk(60, 60, 66))
		end
	end
	K:ring("HomeCalendarCircle", dcf * CF(-0.14, -0.33, 0.027), 0.07, 0.015, 6, lk(220, 40, 40))
	K:box("HomeCalendarNail", V3(0.04, 0.04, 0.05), dcf * CF(0, 0.78, 0.02), L.chrome)
end
-- 벽시계 (실제 게임 시각으로 돔)
function P.wallClock(C_: any, dcf: CFrame, dia: number, look: any?)
	local K = C_.K
	local hr, mn = Props.clock(K, dcf, dia, { frame = look or L.blackMetal })
	Interact.clock(K, hr, mn, dcf, dia)
end
-- 피난안내도 (아크릴 판)
function P.evacuation(K: any, dcf: CFrame)
	K:box("HomeEvacPlate", V3(1.2, 0.85, 0.03), dcf * CF(0, 0, 0.015), { c = c3(250, 250, 248), m = M.Glass, t = 0.1 })
	K:text("HomeEvacTitle", 1.0, 0.14, dcf * CF(0, 0.32, 0.034), "피난안내도 · 현위치 ●", { fg = c3(20, 120, 60), d = 0.004, free = true })
	K:box("HomeEvacMap", V3(0.9, 0.5, 0.005), dcf * CF(0, -0.07, 0.034), lk(230, 236, 230))
	for i = 0, 5 do
		K:box("HomeEvacRoom", V3(0.12, 0.16, 0.006), dcf * CF(-0.36 + i * 0.145, 0.04, 0.036), lk(200, 210, 200))
	end
	K:box("HomeEvacArrow", V3(0.6, 0.04, 0.006), dcf * CF(0, -0.12, 0.037), lk(30, 160, 70))
	K:ball("HomeEvacHere", 0.06, dcf * CF(-0.18, 0.02, 0.04), L.ledRed)
end
-- 액자 여러 개 (가족사진)
function P.photoCluster(C_: any, dcf: CFrame, n: number, seed: number)
	local K = C_.K
	local layout = { { 0, 0, 1.4, 1.0 }, { -1.15, 0.15, 0.7, 0.9 }, { 1.05, -0.1, 0.6, 0.8 }, { -1.0, -0.75, 0.6, 0.45 }, { 0.9, 0.62, 0.5, 0.4 } }
	for i = 1, math.min(n, #layout) do
		local l = layout[i]
		local f = artFrame(K, dcf * CF(l[1], l[2], 0), l[3], l[4], { frame = if i % 2 == 0 then L.walnut else lk(246, 246, 244), border = 0.06, depth = 0.06, mat = lk(250, 250, 248) })
		local iw, ih = l[3] - 0.24, l[4] - 0.24
		K:box("HomePhotoImg", V3(iw, ih, 0.006), f * CF(0, 0, 0.003), { c = c3(150 + math.floor(rnd(seed, i) * 60), 160, 175), m = M.SmoothPlastic })
		K:box("HomePhotoSky", V3(iw, ih * 0.4, 0.007), f * CF(0, ih * 0.3, 0.004), lk(160, 200, 230))
		-- 사람 실루엣 2
		for j = -1, 1, 2 do
			K:ell("HomePhotoPerson", V3(iw * 0.18, ih * 0.5, 0.004), f * CF(j * iw * 0.14, -ih * 0.12, 0.008), lk(70 + j * 10, 60, 60))
			K:ball("HomePhotoHead", math.min(iw, ih) * 0.14, f * CF(j * iw * 0.14, ih * 0.18, 0.008), lk(230, 200, 180))
		end
	end
end
-- 로봇청소기 + 충전 도크 (pcf 바닥, +Z 방 쪽). 반환 { robot parts, led }
function P.robotVacuum(K: any, pcf: CFrame): any
	K:rbox("HomeRobotDock", V3(0.75, 0.65, 0.35), 0.08, pcf * CF(0, 0.325, -0.1), lk(50, 52, 56))
	local dockLed = K:box("HomeRobotDockLED", V3(0.2, 0.04, 0.01), pcf * CF(0, 0.55, 0.08), L.neon(c3(90, 220, 180)))
	local parts = {}
	local rc = pcf * CF(0, 0, 0.55)
	table.insert(parts, K:vcyl("HomeRobot", 0.28, 1.05, rc * CF(0, 0.16, 0), lk(246, 246, 244)))
	table.insert(parts, K:vcyl("HomeRobotBumper", 0.14, 1.07, rc * CF(0, 0.09, 0), lk(60, 62, 66)))
	table.insert(parts, K:vcyl("HomeRobotLidar", 0.09, 0.28, rc * CF(0, 0.35, -0.15), lk(40, 40, 44)))
	table.insert(parts, K:box("HomeRobotButton", V3(0.14, 0.01, 0.06), rc * CF(0, 0.305, 0.18), L.neon(c3(90, 220, 180))))
	return { parts = parts, dockLed = dockLed, home = rc }
end
-- 큰 거울 (벽에 기대 세운 전신거울: pcf 바닥, 등이 벽)
function P.leanMirror(K: any, pcf: CFrame, h: number, look: any?)
	local fr = look or L.walnut
	local tilt = ANG(math.rad(-6), 0, 0)
	local c = pcf * CF(0, 0, 0.32) * tilt
	K:box("HomeMirrorFrame", V3(1.6, h, 0.12), c * CF(0, h / 2, 0), fr)
	K:box("HomeMirrorGlass", V3(1.4, h - 0.2, 0.02), c * CF(0, h / 2, 0.065), L.mirror)
end
-- 가습기
function P.humidifier(K: any, pcf: CFrame)
	K:vcyl("HomeHumidBody", 0.9, 0.7, pcf * CF(0, 0.45, 0), lk(246, 246, 244))
	K:vcyl("HomeHumidTank", 0.4, 0.62, pcf * CF(0, 0.8, 0), { c = c3(200, 226, 240), m = M.Glass, t = 0.35 })
	K:vcyl("HomeHumidTop", 0.08, 0.5, pcf * CF(0, 1.04, 0), lk(246, 246, 244))
	K:box("HomeHumidLED", V3(0.12, 0.04, 0.01), pcf * CF(0, 0.3, 0.35), L.neon(c3(80, 160, 255)))
end
T.P = P

-------------------------------------------------------------------------------------------------
-- 방별 생활 소품 · 붙박이 · 상호작용
-------------------------------------------------------------------------------------------------
local ROOM: { [string]: (any) -> () } = {}

-- 공통: 이 방 소품 리스킨 (이름이 있으면)
function C:commonReskins()
	-- 펜던트 줄 · 와이어 위: 천장 캐노피 (줄이 천장에 그냥 박혀 보이지 않게)
	for _, r in self:ownNamed("Cable", "PendantCord") do
		pcall(function()
			if r.size.Y < 0.5 or r.size.X > 0.2 or r.size.Z > 0.2 then
				return
			end
			local h = self:ceilAt(r.c.X, r.c.Z)
			if math.abs(r.max.Y - h) > 0.35 then
				return
			end
			local K = self.K
			local look = if self.lux >= 5 then L.brass elseif self.lux >= 3 then lk(30, 30, 32, M.Metal) else L.white
			K:free(function()
				K:disc("HomePendantCanopy", 0.42, 0.08, CF(r.c.X, h - 0.04, r.c.Z), look)
				K:disc("HomePendantGrip", 0.1, 0.12, CF(r.c.X, h - 0.14, r.c.Z), look)
			end)
		end)
	end
	-- 아트월 (대형 포세린 타일 · 마블 슬랩): 600x1200 타일 줄눈 (V 홈) — 고정색 마블이라 살짝 어두운 같은 색 줄
	for _, r in self:ownNamed("ArtWall") do
		pcall(function()
			local p: BasePart = r.part
			local back = self:wallFace(p)
			if not back then
				return
			end
			local lc = self.V.cf:ToObjectSpace(p.CFrame)
			local th = math.min(p.Size.X, p.Size.Z)
			local wid = math.max(p.Size.X, p.Size.Z)
			local front = back * CF(0, 0, th)
			local f = front * CF(0, lc.Position.Y - front.Position.Y, 0)
			local K = self.K
			local gl = { c = p.Color:Lerp(Color3.new(0, 0, 0), 0.22), m = M.SmoothPlastic }
			local cols = math.max(2, math.floor(wid / 2.3 + 0.5))
			local cw = wid / cols
			K:free(function()
				for k = 1, cols - 1 do
					K:box("HomeArtWallGrout", V3(0.03, p.Size.Y - 0.02, 0.012), f * CF(-wid / 2 + k * cw, 0, 0.004), gl)
				end
				local rows = math.max(1, math.floor(p.Size.Y / 4.2 + 0.5))
				for k = 1, rows - 1 do
					K:box("HomeArtWallGrout", V3(wid - 0.02, 0.03, 0.012), f * CF(0, -p.Size.Y / 2 + k * p.Size.Y / rows, 0.004), gl)
				end
			end)
		end)
	end
	-- 벽걸이 에어컨
	for _, r in self:ownNamed("WallAC") do
		pcall(function()
			self:wallAC(r)
		end)
	end
	-- 협탁 (갓은 테마 조명이라 그대로, 받침 · 기둥만)
	for ni, r in self:ownNamed("Nightstand") do
		pcall(function()
			local F, info = self:nightstand(r)
			for _, q in self:ownNamed("DrawerLine") do
				if math.abs(q.c.X - r.c.X) < r.size.X / 2 + 0.1 and math.abs(q.c.Z - r.c.Z) < r.size.Z / 2 + 0.1 and q.c.Y < r.max.Y then
					self:hide(q.part)
				end
			end
			-- 협탁 위 생활 소품 (스탠드 피해서 앞쪽 양 모서리)
			local lampX = nil
			for _, q in self:ownNamed("LampBase") do
				if math.abs(q.c.X - r.c.X) < r.size.X / 2 and math.abs(q.c.Z - r.c.Z) < r.size.Z / 2 then
					lampX = F:PointToObjectSpace(q.c).X
				end
			end
			local K = self.K
			local y = info.max.Y
			local x0, x1, z1 = info.min.X, info.max.X, info.max.Z
			local leftFree = not lampX or lampX > (x0 + x1) / 2 - 0.1
			local rightFree = not lampX or lampX < (x0 + x1) / 2 + 0.1
			K:free(function()
				local px = if leftFree then x0 + 0.3 else x1 - 0.3
				phone(K, F * CF(px, y, z1 - 0.38) * ANG(0, 0.35, 0), self.lux >= 3)
				K:seg("HomeChargeCable", F * V3(px, y + 0.02, z1 - 0.68), F * V3(px - 0.05, y + 0.01, info.min.Z + 0.05), 0.025, lk(240, 240, 240))
				local ox = if rightFree then x1 - 0.3 else x0 + 0.3
				if ni % 2 == 1 then
					if self.lux >= 4 then
						K:box("HomeNSTray", V3(0.55, 0.03, 0.4), F * CF(ox, y + 0.015, z1 - 0.35), L.brass)
						K:vcyl("HomeNSWatch", 0.05, 0.22, F * CF(ox - 0.1, y + 0.055, z1 - 0.35), L.goldMetal)
						K:vcyl("HomeNSRing", 0.03, 0.08, F * CF(ox + 0.12, y + 0.045, z1 - 0.3), L.goldMetal)
					else
						K:vcyl("HomeWaterGlass", 0.38, 0.2, F * CF(ox, y + 0.19, z1 - 0.32), L.glass(c3(220, 236, 240), 0.55))
						K:vcyl("HomeWater", 0.25, 0.17, F * CF(ox, y + 0.14, z1 - 0.32), L.glass(c3(190, 220, 236), 0.35))
					end
				else
					-- 디지털 알람시계 / 안경 + 책
					K:rbox("HomeAlarmClock", V3(0.5, 0.26, 0.2), 0.05, F * CF(ox, y + 0.13, z1 - 0.3), lk(40, 40, 44))
					K:text("HomeAlarmTime", 0.42, 0.16, F * CF(ox, y + 0.14, z1 - 0.195), "07:00", { fg = c3(255, 90, 70), glow = 1.4, font = Enum.Font.Code, d = 0.004, free = true })
				end
			end)
			local _ = ni

			-- 같은 모델의 스탠드 받침 · 기둥
			for _, q in (r.part.Parent and r.part.Parent:GetDescendants() or {}) do
				if q:IsA("BasePart") and (q.Name == "LampBase" or q.Name == "LampStem") then
					local lp = self.V.cf:PointToObjectSpace(q.Position)
					if math.abs(lp.X - r.c.X) < 1.2 and math.abs(lp.Z - r.c.Z) < 1.2 then
						local K = self.K
						K:free(function()
							if q.Name == "LampBase" then
								K:disc("HomeLampBase", math.max(q.Size.Y, q.Size.Z), 0.1, CF(lp.X, r.max.Y + 0.05, lp.Z), L.brass)
								K:ell("HomeLampBody", V3(0.5, 0.55, 0.5), CF(lp.X, r.max.Y + 0.35, lp.Z), lk(236, 230, 218, M.Marble))
							else
								K:vcyl("HomeLampStem", q.Size.X * 0.7, 0.06, CF(lp.X, lp.Y + 0.15, lp.Z), L.brass)
							end
						end)
						self:hide(q)
					end
				end
			end
		end)
	end
end

-- 고시원 1인실 ----------------------------------------------------------------------------------
ROOM["goshiwon:main"] = function(Cx: any)
	local K = Cx.K
	local hi = K.detail ~= "low"
	-- 냉장고 + 전자레인지 + 포트 + 컵
	local fb = Cx:ownNamed("FridgeBody")[1]
	if fb then
		Cx:miniFridge(fb, Cx:ownNamed("FridgeDoor")[1])
	end
	local mw = Cx:ownNamed("Microwave")[1]
	if mw then
		Cx:microwave(mw, Cx:ownNamed("MicrowaveDoor")[1])
	end
	local kt = Cx:ownNamed("Kettle")[1]
	if kt then
		Cx:kettle(Cx:ownNamed("KettleBase")[1], kt)
	end
	for _, cup in Cx:ownNamed("Cup") do
		K:free(function()
			mug(K, CF(cup.c.X, cup.min.Y, cup.c.Z), lk(236, 236, 232))
		end)
		Cx:hide(cup.part)
	end
	-- 행거 + 옷
	local rail = Cx:ownNamed("HangerRail")[1]
	if rail then
		Cx:clothesRail(rail, Cx:ownNamed("Clothes"))
		for _, b in Cx:ownNamed("RailBracket") do
			K:free(function()
				K:box("HomeRailBracket", V3(b.size.X, 0.36, b.size.Z), CF(b.c), L.chrome)
			end)
			Cx:hide(b.part)
		end
	end
	-- 플라스틱 서랍장 (+ 위: 휴지 · 로션 · 거울 · 빗)
	local dr = Cx:ownNamed("Drawers")[1]
	if dr then
		local F, info = Cx:plasticDrawers(dr)
		for _, q in Cx:ownNamed("DrawerLine") do
			if math.abs(q.c.X - dr.c.X) < 1 and math.abs(q.c.Z - dr.c.Z) < 2 then
				Cx:hide(q.part)
			end
		end
		if hi then
			local y = info.max.Y + 0.02
			local zc = (info.min.Z + info.max.Z) / 2
			K:free(function()
				K:rbox("HomeTissueBox", V3(0.9, 0.36, 0.5), 0.06, F * CF(info.min.X + 0.6, y + 0.18, zc), lk(250, 250, 246))
				K:ell("HomeTissue", V3(0.3, 0.22, 0.2), F * CF(info.min.X + 0.6, y + 0.4, zc), lk(252, 252, 252))
				K:vcyl("HomeLotion", 0.6, 0.22, F * CF(info.max.X - 0.3, y + 0.3, zc - 0.3), lk(240, 210, 220))
				K:vcyl("HomeLotionPump", 0.12, 0.08, F * CF(info.max.X - 0.3, y + 0.66, zc - 0.3), lk(250, 250, 250))
				K:vcyl("HomeSkinToner", 0.48, 0.2, F * CF(info.max.X - 0.6, y + 0.24, zc - 0.1), L.glass(c3(200, 230, 240), 0.2))
				K:box("HomeHairBrush", V3(0.14, 0.05, 0.8), F * CF(info.max.X - 0.35, y + 0.03, zc + 0.5) * ANG(0, 0.4, 0), lk(30, 30, 34))
				K:slab("HomeStandMirror", 0.6, 0.06, 0.75, 0.25, F * CF(info.min.X + 0.5, y + 0.45, zc + 0.9) * ANG(math.rad(80), 0, 0), lk(240, 240, 238))
			end)
		end
	end
	-- 빨래 건조대
	local rackParts = {}
	local rmn, rmx = V3(math.huge, math.huge, math.huge), V3(-math.huge, -math.huge, -math.huge)
	for _, r in Cx:ownNamed("RackLeg", "RackBar", "Laundry") do
		table.insert(rackParts, r.part)
		rmn, rmx = rmn:Min(r.min), rmx:Max(r.max)
	end
	if #rackParts > 0 then
		Cx:dryingRack(rmn, rmx, rackParts, { c3(240, 240, 236), c3(70, 90, 140), c3(230, 160, 170), c3(40, 40, 44) })
	end
	-- 라면 상자 (멀티팩) + 컵라면
	local boxes = Cx:ownNamed("RamenBox")
	for i, b in boxes do
		local F = CF(b.c.X, b.min.Y, b.c.Z)
		K:free(function()
			K:box("HomeRamenCarton", V3(b.size.X, b.size.Y - 0.02, b.size.Z), F * CF(0, b.size.Y / 2, 0), lk(196, 52, 40, M.Cardboard))
			K:box("HomeRamenCartonFlap", V3(b.size.X + 0.01, 0.04, b.size.Z * 0.5), F * CF(0, b.size.Y - 0.01, 0), lk(176, 44, 34, M.Cardboard))
			-- 상자 앞 글자: 방 쪽 면 (가까운 쪽 +Z 가정 대신 넓은 면 두 쪽)
			for _, sz in { -1, 1 } do
				K:text("HomeRamenLabel", b.size.X * 0.86, b.size.Y * 0.5, CFrame.fromMatrix((F * CF(0, b.size.Y * 0.5, sz * (b.size.Z / 2 + 0.006))).Position, V3(sz, 0, 0), YA, V3(0, 0, sz)), if i == 1 then "얼큰 라면\n5개입 ×8" else "짜장 라면\n4개입 ×8", { fg = c3(255, 240, 210), bg = c3(176, 36, 30), d = 0.006, free = true, font = Enum.Font.GothamBlack })
			end
		end)
		Cx:hide(b.part)
	end
	for _, b in Cx:ownNamed("RamenBand") do
		Cx:hide(b.part)
	end
	for _, cn in Cx:ownNamed("CupNoodle") do
		local inShelf = cn.part.Parent and cn.part.Parent.Parent and cn.part.Parent.Parent.Name == "Furniture"
		if not inShelf and cn.min.Y < 3 then
			K:free(function()
				K:vcyl("HomeCupNoodle", 0.38, 0.38, CF(cn.c.X, cn.min.Y + 0.19, cn.c.Z), { c = cn.part.Color, m = M.SmoothPlastic })
				K:vcyl("HomeCupNoodleTop", 0.04, 0.42, CF(cn.c.X, cn.min.Y + 0.38, cn.c.Z), lk(240, 236, 226))
				K:vcyl("HomeCupNoodleBand", 0.1, 0.39, CF(cn.c.X, cn.min.Y + 0.2, cn.c.Z), lk(250, 246, 236))
			end)
			Cx:hide(cn.part)
		end
	end
	-- 롤 블라인드
	local roll, blind = Cx:ownNamed("BlindRoll")[1], Cx:ownNamed("Blind")[1]
	if roll and blind then
		for _, s in Cx:ownNamed("Sill") do
			Cx.sillY = s.max.Y
		end
		Cx:rollBlind(roll, blind)
	end
	-- 바닥: 멀티탭 (책상 아래 콘센트 쪽) · 소화기 · 슬리퍼 · 백팩 · 휴지통
	local ps = Cx:ownNamed("PowerStrip")[1]
	if ps then
		K:free(function()
			Cx.powerStrip = P.powerStrip(K, CF(ps.c.X, 0, ps.c.Z) * ANG(0, if ps.size.X > ps.size.Z then 0 else PI / 2, 0))
		end)
		Cx:hide(ps.part)
	end
	local doorP = Cx:floorCenter() + V3(0, 0, 4)
	for _, it in Cx.interacts do
		if it.kind == "door" then
			doorP = it.p
		end
	end
	local pcf = Cx:floorAlongWall(0.8, 0.8, 1.8, { score = near(doorP) })
	if pcf then
		K:free(function()
			P.extinguisher(K, pcf)
		end)
	end
	local bed = nil
	for _, sl in Cx.slots do
		if sl:GetAttribute("Category") == "bed" then
			bed = sl
		end
	end
	if bed then
		local b = bed:FindFirstChild("SlotBase") :: BasePart?
		if b then
			local bp = Cx.V.cf:PointToObjectSpace(b.Position)
			local spot = Cx:floorAt({ CF(bp.X + 2.0, 0, bp.Z + 2.2), CF(bp.X + 2.0, 0, bp.Z + 1.2), CF(bp.X + 1.9, 0, bp.Z - 0.5) }, V3(0.9, 0.2, 1.0), 0.02)
			if spot then
				K:free(function()
					P.slippers(K, spot * ANG(0, 0.3, 0), c3(60, 100, 180))
				end)
			end
		end
	end
	local bp2 = Cx:floorAlongWall(1.2, 0.7, 1.6, { score = near(Cx:floorCenter() + V3(1, 0, 2)) })
	if bp2 then
		K:free(function()
			P.backpack(K, bp2, c3(40, 44, 52))
		end)
	end
	-- 벽: 달력 · 피난안내도
	local _, _, cal = Cx:wallSpot(1.2, 4.0, 5.6, 0.12, { score = near(Cx:floorCenter()) })
	if cal then
		K:free(function()
			P.calendar(K, cal)
		end)
	end
	local _, _, ev = Cx:wallSpot(1.3, 4.6, 5.6, 0.1, { score = near(doorP) })
	if ev then
		K:free(function()
			P.evacuation(K, ev)
		end)
	end
	-- 입실 안내문 (A4, 테이프로 붙임): 소음 · 공용주방 · 와이파이 · 분리수거
	local _, _, nt = Cx:wallSpot(1.0, 3.9, 5.3, 0.06, { score = near(doorP + V3(0, 0, -2)) })
	if nt then
		K:free(function()
			local f = nt * ANG(0, 0, 0.02)
			K:plate("HomeNoticePaper", 0.85, 1.2, 0.01, f, L.paper)
			K:text("HomeNoticeTitle", 0.75, 0.16, f * CF(0, 0.47, 0.012), "입실 안내", { fg = c3(30, 30, 34), d = 0.003, free = true, font = Enum.Font.GothamBold })
			K:text("HomeNoticeBody", 0.75, 0.8, f * CF(0, -0.08, 0.012), "· 22시 이후 소음 주의\n· 공용주방 07~23시\n· 밥 · 김치 · 라면 무료\n· Wi-Fi GW_2F / 0510\n· 분리수거 화 · 목 · 토", { fg = c3(50, 50, 56), d = 0.003, free = true, font = Enum.Font.Gotham, align = "Left", wrap = true })
			for _, sx in { -0.36, 0.36 } do
				K:plate("HomeNoticeTape", 0.22, 0.08, 0.004, f * CF(sx, 0.6, 0.011) * ANG(0, 0, sx * 0.6), { c = c3(240, 236, 210), m = M.SmoothPlastic, t = 0.3 })
			end
		end)
	end
end

-- 원룸 -------------------------------------------------------------------------------------------
ROOM["oneroom:main"] = function(Cx: any)
	local K = Cx.K
	local hi = K.detail ~= "low"
	for _, r in Cx:ownNamed("Wardrobe") do
		pcall(function()
			Cx:wardrobe(r, 3)
		end)
	end
	-- 바닥: 빨래 건조대 (창가) · 빨래 바구니 · 휴지통 · 전신 거울 · 슬리퍼
	local win = nil
	for _, it in Cx.interacts do
		if it.kind == "window" then
			win = it.p
		end
	end
	local doorP = Cx:floorCenter() + V3(0, 0, 5)
	for _, it in Cx.interacts do
		if it.kind == "door" then
			doorP = it.p
		end
	end
	local mirror = Cx:floorAlongWall(1.7, 0.6, 5.5, { score = near(doorP) })
	if mirror then
		K:free(function()
			P.leanMirror(K, mirror, 5.2, lk(236, 232, 224))
		end)
	end
	local bas = Cx:floorAlongWall(1.5, 1.1, 1.6, { score = near(Cx:floorCenter() + V3(6, 0, 0)) })
	if bas then
		K:free(function()
			P.laundryBasket(K, bas, { c3(240, 240, 236), c3(60, 80, 130), c3(200, 120, 130) })
		end)
	end
	local tb = Cx:floorAlongWall(0.95, 0.95, 1.3, { score = near(doorP) })
	if tb then
		K:free(function()
			P.trashBin(K, tb)
		end)
	end
	-- 창가 빨래 건조대 (날개 펼친 X 건조대 + 수건 · 티셔츠 · 양말)
	do
		local rk = if win then Cx:floorAlongWall(3.6, 1.8, 3.5, { score = near(win), gap = 0.3 }) else nil
		if not rk then
			-- 창가가 가구로 차 있으면: 다른 벽 (현관 · 주방 쪽은 피해서 방 가운데에 가까운 벽)
			rk = Cx:floorAlongWall(3.6, 1.8, 3.5, { score = near(Cx:floorCenter() + V3(0, 0, -2)), gap = 0.3 })
		end
		if rk then
			local mn, mx = laabb(rk * CF(0, 1.75, 0), V3(3.6, 3.5, 1.8))
			Cx:dryingRack(mn, mx, {}, { c3(246, 244, 238), c3(90, 120, 160), c3(236, 190, 196), c3(60, 62, 70), c3(220, 214, 190) })
		elseif win then
			-- 벽이 다 차 있으면: 창가 천장형 빨래 건조대 (바닥을 안 막음, 빨래 아래 끝 5.7 이상)
			Cx:ceilingRack(V3(win.X, 0, win.Z), { c3(246, 244, 238), c3(90, 120, 160), c3(236, 190, 196), c3(60, 62, 70) })
		end
	end
	-- TV 옆 멀티탭
	for _, sl in Cx.slots do
		if sl:GetAttribute("Category") == "tv" then
			local b = sl:FindFirstChild("SlotBase") :: BasePart?
			if b then
				local bp = Cx.V.cf:PointToObjectSpace(b.Position)
				local spot = Cx:floorAt({ CF(bp.X - 0.3, 0, bp.Z + 2.3), CF(bp.X - 0.3, 0, bp.Z - 2.3), CF(bp.X - 1.2, 0, bp.Z + 2.2) }, V3(1.2, 0.3, 0.4), 0)
				if spot then
					K:free(function()
						P.powerStrip(K, spot)
					end)
				end
			end
		end
	end
	-- 벽: 시계 · 달력
	local _, _, ck = Cx:wallSpot(1.4, 5.6, 7.0, 0.2, { score = near(Cx:floorCenter() + V3(0, 0, -6)) })
	if ck then
		K:free(function()
			P.wallClock(Cx, ck, 1.2, lk(240, 240, 236))
		end)
	end
	if hi then
		local _, _, cal = Cx:wallSpot(1.2, 4.2, 5.8, 0.12, { score = near(doorP) })
		if cal then
			K:free(function()
				P.calendar(K, cal)
			end)
		end
	end
end

-- 소품 모델을 슬롯 빌더로 다시 짓기 (데이베드 = 소파, 바닥 러그, 라운지 체어)
function C:reskinAs(cat: string, m: Instance, item: string, backName: string?): boolean
	local K = self.K
	local fn = SLOT[cat]
	if not fn then
		return false
	end
	local F, info = propFrame(self, m)
	if backName then
		local b = first(info, backName)
		if b then
			local ctr = (info.min + info.max) / 2
			local d = b.c - ctr
			if math.abs(d.X) > math.abs(d.Z) and math.abs(d.X) > 0.2 then
				F = F * ANG(0, if d.X > 0 then -PI / 2 else PI / 2, 0)
			elseif d.Z > 0.2 then
				F = F * ANG(0, PI, 0)
			end
			info = analyze(self, F, m)
		end
	end
	info.item = item
	local ok, res = false, nil
	K:free(function()
		ok, res = pcall(fn, self, info)
	end)
	if ok and res ~= false then
		for _, r in info.all do
			if not keepVisible(r.part) and r.part.Transparency < 0.99 then
				self:hide(r.part)
			end
		end
		return true
	end
	if not ok then
		K:note("reskinAs " .. cat .. " error: " .. tostring(res))
	end
	return false
end

-- 바닥에 놓인 러그 파트 (슬롯 아님) 리스킨
function C:plainRug(r: any, item: string)
	local K = self.K
	local F = CF(r.c.X, r.min.Y, r.c.Z)
	local info = analyze(self, F, r.part)
	info.item = item
	K:free(function()
		SLOT.rug(self, info)
	end)
	self:hide(r.part)
end

-- 세탁기 · 건조기 (rec 본체): 드럼 문 · 조작부 · 세제
function C:drumWasher(r: any, label: string?)
	local K = self.K
	local F, info = propFrame(self, r.part)
	local x0, x1, y0, y1, z0, z1 = info.min.X, info.max.X, info.min.Y, info.max.Y, info.min.Z, info.max.Z
	local w, h = x1 - x0, y1 - y0
	local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
	local out: any = {}
	K:free(function()
		K:rbox("HomeWasherBody", V3(w, h, z1 - z0), 0.05, F * CF(cx, cy, (z0 + z1) / 2), lk(242, 242, 240))
		K:box("HomeWasherPanel", V3(w - 0.08, 0.42, 0.03), F * CF(cx, y1 - 0.25, z1 + 0.005), lk(56, 58, 62))
		K:box("HomeWasherLCD", V3(0.5, 0.18, 0.01), F * CF(cx + 0.1, y1 - 0.25, z1 + 0.025), lk(20, 24, 28))
		local _, lab = K:text("HomeWasherTime", 0.46, 0.15, F * CF(cx + 0.1, y1 - 0.25, z1 + 0.032), label or "0:48", { fg = c3(110, 220, 255), glow = 1.3, font = Enum.Font.Code, d = 0.004, free = true })
		out.label = lab
		K:cyl("HomeWasherKnob", 0.06, 0.26, F * CF(x0 + 0.35, y1 - 0.25, z1 + 0.03) * ANG(0, PI / 2, 0), lk(200, 202, 206, M.Metal))
		local dc = F * CF(cx, cy - h * 0.08, z1 + 0.02)
		K:cyl("HomeWasherDoorRing", 0.08, math.min(w, h) * 0.66, dc * ANG(0, PI / 2, 0), lk(200, 202, 206, M.Metal))
		out.glass = K:cyl("HomeWasherDoorGlass", 0.06, math.min(w, h) * 0.5, dc * CF(0, 0, 0.02) * ANG(0, PI / 2, 0), { c = c3(40, 50, 60), m = M.Glass, t = 0.25, r = 0.2 })
		out.drum = {}
		for i = 0, 2 do
			table.insert(out.drum, K:box("HomeWasherDrumRib", V3(math.min(w, h) * 0.36, 0.06, 0.02), dc * CF(0, 0, -0.06) * ANG(0, 0, i * PI / 3), lk(170, 176, 182, M.Metal)))
		end
		out.center = (self.V.cf * dc).Position
		out.axis = (self.V.cf * dc).LookVector
		K:box("HomeWasherDetergent", V3(w * 0.3, 0.08, 0.02), F * CF(x0 + w * 0.22, y1 - 0.62, z1 + 0.005), lk(220, 220, 218))
		K:box("HomeWasherKick", V3(w - 0.1, 0.2, 0.02), F * CF(cx, y0 + 0.12, z1 + 0.004), lk(220, 220, 218))
	end)
	self:hide(r.part)
	return out, F, info
end

-- 가스 보일러 (벽 dcf)
function P.boiler(K: any, dcf: CFrame)
	K:rbox("HomeBoiler", V3(1.5, 2.2, 0.9), 0.06, dcf * CF(0, 0, 0.45), lk(246, 246, 244))
	K:box("HomeBoilerPanel", V3(0.9, 0.35, 0.02), dcf * CF(0, -0.7, 0.91), lk(40, 42, 46))
	K:text("HomeBoilerLCD", 0.5, 0.18, dcf * CF(-0.1, -0.7, 0.925), "난방 45℃", { fg = c3(255, 170, 60), glow = 1.2, d = 0.004, free = true })
	K:box("HomeBoilerBrand", V3(0.5, 0.08, 0.005), dcf * CF(0, 0.75, 0.905), lk(200, 60, 50))
	for i, col in { c3(220, 190, 50), c3(200, 202, 206), c3(200, 202, 206), c3(180, 60, 50) } do
		K:seg("HomeBoilerPipe", (dcf * CF(-0.5 + (i - 1) * 0.33, -1.1, 0.4)).Position, (dcf * CF(-0.5 + (i - 1) * 0.33, -2.6, 0.4)).Position, 0.12, { c = col, m = M.Metal })
	end
	K:seg("HomeBoilerFlue", (dcf * CF(0.3, 1.1, 0.4)).Position, (dcf * CF(0.3, 1.9, 0.4)).Position, 0.3, lk(220, 222, 224, M.Metal))
end
-- 분리수거함 (3칸)
function P.recycleBins(K: any, pcf: CFrame)
	local cols = { { c3(60, 140, 220), "플라스틱" }, { c3(80, 170, 80), "캔 · 병" }, { c3(230, 180, 40), "종이" } }
	for i, c in cols do
		local x = (i - 2) * 0.95
		K:rbox("HomeRecycleBin", V3(0.85, 1.5, 1.0), 0.06, pcf * CF(x, 0.75, 0), { c = c[1], m = M.Plastic })
		K:box("HomeRecycleLid", V3(0.86, 0.08, 1.02), pcf * CF(x, 1.52, 0), { c = c[1]:Lerp(Color3.new(0, 0, 0), 0.2), m = M.Plastic })
		K:text("HomeRecycleLabel", 0.7, 0.24, pcf * CF(x, 1.1, 0.505), c[2], { fg = c3(255, 255, 255), d = 0.005, free = true })
	end
end
-- 장난감 바구니 (블록 · 곰인형)
function P.toyBasket(K: any, pcf: CFrame)
	K:rbox("HomeToyBasket", V3(1.6, 1.0, 1.1), 0.12, pcf * CF(0, 0.5, 0), lk(214, 196, 160, M.Fabric))
	local cols = { c3(230, 60, 60), c3(60, 140, 230), c3(250, 200, 40), c3(70, 180, 90) }
	for i = 1, 6 do
		K:box("HomeToyBlock", V3(0.25, 0.25, 0.25), pcf * CF(-0.5 + (i % 3) * 0.4, 1.05 + (i // 4) * 0.2, -0.2 + (i % 2) * 0.35) * ANG(0, i, 0.3), { c = cols[i % 4 + 1], m = M.Plastic })
	end
	K:ball("HomeTeddyBody", 0.6, pcf * CF(0.45, 1.25, 0.05), lk(176, 130, 86, M.Fabric))
	K:ball("HomeTeddyHead", 0.42, pcf * CF(0.45, 1.68, 0.1), lk(176, 130, 86, M.Fabric))
	for _, sx in { -1, 1 } do
		K:ball("HomeTeddyEar", 0.16, pcf * CF(0.45 + sx * 0.16, 1.86, 0.08), lk(150, 108, 70, M.Fabric))
	end
	K:ball("HomeTeddyNose", 0.1, pcf * CF(0.45, 1.66, 0.3), lk(60, 40, 30))
end
-- 기타 + 스탠드
function P.guitar(K: any, pcf: CFrame)
	local tilt = pcf * CF(0, 0, 0) * ANG(math.rad(-12), 0, 0)
	K:seg("HomeGuitarStand", pcf * V3(-0.35, 0.02, 0.2), pcf * V3(0, 1.0, -0.15), 0.05, L.blackMetal)
	K:seg("HomeGuitarStand", pcf * V3(0.35, 0.02, 0.2), pcf * V3(0, 1.0, -0.15), 0.05, L.blackMetal)
	K:seg("HomeGuitarStand", pcf * V3(0, 0.02, -0.4), pcf * V3(0, 2.6, -0.45), 0.05, L.blackMetal)
	K:ell("HomeGuitarBody", V3(1.15, 1.35, 0.32), tilt * CF(0, 0.85, 0), lk(196, 140, 80, M.Wood))
	K:ell("HomeGuitarUpper", V3(0.9, 0.9, 0.32), tilt * CF(0, 1.55, 0), lk(196, 140, 80, M.Wood))
	K:disc("HomeGuitarHole", 0.32, 0.02, tilt * CF(0, 1.35, 0.16) * ANG(PI / 2, 0, 0), lk(30, 22, 16))
	K:box("HomeGuitarNeck", V3(0.16, 1.7, 0.1), tilt * CF(0, 2.75, 0.06), lk(90, 60, 40, M.Wood))
	K:box("HomeGuitarHead", V3(0.26, 0.45, 0.08), tilt * CF(0, 3.8, 0.05), lk(60, 40, 28, M.Wood))
	K:box("HomeGuitarBridge", V3(0.4, 0.08, 0.04), tilt * CF(0, 0.7, 0.17), lk(40, 28, 20))
end

-- 이 방 바닥 위의 슬롯 (Category) 받침 위치 (방 프레임)
local function Kit_overlap(a: Vector3, b: Vector3, c: Vector3, d: Vector3): boolean
	return a.X < d.X - 0.02 and b.X > c.X + 0.02 and a.Y < d.Y - 0.02 and b.Y > c.Y + 0.02 and a.Z < d.Z - 0.02 and b.Z > c.Z + 0.02
end
local function slotAt(Cx: any, cat: string): Vector3?
	for _, slot in Cx.slots do
		if slot:GetAttribute("Category") == cat then
			local base = slot:FindFirstChild("SlotBase") or slot.PrimaryPart
			if base and base:IsA("BasePart") then
				local lp = Cx.V.cf:PointToObjectSpace(base.Position)
				if Cx:mine(V3(lp.X, 0.5, lp.Z)) then
					return lp
				end
			end
		end
	end
	return nil
end
T.slotAt = slotAt

-- 이 방 슬롯 가구 기록 (overlaySlot 이 남긴 F 프레임 + F 공간 상자)
local function slotRecOf(Cx: any, cat: string): any?
	for _, rec in Cx.slotRec or {} do
		if rec.info and rec.info.cat == cat and rec.F then
			return rec
		end
	end
	return nil
end

-- 침대 아래 러그 (침대 슬롯 F: +Z = 발치): 침대 아래 2/3 + 양옆 · 발치로 나옴. 바닥 위 납작 (걸어 다녀도 됨)
function C:bedRug(look: any, border: any, opts: any?)
	local o: any = opts or {}
	local rec = slotRecOf(self, "bed")
	if not rec or self.V.decorPlus then
		return
	end
	local K = self.K
	local F, info = rec.F, rec.info
	local side = o.side or 1.3
	local x0, x1 = info.min.X - side, info.max.X + side
	local zc = (info.min.Z + info.max.Z) / 2
	local z0, z1 = zc - (info.max.Z - info.min.Z) * 0.12, info.max.Z + (o.foot or 1.7)
	-- 바닥 위 · 이 방 · 벽 · 다른 바닥 소품과 안 겹치는지 (러그 네 모서리)
	for _, q in { V3(x0, 0, z0), V3(x1, 0, z0), V3(x0, 0, z1), V3(x1, 0, z1) } do
		local w = F * q
		if not self:mine(V3(w.X, 0.5, w.Z)) or self:insideWall(V3(w.X, 0.5, w.Z)) then
			return
		end
	end
	local c = F * CF((x0 + x1) / 2, 0.02, (z0 + z1) / 2)
	local rmn, rmx = laabb(c, V3(x1 - x0, 0.06, z1 - z0))
	K:reserve(rmn, rmx, "rug")
	self.bedRugArgs = { look, border, opts }
	self.bedRugGroup = K:group("HomeBedRugGroup", function()
		self:_bedRugParts(c, x1 - x0, z1 - z0, look, border)
	end)
end
function C:_bedRugParts(c: CFrame, w: number, len: number, look: any, border: any?)
	local K = self.K
	local x0, x1, z0, z1 = -w / 2, w / 2, -len / 2, len / 2
	c = c * CF(0, 0, 0)
	K:free(function()
		K:box("HomeBedRug", V3(x1 - x0, 0.04, z1 - z0), c, look)
		if border then
			for _, sz in { -1, 1 } do
				K:box("HomeBedRugBorder", V3(x1 - x0 - 0.5, 0.05, 0.22), c * CF(0, 0.005, sz * ((z1 - z0) / 2 - 0.35)), border)
			end
			for _, sx in { -1, 1 } do
				K:box("HomeBedRugBorder", V3(0.22, 0.05, z1 - z0 - 0.92), c * CF(sx * ((x1 - x0) / 2 - 0.35), 0.005, 0), border)
			end
		end
	end)
end

-- 빈백 소파 (pcf: +Z = 앉은 사람이 보는 쪽): 부클 원단, 눌린 자리 · 손잡이 루프
function P.beanBag(K: any, pcf: CFrame, look: any)
	K:ell("HomeBeanBagBase", V3(2.3, 1.25, 2.3), pcf * CF(0, 0.6, 0), look)
	K:ell("HomeBeanBagBack", V3(2.0, 1.9, 1.0), pcf * CF(0, 1.15, -0.62) * ANG(math.rad(-14), 0, 0), look)
	K:ell("HomeBeanBagSeat", V3(1.5, 0.35, 1.3), pcf * CF(0, 1.12, 0.25), tint(look, -0.05))
	K:ell("HomeBeanBagArm", V3(0.55, 0.9, 1.5), pcf * CF(-0.88, 0.95, 0.05), tint(look, 0.02))
	K:ell("HomeBeanBagArm", V3(0.55, 0.9, 1.5), pcf * CF(0.88, 0.95, 0.05), tint(look, 0.02))
	K:ring("HomeBeanBagLoop", pcf * CF(0, 2.02, -0.86) * ANG(math.rad(-20), 0, 0), 0.16, 0.04, 6, tint(look, -0.2), 0, PI)
	K:disc("HomeBeanBagShadow", 2.0, 0.02, pcf * CF(0, 0.01, 0), tint(look, -0.35))
end

-- 캣타워 (pcf 바닥, 2.2 x 2.2, 높이 6.2): 원목 판 3 + 사이잘 기둥 + 숨숨집 + 해먹 + 맨 위에 자는 고양이
-- 반환: { tail = { parts }, tailBase = CFrame(로컬), head = part }
function P.catTower(K: any, pcf: CFrame, seed: number): any
	local wood = lk(222, 196, 156, M.Wood)
	local carpet = lk(214, 206, 192, M.Fabric)
	local sisal = lk(196, 170, 120, M.Fabric)
	K:slab("HomeCatBase", 2.2, 2.2, 0.16, 0.2, pcf * CF(0, 0.08, 0), wood)
	K:slab("HomeCatBaseMat", 2.1, 2.1, 0.03, 0.18, pcf * CF(0, 0.175, 0), carpet)
	-- 기둥 (사이잘 로프 감김: 띠 무늬)
	local posts = { { -0.65, -0.65, 4.6 }, { 0.7, 0.55, 2.4 }, { 0.6, -0.6, 5.9 } }
	for _, pp in posts do
		K:vcyl("HomeCatPost", pp[3], 0.34, pcf * CF(pp[1], 0.16 + pp[3] / 2, pp[2]), sisal)
		for k = 1, math.floor(pp[3] / 0.5) do
			K:vcyl("HomeCatPostBand", 0.03, 0.35, pcf * CF(pp[1], 0.16 + k * 0.5, pp[2]), tint(sisal, -0.1))
		end
	end
	-- 숨숨집 (아래 큐브, 둥근 입구)
	K:box("HomeCatHouse", V3(1.2, 1.1, 1.2), pcf * CF(-0.4, 0.75, 0.35), carpet)
	K:disc("HomeCatHouseHole", 0.6, 0.02, pcf * CF(-0.4, 0.75, 0.96) * ANG(PI / 2, 0, 0), lk(60, 54, 48, M.Fabric))
	-- 판 3 (높이 2.6 · 4.7 · 6.0) + 해먹
	for _, pl in { { 0.25, 0.2, 2.56, 1.5 }, { -0.5, -0.4, 4.76, 1.3 }, { 0.5, -0.45, 6.06, 1.45 } } do
		K:slab("HomeCatShelf", pl[4], pl[4], 0.12, 0.3, pcf * CF(pl[1], pl[3], pl[2]), wood)
		K:slab("HomeCatShelfMat", pl[4] - 0.08, pl[4] - 0.08, 0.03, 0.28, pcf * CF(pl[1], pl[3] + 0.075, pl[2]), carpet)
	end
	K:ell("HomeCatHammock", V3(1.3, 0.3, 1.0), pcf * CF(0.65, 3.6, 0.45), lk(150, 160, 170, M.Fabric))
	-- 장난감 공 (끈)
	K:seg("HomeCatToyString", pcf * V3(0.25, 2.5, 0.85), pcf * V3(0.25, 1.7, 0.92), 0.015, lk(240, 240, 240))
	local ball = K:ball("HomeCatToyBall", 0.16, pcf * CF(0.25, 1.65, 0.92), lk(240, 90, 90, M.Fabric))
	-- 고양이 (맨 위 판에서 몸을 말고 잠): 몸 · 머리 · 귀 · 꼬리 조각
	local top = 6.06 + 0.09
	local coat = ({ lk(236, 160, 90, M.Fabric), lk(240, 238, 232, M.Fabric), lk(60, 58, 60, M.Fabric) })[seed % 3 + 1]
	local cc = pcf * CF(0.5, top, -0.45)
	K:ell("HomeCatBody", V3(0.95, 0.5, 0.7), cc * CF(0, 0.25, 0) * ANG(0, 0.4, 0), coat)
	local head = K:ell("HomeCatHead", V3(0.42, 0.36, 0.4), cc * CF(0.38, 0.22, 0.22) * ANG(0, 0.4, 0), coat)
	for _, ex in { -0.1, 0.1 } do
		K:wedge("HomeCatEar", V3(0.04, 0.14, 0.12), cc * CF(0.38 + ex, 0.44, 0.22) * ANG(0, 0.4, 0), coat)
	end
	local tail = {}
	for k = 0, 3 do
		local a = 0.8 + k * 0.5
		table.insert(tail, K:ell("HomeCatTail", V3(0.16, 0.16, 0.3), cc * CF(math.cos(a) * 0.45, 0.1, math.sin(a) * 0.4) * ANG(0, -a, 0), coat))
	end
	return { tail = tail, head = head, ball = ball, center = (cc * CF(0, 0.1, 0)).Position }
end

-- 실링팬 (복층 높은 천장): c = 바닥 위 점 (방 로컬, y 무시), ceil = 천장 높이, y = 날개 높이.
-- 반환 { spin = { parts }, center = 로컬 Vector3, light = 아래 조명 판 }
function P.ceilingFan(K: any, c: Vector3, ceil: number, y: number): any
	local blk = lk(30, 30, 32, M.Metal)
	local wood = lk(120, 84, 56, M.Wood)
	K:disc("HomeFanCanopy", 0.7, 0.22, CF(c.X, ceil - 0.11, c.Z), blk)
	K:vcyl("HomeFanDownrod", ceil - 0.22 - (y + 0.35), 0.09, CF(c.X, (ceil - 0.22 + y + 0.35) / 2, c.Z), blk)
	K:vcyl("HomeFanMotor", 0.42, 1.0, CF(c.X, y + 0.2, c.Z), blk)
	K:vcyl("HomeFanMotorRing", 0.06, 1.04, CF(c.X, y + 0.04, c.Z), L.brass)
	local spin = {}
	for i = 0, 4 do
		local a = i * PI * 2 / 5
		local dir = V3(math.cos(a), 0, math.sin(a))
		local p0 = V3(c.X, y, c.Z) + dir * 0.5
		local fr = CFrame.lookAt(p0, p0 + dir) -- -Z = 바깥
		table.insert(spin, K:box("HomeFanIron", V3(0.12, 0.05, 0.6), fr * CF(0, 0, -0.3), blk))
		table.insert(spin, K:box("HomeFanBlade", V3(0.5, 0.04, 2.0), fr * CF(0, 0.02, -1.45) * ANG(0, 0, math.rad(10)), wood))
	end
	local light = K:disc("HomeFanLight", 0.7, 0.05, CF(c.X, y - 0.03, c.Z), L.neon(c3(255, 236, 214), 0.15))
	table.insert(spin, light)
	return { spin = spin, center = V3(c.X, y, c.Z), light = light }
end

-- 3단 이동식 트롤리 (pcf 바닥, 폭 1.4 · 깊이 1.0 · 높이 2.6): 스킨케어 · 수건 · 드라이기
function P.rollingCart(K: any, pcf: CFrame, look: any, seed: number)
	local w, d = 1.3, 0.95
	for _, sx in { -w / 2 + 0.04, w / 2 - 0.04 } do
		for _, sz in { -d / 2 + 0.04, d / 2 - 0.04 } do
			K:vcyl("HomeCartPost", 2.35, 0.05, pcf * CF(sx, 1.33, sz), look)
			K:ball("HomeCartWheel", 0.14, pcf * CF(sx, 0.07, sz), lk(40, 40, 42))
		end
	end
	for i, y in { 0.35, 1.25, 2.15 } do
		K:slab("HomeCartTray", w, d, 0.05, 0.08, pcf * CF(0, y, 0), look)
		K:box("HomeCartLip", V3(w, 0.18, 0.03), pcf * CF(0, y + 0.09, d / 2 - 0.015), look)
		K:box("HomeCartLip", V3(w, 0.18, 0.03), pcf * CF(0, y + 0.09, -d / 2 + 0.015), look)
		if i == 1 then
			-- 아래: 말아 둔 수건
			for j = 0, 2 do
				K:cyl("HomeRolledTowel", 0.8, 0.3, pcf * CF(0, y + 0.18, -0.28 + j * 0.28), { c = ({ c3(246, 244, 238), c3(196, 206, 214), c3(232, 222, 206) })[j + 1], m = M.Fabric })
			end
		elseif i == 2 then
			-- 가운데: 드라이기 + 고데기
			K:ell("HomeDryerBody", V3(0.55, 0.3, 0.3), pcf * CF(-0.25, y + 0.18, 0.05) * ANG(0, 0.3, 0), lk(236, 232, 228))
			K:vcyl("HomeDryerGrip", 0.35, 0.14, pcf * CF(-0.4, y + 0.1, 0.15) * ANG(PI / 2, 0, 0.3), lk(236, 232, 228))
			K:cyl("HomeFlatIron", 0.7, 0.1, pcf * CF(0.3, y + 0.08, -0.15) * ANG(0, 0.4, 0), lk(40, 40, 44))
		else
			-- 위: 스킨케어 병 · 화장솜 통 · 핸드크림
			local cols = { c3(244, 238, 230), c3(214, 226, 236), c3(236, 214, 210), c3(250, 250, 250) }
			for j = 1, 4 do
				local hh = 0.3 + rnd(seed, j) * 0.25
				K:vcyl("HomeSkincare", hh, 0.16, pcf * CF(-0.45 + (j - 1) * 0.22, y + hh / 2 + 0.02, -0.2), { c = cols[j], m = M.SmoothPlastic })
				K:vcyl("HomeSkincareCap", 0.07, 0.12, pcf * CF(-0.45 + (j - 1) * 0.22, y + hh + 0.055, -0.2), if j % 2 == 0 then L.goldMetal else lk(40, 40, 44))
			end
			K:vcyl("HomeCottonJar", 0.3, 0.26, pcf * CF(0.4, y + 0.17, 0.1), L.glass(c3(236, 240, 244), 0.4))
			K:vcyl("HomeCottonPads", 0.22, 0.2, pcf * CF(0.4, y + 0.13, 0.1), lk(252, 252, 250, M.Fabric))
		end
	end
end

-- 벽 선반 (액자 선반): dcf 벽면, 폭 w. 액자 2-3개 기대 세움 + 소품
function P.pictureLedge(C_: any, dcf: CFrame, w: number, look: any, seed: number, cols: { Color3 })
	local K = C_.K
	K:box("HomeLedge", V3(w, 0.07, 0.38), dcf * CF(0, 0, 0.19), look)
	K:box("HomeLedgeLip", V3(w, 0.14, 0.04), dcf * CF(0, 0.07, 0.36), look)
	local x = -w / 2 + 0.25
	local i = 0
	while x < w / 2 - 0.6 do
		i += 1
		local fw = 0.9 + rnd(seed, i) * 0.6
		local fh = fw * (1.1 + rnd(seed, i + 9) * 0.35)
		if x + fw > w / 2 - 0.15 then
			break
		end
		local f = dcf * CF(x + fw / 2, 0.035 + fh / 2 * math.cos(0.12), 0.1) * ANG(-0.12, 0, 0)
		K:box("HomeLedgeFrame", V3(fw, fh, 0.05), f, if i % 2 == 1 then lk(30, 30, 32) else lk(236, 232, 224, M.Wood))
		K:box("HomeLedgeMat", V3(fw - 0.1, fh - 0.1, 0.01), f * CF(0, 0, 0.026), lk(250, 250, 246))
		local pc = cols[(i - 1) % #cols + 1]
		K:box("HomeLedgeArt", V3(fw - 0.34, fh - 0.4, 0.01), f * CF(0, 0.02, 0.031), { c = pc, m = M.SmoothPlastic })
		if rnd(seed, i + 3) > 0.4 then
			K:ell("HomeLedgeArtForm", V3((fw - 0.34) * 0.5, (fh - 0.4) * 0.45, 0.01), f * CF(0.05, -0.05, 0.036), { c = pc:Lerp(Color3.new(1, 1, 1), 0.5), m = M.SmoothPlastic })
		end
		x += fw + 0.12 - (if i == 1 then 0.25 else 0)
	end
	-- 오른쪽 끝: 작은 화병 + 잎
	local vx = w / 2 - 0.3
	K:vcyl("HomeLedgeVase", 0.45, 0.2, dcf * CF(vx, 0.26, 0.18), lk(232, 226, 214, M.Concrete))
	K:seg("HomeLedgeStem", (dcf * CF(vx, 0.45, 0.18)).Position, (dcf * CF(vx + 0.1, 0.95, 0.16)).Position, 0.02, lk(90, 110, 70))
	K:ell("HomeLedgeLeaf", V3(0.22, 0.12, 0.05), dcf * CF(vx + 0.12, 0.95, 0.16) * ANG(0, 0, 0.5), lk(110, 140, 90, M.Grass))
end

-- 낮은 오픈 책장 (pcf 바닥, 등 = 벽): 2칸, 책 · 바구니 · 스피커 · 디퓨저 · 액자
function C:lowShelf(pcf: CFrame, w: number, h: number, wood: any, opts: any?)
	local K = self.K
	local o: any = opts or {}
	local d = 0.95
	local mid = h / 2 + 0.03
	for _, sx in { -w / 2 + 0.03, w / 2 - 0.03 } do
		K:box("HomeLowShelfSide", V3(0.06, h, d), pcf * CF(sx, h / 2, 0), wood)
	end
	K:box("HomeLowShelfTop", V3(w, 0.07, d + 0.02), pcf * CF(0, h - 0.035, 0), wood)
	K:box("HomeLowShelfMid", V3(w - 0.12, 0.05, d - 0.04), pcf * CF(0, mid, 0), wood)
	K:box("HomeLowShelfBot", V3(w - 0.12, 0.05, d - 0.04), pcf * CF(0, 0.12, 0), wood)
	K:box("HomeLowShelfKick", V3(w - 0.12, 0.1, 0.04), pcf * CF(0, 0.05, d / 2 - 0.06), tint(wood, -0.15))
	K:box("HomeLowShelfBack", V3(w - 0.12, h - 0.1, 0.03), pcf * CF(0, h / 2, -d / 2 + 0.015), tint(wood, -0.06))
	local seed = self.seed + (o.seed or 0)
	local inner = mid - 0.12 - 0.05
	-- 아래칸: 왼쪽 패브릭 바구니 2 · 오른쪽 잡지 꽂이
	for j = 0, 1 do
		local bx = -w / 2 + 0.55 + j * 0.95
		K:rbox("HomeShelfBasket", V3(0.85, inner - 0.12, 0.8), 0.05, pcf * CF(bx, 0.145 + (inner - 0.12) / 2, 0.02), lk(206, 190, 160, M.Fabric))
		K:box("HomeShelfBasketRim", V3(0.86, 0.06, 0.81), pcf * CF(bx, 0.145 + inner - 0.15, 0.02), lk(176, 156, 120, M.Fabric))
	end
	bookRow(self, pcf, -w / 2 + 2.05, w / 2 - 0.08, 0.145, d / 2 - 0.06, inner, d - 0.1, seed + 3, { straight = false })
	-- 위칸: 책 + 북엔드 + 레코드/잡지
	local bx1 = bookRow(self, pcf, -w / 2 + 0.08, 0.2, mid + 0.025, d / 2 - 0.06, h - mid - 0.14, d - 0.1, seed + 11, { straight = true })
	K:box("HomeBookend", V3(0.04, 0.5, 0.4), pcf * CF(bx1 + 0.04, mid + 0.275, 0.1), L.blackMetal)
	shelfDeco(self, pcf, w / 2 - 0.5, mid + 0.025, d / 2 - 0.05, "jar", h - mid - 0.14, seed)
	-- 상판: 블루투스 스피커 · 디퓨저 · 액자
	local y = h
	K:rbox("HomeSpeaker", V3(0.9, 0.55, 0.45), 0.12, pcf * CF(-w / 2 + 0.6, y + 0.275, -0.05), lk(70, 72, 76, M.Fabric))
	K:box("HomeSpeakerTop", V3(0.9, 0.02, 0.4), pcf * CF(-w / 2 + 0.6, y + 0.56, -0.05), lk(40, 40, 44))
	K:box("HomeSpeakerLED", V3(0.12, 0.02, 0.01), pcf * CF(-w / 2 + 0.6, y + 0.12, 0.18), L.neon(c3(255, 255, 255), 0.3))
	if o.moodLamp then
		-- 버섯 무드등 (유백 유리 갓 + 원목 받침): 켜고 끄기는 방 상호작용
		K:vcyl("HomeMoodLampBase", 0.12, 0.34, pcf * CF(0.05, y + 0.06, 0), L.oak)
		K:vcyl("HomeMoodLampStem", 0.4, 0.1, pcf * CF(0.05, y + 0.32, 0), lk(250, 248, 244, M.Glass, { t = 0.2 }))
		self.moodLamp = K:ell("HomeMoodLampShade", V3(0.62, 0.42, 0.62), pcf * CF(0.05, y + 0.62, 0), { c = c3(255, 228, 190), m = M.Neon, t = 0.1 })
	else
		K:vcyl("HomeDiffuser", 0.35, 0.22, pcf * CF(0.05, y + 0.175, 0), L.glass(c3(214, 190, 150), 0.25))
		for k = 0, 4 do
			local a = k * 1.25
			K:seg("HomeDiffuserReed", pcf * V3(0.05, y + 0.3, 0), pcf * V3(0.05 + math.cos(a) * 0.16, y + 1.0, math.sin(a) * 0.12), 0.02, lk(60, 44, 32, M.Wood))
		end
	end
	shelfDeco(self, pcf, w / 2 - 0.6, y, 0.25, "frame", 1.0, seed + 2)
end

-- 오피스텔 ---------------------------------------------------------------------------------------
ROOM["officetel:living"] = function(Cx: any)
	local K = Cx.K
	-- 수납 계단: 아래 5단 아래에 서랍장 (방 쪽으로 서랍)
	local steps = Cx:ownNamed("StairStep")
	table.sort(steps, function(a, b)
		return a.max.Y < b.max.Y
	end)
	local treads = Cx:ownNamed("StairTread")
	K:free(function()
		for i, s in steps do
			if i > 5 then
				-- 위쪽: 철제 계단 판 그대로 + 디딤판 LED
				K:box("HomeStairLED", V3(s.size.X - 0.3, 0.03, 0.04), CF(s.c.X, s.min.Y - 0.02, s.max.Z - 0.05), L.neon(c3(255, 210, 160), 0.1))
				continue
			end
			local top = s.max.Y
			local mn, mx = V3(s.min.X, 0, s.min.Z), V3(s.max.X, top, s.max.Z)
			local body = lk(240, 238, 234)
			K:box("HomeStairBox", mx - mn, CF((mn + mx) / 2), body)
			-- 서랍 앞판: 방 쪽 (+X 쪽이 방이면 그쪽)
			local side = if Cx:mine(V3(s.max.X + 0.6, 0.5, s.c.Z)) then 1 else -1
			local fx = if side > 0 then s.max.X else s.min.X
			local dh = math.max(0.4, top - 0.12)
			K:box("HomeStairDrawer", V3(0.03, dh - 0.08, s.size.Z - 0.08), CF(fx + side * 0.015, dh / 2 + 0.04, s.c.Z), tint(body, -0.03))
			K:box("HomeStairPull", V3(0.04, 0.05, s.size.Z * 0.5), CF(fx + side * 0.04, dh - 0.15, s.c.Z), lk(70, 66, 60, M.Metal))
			Cx:hide(s.part)
		end
		for _, t in treads do
			K:box("HomeStairNosing", V3(t.size.X, 0.05, 0.06), CF(t.c.X, t.max.Y - 0.025, t.max.Z + 0.01), lk(60, 50, 40, M.Wood))
		end
	end)
	-- 로봇청소기 (벽 쪽 도크)
	local doc = Cx:floorAlongWall(1.2, 1.7, 0.8, { score = near(Cx:floorCenter() + V3(-6, 0, 3)) })
	if doc then
		K:free(function()
			Cx.robot = P.robotVacuum(K, doc)
			local h = Cx.robot.home.Position
			local c = Cx:floorCenter()
			Cx.robot.path = { h, h + (doc.ZVector * 2), V3(c.X - 4, 0, c.Z + 1.5), V3(c.X + 4, 0, c.Z + 2.2), V3(c.X + 6, 0, c.Z + 0.5), V3(c.X - 2, 0, c.Z + 2.5), h + (doc.ZVector * 2), h }
		end)
	end
	-- 기타 (책상 쪽 창가)
	local gs = Cx:floorAlongWall(1.0, 0.9, 4.0, { score = near(Cx:floorCenter() + V3(-6, 0, -4)) })
	if gs then
		K:free(function()
			P.guitar(K, gs)
		end)
	end
	-- 왼쪽 큰 벽 (계단 위): 포스터 액자
	local _, _, poster = Cx:wallSpot(4.0, 8.6, 13.4, 0.15, { score = near(Cx:floorCenter() + V3(-15, 0, -2)) })
	if poster then
		K:free(function()
			local f = artFrame(K, poster, 3.6, 4.6, { frame = lk(28, 28, 30, M.Metal), border = 0.06, mat = lk(250, 250, 248) })
			artPaint(K, f, 3.0, 4.0, "sea", Cx.seed + 7, {})
			K:text("HomePosterText", 2.6, 0.3, f * CF(0, -1.75, 0.012), "GWANGALLI · BUSAN", { fg = c3(40, 60, 90), d = 0.004, free = true, font = Enum.Font.GothamBold })
		end)
	end
	-- 벽시계
	local _, _, ck = Cx:wallSpot(1.6, 6.2, 7.8, 0.2, { score = near(Cx:floorCenter() + V3(-6, 0, 4)) })
	if ck then
		K:free(function()
			P.wallClock(Cx, ck, 1.4, lk(28, 28, 30, M.Metal))
		end)
	end
	-- 휴지통 · 슬리퍼
	local tb = Cx:floorAlongWall(0.95, 0.95, 1.3, { score = near(Cx:floorCenter() + V3(-8, 0, -4)) })
	if tb then
		K:free(function()
			P.trashBin(K, tb, lk(60, 62, 66))
		end)
	end
	-- 이 방 프롬프트 4개: 커튼 · 로봇청소기 · 실링팬 · 고양이 (스탠드 토글은 생략)
	Cx.noLampToggle = true
	-- 복층 높은 천장: 실링팬 (거실 가운데, 리니어 펜던트 피해서) + 벽 스위치 (켜면 천천히 돌기 시작)
	do
		local fc0 = Cx:floorCenter()
		local best = nil
		for _, dq in { V3(-3.0, 0, 0), V3(-7.6, 0, 0.2), V3(-8.4, 0, 0.6), V3(-1.2, 0, -1.0), V3(-3.0, 0, 2.6), V3(-6.8, 0, 1.2) } do
			local q = V3(fc0.X + dq.X, 0, fc0.Z + dq.Z)
			-- 천장에 닿는 건 캐노피뿐 (날개는 천장 3 아래): 캐노피 자리만 비었으면 됨
			if Cx:mine(V3(q.X, 0.5, q.Z)) and Cx:ceilFree(q.X, q.Z, 0.6) and Cx:ceilAt(q.X, q.Z) > 12 then
				best = q
				break
			end
		end
		if best then
			local h = Cx:ceilAt(best.X, best.Z)
			Cx:useCeil(best.X, best.Z, 0.6)
			local fan = nil
			K:free(function()
				fan = P.ceilingFan(K, best, h, math.max(12.6, h - 3.2))
			end)
			if fan then
				table.insert(Cx.extraInteract, function()
					local base = {}
					for _, p in fan.spin do
						base[p] = p.CFrame
					end
					local center = (Cx.V.cf * CF(fan.center)).Position
					local speed, target, ang = 0, 0, 0
					Interact.anim(K, function(_t, dt)
						speed += (target - speed) * math.min(1, dt * 0.8)
						if speed < 0.01 and target == 0 then
							return
						end
						ang += speed * dt
						local rot = CFrame.new(center) * CFrame.Angles(0, ang, 0) * CFrame.new(-center)
						for p, cf in base do
							if p.Parent then
								p.CFrame = rot * cf
							end
						end
					end)
					Cx:wallToggle("실링팬", best, false, "실링팬 끄기", "실링팬 켜기", function(st: boolean)
						target = if st then 3.2 else 0
					end, { label = "FAN" })
				end)
			end
		end
	end
	-- 창가 캣타워 (바다 보는 고양이) + 밥그릇 · 물그릇 + 쓰다듬기
	local fc = Cx:floorCenter()
	local ct = Cx:floorAt({ CF(fc.X - 2.8, 0, fc.Z - 2.7), CF(fc.X - 1.4, 0, fc.Z - 2.7), CF(fc.X - 4.0, 0, fc.Z - 2.5), CF(fc.X - 0.2, 0, fc.Z - 2.6), CF(fc.X - 2.8, 0, fc.Z - 1.6) }, V3(2.3, 6.6, 2.3), 0.05)
	if ct then
		local cat = nil
		K:free(function()
			cat = P.catTower(K, ct * ANG(0, 0.3, 0), Cx.seed)
		end)
		local bw = Cx:floorAt({ ct * CF(2.0, 0, 0.6), ct * CF(-2.0, 0, 0.6), ct * CF(0, 0, 2.0) }, V3(1.3, 0.4, 0.6), 0)
		if bw then
			K:free(function()
				K:box("HomeCatMat", V3(1.3, 0.02, 0.6), bw * CF(0, 0.01, 0), lk(200, 210, 220, M.Rubber))
				for k, col in { c3(240, 240, 236), c3(120, 170, 220) } do
					K:vcyl("HomeCatBowl", 0.2, 0.44, bw * CF(-0.32 + (k - 1) * 0.64, 0.12, 0), { c = col, m = M.SmoothPlastic })
					K:disc("HomeCatBowlFill", 0.34, 0.02, bw * CF(-0.32 + (k - 1) * 0.64, 0.2, 0), if k == 1 then lk(150, 100, 60) else L.glass(c3(170, 210, 230), 0.3))
				end
			end)
		end
		if cat then
			table.insert(Cx.extraInteract, function()
				local tail = cat.tail
				local base = {}
				for _, p in tail do
					base[p] = p.CFrame
				end
				local t0 = -10
				local center = (Cx.V.cf * CF(cat.center)).Position
				Interact.anim(K, function(t)
					local u = t - t0
					if u > 4 then
						return
					end
					local a = math.sin(u * 6) * 0.25 * (1 - u / 4)
					local rot = CFrame.new(center) * CFrame.Angles(0, a, 0) * CFrame.new(-center)
					for p, cf in base do
						if p.Parent then
							p.CFrame = rot * cf
						end
					end
				end)
				for _, tgt in { cat.head, cat.ball } do
					local pr = Cx:withPrompt(tgt, function()
						return Interact.prompt(K, tgt, { action = if tgt == cat.head then "쓰다듬기" else "장난감 흔들기", object = "고양이", fn = function()
							t0 = os.clock()
						end })
					end)
					if pr then
						break
					end
				end
			end)
		end
	end
end

ROOM["officetel:loft"] = function(Cx: any)
	local K = Cx.K
	for _, r in Cx:ownNamed("Wardrobe") do
		pcall(function()
			Cx:wardrobe(r, 4)
		end)
	end
	for _, r in Cx:ownNamed("LoftRug") do
		Cx:plainRug(r, "rug_loft")
	end
	for _, r in Cx:ownNamed("Pot") do
		if r.part.Parent and r.part.Parent.Name == "LoftDetail" then
			local h = 2.6
			K:free(function()
				K:disc("HomePlantSaucer", r.size.X + 0.15, 0.06, CF(r.c.X, r.min.Y + 0.03, r.c.Z), lk(200, 196, 188))
				Props.floorPlant(K, CF(r.c.X, r.min.Y + 0.06, r.c.Z), { kind = "snake", h = h, dia = r.size.X, pot = lk(222, 218, 208, M.Concrete) })
			end)
			Cx:hide(r.part)
			for _, q in Cx:ownNamed("Soil", "Leaves") do
				if (q.c - r.c).Magnitude < 1.5 then
					Cx:hide(q.part)
				end
			end
		end
	end
	local fc = Cx:floorCenter()
	local bedP = slotAt(Cx, "bed") or fc
	-- 침대 머리 위 액자 선반 (낮은 천장: 머리 높이 위 3.3)
	local _, _, ledge = Cx:wallSpot(4.2, 3.0, 4.4, 0.4, { score = near(bedP + V3(-4, 0, 0)) })
	if ledge then
		K:free(function()
			P.pictureLedge(Cx, ledge * CF(0, -0.55, 0), 4.0, lk(214, 186, 146, M.Wood), Cx.seed + 21, { c3(196, 210, 220), c3(226, 200, 170), c3(60, 80, 100) })
		end)
	end
	-- 침대 옆 독서등 (벽 부착, 내 불빛): 협탁 반대쪽 머리맡
	local nsZ = nil
	for _, q in Cx:ownNamed("Nightstand") do
		nsZ = q.c.Z
	end
	local lampSide = if nsZ and nsZ < bedP.Z then 1 else -1
	local _, _, rl = Cx:wallSpot(0.6, 3.4, 4.4, 0.6, { score = near(bedP + V3(-4, 0, lampSide * 2.9)) })
	if rl then
		K:free(function()
			K:disc("HomeReadingLampMount", 0.3, 0.06, rl * CF(0, 0, 0.03) * ANG(PI / 2, 0, 0), L.brass)
			K:seg("HomeReadingLampArm", (rl * CF(0, 0, 0.06)).Position, (rl * CF(0, 0.3, 0.5)).Position, 0.05, L.brass)
			local head = K:cyl("HomeReadingLampHead", 0.35, 0.24, rl * CF(0, 0.28, 0.58) * ANG(0, 0, math.rad(-60)), L.brass)
			local bulb = K:disc("HomeReadingLampBulb", 0.18, 0.02, rl * CF(0, 0.12, 0.62) * ANG(0, 0, 0), L.lampWarm)
			local l = Cx:light(bulb, "SpotLight", { Face = Enum.NormalId.Bottom, Range = 9, Brightness = 0.8, Angle = 70, Color = L.warmLight })
			Cx.lamps = Cx.lamps or {}
			table.insert(Cx.lamps, { glow = bulb, light = l, name = "독서등" })
			local _ = head
		end)
	end
	-- 낮은 책장 (등 벽, 화분과 옷장 사이)
	local shelfP = Cx:floorAlongWall(3.0, 1.0, 2.9, { score = near(fc + V3(-3.5, 0, 4.4)) })
	if shelfP then
		K:free(function()
			Cx:lowShelf(shelfP, 3.0, 2.0, lk(212, 184, 146, M.Wood), { seed = 31, moodLamp = true })
		end)
		if Cx.moodLamp then
			local ml: BasePart = Cx.moodLamp
			local light = Cx:light(ml, "PointLight", { Range = 7, Brightness = 0.45, Color = c3(255, 200, 140) })
			Cx.lamps = Cx.lamps or {}
			table.insert(Cx.lamps, { glow = ml, light = light, base = shelfP.Position, name = "무드등" })
		end
	end
	local mir = Cx:floorAlongWall(1.7, 0.6, 5.0, { score = near(Cx:floorCenter() + V3(8, 0, 2)) })
	if mir then
		K:free(function()
			P.leanMirror(K, mir, 4.8, L.blackMetal)
		end)
	end
	-- 바다 쪽 독서 자리: 러그 위 빈백 (난간 쪽을 봄) + 사이드 테이블 (머그 · 책)
	local rug = Cx:ownNamed("LoftRug")[1]
	if rug then
		local c = V3(rug.c.X - 0.2, 0, rug.c.Z - 0.6)
		local face = if Cx:mine(V3(c.X + 3, 0.5, c.Z)) then V3(1, 0, 0) else V3(-1, 0, 0)
		local bb = CFrame.lookAt(c, c - face) * ANG(0, PI, 0) * ANG(0, 0.35, 0)
		-- 러그 위: 러그 두께만큼 띄워서 자리 확인 (러그는 바닥 가구로 잡혀 있음)
		if not Cx.V.decorPlus and K:spot(bb * CF(0, 0.08, 0), V3(2.4, 2.2, 2.4), 0.05) then
			K:free(function()
				P.beanBag(K, bb, lk(232, 226, 214, M.Fabric))
				K:ell("HomeThrowFold", V3(1.2, 0.2, 0.6), bb * CF(0.45, 1.35, -0.4) * ANG(0.3, 0.2, 0.2), lk(150, 160, 150, M.Fabric))
			end)
			local st = nil
			for _, off in { V3(0.3, 0, 2.2), V3(-0.4, 0, 2.2), V3(1.9, 0, 1.2), V3(-1.7, 0, 1.3) } do
				local q = CF(c.X + off.X, 0, c.Z + off.Z)
				if Cx:mine(q.Position + V3(0, 0.5, 0)) and K:spot(q * CF(0, 0.08, 0), V3(0.9, 1.6, 0.9), 0.02) then
					st = q * CF(0, 0.06, 0) -- 러그 위에 올림
					break
				end
			end
			if st then
				K:free(function()
					K:disc("HomeSideTableTop", 0.9, 0.06, st * CF(0, 1.5, 0), lk(36, 36, 38, M.Metal))
					K:vcyl("HomeSideTableStem", 1.45, 0.07, st * CF(0, 0.75, 0), lk(36, 36, 38, M.Metal))
					K:disc("HomeSideTableFoot", 0.7, 0.05, st * CF(0, 0.025, 0), lk(36, 36, 38, M.Metal))
					mug(K, st * CF(-0.15, 1.53, 0.1), lk(214, 200, 180))
					bookStack(K, st * CF(0.12, 1.53, -0.12) * ANG(0, 0.5, 0), 2, Cx.seed + 41)
				end)
			end
		end
	end
	-- 홈트 자리 (난간 쪽): 요가 매트 · 덤벨 · 폼롤러
	local wd = Cx:ownNamed("Wardrobe")[1]
	if wd then
		local mz = wd.c.Z
		local mx = 2.2
		local mat = CF(mx, 0, mz)
		if not Cx.V.decorPlus and Cx:mine(V3(mx + 0.9, 0.5, mz)) and K:spot(mat, V3(2.1, 0.1, 5.6), 0) then
			K:free(function()
				K:slab("HomeYogaMat", 2.1, 5.6, 0.04, 0.12, mat * CF(0, 0.02, 0), lk(150, 170, 190, M.Rubber))
				K:cyl("HomeYogaMatRoll", 2.1, 0.32, mat * CF(0, 0.16, -2.95), lk(130, 150, 170, M.Rubber))
				for i, dz in { -0.8, -0.2 } do
					local db = mat * CF(0.6, 0.12, 2.0 + dz) * ANG(0, 0.2 * i, 0)
					K:cyl("HomeDumbbellBar", 0.75, 0.07, db, L.chrome)
					for _, sx in { -0.28, 0.28 } do
						K:cyl("HomeDumbbellBell", 0.16, 0.26, db * CF(sx, 0, 0), lk(60, 62, 70, M.Rubber))
					end
				end
				K:cyl("HomeFoamRoller", 1.1, 0.42, mat * CF(-0.45, 0.21, 2.05) * ANG(0, PI / 2 - 0.3, 0), lk(60, 70, 90, M.SmoothPlastic))
			end)
		end
	end
	-- 끝벽: 빨래 건조대 (오피스텔은 베란다가 없어서 복층에 말림)
	local rk = Cx:floorAlongWall(3.6, 1.8, 3.3, { score = near(fc + V3(0.6, 0, 15)), gap = 0.3 })
	if rk then
		local mn, mx = laabb(rk * CF(0, 1.65, 0), V3(3.6, 3.3, 1.8))
		Cx:dryingRack(mn, mx, {}, { c3(240, 240, 236), c3(60, 64, 72), c3(170, 190, 210), c3(214, 200, 180) })
	end
	-- 옷장 끝 · 끝벽: 3단 트롤리
	local cart = Cx:floorAlongWall(1.4, 1.0, 2.6, { score = near(fc + V3(-3.5, 0, 14)) })
	if cart then
		K:free(function()
			P.rollingCart(K, cart, lk(240, 240, 238, M.Metal), Cx.seed)
		end)
	end
end

ROOM["officetel:main"] = function(Cx: any)
	local K = Cx.K
	local _, _, art = Cx:wallSpot(2.2, 3.6, 6.4, 0.12, { score = near(Cx:floorCenter()) })
	if art then
		K:free(function()
			local f = artFrame(K, art, 2.0, 2.6, { frame = lk(28, 28, 30, M.Metal), border = 0.05, mat = lk(250, 250, 248) })
			artPaint(K, f, 1.5, 2.1, "abstract", Cx.seed, { c3(236, 232, 224), c3(60, 90, 120), c3(210, 150, 100) })
		end)
	end
end

-- 아파트 ----------------------------------------------------------------------------------------
ROOM["apartment:living"] = function(Cx: any)
	local K = Cx.K
	local fc = Cx:floorCenter()
	-- 로봇청소기
	local doc = Cx:floorAlongWall(1.2, 1.7, 0.8, { score = near(fc + V3(-6, 0, 6)) })
	if doc then
		K:free(function()
			Cx.robot = P.robotVacuum(K, doc)
			local h = Cx.robot.home.Position
			Cx.robot.path = { h, h + doc.ZVector * 2, V3(fc.X - 5, 0, fc.Z + 4), V3(fc.X + 5, 0, fc.Z + 4.5), V3(fc.X + 5, 0, fc.Z - 4.5), V3(fc.X - 2, 0, fc.Z + 5), h + doc.ZVector * 2, h }
		end)
	end
	-- 아이 장난감 바구니
	local toy = Cx:floorAlongWall(1.7, 1.2, 2.0, { score = near(fc + V3(6, 0, 5)) })
	if toy then
		K:free(function()
			P.toyBasket(K, toy)
		end)
	end
	-- 가족사진 (벽)
	local _, _, ph = Cx:wallSpot(3.4, 3.6, 6.0, 0.12, { score = near(fc + V3(0, 0, 7)) })
	if ph then
		K:free(function()
			P.photoCluster(Cx, ph * CF(0, 0.2, 0), 5, Cx.seed)
		end)
	end
	-- 벽시계
	local _, _, ck = Cx:wallSpot(1.8, 5.8, 7.4, 0.2, { score = near(fc + V3(0, 0, 7)) })
	if ck then
		K:free(function()
			P.wallClock(Cx, ck, 1.5, L.walnut)
		end)
	end
	-- 휴지통
	local tb = Cx:floorAlongWall(0.95, 0.95, 1.3, { score = near(fc + V3(7, 0, 6)) })
	if tb then
		K:free(function()
			P.trashBin(K, tb)
		end)
	end
end

ROOM["apartment:bedroom"] = function(Cx: any)
	local K = Cx.K
	local fc = Cx:floorCenter()
	-- 화장대 + 거울 + 스툴 + 화장품
	local dz = Cx:ownNamed("Dresser")[1]
	if dz then
		local F, info = propFrame(Cx, dz.part)
		local x0, x1, y1, z0, z1 = info.min.X, info.max.X, info.max.Y, info.min.Z, info.max.Z
		K:free(function()
			boxF(K, "HomeVanityBody", F, V3(x0, 0.3, z0), V3(x1, y1 - 0.08, z1 - 0.03), lk(244, 242, 238))
			K:slab("HomeVanityTop", x1 - x0 + 0.04, z1 - z0 + 0.04, 0.08, 0.04, F * CF((x0 + x1) / 2, y1 - 0.04, (z0 + z1) / 2), L.marbleWhite)
			for _, sx in { x0 + 0.15, x1 - 0.15 } do
				K:box("HomeVanityLeg", V3(0.12, 0.3, 0.12), F * CF(sx, 0.15, z1 - 0.2), L.brass)
				K:box("HomeVanityLeg", V3(0.12, 0.3, 0.12), F * CF(sx, 0.15, z0 + 0.2), L.brass)
			end
			for i = 1, 3 do
				local xc = x0 + (x1 - x0) * (i - 0.5) / 3
				K:box("HomeVanityDrawer", V3((x1 - x0) / 3 - 0.06, y1 - 0.5, 0.03), F * CF(xc, (y1 + 0.22) / 2, z1 - 0.01), lk(250, 248, 244))
				K:box("HomeVanityPull", V3(0.4, 0.04, 0.04), F * CF(xc, y1 - 0.3, z1 + 0.015), L.brass)
			end
			-- 화장품 (스킨 · 로션 · 크림 · 향수 · 브러시 통 · 드라이기)
			local y = y1
			local items = { { "HomeSkin", 0.18, 0.55, c3(250, 236, 240) }, { "HomeLotion", 0.2, 0.45, c3(236, 240, 250) }, { "HomeEssence", 0.14, 0.4, c3(200, 160, 120) }, { "HomeSerum", 0.12, 0.32, c3(230, 200, 140) } }
			for i, it in items do
				K:vcyl(it[1], it[3], it[2], F * CF(x0 + 0.4 + i * 0.28, y + it[3] / 2, z0 + 0.35), { c = it[4], m = M.Glass, t = 0.1 })
				K:vcyl(it[1] .. "Cap", 0.1, it[2] * 0.75, F * CF(x0 + 0.4 + i * 0.28, y + it[3] + 0.05, z0 + 0.35), L.goldMetal)
			end
			K:vcyl("HomeCream", 0.16, 0.34, F * CF(x1 - 0.7, y + 0.08, z0 + 0.5), lk(250, 250, 250))
			K:vcyl("HomeBrushCup", 0.4, 0.24, F * CF(x1 - 0.35, y + 0.2, z0 + 0.35), lk(230, 210, 190))
			for j = 0, 2 do
				K:seg("HomeMakeupBrush", F * V3(x1 - 0.35, y + 0.3, z0 + 0.35), F * V3(x1 - 0.35 + (j - 1) * 0.08, y + 0.75, z0 + 0.35 + (j - 1) * 0.05), 0.04, lk(30, 30, 32))
			end
			K:ell("HomeHairDryer", V3(0.3, 0.3, 0.6), F * CF(x1 - 0.9, y + 0.15, z1 - 0.35) * ANG(0, 0.6, 0), lk(250, 220, 226))
			K:vcyl("HomePerfume", 0.32, 0.22, F * CF(x0 + 1.6, y + 0.16, z0 + 0.6), L.glass(c3(240, 200, 210), 0.25))
			K:box("HomePerfumeCap", V3(0.14, 0.12, 0.14), F * CF(x0 + 1.6, y + 0.38, z0 + 0.6), L.goldMetal)
		end)
		Cx:hide(dz.part)
		for _, q in Cx:ownNamed("Perfume") do
			Cx:hide(q.part)
		end
		-- 거울 (프레임 + LED 테두리)
		local mr = Cx:ownNamed("DresserMirror")[1]
		if mr then
			local d = Cx:wallFace(mr.part)
			if d then
				local w, h = math.max(mr.size.X, mr.size.Z), mr.size.Y
				local c = CFrame.fromMatrix(V3(d.Position.X, mr.c.Y, d.Position.Z), d.XVector, YA, d.ZVector)
				K:free(function()
					K:panel("HomeVanityMirrorFrame", w + 0.16, h + 0.16, 0.06, 0.4, c, lk(236, 230, 220))
					K:panel("HomeVanityMirror", w, h, 0.08, 0.36, c, L.mirror)
					K:panel("HomeVanityMirrorLED", w + 0.04, h + 0.04, 0.02, 0.38, c * CF(0, 0, -0.02), L.neon(c3(255, 236, 214), 0.3))
				end)
				Cx:hide(mr.part)
			end
		end
		local st = Cx:ownNamed("Stool")[1]
		if st then
			K:free(function()
				local top = st.max.Y
				K:disc("HomeVanityStoolSeat", math.max(st.size.X, st.size.Z), 0.35, CF(st.c.X, top - 0.175, st.c.Z), lk(232, 220, 206, M.Fabric))
				K:disc("HomeVanityStoolWelt", math.max(st.size.X, st.size.Z) + 0.03, 0.04, CF(st.c.X, top - 0.3, st.c.Z), lk(196, 176, 150, M.Fabric))
				for i = 0, 3 do
					local a = i * PI / 2 + PI / 4
					K:seg("HomeVanityStoolLeg", V3(st.c.X + math.cos(a) * 0.35, top - 0.35, st.c.Z + math.sin(a) * 0.35), V3(st.c.X + math.cos(a) * 0.5, 0.02, st.c.Z + math.sin(a) * 0.5), 0.07, L.brass)
				end
			end)
			Cx:hide(st.part)
		end
	end
	-- 안방 TV (화면은 그대로)
	for _, scr in Cx:ownNamed("TVScreen") do
		local tvm = scr.part.Parent
		if tvm and tvm.Name == "MasterTV" then
			local F, info = propFrame(Cx, tvm, "TV")
			local sr = first(info, "TVScreen")
			if sr then
				K:free(function()
					tvBezel(Cx, F, sr, { bezel = 0.045, depth = 0.08 })
					K:box("HomeTVMount", V3(sr.size.X * 0.4, sr.size.Y * 0.35, 0.06), F * CF(sr.c.X, sr.c.Y, sr.min.Z - 0.12), lk(40, 40, 44, M.Metal))
				end)
				for _, q in tvm:GetDescendants() do
					if q:IsA("BasePart") and q.Name == "TV" then
						Cx:hide(q)
					end
				end
			end
		end
	end
	-- 가습기 · 빨래 바구니 · 전신 거울
	local hm = Cx:floorAlongWall(0.8, 0.8, 1.2, { score = near(fc + V3(-5, 0, -2)) })
	if hm then
		K:free(function()
			P.humidifier(K, hm)
		end)
	end
	local bas = Cx:floorAlongWall(1.5, 1.1, 1.6, { score = near(fc + V3(5, 0, 6)) })
	if bas then
		K:free(function()
			P.laundryBasket(K, bas, { c3(240, 240, 236), c3(150, 160, 190), c3(220, 200, 190) })
		end)
	end
	-- 침대 아래 러그 (울 · 테두리)
	Cx:bedRug(lk(222, 214, 200, M.Fabric), lk(176, 160, 138, M.Fabric))
	-- 침대 머리 위 벽: 광안대교 노을 사진 (캔버스 액자)
	local _, _, wed = Cx:wallSpot(4.2, 4.4, 7.0, 0.14, { score = near(slotAt(Cx, "bed") or (fc + V3(0, 0, -6))) })
	if wed then
		K:free(function()
			local f = artFrame(K, wed, 4.0, 2.4, { frame = lk(232, 226, 214, M.Wood), border = 0.1, mat = lk(250, 250, 248) })
			artPaint(K, f, 3.4, 1.8, "sea", Cx.seed + 3, {})
		end)
	end
	-- TV 아래: 6단 서랍장 (낮은 체스트) + 위 소품
	local tvP = nil
	for _, scr in Cx:ownNamed("TVScreen") do
		tvP = scr.c
	end
	if tvP then
		local ch = Cx:floorAlongWall(4.6, 1.5, 2.8, { score = near(tvP) })
		if ch then
			K:free(function()
				local W, H, D = 4.6, 2.6, 1.5
				local body = lk(244, 240, 232)
				K:box("HomeChestBody", V3(W, H - 0.3, D - 0.04), ch * CF(0, 0.3 + (H - 0.3) / 2, -0.02), body)
				K:box("HomeChestTop", V3(W + 0.06, 0.08, D + 0.04), ch * CF(0, H + 0.04, 0), L.oak)
				for _, sx in { -W / 2 + 0.2, W / 2 - 0.2 } do
					for _, sz in { -D / 2 + 0.2, D / 2 - 0.2 } do
						K:seg("HomeChestLeg", ch * V3(sx, 0.32, sz), ch * V3(sx + (if sx < 0 then -0.04 else 0.04), 0.02, sz + (if sz < 0 then -0.03 else 0.03)), 0.1, L.oak)
					end
				end
				for col = 0, 1 do
					for row = 0, 2 do
						local dx = (col - 0.5) * (W / 2)
						local yy = 0.38 + row * 0.72 + 0.34
						K:box("HomeChestDrawer", V3(W / 2 - 0.08, 0.66, 0.03), ch * CF(dx, yy, D / 2 - 0.01), lk(250, 248, 242))
						K:box("HomeChestPull", V3(0.5, 0.05, 0.05), ch * CF(dx, yy + 0.12, D / 2 + 0.02), L.brass)
					end
				end
				-- 위: 액자 · 보석 트레이 · 디퓨저 · 작은 화분 · 책
				local y = H + 0.08
				shelfDeco(Cx, ch, -1.5, y, 0.25, "frame", 1.1, Cx.seed + 1)
				K:box("HomeJewelTray", V3(0.8, 0.05, 0.5), ch * CF(-0.4, y + 0.025, 0.2), L.brass)
				K:ring("HomeRing", ch * CF(-0.55, y + 0.08, 0.25) * ANG(PI / 2, 0, 0), 0.05, 0.02, 6, L.goldMetal)
				K:cyl("HomeWatch", 0.06, 0.24, ch * CF(-0.25, y + 0.08, 0.15) * ANG(0, 0, PI / 2), L.chrome)
				K:vcyl("HomeDiffuser", 0.4, 0.22, ch * CF(0.5, y + 0.2, -0.2), L.glass(c3(214, 190, 150), 0.25))
				for k = 0, 4 do
					local a = k * 1.25
					K:seg("HomeDiffuserReed", ch * V3(0.5, y + 0.35, -0.2), ch * V3(0.5 + math.cos(a) * 0.16, y + 1.05, -0.2 + math.sin(a) * 0.12), 0.02, lk(60, 44, 32, M.Wood))
				end
				shelfDeco(Cx, ch, 1.6, y, 0.45, "plant", 1.1, Cx.seed + 2)
				bookStack(K, ch * CF(1.0, y, 0.35) * ANG(0, 0.3, 0), 2, Cx.seed + 7)
			end)
		end
	end
	-- 화장대 거울 LED (켜고 끄기)
	table.insert(Cx.extraInteract, function()
		local led = nil
		for _, p in K.parts do
			if p.Name == "HomeVanityMirrorLED" and p.Parent then
				led = p
			end
		end
		if not led then
			return
		end
		local col = led.Color
		Cx:withPrompt(led, function()
			return Interact.toggle(K, led, { object = "화장대 거울 조명", state = true, onText = "끄기", offText = "켜기", on = function(st: boolean)
				led.Material = if st then M.Neon else M.SmoothPlastic
				led.Color = if st then col else c3(200, 196, 190)
				led.Transparency = if st then 0.3 else 0.6
			end })
		end)
	end)
end

ROOM["apartment:dress"] = function(Cx: any)
	local K = Cx.K
	local rails = Cx:ownNamed("HangerRail")
	local clothes = Cx:ownNamed("Clothes")
	-- 봉 뒤 벽의 뚫린 곳 (욕실 문 등): 봉 방향 좌표 구간
	local railGaps = {}
	for _, r in rails do
		local alongZ = r.size.Z >= r.size.X
		local gaps = {}
		if alongZ then
			local side = if r.c.X > Cx:floorCenter().X then 1 else -1
			local wx = nil
			for d = 0.6, 1.8, 0.1 do
				if Cx:insideWall(V3(r.c.X + side * d, 1.0, r.c.Z)) or Cx:insideWall(V3(r.c.X + side * d, 1.0, r.min.Z + 0.5)) then
					wx = r.c.X + side * (d + 0.15)
					break
				end
			end
			if wx then
				local g0 = nil
				local z = r.min.Z
				while z <= r.max.Z + 0.01 do
					local open = not Cx:insideWall(V3(wx, 1.0, z))
					if open and not g0 then
						g0 = z
					elseif not open and g0 then
						table.insert(gaps, { g0, z })
						g0 = nil
					end
					z += 0.2
				end
				if g0 then
					table.insert(gaps, { g0, r.max.Z })
				end
			end
		end
		railGaps[r] = gaps
	end
	for _, r in rails do
		local mine = {}
		for _, c in clothes do
			local alongX = r.size.X >= r.size.Z
			if (alongX and math.abs(c.c.Z - r.c.Z) < 0.6) or (not alongX and math.abs(c.c.X - r.c.X) < 0.6) then
				table.insert(mine, c)
			end
		end
		table.sort(mine, function(a, b)
			return a.c.X + a.c.Z < b.c.X + b.c.Z
		end)
		Cx:clothesRail(r, mine, { gaps = railGaps[r] })
	end
	-- 선반 (위) + 개킨 옷 · 가방 · 모자 상자
	for i, sh in Cx:ownNamed("ClosetShelf") do
		local alongZ = sh.size.Z >= sh.size.X
		K:free(function()
			K:box("HomeClosetShelf", sh.size, CF(sh.c), lk(240, 236, 228, M.Wood))
			K:box("HomeClosetShelfLED", if alongZ then V3(0.06, 0.02, sh.size.Z - 0.3) else V3(sh.size.X - 0.3, 0.02, 0.06), CF(sh.c.X, sh.min.Y - 0.015, sh.c.Z), L.neon(c3(255, 230, 200), 0.15))
			local len = if alongZ then sh.size.Z else sh.size.X
			local n = math.floor(len / 1.1)
			for j = 1, n do
				local t = -len / 2 + len * (j - 0.5) / n
				local p = if alongZ then V3(sh.c.X, sh.max.Y, sh.c.Z + t) else V3(sh.c.X + t, sh.max.Y, sh.c.Z)
				local kind = (j + i) % 4
				if kind == 0 then
					K:rbox("HomeHatBox", V3(0.8, 0.6, 0.8), 0.06, CF(p + V3(0, 0.3, 0)), lk(236, 226, 210))
				elseif kind == 1 then
					K:rbox("HomeHandbag", V3(0.8, 0.55, 0.35), 0.1, CF(p + V3(0, 0.28, 0)) * ANG(0, if alongZ then PI / 2 else 0, 0), lk(150, 90, 60, M.Leather))
					K:ring("HomeHandbagStrap", CF(p + V3(0, 0.6, 0)) * ANG(0, if alongZ then PI / 2 else 0, 0), 0.25, 0.04, 6, lk(130, 80, 54, M.Leather), 0, PI)
				else
					for k = 0, 2 do
						local sc = ({ c3(214, 200, 180), c3(60, 70, 90), c3(160, 60, 60), c3(230, 230, 226), c3(120, 130, 110) })[(j * 3 + k + i) % 5 + 1]
						local scf = CF(p + V3(0, 0.08 + k * 0.17, 0)) * ANG(0, (if alongZ then PI / 2 else 0) + (rnd(j * 7 + i, k) - 0.5) * 0.12, 0)
						K:box("HomeFoldedSweater", V3(0.85, 0.15, 0.7), scf, { c = sc, m = M.Fabric })
						if k == 0 or K.detail ~= "low" then
							K:box("HomeSweaterFold", V3(0.86, 0.03, 0.04), scf * CF(0, 0.02, 0.34), { c = sc:Lerp(Color3.new(0, 0, 0), 0.12), m = M.Fabric })
						end
					end
				end
			end
		end)
		Cx:hide(sh.part)
	end
	-- 옷 아래: 한쪽 벽은 3단 서랍장 (앞판이 통로 쪽), 다른 쪽은 2단 신발 선반. 벽이 뚫린 곳(문)은 비움
	local fcx = Cx:floorCenter().X
	for si, r in rails do
		local alongZ = r.size.Z >= r.size.X
		if not alongZ then
			continue
		end
		local toWall = if r.c.X > fcx then 1 else -1
		local wf = nil -- 벽 안쪽 면 X
		for d = 0.3, 1.8, 0.05 do
			if Cx:insideWall(V3(r.c.X + toWall * d, 1.0, r.c.Z)) or Cx:insideWall(V3(r.c.X + toWall * d, 1.0, r.min.Z + 0.6)) then
				wf = r.c.X + toWall * (d - 0.03)
				break
			end
		end
		if not wf then
			continue
		end
		local dep = if si == 1 then 1.3 else 0.85
		local back, front = wf - toWall * 0.02, wf - toWall * (dep + 0.02)
		-- 봉 길이 안에서 문 구간을 뺀 조각들
		local runs = {}
		local cur = r.min.Z + 0.3
		for _, g in railGaps[r] or {} do
			if g[1] - 0.35 - cur > 1.4 then
				table.insert(runs, { cur, g[1] - 0.35 })
			end
			cur = math.max(cur, g[2] + 0.35)
		end
		if r.max.Z - 0.3 - cur > 1.4 then
			table.insert(runs, { cur, r.max.Z - 0.3 })
		end
		local best = nil
		for _, rn in runs do
			local z0, z1 = rn[1], rn[2]
			local zc, zl = (z0 + z1) / 2, z1 - z0
			local mn = V3(math.min(back, front), 0, z0)
			local mx = V3(math.max(back, front), if si == 1 then 2.4 else 1.0, z1)
			if not Cx:boxFree(mn, mx, { noKeep = true }) then
				continue
			end
			Cx:use(mn, mx)
			local fx = front -- 앞판 면
			K:free(function()
				if si == 1 then
					K:box("HomeDressDrawers", V3(mx.X - mn.X, 2.3, zl), CF((mn.X + mx.X) / 2, 1.2 + 0.05, zc), lk(242, 238, 230))
					K:box("HomeDressDrawerKick", V3(mx.X - mn.X - 0.1, 0.1, zl - 0.1), CF((mn.X + mx.X) / 2 + toWall * 0.05, 0.05, zc), lk(60, 58, 56))
					local cols = if zl > 3.6 then 2 else 1
					for cI = 1, cols do
						local cz = z0 + zl * (cI - 0.5) / cols
						local cw = zl / cols - 0.08
						for j = 1, 3 do
							local yy = 0.15 + 0.72 * (j - 0.5) + 0.05
							local slide = (j >= 2 and not Cx.dressSlide and Cx:promptOk(V3(fx - toWall * 0.04, yy + 0.2, cz)))
							local parts = {}
							table.insert(parts, K:box("HomeDressDrawerFront", V3(0.03, 0.66, cw), CF(fx - toWall * 0.015, yy, cz), lk(250, 248, 244)))
							table.insert(parts, K:box("HomeDressDrawerPull", V3(0.04, 0.04, math.min(1.0, cw * 0.4)), CF(fx - toWall * 0.04, yy + 0.2, cz), L.brass))
							if slide then
								-- 열리는 서랍 (닫혀 있을 땐 본체 속): 서랍 통 + 개킨 티셔츠 · 양말 말이 · 넥타이
								local inner = CF(fx + toWall * 0.5, yy - 0.12, cz)
								table.insert(parts, K:box("HomeDrawerTrayBottom", V3(0.95, 0.04, cw - 0.12), inner * CF(0, -0.18, 0), lk(226, 220, 210, M.Wood)))
								for _, sz in { -1, 1 } do
									table.insert(parts, K:box("HomeDrawerTraySide", V3(0.95, 0.4, 0.03), inner * CF(0, 0, sz * (cw / 2 - 0.08)), lk(226, 220, 210, M.Wood)))
								end
								local tcol = { c3(240, 240, 236), c3(60, 70, 90), c3(170, 180, 190), c3(220, 200, 170) }
								local nT = math.max(2, math.floor((cw - 0.3) / 0.62))
								for t = 1, nT do
									local tz = -cw / 2 + 0.15 + (cw - 0.3) * (t - 0.5) / nT
									table.insert(parts, K:box("HomeDrawerTee", V3(0.7, 0.12, 0.52), inner * CF(0, -0.1, tz), { c = tcol[(t - 1) % #tcol + 1], m = M.Fabric }))
									table.insert(parts, K:box("HomeDrawerTee", V3(0.7, 0.12, 0.52), inner * CF(0, 0.02, tz), { c = tcol[t % #tcol + 1], m = M.Fabric }))
								end
								Cx.dressSlide = { parts = parts, dir = V3(-toWall, 0, 0) }
							end
						end
					end
					K:box("HomeDressDrawerTop", V3(mx.X - mn.X + 0.04, 0.06, zl + 0.04), CF((mn.X + mx.X) / 2, 2.43, zc), L.oak)
					if not best or zl > best.len then
						best = { front = fx, side = -toWall, z = zc, len = zl }
					end
				else
					for k = 0, 1 do
						K:box("HomeShoeShelf", V3(mx.X - mn.X, 0.06, zl), CF((mn.X + mx.X) / 2, 0.15 + k * 0.5, zc), lk(240, 236, 228, M.Wood))
						local n = math.floor(zl / 0.75)
						for j = 1, n do
							local z = z0 + zl * (j - 0.5) / n
							local col = ({ c3(30, 30, 32), c3(240, 240, 236), c3(150, 100, 60), c3(200, 60, 60), c3(60, 80, 130) })[(j + k * 2) % 5 + 1]
							for q = -1, 1, 2 do
								-- 신발 한 짝: 밑창 + 갑피, 길이 방향 = 벽 → 통로
								local scf = CF((mn.X + mx.X) / 2, 0.18 + k * 0.5, z + q * 0.16) * ANG(0, PI / 2 + q * 0.04, 0)
								-- 운동화 (흰 밑창 · 뒤꿈치 높고 앞코 둥근 갑피 · 발 넣는 구멍) / 로퍼 (얇은 밑창 · 낮은 갑피)
								local loafer = col.R < 0.62 and col.G < 0.45 and col.B < 0.3 or (col.R < 0.15 and col.G < 0.15)
								if loafer then
									K:box("HomeShoeSole", V3(0.27, 0.035, 0.76), scf * CF(0, 0.018, 0), lk(40, 30, 24))
									K:ell("HomeShoe", V3(0.26, 0.17, 0.72), scf * CF(0, 0.1, 0.0), { c = col, m = M.Leather })
									K:ell("HomeShoeOpening", V3(0.17, 0.02, 0.3), scf * CF(0, 0.18, -0.15), lk(30, 24, 20))
								else
									K:box("HomeShoeSole", V3(0.28, 0.06, 0.76), scf * CF(0, 0.03, 0), lk(242, 240, 234))
									K:box("HomeShoeHeel", V3(0.25, 0.2, 0.34), scf * CF(0, 0.16, -0.19), { c = col, m = M.Fabric })
									K:ell("HomeShoe", V3(0.25, 0.2, 0.56), scf * CF(0, 0.1, 0.08), { c = col, m = M.Fabric })
									K:ell("HomeShoeOpening", V3(0.17, 0.02, 0.22), scf * CF(0, 0.26, -0.2), lk(36, 36, 40))
								end
							end
						end
					end
				end
			end)
		end
		if best then
			Cx.dressDrawer = best
		end
	end
	-- 서랍장 위 (옷 아래 빈 칸): 시계 보관함 · 보석함 · 향수 · 스카프
	local dd = Cx.dressDrawer
	if dd then
		local xc = dd.front - dd.side * 0.55
		local y = 2.46
		local F = CF(xc, y, dd.z) * ANG(0, if dd.side > 0 then PI / 2 else -PI / 2, 0) -- +Z = 통로 쪽
		K:free(function()
			-- 시계 보관함 (유리 뚜껑 + 쿠션 3개 + 시계)
			local wb = F * CF(-1.6, 0, 0)
			K:box("HomeWatchBox", V3(1.1, 0.3, 0.6), wb * CF(0, 0.15, 0), L.walnut)
			K:box("HomeWatchBoxGlass", V3(1.0, 0.02, 0.5), wb * CF(0, 0.31, 0), L.glass(c3(220, 230, 236), 0.55))
			for i = -1, 1 do
				K:ell("HomeWatchPillow", V3(0.26, 0.18, 0.36), wb * CF(i * 0.32, 0.25, 0), lk(220, 214, 200, M.Fabric))
				K:cyl("HomeWatchFace", 0.05, 0.2, wb * CF(i * 0.32, 0.3, 0.04) * ANG(0, PI / 2, 0) * ANG(0, 0, 0), if i == 0 then L.goldMetal else L.chrome)
			end
			-- 보석함 (열린 서랍 · 반지 · 귀걸이)
			local jb = F * CF(-0.2, 0, -0.05)
			K:rbox("HomeJewelBox", V3(0.8, 0.32, 0.55), 0.04, jb * CF(0, 0.16, 0), lk(236, 226, 214, M.Leather))
			K:box("HomeJewelVelvet", V3(0.7, 0.02, 0.45), jb * CF(0, 0.33, 0), lk(120, 40, 60, M.Fabric))
			K:ring("HomeRing", jb * CF(-0.18, 0.36, 0.05) * ANG(PI / 2, 0, 0), 0.05, 0.02, 6, L.goldMetal)
			K:ball("HomeEarring", 0.05, jb * CF(0.1, 0.36, 0.08), lk(250, 250, 248, M.Glass))
			K:ball("HomeEarring", 0.05, jb * CF(0.18, 0.36, 0.08), lk(250, 250, 248, M.Glass))
			-- 향수 2
			for i, col in { c3(240, 210, 220), c3(220, 200, 150) } do
				local pf = F * CF(0.75 + (i - 1) * 0.3, 0, -0.1)
				K:box("HomePerfumeBottle", V3(0.2, 0.32, 0.12), pf * CF(0, 0.16, 0), L.glass(col, 0.2))
				K:vcyl("HomePerfumeCap", 0.12, 0.1, pf * CF(0, 0.38, 0), L.goldMetal)
			end
			-- 개어 둔 스카프
			K:box("HomeScarf", V3(0.7, 0.06, 0.45), F * CF(1.6, 0.03, 0) * ANG(0, 0.1, 0), lk(196, 120, 90, M.Fabric))
			K:box("HomeScarfStripe", V3(0.72, 0.065, 0.06), F * CF(1.6, 0.03, 0.12) * ANG(0, 0.1, 0), lk(240, 214, 160, M.Fabric))
		end)
	end
	-- 상호작용: 서랍 열고 닫기 · 선반 LED 조명 (벽 스위치)
	table.insert(Cx.extraInteract, function()
		local sl = Cx.dressSlide
		if sl and sl.parts[2] and sl.parts[2].Parent then
			local base = {}
			for _, p in sl.parts do
				base[p] = p.CFrame
			end
			local off = Cx.V.cf:VectorToWorldSpace(sl.dir * 0.9)
			Cx:withPrompt(sl.parts[2], function()
				return Interact.toggle(K, sl.parts[2], { object = "서랍", state = false, onText = "닫기", offText = "열기", on = function(st: boolean)
					for p, cf in base do
						if p.Parent then
							tween(p, 0.45, { CFrame = if st then cf + off else cf })
						end
					end
				end })
			end)
		end
	end)
	table.insert(Cx.extraInteract, function()
		local leds = {}
		for _, p in K.parts do
			if p.Name == "HomeClosetShelfLED" and p.Parent then
				table.insert(leds, p)
			end
		end
		if #leds == 0 then
			return
		end
		local light = Cx:light(leds[1], "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 7, Brightness = 0.7, Angle = 120, Color = c3(255, 228, 196) })
		-- 방 프레임 +Z = 이 방 문 쪽: 문 옆 벽에 스위치
		Cx:wallToggle("선반 조명", V3(0, 0, Cx.V.z1), true, "조명 끄기", "조명 켜기", function(st: boolean)
			for _, l in leds do
				if l.Parent then
					l.Material = if st then M.Neon else M.SmoothPlastic
					l.Color = if st then c3(255, 230, 200) else c3(200, 196, 190)
				end
			end
			if light then
				light.Enabled = st
			end
		end, { label = "선반" })
	end)
	-- 거울 프레임 · 캐리어
	for _, m in Cx:ownNamed("ClosetMirror") do
		local d = Cx:wallFace(m.part)
		if d then
			local w, h = math.max(m.size.X, m.size.Z), m.size.Y
			local c = CFrame.fromMatrix(V3(d.Position.X, m.c.Y, d.Position.Z), d.XVector, YA, d.ZVector)
			local glow: BasePart? = nil
			K:free(function()
				-- 뒤에서 비추는 LED 띠 (벽에 번지는 빛) + 얇은 황동 테 + 거울
				glow = K:plate("HomeClosetMirrorGlow", w + 0.34, h + 0.34, 0.02, c, L.neon(c3(255, 236, 214), 0.35))
				K:plate("HomeClosetMirrorFrame", w + 0.2, h + 0.2, 0.05, c * CF(0, 0, 0.02), L.brass)
				K:plate("HomeClosetMirrorGlass", w, h, 0.07, c * CF(0, 0, 0.02), L.mirror)
			end)
			Cx:hide(m.part)
			if glow then
				local gp = glow :: BasePart
				table.insert(Cx.extraInteract, function()
					local mirrorFace = K:box("HomeMirrorTouch", V3(0.3, 0.3, 0.02), c * CF(-w / 2 + 0.3, -h / 2 + 2.2, 0.1), L.neon(c3(255, 255, 255), 0.6))
					Cx:withPrompt(mirrorFace, function()
						return Interact.toggle(K, mirrorFace, { object = "거울 조명", state = true, onText = "끄기", offText = "켜기", on = function(st: boolean)
							gp.Material = if st then M.Neon else M.SmoothPlastic
							gp.Transparency = if st then 0.35 else 0.85
							mirrorFace.Material = if st then M.Neon else M.SmoothPlastic
						end })
					end)
				end)
			end
		end
	end
	-- 캐리어: 끝벽 거울 옆 구석 (거울 앞을 막지 않게)
	for _, m in Cx:ownNamed("ClosetMirror") do
		local half = math.max(m.size.X, m.size.Z) / 2
		Cx:use(V3(m.c.X - half - 0.1, 0, m.c.Z - 0.2) - V3(0, 0, 0), V3(m.c.X + half + 0.1, 7, m.c.Z + 2.2))
	end
	local lug = Cx:floorAlongWall(1.4, 1.0, 2.8, { score = near(Cx:floorCenter() + V3(3, 0, -6)) })
	if lug then
		K:free(function()
			K:rbox("HomeSuitcase", V3(1.3, 2.2, 0.9), 0.15, lug * CF(0, 1.25, 0), lk(120, 140, 160, M.Plastic))
			for i = -1, 1 do
				K:box("HomeSuitcaseRib", V3(0.04, 2.0, 0.92), lug * CF(i * 0.35, 1.25, 0), lk(100, 118, 136, M.Plastic))
			end
			K:box("HomeSuitcaseHandle", V3(0.5, 0.5, 0.06), lug * CF(0, 2.6, -0.35), lk(40, 40, 42, M.Metal))
			for _, sx in { -0.5, 0.5 } do
				K:ball("HomeSuitcaseWheel", 0.18, lug * CF(sx, 0.09, 0.3), lk(30, 30, 32))
				K:ball("HomeSuitcaseWheel", 0.18, lug * CF(sx, 0.09, -0.3), lk(30, 30, 32))
			end
		end)
	end
end

ROOM["apartment:study"] = function(Cx: any)
	local K = Cx.K
	local fc = Cx:floorCenter()
	local db = nil
	for _, m in Cx:propModels("Daybed") do
		db = m
	end
	if db then
		Cx:reskinAs("sofa", db, "daybed_study", "SofaBack")
	end
	local roll, blind = Cx:ownNamed("BlindRoll")[1], Cx:ownNamed("Blind")[1]
	if roll and blind then
		for _, s in Cx:ownNamed("Sill") do
			Cx.sillY = s.max.Y
		end
		Cx:rollBlind(roll, blind)
	end
	-- 프린터 (작은 수납장 위) · 벽 코르크 보드 · 기타 · 스탠드
	local pc = Cx:floorAlongWall(1.6, 1.1, 3.4, { score = near(fc + V3(4, 0, -5)) })
	if pc then
		K:free(function()
			K:box("HomeSideCabinet", V3(1.6, 2.0, 1.1), pc * CF(0, 1.0, 0), lk(240, 238, 234))
			K:box("HomeSideCabinetDoor", V3(1.5, 1.85, 0.03), pc * CF(0, 1.0, 0.56), lk(248, 246, 242))
			K:box("HomeSideCabinetPull", V3(0.4, 0.04, 0.04), pc * CF(0, 1.75, 0.6), lk(70, 70, 74, M.Metal))
			K:rbox("HomePrinter", V3(1.4, 0.55, 1.0), 0.05, pc * CF(0, 2.28, -0.02), lk(246, 246, 244))
			K:box("HomePrinterTray", V3(0.9, 0.04, 0.4), pc * CF(0, 2.4, 0.55), lk(220, 220, 218))
			K:box("HomePrinterPaper", V3(0.8, 0.03, 0.35), pc * CF(0, 2.44, 0.55), L.paper)
			K:box("HomePrinterPanel", V3(0.4, 0.12, 0.02), pc * CF(0.4, 2.48, 0.49), lk(40, 44, 50))
			K:box("HomePrinterLED", V3(0.05, 0.03, 0.01), pc * CF(0.25, 2.48, 0.505), L.neon(c3(80, 220, 120)))
		end)
	end
	local _, _, cb = Cx:wallSpot(2.6, 4.2, 6.4, 0.14, { score = near(fc + V3(0, 0, -6)) })
	if cb then
		K:free(function()
			local f = artFrame(K, cb, 2.4, 1.8, { frame = L.oak, border = 0.08, depth = 0.08, mat = lk(196, 150, 100, M.Fabric) })
			local memo = { c3(255, 236, 120), c3(255, 186, 200), c3(170, 220, 255), c3(250, 250, 246) }
			local t = { "가족여행\n제주 7/20", "피아노\n화 · 목", "관리비\n자동이체", "할 일\n- 세차" }
			for i = 1, 4 do
				local mcf = f * CF(-0.75 + (i - 1) * 0.5, (if i % 2 == 0 then 0.25 else -0.2), 0) * ANG(0, 0, (i - 2.5) * 0.08)
				K:box("HomeMemo", V3(0.45, 0.45, 0.01), mcf * CF(0, 0, 0.005), { c = memo[i], m = M.SmoothPlastic })
				K:text("HomeMemoText", 0.4, 0.32, mcf * CF(0, -0.02, 0.011), t[i], { fg = c3(40, 40, 60), font = Enum.Font.Gotham, d = 0.004, free = true })
				K:ball("HomePushPin", 0.07, mcf * CF(0, 0.18, 0.04), { c = ({ c3(220, 40, 40), c3(40, 120, 220) })[i % 2 + 1], m = M.SmoothPlastic })
			end
			-- 아이 그림
			K:box("HomeKidDrawing", V3(0.7, 0.5, 0.01), f * CF(0.85, 0.3, 0.006) * ANG(0, 0, 0.05), L.paper)
			K:ball("HomeKidSun", 0.16, f * CF(1.0, 0.42, 0.012), lk(250, 200, 40))
			K:box("HomeKidHouse", V3(0.22, 0.18, 0.005), f * CF(0.75, 0.2, 0.012), lk(220, 80, 60))
		end)
	end
	local gs = Cx:floorAlongWall(1.0, 0.9, 4.0, { score = near(fc + V3(5, 0, 3)) })
	if gs then
		K:free(function()
			P.guitar(K, gs)
		end)
	end
	-- 독서 스탠드 (내 불빛)
	local lp = Cx:floorAlongWall(1.0, 1.0, 5.5, { score = near(fc + V3(-5, 0, 0)) })
	if lp then
		K:free(function()
			K:disc("HomeLampBase", 0.85, 0.08, lp * CF(0, 0.04, 0), lk(30, 30, 32, M.Metal))
			K:vcyl("HomeLampPole", 4.6, 0.08, lp * CF(0, 2.38, 0), lk(30, 30, 32, M.Metal))
			local sh = K:vcyl("HomeLampShade", 1.0, 1.15, lp * CF(0, 5.0, 0), { c = c3(244, 236, 220), m = M.Fabric, t = 0.15 })
			local glow = K:vcyl("HomeLampBulb", 0.6, 0.5, lp * CF(0, 5.0, 0), L.lampWarm)
			local l = Cx:light(glow, "PointLight", { Range = 10, Brightness = 0.5, Color = c3(255, 206, 150) })
			Cx.lamps = Cx.lamps or {}
			table.insert(Cx.lamps, { glow = glow, light = l, base = lp.Position })
			local _ = sh
		end)
	end
end

ROOM["apartment:main"] = function(Cx: any)
	-- 베란다 (다용도): 세탁기 + 건조기 · 건조대 · 보일러 · 분리수거 · 화분
	local K = Cx.K
	local w = Cx:ownNamed("Washer")[1]
	local d = Cx:ownNamed("Dryer")[1]
	if w then
		local out = Cx:drumWasher(w, "0:48")
		Cx.washer = out
		K:free(function()
			-- 세탁기 위 세제 · 섬유유연제 (건조기 아래 공간이 없으면 생략)
		end)
	end
	if d then
		Cx:drumWasher(d, "건조 1:10")
	end
	for _, q in Cx:ownNamed("DoorRing", "DoorGlass", "ControlPanel") do
		Cx:hide(q.part)
	end
	local rackParts, mn, mx = {}, V3(math.huge, math.huge, math.huge), V3(-math.huge, -math.huge, -math.huge)
	for _, r in Cx:ownNamed("RackLeg", "RackBar", "Laundry") do
		table.insert(rackParts, r.part)
		mn, mx = mn:Min(r.min), mx:Max(r.max)
	end
	if #rackParts > 0 then
		Cx:dryingRack(mn, mx, rackParts, { c3(240, 240, 236), c3(60, 80, 130), c3(200, 90, 90), c3(230, 220, 170), c3(40, 40, 44) })
	end
	for _, b in Cx:ownNamed("LaundryBasket") do
		K:free(function()
			P.laundryBasket(K, CF(b.c.X, 0, b.c.Z), { c3(240, 240, 236), c3(90, 110, 150) })
		end)
		Cx:hide(b.part)
	end
	-- 화분 (Pot + Trunk/Canopy | Leaves)
	for _, pot in Cx:ownNamed("Pot") do
		local hasTrunk = false
		for _, q in Cx:ownNamed("Trunk") do
			if math.abs(q.c.X - pot.c.X) < 0.6 and math.abs(q.c.Z - pot.c.Z) < 0.6 then
				hasTrunk = true
			end
		end
		K:free(function()
			Props.floorPlant(K, CF(pot.c.X, 0, pot.c.Z), { kind = if hasTrunk then "olive" else "snake", h = if hasTrunk then 4.8 else 2.2, dia = pot.size.X, pot = lk(190, 110, 80, M.SmoothPlastic) })
		end)
		Cx:hide(pot.part)
		for _, q in Cx:ownNamed("Soil", "Trunk", "Canopy", "Leaves") do
			if math.abs(q.c.X - pot.c.X) < 1 and math.abs(q.c.Z - pot.c.Z) < 1 then
				Cx:hide(q.part)
			end
		end
	end
	local _, _, bl = Cx:wallSpot(1.6, 3.6, 6.4, 1.0, { score = near(Cx:floorCenter() + V3(6, 0, 0)) })
	if bl then
		K:free(function()
			P.boiler(K, bl * CF(0, 0.6, 0))
		end)
	end
	local rb = Cx:floorAlongWall(3.0, 1.1, 1.7, { score = near(Cx:floorCenter() + V3(3, 0, 0)) })
	if rb then
		K:free(function()
			P.recycleBins(K, rb)
		end)
	end
	local sl = Cx:floorAt({ CF(Cx:floorCenter().X - 2, 0, Cx:floorCenter().Z + 1.4), CF(Cx:floorCenter().X + 1, 0, Cx:floorCenter().Z + 1.4) }, V3(0.9, 0.2, 1.0), 0)
	if sl then
		K:free(function()
			P.slippers(K, sl, c3(80, 140, 200))
		end)
	end
end

-- 펜트하우스 -------------------------------------------------------------------------------------
-- 그랜드 피아노 (케이스 · 꼬리 · 뚜껑 · 건반 · 보면대 · 다리 · 페달 · 의자)
function C:grandPiano()
	local K = self.K
	local case = self:ownNamed("PianoCase")[1]
	if not case then
		return
	end
	local m = case.part.Parent
	local F, info = propFrame(self, m :: Instance, "KeyBed")
	-- 건반 쪽이 +Z (연주자 쪽)
	local kb = first(info, "KeyBed")
	if kb then
		local ctr = (info.min + info.max) / 2
		if kb.c.Z < ctr.Z then
			F = F * ANG(0, PI, 0)
			info = analyze(self, F, m :: Instance)
			kb = first(info, "KeyBed")
		end
	end
	local cs = first(info, "PianoCase")
	if not (cs and kb) then
		return
	end
	local black = { c = c3(14, 14, 16), m = M.SmoothPlastic, r = 0.12 }
	local w = cs.size.X
	local y0, y1 = cs.min.Y, cs.max.Y
	local zf = kb.max.Z
	local zb = info.min.Z
	local hi = K.detail ~= "low"
	local fold: Model? = nil
	K:free(function()
		-- 케이스: 앞쪽 직사각 + 뒤로 좁아지는 곡선 (조각 6)
		local zs = zf - 0.6
		local n = 6
		local len = zs - zb
		for i = 1, n do
			local t0, t1 = (i - 1) / n, i / n
			local wv = w * (1 - 0.55 * (t0 + t1) / 2 ^ 1.4)
			local xoff = -w * 0.18 * ((t0 + t1) / 2)
			local zc = zs - len * (t0 + t1) / 2
			K:rbox("HomePianoCase", V3(wv, y1 - y0, len / n + 0.02), 0.08, F * CF(xoff - (w - wv) * 0.2, (y0 + y1) / 2, zc), black)
		end
		K:box("HomePianoCaseFront", V3(w, y1 - y0, 0.6), F * CF(0, (y0 + y1) / 2, zf - 0.3 - 0.6), black)
		-- 건반 (흰 52 / 검은 36 대신 덩어리 + 검은 건반 줄)
		K:box("HomePianoKeybed", V3(w - 0.1, 0.12, 0.8), F * CF(0, kb.max.Y - 0.06, zf - 0.4), black)
		K:box("HomePianoWhiteKeys", V3(w - 0.5, 0.06, 0.62), F * CF(0, kb.max.Y + 0.03, zf - 0.36), lk(248, 246, 240))
		if hi then
			local nk = 22
			for i = 1, nk do
				if i % 7 ~= 3 and i % 7 ~= 0 then
					local x = -(w - 0.5) / 2 + (w - 0.5) * (i - 0.5) / nk
					K:box("HomePianoBlackKey", V3((w - 0.5) / nk * 0.55, 0.07, 0.38), F * CF(x, kb.max.Y + 0.09, zf - 0.48), black)
				end
			end
		end
		for _, sx in { -1, 1 } do
			K:box("HomePianoCheek", V3(0.22, 0.4, 0.85), F * CF(sx * (w / 2 - 0.11), kb.max.Y + 0.1, zf - 0.4), black)
		end
		-- 건반 뚜껑 (상호작용: 열기 · 닫기)
		fold = K:group("HomePianoFallboard", function()
			K:box("HomePianoFallboardHandle", V3(w - 0.5, 0.05, 0.3), F * CF(0, kb.max.Y + 0.42, zf - 0.75) * ANG(math.rad(-70), 0, 0), black)
		end)
		-- 보면대 + 악보
		K:box("HomePianoMusicDesk", V3(w * 0.5, 0.7, 0.05), F * CF(0, y1 + 0.32, zf - 1.0) * ANG(math.rad(-15), 0, 0), black)
		K:box("HomePianoSheet", V3(0.9, 0.6, 0.01), F * CF(-0.25, y1 + 0.34, zf - 0.96) * ANG(math.rad(-15), 0, 0), L.paper)
		K:box("HomePianoSheet", V3(0.9, 0.6, 0.01), F * CF(0.55, y1 + 0.34, zf - 0.96) * ANG(math.rad(-15), 0, 0), lk(244, 240, 230))
		-- 뚜껑 (받침대로 열림)
		local lidHinge = F * CF(-w / 2 + 0.05, y1, (zf + zb) / 2 - 0.3)
		K:box("HomePianoLid", V3(w * 0.9, 0.06, (zf - zb) * 0.85), lidHinge * ANG(0, 0, math.rad(-32)) * CF(w * 0.45, 0, 0), black)
		K:seg("HomePianoLidStick", (F * CF(w * 0.3, y1, (zf + zb) / 2 - 0.4)).Position, (lidHinge * ANG(0, 0, math.rad(-32)) * CF(w * 0.78, -0.03, -0.4)).Position, 0.06, black)
		-- 다리 3 + 바퀴 + 페달
		for _, lg in all(info, "PianoLeg") do
			K:box("HomePianoLeg", V3(0.3, y0 - 0.12, 0.3), F * CF(lg.c.X, (y0 - 0.12) / 2 + 0.12, lg.c.Z), black)
			K:box("HomePianoLegCap", V3(0.36, 0.08, 0.36), F * CF(lg.c.X, y0 - 0.04, lg.c.Z), L.brass)
			K:ball("HomePianoCaster", 0.14, F * CF(lg.c.X, 0.07, lg.c.Z), L.brass)
		end
		K:box("HomePianoLyre", V3(0.5, y0 - 0.3, 0.12), F * CF(0, (y0 - 0.3) / 2 + 0.25, zf - 0.9), black)
		for i = -1, 1 do
			K:box("HomePianoPedal", V3(0.08, 0.04, 0.3), F * CF(i * 0.14, 0.24, zf - 0.75), L.brass)
		end
		-- 의자
		local bench = first(info, "PianoBench")
		if bench then
			K:rbox("HomePianoBenchTop", V3(bench.size.X, 0.25, bench.size.Z), 0.08, F * CF(bench.c.X, bench.max.Y - 0.125, bench.c.Z), L.leatherBlack)
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					K:box("HomePianoBenchLeg", V3(0.14, bench.max.Y - 0.25, 0.14), F * CF(bench.c.X + sx * (bench.size.X / 2 - 0.15), (bench.max.Y - 0.25) / 2, bench.c.Z + sz * (bench.size.Z / 2 - 0.15)), black)
				end
			end
		end
	end)
	for _, r in info.all do
		self:hide(r.part)
	end
	if fold then
		local hinge = (self.V.cf * (F * CF(0, kb.max.Y + 0.25, zf - 0.75))).Position
		local axis = (self.V.cf * F).XVector
		self.extraInteract = self.extraInteract or {}
		table.insert(self.extraInteract, function()
			local f = fold :: Model
			local part = f:FindFirstChildWhichIsA("BasePart")
			if part then
				self:withPrompt(part, function()
					return Interact.swing(K, f, hinge, axis, math.rad(-75), { object = "피아노 건반 뚜껑", openText = "뚜껑 열기", closeText = "뚜껑 닫기" })
				end)
			end
		end)
	end
end

-- 벽난로 (돌 테두리 · 유리 · 숯 · 불꽃 깜빡임 · 불빛) + 켜고 끄기
function C:fireplace()
	local K = self.K
	local gl = self:ownNamed("FireplaceGlass")[1]
	local fl = self:ownNamed("FireplaceFlame")[1]
	local hr = self:ownNamed("FireplaceHearth")[1]
	if not gl then
		return
	end
	local dcf = self:wallFace(gl.part)
	if not dcf then
		-- 유리 앞면 (방 쪽)
		local n = V3(0, 0, 1)
		for _, cand in { V3(1, 0, 0), V3(-1, 0, 0), V3(0, 0, 1), V3(0, 0, -1) } do
			if self:mine(gl.c + cand * 1.2) and not self:insideWall(gl.c + cand * 1.2) then
				n = cand
			end
		end
		dcf = faceCF(gl.c - n * (math.min(gl.size.X, gl.size.Z) / 2), n)
	end
	local f = dcf :: CFrame
	local w = math.max(gl.size.X, gl.size.Z)
	local h = gl.size.Y
	local cy = gl.c.Y
	local base = CFrame.fromMatrix(V3(f.Position.X, cy, f.Position.Z), f.XVector, YA, f.ZVector)
	local th = math.min(gl.size.X, gl.size.Z)
	local flames = {}
	local glow: BasePart? = nil
	K:free(function()
		-- 테두리 (검은 금속 프레임) + 안쪽 내화 벽돌 + 숯 + 장작
		K:box("HomeFireFrame", V3(w + 0.3, 0.15, 0.1), base * CF(0, h / 2 + 0.07, th + 0.05), lk(20, 20, 22, M.Metal))
		K:box("HomeFireFrame", V3(w + 0.3, 0.15, 0.1), base * CF(0, -h / 2 - 0.07, th + 0.05), lk(20, 20, 22, M.Metal))
		K:box("HomeFireInner", V3(w - 0.1, h - 0.1, 0.05), base * CF(0, 0, 0.06), lk(30, 26, 24, M.Slate))
		-- 앞 유리: 거의 투명 (불이 또렷이 보이게). Glass 재질 뒤의 Neon 은 빛 번짐이 죽어 보여서 SmoothPlastic 반투명
		K:box("HomeFireGlass", V3(w, h, 0.02), base * CF(0, 0, th + 0.02), { c = c3(210, 214, 220), m = M.SmoothPlastic, t = 0.9, r = 0.06 })
		K:box("HomeFireEmbers", V3(w - 0.4, 0.12, 0.25), base * CF(0, -h / 2 + 0.12, th * 0.5), L.neon(c3(255, 90, 30), 0.15))
		for i = 1, 4 do
			local x = -w / 2 + w * (i - 0.5) / 4
			K:cyl("HomeFireLog", 0.9, 0.18, base * CF(x, -h / 2 + 0.24, th * 0.5) * ANG(0, 0.4 * (i % 2 == 0 and 1 or -1), 0), lk(70, 48, 32, M.Wood))
		end
		-- 불: 이어진 불빛 띠(뒤) + 넓은 뒷불꽃 줄 + 좁고 높은 앞불꽃 줄 (서로 겹쳐서 촛불 줄처럼 안 보이게)
		self.fireBand = { K:box("HomeFireGlowBand", V3(w - 0.5, h * 0.42, 0.02), base * CF(0, -h / 2 + 0.12 + h * 0.21, 0.1), { c = c3(255, 120, 40), m = M.Neon, t = 0.55 }) }
		local n = math.max(6, math.floor((w - 0.6) / 0.55))
		for i = 1, n do
			local x = -w / 2 + 0.3 + (w - 0.6) * (i - 0.5) / n
			local hh = 0.5 + rnd(self.seed, i) * 0.35
			table.insert(flames, K:ell("HomeFireFlame", V3((w - 0.6) / n * 1.7, hh, 0.1), base * CF(x, -h / 2 + 0.2 + hh / 2, th * 0.38), L.neon(c3(255, 140, 45), 0.25)))
		end
		for i = 1, n - 1 do
			local x = -w / 2 + 0.3 + (w - 0.6) * i / n + (rnd(self.seed, i + 60) - 0.5) * 0.15
			local hh = 0.5 + rnd(self.seed, i + 40) * 0.35
			local fw = (w - 0.6) / n * 0.62
			local lean = (rnd(self.seed, i + 80) - 0.5) * 0.25
			-- 앞불꽃: 몸통 + 가늘고 뾰족한 끝 (기울기 조금씩 달리)
			table.insert(flames, K:ell("HomeFireFlame", V3(fw, hh, 0.08), base * CF(x, -h / 2 + 0.22 + hh / 2, th * 0.6) * ANG(0, 0, lean), L.neon(c3(255, 205, 100), 0.1)))
			table.insert(flames, K:ell("HomeFireFlame", V3(fw * 0.42, hh * 0.6, 0.07), base * CF(x - math.sin(lean) * hh * 0.55, -h / 2 + 0.22 + hh * 1.05, th * 0.6) * ANG(0, 0, lean * 1.6), L.neon(c3(255, 225, 140), 0.2)))
		end
		glow = flames[math.floor(n / 2)]
		-- 벽난로 위 선반 (대리석) + 장식 (촛대 · 작은 조각)
		if hr then
			K:box("HomeFireHearth", hr.size + V3(0.02, 0, 0.02), CF(hr.c), L.marbleBlack)
		end
	end)
	local l = self:light(glow, "PointLight", { Range = 12, Brightness = 0.9, Color = c3(255, 150, 70) })
	self:hide(gl.part)
	if fl then
		self:hide(fl.part)
	end
	if hr then
		self:hide(hr.part)
	end
	local on = true
	Interact.anim(K, function(t)
		for i, p in flames do
			if p.Parent then
				local k = 0.85 + 0.15 * math.sin(t * (5 + i % 5) + i * 1.7)
				p.Transparency = if on then 0.1 + (1 - k) * 0.6 else 1
			end
		end
		for _, p in self.fireBand or {} do
			if p.Parent then
				p.Transparency = if on then 0.5 + 0.08 * math.sin(t * 6.1) else 1
			end
		end
		if l then
			l.Brightness = if on then 0.75 + 0.2 * math.sin(t * 7.3) else 0
		end
	end)
	self.extraInteract = self.extraInteract or {}
	table.insert(self.extraInteract, function()
		local sw = nil
		local _, _, d = self:wallSpot(0.5, 3.95, 4.45, 0.12, { score = near(V3(f.Position.X, 0, f.Position.Z)), accept = function(cfm)
			return self:promptOk(cfm.Position)
		end })
		if d then
			K:free(function()
				sw = switchPlate(self, d, 0.5, 1, "HomeFireSwitch")
				K:text("HomeFireSwitchLabel", 0.5, 0.12, d * CF(0, 0.33, 0.01), "벽난로", { fg = c3(160, 150, 140), d = 0.004, free = true })
			end)
		end
		if sw then
			self:withPrompt(sw, function()
				return Interact.toggle(K, sw, { object = "벽난로", state = true, onText = "불 끄기", offText = "불 켜기", on = function(st: boolean)
					on = st
				end })
			end)
		end
	end)
end

ROOM["penthouse:living"] = function(Cx: any)
	local K = Cx.K
	pcall(function()
		Cx:grandPiano()
	end)
	pcall(function()
		Cx:fireplace()
	end)
	local fc = Cx:floorCenter()
	-- 조각상 (받침대 위) · 팜파스 화병 · 사이드 테이블
	local sc = Cx:floorAlongWall(1.4, 1.4, 5.0, { score = near(fc + V3(-6, 0, 8)) })
	if sc then
		K:free(function()
			K:box("HomePlinth", V3(1.3, 3.0, 1.3), sc * CF(0, 1.5, 0), lk(236, 232, 224, M.Marble))
			K:ell("HomeSculpture", V3(0.7, 1.4, 0.5), sc * CF(0, 3.7, 0) * ANG(0, 0.5, 0.15), lk(186, 152, 88, M.Metal, { r = 0.1 }))
			K:ring("HomeSculptureRing", sc * CF(0, 3.9, 0) * ANG(0, 0.9, 0), 0.4, 0.1, 10, lk(186, 152, 88, M.Metal, { r = 0.1 }))
		end)
	end
	local pv = Cx:floorAlongWall(1.3, 1.3, 5.5, { score = near(fc + V3(6, 0, -8)) })
	if pv then
		K:free(function()
			K:vcyl("HomeFloorVase", 2.2, 1.0, pv * CF(0, 1.1, 0), lk(200, 190, 176, M.Concrete))
			K:ell("HomeFloorVaseShoulder", V3(1.0, 0.5, 1.0), pv * CF(0, 2.2, 0), lk(200, 190, 176, M.Concrete))
			for i = 0, 8 do
				local a = i * 0.7
				local tip = pv * V3(math.cos(a) * 0.7, 4.6 + (i % 3) * 0.4, math.sin(a) * 0.6)
				K:seg("HomePampasStem", pv * V3(0, 2.3, 0), tip, 0.03, lk(196, 176, 140))
				K:ell("HomePampas", V3(0.35, 0.9, 0.35), CF(tip) * ANG(math.cos(a) * 0.3, 0, math.sin(a) * 0.3), lk(232, 220, 196, M.Fabric))
			end
		end)
	end
end

ROOM["penthouse:dining"] = function(Cx: any)
	local K = Cx.K
	local fc = Cx:floorCenter()
	-- 홈바: 바 앞판 루버 · 상판 테두리 · 뒷장 문 · 바 스툴 · 도구
	local body = Cx:ownNamed("BarBody")[1]
	local top = Cx:ownNamed("BarTop")[1]
	if body then
		local F, info = propFrame(Cx, body.part)
		local _ = info
		K:free(function()
			local d = Cx:wallFace(body.part)
			local _ = d
			-- 손님 쪽 (방 가운데 쪽) 면에 세로 루버
			local c = body.c
			local alongZ = body.size.Z >= body.size.X
			local len = if alongZ then body.size.Z else body.size.X
			local side = if alongZ then (if fc.X > c.X then 1 else -1) else (if fc.Z > c.Z then 1 else -1)
			local n = math.floor(len / 0.3)
			for i = 1, n do
				local t = -len / 2 + len * (i - 0.5) / n
				local p = if alongZ then V3(c.X + side * (body.size.X / 2 + 0.03), c.Y - 0.1, c.Z + t) else V3(c.X + t, c.Y - 0.1, c.Z + side * (body.size.Z / 2 + 0.03))
				K:vcyl("HomeBarFlute", body.size.Y - 0.5, 0.22, CF(p), lk(110, 76, 52, M.Wood))
			end
			local kp = if alongZ then V3(c.X + side * (body.size.X / 2 - 0.1), 0.18, c.Z) else V3(c.X, 0.18, c.Z + side * (body.size.Z / 2 - 0.1))
			K:box("HomeBarKick", if alongZ then V3(0.1, 0.36, len) else V3(len, 0.36, 0.1), CF(kp), lk(20, 20, 22))
			K:box("HomeBarFootRail", if alongZ then V3(0.1, 0.1, len - 0.4) else V3(len - 0.4, 0.1, 0.1), CF(kp + (if alongZ then V3(side * 0.45, 0.45, 0) else V3(0, 0.45, side * 0.45))), L.brass)
			local _ = F
		end)
	end
	if top then
		K:free(function()
			K:box("HomeBarTopEdge", V3(top.size.X + 0.04, 0.05, top.size.Z + 0.04), CF(top.c.X, top.min.Y - 0.02, top.c.Z), L.brass)
		end)
	end
	-- 바 스툴 (Seat 기둥형) 리스킨
	for _, s in Cx:ownNamed("Seat") do
		if s.part.Parent and s.part.Parent.Name == "Bar" then
			K:free(function()
				Props.stool(K, CF(s.c.X, 0, s.c.Z), { seatTop = s.max.Y, dia = 1.35, style = "bar", frame = L.brass, seat = L.leatherBlack })
				-- 등받이
				local back = nil
				for _, b in Cx:ownNamed("StoolBack") do
					if math.abs(b.c.Z - s.c.Z) < 0.5 and math.abs(b.c.X - s.c.X) < 1 then
						back = b
					end
				end
				if back then
					K:rbox("HomeBarStoolBack", V3(back.size.X, back.size.Y, back.size.Z), 0.06, CF(back.c) * ANG(0, if back.size.X > back.size.Z then 0 else PI / 2, 0), L.leatherBlack)
					K:seg("HomeBarStoolBackPost", V3(back.c.X, s.max.Y - 0.1, back.c.Z), V3(back.c.X, back.min.Y + 0.1, back.c.Z), 0.06, L.brass)
					Cx:hide(back.part)
				end
			end)
			Cx:hide(s.part)
			for _, q in Cx:ownNamed("StoolFoot", "StoolPost", "FootRing") do
				if math.abs(q.c.Z - s.c.Z) < 0.4 and math.abs(q.c.X - s.c.X) < 0.4 then
					Cx:hide(q.part)
				end
			end
		end
	end
	-- 뒷장 위: 셰이커 · 지거 · 아이스 버킷 · 잔 트레이
	local bb = Cx:ownNamed("BackBarTop")[1]
	if bb then
		local y = bb.max.Y
		local alongZ = bb.size.Z >= bb.size.X
		local function at(t: number, off: number): CFrame
			return if alongZ then CF(bb.c.X + off, y, bb.c.Z + t) else CF(bb.c.X + t, y, bb.c.Z + off)
		end
		K:free(function()
			K:vcyl("HomeIceBucket", 0.6, 0.6, at(-3.5, 0.1) * CF(0, 0.3, 0), L.chrome)
			for i = 0, 3 do
				K:box("HomeIceCube", V3(0.14, 0.14, 0.14), at(-3.5, 0.1) * CF(-0.12 + i * 0.08, 0.62, (i % 2) * 0.08) * ANG(i, i * 0.5, 0), L.glass(c3(230, 240, 246), 0.4))
			end
			K:vcyl("HomeShaker", 0.6, 0.24, at(-2.6, 0.2) * CF(0, 0.3, 0), L.chrome)
			K:vcyl("HomeShakerCap", 0.16, 0.18, at(-2.6, 0.2) * CF(0, 0.68, 0), L.chrome)
			K:vcyl("HomeJigger", 0.25, 0.12, at(-2.2, 0.25) * CF(0, 0.125, 0), L.brass)
			K:box("HomeBarTray", V3(1.4, 0.04, 0.9), at(2.8, 0.1) * CF(0, 0.02, 0), L.brass)
			for i = 0, 5 do
				local gx, gz = (i % 3 - 1) * 0.38, (i // 3 - 0.5) * 0.38
				K:vcyl("HomeGlassFoot", 0.02, 0.18, at(2.8 + gx, 0.1 + gz) * CF(0, 0.05, 0), L.glass(c3(230, 240, 246), 0.5))
				K:vcyl("HomeGlassStem", 0.3, 0.03, at(2.8 + gx, 0.1 + gz) * CF(0, 0.2, 0), L.glass(c3(230, 240, 246), 0.5))
				K:ell("HomeGlassBowl", V3(0.22, 0.3, 0.22), at(2.8 + gx, 0.1 + gz) * CF(0, 0.48, 0), L.glass(c3(230, 240, 246), 0.6))
			end
			-- 허리케인 캔들 2 (유리 갓 + 필라 캔들, 불꽃은 꺼진 채로 시작)
			Cx.candleFlames = Cx.candleFlames or {}
			for j, off in { -1.15, -0.65 } do
				local cc = at(off, 0.05 + (j - 1) * 0.12)
				K:disc("HomeCandleBase", 0.42, 0.04, cc * CF(0, 0.02, 0), L.brass)
				K:vcyl("HomeCandlePillar", 0.35 + j * 0.1, 0.24, cc * CF(0, 0.04 + (0.35 + j * 0.1) / 2, 0), lk(250, 246, 236))
				K:vcyl("HomeHurricaneGlass", 0.8 + j * 0.1, 0.4, cc * CF(0, 0.04 + (0.8 + j * 0.1) / 2, 0), L.glass(c3(236, 240, 244), 0.75))
				local fl = K:ell("HomeCandleFlame", V3(0.07, 0.15, 0.07), cc * CF(0, 0.04 + 0.35 + j * 0.1 + 0.1, 0), { c = c3(255, 190, 90), m = M.Neon, t = 1 })
				table.insert(Cx.candleFlames, fl)
			end
			K:box("HomeBarBoard", V3(0.9, 0.05, 0.5), at(0.6, 0.15) * CF(0, 0.025, 0), lk(150, 110, 70, M.Wood))
			K:ball("HomeLemon", 0.2, at(0.4, 0.15) * CF(0, 0.15, 0), lk(250, 220, 60))
			K:ball("HomeLime", 0.18, at(0.75, 0.2) * CF(0, 0.14, 0), lk(120, 190, 60))
		end)
	end
	-- 백바 병 진열: 상자 병을 실제 병 모양으로 (와인 · 위스키 · 진 · 리큐르) + 백라이트 오닉스 패널 + 선반 앞 LED
	local bottles = Cx:ownNamed("Bottle")
	local bback = Cx:ownNamed("BottleBack")[1]
	local barGlow: { BasePart } = {}
	if #bottles > 0 then
		local kinds = {
			{ body = c3(40, 70, 46), t = 0.15, h = 0.62, d = 0.26, neck = 0.3, cap = c3(120, 30, 40) }, -- 레드 와인
			{ body = c3(176, 110, 40), t = 0.2, h = 0.5, d = 0.3, neck = 0.16, cap = c3(30, 26, 22), square = true }, -- 위스키
			{ body = c3(214, 230, 232), t = 0.45, h = 0.6, d = 0.27, neck = 0.18, cap = c3(200, 200, 204) }, -- 진 · 보드카
			{ body = c3(120, 40, 30), t = 0.2, h = 0.45, d = 0.3, neck = 0.2, cap = c3(196, 164, 98) }, -- 코냑
			{ body = c3(210, 190, 120), t = 0.3, h = 0.66, d = 0.25, neck = 0.32, cap = c3(196, 164, 98) }, -- 화이트 와인
		}
		K:free(function()
			for i, b in bottles do
				local k = kinds[(i * 7 + Cx.seed) % #kinds + 1]
				local y0 = b.min.Y
				local p = CF(b.c.X, y0, b.c.Z)
				local look = { c = k.body, m = M.Glass, t = k.t, r = 0.15 }
				if k.square then
					K:box("HomeBottleBody", V3(k.d, k.h, k.d), p * CF(0, k.h / 2, 0), look)
				else
					K:vcyl("HomeBottleBody", k.h, k.d, p * CF(0, k.h / 2, 0), look)
					K:ball("HomeBottleShoulder", k.d, p * CF(0, k.h, 0), look)
				end
				K:vcyl("HomeBottleNeck", k.neck, 0.1, p * CF(0, k.h + k.d * 0.35 + k.neck / 2, 0), look)
				K:vcyl("HomeBottleCap", 0.1, 0.12, p * CF(0, k.h + k.d * 0.35 + k.neck + 0.04, 0), { c = k.cap, m = M.SmoothPlastic })
				if i % 2 == 0 then
					-- 라벨 (방 쪽 면)
					local toRoom = if bback and bback.c.X < b.c.X then 1 else -1
					K:box("HomeBottleLabel", V3(0.005, k.h * 0.4, k.d * 0.7), p * CF(toRoom * (k.d / 2 + 0.004), k.h * 0.45, 0), lk(236, 226, 200))
				end
				Cx:hide(b.part)
			end
			if bback then
				-- 백라이트 오닉스 패널 (병 뒤 벽면): 방 쪽 면에 얇게
				local toRoom = if bback.c.X < fc.X then 1 else -1
				local fx = if toRoom > 0 then bback.max.X else bback.min.X
				local panel = K:box("HomeBarOnyx", V3(0.03, bback.size.Y - 0.3, bback.size.Z - 0.3), CF(fx + toRoom * 0.016, bback.c.Y, bback.c.Z), { c = c3(255, 196, 120), m = M.Neon, t = 0.55 })
				table.insert(barGlow, panel)
				-- 오닉스 결 (빛이 비치는 돌 무늬): 비스듬한 얇은 띠 몇 줄
				for v = 1, 6 do
					local zz = bback.c.Z - bback.size.Z / 2 + 0.6 + (bback.size.Z - 1.2) * (v - 0.5) / 6
					local yy = bback.c.Y + (rnd(Cx.seed, v) - 0.5) * (bback.size.Y - 1.0)
					local vein = K:box("HomeOnyxVein", V3(0.006, 0.05 + rnd(Cx.seed, v + 10) * 0.05, 1.6 + rnd(Cx.seed, v + 20) * 1.6), CF(fx + toRoom * 0.034, yy, zz) * ANG(0.35 + rnd(Cx.seed, v + 30) * 0.5, 0, 0), { c = c3(196, 110, 50), m = M.SmoothPlastic, t = 0.45 })
					local _ = vein
				end
				for _, sh in Cx:ownNamed("BottleShelf") do
					local sf = if toRoom > 0 then sh.max.X else sh.min.X
					table.insert(barGlow, K:box("HomeBarShelfLip", V3(0.04, 0.04, sh.size.Z - 0.1), CF(sf + toRoom * 0.02, sh.max.Y - 0.02, sh.c.Z), L.neon(c3(255, 210, 160), 0.1)))
				end
			end
		end)
	end
	-- 촛불 켜기 · 끄기 (사이드보드 촛대)
	table.insert(Cx.extraInteract, function()
		local fl = Cx.candleFlames
		if not fl or not fl[1] or not fl[1].Parent then
			return
		end
		local light = nil
		local tgt = fl[1]
		local flick = false
		Interact.anim(K, function(t)
			if not flick then
				return
			end
			for i, f in fl do
				if f.Parent then
					f.Size = V3(0.07, 0.14 + 0.03 * math.sin(t * 9 + i * 2), 0.07)
				end
			end
			if light then
				light.Brightness = 0.55 + 0.1 * math.sin(t * 11)
			end
		end)
		Cx:withPrompt(tgt, function()
			return Interact.toggle(K, tgt, { object = "촛불", state = false, onText = "끄기", offText = "켜기", on = function(st: boolean)
				flick = st
				for _, f in fl do
					if f.Parent then
						f.Transparency = if st then 0 else 1
					end
				end
				if st and not light then
					light = Cx:light(tgt, "PointLight", { Range = 8, Brightness = 0.6, Color = c3(255, 180, 100) })
				end
				if light then
					light.Enabled = st
				end
			end })
		end)
	end)
	if #barGlow > 0 then
		table.insert(Cx.extraInteract, function()
			local light = Cx:light(barGlow[1], "SurfaceLight", { Face = Enum.NormalId.Front, Range = 9, Brightness = 0.6, Angle = 110, Color = c3(255, 196, 130) })
			local orig = {}
			for _, g in barGlow do
				orig[g] = { g.Color, g.Transparency }
			end
			local bt = Cx:ownNamed("BarTop")[1]
			local at = if bt then V3(bt.c.X, 0, bt.c.Z - bt.size.Z / 2) else fc
			Cx:wallToggle("바 조명", at, true, "바 조명 끄기", "바 조명 켜기", function(st: boolean)
				for g, o in orig do
					if g.Parent then
						g.Material = if st then M.Neon else M.SmoothPlastic
						g.Color = if st then o[1] else c3(70, 60, 50)
						g.Transparency = if st then o[2] else 0
					end
				end
				if light then
					light.Enabled = st
				end
			end, { label = "BAR" })
		end)
	end
	-- 사이드보드 (벽) + 장식
	local sb = Cx:floorAlongWall(6.0, 1.5, 3.0, { score = near(fc + V3(0, 0, 6)) })
	if sb then
		K:free(function()
			K:box("HomeSideboard", V3(6.0, 2.4, 1.5), sb * CF(0, 1.5, 0), L.walnut)
			for i = 1, 4 do
				K:box("HomeSideboardDoor", V3(1.45, 2.2, 0.03), sb * CF(-2.25 + (i - 1) * 1.5, 1.5, 0.76), tint(L.walnut, -0.05))
				K:box("HomeSideboardPull", V3(0.04, 0.6, 0.04), sb * CF(-2.25 + (i - 1) * 1.5 + (if i % 2 == 0 then -0.6 else 0.6), 1.6, 0.8), L.brass)
			end
			for _, sx in { -2.8, 2.8 } do
				K:box("HomeSideboardLeg", V3(0.14, 0.3, 0.14), sb * CF(sx, 0.15, 0.55), L.brass)
				K:box("HomeSideboardLeg", V3(0.14, 0.3, 0.14), sb * CF(sx, 0.15, -0.55), L.brass)
			end
			K:box("HomeSideboardTop", V3(6.1, 0.08, 1.55), sb * CF(0, 2.74, 0), L.marbleBlack)
			-- 위: 화병 · 촛대 · 볼
			K:vcyl("HomeSBVase", 1.0, 0.45, sb * CF(-2.1, 3.28, 0), lk(236, 232, 224, M.Marble))
			for j = 0, 4 do
				K:seg("HomeSBBranch", sb * V3(-2.1, 3.7, 0), sb * V3(-2.1 + (j - 2) * 0.3, 4.9 + (j % 2) * 0.3, (j % 3 - 1) * 0.2), 0.03, lk(110, 90, 70))
			end
			Cx.candleFlames = {}
			for j = 0, 1 do
				K:vcyl("HomeCandleStick", 0.8, 0.12, sb * CF(1.2 + j * 0.5, 3.18, 0), L.brass)
				K:vcyl("HomeCandleTaper", 0.6, 0.08, sb * CF(1.2 + j * 0.5, 3.88, 0), lk(250, 248, 240))
				K:seg("HomeCandleWick", sb * V3(1.2 + j * 0.5, 4.18, 0), sb * V3(1.2 + j * 0.5, 4.24, 0), 0.015, lk(30, 30, 30))
				local fl = K:ell("HomeCandleFlame", V3(0.07, 0.16, 0.07), sb * CF(1.2 + j * 0.5, 4.3, 0), { c = c3(255, 190, 90), m = M.Neon, t = 1 })
				table.insert(Cx.candleFlames, fl)
			end
			K:ell("HomeSBBowl", V3(1.0, 0.35, 1.0), sb * CF(2.4, 2.95, 0), lk(30, 30, 32, M.SmoothPlastic, { r = 0.1 }))
		end)
	end
	-- 빈 벽 (바 옆 · 현관 쪽): 대형 캔버스 2 폭 + 픽처 라이트 (다이닝 갤러리 월)
	local placed = 0
	for _, aw in { 4.4, 4.4, 2.6, 2.0 } do
		if placed >= 2 then
			break
		end
		local _, _, art = Cx:wallSpotHigh(aw, 3.6, 7.6, 0.2, { score = near(fc + V3(0, 0, 6)), margin = 0.4 })
		if not art then
			continue
		end
		placed += 1
		local i = placed
		local cw = aw - 0.6
		K:free(function()
			local f = artFrame(K, art * CF(0, 0.1, 0), cw, 3.6, { gallery = true, depth = 0.14, edge = lk(30, 30, 32) })
			artPaint(K, f, cw, 3.6, "abstract", Cx.seed + 31 + i * 7, if i == 1 then { c3(226, 218, 204), c3(34, 46, 70), c3(176, 132, 82) } else { c3(214, 206, 192), c3(120, 52, 40), c3(40, 40, 42) })
			K:box("HomePictureLightBar", V3(cw * 0.5, 0.1, 0.1), art * CF(0, 2.15, 0.34), L.brass)
			K:seg("HomePictureLightArm", (art * CF(0, 2.0, 0.02)).Position, (art * CF(0, 2.1, 0.3)).Position, 0.05, L.brass)
			K:box("HomePictureLightGlow", V3(cw * 0.45, 0.02, 0.06), art * CF(0, 2.09, 0.34), L.neon(c3(255, 226, 180), 0.2))
		end)
	end
end

ROOM["penthouse:study"] = function(Cx: any)
	local K = Cx.K
	local fc = Cx:floorCenter()
	-- 라운지 체어 (스터디)
	local seat = nil
	for _, s in Cx:ownNamed("Seat") do
		if s.part.Parent and s.part.Parent.Name == "Study" then
			seat = s
		end
	end
	if seat then
		local shell = nil
		for _, q in Cx:ownNamed("LoungeShell") do
			shell = q
		end
		local face = V3(0, 0, 1)
		if shell then
			local d = V3(seat.c.X - shell.c.X, 0, seat.c.Z - shell.c.Z)
			if d.Magnitude > 0.05 then
				face = d.Unit
			end
		end
		local c = V3(seat.c.X, 0, seat.c.Z)
		K:free(function()
			loungeChair(Cx, CFrame.lookAt(c, c - face), seat.max.Y, { shell = L.walnut, cushion = lk(52, 36, 28, M.Leather) })
		end)
		Cx:hide(seat.part)
		for _, q in Cx:ownNamed("LoungeShell", "LoungeBase", "LoungeStem", "LoungeCushion") do
			Cx:hide(q.part)
		end
	end
	for _, r in Cx:ownNamed("StudyRug") do
		Cx:plainRug(r, "rug_study_wool")
	end
	-- 크레덴자 (문 사이 벽) + 지구본 + 상패 · 시가 상자 · 위: 세계지도
	local CW = 4.3
	local cr = Cx:floorAlongWall(CW, 1.4, 3.0, { score = near(fc + V3(-2.1, 0, 9)) })
	if cr then
		local globe: { BasePart } = {}
		K:free(function()
			K:box("HomeCredenza", V3(CW, 2.3, 1.4), cr * CF(0, 1.45, 0), L.walnut)
			K:box("HomeCredenzaTop", V3(CW + 0.1, 0.08, 1.45), cr * CF(0, 2.64, 0), L.leatherBrown)
			local dw = (CW - 0.12) / 3
			for i = 1, 3 do
				local x = -CW / 2 + 0.06 + dw * (i - 0.5)
				K:box("HomeCredenzaDoor", V3(dw - 0.04, 2.1, 0.03), cr * CF(x, 1.45, 0.71), tint(L.walnut, -0.06))
				-- 가로 플루팅 (문짝 홈)
				for k = 1, 5 do
					K:box("HomeCredenzaFlute", V3(dw - 0.2, 0.025, 0.01), cr * CF(x, 0.55 + k * 0.32, 0.728), tint(L.walnut, -0.18))
				end
				K:box("HomeCredenzaPull", V3(0.5, 0.04, 0.04), cr * CF(x, 2.3, 0.74), L.brass)
			end
			for _, sx in { -CW / 2 + 0.2, CW / 2 - 0.2 } do
				K:box("HomeCredenzaLeg", V3(0.14, 0.3, 0.14), cr * CF(sx, 0.15, 0.5), L.brass)
				K:box("HomeCredenzaLeg", V3(0.14, 0.3, 0.14), cr * CF(sx, 0.15, -0.5), L.brass)
			end
			-- 지구본 (돌아감)
			local gx = -CW / 2 + 0.6
			K:disc("HomeGlobeBase", 0.5, 0.08, cr * CF(gx, 2.72, 0), L.brass)
			K:vcyl("HomeGlobeStem", 0.25, 0.06, cr * CF(gx, 2.88, 0), L.brass)
			table.insert(globe, K:ball("HomeGlobe", 0.8, cr * CF(gx, 3.4, 0), lk(70, 120, 150)))
			table.insert(globe, K:ell("HomeGlobeLand", V3(0.42, 0.36, 0.2), cr * CF(gx + 0.05, 3.48, 0.31), lk(200, 180, 120)))
			table.insert(globe, K:ell("HomeGlobeLand", V3(0.2, 0.3, 0.42), cr * CF(gx - 0.3, 3.3, -0.06), lk(200, 180, 120)))
			table.insert(globe, K:ell("HomeGlobeLand", V3(0.3, 0.2, 0.36), cr * CF(gx + 0.12, 3.6, -0.24), lk(200, 180, 120)))
			K:ring("HomeGlobeMeridian", cr * CF(gx, 3.4, 0) * ANG(0, 0.4, 0.4), 0.46, 0.04, 12, L.brass)
			-- 상패 · 시가 상자 · 디캔터 트레이 · 책
			K:box("HomePlaque", V3(0.6, 0.8, 0.08), cr * CF(0.35, 3.08, -0.3) * ANG(math.rad(-10), 0, 0), L.walnut)
			K:box("HomePlaqueMetal", V3(0.44, 0.52, 0.01), cr * CF(0.35, 3.08, -0.255) * ANG(math.rad(-10), 0, 0), L.goldMetal)
			K:box("HomeHumidor", V3(0.8, 0.32, 0.55), cr * CF(-0.5, 2.84, 0.1), lk(90, 50, 30, M.Wood))
			K:box("HomeHumidorHygro", V3(0.16, 0.16, 0.01), cr * CF(-0.5, 2.84, 0.38), L.brass)
			local tr = cr * CF(1.35, 2.68, 0)
			K:box("HomeDecanterTray", V3(1.0, 0.04, 0.6), tr * CF(0, 0.02, 0), L.brass)
			K:vcyl("HomeDecanter", 0.5, 0.36, tr * CF(-0.2, 0.29, 0), L.glass(c3(200, 130, 60), 0.25))
			K:vcyl("HomeDecanterNeck", 0.2, 0.12, tr * CF(-0.2, 0.64, 0), L.glass(c3(230, 236, 236), 0.5))
			K:ball("HomeDecanterStopper", 0.16, tr * CF(-0.2, 0.8, 0), L.glass(c3(230, 236, 236), 0.4))
			for k = 0, 1 do
				K:vcyl("HomeRocksGlass", 0.22, 0.2, tr * CF(0.2 + k * 0.22, 0.15, (k - 0.5) * 0.24), L.glass(c3(230, 236, 236), 0.5))
			end
			bookStack(K, cr * CF(-1.35, 2.68, 0.05) * ANG(0, 0.2, 0), 3, Cx.seed + 5)
		end)
		-- 지구본 돌리기 (이 클라이언트)
		table.insert(Cx.extraInteract, function()
			if not globe[1] or not globe[1].Parent then
				return
			end
			local center = globe[1].Position
			local base = {}
			for _, g in globe do
				base[g] = g.CFrame
			end
			local spin = 0
			local spinning = false
			Interact.anim(K, function(_t, dt)
				if spin <= 0 then
					return
				end
				spin = math.max(0, spin - dt)
				local a = (6 - spin) * 1.6
				local rot = CFrame.new(center) * CFrame.Angles(0, a, 0) * CFrame.new(-center)
				for g, c in base do
					if g.Parent then
						g.CFrame = rot * c
					end
				end
				spinning = spin > 0
			end)
			Cx:withPrompt(globe[1], function()
				return Interact.prompt(K, globe[1], { action = "돌리기", object = "지구본", fn = function()
					if not spinning then
						spin = 6
						spinning = true
					end
				end })
			end)
		end)
	end
	-- 크레덴자 위 벽: 세계지도 액자 (부산 핀)
	local _, _, mp = Cx:wallSpot(4.0, 4.0, 7.2, 0.12, { score = near(fc + V3(-2.1, 0, 9)) })
	if mp then
		K:free(function()
			local f = artFrame(K, mp, 3.8, 2.5, { frame = L.walnut, border = 0.1, mat = lk(236, 226, 200) })
			K:box("HomeMapSea", V3(3.3, 1.95, 0.006), f * CF(0, 0, 0.003), lk(170, 196, 200))
			local land = { { -1.0, 0.25, 0.8, 0.75 }, { -0.75, -0.5, 0.42, 0.66 }, { 0.25, 0.33, 1.15, 0.66 }, { 0.5, -0.33, 0.42, 0.5 }, { 1.15, -0.58, 0.42, 0.3 } }
			for _, l in land do
				K:ell("HomeMapLand", V3(l[3], l[4], 0.006), f * CF(l[1], l[2], 0.008), lk(214, 196, 150))
			end
			K:ball("HomeMapPin", 0.08, f * CF(0.87, 0.32, 0.03), L.ledRed)
			K:text("HomeMapTitle", 1.6, 0.16, f * CF(0, 1.08, 0.012), "MAPPA MUNDI · 2026", { fg = c3(90, 70, 50), d = 0.004, free = true, font = Enum.Font.Garamond })
		end)
	end
	-- 다른 문 사이 벽: 위스키 진열장 (유리문 + 내부 LED + 병 · 잔)
	local wc = Cx:floorAlongWall(3.0, 1.3, 6.2, { score = near(fc + V3(6.4, 0, 9)) })
	if wc then
		local leds: { BasePart } = {}
		K:free(function()
			local W, H, D = 3.0, 6.0, 1.3
			K:box("HomeCabinetBack", V3(W, H, 0.06), wc * CF(0, H / 2, -D / 2 + 0.03), lk(52, 36, 26, M.Wood))
			for _, sx in { -W / 2 + 0.04, W / 2 - 0.04 } do
				K:box("HomeCabinetSide", V3(0.08, H, D), wc * CF(sx, H / 2, 0), L.walnut)
			end
			K:box("HomeCabinetTop", V3(W, 0.1, D), wc * CF(0, H - 0.05, 0), L.walnut)
			K:box("HomeCabinetPlinth", V3(W, 0.5, D), wc * CF(0, 0.25, 0), L.walnut)
			local bcols = { c3(160, 90, 30), c3(120, 60, 20), c3(200, 150, 70), c3(90, 50, 24), c3(170, 120, 50) }
			for k = 1, 3 do
				local sy = 0.5 + k * 1.35
				K:box("HomeCabinetShelf", V3(W - 0.16, 0.05, D - 0.1), wc * CF(0, sy, -0.02), L.glass(c3(220, 230, 230), 0.3))
				table.insert(leds, K:box("HomeCabinetLED", V3(W - 0.2, 0.02, 0.04), wc * CF(0, sy + 1.28, D / 2 - 0.14), L.neon(c3(255, 210, 150), 0.1)))
				for j = 0, 3 do
					local bx = -1.05 + j * 0.7
					if k == 2 and j >= 2 then
						-- 가운데 칸: 크리스털 잔
						K:vcyl("HomeCrystalGlass", 0.3, 0.24, wc * CF(bx, sy + 0.18, 0.05), L.glass(c3(236, 240, 244), 0.45))
					else
						local col = bcols[(j + k) % #bcols + 1]
						local hb = 0.85 + ((j * 7 + k) % 3) * 0.08
						K:box("HomeWhisky", V3(0.3, hb, 0.3), wc * CF(bx, sy + 0.025 + hb / 2, -0.1), L.glass(col, 0.15))
						K:vcyl("HomeWhiskyNeck", 0.22, 0.12, wc * CF(bx, sy + hb + 0.13, -0.1), L.glass(col, 0.2))
						K:vcyl("HomeWhiskyCork", 0.1, 0.14, wc * CF(bx, sy + hb + 0.29, -0.1), lk(60, 40, 26, M.Wood))
						K:box("HomeWhiskyLabel", V3(0.24, 0.3, 0.005), wc * CF(bx, sy + 0.025 + hb * 0.45, 0.053), lk(236, 226, 196))
					end
				end
			end
			-- 유리 문 2짝 + 손잡이
			for _, sx in { -W / 4, W / 4 } do
				K:box("HomeCabinetGlassDoor", V3(W / 2 - 0.08, H - 0.7, 0.03), wc * CF(sx, 0.5 + (H - 0.6) / 2, D / 2 - 0.02), L.glass(c3(210, 220, 220), 0.7))
				K:box("HomeCabinetDoorFrame", V3(W / 2 - 0.08, 0.06, 0.04), wc * CF(sx, H - 0.14, D / 2 - 0.02), L.brass)
				K:box("HomeCabinetDoorFrame", V3(W / 2 - 0.08, 0.06, 0.04), wc * CF(sx, 0.56, D / 2 - 0.02), L.brass)
				K:box("HomeCabinetHandle", V3(0.04, 0.9, 0.05), wc * CF(sx + (if sx < 0 then W / 4 - 0.14 else -W / 4 + 0.14), 3.2, D / 2 + 0.02), L.brass)
			end
		end)
		table.insert(Cx.extraInteract, function()
			local tgt = leds[1]
			if not tgt or not tgt.Parent then
				return
			end
			local light = Cx:light(leds[2] or tgt, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 6, Brightness = 0.9, Angle = 120, Color = c3(255, 210, 150) })
			Cx:withPrompt(tgt, function()
				return Interact.toggle(K, tgt, { object = "위스키 진열장 조명", state = true, onText = "끄기", offText = "켜기", on = function(st: boolean)
					for _, l in leds do
						if l.Parent then
							l.Material = if st then M.Neon else M.SmoothPlastic
							l.Color = if st then c3(255, 210, 150) else c3(90, 86, 80)
						end
					end
					if light then
						light.Enabled = st
					end
				end })
			end)
		end)
	end
	-- 슬레이트 피처월 (서재 쪽 면): 대형 작품 + 픽처 라이트 + 황동 리빌 라인 2
	local fw = Cx:ownNamed("FeatureWall")[1]
	if fw then
		local d = Cx:wallFace(fw.part)
		if d then
			-- wallFace 는 얇은 판의 뒷면(벽 쪽)을 줌 → 두께만큼 앞으로 (이 방 쪽 면)
			local th = math.min(fw.size.X, fw.size.Z)
			local fp = d.Position + d.ZVector * th
			local fwc = CFrame.fromMatrix(V3(fp.X, 0, fp.Z), d.XVector, YA, d.ZVector)
			local wlen = math.max(fw.size.X, fw.size.Z)
			K:free(function()
				local f = artFrame(K, fwc * CF(0, 4.6, 0), 4.6, 3.0, { frame = L.goldMetal, border = 0.04, mat = lk(244, 240, 232) })
				artPaint(K, f, 4.1, 2.6, "abstract", Cx.seed + 23, { c3(214, 200, 176), c3(150, 60, 40), c3(30, 30, 32) })
				K:box("HomePictureLightBar", V3(2.0, 0.1, 0.1), fwc * CF(0, 6.3, 0.34), L.brass)
				K:seg("HomePictureLightArm", (fwc * CF(0, 6.25, 0.02)).Position, (fwc * CF(0, 6.3, 0.3)).Position, 0.05, L.brass)
				K:box("HomePictureLightGlow", V3(1.8, 0.02, 0.06), fwc * CF(0, 6.24, 0.34), L.neon(c3(255, 226, 180), 0.2))
				for _, sx in { -1, 1 } do
					K:box("HomeFeatureReveal", V3(0.05, math.min(fw.size.Y, Cx.H) - 0.3, 0.012), fwc * CF(sx * (wlen / 2 - 0.9), (math.min(fw.size.Y, Cx.H) - 0.3) / 2 + 0.15, 0.006), L.brass)
				end
			end)
		end
	end
	-- 라운지 체어 옆: 사이드 테이블 + 독서 플로어 램프 (내 불빛)
	if seat then
		local c = V3(seat.c.X, 0, seat.c.Z)
		for _, off in { V3(1.2, 0, 2.7), V3(-0.4, 0, 2.7), V3(2.5, 0, 1.6), V3(1.2, 0, -2.5), V3(2.5, 0, -1.6), V3(-0.4, 0, -2.5) } do
			local st = CF(c + off)
			if Cx:mine(st.Position + V3(0, 0.5, 0)) and Cx:floorSpot(st * CF(0, 0.08, 0), V3(1.7, 5.4, 1.7), 0) then
				K:free(function()
					K:disc("HomeSideTableTop", 1.1, 0.08, st * CF(0, 1.9, 0), lk(236, 232, 224, M.Marble))
					K:vcyl("HomeSideTableStem", 1.85, 0.1, st * CF(0, 0.95, 0), L.brass)
					K:disc("HomeSideTableFoot", 0.8, 0.06, st * CF(0, 0.03, 0), L.brass)
					bookStack(K, st * CF(-0.15, 1.94, 0.05) * ANG(0, 0.4, 0), 2, Cx.seed + 9)
					K:vcyl("HomeRocksGlass", 0.22, 0.2, st * CF(0.3, 2.05, -0.2), L.glass(c3(230, 236, 236), 0.5))
					K:vcyl("HomeWhiskyPour", 0.08, 0.17, st * CF(0.3, 1.99, -0.2), L.glass(c3(200, 130, 60), 0.2))
					-- 플로어 램프: 테이블 뒤 기둥 + 갓
					local lp = st * CF(0.47, 0, -0.47)
					K:disc("HomeLampBase", 0.5, 0.05, lp * CF(0, 0.025, 0), L.brass)
					K:vcyl("HomeLampPole", 4.3, 0.07, lp * CF(0, 2.2, 0), L.brass)
					local sh = K:vcyl("HomeLampShade", 0.9, 1.0, lp * CF(0, 4.75, 0), { c = c3(240, 230, 210), m = M.Fabric, t = 0.15 })
					local glow = K:vcyl("HomeLampBulb", 0.5, 0.45, lp * CF(0, 4.75, 0), L.lampWarm)
					local l = Cx:light(glow, "PointLight", { Range = 10, Brightness = 0.55, Color = c3(255, 206, 150) })
					Cx.lamps = Cx.lamps or {}
					table.insert(Cx.lamps, { glow = glow, light = l, base = st.Position })
					local _ = sh
				end)
				break
			end
		end
	end
end

ROOM["penthouse:bedroom"] = function(Cx: any)
	local K = Cx.K
	-- 침대 벤치
	for _, b in Cx:ownNamed("BedBench") do
		K:free(function()
			local top = b.max.Y
			K:rbox("HomeBenchCushion", V3(b.size.X, 0.4, b.size.Z), 0.15, CF(b.c.X, top - 0.2, b.c.Z) * ANG(0, if b.size.X >= b.size.Z then 0 else PI / 2, 0), { c = b.part.Color, m = M.Fabric })
			K:box("HomeBenchBase", V3(b.size.X - 0.1, 0.12, b.size.Z - 0.1), CF(b.c.X, top - 0.46, b.c.Z), L.brass)
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					K:box("HomeBenchLeg", V3(0.1, top - 0.52, 0.1), CF(b.c.X + sx * (b.size.X / 2 - 0.15), b.min.Y + (top - 0.52) / 2, b.c.Z + sz * (b.size.Z / 2 - 0.15)), L.brass)
				end
			end
			-- 벤치 위 담요 + 트레이
			K:box("HomeBenchThrow", V3(1.2, 0.08, b.size.Z + 0.1), CF(b.c.X - b.size.X * 0.25, top + 0.04, b.c.Z), lk(196, 182, 160, M.Fabric))
		end)
		Cx:hide(b.part)
	end
	-- 서랍장 (월넛) + 유리 상판 + 위 소품
	for _, d in Cx:ownNamed("ClosetDrawers") do
		local F, info = propFrame(Cx, d.part)
		K:free(function()
			local x0, x1, y1, z0, z1 = info.min.X, info.max.X, info.max.Y, info.min.Z, info.max.Z
			boxF(K, "HomeDresserBody", F, V3(x0, 0.2, z0), V3(x1, y1, z1 - 0.03), L.walnut)
			for i = 1, 4 do
				for j = 1, 2 do
					local xc = x0 + (x1 - x0) * (j - 0.5) / 2
					local yc = 0.25 + (y1 - 0.3) * (i - 0.5) / 4
					K:box("HomeDresserDrawer", V3((x1 - x0) / 2 - 0.06, (y1 - 0.3) / 4 - 0.05, 0.03), F * CF(xc, yc, z1 - 0.01), tint(L.walnut, -0.05))
					K:box("HomeDresserPull", V3(0.5, 0.04, 0.04), F * CF(xc, yc, z1 + 0.02), L.brass)
				end
			end
		end)
		Cx:hide(d.part)
	end
	for _, t in Cx:ownNamed("ClosetDrawersTop") do
		local y = t.max.Y
		K:free(function()
			K:box("HomeDresserGlass", t.size, CF(t.c), { c = c3(30, 30, 32), m = M.Glass, r = 0.2 })
			-- 시계함 · 향수 · 꽃
			K:box("HomeWatchBox", V3(0.9, 0.3, 0.6), CF(t.c.X - 1.5, y + 0.15, t.c.Z), lk(40, 30, 26, M.Leather))
			K:box("HomeWatchBoxGlass", V3(0.8, 0.02, 0.5), CF(t.c.X - 1.5, y + 0.31, t.c.Z), L.glass(c3(220, 230, 236), 0.5))
			K:vcyl("HomePerfume", 0.35, 0.24, CF(t.c.X - 0.5, y + 0.17, t.c.Z + 0.1), L.glass(c3(230, 200, 150), 0.25))
			K:box("HomePerfumeCap", V3(0.16, 0.14, 0.16), CF(t.c.X - 0.5, y + 0.41, t.c.Z + 0.1), L.goldMetal)
			K:vcyl("HomeFlowerVase", 0.7, 0.36, CF(t.c.X + 1.4, y + 0.35, t.c.Z), L.glass(c3(220, 236, 240), 0.5))
			for i = 0, 4 do
				local a = i * 1.26
				K:seg("HomeFlowerStem", V3(t.c.X + 1.4, y + 0.6, t.c.Z), V3(t.c.X + 1.4 + math.cos(a) * 0.25, y + 1.3, t.c.Z + math.sin(a) * 0.2), 0.03, lk(80, 120, 70))
				K:ball("HomeFlower", 0.22, CF(t.c.X + 1.4 + math.cos(a) * 0.25, y + 1.33, t.c.Z + math.sin(a) * 0.2), lk(250, 250, 246))
			end
		end)
		Cx:hide(t.part)
	end
	-- 라운지 체어
	for _, s in Cx:ownNamed("Seat") do
		if s.part.Parent and s.part.Parent.Name == "MasterSuite" then
			local shell = nil
			for _, q in Cx:ownNamed("LoungeShell") do
				if (q.c - s.c).Magnitude < 2.5 then
					shell = q
				end
			end
			local face = V3(0, 0, 1)
			if shell then
				local d = V3(s.c.X - shell.c.X, 0, s.c.Z - shell.c.Z)
				if d.Magnitude > 0.05 then
					face = d.Unit
				end
			end
			local c = V3(s.c.X, 0, s.c.Z)
			K:free(function()
				loungeChair(Cx, CFrame.lookAt(c, c - face), s.max.Y, { shell = L.walnut, cushion = lk(236, 230, 218, M.Fabric) })
			end)
			Cx:hide(s.part)
			for _, q in Cx:ownNamed("LoungeShell", "LoungeBase", "LoungeStem", "LoungeCushion") do
				if (q.c - s.c).Magnitude < 2.5 then
					Cx:hide(q.part)
				end
			end
		end
	end
	-- 사이드 테이블 (황동 원통) · 러그 · 옷걸이
	for _, st in Cx:ownNamed("SideTable") do
		K:free(function()
			local top = st.max.Y
			K:disc("HomeSideTableTop", math.max(st.size.X, st.size.Z), 0.08, CF(st.c.X, top - 0.04, st.c.Z), L.marbleWhite)
			K:vcyl("HomeSideTableDrum", top - 0.1, math.max(st.size.X, st.size.Z) * 0.85, CF(st.c.X, (top - 0.1) / 2 + st.min.Y, st.c.Z), L.brass)
			K:vcyl("HomeTeaCup", 0.2, 0.25, CF(st.c.X + 0.2, top + 0.1, st.c.Z), L.white)
		end)
		Cx:hide(st.part)
	end
	for _, r in Cx:ownNamed("Rug") do
		if r.part.Parent and r.part.Parent.Name == "MasterSuite" then
			Cx:plainRug(r, "rug_master")
		end
	end
	local rail = Cx:ownNamed("HangerRail")[1]
	if rail then
		Cx:clothesRail(rail, Cx:ownNamed("Clothes"))
	end
	-- 욕조 (프리스탠딩): 둥근 벽 + 물 + 황동 수전 (서버 반신욕 프롬프트는 그대로)
	local tf = Cx:ownNamed("TubFloor")[1]
	if tf then
		local walls = Cx:ownNamed("TubWall")
		local mn, mx = tf.min, tf.max
		for _, w in walls do
			mn, mx = mn:Min(w.min), mx:Max(w.max)
		end
		local c = (mn + mx) / 2
		local alongX = (mx.X - mn.X) >= (mx.Z - mn.Z)
		local len, wid = if alongX then mx.X - mn.X else mx.Z - mn.Z, if alongX then mx.Z - mn.Z else mx.X - mn.X
		local F = CF(c.X, mn.Y, c.Z) * (if alongX then CFrame.new() else ANG(0, PI / 2, 0))
		local h = mx.Y - mn.Y
		K:free(function()
			K:rbox("HomeTubShell", V3(len, h - 0.1, wid), wid * 0.45, F * CF(0, (h - 0.1) / 2 + 0.1, 0) * ANG(0, PI / 2, 0) * ANG(0, -PI / 2, 0), lk(250, 250, 248))
			K:slab("HomeTubRim", len, wid, 0.08, wid * 0.48, F * CF(0, h - 0.02, 0), lk(252, 252, 250))
			K:slab("HomeTubWater", len - 0.5, wid - 0.5, 0.04, wid * 0.4, F * CF(0, h - 0.25, 0), { c = c3(150, 200, 214), m = M.Glass, t = 0.35, r = 0.1 })
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					K:ball("HomeTubFoot", 0.22, F * CF(sx * (len / 2 - 0.5), 0.11, sz * (wid / 2 - 0.4)), L.brass)
				end
			end
			-- 욕조 트레이 (책 · 와인잔 · 초)
			K:box("HomeTubTray", V3(0.4, 0.06, wid + 0.3), F * CF(len * 0.15, h + 0.05, 0), lk(150, 120, 90, M.Wood))
			K:vcyl("HomeTubCandle", 0.2, 0.2, F * CF(len * 0.15, h + 0.18, -wid * 0.3), lk(248, 244, 234))
			K:vcyl("HomeTubGlassStem", 0.25, 0.03, F * CF(len * 0.15, h + 0.2, wid * 0.25), L.glass(c3(230, 240, 246), 0.5))
			K:ell("HomeTubGlassBowl", V3(0.2, 0.26, 0.2), F * CF(len * 0.15, h + 0.42, wid * 0.25), { c = c3(120, 30, 40), m = M.Glass, t = 0.3 })
		end)
		Cx:hide(tf.part)
		for _, w in walls do
			Cx:hide(w.part)
		end
		for _, q in Cx:ownNamed("Water") do
			if (q.c - c).Magnitude < 3 then
				Cx:hide(q.part)
			end
		end
	end
	local fc = Cx:floorCenter()
	-- 침대 위 벽: 큰 추상화 (크림 · 골드 · 차콜) + 픽처 라이트
	local brec = slotRecOf(Cx, "bed")
	if brec then
		local headW = brec.F * CF((brec.info.min.X + brec.info.max.X) / 2, 0, brec.info.min.Z - 0.6)
		local _, _, art = Cx:wallSpotHigh(5.6, 4.7, 7.9, 0.16, { score = near(headW.Position) })
		if art then
			K:free(function()
				local f = artFrame(K, art, 5.2, 2.8, { frame = L.goldMetal, border = 0.05, mat = lk(246, 242, 234) })
				artPaint(K, f, 4.6, 2.3, "abstract", Cx.seed + 11, { c3(236, 228, 214), c3(196, 164, 98), c3(52, 50, 48) })
				K:box("HomePictureLightBar", V3(2.2, 0.1, 0.1), art * CF(0, 1.62, 0.32), L.brass)
				K:seg("HomePictureLightArm", (art * CF(0, 1.55, 0.02)).Position, (art * CF(0, 1.6, 0.3)).Position, 0.05, L.brass)
				K:box("HomePictureLightGlow", V3(2.0, 0.02, 0.06), art * CF(0, 1.56, 0.32), L.neon(c3(255, 226, 180), 0.2))
			end)
		end
		-- 침대 아래 간접등 (프레임 밑 LED 띠: 바닥에 번지는 빛) + 벽 스위치. 침대가 바뀌면 rebuildSlot 이 다시 부름
		local F, info = brec.F, brec.info
		local strips: { BasePart } = {}
		local glowOn = false
		local function buildGlow()
			table.clear(strips)
			local rec = slotRecOf(Cx, "bed")
			if not rec then
				return
			end
			local F2, info2 = rec.F, rec.info
			Cx.bedGlowGroup = K:group("HomeBedGlowGroup", function()
				K:free(function()
					-- 프레임 바로 바깥 바닥 띠 (프레임 밑에서 새어 나온 빛처럼): 러그 위로 올라오게 0.065~0.085
					local x0, x1, z0, z1 = info2.min.X - 0.05, info2.max.X + 0.05, (info2.min.Z + info2.max.Z) / 2 - 1.0, info2.max.Z + 0.05
					table.insert(strips, K:box("HomeBedGlow", V3(0.07, 0.02, z1 - z0), F2 * CF(x0, 0.075, (z0 + z1) / 2), L.neon(c3(255, 206, 150), 0.3)))
					table.insert(strips, K:box("HomeBedGlow", V3(0.07, 0.02, z1 - z0), F2 * CF(x1, 0.075, (z0 + z1) / 2), L.neon(c3(255, 206, 150), 0.3)))
					table.insert(strips, K:box("HomeBedGlow", V3(x1 - x0, 0.02, 0.07), F2 * CF((x0 + x1) / 2, 0.075, z1), L.neon(c3(255, 206, 150), 0.3)))
				end)
			end)
			for _, g in strips do
				g.Material = if glowOn then M.Neon else M.SmoothPlastic
				g.Color = if glowOn then c3(255, 206, 150) else c3(60, 56, 52)
			end
		end
		buildGlow()
		Cx.bedGlowRebuild = buildGlow
		table.insert(Cx.extraInteract, function()
			if not strips[1] or not strips[1].Parent then
				return
			end
			local side = F * V3(info.max.X + 1.4, 0, info.min.Z + 0.6)
			Cx:wallToggle("침대 간접등", side, false, "간접등 끄기", "간접등 켜기", function(st: boolean)
				glowOn = st
				for _, g in strips do
					if g.Parent then
						g.Material = if st then M.Neon else M.SmoothPlastic
						g.Color = if st then c3(255, 206, 150) else c3(60, 56, 52)
					end
				end
			end, { label = "무드" })
		end)
	end
end

ROOM["penthouse:main"] = function(Cx: any)
	-- 와인룸 + 파우더룸
	local K = Cx.K
	local bb = Cx:ownNamed("BottleBack")[1]
	if bb then
		local d = Cx:wallFace(bb.part)
		local _, _, td = Cx:wallSpot(1.0, 4.4, 5.2, 0.12, { score = near(bb.c) })
		if td then
			K:free(function()
				K:box("HomeWineDisplay", V3(0.9, 0.55, 0.06), td * CF(0, 0, 0.03), lk(24, 24, 26))
				K:text("HomeWineTemp", 0.8, 0.45, td * CF(0, 0, 0.065), "14℃\n습도 65%", { fg = c3(120, 200, 255), glow = 1.2, d = 0.004, free = true, font = Enum.Font.Code })
			end)
		end
		local _ = d
	end
	-- 와인잔 걸이 (선반 아래)
	local shelves = Cx:ownNamed("BottleShelf")
	if #shelves > 0 then
		local top = shelves[1]
		for _, s in shelves do
			if s.max.Y > top.max.Y then
				top = s
			end
		end
		local _ = top
	end
	-- 파우더룸: 수건 링 · 비누 디스펜서 · 디퓨저 · 휴지 걸이
	local vt = Cx:ownNamed("VanityTop")[1]
	if vt then
		local y = vt.max.Y
		K:free(function()
			K:vcyl("HomeSoapDispenser", 0.45, 0.2, CF(vt.c.X, y + 0.225, vt.c.Z - vt.size.Z * 0.3), lk(40, 36, 32))
			K:vcyl("HomeSoapPump", 0.12, 0.07, CF(vt.c.X, y + 0.5, vt.c.Z - vt.size.Z * 0.3), L.brass)
			K:vcyl("HomePowderDiffuser", 0.4, 0.26, CF(vt.c.X, y + 0.2, vt.c.Z + vt.size.Z * 0.3), L.glass(c3(60, 40, 30), 0.3))
			for i = 0, 3 do
				K:seg("HomeDiffuserReed", V3(vt.c.X, y + 0.35, vt.c.Z + vt.size.Z * 0.3), V3(vt.c.X + math.cos(i * 1.6) * 0.18, y + 1.0, vt.c.Z + vt.size.Z * 0.3 + math.sin(i * 1.6) * 0.15), 0.02, L.darkWood)
			end
			K:box("HomeHandTowel", V3(0.6, 0.06, 0.4), CF(vt.c.X - 0.1, y + 0.03, vt.c.Z + vt.size.Z * 0.05), lk(236, 230, 220, M.Fabric))
		end)
	end
	local tank = Cx:ownNamed("ToiletTank")[1]
	if tank then
		local _, _, tp = Cx:wallSpot(0.5, 2.4, 3.0, 0.4, { score = near(tank.c) })
		if tp then
			K:free(function()
				K:box("HomeTPHolderPlate", V3(0.16, 0.16, 0.05), tp * CF(-0.2, 0, 0.025), L.brass)
				K:cyl("HomeTPHolderBar", 0.5, 0.05, tp * CF(0.05, 0, 0.18), L.brass)
				K:cyl("HomeTPRoll", 0.4, 0.4, tp * CF(0.1, -0.1, 0.2), lk(252, 252, 250))
			end)
		end
	end
end

function C:roomDress()
	self:commonReskins()
	local fn = ROOM[self.tier .. ":" .. self.room] or ROOM[self.room]
	if fn then
		fn(self)
	end
end

-------------------------------------------------------------------------------------------------
-- 상호작용 (이 클라이언트 전용, R 키) — 서버 집 행동(잠 · 앉기 · TV · 냉장고 · 옷장 · 샤워 · 창밖)과 겹치지 않는 것
-------------------------------------------------------------------------------------------------

-- 벽 스위치 + 토글 (스위치 판을 벽 빈 자리에 새로 달고 프롬프트)
function C:wallToggle(object: string, near_: Vector3, state: boolean, onText: string, offText: string, on: (boolean) -> (), opts: any?): ProximityPrompt?
	local o: any = opts or {}
	local K = self.K
	local _, _, dcf = self:wallSpot(o.w or 0.4, 3.95, 4.45, 0.12, {
		score = near(near_),
		accept = function(cfm: CFrame)
			return self:promptOk(cfm.Position)
		end,
	})
	if not dcf then
		return nil
	end
	local plate: BasePart? = nil
	K:free(function()
		plate = switchPlate(self, dcf, o.w or 0.4, 1, "HomeSwitchPlate")
		if o.label then
			K:text("HomeSwitchLabel", 0.5, 0.12, dcf * CF(0, 0.33, 0.01), o.label, { fg = c3(90, 90, 96), d = 0.004, free = true, font = Enum.Font.GothamMedium })
		end
	end)
	return self:withPrompt(plate, function()
		return Interact.toggle(K, plate :: BasePart, { object = object, state = state, onText = onText, offText = offText, on = on })
	end)
end

function C:interactions()
	local K = self.K
	local fc = self:floorCenter()
	-- 1) 커튼 (전동 / 수동): 열기 · 닫기
	for i, cur in self.curtains or {} do
		if i > 1 then
			break
		end
		local at = (cur.at :: CFrame).Position
		self:wallToggle(if self.lux >= 3 then "전동 커튼" else "커튼", at, true, "커튼 닫기", "커튼 열기", function(open: boolean)
			for _, p in cur.open do
				if p.Parent then
					tween(p, 0.9, { Transparency = if open then (cur.t[p] or 0) else 1 })
				end
			end
			for _, p in cur.closed do
				if p.Parent then
					tween(p, 0.9, { Transparency = if open then 1 else (cur.t[p] or 0) })
				end
			end
		end, { label = if self.lux >= 3 then "커튼" else nil })
	end
	-- 2) 스탠드 조명 (방에 더 재미있는 상호작용이 많으면 생략: noLampToggle)
	for _, lamp in (if self.noLampToggle then {} else self.lamps or {}) do
		local g: BasePart = lamp.glow
		if g and g.Parent then
			local col = g.Color
			-- 갓 근처에 서버 프롬프트가 있으면 전선 중간 발 스위치에
			local target: BasePart = g
			if not self:promptOk(self.V.cf:PointToObjectSpace(g.Position)) and lamp.base then
				local bp: Vector3 = lamp.base
				for k = 0, 7 do
					local a = k * PI / 4
					local q = bp + V3(math.cos(a) * 1.5, 0, math.sin(a) * 1.5)
					local smn, smx = V3(q.X - 0.2, 0, q.Z - 0.2), V3(q.X + 0.2, 0.12, q.Z + 0.2)
					if self:promptOk(V3(q.X, 0.06, q.Z)) and self:mine(V3(q.X, 0.5, q.Z)) and not self:insideWall(V3(q.X, 0.5, q.Z)) and self:boxFree(smn, smx, { noKeep = true }) then
						self:use(smn, smx)
						local sw: BasePart? = nil
						K:free(function()
							K:seg("HomeLampCord", V3(bp.X, 0.03, bp.Z), V3(q.X, 0.03, q.Z), 0.035, lk(30, 30, 32))
							sw = K:rbox("HomeFootSwitch", V3(0.3, 0.1, 0.22), 0.04, CF(q.X, 0.05, q.Z) * ANG(0, a, 0), lk(30, 30, 32))[1]
						end)
						if sw then
							target = sw
						end
						break
					end
				end
			end
			self:withPrompt(target, function()
				return Interact.toggle(K, target, { object = lamp.name or "스탠드", state = true, onText = "끄기", offText = "켜기", on = function(st: boolean)
					g.Material = if st then M.Neon else M.SmoothPlastic
					g.Color = if st then col else col:Lerp(c3(140, 136, 128), 0.6)
					if lamp.light then
						lamp.light.Enabled = st
					end
				end })
			end)
		end
	end
	-- 3) 롤 블라인드 (고시원 · 서재)
	if self.blind then
		local b = self.blind
		local cloth: BasePart, bar: BasePart = b.parts.cloth, b.parts.bar
		local function set(len: number)
			if cloth and cloth.Parent then
				tween(cloth, 1.0, { Size = V3(cloth.Size.X, len, cloth.Size.Z), CFrame = self.V.cf * (b.face * CF(0, -0.16 - len / 2, -0.06)) })
			end
			if bar and bar.Parent then
				tween(bar, 1.0, { CFrame = self.V.cf * (b.face * CF(0, -0.16 - len, -0.06)) })
			end
		end
		local target = b.parts.chain
		local pr = self:withPrompt(target, function()
			return Interact.cycle(K, target, { "up", "down", "part" }, { action = "블라인드 올리기/내리기", object = "롤 블라인드", on = function(_i, st)
				set(if st == "up" then 0.35 elseif st == "down" then b.full else b.down)
			end })
		end)
		if not pr then
			self:wallToggle("롤 블라인드", (b.face :: CFrame).Position, true, "블라인드 내리기", "블라인드 올리기", function(up: boolean)
				set(if up then b.down else b.full)
			end)
		end
	end
	-- 4) 선풍기 (날개 회전)
	if self.fan then
		local f = self.fan
		local spinning = false
		local base = {}
		for _, p in f.blades do
			base[p] = p.CFrame
		end
		local ang = 0
		Interact.anim(K, function(_t, dt)
			if not spinning then
				return
			end
			ang += dt * 18
			local rot = CFrame.new(f.center) * CFrame.fromAxisAngle(f.axis, ang) * CFrame.new(-f.center)
			for p, cf in base do
				if p.Parent then
					p.CFrame = rot * cf
				end
			end
		end)
		local tgt = f.blades[#f.blades]
		local pr = self:withPrompt(tgt, function()
			return Interact.toggle(K, tgt, { object = "선풍기", state = false, onText = "끄기", offText = "켜기", on = function(st: boolean)
				spinning = st
			end })
		end)
		if not pr then
			self.fanSpin = function(st: boolean)
				spinning = st
			end
		end
	end
	-- 4-1) 책상 아래 멀티탭: 모니터 · 선풍기 전원
	if self.powerStrip and (self.fanSpin or self.monitorScreen) then
		local scr: BasePart? = self.monitorScreen
		local lab: TextLabel? = self.monitorText
		local scrC = if scr then scr.Color else nil
		self:withPrompt(self.powerStrip, function()
			return Interact.toggle(K, self.powerStrip, { object = "멀티탭 (모니터 · 선풍기)", state = true, onText = "전원 끄기", offText = "전원 켜기", on = function(st: boolean)
				if self.fanSpin then
					self.fanSpin(st)
				end
				if scr and scr.Parent then
					scr.Color = if st then (scrC :: Color3) else c3(8, 8, 10)
				end
				if lab and lab.Parent then
					local g = lab.Parent :: any
					if g and g:IsA("SurfaceGui") then
						g.Enabled = st
					end
				end
			end })
		end)
		if self.fanSpin then
			self.fanSpin(true)
		end
	end
	-- 5) 공기청정기 모드 (색 · 글자)
	if self.purifier and self.purifier.led then
		local pu = self.purifier
		local modes = { { "좋음", c3(60, 140, 255) }, { "보통", c3(60, 210, 120) }, { "나쁨", c3(255, 170, 40) }, { "수면", c3(120, 90, 200) } }
		self:withPrompt(pu.led, function()
			return Interact.cycle(K, pu.led, modes, { action = "모드 바꾸기", object = "공기청정기", on = function(_i, m)
				pu.led.Color = m[2]
				if pu.label then
					pu.label.Text = m[1]
					pu.label.TextColor3 = m[2]
				end
			end })
		end)
	end
	-- 6) 에어컨 (날개 열고 닫기 + LED)
	if self.acVanes and #self.acVanes > 0 then
		local vanes = self.acVanes
		local base = {}
		for _, v in vanes do
			base[v] = v.CFrame
		end
		local led = self.acLED
		local function apply(st: boolean)
			for v, cf in base do
				if v.Parent then
					tween(v, 0.8, { CFrame = cf * ANG(if st then math.rad(-35) else 0, 0, 0) })
				end
			end
			if led and led.Parent then
				led.Color = if st then c3(80, 200, 255) else c3(60, 60, 60)
				led.Material = if st then M.Neon else M.SmoothPlastic
			end
		end
		local at = if self.acAt then self.acAt else (vanes[1].Position and self.V.cf:PointToObjectSpace(vanes[1].Position)) or fc
		self:wallToggle("에어컨", at, false, "에어컨 끄기", "에어컨 켜기", apply, { label = "냉방" })
	end
	-- 7) 로봇청소기 (청소 시작: 바닥을 한 바퀴 돌고 도크로)
	if self.robot then
		local rb = self.robot
		local base = {}
		for _, p in rb.parts do
			base[p] = p.CFrame
		end
		local running = false
		local t0 = 0
		local path = rb.path or {}
		Interact.anim(K, function(t)
			if not running or #path < 2 then
				return
			end
			local u = math.max(0, (t - t0) / 26)
			if u >= 1 then
				running = false
				for p, cf in base do
					if p.Parent then
						p.CFrame = cf
					end
				end
				if rb.dockLed and rb.dockLed.Parent then
					rb.dockLed.Color = c3(90, 220, 180)
				end
				return
			end
			local seg = u * (#path - 1)
			local i = math.floor(seg) + 1
			local f = seg - math.floor(seg)
			local a, b = path[i], path[math.min(#path, i + 1)]
			local pos = a:Lerp(b, f)
			local dir = (b - a)
			local look = if dir.Magnitude > 0.01 then dir.Unit else V3(0, 0, 1)
			local home: CFrame = rb.home
			local off = self.V.cf * CFrame.lookAt(pos, pos + look) * home:Inverse() * self.V.cf:Inverse()
			for p, cf in base do
				if p.Parent then
					p.CFrame = off * cf
				end
			end
		end)
		local btn = rb.parts[#rb.parts]
		self:withPrompt(btn, function()
			return Interact.prompt(K, btn, { action = "청소 시작", object = "로봇청소기", fn = function()
				if running then
					return
				end
				running = true
				t0 = os.clock()
				if rb.dockLed and rb.dockLed.Parent then
					rb.dockLed.Color = c3(255, 170, 40)
				end
			end })
		end)
	end
	-- 8) 방 전용 (벽난로 등)
	for _, f in self.extraInteract or {} do
		pcall(f)
	end
end

-- 집 방의 keep 바로잡기 (이 방 빌드에서만):
--   1) Homes.post 는 슬롯 자리를 늘 이 방 바닥(0.05)부터 세움 → 복층 위 침대 · 아래층 주방 슬롯이 이 방 바닥에
--      기둥처럼 박혀 소품 자리를 막음. 슬롯 상자가 이 방 천장 위 / 바닥 아래에 있으면 그 keep 은 뺌.
--   2) Scan.keepouts 의 "window" 띠 (가게 앞 유리 안쪽) 는 집에선 +Z = 방문 쪽이라 맞지 않음 → 뺌 (문 keep 은 그대로).
function C:fixKeeps()
	local V = self.V
	local boxes = {}
	for _, slot in self.slots do
		local ok, cf, sz = pcall(function()
			return (slot :: Model):GetBoundingBox()
		end)
		if ok and cf then
			local fp = slot:GetAttribute("Footprint")
			local size = if typeof(fp) == "Vector3" then (fp :: Vector3):Max(sz) else sz
			local mn, mx = laabb(V.cf:ToObjectSpace(cf), size + V3(0.4, 0.2, 0.4))
			-- 슬롯이 놓인 바닥 높이 = 받침(SlotBase) 높이 (없으면 상자 바닥)
			local base = slot:FindFirstChild("SlotBase") or (slot :: Model).PrimaryPart
			local bp = if base and base:IsA("BasePart") then V.cf:PointToObjectSpace(base.Position) else (mn + mx) / 2
			table.insert(boxes, { mn = mn, mx = mx, by = bp.Y, bp = bp })
		end
	end
	local out = {}
	local dropped = 0
	for _, k in V.keep do
		local drop = false
		if k.kind == "slot" then
			for _, b in boxes do
				if math.abs(b.mn.X - k.min.X) < 0.02 and math.abs(b.mx.X - k.max.X) < 0.02 and math.abs(b.mn.Z - k.min.Z) < 0.02 and math.abs(b.mx.Z - k.max.Z) < 0.02 then
					if b.by > self.H - 1.0 or b.by < -1.0 or b.mn.Y > self.H - 0.3 or b.mx.Y < -0.3 then
						drop = true
					else
						-- 벽 너머 슬롯 (옆방 가구 · 복도 그림): 이 방 쪽으로 벽을 뚫고 나온 부분을 벽면에서 자름
						local kmn, kmx = k.min, k.max
						for _, w in self.walls do
							if w.mx.Y - w.mn.Y < 2.5 or w.mn.Y > 1.0 then
								continue
							end
							local thinX = (w.mx.X - w.mn.X) <= (w.mx.Z - w.mn.Z)
							if thinX then
								if w.mn.Z <= kmn.Z + 0.3 and w.mx.Z >= kmx.Z - 0.3 or (math.min(w.mx.Z, kmx.Z) - math.max(w.mn.Z, kmn.Z)) > 0.6 * (kmx.Z - kmn.Z) then
									if b.bp.X <= w.mn.X and kmx.X > w.mn.X then
										kmx = V3(w.mn.X, kmx.Y, kmx.Z)
									elseif b.bp.X >= w.mx.X and kmn.X < w.mx.X then
										kmn = V3(w.mx.X, kmn.Y, kmn.Z)
									end
								end
							else
								if w.mn.X <= kmn.X + 0.3 and w.mx.X >= kmx.X - 0.3 or (math.min(w.mx.X, kmx.X) - math.max(w.mn.X, kmn.X)) > 0.6 * (kmx.X - kmn.X) then
									if b.bp.Z <= w.mn.Z and kmx.Z > w.mn.Z then
										kmx = V3(kmx.X, kmx.Y, w.mn.Z)
									elseif b.bp.Z >= w.mx.Z and kmn.Z < w.mx.Z then
										kmn = V3(kmn.X, kmn.Y, w.mx.Z)
									end
								end
							end
						end
						if kmn ~= k.min or kmx ~= k.max then
							if kmx.X - kmn.X < 0.05 or kmx.Z - kmn.Z < 0.05 then
								drop = true
							else
								k = { min = kmn, max = kmx, kind = k.kind }
								dropped += 1
							end
						end
					end
					break
				end
			end
		elseif k.kind == "window" and not HomeWet.rooms[V.room] then
			drop = true
		end
		if drop then
			dropped += 1
		else
			table.insert(out, k)
		end
	end
	if dropped > 0 then
		V.keep = out
	end
end

-------------------------------------------------------------------------------------------------
-- 각방 온도조절기 (한국 집 필수: 스위치 옆 보일러 · 각방 난방 조절기) + 남은 빈 벽 액자
-------------------------------------------------------------------------------------------------
-- 이 방에서 K 가 이미 만든 파트들의 로컬 AABB (벽 장식 겹침 검사용, 트림 제외)
function C:builtBoxes(y0: number, y1: number): { any }
	local out = {}
	local inv = self.V.cf:Inverse()
	for _, p in self.K.parts or {} do
		if p.Parent and p.Transparency < 0.95 then
			local n = p.Name
			if string.sub(n, 1, 12) ~= "HomeBaseboar" and string.sub(n, 1, 9) ~= "HomeCrown" and n ~= "HomeShadowGap" then
				local mn, mx = laabb(inv * p.CFrame, p.Size)
				if mx.Y > y0 and mn.Y < y1 then
					table.insert(out, { mn = mn, mx = mx })
				end
			end
		end
	end
	return out
end

local function hitsAny(list: { any }, mn: Vector3, mx: Vector3): boolean
	for _, b in list do
		if boxHit(mn, mx, b.mn, b.mx, 0.01) then
			return true
		end
	end
	return false
end

function C:thermostat()
	local K = self.K
	if self.lux < 2 or HomeWet.rooms[self.room] or self.room == "dress" then
		return
	end
	local built = self:builtBoxes(3.6, 5.0)
	local W, Hh = 0.5, 0.62
	if self.lux == 3 then
		W, Hh = 0.5, 0.5
	elseif self.lux >= 5 then
		W, Hh = 0.52, 0.52
	end
	-- 1) 기존 스위치 바로 옆 (같은 높이, 0.75 옆)
	local dcf: CFrame? = nil
	local inv = self.V.cf:Inverse()
	for _, plate in self.switches or {} do
		if dcf then
			break
		end
		if plate.Parent then
			local sc = inv * plate.CFrame * CF(0, 0, -0.0225)
			for _, dx in { 0.62 + W / 2, -(0.62 + W / 2) } do
				local c = sc * CF(dx, 0, 0)
				local mn, mx = laabb(c * CF(0, 0, 0.08), V3(W + 0.12, Hh + 0.12, 0.16))
				local behind = (c * CF(0, 0, -0.08)).Position
				local front = (c * CF(0, 0, 0.3)).Position
				if self:insideWall(behind) and not self:insideWall(front) and self:mine(V3(front.X, 0.5, front.Z)) and self:boxFree(mn, mx) and not hitsAny(built, mn, mx) then
					dcf = c
					self:use(mn, mx)
					break
				end
			end
		end
	end
	-- 2) 없으면 문 쪽 벽 스위치 높이
	if not dcf then
		local fc = self:floorCenter()
		local _, _, d = self:wallSpot(W + 0.1, 3.95, 4.6, 0.14, {
			score = near(fc + V3(0, 0, 8)),
			accept = function(cfm: CFrame)
				local mn, mx = laabb(cfm, V3(W + 0.1, 0.65, 0.14))
				return not hitsAny(built, mn, mx)
			end,
		})
		dcf = d
	end
	if not dcf then
		return
	end
	local c = (dcf :: CFrame) * CF(0, 4.25 - (dcf :: CFrame).Position.Y, 0)
	local lbl: TextLabel? = nil
	local led: BasePart? = nil
	local body: BasePart? = nil
	K:free(function()
		if self.lux == 2 then
			-- 원룸: 가스보일러 실내 조절기 (하얀 몸통 · 주황 백라이트 LCD · 버튼 4 · 전원)
			body = K:rbox("HomeThermoBody", V3(W, Hh, 0.1), 0.06, c * CF(0, 0, 0.05), lk(244, 244, 240))[1]
			K:box("HomeThermoLCDBezel", V3(0.4, 0.24, 0.02), c * CF(0, 0.12, 0.105), lk(60, 62, 66))
			local _, t = K:text("HomeThermoLCD", 0.36, 0.2, c * CF(0, 0.12, 0.116), "난방 23°", { bg = c3(255, 196, 120), fg = c3(60, 40, 20), d = 0.006, free = true, font = Enum.Font.Code, glow = 1.2 })
			lbl = t
			for i = 0, 3 do
				K:box("HomeThermoBtn", V3(0.08, 0.05, 0.02), c * CF(-0.15 + i * 0.1, -0.08, 0.105), lk(214, 214, 210))
			end
			K:disc("HomeThermoPower", 0.09, 0.02, c * CF(0.15, -0.2, 0.11) * ANG(PI / 2, 0, 0), lk(220, 60, 50))
			led = K:box("HomeThermoLED", V3(0.03, 0.03, 0.01), c * CF(-0.17, -0.2, 0.105), L.neon(c3(255, 140, 40)))
			K:text("HomeThermoBrand", 0.26, 0.05, c * CF(-0.05, -0.2, 0.101), "난방 · 온수", { fg = c3(110, 110, 116), d = 0.003, free = true, font = Enum.Font.Gotham })
		elseif self.lux == 3 then
			-- 오피스텔: 개별 냉난방 컨트롤러 (흰 사각 · 검은 유리 화면)
			body = K:rbox("HomeThermoBody", V3(W, Hh, 0.08), 0.05, c * CF(0, 0, 0.04), lk(246, 246, 244))[1]
			K:box("HomeThermoGlass", V3(W - 0.08, Hh - 0.16, 0.012), c * CF(0, 0.04, 0.086), lk(24, 26, 30, M.Glass, { r = 0.1 }))
			local _, t = K:text("HomeThermoLCD", W - 0.14, 0.16, c * CF(0, 0.06, 0.093), "난방 24℃", { fg = c3(120, 210, 255), d = 0.004, free = true, font = Enum.Font.GothamMedium, glow = 1.4 })
			lbl = t
			led = K:box("HomeThermoLED", V3(0.04, 0.02, 0.01), c * CF(0, -0.17, 0.085), L.neon(c3(255, 140, 40)))
		elseif self.lux == 4 then
			-- 아파트: 각방 온도조절기 (흰 몸통 · LCD · ▲▼)
			body = K:rbox("HomeThermoBody", V3(W - 0.08, Hh - 0.06, 0.09), 0.05, c * CF(0, 0, 0.045), lk(246, 246, 242))[1]
			K:box("HomeThermoLCDBezel", V3(0.34, 0.22, 0.015), c * CF(0, 0.1, 0.096), lk(70, 74, 78))
			local _, t = K:text("HomeThermoLCD", 0.3, 0.18, c * CF(0, 0.1, 0.105), "22.5℃", { bg = c3(196, 226, 214), fg = c3(30, 40, 40), d = 0.005, free = true, font = Enum.Font.Code, glow = 1.1 })
			lbl = t
			K:text("HomeThermoUp", 0.08, 0.07, c * CF(-0.07, -0.1, 0.091), "▲", { fg = c3(120, 120, 126), d = 0.004, free = true })
			K:text("HomeThermoDn", 0.08, 0.07, c * CF(0.07, -0.1, 0.091), "▼", { fg = c3(120, 120, 126), d = 0.004, free = true })
			led = K:box("HomeThermoLED", V3(0.03, 0.03, 0.01), c * CF(0, -0.2, 0.092), L.neon(c3(255, 140, 40)))
		else
			-- 펜트하우스: 블랙 글라스 스마트 조절기 (하얀 숫자 · 아이콘 줄)
			body = K:box("HomeThermoBody", V3(W, Hh, 0.06), c * CF(0, 0, 0.03), lk(16, 16, 18, M.Glass, { r = 0.15 }))
			K:box("HomeThermoRim", V3(W + 0.03, Hh + 0.03, 0.03), c * CF(0, 0, 0.015), L.brushed)
			local _, t = K:text("HomeThermoLCD", W - 0.12, 0.2, c * CF(0, 0.06, 0.062), "22℃", { fg = c3(250, 250, 250), d = 0.004, free = true, font = Enum.Font.GothamMedium, glow = 1.3 })
			lbl = t
			K:text("HomeThermoMode", W - 0.16, 0.07, c * CF(0, -0.1, 0.062), "바닥난방 · 자동", { fg = c3(170, 170, 176), d = 0.004, free = true, font = Enum.Font.Gotham, glow = 1 })
			led = K:box("HomeThermoLED", V3(0.12, 0.012, 0.008), c * CF(0, -0.19, 0.062), L.neon(c3(255, 150, 70)))
		end
	end)
	self.thermo = { body = body, label = lbl, led = led }
	-- 상호작용: 난방 온도 바꾸기 (LCD 숫자 · 난방 LED)
	if body and lbl then
		local steps = if self.lux == 2 then { "난방 23°", "난방 25°", "외출", "난방 21°" }
			elseif self.lux == 3 then { "난방 24℃", "난방 26℃", "냉방 23℃", "꺼짐" }
			elseif self.lux == 4 then { "22.5℃", "24.0℃", "외출", "20.5℃" }
			else { "22℃", "24℃", "에코 20℃", "꺼짐" }
		local ledCol = led and led.Color
		self:withPrompt(body, function()
			return Interact.cycle(K, body :: BasePart, steps, { action = "온도 바꾸기", object = "난방 조절기", on = function(_i, st)
				if lbl then
					lbl.Text = st
				end
				if led and led.Parent then
					local off = st == "외출" or st == "꺼짐"
					led.Material = if off then M.SmoothPlastic else M.Neon
					led.Color = if off then c3(70, 70, 74) elseif string.find(st, "냉방") then c3(80, 170, 255) else (ledCol :: Color3)
				end
			end })
		end)
	end
end

-- 남은 큰 빈 벽: 눈높이 액자 (이미 건 벽 장식 · 큰 가구에서 먼 곳부터, 등급별 액자 스타일)
function C:fillWalls(maxN: number)
	local K = self.K
	if self.V.decorPlus or maxN <= 0 or HomeWet.rooms[self.room] or self.room == "dress" or self.room == "entry" then
		return
	end
	local placed = 0
	local kinds = if self.lux >= 5 then { "field", "lines", "field", "bridge" }
		elseif self.lux == 4 then { "sea", "field", "lines", "warm" }
		elseif self.lux == 3 then { "bridge", "lines", "abstract", "sea" }
		else { "sea", "warm", "lines", "bridge" }
	for n = 1, maxN do
		local built = self:builtBoxes(3.4, 7.6)
		-- 이미 벽에 있는 것들 (액자 · TV · 에어컨 · 키 큰 가구)의 가운데
		local centers = {}
		local cell = {}
		local function addC(q: Vector3)
			local key = string.format("%d,%d,%d", math.floor(q.X / 0.8), math.floor(q.Y / 1.2), math.floor(q.Z / 0.8))
			if not cell[key] then
				cell[key] = true
				table.insert(centers, q)
			end
		end
		for _, b in built do
			local sz = b.mx - b.mn
			if math.max(sz.X, sz.Y, sz.Z) > 0.5 then
				addC((b.mn + b.mx) / 2)
			end
		end
		local calls = 0
		for _, r in self:obstacles() do
			if r.max.Y > 4.0 and r.min.Y < 7.0 and not self.K.hidden[r.part] then
				addC(r.c)
			end
		end
		local memo = {}
		local function minD(p: Vector3): number
			local mk = string.format("%.2f,%.2f,%.2f", p.X, p.Y, p.Z)
			if memo[mk] then
				return memo[mk]
			end
			local d = math.huge
			for _, q in centers do
				d = math.min(d, (V3(p.X, 0, p.Z) - V3(q.X, 0, q.Z)).Magnitude + math.abs(p.Y - q.Y) * 0.3)
			end
			memo[mk] = d
			return d
		end
		local done = false
		for _, sz in (if self.lux >= 4 then { { 4.2, 2.6 }, { 3.0, 2.2 }, { 2.0, 2.6 } } else { { 3.0, 2.2 }, { 2.0, 2.6 } }) do
			local w, h = sz[1], sz[2]
			local cy = math.min(5.5, self.H - h / 2 - 0.9)
			local y0, y1 = cy - h / 2 - 0.1, cy + h / 2 + 0.1
			if y0 < 4.0 then
				continue
			end
			local _, _, art = self:wallSpotHigh(w + 0.2, y0, y1, 0.2, {
				margin = 0.5,
				score = function(_s, _u, cfm)
					return -minD(cfm.Position)
				end,
				accept = function(cfm: CFrame)
					calls += 1
					if calls % 8 == 0 then
						self:yield()
					end
					if minD(cfm.Position) < 2.2 + w / 2 then
						return false
					end
					local mn, mx = laabb(cfm, V3(w + 0.2, y1 - y0, 0.2))
					return not hitsAny(built, mn, mx)
				end,
			})
			if art then
				local seed = self.seed + n * 13 + placed
				local kind = kinds[(seed % #kinds) + 1]
				K:free(function()
					local f
					if self.lux >= 5 then
						f = artFrame(K, art, w, h, { gallery = true, depth = 0.16, edge = lk(240, 236, 228, M.Fabric) })
						local fc3 = if kind == "field" then (if seed % 2 == 0 then { c3(46, 52, 66), c3(150, 120, 86), c3(28, 30, 36) } else { c3(120, 46, 36), c3(200, 140, 70), c3(70, 24, 24) }) else { c3(236, 230, 220), c3(214, 196, 170), c3(176, 96, 60) }
						artPaint(K, f, w, h, kind, seed, fc3)
					elseif self.lux == 4 then
						f = artFrame(K, art, w, h, { frame = if seed % 2 == 0 then lk(236, 232, 224, M.Wood) else L.walnut, border = 0.1, mat = lk(250, 250, 246) })
						artPaint(K, f, w - 0.7, h - 0.7, kind, seed, if kind == "field" then { c3(206, 196, 178), c3(120, 140, 150), c3(170, 120, 90) } else { c3(236, 230, 218), c3(80, 110, 130), c3(204, 150, 110) })
					elseif self.lux == 3 then
						f = artFrame(K, art, w, h, { frame = L.oak, border = 0.07, depth = 0.08, mat = lk(248, 248, 244) })
						artPaint(K, f, w - 0.6, h - 0.6, kind, seed, { c3(238, 234, 226), c3(40, 60, 90), c3(220, 160, 110) })
					else
						-- 원룸: 얇은 검정 알루미늄 포스터 액자
						f = artFrame(K, art, w * 0.8, h, { frame = lk(30, 30, 32, M.Metal), border = 0.05, depth = 0.05 })
						artPaint(K, f, w * 0.8 - 0.14, h - 0.14, kind, seed, { c3(240, 236, 228), c3(60, 90, 140), c3(230, 140, 90) })
					end
				end)
				placed += 1
				done = true
				break
			end
		end
		if not done then
			break
		end
	end
	if placed > 0 then
		K:note(string.format("home fillWalls: %d", placed))
	end
end

T.C = C

-------------------------------------------------------------------------------------------------
-- 디스패처
-------------------------------------------------------------------------------------------------
function T.style(V: any): any
	return { chair = false, stool = false, table = false, counter = false, base = false, lower = false, mat = false, clock = false, license = false, cctv = false, ceiling = false, lights = { kind = "none" }, skip = { upgrades = true, fixtures = true, floor = true, ceiling = true, walls = true } }
end

function T.build(K: any, V: any, S: any)
	K.maxParts = math.min(K.maxParts, if HomeWet.rooms[V.room] then 1500 else 1400)
	local ok, Cx = pcall(newCtx, K, V)
	if not ok then
		K:note("home ctx error: " .. tostring(Cx))
		if HomeWet.rooms[V.room] then
			HomeWet.build(K, V, S)
		end
		return
	end
	local function step(name: string, fn: (any) -> ())
		local ok2, err = pcall(fn, Cx)
		if not ok2 then
			K:note("home." .. name .. " error: " .. tostring(err))
		end
	end
	K:note(string.format("home %s/%s H=%.1f (box %.1f) segs=%d walls=%d floors=%d", Cx.tier, Cx.room, Cx.H, Cx.Hbox, #Cx.segs, #Cx.walls, #Cx.floors))
	K.homeCx = Cx -- (오프라인 테스트 · 디버그용 참조)
	step("keepfix", function(c) c:fixKeeps() end)
	if T.dumpKeep then
		for _, kz in V.keep do
			K:note(string.format("keep %s x[%.1f,%.1f] y[%.1f,%.1f] z[%.1f,%.1f]", tostring(kz.kind), kz.min.X, kz.max.X, kz.min.Y, kz.max.Y, kz.min.Z, kz.max.Z))
		end
	end
	step("trims", function(c) c:trims() end)
	step("fixtures", function(c) c:fixtures() end)
	step("ceiling", function(c) c:ceilingKit() end)
	step("windows", function(c) c:windows() end)
	step("slots", function(c) c:slotOverlays() end)
	if HomeWet.rooms[V.room] then
		local ok3, err = pcall(HomeWet.build, K, V, S)
		if not ok3 then
			K:note("HomeWet error: " .. tostring(err))
		end
	else
		step("room", function(c) c:roomDress() end)
		step("interact", function(c) c:interactions() end)
		step("thermo", function(c) c:thermostat() end)
		step("fillWalls", function(c) c:fillWalls(({ goshiwon = 0, oneroom = 1, officetel = 2, apartment = 2, penthouse = 2 })[c.tier] or 1) end)
	end
end

return T
