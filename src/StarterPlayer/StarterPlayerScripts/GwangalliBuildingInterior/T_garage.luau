--!strict
-- GwangalliBuildingInterior/T_garage: 광안 오토 정비소 & 중고차 의 세 방 (showroom · servicebay · carwash) 실내.
--   style(V) -> S  : Common 공통 마감은 전부 건너뜀 (이 건물은 1.9 도 돌아가 있어 V 프레임 벽 · 천장과 안 맞음)
--   build(K, V, S) : 건물 프레임 B 를 맵 바닥 파트에서 직접 재고, 그 프레임에서 벽 · 천장 · 바닥 마감 + 장비 + 상호작용
--
-- 건물 프레임 B (이 모듈의 모든 좌표): 원점 = 방 상자 원점 근처 (바닥 파트 기준으로 고정), +X / +Z 가 실제 벽과 평행,
--   y = 방 바닥 높이 기준. 방 상자(rooms.json)가 조금 틀려도 (쇼룸은 뒤쪽 5 스터드가 상자 밖) 바닥 파트에서 프레임을
--   다시 잡으니 결과가 같습니다. 바닥 소품 자리는 spot() (K:spot 과 같은 검사를 B 프레임에서: 방 경계 · 맵 물건 ·
--   V.keep · 이 모듈의 계약 구역 · 예약) 으로 확인하고 K:reserve 로 예약합니다.
--
-- 계약 구역 (keepB, 절대 안 들어감): 턴테이블 반지름 8.75 원기둥 (천장까지), PriceCard 앞, GarageDesk_* 프롬프트 앞,
--   직원(GarageStaff) 주변, 리프트 1 · 2 작업 구역 + 진입로, GarageZone_service / GarageZone_wash, 세차 갠트리 이동 구간
--   (z 432..471 월드), 세차 진입 · 출차로, 쇼룸 통로. Workspace.GwangalliShowroom 의 차(서버가 6 초 뒤 빈 바닥에 둠)는
--   지을 때 keep 으로, 나중에 생기면 겹치는 우리 바닥 소품을 지웁니다.
-- 맵 파트는 숨기기만 (Scan.hide): 조잡한 장식 (LightPanel 네온 띠, 소파 상자, 정수기 상자, 화분, 나무 문짝, 공구 판때기,
--   빨간 공구함 상자, 오일 선반 상자, 진공청소기 상자 ...) 을 숨기고 같은 자리 · 같은 크기로 다시 지음. 게임플레이 파트
--   (LIVE_BOARDS, 프롬프트 앵커, 리프트, 존, 갠트리, 브러시, 차, 직원) 는 그대로.

local Look = require(script.Parent:WaitForChild("Look"))
local Props = require(script.Parent:WaitForChild("Props"))
local Interact = require(script.Parent:WaitForChild("Interact"))
local Scan = require(script.Parent:WaitForChild("Scan"))

local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local T = {}
T.types = { "showroom", "servicebay", "carwash" }

local CF, V3 = CFrame.new, Vector3.new
local ANG = CFrame.Angles
local PI = math.pi
local M = Enum.Material
local C = Color3.fromRGB
local WHITE = C(255, 255, 255)
local INK = C(26, 28, 34)
local XA, YA, ZA = Vector3.xAxis, Vector3.yAxis, Vector3.zAxis

-- 광안 오토 브랜드 색 (맵 파사드 · 데스크와 같은 색)
local NAVY = C(30, 36, 48)
local ORANGE = C(232, 86, 30)

local function lk(c: Color3, m: Enum.Material?, extra: { [string]: any }?): any
	local t: any = { c = c, m = m or M.SmoothPlastic }
	if extra then
		for k, v in extra do
			t[k] = v
		end
	end
	return t
end
local function darker(c: Color3, t: number): Color3
	return c:Lerp(C(0, 0, 0), t)
end

local L = {
	panelWhite = lk(C(243, 243, 240)),
	reveal = lk(C(150, 152, 156)),
	navy = lk(NAVY),
	navyMatte = lk(C(34, 40, 54), M.SmoothPlastic),
	orangeNeon = Look.neon(ORANGE),
	alu = Look.alu,
	darkAlu = Look.darkAlu,
	steel = Look.steel,
	black = Look.black,
	rubber = Look.rubber,
	chrome = Look.chrome,
	white = Look.white,
	glassFrost = { c = C(236, 240, 242), m = M.Glass, t = 0.18, r = 0.05 },
	glassClear = { c = C(200, 222, 228), m = M.Glass, t = 0.72, r = 0.18 },
	screenDark = { c = C(14, 16, 20), m = M.Glass, r = 0.2 },
	epoxy = lk(C(126, 132, 136), M.SmoothPlastic, { r = 0.04 }),
	epoxyDark = lk(C(84, 88, 92), M.SmoothPlastic, { r = 0.04 }),
	yellow = lk(C(236, 186, 30)),
	red = lk(C(196, 34, 30)),
	toolRed = lk(C(186, 28, 26), M.Metal),
	blueSteel = lk(C(40, 72, 130), M.Metal),
	hiVis = lk(C(250, 204, 20)),
	cardboard = Look.cardboard,
	tyre = lk(C(30, 30, 32), M.Rubber),
	tyreSide = lk(C(42, 42, 44), M.Rubber),
	rim = lk(C(196, 198, 202), M.Metal, { r = 0.15 }),
	tile = lk(C(238, 240, 240), M.CeramicTiles),
	grout = lk(C(178, 184, 188)),
	stainless = Look.steel,
	fabric = lk(C(84, 86, 92), M.Fabric),
	fabricLight = lk(C(118, 120, 126), M.Fabric),
}

---------------------------------------------------------------------------------------------------
-- 0. 작은 도구
---------------------------------------------------------------------------------------------------
local function note(K: any, s: string)
	K:note("garage: " .. s)
end

local function step(K: any, name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		note(K, name .. " error: " .. tostring(err))
	end
end

-- 결정적 난수
local function mkRng(seed: number): () -> number
	local s = math.floor(seed) % 2147483646 + 1
	return function(): number
		s = (s * 48271) % 2147483647
		return s / 2147483647
	end
end

local function laabb(cf: CFrame, size: Vector3): (Vector3, Vector3)
	local h = size / 2
	local ex = math.abs(cf.XVector.X) * h.X + math.abs(cf.YVector.X) * h.Y + math.abs(cf.ZVector.X) * h.Z
	local ey = math.abs(cf.XVector.Y) * h.X + math.abs(cf.YVector.Y) * h.Y + math.abs(cf.ZVector.Y) * h.Z
	local ez = math.abs(cf.XVector.Z) * h.X + math.abs(cf.YVector.Z) * h.Y + math.abs(cf.ZVector.Z) * h.Z
	local p = cf.Position
	return V3(p.X - ex, p.Y - ey, p.Z - ez), V3(p.X + ex, p.Y + ey, p.Z + ez)
end

local function overlap(amin: Vector3, amax: Vector3, bmin: Vector3, bmax: Vector3, eps: number): boolean
	return amin.X < bmax.X - eps and amax.X > bmin.X + eps and amin.Y < bmax.Y - eps and amax.Y > bmin.Y + eps and amin.Z < bmax.Z - eps and amax.Z > bmin.Z + eps
end

-- 표시면 프레임 (B): p 에서 n 쪽을 봄
local function dcfAt(p: Vector3, n: Vector3): CFrame
	local x = YA:Cross(n)
	if x.Magnitude < 1e-3 then
		x = XA
	end
	x = x.Unit
	local y = n:Cross(x).Unit
	return CFrame.fromMatrix(p, x, y, n)
end
-- 바닥에 누운 글자 (위에서 읽음, 글자 위쪽 = up 방향)
local function floorCF(p: Vector3, up: Vector3): CFrame
	local u = V3(up.X, 0, up.Z).Unit
	local x = u:Cross(YA)
	return CFrame.fromMatrix(p, x, u, YA)
end
-- 소품 프레임: 바닥 점 (x, y, z), 정면 yaw (도, 0 = +Z)
local function pf(x: number, y: number, z: number, yawDeg: number?): CFrame
	return CF(x, y, z) * ANG(0, math.rad(yawDeg or 0), 0)
end

local function fmtWon(n: number): string
	local s = tostring(math.floor(n + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return out
end

---------------------------------------------------------------------------------------------------
-- 1. 건물 프레임 · 맵 읽기 · 자리 엔진
---------------------------------------------------------------------------------------------------
-- 지금 rooms.json 상자 기준으로 잰 바닥 파트 윗면 가운데의 B 좌표 (프레임을 바닥 파트에 고정할 때 씀)
local FLOOR_REF = {
	showroom = { name = "ShowroomFloor", p = V3(-0.16, 0.03, -3.58) },
	servicebay = { name = "BayFloor", p = V3(-0.02, 0.02, -0.82) },
	carwash = { name = "WashFloor", p = V3(0.02, 0.02, 0.02) },
}

-- 방 경계 (B 좌표, 맵에서 다시 재지 못하면 이 값). x0/x1/z0/z1 = 벽 안쪽 면, y1 = 천장 아랫면
local ROOM_DEF = {
	showroom = { x0 = -35.35, x1 = 35.03, z0 = -29.47, z1 = 21.9, y0 = 0.03, y1 = 14.73 },
	servicebay = { x0 = -24.01, x1 = 23.97, z0 = -27.01, z1 = 25.2, y0 = 0.02, y1 = 15.84 },
	carwash = { x0 = -13.57, x1 = 13.61, z0 = -25.0, z1 = 25.03, y0 = 0.02, y1 = 13.44 },
}

local STRUCT: { [string]: boolean } = {}
for k in Scan.SHELL do
	STRUCT[k] = true
end
for _, k in {
	"ShowroomFloor", "BayFloor", "WashFloor", "GroundBack", "GroundSide", "CeilingBoard", "Slab", "Forecourt", "PlotPaving", "Apron",
	"BayWall", "BayRoof", "WashWall", "WashRoof", "WashGlass", "Truss", "Baseboard", "SpandrelGlass", "Fascia", "FasciaStripe",
	"HeadRail", "SillRail", "BayFascia", "WashFascia", "CornerCanopy", "Threshold", "FloorTrack", "Runway", "SafetyLine",
	"ZoneMark", "WashGuideLine", "WashStopLine", "DrainGrate", "GantryRail", "ApronLine", "ApronHatch", "DiscTag", "LightPanel",
	"CassetteAC", "ACVanes", "ACGrille", "SmokeDetector", "CCTV", "CCTVMount", "RollUpDrum", "RollUpSlat", "Core",
} do
	STRUCT[k] = true
end

local function yawOf(cf: CFrame): number
	local x = cf.XVector
	local a = math.atan2(-x.Z, x.X)
	-- 90 도 단위로 접어 (-45, 45] 로
	while a > PI / 4 do
		a -= PI / 2
	end
	while a <= -PI / 4 do
		a += PI / 2
	end
	return a
end

local function newCtx(K: any, V: any, kind: string): any
	local G: any = { K = K, V = V, kind = kind }
	-- 1) 프레임: 바닥 파트 (방 상자 근처에서 이름으로)
	local ref = FLOOR_REF[kind]
	local B = CFrame.new()
	local floorPart: BasePart? = nil
	local best = math.huge
	for _, d in V.model:GetDescendants() do
		if d:IsA("BasePart") and d.Name == ref.name then
			local lp = V.cf:PointToObjectSpace(d.Position)
			local dist = V3(lp.X, 0, lp.Z).Magnitude
			if dist < best then
				best = dist
				floorPart = d
			end
		end
	end
	if floorPart and best < 40 then
		local lcf = V.cf:ToObjectSpace(floorPart.CFrame)
		local yaw = yawOf(lcf)
		local _, mx = laabb(lcf, floorPart.Size)
		-- 바닥 윗면 가운데 (V 프레임), 같은 yaw
		local top = CFrame.new(lcf.Position.X, mx.Y, lcf.Position.Z) * ANG(0, yaw, 0)
		-- 경사진 바닥 윗면: 회전된 상자의 AABB 윗면 = 실제 윗면 (yaw 만 있으니 같음)
		B = top * CF(-ref.p.X, -ref.p.Y, -ref.p.Z)
		G.frameFrom = ref.name
	else
		B = ANG(0, math.rad(-1.9), 0)
		G.frameFrom = "fallback"
	end
	G.B = B
	G.Binv = B:Inverse()
	-- 2) 맵 파트 (방 + 둘레 8 스터드) 의 B AABB
	local def = ROOM_DEF[kind]
	G.RB = table.clone(def)
	local mg = 8
	G.parts = {}
	G.byName = {}
	for _, d in V.model:GetDescendants() do
		if d:IsA("BasePart") then
			local bcf = G.Binv * V.cf:ToObjectSpace(d.CFrame)
			local c = bcf.Position
			if c.X > def.x0 - mg and c.X < def.x1 + mg and c.Z > def.z0 - mg and c.Z < def.z1 + mg and c.Y > -3 and c.Y < def.y1 + 4 then
				local mn, mx = laabb(bcf, d.Size)
				local r = { part = d, name = d.Name, min = mn, max = mx, c = (mn + mx) / 2, size = mx - mn, bcf = bcf }
				table.insert(G.parts, r)
				local l = G.byName[d.Name]
				if not l then
					l = {}
					G.byName[d.Name] = l
				end
				table.insert(l, r)
			end
		end
	end
	-- 3) 벽 · 천장 다시 재기 (이름이 있으면)
	local RB = G.RB
	local function inner(names: { string }, axis: string, side: number, cur: number): number
		local v = nil
		for _, nm in names do
			for _, r in G.byName[nm] or {} do
				local big = (axis == "X" and r.size.Z > 20) or (axis == "Z" and r.size.X > 20)
				if big and r.size.Y > 3 then
					local c = if axis == "X" then r.c.X else r.c.Z
					local ref0 = if axis == "X" then (if side < 0 then def.x0 else def.x1) else (if side < 0 then def.z0 else def.z1)
					if math.abs(c - ref0) < 2.5 then
						local face = if axis == "X" then (if side < 0 then r.max.X else r.min.X) else (if side < 0 then r.max.Z else r.min.Z)
						v = face
					end
				end
			end
		end
		return v or cur
	end
	if kind == "showroom" then
		RB.x0 = inner({ "GroundSide" }, "X", -1, RB.x0)
		RB.x1 = inner({ "GroundSide" }, "X", 1, RB.x1)
		RB.z0 = inner({ "GroundBack" }, "Z", -1, RB.z0)
		local cb = G.byName.CeilingBoard and G.byName.CeilingBoard[1]
		if cb then
			RB.y1 = cb.min.Y
		end
	elseif kind == "servicebay" then
		RB.x0 = inner({ "BayWall" }, "X", -1, RB.x0)
		RB.x1 = inner({ "BayWall" }, "X", 1, RB.x1)
		RB.z0 = inner({ "BayWall" }, "Z", -1, RB.z0)
		local rf = G.byName.BayRoof and G.byName.BayRoof[1]
		if rf then
			RB.y1 = rf.min.Y
		end
	else
		RB.x0 = inner({ "WashWall" }, "X", -1, RB.x0)
		RB.x1 = inner({ "WashWall" }, "X", 1, RB.x1)
		local rf = G.byName.WashRoof and G.byName.WashRoof[1]
		if rf then
			RB.y1 = rf.min.Y
		end
	end
	G.keepB = {}
	G.resB = {}
	G.props = {}
	G.obst = {}
	for _, r in G.parts do
		local big = (r.size.X > 30 and r.size.Z > 2) or (r.size.Z > 30 and r.size.X > 2) or (r.size.X > 30 and r.size.Z > 30)
		if not STRUCT[r.name] and string.sub(r.name, 1, 5) ~= "Sign_" and not big then
			table.insert(G.obst, r)
		end
	end
	-- 4) V.keep (Scan 이 만든 keep: 문 · NPC · 좌석 ...) 을 B AABB 로
	for _, k in V.keep do
		local c = (k.min + k.max) / 2
		local mn, mx = laabb(G.Binv * CF(c), k.max - k.min)
		table.insert(G.keepB, { min = mn, max = mx, kind = "v:" .. tostring(k.kind) })
	end
	return G
