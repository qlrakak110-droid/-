--!strict
-- GwangalliBuildingInterior/T_style: 유형 (salon clothing surf play gym) 실내.
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (Common.luau 머리말의 S 필드)
--   build(K, V, S) 유형별 디테일 (진열 · 설비 · 간판 · 소품 · 상호작용)
--
-- 맵의 GwShop (헤어살롱 물결 · 바다옷장 · 광안 서프 & SUP) 과 인형뽑기 가게는 이미 가구가 다 있는 매장이라
-- "엉성한 장식 파트를 같은 자리에서 더 좋은 모양으로 다시 짓고 (원본은 로컬로 숨김), 빈 벽 · 천장 · 바닥을 채우는" 방식.
--   * 게임 파트 (Seat · SalonChair · WashSeat · SofaSeat · Pouf · Bench · PosBase · CardReader · Point_* · Spot_* ·
--     StylistSpot · FitStand · GwShopClerk 인형 · ClawBase/ClawGlass/ClawTop/Joystick/Claw · ChangeMachine) 은
--     정확히 같은 자세 · 크기로만 덧씌우고 (의자 · 소파) 숨기거나, 아예 건드리지 않고 겉에 장식만 붙임 (인형뽑기 기계).
--   * 상호작용은 손님 자리 · 게임 포인트에서 6.6 스터드 넘게 떨어진 벽 쪽에만 (promptSpot).
--   * 공통 손질 (네 유형 모두): 앞 유리 시트지 뒷면 (windowSignBacks) · 홀로 선 맵 POP 양면화 (twoSidedSigns) ·
--     남은 벽에 영업시간 · 결제 (동백전 등) 아크릴 명판 (hoursPlaque, T.build 끝) · 일러스트 포스터 (portraitArt / photoArt).
-- 실제 기준: 부산 광안리 2026 동네 미용실 · 편집숍 · 서핑 숍 · 무인 인형뽑기방의 집기 · 가격 · 안내문.

local Look = require(script.Parent:WaitForChild("Look"))
local Props = require(script.Parent:WaitForChild("Props"))
local Interact = require(script.Parent:WaitForChild("Interact"))
local Common = require(script.Parent:WaitForChild("Common"))
local Scan = require(script.Parent:WaitForChild("Scan"))

local T = {}
T.types = { "salon", "clothing", "surf", "play", "gym" }

local CF, V3 = CFrame.new, Vector3.new
local ANG = CFrame.Angles
local PI = math.pi
local M = Enum.Material
local F = Enum.Font
local rgb = Color3.fromRGB
local BLACK, WHITE = Color3.new(0, 0, 0), Color3.new(1, 1, 1)

-- 작은 도구 ------------------------------------------------------------------------------------------
local function lk(c: Color3, m: Enum.Material?, extra: { [string]: any }?): { [string]: any }
	local t: { [string]: any } = { c = c, m = m or M.SmoothPlastic }
	if extra then
		for k, v in extra do
			t[k] = v
		end
	end
	return t
end
local function nl(c: Color3): { [string]: any }
	return { c = c, m = M.Neon }
end
local function gl(c: Color3?, t: number?): { [string]: any }
	return { c = c or rgb(220, 232, 238), m = M.Glass, t = t or 0.6, r = 0.12 }
end
local function dk(c: Color3, f: number): Color3
	return c:Lerp(BLACK, f)
end
local function lt(c: Color3, f: number): Color3
	return c:Lerp(WHITE, f)
end
local function rnd(seed: number, i: number): number
	local s = math.sin((seed % 9973) * 0.731 + i * 12.9898) * 43758.5453
	return s - math.floor(s)
end
local function hashStr(s: string): number
	local h = 7
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 1000003
	end
	return h
end
local function hi(K: any): boolean
	return K.detail == "high"
end
local function lowD(K: any): boolean
	return K.detail == "low"
end

-- 글자판 (dcf +Z = 보는 쪽)
local function txt(K: any, name: string, w: number, h: number, dcf: CFrame, s: string, fg: Color3, bg: Color3?, font: Enum.Font?, glow: number?, o: any?): (BasePart, TextLabel)
	local op: any = { fg = fg, bg = bg, font = font or F.GothamBold, glow = glow, d = 0.02 }
	if o then
		for k, v in o do
			op[k] = v
		end
	end
	return K:text(name, w, h, dcf, s, op)
end

-- 위를 보는 글자판 (판 윗면): p 중심, 글자 위쪽 = up
local function topCF(p: Vector3, up: Vector3): CFrame
	local x = up:Cross(Vector3.yAxis).Unit
	return CFrame.fromMatrix(p, x, up, Vector3.yAxis)
end

-- 표시면(dcf)에 붙는 원판 (축 = dcf Z)
local function wdisc(K: any, name: string, dia: number, t: number, dcf: CFrame, look: any): BasePart
	return K:disc(name, dia, t, dcf * CF(0, 0, t / 2) * ANG(PI / 2, 0, 0), look)
end

-- +Z 가 dir 쪽을 보는 바닥 프레임
local function faceCF(p: Vector3, dir: Vector3): CFrame
	local d = V3(dir.X, 0, dir.Z)
	if d.Magnitude < 1e-3 then
		d = V3(0, 0, 1)
	end
	return CFrame.lookAt(V3(p.X, p.Y, p.Z), V3(p.X, p.Y, p.Z) - d.Unit)
end

-- 맵 파트 레코드 ------------------------------------------------------------------------------------
-- 홀로 선 맵 안내판 (테이블 · 진열대 위 Sign_): 글자가 한쪽 면에만 있어 반대쪽이 빈 색판으로 보임 ->
-- 빈 면에 같은 글자 · 색의 글자판을 덧붙여 양면 아크릴 POP 처럼 (맵 파트는 그대로)
local function twoSidedSigns(K: any, V: any)
	for _, r in V.parts do
		if string.sub(r.name, 1, 5) ~= "Sign_" or r.name == "Sign_메  뉴" then
			continue
		end
		local thin = math.min(r.size.X, r.size.Y, r.size.Z)
		if thin > 0.15 or r.max.Y > V.H - 0.2 or r.min.Y < 0.3 then
			continue
		end
		-- 벽 · 유리에서 떨어져 있어야 (양면이 다 보이는 것만)
		local dWall = math.min(r.c.X - V.x0, V.x1 - r.c.X, r.c.Z - V.z0, V.z1 - r.c.Z)
		if dWall < 0.9 then
			continue
		end
		local part = r.part
		local gui = part:FindFirstChildWhichIsA("SurfaceGui")
		if not gui then
			continue
		end
		local label: any = nil
		for _, d in gui:GetDescendants() do
			if d:IsA("TextLabel") and d.Text ~= "" then
				label = d
				break
			end
		end
		if not label then
			continue
		end
		local bg = part.Color
		local fr = gui:FindFirstChildWhichIsA("Frame")
		if fr and fr.BackgroundTransparency < 0.5 then
			bg = fr.BackgroundColor3
		end
		-- 맵 글꼴이 FontFace 전용(Unknown)이면 GothamBold 로
		local fnt = F.GothamBold
		pcall(function()
			if label.Font ~= Enum.Font.Unknown then
				fnt = label.Font
			end
		end)
		-- 양쪽 면 모두에 같은 글자판 (글자 있는 면은 같은 글자로 덮이므로 똑같이 보임; Face 정보가 없는 환경에서도 안전)
		local pcfL = V.cf:ToObjectSpace(part.CFrame)
		local half = part.Size.Z / 2
		local up = pcfL.UpVector
		for _, n in { pcfL.LookVector, -pcfL.LookVector } do
			local o = r.c + n * (half + 0.004)
			local dcf = CFrame.fromMatrix(o, up:Cross(n), up, n)
			K:free(function()
				txt(K, "SignBackFace", part.Size.X - 0.02, part.Size.Y - 0.02, dcf, (string.gsub(label.Text, "<[^>]+>", "")), label.TextColor3, bg, fnt)
			end)
		end
	end
end

-- 유리창 시트지 (맵 Sign_ 판이 앞 유리 안쪽에 붙어 있으면 실내에서 검은 뒷면만 보임): 안쪽에 흰 시트 뒷면 + 테두리
local function windowSignBacks(K: any, V: any)
	for _, r in V.parts do
		if string.sub(r.name, 1, 5) == "Sign_" and r.size.Z < 0.3 and r.size.X > 0.6 and r.min.Y > 0.5 and r.max.Y < V.H - 0.1 and math.abs(r.c.Z - V.z1) < 0.6 and r.c.X > V.x0 and r.c.X < V.x1 then
			local z = r.min.Z - 0.012
			K:free(function()
				K:box("WindowVinylBack", V3(r.size.X - 0.02, r.size.Y - 0.02, 0.012), CF(r.c.X, r.c.Y, z), lk(rgb(240, 238, 234), M.SmoothPlastic, { t = 0.05 }))
				K:box("WindowVinylEdge", V3(r.size.X, 0.03, 0.014), CF(r.c.X, r.max.Y - 0.015, z - 0.002), lk(rgb(210, 208, 204)))
			end)
		end
	end
end

local function recs(V: any, name: string): { any }
	return V.byName[name] or {}
end
local function hideRec(K: any, r: any)
	Scan.hide(K.hidden, r.part)
end
-- 이름 집합 + 조건으로 숨기기
local function hideWhere(K: any, V: any, names: { [string]: boolean }, pred: ((any) -> boolean)?)
	for _, r in V.parts do
		if names[r.name] and (pred == nil or pred(r)) then
			hideRec(K, r)
		end
	end
end
local function setOf(list: { string }): { [string]: boolean }
	local t = {}
	for _, n in list do
		t[n] = true
	end
	return t
end
local function nearXZ(a: Vector3, b: Vector3): number
	local d = a - b
	return math.sqrt(d.X * d.X + d.Z * d.Z)
end

-- 가장 가까운 벽 (점 p 기준, 앞 유리 제외)
local function nearestWall(V: any, p: Vector3): string
	local best, bd = "back", p.Z - V.z0
	if p.X - V.x0 < bd then
		best, bd = "left", p.X - V.x0
	end
	if V.x1 - p.X < bd then
		best, bd = "right", V.x1 - p.X
	end
	return best
end

-- 벽 프레임 (벽 표면 기준; 바닥 소품이면 y = 0): +Z = 방 안쪽
local function wcf(V: any, wall: string, u: number, y: number, off: number?): CFrame
	return V:wall(wall, u, y, off or 0)
end

-- 상호작용 자리: 손님 자리 · 게임 포인트 · 호스트 앵커에서 6.6 넘게 (런타임 ShopLife 앵커도 Interact 가 다시 확인)
local function promptOK(K: any, V: any, lp: Vector3): boolean
	for _, list in { V.chairs, V.stools } do
		for _, ch in list do
			if nearXZ(ch.seat.c, lp) < 6.6 then
				return false
			end
		end
	end
	for _, p in V.points do
		local n = p.name or ""
		if (string.sub(n, 1, 6) == "Point_" or string.sub(n, 1, 7) == "Stylist" or string.sub(n, 1, 3) == "Fit") and nearXZ(p.c, lp) < 6.6 then
			return false
		end
	end
	return Interact.canPrompt(K, lp)
end

-- 한 자리에서 프롬프트를 띄울 작은 판 (보이는 버튼 패널): dcf 위치에 만들고 OK 면 반환
local function panelAt(K: any, V: any, dcf: CFrame, w: number, h: number, look: any): BasePart?
	local lp = dcf.Position
	if not promptOK(K, V, lp) then
		K:note("prompt spot rejected @" .. string.format("%.1f,%.1f", lp.X, lp.Z))
		return nil
	end
	return K:plate("CtrlPanel", w, h, 0.06, dcf, look)
end

-- 벽 구간 사용 기록 (Common.wallSpot 이 그 자리를 피하게): u 범위 a..b, 높이 y0..y1
local function useWall(K: any, wall: string, a: number, b: number, y0: number, y1: number)
	K.wallUsed = K.wallUsed or {}
	table.insert(K.wallUsed, { w = wall, a = math.min(a, b) - 0.2, b = math.max(a, b) + 0.2, y0 = y0, y1 = y1 })
end
-- 맵 파트 레코드가 덮는 벽 구간 기록
local function useWallRec(K: any, V: any, r: any, pad: number?)
	local wall = nearestWall(V, r.c)
	local a = V:wallCoord(wall, r.min)
	local b = V:wallCoord(wall, r.max)
	useWall(K, wall, math.min(a, b) - (pad or 0), math.max(a, b) + (pad or 0), r.min.Y, r.max.Y)
end

-- 천장 빈 자리 (x, z 근처에서 반지름 r 이 비는 곳; 못 찾으면 nil)
local function ceilSpot(K: any, x: number, z: number, r: number, reach: number?): (number?, number?)
	local R = reach or 2.5
	local best, bx, bz = math.huge, nil, nil
	for dx = -R, R, 0.5 do
		for dz = -R, R, 0.5 do
			local d = dx * dx + dz * dz
			if d < best and Common.ceilFree(K, x + dx, z + dz, r) then
				best, bx, bz = d, x + dx, z + dz
			end
		end
	end
	return bx, bz
end

-- 불빛 있는 다운라이트 (근처 빈 천장)
local function litDownlight(K: any, x: number, z: number, color: Color3?, range: number?)
	local bx, bz = ceilSpot(K, x, z, 0.8)
	if bx and bz then
		Props.downlight(K, bx, bz, { light = true, color = color or Look.warmLight, glow = Look.lampWarm, range = range or 18, bright = 1.0, dia = 0.8 })
		Common.useCeil(K, bx, bz)
	end
end

-- 레일 조명 + 일부 헤드에 SpotLight (aim 쪽)
local function litTrack(K: any, a: Vector3, b: Vector3, n: number, aim: Vector3, nLit: number, color: Color3?)
	local i0 = #K.parts
	Props.trackLight(K, a, b, n, { aim = aim })
	local lit = 0
	for i = i0 + 1, #K.parts do
		local p = K.parts[i]
		if p.Name == "TrackLens" and lit < nLit and (i - i0) % 2 == 0 then
			if K:light(p, "SpotLight", { Face = Enum.NormalId.Top, Range = 16, Brightness = 1.2, Angle = 60, Color = color or Look.warmLight }) then
				lit += 1
			end
		end
	end
end

-- 공용 소품 ------------------------------------------------------------------------------------------

-- 액자 포스터 (색 블록 그림 + 제목)
local function poster(K: any, dcf: CFrame, w: number, h: number, o: any)
	Props.frame(K, dcf, w, h, { frame = o.frame or Look.blackMetal, mat = lk(o.bg or rgb(244, 240, 232)), art = o.art, depth = 0.06, border = 0.06 })
	if o.title then
		txt(K, "PosterTitle", w * 0.82, h * (o.th or 0.16), dcf * CF(0, h * (o.ty or -0.33), 0.06), o.title, o.fg or rgb(30, 30, 30), nil, o.font or F.GothamBlack)
	end
	if o.sub then
		txt(K, "PosterSub", w * 0.78, h * 0.08, dcf * CF(0, h * (o.sy or -0.42), 0.06), o.sub, o.fg or rgb(60, 60, 60), nil, F.GothamMedium)
	end
end

-- 안내문 (흰 판 + 색 머리띠)
local function notice(K: any, dcf: CFrame, w: number, h: number, title: string, body: string, head: Color3, o: any?)
	local op: any = o or {}
	K:plate("NoticeBoard", w, h, 0.03, dcf, lk(op.bg or rgb(250, 249, 245)))
	local hh = math.min(h * 0.28, 0.5)
	K:plate("NoticeHead", w, hh, 0.035, dcf * CF(0, h / 2 - hh / 2, 0), lk(head))
	txt(K, "NoticeTitle", w * 0.9, hh * 0.78, dcf * CF(0, h / 2 - hh / 2, 0.04), title, op.titleFg or WHITE, nil, F.GothamBlack)
	txt(K, "NoticeBody", w * 0.88, (h - hh) * 0.84, dcf * CF(0, -hh / 2, 0.035), body, op.fg or rgb(40, 40, 44), nil, op.font or F.GothamMedium)
end

-- 영업시간 · 결제 안내 아크릴 명판 (입구 쪽 옆벽, 눈높이): 흰 인쇄판 + 앞 투명 아크릴 + 크롬 스탠드오프 4
local function hoursPlaque(K: any, V: any, title: string, body: string, accent: Color3)
	local w, h = 1.5, 1.05
	for _, wn in { "left", "right" } do
		local pref = if wn == "left" then -(V.z1 - 3.5) else (V.z1 - 3.5)
		local w2, d = Common.wallSpot(K, { wn }, w + 0.2, 4.5, 5.7, pref)
		if w2 and d then
			K:free(function()
				local dd = d * CF(0, 0, 0.01)
				K:plate("PlaquePrint", w, h, 0.02, dd, lk(rgb(252, 251, 248)))
				K:plate("PlaqueBand", w, 0.26, 0.022, dd * CF(0, h / 2 - 0.13, 0), lk(accent))
				txt(K, "PlaqueTitle", w * 0.9, 0.2, dd * CF(0, h / 2 - 0.13, 0.024), title, WHITE, nil, F.GothamBlack)
				txt(K, "PlaqueBody", w * 0.9, h - 0.38, dd * CF(0, -0.13, 0.024), body, rgb(40, 40, 44), nil, F.GothamMedium)
				K:plate("PlaqueAcrylic", w + 0.1, h + 0.1, 0.03, dd * CF(0, 0, 0.1), gl(rgb(236, 246, 248), 0.75))
				for _, sx in { -1, 1 } do
					for _, sy in { -1, 1 } do
						wdisc(K, "PlaqueStandoff", 0.09, 0.15, dd * CF(sx * (w / 2 - 0.02), sy * (h / 2 - 0.02), 0), Look.chrome)
					end
				end
			end)
			return
		end
	end
end

-- 병 (pcf = 놓이는 면 위, +Z = 라벨 쪽). kind = "pump" | "bottle" | "tube" | "spray" | "jar" | "tall"
local function bottle(K: any, pcf: CFrame, kind: string, h: number, c: Color3, cap: Color3?, label: Color3?)
	local capC = cap or rgb(30, 30, 32)
	local d = if kind == "jar" then h * 0.95 elseif kind == "tall" then h * 0.26 else h * 0.36
	if kind == "tube" then
		-- 세운 튜브 (뚜껑 아래)
		K:vcyl("ProdCap", h * 0.18, d * 0.75, pcf * CF(0, h * 0.09, 0), lk(capC))
		K:box("ProdTube", V3(d, h * 0.82, d * 0.42), pcf * CF(0, h * 0.18 + h * 0.41, 0), lk(c))
		K:box("ProdTubeCrimp", V3(d * 1.04, h * 0.05, d * 0.12), pcf * CF(0, h * 0.98, 0), lk(dk(c, 0.15)))
	elseif kind == "jar" then
		K:vcyl("ProdJar", h * 0.75, d, pcf * CF(0, h * 0.375, 0), lk(c))
		K:vcyl("ProdJarLid", h * 0.25, d * 1.02, pcf * CF(0, h * 0.875, 0), lk(capC, M.SmoothPlastic, { r = 0.1 }))
	else
		local bh = if kind == "pump" then h * 0.72 elseif kind == "spray" then h * 0.68 else h * 0.8
		if kind == "tall" or kind == "pump" then
			K:vcyl("ProdBottle", bh, d * (if kind == "pump" then 0.8 else 1), pcf * CF(0, bh / 2, 0), lk(c, M.SmoothPlastic, { r = 0.05 }))
		else
			K:box("ProdBottle", V3(d, bh, d * 0.62), pcf * CF(0, bh / 2, 0), lk(c, M.SmoothPlastic, { r = 0.05 }))
		end
		if kind == "pump" then
			K:vcyl("ProdPumpCollar", h * 0.06, d * 0.42, pcf * CF(0, bh + h * 0.03, 0), lk(capC))
			K:vcyl("ProdPump", h * 0.16, d * 0.12, pcf * CF(0, bh + h * 0.12, 0), lk(capC))
			K:box("ProdPumpHead", V3(d * 0.16, h * 0.06, d * 0.5), pcf * CF(0, bh + h * 0.21, d * 0.15), lk(capC))
		elseif kind == "spray" then
			K:vcyl("ProdSprayNeck", h * 0.08, d * 0.36, pcf * CF(0, bh + h * 0.04, 0), lk(capC))
			K:box("ProdSprayHead", V3(d * 0.32, h * 0.16, d * 0.5), pcf * CF(0, bh + h * 0.16, d * 0.08), lk(capC))
			K:box("ProdSprayTrigger", V3(d * 0.12, h * 0.14, d * 0.1), pcf * CF(0, bh + h * 0.04, d * 0.3) * ANG(0.3, 0, 0), lk(capC))
		else
			K:vcyl("ProdCap", h * 0.14, d * 0.4, pcf * CF(0, bh + h * 0.07, 0), lk(capC))
		end
		if label and not lowD(K) then
			local lw = if kind == "tall" or kind == "pump" then d * 0.55 else d * 0.7
			local lz = if kind == "tall" then d / 2 elseif kind == "pump" then d * 0.4 else d * 0.31
			K:box("ProdLabel", V3(lw, bh * 0.42, 0.01), pcf * CF(0, bh * 0.45, lz + 0.004), lk(label))
		end
	end
end

-- 수건: 접은 더미 (pcf = 놓이는 면, 폭 w, 깊이 d, n 장)
local function towelStack(K: any, pcf: CFrame, w: number, d: number, n: number, c: Color3)
	for i = 1, n do
		local y = (i - 0.5) * 0.17
		K:box("Towel", V3(w, 0.15, d), pcf * CF((rnd(i, 3) - 0.5) * 0.05, y, 0), lk(if i % 2 == 0 then dk(c, 0.05) else c, M.Fabric))
	end
end
-- 말아 둔 수건 (축 = pcf X)
local function towelRoll(K: any, pcf: CFrame, len: number, dia: number, c: Color3)
	K:cyl("TowelRoll", len, dia, pcf * CF(0, dia / 2, 0), lk(c, M.Fabric))
	K:cyl("TowelRollEnd", 0.02, dia * 0.5, pcf * CF(len / 2 + 0.005, dia / 2, 0), lk(dk(c, 0.12), M.Fabric))
end

-- 작은 화분
local function smallPlant(K: any, pcf: CFrame, dia: number, h: number, pot: any?)
	Props.potPlant(K, pcf, dia, h, { pot = pot or Look.white })
end

-- 전선 (점 목록 따라)
local function cable(K: any, pts: { Vector3 }, d: number?, look: any?)
	for i = 1, #pts - 1 do
		K:seg("Cable", pts[i], pts[i + 1], d or 0.05, look or Look.black, 0.03)
	end
end

-- 매장 입구 쪽 바닥 안내 스티커 등 위를 보는 글자
local function floorText(K: any, p: Vector3, up: Vector3, w: number, h: number, s: string, fg: Color3, bg: Color3?)
	K:free(function()
		txt(K, "FloorText", w, h, topCF(p, up), s, fg, bg, F.GothamBlack, nil, { d = 0.01 })
	end)
end

--================================================================================================
-- 미용실 (salon)
--================================================================================================
local SALON = {
	pink = rgb(232, 182, 186),
	rose = rgb(206, 138, 146),
	cream = rgb(244, 236, 226),
	walnut = rgb(112, 78, 54),
	brass = rgb(190, 156, 96),
	ink = rgb(28, 26, 28),
	leather = rgb(30, 28, 30),
}

-- 미용 의자 (유압식): 앉은 사람이 pcf +Z 를 봄. top = 좌판 윗면
local function salonChair(K: any, pcf: CFrame, top: number, w: number, d: number, o: any)
	local leather = lk(o.leather or SALON.leather, M.Leather)
	local chrome = Look.chrome
	local hw, hd = w / 2, d / 2
	-- 받침 원판 + 돔
	K:disc("ChairBaseDisc", 2.1, 0.1, pcf * CF(0, 0.05, 0), chrome)
	K:ell("ChairBaseDome", V3(1.7, 0.22, 1.7), pcf * CF(0, 0.1, 0), chrome)
	-- 유압 기둥 + 주름 커버
	K:vcyl("ChairPump", 0.75, 0.42, pcf * CF(0, 0.55, 0), chrome)
	K:vcyl("ChairBellows", 0.3, 0.5, pcf * CF(0, 1.05, 0), Look.rubber)
	K:box("ChairPumpHousing", V3(1.1, 0.26, 1.1), pcf * CF(0, top - 0.55, 0), Look.blackMetal)
	-- 펌프 페달 (오른쪽)
	K:bar("ChairPedal", (pcf * CF(0.25, 0.42, 0.1)).Position, (pcf * CF(0.95, 0.24, 0.35)).Position, 0.08, 0.06, chrome)
	K:box("ChairPedalPad", V3(0.36, 0.06, 0.26), pcf * CF(1.0, 0.22, 0.38), Look.rubber)
	-- 좌판 (가죽 + 테두리 파이핑)
	K:rbox("ChairSeatPad", V3(w, 0.36, d), 0.14, pcf * CF(0, top - 0.18, 0) * ANG(0, PI / 2, 0), leather)
	K:box("ChairSeatPiping", V3(w - 0.12, 0.04, d - 0.12), pcf * CF(0, top - 0.005, 0), lk(dk(o.leather or SALON.leather, 0.3), M.Leather))
	K:box("ChairSeatShell", V3(w - 0.1, 0.12, d - 0.1), pcf * CF(0, top - 0.42, 0), Look.blackMetal)
	-- 등받이 (뒤 -Z, 약간 젖힘) + 누빔 줄
	local bh = 2.75
	local back = pcf * CF(0, top, -hd + 0.08) * ANG(-0.12, 0, 0) * CF(0, bh / 2, -0.12)
	K:rbox("ChairBackPad", V3(0.34, bh, w * 0.94), 0.16, back * ANG(0, PI / 2, 0), leather)
	if not lowD(K) then
		for i = 1, 3 do
			K:box("ChairBackTuft", V3(w * 0.8, 0.03, 0.02), back * CF(0, -bh / 2 + bh * i / 4, 0.175), lk(dk(o.leather or SALON.leather, 0.35), M.Leather))
		end
	end
	K:box("ChairBackShell", V3(w * 0.9, bh - 0.2, 0.08), back * CF(0, 0, -0.2), Look.blackMetal)
	-- 머리받이 (크롬 기둥 위)
	K:seg("ChairHeadStem", (back * CF(0, bh / 2 - 0.1, -0.12)).Position, (back * CF(0, bh / 2 + 0.45, -0.12)).Position, 0.08, chrome)
	K:rbox("ChairHeadrest", V3(0.28, 0.5, 1.0), 0.14, back * CF(0, bh / 2 + 0.55, -0.02) * ANG(0, PI / 2, 0), leather)
	-- 팔걸이 (크롬 지지대 + 가죽 패드)
	for _, sx in { -1, 1 } do
		local x = sx * (hw + 0.1)
		K:bar("ChairArmPost", (pcf * CF(x, top - 0.3, -hd + 0.25)).Position, (pcf * CF(x, top + 0.38, -hd + 0.35)).Position, 0.08, 0.08, chrome)
		K:bar("ChairArmPost", (pcf * CF(x, top - 0.3, hd - 0.2)).Position, (pcf * CF(x, top + 0.38, hd - 0.3)).Position, 0.08, 0.08, chrome)
		K:rbox("ChairArmPad", V3(0.28, 0.16, d * 0.82), 0.07, pcf * CF(x, top + 0.46, 0) * ANG(0, PI / 2, 0) * ANG(0, PI / 2, 0), leather)
	end
	-- 발판 (앞)
	local fz = hd + 0.55
	K:bar("ChairFootStrut", (pcf * CF(-0.35, top - 0.6, hd - 0.4)).Position, (pcf * CF(-0.35, 0.5, fz)).Position, 0.08, 0.08, chrome)
	K:bar("ChairFootStrut", (pcf * CF(0.35, top - 0.6, hd - 0.4)).Position, (pcf * CF(0.35, 0.5, fz)).Position, 0.08, 0.08, chrome)
	K:box("ChairFootPlate", V3(1.25, 0.08, 0.5), pcf * CF(0, 0.5, fz + 0.08), chrome)
	if not lowD(K) then
		for i = -2, 2 do
			K:box("ChairFootGrip", V3(0.06, 0.03, 0.42), pcf * CF(i * 0.22, 0.55, fz + 0.08), Look.rubber)
		end
	end
end

-- 바닥에 떨어진 머리카락 뭉치 (의자 둘레)
local function hairClumps(K: any, p: Vector3, seed: number, c: Color3)
	if lowD(K) then
		return
	end
	for i = 1, 6 do
		local a = rnd(seed, i) * PI * 2
		local r = 1.2 + rnd(seed, i + 9) * 0.7
		local s = 0.18 + rnd(seed, i + 20) * 0.22
		K:free(function()
			K:ell("HairClipping", V3(s * 1.6, 0.03, s), CF(p.X + math.cos(a) * r, 0.03, p.Z + math.sin(a) * r) * ANG(0, a, 0), lk(c, M.Fabric))
		end)
	end
end

-- 스타일링 스테이션 (벽 거울 + 콘솔 + 도구). wall, u = 의자 중심의 벽 좌표
local function salonStation(K: any, V: any, wall: string, u: number, idx: number, seed: number)
	local mw, mh, my = 3.2, 4.6, 5.9
	local brass = lk(SALON.brass, M.Metal, { r = 0.12 })
	K:free(function()
		-- 거울 뒤 간접광 (네온 판이 거울 둘레로 0.08 비침)
		local halo = K:panel("MirrorLEDHalo", mw + 0.18, mh + 0.18, 0.04, 0.5, wcf(V, wall, u, my, 0.01), Look.lampWarm)
		local _ = halo
		K:panel("MirrorBacker", mw + 0.02, mh + 0.02, 0.1, 0.45, wcf(V, wall, u, my, 0.04), lk(rgb(40, 38, 40)))
		K:panel("StationMirror", mw, mh, 0.03, 0.42, wcf(V, wall, u, my, 0.14), Look.mirror)
		-- 거울 반사 하이라이트 (사선 두 줄)
		K:plate("MirrorSheen", 0.34, 2.5, 0.004, wcf(V, wall, u - 0.55, my + 0.35, 0.171) * ANG(0, 0, -0.55), lk(WHITE, M.Glass, { t = 0.84 }))
		K:plate("MirrorSheen", 0.12, 2.1, 0.004, wcf(V, wall, u - 0.05, my + 0.2, 0.171) * ANG(0, 0, -0.55), lk(WHITE, M.Glass, { t = 0.86 }))
		-- 거울 아래 터치 스위치 · 번호
		K:plate("MirrorTouch", 0.16, 0.16, 0.01, wcf(V, wall, u + mw / 2 - 0.4, my - mh / 2 + 0.35, 0.17), lk(rgb(200, 200, 204), M.Glass, { t = 0.3 }))
		txt(K, "StationNo", 0.6, 0.3, wcf(V, wall, u - mw / 2 + 0.55, my - mh / 2 + 0.36, 0.175), string.format("%02d", idx), lt(SALON.brass, 0.2), nil, F.GothamMedium)
		-- 콘솔 (떠 있는 서랍장 + 월넛 상판)
		local cw, cd = 3.7, 1.25
		local top = 3.05
		local base = wcf(V, wall, u, 0, 0)
		K:box("ConsoleTop", V3(cw, 0.14, cd), base * CF(0, top + 0.07, cd / 2), lk(SALON.walnut, M.Wood))
		K:box("ConsoleTopEdge", V3(cw, 0.05, 0.03), base * CF(0, top + 0.07, cd + 0.01), brass)
		K:box("ConsoleBody", V3(cw - 0.1, 0.9, cd - 0.1), base * CF(0, top - 0.45, cd / 2 - 0.03), lk(SALON.cream))
		for i, x in { -cw / 4, cw / 4 } do
			K:box("ConsoleDrawer", V3(cw / 2 - 0.12, 0.78, 0.04), base * CF(x, top - 0.45, cd - 0.06), lk(lt(SALON.cream, 0.15)))
			K:box("ConsolePull", V3(0.6, 0.05, 0.05), base * CF(x, top - 0.18, cd - 0.02), brass)
			local _ = i
		end
		-- 아래 선반 + 바구니 (수건)
		K:box("ConsoleLowShelf", V3(cw - 0.4, 0.08, cd - 0.2), base * CF(0, 0.85, cd / 2 - 0.05), lk(SALON.walnut, M.Wood))
		K:box("ConsoleLeg", V3(0.08, top - 0.9, 0.08), base * CF(-cw / 2 + 0.25, (top - 0.9) / 2, cd - 0.2), brass)
		K:box("ConsoleLeg", V3(0.08, top - 0.9, 0.08), base * CF(cw / 2 - 0.25, (top - 0.9) / 2, cd - 0.2), brass)
		K:box("TowelBasket", V3(1.3, 0.5, 0.8), base * CF(-0.75, 1.14, cd / 2), lk(rgb(196, 170, 130), M.Fabric))
		towelStack(K, base * CF(-0.75, 1.39, cd / 2), 1.0, 0.6, 2, rgb(246, 244, 240))
		towelStack(K, base * CF(0.75, 0.89, cd / 2), 1.0, 0.7, 3, if idx % 2 == 0 then rgb(170, 170, 172) else rgb(234, 200, 202))
		-- 상판 위 도구
		local ct = base * CF(0, top + 0.14, 0)
		-- 소독액 통 (바비사이드 블루 + 빗)
		K:vcyl("CombJar", 0.8, 0.44, ct * CF(1.35, 0.4, 0.55), gl(rgb(220, 236, 240), 0.55))
		K:vcyl("CombJarFluid", 0.6, 0.38, ct * CF(1.35, 0.32, 0.55), lk(rgb(40, 120, 210), M.Glass, { t = 0.25 }))
		K:vcyl("CombJarLid", 0.06, 0.46, ct * CF(1.35, 0.83, 0.55), Look.chrome)
		for j = -1, 1 do
			K:box("JarComb", V3(0.06, 0.7, 0.14), ct * CF(1.35 + j * 0.08, 0.75, 0.55 + j * 0.04) * ANG(0, 0, j * 0.15), lk(rgb(30, 30, 30)))
		end
		-- 물 스프레이 · 제품 2
		bottle(K, ct * CF(0.85, 0, 0.45), "spray", 0.75, rgb(240, 240, 240), rgb(40, 40, 44))
		bottle(K, ct * CF(0.5, 0, 0.3), "pump", 0.7, if idx % 2 == 0 then rgb(28, 28, 30) else rgb(238, 232, 222), SALON.brass, rgb(250, 248, 244))
		bottle(K, ct * CF(0.2, 0, 0.3), "tube", 0.55, rgb(244, 214, 216), WHITE)
		-- 롤브러시 2 · 꼬리빗
		for j = 0, 1 do
			local bc = ct * CF(-0.3 - j * 0.35, 0.09, 0.85) * ANG(0, 0.2 + j * 0.3, 0)
			K:cyl("RoundBrush", 0.55, 0.18, bc * CF(0.15, 0, 0), lk(rgb(60, 60, 64), M.Fabric))
			K:cyl("RoundBrushHandle", 0.45, 0.08, bc * CF(-0.33, 0, 0), lk(if j == 0 then rgb(30, 30, 30) else SALON.rose))
		end
		K:box("TailComb", V3(0.75, 0.02, 0.08), ct * CF(-0.95, 0.01, 0.95) * ANG(0, -0.3, 0), lk(rgb(20, 20, 22)))
		-- 고데기 (매직기, 거치대 위)
		local iron = ct * CF(-1.35, 0.06, 0.55) * ANG(0, 0.4, 0)
		K:box("FlatIron", V3(0.9, 0.1, 0.14), iron, lk(rgb(30, 30, 34)))
		K:box("FlatIronPlate", V3(0.42, 0.11, 0.1), iron * CF(0.2, 0.005, 0), lk(rgb(210, 170, 150), M.Metal))
		K:box("FlatIronLED", V3(0.06, 0.02, 0.04), iron * CF(-0.25, 0.06, 0.03), nl(rgb(255, 80, 80)))
		-- 집게핀 쟁반
		K:box("ClipTray", V3(0.6, 0.06, 0.4), ct * CF(-0.75, 0.03, 0.4), lk(rgb(240, 240, 238)))
		if not lowD(K) then
			for j = 0, 3 do
				K:box("HairClip", V3(0.22, 0.06, 0.07), ct * CF(-0.95 + j * 0.13, 0.08, 0.38 + (j % 2) * 0.08) * ANG(0, j * 0.6, 0), lk(({ SALON.rose, rgb(30, 30, 30), rgb(250, 250, 250), SALON.brass })[j + 1]))
			end
		end
		-- 콘솔 뒤 멀티탭 + 전선
		K:box("PowerStrip", V3(1.2, 0.12, 0.22), ct * CF(-0.3, 0.06, 0.16), Look.plasticWhite)
		K:box("PowerStripLED", V3(0.05, 0.02, 0.05), ct * CF(-0.85, 0.13, 0.16), nl(rgb(255, 60, 40)))
		-- 드라이어 (거울 옆 벽 거치링) + 전선
		local side = mw / 2 + 0.55
		local hr = wcf(V, wall, u + side, 4.4, 0.32)
		K:box("DryerHolderArm", V3(0.12, 0.12, 0.32), hr * CF(0, 0, -0.16), brass)
		K:ring("DryerHolderRing", hr * CF(0, 0, 0.12) * ANG(PI / 2, 0, 0), 0.26, 0.05, 8, brass)
		K:vcyl("DryerBody", 0.85, 0.44, hr * CF(0, 0.32, 0.12), lk(if idx % 2 == 0 then rgb(236, 236, 234) else rgb(40, 40, 44)))
		K:vcyl("DryerNozzle", 0.35, 0.26, hr * CF(0, -0.18, 0.12), lk(rgb(50, 50, 54)))
		K:box("DryerHandle", V3(0.2, 0.18, 0.6), hr * CF(0, 0.6, 0.38) * ANG(0.35, 0, 0), lk(rgb(60, 60, 64)))
		wdisc(K, "DryerVent", 0.38, 0.02, hr * CF(0, 0.75, 0.12) * ANG(-PI / 2, 0, 0), lk(rgb(120, 120, 124), M.DiamondPlate))
		cable(K, { (hr * CF(0, 0.55, 0.62)).Position, (hr * CF(0.1, -0.6, 0.6)).Position, (ct * CF(side - 0.5, 0.1, 0.25)).Position, (ct * CF(-0.3, 0.12, 0.16)).Position }, 0.05)
		-- 미용 가운 (반대쪽 벽 고리)
		local cape = wcf(V, wall, u - side - 0.05, 6.1, 0.0)
		K:box("CapeHook", V3(0.1, 0.1, 0.3), cape * CF(0, 0, 0.15), brass)
		K:ball("CapeHookKnob", 0.16, cape * CF(0, 0, 0.31), brass)
		local capeC = if idx % 2 == 0 then rgb(120, 110, 122) else rgb(196, 160, 166)
		-- 고리에 건 가운: 목 부분에서 모이고 아래로 퍼지는 주름 5폭 + 목 밴드 + 로고
		K:cyl("CapeNeck", 0.46, 0.13, cape * CF(0, -0.1, 0.26), lk(dk(capeC, 0.2), M.Fabric))
		local len = 1.85
		for k = -2, 2 do
			local tx, bx = k * 0.06, k * 0.21
			local roll = math.atan2(bx - tx, len)
			local yaw = if k % 2 == 0 then 0.32 else -0.32
			K:box("CapePleat", V3(0.25, len, 0.03), cape * CF((tx + bx) / 2, -0.15 - len / 2, 0.22 + (k % 2) * 0.03) * ANG(0, 0, roll) * ANG(0, yaw, 0), lk(if k % 2 == 0 then capeC else dk(capeC, 0.1), M.Fabric))
		end
		K:box("CapeHem", V3(1.0, 0.05, 0.05), cape * CF(0, -0.15 - len + 0.02, 0.25), lk(dk(capeC, 0.25), M.Fabric))
		txt(K, "CapeLogo", 0.36, 0.13, cape * CF(0, -0.85, 0.255), "물결", WHITE, nil, F.GothamBlack)
	end)
	local _ = seed
