--!nocheck
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
-- (한 파일 버전: tools/bundle_luau.py 가 GwangalliBuildingInterior 폴더를 묶은 것. StarterPlayerScripts 에 LocalScript 로 넣으세요)

local __defs, __cache = {}, {}
local function __require(name)
	local v = __cache[name]
	if v == nil then
		v = __defs[name]()
		__cache[name] = v
	end
	return v
end

__defs["Build"] = function()
-- GwangalliBuildingInterior/Build: 한 매장 짓기. V (Scan.fit) -> K (Kit, 만든 파트 · 숨긴 원본 · 불빛 · 프롬프트)
--   유형 모듈 T_* : { types = { "cafe", ... }, style = function(V) -> S, build = function(K, V, S) }
--   순서: Common.run(K, V, S) (공통 마감 + 리스킨) -> T.build (유형별 디테일) -> 정리.
-- 각 단계는 pcall: 한 단계가 실패해도 나머지는 지어지고 K.log 에 남습니다.

local Kit = __require("Kit")
local Look = __require("Look")
local Common = __require("Common")

local Build = {}

local MODULES = {
	__require("T_cafe"),
	__require("T_pub"),
	__require("T_korean"),
	__require("T_grill"),
	__require("T_seafood"),
	__require("T_fastfood"),
	__require("T_store"),
	__require("T_service"),
	__require("T_style"),
	-- 큰 시설의 방 (Venues)
	__require("T_pc"),
	__require("T_karaoke"),
	__require("T_gs25"),
	__require("T_delivery"),
	__require("T_arcade"),
	__require("T_bowling"),
	__require("T_billiards"),
	__require("T_gym"), -- T_style 의 gym 보다 뒤 (덮어씀)
	__require("T_club"),
	__require("T_facility"),
	__require("T_clinic"),
	__require("T_garage"),
	__require("T_home"),
}
local BY_TYPE: { [string]: any } = {}
for _, m in MODULES do
	for _, t in m.types or {} do
		BY_TYPE[t] = m
	end
end
Build.BY_TYPE = BY_TYPE

-- 유형을 모르는 매장: 깔끔한 기본 마감만
local GENERIC = {
	style = function(V: any): any
		if V.kind == "venue" or V.kind == "home" then
			-- 전용 모듈이 없는 큰 시설의 방: 기존 가구는 그대로, 천장 설비만
			return { chair = false, stool = false, table = false, counter = false, base = false, lower = false, mat = false, clock = false, license = false, cctv = false, ceiling = {}, lights = { kind = "none" }, skip = { upgrades = true, fixtures = true } }
		end
		return {
			chair = { style = "padded", frame = Look.blackMetal, seat = Look.fabricGrey },
			stool = {},
			table = { top = Look.oak, base = Look.blackMetal },
			counter = { front = "panel", frontL = Look.white, topL = Look.marbleWhite },
			ceiling = { grid = false },
			lights = { kind = "downlight" },
		}
	end,
	build = function() end,
}

function Build.moduleFor(t: string?): any
	return (t and BY_TYPE[t]) or GENERIC
end

function Build.run(V: any, parent: Instance): any
	local K = Kit.new(V, parent)
	K.hidden = {}
	local T = Build.moduleFor(V.type)
	local S: any = {}
	local ok, res = pcall(T.style, V)
	if ok and type(res) == "table" then
		S = res
	elseif not ok then
		K:note("style error: " .. tostring(res))
	end
	K.style = S
	Common.run(K, V, S)
	if T.build then
		local ok2, err = pcall(T.build, K, V, S)
		if not ok2 then
			K:note("build error: " .. tostring(err))
		end
	end
	K:finish()
	return K
end

return Build

end

__defs["Common"] = function()
-- GwangalliBuildingInterior/Common: 모든 매장 공통 마감 + 기존 가구 리스킨.
--   Common.run(K, V, S)  S = 유형 스타일 (T_* 모듈의 style(V) 결과). 순서:
--     1) 리스킨: 의자 · 스툴 · 테이블 · 카운터 (원래 자세 그대로 덮어씌우고 원본은 숨김, R3/R4)
--     2) 맵의 엉성한 소품 바꾸기: 펜던트 · 화분 · 소화기 · 형광등 (같은 자리)
--     3) 천장 (텍스 그리드 / 단색 스킨) + 설비 (스프링클러 · 감지기 · CCTV)
--     4) 벽: 걸레받이 + 아랫벽 마감 (웨인스코팅 · 타일 · 루버)
--     5) 바닥 오버레이 (선택) + 현관 매트
--     6) 작은 벽 부착물: 조명 스위치(상호작용) · 콘센트 · 온도조절기 · 비상벨 · 사업자등록증 · 시계
-- S 필드 (모두 선택):
--   chair = { style, frame, seat, back } | false     stool = { style, frame, seat } | false
--   table = { style, top, edge, base, thick, r } | false     counter = { front, frontL, topL, kickL, led } | false
--   ceiling = { grid = bool, skin = look, tile } | false    floor = { look, tile, grout } | false
--   lower = { kind = "wainscot" | "tile" | "louver" | "paint", h, look, cap, walls = { "back", "left", "right" } } | false
--   base = look (걸레받이) | false     pendant = { shade, look, dia } (맵 펜던트 바꿀 모양)
--   clock = bool, license = bool, cctv = bool, mat = { look, text } | false
--   lights = { kind = "downlight" | "panel" | "none", n, color, glow }  (우리 불빛, 최대 V.maxLights)

local Kit = __require("Kit")
local Look = __require("Look")
local Props = __require("Props")
local Interact = __require("Interact")
local Scan = __require("Scan")

local Common = {}
local CF, V3 = CFrame.new, Vector3.new
local PI = math.pi

local function hideRec(K: any, r: any)
	Scan.hide(K.hidden, r.part)
end
Common.hideRec = hideRec

-- 의자 · 스툴 -----------------------------------------------------------------------------------------
local function chairFrame(ch: any): CFrame
	local s = ch.seat
	local f: Vector3 = ch.face
	local p = V3(s.c.X, 0, s.c.Z)
	-- pcf: +Z = 앉은 사람이 보는 쪽
	return CFrame.lookAt(p, p - f)
end

function Common.chairs(K: any, V: any, S: any)
	local cs = S.chair
	if cs == false then
		return
	end
	-- 파트 예산: 의자 리스킨이 예산의 40% 를 넘지 않게 디테일을 낮춤 (고급 ~30, 보통 ~22, 저사양 6 파트)
	local n = #V.chairs
	local detail = K.detail
	if n * 30 > K.maxParts * 0.4 then
		detail = if n * 22 > K.maxParts * 0.4 then "low" else "mid"
	end
	for _, ch in V.chairs do
		local s = ch.seat
		-- Seat 인스턴스(앉기용, 보이지 않는 것)는 건드리지 않음
		if s.part:IsA("Seat") and s.part.Transparency >= 0.99 then
			continue
		end
		local w = math.max(1.1, math.min(2.2, math.min(s.size.X, s.size.Z) + 0.05))
		local d = w
		local backH = 1.8
		if ch.back then
			backH = math.clamp(ch.back.max.Y - ch.top, 1.0, 3.2)
		end
		local o = table.clone(cs or {})
		o.seatTop = ch.top
		o.w = w
		o.d = d
		o.backH = o.backH or backH
		o.detail = if detail == "high" then o.detail else detail
		K:free(function()
			Props.chair(K, chairFrame(ch), o)
		end)
		for _, r in ch.parts do
			hideRec(K, r)
		end
		K:reserve(V3(s.min.X - 0.3, 0, s.min.Z - 0.3), V3(s.max.X + 0.3, ch.top + backH, s.max.Z + 0.3), "chair")
	end
end

function Common.stools(K: any, V: any, S: any)
	local ss = S.stool
	if ss == false then
		return
	end
	for _, ch in V.stools do
		local s = ch.seat
		if s.part:IsA("Seat") and s.part.Transparency >= 0.99 then
			continue
		end
		local o = table.clone(ss or {})
		o.seatTop = ch.top
		o.dia = math.max(0.9, math.min(1.8, math.max(s.size.X, s.size.Z)))
		if not o.style then
			o.style = if ch.top > 2.3 then "bar" elseif s.name == "Stool" then "plastic" else "wood"
		end
		K:free(function()
			Props.stool(K, CF(s.c.X, 0, s.c.Z), o)
		end)
		for _, r in ch.parts do
			hideRec(K, r)
		end
		K:reserve(V3(s.min.X - 0.2, 0, s.min.Z - 0.2), V3(s.max.X + 0.2, ch.top + 0.5, s.max.Z + 0.2), "stool")
	end
end

function Common.tables(K: any, V: any, S: any)
	local ts = S.table
	if ts == false then
		return
	end
	for _, t in V.tables do
		if t.kind == "grill" then
			continue -- 불판 테이블은 유형 빌더가 (화로 · 후드 연동)
		end
		local o = table.clone(ts or {})
		if t.kind == "bar" then
			o.style = o.barStyle or "steel"
		end
		Props.tableOver(K, t, o)
		for _, r in t.parts do
			hideRec(K, r)
		end
		K:reserve(V3(t.min.X, 0, t.min.Z), V3(t.max.X, t.y + 0.2, t.max.Z), "table")
	end
end

function Common.counters(K: any, V: any, S: any)
	local cs = S.counter
	if cs == false then
		return
	end
	for _, g in V.counters do
		Props.counterOver(K, g, cs or {})
		for _, r in g.parts do
			-- CounterTop · Counter 는 게임플레이 파트: 덮어씌웠으니 원본은 숨김 (자리 · 높이 그대로)
			hideRec(K, r)
		end
		K:reserve(g.min - V3(0.1, 0, 0.1), g.max + V3(0.1, 0, 0.1), "counter")
	end
end

-- 맵 소품 바꾸기 -----------------------------------------------------------------------------------------
function Common.upgrades(K: any, V: any, S: any)
	-- 펜던트: PendantShade / PendantGlobe (+ Cord + Bulb) -> Props.pendant
	local ps = S.pendant or {}
	for _, nm in { "PendantShade", "PendantGlobe" } do
		for _, r in V.byName[nm] or {} do
			local topY = V.H
			local drop = topY - r.min.Y
			local p = V3(r.c.X, topY, r.c.Z)
			local shade = ps.shade or (if nm == "PendantGlobe" then "globe" else "dome")
			K:free(function()
				Props.pendant(K, p, math.max(0.8, drop - 0.1), { shade = shade, dia = ps.dia or math.max(r.size.X, r.size.Z), look = ps.look, light = (#K.lights < 4), range = 11, bright = 0.55 })
			end)
			hideRec(K, r)
			for _, q in V.parts do
				if (q.name == "PendantCord" or q.name == "PendantBulb") and math.abs(q.c.X - r.c.X) < 0.4 and math.abs(q.c.Z - r.c.Z) < 0.4 then
					hideRec(K, q)
				end
			end
		end
	end
	-- 큰 화분 (Pot + Soil + Leaves 묶음, 'Plant' 모델) -> Props.floorPlant
	for _, r in V.byName.Pot or {} do
		if r.c.Z < V.z1 - 0.2 and r.size.Y > 1.2 then
			local kinds = S.plants or { "monstera", "olive", "snake" }
			local kind = kinds[(math.floor(r.c.X * 7 + r.c.Z * 3) % #kinds) + 1]
			K:free(function()
				Props.floorPlant(K, CF(r.c.X, 0, r.c.Z), { kind = kind, h = math.clamp(V.H * 0.55, 4, 6), dia = math.min(1.8, math.max(r.size.X, r.size.Z)) })
			end)
			hideRec(K, r)
			for _, q in V.parts do
				if (q.name == "Soil" or q.name == "Leaves") and math.abs(q.c.X - r.c.X) < 1.6 and math.abs(q.c.Z - r.c.Z) < 1.6 then
					hideRec(K, q)
				end
			end
		end
	end
	-- 소화기 (빨간 통 + 밸브) -> 손잡이 · 호스 · 압력계 · 받침
	for _, r in V.byName.FireExtinguisher or {} do
		local p = V3(r.c.X, 0, r.c.Z)
		K:free(function()
			local base = CF(p)
			K:box("ExtStand", V3(0.9, 0.12, 0.9), base * CF(0, 0.06, 0), Look.of(180, 30, 30))
			K:vcyl("ExtBody", 1.5, 0.62, base * CF(0, 0.12 + 0.75, 0), Look.of(200, 24, 28))
			K:ell("ExtDome", V3(0.62, 0.3, 0.62), base * CF(0, 1.62, 0), Look.of(200, 24, 28))
			K:vcyl("ExtNeck", 0.16, 0.2, base * CF(0, 1.8, 0), Look.black)
			K:box("ExtHandle", V3(0.5, 0.06, 0.12), base * CF(0.08, 1.95, 0) * CFrame.Angles(0, 0, -0.2), Look.black)
			K:ball("ExtGauge", 0.18, base * CF(0, 1.82, 0.12), Look.white)
			K:seg("ExtHose", (base * CF(-0.05, 1.82, -0.1)).Position, (base * CF(-0.3, 0.6, -0.3)).Position, 0.08, Look.black)
			K:text("ExtLabel", 0.44, 0.5, CFrame.fromMatrix((base * CF(0, 1.0, 0.315)).Position, Vector3.xAxis, Vector3.yAxis, Vector3.zAxis), "소화기\nABC", { fg = Color3.fromRGB(255, 255, 255), bg = Color3.fromRGB(40, 40, 40), d = 0.01, free = true })
		end)
		hideRec(K, r)
		for _, q in V.byName.ExtinguisherValve or {} do
			if math.abs(q.c.X - r.c.X) < 0.8 and math.abs(q.c.Z - r.c.Z) < 0.8 then
				hideRec(K, q)
			end
		end
	end
	-- 형광등 (TubeLamp + TubeFitting) -> 반사갓 있는 LED 등기구
	for _, r in V.byName.TubeLamp or {} do
		local long = math.max(r.size.X, r.size.Z)
		local alongX = r.size.X >= r.size.Z
		local c = V3(r.c.X, V.H, r.c.Z)
		K:free(function()
			local rot = if alongX then CFrame.new() else CFrame.Angles(0, PI / 2, 0)
			local base = CF(c) * rot
			K:box("TubeHousing", V3(long + 0.3, 0.16, 0.7), base * CF(0, -0.08, 0), Look.white)
			local glow = K:box("TubeDiffuser", V3(long, 0.04, 0.5), base * CF(0, -0.18, 0), Look.lampCool)
			if #K.lights < (V.maxLights or 8) - 2 then
				K:light(glow, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 14, Brightness = 0.6, Angle = 150, Color = Look.coolLight })
			end
		end)
		hideRec(K, r)
		for _, q in V.byName.TubeFitting or {} do
			if (q.c - r.c).Magnitude < long then
				hideRec(K, q)
			end
		end
	end
end

-- 천장 -----------------------------------------------------------------------------------------------
-- 천장 아래 비어 있는 xz 점인가? (AC · 펜던트 · 맵 조명 피하기)
function Common.ceilFree(K: any, x: number, z: number, r: number): boolean
	local V = K.V
	for _, h in V.hang do
		if x > h.min.X - r and x < h.max.X + r and z > h.min.Z - r and z < h.max.Z + r then
			return false
		end
	end
	for _, p in V.parts do
		if (p.name == "CassetteAC" or p.name == "ACVanes" or p.name == "ShopLight" or p.name == "Downlight" or p.name == "Troffer" or p.name == "TBar" or p.name == "CCTV" or p.name == "TrackRail") and x > p.min.X - r and x < p.max.X + r and z > p.min.Z - r and z < p.max.Z + r then
			return false
		end
	end
	for _, q in K.ceilUsed or {} do
		if math.abs(q.X - x) < r * 2 and math.abs(q.Z - z) < r * 2 then
			return false
		end
	end
	return true
end

function Common.useCeil(K: any, x: number, z: number)
	K.ceilUsed = K.ceilUsed or {}
	table.insert(K.ceilUsed, V3(x, 0, z))
end

function Common.ceiling(K: any, V: any, S: any)
	local cs = S.ceiling
	if cs == false then
		return
	end
	cs = cs or {}
	-- 맵에 이미 T-bar · Troffer 천장이 있으면 그리드는 안 덮음
	local hasGrid = V:has("TBar") > 0 or V:has("Troffer") > 0
	if cs.grid and not hasGrid then
		Props.ceilingGrid(K, { tile = cs.tile or 2.0, skin = cs.skin })
	elseif cs.skin then
		K:free(function()
			K:box("CeilingSkin", V3(V.W - 0.05, 0.02, V.D - 0.05), CF((V.x0 + V.x1) / 2, V.H - 0.03, (V.z0 + V.z1) / 2), cs.skin)
		end)
	end
	-- 몰딩 (천장-벽 경계)
	if cs.crown then
		for _, w in { "back", "left", "right" } do
			local wall = V.walls[w]
			K:free(function()
				K:plate("Crown", wall.b - wall.a, 0.22, 0.12, V:wall(w, (wall.a + wall.b) / 2, V.H - 0.11, 0.0), cs.crown)
			end)
		end
	end
	-- 설비: 스프링클러 격자 (약 7 스터드 간격) · 화재감지기 2 · CCTV 1
	local nx = math.max(1, math.floor(V.W / 7))
	local nz = math.max(1, math.floor(V.D / 7))
	for i = 1, nx do
		for j = 1, nz do
			local x = V.x0 + V.W * (i - 0.5) / nx + 0.6
			local z = V.z0 + V.D * (j - 0.5) / nz - 0.4
			if Common.ceilFree(K, x, z, 0.5) then
				Props.sprinkler(K, x, z)
				Common.useCeil(K, x, z)
			end
		end
	end
	local det = 0
	for _, f in { { 0.25, 0.3 }, { 0.75, 0.7 }, { 0.5, 0.5 } } do
		local x, z = V.x0 + V.W * f[1], V.z0 + V.D * f[2]
		if det < 2 and Common.ceilFree(K, x, z, 0.6) then
			Props.smokeDetector(K, x, z)
			Common.useCeil(K, x, z)
			det += 1
		end
	end
	if S.cctv ~= false and V:has("CCTV") == 0 then
		local x, z = V.x1 - 1.2, V.z0 + 1.2
		if Common.ceilFree(K, x, z, 0.5) then
			Props.cctv(K, x, z)
			Common.useCeil(K, x, z)
		end
	end
	-- 우리 조명 (맵 조명이 적은 매장만)
	local ls = S.lights or {}
	if ls.kind and ls.kind ~= "none" then
		local n = ls.n or math.clamp(math.floor(V.W * V.D / 60), 2, 8)
		local cols = math.max(1, math.floor(math.sqrt(n * V.W / math.max(1, V.D)) + 0.5))
		local rows = math.max(1, math.ceil(n / cols))
		for i = 1, cols do
			for j = 1, rows do
				local x = V.x0 + V.W * (i - 0.5) / cols
				local z = V.z0 + V.D * (j - 0.5) / rows
				if Common.ceilFree(K, x, z, 0.8) then
					local withLight = ((i + j) % 2 == 0) and #K.lights < (V.maxLights or 8) - 1
					if ls.kind == "panel" then
						Props.panelLight(K, x, z, { light = withLight, color = ls.color, glow = ls.glow })
					else
						Props.downlight(K, x, z, { light = withLight, color = ls.color, glow = ls.glow })
					end
					Common.useCeil(K, x, z)
				end
			end
		end
	end
end

-- 벽 ------------------------------------------------------------------------------------------------
function Common.walls(K: any, V: any, S: any)
	if S.base ~= false then
		for _, w in { "back", "left", "right" } do
			K:free(function()
				Props.baseboard(K, w, S.base or Look.white)
			end)
		end
	end
	local lw = S.lower
	if lw then
		local h = lw.h or 3.0
		for _, w in lw.walls or { "left", "right" } do
			K:free(function()
				if lw.kind == "tile" then
					for _, s in V:spans(w, 0.45, h, 0.25) do
						Props.wallTiles(K, w, s[1], s[2], 0.45, h, { look = lw.look, grout = lw.grout, tw = lw.tw, th = lw.th })
					end
				elseif lw.kind == "louver" then
					for _, s in V:spans(w, 0.45, h, 0.25) do
						Props.louverWall(K, w, s[1], s[2], 0.45, h, { look = lw.look, back = lw.back, pitch = lw.pitch })
					end
				elseif lw.kind == "paint" then
					for _, s in V:spans(w, 0.45, h, 0.25) do
						K:plate("WallPaint", s[2] - s[1], h - 0.45, 0.02, V:wall(w, (s[1] + s[2]) / 2, 0.45 + (h - 0.45) / 2, 0.01), lw.look)
						K:plate("WallPaintLine", s[2] - s[1], 0.06, 0.04, V:wall(w, (s[1] + s[2]) / 2, h, 0.01), lw.cap or Look.white)
					end
				else
					Props.wainscot(K, w, h, { look = lw.look, cap = lw.cap, panel = lw.panel })
				end
			end)
		end
	end
end

-- 작은 벽 부착물 ---------------------------------------------------------------------------------------
-- 벽면 빈 자리 하나 찾기 (폭 w, 높이 y0..y1). 반환 dcf 또는 nil. 찾은 자리는 K.wallUsed 에 기록
function Common.wallSpot(K: any, walls: { string }, w: number, y0: number, y1: number, prefer: number?): (string?, CFrame?)
	local V = K.V
	K.wallUsed = K.wallUsed or {}
	for _, wn in walls do
		local spans = V:spans(wn, y0, y1, 1.0)
		-- 이미 쓴 자리 빼기
		local cand = {}
		for _, s in spans do
			local a, b = s[1], s[2]
			for _, u in K.wallUsed do
				if u.w == wn and u.y1 > y0 and u.y0 < y1 then
					if u.a <= a and u.b >= b then
						a = b
					elseif u.a > a and u.a < b and u.b >= b then
						b = u.a
					elseif u.b > a and u.b < b and u.a <= a then
						a = u.b
					elseif u.a > a and u.b < b then
						table.insert(cand, { a, u.a })
						a = u.b
					end
				end
			end
			if b - a >= w then
				table.insert(cand, { a, b })
			end
		end
		local best, bd = nil, math.huge
		for _, s in cand do
			if s[2] - s[1] >= w then
				local target = prefer or 0
				local u = math.clamp(target, s[1] + w / 2, s[2] - w / 2)
				local d = math.abs(u - target)
				if d < bd then
					best, bd = u, d
				end
			end
		end
		if best then
			table.insert(K.wallUsed, { w = wn, a = best - w / 2 - 0.2, b = best + w / 2 + 0.2, y0 = y0, y1 = y1 })
			return wn, V:wall(wn, best, (y0 + y1) / 2, 0.0)
		end
	end
	return nil, nil
end

function Common.fixtures(K: any, V: any, S: any)
	-- 조명 스위치 (상호작용) + 콘센트: 입구 쪽 옆벽, 높이 4.2
	local side = if V.door and V.door.x > 0 then "left" else "right"
	local wn, dcf = Common.wallSpot(K, { side, if side == "left" then "right" else "left" }, 1.0, 3.8, 4.6, if side == "left" then -V.D / 2 + 3 else V.D / 2 - 3)
	if wn and dcf then
		local plate = Props.switchPlate(K, dcf, 2)
		Interact.lightSwitch(K, plate, "실내 조명 스위치")
	end
	local wn2, d2 = Common.wallSpot(K, { "left", "right", "back" }, 0.5, 1.0, 1.7, 0)
	if wn2 and d2 then
		Props.outlet(K, d2)
	end
	local wn3, d3 = Common.wallSpot(K, { side, "back" }, 0.7, 4.5, 5.3, 0)
	if wn3 and d3 then
		Props.thermostat(K, d3)
	end
	-- 비상벨 (소화기 위 또는 옆벽)
	local wn4, d4 = Common.wallSpot(K, { "right", "left" }, 1.0, 4.4, 5.4, 0)
	if wn4 and d4 then
		Props.fireBell(K, d4)
	end
	-- 사업자등록증 (계산대 가까운 벽)
	if S.license ~= false and #V.counters > 0 then
		local g = V.counters[1]
		local wn5, d5 = Common.wallSpot(K, { "back", "left", "right" }, 1.3, 5.0, 6.7, (g.min.X + g.max.X) / 2 - (V.x0 + V.x1) / 2 + 3)
		if wn5 and d5 then
			Props.license(K, d5, V.name)
		end
	end
	-- 벽시계 (상호작용 없이 실제 게임 시각으로 돔)
	if S.clock ~= false then
		local h = math.min(V.H - 1.4, 7.6)
		local wn6, d6 = Common.wallSpot(K, { "back", "left", "right" }, 1.6, h - 0.8, h + 0.8, 0)
		if wn6 and d6 then
			local hr, mn = Props.clock(K, d6, 1.4, S.clockLook)
			Interact.clock(K, hr, mn, d6, 1.4)
		end
	end
end

function Common.floor(K: any, V: any, S: any)
	if S.floor then
		Props.floorTiles(K, S.floor)
	end
	if S.mat ~= false then
		Props.doorMat(K, S.mat or {})
	end
end

function Common.run(K: any, V: any, S: any)
	local steps = {
		{ "floor", Common.floor },
		{ "ceiling", Common.ceiling },
		{ "walls", Common.walls },
		{ "chairs", Common.chairs },
		{ "stools", Common.stools },
		{ "tables", Common.tables },
		{ "counters", Common.counters },
		{ "upgrades", Common.upgrades },
		{ "fixtures", Common.fixtures },
	}
	for _, st in steps do
		if S.skip and S.skip[st[1]] then
			continue
		end
		local ok, err = pcall(st[2], K, V, S)
		if not ok then
			K:note("common." .. st[1] .. " error: " .. tostring(err))
		end
	end
end

return Common

end

__defs["Homes"] = function()
-- GwangalliBuildingInterior/Homes: 생활 게임 집 (HomeUnit_goshiwon · oneroom · officetel · apartment · penthouse) 을 방 단위로.
-- 집 모델(Workspace.GwangalliHomeInstances 아래 HomeUnit 복제본, 속성 Tier)의 Shell 바닥 파트(속성 Room = main / kitchen / bath /
-- living / bedroom / ...)를 방마다 묶어 Scan.fitRoom 용 spec 을 만듭니다. 방 프레임은 UnitRoot 방향, +Z = 그 방의 문(Door 모델) 쪽.
-- 플레이어가 꾸미는 집이라: 가구 슬롯(FurnitureSlot) 자리 · HomeInteract 파트 둘레는 비워 두고(post), 벽 · 바닥 색은 바꾸지 않습니다.
--   Homes.find() -> { { model, room, spec } }       Homes.rooms(model) -> { spec ... }       Homes.post(V, model)

local CollectionService = game:GetService("CollectionService")

local Homes = {}

local function laabb(cf: CFrame, size: Vector3): (Vector3, Vector3)
	local h = size / 2
	local ex = math.abs(cf.XVector.X) * h.X + math.abs(cf.YVector.X) * h.Y + math.abs(cf.ZVector.X) * h.Z
	local ey = math.abs(cf.XVector.Y) * h.X + math.abs(cf.YVector.Y) * h.Y + math.abs(cf.ZVector.Y) * h.Z
	local ez = math.abs(cf.XVector.Z) * h.X + math.abs(cf.YVector.Z) * h.Y + math.abs(cf.ZVector.Z) * h.Z
	local p = cf.Position
	return Vector3.new(p.X - ex, p.Y - ey, p.Z - ez), Vector3.new(p.X + ex, p.Y + ey, p.Z + ez)
end

local ROOM_OF = { FloorEntry = "entry", FloorBath = "bath" }

function Homes.isUnit(m: Instance): boolean
	return m:IsA("Model") and m:GetAttribute("Tier") ~= nil and m:FindFirstChild("Shell") ~= nil and m:FindFirstChild("UnitRoot") ~= nil
end

-- 방 spec 목록
function Homes.rooms(model: Model): { any }
	local root = model:FindFirstChild("UnitRoot") :: BasePart?
	local shell = model:FindFirstChild("Shell")
	if not root or not shell then
		return {}
	end
	local base = CFrame.new(root.Position) * root.CFrame.Rotation
	local boxes: { [string]: { any } } = {}
	local ceilY = -math.huge
	for _, p in shell:GetDescendants() do
		if p:IsA("BasePart") then
			local room = p:GetAttribute("Room") :: string?
			local surface = p:GetAttribute("Surface")
			local nm = p.Name
			if nm == "Ceiling" then
				local mn = laabb(base:ToObjectSpace(p.CFrame), p.Size)
				ceilY = math.max(ceilY, mn.Y)
			end
			local isFloor = surface == "floor" or ROOM_OF[nm] ~= nil or string.sub(nm, 1, 5) == "Floor"
			if isFloor then
				local r = room or ROOM_OF[nm] or "main"
				local mn, mx = laabb(base:ToObjectSpace(p.CFrame), p.Size)
				local b = boxes[r]
				if not b then
					boxes[r] = { mn, mx }
				else
					b[1] = b[1]:Min(mn)
					b[2] = b[2]:Max(mx)
				end
			end
		end
	end
	-- 문 위치 (방 프레임의 +Z 를 문 쪽으로)
	local doors = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Model") and (d.Name == "Door" or string.sub(d.Name, 1, 5) == "Door_") then
			local cf = d:GetBoundingBox()
			table.insert(doors, base:PointToObjectSpace(cf.Position))
		end
	end
	local out = {}
	for room, b in boxes do
		local mn, mx = b[1], b[2]
		local floorY = mx.Y
		local top = if ceilY > floorY then ceilY else floorY + 8.5
		local c = Vector3.new((mn.X + mx.X) / 2, floorY, (mn.Z + mx.Z) / 2)
		local sx, sz = mx.X - mn.X, mx.Z - mn.Z
		-- 가장 가까운 문 쪽 방향
		local best, bd = nil, math.huge
		for _, dp in doors do
			local cx = math.clamp(dp.X, mn.X, mx.X)
			local cz = math.clamp(dp.Z, mn.Z, mx.Z)
			local d = Vector3.new(dp.X - cx, 0, dp.Z - cz).Magnitude
			if d < bd then
				best, bd = dp, d
			end
		end
		local dir = Vector3.new(0, 0, 1)
		if best and bd < 4 then
			local dx = (best.X - c.X) / math.max(0.1, sx / 2)
			local dz = (best.Z - c.Z) / math.max(0.1, sz / 2)
			if math.abs(dx) > math.abs(dz) then
				dir = Vector3.new(math.sign(dx), 0, 0)
			else
				dir = Vector3.new(0, 0, if dz == 0 then 1 else math.sign(dz))
			end
		end
		local alongX = math.abs(dir.X) > 0.5
		local W = if alongX then sz else sx
		local D = if alongX then sx else sz
		local wc = base * CFrame.new(c)
		local cf = CFrame.lookAt(wc.Position, wc.Position - base:VectorToWorldSpace(dir))
		local spec: any = {
			cf = cf,
			size = Vector3.new(W, top - floorY, D),
			type = "home",
			room = room,
			kind = "home",
			name = (model:GetAttribute("DisplayName") :: any) or model.Name,
			key = string.format("%s#%s@%d,%d,%d", model.Name, room, math.floor(wc.X + 0.5), math.floor(wc.Y + 0.5), math.floor(wc.Z + 0.5)),
			noDoorGuess = true,
			margin = 0.4,
			tier = model:GetAttribute("Tier"),
		}
		table.insert(out, spec)
	end
	table.sort(out, function(a, b)
		return a.room < b.room
	end)
	return out
end

-- 가구 슬롯 자리 · 집 상호작용 파트 둘레 · 커튼 자리는 비움 (플레이어가 고른 가구가 들어가는 곳)
function Homes.post(V: any, model: Instance)
	for _, d in model:GetDescendants() do
		if d:IsA("Model") and (CollectionService:HasTag(d, "FurnitureSlot") or string.sub(d.Name, 1, 5) == "Slot_") then
			local cf, s = d:GetBoundingBox()
			local fp = d:GetAttribute("Footprint")
			local size = if typeof(fp) == "Vector3" then (fp :: Vector3):Max(s) else s
			local lc = V.cf:ToObjectSpace(cf)
			local mn, mx = laabb(lc, size + Vector3.new(0.4, 0.2, 0.4))
			V:addKeep(Vector3.new(mn.X, 0.05, mn.Z), Vector3.new(mx.X, math.max(mx.Y, 0.3), mx.Z), "slot")
		elseif d:IsA("BasePart") and (CollectionService:HasTag(d, "HomeInteract") or string.sub(d.Name, 1, 9) == "Interact_") then
			local lc = V.cf:ToObjectSpace(d.CFrame)
			local mn, mx = laabb(lc, d.Size + Vector3.new(0.6, 0.4, 0.6))
			V:addKeep(mn, mx, "point")
		elseif d:IsA("Model") and (CollectionService:HasTag(d, "GwDecorItem") or (d.Parent and d.Parent.Name == "DecorPlus")) then
			-- 인테리어 모드(GwangalliDecorPlus)로 플레이어가 직접 놓은 가구
			local cf, s = d:GetBoundingBox()
			local mn, mx = laabb(V.cf:ToObjectSpace(cf), s + Vector3.new(0.4, 0.2, 0.4))
			V:addKeep(mn, mx, "slot")
		end
	end
	-- 플레이어가 자유 배치로 꾸미는 집: 가구 · 소품은 플레이어 몫이라 바닥 위 소품은 만들지 않음 (천장 · 벽 마감만)
	local dp = model:FindFirstChild("DecorPlus")
	if dp and #dp:GetChildren() > 0 then
		V.decorPlus = true
	end
end

function Homes.find(): { any }
	local out = {}
	local root = workspace:FindFirstChild("GwangalliHomeInstances")
	if not root then
		return out
	end
	-- 집 모델은 루트 바로 아래나 플레이어별 폴더 아래 (깊이 3 까지만 봄: 집 안의 수천 파트는 훑지 않음)
	local function visit(node: Instance, depth: number)
		for _, d in node:GetChildren() do
			if Homes.isUnit(d) then
				for _, spec in Homes.rooms(d :: Model) do
					table.insert(out, { model = d, room = spec.room, spec = spec })
				end
			elseif depth < 3 and (d:IsA("Folder") or d:IsA("Model")) then
				visit(d, depth + 1)
			end
		end
	end
	visit(root, 1)
	return out
end

return Homes

end

__defs["Interact"] = function()
-- GwangalliBuildingInterior/Interact: 이 클라이언트에서만 도는 상호작용 (서버 행동과 겹치지 않는 것만, R8).
--   * 프롬프트: 이름 "GwInteriorPrompt", R 키 (패드 Y), 최대 5 스터드, OnePerButton, 줄 시야 필요 없음.
--     맵 서버의 앵커(주문 · 계산 · 앉기 · 메뉴판 · 화장실 ...) 6.5 스터드 안에는 만들지 않음.
--   * 종류: toggle (켜기/끄기), cycle (채널 · 곡 · 모드 돌리기), swing (문 · 뚜껑 여닫기), 그리고 프롬프트 없는
--     애니메이션 (시계 바늘 · 화면 순환 · 회전 · 깜빡임) = Interact.anim.
-- 모든 효과는 K.parts 의 파트(클라이언트 소유)만 바꿉니다. 맵 파트는 안 건드림.

local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local Interact = {}

local MAX_DIST = 5
local HOST_GAP = 6.5

-- 서버 앵커가 될 자리 (ShopLife 가 프롬프트를 띄우는 곳): V 에서 미리 계산 + 실제 ShopLife 폴더가 있으면 그 위치
local HOST_NAMES = {
	"PosBase", "OrderKiosk", "KioskScreen", "CounterTop", "KitchenPass", "PassLedge", "Sign_메  뉴", "Sign_MENU", "DoorLeaf",
	"HotWater", "Microwave", "ATMScreen", "TapPost", "TankWater", "DeskBell", "Mailboxes", "Tester", "WaterPurifier", "Bin",
	"TrashBin", "FrontDesk", "WorkDesk", "Gondola_1", "Fridge", "OpenChiller", "PastryCase", "WallRack", "MDBoard",
}

function Interact.hostPoints(V: any): { Vector3 }
	local pts = {}
	for _, n in HOST_NAMES do
		for _, r in V.byName[n] or {} do
			table.insert(pts, r.c)
		end
	end
	for _, t in V.tables or {} do
		table.insert(pts, (t.min + t.max) / 2)
	end
	for _, k in V.keep do
		if k.kind == "bin" then
			table.insert(pts, (k.min + k.max) / 2)
		end
	end
	-- 실제 ShopLife 앵커
	local root = workspace:FindFirstChild("GwangalliBuildingsShopLife")
	local f = root and root:FindFirstChild(V.key)
	local anchors = f and f:FindFirstChild("Anchors")
	if anchors then
		for _, a in anchors:GetChildren() do
			if a:IsA("BasePart") then
				table.insert(pts, V.cf:PointToObjectSpace(a.Position))
			end
		end
	end
	return pts
end

-- 이 로컬 위치에 우리 프롬프트를 둬도 되나?
function Interact.canPrompt(K: any, lp: Vector3): boolean
	if not K.hostPts then
		K.hostPts = Interact.hostPoints(K.V)
	end
	for _, h in K.hostPts do
		local d = h - lp
		if Vector3.new(d.X, 0, d.Z).Magnitude < HOST_GAP then
			return false
		end
	end
	for _, p in K.promptAt or {} do
		if (p - lp).Magnitude < 2.5 then
			return false
		end
	end
	return true
end

local function clickSound(part: BasePart, id: string?)
	local s = Instance.new("Sound")
	s.Name = "GwInteriorClick"
	s.SoundId = id or "rbxasset://sounds/switch.wav"
	s.Volume = 0.35
	s.RollOffMaxDistance = 30
	s.Parent = part
	s:Play()
	task.delay(2, function()
		s:Destroy()
	end)
end
Interact.click = clickSound

-- 프롬프트 붙이기. spec = { action, object, hold?, fn = function(n) end (n = 누른 횟수) , sound? }
function Interact.prompt(K: any, part: BasePart, spec: any): ProximityPrompt?
	if part.Parent == nil then
		return nil
	end
	local lp = K.V.cf:PointToObjectSpace(part.Position)
	if not Interact.canPrompt(K, lp) then
		K:note("prompt skipped near host: " .. tostring(spec.object))
		return nil
	end
	K.promptAt = K.promptAt or {}
	table.insert(K.promptAt, lp)
	local pr = Instance.new("ProximityPrompt")
	pr.Name = "GwInteriorPrompt"
	pr.ActionText = spec.action or "사용하기"
	pr.ObjectText = spec.object or ""
	pr.HoldDuration = spec.hold or 0
	pr.MaxActivationDistance = math.min(spec.dist or MAX_DIST, MAX_DIST)
	pr.RequiresLineOfSight = false
	pr.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	pr.KeyboardKeyCode = Enum.KeyCode.R
	pr.GamepadKeyCode = Enum.KeyCode.ButtonY
	pr.Style = Enum.ProximityPromptStyle.Default
	pr.Parent = part
	local n = 0
	local conn = pr.Triggered:Connect(function()
		n += 1
		local ok, err = pcall(spec.fn, n, pr)
		if not ok then
			warn("[GwangalliBuildingInterior] prompt " .. tostring(spec.object) .. ": " .. tostring(err))
		end
		if spec.sound ~= false then
			clickSound(part, spec.sound)
		end
	end)
	K.conns = K.conns or {}
	table.insert(K.conns, conn)
	table.insert(K.prompts, pr)
	return pr
end

-- 켜기/끄기: on(state) 콜백. 첫 상태 = spec.state (기본 true = 켜짐)
function Interact.toggle(K: any, part: BasePart, spec: any): ProximityPrompt?
	local state = if spec.state == nil then true else spec.state
	local onT, offT = spec.onText or "끄기", spec.offText or "켜기"
	local pr: ProximityPrompt? = nil
	pr = Interact.prompt(K, part, {
		action = if state then onT else offT,
		object = spec.object,
		sound = spec.sound,
		fn = function(_n, p)
			state = not state
			spec.on(state)
			p.ActionText = if state then onT else offT
		end,
	})
	return pr
end

-- 순환: items 를 차례로. spec.on(i, item)
function Interact.cycle(K: any, part: BasePart, items: { any }, spec: any): ProximityPrompt?
	local i = spec.start or 1
	return Interact.prompt(K, part, {
		action = spec.action or "바꾸기",
		object = spec.object,
		sound = spec.sound,
		fn = function()
			i = i % #items + 1
			spec.on(i, items[i])
		end,
	})
end

-- 여닫기: model 안 파트를 hinge(월드 점) 둘레 axis(월드 단위벡터)로 angle 라디안 회전 (트윈)
function Interact.swing(K: any, model: Model, hinge: Vector3, axis: Vector3, angle: number, spec: any?): ProximityPrompt?
	local s: any = spec or {}
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, { p = d, cf = d.CFrame })
		end
	end
	if #parts == 0 then
		return nil
	end
	local open = false
	local handle = model:FindFirstChildWhichIsA("BasePart", true) :: BasePart
	for _, r in parts do
		if string.find(r.p.Name, "Handle") then
			handle = r.p
		end
	end
	local function set(o: boolean)
		local rot = CFrame.new(hinge) * CFrame.fromAxisAngle(axis, if o then angle else 0) * CFrame.new(-hinge)
		for _, r in parts do
			if r.p.Parent then
				TweenService:Create(r.p, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = rot * r.cf }):Play()
			end
		end
	end
	return Interact.prompt(K, handle, {
		action = s.openText or "열기",
		object = s.object or "문",
		sound = s.sound or "rbxasset://sounds/clickfast.wav",
		fn = function(_n, p)
			open = not open
			set(open)
			p.ActionText = if open then (s.closeText or "닫기") else (s.openText or "열기")
		end,
	})
end

-- 조명 묶음 켜고 끄기 (우리 불빛 + 빛나는 네온 파트)
function Interact.lightSwitch(K: any, switchPart: BasePart, object: string?): ProximityPrompt?
	local neons = {}
	for _, p in K.parts do
		if p.Material == Enum.Material.Neon and (string.find(p.Name, "Lamp") or string.find(p.Name, "Bulb") or string.find(p.Name, "Diffuser") or string.find(p.Name, "Lens") or string.find(p.Name, "PanelLight") or string.find(p.Name, "LED")) then
			table.insert(neons, { p = p, c = p.Color })
		end
	end
	return Interact.toggle(K, switchPart, {
		object = object or "실내 조명",
		state = true,
		fn = nil,
		on = function(state)
			for _, l in K.lights do
				l.Enabled = state
			end
			for _, n in neons do
				if n.p.Parent then
					n.p.Material = if state then Enum.Material.Neon else Enum.Material.SmoothPlastic
					n.p.Color = if state then n.c else n.c:Lerp(Color3.fromRGB(120, 120, 120), 0.6)
				end
			end
		end,
	})
end

-- 프롬프트 없는 애니메이션: fn(t, dt) 를 매장이 활성일 때 10Hz 로 부름
function Interact.anim(K: any, fn: (number, number) -> ())
	K.anims = K.anims or {}
	table.insert(K.anims, fn)
end

-- 시계 바늘을 게임 시각(Lighting.ClockTime)에 맞춰 돌림. hour/minute = Props.clock 반환 파트, center = dcf
function Interact.clock(K: any, hour: BasePart, minute: BasePart, dcf: CFrame, d: number)
	if hour.Parent == nil then
		return
	end
	local wc = K.cf * dcf
	Interact.anim(K, function()
		local h = Lighting.ClockTime
		local m = (h % 1) * 60
		local ah = -((h % 12) / 12) * math.pi * 2
		local am = -(m / 60) * math.pi * 2
		hour.CFrame = wc * CFrame.Angles(0, 0, ah) * CFrame.new(0, d * 0.1, 0.145 + 0.01)
		minute.CFrame = wc * CFrame.Angles(0, 0, am) * CFrame.new(0, d * 0.16, 0.165 + 0.01)
	end)
end

-- 화면 순환 (TV · 키오스크 대기화면 · 전광판): label 의 글자 / 화면 파트 색을 period 초마다 바꿈
function Interact.screenLoop(K: any, screen: BasePart?, label: TextLabel?, frames: { any }, period: number?)
	local per = period or 4
	local last = -1
	Interact.anim(K, function(t)
		local i = math.floor(t / per) % #frames + 1
		if i == last then
			return
		end
		last = i
		local f = frames[i]
		if screen and screen.Parent and f.c then
			screen.Color = f.c
		end
		if label and label.Parent and f.text then
			label.Text = f.text
		end
	end)
end

-- 회전 (선풍기 · 실링팬 · 미러볼): parts 를 center(월드) 둘레 Y 축으로 rps 회전/초
function Interact.spin(K: any, parts: { BasePart }, center: Vector3, rps: number)
	local base = {}
	for _, p in parts do
		table.insert(base, { p = p, cf = p.CFrame })
	end
	Interact.anim(K, function(t)
		local rot = CFrame.new(center) * CFrame.Angles(0, t * rps * math.pi * 2, 0) * CFrame.new(-center)
		for _, b in base do
			if b.p.Parent then
				b.p.CFrame = rot * b.cf
			end
		end
	end)
end

return Interact

end

__defs["Kit"] = function()
-- GwangalliBuildingInterior/Kit: 파트 조립 도구. 모든 좌표는 매장 프레임(V.cf) 기준 스터드입니다.
--   매장 프레임: 원점 = 바닥 윗면 가운데, +X = 안쪽(뒷벽)을 보고 섰을 때 오른쪽, +Y = 위,
--   -Z = 뒷벽 쪽, +Z = 입구(거리) 쪽.
-- 파트는 전부 이 클라이언트에만 생기고 Anchored, 충돌·쿼리·터치 없음, 질량 없음 (맵 서버 판정에 영향 없음).
--
-- 두 가지 프레임 규약 (Props · 타입 빌더 공통):
--   * 소품 프레임 pcf: 원점 = 소품 바닥 가운데, +X = 소품의 오른쪽(정면에서 볼 때), +Y = 위,
--     +Z = 소품 정면이 향하는 쪽 (사용자가 서는 쪽). 의자: 앉은 사람이 +Z 를 봄.
--   * 표시면 프레임 dcf: 원점 = 벽·판 표면 위의 점, +X = 보는 사람의 오른쪽, +Y = 위,
--     +Z = 보는 사람 쪽 (표면 바깥). 벽에 붙이는 것 · 글자판 · 액자 · 화면은 전부 dcf 로.
--   V:wall(name, u, y, off) 가 벽의 dcf 를 줍니다 (Scan).
--
-- 막힘 규칙: Kit 는 V.keep (게임플레이용으로 비워 둘 공간: 자동문 앞, 계산대 뒤 직원 자리, 테이블 위,
-- 통로 ...) 과 겹치는 파트를 만들지 않습니다 (ghost 로 남겼다가 끝에 지움). 기존 가구를 정확히 덮어 씌우는
-- 리스킨 · 벽면 마감처럼 의도적으로 그 공간에 들어가야 하면 look.free = true 또는 K:free(fn).
-- 바닥에 세우는 새 소품은 K:spot(lcf, size) 로 자리가 비었는지 먼저 확인하고(기존 가구 · 다른 새 소품 ·
-- keep 전부) 자리를 예약합니다.

local Kit = {}
Kit.__index = Kit

export type Look = {
	c: Color3?,
	m: Enum.Material?,
	t: number?, -- Transparency
	r: number?, -- Reflectance
	shadow: boolean?,
	collide: boolean?, -- 이 클라이언트에서만 충돌 (큰 바닥 가구 · 벽 쪽 진열장에만)
	free: boolean?, -- keep 공간 검사 생략 (리스킨 · 마감 오버레이)
}

local DEFAULT_COLOR = Color3.fromRGB(200, 200, 200)
local PI = math.pi

function Kit.new(V: any, parent: Instance)
	local self = setmetatable({}, Kit)
	self.V = V
	self.cf = V.cf :: CFrame
	self.parent = parent
	self.root = parent
	self.count = 0
	self.blocked = 0
	self.sliceT = os.clock()
	self.slice = 0.0025 -- 프레임당 최대 빌드 시간 (초)
	self.parts = {} :: { BasePart }
	self.ghosts = {} :: { Instance }
	self.lights = {} :: { Light }
	self.prompts = {} :: { ProximityPrompt }
	self.reserved = {} :: { any }
	self.freeDepth = 0
	self.maxParts = V.maxParts or 2600
	-- 디테일 단계: "high" | "mid" | "low" (작은 장식 생략). 의자가 아주 많은 매장은 Common 이 의자만 낮춤
	self.detail = V.detail or (if self.maxParts < 1500 then "low" elseif self.maxParts < 2300 then "mid" else "high")
	self.log = {} :: { string }
	return self
end

-- 시간 분할 양보 (빌드 코루틴 안에서만 호출됨)
function Kit:tick()
	self.count += 1
	if os.clock() - self.sliceT > self.slice then
		task.wait()
		self.sliceT = os.clock()
	end
end

function Kit:note(s: string)
	if #self.log < 60 then
		table.insert(self.log, s)
	end
end

local function apply(p: BasePart, look: any?)
	local l: any = look or {}
	p.Anchored = true
	p.CanCollide = l.collide == true
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = l.shadow == true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Color = l.c or DEFAULT_COLOR
	p.Material = l.m or Enum.Material.SmoothPlastic
	p.Transparency = l.t or 0
	p.Reflectance = l.r or 0
end
Kit.apply = apply

-- 매장 프레임 기준 축 정렬 상자(lcf, size)의 로컬 AABB
local function laabb(lcf: CFrame, size: Vector3): (Vector3, Vector3)
	local h = size / 2
	local r = lcf
	local ex = math.abs(r.XVector.X) * h.X + math.abs(r.YVector.X) * h.Y + math.abs(r.ZVector.X) * h.Z
	local ey = math.abs(r.XVector.Y) * h.X + math.abs(r.YVector.Y) * h.Y + math.abs(r.ZVector.Y) * h.Z
	local ez = math.abs(r.XVector.Z) * h.X + math.abs(r.YVector.Z) * h.Y + math.abs(r.ZVector.Z) * h.Z
	local p = lcf.Position
	return Vector3.new(p.X - ex, p.Y - ey, p.Z - ez), Vector3.new(p.X + ex, p.Y + ey, p.Z + ez)
end
Kit.laabb = laabb

local function overlap(amin: Vector3, amax: Vector3, bmin: Vector3, bmax: Vector3, eps: number): boolean
	return amin.X < bmax.X - eps and amax.X > bmin.X + eps and amin.Y < bmax.Y - eps and amax.Y > bmin.Y + eps and amin.Z < bmax.Z - eps and amax.Z > bmin.Z + eps
end
Kit.overlap = overlap

-- keep 공간과 겹치나? (겹치는 keep 의 kind 를 돌려줌)
function Kit:hitsKeep(mn: Vector3, mx: Vector3): string?
	for _, k in self.V.keep do
		if overlap(mn, mx, k.min, k.max, 0.04) then
			return k.kind
		end
	end
	return nil
end

-- 바닥 소품 자리 확인 + 예약: lcf = 소품 바닥 가운데, size = 소품 전체 크기 (pad = 둘레 여유).
-- 기존 가구(V.solid) · keep · 이미 예약된 새 소품과 겹치면 false.
function Kit:spot(lcf: CFrame, size: Vector3, pad: number?, kind: string?): boolean
	local c = lcf * CFrame.new(0, size.Y / 2, 0)
	local mn, mx = laabb(c, size + Vector3.new(2 * (pad or 0), 0, 2 * (pad or 0)))
	local V = self.V
	if mn.X < V.x0 - 0.05 or mx.X > V.x1 + 0.05 or mn.Z < V.z0 - 0.05 or mx.Z > V.z1 + 0.05 then
		return false
	end
	if self:hitsKeep(mn, mx) then
		return false
	end
	for _, s in V.solid do
		if overlap(mn, mx, s.min, s.max, 0.04) then
			return false
		end
	end
	for _, r in self.reserved do
		if overlap(mn, mx, r.min, r.max, 0.02) then
			return false
		end
	end
	table.insert(self.reserved, { min = mn, max = mx, kind = kind or "prop" })
	return true
end

-- 이미 정해진 자리를 예약만 (리스킨한 가구 등: 이후 새 소품이 겹치지 않게)
function Kit:reserve(mn: Vector3, mx: Vector3, kind: string?)
	table.insert(self.reserved, { min = mn, max = mx, kind = kind or "prop" })
end

-- fn 안에서 만드는 파트는 keep 검사를 하지 않음 (리스킨 · 마감)
function Kit:free(fn: () -> ())
	self.freeDepth += 1
	local ok, err = pcall(fn)
	self.freeDepth -= 1
	if not ok then
		error(err, 0)
	end
end

-- 하위 모델(그룹) 안에서 만들기: 문짝처럼 통째로 움직일 부품, 상호작용 대상
function Kit:group(name: string, fn: () -> ()): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = self.parent
	local prev = self.parent
	self.parent = m
	local ok, err = pcall(fn)
	self.parent = prev
	if not ok then
		error(err, 0)
	end
	return m
end

-- lcf: 매장 프레임 기준 CFrame. 파트를 만들어 현재 parent 에 넣음 (keep 과 겹치면 ghost)
function Kit:make(class: string, name: string, size: Vector3, lcf: CFrame, look: any?, shape: Enum.PartType?): BasePart
	local p = Instance.new(class) :: BasePart
	if shape then
		(p :: Part).Shape = shape
	end
	p.Name = name
	apply(p, look)
	p.Size = size
	p.CFrame = self.cf * lcf
	local l: any = look or {}
	local ghost = false
	if #self.parts >= self.maxParts then
		ghost = true
	elseif self.freeDepth == 0 and not l.free then
		local mn, mx = laabb(lcf, size)
		local k = self:hitsKeep(mn, mx)
		if k then
			ghost = true
			self.blocked += 1
			if self.blocked <= 8 then
				self:note(string.format("blocked %s by keep %s", name, k))
			end
		end
	end
	if ghost then
		table.insert(self.ghosts, p)
		return p
	end
	p.Parent = self.parent
	table.insert(self.parts, p)
	self:tick()
	return p
end

function Kit:box(name: string, size: Vector3, lcf: CFrame, look: any?): BasePart
	return self:make("Part", name, size, lcf, look)
end

-- 쐐기: Roblox WedgePart (뒤 +Z 가 높은 면, 경사는 앞 -Z 아래로)
function Kit:wedge(name: string, size: Vector3, lcf: CFrame, look: any?): BasePart
	return self:make("WedgePart", name, size, lcf, look)
end

-- 원통: 축 = lcf 의 X 축 (Roblox Cylinder 규약). len = 길이, d = 지름
function Kit:cyl(name: string, len: number, d: number, lcf: CFrame, look: any?): BasePart
	return self:make("Part", name, Vector3.new(len, d, d), lcf, look, Enum.PartType.Cylinder)
end

-- 세운 원통 (축 = Y): 기둥 · 컵 · 병 · 화분 · 스툴 다리
function Kit:vcyl(name: string, h: number, d: number, lcf: CFrame, look: any?): BasePart
	return self:make("Part", name, Vector3.new(h, d, d), lcf * CFrame.Angles(0, 0, PI / 2), look, Enum.PartType.Cylinder)
end

function Kit:ball(name: string, d: number, lcf: CFrame, look: any?): BasePart
	return self:make("Part", name, Vector3.new(d, d, d), lcf, look, Enum.PartType.Ball)
end

-- 타원체 (쿠션 · 잎 · 전등갓 · 빵): SpecialMesh Sphere 는 파트 크기에 맞춰 늘어남
function Kit:ell(name: string, size: Vector3, lcf: CFrame, look: any?): BasePart
	local p = self:make("Part", name, size, lcf, look)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

-- 두 점 a, b (매장 프레임) 사이 원통 (파이프 · 다리 · 프레임 · 전선)
function Kit:seg(name: string, a: Vector3, b: Vector3, d: number, look: any?, extra: number?): BasePart?
	local v = b - a
	local len = v.Magnitude
	if len < 1e-3 then
		return nil
	end
	local mid = (a + b) / 2
	local x = v / len
	local up = if math.abs(x.Y) < 0.95 then Vector3.yAxis else Vector3.xAxis
	local z = x:Cross(up).Unit
	local y = z:Cross(x).Unit
	return self:cyl(name, len + (extra or 0), d, CFrame.fromMatrix(mid, x, y, z), look)
end

-- 두 점 사이 각진 막대 (단면 w x h): 프레임 · 레일 · 몰딩
function Kit:bar(name: string, a: Vector3, b: Vector3, w: number, h: number, look: any?): BasePart?
	local v = b - a
	local len = v.Magnitude
	if len < 1e-3 then
		return nil
	end
	local z = v / len
	local up = if math.abs(z.Y) < 0.95 then Vector3.yAxis else Vector3.xAxis
	local x = up:Cross(z).Unit
	local y = z:Cross(x).Unit
	return self:box(name, Vector3.new(w, h, len), CFrame.fromMatrix((a + b) / 2, x, y, -z), look)
end

-- 원환 (frame 의 XY 평면, 반지름 R, 단면 지름 d, n 조각, a0..a1 라디안)
function Kit:ring(name: string, frame: CFrame, R: number, d: number, n: number, look: any?, a0: number?, a1: number?)
	local s0, s1 = a0 or 0, a1 or PI * 2
	local out = {}
	for i = 0, n - 1 do
		local t0 = s0 + (s1 - s0) * i / n
		local t1 = s0 + (s1 - s0) * (i + 1) / n
		local pa = frame * Vector3.new(math.cos(t0) * R, math.sin(t0) * R, 0)
		local pb = frame * Vector3.new(math.cos(t1) * R, math.sin(t1) * R, 0)
		local p = self:seg(name, pa, pb, d, look, d * 0.42)
		if p then
			table.insert(out, p)
		end
	end
	return out
end

-- 모서리가 둥근 상자 (lcf 의 X 축 방향 4개 모서리를 반지름 r 로): 상자 2개 + 원통 4개
function Kit:rbox(name: string, size: Vector3, r: number, lcf: CFrame, look: any?): { BasePart }
	r = math.min(r, size.Y / 2 - 1e-3, size.Z / 2 - 1e-3)
	if r <= 0.01 then
		return { self:box(name, size, lcf, look) }
	end
	local out = {}
	table.insert(out, self:box(name, Vector3.new(size.X, size.Y - 2 * r, size.Z), lcf, look))
	table.insert(out, self:box(name, Vector3.new(size.X, size.Y, size.Z - 2 * r), lcf, look))
	for _, sy in { -1, 1 } do
		for _, sz in { -1, 1 } do
			table.insert(out, self:cyl(name, size.X, 2 * r, lcf * CFrame.new(0, sy * (size.Y / 2 - r), sz * (size.Z / 2 - r)), look))
		end
	end
	return out
end

-- 위에서 보면 네 모서리가 둥근 수평 판 (상판 · 쟁반 · 매트): 폭 w(X), 길이 len(Z), 두께 t, 모서리 r. lcf = 판 중심
function Kit:slab(name: string, w: number, len: number, t: number, r: number, lcf: CFrame, look: any?): { BasePart }
	return self:rbox(name, Vector3.new(t, w, len), math.min(r, w / 2 - 0.002, len / 2 - 0.002), lcf * CFrame.Angles(0, 0, PI / 2), look)
end

-- 정면에서 보면 네 모서리가 둥근 판 (dcf: +Z = 보는 쪽): 폭 w, 높이 h, 두께 d, 모서리 r. 판은 표면에서 d 만큼 나옴
function Kit:panel(name: string, w: number, h: number, d: number, r: number, dcf: CFrame, look: any?): { BasePart }
	return self:rbox(name, Vector3.new(d, h, w), math.min(r, w / 2 - 0.002, h / 2 - 0.002), dcf * CFrame.new(0, 0, d / 2) * CFrame.Angles(0, -PI / 2, 0), look)
end

-- 세운 원기둥을 위에서 본 원판 (바닥 원판 · 테이블 상판 · 접시): 지름 dia, 두께 t, lcf = 원판 중심
function Kit:disc(name: string, dia: number, t: number, lcf: CFrame, look: any?): BasePart
	return self:make("Part", name, Vector3.new(t, dia, dia), lcf * CFrame.Angles(0, 0, PI / 2), look, Enum.PartType.Cylinder)
end

-- 표시면(dcf)에 붙는 얇은 판: 표면에서 d 만큼 나온 w x h 상자 (액자 · 포스터 · 화면 · 타일)
function Kit:plate(name: string, w: number, h: number, d: number, dcf: CFrame, look: any?): BasePart
	return self:box(name, Vector3.new(w, h, d), dcf * CFrame.new(0, 0, d / 2), look)
end

-- 글자판: dcf 표면에 w x h 판 + 글자 (SurfaceGui 하나 + TextLabel 하나 = 임시 스튜디오와 실제 게임이 똑같이 보임).
-- opts: fg (글자색), bg (판 색; nil 이면 판 투명 = 글자만), font (Enum.Font), d (두께), glow (SurfaceGui.Brightness,
--   불빛 간판), look (판 재질 look), align ("Left"|"Center"|"Right"), lines (줄 수 힌트), wrap
-- 여러 줄은 "\n" 으로. 반환: 판 파트, TextLabel
function Kit:text(name: string, w: number, h: number, dcf: CFrame, text: string, opts: any?): (BasePart, TextLabel)
	local o: any = opts or {}
	local d = o.d or 0.04
	local look = table.clone(o.look or {})
	if not o.look then
		look.c = o.bg or Color3.new(1, 1, 1)
		look.t = if o.bg then 0 else 1
	end
	look.free = look.free or o.free
	-- 판의 Front(-Z) 가 보는 사람 쪽 (+Z of dcf)
	local p = self:box(name, Vector3.new(w, h, d), dcf * CFrame.new(0, 0, d / 2) * CFrame.Angles(0, PI, 0), look)
	local g = Instance.new("SurfaceGui")
	g.Name = "Gw" .. name
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = o.ppx or math.clamp(math.floor(220 / math.max(w, h)), 24, 80)
	g.LightInfluence = if o.glow then 0 else 1
	g.Brightness = o.glow or 1
	g.MaxDistance = o.maxDist or 60
	g.ClipsDescendants = true
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = if o.bg and not o.look then 0 else 1
	t.BackgroundColor3 = o.bg or Color3.new(1, 1, 1)
	t.BorderSizePixel = 0
	t.Text = text
	t.TextColor3 = o.fg or Color3.fromRGB(20, 20, 22)
	t.TextScaled = true
	t.TextWrapped = o.wrap == true
	t.Font = o.font or Enum.Font.GothamBold
	t.TextXAlignment = if o.align == "Left" then Enum.TextXAlignment.Left elseif o.align == "Right" then Enum.TextXAlignment.Right else Enum.TextXAlignment.Center
	t.RichText = false
	t.Parent = g
	g.Parent = p
	return p, t
end

-- 불빛: kind = "PointLight" | "SpotLight" | "SurfaceLight". props 는 그대로 대입 (Brightness, Range, Color, Face, Angle).
-- GwangalliIndoorLight 가 실내 조명을 x0.55 로 줄이지 않게 GwIndoorDim = 0 을 먼저 붙임 (R9).
function Kit:light(part: BasePart, kind: string, props: { [string]: any }): Light?
	if part.Parent == nil then
		return nil -- ghost
	end
	if #self.lights >= (self.V.maxLights or 8) then
		return nil
	end
	local l = Instance.new(kind) :: Light
	l:SetAttribute("GwIndoorDim", 0)
	l.Shadows = false
	for k, v in props do
		(l :: any)[k] = v
	end
	l.Parent = part
	table.insert(self.lights, l)
	return l
end

-- 끝: ghost 정리
function Kit:finish()
	for _, g in self.ghosts do
		g:Destroy()
	end
	self.ghosts = {}
end

return Kit

end

__defs["Look"] = function()
-- GwangalliBuildingInterior/Look: 재질 · 색 팔레트. look 테이블 = { c, m, t, r, shadow, collide, free }.
--   L.of(r, g, b, material?, extra?)  임의 색
--   L.<이름>                         자주 쓰는 마감재 (아래 목록)
--   L.neon(color) / L.screen(color) / L.glass(tint, t)
--   L.with(look, { ... })             look 에 필드 덧씌우기 (예: L.with(L.oak, { shadow = true }))
-- 실제 한국 매장 마감 기준: 무광 화이트 도장, 오크 · 월넛 무늬목, 스테인리스 주방, 테라조 · 포세린 타일 바닥,
-- 블랙 파우더 코팅 철제 다리, PVC 레더 의자, 아크릴 간판, 텍스 천장 (흡음 텍스 600각).

local M = Enum.Material
local L = {}

local function c3(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
L.rgb = c3

function L.of(r: number, g: number, b: number, m: Enum.Material?, extra: { [string]: any }?): { [string]: any }
	local t: { [string]: any } = { c = c3(r, g, b), m = m or M.SmoothPlastic }
	if extra then
		for k, v in extra do
			t[k] = v
		end
	end
	return t
end

function L.with(look: { [string]: any }, extra: { [string]: any }): { [string]: any }
	local t = table.clone(look)
	for k, v in extra do
		t[k] = v
	end
	return t
end

function L.neon(c: Color3, t: number?): { [string]: any }
	return { c = c, m = M.Neon, t = t or 0 }
end

-- 켜진 화면 (LCD): 약하게 빛나는 SmoothPlastic 위에 글자판 · 화면 GUI 를 얹어 씀
function L.screen(c: Color3?): { [string]: any }
	return { c = c or c3(18, 22, 30), m = M.Glass, r = 0.12 }
end

function L.glass(tint: Color3?, t: number?): { [string]: any }
	return { c = tint or c3(200, 225, 230), m = M.Glass, t = t or 0.6, r = 0.15 }
end

-- 금속
L.chrome = L.of(222, 224, 228, M.Metal, { r = 0.25 })
L.steel = L.of(178, 182, 186, M.Metal, { r = 0.08 }) -- 스테인리스 (주방 · 냉장고 · 싱크)
L.brushed = L.of(160, 163, 168, M.Metal) -- 헤어라인
L.blackMetal = L.of(32, 32, 34, M.Metal) -- 블랙 파우더 코팅 (의자 다리 · 레일 · 조명)
L.brass = L.of(186, 152, 88, M.Metal, { r = 0.1 })
L.goldMetal = L.of(196, 164, 98, M.Metal, { r = 0.12 })
L.alu = L.of(196, 198, 202, M.Metal) -- 알루미늄 프레임 · 섀시
L.darkAlu = L.of(70, 72, 76, M.Metal)

-- 나무 (Wood = 결이 보이는 무늬목, WoodPlanks = 마루 · 루버)
L.oak = L.of(196, 160, 118, M.Wood)
L.lightOak = L.of(214, 186, 148, M.Wood)
L.walnut = L.of(110, 76, 52, M.Wood)
L.darkWood = L.of(72, 50, 36, M.Wood)
L.birch = L.of(226, 206, 174, M.Wood)
L.pine = L.of(208, 168, 112, M.Wood)
L.plywood = L.of(214, 182, 136, M.Wood)
L.floorOak = L.of(170, 128, 88, M.WoodPlanks)
L.louver = L.of(160, 120, 84, M.WoodPlanks)

-- 도장 · 플라스틱
L.white = L.of(242, 242, 238, M.SmoothPlastic) -- 무광 화이트 도장
L.offWhite = L.of(232, 226, 214, M.SmoothPlastic)
L.warmGrey = L.of(170, 164, 156, M.SmoothPlastic)
L.grey = L.of(128, 130, 134, M.SmoothPlastic)
L.charcoal = L.of(48, 50, 54, M.SmoothPlastic)
L.black = L.of(22, 22, 24, M.SmoothPlastic)
L.plasticWhite = L.of(236, 236, 232, M.Plastic)
L.plasticBlack = L.of(28, 28, 30, M.Plastic)
L.rubber = L.of(30, 30, 32, M.Rubber)
L.cardboard = L.of(176, 136, 92, M.Cardboard)
L.paper = L.of(246, 244, 236, M.SmoothPlastic)
L.kraft = L.of(196, 162, 118, M.Cardboard)

-- 돌 · 타일 · 바닥
L.marbleWhite = L.of(236, 234, 228, M.Marble)
L.marbleBlack = L.of(40, 40, 42, M.Marble)
L.terrazzo = L.of(214, 210, 200, M.Granite)
L.granite = L.of(120, 116, 112, M.Granite)
L.concrete = L.of(150, 148, 144, M.Concrete)
L.polishedConcrete = L.of(168, 166, 162, M.Slate, { r = 0.04 })
L.tileWhite = L.of(240, 240, 236, M.CeramicTiles) -- 주방 · 화장실 벽 타일
L.tileGrey = L.of(170, 172, 172, M.CeramicTiles)
L.porcelain = L.of(206, 202, 194, M.CeramicTiles) -- 600각 포세린 바닥 타일
L.brickRed = L.of(150, 82, 62, M.Brick)
L.brickWhite = L.of(226, 222, 214, M.Brick)
L.slate = L.of(70, 72, 74, M.Slate)
L.plaster = L.of(236, 232, 222, M.Plaster)
L.ceilingTex = L.of(240, 238, 232, M.Plaster) -- 흡음 텍스

-- 섬유 · 가죽
L.leatherBlack = L.of(34, 32, 32, M.Leather)
L.leatherBrown = L.of(118, 74, 46, M.Leather)
L.leatherCream = L.of(222, 210, 188, M.Leather)
L.leatherRed = L.of(150, 36, 34, M.Leather)
L.fabricGrey = L.of(140, 140, 138, M.Fabric)
L.fabricBeige = L.of(204, 190, 166, M.Fabric)
L.fabricNavy = L.of(44, 54, 84, M.Fabric)
L.fabricGreen = L.of(70, 98, 74, M.Fabric)
L.carpetGrey = L.of(96, 96, 98, M.Fabric)
L.rattan = L.of(190, 156, 104, M.Fabric)

-- 식물
L.leaf = L.of(70, 112, 58, M.Grass)
L.leafDark = L.of(46, 82, 44, M.Grass)
L.leafLight = L.of(110, 150, 74, M.Grass)
L.soil = L.of(76, 56, 40, M.Ground)
L.terracotta = L.of(182, 104, 70, M.SmoothPlastic)

-- 유리 · 빛
L.glassClear = L.glass(c3(214, 232, 236), 0.7)
L.glassDark = L.glass(c3(40, 46, 52), 0.35)
L.mirror = { c = c3(196, 206, 212), m = M.Glass, t = 0.05, r = 0.55 }
L.acrylicWhite = { c = c3(252, 250, 244), m = M.Glass, t = 0.15 } -- 조명 확산판 · 아크릴
L.lampWarm = L.neon(c3(255, 214, 160)) -- 백열 · 3000K
L.lampNeutral = L.neon(c3(255, 240, 220)) -- 4000K
L.lampCool = L.neon(c3(232, 242, 255)) -- 형광 · 6500K
L.ledRed = L.neon(c3(255, 60, 50))
L.ledGreen = L.neon(c3(60, 230, 120))
L.ledBlue = L.neon(c3(70, 150, 255))

-- 불빛 색 (Light.Color)
L.warmLight = c3(255, 214, 170)
L.neutralLight = c3(255, 238, 220)
L.coolLight = c3(236, 244, 255)

return L

end

__defs["Props"] = function()
-- GwangalliBuildingInterior/Props: 실내 소품 라이브러리 (가구 · 조명 · 벽 부착물 · 카운터 소품).
-- 프레임 규약 (Kit 참고):
--   pcf  소품 프레임: 원점 = 바닥 가운데(또는 올려놓는 면 위), +Z = 소품 정면
--   dcf  표시면 프레임: 원점 = 벽/판 표면 위의 점, +X = 보는 사람 오른쪽, +Z = 보는 사람 쪽
-- 모든 함수: Props.<이름>(K, cf, o?) — o 는 선택 옵션 테이블. 크기 단위 스터드 (사람 키 ≈ 5.2, 의자 좌판 ≈ 1.9).

local Look = __require("Look")

local Props = {}
local PI = math.pi
local CF, V3 = CFrame.new, Vector3.new
local ANG = CFrame.Angles

local function pick(o: any, k: string, d: any): any
	if o and o[k] ~= nil then
		return o[k]
	end
	return d
end

-- 가구 ------------------------------------------------------------------------------------------------

-- 의자. pcf = 좌판 가운데 바로 아래 바닥, +Z = 앉은 사람이 보는 쪽.
-- o.seatTop (좌판 윗면 높이, 기본 1.9), o.w, o.d (좌판 폭 · 깊이), o.backH (좌판 위 등받이 높이),
-- o.style = "diner" (식당: 크롬 파이프 + PVC 쿠션) | "bentwood" (카페 원목) | "shell" (합판 셸 + 철제 다리)
--         | "padded" (패브릭 다이닝) | "plastic" (포차 플라스틱 의자) | "office" (사무용 메쉬)
-- o.frame / o.seat / o.back = look
function Props.chair(K: any, pcf: CFrame, o: any?)
	local style = pick(o, "style", "diner")
	local top = pick(o, "seatTop", 1.9)
	local w = pick(o, "w", 1.55)
	local d = pick(o, "d", 1.5)
	local backH = pick(o, "backH", 1.85)
	local fr = pick(o, "frame", if style == "bentwood" then Look.walnut elseif style == "diner" then Look.chrome else Look.blackMetal)
	local seatL = pick(o, "seat", if style == "diner" then Look.leatherRed elseif style == "bentwood" then Look.walnut elseif style == "shell" then Look.plywood else Look.fabricGrey)
	local backL = pick(o, "back", seatL)
	local th = 0.26 -- 쿠션 두께
	local hw, hd = w / 2, d / 2
	if style == "plastic" then
		-- 포차 플라스틱 의자: 통짜 좌판 + 넓은 다리 4개 + 구멍 뚫린 등받이 느낌
		local pl = pick(o, "seat", Look.of(214, 40, 40, Enum.Material.Plastic))
		K:slab("ChairSeat", w, d, 0.14, 0.18, pcf * CF(0, top - 0.07, 0), pl)
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local a = pcf * V3(sx * (hw - 0.12), top - 0.12, sz * (hd - 0.12))
				local b = pcf * V3(sx * (hw + 0.05), 0.02, sz * (hd + 0.05))
				K:bar("ChairLeg", a, b, 0.2, 0.12, pl)
			end
		end
		local bz = -hd + 0.06
		K:box("ChairBack", V3(w - 0.1, backH * 0.55, 0.1), pcf * CF(0, top + backH * 0.55, bz) * ANG(math.rad(-8), 0, 0), pl)
		for _, sx in { -1, 1 } do
			K:bar("ChairBackPost", pcf * V3(sx * (hw - 0.14), top, bz), pcf * V3(sx * (hw - 0.14), top + backH * 0.3, bz - 0.03), 0.14, 0.1, pl)
		end
		return
	end
	local detail = (o and o.detail) or K.detail or "high"
	if detail == "low" then
		-- 저사양 / 의자가 아주 많은 매장: 6 파트
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				K:box("ChairLeg", V3(0.1, top - 0.2, 0.1), pcf * CF(sx * (hw - 0.14), (top - 0.2) / 2, sz * (hd - 0.14)), fr)
			end
		end
		K:box("ChairSeat", V3(w, 0.22, d), pcf * CF(0, top - 0.11, 0), seatL)
		K:box("ChairBack", V3(w - 0.1, backH * 0.6, 0.16), pcf * CF(0, top + backH * 0.55, -hd + 0.1) * ANG(math.rad(8), 0, 0), backL)
		return
	end
	-- 다리
	local legD = if style == "bentwood" then 0.16 else 0.1
	local splay = if style == "shell" then 0.12 else 0.05
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local a = pcf * V3(sx * (hw - 0.14), top - th, sz * (hd - 0.14))
			local b = pcf * V3(sx * (hw - 0.14 + splay), 0.05, sz * (hd - 0.14 + splay))
			K:seg("ChairLeg", a, b, legD, fr)
			if detail == "high" then
				K:disc("ChairGlide", legD + 0.04, 0.05, CF(b - V3(0, 0.025, 0)) * pcf.Rotation, Look.rubber)
			end
		end
	end
	-- 다리 사이 가로대 (식당 · 원목)
	if style == "diner" or style == "bentwood" or style == "padded" then
		local y = 0.55
		for _, sx in { -1, 1 } do
			K:seg("ChairRail", pcf * V3(sx * (hw - 0.12), y, -hd + 0.16), pcf * V3(sx * (hw - 0.12), y, hd - 0.16), legD * 0.7, fr)
		end
		K:seg("ChairRail", pcf * V3(-hw + 0.14, y + 0.15, hd - 0.15), pcf * V3(hw - 0.14, y + 0.15, hd - 0.15), legD * 0.7, fr)
	end
	-- 좌판 프레임 + 쿠션 (윗면 = top)
	if style == "shell" or style == "bentwood" then
		K:slab("ChairSeat", w, d, 0.12, 0.3, pcf * CF(0, top - 0.06, 0), seatL)
		K:slab("ChairSeatEdge", w - 0.06, d - 0.06, 0.06, 0.28, pcf * CF(0, top - 0.15, 0), fr)
	else
		K:box("ChairSeatFrame", V3(w - 0.3, 0.08, d - 0.3), pcf * CF(0, top - th - 0.02, 0), fr)
		K:slab("ChairSeat", w, d, th, 0.16, pcf * CF(0, top - th / 2, 0), seatL)
		if detail == "high" then
			-- 쿠션 테두리 바느질선 (살짝 어두운 띠)
			K:slab("ChairPiping", w + 0.02, d + 0.02, 0.03, 0.17, pcf * CF(0, top - th + 0.05, 0), Look.with(seatL, { c = (seatL.c :: Color3):Lerp(Color3.new(0, 0, 0), 0.35) }))
		end
	end
	-- 등받이
	local recline = math.rad(if style == "office" then 12 else 8)
	local bz = -hd + 0.1
	local backCF = pcf * CF(0, top, bz) * ANG(recline, 0, 0)
	if style == "bentwood" then
		-- 원목 곡목 의자: 뒷다리가 올라가 등받이 테 + 세로 살
		for _, sx in { -1, 1 } do
			K:seg("ChairBackPost", pcf * V3(sx * (hw - 0.16), top - 0.1, bz), (backCF * CF(sx * (hw - 0.2), backH, -0.05)).Position, 0.13, fr)
		end
		K:ring("ChairHoop", backCF * CF(0, backH - 0.35, -0.05), hw - 0.2, 0.13, 8, fr, 0, PI)
		for i = -1, 1 do
			K:seg("ChairSpindle", (backCF * CF(i * 0.32, 0.12, -0.02)).Position, (backCF * CF(i * 0.32, backH - 0.1 - math.abs(i) * 0.12, -0.04)).Position, 0.07, fr)
		end
		return
	end
	if style == "shell" then
		K:panel("ChairBack", w - 0.1, backH * 0.6, 0.12, 0.35, backCF * CF(0, backH * 0.62, 0), backL)
		for _, sx in { -1, 1 } do
			K:seg("ChairBackPost", pcf * V3(sx * (hw - 0.22), top - 0.06, bz + 0.05), (backCF * CF(sx * (hw - 0.26), backH * 0.45, 0.08)).Position, 0.08, fr)
		end
		return
	end
	for _, sx in { -1, 1 } do
		K:seg("ChairBackPost", pcf * V3(sx * (hw - 0.14), top - th, bz), (backCF * CF(sx * (hw - 0.14), backH, 0)).Position, legD, fr)
	end
	K:seg("ChairBackRail", (backCF * CF(-hw + 0.14, backH, 0)).Position, (backCF * CF(hw - 0.14, backH, 0)).Position, legD, fr)
	-- 패드 등받이 (앞 = +Z)
	K:panel("ChairBack", w - 0.34, backH * 0.55, 0.22, 0.14, backCF * CF(0, backH * 0.62, 0.02), backL)
	if style == "office" then
		K:disc("ChairBase", 1.4, 0.08, pcf * CF(0, 0.2, 0), fr)
	end
end

-- 스툴. pcf = 바닥, o.seatTop (기본 2.7 바 스툴), o.dia, o.style = "bar" (크롬 기둥 + 발판 링 + 원판 받침) |
-- "wood" (원목 4다리 스툴) | "plastic" (포차 원형 플라스틱 스툴) | "cushion" (가죽 쿠션 + 블랙 다리)
function Props.stool(K: any, pcf: CFrame, o: any?)
	local style = pick(o, "style", "bar")
	local top = pick(o, "seatTop", 2.7)
	local dia = pick(o, "dia", 1.3)
	local fr = pick(o, "frame", if style == "wood" then Look.oak else if style == "bar" then Look.chrome else Look.blackMetal)
	local seatL = pick(o, "seat", if style == "wood" then Look.oak elseif style == "plastic" then Look.of(40, 90, 200, Enum.Material.Plastic) else Look.leatherBlack)
	if style == "plastic" then
		-- 원형 플라스틱 스툴: 위가 좁고 아래가 넓은 통 (원통 3단)
		K:disc("StoolSeat", dia, 0.12, pcf * CF(0, top - 0.06, 0), seatL)
		K:disc("StoolBody", dia * 0.92, top * 0.45, pcf * CF(0, top - 0.12 - top * 0.225, 0), seatL)
		K:disc("StoolSkirt", dia * 1.06, top * 0.42, pcf * CF(0, top * 0.21, 0), seatL)
		K:disc("StoolGrip", dia * 0.3, 0.02, pcf * CF(0, top + 0.005, 0), Look.with(seatL, { c = (seatL.c :: Color3):Lerp(Color3.new(0, 0, 0), 0.4) }))
		return
	end
	if style == "wood" then
		K:disc("StoolSeat", dia, 0.16, pcf * CF(0, top - 0.08, 0), seatL)
		for i = 0, 3 do
			local a = i * PI / 2 + PI / 4
			local r0, r1 = dia * 0.32, dia * 0.44
			K:seg("StoolLeg", pcf * V3(math.cos(a) * r0, top - 0.16, math.sin(a) * r0), pcf * V3(math.cos(a) * r1, 0.03, math.sin(a) * r1), 0.13, fr)
		end
		local ry = top * 0.32
		K:ring("StoolRung", pcf * CF(0, ry, 0) * ANG(PI / 2, 0, 0), dia * 0.4, 0.08, 8, fr)
		return
	end
	-- 바 스툴 / 쿠션 스툴
	K:disc("StoolBase", dia * 0.95, 0.08, pcf * CF(0, 0.04, 0), fr)
	K:disc("StoolBaseCap", dia * 0.5, 0.06, pcf * CF(0, 0.1, 0), fr)
	K:vcyl("StoolPost", top - 0.4, 0.2, pcf * CF(0, (top - 0.4) / 2 + 0.06, 0), fr)
	K:ring("StoolFootRing", pcf * CF(0, top * 0.36, 0) * ANG(PI / 2, 0, 0), dia * 0.42, 0.08, 10, fr)
	for i = 0, 2 do
		local a = i * 2 * PI / 3
		K:seg("StoolSpoke", pcf * V3(0, top * 0.36, 0), pcf * V3(math.cos(a) * dia * 0.42, top * 0.36, math.sin(a) * dia * 0.42), 0.06, fr)
	end
	K:disc("StoolSeatPlate", dia * 0.6, 0.08, pcf * CF(0, top - 0.3, 0), fr)
	K:disc("StoolSeat", dia, 0.22, pcf * CF(0, top - 0.11, 0), seatL)
	K:disc("StoolPiping", dia + 0.03, 0.03, pcf * CF(0, top - 0.2, 0), Look.with(seatL, { c = (seatL.c :: Color3):Lerp(Color3.new(0, 0, 0), 0.4) }))
end

-- 테이블 덮어씌우기 (R4/R7): 원래 상판과 같은 윗면 높이 · 같은 XZ 범위. t = V.tables 항목 (Scan.families)
-- o.top (상판 look), o.edge (모서리 띠 look), o.base (다리 look), o.style = "pedestal" | "four" | "trestle" | "steel"
-- o.r (상판 모서리 반지름), o.thick (상판 두께)
function Props.tableOver(K: any, t: any, o: any?)
	local mn, mx = t.min, t.max
	local y = t.y
	local w, l = mx.X - mn.X, mx.Z - mn.Z
	local cx, cz = (mn.X + mx.X) / 2, (mn.Z + mx.Z) / 2
	local topL = pick(o, "top", Look.oak)
	local edgeL = pick(o, "edge", Look.with(topL, { c = (topL.c :: Color3):Lerp(Color3.new(0, 0, 0), 0.25) }))
	local baseL = pick(o, "base", Look.blackMetal)
	local th = pick(o, "thick", 0.14)
	local r = pick(o, "r", 0.12)
	local style = pick(o, "style", if w * l < 7 then "pedestal" else "four")
	local c = CF(cx, 0, cz)
	K:free(function()
		K:slab("TableTop", w, l, th, r, c * CF(0, y - th / 2, 0), topL)
		K:slab("TableEdge", w - 0.04, l - 0.04, 0.05, r, c * CF(0, y - th - 0.025, 0), edgeL)
		if style == "pedestal" then
			local h = y - th - 0.05
			K:box("TableApron", V3(math.min(w, 1.2), 0.08, math.min(l, 1.2)), c * CF(0, h - 0.04, 0), baseL)
			K:vcyl("TableColumn", h - 0.12, 0.26, c * CF(0, (h - 0.12) / 2 + 0.08, 0), baseL)
			local fw = math.min(w, l) * 0.78
			K:box("TableFoot", V3(fw, 0.08, 0.3), c * CF(0, 0.05, 0), baseL)
			K:box("TableFoot", V3(0.3, 0.08, fw), c * CF(0, 0.05, 0), baseL)
			for _, sx in { -1, 1 } do
				K:disc("TableGlide", 0.18, 0.04, c * CF(sx * fw / 2 - sx * 0.08, 0.02, 0), Look.rubber)
				K:disc("TableGlide", 0.18, 0.04, c * CF(0, 0.02, sx * fw / 2 - sx * 0.08), Look.rubber)
			end
		elseif style == "trestle" then
			local h = y - th
			for _, sx in { -1, 1 } do
				local x = sx * (w / 2 - 0.45)
				K:box("TableLeg", V3(0.18, h, 0.18), c * CF(x, h / 2, -l / 2 + 0.4), baseL)
				K:box("TableLeg", V3(0.18, h, 0.18), c * CF(x, h / 2, l / 2 - 0.4), baseL)
				K:box("TableFoot", V3(0.24, 0.1, l - 0.5), c * CF(x, 0.05, 0), baseL)
				K:box("TableRail", V3(0.16, 0.14, l - 0.7), c * CF(x, h - 0.1, 0), baseL)
			end
			K:box("TableStretcher", V3(w - 1.0, 0.12, 0.12), c * CF(0, 0.45, 0), baseL)
		else
			-- 네 다리 (+ 앞치마 판)
			local h = y - th
			local leg = if style == "steel" then 0.12 else 0.16
			K:box("TableApron", V3(w - 0.4, 0.22, 0.06), c * CF(0, h - 0.11, -l / 2 + 0.2), baseL)
			K:box("TableApron", V3(w - 0.4, 0.22, 0.06), c * CF(0, h - 0.11, l / 2 - 0.2), baseL)
			K:box("TableApron", V3(0.06, 0.22, l - 0.4), c * CF(-w / 2 + 0.2, h - 0.11, 0), baseL)
			K:box("TableApron", V3(0.06, 0.22, l - 0.4), c * CF(w / 2 - 0.2, h - 0.11, 0), baseL)
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					K:box("TableLeg", V3(leg, h, leg), c * CF(sx * (w / 2 - 0.2), h / 2, sz * (l / 2 - 0.2)), baseL)
				end
			end
		end
	end)
end

-- 계산대(카운터) 덮어씌우기: g = V.counters 항목. 손님 쪽(front) 면에 마감 패널 + 상판 덮개 + 걸레받이 + 상판 아래 LED.
-- o.front = "fluted" (세로 루버) | "tile" | "panel" | "marble" | "wood", o.frontL, o.topL, o.kickL, o.led (Color3 | false)
-- o.face = 손님 쪽 방향 (기본: 입구 쪽 +Z, 옆벽 쪽 카운터는 방 가운데 쪽)
function Props.counterOver(K: any, g: any, o: any?)
	local V = K.V
	local mn, mx = g.min, g.max
	local y = g.y
	local alongX = (mx.X - mn.X) >= (mx.Z - mn.Z)
	local frontStyle = pick(o, "front", "fluted")
	local frontL = pick(o, "frontL", Look.oak)
	local topL = pick(o, "topL", Look.marbleWhite)
	local kickL = pick(o, "kickL", Look.black)
	local led = pick(o, "led", Color3.fromRGB(255, 214, 160))
	K:free(function()
		-- 상판 덮개 (같은 높이 · 범위, 둥근 앞 모서리)
		local top = g.top
		if top then
			local tmn, tmx = top.min, top.max
			local tw, tl = tmx.X - tmn.X, tmx.Z - tmn.Z
			K:slab("CounterTop", tw + 0.04, tl + 0.04, 0.16, 0.06, CF((tmn.X + tmx.X) / 2, y - 0.08 + 0.005, (tmn.Z + tmx.Z) / 2), topL)
		end
		local body = g.body or g.top
		if not body then
			return
		end
		local bmn, bmx = body.min, body.max
		local h = (if g.top then g.top.min.Y else y) - 0.02
		-- 손님 쪽 면
		local faceDir: Vector3 = pick(o, "face", nil)
		if not faceDir then
			if alongX then
				local cz = (bmn.Z + bmx.Z) / 2
				faceDir = if (V.door and V.door.z or V.z1) > cz then V3(0, 0, 1) else V3(0, 0, -1)
			else
				local cx = (bmn.X + bmx.X) / 2
				faceDir = if cx > 0 then V3(-1, 0, 0) else V3(1, 0, 0)
			end
		end
		local len = if alongX then bmx.X - bmn.X else bmx.Z - bmn.Z
		local fc: CFrame -- 앞면 dcf (보는 사람 = 손님)
		if alongX then
			local z = if faceDir.Z > 0 then bmx.Z else bmn.Z
			fc = CFrame.fromMatrix(V3((bmn.X + bmx.X) / 2, 0, z + faceDir.Z * 0.01), V3(faceDir.Z, 0, 0), Vector3.yAxis, faceDir)
		else
			local x = if faceDir.X > 0 then bmx.X else bmn.X
			fc = CFrame.fromMatrix(V3(x + faceDir.X * 0.01, 0, (bmn.Z + bmx.Z) / 2), V3(0, 0, -faceDir.X), Vector3.yAxis, faceDir)
		end
		-- 걸레받이 (안쪽으로 들어간 검은 띠)
		K:plate("CounterKick", len, 0.36, 0.04, fc * CF(0, 0.18, -0.02), kickL)
		local fh = h - 0.36
		if frontStyle == "fluted" then
			local n = math.max(4, math.floor(len / 0.32))
			local pw = len / n
			for i = 1, n do
				local u = -len / 2 + pw * (i - 0.5)
				K:cyl("CounterFlute", fh - 0.04, pw * 0.9, fc * CF(u, 0.36 + fh / 2, 0.02) * ANG(0, 0, PI / 2), frontL)
			end
		elseif frontStyle == "tile" then
			K:plate("CounterFront", len, fh, 0.03, fc * CF(0, 0.36 + fh / 2, 0), frontL)
			local rows = math.max(2, math.floor(fh / 0.5))
			for i = 1, rows - 1 do
				K:plate("CounterGrout", len, 0.03, 0.035, fc * CF(0, 0.36 + fh * i / rows, 0), Look.of(200, 196, 188))
			end
			local cols = math.max(2, math.floor(len / 1.0))
			for i = 1, cols - 1 do
				K:plate("CounterGrout", 0.03, fh, 0.035, fc * CF(-len / 2 + len * i / cols, 0.36 + fh / 2, 0), Look.of(200, 196, 188))
			end
		elseif frontStyle == "marble" then
			K:plate("CounterFront", len, fh, 0.05, fc * CF(0, 0.36 + fh / 2, 0), frontL)
			K:plate("CounterVein", len * 0.7, 0.025, 0.055, fc * CF(-len * 0.1, 0.36 + fh * 0.62, 0) * ANG(0, 0, 0.18), Look.of(160, 156, 150, Enum.Material.Marble))
		else
			-- 패널 (가로 판 3단 + 몰딩)
			K:plate("CounterFront", len, fh, 0.04, fc * CF(0, 0.36 + fh / 2, 0), frontL)
			for i = 1, 2 do
				K:plate("CounterMould", len, 0.05, 0.07, fc * CF(0, 0.36 + fh * i / 3, 0), Look.with(frontL, { c = (frontL.c :: Color3):Lerp(Color3.new(0, 0, 0), 0.2) }))
			end
		end
		if led then
			local strip = K:plate("CounterLED", len - 0.2, 0.05, 0.03, fc * CF(0, h - 0.06, 0.06), Look.neon(led :: Color3))
			K:light(strip, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 6, Brightness = 0.6, Angle = 120, Color = led })
		end
	end)
end

-- 조명 ------------------------------------------------------------------------------------------------

-- 펜던트 조명. top = 천장 붙는 점(로컬), drop = 천장에서 갓 아래까지 길이.
-- o.shade = "dome" | "globe" | "cone" | "drum" | "bulb" | "rattan", o.dia, o.look (갓), o.light (true = 불빛)
function Props.pendant(K: any, top: Vector3, drop: number, o: any?)
	local shade = pick(o, "shade", "dome")
	local dia = pick(o, "dia", 1.3)
	local L = pick(o, "look", Look.blackMetal)
	local glow = pick(o, "glow", Look.lampWarm)
	K:disc("PendantCanopy", 0.5, 0.08, CF(top - V3(0, 0.04, 0)), L)
	local sh = top - V3(0, drop, 0)
	K:seg("PendantCord", top - V3(0, 0.08, 0), sh + V3(0, if shade == "globe" then dia else dia * 0.45, 0), 0.04, Look.black)
	local bulbPart
	if shade == "globe" then
		K:ball("PendantGlobe", dia, CF(sh + V3(0, dia / 2, 0)), pick(o, "look", Look.acrylicWhite))
		bulbPart = K:ball("PendantBulb", dia * 0.35, CF(sh + V3(0, dia / 2, 0)), glow)
	elseif shade == "cone" then
		K:vcyl("PendantCap", 0.2, 0.22, CF(sh + V3(0, dia * 0.5, 0)), L)
		for i = 0, 7 do
			local a = i * PI / 4
			K:seg("PendantCone", sh + V3(math.cos(a) * 0.12, dia * 0.45, math.sin(a) * 0.12), sh + V3(math.cos(a) * dia / 2, 0, math.sin(a) * dia / 2), 0.2, L)
		end
		bulbPart = K:ball("PendantBulb", 0.32, CF(sh + V3(0, 0.12, 0)), glow)
	elseif shade == "drum" then
		K:vcyl("PendantDrum", dia * 0.55, dia, CF(sh + V3(0, dia * 0.275, 0)), L)
		bulbPart = K:disc("PendantDiffuser", dia * 0.92, 0.03, CF(sh + V3(0, 0.02, 0)), glow)
	elseif shade == "bulb" then
		K:vcyl("PendantSocket", 0.3, 0.16, CF(sh + V3(0, 0.45, 0)), Look.brass)
		bulbPart = K:ell("PendantBulb", V3(0.34, 0.46, 0.34), CF(sh + V3(0, 0.2, 0)), glow)
	elseif shade == "rattan" then
		K:ell("PendantRattan", V3(dia, dia * 0.7, dia), CF(sh + V3(0, dia * 0.35, 0)), Look.with(Look.rattan, { t = 0.25 }))
		bulbPart = K:ball("PendantBulb", 0.3, CF(sh + V3(0, dia * 0.3, 0)), glow)
	else
		-- dome (반구 갓: 타원체 + 아래 테두리)
		K:ell("PendantDome", V3(dia, dia * 0.7, dia), CF(sh + V3(0, dia * 0.12, 0)), L)
		K:disc("PendantRim", dia * 0.98, 0.04, CF(sh + V3(0, -0.2, 0)), L)
		bulbPart = K:disc("PendantDiffuser", dia * 0.86, 0.02, CF(sh + V3(0, -0.215, 0)), glow)
	end
	if pick(o, "light", false) and bulbPart then
		K:light(bulbPart, "PointLight", { Range = pick(o, "range", 12), Brightness = pick(o, "bright", 0.7), Color = pick(o, "color", Look.warmLight) })
	end
	return bulbPart
end

-- 매입 다운라이트 (천장 아래면 y = V.H 에 붙음). p = 로컬 (x, ?, z)
function Props.downlight(K: any, x: number, z: number, o: any?)
	local y = K.V.H
	local d = pick(o, "dia", 0.7)
	K:free(function()
		K:disc("DownlightTrim", d, 0.04, CF(x, y - 0.02, z), Look.white)
		local lens = K:disc("DownlightLens", d * 0.72, 0.03, CF(x, y - 0.035, z), pick(o, "glow", Look.lampNeutral))
		if pick(o, "light", false) then
			K:light(lens, "SpotLight", { Face = Enum.NormalId.Bottom, Range = pick(o, "range", 14), Brightness = pick(o, "bright", 0.9), Angle = 80, Color = pick(o, "color", Look.neutralLight) })
		end
	end)
end

-- 레일 조명: 천장 아래 a -> b (로컬 xz) 레일 + n 개 스포트
function Props.trackLight(K: any, a: Vector3, b: Vector3, n: number, o: any?)
	local y = K.V.H
	local L = pick(o, "look", Look.blackMetal)
	K:free(function()
		local pa, pb = V3(a.X, y - 0.06, a.Z), V3(b.X, y - 0.06, b.Z)
		K:bar("TrackRail", pa, pb, 0.16, 0.12, L)
		for i = 1, n do
			local p = pa:Lerp(pb, (i - 0.5) / n)
			K:vcyl("TrackStem", 0.3, 0.06, CF(p - V3(0, 0.2, 0)), L)
			local aim = pick(o, "aim", V3(0, -1, 0.6)).Unit
			local hcf = CFrame.lookAt(p - V3(0, 0.45, 0), p - V3(0, 0.45, 0) + aim)
			K:cyl("TrackHead", 0.55, 0.32, hcf * CF(0, 0, -0.1) * ANG(0, PI / 2, 0), L)
			K:disc("TrackLens", 0.26, 0.02, hcf * CF(0, 0, -0.38) * ANG(PI / 2, 0, 0), pick(o, "glow", Look.lampWarm))
		end
	end)
end

-- 간접 조명 LED 띠 (두 점 사이, 빛나는 얇은 막대)
function Props.ledStrip(K: any, a: Vector3, b: Vector3, c: Color3?, o: any?)
	local p = K:bar("LEDStrip", a, b, pick(o, "w", 0.06), pick(o, "h", 0.05), Look.neon(c or Color3.fromRGB(255, 214, 160)))
	if pick(o, "light", false) and p then
		K:light(p, "SurfaceLight", { Face = pick(o, "face", Enum.NormalId.Bottom), Range = pick(o, "range", 8), Brightness = pick(o, "bright", 0.5), Angle = 140, Color = c or Look.warmLight })
	end
	return p
end

-- 천장 마감: 600각 텍스 그리드 (T-bar) + 판 + (선택) 매입 평판 조명. 맵 천장 바로 아래 0.03 (R5)
function Props.ceilingGrid(K: any, o: any?)
	local V = K.V
	local y = V.H - 0.03
	local tile = pick(o, "tile", 2.0)
	local L = pick(o, "bar", Look.of(236, 236, 232))
	K:free(function()
		K:box("CeilingSkin", V3(V.W - 0.05, 0.02, V.D - 0.05), CF((V.x0 + V.x1) / 2, y, (V.z0 + V.z1) / 2), pick(o, "skin", Look.ceilingTex))
		local nx = math.floor(V.W / tile)
		for i = 1, nx do
			local x = V.x0 + (V.W - nx * tile) / 2 + i * tile - tile
			if x > V.x0 + 0.2 and x < V.x1 - 0.2 then
				K:box("CeilingTBar", V3(0.06, 0.04, V.D - 0.06), CF(x, y - 0.02, (V.z0 + V.z1) / 2), L)
			end
		end
		local nz = math.floor(V.D / tile)
		for i = 1, nz do
			local z = V.z0 + (V.D - nz * tile) / 2 + i * tile - tile
			if z > V.z0 + 0.2 and z < V.z1 - 0.2 then
				K:box("CeilingTBar", V3(V.W - 0.06, 0.04, 0.06), CF((V.x0 + V.x1) / 2, y - 0.02, z), L)
			end
		end
	end)
end

-- 평판 LED 조명 (텍스 한 칸 크기) at 로컬 x, z
function Props.panelLight(K: any, x: number, z: number, o: any?)
	local y = K.V.H - 0.05
	local s = pick(o, "size", 1.9)
	K:free(function()
		K:box("PanelLightFrame", V3(s, 0.05, s), CF(x, y, z), Look.white)
		local d = K:box("PanelLight", V3(s - 0.16, 0.03, s - 0.16), CF(x, y - 0.03, z), pick(o, "glow", Look.lampCool))
		if pick(o, "light", false) then
			K:light(d, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = pick(o, "range", 16), Brightness = pick(o, "bright", 0.8), Angle = 150, Color = pick(o, "color", Look.coolLight) })
		end
	end)
end

-- 천장 설비: 스프링클러 · 화재감지기 · CCTV 돔
function Props.sprinkler(K: any, x: number, z: number)
	local y = K.V.H
	K:free(function()
		K:disc("SprinklerRose", 0.3, 0.03, CF(x, y - 0.015, z), Look.white)
		K:vcyl("SprinklerBody", 0.16, 0.08, CF(x, y - 0.1, z), Look.brass)
		K:disc("SprinklerDeflector", 0.2, 0.02, CF(x, y - 0.19, z), Look.brass)
	end)
end
function Props.smokeDetector(K: any, x: number, z: number)
	local y = K.V.H
	K:free(function()
		K:disc("SmokeDetector", 0.55, 0.14, CF(x, y - 0.07, z), Look.white)
		K:disc("SmokeDetectorLED", 0.06, 0.02, CF(x + 0.16, y - 0.15, z), Look.ledRed)
	end)
end
function Props.cctv(K: any, x: number, z: number)
	local y = K.V.H
	K:free(function()
		K:disc("CCTVBase", 0.62, 0.06, CF(x, y - 0.03, z), Look.white)
		K:ell("CCTVDome", V3(0.5, 0.5, 0.5), CF(x, y - 0.06, z), Look.with(Look.glassDark, { t = 0.15 }))
	end)
end

-- 벽 부착물 ----------------------------------------------------------------------------------------

-- 액자 / 포스터. dcf 표면, w x h. o.art = { {색, x, y, w, h}, ... } (액자 안 0..1 좌표 색 블록) | nil,
-- o.text (포스터 글자) / o.fg / o.bg, o.frame (look), o.mat (매트 색 look), o.depth
function Props.frame(K: any, dcf: CFrame, w: number, h: number, o: any?)
	local fr = pick(o, "frame", Look.blackMetal)
	local dep = pick(o, "depth", 0.08)
	local b = pick(o, "border", 0.08)
	K:plate("FrameBack", w, h, dep * 0.6, dcf, pick(o, "mat", Look.paper))
	K:plate("FrameTop", w, b, dep, dcf * CF(0, h / 2 - b / 2, 0), fr)
	K:plate("FrameBottom", w, b, dep, dcf * CF(0, -h / 2 + b / 2, 0), fr)
	K:plate("FrameSide", b, h - 2 * b, dep, dcf * CF(-w / 2 + b / 2, 0, 0), fr)
	K:plate("FrameSide", b, h - 2 * b, dep, dcf * CF(w / 2 - b / 2, 0, 0), fr)
	local iw, ih = w - 2 * b - 0.12, h - 2 * b - 0.12
	local art = pick(o, "art", nil)
	if art then
		for _, a in art do
			local c: Color3 = a[1]
			K:plate("FrameArt", iw * a[4], ih * a[5], dep * 0.7, dcf * CF(-iw / 2 + iw * (a[2] + a[4] / 2), -ih / 2 + ih * (a[3] + a[5] / 2), 0.002), { c = c, m = Enum.Material.SmoothPlastic })
		end
	end
	local txt = pick(o, "text", nil)
	if txt then
		K:text("FrameText", iw, ih * pick(o, "textH", 1), dcf * CF(0, pick(o, "textY", 0), dep * 0.7 + 0.004), txt, { fg = pick(o, "fg", Color3.fromRGB(30, 30, 30)), bg = pick(o, "bg", nil), font = pick(o, "font", Enum.Font.GothamBold) })
	end
	-- 유리 반사
	K:plate("FrameGlass", w - 2 * b, h - 2 * b, 0.01, dcf * CF(0, 0, dep * 0.75), { c = Color3.fromRGB(230, 236, 240), m = Enum.Material.Glass, t = 0.88, r = 0.2 })
end

-- 메뉴판 (라이트 박스). items = { { "아메리카노", "2,000" }, ... }, title, o.cols (열 수), o.bg / o.fg / o.accent,
-- o.frame look, o.glow (밝기, 기본 1.1), o.rowH
function Props.menuBoard(K: any, dcf: CFrame, w: number, h: number, title: string?, items: { { string } }, o: any?)
	local bg: Color3 = pick(o, "bg", Color3.fromRGB(26, 26, 28))
	local fg: Color3 = pick(o, "fg", Color3.fromRGB(246, 242, 232))
	local acc: Color3 = pick(o, "accent", Color3.fromRGB(255, 196, 60))
	local glow = pick(o, "glow", 1.1)
	local cols = pick(o, "cols", if #items > 6 then 2 else 1)
	K:plate("MenuBoardFrame", w + 0.16, h + 0.16, 0.14, dcf, pick(o, "frame", Look.blackMetal))
	K:plate("MenuBoardFace", w, h, 0.16, dcf, { c = bg, m = Enum.Material.SmoothPlastic })
	local z = 0.165
	local th = 0
	if title then
		th = math.min(h * 0.22, 0.9)
		K:text("MenuTitle", w * 0.9, th * 0.8, dcf * CF(0, h / 2 - th / 2 - 0.06, z), title, { fg = acc, glow = glow, font = Enum.Font.GothamBlack })
		K:plate("MenuRule", w * 0.9, 0.03, 0.17, dcf * CF(0, h / 2 - th - 0.06, 0), Look.neon(acc))
	end
	local rows = math.ceil(#items / cols)
	local avail = h - th - 0.24
	local rh = math.min(pick(o, "rowH", 0.5), avail / math.max(1, rows))
	local cw = (w - 0.3) / cols
	for i, it in items do
		local col = (i - 1) // rows
		local row = (i - 1) % rows
		local x0 = -w / 2 + 0.15 + col * cw
		local y = h / 2 - th - 0.16 - rh * (row + 0.5)
		K:text("MenuItem", cw * 0.64, rh * 0.72, dcf * CF(x0 + cw * 0.33, y, z), it[1], { fg = fg, glow = glow, align = "Left", font = Enum.Font.GothamMedium })
		if it[2] then
			K:text("MenuPrice", cw * 0.3, rh * 0.66, dcf * CF(x0 + cw * 0.82, y, z), it[2], { fg = acc, glow = glow, align = "Right", font = Enum.Font.GothamBold })
		end
	end
end

-- 벽시계 (아날로그). dcf 중심, dia 지름
function Props.clock(K: any, dcf: CFrame, dia: number?, o: any?)
	local d = dia or 1.4
	local L = pick(o, "frame", Look.blackMetal)
	K:make("Part", "ClockRim", V3(0.12, d, d), dcf * CF(0, 0, 0.06) * ANG(0, PI / 2, 0), L, Enum.PartType.Cylinder)
	K:make("Part", "ClockFace", V3(0.13, d * 0.9, d * 0.9), dcf * CF(0, 0, 0.065) * ANG(0, PI / 2, 0), Look.white, Enum.PartType.Cylinder)
	for i = 0, 11 do
		local a = i * PI / 6
		local r = d * 0.38
		local big = i % 3 == 0
		K:plate("ClockTick", if big then 0.06 else 0.035, if big then 0.16 else 0.09, 0.015, dcf * CF(math.sin(a) * r, math.cos(a) * r, 0.13) * ANG(0, 0, -a), Look.black)
	end
	-- 시침 · 분침 (실제 시각은 Interact/런타임이 돌림: 이름 ClockHour/ClockMinute)
	local hr = K:plate("ClockHour", 0.07, d * 0.24, 0.02, dcf * CF(0, d * 0.1, 0.145), Look.black)
	local mn = K:plate("ClockMinute", 0.045, d * 0.36, 0.02, dcf * CF(0, d * 0.16, 0.165), Look.black)
	K:disc("ClockPin", 0.08, 0.04, dcf * CF(0, 0, 0.18) * ANG(PI / 2, 0, 0), Look.ledRed)
	return hr, mn
end

-- 벽걸이 TV. dcf 중심, w 화면 폭 (16:9). o.text (화면 글자), o.screen (화면 색), o.on (켜짐)
function Props.tv(K: any, dcf: CFrame, w: number, o: any?)
	local h = w * 9 / 16
	K:plate("TVMount", w * 0.3, h * 0.35, 0.12, dcf, Look.blackMetal)
	K:plate("TVBody", w + 0.1, h + 0.1, 0.12, dcf * CF(0, 0, 0.12), Look.black)
	local on = pick(o, "on", true)
	local scr = K:plate("TVScreen", w, h, 0.02, dcf * CF(0, 0, 0.24), if on then { c = pick(o, "screen", Color3.fromRGB(40, 90, 150)), m = Enum.Material.Neon, t = 0.05 } else Look.screen())
	if on and pick(o, "text", nil) then
		K:text("TVText", w * 0.9, h * 0.5, dcf * CF(0, -h * 0.1, 0.265), pick(o, "text", ""), { fg = Color3.fromRGB(255, 255, 255), glow = 1.2 })
	end
	K:plate("TVLogo", 0.2, 0.04, 0.01, dcf * CF(0, -h / 2 - 0.02, 0.245), Look.chrome)
	return scr
end

-- 벽 선반 + 까치발. dcf = 선반 뒤쪽 가운데 (벽 표면), w 폭, o.depth, o.look, o.bracket
-- 반환: 선반 윗면 위 물건 놓을 dcf (선반 가운데 앞쪽 = 보는 쪽)
function Props.shelf(K: any, dcf: CFrame, w: number, o: any?): CFrame
	local dep = pick(o, "depth", 0.8)
	local L = pick(o, "look", Look.oak)
	local br = pick(o, "bracket", Look.blackMetal)
	local th = pick(o, "thick", 0.14)
	K:box("WallShelf", V3(w, th, dep), dcf * CF(0, 0, dep / 2), L)
	for _, sx in { -1, 1 } do
		local x = sx * (w / 2 - math.min(0.6, w * 0.15))
		K:box("ShelfBracket", V3(0.06, 0.5, 0.05), dcf * CF(x, -0.3, 0.025), br)
		K:bar("ShelfBracket", (dcf * CF(x, -0.5, 0.03)).Position, (dcf * CF(x, -th / 2, dep * 0.75)).Position, 0.06, 0.06, br)
	end
	return dcf * CF(0, th / 2, dep / 2)
end

-- 선반 위 물건 줄: at = 선반 윗면 dcf (shelf 반환값), w 폭, kind = "bottles" | "jars" | "books" | "cups" | "cans" | "boxes" | "plants"
-- o.colors = { Color3 ... }, o.n, o.seed
function Props.row(K: any, at: CFrame, w: number, kind: string, o: any?)
	local cols: { Color3 } = pick(o, "colors", { Color3.fromRGB(90, 60, 40), Color3.fromRGB(40, 90, 60), Color3.fromRGB(150, 40, 40), Color3.fromRGB(220, 200, 150) })
	local seed = pick(o, "seed", 7)
	local function rnd(i: number): number
		local s = math.sin(i * 12.9898 + seed * 78.233) * 43758.5453
		return s - math.floor(s)
	end
	local gap = if kind == "books" then 0.2 elseif kind == "cans" then 0.36 elseif kind == "boxes" then 0.7 else 0.5
	local n = pick(o, "n", math.max(1, math.floor((w - 0.2) / gap)))
	local step = (w - 0.2) / n
	for i = 1, n do
		local x = -w / 2 + 0.1 + step * (i - 0.5)
		local c = cols[(i + seed) % #cols + 1]
		local r = rnd(i)
		local base = at * CF(x, 0, 0)
		if kind == "bottles" then
			local h = 0.9 + r * 0.35
			local bl = { c = c, m = Enum.Material.Glass, t = 0.25, r = 0.1 }
			K:vcyl("Bottle", h * 0.62, 0.3, base * CF(0, h * 0.31, 0), bl)
			K:vcyl("BottleNeck", h * 0.3, 0.12, base * CF(0, h * 0.62 + h * 0.15, 0), bl)
			K:vcyl("BottleCap", 0.06, 0.13, base * CF(0, h * 0.95, 0), Look.goldMetal)
			K:plate("BottleLabel", 0.22, 0.2, 0.01, base * CF(0, h * 0.3, 0.15), Look.of(240, 232, 214))
		elseif kind == "jars" then
			local h = 0.55 + r * 0.25
			K:vcyl("Jar", h, 0.42, base * CF(0, h / 2, 0), { c = Color3.fromRGB(230, 236, 236), m = Enum.Material.Glass, t = 0.45 })
			K:vcyl("JarFill", h * 0.7, 0.36, base * CF(0, h * 0.36, 0), { c = c, m = Enum.Material.SmoothPlastic })
			K:vcyl("JarLid", 0.08, 0.44, base * CF(0, h + 0.04, 0), Look.walnut)
		elseif kind == "books" then
			local h = 0.7 + r * 0.3
			K:box("Book", V3(0.16, h, 0.55), base * CF(0, h / 2, 0) * ANG(0, 0, (r - 0.5) * 0.08), { c = c, m = Enum.Material.SmoothPlastic })
		elseif kind == "cups" then
			K:vcyl("Cup", 0.34, 0.3, base * CF(0, 0.17, 0), { c = c, m = Enum.Material.SmoothPlastic })
			K:vcyl("CupInner", 0.02, 0.24, base * CF(0, 0.34, 0), Look.of(60, 40, 30))
		elseif kind == "cans" then
			K:vcyl("Can", 0.46, 0.26, base * CF(0, 0.23, 0), { c = c, m = Enum.Material.Metal })
			K:vcyl("CanTop", 0.03, 0.22, base * CF(0, 0.475, 0), Look.alu)
		elseif kind == "boxes" then
			local h = 0.5 + r * 0.4
			K:box("Box", V3(0.6, h, 0.5), base * CF(0, h / 2, 0), { c = c, m = Enum.Material.SmoothPlastic })
			K:plate("BoxLabel", 0.4, h * 0.4, 0.01, base * CF(0, h * 0.55, 0.25), Look.of(250, 250, 248))
		elseif kind == "plants" then
			Props.potPlant(K, base, 0.3 + r * 0.1, 0.4 + r * 0.3)
		end
	end
end

-- 작은 화분 (선반 · 카운터 위). pcf, dia 화분 지름, h 잎 높이
function Props.potPlant(K: any, pcf: CFrame, dia: number, h: number, o: any?)
	local pot = pick(o, "pot", Look.white)
	K:vcyl("PotSmall", dia * 0.9, dia, pcf * CF(0, dia * 0.45, 0), pot)
	K:disc("PotSoil", dia * 0.9, 0.02, pcf * CF(0, dia * 0.88, 0), Look.soil)
	local leaf = pick(o, "leaf", Look.leaf)
	for i = 0, 4 do
		local a = i * 2 * PI / 5 + 0.4
		K:ell("PlantLeaf", V3(dia * 0.5, h * 0.55, dia * 0.22), pcf * CF(math.cos(a) * dia * 0.18, dia * 0.9 + h * 0.3, math.sin(a) * dia * 0.18) * ANG(0, -a, math.rad(25)), if i % 2 == 0 then leaf else Look.leafDark)
	end
end

-- 큰 바닥 화분 (몬스테라 · 올리브 · 극락조). pcf 바닥, o.kind = "monstera" | "olive" | "ficus" | "snake" | "bamboo", o.h (전체 높이)
-- 자리 확인을 원하면 먼저 K:spot(pcf, V3(1.8, h, 1.8))
function Props.floorPlant(K: any, pcf: CFrame, o: any?)
	local kind = pick(o, "kind", "monstera")
	local h = pick(o, "h", 5.2)
	local potL = pick(o, "pot", Look.of(232, 228, 220, Enum.Material.Concrete))
	local pd = pick(o, "dia", 1.5)
	local ph = pd * 0.9
	-- 원통형 화분 + 테두리 + 흙 + 바크
	K:vcyl("PlanterPot", ph, pd, pcf * CF(0, ph / 2, 0), potL)
	K:vcyl("PlanterLip", 0.12, pd + 0.06, pcf * CF(0, ph - 0.06, 0), potL)
	K:disc("PlanterSoil", pd - 0.12, 0.04, pcf * CF(0, ph - 0.1, 0), Look.of(98, 70, 50, Enum.Material.Ground))
	local leafL = pick(o, "leaf", Look.leaf)
	if kind == "olive" or kind == "ficus" then
		-- 줄기 + 둥근 잎 뭉치 3단
		local trunkTop = pcf * V3(0, h * 0.62, 0)
		K:seg("PlantTrunk", pcf * V3(0, ph - 0.1, 0), trunkTop, 0.14, Look.of(120, 96, 70, Enum.Material.Wood))
		for i, c in { { 0, h * 0.75, 0, 1.5 }, { 0.5, h * 0.66, 0.3, 1.1 }, { -0.45, h * 0.86, -0.2, 1.2 }, { 0.2, h * 0.95, -0.4, 0.9 } } do
			K:ell("PlantCanopy", V3(c[4] * 1.15, c[4] * 0.85, c[4]), pcf * CF(c[1], c[2], c[3]), if i % 2 == 0 then Look.leafDark else (if kind == "olive" then Look.of(118, 136, 92, Enum.Material.Grass) else leafL))
		end
		return
	end
	if kind == "snake" then
		for i = 0, 8 do
			local a = i * 2 * PI / 9
			local r = 0.18 + (i % 3) * 0.1
			local lh = h * (0.45 + (i % 4) * 0.08)
			K:ell("SnakeLeaf", V3(0.3, lh, 0.08), pcf * CF(math.cos(a) * r, ph + lh / 2 - 0.2, math.sin(a) * r) * ANG(0, -a, math.rad(6)), if i % 2 == 0 then Look.of(54, 96, 60, Enum.Material.Grass) else Look.of(88, 120, 70, Enum.Material.Grass))
		end
		return
	end
	if kind == "bamboo" then
		for i = 0, 4 do
			local a = i * 2 * PI / 5
			local base = pcf * V3(math.cos(a) * 0.3, ph - 0.1, math.sin(a) * 0.3)
			local topP = pcf * V3(math.cos(a) * 0.5, h, math.sin(a) * 0.5)
			K:seg("BambooStem", base, topP, 0.1, Look.of(150, 170, 90, Enum.Material.Wood))
			K:ell("BambooLeaves", V3(0.9, 0.5, 0.9), CF(topP), leafL)
		end
		return
	end
	-- monstera: 갈라진 큰 잎 (타원체 잎 + 줄기) 9장
	for i = 0, 8 do
		local a = i * 2 * PI / 9 + 0.3
		local lean = math.rad(30 + (i % 3) * 14)
		local stemLen = h * (0.38 + (i % 4) * 0.08)
		local s0 = pcf * V3(0, ph - 0.1, 0)
		local dir = V3(math.cos(a) * math.sin(lean), math.cos(lean), math.sin(a) * math.sin(lean))
		local s1 = s0 + dir * stemLen
		K:seg("MonsteraStem", s0, s1, 0.06, Look.of(80, 120, 60, Enum.Material.Grass))
		local leafCF = CFrame.lookAt(s1, s1 + V3(dir.X, -0.35, dir.Z)) * ANG(math.rad(-20), 0, 0)
		K:ell("MonsteraLeaf", V3(1.25, 0.06, 1.5), leafCF * CF(0, 0, -0.55), if i % 3 == 0 then Look.leafDark else leafL)
		K:box("MonsteraSlit", V3(0.06, 0.07, 0.6), leafCF * CF(0.25, 0, -0.75), Look.leafDark)
	end
end

-- 벽 마감 -----------------------------------------------------------------------------------------

-- 걸레받이 (벽 아래 0.4 띠). wall 이름, look. 문 · keep 을 피해 구간마다
function Props.baseboard(K: any, wall: string, look: any?, h: number?)
	local V = K.V
	local bh = h or 0.42
	for _, s in V:spans(wall, 0.05, bh, 0.3) do
		local len = s[2] - s[1]
		K:plate("Baseboard", len, bh, 0.06, V:wall(wall, (s[1] + s[2]) / 2, bh / 2, 0.01), look or Look.white)
	end
end

-- 벽 아래쪽 패널(징두리 · 웨인스코팅): y0..y1, 세로 패널 간격 o.panel, 위 몰딩 o.cap
function Props.wainscot(K: any, wall: string, y1: number, o: any?)
	local V = K.V
	local L = pick(o, "look", Look.offWhite)
	local cap = pick(o, "cap", Look.with(L, { c = (L.c :: Color3):Lerp(Color3.new(0, 0, 0), 0.12) }))
	local pw = pick(o, "panel", 1.6)
	for _, s in V:spans(wall, 0.4, y1, 0.3) do
		local len = s[2] - s[1]
		local mid = (s[1] + s[2]) / 2
		K:plate("Wainscot", len, y1 - 0.4, 0.04, V:wall(wall, mid, 0.4 + (y1 - 0.4) / 2, 0.01), L)
		K:plate("WainscotCap", len, 0.1, 0.1, V:wall(wall, mid, y1, 0.01), cap)
		if pw > 0 then
			local n = math.max(1, math.floor(len / pw))
			local step = len / n
			for i = 1, n do
				local u = s[1] + step * (i - 0.5)
				-- 액자 몰딩 (사각 테두리 4개)
				local iw, ih = step - 0.36, y1 - 1.1
				local c = V:wall(wall, u, 0.4 + (y1 - 0.4) / 2, 0.05)
				K:plate("WainscotMould", iw, 0.05, 0.03, c * CF(0, ih / 2, 0), cap)
				K:plate("WainscotMould", iw, 0.05, 0.03, c * CF(0, -ih / 2, 0), cap)
				K:plate("WainscotMould", 0.05, ih, 0.03, c * CF(-iw / 2, 0, 0), cap)
				K:plate("WainscotMould", 0.05, ih, 0.03, c * CF(iw / 2, 0, 0), cap)
			end
		end
	end
end

-- 벽 타일 (주방 · 화장실 · 분식집): u0..u1, y0..y1, 타일 크기 tw x th, 줄눈 색
function Props.wallTiles(K: any, wall: string, u0: number, u1: number, y0: number, y1: number, o: any?)
	local V = K.V
	local L = pick(o, "look", Look.tileWhite)
	local grout = pick(o, "grout", Look.of(196, 194, 188))
	local tw, th = pick(o, "tw", 1.0), pick(o, "th", 0.5)
	local len, hh = u1 - u0, y1 - y0
	local c = V:wall(wall, (u0 + u1) / 2, (y0 + y1) / 2, 0.01)
	K:plate("WallTile", len, hh, 0.03, c, L)
	local rows = math.floor(hh / th)
	for i = 1, rows do
		K:plate("TileGrout", len, 0.025, 0.035, c * CF(0, -hh / 2 + i * th, 0), grout)
	end
	local cols = math.floor(len / tw)
	for i = 1, cols do
		K:plate("TileGrout", 0.025, hh, 0.035, c * CF(-len / 2 + i * tw, 0, 0), grout)
	end
end

-- 원목 루버 (세로 각재) 벽: u0..u1, y0..y1
function Props.louverWall(K: any, wall: string, u0: number, u1: number, y0: number, y1: number, o: any?)
	local V = K.V
	local L = pick(o, "look", Look.oak)
	local back = pick(o, "back", Look.charcoal)
	local pitch = pick(o, "pitch", 0.45)
	local len, hh = u1 - u0, y1 - y0
	local c = V:wall(wall, (u0 + u1) / 2, (y0 + y1) / 2, 0.01)
	K:plate("LouverBack", len, hh, 0.03, c, back)
	local n = math.floor(len / pitch)
	for i = 0, n - 1 do
		K:plate("LouverSlat", pitch * 0.55, hh, 0.16, c * CF(-len / 2 + pitch * (i + 0.5), 0, 0.03), L)
	end
end

-- 바닥 오버레이 (타일 · 마루 무늬). 맵 바닥 위 0.02 (R5). o.look, o.tile (타일 크기), o.grout
function Props.floorTiles(K: any, o: any?)
	local V = K.V
	local L = pick(o, "look", Look.porcelain)
	local grout = pick(o, "grout", Look.of(150, 146, 140))
	local t = pick(o, "tile", 2.0)
	local cx, cz = (V.x0 + V.x1) / 2, (V.z0 + V.z1) / 2
	K:free(function()
		K:box("FloorSkin", V3(V.W - 0.02, 0.02, V.D - 0.02), CF(cx, 0.01, cz), L)
		if t > 0 then
			for x = V.x0 + t, V.x1 - 0.1, t do
				K:box("FloorGrout", V3(0.04, 0.022, V.D - 0.04), CF(x, 0.012, cz), grout)
			end
			for z = V.z0 + t, V.z1 - 0.1, t do
				K:box("FloorGrout", V3(V.W - 0.04, 0.022, 0.04), CF(cx, 0.012, z), grout)
			end
		end
	end)
end

-- 현관 매트 (자동문 안쪽 바닥, 높이 0.03 이라 keep 상관없음)
function Props.doorMat(K: any, o: any?)
	local V = K.V
	local d = V.door
	if not d then
		return
	end
	K:free(function()
		local w = math.min((d.w or 4) + 0.8, V.W - 1)
		K:box("DoorMat", V3(w, 0.04, 2.4), CF(d.x, 0.02, V.z1 - 1.4), pick(o, "look", Look.of(52, 52, 54, Enum.Material.Fabric)))
		K:box("DoorMatEdge", V3(w + 0.1, 0.035, 2.5), CF(d.x, 0.017, V.z1 - 1.4), Look.rubber)
		if pick(o, "text", nil) then
			K:text("DoorMatText", w * 0.6, 1.2, CFrame.fromMatrix(V3(d.x, 0.05, V.z1 - 1.4), V3(1, 0, 0), V3(0, 0, -1), V3(0, 1, 0)), pick(o, "text", "WELCOME"), { fg = Color3.fromRGB(190, 190, 186), d = 0.01, free = true })
		end
	end)
end

-- 작은 벽 부착물: 스위치 · 콘센트 · 비상벨 · 온도조절기 · 손소독제 · 사업자등록증
function Props.switchPlate(K: any, dcf: CFrame, n: number?): BasePart
	local k = n or 2
	local plate = K:plate("SwitchPlate", 0.3 + 0.2 * k, 0.5, 0.04, dcf, Look.white)
	for i = 1, k do
		K:plate("SwitchRocker", 0.14, 0.3, 0.03, dcf * CF(-0.1 * (k - 1) + 0.2 * (i - 1), 0, 0.04), Look.offWhite)
	end
	return plate
end
function Props.outlet(K: any, dcf: CFrame)
	K:plate("OutletPlate", 0.36, 0.6, 0.04, dcf, Look.white)
	for _, y in { -0.12, 0.12 } do
		K:disc("OutletSocket", 0.2, 0.02, dcf * CF(0, y, 0.05) * ANG(PI / 2, 0, 0), Look.offWhite)
	end
end
function Props.fireBell(K: any, dcf: CFrame)
	-- 소화전 위 빨간 비상벨 + 표시등 (한국 상가 표준)
	K:plate("FireBellBox", 0.9, 0.9, 0.12, dcf, Look.of(196, 30, 30))
	K:disc("FireBellLamp", 0.3, 0.06, dcf * CF(0, 0.2, 0.15) * ANG(PI / 2, 0, 0), Look.ledRed)
	K:disc("FireBellButton", 0.24, 0.05, dcf * CF(0, -0.2, 0.15) * ANG(PI / 2, 0, 0), Look.white)
end
function Props.thermostat(K: any, dcf: CFrame)
	K:plate("ACController", 0.6, 0.6, 0.06, dcf, Look.white)
	K:plate("ACControllerLCD", 0.4, 0.24, 0.02, dcf * CF(0, 0.08, 0.06), Look.of(150, 200, 230, Enum.Material.Neon, { t = 0.2 }))
	K:text("ACTemp", 0.38, 0.2, dcf * CF(0, 0.08, 0.08), "24°C", { fg = Color3.fromRGB(20, 30, 40) })
end
function Props.license(K: any, dcf: CFrame, name: string?)
	Props.frame(K, dcf, 1.2, 1.6, { frame = Look.goldMetal, text = "사업자등록증\n\n" .. (name or "") .. "\n\n국세청", fg = Color3.fromRGB(40, 40, 40), textH = 0.9, border = 0.06, depth = 0.05 })
end

-- 카운터 소품 ---------------------------------------------------------------------------------------
-- 카드 단말기 (pcf = 카운터 윗면)
function Props.cardTerminal(K: any, pcf: CFrame)
	K:box("CardTerminal", V3(0.42, 0.14, 0.7), pcf * CF(0, 0.07, 0) * ANG(math.rad(-12), 0, 0), Look.charcoal)
	K:plate("CardTerminalLCD", 0.3, 0.2, 0.01, CFrame.fromMatrix((pcf * CF(0, 0.15, -0.12)).Position, pcf.XVector, pcf.ZVector, -pcf.YVector) * ANG(PI, 0, 0), Look.of(120, 180, 210, Enum.Material.Neon, { t = 0.25 }))
	for i = 0, 2 do
		for j = 0, 2 do
			K:box("CardTerminalKey", V3(0.07, 0.03, 0.06), pcf * CF(-0.1 + i * 0.1, 0.15, 0.08 + j * 0.08), Look.grey)
		end
	end
end
function Props.receiptPrinter(K: any, pcf: CFrame)
	K:rbox("ReceiptPrinter", V3(0.6, 0.45, 0.7), 0.08, pcf * CF(0, 0.225, 0), Look.charcoal)
	K:box("ReceiptPaper", V3(0.36, 0.02, 0.25), pcf * CF(0, 0.46, -0.2) * ANG(math.rad(-30), 0, 0), Look.paper)
end
function Props.bell(K: any, pcf: CFrame)
	K:disc("CounterBellBase", 0.5, 0.06, pcf * CF(0, 0.03, 0), Look.black)
	K:ell("CounterBell", V3(0.42, 0.34, 0.42), pcf * CF(0, 0.1, 0), Look.chrome)
	K:vcyl("CounterBellButton", 0.06, 0.06, pcf * CF(0, 0.28, 0), Look.chrome)
end
function Props.tipJar(K: any, pcf: CFrame, label: string?)
	K:vcyl("TipJar", 0.6, 0.42, pcf * CF(0, 0.3, 0), { c = Color3.fromRGB(230, 240, 240), m = Enum.Material.Glass, t = 0.5 })
	K:vcyl("TipJarCoins", 0.12, 0.36, pcf * CF(0, 0.08, 0), Look.goldMetal)
	K:text("TipJarLabel", 0.36, 0.16, CFrame.fromMatrix((pcf * CF(0, 0.32, 0.215)).Position, pcf.XVector, pcf.YVector, pcf.ZVector), label or "TIP", { fg = Color3.fromRGB(40, 40, 40), bg = Color3.fromRGB(248, 240, 220), d = 0.01 })
end
function Props.napkinBox(K: any, pcf: CFrame)
	K:box("NapkinBox", V3(0.5, 0.36, 0.34), pcf * CF(0, 0.18, 0), Look.of(240, 238, 232))
	K:box("NapkinTissue", V3(0.2, 0.1, 0.12), pcf * CF(0, 0.4, 0), Look.paper)
end
-- 테이블 호출벨이 아닌 '메뉴 스탠드' (카운터 위 A4 아크릴 꽂이)
function Props.menuStand(K: any, pcf: CFrame, text: string)
	K:box("MenuStandBase", V3(0.6, 0.06, 0.3), pcf * CF(0, 0.03, 0), Look.acrylicWhite)
	local d = CFrame.fromMatrix((pcf * CF(0, 0.5, 0)).Position, pcf.XVector, pcf.YVector, pcf.ZVector) * ANG(math.rad(-10), 0, 0)
	K:text("MenuStand", 0.56, 0.8, d, text, { fg = Color3.fromRGB(30, 30, 30), bg = Color3.fromRGB(252, 250, 244), d = 0.02, wrap = true })
end

-- 네온사인 글자 (벽): 판 없이 글자만 빛남 + 뒤 아크릴 판. dcf, w, h
function Props.neonSign(K: any, dcf: CFrame, w: number, h: number, text: string, c: Color3, o: any?)
	if pick(o, "backer", true) then
		K:plate("NeonBacker", w + 0.3, h + 0.2, 0.05, dcf, { c = Color3.fromRGB(30, 30, 34), m = Enum.Material.Glass, t = 0.55 })
	end
	local p = K:text("NeonText", w, h, dcf * CF(0, 0, 0.07), text, { fg = c, glow = 2.2, font = pick(o, "font", Enum.Font.Arcade) })
	if pick(o, "light", true) then
		K:light(p, "SurfaceLight", { Face = Enum.NormalId.Front, Range = 7, Brightness = 0.9, Angle = 120, Color = c })
	end
	return p
end

-- 음료 쇼케이스 냉장고 (유리문 1~3칸). pcf 바닥, o.doors (칸 수), o.h, o.d, o.items = "bottles" | "cans" | "mixed"
-- 반환: { doors = { 문 Model ... } } (Interact.swingDoor 로 열고 닫기)
function Props.showcaseFridge(K: any, pcf: CFrame, o: any?)
	local nd = pick(o, "doors", 2)
	local dw = pick(o, "doorW", 2.1)
	local w = nd * dw + 0.3
	local h = pick(o, "h", 6.6)
	local d = pick(o, "d", 2.2)
	local body = pick(o, "body", Look.of(36, 38, 42, Enum.Material.Metal))
	local out = { doors = {} }
	K:box("FridgeBody", V3(w, h, d), pcf * CF(0, h / 2, -0.05), body)
	-- 상단 광고판 (브랜드 띠)
	K:text("FridgeHeader", w - 0.1, 0.55, pcf * CF(0, h - 0.33, d / 2 - 0.04), pick(o, "header", "COLD DRINKS"), { fg = Color3.fromRGB(255, 255, 255), bg = pick(o, "headerBg", Color3.fromRGB(196, 28, 36)), glow = 1.3 })
	-- 안쪽 (밝은 흰 내부 + 선반 + 음료)
	local innerH = h - 1.2
	K:box("FridgeInner", V3(w - 0.3, innerH, 0.05), pcf * CF(0, 0.55 + innerH / 2, -d / 2 + 0.25), Look.white)
	local glowP = K:box("FridgeLamp", V3(w - 0.4, 0.06, 0.1), pcf * CF(0, 0.55 + innerH - 0.08, d / 2 - 0.35), Look.lampCool)
	K:light(glowP, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 6, Brightness = 0.8, Angle = 130, Color = Look.coolLight })
	local shelves = pick(o, "shelves", 5)
	local colorsB = { Color3.fromRGB(196, 30, 40), Color3.fromRGB(40, 120, 60), Color3.fromRGB(250, 200, 40), Color3.fromRGB(30, 70, 160), Color3.fromRGB(230, 120, 30), Color3.fromRGB(240, 240, 240) }
	for i = 1, shelves do
		local y = 0.55 + (i - 1) * innerH / shelves + 0.05
		K:box("FridgeShelf", V3(w - 0.4, 0.05, d - 0.6), pcf * CF(0, y, -0.05), Look.of(200, 204, 208, Enum.Material.Metal))
		local at = pcf * CF(0, y + 0.025, d / 2 - 0.55)
		local kind = pick(o, "items", "mixed")
		if kind == "mixed" then
			kind = if i % 2 == 0 then "cans" else "bottles"
		end
		Props.row(K, at, w - 0.5, kind, { colors = colorsB, seed = i * 3 })
	end
	-- 문 (프레임 + 유리 + 손잡이) — 각 문은 Model "FridgeDoor_i" (경첩 = 왼쪽 끝)
	for i = 1, nd do
		local x0 = -w / 2 + 0.15 + (i - 1) * dw
		local m = K:group("FridgeDoor_" .. i, function()
			local c = pcf * CF(x0 + dw / 2, 0.55 + innerH / 2, d / 2 + 0.03)
			K:box("FridgeDoorFrame", V3(dw, innerH + 0.2, 0.1), c * CF(0, 0, 0), Look.of(30, 30, 32, Enum.Material.Metal))
			K:box("FridgeDoorGlass", V3(dw - 0.24, innerH - 0.05, 0.04), c * CF(0, 0, 0.04), { c = Color3.fromRGB(210, 230, 236), m = Enum.Material.Glass, t = 0.72, r = 0.12 })
			K:box("FridgeDoorHandle", V3(0.08, innerH * 0.6, 0.1), c * CF(dw / 2 - 0.2, 0, 0.12), Look.chrome)
		end)
		m:SetAttribute("Hinge", (K.cf * pcf * CF(x0, 0, d / 2 + 0.03)).Position)
		table.insert(out.doors, m)
	end
	K:box("FridgeKick", V3(w, 0.5, 0.1), pcf * CF(0, 0.25, d / 2 - 0.02), Look.of(40, 40, 42, Enum.Material.Metal))
	K:plate("FridgeVent", w * 0.6, 0.3, 0.02, CFrame.fromMatrix((pcf * CF(0, 0.25, d / 2 + 0.03)).Position, pcf.XVector, pcf.YVector, pcf.ZVector), Look.of(70, 70, 74, Enum.Material.DiamondPlate))
	return out
end

return Props

end

__defs["Scan"] = function()
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
local SEATS = { ChairSeat = true, StoolSeat = true, Stool = true, Cushion = true, SeatCushion = true, StoolTop = true, BarStool = true, SofaSeat = true, WashSeat = true }
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
	V:addKeep(Vector3.new(V.x0 - 1, 3.4, V.z1 - 1.8), Vector3.new(V.x1 + 1, H, V.z1 + 0.5), "window")
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

end

__defs["T_arcade"] = function()
-- GwangalliBuildingInterior/T_arcade: 큰 시설 방 유형 (arcade stairlobby photo bowarcade) 실내 (Venues.luau 의 방, Scan.fitRoom).
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (Common.luau 머리말의 S 필드)
--   build(K, V, S) 유형별 디테일

local Look = __require("Look")
local Props = __require("Props")
local Interact = __require("Interact")
local Common = __require("Common")

local T = {}
T.types = { "arcade", "stairlobby", "photo", "bowarcade" }

function T.style(V: any): any
	-- 기본: 기존 가구는 그대로, 천장 설비만 (모듈을 채우면서 바꿈)
	return { chair = false, stool = false, table = false, counter = false, base = false, lower = false, mat = false, clock = false, license = false, cctv = false, ceiling = {}, lights = { kind = "none" }, skip = { upgrades = true, fixtures = true } }
end

function T.build(K: any, V: any, S: any) end

return T

end

__defs["T_billiards"] = function()
-- GwangalliBuildingInterior/T_billiards: 큰 시설 방 유형 (billiards) 실내 (Venues.luau 의 방, Scan.fitRoom).
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (Common.luau 머리말의 S 필드)
--   build(K, V, S) 유형별 디테일

local Look = __require("Look")
local Props = __require("Props")
local Interact = __require("Interact")
local Common = __require("Common")

local T = {}
T.types = { "billiards" }

function T.style(V: any): any
	-- 기본: 기존 가구는 그대로, 천장 설비만 (모듈을 채우면서 바꿈)
	return { chair = false, stool = false, table = false, counter = false, base = false, lower = false, mat = false, clock = false, license = false, cctv = false, ceiling = {}, lights = { kind = "none" }, skip = { upgrades = true, fixtures = true } }
end

function T.build(K: any, V: any, S: any) end

return T

end

__defs["T_bowling"] = function()
-- GwangalliBuildingInterior/T_bowling: 큰 시설 방 유형 (bowlobby bowlounge bowbar bowsnack) 실내 (Venues.luau 의 방, Scan.fitRoom).
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (Common.luau 머리말의 S 필드)
--   build(K, V, S) 유형별 디테일

local Look = __require("Look")
local Props = __require("Props")
local Interact = __require("Interact")
local Common = __require("Common")

local T = {}
T.types = { "bowlobby", "bowlounge", "bowbar", "bowsnack" }

function T.style(V: any): any
	-- 기본: 기존 가구는 그대로, 천장 설비만 (모듈을 채우면서 바꿈)
	return { chair = false, stool = false, table = false, counter = false, base = false, lower = false, mat = false, clock = false, license = false, cctv = false, ceiling = {}, lights = { kind = "none" }, skip = { upgrades = true, fixtures = true } }
end

function T.build(K: any, V: any, S: any) end

return T

end

__defs["T_cafe"] = function()
-- GwangalliBuildingInterior/T_cafe: 유형 (cafe bakery dessert) 실내.
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (Common.luau 머리말의 S 필드) + S.brand (아래 B)
--   build(K, V, S) 유형별 디테일 (메뉴판 · 진열 · 장비 · 간판 · 소품 · 상호작용)
--
-- 브랜드 B (이름 · 메뉴 · 맵 내용물로 고름): 메가 · 컴포즈 · 투썸 · 파스쿠찌 · 스타벅스 · 로스터리 · 오뜨 · 051 · 라운지 ·
--   인디 5종 (scandi / terracotta / concrete / ocean / green, 매장 이름 해시로) · 베이커리 · 와플/젤라또 · 탕후루 ·
--   빙수 · 인형뽑기(BINGBING) · 츄러스 · 호떡. 가격은 2026 부산 기준.
-- 짓는 순서 (각 단계 pcall):
--   1) 맵 간판 · 표시물 자리 등록 (V:spans 는 Sign_* 쉘을 안 보므로 K.wallUsed 에 넣음)
--   2) 큰 바닥 소품 (로스터 · 오븐 · 셀프바 · 냉장 쇼케이스 · MD 선반 · 아일랜드 진열대 · 화분) — K:spot + 벽 사용 기록
--   3) 카운터 위 / 뒤 장비 (카드단말기 · 진동벨 · 메뉴 스탠드 · 블렌더 · 시럽 · 컵 디스펜서 · 제빙기 패널 ...)
--   4) 맵의 엉성한 장식 다시 만들기 (Jar · Pastry · Bread · Cup · Plush 숨기고 같은 자리에) + 게임플레이 장비는
--      같은 자세 오버레이 (GelatoTub · WaffleIron) 또는 0.02 바깥 스킨 (EspressoBody · Grinder · CaseBase)
--   5) 뒷벽 메뉴판 (라이트박스 / 칠판 / 펠트 레터보드 / 브라스) + 로고 + 프로모 띠
--   6) 옆벽: 액자 · 네온(켜기/끄기) · 안내문 (와이파이 · 영업시간 · 카드결제 · 원산지 · 위생등급) · 선반 · 스피커(BGM 바꾸기) · TV
--   7) 천장: 덕트 · 레일 조명 · 픽업 전광판 · 행잉 화분 · LED 띠
-- 스타벅스 광안리점: 바리스타 잡 시스템 → 카운터 위 · 카운터 리스킨 · 커피 머신 스킨은 하지 않음.

local Look = __require("Look")
local Props = __require("Props")
local Interact = __require("Interact")
local Common = __require("Common")
local Scan = __require("Scan")
local Kit = __require("Kit")

local T = {}
T.types = { "cafe", "bakery", "dessert" }

local CF, V3 = CFrame.new, Vector3.new
local ANG = CFrame.Angles
local PI = math.pi
local M = Enum.Material
local F = Enum.Font
local rgb = Color3.fromRGB
local BLACK, WHITE = Color3.new(0, 0, 0), Color3.new(1, 1, 1)

-- 작은 도구 ------------------------------------------------------------------------------------------
local function hashStr(s: string): number
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 1000003
	end
	return h
end

-- 0..1 의사난수
local function rnd(seed: number, i: number): number
	local s = math.sin((seed % 9973) * 0.731 + i * 12.9898) * 43758.5453
	return s - math.floor(s)
end

local function dk(c: Color3, f: number): Color3
	return c:Lerp(BLACK, f)
end
local function lt(c: Color3, f: number): Color3
	return c:Lerp(WHITE, f)
end
local function lk(c: Color3, m: Enum.Material?, extra: { [string]: any }?): { [string]: any }
	local t: { [string]: any } = { c = c, m = m or M.SmoothPlastic }
	if extra then
		for k, v in extra do
			t[k] = v
		end
	end
	return t
end
local function glassL(c: Color3?, t: number?): { [string]: any }
	return { c = c or rgb(226, 236, 238), m = M.Glass, t = t or 0.55, r = 0.12 }
end

-- 표시면 프레임 (점 p, 바깥 법선 n)
local function faceCF(p: Vector3, n: Vector3): CFrame
	local x = Vector3.yAxis:Cross(n).Unit
	return CFrame.fromMatrix(p, x, Vector3.yAxis, n)
end
-- 소품 프레임: 원점 p, +Z = n
local function facing(p: Vector3, n: Vector3): CFrame
	return CFrame.lookAt(p, p - n)
end
-- 벽(표시면)에 붙는 원판: 축 = dcf Z
local function wdisc(K: any, name: string, dia: number, t: number, dcf: CFrame, look: any): BasePart
	return K:disc(name, dia, t, dcf * CF(0, 0, t / 2) * ANG(PI / 2, 0, 0), look)
end
-- 위를 보는 글자판 (카운터 위 스티커 · 바닥 표시): p 중심, 글자 위쪽 = up (수평 벡터)
local function topCF(p: Vector3, up: Vector3): CFrame
	local x = up:Cross(Vector3.yAxis).Unit
	return CFrame.fromMatrix(p, x, up, Vector3.yAxis)
end

local function hi(K: any): boolean
	return K.detail == "high"
end
local function lowD(K: any): boolean
	return K.detail == "low"
end

-- 자리 관리 ---------------------------------------------------------------------------------------------
local function useWall(K: any, wn: string, a: number, b: number, y0: number, y1: number)
	K.wallUsed = K.wallUsed or {}
	table.insert(K.wallUsed, { w = wn, a = a, b = b, y0 = y0, y1 = y1 })
end

local function wallBlocked(K: any, wn: string, a: number, b: number, y0: number, y1: number): boolean
	for _, u in K.wallUsed or {} do
		if u.w == wn and u.y1 > y0 and u.y0 < y1 and u.b > a and u.a < b then
			return true
		end
	end
	return false
end

-- 벽면 빈 구간 (V:spans 에서 K.wallUsed 빼기)
local function freeSpans(K: any, wn: string, y0: number, y1: number, depth: number?): { { number } }
	local V = K.V
	local out = {}
	for _, s in V:spans(wn, y0, y1, depth or 1.0) do
		local segs = { { s[1], s[2] } }
		for _, u in K.wallUsed or {} do
			if u.w == wn and u.y1 > y0 and u.y0 < y1 then
				local nxt = {}
				for _, g in segs do
					if u.b <= g[1] or u.a >= g[2] then
						table.insert(nxt, g)
					else
						if u.a > g[1] then
							table.insert(nxt, { g[1], u.a })
						end
						if u.b < g[2] then
							table.insert(nxt, { u.b, g[2] })
						end
					end
				end
				segs = nxt
			end
		end
		for _, g in segs do
			if g[2] - g[1] > 0.3 then
				table.insert(out, g)
			end
		end
	end
	return out
end

-- 벽에 w 폭, y0..y1 높이 자리 찾기. pred(dcf, wn, u) 로 추가 조건 (프롬프트 거리 등). 반환 wn, dcf(가운데), u
local function wallFind(K: any, walls: { string }, w: number, y0: number, y1: number, prefer: any?, pred: any?, depth: number?): (string?, CFrame?, number?)
	local V = K.V
	for _, wn in walls do
		local pu = 0
		if type(prefer) == "number" then
			pu = prefer
		elseif type(prefer) == "table" and prefer[wn] then
			pu = prefer[wn]
		end
		local cands = {}
		for _, s in freeSpans(K, wn, y0, y1, depth) do
			if s[2] - s[1] >= w then
				local lo, hi2 = s[1] + w / 2, s[2] - w / 2
				table.insert(cands, math.clamp(pu, lo, hi2))
				if pred then
					local u = lo
					while u <= hi2 do
						table.insert(cands, u)
						u += 0.5
					end
				end
			end
		end
		table.sort(cands, function(a, b)
			return math.abs(a - pu) < math.abs(b - pu)
		end)
		for _, cu in cands do
			local dcf = V:wall(wn, cu, (y0 + y1) / 2, 0)
			if not pred or pred(dcf, wn, cu) then
				useWall(K, wn, cu - w / 2 - 0.15, cu + w / 2 + 0.15, y0, y1)
				return wn, dcf, cu
			end
		end
	end
	return nil, nil, nil
end

local function boxHits(list: { any }, mn: Vector3, mx: Vector3): boolean
	for _, r in list do
		if Kit.overlap(mn, mx, r.min, r.max, 0.04) then
			return true
		end
	end
	return false
end

-- K:spot + 벽 부착물 · 천장 매달린 것 · 문짝까지 확인
local function spotX(K: any, pcf: CFrame, size: Vector3, pad: number?, kind: string?): boolean
	local V = K.V
	local p = pad or 0
	local mn, mx = Kit.laabb(pcf * CF(0, size.Y / 2, 0), size + V3(2 * p, 0, 2 * p))
	if boxHits(V.wallItems, mn, mx) or boxHits(V.hang, mn, mx) then
		return false
	end
	for _, r in V.parts do
		if r.door and Kit.overlap(mn, mx, r.min, r.max, 0.04) then
			return false
		end
	end
	return K:spot(pcf, size, pad, kind)
end

-- 벽에 붙여 세우는 바닥 소품 자리: 폭 w (벽 방향) · 깊이 d · 높이 h. 반환 wn, pcf (+Z = 방 안쪽), u
local function floorFind(K: any, walls: { string }, w: number, d: number, h: number, prefer: any?, opts: any?): (string?, CFrame?, number?)
	local V = K.V
	local o: any = opts or {}
	for _, wn in walls do
		local wall = V.walls[wn]
		if wall then
			local pu = 0
			if type(prefer) == "number" then
				pu = prefer
			elseif type(prefer) == "table" and prefer[wn] then
				pu = prefer[wn]
			end
			local cands = {}
			local u = wall.a + w / 2 + 0.15
			while u <= wall.b - w / 2 - 0.15 do
				table.insert(cands, u)
				u += 0.5
			end
			table.sort(cands, function(a, b)
				return math.abs(a - pu) < math.abs(b - pu)
			end)
			for _, cu in cands do
				if not wallBlocked(K, wn, cu - w / 2, cu + w / 2, 0, h) then
					local pcf = V:wall(wn, cu, 0, d / 2 + 0.06)
					if (not o.pred or o.pred(pcf, wn, cu)) and spotX(K, pcf, V3(w, h, d), o.pad or 0.08, o.kind) then
						useWall(K, wn, cu - w / 2 - 0.1, cu + w / 2 + 0.1, 0, h + 0.25)
						return wn, pcf, cu
					end
				end
			end
		end
	end
	return nil, nil, nil
end

-- 카운터 손님 쪽 방향 (Props.counterOver 와 같은 규칙)
local function custDir(V: any, g: any): Vector3
	local alongX = (g.max.X - g.min.X) >= (g.max.Z - g.min.Z)
	if alongX then
		local cz = (g.min.Z + g.max.Z) / 2
		return if (V.door and V.door.z or V.z1) > cz then V3(0, 0, 1) else V3(0, 0, -1)
	else
		local cx = (g.min.X + g.max.X) / 2
		return if cx > 0 then V3(-1, 0, 0) else V3(1, 0, 0)
	end
end

-- 카운터 윗면 자리: side = "front" (손님 쪽 끝) | "back" (안쪽 끝) | "mid". 반환 pcf (+Z = 손님 쪽) 또는 nil
local function counterSpot(K: any, g: any, w: number, d: number, h: number, side: string, prefer: number?, pad: number?, inset: number?): CFrame?
	local V = K.V
	local n = custDir(V, g)
	local t = g.top or g
	local mn, mx = t.min, t.max
	local y = g.y
	local alongX = math.abs(n.Z) > 0.5
	local ins = inset or 0.14
	local lo, hi2, fixed
	if alongX then
		lo, hi2 = mn.X + w / 2 + 0.12, mx.X - w / 2 - 0.12
		local zf = if n.Z > 0 then mx.Z - d / 2 - ins else mn.Z + d / 2 + ins
		local zb = if n.Z > 0 then mn.Z + d / 2 + ins else mx.Z - d / 2 - ins
		fixed = if side == "back" then zb elseif side == "mid" then (mn.Z + mx.Z) / 2 else zf
	else
		lo, hi2 = mn.Z + w / 2 + 0.12, mx.Z - w / 2 - 0.12
		local xf = if n.X > 0 then mx.X - d / 2 - ins else mn.X + d / 2 + ins
		local xb = if n.X > 0 then mn.X + d / 2 + ins else mx.X - d / 2 - ins
		fixed = if side == "back" then xb elseif side == "mid" then (mn.X + mx.X) / 2 else xf
	end
	if hi2 < lo then
		return nil
	end
	local cands = {}
	local s = lo
	while s <= hi2 + 1e-6 do
		table.insert(cands, s)
		s += 0.2
	end
	local pu = prefer or (lo + hi2) / 2
	table.sort(cands, function(a, b)
		return math.abs(a - pu) < math.abs(b - pu)
	end)
	for _, c in cands do
		local p = if alongX then V3(c, y, fixed) else V3(fixed, y, c)
		local pcf = facing(p, n)
		if spotX(K, pcf, V3(w, h, d), pad or 0.04) then
			return pcf
		end
	end
	return nil
end

-- 프롬프트를 둘 수 있는 벽 자리인가 (서버 앵커 6.5 밖)
local function promptOK(K: any, half: number?): (CFrame, string, number) -> boolean
	local hw = half or 0.8
	return function(dcf: CFrame)
		for _, dx in { -hw, 0, hw } do
			for _, dy in { -0.5, 0.5 } do
				if not Interact.canPrompt(K, dcf.Position + dcf.XVector * dx + dcf.YVector * dy + dcf.ZVector * 0.25) then
					return false
				end
			end
		end
		return true
	end
end

-- 프롬프트 붙일 벽 자리: 여러 높이 띠를 차례로
local function promptSpot(K: any, walls: { string }, w: number, bands: { { number } }, prefer: any?): (string?, CFrame?, number?)
	local pred = promptOK(K, w / 2)
	for _, wl in walls do
		for _, b in bands do
			local wn, dcf, u = wallFind(K, { wl }, w, b[1], b[2], prefer, pred)
			if wn then
				return wn, dcf, u
			end
		end
	end
	return nil, nil, nil
end

-- 브랜드 카탈로그 -----------------------------------------------------------------------------------------
-- 메뉴 항목 { 이름, 가격, 아이콘? }
local MENUS: { [string]: any } = {}
MENUS.mega = {
	{ "COFFEE", { { "아메리카노", "2,000", "americano" }, { "카페라떼", "3,200", "latte" }, { "바닐라라떼", "3,700", "vanilla" }, { "메가리카노", "3,300", "americano" }, { "헛개리카노", "2,700" }, { "콜드브루", "3,800" } } },
	{ "NON-COFFEE", { { "딸기라떼", "4,000", "strawberry" }, { "녹차라떼", "3,700", "matcha" }, { "고구마라떼", "3,700" }, { "초코라떼", "3,700", "choco" }, { "퐁크러쉬", "4,400" }, { "곡물라떼", "3,500" } } },
	{ "ADE · TEA", { { "레몬에이드", "3,800", "ade" }, { "자몽에이드", "3,800", "grapefruit" }, { "블루레몬에이드", "3,800", "blue" }, { "복숭아아이스티", "3,000", "tea" }, { "유자차", "3,500" }, { "캐모마일", "2,800" } } },
}
MENUS.compose = {
	{ "COFFEE", { { "아메리카노", "1,800", "americano" }, { "카페라떼", "2,900", "latte" }, { "바닐라라떼", "3,300", "vanilla" }, { "돌체라떼", "3,800", "latte" }, { "헤이즐넛라떼", "3,300" }, { "콜드브루", "3,300" } } },
	{ "BEVERAGE", { { "딸기라떼", "3,800", "strawberry" }, { "리얼초코", "3,500", "choco" }, { "녹차라떼", "3,500", "matcha" }, { "요거트스무디", "3,900" }, { "자몽에이드", "3,800", "grapefruit" }, { "복숭아아이스티", "2,800", "tea" } } },
}
MENUS.twosome = {
	{ "COFFEE", { { "아메리카노", "4,700", "americano" }, { "카페라떼", "5,200", "latte" }, { "스페니쉬 연유라떼", "6,200", "vanilla" }, { "바닐라라떼", "5,700" }, { "로얄 밀크티", "5,900", "tea" } } },
	{ "CAKE", { { "아이스박스", "7,500" }, { "스트로베리 레어치즈", "7,500" }, { "떠먹는 티라미수", "6,900" }, { "생크림 카스텔라", "6,500" }, { "마카롱", "3,000" } } },
}
MENUS.pascucci = {
	{ "CAFFÈ", { { "아메리카노", "4,800", "americano" }, { "카페라떼", "5,300", "latte" }, { "카푸치노", "5,300", "latte" }, { "아포가토", "6,500" }, { "카페모카", "5,800", "choco" } } },
	{ "DOLCE", { { "티라미수", "7,000" }, { "젤라또 컵", "5,500" }, { "파니니", "7,500" }, { "크로플", "5,000" }, { "레몬에이드", "6,000", "ade" } } },
}
MENUS.starbucks = {
	{ "ESPRESSO", { { "아메리카노", "4,700" }, { "카페라떼", "5,200" }, { "카라멜 마키아또", "6,100" }, { "돌체라떼", "6,100" }, { "콜드브루", "5,100" } } },
	{ "FRAPPUCCINO · TEA", { { "자바칩 프라푸치노", "6,600" }, { "자몽허니블랙티", "6,100" }, { "유자민트티", "6,100" }, { "딸기 딜라이트 요거트", "6,700" } } },
}
MENUS.roastery = {
	{ "ESPRESSO BAR", { { "에스프레소", "4,000", "americano" }, { "아메리카노", "5,000", "americano" }, { "카페라떼", "5,500", "latte" }, { "플랫화이트", "5,800", "latte" }, { "아인슈페너", "6,500", "vanilla" }, { "콜드브루", "6,000" } } },
	{ "FILTER COFFEE", { { "에티오피아 예가체프 G1", "7,000" }, { "케냐 AA 키리냐가", "7,500" }, { "콜롬비아 게이샤", "12,000" }, { "과테말라 안티구아", "6,500" }, { "디카페인 콜롬비아", "6,500" }, { "오늘의 핸드드립", "6,000" } } },
	{ "BEANS 200g", { { "하우스 블렌드", "16,000" }, { "싱글 오리진", "19,000" }, { "게이샤 100g", "28,000" }, { "드립백 10입", "15,000" }, { "디카페인", "18,000" } } },
}
MENUS.haute = {
	{ "SIGNATURE", { { "오뜨 크림라떼", "7,500", "vanilla" }, { "피스타치오 라떼", "7,500", "matcha" }, { "얼그레이 밀크티", "7,000", "tea" }, { "아메리카노", "5,500", "americano" }, { "로즈 에이드", "7,500", "strawberry" } } },
	{ "PÂTISSERIE", { { "딸기 생크림 케이크", "8,500" }, { "바닐라 밀푀유", "9,000" }, { "마카롱 (1개)", "3,200" }, { "까눌레", "3,800" }, { "바스크 치즈케이크", "7,500" } } },
}
MENUS.busan = {
	{ "051 COFFEE", { { "아메리카노", "4,500", "americano" }, { "카페라떼", "5,000", "latte" }, { "광안 씨솔트라떼", "6,500", "vanilla" }, { "영도 흑임자라떼", "6,500", "choco" }, { "아인슈페너", "6,000" }, { "콜드브루", "5,500" } } },
	{ "NON-COFFEE", { { "해운대 블루에이드", "6,800", "blue" }, { "기장 유자에이드", "6,500", "ade" }, { "흑당 밀크티", "6,000", "tea" }, { "말차라떼", "6,000", "matcha" }, { "바다 소금빵", "3,800" }, { "부산 앙버터", "4,500" } } },
}
MENUS.lounge = {
	{ "COFFEE", { { "아메리카노", "7,000", "americano" }, { "카페라떼", "7,500", "latte" }, { "플랫화이트", "7,500", "latte" }, { "아인슈페너", "8,000" }, { "콜드브루", "7,500" } } },
	{ "TEA · DESSERT", { { "TWG 얼그레이", "8,000", "tea" }, { "캐모마일", "8,000" }, { "애프터눈 티 세트 (2인)", "39,000" }, { "치즈케이크", "9,000" }, { "와인 (글라스)", "12,000" } } },
}
MENUS.indie = {
	{ "COFFEE", { { "아메리카노", "4,500", "americano" }, { "카페라떼", "5,000", "latte" }, { "바닐라빈라떼", "5,500", "vanilla" }, { "플랫화이트", "5,500", "latte" }, { "아인슈페너", "6,000" }, { "핸드드립", "6,500" } } },
	{ "NON-COFFEE", { { "말차라떼", "6,000", "matcha" }, { "딸기라떼", "6,500", "strawberry" }, { "자몽에이드", "6,000", "grapefruit" }, { "얼그레이 밀크티", "6,000", "tea" }, { "레몬 진저티", "5,500" } } },
	{ "BAKE", { { "소금빵", "3,800" }, { "바스크 치즈케이크", "7,000" }, { "휘낭시에", "3,000" }, { "스콘", "3,500" }, { "크로플", "5,500" } } },
}
MENUS.indie2 = {
	{ "COFFEE", { { "아메리카노", "4,800", "americano" }, { "카페라떼", "5,300", "latte" }, { "크림라떼", "6,000", "vanilla" }, { "흑당라떼", "6,000", "choco" }, { "콜드브루", "5,500" }, { "디카페인 +500", "" } } },
	{ "TEA · ADE", { { "청귤에이드", "6,500", "ade" }, { "자몽허니블랙티", "6,000", "grapefruit" }, { "유자민트티", "5,800", "tea" }, { "말차라떼", "6,300", "matcha" }, { "딸기우유", "6,500", "strawberry" } } },
	{ "DESSERT", { { "크로플", "5,800" }, { "티라미수", "7,000" }, { "레몬 파운드", "4,500" }, { "버터바", "4,000" }, { "스모어 쿠키", "4,200" } } },
}
MENUS.indie3 = {
	{ "COFFEE", { { "에스프레소", "4,000", "americano" }, { "아메리카노", "4,500", "americano" }, { "라떼", "5,000", "latte" }, { "오트라떼", "5,800", "latte" }, { "아포가토", "6,500" }, { "핸드드립", "7,000" } } },
	{ "SIGNATURE", { { "바다 크림커피", "6,500", "vanilla" }, { "피스타치오 라떼", "6,800", "matcha" }, { "선셋 에이드", "6,800", "grapefruit" }, { "밀크티", "6,000", "tea" }, { "바닐라빈 쉐이크", "7,000", "vanilla" } } },
}
MENUS.bakery = {
	{ "오늘의 빵", { { "소금빵", "3,500" }, { "크루아상", "4,200" }, { "단팥빵", "2,800" }, { "소보로", "2,800" }, { "우유식빵", "5,500" }, { "바게트", "4,500" }, { "고로케", "3,000" }, { "마늘바게트", "5,000" } } },
	{ "CAKE · DRINK", { { "생크림 케이크 1호", "32,000" }, { "에그타르트", "3,200" }, { "크림치즈 베이글", "4,500" }, { "아메리카노", "3,500", "americano" }, { "카페라떼", "4,000", "latte" }, { "우유 (200ml)", "1,500" } } },
}
MENUS.waffle = {
	{ "WAFFLE", { { "플레인 와플", "3,500" }, { "생크림 와플", "4,500" }, { "누텔라 바나나", "5,500" }, { "젤라또 와플", "6,500" }, { "크로플", "4,500" }, { "애플 시나몬", "5,000" } } },
	{ "GELATO", { { "싱글 컵 · 콘", "4,800" }, { "더블", "6,800" }, { "트리플", "8,800" }, { "파인트 (포장)", "16,000" }, { "아포가토", "6,500", "americano" } } },
}
MENUS.tanghulu = {
	{ "탕후루", { { "딸기 탕후루", "3,500" }, { "샤인머스캣", "4,500" }, { "블루베리", "4,000" }, { "귤 탕후루", "3,000" }, { "키위", "3,500" }, { "방울토마토", "3,000" }, { "파인애플", "3,500" }, { "모둠 (3꼬치)", "9,900" } } },
	{ "GELATO", { { "싱글", "4,800" }, { "더블", "6,800" }, { "트리플", "8,800" }, { "탕후루 젤라또", "6,500" }, { "아이스티", "3,000", "tea" } } },
}
MENUS.bingsu = {
	{ "빙수", { { "우유 눈꽃빙수", "9,900" }, { "애플망고 빙수", "13,900" }, { "인절미 빙수", "10,900" }, { "옛날 팥빙수", "9,500" }, { "생딸기 빙수", "12,900" }, { "초코 브라우니 빙수", "11,500" } } },
	{ "DRINK", { { "아메리카노", "3,500", "americano" }, { "딸기라떼", "5,000", "strawberry" }, { "망고 스무디", "5,500", "ade" }, { "아이스티", "3,000", "tea" } } },
}
MENUS.claw = {
	{ "PLAY", { { "1회", "1,000원" }, { "5회 (+1 보너스)", "5,000원" }, { "10회 (+3 보너스)", "10,000원" } } },
	{ "빙수 · 아이스크림", { { "컵빙수", "4,500" }, { "아이스크림 (낱개)", "1,000~" }, { "음료", "1,500~" } } },
}
MENUS.churros = {
	{ "CHURROS", { { "오리지널 츄러스", "3,000" }, { "시나몬 슈가", "3,000" }, { "초코 딥", "4,000" }, { "츄러스 + 젤라또", "6,500" }, { "미니 츄러스 (6개)", "5,000" } } },
	{ "GELATO", { { "싱글", "4,800" }, { "더블", "6,800" }, { "아이스 초코", "4,500", "choco" } } },
}
MENUS.hotteok = {
	{ "호떡", { { "씨앗호떡", "2,000" }, { "꿀호떡", "1,500" }, { "치즈호떡", "2,500" }, { "녹차씨앗호떡", "2,500" }, { "호떡 아이스크림", "4,000" } } },
	{ "DRINK", { { "식혜", "2,500" }, { "아메리카노", "2,500", "americano" }, { "유자차", "3,000" } } },
}

-- B 필드: title (간판), logo (짧은 로고), slogan, c1 (주색), c2 (짙은색), c3 (강조), paper, ink,
--   menuKind ("lightbox" | "chalk" | "felt" | "brass" | "tv"), menuBg / menuFg / menuAcc, menus,
--   neon = { 글자, 색, 폰트 }, art (벽 그림 종류), wifi, promo, wall = { 벽 이름 = look } (벽 전체 스킨),
--   feat = { selfbar, fridge, md, roaster, ducts, track, pickup, cake, oven, island, hangPlants, claw, tanghulu ... }
local function brandKey(V: any): string
	local n = string.upper(V.name or "")
	local menu = V.menu or ""
	local function has(s: string): boolean
		return string.find(n, s, 1, true) ~= nil
	end
	if V.type == "dessert" then
		if V:has("ClawBase") > 0 then
			return "claw"
		end
		if has("탕후루") or menu == "tanghulu" then
			return "tanghulu"
		end
		if has("와플") or menu == "waffle" or V:has("WaffleIron") > 0 then
			return "waffle"
		end
		if has("츄러스") or menu == "churros" then
			return "churros"
		end
		if has("호떡") or menu == "hotteok" then
			return "hotteok"
		end
		if V:has("GelatoTub") > 0 then
			return "waffle"
		end
		return "bingsu"
	end
	if V.type == "bakery" then
		return "bakery"
	end
	if has("STARBUCKS") or has("스타벅스") then
		return "starbucks"
	end
	if has("MEGA") then
		return "mega"
	end
	if has("COMPOSE") then
		return "compose"
	end
	if has("TWOSOME") then
		return "twosome"
	end
	if has("PASCUCCI") then
		return "pascucci"
	end
	if has("로스터리") or has("LAB") or has("ROAST") or menu == "roastery" then
		return "roastery"
	end
	if has("HAUTE") then
		return "haute"
	end
	if has("051") then
		return "busan"
	end
	if has("라운지") or has("LOUNGE") or has("HOTEL") or has("15F") or has("씨엘로") then
		return "lounge"
	end
	if menu == "dessertcafe" then
		return "haute"
	end
	local list = { "scandi", "terracotta", "concrete", "ocean", "green" }
	return list[hashStr(V.name or "cafe") % #list + 1]
end

local function brandOf(V: any): any
	local key = brandKey(V)
	local nm = V.name or "CAFE"
	local seed = hashStr((V.key or nm) .. "#")
	local B: any = {
		key = key,
		seed = seed,
		title = nm,
		logo = nm,
		slogan = "SPECIALTY COFFEE",
		c1 = rgb(60, 44, 34),
		c2 = rgb(28, 26, 24),
		c3 = rgb(214, 172, 110),
		paper = rgb(246, 242, 234),
		ink = rgb(30, 28, 26),
		menuKind = "chalk",
		menus = MENUS.indie,
		neon = { "coffee & moments", rgb(255, 196, 120), F.IndieFlower },
		art = "abstract",
		wifi = "CAFE_5G",
		pw = "coffee2026",
		hours = "매일 10:00 - 23:00",
		promo = { "NEW", "딸기 라떼 시즌 한정", "6,500" },
		feat = { selfbar = true, md = true, pickup = true, plants = 2 },
		cup = rgb(250, 250, 248),
	}
	local feat = B.feat
	if key == "mega" then
		B.title, B.logo, B.slogan = "MEGA COFFEE", "MGC", "MEGA SIZE · MEGA VALUE"
		B.c1, B.c2, B.c3, B.paper, B.ink = rgb(255, 208, 0), rgb(24, 24, 26), rgb(255, 255, 255), rgb(255, 255, 255), rgb(22, 22, 22)
		B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "lightbox", rgb(255, 208, 0), rgb(24, 24, 24), rgb(24, 24, 24)
		B.menus = MENUS.mega
		B.neon = { "MEGA COFFEE", rgb(255, 214, 40), F.GothamBlack }
		B.art, B.wifi, B.pw, B.hours = "pop", "MEGACOFFEE_FREE", "mega2026!", "매일 07:00 - 24:00"
		B.promo = { "NEW", "딸기 퐁크러쉬", "4,400" }
		B.cup = rgb(255, 208, 0)
		B.wall = { left = lk(rgb(246, 246, 242), M.Plaster), right = lk(rgb(246, 246, 242), M.Plaster) }
		B.logoPlate, B.logoFg = Look.black, rgb(255, 208, 0)
		feat.fridge, feat.md, feat.tv = true, false, true
	elseif key == "compose" then
		B.title, B.logo, B.slogan = "COMPOSE COFFEE", "COMPOSE", "BEST QUALITY · BEST PRICE"
		B.c1, B.c2, B.c3, B.paper, B.ink = rgb(255, 196, 0), rgb(30, 30, 30), rgb(255, 255, 255), rgb(255, 255, 255), rgb(22, 22, 22)
		B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "lightbox", rgb(28, 28, 30), rgb(250, 250, 248), rgb(255, 196, 0)
		B.menus = MENUS.compose
		B.neon = { "COMPOSE COFFEE", rgb(255, 200, 40), F.GothamBlack }
		B.art, B.wifi, B.pw, B.hours = "pop", "COMPOSE_5G", "compose1234", "매일 07:00 - 24:00"
		B.cup = rgb(255, 196, 0)
		B.wall = { left = lk(rgb(40, 40, 42), M.Plaster), right = lk(rgb(40, 40, 42), M.Plaster) }
		B.logoPlate, B.logoFg = Look.black, rgb(255, 196, 0)
		feat.fridge, feat.md, feat.tv = true, false, true
	elseif key == "twosome" then
		B.title, B.logo, B.slogan = "A TWOSOME PLACE", "TWOSOME", "DESSERT CAFE"
		B.c1, B.c2, B.c3, B.paper, B.ink = rgb(30, 28, 28), rgb(16, 16, 16), rgb(176, 30, 50), rgb(246, 242, 236), rgb(20, 20, 20)
		B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "tv", rgb(18, 18, 18), rgb(244, 240, 232), rgb(220, 60, 80)
		B.menus = MENUS.twosome
		B.neon = { "A TWOSOME PLACE", rgb(255, 240, 230), F.Gotham }
		B.art = "botanical"
		feat.cake, feat.md, feat.fridge = true, false, false
	elseif key == "pascucci" then
		B.title, B.logo, B.slogan = "PASCUCCI", "PASCUCCI", "CAFFÈ ITALIANO DAL 1883"
		B.c1, B.c2, B.c3, B.paper, B.ink = rgb(150, 32, 40), rgb(48, 30, 24), rgb(214, 180, 120), rgb(244, 236, 222), rgb(40, 28, 22)
		B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "brass", rgb(48, 30, 24), rgb(246, 238, 222), rgb(214, 180, 120)
		B.menus = MENUS.pascucci
		B.neon = { "Pascucci", rgb(255, 220, 170), F.Garamond }
		B.art = "coffee"
		feat.fridge = true
	elseif key == "starbucks" then
		B.title, B.logo, B.slogan = "STARBUCKS", "STARBUCKS", "광안리점"
		B.c1, B.c2, B.c3, B.paper, B.ink = rgb(0, 112, 74), rgb(30, 57, 50), rgb(212, 180, 120), rgb(242, 240, 235), rgb(30, 57, 50)
		B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "chalk", rgb(30, 40, 36), rgb(240, 238, 228), rgb(200, 220, 190)
		B.menus = MENUS.starbucks
		B.neon = { "STARBUCKS COFFEE", rgb(220, 250, 230), F.GothamBold }
		B.art = "coffee"
		B.noCounter = true
		feat.pickup, feat.selfbar, feat.md, feat.plants = false, false, false, 0
	elseif key == "roastery" then
		B.title, B.logo, B.slogan = nm, "LAB", "SPECIALTY COFFEE ROASTERS"
		B.c1, B.c2, B.c3, B.paper, B.ink = rgb(28, 28, 30), rgb(18, 18, 18), rgb(214, 120, 52), rgb(236, 232, 224), rgb(24, 24, 24)
		B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "felt", rgb(26, 26, 28), rgb(240, 240, 236), rgb(240, 160, 90)
		B.menus = MENUS.roastery
		B.neon = { "ROASTING IN PROGRESS", rgb(255, 140, 60), F.Oswald }
		B.art, B.wifi, B.pw, B.hours = "coffee", "LAB149_GUEST", "roast149", "매일 09:00 - 22:00 · 로스팅 화 · 금"
		B.wall = { left = lk(rgb(168, 98, 76), M.Brick), right = lk(rgb(160, 158, 154), M.Concrete), back = lk(rgb(176, 174, 170), M.Concrete) }
		B.promo = { "THIS WEEK", "에티오피아 게뎁 내추럴", "7,500" }
		feat.roaster, feat.ducts, feat.track, feat.sacks, feat.drip = true, true, true, true, true
	elseif key == "haute" then
		B.title, B.logo, B.slogan = nm, "Haute", "PÂTISSERIE & CAFÉ"
		B.c1, B.c2, B.c3, B.paper, B.ink = rgb(236, 196, 196), rgb(60, 44, 40), rgb(196, 160, 96), rgb(250, 246, 240), rgb(52, 40, 36)
		B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "brass", rgb(250, 246, 238), rgb(52, 40, 36), rgb(176, 136, 70)
		B.menus = MENUS.haute
		B.neon = { "la vie en rose", rgb(255, 150, 180), F.IndieFlower }
		B.art, B.wifi, B.pw, B.hours = "gallery", "HAUTE_GUEST", "haute0510", "매일 11:00 - 22:00"
		B.promo = { "SEASON", "딸기 밀푀유 출시", "9,800" }
		B.cup = rgb(248, 236, 236)
		B.sofa = rgb(196, 150, 150)
		B.logoFg = rgb(190, 150, 86)
		feat.cake, feat.md, feat.mirror, feat.flowers = true, false, true, true
	elseif key == "busan" then
		B.title, B.logo, B.slogan = nm, "051", "GWANGALLI · BUSAN"
		B.c1, B.c2, B.c3, B.paper, B.ink = rgb(30, 74, 140), rgb(18, 34, 64), rgb(250, 196, 60), rgb(246, 246, 242), rgb(22, 36, 60)
		B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "lightbox", rgb(246, 246, 242), rgb(22, 36, 60), rgb(30, 74, 140)
		B.menus = MENUS.busan
		B.neon = { "SEA YOU IN 051", rgb(120, 200, 255), F.FredokaOne }
		B.art, B.wifi, B.pw = "busan", "CAFE051_FREE", "gwangalli051"
		B.promo = { "BUSAN ONLY", "광안 씨솔트라떼", "6,500" }
		B.cup = rgb(240, 246, 252)
		feat.fridge = true
	elseif key == "lounge" then
		B.title, B.logo, B.slogan = nm, "LOUNGE", "COFFEE · TEA · WINE"
		B.c1, B.c2, B.c3, B.paper, B.ink = rgb(40, 34, 30), rgb(22, 20, 18), rgb(196, 160, 96), rgb(240, 234, 222), rgb(30, 26, 22)
		B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "brass", rgb(30, 28, 26), rgb(240, 232, 216), rgb(206, 170, 106)
		B.menus = MENUS.lounge
		B.neon = { "good evening", rgb(255, 210, 160), F.IndieFlower }
		B.art = "gallery"
		feat.md = false
	elseif key == "bakery" then
		B.title, B.logo, B.slogan = nm, "BAKERY", "매일 아침 직접 굽는 빵"
		B.c1, B.c2, B.c3, B.paper, B.ink = rgb(150, 96, 52), rgb(60, 40, 28), rgb(232, 176, 60), rgb(250, 244, 230), rgb(52, 36, 24)
		B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "chalk", rgb(36, 40, 36), rgb(244, 240, 228), rgb(246, 210, 120)
		B.menus = MENUS.bakery
		B.neon = { "FRESH BREAD DAILY", rgb(255, 196, 110), F.FredokaOne }
		B.art, B.wifi, B.pw, B.hours = "bread", "BAKERY_GUEST", "bread0707", "매일 07:00 - 22:00"
		B.promo = { "OVEN FRESH", "오늘의 소금빵 나왔어요", "3,500" }
		feat = { oven = true, cake = true, island = true, plants = 1, tongs = true }
		B.feat = feat
	elseif key == "waffle" or key == "churros" or key == "hotteok" then
		B.title, B.logo = nm, if key == "waffle" then "WAFFLE" elseif key == "churros" then "CHURROS" else "호떡"
		B.slogan = if key == "waffle" then "WAFFLE & GELATO" elseif key == "churros" then "CHURROS & GELATO" else "부산 명물 씨앗호떡"
		B.c1, B.c2, B.c3, B.paper, B.ink = rgb(150, 210, 196), rgb(60, 50, 46), rgb(246, 150, 160), rgb(255, 250, 244), rgb(60, 46, 40)
		B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "lightbox", rgb(255, 250, 244), rgb(60, 46, 40), rgb(230, 110, 130)
		B.menus = MENUS[key]
		B.neon = { if key == "waffle" then "sweet waffle" else "sweet & warm", rgb(255, 150, 190), F.FredokaOne }
		B.art, B.wifi, B.pw, B.hours = "pastel", "SWEET_FREE", "gelato777", "매일 11:00 - 23:00"
		B.promo = { "BEST", "젤라또 와플", "6,500" }
		B.cup = rgb(255, 236, 240)
		feat = { freezer = true, plants = 1, gelato = true }
		B.feat = feat
	elseif key == "tanghulu" then
		B.title, B.logo, B.slogan = nm, "탕후루", "바삭 달콤 과일 탕후루"
		B.c1, B.c2, B.c3, B.paper, B.ink = rgb(222, 40, 60), rgb(60, 20, 24), rgb(255, 210, 60), rgb(255, 248, 244), rgb(70, 20, 26)
		B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "lightbox", rgb(222, 40, 60), rgb(255, 255, 255), rgb(255, 222, 90)
		B.menus = MENUS.tanghulu
		B.neon = { "탕후루 & 젤라또", rgb(255, 90, 120), F.FredokaOne }
		B.art, B.wifi, B.pw, B.hours = "fruit", "TANGHULU_5G", "sweet2026", "매일 12:00 - 23:00"
		B.promo = { "BEST", "샤인머스캣 탕후루", "4,500" }
		B.cup = rgb(255, 240, 240)
		feat = { tanghulu = true, freezer = true, plants = 1, gelato = true, fruit = true }
		B.feat = feat
	elseif key == "claw" then
		B.title, B.logo, B.slogan = nm, "BINGBING", "인형뽑기 · 빙수"
		B.c1, B.c2, B.c3, B.paper, B.ink = rgb(255, 80, 170), rgb(30, 22, 48), rgb(80, 230, 255), rgb(255, 240, 250), rgb(30, 22, 48)
		B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "tv", rgb(24, 16, 40), rgb(255, 255, 255), rgb(255, 90, 180)
		B.menus = MENUS.claw
		B.neon = { "BINGBING", rgb(255, 80, 200), F.FredokaOne }
		B.art, B.wifi, B.pw, B.hours = "neon", "BINGBING_FREE", "pickme2026", "24시간 무인 운영"
		feat = { claw = true, plants = 0, freezer = true, leds = true }
		B.feat = feat
	elseif key == "bingsu" then
		B.title, B.logo, B.slogan = nm, "빙수", "눈꽃빙수 전문점"
		B.c1, B.c2, B.c3, B.paper, B.ink = rgb(140, 196, 236), rgb(30, 50, 80), rgb(255, 190, 200), rgb(250, 252, 255), rgb(30, 46, 70)
		B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "lightbox", rgb(250, 252, 255), rgb(30, 46, 70), rgb(70, 140, 210)
		B.menus = MENUS.bingsu
		B.neon = { "snow flake", rgb(150, 220, 255), F.FredokaOne }
		B.art = "pastel"
		feat = { freezer = true, plants = 1 }
		B.feat = feat
	else
		-- 인디 카페 팔레트
		if string.sub(nm, 1, 8) == "SideShop" then
			local names = { "BEACH COFFEE", "바다 커피", "COFFEE STAND", "SURF COFFEE", "카페 파도", "GWANGAN BREW" }
			nm = names[seed % #names + 1]
		end
		B.title, B.logo = nm, nm
		local mv = { MENUS.indie, MENUS.indie2, MENUS.indie3 }
		B.menus = mv[seed % #mv + 1]
		if key == "scandi" then
			B.c1, B.c2, B.c3, B.paper, B.ink = rgb(156, 176, 150), rgb(48, 52, 46), rgb(214, 186, 140), rgb(248, 246, 240), rgb(40, 42, 38)
			B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "felt", rgb(36, 38, 36), rgb(244, 244, 238), rgb(214, 220, 190)
			B.neon = { "slow coffee", rgb(255, 214, 160), F.IndieFlower }
			B.art = "abstract"
			feat.hangPlants = true
		elseif key == "terracotta" then
			B.c1, B.c2, B.c3, B.paper, B.ink = rgb(196, 112, 76), rgb(72, 44, 32), rgb(232, 196, 140), rgb(246, 238, 226), rgb(64, 40, 28)
			B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "chalk", rgb(52, 44, 40), rgb(244, 236, 222), rgb(240, 190, 140)
			B.neon = { "sunny day coffee", rgb(255, 170, 110), F.IndieFlower }
			B.art = "abstract"
			feat.hangPlants = true
		elseif key == "concrete" then
			B.c1, B.c2, B.c3, B.paper, B.ink = rgb(60, 60, 62), rgb(24, 24, 26), rgb(220, 120, 60), rgb(236, 234, 230), rgb(26, 26, 28)
			B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "felt", rgb(26, 26, 28), rgb(240, 240, 236), rgb(240, 150, 90)
			B.neon = { "COFFEE ON THE BEACH", rgb(255, 255, 255), F.Oswald }
			B.art = "coffee"
			B.wall = { left = lk(rgb(150, 148, 144), M.Concrete) }
			feat.ducts, feat.track = true, true
		elseif key == "ocean" then
			B.c1, B.c2, B.c3, B.paper, B.ink = rgb(40, 110, 170), rgb(20, 40, 64), rgb(250, 210, 120), rgb(248, 248, 244), rgb(24, 40, 64)
			B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "lightbox", rgb(248, 248, 244), rgb(24, 40, 64), rgb(40, 110, 170)
			B.neon = { "ocean breeze", rgb(110, 210, 255), F.FredokaOne }
			B.art = "busan"
		else
			B.c1, B.c2, B.c3, B.paper, B.ink = rgb(44, 80, 62), rgb(24, 40, 32), rgb(200, 164, 96), rgb(244, 240, 228), rgb(28, 40, 32)
			B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "brass", rgb(30, 50, 40), rgb(240, 236, 220), rgb(214, 180, 110)
			B.neon = { "green & bean", rgb(170, 255, 190), F.IndieFlower }
			B.art = "botanical"
			feat.hangPlants = true
		end
	end
	B.menuBg = B.menuBg or rgb(34, 36, 34)
	B.menuFg = B.menuFg or rgb(244, 240, 230)
	B.menuAcc = B.menuAcc or B.c3
	return B
end
T.brandOf = brandOf

-- 스타일 (Common 용) -----------------------------------------------------------------------------------
function T.style(V: any): any
	local B = brandOf(V)
	local k = B.key
	local S: any = {
		brand = B,
		chair = { style = "bentwood", frame = Look.walnut, seat = Look.walnut },
		stool = { style = "bar", frame = Look.blackMetal, seat = Look.leatherBrown },
		table = { top = Look.oak, base = Look.blackMetal, barStyle = "steel" },
		counter = { front = "fluted", frontL = Look.oak, topL = Look.marbleWhite, kickL = Look.black, led = rgb(255, 214, 160) },
		ceiling = { skin = Look.white },
		lights = { kind = "downlight", color = Look.warmLight },
		pendant = { shade = "dome", look = Look.blackMetal },
		base = lk(rgb(70, 60, 52)),
		mat = { text = string.upper(B.logo or "WELCOME") },
		plants = { "monstera", "olive", "snake" },
	}
	if k == "mega" or k == "compose" then
		S.chair = { style = "shell", frame = Look.blackMetal, seat = lk(B.c1, M.Plastic) }
		S.stool = { style = "bar", frame = Look.chrome, seat = lk(rgb(30, 30, 30), M.Leather) }
		S.table = { top = Look.white, base = Look.blackMetal, barStyle = "steel", style = "pedestal" }
		S.counter = { front = "panel", frontL = lk(B.c1), topL = Look.white, kickL = Look.black, led = rgb(255, 240, 200) }
		S.floor = { look = lk(rgb(200, 200, 198), M.CeramicTiles), tile = 2.0, grout = lk(rgb(162, 162, 160)) }
		S.lower = { kind = "tile", h = 3.2, look = Look.tileWhite, grout = lk(rgb(206, 204, 200)), walls = { "left", "right" } }
		S.pendant = { shade = "drum", look = lk(B.c1, M.Metal) }
		S.lights = { kind = "downlight", color = Look.neutralLight }
		S.base = Look.black
	elseif k == "twosome" then
		S.chair = { style = "padded", frame = Look.blackMetal, seat = Look.leatherBlack }
		S.table = { top = Look.marbleBlack, base = Look.blackMetal, style = "pedestal", barStyle = "steel" }
		S.counter = { front = "fluted", frontL = lk(rgb(32, 30, 30)), topL = Look.marbleWhite, kickL = Look.black, led = rgb(255, 220, 190) }
		S.floor = { look = lk(rgb(120, 96, 76), M.WoodPlanks), tile = 0 }
		S.lower = { kind = "wainscot", h = 3.4, look = lk(rgb(40, 36, 36)), panel = 1.8, walls = { "left", "right" } }
		S.pendant = { shade = "dome", look = Look.blackMetal }
	elseif k == "pascucci" then
		S.chair = { style = "bentwood", frame = Look.darkWood, seat = Look.leatherBrown }
		S.counter = { front = "panel", frontL = lk(rgb(120, 30, 34)), topL = Look.marbleWhite, kickL = Look.darkWood, led = rgb(255, 210, 160) }
		S.lower = { kind = "wainscot", h = 3.4, look = Look.walnut, panel = 1.8, walls = { "left", "right" } }
		S.pendant = { shade = "cone", look = Look.brass }
	elseif k == "starbucks" then
		S.chair = { style = "padded", frame = Look.darkWood, seat = Look.leatherBrown }
		S.table = { top = Look.walnut, base = Look.blackMetal, barStyle = "steel" }
		S.counter = false
		S.lower = { kind = "louver", h = 3.4, look = Look.walnut, back = Look.darkWood, walls = { "left", "right" } }
		S.pendant = { shade = "dome", look = lk(rgb(30, 57, 50), M.Metal) }
	elseif k == "roastery" or k == "concrete" then
		S.chair = { style = "shell", frame = Look.blackMetal, seat = Look.plywood }
		S.stool = { style = "cushion", frame = Look.blackMetal, seat = Look.leatherBrown }
		S.table = { top = Look.walnut, base = Look.blackMetal, barStyle = "steel" }
		S.counter = { front = "fluted", frontL = Look.walnut, topL = lk(rgb(64, 64, 66), M.Slate), kickL = Look.black, led = rgb(255, 196, 140) }
		S.floor = { look = Look.polishedConcrete, tile = 4.0, grout = lk(rgb(128, 126, 122)) }
		S.ceiling = { skin = lk(rgb(46, 46, 48), M.Concrete) }
		S.pendant = { shade = "cone", look = Look.blackMetal }
		S.lights = { kind = "downlight", color = Look.warmLight }
		S.base = Look.black
		S.plants = { "snake", "olive" }
	elseif k == "haute" then
		S.chair = { style = "bentwood", frame = Look.walnut, seat = Look.leatherCream }
		S.table = { top = Look.marbleWhite, base = Look.brass, edge = Look.goldMetal, style = "pedestal", barStyle = "steel" }
		S.counter = { front = "fluted", frontL = lk(rgb(240, 232, 220)), topL = Look.marbleWhite, kickL = Look.brass, led = rgb(255, 220, 186) }
		S.floor = { look = lk(rgb(234, 228, 220), M.Marble), tile = 2.5, grout = lk(rgb(204, 196, 184)) }
		S.ceiling = { skin = Look.white, crown = lk(rgb(242, 238, 230)) }
		S.lower = { kind = "wainscot", h = 3.4, look = lk(rgb(242, 236, 226)), cap = lk(rgb(200, 168, 108), M.Metal), panel = 2.2, walls = { "left", "right" } }
		S.pendant = { shade = "globe" }
		S.base = lk(rgb(232, 224, 212))
		S.plants = { "olive", "ficus" }
	elseif k == "busan" or k == "ocean" then
		S.stool = { style = "wood", frame = Look.oak, seat = Look.oak }
		S.chair = { style = "shell", frame = Look.blackMetal, seat = Look.lightOak }
		S.table = { top = Look.lightOak, base = Look.blackMetal, barStyle = "steel" }
		S.counter = { front = "tile", frontL = lk(rgb(36, 80, 146), M.CeramicTiles), topL = Look.terrazzo, kickL = Look.black, led = rgb(220, 236, 255) }
		S.floor = { look = Look.terrazzo, tile = 0 }
		S.lower = { kind = "tile", h = 3.0, look = Look.tileWhite, grout = lk(rgb(96, 136, 186)), walls = { "left", "right" } }
		S.pendant = { shade = "dome", look = lk(rgb(30, 60, 110), M.Metal) }
		S.lights = { kind = "downlight", color = Look.neutralLight }
	elseif k == "lounge" then
		S.chair = { style = "padded", frame = Look.darkWood, seat = Look.fabricNavy }
		S.table = { top = Look.marbleBlack, base = Look.brass, style = "pedestal", barStyle = "steel" }
		S.counter = { front = "marble", frontL = Look.marbleBlack, topL = Look.marbleWhite, kickL = Look.brass, led = rgb(255, 210, 160) }
		S.floor = { look = lk(rgb(92, 66, 48), M.WoodPlanks), tile = 0 }
		S.lower = { kind = "wainscot", h = 3.4, look = Look.walnut, cap = Look.brass, panel = 2.0, walls = { "left", "right" } }
		S.pendant = { shade = "drum", look = Look.fabricBeige }
	elseif k == "scandi" then
		S.chair = { style = "shell", frame = Look.birch, seat = Look.birch }
		S.stool = { style = "wood", frame = Look.birch, seat = Look.birch }
		S.table = { top = Look.birch, base = Look.birch, barStyle = "steel" }
		S.counter = { front = "fluted", frontL = Look.birch, topL = Look.white, kickL = lk(rgb(120, 136, 116)), led = rgb(255, 224, 180) }
		S.floor = { look = lk(rgb(208, 180, 140), M.WoodPlanks), tile = 0 }
		S.lower = { kind = "paint", h = 3.4, look = lk(B.c1), cap = Look.birch, walls = { "left", "right" } }
		S.pendant = { shade = "cone", look = Look.white }
	elseif k == "terracotta" then
		S.chair = { style = "bentwood", frame = Look.oak, seat = Look.rattan }
		S.counter = { front = "tile", frontL = lk(rgb(196, 112, 76), M.CeramicTiles), topL = Look.lightOak, kickL = lk(rgb(90, 56, 40)), led = rgb(255, 200, 150) }
		S.floor = { look = lk(rgb(190, 116, 84), M.CeramicTiles), tile = 1.5, grout = lk(rgb(214, 196, 176)) }
		S.lower = { kind = "paint", h = 3.0, look = lk(rgb(230, 186, 156)), cap = Look.oak, walls = { "left", "right" } }
		S.pendant = { shade = "rattan" }
	elseif k == "green" then
		S.chair = { style = "padded", frame = Look.brass, seat = Look.fabricGreen }
		S.counter = { front = "fluted", frontL = lk(rgb(40, 72, 56)), topL = Look.marbleWhite, kickL = Look.brass, led = rgb(255, 216, 170) }
		S.floor = { look = lk(rgb(150, 112, 80), M.WoodPlanks), tile = 0 }
		S.lower = { kind = "louver", h = 3.4, look = lk(rgb(46, 82, 62), M.Wood), back = lk(rgb(30, 50, 40)), walls = { "left", "right" } }
		S.pendant = { shade = "dome", look = Look.brass }
	elseif k == "bakery" then
		S.chair = { style = "bentwood", frame = Look.oak, seat = Look.oak }
		S.table = { top = Look.marbleWhite, base = Look.blackMetal, style = "pedestal", barStyle = "steel" }
		S.counter = { front = "panel", frontL = Look.oak, topL = Look.marbleWhite, kickL = Look.walnut, led = rgb(255, 214, 160) }
		S.floor = { look = lk(rgb(214, 200, 182), M.CeramicTiles), tile = 2.0, grout = lk(rgb(182, 168, 150)) }
		S.lower = { kind = "tile", h = 3.2, look = Look.tileWhite, grout = lk(rgb(200, 196, 190)), walls = { "left", "right" } }
		S.pendant = { shade = "dome", look = lk(rgb(60, 52, 46), M.Metal) }
		S.base = Look.walnut
		S.plants = { "olive" }
	elseif k == "waffle" or k == "churros" or k == "hotteok" or k == "bingsu" then
		S.chair = { style = "shell", frame = Look.white, seat = lk(B.c3, M.Plastic) }
		S.table = { top = Look.white, base = Look.white, style = "pedestal", barStyle = "steel" }
		S.counter = { front = "fluted", frontL = lk(B.c1), topL = Look.white, kickL = lk(dk(B.c1, 0.4)), led = rgb(255, 230, 220) }
		S.floor = { look = lk(rgb(240, 232, 228), M.Granite), tile = 0 }
		S.lower = { kind = "tile", h = 3.0, look = lk(lt(B.c1, 0.55), M.CeramicTiles), grout = lk(rgb(255, 255, 255)), walls = { "left", "right" } }
		S.pendant = { shade = "globe" }
		S.lights = { kind = "downlight", color = Look.neutralLight }
		S.base = Look.white
		S.plants = { "olive" }
	elseif k == "tanghulu" then
		S.chair = { style = "shell", frame = Look.white, seat = lk(B.c1, M.Plastic) }
		S.table = { top = Look.white, base = Look.white, style = "pedestal", barStyle = "steel" }
		S.counter = { front = "panel", frontL = lk(B.c1), topL = Look.white, kickL = lk(dk(B.c1, 0.5)), led = rgb(255, 230, 220) }
		S.floor = { look = lk(rgb(244, 242, 238), M.CeramicTiles), tile = 2.0, grout = lk(rgb(224, 210, 210)) }
		S.lower = { kind = "tile", h = 3.0, look = Look.tileWhite, grout = lk(rgb(240, 160, 170)), walls = { "left", "right" } }
		S.pendant = { shade = "dome", look = lk(B.c1, M.Metal) }
		S.lights = { kind = "downlight", color = Look.neutralLight }
		S.base = lk(B.c1)
		S.plants = { "olive" }
	elseif k == "claw" then
		S.floor = { look = lk(rgb(34, 28, 50), M.Rubber), tile = 2.0, grout = lk(rgb(60, 40, 90)) }
		S.ceiling = { skin = lk(rgb(26, 22, 34)) }
		S.lower = false
		S.lights = { kind = "downlight", color = rgb(240, 230, 255) }
		S.base = lk(rgb(40, 30, 60))
		S.mat = { text = "PICK ME UP!" }
		S.plants = {}
	end
	-- 의자는 이 모듈이 직접 (소파 구분)
	S.myChair = S.chair
	S.chair = false
	return S
end

-- 소품 라이브러리 ----------------------------------------------------------------------------------------

-- 음료 그림 (메뉴판 사진 자리): dcf 표면, s = 높이
local DRINK: { [string]: { Color3 } } = {
	americano = { rgb(52, 30, 18), rgb(86, 52, 30), rgb(30, 30, 30) },
	latte = { rgb(190, 142, 96), rgb(242, 228, 206), rgb(30, 30, 30) },
	vanilla = { rgb(214, 172, 116), rgb(248, 238, 216), rgb(30, 30, 30) },
	strawberry = { rgb(226, 70, 96), rgb(252, 214, 222), rgb(240, 240, 240) },
	matcha = { rgb(112, 156, 72), rgb(228, 238, 206), rgb(30, 30, 30) },
	ade = { rgb(250, 204, 54), rgb(255, 244, 180), rgb(240, 240, 240) },
	grapefruit = { rgb(238, 100, 80), rgb(255, 200, 176), rgb(240, 240, 240) },
	choco = { rgb(86, 52, 34), rgb(200, 164, 132), rgb(30, 30, 30) },
	blue = { rgb(50, 130, 220), rgb(196, 232, 252), rgb(240, 240, 240) },
	tea = { rgb(196, 112, 36), rgb(236, 176, 96), rgb(30, 30, 30) },
}
local function glyph(K: any, dcf: CFrame, s: number, kind: string)
	local c = DRINK[kind] or DRINK.latte
	K:plate("CupGlyph", 0.48 * s, 0.66 * s, 0.01, dcf * CF(0, -0.08 * s, 0), lk(rgb(238, 242, 244)))
	K:plate("CupDrink", 0.42 * s, 0.36 * s, 0.014, dcf * CF(0, -0.22 * s, 0), lk(c[1]))
	K:plate("CupTop", 0.44 * s, 0.2 * s, 0.014, dcf * CF(0, 0.06 * s, 0), lk(c[2]))
	K:plate("CupLid", 0.56 * s, 0.07 * s, 0.018, dcf * CF(0, 0.28 * s, 0), lk(rgb(252, 252, 252)))
	K:plate("CupStraw", 0.045 * s, 0.34 * s, 0.02, dcf * CF(0.07 * s, 0.44 * s, 0) * ANG(0, 0, -0.2), lk(c[3]))
end

-- 메뉴판. st = { kind, bg, fg, acc, frame, font, tfont, icons, sub }. 반환 얼굴 파트
local function menuPanel(K: any, dcf: CFrame, w: number, h: number, title: string?, items: { any }, st: any): BasePart?
	local kind = st.kind or "lightbox"
	local bg: Color3, fg: Color3, acc: Color3 = st.bg, st.fg, st.acc
	local lit = kind == "lightbox" or kind == "tv"
	local glow = if lit then (st.glow or 1.0) else nil
	local dep = if kind == "lightbox" then 0.24 elseif kind == "tv" then 0.14 else 0.08
	local frameL = st.frame or (if kind == "chalk" then Look.walnut elseif kind == "brass" then Look.brass elseif kind == "felt" then Look.oak elseif kind == "tv" then Look.black else Look.alu)
	local bw = if kind == "tv" then 0.05 elseif kind == "lightbox" then 0.07 else 0.11
	K:plate("MenuBack", w + 2 * bw, h + 2 * bw, dep, dcf, lk(dk(frameL.c, 0.2), frameL.m))
	local face: BasePart
	if lit then
		face = K:text("MenuFace", w, h, dcf * CF(0, 0, dep), " ", { bg = bg, glow = 0.8, d = 0.02 })
	else
		local fm = if kind == "chalk" then M.Slate elseif kind == "felt" then M.Fabric else M.SmoothPlastic
		face = K:plate("MenuFace", w, h, 0.02, dcf * CF(0, 0, dep), lk(bg, fm))
	end
	local fz = dep + 0.025
	-- 테두리 (프레임 립)
	local lipD = if lit then 0.035 else 0.06
	K:plate("MenuLip", w + 2 * bw, bw, fz - dep + lipD, dcf * CF(0, h / 2 + bw / 2, dep), frameL)
	K:plate("MenuLip", w + 2 * bw, bw, fz - dep + lipD, dcf * CF(0, -h / 2 - bw / 2, dep), frameL)
	K:plate("MenuLip", bw, h, fz - dep + lipD, dcf * CF(-w / 2 - bw / 2, 0, dep), frameL)
	K:plate("MenuLip", bw, h, fz - dep + lipD, dcf * CF(w / 2 + bw / 2, 0, dep), frameL)
	local y = h / 2 - 0.12
	if title then
		local th = math.clamp(h * 0.13, 0.3, 0.62)
		K:text("MenuTitle", w * 0.86, th, dcf * CF(0, y - th / 2, fz), title, { fg = acc, glow = glow, font = st.tfont or F.GothamBlack })
		y -= th + 0.07
		K:plate("MenuRule", w * 0.86, 0.03, 0.006, dcf * CF(0, y, fz + (if lit then 0.05 else -0.003)), lk(acc))
		y -= 0.08
	end
	local icons = {}
	for _, it in items do
		if it[3] and #icons < 4 then
			table.insert(icons, it[3])
		end
	end
	local iconH = if st.icons ~= false and #icons > 0 and h >= 2.4 and w >= 2.0 then math.min(0.95, h * 0.24) else 0
	local bottom = -h / 2 + 0.1 + iconH
	local n = #items
	local rh = math.min(0.46, (y - bottom) / math.max(1, n))
	for i, it in items do
		local ry = y - rh * (i - 0.5)
		K:text("MenuItem", w * 0.6, rh * 0.6, dcf * CF(-w * 0.43 + w * 0.3, ry, fz), it[1], { fg = fg, glow = glow, align = "Left", font = st.font or F.GothamMedium })
		if it[2] then
			K:text("MenuPrice", w * 0.25, rh * 0.56, dcf * CF(w * 0.43 - w * 0.125, ry, fz), it[2], { fg = acc, glow = glow, align = "Right", font = F.GothamBold })
		end
		if not lit and hi(K) and i < n and kind ~= "felt" then
			K:plate("MenuDots", w * 0.86, 0.012, 0.004, dcf * CF(0, ry - rh / 2, fz - 0.004), lk(dk(bg:Lerp(fg, 0.35), 0.1)))
		end
	end
	if iconH > 0 then
		for i, ik in icons do
			local x = -w / 2 + w * (i - 0.5) / #icons
			glyph(K, dcf * CF(x, -h / 2 + 0.08 + iconH / 2, fz + (if lit then 0.05 else -0.004)), iconH * 0.92, ik)
		end
	end
	if st.sub then
		K:text("MenuSub", w * 0.8, 0.16, dcf * CF(0, -h / 2 + 0.1, fz), st.sub, { fg = dk(fg, 0.15), glow = glow, font = F.Gotham })
	end
	return face
end

-- 네온 사인 (아크릴 판 + 빛나는 글자 + 스탠드오프). 반환 sign 표 (켜기/끄기용)
local function neonSign(K: any, dcf: CFrame, w: number, h: number, text: string, c: Color3, font: any?, backer: boolean?): any
	if backer ~= false then
		K:plate("NeonBacker", w + 0.36, h + 0.26, 0.05, dcf * CF(0, 0, 0.1), glassL(rgb(36, 36, 42), 0.5))
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				K:cyl("NeonStandoff", 0.12, 0.08, dcf * CF(sx * (w / 2 + 0.06), sy * (h / 2 + 0.02), 0.06) * ANG(0, PI / 2, 0), Look.chrome)
			end
		end
	end
	local p, lab = K:text("NeonText", w, h, dcf * CF(0, 0, 0.16), text, { fg = c, glow = 2.1, font = font or F.FredokaOne })
	local light = K:light(p, "SurfaceLight", { Face = Enum.NormalId.Front, Range = 8, Brightness = 0.7, Angle = 120, Color = c })
	return { part = p, label = lab, light = light, color = c }
end

local function neonToggle(K: any, sign: any, object: string, at: BasePart?)
	local p: BasePart? = at or sign.part
	if not p or p.Parent == nil then
		return
	end
	local gui = sign.part and sign.part:FindFirstChildWhichIsA("SurfaceGui")
	Interact.toggle(K, p :: BasePart, {
		object = object,
		onText = "끄기",
		offText = "켜기",
		state = true,
		on = function(state: boolean)
			if sign.label then
				sign.label.TextColor3 = if state then sign.color else dk(sign.color, 0.6)
			end
			if gui then
				gui.Brightness = if state then 2.1 else 1
				gui.LightInfluence = if state then 0 else 1
			end
			if sign.light then
				sign.light.Enabled = state
			end
			for _, t in sign.tubes or {} do
				if t.Parent then
					t.Material = if state then M.Neon else M.SmoothPlastic
				end
			end
		end,
	})
end

-- 스피커 한 쌍 + 앰프 (BGM 바꾸기 + 이퀄라이저 깜빡임)
local PLAYLIST = { "Lo-fi Beach Jazz", "City Pop 1984", "Bossa Nova Café", "K-Indie Acoustic", "Rainy Day Piano", "광안리 Sunset Mix", "OFF" }
local function speaker(K: any, dcf: CFrame)
	K:plate("SpeakerMount", 0.3, 0.3, 0.12, dcf * CF(0, 0.2, 0), Look.blackMetal)
	K:plate("SpeakerBox", 0.62, 0.98, 0.5, dcf * CF(0, 0, 0.12), Look.of(28, 28, 30, Enum.Material.SmoothPlastic))
	wdisc(K, "SpeakerWoofer", 0.42, 0.03, dcf * CF(0, -0.15, 0.62), Look.of(50, 50, 54, Enum.Material.Fabric))
	wdisc(K, "SpeakerTweeter", 0.16, 0.03, dcf * CF(0, 0.28, 0.62), Look.of(60, 60, 64, Enum.Material.Metal))
end

local function musicPanel(K: any, dcf: CFrame, B: any, compact: boolean?)
	local sc = if compact then 0.72 else 1.0
	K:plate("AmpBody", 1.4 * sc, 0.8, 0.22, dcf, Look.of(34, 34, 36, Enum.Material.Metal))
	K:plate("AmpFace", 1.3 * sc, 0.68, 0.02, dcf * CF(0, 0, 0.22), Look.black)
	local scr, lab = K:text("AmpScreen", 0.84 * sc, 0.24, dcf * CF(-0.14 * sc, 0.13, 0.245), "♪ " .. PLAYLIST[1], { fg = rgb(140, 230, 255), bg = rgb(10, 16, 24), glow = 1.2, font = F.Code, d = 0.01 })
	K:cyl("AmpKnob", 0.08, 0.24 * sc, dcf * CF(0.46 * sc, 0.06, 0.28) * ANG(0, PI / 2, 0), Look.chrome)
	K:text("AmpBrand", 0.5 * sc, 0.08, dcf * CF(-0.3 * sc, -0.27, 0.245), "STREAMER · AMP", { fg = rgb(160, 160, 160), font = F.Gotham, d = 0.005 })
	local bars = {}
	local base = {}
	for i = 1, 7 do
		local x = (-0.42 + i * 0.085) * sc
		local b = K:plate("AmpLED", 0.06, 0.1, 0.012, dcf * CF(x, -0.12, 0.245), Look.neon(if i > 5 then rgb(255, 90, 60) else rgb(80, 230, 140)))
		bars[i] = b
		base[i] = K.cf * dcf * CF(x, -0.17, 0.251)
	end
	local playing = true
	Interact.cycle(K, scr, PLAYLIST, {
		action = "BGM 바꾸기",
		object = "매장 음악",
		on = function(_i: number, item: string)
			playing = item ~= "OFF"
			lab.Text = if playing then "♪ " .. item else "■ BGM OFF"
		end,
	})
	Interact.anim(K, function(t: number)
		for i, b in bars do
			if b.Parent then
				local hgt = if playing then 0.03 + 0.17 * math.abs(math.sin(t * (2.1 + i * 0.37) + i * 1.3)) else 0.02
				b.Size = V3(0.06, hgt, 0.012)
				b.CFrame = base[i] * CF(0, hgt / 2, 0)
			end
		end
	end)
	return scr
end

-- 안내판 (아크릴 + 글자)
local function notice(K: any, dcf: CFrame, w: number, h: number, text: string, fg: Color3, bg: Color3, font: any?)
	K:plate("NoticeBack", w + 0.08, h + 0.08, 0.02, dcf, lk(dk(bg, 0.25)))
	K:text("Notice", w, h, dcf * CF(0, 0, 0.02), text, { fg = fg, bg = bg, d = 0.02, font = font or F.GothamMedium })
	if hi(K) then
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				wdisc(K, "NoticeScrew", 0.06, 0.02, dcf * CF(sx * (w / 2 - 0.06), sy * (h / 2 - 0.06), 0.04), Look.chrome)
			end
		end
	end
end

-- 안내 보드 (코르크 + 꽂힌 종이 3장: 와이파이 · 영업시간 · 결제 안내)
local function infoBoard(K: any, dcf: CFrame, B: any)
	local w, h = 1.9, 2.3
	K:plate("InfoBoardFrame", w + 0.14, h + 0.14, 0.06, dcf, Look.oak)
	K:plate("InfoBoardCork", w, h, 0.07, dcf, lk(rgb(178, 136, 92), M.Sand))
	local z = 0.075
	K:text("InfoWifi", 0.86, 0.95, dcf * CF(-0.44, 0.56, z) * ANG(0, 0, 0.03), "Wi-Fi\n" .. B.wifi .. "\nPW " .. B.pw, { fg = rgb(30, 30, 34), bg = rgb(252, 252, 250), d = 0.01, font = F.GothamMedium })
	K:text("InfoHours", 0.86, 0.95, dcf * CF(0.47, 0.6, z) * ANG(0, 0, -0.04), "영업시간\n" .. B.hours .. "\n라스트오더 30분 전", { fg = rgb(40, 34, 30), bg = rgb(255, 244, 196), d = 0.01, font = F.GothamMedium })
	K:text("InfoPay", 1.6, 0.8, dcf * CF(0, -0.55, z) * ANG(0, 0, 0.015), "카드 · 삼성페이 · 카카오페이 · 제로페이\n현금영수증 발행 가능\n1인 1음료 부탁드려요 :)", { fg = rgb(30, 30, 30), bg = rgb(240, 244, 248), d = 0.01, font = F.GothamMedium })
	for _, p in { V3(-0.44, 0.98, 0), V3(0.47, 1.02, 0), V3(-0.6, -0.2, 0), V3(0.6, -0.2, 0) } do
		K:ball("InfoPin", 0.08, dcf * CF(p.X, p.Y, z + 0.03), lk(if p.Y > 0 then rgb(220, 40, 40) else rgb(40, 110, 220)))
	end
end

-- 벽 그림 --------------------------------------------------------------------------------------------
local function artPiece(K: any, dcf: CFrame, w: number, h: number, kind: string, B: any, idx: number)
	local seed = B.seed + idx * 17
	local frameL = if B.key == "haute" or B.key == "lounge" or B.key == "pascucci" then Look.goldMetal elseif B.key == "scandi" or B.key == "terracotta" or B.key == "bakery" then Look.oak else Look.blackMetal
	local mat = Look.paper
	if kind == "bridge" or kind == "neon" then
		mat = lk(rgb(20, 24, 48))
	elseif kind == "pop" then
		mat = lk(B.c1)
	elseif kind == "botanical" then
		mat = lk(rgb(236, 230, 214))
	end
	Props.frame(K, dcf, w, h, { frame = frameL, mat = mat, border = 0.08, depth = 0.08 })
	local iw, ih = w - 0.32, h - 0.32
	local z = 0.049
	local function blk(nm: string, x: number, y: number, bw: number, bh: number, c: Color3, rot: number?)
		K:plate(nm, iw * bw, ih * bh, 0.005, dcf * CF(iw * (x - 0.5), ih * (y - 0.5), z) * ANG(0, 0, rot or 0), lk(c))
	end
	if kind == "bridge" then
		-- 광안대교 야경: 하늘 띠 · 바다 · 상판 · 주탑 2 · 케이블 · 불빛
		blk("ArtSky", 0.5, 0.82, 1, 0.36, rgb(56, 46, 104))
		blk("ArtSky", 0.5, 0.6, 1, 0.12, rgb(150, 80, 120))
		blk("ArtSea", 0.5, 0.2, 1, 0.4, rgb(14, 30, 64))
		blk("ArtDeck", 0.5, 0.42, 1, 0.025, rgb(220, 226, 236))
		for _, tx in { 0.3, 0.7 } do
			blk("ArtTower", tx, 0.6, 0.018, 0.4, rgb(230, 236, 246))
			for k = 1, 4 do
				local dx = 0.05 * k
				for _, sgn in { -1, 1 } do
					local x0, y0 = tx, 0.8
					local x1, y1 = tx + sgn * dx * 1.6, 0.43
					local len = math.sqrt(((x1 - x0) * iw) ^ 2 + ((y1 - y0) * ih) ^ 2)
					local ang = math.atan2((y1 - y0) * ih, (x1 - x0) * iw)
					K:plate("ArtCable", len, 0.012, 0.004, dcf * CF(iw * ((x0 + x1) / 2 - 0.5), ih * ((y0 + y1) / 2 - 0.5), z) * ANG(0, 0, ang), lk(rgb(200, 210, 230)))
				end
			end
		end
		local cols = { rgb(255, 90, 160), rgb(90, 200, 255), rgb(255, 220, 90), rgb(160, 120, 255) }
		for k = 0, 7 do
			blk("ArtLight", 0.06 + k * 0.125, 0.405, 0.05, 0.012, cols[k % 4 + 1])
		end
		blk("ArtReflect", 0.5, 0.3, 0.9, 0.01, rgb(90, 120, 190))
		K:disc("ArtMoon", ih * 0.12, 0.005, dcf * CF(iw * 0.32, ih * 0.38, z) * ANG(PI / 2, 0, 0), lk(rgb(250, 240, 210)))
	elseif kind == "pop" then
		K:text("ArtPopTitle", iw * 0.9, ih * 0.22, dcf * CF(0, ih * 0.34, z + 0.002), if rnd(seed, 1) > 0.5 then "ICE\nAMERICANO" else "BIG SIZE\nLATTE", { fg = B.c2 or BLACK, font = F.GothamBlack })
		glyph(K, dcf * CF(0, -ih * 0.08, z + 0.002), ih * 0.42, if rnd(seed, 2) > 0.5 then "americano" else "latte")
		K:text("ArtPopPrice", iw * 0.7, ih * 0.14, dcf * CF(0, -ih * 0.38, z + 0.002), B.promo[3] .. "원~", { fg = B.c2 or BLACK, font = F.GothamBlack })
	elseif kind == "botanical" then
		local stems = 2 + math.floor(rnd(seed, 3) * 2)
		for sI = 1, stems do
			local x = 0.25 + (sI - 1) * 0.5 / math.max(1, stems - 1)
			blk("ArtStem", x, 0.45, 0.008, 0.7, rgb(80, 104, 70), (sI - 2) * 0.12)
			for lI = 1, 4 do
				local ly = 0.25 + lI * 0.14
				local side = if lI % 2 == 0 then 1 else -1
				K:ell("ArtLeaf", V3(iw * 0.16, ih * 0.06, 0.01), dcf * CF(iw * (x - 0.5) + side * iw * 0.07, ih * (ly - 0.5), z + 0.004) * ANG(0, 0, side * 0.5), lk(if lI % 2 == 0 then rgb(96, 130, 84) else rgb(130, 160, 100)))
			end
		end
	elseif kind == "coffee" then
		K:text("ArtTitle", iw * 0.86, ih * 0.14, dcf * CF(0, ih * 0.38, z + 0.002), if rnd(seed, 4) > 0.5 then "SINGLE ORIGIN" else "FROM SEED TO CUP", { fg = rgb(40, 32, 26), font = F.Oswald })
		for k = 0, 5 do
			local bx, by = 0.22 + (k % 3) * 0.28, 0.48 - math.floor(k / 3) * 0.24
			K:ell("ArtBean", V3(iw * 0.16, ih * 0.13, 0.02), dcf * CF(iw * (bx - 0.5), ih * (by - 0.5), z + 0.006) * ANG(0, 0, 0.5 + k * 0.4), lk(rgb(92 + k * 6, 58, 36)))
			blk("ArtBeanLine", bx, by, 0.012, 0.11, rgb(50, 30, 20), 0.5 + k * 0.4)
		end
		K:text("ArtOrigin", iw * 0.86, ih * 0.12, dcf * CF(0, -ih * 0.4, z + 0.002), "ETHIOPIA · KENYA · COLOMBIA · GUATEMALA", { fg = rgb(90, 70, 56), font = F.Gotham })
	elseif kind == "bread" then
		K:text("ArtTitle", iw * 0.86, ih * 0.15, dcf * CF(0, ih * 0.37, z + 0.002), "BOULANGERIE", { fg = rgb(90, 56, 30), font = F.Garamond })
		for k = 0, 2 do
			K:ell("ArtBaguette", V3(iw * 0.7, ih * 0.08, 0.02), dcf * CF(0, ih * (0.12 - k * 0.15), z + 0.006) * ANG(0, 0, 0.12 - k * 0.12), lk(rgb(200, 140, 64)))
		end
		K:text("ArtSub", iw * 0.8, ih * 0.1, dcf * CF(0, -ih * 0.4, z + 0.002), "PAIN · CROISSANT · BRIOCHE", { fg = rgb(120, 90, 60), font = F.Gotham })
	elseif kind == "pastel" or kind == "fruit" then
		-- 아이스크림 콘 / 딸기 일러스트
		if kind == "fruit" then
			K:ell("ArtBerry", V3(iw * 0.5, ih * 0.5, 0.02), dcf * CF(0, -ih * 0.05, z + 0.006), lk(rgb(226, 40, 60)))
			for k = 0, 2 do
				K:ell("ArtBerryLeaf", V3(iw * 0.16, ih * 0.07, 0.02), dcf * CF((k - 1) * iw * 0.11, ih * 0.22, z + 0.01) * ANG(0, 0, (k - 1) * 0.5), lk(rgb(60, 150, 60)))
			end
			for k = 0, 8 do
				blk("ArtSeed", 0.36 + (k % 3) * 0.14, 0.32 + math.floor(k / 3) * 0.13, 0.025, 0.04, rgb(255, 230, 120))
			end
		else
			K:wedge("ArtCone", V3(0.004, ih * 0.42, iw * 0.3), dcf * CF(0, -ih * 0.2, z + 0.004) * ANG(0, PI / 2, PI), lk(rgb(214, 160, 90)))
			local sc = { rgb(250, 200, 210), rgb(190, 230, 210), rgb(250, 236, 180) }
			for k = 1, 3 do
				K:disc("ArtScoop", iw * 0.34, 0.005, dcf * CF((k - 2) * iw * 0.08, ih * (0.02 + k * 0.1), z + 0.004 + k * 0.001) * ANG(PI / 2, 0, 0), lk(sc[k]))
			end
		end
		K:text("ArtTitle", iw * 0.86, ih * 0.13, dcf * CF(0, ih * 0.4, z + 0.012), if kind == "fruit" then "SWEET & CRUNCHY" else "HAPPY SCOOPS", { fg = dk(B.c1, 0.3), font = F.FredokaOne })
	elseif kind == "busan" then
		K:text("ArtTitle", iw * 0.8, ih * 0.22, dcf * CF(0, ih * 0.3, z + 0.002), "BUSAN\n051", { fg = rgb(24, 50, 100), font = F.GothamBlack })
		for k = 0, 2 do
			K:ring("ArtWave", dcf * CF(iw * (k * 0.3 - 0.3), -ih * 0.32, z + 0.006), iw * 0.13, 0.025, 6, lk(rgb(50, 120, 200)), 0, PI)
		end
		blk("ArtSea", 0.5, 0.08, 1, 0.16, rgb(60, 140, 210))
		for k = 0, 1 do
			blk("ArtGull", 0.65 + k * 0.12, 0.52 + k * 0.06, 0.07, 0.012, rgb(40, 40, 50), 0.4)
			blk("ArtGull", 0.7 + k * 0.12, 0.52 + k * 0.06, 0.07, 0.012, rgb(40, 40, 50), -0.4)
		end
	elseif kind == "gallery" then
		-- 흑백 사진 느낌 (바다 · 수평선 · 인물 실루엣)
		blk("ArtPhoto", 0.5, 0.65, 1, 0.7, rgb(190, 190, 186))
		blk("ArtPhoto", 0.5, 0.18, 1, 0.36, rgb(110, 112, 114))
		blk("ArtHorizon", 0.5, 0.36, 1, 0.01, rgb(240, 240, 238))
		blk("ArtFigure", 0.62 + rnd(seed, 6) * 0.15, 0.32, 0.03, 0.14, rgb(40, 40, 42))
		K:disc("ArtSun", ih * 0.16, 0.005, dcf * CF(-iw * 0.2, ih * 0.15, z + 0.004) * ANG(PI / 2, 0, 0), lk(rgb(236, 236, 232)))
	else
		-- abstract: 원 · 사각 · 아치 (미드센추리)
		local pal = { B.c1, B.c3, lt(B.c2, 0.3), rgb(226, 160, 96), rgb(150, 170, 140) }
		for k = 1, 3 do
			local d = ih * (0.22 + rnd(seed, k) * 0.25)
			K:disc("ArtCircle", d, 0.006, dcf * CF(iw * (rnd(seed, k + 10) - 0.5) * 0.6, ih * (rnd(seed, k + 20) - 0.5) * 0.5, z + 0.002 + k * 0.001) * ANG(PI / 2, 0, 0), lk(pal[(k + idx) % #pal + 1]))
		end
		blk("ArtBlock", 0.3 + rnd(seed, 30) * 0.4, 0.2, 0.3, 0.3, pal[(idx + 3) % #pal + 1])
		K:ring("ArtArc", dcf * CF(0, -ih * 0.2, z + 0.008), iw * 0.25, 0.03, 8, lk(B.c2), 0, PI)
	end
end

-- 바닥 소품 ------------------------------------------------------------------------------------------------

-- 셀프바 (빨대 · 냅킨 · 시럽 · 뚜껑 · 퇴식구). pcf 바닥, +Z = 손님 쪽. w 폭 (깊이 1.5)
local function selfBar(K: any, pcf: CFrame, w: number, B: any)
	local d, h = 1.5, 3.1
	local body = if B.key == "mega" or B.key == "compose" then Look.white elseif B.key == "roastery" or B.key == "concrete" then Look.of(40, 40, 42, Enum.Material.Metal) else Look.offWhite
	local topL = if B.key == "haute" or B.key == "lounge" then Look.marbleWhite elseif B.key == "mega" or B.key == "compose" then Look.of(60, 60, 62, Enum.Material.Slate) else Look.oak
	K:box("SelfBarKick", V3(w - 0.12, 0.3, d - 0.2), pcf * CF(0, 0.15, -0.06), Look.black)
	K:box("SelfBarBody", V3(w, h - 0.42, d), pcf * CF(0, 0.3 + (h - 0.42) / 2, 0), body)
	K:box("SelfBarTop", V3(w + 0.1, 0.12, d + 0.08), pcf * CF(0, h - 0.06, 0.03), topL)
	-- 문짝 + 손잡이
	local nd = math.max(2, math.floor(w / 1.1))
	local dw = (w - 0.1) / nd
	for i = 1, nd do
		local x = -w / 2 + 0.05 + dw * (i - 0.5)
		K:box("SelfBarDoor", V3(dw - 0.06, h - 0.62, 0.04), pcf * CF(x, 0.32 + (h - 0.62) / 2, d / 2 + 0.02), lk(dk((body :: any).c, 0.05), (body :: any).m))
		if i < nd then
			K:box("SelfBarHandle", V3(0.05, 0.6, 0.06), pcf * CF(x + dw / 2 - 0.16, h - 0.75, d / 2 + 0.07), Look.brushed)
		end
	end
	-- 퇴식구 (오른쪽 문: 동그란 투입구 + 글자)
	local rx = w / 2 - 0.05 - dw / 2
	K:cyl("SelfBarSlot", 0.06, 0.6, pcf * CF(rx, h - 0.85, d / 2 + 0.05) * ANG(0, PI / 2, 0), Look.black)
	K:text("SelfBarSlotLabel", dw * 0.8, 0.22, pcf * CF(rx, h - 1.38, d / 2 + 0.045), "일반쓰레기 · 컵 투입구", { fg = rgb(60, 60, 60), font = F.GothamMedium, d = 0.01 })
	local y = h
	-- 음료 버리는 곳 (스테인리스 싱크 + 그레이트)
	local sx = w / 2 - 0.65
	K:box("SelfBarSink", V3(0.95, 0.04, 0.95), pcf * CF(sx, y + 0.02, -0.05), Look.steel)
	for k = -2, 2 do
		K:box("SelfBarGrate", V3(0.85, 0.03, 0.04), pcf * CF(sx, y + 0.045, -0.05 + k * 0.17), Look.chrome)
	end
	-- 빨대 디스펜서
	local px = -w / 2 + 0.4
	K:box("StrawBox", V3(0.44, 0.8, 0.34), pcf * CF(px, y + 0.4, -0.25), glassL(rgb(236, 240, 242), 0.55))
	K:box("StrawBoxBase", V3(0.48, 0.1, 0.38), pcf * CF(px, y + 0.05, -0.25), Look.black)
	for k = 0, 4 do
		K:vcyl("Straw", 0.75, 0.04, pcf * CF(px - 0.14 + k * 0.07, y + 0.45, -0.25 + (k % 2) * 0.06) * ANG(0.1 * (k - 2), 0, 0.06 * (k - 2)), lk(if k % 2 == 0 then rgb(250, 250, 250) else rgb(30, 30, 30)))
	end
	-- 냅킨 꽂이 · 물티슈
	px += 0.62
	K:box("NapkinHolder", V3(0.52, 0.4, 0.34), pcf * CF(px, y + 0.2, -0.2), Look.brushed)
	K:box("NapkinStack", V3(0.44, 0.08, 0.28), pcf * CF(px, y + 0.43, -0.2), Look.paper)
	-- 시럽 펌프 2
	for k = 0, 1 do
		local bx = px + 0.55 + k * 0.4
		K:vcyl("SyrupBottle", 0.75, 0.3, pcf * CF(bx, y + 0.375, -0.3), lk(if k == 0 then rgb(170, 110, 50) else rgb(230, 220, 200), M.Glass, { t = 0.2 }))
		K:vcyl("SyrupPump", 0.24, 0.12, pcf * CF(bx, y + 0.87, -0.3), Look.black)
		K:box("SyrupNozzle", V3(0.05, 0.05, 0.22), pcf * CF(bx, y + 0.98, -0.2), Look.black)
		K:text("SyrupLabel", 0.26, 0.16, pcf * CF(bx, y + 0.35, -0.149), if k == 0 then "시럽" else "헤이즐넛", { fg = rgb(40, 40, 40), bg = rgb(250, 250, 246), d = 0.01, font = F.GothamBold })
	end
	-- 뚜껑 · 컵 슬리브
	local lx = px + 1.42
	if lx < sx - 0.7 then
		K:vcyl("LidStack", 0.32, 0.38, pcf * CF(lx, y + 0.16, 0.1), lk(rgb(250, 250, 250), M.Glass, { t = 0.25 }))
		K:vcyl("SleeveStack", 0.42, 0.34, pcf * CF(lx, y + 0.21, -0.35), Look.kraft)
	end
	-- 뒤판 + 안내
	K:plate("SelfBarSplash", w, 1.45, 0.04, pcf * CF(0, y + 0.725, -d / 2 + 0.0) * CF(0, 0, -0.06), lk(dk(topL.c, 0.06), topL.m))
	K:text("SelfBarSign", w * 0.8, 0.32, pcf * CF(0, y + 1.22, -d / 2 + 0.0), "SELF BAR  빨대 · 냅킨 · 시럽", { fg = B.ink, bg = B.paper, d = 0.02, font = F.GothamBold })
	K:text("SelfBarSink", 0.9, 0.18, pcf * CF(sx, y + 0.28, -d / 2 + 0.01), "남은 음료 · 얼음 버리는 곳", { fg = rgb(255, 255, 255), bg = rgb(50, 120, 200), d = 0.01, font = F.GothamBold })
end

-- MD 선반 (원두 · 드립백 · 텀블러 · 머그). pcf 바닥, w 폭, h 높이
local function mdShelf(K: any, pcf: CFrame, w: number, h: number, B: any)
	local d = 1.1
	local wood = if B.key == "roastery" or B.key == "concrete" then Look.of(40, 40, 42, Enum.Material.Metal) else Look.oak
	local shelfL = if B.key == "roastery" or B.key == "concrete" then Look.walnut else wood
	for _, sx in { -1, 1 } do
		K:box("MDSide", V3(0.1, h, d), pcf * CF(sx * (w / 2 - 0.05), h / 2, 0), wood)
	end
	K:box("MDBack", V3(w - 0.2, h - 0.1, 0.04), pcf * CF(0, h / 2, -d / 2 + 0.03), lk(dk((shelfL :: any).c, 0.2), (shelfL :: any).m))
	local ns = 4
	local seed = B.seed
	local bag = lk(rgb(196, 160, 112), M.Cardboard)
	local cols = { B.c1, rgb(250, 250, 248), rgb(30, 30, 32), rgb(150, 170, 150), B.c3 }
	for i = 0, ns do
		local y = 0.18 + (h - 0.4) * i / ns
		K:box("MDShelfBoard", V3(w - 0.2, 0.08, d - 0.06), pcf * CF(0, y, 0.02), shelfL)
		if i < ns then
			local yy = y + 0.04
			local inner = w - 0.4
			if i == 0 then
				local n = math.max(2, math.floor(inner / 0.75))
				for k = 1, n do
					local x = -inner / 2 + inner * (k - 0.5) / n
					local bh = 0.5 + rnd(seed, k) * 0.1
					K:box("DripBox", V3(0.6, bh, 0.42), pcf * CF(x, yy + bh / 2, 0.05), lk(cols[(k % #cols) + 1]))
					K:text("DripBoxLabel", 0.5, 0.2, pcf * CF(x, yy + bh * 0.6, 0.265), "DRIP BAG\n10입", { fg = if k % #cols == 1 then rgb(255, 255, 255) else rgb(30, 30, 30), d = 0.005, font = F.GothamBold })
				end
			elseif i == 1 then
				local n = math.max(2, math.floor(inner / 0.62))
				for k = 1, n do
					local x = -inner / 2 + inner * (k - 0.5) / n
					K:box("BeanBag", V3(0.48, 0.72, 0.3), pcf * CF(x, yy + 0.36, 0.08), bag)
					K:box("BeanBagFold", V3(0.5, 0.1, 0.32), pcf * CF(x, yy + 0.75, 0.08), lk(rgb(170, 134, 90), M.Cardboard))
					K:plate("BeanBagLabel", 0.36, 0.3, 0.01, pcf * CF(x, yy + 0.4, 0.23), lk(cols[(k + 1) % #cols + 1]))
					if hi(K) then
						K:cyl("BeanBagValve", 0.02, 0.08, pcf * CF(x, yy + 0.6, 0.235) * ANG(0, PI / 2, 0), Look.black)
					end
				end
			elseif i == 2 then
				local n = math.max(2, math.floor(inner / 0.5))
				for k = 1, n do
					local x = -inner / 2 + inner * (k - 0.5) / n
					if k % 3 == 0 then
						K:vcyl("Mug", 0.4, 0.38, pcf * CF(x, yy + 0.2, 0.05), lk(cols[k % #cols + 1]))
						K:box("MugHandle", V3(0.06, 0.24, 0.08), pcf * CF(x + 0.22, yy + 0.2, 0.05), lk(cols[k % #cols + 1]))
					else
						K:vcyl("Tumbler", 0.82, 0.32, pcf * CF(x, yy + 0.41, 0.05), lk(cols[k % #cols + 1], M.Metal))
						K:vcyl("TumblerLid", 0.14, 0.34, pcf * CF(x, yy + 0.89, 0.05), if k % 2 == 0 then Look.black else Look.chrome)
					end
				end
			else
				Props.potPlant(K, pcf * CF(-inner / 2 + 0.35, yy, 0.05), 0.42, 0.6)
				K:box("GiftSet", V3(1.0, 0.45, 0.6), pcf * CF(0.2, yy + 0.225, 0.05), lk(B.c2))
				K:plate("GiftRibbon", 0.08, 0.46, 0.01, pcf * CF(0.2, yy + 0.225, 0.35), lk(B.c3))
				K:text("GiftLabel", 0.9, 0.16, pcf * CF(0.2, yy + 0.32, 0.36), "GIFT SET 29,000", { fg = rgb(255, 255, 255), d = 0.005, font = F.GothamBold })
			end
			if hi(K) then
				K:text("MDPriceStrip", w - 0.3, 0.07, pcf * CF(0, y - 0.005, d / 2 - 0.02), if i == 1 then "원두 200g  16,000~19,000" elseif i == 2 then "텀블러 25,000 · 머그 15,000" elseif i == 0 then "드립백 10입 15,000" else "" , { fg = rgb(30, 30, 30), bg = rgb(250, 250, 246), d = 0.005, font = F.GothamMedium })
			end
		end
	end
	K:text("MDHeader", w - 0.3, 0.32, pcf * CF(0, h + 0.18, 0), if B.key == "roastery" then "BEANS & GOODS" else "MD · 원두 · 텀블러", { fg = B.ink, bg = B.paper, d = 0.04, font = F.GothamBold })
end

-- 냉장 쇼케이스 (케이크 · 디저트, 세로형 유리문). 반환 문 Model, 경첩(월드)
local function cakeFridge(K: any, pcf: CFrame, w: number, B: any, title: string): (Model?, Vector3?)
	local d, h = 2.0, 6.2
	local body = lk(B.c2 or rgb(40, 36, 34), M.Metal)
	K:box("CakeFridgeBase", V3(w, 1.5, d), pcf * CF(0, 0.75, 0), body)
	K:box("CakeFridgeKick", V3(w - 0.1, 0.3, 0.06), pcf * CF(0, 0.15, d / 2 + 0.02), Look.black)
	K:plate("CakeFridgeVent", w * 0.6, 0.3, 0.02, faceCF((pcf * CF(0, 0.6, d / 2 + 0.01)).Position, pcf.ZVector), lk(rgb(70, 70, 74), M.DiamondPlate))
	-- 유리 몸체 (옆 · 뒤 판 + 위 헤더)
	K:box("CakeFridgeBack", V3(w, h - 2.1, 0.1), pcf * CF(0, 1.5 + (h - 2.1) / 2, -d / 2 + 0.05), Look.mirror)
	for _, sx in { -1, 1 } do
		K:box("CakeFridgePost", V3(0.1, h - 2.1, d), pcf * CF(sx * (w / 2 - 0.05), 1.5 + (h - 2.1) / 2, 0), glassL(rgb(220, 232, 236), 0.6))
		K:box("CakeFridgeEdge", V3(0.06, h - 2.1, 0.08), pcf * CF(sx * (w / 2 - 0.03), 1.5 + (h - 2.1) / 2, d / 2 - 0.04), body)
	end
	K:box("CakeFridgeHead", V3(w, 0.6, d), pcf * CF(0, h - 0.3, 0), body)
	K:text("CakeFridgeTitle", w - 0.3, 0.38, pcf * CF(0, h - 0.3, d / 2 + 0.005), title, { fg = rgb(255, 255, 255), glow = 1.2, font = F.GothamBold, d = 0.01 })
	local lamp = K:box("CakeFridgeLamp", V3(w - 0.3, 0.05, 0.12), pcf * CF(0, h - 0.65, d / 2 - 0.3), Look.lampNeutral)
	K:light(lamp, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 6, Brightness = 0.6, Angle = 120, Color = Look.neutralLight })
	-- 선반 3 + 케이크
	local cakeCols = { { rgb(250, 246, 240), rgb(220, 30, 50) }, { rgb(84, 50, 34), rgb(240, 220, 200) }, { rgb(250, 230, 150), rgb(250, 250, 240) }, { rgb(240, 200, 210), rgb(250, 250, 250) }, { rgb(140, 180, 100), rgb(250, 250, 240) } }
	for i = 0, 2 do
		local y = 1.5 + 0.1 + i * 1.32
		K:box("CakeShelf", V3(w - 0.2, 0.04, d - 0.3), pcf * CF(0, y, -0.05), glassL(rgb(230, 240, 240), 0.5))
		local n = math.max(1, math.floor((w - 0.3) / 0.95))
		for k = 1, n do
			local x = -(w - 0.3) / 2 + (w - 0.3) * (k - 0.5) / n
			local cc = cakeCols[(i * 2 + k) % #cakeCols + 1]
			local c = pcf * CF(x, y + 0.02, 0.0)
			K:disc("CakeBoard", 0.82, 0.03, c * CF(0, 0.015, 0), Look.goldMetal)
			if (i + k) % 3 == 0 then
				-- 조각 케이크 3개
				for j = 0, 2 do
					K:wedge("CakeSlice", V3(0.22, 0.4, 0.34), c * CF((j - 1) * 0.26, 0.23, 0) * ANG(0, PI / 2, 0), lk(cc[1]))
					K:ball("CakeTopping", 0.1, c * CF((j - 1) * 0.26, 0.45, 0.06), lk(cc[2]))
				end
			else
				K:vcyl("Cake", 0.48, 0.74, c * CF(0, 0.27, 0), lk(cc[1]))
				K:vcyl("CakeCream", 0.06, 0.76, c * CF(0, 0.5, 0), lk(lt(cc[1], 0.4)))
				if hi(K) then
					for j = 0, 5 do
						local a = j * PI / 3
						K:ball("CakeTopping", 0.12, c * CF(math.cos(a) * 0.26, 0.56, math.sin(a) * 0.26), lk(cc[2]))
					end
				else
					K:ball("CakeTopping", 0.16, c * CF(0, 0.56, 0), lk(cc[2]))
				end
			end
			K:text("CakeTag", 0.42, 0.14, pcf * CF(x, y + 0.1, d / 2 - 0.22), if i == 0 then "8,500" elseif i == 1 then "7,500" else "32,000", { fg = rgb(40, 40, 40), bg = rgb(252, 250, 244), d = 0.01, font = F.GothamBold })
		end
	end
	-- 앞 유리문
	local hingeL = pcf * CF(-w / 2 + 0.06, 0, d / 2 + 0.04)
	local door = K:group("CakeFridgeDoor", function()
		K:box("CakeDoorGlass", V3(w - 0.14, h - 2.15, 0.05), pcf * CF(0, 1.5 + (h - 2.1) / 2, d / 2 + 0.04), glassL(rgb(220, 236, 240), 0.72))
		K:box("CakeDoorFrame", V3(w - 0.12, 0.08, 0.07), pcf * CF(0, 1.53, d / 2 + 0.04), body)
		K:box("CakeDoorFrame", V3(w - 0.12, 0.08, 0.07), pcf * CF(0, h - 0.64, d / 2 + 0.04), body)
		K:box("CakeDoorHandle", V3(0.07, 1.6, 0.1), pcf * CF(w / 2 - 0.25, 3.6, d / 2 + 0.12), Look.chrome)
	end)
	return door, (K.cf * hingeL).Position
end

-- 음료 병 (몸통 · 어깨 · 뚜껑 · 라벨)
local function bottle(K: any, base: CFrame, h: number, d: number, liquid: Color3, cap: Color3, label: Color3?)
	K:vcyl("Bottle", h * 0.7, d, base * CF(0, h * 0.35, 0), lk(liquid, M.Glass, { t = 0.2 }))
	K:vcyl("BottleShoulder", h * 0.14, d * 0.62, base * CF(0, h * 0.77, 0), lk(liquid, M.Glass, { t = 0.2 }))
	K:vcyl("BottleCap", h * 0.09, d * 0.4, base * CF(0, h * 0.885, 0), lk(cap))
	if label then
		K:vcyl("BottleLabel", h * 0.24, d + 0.012, base * CF(0, h * 0.4, 0), lk(label))
	end
end

-- 음료 냉장고 (유리문 1칸: 생수 · 주스 · 우유 · 콜드브루 · 샌드위치). 반환 문 Model, 경첩(월드)
local function drinkFridge(K: any, pcf: CFrame, w: number, B: any, header: string): (Model?, Vector3?)
	local d, h = 2.0, 6.4
	local body = lk(rgb(38, 38, 42), M.Metal)
	K:box("FridgeBack", V3(w, h, 0.1), pcf * CF(0, h / 2, -d / 2 + 0.05), body)
	for _, sx in { -1, 1 } do
		K:box("FridgeSide", V3(0.1, h, d), pcf * CF(sx * (w / 2 - 0.05), h / 2, 0), body)
	end
	K:box("FridgeTop", V3(w, 0.75, d), pcf * CF(0, h - 0.375, 0), body)
	K:box("FridgeBottom", V3(w, 0.62, d), pcf * CF(0, 0.31, 0), body)
	K:text("FridgeHeader", w - 0.24, 0.5, faceCF((pcf * CF(0, h - 0.375, d / 2 + 0.01)).Position, pcf.ZVector), header, { fg = B.ink, bg = B.c1, glow = 1.1, font = F.GothamBlack, d = 0.01 })
	K:plate("FridgeGrille", w - 0.5, 0.3, 0.02, faceCF((pcf * CF(0, 0.3, d / 2 + 0.01)).Position, pcf.ZVector), lk(rgb(64, 64, 68), M.DiamondPlate))
	local ih = h - 1.37
	local iy = 0.62 + ih / 2
	K:box("FridgeLiner", V3(w - 0.2, ih, 0.04), pcf * CF(0, iy, -d / 2 + 0.12), Look.white)
	for _, sx in { -1, 1 } do
		K:box("FridgeLinerSide", V3(0.04, ih, d - 0.3), pcf * CF(sx * (w / 2 - 0.12), iy, -0.05), Look.white)
	end
	local lamp = K:box("FridgeLamp", V3(w - 0.3, 0.05, 0.08), pcf * CF(0, h - 0.8, d / 2 - 0.25), Look.lampCool)
	K:light(lamp, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 6, Brightness = 0.7, Angle = 130, Color = Look.coolLight })
	local ns = 5
	local inner = w - 0.45
	for i = 0, ns - 1 do
		local y = 0.62 + 0.06 + i * ih / ns
		K:box("FridgeShelf", V3(w - 0.3, 0.04, d - 0.4), pcf * CF(0, y, -0.1), Look.chrome)
		K:box("FridgeShelfStrip", V3(w - 0.3, 0.1, 0.02), pcf * CF(0, y - 0.03, d / 2 - 0.31), lk(B.c1))
		local function slot(k: number, n: number): CFrame
			return pcf * CF(-inner / 2 + inner * (k - 0.5) / n, y + 0.02, 0.2)
		end
		if i == 0 then
			for k = 1, 4 do
				bottle(K, slot(k, 4), 0.95, 0.36, rgb(214, 232, 240), rgb(40, 110, 220), rgb(230, 240, 250))
			end
		elseif i == ns - 1 then
			for k = 1, 3 do
				local c = slot(k, 3)
				K:box("SandwichPack", V3(0.5, 0.42, 0.2), c * CF(0, 0.21, 0), glassL(rgb(240, 244, 246), 0.55))
				K:wedge("SandwichBread", V3(0.16, 0.36, 0.44), c * CF(0, 0.19, 0) * ANG(0, PI / 2, 0), lk(rgb(236, 210, 160)))
				K:box("SandwichFill", V3(0.44, 0.06, 0.17), c * CF(0, 0.12, 0), lk(if k == 2 then rgb(240, 160, 160) else rgb(130, 180, 90)))
			end
		else
			local kinds = { { rgb(250, 150, 40), rgb(250, 250, 250), rgb(250, 200, 60) }, { rgb(60, 36, 24), rgb(20, 20, 20), rgb(230, 220, 200) }, { rgb(248, 248, 244), rgb(60, 140, 220), rgb(90, 160, 230) }, { rgb(200, 30, 40), rgb(220, 220, 220), rgb(200, 30, 40) } }
			local kd = kinds[(i - 1) % #kinds + 1]
			local n = if hi(K) then 5 else 3
			for k = 1, n do
				bottle(K, slot(k, n), 0.85, 0.28, kd[1], kd[2], kd[3])
			end
		end
	end
	local hinge = pcf * CF(-w / 2 + 0.06, 0, d / 2 + 0.05)
	local door = K:group("FridgeGlassDoor", function()
		local c = pcf * CF(0, iy, d / 2 + 0.05)
		K:box("FridgeDoorGlass", V3(w - 0.2, ih, 0.04), c, glassL(rgb(214, 232, 238), 0.78))
		K:box("FridgeDoorBar", V3(w - 0.12, 0.12, 0.08), c * CF(0, ih / 2, 0), body)
		K:box("FridgeDoorBar", V3(w - 0.12, 0.12, 0.08), c * CF(0, -ih / 2, 0), body)
		K:box("FridgeDoorBar", V3(0.12, ih, 0.08), c * CF(-w / 2 + 0.12, 0, 0), body)
		K:box("FridgeDoorBar", V3(0.12, ih, 0.08), c * CF(w / 2 - 0.12, 0, 0), body)
		K:box("FridgeDoorHandle", V3(0.08, ih * 0.55, 0.12), c * CF(w / 2 - 0.3, 0, 0.1), Look.chrome)
	end)
	return door, (K.cf * hinge).Position
end

-- 계산대 앞 로고 (판 + 글자 또는 금속 글자)
local function counterLogo(K: any, V: any, g: any, B: any)
	local n = custDir(V, g)
	local body = g.body or g.top
	if not body then
		return
	end
	local alongX = math.abs(n.Z) > 0.5
	local len = if alongX then body.size.X else body.size.Z
	if len < 3 then
		return
	end
	local c = (body.min + body.max) / 2
	local fp = if alongX then V3(c.X, 0, if n.Z > 0 then body.max.Z else body.min.Z) else V3(if n.X > 0 then body.max.X else body.min.X, 0, c.Z)
	local top = if g.top then g.top.min.Y else g.y
	local dcf = faceCF(fp + n * 0.2 + V3(0, top * 0.56, 0), n)
	local font = if B.key == "haute" or B.key == "bakery" or B.key == "pascucci" then F.Garamond elseif B.key == "roastery" or B.key == "concrete" then F.Oswald elseif B.type == "dessert" then F.FredokaOne else F.GothamBlack
	K:free(function()
		if B.logoPlate then
			K:panel("CounterLogoPlate", 2.7, 0.92, 0.05, 0.22, dcf, B.logoPlate)
			K:text("CounterLogo", 2.4, 0.62, dcf * CF(0, 0, 0.06), B.logo, { fg = B.logoFg, font = font, d = 0.01 })
		else
			local lw = math.min(4.0, len * 0.32)
			K:text("CounterLogo", lw, 0.55, dcf, B.logo, { fg = B.logoFg or B.c3, font = font, d = 0.03 })
		end
	end)
end

-- 커피 로스터 (드럼 · 호퍼 · 냉각 트레이 · 연통 · 사이클론 · 제어반). 반환 { glass, arms, armBase, panel, screen }
local function roaster(K: any, pcf: CFrame, B: any): any
	local V = K.V
	local body = lk(rgb(32, 32, 34), M.Metal)
	local acc = lk(B.c3 or rgb(200, 110, 50), M.Metal, { r = 0.1 })
	local out: any = {}
	K:box("RoasterPlinth", V3(2.3, 0.14, 2.0), pcf * CF(-0.55, 0.07, -0.3), Look.black)
	K:box("RoasterBase", V3(2.1, 2.3, 1.8), pcf * CF(-0.55, 1.29, -0.3), body)
	K:plate("RoasterBasePanel", 1.5, 1.4, 0.03, faceCF((pcf * CF(-0.55, 1.25, 0.6)).Position, pcf.ZVector), acc)
	K:cyl("RoasterDrum", 1.9, 1.7, pcf * CF(-0.55, 3.3, -0.35) * ANG(0, PI / 2, 0), body)
	K:cyl("RoasterBand", 0.12, 1.78, pcf * CF(-0.55, 3.3, 0.35) * ANG(0, PI / 2, 0), acc)
	K:cyl("RoasterFace", 0.08, 1.6, pcf * CF(-0.55, 3.3, 0.62) * ANG(0, PI / 2, 0), Look.brushed)
	K:cyl("RoasterDoor", 0.1, 1.05, pcf * CF(-0.55, 3.2, 0.7) * ANG(0, PI / 2, 0), Look.chrome)
	out.glass = K:cyl("RoasterSightGlass", 0.04, 0.34, pcf * CF(-0.2, 3.62, 0.72) * ANG(0, PI / 2, 0), lk(rgb(120, 70, 40), M.Glass, { t = 0.2 }))
	K:bar("RoasterDoorHandle", (pcf * CF(-0.55, 3.2, 0.78)).Position, (pcf * CF(0.1, 3.0, 0.82)).Position, 0.08, 0.08, Look.black)
	K:cyl("RoasterTrier", 0.36, 0.1, pcf * CF(-0.95, 3.55, 0.8) * ANG(0, PI / 2, 0), Look.walnut)
	-- 배출 슈트
	K:wedge("RoasterChute", V3(0.6, 0.35, 0.6), pcf * CF(0.0, 2.55, 0.62) * ANG(0, PI / 2, 0), Look.brushed)
	-- 호퍼 (깔때기)
	K:vcyl("RoasterHopperNeck", 0.5, 0.34, pcf * CF(-0.55, 4.4, -0.35), Look.chrome)
	K:vcyl("RoasterHopperLow", 0.35, 0.7, pcf * CF(-0.55, 4.8, -0.35), Look.chrome)
	K:vcyl("RoasterHopper", 0.6, 1.1, pcf * CF(-0.55, 5.25, -0.35), Look.chrome)
	K:disc("RoasterHopperBeans", 1.0, 0.04, pcf * CF(-0.55, 5.54, -0.35), lk(rgb(150, 170, 96), M.Pebble))
	-- 연통 (천장까지)
	K:free(function()
		K:seg("RoasterFlue", pcf * V3(-0.55, 3.9, -1.05), pcf * V3(-0.55, V.H - 0.05, -1.05), 0.42, Look.brushed)
		K:seg("RoasterFlueJoint", pcf * V3(-0.55, 3.3, -1.05), pcf * V3(-0.55, 3.95, -1.05), 0.5, Look.brushed)
		K:disc("RoasterFlueCollar", 0.7, 0.08, CF(pcf * V3(-0.55, V.H - 0.05, -1.05)), Look.brushed)
	end)
	-- 냉각 트레이 (교반 날개 회전)
	local trayC = pcf * CF(0.95, 2.05, 0.35)
	K:vcyl("CoolingStand", 1.8, 0.5, pcf * CF(0.95, 0.9, 0.35), body)
	K:disc("CoolingTray", 1.85, 0.32, trayC, Look.steel)
	K:disc("CoolingBeans", 1.7, 0.04, trayC * CF(0, 0.15, 0), lk(rgb(86, 52, 32), M.Pebble))
	K:vcyl("CoolingHub", 0.28, 0.16, trayC * CF(0, 0.3, 0), Look.chrome)
	local a1 = K:box("CoolingArm", V3(1.6, 0.06, 0.07), trayC * CF(0, 0.22, 0), Look.chrome)
	local a2 = K:box("CoolingArm", V3(1.6, 0.06, 0.07), trayC * CF(0, 0.22, 0) * ANG(0, PI / 2, 0), Look.chrome)
	out.arms = { a1, a2 }
	out.armBase = { a1.CFrame, a2.CFrame }
	out.center = (K.cf * trayC).Position
	-- 사이클론 (채프 수집기)
	K:vcyl("ChaffCyclone", 1.4, 0.8, pcf * CF(1.25, 4.1, -0.95), body)
	K:vcyl("ChaffCone", 0.5, 0.45, pcf * CF(1.25, 3.15, -0.95), body)
	K:vcyl("ChaffBin", 0.6, 0.6, pcf * CF(1.25, 0.3, -0.95), Look.brushed)
	K:seg("ChaffPipe", pcf * V3(-0.2, 3.9, -0.9), pcf * V3(0.9, 4.5, -0.95), 0.2, Look.brushed)
	-- 제어반 (화면 + 계기)
	local pc = pcf * CF(0.95, 3.65, 0.2)
	out.panel = K:box("RoasterPanel", V3(0.95, 0.95, 0.2), pc, body)
	local dcfP = faceCF((pc * CF(0, 0, 0.1)).Position, pcf.ZVector)
	local scr, lab = K:text("RoasterScreen", 0.7, 0.36, dcfP * CF(0, 0.18, 0.01), "STANDBY\nBT 25℃", { fg = rgb(120, 255, 160), bg = rgb(8, 14, 10), glow = 1.3, font = F.Code, d = 0.01 })
	out.screen, out.label = scr, lab
	for k = -1, 1 do
		wdisc(K, "RoasterGauge", 0.2, 0.03, dcfP * CF(k * 0.26, -0.22, 0.0), Look.white)
	end
	K:text("RoasterBadge", 1.2, 0.22, faceCF((pcf * CF(-0.55, 1.95, 0.64)).Position, pcf.ZVector), "LAB ROASTER 12kg", { fg = rgb(240, 240, 236), font = F.GothamBold, d = 0.01 })
	return out
end

-- 생두 자루 (팔레트 위 마대)
local function beanSacks(K: any, pcf: CFrame, w: number)
	K:box("PalletTop", V3(w, 0.12, 1.7), pcf * CF(0, 0.42, 0), Look.pine)
	for k = -1, 1 do
		K:box("PalletBlock", V3(w, 0.3, 0.22), pcf * CF(0, 0.18, k * 0.7), Look.pine)
	end
	local origin = { "ETHIOPIA\nYIRGACHEFFE", "COLOMBIA\nHUILA", "KENYA AA", "GUATEMALA\nANTIGUA", "BRAZIL\nCERRADO" }
	local n = math.max(2, math.floor(w / 1.05))
	for k = 1, n do
		local x = -w / 2 + w * (k - 0.5) / n
		local c = pcf * CF(x, 0.48, 0.05 + (k % 2) * 0.15)
		K:ell("JuteSack", V3(0.95, 0.75, 1.3), c * CF(0, 0.36, 0) * ANG(0, (k % 3) * 0.15 - 0.15, 0), lk(rgb(176, 146, 100), M.Fabric))
		K:ell("JuteSackTop", V3(0.5, 0.25, 0.6), c * CF(0, 0.74, -0.1), lk(rgb(160, 130, 88), M.Fabric))
		K:text("JuteSackPrint", 0.62, 0.36, faceCF((c * CF(0, 0.38, 0.62)).Position, pcf.ZVector) * ANG(-0.25, 0, 0), origin[(k - 1) % #origin + 1], { fg = rgb(70, 50, 34), font = F.SpecialElite, d = 0.005 })
	end
	if w > 2.2 then
		local c = pcf * CF(0.2, 1.25, 0.1)
		K:ell("JuteSack", V3(0.9, 0.6, 1.2), c * CF(0, 0.2, 0) * ANG(0, 0.4, 0), lk(rgb(186, 156, 108), M.Fabric))
	end
end

-- 데크 오븐 3단 (스테인리스 + 창 안쪽 빵 + 온도 표시)
local function deckOven(K: any, pcf: CFrame, w: number): any
	local d = 2.5
	local steel = lk(rgb(196, 198, 200), M.SmoothPlastic, { r = 0.05 })
	local out: any = { glows = {} }
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			K:box("OvenLeg", V3(0.14, 1.1, 0.14), pcf * CF(sx * (w / 2 - 0.15), 0.55, sz * (d / 2 - 0.15)), steel)
		end
	end
	K:box("OvenRackShelf", V3(w - 0.2, 0.06, d - 0.2), pcf * CF(0, 0.35, 0), steel)
	for k = 0, 2 do
		K:box("OvenSheetPan", V3(w - 0.5, 0.04, d - 0.6), pcf * CF(0, 0.45 + k * 0.18, 0), Look.alu)
	end
	K:box("OvenBody", V3(w, 4.0, d), pcf * CF(0, 1.1 + 2.0, 0), steel)
	K:box("OvenHood", V3(w + 0.1, 0.7, d + 0.2), pcf * CF(0, 5.45, 0.08), lk(rgb(176, 178, 182), M.SmoothPlastic, { r = 0.05 }))
	K:box("OvenHoodLip", V3(w + 0.12, 0.1, 0.1), pcf * CF(0, 5.1, d / 2 + 0.16), Look.brushed)
	local dw = w - 1.1
	for k = 0, 2 do
		local y = 1.1 + 0.2 + k * 1.3 + 0.55
		local dc = faceCF((pcf * CF(-0.45, y, d / 2 + 0.01)).Position, pcf.ZVector)
		K:plate("OvenDoor", dw, 1.05, 0.06, dc, Look.chrome)
		local g = K:plate("OvenGlow", dw - 0.5, 0.48, 0.065, dc * CF(0, 0.08, 0), Look.neon(rgb(255, 150, 70), 0.25))
		table.insert(out.glows, g)
		K:plate("OvenWindow", dw - 0.4, 0.56, 0.075, dc * CF(0, 0.08, 0), glassL(rgb(60, 40, 30), 0.55))
		for j = 0, 2 do
			K:ell("OvenLoaf", V3(0.55, 0.2, 0.3), dc * CF(-0.6 + j * 0.6, -0.08, -0.25), lk(rgb(196, 130, 60)))
		end
		K:bar("OvenHandle", (dc * CF(-dw / 2 + 0.3, -0.38, 0.14)).Position, (dc * CF(dw / 2 - 0.3, -0.38, 0.14)).Position, 0.08, 0.08, Look.black)
		local pc = faceCF((pcf * CF(w / 2 - 0.5, y, d / 2 + 0.01)).Position, pcf.ZVector)
		K:plate("OvenPanel", 0.8, 1.0, 0.04, pc, Look.charcoal)
		K:text("OvenTemp", 0.6, 0.24, pc * CF(0, 0.22, 0.045), if k == 0 then "220℃" elseif k == 1 then "200℃" else "180℃", { fg = rgb(255, 60, 40), bg = rgb(10, 6, 6), glow = 1.5, font = F.Code, d = 0.01 })
		for j = -1, 1 do
			wdisc(K, "OvenKnob", 0.14, 0.05, pc * CF(j * 0.22, -0.2, 0.04), Look.chrome)
		end
	end
	K:text("OvenBadge", 1.6, 0.26, faceCF((pcf * CF(0, 5.45, d / 2 + 0.19)).Position, pcf.ZVector), "DECK OVEN 3단", { fg = rgb(60, 60, 64), font = F.GothamBold, d = 0.01 })
	return out
end

-- 빵 ------------------------------------------------------------------------------------------------------
local BREADS = {
	{ "소금빵", "3,500", "salt" }, { "크루아상", "4,200", "croissant" }, { "단팥빵", "2,800", "bun" }, { "소보로", "2,800", "soboro" },
	{ "우유식빵", "5,500", "loaf" }, { "바게트", "4,500", "baguette" }, { "고로케", "3,000", "goroke" }, { "마늘바게트", "5,000", "garlic" },
	{ "에그타르트", "3,200", "tart" }, { "크림치즈 베이글", "4,500", "bagel" }, { "앙버터", "4,500", "salt" }, { "옥수수빵", "3,200", "bun" },
	{ "치아바타", "4,000", "ciabatta" }, { "명란 바게트", "5,500", "baguette" },
}
local function bread(K: any, pcf: CFrame, kind: string, s: number)
	if kind == "salt" then
		K:ell("Bread", V3(0.6, 0.28, 0.36) * s, pcf * CF(0, 0.13 * s, 0), lk(rgb(216, 154, 72)))
		K:ell("BreadGloss", V3(0.46, 0.1, 0.26) * s, pcf * CF(0, 0.24 * s, 0), lk(rgb(186, 112, 44), M.SmoothPlastic, { r = 0.06 }))
	elseif kind == "croissant" then
		local c = lk(rgb(202, 132, 56))
		K:ell("Croissant", V3(0.46, 0.28, 0.32) * s, pcf * CF(0, 0.13 * s, 0), c)
		for _, sx in { -1, 1 } do
			K:ell("CroissantHorn", V3(0.32, 0.16, 0.18) * s, pcf * CF(sx * 0.28 * s, 0.08 * s, 0.08 * s) * ANG(0, sx * 0.7, 0), c)
		end
		K:ell("CroissantRidge", V3(0.1, 0.27, 0.33) * s, pcf * CF(0.1 * s, 0.14 * s, 0), lk(rgb(176, 104, 40)))
	elseif kind == "baguette" or kind == "garlic" then
		K:ell("Baguette", V3(1.2, 0.22, 0.24) * s, pcf * CF(0, 0.11 * s, 0) * ANG(0, 0.1, 0), lk(if kind == "garlic" then rgb(214, 170, 90) else rgb(204, 144, 64)))
		for i = -1, 1 do
			K:box("BaguetteScore", V3(0.18, 0.02, 0.05) * s, pcf * CF(i * 0.3 * s, 0.215 * s, 0) * ANG(0, 0.1 + 0.6, 0), lk(if kind == "garlic" then rgb(120, 150, 60) else rgb(238, 210, 156)))
		end
	elseif kind == "loaf" then
		K:box("Loaf", V3(0.7, 0.38, 0.44) * s, pcf * CF(0, 0.19 * s, 0), lk(rgb(234, 204, 156)))
		for i = -1, 1 do
			K:ell("LoafTop", V3(0.25, 0.22, 0.44) * s, pcf * CF(i * 0.22 * s, 0.38 * s, 0), lk(rgb(178, 106, 44)))
		end
	elseif kind == "ciabatta" then
		K:ell("Ciabatta", V3(0.8, 0.2, 0.46) * s, pcf * CF(0, 0.09 * s, 0), lk(rgb(226, 196, 150), M.Sand))
	elseif kind == "soboro" then
		K:ell("Soboro", V3(0.52, 0.26, 0.52) * s, pcf * CF(0, 0.12 * s, 0), lk(rgb(214, 164, 92), M.Sand))
	elseif kind == "goroke" then
		K:ell("Goroke", V3(0.56, 0.26, 0.36) * s, pcf * CF(0, 0.12 * s, 0), lk(rgb(190, 120, 50), M.Sand))
	elseif kind == "tart" then
		K:disc("TartCrust", 0.42 * s, 0.14 * s, pcf * CF(0, 0.07 * s, 0), lk(rgb(220, 170, 96)))
		K:disc("TartCustard", 0.34 * s, 0.03 * s, pcf * CF(0, 0.14 * s, 0), lk(rgb(250, 206, 80)))
		K:disc("TartBurn", 0.12 * s, 0.032 * s, pcf * CF(0.05 * s, 0.142 * s, 0.03 * s), lk(rgb(150, 86, 30)))
	elseif kind == "bagel" then
		K:disc("Bagel", 0.5 * s, 0.18 * s, pcf * CF(0, 0.09 * s, 0), lk(rgb(200, 140, 70)))
		K:disc("BagelHole", 0.14 * s, 0.185 * s, pcf * CF(0, 0.09 * s, 0), lk(rgb(90, 60, 36)))
	else
		K:ell("Bun", V3(0.48, 0.26, 0.48) * s, pcf * CF(0, 0.12 * s, 0), lk(rgb(178, 104, 40), M.SmoothPlastic, { r = 0.05 }))
		K:ball("BunSesame", 0.06 * s, pcf * CF(0, 0.25 * s, 0), lk(rgb(30, 24, 20)))
	end
end

-- 바구니 (등나무 테 + 유산지)
local function basket(K: any, pcf: CFrame, w: number, d: number, look: any)
	K:box("BasketBase", V3(w, 0.06, d), pcf * CF(0, 0.03, 0), look)
	K:box("BasketRim", V3(w, 0.16, 0.06), pcf * CF(0, 0.1, d / 2 - 0.03), look)
	K:box("BasketRim", V3(w, 0.16, 0.06), pcf * CF(0, 0.1, -d / 2 + 0.03), look)
	K:box("BasketRim", V3(0.06, 0.16, d - 0.12), pcf * CF(w / 2 - 0.03, 0.1, 0), look)
	K:box("BasketRim", V3(0.06, 0.16, d - 0.12), pcf * CF(-w / 2 + 0.03, 0.1, 0), look)
	K:box("BasketPaper", V3(w - 0.14, 0.02, d - 0.14), pcf * CF(0, 0.07, 0), Look.paper)
end

-- 가격표 (작은 판)
local function tag(K: any, dcf: CFrame, w: number, h: number, text: string, bg: Color3?, fg: Color3?)
	K:text("PriceTag", w, h, dcf, text, { fg = fg or rgb(30, 30, 30), bg = bg or rgb(252, 250, 244), d = 0.012, font = F.GothamBold })
end

-- 페이스트리 (진열장 안): kind 로 모양
local function pastry(K: any, pcf: CFrame, kind: string, s: number)
	if kind == "croissant" or kind == "salt" or kind == "tart" or kind == "bagel" then
		bread(K, pcf, kind, s)
	elseif kind == "muffin" then
		K:vcyl("MuffinCup", 0.22 * s, 0.34 * s, pcf * CF(0, 0.11 * s, 0), lk(rgb(240, 236, 226)))
		K:ell("MuffinTop", V3(0.42, 0.26, 0.42) * s, pcf * CF(0, 0.24 * s, 0), lk(rgb(120, 72, 40)))
	elseif kind == "macaron" then
		local cols = { rgb(250, 190, 206), rgb(190, 230, 200), rgb(250, 230, 150), rgb(200, 180, 240) }
		for k = 0, 2 do
			local c = pcf * CF((k - 1) * 0.2 * s, 0, 0)
			local col = cols[(k + math.floor(s * 10)) % #cols + 1]
			K:disc("MacaronShell", 0.18 * s, 0.05 * s, c * CF(0, 0.025 * s, 0), lk(col))
			K:disc("MacaronFill", 0.16 * s, 0.03 * s, c * CF(0, 0.065 * s, 0), lk(rgb(250, 246, 236)))
			K:disc("MacaronShell", 0.18 * s, 0.05 * s, c * CF(0, 0.105 * s, 0), lk(col))
		end
	elseif kind == "cake" then
		K:box("CakeSlice", V3(0.34, 0.3, 0.42) * s, pcf * CF(0, 0.15 * s, 0), lk(rgb(250, 240, 220)))
		K:box("CakeLayer", V3(0.345, 0.04, 0.425) * s, pcf * CF(0, 0.15 * s, 0), lk(rgb(220, 60, 80)))
		K:ball("CakeBerry", 0.12 * s, pcf * CF(0, 0.33 * s, 0), lk(rgb(220, 30, 50)))
	elseif kind == "cookie" then
		for k = 0, 2 do
			K:disc("Cookie", 0.3 * s, 0.05 * s, pcf * CF((k - 1) * 0.12 * s, 0.03 * s + k * 0.045 * s, 0) * ANG(0.12 * (k - 1), 0, 0.08), lk(rgb(196, 140, 76)))
		end
	elseif kind == "financier" then
		for k = 0, 1 do
			K:box("Financier", V3(0.32, 0.12, 0.16) * s, pcf * CF(0, 0.06 * s, (k - 0.5) * 0.2 * s), lk(rgb(206, 150, 76)))
		end
	else
		K:ell("Scone", V3(0.4, 0.24, 0.4) * s, pcf * CF(0, 0.11 * s, 0), lk(rgb(220, 176, 110), M.Sand))
	end
end
local PASTRIES = {
	{ "크루아상", "4,200", "croissant" }, { "블루베리 머핀", "3,800", "muffin" }, { "마카롱", "3,000", "macaron" }, { "딸기 케이크", "7,500", "cake" },
	{ "초코칩 쿠키", "2,800", "cookie" }, { "휘낭시에", "3,000", "financier" }, { "소금빵", "3,800", "salt" }, { "스콘", "3,500", "scone" },
	{ "에그타르트", "3,200", "tart" }, { "베이글", "3,500", "bagel" },
}

-- 카운터 위 소품 ----------------------------------------------------------------------------------------
local function pagerTower(K: any, pcf: CFrame, n: number, c: Color3)
	K:box("PagerBase", V3(0.66, 0.14, 0.66), pcf * CF(0, 0.07, 0), Look.black)
	K:box("PagerBaseLED", V3(0.3, 0.03, 0.02), pcf * CF(0, 0.08, 0.335), Look.ledGreen)
	for i = 1, n do
		local y = 0.14 + 0.1 * (i - 0.5)
		K:box("Pager", V3(0.56, 0.08, 0.56), pcf * CF(0, y, 0) * ANG(0, (i % 2) * 0.05, 0), lk(if i % 2 == 0 then rgb(250, 250, 248) else c))
		K:box("PagerLED", V3(0.12, 0.03, 0.02), pcf * CF(0.12, y, 0.29), Look.ledRed)
	end
	K:text("PagerNo", 0.36, 0.16, topCF((pcf * CF(0, 0.15 + 0.1 * n, 0)).Position, pcf.ZVector * -1), tostring(10 + n), { fg = rgb(40, 40, 40), d = 0.005, font = F.GothamBold })
end

local function cookieJar(K: any, pcf: CFrame, c: Color3, label: string)
	K:vcyl("CookieJar", 0.7, 0.5, pcf * CF(0, 0.35, 0), glassL(rgb(236, 242, 244), 0.6))
	K:vcyl("CookieJarLid", 0.1, 0.52, pcf * CF(0, 0.75, 0), Look.walnut)
	K:ball("CookieJarKnob", 0.12, pcf * CF(0, 0.82, 0), Look.walnut)
	for k = 0, 3 do
		K:disc("JarCookie", 0.36, 0.06, pcf * CF((k % 2) * 0.04 - 0.02, 0.08 + k * 0.1, 0) * ANG(0.2 * (k % 2), 0, 0.15), lk(c))
	end
	tag(K, facing((pcf * CF(0, 0.3, 0.26)).Position, pcf.ZVector), 0.4, 0.16, label)
end

local function cakeDome(K: any, pcf: CFrame, c: Color3)
	K:disc("DomeStand", 0.8, 0.04, pcf * CF(0, 0.02, 0), Look.white)
	K:vcyl("DomeStem", 0.25, 0.12, pcf * CF(0, 0.15, 0), Look.white)
	K:disc("DomePlate", 0.86, 0.04, pcf * CF(0, 0.29, 0), Look.white)
	K:vcyl("DomeCake", 0.32, 0.56, pcf * CF(0, 0.47, 0), lk(c))
	K:vcyl("DomeCakeCream", 0.05, 0.58, pcf * CF(0, 0.62, 0), Look.white)
	K:ell("DomeGlass", V3(0.8, 0.8, 0.8), pcf * CF(0, 0.55, 0), glassL(rgb(236, 242, 244), 0.75))
	K:ball("DomeKnob", 0.08, pcf * CF(0, 0.97, 0), Look.chrome)
end

local function flowerVase(K: any, pcf: CFrame, B: any)
	K:vcyl("Vase", 0.5, 0.28, pcf * CF(0, 0.25, 0), glassL(rgb(220, 236, 236), 0.4))
	local cols = { B.c1, rgb(250, 250, 246), rgb(250, 200, 120), lt(B.c1, 0.4) }
	for k = 0, 6 do
		local a = k * 2 * PI / 7
		local tip = pcf * V3(math.cos(a) * 0.22, 0.95 + (k % 3) * 0.1, math.sin(a) * 0.22)
		K:seg("FlowerStem", pcf * V3(0, 0.45, 0), tip, 0.025, Look.leafDark)
		K:ball("FlowerHead", 0.17 + (k % 2) * 0.05, CF(tip), lk(cols[k % #cols + 1], M.Fabric))
	end
end

local function standSign(K: any, pcf: CFrame, w: number, h: number, text: string, fg: Color3, bg: Color3)
	K:box("StandSignFoot", V3(w * 0.7, 0.05, 0.3), pcf * CF(0, 0.025, 0), Look.acrylicWhite)
	K:text("StandSign", w, h, pcf * CF(0, 0.05 + h / 2, 0) * ANG(math.rad(-6), 0, 0), text, { fg = fg, bg = bg, d = 0.03, font = F.GothamBold })
end

-- 뒷바 장비
local function blender(K: any, pcf: CFrame, enclosure: boolean)
	K:box("BlenderBase", V3(0.55, 0.45, 0.6), pcf * CF(0, 0.225, 0), Look.of(30, 30, 32))
	K:plate("BlenderPanel", 0.42, 0.16, 0.02, faceCF((pcf * CF(0, 0.25, 0.3)).Position, pcf.ZVector), Look.of(60, 60, 64, Enum.Material.Glass))
	K:box("BlenderLED", V3(0.1, 0.03, 0.02), pcf * CF(-0.12, 0.3, 0.31), Look.ledBlue)
	K:vcyl("BlenderJar", 0.8, 0.46, pcf * CF(0, 0.45 + 0.4, 0), glassL(rgb(230, 236, 240), 0.5))
	K:vcyl("BlenderLid", 0.1, 0.48, pcf * CF(0, 1.3, 0), Look.black)
	K:box("BlenderHandle", V3(0.07, 0.56, 0.1), pcf * CF(0.29, 0.88, 0), Look.black)
	if enclosure then
		K:box("BlenderHood", V3(0.82, 1.15, 0.78), pcf * CF(0, 0.45 + 0.6, 0), glassL(rgb(220, 230, 236), 0.75))
	end
end

local function syrupRack(K: any, pcf: CFrame, n: number)
	local w = n * 0.34 + 0.1
	K:box("SyrupRack", V3(w, 0.12, 0.42), pcf * CF(0, 0.06, 0), Look.steel)
	K:box("SyrupRackBack", V3(w, 0.4, 0.04), pcf * CF(0, 0.2, -0.2), Look.steel)
	local cols = { rgb(150, 92, 40), rgb(220, 200, 160), rgb(120, 40, 30), rgb(90, 140, 70), rgb(230, 230, 220), rgb(60, 30, 20) }
	local names = { "바닐라", "헤이즐넛", "카라멜", "모카", "슈가", "돌체" }
	for k = 1, n do
		local x = -w / 2 + 0.05 + 0.34 * (k - 0.5)
		K:vcyl("SyrupBottle", 0.82, 0.26, pcf * CF(x, 0.12 + 0.41, 0), lk(cols[(k - 1) % #cols + 1], M.Glass, { t = 0.15 }))
		K:vcyl("SyrupPump", 0.22, 0.1, pcf * CF(x, 1.05, 0), Look.black)
		K:box("SyrupNozzle", V3(0.04, 0.04, 0.18), pcf * CF(x, 1.15, 0.08), Look.black)
		if hi(K) then
			K:text("SyrupLabel", 0.22, 0.2, pcf * CF(x, 0.5, 0.131), names[(k - 1) % #names + 1], { fg = rgb(40, 40, 40), bg = rgb(250, 248, 240), d = 0.005, font = F.GothamBold })
		end
	end
end

local function cupTower(K: any, pcf: CFrame, cupC: Color3)
	K:box("CupTowerBase", V3(1.2, 0.1, 0.45), pcf * CF(0, 0.05, 0), Look.steel)
	local sizes = { 0.34, 0.4, 0.46 }
	for k = 1, 3 do
		local x = -0.4 + (k - 1) * 0.4
		K:vcyl("CupTube", 1.2, sizes[k] + 0.06, pcf * CF(x, 0.7, 0), glassL(rgb(230, 236, 240), 0.7))
		K:vcyl("CupStack", 1.05, sizes[k], pcf * CF(x, 0.65, 0), lk(cupC, M.SmoothPlastic))
	end
end

local function hotWater(K: any, pcf: CFrame)
	K:box("HotWaterBody", V3(0.7, 1.25, 0.8), pcf * CF(0, 0.625, 0), Look.steel)
	K:text("HotWaterLCD", 0.4, 0.16, faceCF((pcf * CF(0, 1.05, 0.405)).Position, pcf.ZVector), "95℃", { fg = rgb(255, 80, 60), bg = rgb(10, 10, 12), glow = 1.3, font = F.Code, d = 0.01 })
	K:box("HotWaterTap", V3(0.12, 0.2, 0.18), pcf * CF(0, 0.62, 0.48), Look.black)
	K:box("HotWaterTray", V3(0.5, 0.05, 0.3), pcf * CF(0, 0.08, 0.5), Look.chrome)
end

local function pitchers(K: any, pcf: CFrame)
	for k = 0, 2 do
		local c = pcf * CF((k - 1) * 0.3, 0, (k % 2) * 0.08)
		K:vcyl("MilkPitcher", 0.34, 0.24, c * CF(0, 0.17, 0), Look.steel)
		K:box("MilkPitcherSpout", V3(0.06, 0.06, 0.08), c * CF(0, 0.32, 0.13), Look.steel)
	end
end

local function knockBox(K: any, pcf: CFrame)
	K:box("KnockBox", V3(0.55, 0.36, 0.5), pcf * CF(0, 0.18, 0), Look.black)
	K:cyl("KnockBar", 0.5, 0.07, pcf * CF(0, 0.33, 0), Look.rubber)
	K:box("KnockGrounds", V3(0.45, 0.02, 0.4), pcf * CF(0, 0.3, 0), lk(rgb(56, 36, 24), M.Ground))
end

local function canisters(K: any, pcf: CFrame, n: number, B: any)
	local cols = { B.c1, rgb(240, 240, 236), B.c2 or rgb(30, 30, 30) }
	for k = 1, n do
		local x = (k - (n + 1) / 2) * 0.42
		K:vcyl("TeaTin", 0.55, 0.34, pcf * CF(x, 0.275, 0), lk(cols[k % #cols + 1], M.Metal))
		K:vcyl("TeaTinLid", 0.08, 0.36, pcf * CF(x, 0.59, 0), Look.chrome)
	end
end

-- 드립 스테이션 (핸드드립 3구 + 주전자 + 저울)
local function dripStation(K: any, pcf: CFrame)
	K:box("DripStand", V3(1.5, 0.08, 0.5), pcf * CF(0, 0.75, 0), Look.walnut)
	for _, sx in { -1, 1 } do
		K:box("DripStandLeg", V3(0.08, 0.75, 0.45), pcf * CF(sx * 0.7, 0.375, 0), Look.walnut)
	end
	for k = -1, 1 do
		local c = pcf * CF(k * 0.48, 0, 0)
		K:vcyl("DripServer", 0.42, 0.3, c * CF(0, 0.21, 0), glassL(rgb(230, 236, 240), 0.5))
		K:vcyl("DripCoffee", 0.12, 0.26, c * CF(0, 0.07, 0), lk(rgb(70, 40, 22)))
		K:vcyl("Dripper", 0.3, 0.34, c * CF(0, 0.94, 0), lk(rgb(250, 250, 248)))
		K:vcyl("DripperCone", 0.15, 0.2, c * CF(0, 0.82, 0), lk(rgb(250, 250, 248)))
	end
	local kc = pcf * CF(0.95, 0, 0.05)
	K:box("DripScale", V3(0.4, 0.06, 0.4), kc * CF(0, 0.03, 0), Look.black)
	K:vcyl("Kettle", 0.42, 0.34, kc * CF(0, 0.27, 0), Look.blackMetal)
	K:seg("KettleSpout", (kc * CF(0, 0.2, 0.15)).Position, (kc * CF(0, 0.55, 0.45)).Position, 0.04, Look.blackMetal)
	K:bar("KettleHandle", (kc * CF(0, 0.45, -0.16)).Position, (kc * CF(0, 0.22, -0.26)).Position, 0.05, 0.08, Look.walnut)
end

-- 진열장 / 장비 스킨 ----------------------------------------------------------------------------------------
local function machineSkin(K: any, r: any, look: any)
	K:free(function()
		K:box("Skin" .. r.name, r.size + V3(0.03, 0.03, 0.03), CF(r.c), look)
	end)
end

-- 젤라또 맛
local FLAVORS = {
	{ "피스타치오", rgb(156, 186, 104) }, { "바닐라빈", rgb(248, 238, 206) }, { "다크초코", rgb(88, 54, 36) }, { "생딸기", rgb(240, 130, 150) },
	{ "애플망고", rgb(250, 184, 60) }, { "그릭요거트", rgb(250, 250, 244) }, { "흑임자", rgb(92, 88, 86) }, { "레몬셔벗", rgb(250, 236, 120) },
	{ "쑥 인절미", rgb(150, 168, 104) }, { "솔티드카라멜", rgb(212, 150, 80) }, { "민트초코", rgb(170, 230, 210) }, { "블루베리", rgb(120, 96, 168) },
}

-- 탕후루 꼬치: base = 막대 아래 끝 (축 +Y)
local FRUIT: { [string]: any } = {
	strawberry = { c = rgb(214, 28, 48), d = 0.24, n = 4, ell = true },
	grape = { c = rgb(160, 206, 80), d = 0.2, n = 5 },
	blueberry = { c = rgb(60, 60, 120), d = 0.13, n = 7 },
	mandarin = { c = rgb(250, 146, 28), d = 0.25, n = 3 },
	kiwi = { c = rgb(130, 180, 50), d = 0.22, n = 4, ell = true },
	tomato = { c = rgb(232, 44, 36), d = 0.17, n = 5 },
	pineapple = { c = rgb(250, 206, 60), d = 0.21, n = 4, cube = true },
}
local FRUIT_ORDER = { "strawberry", "grape", "blueberry", "mandarin", "kiwi", "tomato", "pineapple" }
local function skewer(K: any, base: CFrame, kind: string, len: number)
	local f = FRUIT[kind] or FRUIT.strawberry
	K:vcyl("TangStick", len, 0.04, base * CF(0, len / 2, 0), lk(rgb(224, 202, 160), M.Wood))
	local y = len - 0.06
	local candy = lk(f.c, M.Glass, { t = 0.04, r = 0.22 })
	for _ = 1, f.n do
		local p = base * CF(0, y - f.d / 2, 0)
		if f.cube then
			K:box("TangFruit", V3(f.d, f.d, f.d) * 0.9, p * ANG(0, 0.6, 0), candy)
		elseif f.ell then
			K:ell("TangFruit", V3(f.d, f.d * 1.15, f.d), p, candy)
		else
			K:ball("TangFruit", f.d, p, candy)
		end
		y -= f.d * 0.98
	end
end

-- 인형 (곰 · 토끼 · 병아리): c 중심, s 크기, face = 앞 방향
local function plush(K: any, c: Vector3, s: number, kind: number, col: Color3, face: Vector3)
	local pcf = facing(c - V3(0, s * 0.45, 0), face)
	local fur = lk(col, M.Fabric)
	K:ell("PlushBody", V3(0.8, 0.7, 0.7) * s, pcf * CF(0, s * 0.32, 0), fur)
	K:ball("PlushHead", 0.62 * s, pcf * CF(0, s * 0.8, 0.03 * s), fur)
	if kind == 1 then
		for _, sx in { -1, 1 } do
			K:ell("PlushEar", V3(0.14, 0.42, 0.1) * s, pcf * CF(sx * 0.14 * s, s * 1.2, 0), fur)
		end
	elseif kind == 2 then
		K:wedge("PlushBeak", V3(0.12, 0.08, 0.14) * s, pcf * CF(0, s * 0.78, 0.33 * s), lk(rgb(250, 150, 40)))
	else
		for _, sx in { -1, 1 } do
			K:ball("PlushEar", 0.2 * s, pcf * CF(sx * 0.22 * s, s * 1.06, 0), fur)
		end
		if hi(K) then
			K:ell("PlushMuzzle", V3(0.24, 0.16, 0.12) * s, pcf * CF(0, s * 0.74, 0.3 * s), lk(lt(col, 0.5), M.Fabric))
		end
	end
	if not lowD(K) then
		for _, sx in { -1, 1 } do
			K:ball("PlushEye", 0.07 * s, pcf * CF(sx * 0.11 * s, s * 0.86, 0.3 * s), Look.black)
		end
	end
end

-- 아이스크림 냉동고 (유리 뚜껑 + 속 상자들 + 할인 띠). 반환 뚜껑 파트
local function freezerChest(K: any, pcf: CFrame, w: number, B: any, title: string): BasePart
	local d, h = 1.7, 2.7
	K:box("FreezerBody", V3(w, h - 0.3, d), pcf * CF(0, 0.3 + (h - 0.3) / 2, 0), Look.white)
	K:box("FreezerKick", V3(w - 0.1, 0.3, d - 0.1), pcf * CF(0, 0.15, 0), Look.grey)
	K:box("FreezerStripe", V3(w + 0.01, 0.45, d + 0.01), pcf * CF(0, h - 0.6, 0), lk(B.c1))
	K:text("FreezerTitle", w * 0.8, 0.36, faceCF((pcf * CF(0, h - 0.6, d / 2 + 0.01)).Position, pcf.ZVector), title, { fg = rgb(255, 255, 255), font = F.GothamBlack, d = 0.01 })
	K:text("FreezerPrice", w * 0.7, 0.5, faceCF((pcf * CF(0, 1.2, d / 2 + 0.01)).Position, pcf.ZVector), "아이스크림 전 품목 50%\n파인트 16,000", { fg = rgb(220, 30, 40), bg = rgb(255, 250, 236), font = F.GothamBold, d = 0.02 })
	K:box("FreezerInner", V3(w - 0.2, 0.05, d - 0.2), pcf * CF(0, h - 0.4, 0), lk(rgb(220, 236, 244)))
	local cols = { rgb(250, 200, 210), rgb(160, 210, 250), rgb(250, 230, 150), rgb(200, 240, 200), rgb(110, 70, 50), rgb(250, 250, 244) }
	local n = math.max(3, math.floor((w - 0.3) / 0.45))
	for k = 1, n do
		for j = 0, 1 do
			local x = -(w - 0.3) / 2 + (w - 0.3) * (k - 0.5) / n
			local c = cols[(k + j * 3) % #cols + 1]
			if (k + j) % 3 == 0 then
				K:vcyl("FreezerPint", 0.36, 0.34, pcf * CF(x, h - 0.2, (j - 0.5) * 0.7), lk(c))
			else
				K:box("FreezerBar", V3(0.36, 0.14, 0.5), pcf * CF(x, h - 0.3, (j - 0.5) * 0.7) * ANG(0, 0.15 * (k % 3 - 1), 0), lk(c))
			end
		end
	end
	K:box("FreezerRim", V3(w, 0.06, 0.08), pcf * CF(0, h + 0.03, d / 2 - 0.04), Look.grey)
	K:box("FreezerRim", V3(w, 0.06, 0.08), pcf * CF(0, h + 0.03, -d / 2 + 0.04), Look.grey)
	local lid = K:box("FreezerLid", V3(w / 2, 0.04, d - 0.1), pcf * CF(-w / 4, h + 0.05, 0), glassL(rgb(220, 236, 244), 0.6))
	K:box("FreezerLid", V3(w / 2, 0.04, d - 0.1), pcf * CF(w / 4, h + 0.09, 0), glassL(rgb(220, 236, 244), 0.6))
	return lid
end

-- 픽업 전광판 (천장에 매닮). x, z 로컬, n = 손님 쪽 방향
local function pickupBoard(K: any, x: number, z: number, n: Vector3, B: any)
	local V = K.V
	local y = V.H - 1.05
	local c = facing(V3(x, y, z), n)
	K:free(function()
		for _, sx in { -1, 1 } do
			K:seg("PickupRod", (c * CF(sx * 0.9, 0.45, 0)).Position, V3(x, V.H, z) + (c.XVector * sx * 0.9), 0.05, Look.blackMetal)
		end
	end)
	K:box("PickupBox", V3(2.4, 0.9, 0.18), c, Look.black)
	K:text("PickupHead", 0.9, 0.3, c * CF(-0.62, 0.18, 0.095), "PICK UP", { fg = B.c1, glow = 1.4, font = F.GothamBlack, d = 0.005 })
	local scr, lab = K:text("PickupNo", 1.1, 0.5, c * CF(0.55, 0, 0.095), "0127", { fg = rgb(255, 60, 40), bg = rgb(8, 8, 8), glow = 1.6, font = F.Code, d = 0.005 })
	K:text("PickupSub", 0.9, 0.18, c * CF(-0.62, -0.2, 0.095), "음료가 준비되었습니다", { fg = rgb(230, 230, 230), glow = 1.1, font = F.Gotham, d = 0.005 })
	local frames = {}
	for k = 0, 7 do
		table.insert(frames, { text = string.format("%04d", 127 + k * 3 + (k % 2)) })
	end
	Interact.screenLoop(K, nil, lab, frames, 6)
	return scr
end

-- 화면 (TV 메뉴 · 프로모): 프레임 순환
local function promoScreen(K: any, dcf: CFrame, w: number, frames: { any })
	local h = w * 9 / 16
	K:plate("ScreenMount", w * 0.3, h * 0.3, 0.1, dcf, Look.blackMetal)
	K:plate("ScreenBody", w + 0.1, h + 0.1, 0.12, dcf * CF(0, 0, 0.1), Look.black)
	local scr, lab = K:text("PromoScreen", w, h, dcf * CF(0, 0, 0.22), frames[1].text, { fg = frames[1].fg or rgb(255, 255, 255), bg = frames[1].c or rgb(30, 30, 30), glow = 1.15, font = F.GothamBlack, d = 0.02 })
	Interact.anim(K, function(t: number)
		local i = math.floor(t / 5) % #frames + 1
		local f = frames[i]
		if lab.Parent then
			lab.Text = f.text
			lab.BackgroundColor3 = f.c or rgb(30, 30, 30)
			lab.TextColor3 = f.fg or rgb(255, 255, 255)
		end
	end)
	return scr
end

-- 덕트 (스파이럴 원형 덕트 + 행거 + 디퓨저): 천장 아래 z 줄을 따라 빈 구간만
local function ducts(K: any, V: any)
	local dia = 1.1
	local y = V.H - 0.95
	local best, bz = -1, nil
	local function blocked(x: number, z: number): boolean
		for _, r in V.hang do
			if x > r.min.X - 0.8 and x < r.max.X + 0.8 and z > r.min.Z - 0.8 and z < r.max.Z + 0.8 and r.max.Y > y - 0.7 then
				return true
			end
		end
		return false
	end
	local z = V.z0 + 2.0
	while z < V.z1 - 3.0 do
		local free, run = 0, 0
		for x = V.x0 + 1, V.x1 - 1, 0.5 do
			if blocked(x, z) then
				run = 0
			else
				run += 0.5
				free = math.max(free, run)
			end
		end
		if free > best + 0.6 then
			best, bz = free, z
		end
		z += 0.5
	end
	if not bz or best < 6 then
		return
	end
	-- 가장 긴 빈 구간
	local runs, cur = {}, nil
	for x = V.x0 + 1, V.x1 - 1, 0.5 do
		if blocked(x, bz) then
			cur = nil
		else
			if not cur then
				cur = { x, x }
				table.insert(runs, cur)
			end
			cur[2] = x
		end
	end
	local look = lk(rgb(196, 198, 200), M.Metal, { r = 0.1 })
	K:free(function()
		for _, rr in runs do
			if rr[2] - rr[1] >= 5 then
				local a, b = V3(rr[1], y, bz), V3(rr[2], y, bz)
				K:seg("Duct", a, b, dia, look)
				local n = math.floor((rr[2] - rr[1]) / 2.0)
				for k = 0, n do
					local x = rr[1] + (rr[2] - rr[1]) * k / math.max(1, n)
					K:cyl("DuctSeam", 0.06, dia + 0.04, CF(x, y, bz), look)
					if k % 2 == 0 then
						K:seg("DuctHanger", V3(x, y + dia / 2, bz), V3(x, V.H, bz), 0.04, Look.blackMetal)
						K:bar("DuctStrap", V3(x - 0.04, y + dia / 2 + 0.02, bz - dia / 2), V3(x - 0.04, y + dia / 2 + 0.02, bz + dia / 2), 0.05, 0.03, Look.blackMetal)
					end
					if k % 3 == 1 then
						K:vcyl("DuctDiffuserNeck", 0.3, 0.5, CF(x, y - dia / 2 - 0.1, bz), look)
						K:disc("DuctDiffuser", 0.8, 0.08, CF(x, y - dia / 2 - 0.28, bz), look)
					end
				end
				K:disc("DuctCap", dia + 0.06, 0.08, CF(a) * ANG(0, 0, PI / 2), look)
				K:disc("DuctCap", dia + 0.06, 0.08, CF(b) * ANG(0, 0, PI / 2), look)
			end
		end
		-- 케이블 트레이 (덕트 옆)
		local tz = bz + dia / 2 + 0.6
		for _, rr in runs do
			if rr[2] - rr[1] >= 5 then
				K:box("CableTray", V3(rr[2] - rr[1], 0.08, 0.5), CF((rr[1] + rr[2]) / 2, V.H - 0.4, tz), Look.blackMetal)
				K:seg("CableBundle", V3(rr[1], V.H - 0.33, tz), V3(rr[2], V.H - 0.33, tz), 0.12, Look.black)
			end
		end
	end)
end

-- 행잉 화분 (천장 줄 + 화분 + 늘어진 잎)
local function hangingPlant(K: any, x: number, z: number, drop: number)
	local V = K.V
	local y = V.H - drop
	K:free(function()
		for k = 0, 2 do
			local a = k * 2 * PI / 3
			K:seg("HangCord", V3(x, V.H, z), V3(x + math.cos(a) * 0.3, y + 0.5, z + math.sin(a) * 0.3), 0.03, Look.of(200, 190, 170, Enum.Material.Fabric))
		end
		K:vcyl("HangPot", 0.5, 0.65, CF(x, y + 0.25, z), Look.terracotta)
		K:disc("HangSoil", 0.58, 0.02, CF(x, y + 0.5, z), Look.soil)
		for k = 0, 6 do
			local a = k * 2 * PI / 7
			local len = 0.8 + (k % 3) * 0.45
			local p0 = V3(x + math.cos(a) * 0.3, y + 0.5, z + math.sin(a) * 0.3)
			local p1 = V3(x + math.cos(a) * 0.55, y + 0.4 - len, z + math.sin(a) * 0.55)
			K:seg("HangVine", p0, p1, 0.03, Look.leafDark)
			K:ell("HangLeaf", V3(0.3, 0.12, 0.22), CF(p1) * ANG(0, a, 0.4), if k % 2 == 0 then Look.leaf else Look.leafLight)
			K:ell("HangLeaf", V3(0.26, 0.1, 0.2), CF(p0:Lerp(p1, 0.5)) * ANG(0, a + 1, -0.3), Look.leaf)
		end
		K:ell("HangTuft", V3(0.8, 0.35, 0.8), CF(x, y + 0.62, z), Look.leaf)
	end)
end

-- 벽 스킨 (문 · 개구부 피함): wn 벽, look
local function wallSkin(K: any, V: any, wn: string, look: any)
	local wall = V.walls[wn]
	if not wall then
		return
	end
	local cuts = {}
	for _, nm in { "DoorCasing", "DoorLeaf", "Door", "GlassDoor" } do
		for _, r in V.byName[nm] or {} do
			local u0, d0 = V:wallCoord(wn, r.min)
			local u1, d1 = V:wallCoord(wn, r.max)
			if math.min(d0, d1) < 0.6 then
				table.insert(cuts, { math.min(u0, u1) - 0.12, math.max(u0, u1) + 0.12, r.max.Y + 0.1 })
			end
		end
	end
	table.sort(cuts, function(a, b)
		return a[1] < b[1]
	end)
	local H = V.H - 0.04
	K:free(function()
		local cur = wall.a
		for _, c in cuts do
			if c[1] > cur + 0.05 then
				K:plate("WallSkin", c[1] - cur, H, 0.012, V:wall(wn, (cur + c[1]) / 2, H / 2, 0.004), look)
			end
			if H > c[3] + 0.05 then
				K:plate("WallSkin", c[2] - math.max(cur, c[1]), H - c[3], 0.012, V:wall(wn, (math.max(cur, c[1]) + c[2]) / 2, c[3] + (H - c[3]) / 2, 0.004), look)
			end
			cur = math.max(cur, c[2])
		end
		if wall.b > cur + 0.05 then
			K:plate("WallSkin", wall.b - cur, H, 0.012, V:wall(wn, (cur + wall.b) / 2, H / 2, 0.004), look)
		end
	end)
end


-- 단계 ------------------------------------------------------------------------------------------------------

local function context(K: any, V: any, B: any): any
	local ctx: any = { boards = {} }
	local pos = V:first("PosBase") or V:first("OrderKiosk") or V:first("CashierPanel")
	ctx.pos = pos
	local main = nil
	if pos then
		for _, g in V.counters do
			if pos.c.X >= g.min.X - 0.6 and pos.c.X <= g.max.X + 0.6 and pos.c.Z >= g.min.Z - 0.9 and pos.c.Z <= g.max.Z + 0.9 then
				main = g
			end
		end
	end
	if not main then
		local best = 0
		for _, g in V.counters do
			local a = (g.max.X - g.min.X) * (g.max.Z - g.min.Z)
			if a > best then
				best, main = a, g
			end
		end
	end
	ctx.main = main
	ctx.esp = V.byName.EspressoBody or {}
	ctx.cx, ctx.cz = (V.x0 + V.x1) / 2, (V.z0 + V.z1) / 2
	if main then
		ctx.n = custDir(V, main)
		for _, g in V.counters do
			if g ~= main then
				local behind = if ctx.n.Z > 0.5 then g.max.Z <= main.min.Z + 0.3 elseif ctx.n.Z < -0.5 then g.min.Z >= main.max.Z - 0.3 else false
				if behind then
					ctx.back = g
				end
			end
		end
		local alongX = math.abs(ctx.n.Z) > 0.5
		local lo = if alongX then main.min.X else main.min.Z
		local hi2 = if alongX then main.max.X else main.max.Z
		local pu = if pos then (if alongX then pos.c.X else pos.c.Z) else lo
		ctx.alongX = alongX
		ctx.posU = pu
		ctx.pickU = if math.abs(pu - lo) < math.abs(pu - hi2) then hi2 - 1.0 else lo + 1.0
	end
	-- 뒷벽에 맵 간판이 있나 (브랜드 로고 중복 피함)
	for _, r in V.parts do
		if r.shell and string.sub(r.name, 1, 5) == "Sign_" and r.c.Z < V.z0 + 0.8 and not string.find(r.name, "화장실", 1, true) then
			ctx.backSign = r
		end
	end
	return ctx
end

-- 1) 맵 간판 자리 등록
local function stepShell(K: any, V: any, B: any, _ctx: any)
	for _, r in V.parts do
		if r.shell and string.sub(r.name, 1, 5) == "Sign_" then
			for _, wn in { "back", "left", "right" } do
				local u0, d0 = V:wallCoord(wn, r.min)
				local u1, d1 = V:wallCoord(wn, r.max)
				local dmin = math.min(d0, d1)
				if dmin < 0.9 and dmin > -0.8 then
					useWall(K, wn, math.min(u0, u1) - 0.25, math.max(u0, u1) + 0.25, r.min.Y - 0.2, r.max.Y + 0.2)
				end
			end
		end
	end
	-- 벽 전체 스킨 (브랜드)
	if B.wall then
		for wn, look in B.wall do
			wallSkin(K, V, wn, look)
		end
	end
end

local function uOf(V: any, wn: string, x: number, z: number): number
	local u = V:wallCoord(wn, V3(x, 0, z))
	return u
end

-- 2) 바닥 소품
local function stepFloor(K: any, V: any, B: any, ctx: any)
	local feat = B.feat or {}
	ctx.placed = ctx.placed or {}
	local function mark(name: string, cf: CFrame?)
		if cf then
			table.insert(ctx.placed, name .. ctx.where(cf))
		end
	end
	local main = ctx.main
	local small = V.W * V.D < 180
	-- 셀프바 · 냉장고는 픽업 쪽 옆벽, MD 는 반대쪽
	local pickSide = "right"
	if main and ctx.alongX then
		pickSide = if ctx.pickU > ctx.cx then "right" else "left"
	elseif main then
		pickSide = if (main.min.X + main.max.X) / 2 > 0 then "right" else "left"
	end
	local other = if pickSide == "right" then "left" else "right"
	local zT = if main then math.min(V.z1 - 4, main.max.Z + 2.4) else V.z0 + V.D * 0.45
	local pref = { [pickSide] = uOf(V, pickSide, 0, zT), [other] = uOf(V, other, 0, zT + 1.5), back = 0 }

	if feat.roaster then
		local wn, pcf = floorFind(K, { "back", "left", "right" }, 3.9, 2.9, 5.7, { back = V.x0 + 4.0 - ctx.cx, left = uOf(V, "left", 0, V.z0 + 3), right = uOf(V, "right", 0, V.z0 + 3) }, { pad = 0.1 })
		if wn and pcf then
			mark("roaster", pcf)
			local R = roaster(K, pcf, B)
			ctx.roaster = R
			if feat.sacks then
				local wn2, pcf2 = floorFind(K, { wn, "left", "right" }, 2.6, 1.8, 2.0, uOf(V, wn, (pcf.Position.X), pcf.Position.Z) + 3.6, { pad = 0.05 })
				if wn2 and pcf2 then
					beanSacks(K, pcf2, 2.4)
				end
			end
		end
	end
	if feat.oven then
		local wn, pcf = floorFind(K, { pickSide, other }, 4.2, 2.6, 6.0, pref, { pad = 0.1 })
		if wn and pcf then
			mark("oven", pcf)
			ctx.oven = deckOven(K, pcf, 4.2)
		end
	end
	if feat.selfbar then
		local w = if small then 2.6 else 3.4
		local wn, pcf = floorFind(K, { pickSide, other }, w, 1.5, 4.6, pref, { pad = 0.08 })
		if wn and pcf then
			mark("selfbar", pcf)
			selfBar(K, pcf, w, B)
		end
	end
	if feat.fridge and not small then
		local wn, pcf = floorFind(K, { pickSide, other }, 2.5, 2.1, 6.6, pref, { pad = 0.06 })
		if wn and pcf then
			mark("fridge", pcf)
			local door, hinge = drinkFridge(K, pcf, 2.5, B, "GRAB & GO")
			if door and hinge then
				Interact.swing(K, door, hinge, (K.cf * pcf).UpVector, -1.75, { object = "음료 냉장고", openText = "문 열기", closeText = "문 닫기" })
			end
		end
	end
	if feat.cake then
		local wn, pcf = floorFind(K, { pickSide, other, "back" }, 2.8, 2.0, 6.2, pref, { pad = 0.06 })
		if wn and pcf then
			mark("cake", pcf)
			local door, hinge = cakeFridge(K, pcf, 2.8, B, if B.key == "bakery" then "CAKE · 생크림 케이크" else "CAKE & DESSERT")
			if door and hinge then
				Interact.swing(K, door, hinge, (K.cf * pcf).UpVector, -1.6, { object = "케이크 쇼케이스", openText = "문 열기", closeText = "문 닫기" })
			end
		end
	end
	if feat.md and not small then
		local wn, pcf = floorFind(K, { other, pickSide }, 3.2, 1.1, 5.8, pref, { pad = 0.06 })
		if wn and pcf then
			mark("md", pcf)
			mdShelf(K, pcf, 3.2, 5.4, B)
		end
	end
	if feat.freezer then
		local w = if small then 2.6 else 3.2
		local placed = false
		if B.key == "claw" then
			-- 가운데 (인형뽑기 기계 앞 2.6 비움)
			local zs = { ctx.cz + 0.3, ctx.cz - 0.4, ctx.cz + 1.0 }
			for _, z in zs do
				local pcf = facing(V3(ctx.cx, 0, z), V3(0, 0, 1))
				if spotX(K, pcf, V3(w, 2.9, 1.7), 0.9) then
					ctx.freezer = freezerChest(K, pcf, w, B, "무인 아이스크림")
					ctx.freezerCF = pcf
					placed = true
					break
				end
			end
		end
		if not placed then
			local wn, pcf = floorFind(K, { other, pickSide, "back" }, w, 1.7, 2.9, pref, { pad = 0.08 })
			if wn and pcf then
				mark("freezer", pcf)
				ctx.freezer = freezerChest(K, pcf, w, B, if B.key == "tanghulu" then "젤라또 파인트" else "HOME PINT")
				ctx.freezerCF = pcf
			end
		end
	end
	-- 탕후루 냉장 쇼케이스: 젤라또 진열장 옆 같은 줄
	if feat.tanghulu then
		local case = V:first("CaseBase")
		local zc = if case then (case.min.Z + case.max.Z) / 2 else V.z0 + 5
		local w, d, h = 3.6, 2.2, 4.4
		local x = if case then case.min.X - 0.25 - w / 2 else ctx.cx
		for _ = 1, 16 do
			local pcf = facing(V3(x, 0, zc), V3(0, 0, 1))
			if spotX(K, pcf, V3(w, h, d), 0.05) then
				ctx.tangCase = pcf
				mark("tang", pcf)
				break
			end
			x -= 0.5
		end
	end
	-- 베이커리 아일랜드 진열대 (가운데)
	if feat.island then
		local done = false
		for dz = 0, 6 do
			for dx = 0, 10 do
				for _, sx in { -1, 1 } do
					local x = ctx.cx - V.W * 0.12 + sx * dx * 0.8
					local z = V.z0 + V.D * 0.42 + (if dz % 2 == 0 then 1 else -1) * math.floor((dz + 1) / 2) * 0.5
					local pcf = facing(V3(x, 0, z), V3(0, 0, 1))
					if not done and spotX(K, pcf, V3(4.2, 3.4, 2.4), 0.7) then
						ctx.island = pcf
						mark("island", pcf)
						done = true
					end
				end
				if done then
					break
				end
			end
			if done then
				break
			end
		end
	end
	-- 바닥 화분
	local np = feat.plants or 2
	local kinds = (K.style and K.style.plants) or { "monstera", "olive" }
	for i = 1, np do
		local z = if i == 1 then V.z1 - 4.5 else V.z0 + V.D * 0.5
		local wn, pcf = floorFind(K, if i % 2 == 1 then { other, pickSide } else { pickSide, other }, 1.9, 1.9, 5.5, { [other] = uOf(V, other, 0, z), [pickSide] = uOf(V, pickSide, 0, z) }, { pad = 0.05 })
		if wn and pcf and #kinds > 0 then
			mark("plant", pcf)
			local kind = kinds[(i + B.seed) % #kinds + 1]
			local ph = math.clamp(V.H * 0.5, 4.2, 5.4)
			-- 잎이 넓게 퍼지는 몬스테라 · 올리브는 좌석 · 통로 keep 에 닿으면 산세베리아로
			if kind ~= "snake" then
				local mn, mx = Kit.laabb(pcf * CF(0, ph / 2, 0), V3(3.2, ph, 3.2))
				if K:hitsKeep(mn, mx) then
					kind = "snake"
				end
			end
			Props.floorPlant(K, pcf, { kind = kind, h = ph, dia = 1.5, pot = if B.key == "roastery" or B.key == "concrete" then Look.of(60, 60, 62, Enum.Material.Concrete) else nil })
		end
	end
end

-- 3) 카운터 위 / 뒤
local function stepCounters(K: any, V: any, B: any, ctx: any)
	if B.noCounter then
		return
	end
	local g = ctx.main
	if g then
		counterLogo(K, V, g, B)
		local pu = ctx.posU or 0
		local pcf = counterSpot(K, g, 0.5, 0.8, 0.4, "front", pu + 1.05)
		if pcf then
			Props.cardTerminal(K, pcf)
		end
		pcf = counterSpot(K, g, 0.7, 0.7, 1.5, "front", pu - 1.15)
		if pcf then
			pagerTower(K, pcf, if lowD(K) then 4 else 8, B.c1)
		end
		pcf = counterSpot(K, g, 0.65, 0.35, 1.0, "front", pu + 1.9)
		if pcf then
			Props.menuStand(K, pcf, B.promo[1] .. "\n" .. B.promo[2] .. "\n" .. B.promo[3] .. "원")
		end
		if B.feat.pickup ~= false then
			pcf = counterSpot(K, g, 1.3, 0.35, 0.8, "front", ctx.pickU)
			if pcf then
				standSign(K, pcf, 1.2, 0.62, "PICK UP\n픽업대", B.ink, B.paper)
				ctx.pickCF = pcf
			end
		end
		-- 디저트 진열 (쿠키 병 · 케이크 돔) / 꽃
		local mid = if ctx.esp[1] then (if ctx.alongX then ctx.esp[1].c.X else ctx.esp[1].c.Z) else pu + 3
		local dpos = (pu + mid) / 2
		if B.key == "haute" or B.key == "lounge" or B.key == "twosome" then
			pcf = counterSpot(K, g, 1.0, 1.0, 1.1, "front", dpos)
			if pcf then
				cakeDome(K, pcf, if B.key == "twosome" then rgb(90, 56, 40) else rgb(250, 232, 236))
			end
			pcf = counterSpot(K, g, 0.6, 0.6, 1.3, "front", ctx.pickU - 1.6)
			if pcf then
				flowerVase(K, pcf, B)
			end
		elseif B.type ~= "bakery" and B.key ~= "claw" then
			for k = 0, 1 do
				pcf = counterSpot(K, g, 0.6, 0.6, 0.9, "front", dpos + (k - 0.5) * 0.8)
				if pcf then
					cookieJar(K, pcf, if k == 0 then rgb(196, 140, 76) else rgb(110, 70, 44), if k == 0 then "쿠키 2,800" else "휘낭시에 3,000")
				end
			end
		end
		if B.feat.drip then
			pcf = counterSpot(K, g, 2.4, 0.6, 1.3, "front", ctx.pickU - 2.6)
			if pcf then
				dripStation(K, pcf)
			end
		end
		-- 픽업 쪽 안쪽: 포장 봉투 · 컵 캐리어
		if not lowD(K) then
			local pk = counterSpot(K, g, 1.3, 0.5, 0.95, "back", ctx.pickU)
			if pk then
				for k = 0, 1 do
					local c = pk * CF(-0.32 + k * 0.62, 0, 0)
					K:box("TakeoutBag", V3(0.5, 0.72, 0.3), c * CF(0, 0.36, 0), Look.kraft)
					K:box("TakeoutBagFold", V3(0.52, 0.08, 0.32), c * CF(0, 0.74, 0), lk(rgb(170, 134, 90), M.Cardboard))
					K:plate("TakeoutBagLogo", 0.3, 0.2, 0.01, c * CF(0, 0.4, 0.15), lk(B.c1))
				end
			end
		end
		-- 직원 쪽: 컵 · 피처 · 넉박스
		if ctx.esp[1] then
			local eu = if ctx.alongX then ctx.esp[1].c.X else ctx.esp[1].c.Z
			pcf = counterSpot(K, g, 0.6, 0.55, 0.45, "back", eu - 2.0)
			if pcf then
				knockBox(K, pcf)
			end
			pcf = counterSpot(K, g, 1.0, 0.4, 0.5, "back", eu + 2.1)
			if pcf then
				pitchers(K, pcf)
			end
		end
		-- 베이커리 / 디저트 계산대: 포장 봉투 · 영수증
		if B.key == "bakery" or B.type == "dessert" then
			pcf = counterSpot(K, g, 0.7, 0.8, 0.6, "mid", pu + 1.4)
			if pcf then
				Props.receiptPrinter(K, pcf)
			end
			pcf = counterSpot(K, g, 0.9, 0.6, 0.5, "front", pu - 1.3)
			if pcf then
				for k = 0, 3 do
					K:box("PaperBag", V3(0.8, 0.06, 0.55), pcf * CF(0, 0.03 + k * 0.065, 0) * ANG(0, k * 0.06, 0), Look.kraft)
				end
				K:text("PaperBagLogo", 0.5, 0.2, topCF((pcf * CF(0, 0.3, 0)).Position, -pcf.ZVector), B.logo, { fg = dk(B.c1, 0.3), d = 0.005, font = F.GothamBold })
			end
		end
	end
	-- 뒷바 (벽쪽 카운터)
	local bk = ctx.back
	if bk then
		local function bspot(w: number, d: number, h: number, pu: number): CFrame?
			return counterSpot(K, bk, w, d, h, "back", pu, 0.04, 0.08)
		end
		local lo = if ctx.alongX then bk.min.X else bk.min.Z
		local span = if ctx.alongX then bk.max.X - bk.min.X else bk.max.Z - bk.min.Z
		local chain = B.key == "mega" or B.key == "compose" or B.key == "twosome" or B.key == "pascucci"
		local items = {
			{ 0.9, 0.85, 1.5, 0.62, function(p) blender(K, p, chain) end },
			{ 0.9, 0.85, 1.5, 0.7, function(p) blender(K, p, chain) end },
			{ 1.9, 0.45, 1.25, 0.45, function(p) syrupRack(K, p, 5) end },
			{ 1.3, 0.5, 1.35, 0.25, function(p) cupTower(K, p, B.cup) end },
			{ 0.8, 0.85, 1.3, 0.85, function(p) hotWater(K, p) end },
			{ 1.3, 0.4, 0.7, 0.15, function(p) canisters(K, p, 3, B) end },
			{ 0.8, 0.85, 1.3, 0.92, function(p) blender(K, p, false) end },
		}
		for _, it in items do
			local p = bspot(it[1], it[2], it[3], lo + span * it[4])
			if p then
				it[5](p)
			end
		end
		-- 뒷바 앞면: 테이블 냉장고 문 + 제빙기 패널 (평평한 마감)
		local body = bk.body or bk
		local n = custDir(V, bk)
		if math.abs(n.Z) > 0.5 then
			local fz = if n.Z > 0 then body.max.Z else body.min.Z
			local top = (if bk.top then bk.top.min.Y else bk.y) - 0.1
			local h = top - 0.5
			local x = body.min.X + 0.3
			local k = 0
			K:free(function()
				while x + 2.0 <= body.max.X - 0.2 do
					local dcf = faceCF(V3(x + 1.0, 0.45 + h / 2, fz + n.Z * 0.085), n)
					local ice = k == 1
					K:plate("UnderFridgeDoor", 1.9, h - 0.1, 0.05, dcf, Look.steel)
					K:plate("UnderFridgeHandle", 1.5, 0.08, 0.06, dcf * CF(0, h / 2 - 0.3, 0.05), Look.chrome)
					if ice then
						for j = 0, 3 do
							K:plate("IceMachineVent", 1.4, 0.05, 0.02, dcf * CF(0, -h / 2 + 0.3 + j * 0.14, 0.05), Look.black)
						end
						K:text("IceMachineLabel", 0.8, 0.18, dcf * CF(0, 0.15, 0.06), "ICE MAKER", { fg = rgb(60, 60, 64), font = F.GothamBold, d = 0.005 })
					else
						K:text("UnderFridgeLCD", 0.36, 0.14, dcf * CF(0.6, h / 2 - 0.55, 0.06), "3℃", { fg = rgb(90, 200, 255), bg = rgb(10, 14, 20), glow = 1.2, font = F.Code, d = 0.005 })
					end
					x += 2.1
					k += 1
				end
			end)
		end
	end
end

-- 4) 장비 스킨 · 진열장 · 맵 소품 다시 만들기
local function stepMachines(K: any, V: any, B: any, ctx: any)
	if B.noCounter then
		return
	end
	local n: Vector3 = ctx.n or V3(0, 0, 1)
	local espL = if B.key == "mega" or B.key == "compose" then lk(rgb(30, 30, 32), M.Metal) elseif B.key == "haute" then lk(rgb(240, 236, 228), M.Metal) elseif B.key == "busan" or B.key == "ocean" then lk(rgb(30, 64, 120), M.Metal) elseif B.key == "roastery" or B.key == "concrete" then lk(rgb(40, 40, 42), M.Metal) else lk(rgb(170, 40, 36), M.Metal, { r = 0.06 })
	for _, e in V.byName.EspressoBody or {} do
		machineSkin(K, e, espL)
		local half = math.abs(n.X) * e.size.X / 2 + math.abs(n.Z) * e.size.Z / 2
		local fp = e.c + n * (half + 0.016)
		local dcf = faceCF(V3(fp.X, e.c.Y + 0.05, fp.Z), n)
		local wdt = math.abs(n.Z) * e.size.X + math.abs(n.X) * e.size.Z
		K:free(function()
			K:plate("EspressoPanel", wdt * 0.8, e.size.Y * 0.55, 0.02, dcf, lk(dk(espL.c, 0.25), M.Metal))
			K:text("EspressoBrand", wdt * 0.6, 0.32, dcf * CF(0, 0.05, 0.025), if B.key == "mega" then "MGC" else "ESPRESSO", { fg = if B.key == "mega" then B.c1 else rgb(236, 236, 236), font = F.GothamBlack, d = 0.008 })
			K:plate("EspressoTrim", wdt + 0.04, 0.06, 0.03, faceCF(V3(fp.X, e.max.Y - 0.05, fp.Z), n), Look.chrome)
			-- 컵 워머 레일 + 잔
			local topY = e.max.Y + 0.02
			local ax = if math.abs(n.Z) > 0.5 then V3(1, 0, 0) else V3(0, 0, 1)
			local L2 = wdt / 2 - 0.12
			local dep = (math.abs(n.X) * e.size.X + math.abs(n.Z) * e.size.Z) / 2 - 0.12
			for _, s in { -1, 1 } do
				K:bar("CupRail", e.c * V3(1, 0, 1) + V3(0, topY + 0.08, 0) - ax * L2 + n * (s * dep), e.c * V3(1, 0, 1) + V3(0, topY + 0.08, 0) + ax * L2 + n * (s * dep), 0.04, 0.04, Look.chrome)
			end
			for k = 0, 4 do
				local p = e.c * V3(1, 0, 1) + V3(0, topY + 0.11, 0) + ax * (-L2 + 0.2 + k * (2 * L2 - 0.4) / 4)
				K:vcyl("WarmerCup", 0.22, 0.24, CF(p), Look.white)
			end
			-- 스팀 완드 2 (직원 쪽)
			for _, s in { -1, 1 } do
				local a = e.c * V3(1, 0, 1) + V3(0, e.max.Y - 0.35, 0) + ax * s * (wdt / 2 + 0.06) - n * (half - 0.2)
				local b = a + V3(0, -0.85, 0) + ax * s * 0.12 - n * 0.15
				K:seg("SteamWand", a, b, 0.05, Look.chrome)
				K:seg("SteamKnob", a + V3(0, 0.2, 0), a + V3(0, 0.2, 0) - n * 0.15, 0.1, Look.black)
			end
			-- 압력계 (직원 쪽 위)
			for _, s in { -1, 1 } do
				local gp = e.c * V3(1, 0, 1) + V3(0, e.max.Y - 0.32, 0) - n * (half + 0.016) + ax * s * 0.35
				local g = faceCF(gp, -n)
				wdisc(K, "EspressoGauge", 0.26, 0.04, g, Look.chrome)
				wdisc(K, "EspressoGaugeFace", 0.2, 0.045, g, Look.white)
			end
		end)
	end
	for _, r in V.byName.Grinder or {} do
		machineSkin(K, r, Look.of(30, 30, 32, Enum.Material.Metal))
		K:free(function()
			K:vcyl("GrinderCollar", 0.12, math.min(r.size.X, r.size.Z) * 0.9, CF(r.c.X, r.max.Y + 0.06, r.c.Z), Look.chrome)
			local half = math.abs(n.X) * r.size.X / 2 + math.abs(n.Z) * r.size.Z / 2
			local fp = r.c + n * (half + 0.016)
			K:text("GrinderLabel", 0.5, 0.18, faceCF(V3(fp.X, r.c.Y + 0.25, fp.Z), n), "GRINDER", { fg = rgb(220, 220, 220), font = F.GothamBold, d = 0.005 })
			wdisc(K, "GrinderDial", 0.26, 0.04, faceCF(V3(fp.X, r.c.Y - 0.15, fp.Z), n), Look.chrome)
		end)
	end
	-- 진열장 (CaseBase · CaseGlass): 앞면 패널 + 크롬 모서리 + 가격 레일
	for _, cb in V.byName.CaseBase or {} do
		local cg = nil
		for _, q in V.byName.CaseGlass or {} do
			if math.abs(q.c.X - cb.c.X) < 1 and math.abs(q.c.Z - cb.c.Z) < 1 then
				cg = q
			end
		end
		local cn = n
		if math.abs(cn.Z) < 0.5 then
			cn = V3(0, 0, 1)
		end
		local fz = if cn.Z > 0 then cb.max.Z else cb.min.Z
		local w = cb.size.X
		local front = faceCF(V3(cb.c.X, 0, fz + cn.Z * 0.012), cn)
		local panelL = lk(if B.type == "dessert" then B.c1 else dk(B.c2 or rgb(40, 34, 30), 0.0), if B.type == "dessert" then M.SmoothPlastic else M.Wood)
		if B.key == "mega" or B.key == "compose" then
			panelL = Look.white
		end
		K:free(function()
			K:plate("CaseKick", w - 0.1, 0.35, 0.04, front * CF(0, 0.175, -0.02), Look.black)
			K:plate("CasePanel", w, cb.size.Y - 0.4, 0.03, front * CF(0, 0.35 + (cb.size.Y - 0.4) / 2, 0), panelL)
			K:plate("CaseRail", w, 0.2, 0.06, front * CF(0, cb.max.Y - 0.12, 0), Look.chrome)
			local nf = math.max(2, math.floor(w / 1.2))
			for k = 1, nf - 1 do
				K:plate("CasePanelGroove", 0.03, cb.size.Y - 0.6, 0.035, front * CF(-w / 2 + w * k / nf, 0.35 + (cb.size.Y - 0.4) / 2, 0), lk(dk(panelL.c, 0.2)))
			end
			K:text("CaseLabel", math.min(w * 0.6, 3.4), 0.36, front * CF(0, 1.35, 0.035), if B.type == "dessert" then "GELATO · 매일 아침 직접 만듭니다" elseif B.type == "bakery" then "오늘 구운 디저트" else "BAKERY & DESSERT", { fg = if B.type == "dessert" then rgb(255, 255, 255) else rgb(236, 226, 206), font = F.GothamBold, d = 0.01 })
			if cg and cg.size.Y < 1.6 then
				-- 낮은 젤라또 진열장: 맵의 빛 판(CaseLight) 대신 유리 상판 + 뒤쪽 LED 바
				for _, cl in V.byName.CaseLight or {} do
					if cl.c.X >= cg.min.X - 0.2 and cl.c.X <= cg.max.X + 0.2 and math.abs(cl.c.Z - cg.c.Z) < 1.5 then
						Scan.hide(K.hidden, cl.part)
					end
				end
				K:box("CaseGlassTop", V3(cg.size.X - 0.08, 0.04, cg.size.Z * 0.62), CF(cg.c.X, cg.max.Y - 0.02, cg.c.Z - cn.Z * cg.size.Z * 0.18), glassL(rgb(226, 238, 240), 0.72))
				K:box("CaseLEDBar", V3(cg.size.X - 0.1, 0.08, 0.1), CF(cg.c.X, cg.max.Y - 0.06, if cn.Z > 0 then cg.min.Z + 0.08 else cg.max.Z - 0.08), Look.lampNeutral)
			end
			if cg then
				local gfz = if cn.Z > 0 then cg.max.Z else cg.min.Z
				local gbz = if cn.Z > 0 then cg.min.Z else cg.max.Z
				for _, zz in { gfz, gbz } do
					K:box("CaseTrim", V3(cg.size.X + 0.04, 0.06, 0.06), CF(cg.c.X, cg.max.Y, zz), Look.chrome)
				end
				for _, sx in { -1, 1 } do
					for _, zz in { gfz, gbz } do
						K:box("CasePost", V3(0.05, cg.size.Y, 0.05), CF(cg.c.X + sx * cg.size.X / 2, cg.c.Y, zz), Look.chrome)
					end
				end
			end
		end)
		-- 페이스트리 (Pastry 상자 → 모양 + 가격표)
		local k = 0
		for _, pr in V.byName.Pastry or {} do
			if pr.c.X >= cb.min.X - 0.1 and pr.c.X <= cb.max.X + 0.1 and pr.c.Z >= cb.min.Z - 0.4 and pr.c.Z <= cb.max.Z + 0.4 then
				k += 1
				local info = PASTRIES[(k + B.seed) % #PASTRIES + 1]
				local pcf = facing(V3(pr.c.X, pr.min.Y, pr.c.Z), cn)
				Scan.hide(K.hidden, pr.part)
				K:free(function()
					pastry(K, pcf, info[3], 1.2)
					if not lowD(K) and pr.c.Z * cn.Z > (cb.c.Z * cn.Z) - 0.05 then
						tag(K, facing(V3(pr.c.X, pr.min.Y + 0.12, (if cn.Z > 0 then pr.max.Z + 0.12 else pr.min.Z - 0.12)), cn) * ANG(math.rad(-20), 0, 0), 0.5, 0.2, info[1] .. "\n" .. info[2])
					end
				end)
			end
		end
	end
end

local function stepRebuild(K: any, V: any, B: any, ctx: any)
	local n: Vector3 = ctx.n or V3(0, 0, 1)
	local seed = B.seed
	-- 벽 선반 병 (Jar): 원두 캐니스터 · 원두 봉투 · 시럽병 · 틴 · 화분
	local i = 0
	for _, r in V.byName.Jar or {} do
		i += 1
		Scan.hide(K.hidden, r.part)
		local pcf = facing(V3(r.c.X, r.min.Y, r.c.Z), V3(0, 0, 1))
		local kind = (i + seed) % 5
		local h = math.clamp(r.size.Y, 0.5, 1.1)
		if kind == 0 then
			K:vcyl("BeanCanister", h, 0.5, pcf * CF(0, h / 2, 0), glassL(rgb(236, 240, 242), 0.55))
			K:vcyl("BeanFill", h * 0.72, 0.44, pcf * CF(0, h * 0.37, 0), lk(rgb(78, 46, 28), M.Pebble))
			K:vcyl("BeanCanisterLid", 0.1, 0.52, pcf * CF(0, h + 0.05, 0), Look.walnut)
		elseif kind == 1 then
			K:box("BeanBag", V3(0.46, h * 0.85, 0.3), pcf * CF(0, h * 0.425, 0), Look.kraft)
			K:box("BeanBagFold", V3(0.48, 0.1, 0.32), pcf * CF(0, h * 0.85 + 0.03, 0), lk(rgb(170, 134, 90), M.Cardboard))
			K:plate("BeanBagLabel", 0.34, 0.26, 0.01, pcf * CF(0, h * 0.45, 0.15), lk(B.c1))
		elseif kind == 2 then
			K:vcyl("SyrupBottle", h * 0.7, 0.26, pcf * CF(0, h * 0.35, 0), lk(if i % 2 == 0 then rgb(150, 90, 40) else rgb(110, 30, 30), M.Glass, { t = 0.12 }))
			K:vcyl("SyrupNeck", h * 0.25, 0.1, pcf * CF(0, h * 0.82, 0), lk(rgb(150, 90, 40), M.Glass, { t = 0.12 }))
			K:vcyl("SyrupCap", 0.06, 0.12, pcf * CF(0, h * 0.97, 0), Look.black)
			K:plate("SyrupBottleLabel", 0.2, 0.22, 0.01, pcf * CF(0, h * 0.35, 0.13), Look.paper)
		elseif kind == 3 then
			K:vcyl("TeaTin", h * 0.7, 0.38, pcf * CF(0, h * 0.35, 0), lk(if i % 2 == 0 then B.c1 else rgb(40, 40, 42), M.Metal))
			K:vcyl("TeaTinLid", 0.08, 0.4, pcf * CF(0, h * 0.7 + 0.04, 0), Look.chrome)
		else
			Props.potPlant(K, pcf, 0.4, math.max(0.4, h - 0.3))
		end
	end
	-- 디저트 선반 컵 (Cup): 파인트 · 콘 타워 · 토핑 병 · 소스 · 컵 스택
	i = 0
	for _, r in V.byName.Cup or {} do
		i += 1
		Scan.hide(K.hidden, r.part)
		local pcf = facing(V3(r.c.X, r.min.Y, r.c.Z), V3(0, 0, 1))
		local kind = (i + seed) % 5
		if kind == 0 then
			for k = 0, 2 do
				local fl = FLAVORS[(i + k) % #FLAVORS + 1]
				K:vcyl("PintCup", 0.42, 0.36, pcf * CF((k - 1) * 0.4, 0.21, 0), Look.white)
				K:vcyl("PintLid", 0.06, 0.38, pcf * CF((k - 1) * 0.4, 0.45, 0), lk(fl[2]))
			end
		elseif kind == 1 then
			K:box("ConeHolder", V3(0.95, 0.32, 0.45), pcf * CF(0, 0.16, 0), Look.walnut)
			local cone = lk(rgb(214, 160, 90), M.Sand)
			for k = 0, 2 do
				local c = pcf * CF((k - 1) * 0.3, 0.32, 0)
				K:vcyl("ConeTip", 0.14, 0.08, c * CF(0, 0.07, 0), cone)
				K:vcyl("ConeBody", 0.16, 0.16, c * CF(0, 0.2, 0), cone)
				K:vcyl("ConeBody", 0.16, 0.23, c * CF(0, 0.34, 0), cone)
				K:vcyl("ConeRim", 0.1, 0.28, c * CF(0, 0.46, 0), lk(rgb(200, 146, 80), M.Sand))
				K:vcyl("ConeStackTop", 0.14, 0.27, c * CF(0, 0.57, 0), lk(rgb(220, 170, 100), M.Sand))
			end
		elseif kind == 2 then
			for k = 0, 1 do
				K:vcyl("ToppingJar", 0.5, 0.34, pcf * CF((k - 0.5) * 0.42, 0.25, 0), glassL(rgb(240, 240, 240), 0.5))
				K:vcyl("ToppingFill", 0.34, 0.3, pcf * CF((k - 0.5) * 0.42, 0.19, 0), lk(if k == 0 then rgb(250, 120, 170) else rgb(110, 70, 40), M.Pebble))
				K:vcyl("ToppingLid", 0.06, 0.36, pcf * CF((k - 0.5) * 0.42, 0.53, 0), Look.chrome)
			end
		elseif kind == 3 then
			for k = 0, 2 do
				K:vcyl("SauceBottle", 0.6, 0.22, pcf * CF((k - 1) * 0.28, 0.3, 0), lk(if k == 0 then rgb(80, 50, 30) elseif k == 1 then rgb(220, 40, 60) else rgb(230, 170, 70)))
				K:vcyl("SauceTip", 0.16, 0.08, pcf * CF((k - 1) * 0.28, 0.68, 0), Look.white)
			end
		else
			for k = 0, 1 do
				local c = pcf * CF((k - 0.5) * 0.42, 0, 0)
				K:vcyl("PaperCupStack", 0.7, 0.3, c * CF(0, 0.35, 0), lk(if k == 0 then B.cup else rgb(250, 250, 248)))
				for j = 1, 3 do
					K:vcyl("PaperCupRim", 0.03, 0.34, c * CF(0, 0.2 * j + 0.08, 0), lk(dk(if k == 0 then B.cup else rgb(250, 250, 248), 0.12)))
				end
			end
		end
	end
	-- 빵 (Bread): 바구니 + 빵 2~3 + 선반 앞 가격표
	i = 0
	local shelves = V.byName.BreadShelf or {}
	for _, r in V.byName.Bread or {} do
		i += 1
		Scan.hide(K.hidden, r.part)
		local sh = nil
		for _, s in shelves do
			if r.c.X >= s.min.X and r.c.X <= s.max.X and math.abs(r.min.Y - s.max.Y) < 0.35 then
				sh = s
			end
		end
		local y = if sh then sh.max.Y else r.min.Y
		local info = BREADS[(i + seed) % #BREADS + 1]
		local pcf = facing(V3(r.c.X, y, if sh then (sh.min.Z + sh.max.Z) / 2 + 0.1 else r.c.Z), V3(0, 0, 1))
		local bw = 1.55
		basket(K, pcf, bw, 1.1, if i % 2 == 0 then Look.rattan else Look.of(150, 110, 70, Enum.Material.Wood))
		local kind = info[3]
		local cnt = if kind == "baguette" or kind == "garlic" then 2 elseif kind == "loaf" then 1 else 3
		for k = 1, cnt do
			local ox = (k - (cnt + 1) / 2) * (if cnt == 2 then 0.0 else 0.45)
			local oz = if cnt == 2 then (k - 1.5) * 0.32 else (k % 2) * 0.12 - 0.06
			bread(K, pcf * CF(ox, 0.08, oz) * ANG(0, (k - 2) * 0.2, 0), kind, if kind == "baguette" or kind == "garlic" then 1.05 elseif kind == "loaf" or kind == "ciabatta" then 1.25 else 1.05)
		end
		if sh then
			local dcf = faceCF(V3(r.c.X, sh.c.Y, sh.max.Z + 0.012), V3(0, 0, 1))
			tag(K, dcf, 0.95, math.min(0.22, sh.size.Y + 0.02), info[1] .. "  " .. info[2])
		end
	end
	-- 빵 선반 보강: 앞 레일 · 까치발 · 선반 아래 LED
	K:free(function()
		for _, s in shelves do
			local fz = s.max.Z
			K:box("BreadShelfLip", V3(s.size.X, 0.06, 0.05), CF(s.c.X, s.max.Y + 0.03, fz - 0.02), Look.walnut)
			local nb = math.max(2, math.floor(s.size.X / 4))
			for k = 0, nb do
				local x = s.min.X + 0.2 + (s.size.X - 0.4) * k / nb
				K:box("BreadShelfBracket", V3(0.06, 0.5, 0.04), CF(x, s.min.Y - 0.25, s.min.Z + 0.03), Look.blackMetal)
				K:box("BreadShelfBracket", V3(0.06, 0.06, s.size.Z - 0.35), CF(x, s.min.Y - 0.03, s.min.Z + (s.size.Z - 0.35) / 2 + 0.05), Look.blackMetal)
			end
			if s.c.Y > 3.5 then
				local led = K:box("BreadShelfLED", V3(s.size.X - 0.4, 0.04, 0.06), CF(s.c.X, s.min.Y - 0.03, fz - 0.25), Look.lampWarm)
				if not ctx.shelfLit then
					ctx.shelfLit = K:light(led, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 6, Brightness = 0.5, Angle = 120, Color = Look.warmLight })
				end
			end
		end
	end)
	-- 젤라또 통 (GelatoTub, 게임플레이: 같은 자세 오버레이 후 숨김) + 맛 이름표
	i = 0
	for _, r in V.byName.GelatoTub or {} do
		i += 1
		local fl = FLAVORS[(i + seed) % #FLAVORS + 1]
		local top = r.max.Y
		K:free(function()
			K:box("GelatoPan", r.size, CF(r.c), Look.steel)
			K:box("GelatoSurface", V3(r.size.X - 0.08, 0.03, r.size.Z - 0.08), CF(r.c.X, top - 0.005, r.c.Z), lk(fl[2]))
			K:ell("GelatoMound", V3(r.size.X * 0.82, 0.2, r.size.Z * 0.7), CF(r.c.X, top - 0.03, r.c.Z - 0.05), lk(fl[2]))
			K:ell("GelatoWave", V3(r.size.X * 0.5, 0.14, r.size.Z * 0.3), CF(r.c.X + 0.1, top + 0.01, r.c.Z + 0.25) * ANG(0, 0.3, 0), lk(dk(fl[2], 0.08)))
			if i % 2 == 1 then
				K:box("GelatoSpade", V3(0.16, 0.02, 0.32), CF(r.c.X - 0.15, top + 0.06, r.c.Z - 0.3) * ANG(0.5, 0, 0), Look.chrome)
				K:bar("GelatoSpadeHandle", V3(r.c.X - 0.15, top + 0.12, r.c.Z - 0.45), V3(r.c.X - 0.15, top + 0.45, r.c.Z - 0.75), 0.05, 0.05, Look.black)
			end
		end)
		Scan.hide(K.hidden, r.part)
		local glass = nil
		for _, q in V.byName.CaseGlass or {} do
			if r.c.X >= q.min.X and r.c.X <= q.max.X then
				glass = q
			end
		end
		if glass then
			local dcf = faceCF(V3(r.c.X, glass.min.Y + 0.25, glass.max.Z + 0.012), V3(0, 0, 1))
			tag(K, dcf, 0.85, 0.2, fl[1], rgb(255, 255, 255), dk(fl[2], 0.55))
		end
	end
	-- 와플 기계 (WaffleIron + WaffleLid, 게임플레이: 같은 자세 오버레이 후 숨김)
	for _, r in V.byName.WaffleIron or {} do
		local lid = nil
		for _, q in V.byName.WaffleLid or {} do
			if (q.c - r.c).Magnitude < 1 then
				lid = q
			end
		end
		K:free(function()
			K:box("WaffleBase", r.size, CF(r.c), Look.of(34, 34, 36, Enum.Material.Metal))
			K:box("WafflePlate", V3(r.size.X - 0.16, 0.06, r.size.Z - 0.16), CF(r.c.X, r.max.Y - 0.03, r.c.Z), Look.of(70, 70, 74, Enum.Material.DiamondPlate))
			K:box("WaffleLED", V3(0.12, 0.04, 0.02), CF(r.c.X - r.size.X / 2 + 0.25, r.c.Y, r.max.Z + 0.005), Look.ledRed)
			K:box("WaffleLED", V3(0.12, 0.04, 0.02), CF(r.c.X - r.size.X / 2 + 0.45, r.c.Y, r.max.Z + 0.005), Look.ledGreen)
			if lid then
				K:box("WaffleLidSkin", lid.size, CF(lid.c), Look.of(44, 44, 48, Enum.Material.Metal))
				for k = -1, 1 do
					K:box("WaffleGrid", V3(lid.size.X - 0.2, 0.012, 0.04), CF(lid.c.X, lid.max.Y + 0.006, lid.c.Z + k * 0.25), Look.of(28, 28, 30))
					K:box("WaffleGrid", V3(0.04, 0.012, lid.size.Z - 0.2), CF(lid.c.X + k * 0.25, lid.max.Y + 0.006, lid.c.Z), Look.of(28, 28, 30))
				end
				K:box("WaffleHandle", V3(0.5, 0.08, 0.08), CF(lid.c.X, lid.max.Y + 0.04, lid.min.Z + 0.08), Look.black)
			end
		end)
		Scan.hide(K.hidden, r.part)
		if lid then
			Scan.hide(K.hidden, lid.part)
		end
	end
	-- 인형 (Plush): 곰 · 토끼 · 병아리
	i = 0
	local pal = { rgb(250, 190, 210), rgb(250, 230, 160), rgb(180, 220, 250), rgb(210, 180, 140), rgb(250, 250, 246), rgb(200, 240, 200), rgb(230, 200, 250) }
	for _, r in V.byName.Plush or {} do
		i += 1
		Scan.hide(K.hidden, r.part)
		local face = V3(0, 0, 1)
		local best = math.huge
		for _, j in V.byName.Joystick or {} do
			local d = (j.c - r.c) * V3(1, 0, 1)
			if d.Magnitude < best then
				best = d.Magnitude
				face = if math.abs(d.X) > math.abs(d.Z) then V3(math.sign(d.X), 0, 0) else V3(0, 0, math.sign(d.Z))
			end
		end
		local kind = (i + seed) % 3
		local col = if kind == 2 then rgb(250, 220, 90) else pal[(i * 3 + seed) % #pal + 1]
		plush(K, V3(r.c.X, r.min.Y + r.size.Y * 0.45, r.c.Z), r.size.Y * 0.95, kind, col, face)
	end
end

-- 인형뽑기 기계 꾸미기
local function stepClaw(K: any, V: any, B: any, ctx: any)
	local pal = { rgb(255, 90, 170), rgb(80, 200, 255), rgb(255, 210, 60), rgb(120, 230, 170), rgb(190, 130, 255) }
	local i = 0
	ctx.clawLeds = {}
	for _, b in V.byName.ClawBase or {} do
		i += 1
		local face = V3(0, 0, 1)
		local best = math.huge
		for _, j in V.byName.Joystick or {} do
			local d = (j.c - b.c) * V3(1, 0, 1)
			if d.Magnitude < best then
				best = d.Magnitude
				face = if math.abs(d.X) > math.abs(d.Z) then V3(math.sign(d.X), 0, 0) else V3(0, 0, math.sign(d.Z))
			end
		end
		local half = math.abs(face.X) * b.size.X / 2 + math.abs(face.Z) * b.size.Z / 2
		local w = math.abs(face.Z) * b.size.X + math.abs(face.X) * b.size.Z
		local fp = b.c + face * (half + 0.012)
		local front = faceCF(V3(fp.X, 0, fp.Z), face)
		local c = pal[(i + B.seed) % #pal + 1]
		local top = nil
		for _, q in V.byName.ClawTop or {} do
			if (q.c * V3(1, 0, 1) - b.c * V3(1, 0, 1)).Magnitude < 0.6 then
				top = q
			end
		end
		K:free(function()
			K:plate("ClawPanel", w, b.size.Y - 0.3, 0.03, front * CF(0, 0.3 + (b.size.Y - 0.3) / 2, 0), lk(c))
			K:plate("ClawKick", w - 0.1, 0.3, 0.04, front * CF(0, 0.15, -0.01), Look.black)
			K:plate("ClawPrizeDoor", 1.1, 0.8, 0.05, front * CF(-w * 0.18, 0.95, 0), Look.black)
			K:plate("ClawPrizeFlap", 1.0, 0.7, 0.06, front * CF(-w * 0.18, 0.95, 0), glassL(rgb(200, 200, 210), 0.5))
			K:text("ClawPrizeLabel", 1.0, 0.18, front * CF(-w * 0.18, 1.5, 0.04), "PRIZE ▼", { fg = rgb(255, 255, 255), font = F.GothamBlack, d = 0.005 })
			K:plate("ClawCoin", 0.42, 0.7, 0.06, front * CF(w * 0.28, 1.6, 0), Look.chrome)
			K:plate("ClawCoinSlot", 0.06, 0.24, 0.07, front * CF(w * 0.28, 1.7, 0), Look.black)
			K:text("ClawCoinLabel", 0.4, 0.14, front * CF(w * 0.28, 1.36, 0.065), "1,000", { fg = rgb(30, 30, 30), bg = rgb(255, 230, 80), d = 0.005, font = F.GothamBold })
			K:text("ClawBrand", w * 0.7, 0.3, front * CF(0, 2.45, 0.035), if i % 2 == 0 then "PICK ME!" else "LUCKY CATCH", { fg = rgb(255, 255, 255), font = F.FredokaOne, d = 0.005 })
			-- 버튼 (조작대 위)
			local bp = b.c + face * (half - 0.35) + V3(0, b.max.Y - b.c.Y + 0.03, 0)
			K:disc("ClawButton", 0.3, 0.06, CF(bp) + face:Cross(Vector3.yAxis) * 0.6, Look.ledRed)
			-- 모서리 LED 기둥
			if not lowD(K) then
				local side = face:Cross(Vector3.yAxis)
				local hTop = if top then top.max.Y else 7.9
				for _, s in { -1, 1 } do
					local p = b.c + face * (half + 0.03) + side * s * (w / 2 - 0.04)
					local led = K:box("ClawLED", V3(0.07, hTop - 0.1, 0.07), CF(p.X, hTop / 2, p.Z), Look.neon(c))
					table.insert(ctx.clawLeds, led)
				end
			end
			if top then
				local tf = top.c + face * (half + 0.015)
				K:text("ClawMarquee", w * 0.9, top.size.Y * 0.7, faceCF(V3(tf.X, top.c.Y, tf.Z), face), if i % 3 == 0 then "인형뽑기" elseif i % 3 == 1 then "BINGBING" else "♥ CATCH ♥", { fg = rgb(255, 255, 255), glow = 1.6, font = F.FredokaOne, d = 0.01 })
			end
		end)
	end
	-- 지폐교환기
	for _, r in V.byName.ChangeMachine or {} do
		local fp = r.max.Z + 0.012
		local f = faceCF(V3(r.c.X, 0, fp), V3(0, 0, 1))
		K:free(function()
			K:plate("ChangePanel", r.size.X, 2.2, 0.03, f * CF(0, 2.0, 0), lk(rgb(30, 30, 34), M.Metal))
			K:plate("ChangeBillSlot", 0.8, 0.16, 0.06, f * CF(0, 2.6, 0), Look.black)
			K:plate("ChangeBillLight", 0.7, 0.04, 0.065, f * CF(0, 2.6, 0), Look.ledGreen)
			K:plate("ChangeCoinCup", 0.8, 0.5, 0.2, f * CF(0, 1.0, 0), Look.chrome)
			K:text("ChangeLabel", r.size.X * 0.9, 0.6, f * CF(0, 3.4, 0.035), "지폐교환기\n1,000 · 5,000 · 10,000원", { fg = rgb(255, 255, 255), font = F.GothamBold, d = 0.005 })
			K:text("ChangeNotice", r.size.X * 0.9, 0.4, f * CF(0, 1.6, 0.035), "고장 · 분실 문의 010-5150-0511", { fg = rgb(255, 230, 90), font = F.GothamMedium, d = 0.005 })
		end)
	end
end

-- 5) 뒷벽 메뉴판 · 로고 · 빵 시간표
local function stepBackWall(K: any, V: any, B: any, ctx: any)
	local st = { kind = B.menuKind, bg = B.menuBg, fg = B.menuFg, acc = B.menuAcc, tfont = (if B.menuKind == "chalk" then F.PermanentMarker elseif B.menuKind == "brass" then F.Garamond else F.GothamBlack) }
	local menus = B.menus or {}
	-- 판 자리: 뒷벽 빈 구간 (넓으면 2~3 장으로 나눔). 계산대 뒤 직원 자리(6.5 까지) · 사업자등록증 위
	local function backSlots(y0: number, y1: number): { any }
		local slots = {}
		local spans = freeSpans(K, "back", y0, y1, 1.0)
		table.sort(spans, function(a, b)
			return a[1] < b[1]
		end)
		for _, sp in spans do
			local len = sp[2] - sp[1] - 0.3
			if len >= 2.0 then
				local nb = math.clamp(math.floor((len + 0.5) / 3.4), 1, 3)
				local bw = math.min(4.6, (len - (nb - 1) * 0.5) / nb)
				local total = nb * bw + (nb - 1) * 0.5
				local start = (sp[1] + sp[2]) / 2 - total / 2
				for k = 1, nb do
					table.insert(slots, { u = start + (k - 0.5) * bw + (k - 1) * 0.5, w = bw, y0 = y0, y1 = y1, wall = "back" })
				end
			end
		end
		return slots
	end
	local y1 = math.min(V.H - 0.35, 9.9)
	local slots = backSlots(math.max(6.8, y1 - 3.0), y1)
	if #slots == 0 then
		slots = backSlots(math.max(5.9, y1 - 3.2), y1)
	end
	local mi = 0
	local litDone = false
	local function place(sl: any, sec: any)
		local h = sl.y1 - sl.y0
		local dcf = V:wall(sl.wall, sl.u, sl.y0 + h / 2, 0)
		useWall(K, sl.wall, sl.u - sl.w / 2 - 0.15, sl.u + sl.w / 2 + 0.15, sl.y0, sl.y1)
		if sec then
			local face = menuPanel(K, dcf, sl.w, h - 0.2, sec[1], sec[2], st)
			if sl.wall == "back" then
				table.insert(ctx.boards, { u = sl.u, w = sl.w, y = sl.y0 + h / 2 })
			end
			if face and not litDone and (B.menuKind == "lightbox" or B.menuKind == "tv") then
				litDone = true
				K:light(face, "SurfaceLight", { Face = Enum.NormalId.Front, Range = 7, Brightness = 0.35, Angle = 110, Color = lt(B.menuBg, 0.5) })
			end
		else
			-- 남는 칸: 프로모 포스터 (사진 메뉴)
			local pw, ph = sl.w, h - 0.2
			K:plate("PromoBack", pw + 0.1, ph + 0.1, 0.06, dcf, Look.blackMetal)
			K:plate("PromoFace", pw, ph, 0.02, dcf * CF(0, 0, 0.06), lk(B.c1))
			K:text("PromoTag", pw * 0.5, 0.36, dcf * CF(0, ph / 2 - 0.35, 0.085), B.promo[1], { fg = B.paper, bg = B.c2 or BLACK, font = F.GothamBlack, d = 0.01 })
			glyph(K, dcf * CF(0, 0.05, 0.085), math.min(ph * 0.5, pw * 0.9), if B.type == "dessert" then "strawberry" else "latte")
			K:text("PromoName", pw * 0.9, 0.42, dcf * CF(0, -ph / 2 + 0.75, 0.085), B.promo[2], { fg = B.ink, font = F.GothamBlack, d = 0.01 })
			K:text("PromoPrice", pw * 0.6, 0.34, dcf * CF(0, -ph / 2 + 0.32, 0.085), B.promo[3] .. "원", { fg = B.ink, font = F.GothamBold, d = 0.01 })
		end
	end
	for idx, sl in slots do
		if mi >= #menus and idx > 3 then
			break
		end
		if mi < #menus then
			mi += 1
			place(sl, menus[mi])
		else
			place(sl, nil)
		end
	end
	-- 남은 메뉴: 계산대 가까운 옆벽 (뒤쪽 끝)
	if mi < #menus then
		local order = { "left", "right" }
		if ctx.main and (ctx.main.min.X + ctx.main.max.X) / 2 > ctx.cx then
			order = { "right", "left" }
		end
		for _, s in order do
			if mi < #menus then
				local zt = if ctx.main then math.max(V.z0 + 1.8, ctx.main.min.Z + 0.6) else V.z0 + 2
				local wn, dcf, u = wallFind(K, { s }, 3.3, 5.6, 8.6, uOf(V, s, 0, zt))
				if wn and dcf and u then
					mi += 1
					K.wallUsed[#K.wallUsed] = nil
					place({ wall = s, u = u, w = 3.0, y0 = 5.6, y1 = 8.6 }, menus[mi])
				end
			end
		end
	end
	ctx.menuPlaced = mi
	-- 메뉴판 아래 띠 (프랜차이즈: BEST 음료 사진 4)
	if (B.key == "mega" or B.key == "compose" or B.key == "busan" or B.type == "dessert") and V.H > 9 then
		local wn, dcf = wallFind(K, { "back" }, 5.6, 5.95, 6.5 + (if ctx.backSign then 1.2 else 0.0), ctx.backSign and (ctx.backSign.c.X - ctx.cx) or 0)
		if wn and dcf then
			local bh = if ctx.backSign then 1.6 else 0.5
			local bw = 5.4
			K:plate("BestStripBack", bw + 0.1, bh + 0.08, 0.05, dcf, Look.blackMetal)
			K:plate("BestStrip", bw, bh, 0.02, dcf * CF(0, 0, 0.05), lk(if B.key == "mega" then rgb(28, 28, 28) else B.paper))
			if bh > 1 then
				local kinds = { "americano", "latte", "strawberry", "ade" }
				for k = 1, 4 do
					local x = -bw / 2 + bw * (k - 0.5) / 4
					glyph(K, dcf * CF(x - 0.35, 0.0, 0.075), 1.1, kinds[k])
					local it = (B.menus[1] and B.menus[1][2][k]) or { "", "" }
					K:text("BestName", 0.75, 0.28, dcf * CF(x + 0.3, 0.18, 0.075), it[1], { fg = if B.key == "mega" then rgb(255, 255, 255) else B.ink, glow = 0.9, font = F.GothamBold, d = 0.005 })
					K:text("BestPrice", 0.6, 0.24, dcf * CF(x + 0.3, -0.18, 0.075), it[2] or "", { fg = B.c1, glow = 0.9, font = F.GothamBlack, d = 0.005 })
				end
			else
				K:text("BestLine", bw * 0.9, 0.34, dcf * CF(0, 0, 0.075), B.slogan, { fg = if B.key == "mega" then B.c1 else B.ink, glow = 0.9, font = F.GothamBlack, d = 0.005 })
			end
		end
	end
	-- 베이커리: 빵 나오는 시간 + 원산지 표시판
	if B.key == "bakery" then
		local wn, dcf = wallFind(K, { "back", "left", "right" }, 2.4, 5.8, 8.6, -V.W * 0.25)
		if wn and dcf then
			K:plate("BakeTimeFrame", 2.5, 2.9, 0.08, dcf, Look.walnut)
			K:plate("BakeTimeBoard", 2.3, 2.7, 0.1, dcf, lk(rgb(36, 40, 36), M.Slate))
			K:text("BakeTimeTitle", 2.0, 0.36, dcf * CF(0, 1.05, 0.11), "빵 나오는 시간", { fg = rgb(246, 210, 120), font = F.PermanentMarker })
			K:text("BakeTimeList", 2.1, 1.9, dcf * CF(0, -0.2, 0.11), "07:00  소금빵 · 크루아상\n09:30  우유식빵 · 바게트\n12:00  고로케 · 단팥빵\n15:00  마늘바게트 · 에그타르트\n18:00  앙버터 · 치아바타", { fg = rgb(244, 240, 228), font = F.GothamMedium, align = "Left" })
		end
	end
	-- 브랜드 로고 (뒷벽에 맵 간판이 없을 때)
	if not ctx.backSign then
		local wn, dcf = wallFind(K, { "back" }, math.min(7, V.W * 0.4), y1 + 0.05, math.min(V.H - 0.15, y1 + 0.9), 0)
		if wn and dcf then
			K:text("BackLogo", math.min(6.8, V.W * 0.38), 0.7, dcf * CF(0, 0, 0.06), B.title, { fg = B.c1, glow = 1.0, font = F.GothamBlack, d = 0.06 })
		end
	end
end

-- 6) 옆벽
local function stepSideWalls(K: any, V: any, B: any, ctx: any)
	local sides = { "left", "right" }
	local frontU = { left = uOf(V, "left", 0, V.z1 - 5), right = uOf(V, "right", 0, V.z1 - 5) }
	local midU = { left = uOf(V, "left", 0, ctx.cz), right = uOf(V, "right", 0, ctx.cz) }
	local promptPred = promptOK(K)
	-- 네온 (켜기/끄기)
	local nt = B.neon
	if nt and B.key ~= "claw" then
		local nw = math.clamp(utf8.len(nt[1]) or #nt[1], 6, 18) * 0.26 + 0.5
		local wn, dcf = promptSpot(K, { "left", "right", "back" }, nw + 0.5, { { 5.3, 6.7 }, { 5.7, 6.9 }, { 4.9, 6.3 } }, midU)
		local withPrompt = wn ~= nil
		if not wn then
			wn, dcf = wallFind(K, sides, nw + 0.5, 5.3, 6.7, midU)
		end
		if wn and dcf then
			local sign = neonSign(K, dcf, nw, 0.9, nt[1], nt[2], nt[3])
			if withPrompt then
				neonToggle(K, sign, "네온사인")
			end
		end
	end
	-- BGM 앰프 + 스피커
	local wn, dcf = promptSpot(K, { "left", "right", "back" }, 1.6, { { 3.85, 4.75 }, { 4.9, 5.8 }, { 5.45, 6.35 } }, frontU)
	if not wn then
		wn, dcf = promptSpot(K, { "left", "right", "back" }, 1.15, { { 3.85, 4.75 }, { 4.9, 5.8 }, { 5.45, 6.35 } }, frontU)
	end
	if wn and dcf then
		musicPanel(K, dcf, B, false)
	end
	local _ = promptPred
	for _, s in sides do
		local w2, d2 = wallFind(K, { s }, 0.8, V.H - 1.75, V.H - 0.55, if s == "left" then uOf(V, s, 0, V.z1 - 3.5) else uOf(V, s, 0, V.z1 - 3.5))
		if w2 and d2 then
			speaker(K, d2 * CF(0, 0.05, 0))
		end
	end
	-- 안내 보드 (와이파이 · 영업시간 · 결제)
	local wi, di = wallFind(K, sides, 2.2, 3.6, 6.1, frontU)
	if wi and di then
		infoBoard(K, di, B)
	end
	-- TV 프로모 (프랜차이즈)
	if B.feat.tv then
		local wt, dt = wallFind(K, sides, 3.2, 5.7, 7.6, midU)
		if wt and dt then
			promoScreen(K, dt, 3.0, {
				{ text = B.promo[1] .. "\n" .. B.promo[2] .. "\n" .. B.promo[3] .. "원", c = B.c1, fg = B.c2 or BLACK },
				{ text = "ICE AMERICANO\n" .. (B.menus[1][2][1][2]) .. "원", c = rgb(24, 24, 26), fg = B.c1 },
				{ text = "앱 주문하고\n스탬프 2배 적립", c = rgb(250, 250, 248), fg = rgb(24, 24, 26) },
			})
		end
	end
	-- 거울 (오뜨)
	if B.feat.mirror then
		local wm, dm = wallFind(K, sides, 2.6, 3.3, 8.0, midU)
		if wm and dm then
			K:panel("MirrorFrame", 2.5, 4.6, 0.1, 0.5, dm, Look.goldMetal)
			K:panel("Mirror", 2.25, 4.35, 0.12, 0.42, dm, Look.mirror)
		end
	end
	-- 액자
	local artKinds = { B.art, if B.key == "busan" or B.key == "ocean" or B.key == "mega" then "bridge" else "abstract", "bridge", B.art }
	local nArt = if V.W * V.D > 500 then 4 elseif V.W * V.D > 250 then 3 else 2
	for k = 1, nArt do
		local aw = if k % 2 == 1 then 2.6 else 2.0
		local ah = if k % 2 == 1 then 2.0 else 2.6
		local s = if k % 2 == 1 then { "left", "right" } else { "right", "left" }
		local wa, da = wallFind(K, s, aw + 0.3, 6.6 - ah - 0.1, 6.7, midU)
		if not wa then
			wa, da = wallFind(K, s, aw + 0.3, 7.0 - ah, 7.2, frontU)
		end
		if wa and da then
			artPiece(K, da * CF(0, 0, 0.01), aw, ah, artKinds[(k - 1) % #artKinds + 1], B, k)
		end
	end
	-- 벽 선반 (식물 · 책 · 원두)
	local ws, dsh = wallFind(K, sides, 3.2, 6.9, 8.1, midU)
	if ws and dsh then
		local at = Props.shelf(K, dsh * CF(0, -0.45, 0), 3.0, { depth = 0.75, look = if B.key == "roastery" then Look.walnut else Look.oak })
		Props.row(K, at, 2.9, if B.type == "bakery" then "jars" elseif B.key == "roastery" then "books" else "plants", { seed = B.seed % 97, n = if B.key == "roastery" then 10 else 4 })
	end
	-- 위생 · 원산지 · 콘센트 안내
	local wn2, dn = wallFind(K, sides, 1.0, 4.2, 5.2, frontU)
	if wn2 and dn then
		K:panel("HygieneBadge", 0.85, 0.85, 0.03, 0.42, dn, lk(rgb(30, 110, 200)))
		K:text("HygieneText", 0.7, 0.5, dn * CF(0, 0, 0.035), "위생등급\n매우 우수", { fg = rgb(255, 255, 255), font = F.GothamBold, d = 0.005 })
	end
	if B.type == "bakery" or B.type == "dessert" or B.key == "haute" then
		local wo, dor = wallFind(K, { "left", "right", "back" }, 1.9, 3.5, 5.3, frontU)
		if wo and dor then
			notice(K, dor, 1.8, 1.6, "원산지 표시\n밀가루: 미국산 · 캐나다산\n버터: 뉴질랜드산\n우유 · 계란: 국내산\n딸기: 국내산 (논산)\n팥: 국내산", rgb(30, 30, 30), rgb(250, 250, 246))
		end
	else
		local wo, dor = wallFind(K, sides, 1.5, 3.2, 3.9, midU)
		if wo and dor then
			notice(K, dor, 1.4, 0.55, "콘센트 사용 가능\n노트북 이용 2시간", rgb(40, 40, 40), rgb(250, 248, 240))
		end
	end
	-- 윗벽 띠 문구
	if V.H >= 9.5 and B.key ~= "claw" then
		for _, s in sides do
			local wl, dl = wallFind(K, { s }, math.min(9, V.D * 0.5), 8.35, 9.05, midU)
			if wl and dl then
				K:text("WallSlogan", math.min(8.6, V.D * 0.48), 0.5, dl * CF(0, 0, 0.02), B.slogan, { fg = if B.key == "mega" then rgb(30, 30, 30) elseif B.key == "compose" then B.c1 else lt(B.ink, 0.15), font = F.GothamBlack, d = 0.02 })
			end
		end
	end
end

-- 인형뽑기방 벽 (기계 위 높은 띠 + 조작 패널)
local function stepClawWalls(K: any, V: any, B: any, ctx: any)
	local promptPred = promptOK(K)
	local midU = { left = uOf(V, "left", 0, ctx.cz), right = uOf(V, "right", 0, ctx.cz) }
	local wn, dcf = wallFind(K, { "back" }, 7.0, 8.3, 10.2, 0)
	if wn and dcf then
		ctx.clawSign = neonSign(K, dcf, 6.4, 1.5, B.neon[1], B.neon[2], B.neon[3])
	end
	local words = { "PICK ME UP!", "오늘은 꼭 뽑자!" }
	ctx.wallNeons = {}
	for k, s in { "left", "right" } do
		local w2, d2 = wallFind(K, { s }, 6.0, 8.4, 9.8, midU[s])
		if w2 and d2 then
			table.insert(ctx.wallNeons, neonSign(K, d2, 5.4, 1.0, words[k], if k == 1 then rgb(80, 220, 255) else rgb(255, 210, 60), F.FredokaOne, false))
		end
	end
	-- 조작 패널 (LED 모드) + BGM
	local _ = promptPred
	local wp, dp = promptSpot(K, { "left", "right", "back" }, 0.95, { { 3.9, 4.9 }, { 5.5, 6.5 }, { 4.9, 5.9 } }, midU)
	if wp and dp then
		K:plate("LEDPanel", 0.85, 0.9, 0.08, dp, Look.of(30, 30, 34, Enum.Material.Metal))
		local scr, lab = K:text("LEDPanelScreen", 0.7, 0.3, dp * CF(0, 0.16, 0.09), "LED: PARTY", { fg = rgb(255, 120, 220), bg = rgb(10, 8, 16), glow = 1.3, font = F.Code, d = 0.01 })
		for k = -1, 1 do
			wdisc(K, "LEDPanelButton", 0.16, 0.04, dp * CF(k * 0.24, -0.22, 0.08), Look.neon(if k == -1 then rgb(255, 60, 160) elseif k == 0 then rgb(60, 200, 255) else rgb(255, 220, 60)))
		end
		local signs = {}
		if ctx.clawSign then
			table.insert(signs, ctx.clawSign)
		end
		for _, sg in ctx.wallNeons or {} do
			table.insert(signs, sg)
		end
		local modes = { { "PARTY", nil }, { "PINK", rgb(255, 80, 180) }, { "OCEAN", rgb(60, 190, 255) }, { "GOLD", rgb(255, 200, 60) }, { "OFF", rgb(60, 60, 70) } }
		local leds = {}
		for _, p in ctx.clawLeds or {} do
			table.insert(leds, { p = p, c = p.Color })
		end
		local mode = 1
		Interact.cycle(K, scr, modes, {
			action = "LED 모드",
			object = "매장 조명",
			on = function(i: number, m: any)
				mode = i
				lab.Text = "LED: " .. m[1]
				for _, l in leds do
					if l.p.Parent then
						l.p.Color = m[2] or l.c
						l.p.Material = if m[1] == "OFF" then M.SmoothPlastic else M.Neon
					end
				end
				local off = m[1] == "OFF"
				for _, sg in signs do
					local gui = sg.part and sg.part:FindFirstChildWhichIsA("SurfaceGui")
					if sg.label then
						sg.label.TextColor3 = if off then dk(sg.color, 0.6) else sg.color
					end
					if gui then
						gui.Brightness = if off then 1 else 2.1
						gui.LightInfluence = if off then 1 else 0
					end
					if sg.light then
						sg.light.Enabled = not off
					end
				end
			end,
		})
		Interact.anim(K, function(t: number)
			if mode ~= 1 then
				return
			end
			for k, l in leds do
				if l.p.Parent then
					local f = 0.5 + 0.5 * math.sin(t * 3 + k * 0.7)
					l.p.Color = l.c:Lerp(WHITE, f * 0.35)
				end
			end
		end)
	end
	local wm, dm = promptSpot(K, { "right", "left", "back" }, 1.05, { { 3.85, 4.75 }, { 5.5, 6.4 }, { 4.9, 5.8 } }, midU)
	if wm and dm then
		musicPanel(K, dm, B, true)
	end
	-- 안내 (가격 · CCTV · 무인)
	local wi, di = wallFind(K, { "left", "right", "back" }, 1.8, 5.2, 7.0, midU)
	if wi and di then
		notice(K, di, 1.7, 1.6, "1PLAY 1,000원\n5,000원 = 6PLAY\n\nCCTV 24시간 녹화중\n무인 운영 매장입니다", rgb(255, 255, 255), rgb(40, 20, 60))
	end

	-- 아이스크림 냉동고 뚜껑 (밀어 열기)
	if ctx.freezer and ctx.freezer.Parent then
		local lid: BasePart = ctx.freezer
		local base = lid.CFrame
		local w = lid.Size.X
		Interact.toggle(K, lid, {
			object = "아이스크림 냉동고",
			onText = "뚜껑 열기",
			offText = "뚜껑 닫기",
			state = true,
			on = function(state: boolean)
				lid.CFrame = if state then base else base * CF(w * 0.9, 0.04, 0)
			end,
		})
	end
end

-- 7) 천장
local function stepCeiling(K: any, V: any, B: any, ctx: any)
	local feat = B.feat or {}
	if feat.ducts then
		ducts(K, V)
	end
	-- 메뉴판 레일 조명 (칠판 · 펠트 · 브라스)
	if (feat.track or B.menuKind == "chalk" or B.menuKind == "felt" or B.menuKind == "brass") and #ctx.boards > 0 then
		local z = V.z0 + 2.2
		for _, b in ctx.boards do
			local x = b.u + ctx.cx
			if Common.ceilFree(K, x, z, 0.6) then
				Props.trackLight(K, V3(x - b.w / 2 + 0.3, 0, z), V3(x + b.w / 2 - 0.3, 0, z), math.max(2, math.floor(b.w / 1.5)), { aim = V3(0, -1, -1.1), look = Look.blackMetal })
				Common.useCeil(K, x, z)
			end
		end
	end
	-- 픽업 전광판
	if ctx.main and B.feat.pickup ~= false and not B.noCounter then
		local g = ctx.main
		local n = ctx.n
		local x, z
		if ctx.alongX then
			x = ctx.pickU
			z = if n.Z > 0 then g.max.Z + 0.6 else g.min.Z - 0.6
		else
			z = ctx.pickU
			x = if n.X > 0 then g.max.X + 0.6 else g.min.X - 0.6
		end
		local fx, fz = nil, nil
		for _, dz in { 0, 0.6, 1.2, 1.8, 2.4 } do
			for k = 0, 8 do
				local off = (if k % 2 == 0 then 1 else -1) * math.floor((k + 1) / 2) * 0.6
				local xx = if ctx.alongX then x + off else x + n.X * dz
				local zz = if ctx.alongX then z + n.Z * dz else z + off
				if not fx and Common.ceilFree(K, xx, zz, 1.25) then
					fx, fz = xx, zz
				end
			end
		end
		if fx and fz then
			pickupBoard(K, fx, fz, n, B)
			Common.useCeil(K, fx, fz)
		end
	end
	-- 행잉 화분
	if feat.hangPlants then
		local n = 0
		for _, f in { { 0.25, 0.55 }, { 0.75, 0.55 }, { 0.5, 0.7 }, { 0.15, 0.75 } } do
			local x, z = V.x0 + V.W * f[1], V.z0 + V.D * f[2]
			if n < 3 and Common.ceilFree(K, x, z, 0.8) then
				hangingPlant(K, x, z, 2.2 + (n % 2) * 0.5)
				Common.useCeil(K, x, z)
				n += 1
			end
		end
	end
	-- 인형뽑기방: 천장 LED 띠
	if feat.leds then
		local cols = { rgb(255, 70, 190), rgb(70, 210, 255) }
		local y = V.H - 0.06
		K:free(function()
			for k = 0, 3 do
				local z = V.z0 + V.D * (0.15 + k * 0.23)
				local p = K:box("CeilingLED", V3(V.W - 1.0, 0.05, 0.1), CF(ctx.cx, y, z), Look.neon(cols[k % 2 + 1]))
				table.insert(ctx.clawLeds, p)
			end
			for _, s in { -1, 1 } do
				local p = K:box("CeilingLED", V3(0.1, 0.05, V.D - 1.0), CF(ctx.cx + s * (V.W / 2 - 0.6), y, ctx.cz), Look.neon(cols[1]))
				table.insert(ctx.clawLeds, p)
			end
		end)
	end
end

-- 8) 유형 특수: 로스터 · 오븐 · 탕후루 · 아일랜드 · 집게 (바닥 단계에서 정한 자리)
local function stepSpecial(K: any, V: any, B: any, ctx: any)
	local R = ctx.roaster
	if R and R.panel and R.panel.Parent then
		local on = false
		local ang = 0
		Interact.toggle(K, R.panel, {
			object = "커피 로스터",
			onText = "로스팅 시작",
			offText = "로스팅 멈춤",
			state = true,
			on = function(_s: boolean)
				on = not on
				if R.glass and R.glass.Parent then
					R.glass.Material = if on then M.Neon else M.Glass
					R.glass.Color = if on then rgb(255, 120, 40) else rgb(120, 70, 40)
				end
				if R.label then
					R.label.Text = if on then "ROASTING\nBT 198℃  ▲" else "STANDBY\nBT 25℃"
				end
			end,
		})
		Interact.anim(K, function(_t: number, dt: number)
			if not on then
				return
			end
			ang += (dt or 0.1) * PI
			local c = CF(R.center)
			for k, a in R.arms do
				if a.Parent then
					a.CFrame = c * ANG(0, ang, 0) * c:Inverse() * R.armBase[k]
				end
			end
		end)
	end
	-- 오븐 창 깜빡임 (불꽃 느낌)
	if ctx.oven and ctx.oven.glows then
		local gl = ctx.oven.glows
		Interact.anim(K, function(t: number)
			for k, g in gl do
				if g.Parent then
					g.Transparency = 0.2 + 0.15 * math.abs(math.sin(t * 1.3 + k))
				end
			end
		end)
	end
	-- 탕후루 쇼케이스 (냉장, 앞 유리) + 꼬치
	if ctx.tangCase then
		local pcf: CFrame = ctx.tangCase
		local w, d, h = 3.6, 2.2, 4.4
		K:box("TangCaseBase", V3(w, 2.2, d), pcf * CF(0, 1.1, 0), lk(B.c1))
		K:box("TangCaseKick", V3(w - 0.1, 0.3, 0.05), pcf * CF(0, 0.15, d / 2 + 0.02), Look.black)
		K:text("TangCaseLabel", w * 0.8, 0.5, faceCF((pcf * CF(0, 1.3, d / 2 + 0.01)).Position, pcf.ZVector), "탕후루 · 당일 생과일", { fg = rgb(255, 255, 255), font = F.GothamBlack, d = 0.01 })
		K:box("TangCaseFloor", V3(w - 0.2, 0.06, d - 0.2), pcf * CF(0, 2.23, 0), Look.white)
		K:box("TangCaseGlass", V3(w, 1.7, 0.05), pcf * CF(0, 2.2 + 0.85, d / 2 - 0.03) * ANG(-0.25, 0, 0), glassL(rgb(230, 240, 244), 0.75))
		K:box("TangCaseTop", V3(w, 0.06, d * 0.5), pcf * CF(0, 4.0, -d * 0.25), glassL(rgb(230, 240, 244), 0.7))
		for _, sx in { -1, 1 } do
			K:box("TangCaseSide", V3(0.05, 1.8, d), pcf * CF(sx * (w / 2 - 0.03), 3.1, 0), glassL(rgb(230, 240, 244), 0.75))
		end
		local lamp = K:box("TangCaseLamp", V3(w - 0.3, 0.04, 0.1), pcf * CF(0, 3.95, -0.2), Look.lampNeutral)
		local _ = lamp
		-- 꼬치 (누운 줄 3 x 7 종)
		local rows = 3
		for rr = 0, rows - 1 do
			local zz = -d / 2 + 0.45 + rr * 0.55
			K:box("TangTray", V3(w - 0.4, 0.04, 0.48), pcf * CF(0, 2.28, zz), Look.white)
			for k = 0, 6 do
				local kind = FRUIT_ORDER[(k + rr) % #FRUIT_ORDER + 1]
				local x = -(w - 0.6) / 2 + (w - 0.6) * k / 6
				skewer(K, pcf * CF(x, 2.43, zz + 0.2) * ANG(-PI / 2 + 0.05, 0, 0), kind, 0.9)
			end
			tag(K, faceCF((pcf * CF(0, 2.32, zz + 0.25)).Position, pcf.ZVector), 1.0, 0.12, if rr == 0 then "딸기 3,500 · 샤인 4,500" elseif rr == 1 then "블루베리 4,000 · 귤 3,000" else "키위 3,500 · 토마토 3,000")
		end
		-- 위: 꼬치 스탠드 (세워 꽂은 꼬치)
		local sb = pcf * CF(0.9, 4.03, -d * 0.25)
		K:box("TangStand", V3(1.2, 0.22, 0.4), sb * CF(0, 0.11, 0), Look.walnut)
		for k = 0, 5 do
			skewer(K, sb * CF(-0.5 + k * 0.2, 0.2, 0) * ANG(0, 0, (k - 2.5) * 0.08), FRUIT_ORDER[k % #FRUIT_ORDER + 1], 1.0)
		end
		-- 과일 상자
		local fb = pcf * CF(-0.9, 4.03, -d * 0.25)
		K:box("FruitCrate", V3(1.2, 0.3, 0.8), fb * CF(0, 0.15, 0), Look.pine)
		for k = 0, 9 do
			K:ell("CrateStrawberry", V3(0.2, 0.22, 0.2), fb * CF(-0.45 + (k % 5) * 0.22, 0.36, -0.15 + math.floor(k / 5) * 0.3), lk(rgb(214, 28, 48)))
		end
	end
	-- 베이커리 아일랜드 진열대
	if ctx.island then
		local pcf: CFrame = ctx.island
		local w, d, h = 4.2, 2.4, 2.9
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				K:box("IslandLeg", V3(0.2, h - 0.12, 0.2), pcf * CF(sx * (w / 2 - 0.2), (h - 0.12) / 2, sz * (d / 2 - 0.2)), Look.walnut)
			end
		end
		K:box("IslandShelf", V3(w - 0.3, 0.1, d - 0.3), pcf * CF(0, 0.6, 0), Look.walnut)
		K:box("IslandApron", V3(w - 0.2, 0.3, d - 0.2), pcf * CF(0, h - 0.27, 0), Look.walnut)
		K:box("IslandTop", V3(w, 0.12, d), pcf * CF(0, h - 0.06, 0), Look.oak)
		for k = 0, 2 do
			K:box("IslandBagBox", V3(1.0, 0.5, 0.8), pcf * CF(-1.3 + k * 1.3, 0.9, 0), Look.kraft)
		end
		local idx = 0
		for bx = -1, 1 do
			for bz = 0, 1 do
				idx += 1
				local info = BREADS[(idx * 3 + B.seed) % #BREADS + 1]
				local bc = pcf * CF(bx * 1.35, h, (bz - 0.5) * 1.05)
				basket(K, bc, 1.2, 0.9, if idx % 2 == 0 then Look.rattan else Look.of(150, 110, 70, Enum.Material.Wood))
				local kind = info[3]
				local cnt = if kind == "baguette" or kind == "garlic" then 2 elseif kind == "loaf" then 1 else 3
				for j = 1, cnt do
					bread(K, bc * CF((j - (cnt + 1) / 2) * (if cnt == 2 then 0 else 0.36), 0.08, if cnt == 2 then (j - 1.5) * 0.3 else 0) * ANG(0, j * 0.3, 0), kind, if kind == "baguette" or kind == "garlic" then 0.9 else 1.1)
				end
				local zf = if bz == 1 then d / 2 + 0.012 else -d / 2 - 0.012
				local nrm = if bz == 1 then pcf.ZVector else -pcf.ZVector
				tag(K, faceCF((pcf * CF(bx * 1.35, h - 0.27, zf)).Position, nrm), 0.95, 0.22, info[1] .. "  " .. info[2])
			end
		end
	end
	-- 집게 · 쟁반 안내 (TrayStation 옆벽)
	for _, ts in V.byName.TrayStation or {} do
		local best, bw = nil, math.huge
		for _, wn in { "left", "right", "back" } do
			local u, d = V:wallCoord(wn, ts.c)
			if d < bw then
				best, bw = { wn, u }, d
			end
		end
		if best and bw < 2.5 then
			local wn, dcf = wallFind(K, { best[1] }, 2.0, 3.6, 4.6, best[2])
			if wn and dcf then
				K:plate("TongRail", 1.8, 0.08, 0.1, dcf * CF(0, 0.25, 0), Look.chrome)
				for k = 0, 3 do
					local x = -0.6 + k * 0.4
					K:bar("Tong", (dcf * CF(x, 0.22, 0.1)).Position, (dcf * CF(x + 0.04, -0.4, 0.12)).Position, 0.05, 0.03, Look.steel)
					K:bar("Tong", (dcf * CF(x + 0.06, 0.22, 0.1)).Position, (dcf * CF(x + 0.12, -0.4, 0.12)).Position, 0.05, 0.03, Look.steel)
				end
				K:text("TongSign", 1.8, 0.3, dcf * CF(0, 0.52, 0.04), if B.type == "bakery" then "쟁반과 집게를 이용해 주세요" else "쟁반 · 스푼은 이곳에", { fg = rgb(60, 40, 30), bg = rgb(252, 246, 232), d = 0.02, font = F.GothamBold })
			end
		end
	end
end

-- keep 에 닿되 통로(aisle)뿐인가? (기존 가구 발자국 안에 붙이는 작은 부착물은 통로 keep 을 허용)
local function onlyAisle(K: any, mn: Vector3, mx: Vector3): boolean
	for _, k in K.V.keep do
		if Kit.overlap(mn, mx, k.min, k.max, 0.04) and k.kind ~= "aisle" then
			return false
		end
	end
	return true
end

-- 창가 바: 발받침 레일 + 바 아래 콘센트 박스 (USB)
local function stepBars(K: any, V: any, B: any, ctx: any)
	for _, t in V.tables do
		if t.kind == "bar" and (t.max.X - t.min.X) >= (t.max.Z - t.min.Z) and (t.max.X - t.min.X) > 3 then
			local cz = (t.min.Z + t.max.Z) / 2
			local side = 1
			for _, st in V.stools do
				if st.seat.c.X >= t.min.X - 0.5 and st.seat.c.X <= t.max.X + 0.5 and math.abs(st.seat.c.Z - cz) < 3 then
					side = if st.seat.c.Z < cz then -1 else 1
				end
			end
			local zf = if side < 0 then t.min.Z else t.max.Z
			local n = V3(0, 0, side)
			-- 발받침 레일
			local zr = zf + side * 0.18
			-- 문 · 좌석 keep 을 피한 가장 긴 구간
			local bestA, bestB, curA = 0, 0, nil
			local xs = t.min.X + 0.35
			while xs <= t.max.X - 0.35 + 1e-6 do
				local ok = onlyAisle(K, V3(xs - 0.15, 0.0, zr - 0.1), V3(xs + 0.15, 0.86, zr + 0.1))
				if ok then
					curA = curA or xs
					if xs - curA > bestB - bestA then
						bestA, bestB = curA, xs
					end
				else
					curA = nil
				end
				xs += 0.25
			end
			local x0, x1 = bestA, bestB
			if x1 - x0 >= 2.0 then
				K:free(function()
					K:seg("FootRail", V3(x0, 0.78, zr), V3(x1, 0.78, zr), 0.12, Look.chrome)
					local nb = math.max(2, math.floor((x1 - x0) / 3.5) + 1)
					for k = 0, nb - 1 do
						local x = x0 + 0.3 + (x1 - x0 - 0.6) * k / math.max(1, nb - 1)
						K:seg("FootRailPost", V3(x, 0.02, zr), V3(x, 0.78, zr), 0.08, Look.chrome)
						K:disc("FootRailFoot", 0.24, 0.03, CF(x, 0.015, zr), Look.chrome)
					end
				end)
			end
			-- 콘센트 (2.6 간격)
			local y = t.y - 0.34
			local nb = math.max(1, math.floor((t.max.X - t.min.X) / 2.6))
			for k = 1, nb do
				local x = t.min.X + (t.max.X - t.min.X) * (k - 0.5) / nb
				local c = V3(x, y, zf - side * 0.1)
				local bmn, bmx = c - V3(0.3, 0.13, 0.1), c + V3(0.3, 0.13, 0.1)
				if onlyAisle(K, bmn, bmx) then
					K.freeDepth += 1
					K:box("OutletBox", V3(0.56, 0.24, 0.16), CF(c), Look.white)
					local dcf = faceCF(c + n * 0.081, n)
					for j = -1, 1 do
						if j == 1 then
							K:plate("OutletUSB", 0.1, 0.05, 0.01, dcf * CF(0.18, 0.03, 0), Look.black)
							K:plate("OutletUSB", 0.1, 0.05, 0.01, dcf * CF(0.18, -0.05, 0), Look.black)
						else
							wdisc(K, "OutletSocket", 0.14, 0.01, dcf * CF(if j == -1 then -0.15 else -0.01, 0, 0), Look.offWhite)
						end
					end
					K.freeDepth -= 1
				end
			end
		end
	end
end

-- 주문하는 곳 표시 (POS 위, 천장에 매닮)
local function orderSign(K: any, V: any, B: any, ctx: any)
	local g, pos = ctx.main, ctx.pos
	if not g or not pos or B.noCounter then
		return
	end
	local n = ctx.n
	for _, dz in { 0.6, 1.2, 1.8 } do
		for k = 0, 6 do
			local off = (if k % 2 == 0 then 1 else -1) * math.floor((k + 1) / 2) * 0.5
			local x = if ctx.alongX then pos.c.X + off else (if n.X > 0 then g.max.X else g.min.X) + n.X * dz
			local z = if ctx.alongX then (if n.Z > 0 then g.max.Z else g.min.Z) + n.Z * dz else pos.c.Z + off
			if Common.ceilFree(K, x, z, 1.0) then
				Common.useCeil(K, x, z)
				local y = V.H - 1.0
				local c = facing(V3(x, y, z), n)
				K:free(function()
					for _, sx in { -1, 1 } do
						K:seg("OrderRod", (c * CF(sx * 0.7, 0.3, 0)).Position, V3(x, V.H, z) + c.XVector * sx * 0.7, 0.04, Look.blackMetal)
					end
					K:box("OrderBox", V3(1.8, 0.6, 0.1), c, lk(B.c2 or BLACK))
					K:text("OrderText", 1.6, 0.46, c * CF(0, 0, 0.051), "ORDER · 주문하는 곳", { fg = B.c1, glow = 1.2, font = F.GothamBold, d = 0.005 })
				end)
				return
			end
		end
	end
end

-- 의자 · 소파 리스킨 (Common.chairs 대신 여기서: 소파 Seat 는 소파 모양 오버레이, 원래 자세 · 윗면 그대로)
local function roundOver(K: any, name: string, r: any, rad: number, look: any)
	if r.size.X >= r.size.Z then
		K:rbox(name, r.size, rad, CF(r.c), look)
	else
		K:rbox(name, V3(r.size.Z, r.size.Y, r.size.X), rad, CF(r.c) * ANG(0, PI / 2, 0), look)
	end
end

local function sofaOverlay(K: any, ch: any, done: { [any]: boolean }, B: any)
	local fab = lk(B.sofa or rgb(176, 156, 136), M.Fabric)
	local dark = lk(dk(fab.c, 0.16), M.Fabric)
	local s = ch.seat
	K:free(function()
		for _, r in ch.parts do
			if not done[r] then
				done[r] = true
				local nm = r.name
				if r == s then
					K:slab("SofaCushion", r.size.X, r.size.Z, r.size.Y, 0.22, CF(r.c), fab)
					K:slab("SofaCushionPiping", r.size.X + 0.02, r.size.Z + 0.02, 0.04, 0.23, CF(r.c.X, r.min.Y + 0.08, r.c.Z), dark)
				elseif nm == "Plinth" then
					K:box("SofaPlinth", r.size, CF(r.c), Look.brass)
				elseif nm == "Base" then
					K:box("SofaBase", r.size, CF(r.c), dark)
				elseif nm == "Backrest" or nm == "ChairBack" then
					roundOver(K, "SofaBack", r, 0.35, fab)
					-- 단추 터프팅 (앞면)
					local d = (s.c - r.c) * V3(1, 0, 1)
					if d.Magnitude > 0.05 and hi(K) then
						local nrm = if math.abs(d.X) > math.abs(d.Z) then V3(math.sign(d.X), 0, 0) else V3(0, 0, math.sign(d.Z))
						local along = nrm:Cross(Vector3.yAxis)
						local half = math.abs(nrm.X) * r.size.X / 2 + math.abs(nrm.Z) * r.size.Z / 2
						local len = math.abs(along.X) * r.size.X + math.abs(along.Z) * r.size.Z
						local nb = math.max(3, math.floor(len / 1.1))
						for row = 0, 1 do
							for k = 1, nb do
								local p = r.c + nrm * (half + 0.01) + along * (-len / 2 + len * (k - 0.5 + row * 0.5) / (nb + 0.5)) + V3(0, (row - 0.2) * 0.8 + 0.4, 0)
								K:ball("SofaButton", 0.1, CF(p), dark)
							end
						end
					end
				elseif nm == "Arm" then
					roundOver(K, "SofaArm", r, 0.3, fab)
				else
					K:box("Sofa" .. nm, r.size, CF(r.c), fab)
				end
				Scan.hide(K.hidden, r.part)
			end
		end
	end)
	K:reserve(V3(s.min.X - 0.3, 0, s.min.Z - 0.3), V3(s.max.X + 0.3, ch.top + 2, s.max.Z + 0.3), "chair")
end

local function stepChairs(K: any, V: any, B: any, S: any)
	local cs = S.myChair
	if not cs then
		return
	end
	local done: { [any]: boolean } = {}
	local n = #V.chairs
	local detail = K.detail
	if n * 30 > K.maxParts * 0.4 then
		detail = if n * 22 > K.maxParts * 0.4 then "low" else "mid"
	end
	for _, ch in V.chairs do
		local s = ch.seat
		if s.part:IsA("Seat") and s.part.Transparency >= 0.99 then
			continue
		end
		local isSofa = s.name == "Seat" or s.name == "SofaSeat" or s.size.X * s.size.Z > 4.5
		if isSofa then
			sofaOverlay(K, ch, done, B)
		else
			local w = math.max(1.1, math.min(2.2, math.min(s.size.X, s.size.Z) + 0.05))
			local backH = 1.8
			if ch.back then
				backH = math.clamp(ch.back.max.Y - ch.top, 1.0, 3.2)
			end
			local o = table.clone(cs)
			o.seatTop, o.w, o.d = ch.top, w, w
			o.backH = o.backH or backH
			o.detail = if detail == "high" then o.detail else detail
			local p = V3(s.c.X, 0, s.c.Z)
			local pcf = CFrame.lookAt(p, p - ch.face)
			K:free(function()
				Props.chair(K, pcf, o)
			end)
			for _, r in ch.parts do
				Scan.hide(K.hidden, r.part)
			end
			K:reserve(V3(s.min.X - 0.3, 0, s.min.Z - 0.3), V3(s.max.X + 0.3, ch.top + backH, s.max.Z + 0.3), "chair")
		end
	end
end

-- 짓기 ------------------------------------------------------------------------------------------------------
function T.build(K: any, V: any, S: any)
	local B = (S and S.brand) or brandOf(V)
	B.type = V.type
	local ctx = context(K, V, B)
	local okC, errC = pcall(stepChairs, K, V, B, S or {})
	if not okC then
		K:note("cafe.chairs error: " .. tostring(errC))
	end
	local steps: { any } = {
		{ "shell", stepShell },
		{ "floor", stepFloor },
		{ "counters", stepCounters },
		{ "bars", stepBars },
		{ "order", orderSign },
		{ "machines", stepMachines },
		{ "rebuild", stepRebuild },
	}
	if B.key == "claw" then
		table.insert(steps, { "claw", stepClaw })
		table.insert(steps, { "ceiling", stepCeiling })
		table.insert(steps, { "clawWalls", stepClawWalls })
	else
		table.insert(steps, { "back", stepBackWall })
		table.insert(steps, { "special", stepSpecial })
		table.insert(steps, { "sides", stepSideWalls })
		table.insert(steps, { "ceiling", stepCeiling })
	end
	local function where(cf: CFrame?): string
		if not cf then
			return "-"
		end
		local p = cf.Position
		return string.format("(%.1f,%.1f)", p.X, p.Z)
	end
	ctx.where = where
	for _, st in steps do
		local fn = st[2]
		local ok, err = pcall(function()
			if st[1] == "rebuild" or st[1] == "claw" then
				K:free(function()
					fn(K, V, B, ctx)
				end)
			else
				fn(K, V, B, ctx)
			end
		end)
		if not ok then
			K:note("cafe." .. st[1] .. " error: " .. tostring(err))
		end
	end
	K:note(string.format("cafe[%s] menus=%d boards=%d placed=%s", B.key, ctx.menuPlaced or 0, #ctx.boards, table.concat(ctx.placed or {}, " ")))
end

return T

end

__defs["T_clinic"] = function()
-- GwangalliBuildingInterior/T_clinic: 광안 메디컬 의원 방 유형 실내 (Venues.luau 의 방, Scan.fitRoom).
--   clinic_lobby (접수 · 수납) clinic_waiting (대기실) clinic_consult (진료실 1 · 내과) clinic_pharmacy (약국 코너)
--   clinic_treat (주사실 · 처치실) clinic_hall (후면 홀) clinic_ward (입원실 201 · 202) clinic_nurse (간호사실)
--   clinic_lounge (휴게실) clinic_checkup (건강검진센터)
--   style(V) -> S  (Common 단계는 전부 건너뜀: 아래 build 에서 방 틀을 다시 맞춘 뒤 직접 부름)
--   build(K, V, S) 유형별 디테일
-- 방 틀 다시 맞추기 (refit): 병원 건물은 월드 축에서 약 1.9도 돌아가 있고 rooms.json 상자는 월드 축 · 벽 안쪽 면과
-- 0.4~2 스터드 어긋나 있어, 건물 벽에 맞춘 회전 틀 + 실제 벽 안쪽 면 상자로 Scan.fitRoom 을 다시 합니다 (K.V / K.cf 교체).
-- 지켜야 할 것 (서버 계약): HospitalPrompt 앵커 · 프롬프트, HospitalBed BedSeat (자리 · 높이 그대로, 보이게),
-- HospitalStaff 리그, GwProp 주사기, AutoDoor_Hospital, Door_* 모델, LEDScreen, Seat 파트 (숨겨도 앉기는 그대로),
-- Law/Hospital NPC 지점 사이 통로 (아래 SPOTS/LANES 로 keep 추가).

local Look = __require("Look")
local Props = __require("Props")
local Interact = __require("Interact")
local Common = __require("Common")
local Scan = __require("Scan")

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local T = {}
T.types = { "clinic_lobby", "clinic_waiting", "clinic_consult", "clinic_pharmacy", "clinic_treat", "clinic_hall", "clinic_ward", "clinic_nurse", "clinic_lounge", "clinic_checkup" }

local M = Enum.Material
local CF, V3, ANG = CFrame.new, Vector3.new, CFrame.Angles
local PI = math.pi
local C3 = Color3.fromRGB
local FONT_B, FONT_M, FONT_K = Enum.Font.GothamBold, Enum.Font.GothamMedium, Enum.Font.GothamBlack

-- 색 · 재질 ----------------------------------------------------------------------------------------------
local TEAL = C3(0, 128, 118) -- 맵 병원 브랜드 청록
local TEAL_D = C3(0, 92, 86)
local MINT = C3(196, 232, 226)
local MINT_L = C3(228, 245, 241)
local WHITE = C3(250, 250, 248)
local INK = C3(30, 34, 38)
local GREY_T = C3(96, 102, 108)
local RED = C3(206, 36, 40)
local NAVY = C3(28, 50, 92)
local GREEN_EXIT = C3(0, 150, 80)

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
local function darker(c: Color3, t: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), t)
end

local LK = {
	white = lk(246, 246, 243),
	paint = lk(240, 240, 236),
	abs = lk(236, 238, 236, M.Plastic),
	absGrey = lk(178, 184, 188, M.Plastic),
	absDark = lk(86, 92, 98, M.Plastic),
	steel = Look.steel,
	chrome = Look.chrome,
	alu = Look.alu,
	darkAlu = Look.darkAlu,
	black = Look.black,
	rubber = Look.rubber,
	teal = col(TEAL),
	tealD = col(TEAL_D),
	mint = col(MINT),
	vinylTeal = lk(46, 120, 124, M.Leather),
	vinylNavy = lk(40, 56, 88, M.Leather),
	vinylGrey = lk(118, 124, 130, M.Leather),
	vinylMint = lk(150, 200, 196, M.Leather),
	vinylCream = lk(226, 218, 200, M.Leather),
	mattress = lk(170, 196, 214, M.Leather),
	sheet = lk(244, 246, 246, M.Fabric),
	curtain = lk(150, 198, 200, M.Fabric),
	curtainMesh = lk(228, 240, 238, M.Fabric, { t = 0.35 }),
	glass = Look.glass(C3(214, 232, 236), 0.62),
	glassFrost = { c = C3(232, 240, 240), m = M.Glass, t = 0.25, r = 0.05 },
	screenOff = Look.screen(),
	wood = Look.oak,
	lightWood = Look.lightOak,
	paper = Look.paper,
	cardboard = Look.cardboard,
}

-- 기본 도구 -----------------------------------------------------------------------------------------------
local function note(K: any, s: string)
	K:note("clinic: " .. s)
end

local function step(K: any, name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		note(K, name .. " error: " .. tostring(err))
	end
end

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

-- 글자판 (K:text) 줄임
local function tx(K: any, name: string, w: number, h: number, dcf: CFrame, s: string, fg: Color3?, bg: Color3?, o: any?): (BasePart, TextLabel)
	local oo: any = o or {}
	return K:text(name, w, h, dcf, s, {
		fg = fg or INK,
		bg = bg,
		font = oo.font or FONT_B,
		d = oo.d or 0.03,
		glow = oo.glow,
		align = oo.align,
		free = oo.free,
		look = oo.look,
		maxDist = oo.maxDist,
		wrap = oo.wrap,
	})
end

-- dcf 를 pcf 처럼: 표면 위 점에서 수평으로 바라보는 방향 n (보는 사람 쪽)
local function faceCF(p: Vector3, n: Vector3): CFrame
	local z = Vector3.new(n.X, 0, n.Z).Unit
	local x = Vector3.yAxis:Cross(z).Unit
	return CFrame.fromMatrix(p, x, Vector3.yAxis, z)
end

-- 바닥 소품 pcf (x, z, 앞 방향 각도: 0 = +Z, PI/2 = +X ...)
local function at(x: number, z: number, yaw: number?): CFrame
	return CF(x, 0, z) * ANG(0, yaw or 0, 0)
end

-- 숨기기 ----------------------------------------------------------------------------------------------------
local function hideRec(K: any, r: any)
	if r and r.part then
		Scan.hide(K.hidden, r.part)
	end
end

local function hideList(K: any, list: { any }?)
	for _, r in list or {} do
		hideRec(K, r)
	end
end

-- 이름 목록의 파트 숨기기 (filter(rec) -> bool 선택)
local function hideNames(K: any, names: { string }, filter: ((any) -> boolean)?)
	local V = K.V
	for _, n in names do
		for _, r in V.byName[n] or {} do
			if not filter or filter(r) then
				hideRec(K, r)
			end
		end
	end
end

-- 부모 모델 이름으로 찾기
local function recsIn(V: any, modelName: string): { any }
	local out = {}
	for _, r in V.parts do
		local p = r.part.Parent
		if p and p.Name == modelName then
			table.insert(out, r)
		end
	end
	return out
end

local function sibling(V: any, r: any, name: string): any?
	local par = r.part.Parent
	for _, q in V.parts do
		if q.name == name and q.part.Parent == par then
			return q
		end
	end
	return nil
end

local function siblings(V: any, r: any): { any }
	local par = r.part.Parent
	local out = {}
	for _, q in V.parts do
		if q.part.Parent == par then
			table.insert(out, q)
		end
	end
	return out
end

local function nearest(V: any, name: string, p: Vector3, maxD: number?): any?
	local best, bd = nil, maxD or math.huge
	for _, r in V.byName[name] or {} do
		local d = (Vector3.new(r.c.X, 0, r.c.Z) - Vector3.new(p.X, 0, p.Z)).Magnitude
		if d < bd then
			best, bd = r, d
		end
	end
	return best
end

-- 벽 자리 기록 (Common.wallSpot 이 피하게)
local function wallUse(K: any, wn: string, a: number, b: number, y0: number, y1: number)
	K.wallUsed = K.wallUsed or {}
	table.insert(K.wallUsed, { w = wn, a = a, b = b, y0 = y0, y1 = y1 })
end

-- 벽면 u 구간이 비었나 (맵 물건 · keep · 이미 쓴 자리)
local function wallFree(K: any, wn: string, u: number, w: number, y0: number, y1: number, depth: number?): boolean
	local V = K.V
	local a, b = u - w / 2, u + w / 2
	local okSpan = false
	for _, s in V:spans(wn, y0, y1, depth or 1.0) do
		if s[1] <= a + 0.01 and s[2] >= b - 0.01 then
			okSpan = true
			break
		end
	end
	if not okSpan then
		return false
	end
	for _, used in K.wallUsed or {} do
		if used.w == wn and used.a < b and used.b > a and used.y0 < y1 and used.y1 > y0 then
			return false
		end
	end
	return true
end

-- 벽 위 자리 찾기: prefer 에 가까운 빈 u (없으면 nil). 찾으면 기록하고 dcf 반환
local function wallSpot(K: any, wn: string, w: number, y0: number, y1: number, prefer: number, depth: number?): CFrame?
	local V = K.V
	local wall = V.walls[wn]
	if not wall then
		return nil
	end
	local best, bd = nil, math.huge
	local stepU = 0.25
	local u = wall.a + w / 2 + 0.3
	while u <= wall.b - w / 2 - 0.3 do
		local d = math.abs(u - prefer)
		if d < bd and wallFree(K, wn, u, w, y0, y1, depth) then
			best, bd = u, d
		end
		u += stepU
	end
	if best then
		wallUse(K, wn, best - w / 2 - 0.15, best + w / 2 + 0.15, y0, y1)
		return V:wall(wn, best, (y0 + y1) / 2, 0)
	end
	return nil
end

-- 벽에 등을 댄 바닥 소품 pcf (+Z = 방 안쪽). 자리가 비었으면 pcf, 아니면 nil
local function wallFloor(K: any, wn: string, u: number, w: number, d: number, h: number, pad: number?, gap: number?): CFrame?
	local V = K.V
	local pcf = V:wall(wn, u, 0, (gap or 0.02) + d / 2)
	pcf = CFrame.fromMatrix(pcf.Position, pcf.XVector, Vector3.yAxis, pcf.ZVector)
	if K:spot(pcf, V3(w, h, d), pad or 0) then
		return pcf
	end
	return nil
end

-- 벽에 등을 댄 바닥 소품: prefer 근처에서 자리 찾기
local function wallFloorNear(K: any, wn: string, prefer: number, w: number, d: number, h: number, range: number?, pad: number?): (CFrame?, number?)
	local r = range or 6
	local best = nil
	for i = 0, math.floor(r / 0.5) do
		for _, sgn in { 1, -1 } do
			local u = prefer + sgn * i * 0.5
			local pcf = wallFloor(K, wn, u, w, d, h, pad)
			if pcf then
				return pcf, u
			end
			if i == 0 then
				break
			end
		end
	end
	return best, nil
end

-- 자유 바닥 소품
local function floorAt(K: any, x: number, z: number, yaw: number, w: number, d: number, h: number, pad: number?): CFrame?
	local pcf = at(x, z, yaw)
	if K:spot(pcf, V3(w, h, d), pad or 0) then
		return pcf
	end
	return nil
end

-- 방 틀 다시 맞추기 ------------------------------------------------------------------------------------------
-- 건물에 맞춘 회전 틀(원점 = rooms.json 방 가운데)에서 잰 실제 벽 안쪽 면 { x0, x1, z0, z1 }
local ROOMFIX: { [string]: { number } } = {
	lobby = { -23.5, 23.87, -13.6, 12.9 },
	waiting = { -13.31, 12.5, -13.48, 13.04 },
	consult = { -22.28, 22.3, -13.87, 14.27 },
	pharmacy = { -29.31, 29.29, -11.88, 11.5 },
	treat = { -23.26, 23.33, -11.64, 11.75 },
	backhall = { -58.8, 59.6, -8.26, 8.32 },
	ward201 = { -22.25, 22.53, -12.66, 12.79 },
	nurse = { -13.94, 14.05, -13.17, 12.27 },
	ward202 = { -22.38, 22.38, -12.98, 12.47 },
	lounge = { -18.92, 19.83, -22.86, 19.9 },
	checkup = { -24.76, 26.01, -21.72, 21.02 },
}
-- 앞(+Z)이 거리 유리창인 방 (window keep 유지)
local FRONT_GLASS = { lobby = true, waiting = true }
-- 뒤(-Z)가 바깥 창인 방 (창 앞 비움)
local BACK_GLASS = { consult = true, ward201 = true, ward202 = true, nurse = true }

-- Law/Hospital NPC 지점 (월드 xz, 서버 SPOTS) 과 지점 사이 통로 (서버 걷기 격자가 고르는 길을 단순화한 꺾은선)
local SPOTS1 = {
	fore = { -496, 252 }, door = { -496, 270 }, lobby = { -505, 276 }, desk_front = { -515, 281 }, desk = { -503, 284 },
	wait1 = { -466, 275 }, wait2 = { -466, 281 }, wait3 = { -466, 287 }, hall = { -505, 300 }, hall2 = { -525, 294 },
	bench = { -520, 328 }, pharm = { -540, 294 }, cons_door = { -537, 297 }, cons = { -545, 285 }, treat_door = { -485, 296 },
	treat = { -478, 308 }, treat_bed = { -468, 309 }, lift1 = { -548, 332 },
}
local SPOTS2 = {
	lift2 = { -548, 332 }, landing = { -540, 294 }, corr2 = { -520, 290 }, station = { -515, 284 }, w201_door = { -497, 293 },
	w201 = { -480, 283 }, w201_bed = { -466, 282 }, w202_door = { -537, 292 }, w202 = { -550, 281 }, w202_bed = { -540, 281 },
	check_door = { -543, 298 }, check = { -552, 312 }, lounge = { -478, 311 },
}
local LANES1 = {
	{ { -496, 252 }, { -496, 270 }, { -505, 276 }, { -515, 281 } },
	{ { -505, 276 }, { -503, 284 } },
	{ { -505, 276 }, { -466, 275 } },
	{ { -505, 276 }, { -466, 281 } },
	{ { -505, 276 }, { -480, 284 }, { -466, 287 } },
	{ { -505, 276 }, { -497, 291 }, { -505, 300 } },
	{ { -505, 300 }, { -525, 294 }, { -540, 294 } },
	{ { -525, 294 }, { -537, 297 }, { -534.9, 292.5 }, { -545, 285 } },
	{ { -505, 300 }, { -485, 296 }, { -487, 298.8 }, { -478, 308 }, { -468, 309 } },
	{ { -505, 300 }, { -510, 323 }, { -520, 328 }, { -548, 332 } },
}
local LANES2 = {
	{ { -548, 332 }, { -552, 312 }, { -543, 298 }, { -538.9, 295 }, { -540, 294 }, { -520, 290 } },
	{ { -548, 332 }, { -543, 298 } },
	{ { -540, 294 }, { -537, 292 }, { -534.75, 289.2 }, { -550, 281 }, { -540, 281 } },
	{ { -520, 290 }, { -497, 293 }, { -494.8, 290.5 }, { -480, 283 }, { -466, 282 } },
	{ { -520, 290 }, { -525.5, 290 }, { -525.5, 284 }, { -515, 284 } },
	{ { -520, 290 }, { -503.5, 290 }, { -503.5, 284 }, { -515, 284 } },
	{ { -497, 293 }, { -478.6, 296 }, { -478, 311 } },
}

-- 건물 회전 (V.cf 기준 Y 각, -45..45 도)
local function buildingAngle(V: any): number
	local angs = {}
	for _, r in V.parts do
		local p: BasePart = r.part
		if p.Size.Magnitude > 8 and math.abs(p.CFrame.UpVector.Y) > 0.999 then
			local xv = V.cf:VectorToObjectSpace(p.CFrame.XVector)
			local a = math.atan2(-xv.Z, xv.X)
			while a > PI / 4 do
				a -= PI / 2
			end
			while a <= -PI / 4 do
				a += PI / 2
			end
			table.insert(angs, a)
		end
	end
	if #angs == 0 then
		return 0
	end
	table.sort(angs)
	return angs[math.floor(#angs / 2) + 1]
end

local function addLaneKeeps(V: any, floorY: number, lanes: { any }, spots: { [string]: { number } }, hw: number, sr: number)
	local function L(p: { number }): Vector3
		local l = V.cf:PointToObjectSpace(Vector3.new(p[1], floorY, p[2]))
		return Vector3.new(l.X, 0, l.Z)
	end
	local function inside(p: Vector3, m: number): boolean
		return p.X > V.x0 - m and p.X < V.x1 + m and p.Z > V.z0 - m and p.Z < V.z1 + m
	end
	for _, line in lanes do
		for i = 1, #line - 1 do
			local a, b = L(line[i]), L(line[i + 1])
			local len = (b - a).Magnitude
			local n = math.max(1, math.ceil(len / 1.0))
			for k = 0, n do
				local p = a:Lerp(b, k / n)
				if inside(p, hw) then
					V:addKeep(Vector3.new(p.X - hw, 0.1, p.Z - hw), Vector3.new(p.X + hw, 6.5, p.Z + hw), "lane")
				end
			end
		end
	end
	for _, s in spots do
		local p = L(s)
		if inside(p, sr) then
			V:keepAround(p, sr, 6.5, "point")
		end
	end
end

-- V 를 건물 틀로 다시 맞춤. 반환 V2 (실패하면 V)
local function refit(V: any): any
	local fix = ROOMFIX[V.room or ""]
	if not fix or not V.model then
		return V
	end
	local a = buildingAngle(V)
	local rf = V.cf * ANG(0, a, 0)
	local x0, x1, z0, z1 = fix[1], fix[2], fix[3], fix[4]
	local cf2 = rf * CF((x0 + x1) / 2, 0, (z0 + z1) / 2)
	local spec = {
		cf = cf2,
		size = V3(x1 - x0, V.H, z1 - z0),
		type = V.type,
		room = V.room,
		kind = "venue",
		name = V.name,
		key = V.key,
		noDoorGuess = true,
		margin = 0.6,
	}
	local ok, V2 = pcall(Scan.fitRoom, V.model, spec)
	if not ok or not V2 then
		return V
	end
	V2.maxParts, V2.maxLights, V2.detail = V.maxParts, V.maxLights, V.detail
	V2.bAngle = a
	V2.orig = V
	local upper = V2.cf.Y > 15 -- 2층
	V2.upper = upper
	-- keep 고치기 (Scan 이 시설 전체 'Staff' 폴더를 NPC 하나로 · 1층 자동문을 2층 방 문으로 · 벽을 유리창으로 봄)
	local keep = {}
	for _, k in V2.keep do
		local sz = k.max - k.min
		if k.kind == "npc" and (sz.X > 10 or sz.Z > 10) then
			continue
		end
		if k.kind == "door" and upper then
			continue
		end
		if k.kind == "window" and not FRONT_GLASS[V.room] then
			continue
		end
		table.insert(keep, k)
	end
	V2.keep = keep
	if upper then
		V2.door, V2.doors = nil, {}
	end
	-- 실제 리그 (HumanoidRootPart) 둘레
	for _, r in V2.byName.HumanoidRootPart or {} do
		V2:keepAround(r.c, 2.0, 6.5, "npc")
	end
	-- 서버 프롬프트 앵커 둘레
	for _, n in { "HospitalPrompt_desk", "HospitalPrompt_doctor" } do
		for _, r in V2.byName[n] or {} do
			V2:keepAround(r.c, 1.4, 6.5, "point")
		end
	end
	if BACK_GLASS[V.room] then
		V2:addKeep(Vector3.new(V2.x0 - 1, 0.1, V2.z0 - 0.5), Vector3.new(V2.x1 + 1, V2.H, V2.z0 + 1.1), "window")
	end
	-- NPC 통로
	local floorY = V2.cf.Y
	if upper then
		addLaneKeeps(V2, floorY, LANES2, SPOTS2, 1.25, 1.7)
	else
		addLaneKeeps(V2, floorY, LANES1, SPOTS1, 1.25, 1.7)
	end
	return V2
end
T._refit = refit

T._debug = {}

return T

end

__defs["T_club"] = function()
-- GwangalliBuildingInterior/T_club: 큰 시설 방 유형 (clublounge rooftop hiphop) 실내 (Venues.luau 의 방, Scan.fitRoom).
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (Common.luau 머리말의 S 필드)
--   build(K, V, S) 유형별 디테일

local Look = __require("Look")
local Props = __require("Props")
local Interact = __require("Interact")
local Common = __require("Common")

local T = {}
T.types = { "clublounge", "rooftop", "hiphop" }

function T.style(V: any): any
	-- 기본: 기존 가구는 그대로, 천장 설비만 (모듈을 채우면서 바꿈)
	return { chair = false, stool = false, table = false, counter = false, base = false, lower = false, mat = false, clock = false, license = false, cctv = false, ceiling = {}, lights = { kind = "none" }, skip = { upgrades = true, fixtures = true } }
end

function T.build(K: any, V: any, S: any) end

return T

end

__defs["T_delivery"] = function()
-- GwangalliBuildingInterior/T_delivery: 큰 시설 방 유형 (delivery warehouse) 실내 (Venues.luau 의 방, Scan.fitRoom).
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (Common.luau 머리말의 S 필드)
--   build(K, V, S) 유형별 디테일

local Look = __require("Look")
local Props = __require("Props")
local Interact = __require("Interact")
local Common = __require("Common")

local T = {}
T.types = { "delivery", "warehouse" }

function T.style(V: any): any
	-- 기본: 기존 가구는 그대로, 천장 설비만 (모듈을 채우면서 바꿈)
	return { chair = false, stool = false, table = false, counter = false, base = false, lower = false, mat = false, clock = false, license = false, cctv = false, ceiling = {}, lights = { kind = "none" }, skip = { upgrades = true, fixtures = true } }
end

function T.build(K: any, V: any, S: any) end

return T

end

__defs["T_facility"] = function()
-- GwangalliBuildingInterior/T_facility: 큰 시설 방 유형 (restroom corridor office elevhall) 실내 (Venues.luau 의 방, Scan.fitRoom).
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (Common.luau 머리말의 S 필드)
--   build(K, V, S) 유형별 디테일

local Look = __require("Look")
local Props = __require("Props")
local Interact = __require("Interact")
local Common = __require("Common")

local T = {}
T.types = { "restroom", "corridor", "office", "elevhall" }

function T.style(V: any): any
	-- 기본: 기존 가구는 그대로, 천장 설비만 (모듈을 채우면서 바꿈)
	return { chair = false, stool = false, table = false, counter = false, base = false, lower = false, mat = false, clock = false, license = false, cctv = false, ceiling = {}, lights = { kind = "none" }, skip = { upgrades = true, fixtures = true } }
end

function T.build(K: any, V: any, S: any) end

return T

end

__defs["T_fastfood"] = function()
-- GwangalliBuildingInterior/T_fastfood: 유형 (chicken burger snack) 실내.
--   치킨집 (치킨호프 · 옛날통닭 · 비비큐 같은 프랜차이즈), 버거 (수제버거 · SUBWAY · 타코), 분식 (분식집 · 떡볶이 · 오뎅바)
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (Common.luau 머리말의 S 필드)
--   build(K, V, S) 유형별 디테일 (메뉴판 · 진열 · 주방 · 간판 · 소품 · 상호작용)
--
-- 배치 원칙
--   * 바닥 소품: floorSpot = 벽을 따라 후보 자리를 훑으며 K:spot (keep · 기존 가구 · 새 소품) + 벽 부착물 · 천장 행거 ·
--     간판 · 우리 금지 구역(주방 패스 앞, 키오스크 앞, 입구 -> 패스/키오스크/화장실 동선, NPC 주변)을 검사.
--   * 벽 장식: Common.wallSpot (빈 벽 구간), 바닥 소품이 쓰는 벽 구간은 K.wallUsed 에 기록해 겹치지 않게.
--   * 맵 게임플레이 파트 (KitchenPass · PassLedge · 카운터 · 좌석 · 분식 조리대 음식): 같은 자리 · 같은 범위 덮개 + 원본 숨김.
--   * Sign_* 파트는 절대 건드리지 않음 (R10) — 주변 액자 · 조명만.
--   * 프롬프트는 Interact.canPrompt 로 먼저 확인한 자리에만 (서버 앵커 6.5 스터드 밖).

local Look = __require("Look")
local Props = __require("Props")
local Interact = __require("Interact")
local Common = __require("Common")
local Scan = __require("Scan")

local TweenService = game:GetService("TweenService")

local T = {}
T.types = { "chicken", "burger", "snack" }

local CF, V3 = CFrame.new, Vector3.new
local ANG = CFrame.Angles
local PI = math.pi
local M = Enum.Material
local F = Enum.Font
local L = Look
local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

-- 작은 도구 ------------------------------------------------------------------------------------------
local function hash(s: string): number
	local h = 7
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 2147483629
	end
	return h
end

local function mkRand(seed: number): (number?, number?) -> number
	local s = seed % 2147483646 + 1
	return function(a: number?, b: number?): number
		s = (s * 16807) % 2147483647
		local f = (s - 1) / 2147483646
		if a == nil then
			return f
		end
		if b == nil then
			return math.floor(f * (a :: number)) + 1
		end
		return (a :: number) + ((b :: number) - (a :: number)) * f
	end
end

local function pl(c: Color3, m: Enum.Material?, extra: any?): any
	local t: any = { c = c, m = m or M.SmoothPlastic }
	if extra then
		for k, v in extra do
			t[k] = v
		end
	end
	return t
end
local function dark(c: Color3, f: number): Color3
	return c:Lerp(BLACK, f)
end
local function light(c: Color3, f: number): Color3
	return c:Lerp(WHITE, f)
end
local function neon(c: Color3): any
	return { c = c, m = M.Neon }
end

local function ov(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3, e: number): boolean
	return a0.X < b1.X - e and a1.X > b0.X + e and a0.Y < b1.Y - e and a1.Y > b0.Y + e and a0.Z < b1.Z - e and a1.Z > b0.Z + e
end

local function laabb(lcf: CFrame, size: Vector3): (Vector3, Vector3)
	local h = size / 2
	local ex = math.abs(lcf.XVector.X) * h.X + math.abs(lcf.YVector.X) * h.Y + math.abs(lcf.ZVector.X) * h.Z
	local ey = math.abs(lcf.XVector.Y) * h.X + math.abs(lcf.YVector.Y) * h.Y + math.abs(lcf.ZVector.Y) * h.Z
	local ez = math.abs(lcf.XVector.Z) * h.X + math.abs(lcf.YVector.Z) * h.Y + math.abs(lcf.ZVector.Z) * h.Z
	local p = lcf.Position
	return V3(p.X - ex, p.Y - ey, p.Z - ez), V3(p.X + ex, p.Y + ey, p.Z + ez)
end

-- 맵 간판 글자 모으기 (메뉴판 가격 · 상호를 우리 포스터에 똑같이 쓰려고). 읽기만.
local function signTexts(V: any): string
	local out = { V.name or "" }
	for _, r in V.parts do
		if string.sub(r.name, 1, 5) == "Sign_" then
			table.insert(out, string.sub(r.name, 6))
			pcall(function()
				for _, d in r.part:GetDescendants() do
					if d:IsA("TextLabel") then
						table.insert(out, (d :: TextLabel).Text)
					end
				end
			end)
		end
	end
	return table.concat(out, " | ")
end

-- "후라이드 20,000 · 양념 21,000" 에서 품목 다음 가격 (가운데 점 · 줄바꿈을 넘지 않음)
local function priceIn(txt: string, item: string, default: string): string
	local init = 1
	for _ = 1, 12 do
		local i, j = string.find(txt, item, init, true)
		if not i or not j then
			return default
		end
		local rest = string.sub(txt, j + 1, j + 30)
		local a, _, num = string.find(rest, "(%d[%d,]*%d)")
		if a then
			local between = string.sub(rest, 1, a - 1)
			if not string.find(between, "·", 1, true) and not string.find(between, "|", 1, true) and not string.find(between, "\n", 1, true) then
				return num
			end
		end
		init = j + 1
	end
	return default
end

local function has(s: string, w: string): boolean
	return string.find(s, w, 1, true) ~= nil
end

-- 세부 유형 -----------------------------------------------------------------------------------------
local function subKind(V: any, signs: string?): string
	local n = (V.name or "") .. " " .. (if V.model then V.model.Name else "")
	local up = string.upper(n)
	local m = V.menu
	local s = signs or ""
	if V.type == "chicken" or m == "chicken" or m == "tongdak" then
		if m == "tongdak" or has(n, "통닭") then
			return "tongdak"
		end
		return "chicken"
	elseif V.type == "burger" then
		if m == "sub" or has(up, "SUBWAY") or has(n, "써브웨이") then
			return "sub"
		end
		if m == "taco" or has(n, "타코") or has(up, "TACO") then
			return "taco"
		end
		-- 맵에서 버거로 분류됐지만 실제 간판 · 메뉴가 치킨인 가게 (예: BBQ 민락점)
		if (has(s, "치킨") or has(s, "후라이드")) and not has(s, "버거") then
			return "chicken"
		end
		return "burger"
	else
		if m == "odeng" or has(n, "오뎅") or has(n, "어묵") then
			return "odeng"
		end
		return "bunsik"
	end
end
T.subKind = subKind

-- 팔레트 ------------------------------------------------------------------------------------------
local CHICKEN_PAL = {
	-- 노랑 · 빨강 (호프형 치킨집)
	{ key = "yellow", wall = rgb(244, 206, 96), wall2 = rgb(250, 240, 222), accent = rgb(204, 34, 30), ink = rgb(40, 28, 20), gold = rgb(255, 196, 40), wood = L.oak, lowerL = L.walnut, floor = rgb(150, 112, 78), floorM = M.WoodPlanks, chair = "padded", seat = L.leatherBrown, table = L.oak },
	-- 화이트 · 레드 (깔끔한 프랜차이즈)
	{ key = "red", wall = rgb(238, 234, 228), wall2 = rgb(200, 30, 38), accent = rgb(200, 30, 38), ink = rgb(30, 30, 30), gold = rgb(255, 210, 60), wood = L.lightOak, lowerL = L.white, floor = rgb(196, 194, 190), floorM = M.CeramicTiles, chair = "shell", seat = L.plywood, table = L.lightOak },
	-- 블랙 · 골드 (프리미엄 치킨 & 펍)
	{ key = "black", wall = rgb(46, 44, 42), wall2 = rgb(64, 60, 56), accent = rgb(212, 168, 74), ink = rgb(246, 236, 210), gold = rgb(228, 186, 90), wood = L.walnut, lowerL = L.darkWood, floor = rgb(84, 80, 76), floorM = M.Slate, chair = "padded", seat = L.leatherBlack, table = L.walnut },
}
local TONGDAK_PAL = { key = "tongdak", wall = rgb(246, 226, 168), wall2 = rgb(252, 244, 226), accent = rgb(196, 40, 30), ink = rgb(70, 40, 20), gold = rgb(250, 190, 40), wood = L.pine, lowerL = L.pine, floor = rgb(160, 120, 84), floorM = M.WoodPlanks, chair = "bentwood", seat = L.walnut, table = L.pine }

local BURGER_PAL = {
	-- 아메리칸 다이너 (빨강 · 크림 · 체커)
	{ key = "diner", wall = rgb(166, 30, 34), wall2 = rgb(246, 240, 226), accent = rgb(220, 36, 40), ink = rgb(24, 24, 26), gold = rgb(255, 196, 48), checker = true, tile = rgb(246, 246, 242), neonC = rgb(255, 70, 90), chair = "diner", seat = L.leatherRed, table = L.marbleWhite },
	-- 인더스트리얼 (블랙 · 콘크리트 · 오렌지)
	{ key = "industrial", wall = rgb(58, 58, 60), wall2 = rgb(150, 148, 144), accent = rgb(244, 120, 32), ink = rgb(240, 236, 228), gold = rgb(255, 170, 40), checker = false, tile = rgb(238, 238, 234), neonC = rgb(255, 150, 50), chair = "shell", seat = L.plywood, table = L.walnut },
	-- 브루클린 (벽돌 · 블랙 · 머스터드)
	{ key = "brick", wall = rgb(150, 82, 62), wall2 = rgb(36, 36, 38), accent = rgb(236, 176, 40), ink = rgb(250, 244, 230), gold = rgb(236, 176, 40), checker = false, brick = true, tile = rgb(30, 30, 32), neonC = rgb(255, 200, 70), chair = "padded", seat = L.leatherBlack, table = L.oak },
}
local SUB_PAL = { key = "sub", wall = rgb(0, 132, 61), wall2 = rgb(244, 240, 230), accent = rgb(255, 194, 14), ink = rgb(255, 255, 255), gold = rgb(255, 194, 14), green = rgb(0, 132, 61), chair = "shell", seat = L.lightOak, table = L.lightOak }
local TACO_PAL = { key = "taco", wall = rgb(236, 110, 60), wall2 = rgb(250, 226, 160), accent = rgb(30, 140, 120), ink = rgb(40, 24, 20), gold = rgb(255, 200, 60), checker = false, tile = rgb(230, 120, 70), neonC = rgb(80, 230, 200), chair = "shell", seat = L.plywood, table = L.pine }

local SNACK_PAL = {
	-- 빨강 · 노랑 분식 (떡볶이집)
	{ key = "red", wall = rgb(250, 238, 214), wall2 = rgb(210, 40, 36), accent = rgb(214, 38, 34), ink = rgb(30, 26, 24), gold = rgb(255, 200, 40), tile = rgb(240, 240, 236), tileAcc = rgb(206, 44, 40), chair = "cushion", seat = L.leatherRed, table = L.of(232, 230, 222) },
	-- 민트 · 화이트 (요즘 분식 프랜차이즈)
	{ key = "mint", wall = rgb(236, 246, 240), wall2 = rgb(40, 160, 130), accent = rgb(236, 90, 40), ink = rgb(24, 40, 36), gold = rgb(255, 196, 60), tile = rgb(244, 244, 240), tileAcc = rgb(60, 170, 140), chair = "cushion", seat = L.of(60, 150, 124, M.Leather), table = L.of(244, 242, 236) },
}
local ODENG_PAL = { key = "odeng", wall = rgb(120, 70, 40), wall2 = rgb(40, 30, 26), accent = rgb(196, 40, 36), ink = rgb(250, 238, 214), gold = rgb(236, 196, 120), wood = L.of(150, 106, 66, M.Wood) }

-- style ----------------------------------------------------------------------------------------------
function T.style(V: any): any
	local signs = signTexts(V)
	local sk = subKind(V, signs)
	local seed = hash(V.key or V.name or "x")
	local gw = V.kind == "gwshop"
	local S: any
	if sk == "chicken" or sk == "tongdak" then
		local P = if sk == "tongdak" then TONGDAK_PAL else CHICKEN_PAL[seed % #CHICKEN_PAL + 1]
		if has(signs, "비비큐") or has(string.upper(V.name or ""), "BBQ") then
			P = CHICKEN_PAL[2]
		end
		S = {
			chair = { style = P.chair, frame = if P.chair == "bentwood" then L.walnut else L.blackMetal, seat = P.seat, back = P.seat },
			stool = { style = "cushion", seat = L.leatherRed },
			table = { top = P.table, base = L.blackMetal, thick = 0.16 },
			counter = { front = "wood", frontL = P.wood, topL = L.of(60, 58, 56, M.Granite), led = rgb(255, 200, 140) },
			ceiling = { grid = false, skin = if P.key == "black" then L.of(40, 40, 42) else L.of(244, 240, 232, M.Plaster) },
			lower = { kind = if P.key == "red" then "tile" else "louver", h = 3.3, look = if P.key == "red" then L.tileWhite else P.lowerL, back = L.charcoal, walls = { "left", "right" }, tw = 0.8, th = 0.4 },
			floor = { look = L.of(P.floor.R * 255, P.floor.G * 255, P.floor.B * 255, P.floorM), tile = if P.floorM == M.WoodPlanks then 0 else 2.0, grout = L.of(120, 116, 110) },
			base = L.walnut,
			pendant = { shade = "dome", look = L.with(L.blackMetal, { c = dark(P.accent, 0.2) }) },
			lights = { kind = "downlight", n = 4, color = L.warmLight },
			mat = { look = L.of(60, 40, 30, M.Fabric), text = "어서 오세요" },
			plants = { "snake", "olive" },
		}
		S.pal = P
	elseif sk == "sub" then
		local P = SUB_PAL
		S = {
			chair = { style = "shell", frame = L.blackMetal, seat = L.of(0, 120, 56, M.Plastic), back = L.of(0, 120, 56, M.Plastic) },
			stool = { style = "bar", frame = L.blackMetal, seat = L.of(0, 110, 52, M.Leather) },
			table = { top = L.lightOak, base = L.blackMetal, barStyle = "steel" },
			counter = { front = "wood", frontL = L.lightOak, topL = L.of(70, 72, 74, M.Granite), led = rgb(255, 230, 170) },
			ceiling = { grid = true, tile = 2.0 },
			lower = { kind = "louver", h = 3.4, look = L.lightOak, back = L.of(0, 110, 52), walls = { "left", "right" }, pitch = 0.5 },
			floor = { look = L.of(196, 192, 184, M.CeramicTiles), tile = 2.0, grout = L.of(150, 146, 140) },
			base = L.of(0, 100, 50),
			lights = { kind = "panel", n = 4 },
			mat = { look = L.of(0, 96, 46, M.Fabric), text = "SUBWAY" },
			plants = { "snake", "olive" },
		}
		S.pal = P
	elseif sk == "burger" or sk == "taco" then
		local P = if sk == "taco" then TACO_PAL else BURGER_PAL[seed % #BURGER_PAL + 1]
		S = {
			chair = { style = P.chair, frame = if P.chair == "diner" then L.chrome else L.blackMetal, seat = P.seat, back = P.seat },
			stool = { style = "bar", frame = L.chrome, seat = P.seat },
			table = { top = P.table, base = if P.chair == "diner" then L.chrome else L.blackMetal, edge = if P.chair == "diner" then L.chrome else nil },
			counter = { front = "tile", frontL = L.tileWhite, topL = L.of(36, 36, 38, M.Granite), led = rgb(255, 210, 160) },
			ceiling = { grid = false, skin = if P.key == "diner" then L.of(244, 240, 230, M.Plaster) else L.of(34, 34, 36, M.Concrete) },
			lower = { kind = "tile", h = 3.6, look = L.of(P.tile.R * 255, P.tile.G * 255, P.tile.B * 255, M.CeramicTiles), grout = L.of(170, 168, 162), walls = { "left", "right", "back" }, tw = 0.66, th = 0.33 },
			floor = if P.checker then false else { look = L.of(120, 118, 114, M.Slate), tile = 2.4, grout = L.of(90, 88, 86) },
			base = L.black,
			pendant = { shade = "bulb" },
			lights = { kind = "downlight", n = 4, color = L.warmLight },
			mat = { look = L.of(30, 30, 30, M.Fabric), text = "WELCOME" },
			plants = { "snake", "bamboo" },
		}
		S.pal = P
	elseif sk == "odeng" then
		local P = ODENG_PAL
		S = {
			chair = false, -- 벤치 · 의자는 아래에서 직접 (벤치형 Seat 를 의자로 덮지 않게)
			stool = { style = "wood", frame = L.walnut, seat = L.walnut },
			table = { top = L.of(150, 106, 66, M.Wood), base = L.blackMetal },
			counter = { front = "wood", frontL = L.of(120, 80, 50, M.Wood), topL = L.of(176, 132, 88, M.Wood), kickL = L.black, led = rgb(255, 190, 120) },
			ceiling = { grid = false, skin = L.of(44, 34, 28, M.Wood) },
			lower = { kind = "louver", h = 3.4, look = L.of(110, 74, 48, M.Wood), back = L.of(40, 30, 26), walls = { "left", "right" }, pitch = 0.42 },
			floor = false,
			base = L.darkWood,
			pendant = { shade = "drum", look = L.of(236, 226, 200, M.Fabric) },
			lights = { kind = "none" },
			mat = { look = L.of(40, 30, 24, M.Fabric), text = "어서 오세요" },
			plants = { "bamboo", "snake" },
		}
		S.pal = P
	else
		local P = if gw then SNACK_PAL[1] else SNACK_PAL[seed % #SNACK_PAL + 1]
		S = {
			chair = { style = "padded", frame = L.chrome, seat = P.seat, back = P.seat },
			stool = { style = "cushion", frame = L.chrome, seat = P.seat },
			table = { top = P.table, base = L.chrome, edge = L.steel, thick = 0.12 },
			counter = { front = "tile", frontL = L.of(P.tileAcc.R * 255, P.tileAcc.G * 255, P.tileAcc.B * 255, M.CeramicTiles), topL = L.steel, led = false },
			ceiling = { grid = true, tile = 2.0 },
			lower = { kind = "tile", h = 3.6, look = L.of(P.tile.R * 255, P.tile.G * 255, P.tile.B * 255, M.CeramicTiles), grout = L.of(188, 186, 180), walls = { "left", "right", "back" }, tw = 0.6, th = 0.6 },
			floor = { look = L.of(170, 166, 158, M.Granite), tile = 2.0, grout = L.of(130, 126, 120) },
			base = L.of(P.tileAcc.R * 255, P.tileAcc.G * 255, P.tileAcc.B * 255),
			lights = { kind = "panel", n = 4 },
			mat = { look = L.of(150, 30, 30, M.Fabric), text = "어서 오세요" },
			plants = { "snake" },
		}
		S.pal = P
	end
	if gw then
		-- GwShop 은 맵이 이미 마감한 곳 위주: 벽 아랫단 · 천장 그리드 · 현관 매트는 맵 것 그대로
		S.lower = false
		if V:has("TBar") > 0 then
			S.ceiling = { grid = true }
		end
		if V:has("DoorMat") > 0 then
			S.mat = false
		end
	end
	S.sk = sk
	S.signs = signs
	return S
end

-- 빌드 문맥 ----------------------------------------------------------------------------------------
local function ctxNew(K: any, V: any, S: any): any
	local signs = S.signs or signTexts(V)
	local ctx: any = {
		K = K,
		V = V,
		S = S,
		sk = S.sk or subKind(V, signs),
		pal = S.pal or CHICKEN_PAL[1],
		signs = signs,
		rand = mkRand(hash(V.key or V.name or "x")),
		no = {},
		wallSigns = {},
		low = K.detail == "low",
		high = K.detail == "high",
		gw = V.kind == "gwshop",
		stats = {},
		toggles = 0,
	}
	for _, r in V.parts do
		if string.sub(r.name, 1, 5) == "Sign_" and r.size.Y < 6 then
			table.insert(ctx.wallSigns, r)
		end
	end
	return ctx
end

local function addNo(ctx: any, mn: Vector3, mx: Vector3)
	table.insert(ctx.no, { min = mn, max = mx })
end

-- a -> b (바닥 xz) 폭 w 동선을 금지 구역으로
local function corridor(ctx: any, a: Vector3, b: Vector3, w: number)
	local d = V3(b.X - a.X, 0, b.Z - a.Z)
	local len = d.Magnitude
	local n = math.max(1, math.ceil(len / 1.2))
	for i = 0, n do
		local p = a:Lerp(b, i / n)
		addNo(ctx, V3(p.X - w / 2, 0.05, p.Z - w / 2), V3(p.X + w / 2, 7, p.Z + w / 2))
	end
end

local function wallBusy(K: any, wn: string, a: number, b: number, y0: number, y1: number): boolean
	for _, u in K.wallUsed or {} do
		if u.w == wn and u.a < b and u.b > a and u.y0 < y1 and u.y1 > y0 then
			return true
		end
	end
	return false
end

local function markWall(K: any, wn: string, a: number, b: number, y0: number, y1: number)
	K.wallUsed = K.wallUsed or {}
	table.insert(K.wallUsed, { w = wn, a = a, b = b, y0 = y0, y1 = y1 })
end

local function blockedBy(ctx: any, mn: Vector3, mx: Vector3): boolean
	for _, z in ctx.no do
		if ov(mn, mx, z.min, z.max, 0.02) then
			return true
		end
	end
	local V = ctx.V
	for _, list in { V.wallItems, V.hang, ctx.wallSigns } do
		for _, r in list do
			if ov(mn, mx, r.min, r.max, 0.02) then
				return true
			end
		end
	end
	return false
end

-- 옆벽의 뒤쪽 / 앞쪽 끝 u
local function uEnd(V: any, wn: string, which: string): number
	local wl = V.walls[wn]
	if wn == "left" then
		return if which == "back" then wl.b else wl.a
	elseif wn == "right" then
		return if which == "back" then wl.a else wl.b
	elseif wn == "back" then
		return if which == "left" then wl.a else wl.b
	end
	return 0
end

-- 벽에 붙여 세우는 바닥 소품 자리. o = { walls, w, h, d, pref = { [wall] = u | "back" | "front" | "left" | "right" | "mid" },
--   front (앞 여유, 기본 0.9), prompt (true = 프롬프트 가능한 자리 먼저), kind, step }
-- 반환 pcf (+Z = 방 쪽 = 소품 정면), wall, u
local function floorSpot(ctx: any, o: any): (CFrame?, string?, number?)
	local K, V = ctx.K, ctx.V
	local w, h, d = o.w, o.h, o.d
	local gap = o.gap or 0.06
	local front = o.front or 0.9
	local cands = {}
	for wi, wn in o.walls do
		local wl = V.walls[wn]
		if wl then
			local pref = o.pref and o.pref[wn]
			local target: number
			if type(pref) == "number" then
				target = pref
			elseif pref == "back" or pref == "front" or pref == "left" or pref == "right" then
				target = uEnd(V, wn, pref)
			else
				target = (wl.a + wl.b) / 2
			end
			local lo, hi = wl.a + w / 2 + 0.1, wl.b - w / 2 - 0.1
			local step = o.step or 0.4
			local u = lo
			while u <= hi + 1e-6 do
				table.insert(cands, { wn = wn, u = u, s = wi * 1000 + math.abs(u - target) })
				u += step
			end
		end
	end
	table.sort(cands, function(a, b)
		return a.s < b.s
	end)
	for pass = 1, (if o.prompt then 2 else 1) do
		for _, c in cands do
			local pcf = V:wall(c.wn, c.u, 0, d / 2 + gap)
			local mn, mx = laabb(pcf * CF(0, h / 2, 0), V3(w, h, d))
			if wallBusy(K, c.wn, c.u - w / 2 - 0.05, c.u + w / 2 + 0.05, 0, h) or blockedBy(ctx, mn, mx) then
				continue
			end
			if pass == 1 and o.prompt then
				local any = false
				for _, px in { -w / 2 + 0.4, 0, w / 2 - 0.4 } do
					if Interact.canPrompt(K, (pcf * CF(px, 3, d / 2 + 0.2)).Position) then
						any = true
						break
					end
				end
				if not any then
					continue
				end
			end
			-- 앞 여유까지 포함해 예약 (소품 앞에 다른 소품이 막지 않게)
			if K:spot(pcf * CF(0, 0, front / 2), V3(w, h, d + front), 0, o.kind or "ff") then
				markWall(K, c.wn, c.u - w / 2, c.u + w / 2, 0, h + (o.above or 0))
				return pcf, c.wn, c.u
			end
		end
	end
	ctx.miss = (ctx.miss or "") .. string.format(" F%.1fx%.1f", w, d)
	return nil, nil, nil
end

-- 벽 빈 구간 (V:spans 와 같은 계산이지만 벽 마감재 — 벽돌 · 타일 · 걸레받이 — 는 장애물로 보지 않음)
local FINISH = { BrickWall = true, WallTiles = true, TileStripe = true, WainscotCap = true, Skirting = true, Baseboard = true, WallPanel = true, AccentWall = true }
local function spans(ctx: any, name: string, y0: number, y1: number, depth: number?): { { number } }
	local V = ctx.V
	local w = V.walls[name]
	if not w then
		return {}
	end
	local dep = depth or 1.0
	local cuts: { { number } } = {}
	local function cutBox(mn: Vector3, mx: Vector3, pad: number)
		if mx.Y < y0 or mn.Y > y1 then
			return
		end
		local umin, umax, dmin, dmax = math.huge, -math.huge, math.huge, -math.huge
		for _, x in { mn.X, mx.X } do
			for _, z in { mn.Z, mx.Z } do
				local u, d = V:wallCoord(name, V3(x, 0, z))
				umin = math.min(umin, u)
				umax = math.max(umax, u)
				dmin = math.min(dmin, d)
				dmax = math.max(dmax, d)
			end
		end
		if dmin > dep or dmax < 0.02 then
			return -- 벽에서 먼 것 · 벽 뒤(옆 가게 · 주방)에 있는 것은 상관없음
		end
		table.insert(cuts, { umin - pad, umax + pad })
	end
	for _, r in V.parts do
		if (not r.shell or r.door) and not FINISH[r.name] then
			cutBox(r.min, r.max, 0.25)
		elseif string.sub(r.name, 1, 5) == "Sign_" and r.size.Y < 6 then
			cutBox(r.min, r.max, 0.2)
		end
	end
	for _, k in V.keep do
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

-- 벽 장식 자리: 빈 구간에서 K.wallUsed (Common · 우리 기록) 를 정확히 빼고 prefer 에 가장 가까운 곳.
-- (Common.wallSpot 은 한 구간이 둘로 갈릴 때 앞 조각을 뒤 기록과 다시 비교하지 않아 겹칠 수 있어 따로 둠)
local function wallSpot(ctx: any, walls: { string }, w: number, y0: number, y1: number, prefer: number?): (CFrame?, string?)
	local K, V = ctx.K, ctx.V
	K.wallUsed = K.wallUsed or {}
	for _, wn in walls do
		local free = {}
		for _, s in spans(ctx, wn, y0, y1, 1.0) do
			table.insert(free, { s[1], s[2] })
		end
		for _, u in K.wallUsed do
			if u.w == wn and u.y1 > y0 and u.y0 < y1 then
				local nxt = {}
				for _, f in free do
					if u.b <= f[1] or u.a >= f[2] then
						table.insert(nxt, f)
					else
						if u.a > f[1] then
							table.insert(nxt, { f[1], u.a })
						end
						if u.b < f[2] then
							table.insert(nxt, { u.b, f[2] })
						end
					end
				end
				free = nxt
			end
		end
		local best, bd = nil, math.huge
		local target = prefer or 0
		for _, f in free do
			if f[2] - f[1] >= w then
				local u = math.clamp(target, f[1] + w / 2, f[2] - w / 2)
				local dd = math.abs(u - target)
				if dd < bd then
					best, bd = u, dd
				end
			end
		end
		if best then
			table.insert(K.wallUsed, { w = wn, a = best - w / 2 - 0.2, b = best + w / 2 + 0.2, y0 = y0, y1 = y1 })
			return V:wall(wn, best, (y0 + y1) / 2, 0.0), wn
		end
	end
	ctx.miss = (ctx.miss or "") .. string.format(" w%.1f@%.1f-%.1f", w, y0, y1)
	return nil, nil
end

-- 프롬프트를 둘 수 있는 벽 구간 (서버 앵커 6.5 밖): { { wall, a, b } } 긴 것부터
local function promptIntervals(ctx: any, walls: { string }): { any }
	local K, V = ctx.K, ctx.V
	local out = {}
	for _, wn in walls do
		local wl = V.walls[wn]
		if not wl then
			continue
		end
		local run0: number? = nil
		local u = wl.a + 0.3
		while u <= wl.b - 0.3 + 1e-6 do
			local p = V:wall(wn, u, 3, 0.4).Position
			local okp = Interact.canPrompt(K, p)
			if okp and not run0 then
				run0 = u
			elseif not okp and run0 then
				table.insert(out, { wn, run0, u - 0.25 })
				run0 = nil
			end
			u += 0.25
		end
		if run0 then
			table.insert(out, { wn, run0, wl.b - 0.3 })
		end
	end
	table.sort(out, function(a, b)
		return (a[3] - a[2]) > (b[3] - b[2])
	end)
	return out
end

-- 프롬프트 되는 벽 자리 먼저 (없으면 nil): 반환 dcf, wall
local function promptWallSpot(ctx: any, walls: { string }, w: number, y0: number, y1: number): (CFrame?, string?)
	local K = ctx.K
	for _, iv in promptIntervals(ctx, walls) do
		local mid = (iv[2] + iv[3]) / 2
		local dcf, wn = wallSpot(ctx, { iv[1] }, w, y0, y1, mid)
		if dcf then
			if Interact.canPrompt(K, dcf.Position) then
				return dcf, wn
			end
			-- 프롬프트는 안 되지만 자리는 이미 잡았으니 그대로 씀
			return dcf, wn
		end
	end
	return nil, nil
end

-- 폭 후보를 차례로 (큰 것부터): 반환 dcf, 고른 폭
local function wallSpotFit(ctx: any, walls: { string }, ws: { number }, y0: number, y1: number, prefer: number?): (CFrame?, number)
	for _, w in ws do
		local d = wallSpot(ctx, walls, w, y0, y1, prefer)
		if d then
			return d, w
		end
	end
	return nil, 0
end

-- 2D 그림 (포스터 · 라이트박스 위 색 블록): items = { { "e"|"b", x, y, w, h, Color3, rot?, mat? } } (dcf 기준 스터드)
local function art(K: any, dcf: CFrame, items: { any }, z0: number?)
	local z = z0 or 0.004
	for i, it in items do
		local cf = dcf * CF(it[2], it[3], z + i * 0.004) * ANG(0, 0, it[7] or 0)
		local look = { c = it[6], m = it[8] or M.SmoothPlastic }
		if it[1] == "e" then
			K:ell("FfArt", V3(it[4], it[5], 0.012), cf * CF(0, 0, 0.006), look)
		else
			K:box("FfArt", V3(it[4], it[5], 0.012), cf * CF(0, 0, 0.006), look)
		end
	end
	return z + (#items + 1) * 0.004
end

-- 음식 그림 (중심 x, y, 크기 s) ---------------------------------------------------------------------
local function artChicken(x: number, y: number, s: number): { any }
	local g1, g2, g3 = rgb(200, 122, 44), rgb(176, 98, 32), rgb(222, 150, 66)
	return {
		{ "e", x - 0.05 * s, y - 0.32 * s, 1.5 * s, 0.32 * s, rgb(236, 236, 230) }, -- 접시 (바구니 종이)
		{ "e", x - 0.42 * s, y - 0.05 * s, 0.62 * s, 0.46 * s, g2, 0.3 },
		{ "e", x + 0.1 * s, y + 0.08 * s, 0.7 * s, 0.52 * s, g1, -0.2 },
		{ "e", x + 0.46 * s, y - 0.1 * s, 0.56 * s, 0.42 * s, g3, 0.4 },
		{ "e", x - 0.1 * s, y - 0.18 * s, 0.6 * s, 0.36 * s, g1, 0.1 },
		{ "e", x - 0.62 * s, y + 0.18 * s, 0.2 * s, 0.14 * s, rgb(240, 230, 210), 0.5 }, -- 닭다리 뼈
		{ "e", x + 0.18 * s, y + 0.2 * s, 0.14 * s, 0.08 * s, dark(g1, 0.3), 0.3 },
		{ "e", x - 0.25 * s, y + 0.02 * s, 0.12 * s, 0.07 * s, dark(g2, 0.25), -0.4 },
		{ "e", x + 0.42 * s, y - 0.02 * s, 0.1 * s, 0.06 * s, light(g3, 0.3), 0.2 },
	}
end

local function artYangnyeom(x: number, y: number, s: number): { any }
	local r1, r2 = rgb(170, 40, 24), rgb(196, 62, 30)
	return {
		{ "e", x, y - 0.3 * s, 1.5 * s, 0.32 * s, rgb(240, 236, 228) },
		{ "e", x - 0.35 * s, y - 0.02 * s, 0.6 * s, 0.46 * s, r1, 0.3 },
		{ "e", x + 0.15 * s, y + 0.08 * s, 0.66 * s, 0.5 * s, r2, -0.2 },
		{ "e", x + 0.45 * s, y - 0.12 * s, 0.5 * s, 0.4 * s, r1, 0.5 },
		{ "e", x - 0.05 * s, y + 0.18 * s, 0.07 * s, 0.05 * s, rgb(250, 246, 230) }, -- 깨
		{ "e", x + 0.25 * s, y + 0.05 * s, 0.07 * s, 0.05 * s, rgb(250, 246, 230) },
		{ "e", x - 0.3 * s, y + 0.1 * s, 0.07 * s, 0.05 * s, rgb(250, 246, 230) },
		{ "e", x + 0.1 * s, y + 0.22 * s, 0.16 * s, 0.06 * s, light(r2, 0.4), 0.2 }, -- 윤기
	}
end

local function artBeer(x: number, y: number, s: number): { any }
	return {
		{ "b", x + 0.33 * s, y - 0.02 * s, 0.14 * s, 0.6 * s, rgb(220, 226, 228) }, -- 손잡이
		{ "b", x, y - 0.08 * s, 0.56 * s, 0.86 * s, rgb(236, 168, 30) },
		{ "b", x - 0.14 * s, y - 0.08 * s, 0.07 * s, 0.7 * s, rgb(252, 214, 110) }, -- 빛
		{ "e", x, y + 0.38 * s, 0.66 * s, 0.3 * s, rgb(252, 250, 244) }, -- 거품
		{ "e", x + 0.16 * s, y + 0.44 * s, 0.32 * s, 0.22 * s, rgb(252, 250, 244) },
		{ "e", x + 0.1 * s, y - 0.25 * s, 0.05 * s, 0.05 * s, rgb(255, 236, 170) },
		{ "e", x - 0.05 * s, y + 0.05 * s, 0.04 * s, 0.04 * s, rgb(255, 236, 170) },
	}
end

local function artBurger(x: number, y: number, s: number): { any }
	return {
		{ "e", x, y + 0.2 * s, 1.0 * s, 0.56 * s, rgb(214, 140, 60) }, -- 윗빵
		{ "e", x - 0.18 * s, y + 0.36 * s, 0.06 * s, 0.035 * s, rgb(250, 240, 210) },
		{ "e", x + 0.12 * s, y + 0.4 * s, 0.06 * s, 0.035 * s, rgb(250, 240, 210) },
		{ "e", x + 0.3 * s, y + 0.3 * s, 0.06 * s, 0.035 * s, rgb(250, 240, 210) },
		{ "e", x - 0.02 * s, y - 0.02 * s, 1.1 * s, 0.14 * s, rgb(90, 170, 60) }, -- 양상추
		{ "b", x, y - 0.08 * s, 0.96 * s, 0.07 * s, rgb(210, 50, 40) }, -- 토마토
		{ "b", x + 0.02 * s, y - 0.14 * s, 1.0 * s, 0.07 * s, rgb(250, 196, 40), 0.04 }, -- 치즈
		{ "e", x, y - 0.24 * s, 1.04 * s, 0.2 * s, rgb(92, 52, 30) }, -- 패티
		{ "e", x, y - 0.4 * s, 0.98 * s, 0.2 * s, rgb(206, 132, 56) }, -- 아랫빵
	}
end

local function artFries(x: number, y: number, s: number): { any }
	local out = {}
	for i = -3, 3 do
		table.insert(out, { "b", x + i * 0.07 * s, y + 0.12 * s + math.abs(i) * -0.02 * s, 0.06 * s, 0.6 * s, rgb(250, 204, 70), i * 0.06 })
	end
	table.insert(out, { "b", x, y - 0.16 * s, 0.56 * s, 0.5 * s, rgb(210, 30, 36) })
	table.insert(out, { "b", x, y - 0.1 * s, 0.3 * s, 0.12 * s, rgb(255, 210, 60) })
	return out
end

local function artCola(x: number, y: number, s: number): { any }
	return {
		{ "b", x + 0.06 * s, y + 0.52 * s, 0.04 * s, 0.34 * s, rgb(240, 240, 240), -0.2 },
		{ "b", x, y + 0.32 * s, 0.5 * s, 0.07 * s, rgb(240, 240, 240) },
		{ "b", x, y, 0.44 * s, 0.6 * s, rgb(200, 28, 36) },
		{ "b", x, y + 0.02 * s, 0.44 * s, 0.1 * s, rgb(250, 250, 250) },
	}
end

local function artTteok(x: number, y: number, s: number): { any }
	local out = {
		{ "e", x, y - 0.06 * s, 1.5 * s, 0.6 * s, rgb(248, 246, 240) },
		{ "e", x, y - 0.03 * s, 1.26 * s, 0.46 * s, rgb(206, 52, 28) },
	}
	for i = 0, 6 do
		local a = i * 0.9
		table.insert(out, { "b", x + math.cos(a) * 0.36 * s, y + math.sin(a) * 0.1 * s, 0.32 * s, 0.09 * s, rgb(236, 120, 96), a * 0.3 })
	end
	table.insert(out, { "e", x + 0.32 * s, y + 0.06 * s, 0.24 * s, 0.18 * s, rgb(250, 246, 236) }) -- 삶은 달걀
	table.insert(out, { "e", x + 0.32 * s, y + 0.06 * s, 0.1 * s, 0.08 * s, rgb(250, 200, 60) })
	table.insert(out, { "b", x - 0.3 * s, y + 0.08 * s, 0.3 * s, 0.14 * s, rgb(214, 150, 96), 0.4 }) -- 어묵
	table.insert(out, { "b", x - 0.05 * s, y + 0.14 * s, 0.14 * s, 0.03 * s, rgb(80, 160, 60), 0.6 }) -- 파
	return out
end

local function artGimbap(x: number, y: number, s: number): { any }
	local out = {}
	for i = 0, 2 do
		local cx = x + (i - 1) * 0.42 * s
		table.insert(out, { "e", cx, y, 0.4 * s, 0.4 * s, rgb(28, 32, 26) })
		table.insert(out, { "e", cx, y, 0.34 * s, 0.34 * s, rgb(248, 246, 238) })
		table.insert(out, { "b", cx - 0.06 * s, y + 0.04 * s, 0.06 * s, 0.06 * s, rgb(250, 210, 40) })
		table.insert(out, { "b", cx + 0.05 * s, y + 0.04 * s, 0.06 * s, 0.06 * s, rgb(240, 120, 40) })
		table.insert(out, { "b", cx, y - 0.05 * s, 0.07 * s, 0.05 * s, rgb(60, 140, 50) })
	end
	return out
end

local function artSandwich(x: number, y: number, s: number): { any }
	return {
		{ "e", x, y - 0.14 * s, 1.6 * s, 0.3 * s, rgb(214, 160, 92) },
		{ "e", x - 0.02 * s, y - 0.02 * s, 1.56 * s, 0.14 * s, rgb(240, 150, 150) }, -- 햄
		{ "b", x, y + 0.04 * s, 1.44 * s, 0.07 * s, rgb(250, 210, 60), 0.02 }, -- 치즈
		{ "e", x, y + 0.1 * s, 1.5 * s, 0.12 * s, rgb(100, 180, 60) }, -- 양상추
		{ "e", x - 0.4 * s, y + 0.14 * s, 0.26 * s, 0.1 * s, rgb(210, 50, 40) }, -- 토마토
		{ "e", x + 0.2 * s, y + 0.15 * s, 0.26 * s, 0.1 * s, rgb(210, 50, 40) },
		{ "e", x + 0.5 * s, y + 0.13 * s, 0.2 * s, 0.08 * s, rgb(60, 130, 50) }, -- 오이
		{ "e", x, y + 0.28 * s, 1.58 * s, 0.32 * s, rgb(222, 168, 98) }, -- 윗빵
		{ "e", x - 0.2 * s, y + 0.36 * s, 0.6 * s, 0.06 * s, rgb(236, 196, 130) },
	}
end

local function artTaco(x: number, y: number, s: number): { any }
	return {
		{ "e", x, y - 0.05 * s, 1.2 * s, 0.7 * s, rgb(236, 190, 90) },
		{ "e", x, y + 0.12 * s, 1.0 * s, 0.3 * s, rgb(110, 60, 36) },
		{ "e", x - 0.2 * s, y + 0.2 * s, 0.4 * s, 0.14 * s, rgb(90, 170, 60) },
		{ "e", x + 0.2 * s, y + 0.22 * s, 0.3 * s, 0.12 * s, rgb(210, 50, 40) },
		{ "e", x + 0.05 * s, y + 0.26 * s, 0.3 * s, 0.08 * s, rgb(250, 230, 160) },
	}
end

-- 포스터 · 액자 -----------------------------------------------------------------------------------
-- o = { bg, frame (look | false), art (items), texts = { { s, x, y, w, h, fg, font, align?, glow? } }, glass, lit (bg 가 빛나는 라이트박스), depth }
local function poster(ctx: any, dcf: CFrame, w: number, h: number, o: any)
	local K = ctx.K
	local fr = o.frame
	local b = o.border or 0.08
	local dep = o.depth or 0.08
	if fr ~= false then
		local fl = fr or L.blackMetal
		K:plate("FfFrame", w, b, dep, dcf * CF(0, h / 2 - b / 2, 0), fl)
		K:plate("FfFrame", w, b, dep, dcf * CF(0, -h / 2 + b / 2, 0), fl)
		K:plate("FfFrame", b, h - 2 * b, dep, dcf * CF(-w / 2 + b / 2, 0, 0), fl)
		K:plate("FfFrame", b, h - 2 * b, dep, dcf * CF(w / 2 - b / 2, 0, 0), fl)
	end
	local iw, ih = w - (if fr ~= false then 2 * b else 0), h - (if fr ~= false then 2 * b else 0)
	local face = dcf * CF(0, 0, 0.03)
	if o.lit then
		K:text("FfLightbox", iw, ih, dcf * CF(0, 0, 0.0), "", { bg = o.bg, glow = o.lit, d = 0.03 })
	else
		K:plate("FfPosterBg", iw, ih, 0.03, dcf, pl(o.bg or WHITE))
	end
	local z = 0.004
	if o.art then
		z = art(K, face, o.art, z)
	end
	for i, t in o.texts or {} do
		K:text("FfPosterText", t[4], t[5], face * CF(t[2], t[3], z + i * 0.003), t[1], { fg = t[6], font = t[7] or F.GothamBlack, align = t[8], glow = t[9] or o.textGlow, d = 0.006 })
	end
	if o.glass and not ctx.low then
		K:plate("FfPosterGlass", iw, ih, 0.01, dcf * CF(0, 0, dep - 0.012), { c = rgb(230, 236, 240), m = M.Glass, t = 0.9, r = 0.2 })
	end
end

-- 추가 음식 그림 -------------------------------------------------------------------------------------
local function artGanjang(x: number, y: number, s: number): { any }
	local a = artChicken(x, y, s)
	for i, q in a do
		if i ~= 1 and i ~= 6 then
			q[6] = (q[6] :: Color3):Lerp(rgb(110, 60, 24), 0.55)
		end
	end
	table.insert(a, { "e", x + 0.1 * s, y + 0.2 * s, 0.2 * s, 0.06 * s, rgb(230, 170, 90), 0.2 })
	return a
end

local function artPadak(x: number, y: number, s: number): { any }
	local a = artChicken(x, y - 0.05 * s, s * 0.9)
	for i = -3, 3 do
		table.insert(a, { "b", x + i * 0.12 * s, y + 0.25 * s, 0.05 * s, 0.5 * s, if i % 2 == 0 then rgb(120, 190, 70) else rgb(230, 240, 210), i * 0.3 })
	end
	return a
end

local function artBalls(x: number, y: number, s: number, c: Color3): { any }
	local out = { { "e", x, y - 0.25 * s, 1.3 * s, 0.3 * s, rgb(240, 236, 228) } }
	for i = 0, 5 do
		local a = i * 1.05
		table.insert(out, { "e", x + math.cos(a) * 0.32 * s, y + math.sin(a) * 0.14 * s, 0.36 * s, 0.36 * s, if i % 2 == 0 then c else dark(c, 0.12) })
	end
	return out
end

local function artSundae(x: number, y: number, s: number): { any }
	local out = { { "e", x, y - 0.1 * s, 1.4 * s, 0.5 * s, rgb(244, 242, 236) } }
	for i = -2, 2 do
		table.insert(out, { "e", x + i * 0.24 * s, y, 0.26 * s, 0.26 * s, rgb(50, 36, 42) })
		table.insert(out, { "e", x + i * 0.24 * s, y, 0.14 * s, 0.14 * s, rgb(96, 70, 76) })
	end
	table.insert(out, { "b", x + 0.45 * s, y - 0.2 * s, 0.3 * s, 0.14 * s, rgb(110, 50, 40), 0.3 })
	return out
end

local function artTwigim(x: number, y: number, s: number): { any }
	local out = { { "b", x, y - 0.25 * s, 1.4 * s, 0.14 * s, rgb(246, 240, 220) } }
	local cols = { rgb(206, 150, 70), rgb(222, 176, 96), rgb(214, 140, 60), rgb(196, 150, 70) }
	for i = 0, 4 do
		table.insert(out, { "e", x + (i - 2) * 0.26 * s, y + (i % 2) * 0.1 * s - 0.05 * s, 0.4 * s, 0.26 * s, cols[i % 4 + 1], (i - 2) * 0.3 })
	end
	return out
end

local function artEomuk(x: number, y: number, s: number): { any }
	local out = { { "e", x, y - 0.3 * s, 1.2 * s, 0.34 * s, rgb(200, 160, 100) } }
	for i = -1, 1 do
		table.insert(out, { "b", x + i * 0.3 * s, y + 0.1 * s, 0.03 * s, 0.9 * s, rgb(214, 182, 130), i * 0.15 })
		table.insert(out, { "e", x + i * 0.3 * s, y + 0.02 * s, 0.3 * s, 0.22 * s, rgb(214, 166, 110), i * 0.15 })
		table.insert(out, { "e", x + i * 0.3 * s, y - 0.16 * s, 0.3 * s, 0.22 * s, rgb(200, 150, 96), i * 0.15 })
	end
	return out
end

local function artNoodle(x: number, y: number, s: number, broth: Color3, top: Color3?): { any }
	local out = {
		{ "e", x, y - 0.05 * s, 1.4 * s, 0.6 * s, rgb(40, 40, 44) },
		{ "e", x, y, 1.2 * s, 0.46 * s, broth },
	}
	for i = -2, 2 do
		table.insert(out, { "b", x + i * 0.15 * s, y + 0.02 * s, 0.08 * s, 0.32 * s, rgb(244, 220, 150), 0.5 + i * 0.2 })
	end
	if top then
		table.insert(out, { "e", x + 0.25 * s, y + 0.08 * s, 0.3 * s, 0.14 * s, top })
	end
	table.insert(out, { "e", x - 0.25 * s, y + 0.1 * s, 0.22 * s, 0.16 * s, rgb(250, 246, 236) })
	table.insert(out, { "e", x - 0.25 * s, y + 0.1 * s, 0.1 * s, 0.08 * s, rgb(250, 200, 60) })
	return out
end

-- 사진 메뉴 띠 (라이트박스 한 줄): items = { { 이름, 가격, art } }
local function photoStrip(ctx: any, dcf: CFrame, w: number, h: number, items: { any }, o: any?)
	local K = ctx.K
	local oo: any = o or {}
	local n = #items
	local frameL = oo.frame or L.of(30, 30, 32, M.Metal)
	K:plate("FfStripBox", w + 0.16, h + 0.16, 0.22, dcf, frameL)
	local pw = w / n
	for i, it in items do
		local c = dcf * CF(-w / 2 + pw * (i - 0.5), 0, 0.22)
		K:text("FfStripPanel", pw - 0.06, h, c, "", { bg = oo.bg or rgb(252, 250, 244), glow = 1.1, d = 0.01 })
		local face = c * CF(0, 0, 0.012)
		local s = math.min(pw * 0.62, h * 0.55)
		art(K, face, it[3], 0.002)
		K:text("FfStripName", pw - 0.2, h * 0.17, face * CF(0, -h * 0.3, 0.06), it[1], { fg = oo.fg or rgb(40, 30, 20), font = F.GothamBlack, d = 0.004 })
		K:text("FfStripPrice", pw - 0.3, h * 0.14, face * CF(0, -h * 0.43, 0.06), it[2], { fg = oo.priceC or rgb(200, 30, 30), font = F.GothamBlack, d = 0.004 })
		if i < n then
			K:plate("FfStripDiv", 0.04, h, 0.03, dcf * CF(-w / 2 + pw * i, 0, 0.22), frameL)
		end
		local _ = s
	end
	if oo.title then
		K:text("FfStripTitle", math.min(w * 0.5, 4), 0.34, dcf * CF(0, h / 2 + 0.3, 0.02), oo.title, { fg = WHITE, bg = oo.titleBg or rgb(200, 30, 30), font = F.GothamBlack, d = 0.04 })
	end
end

-- 천장 원목 보 (장애물 · keep 피해 잘라서). axis = "x" (가로 보) | "z" (세로 보)
local function ceilingBeams(ctx: any, axis: string, n: number, look: any, depth: number?)
	local K, V = ctx.K, ctx.V
	local dep = depth or 0.42
	local y = V.H - dep / 2 - 0.01
	local boxes = {}
	for _, r in V.hang do
		table.insert(boxes, r)
	end
	for _, r in V.parts do
		if (r.name == "CassetteAC" or r.name == "Downlight" or r.name == "TBar" or r.name == "LightPanel" or r.name == "LightFrame") then
			table.insert(boxes, r)
		end
	end
	for _, k in V.keep do
		if k.max.Y > V.H - 0.8 then
			table.insert(boxes, { min = k.min, max = k.max })
		end
	end
	for _, q in K.ceilUsed or {} do
		table.insert(boxes, { min = q - V3(0.5, 0, 0.5) + V3(0, V.H - 1, 0), max = q + V3(0.5, 0, 0.5) + V3(0, V.H + 1, 0) })
	end
	for i = 1, n do
		local f = (i - 0.5) / n
		local a0, a1, c
		if axis == "x" then
			c = V.z0 + V.D * f
			a0, a1 = V.x0 + 0.05, V.x1 - 0.05
		else
			c = V.x0 + V.W * f
			a0, a1 = V.z0 + 0.05, V.z1 - 2.0
		end
		-- 이 보와 겹치는 구간 빼기
		local cuts = {}
		for _, b in boxes do
			local lo, hi, cmin, cmax
			if axis == "x" then
				lo, hi, cmin, cmax = b.min.X, b.max.X, b.min.Z, b.max.Z
			else
				lo, hi, cmin, cmax = b.min.Z, b.max.Z, b.min.X, b.max.X
			end
			if b.max.Y > y - dep / 2 and cmin < c + 0.3 and cmax > c - 0.3 then
				table.insert(cuts, { lo - 0.15, hi + 0.15 })
			end
		end
		table.sort(cuts, function(p, q)
			return p[1] < q[1]
		end)
		local cur = a0
		local segs = {}
		for _, ct in cuts do
			if ct[1] > cur then
				table.insert(segs, { cur, math.min(ct[1], a1) })
			end
			cur = math.max(cur, ct[2])
		end
		if cur < a1 then
			table.insert(segs, { cur, a1 })
		end
		for _, sg in segs do
			local len = sg[2] - sg[1]
			if len > 1.2 then
				local m = (sg[1] + sg[2]) / 2
				local cf = if axis == "x" then CF(m, y, c) else CF(c, y, m)
				K:box("FfBeam", if axis == "x" then V3(len, dep, 0.36) else V3(0.36, dep, len), cf, look)
				-- 펜던트 · 조명이 보를 뚫지 않게 천장 사용 기록
				local t = sg[1]
				while t <= sg[2] do
					if axis == "x" then
						Common.useCeil(K, t, c)
					else
						Common.useCeil(K, c, t)
					end
					t += 0.6
				end
			end
		end
	end
end

-- 종이 · 아크릴 안내문 (한 판 + 글자)
local function notice(ctx: any, dcf: CFrame, w: number, h: number, text: string, o: any?)
	local K = ctx.K
	local oo: any = o or {}
	if oo.frame ~= false then
		K:plate("FfNoticeBack", w + 0.08, h + 0.08, 0.03, dcf, oo.frame or L.of(220, 220, 216))
	end
	K:text("FfNotice", w, h, dcf * CF(0, 0, 0.03), text, { fg = oo.fg or rgb(30, 30, 30), bg = oo.bg or rgb(252, 252, 248), font = oo.font or F.GothamBold, d = 0.02, glow = oo.glow })
end

-- 작은 위생 · 결제 스티커 줄 (dcf 가운데, 가로로 n 개)
local function stickerRow(ctx: any, dcf: CFrame, items: { any }, size: number)
	local n = #items
	local gap = size * 0.12
	local total = n * size + (n - 1) * gap
	for i, it in items do
		local x = -total / 2 + size / 2 + (i - 1) * (size + gap)
		ctx.K:text("FfSticker", size, size * (it.h or 0.62), dcf * CF(x, 0, 0), it[1], { fg = it[3] or WHITE, bg = it[2], font = F.GothamBlack, d = 0.012 })
	end
end

-- 원산지 표시판 (음식점 의무 표시)
local function originBoard(ctx: any, dcf: CFrame, w: number, lines: { string })
	local K = ctx.K
	local h = 0.55 + #lines * 0.36
	K:plate("FfOriginBack", w + 0.1, h + 0.1, 0.04, dcf, L.of(40, 60, 120))
	K:text("FfOriginTitle", w, 0.46, dcf * CF(0, h / 2 - 0.25, 0.04), "원 산 지 표 시", { fg = WHITE, bg = rgb(40, 60, 120), font = F.GothamBlack, d = 0.01 })
	K:text("FfOriginBody", w - 0.1, h - 0.6, dcf * CF(0, -0.27, 0.04), table.concat(lines, "\n"), { fg = rgb(20, 24, 40), bg = rgb(250, 250, 246), font = F.GothamBold, align = "Left", d = 0.01 })
	return h
end

-- 와이파이 안내 (아이콘 + 글자)
local function wifiSign(ctx: any, dcf: CFrame, ssid: string, pw: string)
	local K = ctx.K
	K:plate("FfWifiBack", 1.3, 0.62, 0.03, dcf, L.of(250, 250, 248))
	if not ctx.low then
		for i = 1, 3 do
			K:ring("FfWifiArc", dcf * CF(-0.42, -0.12, 0.04), 0.07 * i, 0.03, 4, L.of(40, 120, 220), PI * 0.25, PI * 0.75)
		end
		K:disc("FfWifiDot", 0.05, 0.02, dcf * CF(-0.42, -0.12, 0.04) * ANG(PI / 2, 0, 0), L.of(40, 120, 220))
	end
	K:text("FfWifiText", 0.86, 0.5, dcf * CF(0.16, 0, 0.04), "Wi-Fi  " .. ssid .. "\nPW  " .. pw, { fg = rgb(30, 40, 60), font = F.GothamBold, align = "Left", d = 0.01 })
end

-- 프롬프트를 달 파트 고르기: 후보 중 서버 앵커 6.5 밖에 있는 첫 파트
local function pickAnchor(K: any, parts: { any }): BasePart?
	for _, p in parts do
		if p and p.Parent and Interact.canPrompt(K, K.cf:PointToObjectSpace(p.Position)) then
			return p
		end
	end
	return nil
end

-- 벽걸이 TV (채널 바꾸기 / 자동 순환). chans = { { name, bg, items (art), text, text2? } }
local function tvSet(ctx: any, dcf: CFrame, w: number, chans: { any }, objName: string?)
	local K = ctx.K
	local h = w * 9 / 16
	K:plate("FfTVMount", w * 0.3, h * 0.3, 0.12, dcf, L.blackMetal)
	K:plate("FfTVBody", w + 0.14, h + 0.14, 0.14, dcf * CF(0, 0, 0.12), L.black)
	K:plate("FfTVLogo", 0.24, 0.04, 0.01, dcf * CF(0, -h / 2 - 0.035, 0.265), L.chrome)
	if not ctx.low then
		-- 전원 · HDMI 케이블 (벽 몰딩 덮개로 내려가 콘센트로)
		K:plate("FfTVCableCover", 0.12, 1.4, 0.05, dcf * CF(w * 0.2, -h / 2 - 0.7, 0), L.of(236, 236, 232))
		K:plate("FfTVOutlet", 0.3, 0.4, 0.04, dcf * CF(w * 0.2, -h / 2 - 1.55, 0), L.white)
		K:plate("FfSettopShelf", 0.9, 0.05, 0.46, dcf * CF(-w * 0.3, -h / 2 - 0.4, 0), L.of(30, 30, 32, M.Glass, { t = 0.3 }))
		K:plate("FfSettopBracket", 0.06, 0.25, 0.04, dcf * CF(-w * 0.3, -h / 2 - 0.53, 0), L.blackMetal)
		K:plate("FfSettopBox", 0.7, 0.16, 0.38, dcf * CF(-w * 0.3, -h / 2 - 0.295, 0.02), L.of(30, 30, 32))
		K:plate("FfSettopLed", 0.05, 0.03, 0.01, dcf * CF(-w * 0.3 + 0.25, -h / 2 - 0.295, 0.4), L.ledGreen)
	end
	if not ctx.low then
		K:disc("FfTVLed", 0.04, 0.01, dcf * CF(w / 2 - 0.1, -h / 2 - 0.04, 0.265) * ANG(PI / 2, 0, 0), L.ledRed)
	end
	local screen = K:plate("FfTVScreen", w, h, 0.02, dcf * CF(0, 0, 0.26), { c = chans[1][2], m = M.Neon })
	local face = dcf * CF(0, 0, 0.28)
	local groups = {}
	local labels = {}
	for ci, ch in chans do
		local parts = {}
		for i, it in ch[3] or {} do
			local cf = face * CF(it[2] * w, it[3] * h, i * 0.003) * ANG(0, 0, it[7] or 0)
			local p
			if it[1] == "e" then
				p = K:ell("FfTVArt", V3(it[4] * w, it[5] * h, 0.01), cf, { c = it[6], m = M.Neon })
			else
				p = K:box("FfTVArt", V3(it[4] * w, it[5] * h, 0.01), cf, { c = it[6], m = M.Neon })
			end
			if ci ~= 1 then
				p.Transparency = 1
			end
			table.insert(parts, p)
		end
		local lab = nil
		if ch[4] then
			local tp, tl = K:text("FfTVText", w * 0.92, h * 0.16, face * CF(0, h * 0.4, 0.04), ch[4], { fg = WHITE, glow = 1.4, font = F.GothamBold, d = 0.004 })
			lab = tl
			if ci ~= 1 then
				tl.Visible = false
			end
			table.insert(labels, tl)
		end
		if ch[5] then
			local _, tl2 = K:text("FfTVText2", w * 0.92, h * 0.13, face * CF(0, -h * 0.4, 0.04), ch[5], { fg = WHITE, glow = 1.4, font = F.GothamBold, d = 0.004 })
			if ci ~= 1 then
				tl2.Visible = false
			end
			table.insert(parts, tl2 :: any)
		end
		groups[ci] = { parts = parts, label = lab, bg = ch[2] }
	end
	local function show(i: number)
		for gi, g in groups do
			for _, p in g.parts do
				if typeof(p) == "Instance" and (p :: Instance):IsA("TextLabel") then
					(p :: any).Visible = gi == i
				elseif (p :: any).Parent then
					(p :: any).Transparency = if gi == i then 0 else 1
				end
			end
			if g.label then
				g.label.Visible = gi == i
			end
		end
		if screen.Parent then
			screen.Color = groups[i].bg
		end
	end
	local items = {}
	for i = 1, #chans do
		items[i] = i
	end
	local pr = nil
	-- 전원 버튼 (아래 양 모서리) 도 프롬프트 후보
	local bl = K:plate("FfTVButton", 0.12, 0.05, 0.03, dcf * CF(-w / 2 + 0.25, -h / 2 - 0.04, 0.26), L.of(60, 60, 64))
	local br = K:plate("FfTVButton", 0.12, 0.05, 0.03, dcf * CF(w / 2 - 0.25, -h / 2 - 0.04, 0.26), L.of(60, 60, 64))
	local anchor = pickAnchor(K, { screen, bl, br })
	if anchor then
		pr = Interact.cycle(K, anchor, items, { object = objName or "TV", action = "채널 바꾸기", on = function(i)
			show(i)
		end })
	end
	if not pr then
		-- 프롬프트를 둘 수 없는 자리: 채널이 저절로 돔
		local last = 1
		Interact.anim(K, function(t)
			local i = math.floor(t / 9) % #chans + 1
			if i ~= last then
				last = i
				show(i)
			end
		end)
	end
	return screen
end

-- 네온사인 (글자 + 선택 네온관 그림) + 켜기/끄기
local function neonSign(ctx: any, dcf: CFrame, w: number, h: number, text: string, c: Color3, o: any?): any
	local K = ctx.K
	local oo: any = o or {}
	local tubes = {}
	local anchors = {}
	if oo.backer ~= false then
		K:plate("FfNeonBacker", w + 0.3, h + 0.24, 0.05, dcf, oo.backerLook or { c = rgb(26, 26, 30), m = M.Glass, t = 0.4 })
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				table.insert(anchors, K:cyl("FfNeonStandoff", 0.16, 0.08, dcf * CF(sx * (w / 2 + 0.05), sy * (h / 2 + 0.02), 0.13) * ANG(0, PI / 2, 0), L.chrome))
			end
		end
	end
	local plate, label = K:text("FfNeonText", w, h, dcf * CF(0, 0, 0.08), text, { fg = c, glow = 2.4, font = oo.font or F.GothamBlack })
	for _, sg in oo.shapes or {} do
		-- sg = { a = Vector2, b = Vector2 } 표시면 좌표의 네온관
		local pa = (dcf * CF(sg[1], sg[2], 0.1)).Position
		local pb = (dcf * CF(sg[3], sg[4], 0.1)).Position
		local p = K:seg("FfNeonTube", pa, pb, 0.07, neon(sg[5] or c), 0.06)
		if p then
			table.insert(tubes, p)
		end
	end
	local lt = nil
	if oo.light ~= false then
		lt = K:light(plate, "SurfaceLight", { Face = Enum.NormalId.Front, Range = 6, Brightness = 0.55, Angle = 70, Color = c })
	end
	local rec = { plate = plate, label = label, tubes = tubes, light = lt, c = c }
	if oo.toggle ~= false and plate.Parent and ctx.toggles < 2 then
		table.insert(anchors, 1, plate)
		local anchor = pickAnchor(K, anchors)
		if anchor then
			local pr = Interact.toggle(K, anchor, {
				object = oo.object or "네온사인",
				state = true,
				on = function(state)
					label.TextColor3 = if state then c else dark(c, 0.65)
					local g = label.Parent :: any
					if g then
						g.Brightness = if state then 2.4 else 1
						g.LightInfluence = if state then 0 else 1
					end
					for _, t in tubes do
						t.Material = if state then M.Neon else M.SmoothPlastic
						t.Color = if state then c else dark(c, 0.5)
					end
					if lt then
						lt.Enabled = state
					end
				end,
			})
			if pr then
				ctx.toggles += 1
			end
		end
	end
	return rec
end

-- 벽걸이 선풍기 (좌우 회전 + 날개 회전, 켜기/끄기). dcf = 벽 표면 브래킷 가운데
local function wallFan(ctx: any, dcf: CFrame, o: any?)
	local K = ctx.K
	local oo: any = o or {}
	local body = oo.body or L.of(238, 238, 234, M.Plastic)
	local bladeL = oo.blade or { c = rgb(120, 190, 230), m = M.Plastic, t = 0.25 }
	K:plate("FfFanBracket", 0.5, 0.7, 0.08, dcf, body)
	local pivot = dcf * CF(0, -0.2, 0.55)
	K:bar("FfFanArm", (dcf * CF(0, 0, 0.08)).Position, pivot.Position, 0.14, 0.14, body)
	local head = {}
	local blades = {}
	local tilt = ANG(0.22, 0, 0)
	local hcf = pivot * tilt
	table.insert(head, K:ell("FfFanMotor", V3(0.5, 0.5, 0.72), hcf * CF(0, 0, 0.1), body))
	local cageC = hcf * CF(0, 0, 0.62)
	table.insert(head, K:cyl("FfFanCageBack", 0.04, 1.34, cageC * CF(0, 0, -0.16) * ANG(0, PI / 2, 0), { c = rgb(220, 222, 224), m = M.Metal, t = 0.72 }))
	for _, p in K:ring("FfFanCage", cageC * CF(0, 0, 0.12), 0.66, 0.04, if ctx.low then 8 else 12, L.of(226, 228, 230, M.Metal)) do
		table.insert(head, p)
	end
	if not ctx.low then
		for i = 0, 3 do
			local a = i * PI / 4
			table.insert(head, K:box("FfFanWire", V3(1.3, 0.025, 0.025), cageC * CF(0, 0, 0.14) * ANG(0, 0, a), L.of(226, 228, 230, M.Metal)))
		end
	end
	table.insert(head, K:cyl("FfFanBadge", 0.06, 0.26, cageC * CF(0, 0, 0.16) * ANG(0, PI / 2, 0), oo.badge or L.of(40, 110, 200)))
	local hub = cageC * CF(0, 0, -0.02)
	table.insert(head, K:cyl("FfFanHub", 0.14, 0.2, hub * ANG(0, PI / 2, 0), body))
	for i = 0, 2 do
		local a = i * 2 * PI / 3
		local b = K:ell("FfFanBlade", V3(0.26, 0.56, 0.04), hub * ANG(0, 0, a) * CF(0, 0.3, 0) * ANG(0, 0.35, 0), bladeL)
		table.insert(blades, { p = b, a = a })
	end
	-- 상대 자세 기록
	local wp = K.cf * pivot
	local rel = {}
	for _, p in head do
		if p.Parent then
			table.insert(rel, { p = p, r = wp:ToObjectSpace(p.CFrame) })
		end
	end
	local hubRel = (pivot):ToObjectSpace(hub)
	local on = true
	local spin = 0
	local yawT = 0
	local lastT: number? = nil
	Interact.anim(K, function(t)
		local dt = if lastT then math.clamp(t - (lastT :: number), 0, 0.3) else 0.1
		lastT = t
		if not on then
			return
		end
		yawT += dt
		spin += dt * 11
		local yaw = math.sin(yawT * 0.55) * 0.55
		local base = wp * ANG(0, yaw, 0)
		for _, r in rel do
			if r.p.Parent then
				r.p.CFrame = base * r.r
			end
		end
		local hw = base * hubRel
		for _, b in blades do
			if b.p.Parent then
				b.p.CFrame = hw * ANG(0, 0, b.a + spin) * CF(0, 0.3, 0) * ANG(0, 0.35, 0)
			end
		end
	end)
	local motor = head[1]
	if motor and motor.Parent and ctx.toggles < 3 then
		local lp = K.cf:PointToObjectSpace(motor.Position)
		if Interact.canPrompt(K, lp) then
			local pr = Interact.toggle(K, motor, { object = "선풍기", state = true, on = function(s)
				on = s
			end })
			if pr then
				ctx.toggles += 1
			end
		end
	end
end

-- 여러 문짝을 한 프롬프트로 여닫기 (냉장고 2~3칸)
local function swingDoors(ctx: any, doors: { any }, object: string)
	local K = ctx.K
	local recs = {}
	local handle: BasePart? = nil
	for _, d in doors do
		local parts = {}
		for _, p in d.model:GetDescendants() do
			if p:IsA("BasePart") then
				table.insert(parts, { p = p, cf = p.CFrame })
				if string.find(p.Name, "Handle") and not handle and Interact.canPrompt(K, K.cf:PointToObjectSpace(p.Position)) then
					handle = p
				end
			end
		end
		table.insert(recs, { parts = parts, hinge = d.hinge, angle = d.angle })
	end
	if not handle then
		for _, r in recs do
			for _, q in r.parts do
				if not handle and string.find(q.p.Name, "Frame") and Interact.canPrompt(K, K.cf:PointToObjectSpace(q.p.Position)) then
					handle = q.p
				end
			end
		end
	end
	if not handle or not (handle :: BasePart).Parent then
		return nil
	end
	local open = false
	local axis = (K.cf.UpVector :: Vector3)
	local function set(o: boolean)
		for _, r in recs do
			local rot = CFrame.new(r.hinge) * CFrame.fromAxisAngle(axis, if o then r.angle else 0) * CFrame.new(-r.hinge)
			for _, q in r.parts do
				if q.p.Parent then
					TweenService:Create(q.p, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = rot * q.cf }):Play()
				end
			end
		end
	end
	return Interact.prompt(K, handle :: BasePart, {
		action = "열기",
		object = object,
		sound = "rbxasset://sounds/clickfast.wav",
		fn = function(_n, p)
			open = not open
			set(open)
			p.ActionText = if open then "닫기" else "열기"
		end,
	})
end

-- 음료 쇼케이스 냉장고 (속이 보이는 빈 몸체: 옆판 · 뒤판 · 천장 · 받침 + 선반 + 병/캔 + 유리문)
-- items = { { Color3, "can"|"bottle"|"pet"|"soju", cap? } } 순서대로 채움
local function drinkFridge(ctx: any, pcf: CFrame, o: any): any
	local K = ctx.K
	local nd = o.doors or 2
	local dw = o.doorW or 2.0
	local w = nd * dw + 0.3
	local h = o.h or 6.4
	local d = o.d or 2.0
	local body = o.body or L.of(34, 36, 40, M.Metal)
	local inner = L.of(236, 240, 242)
	-- 몸체 (빈 상자)
	K:box("FfFridgeSide", V3(0.15, h, d), pcf * CF(-w / 2 + 0.075, h / 2, 0), body)
	K:box("FfFridgeSide", V3(0.15, h, d), pcf * CF(w / 2 - 0.075, h / 2, 0), body)
	K:box("FfFridgeBack", V3(w - 0.3, h, 0.12), pcf * CF(0, h / 2, -d / 2 + 0.06), body)
	K:box("FfFridgeKick", V3(w - 0.3, 0.6, d), pcf * CF(0, 0.3, 0), body)
	local headH = 0.75
	K:box("FfFridgeTop", V3(w - 0.3, headH, d), pcf * CF(0, h - headH / 2, 0), body)
	K:text("FfFridgeHeader", w - 0.2, headH - 0.14, pcf * CF(0, h - headH / 2, d / 2 + 0.005), o.header or "시원한 음료", { fg = o.headerFg or WHITE, bg = o.headerBg or rgb(200, 30, 36), glow = 1.3, font = F.GothamBlack, d = 0.02 })
	local innerH = h - headH - 0.6
	local y0 = 0.6
	K:box("FfFridgeInner", V3(w - 0.32, innerH, 0.03), pcf * CF(0, y0 + innerH / 2, -d / 2 + 0.135), inner)
	-- 안쪽 LED (문 사이 · 양옆 세로)
	local lamp = K:box("FfFridgeLamp", V3(w - 0.4, 0.06, 0.08), pcf * CF(0, y0 + innerH - 0.06, d / 2 - 0.3), neon(rgb(236, 246, 255)))
	if o.light ~= false then
		K:light(lamp, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 7, Brightness = 0.7, Angle = 140, Color = L.coolLight })
	end
	for i = 0, nd do
		local x = -w / 2 + 0.15 + i * dw
		K:box("FfFridgeLedV", V3(0.05, innerH - 0.1, 0.05), pcf * CF(x + (if i == 0 then 0.05 elseif i == nd then -0.05 else 0), y0 + innerH / 2, d / 2 - 0.2), neon(rgb(230, 242, 255)))
	end
	-- 선반 + 음료
	local shelves = o.shelves or 4
	local items = o.items
	local k = 0
	local depthRows = if ctx.low then 1 else 2
	for s = 1, shelves do
		local y = y0 + (s - 1) * innerH / shelves + 0.04
		K:box("FfFridgeShelf", V3(w - 0.34, 0.04, d - 0.4), pcf * CF(0, y, 0.0), L.of(210, 214, 218, M.Metal))
		if not ctx.low then
			K:box("FfFridgePriceRail", V3(w - 0.34, 0.12, 0.02), pcf * CF(0, y - 0.02, d / 2 - 0.2), L.of(250, 250, 250))
		end
		local x = -w / 2 + 0.32
		local maxH = innerH / shelves - 0.2
		while x < w / 2 - 0.3 do
			k += 1
			local it = items[(k - 1) % #items + 1]
			local kind = it[2]
			local dia = if kind == "can" then 0.24 elseif kind == "pet" then 0.32 elseif kind == "soju" then 0.24 else 0.26
			local ht = math.min(maxH, if kind == "can" then 0.44 elseif kind == "pet" then 1.05 elseif kind == "soju" then 0.78 else 0.82)
			for r = 1, depthRows do
				local z = d / 2 - 0.42 - (r - 1) * 0.42
				local base = pcf * CF(x, y + 0.02, z)
				if kind == "can" then
					K:vcyl("FfCan", ht, dia, base * CF(0, ht / 2, 0), { c = it[1], m = M.Metal })
					if r == 1 and not ctx.low then
						K:vcyl("FfCanTop", 0.03, dia * 0.86, base * CF(0, ht + 0.015, 0), L.alu)
					end
				else
					local glass = kind == "soju" or kind == "bottle"
					local bl = if glass then { c = it[1], m = M.Glass, t = 0.2, r = 0.08 } else { c = it[1], m = M.Plastic, t = 0.1 }
					K:vcyl("FfBottle", ht * 0.66, dia, base * CF(0, ht * 0.33, 0), bl)
					K:vcyl("FfBottleNeck", ht * 0.3, dia * 0.42, base * CF(0, ht * 0.66 + ht * 0.15, 0), bl)
					if r == 1 then
						K:vcyl("FfBottleLabel", ht * 0.24, dia + 0.01, base * CF(0, ht * 0.34, 0), pl(it[3] or WHITE))
					end
				end
			end
			x += dia + 0.06
		end
	end
	-- 문 (프레임 + 유리 + 손잡이), 경첩 = 각 문 왼쪽 (짝수 칸은 오른쪽)
	local doors = {}
	for i = 1, nd do
		local x0 = -w / 2 + 0.15 + (i - 1) * dw
		local leftHinge = (i % 2 == 1)
		local zf = d / 2 + 0.05
		local m = K:group("FfFridgeDoor_" .. i, function()
			local c = pcf * CF(x0 + dw / 2, y0 + innerH / 2, zf)
			local fl = L.of(26, 26, 28, M.Metal)
			K:box("FfFridgeDoorFrame", V3(dw - 0.02, 0.12, 0.1), c * CF(0, innerH / 2 - 0.06, 0), fl)
			K:box("FfFridgeDoorFrame", V3(dw - 0.02, 0.12, 0.1), c * CF(0, -innerH / 2 + 0.06, 0), fl)
			K:box("FfFridgeDoorFrame", V3(0.1, innerH - 0.24, 0.1), c * CF(-dw / 2 + 0.06, 0, 0), fl)
			K:box("FfFridgeDoorFrame", V3(0.1, innerH - 0.24, 0.1), c * CF(dw / 2 - 0.06, 0, 0), fl)
			K:box("FfFridgeDoorGlass", V3(dw - 0.2, innerH - 0.24, 0.03), c, { c = rgb(214, 232, 238), m = M.Glass, t = 0.78, r = 0.15 })
			local hx = if leftHinge then dw / 2 - 0.2 else -dw / 2 + 0.2
			K:box("FfFridgeDoorHandle", V3(0.07, innerH * 0.55, 0.07), c * CF(hx, 0, 0.14), L.chrome)
			K:box("FfFridgeDoorHandle", V3(0.05, 0.05, 0.12), c * CF(hx, innerH * 0.27, 0.08), L.chrome)
			K:box("FfFridgeDoorHandle", V3(0.05, 0.05, 0.12), c * CF(hx, -innerH * 0.27, 0.08), L.chrome)
		end)
		local hx = if leftHinge then x0 else x0 + dw
		table.insert(doors, { model = m, hinge = (K.cf * pcf * CF(hx, 0, zf)).Position, angle = if leftHinge then -1.75 else 1.75 })
	end
	if not ctx.low then
		K:plate("FfFridgeVent", w * 0.7, 0.32, 0.02, pcf * CF(0, 0.3, d / 2), L.of(60, 60, 64, M.DiamondPlate))
		K:text("FfFridgeBrand", 0.9, 0.18, pcf * CF(-w / 2 + 0.7, 0.3, d / 2 + 0.025), o.brand or "SHOWCASE", { fg = rgb(220, 220, 220), font = F.GothamBold, d = 0.005 })
	end
	return { doors = doors, w = w, h = h, d = d }
end

-- 냉장고 놓기: 2칸 -> 1칸 순서로 자리 찾기 (맵에 냉장고가 이미 있으면 건너뜀)
local function placeFridge(ctx: any, o: any): any
	local V = ctx.V
	if not o.force and (V:has("FridgeDoor") > 0 or V:has("Fridge") > 0 or V:has("OpenChiller") > 0) then
		return nil
	end
	for _, nd in { 2, 1 } do
		local w = nd * 2.0 + 0.3
		local pcf = floorSpot(ctx, { walls = o.walls or { "back", "right", "left" }, w = w, h = 6.4, d = 2.0, pref = o.pref or { back = "right", right = "back", left = "back" }, prompt = true, front = 1.2 })
		if pcf then
			local oo = table.clone(o)
			oo.doors = nd
			local fr = drinkFridge(ctx, pcf, oo)
			swingDoors(ctx, fr.doors, o.object or "음료 냉장고")
			return fr
		end
	end
	return nil
end

-- 천장에서 매다는 펜던트 (테이블 위). 맵 펜던트가 있는 매장은 Common 이 이미 바꿨으므로 건너뜀
local function tablePendants(ctx: any, o: any)
	local K, V = ctx.K, ctx.V
	if V:has("PendantShade") > 0 or V:has("PendantGlobe") > 0 then
		return
	end
	local nLight = 0
	for _, t in V.tables do
		if t.kind ~= "table" then
			continue
		end
		local cx, cz = (t.min.X + t.max.X) / 2, (t.min.Z + t.max.Z) / 2
		local alongX = (t.max.X - t.min.X) >= (t.max.Z - t.min.Z)
		local spots = {}
		if o.pair and alongX and (t.max.X - t.min.X) > 3 then
			spots = { { cx - 0.85, cz }, { cx + 0.85, cz } }
		else
			spots = { { cx, cz } }
		end
		for _, sp in spots do
			local x, z = sp[1], sp[2]
			-- 형광등 · 에어컨 피해 앞뒤로 조금씩 옮겨 보기
			local placed = false
			for _, dz in { 0, 0.5, -0.5, 0.9, -0.9 } do
				local zz = math.clamp(z + dz, t.min.Z + 0.2, t.max.Z - 0.2)
				if Common.ceilFree(K, x, zz, 0.55) then
					local drop = math.clamp(V.H - 6.6, 1.6, 3.6)
					local withLight = nLight < (o.lights or 1) and #K.lights < (V.maxLights or 8) - 2
					K:free(function()
						Props.pendant(K, V3(x, V.H, zz), drop, { shade = o.shade or "dome", dia = o.dia or 1.15, look = o.look, glow = o.glow, light = withLight, range = 12, bright = 0.6 })
					end)
					if withLight then
						nLight += 1
					end
					Common.useCeil(K, x, zz)
					placed = true
					break
				end
			end
			if not placed then
				continue
			end
		end
	end
end

-- 벽 위쪽 칠 (맵 벽 조각이 있는 곳만: 주방 창 · 문 구멍은 피함). 벽면 0.012 앞
local function upperPaint(ctx: any, walls: { string }, y0: number, look: any, y1: number?)
	local K, V = ctx.K, ctx.V
	local top = y1 or (V.H - 0.02)
	local names = {
		back = { "ShopBackWall", "BackWall" },
		left = { "ShopPartition", "ShopWall", "Partition", "SideWall", "Wall" },
		right = { "ShopPartition", "ShopWall", "Partition", "SideWall", "Wall" },
	}
	for _, wn in walls do
		local wl = V.walls[wn]
		if not wl then
			continue
		end
		for _, nm in names[wn] do
			for _, r in V.byName[nm] or {} do
				local plane: number, face: number
				if wn == "back" then
					plane, face = V.z0, r.max.Z
				elseif wn == "left" then
					plane, face = V.x0, r.max.X
				else
					plane, face = V.x1, r.min.X
				end
				if math.abs(face - plane) > 0.3 then
					continue
				end
				local umin, umax = math.huge, -math.huge
				for _, x in { r.min.X, r.max.X } do
					for _, z in { r.min.Z, r.max.Z } do
						local u = V:wallCoord(wn, V3(x, 0, z))
						umin = math.min(umin, u)
						umax = math.max(umax, u)
					end
				end
				umin = math.max(umin, wl.a)
				umax = math.min(umax, wl.b)
				local ya, yb = math.max(y0, r.min.Y), math.min(top, r.max.Y)
				if umax - umin > 0.3 and yb - ya > 0.2 then
					K:free(function()
						K:plate("FfWallPaint", umax - umin, yb - ya, 0.02, V:wall(wn, (umin + umax) / 2, (ya + yb) / 2, 0.012), look)
					end)
				end
			end
		end
	end
end

-- 몰딩 띠 (벽 따라 수평 한 줄, 문 · 창 · 기존 물건은 V:spans 로 피함)
local function wallBand(ctx: any, walls: { string }, y: number, hgt: number, dep: number, look: any)
	local K, V = ctx.K, ctx.V
	for _, wn in walls do
		for _, s in V:spans(wn, y - hgt / 2, y + hgt / 2, 0.3) do
			K:free(function()
				K:plate("FfWallBand", s[2] - s[1], hgt, dep, V:wall(wn, (s[1] + s[2]) / 2, y, 0.02), look)
			end)
		end
	end
end

-- 주방 패스 (KitchenPass + PassLedge) 덮개 + 노렌/후드 -----------------------------------------------
-- o = { trim (look), inner (Color3), lamp (Color3), header = "noren" | "hood" | "pickup" | nil, norenText, norenColor, hoodText }
local function passDress(ctx: any, o: any)
	local K, V = ctx.K, ctx.V
	for _, r in V.byName.KitchenPass or {} do
		if r.c.Z > V.z0 + 1.0 or r.size.X < 1 then
			continue
		end
		local w, h = r.size.X, r.size.Y
		local face = CFrame.fromMatrix(V3(r.c.X, r.c.Y, r.max.Z), Vector3.xAxis, Vector3.yAxis, Vector3.zAxis)
		K:free(function()
			-- 같은 자리 · 같은 크기 덮개 (주방 안쪽처럼 보이는 어두운 스테인리스)
			K:box("FfPassCover", r.size + V3(0.004, 0.004, 0.004), CF(r.c), L.of(46, 48, 52, M.Metal))
			local z = 0.004
			-- 안쪽 벽 타일 (조금 그늘진 흰 타일 + 줄눈) + 아래 스테인리스 조리대 띠 + 위 따뜻한 빛
			K:plate("FfPassTile", w - 0.12, h - 0.62, 0.006, face * CF(0, -0.18, z), L.of(204, 206, 204, M.CeramicTiles))
			K:plate("FfPassCounter", w - 0.12, h * 0.2, 0.012, face * CF(0, -h / 2 + h * 0.1 + 0.02, z + 0.004), L.of(150, 154, 158, M.Metal))
			K:plate("FfPassCounterEdge", w - 0.12, 0.05, 0.016, face * CF(0, -h / 2 + h * 0.2 + 0.02, z + 0.006), L.chrome)
			K:plate("FfPassGlow", w - 0.2, h * 0.34, 0.004, face * CF(0, h * 0.12, z + 0.014), { c = rgb(255, 176, 96), m = M.Neon, t = 0.86 })
			if not ctx.low then
				-- 선반 위 양념통 · 바구니 실루엣
				local cols = o.shelfColors or { rgb(200, 40, 30), rgb(240, 196, 40), rgb(246, 244, 236), rgb(200, 40, 30), rgb(60, 60, 64) }
				for i, c in cols do
					local tx = -w / 2 + 0.45 + (i - 1) * (w - 0.9) / math.max(1, #cols - 1)
					K:plate("FfPassJar", 0.32, 0.4, 0.01, face * CF(tx, h * 0.06 + 0.26, z + 0.012), pl(c))
				end
			end
			if not ctx.low then
				for i = 1, 3 do
					K:plate("FfPassGrout", w - 0.12, 0.02, 0.008, face * CF(0, -0.18 - (h - 0.62) / 2 + i * (h - 0.62) / 4, z), L.of(170, 172, 170))
				end
				for i = 1, math.floor(w / 0.8) do
					K:plate("FfPassGrout", 0.02, h - 0.62, 0.008, face * CF(-w / 2 + 0.06 + i * 0.8, -0.18, z), L.of(170, 172, 170))
				end
			end
			-- 주방 선반 (스테인리스) + 위 후드 그림자 띠
			K:plate("FfPassShelf", w - 0.12, 0.12, 0.03, face * CF(0, h * 0.06, z + 0.006), L.steel)
			K:plate("FfPassHoodBand", w, 0.5, 0.02, face * CF(0, h / 2 - 0.25, z), L.of(70, 72, 76, M.Metal))
			-- 열 램프 (주황 네온 2줄)
			local lampC = o.lamp or rgb(255, 150, 70)
			for _, sx in { -1, 1 } do
				K:plate("FfPassHeatLamp", w * 0.36, 0.07, 0.04, face * CF(sx * w * 0.22, h / 2 - 0.55, z + 0.01), neon(lampC))
			end
			-- 주문서 레일 + 주문서
			K:plate("FfTicketRail", w - 0.3, 0.07, 0.05, face * CF(0, h / 2 - 0.78, z + 0.01), L.chrome)
			local nT = if ctx.low then 2 else 4
			for i = 1, nT do
				local tx = -w / 2 + 0.5 + (i - 1) * (w - 1.0) / math.max(1, nT - 1)
				K:plate("FfTicket", 0.3, 0.46, 0.008, face * CF(tx, h / 2 - 1.04, z + 0.06) * ANG(0, 0, (i % 2 - 0.5) * 0.06), L.paper)
				if not ctx.low then
					for j = 1, 3 do
						K:plate("FfTicketLine", 0.22, 0.025, 0.004, face * CF(tx, h / 2 - 0.9 - j * 0.09, z + 0.068), L.of(60, 60, 60))
					end
				end
			end
			-- 안쪽 소품 실루엣 (국자 · 튀김망 · 뒤집개)
			if not ctx.low then
				for i = 1, 3 do
					local tx = -w / 2 + w * (0.25 + (i - 1) * 0.25)
					K:plate("FfPassUtensil", 0.06, 0.6, 0.008, face * CF(tx, -0.15, z + 0.012), L.of(150, 152, 156, M.Metal))
					if o.utensil == "basket" then
						K:plate("FfPassUtensil", 0.42, 0.3, 0.008, face * CF(tx, -0.55, z + 0.012), L.of(120, 122, 126, M.DiamondPlate))
					else
						K:ell("FfPassUtensil", V3(0.26, 0.18, 0.008), face * CF(tx, -0.5, z + 0.016), L.of(150, 152, 156, M.Metal))
					end
				end
			end
			-- 둘레 몰딩 (벽 마감)
			local tl = o.trim or L.steel
			local tw = 0.16
			K:plate("FfPassTrim", w + 2 * tw, tw, 0.1, face * CF(0, h / 2 + tw / 2, 0), tl)
			K:plate("FfPassTrim", tw, h, 0.1, face * CF(-w / 2 - tw / 2, 0, 0), tl)
			K:plate("FfPassTrim", tw, h, 0.1, face * CF(w / 2 + tw / 2, 0, 0), tl)
		end)
		Scan.hide(K.hidden, r.part)
		-- 헤더
		local topY = r.max.Y
		local hd = o.header
		if hd == "noren" then
			for _, n in V.byName.Noren or {} do
				Scan.hide(K.hidden, n.part)
			end
			local txt = o.norenText or { "분", "식" }
			local n = #txt
			local nw = (w + 0.2) / n
			local col = o.norenColor or rgb(30, 40, 90)
			K:free(function()
				local rodY = topY + 0.3
				K:cyl("FfNorenRod", w + 0.7, 0.12, face * CF(0, rodY - r.c.Y, 0.22), L.of(120, 84, 50, M.Wood))
				for _, sx in { -1, 1 } do
					K:box("FfNorenHook", V3(0.06, 0.2, 0.22), face * CF(sx * (w / 2 + 0.25), rodY - r.c.Y + 0.08, 0.11), L.brass)
				end
				for i = 1, n do
					local x = -w / 2 - 0.1 + nw * (i - 0.5)
					local pcf = face * CF(x, rodY - r.c.Y - 0.62, 0.22)
					K:box("FfNoren", V3(nw - 0.08, 1.16, 0.03), pcf, { c = col, m = M.Fabric })
					K:box("FfNorenHem", V3(nw - 0.08, 0.08, 0.04), pcf * CF(0, 0.54, 0), { c = dark(col, 0.3), m = M.Fabric })
					K:text("FfNorenText", (nw - 0.08) * 0.8, 0.7, pcf * CF(0, -0.06, 0.016), txt[i], { fg = WHITE, font = F.GothamBlack, d = 0.004 })
				end
			end)
		elseif hd == "hood" or hd == "pickup" then
			for _, n in V.byName.Noren or {} do
				Scan.hide(K.hidden, n.part)
			end
			local hw = w + 0.5
			local hh = math.min(0.75, (V.H - topY) - 2.2)
			if hh > 0.3 then
				local hc = face * CF(0, topY - r.c.Y + 0.12 + hh / 2, 0)
				local hl = o.hoodLook or L.steel
				K:free(function()
					K:box("FfPassHood", V3(hw, hh, 0.55), hc * CF(0, 0, 0.275), hl)
					K:box("FfPassHoodLip", V3(hw, 0.06, 0.6), hc * CF(0, -hh / 2 - 0.03, 0.3), dark(hl.c, 0.2) and L.with(hl, { c = dark(hl.c, 0.2) }))
					local txt = o.hoodText or "PICK UP"
					K:text("FfPassHoodText", hw * 0.7, hh * 0.62, hc * CF(0, 0, 0.553), txt, { fg = o.hoodFg or rgb(255, 80, 60), glow = 1.8, font = F.GothamBlack, d = 0.01 })
					if hd == "pickup" and not ctx.low then
						-- 주문번호 호출 모니터 (번호가 바뀜)
						local mw = 1.5
						local mcf = hc * CF(hw / 2 + mw / 2 + 0.3, 0, 0)
						K:plate("FfPickupMon", mw + 0.1, hh + 0.1, 0.12, mcf, L.black)
						local scr, lab = K:text("FfPickupNum", mw, hh, mcf * CF(0, 0, 0.12), "주문번호\n0127", { fg = rgb(255, 210, 60), bg = rgb(16, 16, 20), glow = 1.6, font = F.GothamBlack, d = 0.01 })
						local nums = { "0127", "0128", "0131", "0132", "0135" }
						Interact.anim(K, function(t)
							local i = math.floor(t / 6) % #nums + 1
							lab.Text = "주문번호\n" .. nums[i]
						end)
					end
				end)
			end
		end
	end
	-- 패스 선반: 같은 윗면 · 같은 범위 스테인리스 덮개 (앞 모서리 둥글게)
	for _, r in V.byName.PassLedge or {} do
		local w, d, t = r.size.X, r.size.Z, r.size.Y
		if w < 0.8 or d < 0.3 then
			continue
		end
		K:free(function()
			K:box("FfPassLedge", V3(w, t, d - t / 2), CF(r.c.X, r.c.Y, r.c.Z - t / 4), L.of(196, 200, 204, M.Metal, { r = 0.1 }))
			K:cyl("FfPassLedgeNose", w, t, CF(r.c.X, r.c.Y, r.max.Z - t / 2), L.of(196, 200, 204, M.Metal, { r = 0.1 }))
			if not ctx.low then
				K:box("FfPassLedgeLine", V3(w - 0.1, 0.02, 0.04), CF(r.c.X, r.max.Y + 0.004, r.max.Z - t - 0.08), L.of(150, 154, 158, M.Metal))
			end
		end)
		Scan.hide(K.hidden, r.part)
	end
end

-- 메뉴판 (Sign_메  뉴 / Sign_MENU) 둘레 액자 + 아래 LED 띠 + 위 스포트 (간판 자체는 안 건드림)
local function menuSignDress(ctx: any, look: any, ledC: Color3?)
	local K, V = ctx.K, ctx.V
	for _, r in ctx.wallSigns do
		local nm = r.name
		if not (has(nm, "메  뉴") or has(nm, "MENU") or has(nm, "SUB OF") or has(nm, "SALAD") or has(nm, "15cm")) then
			continue
		end
		if r.c.Z > V.z0 + 0.8 or r.size.X < 2 then
			continue -- 뒷벽 메뉴판만
		end
		local w, h = r.size.X, r.size.Y
		local dcf = CFrame.fromMatrix(V3(r.c.X, r.c.Y, V.z0), Vector3.xAxis, Vector3.yAxis, Vector3.zAxis)
		K:free(function()
			K:plate("FfMenuBacker", w + 0.4, h + 0.36, 0.035, dcf, look)
			if ledC then
				K:plate("FfMenuLED", w - 0.3, 0.05, 0.05, dcf * CF(0, -h / 2 - 0.14, 0.06), neon(ledC))
			end
		end)
		-- 위에서 비추는 작은 스포트 2개 (레일 없이 벽 암)
		if not ctx.low and r.max.Y < V.H - 0.5 then
			for _, sx in { -0.3, 0.3 } do
				local base = dcf * CF(sx * w, h / 2 + 0.35, 0)
				K:free(function()
					K:plate("FfSpotPlate", 0.24, 0.24, 0.04, base, L.blackMetal)
					local tip = base * CF(0, 0.05, 0.7)
					K:bar("FfSpotArm", (base * CF(0, 0, 0.04)).Position, tip.Position, 0.05, 0.05, L.blackMetal)
					local hcf = CFrame.lookAt(tip.Position, (dcf * CF(sx * w, 0, 0)).Position)
					K:cyl("FfSpotHead", 0.36, 0.22, hcf * CF(0, 0, -0.1) * ANG(0, PI / 2, 0), L.blackMetal)
					K:disc("FfSpotLens", 0.17, 0.02, hcf * CF(0, 0, -0.29) * ANG(PI / 2, 0, 0), L.lampWarm)
				end)
			end
		end
	end
end

-- 무인 주문 키오스크 (OrderKiosk + KioskScreen): 같은 자리 · 같은 크기 덮개 (세로형 터치스크린 + 카드 단말 + 영수증)
local function kioskOverlay(ctx: any, brand: string, accent: Color3, tiles: { Color3 }?)
	local K, V = ctx.K, ctx.V
	local scr = V:first("KioskScreen")
	for _, r in V.byName.OrderKiosk or {} do
		-- 화면이 있는 면 = 정면
		local face = V3(0, 0, 1)
		if scr then
			local d = scr.c - r.c
			if math.abs(d.X) > math.abs(d.Z) then
				face = V3(math.sign(d.X), 0, 0)
			else
				face = V3(0, 0, if d.Z < 0 then -1 else 1)
			end
		end
		local w = if math.abs(face.X) > 0.5 then r.size.Z else r.size.X
		local d = if math.abs(face.X) > 0.5 then r.size.X else r.size.Z
		local h = r.size.Y
		local base = CFrame.lookAt(V3(r.c.X, r.min.Y, r.c.Z), V3(r.c.X, r.min.Y, r.c.Z) - face)
		K:free(function()
			K:box("FfKioskPlinth", V3(w, 0.22, d), base * CF(0, 0.11, 0), L.of(30, 30, 32, M.Metal))
			K:box("FfKioskBody", V3(w - 0.04, h - 0.22, d - 0.04), base * CF(0, 0.22 + (h - 0.22) / 2, 0), L.of(40, 42, 46))
			K:box("FfKioskSide", V3(0.06, h - 0.3, d), base * CF(-w / 2 + 0.03, 0.22 + (h - 0.3) / 2, 0), L.of(200, 202, 206, M.Metal))
			K:box("FfKioskSide", V3(0.06, h - 0.3, d), base * CF(w / 2 - 0.03, 0.22 + (h - 0.3) / 2, 0), L.of(200, 202, 206, M.Metal))
			local fz = d / 2 + 0.005
			-- 머리 로고
			K:text("FfKioskBrand", w - 0.2, 0.4, base * CF(0, h - 0.32, fz), brand, { fg = WHITE, bg = accent, glow = 1.4, font = F.GothamBlack, d = 0.02 })
			-- 화면 (맵 화면 자리)
			local sy = if scr then scr.c.Y else h * 0.73
			local sh = if scr then scr.size.Y else 2.2
			local sw = math.min(w - 0.2, if scr then math.max(scr.size.X, scr.size.Z) else w - 0.3)
			local sc = base * CF(0, sy, fz)
			K:text("FfKioskUI", sw, sh, sc, "", { bg = rgb(250, 250, 252), glow = 1.25, d = 0.02 })
			K:text("FfKioskTop", sw, sh * 0.13, sc * CF(0, sh * 0.435, 0.022), "주문하실 메뉴를 선택하세요", { fg = WHITE, bg = accent, glow = 1.3, font = F.GothamBold, d = 0.004 })
			local cols = tiles or { rgb(214, 140, 60), rgb(200, 30, 36), rgb(250, 196, 40), rgb(90, 170, 60), rgb(150, 90, 50), rgb(60, 120, 200) }
			if not ctx.low then
				for i = 0, 5 do
					local cx = (i % 2 - 0.5) * sw * 0.46
					local cy = sh * 0.24 - math.floor(i / 2) * sh * 0.22
					K:text("FfKioskTile", sw * 0.42, sh * 0.18, sc * CF(cx, cy, 0.022), "", { bg = cols[i % #cols + 1], glow = 1.1, d = 0.004 })
				end
			end
			K:text("FfKioskPay", sw * 0.9, sh * 0.1, sc * CF(0, -sh * 0.43, 0.022), "결제하기", { fg = WHITE, bg = rgb(30, 30, 34), glow = 1.2, font = F.GothamBlack, d = 0.004 })
			-- 카드 단말 · NFC · 영수증
			local py = sy - sh / 2 - 0.45
			K:box("FfKioskCard", V3(0.6, 0.36, 0.1), base * CF(-w * 0.18, py, fz + 0.05), L.of(20, 20, 22))
			K:box("FfKioskCardSlot", V3(0.46, 0.04, 0.02), base * CF(-w * 0.18, py - 0.08, fz + 0.11), L.of(70, 70, 74))
			K:text("FfKioskNFC", 0.36, 0.2, base * CF(w * 0.2, py, fz + 0.01), "IC · NFC", { fg = rgb(120, 220, 255), bg = rgb(20, 24, 30), glow = 1.2, font = F.GothamBold, d = 0.01 })
			K:box("FfKioskReceipt", V3(0.5, 0.04, 0.02), base * CF(0, py - 0.45, fz + 0.01), L.of(20, 20, 22))
			K:text("FfKioskReceiptLbl", 0.6, 0.12, base * CF(0, py - 0.58, fz + 0.005), "영수증", { fg = rgb(200, 200, 200), font = F.GothamBold, d = 0.004 })
		end)
		Scan.hide(K.hidden, r.part)
	end
	if scr then
		Scan.hide(K.hidden, scr.part)
	end
end

-- 금지 구역: 주방 패스 앞, 키오스크 · 카운터 앞, 입구 -> 각 서비스 지점 동선, 화장실 문 앞, NPC 2 스터드
local function setupZones(ctx: any)
	local V = ctx.V
	local doorIn = V3(V.door.x, 0, V.z1 - 2.6)
	local targets = {}
	for _, nm in { "KitchenPass", "PassLedge" } do
		for _, r in V.byName[nm] or {} do
			addNo(ctx, V3(r.min.X - 1.0, 0.05, V.z0 - 0.5), V3(r.max.X + 1.0, 8, math.max(r.max.Z, V.z0) + 3.2))
			table.insert(targets, V3(r.c.X, 0, math.max(r.max.Z, V.z0) + 2.5))
		end
	end
	for _, nm in { "OrderKiosk", "KioskScreen", "PosBase" } do
		for _, r in V.byName[nm] or {} do
			addNo(ctx, V3(r.min.X - 1.2, 0.05, r.min.Z - 2.6), V3(r.max.X + 1.2, 8, r.max.Z + 2.6))
			table.insert(targets, V3(r.c.X, 0, r.c.Z))
		end
	end
	for _, g in V.counters do
		local alongX = (g.max.X - g.min.X) >= (g.max.Z - g.min.Z)
		if alongX then
			addNo(ctx, V3(g.min.X - 0.5, 0.05, g.max.Z), V3(g.max.X + 0.5, 8, g.max.Z + 2.8))
			table.insert(targets, V3((g.min.X + g.max.X) / 2, 0, g.max.Z + 1.5))
		else
			local cx = (g.min.X + g.max.X) / 2
			if cx > 0 then
				addNo(ctx, V3(g.min.X - 2.8, 0.05, g.min.Z - 0.5), V3(g.min.X, 8, g.max.Z + 0.5))
			else
				addNo(ctx, V3(g.max.X, 0.05, g.min.Z - 0.5), V3(g.max.X + 2.8, 8, g.max.Z + 0.5))
			end
		end
	end
	for _, nm in { "DoorLeaf", "StaffDoor" } do
		for _, r in V.byName[nm] or {} do
			local p = V3(r.c.X, 0, r.c.Z)
			if r.size.X >= r.size.Z then
				p = V3(r.c.X, 0, r.c.Z + (if r.c.Z < 0 then 2.4 else -2.4))
			else
				p = V3(r.c.X + (if r.c.X < 0 then 2.4 else -2.4), 0, r.c.Z)
			end
			addNo(ctx, V3(r.min.X - 0.6, 0.05, r.min.Z - 0.6), V3(r.max.X + 0.6, 8, r.max.Z + 0.6))
			table.insert(targets, p)
		end
	end
	-- 맵 냉장고 · 정수기 · 셀프바 앞
	for _, nm in { "FridgeDoor", "Purifier", "SelfTop", "WaterStand", "SelfCounter", "BrothUrn", "OpenChiller" } do
		for _, r in V.byName[nm] or {} do
			addNo(ctx, r.min - V3(1.2, 0, 1.2), r.max + V3(1.2, 0, 1.2))
		end
	end
	for _, t in targets do
		corridor(ctx, doorIn, t, 2.8)
	end
	-- NPC 모형 (맵 고정 직원 · 분식 이모): 2.5 스터드 비움 (Kit keep 으로 넣어 모든 새 파트가 피함)
	for _, r in V.byName.HumanoidRootPart or {} do
		V:addKeep(V3(r.min.X - 2.5, 0.05, r.min.Z - 2.5), V3(r.max.X + 2.5, 7, r.max.Z + 2.5), "npc")
	end
end

-- 영업 안내 소품 묶음 (영업시간 · 와이파이 · 결제 · 원산지 · 스티커)
local function infoSet(ctx: any, o: any)
	local K = ctx.K
	local walls = o.walls or { "right", "left", "back" }
	local dcf = wallSpot(ctx, walls, 2.0, 4.2 + 0.0, 6.6, o.originPrefer)
	if dcf then
		originBoard(ctx, dcf, 1.8, o.origin)
	end
	local d2 = wallSpot(ctx, walls, 1.5, 4.6, 5.6, o.hoursPrefer)
	if d2 then
		notice(ctx, d2, 1.4, 0.9, o.hours or "영업시간\n11:00 - 24:00", { bg = rgb(250, 250, 246), font = F.GothamBold })
	end
	local d3 = wallSpot(ctx, walls, 1.4, 4.0, 4.7, o.wifiPrefer)
	if d3 then
		wifiSign(ctx, d3, o.ssid or "SHOP_5G", o.pw or "12345678")
	end
	local d4 = wallSpot(ctx, walls, 2.6, 3.7, 4.3, o.stickerPrefer)
	if d4 then
		local items = o.stickers or {
			{ "카드 · 페이\n결제 가능", rgb(40, 90, 200) },
			{ "현금영수증\n발행", rgb(60, 60, 64) },
			{ "포장 주문\n환영", rgb(220, 60, 40) },
		}
		stickerRow(ctx, d4, items, 0.78)
	end
end

-- 바닥에 세우는 낮은 장식장 몸체 (상판 · 문짝 · 걸레받이). 반환 상판 높이
local function cabinet(ctx: any, pcf: CFrame, w: number, h: number, d: number, bodyL: any, topL: any, o: any?): number
	local K = ctx.K
	local oo: any = o or {}
	K:box("FfCabBody", V3(w, h - 0.36, d - 0.06), pcf * CF(0, 0.3 + (h - 0.36) / 2 - 0.15, -0.03), bodyL)
	K:box("FfCabKick", V3(w - 0.1, 0.3, d - 0.2), pcf * CF(0, 0.15, -0.1), L.black)
	K:box("FfCabTop", V3(w + 0.06, 0.12, d + 0.04), pcf * CF(0, h - 0.06, 0), topL)
	local nd = oo.doors or math.max(1, math.floor(w / 1.2))
	if not ctx.low then
		local dw = (w - 0.1) / nd
		for i = 1, nd do
			local x = -w / 2 + 0.05 + dw * (i - 0.5)
			K:plate("FfCabDoorGap", 0.03, h - 0.62, 0.012, pcf * CF(x + dw / 2, 0.3 + (h - 0.62) / 2, d / 2 - 0.06), L.of(40, 40, 40))
			K:box("FfCabHandle", V3(0.05, 0.42, 0.06), pcf * CF(x + (if i % 2 == 0 then -dw / 2 + 0.16 else dw / 2 - 0.16), h - 0.75, d / 2 - 0.03), oo.handle or L.chrome)
		end
	end
	return h
end

-- 치킨집 소품 ----------------------------------------------------------------------------------------
local function beerMug(K: any, base: CFrame, full: boolean, frost: boolean?)
	local gl = { c = if frost then rgb(232, 240, 244) else rgb(220, 232, 236), m = M.Glass, t = if frost then 0.25 else 0.5, r = 0.1 }
	K:vcyl("FfMug", 0.52, 0.3, base * CF(0, 0.26, 0), gl)
	if full then
		K:vcyl("FfMugBeer", 0.4, 0.26, base * CF(0, 0.2, 0), { c = rgb(236, 168, 30), m = M.Glass, t = 0.15 })
		K:vcyl("FfMugFoam", 0.1, 0.27, base * CF(0, 0.46, 0), L.of(252, 250, 244))
	end
	K:bar("FfMugHandle", (base * CF(0.15, 0.4, 0)).Position, (base * CF(0.26, 0.26, 0)).Position, 0.05, 0.05, gl)
	K:bar("FfMugHandle", (base * CF(0.26, 0.26, 0)).Position, (base * CF(0.15, 0.1, 0)).Position, 0.05, 0.05, gl)
end

-- 생맥주 셀프 · 서빙 스테이션 (냉각 캐비닛 + 맥주 타워 + 잔 냉동고 + 잔)
local function beerStation(ctx: any, pcf: CFrame, w: number)
	local K = ctx.K
	local P = ctx.pal
	local h, d = 3.3, 1.5
	local top = cabinet(ctx, pcf, w, h, d, L.of(60, 62, 66, M.Metal), L.of(196, 200, 204, M.Metal, { r = 0.1 }), { doors = 2 })
	-- 왼쪽 잔 냉동고 유리문 (성에 낀 잔)
	local gx = -w / 2 + 0.75
	local door = K:group("FfFrosterDoor", function()
		K:plate("FfFrosterGlass", 1.2, 1.8, 0.03, pcf * CF(gx, 1.4, d / 2 + 0.1), { c = rgb(220, 236, 244), m = M.Glass, t = 0.5, r = 0.15 })
		K:plate("FfFrosterFrame", 1.26, 0.08, 0.16, pcf * CF(gx, 2.31, d / 2 - 0.03), L.of(40, 42, 46, M.Metal))
		K:plate("FfFrosterFrame", 1.26, 0.08, 0.16, pcf * CF(gx, 0.49, d / 2 - 0.03), L.of(40, 42, 46, M.Metal))
		K:plate("FfFrosterFrame", 0.08, 1.74, 0.16, pcf * CF(gx - 0.59, 1.4, d / 2 - 0.03), L.of(40, 42, 46, M.Metal))
		K:plate("FfFrosterFrame", 0.08, 1.74, 0.16, pcf * CF(gx + 0.59, 1.4, d / 2 - 0.03), L.of(40, 42, 46, M.Metal))
		K:plate("FfFrosterHandle", 0.06, 0.9, 0.08, pcf * CF(gx + 0.48, 1.4, d / 2 + 0.13), L.chrome)
	end)
	K:plate("FfFrosterInner", 1.1, 1.7, 0.01, pcf * CF(gx, 1.4, d / 2 - 0.055), L.of(230, 242, 250))
	local hp = door:FindFirstChild("FfFrosterHandle") :: BasePart?
	if hp and hp.Parent and pickAnchor(K, { hp }) then
		Interact.swing(K, door, (K.cf * pcf * CF(gx - 0.6, 0, d / 2)).Position, K.cf.UpVector, -1.5, { object = "잔 냉동고", openText = "문 열기", closeText = "문 닫기" })
	end
	if not ctx.low then
		for row = 0, 1 do
			for i = -1, 1 do
				K:vcyl("FfFrostMug", 0.44, 0.24, pcf * CF(gx + i * 0.34, 0.8 + row * 0.8, d / 2 - 0.05), { c = rgb(240, 246, 250), m = M.Glass, t = 0.25 })
			end
		end
	end
	-- 맥주 타워 (서리 낀 크롬 기둥 + T 바 + 탭 2개 + 손잡이)
	local tx = w / 2 - 1.0
	local tb = pcf * CF(tx, top, -0.1)
	K:disc("FfTowerBase", 0.5, 0.06, tb * CF(0, 0.03, 0), L.chrome)
	K:vcyl("FfTowerCol", 1.25, 0.24, tb * CF(0, 0.66, 0), { c = rgb(224, 232, 238), m = M.Metal, r = 0.2 })
	K:vcyl("FfTowerFrost", 0.7, 0.27, tb * CF(0, 0.75, 0), { c = rgb(240, 246, 250), m = M.Ice, t = 0.25 })
	K:cyl("FfTowerBar", 1.1, 0.16, tb * CF(0, 1.3, 0), L.chrome)
	for _, sx in { -1, 1 } do
		local tap = tb * CF(sx * 0.4, 1.3, 0)
		K:cyl("FfTapSpout", 0.24, 0.07, tap * CF(0, -0.02, 0.12) * ANG(0, PI / 2, 0), L.chrome)
		K:vcyl("FfTapNozzle", 0.14, 0.05, tap * CF(0, -0.1, 0.22), L.chrome)
		K:vcyl("FfTapHandle", 0.5, 0.08, tap * CF(0, 0.32, 0.12), L.black)
		K:vcyl("FfTapKnob", 0.16, 0.13, tap * CF(0, 0.6, 0.12), if sx < 0 then L.of(30, 90, 190) else L.of(30, 140, 70))
	end
	K:box("FfDripTray", V3(1.2, 0.06, 0.42), tb * CF(0, 0.03, 0.3), L.of(60, 62, 66, M.Metal))
	if not ctx.low then
		K:box("FfDripGrate", V3(1.12, 0.012, 0.36), tb * CF(0, 0.066, 0.3), L.of(150, 154, 158, M.DiamondPlate))
	end
	-- 엎어 놓은 500cc 잔 (고무 매트 위)
	local mx = -w / 2 + 0.75
	K:box("FfBarMat", V3(1.2, 0.03, 0.8), pcf * CF(mx, top + 0.015, 0.05), L.of(30, 30, 32, M.Rubber))
	local n = if ctx.low then 2 else 6
	for i = 1, n do
		local col = (i - 1) % 3
		local row = math.floor((i - 1) / 3)
		local base = pcf * CF(mx - 0.36 + col * 0.36, top + 0.03, -0.18 + row * 0.36)
		K:vcyl("FfMugUp", 0.5, 0.3, base * CF(0, 0.25, 0), { c = rgb(222, 234, 238), m = M.Glass, t = 0.45 })
	end
	-- 가격 꽂이
	local sp = pcf * CF(0.1, top, 0.4)
	K:box("FfPriceStandBase", V3(0.6, 0.04, 0.24), sp * CF(0, 0.02, 0), L.acrylicWhite)
	K:text("FfPriceStand", 0.56, 0.4, sp * CF(0, 0.25, 0) * ANG(math.rad(-10), 0, 0), "생맥주\n500cc " .. priceIn(ctx.signs, "생맥주", "4,500"), { fg = rgb(30, 30, 30), bg = rgb(255, 214, 60), d = 0.02, font = F.GothamBlack })
	-- 캐비닛 앞 브랜드 띠
	K:text("FfBeerBand", w - 0.3, 0.32, pcf * CF(0, h - 0.4, d / 2 + 0.005), "생맥주  DRAFT BEER", { fg = WHITE, bg = P.accent, font = F.GothamBlack, d = 0.01 })
end

-- 셀프 코너 (치킨무 · 소스 · 물티슈 · 비닐장갑 · 앞치마)
local function selfBar(ctx: any, pcf: CFrame, w: number, o: any?)
	local K = ctx.K
	local P = ctx.pal
	local oo: any = o or {}
	local h, d = 3.1, 1.3
	local top = cabinet(ctx, pcf, w, h, d, oo.body or L.with(P.wood or L.oak, {}), L.marbleWhite, { doors = 2 })
	local y = top
	-- 치킨무 통 (반투명 사각 통 + 하얀 무 + 집게)
	local mu = pcf * CF(-w / 2 + 0.55, y, 0)
	K:box("FfRadishTub", V3(0.75, 0.42, 0.6), mu * CF(0, 0.21, 0), { c = rgb(236, 244, 240), m = M.Glass, t = 0.4 })
	K:box("FfRadish", V3(0.66, 0.3, 0.52), mu * CF(0, 0.17, 0), L.of(250, 250, 238))
	K:box("FfRadishLid", V3(0.8, 0.04, 0.64), mu * CF(-0.05, 0.44, -0.05) * ANG(0, 0.12, 0), L.of(230, 70, 60, M.Plastic))
	K:bar("FfTongs", (mu * CF(0.25, 0.46, 0.1)).Position, (mu * CF(0.45, 0.48, 0.42)).Position, 0.05, 0.03, L.steel)
	if not ctx.low then
		K:text("FfRadishLabel", 0.5, 0.16, mu * CF(0, 0.24, 0.305), "치킨무", { fg = WHITE, bg = rgb(220, 60, 50), d = 0.005, font = F.GothamBlack })
	end
	-- 소스 통 3 (양념 · 머스터드 · 마요)
	for i, c in { rgb(190, 40, 30), rgb(240, 196, 40), rgb(246, 244, 236) } do
		local b = pcf * CF(-w / 2 + 1.15 + (i - 1) * 0.26, y, -0.25)
		K:vcyl("FfSauceBottle", 0.5, 0.2, b * CF(0, 0.25, 0), L.of(c.R * 255, c.G * 255, c.B * 255, M.Plastic))
		K:vcyl("FfSauceTip", 0.14, 0.07, b * CF(0, 0.57, 0), L.of(240, 240, 240, M.Plastic))
	end
	-- 물티슈 더미 + 비닐장갑 상자 + 종이컵
	if w > 2.2 then
		local wt = pcf * CF(w / 2 - 0.55, y, -0.2)
		for i = 0, 2 do
			K:box("FfWetWipe", V3(0.5, 0.06, 0.36), wt * CF(0, 0.03 + i * 0.065, 0) * ANG(0, i * 0.2, 0), L.of(250, 250, 250))
			if not ctx.low then
				K:box("FfWetWipeBand", V3(0.2, 0.065, 0.37), wt * CF(0, 0.03 + i * 0.065, 0) * ANG(0, i * 0.2, 0), L.of(60, 150, 210))
			end
		end
		local gb = pcf * CF(w / 2 - 0.55, y, 0.3)
		K:box("FfGloveBox", V3(0.6, 0.3, 0.32), gb * CF(0, 0.15, 0), L.of(250, 250, 250))
		K:text("FfGloveLabel", 0.5, 0.18, gb * CF(0, 0.15, 0.165), "위생장갑", { fg = rgb(30, 90, 190), d = 0.005, font = F.GothamBlack })
		K:vcyl("FfCupStack", 0.7, 0.26, pcf * CF(0.25, y + 0.35, -0.3), L.of(250, 250, 246))
		K:vcyl("FfCupStackRim", 0.03, 0.29, pcf * CF(0.25, y + 0.7, -0.3), L.of(240, 240, 236))
	end
	-- 수저통 (스테인리스 원통 + 숟가락 · 젓가락)
	local sj = pcf * CF(0.25, y, 0.25)
	K:vcyl("FfSpoonPot", 0.5, 0.3, sj * CF(0, 0.25, 0), L.steel)
	if not ctx.low then
		for i = 0, 4 do
			local a = i * 1.25
			K:seg("FfSpoon", (sj * CF(math.cos(a) * 0.06, 0.45, math.sin(a) * 0.06)).Position, (sj * CF(math.cos(a) * 0.12, 0.85, math.sin(a) * 0.12)).Position, 0.03, L.chrome)
		end
	end
	-- 벽 안내판 + 앞치마 걸이
	local wcf = pcf * CF(0, 0, -d / 2 - 0.06)
	local sgn = wcf * CF(0, h + 1.15, 0)
	K:text("FfSelfSign", math.min(w - 0.2, 2.4), 0.55, sgn, "셀프 코너", { fg = WHITE, bg = P.accent, font = F.GothamBlack, d = 0.04 })
	K:text("FfSelfSign2", math.min(w - 0.2, 2.4), 0.3, sgn * CF(0, -0.45, 0), "치킨무 · 소스 · 물티슈 · 앞치마", { fg = rgb(40, 30, 20), bg = rgb(250, 246, 236), font = F.GothamBold, d = 0.04 })
	if not ctx.low and w > 2.2 then
		local hr = wcf * CF(0, h + 0.38, 0)
		K:plate("FfApronRail", w - 0.4, 0.12, 0.06, hr, L.walnut)
		for i, c in { rgb(30, 30, 32), rgb(196, 40, 36) } do
			local x = -w / 2 + 0.6 + (i - 1) * 0.65
			K:plate("FfApronHook", 0.05, 0.12, 0.16, hr * CF(x, 0, 0.06), L.chrome)
			K:plate("FfApron", 0.5, 0.75, 0.03, hr * CF(x, -0.42, 0.1), { c = c, m = M.Fabric })
			K:plate("FfApronStrap", 0.3, 0.08, 0.03, hr * CF(x, -0.02, 0.1), { c = c, m = M.Fabric })
		end
	end
end

-- 포장 박스 랙 (철제 선반 + 치킨 박스 · 1.25L 콜라 · 비닐봉투)
local function boxRack(ctx: any, pcf: CFrame, w: number, brand: string)
	local K = ctx.K
	local P = ctx.pal
	local h, d = 5.2, 1.2
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			K:vcyl("FfRackPost", h, 0.08, pcf * CF(sx * (w / 2 - 0.05), h / 2, sz * (d / 2 - 0.05)), L.chrome)
		end
	end
	for i, y in { 0.3, 1.9, 3.5, 5.0 } do
		K:box("FfRackShelf", V3(w, 0.06, d), pcf * CF(0, y, 0), L.of(200, 204, 208, M.DiamondPlate))
		if i < 4 then
			local n = math.max(1, math.floor((w - 0.2) / 1.05))
			for j = 1, n do
				local x = -w / 2 + 0.1 + (w - 0.2) * (j - 0.5) / n
				if i == 1 and j == n then
					-- 콜라 1.25L 묶음
					for k = 0, 2 do
						K:vcyl("FfColaPet", 1.0, 0.3, pcf * CF(x - 0.32 + k * 0.32, y + 0.53, 0.1), { c = rgb(60, 24, 20), m = M.Plastic, t = 0.1 })
						K:vcyl("FfColaLabel", 0.26, 0.31, pcf * CF(x - 0.32 + k * 0.32, y + 0.5, 0.1), L.of(210, 30, 36))
						K:vcyl("FfColaCap", 0.07, 0.12, pcf * CF(x - 0.32 + k * 0.32, y + 1.06, 0.1), L.of(210, 30, 36))
					end
				else
					local stack = if i == 3 then 2 else 4
					for k = 0, stack - 1 do
						K:box("FfChickenBox", V3(0.95, 0.34, 0.95), pcf * CF(x, y + 0.2 + k * 0.35, 0) * ANG(0, (k % 2) * 0.05, 0), L.of(250, 248, 242, M.Cardboard))
						K:box("FfChickenBoxBand", V3(0.96, 0.12, 0.96), pcf * CF(x, y + 0.24 + k * 0.35, 0) * ANG(0, (k % 2) * 0.05, 0), pl(P.accent))
					end
					if not ctx.low then
						K:text("FfChickenBoxLogo", 0.7, 0.14, pcf * CF(x, y + 0.2 + (stack - 1) * 0.35 + 0.08, 0.485), brand, { fg = P.accent, font = F.GothamBlack, d = 0.004 })
					end
				end
			end
		end
	end
	-- 비닐봉투 롤
	if not ctx.low then
		K:cyl("FfBagRoll", w - 0.5, 0.3, pcf * CF(0, 4.6, 0.2), L.of(236, 236, 232, M.Plastic))
	end
end

-- 맥주 · 치킨 네온 (맥주잔 네온관 그림 + 글자)
local function chimaekNeon(ctx: any, dcf: CFrame, w: number, txt: string, c: Color3, c2: Color3)
	local s = 0.55
	local x0 = -w / 2 + 0.55
	local shapes = {
		{ x0 - s * 0.45, -s, x0 + s * 0.45, -s, c2 },
		{ x0 - s * 0.45, -s, x0 - s * 0.5, s * 0.8, c2 },
		{ x0 + s * 0.45, -s, x0 + s * 0.5, s * 0.8, c2 },
		{ x0 - s * 0.6, s * 0.8, x0 + s * 0.6, s * 0.8, WHITE },
		{ x0 + s * 0.5, s * 0.4, x0 + s * 0.85, s * 0.3, c2 },
		{ x0 + s * 0.85, s * 0.3, x0 + s * 0.85, -s * 0.4, c2 },
		{ x0 + s * 0.85, -s * 0.4, x0 + s * 0.48, -s * 0.5, c2 },
	}
	return neonSign(ctx, dcf, w, 1.0, txt, c, { shapes = shapes, object = "네온사인" })
end

local CHICKEN_DRINKS = {
	{ rgb(200, 24, 32), "can", rgb(200, 24, 32) }, -- 콜라
	{ rgb(40, 150, 70), "can" }, -- 사이다
	{ rgb(30, 70, 170), "can" }, -- 맥주 (블루)
	{ rgb(20, 20, 22), "can" }, -- 제로
	{ rgb(36, 110, 50), "soju", rgb(240, 250, 240) }, -- 소주
	{ rgb(60, 120, 40), "bottle", rgb(30, 110, 40) }, -- 맥주 (녹색 병)
	{ rgb(236, 120, 30), "can" }, -- 환타
	{ rgb(200, 230, 240), "pet", rgb(40, 120, 210) }, -- 생수
}

local function baseballChannels(): { any }
	return {
		{ "야구", rgb(30, 100, 46), {
			{ "b", 0, -0.18, 0.34, 0.34, rgb(150, 100, 56), PI / 4 },
			{ "b", 0, -0.18, 0.2, 0.2, rgb(40, 120, 54), PI / 4 },
			{ "b", 0, -0.42, 0.04, 0.06, rgb(240, 240, 240), PI / 4 },
			{ "b", 0.12, -0.18, 0.04, 0.06, rgb(240, 240, 240), PI / 4 },
			{ "b", 0, 0.38, 1.0, 0.18, rgb(16, 26, 70) },
		}, "롯데 3 : 2 두산   7회말 1사 2루", "사직야구장 LIVE · 2026 KBO" },
		{ "뉴스", rgb(20, 46, 110), {
			{ "b", 0, -0.2, 0.7, 0.18, rgb(40, 40, 50) },
			{ "e", 0, 0.05, 0.12, 0.2, rgb(220, 180, 150) },
			{ "b", 0, -0.08, 0.22, 0.16, rgb(30, 30, 40) },
			{ "b", 0, -0.42, 1.0, 0.12, rgb(200, 24, 32) },
		}, "부산 MBC 뉴스", "[속보] 광안리 불꽃축제 11월 8일 개최" },
		{ "먹방", rgb(240, 160, 50), {
			{ "e", 0, -0.12, 0.5, 0.36, rgb(250, 246, 236) },
			{ "e", -0.06, -0.1, 0.24, 0.18, rgb(200, 122, 44) },
			{ "e", 0.08, -0.06, 0.22, 0.16, rgb(176, 98, 32) },
			{ "e", 0.04, -0.16, 0.2, 0.14, rgb(170, 40, 24) },
		}, "치킨 먹방 특집", "오늘 밤 야식은 반반 치킨!" },
		{ "날씨", rgb(60, 140, 210), {
			{ "e", -0.25, 0.0, 0.22, 0.38, rgb(255, 210, 60) },
			{ "e", 0.1, -0.05, 0.3, 0.22, rgb(250, 250, 250) },
			{ "e", 0.22, -0.02, 0.22, 0.18, rgb(250, 250, 250) },
		}, "부산 날씨  맑음 22°C", "광안리 해수욕장 파도 0.5m" },
	}
end

-- 주방 튀김기 · 후드 (맵 Fryer / Hood 자리 그대로 스테인리스 덮개: GwShop 주방 창으로 보임)
local function fryerOverlay(ctx: any)
	local K, V = ctx.K, ctx.V
	local steel = L.of(196, 200, 204, M.Metal, { r = 0.1 })
	for _, r in V.byName.Fryer or {} do
		local w, h, d = r.size.X, r.size.Y, r.size.Z
		-- 정면 = 방(+Z) 쪽
		local base = CF(r.c.X, r.min.Y, r.c.Z)
		K:free(function()
			K:box("FfFryerBody", V3(w, h - 0.12, d), base * CF(0, (h - 0.12) / 2, 0), steel)
			K:box("FfFryerTop", V3(w, 0.12, d), base * CF(0, h - 0.06, 0), L.of(170, 174, 178, M.Metal))
			K:box("FfFryerKick", V3(w - 0.1, 0.4, 0.04), base * CF(0, 0.2, d / 2 + 0.01), L.black)
			K:box("FfFryerPanel", V3(w - 0.2, 0.7, 0.04), base * CF(0, h - 0.55, d / 2 + 0.01), L.of(40, 42, 46))
			for i = -1, 1 do
				K:cyl("FfFryerKnob", 0.08, 0.22, base * CF(i * w * 0.25, h - 0.55, d / 2 + 0.06) * ANG(0, PI / 2, 0), L.black)
			end
			K:box("FfFryerLed", V3(0.08, 0.08, 0.02), base * CF(w / 2 - 0.25, h - 0.42, d / 2 + 0.04), neon(rgb(255, 60, 40)))
			K:box("FfFryerLed", V3(0.08, 0.08, 0.02), base * CF(w / 2 - 0.4, h - 0.42, d / 2 + 0.04), neon(rgb(60, 230, 120)))
			K:box("FfFryerDoorGap", V3(0.03, h - 1.4, 0.02), base * CF(0, (h - 1.4) / 2 + 0.45, d / 2 + 0.01), L.of(90, 92, 96))
			K:text("FfFryerLabel", w * 0.5, 0.18, base * CF(0, h - 1.05, d / 2 + 0.02), "가스 튀김기 · 18L", { fg = rgb(40, 40, 40), bg = rgb(230, 232, 234), d = 0.005, font = F.GothamBold })
		end)
		Scan.hide(K.hidden, r.part)
	end
	for _, r in V.byName.FryerOil or {} do
		K:free(function()
			K:box("FfFryerOil", r.size, CF(r.c), { c = rgb(214, 150, 40), m = M.Glass, t = 0.12, r = 0.2 })
			K:box("FfFryerRim", V3(r.size.X + 0.1, 0.06, 0.06), CF(r.c.X, r.max.Y, r.max.Z + 0.03), L.chrome)
			K:box("FfFryerRim", V3(r.size.X + 0.1, 0.06, 0.06), CF(r.c.X, r.max.Y, r.min.Z - 0.03), L.chrome)
		end)
		Scan.hide(K.hidden, r.part)
	end
	for _, r in V.byName.FryBasket or {} do
		K:free(function()
			local c = CF(r.c)
			K:box("FfBasketMesh", r.size - V3(0.04, 0.04, 0.04), c, { c = rgb(170, 174, 178), m = M.DiamondPlate, t = 0.25 })
			K:box("FfBasketRim", V3(r.size.X, 0.05, 0.05), c * CF(0, r.size.Y / 2 - 0.03, r.size.Z / 2), L.chrome)
			K:box("FfBasketRim", V3(r.size.X, 0.05, 0.05), c * CF(0, r.size.Y / 2 - 0.03, -r.size.Z / 2), L.chrome)
			K:box("FfBasketRim", V3(0.05, 0.05, r.size.Z), c * CF(r.size.X / 2, r.size.Y / 2 - 0.03, 0), L.chrome)
			K:box("FfBasketRim", V3(0.05, 0.05, r.size.Z), c * CF(-r.size.X / 2, r.size.Y / 2 - 0.03, 0), L.chrome)
			-- 튀김 중인 치킨 몇 조각
			for i = 0, 2 do
				K:ell("FfFryingChicken", V3(0.3, 0.2, 0.26), c * CF((i - 1) * 0.26, 0.12, (i % 2) * 0.2 - 0.1), L.of(206, 140, 56))
			end
		end)
		Scan.hide(K.hidden, r.part)
	end
	for _, r in V.byName.BasketHandle or {} do
		K:free(function()
			K:box("FfBasketHandle", r.size, CF(r.c), L.of(30, 30, 32, M.Rubber))
		end)
		Scan.hide(K.hidden, r.part)
	end
	for _, r in V.byName.Hood or {} do
		K:free(function()
			local c = CF(r.c)
			K:box("FfHoodBox", V3(r.size.X, r.size.Y * 0.55, r.size.Z), c * CF(0, r.size.Y * 0.225, 0), steel)
			K:wedge("FfHoodSlope", V3(r.size.X, r.size.Y * 0.45, 0.5), c * CF(0, -r.size.Y * 0.275, r.size.Z / 2 - 0.25) * ANG(0, PI, 0), steel)
			K:box("FfHoodBack", V3(r.size.X, r.size.Y * 0.45, r.size.Z - 0.5), c * CF(0, -r.size.Y * 0.275, -0.25), L.of(150, 154, 158, M.Metal))
			local n = math.max(3, math.floor(r.size.X / 1.0))
			for i = 1, n do
				K:box("FfHoodFilter", V3(r.size.X / n - 0.1, 0.03, r.size.Z - 0.7), c * CF(-r.size.X / 2 + (i - 0.5) * r.size.X / n, -r.size.Y / 2 + 0.03, -0.2), L.of(120, 124, 128, M.DiamondPlate))
			end
			K:box("FfHoodLamp", V3(r.size.X - 0.6, 0.04, 0.12), c * CF(0, -r.size.Y / 2 + 0.02, r.size.Z / 2 - 0.35), neon(rgb(255, 236, 200)))
		end)
		Scan.hide(K.hidden, r.part)
	end
	for _, nm in { "HoodFilter", "FryerDial" } do
		for _, r in V.byName[nm] or {} do
			Scan.hide(K.hidden, r.part)
		end
	end
end

local function chickenBuild(ctx: any)
	local K, V, S = ctx.K, ctx.V, ctx.S
	local P = ctx.pal
	local tong = ctx.sk == "tongdak"
	local nm = V.name or "치킨"
	if nm == "SideShop" then
		nm = if tong then "옛날통닭" else "치킨"
	end
	local pF = priceIn(ctx.signs, "후라이드", "20,000")
	local pY = priceIn(ctx.signs, "양념", "21,000")
	local pB = priceIn(ctx.signs, "반반", pY)
	-- 벽 위쪽 칠 + 몰딩 (GwShop 은 맵 마감 유지)
	if not ctx.gw then
		local lh = if S.lower then S.lower.h else 0.45
		upperPaint(ctx, { "left", "right" }, lh + 0.08, pl(P.wall, M.Plaster))
		upperPaint(ctx, { "back" }, 0.45, pl(P.wall2, M.Plaster))
		wallBand(ctx, { "left", "right" }, V.H - 0.9, 0.22, 0.05, pl(P.accent))
		if S.lower then
			wallBand(ctx, { "left", "right" }, S.lower.h + 0.04, 0.14, 0.16, if P.key == "red" then L.of(200, 30, 38) else L.darkWood)
		end
		if P.key ~= "red" then
			ceilingBeams(ctx, "x", math.max(2, math.floor(V.D / 3.4)), if P.key == "black" then L.of(30, 28, 26, M.Wood) else L.of(120, 84, 52, M.Wood))
		end
	end
	-- 주방 패스 + 메뉴판
	passDress(ctx, { trim = L.steel, header = "hood", hoodText = if tong then "옛날통닭 · 주방" else "PICK UP · 포장", hoodFg = P.gold, hoodLook = L.of(40, 40, 42, M.Metal), utensil = "basket" })
	menuSignDress(ctx, pl(dark(P.accent, 0.35)), P.gold)
	kioskOverlay(ctx, nm, P.accent, { rgb(200, 122, 44), rgb(170, 40, 24), rgb(222, 150, 66), rgb(236, 168, 30), rgb(200, 30, 36), rgb(250, 196, 40) })
	fryerOverlay(ctx)
	-- 상호작용 벽 장식 먼저 (프롬프트 되는 자리를 차지하게): TV (야구) · 네온
	if V:has("TVBezel") == 0 and V:has("TV") == 0 then
		local tvw = if V.D > 14 then 3.6 else 3.0
		local th = tvw * 9 / 16 + 0.3
		local d = promptWallSpot(ctx, { "left", "right", "back" }, tvw + 0.3, 6.0, 6.0 + th)
		if not d then
			d = wallSpot(ctx, { "left", "right", "back" }, tvw + 0.3, 6.0, 6.0 + th, 0)
		end
		if d then
			tvSet(ctx, d, tvw, baseballChannels(), "TV")
		end
	end
	local nd = promptWallSpot(ctx, { "right", "left", "back" }, 3.6, 6.6, 8.2)
	local nw = 3.2
	if not nd then
		local fw
		nd, fw = wallSpotFit(ctx, { "right", "left", "back" }, { 3.6, 2.6 }, 6.6, 8.2, 0)
		nw = fw - 0.4
	end
	if nd then
		chimaekNeon(ctx, nd, nw, if tong then "옛날통닭" elseif nw < 3 then "치맥" else "치킨 & 맥주", rgb(255, 120, 170), rgb(255, 200, 60))
	end
	-- 바닥 소품: 음료 냉장고 · 생맥주 스테이션 · 셀프 코너 · 포장 박스 랙
	placeFridge(ctx, { header = "시원한 음료 · 주류", headerBg = P.accent, items = CHICKEN_DRINKS, brand = "SHOWCASE" })
	local bw = if V.W > 22 then 3.6 else 3.2
	local bpcf, bwn, bu = floorSpot(ctx, { walls = { "back", "left", "right" }, w = bw, h = 4.8, d = 1.5, pref = { back = "left", left = "back", right = "back" }, front = 1.0 })
	if bpcf and bwn and bu and not wallBusy(K, bwn, bu - 1.4, bu + 1.4, 5.3, 7.5) and #spans(ctx, bwn, 5.3, 7.5, 1.0) > 0 then
		markWall(K, bwn, bu - 1.4, bu + 1.4, 5.3, 7.5)
	else
		bwn = nil
	end
	if bpcf then
		beerStation(ctx, bpcf, bw)
	end
	if bpcf and bwn then
		-- 위 벽: 생맥주 포스터
		local wc = bpcf * CF(0, 0, -0.75 - 0.06)
		poster(ctx, wc * CF(0, 6.4, 0), 2.6, 2.0, {
			bg = rgb(20, 60, 140),
			art = artBeer(-0.6, -0.05, 1.2),
			texts = {
				{ "치킨엔\n생맥주", 0.45, 0.25, 1.3, 0.9, WHITE, F.GothamBlack },
				{ "500cc " .. priceIn(ctx.signs, "생맥주", "4,500") .. "원", 0.45, -0.55, 1.3, 0.34, rgb(255, 214, 60), F.GothamBlack },
			},
		})
	end
	local spcf = if V:has("SelfCabinet") > 0 or V:has("SelfTop") > 0 then nil else floorSpot(ctx, { walls = { "left", "right", "back" }, w = 2.8, h = 4.9, d = 1.3, pref = { left = "back", right = "back", back = 0 }, front = 1.0 })
	if spcf then
		selfBar(ctx, spcf, 2.8)
	end
	if not ctx.gw then
		local rpcf = floorSpot(ctx, { walls = { "right", "left", "back" }, w = 2.3, h = 5.3, d = 1.2, pref = { right = "back", left = "back" }, front = 0.9 })
		if rpcf then
			boxRack(ctx, rpcf, 2.3, nm)
		end
	end
	-- 테이블 위 펜던트
	tablePendants(ctx, { shade = "dome", look = if tong then L.of(44, 96, 66, M.SmoothPlastic, { r = 0.05 }) else (S.pendant and S.pendant.look), lights = 2, dia = 1.2 })
	-- 사진 메뉴 띠 (옆벽 위쪽 라이트박스)
	local sw = math.min(9.6, V.D - 5.5, V.W - 4)
	if sw > 5 then
		local sd = wallSpot(ctx, { "right", "left" }, sw + 0.3, 7.0, 8.95, 0)
		if sd then
			local items = {
				{ "후라이드", pF, artChicken(0, 0.22, 0.62) },
				{ "양념치킨", pY, artYangnyeom(0, 0.22, 0.62) },
				{ "간장치킨", priceIn(ctx.signs, "간장", pY), artGanjang(0, 0.22, 0.62) },
				{ "파닭", "22,000", artPadak(0, 0.22, 0.62) },
				{ "치즈볼", "5,000", artBalls(0, 0.2, 0.55, rgb(240, 196, 80)) },
				{ "감자튀김", "5,000", artFries(0, 0.22, 0.75) },
			}
			local n = math.clamp(math.floor(sw / 1.55), 3, 6)
			while #items > n do
				table.remove(items)
			end
			photoStrip(ctx, sd, sw, 1.8, items, { priceC = P.accent })
		end
	end
	-- 큰 음식 포스터 2 (후라이드 · 양념): 자리가 좁으면 작은 판
	local p1, w1 = wallSpotFit(ctx, { "left", "right" }, { 2.6, 2.0 }, 3.9, 7.0, -2)
	if p1 then
		local k = (w1 - 0.2) / 2.4
		poster(ctx, p1, 2.4 * k, 3.0 * k, {
			bg = P.accent,
			frame = L.blackMetal,
			glass = true,
			art = artChicken(0, -0.1 * k, 1.25 * k),
			texts = {
				{ "바삭한", 0, 1.05 * k, 1.6 * k, 0.36 * k, WHITE, F.GothamBold },
				{ "후라이드", 0, 0.68 * k, 2.0 * k, 0.5 * k, P.gold, F.GothamBlack },
				{ pF .. "원", 0, -1.05 * k, 1.6 * k, 0.42 * k, WHITE, F.GothamBlack },
			},
		})
	end
	local p2, w2 = wallSpotFit(ctx, { "right", "left", "back" }, { 2.6, 2.0 }, 3.9, 7.0, 2)
	if p2 then
		local k = (w2 - 0.2) / 2.4
		poster(ctx, p2, 2.4 * k, 3.0 * k, {
			bg = rgb(250, 236, 200),
			frame = L.blackMetal,
			glass = true,
			art = artYangnyeom(0, -0.1 * k, 1.25 * k),
			texts = {
				{ "달콤 매콤", 0, 1.05 * k, 1.7 * k, 0.34 * k, rgb(120, 30, 20), F.GothamBold },
				{ "양념치킨", 0, 0.68 * k, 2.0 * k, 0.5 * k, rgb(190, 30, 24), F.GothamBlack },
				{ pY .. "원", 0, -1.05 * k, 1.6 * k, 0.42 * k, rgb(60, 30, 20), F.GothamBlack },
			},
		})
	end
	-- 유머 문구 포스터 (치킨집 단골 문구)
	local p3 = wallSpot(ctx, { "left", "right", "back" }, 2.2, 4.0, 6.2, -5)
	if p3 then
		poster(ctx, p3, 2.0, 1.9, {
			bg = P.gold,
			frame = false,
			texts = (function()
				local sl = ({
					{ "치킨은 살 안 쪄요", "살은 내가 쪄요", "오늘도 1인 1닭" },
					{ "치킨 먹을 이유?", "오늘이니까!", "치맥은 국룰" },
					{ "치킨은", "언제나 옳다", "반반 무 많이" },
					{ "야구 볼 땐", "치킨에 맥주", "롯데 화이팅!" },
				})[ctx.rand(4)]
				return {
					{ sl[1], 0, 0.42, 1.8, 0.36, rgb(40, 24, 10), F.GothamBlack },
					{ sl[2], 0, 0.0, 1.8, 0.36, rgb(40, 24, 10), F.GothamBlack },
					{ sl[3], 0, -0.5, 1.6, 0.3, P.accent, F.GothamBold },
				}
			end)(),
		})
	end
	-- 메뉴 사진 줄 (작은 액자 3: 후라이드 · 양념 · 반반)
	local mrow = wallSpot(ctx, { "right", "left", "back" }, 4.6, 4.2, 5.8, 4)
	if mrow then
		local items = { { "후라이드", pF, artChicken }, { "양념", pY, artYangnyeom }, { "반반", pB, nil } }
		for i, it in items do
			local c = mrow * CF((i - 2) * 1.5, 0, 0)
			local a = it[3] and (it[3] :: any)(0, 0.05, 0.62) or nil
			if not a then
				a = artChicken(-0.25, 0.05, 0.5)
				for _, q in artYangnyeom(0.28, 0.05, 0.5) do
					table.insert(a, q)
				end
			end
			poster(ctx, c, 1.36, 1.5, {
				bg = rgb(250, 248, 242),
				frame = L.walnut,
				border = 0.06,
				art = a,
				texts = { { it[1] .. "  " .. it[2], 0, -0.52, 1.1, 0.24, rgb(40, 30, 20), F.GothamBlack } },
			})
		end
	end
	infoSet(ctx, {
		origin = { "닭고기 : 국내산", "쌀(치킨무 제외) : 국내산", "배추김치 : 국내산", "치킨무(무) : 국내산", "감자 : 미국산" },
		hours = if has(ctx.signs, "01:00") then "영업시간\n11:00 - 01:00" else "영업시간\n16:00 - 02:00",
		ssid = string.upper(string.gsub(nm, "%s", "")) .. "_5G",
		pw = "chicken1234",
		stickers = {
			{ "19세 미만\n주류 판매 금지", rgb(200, 30, 36) },
			{ "카드 · 페이\n결제 가능", rgb(40, 90, 200) },
			{ "포장 2,000원\n할인", rgb(240, 160, 30), rgb(40, 24, 10) },
		},
		originPrefer = -3,
	})
	-- 배달앱 스티커 (입구 쪽 옆벽)
	local dl = wallSpot(ctx, { "left", "right" }, 2.6, 3.9, 4.6, if V.walls.left then V.walls.left.a + 2 else 0)
	if dl then
		stickerRow(ctx, dl, {
			{ "배달의민족", rgb(42, 193, 188) },
			{ "쿠팡이츠", rgb(30, 130, 230) },
			{ "요기요", rgb(250, 10, 80) },
		}, 0.78)
	end
end

-- 버거 · 서브웨이 · 타코 ----------------------------------------------------------------------------
local function burger3D(K: any, base: CFrame, s: number)
	K:disc("FfBurgerBunB", 1.0 * s, 0.22 * s, base * CF(0, 0.11 * s, 0), L.of(206, 136, 60))
	K:disc("FfBurgerPatty", 1.06 * s, 0.22 * s, base * CF(0, 0.33 * s, 0), L.of(86, 50, 30))
	K:box("FfBurgerCheese", V3(1.0 * s, 0.05 * s, 1.0 * s), base * CF(0, 0.46 * s, 0) * ANG(0, PI / 4, 0), L.of(250, 196, 40))
	K:disc("FfBurgerTomato", 0.92 * s, 0.08 * s, base * CF(0, 0.52 * s, 0), L.of(210, 50, 40))
	K:disc("FfBurgerLettuce", 1.1 * s, 0.06 * s, base * CF(0, 0.58 * s, 0), L.of(100, 180, 60, M.Grass))
	K:ell("FfBurgerBunT", V3(1.0 * s, 0.62 * s, 1.0 * s), base * CF(0, 0.62 * s, 0), L.of(214, 140, 60))
	K:box("FfBurgerBunCut", V3(1.02 * s, 0.31 * s, 1.02 * s), base * CF(0, 0.47 * s, 0), { c = rgb(0, 0, 0), m = M.SmoothPlastic, t = 1 })
	if s > 0.5 then
		for i = 0, 5 do
			local a = i * 1.1
			K:ell("FfSesame", V3(0.06 * s, 0.03 * s, 0.1 * s), base * CF(math.cos(a) * 0.22 * s, 0.9 * s, math.sin(a) * 0.22 * s) * ANG(0, a, 0.5), L.of(250, 240, 210))
		end
	end
end

-- 음료 셀프바 (탄산 디스펜서 + 컵 · 뚜껑 · 빨대)
local function sodaStation(ctx: any, pcf: CFrame, w: number)
	local K = ctx.K
	local P = ctx.pal
	local h, d = 3.3, 1.6
	local top = cabinet(ctx, pcf, w, h, d, L.of(36, 36, 38), L.of(200, 204, 208, M.Metal, { r = 0.1 }), { doors = 2 })
	-- 디스펜서 본체
	local mw = math.min(2.2, w - 1.0)
	local m = pcf * CF(-w / 2 + mw / 2 + 0.15, top, -0.15)
	K:box("FfFountain", V3(mw, 2.0, 1.1), m * CF(0, 1.0, 0), L.of(200, 204, 208, M.Metal))
	K:text("FfFountainPanel", mw - 0.1, 0.9, m * CF(0, 1.45, 0.555), "", { bg = rgb(200, 28, 36), glow = 1.1, d = 0.01 })
	local brands = { { "콜라", rgb(200, 28, 36) }, { "제로", rgb(20, 20, 22) }, { "사이다", rgb(40, 150, 70) }, { "환타", rgb(236, 120, 30) } }
	local n = if mw > 1.8 then 4 else 3
	for i = 1, n do
		local x = -mw / 2 + mw * (i - 0.5) / n
		K:text("FfFountainBrand", mw / n - 0.08, 0.36, m * CF(x, 1.5, 0.57), brands[i][1], { fg = WHITE, bg = brands[i][2], font = F.GothamBlack, d = 0.01 })
		K:box("FfFountainLever", V3(0.16, 0.36, 0.1), m * CF(x, 0.8, 0.6), L.of(30, 30, 32))
		K:vcyl("FfFountainNozzle", 0.12, 0.1, m * CF(x, 0.9, 0.45), L.chrome)
	end
	K:box("FfFountainDrip", V3(mw, 0.08, 0.5), m * CF(0, 0.04, 0.6), L.of(60, 62, 66, M.DiamondPlate))
	K:box("FfFountainIce", V3(mw - 0.2, 0.3, 0.06), m * CF(0, 1.95, 0.56), L.of(230, 236, 240, M.Metal))
	-- 컵 · 뚜껑 · 빨대
	local cx = w / 2 - 0.5
	for i, sz in { 0.26, 0.32 } do
		K:vcyl("FfCupTower", 0.9, sz, pcf * CF(cx - 0.2 + (i - 1) * 0.4, top + 0.45, -0.2), L.of(250, 250, 246))
		K:vcyl("FfCupTowerBand", 0.12, sz + 0.01, pcf * CF(cx - 0.2 + (i - 1) * 0.4, top + 0.5, -0.2), pl(P.accent))
	end
	K:box("FfLidBox", V3(0.5, 0.3, 0.4), pcf * CF(cx, top + 0.15, 0.35), L.of(40, 40, 42))
	K:vcyl("FfStrawCup", 0.5, 0.24, pcf * CF(cx - 0.45, top + 0.25, 0.4), L.of(240, 240, 236, M.Glass, { t = 0.3 }))
	if not ctx.low then
		for i = 0, 5 do
			local a = i * 1.05
			K:seg("FfStraw", (pcf * CF(cx - 0.45 + math.cos(a) * 0.05, top + 0.2, 0.4 + math.sin(a) * 0.05)).Position, (pcf * CF(cx - 0.45 + math.cos(a) * 0.12, top + 0.95, 0.4 + math.sin(a) * 0.12)).Position, 0.03, pl(if i % 2 == 0 then rgb(240, 240, 240) else P.accent))
		end
	end
	local wc = pcf * CF(0, 0, -d / 2 - 0.06)
	K:text("FfSodaSign", math.min(w - 0.3, 2.6), 0.5, wc * CF(0, top + 2.5, 0), "음료 리필 셀프 · REFILL", { fg = WHITE, bg = rgb(26, 26, 28), font = F.GothamBlack, d = 0.04 })
end

-- 소스 · 냅킨 스테이션 (펌프 소스 + 냅킨 + 포크 · 물티슈 + 반납대)
local function sauceStation(ctx: any, pcf: CFrame, w: number)
	local K = ctx.K
	local P = ctx.pal
	local h, d = 3.2, 1.3
	local top = cabinet(ctx, pcf, w, h, d, pl(P.wall2), L.of(36, 36, 38, M.Granite), { doors = 2 })
	local sauces = { { "케첩", rgb(196, 30, 30) }, { "머스터드", rgb(240, 190, 30) }, { "마요", rgb(246, 242, 230) }, { "핫소스", rgb(150, 30, 20) } }
	local n = if w > 2.4 then 4 else 3
	for i = 1, n do
		local b = pcf * CF(-w / 2 + 0.4 + (i - 1) * 0.5, top, -0.25)
		local c = sauces[i][2]
		K:vcyl("FfPumpJar", 0.62, 0.36, b * CF(0, 0.31, 0), L.of(c.R * 255, c.G * 255, c.B * 255, M.Plastic))
		K:vcyl("FfPumpHead", 0.22, 0.12, b * CF(0, 0.73, 0), L.of(40, 40, 42))
		K:box("FfPumpNozzle", V3(0.06, 0.06, 0.24), b * CF(0, 0.8, 0.12), L.of(40, 40, 42))
		if not ctx.low then
			K:text("FfPumpLabel", 0.32, 0.12, b * CF(0, 0.34, 0.185), sauces[i][1], { fg = WHITE, bg = dark(c, 0.3), d = 0.004, font = F.GothamBlack })
		end
	end
	local nb = pcf * CF(w / 2 - 0.5, top, 0.0)
	K:box("FfNapkinDisp", V3(0.55, 0.5, 0.5), nb * CF(0, 0.25, 0), L.steel)
	K:box("FfNapkinPaper", V3(0.4, 0.06, 0.3), nb * CF(0, 0.53, 0.05), L.paper)
	K:vcyl("FfForkCup", 0.45, 0.24, pcf * CF(w / 2 - 0.5, top + 0.22, 0.45), L.steel)
	-- 아래 반납대 칸 (쟁반 꽂이)
	K:box("FfTrayReturn", V3(w - 0.4, 0.9, 0.1), pcf * CF(0, 1.2, d / 2 - 0.02), L.of(26, 26, 28))
	K:text("FfTrayReturnText", w - 0.6, 0.36, pcf * CF(0, 1.2, d / 2 + 0.035), "식기 · 쟁반 반납", { fg = WHITE, font = F.GothamBlack, d = 0.005 })
end

-- 레트로 주크박스 (곡 바꾸기)
local function jukebox(ctx: any, pcf: CFrame)
	local K = ctx.K
	local P = ctx.pal
	local w, h, d = 2.2, 4.6, 1.3
	K:box("FfJukeBody", V3(w, h - 1.1, d), pcf * CF(0, (h - 1.1) / 2, 0), L.of(120, 40, 30, M.Wood))
	K:cyl("FfJukeArch", d, w, pcf * CF(0, h - 1.1, 0) * ANG(0, PI / 2, 0), L.of(120, 40, 30, M.Wood))
	-- 무지개 아치 네온
	local arcs = { rgb(255, 70, 90), rgb(255, 196, 48), rgb(80, 220, 120), rgb(70, 160, 255) }
	for i, c in arcs do
		K:ring("FfJukeNeon", pcf * CF(0, h - 1.1, d / 2 + 0.02), w / 2 - 0.12 - (i - 1) * 0.14, 0.07, if ctx.low then 5 else 9, neon(c), 0, PI)
	end
	K:plate("FfJukeGrille", w - 0.5, 1.2, 0.04, pcf * CF(0, 1.0, d / 2), L.of(190, 160, 80, M.DiamondPlate))
	local scr, lab = K:text("FfJukeScreen", w - 0.6, 0.9, pcf * CF(0, 2.5, d / 2 + 0.005), "♪ Fly Me To The Moon", { fg = rgb(255, 230, 160), bg = rgb(30, 20, 16), glow = 1.5, font = F.GothamBold, d = 0.02 })
	for i = -2, 2 do
		K:box("FfJukeButton", V3(0.2, 0.12, 0.08), pcf * CF(i * 0.3, 1.85, d / 2 + 0.03), L.of(250, 240, 220))
	end
	K:box("FfJukeFoot", V3(w + 0.1, 0.12, d + 0.1), pcf * CF(0, 0.06, 0), L.chrome)
	local songs = { "♪ Fly Me To The Moon", "♪ 부산 갈매기", "♪ Johnny B. Goode", "♪ 해운대 연가", "♪ Don't Stop Me Now" }
	if scr.Parent then
		local lp = K.cf:PointToObjectSpace(scr.Position)
		if Interact.canPrompt(K, lp) then
			Interact.cycle(K, scr, songs, { object = "주크박스", action = "다음 곡", on = function(_i, s)
				lab.Text = s
			end })
		end
	end
end

-- 메뉴 라이트박스 3칸 (세트 사진 = 색 블록 + 이름 + 가격)
local function burgerLightboxes(ctx: any, dcf: CFrame, w: number, combos: { any })
	local n = #combos
	local pw = (w - 0.2 * (n - 1)) / n
	local ph = 2.0
	local k = math.min(1, pw / 2.3)
	for i, cb in combos do
		local c = dcf * CF(-w / 2 + pw / 2 + (i - 1) * (pw + 0.2), 0, 0)
		local a = artBurger(-0.35 * pw / 2.2, 0.05, 0.85 * k)
		for _, q in artFries(0.36 * pw / 2.2, 0.0, 0.7 * k) do
			table.insert(a, q)
		end
		for _, q in artCola(0.74 * pw / 2.2, 0.02, 0.6 * k) do
			table.insert(a, q)
		end
		poster(ctx, c, pw, ph, {
			bg = cb.bg or rgb(26, 26, 28),
			lit = 1.1,
			frame = L.blackMetal,
			border = 0.06,
			art = a,
			texts = {
				{ cb[1], 0, ph / 2 - 0.33, pw - 0.3, 0.32, WHITE, F.GothamBlack },
				{ cb[2], 0, -ph / 2 + 0.3, pw - 0.6, 0.34, ctx.pal.gold, F.GothamBlack },
			},
		})
	end
end

local BURGER_DRINKS = {
	{ rgb(200, 24, 32), "can", rgb(200, 24, 32) },
	{ rgb(20, 20, 22), "can" },
	{ rgb(40, 150, 70), "can" },
	{ rgb(236, 120, 30), "can" },
	{ rgb(60, 24, 20), "pet", rgb(200, 28, 36) },
	{ rgb(200, 230, 240), "pet", rgb(40, 120, 210) },
	{ rgb(250, 210, 60), "bottle", rgb(250, 250, 250) },
}

local function musicChannels(): { any }
	return {
		{ "MV", rgb(110, 30, 140), {
			{ "e", -0.2, -0.05, 0.3, 0.5, rgb(255, 120, 200) },
			{ "e", 0.2, -0.05, 0.3, 0.5, rgb(80, 220, 255) },
			{ "b", 0, -0.42, 1.0, 0.1, rgb(20, 10, 30) },
		}, "MUSIC TOP 10", "♪ 이번 주 1위 · 부산 갈매기 리믹스" },
		{ "스포츠", rgb(30, 100, 46), {
			{ "b", 0, -0.18, 0.34, 0.34, rgb(150, 100, 56), PI / 4 },
			{ "b", 0, 0.38, 1.0, 0.18, rgb(16, 26, 70) },
		}, "롯데 5 : 4 LG   9회초", "사직야구장 LIVE" },
		{ "광고", rgb(200, 30, 36), {
			{ "e", 0, -0.08, 0.36, 0.3, rgb(214, 140, 60) },
			{ "b", 0, -0.14, 0.38, 0.06, rgb(92, 52, 30) },
			{ "b", 0, -0.06, 0.36, 0.03, rgb(100, 180, 60) },
		}, "NEW 더블 스매시 버거", "세트 주문 시 감자튀김 L 업그레이드" },
	}
end

local function burgerBuild(ctx: any)
	local K, V, S = ctx.K, ctx.V, ctx.S
	local P = ctx.pal
	local taco = ctx.sk == "taco"
	local nm = V.name or "BURGER"
	if nm == "SideShop" then
		nm = if taco then "TACO" else "BURGER"
	end
	local pB = priceIn(ctx.signs, "수제버거", "9,800")
	local pFr = priceIn(ctx.signs, "감자튀김", "3,500")
	local pSh = priceIn(ctx.signs, "쉐이크", "5,500")
	if not ctx.gw then
		local lh = if S.lower then S.lower.h else 0.45
		if P.brick then
			upperPaint(ctx, { "left", "right" }, lh + 0.08, L.of(150, 82, 62, M.Brick))
		else
			upperPaint(ctx, { "left", "right" }, lh + 0.08, pl(P.wall, M.Plaster))
		end
		upperPaint(ctx, { "back" }, lh + 0.08, pl(P.wall2, M.Plaster))
		wallBand(ctx, { "left", "right", "back" }, lh + 0.06, 0.14, 0.08, L.black)
	end
	-- 체커 바닥 (다이너)
	if P.checker and not ctx.low then
		local t = 2.0
		local nx, nz = math.floor(V.W / t), math.floor(V.D / t)
		K:free(function()
			K:box("FfCheckerBase", V3(V.W - 0.02, 0.02, V.D - 0.02), CF((V.x0 + V.x1) / 2, 0.01, (V.z0 + V.z1) / 2), L.of(240, 238, 232, M.CeramicTiles))
			local x0 = V.x0 + (V.W - nx * t) / 2
			local z0 = V.z0 + (V.D - nz * t) / 2
			for i = 0, nx - 1 do
				for j = 0, nz - 1 do
					if (i + j) % 2 == 0 then
						K:box("FfChecker", V3(t - 0.03, 0.024, t - 0.03), CF(x0 + (i + 0.5) * t, 0.012, z0 + (j + 0.5) * t), L.of(28, 28, 30, M.CeramicTiles))
					end
				end
			end
		end)
	end
	passDress(ctx, { trim = L.of(30, 30, 32, M.Metal), header = "pickup", hoodText = if taco then "TAQUERÍA · PICK UP" else "PICK UP", hoodFg = P.neonC, hoodLook = L.of(30, 30, 32, M.Metal), utensil = "spatula", lamp = rgb(255, 120, 60) })
	menuSignDress(ctx, L.of(24, 24, 26), P.neonC)
	kioskOverlay(ctx, nm, P.accent, { rgb(214, 140, 60), rgb(92, 52, 30), rgb(250, 196, 40), rgb(210, 30, 36), rgb(90, 170, 60), rgb(250, 204, 70) })
	-- 천장: 노출 덕트 (인더스트리얼 · 벽돌) 또는 에디슨 전구 펜던트
	if not P.checker and not ctx.low then
		local x = V.x1 - 2.2
		local za, zb = V.z0 + 0.8, V.z1 - 5.0
		if zb - za > 4 and Common.ceilFree(K, x, (za + zb) / 2, 0.2) then
			local y = V.H - 1.0
			local ok = true
			for _, r in V.hang do
				if r.max.X > x - 0.8 and r.min.X < x + 0.8 and r.min.Y < y + 0.7 then
					ok = false
				end
			end
			if ok then
				K:seg("FfDuct", V3(x, y, za), V3(x, y, zb), 1.1, L.of(176, 180, 184, M.Metal))
				local nseg = math.floor((zb - za) / 2.0)
				for i = 1, nseg do
					local z = za + i * (zb - za) / (nseg + 1)
					K:ring("FfDuctSeam", CFrame.lookAt(V3(x, y, z), V3(x, y, z + 1)), 0.56, 0.05, 8, L.of(150, 154, 158, M.Metal))
					K:seg("FfDuctHanger", V3(x, y + 0.55, z), V3(x, V.H, z), 0.05, L.blackMetal)
				end
				for i = 1, 2 do
					local z = za + i * (zb - za) / 3
					K:box("FfDuctGrille", V3(0.7, 0.06, 0.5), CF(x - 0.2, y - 0.56, z), L.of(130, 134, 138, M.DiamondPlate))
				end
			end
		end
	end
	tablePendants(ctx, { shade = "bulb", lights = 1, dia = 0.8, pair = true })
	-- 바닥 소품
	placeFridge(ctx, { header = "COLD DRINKS · 음료", headerBg = rgb(26, 26, 28), headerFg = P.neonC, items = BURGER_DRINKS, brand = "SHOWCASE" })
	local sw = 3.4
	local sp = floorSpot(ctx, { walls = { "back", "left", "right" }, w = sw, h = 5.6, d = 1.6, pref = { back = "left", left = "back", right = "back" }, front = 1.0 })
	if sp then
		sodaStation(ctx, sp, sw)
	end
	local sp2 = floorSpot(ctx, { walls = { "left", "right", "back" }, w = 2.6, h = 4.4, d = 1.3, pref = { left = "back", right = "back" }, front = 1.0 })
	if sp2 then
		sauceStation(ctx, sp2, 2.6)
	end
	if P.checker or taco then
		local jp = floorSpot(ctx, { walls = { "right", "left", "back" }, w = 2.2, h = 4.6, d = 1.3, pref = { right = "front", left = "front" }, prompt = true, front = 1.0 })
		if jp then
			jukebox(ctx, jp)
		end
	end
	-- 벽: 메뉴 라이트박스 (세트 3칸) · 네온 · 포스터 · TV
	local combos = if taco then {
		{ "비프 타코 세트", "10,900" },
		{ "치킨 부리또 세트", "11,900" },
		{ "나초 & 살사", "7,500" },
	} else {
		{ "클래식 치즈버거 세트", "12,900" },
		{ "더블 스매시 세트", "15,900" },
		{ "베이컨 BBQ 세트", "14,500" },
	}
	local lbw = math.min(7.2, V.D - 6)
	local lb = wallSpot(ctx, { "left", "right" }, lbw, 5.9, 8.1, -1)
	if lb then
		burgerLightboxes(ctx, lb, lbw, combos)
	end
	local nd = promptWallSpot(ctx, { "right", "left", "back" }, 4.0, 5.2, 7.6)
	if not nd then
		nd = wallSpot(ctx, { "right", "left", "back" }, 4.0, 5.2, 7.6, 0)
	end
	if nd then
		local s = 0.7
		local x0 = -1.45
		local shapes = {
			{ x0 - s * 0.6, s * 0.1, x0 + s * 0.6, s * 0.1, rgb(255, 196, 48) },
			{ x0 - s * 0.6, s * 0.1, x0 - s * 0.3, s * 0.6, rgb(255, 196, 48) },
			{ x0 - s * 0.3, s * 0.6, x0 + s * 0.3, s * 0.6, rgb(255, 196, 48) },
			{ x0 + s * 0.3, s * 0.6, x0 + s * 0.6, s * 0.1, rgb(255, 196, 48) },
			{ x0 - s * 0.65, -s * 0.12, x0 + s * 0.65, -s * 0.12, rgb(80, 230, 120) },
			{ x0 - s * 0.6, -s * 0.34, x0 + s * 0.6, -s * 0.34, rgb(255, 90, 60) },
			{ x0 - s * 0.6, -s * 0.56, x0 + s * 0.6, -s * 0.56, rgb(255, 196, 48) },
		}
		local rec = neonSign(ctx, nd * CF(0.55, 0, 0), 2.4, 1.3, if taco then "TACO\nTIME" else "BURGER\nTIME", P.neonC, { shapes = {}, object = "네온사인" })
		-- 버거 그림 네온관 (왼쪽)
		for _, sg in shapes do
			local p = K:seg("FfNeonTube", (nd * CF(sg[1], sg[2], 0.1)).Position, (nd * CF(sg[3], sg[4], 0.1)).Position, 0.08, neon(sg[5]), 0.07)
			if p then
				table.insert(rec.tubes, p)
			end
		end
	end
	local p1 = wallSpot(ctx, { "right", "left" }, 2.4, 3.9, 6.9, 2)
	if p1 then
		poster(ctx, p1, 2.2, 2.9, {
			bg = rgb(250, 240, 220),
			frame = L.blackMetal,
			glass = true,
			art = if taco then artTaco(0, 0.0, 1.3) else artBurger(0, 0.05, 1.3),
			texts = {
				{ if taco then "AUTHENTIC" else "100% BEEF", 0, 1.0, 1.8, 0.4, P.accent, F.GothamBlack },
				{ if taco then "매일 굽는 또르띠야" else "매일 아침 직접 만드는 수제 패티", 0, -0.82, 1.9, 0.26, rgb(40, 30, 20), F.GothamBold },
				{ if taco then "비프 타코 4,900" else "수제버거 " .. pB, 0, -1.12, 1.6, 0.3, rgb(40, 30, 20), F.GothamBlack },
			},
		})
	end
	local p2 = wallSpot(ctx, { "left", "right", "back" }, 2.4, 3.9, 6.9, -4)
	if p2 then
		local a = artFries(-0.45, 0.1, 1.2)
		for _, q in artCola(0.55, 0.05, 1.0) do
			table.insert(a, q)
		end
		poster(ctx, p2, 2.2, 2.9, {
			bg = rgb(28, 28, 30),
			frame = L.of(200, 200, 204, M.Metal),
			glass = true,
			art = a,
			texts = {
				{ "FRIES & SHAKE", 0, 1.02, 1.9, 0.34, P.gold, F.GothamBlack },
				{ "감자튀김 " .. pFr .. "  ·  쉐이크 " .. pSh, 0, -1.05, 1.95, 0.26, WHITE, F.GothamBold },
			},
		})
	end
	if V:has("TV") == 0 then
		local d = wallSpot(ctx, { "left", "right", "back" }, 3.4, 6.2, 8.3, 3)
		if d then
			tvSet(ctx, d, 3.0, musicChannels(), "TV")
		end
	end
	-- 3D 버거 조형 (벽 선반 위)
	if not taco then
		local sh = wallSpot(ctx, { "right", "left", "back" }, 2.2, 6.9, 8.4, -3)
		if sh then
			local at = Props.shelf(K, sh * CF(0, -0.6, 0), 2.0, { depth = 1.1, look = L.walnut })
			burger3D(K, at * CF(0, 0, -0.05), 0.95)
		end
	end
	infoSet(ctx, {
		origin = if taco then { "소고기 : 호주산", "닭고기 : 국내산", "돼지고기 : 국내산", "쌀 : 국내산" } else { "소고기(패티) : 호주산", "돼지고기(베이컨) : 미국산", "닭고기 : 국내산", "감자 : 미국산" },
		hours = if has(ctx.signs, "24 HOURS") then "OPEN 24 HOURS\n연중무휴" else "영업시간\n10:30 - 22:00",
		ssid = "BURGER_FREE",
		pw = "burger2026",
		stickers = {
			{ "키오스크\n주문", rgb(30, 30, 32) },
			{ "카드 · 페이\n결제", rgb(40, 90, 200) },
			{ "포장\n가능", rgb(220, 60, 40) },
		},
	})
end

-- SUBWAY ---------------------------------------------------------------------------------------------
-- 앞 카운터 위 재료 칸 (맵 Ingredient 납작 상자 자리 그대로 스테인리스 1/6 팬 + 재료 덩어리)
local INGREDIENTS = {
	{ rgb(110, 180, 60), "leaf" }, -- 양상추
	{ rgb(210, 50, 40), "slice" }, -- 토마토
	{ rgb(60, 130, 50), "slice" }, -- 오이
	{ rgb(236, 230, 220), "ring" }, -- 양파
	{ rgb(250, 200, 40), "slice" }, -- 피망(노랑)
	{ rgb(40, 40, 30), "dot" }, -- 올리브
	{ rgb(140, 170, 50), "ring" }, -- 할라피뇨
	{ rgb(120, 150, 60), "slice" }, -- 피클
	{ rgb(250, 220, 120), "cube" }, -- 치즈
	{ rgb(232, 150, 150), "slice" }, -- 햄
	{ rgb(240, 236, 220), "cube" }, -- 에그마요
}

local function veggieWells(ctx: any)
	local K, V = ctx.K, ctx.V
	local list = V.byName.Ingredient or {}
	if #list == 0 then
		return
	end
	local rnd = ctx.rand
	K:free(function()
		for i, r in list do
			local ing = INGREDIENTS[(i - 1) % #INGREDIENTS + 1]
			local c: Color3 = ing[1]
			local w, d = r.size.X, r.size.Z
			local base = CF(r.c.X, r.min.Y, r.c.Z)
			-- 스테인리스 팬 (테두리) + 속 재료
			K:box("FfWellRim", V3(w, 0.1, d), base * CF(0, 0.05, 0), L.of(200, 204, 208, M.Metal, { r = 0.12 }))
			K:box("FfWellFill", V3(w - 0.08, 0.06, d - 0.08), base * CF(0, 0.09, 0), pl(c))
			if not ctx.low then
				local n = if ctx.high then 4 else 2
				for k = 1, n do
					local x = (rnd() - 0.5) * (w - 0.3)
					local z = (rnd() - 0.5) * (d - 0.3)
					local p = base * CF(x, 0.12, z) * ANG(0, rnd() * PI, 0)
					local lc = if (k % 2) == 0 then light(c, 0.15) else dark(c, 0.12)
					if ing[2] == "leaf" then
						K:ell("FfIng", V3(0.3, 0.06, 0.22), p, { c = lc, m = M.Grass })
					elseif ing[2] == "slice" then
						K:disc("FfIng", 0.22, 0.03, p, pl(lc))
					elseif ing[2] == "ring" then
						K:disc("FfIng", 0.2, 0.025, p, pl(lc))
					elseif ing[2] == "dot" then
						K:ball("FfIng", 0.1, p, pl(lc))
					else
						K:box("FfIng", V3(0.1, 0.06, 0.1), p, pl(lc))
					end
				end
			end
			Scan.hide(K.hidden, r.part)
		end
		-- 재료 칸 사이 스테인리스 레일 (앞뒤)
		local mn, mx = list[1].min, list[1].max
		for _, r in list do
			mn = mn:Min(r.min)
			mx = mx:Max(r.max)
		end
		K:box("FfWellRailF", V3(mx.X - mn.X + 0.1, 0.05, 0.06), CF((mn.X + mx.X) / 2, mn.Y + 0.12, mx.Z + 0.03), L.chrome)
		K:box("FfWellRailB", V3(mx.X - mn.X + 0.1, 0.05, 0.06), CF((mn.X + mx.X) / 2, mn.Y + 0.12, mn.Z - 0.03), L.chrome)
	end)
end

local function sneezeGuard(ctx: any)
	local K, V = ctx.K, ctx.V
	for _, r in V.byName.SneezeGuard or {} do
		-- 가드가 올라간 카운터 (뒷모서리 = 직원 쪽)
		local g = nil
		for _, c in V.counters do
			if r.c.X > c.min.X - 0.5 and r.c.X < c.max.X + 0.5 and r.c.Z > c.min.Z - 0.5 and r.c.Z < c.max.Z + 0.5 then
				g = c
			end
		end
		local topY = if g then g.y else r.min.Y - 1.3
		local zb = if g then g.min.Z + 0.12 else r.min.Z
		local zf = r.max.Z
		local w = r.size.X
		local yTop = r.max.Y + 0.25
		K:free(function()
			-- 직원 쪽 기둥 + 위 선반 (조명) + 손님 쪽으로 기울어 내려오는 유리
			local n = math.max(2, math.floor(w / 3.2))
			for i = 0, n do
				local x = r.min.X + w * i / n
				K:vcyl("FfGuardPost", yTop - topY, 0.08, CF(x, topY + (yTop - topY) / 2, zb), L.chrome)
				K:bar("FfGuardArm", V3(x, yTop, zb), V3(x, yTop, zb + 0.9), 0.05, 0.05, L.chrome)
			end
			K:box("FfGuardShelf", V3(w + 0.1, 0.05, 1.0), CF(r.c.X, yTop + 0.03, zb + 0.5), { c = rgb(220, 236, 240), m = M.Glass, t = 0.55, r = 0.2 })
			K:box("FfGuardLED", V3(w - 0.2, 0.03, 0.08), CF(r.c.X, yTop - 0.02, zb + 0.85), neon(rgb(255, 244, 220)))
			local a = V3(r.c.X, yTop, zb + 0.95)
			local b = V3(r.c.X, math.max(topY + 0.95, r.min.Y - 0.25), zf)
			local mid = (a + b) / 2
			local dir = (b - a).Unit
			local len = (b - a).Magnitude
			local cf = CFrame.lookAt(mid, mid + dir) 
			K:box("FfGuardGlass", V3(w, 0.04, len), cf * ANG(PI / 2, 0, 0) * ANG(-PI / 2, 0, 0), { c = rgb(220, 236, 240), m = M.Glass, t = 0.72, r = 0.18 })
			K:box("FfGuardEdge", V3(w, 0.05, 0.05), CF(b), L.chrome)
		end)
		Scan.hide(K.hidden, r.part)
	end
end

-- 칩 진열대 (철제 랙 + 봉지)
local function chipsRack(ctx: any, pcf: CFrame)
	local K = ctx.K
	local w, h, d = 1.6, 4.6, 1.0
	K:box("FfChipBase", V3(w, 0.2, d), pcf * CF(0, 0.1, 0), L.of(0, 120, 56))
	K:vcyl("FfChipPost", h, 0.1, pcf * CF(-w / 2 + 0.1, h / 2, -d / 2 + 0.1), L.blackMetal)
	K:vcyl("FfChipPost", h, 0.1, pcf * CF(w / 2 - 0.1, h / 2, -d / 2 + 0.1), L.blackMetal)
	K:text("FfChipHeader", w, 0.5, pcf * CF(0, h - 0.25, -d / 2 + 0.16), "CHIPS · 쿠키", { fg = WHITE, bg = rgb(0, 120, 56), font = F.GothamBlack, d = 0.04 })
	local cols = { rgb(250, 200, 40), rgb(200, 30, 36), rgb(40, 90, 200), rgb(30, 150, 70), rgb(120, 40, 140) }
	for row = 0, 3 do
		local y = 0.6 + row * 0.95
		K:box("FfChipBar", V3(w - 0.1, 0.05, 0.05), pcf * CF(0, y + 0.72, -d / 2 + 0.16), L.blackMetal)
		for i = 0, 2 do
			local c = cols[(row * 3 + i) % #cols + 1]
			K:ell("FfChipBag", V3(0.42, 0.66, 0.2), pcf * CF(-0.5 + i * 0.5, y + 0.36, -d / 2 + 0.32), L.of(c.R * 255, c.G * 255, c.B * 255, M.Foil))
		end
	end
end

local function subwayBuild(ctx: any)
	local K, V = ctx.K, ctx.V
	local P = ctx.pal
	local g = P.green
	-- 벽: 흰 위쪽 + 초록 포인트 벽 (오른쪽 벽) + 노란 화살표 띠
	upperPaint(ctx, { "back" }, 3.5, pl(rgb(244, 240, 230), M.Plaster))
	upperPaint(ctx, { "left" }, 3.5, pl(rgb(244, 240, 230), M.Plaster))
	upperPaint(ctx, { "right" }, 3.5, pl(g, M.Plaster))
	wallBand(ctx, { "left", "back" }, 3.52, 0.16, 0.05, pl(P.accent))
	-- 카운터: 재료 칸 · 재채기 가드 · 뒤 오븐
	veggieWells(ctx)
	sneezeGuard(ctx)
	for _, nm in { "ToasterOven" } do
		for _, r in V.byName[nm] or {} do
			K:free(function()
				local c = CF(r.c.X, r.min.Y, r.c.Z)
				local w, h, d = r.size.X, r.size.Y, r.size.Z
				local face = (r.max.Z > -8) -- 문은 카운터 앞쪽 (+Z)
				K:box("FfOvenBody", V3(w, h, d), c * CF(0, h / 2, 0), L.of(190, 194, 198, M.Metal, { r = 0.08 }))
				K:box("FfOvenWindow", V3(w * 0.66, h * 0.42, 0.03), c * CF(-w * 0.1, h * 0.5, d / 2 + 0.015), { c = rgb(40, 30, 24), m = M.Glass, t = 0.25 })
				K:box("FfOvenGlow", V3(w * 0.6, h * 0.08, 0.02), c * CF(-w * 0.1, h * 0.62, d / 2 + 0.005), neon(rgb(255, 140, 60)))
				K:box("FfOvenPanel", V3(w * 0.2, h * 0.7, 0.03), c * CF(w * 0.36, h * 0.5, d / 2 + 0.015), L.of(30, 30, 32))
				K:box("FfOvenDisplay", V3(w * 0.14, h * 0.12, 0.02), c * CF(w * 0.36, h * 0.72, d / 2 + 0.035), neon(rgb(80, 220, 120)))
				K:box("FfOvenHandle", V3(w * 0.6, 0.06, 0.08), c * CF(-w * 0.1, h * 0.8, d / 2 + 0.05), L.chrome)
				K:box("FfOvenFoot", V3(w - 0.1, 0.06, d - 0.1), c * CF(0, 0.03, 0), L.black)
				local _ = face
			end)
			Scan.hide(K.hidden, r.part)
		end
	end
	for _, r in V.byName.BreadCabinet or {} do
		K:free(function()
			local c = CF(r.c.X, r.min.Y, r.c.Z)
			local w, h, d = r.size.X, r.size.Y, r.size.Z
			-- 빵 발효기: 스테인리스 틀 + 유리문 + 안쪽 따뜻한 불빛 (빵은 맵 Loaf 그대로)
			K:box("FfProoferBack", V3(w, h, 0.08), c * CF(0, h / 2, -d / 2 + 0.04), L.of(190, 194, 198, M.Metal))
			K:box("FfProoferSide", V3(0.08, h, d), c * CF(-w / 2 + 0.04, h / 2, 0), L.of(190, 194, 198, M.Metal))
			K:box("FfProoferSide", V3(0.08, h, d), c * CF(w / 2 - 0.04, h / 2, 0), L.of(190, 194, 198, M.Metal))
			K:box("FfProoferTop", V3(w, 0.1, d), c * CF(0, h - 0.05, 0), L.of(190, 194, 198, M.Metal))
			K:box("FfProoferBottom", V3(w, 0.08, d), c * CF(0, 0.04, 0), L.of(190, 194, 198, M.Metal))
			K:box("FfProoferShelf", V3(w - 0.16, 0.04, d - 0.1), c * CF(0, h * 0.4, 0), L.of(200, 204, 208, M.Metal))
			K:box("FfProoferGlow", V3(w - 0.2, 0.04, 0.06), c * CF(0, h - 0.14, d / 2 - 0.12), neon(rgb(255, 200, 140)))
			K:box("FfProoferGlass", V3(w - 0.12, h - 0.2, 0.03), c * CF(0, h / 2, d / 2 - 0.02), { c = rgb(230, 220, 200), m = M.Glass, t = 0.75, r = 0.15 })
			K:text("FfProoferLabel", w * 0.6, 0.22, c * CF(0, h - 0.3, d / 2 + 0.0), "FRESH BAKED", { fg = rgb(0, 120, 56), font = F.GothamBlack, d = 0.005 })
		end)
		Scan.hide(K.hidden, r.part)
	end
	-- 뒷벽 메뉴판 3개 (Sign_) 뒤 액자 + 아래 노란 LED
	menuSignDress(ctx, L.of(30, 34, 32), P.accent)
	local tvd = promptWallSpot(ctx, { "left", "right", "back" }, 3.4, 6.2, 8.3)
	if not tvd then
		tvd = wallSpot(ctx, { "left", "right" }, 3.4, 6.2, 8.3, 6)
	end
	if tvd then
		tvSet(ctx, tvd, 3.0, {
			{ "메뉴", g, { { "e", -0.18, -0.05, 0.6, 0.3, rgb(214, 160, 92) }, { "e", -0.18, 0.0, 0.58, 0.08, rgb(100, 180, 60) } }, "오늘의 써브  ·  에그마요 5,900", "Sub of the Day" },
			{ "쿠키", P.accent, { { "e", -0.2, -0.05, 0.26, 0.4, rgb(150, 100, 60) }, { "e", 0.18, -0.05, 0.26, 0.4, rgb(110, 70, 40) } }, "갓 구운 쿠키 3개 4,500", "초코칩 · 화이트 마카다미아" },
		}, "메뉴 화면")
	end
	-- 초록 벽 큰 글자 + 노란 화살표
	local sg = wallSpot(ctx, { "right", "left" }, 7.0, 7.0, 9.6, 0)
	if sg then
		K:text("FfSubLogo", 6.0, 1.5, sg * CF(0, 0.45, 0.02), "SUBWAY", { fg = WHITE, font = F.GothamBlack, d = 0.04 })
		K:text("FfSubSlogan", 5.0, 0.5, sg * CF(0, -0.75, 0.02), "신선한 재료를 매일 아침 준비합니다", { fg = P.accent, font = F.GothamBold, d = 0.02 })
		for _, sx in { -1, 1 } do
			K:plate("FfSubArrow", 0.9, 0.16, 0.04, sg * CF(sx * 3.2, 0.45, 0.02) * ANG(0, 0, sx * 0.5), pl(P.accent))
		end
	end
	-- 주문 방법 5단계 포스터 (써브웨이 대표 안내)
	local st = wallSpot(ctx, { "left", "right" }, 5.4, 4.2, 7.0, 0)
	if st then
		local steps = { { "1", "빵 선택" }, { "2", "메인 재료" }, { "3", "치즈 · 토스팅" }, { "4", "야채 선택" }, { "5", "소스 선택" } }
		K:plate("FfStepsBack", 5.3, 2.6, 0.04, st, pl(rgb(250, 248, 240)))
		K:text("FfStepsTitle", 4.6, 0.46, st * CF(0, 0.95, 0.045), "주문 방법  HOW TO ORDER", { fg = g, font = F.GothamBlack, d = 0.01 })
		for i, s in steps do
			local x = -2.1 + (i - 1) * 1.05
			K:disc("FfStepDot", 0.62, 0.04, st * CF(x, 0.15, 0.06) * ANG(PI / 2, 0, 0), pl(if i % 2 == 1 then g else P.accent))
			K:text("FfStepNum", 0.4, 0.4, st * CF(x, 0.15, 0.085), s[1], { fg = WHITE, font = F.GothamBlack, d = 0.005 })
			K:text("FfStepText", 0.98, 0.3, st * CF(x, -0.45, 0.045), s[2], { fg = rgb(30, 30, 30), font = F.GothamBold, d = 0.005 })
			if i < 5 and not ctx.low then
				K:plate("FfStepArrow", 0.3, 0.06, 0.02, st * CF(x + 0.52, 0.15, 0.05), pl(P.accent))
			end
		end
		K:text("FfStepsFoot", 4.8, 0.3, st * CF(0, -0.98, 0.045), "15cm " .. priceIn(ctx.signs, "15cm", "6,900") .. "  ·  30cm " .. priceIn(ctx.signs, "30cm", "11,900"), { fg = rgb(60, 60, 60), font = F.GothamBold, d = 0.01 })
	end
	-- 샌드위치 사진 포스터 2
	for i, pr in { { "이탈리안 비엠티", "15cm 7,400" }, { "로티세리 바비큐 치킨", "15cm 7,900" } } do
		local pd = wallSpot(ctx, { "left", "right", "back" }, 2.6, 3.9, 6.6, -4 + (i - 1) * 7)
		if pd then
			poster(ctx, pd, 2.4, 2.4, {
				bg = if i == 1 then rgb(250, 246, 236) else rgb(0, 120, 56),
				frame = L.of(220, 220, 220, M.Metal),
				glass = true,
				art = artSandwich(0, 0.05, 1.25),
				texts = {
					{ pr[1], 0, 0.85, 2.0, 0.34, if i == 1 then g else WHITE, F.GothamBlack },
					{ pr[2], 0, -0.82, 1.6, 0.3, P.accent, F.GothamBlack },
				},
			})
		end
	end
	-- 칩 랙 (계산대 근처 손님 쪽) + 음료 냉장고는 맵 것
	local cp = floorSpot(ctx, { walls = { "right", "left", "back" }, w = 1.6, h = 4.6, d = 1.0, pref = { right = "back", left = "back" }, front = 0.8 })
	if cp then
		chipsRack(ctx, cp)
	end
	placeFridge(ctx, { walls = { "right", "left", "back" }, pref = { right = "back" }, header = "DRINKS", headerBg = g, items = BURGER_DRINKS })
	local sp = floorSpot(ctx, { walls = { "left", "right", "back" }, w = 3.4, h = 5.6, d = 1.6, pref = { left = "front", right = "front" }, front = 1.0 })
	if sp then
		sodaStation(ctx, sp, 3.4)
	end
	infoSet(ctx, {
		origin = { "닭고기 : 국내산", "돼지고기(햄 · 베이컨) : 미국산", "소고기 : 호주산", "계란 : 국내산" },
		hours = "OPEN 24 HOURS\n연중무휴",
		ssid = "SUBWAY_FREE",
		pw = "subway2026",
	})
	tablePendants(ctx, { shade = "drum", look = L.of(0, 120, 56), lights = 1, dia = 1.1 })
end

-- 분식 ----------------------------------------------------------------------------------------------
-- 떡볶이 철판: 사각 팬 + 빨간 소스 + 떡 · 어묵 · 달걀 · 파. base = 팬 바닥 가운데 (조리대 윗면)
local function tteokPan(ctx: any, base: CFrame, w: number, d: number)
	local K = ctx.K
	local rnd = ctx.rand
	local wall = 0.06
	K:box("FfPanBase", V3(w, 0.06, d), base * CF(0, 0.03, 0), L.of(70, 72, 76, M.Metal))
	K:box("FfPanWall", V3(w, 0.32, wall), base * CF(0, 0.16, d / 2 - wall / 2), L.of(150, 154, 158, M.Metal))
	K:box("FfPanWall", V3(w, 0.32, wall), base * CF(0, 0.16, -d / 2 + wall / 2), L.of(150, 154, 158, M.Metal))
	K:box("FfPanWall", V3(wall, 0.32, d), base * CF(w / 2 - wall / 2, 0.16, 0), L.of(150, 154, 158, M.Metal))
	K:box("FfPanWall", V3(wall, 0.32, d), base * CF(-w / 2 + wall / 2, 0.16, 0), L.of(150, 154, 158, M.Metal))
	K:box("FfPanSauce", V3(w - 0.12, 0.05, d - 0.12), base * CF(0, 0.22, 0), { c = rgb(190, 44, 24), m = M.SmoothPlastic, r = 0.1 })
	local n = if ctx.low then 8 elseif ctx.high then 26 else 16
	for i = 1, n do
		local x = (rnd() - 0.5) * (w - 0.4)
		local z = (rnd() - 0.5) * (d - 0.4)
		K:cyl("FfTteok", 0.42, 0.12, base * CF(x, 0.26, z) * ANG(0, rnd() * PI, 0.05), L.of(236, 118, 92))
	end
	local nf = if ctx.low then 3 else 7
	for i = 1, nf do
		local x = (rnd() - 0.5) * (w - 0.5)
		local z = (rnd() - 0.5) * (d - 0.5)
		K:wedge("FfFishCake", V3(0.04, 0.26, 0.36), base * CF(x, 0.27, z) * ANG(0, rnd() * PI, PI / 2), L.of(206, 120, 80))
	end
	for i = 1, (if ctx.low then 1 else 3) do
		local x = (rnd() - 0.5) * (w - 0.6)
		local z = (rnd() - 0.5) * (d - 0.6)
		K:ell("FfEgg", V3(0.26, 0.2, 0.34), base * CF(x, 0.28, z) * ANG(0, rnd() * PI, 0), L.of(244, 220, 200))
	end
	if not ctx.low then
		for i = 1, 8 do
			local x = (rnd() - 0.5) * (w - 0.4)
			local z = (rnd() - 0.5) * (d - 0.4)
			K:cyl("FfScallion", 0.14, 0.04, base * CF(x, 0.27, z) * ANG(0, rnd() * PI, 0), L.of(90, 170, 60))
		end
		-- 큰 국자 (손잡이 걸쳐 둠)
		K:bar("FfLadle", (base * CF(w / 2 - 0.3, 0.3, d / 2 - 0.4)).Position, (base * CF(w / 2 + 0.2, 0.8, d / 2 - 0.2)).Position, 0.05, 0.04, L.steel)
		K:ell("FfLadleCup", V3(0.3, 0.12, 0.3), base * CF(w / 2 - 0.35, 0.28, d / 2 - 0.42), L.steel)
	end
end

-- 어묵 국물통: 칸막이 사각 통 + 국물 + 꼬치 (기대어 꽂힘)
local function eomukTank(ctx: any, base: CFrame, w: number, d: number, h: number?)
	local K = ctx.K
	local rnd = ctx.rand
	local hh = h or 0.7
	K:box("FfTankBody", V3(w, hh, d), base * CF(0, hh / 2, 0), L.of(190, 194, 198, M.Metal, { r = 0.1 }))
	K:box("FfTankBroth", V3(w - 0.1, 0.03, d - 0.1), base * CF(0, hh - 0.05, 0), { c = rgb(196, 160, 100), m = M.Glass, t = 0.2, r = 0.15 })
	K:box("FfTankRim", V3(w + 0.04, 0.05, 0.05), base * CF(0, hh + 0.02, d / 2), L.chrome)
	K:box("FfTankRim", V3(w + 0.04, 0.05, 0.05), base * CF(0, hh + 0.02, -d / 2), L.chrome)
	local nDiv = math.max(1, math.floor(w / 1.1))
	for i = 1, nDiv - 1 do
		K:box("FfTankDivider", V3(0.04, 0.2, d - 0.06), base * CF(-w / 2 + i * w / nDiv, hh - 0.04, 0), L.chrome)
	end
	local n = if ctx.low then 6 elseif ctx.high then 16 else 11
	for i = 1, n do
		local x = -w / 2 + 0.2 + (w - 0.4) * (i - 0.5) / n
		local z = (rnd() - 0.5) * (d - 0.3)
		local lean = ANG(-0.5 - rnd() * 0.25, 0, (rnd() - 0.5) * 0.3)
		local sk = base * CF(x, hh - 0.25, z + d * 0.18) * lean
		K:cyl("FfSkewer", 1.5, 0.035, sk * CF(0, 0.55, 0) * ANG(0, 0, PI / 2), L.of(214, 182, 130, M.Wood))
		if i % 3 == 0 then
			-- 긴 막대 어묵
			K:cyl("FfEomukStick", 0.6, 0.14, sk * CF(0, 0.15, 0) * ANG(0, 0, PI / 2), L.of(206, 150, 96))
		else
			-- 주름 접은 납작 어묵 (위아래 두 겹)
			K:ell("FfEomuk", V3(0.42, 0.3, 0.08), sk * CF(0, 0.2, 0.04), L.of(214, 166, 110))
			K:ell("FfEomuk", V3(0.42, 0.3, 0.08), sk * CF(0, -0.04, -0.04), L.of(200, 150, 96))
		end
	end
	K:bar("FfTankLadle", (base * CF(w / 2 - 0.2, hh, -d / 2 + 0.15)).Position, (base * CF(w / 2 + 0.1, hh + 0.7, -d / 2 - 0.05)).Position, 0.05, 0.04, L.steel)
end

-- 순대 찜기 (둥근 솥 + 뚜껑 + 손잡이) + 도마 위 썬 순대. 반환 뚜껑 Model (여닫기)
local function sundaeSteamer(ctx: any, base: CFrame, dia: number): any
	local K = ctx.K
	local h = 0.8
	K:vcyl("FfSteamerPot", h, dia, base * CF(0, h / 2, 0), L.of(190, 194, 198, M.Metal, { r = 0.1 }))
	K:vcyl("FfSteamerBand", 0.08, dia + 0.04, base * CF(0, h - 0.06, 0), L.chrome)
	for _, sx in { -1, 1 } do
		K:box("FfSteamerEar", V3(0.24, 0.06, 0.14), base * CF(sx * (dia / 2 + 0.08), h - 0.18, 0), L.chrome)
	end
	-- 안쪽 순대 (뚜껑 열면 보임)
	K:disc("FfSteamerInner", dia - 0.1, 0.02, base * CF(0, h - 0.12, 0), L.of(70, 60, 56))
	for i = 0, 2 do
		K:ring("FfSundaeCoil", base * CF(0, h - 0.08, 0) * ANG(PI / 2, 0, 0), dia * (0.14 + i * 0.1), 0.11, 6, L.of(46, 34, 40), 0, PI * 1.6)
	end
	local lid = K:group("FfSteamerLid", function()
		K:ell("FfSteamerLidDome", V3(dia + 0.04, 0.36, dia + 0.04), base * CF(0, h + 0.02, 0), L.of(200, 204, 208, M.Metal, { r = 0.12 }))
		K:vcyl("FfSteamerLidKnob", 0.12, 0.16, base * CF(0, h + 0.22, 0), L.black)
		K:box("FfSteamerLidHandle", V3(0.3, 0.06, 0.08), base * CF(0, h + 0.3, 0), L.black)
	end)
	return { lid = lid, hinge = (K.cf * base * CF(0, h + 0.02, -dia / 2)).Position }
end

local function sundaeBoard(ctx: any, base: CFrame)
	local K = ctx.K
	K:box("FfCutBoard", V3(1.1, 0.08, 0.75), base * CF(0, 0.04, 0), L.of(220, 200, 160, M.Wood))
	if not ctx.low then
		for i = 0, 5 do
			K:cyl("FfSundaeSlice", 0.08, 0.2, base * CF(-0.35 + i * 0.1, 0.18, 0.05) * ANG(0, 0, 0.2), L.of(50, 36, 42))
		end
		K:box("FfLiver", V3(0.22, 0.08, 0.16), base * CF(0.3, 0.12, -0.15), L.of(110, 50, 40))
		K:box("FfLiver", V3(0.2, 0.07, 0.14), base * CF(0.32, 0.12, 0.1), L.of(96, 44, 36))
		K:box("FfKnife", V3(0.5, 0.02, 0.1), base * CF(0.1, 0.09, -0.27), L.chrome)
		K:box("FfKnifeGrip", V3(0.24, 0.05, 0.08), base * CF(0.46, 0.1, -0.27), L.black)
	end
end

-- 튀김 진열대: 철망 트레이 + 튀김 (김말이 · 오징어 · 고구마 · 야채) + 유리 덮개 + 열 램프
local function twigimCase(ctx: any, base: CFrame, w: number, d: number, o: any?)
	local K = ctx.K
	local rnd = ctx.rand
	local oo: any = o or {}
	K:box("FfTwigimTray", V3(w, 0.08, d), base * CF(0, 0.04, 0), L.of(190, 194, 198, M.Metal))
	K:box("FfTwigimPaper", V3(w - 0.2, 0.012, d - 0.2), base * CF(0, 0.086, 0), L.of(246, 240, 220, M.Fabric))
	local n = if ctx.low then 8 elseif ctx.high then 20 else 14
	for i = 1, n do
		local x = -w / 2 + 0.3 + (w - 0.6) * ((i - 1) % 5 + 0.5) / 5
		local z = -d / 2 + 0.3 + (d - 0.6) * (math.floor((i - 1) / 5) + 0.5) / math.ceil(n / 5)
		local k = i % 4
		local p = base * CF(x + (rnd() - 0.5) * 0.12, 0.16, z) * ANG(0, (rnd() - 0.5) * 0.5, 0)
		if k == 0 then
			K:cyl("FfGimmari", 0.5, 0.16, p, L.of(206, 150, 70)) -- 김말이
		elseif k == 1 then
			K:ell("FfSquidFry", V3(0.5, 0.16, 0.26), p, L.of(222, 176, 96)) -- 오징어
		elseif k == 2 then
			K:ell("FfSweetPotato", V3(0.42, 0.12, 0.3), p, L.of(214, 140, 60)) -- 고구마
		else
			K:ell("FfVegFry", V3(0.44, 0.2, 0.4), p, L.of(196, 150, 70)) -- 야채
		end
	end
	if oo.cover ~= false then
		local ch = 0.9
		K:box("FfTwigimGlassF", V3(w, ch, 0.03), base * CF(0, 0.08 + ch / 2, d / 2) * ANG(-0.2, 0, 0), { c = rgb(224, 236, 240), m = M.Glass, t = 0.75, r = 0.15 })
		K:box("FfTwigimGlassT", V3(w, 0.03, d * 0.6), base * CF(0, 0.08 + ch, -d * 0.2), { c = rgb(224, 236, 240), m = M.Glass, t = 0.75, r = 0.15 })
		K:box("FfTwigimLamp", V3(w - 0.2, 0.05, 0.08), base * CF(0, 0.06 + ch, -d * 0.2), neon(rgb(255, 160, 80)))
		for _, sx in { -1, 1 } do
			K:box("FfTwigimSide", V3(0.04, ch, d), base * CF(sx * w / 2, 0.08 + ch / 2, 0), L.chrome)
		end
	end
end

-- 김밥 말이대: 도마 + 김발 + 말아 놓은 김밥 + 썬 김밥 + 재료 칸
local function gimbapStation(ctx: any, base: CFrame, w: number, d: number)
	local K = ctx.K
	K:box("FfGimbapBoard", V3(w, 0.1, d), base * CF(0, 0.05, 0), L.of(214, 184, 140, M.Wood))
	K:box("FfBambooMat", V3(0.9, 0.03, 0.7), base * CF(-w / 2 + 0.6, 0.115, 0.05), L.of(150, 170, 90, M.Wood))
	K:box("FfGim", V3(0.8, 0.012, 0.6), base * CF(-w / 2 + 0.6, 0.135, 0.05), L.of(24, 30, 22))
	K:box("FfRice", V3(0.7, 0.03, 0.4), base * CF(-w / 2 + 0.6, 0.15, 0.1), L.of(248, 246, 238))
	for i = 0, 2 do
		K:cyl("FfGimbapRoll", 1.0, 0.24, base * CF(0.0, 0.22, -d / 2 + 0.22 + i * 0.27), L.of(26, 30, 24))
	end
	if not ctx.low then
		for i = 0, 6 do
			local p = base * CF(w / 2 - 0.9 + i * 0.13, 0.2, d / 2 - 0.25) * ANG(0, 0, PI / 2)
			K:cyl("FfGimbapSlice", 0.1, 0.24, p * ANG(0, 0, 0), L.of(26, 30, 24))
			K:cyl("FfGimbapRice", 0.104, 0.19, p, L.of(248, 246, 238))
			K:cyl("FfGimbapCore", 0.108, 0.08, p, L.of(240, 180, 40))
		end
	end
	-- 재료 칸 (단무지 · 당근 · 시금치 · 햄 · 계란)
	local cols = { rgb(250, 214, 40), rgb(236, 120, 40), rgb(60, 140, 50), rgb(236, 140, 140), rgb(250, 230, 120) }
	local n = if ctx.low then 3 else 5
	for i = 1, n do
		local x = -w / 2 + 0.3 + (i - 1) * 0.42
		local p = base * CF(x, 0.1, -d / 2 + 0.05)
		K:box("FfFillPan", V3(0.38, 0.14, 0.32), p * CF(0, 0.07, 0.16), L.steel)
		K:box("FfFill", V3(0.32, 0.04, 0.26), p * CF(0, 0.13, 0.16), pl(cols[i]))
	end
end

-- 분식 조리대 (벽에 붙은 스테인리스 작업대 + 모듈들). pcf 앞 = 방 쪽. len 길이
local function snackStation(ctx: any, pcf: CFrame, len: number): any
	local K = ctx.K
	local P = ctx.pal
	local h, d = 3.2, 2.0
	-- 본체 (타일 앞판 + 스테인리스 상판 + 아래 선반)
	K:box("FfStationBody", V3(len, h - 0.4, d - 0.1), pcf * CF(0, 0.3 + (h - 0.4) / 2 - 0.1, -0.05), L.of(190, 194, 198, M.Metal))
	K:box("FfStationKick", V3(len - 0.1, 0.3, d - 0.3), pcf * CF(0, 0.15, -0.15), L.black)
	K:box("FfStationTop", V3(len + 0.06, 0.1, d + 0.04), pcf * CF(0, h - 0.05, 0), L.of(206, 210, 214, M.Metal, { r = 0.1 }))
	local fh = h - 0.75
	K:plate("FfStationFront", len - 0.1, fh, 0.04, pcf * CF(0, 0.35 + fh / 2, d / 2 - 0.08), L.of(P.tileAcc.R * 255, P.tileAcc.G * 255, P.tileAcc.B * 255, M.CeramicTiles))
	if not ctx.low then
		for i = 1, 2 do
			K:plate("FfStationGrout", len - 0.1, 0.025, 0.045, pcf * CF(0, 0.35 + fh * i / 3, d / 2 - 0.08), L.of(240, 236, 230))
		end
	end
	K:text("FfStationBand", len - 0.4, 0.36, pcf * CF(0, h - 0.32, d / 2 - 0.035), "즉석 떡볶이 · 튀김 · 순대 · 김밥 · 어묵", { fg = WHITE, bg = dark(P.accent, 0.1), font = F.GothamBlack, d = 0.01 })
	local y = h
	-- 모듈 배치 (왼쪽부터): 튀김 · 떡볶이 · 어묵 · 순대 · 김밥 (길이에 맞춰)
	local mods = {}
	local x = -len / 2 + 0.15
	local function take(wd: number): number?
		if x + wd > len / 2 - 0.15 then
			return nil
		end
		local c = x + wd / 2
		x += wd + 0.12
		return c
	end
	local out: any = {}
	local tc = take(2.2)
	if tc then
		twigimCase(ctx, pcf * CF(tc, y, 0.05), 2.1, 1.5)
		table.insert(mods, "twigim")
	end
	local pc = take(2.8)
	if pc then
		tteokPan(ctx, pcf * CF(pc, y, 0.05), 2.7, 1.6)
		-- 열기 (불꽃 받침): 팬 아래 버너 테두리
		K:box("FfPanBurner", V3(2.7, 0.06, 1.6), pcf * CF(pc, y + 0.0, 0.05), L.of(40, 40, 42, M.Metal))
		table.insert(mods, "pan")
	end
	local ec = take(2.0)
	if ec then
		eomukTank(ctx, pcf * CF(ec, y, 0.0), 1.9, 1.4)
		table.insert(mods, "eomuk")
	end
	local sc = take(1.25)
	if sc then
		out.steamer = sundaeSteamer(ctx, pcf * CF(sc, y, -0.25), 1.1)
		sundaeBoard(ctx, pcf * CF(sc, y, 0.62))
		table.insert(mods, "sundae")
	end
	local gc = take(2.1)
	if gc then
		gimbapStation(ctx, pcf * CF(gc, y, 0.1), 2.0, 1.4)
		table.insert(mods, "gimbap")
	end
	out.mods = mods
	-- 뒤 벽 아래 받침 선반 위 양념 통 (고춧가루 · 물엿)
	if not ctx.low then
		local wc = pcf * CF(0, 0, -d / 2 - 0.06)
		local sh = Props.shelf(K, wc * CF(0, h + 1.6, 0), math.min(len - 0.6, 5), { depth = 0.6, look = L.steel, bracket = L.steel })
		local cols = { rgb(190, 40, 24), rgb(236, 190, 90), rgb(60, 40, 30), rgb(250, 250, 246), rgb(190, 40, 24) }
		local n = math.min(5, math.floor((math.min(len - 0.6, 5) - 0.4) / 0.6))
		for i = 1, n do
			local xx = -(n - 1) * 0.3 + (i - 1) * 0.6
			K:vcyl("FfSeasoning", 0.55, 0.4, sh * CF(xx, 0.275, 0), { c = cols[i], m = M.Plastic, t = 0.05 })
			K:vcyl("FfSeasoningLid", 0.08, 0.42, sh * CF(xx, 0.59, 0), L.of(230, 60, 50, M.Plastic))
		end
	end
	return out
end

-- 손글씨 가격판 (화이트보드 + 마커 글씨)
local function priceBoard(ctx: any, dcf: CFrame, w: number, h: number, title: string, items: { any })
	local K = ctx.K
	local P = ctx.pal
	K:plate("FfBoardFrame", w + 0.16, h + 0.16, 0.06, dcf, L.alu)
	K:plate("FfBoard", w, h, 0.07, dcf, L.of(252, 252, 250))
	K:text("FfBoardTitle", w * 0.8, 0.5, dcf * CF(0, h / 2 - 0.36, 0.075), title, { fg = P.accent, font = F.PermanentMarker, d = 0.004 })
	local rows = #items
	local rh = (h - 0.9) / rows
	for i, it in items do
		local y = h / 2 - 0.75 - rh * (i - 0.5)
		local c = if i % 3 == 0 then rgb(30, 70, 170) else rgb(30, 30, 30)
		K:text("FfBoardItem", w * 0.55, rh * 0.8, dcf * CF(-w * 0.2, y, 0.075), it[1], { fg = c, font = F.PermanentMarker, align = "Left", d = 0.004 })
		K:text("FfBoardPrice", w * 0.32, rh * 0.8, dcf * CF(w * 0.3, y, 0.075), it[2], { fg = c, font = F.PermanentMarker, align = "Right", d = 0.004 })
	end
	if not ctx.low then
		K:box("FfMarkerTray", V3(w * 0.6, 0.06, 0.18), dcf * CF(0, -h / 2 - 0.05, 0.09), L.alu)
		for i, c in { rgb(200, 30, 30), rgb(30, 70, 170), rgb(30, 30, 30) } do
			K:cyl("FfMarker", 0.4, 0.07, dcf * CF(-0.4 + i * 0.3, -h / 2 + 0.01, 0.1), pl(c))
		end
		-- 자석 쿠폰 · 메모
		K:plate("FfBoardMemo", 0.5, 0.5, 0.008, dcf * CF(w / 2 - 0.4, -h / 2 + 0.45, 0.075) * ANG(0, 0, 0.08), L.of(255, 236, 120))
		K:text("FfBoardMemoText", 0.44, 0.42, dcf * CF(w / 2 - 0.4, -h / 2 + 0.45, 0.085) * ANG(0, 0, 0.08), "쿠폰 10장\n= 떡볶이\n1인분", { fg = rgb(60, 40, 20), font = F.PermanentMarker, d = 0.002 })
	end
end

-- 셀프 단무지 · 물 · 컵 소독기
local function danmujiSelf(ctx: any, pcf: CFrame, w: number)
	local K = ctx.K
	local P = ctx.pal
	local h, d = 3.0, 1.2
	local top = cabinet(ctx, pcf, w, h, d, L.of(P.tileAcc.R * 255, P.tileAcc.G * 255, P.tileAcc.B * 255), L.steel, { doors = 2 })
	local dj = pcf * CF(-w / 2 + 0.55, top, 0)
	K:box("FfDanmujiTub", V3(0.8, 0.4, 0.62), dj * CF(0, 0.2, 0), { c = rgb(236, 244, 236), m = M.Glass, t = 0.4 })
	K:box("FfDanmuji", V3(0.7, 0.28, 0.54), dj * CF(0, 0.16, 0), L.of(250, 214, 40))
	K:bar("FfDanmujiTongs", (dj * CF(0.3, 0.42, 0.1)).Position, (dj * CF(0.48, 0.44, 0.4)).Position, 0.05, 0.03, L.steel)
	K:text("FfDanmujiLabel", 0.6, 0.18, dj * CF(0, 0.22, 0.315), "셀프 단무지", { fg = WHITE, bg = P.accent, font = F.GothamBlack, d = 0.004 })
	-- 물병 · 종이컵
	for i = 0, 1 do
		local b = pcf * CF(0.0 + i * 0.36, top, -0.2)
		K:vcyl("FfWaterBottle", 0.75, 0.28, b * CF(0, 0.375, 0), { c = rgb(200, 220, 240), m = M.Plastic, t = 0.35 })
		K:vcyl("FfWaterCap", 0.1, 0.16, b * CF(0, 0.8, 0), L.of(40, 120, 220, M.Plastic))
	end
	K:vcyl("FfPaperCups", 0.6, 0.24, pcf * CF(0.2, top + 0.3, 0.3), L.of(250, 250, 246))
	-- 벽에 컵 소독기 (UV 자외선 · 한국 식당 필수품): 스테인리스 틀 + 보라빛 유리문 + 안의 컵 선반
	local wc = pcf * CF(0, 0, -d / 2 - 0.06)
	local uv = wc * CF(w / 2 - 0.8, h + 1.5, 0)
	local st = L.of(196, 200, 204, M.Metal, { r = 0.1 })
	K:plate("FfUVBack", 1.3, 1.5, 0.06, uv, st)
	K:plate("FfUVSide", 0.06, 1.5, 0.62, uv * CF(-0.62, 0, 0), st)
	K:plate("FfUVSide", 0.06, 1.5, 0.62, uv * CF(0.62, 0, 0), st)
	K:plate("FfUVTop", 1.3, 0.12, 0.62, uv * CF(0, 0.69, 0), st)
	K:plate("FfUVBottom", 1.3, 0.12, 0.62, uv * CF(0, -0.69, 0), st)
	K:plate("FfUVShelf", 1.18, 0.04, 0.5, uv * CF(0, -0.05, 0.06), L.chrome)
	K:plate("FfUVGlow", 1.1, 0.04, 0.03, uv * CF(0, 0.58, 0.1), neon(rgb(150, 110, 255)))
	if not ctx.low then
		for row = 0, 1 do
			for i = 0, 2 do
				K:vcyl("FfUVCup", 0.34, 0.24, uv * CF(-0.38 + i * 0.38, -0.45 + row * 0.42, 0.3), L.steel)
			end
		end
	end
	K:plate("FfUVGlass", 1.18, 1.26, 0.03, uv * CF(0, 0, 0.6), { c = rgb(160, 130, 255), m = M.Glass, t = 0.55, r = 0.15 })
	K:plate("FfUVHandle", 0.5, 0.06, 0.06, uv * CF(0, 0.5, 0.63), L.chrome)
	K:text("FfUVLabel", 1.0, 0.16, uv * CF(0, -0.62, 0.63), "자외선 컵 소독기", { fg = rgb(40, 40, 50), bg = rgb(236, 238, 240), font = F.GothamBold, d = 0.004 })
end

-- 분식 벽 포스터 묶음
local function snackPosters(ctx: any)
	local P = ctx.pal
	local pT = priceIn(ctx.signs, "떡볶이", "4,500")
	local p1, w1 = wallSpotFit(ctx, { "left", "right", "back" }, { 2.6, 2.0 }, 3.9, 6.9, -2)
	if p1 then
		local k = (w1 - 0.2) / 2.4
		poster(ctx, p1, 2.4 * k, 2.9 * k, {
			bg = P.accent,
			frame = L.of(250, 250, 250),
			glass = true,
			art = artTteok(0, -0.05 * k, 1.3 * k),
			texts = {
				{ "국물 떡볶이", 0, 1.0 * k, 2.0 * k, 0.44 * k, WHITE, F.GothamBlack },
				{ "매일 직접 만든 양념장", 0, 0.62 * k, 1.9 * k, 0.24 * k, rgb(255, 230, 160), F.GothamBold },
				{ "1인분 " .. pT .. "원", 0, -1.02 * k, 1.8 * k, 0.38 * k, P.gold, F.GothamBlack },
			},
		})
	end
	local p2, w2 = wallSpotFit(ctx, { "right", "left", "back" }, { 2.6, 2.0 }, 3.9, 6.9, 2)
	if p2 then
		local k = (w2 - 0.2) / 2.4
		local a = artTteok(-0.5 * k, 0.15 * k, 0.8 * k)
		for _, q in artGimbap(0.4 * k, -0.25 * k, 0.8 * k) do
			table.insert(a, q)
		end
		poster(ctx, p2, 2.4 * k, 2.9 * k, {
			bg = rgb(255, 236, 170),
			frame = L.of(250, 250, 250),
			glass = true,
			art = a,
			texts = {
				{ "떡튀순 세트", 0, 1.02 * k, 2.0 * k, 0.44 * k, rgb(190, 30, 24), F.GothamBlack },
				{ "떡볶이 + 튀김 + 순대", 0, 0.62 * k, 1.9 * k, 0.26 * k, rgb(60, 40, 20), F.GothamBold },
				{ "12,000원", 0, -1.02 * k, 1.6 * k, 0.4 * k, rgb(190, 30, 24), F.GothamBlack },
			},
		})
	end
	-- 매운맛 단계 안내
	local p3 = wallSpot(ctx, { "left", "right", "back" }, 2.4, 4.0, 6.2, -5)
	if p3 then
		local K = ctx.K
		K:plate("FfSpicyBack", 2.3, 2.0, 0.04, p3, pl(rgb(30, 26, 24)))
		K:text("FfSpicyTitle", 2.0, 0.42, p3 * CF(0, 0.7, 0.045), "매운맛 단계", { fg = P.gold, font = F.GothamBlack, d = 0.005 })
		for i, s in { { "순한맛", rgb(250, 190, 60) }, { "보통맛", rgb(240, 120, 40) }, { "매운맛", rgb(220, 40, 30) }, { "지옥맛", rgb(120, 10, 10) } } do
			local x = -0.84 + (i - 1) * 0.56
			K:disc("FfSpicyDot", 0.46, 0.04, p3 * CF(x, 0.05, 0.06) * ANG(PI / 2, 0, 0), pl(s[2]))
			K:text("FfSpicyText", 0.54, 0.22, p3 * CF(x, -0.42, 0.045), s[1], { fg = WHITE, font = F.GothamBold, d = 0.005 })
		end
		K:text("FfSpicyFoot", 2.0, 0.24, p3 * CF(0, -0.78, 0.045), "주문 시 말씀해 주세요", { fg = rgb(200, 200, 196), font = F.GothamBold, d = 0.005 })
	end
end

local function bunsikBuild(ctx: any)
	local K, V, S = ctx.K, ctx.V, ctx.S
	local P = ctx.pal
	local pT = priceIn(ctx.signs, "떡볶이", "4,500")
	local pG = priceIn(ctx.signs, "김밥", "3,500")
	local pE = priceIn(ctx.signs, "어묵", "1,000")
	if not ctx.gw then
		local lh = if S.lower then S.lower.h else 0.45
		upperPaint(ctx, { "left", "right", "back" }, lh + 0.08, pl(P.wall, M.Plaster))
		wallBand(ctx, { "left", "right", "back" }, lh + 0.05, 0.2, 0.06, pl(P.wall2))
	end
	passDress(ctx, { trim = L.steel, header = "noren", norenText = { "분", "식", "주", "방" }, norenColor = if P.key == "mint" then rgb(30, 120, 100) else rgb(30, 40, 90), utensil = "ladle" })
	menuSignDress(ctx, pl(P.wall2), nil)
	for i = 1, 2 do
		local fd = if i == 1 then promptWallSpot(ctx, { "left", "right", "back" }, 1.6, 6.9, 8.5) else nil
		if not fd then
			fd = wallSpot(ctx, { if i == 1 then "left" else "right", if i == 1 then "right" else "left" }, 1.6, 6.9, 8.5, (i * 2 - 3) * 1.5)
		end
		if fd then
			wallFan(ctx, fd * CF(0, 0.4, 0))
		end
	end
	local gwStation = V:has("Pan") > 0 or V:has("EomukTank") > 0
	local stationRec: any = nil
	if gwStation then
		-- GwShop 조리대: 맵 음식 파트 자리에 같은 크기로 다시 (원본 숨김)
		K:free(function()
			for _, r in V.byName.Pan or {} do
				tteokPan(ctx, CF(r.c.X, r.min.Y, r.c.Z), r.size.X, r.size.Z)
				Scan.hide(K.hidden, r.part)
			end
			for _, nm in { "Sauce", "Tteok", "FishCake" } do
				for _, r in V.byName[nm] or {} do
					Scan.hide(K.hidden, r.part)
				end
			end
			for _, r in V.byName.EomukTank or {} do
				eomukTank(ctx, CF(r.c.X, r.min.Y, r.c.Z) * ANG(0, PI / 2, 0), r.size.Z, r.size.X, r.size.Y)
				Scan.hide(K.hidden, r.part)
			end
			for _, nm in { "EomukBroth", "Skewer", "Eomuk" } do
				for _, r in V.byName[nm] or {} do
					Scan.hide(K.hidden, r.part)
				end
			end
			for _, r in V.byName.SundaeSteamer or {} do
				stationRec = { steamer = sundaeSteamer(ctx, CF(r.c.X, r.min.Y, r.c.Z), math.min(r.size.X, r.size.Z)) }
				Scan.hide(K.hidden, r.part)
			end
			for _, r in V.byName.SteamerLid or {} do
				Scan.hide(K.hidden, r.part)
			end
			for _, r in V.byName.GimbapBoard or {} do
				gimbapStation(ctx, CF(r.c.X, r.min.Y, r.c.Z) * ANG(0, PI / 2, 0), r.size.Z, r.size.X)
				Scan.hide(K.hidden, r.part)
			end
			for _, r in V.byName.GimbapRoll or {} do
				Scan.hide(K.hidden, r.part)
			end
			for _, r in V.byName.CasePaper or {} do
				twigimCase(ctx, CF(r.c.X, r.min.Y - 0.08, r.c.Z) * ANG(0, PI / 2, 0), r.size.Z, r.size.X, { cover = false })
				Scan.hide(K.hidden, r.part)
			end
			for _, r in V.byName.Twigim or {} do
				Scan.hide(K.hidden, r.part)
			end
		end)
	else
		local len = math.clamp(V.W * 0.42, 6.5, 11.5)
		local spcf = nil
		local tries = { len, 9.0, 7.6, 6.4 }
		for _, l in tries do
			if l <= len + 0.01 then
				spcf = floorSpot(ctx, { walls = { "back", "left", "right" }, w = l, h = 5.4, d = 2.0, pref = { back = "left", left = "back", right = "back" }, front = 1.2, above = 2.4 })
				if spcf then
					len = l
					break
				end
			end
		end
		if spcf then
			stationRec = snackStation(ctx, spcf, len)
			-- 조리대 위 벽: 손글씨 가격판
			local wc = spcf * CF(0, 0, -1.0 - 0.06)
			priceBoard(ctx, wc * CF(-len / 4, 6.9, 0), math.min(3.4, len / 2 - 0.3), 2.3, "오늘의 메뉴", {
				{ "떡볶이", pT },
				{ "순대", "5,000" },
				{ "튀김 (3개)", "4,000" },
				{ "김밥", pG },
				{ "어묵 (1개)", pE },
			})
			-- 오른쪽 위: 메뉴 사진 액자
			local pc = wc * CF(len / 4, 6.9, 0)
			poster(ctx, pc, math.min(3.2, len / 2 - 0.4), 2.2, {
				bg = rgb(250, 246, 236),
				frame = L.of(220, 220, 220, M.Metal),
				art = artTteok(-0.7, 0.1, 0.9),
				texts = {
					{ "라볶이 6,500", 0.65, 0.35, 1.4, 0.32, rgb(190, 30, 24), F.GothamBlack },
					{ "쫄면 7,000", 0.65, -0.05, 1.4, 0.32, rgb(40, 30, 20), F.GothamBlack },
					{ "참치김밥 4,500", 0.65, -0.45, 1.4, 0.3, rgb(40, 30, 20), F.GothamBlack },
				},
			})
		end
	end
	-- 순대 찜기 뚜껑 열기 (상호작용)
	if stationRec and stationRec.steamer then
		local st = stationRec.steamer
		local knob = nil
		for _, p in st.lid:GetDescendants() do
			if p:IsA("BasePart") and string.find(p.Name, "Handle") then
				knob = p
			end
		end
		if knob and Interact.canPrompt(K, K.cf:PointToObjectSpace(knob.Position)) then
			Interact.swing(K, st.lid, st.hinge, (K.cf.RightVector :: Vector3), -1.1, { object = "순대 찜기", openText = "뚜껑 열기", closeText = "뚜껑 닫기" })
		end
	end
	-- 음료 냉장고 (콜라 · 사이다 · 쿨피스)
	if not ctx.gw then
		placeFridge(ctx, { walls = { "back", "right", "left" }, pref = { back = "right", right = "back", left = "back" }, header = "음료수 · 쿨피스", headerBg = P.accent, items = {
			{ rgb(200, 24, 32), "can", rgb(200, 24, 32) },
			{ rgb(40, 150, 70), "can" },
			{ rgb(250, 160, 190), "pet", rgb(250, 120, 160) },
			{ rgb(236, 120, 30), "can" },
			{ rgb(200, 230, 240), "pet", rgb(40, 120, 210) },
			{ rgb(250, 230, 120), "can" },
		}, brand = "SHOWCASE" })
	end
	-- 셀프 단무지 · 물 (옆벽 앞쪽)
	local dp = floorSpot(ctx, { walls = { "left", "right", "back" }, w = 2.4, h = 5.2, d = 1.2, pref = { left = "back", right = "back" }, front = 1.0 })
	if dp then
		danmujiSelf(ctx, dp, 2.4)
	end
	-- 벽: 선풍기 2 · TV · 포스터 · 안내
	-- 사진 메뉴 띠 (옆벽 위)
	local sw0 = math.min(12.4, V.D - 5.5, V.W - 4)
	if sw0 > 5 then
		local sd, fw = wallSpotFit(ctx, { "right", "left", "back" }, { sw0 + 0.3, 9.3, 6.3 }, 7.0, 8.95, 0)
		local sw = fw - 0.3
		if sd and sw > 4.5 then
			local items = {
				{ "떡볶이", pT, artTteok(0, 0.2, 0.6) },
				{ "순대", "5,000", artSundae(0, 0.2, 0.6) },
				{ "모듬튀김", "4,000", artTwigim(0, 0.2, 0.6) },
				{ "김밥", pG, artGimbap(0, 0.2, 0.55) },
				{ "어묵", pE, artEomuk(0, 0.2, 0.6) },
				{ "라볶이", "6,500", artNoodle(0, 0.2, 0.55, rgb(196, 50, 28), nil) },
				{ "쫄면", "7,000", artNoodle(0, 0.2, 0.55, rgb(220, 90, 50), rgb(90, 170, 60)) },
				{ "라면", "4,500", artNoodle(0, 0.2, 0.55, rgb(200, 90, 40), rgb(250, 230, 120)) },
			}
			local n = math.clamp(math.floor(sw / 1.5), 3, 8)
			while #items > n do
				table.remove(items)
			end
			photoStrip(ctx, sd, sw, 1.8, items, { priceC = P.accent, frame = pl(dark(P.wall2, 0.1)) })
		end
	end
	if V:has("TV") == 0 and V:has("MonitorScreen") == 0 then
		local d = wallSpot(ctx, { "left", "right", "back" }, 3.4, 6.2, 8.3, 4)
		if d then
			tvSet(ctx, d, 3.0, {
				{ "예능", rgb(90, 60, 150), {
					{ "b", 0, -0.05, 1.0, 0.5, rgb(240, 120, 160) },
					{ "e", -0.22, 0.0, 0.16, 0.26, rgb(250, 214, 180) },
					{ "b", -0.22, -0.2, 0.2, 0.2, rgb(40, 90, 200) },
					{ "e", 0.18, 0.0, 0.16, 0.26, rgb(240, 200, 170) },
					{ "b", 0.18, -0.2, 0.2, 0.2, rgb(250, 200, 40) },
					{ "b", 0, -0.36, 0.8, 0.12, rgb(255, 230, 40) },
				}, "분식 먹방 대결!", "떡볶이 10인분 도전 ㅋㅋㅋ" },
				{ "드라마", rgb(60, 50, 90), { { "e", 0, -0.05, 0.3, 0.6, rgb(230, 200, 180) } }, "주말 드라마 · 부산 사나이", "본방 사수!" },
				{ "뉴스", rgb(20, 46, 110), { { "b", 0, -0.42, 1.0, 0.12, rgb(200, 24, 32) } }, "부산 날씨  맑음 22°C", "광안리 불꽃축제 11월 8일 개최" },
			}, "TV")
		end
	end
	snackPosters(ctx)
	infoSet(ctx, {
		origin = { "쌀 : 국내산", "떡(쌀) : 국내산", "어묵(연육) : 수입산", "순대(돼지 창자) : 국내산", "배추김치 : 국내산", "고춧가루 : 국내산" },
		hours = "영업시간\n10:00 - 22:00",
		ssid = "BUNSIK_5G",
		pw = "tteok4500",
		stickers = {
			{ "카드 · 페이\n결제 가능", rgb(40, 90, 200) },
			{ "포장 · 배달\n가능", rgb(220, 60, 40) },
			{ "셀프\n물 · 단무지", rgb(40, 150, 90) },
		},
	})
end

-- 오뎅바 ----------------------------------------------------------------------------------------------
-- 나무 메뉴 패 (이자카야식 세로 나무판 줄)
local function woodPlaques(ctx: any, dcf: CFrame, items: { any }, o: any?)
	local K = ctx.K
	local oo: any = o or {}
	local n = #items
	local pw, ph = 0.62, 2.2
	local gap = 0.1
	local total = n * pw + (n - 1) * gap
	K:plate("FfPlaqueRail", total + 0.4, 0.12, 0.08, dcf * CF(0, ph / 2 + 0.12, 0), L.darkWood)
	for i, it in items do
		local x = -total / 2 + pw / 2 + (i - 1) * (pw + gap)
		local c = dcf * CF(x, 0, 0.0)
		K:plate("FfPlaque", pw, ph, 0.06, c, L.of(222, 196, 150, M.Wood))
		K:text("FfPlaqueName", pw - 0.1, ph * 0.66, c * CF(0, 0.3, 0.065), it[1], { fg = rgb(30, 20, 14), font = F.GothamBlack, d = 0.004, wrap = true })
		K:text("FfPlaquePrice", pw - 0.08, 0.32, c * CF(0, -ph / 2 + 0.3, 0.065), it[2], { fg = oo.priceC or rgb(180, 30, 24), font = F.GothamBold, d = 0.004 })
		if not ctx.low then
			K:cyl("FfPlaqueNail", 0.06, 0.06, c * CF(0, ph / 2 - 0.1, 0.09) * ANG(0, PI / 2, 0), L.brass)
		end
	end
end

-- 빨간 제등 (종이 등): 천장에서 끈으로
local function lantern(ctx: any, top: Vector3, drop: number, text: string, c: Color3?)
	local K = ctx.K
	local col = c or rgb(200, 36, 30)
	local p = top - V3(0, drop, 0)
	K:seg("FfLanternCord", top, p + V3(0, 0.75, 0), 0.04, L.black)
	K:disc("FfLanternCap", 0.42, 0.1, CF(p + V3(0, 0.7, 0)), L.black)
	local body = K:ell("FfLantern", V3(0.95, 1.3, 0.95), CF(p), { c = col, m = M.Neon, t = 0.25 })
	K:disc("FfLanternCap", 0.42, 0.1, CF(p - V3(0, 0.66, 0)), L.black)
	if not ctx.low then
		for i = -1, 1 do
			K:disc("FfLanternRib", 0.96 - math.abs(i) * 0.22, 0.02, CF(p + V3(0, i * 0.34, 0)), { c = dark(col, 0.45), m = M.SmoothPlastic })
		end
		K:seg("FfLanternTassel", p - V3(0, 0.7, 0), p - V3(0, 1.05, 0), 0.06, L.black)
	end
	-- 글자 (양면)
	K:text("FfLanternText", 0.5, 0.8, CF(p + V3(0, 0, 0.47)), text, { fg = rgb(30, 10, 8), font = F.GothamBlack, d = 0.005 })
	return body
end

-- 오뎅 통 (카운터 뒤쪽 3분의 1, 상판에 묻힌 사각 통 + 칸막이 + 꼬치)
local function odengTrough(ctx: any)
	local K, V = ctx.K, ctx.V
	local g = V.counters[1]
	if not g then
		return
	end
	local alongX = (g.max.X - g.min.X) >= (g.max.Z - g.min.Z)
	if not alongX then
		return
	end
	-- 맥주 탭 · 드립 트레이 자리는 피함
	local avoid0, avoid1 = math.huge, -math.huge
	for _, nm in { "TapPost", "TapBar", "DripTray", "TapHandle" } do
		for _, r in V.byName[nm] or {} do
			avoid0 = math.min(avoid0, r.min.X - 0.6)
			avoid1 = math.max(avoid1, r.max.X + 0.6)
		end
	end
	local a, b = g.min.X + 0.6, g.max.X - 0.6
	-- 탭에서 먼 쪽의 넓은 구간
	local segs = {}
	if avoid0 < avoid1 then
		table.insert(segs, { a, math.min(b, avoid0) })
		table.insert(segs, { math.max(a, avoid1), b })
	else
		table.insert(segs, { a, b })
	end
	table.sort(segs, function(p, q)
		return (p[2] - p[1]) > (q[2] - q[1])
	end)
	local s = segs[1]
	local len = math.min(7.5, s[2] - s[1])
	if len < 2.5 then
		return
	end
	local cx = (s[1] + s[2]) / 2
	-- 손님 쪽 = +Z (입구) 가정: 통은 뒤쪽 (min.Z 쪽) 0.95 폭
	local dd = 0.95
	local cz = g.min.Z + 0.12 + dd / 2
	local y = g.y
	K:free(function()
		local base = CF(cx, y - 0.6, cz)
		eomukTank(ctx, base, len, dd, 0.7)
		K:box("FfTroughLip", V3(len + 0.2, 0.04, dd + 0.2), CF(cx, y + 0.11, cz), L.chrome)
	end)
end

-- 벤치 (Seat 3 + Base + Backrest + Arm + Plinth): 같은 자리 덮개 (가죽 쿠션 + 원목 프레임)
local function benchOverlay(ctx: any)
	local K, V = ctx.K, ctx.V
	local seats = {}
	for _, r in V.byName.Seat or {} do
		if r.part:IsA("Seat") or true then
			table.insert(seats, r)
		end
	end
	if #seats == 0 then
		return
	end
	K:free(function()
		for _, nm in { "Plinth", "Base", "Backrest", "Arm" } do
			for _, r in V.byName[nm] or {} do
				local look = if nm == "Plinth" then L.black elseif nm == "Base" then L.of(120, 80, 50, M.Wood) elseif nm == "Arm" then L.of(110, 74, 46, M.Wood) else L.of(120, 40, 30, M.Leather)
				if nm == "Backrest" then
					K:rbox("FfBenchBack", r.size, 0.1, CF(r.c) * ANG(0, PI / 2, 0), look)
					local n = math.max(2, math.floor(math.max(r.size.X, r.size.Z) / 1.2))
					local alongZ = r.size.Z > r.size.X
					for i = 1, n - 1 do
						local off = -math.max(r.size.X, r.size.Z) / 2 + i * math.max(r.size.X, r.size.Z) / n
						K:box("FfBenchTuft", if alongZ then V3(r.size.X + 0.02, r.size.Y - 0.4, 0.04) else V3(0.04, r.size.Y - 0.4, r.size.Z + 0.02), CF(r.c) * (if alongZ then CF(0, 0, off) else CF(off, 0, 0)), L.of(90, 30, 24, M.Leather))
					end
				else
					K:box("FfBench" .. nm, r.size, CF(r.c), look)
				end
				Scan.hide(K.hidden, r.part)
			end
		end
		for _, r in seats do
			K:rbox("FfBenchCushion", r.size, 0.12, CF(r.c) * ANG(0, PI / 2, 0), L.of(150, 46, 36, M.Leather))
			Scan.hide(K.hidden, r.part)
		end
	end)
end

local function odengBuild(ctx: any)
	local K, V, S = ctx.K, ctx.V, ctx.S
	local P = ctx.pal
	-- 일반 의자 (Seat 가 아닌 ChairSeat 등)는 직접: 벤치형 Seat 는 benchOverlay
	local hasBench = V:has("Backrest") > 0
	if not hasBench then
		Common.chairs(K, V, { chair = { style = "bentwood", frame = L.walnut, seat = L.walnut } })
	else
		benchOverlay(ctx)
		-- 벤치 Seat 가 아닌 의자만
		local chairs = {}
		for _, ch in V.chairs do
			if ch.seat.name ~= "Seat" then
				table.insert(chairs, ch)
			end
		end
		if #chairs > 0 then
			local Vc = setmetatable({ chairs = chairs }, { __index = V })
			Common.chairs(K, Vc, { chair = { style = "bentwood", frame = L.walnut, seat = L.walnut } })
		end
	end
	upperPaint(ctx, { "back" }, 0.45, pl(rgb(60, 40, 30), M.Wood))
	wallBand(ctx, { "left", "right" }, V.H - 0.6, 0.3, 0.1, L.darkWood)
	odengTrough(ctx)
	-- 카운터 위 천장: 빨간 제등 줄 (카운터 길이 따라)
	local g = V.counters[1]
	if g then
		local n = math.clamp(math.floor((g.max.X - g.min.X) / 3.2), 2, 6)
		local texts = { "오\n뎅", "사\n케", "어\n묵", "酒", "오\n뎅", "사\n케" }
		for i = 1, n do
			local x = g.min.X + (g.max.X - g.min.X) * (i - 0.5) / n
			local z = (g.min.Z + g.max.Z) / 2
			if Common.ceilFree(K, x, z, 0.5) then
				local body = lantern(ctx, V3(x, V.H, z), math.clamp(V.H - 7.4, 1.6, 2.8), texts[i], if i % 2 == 0 then rgb(236, 220, 190) else nil)
				if i <= 2 then
					K:light(body, "PointLight", { Range = 10, Brightness = 0.7, Color = rgb(255, 170, 110) })
				end
				Common.useCeil(K, x, z)
			end
		end
	end
	-- 뒷벽 · 옆벽: 나무 메뉴 패
	local items = {
		{ "모둠\n어묵탕", "18,000" },
		{ "어묵\n꼬치", "2,000" },
		{ "곤약\n무", "2,500" },
		{ "계란\n말이", "15,000" },
		{ "타코\n와사비", "13,000" },
		{ "정종\n대포", "9,000" },
		{ "사케\n1병", "32,000" },
		{ "하이\n볼", "8,000" },
	}
	local wp = wallSpot(ctx, { "back", "left", "right" }, #items * 0.72 + 0.6, 5.8, 8.4, 0)
	if wp then
		woodPlaques(ctx, wp, items)
	end
	local wp2 = wallSpot(ctx, { "left", "right" }, 5 * 0.72 + 0.6, 5.6, 8.2, 0)
	if wp2 then
		woodPlaques(ctx, wp2, { { "생맥주", "5,000" }, { "소주", "5,500" }, { "맥주\n병", "6,000" }, { "어묵\n우동", "8,000" }, { "볶음\n우동", "12,000" } })
	end
	-- 사케 병 (일되병) 줄 + 나무 술통: 벽 선반
	local sh = wallSpot(ctx, { "right", "left", "back" }, 4.2, 6.6, 8.2, -2)
	if sh then
		local at = Props.shelf(K, sh * CF(0, -0.7, 0), 4.0, { depth = 0.9, look = L.darkWood })
		for i = 0, 5 do
			local x = -1.6 + i * 0.55
			local c = if i % 2 == 0 then rgb(40, 80, 50) else rgb(90, 50, 30)
			K:vcyl("FfSakeBottle", 0.9, 0.32, at * CF(x, 0.45, -0.1), { c = c, m = M.Glass, t = 0.15 })
			K:vcyl("FfSakeNeck", 0.35, 0.14, at * CF(x, 1.07, -0.1), { c = c, m = M.Glass, t = 0.15 })
			K:vcyl("FfSakeLabel", 0.4, 0.33, at * CF(x, 0.45, -0.1), L.of(246, 240, 226))
		end
	end
	local barrelSpot = floorSpot(ctx, { walls = { "left", "right", "back" }, w = 1.6, h = 2.4, d = 1.6, pref = { left = "front", right = "front" }, front = 0.6 })
	if barrelSpot then
		local b = barrelSpot
		K:vcyl("FfBarrel", 2.0, 1.5, b * CF(0, 1.0, 0), L.of(150, 106, 66, M.Wood))
		for _, y in { 0.3, 1.0, 1.7 } do
			K:vcyl("FfBarrelHoop", 0.1, 1.54, b * CF(0, y, 0), L.blackMetal)
		end
		K:disc("FfBarrelTop", 1.4, 0.06, b * CF(0, 2.02, 0), L.of(170, 126, 80, M.Wood))
		K:plate("FfBarrelLabel", 0.8, 0.9, 0.02, b * CF(0, 1.0, 0.75), L.of(246, 240, 226))
		K:text("FfBarrelText", 0.7, 0.8, b * CF(0, 1.0, 0.775), "大\n吟醸", { fg = rgb(30, 20, 14), font = F.GothamBlack, d = 0.004 })
	end
	-- 사케 · 소주 냉장고 + 네온 (손님이 닿는 자리에 상호작용)
	placeFridge(ctx, { walls = { "left", "right", "back" }, pref = { left = "back", right = "back" }, header = "사케 · 소주 · 맥주", headerBg = rgb(40, 30, 26), headerFg = P.gold, items = {
		{ rgb(40, 80, 50), "bottle", rgb(246, 240, 226) },
		{ rgb(90, 50, 30), "bottle", rgb(246, 240, 226) },
		{ rgb(36, 110, 50), "soju", rgb(240, 250, 240) },
		{ rgb(60, 120, 40), "bottle", rgb(30, 110, 40) },
		{ rgb(30, 70, 170), "can" },
		{ rgb(236, 230, 214), "bottle", rgb(180, 30, 24) },
	}, brand = "SAKE" })
	local nd = promptWallSpot(ctx, { "left", "right", "back" }, 3.4, 6.4, 7.8)
	if not nd then
		nd = wallSpot(ctx, { "left", "right", "back" }, 3.4, 6.4, 7.8, 0)
	end
	if nd then
		neonSign(ctx, nd, 3.0, 1.0, "오뎅 · 사케", rgb(255, 150, 90), { object = "네온사인" })
	end
	-- 레트로 소주 포스터 · 안내
	local p1 = wallSpot(ctx, { "left", "right", "back" }, 2.2, 3.9, 6.6, -4)
	if p1 then
		poster(ctx, p1, 2.0, 2.6, {
			bg = rgb(240, 232, 210),
			frame = L.darkWood,
			art = {
				{ "b", 0, -0.1, 0.36, 1.1, rgb(40, 120, 60) },
				{ "b", 0, 0.55, 0.14, 0.3, rgb(40, 120, 60) },
				{ "b", 0, -0.1, 0.38, 0.4, rgb(240, 240, 230) },
			},
			texts = {
				{ "부산 소주 한 잔", 0, 0.98, 1.7, 0.3, rgb(30, 80, 50), F.GothamBlack },
				{ "어묵탕엔 역시", 0, -0.86, 1.6, 0.26, rgb(60, 40, 30), F.GothamBold },
			},
		})
	end
	if V:has("TVScreen") > 0 then
		for _, r in V.byName.TVScreen do
			-- 맵 TV 화면 위에 같은 크기로 채널 화면 (자동 순환)
			local d = CFrame.fromMatrix(V3(r.c.X, r.c.Y, r.max.Z), Vector3.xAxis, Vector3.yAxis, Vector3.zAxis)
			K:free(function()
				local scr, lab = K:text("FfOdengTV", r.size.X - 0.04, r.size.Y - 0.04, d * CF(0, 0, 0.005), "롯데 3 : 2 두산\n7회말 1사 2루", { fg = WHITE, bg = rgb(30, 100, 46), glow = 1.3, font = F.GothamBold, d = 0.01 })
				local frames = {
					{ c = rgb(30, 100, 46), text = "롯데 3 : 2 두산\n7회말 1사 2루" },
					{ c = rgb(20, 46, 110), text = "부산 뉴스\n광안리 불꽃축제 11월 8일" },
					{ c = rgb(120, 40, 30), text = "심야 식당\n오늘의 안주 : 모둠 어묵" },
				}
				local last = 0
				Interact.anim(K, function(t)
					local i = math.floor(t / 8) % #frames + 1
					if i ~= last then
						last = i
						lab.Text = frames[i].text
						lab.BackgroundColor3 = frames[i].c
					end
				end)
			end)
		end
	end
	infoSet(ctx, {
		origin = { "어묵(연육) : 수입산", "무 : 국내산", "계란 : 국내산", "쌀(사케 제외) : 국내산" },
		hours = "영업시간\n17:00 - 03:00",
		ssid = "ODENG_BAR",
		pw = "oden0000",
		stickers = {
			{ "19세 미만\n주류 판매 금지", rgb(200, 30, 36) },
			{ "카드 · 페이\n결제 가능", rgb(40, 90, 200) },
		},
	})
end

-- build ----------------------------------------------------------------------------------------------
function T.build(K: any, V: any, S: any)
	local ctx = ctxNew(K, V, S)
	local ok, err = pcall(setupZones, ctx)
	if not ok then
		K:note("ff zones error: " .. tostring(err))
	end
	local t0 = #K.parts
	-- 벽 아랫단 마감 (타일 · 루버) 뒤 바탕: 콘센트 · 소화기 등으로 끊긴 틈에 맨 벽이 보이지 않게
	if S.lower and not ctx.gw then
		local lw = S.lower
		local base = if lw.kind == "louver" then (lw.back or L.charcoal) else (lw.grout or L.of(150, 148, 144))
		pcall(upperPaint, ctx, lw.walls or { "left", "right" }, 0.42, base, lw.h)
	end
	local fn = if ctx.sk == "chicken" or ctx.sk == "tongdak" then chickenBuild elseif ctx.sk == "sub" then subwayBuild elseif ctx.sk == "burger" or ctx.sk == "taco" then burgerBuild elseif ctx.sk == "odeng" then odengBuild else bunsikBuild
	local ok2, err2 = pcall(fn, ctx)
	if not ok2 then
		K:note("ff build error: " .. tostring(err2))
	end
	K:note(string.format("ff %s/%s: +%d parts, toggles %d", ctx.sk, ctx.pal.key or "?", #K.parts - t0, ctx.toggles))
	if ctx.miss then
		K:note("ff miss:" .. string.sub(ctx.miss, 1, 200))
	end
end

return T

end

__defs["T_garage"] = function()
-- GwangalliBuildingInterior/T_garage: 큰 시설 방 유형 (showroom servicebay carwash) 실내 (Venues.luau 의 방, Scan.fitRoom).
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (Common.luau 머리말의 S 필드)
--   build(K, V, S) 유형별 디테일

local Look = __require("Look")
local Props = __require("Props")
local Interact = __require("Interact")
local Common = __require("Common")

local T = {}
T.types = { "showroom", "servicebay", "carwash" }

function T.style(V: any): any
	-- 기본: 기존 가구는 그대로, 천장 설비만 (모듈을 채우면서 바꿈)
	return { chair = false, stool = false, table = false, counter = false, base = false, lower = false, mat = false, clock = false, license = false, cctv = false, ceiling = {}, lights = { kind = "none" }, skip = { upgrades = true, fixtures = true } }
end

function T.build(K: any, V: any, S: any) end

return T

end

__defs["T_grill"] = function()
-- GwangalliBuildingInterior/T_grill: 유형 (grill pocha) 실내.
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (Common.luau 머리말의 S 필드)
--   build(K, V, S) 유형별 디테일 (메뉴판 · 진열 · 주방 · 간판 · 소품 · 상호작용)

local Look = __require("Look")
local Props = __require("Props")
local Interact = __require("Interact")
local Common = __require("Common")

local T = {}
T.types = { "grill", "pocha" }

function T.style(V: any): any
	return {
		chair = { style = "padded", frame = Look.blackMetal, seat = Look.fabricGrey },
		table = { top = Look.oak, base = Look.blackMetal },
		counter = { front = "panel", frontL = Look.white, topL = Look.marbleWhite },
		lights = { kind = "downlight" },
	}
end

function T.build(K: any, V: any, S: any) end

return T

end

__defs["T_gs25"] = function()
-- GwangalliBuildingInterior/T_gs25: GS25 광안리점 매장 (gs25) + 창고 · 직원실 (stockroom) 실내 (Venues 방, Scan.fitRoom).
--   style(V) -> S  Common 에 줄 공통 마감 (스프링클러 · 감지기 · 소화기 정도만; 벽 · 바닥 · 부착물은 여기서 건물 프레임으로)
--   build(K, V, S) 유형별 디테일
--
-- 건물 프레임 B: rooms.json 의 방 상자는 월드 축 정렬인데 GS25 건물은 약 1.07° 돌아가 있음 (긴 벽에서 0.5 스터드 어긋남).
--   그래서 바닥 파트(Floor / StockFloor)의 방향으로 B 를 만들고 (원점 = 방 원점), 모든 좌표를 B 로 씀.
--   Q = K 를 감싼 대리자: Q:box(.., bcf) == K:box(.., ROT * bcf). Props 도 Q 를 받으면 B 프레임으로 지음.
--   B 축은 방 프레임과 같은 뜻: +Z = 입구 쪽, -Z = 안쪽 끝, +X = 안쪽을 볼 때 오른쪽, y = 바닥 위 높이.
--
-- 지키는 것 (cvs_delivery.json 조사): Station_* · GwJobSpawn · Destination · AutoDoor · StaffMicrowave · HotWaterMachine ·
--   CashDrawer · CardTerminalScreen · POSMonitor · CustomerDisplay · BarcodeScanner · ReceiptPrinter · CounterTop ·
--   Gondola_n · OpenChiller · Fridge · ATM · Microwave · HotBar · RestockBoxes 는 그대로 (숨기지도 덮지도 않음).
--   진열 슬롯 (SlotBack/SlotBoard, Display_slot_*) 앞 · 계산대 위 (counter_items/scanned) · 줄 서는 곳 · 직원 문 · 통로 비움.
--   숨기는 것 (순수 장식만, 같은 자리에 더 나은 것으로): CigarettePacks · CoffeeMachine · GumRack · EntranceMat ·
--   창고의 RackPost/RackDeck · StaffLocker · StaffSink · RollCage · MopBucket · WorkNotice.
--
-- 매장: 담배장 (갑 하나하나 + 가격표 + 전자담배 · 라이터) · 카페25 머신 · 핫바 · 찐빵 스티머 꾸밈 · LED 전광판 ·
--   계산대 앞 결제 스티커 · 껌/사탕 랙 · 로또 용지대 · 택배 저울 선반 · CCTV 모니터 · 봉투 걸이 · 천장 카테고리 행잉 사인 ·
--   엔드캡 POP · 진열대 전자가격표 · 행사 꼬리표 · 냉장고 문 스티커 · 냉동고 (문 여닫기) · 생활잡화 타공판 · ATM 칸막이 ·
--   온수 · 전자레인지 · 국물 싱크 꾸밈 · 창가 바 스툴 · 창 띠 시트 · 택배 키오스크 · 행사 평대 · 생수 묶음 · X배너 ·
--   장바구니 · 우산 비닐 커버기 (상호작용) · 미끄럼 주의 · 빵 매대 · 소화전 · 볼록거울 · 스피커 · 현관 매트.
-- 창고: 앵글 랙 (기둥 · 빔 · 가새 · 메쉬 선반) + 라벨 붙은 박스 · 워크인 냉장고 (문 여닫기, 안에 음료 박스) ·
--   직원 책상 (발주 단말기 · PC · CCTV 화면 전환) + 의자 · 사물함 (문 여닫기, 조끼) · 금고 · 유니폼 걸이 · 개수대 + 청소 싱크 ·
--   박스 더미 · 롤테이너 · 우유 상자 · 폐기 바구니 · 게시판 · 분전반 · 스프링클러 배관 · 바닥 안전선.

local Look = __require("Look")
local Props = __require("Props")
local Interact = __require("Interact")
local Scan = __require("Scan")
local Kit = __require("Kit")

local T = {}
T.types = { "gs25", "stockroom" }

local CF, V3 = CFrame.new, Vector3.new
local ANG = CFrame.Angles
local PI = math.pi
local M = Enum.Material
local F = Enum.Font
local rgb = Color3.fromRGB
local XA, YA, ZA = Vector3.xAxis, Vector3.yAxis, Vector3.zAxis

-- GS25 색 (2026 BI: 블루 · 스카이블루 · 화이트)
local GS_BLUE = rgb(0, 83, 166)
local GS_NAVY = rgb(16, 38, 84)
local GS_CYAN = rgb(0, 178, 226)
local WHITE = rgb(255, 255, 255)
local INK = rgb(28, 30, 34)
local RED = rgb(218, 36, 40)
local YEL = rgb(255, 210, 0)

local function lk(c: Color3, m: Enum.Material?, extra: { [string]: any }?): { [string]: any }
	local t: { [string]: any } = { c = c, m = m or M.SmoothPlastic }
	if extra then
		for k, v in extra do
			t[k] = v
		end
	end
	return t
end
local function rnd(seed: number, i: number): number
	local s = math.sin(seed * 0.731 + i * 12.9898) * 43758.5453
	return s - math.floor(s)
end
local function dk(c: Color3, f: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), f)
end

local L_BLUE = lk(GS_BLUE)
local L_CYAN = lk(GS_CYAN)
local L_STEEL = Look.steel
local L_CHROME = Look.chrome
local L_DARK = lk(rgb(40, 42, 46), M.Metal)
local L_WHITEP = lk(rgb(244, 244, 240))
local L_RUBBER = Look.rubber
local L_CARD = Look.cardboard
local L_GLASS = { c = rgb(214, 232, 238), m = M.Glass, t = 0.72, r = 0.12 }

-- 표시면 프레임 (점 p, 바깥 법선 n): +X = 보는 사람 오른쪽
local function fc(p: Vector3, n: Vector3): CFrame
	local x = YA:Cross(n).Unit
	return CFrame.fromMatrix(p, x, YA, n)
end
-- 소품 프레임 (바닥 점 p, 정면 n)
local function pf(p: Vector3, n: Vector3): CFrame
	return CFrame.lookAt(p, p - n)
end
-- 바닥에 누운 글자판 (위를 봄, 글자 위쪽 = up)
local function floorCF(p: Vector3, up: Vector3): CFrame
	local x = up:Cross(YA).Unit
	return CFrame.fromMatrix(p, x, up, YA)
end

-- 건물 프레임 --------------------------------------------------------------------------------------
local function buildingYaw(V: any): number
	for _, nm in { "Floor", "StockFloor", "CeilingBoard", "StockCeiling", "CounterTop", "CashierPartition" } do
		local l = V.byName[nm]
		local r = l and l[1]
		if r then
			local x = r.lcf.XVector
			local a = math.atan2(x.Z, x.X)
			while a > PI / 4 do
				a -= PI / 2
			end
			while a <= -PI / 4 do
				a += PI / 2
			end
			return a
		end
	end
	return 0
end

-- K 대리자: 모든 CFrame · 점 인수를 R 로 돌림 (B -> 방 프레임)
local function proxy(K: any, R: CFrame): any
	local Q: any = setmetatable({}, { __index = K })
	function Q.make(_, class, name, size, cf, look, shape)
		return K:make(class, name, size, R * cf, look, shape)
	end
	function Q.box(_, name, size, cf, look)
		return K:box(name, size, R * cf, look)
	end
	function Q.wedge(_, name, size, cf, look)
		return K:wedge(name, size, R * cf, look)
	end
	function Q.cyl(_, name, len, d, cf, look)
		return K:cyl(name, len, d, R * cf, look)
	end
	function Q.vcyl(_, name, h, d, cf, look)
		return K:vcyl(name, h, d, R * cf, look)
	end
	function Q.ball(_, name, d, cf, look)
		return K:ball(name, d, R * cf, look)
	end
	function Q.ell(_, name, size, cf, look)
		return K:ell(name, size, R * cf, look)
	end
	function Q.seg(_, name, a, b, d, look, extra)
		return K:seg(name, R * a, R * b, d, look, extra)
	end
	function Q.bar(_, name, a, b, w, h, look)
		return K:bar(name, R * a, R * b, w, h, look)
	end
	function Q.ring(_, name, frame, rr, d, n, look, a0, a1)
		return K:ring(name, R * frame, rr, d, n, look, a0, a1)
	end
	function Q.rbox(_, name, size, r, cf, look)
		return K:rbox(name, size, r, R * cf, look)
	end
	function Q.slab(_, name, w, len, th, r, cf, look)
		return K:slab(name, w, len, th, r, R * cf, look)
	end
	function Q.panel(_, name, w, h, d, r, cf, look)
		return K:panel(name, w, h, d, r, R * cf, look)
	end
	function Q.disc(_, name, dia, th, cf, look)
		return K:disc(name, dia, th, R * cf, look)
	end
	function Q.plate(_, name, w, h, d, cf, look)
		return K:plate(name, w, h, d, R * cf, look)
	end
	function Q.text(_, name, w, h, cf, s, opts)
		return K:text(name, w, h, R * cf, s, opts)
	end
	function Q.light(_, part, kind, props)
		return K:light(part, kind, props)
	end
	function Q.free(_, fn)
		return K:free(fn)
	end
	function Q.group(_, name, fn)
		return K:group(name, fn)
	end
	function Q.note(_, s)
		return K:note(s)
	end
	function Q.tick(_)
		return K:tick()
	end
	function Q.spot(_, cf, size, pad, kind)
		return K:spot(R * cf, size, pad, kind)
	end
	function Q.reserve(_, mn, mx, kind)
		return K:reserve(mn, mx, kind)
	end
	function Q.hitsKeep(_, mn, mx)
		return K:hitsKeep(mn, mx)
	end
	return Q
end

-- 작업 묶음 (ctx): K, Q, V, R, IR, BB (맵 파트 rec -> B AABB), 바닥 범위, 예약
local function newCtx(K: any, V: any): any
	local a = buildingYaw(V)
	local R = ANG(0, -a, 0)
	local IR = R:Inverse()
	local ctx: any = { K = K, V = V, R = R, IR = IR, Q = proxy(K, R), BB = {}, res = {}, yaw = a }
	for _, r in V.parts do
		local mn, mx = Kit.laabb(IR * r.lcf, r.part.Size)
		ctx.BB[r] = { mn, mx }
	end
	ctx.fx0, ctx.fx1, ctx.fz0, ctx.fz1 = V.x0, V.x1, V.z0, V.z1
	local fl = V.byName.Floor or V.byName.StockFloor
	if fl and fl[1] then
		local b = ctx.BB[fl[1]]
		ctx.fx0, ctx.fx1, ctx.fz0, ctx.fz1 = b[1].X, b[2].X, b[1].Z, b[2].Z
	end
	return ctx
end

-- 이름으로 맵 파트 찾기: { {rec, mn, mx} } (B 프레임), 정렬 = x 다음 z
local function all(ctx: any, name: string): { any }
	local out = {}
	for _, r in ctx.V.byName[name] or {} do
		local b = ctx.BB[r]
		table.insert(out, { r = r, mn = b[1], mx = b[2], c = (b[1] + b[2]) / 2, s = b[2] - b[1] })
	end
	table.sort(out, function(p, q)
		if math.abs(p.c.X - q.c.X) > 0.05 then
			return p.c.X < q.c.X
		end
		return p.c.Z < q.c.Z
	end)
	return out
end
local function one(ctx: any, name: string, pickFn: ((any) -> boolean)?): any?
	for _, e in all(ctx, name) do
		if not pickFn or pickFn(e) then
			return e
		end
	end
	return nil
end
local function hideName(ctx: any, name: string, pickFn: ((any) -> boolean)?)
	for _, e in all(ctx, name) do
		if not pickFn or pickFn(e) then
			Scan.hide(ctx.K.hidden, e.r.part)
		end
	end
end

-- B 상자가 keep 과 겹치나 (ignore = { kind = true })
local function keepHit(ctx: any, bmn: Vector3, bmx: Vector3, ignore: { [string]: boolean }?): string?
	local c = (bmn + bmx) / 2
	local rmn, rmx = Kit.laabb(ctx.R * CF(c), bmx - bmn)
	for _, k in ctx.V.keep do
		if (not ignore or not ignore[k.kind]) and Kit.overlap(rmn, rmx, k.min, k.max, 0.04) then
			return k.kind
		end
	end
	return nil
end

-- 바닥 소품 자리 (B): bcf = 바닥 가운데 (+Z 정면), size 전체 크기. keep · 맵 가구 · 우리 예약과 겹치면 false
local function spotB(ctx: any, bcf: CFrame, size: Vector3, pad: number?, ignore: { [string]: boolean }?, skipSolid: { [string]: boolean }?): boolean
	local p = pad or 0
	local c = bcf * CF(0, size.Y / 2, 0)
	local sz = size + V3(2 * p, 0, 2 * p)
	local bmn, bmx = Kit.laabb(c, sz)
	if bmn.X < ctx.fx0 - 0.05 or bmx.X > ctx.fx1 + 0.05 or bmn.Z < ctx.fz0 - 0.05 or bmx.Z > ctx.fz1 + 0.05 then
		ctx.K:note("gs25 spot out of room")
		return false
	end
	local kh = keepHit(ctx, bmn, bmx, ignore)
	if kh then
		ctx.K:note("gs25 spot keep " .. kh)
		return false
	end
	for _, s in ctx.V.solid do
		local b = ctx.BB[s]
		if b and not (skipSolid and skipSolid[s.name]) and not (ctx.hiddenSet and ctx.hiddenSet[s]) and Kit.overlap(bmn, bmx, b[1], b[2], 0.04) then
			ctx.K:note("gs25 spot solid " .. s.name)
			return false
		end
	end
	for _, q in ctx.res do
		if Kit.overlap(bmn, bmx, q[1], q[2], 0.02) then
			ctx.K:note("gs25 spot reserved")
			return false
		end
	end
	table.insert(ctx.res, { bmn, bmx })
	local rmn, rmx = Kit.laabb(ctx.R * c, sz)
	ctx.K:reserve(rmn, rmx, "gs25")
	return true
end

-- 맵 파트를 숨기고 그 자리를 spotB 가 다시 쓸 수 있게 기록
local function hideRec(ctx: any, e: any)
	Scan.hide(ctx.K.hidden, e.r.part)
	ctx.hiddenSet = ctx.hiddenSet or {}
	ctx.hiddenSet[e.r] = true
end

-- 글자판 (B dcf)
local function txt(ctx: any, name: string, w: number, h: number, dcf: CFrame, s: string, fg: Color3?, bg: Color3?, opts: any?): (BasePart, TextLabel)
	local o: any = opts or {}
	o.fg = fg or INK
	o.bg = bg
	return ctx.Q:text(name, w, h, dcf, s, o)
end

-- 월드 점 (B 점 -> 월드)
local function W(ctx: any, p: Vector3): Vector3
	return ctx.K.cf * (ctx.R * p)
end

-- 여닫이: B 프레임 경첩점 hingeB, 세로축. spec = Interact.swing spec
local function swingB(ctx: any, model: Model, hingeB: Vector3, angle: number, spec: any)
	return Interact.swing(ctx.K, model, W(ctx, hingeB), YA, angle, spec)
end

-- 공통 작은 소품 ---------------------------------------------------------------------------------------

-- 벽 포스터 (액자 없이 붙인 인쇄물 + 테이프 자국): dcf, w, h, 글자, 색
local function poster(ctx: any, dcf: CFrame, w: number, h: number, s: string, fg: Color3, bg: Color3, opts: any?)
	local Q = ctx.Q
	local o: any = opts or {}
	Q:plate("PosterBack", w, h, 0.02, dcf, lk(bg))
	if o.band then
		Q:plate("PosterBand", w, h * (o.bandH or 0.22), 0.025, dcf * CF(0, h / 2 - h * (o.bandH or 0.22) / 2, 0), lk(o.band))
	end
	txt(ctx, "PosterText", w * 0.9, h * (o.textH or 0.86), dcf * CF(0, (o.textY or 0) * h, 0.03), s, fg, nil, { font = o.font or F.GothamBold })
	if o.tape ~= false then
		for _, sx in { -1, 1 } do
			Q:plate("PosterTape", 0.34, 0.12, 0.01, dcf * CF(sx * (w / 2 - 0.12), h / 2 - 0.02, 0.03) * ANG(0, 0, sx * 0.5), lk(rgb(236, 232, 214), M.SmoothPlastic, { t = 0.25 }))
		end
	end
end

-- 천장에서 매다는 양면 사인: 중심 (x, yc, z), 폭 w, 높이 h, 앞면 = +Z
local function hangSign(ctx: any, x: number, z: number, w: number, title: string, sub: string, yc: number?)
	local Q, V = ctx.Q, ctx.V
	local h = 1.2
	local y = yc or 9.0
	local c = CF(x, y, z)
	Q:box("HangSign", V3(w, h, 0.1), c, L_BLUE)
	Q:box("HangSignEdge", V3(w + 0.06, 0.1, 0.14), c * CF(0, h / 2, 0), L_CYAN)
	Q:box("HangSignEdge", V3(w + 0.06, 0.06, 0.14), c * CF(0, -h / 2, 0), lk(GS_NAVY))
	for _, side in { 1, -1 } do
		local d = fc(V3(x, y, z + side * 0.05), V3(0, 0, side))
		txt(ctx, "HangSignText", w * 0.9, h * 0.52, d * CF(0, 0.13, 0), title, WHITE, nil, { font = F.GothamBlack, d = 0.02 })
		txt(ctx, "HangSignSub", w * 0.7, h * 0.2, d * CF(0, -0.36, 0), sub, rgb(190, 228, 250), nil, { font = F.GothamMedium, d = 0.02 })
	end
	for _, sx in { -1, 1 } do
		local rx = x + sx * (w / 2 - 0.3)
		Q:seg("HangSignWire", V3(rx, y + h / 2 + 0.05, z), V3(rx, V.H - 0.04, z), 0.04, L_CHROME)
		Q:disc("HangSignClip", 0.2, 0.05, CF(rx, V.H - 0.025, z), L_CHROME)
	end
end

-- 바 스툴 (창가 바): 크롬 기둥 + 원판 받침 + 발판 링 + 흑색 쿠션
local function barStool(ctx: any, p: Vector3, top: number)
	local Q = ctx.Q
	local base = CF(p)
	Q:disc("StoolBase", 1.2, 0.07, base * CF(0, 0.035, 0), L_CHROME)
	Q:vcyl("StoolPost", top - 0.35, 0.18, base * CF(0, (top - 0.35) / 2 + 0.05, 0), L_CHROME)
	Q:vcyl("StoolGas", 0.5, 0.26, base * CF(0, top - 0.6, 0), Look.blackMetal)
	Q:ring("StoolFootRing", base * CF(0, top * 0.38, 0) * ANG(PI / 2, 0, 0), 0.5, 0.07, 8, L_CHROME)
	for i = 0, 2 do
		local a = i * 2 * PI / 3 + 0.3
		Q:seg("StoolSpoke", base * V3(0, top * 0.38, 0), base * V3(math.cos(a) * 0.5, top * 0.38, math.sin(a) * 0.5), 0.05, L_CHROME)
	end
	Q:disc("StoolSeat", 1.25, 0.24, base * CF(0, top - 0.12, 0), lk(rgb(30, 32, 36), M.Leather))
	Q:disc("StoolPiping", 1.28, 0.04, base * CF(0, top - 0.2, 0), lk(GS_BLUE, M.Leather))
end

-- 유리문 냉동 · 냉장 쇼케이스 (벽 붙박이). pcf 바닥 가운데 (+Z 정면), w 폭, d 깊이, h 높이, nd 문 수,
-- fill(shelfCF, iw, idx) 선반 물건, header 글자. 반환 { doors = { {model, hingeB, side} } }
local function glassCase(ctx: any, pcf: CFrame, w: number, d: number, h: number, nd: number, header: string, fill: (CFrame, number, number) -> ())
	local Q = ctx.Q
	local body = lk(rgb(232, 234, 236), M.Metal)
	local out = { doors = {} }
	local iw = w - 0.3
	local ih = h - 1.6
	-- 몸체 (뒤 · 옆 · 위 · 아래)
	Q:box("CaseBack", V3(w, h, 0.12), pcf * CF(0, h / 2, -d / 2 + 0.06), body)
	for _, sx in { -1, 1 } do
		Q:box("CaseSide", V3(0.15, h, d), pcf * CF(sx * (w / 2 - 0.075), h / 2, 0), body)
	end
	Q:box("CaseTop", V3(w, 0.9, d), pcf * CF(0, h - 0.45, 0), body)
	Q:box("CaseKick", V3(w, 0.7, d), pcf * CF(0, 0.35, 0), lk(rgb(46, 48, 52), M.Metal))
	Q:plate("CaseVent", w * 0.7, 0.32, 0.02, pcf * CF(0, 0.35, d / 2), lk(rgb(80, 82, 86), M.DiamondPlate))
	-- 안쪽 (흰 라이너 + 빛)
	Q:box("CaseLiner", V3(iw, ih, 0.04), pcf * CF(0, 0.7 + ih / 2, -d / 2 + 0.14), lk(rgb(246, 248, 250)))
	local lamp = Q:box("CaseLamp", V3(iw - 0.2, 0.06, 0.12), pcf * CF(0, 0.7 + ih - 0.06, d / 2 - 0.45), Look.lampCool)
	ctx.Q:light(lamp, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 7, Brightness = 0.7, Angle = 120, Color = Look.coolLight })
	-- 선반 4단
	local ns = 4
	for i = 1, ns do
		local y = 0.7 + (i - 1) * (ih / ns) + 0.04
		Q:box("CaseShelf", V3(iw - 0.05, 0.05, d - 0.6), pcf * CF(0, y, -0.1), lk(rgb(200, 204, 208), M.Metal))
		Q:box("CaseShelfStrip", V3(iw - 0.05, 0.18, 0.03), pcf * CF(0, y - 0.04, d / 2 - 0.42), lk(rgb(250, 250, 248)))
		fill(pcf * CF(0, y + 0.025, -0.1), iw - 0.2, i)
	end
	-- 머리 광고판
	txt(ctx, "CaseHeader", w - 0.4, 0.58, pcf * CF(0, h - 0.45, d / 2 + 0.005), header, WHITE, GS_BLUE, { font = F.GothamBlack, glow = 1.15 })
	-- 문 (프레임 + 유리 + 손잡이), 경첩은 바깥쪽
	local dw = iw / nd
	for i = 1, nd do
		local x0 = -iw / 2 + (i - 1) * dw
		local side = if i <= nd / 2 then -1 else 1 -- 경첩 쪽 (-1 = 왼쪽)
		if nd == 1 then
			side = 1
		end
		local cy = 0.7 + ih / 2
		local zc = d / 2 + 0.05
		local model = Q:group("CaseDoor_" .. i, function()
			local c = pcf * CF(x0 + dw / 2, cy, zc)
			local fr = lk(rgb(56, 58, 62), M.Metal)
			Q:box("CaseDoorRail", V3(dw, 0.12, 0.1), c * CF(0, ih / 2 + 0.04, 0), fr)
			Q:box("CaseDoorRail", V3(dw, 0.12, 0.1), c * CF(0, -ih / 2 - 0.04, 0), fr)
			Q:box("CaseDoorStile", V3(0.1, ih + 0.2, 0.1), c * CF(-dw / 2 + 0.05, 0, 0), fr)
			Q:box("CaseDoorStile", V3(0.1, ih + 0.2, 0.1), c * CF(dw / 2 - 0.05, 0, 0), fr)
			Q:box("CaseDoorGlass", V3(dw - 0.18, ih, 0.04), c, { c = rgb(200, 226, 240), m = M.Glass, t = 0.7, r = 0.15 })
			Q:box("CaseDoorHandle", V3(0.07, ih * 0.55, 0.08), c * CF(-side * (dw / 2 - 0.22), 0, 0.12), L_CHROME)
			Q:box("CaseDoorHandleFoot", V3(0.07, 0.07, 0.12), c * CF(-side * (dw / 2 - 0.22), ih * 0.27, 0.06), L_CHROME)
			Q:box("CaseDoorHandleFoot", V3(0.07, 0.07, 0.12), c * CF(-side * (dw / 2 - 0.22), -ih * 0.27, 0.06), L_CHROME)
		end)
		local hx = x0 + (if side < 0 then 0 else dw)
		table.insert(out.doors, { model = model, hingeB = (pcf * CF(hx, 0, zc)).Position, side = side })
	end
	return out
end

-- 냉동 · 냉장 물건 채우기용 작은 상자 줄
local function packRow(ctx: any, at: CFrame, w: number, items: { any }, seed: number)
	local Q = ctx.Q
	local x = -w / 2
	local i = 0
	while x < w / 2 - 0.3 do
		i += 1
		local it = items[(i + seed) % #items + 1]
		local iw = it.w or 0.6
		if x + iw > w / 2 then
			break
		end
		local h = it.h or 0.6
		local dd = it.d or 0.8
		local c = at * CF(x + iw / 2, 0, 0)
		if it.kind == "cup" then
			Q:vcyl("IceCup", h, iw * 0.9, c * CF(0, h / 2, 0.1), { c = rgb(226, 240, 248), m = M.Glass, t = 0.35 })
			Q:disc("IceCupLid", iw * 0.92, 0.03, c * CF(0, h + 0.01, 0.1), lk(it.c))
		elseif it.kind == "bag" then
			Q:rbox("FrozenBag", V3(iw, h, dd), 0.08, c * CF(0, h / 2, 0) * ANG(0, PI / 2, 0), lk(it.c))
			Q:plate("FrozenBagLabel", iw * 0.7, h * 0.4, 0.01, c * CF(0, h * 0.55, dd / 2), lk(it.c2 or WHITE))
		else
			Q:box("PackBox", V3(iw, h, dd), c * CF(0, h / 2, 0), lk(it.c))
			Q:plate("PackBoxLabel", iw * 0.8, h * 0.35, 0.01, c * CF(0, h * 0.6, dd / 2), lk(it.c2 or WHITE))
		end
		x += iw + 0.06
	end
end

-- 골판지 상자 (테이프 + 인쇄 라벨). bcf = 바닥 가운데 (+Z = 라벨 면), size
local function carton(ctx: any, bcf: CFrame, size: Vector3, label: string?, ink: Color3?, seed: number?)
	local Q = ctx.Q
	local s = seed or 1
	local c = bcf * CF(0, size.Y / 2, 0)
	local tone = rnd(s, 3)
	local body = lk(rgb(182 + math.floor(tone * 26), 140 + math.floor(tone * 24), 94 + math.floor(tone * 20)), M.Cardboard)
	Q:box("Carton", size, c, body)
	Q:box("CartonTape", V3(size.X + 0.01, 0.02, size.Z * 0.18), c * CF(0, size.Y / 2 + 0.005, 0), lk(rgb(200, 170, 120), M.SmoothPlastic, { t = 0.2 }))
	if label then
		txt(ctx, "CartonLabel", size.X * 0.82, math.min(size.Y * 0.42, 0.75), c * CF(0, size.Y * 0.08, size.Z / 2), label, ink or GS_BLUE, nil, { font = F.GothamBlack, d = 0.01 })
	end
end

---------------------------------------------------------------------------------------------------
-- 매장 (gs25)
---------------------------------------------------------------------------------------------------

-- 담배장: 갑 하나하나 + 선반 + 가격표 + 전자담배 칸 + 라이터
local function cigaretteWall(ctx: any)
	local Q = ctx.Q
	local cab = one(ctx, "CigaretteCabinet")
	if not cab then
		return
	end
	hideName(ctx, "CigarettePacks")
	local x0, x1 = cab.mn.X + 0.38, cab.mx.X - 0.45
	local zf = cab.mx.Z -- 캐비닛 앞면 (+Z)
	local brands = {
		{ rgb(250, 250, 250), rgb(40, 90, 170), "에쎄" },
		{ rgb(250, 250, 250), rgb(200, 30, 36), "말보로" },
		{ rgb(244, 240, 230), rgb(196, 160, 80), "골드" },
		{ rgb(110, 60, 150), rgb(250, 250, 250), "레종" },
		{ rgb(30, 60, 140), rgb(240, 240, 240), "디스" },
		{ rgb(250, 250, 250), rgb(28, 40, 80), "던힐" },
		{ rgb(150, 196, 230), rgb(250, 250, 250), "메비우스" },
		{ rgb(24, 24, 26), rgb(196, 160, 80), "보헴" },
		{ rgb(250, 250, 250), rgb(230, 120, 30), "더원" },
		{ rgb(236, 200, 60), rgb(120, 70, 30), "카멜" },
	}
	local warn = { rgb(70, 52, 48), rgb(96, 40, 36), rgb(54, 60, 66), rgb(120, 90, 70) }
	local xe = x1 - 1.75 -- 오른쪽 1.75 = 전자담배 칸
	local pitch = 0.47
	local n = math.floor((xe - x0) / pitch)
	local prices = {}
	for r = 0, 5 do
		local y = 4.45 + r * 0.8
		-- 선반 (아크릴) + 앞 턱 + 가격표 띠
		Q:box("CigShelf", V3(x1 - x0 + 0.2, 0.05, 0.36), CF((x0 + x1) / 2, y - 0.025, zf + 0.2), lk(rgb(236, 238, 240), M.SmoothPlastic, { t = 0.1 }))
		Q:box("CigLip", V3(x1 - x0 + 0.2, 0.14, 0.03), CF((x0 + x1) / 2, y + 0.05, zf + 0.39), lk(rgb(220, 230, 236), M.Glass, { t = 0.55 }))
		table.clear(prices)
		for i = 0, n - 1 do
			local b = brands[(i * 3 + r * 7) % #brands + 1]
			local x = x0 + pitch * (i + 0.5)
			local c = CF(x, y + 0.3, zf + 0.16)
			Q:box("CigPack", V3(0.4, 0.6, 0.2), c, lk(b[1]))
			Q:box("CigPackWarn", V3(0.4, 0.17, 0.205), c * CF(0, 0.21, 0), lk(warn[(i + r) % #warn + 1]))
			Q:box("CigPackBand", V3(0.4, 0.07, 0.205), c * CF(0, -0.02, 0), lk(b[2]))
			table.insert(prices, if (i + r) % 5 == 0 then "4,800" else "4,500")
		end
		txt(ctx, "CigPrice", xe - x0, 0.13, fc(V3((x0 + xe) / 2, y - 0.09, zf + 0.405), ZA), table.concat(prices, "   "), INK, rgb(252, 252, 250), { font = F.GothamBold, d = 0.01 })
		-- 전자담배 칸
		local ex = xe + 0.1
		if r >= 4 then
			-- 기기 상자 (일루마 · 글로 · 릴)
			local devs = { { rgb(236, 238, 240), rgb(40, 110, 160) }, { rgb(30, 40, 70), rgb(240, 240, 240) }, { rgb(150, 154, 160), rgb(250, 250, 250) } }
			for j = 0, 2 do
				local d = devs[(j + r) % 3 + 1]
				local c = CF(ex + 0.27 + j * 0.55, y + 0.33, zf + 0.17)
				Q:box("ECigBox", V3(0.5, 0.66, 0.24), c, lk(d[1]))
				Q:box("ECigBoxStripe", V3(0.5, 0.1, 0.245), c * CF(0, -0.12, 0), lk(d[2]))
			end
		elseif r >= 1 then
			local sticks = { rgb(236, 160, 40), rgb(40, 170, 160), rgb(120, 70, 160), rgb(230, 220, 70), rgb(60, 120, 200), rgb(90, 170, 90) }
			for j = 0, 4 do
				local c = CF(ex + 0.16 + j * 0.33, y + 0.24, zf + 0.15)
				Q:box("StickPack", V3(0.28, 0.48, 0.18), c, lk(WHITE))
				Q:box("StickPackColor", V3(0.28, 0.24, 0.185), c * CF(0, -0.06, 0), lk(sticks[(j + r * 2) % #sticks + 1]))
			end
		else
			-- 라이터 줄
			local lc = { RED, YEL, rgb(40, 160, 70), rgb(40, 110, 220), rgb(240, 110, 170), rgb(250, 140, 30), rgb(120, 70, 190) }
			for j = 0, 9 do
				Q:box("Lighter", V3(0.12, 0.42, 0.08), CF(ex + 0.08 + j * 0.16, y + 0.21, zf + 0.15), lk(lc[j % #lc + 1], M.SmoothPlastic, { t = 0.15 }))
				Q:box("LighterCap", V3(0.12, 0.06, 0.08), CF(ex + 0.08 + j * 0.16, y + 0.45, zf + 0.15), L_CHROME)
			end
		end
		txt(ctx, "CigPrice", 1.6, 0.13, fc(V3(ex + 0.82, y - 0.09, zf + 0.405), ZA), if r >= 4 then "기기 문의" elseif r >= 1 then "4,800   4,800   4,800" else "라이터 500원", INK, rgb(252, 252, 250), { font = F.GothamBold, d = 0.01 })
	end
	-- 칸막이 (일반 / 전자담배) + 위 LED 조명
	Q:box("CigDivider", V3(0.05, 4.9, 0.4), CF(xe + 0.05, 6.75, zf + 0.2), lk(rgb(30, 30, 34)))
	local led = Q:box("CigLED", V3(x1 - x0, 0.05, 0.08), CF((x0 + x1) / 2, 9.22, zf + 0.35), Look.lampCool)
	Q:light(led, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 7, Brightness = 0.55, Angle = 110, Color = Look.coolLight })
	-- 담배장 아래 안내 (신분증)
	txt(ctx, "CigNotice", 3.2, 0.24, fc(V3(x1 - 1.6, 4.27, zf + 0.42), ZA), "만 19세 미만 판매 금지 · 신분증 확인", WHITE, RED, { font = F.GothamBold, d = 0.01 })
end

-- 카페25 머신 (맵 CoffeeMachine 자리, 계산대 뒤)
local function cafe25(ctx: any)
	local Q, K = ctx.Q, ctx.K
	local cm = one(ctx, "CoffeeMachine")
	if not cm then
		return
	end
	hideRec(ctx, cm)
	local mn, mx = cm.mn, cm.mx
	local w, d = mx.X - mn.X, mx.Z - mn.Z
	local cx, cz, y0 = (mn.X + mx.X) / 2, (mn.Z + mx.Z) / 2, mn.Y
	local base = CF(cx, y0, cz) -- +Z = 손님 쪽
	local body = lk(rgb(34, 36, 40), M.Metal)
	Q:box("Cafe25Body", V3(w - 0.1, 2.15, d - 0.2), base * CF(0, 1.1, -0.1), body)
	for _, sx in { -1, 1 } do
		Q:box("Cafe25Side", V3(0.05, 2.15, d - 0.25), base * CF(sx * (w / 2 - 0.05), 1.1, -0.1), Look.brushed)
	end
	-- 원두 호퍼 2 (투명 + 원두)
	for j, hx in { -0.45, 0.45 } do
		Q:box("Cafe25Hopper", V3(0.8, 0.5, 0.9), base * CF(hx, 2.45, -0.3), { c = rgb(220, 230, 236), m = M.Glass, t = 0.55 })
		Q:box("Cafe25Beans", V3(0.72, if j == 1 then 0.34 else 0.22, 0.82), base * CF(hx, if j == 1 then 2.37 else 2.31, -0.3), lk(rgb(80, 48, 30), M.Sand))
		Q:box("Cafe25HopperLid", V3(0.84, 0.06, 0.94), base * CF(hx, 2.73, -0.3), Look.plasticBlack)
	end
	-- 앞면: 화면 + 로고 + 추출부 + 컵 받침
	local fz = cz + d / 2 - 0.2 + (d - 0.2) / 2 - (d - 0.2) / 2 -- 앞면 z (몸체 앞)
	fz = (base * CF(0, 0, -0.1 + (d - 0.2) / 2)).Position.Z
	local front = fc(V3(cx, y0, fz), ZA)
	Q:plate("Cafe25Bezel", 1.05, 0.72, 0.03, front * CF(0.35, 1.72, 0), Look.plasticBlack)
	local scr = Q:plate("Cafe25Screen", 0.92, 0.6, 0.02, front * CF(0.35, 1.72, 0.03), lk(rgb(20, 60, 110), M.Neon, { t = 0.25 }))
	local _, scrLabel = txt(ctx, "Cafe25ScreenText", 0.86, 0.5, front * CF(0.35, 1.72, 0.055), "아메리카노\nHOT 1,200원", WHITE, nil, { font = F.GothamBold, d = 0.005, glow = 1.4 })
	txt(ctx, "Cafe25Logo", 0.9, 0.3, front * CF(-0.62, 1.86, 0.02), "café25", WHITE, nil, { font = F.GothamBlack, d = 0.01 })
	Q:plate("Cafe25LogoLine", 0.8, 0.04, 0.02, front * CF(-0.62, 1.66, 0), L_CYAN)
	Q:plate("Cafe25Bay", 1.5, 1.15, 0.02, front * CF(0, 0.75, 0.0), lk(rgb(18, 18, 20), M.Metal))
	Q:box("Cafe25Spout", V3(0.6, 0.22, 0.35), front * CF(0, 1.22, 0.18), Look.brushed)
	for _, sx in { -0.12, 0.12 } do
		Q:vcyl("Cafe25Nozzle", 0.14, 0.07, front * CF(sx, 1.05, 0.22), L_CHROME)
	end
	Q:box("Cafe25Tray", V3(1.3, 0.08, 0.55), front * CF(0, 0.12, 0.26), lk(rgb(150, 154, 158), M.DiamondPlate))
	Q:vcyl("Cafe25Cup", 0.62, 0.42, front * CF(0, 0.47, 0.26), lk(rgb(248, 246, 240)))
	Q:vcyl("Cafe25CupSleeve", 0.24, 0.44, front * CF(0, 0.45, 0.26), lk(rgb(150, 100, 60), M.Cardboard))
	-- 컵 쌓기 (위)
	Q:vcyl("Cafe25CupStack", 0.5, 0.36, base * CF(0.9 - w / 2 + 0.2, 2.45, 0.3), lk(rgb(248, 246, 240)))
	Interact.screenLoop(K, scr, scrLabel, {
		{ text = "아메리카노\nHOT 1,200원", c = rgb(20, 60, 110) },
		{ text = "아이스 아메리카노\nICE 1,500원", c = rgb(16, 80, 120) },
		{ text = "카페라떼\n1,800원", c = rgb(70, 46, 30) },
		{ text = "추출 중...\n잠시만 기다려 주세요", c = rgb(30, 30, 34) },
	}, 4)
end

-- 핫바 · 찐빵 스티머 꾸밈 (HotBar 는 그대로) + 김
local function steamer(ctx: any)
	local Q, K = ctx.Q, ctx.K
	local g = one(ctx, "SteamerGlass")
	if not g then
		return
	end
	local mn, mx = g.mn, g.mx
	for _, x in { mn.X + 0.03, mx.X - 0.03 } do
		for _, z in { mn.Z + 0.03, mx.Z - 0.03 } do
			Q:box("SteamerPost", V3(0.06, mx.Y - mn.Y, 0.06), CF(x, (mn.Y + mx.Y) / 2, z), L_STEEL)
		end
	end
	for _, y in { mn.Y + 0.1, mn.Y + 0.6 } do
		Q:box("SteamerGrill", V3(mx.X - mn.X - 0.12, 0.02, mx.Z - mn.Z - 0.12), CF((mn.X + mx.X) / 2, y, (mn.Z + mx.Z) / 2), lk(rgb(190, 194, 198), M.Metal, { t = 0.35 }))
	end
	local warm = Q:box("SteamerLamp", V3(mx.X - mn.X - 0.2, 0.05, 0.1), CF((mn.X + mx.X) / 2, mx.Y - 0.05, (mn.Z + mx.Z) / 2), lk(rgb(255, 196, 120), M.Neon))
	-- 찐빵 (뒤쪽 줄, 핫바 뒤)
	local bz = mn.Z + 0.33
	for i = 0, 4 do
		local x = mn.X + 0.35 + i * 0.55
		local lower = i % 2 == 0
		local y = if lower then mn.Y + 0.27 else mn.Y + 0.77
		local col = if i % 3 == 0 then rgb(246, 242, 232) elseif i % 3 == 1 then rgb(196, 150, 96) else rgb(236, 226, 206)
		Q:ell("SteamBun", V3(0.48, 0.32, 0.46), CF(x, y, bz), lk(col))
	end
	txt(ctx, "SteamerPrice", mx.X - mn.X - 0.1, 0.2, fc(V3((mn.X + mx.X) / 2, mx.Y - 0.18, mx.Z + 0.01), ZA), "핫바 2,500  ·  찐빵 1,700  ·  호빵 1,900", WHITE, RED, { font = F.GothamBold, d = 0.01 })
	-- 김 (안에서 천천히 오름)
	local puffs = {}
	for i = 1, 3 do
		local p = Q:ball("SteamPuff", 0.36, CF(mn.X + 0.6 + i * 0.6, mn.Y + 0.6, mn.Z + 0.5), lk(WHITE, M.SmoothPlastic, { t = 0.82 }))
		table.insert(puffs, p)
	end
	local wcf = K.cf * ctx.R
	Interact.anim(K, function(t)
		for i, p in puffs do
			if p.Parent then
				local f = (t * 0.22 + i / 3) % 1
				p.CFrame = wcf * CF(mn.X + 0.6 + i * 0.6, mn.Y + 0.35 + f * (mx.Y - mn.Y - 0.6), mn.Z + 0.5 + math.sin(t + i) * 0.1)
				p.Transparency = 0.72 + f * 0.26
			end
		end
	end)
	return warm
end

-- 계산대 뒤 수납장 앞면 (BackCounter) + 직원 매트
local function backCounter(ctx: any)
	local Q = ctx.Q
	local bc = one(ctx, "BackCounter")
	if not bc then
		return
	end
	local zf = bc.mx.Z
	local x0, x1 = bc.mn.X + 0.1, bc.mx.X - 0.1
	local n = 4
	local w = (x1 - x0) / n
	for i = 0, n - 1 do
		local cx = x0 + w * (i + 0.5)
		local d = fc(V3(cx, 1.75, zf), ZA)
		Q:plate("BackDoor", w - 0.08, 2.5, 0.03, d, lk(rgb(214, 210, 200)))
		Q:plate("BackDoorPull", 0.5, 0.06, 0.05, d * CF(0, 1.0, 0.03), L_CHROME)
	end
	Q:plate("BackKick", x1 - x0, 0.4, 0.02, fc(V3((x0 + x1) / 2, 0.2, zf), ZA), lk(rgb(60, 62, 66)))
	-- 직원 매트 (피로 방지 고무)
	local ct = one(ctx, "CounterBody")
	if ct then
		local z = ct.mn.Z - 1.4
		Q:box("StaffMat", V3(6.6, 0.05, 2.4), CF((ct.mn.X + ct.mx.X) / 2 + 0.2, 0.025, z), lk(rgb(36, 38, 40), M.Rubber))
		for i = -5, 5 do
			Q:box("StaffMatRib", V3(0.08, 0.06, 2.3), CF((ct.mn.X + ct.mx.X) / 2 + 0.2 + i * 0.55, 0.03, z), lk(rgb(52, 54, 56), M.Rubber))
		end
	end
end

-- 계산대 앞면 스티커 · 껌 사탕 랙 (GumRack 자리)
local function counterFront(ctx: any)
	local Q = ctx.Q
	local cf = one(ctx, "CounterFront")
	if not cf then
		return
	end
	local zf = cf.mx.Z + 0.06 -- 안내판(CounterNotice) 앞
	Q:free(function()
		txt(ctx, "PayStickers", 6.4, 0.42, fc(V3((cf.mn.X + cf.mx.X) / 2 - 0.3, 0.78, zf), ZA), "삼성페이 · 카카오페이 · 네이버페이 · 제로페이 · VISA · Master · 교통카드", GS_NAVY, rgb(250, 250, 248), { font = F.GothamBold, d = 0.01 })
		Q:plate("PayStickersEdge", 6.5, 0.04, 0.012, fc(V3((cf.mn.X + cf.mx.X) / 2 - 0.3, 1.01, zf), ZA), L_CYAN)
		-- 껌 · 사탕 · 젤리 랙
		local gr = all(ctx, "GumRack")
		if #gr > 0 then
			for _, e in gr do
				hideRec(ctx, e)
			end
			local gx = gr[1].c.X - 0.25
			local z0 = cf.mx.Z + 0.07
			local depth = 0.5
			local wR = 1.1
			for _, sx in { -1, 1 } do
				Q:box("GumRackSide", V3(0.04, 2.5, depth), CF(gx + sx * wR / 2, 1.65, z0 + depth / 2), L_CHROME)
			end
			local gumCols = { rgb(40, 170, 90), rgb(60, 140, 220), rgb(240, 240, 240), rgb(230, 60, 120), rgb(250, 200, 30) }
			for t = 0, 3 do
				local y = 0.55 + t * 0.68
				Q:box("GumRackTier", V3(wR, 0.03, depth), CF(gx, y, z0 + depth / 2), lk(rgb(200, 204, 208), M.Metal))
				Q:box("GumRackLip", V3(wR, 0.1, 0.02), CF(gx, y + 0.05, z0 + depth), L_CHROME)
				for j = 0, 3 do
					local x = gx - wR / 2 + 0.15 + j * 0.27
					local c = gumCols[(j + t * 2) % #gumCols + 1]
					if t == 3 then
						-- 츄파춥스 (막대 사탕)
						Q:ball("Lollipop", 0.16, CF(x, y + 0.32, z0 + 0.25), lk(c))
						Q:seg("LollipopStick", V3(x, y + 0.02, z0 + 0.25), V3(x, y + 0.24, z0 + 0.25), 0.03, L_WHITEP)
					elseif t == 2 then
						Q:vcyl("XylitolBottle", 0.42, 0.2, CF(x, y + 0.23, z0 + 0.25), lk(c))
						Q:vcyl("XylitolCap", 0.06, 0.21, CF(x, y + 0.47, z0 + 0.25), L_WHITEP)
					else
						Q:rbox("JellyBag", V3(0.22, 0.42, 0.08), 0.04, CF(x, y + 0.23, z0 + 0.3), lk(c, M.SmoothPlastic, { r = 0.1 }))
					end
				end
			end
			txt(ctx, "GumRackHeader", wR, 0.3, fc(V3(gx, 3.0, z0 + depth), ZA), "껌 · 사탕 · 젤리", WHITE, RED, { font = F.GothamBlack, d = 0.02 })
		end
	end)
end

-- 계산대 옆 낮은 벽 (CashierSideWall) 손님 쪽: 로또 용지대 + 교통카드 충전 스티커
local function lottoStand(ctx: any)
	local Q = ctx.Q
	local sw = one(ctx, "CashierSideWall")
	if not sw then
		return
	end
	local xf = sw.mx.X -- 손님 쪽 면 (+X)
	local z = sw.mn.Z + 6.0
	local d = fc(V3(xf, 2.2, z), XA)
	Q:plate("LottoBox", 1.6, 1.0, 0.24, d, lk(rgb(250, 250, 250)))
	Q:plate("LottoBoxRim", 1.64, 0.08, 0.26, d * CF(0, 0.5, 0), lk(rgb(240, 120, 20)))
	txt(ctx, "LottoLabel", 1.4, 0.42, d * CF(0, 0.12, 0.25), "LOTTO 6/45\n연금복권720+", rgb(230, 90, 20), nil, { font = F.GothamBlack, d = 0.01 })
	for i = 0, 3 do
		Q:plate("LottoSlip", 0.28, 0.32, 0.01, d * CF(-0.5 + i * 0.33, 0.62, 0.12) * ANG(math.rad(-8), 0, 0), lk(if i % 2 == 0 then rgb(250, 210, 220) else rgb(250, 250, 236)))
	end
	Q:seg("LottoPen", (d * CF(0.62, -0.25, 0.3)).Position, (d * CF(0.62, 0.15, 0.3)).Position, 0.05, lk(RED))
	txt(ctx, "TmoneySticker", 1.5, 0.75, fc(V3(xf, 1.0, z), XA) * CF(0, 0, 0.005), "교통카드 충전\n캐시비 · 티머니", WHITE, rgb(30, 150, 90), { font = F.GothamBold, d = 0.01 })
	txt(ctx, "SideNotice", 1.8, 0.6, fc(V3(xf, 1.0, sw.mn.Z + 2.6), XA) * CF(0, 0, 0.005), "택배 접수 · 픽업\n계산대로 오세요", WHITE, GS_BLUE, { font = F.GothamBold, d = 0.01 })
end

-- 계산대 안 택배 선반 + 저울 + 송장 프린터 (CashierSideWall 안쪽)
local function parcelShelf(ctx: any)
	local Q = ctx.Q
	local sw = one(ctx, "CashierSideWall")
	local bc = one(ctx, "BackCounter")
	if not sw or not bc then
		return
	end
	local w, d, h = 1.2, 1.9, 4.0
	local cx = sw.mn.X - 0.08 - w / 2
	local cz = bc.mx.Z + 0.15 + d / 2
	local pcfS = pf(V3(cx, 0, cz), -XA) -- 정면 = 계산대 안쪽 (-X)
	if not spotB(ctx, pcfS, V3(d, h, w), 0) then
		return
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Q:box("ParcelPost", V3(0.08, h, 0.08), pcfS * CF(sx * (d / 2 - 0.04), h / 2, sz * (w / 2 - 0.04)), L_CHROME)
		end
	end
	local boxes = { { 0.9, 0.6, 0.7 }, { 0.7, 0.45, 0.6 }, { 0.6, 0.5, 0.5 } }
	for t = 0, 2 do
		local y = 0.3 + t * 1.3
		Q:box("ParcelShelf", V3(d, 0.05, w), pcfS * CF(0, y, 0), lk(rgb(200, 204, 208), M.DiamondPlate))
		local x = -d / 2 + 0.1
		for j, b in boxes do
			if x + b[1] > d / 2 then
				break
			end
			if (t + j) % 3 == 0 then
				Q:rbox("ParcelPoly", V3(b[1], 0.3, b[3] + 0.1), 0.08, pcfS * CF(x + b[1] / 2, y + 0.18, 0), lk(rgb(250, 214, 40)))
			else
				carton(ctx, pcfS * CF(x + b[1] / 2, y + 0.025, 0), V3(b[1], b[2], b[3]), nil, nil, t * 3 + j)
				Q:plate("ParcelLabel", b[1] * 0.6, b[2] * 0.4, 0.01, pcfS * CF(x + b[1] / 2, y + 0.025 + b[2] * 0.5, b[3] / 2), lk(WHITE))
			end
			x += b[1] + 0.06
		end
	end
	-- 위: 저울 + 표시기 + 송장 프린터
	local top = pcfS * CF(0, h, 0)
	Q:box("ParcelScaleTop", V3(d, 0.06, w), top * CF(0, -0.03, 0), lk(rgb(200, 204, 208), M.Metal))
	Q:box("ScaleBase", V3(0.95, 0.12, 0.9), top * CF(-0.35, 0.06, 0), lk(rgb(90, 94, 100), M.Metal))
	Q:box("ScalePlate", V3(0.85, 0.03, 0.8), top * CF(-0.35, 0.135, 0), L_STEEL)
	Q:box("ScaleDisplay", V3(0.5, 0.3, 0.1), top * CF(-0.35, 0.35, -0.38) * ANG(math.rad(-15), 0, 0), Look.plasticBlack)
	txt(ctx, "ScaleLCD", 0.4, 0.16, top * CF(-0.35, 0.36, -0.32) * ANG(math.rad(-15), 0, 0), "0.00kg", rgb(120, 255, 160), rgb(10, 30, 20), { font = F.GothamBold, d = 0.01 })
	Q:rbox("LabelPrinter", V3(0.55, 0.4, 0.6), 0.06, top * CF(0.55, 0.2, 0), Look.plasticWhite)
	Q:box("LabelPrinterRoll", V3(0.4, 0.02, 0.2), top * CF(0.55, 0.42, 0.32), Look.paper)
	txt(ctx, "ParcelSign", 1.4, 0.42, fc(V3(sw.mn.X - 0.01, h + 0.55, cz), XA) * CF(0, 0, 0.02), "택배 접수\n반값택배 · GS Postbox", WHITE, GS_BLUE, { font = F.GothamBold, d = 0.02 })
	Q:box("ParcelSignPost", V3(0.04, 0.5, 0.04), CF(sw.mn.X - 0.06, h + 0.1, cz), L_CHROME)
end

-- 왼쪽 벽 (계산대 쪽): CCTV 모니터 · 녹화 스티커 · 사업자등록증 · 담배소매인 지정서 · 시계 · 봉투 걸이 · 안내문
local function leftWallCounter(ctx: any)
	local Q, K = ctx.Q, ctx.K
	local wl = one(ctx, "WallLining")
	local xw = if wl then wl.mx.X else ctx.fx0 + 0.15
	local ct = one(ctx, "CounterBody")
	local bc = one(ctx, "BackCounter")
	local zc0 = if bc then bc.mx.Z else 2.2
	local zc1 = if ct then ct.mn.Z else 9.1
	local ztop = if ct then ct.mx.Z else 11.8
	local function wd(y: number, z: number): CFrame
		return fc(V3(xw, y, z), XA) -- +X 정면, 오른쪽 = -Z
	end
	Q:free(function()
		-- CCTV 모니터 (손님 줄 옆, 높이 6.3~8)
		local mz = ztop + 1.7
		local md = wd(7.15, mz)
		Q:plate("CCTVMonArm", 0.3, 0.5, 0.35, md * CF(0, 0, 0), L_DARK)
		Q:plate("CCTVMonBody", 2.7, 1.6, 0.16, md * CF(0, 0, 0.35), Look.plasticBlack)
		local scr = md * CF(0, 0.02, 0.52)
		Q:plate("CCTVMonScreen", 2.5, 1.42, 0.01, scr, lk(rgb(16, 20, 26), M.SmoothPlastic))
		local labels = {}
		local recDots = {}
		local scenes = {
			{ "CAM1 입구", rgb(60, 70, 80), rgb(110, 116, 120) },
			{ "CAM2 계산대", rgb(64, 60, 56), rgb(120, 110, 100) },
			{ "CAM3 음료", rgb(54, 66, 80), rgb(150, 170, 190) },
			{ "CAM4 창고", rgb(70, 66, 60), rgb(130, 120, 100) },
		}
		for i, sc in scenes do
			local qx = if i % 2 == 1 then -0.62 else 0.62
			local qy = if i <= 2 then 0.35 else -0.35
			local q = scr * CF(qx, qy, 0.012)
			Q:plate("CCTVView", 1.2, 0.66, 0.008, q, lk(sc[2]))
			Q:plate("CCTVViewFloor", 1.2, 0.26, 0.009, q * CF(0, -0.2, 0), lk(sc[3]))
			for s = 0, 1 do
				Q:plate("CCTVViewShelf", 0.12, 0.4, 0.01, q * CF(-0.35 + s * 0.5, 0.0, 0), lk(rgb(150, 150, 140)))
			end
			Q:plate("CCTVViewPerson", 0.1, 0.24, 0.011, q * CF(0.12 + i * 0.05, -0.12, 0), lk(rgb(30, 30, 34)))
			local _, lb = txt(ctx, "CCTVViewLabel", 0.9, 0.11, q * CF(-0.12, 0.26, 0.012), sc[1], WHITE, nil, { font = F.Code, align = "Left", d = 0.004 })
			table.insert(labels, lb)
			table.insert(recDots, Q:plate("CCTVRec", 0.06, 0.06, 0.006, q * CF(0.52, 0.27, 0.012), Look.ledRed))
		end
		txt(ctx, "CCTVBrand", 0.6, 0.08, md * CF(0, -0.74, 0.44), "HIKVISION", rgb(170, 170, 170), nil, { font = F.GothamBold, d = 0.004 })
		local lighting = game:GetService("Lighting")
		Interact.anim(K, function(t)
			local h = lighting.ClockTime
			local hh = math.floor(h)
			local mm = math.floor((h % 1) * 60)
			local ss = math.floor(t) % 60
			for i, lb in labels do
				if lb.Parent then
					lb.Text = string.format("%s  2026-10-16 %02d:%02d:%02d", scenes[i][1], hh, mm, ss)
				end
			end
			local on = math.floor(t * 1.2) % 2 == 0
			for _, p in recDots do
				if p.Parent then
					p.Transparency = if on then 0 else 1
				end
			end
		end)
		txt(ctx, "CCTVSticker", 2.4, 0.62, wd(5.75, mz), "CCTV 녹화 중\n24시간 녹화되고 있습니다", WHITE, rgb(30, 34, 40), { font = F.GothamBold, d = 0.01 })
		-- 계산대 안쪽 벽: 시계 · 사업자등록증 · 담배소매인 지정서 · 안내 · 봉투 걸이 · 인터폰
		local span = zc1 - zc0
		if span > 4 then
			local hr, mn = Props.clock(Q, wd(7.7, zc0 + 1.6), 1.3, { frame = lk(GS_BLUE, M.Metal) })
			-- 시계 바늘 (월드 기준 dcf 로 돌림)
			local wd0 = wd(7.7, zc0 + 1.6)
			local wcf = K.cf * ctx.R * wd0
			Interact.anim(K, function()
				if not hr.Parent then
					return
				end
				local h = lighting.ClockTime
				local m = (h % 1) * 60
				local ah = -((h % 12) / 12) * PI * 2
				local am = -(m / 60) * PI * 2
				hr.CFrame = wcf * ANG(0, 0, ah) * CF(0, 1.3 * 0.1, 0.145 + 0.01)
				mn.CFrame = wcf * ANG(0, 0, am) * CF(0, 1.3 * 0.16, 0.165 + 0.01)
			end)
			Props.frame(Q, wd(6.2, zc0 + 3.6), 1.1, 1.45, { frame = Look.goldMetal, text = "사업자등록증\n\nGS25 광안리점\n\n수영세무서", fg = rgb(40, 40, 40), textH = 0.9, border = 0.06, depth = 0.05 })
			Props.frame(Q, wd(6.2, zc0 + 5.0), 1.1, 1.45, { frame = Look.goldMetal, text = "담배소매인\n지정서\n\n부산광역시\n수영구청장", fg = rgb(40, 40, 40), textH = 0.9, border = 0.06, depth = 0.05 })
			poster(ctx, wd(5.1, zc0 + 1.6), 1.9, 1.15, "주류 · 담배 구매 시\n신분증 꼭 확인!\n위조 신분증 = 처벌", WHITE, RED, { font = F.GothamBlack })
			-- 봉투 걸이 (종량제 · 종이봉투 · 다회용)
			local bz = zc0 + 4.3
			local bd = wd(4.6, bz)
			Q:plate("BagRail", 2.6, 0.12, 0.12, bd, L_CHROME)
			local bags = { { rgb(250, 250, 250), rgb(30, 120, 200), "종량제 10L" }, { rgb(250, 250, 250), rgb(30, 150, 80), "종량제 20L" }, { rgb(196, 162, 118), rgb(110, 76, 40), "종이봉투" }, { rgb(0, 90, 170), WHITE, "다회용" } }
			for i, b in bags do
				local x = -0.98 + (i - 1) * 0.65
				Q:plate("BagHook", 0.04, 0.2, 0.25, bd * CF(x, -0.08, 0.05), L_CHROME)
				Q:plate("BagStack", 0.55, 1.1, 0.18, bd * CF(x, -0.68, 0.12), lk(b[1], if i == 3 then M.Cardboard else M.SmoothPlastic))
				Q:plate("BagPrint", 0.4, 0.3, 0.01, bd * CF(x, -0.62, 0.3), lk(b[2]))
			end
			txt(ctx, "BagPriceTag", 2.6, 0.38, wd(3.7, bz), "종량제 10L 290 · 20L 580 · 종이봉투 100~250원", INK, rgb(255, 236, 140), { font = F.GothamBold, d = 0.01 })
			txt(ctx, "BagNotice", 2.6, 0.3, wd(3.25, bz), "1회용 비닐봉투는 판매하지 않습니다", WHITE, rgb(30, 130, 80), { font = F.GothamBold, d = 0.01 })
			-- 인터폰 + 비상벨 (112 연결)
			local id = wd(4.8, zc0 + 0.6)
			Q:plate("Intercom", 0.45, 0.7, 0.1, id, Look.plasticWhite)
			Q:plate("IntercomGrille", 0.3, 0.22, 0.01, id * CF(0, 0.15, 0.1), lk(rgb(90, 90, 94)))
			Q:plate("PanicButton", 0.3, 0.3, 0.08, id * CF(0, -0.55, 0), lk(RED))
			txt(ctx, "PanicLabel", 0.4, 0.12, id * CF(0, -0.82, 0.01), "비상벨 112", INK, nil, { font = F.GothamBold, d = 0.005 })
		end
	end)
end

-- LED 전광판 (담배장 위)
local function ledTicker(ctx: any)
	local Q, K = ctx.Q, ctx.K
	local cp = one(ctx, "CashierPartition")
	local cab = one(ctx, "CigaretteCabinet")
	if not cp or not cab then
		return
	end
	local z = cp.mx.Z
	local x0, x1 = cab.mn.X + 0.2, cab.mx.X - 0.2
	local y = cab.mx.Y + 0.32
	if y + 0.3 > ctx.V.H - 0.05 then
		return
	end
	local c = CF((x0 + x1) / 2, y, z + 0.1)
	Q:box("LEDBoardCase", V3(x1 - x0, 0.56, 0.2), c, lk(rgb(24, 24, 26), M.Metal))
	local _, lb = txt(ctx, "LEDBoardText", x1 - x0 - 0.3, 0.4, fc(V3((x0 + x1) / 2, y, z + 0.2), ZA), "어서오세요 GS25 광안리점입니다", rgb(255, 80, 40), rgb(14, 8, 6), { font = F.GothamBold, d = 0.01, glow = 1.8 })
	Interact.screenLoop(K, nil, lb, {
		{ text = "어서오세요 GS25 광안리점입니다" },
		{ text = "반값택배 · 택배 접수 · 픽업 가능" },
		{ text = "카페25 아메리카노 HOT 1,200원 · ICE 1,500원" },
		{ text = "이번 달 1+1 · 2+1 행사 상품을 확인하세요" },
		{ text = "주류 · 담배 구매 시 신분증을 제시해 주세요" },
	}, 3.5)
end

-- 천장: 카테고리 행잉 사인 · 스피커 · CCTV 돔 · 볼록거울
local function ceilingSales(ctx: any)
	local Q = ctx.Q
	local g = all(ctx, "Plinth")
	local gx = {}
	for _, e in g do
		table.insert(gx, { x0 = e.mn.X, x1 = e.mx.X, z1 = e.mx.Z, z0 = e.mn.Z })
	end
	if #gx == 3 then
		local zc = gx[1].z1 - 1.75
		local chillerX = -19.15
		local ch = one(ctx, "ChillerPlinth")
		if ch then
			chillerX = ch.mx.X
		end
		hangSign(ctx, (chillerX + gx[1].x0) / 2 + 0.5, -4.0, 3.2, "도시락 · 간편식", "FRESH FOOD")
		hangSign(ctx, (gx[1].x1 + gx[2].x0) / 2 + 0.25, zc, 3.2, "라면 · 즉석식품", "RAMEN · INSTANT")
		hangSign(ctx, (gx[2].x1 + gx[3].x0) / 2 + 1.0, zc, 3.2, "과자 · 간식", "SNACK · CANDY")
		hangSign(ctx, gx[3].x1 + 4.2, zc, 3.2, "생활용품", "DAILY · HYGIENE")
		hangSign(ctx, gx[3].x1 + 4.2, gx[3].z0 - 3.3, 3.2, "음료 · 주류 · 냉동", "DRINKS · FROZEN")
	end
	-- 스피커 (천장 매입)
	for _, p in { V3(-13.5, 0, 19.0), V3(8.0, 0, -19.0), V3(17.0, 0, 7.0), V3(-2.0, 0, 3.0) } do
		local y = ctx.V.H
		Q:free(function()
			Q:disc("CeilSpeaker", 0.75, 0.04, CF(p.X, y - 0.02, p.Z), L_WHITEP)
			Q:disc("CeilSpeakerGrille", 0.6, 0.02, CF(p.X, y - 0.045, p.Z), lk(rgb(210, 210, 206), M.DiamondPlate))
		end)
	end
	-- 추가 CCTV 돔
	for _, p in { V3(12.0, 0, -14.0), V3(-8.0, 0, 22.0), V3(-20.0, 0, -24.5) } do
		Props.cctv(Q, p.X, p.Z)
	end
	-- 볼록거울 (천장 매달기, 비스듬히)
	for _, m in { { V3(-19.6, 9.4, -1.6), V3(0.7, -0.4, -0.6) }, { V3(18.6, 9.4, -21.0), V3(-0.7, -0.4, 0.6) } } do
		local p, n = m[1], m[2].Unit
		Q:seg("MirrorRod", p + V3(0, 0.5, 0), V3(p.X, ctx.V.H - 0.03, p.Z), 0.06, Look.blackMetal)
		local mcf = CFrame.lookAt(p, p + n)
		Q:make("Part", "ConvexMirrorRim", V3(0.14, 1.5, 1.5), mcf * ANG(0, PI / 2, 0), lk(rgb(240, 140, 20)), Enum.PartType.Cylinder)
		Q:ell("ConvexMirror", V3(1.38, 1.38, 0.36), mcf * CF(0, 0, -0.06), { c = rgb(210, 220, 226), m = M.Glass, r = 0.5, t = 0.05 })
	end
end

-- 진열대: 받침 걸레받이 (GS 블루) · 엔드캡 POP · 전자가격표 · 행사 꼬리표
local function gondolas(ctx: any)
	local Q = ctx.Q
	local tags = { { "1+1", WHITE, RED }, { "2+1", WHITE, rgb(240, 120, 20) }, { "NEW", WHITE, rgb(30, 150, 80) }, { "행사", INK, YEL }, { "할인", WHITE, GS_BLUE } }
	for gi, e in all(ctx, "Plinth") do
		local mn, mx = e.mn, e.mx
		-- 받침 띠
		for _, sx in { -1, 1 } do
			local x = if sx < 0 then mn.X else mx.X
			Q:plate("PlinthKick", mx.Z - mn.Z, 0.26, 0.02, fc(V3(x, 0.15, (mn.Z + mx.Z) / 2), V3(sx, 0, 0)), L_BLUE)
		end
		-- 엔드캡 위 POP (앞 끝, +Z)
		local cx = (mn.X + mx.X) / 2
		local txts = { "이번 주 행사\n1+1", "이번 주 행사\n2+1", "음료 2+1\n골라 담기" }
		local pz = mx.Z - 0.15
		for _, sx in { -1, 1 } do
			Q:box("POPPole", V3(0.05, 1.0, 0.05), CF(cx + sx * 1.2, 6.95, pz), L_CHROME)
		end
		Q:box("POPCard", V3(2.9, 1.15, 0.05), CF(cx, 7.45, pz), lk(YEL))
		txt(ctx, "POPText", 2.7, 1.0, fc(V3(cx, 7.45, pz + 0.025), ZA), txts[gi] or "행사", RED, nil, { font = F.GothamBlack, d = 0.01 })
		Q:box("POPCardEdge", V3(2.95, 0.08, 0.06), CF(cx, 8.0, pz), lk(RED))
	end
	-- 선반 가격 레일: 전자가격표 (ESL) + 꼬리표
	local rails = {}
	for _, r in all(ctx, "PriceRail") do
		if r.s.Z > 20 and r.r.part.Parent and r.r.part.Parent.Name == "Detail" then
			table.insert(rails, r)
		end
	end
	local plinths = all(ctx, "Plinth")
	local function sideOf(x: number): number?
		for _, p in plinths do
			local c = (p.mn.X + p.mx.X) / 2
			if math.abs(x - c) < 2.2 then
				return if x < c then -1 else 1
			end
		end
		return nil
	end
	local n = 0
	for ri, r in rails do
		local side = sideOf(r.c.X)
		local yc = r.c.Y
		if side and (math.abs(yc - 2.98) < 0.2 or math.abs(yc - 4.31) < 0.2) then
			local xf = if side < 0 then r.mn.X else r.mx.X
			local nrm = V3(side, 0, 0)
			local z = r.mn.Z + 1.2
			local k = 0
			while z < r.mx.Z - 0.6 do
				k += 1
				local bmn = V3(xf - 0.05, yc - 0.14, z - 0.2)
				local bmx = V3(xf + 0.05, yc + 0.14, z + 0.2)
				if not keepHit(ctx, bmn, bmx) then
					local d = fc(V3(xf, yc, z), nrm)
					Q:plate("ESL", 0.38, 0.26, 0.03, d, lk(rgb(236, 238, 236)))
					Q:plate("ESLScreen", 0.3, 0.16, 0.01, d * CF(0, 0.02, 0.03), lk(rgb(196, 200, 190)))
					n += 2
					-- 꼬리표 (쇼카드, 통로 쪽으로 튀어나옴): 레일마다 몇 개
					if (k + ri) % 4 == 0 then
						local tg = tags[(k + ri) % #tags + 1]
						local tz = z + 0.6
						local stemA = V3(xf, yc + 0.1, tz)
						local stemB = V3(xf + side * 0.35, yc + 0.1, tz)
						if not keepHit(ctx, V3(math.min(stemA.X, stemB.X) - 0.3, yc - 0.2, tz - 0.05), V3(math.max(stemA.X, stemB.X) + 0.3, yc + 0.45, tz + 0.05)) then
							Q:seg("TalkerStem", stemA, stemB, 0.03, lk(rgb(230, 236, 240), M.Glass, { t = 0.4 }))
							local tc = fc(V3(xf + side * 0.62, yc + 0.18, tz), ZA)
							txt(ctx, "Talker", 0.56, 0.42, tc, tg[1], tg[2], tg[3], { font = F.GothamBlack, d = 0.02 })
							n += 2
						end
					end
				end
				z += 3.0
			end
		end
	end
end

-- 냉장고 문 스티커 · 선반 가격표 (맵 Fridge 앞)
local function fridgeDress(ctx: any)
	local cats = {
		{ "생수", "이온음료", "탄산음료" },
		{ "커피 · 컵커피", "우유 · 두유", "주스" },
		{ "차 · 음료", "에너지 드링크", "요구르트" },
		{ "소주", "막걸리 · 전통주", "무알콜 · 탄산수" },
		{ "국산 맥주", "수입 맥주", "하이볼 · 와인" },
	}
	local prices = {
		{ "1,000 · 1,600 · 2,200", "1,900 · 2,000 · 2,300", "1,800 · 2,000 · 2,600" },
		{ "2,700 · 3,300 · 1,900", "1,700 · 2,700 · 1,600", "2,000 · 2,800 · 3,200" },
		{ "1,800 · 2,200 · 2,400", "2,200 · 2,600 · 2,800", "1,300 · 1,600 · 2,500" },
		{ "2,200 · 2,300 · 2,500", "2,000 · 3,500 · 4,500", "2,400 · 1,500 · 1,800" },
		{ "2,800 · 3,300 · 4캔 11,000", "4,500 · 4,900 · 4캔 11,000", "3,900 · 4,500 · 9,900" },
	}
	local doors = all(ctx, "FridgeDoor")
	for ui, e in doors do
		local zf = e.mx.Z
		local x0, x1 = e.mn.X, e.mx.X
		local sw = (x1 - x0) / 3
		for s = 0, 2 do
			local cx = x0 + sw * (s + 0.5)
			local cat = cats[ui] and cats[ui][s + 1] or "음료"
			txt(ctx, "FridgeDoorCat", sw - 0.4, 0.34, fc(V3(cx, 6.6, zf + 0.01), ZA), cat, WHITE, GS_BLUE, { font = F.GothamBold, d = 0.01 })
			if (ui + s) % 3 == 0 then
				txt(ctx, "FridgeDoorPromo", 0.62, 0.62, fc(V3(cx + sw / 2 - 0.55, 5.85, zf + 0.01), ZA), if (ui + s) % 2 == 0 then "1+1" else "2+1", WHITE, RED, { font = F.GothamBlack, d = 0.01 })
			end
		end
		txt(ctx, "FridgeDoorNote", 1.6, 0.18, fc(V3((x0 + x1) / 2, 1.2, zf + 0.01), ZA), "문을 꼭 닫아 주세요", rgb(40, 80, 140), rgb(236, 246, 252), { font = F.GothamMedium, d = 0.01 })
	end
	-- 안쪽 선반 가격표 (유리 너머)
	for _, ws in all(ctx, "WireShelf") do
		local ui = 1
		for i, e in doors do
			if ws.c.X > e.mn.X and ws.c.X < e.mx.X then
				ui = i
			end
		end
		local lvl = if ws.c.Y < 3 then 1 elseif ws.c.Y < 4.6 then 2 else 3
		local p = prices[ui] and prices[ui][lvl] or "1,500"
		txt(ctx, "FridgeShelfPrice", ws.s.X - 0.3, 0.13, fc(V3(ws.c.X, ws.mx.Y - 0.03, ws.mx.Z + 0.02), ZA), p .. "   ·   " .. p, INK, rgb(250, 250, 246), { font = F.GothamBold, d = 0.01 })
	end
end

-- 오픈 냉장 (도시락) 가격 · 할인 스티커
local function chillerDress(ctx: any)
	local rails = {}
	for _, r in all(ctx, "PriceRail") do
		if r.r.part.Parent and r.r.part.Parent.Name == "Detail" and r.s.Z > 10 and r.s.Z < 20 then
			table.insert(rails, r)
		end
	end
	local list = { "삼각김밥 1,300 · 1,500", "김밥 3,200 · 3,500", "샌드위치 3,400 · 햄버거 3,900", "도시락 4,900 · 5,900", "샐러드 4,500 · 디저트 3,200" }
	for i, r in rails do
		local d = fc(V3(r.mx.X, r.c.Y, r.c.Z), XA)
		txt(ctx, "ChillerPrice", r.s.Z - 1.0, 0.24, d * CF(0, 0, 0.005), list[(i - 1) % #list + 1], INK, rgb(252, 252, 248), { font = F.GothamBold, d = 0.01 })
		if i % 2 == 0 then
			txt(ctx, "ChillerSale", 0.9, 0.5, d * CF(r.s.Z / 2 - 1.0, 0.35, 0.02), "유통기한\n임박 30%", WHITE, RED, { font = F.GothamBlack, d = 0.01 })
		end
	end
end

-- 냉동고 (뒤쪽 오른쪽 구석, 문 여닫기)
local function freezer(ctx: any)
	local Q, K = ctx.Q, ctx.K
	local fr = all(ctx, "SidePanel")
	local xL = 18.0
	for _, e in fr do
		xL = math.max(xL, e.mx.X)
	end
	local bw = one(ctx, "BackWall", function(e)
		return e.s.X > 20
	end)
	local zb = if bw then bw.mx.Z else ctx.fz0
	local sl = one(ctx, "SideWallLining")
	local xR = if sl then sl.mn.X else ctx.fx1 - 0.15
	local w = xR - xL - 0.12
	local d = 3.4
	local h = 7.4
	local pcfF = pf(V3(xL + 0.06 + w / 2, 0, zb + d / 2 + 0.02), ZA)
	if w < 2.6 or not spotB(ctx, pcfF, V3(w, h, d), 0) then
		return
	end
	local items = {
		{ { kind = "bag", c = rgb(250, 250, 250), c2 = RED, w = 0.8, h = 0.5, d = 0.9 }, { kind = "bag", c = rgb(200, 30, 40), c2 = WHITE, w = 0.8, h = 0.5, d = 0.9 }, { kind = "box", c = rgb(240, 200, 60), c2 = RED, w = 0.9, h = 0.35, d = 1.0 } },
		{ { kind = "cup", c = rgb(30, 120, 200), w = 0.45, h = 0.55 }, { kind = "cup", c = rgb(240, 240, 240), w = 0.45, h = 0.55 } },
		{ { kind = "box", c = rgb(40, 60, 140), c2 = YEL, w = 0.7, h = 0.9, d = 0.5 }, { kind = "box", c = rgb(240, 120, 160), c2 = WHITE, w = 0.6, h = 0.9, d = 0.5 }, { kind = "box", c = rgb(120, 70, 40), c2 = rgb(250, 230, 200), w = 0.6, h = 0.9, d = 0.5 } },
		{ { kind = "bag", c = rgb(220, 236, 248), c2 = GS_BLUE, w = 1.2, h = 0.7, d = 1.2 } },
	}
	local case = glassCase(ctx, pcfF, w, d, h, 2, "냉동식품 · 얼음컵 · 아이스크림", function(at, iw, i)
		packRow(ctx, at, iw, items[i] or items[1], i * 2)
	end)
	txt(ctx, "FreezerTemp", 0.7, 0.24, pcfF * CF(w / 2 - 0.6, h - 1.05, d / 2 + 0.01), "-18°C", rgb(120, 220, 255), rgb(10, 20, 30), { font = F.GothamBold, d = 0.01, glow = 1.3 })
	for _, dr in case.doors do
		swingB(ctx, dr.model, dr.hingeB, dr.side * -1.45, { object = "냉동고", openText = "문 열기", closeText = "문 닫기", sound = "rbxasset://sounds/clickfast.wav" })
	end
end

-- 생활잡화 타공판 (오른쪽 벽 안쪽, ATM 과 냉동고 사이)
local function pegWall(ctx: any)
	local Q = ctx.Q
	local sl = one(ctx, "SideWallLining")
	local atm = one(ctx, "ATM")
	if not sl or not atm then
		return
	end
	local xw = sl.mn.X
	local z0 = math.max(sl.mn.Z, ctx.fz0) + 3.95
	local z1 = atm.mn.Z - 0.35
	local len = z1 - z0
	if len < 3 then
		return
	end
	local zc = (z0 + z1) / 2
	-- 아래 받침장 (화장지 묶음)
	local bd = 1.0
	local basePcf = pf(V3(xw - bd / 2, 0, zc), -XA)
	local okBase = spotB(ctx, basePcf, V3(len, 1.3, bd), 0)
	if okBase then
		Q:box("PegBase", V3(len, 1.2, bd), basePcf * CF(0, 0.6, 0), lk(rgb(232, 232, 228)))
		Q:plate("PegBaseKick", len, 0.3, 0.02, basePcf * CF(0, 0.15, bd / 2), L_BLUE)
		local cols = { rgb(250, 250, 250), rgb(236, 244, 252), rgb(250, 240, 246) }
		local x = -len / 2 + 0.2
		local i = 0
		while x < len / 2 - 1.2 do
			i += 1
			Q:rbox("TissuePack", V3(1.1, 0.8, 0.85), 0.12, basePcf * CF(x + 0.55, 1.6, 0) * ANG(0, PI / 2, 0), lk(cols[i % 3 + 1], M.SmoothPlastic))
			Q:plate("TissuePackLabel", 0.6, 0.3, 0.01, basePcf * CF(x + 0.55, 1.65, 0.43), lk(if i % 2 == 0 then rgb(40, 120, 200) else rgb(240, 120, 160)))
			x += 1.25
		end
	end
	-- 타공판 + 머리띠
	local d = fc(V3(xw, 4.1, zc), -XA)
	Q:plate("PegBoard", len, 4.6, 0.1, d, lk(rgb(240, 240, 236)))
	Q:plate("PegBoardFrame", len + 0.1, 0.1, 0.14, d * CF(0, 2.3, 0), L_CHROME)
	Q:plate("PegBoardFrame", len + 0.1, 0.1, 0.14, d * CF(0, -2.3, 0), L_CHROME)
	txt(ctx, "PegHeader", len, 0.55, d * CF(0, 2.75, 0.02), "생활잡화 · 충전기 · 핫팩 · 마스크", WHITE, GS_BLUE, { font = F.GothamBlack, d = 0.04 })
	local rows = {
		{ "충전케이블 C타입 9,900 · 고속충전기 15,900", { rgb(250, 250, 250), rgb(30, 30, 34) } },
		{ "보조배터리 29,000 · 이어폰 12,000", { rgb(40, 40, 46), rgb(250, 250, 250) } },
		{ "건전지 AA 4입 4,500 · AAA 4,500", { rgb(240, 130, 20), rgb(30, 30, 30) } },
		{ "핫팩 1,500 · 마스크 KF94 1,500", { rgb(230, 60, 40), rgb(250, 250, 250) } },
	}
	local ncol = math.floor(len / 1.15)
	local pitch = len / ncol
	for ri, row in rows do
		local y = 1.75 + (ri - 1) * 1.05 - 4.1
		for ci = 0, ncol - 1 do
			local x = -len / 2 + pitch * (ci + 0.5)
			local c = row[2][(ci + ri) % 2 + 1]
			Q:plate("PegHook", 0.03, 0.03, 0.5, d * CF(x, y + 0.42, 0.1), L_CHROME)
			Q:plate("Blister", 0.5, 0.72, 0.06, d * CF(x, y, 0.32), lk(c))
			Q:plate("BlisterLabel", 0.42, 0.18, 0.01, d * CF(x, y + 0.22, 0.38), lk(if c == rgb(250, 250, 250) then GS_BLUE else WHITE))
		end
		txt(ctx, "PegPrice", len - 0.4, 0.17, d * CF(0, y - 0.5, 0.11), row[1], INK, rgb(255, 245, 190), { font = F.GothamBold, d = 0.01 })
	end
end

-- ATM 칸막이 · 안내
local function atmBooth(ctx: any)
	local Q = ctx.Q
	local atm = one(ctx, "ATM")
	if not atm then
		return
	end
	local mn, mx = atm.mn, atm.mx
	for _, sz in { -1, 1 } do
		local z = if sz < 0 then mn.Z - 0.12 else mx.Z + 0.12
		local depth = mx.X - mn.X + 0.6
		local c = CF(mx.X - depth / 2, 3.4, z)
		Q:box("ATMPanel", V3(depth, 6.8, 0.1), c, lk(rgb(236, 240, 244), M.Glass, { t = 0.25 }))
		Q:box("ATMPanelEdge", V3(0.1, 6.8, 0.14), CF(mx.X - depth, 3.4, z), L_CHROME)
		txt(ctx, "ATMPanelSign", depth - 0.6, 0.9, fc(V3(mx.X - depth / 2, 5.6, z + sz * 0.06), V3(0, 0, sz)), "ATM\n365일 24시간", WHITE, GS_BLUE, { font = F.GothamBlack, d = 0.01 })
		txt(ctx, "ATMWarn", depth - 1.0, 0.75, fc(V3(mx.X - depth / 2 + 0.2, 3.7, z - sz * 0.06), V3(0, 0, -sz)), "보이스피싱 주의!\n모르는 사람에게 송금 금지", WHITE, rgb(200, 40, 40), { font = F.GothamBold, d = 0.01 })
	end
	-- 수수료 안내 (화면 옆) + 거울
	local front = mn.X - 0.01
	txt(ctx, "ATMFee", 0.75, 0.9, fc(V3(front, 4.9, mx.Z - 0.45), -XA), "수수료\n영업시간 내\n1,000원", INK, rgb(250, 250, 246), { font = F.GothamMedium, d = 0.01 })
	Q:ell("ATMMirror", V3(0.6, 0.6, 0.14), fc(V3(front + 0.02, 6.05, (mn.Z + mx.Z) / 2), -XA), { c = rgb(210, 220, 226), m = M.Glass, r = 0.5, t = 0.05 })
	Q:box("ATMFloorMat", V3(1.8, 0.04, mx.Z - mn.Z - 0.4), CF(mn.X - 1.0, 0.02, (mn.Z + mx.Z) / 2), lk(rgb(46, 48, 52), M.Rubber))
end

-- 온수기 · 전자레인지 · 국물 싱크 꾸밈
local function hotStation(ctx: any)
	local Q = ctx.Q
	local cab = one(ctx, "HotWaterCabinet")
	if not cab then
		return
	end
	local xf = cab.mn.X
	local function fd(y: number, z: number): CFrame
		return fc(V3(xf, y, z), -XA)
	end
	local zlen = cab.mx.Z - cab.mn.Z
	-- 분리수거 구멍 3 (앞면)
	local bins = { { "일반쓰레기", rgb(90, 90, 96) }, { "컵라면 용기", rgb(230, 120, 20) }, { "캔 · 페트", GS_BLUE } }
	for i, b in bins do
		local z = cab.mx.Z - zlen * (i - 0.5) / 3
		Q:plate("BinDoor", zlen / 3 - 0.14, 2.3, 0.03, fd(1.3, z), lk(rgb(214, 210, 200)))
		Q:plate("BinSlot", 1.4, 0.42, 0.04, fd(2.1, z), lk(rgb(20, 20, 22)))
		Q:plate("BinSlotRim", 1.5, 0.08, 0.05, fd(2.34, z), lk(b[2]))
		txt(ctx, "BinLabel", 1.6, 0.3, fd(1.6, z) * CF(0, 0, 0.04), b[1], WHITE, b[2], { font = F.GothamBold, d = 0.01 })
	end
	Q:plate("HotNosing", zlen, 0.08, 0.06, fd(3.36, (cab.mn.Z + cab.mx.Z) / 2), L_STEEL)
	-- 사용 안내 스티커
	txt(ctx, "MicroGuide", 2.2, 0.38, fd(2.9, cab.mn.Z + 2.4) * CF(0, 0, 0.04), "도시락 1분30초 · 삼각김밥 20초\n금속 용기 X", INK, rgb(255, 240, 160), { font = F.GothamBold, d = 0.01 })
	-- 국물 싱크 (맵 SoupSink 판 둘레 테 + 거름망)
	local ss = one(ctx, "SoupSink")
	if ss then
		local mn, mx = ss.mn, ss.mx
		local y = mx.Y + 0.05
		local cx, cz = (mn.X + mx.X) / 2, (mn.Z + mx.Z) / 2
		Q:box("SinkRim", V3(mx.X - mn.X, 0.1, 0.08), CF(cx, y, mn.Z + 0.04), L_STEEL)
		Q:box("SinkRim", V3(mx.X - mn.X, 0.1, 0.08), CF(cx, y, mx.Z - 0.04), L_STEEL)
		Q:box("SinkRim", V3(0.08, 0.1, mx.Z - mn.Z), CF(mn.X + 0.04, y, cz), L_STEEL)
		Q:box("SinkRim", V3(0.08, 0.1, mx.Z - mn.Z), CF(mx.X - 0.04, y, cz), L_STEEL)
		Q:box("SinkGrate", V3(0.9, 0.02, 0.6), CF(cx - 0.2, mx.Y + 0.01, cz), lk(rgb(90, 92, 96), M.DiamondPlate))
		txt(ctx, "SinkLabel", 1.3, 0.28, fd(2.9, cz) * CF(0, 0, 0.04), "↑ 국물 버리는 곳", WHITE, rgb(30, 130, 200), { font = F.GothamBold, d = 0.01 })
	end
	-- 전자레인지 조작부 (맵 Microwave 앞면 오른쪽, 덮지 않음)
	for _, mw in all(ctx, "Microwave") do
		local win = nil
		for _, e in all(ctx, "MicrowaveWindow") do
			if math.abs(e.c.Y - mw.c.Y) < 0.5 and math.abs(e.c.Z - mw.c.Z) < 2 then
				win = e
			end
		end
		local z0 = mw.mn.Z + 0.08
		local z1 = if win then win.mn.Z - 0.06 else mw.mn.Z + 0.75
		if z1 - z0 > 0.4 then
			local zc = (z0 + z1) / 2
			local d = fc(V3(mw.mn.X, mw.c.Y, zc), -XA)
			Q:plate("MicroPanel", z1 - z0, mw.s.Y - 0.2, 0.02, d, lk(rgb(60, 62, 66)))
			txt(ctx, "MicroLCD", z1 - z0 - 0.12, 0.2, d * CF(0, 0.38, 0.02), "1:30", rgb(120, 230, 255), rgb(10, 20, 30), { font = F.GothamBold, d = 0.005 })
			for i = 0, 5 do
				Q:plate("MicroKey", 0.14, 0.1, 0.02, d * CF(-0.11 + (i % 2) * 0.22, 0.1 - (i // 2) * 0.17, 0.02), lk(rgb(200, 202, 204)))
			end
			Q:plate("MicroStart", 0.36, 0.12, 0.02, d * CF(0, -0.45, 0.02), lk(rgb(40, 170, 90)))
		end
	end
	-- 온수기 물받이 + 주의 스티커
	local hw = one(ctx, "HotWaterMachine")
	if hw then
		Q:box("HotDripTray", V3(0.55, 0.06, 0.8), CF(hw.mn.X - 0.3, hw.mn.Y + 0.03, hw.c.Z - 0.2), lk(rgb(120, 124, 128), M.DiamondPlate))
		txt(ctx, "HotWarn", 1.5, 0.38, fd(2.9, hw.c.Z) * CF(0, 0, 0.04), "뜨거운 물 주의\n물 붓는 선까지", WHITE, RED, { font = F.GothamBold, d = 0.01 })
		-- 냅킨 · 젓가락 통 (레인지와 온수기 사이)
		local tz = hw.mn.Z - 0.35
		Q:box("NapkinDispenser", V3(0.5, 0.55, 0.4), CF(hw.mn.X + 0.35, hw.mn.Y + 0.275, tz), L_STEEL)
		Q:box("NapkinSlot", V3(0.02, 0.06, 0.3), CF(hw.mn.X + 0.09, hw.mn.Y + 0.4, tz), lk(WHITE))
	end
end

-- 창가 바 (StandingCounter): 스툴 · 발걸이 · 콘센트 · 안내 텐트
local function eatIn(ctx: any)
	local Q = ctx.Q
	local top = one(ctx, "StandingCounterTop")
	local base = one(ctx, "StandingCounterBase")
	if not top then
		return
	end
	local ty = top.mx.Y
	local xs = top.mn.X - 0.45
	local z = top.mn.Z + 1.0
	local k = 0
	while z < top.mx.Z - 0.6 do
		local p = V3(xs, 0, z)
		if spotB(ctx, CF(p), V3(1.3, ty - 0.9, 1.3), 0) then
			barStool(ctx, p, ty - 0.95)
			k += 1
		end
		z += 3.0
	end
	if base then
		Q:seg("FootRail", V3(base.mn.X - 0.25, 0.9, top.mn.Z + 0.4), V3(base.mn.X - 0.25, 0.9, top.mx.Z - 0.4), 0.12, L_CHROME)
		for zz = top.mn.Z + 1.5, top.mx.Z - 1.0, 5.5 do
			Q:seg("FootRailBracket", V3(base.mn.X - 0.25, 0.9, zz), V3(base.mn.X, 0.9, zz), 0.08, L_CHROME)
		end
	end
	-- 상판 앞 모서리 아래 콘센트 · USB
	for zz = top.mn.Z + 4.0, top.mx.Z - 2.0, 6.0 do
		local d = fc(V3(top.mn.X, ty - 0.22, zz), -XA)
		Q:plate("BarOutlet", 0.5, 0.16, 0.04, d * CF(0, 0, 0.0) * ANG(0, 0, 0), L_WHITEP)
		Q:plate("BarOutletUSB", 0.12, 0.05, 0.01, d * CF(0.12, 0, 0.04), lk(rgb(30, 30, 34)))
	end
	-- 상판 위 안내 텐트 2
	for i, zz in { top.mn.Z + 6.6, top.mn.Z + 13.6 } do
		local tc = CF(top.mx.X - 0.9, ty, zz)
		Q:box("TableTentBase", V3(0.5, 0.04, 0.3), tc * CF(0, 0.02, 0), lk(rgb(230, 236, 240), M.Glass, { t = 0.3 }))
		txt(ctx, "TableTent", 0.5, 0.7, fc(V3(top.mx.X - 0.9 - 0.05, ty + 0.4, zz), -XA) * ANG(math.rad(8), 0, 0), if i == 1 then "다 드신 용기는\n분리수거해\n주세요" else "와이파이\nGS25_FREE", INK, rgb(250, 250, 246), { font = F.GothamBold, d = 0.02 })
	end
	return k
end

-- 창 안쪽: 옆 창 GS25 띠 시트 + 포스터 2 + 앞 창 아래 띠
local function windowFilm(ctx: any)
	local Q = ctx.Q
	local panes = {}
	for _, e in all(ctx, "ShopWindow") do
		if e.s.Z > 4 and e.s.X < 0.6 then
			table.insert(panes, e) -- 옆 창
		end
	end
	for i, e in panes do
		local xg = e.mn.X - 0.01
		local d = fc(V3(xg, 4.7, e.c.Z), -XA)
		Q:plate("WindowBand", e.s.Z - 0.3, 0.3, 0.01, d, lk(rgb(240, 246, 250), M.SmoothPlastic, { t = 0.3 }))
		txt(ctx, "WindowBandText", e.s.Z - 0.6, 0.22, d * CF(0, 0, 0.012), "GS25      GS25      GS25", GS_BLUE, nil, { font = F.GothamBlack, d = 0.005 })
		if i == 4 or i == 5 then
			local s = if i == 4 then "카페25 원두커피\n아메리카노\nHOT 1,200원" else "반값택배\n1,800원부터\n접수 · 픽업"
			local bg = if i == 4 then rgb(70, 46, 30) else GS_BLUE
			poster(ctx, fc(V3(xg, 7.4, e.c.Z), -XA), 3.0, 3.0, s, WHITE, bg, { band = GS_CYAN, bandH = 0.12, tape = true, font = F.GothamBlack })
		end
	end
	-- 앞 유리 아래 띠 (창 keep 높이 3.4 아래)
	for _, e in all(ctx, "ShopWindow") do
		if e.s.X > 4 then
			local zg = e.mn.Z - 0.01
			local d = fc(V3(e.c.X, 3.0, zg), -ZA)
			Q:plate("FrontBand", e.s.X - 0.3, 0.42, 0.01, d, lk(GS_BLUE, M.SmoothPlastic, { t = 0.1 }))
			txt(ctx, "FrontBandText", e.s.X - 0.8, 0.3, d * CF(0, 0, 0.012), "GS25 광안리점 · 24시간 영업", WHITE, nil, { font = F.GothamBold, d = 0.005 })
		end
	end
end

-- 앞쪽 빈 바닥: 택배 키오스크 · 행사 평대 · 생수 묶음 · X배너 · 장바구니 · 우산 커버기 · 미끄럼 주의
local function frontZone(ctx: any)
	local Q, K = ctx.Q, ctx.K
	local top = one(ctx, "StandingCounterTop")
	-- 택배 키오스크 (창가 바 끝)
	if top then
		local kz = top.mx.Z + 1.3
		local kx = top.mx.X - 1.15
		local pcfK = pf(V3(kx, 0, kz), -XA)
		if spotB(ctx, pcfK, V3(2.1, 5.2, 1.7), 0) then
			Q:box("KioskBody", V3(2.1, 4.4, 1.5), pcfK * CF(0, 2.2, -0.1), lk(rgb(244, 246, 248)))
			Q:box("KioskSide", V3(2.14, 4.4, 0.06), pcfK * CF(0, 2.2, 0.66), L_BLUE)
			Q:box("KioskHead", V3(2.1, 0.8, 1.5), pcfK * CF(0, 4.8, -0.1), L_BLUE)
			txt(ctx, "KioskHeadText", 1.9, 0.6, pcfK * CF(0, 4.8, 0.66), "GS25 택배 접수", WHITE, nil, { font = F.GothamBlack, d = 0.01 })
			local scr = Q:box("KioskScreen", V3(1.3, 1.0, 0.04), pcfK * CF(0, 3.6, 0.67) * ANG(math.rad(-10), 0, 0), lk(rgb(30, 90, 170), M.Neon, { t = 0.3 }))
			local _, sl = txt(ctx, "KioskScreenText", 1.2, 0.8, pcfK * CF(0, 3.6, 0.7) * ANG(math.rad(-10), 0, 0), "반값택배 · 일반택배\n화면을 눌러 주세요", WHITE, nil, { font = F.GothamBold, d = 0.005, glow = 1.3 })
			Interact.screenLoop(K, scr, sl, {
				{ text = "반값택배 · 일반택배\n화면을 눌러 주세요", c = rgb(30, 90, 170) },
				{ text = "1. 무게 재기\n2. 송장 출력 · 붙이기", c = rgb(20, 110, 150) },
				{ text = "반값택배 1,800원~\n편의점 픽업", c = rgb(0, 120, 120) },
			}, 5)
			Q:box("KioskScale", V3(1.6, 0.1, 0.9), pcfK * CF(0, 2.0, 0.95), L_STEEL)
			Q:box("KioskScaleArm", V3(0.1, 0.5, 0.6), pcfK * CF(-0.75, 1.75, 0.95), L_STEEL)
			Q:box("KioskPrinterSlot", V3(0.7, 0.08, 0.04), pcfK * CF(0.45, 2.8, 0.67), lk(rgb(20, 20, 22)))
			Q:box("KioskCardSlot", V3(0.4, 0.06, 0.04), pcfK * CF(-0.45, 2.8, 0.67), lk(rgb(20, 20, 22)))
			txt(ctx, "KioskNote", 1.6, 0.35, pcfK * CF(0, 1.3, 0.69), "택배 상자 무게 20kg 이하", INK, rgb(255, 236, 140), { font = F.GothamBold, d = 0.01 })
		end
	end
	-- 행사 평대 (아이스크림 냉동고 오른쪽)
	local icf = one(ctx, "IceCreamFreezer")
	local baseZ = if icf then icf.c.Z else 20.5
	local pz = baseZ + 1.0
	local pcfP = pf(V3(5.0, 0, pz), ZA)
	if spotB(ctx, pcfP, V3(5.6, 3.2, 2.8), 0) then
		Q:box("PromoTableTop", V3(5.6, 0.12, 2.8), pcfP * CF(0, 2.3, 0), lk(rgb(240, 240, 236)))
		Q:box("PromoSkirt", V3(5.5, 2.2, 2.7), pcfP * CF(0, 1.12, 0), L_BLUE)
		Q:plate("PromoSkirtBand", 5.5, 0.3, 0.02, pcfP * CF(0, 1.9, 1.35), L_CYAN)
		txt(ctx, "PromoSkirtText", 4.8, 0.9, pcfP * CF(0, 1.0, 1.37), "2+1 행사 골라 담기", WHITE, nil, { font = F.GothamBlack, d = 0.01 })
		-- 상품 묶음: 라면 멀티팩 · 과자 박스 · 생수 소형
		local groups = {
			{ -1.8, function(c: CFrame)
				for i = 0, 5 do
					Q:rbox("RamenMulti", V3(1.1, 0.42, 0.75), 0.12, c * CF((i % 2) * 1.15 - 0.57, 0.21 + (i // 2) * 0.43, 0) * ANG(0, PI / 2, 0), lk(if i % 3 == 2 then rgb(240, 160, 30) else RED))
				end
			end },
			{ 0.2, function(c: CFrame)
				local cols = { rgb(250, 210, 40), rgb(60, 160, 220), rgb(230, 80, 120), rgb(120, 70, 40) }
				for i = 0, 5 do
					Q:box("SnackBox", V3(0.85, 0.6, 0.55), c * CF((i % 3) * 0.9 - 0.9, 0.3 + (i // 3) * 0.6, 0), lk(cols[i % #cols + 1]))
				end
			end },
			{ 2.0, function(c: CFrame)
				for i = 0, 8 do
					Q:vcyl("SmallWater", 0.75, 0.28, c * CF((i % 3) * 0.32 - 0.32, 0.38, (i // 3) * 0.32 - 0.32), { c = rgb(210, 230, 245), m = M.Glass, t = 0.4 })
					Q:vcyl("SmallWaterCap", 0.08, 0.14, c * CF((i % 3) * 0.32 - 0.32, 0.79, (i // 3) * 0.32 - 0.32), lk(GS_BLUE))
				end
			end },
		}
		for _, gp in groups do
			gp[2](pcfP * CF(gp[1], 2.36, 0))
		end
		Q:box("PromoPOPPole", V3(0.05, 1.3, 0.05), pcfP * CF(0, 2.98, -0.9), L_CHROME)
		txt(ctx, "PromoPOP", 1.4, 0.7, pcfP * CF(0, 3.95, -0.9), "2+1\n골라 담기", RED, YEL, { font = F.GothamBlack, d = 0.03 })
	end
	-- 생수 2L 6입 묶음 (팔레트처럼 쌓기)
	local pcfW = pf(V3(11.2, 0, pz + 0.2), ZA)
	if spotB(ctx, pcfW, V3(2.4, 2.8, 2.0), 0) then
		Q:box("WaterPallet", V3(2.4, 0.3, 2.0), pcfW * CF(0, 0.15, 0), lk(rgb(40, 90, 160), M.Plastic))
		for i = 0, 7 do
			local c = pcfW * CF((i % 2) * 1.15 - 0.575, 0.3 + (i // 4) * 1.15 + 0.55, ((i // 2) % 2) * 0.95 - 0.475)
			Q:box("Water6", V3(1.1, 1.1, 0.9), c, { c = rgb(200, 226, 242), m = M.Glass, t = 0.35, r = 0.1 })
			Q:box("Water6Band", V3(1.12, 0.28, 0.92), c * CF(0, 0.15, 0), lk(rgb(30, 110, 200)))
			Q:box("Water6Handle", V3(0.5, 0.04, 0.1), c * CF(0, 0.57, 0), lk(WHITE))
		end
		txt(ctx, "WaterPrice", 1.4, 0.55, pcfW * CF(0, 2.0, 1.02), "생수 2L × 6\n5,900원", RED, WHITE, { font = F.GothamBlack, d = 0.02 })
	end
	-- X 배너
	local pcfX = pf(V3(15.6, 0, pz + 1.6), ZA)
	if spotB(ctx, pcfX, V3(2.1, 5.6, 0.8), 0) then
		Q:seg("XBannerLeg", pcfX * V3(-0.8, 0, 0.3), pcfX * V3(0, 1.0, 0), 0.05, Look.blackMetal)
		Q:seg("XBannerLeg", pcfX * V3(0.8, 0, 0.3), pcfX * V3(0, 1.0, 0), 0.05, Look.blackMetal)
		Q:seg("XBannerLeg", pcfX * V3(0, 0, -0.35), pcfX * V3(0, 1.0, 0), 0.05, Look.blackMetal)
		Q:seg("XBannerX", pcfX * V3(-0.95, 0.5, -0.04), pcfX * V3(0.95, 5.4, -0.04), 0.04, Look.blackMetal)
		Q:seg("XBannerX", pcfX * V3(0.95, 0.5, -0.04), pcfX * V3(-0.95, 5.4, -0.04), 0.04, Look.blackMetal)
		Q:box("XBanner", V3(1.9, 4.9, 0.02), pcfX * CF(0, 2.95, 0), lk(WHITE, M.Fabric))
		Q:box("XBannerTop", V3(1.9, 1.1, 0.025), pcfX * CF(0, 4.85, 0), L_BLUE)
		txt(ctx, "XBannerHead", 1.7, 0.9, pcfX * CF(0, 4.85, 0.015), "10월 GS25\n행사", WHITE, nil, { font = F.GothamBlack, d = 0.005 })
		txt(ctx, "XBannerBody", 1.7, 2.6, pcfX * CF(0, 2.9, 0.015), "1+1\n2+1\n음료 · 과자 · 라면\n도시락 할인", RED, nil, { font = F.GothamBlack, d = 0.005 })
		txt(ctx, "XBannerFoot", 1.7, 0.5, pcfX * CF(0, 1.0, 0.015), "우리동네GS 앱 픽업", GS_BLUE, nil, { font = F.GothamBold, d = 0.005 })
	end
	-- 장바구니 쌓기 (자동문 오른쪽)
	local pcfB = pf(V3(-9.4, 0, 23.7), ZA)
	if spotB(ctx, pcfB, V3(1.7, 2.4, 1.2), 0) then
		Q:box("BasketStand", V3(1.7, 0.1, 1.2), pcfB * CF(0, 0.05, 0), lk(rgb(60, 62, 66), M.Metal))
		for i = 0, 6 do
			local y = 0.1 + i * 0.28
			Q:box("BasketRim", V3(1.64, 0.1, 1.12), pcfB * CF(0, y + 0.22, 0), lk(GS_BLUE, M.Plastic))
		end
		Q:box("BasketBody", V3(1.56, 1.9, 1.04), pcfB * CF(0, 1.06, 0), lk(dk(GS_BLUE, 0.15), M.Plastic))
		for _, sz in { -1, 1 } do
			Q:box("BasketSlot", V3(1.2, 0.9, 0.02), pcfB * CF(0, 1.1, sz * 0.53), lk(dk(GS_BLUE, 0.4), M.Plastic))
		end
		Q:box("BasketInside", V3(1.4, 0.04, 0.9), pcfB * CF(0, 2.03, 0), lk(dk(GS_BLUE, 0.5), M.Plastic))
		for _, sx in { -1, 1 } do
			Q:box("BasketHandle", V3(0.08, 0.06, 0.9), pcfB * CF(sx * 0.6, 2.1, 0), lk(rgb(30, 30, 34), M.Plastic))
		end
		txt(ctx, "BasketLogo", 0.9, 0.35, pcfB * CF(0, 1.3, 0.55), "GS25", WHITE, nil, { font = F.GothamBlack, d = 0.01 })
	end
	-- 우산 비닐 커버기 + 비닐우산 통 (상호작용)
	local pcfU = pf(V3(-7.5, 0, 23.8), ZA)
	if spotB(ctx, pcfU, V3(1.1, 3.4, 1.0), 0) then
		Q:box("UmbWrapBody", V3(1.0, 2.9, 0.8), pcfU * CF(0, 1.45, 0), L_STEEL)
		Q:box("UmbWrapTop", V3(1.04, 0.14, 0.84), pcfU * CF(0, 2.95, 0), L_BLUE)
		Q:box("UmbWrapSlot", V3(0.5, 0.04, 0.3), pcfU * CF(0, 3.03, 0), lk(rgb(20, 20, 22)))
		txt(ctx, "UmbWrapLabel", 0.86, 0.7, pcfU * CF(0, 2.1, 0.41), "우산 비닐\n커버", WHITE, GS_BLUE, { font = F.GothamBold, d = 0.01 })
		local sleeve = Q:box("UmbSleeve", V3(0.3, 0.05, 0.22), pcfU * CF(0, 3.04, 0), { c = rgb(236, 244, 250), m = M.SmoothPlastic, t = 0.5 })
		for i = 0, 2 do
			local bx = -0.25 + i * 0.25
			Q:seg("VinylUmbrella", pcfU * V3(bx, 0.2, -0.65), pcfU * V3(bx * 1.3, 2.6, -0.7), 0.22, { c = rgb(236, 240, 244), m = M.SmoothPlastic, t = 0.35 })
			Q:seg("VinylUmbrellaHandle", pcfU * V3(bx * 1.3, 2.6, -0.7), pcfU * V3(bx * 1.3, 3.0, -0.7), 0.06, lk(rgb(240, 240, 240)))
		end
		Q:vcyl("UmbrellaBucket", 1.0, 0.8, pcfU * CF(0, 0.5, -0.68), lk(rgb(200, 204, 208), M.Metal))
		txt(ctx, "UmbrellaPrice", 0.7, 0.3, pcfU * CF(0, 0.6, -0.27), "비닐우산 5,000", INK, YEL, { font = F.GothamBold, d = 0.01 })
		local wcf = K.cf * ctx.R
		local busy = false
		Interact.prompt(K, sleeve, {
			action = "비닐 씌우기",
			object = "우산 비닐 커버기",
			fn = function()
				if busy then
					return
				end
				busy = true
				local t0 = os.clock()
				local conn: any = nil
				conn = game:GetService("RunService").Heartbeat:Connect(function()
					local f = math.clamp((os.clock() - t0) / 1.2, 0, 1)
					if sleeve.Parent then
						sleeve.Size = V3(0.3, 0.05 + f * 2.2, 0.22)
						sleeve.CFrame = wcf * pcfU * CF(0, 3.04 + f * 1.1, 0)
					end
					if f >= 1 then
						conn:Disconnect()
						task.delay(1.5, function()
							if sleeve.Parent then
								sleeve.Size = V3(0.3, 0.05, 0.22)
								sleeve.CFrame = wcf * pcfU * CF(0, 3.04, 0)
							end
							busy = false
						end)
					end
				end)
			end,
		})
	end
	-- 미끄럼 주의 A-보드
	local pcfA = pf(V3(-5.6, 0, 24.0), ZA)
	if spotB(ctx, pcfA, V3(1.2, 2.7, 1.0), 0) then
		for _, sz in { -1, 1 } do
			local c = pcfA * CF(0, 1.3, sz * 0.22) * ANG(sz * 0.18, 0, 0)
			Q:box("WetSign", V3(1.1, 2.6, 0.05), c, lk(YEL, M.Plastic))
			txt(ctx, "WetSignText", 0.95, 1.4, fc((c * CF(0, -0.1, sz * 0.03)).Position, V3(0, 0, sz)) * ANG(sz * 0.18, 0, 0), "미끄럼\n주의\nCAUTION", INK, nil, { font = F.GothamBlack, d = 0.005 })
		end
		Q:box("WetSignHinge", V3(1.0, 0.1, 0.12), pcfA * CF(0, 2.62, 0), lk(rgb(40, 40, 44), M.Plastic))
	end
end

-- 빵 · 디저트 매대 (냉장 통로 끝, 계산대 칸막이 뒤)
local function breadRack(ctx: any)
	local Q = ctx.Q
	local cp = one(ctx, "CashierPartition")
	if not cp then
		return
	end
	local zb = cp.mn.Z - 0.12
	local w, d, h = 3.6, 1.5, 5.0
	local cx = -15.7
	local pcfR = pf(V3(cx, 0, zb - d / 2), -ZA)
	if not spotB(ctx, pcfR, V3(w, h, d), 0) then
		return
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Q:box("BreadPost", V3(0.07, h, 0.07), pcfR * CF(sx * (w / 2 - 0.04), h / 2, sz * (d / 2 - 0.04)), L_CHROME)
		end
	end
	local breadCols = { { rgb(250, 240, 220), rgb(230, 60, 60) }, { rgb(240, 220, 180), rgb(60, 120, 200) }, { rgb(200, 150, 90), rgb(240, 180, 30) }, { rgb(250, 246, 236), rgb(120, 70, 160) } }
	for t = 0, 3 do
		local y = 0.35 + t * 1.15
		Q:box("BreadShelf", V3(w - 0.1, 0.04, d - 0.1), pcfR * CF(0, y, 0) * ANG(math.rad(-6), 0, 0), lk(rgb(205, 208, 212), M.Metal))
		Q:box("BreadLip", V3(w - 0.1, 0.12, 0.03), pcfR * CF(0, y + 0.06, d / 2 - 0.05), L_CHROME)
		for i = 0, 4 do
			local bc = breadCols[(i + t) % #breadCols + 1]
			local c = pcfR * CF(-w / 2 + 0.42 + i * 0.68, y + 0.2, 0.1)
			Q:rbox("BreadBag", V3(0.6, 0.34, 0.9), 0.12, c * ANG(0, PI / 2, 0), { c = bc[1], m = M.SmoothPlastic, r = 0.08 })
			Q:plate("BreadLabel", 0.4, 0.16, 0.01, c * CF(0, 0.05, 0.45), lk(bc[2]))
		end
		txt(ctx, "BreadPrice", w - 0.4, 0.12, pcfR * CF(0, y - 0.04, d / 2 - 0.03), "크림빵 1,500 · 단팥빵 1,500 · 카스테라 2,200 · 롤케이크 3,500", INK, rgb(252, 252, 248), { font = F.GothamBold, d = 0.01 })
	end
	txt(ctx, "BreadHeader", w, 0.55, pcfR * CF(0, h + 0.05, d / 2 - 0.2), "빵 · 디저트", WHITE, rgb(200, 120, 40), { font = F.GothamBlack, d = 0.05 })
	-- 칸막이 뒷면 포스터
	local pd = fc(V3(cx, 7.3, cp.mn.Z), -ZA)
	poster(ctx, pd, 4.2, 2.6, "이달의 행사\n1+1 · 2+1 · 덤 증정\n우리동네GS 앱에서 확인", WHITE, GS_BLUE, { band = GS_CYAN, bandH = 0.14, font = F.GothamBlack })
	poster(ctx, fc(V3(cx + 3.2, 7.0, cp.mn.Z), -ZA), 1.6, 2.2, "GS Pay\n결제 시\n5% 적립", GS_NAVY, rgb(250, 250, 248), { band = YEL, bandH = 0.2, font = F.GothamBlack })
	Q:plate("PartitionBase", 7.0, 0.42, 0.05, fc(V3(cx + 0.6, 0.21, cp.mn.Z), -ZA), lk(rgb(60, 62, 66)))
end

-- 왼쪽 안쪽 구석: 옥내소화전 · 소화기 표지 · 비상벨
local function fireCorner(ctx: any)
	local Q = ctx.Q
	local wl = one(ctx, "WallLining")
	local xw = if wl then wl.mx.X else ctx.fx0 + 0.15
	local ch = one(ctx, "ChillerSide")
	local zEnd = if ch then ch.mn.Z else -17.6
	local z = ctx.fz0 + 3.2
	if zEnd - z < 3 then
		return
	end
	Q:free(function()
		local d = fc(V3(xw, 3.6, z), XA)
		Q:plate("HydrantBox", 2.4, 3.6, 0.32, d, lk(rgb(200, 30, 30), M.Metal))
		Q:plate("HydrantWindow", 1.5, 1.6, 0.02, d * CF(0, 0.4, 0.32), { c = rgb(220, 230, 236), m = M.Glass, t = 0.45 })
		Q:plate("HydrantHose", 1.2, 1.2, 0.01, d * CF(0, 0.4, 0.3), lk(rgb(230, 230, 220), M.Fabric))
		txt(ctx, "HydrantText", 1.8, 0.5, d * CF(0, -1.1, 0.33), "소화전", WHITE, nil, { font = F.GothamBlack, d = 0.01 })
		Q:plate("HydrantHandle", 0.1, 0.5, 0.06, d * CF(1.0, 0.0, 0.32), L_CHROME)
		Props.fireBell(Q, d * CF(0, 2.45, 0))
		txt(ctx, "HydrantSign", 2.0, 0.4, d * CF(0, 3.25, 0), "옥내소화전 · 비상벨", WHITE, RED, { font = F.GothamBold, d = 0.02 })
		local ext = one(ctx, "FireExtinguisher")
		if ext then
			txt(ctx, "ExtSign", 0.9, 0.42, fc(V3(xw, 2.6, ext.c.Z), XA), "소화기", WHITE, RED, { font = F.GothamBlack, d = 0.02 })
		end
	end)
end

-- 바닥 · 걸레받이 · 현관 매트
local function floorSales(ctx: any)
	local Q = ctx.Q
	local mat = one(ctx, "EntranceMat")
	if mat then
		hideRec(ctx, mat)
		local c = CF((mat.mn.X + mat.mx.X) / 2, 0, (mat.mn.Z + mat.mx.Z) / 2)
		local w, l = mat.s.X, mat.s.Z
		Q:free(function()
			Q:box("EntryMatEdge", V3(w + 0.1, 0.035, l + 0.1), c * CF(0, 0.0175, 0), L_RUBBER)
			Q:box("EntryMat", V3(w - 0.2, 0.05, l - 0.2), c * CF(0, 0.025, 0), lk(rgb(40, 52, 80), M.Fabric))
			Q:box("EntryMatBand", V3(w - 0.2, 0.052, 0.5), c * CF(0, 0.026, l / 2 - 0.6), lk(GS_BLUE, M.Fabric))
			txt(ctx, "EntryMatLogo", 2.6, 1.0, floorCF((c * CF(0, 0.055, -0.3)).Position, -ZA), "GS25", WHITE, nil, { font = F.GothamBlack, d = 0.005, free = true })
			txt(ctx, "EntryMatWelcome", 3.2, 0.42, floorCF((c * CF(0, 0.055, 0.85)).Position, -ZA), "WELCOME · 어서오세요", rgb(200, 220, 240), nil, { font = F.GothamBold, d = 0.005, free = true })
		end)
	end
	-- 걸레받이
	local wl = one(ctx, "WallLining")
	if wl then
		local xw = wl.mx.X
		local ch = one(ctx, "ChillerSide")
		local ct = one(ctx, "CounterTop")
		local spans = {}
		if ch then
			table.insert(spans, { ctx.fz0 + 0.1, ch.mn.Z - 0.05 })
		end
		local bc = one(ctx, "BackCounter")
		if bc and ct then
			table.insert(spans, { bc.mx.Z + 0.05, ct.mn.Z - 0.05 })
		end
		if ct then
			table.insert(spans, { ct.mx.Z + 0.05, ctx.fz1 - 0.6 })
		end
		Q:free(function()
			for _, s in spans do
				if s[2] - s[1] > 0.6 then
					Q:plate("Baseboard", s[2] - s[1], 0.42, 0.05, fc(V3(xw, 0.21, (s[1] + s[2]) / 2), XA), lk(rgb(60, 62, 66)))
				end
			end
		end)
	end
end

local function buildSales(K: any, V: any, S: any)
	local ctx = newCtx(K, V)
	local steps = {
		{ "floor", floorSales },
		{ "cig", cigaretteWall },
		{ "cafe25", cafe25 },
		{ "steamer", steamer },
		{ "backCounter", backCounter },
		{ "counterFront", counterFront },
		{ "lotto", lottoStand },
		{ "parcel", parcelShelf },
		{ "leftWall", leftWallCounter },
		{ "ticker", ledTicker },
		{ "ceiling", ceilingSales },
		{ "gondolas", gondolas },
		{ "fridge", fridgeDress },
		{ "chiller", chillerDress },
		{ "freezer", freezer },
		{ "peg", pegWall },
		{ "atm", atmBooth },
		{ "hot", hotStation },
		{ "eatIn", eatIn },
		{ "window", windowFilm },
		{ "front", frontZone },
		{ "bread", breadRack },
		{ "fire", fireCorner },
	}
	for _, st in steps do
		local n0 = #K.parts
		local ok, err = pcall(st[2], ctx)
		if not ok then
			K:note("gs25." .. st[1] .. " error: " .. tostring(err))
		else
			K:note(string.format("gs25.%s +%d", st[1], #K.parts - n0))
		end
	end
end

---------------------------------------------------------------------------------------------------
-- 창고 · 직원실 (stockroom)
---------------------------------------------------------------------------------------------------

-- 앵글 랙 다시 짓기: 기둥 (타공) · 앞뒤 빔 (주황) · 가새 · 메쉬 선반 · 박스 라벨
local function racks(ctx: any)
	local Q = ctx.Q
	local decks = all(ctx, "RackDeck")
	if #decks == 0 then
		return
	end
	-- 랙 묶기 (x 범위로)
	local groups = {}
	for _, e in decks do
		local g = nil
		for _, q in groups do
			if math.abs(q.x0 - e.mn.X) < 0.3 and math.abs(q.x1 - e.mx.X) < 0.3 then
				g = q
			end
		end
		if not g then
			g = { x0 = e.mn.X, x1 = e.mx.X, z0 = e.mn.Z, z1 = e.mx.Z, ys = {} }
			table.insert(groups, g)
		end
		table.insert(g.ys, e.mx.Y)
	end
	hideName(ctx, "RackPost")
	hideName(ctx, "RackDeck")
	local up = lk(rgb(30, 80, 160), M.Metal)
	local beam = lk(rgb(240, 120, 20), M.Metal)
	local deckL = lk(rgb(170, 174, 178), M.DiamondPlate)
	for _, g in groups do
		local H = 8.5
		local zs = { g.z0 + 0.15, g.z1 - 0.15 }
		for _, x in { g.x0 + 0.15, g.x1 - 0.15 } do
			for _, z in zs do
				Q:box("RackUpright", V3(0.28, H, 0.28), CF(x, H / 2, z), up)
				Q:box("RackFootPlate", V3(0.45, 0.05, 0.45), CF(x, 0.025, z), lk(rgb(40, 44, 50), M.Metal))
				for yy = 0.6, H - 0.4, 0.9 do
					Q:box("RackHoles", V3(0.29, 0.05, 0.06), CF(x, yy, z + (if z < (g.z0 + g.z1) / 2 then 0.12 else -0.12)), lk(rgb(16, 40, 90), M.Metal))
				end
			end
			-- 옆 프레임: 가로대 + 대각 가새
			for _, yy in { 0.4, H - 0.3 } do
				Q:bar("RackTie", V3(x, yy, zs[1]), V3(x, yy, zs[2]), 0.08, 0.12, up)
			end
			local ys = { 0.4, 2.4, 4.4, 6.4, H - 0.3 }
			for i = 1, #ys - 1 do
				local za, zb = if i % 2 == 1 then zs[1] else zs[2], if i % 2 == 1 then zs[2] else zs[1]
				Q:bar("RackBrace", V3(x, ys[i], za), V3(x, ys[i + 1], zb), 0.06, 0.08, up)
			end
		end
		table.sort(g.ys)
		for _, y in g.ys do
			for _, z in zs do
				Q:box("RackBeam", V3(g.x1 - g.x0 - 0.3, 0.32, 0.12), CF((g.x0 + g.x1) / 2, y - 0.2, z), beam)
			end
			Q:box("RackDeckMesh", V3(g.x1 - g.x0 - 0.4, 0.05, g.z1 - g.z0 - 0.2), CF((g.x0 + g.x1) / 2, y - 0.03, (g.z0 + g.z1) / 2), deckL)
			for k = 1, 3 do
				Q:box("RackDeckBar", V3(0.06, 0.1, g.z1 - g.z0 - 0.3), CF(g.x0 + (g.x1 - g.x0) * k / 4, y - 0.1, (g.z0 + g.z1) / 2), lk(rgb(120, 124, 128), M.Metal))
			end
			txt(ctx, "RackLoc", 0.9, 0.22, fc(V3(g.x0 + 0.9, y - 0.2, g.z1 - 0.15 + 0.06), ZA), string.format("%s-%d", if g.x0 < -10 then "A" elseif g.x0 < 0 then "B" else "C", math.floor(y)), INK, YEL, { font = F.GothamBold, d = 0.01 })
		end
		txt(ctx, "RackLimit", 1.6, 0.36, fc(V3((g.x0 + g.x1) / 2, H - 0.2, g.z1 - 0.15 + 0.08), ZA), "적재 하중 300kg / 단", WHITE, rgb(200, 40, 40), { font = F.GothamBold, d = 0.01 })
	end
	-- 박스 라벨 (맵 Carton 앞면)
	local labels = {
		{ "신라면 40입", RED }, { "삼다수 2L × 6", GS_BLUE }, { "코카콜라 500ml × 24", RED }, { "새우깡 20입", rgb(220, 120, 20) },
		{ "크리넥스 30롤", rgb(30, 120, 200) }, { "햇반 210g × 24", rgb(40, 140, 70) }, { "진라면 매운맛 40입", rgb(200, 40, 40) },
		{ "포카리스웨트 × 24", rgb(30, 100, 200) }, { "참이슬 후레쉬 × 20", rgb(30, 140, 90) }, { "카스 500ml × 24", rgb(20, 60, 160) },
		{ "바나나맛우유 × 24", rgb(220, 170, 20) }, { "컵라면 육개장 × 30", rgb(200, 60, 30) }, { "물티슈 × 12", rgb(30, 150, 160) },
		{ "삼각김밥 김 (냉장)", rgb(40, 40, 40) }, { "종이컵 1,000개", rgb(120, 90, 60) },
	}
	for i, e in all(ctx, "Carton") do
		local lb = labels[(i * 7) % #labels + 1]
		local w = e.s.X
		local hgt = e.s.Y
		local zf = e.mx.Z
		txt(ctx, "CartonLabel", w * 0.8, math.min(0.5, hgt * 0.3), fc(V3(e.c.X, e.c.Y + hgt * 0.12, zf + 0.005), ZA), lb[1], lb[2], WHITE, { font = F.GothamBold, d = 0.01 })
		Q:box("CartonTape", V3(w * 0.18, 0.02, e.s.Z + 0.01), CF(e.c.X, e.mx.Y + 0.005, e.c.Z), lk(rgb(200, 172, 120), M.SmoothPlastic, { t = 0.15 }))
		if i % 3 == 0 then
			Q:plate("CartonBarcode", 0.4, 0.22, 0.01, fc(V3(e.c.X + w * 0.25, e.mn.Y + 0.25, zf + 0.005), ZA), lk(WHITE))
		end
	end
end

-- 워크인 냉장고 (앞벽 = 매장 음료 냉장고 뒤): 단열 패널 · 문 (여닫기) · 안쪽 음료 박스 · 온도 표시
local function walkIn(ctx: any)
	local Q, K = ctx.Q, ctx.K
	local bw = one(ctx, "BackWall", function(e)
		return e.s.X > 20
	end)
	if not bw then
		return
	end
	local zw = bw.mn.Z -- 창고 쪽 벽면 (-Z 를 봄)
	local x0, x1 = -14.2, 3.4
	local tc = one(ctx, "TimeClock")
	if tc then
		x1 = math.min(x1, tc.mn.X - 0.5)
	end
	local d = 2.6
	local h = 8.6
	local z0 = zw - d
	-- 자리 확인 (창 keep 은 창고 앞벽이라 무시)
	local bmn, bmx = V3(x0, 0.1, z0), V3(x1, h, zw)
	if keepHit(ctx, bmn, bmx, { window = true }) then
		K:note("gs25 walkin keep")
		return
	end
	local wn = one(ctx, "WorkNotice")
	if wn then
		hideRec(ctx, wn)
	end
	table.insert(ctx.res, { bmn, bmx })
	local panel = lk(rgb(236, 238, 238), M.Metal)
	local w = x1 - x0
	local cx = (x0 + x1) / 2
	local doorW, doorH = 3.2, 7.2
	local dx = cx + 2.0 -- 문 가운데
	Q:free(function()
		-- 몸체: 앞판 (문 구멍 둘레) + 옆판 + 위판
		local fz = z0
		local function frontPanel(a: number, b: number, y0: number, y1: number)
			if b - a > 0.05 and y1 - y0 > 0.05 then
				Q:box("WalkInPanel", V3(b - a, y1 - y0, 0.3), CF((a + b) / 2, (y0 + y1) / 2, fz + 0.15), panel)
			end
		end
		frontPanel(x0, dx - doorW / 2, 0, h)
		frontPanel(dx + doorW / 2, x1, 0, h)
		frontPanel(dx - doorW / 2, dx + doorW / 2, doorH, h)
		for _, sx in { x0, x1 } do
			Q:box("WalkInSide", V3(0.3, h, d), CF(sx + (if sx == x0 then 0.15 else -0.15), h / 2, z0 + d / 2), panel)
		end
		Q:box("WalkInTop", V3(w, 0.3, d), CF(cx, h - 0.15, z0 + d / 2), panel)
		-- 패널 이음매 (세로 줄)
		local seam = lk(rgb(200, 204, 206), M.Metal)
		local xx = x0 + 3.0
		while xx < x1 - 0.5 do
			if math.abs(xx - dx) > doorW / 2 + 0.3 then
				Q:box("WalkInSeam", V3(0.05, h - 0.3, 0.02), CF(xx, (h - 0.3) / 2, fz - 0.01), seam)
			end
			xx += 3.0
		end
		Q:box("WalkInKick", V3(w, 0.6, 0.06), CF(cx, 0.3, fz - 0.03), L_STEEL)
		Q:box("WalkInCap", V3(w + 0.1, 0.12, 0.08), CF(cx, h, fz - 0.04), L_STEEL)
		-- 위 증발기 (냉각기) + 배관
		Q:box("Evaporator", V3(3.4, 0.9, 1.6), CF(x0 + 3.0, h + 0.6, z0 + 1.1), lk(rgb(220, 222, 224), M.Metal))
		Q:plate("EvaporatorGrille", 3.0, 0.6, 0.02, fc(V3(x0 + 3.0, h + 0.6, z0 + 0.3), -ZA), lk(rgb(120, 124, 128), M.DiamondPlate))
		Q:seg("CoolPipe", V3(x0 + 4.5, h + 0.6, z0 + 1.3), V3(x0 + 6.5, h + 0.6, z0 + 1.3), 0.14, lk(rgb(30, 30, 32), M.Rubber))
		Q:seg("CoolPipe", V3(x0 + 6.5, h + 0.6, z0 + 1.3), V3(x0 + 6.5, ctx.V.H - 0.05, z0 + 1.3), 0.14, lk(rgb(30, 30, 32), M.Rubber))
		Q:seg("CoolPipeCopper", V3(x0 + 4.5, h + 0.35, z0 + 1.6), V3(x0 + 6.8, h + 0.35, z0 + 1.6), 0.08, lk(rgb(190, 110, 60), M.Metal))
		Q:seg("CoolPipeCopper", V3(x0 + 6.8, h + 0.35, z0 + 1.6), V3(x0 + 6.8, ctx.V.H - 0.05, z0 + 1.6), 0.08, lk(rgb(190, 110, 60), M.Metal))
		-- 문틀 + 안쪽 (어두운 냉기 + 비닐 커튼 + 음료 박스 랙)
		Q:box("WalkInJamb", V3(0.15, doorH, d - 0.3), CF(dx - doorW / 2 - 0.075, doorH / 2, z0 + d / 2), L_STEEL)
		Q:box("WalkInJamb", V3(0.15, doorH, d - 0.3), CF(dx + doorW / 2 + 0.075, doorH / 2, z0 + d / 2), L_STEEL)
		Q:box("WalkInHeader", V3(doorW + 0.3, 0.15, d - 0.3), CF(dx, doorH + 0.075, z0 + d / 2), L_STEEL)
		Q:box("WalkInInner", V3(doorW, doorH, 0.05), CF(dx, doorH / 2, zw - 0.05), lk(rgb(60, 80, 100)))
		Q:box("WalkInFloor", V3(doorW, 0.06, d - 0.3), CF(dx, 0.03, z0 + d / 2), lk(rgb(140, 150, 156), M.DiamondPlate))
		local glow = Q:box("WalkInLamp", V3(doorW - 0.4, 0.05, 0.3), CF(dx, doorH - 0.15, z0 + d / 2), Look.lampCool)
		Q:light(glow, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 6, Brightness = 0.5, Angle = 120, Color = rgb(200, 230, 255) })
		for k = 0, 2 do
			local y = 0.5 + k * 2.2
			Q:box("WalkInShelf", V3(doorW - 0.2, 0.06, 1.2), CF(dx, y, zw - 0.75), lk(rgb(170, 176, 180), M.Metal))
			for j = 0, 2 do
				Q:box("DrinkCase", V3(0.9, 0.7, 1.0), CF(dx - 1.0 + j * 1.0, y + 0.38, zw - 0.75), lk(if (j + k) % 2 == 0 then rgb(30, 110, 200) else RED, M.Plastic))
				Q:box("DrinkCaseTop", V3(0.9, 0.04, 1.0), CF(dx - 1.0 + j * 1.0, y + 0.75, zw - 0.75), { c = rgb(220, 236, 246), m = M.Glass, t = 0.3 })
			end
		end
		for s = 0, 9 do
			Q:box("StripCurtain", V3(doorW / 10 - 0.03, doorH - 0.3, 0.02), CF(dx - doorW / 2 + (s + 0.5) * doorW / 10, doorH / 2 - 0.1, z0 + 0.7), { c = rgb(220, 236, 244), m = M.SmoothPlastic, t = 0.6 })
		end
		-- 문 (그룹, 왼쪽 경첩)
		local hingeX = dx - doorW / 2
		local model = Q:group("WalkInDoor", function()
			local c = CF(dx, doorH / 2, z0 - 0.12)
			Q:box("WalkInDoorLeaf", V3(doorW - 0.05, doorH - 0.08, 0.32), c, lk(rgb(244, 246, 246), M.Metal))
			Q:box("WalkInDoorGasket", V3(doorW + 0.02, doorH, 0.04), c * CF(0, 0, 0.17), lk(rgb(40, 40, 42), M.Rubber))
			Q:box("WalkInDoorKick", V3(doorW - 0.1, 0.8, 0.02), c * CF(0, -doorH / 2 + 0.45, -0.17), L_STEEL)
			Q:box("WalkInDoorWindow", V3(0.9, 0.9, 0.04), c * CF(0, 1.6, -0.16), { c = rgb(200, 220, 236), m = M.Glass, t = 0.45 })
			Q:box("WalkInDoorHandle", V3(0.22, 1.1, 0.22), c * CF(doorW / 2 - 0.4, 0, -0.27), L_CHROME)
			Q:box("WalkInDoorLatch", V3(0.5, 0.3, 0.12), c * CF(doorW / 2 - 0.4, 0.6, -0.2), L_CHROME)
			for _, yy in { doorH / 2 - 0.9, -doorH / 2 + 0.9 } do
				Q:box("WalkInDoorHinge", V3(0.3, 0.6, 0.2), c * CF(-doorW / 2 + 0.1, yy, -0.18), L_CHROME)
			end
			txt(ctx, "WalkInDoorSign", 1.6, 0.6, fc(V3(dx, doorH / 2 + 2.6, z0 - 0.3), -ZA), "냉장 창고\n문을 꼭 닫아 주세요", WHITE, GS_BLUE, { font = F.GothamBold, d = 0.01 })
		end)
		swingB(ctx, model, V3(hingeX, 0, z0 - 0.12), 1.4, { object = "워크인 냉장고", openText = "문 열기", closeText = "문 닫기" })
		-- 온도 조절기
		local td = fc(V3(dx + doorW / 2 + 0.9, 5.4, z0), -ZA)
		Q:plate("CoolCtrl", 0.8, 0.6, 0.12, td, Look.plasticWhite)
		txt(ctx, "CoolCtrlLCD", 0.6, 0.28, td * CF(0, 0.08, 0.13), "3.0°C", rgb(255, 80, 60), rgb(20, 8, 6), { font = F.GothamBold, d = 0.01, glow = 1.4 })
		for i = 0, 2 do
			Q:plate("CoolCtrlKey", 0.12, 0.08, 0.02, td * CF(-0.2 + i * 0.2, -0.18, 0.12), lk(rgb(90, 90, 94)))
		end
		-- 알바 수칙 (냉장고 앞판에 붙임) + 유통기한 점검표
		poster(ctx, fc(V3(x0 + 3.3, 5.5, z0), -ZA), 3.6, 2.4, "알바 수칙\n① 손님께 먼저 인사\n② 유통기한 확인 · 폐기 등록\n③ 박스는 빈 칸부터 진열", INK, rgb(250, 250, 246), { band = GS_BLUE, bandH = 0.18 })
		poster(ctx, fc(V3(x0 + 6.5, 5.6, z0), -ZA), 1.6, 2.2, "유통기한 점검표\n06 · 14 · 22시\n□ □ □ □\n□ □ □ □", INK, rgb(255, 250, 220), { band = YEL, bandH = 0.14, font = F.GothamMedium })
		txt(ctx, "WalkInLabel", 3.0, 0.5, fc(V3(x0 + 3.0, h - 0.6, z0), -ZA) * CF(0, 0, 0.01), "WALK-IN COOLER", GS_BLUE, nil, { font = F.GothamBlack, d = 0.01 })
	end)
end

-- 직원 책상: 발주 단말기 · PC · CCTV 화면 (전환) · 의자 · 서류 · 폐기 바구니
local function staffDesk(ctx: any)
	local Q, K = ctx.Q, ctx.K
	local desk = one(ctx, "StaffDesk")
	if not desk then
		return
	end
	local top = desk.mx.Y
	local mn, mx = desk.mn, desk.mx
	local cx = (mn.X + mx.X) / 2
	-- 의자 (책상 앞 +Z, 사람은 -Z 를 봄)
	local chairP = V3(cx, 0, mx.Z + 0.9)
	if spotB(ctx, CF(chairP), V3(1.6, 3.6, 1.6), 0) then
		Props.chair(Q, pf(chairP, -ZA), { style = "office", seatTop = 2.4, w = 1.5, d = 1.4, backH = 2.0, frame = Look.blackMetal, seat = lk(rgb(40, 42, 46), M.Fabric), back = lk(rgb(40, 42, 46), M.Fabric) })
	end
	-- CCTV 모니터 덮개 (맵 CCTVMonitor 앞) + 4분할 화면
	local mon = one(ctx, "CCTVMonitor")
	local labels = {}
	local frames = {}
	if mon then
		local mz = mon.mx.Z + 0.02
		local md = fc(V3(mon.c.X, mon.c.Y + 0.05, mz), ZA)
		Q:plate("DeskMonBezel", mon.s.X + 0.1, mon.s.Y + 0.1, 0.06, md, Look.plasticBlack)
		Q:plate("DeskMonStand", 0.3, 0.08, 0.5, fc(V3(mon.c.X, top + 0.04, mon.mn.Z - 0.1), ZA), Look.plasticBlack)
		local names = { "CAM1 입구", "CAM2 계산대", "CAM3 진열대", "CAM4 창고" }
		local cols = { rgb(56, 64, 72), rgb(64, 60, 54), rgb(52, 62, 74), rgb(66, 62, 56) }
		for i = 1, 4 do
			local qx = if i % 2 == 1 then -0.53 else 0.53
			local qy = if i <= 2 then 0.37 else -0.37
			local q = md * CF(qx, qy, 0.065)
			Q:plate("DeskCamView", 1.02, 0.7, 0.005, q, lk(cols[i]))
			Q:plate("DeskCamFloor", 1.02, 0.26, 0.006, q * CF(0, -0.22, 0), lk(rgb(120, 118, 110)))
			Q:plate("DeskCamShelf", 0.14, 0.42, 0.007, q * CF(-0.3, 0.02, 0), lk(rgb(160, 150, 130)))
			local fr = Q:plate("DeskCamSel", 1.04, 0.04, 0.008, q * CF(0, 0.36, 0), lk(YEL))
			fr.Transparency = if i == 1 then 0 else 1
			table.insert(frames, fr)
			local _, lb = txt(ctx, "DeskCamLabel", 0.9, 0.1, q * CF(-0.05, 0.28, 0.008), names[i], WHITE, nil, { font = F.Code, align = "Left", d = 0.003 })
			table.insert(labels, lb)
		end
		local lighting = game:GetService("Lighting")
		Interact.anim(K, function(t)
			local h = lighting.ClockTime
			for i, lb in labels do
				if lb.Parent then
					lb.Text = string.format("%s %02d:%02d:%02d", names[i], math.floor(h), math.floor((h % 1) * 60), math.floor(t) % 60)
				end
			end
		end)
		-- 화면 전환: 선택 카메라 바꾸기
		local btn = Q:box("DeskMonButton", V3(0.3, 0.12, 0.2), CF(mon.c.X + mon.s.X / 2 - 0.2, top + 0.06, mon.mx.Z + 0.35), lk(rgb(40, 40, 44)))
		Interact.cycle(K, btn, { 1, 2, 3, 4 }, {
			action = "화면 전환",
			object = "CCTV 모니터",
			on = function(i)
				for j, fr in frames do
					if fr.Parent then
						fr.Transparency = if j == i then 0 else 1
					end
				end
			end,
		})
	end
	-- 발주 단말기 (PDA 거치대) + PC + 키보드 + 서류
	local function onTop(x: number, z: number): CFrame
		return CF(x, top, z)
	end
	local pda = onTop(mn.X + 0.6, mx.Z - 0.6)
	Q:box("PDACradle", V3(0.6, 0.2, 0.45), pda * CF(0, 0.1, 0), Look.plasticBlack)
	Q:box("PDA", V3(0.42, 0.85, 0.12), pda * CF(0, 0.55, -0.05) * ANG(math.rad(-12), 0, 0), lk(rgb(40, 44, 50)))
	local pdaScr = Q:box("PDAScreen", V3(0.34, 0.45, 0.02), pda * CF(0, 0.66, 0.02) * ANG(math.rad(-12), 0, 0), lk(rgb(40, 140, 200), M.Neon, { t = 0.3 }))
	txt(ctx, "PDALabel", 0.5, 0.12, fc((pda * CF(0, 0.12, 0.23)).Position, ZA), "발주 단말기", WHITE, nil, { font = F.GothamBold, d = 0.005 })
	Q:box("PDALed", V3(0.06, 0.03, 0.03), pda * CF(0.22, 0.2, 0.23), Look.ledGreen)
	Interact.screenLoop(K, pdaScr, nil, { { c = rgb(40, 140, 200) }, { c = rgb(40, 170, 120) }, { c = rgb(40, 140, 200) }, { c = rgb(230, 150, 40) } }, 2.5)
	Q:box("Keyboard", V3(1.4, 0.06, 0.45), onTop(cx, mx.Z - 0.55) * CF(0, 0.03, 0), lk(rgb(36, 38, 42)))
	Q:box("Mouse", V3(0.16, 0.06, 0.26), onTop(cx + 1.0, mx.Z - 0.55) * CF(0, 0.03, 0), lk(rgb(36, 38, 42)))
	Q:box("DocTray", V3(0.9, 0.25, 0.7), onTop(mx.X - 0.6, mn.Z + 0.9) * CF(0, 0.125, 0), lk(rgb(60, 64, 70)))
	Q:box("DocPaper", V3(0.8, 0.1, 0.6), onTop(mx.X - 0.6, mn.Z + 0.9) * CF(0, 0.24, 0), Look.paper)
	Q:box("Binder", V3(0.25, 1.0, 0.8), onTop(mx.X - 0.25, mx.Z - 1.3) * CF(0, 0.5, 0), lk(GS_BLUE))
	Q:box("Binder", V3(0.25, 1.0, 0.8), onTop(mx.X - 0.52, mx.Z - 1.3) * CF(0, 0.5, 0), lk(RED))
	Q:vcyl("Mug", 0.3, 0.26, onTop(mn.X + 1.3, mx.Z - 0.45) * CF(0, 0.15, 0), lk(WHITE))
	Q:box("Calculator", V3(0.4, 0.05, 0.55), onTop(cx - 1.1, mx.Z - 0.55) * CF(0, 0.025, 0), lk(rgb(60, 60, 64)))
	-- 책상 앞판 (다리 사이 가림판)
	Q:box("DeskModesty", V3(mx.X - mn.X - 0.4, 1.6, 0.05), CF(cx, top - 1.2, mn.Z + 0.3), lk(rgb(140, 112, 84), M.Wood))
	-- 폐기 바구니 (책상 옆)
	local bp = V3(mn.X - 0.9, 0, mx.Z - 0.4)
	if spotB(ctx, CF(bp), V3(1.3, 1.6, 1.0), 0) then
		Q:box("DiscardBasket", V3(1.2, 0.9, 0.9), CF(bp) * CF(0, 0.45, 0), lk(RED, M.Plastic))
		Q:box("DiscardInside", V3(1.05, 0.04, 0.75), CF(bp) * CF(0, 0.86, 0), lk(rgb(120, 20, 20), M.Plastic))
		for i = 0, 2 do
			Q:wedge("ExpiredSamgak", V3(0.35, 0.3, 0.12), CF(bp) * CF(-0.3 + i * 0.3, 0.98, 0.1 * i) * ANG(0, 0.4 * i, 0), lk(rgb(250, 250, 246)))
		end
		txt(ctx, "DiscardLabel", 1.0, 0.36, fc(V3(bp.X, 0.55, bp.Z + 0.46), ZA), "폐기", WHITE, nil, { font = F.GothamBlack, d = 0.01 })
	end
end

-- 사물함 (맵 StaffLocker 숨기고 속이 빈 사물함 + 문) · 유니폼 걸이
local function lockers(ctx: any)
	local Q = ctx.Q
	local ls = all(ctx, "StaffLocker")
	if #ls == 0 then
		return
	end
	local body = lk(rgb(120, 139, 160), M.Metal)
	local inner = lk(rgb(90, 104, 120), M.Metal)
	for i, e in ls do
		hideRec(ctx, e)
		local mn, mx = e.mn, e.mx
		local w, h, d = mx.X - mn.X, mx.Y - mn.Y, mx.Z - mn.Z
		local cx = (mn.X + mx.X) / 2
		local fz = mn.Z -- 앞면 (-Z 를 봄)
		Q:free(function()
			Q:box("LockerBack", V3(w, h, 0.06), CF(cx, h / 2, mx.Z - 0.03), body)
			Q:box("LockerSide", V3(0.05, h, d), CF(mn.X + 0.025, h / 2, (mn.Z + mx.Z) / 2), body)
			Q:box("LockerSide", V3(0.05, h, d), CF(mx.X - 0.025, h / 2, (mn.Z + mx.Z) / 2), body)
			Q:box("LockerTop", V3(w, 0.06, d), CF(cx, h - 0.03, (mn.Z + mx.Z) / 2), body)
			Q:box("LockerPlinth", V3(w, 0.4, d), CF(cx, 0.2, (mn.Z + mx.Z) / 2), lk(rgb(60, 64, 70), M.Metal))
			Q:box("LockerShelf", V3(w - 0.1, 0.05, d - 0.1), CF(cx, h - 1.3, (mn.Z + mx.Z) / 2), inner)
			Q:box("LockerInnerBack", V3(w - 0.1, h - 0.5, 0.02), CF(cx, h / 2 + 0.2, mx.Z - 0.07), inner)
			Q:seg("LockerRod", V3(mn.X + 0.1, h - 1.6, (mn.Z + mx.Z) / 2), V3(mx.X - 0.1, h - 1.6, (mn.Z + mx.Z) / 2), 0.05, L_CHROME)
			-- 안: GS25 조끼 · 가방 · 모자
			if i % 2 == 1 then
				local vc = CF(cx, h - 3.0, (mn.Z + mx.Z) / 2)
				Q:box("VestHanger", V3(1.0, 0.05, 0.05), vc * CF(0, 1.38, 0), lk(rgb(40, 40, 40)))
				Q:box("Vest", V3(1.1, 2.6, 0.25), vc, lk(GS_BLUE, M.Fabric))
				Q:box("VestPanel", V3(0.3, 2.4, 0.26), vc * CF(0, 0, 0), lk(rgb(240, 240, 240), M.Fabric))
				txt(ctx, "VestLogo", 0.5, 0.22, fc((vc * CF(-0.3, 0.6, -0.13)).Position, -ZA), "GS25", WHITE, nil, { font = F.GothamBlack, d = 0.005 })
			else
				Q:rbox("LockerBag", V3(1.2, 1.0, 0.6), 0.2, CF(cx, 0.4 + 0.5, (mn.Z + mx.Z) / 2), lk(rgb(30, 30, 34), M.Fabric))
				Q:vcyl("LockerBottle", 0.6, 0.22, CF(cx + 0.5, h - 1.0, (mn.Z + mx.Z) / 2), lk(rgb(80, 160, 200)))
			end
			-- 문 (그룹, 왼쪽 경첩)
			local model = Q:group("LockerDoor_" .. i, function()
				local c = CF(cx, h / 2 + 0.2, fz - 0.03)
				Q:box("LockerDoorLeaf", V3(w - 0.06, h - 0.5, 0.05), c, body)
				for v = 0, 3 do
					Q:box("LockerVent", V3(w * 0.5, 0.06, 0.01), c * CF(0, h / 2 - 0.9 - v * 0.18, -0.03), lk(rgb(60, 70, 84), M.Metal))
				end
				Q:box("LockerHandle", V3(0.1, 0.5, 0.1), c * CF(w / 2 - 0.25, 0, -0.06), L_CHROME)
				Q:box("LockerLock", V3(0.16, 0.16, 0.04), c * CF(w / 2 - 0.25, 0.45, -0.04), lk(rgb(200, 170, 80), M.Metal))
				Q:box("LockerNameTag", V3(0.6, 0.25, 0.02), c * CF(0, h / 2 - 0.5, -0.035), lk(WHITE))
				txt(ctx, "LockerName", 0.55, 0.2, fc((c * CF(0, h / 2 - 0.5, -0.05)).Position, -ZA), string.format("%02d", i), INK, nil, { font = F.GothamBold, d = 0.004 })
			end)
			if i % 2 == 1 then
				swingB(ctx, model, V3(mn.X + 0.03, 0, fz - 0.03), -1.6, { object = "직원 사물함", openText = "열기", closeText = "닫기" })
			end
		end)
	end
	-- 유니폼 걸이 (사물함 오른쪽 벽)
	local last = ls[#ls]
	local bw = one(ctx, "BackWall", function(e)
		return e.s.X > 20
	end)
	if last and bw then
		local zw = bw.mn.Z
		local x0 = last.mx.X + 0.4
		local x1 = x0 + 3.0
		local sink = one(ctx, "StaffSink")
		if sink then
			x1 = math.min(x1, sink.mn.X - 0.4)
		end
		if x1 - x0 > 1.8 then
			Q:free(function()
				local d = fc(V3((x0 + x1) / 2, 6.4, zw), -ZA)
				Q:plate("HookRail", x1 - x0, 0.3, 0.08, d, lk(rgb(140, 110, 80), M.Wood))
				local n = math.floor((x1 - x0) / 0.9)
				for k = 0, n - 1 do
					local hx = -(x1 - x0) / 2 + 0.45 + k * 0.9
					Q:plate("Hook", 0.08, 0.08, 0.35, d * CF(hx, -0.05, 0.08), L_CHROME)
					if k < 2 then
						Q:plate("HungVest", 0.95, 2.4, 0.22, d * CF(hx, -1.45, 0.25), lk(GS_BLUE, M.Fabric))
						Q:plate("HungVestPanel", 0.28, 2.2, 0.01, d * CF(hx, -1.5, 0.37), lk(rgb(240, 240, 240), M.Fabric))
					elseif k == 2 then
						Q:ell("HungCap", V3(0.7, 0.35, 0.7), d * CF(hx, -0.4, 0.3), lk(GS_BLUE, M.Fabric))
					end
				end
				txt(ctx, "HookSign", 1.8, 0.3, d * CF(0, 0.45, 0.02), "유니폼 · 조끼 걸이", INK, rgb(250, 250, 246), { font = F.GothamBold, d = 0.01 })
			end)
		end
	end
end

-- 개수대 + 청소용 싱크 (맵 StaffSink 자리) · 대걸레 · 양동이
local function sinks(ctx: any)
	local Q = ctx.Q
	local s = one(ctx, "StaffSink")
	if not s then
		return
	end
	hideRec(ctx, s)
	local mn, mx = s.mn, s.mx
	local xw = mx.X -- 벽 쪽 (+X)
	local zmid = (mn.Z + mx.Z) / 2
	Q:free(function()
		-- 개수대 (앞쪽 반, z mn..zmid)
		local cz = (mn.Z + zmid) / 2
		local cw = zmid - mn.Z - 0.1
		local cxx = (mn.X + mx.X) / 2
		Q:box("SinkCabinet", V3(mx.X - mn.X, 2.9, cw), CF(cxx, 1.45, cz), L_STEEL)
		Q:plate("SinkCabinetDoor", cw - 0.2, 2.3, 0.02, fc(V3(mn.X, 1.4, cz), -XA), lk(rgb(190, 194, 198), M.Metal))
		Q:box("SinkTop", V3(mx.X - mn.X, 0.12, cw), CF(cxx, 2.96, cz), L_STEEL)
		Q:box("SinkBowl", V3(mx.X - mn.X - 0.6, 0.04, cw - 0.6), CF(cxx - 0.1, 2.75, cz), lk(rgb(150, 154, 158), M.Metal))
		Q:box("SinkBowlWall", V3(mx.X - mn.X - 0.6, 0.25, 0.04), CF(cxx - 0.1, 2.88, cz - (cw - 0.6) / 2), L_STEEL)
		Q:box("SinkBowlWall", V3(mx.X - mn.X - 0.6, 0.25, 0.04), CF(cxx - 0.1, 2.88, cz + (cw - 0.6) / 2), L_STEEL)
		Q:box("SinkSplash", V3(0.08, 0.8, cw), CF(xw - 0.04, 3.4, cz), L_STEEL)
		Q:seg("Faucet", V3(xw - 0.25, 3.0, cz), V3(xw - 0.25, 3.7, cz), 0.1, L_CHROME)
		Q:seg("FaucetSpout", V3(xw - 0.25, 3.7, cz), V3(xw - 0.8, 3.7, cz), 0.08, L_CHROME)
		Q:box("FaucetLever", V3(0.3, 0.05, 0.08), CF(xw - 0.25, 3.78, cz + 0.15), L_CHROME)
		Q:box("SoapBottle", V3(0.2, 0.45, 0.2), CF(xw - 0.4, 3.25, cz - 0.6), lk(rgb(60, 160, 120)))
		-- 청소용 싱크 (뒤쪽 반, 바닥 낮은 통)
		local mz = (zmid + mx.Z) / 2
		local mw = mx.Z - zmid - 0.1
		Q:box("MopSinkBase", V3(mx.X - mn.X - 0.4, 1.1, mw), CF(cxx + 0.2, 0.55, mz), lk(rgb(230, 230, 226), M.Concrete))
		Q:box("MopSinkBasin", V3(mx.X - mn.X - 0.9, 0.04, mw - 0.5), CF(cxx + 0.2, 1.08, mz), lk(rgb(120, 124, 128), M.Metal))
		Q:box("MopSinkRim", V3(mx.X - mn.X - 0.4, 0.1, 0.2), CF(cxx + 0.2, 1.15, mz - mw / 2 + 0.1), L_STEEL)
		Q:seg("MopFaucet", V3(xw - 0.05, 3.2, mz), V3(xw - 0.6, 3.2, mz), 0.1, L_CHROME)
		Q:seg("MopFaucetDrop", V3(xw - 0.6, 3.2, mz), V3(xw - 0.6, 2.9, mz), 0.08, L_CHROME)
		-- 벽 타일 (싱크 뒤)
		local td = fc(V3(xw, 4.3, (mn.Z + mx.Z) / 2), -XA)
		Q:plate("SinkTiles", mx.Z - mn.Z, 2.6, 0.03, td, Look.tileWhite)
		for k = 1, 4 do
			Q:plate("SinkGrout", mx.Z - mn.Z, 0.03, 0.035, td * CF(0, -1.3 + k * 0.52, 0), lk(rgb(196, 194, 188)))
		end
		-- 대걸레 · 빗자루 (벽에 기대기)
		Q:seg("MopHandle", V3(xw - 0.2, 0.3, mx.Z - 0.3), V3(xw - 0.1, 5.4, mx.Z - 0.2), 0.08, lk(rgb(30, 120, 200), M.Metal))
		Q:ell("MopHead", V3(0.7, 0.5, 0.5), CF(xw - 0.2, 0.25, mx.Z - 0.3), lk(rgb(230, 230, 220), M.Fabric))
		Q:seg("BroomHandle", V3(xw - 0.2, 0.5, mx.Z - 0.7), V3(xw - 0.1, 5.2, mx.Z - 0.6), 0.07, lk(RED, M.Metal))
		Q:box("BroomHead", V3(0.25, 0.4, 0.9), CF(xw - 0.25, 0.3, mx.Z - 0.7), lk(rgb(240, 200, 40), M.Plastic))
		txt(ctx, "SinkSign", 1.6, 0.3, td * CF(0, 1.55, 0.04), "손 씻기 · 30초 이상", WHITE, rgb(30, 130, 200), { font = F.GothamBold, d = 0.01 })
	end)
	-- 양동이 (맵 MopBucket 자리)
	local mb = one(ctx, "MopBucket")
	if mb then
		hideRec(ctx, mb)
		local p = V3(mb.c.X, 0, mb.c.Z)
		Q:free(function()
			Q:box("MopBucketBody", V3(1.4, 1.0, 1.1), CF(p) * CF(0, 0.6, 0), lk(rgb(250, 200, 0), M.Plastic))
			Q:box("MopBucketWater", V3(1.2, 0.04, 0.9), CF(p) * CF(0, 0.9, 0), { c = rgb(140, 160, 150), m = M.Glass, t = 0.3 })
			Q:box("MopWringer", V3(0.6, 0.5, 1.0), CF(p) * CF(0.35, 1.3, 0), lk(rgb(230, 170, 0), M.Plastic))
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					Q:ball("MopBucketWheel", 0.2, CF(p) * CF(sx * 0.55, 0.1, sz * 0.42), lk(rgb(30, 30, 32), M.Rubber))
				end
			end
			Q:seg("BucketMop", p + V3(-0.2, 0.9, 0), p + V3(-0.5, 5.0, 0.3), 0.08, lk(rgb(30, 120, 200), M.Metal))
			txt(ctx, "BucketLabel", 0.9, 0.3, fc(p + V3(0, 0.55, 0.56), ZA), "CAUTION", INK, nil, { font = F.GothamBlack, d = 0.005 })
		end)
	end
end

-- 롤테이너 (맵 RollCage 자리 + 하나 더) · 박스 더미 · 우유 상자 · 도시락 트레이
local function cagesAndPiles(ctx: any)
	local Q = ctx.Q
	local function rollCage(c: CFrame, w: number, d: number, h: number)
		local fr = lk(rgb(170, 174, 178), M.Metal)
		Q:box("CageBase", V3(w, 0.2, d), c * CF(0, 0.35, 0), lk(rgb(120, 124, 128), M.Metal))
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				Q:ball("CageWheel", 0.3, c * CF(sx * (w / 2 - 0.2), 0.15, sz * (d / 2 - 0.2)), lk(rgb(30, 30, 32), M.Rubber))
			end
		end
		-- 옆 3면 (그물: 기둥 + 가로대)
		for _, sx in { -1, 1 } do
			Q:box("CagePost", V3(0.08, h, 0.08), c * CF(sx * (w / 2 - 0.04), 0.45 + h / 2, -d / 2 + 0.04), fr)
			Q:box("CagePost", V3(0.08, h, 0.08), c * CF(sx * (w / 2 - 0.04), 0.45 + h / 2, d / 2 - 0.04), fr)
			for k = 1, 5 do
				Q:box("CageBar", V3(0.04, 0.04, d), c * CF(sx * (w / 2 - 0.04), 0.45 + k * h / 6, 0), fr)
			end
		end
		for k = 1, 5 do
			Q:box("CageBar", V3(w, 0.04, 0.04), c * CF(0, 0.45 + k * h / 6, -d / 2 + 0.04), fr)
		end
		for k = 1, 4 do
			Q:box("CageWire", V3(0.03, h, 0.03), c * CF(-w / 2 + k * w / 5, 0.45 + h / 2, -d / 2 + 0.04), fr)
		end
		Q:box("CageTop", V3(w, 0.06, 0.06), c * CF(0, 0.45 + h, -d / 2 + 0.04), fr)
	end
	local rc = one(ctx, "RollCage")
	if rc then
		hideRec(ctx, rc)
		local c = CF((rc.mn.X + rc.mx.X) / 2, 0, (rc.mn.Z + rc.mx.Z) / 2)
		Q:free(function()
			rollCage(c, rc.s.X, rc.s.Z, rc.s.Y - 0.5)
			-- 도시락 배송 트레이 (위)
			for k = 0, 2 do
				Q:box("BentoTray", V3(rc.s.X - 0.6, 0.3, rc.s.Z - 0.6), c * CF(0, rc.s.Y + 0.15 + k * 0.32, 0), lk(rgb(30, 110, 190), M.Plastic))
			end
		end)
	end
	-- 왼쪽 벽: 박스 더미 + 롤테이너 하나 더 + 우유 상자
	local sl = one(ctx, "StockLining")
	local xw = if sl then sl.mx.X else ctx.fx0 + 0.15
	local pileP = CF(xw + 1.5, 0, -4.6)
	if spotB(ctx, pileP, V3(2.8, 1.8, 3.6), 0) then
		for k = 0, 8 do
			Q:box("FlatCardboard", V3(2.6, 0.12, 3.4), pileP * CF(rnd(5, k) * 0.2 - 0.1, 0.06 + k * 0.13, rnd(9, k) * 0.2 - 0.1) * ANG(0, (rnd(3, k) - 0.5) * 0.1, 0), lk(rgb(180 + math.floor(rnd(4, k) * 20), 140, 96), M.Cardboard))
		end
		Q:box("StrapBand", V3(0.06, 0.02, 3.5), pileP * CF(-0.6, 1.25, 0), lk(rgb(240, 200, 40)))
		Q:box("StrapBand", V3(0.06, 0.02, 3.5), pileP * CF(0.6, 1.25, 0), lk(rgb(240, 200, 40)))
		-- 기대 놓은 박스판
		for k = 0, 2 do
			Q:box("LeanCardboard", V3(0.1, 3.4, 2.6), CF(xw + 0.25 + k * 0.12, 1.7, -4.6) * ANG(0, 0, -0.12 - k * 0.04), lk(rgb(186, 146, 100), M.Cardboard))
		end
		txt(ctx, "RecycleSign", 2.0, 0.4, fc(V3(xw, 4.2, -4.6), XA) * CF(0, 0, 0.02), "박스 재활용 · 접어서 쌓기", WHITE, rgb(40, 140, 80), { font = F.GothamBold, d = 0.01 })
	end
	local cageP = CF(xw + 1.6, 0, 0.6)
	if spotB(ctx, cageP, V3(2.6, 6.0, 3.0), 0) then
		rollCage(cageP * ANG(0, PI / 2, 0), 3.0, 2.6, 5.0)
		for k = 0, 2 do
			carton(ctx, cageP * CF(0, 0.45 + k * 1.25, 0), V3(1.9, 1.2, 2.3), ({ "새우깡 20입", "신라면 40입", "햇반 × 24" })[k + 1], ({ rgb(220, 120, 20), RED, rgb(40, 140, 70) })[k + 1], k + 3)
		end
	end
	local milkP = CF(xw + 1.3, 0, 4.0)
	if spotB(ctx, milkP, V3(2.0, 2.2, 1.6), 0) then
		for k = 0, 2 do
			local c = milkP * CF(0, k * 0.68, 0)
			local col = if k == 1 then rgb(30, 120, 200) else rgb(40, 150, 80)
			Q:box("MilkCrate", V3(1.9, 0.66, 1.5), c * CF(0, 0.33, 0), lk(col, M.Plastic))
			Q:box("MilkCrateHole", V3(1.2, 0.2, 0.02), c * CF(0, 0.42, 0.76), lk(dk(col, 0.5), M.Plastic))
		end
		for i = 0, 5 do
			Q:box("MilkCarton", V3(0.32, 0.6, 0.32), milkP * CF(-0.6 + (i % 3) * 0.6, 2.04 + 0.3, -0.3 + (i // 3) * 0.6), lk(WHITE))
			Q:wedge("MilkCartonTop", V3(0.32, 0.16, 0.32), milkP * CF(-0.6 + (i % 3) * 0.6, 2.04 + 0.68, -0.3 + (i // 3) * 0.6), lk(WHITE))
		end
	end
end

-- 금고 · 미니 냉장고 + 직원용 전자레인지 · 분전반 · 게시판 · 소화기 · 유도등
local function staffWall(ctx: any)
	local Q = ctx.Q
	local gs = one(ctx, "GroundSide")
	local xr = if gs then gs.mn.X else ctx.fx1
	local desk = one(ctx, "StaffDesk")
	-- 금고 (책상 오른쪽, 벽에 붙여)
	local safeZ = if desk then desk.mn.Z - 1.2 else -3.0
	local safeP = pf(V3(xr - 1.0, 0, safeZ), -XA)
	if spotB(ctx, safeP, V3(1.8, 2.6, 1.9), 0) then
		Q:box("SafeBody", V3(1.8, 2.5, 1.8), safeP * CF(0, 1.25, 0), lk(rgb(56, 60, 64), M.Metal))
		local door = fc((safeP * CF(0, 1.25, 0.9)).Position, -XA)
		Q:plate("SafeDoor", 1.5, 2.1, 0.08, door, lk(rgb(70, 74, 80), M.Metal))
		Q:plate("SafeKeypad", 0.45, 0.6, 0.04, door * CF(0.35, 0.4, 0.08), lk(rgb(30, 30, 32)))
		for k = 0, 8 do
			Q:plate("SafeKey", 0.1, 0.08, 0.02, door * CF(0.25 + (k % 3) * 0.1, 0.5 - (k // 3) * 0.12, 0.12), lk(rgb(200, 200, 200)))
		end
		Q:plate("SafeLCD", 0.35, 0.1, 0.01, door * CF(0.35, 0.65, 0.12), Look.ledGreen)
		Q:plate("SafeHandle", 0.1, 0.7, 0.18, door * CF(-0.45, 0.0, 0.08), L_CHROME)
		txt(ctx, "SafeLabel", 1.0, 0.25, door * CF(0, -0.7, 0.09), "시재 금고", WHITE, nil, { font = F.GothamBold, d = 0.005 })
	end
	-- 미니 냉장고 + 전자레인지 (안쪽 구석)
	local gb = one(ctx, "GroundBack")
	local zb = if gb then gb.mx.Z else ctx.fz0
	local fP = pf(V3(xr - 1.2, 0, zb + 1.3), -XA)
	if spotB(ctx, fP, V3(2.2, 4.6, 2.2), 0) then
		Q:box("MiniFridge", V3(2.0, 3.0, 2.0), fP * CF(0, 1.5, 0), lk(rgb(236, 236, 232)))
		Q:plate("MiniFridgeDoorLine", 1.9, 0.03, 0.02, fc((fP * CF(0, 2.1, 1.0)).Position, -XA), lk(rgb(180, 180, 176)))
		Q:box("MiniFridgeHandle", V3(0.08, 1.0, 0.1), fP * CF(0.8, 1.6, 1.05), L_CHROME)
		Q:box("StaffMicro", V3(1.8, 1.0, 1.4), fP * CF(0, 3.5, -0.2), lk(rgb(60, 62, 66)))
		Q:plate("StaffMicroWindow", 1.0, 0.7, 0.02, fc((fP * CF(-0.25, 3.5, 0.5)).Position, -XA), lk(rgb(20, 20, 22), M.Glass))
		Q:vcyl("FridgeMagnetCup", 0.3, 0.25, fP * CF(0.5, 3.15, 0.6), lk(RED))
	end
	-- 오른쪽 벽: 분전반 · 근무표 · 소화기 · 전화
	Q:free(function()
		local function rw(y: number, z: number): CFrame
			return fc(V3(xr, y, z), -XA)
		end
		local pz = -6.5
		local p = rw(5.6, pz)
		Q:plate("ElecPanel", 1.6, 2.2, 0.2, p, lk(rgb(210, 212, 210), M.Metal))
		Q:plate("ElecPanelDoorLine", 0.03, 2.0, 0.01, p * CF(0, 0, 0.2), lk(rgb(150, 150, 150)))
		Q:plate("ElecPanelHandle", 0.06, 0.3, 0.06, p * CF(0.55, 0, 0.2), L_CHROME)
		txt(ctx, "ElecPanelSign", 1.2, 0.3, p * CF(0, 0.75, 0.21), "분전반 ⚡ 위험", INK, YEL, { font = F.GothamBold, d = 0.01 })
		Q:seg("ElecConduit", (p * CF(0, 1.1, 0.1)).Position, V3(xr - 0.12, ctx.V.H - 0.05, pz), 0.12, lk(rgb(200, 200, 196)))
		-- 근무 스케줄표 (화이트보드)
		local sz = 1.0
		local sb = rw(5.4, sz)
		Q:plate("ScheduleBoard", 4.0, 2.6, 0.08, sb, lk(rgb(250, 250, 250)))
		Q:plate("ScheduleFrame", 4.1, 0.08, 0.1, sb * CF(0, 1.3, 0), L_STEEL)
		Q:plate("ScheduleFrame", 4.1, 0.08, 0.1, sb * CF(0, -1.3, 0), L_STEEL)
		txt(ctx, "ScheduleTitle", 3.6, 0.35, sb * CF(0, 1.0, 0.09), "10월 근무 스케줄", GS_BLUE, nil, { font = F.GothamBlack, d = 0.005 })
		txt(ctx, "ScheduleBody", 3.7, 1.7, sb * CF(0, -0.15, 0.09), "오전 07-15  김민지 · 박서준\n오후 15-23  이도윤 · 최하은\n야간 23-07  정우진 (주3일)\n점장 연락처 010-****-2525", INK, nil, { font = F.GothamMedium, align = "Left", d = 0.005 })
		Q:plate("BoardMarker", 0.5, 0.06, 0.12, sb * CF(1.4, -1.38, 0.06), lk(RED))
		-- 전화기
		local ph = rw(4.8, sz + 2.6)
		Q:plate("WallPhone", 0.5, 0.8, 0.16, ph, Look.plasticWhite)
		Q:plate("WallPhoneHandset", 0.16, 0.7, 0.1, ph * CF(-0.15, 0, 0.16), Look.plasticWhite)
		-- 소화기 + 표지
		local ep = V3(xr - 0.5, 0, sz + 4.2)
		Q:vcyl("StockExtBody", 1.5, 0.62, CF(ep) * CF(0, 0.85, 0), lk(rgb(200, 24, 28)))
		Q:box("StockExtStand", V3(0.9, 0.12, 0.9), CF(ep) * CF(0, 0.06, 0), lk(rgb(180, 30, 30)))
		Q:vcyl("StockExtNeck", 0.2, 0.2, CF(ep) * CF(0, 1.7, 0), Look.black)
		Q:seg("StockExtHose", ep + V3(0, 1.7, -0.1), ep + V3(-0.1, 0.6, -0.32), 0.08, Look.black)
		txt(ctx, "StockExtSign", 0.9, 0.42, rw(2.6, sz + 4.2), "소화기", WHITE, RED, { font = F.GothamBlack, d = 0.02 })
	end)
	-- 왼쪽 벽 게시판 (코르크)
	local sl = one(ctx, "StockLining")
	local xl = if sl then sl.mx.X else ctx.fx0 + 0.15
	Q:free(function()
		local bd = fc(V3(xl, 5.6, 7.6), XA)
		Q:plate("CorkBoard", 3.6, 2.4, 0.08, bd, lk(rgb(190, 150, 100), M.Fabric))
		Q:plate("CorkFrame", 3.7, 0.1, 0.1, bd * CF(0, 1.2, 0), lk(rgb(120, 90, 60), M.Wood))
		Q:plate("CorkFrame", 3.7, 0.1, 0.1, bd * CF(0, -1.2, 0), lk(rgb(120, 90, 60), M.Wood))
		local notes = { { "위생교육\n이수증", rgb(250, 250, 246) }, { "행사 일정\n10/1~10/31\n1+1 · 2+1", rgb(255, 240, 160) }, { "택배 마감\n18:00", rgb(220, 240, 255) }, { "폐기 등록\n꼭 하기!", rgb(255, 220, 220) } }
		for i, n in notes do
			local x = -1.3 + (i - 1) * 0.86
			local y = if i % 2 == 0 then 0.25 else -0.15
			txt(ctx, "CorkNote", 0.75, 0.95, bd * CF(x, y, 0.09) * ANG(0, 0, (i - 2.5) * 0.04), n[1], INK, n[2], { font = F.GothamMedium, d = 0.01 })
			Q:plate("CorkPin", 0.08, 0.08, 0.04, bd * CF(x, y + 0.42, 0.1), lk(RED))
		end
		txt(ctx, "CorkTitle", 2.4, 0.3, bd * CF(0, 1.5, 0.02), "직원 게시판", INK, nil, { font = F.GothamBlack, d = 0.01 })
		-- 벽 보호대 (카트 범퍼)
		Q:plate("WallBumper", 9.0, 0.3, 0.12, fc(V3(xl, 1.5, -2.0), XA), lk(rgb(60, 62, 66), M.Rubber))
	end)
end

-- 창고 천장: 스프링클러 배관 + 헤드 · 감지기 · 등기구 테 · 유도등
local function ceilingStock(ctx: any)
	local Q = ctx.Q
	local H = ctx.V.H
	local pipe = lk(rgb(200, 30, 30), M.Metal)
	for _, z in { -5.0, 6.8 } do
		Q:free(function()
			Q:seg("SprinklerMain", V3(ctx.fx0 + 0.4, H - 0.35, z), V3(ctx.fx1 - 0.4, H - 0.35, z), 0.2, pipe)
			for x = ctx.fx0 + 3.0, ctx.fx1 - 2.0, 6.5 do
				Q:seg("SprinklerDrop", V3(x, H - 0.35, z), V3(x, H - 0.75, z), 0.1, pipe)
				Q:vcyl("SprinklerHead", 0.14, 0.1, CF(x, H - 0.82, z), Look.brass)
				Q:disc("SprinklerDeflector", 0.2, 0.02, CF(x, H - 0.9, z), Look.brass)
			end
			for x = ctx.fx0 + 2.0, ctx.fx1 - 1.0, 8.0 do
				Q:box("PipeHanger", V3(0.05, 0.3, 0.05), CF(x, H - 0.15, z), L_STEEL)
			end
		end)
	end
	-- 감지기
	for _, p in { V3(-12, 0, 0.5), V3(10, 0, 2.5) } do
		Q:free(function()
			Q:disc("SmokeDetector", 0.55, 0.14, CF(p.X, H - 0.07, p.Z), Look.white)
			Q:disc("SmokeDetectorLED", 0.06, 0.02, CF(p.X + 0.16, H - 0.15, p.Z), Look.ledRed)
		end)
	end
	-- 맵 LightPanel (네온 판) 둘레 등기구 테
	for _, lp in all(ctx, "LightPanel") do
		Q:free(function()
			local cx, cz = lp.c.X, lp.c.Z
			Q:box("LightHousing", V3(lp.s.X + 0.3, 0.1, 0.12), CF(cx, H - 0.08, lp.mn.Z - 0.06), L_WHITEP)
			Q:box("LightHousing", V3(lp.s.X + 0.3, 0.1, 0.12), CF(cx, H - 0.08, lp.mx.Z + 0.06), L_WHITEP)
			Q:box("LightHousing", V3(0.12, 0.1, lp.s.Z), CF(lp.mn.X - 0.06, H - 0.08, cz), L_WHITEP)
			Q:box("LightHousing", V3(0.12, 0.1, lp.s.Z), CF(lp.mx.X + 0.06, H - 0.08, cz), L_WHITEP)
		end)
	end
	-- 케이블 트레이 (뒤벽 위)
	local gb = one(ctx, "GroundBack")
	local zb = if gb then gb.mx.Z else ctx.fz0
	Q:free(function()
		Q:box("CableTray", V3(ctx.fx1 - ctx.fx0 - 1, 0.12, 0.8), CF((ctx.fx0 + ctx.fx1) / 2, H - 1.0, zb + 0.6), lk(rgb(170, 174, 178), M.Metal))
		Q:box("CableBundle", V3(ctx.fx1 - ctx.fx0 - 1.2, 0.14, 0.4), CF((ctx.fx0 + ctx.fx1) / 2, H - 0.88, zb + 0.55), lk(rgb(40, 40, 44), M.Rubber))
	end)
end

-- 창고 바닥: 노란 안전선 (직원 문 -> 진열용 박스 자리) · 랙 앞 경고선
local function floorStock(ctx: any)
	local Q = ctx.Q
	local tape = lk(rgb(250, 200, 0), M.SmoothPlastic)
	Q:free(function()
		-- 통로 선 (문 앞 -> 창고 가운데)
		for _, z in { 7.6, 3.0 } do
			Q:box("FloorTape", V3(18.0, 0.02, 0.18), CF(-12.0, 0.012, z), tape)
		end
		-- 랙 앞 경고선 (노랑 · 검정)
		local decks = all(ctx, "RackDeck")
		local zf = -7.6
		for _, e in decks do
			zf = math.max(zf, e.mx.Z + 0.25)
		end
		Q:box("RackTape", V3(ctx.fx1 - ctx.fx0 - 4.5, 0.02, 0.22), CF((ctx.fx0 + ctx.fx1) / 2 - 1.0, 0.012, zf), tape)
		for x = ctx.fx0 + 3.0, ctx.fx1 - 6.0, 1.0 do
			Q:box("RackTapeStripe", V3(0.3, 0.022, 0.22), CF(x, 0.013, zf) * ANG(0, 0.6, 0), lk(rgb(30, 30, 30)))
		end
		txt(ctx, "FloorStencil", 3.0, 0.6, floorCF(V3(-12.0, 0.03, 5.3), -XA), "통로 · 적치 금지", rgb(250, 200, 0), nil, { font = F.GothamBlack, d = 0.005, free = true })
	end)
end

local function buildStock(K: any, V: any, S: any)
	local ctx = newCtx(K, V)
	local steps = {
		{ "racks", racks },
		{ "walkIn", walkIn },
		{ "desk", staffDesk },
		{ "lockers", lockers },
		{ "sinks", sinks },
		{ "cages", cagesAndPiles },
		{ "staffWall", staffWall },
		{ "ceiling", ceilingStock },
		{ "floor", floorStock },
	}
	for _, st in steps do
		local n0 = #K.parts
		local ok, err = pcall(st[2], ctx)
		if not ok then
			K:note("gs25." .. st[1] .. " error: " .. tostring(err))
		else
			K:note(string.format("gs25.%s +%d", st[1], #K.parts - n0))
		end
	end
	-- 조명 스위치 (직원 문 옆, 우리 불빛 · 네온 끄고 켜기)
	pcall(function()
		local Q = ctx.Q
		local bw = one(ctx, "BackWall", function(e)
			return e.s.X > 20
		end)
		local jamb = one(ctx, "StaffDoorJamb", function(e)
			return e.c.X > -18
		end)
		if bw and jamb then
			Q:free(function()
				local d = fc(V3(jamb.mx.X + 0.8, 4.3, bw.mn.Z), -ZA)
				local plate = Props.switchPlate(Q, d, 3)
				Interact.lightSwitch(K, plate, "창고 조명")
			end)
		end
	end)
end

---------------------------------------------------------------------------------------------------

function T.style(V: any): any
	if V.type == "stockroom" then
		return {
			chair = false, stool = false, table = false, counter = false, base = false, lower = false, mat = false,
			clock = false, license = false, cctv = false, ceiling = false, lights = { kind = "none" },
			skip = { fixtures = true, walls = true, floor = true, upgrades = true },
		}
	end
	return {
		chair = false, stool = false, table = false, counter = false, base = false, lower = false, mat = false,
		clock = false, license = false, cctv = false, ceiling = {}, lights = { kind = "none" },
		skip = { fixtures = true, walls = true, floor = true },
	}
end

function T.build(K: any, V: any, S: any)
	if V.type == "stockroom" then
		buildStock(K, V, S)
	else
		buildSales(K, V, S)
	end
end

return T

end

__defs["T_gym"] = function()
-- GwangalliBuildingInterior/T_gym: 큰 시설 방 유형 (gym) 실내 (Venues.luau 의 방, Scan.fitRoom).
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (Common.luau 머리말의 S 필드)
--   build(K, V, S) 유형별 디테일

local Look = __require("Look")
local Props = __require("Props")
local Interact = __require("Interact")
local Common = __require("Common")

local T = {}
T.types = { "gym" }

function T.style(V: any): any
	-- 기본: 기존 가구는 그대로, 천장 설비만 (모듈을 채우면서 바꿈)
	return { chair = false, stool = false, table = false, counter = false, base = false, lower = false, mat = false, clock = false, license = false, cctv = false, ceiling = {}, lights = { kind = "none" }, skip = { upgrades = true, fixtures = true } }
end

function T.build(K: any, V: any, S: any) end

return T

end

__defs["T_home"] = function()
-- GwangalliBuildingInterior/T_home: 생활 게임 집 (고시원 · 원룸 · 오피스텔 · 아파트 · 펜트하우스) 의 방 (Homes.luau, Scan.fitRoom).
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (Common.luau 머리말의 S 필드)
--   build(K, V, S) 방별 디테일

local Look = __require("Look")
local Props = __require("Props")
local Interact = __require("Interact")
local Common = __require("Common")

local T = {}
T.types = { "home" }

function T.style(V: any): any
	return { chair = false, stool = false, table = false, counter = false, base = false, lower = false, mat = false, clock = false, license = false, cctv = false, ceiling = false, lights = { kind = "none" }, skip = { upgrades = true, fixtures = true } }
end

function T.build(K: any, V: any, S: any) end

return T

end

__defs["T_karaoke"] = function()
-- GwangalliBuildingInterior/T_karaoke: 광안 코인노래연습장 (Venues: karaoke 로비 · kcorridor 복도 · kbooth 노래방 8칸).
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (+ 방 상자 보정: 부스의 문 · 가짜 유리 keep 을 실제 문 자리로)
--   build(K, V, S) 유형별 디테일
--
-- 게임플레이 계약 (bld/pcbang_karaoke.json): KaraokePanel · KaraokeZone · KaraokeScreen (화면 앞면 = 클라이언트 TV gui) ·
--   StatusLight · MirrorBall · Booth_NN 모델 · 좌석 Seat 6개 · TableTop · Board_karaoke · CardReader · LEDScreen · Sign_* 는
--   절대 숨기거나 덮지 않음. 소파 좌석은 같은 자세의 쿠션으로 감싸기만 (윗면 +0.02). 장식 쉘(소파 몸체 · 스피커 상자 ·
--   반주기 상자 · 흡음판 · 유리문 · 장식 소품)만 숨기고 같은 자리에 다시 만듦.
-- 부스 (kbooth): U자 가죽 소파(채널 등받이 · 버튼 쿠션 · 크롬 걸레받이 LED) · 실제 콘이 있는 스피커 · 랙 앰프 · 반주기(지금 곡 번호
--   표시) · 마이크 충전 거치대 · 코인기(남은 시간 표시: KPaidUntil) · 터치 선곡 패널 · 벽걸이 에어컨 · 조명 패널 · QRD 디퓨저 ·
--   채널 패딩 벽 · 별빛 천장 · 핀스폿 · 유리문(문 닫기/열기) · 피난안내도 · 유도등.
--   상호작용: 조명 모드 (기본/무드/파티/끄기), 에어컨 켜기/끄기, 문 닫기/열기 (+ 프롬프트 없는 실시간 표시 2종)
-- 로비 (karaoke): 동전교환기 · 음료 자판기 실물 오버레이, 대기 소파, 카운터 앞판, 직원 구역(마이크 충전 랙 · 캐비닛),
--   UV 살균기(살균하기) · 마이크 커버 디스펜서(뽑기), 방 현황판(실시간), 노래책 거치대, 미러볼 네온 링, 바닥 인레이,
--   X배너 · 우산꽂이 · 분리수거함 · 법정 게시물(청소년 출입시간 · 등록증 · 요금 변경 안내).
-- 복도 (kcorridor): 유광 블랙 징두리 · 신곡 포스터 라이트박스 · 문틀 리빌 · 러너 패턴 · 바닥 방 번호 · 천장 다운라이트/스피커/
--   유도등 · 소화기함 · 피난안내도 · 손 소독기(소독하기) · 안내 터치스크린(페이지 넘기기).

local Look = __require("Look")
local Props = __require("Props")
local Interact = __require("Interact")
local Common = __require("Common")
local Scan = __require("Scan")
local TweenService = game:GetService("TweenService")

local T = {}
T.types = { "karaoke", "kcorridor", "kbooth" }

local CF, V3 = CFrame.new, Vector3.new
local ANG = CFrame.Angles
local PI = math.pi
local M = Enum.Material
local F = Enum.Font
local rgb = Color3.fromRGB
local BLACK, WHITE = Color3.new(0, 0, 0), Color3.new(1, 1, 1)

-- 작은 도구 ------------------------------------------------------------------------------------------
local function dk(c: Color3, f: number): Color3
	return c:Lerp(BLACK, f)
end
local function lt(c: Color3, f: number): Color3
	return c:Lerp(WHITE, f)
end
local function lk(c: Color3, m: Enum.Material?, extra: { [string]: any }?): { [string]: any }
	local t: { [string]: any } = { c = c, m = m or M.SmoothPlastic }
	if extra then
		for k, v in extra do
			t[k] = v
		end
	end
	return t
end
local function neon(c: Color3, t: number?): { [string]: any }
	return { c = c, m = M.Neon, t = t or 0 }
end
local function rnd(seed: number, i: number): number
	local s = math.sin((seed % 9973) * 0.731 + i * 12.9898) * 43758.5453
	return s - math.floor(s)
end
-- 표시면 프레임 (점 p, 바깥 법선 n): +X = 보는 사람 오른쪽
local function faceCF(p: Vector3, n: Vector3): CFrame
	local x = Vector3.yAxis:Cross(n).Unit
	return CFrame.fromMatrix(p, x, Vector3.yAxis, n)
end
-- 위를 보는 글자판 (바닥 표시 · 책 표지): p 중심, 글자 위쪽 = up (수평)
local function topCF(p: Vector3, up: Vector3): CFrame
	local x = up:Cross(Vector3.yAxis).Unit
	return CFrame.fromMatrix(p, x, up, Vector3.yAxis)
end
-- 표시면에서 튀어나온 원판 (축 = dcf Z)
local function wdisc(K: any, name: string, dia: number, t: number, dcf: CFrame, look: any): BasePart
	return K:disc(name, dia, t, dcf * CF(0, 0, t / 2) * ANG(PI / 2, 0, 0), look)
end
local function snapAxis(v: Vector3): Vector3
	if math.abs(v.X) >= math.abs(v.Z) then
		return V3(if v.X >= 0 then 1 else -1, 0, 0)
	end
	return V3(0, 0, if v.Z >= 0 then 1 else -1)
end
local function hi(K: any): boolean
	return K.detail == "high"
end
local function lo(K: any): boolean
	return K.detail == "low"
end
local function hideRec(K: any, r: any)
	if r and r.part then
		Scan.hide(K.hidden, r.part)
	end
end
-- 파트 원래 축 (rec.lcf) 기준 프레임
local function recCF(r: any): CFrame
	return r.lcf :: CFrame
end
local function step(K: any, name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		K:note("karaoke." .. name .. " error: " .. tostring(err))
	end
end

-- 재질
local LACQ = lk(rgb(16, 15, 20), M.SmoothPlastic, { r = 0.08 }) -- 유광 블랙 래커
local GLOSS = lk(rgb(10, 10, 14), M.Glass, { r = 0.18 }) -- 유광 블랙 패널 (반사)
local CHROME = Look.chrome
local ALU = Look.alu
local DARKALU = Look.darkAlu
local RUBBER = Look.rubber
local CONE = lk(rgb(30, 30, 34), M.Fabric)
local GRILLE = lk(rgb(26, 26, 30), M.DiamondPlate)
local MICGRILLE = lk(rgb(176, 178, 186), M.DiamondPlate)

local NEONS = {
	pink = rgb(255, 60, 170), cyan = rgb(40, 240, 240), purple = rgb(170, 70, 255), green = rgb(60, 255, 120),
	amber = rgb(255, 160, 50), blue = rgb(40, 170, 255), red = rgb(255, 40, 60), yellow = rgb(255, 230, 60), white = rgb(240, 236, 255),
}

-- 노래 (GwangalliVenuesShared.SONGS 와 같은 제목 · 번호 = 38000 + i*131)
local SONGS = {
	"광안대교 불빛 아래", "민락동 치킨송", "2호선 막차", "갈매기 트로트", "썸머 모래성",
	"PC방 영웅", "새벽 편의점", "득근득근", "해운대 말고 광안리", "생일 축하해 친구야",
}
local ARTISTS = { "파도청년단", "바삭즈", "금련산 밴드", "김부산", "오션걸즈", "레벨업", "도시소년", "헬스보이즈", "수영구 청년회", "노래방 오리지널" }
local function songNo(i: number): number
	return 38000 + i * 131
end

-- 실제 천장 아랫면 (방 상자 높이 11.1 보다 0.05 위)
local function ceilingY(V: any): number
	local best = math.huge
	for _, nm in { "Ceiling", "CeilingBoard" } do
		for _, r in V.byName[nm] or {} do
			if r.size.X > 8 and r.size.Z > 8 then
				best = math.min(best, r.min.Y)
			end
		end
	end
	if best == math.huge then
		return V.H + 0.05
	end
	return best
end

-- 소파 오버레이 ----------------------------------------------------------------------------------------
local SOFA_PARTS = { Base = true, Plinth = true, Arm = true, Seat = true, BackCushion = true, Backrest = true }

local function sofaRoot(p: Instance): Instance?
	local a = p.Parent
	while a and a ~= workspace do
		if string.find(a.Name, "Sofa", 1, true) then
			return a
		end
		a = a.Parent
	end
	return nil
end

local function sofaGroups(V: any, accept: (any) -> boolean): { any }
	local by: { [Instance]: any } = {}
	local out = {}
	for _, r in V.parts do
		if SOFA_PARTS[r.name] and accept(r) then
			local root = sofaRoot(r.part)
			if root then
				local g = by[root]
				if not g then
					g = { root = root, recs = {} }
					by[root] = g
					table.insert(out, g)
				end
				table.insert(g.recs, r)
				if r.name == "Backrest" then
					g.back = r
				elseif r.name == "Base" then
					g.base = r
				end
			end
		end
	end
	return out
end

-- o = { color, led (Color3?), leds (목록: 조명 모드용) }
local function sofaOverlay(K: any, g: any, o: any)
	local back, base = g.back, g.base
	if not back or not base then
		return
	end
	local d = base.c - back.c
	local f = snapAxis(V3(d.X, 0, d.Z))
	local org = V3(back.c.X, 0, back.c.Z)
	local sf = CFrame.lookAt(org, org - f) -- +Z = 앉는 쪽(앞)
	local swap = math.abs(f.X) > 0.5
	local C: Color3 = o.color
	local up = lk(C, M.Leather)
	local side = lk(dk(C, 0.18), M.Leather)
	local pipe = lk(dk(C, 0.5), M.Leather)
	local btn = lk(dk(C, 0.42), M.Leather)
	local function loc(r: any): (Vector3, Vector3)
		local c = sf:PointToObjectSpace(r.c)
		local s = if swap then V3(r.size.Z, r.size.Y, r.size.X) else r.size
		return c, s
	end
	K:free(function()
		for _, r in g.recs do
			local c, s = loc(r)
			local at = sf * CF(c)
			local top = c.Y + s.Y / 2
			local bot = c.Y - s.Y / 2
			if r.name == "Plinth" then
				K:box("SofaKick", V3(s.X - 0.04, s.Y, s.Z - 0.04), at, Look.of(20, 20, 24, M.Metal))
				K:box("SofaKickTrim", V3(s.X - 0.04, 0.04, 0.03), at * CF(0, s.Y / 2 - 0.04, s.Z / 2 - 0.005), CHROME)
				if o.led then
					local p = K:box("SofaKickLED", V3(s.X - 0.3, 0.05, 0.03), at * CF(0, -0.02, s.Z / 2 - 0.005), neon(o.led))
					table.insert(o.leds, { p = p, c = o.led })
				end
			elseif r.name == "Base" then
				K:rbox("SofaBase", V3(s.X + 0.03, s.Y + 0.02, s.Z + 0.03), 0.12, at, side)
				K:box("SofaBaseTrim", V3(s.X - 0.2, 0.05, 0.02), at * CF(0, -s.Y / 2 + 0.16, s.Z / 2 + 0.02), CHROME)
			elseif r.name == "Backrest" then
				local dia = s.Z + 0.04
				local h = s.Y - dia / 2 + 0.02
				K:box("SofaBackrest", V3(s.X + 0.03, h, s.Z + 0.03), sf * CF(c.X, bot + h / 2, c.Z), up)
				K:cyl("SofaBackRoll", s.X + 0.03, dia, sf * CF(c.X, top - dia / 2 + 0.01, c.Z), up)
				K:cyl("SofaBackPipe", s.X + 0.05, 0.07, sf * CF(c.X, top - dia * 0.5 + 0.01, c.Z + dia / 2 - 0.01), pipe)
				-- 등받이 뒤쪽 세로 채널 (벽 쪽에서 살짝 보이는 옆면 선)
				if hi(K) then
					K:box("SofaBackSeam", V3(s.X + 0.04, 0.03, 0.02), sf * CF(c.X, bot + 0.6, c.Z + s.Z / 2 + 0.02), pipe)
				end
			elseif r.name == "Arm" then
				local dia = s.X + 0.05
				local h = s.Y - dia / 2 + 0.01
				K:box("SofaArm", V3(s.X + 0.04, h, s.Z + 0.04), sf * CF(c.X, bot + h / 2, c.Z), up)
				K:cyl("SofaArmRoll", s.Z + 0.04, dia, sf * CF(c.X, top - dia / 2 + 0.01, c.Z) * ANG(0, PI / 2, 0), up)
				K:box("SofaArmFront", V3(s.X + 0.06, h - 0.2, 0.03), sf * CF(c.X, bot + h / 2 + 0.05, c.Z + s.Z / 2 + 0.03), side)
				K:box("SofaArmTrim", V3(0.06, h - 0.4, 0.02), sf * CF(c.X, bot + h / 2 + 0.05, c.Z + s.Z / 2 + 0.05), CHROME)
			elseif r.name == "Seat" then
				-- Seat 은 숨기지 않음: 같은 자세 쿠션으로 감쌈 (윗면 +0.02)
				local th = 0.46
				K:rbox("SofaCushion", V3(s.X + 0.05, th, s.Z + 0.05), 0.15, sf * CF(c.X, top + 0.02 - th / 2, c.Z), up)
				K:cyl("SofaCushionPipe", s.X + 0.02, 0.06, sf * CF(c.X, top - 0.2, c.Z + s.Z / 2 + 0.03), pipe)
				if s.X > 3.6 then
					K:box("SofaCushionSeam", V3(0.05, 0.03, s.Z - 0.1), sf * CF(c.X, top + 0.03, c.Z), pipe)
					K:box("SofaCushionGap", V3(0.05, th - 0.1, 0.03), sf * CF(c.X, top - th / 2, c.Z + s.Z / 2 + 0.03), pipe)
				end
			elseif r.name == "BackCushion" then
				K:rbox("SofaBackCushion", V3(s.X - 0.03, s.Y, s.Z + 0.08), 0.19, at, up)
				if not lo(K) then
					local n = math.max(2, math.floor(s.X / 0.9))
					for i = 1, n do
						local x = -s.X / 2 + (i - 0.5) * s.X / n
						for _, yy in { 0.27, -0.2 } do
							K:ball("SofaButton", 0.11, at * CF(x, yy * s.Y, s.Z / 2 + 0.035), btn)
						end
					end
				end
			end
		end
	end)
	for _, r in g.recs do
		if r.name ~= "Seat" then
			hideRec(K, r)
		end
	end
end

-- 스피커 (드라이버: 서라운드 + 콘 + 더스트캡 + LED 링) ---------------------------------------------------
local function driver(K: any, dcf: CFrame, dia: number, ring: Color3?, leds: { any }?)
	if ring then
		local p = wdisc(K, "SpeakerLEDRing", dia + 0.1, 0.02, dcf, neon(ring))
		if leds then
			table.insert(leds, { p = p, c = ring })
		end
	end
	wdisc(K, "SpeakerSurround", dia, 0.05, dcf, RUBBER)
	wdisc(K, "SpeakerCone", dia * 0.78, 0.06, dcf, CONE)
	K:ball("SpeakerDustCap", dia * 0.28, dcf * CF(0, 0, 0.06), lk(rgb(40, 40, 44), M.Metal))
end

-- 세로 스피커 (FloorSpeaker): 둥근 모서리 캐비닛 + 그릴 테 + 우퍼 2 + 혼 트위터 + 포트 + 로고
local function columnSpeaker(K: any, r: any, ring: Color3?, leds: { any })
	local mn, mx = r.min, r.max
	local c = (mn + mx) / 2
	local w, h, d = mx.X - mn.X, mx.Y - mn.Y, mx.Z - mn.Z
	local front = mx.Z
	K:free(function()
		K:rbox("SpeakerCabinet", V3(h + 0.02, w + 0.06, d + 0.04), 0.1, CF(c.X, c.Y, c.Z) * ANG(0, 0, PI / 2), lk(rgb(22, 22, 26), M.SmoothPlastic, { r = 0.05 }))
		local f0 = faceCF(V3(c.X, 0, front + 0.02), V3(0, 0, 1))
		K:plate("SpeakerBaffle", w - 0.08, h - 0.3, 0.02, f0 * CF(0, c.Y, 0), lk(rgb(14, 14, 16)))
		for _, yy in { 1.35, 3.35 } do
			driver(K, f0 * CF(0, yy, 0.02), math.min(0.74, w - 0.16), ring, leds)
		end
		K:plate("SpeakerHorn", w - 0.3, 0.42, 0.06, f0 * CF(0, 4.85, 0.02), lk(rgb(34, 34, 38), M.Metal))
		K:plate("SpeakerHornThroat", 0.34, 0.2, 0.07, f0 * CF(0, 4.85, 0.02), lk(rgb(8, 8, 10)))
		K:ball("SpeakerTweeter", 0.14, f0 * CF(0, 4.85, 0.08), lk(rgb(190, 190, 196), M.Metal))
		K:plate("SpeakerPort", w - 0.36, 0.12, 0.03, f0 * CF(0, 0.42, 0.02), lk(rgb(4, 4, 6)))
		K:text("SpeakerBadge", 0.36, 0.1, f0 * CF(0, 5.3, 0.02), "GW·PRO", { fg = rgb(200, 200, 206), font = F.GothamBlack, d = 0.01 })
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				K:vcyl("SpeakerFoot", 0.06, 0.16, CF(c.X + sx * (w / 2 - 0.12), 0.03, c.Z + sz * (d / 2 - 0.15)), CHROME)
			end
		end
	end)
end

-- 천장 모서리 스피커 (Speaker): 캐비닛 + 그릴 + 벽 브래킷
local function wallSpeaker(K: any, r: any)
	local mn, mx = r.min, r.max
	local c = (mn + mx) / 2
	local w, h, d = mx.X - mn.X, mx.Y - mn.Y, mx.Z - mn.Z
	K:free(function()
		K:rbox("WallSpeakerBox", V3(h, w + 0.04, d + 0.02), 0.08, CF(c) * ANG(0, 0, PI / 2), lk(rgb(26, 26, 30)))
		local f0 = faceCF(V3(c.X, c.Y, mx.Z + 0.01), V3(0, 0, 1))
		K:plate("WallSpeakerGrille", w - 0.14, h - 0.18, 0.03, f0, GRILLE)
		driver(K, f0 * CF(0, 0.25, 0.03), 0.8, nil, nil)
		K:ball("WallSpeakerTweet", 0.16, f0 * CF(0, -0.68, 0.05), lk(rgb(170, 170, 176), M.Metal))
		for _, sx in { -1, 1 } do
			K:box("WallSpeakerBracket", V3(0.06, 0.5, d * 0.7), CF(c.X + sx * (w / 2 + 0.05), c.Y, c.Z - d * 0.1), DARKALU)
			wdisc(K, "WallSpeakerKnob", 0.16, 0.05, faceCF(V3(c.X + sx * (w / 2 + 0.08), c.Y, c.Z), V3(sx, 0, 0)), DARKALU)
		end
	end)
end

local function subwoofer(K: any, r: any, ring: Color3?, leds: { any })
	local mn, mx = r.min, r.max
	local c = (mn + mx) / 2
	local w, h, d = mx.X - mn.X, mx.Y - mn.Y, mx.Z - mn.Z
	K:free(function()
		K:rbox("SubCabinet", V3(w + 0.04, h + 0.02, d + 0.04), 0.08, CF(c), lk(rgb(20, 20, 24), M.SmoothPlastic, { r = 0.04 }))
		local f0 = faceCF(V3(c.X, c.Y + 0.08, mx.Z + 0.02), V3(0, 0, 1))
		driver(K, f0, math.min(1.02, w - 0.2), ring, leds)
		K:plate("SubPort", w - 0.4, 0.1, 0.02, f0 * CF(0, -h / 2 + 0.2, 0), lk(rgb(4, 4, 6)))
		K:text("SubBadge", 0.5, 0.1, f0 * CF(0, h / 2 - 0.16, 0), "SUB 12\"", { fg = rgb(190, 190, 196), font = F.GothamBold, d = 0.01 })
	end)
end

-- 마이크 (손잡이 + 밴드 + 그릴 볼): a = 손잡이 끝, b = 그릴 쪽 (로컬 점)
local function handMic(K: any, a: Vector3, b: Vector3, body: any, band: Color3, cover: Color3?)
	local dir = (b - a).Unit
	K:seg("MicBodyTail", a, a:Lerp(b, 0.55), 0.24, body)
	K:seg("MicBodyNeck", a:Lerp(b, 0.55), b - dir * 0.18, 0.3, body)
	K:seg("MicBand", b - dir * 0.22, b - dir * 0.16, 0.32, neon(band))
	local head = b + dir * 0.1
	if cover then
		K:ball("MicCoverSponge", 0.5, CF(head), lk(cover, M.Fabric))
	else
		K:ball("MicGrille", 0.44, CF(head), MICGRILLE)
	end
	K:seg("MicSwitch", a:Lerp(b, 0.6) + V3(0, 0.13, 0), a:Lerp(b, 0.7) + V3(0, 0.13, 0), 0.06, lk(rgb(60, 60, 64)))
end

-- 상태 · 테마 ------------------------------------------------------------------------------------------
local function boothModel(V: any): Instance?
	local best, bd = nil, math.huge
	for _, r in V.byName.KaraokeZone or {} do
		local d = math.abs(r.c.X) + math.abs(r.c.Z)
		if d < bd then
			best, bd = r, d
		end
	end
	if best and bd < 3 then
		return best.part.Parent
	end
	return nil
end

local function attr(m: Instance?, k: string): any
	if not m then
		return nil
	end
	local ok, v = pcall(function()
		return m:GetAttribute(k)
	end)
	return if ok then v else nil
end

local function serverNow(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return if ok and type(t) == "number" then t else os.clock()
end

local function rented(m: Instance?): boolean
	local r = attr(m, "KRenter")
	return type(r) == "number" and r ~= 0
end

-- 조명 모드 묶음 (부스) ---------------------------------------------------------------------------------
-- st = { leds = { {p, c} }, stars = { p }, lights = { {l, c, b} }, mode = 1 }
local MODES = { "기본", "무드", "파티", "끄기" }
local WARM = rgb(255, 136, 60)

local function applyMode(st: any, t: number)
	local mode = st.mode
	for i, e in st.leds do
		local p: BasePart = e.p
		if p.Parent then
			if mode == 4 then
				p.Material = M.SmoothPlastic
				p.Color = dk(e.c, 0.75)
			elseif mode == 3 then
				p.Material = M.Neon
				p.Color = Color3.fromHSV((t * 0.18 + i * 0.07) % 1, 0.85, 1)
			elseif mode == 2 then
				p.Material = M.Neon
				p.Color = e.c:Lerp(WARM, 0.75)
			else
				p.Material = M.Neon
				p.Color = e.c
			end
		end
	end
	for i, p in st.stars do
		if p.Parent then
			if mode == 4 then
				p.Transparency = 1
			elseif mode == 3 then
				p.Transparency = if rnd(i, math.floor(t * 6)) > 0.55 then 0 else 0.85
			else
				p.Transparency = if mode == 2 then 0.35 else 0
			end
		end
	end
	for i, e in st.lights do
		local l: any = e.l
		if l.Parent then
			l.Enabled = mode ~= 4 and not (e.party and mode ~= 3)
			if mode == 3 then
				l.Color = Color3.fromHSV((t * 0.18 + i * 0.21) % 1, 0.8, 1)
				l.Brightness = e.b * 1.15
			elseif mode == 2 then
				l.Color = e.c:Lerp(WARM, 0.75)
				l.Brightness = e.b * 0.55
			else
				l.Color = e.c
				l.Brightness = e.b
			end
		end
	end
	for i, p in st.buttons or {} do
		if p.Parent then
			p.Material = if i == mode then M.Neon else M.SmoothPlastic
			p.Transparency = if i == mode then 0 else 0.1
		end
	end
end

local function addLight(K: any, st: any, part: BasePart, kind: string, props: { [string]: any }, party: boolean?): Light?
	local l = K:light(part, kind, props)
	if l then
		table.insert(st.lights, { l = l, c = props.Color or WHITE, b = props.Brightness or 1, party = party })
		if party then
			l.Enabled = false
		end
	end
	return l
end

-- =====================================================================================================
-- 부스 (kbooth)
-- =====================================================================================================
local function boothBuild(K: any, V: any, S: any)
	local booth = boothModel(V)
	local function mine(r: any): boolean
		return booth ~= nil and r.part:IsDescendantOf(booth)
	end
	local function first(name: string): any?
		for _, r in V.byName[name] or {} do
			if mine(r) then
				return r
			end
		end
		return nil
	end
	local function all(name: string): { any }
		local out = {}
		for _, r in V.byName[name] or {} do
			if mine(r) then
				table.insert(out, r)
			end
		end
		return out
	end
	local roomNo = tonumber(attr(booth, "RoomNo")) or tonumber(string.match(tostring(V.room or ""), "%d+")) or 1
	local H = S.ceilY or V.H
	-- 테마: 맵의 LED 띠 색 · 패브릭 벽 색 · 소파 색
	local ledR = first("LedStrip")
	local theme: Color3 = if ledR then ledR.part.Color else NEONS.cyan
	local accR = first("AccentWall")
	local fabric: Color3 = if accR then accR.part.Color else rgb(30, 42, 120)
	local baseR = first("Base")
	local leather: Color3 = if baseR then baseR.part.Color else rgb(130, 26, 30)
	local zBack = if accR then accR.max.Z else V.z0
	local cw = first("CorridorWall")
	local zFront = if cw then cw.min.Z else V.z1
	local x0, x1 = V.x0, V.x1
	local st: any = { leds = {}, stars = {}, lights = {}, mode = 1, buttons = {} }
	K.kst = st
	local wallTone = lk(dk(fabric, 0.55), M.Fabric)
	local panelTone = lk(lt(dk(fabric, 0.15), 0.06), M.Fabric)

	-- 1) 소파 (U자 3개) -------------------------------------------------------------------------------
	step(K, "sofa", function()
		for _, g in sofaGroups(V, mine) do
			sofaOverlay(K, g, { color = leather, led = theme, leds = st.leds })
		end
	end)

	-- 2) 테이블: 받침 다시 + 유리 상판 크롬 테 (상판 · 위 소품 자리 그대로) -------------------------------------
	step(K, "table", function()
		local tb = first("TableBase")
		local tt = first("TableTop")
		K:free(function()
			if tb then
				local c = tb.c
				local s = tb.size
				K:rbox("TablePedestal", V3(s.Y - 0.02, s.X - 0.04, s.Z - 0.04), 0.3, CF(c.X, c.Y, c.Z) * ANG(0, 0, PI / 2), LACQ)
				K:box("TableBand", V3(s.X - 0.02, 0.06, s.Z - 0.02), CF(c.X, tb.max.Y - 0.06, c.Z), CHROME)
				local p = K:box("TableLEDLine", V3(s.X + 0.0, 0.05, s.Z + 0.0), CF(c.X, 0.42, c.Z), neon(theme))
				table.insert(st.leds, { p = p, c = theme })
				hideRec(K, tb)
			end
			if tt then
				local mn, mx = tt.min, tt.max
				local cy = (mn.Y + mx.Y) / 2
				local h = mx.Y - mn.Y - 0.03
				local cx, cz = (mn.X + mx.X) / 2, (mn.Z + mx.Z) / 2
				local w, l = mx.X - mn.X, mx.Z - mn.Z
				K:box("TableRim", V3(w + 0.06, h, 0.04), CF(cx, cy - 0.015, mx.Z + 0.02), CHROME)
				K:box("TableRim", V3(w + 0.06, h, 0.04), CF(cx, cy - 0.015, mn.Z - 0.02), CHROME)
				K:box("TableRim", V3(0.04, h, l + 0.02), CF(mx.X + 0.02, cy - 0.015, cz), CHROME)
				K:box("TableRim", V3(0.04, h, l + 0.02), CF(mn.X - 0.02, cy - 0.015, cz), CHROME)
			end
		end)
	end)

	-- 3) 테이블 위 소품 (같은 자리 다시: 마이크 · 탬버린 · 노래책 · 리모컨 · 안내 스탠드) ------------------------------
	step(K, "tableItems", function()
		K:free(function()
			local mics = all("WirelessMic")
			local heads = all("WirelessMicHead")
			for i, m in mics do
				local cfm = recCF(m)
				local ax = cfm.XVector
				local len = m.part.Size.X
				local pA = cfm.Position + ax * len / 2
				local pB = cfm.Position - ax * len / 2
				-- 그릴 쪽 = 머리에 가까운 끝
				local hd = heads[i]
				if hd and (hd.c - pA).Magnitude < (hd.c - pB).Magnitude then
					pA, pB = pB, pA
				end
				local y = m.c.Y
				pA = V3(pA.X, y, pA.Z)
				pB = V3(pB.X, y, pB.Z)
				local body = if m.part.Color.R > 0.5 then lk(rgb(232, 232, 236), M.SmoothPlastic, { r = 0.05 }) else lk(rgb(30, 30, 34), M.SmoothPlastic, { r = 0.05 })
				handMic(K, pA, pB, body, if i == 1 then theme else NEONS.pink, if i == 2 then rgb(220, 40, 60) else nil)
				hideRec(K, m)
				if hd then
					hideRec(K, hd)
				end
			end
			local tam = first("Tambourine")
			if tam then
				local c = tam.c
				local dia = tam.size.X
				local base = CF(c.X, tam.min.Y, c.Z)
				K:disc("TambourineRim", dia, 0.2, base * CF(0, 0.1, 0), lk(rgb(250, 204, 20), M.Plastic))
				K:disc("TambourineHole", dia * 0.62, 0.21, base * CF(0, 0.1, 0), lk(rgb(30, 30, 36)))
				K:box("TambourineGrip", V3(dia * 0.62, 0.16, 0.18), base * CF(0, 0.1, 0), lk(rgb(250, 204, 20), M.Plastic))
				for j = 0, 4 do
					local a = j * 2 * PI / 5 + 0.3
					local r0 = dia * 0.4
					local p = base * CF(math.cos(a) * r0, 0.1, math.sin(a) * r0)
					K:box("TambourineSlot", V3(0.3, 0.22, 0.16), p * ANG(0, -a, 0), lk(rgb(20, 20, 24)))
					K:disc("TambourineJingle", 0.22, 0.03, p * CF(0, 0.05, 0), lk(rgb(214, 218, 226), M.Metal, { r = 0.2 }))
					K:disc("TambourineJingle", 0.22, 0.03, p * CF(0, -0.05, 0), lk(rgb(214, 218, 226), M.Metal, { r = 0.2 }))
				end
				hideRec(K, tam)
				for _, j in all("Jingle") do
					hideRec(K, j)
				end
			end
			local book = first("SongBook")
			if book then
				local c, s = book.c, book.size
				local th = s.Y
				K:box("SongBookCover", V3(s.X, 0.06, s.Z), CF(c.X, book.min.Y + 0.03, c.Z), lk(dk(theme, 0.35)))
				K:box("SongBookPages", V3(s.X - 0.08, th - 0.12, s.Z - 0.06), CF(c.X + 0.02, c.Y, c.Z), lk(rgb(240, 236, 226)))
				K:box("SongBookCover", V3(s.X, 0.06, s.Z), CF(c.X, book.max.Y - 0.03, c.Z), lk(dk(theme, 0.35)))
				K:box("SongBookSpine", V3(0.08, th, s.Z), CF(book.min.X + 0.04, c.Y, c.Z), lk(dk(theme, 0.55)))
				for j, col in { NEONS.red, NEONS.yellow, NEONS.green, NEONS.blue } do
					K:box("SongBookTab", V3(0.12, 0.04, 0.2), CF(book.max.X + 0.02, c.Y + 0.1 - j * 0.05, book.min.Z + 0.3 + j * 0.28), lk(col))
				end
				K:text("SongBookTitle", s.X - 0.2, s.Z * 0.5, topCF(V3(c.X, book.max.Y + 0.002, c.Z), V3(0, 0, -1)), "노래방 책\n2026 최신곡", { fg = WHITE, font = F.GothamBlack, d = 0.01, free = true })
				hideRec(K, book)
				hideRec(K, first("SongBookLabel"))
			end
			local rem = first("Remote")
			if rem then
				local cfr = recCF(rem)
				local s = rem.part.Size
				local long = if s.Z >= s.X then cfr.ZVector else cfr.XVector
				local L = math.max(s.X, s.Z)
				local Wd = math.min(s.X, s.Z)
				local c = V3(rem.c.X, rem.min.Y, rem.c.Z)
				local frame = CFrame.lookAt(c, c + V3(long.X, 0, long.Z)) -- -Z = 리모컨 앞(화면 쪽)
				K:rbox("RemoteBody", V3(Wd + 0.02, 0.12, L), 0.05, frame * CF(0, 0.06, 0) * ANG(0, PI / 2, 0) * ANG(0, -PI / 2, 0), lk(rgb(28, 28, 32), M.SmoothPlastic, { r = 0.06 }))
				K:box("RemoteScreen", V3(Wd - 0.08, 0.02, 0.24), frame * CF(0, 0.125, -L / 2 + 0.2), lk(rgb(60, 200, 230), M.Neon, { t = 0.2 }))
				if not lo(K) then
					for row = 0, 3 do
						for col = -1, 1 do
							K:box("RemoteKey", V3(0.07, 0.025, 0.06), frame * CF(col * 0.09, 0.125, -L / 2 + 0.46 + row * 0.1), lk(rgb(200, 200, 206)))
						end
					end
				end
				K:box("RemoteKeyRes", V3(0.12, 0.03, 0.08), frame * CF(-0.06, 0.13, L / 2 - 0.18), lk(rgb(40, 120, 230)))
				K:box("RemoteKeyCancel", V3(0.12, 0.03, 0.08), frame * CF(0.07, 0.13, L / 2 - 0.18), lk(rgb(220, 40, 50)))
				hideRec(K, rem)
				hideRec(K, first("RemoteKeys"))
			end
			local ms = first("MenuStand")
			if ms then
				local c = V3(ms.c.X, ms.min.Y, ms.c.Z)
				local w = math.max(ms.size.X, ms.size.Z) * 0.9
				local along = if ms.size.X >= ms.size.Z then V3(1, 0, 0) else V3(0, 0, 1)
				local n = V3(0, 0, 1):Cross(Vector3.yAxis) -- 임시
				n = Vector3.yAxis:Cross(along)
				K:box("MenuStandFoot", V3(w, 0.04, 0.42), CFrame.fromMatrix(c + V3(0, 0.02, 0), along, Vector3.yAxis, n), lk(rgb(240, 240, 244), M.Glass, { t = 0.3 }))
				for _, sgn in { 1, -1 } do
					local nn = n * sgn
					local d0 = faceCF(c + V3(0, 0.38, 0) + nn * 0.09, nn) * ANG(math.rad(-12), 0, 0)
					K:text("MenuStandCard", w - 0.06, 0.66, d0, "이용 안내\n30분 500원 · 자동 연장\n문 옆 패널에서 방 잡기\n주류 · 흡연 금지", { fg = rgb(30, 30, 40), bg = rgb(250, 248, 240), d = 0.02, font = F.GothamBold, free = true })
				end
				hideRec(K, ms)
			end
			-- 컵: 빨대 · 얼음
			for i, cp in all("Cup") do
				local top = cp.max.Y
				K:seg("CupStraw", V3(cp.c.X, top - 0.3, cp.c.Z), V3(cp.c.X + 0.12, top + 0.32, cp.c.Z - 0.08), 0.05, lk(if i == 1 then rgb(240, 80, 120) else rgb(60, 160, 240)))
				K:disc("CupIce", cp.size.X * 0.8, 0.04, CF(cp.c.X, top - 0.12, cp.c.Z), lk(rgb(220, 236, 244), M.Glass, { t = 0.3 }))
			end
			local tissue = first("TissueBox")
			if tissue then
				K:ell("TissuePuff", V3(0.3, 0.26, 0.22), CF(tissue.c.X, tissue.max.Y + 0.08, tissue.c.Z), lk(rgb(250, 250, 248), M.Fabric))
				K:box("TissueBand", V3(tissue.size.X + 0.01, 0.1, tissue.size.Z + 0.01), CF(tissue.c.X, tissue.c.Y, tissue.c.Z), lk(dk(theme, 0.3)))
			end
		end)
	end)

	-- 4) TV 벽: 베젤 테 · LED 헤일로 · 위 네온 간판 · 옆 LED 바 (화면 앞면은 비움) ------------------------------
	step(K, "tvwall", function()
		local bez = first("TVBezel")
		local scr = first("KaraokeScreen")
		if bez and scr then
			local bmn, bmx = bez.min, bez.max
			local smn, smx = scr.min, scr.max
			local zf = bmx.Z -- 베젤 앞면
			local cx = (bmn.X + bmx.X) / 2
			local fz = faceCF(V3(cx, 0, zf), V3(0, 0, 1))
			K:free(function()
				-- 화면 바깥 테두리 (화면 사각형 밖만)
				local topH = bmx.Y - smx.Y
				local botH = smn.Y - bmn.Y
				local sideW = (bmx.X - bmn.X - (smx.X - smn.X)) / 2
				local bw = bmx.X - bmn.X
				K:plate("TVFrameTop", bw, topH, 0.05, fz * CF(0, smx.Y + topH / 2, 0), GLOSS)
				K:plate("TVFrameBot", bw, botH, 0.05, fz * CF(0, bmn.Y + botH / 2, 0), GLOSS)
				K:plate("TVFrameSide", sideW, smx.Y - smn.Y, 0.05, fz * CF(-bw / 2 + sideW / 2, (smn.Y + smx.Y) / 2, 0), GLOSS)
				K:plate("TVFrameSide", sideW, smx.Y - smn.Y, 0.05, fz * CF(bw / 2 - sideW / 2, (smn.Y + smx.Y) / 2, 0), GLOSS)
				for _, sy in { -1, 1 } do
					K:plate("TVTrim", bw, 0.035, 0.06, fz * CF(0, (bmn.Y + bmx.Y) / 2 + sy * ((bmx.Y - bmn.Y) / 2 - 0.0175), 0), CHROME)
					K:plate("TVTrim", 0.035, bmx.Y - bmn.Y, 0.06, fz * CF(sy * (bw / 2 - 0.0175), (bmn.Y + bmx.Y) / 2, 0), CHROME)
				end
				K:text("TVLogo", 1.0, math.min(0.12, botH * 0.7), fz * CF(0, bmn.Y + botH / 2, 0.055), "GW MEDIA", { fg = rgb(170, 170, 180), font = F.GothamBold, d = 0.005 })
				K:plate("TVPowerLED", 0.06, 0.04, 0.06, fz * CF(bw / 2 - 0.3, bmn.Y + botH / 2, 0.01), Look.ledRed)
				-- 벽 쪽 LED 헤일로 (베젤 밖으로 0.1 삐져나온 빛 테)
				local zw = zBack + 0.01
				local hz = faceCF(V3(cx, 0, zw), V3(0, 0, 1))
				local hw, hh = bw + 0.24, (bmx.Y - bmn.Y) + 0.24
				local hc = (bmn.Y + bmx.Y) / 2
				local parts = {
					K:plate("TVHaloLED", hw, 0.08, 0.05, hz * CF(0, hc + hh / 2 - 0.04, 0), neon(theme)),
					K:plate("TVHaloLED", hw, 0.08, 0.05, hz * CF(0, hc - hh / 2 + 0.04, 0), neon(theme)),
					K:plate("TVHaloLED", 0.08, hh, 0.05, hz * CF(-hw / 2 + 0.04, hc, 0), neon(theme)),
					K:plate("TVHaloLED", 0.08, hh, 0.05, hz * CF(hw / 2 - 0.04, hc, 0), neon(theme)),
				}
				for _, p in parts do
					table.insert(st.leds, { p = p, c = theme })
				end
				addLight(K, st, parts[1], "PointLight", { Range = 9, Brightness = 0.7, Color = theme })
				-- 위: 네온 간판 (검정 아크릴 + 글자)
				local sy0 = bmx.Y + 0.35
				local sh = math.min(1.2, H - 0.75 - sy0)
				if sh > 0.6 then
					K:plate("TVTopSignBack", 5.6, sh, 0.08, hz * CF(0, sy0 + sh / 2, 0), GLOSS)
					local p = K:text("TVTopSign", 5.2, sh * 0.72, hz * CF(0, sy0 + sh / 2, 0.1), string.format("♪ ROOM %02d  ·  SING SING", roomNo), { fg = theme, glow = 2.2, font = F.FredokaOne, d = 0.02 })
					local _ = p
					local ln = K:plate("TVTopSignLine", 5.4, 0.04, 0.1, hz * CF(0, sy0 + 0.06, 0), neon(theme))
					table.insert(st.leds, { p = ln, c = theme })
				end
				-- 옆 세로 LED 바 (바닥 스피커 위 · 천장 스피커 아래)
				for _, sx in { -1, 1 } do
					local x = sx * ((bmx.X - bmn.X) / 2 + 0.62)
					local p = K:plate("TVSideLED", 0.1, 2.2, 0.06, hz * CF(x, 6.9, 0), neon(theme))
					table.insert(st.leds, { p = p, c = theme })
					K:plate("TVSideLEDBack", 0.3, 2.4, 0.03, hz * CF(x, 6.9, 0), GLOSS)
				end
			end)
		end
	end)

	-- 5) AV 장 · 반주기 · 마이크 충전 거치대 ------------------------------------------------------------------
	step(K, "av", function()
		local cab = first("MachineCabinet")
		local ctop = first("CabinetTop")
		K:free(function()
			if cab then
				local mn, mx = cab.min, cab.max
				local c = (mn + mx) / 2
				local w, h, d = mx.X - mn.X + 0.06, mx.Y - mn.Y, mx.Z - mn.Z + 0.04
				local zf = mx.Z + 0.02
				-- 몸체 (옆판 · 뒤판 · 바닥 · 칸막이: 앞 0.18 들어간 칸)
				local rec = 0.18
				K:box("CabinetSide", V3(0.12, h, d), CF(mn.X - 0.03 + 0.06, c.Y, c.Z), LACQ)
				K:box("CabinetSide", V3(0.12, h, d), CF(mx.X + 0.03 - 0.06, c.Y, c.Z), LACQ)
				K:box("CabinetBack", V3(w - 0.2, h, d - rec), CF(c.X, c.Y, c.Z - rec / 2), lk(rgb(10, 10, 12)))
				K:box("CabinetKick", V3(w - 0.24, 0.24, 0.05), CF(c.X, 0.12, zf - rec - 0.02), lk(rgb(8, 8, 10)))
				K:box("CabinetShelf", V3(w - 0.2, 0.08, d), CF(c.X, 0.28, c.Z), LACQ)
				local bayW = (w - 0.24 - 0.16) / 3
				local xs = { mn.X + 0.12 + bayW / 2, c.X, mx.X - 0.12 - bayW / 2 }
				for _, dx in { -1, 1 } do
					K:box("CabinetDivider", V3(0.08, h - 0.32, d), CF(c.X + dx * (bayW / 2 + 0.04), c.Y + 0.14, c.Z), LACQ)
				end
				K:box("CabinetFrontTrim", V3(w, 0.04, 0.03), CF(c.X, mx.Y - 0.05, zf), CHROME)
				local fz = faceCF(V3(0, 0, zf - rec + 0.02), V3(0, 0, 1))
				-- 왼쪽 칸: 앰프 (VU 미터 2 · 노브 4) + 무선 수신기
				do
					local x = xs[1]
					K:plate("AmpFace", bayW - 0.06, 0.95, 0.06, fz * CF(x, 1.85, 0), lk(rgb(176, 178, 184), M.Metal))
					for k, ux in { -0.42, 0.06 } do
						K:plate("AmpVU", 0.42, 0.26, 0.07, fz * CF(x + ux, 2.08, 0), lk(rgb(255, 176, 80), M.Neon, { t = 0.15 }))
						K:plate("AmpNeedle", 0.02, 0.2, 0.08, fz * CF(x + ux - 0.04 + k * 0.03, 2.06, 0) * ANG(0, 0, 0.35 - k * 0.5), lk(rgb(20, 20, 20)))
					end
					for k = 0, 3 do
						wdisc(K, "AmpKnob", 0.17, 0.08, fz * CF(x - 0.6 + k * 0.4, 1.6, 0.06), lk(rgb(30, 30, 34), M.Metal))
					end
					K:text("AmpLabel", bayW - 0.2, 0.09, fz * CF(x, 1.45, 0.065), "MIC    ECHO    MUSIC    MASTER", { fg = rgb(30, 30, 34), font = F.GothamBold, d = 0.005 })
					K:text("AmpBrand", 0.5, 0.08, fz * CF(x + 0.55, 2.24, 0.065), "GW-A800", { fg = rgb(30, 30, 34), font = F.GothamBlack, d = 0.005 })
					K:plate("RxFace", bayW - 0.06, 0.5, 0.06, fz * CF(x, 1.0, 0), lk(rgb(22, 22, 26), M.Metal))
					for k, ux in { -0.35, 0.35 } do
						K:plate("RxLCD", 0.5, 0.2, 0.065, fz * CF(x + ux, 1.05, 0), lk(rgb(30, 60, 110)))
						K:text("RxLCDText", 0.46, 0.16, fz * CF(x + ux, 1.05, 0.07), if k == 1 then "A 638.2" else "B 645.5", { fg = rgb(140, 220, 255), glow = 1.4, font = F.Arcade, d = 0.005 })
					end
					K:plate("RxLED", 0.05, 0.05, 0.07, fz * CF(x + 0.8, 0.86, 0), Look.ledGreen)
					K:plate("BayVent", bayW - 0.06, 0.38, 0.03, fz * CF(x, 0.55, 0), lk(rgb(12, 12, 14)))
					for k = 0, 2 do
						K:plate("BayVentSlot", bayW - 0.3, 0.03, 0.04, fz * CF(x, 0.45 + k * 0.1, 0), lk(rgb(40, 40, 44)))
					end
				end
				-- 가운데 칸: 열린 선반 (노래책 · 마이크 커버 상자 · 건전지)
				do
					local x = xs[2]
					local sy = 1.32
					K:box("CabinetMidShelf", V3(bayW, 0.06, d - rec - 0.05), CF(x, sy, c.Z - rec / 2), LACQ)
					for k = 0, 2 do
						local th = 0.22 + k * 0.03
						K:box("ShelfSongBook", V3(bayW * 0.8, th, 1.2), CF(x, 0.32 + 0.06 + k * 0.27 + th / 2, zf - rec - 0.75), lk(({ rgb(200, 40, 60), rgb(40, 90, 200), rgb(250, 190, 30) })[k + 1]))
					end
					K:box("ShelfCoverBox", V3(0.8, 0.5, 0.6), CF(x - 0.25, sy + 0.28, zf - rec - 0.5), lk(rgb(240, 240, 236)))
					K:text("ShelfCoverLabel", 0.7, 0.26, faceCF(V3(x - 0.25, sy + 0.3, zf - rec - 0.19), V3(0, 0, 1)), "마이크 커버\n100매", { fg = rgb(220, 40, 90), font = F.GothamBold, d = 0.005 })
					K:box("ShelfBattery", V3(0.5, 0.3, 0.4), CF(x + 0.4, sy + 0.18, zf - rec - 0.4), lk(rgb(30, 30, 30)))
					K:plate("ShelfBatteryBand", 0.5, 0.1, 0.01, faceCF(V3(x + 0.4, sy + 0.18, zf - rec - 0.2), V3(0, 0, 1)), lk(rgb(250, 190, 30)))
				end
				-- 오른쪽 칸: 스모크 유리문 (안에 파워 분배기 LED)
				do
					local x = xs[3]
					K:plate("PowerUnit", bayW - 0.1, 0.4, 0.04, fz * CF(x, 1.5, 0), lk(rgb(26, 26, 30), M.Metal))
					for k = 0, 3 do
						K:plate("PowerLED", 0.06, 0.06, 0.05, fz * CF(x - 0.5 + k * 0.3, 1.5, 0), if k < 3 then Look.ledBlue else Look.ledRed)
					end
					local dz = zf - 0.02
					local fd = faceCF(V3(x, 0, dz), V3(0, 0, 1))
					K:plate("CabinetGlassDoor", bayW - 0.02, h - 0.42, 0.03, fd * CF(0, 0.32 + (h - 0.42) / 2, 0), lk(rgb(40, 40, 50), M.Glass, { t = 0.45, r = 0.15 }))
					K:plate("CabinetDoorPull", 0.05, 0.8, 0.06, fd * CF(-bayW / 2 + 0.16, 1.3, 0.03), CHROME)
				end
			end
			if ctop then
				local mn, mx = ctop.min, ctop.max
				K:box("CabinetTopStone", V3(mx.X - mn.X + 0.06, mx.Y - mn.Y + 0.02, mx.Z - mn.Z + 0.04), CF((mn + mx) / 2), lk(rgb(34, 30, 40), M.Marble, { r = 0.06 }))
				K:box("CabinetTopEdge", V3(mx.X - mn.X + 0.08, 0.04, 0.03), CF((mn.X + mx.X) / 2, mn.Y + 0.03, mx.Z + 0.03), CHROME)
				-- 안테나 (무선 수신기)
				for k, x in { mn.X + 0.35, mn.X + 0.85 } do
					K:seg("RxAntenna", V3(x, mx.Y, mn.Z + 0.35), V3(x + (k - 1.5) * 0.4, mx.Y + 1.1, mn.Z + 0.25), 0.06, lk(rgb(20, 20, 22)))
				end
				-- 왼쪽 끝: 손 소독제 · 휴지
				K:vcyl("SanitizerBottle", 0.5, 0.26, CF(mn.X + 0.45, mx.Y + 0.25, mx.Z - 0.4), lk(rgb(220, 236, 244), M.Glass, { t = 0.3 }))
				K:vcyl("SanitizerPump", 0.14, 0.1, CF(mn.X + 0.45, mx.Y + 0.57, mx.Z - 0.4), lk(rgb(240, 240, 240)))
			end
			for _, r in { cab, ctop, first("CabinetSeam") } do
				hideRec(K, r)
			end
			-- 반주기
			local km = first("KaraokeMachine")
			if km then
				local mn, mx = km.min, km.max
				local c = (mn + mx) / 2
				local w, h, d = mx.X - mn.X, mx.Y - mn.Y, mx.Z - mn.Z
				K:rbox("KMBody", V3(w + 0.04, h + 0.02, d + 0.04), 0.06, CF(c), lk(rgb(40, 42, 48), M.Metal))
				local fz = faceCF(V3(c.X, c.Y, mx.Z + 0.02), V3(0, 0, 1))
				K:plate("KMFace", w - 0.06, h - 0.1, 0.03, fz, lk(rgb(14, 14, 18), M.SmoothPlastic, { r = 0.12 }))
				K:plate("KMVFD", 1.6, 0.36, 0.04, fz * CF(-0.62, 0.08, 0), lk(rgb(6, 16, 18)))
				local _, vfd = K:text("KMVFDText", 1.5, 0.3, fz * CF(-0.62, 0.08, 0.045), "♪ READY", { fg = rgb(90, 255, 230), glow = 1.8, font = F.Arcade, d = 0.005 })
				st.vfd = vfd
				for k = 0, 5 do
					K:plate("KMLevel", 0.18, 0.06, 0.04, fz * CF(-1.32 + k * 0.22, -0.22, 0), neon(if k < 4 then NEONS.green elseif k < 5 then NEONS.yellow else NEONS.red))
				end
				for row = 0, 1 do
					for col = 0, 3 do
						K:plate("KMButton", 0.18, 0.1, 0.05, fz * CF(0.42 + col * 0.24, 0.12 - row * 0.2, 0), lk(rgb(64, 64, 70)))
					end
				end
				K:text("KMButtonLabel", 1.0, 0.07, fz * CF(0.78, 0.25, 0.04), "예약  취소  반주  템포", { fg = rgb(170, 170, 178), font = F.GothamBold, d = 0.005 })
				wdisc(K, "KMKnob", 0.3, 0.06, fz * CF(1.5, 0.0, 0.03), lk(rgb(190, 190, 196), M.Metal))
				K:text("KMBrand", 0.9, 0.08, fz * CF(-0.62, 0.32, 0.04), "GW MEDIA  G-9000", { fg = rgb(200, 200, 208), font = F.GothamBlack, d = 0.005 })
				K:plate("KMPower", 0.06, 0.06, 0.05, fz * CF(1.5, 0.3, 0), Look.ledBlue)
				hideRec(K, km)
				hideRec(K, first("MachineDisplay"))
				for _, r in all("MachineLED") do
					hideRec(K, r)
				end
			end
			-- 마이크 충전 거치대 (+ 꽂힌 마이크 2)
			local dock = first("MicDock")
			if dock then
				local mn, mx = dock.min, dock.max
				local c = (mn + mx) / 2
				K:rbox("MicCradle", V3(mx.X - mn.X + 0.04, 0.26, mx.Z - mn.Z + 0.04), 0.08, CF(c.X, mn.Y + 0.13, c.Z), lk(rgb(26, 26, 30), M.SmoothPlastic, { r = 0.05 }))
				for k, dx in { -0.22, 0.22 } do
					local base = V3(c.X + dx, mn.Y + 0.24, c.Z)
					K:vcyl("MicCradleCup", 0.2, 0.32, CF(base + V3(0, 0.08, 0)), lk(rgb(40, 40, 46)))
					handMic(K, base + V3(0, 0.05, 0), base + V3(0, 0.88, 0.02), lk(if k == 1 then rgb(30, 30, 34) else rgb(232, 232, 236), M.SmoothPlastic, { r = 0.05 }), theme, nil)
					K:plate("MicCradleLED", 0.08, 0.05, 0.03, faceCF(V3(c.X + dx, mn.Y + 0.14, mx.Z + 0.02), V3(0, 0, 1)), Look.ledGreen)
				end
				K:text("MicCradleLabel", 0.7, 0.07, faceCF(V3(c.X, mn.Y + 0.06, mx.Z + 0.025), V3(0, 0, 1)), "CH1 · 충전 · CH2", { fg = rgb(170, 170, 178), font = F.GothamBold, d = 0.005 })
				hideRec(K, dock)
			end
		end)
	end)

	-- 6) 스피커 · 우퍼 · 마이크 스탠드 · 미러볼 모터 · 레이저 브래킷 ---------------------------------------------
	step(K, "speakers", function()
		for _, r in all("FloorSpeaker") do
			columnSpeaker(K, r, theme, st.leds)
			hideRec(K, r)
		end
		for _, nm in { "Woofer", "Tweeter" } do
			for _, r in all(nm) do
				hideRec(K, r)
			end
		end
		for _, r in all("Speaker") do
			wallSpeaker(K, r)
			hideRec(K, r)
		end
		for _, r in all("SpeakerCone") do
			hideRec(K, r)
		end
		local sub = first("Subwoofer")
		if sub then
			subwoofer(K, sub, nil, st.leds)
			hideRec(K, sub)
			hideRec(K, first("SubCone"))
		end
		-- 스피커 케이블 (바닥 · 벽 몰딩) + 전원 콘센트
		K:free(function()
			local cab = first("MachineCabinet")
			for _, r in all("FloorSpeaker") do
				if cab then
					local sx = if r.c.X < 0 then -1 else 1
					local a = V3(r.c.X - sx * 0.2, 0.05, r.min.Z + 0.25)
					local b = V3((if sx < 0 then cab.min.X else cab.max.X) - sx * 0.05, 0.05, r.min.Z + 0.25)
					K:seg("SpeakerCable", a, b, 0.07, lk(rgb(10, 10, 12), M.Rubber))
				end
			end
			if cab then
				local x = cab.min.X - 0.6
				local zw = zBack + 0.01
				K:plate("CableRaceway", 0.22, 3.2, 0.1, faceCF(V3(x, cab.max.Y + 1.6 - 1.4, zw), V3(0, 0, 1)), lk(rgb(24, 24, 28)))
				Props.outlet(K, faceCF(V3(x - 0.6, 1.2, zw), V3(0, 0, 1)))
			end
		end)
		-- 마이크 스탠드
		local mb = first("MicBase")
		local mh = first("MicHead")
		if mb then
			K:free(function()
				local c = V3(mb.c.X, 0, mb.c.Z)
				local topY = 5.05
				K:disc("MicStandBase", mb.size.X, 0.1, CF(c + V3(0, 0.05, 0)), lk(rgb(26, 26, 30), M.Metal))
				K:disc("MicStandRubber", mb.size.X + 0.04, 0.03, CF(c + V3(0, 0.015, 0)), RUBBER)
				K:vcyl("MicStandTube", 3.0, 0.2, CF(c + V3(0, 1.6, 0)), lk(rgb(30, 30, 34), M.Metal))
				K:vcyl("MicStandClutch", 0.26, 0.3, CF(c + V3(0, 3.12, 0)), CHROME)
				K:vcyl("MicStandRod", topY - 3.2, 0.12, CF(c + V3(0, 3.2 + (topY - 3.2) / 2, 0)), CHROME)
				if mh then
					local tip = V3(c.X, topY, c.Z)
					local head = mh.c
					local dir = (head - tip).Unit
					K:seg("MicClip", tip, tip + dir * 0.3, 0.12, lk(rgb(30, 30, 34)))
					handMic(K, tip + dir * 0.2, head - dir * 0.1, lk(rgb(40, 40, 46), M.Metal), theme, nil)
				end
			end)
			for _, nm in { "MicBase", "MicPole", "Mic", "MicHead" } do
				hideRec(K, first(nm))
			end
		end
		local rod = first("MirrorBallRod")
		if rod then
			K:free(function()
				K:disc("MirrorBallCanopy", 0.7, 0.06, CF(rod.c.X, H - 0.03, rod.c.Z), lk(rgb(30, 30, 34), M.Metal))
				K:box("MirrorBallMotor", V3(0.4, 0.3, 0.4), CF(rod.c.X, H - 0.21, rod.c.Z), lk(rgb(24, 24, 28), M.Metal))
				K:plate("MirrorBallMotorLED", 0.06, 0.06, 0.02, faceCF(V3(rod.c.X, H - 0.21, rod.c.Z + 0.2), V3(0, 0, 1)), Look.ledRed)
			end)
		end
		local las = first("LaserProjector")
		if las then
			K:free(function()
				for _, sx in { -1, 1 } do
					K:box("LaserBracket", V3(0.05, H - las.c.Y + 0.1, 0.5), CF(las.c.X + sx * (las.size.X / 2 + 0.03), (H + las.c.Y) / 2, las.c.Z), DARKALU)
				end
				K:box("LaserBracketTop", V3(las.size.X + 0.16, 0.05, 0.5), CF(las.c.X, H - 0.025, las.c.Z), DARKALU)
			end)
		end
	end)

	-- 7) 벽 (옆벽 두 면 · 복도 쪽 벽) -----------------------------------------------------------------------
	local function sideCF(sd: number, z: number, y: number, off: number): CFrame
		local x = if sd < 0 then x0 + off else x1 - off
		return faceCF(V3(x, y, z), V3(-sd, 0, 0))
	end
	-- 옆벽 판: z 범위 a..b (a<b), 높이 y0..y1, 두께 d, 벽에서 off
	local function sidePlate(name: string, sd: number, a: number, b: number, y0: number, y1: number, d: number, off: number, look: any): BasePart
		-- dcf +X = 보는 사람 오른쪽 (왼벽: -Z, 오른벽: +Z) 이므로 폭 방향은 z
		return K:plate(name, b - a, y1 - y0, d, sideCF(sd, (a + b) / 2, (y0 + y1) / 2, off), look)
	end
	step(K, "walls", function()
		for _, r in all("AcousticPanel") do
			hideRec(K, r)
		end
		for _, r in all("AcousticTile") do
			hideRec(K, r)
		end
		-- 소파 등받이 범위 (각 옆벽)
		local backs = { [-1] = {}, [1] = {} }
		for _, g in sofaGroups(V, mine) do
			if g.back then
				local b = g.back
				if b.max.X - b.min.X < b.max.Z - b.min.Z then
					local sd = if b.c.X < 0 then -1 else 1
					table.insert(backs[sd], { a = b.min.Z, b = b.max.Z, top = b.max.Y })
				end
			end
		end
		local sign = nil
		for _, r in V.parts do
			if string.sub(r.name, 1, 5) == "Sign_" and mine(r) and r.size.Y > 2 then
				sign = r
			end
		end
		local door = first("BoothDoor")
		local zA, zB = zBack + 0.02, zFront - 0.02
		local spkZ = zBack + 1.25 -- 천장 스피커 앞면 (디퓨저는 그 앞부터)
		for _, sp in all("Speaker") do
			spkZ = math.max(spkZ, sp.max.Z + 0.1)
		end
		K:free(function()
			for _, sd in { -1, 1 } do
				-- 바탕 벽지 + 아래 걸레받이 + 위 블랙 띠
				sidePlate("BoothWallpaper", sd, zA, zB, 0.02, H - 0.02, 0.02, 0.0, wallTone)
				sidePlate("BoothKick", sd, zA, zB, 0.02, 0.4, 0.05, 0.02, GLOSS)
				sidePlate("BoothTopBand", sd, zA, zB, H - 0.95, H - 0.4, 0.05, 0.02, GLOSS)
				local band = sidePlate("BoothTopBandLED", sd, zA + 0.2, zB - 0.2, H - 0.69, H - 0.65, 0.07, 0.02, neon(theme))
				table.insert(st.leds, { p = band, c = theme })
				-- 소파 위 선반 (음료 받침) + 업라이트
				for _, bk in backs[sd] do
					local ly = bk.top + 0.02
					local shelf = K:box("WallLedge", V3(0.6, 0.12, bk.b - bk.a), CF(if sd < 0 then x0 + 0.3 else x1 - 0.3, ly + 0.06, (bk.a + bk.b) / 2), Look.walnut)
					local _ = shelf
					K:box("WallLedgeEdge", V3(0.03, 0.12, bk.b - bk.a), CF(if sd < 0 then x0 + 0.615 else x1 - 0.615, ly + 0.06, (bk.a + bk.b) / 2), CHROME)
					local led = K:box("WallLedgeLED", V3(0.05, 0.04, bk.b - bk.a - 0.3), CF(if sd < 0 then x0 + 0.08 else x1 - 0.08, ly + 0.14, (bk.a + bk.b) / 2), neon(theme))
					table.insert(st.leds, { p = led, c = theme })
					addLight(K, st, led, "SurfaceLight", { Face = Enum.NormalId.Top, Range = 7, Brightness = 0.5, Angle = 120, Color = theme })
				end
				-- 디퓨저 (TV 쪽: 천장 스피커 앞 ~ 소파 앞)
				local da = spkZ
				local db = -4.75
				for _, bk in backs[sd] do
					db = math.min(db, bk.a - 0.1)
				end
				if db - da > 1.6 then
					local y0, y1 = 4.5, H - 1.2
					local n = math.floor((db - da - 0.16) / 0.42)
					local seq = { 0, 1, 4, 2, 2, 4, 1 }
					local cw = (db - da - 0.16) / n
					for i = 1, n do
						local z = da + 0.08 + cw * (i - 0.5)
						local dep = 0.08 + seq[(i - 1) % #seq + 1] * 0.07
						sidePlate("DiffuserWell", sd, z - cw / 2 + 0.02, z + cw / 2 - 0.02, y0 + 0.08, y1 - 0.08, dep, 0.02, if i % 2 == 0 then Look.walnut else Look.oak)
						if i < n then
							sidePlate("DiffuserFin", sd, z + cw / 2 - 0.02, z + cw / 2 + 0.02, y0 + 0.08, y1 - 0.08, 0.42, 0.02, lk(rgb(30, 22, 18), M.Wood))
						end
					end
					sidePlate("DiffuserFrame", sd, da, db, y1 - 0.08, y1, 0.46, 0.02, LACQ)
					sidePlate("DiffuserFrame", sd, da, db, y0, y0 + 0.08, 0.46, 0.02, LACQ)
					sidePlate("DiffuserFrame", sd, da, da + 0.08, y0, y1, 0.46, 0.02, LACQ)
					sidePlate("DiffuserFrame", sd, db - 0.08, db, y0, y1, 0.46, 0.02, LACQ)
				end
				-- 소파 위 채널 패딩 벽 (간판 자리는 비움)
				for _, bk in backs[sd] do
					local segs = { { bk.a + 0.1, bk.b - 0.1 } }
					if sign and ((sign.c.X < 0) == (sd < 0)) then
						local cut = { sign.min.Z - 0.25, sign.max.Z + 0.25 }
						local nxt = {}
						for _, s in segs do
							if cut[2] <= s[1] or cut[1] >= s[2] then
								table.insert(nxt, s)
							else
								if cut[1] - s[1] > 1.0 then
									table.insert(nxt, { s[1], cut[1] })
								end
								if s[2] - cut[2] > 1.0 then
									table.insert(nxt, { cut[2], s[2] })
								end
							end
						end
						segs = nxt
						-- 간판 테두리 LED
						local fr = sidePlate("SignFrameLED", sd, sign.min.Z - 0.12, sign.max.Z + 0.12, sign.min.Y - 0.12, sign.max.Y + 0.12, 0.03, 0.0, neon(theme))
						table.insert(st.leds, { p = fr, c = theme })
					end
					local y0 = bk.top + 0.45
					local y1 = H - 1.25
					for _, s in segs do
						local len = s[2] - s[1]
						local pitch = 0.58
						local n = math.max(2, math.floor(len / pitch))
						local pw = len / n
						sidePlate("ChannelBack", sd, s[1], s[2], y0, y1, 0.04, 0.02, lk(dk(fabric, 0.45), M.Fabric))
						for i = 1, n do
							local z = s[1] + pw * (i - 0.5)
							local x = if sd < 0 then x0 + 0.06 else x1 - 0.06
							K:vcyl("ChannelTuft", y1 - y0 - 0.16, pw * 0.98, CF(x, (y0 + y1) / 2, z), panelTone)
						end
						sidePlate("ChannelFrame", sd, s[1] - 0.06, s[2] + 0.06, y1, y1 + 0.08, 0.36, 0.02, CHROME)
						sidePlate("ChannelFrame", sd, s[1] - 0.06, s[2] + 0.06, y0 - 0.08, y0, 0.36, 0.02, CHROME)
					end
				end
			end
			-- 문 쪽 (오른벽 문 받침 구간): 문 멈춤 + 세로 LED
			if door then
				local sd = if door.c.X < 0 then -1 else 1
				local bump = sidePlate("DoorStopPad", sd, door.min.Z + 0.6, door.min.Z + 0.9, 3.6, 4.0, 0.12, 0.0, RUBBER)
				local _ = bump
			end
		end)
	end)

	-- 8) 복도 쪽 벽 (안쪽 면): 문틀 · 조명 패널 · 코인기 · 에어컨 리모컨 · 터치 선곡 패널 · 에어컨 · 안내문 · 비상구 --------------
	step(K, "frontwall", function()
		local fz = zFront
		local n = V3(0, 0, -1)
		local function fcf(x: number, y: number, off: number): CFrame
			return faceCF(V3(x, y, fz - off), n)
		end
		-- 문 구멍: CorridorWall 들 사이 (로컬 x)
		local walls = {}
		for _, r in V.byName.CorridorWall or {} do
			if math.abs(r.c.Z - (V.z1 + 0.15)) < 0.8 then
				table.insert(walls, r)
			end
		end
		local dx0, dx1 = 0.5, 5.5
		local lin = nil
		for _, r in V.byName.CorridorWallLintel or {} do
			if math.abs(r.c.Z - (V.z1 + 0.15)) < 0.8 then
				lin = r
			end
		end
		if lin then
			dx0, dx1 = lin.min.X, lin.max.X
		end
		local doorTop = if lin then lin.min.Y else 8.55
		local ledgeTop = 4.2
		for _, g in sofaGroups(V, mine) do
			if g.back and g.back.max.X - g.back.min.X > g.back.max.Z - g.back.min.Z then
				ledgeTop = g.back.max.Y + 0.05
			end
		end
		K:free(function()
			-- 벽지 (소파 위) + 위 블랙 띠
			K:plate("FrontWallpaper", dx0 - x0 - 0.04, H - ledgeTop - 0.04, 0.02, fcf((x0 + dx0) / 2, (ledgeTop + H) / 2, 0), wallTone)
			K:plate("FrontLintelPaper", dx1 - dx0, H - doorTop - 0.04, 0.02, fcf((dx0 + dx1) / 2, (doorTop + H) / 2, 0), wallTone)
			K:plate("FrontTopBand", x1 - x0 - 0.06, 0.55, 0.05, fcf((x0 + x1) / 2, H - 0.675, 0.02), GLOSS)
			local band = K:plate("FrontTopBandLED", x1 - x0 - 0.4, 0.04, 0.07, fcf((x0 + x1) / 2, H - 0.67, 0.02), neon(theme))
			table.insert(st.leds, { p = band, c = theme })
			-- 소파 위 선반
			for _, g in sofaGroups(V, mine) do
				local b = g.back
				if b and b.max.X - b.min.X > b.max.Z - b.min.Z then
					K:box("WallLedge", V3(b.max.X - b.min.X, 0.12, 0.6), CF(b.c.X, b.max.Y + 0.08, fz - 0.3), Look.walnut)
					K:box("WallLedgeEdge", V3(b.max.X - b.min.X, 0.12, 0.03), CF(b.c.X, b.max.Y + 0.08, fz - 0.615), CHROME)
					local led = K:box("WallLedgeLED", V3(b.max.X - b.min.X - 0.3, 0.04, 0.05), CF(b.c.X, b.max.Y + 0.16, fz - 0.08), neon(theme))
					table.insert(st.leds, { p = led, c = theme })
				end
			end
			-- 문틀 (안쪽 면 케이싱)
			local casing = lk(rgb(30, 30, 34), M.Metal)
			K:plate("DoorCasing", 0.24, doorTop + 0.2, 0.1, fcf(dx1 + 0.1, (doorTop + 0.2) / 2, 0.0), casing)
			K:plate("DoorCasing", 0.24, doorTop + 0.2, 0.1, fcf(dx0 - 0.1, (doorTop + 0.2) / 2, 0.0), casing)
			K:plate("DoorCasing", dx1 - dx0 + 0.44, 0.22, 0.1, fcf((dx0 + dx1) / 2, doorTop + 0.09, 0.0), casing)
			K:plate("DoorCasingLine", 0.03, doorTop, 0.11, fcf(dx1 - 0.0, doorTop / 2, 0.0), CHROME)
			K:plate("DoorCasingLine", 0.03, doorTop, 0.11, fcf(dx0 + 0.0, doorTop / 2, 0.0), CHROME)
			-- 유도등 (비상구) + 비상조명등
			local exitY = doorTop + 0.75
			K:plate("ExitSignBox", 1.3, 0.55, 0.16, fcf((dx0 + dx1) / 2, exitY, 0.0), lk(rgb(240, 244, 240)))
			K:text("ExitSign", 1.2, 0.45, fcf((dx0 + dx1) / 2, exitY, 0.165), "🏃 비상구", { fg = WHITE, bg = rgb(20, 170, 80), glow = 1.6, font = F.GothamBlack, d = 0.01 })
			K:plate("EmergencyLight", 1.1, 0.36, 0.22, fcf((dx0 + dx1) / 2 + 1.6, H - 0.2 - 0.18 - 0.6, 0.0), lk(rgb(240, 240, 236)))
			for _, sx in { -1, 1 } do
				wdisc(K, "EmergencyLamp", 0.24, 0.12, fcf((dx0 + dx1) / 2 + 1.6 + sx * 0.32, H - 0.98, 0.22), lk(rgb(255, 250, 230), M.Glass, { t = 0.2 }))
			end
			K:plate("EmergencyLightLED", 0.06, 0.06, 0.24, fcf((dx0 + dx1) / 2 + 1.6, H - 0.88, 0.0), Look.ledGreen)
		end)

		-- 조명 패널 (문 바로 왼쪽): 4 버튼
		local px = dx0 - 0.55
		local panel: BasePart? = nil
		K:free(function()
			panel = K:plate("LightPanel", 0.6, 1.0, 0.06, fcf(px, 5.0, 0.0), lk(rgb(20, 20, 24), M.SmoothPlastic, { r = 0.1 }))
			K:text("LightPanelTitle", 0.5, 0.12, fcf(px, 5.4, 0.065), "조명", { fg = rgb(220, 220, 230), font = F.GothamBold, d = 0.005 })
			local cols = { theme, WARM, NEONS.pink, rgb(120, 120, 130) }
			for i = 1, 4 do
				local b = K:plate("LightPanelKey", 0.42, 0.14, 0.05, fcf(px, 5.2 - i * 0.19, 0.06), lk(cols[i]))
				table.insert(st.buttons, b)
				K:text("LightPanelKeyText", 0.4, 0.11, fcf(px, 5.2 - i * 0.19, 0.115), MODES[i], { fg = WHITE, font = F.GothamBold, d = 0.004 })
			end
		end)
		-- 코인기 (동전 · 지폐 투입 + 남은 시간): 밖의 KaraokePanel 바로 뒤
		local cx = px - 1.4
		local coinLabel: TextLabel? = nil
		K:free(function()
			local d0 = fcf(cx, 5.55, 0.0)
			K:rbox("CoinBox", V3(0.5, 2.0, 1.2), 0.08, d0 * CF(0, 0, 0.25) * ANG(0, PI / 2, 0), lk(rgb(70, 74, 82), M.Metal))
			local fc = d0 * CF(0, 0, 0.5)
			K:plate("CoinBoxHeader", 1.1, 0.26, 0.02, fc * CF(0, 0.82, 0), lk(dk(theme, 0.2)))
			K:text("CoinBoxHeaderText", 1.0, 0.2, fc * CF(0, 0.82, 0.025), "COIN · BILL", { fg = WHITE, font = F.GothamBlack, d = 0.004 })
			K:plate("CoinBoxLCD", 0.9, 0.46, 0.02, fc * CF(0, 0.38, 0), lk(rgb(10, 4, 4)))
			local _, lab = K:text("CoinBoxLCDText", 0.84, 0.4, fc * CF(0, 0.38, 0.025), "500원 · 30분\n동전 · 지폐", { fg = rgb(255, 70, 50), glow = 1.6, font = F.Arcade, d = 0.004 })
			coinLabel = lab
			K:plate("CoinSlot", 0.24, 0.3, 0.03, fc * CF(-0.28, -0.06, 0), CHROME)
			K:plate("CoinSlotHole", 0.04, 0.2, 0.035, fc * CF(-0.28, -0.06, 0), lk(rgb(4, 4, 4)))
			K:plate("BillSlotBezel", 0.62, 0.14, 0.03, fc * CF(0.12, -0.32, 0), lk(rgb(30, 30, 34)))
			local bill = K:plate("BillSlotLED", 0.52, 0.04, 0.035, fc * CF(0.12, -0.32, 0), Look.ledGreen)
			st.billLED = bill
			wdisc(K, "CoinReturnBtn", 0.18, 0.05, fc * CF(0.3, -0.06, 0), lk(rgb(220, 40, 40)))
			K:plate("CoinCup", 0.6, 0.22, 0.12, fc * CF(0, -0.78, 0), lk(rgb(40, 40, 44), M.Metal))
			K:text("CoinBoxSticker", 1.0, 0.12, fc * CF(0, -0.56, 0.01), "500원 동전 · 1,000원 지폐", { fg = rgb(230, 230, 236), font = F.GothamBold, d = 0.004 })
		end)
		st.coinLabel = coinLabel
		-- 에어컨 리모컨 (상호작용) · 터치 선곡 패널
		local ax = cx - 1.45
		local acCtl: BasePart? = nil
		local acLabel: TextLabel? = nil
		K:free(function()
			acCtl = K:plate("ACControl", 0.62, 0.62, 0.07, fcf(ax, 5.0, 0.0), lk(rgb(240, 240, 236)))
			K:plate("ACControlLCD", 0.46, 0.26, 0.02, fcf(ax, 5.1, 0.07), lk(rgb(150, 200, 210)))
			local _, l = K:text("ACControlText", 0.44, 0.22, fcf(ax, 5.1, 0.095), "OFF", { fg = rgb(20, 30, 40), font = F.GothamBold, d = 0.004 })
			acLabel = l
			wdisc(K, "ACControlBtn", 0.14, 0.04, fcf(ax, 4.82, 0.07), lk(rgb(60, 140, 230)))
			-- 터치 선곡 패널 (태블릿 + 벽 거치대)
			local tx = ax - 1.55
			K:plate("TabletMount", 0.5, 0.5, 0.12, fcf(tx, 5.4, 0.0), DARKALU)
			K:plate("TabletBody", 1.7, 1.1, 0.08, fcf(tx, 5.4, 0.12), lk(rgb(16, 16, 20), M.SmoothPlastic, { r = 0.1 }))
			K:plate("TabletScreen", 1.56, 0.96, 0.02, fcf(tx, 5.4, 0.2), lk(rgb(20, 26, 50), M.Neon, { t = 0.55 }))
			K:text("TabletHeader", 1.5, 0.16, fcf(tx, 5.78, 0.225), "🔍 곡 검색 · 예약", { fg = WHITE, bg = dk(theme, 0.25), glow = 1.2, font = F.GothamBold, d = 0.004 })
			local list = {}
			for i = 1, 4 do
				local k = ((roomNo + i * 3) % #SONGS) + 1
				table.insert(list, string.format("%d  %s", songNo(k), SONGS[k]))
			end
			K:text("TabletList", 1.48, 0.66, fcf(tx, 5.32, 0.225), table.concat(list, "\n"), { fg = rgb(220, 230, 255), glow = 1.2, font = F.GothamMedium, align = "Left", d = 0.004 })
			-- 안내문 + 가방 고리
			local nx = (x0 + ax) / 2 + 0.2
			K:plate("NoticeFrame", 2.5, 1.36, 0.04, fcf(nx, 7.35, 0.0), CHROME)
			K:text("Notice", 2.4, 1.26, fcf(nx, 7.35, 0.045), "이용 안내\n· 30분 500원 · 사용 중 자동 연장\n· 음식물 OK · 주류 · 흡연 금지\n· 기물 파손 시 변상\n· 퇴실 시 마이크는 충전 거치대에", { fg = rgb(30, 30, 36), bg = rgb(250, 248, 242), font = F.GothamMedium, d = 0.01, align = "Left" })
			for k = 0, 1 do
				local hx = x0 + 0.5 + k * 0.55
				K:plate("BagHookPlate", 0.16, 0.3, 0.04, fcf(hx, 7.0, 0.0), CHROME)
				K:seg("BagHook", (fcf(hx, 7.05, 0.04)).Position, (fcf(hx, 6.85, 0.32)).Position, 0.07, CHROME)
				K:ball("BagHookTip", 0.1, fcf(hx, 6.92, 0.34), CHROME)
			end
		end)
		-- 벽걸이 에어컨 (루버가 열림)
		local acx = (x0 + ax) / 2
		local louver: BasePart? = nil
		local louverCF: CFrame? = nil
		local acLED: BasePart? = nil
		K:free(function()
			local yb = H - 2.3
			local d0 = fcf(acx, yb + 0.55, 0.0)
			K:rbox("ACUnit", V3(0.72, 1.1, 3.2), 0.18, d0 * CF(0, 0, 0.36) * ANG(0, PI / 2, 0), lk(rgb(242, 242, 238)))
			K:plate("ACFrontLine", 3.0, 0.03, 0.73, d0 * CF(0, 0.18, 0), lk(rgb(210, 210, 206)))
			K:text("ACBrand", 0.8, 0.12, d0 * CF(-1.0, 0.32, 0.73), "INVERTER", { fg = rgb(150, 150, 156), font = F.GothamBold, d = 0.004 })
			acLED = K:plate("ACLED", 0.1, 0.06, 0.73, d0 * CF(1.2, 0.32, 0), lk(rgb(120, 120, 120)))
			K:plate("ACIntake", 2.8, 0.12, 0.72, d0 * CF(0, -0.42, 0.0), lk(rgb(60, 60, 64)))
			local lcf = d0 * CF(0, -0.53, 0.66)
			louverCF = lcf
			louver = K:box("ACLouver", V3(2.9, 0.06, 0.24), lcf, lk(rgb(236, 236, 232)))
			-- 배관 커버 (벽 따라 위로)
			K:plate("ACPipeCover", 0.3, H - yb - 1.1, 0.16, fcf(acx + 1.75, (yb + 1.1 + H) / 2, 0.0), lk(rgb(236, 236, 232)))
		end)
		-- 상호작용: 조명 모드 · 에어컨
		if panel then
			Interact.prompt(K, panel :: BasePart, {
				action = "조명: " .. MODES[2],
				object = "방 조명 모드",
				fn = function(_n, pr)
					st.mode = st.mode % #MODES + 1
					applyMode(st, os.clock())
					pr.ActionText = "조명: " .. MODES[st.mode % #MODES + 1]
				end,
			})
		end
		if acCtl then
			local on = false
			Interact.toggle(K, acCtl :: BasePart, {
				object = "벽걸이 에어컨",
				state = false,
				onText = "에어컨 끄기",
				offText = "에어컨 켜기",
				on = function(s: boolean)
					on = s
					if acLabel then
						acLabel.Text = if s then "냉방 22°C" else "OFF"
					end
					if acLED and acLED.Parent then
						acLED.Material = if s then M.Neon else M.SmoothPlastic
						acLED.Color = if s then rgb(60, 230, 120) else rgb(120, 120, 120)
					end
					if louver and louver.Parent and louverCF then
						local w = K.cf * (louverCF :: CFrame) * (if s then CF(0, -0.05, 0.05) * ANG(math.rad(-40), 0, 0) else CF())
						TweenService:Create(louver :: BasePart, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = w }):Play()
					end
				end,
			})
			local _ = on
		end
	end)

	-- 9) 문 (유리문: 같은 자리 열린 자세, 문 닫기/열기) -----------------------------------------------------------
	step(K, "door", function()
		local dr = first("BoothDoor")
		if not dr then
			return
		end
		local hingeZ = math.max(dr.max.Z, zFront - 0.12)
		local L = hingeZ - dr.min.Z
		local x = dr.c.X - 0.03
		local hcf = CF(x, 0, hingeZ) -- 문 프레임: 원점 = 경첩 아래, 문은 -Z 로 뻗음, 두께 = X
		local hgt = dr.max.Y
		local alu = lk(rgb(56, 58, 64), M.Metal)
		local m = K:group("BoothDoorLeaf", function()
			K:free(function()
				K:box("DoorStile", V3(0.16, hgt, 0.2), hcf * CF(0, hgt / 2, -0.1), alu)
				K:box("DoorStile", V3(0.16, hgt, 0.2), hcf * CF(0, hgt / 2, -L + 0.1), alu)
				K:box("DoorRail", V3(0.16, 0.3, L), hcf * CF(0, hgt - 0.15, -L / 2), alu)
				K:box("DoorRail", V3(0.16, 0.5, L), hcf * CF(0, 0.25, -L / 2), alu)
				K:box("DoorKickPlate", V3(0.18, 0.4, L - 0.4), hcf * CF(0, 0.26, -L / 2), Look.brushed)
				K:box("DoorGlass", V3(0.05, hgt - 0.8, L - 0.4), hcf * CF(0, 0.5 + (hgt - 0.8) / 2, -L / 2), lk(lt(dk(theme, 0.55), 0.1), M.Glass, { t = 0.55, r = 0.15 }))
				K:box("DoorFrost", V3(0.07, 1.0, L - 0.4), hcf * CF(0, 4.0, -L / 2), lk(rgb(236, 236, 240), M.Glass, { t = 0.25 }))
				for _, sx in { -1, 1 } do
					K:text("DoorFrostText", L - 0.8, 0.7, faceCF((hcf * V3(sx * 0.04, 4.0, -L / 2)), V3(sx, 0, 0)), string.format("%02d   ♪ COIN KARAOKE", roomNo), { fg = dk(theme, 0.35), font = F.GothamBlack, d = 0.004 })
					-- 레버 손잡이 (양면)
					K:disc("DoorLeverRose", 0.22, 0.05, hcf * CF(sx * 0.1, 3.8, -L + 0.35) * ANG(0, 0, PI / 2) * ANG(0, 0, 0), CHROME)
					K:box("DoorLever", V3(0.07, 0.07, 0.5), hcf * CF(sx * 0.16, 3.8, -L + 0.55), CHROME)
				end
				for k = 0, 2 do
					K:vcyl("DoorHinge", 0.4, 0.1, hcf * CF(-0.09, 0.8 + k * 3.2, -0.02), CHROME)
				end
				K:box("DoorSeal", V3(0.1, hgt - 0.1, 0.04), hcf * CF(0, hgt / 2, -L - 0.01), RUBBER)
				K:box("DoorCloser", V3(0.16, 0.24, 1.0), hcf * CF(-0.16, hgt - 0.32, -0.75), lk(rgb(150, 152, 158), M.Metal))
				K:box("DoorCloserArm", V3(0.05, 0.05, 0.9), hcf * CF(-0.2, hgt - 0.12, -0.6), lk(rgb(130, 132, 138), M.Metal))
				-- 가로 밀대 (프롬프트 자리: 테이블에서 6.5 이상)
				K:box("DoorPushHandle", V3(0.08, 0.08, L * 0.6), hcf * CF(-0.18, 3.1, -L / 2 + 0.2), CHROME)
				for _, f in { -0.25, 0.25 } do
					K:box("DoorPushPost", V3(0.12, 0.06, 0.06), hcf * CF(-0.12, 3.1, -L / 2 + 0.2 + f * L * 0.6 / 0.5 * 0.5), CHROME)
				end
			end)
		end)
		for _, nm in { "BoothDoor", "DoorEdge", "DoorHandle" } do
			for _, r in all(nm) do
				hideRec(K, r)
			end
		end
		local hingeW = (K.cf * hcf).Position
		Interact.swing(K, m, hingeW, K.cf.YVector, PI / 2 - 0.04, { object = "노래방 문", openText = "문 닫기", closeText = "문 열기", sound = "rbxasset://sounds/clickfast.wav" })
	end)

	-- 10) 천장: 별빛 · 핀스폿 · 파 조명 · 환기구 · 비상 (스프링클러 · 감지기는 Common) ----------------------------------
	step(K, "ceiling", function()
		K:free(function()
			-- 별빛 (광섬유 점)
			local nStars = if hi(K) then 46 elseif lo(K) then 0 else 24
			local seed = roomNo * 17 + 3
			local placed = 0
			for i = 1, nStars * 3 do
				if placed >= nStars then
					break
				end
				local x = x0 + 0.9 + rnd(seed, i) * (x1 - x0 - 1.8)
				local z = zBack + 1.6 + rnd(seed + 7, i) * (zFront - zBack - 2.6)
				if Common.ceilFree(K, x, z, 0.3) then
					local s = 0.05 + rnd(seed + 11, i) * 0.05
					local p = K:disc("StarDot", s, 0.02, CF(x, H - 0.01, z), neon(if i % 5 == 0 then rgb(180, 210, 255) else rgb(255, 250, 236)))
					table.insert(st.stars, p)
					placed += 1
				end
			end
			-- 핀스폿 (미러볼 비춤)
			local ball = first("MirrorBall")
			if ball then
				local pos = V3(ball.c.X + 2.2, H - 0.25, ball.c.Z + 2.6)
				local dir = (ball.c - pos).Unit
				K:disc("PinspotMount", 0.4, 0.05, CF(pos.X, H - 0.025, pos.Z), DARKALU)
				local can = K:cyl("PinspotCan", 0.55, 0.32, CFrame.lookAt(pos, pos + dir) * ANG(0, PI / 2, 0), lk(rgb(24, 24, 28), M.Metal))
				K:disc("PinspotLens", 0.24, 0.02, CFrame.lookAt(pos + dir * 0.28, pos + dir) * ANG(PI / 2, 0, 0), Look.lampNeutral)
				addLight(K, st, can, "SpotLight", { Face = Enum.NormalId.Right, Range = 9, Brightness = 2.2, Angle = 16, Color = rgb(255, 250, 240) })
			end
			-- 파 조명 2 (TV 쪽 천장 모서리, 소파를 향함)
			for k, sx in { -1, 1 } do
				local pos = V3(sx * (x1 - 1.6), H - 0.45, zBack + 2.2)
				local aim = V3(sx * -1.2, 1.2, 1.5)
				local dir = (aim - pos).Unit
				K:box("ParYoke", V3(0.6, 0.06, 0.12), CF(pos.X, H - 0.03, pos.Z), DARKALU)
				K:bar("ParYokeArm", V3(pos.X - 0.28, H - 0.05, pos.Z), V3(pos.X - 0.28, pos.Y, pos.Z), 0.05, 0.05, DARKALU)
				K:bar("ParYokeArm", V3(pos.X + 0.28, H - 0.05, pos.Z), V3(pos.X + 0.28, pos.Y, pos.Z), 0.05, 0.05, DARKALU)
				local can = K:cyl("ParCan", 0.6, 0.44, CFrame.lookAt(pos, pos + dir) * ANG(0, PI / 2, 0), lk(rgb(20, 20, 24), M.Metal))
				local lens = K:disc("ParLensLED", 0.36, 0.02, CFrame.lookAt(pos + dir * 0.31, pos + dir) * ANG(PI / 2, 0, 0), neon(if k == 1 then theme else NEONS.pink))
				table.insert(st.leds, { p = lens, c = if k == 1 then theme else NEONS.pink })
				if k == 1 then
					addLight(K, st, can, "SpotLight", { Face = Enum.NormalId.Right, Range = 14, Brightness = 1.4, Angle = 40, Color = theme }, true)
				end
			end
			-- 환기구 (정사각 디퓨저)
			local vx, vz = x0 + 2.4, zFront - 3.2
			if Common.ceilFree(K, vx, vz, 0.8) then
				K:box("CeilingVent", V3(1.3, 0.04, 1.3), CF(vx, H - 0.02, vz), lk(rgb(220, 220, 216)))
				for k = 1, 3 do
					local s = 1.3 - k * 0.3
					K:box("CeilingVentRing", V3(s, 0.05, s), CF(vx, H - 0.03, vz), lk(if k % 2 == 1 then rgb(150, 150, 150) else rgb(220, 220, 216)))
				end
				Common.useCeil(K, vx, vz)
			end
		end)
	end)

	-- 11) 바닥: 카펫 무늬 테두리 + 입구 매트 -------------------------------------------------------------------
	step(K, "floor", function()
		local tt = first("TableTop")
		K:free(function()
			if tt then
				local cx, cz = (tt.min.X + tt.max.X) / 2, (tt.min.Z + tt.max.Z) / 2
				local hw, hl = (tt.max.X - tt.min.X) / 2 + 0.45, (tt.max.Z - tt.min.Z) / 2 + 0.55
				local lineL = lk(dk(theme, 0.45), M.Fabric)
				for _, sx in { -1, 1 } do
					K:box("CarpetLine", V3(0.12, 0.02, hl * 2), CF(cx + sx * hw, 0.03, cz), lineL)
					K:box("CarpetLine", V3(hw * 2 + 0.12, 0.02, 0.12), CF(cx, 0.03, cz + sx * hl), lineL)
				end
			end
			-- TV 앞 줄무늬 (무대 자리)
			local cab = first("MachineCabinet")
			if cab then
				for k = 0, 2 do
					K:box("CarpetStage", V3(cab.max.X - cab.min.X + 1.4, 0.02, 0.1), CF((cab.min.X + cab.max.X) / 2, 0.03, cab.max.Z + 0.45 + k * 0.4), lk(dk(theme, 0.35 + k * 0.1), M.Fabric))
				end
			end
			-- 입구 매트
			K:box("DoorMatBooth", V3(3.4, 0.03, 1.4), CF(3.0, 0.025, zFront - 1.0), lk(rgb(30, 30, 34), M.Fabric))
			K:text("DoorMatBoothText", 2.6, 0.9, topCF(V3(3.0, 0.042, zFront - 1.0), V3(0, 0, -1)), "♪ WELCOME", { fg = dk(theme, 0.2), font = F.GothamBlack, d = 0.004, free = true })
		end)
	end)

	-- 12) 피난안내도 · 거울 (왼벽 복도 쪽) ---------------------------------------------------------------------
	step(K, "evac", function()
		local sd = -1
		local zc = zFront - 1.8
		K:free(function()
			local m0 = sideCF(sd, zc, 6.0, 0.02)
			K:plate("MirrorFrame", 2.5, 2.3, 0.05, m0, CHROME)
			K:plate("Mirror", 2.38, 2.18, 0.06, m0, Look.mirror)
			local e0 = sideCF(sd, zc, 8.3, 0.02)
			K:plate("EvacMapFrame", 2.0, 1.4, 0.05, e0, Look.goldMetal)
			K:text("EvacMap", 1.88, 1.28, e0 * CF(0, 0, 0.055), "피난안내도\n[현위치] ROOM " .. string.format("%02d", roomNo) .. "\n→ 복도 → 비상구 / 로비 출입구\n소화기 · 유도등 위치 표시", { fg = rgb(20, 120, 60), bg = rgb(250, 250, 246), font = F.GothamBold, d = 0.01 })
		end)
	end)

	-- 13) 실시간 표시 + 조명 모드 애니메이션 ------------------------------------------------------------------
	applyMode(st, 0)
	local lastTxt = ""
	local lastVfd = ""
	Interact.anim(K, function(t: number)
		if st.mode == 3 then
			applyMode(st, t)
		end
		local busy = rented(booth)
		if st.coinLabel and st.coinLabel.Parent then
			local txt
			if busy then
				local pu = attr(booth, "KPaidUntil")
				local left = if type(pu) == "number" then math.max(0, pu - serverNow()) else 0
				-- 30초 = 게임 30분
				txt = string.format("남은 시간\n%d분", math.floor(left + 0.5))
			else
				txt = "500원 · 30분\n동전 · 지폐"
			end
			if txt ~= lastTxt then
				st.coinLabel.Text = txt
				lastTxt = txt
			end
		end
		if st.billLED and st.billLED.Parent then
			st.billLED.Transparency = if (not busy) and (math.floor(t * 2) % 2 == 0) then 0.6 else 0
		end
		if st.vfd and st.vfd.Parent then
			local id = attr(booth, "KSong")
			local v = "♪ READY"
			if type(id) == "string" and id ~= "" then
				local i = tonumber(string.match(id, "%d+"))
				if i then
					v = string.format("%d", songNo(i))
				end
			elseif busy then
				v = "선곡 대기"
			end
			if v ~= lastVfd then
				st.vfd.Text = v
				lastVfd = v
			end
		end
	end)
end

-- =====================================================================================================
-- 스타일 · 진입
-- =====================================================================================================
local function fixKeeps(V: any)
	if V.type == "kbooth" then
		-- 부스: 복도 쪽 벽을 '앞 유리'로 본 keep, 가운데로 추측한 문 keep 을 실제 문 자리로 바꿈
		local keep = {}
		for _, k in V.keep do
			if k.kind ~= "window" and k.kind ~= "door" then
				table.insert(keep, k)
			end
		end
		V.keep = keep
		local lin = nil
		for _, r in V.byName.CorridorWallLintel or {} do
			if math.abs(r.c.Z - (V.z1 + 0.15)) < 0.8 then
				lin = r
			end
		end
		local a, b = 0.5, 5.5
		if lin then
			a, b = lin.min.X, lin.max.X
		end
		V:addKeep(V3(a - 0.1, 0.1, V.z1 - 4.9), V3(b + 0.1, 8.6, V.z1 + 0.6), "door")
		V.door = { x = (a + b) / 2, z = V.z1, w = b - a, min = V3(a, 0, V.z1 - 0.2), max = V3(b, 8.6, V.z1 + 0.2) }
	elseif V.type == "kcorridor" then
		local keep = {}
		for _, k in V.keep do
			if k.kind ~= "window" then
				table.insert(keep, k)
			end
		end
		V.keep = keep
		-- 복도 바닥 전체 = 통로 (벽에서 0.9 안쪽)
		V:addKeep(V3(V.x0 + 0.9, 0.1, V.z0), V3(V.x1 - 0.9, 7.2, V.z1), "lane")
	elseif V.type == "karaoke" then
		-- 로비 동선 (입구 -> 복도 아치 · 카운터 · 교환기 · 자판기)
		local function lane(ax: number, az: number, bx: number, bz: number, w: number)
			local a, b = V3(ax, 0, az), V3(bx, 0, bz)
			local n = math.max(1, math.ceil((b - a).Magnitude / 1.5))
			for i = 0, n do
				local p = a:Lerp(b, i / n)
				V:addKeep(V3(p.X - w / 2, 0.1, p.Z - w / 2), V3(p.X + w / 2, 6.5, p.Z + w / 2), "lane")
			end
		end
		local d = V.door or { x = 11.7, z = V.z1 }
		lane(d.x, V.z1 - 3.5, 0, V.z0 + 1.6, 3.6)
		lane(d.x, V.z1 - 3.5, -12, -0.6, 3.0)
		lane(d.x, V.z1 - 3.5, V.x1 - 4.0, 7.8, 3.0)
		lane(V.x1 - 4.0, 7.8, V.x1 - 4.0, -6.8, 3.0)
		lane(0, V.z0 + 1.6, -8, -0.8, 3.0)
	end
end

function T.style(V: any): any
	local ok, err = pcall(fixKeeps, V)
	if not ok then
		warn("[T_karaoke] keep fix: " .. tostring(err))
	end
	local cy = ceilingY(V)
	if V.type == "kbooth" or V.type == "kcorridor" then
		cy = math.max(cy, V.H + 0.05)
	end
	local S: any = {
		chair = false, stool = false, table = false, counter = false, base = false, lower = false, mat = false,
		clock = false, license = false, cctv = false, ceiling = {}, lights = { kind = "none" },
		skip = { upgrades = V.type ~= "karaoke", fixtures = true, floor = true, walls = true },
		ceilY = cy,
	}
	-- 스프링클러 · 감지기가 실제 천장에 붙게
	V.H = cy
	return S
end

function T.build(K: any, V: any, S: any)
	if V.type == "kbooth" then
		boothBuild(K, V, S)
	elseif V.type == "kcorridor" then
		if T.corridor then
			T.corridor(K, V, S)
		end
	else
		if T.lobby then
			T.lobby(K, V, S)
		end
	end
end

return T

end

__defs["T_korean"] = function()
-- GwangalliBuildingInterior/T_korean: 유형 (soup noodle katsu chinese) 실내.
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (Common.luau 머리말의 S 필드)
--   build(K, V, S) 유형별 디테일 (메뉴판 · 진열 · 주방 · 간판 · 소품 · 상호작용)

local Look = __require("Look")
local Props = __require("Props")
local Interact = __require("Interact")
local Common = __require("Common")

local T = {}
T.types = { "soup", "noodle", "katsu", "chinese" }

function T.style(V: any): any
	return {
		chair = { style = "padded", frame = Look.blackMetal, seat = Look.fabricGrey },
		table = { top = Look.oak, base = Look.blackMetal },
		counter = { front = "panel", frontL = Look.white, topL = Look.marbleWhite },
		lights = { kind = "downlight" },
	}
end

function T.build(K: any, V: any, S: any) end

return T

end

__defs["T_pc"] = function()
-- GwangalliBuildingInterior/T_pc: 큰 시설 방 유형 (pcbang pchall pcback) 실내 (Venues.luau 의 방, Scan.fitRoom).
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (Common.luau 머리말의 S 필드)
--   build(K, V, S) 유형별 디테일

local Look = __require("Look")
local Props = __require("Props")
local Interact = __require("Interact")
local Common = __require("Common")

local T = {}
T.types = { "pcbang", "pchall", "pcback" }

function T.style(V: any): any
	-- 기본: 기존 가구는 그대로, 천장 설비만 (모듈을 채우면서 바꿈)
	return { chair = false, stool = false, table = false, counter = false, base = false, lower = false, mat = false, clock = false, license = false, cctv = false, ceiling = {}, lights = { kind = "none" }, skip = { upgrades = true, fixtures = true } }
end

function T.build(K: any, V: any, S: any) end

return T

end

__defs["T_pub"] = function()
-- GwangalliBuildingInterior/T_pub: 유형 (pub) 실내 — 크래프트 비어 펍 · 탭하우스 · 스포츠 펍 · 칵테일 바 · 파티 펍.
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (테마별 바닥 · 징두리 · 카운터 · 스툴 · 펜던트)
--   build(K, V, S) 유형별 디테일:
--     백바 (스모크 거울 · 조명 유리 선반 · 술병 · 하부장 + 유리문 맥주 쿨러 · 상호 크라운)
--     탭 타워 (맵 TapPost/TapBar/TapHandle/DripTray 와 같은 자리 · 같은 높이로 덮어씌움) · 황동 발판 레일 · 코스터
--     탭 리스트 보드 (스타일 · ABV · 가격) · 안주 보드 · 네온사인 · 스포츠 TV · 다트 머신 · 브라이트 탱크 · 케그
--     노출 천장 (스파이럴 덕트 · 에디슨 전구 · 페스툰 전구줄) · 벤치 소파 (같은 자리) · 포스터 · 안내판
--     (영업시간 · 19세 미만 출입금지 · 와이파이 · 원산지 · 간편결제 · 음주운전 · STAFF ONLY)
--   상호작용 (이 클라이언트만): TV 채널 · 네온 켜기/끄기 · 다트 게임 · 주크박스 — 주문 · 계산 · 앉기와 겹치지 않음

local Look = __require("Look")
local Props = __require("Props")
local Interact = __require("Interact")
local Common = __require("Common")
local Scan = __require("Scan")

local T = {}
T.types = { "pub" }

local L = Look
local M = Enum.Material
local F = Enum.Font
local CF, V3 = CFrame.new, Vector3.new
local ANG = CFrame.Angles
local PI = math.pi
local rgb = Color3.fromRGB

-- 공용 도우미 ------------------------------------------------------------------------------------------
local function wood(r: number, g: number, b: number): any
	return L.of(r, g, b, M.Wood)
end

local function dim(look: any, f: number): any
	return L.with(look, { c = (look.c :: Color3):Lerp(Color3.new(0, 0, 0), f) })
end

local function hash(s: string): number
	local h = 7
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 1000003
	end
	return h
end

local function rnd(seed: number, i: number): number
	local s = math.sin(seed * 0.7311 + i * 12.9898) * 43758.5453
	return s - math.floor(s)
end

local function extend(base: any, over: any): any
	local t = table.clone(base)
	for k, v in over do
		t[k] = v
	end
	return t
end

local function laabb(lcf: CFrame, size: Vector3): (Vector3, Vector3)
	local h = size / 2
	local ex = math.abs(lcf.XVector.X) * h.X + math.abs(lcf.YVector.X) * h.Y + math.abs(lcf.ZVector.X) * h.Z
	local ey = math.abs(lcf.XVector.Y) * h.X + math.abs(lcf.YVector.Y) * h.Y + math.abs(lcf.ZVector.Y) * h.Z
	local ez = math.abs(lcf.XVector.Z) * h.X + math.abs(lcf.YVector.Z) * h.Y + math.abs(lcf.ZVector.Z) * h.Z
	local p = lcf.Position
	return V3(p.X - ex, p.Y - ey, p.Z - ez), V3(p.X + ex, p.Y + ey, p.Z + ez)
end

local function overlap(amin: Vector3, amax: Vector3, bmin: Vector3, bmax: Vector3): boolean
	return amin.X < bmax.X - 0.02 and amax.X > bmin.X + 0.02 and amin.Y < bmax.Y - 0.02 and amax.Y > bmin.Y + 0.02 and amin.Z < bmax.Z - 0.02 and amax.Z > bmin.Z + 0.02
end

local function hideRec(K: any, r: any)
	Scan.hide(K.hidden, r.part)
end

local function budget(K: any, n: number): boolean
	return #K.parts + n < K.maxParts * 0.94
end

-- 벽 위 표시면에서 앞을 보는 원판 (다트판 · 맨홀 · 계기판): dcf 의 +Z 쪽으로 z..z+t
local function wdisc(K: any, name: string, dia: number, t: number, dcf: CFrame, z: number, look: any): BasePart
	return K:make("Part", name, V3(t, dia, dia), dcf * CF(0, 0, z + t / 2) * ANG(0, PI / 2, 0), look, Enum.PartType.Cylinder)
end

-- 수평 글자판 (카운터 위 코스터 글자 등): +Z(보는 사람) = 위, 글자 윗변 = -Z
local function flatCF(p: Vector3): CFrame
	return CFrame.fromMatrix(p, V3(1, 0, 0), V3(0, 0, -1), V3(0, 1, 0))
end

-- 벽 자리 관리 -------------------------------------------------------------------------------------------
-- Common.wallSpot 와 같은 K.wallUsed 를 씀 (Common 이 먼저 붙인 스위치 · 비상벨 · 콘센트를 피함)
local function claim(K: any, wn: string, a: number, b: number, y0: number, y1: number)
	K.wallUsed = K.wallUsed or {}
	table.insert(K.wallUsed, { w = wn, a = a, b = b, y0 = y0, y1 = y1 })
end

local function usedHit(K: any, wn: string, a: number, b: number, y0: number, y1: number): boolean
	for _, u in K.wallUsed or {} do
		if u.w == wn and u.a < b and u.b > a and u.y0 < y1 and u.y1 > y0 then
			return true
		end
	end
	return false
end

local function freeSpans(K: any, wn: string, y0: number, y1: number, depth: number?): { { number } }
	local V = K.V
	local out = {}
	for _, s in V:spans(wn, y0, y1, depth or 0.8) do
		local segs = { { s[1], s[2] } }
		for _, u in K.wallUsed or {} do
			if u.w == wn and u.y0 < y1 and u.y1 > y0 then
				local nxt = {}
				for _, g in segs do
					if u.b <= g[1] or u.a >= g[2] then
						table.insert(nxt, g)
					else
						if u.a > g[1] then
							table.insert(nxt, { g[1], u.a })
						end
						if u.b < g[2] then
							table.insert(nxt, { u.b, g[2] })
						end
					end
				end
				segs = nxt
			end
		end
		for _, g in segs do
			if g[2] - g[1] > 0.4 then
				table.insert(out, g)
			end
		end
	end
	return out
end

-- walls 순서대로: 폭 minW..maxW 가 들어가는 빈 구간 중 near 에 가까운 자리. test(wn, u, w) 로 추가 조건.
-- 반환 wn, u (벽 좌표), w (실제 폭). 찾은 자리는 claim.
local function findWall(K: any, walls: { string }, minW: number, maxW: number, y0: number, y1: number, near: Vector3?, depth: number?, test: any?): (string?, number?, number?)
	local V = K.V
	for _, wn in walls do
		if not V.walls[wn] then
			continue
		end
		local target = if near then (V:wallCoord(wn, near)) else 0
		local best, bu, bw = math.huge, nil, nil
		for _, s in freeSpans(K, wn, y0, y1, depth) do
			local span = s[2] - s[1] - 0.2
			if span >= minW then
				local w = math.min(maxW, span)
				local lo, hi = s[1] + 0.1 + w / 2, s[2] - 0.1 - w / 2
				local cands = { math.clamp(target, lo, hi) }
				if test then
					local k = lo
					while k <= hi + 1e-3 do
						table.insert(cands, k)
						k += 0.5
					end
					table.sort(cands, function(a, b)
						return math.abs(a - target) < math.abs(b - target)
					end)
				end
				for _, cu in cands do
					local d = math.abs(cu - target)
					if d >= best then
						break
					end
					if not test or test(wn, cu, w) then
						best, bu, bw = d, cu, w
						break
					end
				end
			end
		end
		if bu and bw then
			claim(K, wn, bu - bw / 2 - 0.15, bu + bw / 2 + 0.15, y0, y1)
			return wn, bu, bw
		end
	end
	return nil, nil, nil
end

-- 맵 파트(쉘 제외)와 안 겹치나
local function mapClear(V: any, mn: Vector3, mx: Vector3): boolean
	for _, r in V.parts do
		if not r.shell and not r.point and overlap(mn, mx, r.min, r.max) then
			return false
		end
	end
	return true
end

-- 벽에 붙여 세우는 바닥 소품 자리 (K:spot 으로 예약). 반환 pcf (+Z = 방 안쪽), wn, u
local function floorOnWall(K: any, walls: { string }, size: Vector3, near: Vector3?, pad: number?, test: any?): (CFrame?, string?, number?)
	local V = K.V
	for _, wn in walls do
		local w = V.walls[wn]
		if not w then
			continue
		end
		local target = if near then (V:wallCoord(wn, near)) else (w.a + w.b) / 2
		local cands = {}
		local u = w.a + size.X / 2 + 0.3
		while u <= w.b - size.X / 2 - 0.3 do
			table.insert(cands, u)
			u += 0.5
		end
		table.sort(cands, function(a, b)
			return math.abs(a - target) < math.abs(b - target)
		end)
		for _, cu in cands do
			local pcf = V:wall(wn, cu, 0, size.Z / 2 + 0.14)
			local mn, mx = laabb(pcf * CF(0, size.Y / 2, 0), size + V3(0.2, 0, 0.2))
			if mapClear(V, mn, mx) and not usedHit(K, wn, cu - size.X / 2, cu + size.X / 2, 0, size.Y) and (not test or test(pcf, wn, cu)) and K:spot(pcf, size, pad or 0.1, "pub") then
				claim(K, wn, cu - size.X / 2 - 0.15, cu + size.X / 2 + 0.15, 0, size.Y + 0.2)
				return pcf, wn, cu
			end
		end
	end
	return nil, nil, nil
end

-- 벽에 붙은 프롬프트 자리가 서버 앵커에서 충분히 먼가
local function promptOK(K: any, lp: Vector3): boolean
	return Interact.canPrompt(K, lp)
end

-- 카운터 안쪽 (직원 쪽) 인가
local function behindCounter(V: any, p: Vector3): boolean
	for _, g in V.counters do
		local alongX = (g.max.X - g.min.X) >= (g.max.Z - g.min.Z)
		if alongX then
			local custPlus = (if V.door then V.door.z else V.z1) > (g.min.Z + g.max.Z) / 2
			if p.X > g.min.X - 1.6 and p.X < g.max.X + 1.6 then
				if custPlus and p.Z < g.min.Z + 0.2 then
					return true
				elseif not custPlus and p.Z > g.max.Z - 0.2 then
					return true
				end
			end
		else
			local cx = (g.min.X + g.max.X) / 2
			if p.Z > g.min.Z - 1.6 and p.Z < g.max.Z + 1.6 then
				if cx < 0 and p.X < g.min.X + 0.2 then
					return true
				elseif cx >= 0 and p.X > g.max.X - 0.2 then
					return true
				end
			end
		end
	end
	for _, k in V.keep do
		if k.kind == "staff" and p.X > k.min.X - 0.6 and p.X < k.max.X + 0.6 and p.Z > k.min.Z - 0.6 and p.Z < k.max.Z + 0.6 then
			return true
		end
	end
	return false
end

-- 손님이 벽 앞 (1.3 ~ 3.4 스터드) 에 설 자리가 있나 (가구 · 카운터 안쪽 · 문 앞 제외)
local function reachable(K: any, wn: string, u: number): boolean
	local V = K.V
	for _, off in { 1.3, 2.3, 3.4, 4.0 } do
		local p = V:wall(wn, u, 0, off).Position
		if p.X > V.x0 + 0.4 and p.X < V.x1 - 0.4 and p.Z > V.z0 + 0.4 and p.Z < V.z1 - 0.4 and not behindCounter(V, p) then
			local mn, mx = p + V3(-0.35, 0.2, -0.35), p + V3(0.35, 3.0, 0.35)
			local ok = true
			for _, s in V.solid do
				if overlap(mn, mx, s.min, s.max) then
					ok = false
					break
				end
			end
			if ok then
				for _, r in K.reserved do
					if overlap(mn, mx, r.min, r.max) then
						ok = false
						break
					end
				end
			end
			if ok then
				return true
			end
		end
	end
	return false
end

-- 작은 소품: keep 에 걸리면 아예 안 만듦 (blocked 수를 늘리지 않게)
local function clearAt(K: any, cf: CFrame, size: Vector3): boolean
	local mn, mx = laabb(cf, size)
	return K:hitsKeep(mn, mx) == nil
end

-- 테마 --------------------------------------------------------------------------------------------------
-- 탭 리스트 행: { 이름, 스타일, ABV, 가격, 맥주색, 탭 핸들 약자, 핸들색 }
local THEMES: { [string]: any } = {}

THEMES.monk = {
	key = "monk",
	brand = "HAPPY MONK",
	crown = "HAPPY MONK  ·  CRAFT BREWERY  ·  광안리",
	font = F.Oswald,
	dark = wood(66, 42, 28),
	mid = wood(104, 70, 44),
	trim = L.brass,
	cabTop = L.of(44, 42, 42, M.Marble),
	mirror = L.of(78, 72, 64, M.Glass, { r = 0.32 }),
	seat = L.of(48, 74, 56, M.Leather),
	seatStyle = "tuft",
	stool = { style = "bar", frame = L.blackMetal, seat = L.of(48, 74, 56, M.Leather) },
	tableTop = wood(122, 84, 52),
	counterFront = "panel",
	counterFrontL = wood(82, 54, 34),
	counterTop = wood(58, 36, 22),
	led = rgb(255, 176, 96),
	floor = { look = L.of(98, 66, 44, M.WoodPlanks), tile = 0 },
	lower = { kind = "wainscot", h = 3.6, look = wood(72, 47, 30), cap = wood(54, 35, 22), panel = 1.9, walls = { "left", "right", "back" } },
	feature = { wall = "left", look = L.of(120, 66, 50, M.Brick) },
	paint = L.of(42, 58, 48),
	ceil = L.of(30, 28, 27),
	pendant = { shade = "dome", look = L.of(40, 62, 48, M.Metal) },
	tablePendant = "bulb",
	neonC = rgb(255, 172, 60),
	neon2 = rgb(255, 92, 70),
	neonText = "CHEERS!",
	neonIcon = "mug",
	neonFont = F.FredokaOne,
	shelfLED = rgb(255, 190, 120),
	board = "chalk",
	boardTitle = "ON TAP  ·  오늘의 생맥주",
	boardSub = "473ml PINT  ·  모든 맥주 하프(330ml) 가능",
	boardFoot = "샘플러 4종 15,000원  ·  매일 17-19시 해피아워 1,000원 할인",
	taps = {
		{ "몽크 윗비어", "Belgian Witbier", "4.9%", "8,500", rgb(240, 214, 140), "WIT", rgb(232, 220, 180) },
		{ "광안 블론드", "Belgian Blonde", "6.2%", "9,000", rgb(232, 184, 72), "BLONDE", rgb(212, 164, 56) },
		{ "갈매기 IPA", "West Coast IPA", "6.8%", "9,500", rgb(214, 140, 48), "IPA", rgb(56, 112, 66) },
		{ "수도원 두벨", "Abbey Dubbel", "7.0%", "10,000", rgb(124, 62, 30), "DUBBEL", rgb(116, 40, 32) },
		{ "트리펠 몽크", "Tripel", "8.5%", "11,000", rgb(226, 170, 60), "TRIPEL", rgb(36, 36, 38) },
		{ "해변 세종", "Farmhouse Saison", "6.0%", "9,500", rgb(224, 176, 84) },
		{ "민락 스타우트", "Oatmeal Stout", "5.8%", "9,000", rgb(36, 24, 18) },
		{ "쿼드 리저브", "Quadrupel", "10.2%", "13,000", rgb(96, 38, 24) },
	},
	foodTitle = "FOOD  ·  안주",
	food = {
		{ "트러플 감자튀김", nil, nil, "9,000" },
		{ "피쉬 앤 칩스", nil, nil, "18,000" },
		{ "벨기에식 홍합찜", nil, nil, "24,000" },
		{ "수제 소시지 플래터", nil, nil, "19,000" },
		{ "버팔로 윙 8pc", nil, nil, "16,000" },
		{ "치즈 플래터", nil, nil, "22,000" },
		{ "노가리 & 땅콩", nil, nil, "9,000" },
	},
	posters = { "monk", "bridge", "prost", "stout", "rules" },
	plants = { "olive", "ficus" },
	tanks = true,
	kegs = true,
	dart = true,
	festoon = false,
	wifi = "HAPPYMONK_5G\nPW  monk2026!",
	hours = "영업시간\nOPEN 17:00 – 02:00\n금 · 토 03:00까지\nLAST ORDER 01:30",
	mat = "HAPPY MONK",
	bottleMix = { "square", "round", "wine", "squat", "tall" },
}

THEMES.wave = {
	key = "wave",
	brand = "WILD WAVE",
	crown = "WILD WAVE  ·  SURF BREWING  ·  BUSAN",
	font = F.Bangers,
	dark = wood(150, 112, 74),
	mid = wood(190, 152, 106),
	trim = L.blackMetal,
	cabTop = L.of(210, 206, 196, M.Concrete),
	mirror = L.of(110, 120, 122, M.Glass, { r = 0.3 }),
	seat = L.of(38, 110, 118, M.Leather),
	seatStyle = "channel",
	stool = { style = "wood", frame = wood(172, 132, 88), seat = wood(172, 132, 88) },
	tableTop = wood(178, 138, 94),
	counterFront = "fluted",
	counterFrontL = wood(164, 124, 82),
	counterTop = L.of(206, 202, 192, M.Concrete),
	led = rgb(255, 204, 150),
	floor = { look = L.of(160, 158, 152, M.Concrete), tile = 4, grout = L.of(120, 118, 114) },
	lower = { kind = "louver", h = 3.6, look = wood(178, 138, 94), back = L.of(36, 66, 72), walls = { "left", "right" } },
	feature = { wall = "left", look = L.of(232, 228, 218, M.Brick) },
	paint = L.of(34, 74, 84),
	ceil = L.of(34, 36, 38),
	pendant = { shade = "cone", look = L.of(30, 92, 102, M.Metal) },
	tablePendant = "bulb",
	neonC = rgb(80, 220, 255),
	neon2 = rgb(255, 120, 180),
	neonText = "RIDE THE WAVE",
	neonIcon = "wave",
	neonFont = F.Bangers,
	shelfLED = rgb(200, 236, 255),
	board = "digital",
	boardTitle = "ON TAP  ·  WILD WAVE BREWING",
	boardSub = "500ml  ·  광안리 해변에서 만든 서핑 맥주",
	boardFoot = "그라울러 포장 1L 18,000원~  ·  해피아워 17-19시",
	taps = {
		{ "와일드 필스너", "Pilsner", "4.8%", "7,500", rgb(240, 206, 110), "PILS", rgb(250, 250, 246) },
		{ "서프 페일에일", "American Pale Ale", "5.3%", "8,500", rgb(226, 164, 64), "PALE", rgb(40, 150, 170) },
		{ "광안 헤이지 IPA", "Hazy IPA", "6.5%", "9,500", rgb(236, 190, 90), "HAZY", rgb(250, 190, 60) },
		{ "타이드 고제", "Sea Salt Gose", "4.2%", "9,000", rgb(236, 210, 150), "GOSE", rgb(80, 200, 220) },
		{ "빅 스웰 DIPA", "Double IPA", "8.2%", "11,000", rgb(214, 130, 40) },
		{ "블랙 타이드", "Porter", "5.6%", "9,000", rgb(44, 28, 20) },
		{ "선셋 앰버", "Amber Ale", "5.2%", "8,500", rgb(170, 84, 36) },
		{ "유자 위트", "Yuzu Wheat", "4.6%", "8,500", rgb(244, 216, 120) },
	},
	foodTitle = "BEACH FOOD",
	food = {
		{ "감바스 알 아히요", nil, nil, "19,000" },
		{ "피쉬 타코 3pc", nil, nil, "15,000" },
		{ "새우튀김 & 칩스", nil, nil, "17,000" },
		{ "클램 차우더", nil, nil, "12,000" },
		{ "할라피뇨 나초", nil, nil, "13,000" },
		{ "감자튀김", nil, nil, "8,000" },
	},
	posters = { "surf", "bridge", "ipa", "map" },
	plants = { "bamboo", "monstera" },
	tanks = true,
	kegs = true,
	dart = false,
	festoon = true,
	surf = true,
	wifi = "WILDWAVE_FREE\nPW  surf2026",
	hours = "영업시간\nOPEN 15:00 – 01:00\n연중무휴\nLAST ORDER 24:30",
	mat = "WILD WAVE",
	bottleMix = { "round", "tall", "square", "wine" },
}

THEMES.tap = {
	key = "tap",
	brand = "광안 탭하우스",
	crown = "GWANGAN TAP HOUSE  ·  20 TAPS",
	font = F.Oswald,
	dark = L.of(38, 38, 40, M.Metal),
	mid = wood(150, 110, 72),
	trim = L.of(176, 180, 184, M.Metal, { r = 0.06 }),
	cabTop = wood(150, 110, 72),
	mirror = L.of(70, 72, 74, M.Glass, { r = 0.3 }),
	seat = L.of(120, 74, 44, M.Leather),
	seatStyle = "channel",
	stool = { style = "bar", frame = L.blackMetal, seat = L.of(120, 74, 44, M.Leather) },
	tableTop = wood(150, 110, 72),
	counterFront = "tile",
	counterFrontL = L.of(236, 236, 230, M.CeramicTiles),
	counterTop = wood(140, 100, 64),
	led = rgb(255, 200, 130),
	floor = { look = L.of(150, 148, 144, M.Concrete), tile = 4, grout = L.of(108, 106, 102) },
	lower = { kind = "tile", h = 4.2, look = L.tileWhite, grout = L.of(70, 70, 72), tw = 0.6, th = 0.3, walls = { "left", "right" } },
	feature = { wall = "right", look = L.of(116, 66, 52, M.Brick) },
	paint = L.of(42, 44, 46),
	ceil = L.of(30, 30, 32),
	pendant = { shade = "bulb" },
	tablePendant = "cone",
	neonC = rgb(255, 214, 150),
	neon2 = rgb(255, 120, 60),
	neonText = "TAP HOUSE",
	neonIcon = "mug",
	neonFont = F.Oswald,
	shelfLED = rgb(255, 214, 170),
	board = "chalk",
	boardTitle = "TODAY'S TAP LIST",
	boardSub = "부산 · 국내 크래프트 생맥주  ·  473ml",
	boardFoot = "탭은 매주 바뀝니다  ·  시음은 직원에게 말씀해 주세요",
	taps = {
		{ "광안 라거", "Helles Lager", "4.6%", "7,000", rgb(240, 206, 110), "LAGER", rgb(220, 180, 60) },
		{ "해운대 필스너", "Czech Pils", "5.0%", "7,500", rgb(236, 196, 92), "PILS", rgb(40, 90, 160) },
		{ "다이아몬드 IPA", "IPA", "6.4%", "9,000", rgb(214, 140, 48), "IPA", rgb(190, 40, 40) },
		{ "수영강 헤페", "Hefeweizen", "5.2%", "8,000", rgb(236, 190, 96), "WEIZEN", rgb(240, 236, 220) },
		{ "민락 레드", "Irish Red Ale", "5.0%", "8,000", rgb(150, 56, 30) },
		{ "부산항 포터", "Robust Porter", "6.0%", "8,500", rgb(40, 26, 18) },
		{ "감귤 사워", "Fruit Sour", "4.5%", "9,000", rgb(240, 150, 70) },
		{ "오륙도 DIPA", "Double IPA", "8.0%", "10,500", rgb(220, 140, 40) },
	},
	foodTitle = "SNACKS",
	food = {
		{ "수제 피클 & 올리브", nil, nil, "6,000" },
		{ "트러플 감자튀김", nil, nil, "10,000" },
		{ "수제 소시지 2종", nil, nil, "15,000" },
		{ "바베큐 폭립", nil, nil, "26,000" },
		{ "맥앤치즈", nil, nil, "12,000" },
		{ "프레첼 & 머스터드", nil, nil, "8,000" },
	},
	posters = { "map", "ipa", "rules", "bridge" },
	plants = { "snake" },
	tanks = true,
	kegs = true,
	dart = true,
	festoon = false,
	wifi = "GWANGAN_TAP\nPW  20taps!",
	hours = "영업시간\nOPEN 16:00 – 01:00\n월요일 휴무\nLAST ORDER 24:30",
	mat = "TAP HOUSE",
	bottleMix = { "round", "square", "tall" },
}

THEMES.sunset = {
	key = "sunset",
	brand = "SUNSET PUB",
	crown = "SUNSET PUB  ·  SPORTS & BEER",
	font = F.GothamBlack,
	dark = wood(84, 56, 38),
	mid = wood(130, 90, 58),
	trim = L.brass,
	cabTop = L.of(38, 38, 40, M.Granite),
	mirror = L.of(86, 80, 74, M.Glass, { r = 0.3 }),
	seat = L.of(168, 92, 52, M.Leather),
	seatStyle = "channel",
	stool = { style = "cushion", frame = L.blackMetal, seat = L.of(168, 92, 52, M.Leather) },
	tableTop = wood(140, 96, 60),
	counterFront = "panel",
	counterFrontL = L.of(34, 44, 70),
	counterTop = wood(90, 58, 36),
	led = rgb(255, 150, 80),
	floor = { look = L.of(112, 76, 50, M.WoodPlanks), tile = 0 },
	lower = { kind = "wainscot", h = 3.4, look = L.of(32, 42, 68), cap = wood(92, 62, 40), panel = 1.7, walls = { "left", "right", "back" } },
	feature = { wall = "left", look = L.of(118, 70, 54, M.Brick) },
	paint = L.of(70, 50, 44),
	ceil = L.of(30, 30, 34),
	pendant = { shade = "dome", look = L.of(196, 92, 52, M.Metal) },
	tablePendant = "bulb",
	neonC = rgb(255, 128, 60),
	neon2 = rgb(255, 60, 140),
	neonText = "SUNSET",
	neonIcon = "sun",
	neonFont = F.FredokaOne,
	shelfLED = rgb(255, 170, 110),
	board = "digital",
	boardTitle = "BEER & DRINKS",
	boardSub = "생맥주 · 수입맥주 · 하이볼",
	boardFoot = "스포츠 중계 있는 날 피처 2,000원 할인",
	taps = {
		{ "생맥주 (라거) 500cc", "Draft Lager", "4.8%", "5,500", rgb(240, 200, 100), "LAGER", rgb(250, 120, 40) },
		{ "생맥주 1,000cc", "Draft Lager", "4.8%", "9,900", rgb(240, 200, 100), "DARK", rgb(30, 30, 34) },
		{ "피처 3,000cc", "Pitcher", "4.8%", "22,000", rgb(240, 200, 100), "IPA", rgb(40, 120, 200) },
		{ "흑맥주 500cc", "Dark Lager", "5.0%", "6,500", rgb(50, 30, 20), "WHEAT", rgb(250, 230, 160) },
		{ "부산 IPA 473ml", "IPA", "6.5%", "8,900", rgb(214, 140, 48) },
		{ "하이볼", "Whisky Highball", "7%", "9,000", rgb(230, 190, 110) },
		{ "소맥 세트 (소주 1 + 500cc 2)", "Somaek", "", "15,000", rgb(250, 250, 240) },
		{ "칵테일 (모히또 · 선라이즈)", "Cocktail", "", "9,900", rgb(250, 120, 80) },
	},
	foodTitle = "PUB FOOD",
	food = {
		{ "감자튀김", nil, nil, "8,000" },
		{ "치킨 텐더 & 칩스", nil, nil, "14,000" },
		{ "버팔로 윙", nil, nil, "15,000" },
		{ "나초 플래터", nil, nil, "12,000" },
		{ "소시지 야채볶음", nil, nil, "17,000" },
		{ "먹태 & 청양마요", nil, nil, "13,000" },
	},
	posters = { "lotte", "sunsetp", "prost", "rules" },
	plants = { "monstera", "snake" },
	tanks = false,
	kegs = true,
	dart = true,
	festoon = true,
	wifi = "SUNSET_PUB_5G\nPW  sunset0909",
	hours = "영업시간\nOPEN 11:00 – 02:00\n스포츠 중계 시 연장\nLAST ORDER 01:30",
	mat = "SUNSET",
	bottleMix = { "square", "round", "tall", "squat" },
}

THEMES.fuzzy = {
	key = "fuzzy",
	brand = "FUZZY NAVEL",
	crown = "FUZZY NAVEL  ·  COCKTAIL BAR",
	font = F.Bangers,
	dark = L.of(28, 24, 28, M.Wood),
	mid = L.of(64, 40, 58, M.Wood),
	trim = L.goldMetal,
	cabTop = L.of(236, 232, 226, M.Marble),
	mirror = L.of(110, 90, 72, M.Glass, { r = 0.36 }),
	seat = L.of(122, 44, 94, M.Fabric),
	seatStyle = "channel",
	stool = { style = "cushion", frame = L.goldMetal, seat = L.of(122, 44, 94, M.Fabric) },
	tableTop = L.of(236, 232, 226, M.Marble),
	counterFront = "fluted",
	counterFrontL = L.of(36, 30, 38, M.Wood),
	counterTop = L.of(236, 232, 226, M.Marble),
	led = rgb(255, 90, 180),
	floor = { look = L.of(40, 38, 42, M.Marble), tile = 2.5, grout = L.of(150, 120, 70) },
	lower = { kind = "paint", h = 3.6, look = L.of(40, 30, 46), cap = L.goldMetal, walls = { "left", "right", "back" } },
	feature = nil,
	paint = L.of(32, 26, 40),
	ceil = L.of(20, 18, 22),
	pendant = { shade = "globe", look = L.of(240, 206, 226, M.Glass, { t = 0.3 }) },
	tablePendant = "globe",
	neonC = rgb(255, 80, 180),
	neon2 = rgb(150, 100, 255),
	neonText = "Fuzzy Navel",
	neonIcon = "cocktail",
	neonFont = F.FredokaOne,
	shelfLED = rgb(255, 150, 220),
	board = "brass",
	boardTitle = "SIGNATURE COCKTAILS",
	boardSub = "바텐더 추천  ·  모든 칵테일 논알콜 가능",
	boardFoot = "칵테일 2잔 이상 주문 시 나쵸 서비스",
	taps = {
		{ "퍼지 네이블", "피치 · 오렌지", "8%", "12,000", rgb(255, 160, 80), "PEACH", rgb(255, 150, 90) },
		{ "모히또", "럼 · 라임 · 민트", "10%", "13,000", rgb(170, 230, 140), "MOJITO", rgb(90, 200, 120) },
		{ "광안 선셋", "보드카 · 패션후르츠", "12%", "14,000", rgb(255, 110, 90), "SUNSET", rgb(255, 90, 140) },
		{ "롱아일랜드 아이스티", "5 Spirits · 콜라", "22%", "15,000", rgb(150, 80, 40), "LIIT", rgb(60, 60, 64) },
		{ "마가리타", "데킬라 · 라임", "15%", "13,000", rgb(220, 240, 170) },
		{ "에스프레소 마티니", "보드카 · 커피", "18%", "14,000", rgb(60, 36, 26) },
		{ "진토닉", "진 · 토닉 · 라임", "10%", "11,000", rgb(230, 244, 240) },
		{ "하이볼", "위스키 · 소다", "9%", "10,000", rgb(230, 186, 100) },
	},
	foodTitle = "BAR BITES",
	food = {
		{ "치즈 & 크래커", nil, nil, "15,000" },
		{ "제철 과일 플래터", nil, nil, "25,000" },
		{ "트러플 감자튀김", nil, nil, "11,000" },
		{ "나쵸 & 과카몰리", nil, nil, "13,000" },
		{ "초콜릿 퐁듀", nil, nil, "16,000" },
	},
	posters = { "cocktail", "deco", "bridge" },
	plants = { "snake", "monstera" },
	tanks = false,
	kegs = false,
	dart = false,
	festoon = false,
	glassRack = true,
	wifi = "FUZZYNAVEL_BAR\nPW  peach1212",
	hours = "영업시간\nOPEN 24 HOURS\n연중무휴\n해피아워 17:00 – 20:00",
	mat = "FUZZY NAVEL",
	bottleMix = { "square", "round", "wine", "squat", "tall", "round" },
}

THEMES.party = extend(THEMES.sunset, {
	key = "party",
	brand = "THURSDAY PARTY",
	crown = "THURSDAY PARTY  ·  광안리점",
	dark = L.of(26, 26, 30, M.SmoothPlastic),
	mid = L.of(52, 52, 58, M.SmoothPlastic),
	trim = L.chrome,
	cabTop = L.of(30, 30, 34, M.Granite),
	mirror = L.of(60, 60, 70, M.Glass, { r = 0.34 }),
	seat = L.of(30, 30, 34, M.Leather),
	stool = { style = "bar", frame = L.chrome, seat = L.of(200, 40, 60, M.Leather) },
	tableTop = L.of(30, 30, 34, M.Granite),
	counterFront = "panel",
	counterFrontL = L.of(26, 26, 30),
	counterTop = L.of(28, 28, 32, M.Granite),
	led = rgb(130, 90, 255),
	floor = { look = L.of(32, 32, 36, M.Slate), tile = 3, grout = L.of(64, 64, 72) },
	lower = { kind = "paint", h = 3.4, look = L.of(26, 26, 30), cap = L.chrome, walls = { "left", "right", "back" } },
	feature = nil,
	paint = L.of(22, 22, 26),
	ceil = L.of(18, 18, 20),
	pendant = { shade = "cone", look = L.chrome },
	neonC = rgb(255, 60, 200),
	neon2 = rgb(60, 220, 255),
	neonText = "PARTY ALL NIGHT",
	neonIcon = "star",
	board = "digital",
	boardTitle = "PARTY DRINKS",
	boardSub = "목요일은 파티 데이!",
	boardFoot = "생일 · 단체 예약 시 샴페인 서비스",
	taps = {
		{ "생맥주 500cc", "Draft", "4.8%", "4,500", rgb(240, 200, 100), "BEER", rgb(255, 60, 200) },
		{ "생맥주 피처 2,000cc", "Pitcher", "4.8%", "15,000", rgb(240, 200, 100), "PITCH", rgb(60, 220, 255) },
		{ "예거밤", "Jäger Bomb", "", "9,000", rgb(60, 30, 20), "BOMB", rgb(250, 200, 40) },
		{ "데킬라 샷", "Tequila Shot", "40%", "5,000", rgb(250, 230, 160), "SHOT", rgb(240, 240, 240) },
		{ "칵테일 타워 3L", "Cocktail Tower", "", "39,000", rgb(255, 90, 140) },
		{ "보드카 1병 세트", "Vodka + Mixer", "", "89,000", rgb(240, 244, 250) },
		{ "하이볼", "Highball", "7%", "8,000", rgb(230, 190, 110) },
		{ "소맥 타워", "Somaek Tower", "", "29,000", rgb(250, 240, 200) },
	},
	posters = { "party", "prost", "deco" },
	plants = { "snake" },
	festoon = false,
	disco = true,
	dart = true,
	wifi = "THURSDAY_PARTY\nPW  party2026",
	hours = "영업시간\nOPEN 19:00 – 05:00\n목 · 금 · 토 파티 나이트",
	mat = "THURSDAY PARTY",
})

THEMES.dogs = extend(THEMES.monk, {
	key = "dogs",
	brand = "MAD DOGS",
	crown = "MAD DOGS  ·  IRISH PUB",
	seat = L.of(120, 72, 44, M.Leather),
	seatStyle = "channel",
	paint = L.of(30, 58, 44),
	neonC = rgb(90, 255, 120),
	neonText = "MAD DOGS",
	neonIcon = "mug",
	tanks = false,
	boardTitle = "ON TAP  ·  IRISH PUB",
	taps = {
		{ "아이리시 스타우트", "Dry Stout", "4.2%", "9,000", rgb(30, 20, 16), "STOUT", rgb(30, 30, 30) },
		{ "레드 에일", "Irish Red", "4.8%", "8,500", rgb(150, 56, 30), "RED", rgb(170, 40, 40) },
		{ "골든 라거", "Lager", "4.6%", "7,000", rgb(240, 200, 100), "LAGER", rgb(230, 190, 60) },
		{ "사이더", "Apple Cider", "4.5%", "8,500", rgb(230, 190, 90), "CIDER", rgb(90, 160, 60) },
		{ "아이리시 위스키 샷", "Whiskey", "40%", "9,000", rgb(180, 110, 40) },
		{ "아이리시 커피", "Hot", "", "11,000", rgb(80, 50, 30) },
	},
	posters = { "stout", "prost", "rules" },
	wifi = "MADDOGS_PUB\nPW  slainte!",
	hours = "영업시간\nOPEN 11:00 – 02:00\n연중무휴",
	mat = "MAD DOGS",
})

THEMES.holiday = extend(THEMES.wave, {
	key = "holiday",
	brand = "WORKING HOLIDAY",
	crown = "WORKING HOLIDAY  ·  AUSSIE PUB",
	neonText = "G'DAY MATE",
	neonIcon = "sun",
	neonC = rgb(255, 190, 60),
	tanks = false,
	boardTitle = "AUSSIE BEERS",
	taps = {
		{ "오지 라거", "Australian Lager", "4.6%", "7,000", rgb(240, 206, 110), "AUSSIE", rgb(250, 190, 40) },
		{ "쿠퍼스 스타일 페일", "Pale Ale", "4.5%", "8,500", rgb(230, 180, 90), "PALE", rgb(40, 120, 60) },
		{ "골드코스트 IPA", "IPA", "6.0%", "9,000", rgb(214, 140, 48), "IPA", rgb(40, 90, 170) },
		{ "시드니 다크", "Dark Ale", "5.5%", "8,500", rgb(70, 40, 24), "DARK", rgb(30, 30, 34) },
		{ "미트 파이", "Meat Pie", "", "9,000", rgb(190, 130, 70) },
		{ "칩스 & 그레이비", "Chips", "", "8,000", rgb(230, 190, 110) },
	},
	posters = { "surf", "map", "prost" },
	wifi = "WORKING_HOLIDAY\nPW  gday2026",
	hours = "영업시간\nOPEN 12:00 – 01:00\n화요일 휴무",
	mat = "G'DAY",
})

THEMES.bat = extend(THEMES.sunset, {
	key = "bat",
	brand = "BEER BAT",
	crown = "BEER BAT  ·  BASEBALL PUB",
	neonText = "BEER BAT",
	neonIcon = "ball",
	neonC = rgb(255, 70, 60),
	neon2 = rgb(80, 160, 255),
	counterFrontL = L.of(20, 36, 80),
	lower = { kind = "wainscot", h = 3.4, look = L.of(20, 34, 76), cap = L.of(200, 40, 40), panel = 1.7, walls = { "left", "right", "back" } },
	posters = { "lotte", "lotte2", "prost", "rules" },
	bats = true,
	boardTitle = "직관보다 맛있는 생맥",
	boardFoot = "롯데 승리한 날 생맥 500cc 1잔 무료!",
	wifi = "BEERBAT_GIANTS\nPW  lotte1982",
	mat = "BEER BAT",
})

local function pickTheme(V: any): any
	local n = string.upper(V.name or "")
	local function has(s: string): boolean
		return string.find(n, s, 1, true) ~= nil
	end
	if has("MONK") then
		return THEMES.monk
	elseif has("WILD WAVE") or has("와일드") then
		return THEMES.wave
	elseif has("탭하우스") or has("TAP HOUSE") or has("TAPHOUSE") then
		return THEMES.tap
	elseif has("FUZZY") or V.menu == "cocktail" then
		return THEMES.fuzzy
	elseif has("THURSDAY") or V.menu == "party" then
		return THEMES.party
	elseif has("MAD DOG") then
		return THEMES.dogs
	elseif has("WORKING HOLIDAY") then
		return THEMES.holiday
	elseif has("BEER BAT") then
		return THEMES.bat
	elseif has("SUNSET") then
		local t = extend(THEMES.sunset, { brand = V.name })
		if has("ROOFTOP") then
			t.crown = "SUNSET ROOFTOP  ·  BAR & LOUNGE"
		end
		return t
	elseif V.menu == "craft" then
		return extend(THEMES.tap, { brand = V.name, crown = tostring(V.name) .. "  ·  CRAFT BEER" })
	end
	return extend(THEMES.sunset, { brand = V.name, crown = tostring(V.name) .. "  ·  PUB" })
end
T.pickTheme = pickTheme

-- 술병 · 맥주병 · 캔 --------------------------------------------------------------------------------------
local GLASS = {
	rgb(150, 86, 30), -- 앰버 (위스키 · 럼)
	rgb(96, 56, 24), -- 갈색
	rgb(226, 234, 236), -- 투명 (보드카 · 진 · 데킬라)
	rgb(40, 96, 56), -- 녹색 (와인 · 압생트 · 리큐르)
	rgb(40, 84, 160), -- 파랑 (진)
	rgb(70, 66, 62), -- 스모크
	rgb(150, 30, 34), -- 빨강 (비터)
	rgb(214, 168, 70), -- 골드 리큐르
	rgb(30, 28, 26), -- 검정 (허브 리큐르)
}
local LABELS = { rgb(244, 236, 214), rgb(30, 30, 32), rgb(196, 40, 40), rgb(236, 200, 90), rgb(240, 240, 240), rgb(40, 70, 120) }

local function bottle(K: any, base: CFrame, h: number, kind: string, gc: Color3, lab: Color3, cap: any, detail: string)
	local clear = gc.R > 0.8 and gc.G > 0.8
	local gl = { c = gc, m = M.Glass, t = if clear then 0.42 else 0.16, r = 0.12 }
	local labL = { c = lab, m = M.SmoothPlastic }
	if kind == "square" then
		local bh = h * 0.64
		K:box("Bottle", V3(0.34, bh, 0.3), base * CF(0, bh / 2, 0), gl)
		K:vcyl("BottleNeck", h * 0.26, 0.13, base * CF(0, bh + h * 0.13, 0), gl)
		K:vcyl("BottleCap", h * 0.1, 0.17, base * CF(0, h * 0.95, 0), cap)
		if detail ~= "low" then
			K:box("BottleLabel", V3(0.28, bh * 0.42, 0.012), base * CF(0, bh * 0.46, 0.156), labL)
		end
	elseif kind == "wine" then
		local bh = h * 0.56
		K:vcyl("Bottle", bh, 0.28, base * CF(0, bh / 2, 0), gl)
		K:ell("BottleShoulder", V3(0.28, 0.24, 0.28), base * CF(0, bh, 0), gl)
		K:vcyl("BottleNeck", h * 0.32, 0.1, base * CF(0, bh + h * 0.16 + 0.03, 0), gl)
		K:vcyl("BottleFoil", h * 0.12, 0.115, base * CF(0, h * 0.94, 0), cap)
		if detail ~= "low" then
			K:box("BottleLabel", V3(0.2, bh * 0.4, 0.012), base * CF(0, bh * 0.5, 0.142), labL)
		end
	elseif kind == "squat" then
		local bh = h * 0.55
		K:ell("Bottle", V3(0.44, bh, 0.44), base * CF(0, bh / 2, 0), gl)
		K:vcyl("BottleNeck", h * 0.4, 0.12, base * CF(0, h * 0.7, 0), gl)
		K:vcyl("BottleCap", h * 0.12, 0.17, base * CF(0, h * 0.94, 0), cap)
		if detail ~= "low" then
			K:box("BottleLabel", V3(0.22, bh * 0.36, 0.012), base * CF(0, bh * 0.48, 0.21), labL)
		end
	else
		local d = if kind == "tall" then 0.25 else 0.31
		local bh = h * (if kind == "tall" then 0.7 else 0.6)
		K:vcyl("Bottle", bh, d, base * CF(0, bh / 2, 0), gl)
		K:ell("BottleShoulder", V3(d, 0.18, d), base * CF(0, bh, 0), gl)
		K:vcyl("BottleNeck", h * 0.92 - bh, 0.11, base * CF(0, (bh + h * 0.92) / 2, 0), gl)
		K:vcyl("BottleCap", h * 0.09, 0.14, base * CF(0, h * 0.955, 0), cap)
		if detail ~= "low" then
			K:box("BottleLabel", V3(d * 0.72, bh * 0.4, 0.012), base * CF(0, bh * 0.45, d / 2 + 0.004), labL)
		end
	end
	if clear and detail == "high" then
		-- 투명한 병 속 술 (조금 남은 높이)
		local fh = h * 0.42
		local fd = if kind == "square" then 0.26 elseif kind == "squat" then 0.3 elseif kind == "wine" then 0.22 elseif kind == "tall" then 0.2 else 0.25
		K:vcyl("BottleSpirit", fh, fd, base * CF(0, fh / 2 + 0.02, 0), { c = rgb(246, 236, 210), m = M.Glass, t = 0.55 })
	end
end

-- 작은 맥주병 (쿨러 · 진열 선반)
local function beerBottle(K: any, base: CFrame, gc: Color3, lab: Color3, detail: string)
	local gl = { c = gc, m = M.Glass, t = 0.12, r = 0.1 }
	K:vcyl("BeerBottle", 0.36, 0.18, base * CF(0, 0.18, 0), gl)
	K:vcyl("BeerBottleNeck", 0.22, 0.08, base * CF(0, 0.46, 0), gl)
	K:vcyl("BeerBottleCap", 0.04, 0.095, base * CF(0, 0.585, 0), L.goldMetal)
	if detail == "high" then
		K:box("BeerLabel", V3(0.14, 0.15, 0.012), base * CF(0, 0.19, 0.092), { c = lab })
	end
end

-- 473ml 크래프트 캔
local function beerCan(K: any, base: CFrame, c: Color3, band: Color3, detail: string)
	K:vcyl("BeerCan", 0.46, 0.21, base * CF(0, 0.23, 0), { c = c, m = M.SmoothPlastic })
	K:vcyl("BeerCanTop", 0.03, 0.18, base * CF(0, 0.475, 0), L.alu)
	if detail == "high" then
		K:vcyl("BeerCanBand", 0.12, 0.214, base * CF(0, 0.27, 0), { c = band })
	end
end

-- 네온 관 (dcf 평면 위 폴리라인, 단위 s) --------------------------------------------------------------------
local function nline(K: any, dcf: CFrame, pts: { { number } }, s: number, z: number, d: number, look: any, out: { BasePart })
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local p = K:seg("NeonTube", (dcf * CF(a[1] * s, a[2] * s, z)).Position, (dcf * CF(b[1] * s, b[2] * s, z)).Position, d, look, d * 0.7)
		if p then
			table.insert(out, p)
		end
	end
end

local function narc(K: any, dcf: CFrame, cx: number, cy: number, r: number, a0: number, a1: number, n: number, s: number, z: number, d: number, look: any, out: { BasePart })
	local pts = {}
	for i = 0, n do
		local a = a0 + (a1 - a0) * i / n
		table.insert(pts, { cx + math.cos(a) * r, cy + math.sin(a) * r })
	end
	nline(K, dcf, pts, s, z, d, look, out)
end

-- 아이콘 (단위 상자 -0.5..0.5)
local function neonIcon(K: any, dcf: CFrame, kind: string, s: number, c: Color3, c2: Color3, out: { BasePart })
	local d = math.clamp(s * 0.045, 0.05, 0.09)
	local lk, lk2 = L.neon(c), L.neon(c2)
	local z = 0.12
	if kind == "mug" then
		nline(K, dcf, { { -0.3, -0.45 }, { 0.18, -0.45 }, { 0.22, 0.26 }, { -0.34, 0.26 }, { -0.3, -0.45 } }, s, z, d, lk, out)
		narc(K, dcf, 0.24, -0.08, 0.16, -1.35, 1.35, 6, s, z, d, lk, out)
		narc(K, dcf, -0.22, 0.3, 0.11, 0, PI, 5, s, z, d, lk2, out)
		narc(K, dcf, -0.02, 0.33, 0.12, 0, PI, 5, s, z, d, lk2, out)
		narc(K, dcf, 0.16, 0.3, 0.08, 0, PI, 4, s, z, d, lk2, out)
		nline(K, dcf, { { -0.16, -0.32 }, { -0.15, 0.12 } }, s, z, d * 0.8, lk, out)
		nline(K, dcf, { { 0.03, -0.32 }, { 0.05, 0.12 } }, s, z, d * 0.8, lk, out)
	elseif kind == "wave" then
		local p1, p2 = {}, {}
		for i = 0, 14 do
			local t = i / 14
			table.insert(p1, { -0.5 + t, 0.08 + 0.14 * math.sin(t * PI * 3) })
			table.insert(p2, { -0.45 + t * 0.9, -0.2 + 0.09 * math.sin(t * PI * 3 + 1) })
		end
		nline(K, dcf, p1, s, z, d, lk, out)
		nline(K, dcf, p2, s, z, d, lk, out)
		narc(K, dcf, 0.28, 0.36, 0.1, 0, 2 * PI, 8, s, z, d, lk2, out)
	elseif kind == "sun" then
		narc(K, dcf, 0, -0.12, 0.3, 0, PI, 10, s, z, d, lk, out)
		for k = 0, 6 do
			local a = PI * k / 6
			nline(K, dcf, { { math.cos(a) * 0.38, -0.12 + math.sin(a) * 0.38 }, { math.cos(a) * 0.5, -0.12 + math.sin(a) * 0.5 } }, s, z, d, lk, out)
		end
		nline(K, dcf, { { -0.5, -0.14 }, { 0.5, -0.14 } }, s, z, d, lk2, out)
		nline(K, dcf, { { -0.34, -0.3 }, { 0.34, -0.3 } }, s, z, d, lk2, out)
		nline(K, dcf, { { -0.18, -0.44 }, { 0.18, -0.44 } }, s, z, d, lk2, out)
	elseif kind == "cocktail" then
		nline(K, dcf, { { -0.38, 0.38 }, { 0.38, 0.38 }, { 0, -0.06 }, { -0.38, 0.38 } }, s, z, d, lk, out)
		nline(K, dcf, { { 0, -0.06 }, { 0, -0.42 } }, s, z, d, lk, out)
		nline(K, dcf, { { -0.2, -0.45 }, { 0.2, -0.45 } }, s, z, d, lk, out)
		narc(K, dcf, 0.1, 0.2, 0.07, 0, 2 * PI, 6, s, z, d, lk2, out)
		nline(K, dcf, { { 0.1, 0.2 }, { 0.3, 0.5 } }, s, z, d * 0.8, lk2, out)
	elseif kind == "star" then
		local pts = {}
		for k = 0, 10 do
			local a = PI / 2 + k * PI / 5
			local r = if k % 2 == 0 then 0.48 else 0.2
			table.insert(pts, { math.cos(a) * r, math.sin(a) * r })
		end
		nline(K, dcf, pts, s, z, d, lk, out)
		narc(K, dcf, 0, 0, 0.08, 0, 2 * PI, 6, s, z, d, lk2, out)
	elseif kind == "ball" then
		narc(K, dcf, 0, 0, 0.42, 0, 2 * PI, 16, s, z, d, lk2, out)
		narc(K, dcf, -0.66, 0, 0.44, -0.75, 0.75, 5, s, z, d, lk, out)
		narc(K, dcf, 0.66, 0, 0.44, PI - 0.75, PI + 0.75, 5, s, z, d, lk, out)
	end
end

-- 네온사인 묶음: 아크릴 뒤판 + 스탠드오프 + 아이콘 + 글자. store = { parts, labels, lights }
local function neonSign(K: any, dcf: CFrame, w: number, h: number, th: any, icon: string?, text: string, c: Color3, c2: Color3, store: any)
	K:panel("NeonBacker", w, h, 0.05, math.min(0.3, h * 0.2), dcf, { c = rgb(14, 14, 18), m = M.SmoothPlastic, r = 0.06 })
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			K:cyl("NeonStandoff", 0.17, 0.08, dcf * CF(sx * (w / 2 - 0.22), sy * (h / 2 - 0.18), 0.0) * ANG(0, PI / 2, 0), L.chrome)
		end
	end
	local iconW = if icon then math.min(h * 0.92, w * 0.4) else 0
	if icon then
		neonIcon(K, dcf * CF(-w / 2 + iconW / 2 + 0.2, 0, 0), icon, iconW, c, c2, store.parts)
	end
	local tw = w - iconW - 0.5
	local p, lab = K:text("NeonText", tw, h * 0.66, dcf * CF(iconW / 2 + 0.05, 0, 0.1), text, { fg = c, glow = 2.4, font = th.neonFont or F.FredokaOne, d = 0.02 })
	table.insert(store.labels, lab)
	local lp = store.parts[1] or p
	local li = K:light(lp, "PointLight", { Range = 11, Brightness = 1.15, Color = c })
	if li then
		table.insert(store.lights, li)
	end
	return p
end

-- 보드 (탭 리스트 · 안주 · 칵테일) -------------------------------------------------------------------------
local BOARD = {
	chalk = { face = L.of(36, 42, 40, M.Slate), frame = wood(86, 58, 38), fg = rgb(236, 234, 222), acc = rgb(250, 214, 110), dim = rgb(176, 186, 180), font = F.PermanentMarker, titleFont = F.PermanentMarker, glow = 1.0 },
	digital = { face = L.of(14, 16, 20, M.Glass, { r = 0.1 }), frame = L.of(24, 24, 26, M.Metal), fg = rgb(246, 246, 246), acc = rgb(255, 196, 60), dim = rgb(150, 170, 190), font = F.GothamMedium, titleFont = F.GothamBlack, glow = 1.3 },
	brass = { face = L.of(18, 16, 20), frame = L.goldMetal, fg = rgb(246, 236, 214), acc = rgb(222, 184, 104), dim = rgb(190, 170, 150), font = F.GothamMedium, titleFont = F.Oswald, glow = 1.15 },
}

-- rows = { { 이름, 스타일?, ABV?, 가격, 색? } }
local function listBoard(K: any, dcf: CFrame, w: number, h: number, style: string, title: string, sub: string?, rows: { any }, foot: string?, accent: Color3?)
	local st = BOARD[style] or BOARD.chalk
	local acc = accent or st.acc
	local fr = 0.16
	K:plate("BoardFace", w, h, 0.06, dcf, st.face)
	K:plate("BoardFrame", w + 2 * fr, fr, 0.12, dcf * CF(0, h / 2 + fr / 2, 0), st.frame)
	K:plate("BoardFrame", w + 2 * fr, fr, 0.12, dcf * CF(0, -h / 2 - fr / 2, 0), st.frame)
	K:plate("BoardFrame", fr, h, 0.12, dcf * CF(-w / 2 - fr / 2, 0, 0), st.frame)
	K:plate("BoardFrame", fr, h, 0.12, dcf * CF(w / 2 + fr / 2, 0, 0), st.frame)
	if style == "chalk" then
		-- 분필 받침 + 분필 두 개
		K:plate("BoardLedge", w * 0.5, 0.06, 0.2, dcf * CF(-w * 0.2, -h / 2 - fr - 0.03, 0), st.frame)
		K:box("Chalk", V3(0.3, 0.06, 0.06), dcf * CF(-w * 0.32, -h / 2 - fr + 0.03, 0.12), L.paper)
		K:box("Chalk", V3(0.24, 0.06, 0.06), dcf * CF(-w * 0.18, -h / 2 - fr + 0.03, 0.1) * ANG(0, 0.3, 0), L.of(250, 210, 120))
	end
	local z = 0.065
	local y = h / 2 - 0.12
	local tH = math.min(0.78, h * 0.15)
	K:text("BoardTitle", w * 0.9, tH, dcf * CF(0, y - tH / 2, z), title, { fg = acc, glow = st.glow, font = st.titleFont, d = 0.01 })
	y -= tH + 0.04
	if sub then
		local sH = math.min(0.3, tH * 0.42)
		K:text("BoardSub", w * 0.84, sH, dcf * CF(0, y - sH / 2, z), sub, { fg = st.dim, glow = st.glow, font = st.font, d = 0.01 })
		y -= sH + 0.06
	end
	K:plate("BoardRule", w * 0.9, 0.035, 0.075, dcf * CF(0, y, 0), { c = acc, m = M.SmoothPlastic })
	y -= 0.08
	local footH = if foot then math.min(0.3, h * 0.07) else 0
	local avail = y - (-h / 2 + 0.12 + footH + 0.06)
	local n = #rows
	local rh = math.min(0.62, avail / math.max(1, n))
	local hasMid = false
	for _, r in rows do
		if r[2] or r[3] then
			hasMid = true
		end
	end
	for i, r in rows do
		local yc = y - rh * (i - 0.5)
		local x0 = -w / 2 + 0.22
		if r[5] then
			wdisc(K, "BoardDot", rh * 0.46, 0.02, dcf * CF(x0 + rh * 0.23, yc, 0), 0.06, { c = r[5], m = M.SmoothPlastic })
			x0 += rh * 0.62
		end
		local nameW = if hasMid then w * 0.4 else w * 0.62
		K:text("BoardItem", nameW, rh * 0.6, dcf * CF(x0 + nameW / 2, yc, z), r[1], { fg = st.fg, glow = st.glow, align = "Left", font = st.font, d = 0.01 })
		if r[2] then
			K:text("BoardStyle", w * 0.24, rh * 0.44, dcf * CF(-w / 2 + 0.22 + rh * 0.62 + nameW + 0.1 + w * 0.12, yc, z), r[2], { fg = st.dim, glow = st.glow, align = "Left", font = st.font, d = 0.01 })
		end
		if r[3] and r[3] ~= "" then
			K:text("BoardABV", w * 0.1, rh * 0.48, dcf * CF(w / 2 - 0.22 - w * 0.17 - 0.1 - w * 0.05, yc, z), r[3], { fg = st.dim, glow = st.glow, align = "Right", font = st.font, d = 0.01 })
		end
		K:text("BoardPrice", w * 0.17, rh * 0.58, dcf * CF(w / 2 - 0.22 - w * 0.085, yc, z), r[4], { fg = acc, glow = st.glow, align = "Right", font = F.GothamBold, d = 0.01 })
	end
	if foot then
		K:text("BoardFoot", w * 0.9, footH, dcf * CF(0, -h / 2 + 0.12 + footH / 2, z), foot, { fg = st.dim, glow = st.glow, font = st.font, d = 0.01 })
	end
end

-- 안내판 ---------------------------------------------------------------------------------------------------
local function signPlate(K: any, dcf: CFrame, w: number, h: number, text: string, fg: Color3, bg: Color3, border: Color3?, font: Enum.Font?)
	if border then
		K:plate("SignBorder", w + 0.1, h + 0.1, 0.03, dcf, { c = border, m = M.SmoothPlastic })
	end
	K:text("SignPlate", w, h, dcf * CF(0, 0, 0.03), text, { fg = fg, bg = bg, d = 0.02, font = font or F.GothamBold })
end

-- 포스터 ---------------------------------------------------------------------------------------------------
local function poster(K: any, dcf: CFrame, w: number, h: number, kind: string, th: any)
	local b = 0.09
	local dep = 0.12
	local iw, ih = w - 2 * b - 0.12, h - 2 * b - 0.12
	local zA = dep * 0.7 + 0.004 -- 그림 앞면
	local function blk(c: Color3, x: number, y: number, bw: number, bh: number, z: number?)
		K:plate("PosterArt", iw * bw, ih * bh, 0.004, dcf * CF(-iw / 2 + iw * (x + bw / 2), -ih / 2 + ih * (y + bh / 2), zA + (z or 0)), { c = c, m = M.SmoothPlastic })
	end
	local function txt(t: string, x: number, y: number, tw: number, thh: number, fg: Color3, font: Enum.Font?)
		K:text("PosterText", iw * tw, ih * thh, dcf * CF(-iw / 2 + iw * x, -ih / 2 + ih * y, zA + 0.006), t, { fg = fg, font = font or F.GothamBlack, d = 0.004 })
	end
	local frameL = if kind == "cocktail" or kind == "deco" then L.goldMetal elseif kind == "rules" or kind == "map" then wood(90, 60, 40) else L.blackMetal
	local bg = rgb(30, 30, 34)
	if kind == "bridge" then
		bg = rgb(30, 28, 64)
	elseif kind == "ipa" then
		bg = rgb(58, 108, 62)
	elseif kind == "prost" then
		bg = rgb(238, 226, 196)
	elseif kind == "stout" then
		bg = rgb(20, 18, 18)
	elseif kind == "surf" then
		bg = rgb(40, 150, 160)
	elseif kind == "lotte" or kind == "lotte2" then
		bg = rgb(16, 30, 72)
	elseif kind == "cocktail" or kind == "deco" then
		bg = rgb(16, 16, 20)
	elseif kind == "map" then
		bg = rgb(214, 190, 150)
	elseif kind == "rules" then
		bg = rgb(34, 40, 38)
	elseif kind == "monk" then
		bg = rgb(70, 40, 26)
	elseif kind == "party" then
		bg = rgb(40, 10, 50)
	elseif kind == "sunsetp" then
		bg = rgb(250, 140, 70)
	end
	Props.frame(K, dcf, w, h, { frame = frameL, depth = dep, border = b, mat = { c = bg, m = M.SmoothPlastic } })
	local cream = rgb(255, 238, 206)
	if kind == "bridge" then
		blk(rgb(250, 150, 70), 0, 0.42, 1, 0.2)
		blk(rgb(236, 96, 112), 0, 0.3, 1, 0.12)
		blk(rgb(26, 40, 82), 0, 0, 1, 0.3)
		wdisc(K, "PosterSun", iw * 0.26, 0.004, dcf * CF(iw * 0.18, -ih / 2 + ih * 0.5, 0), zA + 0.002, { c = rgb(255, 214, 120) })
		-- 광안대교 (상판 · 주탑 2 · 케이블)
		local deckY = -ih / 2 + ih * 0.33
		K:plate("PosterBridge", iw, ih * 0.02, 0.004, dcf * CF(0, deckY, zA + 0.008), { c = rgb(30, 30, 40) })
		for _, tx in { -0.22, 0.22 } do
			local x = iw * tx
			K:plate("PosterBridge", iw * 0.025, ih * 0.22, 0.004, dcf * CF(x, deckY + ih * 0.11, zA + 0.008), { c = rgb(30, 30, 40) })
			for k = 1, 3 do
				for _, sd in { -1, 1 } do
					local a = (dcf * CF(x, deckY + ih * 0.21, zA + 0.01)).Position
					local bb = (dcf * CF(x + sd * iw * 0.075 * k, deckY, zA + 0.01)).Position
					K:seg("PosterCable", a, bb, 0.012, { c = rgb(40, 40, 54) })
				end
			end
		end
		txt("GWANGALLI\nBEER FEST 2026", 0.5, 0.82, 0.86, 0.26, cream)
		txt("10.23 – 10.25  ·  광안리 해변", 0.5, 0.12, 0.8, 0.06, cream, F.GothamMedium)
	elseif kind == "ipa" then
		blk(rgb(236, 210, 120), 0, 0.88, 1, 0.04)
		for k = 0, 2 do
			K:ell("PosterHop", V3(iw * (0.22 - k * 0.04), ih * 0.1, 0.02), dcf * CF(0, -ih * 0.02 - k * ih * 0.07, zA + 0.01), { c = rgb(150, 196, 90), m = M.SmoothPlastic })
		end
		K:ell("PosterHop", V3(iw * 0.12, ih * 0.05, 0.02), dcf * CF(iw * 0.1, ih * 0.06, zA + 0.012) * ANG(0, 0, 0.6), { c = rgb(90, 150, 70), m = M.SmoothPlastic })
		txt("IPA", 0.5, 0.72, 0.8, 0.2, rgb(250, 236, 180))
		txt("INDIA PALE ALE\n6.5% · 60 IBU · 광안리", 0.5, 0.14, 0.86, 0.12, rgb(250, 236, 180), F.GothamBold)
	elseif kind == "prost" then
		blk(rgb(180, 40, 36), 0, 0.9, 1, 0.1)
		blk(rgb(180, 40, 36), 0, 0, 1, 0.08)
		for _, sd in { -1, 1 } do
			local cx = iw * 0.13 * sd
			local rot = ANG(0, 0, -sd * 0.22)
			K:plate("PosterMug", iw * 0.2, ih * 0.22, 0.004, dcf * CF(cx, ih * 0.02, zA + 0.008) * rot, { c = rgb(236, 164, 50) })
			K:plate("PosterFoam", iw * 0.22, ih * 0.05, 0.004, dcf * CF(cx, ih * 0.02, zA + 0.012) * rot * CF(0, ih * 0.12, 0), { c = rgb(252, 250, 240) })
		end
		txt("PROST!", 0.5, 0.74, 0.8, 0.14, rgb(160, 34, 30))
		txt("건배 · CHEERS · 乾杯 · SALUD", 0.5, 0.18, 0.86, 0.07, rgb(60, 40, 30), F.GothamBold)
	elseif kind == "stout" then
		K:plate("PosterPint", iw * 0.3, ih * 0.4, 0.004, dcf * CF(0, -ih * 0.06, zA + 0.008), { c = rgb(44, 24, 16) })
		K:plate("PosterHead", iw * 0.32, ih * 0.07, 0.004, dcf * CF(0, ih * 0.17, zA + 0.01), { c = rgb(240, 224, 190) })
		txt("STOUT", 0.5, 0.84, 0.7, 0.13, rgb(240, 224, 190))
		txt("SMOOTH · ROASTY · DARK", 0.5, 0.13, 0.8, 0.06, rgb(200, 180, 150), F.GothamBold)
	elseif kind == "surf" then
		blk(rgb(244, 220, 170), 0, 0, 1, 0.16)
		local cols = { rgb(250, 120, 80), rgb(250, 230, 120), rgb(250, 250, 246) }
		for k = 1, 3 do
			K:ell("PosterBoard", V3(iw * 0.16, ih * 0.62, 0.02), dcf * CF(iw * (k - 2) * 0.24, -ih * 0.02, zA + 0.01) * ANG(0, 0, (k - 2) * 0.12), { c = cols[k], m = M.SmoothPlastic })
			K:plate("PosterStringer", iw * 0.01, ih * 0.55, 0.004, dcf * CF(iw * (k - 2) * 0.24, -ih * 0.02, zA + 0.024) * ANG(0, 0, (k - 2) * 0.12), { c = rgb(60, 60, 60) })
		end
		txt("SURF & BEER", 0.5, 0.86, 0.86, 0.12, rgb(255, 250, 236))
		txt("광안리 해변 · SINCE 2015", 0.5, 0.08, 0.8, 0.06, rgb(30, 80, 90), F.GothamBold)
	elseif kind == "lotte" or kind == "lotte2" then
		blk(rgb(200, 30, 40), 0, 0.82, 1, 0.05)
		blk(rgb(200, 30, 40), 0, 0.12, 1, 0.05)
		wdisc(K, "PosterBall", iw * 0.36, 0.004, dcf * CF(0, -ih * 0.04, 0), zA + 0.004, { c = rgb(246, 244, 236) })
		for _, sd in { -1, 1 } do
			K:plate("PosterStitch", iw * 0.012, ih * 0.16, 0.004, dcf * CF(sd * iw * 0.09, -ih * 0.04, zA + 0.01) * ANG(0, 0, sd * 0.25), { c = rgb(200, 30, 40) })
		end
		if kind == "lotte" then
			txt("최강 롯데", 0.5, 0.9, 0.8, 0.1, rgb(255, 255, 255))
			txt("부산 갈매기 · 사직 직관 중계", 0.5, 0.06, 0.86, 0.06, rgb(255, 255, 255), F.GothamBold)
		else
			txt("GAME DAY", 0.5, 0.9, 0.8, 0.1, rgb(255, 255, 255))
			txt("야구 보면서 생맥 한 잔", 0.5, 0.06, 0.86, 0.06, rgb(255, 255, 255), F.GothamBold)
		end
	elseif kind == "cocktail" or kind == "deco" then
		local gold = rgb(214, 176, 96)
		for k = -3, 3 do
			local a = (dcf * CF(0, -ih * 0.42, zA + 0.008)).Position
			local bb = (dcf * CF(iw * 0.13 * k, ih * 0.3, zA + 0.008)).Position
			K:seg("PosterDeco", a, bb, 0.014, { c = gold, m = M.Metal })
		end
		if kind == "cocktail" then
			local glassCF = dcf * CF(0, ih * 0.02, 0)
			local pts = { { -0.16, 0.12 }, { 0.16, 0.12 }, { 0, -0.06 }, { -0.16, 0.12 } }
			for i = 1, #pts - 1 do
				K:seg("PosterGlass", (glassCF * CF(pts[i][1] * iw * 1.6, pts[i][2] * ih, zA + 0.012)).Position, (glassCF * CF(pts[i + 1][1] * iw * 1.6, pts[i + 1][2] * ih, zA + 0.012)).Position, 0.02, { c = gold, m = M.Metal })
			end
			txt("COCKTAIL HOUR", 0.5, 0.86, 0.86, 0.1, gold, F.Oswald)
			txt("17:00 – 20:00  ·  2잔째 반값", 0.5, 0.1, 0.84, 0.06, rgb(236, 220, 190), F.GothamMedium)
		else
			txt("THE ART\nOF MIXING", 0.5, 0.78, 0.8, 0.2, gold, F.Oswald)
			txt("SHAKEN · STIRRED · SERVED", 0.5, 0.1, 0.84, 0.06, rgb(236, 220, 190), F.GothamMedium)
		end
	elseif kind == "map" then
		local coast = { { 0.05, 0.62 }, { 0.22, 0.55 }, { 0.36, 0.5 }, { 0.5, 0.4 }, { 0.62, 0.42 }, { 0.78, 0.3 }, { 0.95, 0.26 } }
		for i = 1, #coast - 1 do
			local a = dcf * CF(-iw / 2 + iw * coast[i][1], -ih / 2 + ih * coast[i][2], zA + 0.008)
			local bb = dcf * CF(-iw / 2 + iw * coast[i + 1][1], -ih / 2 + ih * coast[i + 1][2], zA + 0.008)
			K:seg("PosterCoast", a.Position, bb.Position, 0.03, { c = rgb(40, 90, 140) })
		end
		blk(rgb(120, 170, 200), 0, 0, 1, 0.24)
		for i, p in { { 0.3, 0.56, "서면" }, { 0.52, 0.47, "광안리" }, { 0.76, 0.38, "해운대" } } do
			wdisc(K, "PosterPin", iw * 0.05, 0.004, dcf * CF(-iw / 2 + iw * p[1], -ih / 2 + ih * p[2], 0), zA + 0.01, { c = if i == 2 then rgb(200, 40, 40) else rgb(60, 60, 60) })
			txt(p[3], p[1], p[2] + 0.06, 0.24, 0.05, rgb(50, 40, 30), F.GothamBold)
		end
		txt("BUSAN CRAFT\nBEER MAP", 0.5, 0.84, 0.86, 0.2, rgb(70, 46, 30))
	elseif kind == "rules" then
		txt("HOUSE RULES", 0.5, 0.88, 0.8, 0.09, rgb(250, 214, 110), F.PermanentMarker)
		txt("1. 건배는 크게!\n2. 과음은 금물\n3. 음주운전 NO\n4. 대리운전은 필수\n5. 다트는 선 뒤에서", 0.5, 0.42, 0.84, 0.66, rgb(236, 234, 222), F.PermanentMarker)
	elseif kind == "monk" then
		local gold = rgb(220, 180, 90)
		K:plate("PosterChalice", iw * 0.34, ih * 0.14, 0.004, dcf * CF(0, ih * 0.06, zA + 0.008), { c = gold })
		K:plate("PosterChalice", iw * 0.05, ih * 0.14, 0.004, dcf * CF(0, -ih * 0.07, zA + 0.008), { c = gold })
		K:plate("PosterChalice", iw * 0.22, ih * 0.03, 0.004, dcf * CF(0, -ih * 0.15, zA + 0.008), { c = gold })
		K:plate("PosterBeer", iw * 0.3, ih * 0.03, 0.004, dcf * CF(0, ih * 0.14, zA + 0.012), { c = rgb(250, 240, 210) })
		txt("ABBEY ALE", 0.5, 0.86, 0.8, 0.1, gold, F.Oswald)
		txt("BREWED IN GWANGALLI\nSINCE 2015", 0.5, 0.14, 0.86, 0.1, rgb(230, 210, 170), F.GothamBold)
	elseif kind == "party" then
		for k = 1, 12 do
			local cx, cy = rnd(k, 1), 0.2 + rnd(k, 2) * 0.55
			wdisc(K, "PosterDot", iw * (0.03 + rnd(k, 3) * 0.05), 0.004, dcf * CF(-iw / 2 + iw * cx, -ih / 2 + ih * cy, 0), zA + 0.004, { c = if k % 3 == 0 then rgb(255, 60, 200) elseif k % 3 == 1 then rgb(60, 220, 255) else rgb(255, 220, 60) })
		end
		txt("THURSDAY\nPARTY NIGHT", 0.5, 0.82, 0.86, 0.22, rgb(255, 240, 255))
		txt("EVERY THU · FRI · SAT  21:00", 0.5, 0.08, 0.86, 0.06, rgb(255, 200, 250), F.GothamBold)
	elseif kind == "sunsetp" then
		blk(rgb(236, 90, 110), 0, 0.3, 1, 0.22)
		blk(rgb(60, 40, 90), 0, 0, 1, 0.3)
		wdisc(K, "PosterSun", iw * 0.42, 0.004, dcf * CF(0, -ih / 2 + ih * 0.32, 0), zA + 0.002, { c = rgb(255, 214, 110) })
		blk(rgb(60, 40, 90), 0, 0, 1, 0.3, 0.004)
		K:seg("PosterPalm", (dcf * CF(iw * 0.3, -ih * 0.3, zA + 0.012)).Position, (dcf * CF(iw * 0.22, ih * 0.15, zA + 0.012)).Position, 0.03, { c = rgb(30, 20, 30) })
		for k = 0, 4 do
			K:ell("PosterFrond", V3(iw * 0.22, ih * 0.03, 0.01), dcf * CF(iw * 0.22, ih * 0.15, zA + 0.014) * ANG(0, 0, k * 0.8 - 1.6) * CF(iw * 0.1, 0, 0), { c = rgb(30, 20, 30) })
		end
		txt("SUNSET\nHAPPY HOUR", 0.5, 0.82, 0.86, 0.22, rgb(255, 250, 236))
		txt("매일 17 – 19시 생맥주 1+1", 0.5, 0.08, 0.86, 0.06, rgb(255, 230, 210), F.GothamBold)
	end
end

-- 1) 벽 마감 (윗벽 페인트 · 벽돌 포인트 벽) ---------------------------------------------------------------
-- 문틀 · 백바 같은 제외 구간만 빼고 넓은 판 몇 장으로 (작은 벽 물건은 판 앞에 그대로 보임)
local function wallRuns(V: any, wn: string, y0: number, y1: number, excl: { { number } }?): { { number } }
	local w = V.walls[wn]
	local cuts = {}
	for _, r in V.parts do
		local isDoor = r.door or r.name == "DoorCasing" or r.name == "DoorLeaf" or r.name == "DoorFrame" or r.name == "ShopWindow"
		if isDoor and r.max.Y > y0 + 0.05 and r.min.Y < y1 - 0.05 then
			local umin, umax, dmin = math.huge, -math.huge, math.huge
			for _, x in { r.min.X, r.max.X } do
				for _, z in { r.min.Z, r.max.Z } do
					local u, d = V:wallCoord(wn, V3(x, 0, z))
					umin = math.min(umin, u)
					umax = math.max(umax, u)
					dmin = math.min(dmin, d)
				end
			end
			if dmin < 0.6 then
				table.insert(cuts, { umin - 0.05, umax + 0.05 })
			end
		end
	end
	for _, e in excl or {} do
		table.insert(cuts, e)
	end
	table.sort(cuts, function(a, b)
		return a[1] < b[1]
	end)
	local out = {}
	local cur = w.a
	for _, c in cuts do
		if c[1] > cur + 0.3 then
			table.insert(out, { cur, math.min(c[1], w.b) })
		end
		cur = math.max(cur, c[2])
	end
	if cur < w.b - 0.3 then
		table.insert(out, { cur, w.b })
	end
	return out
end

local function upperWalls(c: any)
	local K, V, th, S = c.K, c.V, c.th, c.S
	local y0 = (if S.lower then (S.lower.h or 3.0) else 0.45) + 0.05
	local y1 = V.H - 0.03
	if y1 - y0 < 1 then
		return
	end
	-- 문 위아래로 나눔 (문 위 띠도 칠함)
	local breaks = { y0, y1 }
	for _, r in V.parts do
		if (r.name == "DoorCasing" or r.name == "DoorLeaf") and r.max.Y > y0 + 0.3 and r.max.Y < y1 - 0.3 then
			table.insert(breaks, r.max.Y + 0.02)
		end
	end
	table.sort(breaks)
	for _, wn in { "left", "right", "back" } do
		local look = if th.feature and th.feature.wall == wn then th.feature.look else th.paint
		if not look then
			continue
		end
		local excl = if wn == "back" then c.backExcl else nil
		K:free(function()
			for i = 1, #breaks - 1 do
				local ya, yb = breaks[i], breaks[i + 1]
				if yb - ya > 0.2 then
					for _, s in wallRuns(V, wn, ya, yb, excl) do
						K:plate("WallUpper", s[2] - s[1], yb - ya, 0.03, V:wall(wn, (s[1] + s[2]) / 2, (ya + yb) / 2, 0.012), look)
					end
				end
			end
		end)
	end
end

-- 2) 벤치 소파 (맵 Backrest + Seat + Base + Arm + Plinth 를 같은 자리 · 같은 좌판 높이로) -----------------------
local function banquettes(c: any)
	local K, V, th = c.K, c.V, c.th
	c.usedChairs = c.usedChairs or {}
	c.banq = {}
	for _, br in V.byName.Backrest or {} do
		if br.size.Y < 2.2 then
			continue
		end
		local alongZ = br.size.Z >= br.size.X
		local len = if alongZ then br.size.Z else br.size.X
		if len < 3 then
			continue
		end
		local seats = {}
		for _, ch in V.chairs do
			local sc = ch.seat.c
			local along = if alongZ then sc.Z else sc.X
			local lo = if alongZ then br.min.Z else br.min.X
			local hi = if alongZ then br.max.Z else br.max.X
			local perp = if alongZ then math.abs(sc.X - br.c.X) else math.abs(sc.Z - br.c.Z)
			if along > lo - 0.1 and along < hi + 0.1 and perp < 3.5 and ch.top < 2.4 then
				table.insert(seats, ch)
			end
		end
		if #seats == 0 then
			continue
		end
		local sc = seats[1].seat.c
		local face = if alongZ then V3(if sc.X > br.c.X then 1 else -1, 0, 0) else V3(0, 0, if sc.Z > br.c.Z then 1 else -1)
		local thick = if alongZ then br.size.X else br.size.Z
		local fpos = V3(br.c.X, 0, br.c.Z) + face * (thick / 2)
		local bcf = CFrame.lookAt(fpos, fpos - face)
		local top = seats[1].top
		local depth = 0
		for _, ch in seats do
			local lp = bcf:PointToObjectSpace(ch.seat.c)
			local half = (if alongZ then ch.seat.size.X else ch.seat.size.Z) / 2
			depth = math.max(depth, lp.Z + half)
		end
		local extras = {}
		local arms = {}
		for _, nm in { "Base", "Arm", "Plinth", "SeatBase", "SofaBase" } do
			for _, r in V.byName[nm] or {} do
				local lp = bcf:PointToObjectSpace(r.c)
				if math.abs(lp.X) < len / 2 + 0.8 and lp.Z > -0.3 and lp.Z < depth + 0.8 then
					table.insert(extras, r)
					if nm == "Arm" then
						table.insert(arms, r)
					end
				end
			end
		end
		local up = th.seat
		local dk = dim(up, 0.3)
		local frameL = th.dark
		local baseTop = top - 0.42
		K:free(function()
			-- 받침 (안쪽으로 들어간 걸레받이)
			K:box("BanqPlinth", V3(len - 0.3, 0.3, depth - 0.35), bcf * CF(0, 0.15, (depth - 0.35) / 2), L.black)
			-- 몸통 (가죽 스커트) + 앞 모서리 웰트
			K:box("BanqBase", V3(len - 0.06, baseTop - 0.3, depth - 0.04), bcf * CF(0, 0.3 + (baseTop - 0.3) / 2, (depth - 0.04) / 2), dk)
			K:cyl("BanqWelt", len - 0.12, 0.07, bcf * CF(0, baseTop - 0.03, depth - 0.05), dim(up, 0.5))
			-- 좌판 쿠션 (좌석마다, 윗면 = 원래 좌판 높이)
			for _, ch in seats do
				local lp = bcf:PointToObjectSpace(ch.seat.c)
				local sl = if alongZ then ch.seat.size.Z else ch.seat.size.X
				local cz = (depth - 0.08) / 2 + 0.02
				K:slab("BanqCushion", sl - 0.08, depth - 0.1, 0.42, 0.13, bcf * CF(lp.X, top - 0.21, cz), up)
				K:slab("BanqPiping", sl - 0.05, depth - 0.07, 0.035, 0.14, bcf * CF(lp.X, top - 0.07, cz), dim(up, 0.45))
			end
			-- 등받이: 뒤 셸 (원목) + 채널/버튼 터프팅 + 윗 롤 + 캡
			local bmin, bmax = br.min.Y, br.max.Y
			K:box("BanqBackShell", V3(len, bmax - bmin, thick - 0.32), bcf * CF(0, (bmin + bmax) / 2, -(thick - 0.32) / 2 - 0.32), frameL)
			K:box("BanqCap", V3(len, 0.08, thick), bcf * CF(0, bmax - 0.04, -thick / 2), frameL)
			local bh = bmax - top
			if th.seatStyle == "tuft" then
				K:box("BanqBackPad", V3(len - 0.1, bh - 0.32, 0.3), bcf * CF(0, top + 0.04 + (bh - 0.32) / 2, -0.15), up)
				local cols = math.max(2, math.floor(len / 0.85))
				for row = 1, 2 do
					for k = 1, cols do
						local x = -len / 2 + len * (k - 0.5) / cols + (if row == 2 then len / cols / 2 else 0)
						if x < len / 2 - 0.2 then
							K:ball("BanqButton", 0.08, bcf * CF(x, top + 0.04 + (bh - 0.32) * (if row == 1 then 0.36 else 0.72), 0.0), dk)
						end
					end
				end
			else
				local n = math.max(3, math.floor(len / 0.55))
				local cw = len / n
				for k = 1, n do
					K:vcyl("BanqChannel", bh - 0.36, cw * 1.04, bcf * CF(-len / 2 + cw * (k - 0.5), top + 0.04 + (bh - 0.36) / 2, -cw * 0.52), up)
				end
			end
			K:cyl("BanqTopRoll", len - 0.04, 0.34, bcf * CF(0, bmax - 0.08 - 0.17, -0.22), up)
			-- 팔걸이 (맵 Arm 자리 그대로)
			for _, a in arms do
				local lp = bcf:PointToObjectSpace(a.c)
				local aw = if alongZ then a.size.Z else a.size.X
				local ad = if alongZ then a.size.X else a.size.Z
				local ah = a.size.Y
				K:rbox("BanqArm", V3(ad, ah - 0.04, aw), math.min(0.16, aw / 2 - 0.02), bcf * CF(lp.X, a.c.Y - 0.02, lp.Z) * ANG(0, PI / 2, 0), up)
				K:box("BanqArmCap", V3(aw + 0.02, 0.06, ad + 0.02), bcf * CF(lp.X, a.max.Y - 0.03, lp.Z), frameL)
			end
		end)
		-- 숨김 + 예약
		hideRec(K, br)
		local mn, mx = br.min, br.max
		for _, ch in seats do
			c.usedChairs[ch] = true
			for _, r in ch.parts do
				hideRec(K, r)
				mn, mx = mn:Min(r.min), mx:Max(r.max)
			end
		end
		for _, r in extras do
			hideRec(K, r)
			mn, mx = mn:Min(r.min), mx:Max(r.max)
		end
		K:reserve(V3(mn.X - 0.2, 0, mn.Z - 0.2), V3(mx.X + 0.2, mx.Y, mx.Z + 0.2), "banquette")
		local wn = if alongZ then (if face.X < 0 then "right" else "left") else (if face.Z > 0 then "back" else "front")
		table.insert(c.banq, { wall = wn, center = (mn + mx) / 2, len = len, top = br.max.Y, alongZ = alongZ, min = mn, max = mx })
	end
end

-- 3) 나머지 의자 (Common.chairs 와 같은 방식, 테마 스타일)
local function chairsOver(c: any)
	local K, V, th = c.K, c.V, c.th
	local used = c.usedChairs or {}
	local cs = th.chair or { style = "bentwood", frame = th.dark, seat = th.mid }
	local n = #V.chairs
	local detail = K.detail
	if n * 30 > K.maxParts * 0.4 then
		detail = if n * 22 > K.maxParts * 0.4 then "low" else "mid"
	end
	for _, ch in V.chairs do
		if used[ch] then
			continue
		end
		local s = ch.seat
		if s.part:IsA("Seat") and s.part.Transparency >= 0.99 then
			continue
		end
		local w = math.max(1.1, math.min(2.2, math.min(s.size.X, s.size.Z) + 0.05))
		local backH = 1.8
		if ch.back then
			backH = math.clamp(ch.back.max.Y - ch.top, 1.0, 3.2)
		end
		local o = table.clone(cs)
		o.seatTop = ch.top
		o.w = w
		o.d = w
		o.backH = o.backH or backH
		o.detail = if detail == "high" then o.detail else detail
		local p = V3(s.c.X, 0, s.c.Z)
		local f: Vector3 = ch.face
		K:free(function()
			Props.chair(K, CFrame.lookAt(p, p - f), o)
		end)
		for _, r in ch.parts do
			hideRec(K, r)
		end
		K:reserve(V3(s.min.X - 0.3, 0, s.min.Z - 0.3), V3(s.max.X + 0.3, ch.top + backH, s.max.Z + 0.3), "chair")
	end
end

-- 4) 백바 (맵 MirrorBack · BarShelf · ShelfGlow · Bottle · BackBarCabinet 자리) ---------------------------------
local function backCabinet(K: any, cab: any, th: any, c: any)
	local mn, mx = cab.min, cab.max
	local w, h, d = mx.X - mn.X, mx.Y - mn.Y, mx.Z - mn.Z
	local base = CF((mn.X + mx.X) / 2, 0, (mn.Z + mx.Z) / 2)
	local detail = K.detail
	K:free(function()
		K:box("BackCabTop", V3(w, 0.12, d), base * CF(0, h - 0.06, 0), th.cabTop)
		K:box("BackCabKick", V3(w - 0.06, 0.34, d - 0.12), base * CF(0, 0.17, -0.08), L.black)
		local n = math.max(2, math.floor(w / 1.9 + 0.5))
		local dw = w / n
		local bh = h - 0.12 - 0.34
		local coolers: { [number]: boolean } = {}
		if th.key ~= "fuzzy" and n >= 3 then
			local mid = math.floor((n + 1) / 2)
			coolers[mid] = true
			if n >= 5 then
				coolers[mid + 1] = true
			end
		end
		for i = 1, n do
			local x = -w / 2 + dw * (i - 0.5)
			local yc = 0.34 + bh / 2
			local fz = d / 2
			if coolers[i] then
				-- 유리문 맥주 쿨러: 뒤 몸통 + 밝은 안쪽 + 선반 2 + 병 · 캔 + 검은 문틀 + 유리
				K:box("BackCoolerBody", V3(dw, bh, d - 0.62), base * CF(x, yc, -0.31), th.dark)
				K:box("BackCoolerInner", V3(dw - 0.2, bh - 0.2, 0.04), base * CF(x, yc, fz - 0.6), L.of(232, 238, 242))
				local lamp = K:box("BackCoolerLED", V3(dw - 0.3, 0.04, 0.05), base * CF(x, 0.34 + bh - 0.16, fz - 0.2), L.lampCool)
				for k = 0, 1 do
					local sy = 0.34 + 0.12 + k * (bh - 0.25) / 2
					K:box("BackCoolerShelf", V3(dw - 0.2, 0.03, 0.5), base * CF(x, sy, fz - 0.33), L.of(200, 204, 208, M.Metal))
					local m = math.max(2, math.floor((dw - 0.3) / 0.3))
					for j = 1, m do
						local bx = x - (dw - 0.3) / 2 + (dw - 0.3) * (j - 0.5) / m
						local pc = base * CF(bx, sy + 0.015, fz - 0.33)
						if (j + k) % 2 == 0 then
							beerBottle(K, pc, if j % 3 == 0 then rgb(40, 96, 56) else rgb(110, 60, 24), LABELS[(j + k) % #LABELS + 1], detail)
						else
							beerCan(K, pc, (th.taps[(j % #th.taps) + 1] :: any)[7] or rgb(200, 60, 40), rgb(250, 250, 246), detail)
						end
					end
				end
				K:plate("BackCoolerFrame", dw - 0.06, bh - 0.04, 0.06, CF(base * V3(x, yc, fz)), L.of(26, 26, 28, M.Metal))
				K:box("BackCoolerGlass", V3(dw - 0.3, bh - 0.3, 0.03), base * CF(x, yc, fz + 0.075), { c = rgb(210, 230, 236), m = M.Glass, t = 0.72, r = 0.15 })
				K:box("BackCoolerHandle", V3(0.06, bh * 0.5, 0.08), base * CF(x + dw / 2 - 0.2, yc, fz + 0.12), L.chrome)
				if c then
					table.insert(c.coolLamps, lamp)
				end
			else
				K:box("BackCabBay", V3(dw, bh, d - 0.02), base * CF(x, yc, -0.01), th.dark)
				local dc = CF(base * V3(x, yc, fz))
				K:plate("BackCabDoor", dw - 0.08, bh - 0.08, 0.04, dc, th.mid)
				if detail ~= "low" then
					K:plate("BackCabPanel", dw - 0.46, bh - 0.5, 0.03, dc * CF(0, 0, 0.04), dim(th.mid, 0.18))
				end
				K:ball("BackCabKnob", 0.12, dc * CF(if i % 2 == 0 then -dw / 2 + 0.24 else dw / 2 - 0.24, bh * 0.28, 0.1), th.trim)
			end
		end
	end)
end

local function backBar(c: any)
	local K, V, th = c.K, c.V, c.th
	local mir = V:first("MirrorBack")
	local shelves = {}
	for _, r in V.byName.BarShelf or {} do
		table.insert(shelves, r)
	end
	local cab = V:first("BackBarCabinet")
	c.coolLamps = {}
	if not mir and #shelves == 0 then
		if cab then
			hideRec(K, cab)
			backCabinet(K, cab, th, c)
		end
		return
	end
	local ref = mir or shelves[1]
	if ref.min.Z - V.z0 > 0.7 then
		return -- 뒷벽 백바만
	end
	local x0, x1 = ref.min.X, ref.max.X
	for _, r in shelves do
		x0 = math.min(x0, r.min.X)
		x1 = math.max(x1, r.max.X)
	end
	table.sort(shelves, function(a, b)
		return a.max.Y < b.max.Y
	end)
	local yb = if cab then cab.max.Y else (if shelves[1] then shelves[1].min.Y - 0.4 else 3.0)
	local yTop = if mir then mir.max.Y else shelves[#shelves].max.Y + 1.6
	yTop = math.min(yTop, V.H - 0.6)
	local zw = V.z0
	local W = x1 - x0
	local cx = (x0 + x1) / 2
	local seed = c.seed
	local detail = K.detail
	-- 맵 장식 숨김
	for _, r in V.byName.Bottle or {} do
		if r.c.X >= x0 - 0.6 and r.c.X <= x1 + 0.6 and r.c.Z < zw + 1.8 then
			hideRec(K, r)
		end
	end
	for _, nm in { "MirrorBack", "BarShelf", "ShelfGlow" } do
		for _, r in V.byName[nm] or {} do
			hideRec(K, r)
		end
	end
	local backCx = (V.x0 + V.x1) / 2
	c.backExcl = { { x0 - backCx - 0.05, x1 - backCx + 0.05 } }
	claim(K, "back", x0 - backCx - 0.3, x1 - backCx + 0.3, 0, V.H)
	if cab then
		hideRec(K, cab)
		backCabinet(K, cab, th, c)
		claim(K, "back", cab.min.X - backCx - 0.3, cab.max.X - backCx + 0.3, 0, cab.max.Y + 0.4)
	end
	local nb = math.max(1, math.floor(W / 3.0 + 0.5))
	local bw = W / nb
	local crownH = math.min(0.62, V.H - yTop - 0.04)
	K:free(function()
		-- 스모크 거울
		K:box("BackBarMirror", V3(W - 0.06, yTop - yb, 0.04), CF(cx, (yb + yTop) / 2, zw + 0.03), th.mirror)
		-- 기둥 (원목 + 황동 띠)
		for i = 0, nb do
			local x = math.clamp(x0 + bw * i, x0 + 0.16, x1 - 0.16)
			K:box("BackBarPost", V3(0.32, yTop - yb, 0.96), CF(x, (yb + yTop) / 2, zw + 0.48), th.dark)
			K:box("BackBarPostTrim", V3(0.06, yTop - yb - 0.3, 0.02), CF(x, (yb + yTop) / 2, zw + 0.97), th.trim)
		end
		-- 크라운 + 상호 (뒤에서 빛나는 글자)
		if crownH > 0.3 then
			K:box("BackBarCrown", V3(W + 0.36, crownH, 1.08), CF(cx, yTop + crownH / 2, zw + 0.54), th.dark)
			K:box("BackBarCrownTrim", V3(W + 0.4, 0.05, 0.04), CF(cx, yTop + 0.03, zw + 1.1), th.trim)
			K:text("BackBarCrownSign", math.min(W * 0.8, 12), crownH * 0.62, CF(cx, yTop + crownH / 2 + 0.02, zw + 1.08), th.crown or th.brand, { fg = rgb(255, 222, 160), glow = 1.4, font = th.font or F.Oswald, d = 0.02 })
		end
		local lamp = K:box("BackBarLamp", V3(W - 0.5, 0.04, 0.08), CF(cx, yTop - 0.03, zw + 0.86), L.neon(th.shelfLED))
		K:light(lamp, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 10, Brightness = 1.4, Angle = 120, Color = th.shelfLED })
		-- 선반 + 앞 레일 + LED + 술병
		local cap = { L.goldMetal, L.black, L.of(160, 30, 30), L.chrome, wood(120, 80, 50) }
		local mix = th.bottleMix or { "square", "round", "wine" }
		local idx = 0
		for si, r in shelves do
			local y = r.max.Y
			local clear = (if shelves[si + 1] then shelves[si + 1].min.Y else yTop) - y - 0.12
			for bi = 1, nb do
				local bx0 = x0 + bw * (bi - 1) + 0.2
				local bx1 = x0 + bw * bi - 0.2
				local bcx = (bx0 + bx1) / 2
				local sw = bx1 - bx0
				K:box("BackBarShelf", V3(sw + 0.04, 0.07, 0.86), CF(bcx, y - 0.035, zw + 0.06 + 0.43), { c = rgb(200, 226, 230), m = M.Glass, t = 0.35, r = 0.1 })
				K:cyl("BackBarRail", sw + 0.04, 0.05, CF(bcx, y + 0.24, zw + 0.86), th.trim)
				K:box("BackBarLED", V3(sw - 0.1, 0.03, 0.04), CF(bcx, y - 0.09, zw + 0.82), L.neon(th.shelfLED))
				local m = math.max(1, math.floor(sw / (if K.detail == "high" then 0.56 else 0.7)))
				for j = 1, m do
					idx += 1
					local bx = bx0 + sw * (j - 0.5) / m + (rnd(seed, idx) - 0.5) * 0.06
					local h = math.clamp(0.9 + rnd(seed, idx + 50) * 0.45, 0.6, clear)
					local kind = mix[(idx + seed) % #mix + 1]
					local gc = GLASS[(math.floor(rnd(seed, idx + 99) * 97)) % #GLASS + 1]
					bottle(K, CF(bx, y, zw + 0.42 + (j % 2) * 0.12), h, kind, gc, LABELS[(idx * 7 + seed) % #LABELS + 1], cap[(idx + si) % #cap + 1], detail)
				end
			end
		end
		-- 맨 아래 단 (하부장 위 · 첫 선반 아래) 위로 비추는 LED
		if shelves[1] and shelves[1].min.Y - yb > 0.2 then
			K:box("BackBarUplight", V3(W - 0.5, 0.03, 0.05), CF(cx, yb + 0.03, zw + 0.2), L.neon(th.shelfLED))
		end
	end)
	c.backBar = { x0 = x0, x1 = x1, yTop = yTop }
end

-- 4b) 카페형 매장 (WallShelf + Jar): 병 판매 선반으로
local function shelfBar(c: any)
	local K, V, th = c.K, c.V, c.th
	if c.backBar or V:has("TapPost") > 0 then
		return
	end
	local sh = V:first("WallShelf")
	if not sh then
		return
	end
	for _, r in V.byName.Jar or {} do
		if r.min.Y >= sh.max.Y - 0.2 and r.min.Y < sh.max.Y + 1.5 then
			hideRec(K, r)
		end
	end
	local y = sh.max.Y
	local zf = (sh.min.Z + sh.max.Z) / 2
	local cap = { L.goldMetal, L.black, L.chrome }
	local mix = th.bottleMix or { "square", "round" }
	local n = math.floor((sh.size.X - 0.4) / 0.5)
	for i = 1, n do
		local x = sh.min.X + 0.2 + (sh.size.X - 0.4) * (i - 0.5) / n
		local h = 0.85 + rnd(c.seed, i) * 0.35
		if clearAt(K, CF(x, y + h / 2, zf), V3(0.45, h, 0.45)) then
			bottle(K, CF(x, y, zf), h, mix[(i + c.seed) % #mix + 1], GLASS[(i * 5 + c.seed) % #GLASS + 1], LABELS[i % #LABELS + 1], cap[i % #cap + 1], K.detail)
		end
	end
	K:free(function()
		Props.ledStrip(K, V3(sh.min.X + 0.2, sh.min.Y - 0.03, sh.max.Z - 0.1), V3(sh.max.X - 0.2, sh.min.Y - 0.03, sh.max.Z - 0.1), th.shelfLED)
	end)
end

-- 5) 탭 타워 (맵 TapPost · TapBar · TapHandle · DripTray 와 같은 자리 · 같은 윗면) --------------------------------
local function tapTower(c: any)
	local K, V, th = c.K, c.V, c.th
	local bar = V:first("TapBar")
	local post = V:first("TapPost")
	if not bar or not post then
		return
	end
	local tray = nil
	for _, r in V.byName.DripTray or {} do
		if (r.c - bar.c).Magnitude < 2.5 then
			tray = r
		end
	end
	local handles = {}
	for _, r in V.byName.TapHandle or {} do
		if (r.c - bar.c).Magnitude < 3 then
			table.insert(handles, r)
		end
	end
	local alongX = bar.size.X >= bar.size.Z
	local perp = if alongX then V3(0, 0, 1) else V3(1, 0, 0)
	local zA = perp
	if tray then
		zA = if (tray.c - bar.c):Dot(perp) >= 0 then perp else -perp
	end
	local xA = Vector3.yAxis:Cross(zA)
	local y0 = post.min.Y
	local tc = CFrame.fromMatrix(V3(bar.c.X, y0, bar.c.Z), xA, Vector3.yAxis, zA)
	local len = if alongX then bar.size.X else bar.size.Z
	local fy = bar.c.Y - y0
	local pp = tc:PointToObjectSpace(post.c)
	hideRec(K, bar)
	hideRec(K, post)
	for _, h in handles do
		hideRec(K, h)
	end
	if tray then
		hideRec(K, tray)
	end
	local chrome = L.chrome
	local labels = {}
	K:free(function()
		K:disc("TapFlange", 0.58, 0.05, tc * CF(pp.X, 0.025, pp.Z), chrome)
		K:vcyl("TapColumn", fy - 0.06, 0.27, tc * CF(pp.X, (fy - 0.06) / 2 + 0.04, pp.Z), chrome)
		K:ball("TapElbow", 0.31, tc * CF(pp.X, fy, 0), chrome)
		K:cyl("TapCrossbar", len - 0.3, 0.27, tc * CF(0, fy, 0), chrome)
		K:cyl("TapFrost", len - 0.6, 0.3, tc * CF(0, fy, 0), { c = rgb(238, 244, 248), m = M.Glass, t = 0.5, r = 0.05 })
		for _, sd in { -1, 1 } do
			K:ball("TapEnd", 0.29, tc * CF(sd * (len / 2 - 0.15), fy, 0), chrome)
		end
		-- 탭 브랜드 띠 (크로스바 앞 중앙)
		local _, lab = K:text("TapBadge", math.min(1.2, len * 0.5), 0.2, tc * CF(0, fy + 0.02, 0.16), th.brand, { fg = rgb(30, 30, 30), bg = rgb(240, 232, 214), d = 0.01, font = F.GothamBlack })
		local _ = lab
		for i, h in handles do
			local hp = tc:PointToObjectSpace(h.c)
			local tap = th.taps[(i - 1) % #th.taps + 1]
			local hc = tap[7] or tap[5]
			-- 파우셋 (앞으로 나온 몸통 + 아래 주둥이)
			K:cyl("TapShank", 0.22, 0.09, tc * CF(hp.X, fy - 0.02, 0.16) * ANG(0, PI / 2, 0), chrome)
			K:cyl("TapFaucet", 0.26, 0.15, tc * CF(hp.X, fy - 0.02, 0.36) * ANG(0, PI / 2, 0), chrome)
			K:vcyl("TapSpout", 0.2, 0.07, tc * CF(hp.X, fy - 0.17, 0.44), chrome)
			-- 핸들 (맵 핸들과 같은 높이 · 자리)
			local hb, ht = h.min.Y - y0, h.max.Y - y0
			local hz = hp.Z
			K:vcyl("TapFerrule", 0.12, 0.12, tc * CF(hp.X, hb + 0.06, hz), chrome)
			K:vcyl("TapShaft", 0.2, 0.13, tc * CF(hp.X, hb + 0.22, hz), L.black)
			local bodyH = ht - hb - 0.34
			K:box("TapHandleBody", V3(0.2, bodyH, 0.12), tc * CF(hp.X, hb + 0.32 + bodyH / 2, hz), { c = hc, m = M.SmoothPlastic })
			K:box("TapHandleCap", V3(0.22, 0.03, 0.14), tc * CF(hp.X, ht - 0.015, hz), L.black)
			local _, tl = K:text("TapHandleLabel", 0.17, bodyH * 0.62, tc * CF(hp.X, hb + 0.32 + bodyH * 0.55, hz + 0.06), tap[6] or "ALE", { fg = if hc.R + hc.G + hc.B > 1.8 then rgb(30, 30, 30) else rgb(250, 250, 246), font = F.GothamBlack, d = 0.005 })
			table.insert(labels, tl)
		end
		if tray then
			local tp = tc:PointToObjectSpace(tray.c)
			local tw = if alongX then tray.size.X else tray.size.Z
			local td = if alongX then tray.size.Z else tray.size.X
			local tH = tray.size.Y
			K:box("TapTray", V3(tw, tH, td), tc * CF(tp.X, tray.c.Y - y0, tp.Z), L.steel)
			K:box("TapTrayWell", V3(tw - 0.12, 0.012, td - 0.12), tc * CF(tp.X, tray.max.Y - y0 - 0.008, tp.Z), L.of(40, 40, 42, M.Metal))
			local nbar = math.max(3, math.floor(td / 0.12))
			for k = 1, nbar do
				K:box("TapTrayGrate", V3(tw - 0.14, 0.012, 0.035), tc * CF(tp.X, tray.max.Y - y0 - 0.004, tp.Z - td / 2 + 0.06 + (td - 0.12) * (k - 0.5) / nbar), L.chrome)
			end
		end
	end)
	c.tap = { cf = tc, y = y0, len = len }
end

-- 6) 발판 레일 (FootRail 자리) ------------------------------------------------------------------------------
local function footRail(c: any)
	local K, V, th = c.K, c.V, c.th
	for _, r in V.byName.FootRail or {} do
		local alongX = r.size.X >= r.size.Z
		local len = if alongX then r.size.X else r.size.Z
		-- 레일이 붙은 카운터 앞면
		local g = nil
		for _, cg in V.counters do
			if r.c.X > cg.min.X - 1 and r.c.X < cg.max.X + 1 and r.c.Z > cg.min.Z - 2.5 and r.c.Z < cg.max.Z + 2.5 then
				g = cg
			end
		end
		local face: number? = nil
		local dir = 1
		if g then
			local body = g.body or g
			if alongX then
				if r.c.Z > body.max.Z then
					face, dir = body.max.Z, -1
				else
					face, dir = body.min.Z, 1
				end
			else
				if r.c.X > body.max.X then
					face, dir = body.max.X, -1
				else
					face, dir = body.min.X, 1
				end
			end
		end
		hideRec(K, r)
		K:free(function()
			local rot = if alongX then CFrame.new() else ANG(0, PI / 2, 0)
			local cc = CF(r.c) * rot
			K:cyl("FootRail", len, 0.17, cc, th.trim)
			for _, sd in { -1, 1 } do
				K:ball("FootRailEnd", 0.2, cc * CF(sd * len / 2, 0, 0), th.trim)
			end
			if face then
				local n = math.max(2, math.floor(len / 2.6) + 1)
				for i = 0, n - 1 do
					local u = -len / 2 + 0.35 + (len - 0.7) * i / (n - 1)
					local p = cc * V3(u, 0, 0)
					local q = if alongX then V3(p.X, p.Y, (face :: number) - dir * 0.04) else V3((face :: number) - dir * 0.04, p.Y, p.Z)
					K:seg("FootRailBracket", p, q, 0.07, th.trim)
					local fcf = if alongX then CF(q) else CF(q) * ANG(0, PI / 2, 0)
					K:box("FootRailFlange", V3(0.22, 0.22, 0.04), fcf, th.trim)
				end
			end
		end)
	end
end

-- 7) 스포츠 TV (맵 TV 자리) + 채널 상호작용 ---------------------------------------------------------------
local function tvSet(c: any)
	local K, V, th = c.K, c.V, c.th
	local tv = V:first("TV")
	if not tv then
		return
	end
	local wn: string? = nil
	if tv.min.Z - V.z0 < 0.6 then
		wn = "back"
	elseif V.x1 - tv.max.X < 0.6 then
		wn = "right"
	elseif tv.min.X - V.x0 < 0.6 then
		wn = "left"
	end
	if not wn then
		return
	end
	local u = (V:wallCoord(wn, tv.c))
	local w = if wn == "back" then tv.size.X else tv.size.Z
	local h = tv.size.Y
	hideRec(K, tv)
	for _, r in V.byName.TVScreen or {} do
		hideRec(K, r)
	end
	claim(K, wn, u - w / 2 - 0.3, u + w / 2 + 0.3, tv.min.Y - 1.0, tv.max.Y + 0.2)
	local dcf = V:wall(wn, u, tv.c.Y, 0)
	local sw, sh = w - 0.14, h - 0.14
	local z = 0.24
	K.freeDepth += 1 -- 맵 TV 와 같은 자리 덮어씌우기
	K:plate("TVMount", w * 0.3, h * 0.3, 0.1, dcf, L.blackMetal)
	K:plate("TVBody", w, h, 0.14, dcf * CF(0, 0, 0.1), L.of(18, 18, 20))
	local scr, scrLab = K:text("TVScreen", sw, sh, dcf * CF(0, 0, z), "", { bg = rgb(36, 118, 54), glow = 1.0, d = 0.01 })
	local dirt = K:text("TVField", sh * 0.42, sh * 0.42, dcf * CF(0, -sh * 0.2, z + 0.01) * ANG(0, 0, PI / 4), "", { bg = rgb(170, 110, 64), glow = 1.0, d = 0.005 })
	local stripes = {}
	for k = 1, 3 do
		local p = K:text("TVStripe", sw / 7, sh, dcf * CF(-sw / 2 + sw * (2 * k - 0.5) / 7, 0, z + 0.008), "", { bg = rgb(44, 136, 60), glow = 1.0, d = 0.004 })
		table.insert(stripes, p)
	end
	local _, bug = K:text("TVBug", sw * 0.4, sh * 0.17, dcf * CF(-sw * 0.27, sh * 0.37, z + 0.014), "", { fg = rgb(255, 255, 255), bg = rgb(16, 28, 70), glow = 1.1, d = 0.005, font = F.GothamBold })
	local live, liveLab = K:text("TVLive", sw * 0.1, sh * 0.08, dcf * CF(sw * 0.4, sh * 0.41, z + 0.014), "● LIVE", { fg = rgb(255, 255, 255), bg = rgb(210, 30, 40), glow = 1.2, d = 0.005, font = F.GothamBlack })
	local _, tick = K:text("TVTicker", sw - 0.1, sh * 0.09, dcf * CF(0, -sh / 2 + sh * 0.06, z + 0.014), "", { fg = rgb(255, 230, 90), bg = rgb(10, 10, 14), glow = 1.1, d = 0.005, font = F.GothamMedium })
	local _, logo = K:text("TVLogo", sw * 0.12, sh * 0.08, dcf * CF(sw * 0.4, -sh * 0.3, z + 0.014), "SPORTS", { fg = rgb(255, 255, 255), glow = 1.1, d = 0.004, font = F.GothamBlack })
	local tvBody = K:plate("TVLogoBadge", 0.36, 0.05, 0.01, dcf * CF(0, -h / 2 + 0.05, 0.24), L.chrome)
	K.freeDepth -= 1
	-- 사운드바 (상호작용 손잡이; 문 앞 keep 에 걸리면 생략하고 TV 에 붙임)
	local bar = tvBody
	if clearAt(K, dcf * CF(0, -h / 2 - 0.36, 0.2), V3(w * 0.66, 0.42, 0.34)) then
		bar = K:box("TVSoundbar", V3(w * 0.66, 0.26, 0.34), dcf * CF(0, -h / 2 - 0.42, 0.19), L.of(26, 26, 28))
		K:box("TVSoundbarGrille", V3(w * 0.62, 0.18, 0.02), dcf * CF(0, -h / 2 - 0.42, 0.36), L.of(50, 50, 54, M.Fabric))
		K:box("TVSoundbarLED", V3(0.08, 0.04, 0.02), dcf * CF(w * 0.28, -h / 2 - 0.5, 0.37), L.ledGreen)
		K:seg("TVCable", (dcf * CF(w * 0.2, -h / 2, 0.08)).Position, (dcf * CF(w * 0.2, -h / 2 - 0.3, 0.08)).Position, 0.04, L.black)
	end
	local channels = {
		{ bg = rgb(36, 118, 54), dirt = true, stripes = false, live = true, logo = "SPORTS 1", bug = "롯데  3 : 2  두산\n▲ 7회  2사 1 · 2루", ticker = "KBO 리그 생중계 · 사직야구장 22,990석 매진" },
		{ bg = rgb(34, 124, 52), dirt = false, stripes = true, live = true, logo = "SPORTS 2", bug = "토트넘  1 - 0  첼시\n후반  72:14", ticker = "프리미어리그 9라운드 · 하이라이트는 경기 후 바로" },
		{ bg = rgb(16, 22, 60), dirt = false, stripes = false, live = false, logo = "BUSAN TV", bug = "광안리 M 드론 라이트쇼\n매주 토요일 20:00", ticker = "광안리해수욕장 · 드론 1,500대 · 오늘 밤 날씨 맑음" },
		{ bg = rgb(60, 24, 70), dirt = false, stripes = false, live = false, logo = "MUSIC", bug = "NOW PLAYING\n광안리 여름밤 플레이리스트", ticker = "♪ City Pop · Indie · K-Ballad  ·  신청곡은 바텐더에게" },
		{ bg = rgb(6, 6, 8), dirt = false, stripes = false, live = false, logo = "", bug = "", ticker = "", off = true },
	}
	local cur = 1
	local function apply(i: number)
		cur = i
		local ch = channels[i]
		scrLab.BackgroundColor3 = ch.bg
		dirt.Transparency = if ch.dirt then 0 else 1
		for _, p in dirt:GetChildren() do
			if p:IsA("SurfaceGui") then
				p.Enabled = ch.dirt
			end
		end
		for _, s in stripes do
			for _, p in s:GetChildren() do
				if p:IsA("SurfaceGui") then
					p.Enabled = ch.stripes
				end
			end
		end
		bug.Text = ch.bug
		bug.BackgroundTransparency = if ch.off then 1 else 0
		tick.Text = ch.ticker
		tick.BackgroundTransparency = if ch.off then 1 else 0
		logo.Text = ch.logo
		for _, p in live:GetChildren() do
			if p:IsA("SurfaceGui") then
				p.Enabled = ch.live
			end
		end
	end
	apply(1)
	Interact.cycle(K, bar, channels, {
		action = "채널 바꾸기",
		object = "스포츠 TV",
		on = function(i: number)
			apply(i)
		end,
	})
	-- 경기 진행 (볼카운트 · 시간) + LIVE 깜빡임
	local counts = { "B 1  S 0  O 2", "B 2  S 1  O 2", "B 3  S 2  O 2", "B 0  S 0  O 0" }
	local mins = { "72:14", "73:40", "75:02", "77:31" }
	local last = -1
	Interact.anim(K, function(t: number)
		local ch = channels[cur]
		if ch.live then
			liveLab.TextTransparency = if math.floor(t * 1.2) % 2 == 0 then 0 else 0.6
		end
		local k = math.floor(t / 6) % 4 + 1
		if k ~= last then
			last = k
			if cur == 1 then
				bug.Text = "롯데  3 : 2  두산\n▲ 7회  " .. counts[k]
			elseif cur == 2 then
				bug.Text = "토트넘  1 - 0  첼시\n후반  " .. mins[k]
			end
		end
	end)
	c.tv = { wall = wn, u = u, w = w }
end

-- 8) 탭 리스트 보드 + (뒷벽이면) 아래 맥주 쿨러 · 잔 선반 ---------------------------------------------------
local function tapBoard(c: any)
	local K, V, th = c.K, c.V, c.th
	local g = V.counters[1]
	local near = if g then (g.min + g.max) / 2 else V3(0, 0, V.z0)
	local y0, y1 = 4.5, math.min(V.H - 0.8, 9.0)
	local side = if near.X < 0 then "left" else "right"
	local other = if side == "left" then "right" else "left"
	local wn, u, w = findWall(K, { "back", side, other }, 4.4, 7.6, y0, y1, near, 0.8)
	if not wn or not u or not w then
		return
	end
	local h = y1 - y0 - 0.4
	local dcf = V:wall(wn, u, (y0 + y1) / 2, 0.06)
	local rows = {}
	for _, t in th.taps do
		table.insert(rows, { t[1], t[2], t[3], t[4], t[5] })
	end
	listBoard(K, dcf, w - 0.4, h, th.board, th.boardTitle, th.boardSub, rows, th.boardFoot, nil)
	-- 보드 조명 (위에서 비추는 갤러리 램프 2)
	for _, sx in { -0.3, 0.3 } do
		local base = dcf * CF((w - 0.4) * sx, h / 2 + 0.3, -0.06)
		K:box("BoardLampMount", V3(0.18, 0.18, 0.06), base * CF(0, 0, 0.03), L.blackMetal)
		K:box("BoardLampArm", V3(0.06, 0.06, 0.62), base * CF(0, 0, 0.33), L.blackMetal)
		K:cyl("BoardLampHead", 0.5, 0.18, base * CF(0, -0.06, 0.66), L.blackMetal)
		K:box("BoardLampLens", V3(0.44, 0.02, 0.08), base * CF(0, -0.16, 0.66), L.lampWarm)
	end
	c.board = { wall = wn, u = u, w = w }
	-- 뒷벽 카운터 뒤면: 아래 언더카운터 쿨러 + 잔 선반 (깊이 1.0)
	if wn == "back" and g then
		local bw = math.min(w - 0.6, 6.4)
		local size = V3(bw, 3.0, 1.0)
		local pcf = V:wall("back", u, 0, 0.5 + 0.06)
		local mn, mx = laabb(pcf * CF(0, 1.5, 0), size)
		if mapClear(V, mn, mx) and K:spot(pcf, size, 0.02, "cooler") then
			claim(K, "back", u - bw / 2 - 0.1, u + bw / 2 + 0.1, 0, 3.1)
			local nd = math.max(2, math.floor(bw / 2.0 + 0.5))
			local dw = bw / nd
			K:box("UnderCoolerBody", V3(bw, 2.6, 1.0), pcf * CF(0, 0.3 + 1.3, 0), L.steel)
			K:box("UnderCoolerKick", V3(bw - 0.1, 0.3, 0.9), pcf * CF(0, 0.15, -0.04), L.black)
			K:box("UnderCoolerTop", V3(bw + 0.04, 0.08, 1.04), pcf * CF(0, 2.94, 0), L.steel)
			for i = 1, nd do
				local x = -bw / 2 + dw * (i - 0.5)
				local fc = pcf * CF(x, 1.6, 0.5)
				K:plate("UnderCoolerDoor", dw - 0.08, 2.4, 0.05, fc, L.of(30, 30, 32, M.Metal))
				K:plate("UnderCoolerInner", dw - 0.34, 2.1, 0.02, fc * CF(0, 0, 0.05), L.of(226, 236, 242))
				local m = math.max(2, math.floor((dw - 0.4) / 0.28))
				for row = 0, 1 do
					for j = 1, m do
						local bx = -(dw - 0.5) / 2 + (dw - 0.5) * (j - 0.5) / m
						local col = (th.taps[((i + j + row) % #th.taps) + 1] :: any)[7] or rgb(200, 60, 40)
						K:box("UnderCoolerCan", V3(0.18, 0.42, 0.02), fc * CF(bx, -0.55 + row * 1.0, 0.075), { c = col })
					end
				end
				K:box("UnderCoolerGlass", V3(dw - 0.3, 2.1, 0.02), fc * CF(0, 0, 0.1), { c = rgb(210, 230, 236), m = M.Glass, t = 0.7, r = 0.15 })
				K:box("UnderCoolerHandle", V3(dw - 0.5, 0.06, 0.08), fc * CF(0, 1.06, 0.14), L.chrome)
			end
			-- 위: 바 매트 + 엎어 둔 파인트 잔
			K:box("BarMat", V3(bw - 0.4, 0.03, 0.7), pcf * CF(0, 3.0, 0), L.rubber)
			local ng = math.max(3, math.floor((bw - 0.6) / 0.42))
			for j = 1, ng do
				local gx = -(bw - 0.6) / 2 + (bw - 0.6) * (j - 0.5) / ng
				for row = 0, 1 do
					K:vcyl("PintGlass", 0.48, 0.26, pcf * CF(gx, 3.015 + 0.24, -0.17 + row * 0.34), { c = rgb(226, 236, 238), m = M.Glass, t = 0.55, r = 0.15 })
				end
			end
		end
	end
end

-- 9) 안주 보드 ---------------------------------------------------------------------------------------------
local function foodBoard(c: any)
	local K, V, th = c.K, c.V, c.th
	if not th.food then
		return
	end
	local walls = { "left", "right", "back" }
	if th.feature and th.feature.wall then
		walls = { th.feature.wall, "left", "right", "back" }
	end
	local near = V3((V.x0 + V.x1) / 2, 0, (V.z0 + V.z1) / 2)
	local wn, u, w = findWall(K, walls, 3.2, 4.4, 4.4, 7.8, near, 0.8)
	if not wn or not u or not w then
		return
	end
	local dcf = V:wall(wn, u, 6.1, 0.06)
	local style = if th.board == "digital" then "chalk" else th.board
	listBoard(K, dcf, w - 0.4, 3.0, style, th.foodTitle or "FOOD", nil, th.food, nil, nil)
end

-- 10) 네온사인 (소파 위 > 포인트 벽 > 아무 벽) + 켜기/끄기 ---------------------------------------------------
local function neonFeature(c: any)
	local K, V, th = c.K, c.V, c.th
	local store = c.neon
	local placed = nil
	local function tryWall(walls: { string }, near: Vector3?, minW: number, maxW: number, y0: number, y1: number): boolean
		local wn, u, w = findWall(K, walls, minW, maxW, y0, y1, near, 0.6)
		if wn and u and w then
			local hh = math.min(2.2, y1 - y0 - 0.2)
			local dcf = V:wall(wn, u, (y0 + y1) / 2, 0.08)
			neonSign(K, dcf, w - 0.3, hh, th, th.neonIcon, th.neonText, th.neonC, th.neon2, store)
			placed = { wall = wn, u = u, w = w, y = (y0 + y1) / 2, dcf = dcf }
			return true
		end
		return false
	end
	local done = false
	for _, b in c.banq or {} do
		if not done and (b.wall == "left" or b.wall == "right" or b.wall == "back") then
			local y0 = b.top + 0.7
			done = tryWall({ b.wall }, b.center, 4.0, math.min(7.0, b.len * 0.65), y0, math.min(y0 + 2.6, V.H - 0.6))
		end
	end
	if not done and th.feature then
		done = tryWall({ th.feature.wall }, nil, 4.0, 6.6, 5.0, 7.6)
	end
	if not done then
		done = tryWall({ "left", "right", "back" }, nil, 3.6, 6.0, 5.0, 7.6)
	end
	if not placed then
		return
	end
	-- 스위치 (손 닿는 높이, 서버 앵커에서 떨어진 자리)
	local pl = placed
	local function okAt(wn: string, uu: number, _w: number): boolean
		local lp = (V:wall(wn, uu, 4.8, 0.3)).Position
		return promptOK(K, lp) and reachable(K, wn, uu)
	end
	local swn, su = findWall(K, { pl.wall, "back", "left", "right" }, 0.5, 0.5, 4.45, 5.15, (pl.dcf * CF(pl.w / 2 + 0.6, -2, 0)).Position, 0.6, okAt)
	if not swn or not su then
		K:note("neon: no switch spot")
		return
	end
	local sd = V:wall(swn, su, 4.8, 0.07)
	local plate = K:plate("NeonSwitch", 0.42, 0.6, 0.05, sd, L.of(30, 30, 32))
	K:plate("NeonSwitchRocker", 0.16, 0.3, 0.04, sd * CF(0, 0.04, 0.05), L.of(220, 60, 60))
	K:text("NeonSwitchLabel", 0.4, 0.12, sd * CF(0, -0.38, 0.0), "NEON", { fg = rgb(220, 220, 220), d = 0.01, font = F.GothamBold })
	local base = {}
	for _, p in store.parts do
		table.insert(base, { p = p, c = p.Color })
	end
	Interact.toggle(K, plate, {
		object = "네온사인",
		onText = "네온 끄기",
		offText = "네온 켜기",
		state = true,
		on = function(s: boolean)
			for _, b in base do
				if b.p.Parent then
					b.p.Material = if s then M.Neon else M.SmoothPlastic
					b.p.Color = if s then b.c else b.c:Lerp(rgb(70, 70, 74), 0.7)
				end
			end
			for _, lab in store.labels do
				lab.TextTransparency = if s then 0 else 0.75
			end
			for _, l in store.lights do
				l.Enabled = s
			end
		end,
	})
end

-- 11) 다트 머신 (벽에 세움, 앞 2.4m 던지는 선) + 게임 애니메이션 -----------------------------------------------------
local function dartMachine(c: any)
	local K, V, th = c.K, c.V, c.th
	if not th.dart then
		return
	end
	local size = V3(2.3, 7.7, 1.05)
	if V.H < 8.4 then
		return
	end
	local function test(pcf: CFrame, _wn: string, _u: number): boolean
		-- 프롬프트 자리 + 던지는 길 (앞 7.6) 에 가구 없음
		local lp = (pcf * CF(0.5, 2.3, size.Z / 2 + 0.2)).Position
		if not promptOK(K, lp) then
			return false
		end
		-- 던지는 사람 자리가 카운터 안쪽이면 안 됨
		for _, f in { 2.0, 4.5, 7.4 } do
			if behindCounter(V, (pcf * CF(0, 0, size.Z / 2 + f)).Position) then
				return false
			end
		end
		local mn, mx = laabb(pcf * CF(0, 2.6, size.Z / 2 + 3.9), V3(2.0, 5.0, 7.4))
		if mn.X < V.x0 - 0.1 or mx.X > V.x1 + 0.1 or mn.Z < V.z0 - 0.1 or mx.Z > V.z1 - 1.0 then
			return false
		end
		for _, s in V.solid do
			if overlap(mn, mx, s.min, s.max) then
				return false
			end
		end
		for _, r in K.reserved do
			if overlap(mn, mx, r.min, r.max) then
				return false
			end
		end
		for _, k in V.keep do
			if (k.kind == "door" or k.kind == "restroom" or k.kind == "staff") and overlap(mn, mx, k.min, k.max) then
				return false
			end
		end
		return true
	end
	local pcf = floorOnWall(K, { "left", "right", "back" }, size, V3(V.x0, 0, 0), 0.1, test)
	if not pcf then
		K:note("dart: no spot")
		return
	end
	local _ = reachable
	do
		local lmn, lmx = laabb(pcf * CF(0, 1.5, size.Z / 2 + 4.6), V3(2.4, 3.0, 9.0))
		K:reserve(lmn, lmx, "dartlane")
	end
	local accent = th.neon2 or rgb(60, 160, 255)
	local body = L.of(20, 20, 24)
	local D = size.Z
	local W = size.X
	-- 아래 캐비닛
	K:box("DartCabinet", V3(W, 2.9, D), pcf * CF(0, 1.45, 0), body)
	K:box("DartCabinetFront", V3(W - 0.2, 2.3, 0.04), pcf * CF(0, 1.5, D / 2 + 0.02), L.of(36, 40, 70))
	K:box("DartSpeaker", V3(0.7, 0.55, 0.03), pcf * CF(-0.5, 2.15, D / 2 + 0.05), L.of(44, 44, 48, M.DiamondPlate))
	local panel = K:box("DartPanel", V3(0.86, 0.66, 0.08), pcf * CF(0.5, 2.25, D / 2 + 0.06), L.of(28, 28, 32))
	local _, credit = K:text("DartCredit", 0.7, 0.16, pcf * CF(0.5, 2.44, D / 2 + 0.1), "CREDIT 00", { fg = rgb(255, 60, 50), bg = rgb(8, 8, 8), glow = 1.4, d = 0.01, font = F.Arcade })
	K:box("DartCardSlot", V3(0.4, 0.04, 0.03), pcf * CF(0.5, 2.2, D / 2 + 0.11), L.black)
	K:box("DartCoinSlot", V3(0.06, 0.22, 0.03), pcf * CF(0.75, 2.06, D / 2 + 0.11), L.chrome)
	K:text("DartInsert", 0.6, 0.1, pcf * CF(0.5, 2.0, D / 2 + 0.105), "INSERT CARD", { fg = rgb(220, 220, 220), d = 0.005, font = F.GothamBold })
	K:box("DartKick", V3(W - 0.1, 0.3, 0.05), pcf * CF(0, 0.15, D / 2 + 0.02), L.black)
	-- 위 하우징 (뒤판 + 양 날개 LED)
	K:box("DartBack", V3(W, 4.6, 0.5), pcf * CF(0, 2.9 + 2.3, -D / 2 + 0.25), body)
	local leds = {}
	for _, sx in { -1, 1 } do
		K:box("DartWing", V3(0.2, 4.6, 0.6), pcf * CF(sx * (W / 2 - 0.1), 5.2, -D / 2 + 0.6), body)
		local led = K:box("DartLED", V3(0.05, 4.3, 0.05), pcf * CF(sx * (W / 2 - 0.1), 5.2, -D / 2 + 0.92), L.neon(accent))
		table.insert(leds, led)
	end
	-- 다트판 (소프트팁: 캐치링 · 더블/트리플 링 · 세그먼트 · 불)
	local bc = pcf * CF(0, 5.0, -D / 2 + 0.5)
	wdisc(K, "DartCatch", 2.0, 0.06, bc, 0, L.of(26, 30, 60))
	wdisc(K, "DartNumberRing", 1.72, 0.04, bc, 0.06, L.black)
	wdisc(K, "DartDouble", 1.44, 0.03, bc, 0.1, L.of(210, 30, 40))
	wdisc(K, "DartSingle", 1.32, 0.03, bc, 0.13, L.of(236, 232, 220))
	wdisc(K, "DartTriple", 0.88, 0.03, bc, 0.16, L.of(40, 90, 200))
	wdisc(K, "DartInner", 0.78, 0.03, bc, 0.19, L.of(236, 232, 220))
	if K.detail ~= "low" then
		for k = 0, 9 do
			local a = k * PI / 5 + PI / 20
			K:box("DartSegment", V3(0.12, 0.64, 0.01), bc * CF(0, 0, 0.225) * ANG(0, 0, a) * CF(0, 0.33, 0), L.of(30, 30, 34))
		end
	end
	wdisc(K, "DartBullOuter", 0.18, 0.03, bc, 0.23, L.of(40, 90, 200))
	wdisc(K, "DartBull", 0.08, 0.03, bc, 0.26, L.of(210, 30, 40))
	-- 꽂힌 다트 3개
	for k, off in { { 0.12, 0.3 }, { -0.28, -0.1 }, { 0.05, -0.04 } } do
		local tip = (bc * CF(off[1], off[2], 0.25)).Position
		local tail = (bc * CF(off[1] + 0.05, off[2] + 0.08, 0.85)).Position
		K:seg("DartBarrel", tip, tail, 0.04, L.chrome)
		local fcol = if k == 1 then rgb(250, 60, 60) elseif k == 2 then rgb(60, 200, 255) else rgb(250, 220, 60)
		K:box("DartFlight", V3(0.16, 0.16, 0.01), CF(tail) * ANG(0, 0, PI / 4), { c = fcol })
	end
	-- 화면 + 헤더 간판
	local scr, scrLab = K:text("DartScreen", 1.7, 0.72, pcf * CF(0, 6.55, -D / 2 + 0.51), "DART  ·  501  ·  CRICKET\nINSERT CARD", { fg = rgb(255, 255, 255), bg = rgb(18, 30, 80), glow = 1.3, d = 0.02, font = F.GothamBold })
	local _ = scr
	K:box("DartHeader", V3(W, 0.6, 0.62), pcf * CF(0, 7.4, -D / 2 + 0.31), body)
	K:text("DartHeaderSign", W - 0.3, 0.42, pcf * CF(0, 7.4, -D / 2 + 0.62), "DARTS", { fg = accent, glow = 2.0, font = F.Bangers, d = 0.02 })
	-- 던지는 선 (바닥, 2.44m ≈ 7.2 스터드)
	local lineCF = pcf * CF(0, 0.012, D / 2 + 7.2)
	K:box("DartThrowLine", V3(2.0, 0.024, 0.18), lineCF, L.of(240, 240, 236))
	K:text("DartThrowText", 1.4, 0.3, CFrame.fromMatrix((pcf * CF(0, 0.03, D / 2 + 7.55)).Position, pcf.XVector, -pcf.ZVector, pcf.YVector), "THROW LINE", { fg = rgb(220, 220, 214), d = 0.005, font = F.GothamBlack, free = true })
	-- 게임 상태
	local playing = false
	local score = 501
	local hits = { "T20  ▶  60", "S5  ▶  5", "T19  ▶  57", "BULL  ▶  50", "S20  ▶  20", "D16  ▶  32", "T20  ▶  60", "S1  ▶  1" }
	local vals = { 60, 5, 57, 50, 20, 32, 60, 1 }
	local step = 0
	local lastT = 0
	local base: { [BasePart]: Color3 } = {}
	for _, l in leds do
		base[l] = l.Color
	end
	Interact.toggle(K, panel, {
		object = "다트 머신",
		onText = "게임 끝내기",
		offText = "다트 게임 시작",
		state = false,
		on = function(s: boolean)
			playing = s
			score = 501
			step = 0
			credit.Text = if s then "CREDIT 01" else "CREDIT 00"
			scrLab.Text = if s then "PLAYER 1   501\nGAME ON!" else "DART  ·  501  ·  CRICKET\nINSERT CARD"
		end,
	})
	Interact.anim(K, function(t: number)
		-- 대기: 천천히 색 순환 / 게임 중: 빠르게 깜빡임 + 점수
		for i, l in leds do
			if l.Parent then
				if playing then
					l.Color = if math.floor(t * 4 + i) % 2 == 0 then accent else rgb(255, 255, 255)
				else
					l.Color = Color3.fromHSV((t * 0.08 + i * 0.3) % 1, 0.8, 1)
				end
			end
		end
		if playing and t - lastT > 1.6 then
			lastT = t
			step += 1
			local k = (step - 1) % #hits + 1
			score -= vals[k]
			if score <= 0 then
				scrLab.Text = "PLAYER 1  WIN!\n☆ GAME SHOT ☆"
				score = 501
			else
				scrLab.Text = "PLAYER 1   " .. tostring(score) .. "\n" .. hits[k]
			end
		end
	end)
	c.dart = pcf
end

-- 12) 브라이트 탱크 · 케그 (크래프트 테마) ----------------------------------------------------------------------
local function briteTank(K: any, pcf: CFrame, dia: number, H: number, label: string, detail: string)
	local steel = L.of(150, 156, 162, M.Metal, { r = 0.28 })
	local legH = 1.4
	local r = dia / 2
	for i = 0, 3 do
		local a = i * PI / 2 + PI / 4
		local p0 = pcf * V3(math.cos(a) * r * 0.86, 0.05, math.sin(a) * r * 0.86)
		local p1 = pcf * V3(math.cos(a) * r * 0.72, legH + 0.55, math.sin(a) * r * 0.72)
		K:seg("TankLeg", p0, p1, 0.16, steel)
		K:disc("TankFoot", 0.34, 0.06, CF(p0 - V3(0, 0.02, 0)), steel)
	end
	K:ell("TankBottom", V3(dia, 1.1, dia), pcf * CF(0, legH + 0.55, 0), steel)
	local bodyH = H - legH - 0.55 - 0.45
	K:vcyl("TankBody", bodyH, dia, pcf * CF(0, legH + 0.55 + bodyH / 2, 0), steel)
	local topY = legH + 0.55 + bodyH
	K:ell("TankTop", V3(dia, 0.9, dia), pcf * CF(0, topY, 0), steel)
	for _, f in { 0.22, 0.68 } do
		K:vcyl("TankJacket", bodyH * 0.24, dia + 0.04, pcf * CF(0, legH + 0.55 + bodyH * f, 0), L.of(128, 132, 138, M.DiamondPlate))
	end
	-- 맨홀 (앞 아래)
	local mh = pcf * CF(0, legH + 0.55 + 0.75, r - 0.03)
	K:cyl("TankManway", 0.1, 0.78, mh * ANG(0, PI / 2, 0), steel)
	K:bar("TankManwayHandle", (mh * CF(-0.22, 0, 0.08)).Position, (mh * CF(0.22, 0, 0.08)).Position, 0.06, 0.06, L.blackMetal)
	-- 아래 배출 밸브 + 빨간 손잡이
	local vp = pcf * CF(0.34, legH + 0.62, r * 0.7)
	K:seg("TankPipe", vp.Position, (vp * CF(0, 0, 0.55)).Position, 0.12, steel)
	K:cyl("TankValve", 0.1, 0.28, vp * CF(0, 0, 0.42) * ANG(0, PI / 2, 0), steel)
	K:box("TankValveHandle", V3(0.36, 0.05, 0.06), vp * CF(0.12, 0.12, 0.42), L.of(200, 40, 40))
	-- 사이트 글라스 (맥주 높이)
	local sa = PI / 3
	local sx, sz = math.cos(sa) * (r + 0.08), math.sin(sa) * (r + 0.08)
	K:vcyl("TankSightGlass", bodyH * 0.78, 0.09, pcf * CF(sx, legH + 0.55 + bodyH * 0.5, sz), { c = rgb(220, 236, 240), m = M.Glass, t = 0.45 })
	K:vcyl("TankSightBeer", bodyH * 0.5, 0.06, pcf * CF(sx, legH + 0.55 + bodyH * 0.11 + bodyH * 0.25, sz), { c = rgb(214, 150, 50), m = M.Glass, t = 0.15 })
	-- 위: 압력계 · 안전밸브 · CIP 팔
	K:vcyl("TankTopPipe", 0.5, 0.1, pcf * CF(0.3, topY + 0.3, 0), steel)
	K:cyl("TankGauge", 0.06, 0.26, pcf * CF(0.3, topY + 0.6, 0.06) * ANG(0, PI / 2, 0), L.white)
	K:seg("TankCIP", (pcf * CF(-0.25, topY + 0.35, 0)).Position, (pcf * CF(-0.25, topY + 0.75, 0)).Position, 0.12, steel)
	K:seg("TankCIP", (pcf * CF(-0.25, topY + 0.75, 0)).Position, (pcf * CF(-0.25, topY + 0.75, -r - 0.1)).Position, 0.12, steel)
	-- 라벨 (분필 태그 + 금속판)
	K:text("TankLabel", 0.95, 0.52, pcf * CF(0, legH + 0.55 + bodyH * 0.46, r + 0.015), label, { fg = rgb(30, 30, 30), bg = rgb(240, 240, 236), d = 0.01, font = F.GothamBold })
	if detail == "high" then
		K:box("TankWeld", V3(0.02, bodyH, 0.02), pcf * CF(-r * 0.7, legH + 0.55 + bodyH / 2, r * 0.71), L.of(160, 164, 168, M.Metal))
	end
	-- 온도 · 압력 컨트롤러 (글리콜 냉각)
	local cx = -0.55
	local cz = math.sqrt(math.max(0.01, r * r - cx * cx))
	local ctl = K:box("TankController", V3(0.52, 0.7, 0.16), pcf * CF(cx, 4.35, cz + 0.07), L.of(232, 232, 228))
	local _, lcd = K:text("TankControllerLCD", 0.42, 0.3, pcf * CF(cx, 4.45, cz + 0.152), "", { fg = rgb(120, 255, 160), bg = rgb(10, 20, 14), glow = 1.3, d = 0.005, font = F.Arcade })
	K:box("TankControllerLED", V3(0.06, 0.06, 0.02), pcf * CF(cx + 0.15, 4.12, cz + 0.155), L.ledGreen)
	K:seg("TankControllerCable", (pcf * CF(cx, 4.0, cz + 0.05)).Position, (pcf * CF(cx, 3.2, cz + 0.02)).Position, 0.03, L.black)
	return ctl, lcd
end

local function keg(K: any, base: CFrame, cap: Color3)
	local steel = L.of(150, 154, 160, M.Metal, { r = 0.22 })
	local kd, kh = 1.3, 1.95
	K:vcyl("KegChime", 0.28, kd - 0.08, base * CF(0, 0.14, 0), steel)
	K:vcyl("KegBody", kh - 0.56, kd, base * CF(0, 0.28 + (kh - 0.56) / 2, 0), steel)
	K:vcyl("KegChime", 0.28, kd - 0.08, base * CF(0, kh - 0.14, 0), steel)
	for _, f in { 0.36, 0.64 } do
		K:vcyl("KegRib", 0.06, kd + 0.05, base * CF(0, kh * f, 0), steel)
	end
	K:vcyl("KegSpear", 0.12, 0.34, base * CF(0, kh - 0.2, 0), L.of(40, 40, 44))
	K:vcyl("KegCap", 0.04, 0.4, base * CF(0, kh - 0.12, 0), { c = cap })
end

local function okFront(V: any): any
	return function(pcf: CFrame, _wn: string, _u: number): boolean
		return not behindCounter(V, pcf.Position)
	end
end

local function tanks(c: any)
	local K, V, th = c.K, c.V, c.th
	if not th.tanks or V.H < 8.6 or not budget(K, 80) then
		return
	end
	local H = math.min(V.H - 0.7, 8.8)
	local dia = 2.3
	local walls = { "back", "left", "right" }
	local near = V3((V.x0 + V.x1) / 2 + V.W * 0.25, 0, V.z0)
	local size = V3(2 * dia + 0.5, H + 0.6, dia + 0.3)
	local spots = {}
	local pcf = floorOnWall(K, walls, size, near, 0.15, okFront(V))
	if pcf then
		table.insert(spots, { pcf, 2 })
	else
		size = V3(dia + 0.4, H + 0.6, dia + 0.3)
		for _ = 1, 2 do
			local p1 = floorOnWall(K, walls, size, near, 0.15, okFront(V))
			if p1 then
				table.insert(spots, { p1, 1 })
			end
		end
	end
	if #spots == 0 then
		K:note("tanks: no spot")
		return
	end
	local k = 0
	local ctls = {}
	for _, sp in spots do
		local scf, n = sp[1], sp[2]
		for i = 1, n do
			k += 1
			local x = if n == 2 then (i - 1.5) * (dia + 0.35) else 0
			local b = th.taps[(k % #th.taps) + 1]
			local ctl, lcd = briteTank(K, scf * CF(x, 0, 0), dia, H, string.format("BRITE TANK 0%d\n%s · 1,000L", k, b[1]), K.detail)
			table.insert(ctls, { ctl, lcd, k, b })
		end
		K:box("TankDrain", V3(n * (dia + 0.35) - 0.3, 0.03, 0.4), scf * CF(0, 0.015, dia / 2 + 0.25), L.of(120, 124, 128, M.DiamondPlate))
	end
	c.tankAt = spots[1][1].Position
	-- 컨트롤러 화면: 첫 탱크는 손님이 눌러 볼 수 있음 (온도 · 압력 · 탄산 · 출고)
	local prompted = false
	for _, t in ctls do
		local ctl, lcd, num, b = t[1], t[2], t[3], t[4]
		local pages = {
			string.format("T%02d %s\n 2.0°C  1.1bar", num, b[6] or "ALE"),
			string.format("CO2 %.1f vol\nSET 2.6 vol", 2.4 + num * 0.1),
			"STATUS\nSERVING TODAY",
			string.format("BATCH #%d\nABV %s", 210 + num * 7, b[3] or "5.0%"),
		}
		lcd.Text = pages[1]
		if not prompted and ctl.Parent and promptOK(K, (K.cf:ToObjectSpace(ctl.CFrame)).Position) then
			prompted = true
			Interact.cycle(K, ctl, pages, {
				action = "탱크 상태 보기",
				object = "브라이트 탱크 " .. tostring(num),
				on = function(_i: number, txt: string)
					lcd.Text = txt
				end,
			})
		else
			local cur = 0
			Interact.anim(K, function(tt: number)
				local pg = math.floor(tt / 5 + num) % #pages + 1
				if pg ~= cur then
					cur = pg
					lcd.Text = pages[pg]
				end
			end)
		end
	end
end

local function kegs(c: any)
	local K, V, th = c.K, c.V, c.th
	if not th.kegs or not budget(K, 30) then
		return
	end
	local size = V3(2.9, 2.0, 1.45)
	local pcf = floorOnWall(K, { "back", "left", "right" }, size, c.tankAt or V3(V.x1, 0, V.z0), 0.1, okFront(V))
	if pcf then
		local caps = { rgb(200, 40, 40), rgb(40, 120, 200), rgb(240, 190, 40) }
		keg(K, pcf * CF(-0.72, 0, 0), caps[1])
		keg(K, pcf * CF(0.72, 0, 0), caps[2])
		K:text("KegTag", 0.6, 0.34, pcf * CF(-0.72, 1.05, 0.66), "IPA\n20L", { fg = rgb(30, 30, 30), bg = rgb(250, 236, 200), d = 0.01, font = F.GothamBlack })
	end
end

-- 13) 천장: 에디슨 펜던트 (테이블 위) · 스파이럴 덕트 · 페스툰 · 매달린 와인잔 랙 · 미러볼 ---------------------------
local function tablePendants(c: any)
	local K, V, th = c.K, c.V, c.th
	local lit = 0
	for ti, t in V.tables do
		if t.kind == "grill" then
			continue
		end
		local cx, cz = (t.min.X + t.max.X) / 2, (t.min.Z + t.max.Z) / 2
		local maxDrop = V.H - (t.y + 3.5) - 0.15
		if maxDrop < 0.8 then
			continue
		end
		local offs = if (t.max.X - t.min.X) * (t.max.Z - t.min.Z) > 7 then { { -0.55, 0.2, 0 }, { 0.5, -0.25, 0.35 } } else { { -0.32, 0.12, 0 }, { 0.3, -0.18, 0.4 }, { 0.02, 0.36, 0.2 } }
		for k, o in offs do
			local x, z = cx + o[1], cz + o[2]
			local drop = math.min(2.1 + o[3], maxDrop)
			if Common.ceilFree(K, x, z, 0.3) and clearAt(K, CF(x, V.H - drop / 2, z), V3(1.0, drop + 0.1, 1.0)) then
				local light = k == 1 and lit < 2 and #K.lights < (V.maxLights or 8) - 1
				Props.pendant(K, V3(x, V.H, z), drop, { shade = th.tablePendant or "bulb", dia = if th.tablePendant == "bulb" then 0.9 else 0.8, look = th.pendant and th.pendant.look, light = light, range = 14, bright = 0.95 })
				Common.useCeil(K, x, z)
				if light then
					lit += 1
				end
			end
		end
		local _ = ti
	end
end

local function ducts(c: any)
	local K, V, th = c.K, c.V, c.th
	if V.H < 8.6 or not budget(K, 60) then
		return
	end
	local dia = 0.95
	local y = V.H - 0.32 - dia / 2
	local bestZ, bestRuns, bestLen = nil, nil, 0
	for _, f in { 0.52, 0.44, 0.6, 0.36, 0.68 } do
		local z = V.z0 + V.D * f
		local runs, cur = {}, nil
		local x = V.x0 + 0.5
		while x <= V.x1 - 0.5 do
			local ok = Common.ceilFree(K, x, z, 0.62) and not K:hitsKeep(V3(x - 0.3, y - dia / 2, z - dia / 2), V3(x + 0.3, y + dia / 2, z + dia / 2))
			if ok then
				if not cur then
					cur = { x, x }
					table.insert(runs, cur)
				end
				cur[2] = x
			else
				cur = nil
			end
			x += 0.5
		end
		local total = 0
		for _, r in runs do
			if r[2] - r[1] >= 3 then
				total += r[2] - r[1]
			end
		end
		if total > bestLen then
			bestZ, bestRuns, bestLen = z, runs, total
		end
	end
	if not bestZ or not bestRuns then
		return
	end
	local z = bestZ :: number
	local galv = L.of(178, 182, 186, M.Metal, { r = 0.08 })
	local joint = L.of(150, 154, 158, M.Metal)
	K:free(function()
		for _, r in bestRuns :: { any } do
			local a, b = r[1], r[2]
			local len = b - a
			if len < 3 then
				continue
			end
			local ns = math.max(1, math.ceil(len / 4))
			local sl = len / ns
			for i = 0, ns - 1 do
				local xm = a + sl * (i + 0.5)
				K:cyl("Duct", sl, dia, CF(xm, y, z), galv)
			end
			for i = 0, ns do
				local xj = a + sl * i
				K:cyl("DuctJoint", 0.14, dia + 0.05, CF(xj, y, z), joint)
				K:box("DuctHanger", V3(0.05, V.H - y - dia / 2 + 0.02, 0.1), CF(xj, (V.H + y + dia / 2) / 2, z + dia / 2 - 0.02), L.blackMetal)
				K:box("DuctHanger", V3(0.05, V.H - y - dia / 2 + 0.02, 0.1), CF(xj, (V.H + y + dia / 2) / 2, z - dia / 2 + 0.02), L.blackMetal)
			end
			for _, xe in { a, b } do
				K:cyl("DuctCap", 0.05, dia - 0.04, CF(xe + (if xe == a then -0.02 else 0.02), y, z), joint)
			end
			-- 아래 슬롯 디퓨저
			local ng = math.max(1, math.floor(len / 7))
			for i = 1, ng do
				local xg = a + len * (i - 0.5) / ng
				K:box("DuctGrille", V3(1.4, 0.06, 0.34), CF(xg, y - dia / 2 + 0.02, z), L.of(60, 62, 66))
				for k = -2, 2 do
					K:box("DuctSlot", V3(1.3, 0.065, 0.03), CF(xg, y - dia / 2 + 0.02, z + k * 0.06), L.black)
				end
			end
			local xx = a
			while xx <= b do
				Common.useCeil(K, xx, z)
				xx += 1.2
			end
		end
	end)
	-- 전선관 (뒷벽 위)
	local cy = V.H - 0.25
	K:free(function()
		K:seg("Conduit", V3(V.x0 + 0.4, cy, V.z0 + 0.25), V3(V.x1 - 0.4, cy, V.z0 + 0.25), 0.08, L.blackMetal)
		for _, f in { 0.25, 0.75 } do
			K:box("JunctionBox", V3(0.36, 0.36, 0.2), CF(V.x0 + V.W * f, cy, V.z0 + 0.25), L.blackMetal)
		end
	end)
	local _ = th
end

local function festoon(c: any)
	local K, V, th = c.K, c.V, c.th
	if not th.festoon or V.H < 8.4 or not budget(K, 80) then
		return
	end
	local function line(a: Vector3, b: Vector3, sag: number)
		local len = (b - a).Magnitude
		local n = math.max(3, math.floor(len / 2.2))
		local pts = {}
		for i = 0, n do
			local t = i / n
			table.insert(pts, a:Lerp(b, t) - V3(0, sag * 4 * t * (1 - t), 0))
		end
		for i = 1, n do
			K:seg("FestoonCable", pts[i], pts[i + 1], 0.035, L.black)
		end
		for i = 2, n do
			local p = pts[i]
			K:vcyl("FestoonSocket", 0.14, 0.1, CF(p - V3(0, 0.07, 0)), L.black)
			K:ell("FestoonBulb", V3(0.2, 0.28, 0.2), CF(p - V3(0, 0.27, 0)), L.lampWarm)
		end
		for _, e in { a, b } do
			K:ball("FestoonHook", 0.1, CF(e), L.blackMetal)
		end
	end
	-- 앞쪽 자리 위로 두 줄 (출입문 위 keep 은 피함: 문 keep 은 z >= 문 - 4.4)
	local doorZ = if V.door then V.door.z - 4.6 else V.z1 - 4.6
	local z1 = math.min(doorZ - 0.3, V.z1 - 3)
	local z0 = V.z0 + V.D * 0.38
	local yTop = V.H - 0.15
	K:free(function()
		line(V3(V.x0 + 0.05, yTop, z1), V3(V.x1 - 0.05, yTop, z0), 1.0)
		line(V3(V.x0 + 0.05, yTop, z0), V3(V.x1 - 0.05, yTop, z1), 1.0)
	end)
end

local function glassRack(c: any)
	local K, V, th = c.K, c.V, c.th
	if not th.glassRack then
		return
	end
	local g = V.counters[1]
	if not g or not budget(K, 80) then
		return
	end
	-- 카운터 뒤쪽 위 (7.1 ~ 7.6), 바 펜던트 피함
	local z = g.min.Z + 0.55
	local y = math.min(7.6, V.H - 1.4)
	local x0, x1 = nil, nil
	local best = 0
	local runs, cur = {}, nil
	local x = g.min.X + 0.8
	while x <= g.max.X - 0.8 do
		if Common.ceilFree(K, x, z, 0.75) then
			if not cur then
				cur = { x, x }
				table.insert(runs, cur)
			end
			cur[2] = x
		else
			cur = nil
		end
		x += 0.25
	end
	for _, r in runs do
		if r[2] - r[1] > best then
			best = r[2] - r[1]
			x0, x1 = r[1], r[2]
		end
	end
	if not x0 or not x1 or best < 3 then
		return
	end
	local a, b = x0 :: number, math.min(x1 :: number, (x0 :: number) + 7)
	local metal = th.trim
	K:free(function()
		K:box("GlassRackFrame", V3(b - a, 0.06, 0.08), CF((a + b) / 2, y, z - 0.45), metal)
		K:box("GlassRackFrame", V3(b - a, 0.06, 0.08), CF((a + b) / 2, y, z + 0.45), metal)
		for _, xe in { a, b } do
			K:box("GlassRackFrame", V3(0.08, 0.06, 0.98), CF(xe, y, z), metal)
			K:seg("GlassRackRod", V3(xe, y, z), V3(xe, V.H, z), 0.05, metal)
		end
		local n = math.floor((b - a - 0.3) / 0.42)
		for row = -1, 1, 2 do
			K:box("GlassRackSlide", V3(b - a - 0.1, 0.04, 0.05), CF((a + b) / 2, y - 0.04, z + row * 0.2), metal)
			for i = 1, n do
				local gx = a + 0.15 + (b - a - 0.3) * (i - 0.5) / n
				local gz = z + row * 0.2
				K:disc("WineGlassFoot", 0.26, 0.02, CF(gx, y - 0.08, gz), L.glassClear)
				K:vcyl("WineGlassStem", 0.36, 0.04, CF(gx, y - 0.27, gz), L.glassClear)
				K:ell("WineGlassBowl", V3(0.32, 0.42, 0.32), CF(gx, y - 0.62, gz), { c = rgb(226, 236, 240), m = M.Glass, t = 0.6, r = 0.2 })
			end
		end
	end)
end

local function disco(c: any)
	local K, V, th = c.K, c.V, c.th
	if not th.disco then
		return
	end
	local x, z = (V.x0 + V.x1) / 2 + V.W * 0.18, (V.z0 + V.z1) / 2 + 1.0
	if not Common.ceilFree(K, x, z, 0.9) then
		return
	end
	Common.useCeil(K, x, z)
	local parts = {}
	K:free(function()
		K:seg("DiscoRod", V3(x, V.H, z), V3(x, V.H - 1.1, z), 0.05, L.chrome)
		local ball = K:ball("DiscoBall", 1.3, CF(x, V.H - 1.75, z), { c = rgb(220, 224, 230), m = M.Glass, r = 0.6 })
		table.insert(parts, ball)
		for k = 0, 7 do
			local a = k * PI / 4
			local p = K:box("DiscoMirror", V3(0.22, 0.22, 0.02), CF(x, V.H - 1.75, z) * ANG(0, a, 0) * ANG(0.25 * (k % 3 - 1), 0, 0) * CF(0, 0, 0.66), L.with(L.chrome, { r = 0.6 }))
			table.insert(parts, p)
		end
	end)
	Interact.spin(K, parts, (K.cf * CF(x, 0, z)).Position, 0.08)
end

-- 14) 카운터 위 소품 (코스터 · 바 캐디 · 해피아워 텐트 · 결제 안내) ------------------------------------------------
local function counterProps(c: any)
	local K, V, th = c.K, c.V, c.th
	for gi, g in V.counters do
		local alongX = (g.max.X - g.min.X) >= (g.max.Z - g.min.Z)
		if not alongX then
			continue
		end
		local top = g.y + 0.006
		local custZ = if (V.door and V.door.z or V.z1) > (g.min.Z + g.max.Z) / 2 then 1 else -1
		local edgeZ = if custZ > 0 then g.max.Z else g.min.Z
		local stoolX = {}
		for _, st in V.stools do
			local sc = st.seat.c
			if sc.X > g.min.X and sc.X < g.max.X and (sc.Z - edgeZ) * custZ > 0 and (sc.Z - edgeZ) * custZ < 2.6 then
				table.insert(stoolX, sc.X)
				-- 코스터 (원형 펄프 + 로고 원)
				local p = V3(sc.X + 0.12, top + 0.01, edgeZ - custZ * 0.42)
				if clearAt(K, CF(p), V3(0.5, 0.03, 0.5)) then
					K:disc("Coaster", 0.48, 0.02, CF(p), L.of(236, 226, 204, M.Cardboard))
					K:disc("CoasterPrint", 0.3, 0.022, CF(p + V3(0, 0.002, 0)), { c = th.neonC:Lerp(rgb(0, 0, 0), 0.25) })
				end
			end
		end
		-- 상판 앞 모서리 황동 띠 + 스툴 사이 가방 고리 (카운터 면에 붙임)
		local body = g.body or g.top
		if g.top and body then
			local tz = if custZ > 0 then g.top.max.Z else g.top.min.Z
			local bz = if custZ > 0 then body.max.Z else body.min.Z
			local tw = g.top.max.X - g.top.min.X
			K:free(function()
				K:box("CounterBrassEdge", V3(tw + 0.02, 0.05, 0.03), CF((g.top.min.X + g.top.max.X) / 2, g.y - 0.075, tz + custZ * 0.035), th.trim)
				local xs = {}
				for i = 1, #stoolX - 1 do
					table.insert(xs, (stoolX[i] + stoolX[i + 1]) / 2)
				end
				if K.detail ~= "low" then
					for _, hx in xs do
						local fz = bz + custZ * 0.06
						K:box("BagHookPlate", V3(0.16, 0.22, 0.03), CF(hx, g.y - 0.55, fz), th.trim)
						K:bar("BagHook", V3(hx, g.y - 0.6, fz), V3(hx, g.y - 0.72, fz + custZ * 0.18), 0.05, 0.05, th.trim)
					end
				end
			end)
		end
		if gi > 1 then
			continue
		end
		table.sort(stoolX)
		-- 의자 사이 빈 자리 (탭 타워에서 떨어진 곳)
		local gaps = {}
		for i = 1, #stoolX - 1 do
			table.insert(gaps, (stoolX[i] + stoolX[i + 1]) / 2)
		end
		table.insert(gaps, g.max.X - 0.9)
		table.insert(gaps, g.min.X + 0.9)
		local tapX = if c.tap then c.tap.cf.X else math.huge
		local used = 0
		local zMid = (g.min.Z + g.max.Z) / 2
		for _, gx in gaps do
			if math.abs(gx - tapX) < 2.2 or not clearAt(K, CF(gx, top + 0.4, zMid + custZ * 0.1), V3(1.1, 0.8, 0.7)) then
				continue
			end
			used += 1
			local pc = CF(gx, top, zMid + custZ * 0.1)
			if used == 1 then
				-- 바 캐디 (냅킨 · 빨대 · 코스터 더미)
				K:box("BarCaddy", V3(0.9, 0.3, 0.42), pc * CF(0, 0.15, 0), L.blackMetal)
				K:box("BarCaddyNapkin", V3(0.36, 0.22, 0.36), pc * CF(-0.2, 0.36, 0), L.paper)
				for k = 0, 5 do
					K:seg("Straw", (pc * CF(0.22 + (k % 3) * 0.06 - 0.06, 0.28, (k // 3) * 0.1 - 0.05)).Position, (pc * CF(0.24 + (k % 3) * 0.07 - 0.06, 0.66, (k // 3) * 0.12 - 0.06)).Position, 0.025, { c = if k % 2 == 0 then rgb(30, 30, 30) else th.neonC })
				end
				K:vcyl("CoasterStack", 0.18, 0.46, pc * CF(0.55, 0.09, 0.3), L.of(236, 226, 204, M.Cardboard))
			elseif used == 2 then
				-- 해피아워 텐트 카드
				for _, sd in { -1, 1 } do
					local n = V3(0, 0.31, sd * 0.95)
					local upv = V3(0, 0.95, -sd * 0.31)
					local pos = (pc * CF(0, 0.24, sd * 0.09)).Position
					K:text("TentCard", 0.6, 0.5, CFrame.fromMatrix(pos, upv:Cross(n).Unit, upv, n), "HAPPY HOUR\n17:00 – 19:00\n생맥주 1,000원 ↓", { fg = rgb(30, 30, 30), bg = rgb(250, 240, 214), d = 0.01, font = F.GothamBlack })
				end
			elseif used == 3 then
				-- 간편결제 안내 스탠드
				Props.menuStand(K, pc * CF(0, 0, 0) * ANG(0, 0, 0), "카드 · 삼성페이\n애플페이 · 카카오페이\n제로페이 결제 가능")
			elseif used == 4 then
				-- 기본 안주 (뻥튀기 바구니)
				K:vcyl("SnackBasket", 0.18, 0.62, pc * CF(0, 0.09, 0), L.rattan)
				K:ell("SnackPopcorn", V3(0.56, 0.2, 0.56), pc * CF(0, 0.2, 0), L.of(244, 226, 170))
			end
			if used >= 4 then
				break
			end
		end
		-- 카운터 열린 끝: STAFF ONLY (끝면에 붙임)
		local eb = g.body or g
		local endX = eb.max.X
		K:free(function()
			K:text("StaffOnly", 1.1, 0.34, CFrame.fromMatrix(V3(endX + 0.015, 2.4, (eb.min.Z + eb.max.Z) / 2), V3(0, 0, -1), Vector3.yAxis, V3(1, 0, 0)), "STAFF ONLY", { fg = rgb(255, 255, 255), bg = rgb(170, 30, 30), d = 0.01, font = F.GothamBlack })
		end)
	end
end

-- 15) 벽 장식: 포스터 · 맥주병 진열 선반 · 서핑보드 · 야구배트 · 스피커 · 시계 · 사업자등록증 · 안내판 ----------------------
local function wallDecor(c: any)
	local K, V, th = c.K, c.V, c.th
	local seed = c.seed
	local center = V3((V.x0 + V.x1) / 2, 0, (V.z0 + V.z1) / 2)
	-- 맥주병 · 캔 진열 선반 (포인트 벽 높은 곳)
	do
		local walls = { (th.feature and th.feature.wall) or "left", "left", "right" }
		local wn, u, w = findWall(K, walls, 3.0, 7.0, 6.9, 7.9, center, 0.8)
		if wn and u and w then
			local top = Props.shelf(K, V:wall(wn, u, 7.0, 0.06), w - 0.3, { depth = 0.7, look = th.mid, bracket = L.blackMetal })
			local n = math.max(3, math.floor((w - 0.6) / 0.42))
			for i = 1, n do
				local x = -(w - 0.6) / 2 + (w - 0.6) * (i - 0.5) / n
				local tp = th.taps[(i + seed) % #th.taps + 1]
				local pc = top * CF(x, 0, -0.05)
				if th.key == "fuzzy" or th.key == "party" then
					bottle(K, pc, 0.75 + rnd(seed, i) * 0.25, (th.bottleMix or { "round" })[(i % #(th.bottleMix or { 1 })) + 1], GLASS[(i * 3 + seed) % #GLASS + 1], LABELS[i % #LABELS + 1], L.goldMetal, K.detail)
				elseif i % 2 == 0 then
					beerCan(K, pc, tp[7] or tp[5], rgb(250, 250, 246), K.detail)
				else
					beerBottle(K, pc, if i % 3 == 0 then rgb(40, 96, 56) else rgb(110, 60, 24), LABELS[(i + seed) % #LABELS + 1], K.detail)
				end
			end
		end
	end
	-- 서핑보드 (서핑 테마) / 야구배트 (야구 테마)
	if th.surf then
		local wn, u, w = findWall(K, { "right", "left", "back" }, 3.2, 3.6, 4.4, 8.9, center, 0.8)
		if wn and u and w then
			local cols = { rgb(250, 120, 80), rgb(80, 200, 220), rgb(250, 230, 120) }
			for k = 1, 3 do
				local d = V:wall(wn, u + (k - 2) * 1.05, 6.6, 0.1) * ANG(0, 0, (k - 2) * -0.08)
				K:ell("Surfboard", V3(0.82, 4.0, 0.14), d, { c = cols[k], m = M.SmoothPlastic })
				K:box("SurfStringer", V3(0.03, 3.8, 0.15), d, wood(150, 110, 70))
				K:box("SurfFin", V3(0.06, 0.4, 0.3), d * CF(0, -1.6, 0.18), L.black)
				K:box("SurfRack", V3(0.9, 0.08, 0.3), d * CF(0, -0.9, 0.0), L.blackMetal)
			end
		end
	end
	if th.bats then
		local wn, u, w = findWall(K, { "left", "right", "back" }, 3.0, 3.4, 4.6, 8.4, center, 0.8)
		if wn and u and w then
			for k = 1, 3 do
				local d = V:wall(wn, u + (k - 2) * 0.9, 6.5, 0.12)
				K:seg("BaseballBat", (d * CF(0, -1.5, 0.05)).Position, (d * CF(0, 1.4, 0.05)).Position, 0.18, wood(196, 150, 96))
				K:seg("BaseballBatHandle", (d * CF(0, -1.9, 0.05)).Position, (d * CF(0, -1.45, 0.05)).Position, 0.1, L.black)
				K:box("BatPeg", V3(0.5, 0.06, 0.2), d * CF(0, 0.4, 0.0), L.blackMetal)
			end
			K:text("BatPlate", 2.2, 0.36, V:wall(wn, u, 4.75, 0.08), "사직 직관 기념 배트", { fg = rgb(255, 255, 255), bg = rgb(20, 34, 76), d = 0.02 })
		end
	end
	-- 포스터 (남는 벽)
	local targets = { V3(V.x0, 0, 0), V3(V.x1, 0, V.z0 + 3), V3(0, 0, V.z0), V3(V.x0, 0, V.z1 - 4), V3(V.x1, 0, V.z1 - 4) }
	local np = 0
	for i, kind in th.posters or {} do
		if not budget(K, 30) then
			break
		end
		local near = targets[(i - 1) % #targets + 1]
		local wn, u = findWall(K, { "left", "right", "back" }, 2.0, 2.0, 4.3, 7.5, near, 0.8)
		if wn and u then
			poster(K, V:wall(wn, u, 5.9, 0.06), 2.0, 2.8, kind, th)
			np += 1
		end
	end
	-- 스피커 2 (천장 가까운 벽 모서리)
	for k, near in { V3(V.x0, 0, V.z0 + 1), V3(V.x1, 0, V.z0 + 1) } do
		local wn, u = findWall(K, { if k == 1 then "left" else "right", "back" }, 1.0, 1.0, V.H - 2.0, V.H - 0.5, near, 0.8)
		if wn and u then
			local d = V:wall(wn, u, V.H - 1.25, 0.06)
			K:plate("SpeakerBracket", 0.3, 0.3, 0.3, d * CF(0, 0.5, 0), L.blackMetal)
			K:box("Speaker", V3(0.8, 1.2, 0.7), d * CF(0, 0, 0.45) * ANG(-0.25, 0, 0), L.of(24, 24, 26))
			K:box("SpeakerGrille", V3(0.7, 1.0, 0.02), d * CF(0, 0, 0.45) * ANG(-0.25, 0, 0) * CF(0, 0, 0.36), L.of(40, 40, 44, M.Fabric))
		end
	end
	-- 시계 (빈티지 황동)
	do
		local wn, u = findWall(K, { "back", "right", "left" }, 1.6, 1.6, 7.0, 8.7, V3(0, 0, V.z0), 0.8)
		if wn and u then
			local d = V:wall(wn, u, 7.85, 0.06)
			local hr, mn = Props.clock(K, d, 1.4, { frame = th.trim })
			Interact.clock(K, hr, mn, d, 1.4)
		end
	end
	-- 사업자등록증 · 영업신고증 (카운터 가까이)
	local g = V.counters[1]
	local nearC = if g then (g.min + g.max) / 2 else center
	do
		local wn, u = findWall(K, { "back", "left", "right" }, 1.3, 1.3, 4.6, 6.4, nearC, 0.8)
		if wn and u then
			Props.license(K, V:wall(wn, u, 5.5, 0.06), V.name)
		end
	end
	-- 입구 안내판 (영업시간 · 19세 · 와이파이 · 음주운전)
	local front = V3(0, 0, V.z1 - 2.5)
	local signs = {
		{ 1.5, 1.1, th.hours or "영업시간\n17:00 – 02:00", rgb(250, 246, 236), rgb(24, 24, 26), th.trim and (th.trim.c :: Color3) },
		{ 1.5, 0.95, "청소년 유해업소\n19세 미만 출입 · 고용 금지\n신분증 확인 후 입장", rgb(30, 30, 30), rgb(252, 252, 250), rgb(200, 30, 30) },
		{ 1.1, 0.8, "FREE Wi-Fi\nID  " .. (th.wifi or "PUB_5G"), rgb(255, 255, 255), rgb(30, 30, 34), nil },
		{ 1.5, 0.7, "음주운전은 범죄입니다\n대리운전은 직원에게 문의하세요", rgb(255, 255, 255), rgb(30, 60, 140), nil },
	}
	for i, s in signs do
		local wn, u = findWall(K, { if i % 2 == 1 then "left" else "right", if i % 2 == 1 then "right" else "left" }, s[1] + 0.1, s[1] + 0.1, 4.6, 4.6 + s[2] + 0.2, V3(if i % 2 == 1 then V.x0 else V.x1, 0, V.z1 - 3), 0.8)
		if wn and u then
			signPlate(K, V:wall(wn, u, 4.6 + s[2] / 2 + 0.1, 0.06), s[1], s[2], s[3], s[4], s[5], s[6])
		end
	end
	-- 원산지 표시판 (안주 파는 펍: 카운터 근처, 법정 표시)
	do
		local wn, u = findWall(K, { "back", "left", "right" }, 1.6, 1.6, 3.9, 5.5, nearC, 0.8)
		if wn and u then
			signPlate(K, V:wall(wn, u, 4.7, 0.06), 1.5, 1.4, "원산지 표시\n닭고기(윙) 국내산\n돼지고기(소시지) 국내산\n감자 미국산 · 오징어 국내산\n쌀 · 김치 국내산", rgb(30, 30, 30), rgb(250, 250, 246), rgb(40, 110, 60), F.GothamMedium)
		end
	end
	local _ = np
end

-- 15b) 벽 조명 (황동 브래킷 + 유리 갓 + 에디슨 전구; 불빛 예산 대신 빛나는 전구로)
local function sconces(c: any)
	local K, V, th = c.K, c.V, c.th
	if not budget(K, 30) then
		return
	end
	for _, wn in { "left", "right" } do
		local w = V.walls[wn]
		local n = 0
		local u = w.a + 3.0
		while u < w.b - 2.0 and n < 3 do
			local ok = false
			for _, sp in freeSpans(K, wn, 6.3, 7.5, 0.8) do
				if u - 0.4 > sp[1] and u + 0.4 < sp[2] then
					ok = true
				end
			end
			local p = V:wall(wn, u, 0, 1.0).Position
			if ok and p.Z < V.z1 - 2.2 then
				claim(K, wn, u - 0.6, u + 0.6, 6.3, 7.5)
				local d = V:wall(wn, u, 6.9, 0.05)
				K:plate("SconcePlate", 0.22, 0.36, 0.05, d, th.trim)
				K:bar("SconceArm", (d * CF(0, 0, 0.04)).Position, (d * CF(0, 0.12, 0.42)).Position, 0.05, 0.05, th.trim)
				K:vcyl("SconceCup", 0.12, 0.16, d * CF(0, 0.16, 0.44), th.trim)
				K:ell("SconceBulb", V3(0.2, 0.28, 0.2), d * CF(0, 0.34, 0.44), L.lampWarm)
				K:vcyl("SconceShade", 0.36, 0.42, d * CF(0, 0.42, 0.44), { c = rgb(240, 214, 170), m = M.Glass, t = 0.45 })
				n += 1
				u += 6.0
			else
				u += 1.0
			end
		end
	end
end

-- 16) 주크박스 (벽걸이 디지털 주크박스, 곡 바꾸기) --------------------------------------------------------------
local function jukebox(c: any)
	local K, V, th = c.K, c.V, c.th
	if c.dart and c.neonOK then
		-- 다트 + 네온이 있으면 충분
	end
	local function okAt(wn: string, uu: number, _w: number): boolean
		return promptOK(K, (V:wall(wn, uu, 4.6, 0.4)).Position) and reachable(K, wn, uu)
	end
	local wn, u = findWall(K, { "right", "left", "back" }, 1.9, 1.9, 3.6, 6.4, V3(V.x1, 0, 0), 0.8, okAt)
	if not wn or not u then
		K:note("jukebox: no spot")
		return
	end
	local d = V:wall(wn, u, 5.0, 0.06)
	local body = L.of(24, 24, 28)
	K:panel("JukeBody", 1.5, 2.6, 0.36, 0.26, d, body)
	K:panel("JukeTrim", 1.6, 2.7, 0.3, 0.3, d, L.with(th.trim, {}))
	local glow = K:plate("JukeArch", 1.24, 0.1, 0.38, d * CF(0, 1.14, 0), L.neon(th.neonC))
	local _, lab = K:text("JukeScreen", 1.2, 0.95, d * CF(0, 0.44, 0.38), "", { fg = rgb(255, 255, 255), bg = rgb(16, 20, 40), glow = 1.3, d = 0.02, font = F.GothamBold })
	K:box("JukeSpeaker", V3(1.1, 0.5, 0.02), d * CF(0, -0.68, 0.37), L.of(44, 44, 48, M.Fabric))
	local btn = K:plate("JukeButton", 0.8, 0.26, 0.06, d * CF(0, -0.2, 0.36), L.of(200, 40, 60))
	K:text("JukeButtonText", 0.72, 0.18, d * CF(0, -0.2, 0.42), "SELECT ▶", { fg = rgb(255, 255, 255), d = 0.005, font = F.GothamBlack })
	K:text("JukeBrand", 1.1, 0.16, d * CF(0, 1.0, 0.37), "DIGITAL JUKEBOX", { fg = th.neonC, glow = 1.4, d = 0.005, font = F.GothamBlack })
	local songs = {
		{ "♪ NOW PLAYING", "광안리 밤바다", "City Pop · 3:52" },
		{ "♪ NOW PLAYING", "Summer Wave", "Indie Rock · 4:10" },
		{ "♪ NOW PLAYING", "해운대 연가", "K-Ballad · 4:31" },
		{ "♪ NOW PLAYING", "Friday Night Lights", "Disco · 3:28" },
		{ "♪ NOW PLAYING", "Busan Blues", "Jazz · 5:02" },
	}
	local function show(s: any)
		lab.Text = s[1] .. "\n" .. s[2] .. "\n" .. s[3]
	end
	show(songs[1])
	Interact.cycle(K, btn, songs, {
		action = "다음 곡",
		object = "주크박스",
		on = function(_i: number, s: any)
			show(s)
		end,
	})
	local gc = glow.Color
	Interact.anim(K, function(t: number)
		if glow.Parent then
			glow.Color = gc:Lerp(rgb(255, 255, 255), 0.25 + 0.25 * math.sin(t * 2))
		end
	end)
end

-- 16b) 위스키 배럴 스탠딩 테이블 (넓게 빈 바닥에만, 통로 · 문 · 다트 길 피함) ------------------------------------------
local function barrelTable(K: any, pcf: CFrame, th: any)
	local oak = wood(118, 76, 44)
	local hoop = L.of(36, 36, 38, M.Metal)
	K:vcyl("BarrelBody", 2.9, 1.86, pcf * CF(0, 1.45, 0), oak)
	K:vcyl("BarrelBelly", 1.5, 1.98, pcf * CF(0, 1.45, 0), oak)
	for _, y in { 0.3, 0.95, 1.95, 2.6 } do
		K:vcyl("BarrelHoop", 0.12, (if y == 0.95 or y == 1.95 then 2.02 else 1.9), pcf * CF(0, y, 0), hoop)
	end
	if K.detail == "high" then
		for k = 0, 7 do
			local a = k * PI / 4
			K:box("BarrelStave", V3(0.03, 2.84, 0.04), pcf * CF(math.cos(a) * 0.94, 1.45, math.sin(a) * 0.94) * ANG(0, -a, 0), dim(oak, 0.35))
		end
	end
	K:disc("BarrelTop", 2.5, 0.12, pcf * CF(0, 2.96, 0), wood(140, 94, 56))
	K:disc("BarrelTopEdge", 2.54, 0.05, pcf * CF(0, 2.89, 0), dim(wood(140, 94, 56), 0.3))
	K:text("BarrelBrand", 0.9, 0.36, pcf * CF(0, 1.5, 0.995), th.brand, { fg = rgb(40, 24, 14), d = 0.005, font = F.Oswald })
end

local function barrels(c: any)
	local K, V, th = c.K, c.V, c.th
	if not budget(K, 40) or th.key == "fuzzy" or th.key == "party" then
		return
	end
	local cands = {}
	local x = V.x0 + 2.5
	while x <= V.x1 - 2.5 do
		local z = V.z0 + 2.5
		while z <= V.z1 - 3.0 do
			table.insert(cands, V3(x, 0, z))
			z += 1.0
		end
		x += 1.0
	end
	-- 뒤쪽 (TV · 탭 보드 가까이) 부터
	local tvp = if c.tv then V:wall(c.tv.wall, c.tv.u, 0, 3.5).Position else V3(0, 0, V.z0)
	table.sort(cands, function(a, b)
		return (a - tvp).Magnitude < (b - tvp).Magnitude
	end)
	local n = 0
	local maxN = if V.W * V.D > 600 then 2 else 1
	for _, p in cands do
		if n >= maxN then
			break
		end
		local nearSeat = false
		for _, list in { V.stools, V.chairs } do
			for _, st in list do
				local d = st.seat.c - p
				if V3(d.X, 0, d.Z).Magnitude < 3.0 then
					nearSeat = true
				end
			end
		end
		if not behindCounter(V, p) and not nearSeat then
			local pcf = CF(p)
			local mn, mx = laabb(pcf * CF(0, 1.6, 0), V3(4.6, 3.2, 4.6))
			if mapClear(V, mn, mx) and K:spot(pcf, V3(2.6, 3.1, 2.6), 1.3, "barrel") then
				barrelTable(K, pcf, th)
				n += 1
			end
		end
	end
end

-- 17) 화분 (앞 모서리) ------------------------------------------------------------------------------------
local function plants(c: any)
	local K, V, th = c.K, c.V, c.th
	local kinds = th.plants or { "monstera" }
	local spots = { V3(V.x0 + 1.1, 0, V.z1 - 1.3), V3(V.x1 - 1.1, 0, V.z1 - 1.3), V3(V.x0 + 1.1, 0, V.z1 - 3.6), V3(V.x1 - 1.1, 0, V.z1 - 3.6) }
	local n = 0
	for i, p in spots do
		if n >= 2 then
			break
		end
		local h = math.clamp(V.H * 0.5, 4, 5.4)
		local pcf = CF(p)
		local kind = kinds[(i + c.seed) % #kinds + 1]
		local spread = if kind == "monstera" then 6.2 elseif kind == "snake" then 1.4 else 2.6
		local mn, mx = laabb(pcf * CF(0, h / 2, 0), V3(1.8, h, 1.8))
		if mapClear(V, mn, mx) and clearAt(K, pcf * CF(0, h * 0.62, 0), V3(spread, h * 0.7, spread)) and K:spot(pcf, V3(1.8, h, 1.8), 0.1, "plant") then
			Props.floorPlant(K, pcf, { kind = kind, h = h, dia = 1.4, pot = L.of(52, 50, 48, M.Concrete) })
			n += 1
		end
	end
end

-- 스타일 ------------------------------------------------------------------------------------------------
function T.style(V: any): any
	local th = pickTheme(V)
	return {
		chair = false, -- 벤치 소파 · 의자는 T.build 가 직접 (소파를 의자 3개로 바꾸지 않게)
		stool = th.stool,
		table = { top = th.tableTop, base = L.blackMetal, thick = 0.2, r = 0.08 },
		counter = { front = th.counterFront, frontL = th.counterFrontL, topL = th.counterTop, kickL = L.black, led = th.led },
		ceiling = { skin = th.ceil },
		floor = th.floor,
		lower = th.lower,
		base = dim(th.dark, 0.2),
		pendant = th.pendant,
		clock = false,
		license = false,
		cctv = true,
		mat = { look = L.of(44, 36, 30, M.Fabric), text = th.mat },
		lights = { kind = "none" },
		plants = th.plants,
		pubTheme = th,
	}
end

function T.build(K: any, V: any, S: any)
	local th = S.pubTheme or pickTheme(V)
	local c = {
		K = K,
		V = V,
		S = S,
		th = th,
		seed = hash(tostring(V.key or V.name or "pub")),
		neon = { parts = {}, labels = {}, lights = {} },
		usedChairs = {},
	}
	local steps = {
		{ "banquette", banquettes },
		{ "chairs", chairsOver },
		{ "backbar", backBar },
		{ "shelfbar", shelfBar },
		{ "tap", tapTower },
		{ "rail", footRail },
		{ "upper", upperWalls },
		{ "tv", tvSet },
		{ "board", tapBoard },
		{ "dart", dartMachine },
		{ "tanks", tanks },
		{ "neon", neonFeature },
		{ "jukebox", jukebox },
		{ "kegs", kegs },
		{ "food", foodBoard },
		{ "pendants", tablePendants },
		{ "ducts", ducts },
		{ "festoon", festoon },
		{ "glassrack", glassRack },
		{ "disco", disco },
		{ "counter", counterProps },
		{ "decor", wallDecor },
		{ "sconces", sconces },
		{ "plants", plants },
		{ "barrels", barrels },
	}
	local counts = {}
	local n0 = #K.parts
	for _, st in steps do
		local before = #K.parts
		local ok, err = pcall(st[2], c)
		if not ok then
			K:note("pub." .. st[1] .. " error: " .. tostring(err))
		end
		if #K.parts - before > 0 then
			table.insert(counts, st[1] .. "=" .. tostring(#K.parts - before))
		end
	end
	K:note("pub parts +" .. tostring(#K.parts - n0) .. " (" .. table.concat(counts, " ") .. ")")
end

return T

end

__defs["T_seafood"] = function()
-- GwangalliBuildingInterior/T_seafood: 유형 (rawfish seafood) 실내.
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (Common.luau 머리말의 S 필드)
--   build(K, V, S) 유형별 디테일 (메뉴판 · 진열 · 주방 · 간판 · 소품 · 상호작용)

local Look = __require("Look")
local Props = __require("Props")
local Interact = __require("Interact")
local Common = __require("Common")

local T = {}
T.types = { "rawfish", "seafood" }

function T.style(V: any): any
	return {
		chair = { style = "padded", frame = Look.blackMetal, seat = Look.fabricGrey },
		table = { top = Look.oak, base = Look.blackMetal },
		counter = { front = "panel", frontL = Look.white, topL = Look.marbleWhite },
		lights = { kind = "downlight" },
	}
end

function T.build(K: any, V: any, S: any) end

return T

end

__defs["T_service"] = function()
-- GwangalliBuildingInterior/T_service: 유형 (lobby residence realty laundry office bank clinic academy) 실내.
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (Common.luau 머리말의 S 필드)
--   build(K, V, S) 유형별 디테일 (메뉴판 · 진열 · 주방 · 간판 · 소품 · 상호작용)

local Look = __require("Look")
local Props = __require("Props")
local Interact = __require("Interact")
local Common = __require("Common")

local T = {}
T.types = { "lobby", "residence", "realty", "laundry", "office", "bank", "clinic", "academy" }

function T.style(V: any): any
	return {
		chair = { style = "padded", frame = Look.blackMetal, seat = Look.fabricGrey },
		table = { top = Look.oak, base = Look.blackMetal },
		counter = { front = "panel", frontL = Look.white, topL = Look.marbleWhite },
		lights = { kind = "downlight" },
	}
end

function T.build(K: any, V: any, S: any) end

return T

end

__defs["T_store"] = function()
-- GwangalliBuildingInterior/T_store: 유형 (cvs retail pharmacy) 실내.
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (Common.luau 머리말의 S 필드)
--   build(K, V, S) 유형별 디테일 (진열 상품 · 냉장고 · 담배장 · 계산대 · 간판 · POP · 소품 · 상호작용)
--
-- 세부 유형 (V.name / V.menu / 내용물로 판단):
--   cvs      : gs25 · cu · seven (7-ELEVEn) · emart24 · indie (동네 슈퍼 · 스낵 편의점) — 브랜드 색 · PB · 커피 · 택배 문구
--   retail   : cosmetics (올리브영 · 화장품) · souvenir (기념품 · I AM BUSAN) · beach (비치용품 · 튜브대여 · 돗자리)
--              · flower (꽃집) · book (서점) · generic
--   pharmacy : street (거리 약국) · gw (GwShop 바다약국: 바닥 소품은 거의 안 늘리고 진열 · 벽 · 천장만)
-- 맵 진열대(Gondola · WallBay · 약장 · Fridge)는 게임플레이 파트라 그대로 두고, 그 위의 엉성한 Product/Bottle/Goods/Shirt/Float
-- 상자만 숨긴 뒤 같은 선반 위에 실제 크기 상품(봉지과자 · 컵라면 · 페트 · 캔 · 우유 · 화장품 · 약 상자 ...)을 다시 진열합니다.
-- 새 바닥 소품은 전부 canPlace (= K:spot 과 같은 검사, 예약은 성공 후) 로 자리 확인, 벽 소품은 K.wallUsed 로 서로 피함.
-- Common.fixtures (스위치 · 콘센트 · 시계 · 사업자등록증) 는 S.skip 으로 미뤘다가 큰 진열장을 놓은 뒤 · 포스터 전에 불러 서로 피하게 함.
-- 프롬프트가 있는 소품(사이니지 · 택배 접수기 · 혈압계 · 거울 조명 · 회전 진열대 · 광안대교 모형 · 선풍기)은 서버 앵커 6.5 밖
-- (ShopLife 의 진열대 '고르기' 앵커 추정치 포함) 에서만 자리를 잡고, 그 자리를 다른 것보다 먼저 차지함.

local Look = __require("Look")
local Props = __require("Props")
local Interact = __require("Interact")
local Common = __require("Common")
local Scan = __require("Scan")

local TweenService = game:GetService("TweenService")

local T = {}
T.types = { "cvs", "retail", "pharmacy" }

local CF, V3 = CFrame.new, Vector3.new
local ANG = CFrame.Angles
local PI = math.pi
local M = Enum.Material
local C = Color3.fromRGB
local WHITE = C(255, 255, 255)
local INK = C(28, 28, 32)

---------------------------------------------------------------------------------------------------
-- 0. 기본 도구
---------------------------------------------------------------------------------------------------

local function hashStr(s: string): number
	local h = 7
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 2147483647
	end
	return h
end

-- 결정적 난수 (매장 · 선반마다 같은 결과)
local function mkRng(seed: any): () -> number
	local s = (if type(seed) == "number" then math.floor(seed) else hashStr(tostring(seed))) % 2147483646 + 1
	return function(): number
		s = (s * 48271) % 2147483647
		return s / 2147483647
	end
end

local function pick(rng: () -> number, list: { any }): any
	return list[math.floor(rng() * #list) + 1]
end

-- 목록 섞기 (매장마다 다른 순서 · 다른 조합)
local function shuffled(rng: () -> number, list: { any }): { any }
	local t = table.clone(list)
	for i = #t, 2, -1 do
		local j = math.floor(rng() * i) + 1
		t[i], t[j] = t[j], t[i]
	end
	return t
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

-- keep 검사 생략 표시 (기존 표면에 붙는 마감 · 같은 범위 덧씌우기)
local function L_FREE(l: any): any
	local t = table.clone(l)
	t.free = true
	return t
end

local function darker(c: Color3, t: number): Color3
	return c:Lerp(C(0, 0, 0), t)
end
local function lighter(c: Color3, t: number): Color3
	return c:Lerp(WHITE, t)
end

-- 표시면 프레임: p 에서 n 쪽(보는 사람 쪽)을 향함
local function dcfAt(p: Vector3, n: Vector3): CFrame
	local x = Vector3.yAxis:Cross(n)
	if x.Magnitude < 1e-3 then
		x = Vector3.xAxis
	end
	x = x.Unit
	local y = n:Cross(x).Unit
	return CFrame.fromMatrix(p, x, y, n)
end

-- 소품 프레임: 바닥 점 p, 정면 face
local function pcfAt(p: Vector3, face: Vector3): CFrame
	return CFrame.lookAt(p, p - face)
end

local function note(K: any, s: string)
	K:note("store: " .. s)
end

-- 긴 자리 찾기 반복 중 프레임 양보 (Kit 의 시간 분할과 같은 기준)
local function yieldy(K: any)
	if K.sliceT and os.clock() - K.sliceT > (K.slice or 0.0025) then
		task.wait()
		K.sliceT = os.clock()
	end
end

local function step(K: any, name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		note(K, name .. " error: " .. tostring(err))
	end
end

local function txt(K: any, name: string, w: number, h: number, dcf: CFrame, s: string, fg: Color3?, bg: Color3?, o: any?): (BasePart, TextLabel)
	local opts: any = o and table.clone(o) or {}
	opts.fg = fg or INK
	opts.bg = bg
	return K:text(name, w, h, dcf, s, opts)
end

---------------------------------------------------------------------------------------------------
-- 1. 자리 확인 · 벽 사용 기록
---------------------------------------------------------------------------------------------------

local STRUCT: { [string]: boolean } = {}
for k in Scan.SHELL do
	STRUCT[k] = true
end
for _, k in { "TBar", "Troffer", "BrandStripe", "GreenBand", "LightPanel", "LightFrame", "Downlight", "TrackRail", "TrackHead", "TrackLens", "CassetteAC", "ACVanes", "ACGrille" } do
	STRUCT[k] = true
end

-- 맵 파트(간판 Sign_ 포함, 벽 · 바닥 · 천장 같은 구조체 제외)와 겹치나?
local function mapBlocked(K: any, mn: Vector3, mx: Vector3): boolean
	for _, r in K.V.parts do
		local nm = r.name
		local isSign = string.sub(nm, 1, 5) == "Sign_"
		if (isSign or not STRUCT[nm]) and r.part.Transparency < 0.99 then
			if K.overlap(mn, mx, r.min, r.max, 0.02) then
				return true
			end
		end
	end
	return false
end

local function wallBusy(K: any, wn: string, a: number, b: number, y0: number, y1: number): boolean
	for _, u in K.wallUsed or {} do
		if u.w == wn and u.a < b and u.b > a and u.y0 < y1 and u.y1 > y0 then
			return true
		end
	end
	return false
end

local function addWallUsed(K: any, wn: string, a: number, b: number, y0: number, y1: number)
	K.wallUsed = K.wallUsed or {}
	table.insert(K.wallUsed, { w = wn, a = a, b = b, y0 = y0, y1 = y1 })
end

-- K:spot 과 같은 검사 (keep · 기존 가구 · 예약), 예약은 안 함. 성공하면 AABB
local function canPlace(K: any, lcf: CFrame, size: Vector3, pad: number?): (Vector3?, Vector3?)
	local V = K.V
	local p = pad or 0
	local c = lcf * CF(0, size.Y / 2, 0)
	local mn, mx = K.laabb(c, size + V3(2 * p, 0, 2 * p))
	if mn.X < V.x0 - 0.05 or mx.X > V.x1 + 0.05 or mn.Z < V.z0 - 0.05 or mx.Z > V.z1 + 0.05 then
		return nil, nil
	end
	if K:hitsKeep(mn, mx) then
		return nil, nil
	end
	for _, s in V.solid do
		if K.overlap(mn, mx, s.min, s.max, 0.04) then
			return nil, nil
		end
	end
	for _, r in K.reserved do
		if K.overlap(mn, mx, r.min, r.max, 0.02) then
			return nil, nil
		end
	end
	local smn, smx = K.laabb(c, size)
	if mapBlocked(K, smn, smx) then
		return nil, nil
	end
	return mn, mx
end

-- 벽에 붙여 세우는 바닥 소품 자리 찾기 (폭 w, 깊이 d, 높이 h). prefer = 가까울수록 좋은 로컬 점
local function wallFloorSpot(K: any, walls: { string }, w: number, d: number, h: number, prefer: Vector3?, pad: number?, kind: string?, accept: ((CFrame) -> boolean)?): (string?, CFrame?, number?)
	local V = K.V
	local cands = {}
	for _, wn in walls do
		local wall = V.walls[wn]
		if wall and wall.b - wall.a > w + 0.2 then
			local u = wall.a + w / 2 + 0.1
			while u <= wall.b - w / 2 - 0.1 + 1e-6 do
				local pcf = V:wall(wn, u, 0, 0.06) * CF(0, 0, d / 2)
				local sc = if prefer then (pcf.Position - prefer).Magnitude else math.abs(u)
				table.insert(cands, { wn = wn, u = u, pcf = pcf, sc = sc })
				u += 0.4
			end
		end
	end
	table.sort(cands, function(a, b)
		return a.sc < b.sc
	end)
	for _, c in cands do
		yieldy(K)
		if not wallBusy(K, c.wn, c.u - w / 2 - 0.1, c.u + w / 2 + 0.1, 0, h) and (not accept or accept(c.pcf)) then
			local mn, mx = canPlace(K, c.pcf, V3(w, h, d), pad)
			if mn and mx then
				K:reserve(mn, mx, kind or "store")
				addWallUsed(K, c.wn, c.u - w / 2 - 0.15, c.u + w / 2 + 0.15, 0, h + 0.3)
				return c.wn, c.pcf, c.u
			end
		end
	end
	return nil, nil, nil
end

-- 벽 부착물 자리 (Common.wallSpot + 맵 간판 · 액자와 안 겹치게 다시 찾기). accept(dcf, wn) 가 false 면 다른 자리 (그 자리는 비워 둠)
-- Common.wallSpot 은 사용 구간을 앞에서부터 빼므로 a 순으로 정렬해 두어야 겹침이 안 생김
local function sortWallUsed(K: any)
	if K.wallUsed then
		table.sort(K.wallUsed, function(x, y)
			return x.a < y.a
		end)
	end
end

local function wallItemSpot(K: any, walls: { string }, w: number, y0: number, y1: number, prefer: number?, accept: ((CFrame, string) -> boolean)?): (string?, CFrame?)
	local temp = {}
	local rw, rd = nil, nil
	for _ = 1, 12 do
		sortWallUsed(K)
		local wn, dcf = Common.wallSpot(K, walls, w, y0, y1, prefer)
		if not wn or not dcf then
			break
		end
		local mn, mx = K.laabb(dcf * CF(0, 0, 0.2), V3(w, y1 - y0, 0.4))
		if mapBlocked(K, mn, mx) or K:hitsKeep(mn, mx) then
			continue
		end
		if accept and not accept(dcf, wn) then
			table.insert(temp, K.wallUsed[#K.wallUsed])
			continue
		end
		rw, rd = wn, dcf
		break
	end
	for _, t in temp do
		local i = table.find(K.wallUsed, t)
		if i then
			table.remove(K.wallUsed, i)
		end
	end
	return rw, rd
end

-- ShopLife 가 실제 게임에서 더 만드는 '고르기' 앵커 자리 (진열대 모델 중심 · 냉동고 · 스티머 · 소매 진열 파트)를
-- Interact 의 호스트 점 목록에 미리 더해 둠 → 오프라인 미리보기에서도 게임과 같은 자리에서만 프롬프트가 생김
local function addHostEstimates(K: any, V: any, kind: string)
	if not K.hostPts then
		K.hostPts = Interact.hostPoints(V)
	end
	local pts = K.hostPts
	local function add(p: Vector3)
		table.insert(pts, V.cf:PointToObjectSpace(p))
	end
	local ok = pcall(function()
		if kind == "cvs" then
			for _, m in V.model:GetDescendants() do
				if m:IsA("Model") and (m.Name == "Gondola" or string.match(m.Name, "^Gondola_%d+$") or m.Name == "Fridge" or m.Name == "OpenChiller") then
					local cf = m:GetBoundingBox()
					add(cf.Position)
				end
			end
		end
	end)
	if not ok then
		note(K, "host estimate failed")
	end
	for _, nm in { "IceCreamChest", "SteamerCase", "HotBar" } do
		local r = V:first(nm)
		if r then
			table.insert(pts, r.c)
		end
	end
	if kind == "retail" then
		local n = 0
		for _, nm in { "WallRack", "DisplayTable", "Rack", "WallBay", "Hanger", "Gondola", "WallShelf", "Shelf", "Product" } do
			for i, r in V.byName[nm] or {} do
				if i <= 3 and n < 5 then
					table.insert(pts, r.c)
					n += 1
				end
			end
		end
	end
end

-- 프롬프트를 둘 수 있는 자리인가 (맵 서버 앵커 6.5 밖, 다른 프롬프트 2.5 밖)
local function promptOk(K: any, lp: Vector3): boolean
	return Interact.canPrompt(K, lp)
end

local function firstOk(K: any, parts: { BasePart }): BasePart?
	for _, p in parts do
		if p and p.Parent and promptOk(K, K.V.cf:PointToObjectSpace(p.Position)) then
			return p
		end
	end
	return nil
end

-- 후보 파트 중 프롬프트를 둘 수 있는 첫 파트에
local function promptOn(K: any, parts: { BasePart }, spec: any): ProximityPrompt?
	for _, p in parts do
		if p and p.Parent then
			local lp = K.V.cf:PointToObjectSpace(p.Position)
			if promptOk(K, lp) then
				return Interact.prompt(K, p, spec)
			end
		end
	end
	note(K, "no prompt spot: " .. tostring(spec.object))
	return nil
end

-- 바닥 아무 데나 (격자 탐색): 중심 후보 cands 중 첫 성공
local function floorSpot(K: any, cands: { Vector3 }, size: Vector3, face: Vector3, pad: number?, kind: string?, accept: ((Vector3) -> boolean)?): CFrame?
	for _, p in cands do
		yieldy(K)
		if accept and not accept(p) then
			continue
		end
		local pcf = pcfAt(V3(p.X, 0, p.Z), face)
		local mn, mx = canPlace(K, pcf, size, pad)
		if mn and mx then
			K:reserve(mn, mx, kind or "store")
			return pcf
		end
	end
	return nil
end

-- 손님이 서는 앞 공간 예약 (새 소품이 막지 않게): 계산대 · 전자레인지 · ATM · 냉장고 문 · 진열대 통로
local function reserveFront(K: any, mn: Vector3, mx: Vector3, dir: Vector3, depth: number, side: number?)
	local s = side or 0.3
	local a, b
	if math.abs(dir.X) > math.abs(dir.Z) then
		local x = if dir.X > 0 then mx.X else mn.X
		a = V3(math.min(x, x + dir.X * depth), 0.1, mn.Z - s)
		b = V3(math.max(x, x + dir.X * depth), 6.5, mx.Z + s)
	else
		local z = if dir.Z > 0 then mx.Z else mn.Z
		a = V3(mn.X - s, 0.1, math.min(z, z + dir.Z * depth))
		b = V3(mx.X + s, 6.5, math.max(z, z + dir.Z * depth))
	end
	K:reserve(a, b, "front")
end

-- 계산대 손님 쪽 (Props.counterOver 와 같은 계산)
local function counterFace(V: any, g: any): Vector3
	local mn, mx = g.min, g.max
	local alongX = (mx.X - mn.X) >= (mx.Z - mn.Z)
	if alongX then
		local cz = (mn.Z + mx.Z) / 2
		return if (V.door and V.door.z or V.z1) > cz then V3(0, 0, 1) else V3(0, 0, -1)
	else
		local cx = (mn.X + mx.X) / 2
		return if cx > 0 then V3(-1, 0, 0) else V3(1, 0, 0)
	end
end

-- 가장 가까운 벽 쪽의 반대 (방 안쪽)
local function awayFromWall(V: any, r: any): Vector3
	local dl, dr, db = r.min.X - V.x0, V.x1 - r.max.X, r.min.Z - V.z0
	if dl <= dr and dl <= db then
		return V3(1, 0, 0)
	elseif dr <= db then
		return V3(-1, 0, 0)
	end
	return V3(0, 0, 1)
end

---------------------------------------------------------------------------------------------------
-- 2. 상품 (실제 크기: 1 스터드 ≈ 33cm, 사람 키 5.2)
---------------------------------------------------------------------------------------------------

-- k = 모양, w/h/d 크기, cols = 색 후보, lab = 라벨 색 후보
local SKU: { [string]: any } = {
	-- 편의점 과자 · 라면 · 생활
	chips = { k = "bag", w = 0.62, h = 0.86, d = 0.28, cols = { C(222, 38, 38), C(250, 160, 30), C(250, 206, 48), C(36, 96, 190), C(62, 150, 72), C(120, 64, 160), C(112, 64, 40), C(236, 232, 226) } },
	snackBox = { k = "box", w = 0.5, h = 0.6, d = 0.3, stack = 2, cols = { C(196, 28, 40), C(240, 180, 30), C(48, 40, 38), C(130, 70, 40), C(236, 110, 150), C(250, 120, 40) } },
	pringles = { k = "can", w = 0.26, h = 0.82, cols = { C(200, 30, 40), C(40, 140, 60), C(30, 60, 160), C(240, 170, 30) } },
	candy = { k = "pouch", w = 0.38, h = 0.5, d = 0.14, cols = { C(240, 90, 140), C(255, 180, 40), C(120, 200, 80), C(90, 160, 240), C(255, 120, 60) } },
	choco = { k = "box", w = 0.56, h = 0.2, d = 0.34, stack = 3, cols = { C(90, 50, 30), C(196, 30, 40), C(240, 230, 210), C(40, 40, 120) } },
	cupRamen = { k = "cup", w = 0.4, h = 0.38, cols = { C(210, 30, 30), C(232, 96, 30), C(30, 30, 30), C(240, 196, 40), C(120, 70, 40), C(196, 40, 60) } },
	bowlRamen = { k = "bowl", w = 0.56, h = 0.3, cols = { C(210, 30, 30), C(30, 30, 30), C(250, 140, 30), C(60, 120, 60) } },
	ramenPack = { k = "pack", w = 1.0, h = 0.44, d = 0.62, cols = { C(200, 24, 28), C(236, 120, 30), C(30, 30, 30), C(250, 200, 40), C(40, 110, 60) } },
	rice = { k = "box", w = 0.48, h = 0.3, d = 0.42, stack = 3, cols = { C(240, 240, 236), C(250, 236, 200) }, lab = { C(200, 30, 40), C(30, 90, 170) } },
	tissue = { k = "box", w = 0.74, h = 0.34, d = 0.5, stack = 3, cols = { C(246, 246, 244), C(200, 226, 246), C(250, 220, 230) }, lab = { C(60, 140, 220), C(240, 120, 160) } },
	wetwipe = { k = "pouch", w = 0.66, h = 0.24, d = 0.42, cols = { C(250, 250, 250), C(170, 220, 250), C(190, 240, 200) } },
	shampoo = { k = "pump", w = 0.32, h = 0.88, cols = { C(250, 250, 250), C(40, 90, 160), C(240, 160, 190), C(60, 60, 64) } },
	toothbrush = { k = "card", w = 0.24, h = 0.76, d = 0.06, cols = { C(60, 150, 230), C(230, 60, 80), C(80, 190, 120), C(250, 200, 60) } },
	battery = { k = "card", w = 0.32, h = 0.48, d = 0.06, cols = { C(30, 30, 30), C(240, 160, 30), C(196, 30, 40) } },
	cable = { k = "card", w = 0.36, h = 0.62, d = 0.08, cols = { C(250, 250, 250), C(40, 40, 44) } },
	detergent = { k = "jug", w = 0.5, h = 0.9, d = 0.32, cols = { C(40, 120, 210), C(250, 120, 40), C(120, 60, 180) } },
	-- 음료 (냉장)
	pet = { k = "pet", w = 0.25, h = 0.7, cols = { C(200, 16, 30), C(30, 90, 190), C(250, 140, 20), C(60, 160, 70), C(110, 60, 30), C(240, 220, 60) } },
	water = { k = "pet", w = 0.25, h = 0.72, cols = { C(70, 160, 230), C(40, 120, 200) }, clear = true },
	water2l = { k = "pet", w = 0.38, h = 1.02, cols = { C(70, 160, 230), C(40, 120, 200) }, clear = true },
	can = { k = "can", w = 0.24, h = 0.42, cols = { C(200, 16, 30), C(30, 30, 30), C(30, 120, 200), C(240, 200, 30), C(240, 240, 240), C(60, 160, 70) } },
	tallcan = { k = "can", w = 0.26, h = 0.58, cols = { C(200, 16, 30), C(30, 60, 140), C(60, 60, 64) } },
	beer = { k = "can", w = 0.26, h = 0.58, cols = { C(26, 60, 150), C(30, 110, 60), C(200, 160, 50), C(220, 220, 220), C(150, 30, 40) } },
	soju = { k = "soju", w = 0.24, h = 0.76, cols = { C(40, 150, 70) } },
	milk = { k = "carton", w = 0.32, h = 0.66, d = 0.32, cols = { C(246, 246, 244) }, lab = { C(30, 90, 200), C(40, 150, 70), C(240, 120, 160), C(130, 80, 50) } },
	banana = { k = "banana", w = 0.3, h = 0.42, cols = { C(250, 220, 90) } },
	cupCoffee = { k = "cupc", w = 0.3, h = 0.46, cols = { C(110, 70, 40), C(240, 230, 210), C(30, 30, 30), C(200, 40, 40) } },
	yogurt = { k = "cup", w = 0.3, h = 0.28, cols = { C(246, 246, 244), C(250, 200, 220), C(250, 230, 160) } },
	-- 화장품
	toner = { k = "bottle", w = 0.26, h = 0.74, cols = { C(246, 246, 244), C(236, 226, 214), C(200, 226, 240), C(250, 220, 230), C(220, 240, 220) } },
	serum = { k = "dropper", w = 0.22, h = 0.52, cols = { C(180, 120, 60), C(240, 240, 240), C(120, 160, 200) } },
	cream = { k = "jar", w = 0.36, h = 0.26, cols = { C(246, 246, 244), C(30, 30, 30), C(240, 200, 210), C(200, 220, 250), C(196, 164, 98) } },
	sunscreen = { k = "tube", w = 0.22, h = 0.6, cols = { C(250, 250, 250), C(250, 210, 60), C(250, 140, 40), C(90, 180, 230) } },
	lotion = { k = "pump", w = 0.3, h = 0.82, cols = { C(246, 246, 244), C(220, 236, 250), C(250, 236, 220), C(200, 230, 210) } },
	lip = { k = "lip", w = 0.13, h = 0.38, cols = { C(200, 20, 50), C(230, 90, 110), C(180, 70, 60), C(240, 140, 150), C(150, 30, 60), C(220, 120, 100) } },
	cushionC = { k = "compact", w = 0.36, h = 0.12, cols = { C(250, 250, 250), C(30, 30, 30), C(240, 200, 210), C(200, 180, 150) } },
	palette = { k = "box", w = 0.5, h = 0.08, d = 0.36, stack = 3, cols = { C(30, 30, 30), C(240, 220, 210), C(250, 200, 210) } },
	mask = { k = "card", w = 0.42, h = 0.62, d = 0.05, cols = { C(90, 180, 230), C(250, 140, 170), C(120, 200, 120), C(250, 210, 80), C(180, 140, 220), C(246, 246, 244) } },
	hairBig = { k = "pump", w = 0.42, h = 1.02, cols = { C(250, 250, 250), C(30, 30, 30), C(150, 90, 50), C(60, 120, 80), C(230, 200, 150) } },
	perfume = { k = "perfume", w = 0.3, h = 0.5, cols = { C(250, 220, 230), C(220, 240, 250), C(250, 240, 210) } },
	healthB = { k = "box", w = 0.42, h = 0.56, d = 0.3, stack = 2, cols = { C(246, 246, 244), C(250, 240, 220) }, lab = { C(240, 140, 30), C(40, 150, 70), C(200, 30, 40), C(30, 90, 170) } },
	-- 약국
	med = { k = "medbox", w = 0.46, h = 0.32, d = 0.32, stack = 2, cols = { C(250, 250, 250), C(250, 250, 250), C(40, 100, 200), C(250, 210, 40), C(210, 40, 50), C(40, 150, 80), C(250, 140, 30), C(80, 170, 230) }, lab = { C(30, 90, 190), C(200, 30, 40), C(40, 150, 70), C(250, 170, 30), C(250, 250, 250), C(30, 160, 170) } },
	medTall = { k = "medbox", w = 0.34, h = 0.52, d = 0.28, stack = 1, cols = { C(250, 250, 250), C(40, 100, 200), C(250, 210, 40), C(210, 40, 50), C(120, 70, 40) }, lab = { C(30, 90, 190), C(200, 30, 40), C(40, 150, 70), C(250, 250, 250) } },
	ointment = { k = "medbox", w = 0.56, h = 0.18, d = 0.26, stack = 3, cols = { C(250, 250, 250), C(40, 150, 80), C(210, 40, 50) }, lab = { C(200, 30, 40), C(30, 120, 200), C(250, 250, 250) } },
	drinkA = { k = "amber", w = 0.17, h = 0.42, cols = { C(120, 60, 20) } },
	vitamin = { k = "jar", w = 0.36, h = 0.56, cols = { C(250, 250, 250), C(250, 200, 60), C(240, 140, 30), C(200, 40, 40) } },
	ginseng = { k = "box", w = 0.8, h = 0.5, d = 0.4, stack = 2, cols = { C(150, 20, 30), C(40, 30, 30) }, lab = { C(214, 180, 100) } },
	rxBox = { k = "medbox", w = 0.42, h = 0.36, d = 0.34, stack = 3, cols = { C(250, 250, 250), C(236, 240, 244) }, lab = { C(30, 90, 190), C(40, 150, 70), C(200, 30, 40) } },
	rxBottle = { k = "jar", w = 0.3, h = 0.44, cols = { C(160, 90, 30), C(250, 250, 250) } },
	-- 기념품 · 비치
	giftBox = { k = "box", w = 0.96, h = 0.36, d = 0.66, stack = 3, cols = { C(30, 80, 160), C(200, 40, 40), C(240, 200, 60), C(250, 250, 250), C(40, 130, 120) }, lab = { C(250, 250, 250), C(214, 180, 100) } },
	mug = { k = "mug", w = 0.32, h = 0.36, cols = { C(250, 250, 250), C(30, 80, 160), C(240, 200, 60), C(200, 40, 40) } },
	globe = { k = "globe", w = 0.42, h = 0.52, cols = { C(30, 80, 160), C(250, 250, 250), C(40, 40, 44) } },
	plush = { k = "plush", w = 0.46, h = 0.56, cols = { C(250, 250, 250) } },
	towel = { k = "towel", w = 0.9, h = 0.3, d = 0.62, stack = 3, cols = { C(30, 120, 200), C(250, 120, 40), C(240, 200, 60), C(60, 180, 160), C(240, 90, 120) } },
	sunB = { k = "bottle", w = 0.28, h = 0.62, cols = { C(250, 210, 60), C(250, 140, 40), C(250, 250, 250), C(90, 180, 230) } },
	goggle = { k = "card", w = 0.46, h = 0.6, d = 0.08, cols = { C(30, 120, 200), C(250, 120, 40), C(240, 60, 120), C(60, 60, 64) } },
	flip = { k = "flip", w = 0.56, h = 0.12, d = 0.9, cols = { C(30, 120, 200), C(250, 120, 40), C(240, 60, 120), C(250, 210, 60), C(60, 180, 160) } },
	loaf = { k = "loaf", w = 0.62, h = 0.36, d = 0.42, cols = { C(196, 140, 80), C(170, 110, 60), C(214, 170, 110), C(150, 90, 50) } },
	hotteok = { k = "box", w = 0.8, h = 0.3, d = 0.52, stack = 3, cols = { C(250, 200, 60), C(200, 120, 50), C(240, 240, 236) }, lab = { C(200, 40, 40), C(120, 70, 40) } },
	book = { k = "book", w = 0.16, h = 0.86, d = 0.6, cols = { C(30, 80, 160), C(200, 40, 40), C(240, 200, 60), C(40, 130, 90), C(240, 236, 226), C(60, 60, 64) } },
}

-- 범주 = 진열 칸에 쓸 상품 목록 (아래 칸 -> 위 칸 순으로 큰 것 · 무거운 것)
local CATS: { [string]: any } = {
	snack = { low = { "ramenPack", "snackBox", "chips" }, mid = { "chips", "chips", "snackBox", "pringles" }, top = { "chips", "candy", "choco" } },
	ramen = { low = { "ramenPack", "ramenPack", "rice" }, mid = { "cupRamen", "cupRamen", "bowlRamen" }, top = { "cupRamen", "bowlRamen", "rice" } },
	daily = { low = { "tissue", "detergent", "wetwipe" }, mid = { "shampoo", "toothbrush", "wetwipe", "battery" }, top = { "cable", "battery", "toothbrush" } },
	sweets = { low = { "snackBox", "choco" }, mid = { "candy", "choco", "snackBox" }, top = { "candy", "pringles" } },
	drinkRoom = { low = { "water2l", "pet" }, mid = { "pet", "can", "water" }, top = { "can", "cupCoffee" } },
	-- 냉장고 문 칸 (세로 한 칸 = 한 범주)
	dairy = { low = { "milk" }, mid = { "milk", "banana", "yogurt" }, top = { "yogurt", "banana", "cupCoffee" } },
	coffee = { low = { "pet", "cupCoffee" }, mid = { "cupCoffee", "can" }, top = { "cupCoffee", "can" } },
	soda = { low = { "pet" }, mid = { "pet", "can" }, top = { "can", "tallcan" } },
	waterF = { low = { "water2l" }, mid = { "water", "pet" }, top = { "water", "can" } },
	beer = { low = { "beer", "soju" }, mid = { "beer", "tallcan" }, top = { "soju", "beer" } },
	-- 화장품
	skincare = { low = { "lotion", "toner" }, mid = { "toner", "serum", "cream", "lotion" }, top = { "cream", "serum", "sunscreen" } },
	makeup = { low = { "cushionC", "palette", "cream" }, mid = { "lip", "cushionC", "sunscreen", "lip" }, top = { "lip", "palette", "perfume" } },
	hairbody = { low = { "hairBig" }, mid = { "hairBig", "lotion", "shampoo" }, top = { "lotion", "toner" } },
	maskcare = { low = { "healthB", "lotion" }, mid = { "mask", "mask", "sunscreen" }, top = { "mask", "cream" } },
	health = { low = { "healthB", "ginseng" }, mid = { "healthB", "vitamin" }, top = { "vitamin", "healthB" } },
	-- 약국
	otc = { low = { "medTall", "med" }, mid = { "med", "medTall", "ointment", "drinkA" }, top = { "med", "ointment" } },
	supplement = { low = { "ginseng", "healthB" }, mid = { "vitamin", "healthB" }, top = { "vitamin", "med" } },
	rx = { low = { "rxBox", "rxBottle" }, mid = { "rxBox", "rxBottle", "med" }, top = { "rxBox" } },
	dermo = { low = { "lotion" }, mid = { "cream", "toner", "sunscreen" }, top = { "cream", "serum" } },
	-- 기념품 · 비치
	gift = { low = { "giftBox" }, mid = { "mug", "globe", "plush" }, top = { "plush", "mug", "globe" } },
	beachgoods = { low = { "towel", "flip" }, mid = { "sunB", "goggle", "sunscreen" }, top = { "goggle", "sunB" } },
	books = { low = { "book" }, mid = { "book" }, top = { "book" } },
	busan = { low = { "giftBox", "hotteok" }, mid = { "loaf", "hotteok", "giftBox", "mug" }, top = { "loaf", "plush", "globe" } },
}

-- 상품 하나: base = 상품 바닥 가운데, +Z = 정면. lv = 3 (라벨 · 뚜껑까지) | 2 (모양을 결정하는 두 번째 부품까지) | 1 (한 덩어리)
-- 반환 = 만든 파트 수
local function item(K: any, base: CFrame, sku: any, col: Color3, lab: Color3?, h: number, lv: number): number
	local k, w, d = sku.k, sku.w, sku.d or sku.w
	local L = lk(col)
	local n = 1
	local two = lv >= 2
	local three = lv >= 3
	if k == "bag" then
		-- 과자 봉지: 납작한 몸통 + 위 접착 띠 (앞에서 보면 봉지, 옆은 얇게)
		K:box("StSnackBag", V3(w, h * 0.9, d * 0.62), base * CF(0, h * 0.45, 0), L)
		if two then
			K:box("StSnackSeal", V3(w * 1.03, h * 0.09, d * 0.26), base * CF(0, h * 0.93, 0), lk(darker(col, 0.12)))
			n += 1
		end
		if three then
			K:plate("StSnackLogo", w * 0.56, h * 0.28, 0.015, base * CF(0, h * 0.52, d * 0.31), lk(lab or lighter(col, 0.75)))
			n += 1
		end
	elseif k == "box" or k == "medbox" or k == "pack" then
		K:box("StGoodsBox", V3(w, h, d), base * CF(0, h / 2, 0), L)
		local sn = sku.stackN or 1
		if sn > 1 and two then
			-- 쌓인 상자 이음매 (상자 사이 어두운 줄)
			for si = 1, sn - 1 do
				local lum = col.R * 0.3 + col.G * 0.55 + col.B * 0.15
				K:plate("StStackSeam", w * 1.01, 0.04, 0.014, base * CF(0, h * si / sn, d / 2), lk(if lum < 0.35 then lighter(col, 0.45) else darker(col, 0.4)))
				n += 1
			end
			h = h / sn
			base = base * CF(0, h * (sn - 1), 0)
		end
		if k == "medbox" then
			if two then
				K:plate("StMedBand", w * 0.98, h * 0.34, 0.012, base * CF(0, h * 0.36, d / 2), lk(lab or C(30, 90, 190)))
				n += 1
			end
			if three then
				K:plate("StMedLogo", w * 0.36, h * 0.16, 0.014, base * CF(-w * 0.22, h * 0.76, d / 2), lk(darker(lab or C(30, 90, 190), 0.2)))
				n += 1
			end
		elseif k == "pack" then
			if two then
				K:plate("StPackWindow", w * 0.42, h * 0.5, 0.012, base * CF(w * 0.18, h * 0.46, d / 2), lk(C(250, 236, 200)))
				n += 1
			end
			if three then
				K:plate("StPackLogo", w * 0.3, h * 0.3, 0.014, base * CF(-w * 0.26, h * 0.56, d / 2), lk(C(250, 250, 250)))
				n += 1
			end
		elseif two then
			K:plate("StBoxLabel", w * 0.8, h * 0.36, 0.012, base * CF(0, h * 0.56, d / 2), lk(lab or lighter(col, 0.7)))
			n += 1
		end
	elseif k == "can" then
		K:vcyl("StCan", h, w, base * CF(0, h / 2, 0), lk(col, M.Metal))
		if three then
			K:vcyl("StCanTop", 0.03, w * 0.86, base * CF(0, h + 0.012, 0), Look.alu)
			n += 1
		end
	elseif k == "pet" then
		local body = if sku.clear then { c = lighter(col, 0.55), m = M.Glass, t = 0.35, r = 0.1 } else lk(col)
		K:vcyl("StPet", h * 0.8, w, base * CF(0, h * 0.4, 0), body)
		if two then
			K:vcyl("StPetCap", h * 0.14, w * 0.44, base * CF(0, h * 0.87, 0), lk(if sku.clear then C(40, 110, 200) else lighter(col, 0.6)))
			n += 1
		end
		if three then
			K:vcyl("StPetLabel", h * 0.26, w * 1.02, base * CF(0, h * 0.42, 0), lk(if sku.clear then C(40, 130, 220) else lab or lighter(col, 0.8)))
			n += 1
		end
	elseif k == "cup" or k == "bowl" or k == "cupc" then
		K:vcyl("StCup", h, w, base * CF(0, h / 2, 0), L)
		if two then
			K:vcyl("StCupLid", 0.03, w * 1.04, base * CF(0, h + 0.012, 0), lk(if k == "cupc" then C(250, 250, 250) else C(214, 216, 220), M.Metal))
			n += 1
		end
	elseif k == "pouch" then
		K:ell("StPouch", V3(w, h, d), base * CF(0, h / 2, 0), L)
	elseif k == "pump" or k == "bottle" or k == "jug" then
		local bh = h * 0.76
		if k == "jug" then
			K:box("StJug", V3(w, bh, d), base * CF(0, bh / 2, 0), L)
		else
			K:vcyl("StBottle", bh, w, base * CF(0, bh / 2, 0), L)
		end
		if two then
			K:vcyl("StBottleCap", h * 0.14, w * 0.42, base * CF(0, bh + h * 0.07, 0), lk(if k == "bottle" then darker(col, 0.35) else C(240, 240, 240)))
			n += 1
		end
		if three and k == "pump" then
			K:box("StPumpHead", V3(w * 0.26, h * 0.06, w * 0.5), base * CF(0, h * 0.94, w * 0.18), lk(C(240, 240, 240)))
			n += 1
		end
		if three and lab then
			K:plate("StBottleLabel", w * 0.7, bh * 0.4, 0.01, base * CF(0, bh * 0.5, (if k == "jug" then d else w) / 2), lk(lab))
			n += 1
		end
	elseif k == "tube" then
		K:box("StTube", V3(w, h * 0.84, w * 0.56), base * CF(0, h * 0.16 + h * 0.42, 0), L)
		if two then
			K:vcyl("StTubeCap", h * 0.16, w * 0.8, base * CF(0, h * 0.08, 0), lk(darker(col, 0.25)))
			n += 1
		end
	elseif k == "jar" then
		K:vcyl("StJar", h * 0.72, w, base * CF(0, h * 0.36, 0), L)
		if two then
			K:vcyl("StJarLid", h * 0.28, w * 1.02, base * CF(0, h * 0.86, 0), lk(if lab then lab else darker(col, 0.3), if lab then M.SmoothPlastic else M.Metal))
			n += 1
		end
	elseif k == "dropper" then
		K:vcyl("StDropper", h * 0.62, w, base * CF(0, h * 0.31, 0), { c = col, m = M.Glass, t = 0.2, r = 0.1 })
		if two then
			K:vcyl("StDropperCap", h * 0.38, w * 0.42, base * CF(0, h * 0.81, 0), lk(C(30, 30, 30)))
			n += 1
		end
	elseif k == "lip" then
		K:vcyl("StLip", h * 0.62, w, base * CF(0, h * 0.31, 0), lk(C(30, 30, 32), M.Metal))
		if two then
			K:vcyl("StLipColor", h * 0.36, w * 0.7, base * CF(0, h * 0.8, 0), L)
			n += 1
		end
	elseif k == "compact" then
		K:vcyl("StCompact", h, w, base * CF(0, h / 2, 0), L)
	elseif k == "perfume" then
		K:box("StPerfume", V3(w, h * 0.64, w * 0.6), base * CF(0, h * 0.32, 0), { c = col, m = M.Glass, t = 0.25, r = 0.15 })
		if two then
			K:vcyl("StPerfumeCap", h * 0.3, w * 0.5, base * CF(0, h * 0.8, 0), Look.goldMetal)
			n += 1
		end
	elseif k == "card" then
		K:box("StCard", V3(w, h, d), base * CF(0, h / 2, 0), L)
		if three then
			K:plate("StCardBlister", w * 0.7, h * 0.5, 0.03, base * CF(0, h * 0.42, d / 2), { c = C(230, 236, 240), m = M.Glass, t = 0.4 })
			n += 1
		end
	elseif k == "amber" then
		K:vcyl("StAmber", h * 0.78, w, base * CF(0, h * 0.39, 0), { c = col, m = M.Glass, t = 0.15 })
		if two then
			K:vcyl("StAmberCap", h * 0.14, w * 0.62, base * CF(0, h * 0.85, 0), Look.goldMetal)
			n += 1
		end
		if three then
			K:vcyl("StAmberLabel", h * 0.3, w * 1.02, base * CF(0, h * 0.4, 0), lk(C(250, 210, 40)))
			n += 1
		end
	elseif k == "soju" then
		K:vcyl("StSoju", h * 0.66, w, base * CF(0, h * 0.33, 0), { c = col, m = M.Glass, t = 0.2 })
		if two then
			K:vcyl("StSojuNeck", h * 0.3, w * 0.42, base * CF(0, h * 0.8, 0), { c = col, m = M.Glass, t = 0.2 })
			n += 1
		end
		if three then
			K:vcyl("StSojuLabel", h * 0.22, w * 1.02, base * CF(0, h * 0.34, 0), lk(C(250, 250, 250)))
			n += 1
		end
	elseif k == "carton" then
		K:box("StCarton", V3(w, h * 0.84, d), base * CF(0, h * 0.42, 0), L)
		if two then
			K:box("StCartonFin", V3(w, h * 0.14, 0.06), base * CF(0, h * 0.91, 0), L)
			n += 1
		end
		if three or two then
			K:plate("StCartonLabel", w * 0.9, h * 0.34, 0.012, base * CF(0, h * 0.4, d / 2), lk(lab or C(30, 90, 200)))
			n += 1
		end
	elseif k == "banana" then
		K:ell("StBanana", V3(w, h * 0.86, w), base * CF(0, h * 0.43, 0), lk(col))
		if two then
			K:vcyl("StBananaLid", 0.05, w * 0.5, base * CF(0, h * 0.86, 0), lk(C(250, 240, 220)))
			n += 1
		end
	elseif k == "mug" then
		K:vcyl("StMug", h, w, base * CF(0, h / 2, 0), L)
		if two then
			K:box("StMugHandle", V3(0.06, h * 0.6, 0.12), base * CF(w / 2 + 0.03, h * 0.5, 0), L)
			n += 1
		end
		if three then
			K:plate("StMugPrint", w * 0.5, h * 0.4, 0.01, base * CF(0, h * 0.5, w / 2 - 0.005), lk(C(30, 80, 160)))
			n += 1
		end
	elseif k == "globe" then
		K:vcyl("StGlobeBase", h * 0.3, w * 0.86, base * CF(0, h * 0.15, 0), lk(col))
		K:ball("StGlobeGlass", w * 0.82, base * CF(0, h * 0.3 + w * 0.4, 0), { c = C(220, 236, 246), m = M.Glass, t = 0.55, r = 0.2 })
		n += 1
		if three then
			K:box("StGlobeBridge", V3(w * 0.6, 0.06, 0.06), base * CF(0, h * 0.3 + w * 0.36, 0), lk(C(220, 60, 60)))
			n += 1
		end
	elseif k == "plush" then
		-- 부산 갈매기 인형 (흰 몸통 + 머리 + 노란 부리 + 회색 날개)
		K:ell("StGullBody", V3(w, h * 0.62, w * 0.8), base * CF(0, h * 0.31, 0), lk(C(250, 250, 250), M.Fabric))
		K:ball("StGullHead", w * 0.56, base * CF(0, h * 0.72, w * 0.05), lk(C(250, 250, 250), M.Fabric))
		K:ell("StGullBeak", V3(w * 0.18, w * 0.12, w * 0.3), base * CF(0, h * 0.7, w * 0.34), lk(C(250, 190, 40)))
		n += 2
		if three then
			K:ell("StGullWing", V3(w * 1.12, h * 0.24, w * 0.5), base * CF(0, h * 0.4, -w * 0.1), lk(C(170, 180, 190), M.Fabric))
			n += 1
		end
	elseif k == "towel" then
		K:box("StTowel", V3(w, h, d), base * CF(0, h / 2, 0), lk(col, M.Fabric))
		if two then
			K:plate("StTowelStripe", w, h * 0.3, 0.01, base * CF(0, h * 0.5, d / 2), lk(C(250, 250, 250), M.Fabric))
			n += 1
		end
	elseif k == "flip" then
		for _, sx in { -1, 1 } do
			K:ell("StFlipFlop", V3(w * 0.44, h * 0.6, d), base * CF(sx * w * 0.24, h * 0.3, 0), lk(col, M.Rubber))
		end
		n += 1
	elseif k == "loaf" then
		K:ell("StLoaf", V3(w, h, d), base * CF(0, h * 0.5, 0), lk(col, M.SmoothPlastic))
		if two then
			K:box("StLoafBag", V3(w * 1.05, h * 0.6, d * 1.05), base * CF(0, h * 0.3, 0), { c = C(240, 236, 226), m = M.Glass, t = 0.6 })
			n += 1
		end
	elseif k == "book" then
		K:box("StBook", V3(w, h, d), base * CF(0, h / 2, 0), L)
	else
		K:box("StGoods", V3(w, h, d), base * CF(0, h / 2, 0), L)
	end
	return n
end

---------------------------------------------------------------------------------------------------
-- 3. 진열 칸 (맵 선반 찾기 + 상품 채우기 + 가격표)
---------------------------------------------------------------------------------------------------

local FAMILY: { [string]: boolean } = {
	Board = true, Upright = true, PriceRail = true, BackPanel = true, Product = true, Bottle = true, EndPanel = true, EndHeader = true,
	Header = true, WireShelf = true, Body = true, Kick = true, SidePanel = true, FridgeGlow = true, FridgeDoor = true, FridgeLamp = true,
	DoorMullion = true, DoorHandle = true, Goods = true, PosterFrame = true,
}

-- 진열 칸 s: { cf (앞 모서리 가운데, 윗면, +Z = 손님 쪽, +X = 칸 방향), len, depth, clear (위로 빈 높이), rail (가격 레일 있음),
--   key (진열대 면 이름: 같은 면의 칸끼리 같은 범주), level (아래부터 1..), along (면 위 칸 가운데 좌표) }
local function surfFrom(r: any, front: number, alongX: boolean, clear: number, rail: any?): any
	local top = r.max.Y
	if alongX then
		local z = if front > 0 then r.max.Z else r.min.Z
		return { cf = CFrame.fromMatrix(V3(r.c.X, top, z), V3(front, 0, 0), Vector3.yAxis, V3(0, 0, front)), len = r.size.X, depth = r.size.Z, clear = clear, rail = rail, rec = r, key = string.format("x%d:%d", front, math.floor(z * 2 + 0.5)), along = r.c.X }
	end
	local x = if front > 0 then r.max.X else r.min.X
	return { cf = CFrame.fromMatrix(V3(x, top, r.c.Z), V3(0, 0, -front), Vector3.yAxis, V3(front, 0, 0)), len = r.size.Z, depth = r.size.X, clear = clear, rail = rail, rec = r, key = string.format("z%d:%d", front, math.floor(x * 2 + 0.5)), along = r.c.Z }
end

local function overlapXZ(a: any, b: any, pad: number): boolean
	return a.min.X < b.max.X + pad and a.max.X > b.min.X - pad and a.min.Z < b.max.Z + pad and a.max.Z > b.min.Z - pad
end

-- 맵의 선반 판(Board) · 냉장고 와이어 선반(WireShelf) -> 진열 칸 목록
local function mapSurfaces(V: any): { any }
	local out = {}
	local boards: { any } = {}
	for _, nm in { "Board", "WireShelf", "BreadShelf" } do
		for _, r in V.byName[nm] or {} do
			if math.min(r.size.X, r.size.Z) >= 0.5 and math.max(r.size.X, r.size.Z) >= 1.0 and r.size.Y < 0.4 then
				table.insert(boards, r)
			end
		end
	end
	-- 냉장고 바닥 (Kick 윗면 = 와이어 선반 아래 첫 칸)
	local fridgeFloors = {}
	for _, ws in V.byName.WireShelf or {} do
		for _, kk in V.byName.Kick or {} do
			if overlapXZ(ws, kk, 0.1) and kk.max.Y < ws.min.Y then
				local key = string.format("%d:%d", math.floor(kk.c.X), math.floor(kk.c.Z))
				if not fridgeFloors[key] then
					fridgeFloors[key] = true
					-- 와이어 선반과 같은 XZ, 높이만 Kick 윗면
					table.insert(boards, { name = "FridgeFloor", min = V3(ws.min.X, kk.max.Y - 0.05, ws.min.Z), max = V3(ws.max.X, kk.max.Y, ws.max.Z), c = V3(ws.c.X, kk.max.Y - 0.025, ws.c.Z), size = V3(ws.size.X, 0.05, ws.size.Z), fridge = true })
				end
			end
		end
	end
	for _, r in boards do
		local alongX = r.size.X >= r.size.Z
		local depth = if alongX then r.size.Z else r.size.X
		-- 앞쪽: 가격 레일 > 냉장고 문 > 방 안쪽
		local front: number? = nil
		local rail: any = nil
		for _, pr in V.byName.PriceRail or {} do
			if pr.max.Y > r.min.Y - 0.4 and pr.min.Y < r.max.Y + 0.4 then
				if alongX then
					local ov = math.min(pr.max.X, r.max.X) - math.max(pr.min.X, r.min.X)
					local dz = pr.c.Z - r.c.Z
					if ov > 0.5 and math.abs(dz) > depth * 0.3 and math.abs(dz) < depth / 2 + 0.3 then
						front, rail = (if dz > 0 then 1 else -1), pr
					end
				else
					local ov = math.min(pr.max.Z, r.max.Z) - math.max(pr.min.Z, r.min.Z)
					local dx = pr.c.X - r.c.X
					if ov > 0.5 and math.abs(dx) > depth * 0.3 and math.abs(dx) < depth / 2 + 0.3 then
						front, rail = (if dx > 0 then 1 else -1), pr
					end
				end
			end
		end
		local isFridge = r.name == "WireShelf" or r.fridge == true
		if not front and isFridge then
			for _, fd in V.byName.FridgeDoor or {} do
				if overlapXZ(fd, r, 0.6) then
					front = if alongX then (if fd.c.Z > r.c.Z then 1 else -1) else (if fd.c.X > r.c.X then 1 else -1)
				end
			end
		end
		if not front then
			if alongX then
				front = if r.c.Z < (V.z0 + V.z1) / 2 then 1 else -1
			else
				front = if r.c.X < (V.x0 + V.x1) / 2 then 1 else -1
			end
		end
		-- 위로 빈 높이: 바로 위 판 / 천장 쪽 구조물 / 기둥 꼭대기
		local top = r.max.Y
		local clear = math.huge
		for _, q in boards do
			if q ~= r and q.min.Y > top + 0.2 and overlapXZ(q, r, -0.1) then
				clear = math.min(clear, q.min.Y - top)
			end
		end
		if clear == math.huge then
			local cap = math.huge
			local post = 0
			for _, nm in { "Header", "FridgeLamp", "Body", "EndHeader", "Upright", "SidePanel", "BackPanel" } do
				for _, q in V.byName[nm] or {} do
					if overlapXZ(q, r, 0.15) and q.max.Y > top + 0.3 then
						if (nm == "Header" or nm == "FridgeLamp" or nm == "Body") and q.min.Y > top + 0.3 then
							cap = math.min(cap, q.min.Y - top)
						else
							post = math.max(post, q.max.Y - top)
						end
					end
				end
			end
			clear = if cap < math.huge then cap else (if post > 0.3 then math.min(post, 1.5) else 1.3)
		end
		local s = surfFrom(r, front :: number, alongX, math.min(clear, 2.2), rail)
		s.fridge = isFridge
		table.insert(out, s)
	end
	-- 같은 면(key)끼리 높이 순 level
	local byKey: { [string]: { any } } = {}
	for _, s in out do
		local k = s.key .. ":" .. math.floor(s.along + 0.5)
		s.face = k
		byKey[k] = byKey[k] or {}
		table.insert(byKey[k], s)
	end
	for _, l in byKey do
		table.sort(l, function(a, b)
			return a.cf.Position.Y < b.cf.Position.Y
		end)
		for i, s in l do
			s.level = i
			s.levels = #l
		end
	end
	return out
end

-- 선반 위 상품이 피할 장애물 (계산대 등 선반 가족이 아닌 바닥 가구)
local function obstacles(V: any): { any }
	local o = {}
	for _, s in V.solid do
		if not FAMILY[s.name] then
			table.insert(o, s)
		end
	end
	for _, g in V.counters do
		table.insert(o, { min = g.min, max = g.max })
	end
	return o
end

-- 진열 칸들을 진열대(곤돌라 · 벽 베이) 단위로 묶음 -> { min, max, surfs }
local function clusters(surfs: { any }, fridge: boolean?): { any }
	local out = {}
	for _, s in surfs do
		if (s.fridge == true) == (fridge == true) and s.rec then
			local hit = nil
			for _, c in out do
				if overlapXZ(c, s.rec, 0.45) then
					hit = c
					break
				end
			end
			if hit then
				hit.min = hit.min:Min(s.rec.min)
				hit.max = hit.max:Max(s.rec.max)
				table.insert(hit.surfs, s)
			else
				table.insert(out, { min = s.rec.min, max = s.rec.max, surfs = { s } })
			end
		end
	end
	return out
end

local function hitsAny(K: any, list: { any }, mn: Vector3, mx: Vector3): boolean
	for _, b in list do
		if K.overlap(mn, mx, b.min, b.max, 0.02) then
			return true
		end
	end
	return false
end

-- 가격표 · 행사 태그 (레일 앞면). x = 칸 좌표
local function priceTag(K: any, s: any, x: number, promo: string?, theme: any, price: string?)
	local y = if s.railY then s.railY else -0.12
	local z = s.railOff or 0.075
	local at = s.cf * CF(x, y, z)
	K.stTagTexts = K.stTagTexts or 0
	if promo and K.stTagTexts < (theme.maxTagText or 28) then
		K.stTagTexts += 1
		local bg = if promo == "1+1" then theme.promo1 or C(230, 30, 50) elseif promo == "2+1" then theme.promo2 or C(250, 190, 0) else theme.promo3 or C(230, 30, 50)
		local fg = if promo == "2+1" then INK else WHITE
		txt(K, "StPromoTag", 0.42, 0.22, at, promo, fg, bg, { d = 0.02, font = Enum.Font.GothamBlack })
	elseif price and K.stTagTexts < (theme.maxTagText or 28) and K.detail == "high" then
		K.stTagTexts += 1
		txt(K, "StPriceTag", 0.4, 0.2, at, price, INK, C(252, 252, 248), { d = 0.02, font = Enum.Font.GothamBold })
	else
		K:plate("StPriceTag", 0.36, 0.18, 0.015, at, lk(C(252, 252, 248)))
		if K.detail ~= "low" then
			K:plate("StPriceInk", 0.22, 0.06, 0.017, at * CF(0.03, -0.03, 0), lk(INK))
		end
	end
end

local PRICES = { "1,200", "1,500", "1,700", "1,800", "2,000", "2,200", "2,500", "2,800", "3,000", "3,500", "4,500" }

-- 칸 하나 채우기. cat = CATS 이름, rng, theme (태그 색 · 행사 비율),
-- opt { lvl (상품 디테일 3/2/1), obst, gap, back (뒤쪽 재고 덩어리), noTags, facing, scale, spread (묶음 사이 여유 배수) }
local function fillSurf(K: any, s: any, catName: string, rng: () -> number, theme: any, opt: any?): number
	local o: any = opt or {}
	local cat = CATS[catName] or CATS.snack
	local lv = s.level or 1
	local list = if lv <= 1 then cat.low elseif s.levels and lv >= s.levels then cat.top else cat.mid
	local dl = o.lvl or (if K.detail == "high" then 3 elseif K.detail == "mid" then 2 else 1)
	local a, b = -s.len / 2 + 0.1, s.len / 2 - 0.1
	local x = a
	local used = 0
	local gap = o.gap or 0.04
	local scale = o.scale or 1
	local groups = 0
	while x < b - 0.15 do
		local sku = SKU[pick(rng, list)]
		local w = sku.w * scale
		local d = math.min((sku.d or sku.w) * scale, s.depth - 0.12)
		-- 상자류는 칸 깊이만큼 (한 줄 재고가 통째로 보임) → 뒤 재고 덩어리 대신 라벨에 파트를 씀
		local deep = (sku.k == "box" or sku.k == "medbox" or sku.k == "pack" or sku.k == "towel") and o.back ~= false
		if deep then
			d = math.max(d, s.depth - 0.16)
		end
		local h = math.min(sku.h * scale * (0.92 + rng() * 0.12), s.clear - 0.12)
		if h < 0.12 or d < 0.04 then
			break
		end
		local col: Color3 = pick(rng, sku.cols)
		local lab: Color3? = if sku.lab then pick(rng, sku.lab) else nil
		local n = math.max(1, math.floor((o.facing or 2) + rng() * 3))
		if sku.k == "pack" or (sku.k == "box" and w > 0.8) then
			n = math.max(1, n - 1)
		end
		-- 상자류는 칸 높이만큼 2~3단 쌓기 (한 덩어리 + 이음매)
		local stackN = 1
		if sku.stack then
			stackN = math.clamp(math.floor((s.clear - 0.14) / (h + 0.015)), 1, sku.stack)
			h = h * stackN
		end
		local gx0 = x
		local placed = 0
		local sk = setmetatable({ w = w, d = d, stackN = stackN }, { __index = sku })
		for _ = 1, n do
			if x + w > b then
				break
			end
			local cx = x + w / 2
			local base = s.cf * CF(cx, 0.005, -d / 2 - 0.05)
			local mn, mx = K.laabb(base * CF(0, h / 2, 0), V3(w, h, d))
			if o.obst and hitsAny(K, o.obst, mn, mx) then
				x += w + gap
				continue
			end
			used += item(K, base, sk, col, lab, h, dl)
			placed += 1
			x += w + gap
		end
		if placed > 0 then
			groups += 1
			local gw = x - gx0 - gap
			-- 뒤쪽 재고 (같은 상품 줄이 안쪽으로 이어진 느낌)
			if dl >= 2 and o.back ~= false and not deep and s.depth - d > 0.35 then
				local bd = s.depth - d - 0.2
				local bh = h * 0.9
				local mnb, mxb = K.laabb(s.cf * CF(gx0 + gw / 2, bh / 2, -d - 0.1 - bd / 2), V3(gw, bh, bd))
				if not (o.obst and hitsAny(K, o.obst, mnb, mxb)) then
					local bl = if sku.k == "can" or sku.k == "pet" or sku.k == "soju" or sku.k == "amber" then lk(darker(col, 0.25), if sku.k == "can" then M.Metal else M.SmoothPlastic) else lk(darker(col, 0.18))
					if sku.clear then
						bl = { c = lighter(col, 0.4), m = M.Glass, t = 0.45 }
					end
					K:box("StBackStock", V3(gw, bh, bd), s.cf * CF(gx0 + gw / 2, 0.005 + bh / 2, -d - 0.1 - bd / 2), bl)
					used += 1
				end
			end
			if s.rail and not o.noTags and (dl >= 2 or groups % 2 == 1) then
				local r = rng()
				local p11, p21, ps = theme.p11 or 0.12, theme.p21 or 0.12, theme.pSale or 0
				local promo = if r < p11 then "1+1" elseif r < p11 + p21 then "2+1" elseif r < p11 + p21 + ps then (theme.saleText or "SALE") else nil
				priceTag(K, s, gx0 + gw / 2, promo, theme, if theme.prices then pick(rng, theme.prices) else pick(rng, PRICES))
				used += if promo or dl >= 3 then 1 else 2
			end
		end
		x += (o.groupGap or 0.08) * (o.spread or 1) + (if (o.spread or 1) > 1 then w * ((o.spread or 1) - 1) else 0)
	end
	return used
end

-- 진열 예약: 구조물(진열장 · 아일랜드)을 다 만든 뒤 runFill 이 매장 상품 예산에 맞춰 디테일 단계를 정해 채움
local function queueFill(K: any, s: any, cat: string, seed: string, theme: any, opt: any?)
	K.stQueue = K.stQueue or {}
	table.insert(K.stQueue, { s = s, cat = cat, seed = seed, theme = theme or {}, opt = opt or {} })
end

-- 스터드당 대략 파트 수 (단계 3 / 2 / 1)
local PPS = { 6.6, 4.2, 2.4 }

local function runFill(K: any, budget: number): number
	local q = K.stQueue or {}
	K.stQueue = {}
	local total = 0
	for _, e in q do
		total += e.s.len * (e.opt.weight or 1)
	end
	local used = 0
	local maxLv = if K.detail == "high" then 3 elseif K.detail == "mid" then 2 else 1
	for _, e in q do
		local wl = e.s.len * (e.opt.weight or 1)
		local per = (budget - used) / math.max(total, 1)
		local lv = if per >= PPS[1] then 3 elseif per >= PPS[2] then 2 else 1
		lv = math.min(lv, maxLv, e.opt.maxLvl or 3)
		local o = table.clone(e.opt)
		o.lvl = lv
		if per < PPS[3] * 0.9 then
			o.spread = math.clamp(PPS[3] / math.max(per, 0.5), 1, 2.2)
		end
		local n = 0
		K:free(function()
			n = fillSurf(K, e.s, e.cat, mkRng(e.seed), e.theme, o)
		end)
		used += n
		total -= wl
	end
	K.stGoodsParts = (K.stGoodsParts or 0) + used
	return used
end

-- GwShop: 원래 Product 상자 안쪽만 (같은 범위) 작은 실제 상품 여러 개로 다시 만들기
local function fillInside(K: any, r: any, front: Vector3, catName: string, rng: () -> number, lv: number): number
	local alongX = math.abs(front.Z) > math.abs(front.X)
	local len = if alongX then r.size.X else r.size.Z
	local dep = if alongX then r.size.Z else r.size.X
	local h = r.size.Y
	local p = V3(r.c.X, r.min.Y, r.c.Z) + front * (dep / 2)
	local xv = Vector3.yAxis:Cross(front).Unit
	local cf = CFrame.fromMatrix(p, xv, Vector3.yAxis, front)
	local cat = CATS[catName]
	local sku = SKU[pick(rng, cat.mid)]
	local n = math.max(1, math.floor(len / math.max(0.18, sku.w) + 0.2))
	local w = len / n
	local col: Color3 = pick(rng, sku.cols)
	local lab: Color3? = if sku.lab then pick(rng, sku.lab) else nil
	local used = 0
	local hh = math.min(h, sku.h * 1.15)
	for i = 1, n do
		local base = cf * CF(-len / 2 + w * (i - 0.5), 0.005, -dep / 2)
		used += item(K, base, setmetatable({ w = w * 0.92, d = dep * 0.95 }, { __index = sku }), col, lab, hh, lv)
	end
	return used
end

---------------------------------------------------------------------------------------------------
-- 4. 공용 진열 · 사인 소품
---------------------------------------------------------------------------------------------------

-- 포스터 / POP (dcf 표면, 벽에서 0.06 띄움): 바탕 + 윗띠 + 제목 + 본문
local function poster(K: any, dcf: CFrame, w: number, h: number, title: string, body: string?, bg: Color3, fg: Color3, band: Color3?, bandFg: Color3?, o: any?)
	local oo: any = o or {}
	local d0 = dcf * CF(0, 0, oo.off or 0.06)
	if oo.frame ~= false then
		K:plate("StPosterFrame", w + 0.08, h + 0.08, 0.03, d0, oo.frameL or lk(C(240, 240, 238)))
	end
	K:plate("StPoster", w, h, 0.035, d0, lk(bg))
	local th = if body then h * (oo.titleH or 0.3) else h
	if band then
		K:plate("StPosterBand", w, th, 0.04, d0 * CF(0, h / 2 - th / 2, 0), lk(band))
	end
	txt(K, "StPosterTitle", w * 0.92, th * 0.82, d0 * CF(0, h / 2 - th / 2, 0.041), title, bandFg or fg, nil, { font = oo.font or Enum.Font.GothamBlack })
	if body then
		txt(K, "StPosterBody", w * 0.88, (h - th) * 0.86, d0 * CF(0, -th / 2, 0.036), body, fg, nil, { font = oo.bodyFont or Enum.Font.GothamBold })
	end
end

-- 천장에 매다는 양면 POP (와이어 2개 + 판 + 양면 글자)
local function hangSign(K: any, x: number, z: number, w: number, h: number, yBot: number, rotY: number, front: string, back: string?, bg: Color3, fg: Color3, edge: Color3?): boolean
	local V = K.V
	local cf = CF(x, yBot + h / 2, z) * ANG(0, rotY, 0)
	local mn, mx = K.laabb(cf, V3(w + 0.1, h, 0.2))
	local mnW, mxW = mn, V3(mx.X, V.H, mx.Z)
	if K:hitsKeep(mnW, mxW) then
		return false
	end
	-- 와이어 윗점이 에어컨 · 조명 · CCTV 위에 걸리지 않게 (T-bar 사이는 괜찮음)
	for _, sx in { -1, 1 } do
		local a = (cf * CF(sx * w * 0.38, h / 2, 0)).Position
		for _, r in V.parts do
			local nm = r.name
			if (nm == "CassetteAC" or nm == "ACVanes" or nm == "Troffer" or nm == "Downlight" or nm == "CCTV" or nm == "CCTVMount" or nm == "LightPanel" or nm == "LightFrame" or nm == "TrackRail" or nm == "ShopLight") and a.X > r.min.X - 0.25 and a.X < r.max.X + 0.25 and a.Z > r.min.Z - 0.25 and a.Z < r.max.Z + 0.25 then
				return false
			end
		end
		for _, q in K.ceilUsed or {} do
			if math.abs(q.X - a.X) < 0.5 and math.abs(q.Z - a.Z) < 0.5 then
				return false
			end
		end
	end
	for _, r in V.hang do
		if K.overlap(mn - V3(0, 0.2, 0), mx + V3(0, 0.3, 0), r.min, r.max, 0.05) then
			return false
		end
	end
	if mapBlocked(K, mn, mx) then
		return false
	end
	for _, sx in { -1, 1 } do
		local a = (cf * CF(sx * w * 0.38, h / 2, 0)).Position
		K:seg("StHangWire", a, V3(a.X, V.H - 0.02, a.Z), 0.03, Look.chrome)
	end
	K:box("StHangBoard", V3(w, h, 0.06), cf, lk(bg))
	if edge then
		K:box("StHangEdge", V3(w + 0.04, 0.1, 0.08), cf * CF(0, h / 2 - 0.05, 0), lk(edge))
		K:box("StHangEdge", V3(w + 0.04, 0.1, 0.08), cf * CF(0, -h / 2 + 0.05, 0), lk(edge))
	end
	txt(K, "StHangText", w * 0.92, h * 0.74, cf * CF(0, -0.02, 0.031), front, fg, nil, { font = Enum.Font.GothamBlack, d = 0.01 })
	txt(K, "StHangText", w * 0.92, h * 0.74, cf * CF(0, -0.02, -0.031) * ANG(0, PI, 0), back or front, fg, nil, { font = Enum.Font.GothamBlack, d = 0.01 })
	Common.useCeil(K, x, z)
	return true
end

-- 매다는 POP: 자리가 막히면 조금씩 옮겨 봄
local function hangSignNear(K: any, x: number, z: number, w: number, h: number, yBot: number, rotY: number, front: string, back: string?, bg: Color3, fg: Color3, edge: Color3?): boolean
	for _, o in { V3(0, 0, 0), V3(0.8, 0, 0), V3(-0.8, 0, 0), V3(0, 0, 0.9), V3(0, 0, -0.9), V3(1.6, 0, 0), V3(-1.6, 0, 0), V3(0, 0, 1.8), V3(0, 0, -1.8), V3(1.2, 0, 1.2), V3(-1.2, 0, -1.2) } do
		if hangSign(K, x + o.X, z + o.Z, w, h, yBot, rotY, front, back, bg, fg, edge) then
			return true
		end
	end
	return false
end

-- 디지털 사이니지 (벽걸이 화면): 자동으로 넘어가고, 프롬프트로 직접 넘김. frames = { { text, c } }
local function didScreen(K: any, dcf: CFrame, w: number, frames: { any }, object: string, frameL: any?)
	local h = w * 9 / 16
	K:plate("StDIDMount", w * 0.3, h * 0.3, 0.1, dcf, Look.blackMetal)
	K:plate("StDIDBezel", w + 0.14, h + 0.14, 0.12, dcf * CF(0, 0, 0.1), frameL or Look.black)
	-- 화면 = 불투명 배경 글자판 (밝기 1.3): 화면 색 · 글자를 같이 바꿈
	local scr, label = txt(K, "StDIDScreen", w, h, dcf * CF(0, 0, 0.22), frames[1].text, WHITE, frames[1].c, { glow = 1.3, font = Enum.Font.GothamBlack, d = 0.02 })
	K:plate("StDIDGlass", w, h, 0.005, dcf * CF(0, 0, 0.243), { c = C(220, 230, 240), m = M.Glass, t = 0.9, r = 0.25 })
	K:plate("StDIDLed", 0.06, 0.06, 0.01, dcf * CF(w / 2 - 0.05, -h / 2 - 0.04, 0.225), Look.ledGreen)
	local idx = 0
	local last = -1
	local function show(i: number)
		local f = frames[i]
		if label.Parent then
			label.Text = f.text
			label.BackgroundColor3 = f.c
		end
	end
	Interact.anim(K, function(t)
		local i = (math.floor(t / 6) + idx) % #frames + 1
		if i ~= last then
			last = i
			show(i)
		end
	end)
	promptOn(K, { scr }, {
		action = "화면 넘기기",
		object = object,
		fn = function()
			idx += 1
			last = -1
		end,
	})
	return scr
end

-- 벽에 붙은 진열장 (새 바닥 소품): 벽 wn 의 u 중심, 폭 len. 반환 = 진열 칸 목록
local function wallUnit(K: any, pcf: CFrame, len: number, d: number, h: number, o: any)
	local body = o.body or Look.white
	local backL = o.back or lk(C(236, 236, 232))
	local shelfL = o.shelf or lk(C(246, 246, 244))
	local railL = o.rail or lk(C(250, 250, 248))
	local n = o.levels or 5
	-- 바닥 받침 · 뒤판 · 옆판
	K:box("StUnitKick", V3(len - 0.1, 0.42, d - 0.12), pcf * CF(0, 0.21, 0.0), o.kick or Look.charcoal)
	K:box("StUnitBack", V3(len, h, 0.12), pcf * CF(0, h / 2, -d / 2 + 0.06), backL)
	if o.peg then
		-- 유공보드 느낌 (얇은 가로 줄)
		for yy = 1.2, h - 0.4, 0.9 do
			K:box("StUnitPegLine", V3(len - 0.3, 0.025, 0.02), pcf * CF(0, yy, -d / 2 + 0.13), lk(darker(backL.c, 0.08)))
		end
	end
	for _, sx in { -1, 1 } do
		K:box("StUnitSide", V3(0.12, h, d), pcf * CF(sx * (len / 2 - 0.06), h / 2, 0), body)
	end
	-- 머리 간판 (라이트 박스)
	local hd = K:box("StUnitHeader", V3(len, 0.62, 0.36), pcf * CF(0, h + 0.31, -d / 2 + 0.18), o.headL or lk(C(250, 250, 250)))
	K:plate("StUnitHeaderLine", len, 0.06, 0.37, pcf * CF(0, h + 0.03, -d / 2) * ANG(0, 0, 0), o.lineL or lk(C(30, 30, 30)))
	if o.title then
		txt(K, "StUnitTitle", len * 0.9, 0.46, pcf * CF(0, h + 0.31, -d / 2 + 0.365), o.title, o.titleFg or INK, nil, { font = Enum.Font.GothamBlack, glow = o.glow })
	end
	local surfs = {}
	local y0 = 0.42
	local top = h - 0.25
	local stepY = (top - y0) / n
	for i = 1, n do
		local y = y0 + (i - 1) * stepY
		local sd = if i == 1 then d - 0.14 else d - 0.2 - (i - 1) * 0.06
		if i > 1 then
			K:box("StUnitShelf", V3(len - 0.24, 0.07, sd), pcf * CF(0, y - 0.035, -d / 2 + 0.12 + sd / 2), shelfL)
		end
		local zf = -d / 2 + 0.12 + sd
		K:box("StUnitRail", V3(len - 0.24, 0.2, 0.04), pcf * CF(0, y - 0.07, zf + 0.02), railL)
		local cf = pcf * CF(0, y, zf)
		table.insert(surfs, { cf = CFrame.fromMatrix(cf.Position, cf.XVector, cf.YVector, cf.ZVector), len = len - 0.3, depth = sd - 0.05, clear = stepY - 0.12, rail = true, railY = -0.07, railOff = 0.045, level = i, levels = n })
	end
	if o.led ~= false then
		local strip = K:box("StUnitLED", V3(len - 0.3, 0.04, 0.06), pcf * CF(0, h - 0.06, -d / 2 + 0.4), Look.lampCool)
		if o.light then
			K:light(strip, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 7, Brightness = 0.5, Angle = 120, Color = Look.coolLight })
		end
	end
	return surfs, hd
end

-- 양면 진열대 (새 아일랜드): pcf 바닥 가운데, +X = 긴 방향. 반환 = 진열 칸
local function island(K: any, pcf: CFrame, len: number, w: number, h: number, o: any): { any }
	local body = o.body or Look.white
	local n = o.levels or 3
	K:box("StIslandKick", V3(len - 0.1, 0.4, w - 0.1), pcf * CF(0, 0.2, 0), o.kick or Look.charcoal)
	K:box("StIslandSpine", V3(len, h, 0.14), pcf * CF(0, h / 2, 0), o.spine or body)
	for _, sx in { -1, 1 } do
		K:box("StIslandEnd", V3(0.14, h, w), pcf * CF(sx * (len / 2 - 0.07), h / 2, 0), body)
	end
	if o.topL then
		K:box("StIslandTop", V3(len + 0.1, 0.08, w + 0.1), pcf * CF(0, h + 0.04, 0), o.topL)
	end
	local surfs = {}
	local y0 = 0.4
	local stepY = (h - 0.2 - y0) / n
	local sd = w / 2 - 0.12
	for _, side in { 1, -1 } do
		local face = pcf * ANG(0, if side > 0 then 0 else PI, 0)
		for i = 1, n do
			local y = y0 + (i - 1) * stepY
			if i > 1 then
				K:box("StIslandShelf", V3(len - 0.3, 0.07, sd), face * CF(0, y - 0.035, 0.07 + sd / 2), o.shelf or lk(C(246, 246, 244)))
			end
			K:box("StIslandRail", V3(len - 0.3, 0.2, 0.04), face * CF(0, y - 0.07, 0.07 + sd + 0.02), o.rail or lk(C(250, 250, 248)))
			local cf = face * CF(0, y, 0.07 + sd)
			table.insert(surfs, { cf = cf, len = len - 0.4, depth = sd - 0.04, clear = stepY - 0.1, rail = true, railY = -0.07, railOff = 0.045, level = i, levels = n, side = side })
		end
	end
	return surfs
end

-- 낮은 행사 테이블 (창가 · 입구 쪽, 높이 3.3 아래): 상판 + 계단식 아크릴 단 2개 + POP. 반환 = 진열 칸
local function promoTable(K: any, pcf: CFrame, w: number, d: number, topL: any, popTitle: string, popBody: string, popBg: Color3)
	local th = 2.3
	K:box("StPromoTop", V3(w, 0.12, d), pcf * CF(0, th - 0.06, 0), topL)
	K:box("StPromoBody", V3(w - 0.3, th - 0.4, d - 0.3), pcf * CF(0, (th - 0.4) / 2 + 0.28, 0), lk(C(236, 236, 232)))
	K:box("StPromoKick", V3(w - 0.4, 0.28, d - 0.4), pcf * CF(0, 0.14, 0), Look.charcoal)
	local surfs = {}
	-- 앞 · 뒤 (양쪽 손님) 단
	for _, side in { 1, -1 } do
		local f = pcf * ANG(0, if side > 0 then 0 else PI, 0)
		K:box("StPromoRiser", V3(w - 0.4, 0.34, d / 2 - 0.5), f * CF(0, th + 0.17, -(d / 2 - 0.5) / 2 - 0.05), { c = C(240, 244, 246), m = M.Glass, t = 0.25 })
		table.insert(surfs, { cf = f * CF(0, th, d / 2 - 0.05), len = w - 0.4, depth = 0.45, clear = 0.75, rail = false, level = 2, levels = 3 })
		table.insert(surfs, { cf = f * CF(0, th + 0.34, -0.05), len = w - 0.6, depth = d / 2 - 0.55, clear = 0.62, rail = false, level = 3, levels = 3 })
	end
	-- POP 꽂이 (가운데, 높이 3.3 아래)
	K:box("StPromoPopFoot", V3(0.5, 0.06, 0.3), pcf * CF(0, th, 0), Look.chrome)
	K:box("StPromoPopPole", V3(0.04, 0.4, 0.04), pcf * CF(0, th + 0.2, 0), Look.chrome)
	local pd = pcf * CF(0, th + 0.62, 0)
	txt(K, "StPromoPop", 1.4, 0.5, pd, popTitle, WHITE, popBg, { d = 0.02, font = Enum.Font.GothamBlack })
	txt(K, "StPromoPop", 1.4, 0.5, pd * ANG(0, PI, 0), popBody, WHITE, popBg, { d = 0.02, font = Enum.Font.GothamBold })
	return surfs
end

-- 장바구니 더미 (입구 옆)
local function basketStack(K: any, pcf: CFrame, col: Color3, n: number, label: string?)
	local bw, bd, bh = 1.3, 0.9, 0.62
	for i = 0, n - 1 do
		local y = i * 0.2
		if i == 0 then
			K:box("StBasket", V3(bw, bh, bd), pcf * CF(0, y + bh / 2, 0), lk(col, M.Plastic))
		else
			K:box("StBasketRim", V3(bw + 0.04, 0.08, bd + 0.04), pcf * CF(0, y + bh - 0.04, 0), lk(darker(col, 0.15), M.Plastic))
		end
	end
	local topY = (n - 1) * 0.2 + bh
	K:box("StBasketBody", V3(bw - 0.02, topY - bh + 0.02, bd - 0.02), pcf * CF(0, bh + (topY - bh) / 2 - 0.01, 0), lk(col, M.Plastic))
	K:box("StBasketInside", V3(bw - 0.16, 0.04, bd - 0.16), pcf * CF(0, topY - 0.06, 0), lk(darker(col, 0.45), M.Plastic))
	for _, sx in { -1, 1 } do
		K:bar("StBasketHandle", (pcf * CF(sx * 0.42, topY, 0)).Position, (pcf * CF(sx * 0.12, topY + 0.32, 0)).Position, 0.06, 0.06, lk(C(30, 30, 30), M.Plastic))
	end
	K:box("StBasketHandleTop", V3(0.3, 0.06, 0.06), pcf * CF(0, topY + 0.32, 0), lk(C(30, 30, 30), M.Plastic))
	if label then
		txt(K, "StBasketLabel", bw * 0.7, 0.24, pcf * CF(0, bh * 0.5, bd / 2 + 0.005), label, WHITE, nil, { font = Enum.Font.GothamBlack, d = 0.01 })
	end
end

-- 바닥 스탠드형 POP (A4 꽂이 기둥)
local function popStand(K: any, pcf: CFrame, title: string, body: string, bg: Color3, fg: Color3)
	K:disc("StPopBase", 1.0, 0.06, pcf * CF(0, 0.03, 0), Look.chrome)
	K:vcyl("StPopPole", 3.4, 0.08, pcf * CF(0, 1.75, 0), Look.chrome)
	local d = pcf * CF(0, 4.1, 0.06)
	K:plate("StPopFrame", 1.5, 1.9, 0.04, d, Look.chrome)
	K:plate("StPopCard", 1.4, 1.8, 0.05, d, lk(bg))
	txt(K, "StPopTitle", 1.3, 0.5, d * CF(0, 0.55, 0.051), title, fg, nil, { font = Enum.Font.GothamBlack })
	txt(K, "StPopBody", 1.3, 1.1, d * CF(0, -0.3, 0.051), body, fg, nil, { font = Enum.Font.GothamBold })
end

-- 선반 날개 POP (선반 레일에서 튀어나온 작은 깃발)
local function wobbler(K: any, s: any, x: number, text: string, bg: Color3, fg: Color3)
	local at = s.cf * CF(x, (s.railY or -0.12) - 0.02, (s.railOff or 0.075) + 0.25) * ANG(0, PI / 2, 0)
	K:box("StWobblerArm", V3(0.5, 0.03, 0.03), s.cf * CF(x, (s.railY or -0.12), (s.railOff or 0.075) + 0.25 * 0.5) * ANG(0, PI / 2, 0), Look.chrome)
	K:box("StWobbler", V3(0.04, 0.5, 0.5), at * CF(0, 0, 0), lk(bg))
	txt(K, "StWobblerText", 0.44, 0.44, at * CF(0.025, 0, 0) * ANG(0, PI / 2, 0), text, fg, nil, { font = Enum.Font.GothamBlack, d = 0.01 })
	txt(K, "StWobblerText", 0.44, 0.44, at * CF(-0.025, 0, 0) * ANG(0, -PI / 2, 0), text, fg, nil, { font = Enum.Font.GothamBlack, d = 0.01 })
end

---------------------------------------------------------------------------------------------------
-- 5. 브랜드 · 세부 유형
---------------------------------------------------------------------------------------------------

local BRANDS: { [string]: any } = {
	gs25 = { ssid = "GS25_FREE_WiFi", name = "GS25", main = C(0, 118, 206), sub = C(0, 178, 226), accent = C(122, 190, 64), dark = C(10, 40, 80), basket = C(0, 118, 206), coffee = "카페25", pb = "유어스", parcel = "GS25 반값택배 · 택배 접수", app = "우리동네GS 앱 픽업", promo1 = C(232, 30, 60), promo2 = C(250, 196, 0), slogan = "LIFESTYLE PLATFORM" },
	cu = { ssid = "CU_Free_WiFi", name = "CU", main = C(108, 44, 150), sub = C(160, 206, 60), accent = C(160, 206, 60), dark = C(48, 18, 70), basket = C(108, 44, 150), coffee = "GET 커피", pb = "PB 헤이루", parcel = "CU 알뜰택배 · 택배 접수", app = "포켓CU 앱 픽업", promo1 = C(232, 30, 60), promo2 = C(160, 206, 60), slogan = "가까운 행복 CU" },
	seven = { ssid = "7-ELEVEn_Free", name = "7-ELEVEn", main = C(0, 130, 96), sub = C(246, 132, 32), accent = C(232, 36, 52), dark = C(0, 60, 44), basket = C(0, 130, 96), coffee = "세븐카페", pb = "세븐셀렉트", parcel = "세븐일레븐 택배 접수", app = "세븐앱 픽업", promo1 = C(232, 36, 52), promo2 = C(246, 132, 32), slogan = "Always Open 24" },
	emart24 = { ssid = "emart24_WiFi", name = "emart24", main = C(255, 184, 28), sub = C(60, 60, 62), accent = C(232, 40, 50), dark = C(40, 40, 42), basket = C(255, 184, 28), coffee = "이프레소", pb = "아임e", parcel = "emart24 택배 접수", app = "emart24 앱 픽업", promo1 = C(232, 40, 50), promo2 = C(255, 184, 28), slogan = "Everyday emart24" },
	indie = { ssid = "STORE_WiFi_5G", name = "마트", main = C(214, 40, 44), sub = C(30, 70, 150), accent = C(250, 196, 0), dark = C(60, 20, 20), basket = C(214, 40, 44), coffee = "원두커피", pb = "알뜰상품", parcel = "택배 접수", app = "전화 주문 배달", promo1 = C(214, 40, 44), promo2 = C(250, 196, 0), slogan = "동네 마트" },
}

local OY = { main = C(154, 194, 27), dark = C(28, 34, 30), sub = C(230, 40, 120), white = C(250, 250, 248) }
local PH = { main = C(10, 138, 58), dark = C(10, 70, 40), sub = C(0, 150, 200), white = C(250, 252, 250) }

-- 매장 상품 파트 예산 (넓이 비례, 남은 파트 여유 안에서)
local function goodsBudget(K: any, V: any, mul: number?): number
	local b = math.clamp(V.W * V.D * 1.5 * (mul or 1), 300, 950)
	local room = (K.maxParts or 2600) - #K.parts - 520
	return math.max(160, math.min(b, room))
end

local function subtype(V: any): (string, string)
	local raw = tostring(V.name or "")
	local n = string.upper(raw)
	local m = tostring(V.menu or "")
	local function has(s: string): boolean
		return string.find(n, s, 1, true) ~= nil
	end
	if V.type == "pharmacy" then
		return "pharmacy", if V.kind == "gwshop" then "gw" else "street"
	end
	if V.type == "cvs" then
		if has("GS25") or has("GS 25") then
			return "cvs", "gs25"
		elseif n == "CU" or string.sub(n, 1, 3) == "CU " or has(" CU") or has("씨유") then
			return "cvs", "cu"
		elseif has("7-ELEVEN") or has("세븐일레븐") or has("7ELEVEN") then
			return "cvs", "seven"
		elseif has("EMART24") or has("이마트24") then
			return "cvs", "emart24"
		end
		return "cvs", "indie"
	end
	if m == "cosmetics" or has("OLIVE") or has("올리브") or has("LALAVLA") or has("화장품") or V:has("Tester") > 0 then
		return "retail", "cosmetics"
	elseif m == "beach" or has("비치") or has("튜브") or has("돗자리") or has("폭죽") or has("BEACH") then
		return "retail", "beach"
	elseif m == "souvenir" or has("기념품") or has("BUSAN") or has("ORANGE") or has("SOUVENIR") then
		return "retail", "souvenir"
	elseif m == "flower" or has("꽃") or has("FLOWER") then
		return "retail", "flower"
	elseif m == "book" or has("서점") or has("책") or has("BOOK") then
		return "retail", "book"
	end
	if V:has("Float") > 0 then
		return "retail", "beach"
	elseif V:has("Shirt") > 0 or V:has("Goods") > 0 then
		return "retail", "souvenir"
	end
	return "retail", "generic"
end
T.subtype = subtype

---------------------------------------------------------------------------------------------------
-- 6. 편의점
---------------------------------------------------------------------------------------------------

-- 담배 진열장: 맵 CigCabinet/PackFace/CigHeader 와 같은 범위에 다시 (직원 자리 keep 안이라 free)
local CIG_COLS = { C(250, 250, 250), C(30, 60, 140), C(200, 30, 40), C(30, 30, 34), C(120, 170, 220), C(214, 180, 100), C(90, 60, 140), C(40, 120, 90), C(236, 236, 230), C(160, 30, 50), C(60, 140, 200), C(246, 200, 60) }

local function cigCabinet(K: any, V: any, B: any, rng: () -> number)
	local cab = V:first("CigCabinet")
	if not cab then
		return
	end
	local pf = V:first("PackFace")
	local hd = V:first("CigHeader")
	local alongX = cab.size.X >= cab.size.Z
	local face: Vector3
	if pf then
		face = if alongX then V3(0, 0, if pf.c.Z > cab.c.Z then 1 else -1) else V3(if pf.c.X > cab.c.X then 1 else -1, 0, 0)
	else
		face = if alongX then V3(0, 0, if cab.c.Z < (V.door and V.door.z or V.z1) then 1 else -1) else V3(if cab.c.X < 0 then 1 else -1, 0, 0)
	end
	local len = if alongX then cab.size.X else cab.size.Z
	local dep = if alongX then cab.size.Z else cab.size.X
	local fz = (if alongX then (if face.Z > 0 then cab.max.Z else cab.min.Z) else (if face.X > 0 then cab.max.X else cab.min.X))
	local fp = if alongX then V3(cab.c.X, cab.min.Y, fz) else V3(fz, cab.min.Y, cab.c.Z)
	local fcf = dcfAt(fp, face) -- 앞면 바닥 가운데 (dcf)
	local hgt = cab.size.Y
	K:free(function()
		local frameL = lk(C(30, 30, 34), M.Metal)
		-- 속이 빈 장: 뒤판 · 옆판 · 위아래 (앞은 칸마다 아크릴 턱)
		K:box("StCigBack", V3(len, hgt, 0.08), fcf * CF(0, hgt / 2, -dep + 0.05), frameL)
		K:plate("StCigBackLight", len - 0.24, hgt - 0.3, 0.02, fcf * CF(0, hgt / 2, -dep + 0.09), lk(C(236, 238, 242)))
		for _, sx in { -1, 1 } do
			K:box("StCigSide", V3(0.1, hgt, dep - 0.02), fcf * CF(sx * (len / 2 - 0.05), hgt / 2, -dep / 2), frameL)
		end
		K:box("StCigBottom", V3(len, 0.14, dep - 0.02), fcf * CF(0, 0.07, -dep / 2), frameL)
		K:box("StCigTop", V3(len, 0.1, dep - 0.02), fcf * CF(0, hgt - 0.05, -dep / 2), frameL)
		-- 위 1/4 = 광고 라이트박스, 아래 = 담배 칸
		local adH = math.clamp(hgt * 0.22, 0.9, 1.5)
		local ad = K:plate("StCigAd", len - 0.24, adH - 0.1, 0.04, fcf * CF(0, hgt - adH / 2 - 0.05, -0.1), lk(lighter(B.main, 0.15)))
		txt(K, "StCigAdText", len * 0.8, adH * 0.42, fcf * CF(0, hgt - adH * 0.32 - 0.05, -0.05), "궐련형 전자담배 · 일반 담배 · 라이터", WHITE, nil, { glow = 1.2, font = Enum.Font.GothamBold, d = 0.01 })
		txt(K, "StCigNotice", len - 0.4, adH * 0.32, fcf * CF(0, hgt - adH * 0.78 - 0.05, -0.04), "19세 미만 청소년에게 술 · 담배를 판매하지 않습니다 · 신분증 제시", WHITE, C(200, 30, 40), { d = 0.01, font = Enum.Font.GothamBold })
		local _ = ad
		local rowsH = hgt - adH - 0.25
		local rows = math.max(3, math.floor(rowsH / 0.62))
		local pitch = if K.detail == "high" then 0.34 else (if K.detail == "mid" then 0.44 else 0.66)
		local nCol = math.floor((len - 0.4) / pitch)
		for r = 1, rows do
			local y = 0.18 + (r - 1) * rowsH / rows
			K:box("StCigShelf", V3(len - 0.2, 0.04, dep - 0.2), fcf * CF(0, y, -dep / 2), lk(C(200, 204, 210), M.Metal))
			K:box("StCigLip", V3(len - 0.2, 0.12, 0.02), fcf * CF(0, y + 0.06, -0.05), { c = C(230, 236, 240), m = M.Glass, t = 0.3 })
			for i = 1, nCol do
				local x = -len / 2 + 0.2 + pitch * (i - 0.5)
				local col: Color3 = pick(rng, CIG_COLS)
				K:box("StCigPack", V3(pitch * 0.8, 0.44, 0.1), fcf * CF(x, y + 0.26, -0.22), lk(col))
			end
			if K.detail ~= "low" and r % 2 == 1 then
				txt(K, "StCigPrice", len - 0.4, 0.1, fcf * CF(0, y + 0.06, -0.035), "4,500      4,500      4,800      4,500      5,000      4,500      4,800      5,500", INK, C(250, 250, 248), { d = 0.01, font = Enum.Font.GothamBold })
			end
		end
		-- 장 아래 수납장 (바닥 ~ 장 밑, 같은 깊이: 계산대 뒤 직원 쪽, 서랍 + 문)
		if cab.min.Y > 1.2 then
			local bh = cab.min.Y - 0.02
			local bcf = fcf * CF(0, -cab.min.Y, 0)
			K:box("StCigBase", V3(len, bh, dep - 0.06), bcf * CF(0, bh / 2, -dep / 2), lk(C(236, 236, 232)))
			K:box("StCigBaseKick", V3(len - 0.1, 0.3, 0.04), bcf * CF(0, 0.15, -0.02), Look.charcoal)
			local nd = math.max(2, math.floor(len / 1.6))
			for i = 1, nd do
				local x = -len / 2 + (i - 0.5) * len / nd
				K:plate("StCigBaseDoor", len / nd - 0.08, bh - 0.5, 0.02, bcf * CF(x, 0.3 + (bh - 0.5) / 2 + 0.05, -0.03), lk(C(244, 244, 240)))
				K:box("StCigBaseHandle", V3(0.5, 0.05, 0.05), bcf * CF(x, bh - 0.35, 0.0), Look.chrome)
			end
		end
		-- 머리 라이트 박스
		if hd then
			local hlen = if alongX then hd.size.X else hd.size.Z
			local hfz = if alongX then (if face.Z > 0 then hd.max.Z else hd.min.Z) else (if face.X > 0 then hd.max.X else hd.min.X)
			local hp = if alongX then V3(hd.c.X, hd.c.Y, hfz) else V3(hfz, hd.c.Y, hd.c.Z)
			local hcf = dcfAt(hp, face)
			K:box("StCigHeader", V3(hlen, hd.size.Y, dep - 0.02), hcf * CF(0, 0, -dep / 2), lk(B.dark))
			txt(K, "StCigHeaderText", hlen * 0.9, hd.size.Y * 0.7, hcf * CF(0, 0, 0.002), "TOBACCO · 담배 · 전자담배", WHITE, nil, { glow = 1.3, font = Enum.Font.GothamBlack, d = 0.01 })
			Scan.hide(K.hidden, hd.part)
		end
	end)
	Scan.hide(K.hidden, cab.part)
	if pf then
		Scan.hide(K.hidden, pf.part)
	end
end

-- 냉장 워크인: 맵 와이어 선반 칸에 문(멀리언)별 범주로 음료 진열 + 문 위 범주 띠 + 문틀 LED
local function walkIn(K: any, V: any, surfs: { any }, B: any, rng: () -> number, theme: any, cats: { string })
	local fridge = {}
	for _, s in surfs do
		if s.fridge then
			table.insert(fridge, s)
		end
	end
	if #fridge == 0 then
		return 0
	end
	-- 냉장고 범위
	local mn, mx = V3(math.huge, math.huge, math.huge), V3(-math.huge, -math.huge, -math.huge)
	for _, s in fridge do
		mn = mn:Min(s.rec.min)
		mx = mx:Max(s.rec.max)
	end
	local alongX = (mx.X - mn.X) >= (mx.Z - mn.Z)
	local s0 = fridge[1]
	-- 문 칸 경계 (DoorMullion)
	local cuts = {}
	for _, dm in V.byName.DoorMullion or {} do
		if dm.c.X > mn.X - 0.6 and dm.c.X < mx.X + 0.6 and dm.c.Z > mn.Z - 0.8 and dm.c.Z < mx.Z + 0.8 then
			local lp = s0.cf:PointToObjectSpace(dm.c)
			table.insert(cuts, lp.X)
		end
	end
	table.sort(cuts)
	local half = s0.len / 2
	local cols = {}
	local prev = -half
	for _, cx in cuts do
		if cx > prev + 0.6 and cx < half - 0.4 then
			table.insert(cols, { prev, cx })
			prev = cx
		end
	end
	table.insert(cols, { prev, half })
	-- 범주 (마지막 칸은 주류)
	local colCat = {}
	for i = 1, #cols do
		colCat[i] = cats[math.min(i, #cats)]
		if i == #cols and #cols >= 3 then
			colCat[i] = cats[#cats]
		end
	end
	local used = 0
	for _, s in fridge do
		for i, c in cols do
			local w = c[2] - c[1] - 0.16
			if w > 0.4 then
				local sub = { cf = s.cf * CF((c[1] + c[2]) / 2, 0, 0), len = w, depth = s.depth, clear = s.clear, rail = s.rail, level = s.level, levels = s.levels }
				queueFill(K, sub, colCat[i], V.key .. "f" .. i .. ":" .. (s.level or 0), theme, { facing = 3, noTags = true, gap = 0.03 })
			end
		end
	end
	-- 범주 띠 (냉장고 머리 Body 앞면) + 문틀 LED
	local body = nil
	for _, b in V.byName.Body or {} do
		if b.min.Y > mx.Y and overlapXZ(b, { min = mn, max = mx }, 0.6) then
			body = b
		end
	end
	local LABEL = { dairy = "우유 · 유제품", coffee = "커피 · 차음료", soda = "탄산 · 이온음료", waterF = "생수 · 주스", beer = "맥주 · 소주 · 하이볼", drinkRoom = "음료" }
	if body then
		local face = s0.cf.ZVector
		local fpos = if alongX then (if face.Z > 0 then body.max.Z else body.min.Z) else (if face.X > 0 then body.max.X else body.min.X)
		for i, c in cols do
			local mid = s0.cf * V3((c[1] + c[2]) / 2, 0, 0)
			local p = if alongX then V3(mid.X, (body.min.Y + body.max.Y) / 2, fpos) else V3(fpos, (body.min.Y + body.max.Y) / 2, mid.Z)
			local d = dcfAt(p, face)
			local w = c[2] - c[1] - 0.2
			local bg = if colCat[i] == "beer" then B.dark else (if i % 2 == 0 then B.main else lighter(B.main, 0.1))
			txt(K, "StFridgeCat", w, math.min(0.62, body.size.Y * 0.7), d, LABEL[colCat[i]] or "음료", WHITE, bg, { d = 0.02, font = Enum.Font.GothamBlack, glow = 1.15, free = true })
		end
		if K.detail ~= "low" then
			txt(K, "StFridgeSale", math.min(3.4, s0.len * 0.3), 0.3, dcfAt((if alongX then V3(mx.X - 1.9, body.min.Y - 0.25, fpos + face.Z * 0.02) else V3(fpos + face.X * 0.02, body.min.Y - 0.25, mx.Z - 1.9)), face), "맥주 4캔 12,000원 · 2+1 음료", INK, B.promo2, { d = 0.015, font = Enum.Font.GothamBlack, free = true })
		end
	end
	-- 문틀 안쪽 세로 LED (멀리언 바로 뒤)
	local face = s0.cf.ZVector
	for _, dm in V.byName.DoorMullion or {} do
		if dm.c.X > mn.X - 0.6 and dm.c.X < mx.X + 0.6 and dm.c.Z > mn.Z - 0.8 and dm.c.Z < mx.Z + 0.8 then
			local half = if math.abs(face.Z) > 0.5 then dm.size.Z / 2 else dm.size.X / 2
			local q = dm.c - face * (half + 0.05)
			K:box("StFridgeLED", V3(0.05, dm.size.Y - 0.3, 0.05), CF(q.X, dm.c.Y, q.Z), L_FREE(Look.lampCool))
		end
	end
	return used
end

-- 계산대 꾸밈 (카드 단말기 · 껌 진열 · 일회용 컵 · 봉투 안내 · 택배 스티커)
local function cashierDress(K: any, V: any, g: any, B: any, kind: string)
	local face = counterFace(V, g)
	local alongX = math.abs(face.Z) > 0.5
	local len = if alongX then g.max.X - g.min.X else g.max.Z - g.min.Z
	local fpos = if alongX then (if face.Z > 0 then g.max.Z else g.min.Z) else (if face.X > 0 then g.max.X else g.min.X)
	local mid = (g.min + g.max) / 2
	local fp = if alongX then V3(mid.X, 0, fpos) else V3(fpos, 0, mid.Z)
	local fc = dcfAt(fp, face) -- 계산대 앞면 바닥 (손님 쪽)
	local top = g.y
	local pos = nil
	for _, nm in { "PosBase", "CashierPanel" } do
		for _, r in V.byName[nm] or {} do
			if r.c.X > g.min.X - 0.3 and r.c.X < g.max.X + 0.3 and r.c.Z > g.min.Z - 0.6 and r.c.Z < g.max.Z + 0.6 then
				pos = pos or r
			end
		end
	end
	local posU = if pos then fc:PointToObjectSpace(pos.c).X else 0
	-- 앞면 스티커 (교통카드 · 택배 · 공과금)
	local stickers: { any } = {}
	if kind == "cvs" then
		stickers = { { "교통카드 충전\n티머니 · 캐시비", B.main }, { B.parcel, B.sub }, { "공과금 수납\n휴대폰 요금", C(80, 80, 86) } }
	elseif kind == "cosmetics" then
		stickers = { { "CJ ONE 포인트 적립\n올리브영 앱 쿠폰", C(154, 194, 27) }, { "오늘드림\n3시간 빠른 배송", C(30, 30, 30) } }
	elseif kind == "pharmacy" then
		stickers = { { "처방전 접수\n복약 상담", C(10, 138, 58) }, { "카드 · 간편결제\n현금영수증", C(60, 60, 66) } }
	else
		stickers = { { "카드 · 간편결제 OK\nTAX FREE", C(30, 80, 160) }, { "포장 · 선물 포장 가능", C(200, 40, 40) } }
	end
	local nSt = #stickers
	local sw = math.min(1.9, (len - 1.0) / math.max(1, nSt))
	for i, st in stickers do
		local u = -len / 2 + 0.5 + sw * (i - 0.5)
		if math.abs(u - posU) > 0.3 or true then
			K:free(function()
				txt(K, "StCounterSticker", sw - 0.2, 0.62, fc * CF(u, top * 0.62, 0.1), st[1], WHITE, st[2], { d = 0.01, font = Enum.Font.GothamBold })
			end)
		end
	end
	-- 상판 위 소품: 이미 놓인 것 (POS · 스티머 · 화면) 을 피해 손님 쪽 반에
	local onTop = {}
	for _, r in V.parts do
		if r.min.Y >= top - 0.15 and r.max.Y > top + 0.05 and r.c.X > g.min.X - 0.1 and r.c.X < g.max.X + 0.1 and r.c.Z > g.min.Z - 0.1 and r.c.Z < g.max.Z + 0.1 and r.part.Transparency < 0.99 then
			table.insert(onTop, r)
		end
	end
	local taken = {}
	local function topCf(u: number, depthIn: number): CFrame
		local p = fc * V3(u, top, -depthIn)
		return pcfAt(p, face)
	end
	local function slot(w: number, d: number, depthIn: number, us: { number }): CFrame?
		for _, u in us do
			if math.abs(u) + w / 2 < len / 2 - 0.12 then
				local cf = topCf(u, depthIn)
				local mn, mx = K.laabb(cf * CF(0, 0.3, 0), V3(w, 0.6, d))
				local ok = true
				for _, r in onTop do
					if K.overlap(mn, mx, r.min - V3(0.08, 0, 0.08), r.max + V3(0.08, 0, 0.08), 0) then
						ok = false
						break
					end
				end
				if ok then
					for _, t in taken do
						if K.overlap(mn, mx, t[1], t[2], 0) then
							ok = false
							break
						end
					end
				end
				if ok then
					table.insert(taken, { mn, mx })
					return cf
				end
			end
		end
		return nil
	end
	-- POS 에서 먼 끝 -> POS 쪽으로 훑는 후보
	local farSign = if posU > 0 then -1 else 1
	local function sweepFar(): { number }
		local out = {}
		local u = farSign * (len / 2 - 0.6)
		for _ = 1, 40 do
			table.insert(out, u)
			u -= farSign * 0.25
		end
		return out
	end
	local function nearPos(): { number }
		local out = {}
		for i = 0, 10 do
			table.insert(out, posU + farSign * (1.05 + i * 0.25))
			table.insert(out, posU - farSign * (1.05 + i * 0.25))
		end
		return out
	end
	K:free(function()
		-- 카드 단말기 (POS 옆, 손님 쪽)
		local tc = if V:has("CardReader") > 0 or V:has("CardTerminal") > 0 then nil else slot(0.5, 0.8, 0.5, nearPos())
		if tc then
			Props.cardTerminal(K, tc)
		end
		if kind == "cvs" then
			-- 껌 · 캔디 진열대 (계단식 3단)
			local gp = slot(1.0, 0.8, 0.55, sweepFar())
			if gp then
				for i = 0, 2 do
					K:box("StGumTier", V3(0.9, 0.12 + i * 0.16, 0.24), gp * CF(0, (0.12 + i * 0.16) / 2, 0.2 - i * 0.22), lk(C(240, 240, 240)))
					for j = 0, 3 do
						local col = ({ C(60, 160, 230), C(40, 170, 90), C(240, 80, 120), C(250, 190, 40) })[j + 1]
						K:box("StGumPack", V3(0.18, 0.16, 0.1), gp * CF(-0.33 + j * 0.22, 0.12 + i * 0.16 + 0.08, 0.2 - i * 0.22), lk(col))
					end
				end
				txt(K, "StBagSign", 0.9, 0.5, gp * CF(0, 1.05, -0.32), "봉투 필요하세요?\n종량제 · 종이봉투", INK, C(250, 250, 248), { d = 0.02, font = Enum.Font.GothamBold })
				K:seg("StBagSignStick", (gp * CF(0, 0.5, -0.34)).Position, (gp * CF(0, 0.8, -0.34)).Position, 0.03, Look.chrome)
			end
			-- 일회용 아이스컵 탑
			local cp = slot(0.4, 0.4, 0.4, sweepFar())
			if cp then
				K:vcyl("StCupStack", 0.7, 0.32, cp * CF(0, 0.35, 0), { c = C(236, 244, 250), m = M.Glass, t = 0.35 })
				K:vcyl("StCupStackTop", 0.04, 0.34, cp * CF(0, 0.71, 0), lk(C(250, 250, 250)))
			end
		elseif kind == "cosmetics" then
			local tp = slot(1.1, 0.7, 0.55, sweepFar())
			if tp then
				K:box("StLipTray", V3(1.0, 0.1, 0.6), tp * CF(0, 0.05, 0), lk(C(250, 250, 250)))
				for j = 0, 5 do
					local col = ({ C(230, 90, 110), C(200, 20, 50), C(240, 140, 150), C(180, 70, 60), C(250, 200, 210), C(150, 30, 60) })[j + 1]
					K:vcyl("StLipBalm", 0.28, 0.12, tp * CF(-0.38 + j * 0.15, 0.24, 0.1), lk(col))
				end
				txt(K, "StLipTrayTag", 0.8, 0.2, tp * CF(0, 0.13, 0.302), "계산대 특가 립밤 3,900", INK, C(250, 250, 248), { d = 0.01 })
			end
			local bp = slot(0.9, 0.5, 0.4, sweepFar())
			if bp then
				for i = 0, 2 do
					K:box("StShopBag", V3(0.8, 0.9, 0.08), bp * CF(0, 0.45, -0.1 + i * 0.1), lk(if i == 1 then OY.main else C(250, 250, 248)))
				end
			end
		elseif kind == "pharmacy" then
			-- 처방전 접수 아크릴 + 약봉투 + 손소독제
			local tp = slot(0.9, 0.4, 0.4, sweepFar())
			if tp then
				K:box("StRxStandBase", V3(0.8, 0.05, 0.3), tp * CF(0, 0.025, 0), Look.acrylicWhite)
				txt(K, "StRxStand", 0.76, 0.56, tp * CF(0, 0.34, 0), "처방전\n접수", C(10, 120, 50), C(250, 252, 250), { d = 0.03, font = Enum.Font.GothamBlack })
			end
			local bp = slot(0.8, 0.8, 0.6, sweepFar())
			if bp then
				for i = 0, 3 do
					K:box("StPillBag", V3(0.5, 0.02, 0.7), bp * CF(0, 0.012 + i * 0.022, 0) * ANG(0, 0.08 * i, 0), lk(C(250, 250, 246)))
				end
				K:box("StPillBagPrint", V3(0.3, 0.004, 0.2), bp * CF(0, 0.1, 0.1), lk(C(40, 150, 70)))
			end
			local sp = slot(0.4, 0.4, 0.35, sweepFar())
			if sp then
				K:vcyl("StSanitizer", 0.5, 0.26, sp * CF(0, 0.25, 0), { c = C(220, 240, 250), m = M.Glass, t = 0.3 })
				K:vcyl("StSanitizerPump", 0.14, 0.12, sp * CF(0, 0.57, 0), lk(C(250, 250, 250)))
			end
		else
			local tp = slot(1.1, 0.7, 0.5, sweepFar())
			if tp then
				K:box("StGiftWrapBase", V3(1.0, 0.06, 0.6), tp * CF(0, 0.03, 0), Look.walnut)
				K:cyl("StGiftWrapRoll", 0.9, 0.22, tp * CF(0, 0.2, 0.12), lk(C(200, 40, 40)))
				K:cyl("StGiftWrapRoll", 0.9, 0.22, tp * CF(0, 0.2, -0.12), lk(C(30, 80, 160)))
			end
		end
	end)
end

-- CCTV 모니터 (4분할 화면 · 벽 브래킷): 계산대 가까운 벽, 손님이 보도록 높이 6.6 이상
local function cctvMonitor(K: any, dcf: CFrame)
	K:plate("StCCTVArm", 0.3, 0.3, 0.5, dcf, Look.blackMetal)
	local m = dcf * CF(0, -0.1, 0.5)
	K:plate("StCCTVBezel", 1.7, 1.05, 0.12, m, Look.black)
	local cols = { C(60, 74, 80), C(52, 66, 74), C(70, 80, 84), C(56, 70, 66) }
	for i = 0, 3 do
		local x = -0.39 + (i % 2) * 0.78
		local y = 0.23 - math.floor(i / 2) * 0.46
		K:plate("StCCTVView", 0.74, 0.42, 0.01, m * CF(x, y, 0.12), { c = cols[i + 1], m = M.Neon, t = 0.35 })
	end
	txt(K, "StCCTVRec", 0.5, 0.12, m * CF(-0.52, 0.4, 0.135), "● REC  CAM1-4", C(255, 70, 60), nil, { glow = 1.4, d = 0.005 })
end

-- ATM 앞면 디테일 (같은 면에 얇은 덧붙임)
local function atmDress(K: any, V: any)
	local atm = V:first("ATM")
	if not atm then
		return
	end
	local scr = V:first("ATMScreen")
	local face = if scr then (if math.abs(scr.c.X - atm.c.X) > math.abs(scr.c.Z - atm.c.Z) then V3(math.sign(scr.c.X - atm.c.X), 0, 0) else V3(0, 0, math.sign(scr.c.Z - atm.c.Z))) else awayFromWall(V, atm)
	local fpos = if math.abs(face.X) > 0.5 then (if face.X > 0 then atm.max.X else atm.min.X) else (if face.Z > 0 then atm.max.Z else atm.min.Z)
	local p = if math.abs(face.X) > 0.5 then V3(fpos, 0, atm.c.Z) else V3(atm.c.X, 0, fpos)
	local d = dcfAt(p, face)
	local w = if math.abs(face.X) > 0.5 then atm.size.Z else atm.size.X
	K:free(function()
		K:plate("StATMFascia", w - 0.2, 1.3, 0.03, d * CF(0, 2.4, 0), lk(C(214, 218, 224), M.Metal))
		K:plate("StATMCardSlot", 0.5, 0.08, 0.05, d * CF(-w * 0.22, 2.75, 0.03), lk(C(40, 200, 120), M.Neon))
		K:plate("StATMCashSlot", 1.1, 0.12, 0.05, d * CF(0, 2.2, 0.03), lk(C(30, 30, 32)))
		K:plate("StATMReceipt", 0.4, 0.06, 0.05, d * CF(w * 0.25, 2.75, 0.03), lk(C(30, 30, 32)))
		txt(K, "StATMLabel", w - 0.4, 0.42, d * CF(0, 1.4, 0.035), "현금인출기 ATM\n입금 · 출금 · 이체 24시간", C(20, 60, 120), C(240, 244, 250), { d = 0.01, font = Enum.Font.GothamBold })
		local hd = V:first("ATMHeader")
		if hd then
			local hp = if math.abs(face.X) > 0.5 then V3((if face.X > 0 then hd.max.X else hd.min.X), hd.c.Y, hd.c.Z) else V3(hd.c.X, hd.c.Y, (if face.Z > 0 then hd.max.Z else hd.min.Z))
			txt(K, "StATMHead", w - 0.2, hd.size.Y * 0.7, dcfAt(hp, face), "ATM  24H", WHITE, C(20, 80, 170), { d = 0.02, font = Enum.Font.GothamBlack, glow = 1.2 })
		end
	end)
end

-- 셀프 원두커피 스테이션 (하부장 + 머신 + 컵 · 뚜껑 + 안내)
local function coffeeStation(K: any, pcf: CFrame, B: any)
	local w, d, h = 2.2, 1.5, 2.9
	K:box("StCoffeeCab", V3(w, h - 0.1, d), pcf * CF(0, (h - 0.1) / 2, 0), lk(B.dark))
	K:box("StCoffeeTop", V3(w + 0.06, 0.1, d + 0.06), pcf * CF(0, h - 0.05, 0), lk(C(236, 236, 232)))
	K:plate("StCoffeeDoorLine", 0.03, h - 0.6, 0.01, pcf * CF(0, (h - 0.1) / 2, d / 2), lk(darker(B.dark, 0.3)))
	txt(K, "StCoffeeCabText", w * 0.86, 0.5, pcf * CF(0, h * 0.55, d / 2 + 0.005), B.coffee, WHITE, nil, { font = Enum.Font.GothamBlack, d = 0.01 })
	-- 머신
	local m = pcf * CF(-0.3, h, -0.1)
	K:rbox("StCoffeeMachine", V3(1.1, 1.7, 1.0), 0.08, m * CF(0, 0.85, 0), lk(C(30, 30, 32), M.Metal))
	K:plate("StCoffeePanel", 0.8, 0.5, 0.02, m * CF(0, 1.3, 0.5), lk(C(60, 60, 64), M.Metal))
	K:plate("StCoffeeScreen", 0.46, 0.26, 0.02, m * CF(0, 1.32, 0.52), lk(C(60, 160, 240), M.Neon))
	K:box("StCoffeeNozzle", V3(0.3, 0.16, 0.2), m * CF(0, 0.82, 0.5), Look.chrome)
	K:box("StCoffeeDrip", V3(0.7, 0.06, 0.4), m * CF(0, 0.12, 0.42), Look.chrome)
	K:vcyl("StCoffeeCup", 0.32, 0.22, m * CF(0, 0.32, 0.42), lk(C(250, 250, 250)))
	-- 컵 · 뚜껑 · 빨대
	local c = pcf * CF(0.65, h, 0.1)
	for i = 0, 1 do
		K:vcyl("StCoffeeCups", 0.8, 0.28, c * CF(-0.15 + i * 0.32, 0.4, 0), lk(if i == 0 then C(250, 250, 250) else C(214, 196, 170)))
	end
	K:vcyl("StStrawCup", 0.4, 0.22, c * CF(0.2, 0.2, -0.36), lk(C(240, 240, 240)))
	for i = 0, 3 do
		K:seg("StStraw", (c * CF(0.16 + i * 0.03, 0.35, -0.36)).Position, (c * CF(0.12 + i * 0.06, 0.75, -0.38)).Position, 0.025, lk(({ C(230, 40, 50), C(40, 120, 220), C(250, 250, 250), C(40, 170, 90) })[i + 1]))
	end
	-- 안내판 (뒤 벽쪽 세움)
	txt(K, "StCoffeeMenu", w * 0.9, 1.2, pcf * CF(0, h + 2.4, -d / 2 + 0.1), "셀프 원두커피 " .. B.coffee .. "\n아메리카노 HOT 1,300 · ICE 1,800\n카페라떼 2,500 · 계산 후 컵 받아 가세요", WHITE, B.main, { d = 0.04, font = Enum.Font.GothamBold })
end

-- 무인 택배 접수기 (키오스크 + 저울 선반): 화면 안내를 넘겨 보는 상호작용
local function parcelKiosk(K: any, pcf: CFrame, B: any)
	local body = lk(C(242, 242, 240))
	K:box("StKioskPlinth", V3(1.4, 0.3, 1.0), pcf * CF(0, 0.15, 0), Look.charcoal)
	K:rbox("StKioskBody", V3(1.3, 4.0, 0.86), 0.12, pcf * CF(0, 2.3, -0.02), body)
	K:box("StKioskHead", V3(1.34, 0.62, 0.9), pcf * CF(0, 4.6, -0.02), lk(B.main))
	txt(K, "StKioskHeadText", 1.2, 0.46, pcf * CF(0, 4.6, 0.432), "무인 택배 접수", WHITE, nil, { font = Enum.Font.GothamBlack, d = 0.01, glow = 1.1 })
	K:box("StKioskBezel", V3(1.0, 1.3, 0.08), pcf * CF(0, 3.35, 0.42) * ANG(-0.1, 0, 0), Look.black)
	local scr, label = txt(K, "StKioskScreen", 0.86, 1.14, pcf * CF(0, 3.35, 0.46) * ANG(-0.1, 0, 0), "택배 접수\n화면을 눌러\n시작하세요", WHITE, C(30, 90, 170), { glow = 1.25, font = Enum.Font.GothamBold, d = 0.02 })
	K:box("StKioskPrinter", V3(0.6, 0.12, 0.1), pcf * CF(0, 2.4, 0.44), lk(C(40, 40, 44)))
	K:box("StKioskCard", V3(0.36, 0.2, 0.12), pcf * CF(0.3, 2.75, 0.45), lk(C(60, 60, 64)))
	K:plate("StKioskCardLED", 0.08, 0.04, 0.01, pcf * CF(0.3, 2.82, 0.51), Look.ledGreen)
	K:box("StKioskScanner", V3(0.24, 0.3, 0.2), pcf * CF(-0.36, 2.72, 0.47) * ANG(0.3, 0, 0), Look.black)
	-- 옆 저울 선반
	K:box("StScaleShelf", V3(1.0, 0.1, 0.8), pcf * CF(1.2, 2.0, 0), lk(C(220, 222, 226), M.Metal))
	K:box("StScaleLeg", V3(0.1, 2.0, 0.1), pcf * CF(1.6, 1.0, 0.3), Look.chrome)
	K:box("StScaleLeg", V3(0.1, 2.0, 0.1), pcf * CF(1.6, 1.0, -0.3), Look.chrome)
	K:box("StScale", V3(0.8, 0.12, 0.6), pcf * CF(1.2, 2.11, 0), Look.steel)
	K:plate("StScaleLCD", 0.3, 0.1, 0.01, pcf * CF(1.2, 2.11, 0.305), Look.ledRed)
	K:box("StParcelBox", V3(0.6, 0.45, 0.5), pcf * CF(1.2, 2.4, 0), Look.kraft)
	K:box("StParcelTape", V3(0.62, 0.04, 0.1), pcf * CF(1.2, 2.63, 0), lk(C(220, 200, 150), M.Plastic))
	txt(K, "StKioskGuide", 1.1, 0.7, pcf * CF(0, 1.4, 0.44), B.parcel .. "\n접수 마감 22:00", INK, C(250, 250, 248), { d = 0.01, font = Enum.Font.GothamBold })
	local frames = { "택배 접수\n화면을 눌러\n시작하세요", "1. 받는 분 주소\n입력", "2. 저울에 올려\n무게 측정", "3. 운송장 출력 후\n상자에 부착", "결제는 계산대에서\n" .. B.parcel }
	local i = 1
	promptOn(K, { scr }, {
		action = "화면 넘기기",
		object = "무인 택배 접수기",
		fn = function()
			i = i % #frames + 1
			if label.Parent then
				label.Text = frames[i]
			end
		end,
	})
end

-- 2L 생수 묶음 더미 (팔레트 위, 창가 낮은 진열)
local function waterStack(K: any, pcf: CFrame, B: any)
	K:box("StPallet", V3(2.4, 0.22, 1.6), pcf * CF(0, 0.11, 0), Look.pine)
	local pw, ph, pd = 1.15, 1.02, 0.76
	for layer = 0, 1 do
		for i = 0, 1 do
			for j = 0, 1 do
				local p = pcf * CF(-0.58 + i * 1.17, 0.22 + layer * ph + ph / 2, -0.39 + j * 0.78)
				K:box("StWaterPack", V3(pw, ph, pd), p, { c = C(196, 226, 246), m = M.Glass, t = 0.25, r = 0.1 })
				if K.detail ~= "low" and j == 1 then
					K:box("StWaterPackLabel", V3(pw + 0.01, 0.26, pd + 0.01), p * CF(0, 0.05, 0), lk(C(30, 110, 200)))
				end
			end
		end
	end
	K:bar("StWaterHandle", (pcf * CF(-0.9, 2.3, 0.39)).Position, (pcf * CF(-0.3, 2.3, 0.39)).Position, 0.05, 0.1, lk(C(250, 250, 250)))
	txt(K, "StWaterPOP", 1.8, 0.6, pcf * CF(0, 2.4, 0.8), "생수 2L × 6 행사 5,980원", WHITE, B.promo1, { d = 0.03, font = Enum.Font.GothamBlack })
	K:seg("StWaterPOPStick", (pcf * CF(0.9, 2.1, 0.76)).Position, (pcf * CF(0.9, 2.7, 0.76)).Position, 0.04, Look.chrome)
end

-- 라면 · 전자레인지 코너 (맵 전자레인지 · 온수기 위 벽에 안내, 끝에 국물 버리는 통)
local function ramenCorner(K: any, V: any, B: any)
	local mw = V.byName.Microwave or {}
	local hw = V:first("HotWater")
	if #mw == 0 and not hw then
		return
	end
	local ref = hw or mw[1]
	-- 벽 (가장 가까운 벽)
	local dl, dr, db = ref.min.X - V.x0, V.x1 - ref.max.X, ref.min.Z - V.z0
	local wn = if db <= dl and db <= dr then "back" elseif dl < dr then "left" else "right"
	local u = V:wallCoord(wn, ref.c)
	local dcf = V:wall(wn, u, 4.75, 0.06)
	if not wallBusy(K, wn, u - 1.6, u + 1.6, 4.2, 5.3) then
		local mn, mx = K.laabb(dcf * CF(0, 0, 0.05), V3(3.0, 0.7, 0.1))
		if not mapBlocked(K, mn, mx) then
			txt(K, "StRamenGuide", 3.0, 0.6, dcf, "컵라면 물 붓는 선까지 · 전자레인지 용기 확인 · 국물은 통에", INK, C(250, 236, 120), { d = 0.02, font = Enum.Font.GothamBold })
			addWallUsed(K, wn, u - 1.6, u + 1.6, 4.3, 5.2)
		end
	end
	-- 벽에 붙인 양념 · 냅킨 꽂이 (전자레인지 사이 빈 벽, 상판 바로 위 얕게)
	local cnt0 = nil
	for _, g in V.counters do
		if ref.c.X >= g.min.X - 0.5 and ref.c.X <= g.max.X + 0.5 and ref.c.Z >= g.min.Z - 0.8 and ref.c.Z <= g.max.Z + 0.8 then
			cnt0 = g
		end
	end
	if cnt0 and wn == "back" then
		local busy = {}
		for _, r in V.parts do
			if r.min.Y >= cnt0.y - 0.15 and r.min.Y < cnt0.y + 0.6 and r.max.Y > cnt0.y + 0.05 and r.c.X > cnt0.min.X and r.c.X < cnt0.max.X and r.c.Z > cnt0.min.Z - 0.1 and r.c.Z < cnt0.max.Z + 0.1 then
				table.insert(busy, { r.min.X - 0.15, r.max.X + 0.15 })
			end
		end
		table.sort(busy, function(a, b)
			return a[1] < b[1]
		end)
		local cur, best, bw = cnt0.min.X + 0.2, nil, 0
		for _, b in busy do
			if b[1] - cur > bw then
				best, bw = (cur + b[1]) / 2, b[1] - cur
			end
			cur = math.max(cur, b[2])
		end
		if cnt0.max.X - 0.2 - cur > bw then
			best, bw = (cur + cnt0.max.X - 0.2) / 2, cnt0.max.X - 0.2 - cur
		end
		if best and bw >= 1.2 then
			local rw = math.min(1.8, bw - 0.2)
			local u2 = best - (V.x0 + V.x1) / 2
			local rc = V:wall("back", u2, cnt0.y, 0.02)
			K:free(function()
				K:box("StCondRack", V3(rw, 0.06, 0.36), rc * CF(0, 0.5, 0.18), Look.steel)
				K:box("StCondRackBack", V3(rw, 0.8, 0.04), rc * CF(0, 0.45, 0.02), Look.steel)
				K:box("StNapkinBox", V3(0.5, 0.36, 0.3), rc * CF(-rw / 2 + 0.35, 0.71, 0.18), lk(C(250, 250, 250)))
				K:box("StNapkinTissue", V3(0.2, 0.08, 0.12), rc * CF(-rw / 2 + 0.35, 0.93, 0.18), Look.paper)
				K:vcyl("StChopCup", 0.4, 0.24, rc * CF(-rw / 2 + 0.85, 0.73, 0.18), Look.steel)
				for i = 0, 4 do
					K:seg("StChopstick", (rc * CF(-rw / 2 + 0.8 + i * 0.025, 0.6, 0.18)).Position, (rc * CF(-rw / 2 + 0.78 + i * 0.03, 1.12, 0.16)).Position, 0.03, Look.birch)
				end
				K:vcyl("StForkCup", 0.36, 0.22, rc * CF(-rw / 2 + 1.2, 0.71, 0.18), lk(C(240, 240, 240)))
				if rw > 1.5 then
					K:box("StWetWipe", V3(0.36, 0.14, 0.26), rc * CF(rw / 2 - 0.25, 0.6, 0.18), lk(C(170, 220, 250)))
				end
			end)
		end
	end
	-- 국물 버리는 통 (카운터 옆 바닥)
	local cnt = nil
	for _, g in V.counters do
		if ref.c.X >= g.min.X - 0.5 and ref.c.X <= g.max.X + 0.5 and ref.c.Z >= g.min.Z - 0.8 and ref.c.Z <= g.max.Z + 0.8 then
			cnt = g
		end
	end
	if cnt then
		local cands = {}
		local alongX = (cnt.max.X - cnt.min.X) >= (cnt.max.Z - cnt.min.Z)
		if alongX then
			table.insert(cands, V3(cnt.max.X + 0.65, 0, cnt.min.Z + 0.6))
			table.insert(cands, V3(cnt.min.X - 0.65, 0, cnt.min.Z + 0.6))
		else
			table.insert(cands, V3(cnt.c.X, 0, cnt.max.Z + 0.65))
			table.insert(cands, V3(cnt.c.X, 0, cnt.min.Z - 0.65))
		end
		local pcf = floorSpot(K, cands, V3(1.0, 2.6, 1.0), V3(0, 0, 1), 0, "soupbin")
		if pcf then
			K:vcyl("StSoupBin", 2.0, 0.9, pcf * CF(0, 1.0, 0), lk(C(70, 74, 80), M.Plastic))
			K:vcyl("StSoupBinLid", 0.1, 0.96, pcf * CF(0, 2.05, 0), lk(C(220, 222, 224), M.Metal))
			K:disc("StSoupBinMesh", 0.6, 0.02, pcf * CF(0, 2.11, 0), lk(C(150, 150, 150), M.DiamondPlate))
			txt(K, "StSoupBinLabel", 0.7, 0.4, pcf * CF(0, 1.4, 0.452), "국물\n버리는 곳", WHITE, C(200, 40, 40), { d = 0.01 })
		end
	end
end

-- 미뤄 둔 공통 벽 부착물 (스위치 · 콘센트 · 온도조절기 · 비상벨 · 사업자등록증 · 시계) — 큰 진열장 다음, 포스터 전에 한 번
local function fixturesNow(K: any, V: any, S: any)
	if K.stFixturesDone then
		return
	end
	K.stFixturesDone = true
	step(K, "fixtures", function()
		sortWallUsed(K)
		Common.fixtures(K, V, S)
	end)
end

local function buildCvs(K: any, V: any, S: any, brand: string)
	local B = table.clone(BRANDS[brand] or BRANDS.indie)
	if brand == "indie" then
		B.name = tostring(V.name or "마트")
	end
	local rng = mkRng(V.key .. "cvs")
	local theme = { promo1 = B.promo1, promo2 = B.promo2, p11 = 0.14, p21 = 0.16, maxTagText = 34 }
	local surfs = mapSurfaces(V)
	local obst = obstacles(V)
	-- 손님 앞 공간 예약
	for _, g in V.counters do
		reserveFront(K, g.min, g.max, counterFace(V, g), 2.6, 0.4)
	end
	for _, nm in { "Microwave", "HotWater" } do
		for _, r in V.byName[nm] or {} do
			reserveFront(K, r.min, r.max, awayFromWall(V, r), 2.6, 0.4)
		end
	end
	for _, nm in { "ATM", "IceCreamChest", "FridgeDoor" } do
		for _, r in V.byName[nm] or {} do
			local dir = awayFromWall(V, r)
			if nm == "FridgeDoor" then
				dir = if r.size.X > r.size.Z then V3(0, 0, if r.c.Z < (V.z0 + V.z1) / 2 then 1 else -1) else V3(if r.c.X < 0 then 1 else -1, 0, 0)
			end
			reserveFront(K, r.min, r.max, dir, if nm == "IceCreamChest" then 1.6 else 2.8, 0.3)
		end
	end
	for _, s in surfs do
		if not s.fridge then
			local r = s.rec
			local fwd = s.cf.ZVector
			reserveFront(K, r.min, r.max, V3(math.round(fwd.X), 0, math.round(fwd.Z)), 2.2, 0.2)
		end
	end
	-- 맵 상품 숨김
	for _, nm in { "Product", "Bottle" } do
		for _, r in V.byName[nm] or {} do
			Scan.hide(K.hidden, r.part)
		end
	end
	local used = 0
	step(K, "fridge", function()
		used += walkIn(K, V, surfs, B, rng, theme, { "dairy", "coffee", "soda", "waterF", "beer" })
	end)
	-- 곤돌라: 면마다 범주
	local faceCats = { "snack", "ramen", "sweets", "daily" }
	local faceOf: { [string]: string } = {}
	local nf = 0
	step(K, "gondola", function()
		K:free(function()
			for _, s in surfs do
				if not s.fridge then
					local cat = faceOf[s.face]
					if not cat then
						nf += 1
						cat = faceCats[(nf - 1 + math.floor(rng() * 2)) % #faceCats + 1]
						faceOf[s.face] = cat
					end
					queueFill(K, s, cat, V.key .. s.face .. (s.level or 0), theme, { obst = obst })
				end
			end
		end)
	end)
	-- 곤돌라 끝판 POP + 머리 띠
	step(K, "endcaps", function()
		local CATN = { snack = "과자 · 스낵", ramen = "라면 · 즉석식품", sweets = "초콜릿 · 캔디 · 젤리", daily = "생활용품 · 위생" }
		local promos = { { "2+1", "음료 · 과자 행사" }, { "1+1", B.pb .. " 신상품" }, { "이달의 행사", "카드 결제 시 10% 할인" } }
		for i, ep in V.byName.EndPanel or {} do
			local thinX = ep.size.X < ep.size.Z
			-- 바깥쪽 = 진열대 중심 반대
			local cen = nil
			for _, s in surfs do
				if not s.fridge and overlapXZ(s.rec, ep, 0.6) then
					cen = s.rec.c
				end
			end
			local face = if thinX then V3(if cen and cen.X > ep.c.X then -1 else 1, 0, 0) else V3(0, 0, if cen and cen.Z > ep.c.Z then -1 else 1)
			local fpos = if thinX then (if face.X > 0 then ep.max.X else ep.min.X) else (if face.Z > 0 then ep.max.Z else ep.min.Z)
			local w = if thinX then ep.size.Z else ep.size.X
			local p = if thinX then V3(fpos, ep.size.Y * 0.5, ep.c.Z) else V3(ep.c.X, ep.size.Y * 0.5, fpos)
			local d = dcfAt(p, face)
			local pr = promos[(i - 1) % #promos + 1]
			K:free(function()
				poster(K, d * CF(0, 0, -0.05), w - 0.4, ep.size.Y - 1.2, pr[1], pr[2] .. "\n" .. B.name, C(252, 252, 250), INK, if i % 2 == 0 then B.promo1 else B.main, WHITE, { titleH = 0.42, frame = false })
			end)
			for _, eh in V.byName.EndHeader or {} do
				if overlapXZ(eh, ep, 0.05) then
					local hp = if thinX then V3((if face.X > 0 then eh.max.X else eh.min.X), eh.c.Y, eh.c.Z) else V3(eh.c.X, eh.c.Y, (if face.Z > 0 then eh.max.Z else eh.min.Z))
					local catName = "행사상품"
					for _, s in surfs do
						if not s.fridge and overlapXZ(s.rec, ep, 0.6) and faceOf[s.face] then
							catName = CATN[faceOf[s.face]] or catName
						end
					end
					K:free(function()
						txt(K, "StEndHeaderText", w - 0.2, eh.size.Y * 0.72, dcfAt(hp, face), catName, WHITE, B.main, { d = 0.015, font = Enum.Font.GothamBlack })
					end)
				end
			end
		end
	end)
	-- 담배장 · 계산대 · 라면 코너 · ATM
	step(K, "cig", function()
		cigCabinet(K, V, B, mkRng(V.key .. "cig"))
	end)
	step(K, "cashier", function()
		for _, g in V.counters do
			local hasPos = false
			for _, r in V.byName.PosBase or {} do
				if r.c.X > g.min.X - 0.3 and r.c.X < g.max.X + 0.3 and r.c.Z > g.min.Z - 0.6 and r.c.Z < g.max.Z + 0.6 then
					hasPos = true
				end
			end
			if hasPos then
				cashierDress(K, V, g, B, "cvs")
			end
		end
	end)
	step(K, "ramen", function()
		ramenCorner(K, V, B)
	end)
	step(K, "cctvmon", function()
		local cash = nil
		for _, g in V.counters do
			for _, r in V.byName.PosBase or {} do
				if r.c.X > g.min.X - 0.3 and r.c.X < g.max.X + 0.3 and r.c.Z > g.min.Z - 0.6 and r.c.Z < g.max.Z + 0.6 then
					cash = g
				end
			end
		end
		if cash then
			local c = (cash.min + cash.max) / 2
			local wn = if math.abs(c.X - V.x0) < math.abs(V.x1 - c.X) then "left" else "right"
			local wn2, dcf = wallItemSpot(K, { wn, "back" }, 1.8, 6.7, 8.0, (V:wallCoord(wn, c)))
			if wn2 and dcf then
				cctvMonitor(K, dcf * CF(0, 0, 0.02))
			end
		end
	end)
	step(K, "atm", function()
		atmDress(K, V)
	end)
	-- 아이스크림 냉동고 뒤 모서리 POP (높이 3.4 아래)
	step(K, "icecream", function()
		local ic = V:first("IceCreamChest")
		if ic then
			local alongX = ic.size.X >= ic.size.Z
			-- 뒤쪽 = 가까운 벽 쪽 (손님은 반대편)
			local face = if alongX then V3(0, 0, if ic.c.Z > (V.z0 + V.z1) / 2 then -1 else 1) else V3(if ic.c.X > 0 then -1 else 1, 0, 0)
			local back = if alongX then V3(ic.c.X, ic.max.Y, if face.Z < 0 then ic.max.Z - 0.08 else ic.min.Z + 0.08) else V3(if face.X < 0 then ic.max.X - 0.08 else ic.min.X + 0.08, ic.max.Y, ic.c.Z)
			local d = dcfAt(back + V3(0, 0.36, 0), face)
			local w = math.min(2.2, (if alongX then ic.size.X else ic.size.Z) - 0.6)
			K:free(function()
				K:box("StIceClip", V3(0.3, 0.12, 0.12), dcfAt(back + V3(0, 0.04, 0), face) * CF(0, 0, -0.02), Look.chrome)
				txt(K, "StIcePOP", w, 0.6, d, "아이스크림 상시 할인\n콘 · 바 · 튜브 2+1", WHITE, B.promo1, { d = 0.03, font = Enum.Font.GothamBlack })
			end)
		end
	end)
	-- 핫바 · 호빵 (SteamerCase 안)
	step(K, "steamer", function()
		local sc = V:first("SteamerCase")
		if sc then
			K:free(function()
				local y = sc.min.Y + 0.08
				K:box("StSteamerTray", V3(sc.size.X - 0.2, 0.04, sc.size.Z - 0.2), CF(sc.c.X, y, sc.c.Z), Look.steel)
				for i = 0, 4 do
					local x = sc.min.X + 0.3 + i * (sc.size.X - 0.6) / 4
					K:box("StHotBar", V3(0.16, 0.12, 0.8), CF(x, y + 0.1, sc.c.Z + 0.1), lk(C(214, 150, 90)))
					K:seg("StHotBarStick", V3(x, y + 0.1, sc.c.Z - 0.3), V3(x, y + 0.12, sc.c.Z - 0.55), 0.03, lk(C(230, 210, 170)))
				end
				for i = 0, 2 do
					K:ell("StHoppang", V3(0.42, 0.3, 0.42), CF(sc.min.X + 0.4 + i * 0.6, y + 0.62, sc.c.Z), lk(C(250, 246, 236)))
				end
				K:box("StSteamerShelf", V3(sc.size.X - 0.2, 0.03, sc.size.Z - 0.3), CF(sc.c.X, y + 0.45, sc.c.Z), Look.steel)
				txt(K, "StSteamerTag", math.min(1.8, sc.size.X - 0.2), 0.26, dcfAt(V3(sc.c.X, sc.max.Y + 0.15, sc.c.Z + sc.size.Z / 2), V3(0, 0, 1)), "핫바 2,800 · 호빵 1,800 · 군고구마 3,000", WHITE, C(200, 40, 40), { d = 0.02, font = Enum.Font.GothamBold })
			end)
		end
	end)
	-- 디지털 사이니지 (손 닿는 높이, 서버 앵커에서 먼 벽) — 벽 진열장보다 먼저 자리 잡음
	step(K, "did", function()
		local wn, dcf = wallItemSpot(K, { "right", "left", "back" }, 3.4, 4.6, 6.6, -2, function(d: CFrame): boolean
			return promptOk(K, d.Position)
		end)
		if wn and dcf then
			didScreen(K, dcf * CF(0, 0.1, 0.04), 3.0, {
				{ text = B.name .. "\n이달의 행사 1+1 · 2+1", c = B.main },
				{ text = "도시락 · 삼각김밥\n" .. B.pb .. " 신상", c = darker(B.sub, 0.2) },
				{ text = B.coffee .. "\n아이스 아메리카노 1,800", c = C(70, 44, 30) },
				{ text = B.parcel .. "\n" .. B.app, c = B.dark },
			}, B.name .. " 광고 화면")
		end
	end)
	-- 무인 택배 접수기: 벽 쪽 우선, 없으면 바닥 (화면이 서버 앵커에서 먼 곳)
	step(K, "parcel", function()
		local function okAt(c: CFrame): boolean
			return promptOk(K, (c * CF(0, 3, 0.5)).Position)
		end
		local wn, pcf = wallFloorSpot(K, { "left", "right", "back" }, 2.5, 1.1, 5.2, nil, 0.1, "kiosk", function(c: CFrame): boolean
			return okAt(c * CF(-0.55, 0, 0))
		end)
		if wn and pcf then
			parcelKiosk(K, pcf * CF(-0.55, 0, 0), B)
			return
		end
		local cands = {}
		for gx = V.x0 + 2, V.x1 - 2, 0.5 do
			for gz = V.z0 + 2, V.z1 - 4, 0.5 do
				table.insert(cands, V3(gx, 0, gz))
			end
		end
		for _, face in { V3(0, 0, 1), V3(1, 0, 0), V3(-1, 0, 0) } do
			local pc = floorSpot(K, cands, V3(2.6, 5.2, 1.2), face, 0.9, "kiosk", function(p: Vector3): boolean
				return okAt(pcfAt(p, face) * CF(-0.55, 0, 0))
			end)
			if pc then
				parcelKiosk(K, pc * CF(-0.55, 0, 0), B)
				return
			end
		end
	end)
	-- 새 바닥 소품: 벽 진열장 · 커피 · 생수 · 장바구니
	step(K, "wallunits", function()
		local hU = math.min(5.6, V.H - 2.4)
		local cats = { { "daily", "생활용품 · 위생 · 충전기" }, { "sweets", "초콜릿 · 젤리 · 디저트" }, { "drinkRoom", "음료 · 상온 생수" } }
		local placed = 0
		for _, cc in cats do
			if placed >= 2 then
				break
			end
			for _, len in { 7.2, 5.6, 4.2 } do
				local wn, pcf = wallFloorSpot(K, { "right", "left", "back" }, len, 1.35, hU + 0.7, nil, 0.0, "wallunit")
				if wn and pcf then
					local us = wallUnit(K, pcf, len, 1.35, hU, { title = cc[2], headL = lk(B.main), titleFg = WHITE, lineL = lk(B.sub), levels = 5, glow = 1.1 })
					K:free(function()
						for _, s in us do
							queueFill(K, s, cc[1], V.key .. cc[1] .. s.level, theme, {})
						end
					end)
					placed += 1
					break
				end
			end
		end
	end)
	step(K, "coffee", function()
		local cash = nil
		for _, g in V.counters do
			if V:first("PosBase") and (V:first("PosBase").c - (g.min + g.max) / 2).Magnitude < 5 then
				cash = g
			end
		end
		local prefer = if cash then (cash.min + cash.max) / 2 else nil
		local wn, pcf = wallFloorSpot(K, { "left", "right", "back" }, 2.3, 1.55, 5.6, prefer, 0.0, "coffee")
		if wn and pcf then
			coffeeStation(K, pcf, B)
		end
	end)
	step(K, "water", function()
		local cands = {}
		for _, fx in { -0.38, 0.38, -0.25, 0.25, -0.12, 0.12 } do
			table.insert(cands, V3((V.x0 + V.x1) / 2 + V.W * fx, 0, V.z1 - 1.3))
		end
		local pcf = floorSpot(K, cands, V3(2.5, 3.0, 1.7), V3(0, 0, -1), 0.1, "water")
		if pcf then
			waterStack(K, pcf, B)
		end
	end)
	step(K, "baskets", function()
		local d = V.door
		local cands = {}
		if d then
			for _, dx in { 5.2, -5.2, 6.2, -6.2 } do
				table.insert(cands, V3(d.x + dx, 0, V.z1 - 3.2))
				table.insert(cands, V3(d.x + dx, 0, V.z1 - 4.6))
			end
		end
		local pcf = floorSpot(K, cands, V3(1.5, 2.2, 1.1), V3(0, 0, 1), 0.05, "basket")
		if pcf then
			basketStack(K, pcf, B.basket, 6, B.name)
		end
	end)
	fixturesNow(K, V, S)
	-- 천장 POP (진열대 위 · 입구 쪽을 봄)
	step(K, "hang", function()
		local done = 0
		local texts = { { "1+1 · 2+1 행사상품", "이달의 행사 " .. B.name }, { B.pb .. " 신상품", "도시락 · 김밥 · 샌드위치" }, { "카드 · 간편결제 OK", B.app } }
		local yb = math.max(6.0, V.H - 2.6)
		for _, c in clusters(surfs) do
			if done < 2 then
				local cx, cz = (c.min.X + c.max.X) / 2, (c.min.Z + c.max.Z) / 2
				local t = texts[done + 1]
				if hangSignNear(K, cx, cz, 3.6, 1.0, yb, 0, t[1], t[2], B.main, WHITE, B.sub) then
					done += 1
				end
			end
		end
		for _, p in { V3(0, 0, -1), V3(-V.W * 0.25, 0, 0), V3(V.W * 0.25, 0, 0) } do
			if done < 2 then
				local t = texts[done + 1]
				if hangSignNear(K, (V.x0 + V.x1) / 2 + p.X, (V.z0 + V.z1) / 2 + p.Z, 3.6, 1.0, yb, 0, t[1], t[2], B.main, WHITE, B.sub) then
					done += 1
				end
			end
		end
	end)
	-- 벽 안내 · 포스터 · 사이니지
	step(K, "posters", function()
		local W0 = C(250, 250, 250)
		local P = {
			{ "Free Wi-Fi", (B.ssid or "STORE_WiFi_5G") .. "\n비밀번호 없음", W0, INK, B.main },
			{ "24시간 영업", "연중무휴 · 심야 결제는 카드 권장", W0, INK, B.dark },
			{ "택배 접수", B.parcel .. "\n접수 마감 매일 22:00", W0, INK, B.sub },
			{ B.pb, "가성비 PB 신상품 출시\n도시락 4,900원부터", B.main, WHITE, B.promo1 },
		}
		for _, p in shuffled(mkRng(V.key .. "pp"), {
			{ "CCTV 녹화중", "24시간 녹화 · 도난 방지", W0, INK, C(60, 60, 64) },
			{ "안전상비의약품", "해열진통제 · 소화제 · 파스\n24시간 판매 (1회 1통)", W0, INK, C(10, 138, 58) },
			{ "아이스크림 할인", "전 품목 상시 할인\n콘 · 바 · 튜브 2+1", W0, INK, B.promo1 },
			{ "분리배출 안내", "컵라면 국물은 국물통에\n용기 · 캔 · 페트 분리", W0, INK, C(40, 120, 90) },
			{ "카드 · 간편결제", "통신사 멤버십 할인\n제로페이 · 페이코 · 카카오페이", W0, INK, B.main },
		}) do
			if #P < 6 then
				table.insert(P, p)
			end
		end
		for i, p in P do
			local wn, dcf = wallItemSpot(K, { "left", "right", "back" }, 1.9, 4.4, 6.6, (i - 3) * 3)
			if wn and dcf then
				poster(K, dcf, 1.7, 2.0, p[1], p[2], p[3], p[4], p[5], WHITE, {})
			end
		end
	end)
	step(K, "goods", function()
		used += runFill(K, goodsBudget(K, V))
	end)
	note(K, string.format("cvs %s goods parts=%d surfaces=%d", brand, used, #surfs))
end

---------------------------------------------------------------------------------------------------
-- 7. 소매 (올리브영 · 기념품 · 비치용품 · 꽃 · 서점)
---------------------------------------------------------------------------------------------------

-- 화장대 거울 (전구 둘레) + 조명 토글
local function vanityMirror(K: any, dcf: CFrame, w: number, h: number)
	K:plate("StVanityFrame", w + 0.4, h + 0.4, 0.08, dcf, lk(C(250, 250, 250)))
	K:plate("StVanityGlass", w, h, 0.02, dcf * CF(0, 0, 0.08), Look.mirror)
	local bulbs = {}
	local n = math.floor(w / 0.55)
	for i = 0, n do
		for _, sy in { -1, 1 } do
			table.insert(bulbs, K:ball("StVanityBulb", 0.2, dcf * CF(-w / 2 + i * w / n, sy * (h / 2 + 0.1), 0.14), Look.lampWarm))
		end
	end
	for j = 1, math.floor(h / 0.6) do
		for _, sx in { -1, 1 } do
			table.insert(bulbs, K:ball("StVanityBulb", 0.2, dcf * CF(sx * (w / 2 + 0.1), -h / 2 + j * h / (math.floor(h / 0.6) + 1), 0.14), Look.lampWarm))
		end
	end
	local glow = K:plate("StVanityGlow", 0.1, 0.1, 0.01, dcf * CF(0, h / 2 + 0.1, 0.2), Look.lampWarm)
	local l = K:light(glow, "PointLight", { Range = 7, Brightness = 0.6, Color = Look.warmLight })
	local pp = firstOk(K, bulbs)
	if not pp then
		note(K, "no prompt spot: vanity")
		return
	end
	Interact.toggle(K, pp, {
		object = "화장대 거울 조명",
		state = true,
		on = function(on: boolean)
			for _, b in bulbs do
				if b.Parent then
					b.Material = if on then M.Neon else M.SmoothPlastic
					b.Color = if on then C(255, 214, 160) else C(220, 220, 214)
				end
			end
			if glow.Parent then
				glow.Material = if on then M.Neon else M.SmoothPlastic
			end
			if l then
				l.Enabled = on
			end
		end,
	})
end

-- 회전 진열대 (엽서 · 립스틱 타워): 프롬프트로 돌림
local function spinRack(K: any, pcf: CFrame, kind: string, object: string)
	local parts: { BasePart } = {}
	local function keep(p: BasePart?)
		if p then
			table.insert(parts, p)
		end
	end
	K:disc("StSpinBase", 1.4, 0.08, pcf * CF(0, 0.04, 0), Look.chrome)
	local h = if kind == "postcard" then 5.2 else 4.6
	K:vcyl("StSpinPole", h, 0.12, pcf * CF(0, h / 2, 0), Look.chrome)
	local tiers = if kind == "postcard" then 6 else 5
	for t = 1, tiers do
		local y = 0.7 + (t - 1) * (h - 1.0) / tiers
		for f = 0, 3 do
			local a = f * PI / 2
			local fc = pcf * ANG(0, a, 0) * CF(0, y, 0.3)
			if kind == "postcard" then
				keep(K:box("StSpinPocket", V3(0.62, 0.62, 0.05), fc * CF(0, 0.31, 0.12), { c = C(230, 236, 240), m = M.Glass, t = 0.5 }))
				local col = ({ C(40, 120, 200), C(250, 160, 60), C(60, 170, 150), C(220, 80, 90), C(250, 220, 80), C(120, 90, 200) })[(t + f) % 6 + 1]
				keep(K:box("StPostcard", V3(0.56, 0.74, 0.02), fc * CF(0, 0.4, 0.09), lk(col)))
				if K.detail == "high" and (t + f) % 2 == 0 then
					keep(K:plate("StPostcardSky", 0.5, 0.22, 0.005, fc * CF(0, 0.6, 0.1), lk(lighter(col, 0.5))))
				end
			else
				keep(K:box("StLipShelf", V3(0.7, 0.04, 0.3), fc * CF(0, 0, 0.1), lk(C(250, 250, 250))))
				for j = 0, 3 do
					local col = SKU.lip.cols[(t + j + f) % #SKU.lip.cols + 1]
					keep(K:vcyl("StLipTester", 0.3, 0.1, fc * CF(-0.24 + j * 0.16, 0.17, 0.12), lk(col)))
				end
			end
		end
	end
	if kind == "postcard" then
		keep(K:box("StSpinTop", V3(0.9, 0.5, 0.9), pcf * CF(0, h + 0.25, 0), lk(C(30, 80, 160))))
		txt(K, "StSpinTopText", 0.86, 0.4, pcf * CF(0, h + 0.25, 0.451), "POSTCARD 1,500", WHITE, nil, { d = 0.01 })
	end
	local center = (K.cf * pcf).Position
	local base = {}
	for _, p in parts do
		table.insert(base, { p = p, cf = p.CFrame })
	end
	local angle = 0
	local nv: NumberValue? = nil
	local pr = promptOn(K, parts, {
		action = "돌려 보기",
		object = object,
		sound = "rbxasset://sounds/clickfast.wav",
		fn = function()
			if not nv then
				local v = Instance.new("NumberValue")
				v.Name = "GwSpinAngle"
				v.Value = 0
				v.Parent = parts[1]
				v.Changed:Connect(function(a: number)
					local rot = CFrame.new(center) * CFrame.Angles(0, a, 0) * CFrame.new(-center)
					for _, b in base do
						if b.p.Parent then
							b.p.CFrame = rot * b.cf
						end
					end
				end)
				nv = v
			end
			angle += PI / 2
			TweenService:Create(nv :: NumberValue, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = angle }):Play()
		end,
	})
	return pr
end

-- 광안대교 LED 모형 (벽): 조명 쇼 순환
local function bridgeModel(K: any, dcf: CFrame, w: number)
	local h = w * 0.36
	K:plate("StBridgeBack", w + 0.3, h + 0.3, 0.06, dcf, lk(C(12, 20, 40)))
	-- 바다 · 하늘 · 마린시티 야경 실루엣
	K:plate("StBridgeSea", w, h * 0.28, 0.07, dcf * CF(0, -h * 0.36, 0), lk(C(20, 40, 80)))
	for i = 0, 6 do
		local tw = 0.32 + (i % 3) * 0.08
		local thh = h * (0.32 + ((i * 37) % 5) * 0.07)
		local tx = w * 0.18 + i * 0.36
		if tx + tw / 2 < w / 2 - 0.1 then
			K:plate("StSkyline", tw, thh, 0.065, dcf * CF(tx, -h * 0.22 + thh / 2, 0), lk(C(24, 30, 56)))
			if K.detail ~= "low" then
				K:plate("StSkylineLit", tw * 0.4, thh * 0.7, 0.068, dcf * CF(tx, -h * 0.22 + thh * 0.45, 0), Look.neon(C(255, 214, 140), 0.3))
			end
		end
	end
	local leds: { BasePart } = {}
	-- 상판 (2층 교량)
	local deckY = -h * 0.12
	K:plate("StBridgeDeck", w * 0.96, 0.1, 0.12, dcf * CF(0, deckY, 0), lk(C(200, 204, 210), M.Metal))
	K:plate("StBridgeDeck2", w * 0.96, 0.08, 0.12, dcf * CF(0, deckY - 0.2, 0), lk(C(180, 184, 190), M.Metal))
	table.insert(leds, K:plate("StBridgeDeckLED", w * 0.96, 0.04, 0.14, dcf * CF(0, deckY - 0.08, 0), Look.neon(C(70, 170, 255))))
	-- 주탑 2개 + 케이블 (현수교)
	local towers = { -w * 0.22, w * 0.22 }
	for _, tx in towers do
		K:plate("StBridgeTower", 0.12, h * 0.62, 0.14, dcf * CF(tx - 0.12, deckY + h * 0.2, 0), lk(C(220, 224, 228), M.Metal))
		K:plate("StBridgeTower", 0.12, h * 0.62, 0.14, dcf * CF(tx + 0.12, deckY + h * 0.2, 0), lk(C(220, 224, 228), M.Metal))
		table.insert(leds, K:plate("StBridgeTowerLED", 0.06, h * 0.58, 0.16, dcf * CF(tx, deckY + h * 0.2, 0), Look.neon(C(70, 170, 255))))
	end
	local topY = deckY + h * 0.5
	local pts = {}
	local N = if K.detail == "high" then 12 else 7
	for i = 0, N do
		local t = i / N
		local x = -w * 0.48 + t * w * 0.96
		local y: number
		if x < towers[1] then
			local k = (x - (-w * 0.48)) / (towers[1] + w * 0.48)
			y = deckY + 0.05 + (topY - deckY - 0.05) * k * k
		elseif x > towers[2] then
			local k = (w * 0.48 - x) / (w * 0.48 - towers[2])
			y = deckY + 0.05 + (topY - deckY - 0.05) * k * k
		else
			local k = (x - towers[1]) / (towers[2] - towers[1]) * 2 - 1
			y = deckY + 0.15 + (topY - deckY - 0.15) * k * k
		end
		table.insert(pts, (dcf * CF(x, y, 0.12)).Position)
	end
	for i = 1, #pts - 1 do
		local p = K:seg("StBridgeCableLED", pts[i], pts[i + 1], 0.06, Look.neon(C(70, 170, 255)))
		if p then
			table.insert(leds, p)
		end
	end
	txt(K, "StBridgeTitle", w * 0.5, 0.3, dcf * CF(0, h / 2 - 0.12, 0.07), "광안대교 GWANGAN BRIDGE", C(220, 230, 250), nil, { d = 0.005, glow = 1.2 })
	local schemes = {
		{ "기본 블루", function(_i: number, _n: number): Color3
			return C(70, 170, 255)
		end },
		{ "레인보우", function(i: number, n: number): Color3
			return Color3.fromHSV((i / n) % 1, 0.8, 1)
		end },
		{ "불꽃축제", function(i: number, _n: number): Color3
			return if i % 3 == 0 then C(255, 80, 60) elseif i % 3 == 1 then C(255, 200, 60) else C(255, 255, 255)
		end },
		{ "바다 웨이브", function(i: number, n: number): Color3
			return Color3.fromHSV(0.5 + 0.12 * math.sin(i / n * PI * 2), 0.7, 1)
		end },
	}
	local function apply(k: number)
		local f = schemes[k][2]
		for i, p in leds do
			if p.Parent then
				p.Color = f(i, #leds)
			end
		end
	end
	local pp = firstOk(K, leds)
	if not pp then
		note(K, "no prompt spot: bridge")
		return
	end
	Interact.cycle(K, pp, schemes, {
		action = "조명 쇼 바꾸기",
		object = "광안대교 LED 모형",
		on = function(i: number)
			apply(i)
		end,
	})
end

-- 티셔츠 (옷걸이에 걸린 것): pcf = 어깨선 가운데, +Z = 앞면. w 폭, h 길이
local function tshirt(K: any, cf: CFrame, w: number, h: number, col: Color3, print: string?, hi: boolean)
	local L = lk(col, M.Fabric)
	K:box("StShirtBody", V3(w, h, 0.07), cf * CF(0, -h / 2, 0), L)
	if hi then
		for _, sx in { -1, 1 } do
			K:box("StShirtSleeve", V3(w * 0.34, h * 0.3, 0.07), cf * CF(sx * (w / 2 + w * 0.1), -h * 0.14, 0) * ANG(0, 0, sx * 0.5), L)
		end
		K:box("StShirtCollar", V3(w * 0.3, 0.06, 0.08), cf * CF(0, -0.03, 0.005), lk(darker(col, 0.2), M.Fabric))
	end
	if print and hi then
		txt(K, "StShirtPrint", w * 0.7, h * 0.3, cf * CF(0, -h * 0.4, 0.036), print, if col.R + col.G + col.B > 2 then C(30, 60, 140) else WHITE, nil, { d = 0.005, font = Enum.Font.GothamBlack })
	end
end

-- 옷걸이 + 셔츠 (봉에 수직으로 걸림): rail 위 점 p, 셔츠 면 방향 n (봉 방향)
local function hangerShirt(K: any, p: Vector3, n: Vector3, col: Color3, hi: boolean, h: number)
	local cf = dcfAt(p - V3(0, 0.25, 0), n)
	K:seg("StHangerHook", p + V3(0, 0.08, 0), p - V3(0, 0.22, 0), 0.03, Look.chrome)
	K:box("StHanger", V3(1.3, 0.06, 0.05), cf * CF(0, 0, 0), lk(C(214, 186, 148), M.Wood))
	tshirt(K, cf * CF(0, -0.02, 0), 1.4, h, col, nil, hi)
end

-- 맵 옷걸이 봉 (Rail + RailPost) 의 Shirt 를 숨기고 다시 걸기
local function railShirts(K: any, V: any, cols: { Color3 }, rng: () -> number)
	local rail = V:first("Rail")
	if not rail then
		return
	end
	local shirts = V.byName.Shirt or {}
	local alongX = rail.size.X >= rail.size.Z
	local n = alongX and V3(1, 0, 0) or V3(0, 0, 1)
	local hi = K.detail ~= "low"
	K:free(function()
		for i, s in shirts do
			local p = if alongX then V3(s.c.X, rail.max.Y + 0.02, rail.c.Z) else V3(rail.c.X, rail.max.Y + 0.02, s.c.Z)
			local h = math.min(2.3, rail.max.Y - 1.2)
			hangerShirt(K, p, n, pick(rng, cols), hi and (i % 2 == 0 or K.detail == "high"), h)
			Scan.hide(K.hidden, s.part)
		end
		-- 봉 끝 사이즈 표 · 가격
		local endp = if alongX then V3(rail.max.X + 0.02, rail.max.Y - 0.6, rail.c.Z) else V3(rail.c.X, rail.max.Y - 0.6, rail.max.Z + 0.02)
		txt(K, "StRailPrice", 0.9, 0.6, dcfAt(endp, n), "티셔츠\n15,000\n2장 25,000", INK, C(250, 250, 248), { d = 0.02, font = Enum.Font.GothamBold })
	end)
end

-- 진열 테이블 (맵 DisplayTable) 원목 리스킨 + 위 상품
local function displayTable(K: any, V: any, kind: string, rng: () -> number)
	for _, dt in V.byName.DisplayTable or {} do
		local mn, mx = dt.min, dt.max
		local top = mx.Y
		local cx, cz = dt.c.X, dt.c.Z
		local w, d = dt.size.X, dt.size.Z
		K:free(function()
			K:box("StDTTop", V3(w, 0.16, d), CF(cx, top - 0.08, cz), Look.oak)
			K:box("StDTApron", V3(w - 0.2, 0.36, d - 0.2), CF(cx, top - 0.34, cz), Look.walnut)
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					K:box("StDTLeg", V3(0.18, top - 0.16, 0.18), CF(cx + sx * (w / 2 - 0.2), (top - 0.16) / 2, cz + sz * (d / 2 - 0.2)), Look.walnut)
				end
			end
			K:box("StDTShelf", V3(w - 0.3, 0.1, d - 0.3), CF(cx, 0.55, cz), Look.oak)
			-- 아래 칸: 박스 재고
			for i = 0, 2 do
				K:box("StDTStock", V3(1.4, 0.7, d - 0.6), CF(cx - w / 2 + 1.0 + i * (w - 2) / 2, 0.95, cz), Look.kraft)
			end
			-- 위 상품
			local alongX = w >= d
			if kind == "beach" then
				-- 튜브 (도넛) 쌓기 + 비치볼
				local tubeCols = { C(250, 120, 40), C(40, 160, 230), C(250, 210, 60), C(240, 80, 140), C(60, 200, 150) }
				for i = 0, 2 do
					local px = cx - w / 2 + 1.1 + i * 1.6
					for j = 0, 1 do
						local ring = CF(px, top + 0.14 + j * 0.27, cz - 0.3) * ANG(PI / 2, 0, 0)
						K:ring("StTube", ring, 0.48, 0.28, if K.detail == "high" then 10 else 7, lk(tubeCols[(i + j) % #tubeCols + 1], M.Plastic))
					end
				end
				for i = 0, 1 do
					K:ball("StBeachBall", 0.7, CF(cx + w / 2 - 1.0 - i * 0.8, top + 0.35, cz + 0.4), lk(({ C(250, 250, 250), C(250, 210, 60) })[i + 1], M.Plastic))
					K:ell("StBeachBallStripe", V3(0.72, 0.72, 0.2), CF(cx + w / 2 - 1.0 - i * 0.8, top + 0.35, cz + 0.4), lk(({ C(230, 40, 50), C(40, 120, 220) })[i + 1], M.Plastic))
				end
				txt(K, "StDTSign", 1.4, 0.5, dcfAt(V3(cx, top + 0.5, mx.Z + 0.01), V3(0, 0, 1)) * CF(0, -0.25 - 0.4, 0), "튜브 판매 12,000~", WHITE, C(30, 120, 200), { d = 0.02 })
			else
				-- 기념품: 어묵 선물세트 · 머그 · 스노우볼 · 갈매기 인형
				local surf = { cf = CFrame.fromMatrix(V3(cx, top, if alongX then mx.Z - 0.05 else cz), V3(1, 0, 0), Vector3.yAxis, V3(0, 0, 1)), len = w - 0.4, depth = d * 0.45, clear = 1.4, rail = false, level = 2, levels = 3 }
				fillSurf(K, surf, "gift", rng, {}, { back = false, facing = 1 })
				local surf2 = { cf = CFrame.fromMatrix(V3(cx, top, mn.Z + 0.05), V3(-1, 0, 0), Vector3.yAxis, V3(0, 0, -1)), len = w - 0.4, depth = d * 0.45, clear = 1.4, rail = false, level = 1, levels = 3 }
				fillSurf(K, surf2, "gift", rng, {}, { back = false, facing = 1 })
				txt(K, "StDTSign", 1.6, 0.6, dcfAt(V3(cx, top - 0.34, mx.Z + 0.01), V3(0, 0, 1)), "부산 기념 선물세트\n어묵 · 씨앗호떡 · 머그", WHITE, C(30, 80, 160), { d = 0.02 })
			end
		end)
		Scan.hide(K.hidden, dt.part)
		for _, f in V.byName.Float or {} do
			if f.c.X > mn.X - 0.3 and f.c.X < mx.X + 0.3 and f.c.Z > mn.Z - 0.3 and f.c.Z < mx.Z + 0.3 then
				Scan.hide(K.hidden, f.part)
			end
		end
		K:reserve(mn - V3(1.2, 0, 1.2), mx + V3(1.2, 0, 1.2), "front")
	end
end

-- 기념품 · 비치 벽 (맵 WallRack 앞면의 Goods 자리): 유공보드 + 걸이 상품 + 선반
local function goodsWall(K: any, V: any, kind: string, rng: () -> number)
	local wr = V:first("WallRack")
	local goods = V.byName.Goods or {}
	if not wr then
		return
	end
	local face = V3(0, 0, 1)
	if wr.size.X < wr.size.Z then
		face = V3(if wr.c.X < 0 then 1 else -1, 0, 0)
	end
	local fz = if math.abs(face.Z) > 0.5 then wr.max.Z else (if face.X > 0 then wr.max.X else wr.min.X)
	local hi = K.detail == "high"
	local sections = {}
	for _, g in goods do
		table.insert(sections, g)
		Scan.hide(K.hidden, g.part)
	end
	if #sections == 0 then
		table.insert(sections, { min = V3(wr.min.X + 0.5, 2.0, wr.min.Z), max = V3(wr.max.X - 0.5, wr.max.Y - 1.0, wr.max.Z), c = wr.c, size = wr.size })
	end
	table.sort(sections, function(a, b)
		return a.c.X < b.c.X
	end)
	K:free(function()
		for si, g in sections do
			local w = (if math.abs(face.Z) > 0.5 then g.size.X else g.size.Z) - 0.2
			local y0, y1 = math.max(1.4, g.min.Y - 0.6), math.min(wr.max.Y - 0.4, g.max.Y + 0.2)
			local p = if math.abs(face.Z) > 0.5 then V3(g.c.X, (y0 + y1) / 2, fz) else V3(fz, (y0 + y1) / 2, g.c.Z)
			local d = dcfAt(p, face)
			local h = y1 - y0
			local role = if kind == "beach" then ({ "rings", "wear", "shelves" })[(si - 1) % 3 + 1] else ({ "magnets", "shirts", "shelves" })[(si - 1) % 3 + 1]
			-- 바탕 보드
			K:plate("StPegBoard", w, h, 0.05, d, lk(if role == "magnets" then C(30, 60, 120) else C(236, 230, 218)))
			K:plate("StPegBoardTrim", w + 0.12, 0.1, 0.07, d * CF(0, h / 2, 0), Look.walnut)
			K:plate("StPegBoardTrim", w + 0.12, 0.1, 0.07, d * CF(0, -h / 2, 0), Look.walnut)
			local title = ({ magnets = "광안리 마그넷 · 키링", shirts = "BUSAN T-SHIRTS", shelves = if kind == "beach" then "선크림 · 물놀이 용품" else "부산 기념 선물", rings = "튜브 · 비치볼", wear = "래쉬가드 · 수영복" })[role]
			txt(K, "StGoodsTitle", w * 0.8, 0.5, d * CF(0, h / 2 + 0.42, 0.04), title, WHITE, if kind == "beach" then C(30, 120, 200) else C(30, 60, 120), { d = 0.04, font = Enum.Font.GothamBlack })
			if role == "magnets" then
				local cols = math.floor((w - 0.4) / (if hi then 0.42 else 0.6))
				local rows = math.floor((h - 0.6) / (if hi then 0.46 else 0.66))
				for i = 1, cols do
					for j = 1, rows do
						local x = -w / 2 + 0.2 + (i - 0.5) * (w - 0.4) / cols
						local y = -h / 2 + 0.3 + (j - 0.5) * (h - 0.6) / rows
						local r = rng()
						if j % 3 == 0 then
							-- 키링 (고리 + 작은 모형)
							K:seg("StKeyHook", (d * CF(x, y + 0.18, 0.05)).Position, (d * CF(x, y + 0.18, 0.3)).Position, 0.03, Look.chrome)
							K:box("StKeyring", V3(0.2, 0.26, 0.06), d * CF(x, y - 0.02, 0.26), lk(pick(rng, { C(250, 210, 60), C(240, 80, 120), C(60, 170, 220), C(250, 250, 250) })))
						else
							local col = pick(rng, { C(250, 250, 250), C(250, 210, 60), C(60, 170, 220), C(240, 120, 80), C(120, 200, 140), C(240, 160, 200) })
							K:plate("StMagnet", 0.34 + r * 0.06, 0.3, 0.05, d * CF(x, y, 0.05), lk(col))
							if hi and r < 0.4 then
								K:plate("StMagnetArt", 0.24, 0.08, 0.055, d * CF(x, y - 0.04, 0.05), lk(C(30, 80, 160)))
							end
						end
					end
				end
			elseif role == "shirts" or role == "wear" then
				local n = math.max(1, math.floor(w / 2.0))
				for i = 1, n do
					local x = -w / 2 + (i - 0.5) * w / n
					local col = pick(rng, if role == "wear" then { C(30, 60, 140), C(240, 80, 120), C(30, 30, 34), C(60, 180, 170) } else { C(250, 250, 250), C(30, 60, 140), C(240, 200, 60), C(240, 240, 236), C(200, 40, 50) })
					K:seg("StWallHook", (d * CF(x, h / 2 - 0.35, 0.05)).Position, (d * CF(x, h / 2 - 0.35, 0.3)).Position, 0.04, Look.chrome)
					K:box("StHanger", V3(1.3, 0.06, 0.05), d * CF(x, h / 2 - 0.55, 0.25), lk(C(214, 186, 148), M.Wood))
					tshirt(K, d * CF(x, h / 2 - 0.58, 0.27), 1.5, math.min(1.9, h - 2.8), col, if role == "shirts" then (if i % 2 == 0 then "I ♥ BUSAN" else "광안리\nGWANGALLI") else nil, K.detail ~= "low")
				end
				-- 아래 선반: 개어 놓은 티셔츠 · 래쉬가드 더미 + 가격
				if h > 3.6 then
					local y = -h / 2 + 0.75
					K:box("StGoodsShelf", V3(w - 0.1, 0.08, 0.8), d * CF(0, y, 0.4), Look.oak)
					for _, sx in { -1, 1 } do
						K:bar("StGoodsBracket", (d * CF(sx * (w / 2 - 0.4), y - 0.35, 0.03)).Position, (d * CF(sx * (w / 2 - 0.4), y - 0.04, 0.6)).Position, 0.05, 0.05, Look.blackMetal)
					end
					local ns = math.max(1, math.floor((w - 0.2) / 0.95))
					local fcols = if role == "wear" then { C(30, 60, 140), C(240, 80, 120), C(30, 30, 34), C(60, 180, 170), C(250, 160, 40) } else { C(250, 250, 250), C(30, 60, 140), C(240, 200, 60), C(200, 40, 50), C(120, 180, 220), C(40, 40, 44) }
					for k = 1, ns do
						local x = -w / 2 + 0.1 + (k - 0.5) * (w - 0.2) / ns
						local col = fcols[(k + si) % #fcols + 1]
						local sh = 0.5 + (k % 3) * 0.12
						K:box("StFoldedShirts", V3(0.82, sh, 0.66), d * CF(x, y + 0.04 + sh / 2, 0.42), lk(col, M.Fabric))
						if K.detail ~= "low" then
							for f = 1, 2 do
								K:plate("StFoldLine", 0.82, 0.03, 0.01, d * CF(x, y + 0.04 + sh * f / 3, 0.75), lk(darker(col, 0.25), M.Fabric))
							end
						end
					end
					txt(K, "StShirtPrice", 1.6, 0.3, d * CF(0, y - 0.25, 0.81), if role == "wear" then "래쉬가드 29,000 · 아동 19,000" else "티셔츠 15,000 · 2장 25,000", INK, C(250, 250, 248), { d = 0.01 })
				end
			elseif role == "rings" then
				local n = math.max(1, math.floor(w / 1.5))
				for i = 1, n do
					local x = -w / 2 + (i - 0.5) * w / n
					for j = 0, 1 do
						local y = h / 2 - 0.9 - j * 1.6
						if y > -h / 2 + 0.6 then
							K:seg("StWallHook", (d * CF(x, y + 0.6, 0.05)).Position, (d * CF(x, y + 0.6, 0.3)).Position, 0.04, Look.chrome)
							K:ring("StWallTube", d * CF(x, y, 0.3), 0.5, 0.26, if hi then 10 else 7, lk(pick(rng, { C(250, 120, 40), C(40, 160, 230), C(250, 210, 60), C(240, 80, 140), C(60, 200, 150) }), M.Plastic))
						end
					end
				end
			else
				-- 선반 3단 + 상품
				local lv = 3
				for j = 1, lv do
					local y = -h / 2 + 0.2 + (j - 1) * (h - 0.4) / lv
					K:box("StGoodsShelf", V3(w - 0.1, 0.08, 0.8), d * CF(0, y, 0.4), Look.oak)
					for _, sx in { -1, 1 } do
						K:bar("StGoodsBracket", (d * CF(sx * (w / 2 - 0.4), y - 0.35, 0.03)).Position, (d * CF(sx * (w / 2 - 0.4), y - 0.04, 0.6)).Position, 0.05, 0.05, Look.blackMetal)
					end
					local scf = d * CF(0, y + 0.04, 0.8)
					local surf = { cf = CFrame.fromMatrix(scf.Position, scf.XVector, scf.YVector, scf.ZVector), len = w - 0.3, depth = 0.75, clear = (h - 0.4) / lv - 0.15, rail = false, level = j, levels = lv }
					queueFill(K, surf, if kind == "beach" then "beachgoods" else "gift", V.key .. "gw" .. si .. j, {}, { back = false })
				end
			end
		end
	end)
end

local function buildRetail(K: any, V: any, S: any, sub: string)
	local rng = mkRng(V.key .. sub)
	local surfs = mapSurfaces(V)
	local obst = obstacles(V)
	local used = 0
	for _, g in V.counters do
		reserveFront(K, g.min, g.max, counterFace(V, g), 2.6, 0.4)
	end
	for _, s in surfs do
		local r = s.rec
		local fwd = s.cf.ZVector
		reserveFront(K, r.min, r.max, V3(math.round(fwd.X), 0, math.round(fwd.Z)), 2.4, 0.2)
	end
	for _, nm in { "TesterTable", "Mirror", "WallRack", "Rail" } do
		for _, r in V.byName[nm] or {} do
			reserveFront(K, r.min, r.max, awayFromWall(V, r), 2.4, 0.4)
			if nm == "Rail" then
				K:reserve(r.min - V3(1.4, 0, 1.4), r.max + V3(1.4, 0, 1.4), "front")
			end
		end
	end
	for _, nm in { "Product" } do
		for _, r in V.byName[nm] or {} do
			Scan.hide(K.hidden, r.part)
		end
	end
	if sub == "cosmetics" then
		local theme = { promo1 = OY.sub, promo2 = OY.main, p11 = 0.12, p21 = 0.05, pSale = 0.12, saleText = "올영세일", promo3 = C(230, 40, 50), maxTagText = 34, prices = { "9,900", "12,900", "15,800", "18,000", "22,400", "24,900", "8,500", "31,000" } }
		-- 벽 칸: 구역(긴 판을 3~4 칸 세로 블록)마다 범주
		local wallCats = { "skincare", "makeup", "maskcare", "hairbody", "health" }
		local gondCats = { "makeup", "skincare", "maskcare", "hairbody" }
		local faceIdx = 0
		local faceCat: { [string]: any } = {}
		step(K, "shelves", function()
			K:free(function()
				for _, s in surfs do
					if s.len > 6 then
						-- 긴 벽 칸: 블록 단위로 쪼갬
						local nb = math.max(1, math.floor(s.len / 3.7 + 0.5))
						local bw = s.len / nb
						for bi = 1, nb do
							local key = s.face .. "#" .. bi
							if not faceCat[key] then
								faceIdx += 1
								faceCat[key] = wallCats[(faceIdx - 1) % #wallCats + 1]
							end
							local sub2 = { cf = s.cf * CF(-s.len / 2 + bw * (bi - 0.5), 0, 0), len = bw - 0.16, depth = s.depth, clear = s.clear, rail = s.rail, level = s.level, levels = s.levels }
							queueFill(K, sub2, faceCat[key], V.key .. key .. (s.level or 0), theme, { obst = obst, scale = 1.15, facing = 2 })
						end
					else
						if not faceCat[s.face] then
							faceIdx += 1
							faceCat[s.face] = gondCats[(faceIdx - 1) % #gondCats + 1]
						end
						queueFill(K, s, faceCat[s.face], V.key .. s.face .. (s.level or 0), theme, { obst = obst, scale = 1.15 })
					end
				end
			end)
		end)
		-- 벽 칸 머리 (맵 Header) 범주 글자
		step(K, "headers", function()
			local names = { "스킨케어 SKINCARE", "메이크업 MAKEUP", "마스크팩 · 선케어", "헤어 · 바디 HAIR & BODY", "건강식품 HEALTH" }
			for i, hd in V.byName.Header or {} do
				local face = if hd.size.X >= hd.size.Z then V3(0, 0, if hd.c.Z < 0 then 1 else -1) else V3(if hd.c.X < 0 then 1 else -1, 0, 0)
				local fpos = if math.abs(face.Z) > 0.5 then (if face.Z > 0 then hd.max.Z else hd.min.Z) else (if face.X > 0 then hd.max.X else hd.min.X)
				local p = if math.abs(face.Z) > 0.5 then V3(hd.c.X, hd.c.Y, fpos) else V3(fpos, hd.c.Y, hd.c.Z)
				local w = math.max(hd.size.X, hd.size.Z)
				K:free(function()
					K:plate("StHeaderSkin", w, hd.size.Y, 0.02, dcfAt(p, face), lk(OY.white))
					K:plate("StHeaderLine", w, 0.08, 0.03, dcfAt(p - V3(0, hd.size.Y / 2 - 0.04, 0), face), lk(OY.main))
					txt(K, "StHeaderText", w * 0.6, hd.size.Y * 0.7, dcfAt(p, face) * CF(0, 0.02, 0.03), names[(i - 1) % #names + 1], OY.dark, nil, { font = Enum.Font.GothamBlack })
				end)
			end
			local promos = { { "올영세일", "최대 70% · 10.24 ~ 10.30" }, { "오늘의 특가", "오특 단 하루 특가" }, { "1+1", "선크림 · 마스크팩" }, { "NEW", "올리브영 단독 런칭" } }
			for i, ep in V.byName.EndPanel or {} do
				local thinX = ep.size.X < ep.size.Z
				local cen = nil
				for _, s in surfs do
					if overlapXZ(s.rec, ep, 0.6) then
						cen = s.rec.c
					end
				end
				local face = if thinX then V3(if cen and cen.X > ep.c.X then -1 else 1, 0, 0) else V3(0, 0, if cen and cen.Z > ep.c.Z then -1 else 1)
				local fpos = if thinX then (if face.X > 0 then ep.max.X else ep.min.X) else (if face.Z > 0 then ep.max.Z else ep.min.Z)
				local w = if thinX then ep.size.Z else ep.size.X
				local p = if thinX then V3(fpos, ep.size.Y * 0.52, ep.c.Z) else V3(ep.c.X, ep.size.Y * 0.52, fpos)
				local pr = promos[(i - 1) % #promos + 1]
				K:free(function()
					poster(K, dcfAt(p, face) * CF(0, 0, -0.05), w - 0.4, ep.size.Y - 1.0, pr[1], pr[2], OY.white, OY.dark, if i % 2 == 0 then OY.sub else OY.main, WHITE, { titleH = 0.4, frame = false })
				end)
				for _, eh in V.byName.EndHeader or {} do
					if overlapXZ(eh, ep, 0.05) then
						local hp = if thinX then V3((if face.X > 0 then eh.max.X else eh.min.X), eh.c.Y, eh.c.Z) else V3(eh.c.X, eh.c.Y, (if face.Z > 0 then eh.max.Z else eh.min.Z))
						K:free(function()
							txt(K, "StEndHeaderText", w - 0.2, eh.size.Y * 0.7, dcfAt(hp, face), "OLIVE YOUNG", WHITE, nil, { d = 0.015, font = Enum.Font.GothamBlack })
						end)
					end
				end
			end
		end)
		-- 테스터 테이블: 거울 위 조명 바 + 안내
		step(K, "tester", function()
			local mr = V:first("Mirror")
			if mr then
				Scan.hide(K.hidden, mr.part)
				local face = V3(0, 0, 1)
				local tt = V:first("TesterTable")
				if tt then
					face = if math.abs(mr.c.Z - tt.c.Z) > math.abs(mr.c.X - tt.c.X) then V3(0, 0, math.sign(tt.c.Z - mr.c.Z)) else V3(math.sign(tt.c.X - mr.c.X), 0, 0)
				end
				local fpos = if math.abs(face.Z) > 0.5 then (if face.Z > 0 then mr.max.Z else mr.min.Z) else (if face.X > 0 then mr.max.X else mr.min.X)
				local w = math.max(mr.size.X, mr.size.Z)
				local p = if math.abs(face.Z) > 0.5 then V3(mr.c.X, mr.max.Y + 0.2, fpos) else V3(fpos, mr.max.Y + 0.2, mr.c.Z)
				K:free(function()
					local mc = dcfAt(if math.abs(face.Z) > 0.5 then V3(mr.c.X, mr.c.Y, if face.Z > 0 then mr.min.Z else mr.max.Z) else V3(if face.X > 0 then mr.min.X else mr.max.X, mr.c.Y, mr.c.Z), face)
					local th = if math.abs(face.Z) > 0.5 then mr.size.Z else mr.size.X
					K:plate("StMirrorFrame", w, mr.size.Y, th * 0.6, mc, lk(C(250, 250, 250)))
					K:plate("StMirrorGlass", w - 0.16, mr.size.Y - 0.16, th + 0.01, mc, Look.mirror)
					K:plate("StMirrorLightBar", w, 0.24, 0.12, dcfAt(p, face), lk(C(250, 250, 250)))
					K:plate("StMirrorLight", w - 0.2, 0.08, 0.13, dcfAt(p - V3(0, 0.06, 0), face), Look.lampNeutral)
					txt(K, "StTesterSign", w * 0.7, 0.4, dcfAt(p + V3(0, 0.45, 0), face), "TESTER · 테스터는 자유롭게 사용해 보세요", OY.dark, OY.white, { d = 0.02 })
				end)
			end
		end)
		-- 계산대
		step(K, "cashier", function()
			for _, g in V.counters do
				cashierDress(K, V, g, OY, "cosmetics")
			end
		end)
		-- 빈 바닥: 아일랜드 진열대 (큰 매장)
		step(K, "did", function()
			local wn, dcf = wallItemSpot(K, { "right", "left", "back" }, 4.0, 4.8, 7.0, 0, function(d: CFrame): boolean
				return promptOk(K, d.Position)
			end)
			if wn and dcf then
				didScreen(K, dcf, 3.6, {
					{ text = "올영세일\n최대 70% OFF", c = OY.main },
					{ text = "NEW 선크림\n1+1 기획", c = C(250, 160, 40) },
					{ text = "오늘드림\n3시간 빠른 배송", c = OY.sub },
					{ text = "OLIVE YOUNG\n건강한 아름다움", c = C(40, 40, 40) },
				}, "뷰티 광고 화면")
			end
		end)
		step(K, "vanity", function()
			local wn, dcf = wallItemSpot(K, { "left", "right", "back" }, 3.4, 3.0, 6.6, 0, function(d: CFrame): boolean
				return promptOk(K, (d * CF(-1.3, 1.6, 0)).Position) or promptOk(K, (d * CF(1.3, 1.6, 0)).Position)
			end)
			if wn and dcf then
				vanityMirror(K, dcf * CF(0, 0, 0.04), 2.6, 3.0)
				-- 아래 선반 (화장대 상판)
				K:box("StVanityShelf", V3(3.0, 0.1, 0.8), dcf * CF(0, -1.85, 0.4), lk(C(250, 250, 250)))
				local scf = dcf * CF(0, -1.8, 0.8)
				fillSurf(K, { cf = scf, len = 2.8, depth = 0.7, clear = 0.8, rail = false, level = 2, levels = 3 }, "makeup", mkRng(V.key .. "van"), theme, { back = false })
			end
		end)
		step(K, "islands", function()
			local cands = {}
			local cx0 = (V.x0 + V.x1) / 2
			for gx = V.x0 + 4, V.x1 - 4, 2.0 do
				for gz = V.z0 + 5, V.z1 - 5, 2.0 do
					table.insert(cands, V3(gx, 0, gz))
				end
			end
			table.sort(cands, function(a, b)
				return math.abs(a.X - cx0) > math.abs(b.X - cx0)
			end)
			local cats = { "makeup", "maskcare", "skincare", "health" }
			local n = 0
			local maxN = math.clamp(math.floor(V.W * V.D / 220), 0, 4)
			for _, p in cands do
				if n >= maxN then
					break
				end
				yieldy(K)
				local len, w, h = 6.4, 2.6, 4.2
				local pcf = pcfAt(V3(p.X, 0, p.Z), V3(1, 0, 0)) -- 긴 방향 = Z 축 (앞쪽 = +X)
				local cf2 = CFrame.fromMatrix(pcf.Position, V3(0, 0, 1), Vector3.yAxis, V3(-1, 0, 0))
				local mn, mx = canPlace(K, cf2, V3(len, h + 0.6, w), 2.4)
				if mn and mx then
					local mn2, mx2 = K.laabb(cf2 * CF(0, (h + 0.6) / 2, 0), V3(len, h + 0.6, w))
					K:reserve(mn2, mx2, "island")
					n += 1
					local us = island(K, cf2, len, w, h, { levels = 3, topL = lk(OY.white), kick = lk(C(60, 64, 60)) })
					K:free(function()
						for _, s in us do
							queueFill(K, s, cats[(n - 1) % #cats + 1], V.key .. "is" .. n .. s.level .. s.side, theme, { scale = 1.15 })
						end
						-- 끝판 POP
						for _, sx in { -1, 1 } do
							local d = cf2 * CF(sx * (len / 2), h * 0.55, 0) * ANG(0, sx * PI / 2, 0)
							poster(K, d, w - 0.4, h - 1.6, if n % 2 == 0 then "1+1" else "올영픽", if n % 2 == 0 then "마스크팩 · 선케어" else "이번 주 추천 아이템", OY.white, OY.dark, if sx > 0 then OY.main else OY.sub, WHITE, { titleH = 0.4, frame = false, off = 0.02 })
						end
					end)
				end
			end
		end)
		step(K, "baskets", function()
			local d = V.door
			local cands = {}
			if d then
				for _, dx in { 5.4, -5.4, 6.6, -6.6 } do
					table.insert(cands, V3(d.x + dx, 0, V.z1 - 3.0))
				end
			end
			local pcf = floorSpot(K, cands, V3(1.5, 2.2, 1.1), V3(0, 0, 1), 0.05, "basket")
			if pcf then
				basketStack(K, pcf, OY.dark, 6, "OLIVE YOUNG")
			end
		end)
		-- 창가 낮은 행사 테이블 (올영세일 · 오특)
		step(K, "promoTables", function()
			local cands = {}
			for gx = V.x0 + 3, V.x1 - 3, 1.0 do
				table.insert(cands, V3(gx, 0, V.z1 - 3.2))
				table.insert(cands, V3(gx, 0, V.z1 - 4.4))
			end
			table.sort(cands, function(a, b)
				return math.abs(a.X) > math.abs(b.X)
			end)
			local n = 0
			local maxN = if V.W > 36 then 3 elseif V.W > 24 then 2 else 1
			local pops = { { "오특", "오늘의 특가 단 하루", OY.sub }, { "1+1", "선크림 · 립밤 기획", OY.main }, { "NEW", "이달의 신상 뷰티", OY.dark } }
			for _, p in cands do
				if n >= maxN then
					break
				end
				yieldy(K)
				local pcf = pcfAt(V3(p.X, 0, p.Z), V3(0, 0, 1))
				local mn, mx = canPlace(K, pcf, V3(3.4, 3.3, 2.0), 1.2)
				if mn and mx then
					local mn2, mx2 = K.laabb(pcf * CF(0, 1.65, 0), V3(3.4 + 1.2, 3.3, 2.0 + 1.2))
					K:reserve(mn2, mx2, "promo")
					n += 1
					local pp = pops[(n - 1) % #pops + 1]
					local us = promoTable(K, pcf, 3.4, 2.0, lk(OY.white), pp[1], pp[2], pp[3])
					for _, su in us do
						queueFill(K, su, if n % 2 == 0 then "skincare" else "makeup", V.key .. "pt" .. n .. su.level, theme, { back = false, scale = 1.1, noTags = true })
					end
				end
			end
		end)
		-- 옆벽 진열장 (더마 · 헤어바디 · 건강식품 · 마스크팩)
		step(K, "sidewalls", function()
			local cats = { { "dermo", "더마 · 선케어 DERMA" }, { "hairbody", "헤어 · 바디 · 향수" }, { "health", "건강식품 · 이너뷰티" }, { "maskcare", "마스크팩 MASK" } }
			local placed = 0
			local hU = math.min(5.4, V.H - 2.4)
			for _, cc in cats do
				for _, len in { 7.2, 5.6, 4.4 } do
					local wn, pcf = wallFloorSpot(K, { "left", "right" }, len, 1.3, hU + 0.7, nil, 0, "wallunit")
					if wn and pcf then
						local us = wallUnit(K, pcf, len, 1.3, hU, { title = cc[2], body = lk(OY.white), back = lk(C(244, 244, 240)), headL = lk(OY.white), titleFg = OY.dark, lineL = lk(OY.main), levels = 5, kick = lk(C(60, 64, 60)) })
						for _, su in us do
							queueFill(K, su, cc[1], V.key .. cc[1] .. su.level, theme, { scale = 1.15 })
						end
						placed += 1
						break
					end
				end
			end
			note(K, "olive side units " .. placed)
		end)
		-- 벽 칸 브랜드 띠 (구역마다 실제 브랜드 이름)
		step(K, "brands", function()
			local BR = { "라운드랩", "토리든", "아누아", "닥터지", "메디힐", "라로슈포제", "에스트라", "롬앤", "클리오", "페리페라", "웨이크메이크", "어뮤즈", "마녀공장", "스킨1004", "구달", "닥터포헤어", "일리윤", "바이오더마" }
			local bi0 = 0
			for _, s in surfs do
				if s.len > 6 and s.level and s.levels and s.level == s.levels then
					local nb = math.max(1, math.floor(s.len / 3.7 + 0.5))
					local bw = s.len / nb
					for bi = 1, nb do
						bi0 += 1
						local cf = s.cf * CF(-s.len / 2 + bw * (bi - 0.5), math.min(s.clear - 0.22, 1.1), -s.depth + 0.12)
						K:free(function()
							txt(K, "StBrandStrip", bw - 0.5, 0.32, cf, BR[(hashStr(V.key) + bi0) % #BR + 1], WHITE, if bi0 % 3 == 0 then OY.main else OY.dark, { d = 0.03, font = Enum.Font.GothamBlack })
						end)
					end
				end
			end
		end)
		fixturesNow(K, V, S)
		step(K, "hang", function()
			local done = 0
			for _, x in { -0.3, 0.3, 0, -0.15, 0.15 } do
				if done >= 3 then
					break
				end
				if hangSignNear(K, V.W * x, (V.z0 + V.z1) / 2 - 1.5, 4.4, 1.1, math.max(6.4, V.H - 2.8), 0, if done == 1 then "오늘의 특가 오특" else "올영세일 최대 70%", "OLIVE YOUNG · 건강한 아름다움", if done == 1 then OY.sub else OY.main, WHITE, OY.white) then
					done += 1
				end
			end
		end)
		step(K, "posters", function()
			local P = {
				{ "올영세일", "10.24 - 10.30\n최대 70% 할인", OY.white, OY.dark, OY.main },
				{ "CJ ONE", "결제 시 포인트 적립\n앱 쿠폰 사용 가능", OY.white, OY.dark, OY.dark },
				{ "오늘드림", "주문 후 3시간 내 배송\n광안리점 픽업 가능", OY.white, OY.dark, OY.sub },
				{ "TAX FREE", "외국인 즉시 환급\nInstant Tax Refund", OY.white, OY.dark, C(30, 80, 160) },
			}
			for i, p in P do
				local wn, dcf = wallItemSpot(K, { "left", "right", "back" }, 2.0, 4.6, 7.0, (i - 2) * 4)
				if wn and dcf then
					poster(K, dcf, 1.8, 2.2, p[1], p[2], p[3], p[4], p[5], WHITE, {})
				end
			end
		end)
	elseif sub == "souvenir" or sub == "beach" then
		local beach = sub == "beach"
		local accent = if beach then C(30, 120, 200) else C(30, 60, 120)
		local warm = if beach then C(250, 160, 40) else C(200, 40, 40)
		step(K, "goodswall", function()
			goodsWall(K, V, sub, rng)
		end)
		-- 빵 선반 (I AM BUSAN 같은 부산 먹거리 기념품 가게): 맵 Bread 숨기고 선물세트 · 빵 · 호떡 믹스로
		step(K, "breadshelf", function()
			if V:has("BreadShelf") > 0 then
				for _, r in V.byName.Bread or {} do
					Scan.hide(K.hidden, r.part)
				end
				for _, su in surfs do
					if su.rec.name == "BreadShelf" then
						local nb = math.max(1, math.floor(su.len / 4 + 0.5))
						local bw = su.len / nb
						for bi = 1, nb do
							local sub2 = { cf = su.cf * CF(-su.len / 2 + bw * (bi - 0.5), 0, 0), len = bw - 0.2, depth = su.depth, clear = su.clear, rail = false, level = su.level, levels = su.levels }
							queueFill(K, sub2, if bi % 3 == 0 then "gift" else "busan", V.key .. "bs" .. bi .. (su.level or 0), {}, { obst = obst })
						end
					end
				end
			end
		end)
		step(K, "rail", function()
			railShirts(K, V, if beach then { C(30, 60, 140), C(240, 80, 120), C(30, 30, 34), C(60, 180, 170), C(250, 160, 40) } else { C(250, 250, 250), C(30, 60, 140), C(240, 200, 60), C(240, 240, 236), C(200, 40, 50), C(120, 180, 220) }, rng)
			-- 봉 리스킨 (크롬)
			for _, nm in { "Rail", "RailPost" } do
				for _, r in V.byName[nm] or {} do
					K:free(function()
						if r.size.Y > r.size.X and r.size.Y > r.size.Z then
							K:vcyl("StRailPost", r.size.Y, math.max(r.size.X, r.size.Z) * 0.9, CF(r.c), Look.chrome)
							K:disc("StRailFoot", 0.9, 0.06, CF(r.c.X, 0.03, r.c.Z), Look.chrome)
						else
							K:cyl("StRailBar", math.max(r.size.X, r.size.Z), math.min(r.size.Y, 0.16), CF(r.c) * (if r.size.X >= r.size.Z then CFrame.new() else ANG(0, PI / 2, 0)), Look.chrome)
						end
					end)
					Scan.hide(K.hidden, r.part)
				end
			end
		end)
		step(K, "table", function()
			displayTable(K, V, sub, rng)
		end)
		step(K, "cashier", function()
			for _, g in V.counters do
				cashierDress(K, V, g, { main = accent }, "retail")
			end
		end)
		if beach then
			-- 대여 요금판 · 파라솔 통 · 선풍기
			step(K, "fan", function()
				local wn, pcf = wallFloorSpot(K, { "back", "left", "right" }, 1.4, 1.4, 4.6, V3((V.x0 + V.x1) / 2, 0, V.z0), 0.1, "fan", function(c: CFrame): boolean
					return promptOk(K, c.Position)
				end)
				if wn and pcf then
					local fcf = pcf * ANG(0, 0, 0)
					K:disc("StFanBase", 1.2, 0.12, fcf * CF(0, 0.06, 0), lk(C(240, 240, 240), M.Plastic))
					K:vcyl("StFanPole", 3.0, 0.14, fcf * CF(0, 1.6, 0), lk(C(240, 240, 240), M.Plastic))
					local head = fcf * CF(0, 3.5, 0.1)
					K:ell("StFanMotor", V3(0.5, 0.5, 0.6), head * CF(0, 0, -0.25), lk(C(240, 240, 240), M.Plastic))
					K:ring("StFanGuard", head * CF(0, 0, 0.12), 0.85, 0.05, 12, lk(C(220, 220, 224), M.Metal))
					local blades = {}
					for i = 0, 2 do
						local a = i * 2 * PI / 3
						table.insert(blades, K:ell("StFanBlade", V3(0.36, 0.7, 0.04), head * CF(0, 0, 0.1) * ANG(0, 0, a) * CF(0, 0.38, 0), { c = C(120, 190, 240), m = M.Plastic, t = 0.2 }))
					end
					local blur = K:disc("StFanBlur", 1.6, 0.02, head * CF(0, 0, 0.1) * ANG(PI / 2, 0, 0), { c = C(140, 200, 240), m = M.Glass, t = 1 })
					local hub = K:ball("StFanHub", 0.22, head * CF(0, 0, 0.14), lk(C(240, 240, 240), M.Plastic))
					local on = false
					local fp = firstOk(K, { hub, blur })
					if fp then Interact.toggle(K, fp, {
						object = "선풍기",
						state = false,
						onText = "끄기",
						offText = "켜기",
						on = function(st: boolean)
							on = st
							for _, b in blades do
								if b.Parent then
									b.Transparency = if st then 1 else 0.2
								end
							end
							if blur.Parent then
								blur.Transparency = if st then 0.55 else 1
							end
						end,
					}) end
					local _ = on
				end
			end)
			step(K, "rental", function()
				local wn, dcf = wallItemSpot(K, { "left", "right" }, 3.4, 3.6, 7.6, 0)
				if wn and dcf then
					local d0 = dcf * CF(0, 0, 0.06)
					K:plate("StRentFrame", 3.4, 4.0, 0.06, d0, Look.walnut)
					K:plate("StRentBoard", 3.2, 3.8, 0.07, d0, lk(C(250, 250, 246)))
					K:plate("StRentBand", 3.2, 0.7, 0.08, d0 * CF(0, 1.55, 0), lk(accent))
					txt(K, "StRentTitle", 3.0, 0.56, d0 * CF(0, 1.55, 0.081), "대여 요금 RENTAL", WHITE, nil, { font = Enum.Font.GothamBlack })
					local rows = { { "튜브 (1일)", "10,000" }, { "파라솔 (1일)", "15,000" }, { "비치베드", "20,000" }, { "구명조끼", "5,000" }, { "돗자리", "5,000" }, { "보증금 · 신분증 필수", "10,000" } }
					for i, r in rows do
						local y = 1.0 - i * 0.48
						txt(K, "StRentItem", 1.9, 0.36, d0 * CF(-0.55, y, 0.072), r[1], INK, nil, { align = "Left", font = Enum.Font.GothamBold })
						txt(K, "StRentPrice", 1.0, 0.36, d0 * CF(1.0, y, 0.072), r[2], warm, nil, { align = "Right", font = Enum.Font.GothamBlack })
						K:plate("StRentRule", 2.9, 0.02, 0.071, d0 * CF(0, y - 0.24, 0), lk(C(214, 214, 210)))
					end
				end
			end)
			-- 천장에 매단 튜브 (해변 가게 상징): 옷걸이 봉 · 진열 테이블 위
			step(K, "ceilTubes", function()
				local cols = { C(250, 120, 40), C(40, 160, 230), C(250, 210, 60), C(240, 80, 140), C(60, 200, 150), C(250, 250, 250) }
				local lines = {}
				local rl = V:first("Rail")
				if rl then
					table.insert(lines, { rl.min.X + 0.6, rl.max.X - 0.6, rl.c.Z })
				end
				local dt = V:first("DisplayTable")
				if dt then
					table.insert(lines, { dt.min.X + 0.6, dt.max.X - 0.6, dt.c.Z })
				end
				local n = 0
				for _, ln in lines do
					local cnt = math.max(1, math.floor((ln[2] - ln[1]) / 1.6))
					for i = 0, cnt do
						local x = ln[1] + (ln[2] - ln[1]) * i / math.max(1, cnt)
						local y = V.H - 2.0 - (i % 2) * 0.35
						local ring = CF(x, y, ln[3]) * ANG(0, (i % 3) * 0.5, 0)
						local mn, mx = K.laabb(ring, V3(1.5, 1.5, 1.5))
						if not K:hitsKeep(mn, V3(mx.X, V.H, mx.Z)) and not mapBlocked(K, mn, mx) then
							K:ring("StCeilTube", ring, 0.55, 0.32, if K.detail == "high" then 10 else 7, lk(cols[(n % #cols) + 1], M.Plastic))
							K:seg("StCeilTubeString", V3(x, y + 0.72, ln[3]), V3(x, V.H - 0.02, ln[3]), 0.025, lk(C(240, 240, 240)))
							n += 1
						end
					end
				end
			end)
			step(K, "mats", function()
				local wn, pcf = wallFloorSpot(K, { "left", "right", "back" }, 1.5, 1.2, 4.4, nil, 0.1, "mats")
				if wn and pcf then
					K:box("StMatBin", V3(1.4, 1.4, 1.1), pcf * CF(0, 0.7, 0), lk(C(196, 156, 100), M.Fabric))
					K:box("StMatBinRim", V3(1.46, 0.1, 1.16), pcf * CF(0, 1.42, 0), lk(C(150, 110, 70), M.Fabric))
					local cols = { C(40, 120, 200), C(250, 120, 40), C(60, 180, 160), C(240, 80, 120), C(250, 210, 60), C(120, 80, 200) }
					for i = 0, 5 do
						local x = -0.42 + (i % 3) * 0.42
						local z = -0.2 + math.floor(i / 3) * 0.4
						local h = 3.2 + (i % 2) * 0.3
						K:vcyl("StMatRoll", h, 0.36, pcf * CF(x, 0.3 + h / 2, z) * ANG(0.04 * (i - 2), 0, 0.03 * (i - 3)), lk(cols[i + 1], M.Fabric))
						K:vcyl("StMatStrap", 0.08, 0.38, pcf * CF(x, 0.3 + h * 0.7, z), lk(C(30, 30, 30), M.Fabric))
					end
					txt(K, "StMatTag", 1.2, 0.4, pcf * CF(0, 0.9, 0.555), "돗자리 5,000 · 2개 9,000", WHITE, C(40, 120, 200), { d = 0.01 })
				end
			end)
			step(K, "parasols", function()
				local wn, pcf = wallFloorSpot(K, { "left", "right", "back" }, 1.6, 1.6, 6.0, nil, 0.1, "parasol")
				if wn and pcf then
					K:vcyl("StParasolBin", 1.6, 1.3, pcf * CF(0, 0.8, 0), lk(C(40, 120, 200), M.Plastic))
					K:vcyl("StParasolBinRim", 0.1, 1.36, pcf * CF(0, 1.62, 0), lk(C(250, 250, 250), M.Plastic))
					local cols = { C(250, 120, 40), C(40, 160, 230), C(250, 210, 60), C(240, 80, 140), C(250, 250, 250) }
					for i = 0, 4 do
						local a = i * 2 * PI / 5
						local base = pcf * CF(math.cos(a) * 0.3, 0.3, math.sin(a) * 0.3)
						local top = base * CF(math.cos(a) * 0.25, 5.2, math.sin(a) * 0.25)
						K:seg("StParasolPole", base.Position, top.Position, 0.06, lk(C(250, 250, 250)))
						-- 접힌 천 (길쭉한 타원체)
						local mid = (base.Position + top.Position) / 2 + V3(0, 1.0, 0)
						K:ell("StParasolCloth", V3(0.34, 3.0, 0.34), CF(mid) * ANG(math.sin(a) * 0.05, 0, -math.cos(a) * 0.05), lk(cols[i + 1], M.Fabric))
					end
					txt(K, "StParasolTag", 1.0, 0.4, pcf * CF(0, 1.0, 0.66), "파라솔 대여", WHITE, nil, { d = 0.01 })
				end
			end)
		else
			step(K, "spinner", function()
				local cands = {}
				for gx = V.x0 + 1.6, V.x1 - 1.6, 0.5 do
					for gz = V.z0 + 2, V.z1 - 2.5, 0.5 do
						table.insert(cands, V3(gx, 0, gz))
					end
				end
				table.sort(cands, function(a, b)
					return math.abs(a.X) > math.abs(b.X)
				end)
				local pcf = floorSpot(K, cands, V3(1.6, 5.8, 1.6), V3(0, 0, 1), 0.4, "spinner", function(p: Vector3): boolean
					return promptOk(K, V3(p.X, 3, p.Z + 0.6))
				end)
				if pcf then
					spinRack(K, pcf, "postcard", "엽서 회전 진열대")
				end
			end)
			step(K, "bridge", function()
				local wn, dcf = wallItemSpot(K, { "left", "right", "back" }, 5.6, 5.0, 7.6, 0, function(d: CFrame): boolean
					return promptOk(K, (d * CF(-2.0, 0, 0)).Position) or promptOk(K, (d * CF(2.0, 0, 0)).Position) or promptOk(K, d.Position)
				end)
				if wn and dcf then
					bridgeModel(K, dcf * CF(0, 0, 0.04), 5.2)
				end
			end)
		end
		fixturesNow(K, V, S)
		step(K, "hang", function()
			local t1 = if beach then "BEACH SHOP · 튜브 대여" else "BUSAN SOUVENIR · 부산 기념품"
			local t2 = if beach then "선크림 · 돗자리 · 비치타월" else "I ♥ BUSAN · 광안리"
			hangSignNear(K, (V.x0 + V.x1) / 2 - V.W * 0.2, (V.z0 + V.z1) / 2, 4.6, 1.1, math.max(6.2, V.H - 2.8), 0, t1, t2, accent, WHITE, warm)
		end)
		step(K, "posters", function()
			local P = if beach
				then { { "주의 안내", "수영 가능 시간 09:00 - 18:00\n음주 수영 금지 · 안전요원 지시", C(250, 250, 246), INK, warm }, { "TAX FREE", "카드 · 간편결제 OK", C(250, 250, 246), INK, accent }, { "광안리 해수욕장", "개장 7.1 - 8.31\n튜브는 안전구역 안에서", C(250, 250, 246), INK, C(60, 170, 150) } }
				else { { "부산 여행 기념", "광안대교 · 해운대 · 감천마을\n엽서 1,500 · 마그넷 5,000", C(250, 250, 246), INK, accent }, { "TAX FREE", "외국인 즉시 환급\n카드 · 간편결제 OK", C(250, 250, 246), INK, warm }, { "포장 서비스", "선물 포장 무료\n쇼핑백 100원", C(250, 250, 246), INK, C(60, 140, 90) } }
			for i, p in P do
				local wn, dcf = wallItemSpot(K, { "left", "right" }, 2.0, 4.2, 6.6, (i - 2) * 3)
				if wn and dcf then
					poster(K, dcf, 1.8, 2.2, p[1], p[2], p[3], p[4], p[5], WHITE, {})
				end
			end
		end)
	else
		-- 꽃집 · 서점 · 일반 소매: 맵 선반만 채우고 벽 진열 + 포스터
		local cat = if sub == "book" then "books" elseif sub == "flower" then "gift" else "gift"
		step(K, "shelves", function()
			K:free(function()
				for _, s in surfs do
					queueFill(K, s, cat, V.key .. s.face .. (s.level or 0), {}, { obst = obst })
				end
			end)
		end)
		step(K, "wallunits", function()
			for i = 1, 2 do
				local wn, pcf = wallFloorSpot(K, { "left", "right", "back" }, 5.0, 1.3, math.min(6.2, V.H - 1.6), nil, 0, "wallunit")
				if wn and pcf then
					local us = wallUnit(K, pcf, 5.0, 1.3, math.min(5.6, V.H - 2.2), { title = if sub == "book" then "베스트셀러 · 신간" else "추천 상품", body = Look.oak, back = Look.lightOak, shelf = Look.oak, headL = lk(C(40, 40, 44)), titleFg = WHITE, levels = 5 })
					K:free(function()
						for _, s in us do
							queueFill(K, s, cat, V.key .. "wu" .. i .. s.level, {}, {})
						end
					end)
				end
			end
		end)
		step(K, "cashier", function()
			for _, g in V.counters do
				cashierDress(K, V, g, { main = C(40, 40, 44) }, "retail")
			end
		end)
	end
	step(K, "goods", function()
		used += runFill(K, goodsBudget(K, V, if sub == "cosmetics" then 1.1 else 1))
	end)
	note(K, string.format("retail %s goods parts=%d surfaces=%d", sub, used, #surfs))
end

---------------------------------------------------------------------------------------------------
-- 8. 약국
---------------------------------------------------------------------------------------------------

-- 자동 혈압계 코너 (본체 + 팔걸이 커프 + 화면 + 스툴) : 측정 상호작용
local function bpCorner(K: any, pcf: CFrame)
	K:box("StBPBase", V3(1.4, 0.3, 1.5), pcf * CF(0, 0.15, 0), lk(C(240, 240, 240)))
	K:rbox("StBPBody", V3(1.3, 3.0, 1.1), 0.1, pcf * CF(0, 1.8, -0.15), lk(C(246, 246, 244)))
	K:box("StBPArm", V3(0.8, 0.5, 1.1), pcf * CF(0, 3.05, 0.25), lk(C(70, 120, 180)))
	K:cyl("StBPCuff", 0.9, 0.5, pcf * CF(0, 3.25, 0.3) * ANG(0, PI / 2, 0), lk(C(40, 60, 100), M.Fabric))
	K:plate("StBPBezel", 0.9, 0.6, 0.02, pcf * CF(0, 3.9, 0.4) * ANG(-0.25, 0, 0), Look.black)
	local scr, label = txt(K, "StBPReading", 0.8, 0.5, pcf * CF(0, 3.9, 0.42) * ANG(-0.25, 0, 0), "혈압 측정\n팔을 넣고 시작", C(120, 240, 170), C(16, 30, 36), { glow = 1.3, d = 0.02, font = Enum.Font.GothamBold })
	K:plate("StBPButton", 0.2, 0.2, 0.03, pcf * CF(0.45, 3.4, 0.41), Look.ledGreen)
	txt(K, "StBPLabel", 1.0, 0.36, pcf * CF(0, 2.2, 0.41), "자동 혈압계\n무료 측정", PH.dark, PH.white, { d = 0.01 })
	-- 스툴 (Seat 아님)
	K:vcyl("StBPStoolLeg", 1.7, 0.14, pcf * CF(0, 0.85, 1.6), Look.chrome)
	K:disc("StBPStoolFoot", 0.9, 0.06, pcf * CF(0, 0.03, 1.6), Look.chrome)
	K:disc("StBPStoolSeat", 1.0, 0.18, pcf * CF(0, 1.78, 1.6), lk(C(40, 60, 100), M.Leather))
	local busy = false
	promptOn(K, { scr }, {
		action = "혈압 재기",
		object = "자동 혈압계",
		fn = function()
			if busy then
				return
			end
			busy = true
			label.Text = "측정 중...\n움직이지 마세요"
			task.delay(2.6, function()
				local sys = 108 + math.random(0, 22)
				local dia = 68 + math.random(0, 14)
				local pulse = 64 + math.random(0, 20)
				if label.Parent then
					label.Text = string.format("%d / %d mmHg\n맥박 %d · %s", sys, dia, pulse, if sys < 120 then "정상" else "주의")
				end
				busy = false
			end)
		end,
	})
end

-- 약사 가운 걸이 (벽)
local function coatHook(K: any, dcf: CFrame)
	K:plate("StCoatRail", 1.2, 0.12, 0.06, dcf * CF(0, 0.6, 0), Look.walnut)
	K:seg("StCoatPeg", (dcf * CF(0, 0.6, 0.05)).Position, (dcf * CF(0, 0.66, 0.3)).Position, 0.06, Look.chrome)
	local d = dcf * CF(0, 0.45, 0.14)
	K:box("StCoatHanger", V3(1.4, 0.05, 0.05), d, lk(C(214, 186, 148), M.Wood))
	K:box("StCoatBody", V3(1.5, 2.8, 0.12), d * CF(0, -1.45, 0), lk(C(250, 250, 250), M.Fabric))
	for _, sx in { -1, 1 } do
		K:box("StCoatSleeve", V3(0.36, 2.2, 0.12), d * CF(sx * 0.82, -1.2, 0.02) * ANG(0, 0, sx * 0.08), lk(C(244, 244, 242), M.Fabric))
		K:box("StCoatLapel", V3(0.26, 1.0, 0.02), d * CF(sx * 0.2, -0.55, 0.07) * ANG(0, 0, -sx * 0.25), lk(C(236, 236, 234), M.Fabric))
	end
	K:plate("StCoatPocket", 0.36, 0.3, 0.01, d * CF(-0.38, -0.9, 0.06), lk(C(236, 236, 234), M.Fabric))
	K:plate("StCoatBadge", 0.36, 0.12, 0.01, d * CF(0.4, -0.85, 0.065), lk(PH.main))
	K:box("StCoatPen", V3(0.04, 0.3, 0.04), d * CF(-0.3, -0.8, 0.09), lk(C(30, 60, 140)))
end

local function buildPharmacy(K: any, V: any, S: any, sub: string)
	local gw = sub == "gw"
	local surfs = mapSurfaces(V)
	local obst = obstacles(V)
	local theme = { promo1 = PH.main, promo2 = C(250, 196, 0), p11 = 0.04, p21 = 0.0, pSale = 0.06, saleText = "추천", promo3 = PH.main, maxTagText = 26, prices = { "3,000", "3,500", "4,500", "5,000", "6,500", "8,000", "12,000", "22,000" } }
	local used = 0
	-- GwShop 점원 인형 (Humanoid 없는 것) 주변 2.5 비움
	if not V._stNpcKeep then
		V._stNpcKeep = true
		for _, hr in V.byName.HumanoidRootPart or {} do
			local par = hr.part.Parent
			local mn, mx = hr.min, hr.max
			for _, r in V.parts do
				if r.part.Parent == par then
					mn = mn:Min(r.min)
					mx = mx:Max(r.max)
				end
			end
			V:addKeep(mn - V3(2.5, 0, 2.5), mx + V3(2.5, 0.5, 2.5), "npc")
		end
	end
	for _, g in V.counters do
		reserveFront(K, g.min, g.max, counterFace(V, g), 2.6, 0.4)
	end
	for _, s in surfs do
		local r = s.rec
		local fwd = s.cf.ZVector
		reserveFront(K, r.min, r.max, V3(math.round(fwd.X), 0, math.round(fwd.Z)), 2.4, 0.2)
	end
	-- 진열: 거리 약국은 Product 숨기고 다시, GwShop 은 Product 상자 범위 안에서만 다시
	local rxBoard = {}
	for _, s in surfs do
		local par = s.rec.part and s.rec.part.Parent
		if par and (par.Name == "처방약장" or string.find(par.Name, "처방", 1, true)) then
			rxBoard[s] = true
		end
	end
	step(K, "shelves", function()
		if gw then
			-- 각 Product 의 선반 앞쪽 방향 = 가장 가까운 칸의 앞
			local hidden = 0
			K:free(function()
				for i, r in V.byName.Product or {} do
					local best, bd = nil, math.huge
					for _, s in surfs do
						if overlapXZ(s.rec, r, 0.05) and r.min.Y >= s.rec.max.Y - 0.2 then
							local dy = r.min.Y - s.rec.max.Y
							if dy < bd then
								best, bd = s, dy
							end
						end
					end
					local front = if best then best.cf.ZVector else awayFromWall(V, r)
					front = V3(math.round(front.X), 0, math.round(front.Z))
					local cats = { "otc", "otc", "supplement", "otc" }
					used += fillInside(K, r, front, cats[(math.floor(r.c.Z / 5) % #cats) + 1], mkRng(V.key .. "p" .. i), if K.detail == "low" then 1 else 2)
					Scan.hide(K.hidden, r.part)
					hidden += 1
				end
				for i, r in V.byName.Bottle or {} do
					local front = V3(0, 0, 1)
					for _, fd in V.byName.FridgeDoor or {} do
						if (fd.c - r.c).Magnitude < 5 then
							front = if fd.size.X < fd.size.Z then V3(math.sign(fd.c.X - r.c.X), 0, 0) else V3(0, 0, math.sign(fd.c.Z - r.c.Z))
						end
					end
					local sku = if i % 3 == 0 then SKU.drinkA else SKU.pet
					local base = pcfAt(V3(r.c.X, r.min.Y, r.c.Z), front)
					used += item(K, base, sku, if i % 3 == 0 then C(120, 60, 20) else pick(mkRng(i), { C(250, 200, 40), C(40, 120, 200), C(240, 120, 30) }), nil, math.min(r.size.Y, sku.h), if K.detail == "low" then 1 else 2)
					Scan.hide(K.hidden, r.part)
				end
			end)
			note(K, "gw products restyled " .. hidden)
			-- 원래 상품이 없는 선반 빈 구간만 채움 (선반 안쪽 · 앞 모서리 안)
			local gaps = 0
			for _, su in surfs do
				if not su.fridge and su.rec.part then
					local occ = {}
					for _, r in V.byName.Product or {} do
						if overlapXZ(su.rec, r, 0.02) and r.min.Y >= su.rec.max.Y - 0.25 and r.min.Y < su.rec.max.Y + 0.4 then
							local a = su.cf:PointToObjectSpace(r.min).X
							local b = su.cf:PointToObjectSpace(r.max).X
							table.insert(occ, { math.min(a, b) - 0.05, math.max(a, b) + 0.05 })
						end
					end
					table.sort(occ, function(x, y)
						return x[1] < y[1]
					end)
					local cur = -su.len / 2 + 0.1
					local ivs = {}
					for _, o in occ do
						if o[1] - cur > 0.7 then
							table.insert(ivs, { cur, o[1] })
						end
						cur = math.max(cur, o[2])
					end
					if su.len / 2 - 0.1 - cur > 0.7 then
						table.insert(ivs, { cur, su.len / 2 - 0.1 })
					end
					for gi, iv in ivs do
						local sub2 = { cf = su.cf * CF((iv[1] + iv[2]) / 2, 0, 0), len = iv[2] - iv[1] - 0.05, depth = su.depth, clear = su.clear, rail = false, level = su.level, levels = su.levels }
						queueFill(K, sub2, if (gi + (su.level or 0)) % 3 == 0 then "supplement" else "otc", V.key .. "gg" .. su.face .. gi .. (su.level or 0), theme, { facing = 1, noTags = true, obst = obst })
						gaps += 1
					end
				end
			end
			note(K, "gw shelf gaps filled " .. gaps)
		else
			for _, nm in { "Product", "Bottle" } do
				for _, r in V.byName[nm] or {} do
					Scan.hide(K.hidden, r.part)
				end
			end
			-- 벽 약장: 긴 판을 세로 블록으로 (감기 · 소화 · 진통 · 파스 · 비타민)
			K:free(function()
				for _, s in surfs do
					if rxBoard[s] then
						queueFill(K, s, "rx", V.key .. "rx" .. (s.level or 0), theme, { noTags = true, obst = obst })
					elseif s.len > 6 then
						local nb = math.max(1, math.floor(s.len / 3.2 + 0.5))
						local bw = s.len / nb
						for bi = 1, nb do
							local cat = if bi == nb then "supplement" else "otc"
							local sub2 = { cf = s.cf * CF(-s.len / 2 + bw * (bi - 0.5), 0, 0), len = bw - 0.16, depth = s.depth, clear = s.clear, rail = s.rail, level = s.level, levels = s.levels }
							queueFill(K, sub2, cat, V.key .. s.face .. bi .. (s.level or 0), theme, { obst = obst, facing = 1 })
						end
					else
						local cat = if s.cf.ZVector.X > 0 then "supplement" else "otc"
						queueFill(K, s, cat, V.key .. s.face .. (s.level or 0), theme, { obst = obst, facing = 1 })
					end
				end
			end)
		end
	end)
	-- 머리 띠 · 끝판
	step(K, "headers", function()
		for i, hd in V.byName.Header or {} do
			if not gw then
				local face = if hd.size.X >= hd.size.Z then V3(0, 0, if hd.c.Z < 0 then 1 else -1) else V3(if hd.c.X < 0 then 1 else -1, 0, 0)
				local fpos = if math.abs(face.Z) > 0.5 then (if face.Z > 0 then hd.max.Z else hd.min.Z) else (if face.X > 0 then hd.max.X else hd.min.X)
				local p = if math.abs(face.Z) > 0.5 then V3(hd.c.X, hd.c.Y, fpos) else V3(fpos, hd.c.Y, hd.c.Z)
				local w = math.max(hd.size.X, hd.size.Z)
				K:free(function()
					txt(K, "StHeaderText", w * 0.9, hd.size.Y * 0.72, dcfAt(p, face), "감기 · 해열     소화 · 위장     진통 · 파스     눈 · 피부     비타민 · 영양제", WHITE, nil, { font = Enum.Font.GothamBold, d = 0.01 })
				end)
			end
		end
		local promos = { { "건강기능식품", "비타민 · 유산균 · 오메가3" }, { "약사 추천", "피로회복 · 간 건강" } }
		for i, ep in V.byName.EndPanel or {} do
			local thinX = ep.size.X < ep.size.Z
			local cen = nil
			for _, s in surfs do
				if overlapXZ(s.rec, ep, 0.6) then
					cen = s.rec.c
				end
			end
			local face = if thinX then V3(if cen and cen.X > ep.c.X then -1 else 1, 0, 0) else V3(0, 0, if cen and cen.Z > ep.c.Z then -1 else 1)
			local fpos = if thinX then (if face.X > 0 then ep.max.X else ep.min.X) else (if face.Z > 0 then ep.max.Z else ep.min.Z)
			local w = if thinX then ep.size.Z else ep.size.X
			local p = if thinX then V3(fpos, ep.size.Y * 0.5, ep.c.Z) else V3(ep.c.X, ep.size.Y * 0.5, fpos)
			local pr = promos[(i - 1) % #promos + 1]
			K:free(function()
				poster(K, dcfAt(p, face) * CF(0, 0, -0.05), w - 0.4, ep.size.Y - 1.2, pr[1], pr[2], PH.white, PH.dark, PH.main, WHITE, { titleH = 0.36, frame = false })
			end)
			for _, eh in V.byName.EndHeader or {} do
				if overlapXZ(eh, ep, 0.05) then
					local hp = if thinX then V3((if face.X > 0 then eh.max.X else eh.min.X), eh.c.Y, eh.c.Z) else V3(eh.c.X, eh.c.Y, (if face.Z > 0 then eh.max.Z else eh.min.Z))
					K:free(function()
						txt(K, "StEndHeaderText", w - 0.2, eh.size.Y * 0.7, dcfAt(hp, face), if i % 2 == 0 then "생활건강 · 위생" else "건강기능식품", WHITE, nil, { d = 0.015, font = Enum.Font.GothamBlack })
					end)
				end
			end
		end
	end)
	step(K, "cashier", function()
		for _, g in V.counters do
			cashierDress(K, V, g, PH, "pharmacy")
		end
	end)
	step(K, "did", function()
		local wn, dcf = wallItemSpot(K, { "right", "left", "back" }, 3.2, math.min(4.6, V.H - 3.3), math.min(6.6, V.H - 1.3), -3, function(d: CFrame): boolean
			return promptOk(K, d.Position)
		end)
		if wn and dcf then
			didScreen(K, dcf, 2.8, {
				{ text = "건강 정보\n물은 하루 8잔", c = PH.main },
				{ text = "감기약 복용 중\n음주는 피하세요", c = PH.sub },
				{ text = "약 보관은\n서늘하고 건조하게", c = C(60, 120, 90) },
				{ text = "유통기한 지난 약은\n약국 수거함에", c = PH.dark },
			}, "건강 정보 화면")
		end
	end)
	if not gw then
		step(K, "bp", function()
			local door = V.door
			local prefer = if door then V3(door.x, 0, door.z - 6) else nil
			local wn, pcf = wallFloorSpot(K, { "left", "right", "back" }, 1.6, 3.4, 4.4, prefer, 0.1, "bp", function(c: CFrame): boolean
				return promptOk(K, (c * CF(0, 0, -0.4)).Position)
			end)
			if wn and pcf then
				-- 벽에서 0.2 띄우고 화면은 방 쪽
				bpCorner(K, pcf * CF(0, 0, -0.8))
				local wn2, dcf2 = wallItemSpot(K, { wn }, 1.8, 4.6, 5.8, (V:wallCoord(wn, pcf.Position)))
				if wn2 and dcf2 then
					txt(K, "StBPWallSign", 1.7, 0.7, dcf2 * CF(0, 0, 0.04), "자동 혈압계\n누구나 무료", WHITE, PH.main, { d = 0.03, font = Enum.Font.GothamBlack })
				end
			end
		end)
		step(K, "wallunits", function()
			local hU = math.min(5.4, V.H - 2.0)
			local cats = { { "supplement", "건강기능식품 · 비타민" }, { "dermo", "더마 화장품 · 피부 연고" }, { "otc", "마스크 · 밴드 · 파스" } }
			local placed = 0
			for _, cc in cats do
				if placed >= 2 then
					break
				end
				for _, len in { 6.4, 4.8, 3.6 } do
					local wn, pcf = wallFloorSpot(K, { "right", "left" }, len, 1.3, hU + 0.7, nil, 0, "wallunit")
					if wn and pcf then
						local us = wallUnit(K, pcf, len, 1.3, hU, { title = cc[2], headL = lk(PH.main), titleFg = WHITE, lineL = lk(PH.dark), levels = 5, glow = 1.1 })
						K:free(function()
							for _, s in us do
								queueFill(K, s, cc[1], V.key .. cc[1] .. s.level, theme, {})
							end
						end)
						placed += 1
						break
					end
				end
			end
		end)
		step(K, "cross", function()
			local wn, dcf = wallItemSpot(K, { "back", "left", "right" }, 1.8, math.max(5.6, V.H - 2.3), V.H - 0.3, 0)
			if wn and dcf then
				local d = dcf * CF(0, 0, 0.04)
				K:plate("StCrossBack", 1.7, 1.7, 0.05, d, lk(C(250, 252, 250)))
				K:plate("StCrossH", 1.3, 0.42, 0.08, d, Look.neon(C(30, 200, 90)))
				K:plate("StCrossV", 0.42, 1.3, 0.08, d, Look.neon(C(30, 200, 90)))
			end
		end)
		step(K, "coat", function()
			local cnt = V.counters[1]
			local prefer = if cnt then V:wallCoord("right", (cnt.min + cnt.max) / 2) else 0
			local wn, dcf = wallItemSpot(K, { "right", "left" }, 1.6, 2.4, 6.2, prefer - 4)
			if wn and dcf then
				coatHook(K, dcf * CF(0, 0, 0.02))
			end
		end)
	end
	step(K, "hang", function()
		local n = 0
		for _, s in surfs do
			if n < (if gw then 2 else 1) and not rxBoard[s] and s.len < 7 then
				local r = s.rec
				if hangSignNear(K, r.c.X, r.c.Z, 3.4, 0.9, math.max(5.5, V.H - 2.2), 0, "일반의약품 · 건강기능식품", "약은 약사와 상담하세요", PH.main, WHITE, PH.dark) then
					n += 1
				end
			end
		end
	end)
	fixturesNow(K, V, S)
	step(K, "posters", function()
		local P = {
			{ "영업시간", "평일 09:00 - 21:00\n토 09:00 - 18:00 · 일 휴무", PH.white, INK, PH.main },
			{ "의약품 부작용 피해구제", "한국의약품안전관리원\n1644-6223", PH.white, INK, PH.sub },
			{ "약은 약사에게", "복약 지도 · 상비약 상담\n처방전 접수", PH.white, INK, PH.dark },
			{ "금연 상담", "니코틴 패치 · 껌 상담\n보건소 금연클리닉 연계", PH.white, INK, C(200, 90, 40) },
			{ "휴일지킴이약국", "일 · 공휴일 운영 약국 안내\n129 · 응급의료포털", PH.white, INK, PH.main },
		}
		local nP = if gw then 2 else #P
		for i = 1, nP do
			local p = P[if gw then i + 1 else i]
			local wn, dcf = wallItemSpot(K, { "left", "right", "back" }, 1.9, math.min(4.2, V.H - 3.6), math.min(6.4, V.H - 1.4), (i - 3) * 3)
			if wn and dcf then
				poster(K, dcf, 1.7, math.min(2.0, V.H - 5.8), p[1], p[2], p[3], p[4], p[5], WHITE, {})
			end
		end
	end)
	step(K, "goods", function()
		used += runFill(K, goodsBudget(K, V))
	end)
	note(K, string.format("pharmacy %s goods parts=%d surfaces=%d", sub, used, #surfs))
end

---------------------------------------------------------------------------------------------------
-- 9. 스타일 · 빌드 입구
---------------------------------------------------------------------------------------------------

function T.style(V: any): any
	local kind, sub = subtype(V)
	local S: any = {
		chair = { style = "padded", frame = Look.blackMetal, seat = Look.fabricGrey },
		stool = { style = "cushion" },
		table = { top = Look.white, base = Look.blackMetal },
		lights = { kind = "none" },
		ceiling = {},
		skip = { fixtures = true },
		clock = true,
		license = true,
	}
	if kind == "cvs" then
		local B = BRANDS[sub] or BRANDS.indie
		S.counter = { front = "panel", frontL = lk(B.main), topL = lk(C(232, 232, 228)), kickL = Look.charcoal, led = Color3.fromRGB(236, 244, 255) }
		S.floor = { look = lk(C(226, 226, 222), M.CeramicTiles), tile = 2.0, grout = lk(C(186, 186, 182)) }
		S.base = lk(C(90, 92, 96))
		S.mat = { look = lk(C(48, 50, 54), M.Fabric), text = B.name }
		S.lower = false
		S.plants = { "snake" }
	elseif kind == "pharmacy" then
		S.counter = if sub == "gw" then false else { front = "panel", frontL = lk(C(248, 250, 248)), topL = lk(C(240, 242, 240)), kickL = lk(C(10, 110, 50)), led = Color3.fromRGB(240, 255, 245) }
		S.floor = if sub == "gw" then false else { look = lk(C(236, 238, 236), M.CeramicTiles), tile = 2.0, grout = lk(C(200, 204, 200)) }
		S.base = lk(C(10, 110, 50))
		S.mat = { look = lk(C(40, 60, 48), M.Fabric), text = "WELCOME" }
		S.lights = if sub == "gw" then { kind = "none" } else { kind = "downlight", n = 4, color = Look.coolLight, glow = Look.lampCool }
		S.lower = false
		S.plants = { "snake", "olive" }
	else
		if sub == "cosmetics" then
			S.counter = { front = "panel", frontL = lk(C(250, 250, 248)), topL = lk(C(244, 244, 240), M.Marble), kickL = lk(OY.main), led = Color3.fromRGB(240, 255, 220) }
			S.floor = { look = lk(C(242, 242, 238), M.Marble, { r = 0.04 }), tile = 3.0, grout = lk(C(214, 214, 210)) }
			S.base = lk(C(250, 250, 248))
			S.mat = { look = lk(C(40, 44, 40), M.Fabric), text = "OLIVE YOUNG" }
			S.lower = false
		elseif sub == "beach" then
			S.counter = { front = "wood", frontL = lk(C(196, 160, 118), M.WoodPlanks), topL = lk(C(240, 236, 226)), kickL = Look.charcoal, led = Color3.fromRGB(255, 220, 170) }
			S.floor = { look = lk(C(206, 176, 136), M.WoodPlanks), tile = 0 }
			S.base = lk(C(30, 120, 200))
			S.lower = { kind = "paint", h = 3.2, look = lk(C(200, 230, 246)), cap = lk(C(250, 250, 250)), walls = { "left", "right" } }
			S.mat = { look = lk(C(40, 90, 140), M.Fabric), text = "BEACH" }
		elseif sub == "souvenir" then
			S.counter = { front = "wood", frontL = Look.oak, topL = lk(C(240, 236, 226)), kickL = Look.charcoal, led = Color3.fromRGB(255, 214, 160) }
			S.floor = { look = Look.floorOak, tile = 0 }
			S.base = Look.walnut
			S.lower = { kind = "wainscot", h = 3.0, look = lk(C(236, 228, 212)), walls = { "left", "right" } }
			S.mat = { look = lk(C(40, 50, 80), M.Fabric), text = "BUSAN" }
		else
			S.counter = { front = "wood", frontL = Look.oak, topL = Look.marbleWhite, kickL = Look.charcoal }
			S.floor = { look = Look.floorOak, tile = 0 }
			S.base = Look.walnut
			S.lower = false
		end
	end
	S._kind, S._sub = kind, sub
	return S
end

function T.build(K: any, V: any, S: any)
	local kind, sub = S._kind, S._sub
	if not kind then
		kind, sub = subtype(V)
	end
	note(K, "type " .. tostring(kind) .. "/" .. tostring(sub))
	addHostEstimates(K, V, kind)
	if kind == "cvs" then
		buildCvs(K, V, S, sub)
	elseif kind == "pharmacy" then
		buildPharmacy(K, V, S, sub)
	else
		buildRetail(K, V, S, sub)
	end
	-- 미뤄 둔 공통 벽 부착물 (스위치 · 콘센트 · 온도조절기 · 비상벨 · 사업자등록증 · 시계): 우리 진열대를 피함
	fixturesNow(K, V, S)
end

return T

end

__defs["T_style"] = function()
-- GwangalliBuildingInterior/T_style: 유형 (salon clothing surf play gym) 실내.
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (Common.luau 머리말의 S 필드)
--   build(K, V, S) 유형별 디테일 (메뉴판 · 진열 · 주방 · 간판 · 소품 · 상호작용)

local Look = __require("Look")
local Props = __require("Props")
local Interact = __require("Interact")
local Common = __require("Common")

local T = {}
T.types = { "salon", "clothing", "surf", "play", "gym" }

function T.style(V: any): any
	return {
		chair = { style = "padded", frame = Look.blackMetal, seat = Look.fabricGrey },
		table = { top = Look.oak, base = Look.blackMetal },
		counter = { front = "panel", frontL = Look.white, topL = Look.marbleWhite },
		lights = { kind = "downlight" },
	}
end

function T.build(K: any, V: any, S: any) end

return T

end

__defs["Venues"] = function()
-- GwangalliBuildingInterior/Venues: 큰 시설의 방 목록 (ShopFloor 가 없는 PC방 · 노래방 · GS25 본점 · 딜리버리 · 게임랜드 · 볼링장 층 ...).
-- tools/venues/rooms.json 에서 tools/venues/gen_venues.py 로 생성 (손으로 고치지 말고 JSON 을 고친 뒤 다시 생성).
--   Venues.LIST = { { group, name, rooms = { { room, type, center (바닥 윗면 가운데, 월드), size (월드 축 X, 높이, Z),
--                    face ("+X" | "-X" | "+Z" | "-Z" = 입구 쪽 월드 방향), door?, lanes?, noDoorGuess? } } } }
--   Venues.spec(model, venue, room) -> Scan.fitRoom 에 줄 spec,  Venues.post(V, room) -> 통로 · 포인트 keep 추가

local Venues = {}

Venues.LIST = {
	{ group = "convenience", name = "GS25 광안리점", rooms = {
		{ room = "sales", type = "gs25", center = Vector3.new(-336.12, 7.0, 284.47), size = Vector3.new(55.32, 11.0, 45.41), face = "+X", door = { x = -311.7, z = 302.0, w = 6.0 }, lanes = { { -299.69, 302.15, -311.69, 301.92 }, { -311.69, 301.92, -319.44, 299.28 }, { -319.44, 299.28, -319.23, 288.03 }, { -319.23, 288.03, -319.07, 279.53 }, { -319.07, 279.53, -318.88, 269.28 }, { -319.44, 299.28, -316.93, 304.23 }, { -316.93, 304.23, -319.84, 304.77 }, { -319.84, 304.77, -322.84, 304.72 }, { -322.84, 304.72, -329.04, 304.4 }, { -319.23, 288.03, -355.42, 287.36 } } },
		{ room = "stock", type = "stockroom", center = Vector3.new(-375.36, 7.0, 283.73), size = Vector3.new(23.22, 11.0, 44.81), face = "+X", door = { x = -364.12, z = 303.15, w = 3.6 } },
	} },
	{ group = "delivery", name = "광안 딜리버리", rooms = {
		{ room = "office", type = "delivery", center = Vector3.new(-325.68, 6.8, 341.67), size = Vector3.new(32.36, 11.2, 46.98), face = "+X", door = { x = -309.8, z = 342.0, w = 6.6 } },
		{ room = "warehouse", type = "warehouse", center = Vector3.new(-364.52, 6.8, 340.95), size = Vector3.new(47.05, 11.2, 47.25), face = "+X", door = { x = -341.0, z = 340.4, w = 14.0 }, lanes = { { -341.0, 340.4, -383.96, 342.58 }, { -383.96, 342.58, -388.0, 342.5 } } },
	} },
	{ group = "pcbang", name = "광안 PC방", rooms = {
		{ room = "front", type = "pcbang", center = Vector3.new(118.6, 6.85, 279.3), size = Vector3.new(59.0, 11.1, 22.4), face = "-Z" },
		{ room = "hall", type = "pchall", center = Vector3.new(118.6, 6.85, 318.0), size = Vector3.new(59.0, 11.1, 55.0), face = "-Z", noDoorGuess = true },
		{ room = "back", type = "pcback", center = Vector3.new(118.6, 6.85, 355.3), size = Vector3.new(59.0, 11.1, 20.6), face = "-Z", noDoorGuess = true },
	} },
	{ group = "karaoke", name = "광안 코인노래연습장", rooms = {
		{ room = "lobby", type = "karaoke", center = Vector3.new(17.2, 6.85, 280.65), size = Vector3.new(47.6, 11.1, 24.3), face = "-Z" },
		{ room = "corridor", type = "kcorridor", center = Vector3.new(17.3, 6.85, 317.0), size = Vector3.new(12.0, 11.1, 48.0), face = "-Z", noDoorGuess = true },
		{ room = "booth01", type = "kbooth", center = Vector3.new(32.35, 6.85, 299.0), size = Vector3.new(17.3, 11.1, 11.6), face = "-X" },
		{ room = "booth02", type = "kbooth", center = Vector3.new(32.35, 6.85, 311.0), size = Vector3.new(17.3, 11.1, 11.6), face = "-X" },
		{ room = "booth03", type = "kbooth", center = Vector3.new(32.35, 6.85, 323.0), size = Vector3.new(17.3, 11.1, 11.6), face = "-X" },
		{ room = "booth04", type = "kbooth", center = Vector3.new(32.35, 6.85, 335.0), size = Vector3.new(17.3, 11.1, 11.6), face = "-X" },
		{ room = "booth05", type = "kbooth", center = Vector3.new(2.17, 6.85, 299.0), size = Vector3.new(17.45, 11.1, 11.6), face = "+X" },
		{ room = "booth06", type = "kbooth", center = Vector3.new(2.17, 6.85, 311.0), size = Vector3.new(17.45, 11.1, 11.6), face = "+X" },
		{ room = "booth07", type = "kbooth", center = Vector3.new(2.17, 6.85, 323.0), size = Vector3.new(17.45, 11.1, 11.6), face = "+X" },
		{ room = "booth08", type = "kbooth", center = Vector3.new(2.17, 6.85, 335.0), size = Vector3.new(17.45, 11.1, 11.6), face = "+X" },
	} },
	{ group = "arcade", name = "광안 게임랜드", rooms = {
		{ room = "hall", type = "arcade", center = Vector3.new(-340.3, 6.8, 444.4), size = Vector3.new(74.6, 11.2, 78.6), face = "+X", door = { x = -302.6, z = 433.1, w = 12.5 } },
		{ room = "lobby", type = "stairlobby", center = Vector3.new(-312.9, 6.8, 399.5), size = Vector3.new(21.8, 11.2, 9.6), face = "+X" },
		{ room = "photo", type = "photo", center = Vector3.new(-307.2, 6.8, 387.0), size = Vector3.new(10.2, 9.7, 12.1), face = "+X", door = { x = -301.7, z = 390.2, w = 4.8 } },
	} },
	{ group = "bowling", name = "실내", rooms = {
		{ room = "lobby", type = "bowlobby", center = Vector3.new(297.6, 6.75, 456.2), size = Vector3.new(88.0, 21.9, 26.0), face = "+Z", door = { x = 264.8, z = 469.6, w = 12.0 }, name = "광안 락볼링클럽" },
		{ room = "gamezone", type = "bowarcade", center = Vector3.new(242.6, 6.75, 457.2), size = Vector3.new(22.0, 21.9, 26.0), face = "+Z", name = "락볼링 오락코너" },
		{ room = "lounge", type = "bowlounge", center = Vector3.new(264.2, 6.75, 419.6), size = Vector3.new(40.4, 21.9, 48.5), face = "+Z", noDoorGuess = true, name = "락볼링 라운지" },
		{ room = "bar", type = "bowbar", center = Vector3.new(237.4, 6.75, 422.1), size = Vector3.new(12.1, 21.9, 36.4), face = "+X", noDoorGuess = true, name = "ROCK & BOWL BAR" },
		{ room = "snack", type = "bowsnack", center = Vector3.new(257.0, 6.75, 382.5), size = Vector3.new(52.0, 21.9, 27.0), face = "+Z", noDoorGuess = true, name = "ROCK & BOWL 분식" },
		{ room = "wc_m", type = "restroom", center = Vector3.new(242.3, 6.75, 362.2), size = Vector3.new(22.5, 10.85, 10.9), face = "+X", door = { x = 253.7, z = 363.7, w = 3.5 }, name = "남자 화장실" },
		{ room = "wc_f", type = "restroom", center = Vector3.new(242.2, 6.75, 350.2), size = Vector3.new(22.4, 10.85, 10.9), face = "+X", door = { x = 253.6, z = 348.2, w = 3.5 }, name = "여자 화장실" },
		{ room = "office", type = "office", center = Vector3.new(241.8, 6.75, 336.3), size = Vector3.new(22.8, 10.85, 14.7), face = "+X", door = { x = 253.6, z = 338.0, w = 3.5 }, name = "사무실 · 창고" },
		{ room = "corridor", type = "corridor", center = Vector3.new(268.7, 6.75, 348.9), size = Vector3.new(28.5, 21.9, 40.2), face = "+Z", noDoorGuess = true, name = "락볼링 복도" },
		{ room = "elevhall", type = "elevhall", center = Vector3.new(348.2, 6.75, 457.0), size = Vector3.new(13.2, 11.9, 21.2), face = "+Z", name = "2~4층 엘리베이터 홀" },
	} },
	{ group = "bowling", name = "상층_2F-4F", rooms = {
		{ room = "billiards", type = "billiards", center = Vector3.new(282.8, 30.08, 442.45), size = Vector3.new(101.2, 9.5, 52.5), face = "+X", door = { x = 333.9, z = 459.5, w = 4.0 }, name = "광안 당구클럽" },
		{ room = "salon", type = "salon", center = Vector3.new(314.2, 41.0, 442.45), size = Vector3.new(38.4, 9.55, 52.5), face = "+X", name = "헤어살롱 (3F)" },
		{ room = "select", type = "clothing", center = Vector3.new(263.3, 41.0, 442.45), size = Vector3.new(62.2, 9.55, 52.5), face = "+X", noDoorGuess = true, name = "GWANGAN SELECT SHOP" },
		{ room = "gym", type = "gym", center = Vector3.new(282.8, 52.0, 442.45), size = Vector3.new(101.2, 9.95, 52.5), face = "+X", name = "광안 휘트니스 24" },
		{ room = "hall2", type = "elevhall", center = Vector3.new(344.2, 30.08, 457.3), size = Vector3.new(21.2, 9.5, 20.8), face = "-X", noDoorGuess = true, name = "2F 엘리베이터 홀" },
		{ room = "hall3", type = "elevhall", center = Vector3.new(344.2, 41.0, 457.3), size = Vector3.new(21.2, 9.55, 20.8), face = "-X", noDoorGuess = true, name = "3F 엘리베이터 홀" },
		{ room = "hall4", type = "elevhall", center = Vector3.new(344.2, 52.0, 457.3), size = Vector3.new(21.2, 9.95, 20.8), face = "-X", noDoorGuess = true, name = "4F 엘리베이터 홀" },
	} },
	{ group = "club", name = "CLUB OCEAN 광안", rooms = {
		{ room = "lounge2f", type = "clublounge", center = Vector3.new(-199.1, 33.9, 401.8), size = Vector3.new(42.6, 13.0, 172.6), face = "+Z", noDoorGuess = true, name = "OCEAN SKY LOUNGE" },
		{ room = "rooftop", type = "rooftop", center = Vector3.new(-143.9, 34.1, 290.6), size = Vector3.new(147.8, 12.0, 54.2), face = "-X", noDoorGuess = true, name = "OCEAN ROOFTOP" },
		{ room = "hiphop", type = "hiphop", center = Vector3.new(-121.4, 7.0, 289.5), size = Vector3.new(70.7, 15.5, 50.1), face = "-X", noDoorGuess = true, name = "ROOM 2 · HIP-HOP" },
		{ room = "corridor", type = "corridor", center = Vector3.new(-167.0, 7.0, 302.2), size = Vector3.new(18.1, 10.5, 76.3), face = "+Z", noDoorGuess = true, name = "CLUB OCEAN 복도" },
		{ room = "wc_f", type = "restroom", center = Vector3.new(-196.8, 7.0, 280.3), size = Vector3.new(41.3, 10.5, 19.6), face = "+X", noDoorGuess = true, name = "여자 화장실" },
		{ room = "wc_m", type = "restroom", center = Vector3.new(-197.0, 7.0, 301.8), size = Vector3.new(41.3, 10.5, 20.6), face = "+X", noDoorGuess = true, name = "남자 화장실" },
	} },
	{ group = "hospital", name = "광안 메디컬 의원", rooms = {
		{ room = "lobby", type = "clinic_lobby", center = Vector3.new(-504.5, 6.9, 278.3), size = Vector3.new(47.0, 11.05, 25.5), face = "-Z", name = "광안 메디컬 의원 접수" },
		{ room = "waiting", type = "clinic_waiting", center = Vector3.new(-468.5, 6.9, 279.6), size = Vector3.new(25.0, 11.05, 26.1), face = "-Z", noDoorGuess = true, name = "광안 메디컬 의원 대기실" },
		{ room = "consult", type = "clinic_consult", center = Vector3.new(-551.3, 6.9, 278.1), size = Vector3.new(43.4, 11.05, 26.9), face = "+Z", noDoorGuess = true, name = "진료실 1 · 내과" },
		{ room = "pharmacy", type = "clinic_pharmacy", center = Vector3.new(-545.3, 6.9, 308.7), size = Vector3.new(57.5, 11.05, 21.7), face = "-Z", noDoorGuess = true, name = "약국 코너" },
		{ room = "treat", type = "clinic_treat", center = Vector3.new(-479.5, 6.9, 311.1), size = Vector3.new(45.7, 11.05, 21.7), face = "-Z", noDoorGuess = true, name = "주사실 · 처치실" },
		{ room = "backhall", type = "clinic_hall", center = Vector3.new(-515.7, 6.9, 330.5), size = Vector3.new(116.7, 11.05, 12.5), face = "-Z", noDoorGuess = true, name = "후면 홀" },
		{ room = "ward201", type = "clinic_ward", center = Vector3.new(-477.5, 21.08, 278.0), size = Vector3.new(43.5, 8.4, 24.5), face = "+Z", noDoorGuess = true, name = "입원실 201" },
		{ room = "nurse", type = "clinic_nurse", center = Vector3.new(-514.4, 21.08, 277.3), size = Vector3.new(26.9, 8.4, 25.2), face = "+Z", noDoorGuess = true, name = "간호사실" },
		{ room = "ward202", type = "clinic_ward", center = Vector3.new(-551.3, 21.08, 275.9), size = Vector3.new(43.5, 8.4, 23.2), face = "+Z", noDoorGuess = true, name = "입원실 202" },
		{ room = "lounge", type = "clinic_lounge", center = Vector3.new(-475.2, 21.08, 317.4), size = Vector3.new(38.3, 8.4, 38.3), face = "-Z", noDoorGuess = true, name = "휴게실 LOUNGE" },
		{ room = "checkup", type = "clinic_checkup", center = Vector3.new(-549.0, 21.08, 316.1), size = Vector3.new(47.8, 8.4, 40.4), face = "-Z", noDoorGuess = true, name = "건강검진센터" },
	} },
	{ group = "garage", name = "광안 오토 정비소 & 중고차", rooms = {
		{ room = "showroom", type = "showroom", center = Vector3.new(-564.9, 6.67, 450.3), size = Vector3.new(68.4, 14.8, 49.3), face = "+Z", name = "광안 오토 쇼룸" },
		{ room = "bay", type = "servicebay", center = Vector3.new(-499.0, 6.66, 450.0), size = Vector3.new(46.0, 14.6, 52.1), face = "+Z", name = "광안 오토 정비 베이" },
		{ room = "wash", type = "carwash", center = Vector3.new(-455.1, 6.66, 452.6), size = Vector3.new(25.3, 13.4, 50.0), face = "+Z", noDoorGuess = true, name = "광안 오토 자동세차장" },
	} },
}

local FACE = { ["+X"] = Vector3.new(1, 0, 0), ["-X"] = Vector3.new(-1, 0, 0), ["+Z"] = Vector3.new(0, 0, 1), ["-Z"] = Vector3.new(0, 0, -1) }

-- 방 프레임: 원점 = 바닥 윗면 가운데, 로컬 +Z = 입구 쪽 (= face), -Z = 안쪽 끝
function Venues.frame(r: any): CFrame
	local e = FACE[r.face] or FACE["+Z"]
	return CFrame.lookAt(r.center, r.center - e)
end

function Venues.spec(model: Instance, v: any, r: any): any
	local cf = Venues.frame(r)
	local alongX = r.face == "+X" or r.face == "-X"
	local W = if alongX then r.size.Z else r.size.X
	local D = if alongX then r.size.X else r.size.Z
	local spec: any = {
		cf = cf,
		size = Vector3.new(W, r.size.Y, D),
		type = r.type,
		room = r.room,
		kind = "venue",
		name = r.name or v.name,
		key = string.format("%s#%s", v.name, r.room),
		noDoorGuess = r.noDoorGuess,
	}
	if r.door then
		local p = cf:PointToObjectSpace(Vector3.new(r.door.x, r.center.Y, r.door.z))
		spec.door = { x = p.X, z = p.Z, w = r.door.w }
	end
	return spec
end

-- 방 V 에 통로 (월드 선분, 폭 3) 와 포인트 (반지름 2.5) keep 추가
function Venues.post(V: any, r: any)
	for _, l in r.lanes or {} do
		local a = V.cf:PointToObjectSpace(Vector3.new(l[1], r.center.Y, l[2]))
		local b = V.cf:PointToObjectSpace(Vector3.new(l[3], r.center.Y, l[4]))
		local len = (b - a).Magnitude
		local n = math.max(1, math.ceil(len / 1.5))
		for i = 0, n do
			local p = a:Lerp(b, i / n)
			V:addKeep(Vector3.new(p.X - 1.5, 0.1, p.Z - 1.5), Vector3.new(p.X + 1.5, 6.5, p.Z + 1.5), "lane")
		end
	end
	for _, k in r.keepPts or {} do
		local p = V.cf:PointToObjectSpace(Vector3.new(k[1], k[2], k[3]))
		V:keepAround(p, 2.5, 6.5, "point")
	end
end

-- 맵에 있는 시설 찾기: { { model, venue, room } }
function Venues.find(): { any }
	local out = {}
	local g = workspace:FindFirstChild("Gwangalli")
	if not g then
		return out
	end
	for _, v in Venues.LIST do
		local grp = g:FindFirstChild(v.group)
		local m = grp and grp:FindFirstChild(v.name)
		if m then
			for _, r in v.rooms do
				table.insert(out, { model = m, venue = v, room = r })
			end
		end
	end
	return out
end

return Venues

end


local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Scan = __require("Scan")
local Build = __require("Build")
local Venues = __require("Venues")
local Homes = __require("Homes")

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

task.spawn(function()
	while true do
		local ok, err = pcall(step)
		if not ok then
			warn("[GwangalliBuildingInterior] " .. tostring(err))
		end
		task.wait(CFG.tick)
	end
end)