end

-- B 상자 하나를 keep 으로 (B 목록 + V.keep 에도 넣어 다른 검사도 피하게)
local function keep(G: any, mn: Vector3, mx: Vector3, kind: string)
	table.insert(G.keepB, { min = mn, max = mx, kind = kind })
	local c = (mn + mx) / 2
	local vmn, vmx = laabb(G.B * CF(c), mx - mn)
	G.V:addKeep(vmn, vmx, "garage:" .. kind)
end

-- 원기둥 keep (반지름 r 정사각형으로 근사)
local function keepCyl(G: any, x: number, z: number, r: number, y0: number, y1: number, kind: string)
	keep(G, V3(x - r, y0, z - r), V3(x + r, y1, z + r), kind)
end

local function hitKeep(G: any, mn: Vector3, mx: Vector3): string?
	for _, k in G.keepB do
		if overlap(mn, mx, k.min, k.max, 0.03) then
			return k.kind
		end
	end
	return nil
end

-- B AABB 가 비었나 (keep · 맵 물건 · 예약). ignore = 무시할 맵 파트 집합
local function clear(G: any, mn: Vector3, mx: Vector3, ignore: { [any]: boolean }?): (boolean, string?)
	local RB = G.RB
	if mn.X < RB.x0 - 0.05 or mx.X > RB.x1 + 0.05 or mn.Z < RB.z0 - 0.05 or mx.Z > RB.z1 + 0.05 then
		return false, "bounds"
	end
	local k = hitKeep(G, mn, mx)
	if k then
		return false, "keep " .. k
	end
	for _, o in G.obst do
		if not (ignore and ignore[o.part]) and overlap(mn, mx, o.min, o.max, 0.03) then
			return false, "map " .. o.name
		end
	end
	for _, r in G.resB do
		if overlap(mn, mx, r.min, r.max, 0.01) then
			return false, "reserved " .. tostring(r.kind)
		end
	end
	return true, nil
end

local function reserveB(G: any, mn: Vector3, mx: Vector3, kind: string)
	table.insert(G.resB, { min = mn, max = mx, kind = kind })
	local c = (mn + mx) / 2
	local vmn, vmx = laabb(G.B * CF(c), mx - mn)
	G.K:reserve(vmn, vmx, kind)
end

-- 바닥 소품 자리 (K:spot 과 같은 검사, B 프레임): pcf = 소품 바닥 가운데 (B), size = 전체 크기
local function spot(G: any, pcf: CFrame, size: Vector3, pad: number?, kind: string?, ignore: { [any]: boolean }?): boolean
	local p = pad or 0
	local mn, mx = laabb(pcf * CF(0, size.Y / 2, 0), size + V3(2 * p, 0, 2 * p))
	local ok, why = clear(G, mn, mx, ignore)
	if not ok then
		note(G.K, string.format("skip %s (%s)", tostring(kind), tostring(why)))
		return false
	end
	reserveB(G, mn, mx, kind or "prop")
	return true
end

-- 소품 묶음 기록 (나중에 생긴 쇼룸 차와 겹치면 통째로 지움)
local function propGroup(G: any, name: string, mn: Vector3, mx: Vector3, fn: () -> ())
	local K = G.K
	local i0 = #K.parts
	fn()
	local list = {}
	for i = i0 + 1, #K.parts do
		table.insert(list, K.parts[i])
	end
	table.insert(G.props, { name = name, min = mn, max = mx, parts = list })
end

-- 맵 파트 숨기기 (이름 + 선택 필터)
local function hideRec(G: any, r: any)
	Scan.hide(G.K.hidden, r.part)
end
local function hideNamed(G: any, name: string, filter: ((any) -> boolean)?): { any }
	local out = {}
	for _, r in G.byName[name] or {} do
		if not filter or filter(r) then
			hideRec(G, r)
			table.insert(out, r)
		end
	end
	return out
end
local function within(r: any, x0: number, x1: number, z0: number, z1: number): boolean
	return r.c.X > x0 and r.c.X < x1 and r.c.Z > z0 and r.c.Z < z1
end

---------------------------------------------------------------------------------------------------
-- 2. 그리기 (B 프레임 래퍼)
---------------------------------------------------------------------------------------------------
local function draw(G: any): any
	local K, B = G.K, G.B
	local D: any = {}
	function D.box(n: string, s: Vector3, cf: CFrame, l: any?): BasePart
		return K:box(n, s, B * cf, l)
	end
	function D.wedge(n: string, s: Vector3, cf: CFrame, l: any?): BasePart
		return K:wedge(n, s, B * cf, l)
	end
	function D.cyl(n: string, len: number, d: number, cf: CFrame, l: any?): BasePart
		return K:cyl(n, len, d, B * cf, l)
	end
	function D.vcyl(n: string, h: number, d: number, cf: CFrame, l: any?): BasePart
		return K:vcyl(n, h, d, B * cf, l)
	end
	function D.ball(n: string, d: number, cf: CFrame, l: any?): BasePart
		return K:ball(n, d, B * cf, l)
	end
	function D.ell(n: string, s: Vector3, cf: CFrame, l: any?): BasePart
		return K:ell(n, s, B * cf, l)
	end
	function D.seg(n: string, a: Vector3, b: Vector3, d: number, l: any?, ex: number?): BasePart?
		return K:seg(n, B * a, B * b, d, l, ex)
	end
	function D.bar(n: string, a: Vector3, b: Vector3, w: number, h: number, l: any?): BasePart?
		return K:bar(n, B * a, B * b, w, h, l)
	end
	function D.ring(n: string, f: CFrame, R: number, d: number, k: number, l: any?, a0: number?, a1: number?): { BasePart }
		return K:ring(n, B * f, R, d, k, l, a0, a1)
	end
	function D.rbox(n: string, s: Vector3, r: number, cf: CFrame, l: any?): { BasePart }
		return K:rbox(n, s, r, B * cf, l)
	end
	function D.slab(n: string, w: number, len: number, t: number, r: number, cf: CFrame, l: any?): { BasePart }
		return K:slab(n, w, len, t, r, B * cf, l)
	end
	function D.panel(n: string, w: number, h: number, d: number, r: number, dcf: CFrame, l: any?): { BasePart }
		return K:panel(n, w, h, d, r, B * dcf, l)
	end
	function D.disc(n: string, dia: number, t: number, cf: CFrame, l: any?): BasePart
		return K:disc(n, dia, t, B * cf, l)
	end
	function D.plate(n: string, w: number, h: number, d: number, dcf: CFrame, l: any?): BasePart
		return K:plate(n, w, h, d, B * dcf, l)
	end
	function D.text(n: string, w: number, h: number, dcf: CFrame, s: string, o: any?): (BasePart, TextLabel)
		return K:text(n, w, h, B * dcf, s, o)
	end
	function D.light(p: BasePart?, kind: string, props: any): Light?
		if not p then
			return nil
		end
		return K:light(p, kind, props)
	end
	function D.group(name: string, fn: () -> ()): Model
		return K:group(name, fn)
	end
	-- 벽 표시면 (B): w = back | front | left | right, s = 벽을 따라가는 B 좌표 (back/front = x, left/right = z)
	function D.wall(w: string, s: number, y: number, off: number?): CFrame
		local RB = G.RB
		local o = off or 0
		if w == "back" then
			return CFrame.fromMatrix(V3(s, y, RB.z0 + o), XA, YA, ZA)
		elseif w == "front" then
			return CFrame.fromMatrix(V3(s, y, RB.z1 - o), -XA, YA, -ZA)
		elseif w == "left" then
			return CFrame.fromMatrix(V3(RB.x0 + o, y, s), -ZA, YA, XA)
		end
		return CFrame.fromMatrix(V3(RB.x1 - o, y, s), ZA, YA, -XA)
	end
	-- 벽에서 바닥에 세우는 소품의 pcf (정면 = 방 안쪽)
	function D.wallPf(w: string, s: number, depth: number, y: number?): CFrame
		local RB = G.RB
		local yy = y or RB.y0
		if w == "back" then
			return pf(s, yy, RB.z0 + depth / 2, 0)
		elseif w == "front" then
			return pf(s, yy, RB.z1 - depth / 2, 180)
		elseif w == "left" then
			return pf(RB.x0 + depth / 2, yy, s, 90)
		end
		return pf(RB.x1 - depth / 2, yy, s, -90)
	end
	-- 글자판 (fg, bg 간단 호출)
	function D.label(n: string, w: number, h: number, dcf: CFrame, s: string, fg: Color3?, bg: Color3?, o: any?): (BasePart, TextLabel)
		local opts: any = if o then table.clone(o) else {}
		opts.fg = fg or INK
		opts.bg = bg
		return K:text(n, w, h, B * dcf, s, opts)
	end
	return D
end

---------------------------------------------------------------------------------------------------
-- 3. 공용 소품 (B 프레임, D 사용)
---------------------------------------------------------------------------------------------------
-- 타이어 (+ 휠). cf = 바퀴 중심, 축 = cf.X. o.rim (true = 알로이 휠), o.spokes, o.w (폭)
local function tyre(D: any, cf: CFrame, dia: number, o: any?)
	local w = (o and o.w) or dia * 0.36
	D.cyl("Tyre", w, dia, cf, L.tyre)
	D.cyl("TyreSidewall", w + 0.02, dia * 0.84, cf, L.tyreSide)
	for _, s in { -1, 1 } do
		D.cyl("TyreGroove", 0.04, dia + 0.004, cf * CF(s * w * 0.18, 0, 0), lk(C(18, 18, 20), M.Rubber))
	end
	if o and o.rim then
		local rd = dia * 0.64
		D.cyl("WheelRim", w * 0.86, rd, cf, o.rimLook or L.rim)
		D.cyl("WheelFace", 0.04, rd * 0.92, cf * CF(w * 0.44, 0, 0), lk(C(70, 72, 78), M.Metal))
		local n = o.spokes or 5
		for i = 0, n - 1 do
			local a = i * 2 * PI / n
			local a1 = cf * CF(w * 0.46, math.cos(a) * rd * 0.12, math.sin(a) * rd * 0.12)
			local b1 = cf * CF(w * 0.46, math.cos(a) * rd * 0.44, math.sin(a) * rd * 0.44)
			D.seg("WheelSpoke", a1.Position, b1.Position, rd * 0.1, o.rimLook or L.rim)
		end
		D.cyl("WheelHub", 0.08, rd * 0.26, cf * CF(w * 0.47, 0, 0), lk(C(40, 42, 46), M.Metal))
	else
		D.cyl("TyreBead", w + 0.04, dia * 0.6, cf, lk(C(14, 14, 16), M.Rubber))
	end
end

-- 트랙 스포트 (레일 아래 점 p, 목표 t). 렌즈 파트 반환 (SpotLight 붙일 곳: Front 면이 목표를 봄)
local function trackHead(D: any, p: Vector3, t: Vector3, look: any?): BasePart
	local Lk = look or L.black
	D.box("TrackAdapter", V3(0.28, 0.14, 0.2), CF(p - V3(0, 0.07, 0)), Lk)
	local joint = p - V3(0, 0.38, 0)
	D.seg("TrackStem", p - V3(0, 0.12, 0), joint, 0.07, Lk)
	local hcf = CFrame.lookAt(joint, t)
	D.ball("TrackJoint", 0.16, CF(joint), Lk)
	D.cyl("TrackHead", 0.62, 0.36, hcf * CF(0, 0, -0.16) * ANG(0, PI / 2, 0), Lk)
	D.cyl("TrackRing", 0.06, 0.4, hcf * CF(0, 0, -0.46) * ANG(0, PI / 2, 0), lk(C(60, 60, 64), M.Metal))
	D.cyl("TrackFins", 0.2, 0.3, hcf * CF(0, 0, 0.22) * ANG(0, PI / 2, 0), lk(C(40, 40, 44), M.Metal))
	local lens = D.box("TrackLens", V3(0.26, 0.26, 0.02), hcf * CF(0, 0, -0.48), Look.lampWarm)
	return lens
end

-- 선형 LED (천장 매입 / 직부): a -> b (같은 y 의 천장 아랫면 점), w 폭
local function linearLED(D: any, a: Vector3, b: Vector3, w: number, o: any?): BasePart?
	local len = (b - a).Magnitude
	if len < 0.5 then
		return nil
	end
	local mid = (a + b) / 2
	local dir = (b - a).Unit
	local cf = CFrame.fromMatrix(mid, dir, YA, dir:Cross(YA))
	local hous = (o and o.housing) or lk(C(232, 232, 230), M.Metal)
	local drop = (o and o.drop) or 0.07
	D.box("LinearHousing", V3(len + 0.1, drop, w), cf * CF(0, -drop / 2, 0), hous)
	D.box("LinearReveal", V3(len, 0.02, w * 0.84), cf * CF(0, -drop - 0.005, 0), lk(C(30, 30, 32)))
	local dif = D.box("LinearDiffuser", V3(len - 0.1, 0.03, w * 0.62), cf * CF(0, -drop - 0.02, 0), (o and o.glow) or Look.lampNeutral)
	for _, s in { -1, 1 } do
		D.box("LinearEndCap", V3(0.06, drop + 0.02, w), cf * CF(s * (len / 2 + 0.05), -drop / 2 - 0.01, 0), hous)
	end
	return dif
end

-- 철제 앵글 선반 (pcf = 바닥 가운데, 정면 +Z). 반환: 각 단 윗면 높이 목록
local function angleRack(D: any, pcf: CFrame, w: number, d: number, h: number, n: number, o: any?): { number }
	local post = (o and o.post) or lk(C(60, 96, 150), M.Metal)
	local board = (o and o.board) or lk(C(150, 154, 158), M.Metal)
	local ys = {}
	local nx = math.max(2, math.ceil(w / 4) + 1)
	for i = 0, nx - 1 do
		local x = -w / 2 + 0.06 + (w - 0.12) * i / (nx - 1)
		for _, sz in { -1, 1 } do
			D.box("RackPost", V3(0.1, h, 0.1), pcf * CF(x, h / 2, sz * (d / 2 - 0.05)), post)
			D.box("RackFoot", V3(0.18, 0.04, 0.18), pcf * CF(x, 0.02, sz * (d / 2 - 0.05)), lk(C(40, 40, 42), M.Metal))
		end
		if i > 0 and i < nx - 1 and o and o.brace then
			D.bar("RackBrace", (pcf * CF(x, 0.4, -d / 2 + 0.05)).Position, (pcf * CF(x, h - 0.3, d / 2 - 0.05)).Position, 0.05, 0.05, post)
		end
	end
	for i = 0, n - 1 do
		local y = 0.32 + (h - 0.5) * i / math.max(1, n - 1)
		D.box("RackShelf", V3(w - 0.04, 0.06, d - 0.06), pcf * CF(0, y, 0), board)
		D.box("RackBeam", V3(w, 0.16, 0.06), pcf * CF(0, y - 0.05, d / 2 - 0.03), post)
		table.insert(ys, y + 0.03)
	end
	return ys
end

-- 엔진오일 4L 통 (pcf = 바닥, 정면 +Z)
local function oilJug(D: any, pcf: CFrame, col: Color3, label: string?, hi: boolean)
	D.rbox("OilJug", V3(0.62, 0.9, 0.34), 0.06, pcf * CF(0, 0.45, 0), lk(col, M.Plastic))
	D.box("OilJugHandle", V3(0.12, 0.18, 0.3), pcf * CF(-0.2, 0.98, 0), lk(col, M.Plastic))
	D.vcyl("OilJugCap", 0.1, 0.14, pcf * CF(0.16, 0.95, 0), lk(C(30, 30, 32), M.Plastic))
	if hi then
		D.label("OilJugLabel", 0.5, 0.42, pcf * CF(0, 0.42, 0.172), label or "5W-30\n4L", WHITE, darker(col, 0.45), { d = 0.01 })
	else
		D.box("OilJugLabel", V3(0.5, 0.42, 0.01), pcf * CF(0, 0.42, 0.172), lk(darker(col, 0.45)))
	end
