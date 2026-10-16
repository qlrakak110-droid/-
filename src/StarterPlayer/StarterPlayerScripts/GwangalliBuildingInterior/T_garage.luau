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

-- 태그 확인 (Instance:HasTag, 안 되면 CollectionService)
local function hasTag(inst: Instance, tag: string): boolean
	local ok, v = pcall(function()
		return inst:HasTag(tag)
	end)
	if ok then
		return v == true
	end
	return CollectionService:HasTag(inst, tag)
end

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

-- 후보 자리 중 첫 빈 자리 (pcf 목록)
local function firstSpot(G: any, cands: { CFrame }, size: Vector3, pad: number?, kind: string, ignore: { [any]: boolean }?): CFrame?
	local p = pad or 0
	for _, pcf in cands do
		local mn, mx = laabb(pcf * CF(0, size.Y / 2, 0), size + V3(2 * p, 0, 2 * p))
		if clear(G, mn, mx, ignore) then
			reserveB(G, mn, mx, kind)
			return pcf
		end
	end
	do
		local mn, mx = laabb(cands[1] * CF(0, size.Y / 2, 0), size + V3(2 * p, 0, 2 * p))
		local _, why = clear(G, mn, mx, ignore)
		note(G.K, "skip " .. kind .. " (no free spot; first: " .. tostring(why) .. ")")
	end
	return nil
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
		local f = fg or INK
		opts.fg = f
		-- 어두운 글자는 인쇄된 라벨처럼 밝은 바탕을 깔아 읽히게 (투명 바탕 어두운 글자는 멀리서 사라짐)
		if bg == nil and not opts.clear and (0.3 * f.R + 0.59 * f.G + 0.11 * f.B) < 0.42 then
			bg = opts.autoBg or C(250, 250, 246)
		end
		opts.clear = nil
		opts.autoBg = nil
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
	D.cyl("TrackHead", 0.66, 0.36, hcf * CF(0, 0, -0.14) * ANG(0, PI / 2, 0), Lk)
	D.cyl("TrackRing", 0.06, 0.4, hcf * CF(0, 0, -0.46) * ANG(0, PI / 2, 0), lk(C(60, 60, 64), M.Metal))
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

