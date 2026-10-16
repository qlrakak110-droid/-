--!strict
-- GwangalliBuildingInterior/HomeWet: 생활 게임 집의 물 쓰는 방 · 붙박이 (T_home 이 부름, T_home 의 공통 마감 다음).
--   HomeWet.rooms[room] = true 인 방 (kitchen 주방 · bath 욕실 · entry 현관) 의 붙박이 · 설비 · 작은 물건을 짓습니다.
--   HomeWet.build(K, V, S)   V.room / V.tier (goshiwon · oneroom · officetel · apartment · penthouse) 로 갈래
--
-- 하는 일 (모두 이 클라이언트에만, 맵 파트는 숨기기만):
--   주방  템플릿의 상자 싱크대(BaseCabinet · UpperCabinet · CounterTop · Sink · RangeHood ...)를 같은 자리 · 같은 높이로
--         진짜 싱크대로 다시 지음 (문짝 · 서랍 · 손잡이 · 걸레받이 · 언더싱크 볼 · 수전 · 인덕션 · 슬림 후드 · 빌트인 가전),
--         냉장고 · 김치냉장고 · 전자레인지 · 밥솥 · 전기포트 · 드럼세탁기 리스킨, 조리대 위 살림 (식기건조대 · 고무장갑 ·
--         양념 · 도마 · 수저통 · 냄비 ...), 분리수거함 · 음식물 쓰레기통 · 냉장고 자석 · 메모.
--   욕실  바닥 FloorBath 마다 한 칸 (아파트처럼 욕실이 둘이면 둘 다): 비데 변기 · 세면대 + 거울 수납장 · 샤워 수전 ·
--         욕조 리스킨, 수건 · 칫솔컵 · 샴푸 · 이태리타올 · 휴지걸이 · 욕실화 · 환풍기 · 타일 줄눈 · 천장재 줄.
--   현관  신발장 리스킨 (문짝 · 간접등 · 거울), 신발 · 슬리퍼 리스킨, 도어락 안쪽 · 도어클로저 · 월패드 · 센서등,
--         우산꽂이 · 택배 상자 · 구둣주걱 · 분전반 · 소화기 (등급별).
-- 상호작용 (R 키, 서버 집 행동과 겹치지 않음): 수전 물 틀기 · 수납장 문 · 후드 · 서랍 · 세탁기 · 밥솥 · 거울장 ·
--   환풍기 · 변기 뚜껑 · 신발장 문 · 분전반, 프롬프트 없는 것: 현관 센서등 (가까이 가면 켜짐) · 월패드 화면 순환.
-- 지키는 것: Shell 의 Room/Surface 파트 · Room 조명 (테마 색) 은 숨기지 않음, HomeInteract · FurnitureSlot · GwDecorItem
--   자리 (V.keep "point" · "slot") 와 문 앞 · 통로는 비움, 새 불빛은 방마다 2 개까지, V.decorPlus 면 바닥 소품 없음.

local Look = require(script.Parent:WaitForChild("Look"))
local Interact = require(script.Parent:WaitForChild("Interact"))
local Scan = require(script.Parent:WaitForChild("Scan"))
local Kit = require(script.Parent:WaitForChild("Kit"))

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")

local HomeWet = {}
HomeWet.rooms = { kitchen = true, bath = true, entry = true }

local M = Enum.Material
local CF, V3, ANG = CFrame.new, Vector3.new, CFrame.Angles
local PI = math.pi
local C3 = Color3.fromRGB
local FONT_B, FONT_M = Enum.Font.GothamBold, Enum.Font.GothamMedium

local TIER = { goshiwon = 1, oneroom = 2, officetel = 3, apartment = 4, penthouse = 5 }
local MAX_LIGHTS = 2 -- 이 파일이 방마다 더하는 불빛 (T_home 몫 포함 3 이하)

-- 색 · 재질 ------------------------------------------------------------------------------------------------
local function lk(r: number, g: number, b: number, m: Enum.Material?, extra: { [string]: any }?): any
	return Look.of(r, g, b, m, extra)
end
local function col(c: Color3, m: Enum.Material?, extra: { [string]: any }?): any
	local t: any = { c = c, m = m or M.SmoothPlastic }
	if extra then
		for k, v in extra do
			t[k] = v
		end
	end
	return t
end
local function shade(c: Color3, t: number): Color3
	if t >= 0 then
		return c:Lerp(Color3.new(1, 1, 1), t)
	end
	return c:Lerp(Color3.new(0, 0, 0), -t)
end

local LK = {
	white = lk(246, 246, 243),
	gloss = lk(244, 243, 240, M.SmoothPlastic, { r = 0.06 }),
	ivory = lk(238, 232, 220),
	abs = lk(238, 238, 234, M.Plastic),
	absGrey = lk(176, 180, 184, M.Plastic),
	plasticBlack = lk(30, 30, 32, M.Plastic),
	black = lk(22, 22, 24),
	charcoal = lk(52, 54, 58),
	rubber = Look.rubber,
	steel = lk(188, 190, 194, M.Metal, { r = 0.1 }),
	steelDark = lk(118, 122, 128, M.Metal),
	brushed = lk(166, 168, 172, M.Metal),
	chrome = lk(226, 228, 232, M.Metal, { r = 0.3 }),
	alu = Look.alu,
	brass = lk(184, 150, 92, M.Metal, { r = 0.12 }),
	bronze = lk(120, 96, 70, M.Metal, { r = 0.08 }),
	gunmetal = lk(62, 64, 68, M.Metal, { r = 0.06 }),
	glassBlack = { c = C3(18, 18, 20), m = M.Glass, r = 0.2, t = 0 },
	glassSmoke = { c = C3(40, 44, 48), m = M.Glass, t = 0.25, r = 0.15 },
	glassClear = { c = C3(214, 232, 236), m = M.Glass, t = 0.7, r = 0.12 },
	glassFrost = { c = C3(236, 242, 242), m = M.Glass, t = 0.3, r = 0.04 },
	mirror = { c = C3(198, 208, 214), m = M.Glass, t = 0.02, r = 0.55 },
	water = { c = C3(196, 226, 238), m = M.Glass, t = 0.45, r = 0.2 },
	porcelain = lk(248, 248, 246, M.SmoothPlastic, { r = 0.05 }),
	ceramic = lk(242, 242, 238, M.SmoothPlastic, { r = 0.04 }),
	paper = lk(248, 246, 240),
	kraft = lk(190, 150, 104, M.Cardboard),
	cardboard = lk(176, 136, 92, M.Cardboard),
	tape = lk(214, 196, 150, M.SmoothPlastic, { t = 0.15 }),
	fabricW = lk(244, 242, 236, M.Fabric),
	wood = Look.oak,
	walnut = Look.walnut,
	led = Look.neon(C3(255, 236, 214)),
	ledCool = Look.neon(C3(232, 244, 255)),
	ledOff = lk(220, 220, 214, M.SmoothPlastic, { t = 0.1 }),
	red = lk(204, 40, 36),
	grout = lk(196, 194, 188),
}

-- 결정적 난수 (같은 집은 늘 같은 배치)
local function hashStr(s: string): number
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 2147483647
	end
	return h
end
local function rng(seed: any): () -> number
	local s = (if type(seed) == "number" then seed else hashStr(tostring(seed))) % 2147483646 + 1
	return function(): number
		s = (s * 16807) % 2147483647
		return (s - 1) / 2147483646
	end
end

local laabb = Kit.laabb
local overlap = Kit.overlap

-- 숨기면 안 되는 서버 파트 (테마 · 게임플레이 · 화면)
local function protected(p: BasePart): boolean
	if p:GetAttribute("Room") ~= nil or p:GetAttribute("Surface") ~= nil then
		return true
	end
	if p.Name == "Screen" or p.Name == "TVScreen" or p.Name == "UnitRoot" or p.Name == "Spawn" or p.Name == "HomeSpawn" then
		return true
	end
	if CollectionService:HasTag(p, "HomeInteract") or string.sub(p.Name, 1, 9) == "Interact_" then
		return true
	end
	local a = p.Parent
	while a and a ~= workspace do
		if a.Name == "Backdrop" or a.Name == "WindowView" or a.Name == "ExitDoor" or a.Name == "HomeInteractions" then
			return true
		end
		if a:IsA("Model") and (CollectionService:HasTag(a, "FurnitureSlot") or CollectionService:HasTag(a, "GwDecorItem")) then
			return true
		end
		a = a.Parent
	end
	return false
end

-- 방 틀 (Ctx) ------------------------------------------------------------------------------------------------
-- C.cf = V 프레임 기준 이 방(또는 조리대 한 줄 · 욕실 한 칸) 의 틀. 모든 좌표는 C 로컬 (원점 = 바닥 위,
-- +Z = 문 · 사람 쪽, +X = -Z 를 볼 때 오른쪽). 이 파일의 파트는 전부 K:free 안에서 만들고, 자리 검사는 C:clear 로 직접.
local Ctx = {}
Ctx.__index = Ctx

local function newCtx(K: any, V: any, cf: CFrame, x0: number, x1: number, z0: number, z1: number, H: number, seed: string): any
	local C = setmetatable({}, Ctx) :: any
	C.K, C.V, C.cf = K, V, cf
	C.wcf = K.cf * cf
	C.x0, C.x1, C.z0, C.z1, C.H = x0, x1, z0, z1, H
	C.W, C.D = x1 - x0, z1 - z0
	C.tier = V.tier or "oneroom"
	C.ti = TIER[C.tier] or 2
	C.hi = K.detail == "high"
	C.lo = K.detail == "low"
	C.rnd = rng(tostring(V.key) .. seed)
	return C
end

function Ctx:box(n: string, s: Vector3, cf: CFrame, l: any): BasePart
	return self.K:box(n, s, self.cf * cf, l)
end
function Ctx:wedge(n: string, s: Vector3, cf: CFrame, l: any): BasePart
	return self.K:wedge(n, s, self.cf * cf, l)
end
function Ctx:cyl(n: string, len: number, d: number, cf: CFrame, l: any): BasePart
	return self.K:cyl(n, len, d, self.cf * cf, l)
end
function Ctx:vcyl(n: string, h: number, d: number, cf: CFrame, l: any): BasePart
	return self.K:vcyl(n, h, d, self.cf * cf, l)
end
function Ctx:ball(n: string, d: number, cf: CFrame, l: any): BasePart
	return self.K:ball(n, d, self.cf * cf, l)
end
function Ctx:ell(n: string, s: Vector3, cf: CFrame, l: any): BasePart
	return self.K:ell(n, s, self.cf * cf, l)
end
function Ctx:seg(n: string, a: Vector3, b: Vector3, d: number, l: any, extra: number?): BasePart?
	return self.K:seg(n, self.cf * a, self.cf * b, d, l, extra)
end
function Ctx:bar(n: string, a: Vector3, b: Vector3, w: number, h: number, l: any): BasePart?
	return self.K:bar(n, self.cf * a, self.cf * b, w, h, l)
end
function Ctx:rbox(n: string, s: Vector3, r: number, cf: CFrame, l: any): { BasePart }
	return self.K:rbox(n, s, r, self.cf * cf, l)
end
function Ctx:slab(n: string, w: number, len: number, t: number, r: number, cf: CFrame, l: any): { BasePart }
	return self.K:slab(n, w, len, t, r, self.cf * cf, l)
end
function Ctx:panel(n: string, w: number, h: number, d: number, r: number, dcf: CFrame, l: any): { BasePart }
	return self.K:panel(n, w, h, d, r, self.cf * dcf, l)
end
function Ctx:disc(n: string, dia: number, t: number, cf: CFrame, l: any): BasePart
	return self.K:disc(n, dia, t, self.cf * cf, l)
end
function Ctx:plate(n: string, w: number, h: number, d: number, dcf: CFrame, l: any): BasePart
	return self.K:plate(n, w, h, d, self.cf * dcf, l)
end
function Ctx:ring(n: string, frame: CFrame, R: number, d: number, k: number, l: any, a0: number?, a1: number?): { BasePart }
	return self.K:ring(n, self.cf * frame, R, d, k, l, a0, a1)
end
function Ctx:text(n: string, w: number, h: number, dcf: CFrame, s: string, o: any?): (BasePart, TextLabel)
	local oo: any = table.clone(o or {})
	oo.free = true
	return self.K:text(n, w, h, self.cf * dcf, s, oo)
end
-- 글자판 줄임: 판 색 bg (nil = 투명), 글자 fg
function Ctx:label(n: string, w: number, h: number, dcf: CFrame, s: string, fg: Color3?, bg: Color3?, o: any?): (BasePart, TextLabel)
	local oo: any = table.clone(o or {})
	oo.fg = fg or C3(30, 30, 34)
	oo.bg = bg
	oo.d = oo.d or 0.01
	oo.font = oo.font or FONT_B
	return self:text(n, w, h, dcf, s, oo)
end
function Ctx:group(name: string, fn: () -> ()): Model
	return self.K:group(name, fn)
end
-- 불빛 (방마다 MAX_LIGHTS 까지)
function Ctx:light(p: BasePart, kind: string, props: { [string]: any }): Light?
	local K = self.K
	K.hwLights = K.hwLights or 0
	if K.hwLights >= MAX_LIGHTS then
		return nil
	end
	local l = K:light(p, kind, props)
	if l then
		K.hwLights += 1
	end
	return l
end
-- 로컬 점 / 틀 -> 월드
function Ctx:world(p: Vector3): Vector3
	return self.wcf * p
end
function Ctx:wvec(v: Vector3): Vector3
	return self.wcf:VectorToWorldSpace(v)
end
-- 맵 파트 기록(rec, V 로컬 AABB) -> C 로컬 AABB
function Ctx:bb(rec: any): (Vector3, Vector3)
	local c = self.cf:ToObjectSpace(CFrame.new(rec.c))
	return laabb(c, rec.size)
end
function Ctx:inside(rec: any, m: number?): boolean
	local p = self.cf:PointToObjectSpace(rec.c)
	local mm = m or 0.3
	return p.X > self.x0 - mm and p.X < self.x1 + mm and p.Z > self.z0 - mm and p.Z < self.z1 + mm and p.Y > -1 and p.Y < self.H + 1
end
-- 이름들로 이 틀 안 맵 파트 찾기 (보이는 것만)
function Ctx:find(names: { string }, m: number?): { any }
	local out = {}
	for _, n in names do
		for _, r in self.V.byName[n] or {} do
			if r.part.Transparency < 0.99 and self:inside(r, m) then
				table.insert(out, r)
			end
		end
	end
	return out
end
function Ctx:first(names: { string }, m: number?): any?
	return self:find(names, m)[1]
end
-- 맵 파트 숨기기 (이미 다른 모듈이 숨긴 것 · 지켜야 할 것은 그대로)
function Ctx:hide(rec: any): boolean
	if not rec or not rec.part then
		return false
	end
	local p: BasePart = rec.part
	if protected(p) then
		return false
	end
	Scan.hide(self.K.hidden, p)
	return true
end
function Ctx:hideAll(list: { any })
	for _, r in list do
		self:hide(r)
	end
end
function Ctx:taken(rec: any): boolean
	return rec ~= nil and self.K.hidden[rec.part] ~= nil
end

-- 자리 검사 ----------------------------------------------------------------------------------------------------
-- mode: "floor" 바닥 소품 | "mat" 바닥에 깔리는 얇은 것 (< 0.2) | "top" 조리대 · 선반 위 | "wall" 벽에 붙는 것 |
--       "flush" 기존 면에 0.12 이하로 붙는 것 (냉장고 자석 · 스티커)
local function pointSmall(k: any): boolean
	local s = k.max - k.min
	return s.Y < 3.0
end
function Ctx:hitsKeep(mn: Vector3, mx: Vector3, mode: string): string?
	for _, k in self.V.keep do
		local kind = k.kind
		if kind == "window" then
			continue
		end
		if kind == "point" then
			if (mode == "wall" or mode == "flush") and not pointSmall(k) then
				continue
			end
		elseif kind == "restroom" or kind == "aisle" or kind == "door" or kind == "npc" or kind == "staff" or kind == "bin" then
			if mode ~= "floor" and mode ~= "top" then
				continue
			end
			if mode == "top" and kind ~= "restroom" then
				continue
			end
		elseif kind == "table" or kind == "seat" then
			if mode == "flush" then
				continue
			end
		end
		if overlap(mn, mx, k.min, k.max, 0.03) then
			return kind
		end
	end
	return nil
end
-- 이 파일 전에 다른 모듈 (T_home) 이 만든 파트 중 부딪힐 만한 것 (걸레받이 · 몰딩 같은 얇은 띠 제외)
function Ctx:priorBoxes(): { any }
	local K = self.K
	if K.hwPrior then
		return K.hwPrior
	end
	local out = {}
	local n = K.hwStart or 0
	for i = 1, n do
		local p = K.parts[i]
		if p and p.Parent then
			local mn, mx = laabb(K.cf:ToObjectSpace(p.CFrame), p.Size)
			local s = mx - mn
			local thin = math.min(s.X, s.Z) < 0.16 and (mn.Y < 0.7 or mx.Y > (self.V.H or 8) - 0.8)
			if not thin and p.Transparency < 0.95 then
				table.insert(out, { min = mn, max = mx })
			end
		end
	end
	K.hwPrior = out
	return out