end

-- 골판지 · 컬러 상자 (부품 상자)
local function partBox(D: any, pcf: CFrame, s: Vector3, col: Color3, label: string?, hi: boolean)
	D.box("PartBox", s, pcf * CF(0, s.Y / 2, 0), lk(col, M.SmoothPlastic))
	if label and hi then
		D.label("PartBoxLabel", s.X * 0.86, math.min(0.34, s.Y * 0.5), pcf * CF(0, s.Y * 0.55, s.Z / 2 + 0.003), label, INK, C(250, 250, 246), { d = 0.01 })
	else
		D.box("PartBoxStripe", V3(s.X * 0.9, s.Y * 0.18, 0.01), pcf * CF(0, s.Y * 0.6, s.Z / 2 + 0.005), lk(darker(col, 0.35)))
	end
end

-- 포스터 / 안내판 (액자형): dcf, 크기, 제목, 본문
local function notice(D: any, dcf: CFrame, w: number, h: number, title: string, body: string, o: any?)
	local fr = (o and o.frame) or L.alu
	local bg: Color3 = (o and o.bg) or C(250, 250, 246)
	local hd: Color3 = (o and o.head) or NAVY
	D.plate("NoticeFrame", w + 0.12, h + 0.12, 0.05, dcf, fr)
	D.plate("NoticeBack", w, h, 0.06, dcf, lk(bg))
	local th = math.min(0.8, h * 0.2)
	D.label("NoticeTitle", w, th, dcf * CF(0, h / 2 - th / 2, 0.065), title, WHITE, hd, { d = 0.01, font = Enum.Font.GothamBlack })
	D.label("NoticeBody", w * 0.92, h - th - 0.2, dcf * CF(0, -th / 2 - 0.02, 0.065), body, (o and o.fg) or INK, nil, { d = 0.01, font = Enum.Font.GothamMedium, align = (o and o.align) or "Left" })
	D.plate("NoticeGlass", w, h, 0.01, dcf * CF(0, 0, 0.08), { c = C(230, 236, 240), m = M.Glass, t = 0.9, r = 0.2 })
end

-- 안전 표지 (원형 · 삼각 대신 사각 판 + 색 띠): kind = "warn" | "ban" | "must" | "fire" | "exit"
local function safetySign(D: any, dcf: CFrame, w: number, h: number, kind: string, text: string)
	local col = if kind == "warn" then C(250, 204, 20) elseif kind == "ban" then C(206, 30, 36) elseif kind == "must" then C(20, 90, 170) elseif kind == "exit" then C(20, 150, 80) else C(200, 30, 30)
	local fg = if kind == "warn" then INK else WHITE
	D.plate("SafetySignBack", w, h, 0.03, dcf, lk(C(250, 250, 248)))
	D.plate("SafetySignBand", w, h * 0.62, 0.04, dcf * CF(0, h * 0.19, 0), lk(col))
	D.label("SafetySignText", w * 0.92, h * 0.34, dcf * CF(0, -h * 0.3, 0.045), text, INK, nil, { d = 0.005, font = Enum.Font.GothamBold })
	local glyph = if kind == "warn" then "⚠" elseif kind == "ban" then "⊘" elseif kind == "must" then "●" elseif kind == "exit" then "➜" else "🧯"
	D.label("SafetySignGlyph", w * 0.5, h * 0.5, dcf * CF(0, h * 0.19, 0.045), glyph, fg, nil, { d = 0.005, font = Enum.Font.GothamBlack })
end

-- 스프링클러 (천장 아래면 y)
local function sprinkler(D: any, x: number, y: number, z: number)
	D.disc("SprinklerRose", 0.3, 0.03, CF(x, y - 0.015, z), L.white)
	D.vcyl("SprinklerBody", 0.2, 0.1, CF(x, y - 0.12, z), Look.brass)
end

-- 소화기 (맵 FireExtinguisher 자리 다시 짓기)
local function extinguisher(D: any, p: Vector3, face: number)
	local base = pf(p.X, p.Y, p.Z, face)
	D.box("ExtStand", V3(0.9, 0.12, 0.9), base * CF(0, 0.06, 0), lk(C(180, 30, 30)))
	D.vcyl("ExtBody", 1.5, 0.62, base * CF(0, 0.12 + 0.75, 0), lk(C(200, 24, 28)))
	D.ell("ExtDome", V3(0.62, 0.3, 0.62), base * CF(0, 1.62, 0), lk(C(200, 24, 28)))
	D.vcyl("ExtNeck", 0.16, 0.2, base * CF(0, 1.8, 0), L.black)
	D.box("ExtHandle", V3(0.5, 0.06, 0.12), base * CF(0.08, 1.95, 0) * ANG(0, 0, -0.2), L.black)
	D.ball("ExtGauge", 0.18, base * CF(0, 1.82, 0.12), L.white)
	D.seg("ExtHose", (base * CF(-0.05, 1.82, -0.1)).Position, (base * CF(-0.3, 0.6, -0.3)).Position, 0.08, L.black)
	D.label("ExtLabel", 0.44, 0.5, base * CF(0, 1.0, 0.315), "소화기\nABC", WHITE, C(40, 40, 40), { d = 0.01 })
end

-- 철제 바퀴 (캐스터)
local function caster(D: any, cf: CFrame, d: number)
	D.box("CasterFork", V3(0.12, d * 0.7, d * 0.5), cf * CF(0, d * 0.65, 0), lk(C(70, 70, 74), M.Metal))
	D.cyl("CasterWheel", d * 0.45, d, cf * CF(0, d / 2, 0), L.rubber)
end

-- 화면 순환 (글자 + 배경색 같이): frames = { { text, bg } }
local function screenCycle(K: any, label: TextLabel?, part: BasePart?, frames: { any }, period: number)
	if not label then
		return
	end
	local last = -1
	Interact.anim(K, function(t: number)
		local i = math.floor(t / period) % #frames + 1
		if i == last then
			return
		end
		last = i
		local f = frames[i]
		if label.Parent then
			label.Text = f[1]
			if f[2] then
				label.BackgroundColor3 = f[2]
			end
			if f[3] then
				label.TextColor3 = f[3]
			end
		end
		if part and part.Parent and f[2] then
			part.Color = f[2]
		end
	end)
end

-- 서버 프롬프트 자리 (GarageDesk_* · PriceCard · ProximityPrompt 가진 파트) 를 K.hostPts 에 더해
-- 우리 프롬프트가 그 6.5 스터드 안에 안 생기게
local function addServerPrompts(G: any)
	local K, V = G.K, G.V
	if not K.hostPts then
		K.hostPts = Interact.hostPoints(V)
	end
	for _, d in V.model:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			local p = d.Parent
			local pos: Vector3? = nil
			if p and p:IsA("BasePart") then
				pos = p.Position
			elseif p and p:IsA("Attachment") then
				pos = p.WorldPosition
			end
			if pos then
				table.insert(K.hostPts, V.cf:PointToObjectSpace(pos))
			end
		end
	end
	for _, r in G.parts do
		if string.sub(r.name, 1, 12) == "GarageDesk_" or r.name == "PriceCard" or CollectionService:HasTag(r.part, "GaragePrompt") or CollectionService:HasTag(r.part, "GarageDesk") then
			table.insert(K.hostPts, V.cf:PointToObjectSpace(r.part.Position))
		end
	end
end

-- 우리 상호작용 프롬프트 (Interact.prompt 를 감싸 이름 기록)
local function prompt(G: any, part: BasePart?, spec: any): ProximityPrompt?
	if not part then
		return nil
	end
	local pr = Interact.prompt(G.K, part, spec)
	if pr then
		G.nPrompts = (G.nPrompts or 0) + 1
	end
	return pr
end

-- 서버 쇼룸 차 (Workspace.GwangalliShowroom) 와 나중에 생기는 차를 피함
local function watchShowroomCars(G: any)
	local K, V = G.K, G.V
	local folder = workspace:FindFirstChild("GwangalliShowroom")
	local function boxOf(m: Instance): (Vector3?, Vector3?)
		if not m:IsA("Model") then
			return nil, nil
		end
		local ok, cf, size = pcall(function()
			return (m :: Model):GetBoundingBox()
		end)
		if not ok or not cf then
			return nil, nil
		end
		local bcf = G.Binv * V.cf:ToObjectSpace(cf)
		local mn, mx = laabb(bcf, size)
		local RB = G.RB
		if mx.X < RB.x0 - 2 or mn.X > RB.x1 + 2 or mx.Z < RB.z0 - 2 or mn.Z > RB.z1 + 2 then
			return nil, nil
		end
		return mn - V3(0.6, 0, 0.6), mx + V3(0.6, 0, 0.6)
	end
	if folder then
		for _, m in folder:GetChildren() do
			local mn, mx = boxOf(m)
			if mn and mx then
				keep(G, mn, mx, "showroomCar")
			end
		end
		K.conns = K.conns or {}
		table.insert(K.conns, folder.ChildAdded:Connect(function(m: Instance)
			task.delay(1, function()
				local mn, mx = boxOf(m)
				if not (mn and mx) then
					return
				end
				for _, g in G.props do
					if overlap(mn, mx, g.min, g.max, 0) then
						for _, p in g.parts do
							if p.Parent then
								p:Destroy()
							end
						end
						g.parts = {}
					end
				end
			end)
		end))
	end
end

---------------------------------------------------------------------------------------------------
-- 4. 쇼룸 (광안 오토 쇼룸)
---------------------------------------------------------------------------------------------------
local CATALOG_FALLBACK: { [string]: any } = {
	compact = { label = "큐비", full = "큐비 박스카", blurb = "작고 귀여운 박스형 경차 · 첫 차로 딱", new = 390000, used = 150000, seats = 4 },
	sedan = { label = "미드 세단", full = "미드 세단", blurb = "무난하고 편한 중형 세단", new = 780000, used = 320000, seats = 5 },
	suv = { label = "트레일 SUV", full = "트레일 SUV", blurb = "사륜구동 · 넉넉한 실내", new = 980000, used = 420000, seats = 5 },
	truck = { label = "1톤 트럭", full = "든든 1톤 트럭", blurb = "짐 싣는 무거운 1톤 트럭", new = 640000, used = 280000, seats = 3 },
	van = { label = "패밀리 밴", full = "패밀리 9인승 밴", blurb = "9인승 · 친구들 다 태우는 밴", new = 1250000, used = 520000, seats = 9 },
	luxury = { label = "플래그십", full = "플래그십 세단", blurb = "가장 빠른 후륜 세단 · 드림카", new = 3200000, used = 1400000, seats = 5 },
}
local SPEC_EXTRA: { [string]: string } = {
	compact = "1.0 가솔린 · 전륜 · 연비 15.7km/L",
	sedan = "2.0 가솔린 · 전륜 · 연비 12.6km/L",
	suv = "2.2 디젤 · 사륜 · 연비 13.2km/L",
	truck = "2.5 디젤 · 후륜 · 적재 1,000kg",
	van = "2.2 디젤 · 전륜 · 9인승 슬라이딩 도어",
	luxury = "3.5 터보 · 후륜 · 0-100km/h 5.1초",
}
local PAINTS = {
	{ "화이트", C(238, 239, 238) }, { "블랙", C(18, 19, 21) }, { "실버", C(178, 182, 186) }, { "그레이", C(96, 100, 104) },
	{ "네이비", C(30, 48, 88) }, { "레드", C(150, 30, 34) }, { "베이지", C(192, 182, 162) }, { "민트", C(142, 170, 160) },
}

local function catalog(): { [string]: any }
	local ok, GS = pcall(function()
		local m = ReplicatedStorage:FindFirstChild("GwangalliGarageShared")
		if m and m:IsA("ModuleScript") then
			return require(m) :: any
		end
		return nil
	end)
	if ok and type(GS) == "table" and type(GS.CATALOG) == "table" then
		return GS.CATALOG
	end
	return CATALOG_FALLBACK
end

