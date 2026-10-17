--!strict
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
--   base = look (걸레받이) | false     pendant = { shade, look, dia, maxDrop } (맵 펜던트 바꿀 모양;
--          maxDrop = 천장에서 갓 아래까지 최대 길이: 맵 간판 · 메뉴판 앞으로 늘어지지 않게)
--   clock = bool, license = bool, cctv = bool, mat = { look, text } | false
--   lights = { kind = "downlight" | "panel" | "none", n, color, glow }  (우리 불빛, 최대 V.maxLights)

local Kit = require(script.Parent:WaitForChild("Kit"))
local Look = require(script.Parent:WaitForChild("Look"))
local Props = require(script.Parent:WaitForChild("Props"))
local Interact = require(script.Parent:WaitForChild("Interact"))
local Scan = require(script.Parent:WaitForChild("Scan"))

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
			local drop = math.min(topY - r.min.Y, ps.maxDrop or math.huge)
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
-- K.reserved 중 바닥을 비워 두는 예약 (실제 물건이 아님): 벽 자리를 막지 않음
local CLEAR_KINDS = { front = true, staff = true, wallfront = true }

-- 벽면 빈 자리 하나 찾기 (폭 w, 높이 y0..y1, prefer = 바라는 u). 반환 wn, dcf 또는 nil. 찾은 자리는 K.wallUsed 에 기록.
-- 새로 세운 키 큰 바닥 소품(K.reserved) 뒤에는 걸지 않음. test(wn, u, dcf) -> boolean (선택): 추가 조건
-- (예: 프롬프트를 둘 수 있는 자리). test 가 있으면 구간마다 0.5 간격 후보를 prefer 에 가까운 순서로 시험
function Common.wallSpot(K: any, walls: { string }, w: number, y0: number, y1: number, prefer: number?, test: ((string, number, CFrame) -> boolean)?): (string?, CFrame?)
	local V = K.V
	K.wallUsed = K.wallUsed or {}
	local extra = {}
	for _, r in K.reserved or {} do
		if not CLEAR_KINDS[r.kind] then
			table.insert(extra, r)
		end
	end
	local target = prefer or 0
	local yc = (y0 + y1) / 2
	for _, wn in walls do
		-- 빈 구간에서 이미 쓴 자리 빼기
		local cand = {}
		for _, s in V:spans(wn, y0, y1, 1.0, extra) do
			local pieces = { { s[1], s[2] } }
			for _, used in K.wallUsed do
				if used.w == wn and used.y1 > y0 and used.y0 < y1 then
					local nxt = {}
					for _, pc in pieces do
						if used.b <= pc[1] or used.a >= pc[2] then
							table.insert(nxt, pc)
						else
							if used.a > pc[1] then
								table.insert(nxt, { pc[1], used.a })
							end
							if used.b < pc[2] then
								table.insert(nxt, { used.b, pc[2] })
							end
						end
					end
					pieces = nxt
				end
			end
			for _, pc in pieces do
				if pc[2] - pc[1] >= w then
					table.insert(cand, pc)
				end
			end
		end
		-- 후보 u: 구간마다 prefer 를 구간 안으로 당긴 점 (+ test 가 있으면 0.5 간격 점들), prefer 에 가까운 순서
		local us = {}
		for _, sp in cand do
			local lo, hi = sp[1] + w / 2, sp[2] - w / 2
			table.insert(us, { u = math.clamp(target, lo, hi), n = #us })
			if test then
				local u = lo
				while u < hi - 1e-3 do
					table.insert(us, { u = u, n = #us })
					u += 0.5
				end
				table.insert(us, { u = hi, n = #us })
			end
		end
		table.sort(us, function(a, b)
			local da, db = math.abs(a.u - target), math.abs(b.u - target)
			if math.abs(da - db) > 1e-6 then
				return da < db
			end
			return a.n < b.n
		end)
		for _, c in us do
			local dcf = V:wall(wn, c.u, yc, 0.0)
			if not test or test(wn, c.u, dcf) then
				table.insert(K.wallUsed, { w = wn, a = c.u - w / 2 - 0.2, b = c.u + w / 2 + 0.2, y0 = y0, y1 = y1 })
				return wn, dcf
			end
		end
	end
	return nil, nil
end

function Common.fixtures(K: any, V: any, S: any)
	-- 조명 스위치 (상호작용) + 콘센트: 입구 쪽 옆벽, 높이 4.2. 프롬프트를 둘 수 있는 자리(맵 앵커에서 떨어진 곳)만
	local side = if V.door and V.door.x > 0 then "left" else "right"
	local wn, dcf = Common.wallSpot(K, { side, if side == "left" then "right" else "left" }, 1.0, 3.8, 4.6, if side == "left" then -V.D / 2 + 3 else V.D / 2 - 3, function(_wn: string, _u: number, d: CFrame): boolean
		return Interact.canPrompt(K, (d * CF(0, 0, 0.02)).Position) -- SwitchPlate 중심 = 프롬프트 자리
	end)
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