end
-- C 로컬 상자 (cf = 상자 가운데, size) 가 비었나? V.solid (숨긴 것 제외) · keep · 예약 · 앞 모듈 파트
function Ctx:clear(cf: CFrame, size: Vector3, mode: string, pad: number?): boolean
	local pd = pad or 0
	local mn, mx = laabb(self.cf * cf, size + V3(2 * pd, 0, 2 * pd))
	local V, K = self.V, self.K
	if self:hitsKeep(mn, mx, mode) then
		return false
	end
	if mode == "floor" or mode == "mat" then
		-- 방 (V) 안, 욕실 한 칸처럼 틀이 방이면 그 틀 안
		local a, b = laabb(self.cf * cf, size)
		if a.X < V.x0 - 0.05 or b.X > V.x1 + 0.05 or a.Z < V.z0 - 0.05 or b.Z > V.z1 + 0.05 then
			return false
		end
		if self.bounded then
			local c, d = laabb(cf, size)
			if c.X < self.x0 - 0.05 or d.X > self.x1 + 0.05 or c.Z < self.z0 - 0.05 or d.Z > self.z1 + 0.05 then
				return false
			end
		end
	end
	if mode ~= "flush" then
		for _, s in V.solid do
			if not K.hidden[s.part] and overlap(mn, mx, s.min, s.max, 0.03) then
				return false
			end
		end
		for _, s in V.wallItems do
			if not K.hidden[s.part] and overlap(mn, mx, s.min, s.max, 0.03) then
				return false
			end
		end
		for _, s in self:priorBoxes() do
			if overlap(mn, mx, s.min, s.max, 0.02) then
				return false
			end
		end
	end
	for _, r in K.reserved do
		if overlap(mn, mx, r.min, r.max, 0.02) then
			return false
		end
	end
	for _, r in K.hwRes or {} do
		if overlap(mn, mx, r.min, r.max, 0.01) then
			return false
		end
	end
	return true
end
-- 자리 예약 (C 로컬 상자)
function Ctx:reserve(cf: CFrame, size: Vector3)
	local K = self.K
	K.hwRes = K.hwRes or {}
	local mn, mx = laabb(self.cf * cf, size)
	table.insert(K.hwRes, { min = mn, max = mx })
end
-- 검사 + 예약
function Ctx:claim(cf: CFrame, size: Vector3, mode: string, pad: number?): boolean
	if self:clear(cf, size, mode, pad) then
		self:reserve(cf, size)
		return true
	end
	return false
end

-- 벽 표시면 프레임 (C 로컬). side = "back"(-Z) | "front"(+Z) | "left"(-X) | "right"(+X); u = 벽 가운데 기준 보는 사람 오른쪽
function Ctx:wall(side: string, u: number, y: number, off: number?): CFrame
	local o = off or 0
	local cx, cz = (self.x0 + self.x1) / 2, (self.z0 + self.z1) / 2
	if side == "back" then
		return CFrame.fromMatrix(V3(cx + u, y, self.z0 + o), V3(1, 0, 0), V3(0, 1, 0), V3(0, 0, 1))
	elseif side == "front" then
		return CFrame.fromMatrix(V3(cx - u, y, self.z1 - o), V3(-1, 0, 0), V3(0, 1, 0), V3(0, 0, -1))
	elseif side == "left" then
		return CFrame.fromMatrix(V3(self.x0 + o, y, cz - u), V3(0, 0, -1), V3(0, 1, 0), V3(1, 0, 0))
	end
	return CFrame.fromMatrix(V3(self.x1 - o, y, cz + u), V3(0, 0, 1), V3(0, 1, 0), V3(-1, 0, 0))
end
-- 점 p 에서 n 방향을 보는 수평 틀 (pcf: +Z = n)
local function faceCF(p: Vector3, n: Vector3): CFrame
	local z = V3(n.X, 0, n.Z)
	if z.Magnitude < 1e-3 then
		z = V3(0, 0, 1)
	end
	z = z.Unit
	return CFrame.fromMatrix(p, V3(0, 1, 0):Cross(z), V3(0, 1, 0), z)
end
-- 수평면 위에 놓인 판 (dcf +Z = 위): 바닥 매트 · 조리대 위 글자
local function upCF(p: Vector3, fwd: Vector3?): CFrame
	local f = fwd or V3(0, 0, 1)
	return CFrame.fromMatrix(p, V3(0, 1, 0):Cross(f).Unit * -1, f, V3(0, 1, 0))
end

-- 상호작용 -------------------------------------------------------------------------------------------------------
-- 집의 서버 프롬프트(HomeInteract) 자리와 2.4 스터드 이상 떨어진 곳에만 우리 R 프롬프트 (Interact.canPrompt 의 가게 앵커
-- 6.5 규칙은 집에는 맞지 않아, 이 파일이 부르는 동안만 K.hostPts 를 집 기준으로 바꿈)
function Ctx:promptOK(part: BasePart): boolean
	if part.Parent == nil then
		return false
	end
	local lp = self.K.cf:PointToObjectSpace(part.Position)
	for _, k in self.V.keep do
		if k.kind == "point" then
			local cx = math.clamp(lp.X, k.min.X, k.max.X)
			local cz = math.clamp(lp.Z, k.min.Z, k.max.Z)
			local cy = math.clamp(lp.Y, k.min.Y, k.max.Y)
			if (V3(cx, cy, cz) - lp).Magnitude < (if pointSmall(k) then 2.6 else 1.4) then
				return false
			end
		end
	end
	return true
end
function Ctx:toggle(part: BasePart?, spec: any): ProximityPrompt?
	if not part or not self:promptOK(part) then
		return nil
	end
	return Interact.toggle(self.K, part, spec)
end
-- 여닫이: model 을 hinge (C 로컬 점) 둘레 axis (C 로컬) 로 angle
function Ctx:swing(model: Model, hinge: Vector3, axis: Vector3, angle: number, spec: any): ProximityPrompt?
	local h = model:FindFirstChildWhichIsA("BasePart", true)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and string.find(d.Name, "Handle") then
			h = d
		end
	end
	if not h or not self:promptOK(h) then
		return nil
	end
	return Interact.swing(self.K, model, self:world(hinge), self:wvec(axis).Unit, angle, spec)
end
-- 미닫이 · 서랍: model 을 C 로컬 방향 dir 로 dist 만큼
function Ctx:slide(model: Model, dir: Vector3, dist: number, spec: any): ProximityPrompt?
	local parts = {}
	local handle: BasePart? = nil
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, { p = d, cf = d.CFrame })
			if string.find(d.Name, "Handle") or not handle then
				handle = d
			end
		end
	end
	if not handle or not self:promptOK(handle) then
		return nil
	end
	local off = self:wvec(dir).Unit * dist
	local open = false
	return Interact.prompt(self.K, handle, {
		action = spec.openText or "열기",
		object = spec.object or "서랍",
		sound = spec.sound or "rbxasset://sounds/clickfast.wav",
		fn = function(_n, p)
			open = not open
			for _, r in parts do
				if r.p.Parent then
					TweenService:Create(r.p, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = if open then CFrame.new(off) * r.cf else r.cf }):Play()
				end
			end
			p.ActionText = if open then (spec.closeText or "닫기") else (spec.openText or "열기")
			if spec.on then
				spec.on(open)
			end
		end,
	})
end
-- 네온 켜고 끄기 (켜진 색 / 꺼진 색)
local function setGlow(parts: { BasePart }, on: boolean, onC: Color3?, offC: Color3?)
	for _, p in parts do
		if p.Parent then
			p.Material = if on then M.Neon else M.SmoothPlastic
			if onC and offC then
				p.Color = if on then onC else offC
			end
		end
	end
end
local function setVis(parts: { BasePart }, t: number)
	for _, p in parts do
		if p.Parent then
			p.Transparency = t
		end
	end
end

-- 플레이어가 이 점(월드) 가까이 있나 (센서등 · 월패드)
local function playerNear(wp: Vector3, r: number): boolean
	local plr = Players.LocalPlayer
	local ch = plr and plr.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return (hrp.Position - wp).Magnitude < r
	end
	return false
end

-- 유효 천장 높이 (복층 아래 주방 · 욕실: Homes 는 집 전체의 가장 높은 천장을 씀)
local CEIL_FIX = { Downlight = true, DownlightTrim = true, BathLight = true, SmokeDetector = true, SensorLight = true, VentFan = true, LEDPanel = true, PowderLight = true, Sprinkler = true }
local function ceilingAt(V: any, cx: number, cz: number, hx: number, hz: number): number
	local best = V.H
	local slab = math.huge
	local fixTop = -math.huge
	for _, r in V.parts do
		local inX = r.max.X > cx - hx and r.min.X < cx + hx
		local inZ = r.max.Z > cz - hz and r.min.Z < cz + hz
		if inX and inZ then
			if (r.name == "Ceiling" or r.name == "LoftSlab" or (r.shell and r.size.Y < 1.2 and r.size.X > 3 and r.size.Z > 3)) and r.min.Y > 5.5 and r.min.Y < slab then
				if r.min.X <= cx and r.max.X >= cx and r.min.Z <= cz and r.max.Z >= cz then
					slab = r.min.Y
				end
			end
			if CEIL_FIX[r.name] and r.max.Y > 5.5 then
				fixTop = math.max(fixTop, r.max.Y)
			end
		end
	end
	if slab < best then
		best = slab
	end
	if fixTop > 5.5 and fixTop < best - 0.05 and slab == math.huge then
		best = fixTop
	end
	return best
end

-- 공통 작은 소품 ---------------------------------------------------------------------------------------------------
-- 플라스틱 병 (pcf = 바닥 가운데): h, d, 몸통 look, 뚜껑 look, 라벨 (색, 글자)
local function bottle(C: any, pcf: CFrame, h: number, d: number, body: any, cap: any, labelC: Color3?, labelT: string?, o: any?)
	local oo: any = o or {}
	local shoulder = oo.shoulder or 0.78
	C:vcyl("Bottle", h * shoulder, d, pcf * CF(0, h * shoulder / 2, 0), body)
	if oo.square then
		C:box("BottleSq", V3(d, h * shoulder, d * 0.7), pcf * CF(0, h * shoulder / 2, 0), body)
	end
	C:ell("BottleShoulder", V3(d, h * 0.16, d), pcf * CF(0, h * shoulder, 0), body)
	C:vcyl("BottleNeck", h * 0.12, d * 0.42, pcf * CF(0, h * (shoulder + 0.08), 0), body)
	C:vcyl("BottleCap", h * 0.1, d * 0.5, pcf * CF(0, h * 0.95, 0), cap)
	if oo.pump then
		C:vcyl("PumpStem", h * 0.18, d * 0.16, pcf * CF(0, h * 1.08, 0), cap)
		C:box("PumpHead", V3(d * 0.26, h * 0.06, d * 0.7), pcf * CF(0, h * 1.17, d * 0.2), cap)
	end
	if labelC and C.hi then
		local lw = d * 0.86
		local lh = h * shoulder * 0.5
		if labelT and labelT ~= "" then
			C:label("BottleLabel", lw, lh, pcf * CF(0, h * shoulder * 0.5, d / 2 + 0.004), labelT, shade(labelC, -0.75), labelC, { d = 0.006 })
		else
			C:plate("BottleLabel", lw, lh, 0.006, pcf * CF(0, h * shoulder * 0.5, d / 2), col(labelC))
		end
	end
end

-- 수건 (반 접어 바에 건 것): dcf = 바 높이 · 벽 표면, w 폭, drop 길이, look, 띠 색, 글자
local function hangingTowel(C: any, dcf: CFrame, w: number, drop: number, look: any, stripe: Color3?, txt: string?)
	local t = 0.07
	C:box("TowelFront", V3(w, drop, t), dcf * CF(0, -drop / 2, 0.16), look)
	C:box("TowelBack", V3(w * 0.98, drop * 0.86, t), dcf * CF(0, -drop * 0.43, 0.07), look)
	C:cyl("TowelFold", w, 0.12, dcf * CF(0, 0, 0.115), look)
	if stripe then
		C:box("TowelStripe", V3(w + 0.004, 0.08, t + 0.006), dcf * CF(0, -drop + 0.22, 0.16), col(stripe, M.Fabric))
	end
	if txt and C.hi then
		C:label("TowelPrint", w * 0.86, 0.26, dcf * CF(0, -drop + 0.48, 0.2), txt, stripe or C3(60, 90, 140), nil, { font = FONT_M })
	end
end