end

-- 샴푸대 (의자 + 도기 볼 + 수전). seatRec = WashSeat, look = 앉은 사람이 보는 방향
local function shampooUnit(K: any, V: any, seat: any, idx: number)
	local f = seat.lcf.LookVector
	local pcf = faceCF(V3(seat.c.X, 0, seat.c.Z), f)
	local top = seat.max.Y
	local w = math.min(seat.size.X, seat.size.Z) + 0.0
	local leather = lk(rgb(228, 218, 204), M.Leather) -- 아이보리 가죽 샴푸 체어 (어두운 볼과 대비)
	K:free(function()
		-- 받침대
		K:rbox("WashPlinth", V3(w, top - 0.42, 1.95), 0.12, pcf * CF(0, (top - 0.42) / 2, 0) * ANG(0, PI / 2, 0), Look.blackMetal)
		K:box("WashKick", V3(w + 0.04, 0.12, 1.99), pcf * CF(0, 0.06, 0), Look.chrome)
		-- 좌판 · 다리받침
		K:rbox("WashSeatPad", V3(w, 0.42, 1.9), 0.15, pcf * CF(0, top - 0.21, 0) * ANG(0, PI / 2, 0), leather)
		K:rbox("WashLegRest", V3(w * 0.92, 0.32, 1.25), 0.12, pcf * CF(0, top - 0.32, 1.25) * ANG(-0.42, 0, 0) * CF(0, 0, 0.1) * ANG(0, PI / 2, 0), leather)
		-- 등받이 (뒤로 젖힘)
		local back = pcf * CF(0, top - 0.05, -0.85) * ANG(0.95, 0, 0) * CF(0, 0, -1.15)
		K:rbox("WashBackPad", V3(w * 0.96, 0.36, 2.3), 0.15, back * ANG(0, PI / 2, 0), leather)
		K:box("WashBackShell", V3(w * 0.9, 0.12, 2.2), back * CF(0, -0.22, 0), Look.blackMetal)
		-- 팔걸이
		for _, sx in { -1, 1 } do
			K:rbox("WashArm", V3(0.3, 0.3, 1.4), 0.1, pcf * CF(sx * (w / 2 + 0.08), top + 0.25, -0.1) * ANG(0, PI / 2, 0) * ANG(0, PI / 2, 0), leather)
		end
	end)
	-- 뒤 도기 세면대 (볼 + 목받침 + 수전) — 맵 BasinCabinet 자리
	local cab = nil
	for _, r in recs(V, "BasinCabinet") do
		if nearXZ(r.c, seat.c) < 4.5 then
			cab = r
		end
	end
	if cab then
		local cc = V3(cab.c.X, 0, cab.c.Z)
		local ccf = faceCF(cc, f)
		local cw, ch, cdp = cab.size.X, cab.size.Y, cab.size.Z
		if math.abs(f.X) > math.abs(f.Z) then
			cw, cdp = cab.size.Z, cab.size.X
		end
		K:free(function()
			K:box("BasinCab", V3(cw, ch - 0.1, cdp), ccf * CF(0, (ch - 0.1) / 2 + 0.1, 0), lk(SALON.cream))
			K:box("BasinCabPlinth", V3(cw - 0.1, 0.1, cdp - 0.1), ccf * CF(0, 0.05, -0.04), Look.blackMetal)
			K:box("BasinCabTop", V3(cw + 0.04, 0.12, cdp + 0.04), ccf * CF(0, ch + 0.06, 0), Look.marbleWhite)
			for _, sx in { -1, 1 } do
				K:box("BasinCabDoor", V3(cw / 2 - 0.12, ch - 0.45, 0.04), ccf * CF(sx * cw / 4, ch / 2 + 0.05, cdp / 2 + 0.01), lk(lt(SALON.cream, 0.2)))
				K:box("BasinCabPull", V3(0.05, 0.6, 0.05), ccf * CF(sx * 0.18, ch - 0.6, cdp / 2 + 0.04), lk(SALON.brass, M.Metal))
			end
			-- 도기 볼 (반쯤 묻힘) + 안쪽 + 배수구
			-- 볼 받침 기둥 + 의자 쪽으로 살짝 기운 도기 볼 (테두리 ~3.7, 등받이 끝이 목받침에 닿음)
			local bowlC = if idx % 2 == 0 then rgb(250, 250, 248) else rgb(34, 32, 34)
			K:vcyl("BasinPedestal", 0.42, 0.8, ccf * CF(0, ch + 0.33, 0.05), lk(rgb(236, 234, 230), M.SmoothPlastic, { r = 0.05 }))
			local bowl = ccf * CF(0, ch + 0.62, 0.05) * ANG(0.2, 0, 0)
			K:ell("BasinBowl", V3(1.9, 0.7, 1.55), bowl, lk(bowlC, M.SmoothPlastic, { r = 0.1 }))
			K:ell("BasinBowlInner", V3(1.55, 0.06, 1.2), bowl * CF(0, 0.31, -0.02), lk(if idx % 2 == 0 then rgb(214, 218, 220) else rgb(58, 56, 60), M.SmoothPlastic, { r = 0.15 }))
			K:disc("BasinDrain", 0.16, 0.02, bowl * CF(0, 0.345, -0.05), Look.chrome)
			-- 목받침 (볼 앞 고무 패드)
			K:cyl("BasinNeckRest", 0.7, 0.24, bowl * CF(0, 0.3, 0.72), Look.rubber)
			-- 구즈넥 수전 + 레버 + 핸드 샤워
			local tap = ccf * CF(0.25, ch + 0.12, -cdp / 2 + 0.25)
			K:vcyl("TapBody", 1.15, 0.16, tap * CF(0, 0.575, 0), Look.chrome)
			K:ring("TapNeck", tap * CF(0, 1.15, 0.3) * ANG(0, PI / 2, 0), 0.3, 0.1, 5, Look.chrome, PI * 0.5, PI * 1.5)
			K:box("TapLever", V3(0.36, 0.06, 0.08), tap * CF(0.18, 0.95, 0) * ANG(0, 0, 0.25), Look.chrome)
			-- 핸드 샤워 (볼 왼쪽) + 호스
			local shw = ccf * CF(-1.3, ch + 0.12, -0.55)
			K:vcyl("ShowerHolder", 0.3, 0.16, shw * CF(0, 0.15, 0), Look.chrome)
			K:vcyl("ShowerHead", 0.55, 0.15, shw * CF(0, 0.5, 0) * ANG(0.15, 0, 0), Look.chrome)
			K:disc("ShowerFace", 0.2, 0.02, shw * CF(0, 0.78, 0.04), lk(rgb(60, 60, 64)))
			cable(K, { (shw * CF(0, 0.15, 0)).Position, (shw * CF(0.35, 0.02, -0.15)).Position, (tap * CF(0, 0.02, 0)).Position }, 0.06, Look.chrome)
			-- 샴푸 · 린스 · 트리트먼트 펌프 (볼 왼쪽 앞)
			local sh = ccf * CF(-1.3, ch + 0.12, 0.15)
			local cols = { rgb(36, 86, 60), rgb(240, 236, 228), rgb(30, 30, 34) }
			for j = 1, 3 do
				bottle(K, sh * CF(0, 0, (j - 2) * 0.32) * ANG(0, PI / 2, 0), "pump", 0.95, cols[(j + idx) % 3 + 1], rgb(30, 30, 30), WHITE)
			end
			towelStack(K, ccf * CF(cw / 2 - 0.36, ch + 0.12, -0.15), 0.6, 0.7, 3, rgb(246, 244, 240))
		end)
		hideRec(K, cab)
		for _, nm in { "Basin", "BasinTap" } do
			for _, r in recs(V, nm) do
				if nearXZ(r.c, cab.c) < 1.6 then
					hideRec(K, r)
				end
			end
		end
	end
	hideRec(K, seat)
	for _, nm in { "WashBase", "WashBack" } do
		for _, r in recs(V, nm) do
			if nearXZ(r.c, seat.c) < 2.0 then
				hideRec(K, r)
			end
		end
	end
	K:reserve(V3(seat.min.X - 0.3, 0, seat.min.Z - 0.3), V3(seat.max.X + 0.3, 4, seat.max.Z + 0.3), "chair")
end

-- 소파 덮어씌우기 (SofaBase + SofaBack + SofaSeat 들) — 같은 크기 · 같은 좌판 높이
local function sofaOver(K: any, V: any, base: any, fabric: Color3, pillow: Color3)
	local backs = {}
	for _, r in recs(V, "SofaBack") do
		if nearXZ(r.c, base.c) < 3 then
			table.insert(backs, r)
		end
	end
	local back = backs[1]
	if not back then
		return
	end
	local dir = V3(base.c.X - back.c.X, 0, base.c.Z - back.c.Z).Unit
	local pcf = faceCF(V3(base.c.X, 0, base.c.Z), dir)
	local along = math.abs(dir.X) < 0.5
	local W = if along then base.size.X else base.size.Z
	local D = if along then base.size.Z else base.size.X
	local seatTop = base.max.Y + 0.3
	for _, r in recs(V, "SofaSeat") do
		if nearXZ(r.c, base.c) < 4 then
			seatTop = r.max.Y
		end
	end
	local backTop = back.max.Y
	local fab = lk(fabric, M.Fabric)
	local fabD = lk(dk(fabric, 0.08), M.Fabric)
	K:free(function()
		-- 다리 (브라스) + 받침
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				K:vcyl("SofaLeg", 0.25, 0.14, pcf * CF(sx * (W / 2 - 0.35), 0.125, sz * (D / 2 - 0.3)), lk(SALON.brass, M.Metal))
			end
		end
		K:rbox("SofaFrame", V3(W, seatTop - 0.45 - 0.25, D), 0.1, pcf * CF(0, 0.25 + (seatTop - 0.7) / 2, 0) * ANG(0, PI / 2, 0), fabD)
		-- 등판 + 팔걸이
		local bt = 0.55
		K:rbox("SofaBackFrame", V3(W, backTop - 0.25, bt), 0.2, pcf * CF(0, 0.25 + (backTop - 0.25) / 2, -D / 2 + bt / 2) * ANG(0, PI / 2, 0), fabD)
		local armW = 0.5
		for _, sx in { -1, 1 } do
			K:rbox("SofaArm", V3(armW, seatTop + 0.55 - 0.25, D - bt), 0.22, pcf * CF(sx * (W / 2 - armW / 2), 0.25 + (seatTop + 0.3) / 2, bt / 2) * ANG(0, PI / 2, 0) * ANG(0, PI / 2, 0), fab)
		end
		-- 좌판 쿠션 2 + 등쿠션 2 + 쿠션 베개
		local inner = W - 2 * armW
		for i = 0, 1 do
			local x = -inner / 4 + i * inner / 2
			K:rbox("SofaCushion", V3(inner / 2 - 0.04, 0.45, D - bt - 0.05), 0.16, pcf * CF(x, seatTop - 0.225, bt / 2) * ANG(0, PI / 2, 0), fab)
			K:rbox("SofaBackCushion", V3(inner / 2 - 0.06, backTop - seatTop - 0.25, 0.5), 0.2, pcf * CF(x, seatTop + (backTop - seatTop - 0.25) / 2, -D / 2 + bt + 0.2) * ANG(-0.12, 0, 0) * ANG(0, PI / 2, 0), fab)
			if not lowD(K) then
				K:rbox("SofaPillow", V3(0.9, 0.85, 0.28), 0.25, pcf * CF(x + (if i == 0 then -0.6 else 0.6), seatTop + 0.5, -D / 2 + bt + 0.6) * ANG(-0.25, (i - 0.5) * 0.5, 0) * ANG(0, PI / 2, 0), lk(pillow, M.Fabric))
				-- 단추 (누빔)
				for j = -1, 1 do
					K:ball("SofaButton", 0.07, pcf * CF(x + j * 0.6, seatTop + 0.8, -D / 2 + bt + 0.47), fabD)
				end
			end
		end
	end)
	hideRec(K, base)
	hideRec(K, back)
	for _, r in recs(V, "SofaSeat") do
		if nearXZ(r.c, base.c) < 4 then
			hideRec(K, r)
		end
	end
	K:reserve(base.min - V3(0.2, 0, 0.2), V3(base.max.X + 0.2, backTop, base.max.Z + 0.2), "sofa")
end

-- 헤어 스타일 포스터 그림 (일러스트 초상): d = poster() 에 준 dcf. 그림 칸 = 위쪽 (y -0.55 ~ 1.5).
-- 층: 해(원) -> 뒷머리 -> 몸 · 목 -> 얼굴 -> 앞머리 -> 눈 · 입 (0.0015 간격, FrameBack 앞 0.036 ~ 유리 0.045 사이)
local SKIN_ART = rgb(240, 214, 196)
local function portraitArt(K: any, d0: CFrame, kind: string, bg: Color3, hair: Color3, top: Color3, inner: Color3?, sc: number?)
	local k = sc or 1
	local d = d0
	local function ov(name: string, w: number, h: number, x: number, y: number, z: number, c: Color3, rot: number?)
		K:ell(name, V3(w * k, h * k, 0.001), d * CF(x * k, y * k, z) * ANG(0, 0, rot or 0), lk(c))
	end
	ov("ArtSun", 1.35, 1.35, 0.1, 0.85, 0.0375, lt(bg, 0.28))
	if kind == "long" then
		ov("ArtHairBack", 1.02, 1.6, 0, 0.42, 0.039, hair)
	elseif kind == "bob" then
		ov("ArtHairBack", 1.0, 1.0, 0, 0.66, 0.039, hair)
	end
	-- 몸 (어깨) + 목
	ov("ArtBody", 1.55, 0.95, 0, -0.18, 0.0405, top)
	if inner then
		ov("ArtShirt", 0.3, 0.42, 0, 0.12, 0.041, inner)
		for _, sx in { -1, 1 } do
			K:plate("ArtLapel", 0.07 * k, 0.42 * k, 0.001, d * CF(sx * 0.1 * k, 0.1 * k, 0.0412) * ANG(0, 0, sx * 0.4), lk(dk(top, 0.25)))
		end
	end
	K:plate("ArtNeck", 0.2 * k, 0.34 * k, 0.001, d * CF(0, 0.3 * k, 0.0415), lk(dk(SKIN_ART, 0.08)))
	-- 얼굴
	ov("ArtFace", 0.5, 0.66, 0, 0.75, 0.042, SKIN_ART)
	-- 앞머리 · 옆머리
	if kind == "long" then
		ov("ArtHairSide", 0.3, 1.05, -0.32, 0.38, 0.0435, hair, -0.14)
		ov("ArtHairSide", 0.3, 1.05, 0.32, 0.38, 0.0435, hair, 0.14)
		ov("ArtCurl", 0.34, 0.22, -0.24, -0.13, 0.0435, dk(hair, 0.15), 0.3)
		ov("ArtCurl", 0.34, 0.22, 0.24, -0.13, 0.0435, dk(hair, 0.15), -0.3)
		ov("ArtBangs", 0.64, 0.34, 0.05, 1.02, 0.0435, hair, -0.25)
	elseif kind == "bob" then
		ov("ArtHairSide", 0.3, 0.62, -0.31, 0.55, 0.0435, hair, -0.05)
		ov("ArtHairSide", 0.3, 0.62, 0.31, 0.55, 0.0435, hair, 0.05)
		ov("ArtBangs", 0.62, 0.3, 0, 1.03, 0.0435, hair)
		K:plate("ArtBobLine", 0.86 * k, 0.04 * k, 0.001, d * CF(0, 0.25 * k, 0.0435), lk(dk(hair, 0.2)))
	else
		ov("ArtHairTop", 0.62, 0.42, 0, 1.04, 0.0435, hair)
		ov("ArtHairPart", 0.38, 0.26, 0.13, 1.12, 0.0445, lt(hair, 0.18), -0.35)
		ov("ArtSideburn", 0.08, 0.2, -0.23, 0.82, 0.0435, hair)
		ov("ArtSideburn", 0.08, 0.2, 0.23, 0.82, 0.0435, hair)
	end
	-- 눈 · 입 (아주 단순)
	for _, sx in { -1, 1 } do
		K:plate("ArtEye", 0.09 * k, 0.022 * k, 0.001, d * CF(sx * 0.11 * k, 0.76 * k, 0.0445), lk(rgb(40, 30, 28)))
	end
	ov("ArtLips", 0.11, 0.04, 0, 0.54, 0.0445, if kind == "men" then dk(SKIN_ART, 0.25) else rgb(196, 96, 104))
end

