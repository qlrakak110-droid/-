--!strict
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

local Look = require(script.Parent:WaitForChild("Look"))
local Props = require(script.Parent:WaitForChild("Props"))
local Interact = require(script.Parent:WaitForChild("Interact"))
local Scan = require(script.Parent:WaitForChild("Scan"))
local Kit = require(script.Parent:WaitForChild("Kit"))

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
	Q:ring("StoolFootRing", base * CF(0, top * 0.38, 0) * ANG(PI / 2, 0, 0), 0.5, 0.07, 6, L_CHROME)
	Q:seg("StoolSpoke", base * V3(-0.5, top * 0.38, 0), base * V3(0.5, top * 0.38, 0), 0.05, L_CHROME)
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
			Q:box("FrozenBag", V3(iw, h, dd), c * CF(0, h / 2, 0), lk(it.c, M.SmoothPlastic, { r = 0.06 }))
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
	local pitch = 0.5
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
						Q:box("JellyBag", V3(0.22, 0.42, 0.08), CF(x, y + 0.23, z0 + 0.3), lk(c, M.SmoothPlastic, { r = 0.1 }))
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
				Q:box("ParcelPoly", V3(b[1], 0.3, b[3] + 0.1), pcfS * CF(x + b[1] / 2, y + 0.18, 0), lk(rgb(250, 214, 40)))
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
			Q:free(function()
				Q:plate("PlinthKick", mx.Z - mn.Z, 0.26, 0.02, fc(V3(x, 0.15, (mn.Z + mx.Z) / 2), V3(sx, 0, 0)), L_BLUE)
			end)
		end
		-- 엔드캡 위 POP (앞 끝, +Z)
		local cx = (mn.X + mx.X) / 2
		local txts = { "이번 주 행사\n1+1", "이번 주 행사\n2+1", "음료 2+1\n골라 담기" }
		local pz = mx.Z - 0.15
		for _, sx in { -1, 1 } do
			Q:box("POPPole", V3(0.05, 0.85, 0.05), CF(cx + sx * 1.2, 7.03, pz), L_CHROME)
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
					n += 1
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
	-- 레일 앞면에 붙는 얇은 띠 (선반 물건 자리 · 직원 스탠드 자리는 그대로)
	ctx.Q:free(function()
		for i, r in rails do
			local d = fc(V3(r.mx.X, r.c.Y, r.c.Z), XA)
			txt(ctx, "ChillerPrice", r.s.Z - 1.0, 0.24, d * CF(0, 0, 0.005), list[(i - 1) % #list + 1], INK, rgb(252, 252, 248), { font = F.GothamBold, d = 0.01 })
			if i % 2 == 0 then
				txt(ctx, "ChillerSale", 0.9, 0.5, d * CF(r.s.Z / 2 - 1.0, 0.35, 0.02), "유통기한\n임박 30%", WHITE, RED, { font = F.GothamBlack, d = 0.01 })
			end
		end
	end)
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
			Q:box("TissuePack", V3(1.1, 0.8, 0.85), basePcf * CF(x + 0.55, 1.6, 0), lk(cols[i % 3 + 1], M.SmoothPlastic))
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
		if keepHit(ctx, V3(xg - 0.05, 4.5, e.mn.Z), V3(xg, 4.9, e.mx.Z)) then
			continue
		end
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
			if keepHit(ctx, V3(e.mn.X, 2.75, zg - 0.05), V3(e.mx.X, 3.25, zg)) then
				continue
			end
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
					Q:box("RamenMulti", V3(1.1, 0.42, 0.75), c * CF((i % 2) * 1.15 - 0.57, 0.21 + (i // 2) * 0.43, 0), lk(if i % 3 == 2 then rgb(240, 160, 30) else RED))
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
			Q:box("BreadBag", V3(0.62, 0.36, 0.95), c, { c = bc[1], m = M.SmoothPlastic, r = 0.08 })
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

-- 진열대 눈높이 줄 상품에 포장 라벨 (맵 Product 상자 앞면에 얇은 띠: 덮지 않고 붙임)
local function productLabels(ctx: any)
	local Q, K = ctx.Q, ctx.K
	local plinths = all(ctx, "Plinth")
	if #plinths == 0 then
		return
	end
	local budget = math.max(0, 1580 - #K.parts)
	local n = 0
	local labelCols = { WHITE, rgb(250, 230, 120), rgb(240, 240, 236), rgb(30, 30, 34) }
	for _, e in all(ctx, "Product") do
		if n >= budget then
			break
		end
		local g = nil
		for _, p in plinths do
			if e.c.X > p.mn.X - 0.2 and e.c.X < p.mx.X + 0.2 and e.c.Z > p.mn.Z and e.c.Z < p.mx.Z then
				g = p
			end
		end
		if g and math.abs(e.mn.Y - 2.95) < 0.3 then
			local gc = (g.mn.X + g.mx.X) / 2
			local side = if e.c.X < gc then -1 else 1
			local xf = if side < 0 then e.mn.X else e.mx.X
			local h = e.s.Y
			local w = e.s.Z
			local col = e.r.part.Color
			local lum = col.R * 0.3 + col.G * 0.59 + col.B * 0.11
			local lc = if lum > 0.62 then labelCols[(math.floor(e.c.Z * 3) % 2) + 3 + (if lum > 0.8 then 1 else 0) - 1] else labelCols[(math.floor(e.c.Z * 5) % 2) + 1]
			if lum > 0.62 then
				lc = if math.floor(e.c.Z * 3) % 2 == 0 then GS_BLUE else RED
			end
			local yc = e.mn.Y + h * 0.56
			local bmn = V3(xf - 0.03, yc - h * 0.2, e.c.Z - w * 0.4)
			local bmx = V3(xf + 0.03, yc + h * 0.2, e.c.Z + w * 0.4)
			if not keepHit(ctx, bmn, bmx) then
				Q:plate("ProductLabel", w * 0.78, h * 0.34, 0.012, fc(V3(xf, yc, e.c.Z), V3(side, 0, 0)), lk(lc))
				n += 1
			end
		end
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
		{ "labels", productLabels },
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
