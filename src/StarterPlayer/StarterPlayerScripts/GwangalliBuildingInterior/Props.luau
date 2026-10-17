--!strict
-- GwangalliBuildingInterior/Props: 실내 소품 라이브러리 (가구 · 조명 · 벽 부착물 · 카운터 소품).
-- 프레임 규약 (Kit 참고):
--   pcf  소품 프레임: 원점 = 바닥 가운데(또는 올려놓는 면 위), +Z = 소품 정면
--   dcf  표시면 프레임: 원점 = 벽/판 표면 위의 점, +X = 보는 사람 오른쪽, +Z = 보는 사람 쪽
-- 모든 함수: Props.<이름>(K, cf, o?) — o 는 선택 옵션 테이블. 크기 단위 스터드 (사람 키 ≈ 5.2, 의자 좌판 ≈ 1.9).

local Look = require(script.Parent:WaitForChild("Look"))

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
-- o.text (포스터 글자) / o.fg / o.bg, o.frame (look), o.mat (매트 색 look), o.depth,
-- o.glass (기본 true: 앞 유리. 글씨 증서 · 포스터는 false = 비스듬히 볼 때 하늘 반사가 글씨를 덮지 않음)
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
	if pick(o, "glass", true) then
		K:plate("FrameGlass", w - 2 * b, h - 2 * b, 0.01, dcf * CF(0, 0, dep * 0.75), { c = Color3.fromRGB(230, 236, 240), m = Enum.Material.Glass, t = 0.88, r = 0.2 })
	end
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
			-- 대나무 잎: 줄기 위쪽 세 마디에 가는 잎 다발 (막대사탕처럼 보이지 않게)
			for k = 0, 2 do
				local q = base:Lerp(topP, 0.6 + k * 0.17)
				for j = 0, 2 do
					local b = a + j * 2.1 + k * 0.7
					K:ell("BambooLeaves", V3(0.55, 0.06, 0.16), CF(q) * ANG(0, b, math.rad(-25)) * CF(0.25, 0, 0), leafL)
				end
			end
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
	Props.frame(K, dcf, 1.2, 1.6, { frame = Look.goldMetal, text = "사업자등록증\n\n" .. (name or "") .. "\n\n국세청", fg = Color3.fromRGB(40, 40, 40), textH = 0.9, border = 0.06, depth = 0.05, glass = false })
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
	if pick(o, "light", true) then K:light(glowP, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 6, Brightness = 0.8, Angle = 130, Color = Look.coolLight }) end
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
