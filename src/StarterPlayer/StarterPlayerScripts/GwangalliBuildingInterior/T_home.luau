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
		while u <= s.len - margin - w / 2 + 1e-3 do
			local cfm = self:segCF(s, u, (y0 + y1) / 2, dep / 2)
			local mn, mx = laabb(cfm, V3(w, y1 - y0, dep))
			local score = if o.score then o.score(s, u, cfm) else 0
			if score < bs and self:boxFree(mn, mx, o) then
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
		local h = p.Size / 2 + V3(2.2, 1.2, 2.2)
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
		if d:IsA("BasePart") and d.Transparency < 0.99 then
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
			local d = b.c - ctr
			if math.abs(d.X) > math.abs(d.Z) and math.abs(d.X) > 0.2 then
				F = F * ANG(0, if d.X > 0 then -PI / 2 else PI / 2, 0)
			elseif d.Z > 0.2 then
				F = F * ANG(0, PI, 0)
			end
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
	step("trims", function(c) c:trims() end)
	if HomeWet.rooms[V.room] then
		local ok3, err = pcall(HomeWet.build, K, V, S)
		if not ok3 then
			K:note("HomeWet error: " .. tostring(err))
		end
	end
end

return T