-- 가격표 (불투명 줄 바탕): items = { { 이름, 가격 } }, o.cols, o.accent, o.frame
local function priceBoard(D: any, dcf: CFrame, w: number, h: number, title: string, items: { { string } }, o: any?)
	local acc: Color3 = (o and o.accent) or NAVY
	D.plate("PriceBoardFrame", w + 0.24, h + 0.24, 0.12, dcf, (o and o.frame) or L.alu)
	D.plate("PriceBoardFace", w, h, 0.14, dcf, lk(C(250, 250, 246)))
	local th = math.min(0.85, h * 0.17)
	D.label("PriceBoardTitle", w, th, dcf * CF(0, h / 2 - th / 2, 0.14), title, WHITE, acc, { d = 0.01, font = Enum.Font.GothamBlack })
	local cols = (o and o.cols) or 1
	local rows = math.ceil(#items / cols)
	local rh = (h - th - 0.16) / rows
	local cw = w / cols
	for i, it in items do
		local col = (i - 1) // rows
		local row = (i - 1) % rows
		local x0 = -w / 2 + col * cw
		local y = h / 2 - th - 0.08 - rh * (row + 0.5)
		local bg = if row % 2 == 0 then C(250, 250, 246) else C(234, 236, 240)
		D.label("PriceRowName", cw * 0.6, rh * 0.86, dcf * CF(x0 + cw * 0.33, y, 0.145), it[1], INK, bg, { d = 0.005, align = "Left", font = Enum.Font.GothamMedium })
		D.label("PriceRowPrice", cw * 0.32, rh * 0.86, dcf * CF(x0 + cw * 0.81, y, 0.145), it[2] or "", acc, bg, { d = 0.005, align = "Right", font = Enum.Font.GothamBold })
	end
	if cols > 1 then
		for c = 1, cols - 1 do
			D.plate("PriceBoardDivider", 0.04, h - th - 0.2, 0.16, dcf * CF(-w / 2 + c * cw, -th / 2, 0), lk(C(200, 202, 206)))
		end
	end
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

-- 가벼운 라운지 · 상담 의자 (썰매 다리 + 쿠션 좌판 + 등받이, 9 파트). pcf 정면 = 앉은 사람이 보는 쪽
local function chairLite(D: any, pcf: CFrame, top: number, seat: any, frame: any)
	local w, d = 1.55, 1.5
	for _, sx in { -1, 1 } do
		D.bar("ChairSled", (pcf * CF(sx * 0.62, 0.04, -0.6)).Position, (pcf * CF(sx * 0.62, 0.04, 0.62)).Position, 0.08, 0.08, frame)
		D.bar("ChairSledPost", (pcf * CF(sx * 0.62, 0.04, 0.6)).Position, (pcf * CF(sx * 0.6, top - 0.25, 0.45)).Position, 0.07, 0.07, frame)
		D.bar("ChairSledPost", (pcf * CF(sx * 0.62, 0.04, -0.58)).Position, (pcf * CF(sx * 0.6, top + 1.4, -0.66)).Position, 0.07, 0.07, frame)
	end
	D.box("ChairSeatPad", V3(w, 0.24, d), pcf * CF(0, top - 0.12, 0.02), seat)
	D.box("ChairSeatShell", V3(w - 0.1, 0.06, d - 0.1), pcf * CF(0, top - 0.27, 0.02), frame)
	D.box("ChairBackPad", V3(w - 0.05, 1.05, 0.2), pcf * CF(0, top + 0.95, -0.68) * ANG(math.rad(10), 0, 0), seat)
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
		if string.sub(r.name, 1, 12) == "GarageDesk_" or r.name == "PriceCard" or hasTag(r.part, "GaragePrompt") or hasTag(r.part, "GarageDesk") then
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
		if r.name == "Turntable" or hasTag(r.part, "GarageTurntable") then
			local kind = r.part:GetAttribute("GarageKind")
			local rad = math.max(r.size.X, r.size.Z) / 2
			table.insert(tts, { x = r.c.X, z = r.c.Z, r = math.max(8.75, rad + 0.25), kind = kind })
		end
	end
	-- 차 종류: 턴테이블 속성이 없으면 가까운 GarageDisplayCar 의 GarageKind
	for _, d in V.model:GetDescendants() do
		if d:IsA("Model") and hasTag(d, "GarageDisplayCar") then
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
		local nx = math.floor((RB.x1 - RB.x0) / 11)
		local nz = math.floor((RB.z1 - RB.z0) / 11)
		for i = 0, nx do
			for j = 0, nz do
				local x = RB.x0 + 3.2 + i * 11
				local z = RB.z0 + 3.0 + j * 11
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
				local fc = D.wall("back", -34.0 + (i - 1) * 1.55, 6.7, 0.0)
				D.plate("CertFrame", 1.3, 1.75, 0.06, fc, Look.goldMetal)
				D.label("CertPaper", 1.12, 1.56, fc * CF(0, 0, 0.06), tx, C(40, 40, 40), C(250, 248, 240), { d = 0.01, font = Enum.Font.GothamMedium })
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
			D.plate("SalesHeaderBand", 10.0, 1.2, 0.06, D.wall("back", -22.2, 9.4, 0.0), L.navyMatte)
			D.label("SalesHeader", 9.2, 0.8, D.wall("back", -22.2, 9.45, 0.06), "구매 상담 · 렌트 · 할부 · 내 차 팔기", WHITE, nil, { d = 0.01, font = Enum.Font.GothamBlack })
			D.plate("SalesHeaderLine", 10.0, 0.06, 0.08, D.wall("back", -22.2, 8.85, 0.0), L.orangeNeon)
		end
	end)

	-- 4.7 고객 라운지: 소파 · 테이블 · 정수기 (맵 자리 정확히) + 커피 스테이션 · 음료 냉장고 · 잡지꽂이 · 펜던트 ---------------------------------
	step(K, "lounge", function()
		-- 라운지 뒤 벽: 원목 루버 (TV · 소파 뒤, 화장실 문 앞까지)
		do
			local lx0, lx1 = 8.6, 30.2
			local door = nil
			for _, r in G.byName.DoorCasing or {} do
				if r.c.Z < RB.z0 + 1 then
					door = r
				end
			end
			if door then
				lx1 = math.min(lx1, door.min.X - 0.4)
			end
			local lm = (lx0 + lx1) / 2
			D.plate("LoungeLouverBack", lx1 - lx0, yC - 0.55, 0.03, D.wall("back", lm, (0.45 + yC - 0.1) / 2, 0.004), lk(C(40, 36, 32)))
			local pitch = if hi then 0.45 else 0.7
			local n = math.floor((lx1 - lx0) / pitch)
			for i = 0, n - 1 do
				D.plate("LoungeLouverSlat", pitch * 0.55, yC - 0.6, 0.14, D.wall("back", lx0 + pitch * (i + 0.5), (0.45 + yC - 0.1) / 2, 0.03), Look.oak)
			end
			D.plate("LoungeLouverCap", lx1 - lx0, 0.12, 0.2, D.wall("back", lm, 0.5, 0.0), L.black)
		end
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
			local p = D.wallPf("back", x, 0.9) * CF(0, 0, 0.22)
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
			local w, h = tv.max.X - tv.min.X, tv.max.Y - tv.min.Y
			-- 베젤 깊이 = 벽 ~ TV 앞면 (+0.04): 화면 둘레를 감싸 큰 검은 판이 아니라 벽걸이 TV 로 보이게
			local dep = math.max(0.26, tv.max.Z - RB.z0 + 0.04)
			for _, s in { -1, 1 } do
				D.plate("TVBezel", w + 0.36, 0.18, dep, D.wall("back", cx, cy + s * (h / 2 + 0.09), 0.0), lk(C(24, 25, 28), M.Metal))
				D.plate("TVBezel", 0.18, h, dep, D.wall("back", cx + s * (w / 2 + 0.09), cy, 0.0), lk(C(24, 25, 28), M.Metal))
			end
			D.box("TVLogo", V3(0.5, 0.06, 0.02), CF(cx, tv.min.Y - 0.09, RB.z0 + dep + 0.01), L.alu)
			D.box("TVPowerLED", V3(0.06, 0.04, 0.02), CF(cx + w / 2 - 0.4, tv.min.Y - 0.09, RB.z0 + dep + 0.01), lk(C(255, 60, 40), M.Neon))
			-- 뒤 백라이트 (벽에 번지는 간접광)
			D.plate("TVBackGlow", w + 0.9, h + 0.7, 0.02, D.wall("back", cx, cy, 0.01), lk(C(255, 170, 110), M.Neon, { t = 0.82 }))
			D.rbox("Soundbar", V3(4.6, 0.32, 0.4), 0.12, CF(cx, cy - h / 2 - 0.5, RB.z0 + 0.42), L.black)
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
						chairLite(D, CFrame.lookAt(cp, cp + V3(math.sin(rad), 0, math.cos(rad))), 1.95, if k == 1 then lk(C(214, 206, 192), M.Leather) else lk(C(120, 122, 128), M.Fabric), L.darkAlu)
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
		D.plate("LeftWallBand", 22, 1.2, 0.05, D.wall("left", -2.0, 11.2, 0.0), L.navyMatte)
		D.plate("LeftWallBandLine", 22, 0.06, 0.06, D.wall("left", -2.0, 10.5, 0.0), L.orangeNeon)
		D.label("LeftWallGraphic", 20, 0.8, D.wall("left", -2.0, 11.2, 0.05), "SINCE 2008  ·  광안리 바닷가 옆 믿을 수 있는 자동차 매장", C(236, 236, 230), nil, { d = 0.01, font = Enum.Font.GothamBold })
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
				tyre(D, dcf * CF(0, 0, 0.55) * ANG(0, PI / 2, 0), 2.3, { rim = true, w = 0.8, spokes = if (i + j) % 2 == 0 then 5 else 6, rimLook = if j == 0 then L.rim else lk(C(40, 42, 46), M.Metal, { r = 0.1 }) })
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
		priceBoard(D, D.wall("right", 9.6, 5.6, 0.0), 6.4, 4.4, "차량 가격표 (원)", items, { accent = NAVY })
		D.plate("RightWallBand", 22, 1.2, 0.05, D.wall("right", -1.0, 11.2, 0.0), L.navyMatte)
		D.plate("RightWallBandLine", 22, 0.06, 0.06, D.wall("right", -1.0, 10.5, 0.0), L.orangeNeon)
		D.label("RightWallGraphic", 20, 0.8, D.wall("right", -1.0, 11.2, 0.05), "신차 · 중고차 · 렌트 · 정비 · 세차  ONE STOP", C(236, 236, 230), nil, { d = 0.01, font = Enum.Font.GothamBold })
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
			-- 키즈존 벽: 파스텔 벽화 (도로 · 구름 · 꼬마 자동차) + 큰 간판
			local kzc = (kz0 + kz1) / 2
			local mw = math.min(5.2, kz1 - kz0 - 0.2)
			local mc = D.wall("right", kzc, 3.55, 0.0)
			D.plate("KidsMural", mw, 2.5, 0.05, mc, lk(C(206, 234, 248)))
			D.plate("KidsMuralGrass", mw, 0.6, 0.06, mc * CF(0, -0.95, 0), lk(C(150, 214, 140)))
			D.plate("KidsMuralRoad", mw, 0.22, 0.065, mc * CF(0, -0.75, 0), lk(C(90, 96, 110)))
			for k = 0, 3 do
				D.plate("KidsMuralRoadDash", 0.4, 0.04, 0.07, mc * CF(-mw / 2 + 0.6 + k * (mw - 1.2) / 3, -0.75, 0), lk(C(250, 240, 200)))
			end
			for k, cl in { { -1.6, 0.75, 0.9 }, { 0.6, 0.95, 0.7 }, { 1.9, 0.6, 0.55 } } do
				local cc = mc * CF(cl[1], cl[2], 0.06)
				D.plate("KidsCloud", cl[3], cl[3] * 0.42, 0.02, cc, lk(WHITE))
				D.plate("KidsCloud", cl[3] * 0.55, cl[3] * 0.32, 0.02, cc * CF(-cl[3] * 0.12, cl[3] * 0.2, 0), lk(WHITE))
				local _ = k
			end
			D.plate("KidsSun", 0.55, 0.55, 0.02, mc * CF(-mw / 2 + 0.5, 0.8, 0.06), lk(C(255, 206, 70)))
			for k, cc in { { -1.1, C(240, 90, 80) }, { 0.9, C(70, 140, 230) } } do
				local carC = mc * CF(cc[1], -0.48, 0.08)
				D.plate("KidsMuralCar", 1.0, 0.32, 0.02, carC, lk(cc[2]))
				D.plate("KidsMuralCarTop", 0.55, 0.24, 0.02, carC * CF(-0.05, 0.26, 0), lk(cc[2]))
				D.plate("KidsMuralCarWin", 0.4, 0.14, 0.022, carC * CF(-0.05, 0.27, 0.002), lk(C(220, 240, 255)))
				for _, wx in { -0.3, 0.3 } do
					D.cyl("KidsMuralWheel", 0.03, 0.24, carC * CF(wx, -0.17, 0.01) * ANG(0, PI / 2, 0), lk(C(40, 40, 44)))
				end
				local _ = k
			end
			D.label("KidsSign", 3.6, 0.9, D.wall("right", kzc, 5.35, 0.03), "키즈존 KIDS", C(240, 110, 60), C(255, 250, 236), { d = 0.04, font = Enum.Font.FredokaOne })
			D.label("KidsRule", 3.0, 0.5, D.wall("right", kzc, 2.05, 0.06), "보호자와 함께 · 신발 벗고 놀아요", C(60, 90, 140), C(255, 250, 236), { d = 0.01, font = Enum.Font.GothamBold })
			-- 낮은 소프트 울타리 (안쪽 두 면, 통로 쪽 입구는 열어 둠)
			local fenceL = lk(C(250, 214, 110), M.Plastic)
			local fz = kz0 + 0.12
			for i = 0, 3 do
				local x = kx0 + 0.15 + i * (kx1 - kx0 - 0.3) / 3
				D.vcyl("KidsFencePost", 1.3, 0.22, CF(x, y0 + 0.65, fz), lk(C(110, 190, 240), M.Plastic))
				D.ball("KidsFenceCap", 0.3, CF(x, y0 + 1.36, fz), lk(C(240, 120, 140), M.Plastic))
			end
			D.box("KidsFenceRail", V3(kx1 - kx0 - 0.3, 0.16, 0.12), CF((kx0 + kx1) / 2, y0 + 1.1, fz), fenceL)
			D.box("KidsFenceRail", V3(kx1 - kx0 - 0.3, 0.16, 0.12), CF((kx0 + kx1) / 2, y0 + 0.5, fz), fenceL)
			local fx = kx0 + 0.12
			local fzA, fzB = kz0 + 0.15, kz1 - 2.2
			if fzB - fzA > 0.8 then
				for _, z in { fzA, fzB } do
					D.vcyl("KidsFencePost", 1.3, 0.22, CF(fx, y0 + 0.65, z), lk(C(110, 190, 240), M.Plastic))
					D.ball("KidsFenceCap", 0.3, CF(fx, y0 + 1.36, z), lk(C(240, 120, 140), M.Plastic))
				end
				for _, yy in { 0.5, 1.1 } do
					D.box("KidsFenceRail", V3(0.12, 0.16, fzB - fzA), CF(fx, y0 + yy, (fzA + fzB) / 2), fenceL)
				end
			end
		end
		-- 출고 고객 포토월 (가격표와 키즈존 사이)
		local pwz = (12.9 + kz0) / 2
		local pww = math.min(4.8, kz0 - 12.9 - 0.4)
		if pww > 2.4 then
			local pwc = D.wall("right", pwz, 5.8, 0.0)
			D.plate("PhotoWallBoard", pww, 4.6, 0.05, pwc, lk(C(250, 248, 244)))
			D.label("PhotoWallHead", pww - 0.2, 0.6, pwc * CF(0, 1.95, 0.06), "출고 고객님 감사합니다 ♥", NAVY, nil, { d = 0.01, clear = true, font = Enum.Font.GothamBlack })
			local sky = { C(150, 200, 236), C(240, 200, 150), C(170, 210, 230), C(236, 170, 150), C(180, 214, 190), C(200, 190, 230) }
			local cars = { C(240, 240, 236), C(40, 42, 46), C(196, 34, 30), C(150, 156, 162), C(30, 70, 140), C(200, 220, 210) }
			local captions = { "김○○님 · 큐비", "박○○님 · SUV", "이○○님 · 세단", "최○○님 · 트럭", "정○○님 · 밴", "강○○님 · 플래그십" }
			local pw, ph = (pww - 0.5) / 3, 1.55
			for i = 0, 5 do
				local cx = -pww / 2 + 0.25 + pw * ((i % 3) + 0.5)
				local cy = 0.85 - (i // 3) * 1.75
				local fc = pwc * CF(cx, cy, 0.06) * ANG(0, 0, ((i * 37) % 7 - 3) * 0.012)
				D.plate("PhotoFrame", pw - 0.12, ph, 0.02, fc, lk(WHITE))
				D.plate("PhotoSky", pw - 0.28, ph * 0.5, 0.025, fc * CF(0, ph * 0.13, 0), lk(sky[i + 1]))
				D.plate("PhotoGround", pw - 0.28, ph * 0.16, 0.025, fc * CF(0, -ph * 0.2, 0), lk(C(120, 124, 128)))
				D.plate("PhotoCar", pw * 0.5, ph * 0.14, 0.03, fc * CF(0.05, -ph * 0.08, 0), lk(cars[i + 1]))
				D.plate("PhotoCarTop", pw * 0.28, ph * 0.1, 0.03, fc * CF(0.02, ph * 0.03, 0), lk(cars[i + 1]))
				D.plate("PhotoPerson", pw * 0.1, ph * 0.3, 0.03, fc * CF(-pw * 0.33, -ph * 0.05, 0), lk(C(60, 64, 80)))
				D.label("PhotoCaption", pw - 0.2, ph * 0.18, fc * CF(0, -ph * 0.38, 0.02), captions[i + 1], INK, nil, { d = 0.003, clear = true })
				D.ball("PhotoPin", 0.1, fc * CF(0, ph / 2 - 0.05, 0.04), lk(({ C(220, 50, 50), C(40, 110, 210), C(240, 190, 30) })[i % 3 + 1]))
			end
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
								D.box("SpecBase", V3(0.85, 0.06, 0.6), p * CF(0, 0.03, 0), L.darkAlu)
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

---------------------------------------------------------------------------------------------------
-- 5. 정비 베이 (광안 오토 정비 베이): 카센터 2주식 리프트 2 대 + 장비 · 공구 · 부품 · 접수
---------------------------------------------------------------------------------------------------
local function bayTool(D: any, r: any, zf: number)
	-- 맵 공구 판때기 r 자리에 3D 공구 (zf = 슬랫 패널 앞면 z)
	local x, y = r.c.X, r.c.Y
	local h = r.size.Y
	local z = zf + 0.07
	local steel = lk(C(200, 204, 210), M.Metal, { r = 0.2 })
	local nm = r.name
	D.box("ToolHook", V3(0.05, 0.05, 0.22), CF(x, y + h / 2 + 0.05, zf + 0.11), lk(C(150, 150, 154), M.Metal))
	if nm == "Wrench" then
		D.box("WrenchShank", V3(0.08, h - 0.36, 0.035), CF(x, y, z), steel)
		D.cyl("WrenchRing", 0.05, 0.26, CF(x, y + h / 2 - 0.14, z) * ANG(0, PI / 2, 0), steel)
		D.cyl("WrenchRingHole", 0.06, 0.13, CF(x, y + h / 2 - 0.14, z) * ANG(0, PI / 2, 0), lk(C(40, 40, 44)))
		for _, s in { -1, 1 } do
			D.box("WrenchJaw", V3(0.06, 0.18, 0.035), CF(x + s * 0.08, y - h / 2 + 0.1, z) * ANG(0, 0, s * 0.25), steel)
		end
	elseif nm == "Screwdriver" then
		local col = r.part.Color
		D.vcyl("ScrewdriverGrip", h * 0.62, 0.15, CF(x, y + h * 0.15, z), lk(col, M.Plastic))
		D.vcyl("ScrewdriverGripBand", h * 0.2, 0.16, CF(x, y + h * 0.05, z), lk(C(24, 24, 26), M.Rubber))
		D.vcyl("ScrewdriverShaft", h * 0.75, 0.05, CF(x, y - h * 0.55, z), steel)
	elseif nm == "Plier" then
		local col = if (math.floor(x * 3) % 2) == 0 then C(200, 40, 36) else C(40, 90, 190)
		D.box("PlierJaw", V3(0.14, 0.3, 0.05), CF(x, y + h / 2 - 0.15, z), steel)
		for _, s in { -1, 1 } do
			D.bar("PlierGrip", V3(x + s * 0.03, y + h / 2 - 0.32, z), V3(x + s * 0.17, y - h / 2 + 0.05, z), 0.07, 0.05, lk(col, M.Rubber))
		end
	elseif nm == "SocketSet" then
		local w = r.size.X
		D.box("SocketRail", V3(w, 0.08, 0.06), CF(x, y - h / 2 + 0.15, z), lk(C(200, 40, 36), M.Metal))
		local n = 5
		for i = 1, n do
			local sx = x - w / 2 + w * (i - 0.5) / n
			local d = 0.12 + i * 0.025
			D.cyl("Socket", d * 1.4, d, CF(sx, y - h / 2 + 0.24 + d * 0.7, z + 0.04) * ANG(0, 0, PI / 2), steel)
		end
		D.box("RatchetHandle", V3(0.08, h * 0.9, 0.04), CF(x + w / 2 - 0.1, y + 0.15, z), lk(C(30, 30, 32), M.Rubber))
	elseif nm == "HammerHandle" then
		D.box("HammerGrip", V3(0.12, h * 0.5, 0.1), CF(x, y - h * 0.22, z), lk(C(240, 190, 30), M.Rubber))
		D.box("HammerShaft", V3(0.09, h * 0.55, 0.07), CF(x, y + h * 0.2, z), lk(C(30, 30, 32), M.Metal))
	elseif nm == "HammerHead" then
		D.box("HammerHeadSteel", V3(r.size.X, 0.22, 0.18), CF(x, y, z), lk(C(70, 72, 76), M.Metal))
		D.box("HammerClaw", V3(0.22, 0.14, 0.16), CF(x - r.size.X / 2 - 0.08, y + 0.04, z) * ANG(0, 0, 0.5), lk(C(70, 72, 76), M.Metal))
	elseif nm == "TapeMeasure" then
		D.rbox("TapeBody", V3(0.5, 0.5, 0.22), 0.12, CF(x - 1.0, y, z + 0.03), lk(C(250, 200, 40), M.Plastic))
		D.box("TapeBlade", V3(1.6, 0.08, 0.02), CF(x + 0.1, y - 0.18, z), lk(C(240, 210, 60), M.Metal))
		D.box("TapeHook", V3(0.04, 0.12, 0.06), CF(x + 0.92, y - 0.16, z + 0.02), steel)
		D.rbox("TapeBody", V3(0.5, 0.5, 0.22), 0.12, CF(x + 1.1, y + 0.05, z + 0.03), lk(C(30, 30, 32), M.Plastic))
	end
end

local function buildBayImpl(K: any, V: any): any
	local G = newCtx(K, V, "servicebay")
	local D = draw(G)
	local RB = G.RB
	local hi = K.detail == "high"
	local mid = K.detail ~= "low"
	local y0, yR = RB.y0, RB.y1
	local trussY = 14.64
	local trussZ = {}
	for _, r in G.byName.Truss or {} do
		trussY = math.min(trussY, r.min.Y)
		table.insert(trussZ, r.c.Z)
	end
	table.sort(trussZ)
	if #trussZ == 0 then
		trussZ = { -13.82, 0.18, 14.18 }
	end
	note(K, string.format("bay frame=%s bounds x %.2f..%.2f z %.2f..%.2f roof %.2f truss %.2f", G.frameFrom, RB.x0, RB.x1, RB.z0, RB.z1, yR, trussY))

	-- 5.1 계약 구역 ---------------------------------------------------------------------------------
	local zone = G.byName.GarageZone_service and G.byName.GarageZone_service[1]
	if zone then
		keep(G, zone.min - V3(0.25, 0.3, 0.25), zone.max + V3(0.25, 1, 0.25), "zone")
		keep(G, V3(zone.min.X - 0.4, 0.1, zone.max.Z - 0.5), V3(zone.max.X + 0.4, 9.5, RB.z1 + 2), "driveIn")
	end
	-- 리프트: 안전선 쌍(리프트 구역) + 리프트 모델 상자 + 진입로
	local lifts = {}
	for _, d in V.model:GetDescendants() do
		if d:IsA("Model") and hasTag(d, "GarageLift") then
			local mn, mx = V3(math.huge, math.huge, math.huge), V3(-math.huge, -math.huge, -math.huge)
			for _, q in d:GetDescendants() do
				if q:IsA("BasePart") then
					local a, b = laabb(G.Binv * V.cf:ToObjectSpace(q.CFrame), q.Size)
					mn, mx = mn:Min(a), mx:Max(b)
				end
			end
			if mn.X < math.huge then
				table.insert(lifts, { model = d, min = mn, max = mx, display = d:GetAttribute("Role") == "display" })
			end
		end
	end
	local lines = {}
	for _, r in G.byName.SafetyLine or {} do
		table.insert(lines, r)
	end
	table.sort(lines, function(a, b)
		return a.c.X < b.c.X
	end)
	local bays = {}
	for i = 1, #lines - 1, 2 do
		local a, b = lines[i], lines[i + 1]
		table.insert(bays, { x0 = a.min.X, x1 = b.max.X, z0 = math.min(a.min.Z, b.min.Z), z1 = math.max(a.max.Z, b.max.Z) })
	end
	if #bays == 0 then
		bays = { { x0 = -21.0, x1 = -5.0, z0 = -6.8, z1 = 13.2 }, { x0 = 3.0, x1 = 19.0, z0 = -6.8, z1 = 13.2 } }
	end
	for _, b in bays do
		keep(G, V3(b.x0 - 0.2, 0.1, b.z0 - 0.2), V3(b.x1 + 0.2, yR, b.z1 + 0.2), "liftBay")
		keep(G, V3(b.x0 - 0.2, 0.1, b.z1), V3(b.x1 + 0.2, 9.5, RB.z1 + 2), "liftPath")
	end
	for _, l in lifts do
		keep(G, l.min - V3(0.4, 0, 0.4), l.max + V3(0.4, 0.5, 0.4), "lift")
	end
	table.sort(bays, function(a, b)
		return a.x0 < b.x0
	end)
	local laneX0, laneX1 = -5.0, 3.0
	if #bays >= 2 then
		laneX0, laneX1 = bays[1].x1 + 0.2, bays[2].x0 - 0.2
		keep(G, V3(laneX0, 0.1, bays[1].z0 - 0.2), V3(laneX1, 7, RB.z1 + 2), "lane")
	end
	for _, r in G.byName.GarageDesk_service or {} do
		keep(G, r.min - V3(1.4, 0, 1.4), r.max + V3(1.4, 3, 1.6), "desk")
	end
	for _, r in G.byName.HumanoidRootPart or {} do
		keep(G, V3(r.c.X - 2.4, 0.1, r.c.Z - 2.4), V3(r.c.X + 2.4, 7, r.c.Z + 2.4), "mechanic")
	end
	keep(G, V3(RB.x0 - 1, 0.1, RB.z1 - 1.6), V3(RB.x1 + 1, 12, RB.z1 + 3), "bayMouth")
	addServerPrompts(G)

	-- 5.2 바닥: 에폭시 + 리프트 구역 + 보행로 + 기둥 주의 + 배수로 + 기름 얼룩 -------------------------------------
	step(K, "floor", function()
		local cx, cz = (RB.x0 + RB.x1) / 2, (RB.z0 + RB.z1) / 2
		D.box("EpoxyFloor", V3(RB.x1 - RB.x0 - 0.04, 0.014, RB.z1 - RB.z0 - 0.04), CF(cx, y0 + 0.007, cz), L.epoxy)
		for i, b in bays do
			D.box("EpoxyLiftBay", V3(b.x1 - b.x0 - 0.42, 0.006, b.z1 - b.z0), CF((b.x0 + b.x1) / 2, y0 + 0.017, (b.z0 + b.z1) / 2), L.epoxyDark)
			D.label("BayNumber", 2.6, 2.6, floorCF(V3((b.x0 + b.x1) / 2, y0 + 0.03, b.z1 + 2.4), -ZA), tostring(i), C(236, 236, 230), nil, { d = 0.004, font = Enum.Font.GothamBlack })
			D.label("BayNumberSub", 7.0, 0.6, floorCF(V3((b.x0 + b.x1) / 2, y0 + 0.03, b.z1 + 0.9), -ZA), "리프트 작업구역 · 하부 출입 주의", C(236, 196, 40), nil, { d = 0.004 })
		end
		-- 가운데 보행로 (초록) + 흰 테두리
		D.box("Walkway", V3(laneX1 - laneX0 - 0.8, 0.006, RB.z1 - 2.2 - (-7.0)), CF((laneX0 + laneX1) / 2, y0 + 0.017, (RB.z1 - 2.2 - 7.0) / 2), lk(C(62, 112, 82), M.SmoothPlastic, { r = 0.04 }))
		for _, x in { laneX0 + 0.35, laneX1 - 0.35 } do
			D.box("WalkwayEdge", V3(0.12, 0.007, RB.z1 - 2.2 + 7.0), CF(x, y0 + 0.018, (RB.z1 - 2.2 - 7.0) / 2), lk(C(236, 236, 230)))
		end
		D.label("WalkwayText", 3.6, 0.9, floorCF(V3((laneX0 + laneX1) / 2, y0 + 0.03, 17.0), -ZA), "보행로", WHITE, nil, { d = 0.004, font = Enum.Font.GothamBlack })
		-- 리프트 기둥 둘레 노랑/검정 빗금
		for _, r in G.byName.LiftPost or {} do
			D.box("PostHatch", V3(r.size.X + 1.2, 0.006, r.size.Z + 1.2), CF(r.c.X, y0 + 0.02, r.c.Z), L.yellow)
			for k = -1, 1 do
				D.box("PostHatchStripe", V3(0.22, 0.007, r.size.Z + 1.4), CF(r.c.X + k * 0.55, y0 + 0.021, r.c.Z) * ANG(0, math.rad(35), 0), L.black)
			end
		end
		-- 배수로 (입구 쪽 가로)
		local tz = RB.z1 - 3.0
		local tx0 = RB.x0 + 2.2
		D.box("TrenchFrame", V3(RB.x1 - tx0 - 0.2, 0.012, 1.0), CF((tx0 + RB.x1 - 0.2) / 2, y0 + 0.02, tz), lk(C(70, 72, 76), M.Metal))
		D.box("TrenchGrate", V3(RB.x1 - tx0 - 0.4, 0.014, 0.76), CF((tx0 + RB.x1 - 0.2) / 2, y0 + 0.024, tz), lk(C(56, 58, 62), M.DiamondPlate))
		local n = if hi then 40 else 16
		for i = 1, n do
			local x = tx0 + (RB.x1 - 0.2 - tx0) * i / (n + 1)
			D.box("TrenchSlot", V3(0.06, 0.016, 0.6), CF(x, y0 + 0.027, tz), lk(C(20, 20, 22)))
		end
		-- 기름 얼룩 · 타이어 자국
		local rng = mkRng(77)
		local stains = { { -13.5, 1.5, 2.6 }, { -10.2, 5.0, 1.6 }, { -16.0, 6.2, 1.2 }, { 10.8, 2.2, 2.0 }, { 13.4, 6.4, 1.1 }, { -12.0, -9.0, 1.4 }, { 7.6, -3.5, 0.9 }, { -2.0, -12.5, 1.0 } }
		for _, s in stains do
			local w = s[3] * (0.8 + rng() * 0.4)
			D.cyl("OilStain", 0.005, w, CF(s[1], y0 + 0.031, s[2]) * ANG(0, rng() * PI, PI / 2) * CF(0, 0, 0), { c = C(36, 36, 34), m = M.SmoothPlastic, t = 0.45, r = 0.15 })
			D.cyl("OilStainHalo", 0.004, w * 1.5, CF(s[1] + 0.2, y0 + 0.029, s[2] - 0.1) * ANG(0, 0, PI / 2), { c = C(70, 70, 66), m = M.SmoothPlastic, t = 0.7 })
		end
		for _, b in bays do
			for _, sx in { -1, 1 } do
				local x = (b.x0 + b.x1) / 2 + sx * 3.0
				D.box("TyreMark", V3(0.9, 0.004, RB.z1 - 1.5 - b.z1), CF(x, y0 + 0.03, (b.z1 + RB.z1 - 1.5) / 2), { c = C(40, 40, 40), m = M.SmoothPlastic, t = 0.72 })
			end
		end
	end)

	-- 5.3 벽: 아랫단 도장 (청회색) + 흰 · 오렌지 띠 + 샌드위치 패널 줄눈 -----------------------------------------------
	step(K, "walls", function()
		local dado = lk(C(56, 70, 92))
		local function band(w: string, s0: number, s1: number)
			local m = (s0 + s1) / 2
			local len = s1 - s0
			D.plate("Dado", len, 4.2, 0.02, D.wall(w, m, 2.1, 0.004), dado)
			D.plate("DadoLine", len, 0.15, 0.03, D.wall(w, m, 4.27, 0.004), lk(C(240, 240, 236)))
			D.plate("DadoLine", len, 0.1, 0.03, D.wall(w, m, 4.47, 0.004), lk(ORANGE))
			local n = math.floor(len / 3.4)
			for i = 1, n do
				D.plate("PanelSeam", 0.05, yR - 4.6, 0.025, D.wall(w, s0 + len * i / (n + 1), (4.6 + yR) / 2, 0.004), lk(C(176, 180, 184)))
			end
		end
		band("left", RB.z0, RB.z1 - 0.6)
		band("right", RB.z0, RB.z1 - 0.6)
		band("back", RB.x0, RB.x1)
		-- 위쪽 그래픽 띠
		D.plate("BayBand", 26, 1.3, 0.05, D.wall("left", 2.0, 12.4, 0.0), L.navyMatte)
		D.label("BayBandText", 24, 0.85, D.wall("left", 2.0, 12.4, 0.05), "광안 오토 서비스  ·  정직한 정비 · 투명한 견적", WHITE, nil, { d = 0.01, font = Enum.Font.GothamBold })
		D.plate("BayBand", 26, 1.3, 0.05, D.wall("right", -2.0, 12.4, 0.0), L.navyMatte)
		D.label("BayBandText", 24, 0.85, D.wall("right", -2.0, 12.4, 0.05), "엔진오일 · 타이어 · 얼라인먼트 · 배터리 · 에어컨", WHITE, nil, { d = 0.01, font = Enum.Font.GothamBold })
	end)

	-- 5.4 뒷벽 공구벽: 슬랫 패널 + 3D 공구 (맵 판때기 숨김) + 작업대 소품 + 공구함 (재구성) + 컴프레서 · 에어 배관 --------------
	step(K, "toolWall", function()
		local peg = G.byName.Pegboard and G.byName.Pegboard[1]
		if not peg then
			return
		end
		local zf = peg.max.Z + 0.01
		local off = zf - RB.z0
		local px, py = peg.c.X, peg.c.Y
		local pw, ph = peg.size.X, peg.size.Y
		D.plate("SlatPanel", pw, ph, 0.03, D.wall("back", px, py, off), lk(C(196, 200, 204), M.Metal))
		local ns = math.floor(ph / 0.5)
		for i = 1, ns - 1 do
			D.plate("SlatGroove", pw, 0.05, 0.035, D.wall("back", px, peg.min.Y + ph * i / ns, off), lk(C(120, 124, 130), M.Metal))
		end
		for _, nm in { "Wrench", "Screwdriver", "ScrewdriverTip", "Plier", "SocketSet", "HammerHandle", "HammerHead", "TapeMeasure" } do
			for _, r in G.byName[nm] or {} do
				if r.c.Z < RB.z0 + 1.2 then
					hideRec(G, r)
					if nm ~= "ScrewdriverTip" then
						bayTool(D, r, zf + 0.03)
					end
				end
			end
		end
		-- 공구벽 헤더 글자 (맵 PegboardHeader 앞)
		local hd = G.byName.PegboardHeader and G.byName.PegboardHeader[1]
		if hd then
			D.label("ToolWallHeader", 12, 0.4, D.wall("back", hd.c.X, hd.c.Y, hd.max.Z - RB.z0 + 0.005), "TOOL WALL  ·  사용한 공구는 제자리에", WHITE, nil, { d = 0.01 })
		end
		-- 작업대: 맵 상판 그대로 + 앞 앞치마 · 아래 선반 · 부품 통 + 상판 소품, 맵 바이스 상자 대신 실제 바이스
		local wb = G.byName.Workbench and G.byName.Workbench[1]
		if wb then
			local wx, wz, wy = wb.c.X, wb.c.Z, wb.max.Y
			D.box("BenchApron", V3(wb.size.X, 0.4, 0.06), CF(wx, wb.min.Y - 0.2, wb.max.Z - 0.04), lk(C(60, 96, 150), M.Metal))
			D.box("BenchShelf", V3(wb.size.X - 0.6, 0.06, wb.size.Z - 0.3), CF(wx, 0.65, wz), lk(C(120, 124, 130), M.Metal))
			for i = 0, 5 do
				local bx = wb.min.X + 1.2 + i * (wb.size.X - 2.4) / 5
				D.box("PartsBin", V3(1.0, 0.6, 1.2), CF(bx, 0.98, wz + 0.2), lk(if i % 2 == 0 then C(40, 90, 190) else C(220, 60, 40), M.Plastic))
				D.box("PartsBinLabel", V3(0.6, 0.18, 0.01), CF(bx, 1.05, wz + 0.81), lk(C(250, 250, 246)))
			end
			local vise = G.byName.Vise and G.byName.Vise[1]
			if vise then
				hideRec(G, vise)
				local vp = CF(vise.c.X, wy, vise.c.Z)
				D.box("ViseBase", V3(0.9, 0.2, 0.8), vp * CF(0, 0.1, 0), lk(C(40, 80, 150), M.Metal))
				D.box("ViseBody", V3(0.6, 0.5, 1.0), vp * CF(0, 0.45, 0), lk(C(40, 80, 150), M.Metal))
				D.box("ViseJawFixed", V3(0.9, 0.35, 0.12), vp * CF(0, 0.75, -0.35), lk(C(70, 72, 76), M.Metal))
				D.box("ViseJawMove", V3(0.9, 0.35, 0.12), vp * CF(0, 0.75, 0.05), lk(C(70, 72, 76), M.Metal))
				D.cyl("ViseScrew", 0.9, 0.08, vp * CF(0, 0.5, 0.65) * ANG(0, PI / 2, 0), L.steel)
				D.cyl("ViseHandle", 0.9, 0.06, vp * CF(0, 0.5, 1.1), L.steel)
			end
			-- 상판 소품: 브레이크 디스크 · 캘리퍼 · 오일필터 · 스프레이 · 걸레 · 작업등 · 멀티미터
			local function top(x: number, z: number, yaw: number?): CFrame
				return pf(x, wy, z, yaw or 0)
			end
			D.cyl("BrakeDisc", 0.12, 1.3, top(-16.0, wz + 0.2) * CF(0, 0.06, 0) * ANG(0, 0, PI / 2), lk(C(120, 120, 124), M.Metal, { r = 0.1 }))
			D.cyl("BrakeDiscHat", 0.2, 0.6, top(-16.0, wz + 0.2) * CF(0, 0.16, 0) * ANG(0, 0, PI / 2), lk(C(90, 90, 94), M.Metal))
			D.rbox("Caliper", V3(0.7, 0.35, 0.4), 0.1, top(-14.9, wz + 0.4, 20) * CF(0, 0.18, 0), lk(C(200, 40, 36), M.Metal))
			D.vcyl("OilFilter", 0.45, 0.36, top(-11.2, wz) * CF(0, 0.23, 0), lk(C(30, 60, 150), M.Metal))
			partBox(D, top(-10.5, wz + 0.1, 8), V3(0.45, 0.5, 0.45), C(240, 240, 236), "오일필터", hi)
			for i, col in { C(30, 80, 170), C(200, 40, 30), C(240, 200, 40) } do
				local sp = top(-8.6 + i * 0.32, wz - 0.3)
				D.vcyl("SprayCan", 0.75, 0.24, sp * CF(0, 0.375, 0), lk(col, M.Metal))
				D.vcyl("SprayCap", 0.14, 0.2, sp * CF(0, 0.82, 0), L.white)
			end
			D.ell("ShopRag", V3(0.9, 0.12, 0.7), top(-18.0, wz + 0.5) * CF(0, 0.06, 0), lk(C(200, 50, 40), M.Fabric))
			D.ell("ShopRag", V3(0.7, 0.1, 0.6), top(-17.7, wz + 0.3) * CF(0, 0.15, 0), lk(C(230, 230, 220), M.Fabric))
			local mm = top(-7.2, wz + 0.4, -15)
			D.rbox("Multimeter", V3(0.4, 0.12, 0.7), 0.05, mm * CF(0, 0.06, 0), lk(C(240, 190, 30), M.Plastic))
			D.box("MultimeterLCD", V3(0.26, 0.02, 0.2), mm * CF(0, 0.13, -0.15), lk(C(150, 170, 150)))
			-- 클램프 LED 작업등 (뒤쪽)
			local lp = top(-12.6, wb.min.Z + 0.2)
			D.box("LampClamp", V3(0.3, 0.3, 0.3), lp * CF(0, 0.15, 0), L.black)
			D.seg("LampArm", (lp * CF(0, 0.3, 0)).Position, (lp * CF(0.3, 1.8, 0.4)).Position, 0.07, L.black)
			D.seg("LampArm", (lp * CF(0.3, 1.8, 0.4)).Position, (lp * CF(0.6, 1.6, 1.1)).Position, 0.07, L.black)
			D.box("LampHead", V3(0.7, 0.12, 0.3), lp * CF(0.6, 1.55, 1.15) * ANG(0.4, 0, 0), L.black)
			D.box("LampLED", V3(0.6, 0.02, 0.22), lp * CF(0.6, 1.48, 1.17) * ANG(0.4, 0, 0), Look.lampCool)
			-- 바퀴 의자
			local sp = pf(-14.0, y0, wb.max.Z + 1.6, 160)
			if spot(G, sp, V3(1.3, 2.4, 1.3), 0, "benchStool") then
				Props.stool(K, G.B * sp, { style = "cushion", seatTop = 2.3, dia = 1.15, frame = L.darkAlu, seat = Look.leatherBlack })
			end
		end
		-- 공구함 (맵 빨간 상자 대신, 같은 자리 · 같은 크기 롤캡 + 상단 체스트)
		local tc = G.byName.ToolChest and G.byName.ToolChest[1]
		if tc then
			hideRec(G, tc)
			hideNamed(G, "DrawerLine")
			hideNamed(G, "ChestHandle")
			local w, d = tc.size.X, tc.size.Z
			local cx, cz = tc.c.X, tc.c.Z
			local fz = tc.max.Z
			local red = L.toolRed
			local y1 = tc.min.Y
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					caster(D, CF(cx + sx * (w / 2 - 0.35), 0, cz + sz * (d / 2 - 0.3)), y1)
				end
			end
			local cabH = (tc.max.Y - y1) * 0.6
			D.box("RollCab", V3(w, cabH, d), CF(cx, y1 + cabH / 2, cz), red)
			D.box("TopChest", V3(w - 0.1, tc.max.Y - y1 - cabH - 0.25, d - 0.15), CF(cx, y1 + cabH + (tc.max.Y - y1 - cabH - 0.25) / 2 + 0.05, cz - 0.05), red)
			D.box("TopChestLid", V3(w, 0.2, d - 0.1), CF(cx, tc.max.Y - 0.1, cz - 0.05), red)
			D.box("RollCabTop", V3(w + 0.05, 0.06, d + 0.05), CF(cx, y1 + cabH + 0.03, cz), lk(C(30, 30, 32), M.Rubber))
			D.bar("RollCabSideHandle", V3(cx + w / 2 + 0.25, y1 + cabH - 0.5, cz - 0.6), V3(cx + w / 2 + 0.25, y1 + cabH - 0.5, cz + 0.6), 0.08, 0.08, L.chrome)
			for _, s in { -0.6, 0.6 } do
				D.bar("RollCabSideHandlePost", V3(cx + w / 2, y1 + cabH - 0.5, cz + s), V3(cx + w / 2 + 0.25, y1 + cabH - 0.5, cz + s), 0.06, 0.06, L.chrome)
			end
			-- 서랍 (아래 롤캡 5 + 위 체스트 3)
			local hs = { 0.95, 0.75, 0.6, 0.5, 0.42 }
			local yy = y1 + 0.12
			local drawerParts = {}
			for i, hh in hs do
				local yc = yy + hh / 2
				local grp = {}
				table.insert(grp, D.box("Drawer", V3(w - 0.24, hh - 0.08, 0.06), CF(cx, yc, fz + 0.03), red))
				table.insert(grp, D.box("DrawerHandle", V3(w - 0.6, 0.07, 0.08), CF(cx, yc + hh / 2 - 0.14, fz + 0.1), L.alu))
				if i == 3 then
					-- 열리는 서랍: 안쪽 소켓 트레이
					table.insert(grp, D.box("DrawerTray", V3(w - 0.4, 0.04, d - 0.4), CF(cx, yc - hh / 2 + 0.08, cz + 0.1), lk(C(30, 30, 32), M.Rubber)))
					for k = 0, 7 do
						table.insert(grp, D.cyl("DrawerSocket", 0.35, 0.18 + k * 0.015, CF(cx - w / 2 + 0.6 + k * 0.5, yc - hh / 2 + 0.2, cz + 0.4) * ANG(0, PI / 2, 0), L.steel))
					end
					for _, p in grp do
						table.insert(drawerParts, { p = p, cf = p.CFrame })
					end
				end
				yy += hh
			end
			local ty0 = y1 + cabH + 0.1
			local th = tc.max.Y - 0.2 - ty0
			for i = 0, 2 do
				local hh = th / 3
				local yc = ty0 + hh * (i + 0.5)
				D.box("ChestDrawer", V3(w - 0.34, hh - 0.08, 0.05), CF(cx, yc, fz - 0.06), red)
				D.box("ChestDrawerHandle", V3(w - 0.8, 0.06, 0.07), CF(cx, yc + hh / 2 - 0.12, fz), L.alu)
			end
			D.label("ToolChestBadge", 1.4, 0.3, D.wall("back", cx, y1 + cabH - 0.25, fz - RB.z0 + 0.12), "GW PRO TOOLS", WHITE, nil, { d = 0.01, font = Enum.Font.GothamBlack })
			-- 상호작용: 서랍 열기 (클라이언트 파트만 앞으로 미끄러짐)
			local opened = false
			local handle = drawerParts[2] and drawerParts[2].p or nil
			prompt(G, handle, {
				action = "서랍 열기",
				object = "공구함",
				sound = "rbxasset://sounds/clickfast.wav",
				fn = function(_n: number, pr: ProximityPrompt)
					opened = not opened
					local dz = (G.V.cf * G.B).Rotation * V3(0, 0, if opened then 1.5 else 0)
					for _, rec in drawerParts do
						if rec.p.Parent then
							TweenService:Create(rec.p, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = rec.cf + dz }):Play()
						end
					end
					pr.ActionText = if opened then "서랍 닫기" else "서랍 열기"
				end,
			})
		end
		-- 컴프레서 디테일 + 에어 배관 (파란 알루미늄)
		local ct = G.byName.CompressorTank and G.byName.CompressorTank[1]
		local cm = G.byName.CompressorMotor and G.byName.CompressorMotor[1]
		local pipeL = lk(C(40, 110, 200), M.Metal)
		local yMain = 13.3
		local zPipe = RB.z0 + 0.45
		if ct and cm then
			D.disc("CompGauge", 0.45, 0.08, CF(ct.min.X + 0.6, ct.max.Y + 0.25, ct.max.Z - 0.2) * ANG(PI / 2, 0, 0), L.white)
			D.box("CompSwitch", V3(0.5, 0.6, 0.4), CF(cm.max.X - 0.25, cm.max.Y + 0.3, cm.c.Z), lk(C(50, 52, 56), M.Metal))
			D.box("CompBeltGuard", V3(0.3, 1.3, 1.4), CF(cm.min.X - 0.2, cm.c.Y, cm.c.Z), lk(C(240, 180, 30), M.Metal))
			D.vcyl("CompDrain", 0.3, 0.1, CF(ct.c.X, ct.min.Y - 0.1, ct.c.Z), L.chrome)
			D.label("CompLabel", 1.6, 0.4, D.wall("back", ct.c.X, ct.c.Y, ct.max.Z - RB.z0 + 0.01), "에어 컴프레서 10HP", WHITE, nil, { d = 0.01 })
			local up0 = V3(ct.max.X - 0.3, cm.max.Y, zPipe)
			D.seg("AirPipe", V3(cm.c.X, cm.max.Y + 0.6, cm.c.Z), up0 + V3(0, 0.6, 0), 0.14, pipeL)
			D.seg("AirPipe", up0 + V3(0, 0.6, 0), V3(up0.X, yMain, zPipe), 0.16, pipeL)
			D.seg("AirPipe", V3(up0.X, yMain, zPipe), V3(RB.x0 + 1.0, yMain, zPipe), 0.16, pipeL, 0.1)
			local x = RB.x0 + 3
			while x < up0.X do
				D.box("AirPipeClip", V3(0.12, 0.3, 0.45), CF(x, yMain, RB.z0 + 0.22), L.darkAlu)
				x += 4.2
			end
			-- 내림관 + FRL (필터 · 레귤레이터) + 커플러
			for _, dx in { -9.0, 3.0 } do
				D.seg("AirDrop", V3(dx, yMain, zPipe), V3(dx, 6.4, zPipe), 0.12, pipeL)
				D.vcyl("FRLFilter", 0.5, 0.28, CF(dx, 6.1, zPipe + 0.05), { c = C(220, 230, 236), m = M.Glass, t = 0.4 })
				D.box("FRLBody", V3(0.5, 0.35, 0.35), CF(dx, 6.55, zPipe), lk(C(60, 62, 66), M.Metal))
				D.disc("FRLGauge", 0.26, 0.05, CF(dx, 6.6, zPipe + 0.2) * ANG(PI / 2, 0, 0), L.white)
				D.vcyl("AirCoupler", 0.25, 0.12, CF(dx, 5.7, zPipe), Look.brass)
				D.ring("AirCoil", CF(dx, 4.9, zPipe + 0.25) * ANG(0, 0, 0), 0.45, 0.07, 10, lk(C(240, 190, 30), M.Rubber))
			end
			-- 천장 가지관 (가운데 통로 위, 트러스 아래 → 호스 릴)
			local bx = (laneX0 + laneX1) / 2 + 1.8
			D.seg("AirPipe", V3(bx, yMain, zPipe), V3(bx, trussY - 0.3, zPipe), 0.14, pipeL)
			D.seg("AirPipe", V3(bx, trussY - 0.3, zPipe), V3(bx, trussY - 0.3, trussZ[#trussZ] + 0.6), 0.14, pipeL, 0.1)
			G.airX = bx
		end
		-- 정비 현황 화이트보드
		local wbx = 16.4
		local bc = D.wall("back", wbx, 9.4, 0.0)
		D.plate("Whiteboard", 7.6, 3.8, 0.08, bc, L.alu)
		D.plate("WhiteboardFace", 7.4, 3.6, 0.02, bc * CF(0, 0, 0.08), lk(C(250, 250, 248)))
		D.label("WhiteboardHead", 7.0, 0.5, bc * CF(0, 1.45, 0.1), "오늘의 정비 현황", NAVY, nil, { d = 0.005, font = Enum.Font.GothamBlack })
		local rows = { "12가 3456  엔진오일 교환       ✔ 완료", "34나 7890  브레이크 패드(앞)  ▶ 작업중", "56다 1234  타이어 4본 교체     ▶ 작업중", "78라 5678  휠 얼라인먼트      ◻ 대기", "90마 2468  에어컨 필터           ◻ 대기" }
		for i, row in rows do
			D.label("WhiteboardRow", 7.0, 0.42, bc * CF(0, 1.0 - i * 0.5, 0.1), row, if string.find(row, "완료") then C(30, 130, 60) elseif string.find(row, "작업중") then C(200, 60, 30) else C(40, 50, 120), nil, { d = 0.005, font = Enum.Font.PatrickHand, align = "Left" })
		end
		D.box("WhiteboardTray", V3(5.0, 0.1, 0.3), CF(wbx, 7.45, RB.z0 + 0.2), L.alu)
		for i, col in { C(30, 30, 32), C(200, 40, 30), C(30, 70, 180) } do
			D.cyl("Marker", 0.5, 0.1, CF(wbx - 1.5 + i * 0.6, 7.56, RB.z0 + 0.22), lk(col))
		end
		-- 폐유 보관 (뒤 오른쪽 구석)
		local wp = pf(RB.x1 - 1.25, y0, RB.z0 + 1.3, 0)
		if spot(G, wp, V3(2.3, 3.4, 2.3), 0, "wasteOil") then
			propGroup(G, "wasteOil", V3(RB.x1 - 2.4, 0, RB.z0), V3(RB.x1, 3.4, RB.z0 + 2.5), function()
				D.box("SpillPallet", V3(2.3, 0.5, 2.3), wp * CF(0, 0.25, 0), L.yellow)
				D.box("SpillPalletGrid", V3(2.1, 0.04, 2.1), wp * CF(0, 0.52, 0), lk(C(40, 40, 42), M.DiamondPlate))
				D.vcyl("WasteDrum", 2.8, 1.9, wp * CF(-0.1, 0.54 + 1.4, -0.1), lk(C(30, 80, 170), M.Metal))
				for _, yy in { 0.9, 1.9 } do
					D.vcyl("WasteDrumRib", 0.06, 1.94, wp * CF(-0.1, 0.54 + yy, -0.1), lk(C(26, 66, 140), M.Metal))
				end
				D.vcyl("WasteFunnel", 0.5, 1.2, wp * CF(-0.1, 3.55, -0.1), lk(C(240, 200, 40), M.Plastic))
				D.label("WasteDrumLabel", 1.0, 0.5, wp * CF(-0.1, 1.9, 0.86), "폐유\n200L", WHITE, C(200, 30, 30), { d = 0.01 })
				D.rbox("JerryCan", V3(0.5, 1.1, 0.8), 0.08, wp * CF(0.85, 0.54 + 0.55, 0.5), lk(C(200, 40, 30), M.Plastic))
			end)
			safetySign(D, D.wall("back", RB.x1 - 1.3, 5.6, 0.02), 1.4, 1.6, "ban", "폐유 보관 · 화기엄금")
		end
	end)

	-- 5.5 오른쪽 벽: 오일 선반 (맵 상자 대신) · 얼라인먼트 · 타이어 탈착기 · 휠 밸런서 · 질소 · 타이어 랙 · 접수 카운터 + 요금표 --------
	step(K, "rightWall", function()
		local os = G.byName.OilShelf and G.byName.OilShelf[1]
		if os then
			hideRec(G, os)
			hideNamed(G, "OilCan")
			local w = os.size.Z
			local dep = RB.x1 - os.min.X
			local pcf = D.wallPf("right", os.c.Z, dep)
			local ys = angleRack(D, pcf, w, dep, 7.6, 5, { post = lk(C(60, 96, 150), M.Metal), board = lk(C(170, 174, 178), M.Metal) })
			-- 단마다 다른 물건
			local oilCols = { C(214, 170, 40), C(40, 130, 70), C(30, 30, 34), C(190, 40, 36), C(30, 80, 170) }
			local oilNames = { "5W-30\n4L", "0W-20\n4L", "5W-40\n4L", "ATF\n4L", "10W-30\n4L" }
			local n = math.floor((w - 0.6) / 0.78)
			for i = 0, n - 1 do
				local x = -w / 2 + 0.55 + i * 0.78
				local k = (i // 2) % #oilCols + 1
				oilJug(D, pcf * CF(x, ys[2], 0.15), oilCols[k], oilNames[k], hi and i % 2 == 0)
			end
			-- 1L 병 (브레이크액 · 부동액 · 워셔액)
			local bcols = { C(240, 240, 236), C(60, 180, 80), C(230, 90, 140), C(60, 130, 230) }
			local nb = math.floor((w - 0.6) / 0.45)
			for i = 0, nb - 1 do
				local x = -w / 2 + 0.45 + i * 0.45
				local col = bcols[(i // 3) % #bcols + 1]
				D.vcyl("FluidBottle", 0.8, 0.32, pcf * CF(x, ys[3] + 0.4, 0.2), lk(col, M.Plastic))
				D.vcyl("FluidCap", 0.12, 0.16, pcf * CF(x, ys[3] + 0.86, 0.2), L.black)
			end
			-- 오일필터 · 에어필터 상자
			local nf = math.floor((w - 0.6) / 0.75)
			for i = 0, nf - 1 do
				local x = -w / 2 + 0.6 + i * 0.75
				partBox(D, pcf * CF(x, ys[4], 0.1), V3(0.6, 0.6, 0.6), if i % 3 == 0 then C(30, 70, 160) elseif i % 3 == 1 then C(240, 240, 236) else C(220, 120, 30), if i % 4 == 0 then "오일필터" else nil, hi)
			end
			for i = 0, 5 do
				partBox(D, pcf * CF(-w / 2 + 1.1 + i * 1.8, ys[5], 0.05), V3(1.5, 0.4, 0.9), C(176, 136, 92), if i % 2 == 0 then "에어필터" else "에어컨필터", hi)
			end
			-- 바닥단: 20L 페일 + 상자
			for i = 0, 3 do
				D.vcyl("OilPail", 1.1, 0.95, pcf * CF(-w / 2 + 1.0 + i * 1.2, ys[1] + 0.55, 0.05), lk(if i % 2 == 0 then C(30, 70, 160) else C(214, 170, 40), M.Plastic))
				D.vcyl("OilPailLid", 0.06, 0.98, pcf * CF(-w / 2 + 1.0 + i * 1.2, ys[1] + 1.12, 0.05), L.black)
			end
			for i = 0, 2 do
				partBox(D, pcf * CF(1.5 + i * 1.6, ys[1], 0.05), V3(1.4, 0.9, 1.0), C(176, 136, 92), "와이퍼", hi)
			end
			-- 가격표 띠 + 머리 간판
			local prices = { "엔진오일 합성 4L 52,000", "부동액 · 브레이크액", "필터류 · 소모품", "에어필터 · 에어컨필터" }
			for i = 2, 5 do
				D.label("ShelfPriceTag", 2.6, 0.14, pcf * CF(-w / 2 + 1.6, ys[i] - 0.05, dep / 2 + 0.01), prices[i - 1], INK, C(250, 230, 60), { d = 0.01 })
			end
			D.label("OilShelfHead", 6.0, 0.6, D.wall("right", os.c.Z, 8.35, 0.02), "엔진오일 · 소모품", WHITE, NAVY, { d = 0.02, font = Enum.Font.GothamBlack })
		end
		-- 4륜 얼라인먼트 콘솔
		local az = -2.8
		local ap = D.wallPf("right", az, 2.2)
		if spot(G, ap, V3(3.2, 4.8, 2.2), 0, "alignment") then
			propGroup(G, "alignment", V3(RB.x1 - 2.3, 0, az - 1.7), V3(RB.x1, 4.8, az + 1.7), function()
				D.box("AlignCabinet", V3(2.8, 2.7, 1.8), ap * CF(0, 1.45, -0.1), lk(C(60, 64, 72), M.Metal))
				D.box("AlignFront", V3(2.6, 1.4, 0.04), ap * CF(0, 0.9, 0.81), lk(C(30, 90, 170)))
				D.box("AlignPlinth", V3(2.7, 0.1, 1.7), ap * CF(0, 0.05, -0.1), L.black)
				D.box("AlignKeyTray", V3(1.6, 0.1, 0.8), ap * CF(0, 2.3, 1.0), lk(C(70, 72, 76), M.Metal))
				D.box("AlignKeyboard", V3(1.4, 0.05, 0.5), ap * CF(0, 2.38, 1.0), L.black)
				D.box("AlignPost", V3(0.2, 1.0, 0.2), ap * CF(0, 3.3, -0.6), L.darkAlu)
				local sc = ap * CF(0, 4.05, -0.45) * ANG(math.rad(-6), 0, 0)
				D.box("AlignMonitor", V3(2.4, 1.45, 0.12), sc, L.black)
				D.label("AlignScreen", 2.26, 1.3, sc * CF(0, 0, 0.065), "4륜 얼라인먼트\n앞 토  0°05′  캠버 -0°30′\n뒤 토  0°08′  캠버 -0°45′", C(220, 240, 255), C(14, 40, 80), { d = 0.01, glow = 1.2 })
				D.label("AlignBadge", 1.8, 0.35, ap * CF(0, 1.9, 0.83), "WHEEL ALIGNMENT", WHITE, nil, { d = 0.01 })
				-- 센서 헤드 4 (옆 걸이)
				for _, sx in { -1, 1 } do
					for k = 0, 1 do
						local hp = ap * CF(sx * 1.6, 1.6 + k * 0.95, 0.1 - k * 0.5)
						D.box("SensorHook", V3(0.3, 0.06, 0.06), hp * CF(-sx * 0.05, 0.3, 0), L.chrome)
						D.box("SensorHead", V3(0.35, 0.55, 0.9), hp, lk(C(36, 38, 42), M.Plastic))
						D.box("SensorLens", V3(0.36, 0.2, 0.2), hp * CF(0, 0.1, 0.4), lk(C(40, 120, 220), M.Glass, { t = 0.2 }))
						D.bar("SensorClampArm", (hp * CF(0, -0.3, -0.3)).Position, (hp * CF(0, -0.9, -0.1)).Position, 0.08, 0.08, L.chrome)
					end
				end
			end)
		end
		-- 타이어 탈착기
		local tz = 1.9
		local tp = D.wallPf("right", tz, 3.0)
		if spot(G, tp, V3(2.8, 5.8, 3.0), 0, "tyreChanger") then
			propGroup(G, "tyreChanger", V3(RB.x1 - 3, 0, tz - 1.5), V3(RB.x1, 5.8, tz + 1.5), function()
				local body = lk(C(200, 40, 36), M.Metal)
				D.box("ChangerBase", V3(2.4, 2.4, 2.0), tp * CF(0, 1.2, -0.2), body)
				D.box("ChangerPlinth", V3(2.5, 0.12, 2.1), tp * CF(0, 0.06, -0.2), L.black)
				D.disc("ChangerTable", 2.0, 0.14, tp * CF(0, 2.47, 0.1), lk(C(70, 72, 76), M.Metal))
				for i = 0, 3 do
					local a = i * PI / 2 + PI / 4
					D.box("ChangerJaw", V3(0.22, 0.2, 0.45), tp * CF(math.cos(a) * 0.75, 2.62, 0.1 + math.sin(a) * 0.75) * ANG(0, -a, 0), lk(C(200, 204, 210), M.Metal))
				end
				tyre(D, tp * CF(0, 3.0, 0.1) * ANG(0, 0, PI / 2), 2.2, { rim = true, w = 0.75, spokes = 5 })
				D.box("ChangerColumn", V3(0.45, 3.4, 0.45), tp * CF(0, 3.9, -1.0), body)
				D.box("ChangerArm", V3(0.35, 0.35, 1.5), tp * CF(0, 5.45, -0.35), body)
				D.box("ChangerShaft", V3(0.22, 1.9, 0.22), tp * CF(0.4, 4.5, 0.3), L.chrome)
				D.box("ChangerHead", V3(0.3, 0.3, 0.42), tp * CF(0.4, 3.45, 0.3), lk(C(240, 200, 40), M.Plastic))
				-- 비드 브레이커 (옆 레버)
				D.bar("BeadArm", (tp * CF(1.25, 2.1, -0.8)).Position, (tp * CF(1.35, 1.2, 0.9)).Position, 0.16, 0.16, body)
				D.box("BeadBlade", V3(0.08, 0.6, 0.5), tp * CF(1.25, 1.1, 0.95), L.chrome)
				D.box("BeadPad", V3(0.1, 1.0, 0.8), tp * CF(1.22, 1.1, -0.2), L.rubber)
				-- 페달 3 · 공기 게이지
				for i = -1, 1 do
					D.box("ChangerPedal", V3(0.3, 0.1, 0.5), tp * CF(i * 0.45, 0.2, 0.95) * ANG(math.rad(15), 0, 0), L.black)
				end
				D.disc("ChangerGauge", 0.4, 0.08, tp * CF(-1.0, 2.0, 0.82) * ANG(PI / 2, 0, 0), L.white)
				D.seg("ChangerHose", (tp * CF(-1.0, 1.8, 0.85)).Position, (tp * CF(-1.4, 0.4, 1.2)).Position, 0.07, L.black)
				D.vcyl("BeadLubeBucket", 0.5, 0.5, tp * CF(-1.0, 2.65, -0.4), lk(C(30, 80, 170), M.Plastic))
				D.label("ChangerLabel", 1.6, 0.35, tp * CF(0, 1.5, 0.81), "타이어 탈착기", WHITE, nil, { d = 0.01 })
			end)
		end
		-- 휠 밸런서 (+ 밸런스 측정 상호작용)
		local bz = 6.5
		local bp = D.wallPf("right", bz, 2.6)
		if spot(G, bp * CF(-0.6, 0, 0), V3(3.3, 4.0, 2.6), 0, "balancer") then
			propGroup(G, "balancer", V3(RB.x1 - 2.6, 0, bz - 2.3), V3(RB.x1, 4, bz + 1.1), function()
				local body = lk(C(40, 44, 52), M.Metal)
				D.box("BalancerBody", V3(1.6, 2.1, 1.5), bp * CF(0.3, 1.05, -0.3), body)
				D.box("BalancerTop", V3(1.7, 0.1, 1.6), bp * CF(0.3, 2.15, -0.3), lk(C(200, 40, 36), M.Metal))
				D.box("BalancerWeightTray", V3(1.2, 0.12, 0.8), bp * CF(0.3, 2.26, 0.0), lk(C(30, 30, 32)))
				for i = 0, 5 do
					D.box("BalanceWeight", V3(0.12, 0.06, 0.25), bp * CF(-0.15 + i * 0.18, 2.35, 0.0), L.steel)
				end
				local con = bp * CF(0.3, 2.95, -0.85) * ANG(math.rad(-15), 0, 0)
				D.box("BalancerConsole", V3(1.5, 1.0, 0.25), con, L.black)
				local _, readout = D.label("BalancerScreen", 1.36, 0.82, con * CF(0, 0, 0.13), "L  0g\nR  0g", C(255, 90, 60), C(14, 14, 16), { d = 0.01, glow = 1.4, font = Enum.Font.RobotoMono })
				-- 축 + 바퀴 (축은 왼쪽 = 벽을 따라 -Z)
				D.cyl("BalancerShaft", 1.3, 0.2, bp * CF(-0.95, 1.6, 0.0), L.chrome)
				local i0 = #K.parts
				tyre(D, bp * CF(-1.45, 1.6, 0.0), 2.25, { rim = true, w = 0.8, spokes = 6 })
				local wheel = {}
				for i = i0 + 1, #K.parts do
					table.insert(wheel, { p = K.parts[i], cf = K.parts[i].CFrame })
				end
				D.cyl("BalancerWingNut", 0.4, 0.5, bp * CF(-1.95, 1.6, 0.0), L.chrome)
				-- 후드 (올린 상태, 바퀴 뒤 위)
				for k = 0, 3 do
					local a = math.rad(20 + k * 22)
					D.box("BalancerHood", V3(1.1, 0.06, 0.7), bp * CF(-1.45, 1.6 + math.sin(a) * 1.55, -math.cos(a) * 1.55) * ANG(-(PI / 2 - a), 0, 0), lk(C(200, 40, 36), M.Plastic))
				end
				local busy = false
				prompt(G, (K.parts[i0 + 1] :: BasePart?) or nil, {
					action = "휠 밸런스 측정",
					object = "휠 밸런서",
					fn = function()
						if busy then
							return
						end
						busy = true
						readout.Text = "측정 중..."
						local axisW = (G.V.cf * G.B * bp).XVector
						local centre = (G.V.cf * G.B * bp * CF(-1.45, 1.6, 0)).Position
						task.spawn(function()
							local t0 = os.clock()
							while os.clock() - t0 < 3 do
								local a = (os.clock() - t0) * 18
								local rot = CFrame.new(centre) * CFrame.fromAxisAngle(axisW, a) * CFrame.new(-centre)
								for _, w in wheel do
									if w.p.Parent then
										w.p.CFrame = rot * w.cf
									end
								end
								task.wait()
							end
							for _, w in wheel do
								if w.p.Parent then
									w.p.CFrame = w.cf
								end
							end
							readout.Text = "L 15g → 0g\nR 10g → 0g  OK"
							busy = false
						end)
					end,
				})
			end)
		end
		-- 질소 충전기
		local np = D.wallPf("right", 9.9, 1.2)
		if spot(G, np, V3(1.3, 4.6, 1.2), 0, "nitrogen") then
			propGroup(G, "nitrogen", V3(RB.x1 - 1.2, 0, 9.2), V3(RB.x1, 4.6, 10.6), function()
				D.box("N2Cabinet", V3(1.2, 4.4, 1.05), np * CF(0, 2.2, 0), lk(C(240, 240, 238), M.Metal))
				D.box("N2Band", V3(1.22, 0.6, 1.07), np * CF(0, 3.6, 0), lk(C(30, 140, 80)))
				D.label("N2Label", 1.0, 0.45, np * CF(0, 3.6, 0.54), "N2 질소", WHITE, nil, { d = 0.01, font = Enum.Font.GothamBlack })
				D.box("N2Display", V3(0.6, 0.3, 0.02), np * CF(0, 2.8, 0.53), lk(C(255, 90, 60), M.Neon, { t = 0.2 }))
				D.ring("N2HoseCoil", np * CF(0, 1.6, 0.6), 0.4, 0.08, 10, L.black)
			end)
		end
		-- 신품 타이어 랙
		local rz0, rz1 = 11.0, 16.2
		local rp = D.wallPf("right", (rz0 + rz1) / 2, 1.4)
		if spot(G, rp, V3(rz1 - rz0, 5.8, 1.4), 0, "tyreRack") then
			propGroup(G, "tyreRack", V3(RB.x1 - 1.4, 0, rz0), V3(RB.x1, 5.8, rz1), function()
				local ys = angleRack(D, rp, rz1 - rz0, 1.4, 5.6, 2, {})
				local sizes = { "205/55R16\n89,000", "225/45R17\n119,000", "235/55R19\n169,000", "215/60R16\n95,000", "245/40R18\n149,000" }
				for t = 1, 2 do
					for i = 0, 4 do
						local x = -(rz1 - rz0) / 2 + 0.6 + i * 1.0
						tyre(D, rp * CF(x, ys[t] + 1.15, 0.05) * ANG(0, 0, 0), 2.25, { w = 0.82 })
						if t == 1 and mid then
							D.label("TyreTag", 0.9, 0.42, rp * CF(x, ys[t] + 0.35, 0.72), sizes[i + 1], INK, C(250, 230, 60), { d = 0.01 })
						end
					end
				end
				D.label("TyreRackHead", 4.6, 0.55, D.wall("right", (rz0 + rz1) / 2, 6.3, 0.02), "신품 타이어 · 교체 공임 1본 10,000원", WHITE, NAVY, { d = 0.02 })
			end)
		end
		-- 접수 카운터 (오른쪽 앞 구석, 서버 '정비 받기' 앵커 옆) + 요금표
		local cz0, cz1 = 17.8, math.min(23.2, RB.z1 - 1.8)
		local cx0, cx1 = RB.x1 - 3.7, RB.x1 - 2.1
		local cpf = pf((cx0 + cx1) / 2, y0, (cz0 + cz1) / 2, -90)
		if spot(G, cpf, V3(cz1 - cz0, 3.5, cx1 - cx0), 0, "reception") then
			propGroup(G, "reception", V3(cx0, 0, cz0), V3(RB.x1, 6, cz1), function()
				local len = cz1 - cz0
				D.box("ReceptionBody", V3(len, 3.25, 1.6), cpf * CF(0, 1.625, 0), lk(C(240, 240, 236)))
				D.box("ReceptionFront", V3(len, 2.6, 0.05), cpf * CF(0, 1.6, 0.82), L.navyMatte)
				D.box("ReceptionLine", V3(len, 0.08, 0.06), cpf * CF(0, 2.75, 0.84), L.orangeNeon)
				D.box("ReceptionKick", V3(len - 0.1, 0.28, 0.05), cpf * CF(0, 0.14, 0.78), L.black)
				D.box("ReceptionTop", V3(len + 0.2, 0.12, 1.9), cpf * CF(0, 3.31, 0.1), Look.marbleWhite)
				D.label("ReceptionSign", 3.4, 0.6, cpf * CF(0, 1.95, 0.86), "정비 접수 · 상담", WHITE, nil, { d = 0.01, font = Enum.Font.GothamBlack })
				local top = function(x: number, z: number, yaw: number?): CFrame
					return cpf * CF(x, 3.37, z) * ANG(0, math.rad(yaw or 0), 0)
				end
				Props.cardTerminal(K, G.B * top(-1.2, 0.6, 0))
				Props.bell(K, G.B * top(0.9, 0.65))
				Props.receiptPrinter(K, G.B * top(1.5, -0.4, 180))
				local mp = top(0.0, -0.4, 180)
				D.box("ReceptionMonitorStand", V3(0.5, 0.6, 0.3), mp * CF(0, 0.3, 0), L.darkAlu)
				D.box("ReceptionMonitor", V3(1.9, 1.15, 0.1), mp * CF(0, 1.15, 0), L.black)
				D.label("ReceptionMonitorScreen", 1.8, 1.05, mp * CF(0, 1.15, 0.055), "입고 차량 4대\n대기 2 · 작업 2", WHITE, C(20, 54, 110), { d = 0.005, glow = 1.1 })
				D.box("CouponStand", V3(0.7, 0.9, 0.3), top(-1.9, 0.5) * CF(0, 0.45, 0) * ANG(math.rad(-12), 0, 0), L.glassClear)
				D.label("CouponCard", 0.6, 0.8, top(-1.9, 0.52) * CF(0, 0.48, 0.03) * ANG(math.rad(-12), 0, 0), "정비 쿠폰\n엔진오일\n10% 할인", INK, C(250, 240, 220), { d = 0.01 })
				-- 직원 쪽: 스툴 · 뒤 캐비닛 · 고객 차키 보드
				Props.stool(K, G.B * (cpf * CF(0.4, 0, -1.3)), { style = "cushion", seatTop = 2.6, dia = 1.1, frame = L.darkAlu, seat = Look.leatherBlack })
				local kb = D.wall("right", (cz0 + cz1) / 2 + 0.6, 5.0, 0.0)
				D.plate("CarKeyBoard", 2.6, 1.4, 0.08, kb, lk(C(30, 32, 36)))
				D.label("CarKeyBoardHead", 2.4, 0.3, kb * CF(0, 0.5, 0.09), "고객 차량 키", WHITE, nil, { d = 0.005 })
				for i = 0, 5 do
					D.plate("CustomerKey", 0.14, 0.4, 0.06, kb * CF(-1.0 + i * 0.4, -0.15, 0.08), L.black)
					D.plate("CustomerKeyTag", 0.24, 0.24, 0.02, kb * CF(-1.0 + i * 0.4, -0.5, 0.12), lk(({ C(240, 200, 40), C(230, 80, 40), C(60, 140, 220) })[i % 3 + 1]))
				end
			end)
		end
		-- 정비 요금표 (오른쪽 벽, 접수 위)
		local items = {
			{ "엔진오일 교환 (합성유)", "69,000~" }, { "에어컨 필터", "20,000" }, { "에어 클리너", "20,000" },
			{ "브레이크 패드 (앞)", "80,000~" }, { "타이어 교체 공임 (1본)", "10,000" }, { "휠 얼라인먼트", "40,000" },
			{ "배터리 교체", "120,000~" }, { "와이퍼 (1조)", "15,000" }, { "미션오일 교환", "120,000~" }, { "냉각수 교환", "50,000" },
			{ "차량 점검 · 진단", "무료" },
		}
		local pbz = (17.8 + math.min(23.2, RB.z1 - 1.8)) / 2 - 0.5
		local pdcf = D.wall("right", pbz, 7.9, 0.0)
		priceBoard(D, pdcf, 7.2, 4.6, "정비 요금표 · 광안 오토 서비스", items, { cols = 2, accent = C(200, 60, 24), frame = L.navy })
		local strip = D.plate("PriceBoardLight", 6.6, 0.08, 0.3, pdcf * CF(0, 2.5, 0.0), Look.lampNeutral)
		D.light(strip, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 8, Brightness = 0.8, Angle = 120, Color = Look.neutralLight })
	end)

	-- 5.6 왼쪽 벽: 부품 선반 · 배터리 충전기 · 세면대 · 안전 게시물 · 작업등 · 폐타이어 · 소화전 ------------------------------
	step(K, "leftWall", function()
		local pz0, pz1 = RB.z0 + 2.8, RB.z0 + 12.8
		local pp = D.wallPf("left", (pz0 + pz1) / 2, 1.6)
		if spot(G, pp, V3(pz1 - pz0, 7.6, 1.6), 0, "partsRack") then
			propGroup(G, "partsRack", V3(RB.x0, 0, pz0), V3(RB.x0 + 1.6, 7.6, pz1), function()
				local w = pz1 - pz0
				local ys = angleRack(D, pp, w, 1.6, 7.4, 5, { brace = true })
				local labels = { "오일필터", "에어필터", "에어컨필터", "브레이크패드", "와이퍼", "점화플러그", "벨트", "전구 · 퓨즈" }
				local cols = { C(176, 136, 92), C(240, 240, 236), C(30, 70, 160), C(220, 120, 30), C(176, 136, 92) }
				local li = 1
				for t = 2, 5 do
					local n = 6
					for i = 0, n - 1 do
						local x = -w / 2 + 0.85 + i * (w - 1.4) / (n - 1)
						local s = V3(1.2, 0.55 + ((i + t) % 3) * 0.15, 1.0)
						local lab = nil
						if i % 2 == 0 then
							lab = labels[(li - 1) % #labels + 1]
							li += 1
						end
						partBox(D, pp * CF(x, ys[t], 0.05), s, cols[(i + t) % #cols + 1], lab, hi)
					end
				end
				-- 바닥단: 배터리 3
				for i = 0, 2 do
					local bp = pp * CF(-w / 2 + 1.4 + i * 1.5, ys[1], 0.1)
					D.box("CarBattery", V3(1.2, 0.85, 0.7), bp * CF(0, 0.425, 0), L.black)
					D.box("CarBatteryTop", V3(1.2, 0.06, 0.7), bp * CF(0, 0.88, 0), lk(C(60, 62, 66)))
					D.vcyl("BatteryPos", 0.12, 0.14, bp * CF(-0.4, 0.95, 0.15), lk(C(200, 40, 30)))
					D.vcyl("BatteryNeg", 0.12, 0.14, bp * CF(0.4, 0.95, 0.15), L.black)
					D.label("BatteryLabel", 0.9, 0.3, bp * CF(0, 0.45, 0.36), "AGM 80Ah", WHITE, C(30, 70, 160), { d = 0.01 })
				end
				D.label("PartsRackHead", 4.0, 0.55, D.wall("left", (pz0 + pz1) / 2, 8.1, 0.02), "부품 보관", WHITE, NAVY, { d = 0.02, font = Enum.Font.GothamBlack })
			end)
		end
		-- 배터리 충전기 카트
		local cp = D.wallPf("left", pz1 + 1.2, 1.3)
		if spot(G, cp, V3(1.3, 3.2, 1.3), 0, "charger") then
			propGroup(G, "charger", V3(RB.x0, 0, pz1 + 0.5), V3(RB.x0 + 1.3, 3.2, pz1 + 1.9), function()
				D.box("ChargerBody", V3(1.1, 1.5, 0.9), cp * CF(0, 1.1, 0), lk(C(220, 40, 30), M.Metal))
				D.box("ChargerPanel", V3(0.8, 0.5, 0.02), cp * CF(0, 1.4, 0.46), L.black)
				D.box("ChargerDisplay", V3(0.5, 0.2, 0.02), cp * CF(0, 1.5, 0.47), lk(C(80, 255, 120), M.Neon, { t = 0.2 }))
				D.bar("ChargerHandle", (cp * CF(-0.5, 2.0, -0.4)).Position, (cp * CF(-0.5, 3.0, -0.6)).Position, 0.08, 0.08, L.chrome)
				D.bar("ChargerHandle", (cp * CF(0.5, 2.0, -0.4)).Position, (cp * CF(0.5, 3.0, -0.6)).Position, 0.08, 0.08, L.chrome)
				D.bar("ChargerHandleBar", (cp * CF(-0.5, 3.0, -0.6)).Position, (cp * CF(0.5, 3.0, -0.6)).Position, 0.08, 0.08, L.chrome)
				for _, sx in { -1, 1 } do
					D.cyl("ChargerWheel", 0.15, 0.6, cp * CF(sx * 0.6, 0.3, -0.25), L.rubber)
					D.seg("ChargerCable", (cp * CF(sx * 0.3, 1.0, 0.45)).Position, (cp * CF(sx * 0.45, 0.25, 0.75)).Position, 0.06, lk(if sx < 0 then C(200, 30, 30) else C(20, 20, 22)))
					D.box("ChargerClamp", V3(0.15, 0.15, 0.3), cp * CF(sx * 0.45, 0.15, 0.8), lk(if sx < 0 then C(200, 30, 30) else C(20, 20, 22)))
				end
				D.label("ChargerLabel", 0.9, 0.25, cp * CF(0, 0.6, 0.46), "배터리 충전기", WHITE, nil, { d = 0.01 })
			end)
		end
		-- 세면대
		local sz = pz1 + 4.2
		local sp = D.wallPf("left", sz, 1.5)
		if spot(G, sp, V3(2.2, 3.4, 1.5), 0, "sink") then
			propGroup(G, "sink", V3(RB.x0, 0, sz - 1.1), V3(RB.x0 + 1.5, 6, sz + 1.1), function()
				D.box("SinkBasin", V3(2.1, 0.8, 1.4), sp * CF(0, 2.8, 0), L.stainless)
				D.box("SinkWell", V3(1.8, 0.05, 1.1), sp * CF(0, 3.2, 0.05), lk(C(120, 124, 128), M.Metal))
				for _, sx in { -1, 1 } do
					for _, szz in { -1, 1 } do
						D.box("SinkLeg", V3(0.12, 2.4, 0.12), sp * CF(sx * 0.9, 1.2, szz * 0.55), L.stainless)
					end
				end
				D.box("SinkShelf", V3(1.9, 0.05, 1.2), sp * CF(0, 0.6, 0), L.stainless)
				D.vcyl("SinkFaucet", 0.7, 0.12, sp * CF(0, 3.55, -0.55), L.chrome)
				D.seg("SinkSpout", (sp * CF(0, 3.85, -0.55)).Position, (sp * CF(0, 3.85, -0.1)).Position, 0.1, L.chrome)
				D.vcyl("SoapPump", 0.6, 0.35, sp * CF(0.7, 3.5, -0.4), lk(C(240, 160, 30), M.Plastic))
				D.label("SoapLabel", 0.32, 0.3, sp * CF(0.7, 3.5, -0.22), "기름때\n세정제", INK, C(250, 240, 210), { d = 0.005 })
				local td = D.wall("left", sz, 5.0, 0.0)
				D.plate("TowelDispenser", 1.1, 1.2, 0.4, td, L.white)
				D.plate("TowelSlot", 0.8, 0.06, 0.02, td * CF(0, -0.5, 0.4), L.black)
			end)
		end
		-- 안전 게시물
		notice(D, D.wall("left", 0.5, 6.4, 0.0), 3.4, 4.2, "리프트 안전수칙", "1. 하부 작업 전 안전 잠금 확인\n2. 정격 하중 3.5톤 초과 금지\n3. 상승 · 하강 중 하부 출입 금지\n4. 작업 후 암 원위치 · 전원 OFF", { head = C(200, 40, 30) })
		notice(D, D.wall("left", 5.0, 6.4, 0.0), 3.4, 4.2, "작업장 안전수칙", "· 보안경 · 안전화 착용\n· 작업장 내 금연 · 화기엄금\n· 폐유는 지정 장소에\n· 소화기 위치 확인", { head = C(30, 100, 60) })
		local signs = { { "must", "보안경 착용" }, { "must", "안전화 착용" }, { "ban", "금연" }, { "warn", "협착 주의" } }
		for i, s in signs do
			safetySign(D, D.wall("left", -2.5 + (i - 1) * 1.15 - 0.6, 3.25, 0.02), 1.0, 1.2, s[1], s[2])
		end
		-- 이동식 LED 작업등 (리프트 1 옆, 켜기/끄기)
		local wl0 = firstSpot(G, { pf(RB.x0 + 0.85, y0, 10.0, 90), pf(RB.x0 + 0.85, y0, 12.5, 90), pf(RB.x0 + 0.85, y0, -4.5, 90), pf(RB.x0 + 0.85, y0, -6.5, 90) }, V3(1.6, 5.4, 1.6), 0, "workLight")
		local wl = wl0 or CF()
		if wl0 then
			propGroup(G, "workLight", V3(RB.x0, 0, wl.Z - 0.9), V3(RB.x0 + 2.2, 5.4, wl.Z + 0.9), function()
				for i = 0, 2 do
					local a = i * 2 * PI / 3
					D.seg("TripodLeg", (wl * CF(0, 2.0, 0)).Position, (wl * CF(math.cos(a) * 0.75, 0.02, math.sin(a) * 0.75)).Position, 0.07, L.black)
				end
				D.seg("TripodMast", (wl * CF(0, 2.0, 0)).Position, (wl * CF(0, 4.6, 0)).Position, 0.08, L.black)
				local head = wl * CF(0, 4.8, 0.1) * ANG(math.rad(-25), 0, 0)
				D.box("WorkLightHousing", V3(1.4, 0.9, 0.3), head, lk(C(240, 190, 30), M.Plastic))
				local lens = D.box("WorkLightLens", V3(1.25, 0.75, 0.02), head * CF(0, 0, 0.16), Look.lampCool)
				D.box("WorkLightGrip", V3(1.0, 0.1, 0.1), head * CF(0, 0.55, 0), L.black)
				local lt = D.light(lens, "SpotLight", { Face = Enum.NormalId.Back, Range = 20, Angle = 70, Brightness = 1.2, Color = Look.coolLight })
				local on = true
				prompt(G, lens, {
					action = "작업등 끄기",
					object = "LED 작업등",
					fn = function(_n: number, pr: ProximityPrompt)
						on = not on
						if lt then
							lt.Enabled = on
						end
						lens.Material = if on then M.Neon else M.SmoothPlastic
						lens.Color = if on then C(232, 242, 255) else C(170, 176, 182)
						pr.ActionText = if on then "작업등 끄기" else "작업등 켜기"
					end,
				})
			end)
		end
		-- 폐타이어 (앞쪽 왼쪽)
		for k = 0, 1 do
			local tp = pf(RB.x0 + 1.4, y0, 15.4 + k * 2.6, 0)
			if spot(G, tp, V3(2.5, 3.6, 2.5), 0, "usedTyres") then
				propGroup(G, "usedTyres", V3(RB.x0, 0, 14.1 + k * 2.6), V3(RB.x0 + 2.7, 3.6, 16.7 + k * 2.6), function()
					for i = 0, 3 - k do
						tyre(D, tp * CF(0, 0.42 + i * 0.84, 0) * ANG(0, i * 0.4, PI / 2), 2.4, { w = 0.82 })
					end
				end)
			end
		end
		D.label("UsedTyreSign", 2.4, 0.5, D.wall("left", 16.7, 4.6, 0.02), "폐타이어 수거", WHITE, C(90, 94, 100), { d = 0.02 })
		-- 옥내소화전함 + 비상벨
		local hz = RB.z1 - 3.9
		local hc = D.wall("left", hz, 2.9, 0.0)
		D.plate("HydrantCabinet", 1.6, 3.6, 0.45, hc, lk(C(196, 30, 30)))
		D.plate("HydrantWindow", 1.2, 1.6, 0.02, hc * CF(0, 0.4, 0.45), { c = C(220, 230, 236), m = M.Glass, t = 0.5 })
		D.cyl("HydrantHose", 0.3, 1.0, hc * CF(0, 0.4, 0.25) * ANG(0, PI / 2, 0), lk(C(230, 220, 200), M.Fabric))
		D.label("HydrantLabel", 1.4, 0.4, hc * CF(0, -1.2, 0.46), "소화전", WHITE, nil, { d = 0.01, font = Enum.Font.GothamBlack })
		Props.fireBell(K, G.B * D.wall("left", hz, 5.4, 0.0))
		-- 구급함
		local fa = D.wall("left", 12.6, 5.0, 0.0)
		D.plate("FirstAid", 1.2, 1.0, 0.35, fa, L.white)
		D.label("FirstAidLabel", 1.0, 0.7, fa * CF(0, 0, 0.36), "✚ 구급함", C(200, 30, 30), nil, { d = 0.01 })
		-- 소화기 (맵 자리)
		for _, r in G.byName.FireExtinguisher or {} do
			hideRec(G, r)
			for _, q in G.byName.ExtinguisherValve or {} do
				if (q.c - r.c).Magnitude < 1.5 then
					hideRec(G, q)
				end
			end
			extinguisher(D, V3(r.c.X, y0, r.c.Z), 90)
			safetySign(D, D.wall("left", r.c.Z, 3.6, 0.03), 0.9, 1.1, "fire", "소화기")
		end
	end)

	-- 5.7 뒤쪽 바닥 장비: 진단기 카트 · 폐유 수거기 · 플로어 잭 · 잭 스탠드 · 크리퍼 · 공구 카트 ---------------------------------
	step(K, "equipment", function()
		-- OBD 진단기 카트 (차량 진단 화면 순환)
		local op = pf((laneX0 + laneX1) / 2 + 0.4, y0, -10.4, 0)
		if spot(G, op, V3(1.8, 4.2, 1.3), 0, "obd") then
			propGroup(G, "obd", V3(op.X - 0.9, 0, op.Z - 0.7), V3(op.X + 0.9, 4.2, op.Z + 0.7), function()
				for _, sx in { -1, 1 } do
					for _, sz in { -1, 1 } do
						caster(D, op * CF(sx * 0.7, 0, sz * 0.45), 0.4)
						D.box("CartPost", V3(0.08, 2.9, 0.08), op * CF(sx * 0.75, 1.85, sz * 0.5), L.darkAlu)
					end
				end
				for _, yy in { 0.6, 1.9, 3.25 } do
					D.box("CartShelf", V3(1.65, 0.08, 1.15), op * CF(0, yy, 0), lk(C(40, 44, 50), M.Metal))
				end
				D.box("CartPrinter", V3(1.0, 0.45, 0.8), op * CF(0, 2.17, 0), L.white)
				D.box("CartVCI", V3(0.5, 0.25, 0.35), op * CF(-0.45, 3.42, 0.25), lk(C(240, 190, 30), M.Plastic))
				D.seg("OBDCable", (op * CF(-0.45, 3.42, 0.45)).Position, (op * CF(-0.9, 1.2, 0.7)).Position, 0.06, L.black)
				D.box("OBDPlug", V3(0.2, 0.15, 0.3), op * CF(-0.9, 1.1, 0.72), L.black)
				local base = op * CF(0.2, 3.3, -0.1)
				D.box("LaptopBase", V3(1.2, 0.06, 0.85), base, lk(C(40, 42, 46), M.Metal))
				local scr = base * CF(0, 0.45, -0.42) * ANG(math.rad(-12), 0, 0)
				D.box("LaptopLid", V3(1.2, 0.85, 0.05), scr, lk(C(40, 42, 46), M.Metal))
				local spart, slab = D.label("LaptopScreen", 1.1, 0.75, scr * CF(0, 0, 0.03), "", C(220, 255, 220), C(10, 30, 20), { d = 0.005, glow = 1.3, font = Enum.Font.RobotoMono })
				local pages = {
					"GW DIAG v5.2\nOBD-II 연결됨\n스캔 준비",
					"스캔 중 ...\nECU · TCU · ABS\n에어백 · BCM",
					"고장코드 0건\n엔진 · 변속기 정상\n배터리 12.6V",
					"엔진오일 교환 권장\n주행 8,500km 경과\n브레이크 패드 70%",
				}
				slab.Text = pages[1]
				Interact.cycle(K, spart, pages, {
					action = "차량 진단",
					object = "OBD 진단기",
					on = function(_i: number, s: string)
						slab.Text = s
					end,
				})
				D.label("OBDCartLabel", 1.2, 0.3, op * CF(0, 1.3, 0.58), "진단기", WHITE, NAVY, { d = 0.01 })
			end)
		end
		-- 폐유 수거기 (리프트 1 뒤)
		local b1 = bays[1]
		local dp = pf((b1.x0 + b1.x1) / 2 - 3.0, y0, b1.z0 - 2.2, 0)
		if spot(G, dp, V3(1.8, 5.0, 1.8), 0, "drainCaddy") then
			propGroup(G, "drainCaddy", V3(dp.X - 0.9, 0, dp.Z - 0.9), V3(dp.X + 0.9, 5, dp.Z + 0.9), function()
				for i = 0, 3 do
					local a = i * PI / 2 + PI / 4
					caster(D, dp * CF(math.cos(a) * 0.7, 0, math.sin(a) * 0.7), 0.35)
				end
				D.vcyl("CaddyTank", 1.5, 1.5, dp * CF(0, 1.1, 0), lk(C(240, 196, 30), M.Metal))
				D.vcyl("CaddyTankTop", 0.1, 1.55, dp * CF(0, 1.88, 0), lk(C(200, 160, 20), M.Metal))
				D.vcyl("CaddyGauge", 1.2, 0.12, dp * CF(0.75, 1.1, 0), { c = C(220, 230, 236), m = M.Glass, t = 0.3 })
				D.vcyl("CaddyPole", 2.0, 0.16, dp * CF(0, 2.9, 0), L.chrome)
				D.vcyl("CaddyFunnelNeck", 0.4, 0.4, dp * CF(0, 4.0, 0), lk(C(30, 30, 32), M.Plastic))
				D.vcyl("CaddyFunnel", 0.45, 1.6, dp * CF(0, 4.35, 0), lk(C(30, 30, 32), M.Plastic))
				D.disc("CaddyOil", 1.4, 0.02, dp * CF(0, 4.55, 0), lk(C(60, 40, 20), M.SmoothPlastic, { r = 0.3 }))
				D.label("CaddyLabel", 0.9, 0.35, dp * CF(0, 1.1, 0.76), "폐유 80L", INK, nil, { d = 0.01 })
			end)
		end
		-- 플로어 잭 + 잭 스탠드 2
		local jcx = (b1.x0 + b1.x1) / 2
		local jp0 = firstSpot(G, { pf(jcx + 2.6, y0, b1.z0 - 3.4, 15), pf(jcx + 2.6, y0, b1.z0 - 5.0, 15), pf(jcx + 4.4, y0, b1.z0 - 6.0, 20), pf(jcx - 5.0, y0, b1.z0 - 7.0, 10) }, V3(1.3, 1.0, 3.2), 0.1, "floorJack")
		local jp = jp0 or CF()
		if jp0 then
			propGroup(G, "floorJack", V3(jp.X - 1.6, 0, jp.Z - 2.2), V3(jp.X + 1.6, 3.4, jp.Z + 1.8), function()
				D.box("JackFrame", V3(1.0, 0.5, 2.6), jp * CF(0, 0.4, 0), lk(C(200, 30, 30), M.Metal))
				D.cyl("JackSaddle", 0.12, 0.6, jp * CF(0, 0.75, 1.2) * ANG(0, 0, PI / 2), L.darkAlu)
				for _, sz in { -1, 1 } do
					for _, sx in { -1, 1 } do
						D.cyl("JackWheel", 0.15, 0.32, jp * CF(sx * 0.55, 0.16, sz * 1.1), L.black)
					end
				end
				D.seg("JackHandle", (jp * CF(0, 0.55, -1.25)).Position, (jp * CF(0, 3.0, -2.0)).Position, 0.1, lk(C(200, 30, 30), M.Metal))
				D.box("JackGrip", V3(0.5, 0.12, 0.12), jp * CF(0, 3.0, -2.0), L.rubber)
				for k = 0, 1 do
					local sp = jp * CF(2.0 + k * 0.1, 0, 0.6 - k * 1.3)
					for i = 0, 2 do
						local a = i * 2 * PI / 3
						D.seg("StandLeg", (sp * CF(0, 1.0, 0)).Position, (sp * CF(math.cos(a) * 0.45, 0.02, math.sin(a) * 0.45)).Position, 0.08, lk(C(200, 30, 30), M.Metal))
					end
					D.vcyl("StandPost", 1.3, 0.16, sp * CF(0, 1.4, 0), L.steel)
					D.box("StandSaddle", V3(0.4, 0.12, 0.25), sp * CF(0, 2.08, 0), L.darkAlu)
				end
			end)
		end
		-- 크리퍼 (바닥에 눕혀 둠)
		local cr = pf(b1.x0 + 1.6, y0, b1.z0 - 4.6, 75)
		if spot(G, cr, V3(1.4, 0.6, 3.8), 0, "creeper") then
			propGroup(G, "creeper", V3(cr.X - 2, 0, cr.Z - 2), V3(cr.X + 2, 0.6, cr.Z + 2), function()
				D.slab("CreeperBoard", 1.3, 3.6, 0.12, 0.25, cr * CF(0, 0.4, 0), lk(C(30, 30, 32), M.Plastic))
				D.slab("CreeperPad", 1.1, 3.0, 0.1, 0.2, cr * CF(0, 0.51, -0.2), lk(C(200, 40, 30), M.Fabric))
				D.box("CreeperHead", V3(0.9, 0.18, 0.6), cr * CF(0, 0.6, 1.4), lk(C(200, 40, 30), M.Fabric))
				for _, sx in { -1, 1 } do
					for _, sz in { -1, 0, 1 } do
						D.ball("CreeperCaster", 0.3, cr * CF(sx * 0.5, 0.15, sz * 1.4), L.black)
					end
				end
			end)
		end
		-- 공구 카트 (리프트 2 뒤, 임팩트 렌치)
		local b2 = bays[2] or bays[1]
		local tcp = pf((b2.x0 + b2.x1) / 2 + 2.2, y0, (if zone then zone.min.Z else b2.z0) - 2.4, -10)
		if spot(G, tcp, V3(2.2, 3.4, 1.4), 0, "toolCart") then
			propGroup(G, "toolCart", V3(tcp.X - 1.2, 0, tcp.Z - 0.8), V3(tcp.X + 1.2, 3.4, tcp.Z + 0.8), function()
				for _, sx in { -1, 1 } do
					for _, sz in { -1, 1 } do
						caster(D, tcp * CF(sx * 0.9, 0, sz * 0.5), 0.35)
					end
				end
				for i, yy in { 0.6, 1.5, 2.4 } do
					D.box("UtilityTray", V3(2.0, 0.35, 1.2), tcp * CF(0, yy, 0), L.toolRed)
					D.box("UtilityTrayIn", V3(1.86, 0.06, 1.06), tcp * CF(0, yy + 0.12, 0), lk(C(30, 30, 32), M.Rubber))
					local _ = i
				end
				for _, sx in { -1, 1 } do
					D.box("UtilityPost", V3(0.08, 2.4, 0.08), tcp * CF(sx * 0.95, 1.5, 0.55), L.darkAlu)
					D.box("UtilityPost", V3(0.08, 2.4, 0.08), tcp * CF(sx * 0.95, 1.5, -0.55), L.darkAlu)
				end
				D.bar("UtilityHandle", (tcp * CF(-1.2, 2.7, -0.5)).Position, (tcp * CF(-1.2, 2.7, 0.5)).Position, 0.08, 0.08, L.chrome)
				-- 임팩트 렌치 · 소켓 · 걸레 · 스프레이
				local ip = tcp * CF(0.3, 2.62, 0)
				D.cyl("ImpactBody", 0.8, 0.4, ip * CF(0, 0.2, 0) * ANG(0, PI / 2, 0), lk(C(30, 30, 32), M.Plastic))
				D.box("ImpactGrip", V3(0.25, 0.6, 0.3), ip * CF(0, 0.05, 0.3) * ANG(math.rad(-20), 0, 0), lk(C(220, 60, 30), M.Rubber))
				D.vcyl("ImpactSocket", 0.25, 0.2, ip * CF(0, 0.2, -0.5) * ANG(PI / 2, 0, 0), L.steel)
				D.seg("ImpactHose", (ip * CF(0, -0.2, 0.4)).Position, (tcp * CF(-0.6, 0.2, 0.7)).Position, 0.08, lk(C(240, 190, 30), M.Rubber))
				for k = 0, 4 do
					D.vcyl("CartSocket", 0.3, 0.16 + k * 0.03, tcp * CF(-0.7 + k * 0.25, 1.77, 0.3), L.steel)
				end
				D.ell("ShopRag", V3(0.8, 0.12, 0.6), tcp * CF(-0.5, 2.62, -0.2), lk(C(220, 220, 210), M.Fabric))
				D.vcyl("SprayCan", 0.7, 0.24, tcp * CF(0.7, 1.0, 0.2), lk(C(30, 80, 170), M.Metal))
			end)
		end
	end)

	-- 5.8 리프트 디테일 (정적 파트에만: 기둥 · 모터 · 상단 바), 셔터 레일 · 스위치 ----------------------------------------
	step(K, "lifts", function()
		for _, r in G.byName.LiftPost or {} do
			local fz = r.max.Z + 0.01
			D.box("PostHazard", V3(r.size.X + 0.02, 1.1, 0.03), CF(r.c.X, 0.9, fz), L.yellow)
			for k = -1, 1 do
				D.box("PostHazardStripe", V3(0.22, 1.25, 0.035), CF(r.c.X + k * 0.42, 0.9, fz + 0.005) * ANG(0, 0, math.rad(35)), L.black)
			end
			D.label("PostCap", 1.1, 0.5, CFrame.fromMatrix(V3(r.c.X, 6.2, fz + 0.02), XA, YA, ZA), "3.5 TON", WHITE, C(30, 30, 34), { d = 0.01, font = Enum.Font.GothamBlack })
			D.box("PostLockLadder", V3(0.22, 9.5, 0.04), CF(r.c.X, 6.0, r.min.Z - 0.02), lk(C(60, 60, 64), M.Metal))
		end
		for _, r in G.byName.LiftMotor or {} do
			local fz = r.max.Z + 0.01
			D.box("LiftControl", V3(0.9, 1.0, 0.25), CF(r.c.X, r.min.Y - 0.6, fz + 0.1), lk(C(230, 230, 226), M.Metal))
			D.cyl("LiftUp", 0.06, 0.2, CF(r.c.X - 0.2, r.min.Y - 0.45, fz + 0.24) * ANG(0, PI / 2, 0), lk(C(40, 170, 80)))
			D.cyl("LiftDown", 0.06, 0.2, CF(r.c.X + 0.2, r.min.Y - 0.45, fz + 0.24) * ANG(0, PI / 2, 0), lk(C(240, 190, 30)))
			D.cyl("LiftStop", 0.12, 0.3, CF(r.c.X, r.min.Y - 0.85, fz + 0.27) * ANG(0, PI / 2, 0), lk(C(220, 30, 30)))
			D.seg("LiftHydHose", V3(r.c.X, r.max.Y, r.c.Z), V3(r.c.X - 0.6, 13.2, r.c.Z), 0.1, L.black)
		end
		for _, r in G.byName.LiftTopBar or {} do
			D.label("LiftTopBarLabel", 5.0, 0.5, CFrame.fromMatrix(V3(r.c.X, r.c.Y, r.max.Z + 0.01), XA, YA, ZA), "2주식 리프트 · 3.5 TON", WHITE, nil, { d = 0.01, font = Enum.Font.GothamBold })
		end
		-- 셔터 가이드 레일 + 개폐 스위치
		for _, r in G.byName.BayColumn or {} do
			for _, sx in { -1, 1 } do
				local x = if sx < 0 then r.min.X - 0.12 else r.max.X + 0.12
				if x > RB.x0 and x < RB.x1 then
					D.box("ShutterGuide", V3(0.24, 11.2, 0.5), CF(x, 5.6, r.c.Z - 0.1), lk(C(150, 154, 158), M.Metal))
				end
			end
			if math.abs(r.c.X) < 3 then
				local sc = CFrame.fromMatrix(V3(r.c.X, 4.6, r.min.Z - 0.02), -XA, YA, -ZA)
				D.plate("ShutterSwitch", 0.6, 1.0, 0.2, sc, lk(C(230, 230, 226)))
				for k, col in { C(40, 170, 80), C(220, 30, 30), C(240, 190, 30) } do
					D.cyl("ShutterButton", 0.06, 0.18, sc * CF(0, 0.3 - (k - 1) * 0.3, 0.23) * ANG(0, PI / 2, 0), lk(col))
				end
				D.label("ShutterLabel", 0.6, 0.18, sc * CF(0, 0.6, 0.21), "셔터", INK, C(250, 250, 246), { d = 0.005 })
			end
		end
	end)

	-- 5.9 천장: 하이베이 LED · 배튼 조명 (맵 판 대신) · 퍼린 · 스프링클러 배관 · 에어 호스 릴 · 오일 릴 · 리프트 번호판 -----------------
	step(K, "ceiling", function()
		local lit = 0
		local hbx = { (bays[1].x0 + bays[1].x1) / 2, (laneX0 + laneX1) / 2 - 1.6, ((bays[2] or bays[1]).x0 + (bays[2] or bays[1]).x1) / 2 }
		for ti, tz in trussZ do
			for xi, x in hbx do
				local top = V3(x, trussY, tz)
				D.seg("HighBayChain", top, top - V3(0, 0.8, 0), 0.05, lk(C(150, 150, 154), M.Metal))
				D.box("HighBayDriver", V3(0.5, 0.25, 0.5), CF(top - V3(0, 0.95, 0)), lk(C(60, 62, 66), M.Metal))
				D.disc("HighBaySink", 1.5, 0.35, CF(top - V3(0, 1.25, 0)), lk(C(50, 52, 56), M.Metal))
				local lens = D.disc("HighBayLens", 1.32, 0.04, CF(top - V3(0, 1.44, 0)), Look.lampCool)
				local want = (xi ~= 2 and ti ~= 2) or (xi == 2 and ti == 1) or (ti == 2 and xi ~= 2)
				if want and lit < 5 then
					D.light(lens, "PointLight", { Range = 26, Brightness = 0.9, Color = Look.coolLight })
					lit += 1
				end
			end
		end
		for _, r in hideNamed(G, "LightPanel") do
			local a, b = V3(r.min.X, r.max.Y + 0.02, r.c.Z), V3(r.max.X, r.max.Y + 0.02, r.c.Z)
			linearLED(D, a + V3(0, 0.15, 0), b + V3(0, 0.15, 0), 1.0, { drop = 0.16, glow = Look.lampCool })
			for _, p in { a, b } do
				local q = p + (if p == a then V3(0.4, 0, 0) else V3(-0.4, 0, 0))
				D.seg("BattenWire", q + V3(0, 0.15, 0), V3(q.X, yR, q.Z), 0.03, lk(C(160, 160, 164), M.Metal))
			end
		end
		-- 퍼린 · 지붕 단열재 면
		D.box("RoofLiner", V3(RB.x1 - RB.x0 - 0.1, 0.03, RB.z1 - RB.z0 + 0.8), CF((RB.x0 + RB.x1) / 2, yR - 0.02, (RB.z0 + RB.z1) / 2 + 0.4), lk(C(232, 232, 228), M.Fabric))
		for i = -2, 2 do
			D.box("Purlin", V3(0.25, 0.5, RB.z1 - RB.z0 + 0.8), CF(i * 9.2, yR - 0.29, (RB.z0 + RB.z1) / 2 + 0.4), lk(C(70, 78, 90), M.Metal))
		end
		-- 스프링클러 배관 2 줄 + 헤드
		for _, sz in { -7.0, 7.0 } do
			D.seg("SprinklerMain", V3(RB.x0 + 0.5, yR - 0.75, sz), V3(RB.x1 - 0.5, yR - 0.75, sz), 0.2, lk(C(196, 30, 30), M.Metal))
			for x = RB.x0 + 3.0, RB.x1 - 2.0, 6.0 do
				D.seg("SprinklerDrop", V3(x, yR - 0.75, sz), V3(x, yR - 1.15, sz), 0.08, lk(C(196, 30, 30), M.Metal))
				D.disc("SprinklerHead", 0.22, 0.05, CF(x, yR - 1.2, sz), Look.brass)
			end
		end
		-- 에어 호스 릴 (트러스, 가운데 통로 위)
		local ax = G.airX or (laneX0 + laneX1) / 2 + 1.8
		for i, tz in trussZ do
			if i >= 2 then
				local rc = CF(ax, trussY - 0.75, tz)
				D.box("ReelBracket", V3(0.2, 0.4, 0.9), rc * CF(0, 0.5, 0), L.darkAlu)
				D.cyl("HoseReelBody", 0.6, 1.4, rc, lk(C(240, 190, 30), M.Plastic))
				D.cyl("HoseReelHub", 0.65, 0.5, rc, lk(C(40, 42, 46), M.Metal))
				D.seg("HoseDrop", (rc * CF(0, -0.6, 0.2)).Position, V3(ax + 0.1, 9.0, tz + 0.4), 0.08, lk(C(240, 190, 30), M.Rubber))
				D.box("HoseBallStop", V3(0.25, 0.25, 0.25), CF(ax + 0.1, 9.0, tz + 0.4), L.black)
				D.seg("AirGun", V3(ax + 0.1, 8.9, tz + 0.4), V3(ax + 0.1, 8.3, tz + 0.55), 0.12, lk(C(200, 40, 36), M.Plastic))
			end
		end
		-- 오일 디스펜서 릴 4 (뒤 트러스)
		local rz = trussZ[1]
		local reels = { { "엔진오일", C(30, 30, 32) }, { "ATF", C(196, 30, 30) }, { "기어오일", C(40, 90, 180) }, { "에어", C(240, 190, 30) } }
		local rx0 = ((bays[2] or bays[1]).x0 + (bays[2] or bays[1]).x1) / 2 - 3.6
		D.box("ReelRail", V3(6.4, 0.2, 0.5), CF(rx0 + 2.1, trussY - 0.1, rz), L.darkAlu)
		for i, r in reels do
			local x = rx0 + (i - 1) * 1.4
			local rc = CF(x, trussY - 0.75, rz)
			D.cyl("OilReel", 0.5, 1.1, rc, lk(r[2], M.Metal))
			D.seg("OilHose", (rc * CF(0, -0.5, 0.15)).Position, V3(x, 10.2, rz + 0.3), 0.07, L.black)
			D.box("OilNozzle", V3(0.18, 0.5, 0.3), CF(x, 9.95, rz + 0.3), lk(r[2], M.Metal))
			if mid then
				D.label("OilReelTag", 1.2, 0.3, CFrame.fromMatrix(V3(x, trussY - 1.45, rz + 0.3), XA, YA, ZA), r[1], WHITE, r[2], { d = 0.01 })
			end
		end
		-- 리프트 번호판 (앞 트러스에 매달림)
		local fz = trussZ[#trussZ]
		for i, b in bays do
			local x = (b.x0 + b.x1) / 2
			for _, sx in { -1, 1 } do
				D.seg("BaySignWire", V3(x + sx * 1.2, trussY, fz), V3(x + sx * 1.2, 13.4, fz), 0.03, lk(C(160, 160, 164), M.Metal))
			end
			D.label("BaySign", 3.2, 1.0, CFrame.fromMatrix(V3(x, 12.9, fz + 0.05), XA, YA, ZA), (if i == 1 then "1" else "2") .. "번 리프트", WHITE, NAVY, { d = 0.08, font = Enum.Font.GothamBlack })
		end
	end)
	return G
end
buildBay = buildBayImpl

---------------------------------------------------------------------------------------------------
-- 6. 자동세차장 (문형 자동세차 1 베이): 결제 키오스크 · 신호등 · 드라이어 아치 · 프리워시 · 드라잉존 · 진공청소기 · 매트 세척기
---------------------------------------------------------------------------------------------------
local function buildWashImpl(K: any, V: any): any
	local G = newCtx(K, V, "carwash")
	local D = draw(G)
	local RB = G.RB
	local hi = K.detail == "high"
	local mid = K.detail ~= "low"
	local y0, yR = RB.y0, RB.y1
	note(K, string.format("wash frame=%s bounds x %.2f..%.2f z %.2f..%.2f roof %.2f", G.frameFrom, RB.x0, RB.x1, RB.z0, RB.z1, yR))

	-- 6.1 계약 구역: 갠트리 이동 구간 · 세차 존 · 진입/출차로 · 결제 앵커 ------------------------------------------------
	local gantry: Model? = nil
	for _, d in V.model:GetDescendants() do
		if d:IsA("Model") and hasTag(d, "GarageWashGantry") then
			gantry = d :: Model
		end
	end
	local gmn, gmx = V3(-11.0, 0, -20.4), V3(11.0, 12.44, -17.6)
	local travelB = V3(0, 0, 35.0)
	local gparts: { [string]: BasePart } = {}
	if gantry then
		gmn, gmx = V3(math.huge, math.huge, math.huge), V3(-math.huge, -math.huge, -math.huge)
		for _, q in gantry:GetDescendants() do
			if q:IsA("BasePart") then
				local a, b = laabb(G.Binv * V.cf:ToObjectSpace(q.CFrame), q.Size)
				gmn, gmx = gmn:Min(a), gmx:Max(b)
				gparts[q.Name] = gparts[q.Name] or q
			end
		end
		local off = gantry:GetAttribute("TravelOffset")
		if typeof(off) == "Vector3" then
			travelB = G.Binv.Rotation * V.cf:VectorToObjectSpace(off)
		end
	end
	note(K, string.format("gantry %s travel %.2f,%.2f,%.2f box z %.2f..%.2f", tostring(gantry and gantry.Name), travelB.X, travelB.Y, travelB.Z, gmn.Z, gmx.Z))
	local env0 = gmn:Min(gmn + travelB) - V3(0.3, 0, 0.3)
	local env1 = gmx:Max(gmx + travelB) + V3(0.3, 0.5, 0.3)
	keep(G, V3(env0.X, 0.1, env0.Z), V3(env1.X, env1.Y, env1.Z), "gantry")
	local zone = G.byName.GarageZone_wash and G.byName.GarageZone_wash[1]
	local zx0, zx1 = -6.5, 6.5
	if zone then
		zx0, zx1 = zone.min.X, zone.max.X
		keep(G, zone.min - V3(0.2, 0.3, 0.2), zone.max + V3(0.2, 0.3, 0.2), "zone")
	end
	keep(G, V3(zx0 - 0.2, 0.1, (zone and zone.max.Z or 19) - 1), V3(zx1 + 0.2, 8.6, RB.z1 + 3), "entryPath")
	keep(G, V3(zx0 - 0.2, 0.1, RB.z0 - 6), V3(zx1 + 0.2, 8.0, env0.Z + 0.5), "exitPath")
	for _, r in G.byName.GarageDesk_wash or {} do
		keep(G, r.min - V3(0.25, 0, 0.2), r.max + V3(0.25, 2, 0.2), "payDesk")
	end
	addServerPrompts(G)
	local leftX = env0.X -- 왼쪽 옆 통로 안쪽 끝 (갠트리 바깥)
	local rightX = env1.X

	-- 6.2 바닥: 젖은 물웅덩이 · 배수로 · 차선 글자 · 진입 가이드 레일 · 보행 주의선 ------------------------------------------------
	step(K, "floor", function()
		local wet = { c = C(150, 170, 182), m = M.Glass, t = 0.6, r = 0.35 }
		local rng = mkRng(11)
		for _, p in { { -2.5, -16.5, 3.5 }, { 3.0, -18.8, 2.6 }, { -4.0, -6.0, 2.0 }, { 2.2, 6.5, 2.8 }, { -1.5, 14.0, 1.8 }, { 5.0, -22.0, 2.2 } } do
			D.cyl("WetPuddle", 0.006, p[3] * (0.8 + rng() * 0.4), CF(p[1], y0 + 0.004, p[2]) * ANG(0, rng() * PI, PI / 2), wet)
		end
		D.box("WetSheen", V3(zx1 - zx0 + 6, 0.004, env1.Z - env0.Z), CF((zx0 + zx1) / 2, y0 + 0.002, (env0.Z + env1.Z) / 2), { c = C(170, 186, 196), m = M.Glass, t = 0.82, r = 0.25 })
		for _, tz in { RB.z1 - 4.6, env0.Z - 0.6 } do
			D.box("TrenchFrame", V3(RB.x1 - RB.x0 - 1.0, 0.012, 0.9), CF((RB.x0 + RB.x1) / 2, y0 + 0.006, tz), lk(C(70, 72, 76), M.Metal))
			D.box("TrenchGrate", V3(RB.x1 - RB.x0 - 1.2, 0.014, 0.66), CF((RB.x0 + RB.x1) / 2, y0 + 0.01, tz), lk(C(60, 62, 66), M.DiamondPlate))
			if mid then
				for i = 1, 22 do
					local x = RB.x0 + 0.6 + (RB.x1 - RB.x0 - 1.2) * i / 23
					D.box("TrenchSlot", V3(0.06, 0.016, 0.5), CF(x, y0 + 0.013, tz), lk(C(20, 22, 24)))
				end
			end
		end
		-- 차선 글자 (운전자가 -Z 쪽으로 진입하며 읽음)
		local sl = G.byName.WashStopLine and G.byName.WashStopLine[1]
		local slz = sl and sl.c.Z or -10.68
		D.label("StopText", 6.0, 1.2, floorCF(V3(0, y0 + 0.06, slz + 1.4), -ZA), "정지선  STOP", WHITE, nil, { d = 0.004, font = Enum.Font.GothamBlack })
		for _, az in { 13.0, 5.0 } do
			D.label("LaneArrow", 2.0, 2.6, floorCF(V3(0, y0 + 0.02, az), -ZA), "▲", C(236, 236, 230), nil, { d = 0.004, font = Enum.Font.GothamBlack })
		end
		D.label("LaneEntryText", 7.0, 1.0, floorCF(V3(0, y0 + 0.02, RB.z1 - 2.4), -ZA), "세차 진입 · 서행 5km/h", C(240, 210, 60), nil, { d = 0.004, font = Enum.Font.GothamBlack })
		-- 옆 통로 경계 (노랑) + 보행 주의
		for _, x in { leftX - 0.12, rightX + 0.12 } do
			D.box("WalkEdgeLine", V3(0.18, 0.006, RB.z1 - RB.z0 - 1.0), CF(x, y0 + 0.005, (RB.z0 + RB.z1) / 2), L.yellow)
		end
		D.label("WalkText", 1.6, 4.0, floorCF(V3((RB.x0 + leftX) / 2, y0 + 0.012, 6.0), -ZA), "보행\n주의", C(240, 200, 40), nil, { d = 0.004, font = Enum.Font.GothamBlack })
		-- 진입 바퀴 가이드 레일 (왼쪽 바퀴, 낮은 철제 채널)
		local gz0, gz1 = (zone and zone.max.Z or 19.0) + 0.4, RB.z1 - 0.4
		for _, gx in { -3.45, -1.95 } do
			D.box("WheelGuide", V3(0.14, 0.14, gz1 - gz0), CF(gx, y0 + 0.07, (gz0 + gz1) / 2), lk(C(240, 196, 30), M.Metal))
		end
		for _, s in { -1, 1 } do
			local gx = if s < 0 then -3.45 else -1.95
			D.bar("WheelGuideFlare", V3(gx, y0 + 0.07, gz1), V3(gx + s * 0.7, y0 + 0.07, gz1 + 0.35), 0.14, 0.14, lk(C(240, 196, 30), M.Metal))
		end
	end)

	-- 6.3 벽: 흰 타일 + 스테인리스 캡, 유리 멀리언, 안내 표지 -------------------------------------------------------------
	step(K, "walls", function()
		local wallTop = 3.84
		for _, r in G.byName.WashWall or {} do
			wallTop = math.max(wallTop, r.max.Y)
		end
		for _, w in { "left", "right" } do
			local s0, s1 = RB.z0 + 0.6, RB.z1 - 1.0
			local len = s1 - s0
			local m = (s0 + s1) / 2
			D.plate("WashTile", len, wallTop - 0.05, 0.02, D.wall(w, m, (wallTop - 0.05) / 2, 0.004), L.tile)
			for _, yy in { 1.0, 2.0, 3.0 } do
				D.plate("WashGrout", len, 0.04, 0.025, D.wall(w, m, yy, 0.004), L.grout)
			end
			local n = math.floor(len / 2)
			for i = 1, n - 1 do
				D.plate("WashGrout", 0.04, wallTop - 0.05, 0.025, D.wall(w, s0 + len * i / n, (wallTop - 0.05) / 2, 0.004), L.grout)
			end
			D.plate("WashTileBand", len, 0.3, 0.03, D.wall(w, m, 0.55, 0.004), lk(C(40, 110, 190), M.CeramicTiles))
			D.plate("WashWallCap", len, 0.1, 0.18, D.wall(w, m, wallTop + 0.03, -0.02), L.steel)
			-- 유리 멀리언
			local gm = 8
			for i = 0, gm do
				D.plate("WashMullion", 0.16, 8.5, 0.2, D.wall(w, s0 + len * i / gm, wallTop + 4.3, -0.08), L.alu)
			end
			D.plate("WashGlassRail", len, 0.2, 0.22, D.wall(w, m, 12.35, -0.08), L.alu)
		end
		-- 운전자 쪽 (왼쪽) 안내 표지
		local guides = {
			{ 15.6, "① 천천히 진입", "녹색선 안쪽으로 서행" },
			{ 9.4, "② 사이드미러 접기", "안테나 · 루프박스 확인" },
			{ 3.2, "③ 정지선에서 정지", "기어 P · 사이드브레이크" },
			{ -3.0, "④ 세차 중 이동 금지", "창문 · 선루프 닫기" },
		}
		for _, g in guides do
			local dc = D.wall("left", g[1], 5.1, 0.03)
			D.plate("GuideSign", 3.6, 1.5, 0.04, dc, lk(C(250, 250, 248)))
			D.plate("GuideSignBand", 0.3, 1.5, 0.05, dc * CF(-1.65, 0, 0), lk(C(40, 120, 210)))
			D.label("GuideSignTitle", 3.1, 0.62, dc * CF(0.12, 0.33, 0.05), g[2], C(20, 60, 140), nil, { d = 0.005, font = Enum.Font.GothamBlack })
			D.label("GuideSignSub", 3.1, 0.42, dc * CF(0.12, -0.35, 0.05), g[3], INK, nil, { d = 0.005 })
		end
		D.label("ExitSign", 3.4, 1.0, CFrame.fromMatrix(V3(0, 12.2, RB.z0 + 0.6), XA, YA, ZA), "출구  EXIT  ➜", WHITE, C(20, 150, 80), { d = 0.06, font = Enum.Font.GothamBlack })
		-- 오른쪽 유리면: 세차 코스 라이트박스 2
		local promos = {
			{ 5.5, "폼 세차 7,000원\n풍성한 거품 · 부드러운 브러시", C(30, 110, 200) },
			{ -2.5, "프리미엄 왁스 10,000원\n발수 코팅 · 광택 UP", C(20, 140, 120) },
		}
		for _, pr in promos do
			local dc = D.wall("right", pr[1], 6.0, -0.05)
			D.plate("CourseBox", 4.6, 2.6, 0.25, dc, L.darkAlu)
			local face = D.label("CourseBoxFace", 4.4, 2.4, dc * CF(0, 0, 0.25), pr[2], WHITE, pr[3], { d = 0.02, glow = 1.15, font = Enum.Font.GothamBlack })
			local _ = face
			for k = 0, 2 do
				D.ball("CourseBubble", 0.4 + k * 0.15, dc * CF(1.6 - k * 0.45, 0.75 - k * 0.2, 0.32), { c = C(230, 245, 255), m = M.Glass, t = 0.35 })
			end
		end
	end)

	-- 6.4 결제 키오스크 (서버 '세차하기' 앵커 바로 앞 · 장식) + 요금표 -----------------------------------------------------
	step(K, "kiosk", function()
		local desk = G.byName.GarageDesk_wash and G.byName.GarageDesk_wash[1]
		local kz1 = if desk then desk.min.Z - 0.3 else 20.1
		local kz0 = math.max(env1.Z + 0.1, kz1 - 2.2)
		local ix0, ix1 = RB.x0, math.min(leftX - 0.1, RB.x0 + 2.1)
		local ip = pf((ix0 + ix1) / 2, y0, (kz0 + kz1) / 2, 0)
		if spot(G, ip, V3(ix1 - ix0, 5.6, kz1 - kz0), 0, "kiosk") then
			propGroup(G, "kiosk", V3(ix0, 0, kz0), V3(ix1, 5.6, kz1), function()
				-- 연석 아일랜드 (노랑/검정 모서리)
				D.box("KioskIsland", V3(ix1 - ix0, 0.42, kz1 - kz0), ip * CF(0, 0.21, 0), lk(C(170, 168, 162), M.Concrete))
				for k = 0, 3 do
					D.box("IslandStripe", V3(0.02, 0.42, (kz1 - kz0) / 4 - 0.02), CF(ix1 + 0.005, y0 + 0.21, kz0 + (kz1 - kz0) * (k + 0.5) / 4), if k % 2 == 0 then L.yellow else L.black)
				end
				local kp = CF((ix0 + ix1) / 2 + 0.1, y0 + 0.42, (kz0 + kz1) / 2) * ANG(0, math.rad(72), 0)
				D.box("KioskPlinth", V3(1.3, 0.3, 1.0), kp * CF(0, 0.15, 0), L.steel)
				D.rbox("KioskBody", V3(1.2, 4.0, 0.9), 0.12, kp * CF(0, 2.3, 0), lk(C(30, 90, 170)))
				D.box("KioskFace", V3(1.0, 3.6, 0.04), kp * CF(0, 2.35, 0.46), lk(C(244, 246, 248)))
				D.box("KioskHood", V3(1.4, 0.35, 1.2), kp * CF(0, 4.45, 0.1), lk(C(30, 90, 170)))
				D.label("KioskHoodText", 1.3, 0.3, kp * CF(0, 4.45, 0.71), "결제 PAY", WHITE, nil, { d = 0.01, font = Enum.Font.GothamBlack })
				local scrCF = kp * CF(0, 3.55, 0.49) * ANG(math.rad(-8), 0, 0)
				D.box("KioskBezel", V3(0.92, 0.72, 0.05), scrCF, L.black)
				local sp, lab = D.label("KioskScreen", 0.84, 0.64, scrCF * CF(0, 0, 0.03), "", WHITE, C(20, 70, 150), { d = 0.005, glow = 1.3 })
				local frames = {
					{ "광안 오토 자동세차\n코스를 선택하세요", C(20, 70, 150) },
					{ "기본 5,000원\n폼 7,000원 · 왁스 10,000원", C(20, 90, 120) },
					{ "카드를 넣어주세요\nIC · 삼성페이 · 현금", C(30, 40, 60) },
					{ "결제 완료\n녹색 신호에 진입하세요", C(20, 110, 60) },
				}
				lab.Text = frames[1][1]
				screenCycle(K, lab, nil, frames, 3.5)
				D.light(sp, "SurfaceLight", { Face = Enum.NormalId.Front, Range = 6, Brightness = 0.6, Angle = 100, Color = C(140, 190, 255) })
				-- 코스 버튼 · 카드 슬롯 · 현금 · 영수증 · 키패드 · 인터폰 · 카메라
				for i, col in { C(40, 160, 80), C(240, 180, 30), C(220, 60, 50) } do
					D.cyl("CourseButton", 0.06, 0.24, kp * CF(-0.3 + (i - 1) * 0.3, 3.0, 0.49) * ANG(0, PI / 2, 0), lk(col, M.Neon))
				end
				D.box("CardSlot", V3(0.4, 0.06, 0.05), kp * CF(-0.2, 2.65, 0.49), L.black)
				D.box("CashSlot", V3(0.5, 0.08, 0.05), kp * CF(0.15, 2.35, 0.49), L.black)
				D.box("ReceiptSlot", V3(0.35, 0.05, 0.05), kp * CF(0.25, 2.05, 0.49), L.black)
				for r = 0, 2 do
					for c = 0, 2 do
						D.box("KioskKey", V3(0.1, 0.08, 0.04), kp * CF(-0.32 + c * 0.13, 2.4 - r * 0.12, 0.49), lk(C(200, 204, 210), M.Metal))
					end
				end
				D.cyl("IntercomGrille", 0.04, 0.3, kp * CF(0, 1.6, 0.49) * ANG(0, PI / 2, 0), lk(C(120, 124, 128), M.Metal))
				D.label("IntercomText", 0.6, 0.16, kp * CF(0, 1.3, 0.49), "호출 · 문의", INK, nil, { d = 0.005 })
				D.ball("KioskCamera", 0.16, kp * CF(0, 4.15, 0.48), lk(C(20, 20, 22), M.Glass))
				D.box("CoinTray", V3(0.45, 0.12, 0.2), kp * CF(0, 1.0, 0.52), L.steel)
			end)
		end
		-- 요금표 (왼쪽 유리면, 진입 차량이 보는 높이)
		local pz = ((desk and desk.c.Z or 21.4) + kz0) / 2 + 0.4
		local items = {
			{ "기본 세차", "5,000" }, { "폼 세차 (거품)", "7,000" }, { "프리미엄 왁스", "10,000" }, { "하부 세차 추가", "+2,000" },
			{ "셀프 진공청소기 4분", "1,000" }, { "매트 세척", "1,000" },
		}
		priceBoard(D, D.wall("left", pz, 7.35, -0.05), 4.6, 3.6, "자동세차 요금 (원)", items, { accent = C(30, 90, 170) })
	end)

	-- 6.5 진입 신호등 (전진 / 정지 / 후진) : 갠트리 움직임 · 존 안의 차를 읽어 스스로 바뀜 ---------------------------------------
	step(K, "signal", function()
		local sl = G.byName.WashStopLine and G.byName.WashStopLine[1]
		local sz = (sl and sl.c.Z or -10.68) - 2.4
		local sx = (RB.x0 + leftX) / 2
		local sp = pf(sx, y0, sz, 0)
		if not spot(G, sp, V3(1.2, 7.8, 1.2), 0, "signal") then
			return
		end
		D.box("SignalBase", V3(0.7, 0.12, 0.7), sp * CF(0, 0.06, 0), L.darkAlu)
		D.vcyl("SignalPole", 7.4, 0.24, sp * CF(0, 3.8, 0), lk(C(70, 74, 80), M.Metal))
		local yaw = math.deg(math.atan2(-2.7 - sx, 0 - sz))
		local hp = CF(sx, y0 + 5.8, sz) * ANG(0, math.rad(yaw), 0) * CF(0, 0, 0.18)
		D.box("SignalHead", V3(1.2, 3.3, 0.5), hp, lk(C(26, 28, 32), M.Metal))
		D.box("SignalBackplate", V3(1.5, 3.6, 0.06), hp * CF(0, 0, -0.27), L.black)
		local defs = { { "정지", C(255, 50, 40), 1.05 }, { "전진", C(40, 230, 110), 0.0 }, { "후진", C(255, 170, 30), -1.05 } }
		local lamps = {}
		for _, d in defs do
			local lc = hp * CF(0, d[3], 0.26)
			D.cyl("SignalVisor", 0.35, 0.95, lc * CF(0, 0.05, 0.18) * ANG(0, PI / 2, 0), L.black)
			local lamp = D.cyl("SignalLamp", 0.06, 0.8, lc * ANG(0, PI / 2, 0), lk(darker(d[2], 0.7)))
			D.label("SignalLampText", 0.7, 0.3, lc * CF(0, 0, 0.05), d[1], WHITE, nil, { d = 0.005 })
			table.insert(lamps, { p = lamp, on = d[2], off = darker(d[2], 0.72) })
		end
		local bp = hp * CF(0, -2.15, 0.05)
		D.box("SignalBoard", V3(1.6, 0.8, 0.3), bp, L.black)
		local _, msg = D.label("SignalBoardText", 1.5, 0.66, bp * CF(0, 0, 0.16), "진입하세요", C(80, 255, 140), C(8, 10, 12), { d = 0.005, glow = 1.5 })
		local glow = D.light(lamps[2].p, "PointLight", { Range = 9, Brightness = 0.8, Color = lamps[2].on })
		local function set(idx: number, text: string, col: Color3)
			for i, l in lamps do
				if l.p.Parent then
					l.p.Color = if i == idx then l.on else l.off
					l.p.Material = if i == idx then M.Neon else M.SmoothPlastic
				end
			end
			msg.Text = text
			msg.TextColor3 = col
			if glow then
				glow.Color = lamps[idx].on
			end
		end
		set(2, "↑ 전진 · 천천히 진입", C(80, 255, 140))
		-- 상태: 갠트리가 홈에서 움직이면 세차 중 (정지, 깜빡임) → 돌아오면 6 초간 세차 완료 (전진 출차) → 평소엔 존 안 차 유무
		local beam = gparts.GantryBeam
		local home = beam and beam.Position
		local lastMove, lastScan, carIn = -100, -100, false
		local params: OverlapParams? = nil
		pcall(function()
			local p = OverlapParams.new()
			p.FilterType = Enum.RaycastFilterType.Exclude
			p.FilterDescendantsInstances = { V.model, K.root }
			params = p
		end)
		local zp: BasePart? = zone and zone.part or nil
		Interact.anim(K, function(t: number)
			local moving = false
			if beam and home and beam.Parent then
				moving = (beam.Position - home).Magnitude > 0.3
			end
			if moving then
				lastMove = t
				if math.floor(t * 2) % 2 == 0 then
					set(1, "세차 중 · 정지", C(255, 90, 70))
				else
					set(1, "브레이크 · 기어 P", C(255, 200, 80))
				end
				return
			end
			if t - lastMove < 6 then
				set(2, "세차 완료 · 전진 출차", C(80, 255, 140))
				return
			end
			if zp and params and t - lastScan > 1 then
				lastScan = t
				carIn = false
				pcall(function()
					for _, q in workspace:GetPartBoundsInBox((zp :: BasePart).CFrame, (zp :: BasePart).Size, params :: OverlapParams) do
						local m = q:FindFirstAncestorWhichIsA("Model")
						if m and m:FindFirstChildWhichIsA("VehicleSeat", true) then
							carIn = true
							break
						end
					end
				end)
			end
			if carIn then
				set(1, "정지 · 결제 후 세차", C(255, 90, 70))
			else
				set(2, "↑ 전진 · 천천히 진입", C(80, 255, 140))
			end
		end)
	end)

	-- 6.6 드라이어 아치 (출구, 갠트리 이동 구간 밖) ---------------------------------------------------------------------
	step(K, "dryer", function()
		local az0, az1 = RB.z0 + 0.45, math.min(RB.z0 + 2.0, env0.Z - 0.6)
		if az1 - az0 < 0.9 then
			return
		end
		local az = (az0 + az1) / 2
		local dep = az1 - az0
		local body = lk(C(236, 238, 240))
		local blue = lk(C(30, 100, 190))
		local cols = {}
		for _, s in { -1, 1 } do
			local x0 = if s < 0 then RB.x0 + 0.1 else rightX + 0.25
			local x1 = if s < 0 then leftX - 0.25 else RB.x1 - 0.1
			local cx = (x0 + x1) / 2
			local w = x1 - x0
			if w > 0.6 then
				D.box("DryerColumn", V3(w, 9.0, dep), CF(cx, y0 + 4.5, az), body)
				D.box("DryerColumnStripe", V3(w + 0.02, 0.5, dep + 0.02), CF(cx, y0 + 6.0, az), blue)
				for k = 0, 4 do
					D.box("DryerSideSlot", V3(0.06, 0.9, dep * 0.6), CF(cx - s * (w / 2 + 0.02), y0 + 1.2 + k * 1.0, az), L.black)
				end
				table.insert(cols, cx)
			end
		end
		if #cols == 2 then
			D.box("DryerBeam", V3(RB.x1 - RB.x0 - 0.2, 1.2, dep), CF((RB.x0 + RB.x1) / 2, y0 + 9.6, az), body)
			D.box("DryerBeamStripe", V3(RB.x1 - RB.x0 - 0.2, 0.25, dep + 0.02), CF((RB.x0 + RB.x1) / 2, y0 + 9.25, az), blue)
			for _, x in { -3.2, 3.2 } do
				D.cyl("BlowerHousing", 1.2, 1.7, CF(x, y0 + 10.9, az) * ANG(0, PI / 2, 0), body)
				D.disc("BlowerCap", 1.1, 0.12, CF(x, y0 + 11.85, az), lk(C(60, 64, 70), M.Metal))
				D.wedge("DryerNozzle", V3(3.4, 1.0, 1.0), CF(x, y0 + 8.55, az + 0.2) * ANG(0, PI, 0), lk(C(60, 64, 70), M.Plastic))
				D.box("DryerNozzleSlot", V3(3.0, 0.08, 0.5), CF(x, y0 + 8.08, az + 0.35), L.black)
			end
			D.label("DryerText", 5.0, 0.7, CFrame.fromMatrix(V3(0, y0 + 9.65, az + dep / 2 + 0.01), XA, YA, ZA), "DRY  ·  건조", WHITE, nil, { d = 0.01, font = Enum.Font.GothamBlack })
			D.label("DryerTextBack", 5.0, 0.7, CFrame.fromMatrix(V3(0, y0 + 9.65, az - dep / 2 - 0.01), -XA, YA, -ZA), "광안 오토 WASH", WHITE, nil, { d = 0.01, font = Enum.Font.GothamBlack })
		end
	end)

	-- 6.7 오른쪽 통로: 프리워시 폼건 스테이션 · 제어반 + 약품 · 왼쪽 드라잉존 타월 랙 ---------------------------------------------
	step(K, "sideStrips", function()
		-- 폼건 (진입 쪽 오른쪽)
		local fz0, fz1 = math.max(RB.z0 + 2, env1.Z - 4.6), env1.Z - 0.3
		local fx0 = rightX + 0.15
		local fpcf = D.wallPf("right", (fz0 + fz1) / 2, RB.x1 - fx0)
		if RB.x1 - fx0 > 0.8 and spot(G, fpcf, V3(fz1 - fz0, 4.4, RB.x1 - fx0), 0, "foamLance") then
			propGroup(G, "foamLance", V3(fx0, 0, fz0), V3(RB.x1, 4.4, fz1), function()
				local w = fz1 - fz0
				local dep = RB.x1 - fx0
				D.box("PumpBox", V3(1.8, 1.6, math.min(0.9, dep)), fpcf * CF(-w / 2 + 1.1, 2.6, -dep / 2 + 0.45), L.stainless)
				D.label("PumpLabel", 1.6, 0.36, fpcf * CF(-w / 2 + 1.1, 3.05, -dep / 2 + 0.92), "고압 프리워시", WHITE, C(30, 90, 170), { d = 0.01 })
				D.disc("PumpGauge", 0.38, 0.06, fpcf * CF(-w / 2 + 1.5, 2.3, -dep / 2 + 0.92) * ANG(PI / 2, 0, 0), L.white)
				D.cyl("HoseReelWall", 0.5, 1.3, fpcf * CF(0.2, 2.7, -dep / 2 + 0.3) * ANG(0, PI / 2, 0), lk(C(30, 90, 170), M.Plastic))
				D.ring("LanceHoseCoil", fpcf * CF(0.2, 2.7, -dep / 2 + 0.56), 0.55, 0.09, 12, L.black)
				-- 폼건 (홀스터에 걸린 랜스)
				local gp = fpcf * CF(w / 2 - 0.8, 2.5, -dep / 2 + 0.35)
				D.box("LanceHolster", V3(0.5, 0.5, 0.3), gp, L.darkAlu)
				D.seg("LanceWand", (gp * CF(0, 0.2, 0.2)).Position, (gp * CF(0.2, -1.6, 0.55)).Position, 0.08, L.steel)
				D.box("LanceGun", V3(0.18, 0.5, 0.3), gp * CF(0, 0.45, 0.25), lk(C(220, 50, 40), M.Plastic))
				local tip = gp * CF(0.2, -1.7, 0.6)
				local nozzle = D.vcyl("FoamCannon", 0.5, 0.36, gp * CF(0.05, 0.95, 0.3), { c = C(230, 240, 245), m = M.Glass, t = 0.3 })
				local foam = {}
				for i = 0, 5 do
					local f = D.ell("FoamSpray", V3(0.5 + i * 0.12, 0.35 + i * 0.1, 0.5 + i * 0.12), tip * CF(0.05 * i, -0.15 - i * 0.18, 0.12 * i), { c = WHITE, m = M.SmoothPlastic, t = 1 })
					table.insert(foam, f)
				end
				safetySign(D, D.wall("right", (fz0 + fz1) / 2 + 1.0, 5.2, 0.03), 1.6, 1.3, "warn", "고압 분사 주의")
				local on = false
				prompt(G, nozzle, {
					action = "폼건 분사",
					object = "프리워시 폼건",
					fn = function(_n: number, pr: ProximityPrompt)
						on = not on
						for i, f in foam do
							if f.Parent then
								f.Transparency = if on then 0.15 + i * 0.1 else 1
							end
						end
						pr.ActionText = if on then "분사 멈추기" else "폼건 분사"
					end,
				})
			end)
		end
		-- 제어반 + 약품 드럼 (출구 쪽 오른쪽, 갠트리 옆)
		local cz0, cz1 = env0.Z + 0.6, env0.Z + 5.2
		local cpcf = D.wallPf("right", (cz0 + cz1) / 2, RB.x1 - fx0)
		if RB.x1 - fx0 > 0.8 and spot(G, cpcf, V3(cz1 - cz0, 6.0, RB.x1 - fx0), 0, "washControl") then
			propGroup(G, "washControl", V3(fx0, 0, cz0), V3(RB.x1, 6, cz1), function()
				local dep = RB.x1 - fx0
				local w = cz1 - cz0
				local cab = fpcf and cpcf * CF(-w / 2 + 1.0, 0, -dep / 2 + 0.45)
				D.box("ControlCabinet", V3(1.8, 5.0, 0.9), cab * CF(0, 2.5, 0), lk(C(200, 204, 208), M.Metal))
				D.box("ControlDoorLine", V3(0.03, 4.8, 0.02), cab * CF(0, 2.5, 0.46), lk(C(140, 144, 148)))
				D.box("ControlWindow", V3(0.8, 0.9, 0.02), cab * CF(-0.4, 3.6, 0.46), { c = C(30, 40, 50), m = M.Glass, t = 0.2 })
				for k = 0, 3 do
					D.box("PLCLight", V3(0.08, 0.08, 0.02), cab * CF(-0.65 + k * 0.17, 3.4, 0.47), lk(({ C(40, 230, 110), C(40, 230, 110), C(255, 170, 30), C(255, 60, 40) })[k + 1], M.Neon))
				end
				D.cyl("ControlEStop", 0.12, 0.34, cab * CF(0.45, 3.0, 0.5) * ANG(0, PI / 2, 0), lk(C(220, 30, 30)))
				D.box("ControlEStopRing", V3(0.5, 0.5, 0.04), cab * CF(0.45, 3.0, 0.46), L.yellow)
				D.vcyl("ControlBeacon", 0.4, 0.3, cab * CF(0, 5.2, 0), lk(C(255, 170, 30), M.Neon, { t = 0.2 }))
				D.label("ControlLabel", 1.6, 0.36, cab * CF(0, 4.6, 0.46), "세차기 제어반", INK, C(250, 250, 246), { d = 0.01 })
				safetySign(D, cab * CF(0.45, 2.0, 0.46), 0.9, 1.0, "warn", "감전 주의")
				local drums = { { "샴푸", C(40, 110, 200) }, { "폼", C(240, 240, 236) }, { "왁스", C(240, 190, 30) } }
				for i, d in drums do
					local dp = cpcf * CF(-w / 2 + 2.4 + (i - 1) * 0.85, 0, -dep / 2 + 0.45)
					D.rbox("ChemDrum", V3(0.7, 1.3, 0.6), 0.08, dp * CF(0, 0.65, 0), lk(d[2], M.Plastic))
					D.vcyl("ChemCap", 0.12, 0.22, dp * CF(0.15, 1.36, 0), L.black)
					D.seg("ChemTube", (dp * CF(0.15, 1.4, 0)).Position, (dp * CF(0.15, 3.6, -0.3)).Position, 0.05, { c = C(230, 236, 240), m = M.Glass, t = 0.3 })
					D.label("ChemLabel", 0.6, 0.3, dp * CF(0, 0.8, 0.31), d[1], INK, C(250, 250, 246), { d = 0.005 })
				end
				D.seg("ChemManifold", (cpcf * CF(-w / 2 + 2.4, 3.6, -dep / 2 + 0.15)).Position, (cpcf * CF(-w / 2 + 4.3, 3.6, -dep / 2 + 0.15)).Position, 0.12, L.steel)
				D.seg("ChemRiser", (cpcf * CF(-w / 2 + 4.3, 3.6, -dep / 2 + 0.15)).Position, (cpcf * CF(-w / 2 + 4.3, yR - 0.3, -dep / 2 + 0.15)).Position, 0.12, L.steel)
			end)
		end
		-- 드라잉존 타월 랙 (출구 쪽 왼쪽)
		local tz1 = env0.Z - 0.15
		local tz0 = math.max(RB.z0 + 2.2, tz1 - 2.2)
		local tx1 = leftX - 0.15
		local tpcf = D.wallPf("left", (tz0 + tz1) / 2, tx1 - RB.x0)
		if tz1 - tz0 > 1.2 and spot(G, tpcf, V3(tz1 - tz0, 3.8, tx1 - RB.x0), 0, "towels") then
			propGroup(G, "towels", V3(RB.x0, 0, tz0), V3(tx1, 3.8, tz1), function()
				local w = tz1 - tz0
				for _, s in { -1, 1 } do
					D.box("TowelRackPost", V3(0.1, 3.4, 0.1), tpcf * CF(s * (w / 2 - 0.15), 1.7, 0), L.steel)
					D.box("TowelRackFoot", V3(0.1, 0.06, 0.8), tpcf * CF(s * (w / 2 - 0.15), 0.03, 0), L.steel)
				end
				D.box("TowelRackBar", V3(w - 0.2, 0.08, 0.08), tpcf * CF(0, 3.3, 0), L.steel)
				local tcols = { C(40, 110, 210), C(240, 120, 40), C(60, 170, 110), C(220, 60, 90), C(250, 250, 246) }
				local n = math.max(3, math.floor((w - 0.4) / 0.36))
				for i = 0, n - 1 do
					local x = -w / 2 + 0.3 + i * (w - 0.6) / math.max(1, n - 1)
					D.box("Towel", V3(0.32, 1.3, 0.1), tpcf * CF(x, 2.65, 0.06) * ANG(0, 0, (i % 2 - 0.5) * 0.06), lk(tcols[i % #tcols + 1], M.Fabric))
				end
				D.vcyl("TowelBin", 1.0, 0.9, tpcf * CF(0, 0.5, 0.0), lk(C(60, 64, 70), M.Plastic))
				D.label("TowelBinLabel", 0.8, 0.3, tpcf * CF(0, 0.6, 0.46), "사용 타월", WHITE, nil, { d = 0.005 })
			end)
			D.label("DryZoneSign", 3.4, 0.9, D.wall("left", (tz0 + tz1) / 2, 5.4, 0.03), "드라잉존 · 셀프 타월", WHITE, C(30, 90, 170), { d = 0.03, font = Enum.Font.GothamBlack })
		end
	end)

	-- 6.8 천장: 방수 LED 등기구 3 줄 (맵 판 대신) + 지붕 리브 ------------------------------------------------------------
	step(K, "ceiling", function()
		local lit = 0
		hideNamed(G, "LightPanel")
		local rows = { (RB.x0 + leftX) / 2, 0, (rightX + RB.x1) / 2 }
		for ri, x in rows do
			for k = 0, 3 do
				local z = RB.z0 + 4 + k * (RB.z1 - RB.z0 - 8) / 3
				local a, b = V3(x, yR, z - 2.4), V3(x, yR, z + 2.4)
				local dif = linearLED(D, a, b, 0.8, { drop = 0.2, housing = lk(C(200, 204, 208), M.Metal), glow = Look.lampCool })
				if dif and (k == 1 or k == 2) and lit < 3 and (ri == 2 or k == 1) then
					D.light(dif, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 16, Brightness = 0.9, Angle = 140, Color = Look.coolLight })
					lit += 1
				end
			end
		end
		-- 진입 높이 제한 바 (진입로 위, 차보다 높게)
		local hz = RB.z1 - 1.0
		local hy = 9.1
		D.box("HeightBar", V3(zx1 - zx0 + 1.2, 0.4, 0.4), CF((zx0 + zx1) / 2, hy, hz), L.yellow)
		for k = -3, 3 do
			D.box("HeightBarStripe", V3(0.5, 0.42, 0.42), CF((zx0 + zx1) / 2 + k * 1.9, hy, hz) * ANG(0, 0, math.rad(30)), L.black)
		end
		for _, sx in { -1, 1 } do
			D.seg("HeightBarChain", V3((zx0 + zx1) / 2 + sx * 5.0, hy + 0.2, hz), V3((zx0 + zx1) / 2 + sx * 5.0, yR, hz), 0.06, lk(C(150, 150, 154), M.Metal))
		end
		D.label("HeightBarSign", 3.6, 0.7, CFrame.fromMatrix(V3((zx0 + zx1) / 2, hy + 0.75, hz + 0.05), XA, YA, ZA), "높이 제한 2.1m", INK, L.yellow.c, { d = 0.04, font = Enum.Font.GothamBlack })
		-- 갠트리 전원 · 호스 페스툰 레일 (오른쪽 위) + 홈 쪽에 몰린 케이블 고리
		local fx = (rightX + RB.x1) / 2
		D.box("FestoonRail", V3(0.3, 0.3, env1.Z - env0.Z), CF(fx, yR - 0.35, (env0.Z + env1.Z) / 2), L.darkAlu)
		for k = 0, 4 do
			local z = env0.Z + 0.6 + k * 0.45
			D.seg("FestoonLoop", V3(fx, yR - 0.5, z), V3(fx, yR - 1.6 - k * 0.08, z + 0.22), 0.12, L.black)
			D.seg("FestoonLoop", V3(fx, yR - 1.6 - k * 0.08, z + 0.22), V3(fx, yR - 0.5, z + 0.45), 0.12, L.black)
		end
		local nrib = if hi then 14 else 7
		for i = 0, nrib - 1 do
			local z = RB.z0 + 1 + i * (RB.z1 - RB.z0 - 2) / (nrib - 1)
			D.box("RoofRib", V3(RB.x1 - RB.x0 + 0.4, 0.12, 0.2), CF((RB.x0 + RB.x1) / 2, yR - 0.06, z), lk(C(206, 210, 214), M.Metal))
		end
	end)

	-- 6.9 갠트리 디테일 (갠트리 · 브러시를 매 프레임 따라감): 브러시 천 스트립 · 분사 노즐 · 다리 패널 · 앞 LED ----------------------
	step(K, "gantryDetail", function()
		if not gantry then
			return
		end
		local follow = {}
		local function att(ref: BasePart?, list: { BasePart })
			if not ref then
				return
			end
			for _, p in list do
				if p and p.Parent then
					table.insert(follow, { p = p, ref = ref, off = ref.CFrame:ToObjectSpace(p.CFrame) })
				end
			end
		end
		local function grab(fn: () -> ()): { BasePart }
			local i0 = #K.parts
			fn()
			local out = {}
			for i = i0 + 1, #K.parts do
				table.insert(out, K.parts[i])
			end
			return out
		end
		-- 브러시 천 스트립 (브러시 파트 로컬: 축 = X)
		for _, nm in { "BrushL", "BrushR", "BrushTop" } do
			local br = gparts[nm]
			if br then
				local len = br.Size.X
				local rad = math.min(br.Size.Y, br.Size.Z) / 2
				local base = G.Binv * V.cf:ToObjectSpace(br.CFrame)
				local col = br.Color
				-- 천 브러시: 축에서 바깥으로 뻗은 얇은 천 날개 (회전 방향으로 살짝 휘어 털처럼 보이게) + 양 끝 허브 캡
				local n = if hi then 22 else 12
				local list = grab(function()
					for i = 0, n - 1 do
						local a = i * 2 * PI / n
						local c = if i % 3 == 0 then col:Lerp(WHITE, 0.3) elseif i % 3 == 1 then col else col:Lerp(C(0, 0, 0), 0.2)
						D.box("BrushFin", V3(len - 0.35, 0.62, 0.07), base * ANG(a, 0, 0) * CF(0, rad + 0.12, 0) * ANG(0.42, 0, 0), lk(c, M.Fabric))
					end
					for _, s in { -1, 1 } do
						D.cyl("BrushHub", 0.12, rad * 1.1, base * CF(s * (len / 2 - 0.05), 0, 0), lk(C(60, 64, 70), M.Metal))
					end
				end)
				att(br, list)
			end
		end
		-- 분사 바 노즐 + 폼 아치 (빔 / 분사 바)
		local sb = gparts.SprayBar
		if sb then
			local base = G.Binv * V.cf:ToObjectSpace(sb.CFrame)
			local len = sb.Size.X
			local list = grab(function()
				local n = if hi then 12 else 7
				for i = 0, n - 1 do
					local x = -len / 2 + 0.5 + i * (len - 1) / (n - 1)
					D.vcyl("SprayNozzle", 0.25, 0.12, base * CF(x, -0.3, 0.1), Look.brass)
					D.box("SprayNozzleTip", V3(0.1, 0.06, 0.18), base * CF(x, -0.46, 0.14), L.black)
				end
			end)
			att(sb, list)
		end
		local beamP = gparts.GantryBeam
		if beamP then
			local base = G.Binv * V.cf:ToObjectSpace(beamP.CFrame)
			local bz = beamP.Size.Z / 2
			local list = grab(function()
				D.box("GantryLEDPanel", V3(6.0, 0.9, 0.06), base * CF(0, 0, bz + 0.04), L.black)
				D.label("GantryLEDText", 5.8, 0.75, base * CF(0, 0, bz + 0.08), "광안 오토 WASH  ·  세차 중 이동 금지", C(255, 200, 80), nil, { d = 0.005, glow = 1.4, font = Enum.Font.GothamBold })
				D.box("GantryBeamStripe", V3(beamP.Size.X, 0.18, 0.04), base * CF(0, -0.55, bz + 0.03), lk(C(40, 120, 210)))
				D.box("GantryBeamStripe", V3(beamP.Size.X, 0.18, 0.04), base * CF(0, -0.55, -bz - 0.03), lk(C(40, 120, 210)))
			end)
			att(beamP, list)
		end
		for _, leg in gantry:GetDescendants() do
			if leg:IsA("BasePart") and leg.Name == "GantryLeg" then
				local base = G.Binv * V.cf:ToObjectSpace(leg.CFrame)
				local sx = if base.Position.X < 0 then 1 else -1 -- 안쪽
				local h = leg.Size.Y
				local list = grab(function()
					-- 안쪽 면: 세로 분사 파이프 + 노즐
					D.vcyl("SidePipe", h - 1.6, 0.14, base * CF(sx * (leg.Size.X / 2 + 0.1), 0.2, 0.6), L.steel)
					for k = 0, 5 do
						D.box("SideNozzle", V3(0.16, 0.1, 0.1), base * CF(sx * (leg.Size.X / 2 + 0.2), -h / 2 + 1.4 + k * 1.4, 0.6), Look.brass)
					end
					-- 바깥 면: 조작 패널 · 경고등 · 휠 커버
					D.box("LegPanel", V3(0.06, 1.6, 1.4), base * CF(-sx * (leg.Size.X / 2 + 0.03), 0.8, 0), lk(C(236, 238, 240)))
					D.box("LegPanelScreen", V3(0.02, 0.5, 0.8), base * CF(-sx * (leg.Size.X / 2 + 0.07), 1.2, 0), lk(C(40, 120, 210), M.Neon, { t = 0.2 }))
					D.box("LegEStop", V3(0.1, 0.25, 0.25), base * CF(-sx * (leg.Size.X / 2 + 0.08), 0.5, 0.3), lk(C(220, 30, 30)))
					D.box("LegWheelCover", V3(leg.Size.X + 0.2, 0.6, leg.Size.Z + 0.3), base * CF(0, -h / 2 + 0.3, 0), lk(C(50, 54, 60), M.Metal))
					D.label("LegBadge", 1.4, 0.4, base * CF(0, h / 2 - 1.2, leg.Size.Z / 2 + 0.01), "GW WASH", WHITE, nil, { d = 0.005, font = Enum.Font.GothamBlack })
				end)
				att(leg, list)
			end
		end
		if #follow == 0 then
			return
		end
		local refs = {}
		local seen = {}
		for _, f in follow do
			if not seen[f.ref] then
				seen[f.ref] = true
				table.insert(refs, { p = f.ref, last = f.ref.CFrame })
			end
		end
		K.conns = K.conns or {}
		table.insert(K.conns, RunService.RenderStepped:Connect(function()
			local changed = false
			for _, r in refs do
				local cf = r.p.CFrame
				if cf ~= r.last then
					r.last = cf
					changed = true
				end
			end
			if not changed then
				return
			end
			local parts, cfs = {}, {}
			for _, f in follow do
				if f.p.Parent then
					table.insert(parts, f.p)
					table.insert(cfs, f.ref.CFrame * f.off)
				end
			end
			local ok = pcall(function()
				workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
			end)
			if not ok then
				for i, p in parts do
					p.CFrame = cfs[i]
				end
			end
		end))
	end)

	-- 6.10 출구 뒤: 셀프 진공청소기 (맵 상자 대신) · 매트 세척기 ------------------------------------------------------
	step(K, "vacuum", function()
		local vs = G.byName.VacuumStation and G.byName.VacuumStation[1]
		local gy = if vs then vs.min.Y else y0 - 0.12
		local saved = RB.z0
		RB.z0 = saved - 7
		local vx, vz = 11.26, -27.48
		if vs then
			vx, vz = vs.c.X, vs.c.Z
			hideRec(G, vs)
			hideNamed(G, "VacuumHose")
		end
		local ign: { [any]: boolean } = {}
		if vs then
			ign[vs.part] = true
		end
		for _, r in G.byName.VacuumHose or {} do
			ign[r.part] = true
		end
		local vp = pf(vx, gy, vz, 180)
		if spot(G, vp, V3(2.6, 7.0, 2.2), 0, "vacuum", ign) then
			propGroup(G, "vacuum", V3(vx - 1.3, 0, vz - 1.1), V3(vx + 1.3, 7, vz + 1.1), function()
				-- 패드 + 노랑 차막이 연석
				D.box("VacPad", V3(2.6, 0.12, 2.2), vp * CF(0, 0.06, 0), lk(C(170, 168, 162), M.Concrete))
				D.box("VacCurb", V3(2.4, 0.3, 0.3), vp * CF(0, 0.27, 0.92), L.yellow)
				for k = 0, 3 do
					D.box("VacCurbStripe", V3(0.3, 0.31, 0.31), vp * CF(-0.9 + k * 0.6, 0.27, 0.92), L.black)
				end
				-- 스테인리스 본체 (둥근 모서리) + 브랜드 머리
				local body = vp * CF(0, 0.12, -0.15)
				D.rbox("VacCabinet", V3(1.9, 3.5, 1.3), 0.12, body * CF(0, 1.75, 0), L.stainless)
				D.box("VacKick", V3(1.92, 0.3, 1.32), body * CF(0, 0.15, 0), lk(C(40, 42, 46), M.Metal))
				D.box("VacSeam", V3(0.02, 2.6, 0.02), body * CF(0, 1.9, 0.66), lk(C(140, 144, 150)))
				D.rbox("VacCrown", V3(2.05, 0.75, 1.42), 0.1, body * CF(0, 3.85, 0), lk(C(240, 196, 30)))
				D.box("VacCrownBand", V3(2.07, 0.12, 1.44), body * CF(0, 3.5, 0), lk(C(30, 90, 170)))
				D.label("VacCrownText", 1.9, 0.6, body * CF(0, 3.85, 0.72), "VACUUM · 셀프 진공", INK, nil, { d = 0.005, clear = true, font = Enum.Font.GothamBlack })
				D.label("VacCrownTextB", 1.9, 0.6, body * CF(0, 3.85, -0.72) * ANG(0, PI, 0), "광안 오토 WASH", INK, nil, { d = 0.005, clear = true, font = Enum.Font.GothamBlack })
				-- 조작판: LED 시간 · 카드 · 지폐 · 동전 · 시작 버튼 · 사용법
				local pnl = body * CF(0, 2.6, 0.66)
				D.box("VacPanel", V3(1.5, 1.3, 0.04), pnl, lk(C(30, 32, 36)))
				local _, vlab = D.label("VacScreen", 0.9, 0.34, pnl * CF(-0.18, 0.38, 0.03), "1,000원 · 4분", C(255, 120, 60), C(10, 10, 12), { d = 0.005, glow = 1.4, font = Enum.Font.RobotoMono })
				D.box("VacCardReader", V3(0.36, 0.42, 0.06), pnl * CF(0.5, 0.3, 0.04), lk(C(60, 62, 66)))
				D.box("VacCardLED", V3(0.24, 0.05, 0.02), pnl * CF(0.5, 0.44, 0.08), lk(C(40, 200, 90), M.Neon))
				D.label("VacCardText", 0.32, 0.14, pnl * CF(0.5, 0.2, 0.08), "카드 · 페이", WHITE, nil, { d = 0.003 })
				D.box("VacBillSlot", V3(0.6, 0.08, 0.06), pnl * CF(-0.25, 0.02, 0.04), L.chrome)
				D.label("VacBillText", 0.6, 0.12, pnl * CF(-0.25, -0.1, 0.03), "지폐 1,000원", WHITE, nil, { d = 0.003 })
				D.box("VacCoinSlot", V3(0.06, 0.22, 0.06), pnl * CF(0.25, -0.05, 0.04), L.chrome)
				D.label("VacCoinText", 0.34, 0.12, pnl * CF(0.5, -0.05, 0.03), "500원", WHITE, nil, { d = 0.003 })
				local btn = D.cyl("VacButton", 0.08, 0.3, pnl * CF(-0.4, -0.38, 0.06) * ANG(0, PI / 2, 0), lk(C(40, 200, 90), M.Neon))
				D.label("VacButtonText", 0.5, 0.14, pnl * CF(0.15, -0.38, 0.03), "시작 / 정지", WHITE, nil, { d = 0.003 })
				D.box("VacCoinReturn", V3(0.3, 0.2, 0.12), pnl * CF(0.5, -0.45, 0.06), L.chrome)
				D.label("VacHowTo", 1.5, 0.75, body * CF(0, 1.4, 0.665), "① 결제  ② 시작 버튼\n③ 사용 후 호스 걸기\n유리 · 액체 흡입 금지", INK, C(250, 250, 246), { d = 0.005 })
				D.label("VacPhone", 1.5, 0.22, body * CF(0, 0.75, 0.665), "고장 문의 051-752-0000", INK, C(240, 196, 30), { d = 0.005 })
				-- 옆면: 노즐 홀더 2 · 호스 걸이
				for _, s in { -1, 1 } do
					local sp = body * CF(s * 0.97, 2.2, 0.2)
					D.box("NozzleHolster", V3(0.12, 0.6, 0.3), sp, lk(C(40, 42, 46), M.Plastic))
					D.box("VacNozzleStored", V3(0.14, 0.9, 0.14), sp * CF(s * 0.12, -0.2, 0) * ANG(0, 0, s * 0.12), lk(C(30, 32, 34), M.Plastic))
					D.box("VacNozzleTip", V3(0.08, 0.3, 0.32), sp * CF(s * 0.14, -0.75, 0), lk(C(30, 32, 34), M.Plastic))
				end
				-- 상부 회전 붐 + 처진 호스 2 (곡선)
				local post0 = body * CF(0, 4.22, -0.2)
				D.vcyl("VacBoomPost", 2.0, 0.24, post0 * CF(0, 1.0, 0), L.steel)
				D.vcyl("VacSwivel", 0.3, 0.42, post0 * CF(0, 2.0, 0), lk(C(40, 42, 46), M.Metal))
				local bA = (post0 * CF(0, 2.05, 0)).Position
				local bB = (post0 * CF(-3.4, 2.05, 0.3)).Position
				D.seg("VacBoom", bA, bB, 0.2, L.steel)
				D.seg("VacBoomStay", (post0 * CF(0, 1.1, 0)).Position, (post0 * CF(-1.8, 2.0, 0.16)).Position, 0.08, L.steel)
				D.box("VacBoomEnd", V3(0.3, 0.3, 0.3), post0 * CF(-3.45, 2.05, 0.3), lk(C(240, 196, 30)))
				local function hose(a: Vector3, c: Vector3, b: Vector3, n: number)
					local prev = a
					for i = 1, n do
						local t = i / n
						local p = a * (1 - t) * (1 - t) + c * 2 * t * (1 - t) + b * t * t
						D.seg("VacHose", prev, p, 0.24, lk(C(34, 36, 40), M.Rubber))
						if hi and i < n then
							D.ball("VacHoseCuff", 0.27, CF(p), lk(C(24, 26, 28), M.Rubber))
						end
						prev = p
					end
				end
				for k, ox in { 1.7, 3.3 } do
					local top = (post0 * CF(-ox, 1.95, 0.15 * k)).Position
					D.box("VacHoseClip", V3(0.26, 0.3, 0.26), CF(top), L.black)
					if k == 1 then
						-- 붐에서 U 자로 처져 본체 옆 걸이로 돌아온 호스 (사용 후 걸어 둔 모양)
						local endP = (body * CF(-0.98, 2.9, -0.3)).Position
						local ctl = (post0 * CF(-ox * 0.9, -5.0, 0.9)).Position
						hose(top - Vector3.yAxis * 0.15, ctl, endP, if hi then 8 else 5)
						D.box("VacHoseHook", V3(0.36, 0.14, 0.3), body * CF(-1.1, 2.85, -0.3), lk(C(40, 42, 46), M.Metal))
					else
						-- 붐 끝에서 늘어진 호스 + 노즐 (차 쪽으로)
						local endP = (post0 * CF(-ox - 0.2, -2.6, 0.9)).Position
						local ctl = (post0 * CF(-ox - 0.4, -0.6, 0.3)).Position
						hose(top - Vector3.yAxis * 0.15, ctl, endP, if hi then 6 else 4)
						local tip = endP - Vector3.yAxis * 1.1
						D.seg("VacWand", endP, tip, 0.15, L.steel)
						D.box("VacCrevice", V3(0.12, 0.45, 0.24), CF(tip - Vector3.yAxis * 0.2), lk(C(30, 32, 34), M.Plastic))
					end
				end
				-- 옆 쓰레기통
				local tb = vp * CF(1.05, 0.12, 0.55)
				D.vcyl("VacTrash", 1.3, 0.62, tb * CF(0, 0.65, 0), lk(C(60, 120, 70), M.Plastic))
				D.vcyl("VacTrashLid", 0.12, 0.66, tb * CF(0, 1.36, 0), lk(C(40, 90, 50), M.Plastic))
				D.label("VacTrashText", 0.5, 0.2, tb * CF(0, 0.9, 0.315), "쓰레기", WHITE, nil, { d = 0.003 })
				local on = false
				local t0 = 0
				Interact.anim(K, function(t: number)
					if not on then
						return
					end
					if t0 == 0 then
						t0 = t
					end
					local left = math.max(0, 240 - (t - t0))
					if vlab.Parent then
						vlab.Text = string.format("작동 중 %d:%02d", left // 60, math.floor(left % 60))
					end
					if left <= 0 then
						on = false
					end
				end)
				prompt(G, btn, {
					action = "청소기 켜기",
					object = "셀프 진공청소기 (구경용)",
					fn = function(_n: number, pr: ProximityPrompt)
						on = not on
						t0 = 0
						if not on then
							vlab.Text = "1,000원 · 4분"
						end
						btn.Color = if on then C(255, 70, 50) else C(40, 200, 90)
						pr.ActionText = if on then "청소기 끄기" else "청소기 켜기"
					end,
				})
			end)
		end
		-- 매트 세척기 (진공청소기 옆)
		local mx = vx - 3.15
		local mp = pf(mx, gy, vz, 180)
		if spot(G, mp, V3(1.95, 3.8, 2.2), 0, "matWasher", ign) then
			propGroup(G, "matWasher", V3(mx - 1.2, 0, vz - 1.1), V3(mx + 1.2, 3.8, vz + 1.1), function()
				D.box("MatPad", V3(2.4, 0.12, 2.2), mp * CF(0, 0.06, 0), lk(C(170, 168, 162), M.Concrete))
				D.box("MatWasherBody", V3(2.2, 3.0, 1.6), mp * CF(0, 1.62, -0.1), lk(C(236, 238, 240)))
				D.box("MatWasherTop", V3(2.3, 0.2, 1.7), mp * CF(0, 3.2, -0.1), lk(C(30, 100, 190)))
				D.box("MatSlot", V3(1.8, 0.06, 0.25), mp * CF(0, 3.31, 0.2), L.black)
				D.box("MatWindow", V3(1.6, 1.0, 0.04), mp * CF(0, 2.0, 0.71), { c = C(40, 50, 60), m = M.Glass, t = 0.35 })
				local rollers = {}
				for k = 0, 1 do
					table.insert(rollers, D.cyl("MatRoller", 1.5, 0.45, mp * CF(0, 1.75 + k * 0.5, 0.45), lk(if k == 0 then C(40, 110, 210) else C(230, 70, 50), M.Fabric)))
				end
				D.box("MatOutTray", V3(1.9, 0.08, 0.7), mp * CF(0, 0.75, 0.95) * ANG(math.rad(15), 0, 0), L.steel)
				D.label("MatSign", 1.9, 0.5, mp * CF(0, 2.8, 0.71), "매트 세척 1,000원", WHITE, C(30, 100, 190), { d = 0.01 })
				local btn = D.cyl("MatButton", 0.06, 0.26, mp * CF(0.8, 1.2, 0.72) * ANG(0, PI / 2, 0), lk(C(40, 200, 90), M.Neon))
				-- 매트 걸이
				local hp = mp * CF(-1.6, 0, 0.2)
				D.box("MatHangerPost", V3(0.12, 3.6, 0.12), hp * CF(0, 1.8, 0), L.steel)
				D.box("MatHangerBar", V3(0.1, 0.1, 1.4), hp * CF(0, 3.5, 0), L.steel)
				for k = 0, 1 do
					D.box("HangingMat", V3(0.06, 1.8, 1.0), hp * CF(0.08 + k * 0.08, 2.5, -0.3 + k * 0.6), lk(if k == 0 then C(30, 30, 32) else C(70, 60, 50), M.Rubber))
				end
				local spinning = false
				local rcf = {}
				for _, r in rollers do
					table.insert(rcf, r.CFrame)
				end
				Interact.anim(K, function(t: number)
					if not spinning then
						return
					end
					for i, r in rollers do
						if r.Parent then
							r.CFrame = rcf[i] * CFrame.Angles(t * 6 * (if i == 1 then 1 else -1), 0, 0)
						end
					end
				end)
				prompt(G, btn, {
					action = "세척기 돌리기",
					object = "매트 세척기 (구경용)",
					fn = function(_n: number, pr: ProximityPrompt)
						spinning = not spinning
						btn.Color = if spinning then C(255, 70, 50) else C(40, 200, 90)
						pr.ActionText = if spinning then "세척기 멈추기" else "세척기 돌리기"
					end,
				})
			end)
		end
		RB.z0 = saved
	end)
	return G
end
buildWash = buildWashImpl

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
