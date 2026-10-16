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
		K:wedge("Cape", V3(1.2, 2.7, 0.08), cape * CF(0, -1.35, 0.22) * ANG(0, PI, 0), lk(SALON.ink, M.Fabric))
		K:box("CapeNeck", V3(0.5, 0.12, 0.1), cape * CF(0, -0.02, 0.22), lk(SALON.ink, M.Fabric))
	end)
	local _ = seed
end

-- 샴푸대 (의자 + 도기 볼 + 수전). seatRec = WashSeat, look = 앉은 사람이 보는 방향
local function shampooUnit(K: any, V: any, seat: any, idx: number)
	local f = seat.lcf.LookVector
	local pcf = faceCF(V3(seat.c.X, 0, seat.c.Z), f)
	local top = seat.max.Y
	local w = math.min(seat.size.X, seat.size.Z) + 0.0
	local leather = lk(SALON.leather, M.Leather)
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
			local bowl = ccf * CF(0, ch + 0.12, 0.05)
			K:ell("BasinBowl", V3(1.9, 0.75, 1.55), bowl, lk(rgb(250, 250, 248), M.SmoothPlastic, { r = 0.08 }))
			K:ell("BasinBowlInner", V3(1.55, 0.06, 1.2), bowl * CF(0, 0.34, -0.02), lk(rgb(214, 218, 220), M.SmoothPlastic, { r = 0.12 }))
			K:disc("BasinDrain", 0.16, 0.02, bowl * CF(0, 0.38, -0.05), Look.chrome)
			-- 목받침 (볼 앞 고무 패드)
			K:cyl("BasinNeckRest", 0.7, 0.24, bowl * CF(0, 0.3, 0.72), Look.rubber)
			-- 구즈넥 수전 + 레버 + 핸드 샤워
			local tap = ccf * CF(0.25, ch + 0.12, -cdp / 2 + 0.25)
			K:vcyl("TapBody", 0.7, 0.16, tap * CF(0, 0.35, 0), Look.chrome)
			K:ring("TapNeck", tap * CF(0, 0.7, 0.3) * ANG(0, PI / 2, 0), 0.3, 0.1, 5, Look.chrome, PI * 0.5, PI * 1.5)
			K:box("TapLever", V3(0.36, 0.06, 0.08), tap * CF(0.18, 0.5, 0) * ANG(0, 0, 0.25), Look.chrome)
			K:vcyl("ShowerHolder", 0.3, 0.14, tap * CF(-0.55, 0.15, 0), Look.chrome)
			K:vcyl("ShowerHead", 0.5, 0.14, tap * CF(-0.55, 0.45, 0) * ANG(0.15, 0, 0), Look.chrome)
			cable(K, { (tap * CF(-0.55, 0.15, 0)).Position, (tap * CF(-0.35, 0.02, 0.1)).Position, (tap * CF(0, 0.02, 0.05)).Position }, 0.06, Look.chrome)
			-- 샴푸 · 린스 · 트리트먼트 펌프 (뒤 선반)
			local sh = ccf * CF(-0.75, ch + 0.12, -cdp / 2 + 0.25)
			local cols = { rgb(36, 86, 60), rgb(240, 236, 228), rgb(30, 30, 34) }
			for j = 1, 3 do
				bottle(K, sh * CF((j - 2) * 0.32, 0, 0) * ANG(0, PI, 0) * ANG(0, PI, 0), "pump", 0.95, cols[(j + idx) % 3 + 1], rgb(30, 30, 30), WHITE)
			end
			towelStack(K, ccf * CF(cw / 2 - 0.45, ch + 0.12, -cdp / 2 + 0.4), 0.7, 0.5, 3, rgb(246, 244, 240))
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

-- 미용실 전체
local function buildSalon(K: any, V: any, S: any)
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
			for _, p in K:ring("HeaterRing", head * ANG(PI / 2, 0, 0), 1.0, 0.24, 14, lk(rgb(236, 236, 234))) do
				table.insert(ringParts, p)
			end
			for i = 0, 5 do
				local a = i * PI * 2 / 6
				local lp = head * CF(math.cos(a) * 1.0, -0.14, math.sin(a) * 1.0)
				local lamp = K:disc("HeaterLamp", 0.36, 0.06, lp, lk(rgb(120, 60, 40)))
				table.insert(lamps, lamp)
				table.insert(ringParts, lamp)
			end
			K:disc("HeaterHubCap", 0.5, 0.12, head * CF(0, 0.12, 0), lk(rgb(236, 236, 234)))
			for i = 0, 2 do
				local a = i * PI * 2 / 3
				local sp = K:bar("HeaterSpoke", (head * CF(0, 0.12, 0)).Position, (head * CF(math.cos(a) * 0.95, 0.05, math.sin(a) * 0.95)).Position, 0.08, 0.06, lk(rgb(200, 200, 200)))
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
				end)
				break
			end
		end
	end
	-- 남은 옆벽 빈 자리: 시즌 트렌드 포스터 2 + 스타일북 꽂이
	local posters = {
		{ "2026 S/S 트렌드\n레이어드 C컬", "물결 스타일 제안", { { SALON.pink, 0.1, 0.35, 0.8, 0.55 }, { rgb(60, 40, 34), 0.3, 0.42, 0.4, 0.5 }, { rgb(250, 244, 236), 0.38, 0.5, 0.24, 0.3 } } },
		{ "애쉬 베이지\n톤다운 컬러", "탈색 없이 가능", { { rgb(200, 190, 176), 0.1, 0.35, 0.8, 0.55 }, { rgb(150, 140, 130), 0.25, 0.4, 0.5, 0.48 }, { rgb(240, 230, 220), 0.4, 0.55, 0.2, 0.25 } } },
		{ "남자 댄디컷\n가르마펌", "10월 이벤트 20% ↓", { { rgb(60, 70, 80), 0.1, 0.35, 0.8, 0.55 }, { rgb(30, 26, 24), 0.3, 0.5, 0.4, 0.35 }, { rgb(230, 210, 190), 0.35, 0.38, 0.3, 0.2 } } },
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
				poster(K, d2 * CF(0, 0, 0.01), 2.4, 3.4, { art = pp[3], title = pp[1], sub = pp[2], th = 0.18, ty = -0.3, sy = -0.43, frame = brass, bg = rgb(250, 246, 240), font = F.GothamBlack })
			else
				break
			end
		end
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
			plants = { "olive", "monstera" },
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
}

function T.build(K: any, V: any, S: any)
	local b = BUILDERS[V.type]
	if b then
		b(K, V, S)
	end
end

return T