-- 미용실 전체
local function buildSalon(K: any, V: any, S: any)
	pcall(windowSignBacks, K, V)
	pcall(twoSidedSigns, K, V)
	local seed = hashStr(V.key or V.name or "salon")
	local brass = lk(SALON.brass, M.Metal, { r = 0.12 })
	local W, H = V.W, V.H

	-- 1) 스타일링 의자 + 스테이션 ---------------------------------------------------------------------
	local stations = {}
	for _, ch in V.chairs do
		local s = ch.seat
		if string.find(s.name, "SalonChair") then
			table.insert(stations, ch)
		end
	end
	table.sort(stations, function(a, b)
		return a.seat.name < b.seat.name
	end)
	local stationHide = setOf({ "MirrorFrame", "Mirror", "MirrorLED", "ToolShelf", "ToolCabinet", "HairDryer", "Spray", "Comb", "ChairBase", "ChairPost", "ChairBody", "ChairBack", "Headrest", "Armrest", "ArmPost", "FootRest" })
	for i, ch in stations do
		local s = ch.seat
		local f = s.lcf.LookVector
		local pcf = faceCF(V3(s.c.X, 0, s.c.Z), f)
		K:free(function()
			salonChair(K, pcf, s.max.Y, math.min(s.size.X, s.size.Z), math.max(s.size.X, s.size.Z), { leather = if (seed + i) % 3 == 0 then rgb(92, 60, 48) else SALON.leather })
		end)
		hideRec(K, s)
		hideWhere(K, V, stationHide, function(r)
			return nearXZ(r.c, s.c) < 2.4 or (nearXZ(r.c, s.c) < 4.6 and (r.name == "MirrorFrame" or r.name == "Mirror" or r.name == "MirrorLED" or r.name == "ToolShelf" or r.name == "ToolCabinet" or r.name == "HairDryer" or r.name == "Spray" or r.name == "Comb"))
		end)
		K:reserve(V3(s.min.X - 0.6, 0, s.min.Z - 0.6), V3(s.max.X + 0.6, 5.6, s.max.Z + 0.6), "chair")
		-- 거울 쪽 벽: 의자가 보는 방향의 벽
		local probe = s.c + f * 6
		local wall = nearestWall(V, V3(math.clamp(probe.X, V.x0 + 0.1, V.x1 - 0.1), 0, math.clamp(probe.Z, V.z0 + 0.1, V.z1 - 0.1)))
		local u = V:wallCoord(wall, s.c)
		useWall(K, wall, u - 3.0, u + 2.6, 0, 8.4)
		local ok, err = pcall(salonStation, K, V, wall, u, i, seed)
		if not ok then
			K:note("station error: " .. tostring(err))
		end
		hairClumps(K, s.c, seed + i * 17, if i % 2 == 0 then rgb(40, 30, 24) else rgb(96, 70, 50))
	end

	-- 2) 샴푸대 -------------------------------------------------------------------------------------
	local wi = 0
	for _, ch in V.chairs do
		if ch.seat.name == "WashSeat" then
			wi += 1
			local ok, err = pcall(shampooUnit, K, V, ch.seat, wi)
			if not ok then
				K:note("shampoo error: " .. tostring(err))
			end
		end
	end
	-- 샴푸 구역 위 따뜻한 다운라이트 (어두운 가죽 · 볼이 보이게)
	do
		local sx, sz, n = 0, 0, 0
		for _, ch in V.chairs do
			if ch.seat.name == "WashSeat" then
				sx += ch.seat.c.X
				sz += ch.seat.c.Z
				n += 1
			end
		end
		if n > 0 then
			litDownlight(K, sx / n, sz / n - 1.2, Look.warmLight, 14)
		end
	end

	-- 3) 대기 소파 · 사이드 테이블 ------------------------------------------------------------------------
	for _, r in recs(V, "SofaBase") do
		local ok, err = pcall(sofaOver, K, V, r, rgb(236, 228, 216), SALON.pink)
		if not ok then
			K:note("sofa error: " .. tostring(err))
		end
	end
	for _, r in recs(V, "SideTable") do
		local p = V3(r.c.X, 0, r.c.Z)
		local h = r.max.Y
		K:free(function()
			K:disc("SideTableBase", 1.1, 0.08, CF(p.X, 0.04, p.Z), brass)
			K:vcyl("SideTableStem", h - 0.2, 0.16, CF(p.X, (h - 0.2) / 2 + 0.08, p.Z), brass)
			K:disc("SideTableTop", math.max(r.size.X, r.size.Z), 0.12, CF(p.X, h - 0.06, p.Z), Look.marbleWhite)
			K:disc("SideTableEdge", math.max(r.size.X, r.size.Z) + 0.03, 0.04, CF(p.X, h - 0.1, p.Z), brass)
			-- 스타일북 3권 · 디퓨저
			local cols = { rgb(30, 30, 34), SALON.pink, rgb(240, 236, 226) }
			for j = 1, 3 do
				local bk = CF(p.X - 0.15, h + 0.04 * j - 0.01, p.Z + 0.05) * ANG(0, 0.3 * j - 0.4, 0)
				K:box("StyleBook", V3(0.8, 0.04, 1.05), bk, lk(cols[j]))
			end
			txt(K, "StyleBookCover", 0.6, 0.3, topCF(V3(p.X - 0.15, h + 0.135, p.Z + 0.05), V3(0, 0, -1)), "HAIR\nSTYLE 2026", rgb(250, 244, 236), nil, F.GothamBlack, nil, { d = 0.005 })
			K:vcyl("Diffuser", 0.4, 0.26, CF(p.X + 0.45, h + 0.2, p.Z - 0.35), gl(rgb(200, 170, 120), 0.35))
			for j = 0, 4 do
				local a = j * PI * 2 / 5
				K:seg("DiffuserReed", V3(p.X + 0.45, h + 0.3, p.Z - 0.35), V3(p.X + 0.45 + math.cos(a) * 0.25, h + 1.05, p.Z - 0.35 + math.sin(a) * 0.25), 0.03, Look.darkWood)
			end
		end)
		hideRec(K, r)
		for _, q in recs(V, "Magazine") do
			if nearXZ(q.c, r.c) < 1.2 then
				hideRec(K, q)
			end
		end
	end

	-- 4) 리셉션 (데스크 덮개 + 위 소품) ------------------------------------------------------------------
	local rec = V:first("Reception")
	local rtop = V:first("ReceptionTop")
	if rec and rtop then
		-- 손님 쪽 = 방 가운데 쪽 (ReceptionBand 가 있으면 그쪽)
		local band = V:first("ReceptionBand")
		local fdir = if band then V3(band.c.X - rec.c.X, 0, band.c.Z - rec.c.Z) else V3(-rec.c.X, 0, 0)
		if math.abs(fdir.X) >= math.abs(fdir.Z) then
			fdir = V3(math.sign(fdir.X), 0, 0)
		else
			fdir = V3(0, 0, math.sign(fdir.Z))
		end
		local along = math.abs(fdir.X) > 0.5
		local cw = if along then rec.size.Z else rec.size.X
		local cd = if along then rec.size.X else rec.size.Z
		local ch = rec.max.Y
		local pcf = faceCF(V3(rec.c.X, 0, rec.c.Z), fdir)
		local tw = if along then rtop.size.Z else rtop.size.X
		local td = if along then rtop.size.X else rtop.size.Z
		local tcf = faceCF(V3(rtop.c.X, 0, rtop.c.Z), fdir)
		K:free(function()
			K:box("DeskBody", V3(cw, ch - 0.25, cd), pcf * CF(0, 0.25 + (ch - 0.25) / 2, 0), lk(SALON.cream))
			K:box("DeskKick", V3(cw - 0.1, 0.25, cd - 0.15), pcf * CF(0, 0.125, -0.06), Look.blackMetal)
			-- 앞면 세로 플루팅 (반원 기둥)
			local n = math.floor((cw - 0.2) / 0.3)
			for i = 0, n - 1 do
				local x = -cw / 2 + 0.1 + 0.3 * (i + 0.5)
				K:vcyl("DeskFlute", ch - 0.55, 0.26, pcf * CF(x, 0.3 + (ch - 0.55) / 2, cd / 2 + 0.01), lk(SALON.pink))
			end
			K:box("DeskBrassBand", V3(cw + 0.02, 0.06, cd + 0.02), pcf * CF(0, 0.28, 0), brass)
			-- 상판 (흰 대리석 + 브라스 띠) — 원래 상판과 같은 높이 · 크기
			K:box("DeskTop", V3(tw, rtop.size.Y, td), tcf * CF(0, rtop.c.Y, 0), Look.marbleWhite)
			K:box("DeskTopEdge", V3(tw + 0.02, 0.05, 0.03), tcf * CF(0, rtop.min.Y + 0.03, td / 2), brass)
			-- 상판 아래 간접 LED
			K:box("DeskLED", V3(cw - 0.3, 0.04, 0.06), pcf * CF(0, rtop.min.Y - 0.05, cd / 2 + 0.05), Look.lampWarm)
			-- 앞면 로고 (브라스 글자판)
			K:plate("DeskLogoBack", 2.4, 0.8, 0.03, pcf * CF(0, ch * 0.58, cd / 2 + 0.14), lk(rgb(250, 246, 240)))
			txt(K, "DeskLogo", 2.2, 0.62, pcf * CF(0, ch * 0.58, cd / 2 + 0.175), "물결 HAIR", SALON.brass, nil, F.GothamBlack)
		end)
		hideRec(K, rec)
		hideRec(K, rtop)
		if band then
			hideRec(K, band)
		end
		-- 상판 위: 예약 태블릿 · 명함꽂이 · 꽃병 · 네이버 예약 QR (PosBase · CardReader 는 그대로)
		local topY = rtop.max.Y
		local px = { V:first("PosBase"), V:first("CardReader") }
		local function freeOnTop(lp: Vector3, r: number): boolean
			for _, q in px do
				if q and nearXZ(q.c, lp) < r + 0.6 then
					return false
				end
			end
			return true
		end
		local items = {}
		for i = 0, 6 do
			local x = -tw / 2 + 0.5 + i * (tw - 1) / 6
			local lp = (tcf * CF(x, topY, 0)).Position
			if freeOnTop(lp, 0.3) then
				table.insert(items, x)
			end
		end
		K:free(function()
			local nUsed = 0
			for _, x in items do
				nUsed += 1
				local at = tcf * CF(x, topY, 0)
				if nUsed == 1 then
					-- 꽃병 (유리 + 꽃 5)
					K:vcyl("DeskVase", 0.7, 0.36, at * CF(0, 0.35, -0.2), gl(rgb(220, 236, 236), 0.45))
					for j = 0, 4 do
						local a = j * PI * 2 / 5
						K:seg("FlowerStem", (at * CF(0, 0.5, -0.2)).Position, (at * CF(math.cos(a) * 0.25, 1.15 + rnd(seed, j) * 0.25, -0.2 + math.sin(a) * 0.25)).Position, 0.03, Look.leafDark)
						K:ball("Flower", 0.26, at * CF(math.cos(a) * 0.27, 1.2 + rnd(seed, j) * 0.25, -0.2 + math.sin(a) * 0.27), lk(if j % 2 == 0 then SALON.pink else rgb(250, 246, 236), M.Fabric))
					end
				elseif nUsed == 2 then
					-- 예약 태블릿 (스탠드)
					K:box("TabletStand", V3(0.4, 0.05, 0.35), at * CF(0, 0.025, 0), brass)
					local tab = at * CF(0, 0.45, 0) * ANG(-0.35, 0, 0)
					K:box("Tablet", V3(0.9, 0.65, 0.04), tab, lk(rgb(30, 30, 32)))
					K:box("TabletScreen", V3(0.82, 0.57, 0.01), tab * CF(0, 0, 0.025), lk(rgb(250, 246, 244), M.Neon))
					txt(K, "TabletText", 0.78, 0.5, tab * CF(0, 0, 0.032), "오늘 예약\n14:00 김** 커트\n15:30 박** 셋팅펌\n17:00 이** 뿌리염색", rgb(40, 40, 44), nil, F.GothamMedium)
				elseif nUsed == 3 then
					-- 네이버 예약 QR 아크릴
					K:box("QRBase", V3(0.5, 0.05, 0.25), at * CF(0, 0.025, 0.2), Look.acrylicWhite)
					local q = at * CF(0, 0.38, 0.2) * ANG(-0.12, 0, 0)
					K:box("QRStand", V3(0.5, 0.66, 0.02), q, lk(rgb(250, 250, 250)))
					txt(K, "QRText", 0.44, 0.14, q * CF(0, 0.22, 0.012), "네이버 예약 · 리뷰", rgb(30, 160, 80), nil, F.GothamBlack)
					K:box("QRCode", V3(0.3, 0.3, 0.005), q * CF(0, -0.06, 0.012), lk(rgb(20, 20, 20)))
					for a = 0, 3 do
						K:box("QRDot", V3(0.06, 0.06, 0.004), q * CF(-0.09 + (a % 2) * 0.17, -0.12 + (a // 2) * 0.11, 0.016), lk(WHITE))
					end
				elseif nUsed == 4 then
					-- 명함꽂이 + 볼펜
					K:box("CardHolder", V3(0.4, 0.12, 0.25), at * CF(0, 0.06, 0.2), brass)
					K:box("BizCards", V3(0.34, 0.2, 0.06), at * CF(0, 0.16, 0.2) * ANG(-0.2, 0, 0), lk(rgb(250, 246, 240)))
					K:vcyl("PenCup", 0.4, 0.22, at * CF(0.35, 0.2, -0.15), lk(SALON.ink))
					K:seg("Pen", (at * CF(0.35, 0.3, -0.15)).Position, (at * CF(0.42, 0.62, -0.1)).Position, 0.03, lk(rgb(30, 30, 30)))
				end
			end
		end)
		for _, nm in { "Vase", "Flowers" } do
			for _, r in recs(V, nm) do
				if nearXZ(r.c, rtop.c) < 3.2 then
					hideRec(K, r)
				end
			end
		end
		K:reserve(rec.min - V3(0.2, 0, 0.2), V3(rec.max.X + 0.2, 4, rec.max.Z + 0.2), "counter")
	end

	-- 5) 맵 제품 선반 (직원 머리에 걸림) -> 숨기고 위쪽 진열 선반 + 로고 ------------------------------------
	local prodShelves = recs(V, "ProductShelf")
	if #prodShelves > 0 then
		local mn, mx = prodShelves[1].min, prodShelves[1].max
		for _, r in prodShelves do
			mn, mx = mn:Min(r.min), mx:Max(r.max)
			hideRec(K, r)
		end
		for _, r in recs(V, "HairProduct") do
			hideRec(K, r)
		end
		local c = (mn + mx) / 2
		local wall = nearestWall(V, c)
		local u = V:wallCoord(wall, c)
		local len = math.max(mx.X - mn.X, mx.Z - mn.Z)
		K:free(function()
			local at = Props.shelf(K, wcf(V, wall, u, 7.25, 0), len, { depth = 0.7, look = lk(SALON.walnut, M.Wood), bracket = brass })
			K:box("ShelfLED", V3(len - 0.2, 0.03, 0.05), wcf(V, wall, u, 7.15, 0.6), Look.lampWarm)
			local cols = { rgb(36, 86, 60), rgb(28, 28, 30), rgb(240, 236, 228), SALON.pink, rgb(170, 140, 100) }
			local n = math.floor((len - 0.4) / 0.45)
			for j = 1, n do
				local x = -len / 2 + 0.2 + (j - 0.5) * (len - 0.4) / n
				local kinds = { "pump", "bottle", "tall", "jar", "tube" }
				local kd = kinds[(j + seed) % #kinds + 1]
				bottle(K, at * CF(x, 0, -0.05), kd, if kd == "jar" then 0.4 else 0.75 + rnd(seed, j) * 0.25, cols[(j * 3 + seed) % #cols + 1], if j % 2 == 0 then SALON.brass else rgb(30, 30, 30), WHITE)
			end
			-- 브랜드 사인
			txt(K, "SalonWordmark", math.min(len, 4.6), 0.7, wcf(V, wall, u, 8.55, 0.06), "물결 HAIR · SINCE 2016", SALON.brass, nil, F.GothamBlack)
		end)
	end

	-- 6) 홈케어 제품 진열장 (빈 벽 구간 중 가장 긴 곳, 옆벽 뒤쪽 우선) ---------------------------------------------
	local function bestSpan(walls: { string }, y0: number, y1: number, depth: number, minLen: number, pref: (string, number, number) -> number): (string?, number, number)
		local bw, ba, bb, bs = nil, 0, 0, -math.huge
		for _, wn in walls do
			for _, s in V:spans(wn, y0, y1, depth) do
				if s[2] - s[1] >= minLen then
					local sc = pref(wn, s[1], s[2])
					if sc > bs then
						bw, ba, bb, bs = wn, s[1], s[2], sc
					end
				end
			end
		end
		return bw, ba, bb
	end
	local rw, ra, rb = bestSpan({ "left", "right" }, 0.2, 7.0, 1.4, 4.0, function(wn, a, b)
		-- 뒤쪽(-z) 이면서 긴 구간
		local mid = (a + b) / 2
		local z = if wn == "left" then -mid else mid
		return (b - a) * 1.0 - z * 0.15
	end)
	if rw then
		local len = math.min(rb - ra - 0.4, 8.4)
		local u = (ra + rb) / 2
		local pcf = wcf(V, rw, u, 0, 0)
		if K:spot(pcf * CF(0, 0, 0.6), V3(len, 7, 1.2), 0.05) then
			useWall(K, rw, u - len / 2, u + len / 2, 0, 7.6)
			local cab = lk(SALON.cream)
			K:box("RetailCabinet", V3(len, 2.6, 1.2), pcf * CF(0, 1.3, 0.6), cab)
			K:box("RetailKick", V3(len - 0.1, 0.2, 1.1), pcf * CF(0, 0.1, 0.55), Look.blackMetal)
			local nd = math.max(2, math.floor(len / 1.4))
			for i = 1, nd do
				local x = -len / 2 + (i - 0.5) * len / nd
				K:box("RetailDoor", V3(len / nd - 0.08, 2.2, 0.04), pcf * CF(x, 1.4, 1.21), lk(lt(SALON.cream, 0.2)))
				K:box("RetailPull", V3(0.05, 0.5, 0.05), pcf * CF(x + (if i % 2 == 0 then -1 else 1) * (len / nd / 2 - 0.25), 2.0, 1.25), brass)
			end
			K:box("RetailTop", V3(len + 0.06, 0.12, 1.26), pcf * CF(0, 2.66, 0.6), lk(SALON.walnut, M.Wood))
			-- 뒤판 (분홍 패널 + 아치 니치 느낌의 브라스 테)
			K:plate("RetailBack", len, 4.6, 0.04, wcf(V, rw, u, 2.72 + 2.3, 0.01), lk(SALON.pink))
			K:plate("RetailFrame", len + 0.1, 0.08, 0.1, wcf(V, rw, u, 2.72 + 4.62, 0.01), brass)
			for _, sx in { -1, 1 } do
				K:plate("RetailFrame", 0.08, 4.6, 0.1, wcf(V, rw, u + sx * (len / 2 + 0.01), 2.72 + 2.3, 0.01), brass)
			end
			-- 유리 선반 3단 + LED + 제품 줄
			local brands = {
				{ "녹차실감 샴푸 500g", "18,000", rgb(46, 110, 70), "pump" },
				{ "컬링에센스 2X 150ml", "13,000", rgb(30, 30, 34), "bottle" },
				{ "실크 테라피 60ml", "15,000", rgb(250, 240, 220), "tall" },
				{ "케라틴 앰플 트리트먼트", "22,000", SALON.rose, "tube" },
				{ "두피 스케일러", "24,000", rgb(70, 130, 160), "bottle" },
				{ "헤어 왁스 매트", "16,000", rgb(40, 40, 44), "jar" },
			}
			for si = 1, 3 do
				local y = 2.72 + si * 1.15
				K:box("GlassShelf", V3(len - 0.2, 0.06, 0.75), pcf * CF(0, y, 0.4), gl(rgb(214, 232, 230), 0.45))
				K:box("ShelfLEDStrip", V3(len - 0.3, 0.025, 0.04), pcf * CF(0, y - 0.05, 0.72), Look.lampWarm)
				local n = math.max(3, math.floor((len - 0.6) / 0.5))
				for j = 1, n do
					local b = brands[((j - 1) // 2 + si + seed) % #brands + 1]
					local x = -len / 2 + 0.3 + (j - 0.5) * (len - 0.6) / n
					bottle(K, pcf * CF(x, y + 0.03, 0.45), b[4], if b[4] == "jar" then 0.38 else 0.7 + (si % 2) * 0.15, b[3], if j % 3 == 0 then SALON.brass else rgb(30, 30, 30), WHITE)
				end
				-- 가격 레일
				local pb = brands[(si + seed) % #brands + 1]
				txt(K, "PriceRail", math.min(3.2, len * 0.45), 0.2, pcf * CF(-len / 4, y - 0.12, 0.8), pb[1] .. "  " .. pb[2] .. "원", rgb(40, 40, 40), rgb(252, 250, 246), F.GothamMedium)
				local pb2 = brands[(si + seed + 3) % #brands + 1]
				txt(K, "PriceRail", math.min(3.2, len * 0.45), 0.2, pcf * CF(len / 4, y - 0.12, 0.8), pb2[1] .. "  " .. pb2[2] .. "원", rgb(40, 40, 40), rgb(252, 250, 246), F.GothamMedium)
			end
			txt(K, "RetailHeader", math.min(len - 0.6, 4.4), 0.42, wcf(V, rw, u, 7.0, 0.06), "HOME CARE · 홈케어 제품", SALON.ink, nil, F.GothamBlack)
			-- 위 레일 조명 (벽을 비춤)
			local wc = wcf(V, rw, u, 0, 2.6).Position
			local ax = wcf(V, rw, u, 0, 0).XVector
			Props.trackLight(K, wc - ax * (len / 2 - 0.6), wc + ax * (len / 2 - 0.6), 3, { aim = -wcf(V, rw, u, 0, 0).ZVector + V3(0, -1.2, 0) })
			-- 상판 위 디스플레이 (테스터 트레이 + 거울 + 화분)
			local tp = pcf * CF(0, 2.72, 0.6)
			K:box("TesterTray", V3(1.4, 0.06, 0.6), tp * CF(-len / 4, 0.03, 0.1), lk(rgb(240, 238, 234)))
			for j = 0, 3 do
				bottle(K, tp * CF(-len / 4 - 0.5 + j * 0.33, 0.06, 0.1), "pump", 0.5, ({ rgb(46, 110, 70), rgb(30, 30, 34), SALON.rose, rgb(250, 240, 220) })[j + 1], rgb(30, 30, 30))
			end
			txt(K, "TesterLabel", 1.2, 0.18, tp * CF(-len / 4, 0.12, 0.42), "TESTER · 사용해 보세요", rgb(60, 60, 60), nil, F.GothamMedium)
			smallPlant(K, tp * CF(len / 2 - 0.5, 0, 0.1), 0.45, 0.7, lk(rgb(240, 236, 228)))
			K:ell("ShellDecor", V3(0.5, 0.25, 0.4), tp * CF(len / 4, 0.12, 0.1), lk(rgb(246, 226, 214), M.SmoothPlastic, { r = 0.1 }))
		end
	end

	-- 7) 맵 엉성한 소품 다시 짓기: 트롤리 · 수건 선반 · 수건 온장고 · 열처리기 · 낮은 진열대 -------------------------
	-- 미용 트롤리 (3단 + 서랍 + 도구)
	local trays = recs(V, "TrolleyTray")
	if #trays > 0 then
		local mn, mx = trays[1].min, trays[1].max
		for _, r in trays do
			mn, mx = mn:Min(r.min), mx:Max(r.max)
			hideRec(K, r)
		end
		for _, r in recs(V, "TrolleyPost") do
			mn, mx = mn:Min(r.min), mx:Max(r.max)
			hideRec(K, r)
		end
		local c = (mn + mx) / 2
		local p = CF(c.X, 0, c.Z) * ANG(0, PI / 2, 0)
		local tw, td = mx.X - mn.X, mx.Z - mn.Z
		K:free(function()
			local body = lk(rgb(24, 24, 26))
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					K:ball("TrolleyCaster", 0.22, p * CF(sx * (tw / 2 - 0.15), 0.11, sz * (td / 2 - 0.15)), Look.rubber)
					K:vcyl("TrolleyPostNew", 2.75, 0.08, p * CF(sx * (tw / 2 - 0.12), 0.2 + 1.375, sz * (td / 2 - 0.12)), Look.chrome)
				end
			end
			for i, y in { 0.65, 1.75, 2.85 } do
				K:box("TrolleyShelf", V3(tw, 0.1, td), p * CF(0, y, 0), body)
				K:box("TrolleyLip", V3(tw, 0.14, 0.04), p * CF(0, y + 0.1, td / 2 - 0.02), body)
				K:box("TrolleyLip", V3(tw, 0.14, 0.04), p * CF(0, y + 0.1, -td / 2 + 0.02), body)
				local _ = i
			end
			-- 맨 위: 염색 볼 + 브러시 · 호일 · 집게
			K:vcyl("TintBowl", 0.25, 0.55, p * CF(-0.3, 3.03, 0.1), lk(rgb(250, 250, 250)))
			K:disc("TintMix", 0.47, 0.02, p * CF(-0.3, 3.15, 0.1), lk(rgb(120, 70, 50)))
			K:seg("TintBrush", (p * CF(-0.3, 3.1, 0.1)).Position, (p * CF(0.2, 3.3, -0.25)).Position, 0.05, lk(rgb(30, 30, 30)))
			K:cyl("FoilRoll", 0.7, 0.18, p * CF(0.25, 3.02, 0.35), lk(rgb(200, 202, 206), M.Foil))
			K:box("FoilSheets", V3(0.5, 0.06, 0.4), p * CF(0.3, 2.98, -0.3), lk(rgb(210, 212, 216), M.Foil))
			-- 가운데: 롤 · 고무줄 통 · 스프레이
			for j = 0, 4 do
				K:cyl("PermRod", 0.5, 0.12, p * CF(-0.45 + j * 0.2, 1.88, -0.2), lk(({ rgb(240, 120, 150), rgb(120, 180, 240), rgb(250, 210, 80), rgb(140, 220, 150), rgb(200, 140, 230) })[j + 1]) )
			end
			bottle(K, p * CF(0.35, 1.8, 0.2), "spray", 0.6, rgb(240, 240, 240), rgb(40, 40, 44))
			-- 아래: 수건 · 약제 박스
			towelStack(K, p * CF(-0.1, 0.7, 0), tw - 0.35, td - 0.35, 3, rgb(240, 238, 234))
		end)
	end
	-- 수건 선반 (모서리) -> 3단 오픈 선반 + 수건
	local tsh = V:first("TowelShelf")
	if tsh then
		hideRec(K, tsh)
		for _, r in recs(V, "Towels") do
			hideRec(K, r)
		end
		local wall = nearestWall(V, tsh.c)
		local u = V:wallCoord(wall, tsh.c)
		local len = math.max(tsh.size.X, tsh.size.Z)
		K:free(function()
			for i, y in { 3.6, 4.9, 6.2 } do
				local at = Props.shelf(K, wcf(V, wall, u, y, 0), len, { depth = 1.1, look = Look.white, bracket = brass })
				local cols = { rgb(246, 244, 240), rgb(232, 196, 198), rgb(180, 180, 182) }
				for j = 0, 2 do
					towelStack(K, at * CF(-len / 2 + 0.55 + j * (len - 1.1) / 2, 0, -0.1), 0.85, 0.75, 4 - (i + j) % 2, cols[(i + j) % 3 + 1])
				end
			end
		end)
		-- 바닥 빨래 바구니
		local hb = wcf(V, wall, u, 0, 0.7)
		if K:spot(hb, V3(1.2, 1.6, 1.0), 0.05) then
			K:vcyl("LaundryBasket", 1.5, 1.1, hb * CF(0, 0.75, 0), lk(rgb(200, 182, 150), M.Fabric))
			K:ell("LaundryTowels", V3(1.0, 0.5, 1.0), hb * CF(0, 1.5, 0), lk(rgb(240, 238, 234), M.Fabric))
			txt(K, "LaundryTag", 0.7, 0.25, hb * CF(0, 1.1, 0.56), "사용한 수건", rgb(80, 70, 60), nil, F.GothamMedium)
		end
	end
	-- 수건 온장고 (UV 살균) — 유리문 여닫기
	local warmer = V:first("TowelWarmer")
	if warmer then
		hideRec(K, warmer)
		for _, nm in { "WarmerDoor", "WarmerLED" } do
			for _, r in recs(V, nm) do
				hideRec(K, r)
			end
		end
		local wd = V:first("WarmerDoor")
		local fdir = if wd then V3(wd.c.X - warmer.c.X, 0, wd.c.Z - warmer.c.Z) else V3(0, 0, 1)
		if math.abs(fdir.X) >= math.abs(fdir.Z) then
			fdir = V3(math.sign(fdir.X), 0, 0)
		else
			fdir = V3(0, 0, math.sign(fdir.Z))
		end
		local pcf = faceCF(V3(warmer.c.X, 0, warmer.c.Z), fdir)
		local ww = if math.abs(fdir.X) > 0.5 then warmer.size.Z else warmer.size.X
		local wdp = if math.abs(fdir.X) > 0.5 then warmer.size.X else warmer.size.Z
		local wh = warmer.size.Y
		local doorModel: Model? = nil
		K:free(function()
			local body = lk(rgb(236, 236, 234), M.SmoothPlastic, { r = 0.05 })
			K:box("WarmerBody", V3(ww, wh, wdp), pcf * CF(0, wh / 2, 0), body)
			K:box("WarmerInner", V3(ww - 0.25, 2.0, 0.05), pcf * CF(0, wh - 1.25, -wdp / 2 + 0.2), nl(rgb(150, 110, 255)))
			for r = 0, 1 do
				for c = 0, 2 do
					towelRoll(K, pcf * CF(-ww / 2 + 0.35 + c * (ww - 0.7) / 2, wh - 2.15 + r * 0.95, 0.1) * ANG(0, PI / 2, 0), wdp - 0.5, 0.42, rgb(250, 250, 248))
				end
				K:box("WarmerRack", V3(ww - 0.2, 0.04, wdp - 0.3), pcf * CF(0, wh - 2.18 + r * 0.95, 0), Look.chrome)
			end
			-- 아래 서랍 2
			for i = 0, 1 do
				K:box("WarmerDrawer", V3(ww - 0.16, 0.85, 0.04), pcf * CF(0, 0.55 + i * 0.95, wdp / 2 + 0.01), lk(rgb(226, 226, 224)))
				K:box("WarmerDrawerPull", V3(0.7, 0.05, 0.05), pcf * CF(0, 0.85 + i * 0.95, wdp / 2 + 0.05), Look.chrome)
			end
			-- 표시창 (온도)
			K:box("WarmerPanel", V3(ww - 0.16, 0.36, 0.04), pcf * CF(0, wh - 0.22, wdp / 2 + 0.01), lk(rgb(40, 40, 44)))
			txt(K, "WarmerTemp", 0.7, 0.24, pcf * CF(-0.3, wh - 0.22, wdp / 2 + 0.035), "65°C  UV", rgb(255, 120, 90), nil, F.Arcade, 1.6)
			K:box("WarmerLEDNew", V3(0.1, 0.1, 0.02), pcf * CF(ww / 2 - 0.25, wh - 0.22, wdp / 2 + 0.035), nl(rgb(80, 255, 120)))
			txt(K, "WarmerBrand", 1.0, 0.16, pcf * CF(0, 0.15, wdp / 2 + 0.02), "TOWEL STERILIZER", rgb(120, 120, 124), nil, F.GothamMedium)
			-- 유리문 (경첩 = 왼쪽)
			doorModel = K:group("WarmerGlassDoor", function()
				local dc = pcf * CF(0, wh - 1.3, wdp / 2 + 0.04)
				K:box("WarmerDoorFrame", V3(ww - 0.1, 2.15, 0.06), dc, lk(rgb(220, 220, 222), M.Metal))
				K:box("WarmerDoorGlass", V3(ww - 0.3, 1.95, 0.03), dc * CF(0, 0, 0.03), gl(rgb(200, 190, 240), 0.55))
				K:box("WarmerDoorHandle", V3(0.08, 1.2, 0.1), dc * CF(ww / 2 - 0.22, 0, 0.08), Look.chrome)
			end)
		end)
		if doorModel then
			local hinge = (K.cf * pcf * CF(-ww / 2 + 0.05, 0, wdp / 2 + 0.04)).Position
			local handle = doorModel:FindFirstChild("WarmerDoorHandle", true)
			if handle and handle:IsA("BasePart") and promptOK(K, V, V.cf:PointToObjectSpace(handle.Position)) then
				Interact.swing(K, doorModel, hinge, (K.cf * pcf).YVector, -PI * 0.55, { object = "수건 온장고", openText = "문 열기", closeText = "문 닫기" })
			end
		end
		K:reserve(warmer.min - V3(0.1, 0, 0.1), warmer.max + V3(0.1, 0, 0.1), "warmer")
	end
	-- 열처리기 (롤러볼 히터, 바퀴 받침) — 맵 후드 드라이어 자리
	local hood = V:first("DryerHood")
	local pole = V:first("DryerPole")
	if hood and pole then
		local dir = V3(hood.c.X - pole.c.X, 0, hood.c.Z - pole.c.Z)
		local pcf = faceCF(V3(pole.c.X, 0, pole.c.Z), if dir.Magnitude > 0.1 then dir else V3(0, 0, 1))
		local reach = dir.Magnitude
		local ringParts = {}
		local lamps = {}
		K:free(function()
			-- 5발 바퀴 받침
			for i = 0, 4 do
				local a = i * PI * 2 / 5
				K:bar("HeaterLeg", (pcf * CF(0, 0.32, 0)).Position, (pcf * CF(math.cos(a) * 1.05, 0.2, math.sin(a) * 1.05)).Position, 0.12, 0.08, Look.chrome)
				K:ball("HeaterCaster", 0.2, pcf * CF(math.cos(a) * 1.05, 0.1, math.sin(a) * 1.05), Look.rubber)
			end
			K:vcyl("HeaterHub", 0.3, 0.32, pcf * CF(0, 0.32, 0), Look.blackMetal)
			K:vcyl("HeaterPole", 3.6, 0.16, pcf * CF(0, 2.15, 0), Look.chrome)
			K:vcyl("HeaterCollar", 0.2, 0.24, pcf * CF(0, 3.2, 0), Look.blackMetal)
			-- 조절 팔 + 링 헤드
			local headY = hood.c.Y + 0.4
			K:bar("HeaterArm", (pcf * CF(0, 3.95, 0)).Position, (pcf * CF(0, headY + 0.2, reach)).Position, 0.14, 0.14, Look.blackMetal)
			K:box("HeaterControl", V3(0.7, 0.9, 0.35), pcf * CF(0, 3.55, -0.2), lk(rgb(240, 240, 238)))
			K:box("HeaterLCD", V3(0.5, 0.3, 0.01), pcf * CF(0, 3.75, -0.38) * ANG(0, PI, 0), lk(rgb(40, 160, 220), M.Neon))
			txt(K, "HeaterLCDText", 0.46, 0.26, pcf * CF(0, 3.75, -0.39) * ANG(0, PI, 0), "15:00\n60°C", WHITE, nil, F.Arcade, 1.4)
			local head = pcf * CF(0, headY, reach)
			for _, p in K:ring("HeaterRing", head * ANG(PI / 2, 0, 0), 1.05, 0.16, 12, lk(rgb(196, 198, 202), M.Metal)) do
				table.insert(ringParts, p)
			end
			-- 열 램프 포드 4 (안쪽 아래를 향함)
			for i = 0, 3 do
				local a = i * PI / 2 + PI / 4
				local pp = head * CF(math.cos(a) * 1.05, -0.05, math.sin(a) * 1.05)
				local aim = CFrame.lookAt(pp.Position, (head * CF(0, -1.0, 0)).Position)
				local hous = K:cyl("HeaterPod", 0.5, 0.36, aim * CF(0, 0, -0.1) * ANG(0, PI / 2, 0), lk(rgb(236, 236, 234)))
				local lamp = K:disc("HeaterLamp", 0.28, 0.03, aim * CF(0, 0, -0.36) * ANG(PI / 2, 0, 0), lk(rgb(150, 80, 50), M.Neon))
				table.insert(lamps, lamp)
				table.insert(ringParts, hous)
				table.insert(ringParts, lamp)
			end
			local hub = K:disc("HeaterHubCap", 0.55, 0.16, head * CF(0, 0.1, 0), lk(rgb(236, 236, 234)))
			table.insert(ringParts, hub)
			for i = 0, 3 do
				local a = i * PI / 2 + PI / 4
				local sp = K:bar("HeaterSpoke", (head * CF(0, 0.1, 0)).Position, (head * CF(math.cos(a) * 1.0, 0.0, math.sin(a) * 1.0)).Position, 0.08, 0.06, lk(rgb(200, 200, 204), M.Metal))
				if sp then
					table.insert(ringParts, sp)
				end
			end
		end)
		for _, nm in { "DryerPole", "DryerArm", "DryerHood", "DryerInner", "DryerBase" } do
			for _, r in recs(V, nm) do
				if nearXZ(r.c, pole.c) < 3.5 then
					hideRec(K, r)
				end
			end
		end
		K:reserve(V3(pole.c.X - 1.3, 0, pole.c.Z - 1.3), V3(pole.c.X + 1.3, 6, pole.c.Z + 1.3), "heater")
		-- 작동: 프롬프트 자리가 되면 켜기/끄기 (빛 + 천천히 회전), 아니면 대기 상태로 천천히 회전만
		local panel = K.parts[#K.parts]
		local on = false
		local center = (K.cf * pcf * CF(0, 0, reach)).Position
		local base = {}
		for _, p in ringParts do
			table.insert(base, { p = p, cf = p.CFrame })
		end
		local ang = 0
		Interact.anim(K, function(_t, dt)
			if not on then
				return
			end
			ang += (dt or 0.1) * 0.9
			local rot = CFrame.new(center) * CFrame.Angles(0, ang, 0) * CFrame.new(-center)
			for _, b in base do
				if b.p.Parent then
					b.p.CFrame = rot * b.cf
				end
			end
		end)
		local ctrl = nil
		for _, p in K.parts do
			if p.Name == "HeaterControl" then
				ctrl = p
			end
		end
		local _ = panel
		if ctrl and promptOK(K, V, V.cf:PointToObjectSpace(ctrl.Position)) then
			Interact.toggle(K, ctrl, {
				object = "열처리기 (롤러볼)",
				state = false,
				onText = "끄기",
				offText = "작동",
				on = function(st: boolean)
					on = st
					for _, l in lamps do
						if l.Parent then
							l.Material = if st then M.Neon else M.SmoothPlastic
							l.Color = if st then rgb(255, 120, 40) else rgb(120, 60, 40)
						end
					end
				end,
			})
		else
			on = true -- 대기 회전 (빛은 꺼진 채)
		end
	end
	-- 낮은 진열대 (화분과 겹침) -> 숨김 (화분은 Common 이 다시 지음)
	for _, nm in { "DisplayShelf", "ShampooBottle" } do
		for _, r in recs(V, nm) do
			hideRec(K, r)
		end
	end
	-- 염색 컬러 차트 (스와치 6x4)
	local chart = V:first("ColorChart")
	if chart then
		hideRec(K, chart)
		for _, r in recs(V, "HairSwatch") do
			hideRec(K, r)
		end
		local wall = nearestWall(V, chart.c)
		local u = V:wallCoord(wall, chart.c)
		local cw, chh = math.max(chart.size.X, chart.size.Z), chart.size.Y
		K:free(function()
			local d = wcf(V, wall, u, chart.c.Y - 0.2, 0.01)
			K:plate("ChartBoard", cw, chh, 0.06, d, lk(rgb(250, 248, 244)))
			K:plate("ChartFrame", cw + 0.1, 0.06, 0.08, d * CF(0, chh / 2, 0), brass)
			K:plate("ChartFrame", cw + 0.1, 0.06, 0.08, d * CF(0, -chh / 2, 0), brass)
			local cols = {
				rgb(20, 18, 18), rgb(52, 36, 28), rgb(84, 58, 40), rgb(120, 84, 56), rgb(156, 116, 80), rgb(196, 160, 116),
				rgb(110, 102, 98), rgb(140, 128, 122), rgb(176, 166, 160), rgb(214, 206, 196), rgb(236, 226, 206), rgb(246, 238, 220),
				rgb(122, 40, 46), rgb(160, 60, 70), rgb(204, 110, 120), rgb(232, 160, 172), rgb(170, 90, 150), rgb(120, 80, 160),
				rgb(60, 70, 120), rgb(70, 110, 150), rgb(80, 130, 110), rgb(150, 100, 60), rgb(200, 120, 60), rgb(230, 170, 90),
			}
			local nc, nr = 6, 4
			local sw = (cw - 0.6) / nc
			for r = 0, nr - 1 do
				for c = 0, nc - 1 do
					local col = cols[r * nc + c + 1]
					local x = -cw / 2 + 0.3 + sw * (c + 0.5)
					local y = chh / 2 - 0.55 - r * ((chh - 0.8) / nr)
					K:plate("ChartSwatch", sw * 0.55, 0.38, 0.05, d * CF(x, y, 0.06), lk(col, M.Fabric))
					if not lowD(K) then
						K:plate("ChartTag", sw * 0.55, 0.07, 0.02, d * CF(x, y + 0.23, 0.06), lk(rgb(60, 60, 60)))
					end
				end
			end
		end)
	end

	-- 8) 가격표 (맵 SalonPriceBoard 자리, 같은 항목 + 여성 · 클리닉) ---------------------------------------------
	local pboard = V:first("SalonPriceBoard")
	if pboard then
		hideRec(K, pboard)
		for _, r in recs(V, "PriceFrame") do
			if nearXZ(r.c, pboard.c) < 1.5 then
				hideRec(K, r)
			end
		end
		local wall = nearestWall(V, pboard.c)
		local u = V:wallCoord(wall, pboard.c)
		local bw, bh = math.max(pboard.size.X, pboard.size.Z), pboard.size.Y
		K:free(function()
			local d = wcf(V, wall, u, pboard.c.Y, 0.01)
			K:plate("PriceBoardFrame", bw + 0.2, bh + 0.2, 0.08, d, brass)
			K:plate("PriceBoardFace", bw, bh, 0.1, d, lk(rgb(26, 24, 26)))
			txt(K, "PriceTitle", bw * 0.8, 0.5, d * CF(0, bh / 2 - 0.42, 0.11), "PRICE  ·  시술 요금", lt(SALON.brass, 0.2), nil, F.GothamBlack)
			K:plate("PriceRule", bw * 0.86, 0.025, 0.11, d * CF(0, bh / 2 - 0.78, 0), brass)
			local colsT = {
				{ "CUT  커트", { { "여성 커트", "20,000" }, { "남성 · 댄디컷", "15,000" }, { "투블럭", "18,000" }, { "앞머리 커트", "5,000" }, { "아동 커트", "12,000" } } },
				{ "PERM  펌", { { "리젠트펌", "35,000" }, { "단발 C컬펌", "38,000" }, { "장발 웨이브펌", "40,000" }, { "셋팅펌", "90,000~" }, { "다운펌", "15,000" } } },
				{ "COLOR · CARE", { { "애쉬브라운 염색", "45,000" }, { "뿌리 염색", "40,000~" }, { "핑크 탈색", "60,000" }, { "케라틴 클리닉", "40,000~" }, { "두피 스파", "30,000" } } },
			}
			local cwid = (bw - 0.5) / 3
			for ci, col in colsT do
				local x = -bw / 2 + 0.25 + cwid * (ci - 0.5)
				txt(K, "PriceHead", cwid * 0.9, 0.34, d * CF(x, bh / 2 - 1.08, 0.11), col[1], SALON.pink, nil, F.GothamBlack)
				for ri, it in col[2] do
					local y = bh / 2 - 1.5 - (ri - 1) * 0.5
					txt(K, "PriceItem", cwid * 0.56, 0.28, d * CF(x - cwid * 0.2, y, 0.11), it[1], rgb(240, 236, 228), nil, F.GothamMedium, nil, { align = "Left" })
					txt(K, "PriceValue", cwid * 0.36, 0.28, d * CF(x + cwid * 0.29, y, 0.11), it[2], lt(SALON.brass, 0.25), nil, F.GothamBold, nil, { align = "Right" })
				end
			end
			txt(K, "PriceNote", bw * 0.9, 0.24, d * CF(0, -bh / 2 + 0.28, 0.11), "* 기장 · 모량에 따라 추가 요금  ·  네이버 예약 시 5% 적립  ·  카드 · 현금 동일", rgb(170, 166, 160), nil, F.GothamMedium)
		end)
	end

	-- 9) 벽 장식: 시즌 트렌드 포스터 · 뒷벽 타일 + 선반 + 네온 · 스타일북 꽂이 ------------------------------------------
	-- 뒷벽 (샴푸대 뒤) 타일 + 선반 + 물결 네온
	local backSpans = V:spans("back", 4.6, 9.0, 0.6)
	local bu0, bu1 = math.huge, -math.huge
	for _, r in recs(V, "BasinCabinet") do
		local a, _ = V:wallCoord("back", r.min)
		local b, _ = V:wallCoord("back", r.max)
		bu0 = math.min(bu0, math.min(a, b) - 0.3)
		bu1 = math.max(bu1, math.max(a, b) + 0.3)
	end
	if bu1 > bu0 then
		K:free(function()
			local len = bu1 - bu0
			local mid = (bu0 + bu1) / 2
			local tileL = lk(rgb(238, 214, 212), M.SmoothPlastic, { r = 0.08 })
			local d = wcf(V, "back", mid, 2.6, 0.01)
			K:plate("BackTile", len, 4.3, 0.03, d, tileL)
			for i = 1, 16 do
				local y = -2.15 + i * 0.27
				if y < 2.12 then
					K:plate("BackTileGrout", len, 0.02, 0.035, d * CF(0, y, 0), lk(rgb(250, 248, 244)))
				end
			end
			for i = 1, math.floor(len / 0.55) do
				local x = -len / 2 + i * 0.55
				K:plate("BackTileGrout", 0.02, 4.3, 0.035, d * CF(x, 0, 0), lk(rgb(250, 248, 244)))
			end
			K:plate("BackTileCap", len + 0.05, 0.1, 0.08, d * CF(0, 2.17, 0), brass)
			useWall(K, "back", bu0, bu1, 0.45, 6.5)
			-- 선반 + 소품
			local at = Props.shelf(K, wcf(V, "back", mid, 5.6, 0), len - 0.4, { depth = 0.7, look = lk(SALON.walnut, M.Wood), bracket = brass })
			for j = 0, 5 do
				local x = -len / 2 + 0.6 + j * (len - 1.2) / 5
				if j % 3 == 0 then
					smallPlant(K, at * CF(x, 0, -0.05), 0.42, 0.8, lk(rgb(240, 236, 228)))
				elseif j % 3 == 1 then
					towelStack(K, at * CF(x, 0, -0.05), 0.8, 0.55, 3, rgb(246, 244, 240))
				else
					bottle(K, at * CF(x, 0, -0.05), "tall", 0.9, rgb(46, 110, 70), rgb(30, 30, 30), WHITE)
					bottle(K, at * CF(x + 0.3, 0, -0.05), "tall", 0.8, rgb(240, 236, 228), SALON.brass, rgb(46, 110, 70))
				end
			end
		end)
		-- 네온 (물결 로고 + 물결선)
		local nu = (bu0 + bu1) / 2
		for _, s in backSpans do
			if nu > s[1] + 2.2 and nu < s[2] - 2.2 then
				K:free(function()
					local nd = wcf(V, "back", nu, 7.55, 0.02)
					K:plate("NeonBacker", 4.0, 1.5, 0.05, nd, gl(rgb(40, 34, 38), 0.4))
					local p = txt(K, "NeonLogoLED", 2.2, 0.9, nd * CF(-0.5, 0.15, 0.08), "물결", rgb(255, 170, 190), nil, F.GothamBlack, 2.2)
					txt(K, "NeonSubLED", 1.6, 0.3, nd * CF(1.15, -0.42, 0.08), "hair & spa", rgb(255, 230, 236), nil, F.IndieFlower, 2.0)
					for i = 0, 5 do
						local x0 = -1.6 + i * 0.55
						K:bar("NeonWaveLED", (nd * CF(x0, -0.5 + (i % 2) * 0.16, 0.08)).Position, (nd * CF(x0 + 0.55, -0.5 + ((i + 1) % 2) * 0.16, 0.08)).Position, 0.05, 0.05, nl(rgb(255, 150, 175)))
					end
					K:light(p, "SurfaceLight", { Face = Enum.NormalId.Front, Range = 8, Brightness = 0.7, Angle = 120, Color = rgb(255, 170, 190) })
					useWall(K, "back", nu - 2.1, nu + 2.1, 6.7, 8.4)
				end)
				break
			end
		end
	end
	-- 남은 옆벽 빈 자리: 시즌 트렌드 포스터 2 + 스타일북 꽂이
	local posters = {
		{ "2026 S/S 트렌드\n레이어드 C컬", "물결 스타일 제안", "long", rgb(232, 182, 186), rgb(60, 40, 34), rgb(250, 244, 236), nil, SALON.ink },
		{ "애쉬 베이지\n톤다운 컬러", "탈색 없이 가능", "bob", rgb(96, 104, 112), rgb(206, 190, 168), rgb(240, 236, 228), nil, WHITE },
		{ "남자 댄디컷\n가르마펌", "10월 이벤트 20% ↓", "men", rgb(214, 206, 192), rgb(30, 26, 24), rgb(44, 58, 92), rgb(250, 250, 248), SALON.ink },
	}
	local pi = 0
	for _, wn in { "right", "left" } do
		local s = 0
		while pi < #posters and s < 3 do
			s += 1
			local w2, d2 = Common.wallSpot(K, { wn }, 2.6, 4.6, 8.4, if wn == "left" then 6 else -6)
			if w2 and d2 then
				pi += 1
				local pp = posters[pi]
				local pd = d2 * CF(0, 0, 0.01)
				poster(K, pd, 2.4, 3.4, { title = pp[1], sub = pp[2], th = 0.18, ty = -0.3, sy = -0.43, frame = brass, bg = pp[4], fg = pp[8], font = F.GothamBlack })
				portraitArt(K, pd, pp[3], pp[4], pp[5], pp[6], pp[7])
			else
				break
			end
		end
	end

	-- 맵 브랜드 포스터 (Sign_물결 + PosterFrame) -> 같은 자리 일러스트 포스터 (물결 웨이브 헤어)
	for _, sg in recs(V, "Sign_물결") do
		local wn = nearestWall(V, sg.c)
		if math.min(math.abs(sg.c.X - V.x0), math.abs(sg.c.X - V.x1), math.abs(sg.c.Z - V.z0)) < 0.4 then
			local u = V:wallCoord(wn, sg.c)
			local pw = math.max(sg.size.X, sg.size.Z)
			local ph = sg.size.Y
			local pd = wcf(V, wn, u, sg.c.Y, 0.01)
			K:free(function()
				poster(K, pd, pw, ph, { title = "물결", sub = "자연스럽게, 나답게", th = 0.16, ty = -0.29, sy = -0.41, frame = brass, bg = rgb(226, 176, 182), fg = WHITE, font = F.GothamBlack })
				portraitArt(K, pd * CF(0, ph * 0.04, 0), "long", rgb(226, 176, 182), rgb(70, 46, 38), rgb(250, 244, 236), nil, math.min(pw / 2.4, ph / 3.6))
			end)
			hideRec(K, sg)
			for _, fr in recs(V, "PosterFrame") do
				if nearXZ(fr.c, sg.c) < 0.6 then
					hideRec(K, fr)
				end
			end
		end
	end

	-- 디자이너 소개 보드 (원장 · 실장 · 디자이너)
	local dw, dd = Common.wallSpot(K, { "left", "right", "back" }, 1.85, 4.3, 7.1, 9)
	if dw and dd then
		K:free(function()
			local d = dd * CF(0, 0, 0.01)
			K:plate("DesignerBoard", 1.75, 2.7, 0.04, d, lk(rgb(250, 246, 240)))
			K:plate("DesignerBoardTop", 1.75, 0.06, 0.06, d * CF(0, 1.35, 0), brass)
			txt(K, "DesignerTitle", 1.6, 0.3, d * CF(0, 1.08, 0.045), "OUR DESIGNERS", SALON.ink, nil, F.GothamBlack)
			local ppl = { { "원장 이물결", "펌 · 염색 18년" }, { "실장 김하늘", "커트 · 남성 펌" }, { "디자이너 박소라", "탈색 · 클리닉" } }
			for i, pr in ppl do
				local y = 0.62 - (i - 1) * 0.72
				K:plate("DesignerPhoto", 0.5, 0.6, 0.05, d * CF(-0.5, y, 0), lk(({ rgb(214, 190, 176), rgb(196, 176, 168), rgb(226, 204, 196) })[i]))
				K:ell("DesignerPhotoHead", V3(0.22, 0.26, 0.02), d * CF(-0.5, y + 0.08, 0.06), lk(({ rgb(60, 40, 32), rgb(30, 26, 24), rgb(150, 100, 70) })[i]))
				K:plate("DesignerPhotoBody", 0.34, 0.2, 0.055, d * CF(-0.5, y - 0.2, 0), lk(SALON.ink))
				txt(K, "DesignerName", 1.0, 0.22, d * CF(0.32, y + 0.12, 0.045), pr[1], SALON.ink, nil, F.GothamBold, nil, { align = "Left" })
				txt(K, "DesignerSpec", 1.0, 0.17, d * CF(0.32, y - 0.14, 0.045), pr[2], rgb(140, 120, 120), nil, F.GothamMedium, nil, { align = "Left" })
			end
		end)
	end

	-- 10) 조명 · BGM 패널 (상호작용): 옆벽 낮은 곳 ---------------------------------------------------------
	local bgm = { "♪ 잔나비 - 주저하는 연인들을 위해", "♪ 아이유 - 밤편지", "♪ 데이식스 - 한 페이지가 될 수 있게", "♪ 10CM - 스토커", "♪ 성시경 - 너의 모든 순간" }
	for _, wn in { "right", "left", "back" } do
		local w3, d3 = Common.wallSpot(K, { wn }, 1.4, 3.7, 4.9, -V.D / 4)
		if w3 and d3 and promptOK(K, V, d3.Position) then
			local plate = K:plate("BGMPanel", 1.2, 0.95, 0.06, d3, lk(rgb(30, 30, 32)))
			local scr = K:plate("BGMScreen", 1.04, 0.42, 0.02, d3 * CF(0, 0.16, 0.06), lk(rgb(20, 30, 40), M.Neon))
			local _, lab = txt(K, "BGMText", 1.0, 0.36, d3 * CF(0, 0.16, 0.085), bgm[1], rgb(180, 230, 255), nil, F.GothamMedium, 1.4)
			txt(K, "BGMLabel", 1.0, 0.16, d3 * CF(0, -0.18, 0.07), "매장 음악 · 조명", rgb(200, 200, 200), nil, F.GothamMedium)
			for j = 0, 2 do
				wdisc(K, "BGMButton", 0.16, 0.03, d3 * CF(-0.3 + j * 0.3, -0.36, 0.06), lk(rgb(200, 200, 204)))
			end
			local _ = scr
			Interact.cycle(K, plate, bgm, {
				object = "매장 음악",
				action = "다음 곡",
				on = function(_i, item)
					lab.Text = item
				end,
			})
			break
		end
	end

	-- 11) 바닥 · 구석 소품: 빗자루 · 쓰레받기 ------------------------------------------------------------------
	local bp = wcf(V, "left", -(V.z0 + 3.2), 0, 0.35)
	if K:spot(bp, V3(1.0, 4.6, 0.6), 0.05) then
		K:seg("BroomStick", (bp * CF(0, 0.6, 0.05)).Position, (bp * CF(0, 4.5, -0.25)).Position, 0.08, lk(rgb(200, 60, 80)))
		K:box("BroomHead", V3(0.9, 0.5, 0.18), bp * CF(0, 0.45, 0.08) * ANG(-0.08, 0, 0), lk(rgb(40, 40, 44)))
		K:box("BroomBristle", V3(0.85, 0.3, 0.14), bp * CF(0, 0.15, 0.1), lk(rgb(90, 90, 96), M.Fabric))
		K:box("Dustpan", V3(0.8, 0.06, 0.6), bp * CF(0.6, 0.06, 0.15), lk(rgb(200, 60, 80)))
	end
	local _ = W
	local _2 = H
end

--================================================================================================
-- 옷가게 (clothing)
--================================================================================================
local SKIN = { c = rgb(244, 242, 238), m = M.SmoothPlastic, r = 0.08 }
local WOOD_HANGER = lk(rgb(176, 136, 96), M.Wood)

-- 색 팔레트 (비치웨어 편집숍): 화이트 · 크림 · 샌드 · 스카이 · 네이비 · 올리브 · 테라코타 · 블랙
local CLOTH = {
	rgb(246, 244, 238), rgb(232, 222, 202), rgb(206, 186, 150), rgb(150, 190, 220), rgb(44, 58, 92),
	rgb(110, 120, 80), rgb(190, 100, 70), rgb(30, 30, 32), rgb(226, 170, 170), rgb(96, 140, 160),
	rgb(240, 214, 120), rgb(170, 170, 172),
}

-- 옷걸이에 건 옷 하나 (옆으로 건 것: 폭 = xdir, 두께 = 레일 방향). hook = 레일 윗면 점 (매장 프레임)
local function garment(K: any, hook: Vector3, xdir: Vector3, kind: string, c: Color3, o: any?)
	local op: any = o or {}
	local g = CFrame.fromMatrix(hook, xdir, Vector3.yAxis, xdir:Cross(Vector3.yAxis)) * ANG(0, 0, op.tilt or 0)
	local fab = lk(c, M.Fabric)
	local dark = lk(dk(c, 0.18), M.Fabric)
	local t = op.t or 0.2
	-- 고리 + 나무 옷걸이 (어깨 경사 2)
	local low = lowD(K)
	K:seg("HangerHook", (g * CF(0, 0.12, 0)).Position, (g * CF(0, -0.18, 0)).Position, 0.035, Look.chrome)
	if low then
		K:box("Hanger", V3(1.8, 0.07, 0.06), g * CF(0, -0.3, 0), WOOD_HANGER)
	else
		K:bar("Hanger", (g * CF(0, -0.18, 0)).Position, (g * CF(-0.92, -0.42, 0)).Position, 0.08, 0.06, WOOD_HANGER)
		K:bar("Hanger", (g * CF(0, -0.18, 0)).Position, (g * CF(0.92, -0.42, 0)).Position, 0.08, 0.06, WOOD_HANGER)
	end
	if kind == "tee" or kind == "knit" or kind == "hoodie" then
		local h = if kind == "tee" then 2.15 else 2.35
		K:box("GarmentBody", V3(1.75, h, t), g * CF(0, -0.32 - h / 2, 0), fab)
		if not low then
			K:wedge("GarmentShoulder", V3(t, 0.22, 0.9), g * CF(-0.45, -0.25, 0) * ANG(0, PI / 2, 0), fab)
			K:wedge("GarmentShoulder", V3(t, 0.22, 0.9), g * CF(0.45, -0.25, 0) * ANG(0, -PI / 2, 0), fab)
		end
		local sl = if kind == "tee" then 0.75 else 1.9
		for _, sx in { -1, 1 } do
			K:box("GarmentSleeve", V3(0.36, sl, t * 0.9), g * CF(sx * 0.98, -0.48 - sl / 2, 0) * ANG(0, 0, sx * 0.12), fab)
		end
		if kind == "knit" then
			K:box("GarmentRib", V3(1.76, 0.22, t + 0.01), g * CF(0, -0.32 - h + 0.11, 0), dark)
		elseif kind == "hoodie" then
			K:ell("GarmentHood", V3(0.9, 0.5, t + 0.05), g * CF(0, -0.38, 0), dark)
			K:box("GarmentPocket", V3(0.9, 0.45, t + 0.02), g * CF(0, -0.32 - h + 0.6, 0), dark)
		end
	elseif kind == "shirt" or kind == "jacket" then
		local h = if kind == "shirt" then 2.55 else 2.6
		local tt = if kind == "jacket" then t * 1.8 else t
		K:box("GarmentBody", V3(1.8, h, tt), g * CF(0, -0.32 - h / 2, 0), fab)
		K:box("GarmentCollar", V3(0.7, 0.18, tt + 0.03), g * CF(0, -0.36, 0), dark)
		for _, sx in { -1, 1 } do
			K:box("GarmentSleeve", V3(0.34, h * 0.85, tt * 0.9), g * CF(sx * 1.0, -0.45 - h * 0.42, 0) * ANG(0, 0, sx * 0.05), fab)
		end
		if kind == "jacket" and not lowD(K) then
			K:box("GarmentLapel", V3(0.08, h * 0.5, tt + 0.03), g * CF(-0.15, -0.5 - h * 0.25, 0), dark)
		end
	elseif kind == "dress" then
		K:box("GarmentBodice", V3(1.3, 1.3, t), g * CF(0, -0.32 - 0.65, 0), fab)
		K:box("GarmentSkirt", V3(1.85, 2.0, t), g * CF(0, -0.32 - 1.3 - 1.0, 0), fab)
		K:box("GarmentStrap", V3(0.12, 0.3, t), g * CF(-0.4, -0.25, 0), fab)
		K:box("GarmentStrap", V3(0.12, 0.3, t), g * CF(0.4, -0.25, 0), fab)
		K:box("GarmentWaist", V3(1.32, 0.12, t + 0.02), g * CF(0, -1.62, 0), dark)
	else -- pants / shorts (클립 옷걸이)
		local h = if kind == "shorts" then 1.3 else 2.6
		K:box("GarmentWaistband", V3(1.4, 0.2, t + 0.02), g * CF(0, -0.55, 0), dark)
		for _, sx in { -1, 1 } do
			K:box("GarmentLeg", V3(0.66, h, t), g * CF(sx * 0.36, -0.65 - h / 2, 0), fab)
		end
	end
	if op.tag and not lowD(K) then
		K:box("PriceTag", V3(0.2, 0.3, 0.02), g * CF(0.75, -0.75, t / 2 + 0.015), lk(rgb(250, 248, 240)))
	end
end

-- 레일 따라 옷 걸기: a..b (레일 윗면 점들), xdir = 옷 폭 방향. 색 묶음 (같은 색 2~4벌씩)
local function hangRow(K: any, a: Vector3, b: Vector3, xdir: Vector3, pitch: number, kinds: { string }, seed: number, palette: { Color3 }?)
	local pal = palette or CLOTH
	local len = (b - a).Magnitude
	local n = math.floor(len / pitch)
	local ci = math.floor(rnd(seed, 1) * #pal)
	local run = 0
	local kind = kinds[1]
	for i = 0, n - 1 do
		if run <= 0 then
			ci = (ci + 1 + math.floor(rnd(seed, i + 5) * 3)) % #pal
			run = 2 + math.floor(rnd(seed, i + 9) * 3)
			kind = kinds[math.floor(rnd(seed, i + 13) * #kinds) + 1]
		end
		run -= 1
		local p = a:Lerp(b, (i + 0.5) / n)
		local c = pal[ci + 1]
		if rnd(seed, i + 31) > 0.7 then
			c = dk(c, 0.08)
		end
		garment(K, p, xdir, kind, c, { tilt = (rnd(seed, i + 40) - 0.5) * 0.06, tag = i % 4 == 0, t = 0.16 + rnd(seed, i + 50) * 0.08 })
	end
end

-- 사이즈 구분 링 (레일에 끼움)
local function sizeDivider(K: any, p: Vector3, xdir: Vector3, s: string)
	local g = CFrame.fromMatrix(p, xdir, Vector3.yAxis, xdir:Cross(Vector3.yAxis))
	K:disc("SizeDivider", 0.7, 0.03, g * CF(0, -0.3, 0) * ANG(PI / 2, 0, 0), lk(rgb(250, 250, 248)))
	txt(K, "SizeDividerText", 0.4, 0.3, g * CF(0, -0.3, 0.02), s, rgb(30, 30, 30), nil, F.GothamBlack)
end

-- 개어 쌓은 옷 더미 (pcf = 놓는 면, +Z = 접힌 앞쪽)
local function foldedStack(K: any, pcf: CFrame, w: number, d: number, n: number, c: Color3, seed: number, print: Color3?)
	for i = 1, n do
		local y = (i - 0.5) * 0.14
		local cc = if i % 3 == 0 then dk(c, 0.06) else c
		K:box("FoldedItem", V3(w, 0.13, d), pcf * CF((rnd(seed, i) - 0.5) * 0.06, y, (rnd(seed, i + 7) - 0.5) * 0.05), lk(cc, M.Fabric))
	end
	if print and not lowD(K) then
		K:box("FoldedPrint", V3(w * 0.22, 0.01, d * 0.16), pcf * CF(0, n * 0.14 + 0.005, d * 0.22), lk(print))
	end
end

-- 마네킹 (흰 FRP, 추상 얼굴). pcf = 받침 아래 가운데 (+Z = 보는 쪽), y0 = 받침 윗면 높이, outfit, sc = 크기 배율
-- (기본 키 6.5 스터드 -> sc 0.85 면 사람 키(5.2)보다 조금 큰 5.5)
-- 마네킹 (패션 마네킹: 달걀 머리 · 캡슐 어깨 · 가는 허리 · 크롬 받침). pcf +Z = 정면, y0 = 받침 윗면.
-- 옷 파트 이름: "ManqT_*" = 상의 색, "ManqB_*" = 하의 색 (코디 바꾸기가 이름 앞머리로 색만 바꿈)
local function mannequin(K: any, pcf: CFrame, y0: number, outfit: any, sc: number?)
	local s = sc or 0.85
	local top = lk(outfit.top, M.Fabric)
	local topD = lk(dk(outfit.top, 0.12), M.Fabric)
	local bot = lk(outfit.bottom or outfit.top, M.Fabric)
	local b0 = pcf * CF(0, y0, 0)
	local b = b0 * CF(0, 0.06, 0) -- 발이 받침 원판 위에 서게
	local function P(x: number, y: number, z: number): CFrame
		return b * CF(x * s, y * s, z * s)
	end
	local function S3(x: number, y: number, z: number): Vector3
		return V3(x * s, y * s, z * s)
	end
	local kind = outfit.topKind
	local bk = outfit.bottomKind
	local dress = bk == "dress"
	-- 받침: 크롬 원판 + 종아리로 들어가는 봉
	K:disc("ManqBase", 1.25 * s, 0.06, b0 * CF(0, 0.03, 0), Look.chrome)
	K:disc("ManqBaseRim", 1.3 * s, 0.02, b0 * CF(0, 0.01, 0), lk(rgb(30, 30, 32)))
	K:seg("ManqRod", (b0 * CF(0.2 * s, 0.05, -0.05 * s)).Position, P(0.2, 1.2, -0.05).Position, 0.07, Look.chrome)
	-- 다리 (허벅지 · 종아리 · 발)
	for _, sx in { -1, 1 } do
		local hip = P(sx * 0.22, 3.25, 0).Position
		local knee = P(sx * 0.2, 1.85, 0.03).Position
		local ankle = P(sx * 0.17, 0.32, 0).Position
		local thighL = if bk == "pants" or bk == "shorts" then bot else SKIN
		local shinL = if bk == "pants" then bot else SKIN
		K:seg(if thighL == SKIN then "ManqSkinThigh" else "ManqB_Thigh", hip, knee, (if bk == "pants" then 0.48 else 0.42) * s, thighL)
		K:seg(if shinL == SKIN then "ManqSkinShin" else "ManqB_Shin", knee, ankle, (if bk == "pants" then 0.4 else 0.3) * s, shinL)
		K:ball(if shinL == SKIN then "ManqSkinKnee" else "ManqB_Knee", (if bk == "pants" then 0.46 else 0.34) * s, P(sx * 0.2, 1.85, 0.03), shinL)
		if bk == "shorts" then
			K:seg("ManqB_ShortsLeg", hip, P(sx * 0.215, 2.55, 0.01).Position, 0.54 * s, bot)
			K:seg("ManqB_ShortsCuff", P(sx * 0.215, 2.62, 0.01).Position, P(sx * 0.215, 2.5, 0.01).Position, 0.56 * s, lk(dk(outfit.bottom or outfit.top, 0.12), M.Fabric))
		elseif bk == "pants" then
			K:seg("ManqB_Hem", P(sx * 0.17, 0.5, 0).Position, P(sx * 0.17, 0.34, 0).Position, 0.44 * s, lk(dk(outfit.bottom or outfit.top, 0.1), M.Fabric))
		end
		-- 신발 (스니커즈 / 샌들)
		local shoeC = outfit.shoe or (if bk == "pants" then rgb(246, 244, 240) else rgb(196, 160, 120))
		K:ell("ManqShoe", S3(0.3, 0.2, 0.62), P(sx * 0.17, 0.12, 0.12), lk(shoeC))
		K:box("ManqShoeSole", S3(0.3, 0.05, 0.6), P(sx * 0.17, 0.03, 0.12), lk(rgb(236, 232, 224)))
	end
	-- 골반 · 허리 · 가슴 (하의 · 상의)
	K:ell(if dress then "ManqT_Hips" else "ManqB_Hips", S3(0.92, 0.62, 0.58), P(0, 3.35, 0), if dress then top else bot)
	if bk ~= "dress" then
		K:vcyl("ManqB_Waistband", 0.14 * s, 0.8 * s, P(0, 3.62, 0), lk(dk(outfit.bottom or outfit.top, 0.15), M.Fabric))
	end
	K:ell("ManqT_Waist", S3(0.78, 1.05, 0.5), P(0, 3.92, 0), top)
	K:ell("ManqT_Chest", S3(1.0, 1.15, 0.6), P(0, 4.45, 0), top)
	K:seg("ManqT_Shoulder", P(-0.5, 4.93, 0).Position, P(0.5, 4.93, 0).Position, 0.36 * s, top)
	for _, sx in { -1, 1 } do
		K:ball("ManqT_ShoulderCap", 0.37 * s, P(sx * 0.52, 4.92, 0), top)
	end
	-- 스커트 · 원피스 치마 (층층 원판 = 티어드)
	if bk == "skirt" or dress then
		-- A 라인: 얇은 원판 여러 장이 아래로 갈수록 넓어짐 (같은 색) + 밑단 띠
		local tiers = if dress then 6 else 4
		local yTop = if dress then 3.55 else 3.6
		local hgt = 0.27
		local name = if dress then "ManqT_Skirt" else "ManqB_Skirt"
		local look = if dress then top else bot
		for k = 1, tiers do
			K:vcyl(name, hgt * s + 0.01, (0.84 + k * 0.075) * s, P(0, yTop - (k - 0.5) * hgt, 0), look)
		end
		K:vcyl(if dress then "ManqT_Hem" else "ManqB_Hem", 0.06 * s, (0.86 + tiers * 0.075) * s, P(0, yTop - tiers * hgt + 0.03, 0), if dress then topD else lk(dk(outfit.bottom or outfit.top, 0.15), M.Fabric))
	end
	-- 상의 디테일
	if kind == "jacket" then
		K:box("ManqJacketFront", S3(0.06, 1.5, 0.03), P(-0.1, 4.25, 0.3), lk(dk(outfit.top, 0.3), M.Fabric))
		K:box("ManqInner", S3(0.26, 1.2, 0.03), P(0.06, 4.45, 0.295), lk(outfit.inner or rgb(246, 244, 238), M.Fabric))
		for _, sx in { -1, 1 } do
			K:box("ManqT_Lapel", S3(0.14, 0.6, 0.04), P(sx * 0.17, 4.7, 0.3) * ANG(0, 0, sx * 0.35), topD)
			K:box("ManqT_Pocket", S3(0.3, 0.05, 0.04), P(sx * 0.3, 3.9, 0.25), topD)
		end
	elseif kind == "shirt" then
		for _, sx in { -1, 1 } do
			K:box("ManqT_Collar", S3(0.22, 0.12, 0.08), P(sx * 0.1, 5.12, 0.18) * ANG(0, 0, sx * 0.5), topD)
		end
		for k = 0, 3 do
			K:ball("ManqButton", 0.05 * s, P(0, 4.85 - k * 0.3, 0.3 - (k == 3 and 0.04 or 0)), lk(rgb(240, 238, 232)))
		end
	elseif kind == "knit" then
		K:vcyl("ManqT_Ribbing", 0.14 * s, 0.82 * s, P(0, 3.62, 0), topD)
		K:vcyl("ManqT_Neckline", 0.1 * s, 0.34 * s, P(0, 5.1, 0), topD)
	else
		K:vcyl("ManqT_Neckline", 0.06 * s, 0.32 * s, P(0, 5.08, 0.01), topD)
	end
	-- 목 · 머리 (달걀형)
	K:vcyl("ManqNeck", 0.42 * s, 0.24 * s, P(0, 5.25, 0), SKIN)
	K:ell("ManqHead", S3(0.58, 0.8, 0.66), P(0, 5.82, 0.03), SKIN)
	-- 팔 (어깨 캡슐 끝에서 시작, 살짝 굽힘). 반팔 = 소매 통 + 맨팔
	local longSleeve = kind == "shirt" or kind == "jacket" or kind == "knit"
	for _, sx in { -1, 1 } do
		local sh = P(sx * 0.62, 4.9, 0).Position
		local el = P(sx * 0.7, 3.88, 0.04).Position
		local wr = P(sx * 0.72, 3.0, 0.2).Position
		if dress and kind == "dress" then
			K:seg("ManqSkinUpperArm", sh, el, 0.25 * s, SKIN)
		elseif longSleeve then
			K:seg("ManqT_UpperArm", sh, el, 0.3 * s, top)
		else
			K:seg("ManqT_Sleeve", sh, sh:Lerp(el, 0.45), 0.36 * s, top)
			K:seg("ManqSkinUpperArm", sh:Lerp(el, 0.3), el, 0.24 * s, SKIN)
		end
		K:ball(if longSleeve then "ManqT_Elbow" else "ManqSkinElbow", (if longSleeve then 0.3 else 0.22) * s, CF(el), if longSleeve then top else SKIN)
		K:seg(if longSleeve then "ManqT_Forearm" else "ManqSkinForearm", el, wr, (if longSleeve then 0.27 else 0.21) * s, if longSleeve then top else SKIN)
		if longSleeve then
			K:seg("ManqT_Cuff", wr + (el - wr).Unit * 0.12, wr, 0.29 * s, topD)
		end
		K:ell("ManqHand", S3(0.14, 0.36, 0.24), pcf.Rotation + wr + V3(0, -0.18 * s, 0), SKIN)
	end
	-- 소품: 밀짚모자 · 토트백 · 선글라스
	if outfit.hat then
		K:disc("ManqHatBrim", 1.25 * s, 0.04, P(0, 6.12, 0.03), lk(outfit.hat, M.Fabric))
		K:vcyl("ManqHatCrown", 0.34 * s, 0.66 * s, P(0, 6.3, 0.03), lk(outfit.hat, M.Fabric))
		K:vcyl("ManqHatBand", 0.08, 0.68 * s, P(0, 6.17, 0.03), lk(rgb(40, 40, 44), M.Fabric))
	end
	if outfit.bag then
		local wr = P(-0.74, 3.0, 0.2)
		K:box("ManqBag", S3(0.22, 0.8, 0.95), wr * CF(-0.1 * s, -0.7 * s, 0), lk(outfit.bag, M.Fabric))
		K:box("ManqBagTrim", S3(0.24, 0.08, 0.97), wr * CF(-0.1 * s, -0.36 * s, 0), lk(dk(outfit.bag, 0.25), M.Fabric))
		K:seg("ManqBagStrap", (wr * CF(-0.1 * s, -0.3 * s, -0.3 * s)).Position, (wr * CF(0, 0.12 * s, 0)).Position, 0.05, lk(dk(outfit.bag, 0.3), M.Fabric))
		K:seg("ManqBagStrap", (wr * CF(-0.1 * s, -0.3 * s, 0.3 * s)).Position, (wr * CF(0, 0.12 * s, 0)).Position, 0.05, lk(dk(outfit.bag, 0.3), M.Fabric))
	end
	if outfit.shades then
		K:box("ManqShades", S3(0.56, 0.12, 0.05), P(0, 5.88, 0.36), lk(rgb(20, 20, 22), M.Glass, { r = 0.3 }))
		K:box("ManqShadesBridge", S3(0.6, 0.03, 0.03), P(0, 5.93, 0.37), lk(rgb(190, 156, 96), M.Metal))
	end
end

local OUTFITS = {
	{ top = rgb(246, 244, 238), topKind = "shirt", bottom = rgb(206, 186, 150), bottomKind = "shorts", hat = rgb(222, 196, 140) },
	{ top = rgb(150, 190, 220), topKind = "dress", bottomKind = "dress", hat = rgb(232, 210, 160), bag = rgb(214, 186, 140) },
	{ top = rgb(44, 58, 92), topKind = "knit", bottom = rgb(232, 222, 202), bottomKind = "pants", shades = true },
	{ top = rgb(110, 120, 80), topKind = "jacket", bottom = rgb(30, 30, 32), bottomKind = "pants", inner = rgb(246, 244, 238) },
	{ top = rgb(226, 170, 170), topKind = "tee", bottom = rgb(246, 244, 238), bottomKind = "skirt", bag = rgb(190, 100, 70) },
	{ top = rgb(240, 214, 120), topKind = "tee", bottom = rgb(96, 140, 160), bottomKind = "shorts", shades = true },
}

-- 신발 한 짝 (pcf = 놓는 면, +Z = 앞코)
local function shoe(K: any, pcf: CFrame, c: Color3, kind: string)
	if kind == "sandal" then
		K:box("ShoeSole", V3(0.42, 0.08, 1.05), pcf * CF(0, 0.04, 0), lk(rgb(200, 170, 120), M.Rubber))
		K:box("ShoeStrap", V3(0.44, 0.1, 0.12), pcf * CF(0, 0.12, 0.2), lk(c, M.Leather))
		K:box("ShoeStrap", V3(0.44, 0.1, 0.12), pcf * CF(0, 0.12, -0.2), lk(c, M.Leather))
	else
		K:box("ShoeSole", V3(0.44, 0.1, 1.1), pcf * CF(0, 0.05, 0), lk(rgb(246, 244, 240), M.Rubber))
		K:ell("ShoeUpper", V3(0.42, 0.42, 1.0), pcf * CF(0, 0.2, -0.02), lk(c, M.Leather))
		K:box("ShoeCollar", V3(0.38, 0.12, 0.3), pcf * CF(0, 0.38, -0.3), lk(dk(c, 0.3), M.Fabric))
	end
end

-- 모자 (pcf = 바라보는 쪽 +Z, 원점 = 모자 아래 가운데). kind = "cap" | "bucket" | "straw"
local function hat(K: any, pcf: CFrame, c: Color3, kind: string)
	if kind == "cap" then
		K:ell("CapCrown", V3(0.7, 0.55, 0.72), pcf * CF(0, 0.12, 0), lk(c, M.Fabric))
		K:box("CapBrim", V3(0.6, 0.04, 0.4), pcf * CF(0, 0.02, 0.45) * ANG(-0.12, 0, 0), lk(dk(c, 0.1), M.Fabric))
	elseif kind == "bucket" then
		K:vcyl("BucketCrown", 0.36, 0.62, pcf * CF(0, 0.2, 0), lk(c, M.Fabric))
		K:disc("BucketBrim", 0.92, 0.04, pcf * CF(0, 0.03, 0), lk(dk(c, 0.08), M.Fabric))
	else
		K:vcyl("StrawCrown", 0.32, 0.6, pcf * CF(0, 0.18, 0), lk(c, M.Fabric))
		K:disc("StrawBrim", 1.25, 0.03, pcf * CF(0, 0.03, 0), lk(c, M.Fabric))
		K:vcyl("StrawBand", 0.07, 0.62, pcf * CF(0, 0.07, 0), lk(rgb(40, 40, 44), M.Fabric))
	end
end

-- 바닥 소품 자리 찾기 + 예약 (pcf 후보 목록 중 첫 번째)
local function firstSpot(K: any, cands: { CFrame }, size: Vector3, pad: number?): CFrame?
	for _, c in cands do
		if K:spot(c, size, pad or 0.1) then
			return c
		end
	end
	return nil
end

-- 벽 패널 (프롬프트용) 자리 찾기: walls 순서대로, prefs (u 후보) 마다 Common.wallSpot 으로 찾고 promptOK 확인
local function findPanel(K: any, V: any, walls: { string }, w: number, y0: number, y1: number, prefs: { number }, reject: ((Vector3) -> boolean)?): CFrame?
	for _, wn in walls do
		for _, pu in prefs do
			-- wallSpot 은 찾은 자리를 기록하므로, 거절되면 그 기록을 되돌림
			local nUsed = if K.wallUsed then #K.wallUsed else 0
			local w2, d2 = Common.wallSpot(K, { wn }, w, y0, y1, pu)
			if w2 and d2 then
				if promptOK(K, V, d2.Position) and not (reject and reject(d2.Position)) then
					return d2
				end
				while K.wallUsed and #K.wallUsed > nUsed do
					table.remove(K.wallUsed)
				end
			end
		end
	end
	return nil
end

-- BGM 패널 (매장 음악 순환): dcf 에 만들고 cycle 프롬프트
local function bgmPanel(K: any, d: CFrame, songs: { string }, label: string, accent: Color3)
	local plate = K:plate("BGMPanel", 1.2, 0.95, 0.06, d, lk(rgb(30, 30, 32)))
	K:plate("BGMScreen", 1.04, 0.42, 0.02, d * CF(0, 0.16, 0.06), lk(rgb(20, 30, 40), M.Neon))
	local _, lab = txt(K, "BGMText", 1.0, 0.36, d * CF(0, 0.16, 0.085), songs[1], accent, nil, F.GothamMedium, 1.4)
	txt(K, "BGMLabel", 1.0, 0.16, d * CF(0, -0.18, 0.07), label, rgb(200, 200, 200), nil, F.GothamMedium)
	for j = 0, 2 do
		wdisc(K, "BGMButton", 0.16, 0.03, d * CF(-0.3 + j * 0.3, -0.36, 0.06), lk(rgb(200, 200, 204)))
	end
	Interact.cycle(K, plate, songs, {
		object = "매장 음악",
		action = "다음 곡",
		on = function(_i, item)
			lab.Text = item
		end,
	})
	return plate
end

local function buildClothing(K: any, V: any, S: any)
	pcall(windowSignBacks, K, V)
	pcall(twoSidedSigns, K, V)
	local seed = hashStr(V.key or V.name or "clothing")
	local brass = lk(rgb(190, 156, 96), M.Metal, { r = 0.12 })
	local oak = lk(rgb(204, 170, 128), M.Wood)
	local black = Look.blackMetal

	-- 0) 우리 다운라이트 (맵 조명이 어두운 가운데 통로)
	for _, pz in { { -3.2, V.z1 - 7 }, { 3.2, (V.z0 + V.z1) / 2 + 2 }, { -3.2, V.z0 + 12 }, { V.x1 - 4.5, V.z0 + 6 } } do
		litDownlight(K, pz[1], pz[2])
	end
	-- 벽 진열 (레일 · 큐비) 을 비추는 중성광 월워셔 2 (옷 색이 살게)
	litDownlight(K, V.x0 + 2.6, (V.z0 + V.z1) / 2 + 3, Look.neutralLight, 16)
	litDownlight(K, V.x1 - 2.6, (V.z0 + V.z1) / 2 + 6, Look.neutralLight, 16)

	-- 1) 벽 레일 + 옷 (맵 Rail 자리) --------------------------------------------------------------------
	for _, rail in recs(V, "Rail") do
		local alongZ = rail.size.Z > rail.size.X
		local a = if alongZ then V3(rail.c.X, rail.max.Y, rail.min.Z + 0.3) else V3(rail.min.X + 0.3, rail.max.Y, rail.c.Z)
		local b = if alongZ then V3(rail.c.X, rail.max.Y, rail.max.Z - 0.3) else V3(rail.max.X - 0.3, rail.max.Y, rail.c.Z)
		local wall = nearestWall(V, rail.c)
		local xdir = if alongZ then V3(1, 0, 0) else V3(0, 0, 1)
		K:free(function()
			-- 레일 뒤 벽 패널 (따뜻한 베이지 + 세로 홈)
			local ua = V:wallCoord(wall, a)
			local ub = V:wallCoord(wall, b)
			local um, ul = (ua + ub) / 2, math.abs(ub - ua) + 1.2
			local bd = wcf(V, wall, um, 0.45 + (7.25 - 0.45) / 2, 0.01)
			K:plate("RailBackdrop", ul, 7.25 - 0.45, 0.03, bd, lk(rgb(170, 184, 164)))
			K:plate("RailBackdropTrim", ul + 0.1, 0.08, 0.06, bd * CF(0, -(7.25 - 0.45) / 2, 0), lk(rgb(190, 156, 96), M.Metal))
			for i = 1, math.floor(ul / 1.6) do
				K:plate("RailBackdropGroove", 0.05, 7.25 - 0.45, 0.035, bd * CF(-ul / 2 + i * 1.6, 0, 0), lk(rgb(150, 164, 144)))
			end
			K:cyl("RailNew", rail.size.Z + rail.size.X, 0.14, CF(rail.c) * (if alongZ then ANG(0, PI / 2, 0) else CFrame.new()), brass)
			-- 벽 브래킷 (5 스터드마다)
			local len = (b - a).Magnitude + 0.6
			local nb = math.max(2, math.floor(len / 5) + 1)
			for i = 0, nb - 1 do
				local p = a:Lerp(b, i / (nb - 1)) - V3(0, 0.06, 0)
				local u = V:wallCoord(wall, p)
				local wp = wcf(V, wall, u, p.Y, 0).Position
				K:bar("RailArm", wp, p, 0.08, 0.08, brass)
				wdisc(K, "RailRose", 0.3, 0.04, wcf(V, wall, u, p.Y, 0), brass)
			end
			hangRow(K, a, b, xdir, 0.5, { "tee", "shirt", "dress", "knit", "shirt", "tee", "pants" }, seed)
			-- 사이즈 구분 링 3
			for i, s in { "S", "M", "L" } do
				sizeDivider(K, a:Lerp(b, i / 4), xdir, s)
			end
		end)
		hideRec(K, rail)
	end
	hideWhere(K, V, setOf({ "RailBracket" }))
	for _, r in recs(V, "Garment") do
		hideRec(K, r)
	end
	-- 레일 위 선반 (TopShelf) + 접은 옷 · 바구니 · 라탄백
	for _, sh in recs(V, "TopShelf") do
		local wall = nearestWall(V, sh.c)
		local u = V:wallCoord(wall, sh.c)
		local len = math.max(sh.size.X, sh.size.Z)
		local dep = math.min(sh.size.X, sh.size.Z)
		K:free(function()
			local at = Props.shelf(K, wcf(V, wall, u, sh.min.Y + sh.size.Y / 2, 0), len, { depth = dep, look = oak, bracket = black, thick = sh.size.Y })
			local n = math.floor(len / 1.6)
			for i = 1, n do
				local x = -len / 2 + (i - 0.5) * len / n
				local k = (i + seed) % 5
				if k == 2 then
					K:box("RattanBag", V3(1.0, 0.85, 0.5), at * CF(x, 0.425, -0.3), lk(rgb(196, 160, 104), M.Fabric))
					K:seg("RattanHandle", (at * CF(x - 0.3, 0.85, -0.3)).Position, (at * CF(x + 0.3, 0.85, -0.3)).Position, 0.06, lk(rgb(150, 110, 70), M.Wood))
				elseif k == 4 then
					K:box("StorageBasket", V3(1.2, 0.6, 0.9), at * CF(x, 0.3, -0.4), lk(rgb(214, 200, 176), M.Fabric))
				else
					foldedStack(K, at * CF(x, 0, -0.5), 1.1, 0.85, 4, CLOTH[(i * 3 + seed) % #CLOTH + 1], seed + i)
				end
			end
		end)
		hideRec(K, sh)
	end
	for _, r in recs(V, "FoldedStack") do
		if r.c.Y > 6 then
			hideRec(K, r)
		end
	end

	-- 2) 오른쪽 벽 큐비 (FoldedTees) ---------------------------------------------------------------------
	local cback = V:first("CubbyBack")
	if cback then
		local sides, shelves = recs(V, "CubbySide"), recs(V, "CubbyShelf")
		local mn, mx = cback.min, cback.max
		for _, r in sides do
			mn, mx = mn:Min(r.min), mx:Max(r.max)
		end
		for _, r in shelves do
			mn, mx = mn:Min(r.min), mx:Max(r.max)
		end
		local wall = nearestWall(V, cback.c)
		K:free(function()
			-- 맵의 CubbyBack 은 방 쪽 면에 붙어 칸을 가림 -> 등판은 벽 쪽으로
			local bx = if wall == "right" then V.x1 - 0.06 elseif wall == "left" then V.x0 + 0.06 else cback.c.X
			K:box("CubbyBackNew", V3(0.08, cback.size.Y, cback.size.Z), CF(bx, cback.c.Y, cback.c.Z), lk(rgb(236, 230, 220)))
			for _, r in sides do
				K:box("CubbySideNew", r.size + V3(0, 0, 0.04), CF(r.c), oak)
			end
			for _, r in shelves do
				K:box("CubbyShelfNew", r.size + V3(0, 0.04, 0), CF(r.c), oak)
				-- 앞 가장자리 브라스 띠
				local fx = if wall == "right" then r.min.X - 0.01 else r.max.X + 0.01
				if wall == "right" or wall == "left" then
					K:box("CubbyEdge", V3(0.03, 0.05, r.size.Z), CF(fx, r.max.Y - 0.03, r.c.Z), brass)
				end
			end
			-- 칸마다 접은 티 3 + 가격 클립
			table.sort(shelves, function(p, q)
				return p.c.Y < q.c.Y
			end)
			local zs = {}
			for _, r in sides do
				table.insert(zs, r.c.Z)
			end
			table.sort(zs)
			for si = 1, #shelves - 1 do
				local y = shelves[si].max.Y + 0.02
				for ci = 1, #zs - 1 do
					local zc = (zs[ci] + zs[ci + 1]) / 2
					local cw = zs[ci + 1] - zs[ci] - 0.3
					local c = CLOTH[((si * 7 + ci * 3 + seed) % #CLOTH) + 1]
					local x = (mn.X + mx.X) / 2 + (if wall == "right" then -0.1 else 0.1)
					local fdir = if wall == "right" then V3(-1, 0, 0) else V3(1, 0, 0)
					foldedStack(K, faceCF(V3(x, y, zc), fdir), cw * 0.8, 1.2, 4 + (si + ci) % 3, c, seed + si * 10 + ci, if (si + ci) % 4 == 0 then rgb(30, 60, 110) else nil)
					if not lowD(K) then
						local tx = if wall == "right" then shelves[si].min.X - 0.03 else shelves[si].max.X + 0.03
						txt(K, "CubbyTag", 0.75, 0.2, faceCF(V3(tx, shelves[si].max.Y - 0.12, zc), fdir), (({ "29,000", "35,000", "19,900", "39,000", "25,000" })[(si + ci) % 5 + 1]), rgb(30, 30, 30), rgb(250, 248, 240), F.GothamBold)
					end
				end
			end
			-- 위 조명 띠
			local lx = if wall == "right" then mn.X - 0.05 else mx.X + 0.05
			K:box("CubbyLED", V3(0.05, 0.04, mx.Z - mn.Z - 0.3), CF(lx, mx.Y - 0.12, (mn.Z + mx.Z) / 2), Look.lampWarm)
		end)
		hideRec(K, cback)
		for _, r in sides do
			hideRec(K, r)
		end
		for _, r in shelves do
			hideRec(K, r)
		end
		for _, r in recs(V, "FoldedTees") do
			hideRec(K, r)
		end
	end

	-- 3) 신발 선반 ---------------------------------------------------------------------------------------
	local shoeShelves = recs(V, "ShoeShelf")
	if #shoeShelves > 0 then
		table.sort(shoeShelves, function(p, q)
			return p.c.Y < q.c.Y
		end)
		for si, r in shoeShelves do
			local wall = nearestWall(V, r.c)
			local u = V:wallCoord(wall, r.c)
			local len = math.max(r.size.X, r.size.Z)
			local dep = math.min(r.size.X, r.size.Z)
			K:free(function()
				local at = Props.shelf(K, wcf(V, wall, u, r.c.Y, 0), len, { depth = dep, look = oak, bracket = black, thick = r.size.Y + 0.04 })
				K:box("ShoeShelfLED", V3(len - 0.3, 0.03, 0.04), wcf(V, wall, u, r.min.Y - 0.03, dep - 0.15), Look.lampWarm)
				local kinds = if si == #shoeShelves then { "sandal", "sandal", "sandal" } else { "sneaker", "sneaker", "sandal" }
				local cols = { rgb(246, 244, 240), rgb(30, 30, 32), rgb(206, 186, 150), rgb(150, 190, 220), rgb(190, 100, 70) }
				for j = 1, 3 do
					local x = -len / 2 + (j - 0.5) * len / 3
					local k = kinds[(j + si) % 3 + 1]
					local c = cols[(j * 2 + si + seed) % #cols + 1]
					shoe(K, at * CF(x - 0.27, 0, -0.1) * ANG(0, 0.12, 0), c, k)
					shoe(K, at * CF(x + 0.27, 0, -0.1) * ANG(0, -0.06, 0), c, k)
					if not lowD(K) then
						txt(K, "ShoeTag", 0.6, 0.16, at * CF(x, -0.12, 0.02), (({ "59,000", "39,000", "25,000", "69,000" })[(j + si) % 4 + 1]), rgb(40, 40, 40), rgb(250, 248, 242), F.GothamBold)
					end
				end
			end)
			hideRec(K, r)
		end
		for _, r in recs(V, "Shoes") do
			hideRec(K, r)
		end
	end

	-- 4) 액세서리 벽 (Pegboard 자리): 슬랫월 + 캡 · 버킷햇 · 선글라스 · 토트백 ---------------------------------------
	local peg = V:first("Pegboard")
	if peg then
		local wall = nearestWall(V, peg.c)
		local u = V:wallCoord(wall, peg.c)
		local pw = math.max(peg.size.X, peg.size.Z) + 0.6
		local ph = peg.size.Y
		local yc = peg.c.Y
		K:free(function()
			local d = wcf(V, wall, u, yc, 0.01)
			K:plate("SlatWall", pw, ph, 0.06, d, lk(rgb(226, 214, 196), M.Wood))
			for i = 1, math.floor(ph / 0.5) do
				K:plate("SlatGroove", pw, 0.04, 0.065, d * CF(0, -ph / 2 + i * 0.5, 0), lk(rgb(150, 136, 118)))
			end
			-- 위 2줄: 캡 · 버킷햇 (후크 + 모자)
			local hc = { rgb(30, 30, 32), rgb(232, 222, 202), rgb(44, 58, 92), rgb(110, 120, 80), rgb(226, 170, 170), rgb(246, 244, 238) }
			for row = 0, 1 do
				for col = 0, 2 do
					local x = -pw / 2 + 0.7 + col * (pw - 1.4) / 2
					local y = ph / 2 - 0.65 - row * 1.35
					K:bar("PegHook", (d * CF(x, y, 0.06)).Position, (d * CF(x, y + 0.08, 0.5)).Position, 0.05, 0.05, Look.chrome)
					local kind = if row == 0 then "cap" else "bucket"
					hat(K, d * CF(x, y - 0.25, 0.42) * ANG(-PI / 2 + 0.25, 0, 0) * ANG(PI / 2, 0, 0) * CF(0, 0, 0), hc[(row * 3 + col + seed) % #hc + 1], kind)
				end
			end
			-- 아래: 선글라스 진열대 (아크릴 6) + 작은 거울
			local gy = -ph / 2 + 0.75
			K:plate("ShadesRack", pw * 0.55, 0.9, 0.08, d * CF(-pw * 0.18, gy, 0.06), Look.acrylicWhite)
			for i = 0, 5 do
				local gx = -pw * 0.18 - pw * 0.22 + (i % 3) * pw * 0.22
				local gyy = gy + 0.2 - (i // 3) * 0.42
				K:box("Shades", V3(0.6, 0.16, 0.05), d * CF(gx, gyy, 0.18), lk(({ rgb(20, 20, 22), rgb(110, 70, 40), rgb(40, 60, 90) })[i % 3 + 1], M.Glass, { r = 0.3 }))
				K:box("ShadesBridge", V3(0.66, 0.03, 0.03), d * CF(gx, gyy + 0.08, 0.2), lk(rgb(30, 30, 30), M.Metal))
			end
			K:panel("AccessoryMirror", 0.9, 1.3, 0.04, 0.4, d * CF(pw * 0.32, gy + 0.3, 0.07), Look.mirror)
			txt(K, "AccessorySign", pw * 0.7, 0.36, d * CF(0, ph / 2 + 0.3, 0.06), "ACCESSORY · 모자 · 선글라스", rgb(40, 40, 44), nil, F.GothamBlack)
			useWall(K, wall, u - pw / 2, u + pw / 2, yc - ph / 2, yc + ph / 2 + 0.5)
		end)
		hideRec(K, peg)
		for _, r in recs(V, "Cap") do
			if nearXZ(r.c, peg.c) < 3 then
				hideRec(K, r)
			end
		end
		for _, r in recs(V, "Sunglasses") do
			if nearXZ(r.c, peg.c) < 3 then
				hideRec(K, r)
			end
		end
	end

	-- 5) 가운데 진열 테이블 (DisplayTable + DisplayBase) + 접은 옷 ----------------------------------------------
	for ti, t in recs(V, "DisplayTable") do
		local base = nil
		for _, r in recs(V, "DisplayBase") do
			if nearXZ(r.c, t.c) < 1 then
				base = r
			end
		end
		local p = V3(t.c.X, 0, t.c.Z)
		K:free(function()
			K:box("DisplayTop", t.size, CF(t.c), oak)
			K:box("DisplayTopEdge", V3(t.size.X + 0.02, 0.05, t.size.Z + 0.02), CF(t.c.X, t.min.Y + 0.02, t.c.Z), brass)
			if base then
				K:box("DisplayBody", base.size - V3(0, 0.25, 0), CF(base.c + V3(0, 0.125, 0)), lk(rgb(244, 242, 236)))
				K:box("DisplayPlinth", V3(base.size.X - 0.2, 0.25, base.size.Z - 0.2), CF(base.c.X, 0.125, base.c.Z), black)
				-- 아래 칸 (청바지 더미)
				K:box("DisplayNiche", V3(base.size.X - 0.6, 1.1, 0.04), CF(base.c.X, 1.0, base.max.Z + 0.005), lk(rgb(214, 206, 192)))
			end
			-- 윗면: 3x2 더미
			local cols = if ti % 2 == 0 then { rgb(44, 58, 92), rgb(70, 96, 140), rgb(130, 160, 196) } else { rgb(246, 244, 238), rgb(232, 222, 202), rgb(150, 190, 220), rgb(226, 170, 170) }
			local k = 0
			for ix = -1, 1 do
				for iz = -1, 1, 2 do
					k += 1
					local c = cols[(k + seed) % #cols + 1]
					foldedStack(K, CF(p.X + ix * 1.5, t.max.Y, p.Z + iz * 0.72) * ANG(0, (rnd(seed, k) - 0.5) * 0.1, 0), 1.25, 1.0, 3 + (k % 3), c, seed + k * 11 + ti, if k % 3 == 0 then rgb(190, 100, 70) else nil)
				end
			end
			-- 가격 아크릴 (뒤쪽 가운데)
			K:box("PriceStandBase", V3(0.7, 0.05, 0.25), CF(p.X, t.max.Y + 0.025, t.min.Z + 0.25), Look.acrylicWhite)
			txt(K, "PriceStand", 0.66, 0.46, CF(p.X, t.max.Y + 0.3, t.min.Z + 0.25) * ANG(0, PI, 0), if ti % 2 == 0 then "데님 팬츠\n49,000" else "린넨 셔츠\n39,000", rgb(30, 30, 30), rgb(252, 250, 246), F.GothamBold)
		end)
		hideRec(K, t)
		if base then
			hideRec(K, base)
		end
		for _, r in recs(V, "FoldedStack") do
			if r.c.Y < 6 and nearXZ(r.c, t.c) < 3 then
				hideRec(K, r)
			end
		end
		K:reserve(V3(t.min.X - 0.3, 0, t.min.Z - 0.3), V3(t.max.X + 0.3, 4, t.max.Z + 0.3), "display")
	end

	-- 6) 세일 바구니 (나무 상자) + 양말 팩 --------------------------------------------------------------------
	local bin = V:first("SaleBin")
	if bin then
		local p = V3(bin.c.X, 0, bin.c.Z)
		local w, h, d = bin.size.X, bin.size.Y, bin.size.Z
		K:free(function()
			local crate = lk(rgb(196, 160, 112), M.WoodPlanks)
			for i = 0, 3 do
				local y = 0.3 + i * (h - 0.4) / 3.2
				K:box("CrateSlat", V3(w, (h - 0.4) / 4.2, 0.08), CF(p.X, y + 0.25, p.Z + d / 2 - 0.04), crate)
				K:box("CrateSlat", V3(w, (h - 0.4) / 4.2, 0.08), CF(p.X, y + 0.25, p.Z - d / 2 + 0.04), crate)
				K:box("CrateSlat", V3(0.08, (h - 0.4) / 4.2, d - 0.16), CF(p.X - w / 2 + 0.04, y + 0.25, p.Z), crate)
				K:box("CrateSlat", V3(0.08, (h - 0.4) / 4.2, d - 0.16), CF(p.X + w / 2 - 0.04, y + 0.25, p.Z), crate)
			end
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					K:box("CratePost", V3(0.16, h, 0.16), CF(p.X + sx * (w / 2 - 0.08), h / 2, p.Z + sz * (d / 2 - 0.08)), lk(rgb(150, 116, 80), M.Wood))
				end
			end
			K:box("CrateFill", V3(w - 0.2, 0.1, d - 0.2), CF(p.X, h - 0.35, p.Z), lk(rgb(232, 222, 202), M.Fabric))
			local sc = { rgb(226, 170, 170), rgb(150, 190, 220), rgb(240, 214, 120), rgb(246, 244, 238), rgb(110, 120, 80), rgb(44, 58, 92) }
			for i = 0, 8 do
				local x = -w / 2 + 0.45 + (i % 3) * (w - 0.9) / 2
				local z = -d / 2 + 0.45 + (i // 3) * (d - 0.9) / 2
				local cf2 = CF(p.X + x, h - 0.22 + (i % 2) * 0.06, p.Z + z) * ANG(0, rnd(seed, i) * 1.2 - 0.6, (rnd(seed, i + 3) - 0.5) * 0.3)
				K:box("SockPackNew", V3(0.75, 0.16, 0.5), cf2, lk(sc[(i + seed) % #sc + 1], M.Fabric))
				if not lowD(K) then
					K:box("SockBand", V3(0.2, 0.17, 0.52), cf2 * CF(0.15, 0, 0), lk(rgb(250, 250, 248)))
				end
			end
		end)
		hideRec(K, bin)
		for _, r in recs(V, "SockPack") do
			hideRec(K, r)
		end
		K:reserve(bin.min - V3(0.2, 0, 0.2), bin.max + V3(0.2, 0.5, 0.2), "bin")
	end

	-- 7) 독립 행거 (RackPost · RackBar) -------------------------------------------------------------------
	local bar = V:first("RackBar")
	if bar then
		local alongZ = bar.size.Z > bar.size.X
		local a = if alongZ then V3(bar.c.X, bar.max.Y, bar.min.Z + 0.2) else V3(bar.min.X + 0.2, bar.max.Y, bar.c.Z)
		local b = if alongZ then V3(bar.c.X, bar.max.Y, bar.max.Z - 0.2) else V3(bar.max.X - 0.2, bar.max.Y, bar.c.Z)
		local xdir = if alongZ then V3(1, 0, 0) else V3(0, 0, 1)
		K:free(function()
			local pipe = lk(rgb(36, 36, 38), M.Metal)
			K:seg("RackPipe", a - V3(0, 0.07, 0) - (b - a).Unit * 0.25, b - V3(0, 0.07, 0) + (b - a).Unit * 0.25, 0.14, pipe)
			for _, r in recs(V, "RackPost") do
				K:seg("RackUpright", V3(r.c.X, 0.15, r.c.Z), V3(r.c.X, bar.max.Y - 0.07, r.c.Z), 0.14, pipe)
				K:ball("RackElbow", 0.2, CF(r.c.X, bar.max.Y - 0.07, r.c.Z), pipe)
				K:seg("RackFootBar", V3(r.c.X, 0.08, r.c.Z) - xdir * 0.8, V3(r.c.X, 0.08, r.c.Z) + xdir * 0.8, 0.14, pipe)
				for _, s in { -1, 1 } do
					K:ball("RackCaster", 0.16, CF(V3(r.c.X, 0.08, r.c.Z) + xdir * s * 0.8), Look.rubber)
				end
			end
			-- 아래 나무 선반 + 박스
			local mid = (a + b) / 2
			local len = (b - a).Magnitude
			local rot = if alongZ then ANG(0, PI / 2, 0) else CFrame.new()
			K:box("RackPlank", V3(len, 0.12, 1.2), CF(mid.X, 0.7, mid.Z) * rot, oak)
			for i = 0, 2 do
				local p = a:Lerp(b, (i + 0.5) / 3)
				foldedStack(K, CF(p.X, 0.76, p.Z) * rot, 1.0, 0.9, 3, CLOTH[(i * 5 + seed) % #CLOTH + 1], seed + 70 + i)
			end
			hangRow(K, a, b, xdir, 0.55, { "jacket", "shirt", "knit" }, seed + 99)
			-- 끝 사인 (SALE 30%)
			txt(K, "RackEndSign", 1.2, 0.6, faceCF(b + (b - a).Unit * 0.45 + V3(0, -0.4, 0), (b - a).Unit) * CF(0, 0, 0), "NEW\n아우터", rgb(250, 250, 248), rgb(190, 100, 70), F.GothamBlack)
		end)
		hideRec(K, bar)
		hideWhere(K, V, setOf({ "RackPost", "RackFoot" }), function(r)
			return nearXZ(r.c, bar.c) < 6
		end)
		for _, r in recs(V, "Garment") do
			hideRec(K, r)
		end
	end

	-- 8) 마네킹 (맵 자세 그대로, 원본 숨김) + 쇼윈도 받침 ---------------------------------------------------------
	local torsos = recs(V, "MannequinTorso")
	local mList = {}
	for mi, tr in torsos do
		local base = nil
		for _, r in recs(V, "MannequinBase") do
			if nearXZ(r.c, tr.c) < 0.6 then
				base = r
			end
		end
		local y0 = if base then base.max.Y else 0.8
		local f = tr.lcf.LookVector
		local pcf = faceCF(V3(tr.c.X, 0, tr.c.Z), V3(f.X, 0, f.Z))
		local outfit = OUTFITS[(mi + seed) % #OUTFITS + 1]
		table.insert(mList, { pcf = pcf, y0 = y0, i = mi })
		K:group("Mannequin_" .. mi, function()
			K:free(function()
				mannequin(K, pcf, y0, outfit)
			end)
		end)
		for _, nm in { "MannequinBase", "MannequinPole", "MannequinLegs", "MannequinTorso", "MannequinShoulders", "MannequinNeck", "MannequinHead", "MannequinJacket" } do
			for _, r in recs(V, nm) do
				if nearXZ(r.c, tr.c) < 0.8 then
					hideRec(K, r)
				end
			end
		end
	end
	for _, r in recs(V, "WindowPlinth") do
		K:free(function()
			K:box("WindowPlinthBody", r.size - V3(0, 0.12, 0), CF(r.c - V3(0, 0.06, 0)), lk(rgb(244, 242, 236)))
			K:box("WindowPlinthTop", V3(r.size.X + 0.04, 0.12, r.size.Z + 0.04), CF(r.c.X, r.max.Y - 0.06, r.c.Z), oak)
			K:box("WindowPlinthLED", V3(r.size.X - 0.2, 0.04, 0.04), CF(r.c.X, 0.1, r.min.Z - 0.02), Look.lampWarm)
			-- 소품: 비치 타월 롤 · 조개 장식 · 바구니
			towelRoll(K, CF(r.c.X + (if r.c.X > 0 then -2.2 else 2.0), r.max.Y, r.c.Z - 0.6), 1.4, 0.45, rgb(96, 140, 160))
			towelRoll(K, CF(r.c.X + (if r.c.X > 0 then -2.0 else 2.2), r.max.Y + 0.42, r.c.Z - 0.6), 1.4, 0.45, rgb(246, 244, 238))
			K:ell("ShellDecor", V3(0.7, 0.3, 0.55), CF(r.c.X + (if r.c.X > 0 then 0.9 else -0.9), r.max.Y + 0.15, r.c.Z - 0.9), lk(rgb(246, 226, 214)))
		end)
		hideRec(K, r)
	end
	-- 중앙 마네킹 받침 (MannequinPlinth)
	local mplinth = V:first("MannequinPlinth")
	if mplinth then
		K:free(function()
			K:rbox("ManqPlinth", V3(mplinth.size.X, mplinth.size.Y - 0.08, mplinth.size.Z), 0.25, CF(mplinth.c - V3(0, 0.04, 0)) * ANG(0, PI / 2, 0) * ANG(0, PI / 2, 0), lk(rgb(236, 232, 224), M.Concrete))
			K:box("ManqPlinthTop", V3(mplinth.size.X - 0.1, 0.08, mplinth.size.Z - 0.1), CF(mplinth.c.X, mplinth.max.Y - 0.04, mplinth.c.Z), lk(rgb(214, 206, 192)))
		end)
		hideRec(K, mplinth)
	end
	-- 쇼윈도 스포트 (천장, 마네킹을 비춤) 2개
	local spotParts = {}
	for _, m in mList do
		local pz = (m.pcf * CF(0, 0, 0)).Position
		if pz.Z > V.z1 - 4 and #spotParts < 2 then
			local top = V3(pz.X, V.H, pz.Z - 2.6)
			K:free(function()
				K:box("WinSpotMount", V3(0.5, 0.06, 0.5), CF(top - V3(0, 0.03, 0)), black)
				local hcf = CFrame.lookAt(top - V3(0, 0.5, 0), pz + V3(0, 4.5, 0))
				K:vcyl("WinSpotStem", 0.45, 0.06, CF(top - V3(0, 0.25, 0)), black)
				K:cyl("WinSpotHead", 0.6, 0.38, hcf * CF(0, 0, -0.1) * ANG(0, PI / 2, 0), black)
				local lens = K:disc("WinSpotLens", 0.3, 0.02, hcf * CF(0, 0, -0.41) * ANG(PI / 2, 0, 0), Look.lampWarm)
				local l = K:light(lens, "SpotLight", { Face = Enum.NormalId.Top, Range = 14, Brightness = 1.4, Angle = 45, Color = Look.warmLight })
				table.insert(spotParts, { lens = lens, light = l })
			end)
		end
	end

	-- 9) 피팅룸: 주름 커튼 · 커튼봉 · 번호판 · 바깥벽 루버 · 안내 ---------------------------------------------------
	for ci, cur in recs(V, "Curtain") do
		local alongX = cur.size.X > cur.size.Z
		local w, h = math.max(cur.size.X, cur.size.Z), cur.size.Y
		local fdir = if alongX then V3(0, 0, 1) else V3(1, 0, 0)
		local pcf = faceCF(V3(cur.c.X, 0, cur.c.Z), fdir)
		local col = rgb(206, 190, 160)
		K:free(function()
			local n = math.max(6, math.floor(w / 0.42))
			for i = 0, n - 1 do
				local x = -w / 2 + (i + 0.5) * w / n
				K:vcyl("CurtainPleat", h, w / n * 1.25, pcf * CF(x, cur.min.Y + h / 2, (i % 2) * 0.1 - 0.05), lk(if i % 2 == 0 then col else dk(col, 0.08), M.Fabric))
			end
			K:box("CurtainHeader", V3(w, 0.25, 0.2), pcf * CF(0, cur.max.Y - 0.12, 0), lk(dk(col, 0.05), M.Fabric))
		end)
		hideRec(K, cur)
		local _ = ci
	end
	for _, rod in recs(V, "CurtainRod") do
		local alongX = rod.size.X > rod.size.Z
		K:free(function()
			K:cyl("CurtainRodNew", math.max(rod.size.X, rod.size.Z), 0.1, CF(rod.c) * (if alongX then CFrame.new() else ANG(0, PI / 2, 0)), brass)
			for _, s in { -1, 1 } do
				local e = rod.c + (if alongX then V3(s * rod.size.X / 2, 0, 0) else V3(0, 0, s * rod.size.Z / 2))
				K:ball("CurtainFinial", 0.2, CF(e), brass)
			end
		end)
		hideRec(K, rod)
	end
	-- 피팅룸 번호 (헤더 위) + 바깥벽 루버 + 이용 안내 + 페이스커버 상자
	local hdr = V:first("FittingHeader")
	local curtains = recs(V, "Curtain")
	if hdr then
		K:free(function()
			for i, cur in curtains do
				local d = faceCF(V3(cur.c.X, hdr.c.Y + 0.05, hdr.max.Z + 0.01), V3(0, 0, 1))
				if math.abs(cur.c.X - (V:first("Sign_FITTING ROOM") and V:first("Sign_FITTING ROOM").c.X or 1e9)) > 2.2 then
					K:disc("FitNoPlate", 0.5, 0.03, d * ANG(PI / 2, 0, 0), brass)
					txt(K, "FitNo", 0.34, 0.34, d * CF(0, 0, 0.035), tostring(i), rgb(40, 34, 28), nil, F.GothamBlack)
				end
			end
		end)
	end
	for _, fw in recs(V, "FittingWall") do
		if fw.size.X > 1.2 then
			K:free(function()
				local zf = fw.max.Z + 0.01
				local n = math.floor((fw.size.X - 0.1) / 0.35)
				K:box("FitWallBack", V3(fw.size.X, fw.size.Y - 0.5, 0.03), CF(fw.c.X, 0.25 + (fw.size.Y - 0.5) / 2, zf + 0.015), lk(rgb(232, 222, 202)))
				for i = 0, n - 1 do
					local x = fw.min.X + 0.05 + (i + 0.5) * (fw.size.X - 0.1) / n
					K:box("FitWallSlat", V3(0.18, fw.size.Y - 0.5, 0.1), CF(x, 0.25 + (fw.size.Y - 0.5) / 2, zf + 0.08), oak)
				end
			end)
		end
	end
	-- 이용 안내 (가장 넓은 피팅룸 바깥벽)
	local bigFW = nil
	for _, fw in recs(V, "FittingWall") do
		if not bigFW or fw.size.X > bigFW.size.X then
			bigFW = fw
		end
	end
	if bigFW and bigFW.size.X > 3 then
		K:free(function()
			local d = faceCF(V3(bigFW.c.X, 5.0, bigFW.max.Z + 0.2), V3(0, 0, 1))
			notice(K, d, 2.4, 1.6, "FITTING ROOM 이용 안내", "한 번에 3벌까지\n화장품이 묻지 않게 페이스 커버 사용\n이용 후 옷은 직원에게 주세요", rgb(44, 58, 92))
			local bx = faceCF(V3(bigFW.c.X, 3.4, bigFW.max.Z + 0.2), V3(0, 0, 1))
			K:box("FaceCoverBox", V3(0.9, 0.5, 0.35), bx * CF(0, 0, 0.18), lk(rgb(250, 250, 248)))
			K:box("FaceCoverTissue", V3(0.3, 0.12, 0.2), bx * CF(0, 0.3, 0.18), lk(rgb(240, 240, 238), M.Fabric))
			txt(K, "FaceCoverLabel", 0.8, 0.18, bx * CF(0, 0.02, 0.36), "페이스 커버", rgb(60, 60, 60), nil, F.GothamMedium)
		end)
	end

	-- 10) 대형 거울 테두리 · 푸프 · 계산대 ----------------------------------------------------------------
	local bm = V:first("BigMirrorFrame")
	if bm then
		local wall = nearestWall(V, bm.c)
		local u = V:wallCoord(wall, bm.c)
		local w, h = math.max(bm.size.X, bm.size.Z), bm.size.Y
		K:free(function()
			local d = wcf(V, wall, u, bm.c.Y, 0.01)
			K:plate("MirrorFrameBrass", w + 0.2, 0.18, 0.3, d * CF(0, h / 2, 0), brass)
			K:plate("MirrorFrameBrass", w + 0.2, 0.18, 0.3, d * CF(0, -h / 2, 0), brass)
			for _, s in { -1, 1 } do
				K:plate("MirrorFrameBrass", 0.18, h, 0.3, d * CF(s * (w / 2 + 0.01), 0, 0), brass)
				K:plate("MirrorLED", 0.06, h - 0.6, 0.32, d * CF(s * (w / 2 - 0.14), 0, 0), Look.lampWarm)
			end
			-- 거울면 (맵 BigMirror 자리, 같은 깊이) + 사선 반사 하이라이트
			local gm = V:first("BigMirror")
			if gm then
				local gz = math.abs(V:wall(wall, u, 0, 0):PointToObjectSpace(gm.max).Z)
				local gw, gh = math.max(gm.size.X, gm.size.Z), gm.size.Y
				local gd = wcf(V, wall, u, gm.c.Y, 0)
				K:plate("BigMirrorGlass", gw, gh, 0.02, gd * CF(0, 0, gz - 0.02), Look.mirror)
				K:plate("MirrorSheen", 0.5, 4.2, 0.004, gd * CF(-0.5, 0.6, gz + 0.002) * ANG(0, 0, -0.45), lk(WHITE, M.Glass, { t = 0.84 }))
				K:plate("MirrorSheen", 0.16, 3.4, 0.004, gd * CF(0.25, 0.3, gz + 0.002) * ANG(0, 0, -0.45), lk(WHITE, M.Glass, { t = 0.86 }))
				hideRec(K, gm)
			end
		end)
		hideRec(K, bm)
	end
	for _, pf in recs(V, "Pouf") do
		local dia = math.min(pf.size.X, pf.size.Z)
		K:free(function()
			K:vcyl("PoufBody", pf.size.Y - 0.25, dia, CF(pf.c.X, (pf.size.Y - 0.25) / 2 + 0.05, pf.c.Z), lk(rgb(110, 120, 80), M.Fabric))
			K:ell("PoufTop", V3(dia, 0.5, dia), CF(pf.c.X, pf.max.Y - 0.25, pf.c.Z), lk(rgb(120, 130, 88), M.Fabric))
			K:ball("PoufButton", 0.14, CF(pf.c.X, pf.max.Y + 0.0, pf.c.Z), lk(rgb(90, 100, 64), M.Fabric))
			K:disc("PoufBase", dia - 0.2, 0.06, CF(pf.c.X, 0.03, pf.c.Z), brass)
			for i = 0, 7 do
				local a = i * PI / 4
				K:box("PoufPiping", V3(0.05, pf.size.Y - 0.5, 0.05), CF(pf.c.X + math.cos(a) * dia / 2, (pf.size.Y - 0.25) / 2 + 0.05, pf.c.Z + math.sin(a) * dia / 2), lk(rgb(90, 100, 64), M.Fabric))
			end
		end)
		hideRec(K, pf)
	end
	local cc = V:first("CashCounter")
	local ct = V:first("CashTop")
	if cc and ct then
		local band = V:first("CounterLogoBand")
		local fdir = if band then V3(band.c.X - cc.c.X, 0, band.c.Z - cc.c.Z) else V3(-cc.c.X, 0, 0)
		if math.abs(fdir.X) >= math.abs(fdir.Z) then
			fdir = V3(math.sign(fdir.X), 0, 0)
		else
			fdir = V3(0, 0, math.sign(fdir.Z))
		end
		local along = math.abs(fdir.X) > 0.5
		local cw = if along then cc.size.Z else cc.size.X
		local cd = if along then cc.size.X else cc.size.Z
		local tw = if along then ct.size.Z else ct.size.X
		local td = if along then ct.size.X else ct.size.Z
		local pcf = faceCF(V3(cc.c.X, 0, cc.c.Z), fdir)
		local tcf = faceCF(V3(ct.c.X, 0, ct.c.Z), fdir)
		K:free(function()
			K:box("CashBody", V3(cw, cc.size.Y - 0.25, cd), pcf * CF(0, 0.25 + (cc.size.Y - 0.25) / 2, 0), lk(rgb(244, 242, 236)))
			K:box("CashKick", V3(cw - 0.1, 0.25, cd - 0.15), pcf * CF(0, 0.125, -0.06), black)
			local n = math.floor((cw - 0.2) / 0.35)
			for i = 0, n - 1 do
				K:box("CashSlat", V3(0.2, cc.size.Y - 0.6, 0.1), pcf * CF(-cw / 2 + 0.1 + (i + 0.5) * (cw - 0.2) / n, 0.3 + (cc.size.Y - 0.6) / 2, cd / 2 + 0.05), oak)
			end
			K:box("CashTopNew", V3(tw, ct.size.Y, td), tcf * CF(0, ct.c.Y, 0), Look.terrazzo)
			K:box("CashTopEdge", V3(tw + 0.02, 0.05, 0.03), tcf * CF(0, ct.min.Y + 0.03, td / 2), brass)
			K:plate("CashLogoBack", 3.0, 0.9, 0.03, pcf * CF(0, cc.size.Y * 0.55, cd / 2 + 0.1), lk(rgb(44, 58, 92)))
			txt(K, "CashLogo", 2.8, 0.7, pcf * CF(0, cc.size.Y * 0.55, cd / 2 + 0.135), "BADA CLOSET", rgb(246, 244, 238), nil, F.GothamBlack)
			-- 상판 소품: 쇼핑백 (선 것 1 + 접힌 것) · 포장지 · 옷걸이 통
			local topY = ct.max.Y
			local bagC = rgb(250, 250, 248)
			local items = { -tw / 2 + 0.6, tw / 2 - 0.7 }
			local blk = { V:first("PosBase"), V:first("CardReader"), V:first("Vase") }
			local placed = 0
			for _, x in items do
				local lp = (tcf * CF(x, topY, 0)).Position
				local okp = true
				for _, q in blk do
					if q and nearXZ(q.c, lp) < 1.0 then
						okp = false
					end
				end
				if okp then
					placed += 1
					local at = tcf * CF(x, topY, -0.1)
					if placed == 1 then
						K:box("ShopBagStand", V3(0.9, 1.1, 0.45), at * CF(0, 0.55, 0), lk(bagC, M.Cardboard))
						K:seg("ShopBagRope", (at * CF(-0.2, 1.1, 0)).Position, (at * CF(0, 1.45, 0)).Position, 0.04, lk(rgb(44, 58, 92), M.Fabric))
						K:seg("ShopBagRope", (at * CF(0.2, 1.1, 0)).Position, (at * CF(0, 1.45, 0)).Position, 0.04, lk(rgb(44, 58, 92), M.Fabric))
						txt(K, "ShopBagLogo", 0.8, 0.3, at * CF(0, 0.62, 0.235), "BADA\nCLOSET", rgb(44, 58, 92), nil, F.GothamBlack)
						for j = 0, 2 do
							K:box("ShopBagFlat", V3(1.0, 0.04, 0.7), at * CF(0.1, 0.02 + j * 0.045, 0.25 + 0.0) * ANG(0, 0.08 * j, 0), lk(if j == 1 then rgb(44, 58, 92) else bagC, M.Cardboard))
						end
					else
						K:box("TissuePaper", V3(0.9, 0.08, 0.7), at * CF(0, 0.04, 0), lk(rgb(232, 222, 202)))
						K:vcyl("HangerTub", 0.6, 0.5, at * CF(0.0, 0.38, 0.0), lk(rgb(40, 40, 44)))
						for j = 0, 3 do
							K:bar("SpareHanger", (at * CF(-0.1 + j * 0.06, 0.6, 0)).Position, (at * CF(-0.1 + j * 0.06, 1.0, 0.2)).Position, 0.04, 0.04, WOOD_HANGER)
						end
					end
				end
			end
		end)
		hideRec(K, cc)
		hideRec(K, ct)
		if band then
			hideRec(K, band)
		end
		for _, r in recs(V, "ShopBag") do
			hideRec(K, r)
		end
	end

	-- 11) 모자 스탠드 (HatStand) -> 브라스 모자걸이 + 모자 ---------------------------------------------------------
	local hp = V:first("HatStandPole")
	if hp then
		local p = V3(hp.c.X, 0, hp.c.Z)
		local top = hp.max.Y
		K:free(function()
			K:disc("HatTreeBase", 1.4, 0.15, CF(p.X, 0.075, p.Z), Look.marbleWhite)
			K:vcyl("HatTreePole", top - 0.15, 0.12, CF(p.X, 0.15 + (top - 0.15) / 2, p.Z), brass)
			K:ball("HatTreeTop", 0.22, CF(p.X, top + 0.05, p.Z), brass)
			local hc = { rgb(222, 196, 140), rgb(30, 30, 32), rgb(232, 222, 202), rgb(110, 120, 80), rgb(150, 190, 220), rgb(206, 186, 150) }
			for i = 0, 5 do
				local a = i * PI / 3 + 0.3
				local y = top - 0.4 - (i % 2) * 0.6
				local tip = V3(p.X + math.cos(a) * 0.7, y + 0.25, p.Z + math.sin(a) * 0.7)
				K:seg("HatTreeArm", V3(p.X, y, p.Z), tip, 0.06, brass)
				local kinds = { "straw", "cap", "bucket" }
				hat(K, CF(tip + V3(math.cos(a) * 0.15, -0.2, math.sin(a) * 0.15)) * ANG(0, -a + PI / 2, 0) * ANG(0, 0, (i % 2 - 0.5) * 0.4), hc[(i + seed) % #hc + 1], kinds[i % 3 + 1])
			end
		end)
		hideWhere(K, V, setOf({ "HatStandPole", "HatStandBase" }))
		for _, r in recs(V, "Cap") do
			if nearXZ(r.c, hp.c) < 1.5 then
				hideRec(K, r)
			end
		end
	end

	-- 천장에 매단 SALE 간판 (앞 테이블 위, 양면)
	local ft = nil
	for _, t in recs(V, "DisplayTable") do
		if not ft or t.c.Z > ft.c.Z then
			ft = t
		end
	end
	if ft then
		local c = V3(ft.c.X, 7.4, ft.c.Z)
		K:box("SaleHangSign", V3(3.4, 1.0, 0.08), CF(c), lk(rgb(190, 100, 70)))
		for _, sgn in { 1, -1 } do
			txt(K, "SaleHangText", 3.2, 0.8, CF(c + V3(0, 0, sgn * 0.045)) * (if sgn < 0 then ANG(0, PI, 0) else CFrame.new()), "SUMMER SALE  30 ~ 50%", rgb(252, 248, 240), nil, F.GothamBlack)
		end
		for _, sx in { -1.4, 1.4 } do
			K:seg("SaleHangWire", c + V3(sx, 0.5, 0), V3(c.X + sx, V.H, c.Z), 0.03, Look.chrome)
		end
	end

	-- 12) 위 간판 띠 (큐비 · 신발 · 레일 위 빈 벽) + 비치타월 사다리 ---------------------------------------------------
	local bands = {
		{ "right", "DAILY LOOK  ·  데일리룩", rgb(44, 58, 92) },
		{ "right", "SHOES & SANDALS", rgb(190, 100, 70) },
		{ "left", "BEACHWEAR  ·  린넨 & 코튼", rgb(110, 120, 80) },
		{ "back", "BADA CLOSET", rgb(44, 58, 92) },
	}
	for bi, bd in bands do
		local w2, d2 = Common.wallSpot(K, { bd[1] }, 5.0, 8.15, 9.55, if bi == 2 then -1 else (if bi == 1 then 9 else 4))
		if w2 and d2 then
			K:plate("BandSignBack", 5.0, 1.0, 0.12, d2, lk(rgb(250, 248, 244)))
			K:plate("BandSignEdge", 5.0, 0.06, 0.14, d2 * CF(0, -0.47, 0), lk(bd[3]))
			txt(K, "BandSign", 4.6, 0.62, d2 * CF(0, 0.05, 0.13), bd[2], bd[3], nil, F.GothamBlack)
		end
	end
	-- 비치타월 사다리 (벽에 기대기)
	for _, wn in { "right", "left", "back" } do
		local w2, d2 = Common.wallSpot(K, { wn }, 2.0, 0.5, 7.0, -V.D / 3)
		if w2 and d2 then
			local base = V:wall(wn, (V:wallCoord(wn, d2.Position)), 0, 0.9)
			if K:spot(base, V3(1.8, 6.6, 1.2), 0.05) then
				local lad = lk(rgb(190, 150, 104), M.Wood)
				for _, s in { -0.7, 0.7 } do
					K:bar("LadderRail", (base * CF(s, 0, 0.45)).Position, (base * CF(s, 6.5, -0.75)).Position, 0.14, 0.1, lad)
				end
				local tc = { rgb(96, 140, 160), rgb(240, 214, 120), rgb(246, 244, 238), rgb(190, 100, 70) }
				for i = 1, 4 do
					local t = i / 5
					local y, z = 6.5 * t, 0.45 - 1.2 * t
					K:bar("LadderRung", (base * CF(-0.7, y, z)).Position, (base * CF(0.7, y, z)).Position, 0.1, 0.1, lad)
					K:box("BeachTowel", V3(1.3, 1.4, 0.06), base * CF(0, y - 0.68, z + 0.08), lk(tc[(i + seed) % 4 + 1], M.Fabric))
					if not lowD(K) then
						K:box("BeachTowelStripe", V3(1.31, 0.12, 0.065), base * CF(0, y - 0.95, z + 0.08), lk(rgb(250, 250, 248), M.Fabric))
					end
				end
				txt(K, "LadderTag", 0.9, 0.3, base * CF(0, 1.6, 0.42), "비치타월 19,000", rgb(30, 30, 30), rgb(250, 248, 240), F.GothamBold)
				break
			end
		end
	end

	-- 13) 상호작용: 코디 바꾸기 (가운데 마네킹) · 쇼윈도 조명 · 매장 음악 -------------------------------------------------
	local centerM = {}
	for _, m in mList do
		if m.pcf.Position.Z < V.z1 - 6 then
			table.insert(centerM, m)
		end
	end
	if mplinth and #centerM > 0 then
		local d = faceCF(V3(mplinth.c.X, 0, mplinth.max.Z + 0.03), V3(0, 0, 1))
		local lp = d.Position + V3(0, 0.3, 0)
		if promptOK(K, V, lp) then
			local tag = K:plate("CoordiSign", 1.4, 0.36, 0.04, d * CF(0, mplinth.size.Y / 2 - 0.02, 0), lk(rgb(44, 58, 92)))
			txt(K, "CoordiText", 1.3, 0.26, d * CF(0, mplinth.size.Y / 2 - 0.02, 0.045), "오늘의 코디 · TODAY'S LOOK", rgb(246, 244, 238), nil, F.GothamBold)
			local idx = 0
			Interact.prompt(K, tag, {
				action = "코디 바꾸기",
				object = "마네킹",
				fn = function()
					idx += 1
					for j, m in centerM do
						local g = K.root:FindFirstChild("Mannequin_" .. m.i, true)
						if g then
							local o = OUTFITS[((m.i + seed + idx * 2 + j) % #OUTFITS) + 1]
							for _, p in g:GetDescendants() do
								if p:IsA("BasePart") and p.Material == M.Fabric then
									local nm = p.Name
									local pre = string.sub(nm, 1, 6)
									if pre == "ManqT_" then
										p.Color = if nm == "ManqT_Lapel" or nm == "ManqT_Collar" or nm == "ManqT_Cuff" or nm == "ManqT_Neckline" or nm == "ManqT_Ribbing" or nm == "ManqT_Pocket" or nm == "ManqT_Hem" then dk(o.top, 0.12) else o.top
									elseif pre == "ManqB_" then
										p.Color = if nm == "ManqB_Waistband" or nm == "ManqB_Hem" or nm == "ManqB_ShortsCuff" then dk(o.bottom or o.top, 0.12) else (o.bottom or o.top)
									end
								end
							end
						end
					end
				end,
			})
		end
	end
	-- 피팅룸 칸 안쪽 (FittingWall 뒤) 은 제외
	local bmn, bmx = nil, nil
	for _, nm in { "FittingWall", "BoothDivider", "FittingHeader" } do
		for _, r in recs(V, nm) do
			bmn = if bmn then bmn:Min(r.min) else r.min
			bmx = if bmx then bmx:Max(r.max) else r.max
		end
	end
	local function inBooth(p: Vector3): boolean
		return bmn ~= nil and bmx ~= nil and p.X > bmn.X - 0.5 and p.X < bmx.X + 0.5 and p.Z < bmx.Z + 0.3
	end
	local _ = inBooth
	-- 블루투스 스피커 (뒤쪽 진열 테이블 위) = 매장 음악 순환
	local tables = recs(V, "DisplayTable")
	table.sort(tables, function(p, q)
		return p.c.Z < q.c.Z
	end)
	local songs = { "♪ NewJeans - Supernatural", "♪ 데이식스 - 녹아내려요", "♪ 아이유 - Love wins all", "♪ Crush - 미워", "♪ 검정치마 - Everything" }
	local st = tables[1]
	if st then
		local at = CF(st.c.X + st.size.X / 2 - 0.55, st.max.Y, st.c.Z - st.size.Z / 2 + 0.45)
		if promptOK(K, V, at.Position) then
			K:free(function()
				local spk = K:rbox("Speaker", V3(1.0, 0.7, 0.42), 0.1, at * CF(0, 0.35, 0), lk(rgb(30, 28, 26), M.Leather))
				K:plate("SpeakerGrille", 0.86, 0.42, 0.01, at * CF(0, 0.3, 0.21), lk(rgb(60, 56, 50), M.Fabric))
				for j = 0, 2 do
					K:cyl("SpeakerKnob", 0.05, 0.08, at * CF(-0.25 + j * 0.25, 0.62, 0.2) * ANG(0, PI / 2, 0), lk(rgb(196, 164, 98), M.Metal))
				end
				K:box("SpeakerLED", V3(0.06, 0.03, 0.01), at * CF(0.42, 0.62, 0.21), nl(rgb(80, 200, 255)))
				local cardF = at * CF(-0.95, 0.25, 0.05) * ANG(-0.15, 0.2, 0)
				local _, lab = txt(K, "NowPlaying", 0.9, 0.42, cardF, "NOW PLAYING\n" .. songs[1], rgb(40, 40, 44), rgb(250, 248, 244), F.GothamMedium)
				Interact.cycle(K, spk[1], songs, {
					object = "매장 음악",
					action = "다음 곡",
					on = function(_i, item)
						lab.Text = "NOW PLAYING\n" .. item
					end,
				})
			end)
		end
	end
	-- 룩북 디지털 스탠드 (입구 쪽 바닥, 다음 룩 보기)
	local looks = {
		{ "LOOK 01  린넨 셔츠 + 버뮤다 팬츠", rgb(232, 222, 202) },
		{ "LOOK 02  플리츠 원피스 + 라탄백", rgb(150, 190, 220) },
		{ "LOOK 03  니트 베스트 + 와이드 데님", rgb(44, 58, 92) },
		{ "LOOK 04  오버핏 셔츠 + 버킷햇", rgb(110, 120, 80) },
	}
	local cands = {}
	for _, x in { 4.6, -4.6, 5.6, -5.6 } do
		for _, z in { V.z1 - 7.5, V.z1 - 9.0, V.z1 - 10.5 } do
			table.insert(cands, faceCF(V3(x, 0, z), V3(-x * 0.3, 0, 1)))
		end
	end
	local lb = firstSpot(K, cands, V3(1.8, 6.2, 0.9), 0.15)
	if lb and promptOK(K, V, (lb * CF(0, 4.2, 0.3)).Position) then
		K:box("LookbookBase", V3(1.6, 0.12, 0.8), lb * CF(0, 0.06, 0), black)
		K:box("LookbookPost", V3(1.7, 5.6, 0.22), lb * CF(0, 0.12 + 2.8, 0), lk(rgb(30, 30, 32)))
		local scr = K:box("LookbookScreen", V3(1.5, 3.9, 0.02), lb * CF(0, 3.55, 0.12), lk(looks[1][2], M.SmoothPlastic, { r = 0.1 }))
		-- 화면 속 모델 실루엣 (머리 · 몸 · 다리)
		local fg = lk(rgb(40, 38, 44))
		K:disc("LookbookFigHead", 0.36, 0.01, lb * CF(0, 4.95, 0.135) * ANG(PI / 2, 0, 0), lk(rgb(236, 220, 206)))
		K:box("LookbookFigBody", V3(0.62, 1.1, 0.01), lb * CF(0, 4.15, 0.135), fg)
		K:box("LookbookFigLegs", V3(0.46, 1.1, 0.01), lb * CF(0, 3.05, 0.135), lk(rgb(230, 226, 216)))
		local _, lab = txt(K, "LookbookText", 1.4, 0.6, lb * CF(0, 1.95, 0.135), looks[1][1], rgb(30, 30, 32), rgb(250, 248, 244), F.GothamBold)
		txt(K, "LookbookHead", 1.4, 0.3, lb * CF(0, 5.25, 0.135), "BADA LOOKBOOK 2026", rgb(250, 250, 248), nil, F.GothamBlack, 1.2)
		local back = lb * CF(0, 3.2, -0.115) * ANG(0, PI, 0)
		K:plate("LookbookBackPanel", 1.5, 3.6, 0.01, back, lk(rgb(232, 222, 204)))
		txt(K, "LookbookBackLogo", 1.3, 0.9, back * CF(0, 0.6, 0.012), "BADA\nCLOSET", rgb(44, 58, 92), nil, F.GothamBlack)
		txt(K, "LookbookBackSub", 1.3, 0.3, back * CF(0, -0.4, 0.012), "데일리룩 & 비치웨어", rgb(80, 80, 84), nil, F.GothamMedium)
		Interact.cycle(K, scr, looks, {
			object = "룩북",
			action = "다음 룩",
			on = function(_i, item)
				lab.Text = item[1]
				scr.Color = item[2]
			end,
		})
	end
	local _ = S
end

--================================================================================================
-- 서프 & SUP 숍 (surf)
--================================================================================================
local SURF = {
	teal = rgb(32, 150, 150),
	sea = rgb(40, 110, 170),
	sand = rgb(226, 206, 166),
	coral = rgb(240, 110, 90),
	sun = rgb(250, 196, 70),
	white = rgb(248, 248, 244),
	wood = rgb(176, 136, 92),
	driftwood = rgb(196, 182, 160),
	neo = rgb(26, 26, 28),
}

-- 서프보드: cf = 보드 가운데, X = 폭, Y = 길이 (노즈 +Y), Z = 데크 쪽. o.rail (테두리 색), o.deck (윗면), o.no (번호 글자)
-- 액자 사진 (Props.frame depth 0.06 안쪽, 그림 칸 aw x ah): 층 0.037 ~ 0.0435
--   kind = "bridge" (광안대교 야경) | "wave" (파도 배럴 + 서퍼) | "sunrise" (일출 + 롱보더 실루엣)
local function photoArt(K: any, d: CFrame, aw: number, ah: number, kind: string)
	local L = { 0.0365, 0.038, 0.0395, 0.041, 0.0425 }
	local function R(name: string, w: number, h: number, x: number, y: number, layer: number, c: Color3, rot: number?)
		K:box(name, V3(math.min(w, aw), math.min(h, ah), 0.001), d * CF(x * aw, y * ah, L[layer]) * ANG(0, 0, rot or 0), lk(c))
	end
	local function O(name: string, w: number, h: number, x: number, y: number, layer: number, c: Color3, rot: number?)
		K:ell(name, V3(w, h, 0.001), d * CF(x * aw, y * ah, L[layer]) * ANG(0, 0, rot or 0), lk(c))
	end
	-- 두 점 사이 가는 선 (그림 좌표 -0.5..0.5)
	local function line(name: string, x0: number, y0: number, x1: number, y1: number, th: number, layer: number, c: Color3)
		local dx, dy = (x1 - x0) * aw, (y1 - y0) * ah
		local len = math.sqrt(dx * dx + dy * dy)
		K:box(name, V3(len, th, 0.001), d * CF((x0 + x1) / 2 * aw, (y0 + y1) / 2 * ah, L[layer]) * ANG(0, 0, math.atan2(dy, dx)), lk(c))
	end
	if kind == "bridge" then
		R("ArtSky", aw, ah, 0, 0, 1, rgb(18, 26, 62))
		R("ArtHorizon", aw, ah * 0.16, 0, 0.0, 2, rgb(92, 60, 120))
		R("ArtSea", aw, ah * 0.42, 0, -0.29, 2, rgb(12, 20, 44))
		O("ArtMoon", 0.16, 0.16, 0.36, 0.34, 2, rgb(250, 244, 220))
		R("ArtDeck", aw, 0.05, 0, 0.06, 3, rgb(240, 200, 120))
		for _, tx in { -0.22, 0.22 } do
			R("ArtTower", 0.05, ah * 0.36, tx, 0.24, 3, rgb(200, 204, 214))
			R("ArtTowerGlow", 0.04, ah * 0.2, tx, -0.2, 3, rgb(200, 160, 90))
		end
		local cc = { rgb(120, 210, 255), rgb(255, 130, 200) }
		for k, sx in { -1, 1 } do
			line("ArtCable", sx * 0.22, 0.42, sx * 0.08, 0.16, 0.025, 4, cc[k])
			line("ArtCable", sx * 0.08, 0.16, 0, 0.1, 0.025, 4, cc[k])
			line("ArtCable", sx * 0.22, 0.42, sx * 0.38, 0.17, 0.025, 4, cc[k])
			line("ArtCable", sx * 0.38, 0.17, sx * 0.5, 0.1, 0.025, 4, cc[k])
		end
		for j = 0, 5 do
			R("ArtReflect", 0.05, 0.03 + (j % 3) * 0.03, -0.3 + j * 0.12, -0.12 - (j % 2) * 0.12, 3, if j % 2 == 0 then rgb(220, 180, 110) else rgb(110, 180, 230))
		end
	elseif kind == "wave" then
		R("ArtSky", aw, ah, 0, 0, 1, rgb(170, 214, 236))
		R("ArtSea", aw, ah * 0.5, 0, -0.25, 2, rgb(36, 120, 160))
		O("ArtWave", aw * 0.78, ah * 0.7, 0.14, -0.22, 3, rgb(30, 150, 170), 0.3)
		O("ArtWaveShade", aw * 0.5, ah * 0.42, 0.22, -0.3, 4, rgb(24, 122, 150), 0.3)
		O("ArtLip", aw * 0.6, ah * 0.08, 0.04, 0.08, 4, rgb(244, 250, 252), 0.3)
		for j = 0, 3 do
			O("ArtSpray", 0.08 + j * 0.02, 0.06 + j * 0.015, 0.28 + j * 0.05, 0.16 + (j % 2) * 0.08, 4, rgb(240, 248, 252))
		end
		R("ArtFoam", aw, ah * 0.1, 0, -0.45, 4, rgb(236, 246, 250))
		-- 서퍼 (몸 · 머리 · 보드)
		O("ArtSurferBoard", 0.42, 0.06, -0.06, -0.24, 4, rgb(250, 120, 80), 0.25)
		O("ArtSurfer", 0.08, 0.24, -0.06, -0.15, 4, rgb(30, 30, 34), -0.3)
		O("ArtSurferHead", 0.07, 0.07, -0.08, -0.05, 4, rgb(30, 30, 34))
		line("ArtSurferArm", -0.12, -0.1, -0.0, -0.08, 0.025, 4, rgb(30, 30, 34))
	else
		R("ArtSky", aw, ah, 0, 0, 1, rgb(244, 150, 100))
		R("ArtSkyLow", aw, ah * 0.22, 0, 0.0, 2, rgb(252, 204, 120))
		O("ArtSun", 0.5, 0.5, 0.18, 0.02, 3, rgb(255, 236, 170))
		R("ArtSea", aw, ah * 0.47, 0, -0.265, 4, rgb(52, 92, 132))
		R("ArtBridgeLine", aw, 0.03, 0, -0.03, 4, rgb(70, 60, 80))
		for j = 0, 3 do
			R("ArtSunPath", 0.5 - j * 0.1, 0.025, 0.18, -0.1 - j * 0.09, 5, rgb(255, 214, 140))
		end
		-- 롱보드 든 실루엣
		O("ArtWalker", 0.1, 0.36, -0.28, -0.3, 5, rgb(30, 26, 30))
		O("ArtWalkerHead", 0.08, 0.08, -0.28, -0.15, 5, rgb(30, 26, 30))
		line("ArtLongboard", -0.36, -0.2, -0.2, -0.42, 0.06, 5, rgb(30, 26, 30))
	end
end

local function surfboard(K: any, cf: CFrame, len: number, w: number, t: number, o: any)
	-- cf: +Y = 코, +Z = 데크 (보이는 면). 평면 = 타원 (코 쪽 조금 뾰족) + 데크 색 안쪽 타원 + 스트링어
	local railC = o.rail or SURF.white
	local rail = lk(railC, M.SmoothPlastic, { r = 0.06 })
	local out = {}
	table.insert(out, K:ell("BoardOutline", V3(w, len, t), cf, rail))
	local lift = 0
	if o.deck and o.deck ~= railC then
		-- 소프트보드: 흰 데크 (레일 색 테두리가 남게 조금 작은 타원)
		table.insert(out, K:ell("BoardDeck", V3(w * 0.84, len * 0.9, t), cf * CF(0, -len * 0.02, 0.014), lk(o.deck, M.SmoothPlastic, { r = 0.03 })))
		lift = 0.014
	end
	local top = t / 2 + lift
	if o.stringer ~= false then
		table.insert(out, K:box("BoardStringer", V3(0.035, len * 0.5, 0.016), cf * CF(0, 0, top - 0.002), lk(o.stringerC or rgb(150, 110, 70), M.Wood)))
	end
	if o.stripe then
		-- 코 쪽 핀라인 2줄
		for k, y in { 0.17, 0.2 } do
			table.insert(out, K:box("BoardStripe", V3(w * (0.62 - k * 0.04), 0.06, 0.016), cf * CF(0, len * y, top * 0.94), lk(o.stripe)))
		end
	end
	-- 꼬리 트랙션 패드 (홈 3줄 + 킥)
	if o.pad ~= false then
		local pz = t * 0.5 * math.sqrt(1 - 0.66 ^ 2) + lift
		table.insert(out, K:box("BoardTailPad", V3(w * 0.5, len * 0.12, 0.03), cf * CF(0, -len * 0.33, pz), lk(rgb(30, 30, 32), M.Rubber)))
		if not lowD(K) then
			for g = -1, 1 do
				table.insert(out, K:box("BoardPadGroove", V3(0.025, len * 0.11, 0.012), cf * CF(g * w * 0.12, -len * 0.33, pz + 0.018), lk(rgb(70, 70, 74), M.Rubber)))
			end
			table.insert(out, K:box("BoardPadKick", V3(w * 0.42, 0.12, 0.08), cf * CF(0, -len * 0.39, pz + 0.03), lk(rgb(30, 30, 32), M.Rubber)))
		end
		-- 리시 플러그
		table.insert(out, K:disc("BoardLeashPlug", 0.1, 0.02, cf * CF(0, -len * 0.42, pz - 0.01) * ANG(PI / 2, 0, 0), lk(rgb(240, 240, 240))))
	end
	-- 핀 (바닥 -Z)
	if not lowD(K) then
		for _, fx in { -0.3, 0, 0.3 } do
			local fy = -len * 0.4 + (if fx == 0 then -0.05 else 0.2)
			table.insert(out, K:wedge("BoardFin", V3(0.05, 0.42, 0.34), cf * CF(fx * w * 0.9, fy, -t * 0.3 - 0.17) * ANG(PI, 0, 0), lk(o.fin or rgb(40, 40, 44))))
		end
	end
	-- 렌탈 번호 스티커 (작게, 코 쪽) + 브랜드 로고 타원
	if o.no then
		table.insert(out, K:ell("BoardNoSticker", V3(w * 0.5, w * 0.24, 0.01), cf * CF(0, len * 0.06, top + 0.001), lk(rgb(250, 250, 248))))
		local _ = txt(K, "BoardNo", w * 0.42, w * 0.18, cf * CF(0, len * 0.06, top + 0.006), o.no, o.noC or rgb(30, 30, 32), nil, F.GothamBlack)
	end
	if o.logo ~= false then
		-- 브랜드 스티커 (데크 색과 대비되는 레일 색 타원 + 가는 띠)
		local logoC = o.logoC or (if o.deck and o.deck ~= railC then railC else rgb(250, 250, 248))
		table.insert(out, K:ell("BoardLogo", V3(w * 0.3, w * 0.13, 0.01), cf * CF(0, len * 0.28, top * 0.86), lk(logoC)))
		table.insert(out, K:box("BoardLogoBar", V3(w * 0.2, 0.025, 0.012), cf * CF(0, len * 0.28 - w * 0.1, top * 0.86), lk(logoC)))
	end
	return out
end

-- 웻슈트 (정면 걸이): hook = 레일 점, fdir = 보는 쪽 (방 안쪽)
local function wetsuit(K: any, hook: Vector3, fdir: Vector3, accent: Color3, kind: string)
	local g = faceCF(hook, fdir)
	local neo = lk(SURF.neo, M.Rubber)
	local acc = lk(accent, M.Rubber)
	K:seg("SuitHook", (g * CF(0, 0.1, -0.05)).Position, (g * CF(0, -0.2, 0)).Position, 0.04, Look.chrome)
	K:bar("SuitHanger", (g * CF(-0.75, -0.42, 0)).Position, (g * CF(0.75, -0.42, 0)).Position, 0.12, 0.1, lk(rgb(30, 30, 32)))
	K:ell("SuitShoulders", V3(1.45, 0.5, 0.26), g * CF(0, -0.55, 0), neo)
	K:box("SuitTorso", V3(1.12, 1.75, 0.24), g * CF(0, -1.45, 0), if kind == "color" then lk(dk(accent, 0.45), M.Rubber) else neo)
	K:box("SuitChestPanel", V3(1.0, 0.5, 0.25), g * CF(0, -0.95, 0.005), acc)
	K:box("SuitLogo", V3(0.4, 0.1, 0.01), g * CF(0.25, -1.2, 0.13), lk(rgb(240, 240, 240)))
	-- 팔
	for _, sx in { -1, 1 } do
		local a = (g * CF(sx * 0.68, -0.62, 0)).Position
		local b = (g * CF(sx * 0.82, if kind == "spring" then -1.35 else -2.55, 0.02)).Position
		K:seg("SuitArm", a, b, 0.32, neo)
		if kind ~= "spring" then
			K:seg("SuitCuff", b + V3(0, 0.15, 0), b, 0.33, acc)
		end
	end
	-- 다리
	local legLen = if kind == "spring" then 0.8 else 2.35
	K:box("SuitHips", V3(1.1, 0.5, 0.24), g * CF(0, -2.55, 0), neo)
	for _, sx in { -1, 1 } do
		K:box("SuitLeg", V3(0.5, legLen, 0.22), g * CF(sx * 0.29, -2.8 - legLen / 2, 0), neo)
		if kind ~= "spring" and not lowD(K) then
			K:box("SuitKnee", V3(0.48, 0.4, 0.23), g * CF(sx * 0.29, -3.45, 0.005), lk(rgb(70, 70, 74), M.Rubber))
		end
	end
	-- 가격 · 사이즈 택
	if not lowD(K) then
		K:box("SuitTag", V3(0.22, 0.32, 0.02), g * CF(0.62, -0.75, 0.15), lk(rgb(250, 248, 240)))
	end
end

-- 구명조끼 (정면): g = 고리 점 프레임
local function lifeVest(K: any, g: CFrame, c: Color3)
	local body = lk(c, M.Fabric)
	K:seg("VestHook", (g * CF(0, 0.12, -0.12)).Position, (g * CF(0, -0.1, 0.05)).Position, 0.05, Look.chrome)
	K:rbox("VestBody", V3(0.34, 1.45, 1.3), 0.15, g * CF(0, -0.85, 0.1) * ANG(0, PI / 2, 0), body)
	K:ell("VestCollar", V3(0.9, 0.3, 0.4), g * CF(0, -0.15, 0.1), body)
	K:box("VestZip", V3(0.05, 1.3, 0.01), g * CF(0, -0.85, 0.28), lk(rgb(30, 30, 30)))
	for _, y in { -0.75, -1.25 } do
		K:box("VestStrap", V3(1.32, 0.12, 0.36), g * CF(0, y, 0.1), lk(rgb(26, 26, 28), M.Fabric))
		K:box("VestBuckle", V3(0.22, 0.16, 0.05), g * CF(0, y, 0.3), lk(rgb(40, 40, 40)))
	end
	K:box("VestReflect", V3(0.24, 0.1, 0.01), g * CF(-0.4, -0.4, 0.275), lk(rgb(220, 220, 220), M.SmoothPlastic, { r = 0.3 }))
end

-- 천장 선풍기 (실링팬): 반환 = 회전 파트 목록, 중심 (월드), 조명 파트
local function ceilingFan(K: any, V: any, x: number, z: number, drop: number): ({ BasePart }, Vector3, BasePart?)
	local y = V.H
	local blades = {}
	local hub = V3(x, y - drop, z)
	local glow = nil
	K:free(function()
		K:disc("FanCanopy", 0.6, 0.12, CF(x, y - 0.06, z), lk(rgb(40, 34, 30), M.Metal))
		K:seg("FanDownrod", V3(x, y - 0.1, z), hub + V3(0, 0.25, 0), 0.1, lk(rgb(40, 34, 30), M.Metal))
		K:vcyl("FanMotor", 0.42, 0.75, CF(hub), lk(rgb(40, 34, 30), M.Metal))
		for i = 0, 4 do
			local a = i * PI * 2 / 5
			local dir = V3(math.cos(a), 0, math.sin(a))
			local arm = K:bar("FanArm", hub + dir * 0.3, hub + dir * 0.75 + V3(0, -0.02, 0), 0.12, 0.05, lk(rgb(40, 34, 30), M.Metal))
			local blade = K:box("FanBlade", V3(0.55, 0.04, 1.9), CFrame.lookAt(hub + dir * 1.6, hub + dir * 3) * ANG(0, 0, 0.12), lk(rgb(150, 110, 70), M.Wood))
			if arm then
				table.insert(blades, arm)
			end
			table.insert(blades, blade)
		end
		K:vcyl("FanLightCup", 0.22, 0.55, CF(hub - V3(0, 0.3, 0)), lk(rgb(40, 34, 30), M.Metal))
		glow = K:disc("FanLightLamp", 0.46, 0.04, CF(hub - V3(0, 0.42, 0)), Look.lampWarm)
	end)
	return blades, (K.cf * CF(hub)).Position, glow
end

local function buildSurf(K: any, V: any, S: any)
	pcall(windowSignBacks, K, V)
	pcall(twoSidedSigns, K, V)
	local seed = hashStr(V.key or V.name or "surf")
	local wood = lk(SURF.wood, M.Wood)
	local drift = lk(SURF.driftwood, M.WoodPlanks)
	local rope = lk(rgb(196, 170, 120), M.Fabric)

	-- 1) 벽 서프보드 랙 + 보드 (렌탈 소프트보드 번호) ------------------------------------------------------
	local rackBase = V:first("RackBase")
	local railR = V:first("RackRail")
	local boards = {}
	for _, r in recs(V, "Surfboard") do
		if rackBase and nearXZ(r.c, V3(rackBase.c.X, 0, math.clamp(r.c.Z, rackBase.min.Z, rackBase.max.Z))) < 2.5 then
			table.insert(boards, r)
		end
	end
	table.sort(boards, function(p, q)
		return p.c.Z > q.c.Z
	end)
	K:free(function()
		for i, r in boards do
			local cf = r.lcf
			local soft = i % 3 ~= 0
			local base = r.part.Color
			surfboard(K, cf, r.part.Size.Y, r.part.Size.X, 0.24, {
				rail = if soft then base else SURF.white,
				deck = if soft then SURF.white else base,
				stringer = not soft,
				stripe = if soft then dk(base, 0.1) else nil,
				no = if soft then string.format("R-%02d", i) else nil,
				noC = dk(base, 0.25),
				fin = if soft then rgb(240, 240, 240) else rgb(30, 30, 34),
			})
		end
		if rackBase then
			-- 받침: 나무 + 카펫 패드 + 칸막이
			K:box("BoardRackBase", rackBase.size - V3(0, 0.1, 0), CF(rackBase.c - V3(0, 0.05, 0)), wood)
			K:box("BoardRackPad", V3(rackBase.size.X - 0.1, 0.1, rackBase.size.Z - 0.1), CF(rackBase.c.X, rackBase.max.Y - 0.05, rackBase.c.Z), lk(rgb(40, 60, 70), M.Fabric))
			for i = 1, #boards - 1 do
				local z = (boards[i].c.Z + boards[i + 1].c.Z) / 2
				K:box("BoardRackPeg", V3(1.2, 1.0, 0.12), CF(rackBase.c.X + 0.2, rackBase.max.Y + 0.45, z), lk(rgb(150, 110, 70), M.Wood))
			end
		end
		if railR then
			K:box("BoardRackRail", railR.size + V3(0, 0.1, 0), CF(railR.c), wood)
			K:box("BoardRackRailPad", V3(0.12, 0.3, railR.size.Z), CF(railR.max.X + 0.06, railR.c.Y, railR.c.Z), lk(rgb(196, 176, 136), M.Fabric))
		end
	end)
	for _, r in boards do
		hideRec(K, r)
		for _, q in recs(V, "Stringer") do
			if nearXZ(q.c, r.c) < 0.6 and math.abs(q.c.Z - r.c.Z) < 0.4 then
				hideRec(K, q)
			end
		end
	end
	if rackBase then
		hideRec(K, rackBase)
	end
	if railR then
		hideRec(K, railR)
	end
	-- 랙 위 사진 액자 3 (광안대교 · 파도 · 일출) + 간판
	if rackBase then
		local wall = nearestWall(V, rackBase.c)
		local u0 = V:wallCoord(wall, rackBase.min)
		local u1 = V:wallCoord(wall, rackBase.max)
		local ua, ub = math.min(u0, u1), math.max(u0, u1)
		local arts = { "bridge", "wave", "sunrise" }
		K:free(function()
			for i = 1, 3 do
				local u = ua + (ub - ua) * (i - 0.5) / 3
				local fd = wcf(V, wall, u, 8.45, 0.01)
				Props.frame(K, fd, 3.6, 1.9, { frame = lk(rgb(240, 236, 228), M.Wood), mat = lk(WHITE), depth = 0.06, border = 0.08 })
				photoArt(K, fd, 3.6 - 0.16 - 0.24, 1.9 - 0.16 - 0.24, arts[(i + seed) % 3 + 1])
			end
			txt(K, "RackHeader", 4.2, 0.45, wcf(V, wall, (ua + ub) / 2, 7.45, 0.04), "RENTAL BOARDS · 렌탈 보드", SURF.white, SURF.teal, F.GothamBlack)
			useWall(K, wall, ua, ub, 0, 9.6)
		end)
	end

	-- 2) 웻슈트 레일 ------------------------------------------------------------------------------------
	local suitRail = V:first("SuitRail")
	local suits = recs(V, "Wetsuit")
	if suitRail and #suits > 0 then
		local wall = nearestWall(V, suitRail.c)
		local fdir = V:wall(wall, 0, 0, 0).ZVector
		local accents = { SURF.teal, SURF.sea, SURF.coral, rgb(70, 70, 74), SURF.sun }
		K:free(function()
			K:cyl("SuitRailNew", math.max(suitRail.size.Z, suitRail.size.X) + 0.4, 0.14, CF(suitRail.c) * (if suitRail.size.Z > suitRail.size.X then ANG(0, PI / 2, 0) else CFrame.new()), Look.chrome)
			for _, sz in { -1, 1 } do
				local e = suitRail.c + (if suitRail.size.Z > suitRail.size.X then V3(0, 0, sz * (suitRail.size.Z / 2 + 0.1)) else V3(sz * (suitRail.size.X / 2 + 0.1), 0, 0))
				local u = V:wallCoord(wall, e)
				K:bar("SuitRailArm", wcf(V, wall, u, e.Y, 0).Position, e, 0.1, 0.1, Look.chrome)
			end
			for i, r in suits do
				local hook = V3(r.c.X, suitRail.max.Y, r.c.Z)
				wetsuit(K, hook, fdir, accents[(i + seed) % #accents + 1], if i % 4 == 0 then "spring" elseif i % 3 == 0 then "color" else "full")
			end
			local mid = V:wallCoord(wall, suitRail.c)
			txt(K, "SuitHeader", 4.6, 0.45, wcf(V, wall, mid, 8.0, 0.04), "WETSUIT · 웻슈트 대여 15,000원", SURF.white, SURF.neo, F.GothamBlack)
			txt(K, "SuitSizes", 3.6, 0.3, wcf(V, wall, mid, 7.55, 0.04), "XS  S  M  L  XL  ·  3/2mm 풀슈트 · 스프링 슈트", rgb(40, 40, 44), SURF.white, F.GothamMedium)
			useWall(K, wall, mid - 7, mid + 7, 7.3, 8.3)
		end)
		hideRec(K, suitRail)
		for _, r in suits do
			hideRec(K, r)
		end
		for _, r in recs(V, "SuitTrim") do
			hideRec(K, r)
		end
		-- 아래 바닥: 부츠 (페어) 4
		local u0 = V:wallCoord(wall, suits[1].c)
		local u1 = V:wallCoord(wall, suits[#suits].c)
		for i = 0, 3 do
			local u = u0 + (u1 - u0) * (i + 0.5) / 4
			local pc = wcf(V, wall, u, 0, 0.6)
			if K:spot(pc, V3(0.9, 1.0, 0.8), 0.02) then
				for _, sx in { -0.22, 0.22 } do
					K:box("BootSole", V3(0.38, 0.1, 0.8), pc * CF(sx, 0.05, 0), lk(rgb(60, 60, 64), M.Rubber))
					K:box("BootUpper", V3(0.36, 0.8, 0.42), pc * CF(sx, 0.5, -0.18), lk(SURF.neo, M.Rubber))
					K:ell("BootToe", V3(0.36, 0.36, 0.5), pc * CF(sx, 0.2, 0.15), lk(SURF.neo, M.Rubber))
				end
			end
		end
	end

	-- 3) 장비 선반 (핀 · 리시 · 왁스) -------------------------------------------------------------------
	local gear = recs(V, "GearShelf")
	table.sort(gear, function(p, q)
		return p.c.Y < q.c.Y
	end)
	for gi, r in gear do
		local wall = nearestWall(V, r.c)
		local u = V:wallCoord(wall, r.c)
		local len = math.max(r.size.X, r.size.Z)
		local dep = math.min(r.size.X, r.size.Z)
		K:free(function()
			local at = Props.shelf(K, wcf(V, wall, u, r.c.Y, 0), len, { depth = dep, look = wood, bracket = Look.blackMetal, thick = r.size.Y })
			local n = 4
			for j = 1, n do
				local x = -len / 2 + (j - 0.5) * len / n
				if gi == 1 then
					-- 핀 세트 (카드 + 핀 3)
					K:box("FinCard", V3(1.1, 1.0, 0.04), at * CF(x, 0.5, -0.45), lk(({ SURF.teal, SURF.neo, SURF.coral, SURF.sea })[j]))
					for k = -1, 1 do
						K:wedge("FinSet", V3(0.06, 0.55, 0.4), at * CF(x + k * 0.3, 0.4, -0.38) * ANG(0, PI / 2, 0), lk(if j % 2 == 0 then rgb(250, 250, 250) else rgb(30, 30, 34)))
					end
					txt(K, "FinPrice", 0.9, 0.18, at * CF(x, 0.9, -0.42), (({ "FCS II 89,000", "트라이 핀 65,000", "롱보드 싱글 55,000", "소프트 핀 25,000" })[j]), WHITE, nil, F.GothamBold)
				elseif gi == 2 then
					-- 리시 코일
					local c = ({ SURF.sea, SURF.neo, SURF.coral, SURF.sun })[j]
					K:ring("LeashCoil", at * CF(x, 0.42, -0.3) * ANG(0, 0, 0), 0.34, 0.08, if lowD(K) then 5 else 7, lk(c, M.Rubber))
					K:box("LeashCuff", V3(0.32, 0.28, 0.16), at * CF(x + 0.1, 0.16, -0.25), lk(rgb(30, 30, 32), M.Fabric))
					txt(K, "LeashPrice", 0.9, 0.18, at * CF(x, -0.12, 0.02), (({ "리시 6ft 35,000", "리시 9ft 39,000", "SUP 코일 리시 45,000", "키즈 리시 29,000" })[j]), rgb(30, 30, 30), SURF.white, F.GothamBold)
				else
					-- 왁스 더미 + 왁스 콤
					for k = 0, 2 do
						K:disc("WaxPuck", 0.62, 0.18, at * CF(x - 0.15, 0.09 + k * 0.19, -0.35), lk(({ rgb(250, 240, 200), rgb(200, 230, 240), rgb(250, 210, 220) })[(j + k) % 3 + 1]))
					end
					K:box("WaxComb", V3(0.4, 0.04, 0.3), at * CF(x + 0.35, 0.02, -0.2), lk(({ SURF.coral, SURF.teal })[j % 2 + 1]))
					txt(K, "WaxPrice", 0.9, 0.18, at * CF(x, -0.12, 0.02), (({ "왁스 웜 5,000", "왁스 쿨 5,000", "베이스 코트 6,000", "왁스 콤 3,000" })[j]), rgb(30, 30, 30), SURF.white, F.GothamBold)
				end
			end
		end)
		hideRec(K, r)
	end
	for _, nm in { "Fin", "LeashCoil", "SurfWax" } do
		for _, r in recs(V, nm) do
			hideRec(K, r)
		end
	end
	if #gear > 0 then
		local r = gear[#gear]
		local wall = nearestWall(V, r.c)
		local u = V:wallCoord(wall, r.c)
		K:free(function()
			txt(K, "GearHeader", 4.0, 0.42, wcf(V, wall, u, r.c.Y + 1.15, 0.04), "SURF GEAR · 핀 · 리시 · 왁스", SURF.white, SURF.sea, F.GothamBlack)
		end)
	end

	-- 4) 가운데 SUP 랙 + 보드 3 + 패들 ---------------------------------------------------------------------
	local supRack = V:first("SupRack")
	local sups = recs(V, "SupBoard")
	if supRack then
		local alongZ = supRack.size.Z > supRack.size.X
		K:free(function()
			local L = if alongZ then supRack.size.Z else supRack.size.X
			local Wd = if alongZ then supRack.size.X else supRack.size.Z
			local rot = if alongZ then CFrame.new() else ANG(0, PI / 2, 0)
			local c0 = CF(supRack.c.X, 0, supRack.c.Z) * rot
			for _, s in { -1, 1 } do
				local tz = s * (L / 2 - 1.0)
				for _, sx in { -1, 1 } do
					K:box("SupTrestleLeg", V3(0.3, supRack.size.Y - 0.1, 0.3), c0 * CF(sx * (Wd / 2 - 0.3), (supRack.size.Y - 0.1) / 2, tz), wood)
				end
				K:box("SupTrestleBar", V3(Wd, 0.3, 0.5), c0 * CF(0, supRack.size.Y - 0.15, tz), wood)
				K:box("SupTrestlePad", V3(Wd - 0.1, 0.08, 0.55), c0 * CF(0, supRack.size.Y + 0.0, tz), lk(rgb(196, 176, 136), M.Fabric))
				K:box("SupFoot", V3(Wd + 0.4, 0.15, 0.6), c0 * CF(0, 0.075, tz), wood)
			end
			K:box("SupRunner", V3(0.2, 0.2, L - 2.0), c0 * CF(0, 0.3, 0), wood)
			txt(K, "SupRackSign", 2.8, 0.5, c0 * CF(0, 0.8, L / 2 - 0.9) * CF(0, 0, 0.27), "SUP 체험 20,000원 · 30분", SURF.white, SURF.teal, F.GothamBlack)
			local cols = { { SURF.sea, SURF.sand }, { SURF.coral, rgb(250, 250, 248) }, { SURF.teal, SURF.sand } }
			table.sort(sups, function(p, q)
				return p.c.Y < q.c.Y
			end)
			for i, r in sups do
				local along2 = r.size.Z > r.size.X
				local len = if along2 then r.size.Z else r.size.X
				local w = if along2 then r.size.X else r.size.Z
				local ldir = if along2 then V3(0, 0, -1) else V3(-1, 0, 0)
				if (i + seed) % 2 == 0 then
					ldir = -ldir
				end
				-- 납작한 보드 프레임: +Z = 꼬리, -Z = 코 (위 = +Y)
				local fcf = CFrame.lookAt(r.c, r.c + ldir)
				local t = r.size.Y
				local cc = cols[(i + seed) % #cols + 1]
				local shell = lk(cc[1], M.SmoothPlastic, { r = 0.06 })
				-- 평면: 둥근 꼬리 스타디움 + 뾰족한 코 타원 + 흰 레일 띠
				K:slab("SupHull", w, len * 0.82, t, w / 2 - 0.02, fcf * CF(0, 0, len * 0.09), shell)
				K:ell("SupNose", V3(w, t, len * 0.52), fcf * CF(0, 0, -len * 0.24), shell)
				K:slab("SupRailBand", w + 0.02, len * 0.7, t * 0.3, w / 2 - 0.01, fcf * CF(0, -t * 0.22, len * 0.1), lk(rgb(246, 246, 244)))
				-- EVA 데크 패드 (홈 줄) + 킥 패드
				local padL = len * 0.36
				K:slab("SupPad", w * 0.72, padL, 0.03, 0.18, fcf * CF(0, t / 2 + 0.015, len * 0.08), lk(cc[2], M.Rubber))
				if not lowD(K) then
					for g = -2, 2 do
						K:box("SupPadGroove", V3(0.03, 0.012, padL - 0.2), fcf * CF(g * w * 0.12, t / 2 + 0.034, len * 0.08), lk(dk(cc[2], 0.3), M.Rubber))
					end
				end
				K:slab("SupKickPad", w * 0.5, len * 0.08, 0.05, 0.12, fcf * CF(0, t / 2 + 0.025, len * 0.4), lk(dk(cc[2], 0.15), M.Rubber))
				-- 가운데 손잡이 (홈 + 고무 띠) · 앞 번지 (화물끈 X) · 로고
				K:box("SupHandle", V3(0.55, 0.06, 0.2), fcf * CF(0, t / 2 + 0.04, len * 0.0), lk(rgb(30, 30, 30), M.Rubber))
				if i == #sups then
					for _, d in { 1, -1 } do
						K:bar("SupBungee", (fcf * CF(-w * 0.3, t / 2 + 0.03, -len * 0.27 + d * 0.5)).Position, (fcf * CF(w * 0.3, t / 2 + 0.03, -len * 0.27 - d * 0.5)).Position, 0.05, 0.04, lk(rgb(30, 30, 30), M.Fabric))
					end
					for _, sx in { -1, 1 } do
						for _, dz in { -0.5, 0.5 } do
							K:disc("SupBungeeCleat", 0.12, 0.04, fcf * CF(sx * w * 0.3, t / 2 + 0.02, -len * 0.27 + dz), lk(rgb(240, 240, 240)))
						end
					end
					local lp = (fcf * CF(0, t / 2 + 0.004, -len * 0.08)).Position
					txt(K, "SupLogo", 2.6, 0.42, topCF(lp, fcf.RightVector), "GWANGAN SUP 10'6\"", rgb(250, 250, 248), nil, F.GothamBlack)
				end
				-- 보드 사이 받침 폼
				if i > 1 then
					for _, s in { -1, 1 } do
						K:box("SupSpacer", V3(w * 0.6, r.min.Y - sups[i - 1].max.Y + 0.02, 0.4), CF(r.c.X, (r.min.Y + sups[i - 1].max.Y) / 2, r.c.Z) * rot * CF(0, 0, s * (L / 2 - 1.0)), lk(rgb(40, 60, 70), M.Fabric))
					end
				end
			end
		end)
		hideRec(K, supRack)
		for _, r in sups do
			hideRec(K, r)
		end
	end
	-- 패들 (탄소 샤프트 + T 손잡이 + 블레이드)
	for _, sh in recs(V, "PaddleShaft") do
		local bl = nil
		for _, r in recs(V, "PaddleBlade") do
			if nearXZ(r.c, sh.c) < 1.0 and math.abs(r.c.X - sh.c.X) < 0.2 then
				bl = r
			end
		end
		if bl then
			local topP = V3(sh.c.X, sh.max.Y, sh.max.Z - 0.05)
			local botP = V3(bl.c.X, bl.max.Y - 0.1, bl.c.Z)
			local dir = (topP - botP).Unit
			K:free(function()
				K:seg("PaddleShaftNew", botP, topP, 0.12, lk(rgb(30, 30, 32), M.SmoothPlastic, { r = 0.15 }))
				K:bar("PaddleTGrip", topP - V3(0.22, 0, 0), topP + V3(0.22, 0, 0), 0.14, 0.12, lk(rgb(30, 30, 32)))
				local bc = CFrame.lookAt(bl.c, bl.c + V3(0, 0, 1)) * CFrame.fromAxisAngle(V3(1, 0, 0), 0)
				local up = dir
				local bcf = CFrame.fromMatrix(bl.c, V3(1, 0, 0), up, V3(1, 0, 0):Cross(up))
				K:ell("PaddleBladeNew", V3(0.7, 1.35, 0.1), bcf, lk(SURF.teal))
				K:box("PaddleBladeRib", V3(0.08, 1.2, 0.12), bcf, lk(rgb(30, 30, 32)))
				local _ = bc
			end)
			hideRec(K, sh)
			hideRec(K, bl)
		end
	end

	-- 5) 구명조끼 스탠드 ---------------------------------------------------------------------------------
	local vs = V:first("VestStand")
	if vs then
		local vests = recs(V, "LifeVest")
		local fz = if #vests > 0 then (vests[1].c.Z - vs.c.Z) else 1
		local fdir = if math.abs(vs.size.X) > math.abs(vs.size.Z) then V3(0, 0, math.sign(fz)) else V3(math.sign(fz), 0, 0)
		local pcf = faceCF(V3(vs.c.X, 0, vs.c.Z), fdir)
		local w = math.max(vs.size.X, vs.size.Z)
		local h = vs.size.Y
		K:free(function()
			for _, sx in { -1, 1 } do
				K:box("VestPost", V3(0.3, h, 0.3), pcf * CF(sx * (w / 2 - 0.15), h / 2, -0.1), wood)
				K:box("VestFoot", V3(0.4, 0.15, 1.6), pcf * CF(sx * (w / 2 - 0.15), 0.075, 0), wood)
			end
			K:box("VestTopBar", V3(w, 0.3, 0.3), pcf * CF(0, h - 0.15, -0.1), wood)
			K:box("VestMidBar", V3(w - 0.3, 0.2, 0.2), pcf * CF(0, h * 0.52, -0.1), wood)
			txt(K, "VestHeader", w - 0.2, 0.42, pcf * CF(0, h + 0.3, -0.1), "LIFE JACKET · 구명조끼 필수", SURF.white, SURF.coral, F.GothamBlack)
			local cols = { rgb(250, 110, 40), rgb(250, 200, 40), rgb(250, 110, 40), rgb(40, 110, 200) }
			for i, r in vests do
				local g = faceCF(V3(r.c.X, r.max.Y + 0.25, r.c.Z - fdir.Z * 0.12 - fdir.X * 0.12), fdir)
				lifeVest(K, g, cols[(i - 1) % #cols + 1])
				if not lowD(K) then
					txt(K, "VestSize", 0.4, 0.22, g * CF(0.42, -1.45, 0.3), (({ "M", "L", "S", "XL" })[(i - 1) % 4 + 1]), rgb(30, 30, 30), SURF.white, F.GothamBlack)
				end
			end
		end)
		hideRec(K, vs)
		for _, r in vests do
			hideRec(K, r)
		end
	end

	-- 6) 벤치 (Seat 덮기: 같은 윗면 · 크기) · 아이스박스 ------------------------------------------------------
	for _, ch in V.chairs do
		local s = ch.seat
		if s.name == "Bench" then
			local alongX = s.size.X >= s.size.Z
			local L = if alongX then s.size.X else s.size.Z
			local D = if alongX then s.size.Z else s.size.X
			local c0 = CF(s.c.X, 0, s.c.Z) * (if alongX then CFrame.new() else ANG(0, PI / 2, 0))
			local top = s.max.Y
			K:free(function()
				local n = 5
				for i = 0, n - 1 do
					local z = -D / 2 + (i + 0.5) * D / n
					K:box("BenchSlat", V3(L, 0.2, D / n - 0.06), c0 * CF(0, top - 0.1, z), drift)
				end
				for _, sx in { -1, 1 } do
					local x = sx * (L / 2 - 0.45)
					K:box("BenchLeg", V3(0.26, top - 0.2, D - 0.3), c0 * CF(x, (top - 0.2) / 2, 0), wood)
				end
				K:box("BenchStretcher", V3(L - 1.0, 0.2, 0.2), c0 * CF(0, 0.5, 0), wood)
				-- 벤치 위 수건 한 장 (끝)
				K:box("BenchTowel", V3(1.0, 0.06, D - 0.2), c0 * CF(L / 2 - 0.7, top + 0.03, 0), lk(SURF.sun, M.Fabric))
			end)
			hideRec(K, s)
			for _, q in ch.parts do
				if q ~= s then
					hideRec(K, q)
				end
			end
		end
	end
	local cooler = V:first("CoolerBox")
	if cooler then
		local p = CF(cooler.c.X, 0, cooler.c.Z)
		local w, h, d = cooler.size.X, cooler.size.Y, cooler.size.Z
		K:free(function()
			K:box("CoolerBody", V3(w, h * 0.72, d), p * CF(0, h * 0.36, 0), lk(rgb(40, 110, 200)))
			K:box("CoolerBand", V3(w + 0.02, h * 0.28, d + 0.02), p * CF(0, h * 0.86, 0), lk(rgb(248, 248, 244)))
			K:box("CoolerLidNew", V3(w + 0.06, 0.22, d + 0.06), p * CF(0, h + 0.11, 0), lk(rgb(248, 248, 244)))
			K:box("CoolerHandle", V3(w * 0.6, 0.08, 0.1), p * CF(0, h + 0.27, 0), lk(rgb(40, 40, 44)))
			for _, sx in { -1, 1 } do
				K:box("CoolerLatch", V3(0.12, 0.3, 0.06), p * CF(sx * w * 0.32, h * 0.9, d / 2 + 0.04), lk(rgb(40, 40, 44)))
			end
			K:disc("CoolerDrain", 0.14, 0.04, p * CF(-w * 0.38, 0.2, d / 2 + 0.02) * ANG(PI / 2, 0, 0), lk(rgb(40, 40, 44)))
			txt(K, "CoolerText", w * 0.7, 0.3, p * CF(0, h * 0.45, d / 2 + 0.01), "ICE · 생수 1,500", WHITE, nil, F.GothamBlack)
			for k = 0, 1 do
				K:vcyl("CoolerCan", 0.46, 0.26, p * CF(-0.3 + k * 0.5, h + 0.45, 0.1), lk(({ rgb(220, 40, 40), rgb(40, 150, 220) })[k + 1], M.Metal))
			end
		end)
		hideRec(K, cooler)
		local lid = V:first("CoolerLid")
		if lid then
			hideRec(K, lid)
		end
	end

	-- 7) 렌탈 카운터 (앞면 화이트워시 판자 + 로프 + 서프 그래픽, 상판 티크) -------------------------------------------
	local ctop = V:first("CounterTop")
	local cbody = V:first("RentalCounter")
	if ctop and cbody then
		local fz = cbody.max.Z
		K:free(function()
			K:box("RentalBody", cbody.size - V3(0, 0.25, 0.02), CF(cbody.c + V3(0, 0.125, 0)), lk(rgb(236, 232, 222), M.WoodPlanks))
			K:box("RentalKick", V3(cbody.size.X - 0.1, 0.25, cbody.size.Z - 0.2), CF(cbody.c.X, 0.125, cbody.c.Z - 0.05), lk(rgb(40, 60, 70)))
			K:box("RentalBand", V3(cbody.size.X + 0.02, 0.3, 0.04), CF(cbody.c.X, cbody.max.Y - 0.35, fz + 0.02), lk(SURF.teal))
			K:cyl("RentalRope", cbody.size.X, 0.14, CF(cbody.c.X, cbody.max.Y - 0.12, fz + 0.06), rope)
			K:box("RentalTopNew", ctop.size, CF(ctop.c), lk(rgb(150, 100, 60), M.Wood, { r = 0.08 }))
		end)
		hideRec(K, ctop)
		hideRec(K, cbody)
		local cb = V:first("CounterBoard")
		if cb then
			hideRec(K, cb)
			local st = V:first("CounterBoardStripe")
			if st then
				hideRec(K, st)
			end
			-- 앞면 서프보드 모양 간판 (가로)
			K:free(function()
				local cf = CFrame.fromMatrix(V3(cb.c.X, cb.c.Y, fz + 0.12), V3(0, -1, 0), V3(1, 0, 0), V3(0, 0, 1))
				surfboard(K, cf, cb.size.X * 0.95, cb.size.Y * 1.1, 0.16, { rail = SURF.sea, deck = SURF.white, stringer = false, pad = false })
				txt(K, "CounterLogo", cb.size.X * 0.5, cb.size.Y * 0.55, CF(cb.c.X, cb.c.Y, fz + 0.24), "광안 SURF & SUP", SURF.sea, nil, F.GothamBlack)
				txt(K, "CounterSub", cb.size.X * 0.36, 0.22, CF(cb.c.X, cb.c.Y - cb.size.Y * 0.36, fz + 0.24), "LESSON · RENTAL · SINCE 2019", rgb(80, 80, 84), nil, F.GothamBold)
			end)
		end
		-- 상판 소품: 선크림 진열 · 서약서 클립보드 · 손목밴드 · 가격 스탠드
		local topY = ctop.max.Y
		local blk = { V:first("PosBase"), V:first("CardReader"), V:first("SunscreenDisplay") }
		local function clear(lp: Vector3, r: number): boolean
			for _, q in blk do
				if q and nearXZ(q.c, lp) < r + math.max(q.size.X, q.size.Z) / 2 then
					return false
				end
			end
			return true
		end
		local slots = {}
		for i = 0, 9 do
			local x = ctop.min.X + 1.0 + i * (ctop.size.X - 2.0) / 9
			local lp = V3(x, topY, ctop.c.Z + 0.35)
			if clear(lp, 0.75) then
				table.insert(slots, lp)
			end
		end
		K:free(function()
			for i, lp in slots do
				local at = CF(lp)
				if i == 1 then
					K:box("Clipboard", V3(0.8, 0.04, 1.05), at * CF(0, 0.02, 0) * ANG(0, 0.15, 0), lk(rgb(150, 110, 70), M.Wood))
					K:box("WaiverPaper", V3(0.72, 0.01, 0.95), at * CF(0, 0.045, 0.02) * ANG(0, 0.15, 0), lk(rgb(252, 252, 250)))
					txt(K, "WaiverText", 0.62, 0.8, topCF(lp + V3(0, 0.052, 0.02), V3(0, 0, -1)) * ANG(0, 0, -0.15), "수상레저 안전 서약서\n\n성명 ________\n연락처 ________\n□ 구명조끼 착용\n□ 음주 후 이용 금지", rgb(40, 40, 44), nil, F.GothamMedium, nil, { d = 0.005 })
					K:seg("Pen", lp + V3(0.42, 0.06, -0.2), lp + V3(0.5, 0.06, 0.35), 0.04, lk(rgb(30, 30, 30)))
				elseif i == 2 then
					K:vcyl("WristbandJar", 0.5, 0.6, at * CF(0, 0.25, 0), gl(rgb(220, 236, 240), 0.5))
					for k = 0, 3 do
						K:ring("Wristband", at * CF(-0.1 + (k % 2) * 0.2, 0.18 + (k // 2) * 0.14, -0.05 + (k % 2) * 0.1) * ANG(PI / 2, 0, k), 0.13, 0.04, 5, lk(({ SURF.coral, SURF.sun, SURF.teal, SURF.sea })[k + 1]))
					end
				elseif i == 3 then
					K:box("PriceStandBase", V3(0.8, 0.05, 0.3), at * CF(0, 0.025, 0), Look.acrylicWhite)
					txt(K, "PriceStand", 0.76, 1.0, at * CF(0, 0.55, 0) * ANG(-0.1, 0, 0), "오늘의 강습\n10:00 · 14:00\n16:30 선셋\n※ 예약 우선", rgb(30, 30, 30), rgb(252, 250, 246), F.GothamBold)
				elseif i == 4 then
					K:vcyl("WaxSampleJar", 0.45, 0.55, at * CF(0, 0.22, 0), lk(rgb(250, 240, 200)))
					txt(K, "WaxSampleLabel", 0.5, 0.2, at * CF(0, 0.25, 0.28), "SURF WAX", rgb(200, 60, 60), nil, F.GothamBlack)
				end
			end
		end)
		local ssd = V:first("SunscreenDisplay")
		if ssd then
			local p = CF(ssd.c.X, ssd.min.Y, ssd.c.Z)
			K:free(function()
				K:box("SunStandBase", V3(ssd.size.X, 0.12, ssd.size.Z), p * CF(0, 0.06, 0), Look.acrylicWhite)
				K:box("SunStandStep", V3(ssd.size.X, 0.45, ssd.size.Z * 0.5), p * CF(0, 0.12 + 0.225, -ssd.size.Z * 0.25), Look.acrylicWhite)
				K:box("SunStandBack", V3(ssd.size.X, 0.7, 0.05), p * CF(0, 0.57 + 0.35, -ssd.size.Z / 2 + 0.03), lk(SURF.sun))
				txt(K, "SunStandText", ssd.size.X * 0.9, 0.3, p * CF(0, 0.57 + 0.45, -ssd.size.Z / 2 + 0.06), "워터프루프 선크림 SPF50+", rgb(40, 40, 44), nil, F.GothamBlack)
				local cols = { rgb(250, 250, 250), SURF.sun, SURF.coral, SURF.sea }
				for k = 0, 3 do
					local x = -ssd.size.X / 2 + 0.3 + k * (ssd.size.X - 0.6) / 3
					bottle(K, p * CF(x, 0.57, -ssd.size.Z * 0.25), "tube", 0.65, cols[k + 1], rgb(40, 40, 44))
					bottle(K, p * CF(x, 0.12, ssd.size.Z * 0.22), "spray", 0.55, cols[(k + 2) % 4 + 1], rgb(40, 40, 44))
				end
			end)
			hideRec(K, ssd)
			for _, r in recs(V, "Sunscreen") do
				hideRec(K, r)
			end
		end
		-- 카운터 위 라탄 펜던트 3
		for i, x in { ctop.min.X + 2.5, ctop.c.X - 1.5, ctop.max.X - 2.5 } do
			local z = ctop.c.Z + 0.5
			if Common.ceilFree(K, x, z, 0.9) then
				K:free(function()
					Props.pendant(K, V3(x, V.H, z), 2.6, { shade = "rattan", dia = 1.4, light = i == 2, range = 12, bright = 0.6 })
				end)
				Common.useCeil(K, x, z)
			end
		end
	end

	-- 8) 보관함 (맵 Locker 자리, 문 하나는 여닫기) -----------------------------------------------------------
	local lockers = recs(V, "Locker")
	table.sort(lockers, function(p, q)
		if math.abs(p.c.X - q.c.X) > 0.3 then
			return p.c.X < q.c.X
		end
		return p.c.Y < q.c.Y
	end)
	local doors = {}
	for li, r in lockers do
		local wall = nearestWall(V, r.c)
		local fdir = V:wall(wall, 0, 0, 0).ZVector
		local along = math.abs(fdir.X) > 0.5
		local w = if along then r.size.Z else r.size.X
		local d = if along then r.size.X else r.size.Z
		local pcf = faceCF(V3(r.c.X, 0, r.c.Z), fdir)
		local y0, h = r.min.Y, r.size.Y
		local body = lk(rgb(220, 226, 228), M.Metal)
		K:free(function()
			K:box("LockerBody", V3(w, h, d - 0.06), pcf * CF(0, y0 + h / 2, -0.03), body)
			local m = K:group("LockerDoor_" .. li, function()
				local dc = pcf * CF(0, y0 + h / 2, d / 2 + 0.02)
				K:box("LockerDoorPanel", V3(w - 0.12, h - 0.12, 0.05), dc, lk(({ SURF.teal, SURF.sea, SURF.sun, SURF.coral })[(li - 1) % 4 + 1], M.Metal))
				for k = 0, 2 do
					K:box("LockerVent", V3(w * 0.5, 0.05, 0.01), dc * CF(0, h / 2 - 0.4 - k * 0.14, 0.03), lk(rgb(40, 40, 44)))
				end
				K:box("LockerHandle", V3(0.1, 0.5, 0.1), dc * CF(w / 2 - 0.3, 0, 0.07), Look.chrome)
				K:box("LockerKeypad", V3(0.36, 0.5, 0.05), dc * CF(w / 2 - 0.35, 0.6, 0.04), lk(rgb(40, 40, 44)))
				K:box("LockerKeyLED", V3(0.08, 0.05, 0.01), dc * CF(w / 2 - 0.35, 0.8, 0.07), nl(rgb(80, 255, 120)))
				txt(K, "LockerNo", 0.5, 0.4, dc * CF(-w / 2 + 0.45, h / 2 - 0.45, 0.03), tostring(li), WHITE, nil, F.GothamBlack)
			end)
			table.insert(doors, { m = m, hinge = (K.cf * pcf * CF(-w / 2 + 0.06, y0, d / 2 + 0.02)).Position, axis = (K.cf * pcf).YVector, y = y0, pcf = pcf, w = w, d = d, h = h })
			-- 안쪽 (열면 보이는 가방 · 수건)
			K:box("LockerInside", V3(w - 0.2, h - 0.2, 0.04), pcf * CF(0, y0 + h / 2, -d / 2 + 0.06), lk(rgb(60, 64, 68), M.Metal))
			if li == 1 then
				K:box("LockerBag", V3(1.0, 1.2, 0.8), pcf * CF(0, y0 + 0.7, -0.1), lk(rgb(40, 90, 140), M.Fabric))
				towelRoll(K, pcf * CF(0, y0 + 1.5, 0), 1.1, 0.4, SURF.sun)
			end
		end)
		hideRec(K, r)
	end
	for _, r in recs(V, "LockerTag") do
		hideRec(K, r)
	end
	if #doors > 0 then
		local d1 = doors[1]
		local handle = d1.m:FindFirstChild("LockerHandle", true)
		if handle and handle:IsA("BasePart") and promptOK(K, V, V.cf:PointToObjectSpace(handle.Position)) then
			Interact.swing(K, d1.m, d1.hinge, d1.axis, -PI * 0.6, { object = "보관함 1번", openText = "열기", closeText = "닫기" })
		end
		local top = lockers[1]
		local wall = nearestWall(V, top.c)
		local u0 = V:wallCoord(wall, lockers[1].c)
		local u1 = V:wallCoord(wall, lockers[#lockers].c)
		K:free(function()
			txt(K, "LockerHeader", math.abs(u1 - u0) + 1.6, 0.42, wcf(V, wall, (u0 + u1) / 2, 7.55, 0.04), "LOCKER · 보관함 3,000원 (샤워 이용 시 무료)", rgb(40, 40, 44), SURF.white, F.GothamBold)
		end)
	end

	-- 9) 강습 · 렌탈 요금판 (뒷벽 빈 자리) + 서핑 강습 사진 ----------------------------------------------------
	local w9, d9 = Common.wallSpot(K, { "back", "right", "left" }, 3.15, 4.1, 8.9, -4.45)
	if w9 and d9 then
		local bw, bh = 3.05, 4.5
		K:free(function()
			K:plate("RateBoardFrame", bw + 0.2, bh + 0.2, 0.1, d9, lk(rgb(240, 236, 228), M.Wood))
			K:plate("RateBoard", bw, bh, 0.12, d9, lk(rgb(24, 70, 96)))
			txt(K, "RateTitle", bw * 0.9, 0.45, d9 * CF(0, bh / 2 - 0.38, 0.13), "LESSON & RENTAL 2026", SURF.sun, nil, F.GothamBlack)
			local rows = {
				{ "서핑 입문 강습 (2시간 · 장비 포함)", "60,000" },
				{ "서핑 레벨업 강습 (2시간)", "70,000" },
				{ "SUP 체험 (30분)", "20,000" },
				{ "SUP 선셋 투어 (90분)", "45,000" },
				{ "서프보드 대여 (2시간)", "25,000" },
				{ "소프트보드 대여 (1일)", "35,000" },
				{ "웻슈트 대여", "15,000" },
				{ "구명조끼 · 리시", "무료" },
				{ "온수 샤워 (수건 포함)", "5,000" },
			}
			for i, rr in rows do
				local y = bh / 2 - 0.85 - (i - 1) * 0.38
				txt(K, "RateItem", bw * 0.66, 0.26, d9 * CF(-bw * 0.15, y, 0.13), rr[1], SURF.white, nil, F.GothamMedium, nil, { align = "Left" })
				txt(K, "RatePrice", bw * 0.24, 0.26, d9 * CF(bw * 0.35, y, 0.13), rr[2], SURF.sun, nil, F.GothamBold, nil, { align = "Right" })
			end
			txt(K, "RateNote", bw * 0.9, 0.22, d9 * CF(0, -bh / 2 + 0.25, 0.13), "* 파고 1.5m 이상 · 강풍 주의보 시 강습 취소 (전액 환불)", rgb(170, 200, 210), nil, F.GothamMedium)
		end)
	end

	-- 10) 샤워실 옆: 장비 헹굼통 + 미끄럼 주의 · 샤워 안내 ------------------------------------------------------
	local shower = V:first("ShowerDoor")
	if shower then
		local wall = nearestWall(V, shower.c)
		local u = V:wallCoord(wall, shower.c)
		K:free(function()
			notice(K, wcf(V, wall, u + (if u < 0 then 3.4 else -3.4), 5.0, 0.02), 2.2, 1.5, "SHOWER · 샤워 안내", "온수 샤워 5,000원 (수건 포함)\n모래는 밖에서 털어 주세요\n이용 시간 09:00 - 19:00", SURF.sea)
			-- 문 테두리 (나무) + 손잡이
			local dc = wcf(V, wall, u, shower.c.Y, 0.08)
			for _, s in { -1, 1 } do
				K:plate("ShowerCasing", 0.18, shower.size.Y + 0.1, 0.08, dc * CF(s * (shower.size.X / 2 + 0.08), 0, -0.05), wood)
			end
			K:plate("ShowerCasing", shower.size.X + 0.34, 0.18, 0.08, dc * CF(0, shower.size.Y / 2 + 0.08, -0.05), wood)
		end)
		local tub = firstSpot(K, { wcf(V, wall, u + 4.0, 0, 1.1), wcf(V, wall, u + 5.2, 0, 1.1), wcf(V, "left", -(shower.c.Z + 4.2), 0, 1.1) }, V3(1.8, 1.6, 1.8), 0.1)
		if tub then
			K:vcyl("RinseTub", 1.3, 1.7, tub * CF(0, 0.65, 0), lk(rgb(40, 110, 200)))
			K:disc("RinseWater", 1.5, 0.04, tub * CF(0, 1.18, 0), gl(rgb(120, 190, 220), 0.3))
			K:ring("RinseRim", tub * CF(0, 1.3, 0) * ANG(PI / 2, 0, 0), 0.82, 0.12, 10, lk(rgb(30, 90, 170)))
			cable(K, { (tub * CF(0.6, 1.3, 0)).Position, (tub * CF(0.9, 1.6, -0.6)).Position, (tub * CF(0.9, 3.4, -1.05)).Position }, 0.1, lk(rgb(40, 160, 90)))
			txt(K, "RinseLabel", 1.2, 0.3, tub * CF(0, 0.75, 0.86), "장비 헹굼통", WHITE, nil, F.GothamBlack)
		end
		local wet = firstSpot(K, { wcf(V, wall, u + 2.6, 0, 2.6), wcf(V, wall, u + 1.4, 0, 3.0) }, V3(1.1, 2.2, 0.9), 0.05)
		if wet then
			local yel = lk(rgb(250, 200, 30))
			K:box("WetSignA", V3(1.0, 2.0, 0.06), wet * CF(0, 1.0, 0.3) * ANG(-0.25, 0, 0), yel)
			K:box("WetSignB", V3(1.0, 2.0, 0.06), wet * CF(0, 1.0, -0.3) * ANG(0.25, 0, 0), yel)
			txt(K, "WetSignText", 0.85, 1.2, wet * CF(0, 1.0, 0.34) * ANG(-0.25, 0, 0) * CF(0, 0, 0.035), "미끄럼\n주의\nCAUTION", rgb(30, 30, 30), nil, F.GothamBlack)
		end
	end

	-- 11) 천장: 행잉 롱보드 · 튜브 링 · 비치볼 · 실링팬 2 -----------------------------------------------------
	local hb = V:first("HangingBoard")
	if hb then
		local alongZ = hb.size.Z > hb.size.X
		local len = math.max(hb.size.X, hb.size.Z)
		local cf = CFrame.fromMatrix(hb.c, if alongZ then V3(1, 0, 0) else V3(0, 0, 1), if alongZ then V3(0, 0, -1) else V3(1, 0, 0), V3(0, -1, 0))
		K:free(function()
			surfboard(K, cf, len, 2.3, 0.26, { rail = rgb(244, 232, 206), deck = rgb(244, 232, 206), stringerC = rgb(120, 80, 50), stripe = SURF.coral, pad = false, fin = rgb(150, 110, 70) })
			for _, s in { -1, 1 } do
				local p = hb.c + (if alongZ then V3(0, 0, s * len * 0.3) else V3(s * len * 0.3, 0, 0))
				K:seg("HangRope", p + V3(-0.6, 0, 0), V3(p.X, V.H, p.Z), 0.05, rope)
				K:seg("HangRope", p + V3(0.6, 0, 0), V3(p.X, V.H, p.Z), 0.05, rope)
			end
		end)
		hideRec(K, hb)
		for _, r in recs(V, "Wire") do
			hideRec(K, r)
		end
	end
	local fr = V:first("FloatRing")
	if fr then
		local R = (math.max(fr.size.X, fr.size.Z) + (V:first("FloatRingInner") and math.max(V:first("FloatRingInner").size.X, V:first("FloatRingInner").size.Z) or 1.8)) / 4
		local tube = math.max(fr.size.X, fr.size.Z) / 2 - R
		K:free(function()
			local fcf = CF(fr.c) * ANG(PI / 2, 0, 0)
			for i = 0, 7 do
				K:ring("SwimRing", fcf, R, tube * 2, 2, lk(if i % 2 == 0 then rgb(250, 110, 140) else rgb(250, 250, 248), M.SmoothPlastic, { r = 0.15 }), i * PI / 4, (i + 1) * PI / 4)
			end
			K:seg("SwimRingRope", fr.c + V3(R, 0, 0), V3(fr.c.X + R, V.H, fr.c.Z), 0.04, rope)
		end)
		hideRec(K, fr)
		local fi = V:first("FloatRingInner")
		if fi then
			hideRec(K, fi)
		end
	end
	local bb = V:first("BeachBall")
	if bb then
		local d = bb.size.Y
		K:free(function()
			K:ball("BeachBallNew", d, CF(bb.c), lk(rgb(250, 250, 248), M.SmoothPlastic, { r = 0.1 }))
			for i, c in { rgb(230, 50, 50), rgb(40, 110, 220), rgb(250, 200, 40) } do
				K:disc("BeachBallGore", d * 1.005, d * 0.2, CF(bb.c) * ANG(0, i * PI / 3, 0) * ANG(PI / 2, 0, 0), lk(c, M.SmoothPlastic, { r = 0.1 }))
			end
			K:seg("BeachBallString", bb.c + V3(0, d / 2, 0), V3(bb.c.X, V.H, bb.c.Z), 0.03, rope)
		end)
		hideRec(K, bb)
	end
	-- 실링팬 (작동 토글 패널)
	local fans = {}
	local fanTry = { V3(-V.W * 0.22, 0, 3.3), V3(V.W * 0.22, 0, -4.2), V3(V.W * 0.22, 0, 3.3), V3(-V.W * 0.22, 0, -4.2), V3(0, 0, -4.2) }
	for _, p in fanTry do
		if #fans < 2 then
			local fx, fz = ceilSpot(K, p.X, p.Z, 2.2, 1.5)
			if fx and fz then
				local blades, center, glow = ceilingFan(K, V, fx, fz, 1.0)
				table.insert(fans, { blades = blades, center = center, glow = glow })
				Common.useCeil(K, fx, fz)
				if glow then
					K:light(glow, "PointLight", { Range = 14, Brightness = 0.7, Color = Look.warmLight })
				end
			end
		end
	end
	if #fans > 0 then
		local on = true
		local speed = 0.0
		local spinSets = {}
		for _, f in fans do
			local base = {}
			for _, p in f.blades do
				table.insert(base, { p = p, cf = p.CFrame })
			end
			table.insert(spinSets, { base = base, center = f.center })
		end
		local ang = 0
		Interact.anim(K, function(_t, dt)
			local target = if on then 1.1 else 0
			speed += (target - speed) * math.min(1, (dt or 0.1) * 1.5)
			if speed < 0.01 then
				return
			end
			ang += (dt or 0.1) * speed * PI * 2
			for _, s in spinSets do
				local rot = CFrame.new(s.center) * CFrame.Angles(0, ang, 0) * CFrame.new(-s.center)
				for _, b in s.base do
					if b.p.Parent then
						b.p.CFrame = rot * b.cf
					end
				end
			end
		end)
		local d = findPanel(K, V, { "right", "left", "back" }, 0.9, 3.8, 4.8, { -12.0, -8.0, 12.0, -14.0 })
		if d then
			local plate = K:plate("FanPanel", 0.8, 1.0, 0.05, d, lk(rgb(240, 238, 232)))
			wdisc(K, "FanDial", 0.4, 0.06, d * CF(0, 0.1, 0.05), lk(rgb(60, 60, 64)))
			txt(K, "FanLabel", 0.74, 0.18, d * CF(0, -0.36, 0.06), "선풍기 · FAN", rgb(50, 50, 54), nil, F.GothamBold)
			Interact.toggle(K, plate, {
				object = "실링팬",
				state = true,
				on = function(st: boolean)
					on = st
				end,
			})
		end
	end

	-- 조명: 보드 벽 · 웻슈트 벽 레일 조명 + 가운데 다운라이트
	if rackBase then
		local x = rackBase.max.X + 2.6
		litTrack(K, V3(x, 0, rackBase.min.Z + 1), V3(x, 0, rackBase.max.Z - 1), 4, V3(-1, -1.1, 0), 1)
	end
	if suitRail then
		local x = suitRail.c.X - 3.0
		litTrack(K, V3(x, 0, suitRail.min.Z + 0.5), V3(x, 0, suitRail.max.Z - 0.5), 4, V3(1, -1.1, 0), 1)
	end
	litDownlight(K, 0, 1.5)
	litDownlight(K, -6, -12)

	-- 12) 파도 정보판 (프롬프트 순환: 오늘 · 내일 · 수온 · 일몰) ----------------------------------------------------
	local wave = {
		"오늘 광안리  파고 0.6m · 주기 7s\n남동풍 3m/s · SUP 좋음",
		"내일 오전  파고 1.0m · 주기 8s\n서핑 초급 강습 추천",
		"수온 21°C · 기온 23°C\n3/2mm 웻슈트 권장",
		"일출 06:31 · 일몰 17:52\n선셋 SUP 투어 16:30 출발",
	}
	local wd = findPanel(K, V, { "left", "right", "back" }, 2.6, 3.4, 4.6, { 9.0, 12.0, 6.0, -9.0 })
	if wd then
		local plate = K:plate("WaveBoard", 2.6, 1.15, 0.08, wd, lk(rgb(24, 70, 96)))
		K:plate("WaveScreen", 2.4, 0.8, 0.02, wd * CF(0, -0.05, 0.08), lk(rgb(18, 40, 60), M.Neon))
		txt(K, "WaveTitle", 2.2, 0.22, wd * CF(0, 0.44, 0.09), "WAVE REPORT · 파도 정보", SURF.sun, nil, F.GothamBlack)
		local _, lab = txt(K, "WaveText", 2.3, 0.72, wd * CF(0, -0.06, 0.105), wave[1], rgb(210, 240, 250), nil, F.GothamMedium, 1.3)
		Interact.cycle(K, plate, wave, {
			object = "파도 정보",
			action = "다음 정보",
			on = function(_i, item)
				lab.Text = item
			end,
		})
	end

	-- 13) 바닥: 입구 모래 자국 · 고무 매트 · 수건 바구니 다시 짓기 · 큰 화분은 Common ---------------------------------
	local door = V.door
	if door then
		K:free(function()
			for i = 1, 9 do
				local x = door.x + (rnd(seed, i) - 0.5) * 5.5
				local z = V.z1 - 4.2 - rnd(seed, i + 30) * 6
				K:ell("SandPatch", V3(0.5 + rnd(seed, i + 3) * 0.9, 0.03, 0.4 + rnd(seed, i + 5) * 0.6), CF(x, 0.03, z) * ANG(0, rnd(seed, i + 7) * PI, 0), lk(SURF.sand, M.Sand))
			end
			txt(K, "SandFloorText", 3.2, 0.5, topCF(V3(door.x, 0.035, V.z1 - 3.4), V3(0, 0, -1)), "모래는 밖에서 털어 주세요", rgb(200, 180, 140), nil, F.GothamBlack, nil, { d = 0.01 })
		end)
	end
	local tbk = V:first("TowelBasket")
	if tbk then
		local p = CF(tbk.c.X, 0, tbk.c.Z)
		K:free(function()
			K:vcyl("TowelBasketNew", tbk.size.Y, math.min(tbk.size.X, tbk.size.Z), p * CF(0, tbk.size.Y / 2, 0), lk(rgb(196, 160, 104), M.Fabric))
			K:ring("TowelBasketRim", p * CF(0, tbk.size.Y, 0) * ANG(PI / 2, 0, 0), math.min(tbk.size.X, tbk.size.Z) / 2, 0.12, 10, lk(rgb(150, 116, 70), M.Fabric))
			local cols = { SURF.teal, SURF.sun, SURF.coral, SURF.sea, rgb(250, 250, 248) }
			for i, r in recs(V, "RolledTowel") do
				K:vcyl("RolledTowelNew", r.size.Y, r.size.X, CF(r.c), lk(cols[(i + seed) % #cols + 1], M.Fabric))
				K:disc("RolledTowelSpiral", r.size.X * 0.6, 0.02, CF(r.c + V3(0, r.size.Y / 2, 0)), lk(dk(cols[(i + seed) % #cols + 1], 0.2), M.Fabric))
			end
			txt(K, "TowelBasketTag", 1.4, 0.3, p * CF(0, tbk.size.Y * 0.6, math.min(tbk.size.X, tbk.size.Z) / 2 + 0.02), "비치타월 9,000", rgb(30, 30, 30), SURF.white, F.GothamBold)
		end)
		hideRec(K, tbk)
		for _, r in recs(V, "RolledTowel") do
			hideRec(K, r)
		end
	end
	-- 비치 파라솔 + 비치체어 2 (대여 진열)
	local pcands = {}
	for _, x in { 9.5, -8.5, 8.8, -9.2, 7.5 } do
		for _, z in { V.z1 - 4.4, V.z1 - 5.4, V.z1 - 6.4 } do
			table.insert(pcands, CF(x, 0, z) * ANG(0, if x > 0 then -0.5 else 0.5, 0))
		end
	end
	local pp = firstSpot(K, pcands, V3(3.2, 6.2, 2.6), 0.05)
	if pp then
		K:disc("ParasolBase", 0.9, 0.2, pp * CF(0, 0.1, 0), lk(rgb(60, 60, 64)))
		K:vcyl("ParasolPole", 5.6, 0.12, pp * CF(0, 2.9, 0), lk(rgb(240, 240, 236), M.Metal))
		K:ell("ParasolCanopy", V3(3.4, 1.2, 3.4), pp * CF(0, 5.45, 0), lk(SURF.white, M.Fabric))
		K:ell("ParasolCanopyTop", V3(2.0, 0.9, 2.0), pp * CF(0, 5.62, 0), lk(SURF.teal, M.Fabric))
		for i = 0, 7 do
			local a0, a1 = i * PI / 4, (i + 1) * PI / 4
			K:ring("ParasolValance", pp * CF(0, 5.42, 0) * ANG(PI / 2, 0, 0), 1.68, 0.22, 1, lk(if i % 2 == 0 then SURF.teal else SURF.white, M.Fabric), a0, a1)
			local a = a0
			K:seg("ParasolRib", (pp * CF(0, 6.0, 0)).Position, (pp * CF(math.cos(a) * 1.7, 5.42, math.sin(a) * 1.7)).Position, 0.04, lk(rgb(200, 200, 196), M.Metal))
		end
		K:ball("ParasolFinial", 0.2, pp * CF(0, 5.98, 0), lk(rgb(240, 240, 236)))
		for k, sx in { -0.75, 0.75 } do
			local cc = pp * CF(sx, 0, 0.35) * ANG(0, sx * 0.25, 0)
			local fab = lk(if k == 1 then SURF.coral else SURF.sun, M.Fabric)
			K:bar("ChairFrame", (cc * CF(-0.4, 0.05, 0.45)).Position, (cc * CF(-0.4, 1.9, -0.55)).Position, 0.07, 0.07, lk(rgb(200, 170, 120), M.Wood))
			K:bar("ChairFrame", (cc * CF(0.4, 0.05, 0.45)).Position, (cc * CF(0.4, 1.9, -0.55)).Position, 0.07, 0.07, lk(rgb(200, 170, 120), M.Wood))
			K:bar("ChairFrame", (cc * CF(-0.4, 0.05, -0.4)).Position, (cc * CF(-0.4, 0.75, 0.35)).Position, 0.07, 0.07, lk(rgb(200, 170, 120), M.Wood))
			K:bar("ChairFrame", (cc * CF(0.4, 0.05, -0.4)).Position, (cc * CF(0.4, 0.75, 0.35)).Position, 0.07, 0.07, lk(rgb(200, 170, 120), M.Wood))
			K:box("ChairSling", V3(0.78, 0.04, 1.3), cc * CF(0, 1.05, -0.05) * ANG(0.95, 0, 0), fab)
			K:box("ChairSlingStripe", V3(0.79, 0.045, 0.2), cc * CF(0, 1.05, -0.05) * ANG(0.95, 0, 0) * CF(0, 0, 0.3), lk(SURF.white, M.Fabric))
		end
		txt(K, "ParasolTag", 1.6, 0.5, pp * CF(0, 2.0, 0.08) * CF(0, 0, 0.07), "파라솔 · 비치체어\n대여 15,000원", rgb(30, 30, 30), SURF.white, F.GothamBold)
	end

	-- 플립플랍 보드 다시 짓기
	local ffb = V:first("FlipFlopBoard")
	if ffb then
		local wall = nearestWall(V, ffb.c)
		local u = V:wallCoord(wall, ffb.c)
		local w = math.max(ffb.size.X, ffb.size.Z)
		K:free(function()
			local d = wcf(V, wall, u, ffb.c.Y, 0.01)
			K:plate("FlipBoard", w, ffb.size.Y, 0.08, d, drift)
			txt(K, "FlipHeader", w * 0.9, 0.35, d * CF(0, ffb.size.Y / 2 + 0.25, 0.08), "FLIP FLOPS 12,000", rgb(40, 40, 44), SURF.white, F.GothamBlack)
			local cols = { SURF.coral, SURF.sea, SURF.sun, SURF.teal, rgb(30, 30, 32), rgb(250, 250, 248) }
			for i, r in recs(V, "FlipFlops") do
				local uu = V:wallCoord(wall, r.c)
				for _, s in { -0.17, 0.17 } do
					local fd = wcf(V, wall, uu + s, r.c.Y, 0.1)
					K:panel("FlipSole", 0.3, 1.05, 0.08, 0.14, fd, lk(cols[(i + seed) % #cols + 1], M.Rubber))
					K:bar("FlipStrap", (fd * CF(-0.12, -0.15, 0.1)).Position, (fd * CF(0, 0.32, 0.1)).Position, 0.05, 0.05, lk(rgb(250, 250, 248), M.Rubber))
					K:bar("FlipStrap", (fd * CF(0.12, -0.15, 0.1)).Position, (fd * CF(0, 0.32, 0.1)).Position, 0.05, 0.05, lk(rgb(250, 250, 248), M.Rubber))
				end
			end
		end)
		hideRec(K, ffb)
		for _, r in recs(V, "FlipFlops") do
			hideRec(K, r)
		end
	end
	local _ = S
end

--================================================================================================
-- 인형뽑기 · 포토 (play)
--================================================================================================
local NEONS = { rgb(255, 80, 180), rgb(80, 220, 255), rgb(255, 220, 60), rgb(140, 255, 120), rgb(200, 120, 255), rgb(255, 140, 60) }
local MACHINE_NAMES = { "곰돌이 천국", "말랑 오리", "토끼 마을", "젤리 캣", "쿠션 왕국", "펭귄 파티", "DOLL PARTY", "SWEET BEAR", "키링 뽑기", "LUCKY CLAW" }

-- 인형 하나 (pcf = 바닥, +Z = 얼굴). kind = bear | bunny | duck | cat | pig
local function plush(K: any, pcf: CFrame, s: number, kind: string, c: Color3)
	local fab = lk(c, M.Fabric)
	K:ell("PlushBody", V3(0.9, 0.8, 0.75) * s, pcf * CF(0, 0.38 * s, 0), fab)
	K:ell("PlushHead", V3(0.8, 0.72, 0.7) * s, pcf * CF(0, 0.95 * s, 0.05 * s), fab)
	if kind == "bunny" then
		for _, sx in { -1, 1 } do
			K:ell("PlushEar", V3(0.2, 0.6, 0.14) * s, pcf * CF(sx * 0.18 * s, 1.45 * s, 0), fab)
		end
	elseif kind == "cat" then
		for _, sx in { -1, 1 } do
			K:wedge("PlushEar", V3(0.08, 0.26, 0.24) * s, pcf * CF(sx * 0.24 * s, 1.36 * s, 0.05 * s) * ANG(0, PI / 2, 0), fab)
		end
	elseif kind == "duck" then
		K:ell("PlushBeak", V3(0.36, 0.14, 0.3) * s, pcf * CF(0, 0.9 * s, 0.42 * s), lk(rgb(255, 150, 40), M.Fabric))
	elseif kind == "pig" then
		K:cyl("PlushSnout", 0.08 * s, 0.3 * s, pcf * CF(0, 0.9 * s, 0.4 * s) * ANG(0, PI / 2, 0), lk(dk(c, 0.15), M.Fabric))
	else
		for _, sx in { -1, 1 } do
			K:ball("PlushEar", 0.26 * s, pcf * CF(sx * 0.3 * s, 1.28 * s, 0), fab)
		end
	end
	if s >= 1.0 then
		-- 큰 인형 (포토존): 앉은 다리 · 팔 · 배 · 주둥이 · 코 · 눈 · 리본
		local light = lk(lt(c, 0.4), M.Fabric)
		local dark = lk(rgb(30, 22, 20), M.SmoothPlastic, { r = 0.2 })
		for _, sx in { -1, 1 } do
			K:ell("PlushLeg", V3(0.34, 0.3, 0.52) * s, pcf * CF(sx * 0.25 * s, 0.15 * s, 0.32 * s), fab)
			K:ell("PlushPaw", V3(0.24, 0.24, 0.04) * s, pcf * CF(sx * 0.25 * s, 0.15 * s, 0.58 * s), light)
			K:ell("PlushArm", V3(0.26, 0.52, 0.3) * s, pcf * CF(sx * 0.42 * s, 0.5 * s, 0.14 * s) * ANG(0.35, 0, sx * 0.55), fab)
			K:ball("PlushEye", 0.09 * s, pcf * CF(sx * 0.15 * s, 1.0 * s, 0.37 * s), dark)
			if kind == "bear" then
				K:ball("PlushEarIn", 0.14 * s, pcf * CF(sx * 0.3 * s, 1.28 * s, 0.08 * s), light)
			end
			K:ell("PlushBow", V3(0.26, 0.18, 0.08) * s, pcf * CF(sx * 0.15 * s, 0.68 * s, 0.37 * s) * ANG(0, 0, sx * 0.3), lk(rgb(230, 40, 90), M.Fabric))
		end
		K:ball("PlushBowKnot", 0.1 * s, pcf * CF(0, 0.68 * s, 0.39 * s), lk(rgb(200, 30, 70), M.Fabric))
		K:ell("PlushBelly", V3(0.5, 0.48, 0.1) * s, pcf * CF(0, 0.36 * s, 0.35 * s), light)
		K:ell("PlushMuzzle", V3(0.34, 0.24, 0.2) * s, pcf * CF(0, 0.86 * s, 0.38 * s), light)
		K:ball("PlushNose", 0.1 * s, pcf * CF(0, 0.92 * s, 0.48 * s), dark)
	elseif s > 0.7 and not lowD(K) then
		K:box("PlushEyes", V3(0.36, 0.08, 0.02) * s, pcf * CF(0, 1.0 * s, 0.4 * s), lk(rgb(20, 20, 24)))
	end
end

-- 인형뽑기 기계 덮어 꾸미기 (원본 그대로, 겉면 패널 · 콘솔 · 마키 · 인형 추가)
local function clawSkin(K: any, V: any, base: any, idx: number, seed: number): { BasePart }
	local function near(nm: string): any
		local best, bd = nil, 1.7
		for _, r in recs(V, nm) do
			local d = nearXZ(r.c, base.c)
			if d < bd then
				best, bd = r, d
			end
		end
		return best
	end
	local glass, top, joy = near("ClawGlass"), near("ClawTop"), near("Joystick")
	local fdir = if joy then V3(joy.c.X - base.c.X, 0, joy.c.Z - base.c.Z) else V3(0, 0, 1)
	if math.abs(fdir.X) > math.abs(fdir.Z) then
		fdir = V3(math.sign(fdir.X), 0, 0)
	else
		fdir = V3(0, 0, math.sign(fdir.Z))
	end
	local mf = faceCF(V3(base.c.X, 0, base.c.Z), fdir)
	local hw = (if math.abs(fdir.X) > 0.5 then base.size.Z else base.size.X) / 2
	local hd = (if math.abs(fdir.X) > 0.5 then base.size.X else base.size.Z) / 2
	local by = base.max.Y
	local gy = if glass then glass.max.Y else by + 4.2
	local ty = if top then top.max.Y else gy + 0.8
	local acc = if top then top.part.Color else NEONS[idx % #NEONS + 1]
	local accL = lk(acc)
	local accD = lk(dk(acc, 0.35))
	local leds = {}
	K:free(function()
		-- 몸통: 앞 · 옆 패널 (그래픽 띠) + 크롬 걸레받이
		K:plate("ClawFrontPanel", hw * 2 - 0.1, by - 0.3, 0.03, mf * CF(0, 0.3 + (by - 0.3) / 2, hd + 0.01), lk(rgb(250, 248, 252)))
		K:plate("ClawFrontStripe", hw * 2 - 0.1, 0.5, 0.04, mf * CF(0, by - 0.6, hd + 0.01), accL)
		K:plate("ClawFrontStripe", hw * 2 - 0.1, 0.16, 0.04, mf * CF(0, by - 1.0, hd + 0.01), accD)
		K:plate("ClawKick", hw * 2 + 0.04, 0.3, 0.05, mf * CF(0, 0.15, hd + 0.01), Look.chrome)
		for _, sx in { -1, 1 } do
			local sc = mf * CF(sx * (hw + 0.01), 0, 0) * ANG(0, sx * PI / 2, 0)
			K:plate("ClawSidePanel", hd * 2 - 0.1, by - 0.3, 0.03, sc * CF(0, 0.3 + (by - 0.3) / 2, 0), accD)
			K:plate("ClawSideStar", 1.0, 1.0, 0.04, sc * CF(0, by * 0.55, 0) * ANG(0, 0, PI / 4), lk(lt(acc, 0.35)))
			K:plate("ClawSideStar", 1.0, 1.0, 0.04, sc * CF(0, by * 0.55, 0), lk(lt(acc, 0.35)))
		end
		-- 상품 출구 (왼쪽 아래) + 투명 덮개
		local cx = -hw + 0.75
		K:plate("ClawChute", 0.95, 0.8, 0.02, mf * CF(cx, 1.15, hd + 0.03), lk(rgb(20, 18, 24)))
		K:plate("ClawChuteFlap", 0.9, 0.75, 0.02, mf * CF(cx, 1.15, hd + 0.06), gl(rgb(220, 230, 240), 0.55))
		K:plate("ClawChuteFrame", 1.05, 0.08, 0.05, mf * CF(cx, 1.59, hd + 0.03), Look.chrome)
		txt(K, "ClawChuteLabel", 0.95, 0.2, mf * CF(cx, 1.78, hd + 0.05), "상품 출구", rgb(40, 40, 44), nil, F.GothamBlack)
		-- 지폐 투입구 · 동전 · 카드 (오른쪽)
		local bx = hw - 0.6
		K:plate("ClawBillPlate", 0.7, 0.9, 0.04, mf * CF(bx, 1.3, hd + 0.03), lk(rgb(30, 30, 34)))
		K:plate("ClawBillSlot", 0.5, 0.06, 0.02, mf * CF(bx, 1.55, hd + 0.07), lk(rgb(5, 5, 5)))
		K:plate("ClawBillLED", 0.12, 0.06, 0.02, mf * CF(bx - 0.18, 1.68, hd + 0.07), nl(rgb(80, 255, 120)))
		K:plate("ClawCoinSlot", 0.08, 0.3, 0.02, mf * CF(bx + 0.15, 1.15, hd + 0.07), Look.chrome)
		txt(K, "ClawBillText", 0.62, 0.2, mf * CF(bx, 0.98, hd + 0.075), "1,000원", WHITE, nil, F.GothamBold)
		-- 조작 콘솔 (조이스틱 받침 + 버튼 + 크레딧 표시)
		local cy = by
		K:box("ClawConsole", V3(hw * 2 - 0.1, 0.42, 0.7), mf * CF(0, cy - 0.21, hd + 0.35), lk(rgb(30, 28, 36)))
		K:box("ClawConsoleTop", V3(hw * 2 - 0.1, 0.04, 0.7), mf * CF(0, cy + 0.02, hd + 0.35), lk(rgb(20, 20, 24)))
		K:box("ClawConsoleLED", V3(hw * 2 - 0.1, 0.06, 0.04), mf * CF(0, cy - 0.38, hd + 0.71), nl(acc))
		if joy then
			local jl = mf:PointToObjectSpace(joy.c)
			K:ball("ClawJoyBall", 0.34, CF(joy.c.X, joy.max.Y + 0.12, joy.c.Z), lk(rgb(230, 30, 40), M.SmoothPlastic, { r = 0.1 }))
			K:disc("ClawJoyBoot", 0.4, 0.06, CF(joy.c.X, cy + 0.06, joy.c.Z), lk(rgb(10, 10, 12)))
			K:disc("ClawButton", 0.42, 0.12, mf * CF(jl.X + 0.8, cy + 0.08, hd + 0.35), lk(lt(acc, 0.2), M.Neon))
			K:disc("ClawButtonRing", 0.5, 0.06, mf * CF(jl.X + 0.8, cy + 0.04, hd + 0.35), Look.chrome)
		end
		K:plate("ClawCredit", 0.8, 0.26, 0.02, mf * CF(-0.75, cy - 0.21, hd + 0.71), lk(rgb(30, 10, 10)))
		txt(K, "ClawCreditText", 0.74, 0.2, mf * CF(-0.75, cy - 0.21, hd + 0.725), "CREDIT 0", rgb(255, 60, 50), nil, F.Arcade, 1.6)
		-- 유리 박스: 모서리 크롬 기둥 + 앞 기둥 LED + 안쪽 거울 · 조명
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				K:box("ClawPost", V3(0.1, gy - by, 0.1), mf * CF(sx * (hw - 0.02), (by + gy) / 2, sz * (hd - 0.02)), Look.chrome)
			end
			local p = K:box("ClawPostLED", V3(0.06, gy - by - 0.2, 0.06), mf * CF(sx * (hw - 0.02), (by + gy) / 2, hd + 0.05), nl(acc))
			table.insert(leds, p)
		end
		K:box("ClawMirror", V3(hw * 2 - 0.3, gy - by - 0.6, 0.03), mf * CF(0, (by + gy) / 2 + 0.2, -hd + 0.12), Look.mirror)
		K:box("ClawInnerLight", V3(hw * 2 - 0.4, 0.06, 0.2), mf * CF(0, gy - 0.12, 0), Look.lampCool)
		-- 갠트리 레일 (안쪽 위)
		for _, sz in { -1, 1 } do
			K:box("ClawGantry", V3(hw * 2 - 0.3, 0.08, 0.08), mf * CF(0, gy - 0.3, sz * (hd - 0.4)), Look.chrome)
		end
		-- 집게 발 3 (맵 Claw 아래)
		local claw = near("Claw")
		if claw then
			for i = 0, 2 do
				local a = i * PI * 2 / 3
				local tip = claw.c + V3(math.cos(a) * 0.32, -0.55, math.sin(a) * 0.32)
				K:seg("ClawProng", claw.c - V3(0, 0.2, 0), tip, 0.05, Look.chrome)
				K:seg("ClawProngTip", tip, tip + V3(-math.cos(a) * 0.12, -0.12, -math.sin(a) * 0.12), 0.05, Look.chrome)
			end
		end
		-- 인형 더미 (바닥 + 출구 둘레 칸막이)
		K:box("ClawPrizeFloor", V3(hw * 2 - 0.2, 0.12, hd * 2 - 0.2), mf * CF(0, by + 0.06, 0), lk(dk(acc, 0.5), M.Fabric))
		K:box("ClawDropWall", V3(1.0, 0.7, 0.05), mf * CF(cx, by + 0.35, hd - 1.0), gl(rgb(230, 240, 250), 0.5))
		K:box("ClawDropWall", V3(0.05, 0.7, 1.0), mf * CF(cx + 0.5, by + 0.35, hd - 0.5), gl(rgb(230, 240, 250), 0.5))
		local kinds = { "bear", "bunny", "duck", "cat", "pig" }
		local kind = kinds[(idx + seed) % #kinds + 1]
		local base1 = NEONS[(idx * 2) % #NEONS + 1]
		local pcols = { lt(base1, 0.55), lt(acc, 0.5), rgb(250, 246, 236), rgb(196, 150, 110), rgb(255, 214, 120) }
		local n = if lowD(K) then 3 else 6
		for i = 1, n do
			local px = -hw + 1.25 + rnd(seed + idx, i) * (hw * 2 - 1.6)
			local pz = -hd + 0.4 + rnd(seed + idx, i + 20) * (hd * 2 - 1.6)
			local sc = 0.55 + rnd(seed + idx, i + 40) * 0.3
			plush(K, mf * CF(px, by + 0.12 + (i % 2) * 0.25, pz) * ANG(0, (rnd(seed, i + idx) - 0.5) * 1.6, (rnd(seed, i + 7) - 0.5) * 0.5), sc, if i % 3 == 0 then kinds[(i + idx) % 5 + 1] else kind, pcols[(i + idx) % #pcols + 1])
		end
		-- 마키 (위 상자 앞면 글자) + 볏 간판 + 전구
		K:plate("ClawMarqueeFace", hw * 2 + 0.04, ty - gy + 0.04, 0.04, mf * CF(0, (gy + ty) / 2, hd + 0.01), lk(dk(acc, 0.55)))
		txt(K, "ClawMarquee", hw * 2 - 0.2, ty - gy - 0.15, mf * CF(0, (gy + ty) / 2, hd + 0.055), MACHINE_NAMES[(idx + seed) % #MACHINE_NAMES + 1], lt(acc, 0.4), nil, F.FredokaOne, 2.0)
		local crest = mf * CF(0, ty + 0.45, hd - 0.15)
		K:panel("ClawCrest", hw * 2 - 0.3, 0.9, 0.12, 0.42, crest, lk(rgb(250, 248, 252)))
		K:panel("ClawCrestInner", hw * 2 - 0.55, 0.65, 0.04, 0.3, crest * CF(0, 0, 0.12), accL)
		txt(K, "ClawCrestText", hw * 2 - 0.8, 0.45, crest * CF(0, 0, 0.17), string.format("No.%02d", idx), WHITE, nil, F.FredokaOne, 1.6)
		if not lowD(K) then
			for i = 0, 5 do
				local x = -hw + 0.45 + i * (hw * 2 - 0.9) / 5
				local b = K:ball("ClawBulbLED", 0.14, crest * CF(x, 0.48, 0.1), nl(rgb(255, 244, 210)))
				table.insert(leds, b)
			end
		end
		-- 요금 스티커 (유리 아래 왼쪽) · 결제 스티커
		txt(K, "ClawPriceSticker", 1.3, 0.36, mf * CF(-hw + 0.8, by + 0.35, hd + 0.03), "1회 1,000원\n5,000원 6회", rgb(30, 20, 20), rgb(255, 230, 60), F.GothamBlack)
		txt(K, "ClawPaySticker", 0.9, 0.24, mf * CF(hw - 0.6, by + 0.3, hd + 0.03), "현금 · 카드 · QR", WHITE, rgb(40, 120, 220), F.GothamBold)
	end)
	local ext = fdir * 0.8
	K:reserve(base.min - V3(0.1, 0, 0.1) + ext:Min(Vector3.zero), V3(base.max.X + 0.1, ty + 1, base.max.Z + 0.1) + ext:Max(Vector3.zero), "claw")
	return leds
end

-- 가챠 (캡슐 뽑기) 한 대: pcf = 바닥 (+Z = 앞), y = 받침 높이
local function gacha(K: any, pcf: CFrame, y: number, c: Color3, label: string, seed: number)
	-- 캡슐 뽑기 (등을 맞댄 2대가 겹치지 않게 깊이 0.74, pcf = 뒷면에서 0.37 앞 = 몸통 가운데)
	local b = pcf * CF(0, y, 0)
	local D = 0.74
	local fz = D / 2
	K:box("GachaBody", V3(1.4, 1.2, D), b * CF(0, 0.6, 0), lk(c, M.SmoothPlastic, { r = 0.08 }))
	K:box("GachaBodyTrim", V3(1.42, 0.06, D + 0.02), b * CF(0, 1.2, 0), lk(rgb(250, 250, 252)))
	K:box("GachaWindow", V3(1.24, 1.08, D - 0.1), b * CF(0, 1.77, 0), gl(rgb(236, 244, 250), 0.5))
	for _, sx in { -1, 1 } do
		K:box("GachaPost", V3(0.08, 1.08, 0.08), b * CF(sx * 0.66, 1.77, fz - 0.05), lk(c))
		K:box("GachaPost", V3(0.08, 1.08, 0.08), b * CF(sx * 0.66, 1.77, -fz + 0.05), lk(c))
	end
	K:box("GachaTop", V3(1.4, 0.14, D), b * CF(0, 2.38, 0), lk(c))
	K:ell("GachaDome", V3(1.1, 0.34, D * 0.86), b * CF(0, 2.45, 0), lk(lt(c, 0.35), M.SmoothPlastic, { r = 0.1 }))
	for i = 1, 6 do
		local x = -0.42 + ((i - 1) % 3) * 0.42 + (rnd(seed, i) - 0.5) * 0.08
		local yy = 1.42 + ((i - 1) // 3) * 0.36
		K:ball("Capsule", 0.32, b * CF(x, yy, (rnd(seed, i + 5) - 0.5) * 0.24), lk(NEONS[(i + seed) % #NEONS + 1], M.SmoothPlastic, { r = 0.15 }))
	end
	-- 앞면: 손잡이 (크롬 원판 + 막대) · 동전 투입구 · 상품 출구 덮개 · 라벨 · 가격
	K:disc("GachaKnob", 0.46, 0.08, b * CF(0.28, 0.72, fz + 0.04) * ANG(PI / 2, 0, 0), Look.chrome)
	K:box("GachaKnobBar", V3(0.38, 0.08, 0.08), b * CF(0.28, 0.72, fz + 0.1), lk(rgb(40, 40, 44)))
	K:plate("GachaCoinSlot", 0.2, 0.26, 0.02, CFrame.lookAt((b * CF(0.28, 1.0, fz)).Position, (b * CF(0.28, 1.0, fz + 1)).Position) * ANG(0, PI, 0), lk(rgb(30, 30, 34), M.Metal))
	K:box("GachaExit", V3(0.42, 0.32, 0.06), b * CF(-0.35, 0.3, fz + 0.03), lk(rgb(30, 30, 34)))
	K:box("GachaExitFlap", V3(0.38, 0.14, 0.03), b * CF(-0.35, 0.4, fz + 0.065), gl(rgb(220, 230, 240), 0.4))
	txt(K, "GachaLabel", 1.25, 0.26, b * CF(0, 1.04, fz + 0.005), label, WHITE, nil, F.GothamBlack)
	txt(K, "GachaPrice", 0.5, 0.18, b * CF(-0.35, 0.62, fz + 0.005), "3,000", rgb(255, 230, 60), nil, F.GothamBlack)
end

local function buildPlay(K: any, V: any, S: any)
	pcall(windowSignBacks, K, V)
	pcall(twoSidedSigns, K, V)
	local seed = hashStr(V.key or V.name or "play")
	local H = V.H

	-- 1) 인형뽑기 기계 꾸미기 ------------------------------------------------------------------------
	local bases = recs(V, "ClawBase")
	table.sort(bases, function(p, q)
		if math.abs(p.c.Z - q.c.Z) > 1 then
			return p.c.Z < q.c.Z
		end
		return p.c.X < q.c.X
	end)
	local allLeds = {}
	for i, b in bases do
		local ok, res = pcall(clawSkin, K, V, b, i, seed)
		if ok then
			for _, p in res do
				table.insert(allLeds, p)
			end
		else
			K:note("claw skin error: " .. tostring(res))
		end
	end
	-- 전구 · LED 순환 (프롬프트 없는 애니)
	local ledBase = {}
	for _, p in allLeds do
		table.insert(ledBase, { p = p, c = p.Color })
	end
	Interact.anim(K, function(t)
		local ph = math.floor(t * 4)
		for i, l in ledBase do
			if l.p.Parent then
				if l.p.Name == "ClawBulbLED" then
					l.p.Transparency = if (i + ph) % 3 == 0 then 0.75 else 0
				else
					local k = (math.floor(t * 0.5) + i) % 4
					l.p.Color = if k == 0 then WHITE else l.c
				end
			end
		end
	end)

	-- 2) 지폐 교환기 (앞판 꾸미기) ------------------------------------------------------------------------
	local cm = V:first("ChangeMachine")
	if cm then
		local scr = V:first("ChangeScreen")
		local fdir = if scr then V3(scr.c.X - cm.c.X, 0, scr.c.Z - cm.c.Z) else V3(0, 0, 1)
		if math.abs(fdir.X) > math.abs(fdir.Z) then
			fdir = V3(math.sign(fdir.X), 0, 0)
		else
			fdir = V3(0, 0, math.sign(fdir.Z))
		end
		local mf = faceCF(V3(cm.c.X, 0, cm.c.Z), fdir)
		local hw = (if math.abs(fdir.X) > 0.5 then cm.size.Z else cm.size.X) / 2
		local hd = (if math.abs(fdir.X) > 0.5 then cm.size.X else cm.size.Z) / 2
		local h = cm.size.Y
		K:free(function()
			K:plate("ChangerHeaderBack", hw * 2, 0.7, 0.04, mf * CF(0, h - 0.4, hd + 0.01), lk(rgb(230, 40, 60)))
			txt(K, "ChangerHeader", hw * 2 - 0.2, 0.5, mf * CF(0, h - 0.4, hd + 0.055), "지폐 교환기", WHITE, nil, F.GothamBlack)
			K:plate("ChangerBillSlot", 1.0, 0.5, 0.05, mf * CF(0, 3.3, hd + 0.01), lk(rgb(20, 20, 24)))
			K:plate("ChangerBillMouth", 0.8, 0.07, 0.02, mf * CF(0, 3.35, hd + 0.06), lk(rgb(0, 0, 0)))
			K:plate("ChangerBillLED", 0.8, 0.05, 0.02, mf * CF(0, 3.2, hd + 0.06), nl(rgb(80, 255, 120)))
			txt(K, "ChangerBillText", 1.6, 0.5, mf * CF(0, 2.65, hd + 0.03), "10,000원 · 5,000원\n→ 1,000원권 교환", rgb(30, 30, 34), rgb(250, 248, 240), F.GothamBold)
			K:box("ChangerTray", V3(1.2, 0.5, 0.35), mf * CF(0, 1.2, hd + 0.17), lk(rgb(40, 40, 44), M.Metal))
			K:box("ChangerTrayInner", V3(1.0, 0.2, 0.3), mf * CF(0, 1.1, hd + 0.2), lk(rgb(15, 15, 18)))
			txt(K, "ChangerTrayText", 1.2, 0.2, mf * CF(0, 1.62, hd + 0.03), "지폐 나오는 곳", rgb(230, 230, 230), nil, F.GothamMedium)
			txt(K, "ChangerCall", 1.7, 0.3, mf * CF(0, 0.6, hd + 0.03), "고장 · 환불 문의 010-0000-0000", rgb(255, 230, 60), rgb(30, 30, 34), F.GothamBold)
		end)
		K:reserve(cm.min - V3(0.1, 0, 0.1), cm.max + V3(0.1, 0.5, 0.1) + fdir * 0.6, "changer")
	end

	-- 3) 바닥: 어두운 오락실 카펫 + 무늬 -----------------------------------------------------------------------
	K:free(function()
		K:box("ArcadeCarpet", V3(V.W - 0.04, 0.02, V.D - 0.04), CF((V.x0 + V.x1) / 2, 0.012, (V.z0 + V.z1) / 2), lk(rgb(34, 26, 60), M.Fabric))
		local n = if lowD(K) then 18 else 44
		for i = 1, n do
			local x = V.x0 + 0.6 + rnd(seed, i) * (V.W - 1.2)
			local z = V.z0 + 0.6 + rnd(seed, i + 100) * (V.D - 1.2)
			local c = NEONS[(i + seed) % #NEONS + 1]
			local k = i % 3
			if k == 0 then
				K:disc("CarpetDot", 0.5 + rnd(seed, i + 200) * 0.5, 0.01, CF(x, 0.026, z), lk(c, M.Fabric))
			elseif k == 1 then
				K:box("CarpetSquiggle", V3(0.9, 0.01, 0.14), CF(x, 0.026, z) * ANG(0, rnd(seed, i + 300) * PI, 0), lk(c, M.Fabric))
			else
				K:box("CarpetStar", V3(0.4, 0.01, 0.4), CF(x, 0.026, z) * ANG(0, PI / 4, 0), lk(c, M.Fabric))
			end
		end
	end)

	-- 4) 천장: 무지개 LED 띠 (가로 3줄 + 테두리) · 색 불빛 ------------------------------------------------------
	local strips = {}
	K:free(function()
		local y = H - 0.12
		local zs = { V.z0 + V.D * 0.25, V.z0 + V.D * 0.5, V.z0 + V.D * 0.75 }
		for i, z in zs do
			local p = K:box("CeilLEDStrip", V3(V.W - 2.0, 0.08, 0.16), CF((V.x0 + V.x1) / 2, y, z), nl(NEONS[i]))
			table.insert(strips, p)
			K:box("CeilLEDChannel", V3(V.W - 1.9, 0.06, 0.3), CF((V.x0 + V.x1) / 2, y + 0.06, z), lk(rgb(30, 30, 36), M.Metal))
		end
		-- 벽 위 띠 (뒷벽 · 양옆)
		for _, wn in { "back", "left", "right" } do
			local w = V.walls[wn]
			local p = K:plate("WallLEDStrip", w.b - w.a - 0.4, 0.1, 0.06, V:wall(wn, (w.a + w.b) / 2, H - 0.35, 0.01), nl(rgb(255, 80, 180)))
			table.insert(strips, p)
		end
	end)
	-- 색 불빛 2 (분홍 · 하늘) + 흰 다운라이트 2
	for i, x in { V.x0 + V.W * 0.3, V.x0 + V.W * 0.7 } do
		local holder = nil
		K:free(function()
			holder = K:disc("MoodLightLens", 0.5, 0.04, CF(x, H - 0.05, (V.z0 + V.z1) / 2), nl(if i == 1 then rgb(255, 120, 200) else rgb(120, 220, 255)))
		end)
		if holder then
			K:light(holder, "PointLight", { Range = 20, Brightness = 0.9, Color = if i == 1 then rgb(255, 140, 210) else rgb(140, 220, 255) })
		end
	end
	litDownlight(K, V.x0 + V.W * 0.25, V.z0 + 2.6, Look.neutralLight, 16)
	litDownlight(K, V.x0 + V.W * 0.75, V.z0 + 2.6, Look.neutralLight, 16)

	-- 벽 마감: 기계 위 띠 (y 8.0 위) + 앞쪽 옆벽 (기계 앞 ~ 유리) 를 짙은 보라 별무늬 벽지로
	K:free(function()
		local wall = lk(rgb(46, 30, 72))
		for _, wn in { "back", "left", "right" } do
			local w = V.walls[wn]
			local d = V:wall(wn, (w.a + w.b) / 2, (8.05 + H) / 2, 0.005)
			K:plate("WallBand", w.b - w.a - 0.05, H - 8.05, 0.02, d, wall)
			for i = 0, math.floor((w.b - w.a) / 1.4) - 1 do
				local x = -(w.b - w.a) / 2 + 0.7 + i * 1.4
				K:plate("WallStar", 0.18, 0.18, 0.025, d * CF(x, (rnd(seed, i + #wn) - 0.5) * 0.9, 0) * ANG(0, 0, PI / 4), lk(NEONS[(i + #wn) % #NEONS + 1]))
			end
		end
		for _, wn in { "left", "right", "back" } do
			local w = V.walls[wn]
			K:plate("WallPaper", w.b - w.a - 0.05, 8.05 - 0.45, 0.02, V:wall(wn, (w.a + w.b) / 2, (0.45 + 8.05) / 2, 0.003), wall)
			if wn ~= "back" then
				for _, s in V:spans(wn, 3.6, 4.0, 0.6) do
					if s[2] - s[1] > 0.8 then
						K:plate("WallPaperRail", s[2] - s[1], 0.08, 0.04, V:wall(wn, (s[1] + s[2]) / 2, 3.8, 0.005), nl(rgb(80, 220, 255)))
					end
				end
			end
		end
	end)

	-- 5) 뒷벽 위 네온 간판 + 옆벽 안내문 ---------------------------------------------------------------------
	local topMax = 0
	for _, r in recs(V, "ClawTop") do
		topMax = math.max(topMax, r.max.Y)
	end
	local signY = math.min(H - 0.75, topMax + 1.25)
	K:free(function()
		local wb = V.walls.back
		local d = V:wall("back", (wb.a + wb.b) / 2 - 1.0, signY, 0.02)
		K:plate("NeonBacker", 13.0, 1.1, 0.04, d, lk(rgb(26, 18, 40)))
		local p = txt(K, "NeonSignLED", 12.4, 0.85, d * CF(0, 0, 0.06), "♥ 인형뽑기 천국 ♥  CLAW 24H  ·  매일 신상 입고", rgb(255, 120, 200), nil, F.FredokaOne, 2.4)
		table.insert(strips, p)
		K:light(p, "SurfaceLight", { Face = Enum.NormalId.Front, Range = 10, Brightness = 0.8, Angle = 120, Color = rgb(255, 120, 200) })
		useWall(K, "back", (wb.a + wb.b) / 2 - 7.6, (wb.a + wb.b) / 2 + 5.6, signY - 0.6, signY + 0.6)
	end)
	local notices = {
		{ "무인 운영 안내", "24시간 무인 운영 · CCTV 녹화 중\n기계를 흔들거나 두드리지 마세요\n고장 · 환불 010-0000-0000", rgb(40, 120, 220) },
		{ "청소년 이용 안내", "청소년 출입 09:00 - 22:00\n(게임산업진흥법)\n경품 소비자가 1만 원 이하", rgb(230, 60, 90) },
	}
	local ni = 0
	for _, wn in { "left", "right" } do
		ni += 1
		local nt = notices[ni]
		if nt then
			local w2, d2 = Common.wallSpot(K, { wn, "back" }, 2.4, signY - 0.8, signY + 0.8, 0)
			if w2 and d2 then
				K:free(function()
					notice(K, d2 * CF(0, 0, 0.02), 2.3, 1.4, nt[1], nt[2], nt[3])
				end)
			end
		end
	end

	-- 6) 가운데 섬: 가챠 4대 (양면) + 안내 화면 · LED 모드 ---------------------------------------------------
	local front = V.door and V.door.z or V.z1
	local islandZ = (V.z0 + 3.2 + 2.6 + front - 4.6) / 2
	local icf = CF(0, 0, islandZ)
	local labels = { "말랑 키링", "미니 피규어", "럭키 스티커", "랜덤 뱃지" }
	local islandOK = K:spot(icf, V3(3.4, 5.6, 1.6), 0.2)
	local infoPart, ledPart = nil, nil
	if islandOK then
		K:box("IslandPlinth", V3(3.3, 0.5, 1.5), icf * CF(0, 0.25, 0), lk(rgb(250, 248, 252)))
		K:box("IslandPlinthLED", V3(3.32, 0.06, 1.52), icf * CF(0, 0.08, 0), nl(rgb(255, 80, 180)))
		for k, sx in { -0.8, 0.8 } do
			gacha(K, icf * CF(sx, 0, 0.375), 0.5, NEONS[(k + seed) % #NEONS + 1], labels[k], seed + k)
			gacha(K, icf * CF(-sx, 0, -0.375) * ANG(0, PI, 0), 0.5, NEONS[(k + 2 + seed) % #NEONS + 1], labels[k + 2], seed + k + 2)
		end
		-- 위 안내 화면 (문 쪽)
		-- 양쪽 기둥 2개 (가운데 기둥이 뒷면 글자를 가리지 않게) + 위 캡
		for _, sx in { -1, 1 } do
			K:box("InfoPost", V3(0.12, 2.9, 0.12), icf * CF(sx * 1.26, 3.1 + 1.45, 0.08), lk(rgb(30, 30, 34), M.Metal))
			K:box("InfoPostCap", V3(0.18, 0.06, 0.18), icf * CF(sx * 1.26, 6.03, 0.08), lk(rgb(255, 80, 180), M.Neon))
		end
		local ib = icf * CF(0, 4.55, 0.16)
		K:box("InfoBezel", V3(2.4, 1.4, 0.12), ib, lk(rgb(24, 24, 28)))
		infoPart = K:box("InfoScreen", V3(2.25, 1.25, 0.02), ib * CF(0, 0, 0.07), lk(rgb(20, 16, 40), M.Neon))
		K:box("InfoBezelBack", V3(2.4, 1.4, 0.04), ib * CF(0, 0, -0.08), lk(rgb(30, 22, 44)))
		local bk = ib * CF(0, 0, -0.1) * ANG(0, PI, 0)
		K:plate("InfoBackRim", 2.3, 0.06, 0.02, bk * CF(0, 0.62, 0), nl(rgb(255, 80, 180)))
		K:plate("InfoBackRim", 2.3, 0.06, 0.02, bk * CF(0, -0.62, 0), nl(rgb(80, 220, 255)))
		txt(K, "InfoBackLogo", 2.1, 0.6, bk * CF(0, 0.15, 0.02), "♥ 인형뽑기 ♥", rgb(255, 140, 210), nil, F.FredokaOne, 2.0)
		txt(K, "InfoBackSub", 2.1, 0.3, bk * CF(0, -0.32, 0.02), "CLAW 24H · 오늘도 득템!", rgb(150, 230, 255), nil, F.GothamBlack, 1.6)
		local lb = icf * CF(1.66, 1.2, 0) * ANG(0, PI / 2, 0)
		ledPart = K:box("LEDModeButton", V3(0.9, 0.6, 0.1), lb * CF(0, 0, 0.05), lk(rgb(30, 30, 34)))
		txt(K, "LEDModeLabel", 0.8, 0.5, lb * CF(0, 0, 0.105), "LED\nMODE", rgb(255, 220, 60), nil, F.GothamBlack, 1.3)
	end
	if infoPart then
		local pages = {
			"이용 방법\n① 1,000원권 투입 (5,000원 6회)\n② 조이스틱으로 위치 맞추기\n③ 버튼 = 집게 내리기",
			"오늘의 신상 입고\n곰돌이 쿠션 · 말랑 오리\n토끼 키링 · 젤리 캣",
			"득템 인증 이벤트\n인스타 #광안리인형뽑기\n인증하면 1회 무료!",
			"고장 · 환불 문의\n010-0000-0000\n24시간 무인 운영 · CCTV 녹화",
		}
		local ib = icf * CF(0, 4.55, 0.16)
		local _, lab2 = txt(K, "InfoText", 2.1, 1.1, ib * CF(0, 0, 0.085), pages[1], rgb(250, 240, 255), nil, F.GothamBold, 1.4)
		if promptOK(K, V, (ib * CF(0, 0, 0.1)).Position) then
			Interact.cycle(K, infoPart, pages, {
				object = "이용 안내",
				action = "다음 안내",
				on = function(_i, item)
					lab2.Text = item
				end,
			})
		end
	end
	if ledPart then
		local modes = {
			{ name = "RAINBOW", cols = NEONS },
			{ name = "PINK", cols = { rgb(255, 80, 180), rgb(255, 140, 210), rgb(255, 60, 140) } },
			{ name = "OCEAN", cols = { rgb(80, 220, 255), rgb(60, 140, 255), rgb(120, 255, 220) } },
			{ name = "OFF", cols = {} },
		}
		local base = {}
		for _, p in strips do
			table.insert(base, { p = p, c = p.Color })
		end
		local mode = 1
		Interact.anim(K, function(t)
			local m = modes[mode]
			if m.name ~= "RAINBOW" then
				return
			end
			for i, b in base do
				if b.p.Parent and b.p:IsA("BasePart") and b.p.Name ~= "NeonSignLED" then
					b.p.Color = Color3.fromHSV((t * 0.08 + i * 0.13) % 1, 0.75, 1)
				end
			end
		end)
		if promptOK(K, V, V.cf:PointToObjectSpace(ledPart.Position)) then
			Interact.cycle(K, ledPart, modes, {
				object = "천장 LED",
				action = "모드 바꾸기",
				on = function(i, m)
					mode = i
					for j, b in base do
						if b.p.Parent and b.p.Name ~= "NeonSignLED" then
							if m.name == "OFF" then
								b.p.Material = M.SmoothPlastic
								b.p.Color = rgb(40, 40, 46)
							else
								b.p.Material = M.Neon
								if #m.cols > 0 and m.name ~= "RAINBOW" then
									b.p.Color = m.cols[(j - 1) % #m.cols + 1]
								else
									b.p.Color = b.c
								end
							end
						end
					end
				end,
			})
		end
	end

	-- 7) 앞쪽 모서리: 득템 인증 폴라로이드 보드 · 벤치 · 큰 곰인형 ---------------------------------------------------
	for side, wn in { "left", "right" } do
		local w = V.walls[wn]
		-- 앞 유리 쪽 끝 구간 (기계 앞)
		local u = if wn == "left" then -(V.z1 - 3.2) else (V.z1 - 3.2)
		local _ = w
		local spans = V:spans(wn, 4.0, 6.6, 0.4)
		local okSpan = false
		-- 앞쪽 끝 구간 (창 띠 · 기계 사이) 가운데로
		local best = nil
		for _, s in spans do
			local mid = (s[1] + s[2]) / 2
			if s[2] - s[1] >= 1.7 and (best == nil or math.abs(mid - u) < math.abs(best - u)) then
				best = mid
			end
		end
		if best and math.abs(best - u) < 3 then
			u = best
			okSpan = true
		end
		local d = V:wall(wn, u, 5.2, 0.02)
		if okSpan then
			K:free(function()
				if side == 1 then
					K:plate("CorkBoard", 1.6, 2.2, 0.06, d, lk(rgb(196, 160, 112), M.Fabric))
					K:plate("CorkFrame", 1.7, 0.08, 0.08, d * CF(0, 1.1, 0), lk(rgb(250, 248, 252)))
					txt(K, "CorkTitle", 1.5, 0.3, d * CF(0, 0.85, 0.07), "오늘의 득템 ♥", rgb(230, 40, 120), rgb(255, 250, 252), F.FredokaOne)
					for i = 0, 5 do
						local px = -0.48 + (i % 3) * 0.48
						local py = 0.25 - (i // 3) * 0.75
						local pd = d * CF(px, py, 0.07) * ANG(0, 0, (rnd(seed, i) - 0.5) * 0.35)
						K:plate("Polaroid", 0.5, 0.6, 0.01, pd, lk(rgb(252, 252, 250)))
						K:plate("PolaroidPhoto", 0.42, 0.42, 0.012, pd * CF(0, 0.06, 0), lk(lt(NEONS[(i + seed) % #NEONS + 1], 0.3)))
						K:plate("PolaroidPin", 0.08, 0.08, 0.02, pd * CF(0, 0.26, 0.01), lk(rgb(230, 40, 60)))
					end
				else
					notice(K, d, 1.6, 1.3, "결제 안내", "1,000원권 · 500원 동전\n카드 · 삼성페이 · QR\n지폐 교환기 이용", rgb(255, 160, 40))
				end
			end)
		end
	end
	-- 큰 곰 인형 (앞 모서리 바닥, 자리가 비면)
	for _, sx in { -1, 1 } do
		local p = firstSpot(K, {
			CF(sx * (V.W / 2 - 6.0), 0, V.z1 - 3.2) * ANG(0, -sx * (PI - 0.6), 0),
			CF(sx * (V.W / 2 - 6.6), 0, V.z1 - 3.5) * ANG(0, -sx * (PI - 0.6), 0),
			CF(sx * (V.W / 2 - 4.6), 0, V.z1 - 3.0) * ANG(0, -sx * (PI - 0.6), 0),
		}, V3(1.8, 2.6, 1.6), 0.1)
		if p then
			plush(K, p, 1.6, "bear", if sx < 0 then rgb(196, 150, 110) else rgb(250, 200, 220))
			txt(K, "BigBearTag", 0.8, 0.26, p * CF(0, 0.7, 0.62), "포토존 ♥", rgb(230, 40, 120), rgb(255, 250, 252), F.FredokaOne)
		end
	end
	local _ = S
end

--================================================================================================
-- 스타일 (Common 에 줄 S)
--================================================================================================
function T.style(V: any): any
	local t = V.type
	local gw = V.kind == "gwshop"
	if t == "salon" then
		return {
			chair = false,
			stool = false,
			table = false,
			counter = false,
			base = if gw then false else Look.white,
			lower = false,
			clock = not gw,
			license = not gw,
			cctv = not gw,
			floor = { look = Look.of(214, 210, 202, M.SmoothPlastic, { r = 0.05 }), tile = 2.4, grout = Look.of(186, 182, 174) },
			mat = { look = Look.of(60, 52, 54, M.Fabric), text = "물결 HAIR" },
			ceiling = { crown = Look.white },
			pendant = { shade = "dome", look = Look.of(190, 156, 96, M.Metal, { r = 0.12 }), dia = 1.3 },
			plants = { "monstera" },
			lights = { kind = "downlight", n = 6, color = Look.warmLight, glow = Look.lampWarm },
		}
	end
	if t == "clothing" then
		return {
			chair = false,
			stool = false,
			table = false,
			counter = false,
			base = if gw then false else Look.white,
			lower = false,
			clock = not gw,
			license = not gw,
			cctv = not gw,
			ceiling = { crown = Look.white },
			plants = { "olive", "ficus" },
			mat = false,
			lights = { kind = "downlight", n = 8, color = Look.neutralLight, glow = Look.lampNeutral },
		}
	end
	if t == "surf" then
		return {
			chair = false,
			stool = false,
			table = false,
			counter = false,
			base = if gw then false else Look.of(120, 90, 60, M.Wood),
			lower = false,
			clock = true,
			license = not gw,
			cctv = not gw,
			ceiling = {},
			plants = { "monstera", "bamboo" },
			mat = false,
			lights = { kind = "downlight", n = 6, color = Look.warmLight, glow = Look.lampWarm },
		}
	end
	if t == "play" then
		return {
			chair = false,
			stool = false,
			table = false,
			counter = false,
			base = Look.of(30, 26, 40),
			lower = false,
			clock = false,
			license = false,
			cctv = false,
			ceiling = { skin = Look.of(22, 18, 34) },
			mat = { look = Look.of(40, 30, 60, M.Fabric), text = "CLAW 24H" },
			lights = { kind = "none" },
		}
	end
	-- gym (T_gym 이 덮어씀) · 기타
	return {
		chair = { style = "padded", frame = Look.blackMetal, seat = Look.fabricGrey },
		table = { top = Look.oak, base = Look.blackMetal },
		counter = { front = "panel", frontL = Look.white, topL = Look.marbleWhite },
		lights = { kind = "downlight" },
	}
end

--================================================================================================
-- 빌드
--================================================================================================
local BUILDERS: { [string]: (any, any, any) -> () } = {
	salon = buildSalon,
	clothing = buildClothing,
	surf = buildSurf,
	play = buildPlay,
}

local PLAQUES: { [string]: { any } } = {
	salon = { "영업시간 · OPEN", "10:00 - 20:00 (마지막 접수 19:00)\n매주 화요일 정기 휴무\n카드 · 동백전 · 제로페이 OK", SALON.rose },
	clothing = { "OPEN 11:00 - 22:00", "연중무휴 · 교환 7일 이내 (영수증)\n택 제거 · 세탁 후 교환 불가\n카드 · 동백전 · 네이버페이", rgb(44, 58, 92) },
	surf = { "영업시간 · OPEN", "08:00 - 19:00 (7-8월 06:30 오픈)\n기상 악화 시 강습 · 대여 중단\n카드 · 동백전 · 계좌이체", rgb(0, 150, 160) },
}

function T.build(K: any, V: any, S: any)
	local b = BUILDERS[V.type]
	if b then
		b(K, V, S)
	end
	-- 남은 벽 자리에 영업시간 · 결제 명판 (다른 진열이 자리를 다 잡은 뒤)
	local pq = PLAQUES[V.type]
	if pq then
		local ok, err = pcall(hoursPlaque, K, V, pq[1], pq[2], pq[3])
		if not ok then
			K:note("plaque error: " .. tostring(err))
		end
	end
end

return T