-- 접어 쌓은 수건 (pcf = 바닥 가운데): n 장, 색 목록
local function towelStack(C: any, pcf: CFrame, w: number, d: number, n: number, colors: { Color3 })
	local y = 0
	for i = 1, n do
		local c = colors[(i - 1) % #colors + 1]
		local th = 0.16
		C:rbox("TowelFolded", V3(w, th, d), 0.06, pcf * CF(0, y + th / 2, 0), col(c, M.Fabric))
		y += th
	end
	return y
end

-- 운동화 한 짝 (pcf = 바닥, +Z = 앞코), 길이 L, 폭 w
local function sneaker(C: any, pcf: CFrame, L: number, w: number, upper: any, sole: any, accent: any?)
	C:rbox("ShoeSole", V3(w, 0.1, L), 0.05, pcf * CF(0, 0.05, 0), sole)
	C:ell("ShoeToe", V3(w * 0.96, 0.24, L * 0.42), pcf * CF(0, 0.15, L * 0.27), upper)
	C:rbox("ShoeUpper", V3(w * 0.94, 0.26, L * 0.58), 0.1, pcf * CF(0, 0.22, -L * 0.14), upper)
	C:ell("ShoeHeel", V3(w * 0.9, 0.34, L * 0.3), pcf * CF(0, 0.26, -L * 0.33), upper)
	C:box("ShoeOpening", V3(w * 0.6, 0.02, L * 0.3), pcf * CF(0, 0.355, -L * 0.18), lk(40, 40, 42, M.Fabric))
	if accent and C.hi then
		C:box("ShoeSwoosh", V3(w * 0.97, 0.05, L * 0.4), pcf * CF(0, 0.2, -L * 0.05) * ANG(math.rad(-8), 0, 0), accent)
		C:box("ShoeLace", V3(w * 0.4, 0.03, L * 0.22), pcf * CF(0, 0.33, L * 0.04) * ANG(math.rad(-14), 0, 0), lk(250, 250, 248, M.Fabric))
	end
end
-- 구두 · 로퍼 한 짝
local function dressShoe(C: any, pcf: CFrame, L: number, w: number, leather: any)
	C:rbox("ShoeSole", V3(w, 0.06, L), 0.04, pcf * CF(0, 0.03, 0), lk(40, 30, 24, M.Rubber))
	C:box("ShoeHeelBlock", V3(w * 0.86, 0.1, L * 0.22), pcf * CF(0, 0.05, -L * 0.38), lk(40, 30, 24, M.Rubber))
	C:ell("ShoeToe", V3(w * 0.94, 0.2, L * 0.5), pcf * CF(0, 0.12, L * 0.22), leather)
	C:rbox("ShoeUpper", V3(w * 0.9, 0.22, L * 0.55), 0.09, pcf * CF(0, 0.17, -L * 0.17), leather)
	C:box("ShoeOpening", V3(w * 0.62, 0.02, L * 0.34), pcf * CF(0, 0.285, -L * 0.2), lk(70, 50, 36, M.Leather))
end
-- 삼선 슬리퍼 / 욕실화 한 짝
local function slipper(C: any, pcf: CFrame, L: number, w: number, sole: any, strap: any, stripes: boolean?)
	C:rbox("SlipperSole", V3(w, 0.1, L), 0.12, pcf * CF(0, 0.05, 0), sole)
	C:rbox("SlipperStrap", V3(w * 1.02, 0.16, L * 0.36), 0.07, pcf * CF(0, 0.16, L * 0.12), strap)
	if stripes and C.hi then
		for i = -1, 1 do
			C:box("SlipperStripe", V3(w * 1.04, 0.165, 0.035), pcf * CF(0, 0.16, L * 0.12 + i * 0.075), LK.white)
		end
	end
end

-- 우산 (세워 둔 장우산): pcf 바닥, h, 색
local function umbrella(C: any, pcf: CFrame, h: number, c: Color3, lean: number)
	local base = pcf * ANG(lean, 0, lean * 0.6)
	C:vcyl("UmbrellaTip", 0.2, 0.05, base * CF(0, 0.1, 0), LK.steelDark)
	C:vcyl("UmbrellaCanopy", h * 0.62, 0.32, base * CF(0, 0.2 + h * 0.31, 0), col(c, M.Fabric))
	C:ell("UmbrellaTop", V3(0.3, 0.2, 0.3), base * CF(0, 0.2 + h * 0.62, 0), col(c, M.Fabric))
	C:vcyl("UmbrellaShaft", h * 0.26, 0.06, base * CF(0, 0.2 + h * 0.62 + h * 0.13, 0), LK.steelDark)
	C:ring("UmbrellaHook", base * CF(0.14, 0.2 + h * 0.9, 0), 0.14, 0.07, 5, lk(60, 40, 30, M.Wood), 0, PI)
end

-- 택배 상자 (pcf 바닥), 크기, 송장 글자
local function parcel(C: any, pcf: CFrame, s: Vector3, txt: string)
	C:box("ParcelBox", s, pcf * CF(0, s.Y / 2, 0), LK.cardboard)
	C:box("ParcelTape", V3(0.28, 0.006, s.Z + 0.01), pcf * CF(0, s.Y + 0.003, 0), LK.tape)
	C:box("ParcelTapeF", V3(0.28, s.Y * 0.35, 0.006), pcf * CF(0, s.Y * 0.82, s.Z / 2 + 0.003), LK.tape)
	if C.hi then
		C:label("ParcelLabel", math.min(1.0, s.X * 0.55), 0.5, pcf * CF(-s.X * 0.18, s.Y * 0.45, s.Z / 2 + 0.004), txt, C3(30, 30, 30), C3(250, 250, 248), { wrap = true, font = FONT_M })
		C:plate("ParcelBarcode", 0.3, 0.12, 0.005, pcf * CF(s.X * 0.28, s.Y * 0.3, s.Z / 2), lk(30, 30, 30))
	end
end

--=================================================================================================================
-- 주방 ---------------------------------------------------------------------------------------------------------------
--=================================================================================================================
-- 조리대 한 줄 (run) 틀: 원점 = 조리대 가운데의 벽면 바닥, +Z = 조리대 앞 (사람 쪽), +X = 조리대를 볼 때 오른쪽.
-- 그 안에서 z = 0 벽 ~ zf 하부장 문짝 면 ~ zt 상판 앞 끝, y = 바닥 위.

-- 등급별 주방 마감
local function kitchenStyle(ti: number, base: Color3, top: Color3): any
	local st: any = {}
	if ti >= 5 then
		st.front = col(shade(base, 0.02), M.Wood)
		st.carcass = col(shade(base, -0.25), M.Wood)
		st.handle = "bar"
		st.handleL = LK.bronze
		st.top = col(top, M.Marble)
		st.kick = lk(40, 36, 32)
		st.gap = 0.035
	elseif ti == 4 then
		st.front = col(base, M.SmoothPlastic)
		st.carcass = col(shade(base, -0.12))
		st.handle = "bar"
		st.handleL = LK.brushed
		st.top = col(top, M.Marble)
		st.kick = lk(196, 194, 190)
		st.gap = 0.03
	elseif ti == 3 then
		st.front = col(base, M.SmoothPlastic)
		st.carcass = col(shade(base, -0.15))
		st.handle = "groove"
		st.handleL = LK.gunmetal
		st.top = col(top, M.Marble)
		st.kick = lk(60, 60, 62)
		st.gap = 0.03
	else
		st.front = col(base, M.SmoothPlastic, { r = 0.05 })
		st.carcass = col(shade(base, -0.12))
		st.handle = "lip"
		st.handleL = LK.alu
		st.top = col(top, M.Marble)
		st.kick = lk(70, 70, 72)
		st.gap = 0.03
	end
	return st
end

-- 문짝 (하부장 · 상부장 공통): x0..x1, y0..y1, 면 z (zf), 손잡이 위치 hp = "top" | "bottom" | "left" | "right" | "drawer"
local function cabinetFront(C: any, st: any, name: string, x0: number, x1: number, y0: number, y1: number, zf: number, hp: string): BasePart
	local g = st.gap
	local w, h = x1 - x0 - g, y1 - y0 - g
	local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
	local door = C:box(name, V3(w, h, 0.07), CF(cx, cy, zf + 0.035), st.front)
	local hl = st.handleL
	if st.handle == "bar" then
		if hp == "drawer" then
			local hw = math.min(w * 0.6, 2.2)
			C:box("Handle", V3(hw, 0.05, 0.05), CF(cx, y1 - g - 0.14, zf + 0.12), hl)
			for _, s in { -1, 1 } do
				C:box("HandleFoot", V3(0.04, 0.04, 0.06), CF(cx + s * (hw / 2 - 0.08), y1 - g - 0.14, zf + 0.085), hl)
			end
		else
			local hx = if hp == "left" then x0 + g + 0.14 else x1 - g - 0.14
			local hh = math.min(h * 0.55, 1.6)
			local hy = if hp == "bottom" then y0 + g + hh / 2 + 0.15 elseif hp == "top" then y1 - g - hh / 2 - 0.15 else cy
			C:box("Handle", V3(0.05, hh, 0.05), CF(hx, hy, zf + 0.12), hl)
			for _, s in { -1, 1 } do
				C:box("HandleFoot", V3(0.04, 0.04, 0.06), CF(hx, hy + s * (hh / 2 - 0.06), zf + 0.085), hl)
			end
		end
	elseif st.handle == "groove" then
		-- 손잡이 없는 J 홈: 윗변(하부) · 아랫변(상부) 의 어두운 홈
		local gy = if hp == "bottom" then y0 + g / 2 + 0.03 else y1 - g / 2 - 0.03
		C:box("HandleGroove", V3(w, 0.06, 0.02), CF(cx, gy, zf + 0.071), lk(40, 40, 42))
		C:box("Handle", V3(w * 0.96, 0.02, 0.04), CF(cx, gy + (if hp == "bottom" then -0.03 else 0.03), zf + 0.075), hl)
	else
		-- 알루미늄 립 손잡이 (문짝 위 · 아래 끝)
		local ly = if hp == "bottom" then y0 + g / 2 + 0.02 else y1 - g / 2 - 0.02
		C:box("Handle", V3(math.min(w * 0.5, 1.2), 0.05, 0.1), CF(cx, ly, zf + 0.09), hl)
	end
	return door
end

-- 하부장 모듈 나누기: segs = { {a, b} } (x), specials = { {a, b, kind} } -> 모듈 목록 { a, b, kind }
local function splitModules(segs: { any }, specials: { any }): { any }
	local mods = {}
	for _, s in segs do
		local cuts = {}
		for _, sp in specials do
			local a, b = math.max(sp.a, s.a), math.min(sp.b, s.b)
			if b - a > 0.4 then
				table.insert(cuts, { a = a, b = b, kind = sp.kind })
			end
		end
		table.sort(cuts, function(p, q)
			return p.a < q.a
		end)
		local cur = s.a
		local function fill(a: number, b: number)
			local w = b - a
			if w < 0.05 then
				return
			elseif w < 0.75 then
				table.insert(mods, { a = a, b = b, kind = "filler" })
				return
			end
			local n = math.max(1, math.ceil(w / 2.05))
			for i = 1, n do
				table.insert(mods, { a = a + w * (i - 1) / n, b = a + w * i / n, kind = "door" })
			end
		end
		for _, c in cuts do
			if c.a > cur then
				fill(cur, c.a)
			end
			table.insert(mods, c)
			cur = math.max(cur, c.b)
		end
		if s.b > cur then
			fill(cur, s.b)
		end
	end
	table.sort(mods, function(p, q)
		return p.a < q.a
	end)
	return mods
end

-- 하부장 + 상판 + 개수대 + 인덕션 (run 틀). info = 찾은 맵 파트
local function kitchenBase(C: any, st: any, info: any)
	local zf = info.zf -- 하부장 문짝 면
	local zt = info.zt -- 상판 앞 끝
	local ytop = info.ytop -- 상판 윗면
	local ybot = ytop - 0.14
	local kick = info.kickH
	local segs = {}
	for _, r in info.base do
		local mn, mx = C:bb(r)
		table.insert(segs, { a = mn.X, b = mx.X })
	end
	table.sort(segs, function(p, q)
		return p.a < q.a
	end)
	-- 특수 모듈
	local specials = {}
	if info.sinkBB then
		local mn, mx = info.sinkBB[1], info.sinkBB[2]
		local c, w = (mn.X + mx.X) / 2, math.clamp(mx.X - mn.X + 0.5, 2.2, 3.1)
		table.insert(specials, { a = c - w / 2, b = c + w / 2, kind = "sink" })
		info.sinkMod = { a = c - w / 2, b = c + w / 2 }
		-- 식기세척기 (아파트 · 펜트하우스): 개수대 옆, 인덕션 반대쪽
		if C.ti >= 4 then
			local hobC = if info.hobBB then (info.hobBB[1].X + info.hobBB[2].X) / 2 else c - 10
			local side = if hobC < c then 1 else -1
			local a = if side > 0 then c + w / 2 else c - w / 2 - 2.14
			local b = a + 2.14
			for _, s in segs do
				if a >= s.a - 0.01 and b <= s.b + 0.01 then
					table.insert(specials, { a = a, b = b, kind = "dw" })
					info.dw = { a = a, b = b }
					break
				end
			end
		end
	end
	if info.hobBB then
		local mn, mx = info.hobBB[1], info.hobBB[2]
		local c, w = (mn.X + mx.X) / 2, math.clamp(mx.X - mn.X + 0.3, 1.7, 3.4)
		table.insert(specials, { a = c - w / 2, b = c + w / 2, kind = if C.ti >= 5 then "oven" else "hob" })
	end
	local mods = splitModules(segs, specials)
	-- 수저 서랍 하나 (인덕션 옆 문 모듈)
	local drawerMod = nil
	for i, m in mods do
		if m.kind == "door" and m.b - m.a > 1.2 and m.b - m.a < 2.4 then
			local nb = mods[i - 1]
			local na = mods[i + 1]
			if (nb and (nb.kind == "hob" or nb.kind == "oven")) or (na and (na.kind == "hob" or na.kind == "oven")) then
				m.kind = "drawers"
				drawerMod = m
				break
			end
		end
	end
	if not drawerMod then
		for _, m in mods do
			if m.kind == "door" and m.b - m.a > 1.2 then
				m.kind = "drawers"
				drawerMod = m
				break
			end
		end
	end
	-- 몸통 (문짝 뒤): 세그먼트마다 하나
	for _, s in segs do
		C:box("CabCarcass", V3(s.b - s.a, ybot - kick, zf - 0.02), CF((s.a + s.b) / 2, kick + (ybot - kick) / 2, (zf - 0.02) / 2), st.carcass)
		-- 걸레받이 (안으로 들어간 킥)
		C:box("CabKick", V3(s.b - s.a, kick, 0.06), CF((s.a + s.b) / 2, kick / 2, zf - 0.28), st.kick)
		C:box("CabKickShadow", V3(s.b - s.a, kick, zf - 0.34), CF((s.a + s.b) / 2, kick / 2, (zf - 0.34) / 2), lk(30, 30, 32))
	end
	local yb = kick + 0.02
	local yband = ybot - 0.44 -- 서랍 띠 아래
	local doorIdx = 0
	for _, m in mods do
		local a, b = m.a, m.b
		if m.kind == "filler" then
			cabinetFront(C, { gap = st.gap, front = st.front, handle = "none", handleL = st.handleL }, "CabFiller", a, b, yb, ybot - 0.01, zf, "top")
		elseif m.kind == "sink" then
			-- 개수대 하부장: 위 가짜 서랍판 + 양문
			local mid = (a + b) / 2
			C:box("SinkFalseFront", V3(b - a - st.gap, ybot - yband - st.gap, 0.07), CF(mid, (yband + ybot) / 2, zf + 0.035), st.front)
			cabinetFront(C, st, "CabDoor", a, mid, yb, yband, zf, "right")
			cabinetFront(C, st, "CabDoor", mid, b, yb, yband, zf, "left")
		elseif m.kind == "dw" then
			-- 빌트인 식기세척기: 통문짝 + 위 조작부
			local w = b - a - st.gap
			C:box("DWPanel", V3(w, ybot - yb - st.gap, 0.07), CF((a + b) / 2, (yb + ybot) / 2, zf + 0.035), st.front)
			C:box("DWControl", V3(w - 0.1, 0.12, 0.02), CF((a + b) / 2, ybot - 0.12, zf + 0.075), LK.black)
			if C.hi then
				C:label("DWDisplay", 0.5, 0.09, CF((a + b) / 2 + w * 0.25, ybot - 0.12, zf + 0.087), "1:28", C3(120, 220, 255), nil, { glow = 1 })
				for i = 0, 3 do
					C:disc("DWButton", 0.06, 0.01, CF((a + b) / 2 - w * 0.3 + i * 0.14, ybot - 0.12, zf + 0.088) * ANG(PI / 2, 0, 0), LK.steelDark)
				end
			end
			if st.handle == "bar" then
				C:box("Handle", V3(math.min(w * 0.6, 1.4), 0.05, 0.05), CF((a + b) / 2, ybot - 0.32, zf + 0.12), st.handleL)
			end
		elseif m.kind == "hob" or m.kind == "drawers" then
			-- 서랍 3단 (냄비 서랍 / 수저 서랍)
			local hs = { yb, yb + (yband - yb) * 0.5, yband, ybot }
			for i = 1, 3 do
				local f = cabinetFront(C, st, "CabDrawer", a, b, hs[i], hs[i + 1], zf, "drawer")
				if i == 3 and m == drawerMod then
					info.cutleryFront = { a = a, b = b, y0 = hs[3], y1 = hs[4], part = f }
				end
			end
		elseif m.kind == "oven" then
			-- 빌트인 오븐 (인덕션 아래) + 위 서랍
			local w = b - a - st.gap
			cabinetFront(C, st, "CabDrawer", a, b, yband, ybot, zf, "drawer")
			local oy0, oy1 = yb + 0.2, yband - 0.02
			C:box("OvenFrame", V3(w, oy1 - oy0, 0.08), CF((a + b) / 2, (oy0 + oy1) / 2, zf + 0.04), LK.black)
			C:box("OvenGlass", V3(w - 0.3, (oy1 - oy0) * 0.62, 0.02), CF((a + b) / 2, oy0 + (oy1 - oy0) * 0.4, zf + 0.09), LK.glassSmoke)
			C:box("OvenHandleBar", V3(w * 0.8, 0.06, 0.06), CF((a + b) / 2, oy1 - 0.2, zf + 0.16), LK.steel)
			C:box("OvenControl", V3(w - 0.2, 0.18, 0.02), CF((a + b) / 2, oy1 - 0.06, zf + 0.09), LK.steelDark)
			if C.hi then
				C:label("OvenDisplay", 0.5, 0.12, CF((a + b) / 2, oy1 - 0.06, zf + 0.1), "180°", C3(255, 170, 80), nil, { glow = 1 })
			end
			cabinetFront(C, st, "CabDrawer", a, b, yb, oy0, zf, "drawer")
		else
			doorIdx += 1
			cabinetFront(C, st, "CabDoor", a, b, yb, yband, zf, if doorIdx % 2 == 0 then "left" else "right")
			cabinetFront(C, st, "CabDrawer", a, b, yband, ybot, zf, "drawer")
		end
	end
	info.mods = mods
	-- 상판: 개수대 구멍 둘레 조각 + 앞 모서리
	local topA, topB = math.huge, -math.huge
	for _, r in info.tops do
		local mn, mx = C:bb(r)
		topA = math.min(topA, mn.X)
		topB = math.max(topB, mx.X)
	end
	local zr = 0
	local function topPiece(a: number, b: number, z0: number, z1: number)
		if b - a > 0.01 and z1 - z0 > 0.01 then
			C:box("CounterSlab", V3(b - a, 0.14, z1 - z0), CF((a + b) / 2, ybot + 0.07, (z0 + z1) / 2), st.top)
		end
	end
	if info.sinkBB then
		local mn, mx = info.sinkBB[1], info.sinkBB[2]
		local ca, cb = mn.X + 0.08, mx.X - 0.08
		local cz0, cz1 = math.max(mn.Z + 0.08, 0.35), math.min(mx.Z - 0.08, zt - 0.3)
		info.bowl = { a = ca, b = cb, z0 = cz0, z1 = cz1 }
		topPiece(topA, ca, zr, zt)
		topPiece(cb, topB, zr, zt)
		topPiece(ca, cb, zr, cz0)
		topPiece(ca, cb, cz1, zt)
	else
		topPiece(topA, topB, zr, zt)
	end
	C:box("CounterEdge", V3(topB - topA, 0.03, 0.02), CF((topA + topB) / 2, ybot + 0.015, zt + 0.005), col(shade(st.top.c, -0.12), st.top.m))
	info.topA, info.topB = topA, topB
end

-- 언더싱크 볼 + 수전 + 물 (상호작용)
local function kitchenSink(C: any, st: any, info: any)
	local bw = info.bowl
	if not bw then
		return
	end
	local ytop = info.ytop
	local depth = 0.72
	local yb = ytop - 0.14 - depth + 0.14
	local cx, cz = (bw.a + bw.b) / 2, (bw.z0 + bw.z1) / 2
	local w, d = bw.b - bw.a, bw.z1 - bw.z0
	local s = LK.steel
	C:box("SinkBowlFloor", V3(w, 0.03, d), CF(cx, yb, cz), s)
	C:box("SinkBowlWall", V3(w, depth, 0.03), CF(cx, yb + depth / 2, bw.z0), s)
	C:box("SinkBowlWall", V3(w, depth, 0.03), CF(cx, yb + depth / 2, bw.z1), s)
	C:box("SinkBowlWall", V3(0.03, depth, d), CF(bw.a, yb + depth / 2, cz), s)
	C:box("SinkBowlWall", V3(0.03, depth, d), CF(bw.b, yb + depth / 2, cz), s)
	C:disc("SinkDrain", 0.36, 0.02, CF(cx + w * 0.22, yb + 0.02, cz), LK.steelDark)
	C:disc("SinkDrainBasket", 0.26, 0.025, CF(cx + w * 0.22, yb + 0.025, cz), LK.brushed)
	-- 개수대 안 이야기: 담가 둔 국그릇 + 숟가락, 배수구 거름망
	if C.hi then
		C:vcyl("SoakBowl", 0.26, 0.6, CF(cx - w * 0.18, yb + 0.14, cz + 0.05), LK.ceramic)
		C:disc("SoakWater", 0.52, 0.01, CF(cx - w * 0.18, yb + 0.24, cz + 0.05), LK.water)
		C:bar("SoakSpoon", V3(cx - w * 0.18 + 0.1, yb + 0.26, cz + 0.05), V3(cx - w * 0.18 + 0.42, yb + 0.42, cz + 0.2), 0.04, 0.02, LK.steel)
	end
	-- 수전 (풀다운 구즈넥): 맵 Faucet 자리
	local fx, fz = cx, math.max(0.18, bw.z0 - 0.22)
	if info.faucetBB then
		local mn, mx = info.faucetBB[1], info.faucetBB[2]
		fx, fz = (mn.X + mx.X) / 2, math.clamp((mn.Z + mx.Z) / 2, 0.15, bw.z0 - 0.12)
	end
	local fl = if C.ti >= 5 then LK.gunmetal elseif C.ti == 3 then lk(40, 40, 42, M.Metal) else LK.chrome
	C:disc("FaucetBase", 0.26, 0.04, CF(fx, ytop + 0.02, fz), fl)
	local riseH = if C.ti >= 3 then 1.55 else 1.05
	C:vcyl("FaucetBody", riseH, 0.14, CF(fx, ytop + riseH / 2, fz), fl)
	local R = 0.34
	C:ring("FaucetNeck", CF(fx, ytop + riseH, fz + R) * ANG(0, PI / 2, 0), R, 0.12, 6, fl, 0, PI)
	local hx, hy, hz = fx, ytop + riseH - 0.12, fz + 2 * R
	C:vcyl("FaucetSprayHead", 0.3, 0.15, CF(hx, hy, hz), fl)
	C:disc("FaucetAerator", 0.11, 0.02, CF(hx, hy - 0.16, hz), LK.steelDark)
	local lever = C:box("FaucetHandle", V3(0.06, 0.06, 0.34), CF(fx + 0.1, ytop + riseH * 0.45, fz + 0.12) * ANG(math.rad(-20), 0, 0), fl)
	C:vcyl("FaucetLeverHub", 0.12, 0.12, CF(fx + 0.1, ytop + riseH * 0.45 - 0.06, fz), fl)
	-- 세제 디스펜서 (상판 매립)
	if C.ti >= 4 then
		C:disc("SoapPumpBase", 0.14, 0.02, CF(cx + w / 2 - 0.25, ytop + 0.01, fz), fl)
		C:vcyl("SoapPumpNeck", 0.22, 0.06, CF(cx + w / 2 - 0.25, ytop + 0.11, fz), fl)
		C:box("SoapPumpSpout", V3(0.05, 0.04, 0.16), CF(cx + w / 2 - 0.25, ytop + 0.22, fz + 0.06), fl)
	end
	-- 물줄기
	local stream = C:vcyl("FaucetWater", hy - 0.17 - (yb + 0.02), 0.07, CF(hx, (hy - 0.17 + yb + 0.02) / 2, hz), { c = C3(210, 236, 248), m = M.Glass, t = 1, r = 0.1 })
	local splash = C:disc("FaucetSplash", 0.3, 0.015, CF(hx, yb + 0.03, hz), { c = C3(230, 246, 252), m = M.Glass, t = 1 })
	C:toggle(lever, {
		object = "싱크대 수전",
		onText = "물 잠그기",
		offText = "물 틀기",
		state = false,
		on = function(on: boolean)
			setVis({ stream }, if on then 0.35 else 1)
			setVis({ splash }, if on then 0.5 else 1)
		end,
	})
	info.faucet = V3(fx, ytop, fz)
end

-- 인덕션 (유리 상판 + 화구 링 + 터치 조작부) + 올려 둔 냄비
local function kitchenHob(C: any, st: any, info: any)
	local hb = info.hobBB
	if not hb then
		return
	end
	local mn, mx = hb[1], hb[2]
	local ytop = info.ytop
	local cx, cz = (mn.X + mx.X) / 2, (mn.Z + mx.Z) / 2
	local w, d = mx.X - mn.X, mx.Z - mn.Z
	C:box("HobGlass", V3(w, 0.035, d), CF(cx, ytop + 0.018, cz), LK.glassBlack)
	C:box("HobFrame", V3(w + 0.04, 0.03, d + 0.04), CF(cx, ytop + 0.012, cz), LK.steelDark)
	local rings = info.rings
	if #rings == 0 then
		local n = if w > 2.6 then 3 else 2
		for i = 1, n do
			table.insert(rings, V3(mn.X + w * (i - 0.5) / n, 0, cz - 0.1))
		end
	end
	local zoneOn: { BasePart } = {}
	for i, p in rings do
		local dia = if i == 1 and #rings >= 3 then 0.9 else 0.72
		C:disc("HobZoneLine", dia, 0.004, CF(p.X, ytop + 0.037, p.Z), lk(120, 120, 124))
		C:disc("HobZone", dia - 0.05, 0.005, CF(p.X, ytop + 0.038, p.Z), LK.glassBlack)
		local glow = C:disc("HobZoneGlow", dia * 0.62, 0.004, CF(p.X, ytop + 0.0385, p.Z), lk(70, 24, 20))
		table.insert(zoneOn, glow)
	end
	-- 터치 조작부
	local fz = mx.Z - 0.12
	C:box("HobTouchBar", V3(w * 0.7, 0.002, 0.12), CF(cx, ytop + 0.0365, fz), lk(60, 60, 64))
	if C.hi then
		for i = 0, 5 do
			C:box("HobTouchKey", V3(0.07, 0.002, 0.07), CF(cx - w * 0.3 + i * w * 0.12, ytop + 0.038, fz), lk(200, 200, 204, M.Neon, { t = 0.4 }))
		end
		C:box("HobPowerLED", V3(0.06, 0.002, 0.06), CF(cx + w * 0.42, ytop + 0.038, fz), lk(255, 60, 40, M.Neon))
	end
	info.hobZones = zoneOn
	info.rings = rings
end

-- 슬림 후드 (상부장 아래) + 상호작용 (조명 · 팬)
local function kitchenHood(C: any, st: any, info: any)
	local hb = info.hoodBB
	if not hb then
		return
	end
	local mn, mx = hb[1], hb[2]
	local cx = (mn.X + mx.X) / 2
	local w = mx.X - mn.X
	local d = mx.Z
	local y0, y1 = mn.Y, mx.Y
	local body = if C.ti >= 3 then LK.black else LK.steel
	C:box("HoodBody", V3(w, y1 - y0, d - 0.02), CF(cx, (y0 + y1) / 2, d / 2), body)
	-- 앞 가림판 (당겨 쓰는 슬라이드 바이저)
	C:box("HoodVisor", V3(w, 0.22, 0.12), CF(cx, y0 + 0.11, d + 0.04), if C.ti >= 3 then LK.glassBlack else LK.brushed)
	-- 아랫면: 필터 2장 (줄무늬) + 램프 2
	local lamps: { BasePart } = {}
	for i, f in { -0.25, 0.25 } do
		local fxp = cx + f * w
		C:box("HoodFilter", V3(w * 0.42, 0.02, d * 0.66), CF(fxp, y0 - 0.005, d * 0.4), LK.brushed)
		if C.hi then
			for j = -2, 2 do
				C:box("HoodFilterSlot", V3(w * 0.38, 0.022, 0.025), CF(fxp, y0 - 0.006, d * 0.4 + j * d * 0.11), LK.steelDark)
			end
		end
		local lamp = C:box("HoodLamp", V3(0.28, 0.025, 0.28), CF(cx + (i - 1.5) * w * 0.9, y0 - 0.008, d * 0.82), LK.ledOff)
		table.insert(lamps, lamp)
	end
	-- 버튼
	local btnZ = d + 0.105
	local btn = C:box("HoodButton", V3(0.16, 0.06, 0.02), CF(cx + w * 0.38, y0 + 0.11, btnZ), LK.steelDark)
	C:box("HoodButton", V3(0.16, 0.06, 0.02), CF(cx + w * 0.28, y0 + 0.11, btnZ), LK.steelDark)
	C:box("HoodButton", V3(0.16, 0.06, 0.02), CF(cx + w * 0.18, y0 + 0.11, btnZ), LK.steelDark)
	local led = C:box("HoodLED", V3(0.04, 0.04, 0.01), CF(cx + w * 0.46, y0 + 0.11, btnZ), lk(60, 60, 60))
	local lightObj: Light? = nil
	C:toggle(btn, {
		object = "레인지 후드",
		onText = "후드 끄기",
		offText = "후드 켜기",
		state = false,
		on = function(on: boolean)
			setGlow(lamps, on, C3(255, 238, 214), C3(220, 220, 214))
			setGlow({ led }, on, C3(80, 220, 255), C3(60, 60, 60))
			if on and not lightObj and lamps[1].Parent then
				lightObj = C:light(lamps[1], "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 7, Brightness = 0.9, Angle = 110, Color = C3(255, 232, 205) })
			end
			if lightObj then
				lightObj.Enabled = on
			end
			for _, z in info.hobZones or {} do
				-- 후드를 켜면 앞 화구 하나에 불 (요리 중)
				if z == (info.hobZones or {})[1] then
					setGlow({ z }, on, C3(255, 70, 40), C3(70, 24, 20))
				end
			end
		end,
	})
end

-- 상부장 (문짝 · 하부 LED 그대로) + 문 하나 열리는 수납장 (안에 그릇)
local function kitchenUpper(C: any, st: any, info: any)
	local uppers = {}
	for _, r in info.upper do
		local mn, mx = C:bb(r)
		table.insert(uppers, { mn = mn, mx = mx, hood = r.name == "HoodCabinet" })
	end
	table.sort(uppers, function(p, q)
		return p.mn.X < q.mn.X
	end)
	local opened = false
	for _, u in uppers do
		local mn, mx = u.mn, u.mx
		local zf = mx.Z
		local w = mx.X - mn.X
		local n = math.max(1, math.floor(w / 1.45 + 0.5))
		local y0, y1 = mn.Y, mx.Y
		for i = 1, n do
			local a = mn.X + w * (i - 1) / n
			local b = mn.X + w * i / n
			local hp = if C.ti >= 4 then (if i % 2 == 1 then "right" else "left") else "bottom"
			if st.handle == "bar" then
				hp = if i % 2 == 1 then "right" else "left"
			end
			-- 개수대 위 수납장 하나는 열림: 몸통을 속 빈 상자로
			local canOpen = not opened and not u.hood and info.bowl and a < info.bowl.b + 1.5 and b > info.bowl.a - 1.5 and (b - a) > 1.0 and (b - a) < 2.4 and C.ti >= 2
			if canOpen then
				opened = true
				local t = 0.05
				local cx = (a + b) / 2
				C:box("UpperBack", V3(b - a, y1 - y0, t), CF(cx, (y0 + y1) / 2, t / 2), st.carcass)
				C:box("UpperSide", V3(t, y1 - y0, zf - t), CF(a + t / 2, (y0 + y1) / 2, (zf + t) / 2), st.carcass)
				C:box("UpperSide", V3(t, y1 - y0, zf - t), CF(b - t / 2, (y0 + y1) / 2, (zf + t) / 2), st.carcass)
				C:box("UpperBottom", V3(b - a, t, zf), CF(cx, y0 + t / 2, zf / 2), st.carcass)
				C:box("UpperTop", V3(b - a, t, zf), CF(cx, y1 - t / 2, zf / 2), st.carcass)
				local inner = lk(244, 244, 240)
				local sh = { y0 + (y1 - y0) * 0.36, y0 + (y1 - y0) * 0.68 }
				for _, sy in sh do
					C:box("UpperShelf", V3(b - a - 2 * t, 0.04, zf - t - 0.04), CF(cx, sy, (zf + t) / 2), lk(232, 232, 228, M.Glass, { t = 0.2 }))
				end
				-- 안: 아래칸 접시 탑 · 공기 · 국그릇, 가운데 컵 · 유리잔, 위칸 밀폐용기
				local bw = b - a - 0.2
				local y = y0 + t
				for k = 0, 5 do
					C:disc("CabPlate", 0.8, 0.04, CF(a + 0.6, y + 0.03 + k * 0.05, zf * 0.48), LK.ceramic)
				end
				for k = 0, 2 do
					C:vcyl("CabRiceBowl", 0.24, 0.42, CF(a + 1.25, y + 0.12 + k * 0.17, zf * 0.48), lk(244, 240, 232))
				end
				if bw > 1.4 then
					C:vcyl("CabSoupBowl", 0.26, 0.5, CF(b - 0.4, y + 0.13, zf * 0.48), lk(236, 232, 224))
				end
				for k = 0, 2 do
					local gx = a + 0.3 + k * (bw / 3)
					C:vcyl("CabGlass", 0.4, 0.24, CF(gx, sh[1] + 0.22, zf * 0.42), LK.glassClear)
					C:vcyl("CabMug", 0.34, 0.26, CF(gx + 0.2, sh[1] + 0.19, zf * 0.7), col(({ C3(250, 250, 248), C3(120, 160, 200), C3(230, 200, 120) })[k + 1]))
				end
				for k = 0, 1 do
					C:box("CabContainer", V3(0.5, 0.3, 0.5), CF(a + 0.4 + k * 0.6, sh[2] + 0.17, zf * 0.5), lk(232, 240, 244, M.Glass, { t = 0.4 }))
					C:box("CabContainerLid", V3(0.52, 0.05, 0.52), CF(a + 0.4 + k * 0.6, sh[2] + 0.345, zf * 0.5), lk(70, 130, 200, M.Plastic))
				end
				-- 문짝 (경첩 = 바깥쪽 모서리)
				local hingeX = if hp == "left" then b else a
				local m = C:group("UpperCabinetDoor", function()
					cabinetFront(C, st, "UpperDoor", a, b, y0, y1, zf, hp)
				end)
				local sign = if hingeX == a then -1 else 1
				C:swing(m, V3(hingeX, (y0 + y1) / 2, zf), V3(0, 1, 0), sign * math.rad(100), { object = "그릇 수납장", openText = "열기", closeText = "닫기" })
			else
				cabinetFront(C, st, "UpperDoor", a, b, y0, y1, zf, hp)
			end
		end
		C:box("UpperCarcass", V3(w, y1 - y0 - 0.02, zf - 0.02), CF((mn.X + mx.X) / 2, (y0 + y1) / 2, (zf - 0.02) / 2), st.carcass)
	end
end

-- 가전 리스킨 -------------------------------------------------------------------------------------------------------
-- 냉장고 (맵 FridgeBody / FridgeDoor 자리 그대로). kind = "single" | "sbs" (양문형 4도어) | "kimchi" | "column" (빌트인)
local function fridgeReskin(C: any, mn: Vector3, mx: Vector3, doorZ: number, kind: string, base: Color3, info: any): any
	local w, h = mx.X - mn.X, mx.Y - mn.Y
	local cx = (mn.X + mx.X) / 2
	local d = doorZ - mn.Z
	local body = col(base, if kind == "column" then M.Wood else M.SmoothPlastic, { r = if kind == "column" then 0 else 0.06 })
	local doorL = col(shade(base, 0.03), body.m, { r = body.r })
	C:slab("FridgeShell", w - 0.02, d - 0.06, h, 0.06, CF(cx, mn.Y + h / 2, mn.Z + (d - 0.06) / 2), body)
	local zf = doorZ
	local g = 0.03
	local out: any = { face = zf + 0.1, doors = {} }
	local function door(x0: number, x1: number, y0: number, y1: number, hx: number?)
		local p = C:box("FridgeDoorPanel", V3(x1 - x0 - g, y1 - y0 - g, 0.12), CF((x0 + x1) / 2, (y0 + y1) / 2, zf + 0.04), doorL)
		table.insert(out.doors, { x0 = x0, x1 = x1, y0 = y0, y1 = y1 })
		if hx then
			-- 매립 손잡이 홈 (세로)
			local hh = math.min(1.6, (y1 - y0) * 0.6)
			local hy = if y1 - y0 > 3 then y0 + (y1 - y0) * 0.45 else (y0 + y1) / 2
			if kind == "column" then
				C:box("FridgeHandle", V3(0.06, math.min(4, (y1 - y0) * 0.7), 0.06), CF(hx, (y0 + y1) / 2, zf + 0.17), info.handleL or LK.bronze)
			else
				C:box("FridgeHandle", V3(0.07, hh, 0.04), CF(hx, hy, zf + 0.115), LK.brushed)
			end
		end
		return p
	end
	local y0, y1 = mn.Y + 0.02, mx.Y - 0.02
	if kind == "sbs" then
		-- 위 양문 (프렌치) + 아래 서랍 둘
		local split = mn.Y + h * 0.4
		door(mn.X, cx, split, y1, cx - 0.12)
		door(cx, mx.X, split, y1, cx + 0.12)
		door(mn.X, cx, y0, split, nil)
		door(cx, mx.X, y0, split, nil)
		C:box("FridgeDrawerLip", V3(w * 0.4, 0.05, 0.05), CF(mn.X + w * 0.25, split - 0.12, zf + 0.12), LK.brushed)
		C:box("FridgeDrawerLip", V3(w * 0.4, 0.05, 0.05), CF(mn.X + w * 0.75, split - 0.12, zf + 0.12), LK.brushed)
		-- 디스플레이 (온도)
		C:box("FridgeDisplay", V3(0.5, 0.36, 0.01), CF(mn.X + w * 0.25, mn.Y + h * 0.72, zf + 0.105), LK.glassBlack)
		if C.hi then
			C:label("FridgeDisplayText", 0.44, 0.3, CF(mn.X + w * 0.25, mn.Y + h * 0.72, zf + 0.112), "냉장 3°C\n냉동 -19°C", C3(150, 220, 255), nil, { glow = 1, wrap = true })
		end
	elseif kind == "kimchi" then
		-- 스탠드형 김치냉장고: 위 문 + 서랍 셋
		local cuts = { y0, mn.Y + h * 0.22, mn.Y + h * 0.42, mn.Y + h * 0.62, y1 }
		for i = 1, 4 do
			door(mn.X, mx.X, cuts[i], cuts[i + 1], nil)
			C:box("KimchiLip", V3(w * 0.7, 0.05, 0.05), CF(cx, cuts[i + 1] - 0.14, zf + 0.12), LK.brushed)
		end
		C:box("KimchiPanel", V3(0.7, 0.32, 0.01), CF(cx, mn.Y + h * 0.82, zf + 0.105), LK.glassBlack)
		if C.hi then
			C:label("KimchiPanelText", 0.66, 0.28, CF(cx, mn.Y + h * 0.82, zf + 0.112), "김치 표준\n-1.0°C", C3(140, 230, 170), nil, { glow = 1, wrap = true })
			C:label("KimchiBrand", 0.8, 0.12, CF(cx, mn.Y + h * 0.95, zf + 0.104), "김치플러스", C3(150, 150, 150), nil, { font = FONT_M })
		end
	elseif kind == "column" then
		door(mn.X, mx.X, y0, y1, mn.X + 0.3)
	else
		-- 2 도어 (위 냉동 · 아래 냉장)
		local split = mn.Y + h * 0.63
		door(mn.X, mx.X, split, y1, mn.X + 0.18)
		door(mn.X, mx.X, y0, split, mn.X + 0.18)
	end
	if kind ~= "column" then
		C:box("FridgeKick", V3(w - 0.1, 0.14, 0.04), CF(cx, mn.Y + 0.07, zf - 0.05), LK.charcoal)
	end
	out.mn, out.mx = mn, mx
	return out
end

-- 냉장고 문 자석 · 메모 · 배달 쿠폰 · 달력 (이야기)
local function fridgeDeco(C: any, fr: any, ti: number)
	if not C.hi or not fr or #fr.doors == 0 then
		return
	end
	local dd = fr.doors[1]
	for _, dr in fr.doors do
		if (dr.y1 - dr.y0) > (dd.y1 - dd.y0) then
			dd = dr
		end
	end
	local z = fr.face + 0.005
	local cx = (dd.x0 + dd.x1) / 2
	local w = dd.x1 - dd.x0
	local items = {}
	if ti <= 3 then
		items = {
			{ "치킨 1588-0000\n쿠폰 10장 = 1마리", C3(255, 214, 64), C3(150, 30, 20), 0.55, 0.42 },
			{ "중화요리 짜장 6,000", C3(220, 40, 40), C3(255, 255, 255), 0.5, 0.36 },
			{ "관리비 25일 자동이체", C3(255, 250, 210), C3(60, 60, 60), 0.5, 0.42 },
		}
	else
		items = {
			{ "가족 사진", C3(240, 236, 228), C3(80, 80, 80), 0.62, 0.48 },
			{ "피아노 화·목 4시\n분리수거 수요일", C3(255, 248, 200), C3(60, 60, 60), 0.56, 0.5 },
			{ "2026 10월", C3(250, 250, 250), C3(200, 40, 40), 0.7, 0.8 },
		}
	end
	local ys = { dd.y0 + (dd.y1 - dd.y0) * 0.78, dd.y0 + (dd.y1 - dd.y0) * 0.6, dd.y0 + (dd.y1 - dd.y0) * 0.42 }
	for i, it in items do
		local x = cx + (if i % 2 == 0 then w * 0.18 else -w * 0.12)
		local y = ys[i]
		local dcf = CF(x, y, z) * ANG(0, 0, (C.rnd() - 0.5) * 0.12)
		if it[1] == "가족 사진" then
			C:plate("FridgePhoto", it[4], it[5], 0.01, dcf, lk(250, 250, 248))
			C:plate("FridgePhotoImg", it[4] - 0.08, it[5] - 0.14, 0.012, dcf * CF(0, 0.03, 0), lk(120, 170, 200))
			C:plate("FridgePhotoImg", it[4] - 0.08, (it[5] - 0.14) * 0.4, 0.013, dcf * CF(0, -0.07, 0), lk(220, 196, 150))
			C:ell("FridgePhotoFace", V3(0.12, 0.14, 0.01), dcf * CF(-0.1, 0.06, 0.014), lk(236, 200, 170))
			C:ell("FridgePhotoFace", V3(0.12, 0.14, 0.01), dcf * CF(0.1, 0.05, 0.014), lk(236, 200, 170))
		elseif it[1] == "2026 10월" then
			C:plate("FridgeCalendar", it[4], it[5], 0.01, dcf, lk(250, 250, 248))
			C:label("FridgeCalTitle", it[4] * 0.9, 0.14, dcf * CF(0, it[5] / 2 - 0.1, 0.012), "2026  10", it[3], nil)
			for r = 0, 4 do
				for c = 0, 6 do
					C:plate("FridgeCalDay", 0.06, 0.06, 0.003, dcf * CF(-0.27 + c * 0.09, 0.15 - r * 0.11, 0.011), if c == 0 then lk(230, 120, 110) else lk(200, 200, 200))
				end
			end
			C:ell("FridgeCalCircle", V3(0.12, 0.12, 0.004), dcf * CF(0.0, 0.04, 0.014), lk(230, 60, 60))
		else
			C:label("FridgeMemo", it[4], it[5], dcf, it[1], it[3], it[2], { wrap = true, font = FONT_M })
		end
		C:disc("FridgeMagnet", 0.12, 0.05, dcf * CF(0, it[5] / 2 - 0.05, 0.03) * ANG(PI / 2, 0, 0), col(({ C3(230, 60, 60), C3(60, 140, 220), C3(250, 200, 40) })[i]))
	end
end

-- 전자레인지 (맵 Microwave 자리)
local function microwave(C: any, mn: Vector3, mx: Vector3, ti: number)
	local w, h, d = mx.X - mn.X, mx.Y - mn.Y, mx.Z - mn.Z
	local cx, cy = (mn.X + mx.X) / 2, (mn.Y + mx.Y) / 2
	local bodyL = if ti >= 4 then LK.black else LK.white
	C:slab("MicrowaveBody", w, d, h, 0.05, CF(cx, cy, mn.Z + d / 2), bodyL)
	local zf = mx.Z
	local dw = w * 0.72
	C:box("MicrowaveDoor", V3(dw, h - 0.1, 0.04), CF(mn.X + dw / 2 + 0.04, cy, zf + 0.02), LK.black)
	C:box("MicrowaveWindow", V3(dw - 0.22, h - 0.32, 0.01), CF(mn.X + dw / 2 + 0.04, cy, zf + 0.045), lk(40, 36, 30, M.Glass, { t = 0.15 }))
	C:box("MicrowaveHandle", V3(0.05, h - 0.3, 0.06), CF(mn.X + dw - 0.05, cy, zf + 0.07), LK.steelDark)
	local px = mn.X + dw + (w - dw) / 2 + 0.02
	C:box("MicrowavePanel", V3(w - dw - 0.08, h - 0.1, 0.02), CF(px, cy, zf + 0.01), LK.charcoal)
	C:label("MicrowaveClock", (w - dw) * 0.7, 0.14, CF(px, mx.Y - 0.22, zf + 0.022), "12:30", C3(120, 230, 160), C3(16, 20, 18), { glow = 1 })
	if C.hi then
		C:disc("MicrowaveKnob", 0.2, 0.06, CF(px, cy - 0.12, zf + 0.04) * ANG(PI / 2, 0, 0), LK.steel)
		C:box("MicrowaveStart", V3(0.2, 0.08, 0.02), CF(px, mn.Y + 0.18, zf + 0.025), lk(60, 160, 90))
	end
	for _, s in { -1, 1 } do
		C:vcyl("MicrowaveFoot", 0.03, 0.08, CF(cx + s * w * 0.4, mn.Y + 0.015, mn.Z + d * 0.5), LK.rubber)
	end
end

-- 전기밥솥 (쿠쿠 스타일, 맵 RiceCooker 자리) + 상호작용 (취사)
local function riceCooker(C: any, mn: Vector3, mx: Vector3, ti: number)
	local cx, cz = (mn.X + mx.X) / 2, (mn.Z + mx.Z) / 2
	local y = mn.Y
	local w = math.min(mx.X - mn.X, mx.Z - mn.Z) * 0.98
	local h = math.min(0.85, mx.Y - mn.Y)
	local bodyC = if ti >= 4 then C3(236, 234, 230) else C3(244, 242, 238)
	local accent = if ti >= 4 then C3(140, 116, 92) else C3(200, 36, 40)
	C:vcyl("CookerBody", h * 0.66, w, CF(cx, y + h * 0.33, cz), col(bodyC, M.SmoothPlastic, { r = 0.06 }))
	C:vcyl("CookerBand", 0.06, w + 0.01, CF(cx, y + h * 0.66, cz), col(accent))
	C:ell("CookerLid", V3(w, h * 0.5, w), CF(cx, y + h * 0.66, cz), col(bodyC, M.SmoothPlastic, { r = 0.06 }))
	C:vcyl("CookerSteamCap", 0.07, 0.16, CF(cx, y + h * 0.9, cz - w * 0.12), LK.charcoal)
	C:box("CookerHandle", V3(w * 0.5, 0.06, 0.1), CF(cx, y + h * 0.93, cz + w * 0.05), col(shade(bodyC, -0.1)))
	-- 앞 조작부 (C 로컬 +Z = 사람 쪽)
	local pz = cz + w / 2 + 0.005
	C:box("CookerPanel", V3(w * 0.5, 0.22, 0.03), CF(cx, y + h * 0.45, pz) * ANG(math.rad(-12), 0, 0), LK.black)
	local _, lbl = C:label("CookerDisplay", w * 0.44, 0.15, CF(cx, y + h * 0.47, pz + 0.02) * ANG(math.rad(-12), 0, 0), "백미 · 보온 08", C3(150, 210, 255), nil, { glow = 1 })
	C:box("CookerLatch", V3(0.22, 0.08, 0.05), CF(cx, y + h * 0.7, pz + 0.01), col(accent))
	-- 주걱 꽂이 (옆)
	C:box("PaddleHolder", V3(0.06, 0.3, 0.12), CF(cx + w / 2 + 0.03, y + h * 0.45, cz), col(shade(bodyC, -0.08)))
	C:box("RicePaddle", V3(0.03, 0.42, 0.14), CF(cx + w / 2 + 0.07, y + h * 0.55, cz), LK.white)
	-- 김 (취사 중일 때만)
	local steam: { BasePart } = {}
	for i = 1, 3 do
		table.insert(steam, C:ell("CookerSteam", V3(0.16 + i * 0.06, 0.2, 0.16 + i * 0.06), CF(cx, y + h * 0.95 + i * 0.22, cz - w * 0.12), { c = C3(250, 250, 250), m = M.SmoothPlastic, t = 1 }))
	end
	local cooking = false
	C:toggle(C:box("CookerButton", V3(0.14, 0.05, 0.02), CF(cx, y + h * 0.35, pz + 0.025) * ANG(math.rad(-12), 0, 0), lk(220, 60, 50)), {
		object = "전기밥솥",
		onText = "취사 취소",
		offText = "취사 시작",
		state = false,
		on = function(on: boolean)
			cooking = on
			lbl.Text = if on then "백미 취사 중 · 32분" else "백미 · 보온 08"
			if not on then
				setVis(steam, 1)
			end
		end,
	})
	local t0 = 0
	Interact.anim(C.K, function(t: number)
		if not cooking then
			return
		end
		t0 = t
		for i, s in steam do
			if s.Parent then
				local ph = (t * 0.6 + i / 3) % 1
				s.Transparency = 0.55 + ph * 0.4
			end
		end
	end)
	local _ = t0
end

-- 전기포트 (맵 Kettle 자리)
local function kettle(C: any, mn: Vector3, mx: Vector3, ti: number)
	local cx, cz = (mn.X + mx.X) / 2, (mn.Z + mx.Z) / 2
	local y = mn.Y
	local d = math.min(mx.X - mn.X, mx.Z - mn.Z)
	local body = if ti >= 4 then lk(236, 234, 228, M.SmoothPlastic, { r = 0.05 }) elseif ti == 3 then lk(40, 40, 42, M.Metal) else LK.steel
	C:disc("KettleBase", d + 0.04, 0.07, CF(cx, y + 0.035, cz), LK.black)
	C:vcyl("KettleBody", 0.5, d * 0.9, CF(cx, y + 0.07 + 0.25, cz), body)
	C:ell("KettleTop", V3(d * 0.9, 0.16, d * 0.9), CF(cx, y + 0.57, cz), body)
	C:vcyl("KettleLidKnob", 0.05, 0.12, CF(cx, y + 0.66, cz), LK.black)
	C:bar("KettleHandle", V3(cx, y + 0.62, cz - d * 0.42), V3(cx, y + 0.2, cz - d * 0.52), 0.07, 0.1, LK.black)
	C:wedge("KettleSpout", V3(0.12, 0.14, 0.16), CF(cx, y + 0.55, cz + d * 0.48) * ANG(0, PI, 0), body)
	C:box("KettleWindow", V3(0.06, 0.32, 0.02), CF(cx + d * 0.32, y + 0.32, cz + d * 0.3) * ANG(0, math.rad(45), 0), LK.glassSmoke)
end

-- 드럼세탁기 (싱크대 하부 빌트인, 맵 Washer 자리) + 상호작용 (세탁 시작 → 드럼 회전)
local function washer(C: any, mn: Vector3, mx: Vector3, zf: number, ti: number)
	local w, h = mx.X - mn.X, mx.Y - mn.Y
	local cx = (mn.X + mx.X) / 2
	local body = LK.white
	C:box("WasherBody", V3(w - 0.04, h - 0.02, zf - mn.Z - 0.04), CF(cx, mn.Y + h / 2, mn.Z + (zf - mn.Z) / 2 - 0.02), lk(232, 232, 228))
	C:box("WasherFront", V3(w - 0.04, h - 0.04, 0.05), CF(cx, mn.Y + h / 2, zf), body)
	local dr = math.min(w, h) * 0.66
	local dy = mn.Y + h * 0.43
	local dz = zf + 0.03
	C:ring("WasherDoorRing", CF(cx, dy, dz + 0.04), dr / 2, 0.14, 14, LK.chrome)
	C:disc("WasherDoorGlass", dr - 0.1, 0.04, CF(cx, dy, dz + 0.05) * ANG(PI / 2, 0, 0), lk(60, 70, 80, M.Glass, { t = 0.35, r = 0.2 }))
	C:disc("WasherDrum", dr - 0.14, 0.02, CF(cx, dy, dz - 0.06) * ANG(PI / 2, 0, 0), LK.steel)
	-- 드럼 안 빨래 (돌아감)
	local laundry: { BasePart } = {}
	local lcols = { C3(80, 110, 170), C3(240, 240, 236), C3(200, 80, 90), C3(90, 90, 96) }
	for i = 1, 4 do
		local a = i * PI / 2
		table.insert(laundry, C:ell("WasherLaundry", V3(0.36, 0.3, 0.05), CF(cx + math.cos(a) * dr * 0.2, dy + math.sin(a) * dr * 0.2 - 0.05, dz - 0.03), col(lcols[i], M.Fabric)))
	end
	C:box("WasherDoorHandle", V3(0.06, 0.32, 0.06), CF(cx + dr / 2 - 0.04, dy, dz + 0.1), LK.chrome)
	-- 위 조작부: 세제 서랍 · 다이얼 · 표시창
	local py = mx.Y - 0.2
	C:box("WasherDetergent", V3(w * 0.32, 0.26, 0.03), CF(mn.X + w * 0.2, py, zf + 0.04), lk(240, 240, 236))
	C:box("WasherDetergentPull", V3(w * 0.2, 0.04, 0.03), CF(mn.X + w * 0.2, py - 0.08, zf + 0.06), LK.absGrey)
	C:disc("WasherDial", 0.26, 0.06, CF(cx + w * 0.05, py, zf + 0.05) * ANG(PI / 2, 0, 0), LK.chrome)
	local _, disp = C:label("WasherDisplay", w * 0.24, 0.14, CF(mn.X + w * 0.78, py, zf + 0.03), "표준 0:39", C3(255, 190, 90), C3(20, 18, 16), { glow = 1 })
	local btn = C:box("WasherStart", V3(0.14, 0.1, 0.03), CF(mn.X + w * 0.78, py - 0.16, zf + 0.04), lk(80, 80, 84))
	local running = false
	C:toggle(btn, {
		object = "드럼세탁기",
		onText = "세탁 멈춤",
		offText = "세탁 시작",
		state = false,
		on = function(on: boolean)
			running = on
			disp.Text = if on then "세탁 중 0:38" else "표준 0:39"
		end,
	})
	local base = {}
	for _, p in laundry do
		table.insert(base, p.CFrame)
	end
	local center = C:world(V3(cx, dy, dz))
	local axis = C:wvec(V3(0, 0, 1))
	local ang = 0
	Interact.anim(C.K, function(_t: number, dt: number)
		if not running then
			return
		end
		ang += dt * 5
		local rot = CFrame.new(center) * CFrame.fromAxisAngle(axis, ang) * CFrame.new(-center)
		for i, p in laundry do
			if p.Parent then
				p.CFrame = rot * base[i]
			end
		end
	end)
end

-- 타일 줄눈 (면 위 격자): dcf = 면 가운데 (+Z = 보는 쪽), w x h, 타일 tw x th, 색
local function groutGrid(C: any, dcf: CFrame, w: number, h: number, tw: number, th: number, c: Color3, stagger: boolean?)
	local look = col(c, M.SmoothPlastic)
	local ny = math.floor(h / th + 0.001)
	for j = 1, ny do
		local y = -h / 2 + j * th
		if y < h / 2 - 0.05 then
			C:plate("Grout", w, 0.025, 0.006, dcf * CF(0, y, 0), look)
		end
	end
	local nx = math.floor(w / tw + 0.001)
	if stagger then
		for j = 0, ny do
			local y0 = -h / 2 + j * th
			local y1 = math.min(h / 2, y0 + th)
			if y1 - y0 > 0.05 then
				local off = if j % 2 == 1 then tw / 2 else 0
				for i = 0, nx do
					local x = -w / 2 + off + i * tw
					if x > -w / 2 + 0.05 and x < w / 2 - 0.05 then
						C:plate("Grout", 0.025, y1 - y0, 0.006, dcf * CF(x, (y0 + y1) / 2, 0), look)
					end
				end
			end
		end
	else
		for i = 1, nx do
			local x = -w / 2 + i * tw
			if x < w / 2 - 0.05 then
				C:plate("Grout", 0.025, h, 0.006, dcf * CF(x, 0, 0), look)
			end
		end
	end
end

-- 조리대 위 살림 (pcf = 상판 윗면, +Z = 사람 쪽) --------------------------------------------------------------------
local function dishRack(C: any, pcf: CFrame, w: number, d: number, tiers: number)
	local wire = if C.ti >= 4 then LK.steel else lk(236, 236, 232, M.Plastic)
	C:box("RackTray", V3(w, 0.06, d), pcf * CF(0, 0.03, 0), lk(220, 224, 226, M.Plastic, { t = 0.2 }))
	C:box("RackSpout", V3(0.2, 0.03, 0.24), pcf * CF(w / 2 - 0.2, 0.03, d / 2 + 0.08), lk(220, 224, 226, M.Plastic))
	local h = 0.85
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			C:box("RackPost", V3(0.04, h, 0.04), pcf * CF(sx * (w / 2 - 0.04), 0.06 + h / 2, sz * (d / 2 - 0.04)), wire)
		end
		C:box("RackRail", V3(0.035, 0.035, d - 0.06), pcf * CF(sx * (w / 2 - 0.04), 0.06 + h, 0), wire)
		C:box("RackRail", V3(0.035, 0.035, d - 0.06), pcf * CF(sx * (w / 2 - 0.04), 0.3, 0), wire)
	end
	for _, sz in { -1, 1 } do
		C:box("RackRail", V3(w - 0.06, 0.035, 0.035), pcf * CF(0, 0.06 + h, sz * (d / 2 - 0.04)), wire)
	end
	-- 세운 접시 (빗살 사이)
	local np = math.max(3, math.floor((w * 0.55) / 0.12))
	for i = 0, np - 1 do
		local x = -w / 2 + 0.2 + i * 0.12
		C:disc("RackPlate", if i % 3 == 0 then 0.78 else 0.66, 0.03, pcf * CF(x, 0.46, -d * 0.08) * ANG(0, 0, PI / 2) * ANG(0, 0, 0), LK.ceramic)
	end
	-- 엎어 둔 공기 · 컵 + 수저 꽂이
	C:vcyl("RackBowl", 0.24, 0.44, pcf * CF(w / 2 - 0.35, 0.22, d * 0.18), lk(242, 238, 230))
	C:vcyl("RackCup", 0.36, 0.28, pcf * CF(w / 2 - 0.3, 0.24, -d * 0.25), col(C3(120, 170, 210)))
	C:vcyl("RackCutleryCup", 0.4, 0.26, pcf * CF(w / 2 - 0.15, 0.26, d * 0.42), lk(236, 236, 232, M.Plastic, { t = 0.3 }))
	for i = 0, 3 do
		C:box("RackChopstick", V3(0.025, 0.7, 0.025), pcf * CF(w / 2 - 0.2 + (i % 2) * 0.06, 0.55, d * 0.4 + i * 0.02) * ANG(0.06 * i, 0, 0.05), LK.steel)
	end
	if tiers > 1 then
		C:box("RackShelf", V3(w - 0.06, 0.03, d - 0.06), pcf * CF(0, 0.06 + h + 0.55, 0), wire)
		for _, sx in { -1, 1 } do
			C:box("RackPost", V3(0.04, 0.55, 0.04), pcf * CF(sx * (w / 2 - 0.04), 0.06 + h + 0.28, -(d / 2 - 0.04)), wire)
		end
		for i = 0, 2 do
			C:vcyl("RackShelfCup", 0.3, 0.26, pcf * CF(-w / 2 + 0.3 + i * 0.34, 0.06 + h + 0.72, 0), col(({ C3(250, 250, 248), C3(240, 210, 150), C3(180, 200, 190) })[i + 1]))
		end
	end
end

local function sinkSet(C: any, pcf: CFrame, gloves: boolean)
	-- 주방세제 + 수세미 거치대
	bottle(C, pcf * CF(-0.12, 0, 0), 0.75, 0.26, lk(120, 200, 80, M.Plastic, { t = 0.15 }), lk(240, 240, 240, M.Plastic), C3(250, 250, 240), "주방세제")
	C:box("SpongeHolder", V3(0.36, 0.1, 0.26), pcf * CF(0.24, 0.05, 0.05), lk(236, 236, 232, M.Plastic))
	C:box("Sponge", V3(0.3, 0.12, 0.2), pcf * CF(0.24, 0.16, 0.05), lk(250, 210, 60, M.Fabric))
	C:box("SpongeScrub", V3(0.3, 0.04, 0.2), pcf * CF(0.24, 0.24, 0.05), lk(60, 150, 70, M.Fabric))
	if gloves then
		-- 고무장갑 (분홍), 개수대 가에 걸쳐 둠
		C:ell("RubberGlove", V3(0.32, 0.06, 0.62), pcf * CF(0.12, 0.04, 0.42) * ANG(0, 0.4, 0.1), lk(236, 120, 150, M.Rubber))
		C:ell("RubberGloveCuff", V3(0.34, 0.07, 0.24), pcf * CF(-0.02, 0.05, 0.6) * ANG(0, 0.4, 0), lk(240, 140, 166, M.Rubber))
	end
end

local function utensilHolder(C: any, pcf: CFrame)
	C:vcyl("UtensilCrock", 0.55, 0.42, pcf * CF(0, 0.275, 0), if C.ti >= 4 then lk(236, 232, 224, M.SmoothPlastic, { r = 0.04 }) else LK.steel)
	local tools = {
		{ 0.08, 0.05, 1.2, 0.18, LK.black }, -- 뒤집개
		{ -0.08, 0.06, 1.25, 0.24, LK.steel }, -- 국자
		{ 0.02, -0.08, 1.1, 0.12, LK.wood }, -- 나무 주걱
		{ -0.05, -0.02, 1.15, 0.1, LK.black }, -- 집게
	}
	for i, t in tools do
		local top = pcf * CF(t[1] * 1.4, t[3], t[2] * 1.4)
		C:seg("UtensilStem", (pcf * CF(t[1], 0.2, t[2])).Position, top.Position, 0.04, t[5])
		if i == 2 then
			C:ell("LadleCup", V3(0.24, 0.12, 0.24), top * CF(0, 0.04, 0), t[5])
		else
			C:box("UtensilHead", V3(t[4], 0.22, 0.03), top * CF(0, 0.08, 0) * ANG(0, i * 0.7, 0), t[5])
		end
	end
end

-- 양념 (간장 · 식용유 · 참기름 · 소금 · 고춧가루)
local function seasonings(C: any, pcf: CFrame, ti: number)
	if ti >= 4 then
		C:disc("SpiceTray", 1.0, 0.04, pcf * CF(0, 0.02, 0), lk(110, 80, 56, M.Wood))
	end
	bottle(C, pcf * CF(-0.3, 0.04, -0.12), 0.95, 0.24, lk(50, 26, 16, M.Glass, { t = 0.1 }), lk(200, 30, 30, M.Plastic), C3(250, 246, 236), "진간장")
	bottle(C, pcf * CF(0.0, 0.04, -0.16), 1.0, 0.26, lk(232, 200, 90, M.Glass, { t = 0.35 }), lk(240, 200, 40, M.Plastic), C3(250, 230, 120), "식용유")
	bottle(C, pcf * CF(0.28, 0.04, -0.1), 0.6, 0.18, lk(120, 70, 20, M.Glass, { t = 0.2 }), lk(30, 30, 30, M.Plastic), C3(240, 220, 160), "참기름")
	C:vcyl("SaltTub", 0.32, 0.3, pcf * CF(-0.18, 0.2, 0.18), lk(248, 248, 246, M.Plastic, { t = 0.2 }))
	C:vcyl("SaltLid", 0.05, 0.31, pcf * CF(-0.18, 0.385, 0.18), lk(60, 130, 200, M.Plastic))
	C:vcyl("ChiliJar", 0.34, 0.3, pcf * CF(0.18, 0.21, 0.2), lk(200, 50, 30, M.Plastic, { t = 0.1 }))
	C:vcyl("ChiliLid", 0.05, 0.31, pcf * CF(0.18, 0.405, 0.2), lk(40, 120, 60, M.Plastic))
end

local function cuttingBoard(C: any, pcf: CFrame, ti: number)
	local lookB = if ti >= 4 then lk(170, 126, 84, M.Wood) else lk(244, 244, 240, M.Plastic)
	C:box("CuttingBoard", V3(1.1, 0.8, 0.06), pcf * CF(0, 0.4, 0.12) * ANG(math.rad(-12), 0, 0), lookB)
	if ti >= 3 then
		C:box("CuttingBoard", V3(0.9, 0.62, 0.05), pcf * CF(0.12, 0.31, 0.2) * ANG(math.rad(-10), 0, 0), lk(90, 140, 110, M.Plastic))
	end
end

local function spoonHolder(C: any, pcf: CFrame)
	C:vcyl("SpoonHolder", 0.5, 0.34, pcf * CF(0, 0.25, 0), LK.steel)
	for i = 0, 3 do
		local a = i * PI / 2
		C:seg("Spoon", (pcf * CF(math.cos(a) * 0.06, 0.3, math.sin(a) * 0.06)).Position, (pcf * CF(math.cos(a) * 0.1, 0.78, math.sin(a) * 0.1)).Position, 0.03, LK.steel)
		C:ell("SpoonBowl", V3(0.09, 0.14, 0.03), pcf * CF(math.cos(a) * 0.1, 0.84, math.sin(a) * 0.1), LK.steel)
	end
	for i = 0, 5 do
		local a = i * PI / 3 + 0.3
		C:seg("Chopstick", (pcf * CF(math.cos(a) * 0.08, 0.3, math.sin(a) * 0.08)).Position, (pcf * CF(math.cos(a) * 0.12, 0.88, math.sin(a) * 0.12)).Position, 0.022, LK.steel)
	end
end

local function paperTowel(C: any, pcf: CFrame)
	C:disc("TowelStandBase", 0.42, 0.04, pcf * CF(0, 0.02, 0), LK.steelDark)
	C:vcyl("TowelStandPole", 1.0, 0.05, pcf * CF(0, 0.5, 0), LK.steel)
	C:vcyl("PaperTowelRoll", 0.9, 0.38, pcf * CF(0, 0.5, 0), LK.paper)
	C:box("PaperTowelSheet", V3(0.3, 0.3, 0.01), pcf * CF(0, 0.3, 0.2), LK.paper)
end

-- 정수기 (카운터탑 직수형)
local function purifier(C: any, pcf: CFrame, ti: number)
	local body = if ti >= 5 then lk(60, 62, 66, M.Metal) else LK.white
	C:slab("PurifierBody", 0.62, 1.0, 1.55, 0.1, pcf * CF(0, 0.775, -0.1), body)
	C:box("PurifierNozzleArm", V3(0.18, 0.12, 0.42), pcf * CF(0, 1.1, 0.5), body)
	C:vcyl("PurifierNozzle", 0.08, 0.06, pcf * CF(0, 1.0, 0.62), LK.chrome)
	C:box("PurifierTray", V3(0.5, 0.04, 0.32), pcf * CF(0, 0.05, 0.52), LK.absGrey)
	C:box("PurifierPanel", V3(0.48, 0.3, 0.02), pcf * CF(0, 1.34, 0.41), LK.glassBlack)
	if C.hi then
		C:label("PurifierLabel", 0.44, 0.24, pcf * CF(0, 1.34, 0.42), "냉수 · 정수 · 온수", C3(130, 210, 255), nil, { glow = 1, font = FONT_M })
	end
end

local function airFryer(C: any, pcf: CFrame, ti: number)
	local body = if ti >= 4 then LK.white else LK.black
	C:rbox("FryerBody", V3(0.95, 1.05, 0.95), 0.18, pcf * CF(0, 0.525, 0), body)
	C:box("FryerBasketFront", V3(0.78, 0.48, 0.04), pcf * CF(0, 0.32, 0.48), LK.black)
	C:box("FryerHandle", V3(0.14, 0.12, 0.26), pcf * CF(0, 0.42, 0.62), LK.black)
	C:box("FryerDisplay", V3(0.5, 0.2, 0.02), pcf * CF(0, 0.85, 0.47) * ANG(math.rad(-15), 0, 0), LK.glassBlack)
	if C.hi then
		C:label("FryerDisplayText", 0.46, 0.16, pcf * CF(0, 0.85, 0.485) * ANG(math.rad(-15), 0, 0), "180°  15:00", C3(255, 160, 70), nil, { glow = 1 })
	end
end

local function capsuleMachine(C: any, pcf: CFrame, ti: number)
	local body = if ti >= 5 then LK.chrome else lk(160, 40, 44, M.SmoothPlastic, { r = 0.08 })
	C:rbox("CoffeeBody", V3(0.55, 1.05, 1.0), 0.1, pcf * CF(0, 0.6, -0.1), body)
	C:box("CoffeeHead", V3(0.5, 0.25, 0.4), pcf * CF(0, 0.95, 0.45), body)
	C:box("CoffeeDripTray", V3(0.45, 0.06, 0.4), pcf * CF(0, 0.07, 0.4), LK.steelDark)
	C:vcyl("CoffeeCup", 0.28, 0.26, pcf * CF(0, 0.24, 0.42), LK.ceramic)
	C:box("CoffeeLever", V3(0.4, 0.05, 0.22), pcf * CF(0, 1.14, 0.42) * ANG(math.rad(10), 0, 0), LK.steelDark)
	C:box("CoffeeTank", V3(0.5, 0.8, 0.25), pcf * CF(0, 0.55, -0.68), lk(220, 236, 240, M.Glass, { t = 0.45 }))
end

local function espressoMachine(C: any, pcf: CFrame)
	C:box("EspressoBody", V3(1.2, 1.25, 1.05), pcf * CF(0, 0.66, -0.05), LK.chrome)
	C:box("EspressoTop", V3(1.2, 0.05, 1.05), pcf * CF(0, 1.31, -0.05), LK.steelDark)
	for i = 0, 2 do
		C:vcyl("EspressoCupWarm", 0.24, 0.24, pcf * CF(-0.35 + i * 0.35, 1.45, -0.1), LK.ceramic)
	end
	C:box("EspressoGroupHead", V3(0.3, 0.18, 0.2), pcf * CF(-0.1, 0.95, 0.52), LK.chrome)
	C:bar("EspressoPortafilter", V3(-0.1, 0.85, 0.6), V3(-0.1, 0.8, 1.05), 0.08, 0.08, LK.black)
	C:box("EspressoGauge", V3(0.2, 0.2, 0.02), pcf * CF(0.32, 1.0, 0.48), LK.white)
	C:seg("EspressoWand", (pcf * CF(0.45, 0.95, 0.5)).Position, (pcf * CF(0.5, 0.45, 0.65)).Position, 0.04, LK.chrome)
	C:box("EspressoTray", V3(1.0, 0.06, 0.4), pcf * CF(0, 0.2, 0.52), LK.steelDark)
	C:vcyl("EspressoCup", 0.22, 0.22, pcf * CF(-0.1, 0.34, 0.6), LK.ceramic)
end

-- 과일 그릇 (사과 · 귤 · 바나나)
local function fruitBowl(C: any, pcf: CFrame, ti: number)
	local bowlL = if ti >= 5 then lk(30, 30, 32, M.Marble) else lk(236, 230, 218, M.SmoothPlastic)
	C:vcyl("FruitBowlFoot", 0.08, 0.5, pcf * CF(0, 0.04, 0), bowlL)
	C:ell("FruitBowl", V3(1.2, 0.36, 1.2), pcf * CF(0, 0.2, 0), bowlL)
	local fr = { { -0.2, 0.42, 0.1, 0.32, C3(200, 40, 40) }, { 0.18, 0.42, -0.1, 0.3, C3(210, 60, 40) }, { 0.0, 0.46, 0.22, 0.26, C3(240, 140, 30) }, { 0.25, 0.44, 0.2, 0.26, C3(244, 150, 30) }, { -0.05, 0.62, -0.02, 0.3, C3(196, 40, 46) } }
	for _, f in fr do
		C:ball("Fruit", f[4], pcf * CF(f[1], f[2], f[3]), col(f[5], M.SmoothPlastic, { r = 0.05 }))
	end
	for i = 0, 2 do
		C:ell("Banana", V3(0.16, 0.12, 0.62), pcf * CF(-0.12 + i * 0.1, 0.55 + i * 0.03, -0.18) * ANG(0.3, 0.5 + i * 0.15, 0.5), lk(240, 210, 70))
	end
end

-- 꽃병 (아일랜드 · 콘솔)
local function vaseFlowers(C: any, pcf: CFrame, h: number, glassy: boolean)
	C:vcyl("Vase", h * 0.45, 0.36, pcf * CF(0, h * 0.225, 0), if glassy then lk(214, 232, 236, M.Glass, { t = 0.4 }) else lk(232, 228, 220, M.SmoothPlastic))
	for i = 0, 6 do
		local a = i * 2 * PI / 7
		local tip = pcf * CF(math.cos(a) * 0.22, h * (0.85 + (i % 3) * 0.08), math.sin(a) * 0.22)
		C:seg("FlowerStem", (pcf * CF(0, h * 0.4, 0)).Position, tip.Position, 0.03, lk(80, 120, 60, M.Grass))
		C:ball("FlowerHead", 0.2, tip, col(({ C3(250, 250, 246), C3(240, 200, 210), C3(250, 236, 200) })[(i % 3) + 1], M.Fabric))
	end
	C:ell("FlowerLeaf", V3(0.4, 0.05, 0.16), pcf * CF(0.1, h * 0.55, 0.1) * ANG(0.2, 0.5, 0.4), lk(80, 120, 60, M.Grass))
end

local function knifeBlock(C: any, pcf: CFrame)
	C:box("KnifeBlock", V3(0.4, 0.62, 0.55), pcf * CF(0, 0.3, 0) * ANG(math.rad(-12), 0, 0), lk(60, 44, 34, M.Wood))
	for i = 0, 3 do
		C:box("KnifeHandle", V3(0.07, 0.3, 0.1), pcf * CF(-0.12 + i * 0.08, 0.72, -0.08 + i * 0.03) * ANG(math.rad(-12), 0, 0), LK.black)
	end
end

local function ramenStack(C: any, pcf: CFrame)
	-- 라면 묶음 (5입) + 즉석밥 3개
	C:box("RamenPack", V3(0.95, 0.42, 0.62), pcf * CF(-0.32, 0.21, 0), lk(196, 30, 34, M.SmoothPlastic, { r = 0.06 }))
	C:box("RamenPack", V3(0.95, 0.42, 0.62), pcf * CF(-0.32, 0.63, 0), lk(204, 36, 36, M.SmoothPlastic, { r = 0.06 }))
	if C.hi then
		C:label("RamenLabel", 0.8, 0.3, CF(0, 0, 0) * pcf * CF(-0.32, 0.63, 0.315), "얼큰라면 5입", C3(255, 240, 200), nil, { font = FONT_B })
	end
	for i = 0, 2 do
		C:vcyl("InstantRice", 0.18, 0.5, pcf * CF(0.38, 0.09 + i * 0.19, 0.05), lk(250, 250, 248, M.Plastic))
		C:disc("InstantRiceLid", 0.5, 0.01, pcf * CF(0.38, 0.185 + i * 0.19, 0.05), lk(240, 120, 40))
	end
end

-- 냄비 · 프라이팬 (인덕션 위)
local function potOnHob(C: any, pcf: CFrame, kind: string)
	if kind == "yangeun" then
		-- 양은 냄비 (노란 라면 냄비) + 뚜껑
		C:vcyl("YangeunPot", 0.42, 0.72, pcf * CF(0, 0.21, 0), lk(232, 190, 90, M.Metal, { r = 0.1 }))
		C:disc("YangeunLid", 0.74, 0.03, pcf * CF(0, 0.43, 0), lk(236, 196, 100, M.Metal, { r = 0.1 }))
		C:vcyl("YangeunKnob", 0.06, 0.12, pcf * CF(0, 0.47, 0), LK.black)
		for _, s in { -1, 1 } do
			C:box("YangeunHandle", V3(0.16, 0.04, 0.14), pcf * CF(s * 0.43, 0.38, 0), lk(232, 190, 90, M.Metal))
		end
	elseif kind == "pan" then
		C:vcyl("FryPan", 0.14, 0.9, pcf * CF(0, 0.07, 0), LK.black)
		C:disc("FryPanInside", 0.82, 0.01, pcf * CF(0, 0.135, 0), lk(50, 50, 52))
		C:bar("FryPanHandle", (pcf * CF(0, 0.12, 0.42)).Position, (pcf * CF(0, 0.2, 1.15)).Position, 0.08, 0.06, LK.black)
	elseif kind == "dutch" then
		C:vcyl("DutchOven", 0.5, 0.85, pcf * CF(0, 0.25, 0), lk(224, 96, 40, M.SmoothPlastic, { r = 0.1 }))
		C:ell("DutchLid", V3(0.86, 0.16, 0.86), pcf * CF(0, 0.5, 0), lk(224, 96, 40, M.SmoothPlastic, { r = 0.1 }))
		C:vcyl("DutchKnob", 0.08, 0.16, pcf * CF(0, 0.6, 0), LK.steel)
		for _, s in { -1, 1 } do
			C:box("DutchHandle", V3(0.12, 0.08, 0.24), pcf * CF(s * 0.48, 0.4, 0), lk(224, 96, 40))
		end
	else
		C:vcyl("StockPot", 0.5, 0.8, pcf * CF(0, 0.25, 0), LK.steel)
		C:disc("StockPotLid", 0.82, 0.03, pcf * CF(0, 0.51, 0), lk(214, 232, 236, M.Glass, { t = 0.4 }))
		C:vcyl("StockPotKnob", 0.06, 0.12, pcf * CF(0, 0.55, 0), LK.black)
		for _, s in { -1, 1 } do
			C:box("StockPotHandle", V3(0.14, 0.05, 0.2), pcf * CF(s * 0.46, 0.42, 0), LK.steel)
		end
	end
end

-- 분리수거함 (3 단) + 음식물 쓰레기통 (바닥, pcf +Z = 앞)
local function recycleBins(C: any, pcf: CFrame, foodBin: boolean)
	local labels = { { "플라스틱", C3(60, 140, 220) }, { "캔 · 병", C3(240, 170, 40) }, { "종이", C3(70, 170, 90) } }
	for i, lb in labels do
		local y = (i - 1) * 0.82
		C:box("RecycleBin", V3(1.25, 0.78, 1.05), pcf * CF(0, y + 0.39, 0), lk(244, 244, 240, M.Plastic))
		C:box("RecycleBinFlap", V3(1.1, 0.3, 0.04), pcf * CF(0, y + 0.55, 0.535), col(lb[2], M.Plastic))
		C:label("RecycleLabel", 0.8, 0.2, pcf * CF(0, y + 0.55, 0.56), lb[1], C3(255, 255, 255), nil)
	end
	if foodBin then
		C:vcyl("FoodBin", 0.85, 0.6, pcf * CF(1.0, 0.425, 0.1), lk(240, 240, 236, M.Plastic))
		C:vcyl("FoodBinLid", 0.08, 0.62, pcf * CF(1.0, 0.89, 0.1), lk(110, 170, 70, M.Plastic))
		C:box("FoodBinHandle", V3(0.3, 0.05, 0.06), pcf * CF(1.0, 0.95, 0.1), lk(90, 140, 60, M.Plastic))
		if C.hi then
			C:label("FoodBinLabel", 0.42, 0.14, pcf * CF(1.0, 0.6, 0.405), "음식물", C3(70, 120, 50), C3(250, 250, 246))
		end
	end
end

-- 조리대 위 빈 자리 찾기: 후보 x 목록, 폭 w · 깊이 d · 높이 h, z 앞뒤 (back = 벽에 붙임)
local function topSpot(C: any, info: any, w: number, d: number, h: number, targets: { number }, back: boolean): CFrame?
	local ytop = info.ytop
	local z = if back then 0.1 + d / 2 else math.min(info.zt - d / 2 - 0.08, 0.1 + d / 2 + 0.25)
	local lo, hi = info.topA + w / 2 + 0.05, info.topB - w / 2 - 0.05
	if hi < lo then
		return nil
	end
	local tries = {}
	for _, t in targets do
		for k = 0, 10 do
			for _, s in { 1, -1 } do
				table.insert(tries, math.clamp(t + s * k * 0.25, lo, hi))
			end
		end
	end
	local yclear = (info.upperY or (ytop + 3)) - ytop - 0.05
	if h > yclear and not back then
		return nil
	end
	for _, x in tries do
		local cf = CF(x, ytop + h / 2 + 0.01, z)
		local ok = true
		for _, b in info.busy do
			if x + w / 2 > b[1] and x - w / 2 < b[2] and z + d / 2 > (b[3] or -1) and z - d / 2 < (b[4] or 99) then
				ok = false
				break
			end
		end
		if ok and C:clear(cf, V3(w, h, d), "top") then
			C:reserve(cf, V3(w, h, d))
			table.insert(info.busy, { x - w / 2, x + w / 2, z - d / 2, z + d / 2 })
			return CF(x, ytop, z)
		end
	end
	return nil
end

-- 맵 파트가 어떤 모델 안에 있나
local function inModel(rec: any, names: { [string]: boolean }): boolean
	local a = rec.part.Parent
	for _ = 1, 4 do
		if not a then
			return false
		end
		if names[a.Name] then
			return true
		end
		a = a.Parent
	end
	return false
end

-- 물건 하나의 틀: body 가운데 바닥, +Z = front 쪽 (V 로컬 단위 벡터)
local function frontDir(body: any, front: any): Vector3
	local d = front.c - body.c
	if math.abs(d.X) > math.abs(d.Z) then
		return V3(if d.X >= 0 then 1 else -1, 0, 0)
	end
	return V3(0, 0, if d.Z >= 0 then 1 else -1)
end
local function objCtx(K: any, V: any, body: any, n: Vector3, H: number, seed: string): any
	local p = V3(body.c.X, 0, body.c.Z)
	local cf = CFrame.fromMatrix(p, V3(0, 1, 0):Cross(n), V3(0, 1, 0), n)
	local sx = math.abs(n.Z) * body.size.X + math.abs(n.X) * body.size.Z
	local sz = math.abs(n.X) * body.size.X + math.abs(n.Z) * body.size.Z
	return newCtx(K, V, cf, -sx / 2, sx / 2, -sz / 2, sz / 2, H, seed)
end
-- body 와 겹치는 (앞쪽 포함) 이름 목록의 맵 파트
local function near(V: any, body: any, names: { string }, pad: number): { any }
	local out = {}
	local mn, mx = body.min - V3(pad, 0.2, pad), body.max + V3(pad, 0.2, pad)
	for _, n in names do
		for _, r in V.byName[n] or {} do
			if r.part.Transparency < 0.99 and r.c.X > mn.X and r.c.X < mx.X and r.c.Z > mn.Z and r.c.Z < mx.Z and r.c.Y > mn.Y and r.c.Y < mx.Y then
				table.insert(out, r)
			end
		end
	end
	return out
end

local function unionBB(C: any, list: { any }): (Vector3?, Vector3?)
	local a, b = nil, nil
	for _, r in list do
		local mn, mx = C:bb(r)
		a = if a then a:Min(mn) else mn
		b = if b then b:Max(mx) else mx
	end
	return a, b
end

-- 냉장고 · 김치냉장고 (맵 FridgeBody 마다)
local function kitchenFridges(K: any, V: any, H: number)
	local bodies = {}
	for _, r in V.byName.FridgeBody or {} do
		if r.part.Transparency < 0.99 and not K.hidden[r.part] then
			table.insert(bodies, r)
		end
	end
	table.sort(bodies, function(a, b)
		return a.size.X * a.size.Z > b.size.X * b.size.Z
	end)
	for i, body in bodies do
		local doors = near(V, body, { "FridgeDoor" }, 0.35)
		local door = doors[1]
		if not door then
			continue
		end
		-- body 와 옆으로 겹치는 문만 (양문형 · 김치냉장고가 붙어 있음)
		local best, bd = door, math.huge
		for _, d in doors do
			local dd = (V3(d.c.X, 0, d.c.Z) - V3(body.c.X, 0, body.c.Z)).Magnitude
			if dd < bd then
				best, bd = d, dd
			end
		end
		door = best
		local n = frontDir(body, door)
		local C = objCtx(K, V, body, n, H, "fridge" .. i)
		local bmn, bmx = C:bb(body)
		local dmn, dmx = C:bb(door)
		local mn = V3(math.min(bmn.X, dmn.X), bmn.Y, bmn.Z)
		local mx = V3(math.max(bmx.X, dmx.X), math.max(bmx.Y, dmx.Y), bmx.Z)
		local parts = { body, door }
		for _, r in near(V, body, { "Handle", "DoorGap", "Display" }, 0.4) do
			local a, b = C:bb(r)
			if a.X >= mn.X - 0.1 and b.X <= mx.X + 0.1 and a.Z > bmx.Z - 0.1 then
				table.insert(parts, r)
			end
		end
		local w = mx.X - mn.X
		local kind = "single"
		local base = body.part.Color
		if C.ti >= 5 then
			kind = "column"
		elseif w >= 2.8 then
			kind = "sbs"
			base = C3(214, 212, 208)
		elseif #bodies >= 2 and C.ti >= 4 then
			kind = "kimchi"
			base = door.part.Color
		end
		C:hideAll(parts)
		local fr = fridgeReskin(C, mn, mx, bmx.Z, kind, base, { handleL = LK.bronze })
		C:reserve(CF((mn.X + mx.X) / 2, (mn.Y + mx.Y) / 2, (mn.Z + bmx.Z + 0.2) / 2), mx - mn + V3(0, 0, 0.2))
		if i == 1 then
			fridgeDeco(C, fr, C.ti)
		end
	end
	-- 냉장고 위 수납장 (아파트)
	for _, r in V.byName.FridgeTopCabinet or {} do
		if r.part.Transparency < 0.99 and not K.hidden[r.part] then
			local fb = bodies[1]
			local n = if fb then frontDir(fb, (near(V, fb, { "FridgeDoor" }, 0.35)[1] or fb)) else V3(0, 0, 1)
			local C = objCtx(K, V, r, n, H, "ftop")
			local mn, mx = C:bb(r)
			C:hide(r)
			local st = kitchenStyle(C.ti, r.part.Color, C3(230, 230, 226))
			C:box("FridgeTopCarcass", V3(mx.X - mn.X, mx.Y - mn.Y, mx.Z - mn.Z - 0.08), CF((mn.X + mx.X) / 2, (mn.Y + mx.Y) / 2, (mn.Z + mx.Z - 0.08) / 2), st.carcass)
			local nd = math.max(2, math.floor((mx.X - mn.X) / 1.5 + 0.5))
			for k = 1, nd do
				local a = mn.X + (mx.X - mn.X) * (k - 1) / nd
				local b = mn.X + (mx.X - mn.X) * k / nd
				cabinetFront(C, st, "FridgeTopDoor", a, b, mn.Y, mx.Y, mx.Z - 0.08, "bottom")
			end
		end
	end
end

-- 전자레인지 · 밥솥 · 포트 · 세탁기 (자기 앞 방향을 찾아서)
local function kitchenAppliances(K: any, V: any, H: number)
	for i, r in V.byName.Microwave or {} do
		if r.part.Transparency < 0.99 and not K.hidden[r.part] then
			local dr = near(V, r, { "MicrowaveDoor" }, 0.3)[1]
			local n = if dr then frontDir(r, dr) else V3(0, 0, 1)
			local C = objCtx(K, V, r, n, H, "mw" .. i)
			local mn, mx = C:bb(r)
			C:hide(r)
			if dr then
				C:hide(dr)
			end
			microwave(C, mn, mx, C.ti)
			C:reserve(CF((mn.X + mx.X) / 2, (mn.Y + mx.Y) / 2, (mn.Z + mx.Z) / 2 + 0.05), mx - mn + V3(0.05, 0, 0.15))
		end
	end
	for i, r in V.byName.RiceCooker or {} do
		if r.part.Transparency < 0.99 and not K.hidden[r.part] then
			local pn = near(V, r, { "CookerPanel" }, 0.3)[1]
			local n = if pn then frontDir(r, pn) else V3(0, 0, 1)
			local C = objCtx(K, V, r, n, H, "rc" .. i)
			local mn, mx = C:bb(r)
			C:hide(r)
			if pn then
				C:hide(pn)
			end
			riceCooker(C, mn, mx, C.ti)
			C:reserve(CF((mn.X + mx.X) / 2, (mn.Y + mx.Y) / 2, (mn.Z + mx.Z) / 2), mx - mn + V3(0.3, 0.3, 0.1))
		end
	end
	for i, r in V.byName.Kettle or {} do
		if r.part.Transparency < 0.99 and not K.hidden[r.part] then
			local bs = near(V, r, { "KettleBase" }, 0.2)[1]
			local C = objCtx(K, V, r, V3(0, 0, 1), H, "kt" .. i)
			local mn, mx = C:bb(r)
			if bs then
				local a = C:bb(bs)
				mn = V3(mn.X, a.Y, mn.Z)
				C:hide(bs)
			end
			C:hide(r)
			kettle(C, mn, mx, C.ti)
			C:reserve(CF((mn.X + mx.X) / 2, (mn.Y + mx.Y) / 2, (mn.Z + mx.Z) / 2), mx - mn + V3(0.2, 0.1, 0.2))
		end
	end
	for i, r in V.byName.Washer or {} do
		if r.part.Transparency < 0.99 and not K.hidden[r.part] then
			local rg = near(V, r, { "DoorRing", "ControlPanel" }, 0.3)
			local n = if rg[1] then frontDir(r, rg[1]) else V3(0, 0, 1)
			local C = objCtx(K, V, r, n, H, "wa" .. i)
			local mn, mx = C:bb(r)
			C:hide(r)
			for _, q in near(V, r, { "DoorRing", "ControlPanel", "DoorGlass" }, 0.3) do
				C:hide(q)
			end
			washer(C, mn, mx, mx.Z, C.ti)
		end
	end
	-- 펜트하우스 키 큰 장 (팬트리)
	for i, r in V.byName.TallColumn or {} do
		if r.part.Transparency < 0.99 and not K.hidden[r.part] then
			local top = V.byName.CounterTop and V.byName.CounterTop[1]
			local n = V3(0, 0, 1)
			if top then
				-- 조리대와 같은 방향 (벽 반대)
				local d = top.c - r.c
				n = if math.abs(top.size.X) >= math.abs(top.size.Z) then V3(0, 0, if r.c.Z > (V.z0 + V.z1) / 2 then -1 else 1) else V3(if r.c.X > (V.x0 + V.x1) / 2 then -1 else 1, 0, 0)
				local _ = d
			end
			local C = objCtx(K, V, r, n, H, "tc" .. i)
			local mn, mx = C:bb(r)
			C:hide(r)
			local st = kitchenStyle(C.ti, r.part.Color, C3(230, 230, 226))
			C:box("PantryCarcass", V3(mx.X - mn.X, mx.Y - mn.Y, mx.Z - mn.Z - 0.08), CF((mn.X + mx.X) / 2, (mn.Y + mx.Y) / 2, (mn.Z + mx.Z - 0.08) / 2), st.carcass)
			cabinetFront(C, st, "PantryDoor", mn.X, mx.X, mn.Y + 0.35, mx.Y, mx.Z - 0.08, "left")
		end
	end
end

-- 아일랜드: 작업 쪽 문짝 + 위 살림
local function kitchenIsland(K: any, V: any, H: number, runWallN: Vector3?, runWallPos: Vector3?)
	local top = nil
	for _, r in V.byName.IslandTop or {} do
		if r.part.Transparency < 0.99 then
			top = r
		end
	end
	if not top then
		return
	end
	local body = nil
	for _, r in V.byName.IslandBody or {} do
		if r.part.Transparency < 0.99 then
			body = r
		end
	end
	-- 작업 쪽 = 조리대 벽 쪽
	local n = V3(0, 0, 1)
	if runWallPos then
		local d = runWallPos - top.c
		n = if math.abs(d.X) > math.abs(d.Z) then V3(if d.X > 0 then 1 else -1, 0, 0) else V3(0, 0, if d.Z > 0 then 1 else -1)
	end
	local C = objCtx(K, V, top, n, H, "island")
	local tmn, tmx = C:bb(top)
	local ytop = tmx.Y
	if body then
		local bmn, bmx = C:bb(body)
		local st = kitchenStyle(C.ti, body.part.Color, top.part.Color)
		st.front = col(body.part.Color, if C.ti >= 5 then M.Wood else M.SmoothPlastic)
		-- 작업 쪽 면 (몸통 앞) 에 문짝 · 서랍
		local zf = bmx.Z
		local w = bmx.X - bmn.X
		local n2 = math.max(2, math.floor(w / 2.0 + 0.5))
		for k = 1, n2 do
			local a = bmn.X + w * (k - 1) / n2
			local b = bmn.X + w * k / n2
			if k % 2 == 1 then
				local hs = { bmn.Y + 0.02, bmn.Y + (bmx.Y - bmn.Y) * 0.4, bmn.Y + (bmx.Y - bmn.Y) * 0.72, bmx.Y - 0.02 }
				for j = 1, 3 do
					cabinetFront(C, st, "IslandDrawer", a, b, hs[j], hs[j + 1], zf, "drawer")
				end
			else
				cabinetFront(C, st, "IslandDoor", a, b, bmn.Y + 0.02, bmx.Y - 0.02, zf, "right")
			end
		end
		-- 반대쪽 (의자 쪽) 패널 줄눈
		for k = 1, 3 do
			C:box("IslandPanelSeam", V3(0.02, bmx.Y - bmn.Y - 0.1, 0.01), CF(bmn.X + w * k / 4, (bmn.Y + bmx.Y) / 2, bmn.Z - 0.005), lk(40, 40, 42))
		end
	end
	-- 위: 과일 그릇 · 꽃 · (펜트) 쟁반과 오일병
	local cx = (tmn.X + tmx.X) / 2
	local cz = (tmn.Z + tmx.Z) / 2
	local L = tmx.X - tmn.X
	local spots = { { cx - L * 0.22, cz }, { cx + L * 0.25, cz }, { cx + L * 0.02, cz + 0.2 } }
	local made = 0
	for i, s in spots do
		local cf = CF(s[1], ytop, s[2])
		if C:claim(cf * CF(0, 0.6, 0), V3(1.3, 1.2, 1.3), "top") then
			made += 1
			if i == 1 then
				fruitBowl(C, cf, C.ti)
			elseif i == 2 then
				vaseFlowers(C, cf, 1.5, C.ti >= 5)
			elseif C.ti >= 5 then
				C:slab("ServingTray", 1.0, 0.6, 0.04, 0.08, cf * CF(0, 0.02, 0), lk(40, 36, 32, M.Marble))
				bottle(C, cf * CF(-0.25, 0.04, 0), 1.0, 0.24, lk(60, 90, 40, M.Glass, { t = 0.2 }), LK.brass, C3(240, 230, 200), "OLIVE OIL")
				C:vcyl("PepperMill", 0.75, 0.2, cf * CF(0.1, 0.04 + 0.375, 0), lk(40, 30, 26, M.Wood))
				C:vcyl("SaltMill", 0.75, 0.2, cf * CF(0.35, 0.04 + 0.375, 0), lk(236, 232, 224, M.Wood))
			else
				-- 요리책 받침 + 열어 둔 책
				C:box("CookbookStand", V3(0.9, 0.06, 0.4), cf * CF(0, 0.03, 0), LK.wood)
				C:box("Cookbook", V3(0.9, 0.62, 0.06), cf * CF(0, 0.36, -0.05) * ANG(math.rad(-20), 0, 0), lk(240, 236, 226))
				C:box("CookbookCover", V3(0.92, 0.64, 0.03), cf * CF(0, 0.36, -0.1) * ANG(math.rad(-20), 0, 0), lk(150, 60, 50))
			end
		end
	end
	local _ = made
end

-- 조리대 한 줄 짓기
local RUN_NAMES = {
	"BaseCabinet", "ToeKick", "CounterTop", "DrawerSeam", "DoorSeam", "UpperCabinet", "HoodCabinet", "RangeHood", "Sink", "SinkBasin",
	"Faucet", "FaucetSpout", "InductionHob", "HobRing", "Backsplash",
}
local function kitchenRun(K: any, V: any, top: any, idx: number, H: number): any?
	local alongX = top.size.X >= top.size.Z
	local back = nil
	for _, b in V.byName.Backsplash or {} do
		if alongX and math.abs(b.c.X - top.c.X) < top.size.X / 2 and math.abs(b.c.Z - top.c.Z) < top.size.Z then
			back = b
		elseif not alongX and math.abs(b.c.Z - top.c.Z) < top.size.Z / 2 and math.abs(b.c.X - top.c.X) < top.size.X then
			back = b
		end
	end
	local n: Vector3
	local wallPos: number
	if alongX then
		local plus = if back then back.c.Z > top.c.Z else (V.z1 - top.max.Z) < (top.min.Z - V.z0)
		n = V3(0, 0, if plus then -1 else 1)
		wallPos = if plus then top.max.Z else top.min.Z
	else
		local plus = if back then back.c.X > top.c.X else (V.x1 - top.max.X) < (top.min.X - V.x0)
		n = V3(if plus then -1 else 1, 0, 0)
		wallPos = if plus then top.max.X else top.min.X
	end
	local origin = if alongX then V3(top.c.X, 0, wallPos) else V3(wallPos, 0, top.c.Z)
	local rf = CFrame.fromMatrix(origin, V3(0, 1, 0):Cross(n), V3(0, 1, 0), n)
	local L = if alongX then top.size.X else top.size.Z
	local depth = if alongX then top.size.Z else top.size.X
	local C = newCtx(K, V, rf, -L / 2, L / 2, 0, depth, H, "run" .. idx)
	local info: any = { tops = { top }, base = {}, upper = {}, busy = {}, rings = {}, hide = {} }
	local tmn, tmx = C:bb(top)
	info.ytop = tmx.Y
	info.zt = tmx.Z
	for _, nm in RUN_NAMES do
		for _, r in V.byName[nm] or {} do
			if r ~= top and r.part.Transparency < 0.99 and not K.hidden[r.part] and not inModel(r, { Island = true, Fridge = true, FridgeColumn = true }) then
				local mn, mx = C:bb(r)
				if mx.Z > -0.4 and mn.Z < info.zt + 0.3 and mx.X > tmn.X - 0.4 and mn.X < tmx.X + 0.4 and mn.Y < H then
					table.insert(info.hide, r)
					if nm == "BaseCabinet" then
						table.insert(info.base, r)
					elseif nm == "UpperCabinet" or nm == "HoodCabinet" then
						table.insert(info.upper, r)
					elseif nm == "Sink" then
						info.sinkBB = { mn, mx }
					elseif nm == "InductionHob" then
						info.hobBB = { mn, mx }
					elseif nm == "HobRing" then
						table.insert(info.rings, V3((mn.X + mx.X) / 2, 0, (mn.Z + mx.Z) / 2))
					elseif nm == "RangeHood" then
						info.hoodBB = { mn, mx }
					elseif nm == "Faucet" then
						info.faucetBB = { mn, mx }
					elseif nm == "ToeKick" then
						info.kickH = mx.Y
					elseif nm == "Backsplash" then
						info.splash = { mn, mx, r.part.Color }
					elseif nm == "CounterTop" then
						table.insert(info.tops, r)
					end
				end
			end
		end
	end
	if #info.base == 0 then
		return nil
	end
	-- 하부장 문짝 면 / 걸레받이 높이
	local zf = 0
	for _, r in info.base do
		local _, mx = C:bb(r)
		zf = math.max(zf, mx.Z)
	end
	info.zf = zf
	info.kickH = info.kickH or 0.35
	info.upperY = nil
	for _, r in info.upper do
		local mn = C:bb(r)
		info.upperY = math.min(info.upperY or 99, mn.Y)
	end
	local baseC = info.base[1].part.Color
	local st = kitchenStyle(C.ti, baseC, top.part.Color)
	-- 원본 숨기기 (UnderCabinetLED 는 테마 조명이라 그대로)
	C:hideAll(info.hide)
	C:hide(top)
	kitchenBase(C, st, info)
	kitchenSink(C, st, info)
	kitchenHob(C, st, info)
	kitchenHood(C, st, info)
	kitchenUpper(C, st, info)
	-- 타일 줄눈 (백스플래시)
	if info.splash and C.ti <= 4 then
		local mn, mx = info.splash[1], info.splash[2]
		local bc: Color3 = info.splash[3]
		local gc = shade(bc, if (bc.R + bc.G + bc.B) / 3 > 0.6 then -0.12 else 0.18)
		local tw, th = if C.ti == 2 then 1.43 else 2.14, if C.ti == 2 then 0.71 else 1.07
		groutGrid(C, CF((mn.X + mx.X) / 2, (mn.Y + mx.Y) / 2, mx.Z + 0.001), mx.X - mn.X, mx.Y - mn.Y, tw, th, gc, C.ti == 2)
	end
	-- 상부장 아래 조명 (밤에 조리대가 밝게)
	if info.upperY and C.ti >= 2 then
		local lp = C:box("UnderCabLight", V3(math.min(6, L * 0.6), 0.02, 0.1), CF(0, info.upperY - 0.04, 0.6), { c = C3(255, 240, 220), m = M.SmoothPlastic, t = 1 })
		C:light(lp, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 6, Brightness = 0.55, Angle = 120, Color = C3(255, 232, 205) })
	end
	-- 기존 가전 자리는 비워 둠 (조리대 살림이 겹치지 않게)
	for _, nm in { "RiceCooker", "Kettle", "KettleBase", "Microwave" } do
		for _, r in V.byName[nm] or {} do
			local mn, mx = C:bb(r)
			if mx.Z > -0.2 and mn.Z < info.zt + 0.2 and mx.X > info.topA - 0.2 and mn.X < info.topB + 0.2 and mn.Y < info.ytop + 0.4 and mx.Y > info.ytop - 0.1 then
				table.insert(info.busy, { mn.X - 0.12, mx.X + 0.12, mn.Z - 0.1, mx.Z + 0.1 })
			end
		end
	end
	if info.bowl then
		table.insert(info.busy, { info.bowl.a - 0.12, info.bowl.b + 0.12, -1, 99 })
	end
	if info.hobBB then
		table.insert(info.busy, { info.hobBB[1].X - 0.1, info.hobBB[2].X + 0.1, -1, 99 })
	end
	if info.faucet then
		table.insert(info.busy, { info.faucet.X - 0.3, info.faucet.X + 0.3, -1, 99 })
	end
	info.C, info.st = C, st
	info.n, info.wallPos = n, origin
	return info
end

-- 조리대 위 살림 배치 (등급별 이야기)
local function kitchenClutter(info: any)
	local C = info.C
	local ti = C.ti
	local sinkC = if info.bowl then (info.bowl.a + info.bowl.b) / 2 else 0
	local hobC = if info.hobBB then (info.hobBB[1].X + info.hobBB[2].X) / 2 else sinkC + 4
	local away = if hobC < sinkC then 1 else -1 -- 개수대에서 인덕션 반대쪽
	local sinkEdge = if info.bowl then (if away > 0 then info.bowl.b else info.bowl.a) else sinkC
	local sinkEdge2 = if info.bowl then (if away > 0 then info.bowl.a else info.bowl.b) else sinkC
	local hobEdge = if info.hobBB then (if hobC > sinkC then info.hobBB[2].X else info.hobBB[1].X) else hobC
	local hobOut = if hobC > sinkC then 1 else -1
	-- 냄비 (인덕션 위, 화구에)
	if info.rings and #info.rings > 0 then
		local r1 = info.rings[1]
		potOnHob(C, CF(r1.X, info.ytop + 0.04, r1.Z), if ti <= 3 then "yangeun" elseif ti >= 5 then "dutch" else "stock")
		if ti == 4 and #info.rings >= 2 then
			local r2 = info.rings[#info.rings]
			potOnHob(C, CF(r2.X, info.ytop + 0.04, r2.Z), "pan")
		end
	end
	-- 식기건조대 (식기세척기 집은 작게 / 펜트하우스 없음)
	if ti <= 4 and info.bowl then
		local w = if ti == 4 then 1.7 else 1.45
		local p = topSpot(C, info, w, 0.95, if ti == 4 then 1.5 else 0.95, { sinkEdge + away * (w / 2 + 0.15) }, true)
		if p then
			dishRack(C, p, w, 0.95, if ti == 4 then 2 else 1)
		end
	end
	-- 세제 · 수세미 · 고무장갑 (개수대 옆)
	if info.bowl then
		local p = topSpot(C, info, 0.75, 0.75, 0.8, { sinkEdge2 - away * 0.5 }, false)
		if p then
			sinkSet(C, p, ti <= 4)
		end
	end
	-- 조리도구 꽂이 · 양념 (인덕션 옆)
	if info.hobBB then
		local p = topSpot(C, info, 0.5, 0.5, 1.3, { hobEdge + hobOut * 0.4 }, true)
		if p then
			utensilHolder(C, p)
		end
		local q = topSpot(C, info, 1.0, 0.75, 1.0, { hobEdge + hobOut * 1.2, hobEdge - hobOut * 1.0 }, true)
		if q then
			seasonings(C, q, ti)
		end
	end
	-- 도마 (벽에 기대 둠)
	local cb = topSpot(C, info, 1.2, 0.4, 0.9, { (sinkC + hobC) / 2, sinkC + away * 3 }, true)
	if cb then
		cuttingBoard(C, cb, ti)
	end
	-- 등급별
	local ends = { info.topA + 1.0, info.topB - 1.0 }
	if ti <= 2 then
		local p = topSpot(C, info, 1.0, 0.7, 0.9, { ends[1], ends[2] }, true)
		if p then
			ramenStack(C, p)
		end
		local s = topSpot(C, info, 0.4, 0.4, 0.9, { sinkEdge + away * 2.2 }, false)
		if s then
			spoonHolder(C, s)
		end
	end
	if ti >= 3 then
		local p = topSpot(C, info, 1.0, 1.0, 1.2, { ends[1], ends[2], sinkC + away * 4 }, true)
		if p then
			if ti >= 5 then
				espressoMachine(C, p)
			else
				capsuleMachine(C, p, ti)
			end
		end
		if ti <= 4 then
			local f = topSpot(C, info, 1.0, 1.0, 1.1, { ends[2], ends[1], hobC - hobOut * 4 }, true)
			if f then
				airFryer(C, f, ti)
			end
		end
		local k = topSpot(C, info, 0.45, 0.6, 0.9, { hobEdge + hobOut * 2.2 }, true)
		if k then
			knifeBlock(C, k)
		end
	end
	if ti >= 4 then
		local p = topSpot(C, info, 0.7, 1.2, 1.6, { sinkEdge2 - away * 1.4, sinkEdge + away * 2.4 }, true)
		if p then
			purifier(C, p, ti)
		end
	end
	local pt = topSpot(C, info, 0.45, 0.45, 1.05, { sinkEdge + away * 3.2, ends[1] + 0.5 }, true)
	if pt then
		paperTowel(C, pt)
	end
end

-- 바닥: 분리수거함 · 주방 매트
local function kitchenFloor(K: any, V: any, runs: { any })
	if V.decorPlus then
		return
	end
	local main = runs[1]
	if not main then
		return
	end
	local C = main.C
	-- 주방 매트 (개수대 앞)
	if main.bowl then
		local cx = (main.bowl.a + main.bowl.b) / 2
		local cf = CF(cx, 0.012, main.zt + 0.85)
		if C:claim(cf, V3(3.0, 0.024, 1.3), "mat") then
			C:slab("KitchenMat", 3.0, 1.3, 0.024, 0.15, cf, lk(196, 186, 168, M.Fabric))
			if C.hi then
				for k = -2, 2 do
					C:box("KitchenMatStripe", V3(0.05, 0.026, 1.1), cf * CF(k * 0.55, 0, 0), lk(160, 150, 134, M.Fabric))
				end
			end
		end
	end
	-- 분리수거함: 조리대 끝 바깥 (앞쪽 바닥) 이나 냉장고 옆
	local cands = {}
	for _, s in { -1, 1 } do
		local x = (if s < 0 then main.topA else main.topB) + s * 0.75
		table.insert(cands, CF(x, 0, 0.62))
		table.insert(cands, CF(x + s * 0.4, 0, 0.62))
		table.insert(cands, CF((if s < 0 then main.topA else main.topB) - s * 0.7, 0, main.zt + 0.62))
	end
	for _, cf in cands do
		local food = C.ti >= 2
		local w = if food then 2.0 else 1.3
		local center = cf * CF(if food then 0.35 else 0, 1.25, 0)
		if C:clear(center, V3(w, 2.5, 1.15), "floor", 0.05) then
			C:reserve(center, V3(w, 2.5, 1.15))
			recycleBins(C, cf * CF(if food then -0.15 else 0, 0, 0), food)
			break
		end
	end
end

local function kitchen(K: any, V: any)
	local H = ceilingAt(V, (V.x0 + V.x1) / 2, (V.z0 + V.z1) / 2, V.W / 2, V.D / 2)
	local tops = {}
	for _, r in V.byName.CounterTop or {} do
		if r.part.Transparency < 0.99 and not K.hidden[r.part] and not inModel(r, { Island = true }) then
			table.insert(tops, r)
		end
	end
	table.sort(tops, function(a, b)
		return math.max(a.size.X, a.size.Z) > math.max(b.size.X, b.size.Z)
	end)
	local runs = {}
	for i, top in tops do
		if not K.hidden[top.part] then
			local ok, res = pcall(kitchenRun, K, V, top, i, H)
			if ok and res then
				table.insert(runs, res)
			elseif not ok then
				K:note("homewet kitchen run: " .. tostring(res))
			end
		end
	end
	local steps = {
		{ "fridges", function()
			kitchenFridges(K, V, H)
		end },
		{ "appliances", function()
			kitchenAppliances(K, V, H)
		end },
		{ "island", function()
			local r = runs[1]
			kitchenIsland(K, V, H, r and r.n, r and r.wallPos)
		end },
		{ "clutter", function()
			for _, r in runs do
				kitchenClutter(r)
			end
		end },
		{ "floor", function()
			kitchenFloor(K, V, runs)
		end },
	}
	for _, s in steps do
		local ok, err = pcall(s[2])
		if not ok then
			K:note("homewet kitchen." .. s[1] .. ": " .. tostring(err))
		end
	end
end

--=================================================================================================================
-- 진입점 ------------------------------------------------------------------------------------------------------------
--=================================================================================================================
local BUILDERS: { [string]: (any, any) -> () } = {
	kitchen = kitchen,
}

function HomeWet.build(K: any, V: any, S: any)
	local fn = BUILDERS[V.room]
	if not fn then
		return
	end
	K.hwStart = #K.parts
	K.hwPrior = nil
	K.hwRes = K.hwRes or {}
	K.hwLights = 0
	-- 집에는 가게 앵커(문 · 전자레인지 ...) 6.5 규칙 대신 HomeInteract 거리 규칙 (Ctx:promptOK)
	local savedHosts = K.hostPts
	K.hostPts = {}
	local ok, err = pcall(function()
		K:free(function()
			fn(K, V)
		end)
	end)
	K.hostPts = savedHosts
	if not ok then
		K:note("homewet " .. tostring(V.room) .. " error: " .. tostring(err))
	end
end

return HomeWet