local function buildShowroom(K: any, V: any)
	local G = newCtx(K, V, "showroom")
	local D = draw(G)
	local RB = G.RB
	local hi = K.detail == "high"
	local mid = K.detail ~= "low"
	local y0, yC = RB.y0, RB.y1
	note(K, string.format("showroom frame=%s bounds x %.2f..%.2f z %.2f..%.2f ceil %.2f", G.frameFrom, RB.x0, RB.x1, RB.z0, RB.z1, yC))

	-- 4.1 계약 구역 ---------------------------------------------------------------------------------
	local tts = {}
	for _, r in G.parts do
		if r.name == "Turntable" or CollectionService:HasTag(r.part, "GarageTurntable") then
			local kind = r.part:GetAttribute("GarageKind")
			local rad = math.max(r.size.X, r.size.Z) / 2
			table.insert(tts, { x = r.c.X, z = r.c.Z, r = math.max(8.75, rad + 0.25), kind = kind })
		end
	end
	-- 차 종류: 턴테이블 속성이 없으면 가까운 GarageDisplayCar 의 GarageKind
	for _, d in V.model:GetDescendants() do
		if d:IsA("Model") and CollectionService:HasTag(d, "GarageDisplayCar") then
			local ok, cf = pcall(function()
				return (d :: Model):GetPivot()
			end)
			if ok then
				local p = G.Binv * V.cf:PointToObjectSpace(cf.Position)
				for _, t in tts do
					if not t.kind and (V3(p.X, 0, p.Z) - V3(t.x, 0, t.z)).Magnitude < 6 then
						t.kind = d:GetAttribute("GarageKind")
					end
				end
			end
		end
	end
	for _, t in tts do
		keepCyl(G, t.x, t.z, t.r + 0.1, 0.1, yC + 1, "turntable")
	end
	-- 가격 카드 (구매 / 시승 프롬프트) 앞 1.6 + 둘레
	local cards = {}
	for _, r in G.byName.PriceCard or {} do
		table.insert(cards, r)
		keep(G, V3(r.c.X - 2.2, 0.1, r.c.Z - 1.2), V3(r.c.X + 2.2, 7, r.c.Z + 2.6), "priceCard")
	end
	-- 상담 데스크 프롬프트 + 직원
	for _, r in G.byName.GarageDesk_office or {} do
		keep(G, V3(r.c.X - 2.4, 0.1, r.c.Z - 1.4), V3(r.c.X + 2.4, 7, r.c.Z + 2.2), "desk")
	end
	for _, r in G.byName.HumanoidRootPart or {} do
		keep(G, V3(r.c.X - 2.3, 0.1, r.c.Z - 2.3), V3(r.c.X + 2.3, 7, r.c.Z + 2.3), "staff")
	end
	for _, r in G.byName.GarageReturn or {} do
		keep(G, r.min - V3(1, 0, 1), r.max + V3(1, 6, 1), "return")
	end
	-- 통로: 턴테이블 사이 세로 통로 2 (서버 쇼룸 차도 여기 올 수 있음) + 입구
	if #tts >= 4 then
		table.sort(tts, function(a, b)
			return a.x < b.x
		end)
		local xs = {}
		for _, t in tts do
			local found = false
			for _, x in xs do
				if math.abs(x - t.x) < 3 then
					found = true
				end
			end
			if not found then
				table.insert(xs, t.x)
			end
		end
		table.sort(xs)
		for i = 1, #xs - 1 do
			local a, b = xs[i] + 8.85, xs[i + 1] - 8.85
			if b > a then
				keep(G, V3(a, 0.1, -20.4), V3(b, 7, 18.6), "aisle")
			end
		end
	end
	keep(G, V3(-6.6, 0.1, 16.6), V3(6.4, 10, RB.z1 + 0.5), "entrance")
	-- 상담실 · 화장실 문 앞
	keep(G, V3(30.4, 0.1, RB.z0), V3(34.6, 8, RB.z0 + 3.2), "restroomDoor")
	keep(G, V3(RB.x0, 0.1, -21.6), V3(RB.x0 + 3.2, 8, -17.2), "officeDoor")
	watchShowroomCars(G)
	addServerPrompts(G)

	-- 4.2 바닥: 대형 포세린 타일 줄눈 + 입구 매트 + 안내 바닥 글자 ------------------------------------------------
	step(K, "floor", function()
		local gl = lk(C(212, 212, 207))
		local x = RB.x0 + 4.4
		while x < RB.x1 - 0.5 do
			D.box("FloorJoint", V3(0.04, 0.012, RB.z1 - RB.z0 - 0.1), CF(x, y0 + 0.006, (RB.z0 + RB.z1) / 2), gl)
			x += 4.4
		end
		local z = RB.z0 + 4.4
		while z < RB.z1 - 0.5 do
			D.box("FloorJoint", V3(RB.x1 - RB.x0 - 0.1, 0.012, 0.04), CF((RB.x0 + RB.x1) / 2, y0 + 0.006, z), gl)
			z += 4.4
		end
		-- 입구 매트 (런웨이 카펫 위)
		local mz = (RB.z1 + 18.7) / 2
		D.box("EntryMat", V3(8.2, 0.05, RB.z1 - 18.9), CF(-0.15, 0.095, mz), lk(C(46, 48, 54), M.Fabric))
		D.box("EntryMatEdge", V3(8.36, 0.04, RB.z1 - 18.75), CF(-0.15, 0.08, mz), L.rubber)
		D.label("EntryMatLogo", 5.6, 1.0, floorCF(V3(-0.15, 0.125, mz), -ZA), "광안 오토  ·  WELCOME", C(214, 214, 210), nil, { d = 0.005, font = Enum.Font.GothamBlack })
		-- 안내 바닥 스티커 (가운데 통로)
		local function sticker(x: number, z: number, s: string)
			D.slab("FloorSticker", 4.4, 1.0, 0.012, 0.3, CF(x, y0 + 0.008, z), lk(NAVY))
			D.label("FloorStickerText", 4.0, 0.7, floorCF(V3(x, y0 + 0.02, z), -ZA), s, WHITE, nil, { d = 0.004 })
		end
		sticker(-12.2, -0.75, "◀  구매 상담 데스크")
		sticker(11.8, -0.75, "고객 라운지  ▶")
	end)

	-- 4.3 벽 마감: 흰 알루미늄 복합 패널 (줄눈) + 가운데 브랜드 월 ------------------------------------------------
	local function clad(w: string, s0: number, s1: number, ya: number, yb: number, look: any, joint: number)
		local len = s1 - s0
		local mid = (s0 + s1) / 2
		D.plate("WallPanel", len, yb - ya, 0.022, D.wall(w, mid, (ya + yb) / 2, 0.004), look)
		local n = math.max(1, math.floor(len / joint + 0.5))
		for i = 1, n - 1 do
			local s = s0 + len * i / n
			D.plate("WallJoint", 0.04, yb - ya, 0.03, D.wall(w, s, (ya + yb) / 2, 0.004), L.reveal)
		end
		for _, yy in { 3.9, 7.8, 11.7 } do
			if yy > ya + 0.3 and yy < yb - 0.3 then
				D.plate("WallJoint", len, 0.04, 0.03, D.wall(w, mid, yy, 0.004), L.reveal)
			end
		end
		-- 천장 섀도갭
		D.plate("WallShadowGap", len, 0.1, 0.03, D.wall(w, mid, yb - 0.05, 0.004), lk(C(40, 40, 44)))
	end
	step(K, "walls", function()
		clad("left", RB.z0, RB.z1, 0.45, yC, L.panelWhite, 4.4)
		clad("right", RB.z0, RB.z1, 0.45, yC, L.panelWhite, 4.4)
		clad("back", RB.x0, -16.2, 0.45, yC, L.panelWhite, 4.4)
		clad("back", 8.0, RB.x1, 0.45, yC, L.panelWhite, 4.4)
		-- 브랜드 월 (네이비, 세로 오렌지 라인, 위 브랜드 바)
		local bx0, bx1 = -16.2, 8.0
		local bm = (bx0 + bx1) / 2
		D.plate("BrandWall", bx1 - bx0, yC - 0.45, 0.12, D.wall("back", bm, (0.45 + yC) / 2, 0.004), L.navyMatte)
		for _, x in { bx0 + 0.08, bx1 - 0.08 } do
			D.plate("BrandWallLine", 0.1, yC - 0.6, 0.15, D.wall("back", x, (0.45 + yC) / 2, 0.004), L.orangeNeon)
		end
		D.label("BrandWallBar", 14, 1.0, D.wall("back", bm, 12.95, 0.13), "GWANGAN AUTO  ·  믿을 수 있는 중고차 · 정직한 정비", C(236, 236, 232), nil, { d = 0.01, font = Enum.Font.GothamBold })
		-- 맵 간판(Sign_광안 오토) 둘레 헤일로
		local sg = G.byName["Sign_광안 오토"] and G.byName["Sign_광안 오토"][1]
		if sg then
			local cx, cy = sg.c.X, sg.c.Y
			local w, h = sg.size.X, sg.size.Y
			for _, s in { -1, 1 } do
				D.plate("SignHalo", w + 0.3, 0.06, 0.1, D.wall("back", cx, cy + s * (h / 2 + 0.12), 0.13), L.orangeNeon)
				D.plate("SignHalo", 0.06, h + 0.3, 0.1, D.wall("back", cx + s * (w / 2 + 0.12), cy, 0.13), L.orangeNeon)
			end
		end
	end)

	-- 4.4 LED 미디어 월 (간판 아래) --------------------------------------------------------------------
	step(K, "mediaWall", function()
		local cx = -6.17
		local sg = G.byName["Sign_광안 오토"] and G.byName["Sign_광안 오토"][1]
		if sg then
			cx = sg.c.X
		end
		local w, h, yc = 13.6, 4.9, 4.35
		local base = D.wall("back", cx, yc, 0.124)
		D.plate("LEDWallFrame", w + 0.3, h + 0.3, 0.22, base, lk(C(18, 18, 20), M.Metal))
		local scr, lab = D.text("LEDWallScreen", w, h, base * CF(0, 0, 0.22), "", { fg = WHITE, bg = C(18, 40, 90), glow = 1.6, font = Enum.Font.GothamBlack, ppx = 18 })
		D.plate("LEDWallSill", w + 0.4, 0.1, 0.5, base * CF(0, -h / 2 - 0.2, 0), L.alu)
		local frames = {
			{ "GWANGAN AUTO 2026\n신차 · 중고차 · 정비 · 세차", C(16, 34, 78) },
			{ "이달의 특가\n중고 큐비 150,000원", C(170, 54, 20) },
			{ "시승 무료 · 60초\n상담 데스크에서 신청하세요", C(18, 70, 60) },
			{ "할부 OK · 최대 10일 분할\n선수금 30%", C(40, 30, 80) },
			{ "정직한 정비 · 광안 오토 서비스\n엔진오일 · 타이어 · 세차", C(24, 28, 36) },
		}
		lab.Text = frames[1][1]
		screenCycle(K, lab, nil, frames, 5)
		D.light(scr, "SurfaceLight", { Face = Enum.NormalId.Front, Range = 12, Brightness = 0.6, Angle = 110, Color = C(150, 180, 255) })
	end)

	-- 4.5 천장: 선형 LED (맵 네온 띠 자리), 트랙 스포트 (차마다), 스프링클러, 스피커 ------------------------------------
	local ceilUsed = {}
	local function ceilFree(x0: number, x1: number, z0: number, z1: number): boolean
		for _, nm in { "CassetteAC", "SmokeDetector", "CCTV", "CCTVMount" } do
			for _, r in G.byName[nm] or {} do
				if x1 > r.min.X - 0.25 and x0 < r.max.X + 0.25 and z1 > r.min.Z - 0.25 and z0 < r.max.Z + 0.25 then
					return false
				end
			end
		end
		for _, u in ceilUsed do
			if x1 > u[1] and x0 < u[2] and z1 > u[3] and z0 < u[4] then
				return false
			end
		end
		return true
	end
	step(K, "ceilingLights", function()
		for _, r in hideNamed(G, "LightPanel") do
			local alongX = r.size.X >= r.size.Z
			local y = yC
			if alongX then
				linearLED(D, V3(r.min.X, y, r.c.Z), V3(r.max.X, y, r.c.Z), 0.95)
				table.insert(ceilUsed, { r.min.X - 0.4, r.max.X + 0.4, r.c.Z - 0.7, r.c.Z + 0.7 })
			else
				linearLED(D, V3(r.c.X, y, r.min.Z), V3(r.c.X, y, r.max.Z), 0.95)
				table.insert(ceilUsed, { r.c.X - 0.7, r.c.X + 0.7, r.min.Z - 0.4, r.max.Z + 0.4 })
			end
		end
	end)
	step(K, "trackSpots", function()
		-- 열(같은 x)마다: 뒤 차 뒤쪽 레일, 두 차 사이 레일 (양쪽 차를 비춤), 앞 차 앞쪽 레일. 레일은 차 중심 x ± 1.7..5.4 두 토막
		-- (가운데 선형 LED 를 피함). 차마다 첫 머리 하나에 SpotLight (최대 6)
		local cols = {}
		for _, t in tts do
			local col = nil
			for _, c in cols do
				if math.abs(c.x - t.x) < 3 then
					col = c
				end
			end
			if not col then
				col = { x = t.x, cars = {} }
				table.insert(cols, col)
			end
			table.insert(col.cars, t)
		end
		local lightFor: { [any]: BasePart } = {}
		local lightBack: { [any]: BasePart } = {}
		local function rail(cx: number, rz0: number, aims: { any })
			-- 레일 z: 막히면 조금씩 옮겨 봄 (가로 선형 LED · 에어컨 피하기)
			local rz = rz0
			for _, dz in { 0, 0.6, -0.6, 1.2, -1.2, 1.8 } do
				if ceilFree(cx - 5.4, cx - 1.7, rz0 + dz - 0.25, rz0 + dz + 0.25) or ceilFree(cx + 1.7, cx + 5.4, rz0 + dz - 0.25, rz0 + dz + 0.25) then
					rz = rz0 + dz
					break
				end
			end
			for _, sx in { -1, 1 } do
				local a, b = cx + sx * 1.7, cx + sx * 5.4
				local x0, x1 = math.min(a, b), math.max(a, b)
				local tries = 0
				while not ceilFree(x0, x1, rz - 0.25, rz + 0.25) and tries < 6 do
					if sx > 0 then
						x1 -= 0.6
					else
						x0 += 0.6
					end
					tries += 1
				end
				if x1 - x0 >= 1.4 and ceilFree(x0, x1, rz - 0.25, rz + 0.25) then
					table.insert(ceilUsed, { x0 - 0.2, x1 + 0.2, rz - 0.4, rz + 0.4 })
					D.box("TrackRail", V3(x1 - x0, 0.1, 0.16), CF((x0 + x1) / 2, yC - 0.05, rz), L.black)
					for _, cap in { x0, x1 } do
						D.box("TrackEndCap", V3(0.05, 0.12, 0.18), CF(cap, yC - 0.06, rz), L.darkAlu)
					end
					local n = math.min(#aims, if x1 - x0 > 2.6 then 2 else 1)
					for i = 1, n do
						local t = aims[i]
						local hx = x0 + (x1 - x0) * (i - 0.5) / n
						local lens = trackHead(D, V3(hx, yC - 0.1, rz), V3(t.x + (hx - t.x) * 0.25, 2.2, t.z))
						if rz > t.z then
							lightFor[t] = lightFor[t] or lens
						else
							lightBack[t] = lightBack[t] or lens
						end
					end
				end
			end
		end
		for _, col in cols do
			table.sort(col.cars, function(a, b)
				return a.z < b.z
			end)
			local cars = col.cars
			rail(col.x, math.max(RB.z0 + 2.5, cars[1].z - 10.55), { cars[1] })
			for i = 1, #cars - 1 do
				rail(col.x, (cars[i].z + cars[i + 1].z) / 2, { cars[i], cars[i + 1] })
			end
			rail(col.x, math.min(RB.z1 - 0.8, cars[#cars].z + 10.55), { cars[#cars] })
		end
		local lit = 0
		for _, t in tts do
			local lens = lightFor[t] or lightBack[t]
			if lens and lit < 6 then
				D.light(lens, "SpotLight", { Face = Enum.NormalId.Front, Range = 26, Angle = 48, Brightness = 1.5, Color = C(255, 236, 214) })
				lit += 1
			end
		end
	end)
	step(K, "ceilingFixtures", function()
		-- 스프링클러 (9 스터드 격자, 막히면 건너뜀)
		local nx = math.floor((RB.x1 - RB.x0) / 9)
		local nz = math.floor((RB.z1 - RB.z0) / 9)
		for i = 0, nx do
			for j = 0, nz do
				local x = RB.x0 + 3.2 + i * 9
				local z = RB.z0 + 3.0 + j * 9
				if x < RB.x1 - 1 and z < RB.z1 - 1 and ceilFree(x - 0.3, x + 0.3, z - 0.3, z + 0.3) then
					sprinkler(D, x, yC, z)
				end
			end
		end
		-- 천장 스피커 4 + 비상등 2
		for _, p in { { -17.5, -15.5 }, { 17.0, -15.5 }, { -17.5, 15.0 }, { 17.0, 14.0 } } do
			if ceilFree(p[1] - 0.5, p[1] + 0.5, p[2] - 0.5, p[2] + 0.5) then
				D.disc("CeilSpeaker", 0.95, 0.04, CF(p[1], yC - 0.02, p[2]), L.white)
				D.disc("CeilSpeakerGrille", 0.8, 0.02, CF(p[1], yC - 0.045, p[2]), lk(C(200, 200, 198), M.Metal))
			end
		end
		for _, p in { { -30.0, 20.5 }, { 30.0, -26.0 } } do
			D.box("EmergencyLight", V3(1.1, 0.22, 0.4), CF(p[1], yC - 0.11, p[2]), L.white)
			D.box("EmergencyLightLens", V3(0.9, 0.04, 0.3), CF(p[1], yC - 0.24, p[2]), lk(C(230, 240, 255), M.Neon, { t = 0.4 }))
		end
		-- 벽시계 (상담 데스크 위)
		local dcf = D.wall("back", -22.2, 11.6, 0.0)
		local hr, mn = Props.clock(K, G.B * dcf, 1.5, { frame = L.darkAlu })
		Interact.clock(K, hr, mn, G.B * dcf, 1.5)
	end)

	-- 4.6 상담 데스크 (맵 DeskBody / DeskTop 정확히 덮기) + 데스크 소품 + 뒤 벽 --------------------------------------------
	step(K, "salesDesk", function()
		local body = G.byName.DeskBody and G.byName.DeskBody[1]
		local top = G.byName.DeskTop and G.byName.DeskTop[1]
		if not (body and top) then
			return
		end
		local bx0, bx1, bz0, bz1 = body.min.X, body.max.X, body.min.Z, body.max.Z
		local ty = top.max.Y
		local fz = bz1 -- 손님 쪽 (+Z)
		-- 앞면 세로 플루트 (네이비) — 가운데 DeskSign (라이브 보드) 자리는 비움
		local sign = G.byName.DeskSign and G.byName.DeskSign[1]
		local sx0, sx1 = (sign and sign.min.X or -24.7) - 0.15, (sign and sign.max.X or -19.6) + 0.15
		local flute = lk(C(34, 42, 60))
		local function flutes(a: number, b: number)
			local n = math.max(3, math.floor((b - a) / 0.3))
			local pw = (b - a) / n
			for i = 1, n do
				local x = a + pw * (i - 0.5)
				D.cyl("DeskFlute", body.max.Y - 0.62, pw * 0.92, CF(x, 0.55 + (body.max.Y - 0.62) / 2, fz + 0.02) * ANG(0, 0, PI / 2), flute)
			end
		end
		flutes(bx0 + 0.1, sx0)
		flutes(sx1, bx1 - 0.1)
		-- 사인 둘레 (알루미늄 프레임)
		if sign then
			D.box("DeskSignFrame", V3(sx1 - sx0, 0.08, 0.06), CF((sx0 + sx1) / 2, sign.max.Y + 0.08, fz + 0.03), L.alu)
			D.box("DeskSignFrame", V3(sx1 - sx0, 0.08, 0.06), CF((sx0 + sx1) / 2, sign.min.Y - 0.08, fz + 0.03), L.alu)
		end
		-- 상판 앞 오렌지 띠 + 옆면 대리석 판 (워터폴)
		D.box("DeskEdgeLine", V3(bx1 - bx0, 0.05, 0.04), CF((bx0 + bx1) / 2, body.max.Y - 0.12, fz + 0.03), L.orangeNeon)
		for _, ex in { bx0 - 0.02, bx1 + 0.02 } do
			D.box("DeskWaterfall", V3(0.06, body.max.Y, bz1 - bz0 + 0.2), CF(ex, body.max.Y / 2, (bz0 + bz1) / 2 + 0.05), Look.marbleWhite)
		end
		-- 상판 위 (직원 쪽 z 작은 쪽): 맵 Monitor/Keyboard 그대로, 소품 추가
		local tz = (top.min.Z + top.max.Z) / 2
		local function onTop(x: number, z: number, yaw: number?): CFrame
			return pf(x, ty, z, yaw or 0)
		end
		-- 손님용 견적 모니터 (손님 쪽으로 기울임)
		do
			local p = onTop(-19.1, tz - 0.4, 180)
			D.disc("QuoteMonitorBase", 0.7, 0.05, p * CF(0, 0.025, 0), L.darkAlu)
			D.box("QuoteMonitorNeck", V3(0.14, 0.9, 0.08), p * CF(0, 0.5, -0.05), L.darkAlu)
			local scr = p * CF(0, 1.25, 0) * ANG(math.rad(-8), PI, 0)
			D.box("QuoteMonitorBody", V3(2.1, 1.25, 0.08), scr, L.black)
			D.label("QuoteMonitorScreen", 1.98, 1.12, scr * CF(0, 0, 0.045), "견적서\n트레일 SUV · 신차\n980,000원 · 할부 10일", WHITE, C(20, 54, 110), { d = 0.01, glow = 1.2 })
		end
		-- 키보드 옆 마우스
		D.box("Mouse", V3(0.2, 0.08, 0.32), onTop(-22.9, -23.65) * CF(0, 0.04, 0), L.black)
		D.box("MousePad", V3(0.7, 0.01, 0.6), onTop(-22.9, -23.65) * CF(0, 0.005, 0), lk(C(40, 40, 46), M.Fabric))
		-- 전화기
		do
			local p = onTop(-28.2, -24.35, 20)
			D.rbox("DeskPhone", V3(0.8, 0.22, 0.7), 0.05, p * CF(0, 0.11, 0), L.black)
			D.box("DeskPhoneHandset", V3(0.22, 0.14, 0.7), p * CF(-0.24, 0.27, 0), L.black)
			D.box("DeskPhoneLCD", V3(0.3, 0.01, 0.16), p * CF(0.15, 0.225, -0.15), lk(C(150, 200, 230), M.Neon, { t = 0.3 }))
		end
		-- 카드 단말기 · 영수증 프린터 (손님 쪽)
		Props.cardTerminal(K, G.B * onTop(-20.9, top.max.Z - 0.55, 180))
		Props.receiptPrinter(K, G.B * onTop(-27.1, -24.2, 0))
		-- 카탈로그 스탠드 (맵 Brochures 상자 대신)
		local br = G.byName.Brochures and G.byName.Brochures[1]
		if br then
			hideRec(G, br)
			local p = onTop(br.c.X, br.c.Z, 0)
			D.box("BrochureStand", V3(1.8, 0.06, 0.9), p * CF(0, 0.03, 0), L.glassClear)
			local cols = { C(20, 50, 110), C(170, 40, 30), C(30, 30, 34), C(40, 110, 90) }
			local names = { "트레일 SUV", "플래그십", "패밀리 밴", "큐비" }
			for i = 1, 4 do
				local x = -0.68 + (i - 1) * 0.45
				local c = p * CF(x, 0.55, 0.1) * ANG(math.rad(-12), 0, 0)
				D.box("Brochure", V3(0.42, 0.9, 0.04), c, lk(cols[i]))
				if hi then
					D.label("BrochureTitle", 0.38, 0.22, c * CF(0, 0.22, 0.025), names[i], WHITE, nil, { d = 0.005 })
				end
			end
		end
		-- 펜꽂이 · 명함꽂이 · 서류함 · 도장 · 계산기 · 차 키 · 명패
		do
			local p = onTop(-26.3, -23.0)
			D.vcyl("PenCup", 0.4, 0.26, p * CF(0, 0.2, 0), L.darkAlu)
			for i = 0, 2 do
				D.seg("Pen", (p * CF(-0.04 + i * 0.04, 0.3, 0)).Position, (p * CF(-0.08 + i * 0.08, 0.7, 0.04)).Position, 0.04, lk(if i == 1 then C(30, 60, 160) else C(20, 20, 22)))
			end
			D.box("CardHolder", V3(0.5, 0.18, 0.3), onTop(-25.4, -22.6) * CF(0, 0.09, 0), L.glassClear)
			D.box("BusinessCards", V3(0.44, 0.12, 0.2), onTop(-25.4, -22.6) * CF(0, 0.12, 0), L.white)
			local tray = onTop(-28.0, -23.1, 8)
			D.box("DocTray", V3(1.1, 0.3, 0.8), tray * CF(0, 0.15, 0), L.black)
			D.box("DocPaper", V3(0.95, 0.12, 0.7), tray * CF(0, 0.3, 0), Look.paper)
			if hi then
				D.label("ContractTitle", 0.8, 0.5, CFrame.fromMatrix((tray * CF(0, 0.37, 0)).Position, tray.XVector, -tray.ZVector, YA), "자동차 매매 계약서", INK, nil, { d = 0.004 })
			end
			D.vcyl("Stamp", 0.4, 0.16, onTop(-27.3, -22.55) * CF(0, 0.2, 0), lk(C(150, 30, 30)))
			D.box("InkPad", V3(0.4, 0.06, 0.3), onTop(-26.9, -22.5) * CF(0, 0.03, 0), lk(C(120, 20, 20)))
			D.box("Calculator", V3(0.5, 0.06, 0.7), onTop(-24.3, -22.7, -10) * CF(0, 0.03, 0), lk(C(50, 52, 56)))
			for i = 0, 1 do
				local kp = onTop(-17.3 + i * 0.5, -22.5, 30 * i)
				D.rbox("CarKeyFob", V3(0.3, 0.1, 0.5), 0.04, kp * CF(0, 0.05, 0), L.black)
				D.disc("CarKeyLogo", 0.1, 0.01, kp * CF(0, 0.105, -0.08), L.chrome)
			end
			local np = onTop(-15.9, top.max.Z - 0.4, 180)
			D.wedge("NamePlate", V3(1.5, 0.4, 0.3), np * CF(0, 0.2, 0), L.darkAlu)
			D.label("NamePlateText", 1.4, 0.3, np * CF(0, 0.22, -0.16) * ANG(math.rad(37), PI, 0), "대표  박 사 장", WHITE, nil, { d = 0.005 })
			Props.potPlant(K, G.B * onTop(-15.9, -24.6), 0.36, 0.5, { pot = L.white })
		end
		-- 손님 의자 (맵 ChairSeat/ChairBack/ChairPost 정확히 덮기)
		for _, s in G.byName.ChairSeat or {} do
			if within(s, bx0 - 6, bx1 + 6, bz0 - 6, bz1 + 6) then
				local back = nil
				for _, b in G.byName.ChairBack or {} do
					if (b.c - s.c).Magnitude < 1.8 then
						back = b
					end
				end
				local face = ZA
				if back then
					local d = V3(s.c.X - back.c.X, 0, s.c.Z - back.c.Z)
					if d.Magnitude > 0.05 then
						face = d.Unit
					end
				end
				local p = V3(s.c.X, y0, s.c.Z)
				Props.chair(K, G.B * CFrame.lookAt(p, p - face), { style = "padded", seatTop = s.max.Y, w = 1.7, d = 1.7, backH = 1.9, frame = L.darkAlu, seat = Look.leatherBlack })
				hideRec(G, s)
				if back then
					hideRec(G, back)
				end
				for _, q in G.byName.ChairPost or {} do
					if (q.c - s.c).Magnitude < 1.4 then
						hideRec(G, q)
					end
				end
			end
		end
		-- 뒤 벽: 키 보관함 · 등록증 액자 · 크레덴자 · 서류 캐비닛
		do
			local kc = D.wall("back", -27.4, 5.6, 0.0)
			D.plate("KeyCabinet", 2.4, 2.6, 0.4, kc, L.darkAlu)
			D.plate("KeyCabinetDoor", 2.2, 2.4, 0.03, kc * CF(0, 0, 0.4), { c = C(190, 210, 220), m = M.Glass, t = 0.55, r = 0.2 })
			for i = 0, 3 do
				for j = 0, 2 do
					local kx, ky = -0.8 + i * 0.53, 0.75 - j * 0.75
					D.plate("KeyHook", 0.05, 0.12, 0.12, kc * CF(kx, ky, 0.0), L.chrome)
					D.plate("KeyTag", 0.18, 0.3, 0.03, kc * CF(kx, ky - 0.25, 0.14), lk(({ C(230, 70, 40), C(40, 120, 200), C(240, 200, 40) })[(i + j) % 3 + 1]))
				end
			end
			D.label("KeyCabinetLabel", 2.2, 0.3, kc * CF(0, 1.5, 0.05), "시승차 키 보관함", INK, C(246, 246, 242), { d = 0.01 })
			local texts = { "사업자등록증\n\n광안 오토 정비소 & 중고차\n\n국세청", "자동차매매업\n등록증\n\n부산광역시 수영구청장", "성능·상태점검\n지정증\n\n국토교통부" }
			for i, tx in texts do
				Props.frame(K, G.B * D.wall("back", -34.0 + (i - 1) * 1.55, 6.7, 0.0), 1.3, 1.75, { frame = Look.goldMetal, text = tx, fg = C(40, 40, 40), textH = 0.9, border = 0.06, depth = 0.05 })
			end
			-- 크레덴자 (뒤 벽, 직원 자리 왼쪽)
			local cp = D.wallPf("back", -27.6, 1.5)
			if spot(G, cp, V3(4.6, 2.9, 1.5), 0, "credenza") then
				propGroup(G, "credenza", V3(-29.9, 0, RB.z0), V3(-25.3, 3.4, RB.z0 + 1.5), function()
					D.box("Credenza", V3(4.6, 2.6, 1.5), cp * CF(0, 1.4, 0), L.white)
					D.box("CredenzaPlinth", V3(4.4, 0.1, 1.4), cp * CF(0, 0.05, -0.02), L.black)
					D.box("CredenzaTop", V3(4.7, 0.12, 1.55), cp * CF(0, 2.76, 0), Look.walnut)
					for i = 1, 2 do
						D.box("CredenzaDoorLine", V3(0.03, 2.4, 0.02), cp * CF(-2.3 + 4.6 * i / 3, 1.4, 0.755), lk(C(200, 200, 198)))
					end
					for i = 0, 2 do
						D.box("CredenzaHandle", V3(0.5, 0.05, 0.05), cp * CF(-1.53 + i * 1.53, 2.3, 0.78), L.darkAlu)
					end
					-- 복합기
					local mp = cp * CF(-0.9, 2.82, 0)
					D.box("Printer", V3(1.7, 0.9, 1.2), mp * CF(0, 0.45, 0), L.white)
					D.box("PrinterLid", V3(1.7, 0.12, 1.2), mp * CF(0, 0.96, 0), lk(C(60, 62, 66)))
					D.box("PrinterTray", V3(1.2, 0.05, 0.5), mp * CF(0, 0.55, 0.75), lk(C(220, 220, 216)))
					D.box("PrinterPanel", V3(0.5, 0.05, 0.25), mp * CF(0.5, 1.03, 0.4), lk(C(100, 160, 210), M.Neon, { t = 0.3 }))
					-- 파일 박스
					for i = 0, 2 do
						D.box("Binder", V3(0.3, 0.95, 1.0), cp * CF(0.8 + i * 0.32, 3.3, 0), lk(({ NAVY, ORANGE, C(240, 240, 236) })[i + 1]))
					end
				end)
			end
			local fp = pf(RB.x0 + 0.85, y0, RB.z0 + 0.85, 0)
			if spot(G, fp, V3(1.6, 3.4, 1.6), 0, "fileCabinet") then
				propGroup(G, "fileCabinet", V3(RB.x0, 0, RB.z0), V3(RB.x0 + 1.7, 3.4, RB.z0 + 1.7), function()
					D.box("FileCabinet", V3(1.5, 3.3, 1.5), fp * CF(0, 1.65, 0), lk(C(70, 74, 80), M.Metal))
					for i = 0, 2 do
						D.box("FileDrawerLine", V3(1.4, 0.03, 0.02), fp * CF(0, 1.1 * (i + 1), 0.76), L.black)
						D.box("FileDrawerHandle", V3(0.5, 0.06, 0.06), fp * CF(0, 1.1 * i + 0.85, 0.78), L.chrome)
					end
				end)
			end
			-- 데스크 위 '구매 상담' 간판 (벽)
			D.label("SalesHeader", 9.0, 0.95, D.wall("back", -22.2, 9.5, 0.03), "구매 상담 · 렌트 · 할부 · 내 차 팔기", NAVY, nil, { d = 0.02, font = Enum.Font.GothamBlack })
			D.plate("SalesHeaderLine", 9.0, 0.06, 0.05, D.wall("back", -22.2, 8.9, 0.03), L.orangeNeon)
		end
	end)

	-- 4.7 고객 라운지: 소파 · 테이블 · 정수기 (맵 자리 정확히) + 커피 스테이션 · 음료 냉장고 · 잡지꽂이 · 펜던트 ---------------------------------
	step(K, "lounge", function()
		local sofa = G.byName.Sofa and G.byName.Sofa[1]
		local sback = G.byName.SofaBack and G.byName.SofaBack[1]
		if sofa then
			local x0, x1 = sofa.min.X, sofa.max.X
			local z0, z1 = (sback and sback.min.Z or sofa.min.Z), sofa.max.Z
			local seatTop = sofa.max.Y
			local backTop = sback and sback.max.Y or seatTop + 2
			local fab = lk(C(88, 90, 96), M.Fabric)
			local fabD = lk(C(70, 72, 78), M.Fabric)
			local arm = 0.65
			D.box("SofaPlinth", V3(x1 - x0 - 0.3, 0.28, z1 - z0 - 0.3), CF((x0 + x1) / 2, 0.14, (z0 + z1) / 2), L.black)
			D.box("SofaBase", V3(x1 - x0, seatTop - 0.62 - 0.28, z1 - z0), CF((x0 + x1) / 2, 0.28 + (seatTop - 0.9) / 2, (z0 + z1) / 2), fabD)
			local sx0, sx1 = x0 + arm, x1 - arm
			local n = math.max(2, math.floor((sx1 - sx0) / 3.0 + 0.5))
			local cw = (sx1 - sx0) / n
			local bz = z0 + 0.62
			for i = 1, n do
				local cx = sx0 + cw * (i - 0.5)
				D.rbox("SofaSeatCushion", V3(cw - 0.06, 0.62, z1 - bz), 0.14, CF(cx, seatTop - 0.31, (bz + z1) / 2), fab)
				D.rbox("SofaBackCushion", V3(cw - 0.08, backTop - seatTop - 0.2, 0.62), 0.16, CF(cx, (seatTop + backTop) / 2 - 0.05, z0 + 0.5) * ANG(math.rad(-7), 0, 0), fab)
			end
			D.box("SofaBackFrame", V3(x1 - x0, backTop - 0.28, 0.32), CF((x0 + x1) / 2, 0.28 + (backTop - 0.28) / 2, z0 + 0.16), fabD)
			for _, ax in { x0 + arm / 2, x1 - arm / 2 } do
				D.rbox("SofaArm", V3(arm, seatTop + 0.75 - 0.28, z1 - z0), 0.18, CF(ax, 0.28 + (seatTop + 0.75 - 0.28) / 2, (z0 + z1) / 2), fabD)
			end
			-- 쿠션 2
			D.rbox("ThrowPillow", V3(1.3, 1.2, 0.36), 0.2, CF(sx0 + 0.9, seatTop + 0.62, z0 + 0.98) * ANG(math.rad(-14), math.rad(14), math.rad(6)), lk(ORANGE, M.Fabric))
			D.rbox("ThrowPillow", V3(1.3, 1.2, 0.36), 0.2, CF(sx1 - 0.9, seatTop + 0.62, z0 + 0.98) * ANG(math.rad(-14), math.rad(-12), math.rad(-6)), lk(C(226, 216, 196), M.Fabric))
			hideRec(G, sofa)
			if sback then
				hideRec(G, sback)
			end
			reserveB(G, V3(x0, 0, z0), V3(x1, backTop, z1), "sofa")
		end
		local ct = G.byName.CoffeeTable and G.byName.CoffeeTable[1]
		if ct then
			local cx, cz = ct.c.X, ct.c.Z
			local w, d, h = ct.size.X, ct.size.Z, ct.max.Y
			D.slab("CoffeeTableTop", w, d, 0.1, 0.25, CF(cx, h - 0.05, cz), { c = C(40, 44, 50), m = M.Glass, t = 0.25, r = 0.2 })
			D.slab("CoffeeTableShelf", w - 0.4, d - 0.4, 0.08, 0.2, CF(cx, 0.45, cz), Look.walnut)
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					D.box("CoffeeTableLeg", V3(0.1, h - 0.1, 0.1), CF(cx + sx * (w / 2 - 0.25), (h - 0.1) / 2, cz + sz * (d / 2 - 0.25)), L.black)
				end
			end
			-- 카탈로그 · 잡지 (맵 Magazine 대신) + 휴지 · 작은 화분
			hideNamed(G, "Magazine")
			local mags = { { -1.6, 0.1, 12, C(20, 50, 110), "2026 카탈로그" }, { -0.4, -0.2, -8, C(240, 238, 230), "CAR LIFE" }, { -0.9, 0.3, 30, C(170, 54, 20), "중고차 시세" } }
			for i, m in mags do
				local p = CF(cx + m[1], h + 0.02 + i * 0.02, cz + m[2]) * ANG(0, math.rad(m[3]), 0)
				D.box("Magazine", V3(1.3, 0.03, 1.7), p, lk(m[4]))
				if hi then
					D.label("MagazineTitle", 1.1, 0.4, CFrame.fromMatrix((p * CF(0, 0.02, -0.5)).Position, p.XVector, -p.ZVector, YA), m[5], if i == 2 then INK else WHITE, nil, { d = 0.003 })
				end
			end
			Props.napkinBox(K, G.B * pf(cx + 1.4, h, cz - 0.3, 10))
			Props.potPlant(K, G.B * pf(cx + 2.3, h, cz + 0.3), 0.42, 0.55, { pot = lk(C(60, 62, 66), M.Concrete) })
			reserveB(G, ct.min, ct.max + V3(0, 1, 0), "coffeeTable")
		end
		-- 정수기 (맵 WaterPurifier 상자 정확히)
		local wp = G.byName.WaterPurifier and G.byName.WaterPurifier[1]
		if wp then
			hideRec(G, wp)
			local p = pf(wp.c.X, 0, wp.c.Z, 0)
			local w, d, h = wp.size.X, wp.size.Z, wp.max.Y
			D.rbox("PurifierBody", V3(w, h, d), 0.12, p * CF(0, h / 2, 0), lk(C(244, 244, 242)))
			D.box("PurifierFront", V3(w - 0.3, h * 0.42, 0.04), p * CF(0, h * 0.62, d / 2), lk(C(60, 64, 70)))
			D.box("PurifierNiche", V3(w - 0.6, 1.1, 0.3), p * CF(0, 1.55, d / 2 - 0.12), lk(C(30, 32, 36)))
			D.box("PurifierTapCold", V3(0.16, 0.24, 0.2), p * CF(-0.3, 2.0, d / 2 - 0.08), lk(C(60, 130, 220)))
			D.box("PurifierTapHot", V3(0.16, 0.24, 0.2), p * CF(0.3, 2.0, d / 2 - 0.08), lk(C(210, 50, 40)))
			D.box("PurifierTray", V3(w - 0.6, 0.06, 0.4), p * CF(0, 1.02, d / 2 - 0.1), L.chrome)
			D.label("PurifierPanel", w - 0.4, 0.5, p * CF(0, 3.1, d / 2 + 0.03), "냉수 · 정수 · 온수", C(200, 230, 255), nil, { d = 0.01, glow = 1.1 })
			D.vcyl("CupDispenser", 1.2, 0.3, p * CF(w / 2 + 0.18, 2.4, 0), L.glassClear)
			D.vcyl("CupStack", 1.0, 0.24, p * CF(w / 2 + 0.18, 2.4, 0), L.white)
			reserveB(G, wp.min - V3(0, 0, 0), wp.max + V3(0.5, 0, 0), "purifier")
		end
		-- 잡지꽂이 (소파 끝과 정수기 사이)
		do
			local x = 27.0
			if sofa and wp then
				x = (sofa.max.X + wp.min.X) / 2
			end
			local p = D.wallPf("back", x, 0.9)
			if spot(G, p, V3(1.7, 3.0, 0.9), 0, "magRack") then
				propGroup(G, "magRack", V3(x - 0.9, 0, RB.z0), V3(x + 0.9, 3, RB.z0 + 0.9), function()
					for _, sx in { -1, 1 } do
						D.box("MagRackSide", V3(0.08, 3.0, 0.8), p * CF(sx * 0.8, 1.5, 0), L.darkAlu)
					end
					for i = 0, 2 do
						local yy = 0.6 + i * 0.9
						D.box("MagRackShelf", V3(1.6, 0.06, 0.5), p * CF(0, yy, 0.05) * ANG(math.rad(-18), 0, 0), L.darkAlu)
						D.box("MagRackLip", V3(1.6, 0.18, 0.04), p * CF(0, yy + 0.08, 0.3), L.darkAlu)
						for k = 0, 1 do
							local mc = ({ C(20, 50, 110), C(200, 70, 30), C(230, 230, 222), C(40, 110, 80), C(30, 30, 34), C(180, 160, 120) })[i * 2 + k + 1]
							D.box("RackMagazine", V3(0.66, 0.85, 0.04), p * CF(-0.38 + k * 0.76, yy + 0.4, 0.1) * ANG(math.rad(-18), 0, 0), lk(mc))
						end
					end
				end)
			end
		end
		-- 커피 스테이션 (오른쪽 벽)
		local cz0, cz1 = -25.45, -21.05
		local sc = (cz0 + cz1) / 2
		local cpcf = D.wallPf("right", sc, 2.0)
		if spot(G, cpcf, V3(cz1 - cz0, 2.95, 2.0), 0, "coffee") then
			propGroup(G, "coffee", V3(RB.x1 - 2, 0, cz0), V3(RB.x1, 6.6, cz1), function()
				local wlen = cz1 - cz0
				D.box("CoffeeCabinet", V3(wlen, 2.7, 1.9), cpcf * CF(0, 1.45, -0.05), lk(C(246, 246, 244)))
				D.box("CoffeePlinth", V3(wlen - 0.1, 0.12, 1.8), cpcf * CF(0, 0.06, -0.1), L.black)
				D.box("CoffeeTop", V3(wlen + 0.1, 0.12, 2.0), cpcf * CF(0, 2.86, 0), Look.oak)
				for i = 1, 2 do
					D.box("CoffeeDoorLine", V3(0.03, 2.5, 0.02), cpcf * CF(-wlen / 2 + wlen * i / 3, 1.45, 0.9), lk(C(206, 206, 204)))
				end
				D.box("CoffeeHandleGroove", V3(wlen, 0.06, 0.03), cpcf * CF(0, 2.65, 0.9), lk(C(60, 60, 64)))
				-- 벽 백스플래시 + 선반 + 간판
				local wb = D.wall("right", sc, 4.55, 0.0)
				D.plate("CoffeeSplash", wlen, 3.2, 0.06, wb, L.navyMatte)
				D.label("CoffeeSign", wlen - 0.4, 0.6, wb * CF(0, 1.15, 0.07), "COFFEE · 무료 음료", C(245, 238, 226), nil, { d = 0.01, font = Enum.Font.GothamBlack, glow = 1.1 })
				local sh = Props.shelf(K, G.B * D.wall("right", sc, 5.0, 0.06), wlen - 0.6, { depth = 0.7, look = Look.oak })
				Props.row(K, sh * CF(-0.9, 0, -0.1), 1.6, "cups", { colors = { C(250, 250, 248), C(30, 30, 32) }, n = 4 })
				Props.row(K, sh * CF(1.0, 0, -0.1), 1.6, "jars", { colors = { C(110, 70, 40), C(240, 230, 210), C(60, 40, 30) }, n = 3 })
				-- 캡슐 커피머신
				local mp = cpcf * CF(-0.9, 2.92, 0.2)
				D.rbox("CoffeeMachine", V3(0.9, 1.3, 1.2), 0.1, mp * CF(0, 0.65, 0), L.black)
				D.box("CoffeeMachineTop", V3(0.92, 0.08, 1.22), mp * CF(0, 1.32, 0), L.chrome)
				D.box("CoffeeSpout", V3(0.3, 0.14, 0.3), mp * CF(0, 0.85, 0.62), L.chrome)
				D.box("CoffeeDripTray", V3(0.7, 0.06, 0.4), mp * CF(0, 0.1, 0.72), L.chrome)
				local led = D.box("CoffeeLED", V3(0.3, 0.04, 0.02), mp * CF(0, 1.15, 0.61), lk(C(255, 200, 120), M.Neon))
				D.vcyl("CoffeeWaterTank", 1.0, 0.34, mp * CF(0, 0.6, -0.55), { c = C(200, 220, 230), m = M.Glass, t = 0.5 })
				local cup = D.vcyl("CoffeeCup", 0.32, 0.3, mp * CF(0, 0.29, 0.72), L.white)
				cup.Transparency = 1
				local crema = D.disc("CoffeeCrema", 0.24, 0.02, mp * CF(0, 0.45, 0.72), lk(C(150, 100, 60)))
				crema.Transparency = 1
				local steam = {}
				for i = 0, 2 do
					local s = D.ell("CoffeeSteam", V3(0.18, 0.4, 0.18), mp * CF((i - 1) * 0.05, 0.75 + i * 0.25, 0.72), { c = WHITE, m = M.SmoothPlastic, t = 1 })
					table.insert(steam, s)
				end
				-- 캡슐 진열대 + 종이컵 + 스틱
				local rp = cpcf * CF(0.4, 2.92, 0.1)
				D.box("CapsuleRack", V3(0.9, 1.1, 0.5), rp * CF(0, 0.55, 0), L.glassClear)
				for i = 0, 3 do
					for j = 0, 2 do
						D.disc("Capsule", 0.2, 0.08, rp * CF(-0.3 + j * 0.3, 0.2 + i * 0.25, 0.1) * ANG(PI / 2, 0, 0), lk(({ C(40, 20, 80), C(200, 160, 40), C(160, 30, 30), C(30, 110, 60) })[i + 1], M.Metal))
					end
				end
				D.vcyl("PaperCups", 1.0, 0.3, cpcf * CF(1.3, 3.42, 0.3), L.white)
				D.vcyl("StirrerCup", 0.4, 0.3, cpcf * CF(1.7, 3.12, 0.4), L.darkAlu)
				D.box("SugarTray", V3(0.6, 0.15, 0.4), cpcf * CF(1.6, 2.99, -0.3), L.white)
				D.label("CupReturn", 0.9, 0.3, cpcf * CF(1.5, 1.8, 0.91), "컵 반납", INK, C(246, 246, 244), { d = 0.01 })
				-- 상호작용: 커피 내리기
				local busy = false
				prompt(G, led, {
					action = "커피 내리기",
					object = "캡슐 커피머신 (무료)",
					fn = function()
						if busy then
							return
						end
						busy = true
						cup.Transparency = 0
						crema.Transparency = 1
						led.Color = C(120, 255, 140)
						task.spawn(function()
							for k = 1, 12 do
								for i, s in steam do
									if s.Parent then
										s.Transparency = 0.55 + 0.3 * math.abs(math.sin(k * 0.7 + i))
									end
								end
								task.wait(0.25)
							end
							for _, s in steam do
								if s.Parent then
									s.Transparency = 1
								end
							end
							if crema.Parent then
								crema.Transparency = 0
							end
							if led.Parent then
								led.Color = C(255, 200, 120)
							end
							busy = false
						end)
					end,
				})
			end)
		end
		-- 음료 냉장고 (오른쪽 벽, 커피 스테이션 옆)
		local fz = -19.35
		local fpcf = D.wallPf("right", fz, 2.1)
		if spot(G, fpcf * CF(0, 0, 0.05), V3(2.45, 6.2, 2.1), 0, "fridge") then
			propGroup(G, "fridge", V3(RB.x1 - 2.2, 0, fz - 1.3), V3(RB.x1, 6.2, fz + 1.3), function()
				local out = Props.showcaseFridge(K, G.B * fpcf, { doors = 1, h = 6.0, d = 2.0, header = "음료 · 무료 시음", headerBg = NAVY })
				for _, m in out.doors do
					local hinge = m:GetAttribute("Hinge")
					if typeof(hinge) == "Vector3" then
						Interact.swing(K, m, hinge, Vector3.yAxis, math.rad(-100), { object = "음료 냉장고", openText = "문 열기", closeText = "문 닫기" })
					end
				end
			end)
		end
		-- 펜던트 3 (테이블 위)
		if ct then
			for i = -1, 1 do
				local px = ct.c.X + i * 2.1
				local bulb = Props.pendant(K, G.B * V3(px, yC, ct.c.Z), 4.6, { shade = "dome", dia = 1.3, look = Look.blackMetal, light = (i == 0), range = 14, bright = 0.8 })
				local _ = bulb
			end
		end
		-- 화분 (맵 PlantPot/Plant 자리)
		for idx, r in G.byName.PlantPot or {} do
			hideRec(G, r)
			for _, q in G.byName.Plant or {} do
				if math.abs(q.c.X - r.c.X) < 1 and math.abs(q.c.Z - r.c.Z) < 1 then
					hideRec(G, q)
				end
			end
			Props.floorPlant(K, G.B * pf(r.c.X, 0, r.c.Z, 0), { kind = if idx % 2 == 1 then "olive" else "monstera", h = 5.4, dia = 1.6, pot = lk(C(52, 54, 58), M.Concrete) })
		end
		-- TV (라이브 보드) 둘레 슬림 베젤 + 사운드바
		local tv = G.byName.LoungeTV and G.byName.LoungeTV[1]
		if tv then
			local cx, cy = tv.c.X, tv.c.Y
			local w, h = tv.size.X, tv.size.Y
			for _, s in { -1, 1 } do
				D.plate("TVBezel", w + 0.24, 0.12, 0.26, D.wall("back", cx, cy + s * (h / 2 + 0.06), 0.0), L.black)
				D.plate("TVBezel", 0.12, h, 0.26, D.wall("back", cx + s * (w / 2 + 0.06), cy, 0.0), L.black)
			end
			D.rbox("Soundbar", V3(4.6, 0.32, 0.4), 0.12, CF(cx, cy - h / 2 - 0.5, RB.z0 + 0.25), L.black)
		end
	end)

	-- 4.8 상담 테이블 2 세트 (브랜드 월 앞) -------------------------------------------------------------
	step(K, "consultTables", function()
		for i, tx in { -10.4, 3.6 } do
			local tz = -24.4
			local p = pf(tx, y0, tz, 0)
			if spot(G, p, V3(6.2, 3.4, 6.0), 0, "consult") then
				propGroup(G, "consult" .. i, V3(tx - 3.1, 0, tz - 3), V3(tx + 3.1, 3.4, tz + 3), function()
					local th = 3.0
					D.disc("ConsultTop", 3.0, 0.12, p * CF(0, th - 0.06, 0), Look.marbleWhite)
					D.disc("ConsultEdge", 2.96, 0.06, p * CF(0, th - 0.15, 0), L.darkAlu)
					D.vcyl("ConsultColumn", th - 0.3, 0.3, p * CF(0, (th - 0.3) / 2 + 0.08, 0), L.darkAlu)
					D.disc("ConsultFoot", 1.8, 0.08, p * CF(0, 0.04, 0), L.darkAlu)
					for k, a in { 0, 125, 235 } do
						local rad = math.rad(a)
						local cx, cz = tx + math.sin(rad) * 2.15, tz + math.cos(rad) * 2.15
						local cp = V3(cx, y0, cz)
						Props.chair(K, G.B * CFrame.lookAt(cp, cp + V3(math.sin(rad), 0, math.cos(rad))), { style = "padded", seatTop = 1.95, w = 1.6, d = 1.55, backH = 1.8, frame = L.darkAlu, seat = if k == 1 then lk(C(214, 206, 192), M.Leather) else lk(C(120, 122, 128), M.Fabric) })
					end
					-- 테이블 위: 태블릿 · 카탈로그 · 펜
					local tp = p * CF(-0.35, th, 0.2) * ANG(0, math.rad(20), 0)
					D.box("ConsultTabletStand", V3(0.5, 0.06, 0.4), tp * CF(0, 0.03, 0), L.darkAlu)
					local scr = tp * CF(0, 0.45, 0) * ANG(math.rad(-20), 0, 0)
					D.box("ConsultTablet", V3(0.95, 0.68, 0.05), scr, L.black)
					D.label("ConsultTabletScreen", 0.86, 0.6, scr * CF(0, 0, 0.03), "차량 비교\n큐비 · 미드 세단 · SUV", WHITE, C(30, 70, 140), { d = 0.005, glow = 1.1 })
					D.box("ConsultCatalog", V3(0.9, 0.04, 1.2), p * CF(0.5, th + 0.02, -0.25) * ANG(0, math.rad(-15), 0), lk(C(20, 50, 110)))
					D.seg("ConsultPen", (p * CF(0.2, th + 0.03, 0.55)).Position, (p * CF(0.65, th + 0.03, 0.62)).Position, 0.04, L.black)
				end)
			end
		end
	end)

	-- 4.9 왼쪽 벽: 상담실 유리 파티션 (가짜 문 자리) · 컬러 샘플 보드 + 미니어처 · 점검기록부 · 용품 쇼케이스 ------------------------------
	step(K, "officeGlass", function()
		local leaf, cas = nil, nil
		for _, r in G.byName.DoorLeaf or {} do
			if r.c.X < RB.x0 + 1 then
				leaf = r
			end
		end
		for _, r in G.byName.DoorCasing or {} do
			if r.c.X < RB.x0 + 1 then
				cas = r
			end
		end
		local dz0, dz1 = -21.07, -17.67
		if cas then
			dz0, dz1 = cas.min.Z, cas.max.Z
			hideRec(G, cas)
		end
		if leaf then
			hideRec(G, leaf)
		end
		hideNamed(G, "Sign_상담실 · 계약")
		local pz0, pz1 = dz0 - 6.0, dz1 + 3.4
		local top = 8.2
		local base = function(z: number, y: number, off: number): CFrame
			return D.wall("left", z, y, off)
		end
		-- 블라인드 (벽에 붙은 흰 판 + 세로 슬랫), 유리 (반투명), 프로스트 띠, 알루미늄 프레임
		local mid = (pz0 + pz1) / 2
		local len = pz1 - pz0
		D.plate("OfficeBlind", len, top - 0.7, 0.02, base(mid, 0.35 + (top - 0.7) / 2 + 0.35, 0.03), lk(C(226, 226, 222), M.Fabric))
		local ns = math.floor(len / 0.32)
		for i = 1, ns do
			local z = pz0 + len * i / (ns + 1)
			if z < dz0 - 0.1 or z > dz1 + 0.1 then
				D.plate("OfficeBlindSlat", 0.05, top - 0.8, 0.03, base(z, top / 2 + 0.3, 0.05), lk(C(206, 206, 202)))
			end
		end
		local glow = D.plate("OfficeGlow", len - 0.4, 0.06, 0.02, base(mid, top - 0.25, 0.06), lk(C(255, 244, 226), M.Neon))
		D.plate("OfficeGlass", len, top - 0.7, 0.03, base(mid, 0.35 + (top - 0.7) / 2 + 0.35, 0.22), L.glassClear)
		D.plate("OfficeFrostBand", len, 1.6, 0.02, base(mid, 2.6, 0.25), { c = C(244, 246, 246), m = M.Glass, t = 0.25 })
		D.plate("OfficeFrostLine", len, 0.06, 0.025, base(mid, 4.4, 0.25), lk(ORANGE))
		D.plate("OfficeHeadRail", len + 0.2, 0.3, 0.3, base(mid, top, 0.0), L.alu)
		D.plate("OfficeSillRail", len + 0.2, 0.3, 0.3, base(mid, 0.6, 0.0), L.alu)
		local nm = math.floor(len / 3.2)
		for i = 0, nm do
			local z = pz0 + len * i / nm
			if z < dz0 - 0.2 or z > dz1 + 0.2 then
				D.plate("OfficeMullion", 0.14, top - 0.6, 0.3, base(z, top / 2 + 0.3, 0.0), L.alu)
			end
		end
		-- 유리문 (가짜 문 자리): 프로스트 전면 + 손잡이 + 상하 패치
		local dm = (dz0 + dz1) / 2
		for _, z in { dz0, dz1 } do
			D.plate("OfficeDoorJamb", 0.14, 7.6, 0.32, base(z, 3.8, 0.0), L.alu)
		end
		D.plate("OfficeDoorGlass", dz1 - dz0 - 0.2, 7.3, 0.05, base(dm, 3.75, 0.24), { c = C(232, 238, 240), m = M.Glass, t = 0.3, r = 0.1 })
		D.plate("OfficeDoorPatch", dz1 - dz0 - 0.2, 0.3, 0.08, base(dm, 0.25, 0.22), L.steel)
		D.plate("OfficeDoorPatch", dz1 - dz0 - 0.2, 0.3, 0.08, base(dm, 7.3, 0.22), L.steel)
		D.bar("OfficeDoorPull", base(dz1 - 0.45, 2.6, 0.5).Position, base(dz1 - 0.45, 5.0, 0.5).Position, 0.1, 0.1, L.steel)
		for _, y in { 2.6, 5.0 } do
			D.seg("OfficeDoorPullPost", (base(dz1 - 0.45, y, 0.29)).Position, (base(dz1 - 0.45, y, 0.5)).Position, 0.06, L.steel)
		end
		D.label("OfficeDoorSign", 2.6, 0.7, base(dm, 5.6, 0.3), "상담실 · 계약", NAVY, nil, { d = 0.01, font = Enum.Font.GothamBlack })
		D.label("OfficeDoorSub", 2.6, 0.3, base(dm, 5.05, 0.3), "CONSULTING ROOM", C(110, 112, 118), nil, { d = 0.01 })
		D.label("OfficeGlassText", 5.0, 0.6, base(pz0 + 3.0, 2.6, 0.28), "상담 · 계약 · 출고 안내", C(90, 94, 100), nil, { d = 0.005 })
		local _ = glow
	end)
	step(K, "colorBoard", function()
		local bz = -9.6
		local bc = D.wall("left", bz, 5.0, 0.0)
		D.plate("ColorBoard", 5.6, 3.4, 0.12, bc, L.white)
		D.label("ColorBoardHead", 5.6, 0.6, bc * CF(0, 1.4, 0.13), "컬러 · 내장재 샘플", WHITE, NAVY, { d = 0.01, font = Enum.Font.GothamBlack })
		for i, pnt in PAINTS do
			local col = (i - 1) % 4
			local row = math.floor((i - 1) / 4)
			local c = bc * CF(-2.05 + col * 1.37, 0.55 - row * 0.95, 0.13)
			D.plate("PaintChip", 1.0, 0.5, 0.04, c * CF(0, 0.12, 0), lk(pnt[2], M.SmoothPlastic, { r = 0.15 }))
			D.label("PaintChipName", 1.0, 0.24, c * CF(0, -0.27, 0.01), pnt[1], INK, nil, { d = 0.005 })
		end
		local mats = { { "블랙 가죽", Look.leatherBlack }, { "베이지 가죽", lk(C(206, 190, 164), M.Leather) }, { "그레이 직물", lk(C(120, 122, 126), M.Fabric) } }
		for i, m in mats do
			local c = bc * CF(-1.9 + (i - 1) * 1.9, -1.2, 0.13)
			D.plate("TrimSwatch", 1.5, 0.5, 0.06, c, m[2])
			D.label("TrimSwatchName", 1.5, 0.22, c * CF(0, -0.38, 0.01), m[1], INK, nil, { d = 0.005 })
		end
		-- 미니어처 차 (컬러 미리보기) 받침대
		local pp = D.wallPf("left", bz, 1.3)
		if spot(G, pp, V3(1.4, 2.7, 1.3), 0, "miniCar") then
			propGroup(G, "miniCar", V3(RB.x0, 0, bz - 0.8), V3(RB.x0 + 1.4, 3.6, bz + 0.8), function()
				D.box("MiniPlinth", V3(1.4, 2.4, 1.25), pp * CF(0, 1.2, 0), L.white)
				D.box("MiniPlinthTop", V3(1.5, 0.08, 1.35), pp * CF(0, 2.44, 0), L.darkAlu)
				D.box("MiniCase", V3(1.4, 1.0, 1.25), pp * CF(0, 2.98, 0), { c = C(230, 240, 244), m = M.Glass, t = 0.82, r = 0.2 })
				local cp = pp * CF(0, 2.48, 0) * ANG(0, PI / 2, 0)
				local body = {}
				table.insert(body, D.rbox("MiniCarBody", V3(1.1, 0.22, 0.48), 0.06, cp * CF(0, 0.2, 0), lk(PAINTS[5][2], M.SmoothPlastic, { r = 0.2 }))[1])
				table.insert(body, D.rbox("MiniCarCabin", V3(0.6, 0.18, 0.42), 0.07, cp * CF(-0.05, 0.38, 0), lk(PAINTS[5][2], M.SmoothPlastic, { r = 0.2 }))[1])
				D.box("MiniCarGlass", V3(0.58, 0.12, 0.43), cp * CF(-0.05, 0.38, 0), { c = C(30, 34, 40), m = M.Glass, t = 0.2 })
				for _, sx in { -1, 1 } do
					for _, sz in { -1, 1 } do
						D.cyl("MiniCarWheel", 0.08, 0.2, cp * CF(sx * 0.36, 0.1, sz * 0.24) * ANG(0, PI / 2, 0), L.black)
					end
				end
				local _, lab = D.label("MiniCarLabel", 1.2, 0.3, pp * CF(0, 1.9, 0.64), "네이비", INK, C(246, 246, 242), { d = 0.01 })
				local plinthTop = D.box("MiniCarButton", V3(0.3, 0.05, 0.2), pp * CF(0.45, 2.49, 0.45), lk(ORANGE, M.Neon))
				-- 상호작용: 컬러 바꾸기
				local bodyParts = {}
				for _, b in K.parts do
					if b.Name == "MiniCarBody" or b.Name == "MiniCarCabin" then
						table.insert(bodyParts, b)
					end
				end
				Interact.cycle(K, plinthTop, PAINTS, {
					action = "컬러 바꾸기",
					object = "미니어처 컬러 미리보기",
					start = 5,
					on = function(_i: number, item: any)
						for _, b in bodyParts do
							if b.Parent then
								b.Color = item[2]
							end
						end
						lab.Text = item[1]
					end,
				})
			end)
		end
	end)
	step(K, "leftWall", function()
		-- 점검기록부 · 등록 안내 게시판
		local c1 = D.wall("left", -2.0, 5.2, 0.0)
		D.plate("RecordBoard", 4.6, 3.6, 0.1, c1, L.alu)
		D.plate("RecordBoardFace", 4.4, 3.4, 0.02, c1 * CF(0, 0, 0.1), lk(C(248, 248, 244)))
		D.label("RecordBoardHead", 4.4, 0.55, c1 * CF(0, 1.42, 0.12), "중고자동차 성능·상태 점검기록부 게시", WHITE, C(30, 90, 60), { d = 0.01 })
		for i = 0, 3 do
			local sc = c1 * CF(-1.6 + i * 1.07, -0.25, 0.12)
			D.plate("RecordSheet", 0.9, 1.25, 0.01, sc, Look.paper)
			if hi then
				D.label("RecordSheetText", 0.8, 1.1, sc * CF(0, 0, 0.012), "점검기록부\n차량 " .. ({ "큐비", "미드 세단", "트레일 SUV", "1톤 트럭" })[i + 1] .. "\n주행 · 사고 · 침수\n이상 없음", INK, nil, { d = 0.004, font = Enum.Font.Gotham })
			end
		end
		D.label("RecordBoardFoot", 4.4, 0.3, c1 * CF(0, -1.45, 0.12), "모든 중고차는 성능점검을 마친 뒤 판매합니다", C(80, 84, 90), nil, { d = 0.01 })
		-- 할부 · 렌트 라이트박스
		local c2 = D.wall("left", 5.2, 5.6, 0.0)
		D.plate("Lightbox", 3.6, 5.0, 0.3, c2, L.darkAlu)
		local lbp = D.label("LightboxFace", 3.4, 4.8, c2 * CF(0, 0, 0.3), "할부 OK\n\n선수금 30%\n10일 분할\n\n렌트 큐비 하루\n20,000원", WHITE, C(200, 70, 28), { d = 0.02, glow = 1.15, font = Enum.Font.GothamBlack })
		local _ = lbp
		-- 위쪽 대형 그래픽 띠
		D.label("LeftWallGraphic", 26, 1.4, D.wall("left", -2.0, 11.2, 0.03), "SINCE 2008  ·  광안리 바닷가 옆 믿을 수 있는 자동차 매장", C(60, 66, 80), nil, { d = 0.02, font = Enum.Font.GothamBold })
		-- 소화전 위 비상벨 · 스위치 옆 안내 (맵 스위치 피함)
		Props.fireBell(K, G.B * D.wall("left", 17.6, 4.6, 0.0))
		-- 용품 쇼케이스 (왼쪽 벽 앞쪽)
		local sz0, sz1 = 10.6, 15.8
		local sp = D.wallPf("left", (sz0 + sz1) / 2, 1.4)
		if spot(G, sp, V3(sz1 - sz0, 4.4, 1.4), 0, "accessory") then
			propGroup(G, "accessory", V3(RB.x0, 0, sz0), V3(RB.x0 + 1.4, 4.4, sz1), function()
				local w = sz1 - sz0
				D.box("ShowcaseBase", V3(w, 1.1, 1.35), sp * CF(0, 0.55, 0), L.white)
				D.box("ShowcaseKick", V3(w - 0.1, 0.15, 1.3), sp * CF(0, 0.075, -0.02), L.black)
				D.box("ShowcaseGlass", V3(w, 3.0, 1.3), sp * CF(0, 2.6, 0), { c = C(226, 238, 242), m = M.Glass, t = 0.8, r = 0.2 })
				D.box("ShowcaseTop", V3(w + 0.05, 0.15, 1.4), sp * CF(0, 4.17, 0), L.white)
				D.box("ShowcaseBack", V3(w, 3.0, 0.04), sp * CF(0, 2.6, -0.62), L.navyMatte)
				D.box("ShowcaseLED", V3(w - 0.2, 0.04, 0.06), sp * CF(0, 4.06, 0.4), Look.lampNeutral)
				for _, x in { -w / 2 + 0.03, w / 2 - 0.03 } do
					D.box("ShowcasePost", V3(0.06, 3.0, 1.3), sp * CF(x, 2.6, 0), L.alu)
				end
				local items = {
					{ "블랙박스", C(24, 24, 28), V3(0.5, 0.36, 0.4), "189,000" },
					{ "하이패스", C(240, 240, 236), V3(0.4, 0.2, 0.3), "39,000" },
					{ "방향제", C(120, 60, 160), V3(0.22, 0.4, 0.22), "12,000" },
					{ "폰 거치대", C(40, 42, 46), V3(0.3, 0.3, 0.3), "25,000" },
					{ "고무매트", C(30, 30, 32), V3(0.9, 0.3, 0.3), "59,000" },
					{ "썬팅 필름", C(30, 40, 50), V3(0.25, 0.7, 0.25), "시공 상담" },
					{ "세차 용품", C(40, 120, 200), V3(0.3, 0.5, 0.3), "15,000" },
					{ "차량용 충전기", C(230, 230, 228), V3(0.25, 0.2, 0.25), "18,000" },
				}
				for i, it in items do
					local shelf = math.floor((i - 1) / 4)
					local col = (i - 1) % 4
					local yy = 1.12 + shelf * 1.45
					if col == 0 and shelf > 0 then
						D.box("ShowcaseShelf", V3(w - 0.1, 0.05, 1.1), sp * CF(0, yy - 0.03, 0), L.glassClear)
					end
					local px = -w / 2 + 0.75 + col * (w - 1.2) / 3
					local s: Vector3 = it[3]
					D.box("Accessory", s, sp * CF(px, yy + s.Y / 2, 0.05), lk(it[2]))
					if mid then
						D.label("AccessoryTag", 0.9, 0.36, sp * CF(px, yy + 0.18, 0.6), it[1] .. "\n" .. it[4], INK, C(250, 250, 246), { d = 0.01 })
					end
				end
				D.label("ShowcaseHead", w - 0.4, 0.5, sp * CF(0, 4.55, 0.0), "차량 용품 · ACCESSORIES", NAVY, nil, { d = 0.02, font = Enum.Font.GothamBlack })
			end)
		end
	end)

	-- 4.10 오른쪽 벽: 휠 · 타이어 디스플레이 · 특가 포스터 · 시세표 · 키즈존 --------------------------------------------
	step(K, "rightWall", function()
		-- 휠 · 타이어 벽 (2 x 2)
		local wz = -11.5
		local head = D.wall("right", wz, 8.6, 0.0)
		D.label("WheelWallHead", 6.0, 0.6, head, "휠 · 타이어", NAVY, nil, { d = 0.02, font = Enum.Font.GothamBlack })
		D.plate("WheelWallPanel", 6.6, 6.2, 0.06, D.wall("right", wz, 5.1, 0.0), lk(C(54, 58, 66)))
		for i = 0, 1 do
			for j = 0, 1 do
				local z = wz - 1.6 + i * 3.2
				local y = 6.6 - j * 2.9
				local dcf = D.wall("right", z, y, 0.0)
				D.plate("WheelBracket", 0.3, 0.3, 0.5, dcf, L.darkAlu)
				tyre(D, dcf * CF(0, 0, 0.55) * ANG(0, PI / 2, 0), 2.3, { rim = true, w = 0.8, spokes = if (i + j) % 2 == 0 then 5 else 10, rimLook = if j == 0 then L.rim else lk(C(40, 42, 46), M.Metal, { r = 0.1 }) })
				D.label("WheelTag", 1.4, 0.36, dcf * CF(0, -1.35, 0.06), ({ "18인치 · 189,000", "19인치 · 249,000", "17인치 · 139,000", "20인치 · 329,000" })[i * 2 + j + 1], INK, C(250, 250, 246), { d = 0.01 })
			end
		end
		-- 이달의 특가 포스터 (라이트박스)
		local pc = D.wall("right", 1.0, 5.4, 0.0)
		D.plate("PromoBox", 3.8, 5.6, 0.3, pc, L.darkAlu)
		D.label("PromoFace", 3.6, 5.4, pc * CF(0, 0, 0.3), "이달의 특가\n\n중고 큐비\n150,000원\n\n성능점검 완료\n즉시 출고", WHITE, C(20, 50, 110), { d = 0.02, glow = 1.15, font = Enum.Font.GothamBlack })
		-- 중고차 시세표
		local cat = catalog()
		local order = { "compact", "sedan", "suv", "truck", "van", "luxury" }
		local items = {}
		for _, k in order do
			local e = cat[k] or CATALOG_FALLBACK[k]
			table.insert(items, { e.label or k, "신차 " .. fmtWon(e.new or 0) .. " / 중고 " .. fmtWon(e.used or 0) })
		end
		Props.menuBoard(K, G.B * D.wall("right", 9.6, 5.6, 0.0), 6.4, 4.4, "차량 가격표 (원)", items, { cols = 1, bg = C(250, 250, 246), fg = INK, accent = NAVY, glow = 1.0, frame = L.alu, rowH = 0.55 })
		D.label("RightWallGraphic", 24, 1.4, D.wall("right", -1.0, 11.2, 0.03), "신차 · 중고차 · 렌트 · 정비 · 세차  ONE STOP", C(60, 66, 80), nil, { d = 0.02, font = Enum.Font.GothamBold })
		-- 키즈존 (앞쪽 오른쪽 구석, 창가)
		local kx0, kx1, kz0, kz1 = 27.6, RB.x1 - 0.3, 18.75, RB.z1 - 0.35
		local kp = pf((kx0 + kx1) / 2, y0, (kz0 + kz1) / 2, 180)
		if spot(G, kp, V3(kx1 - kx0, 2.6, kz1 - kz0), 0, "kids") then
			propGroup(G, "kids", V3(kx0, 0, kz0), V3(kx1, 2.6, kz1), function()
				local cols = { C(250, 196, 60), C(110, 190, 240), C(240, 120, 140), C(130, 210, 130) }
				local nx = math.floor((kx1 - kx0) / 1.4)
				local tw = (kx1 - kx0) / nx
				local nz = 2
				local td = (kz1 - kz0) / nz
				for i = 0, nx - 1 do
					for j = 0, nz - 1 do
						D.box("KidsMatTile", V3(tw - 0.03, 0.06, td - 0.03), CF(kx0 + tw * (i + 0.5), y0 + 0.03, kz0 + td * (j + 0.5)), lk(cols[(i + j) % 4 + 1], M.Fabric))
					end
				end
				-- 소프트 블록 · 붕붕카 · 작은 책장
				D.rbox("SoftBlock", V3(0.9, 0.9, 0.9), 0.14, CF(kx0 + 1.0, y0 + 0.51, kz0 + 0.9) * ANG(0, 0.3, 0), lk(C(250, 120, 90), M.Fabric))
				D.rbox("SoftBlock", V3(0.8, 0.8, 0.8), 0.14, CF(kx0 + 1.2, y0 + 1.35, kz0 + 0.9) * ANG(0, -0.2, 0), lk(C(90, 170, 230), M.Fabric))
				D.vcyl("SoftCylinder", 0.7, 0.8, CF(kx0 + 2.3, y0 + 0.41, kz0 + 1.9), lk(C(150, 220, 120), M.Fabric))
				local rc = CF(kx0 + 3.8, y0 + 0.06, kz0 + 1.4) * ANG(0, math.rad(70), 0)
				D.rbox("RideOnCar", V3(0.9, 0.5, 1.7), 0.18, rc * CF(0, 0.55, 0), lk(C(220, 40, 40), M.Plastic))
				D.box("RideOnSeat", V3(0.6, 0.12, 0.5), rc * CF(0, 0.86, -0.2), lk(C(30, 30, 32), M.Plastic))
				D.vcyl("RideOnWheelPost", 0.4, 0.06, rc * CF(0, 1.0, 0.35), L.black)
				D.disc("RideOnWheel", 0.4, 0.05, rc * CF(0, 1.2, 0.38) * ANG(math.rad(60), 0, 0), L.black)
				for _, sx in { -1, 1 } do
					for _, sz in { -1, 1 } do
						D.cyl("RideOnTyre", 0.14, 0.38, rc * CF(sx * 0.45, 0.25, sz * 0.55), L.black)
					end
				end
				local bp = pf(RB.x1 - 0.4, y0 + 0.06, (kz0 + kz1) / 2, -90)
				D.box("KidsBookcase", V3(2.4, 2.0, 0.7), bp * CF(0, 1.0, 0), lk(C(246, 240, 228), M.Wood))
				for i = 0, 1 do
					D.box("KidsBookShelf", V3(2.3, 0.05, 0.6), bp * CF(0, 0.08 + i * 0.95, 0.03), lk(C(220, 200, 170), M.Wood))
					Props.row(K, G.B * (bp * CF(0, 0.12 + i * 0.95, 0.05)), 2.2, "books", { colors = cols, seed = 3 + i })
				end
			end)
			D.label("KidsSign", 2.6, 0.8, D.wall("right", (kz0 + kz1) / 2, 4.2, 0.02), "키즈존 KIDS", C(240, 110, 60), C(255, 250, 236), { d = 0.03, font = Enum.Font.FredokaOne })
		end
	end)

	-- 4.11 사양 안내 태블릿 스탠드 (턴테이블 반경 밖, 가격 카드 옆) ------------------------------------------------
	step(K, "specStands", function()
		local cat = catalog()
		for _, t in tts do
			local card, bd = nil, math.huge
			for _, r in cards do
				local dz = r.c.Z - t.z
				if math.abs(r.c.X - t.x) < 4 and dz > 0 and dz < bd then
					card, bd = r, dz
				end
			end
			if card then
				local placed = false
				for _, dx in { 3.3, -3.3, 6.9, -6.9 } do
					if not placed then
						local sx, sz = card.c.X + dx, card.c.Z + 0.35
						local p = pf(sx, y0, sz, 0)
						if spot(G, p, V3(0.85, 3.6, 0.6), 0, "spec") then
							placed = true
							local kind = t.kind or "sedan"
							local e = cat[kind] or CATALOG_FALLBACK[kind] or CATALOG_FALLBACK.sedan
							propGroup(G, "spec", V3(sx - 0.5, 0, sz - 0.4), V3(sx + 0.5, 3.6, sz + 0.4), function()
								D.slab("SpecBase", 0.85, 0.6, 0.06, 0.12, p * CF(0, 0.03, 0), L.darkAlu)
								D.box("SpecPole", V3(0.12, 3.0, 0.12), p * CF(0, 1.56, -0.05), L.alu)
								local sc = p * CF(0, 3.25, 0.02) * ANG(math.rad(-22), 0, 0)
								D.box("SpecTablet", V3(1.15, 0.82, 0.06), sc, L.black)
								local _, lab = D.label("SpecScreen", 1.06, 0.74, sc * CF(0, 0, 0.035), "", WHITE, C(18, 30, 54), { d = 0.005, glow = 1.15 })
								local pages = {
									{ (e.full or e.label or kind) .. "\n" .. (e.blurb or ""), C(18, 30, 54) },
									{ (SPEC_EXTRA[kind] or "") .. "\n" .. tostring(e.seats or 5) .. "인승", C(24, 40, 40) },
									{ "신차 " .. fmtWon(e.new or 0) .. "원\n중고 " .. fmtWon(e.used or 0) .. "원", C(60, 30, 20) },
									{ "시승 무료 · 60초\n구매 / 시승 은 가격 카드에서", C(20, 50, 100) },
								}
								lab.Text = pages[1][1]
								screenCycle(K, lab, nil, pages, 4 + (math.floor(t.x) % 3) * 0.5)
							end)
						end
					end
				end
			end
		end
	end)

	-- 4.12 문 · 소화기 · 기타 ---------------------------------------------------------------------------
	step(K, "restroomDoor", function()
		local leaf, cas = nil, nil
		for _, r in G.byName.DoorLeaf or {} do
			if r.c.Z < RB.z0 + 1 then
				leaf = r
			end
		end
		for _, r in G.byName.DoorCasing or {} do
			if r.c.Z < RB.z0 + 1 then
				cas = r
			end
		end
		if not cas then
			return
		end
		hideRec(G, cas)
		if leaf then
			hideRec(G, leaf)
		end
		local cx = cas.c.X
		local w = cas.size.X
		local h = cas.size.Y
		for _, s in { -1, 1 } do
			D.plate("RestroomJamb", 0.18, h, 0.14, D.wall("back", cx + s * (w / 2 - 0.09), h / 2, 0.0), L.alu)
		end
		D.plate("RestroomHead", w, 0.18, 0.14, D.wall("back", cx, h - 0.09, 0.0), L.alu)
		D.plate("RestroomLeaf", w - 0.4, h - 0.3, 0.08, D.wall("back", cx, (h - 0.3) / 2 + 0.05, 0.02), lk(C(214, 216, 218)))
		D.plate("RestroomKick", w - 0.5, 0.8, 0.02, D.wall("back", cx, 0.5, 0.1), L.steel)
		D.plate("RestroomPush", 0.3, 1.2, 0.02, D.wall("back", cx + w / 2 - 0.55, 3.8, 0.1), L.steel)
		D.plate("RestroomCloser", 1.0, 0.2, 0.2, D.wall("back", cx, h - 0.45, 0.1), L.darkAlu)
		D.label("RestroomPicto", 1.4, 0.7, D.wall("back", cx, 4.6, 0.11), "🚹 🚺", C(32, 70, 140), C(246, 246, 242), { d = 0.01 })
	end)
	step(K, "extinguisher", function()
		for _, r in G.byName.FireExtinguisher or {} do
			hideRec(G, r)
			for _, q in G.byName.ExtinguisherValve or {} do
				if (q.c - r.c).Magnitude < 1.5 then
					hideRec(G, q)
				end
			end
			extinguisher(D, V3(r.c.X, y0, r.c.Z), -90)
			local wn = if r.c.X > 0 then "right" else "left"
			safetySign(D, D.wall(wn, r.c.Z, 3.6, 0.03), 0.9, 1.1, "fire", "소화기")
		end
	end)
	return G
end

---------------------------------------------------------------------------------------------------
-- 5. 정비 베이 / 6. 자동세차장 (아래)
---------------------------------------------------------------------------------------------------
local buildBay: (any, any) -> any
local buildWash: (any, any) -> any

function T.style(V: any): any
	-- 공통 마감 · 리스킨 전부 끔: 이 건물은 V 프레임과 1.9 도 어긋나 우리 B 프레임에서 직접 지음
	return {
		chair = false, stool = false, table = false, counter = false, base = false, lower = false, mat = false,
		clock = false, license = false, cctv = false, ceiling = false, lights = { kind = "none" },
		skip = { floor = true, ceiling = true, walls = true, chairs = true, stools = true, tables = true, counters = true, upgrades = true, fixtures = true },
	}
end

function T.build(K: any, V: any, S: any)
	local t = V.type
	K:free(function()
		if t == "showroom" then
			buildShowroom(K, V)
		elseif t == "servicebay" then
			if buildBay then
				buildBay(K, V)
			end
		elseif t == "carwash" then
			if buildWash then
				buildWash(K, V)
			end
		end
	end)
end

return T
