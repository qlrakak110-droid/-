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
		local lp = self.cf:ToObjectSpace(self.cf * cf)
		local a, b = laabb(lp, size)
		if a.X < self.x0 - 0.05 or b.X > self.x1 + 0.05 or a.Z < self.z0 - 0.05 or b.Z > self.z1 + 0.05 then
			return false
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
