--!strict
-- GwangalliBuildingInterior/T_bowling: 광안 락볼링클럽 1층 방들 (Venues.luau 의 방, Scan.fitRoom).
--   bowlobby  1F 로비 · 리셉션 · 볼링화 대여 · 프로샵 · 포토존
--   bowlounge 라운지 · DJ 부스 · 미러볼
--   bowbar    ROCK & BOWL BAR (백바 · 생맥주 · 냉장고)
--   bowsnack  ROCK & BOWL 분식 (주방 라인 · 셀프바 · 반납대)
-- style(V) -> S: 공통 마감은 거의 다 끔 (1층 전체가 하나로 트인 홀이고, 건물이 약 0.95도 돌아가 있어서
--   이 모듈이 '정렬 프레임' R.A (방 프레임을 건물 회전만큼 돌린 것) 로 직접 지음).
-- build(K, V, S): 방마다 디테일 + 상호작용 (모두 클라이언트 전용, 서버 행동과 겹치지 않음).
-- 지켜야 할 것 (bld/bowling.json): Spot_bowl_shoes · Spot_bowl_snack (+ PickupTop 위) · VenueStaff 직원 자리 ·
--   Board_bowling · LEDScreen · Seat 들 · 레인 홀 · 자동문 · 오락코너 입구 (인생사진 부스 · 동전교환기) 는 그대로.

local Look = require(script.Parent:WaitForChild("Look"))
local Props = require(script.Parent:WaitForChild("Props"))
local Interact = require(script.Parent:WaitForChild("Interact"))
local Scan = require(script.Parent:WaitForChild("Scan"))

local T = {}
T.types = { "bowlobby", "bowlounge", "bowbar", "bowsnack" }

local CF, V3 = CFrame.new, Vector3.new
local ANG = CFrame.Angles
local PI = math.pi
local M = Enum.Material
local F = Enum.Font
local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

-- 방향 (dcf / pcf 의 +Z 가 바라보는 쪽)
local FZ, BZ, FX, BX = 0, PI, PI / 2, -PI / 2

-- 공통 재질 ---------------------------------------------------------------------------------------------
local function lk(r: number, g: number, b: number, m: Enum.Material?, extra: { [string]: any }?): { [string]: any }
	return Look.of(r, g, b, m, extra)
end
local function nl(c: Color3, t: number?): { [string]: any }
	return Look.neon(c, t)
end
local function gl(c: Color3?, t: number?): { [string]: any }
	return Look.glass(c, t)
end
local function dk(c: Color3, f: number): Color3
	return c:Lerp(BLACK, f)
end

local PURPLE = rgb(150, 70, 255)
local PINK = rgb(255, 60, 170)
local CYAN = rgb(40, 220, 255)
local AMBER = rgb(255, 176, 60)
local LIME = rgb(150, 255, 90)

local BLACKMETAL = Look.blackMetal
local CHROME = Look.chrome
local STEEL = Look.steel
local BRUSHED = Look.brushed
local RUBBERW = lk(234, 230, 222, M.Rubber)
local MATTE = lk(26, 24, 30, M.SmoothPlastic)
local PLUM = lk(84, 40, 96, M.Leather)
local PLUMDK = lk(58, 28, 68, M.Leather)
local WALNUT = Look.walnut
local CORD = lk(20, 20, 22, M.Rubber)

local function rnd(seed: number, i: number): number
	local s = math.sin(i * 12.9898 + seed * 78.233) * 43758.5453
	return s - math.floor(s)
end

local function hi(K: any): boolean
	return K.detail == "high"
end

-- 정렬 프레임 -------------------------------------------------------------------------------------------
local function yawOf(c: CFrame): number
	local xv = c.XVector
	local a = math.atan2(-xv.Z, xv.X)
	while a > PI / 4 do
		a -= PI / 2
	end
	while a < -PI / 4 do
		a += PI / 2
	end
	return a
end

local ALIGN_PARTS = {
	bowlobby = { "CubbyBack", "Body", "Floor_Lobby" },
	bowlounge = { "RailBase", "HighLedge", "DJPlatform" },
	bowbar = { "BackBarCabinet", "BarMirror", "Top" },
	bowsnack = { "KitchenCounter", "PickupShelf", "Body" },
}

local function makeR(K: any, V: any): any
	local yaw = 0.0165
	for _, nm in ALIGN_PARTS[V.type] or {} do
		local r = V:first(nm)
		if r then
			yaw = yawOf(r.lcf)
			break
		end
	end
	local R: any = { K = K, V = V, A = ANG(0, yaw, 0), yaw = yaw, H = V.H }
	K:note(string.format("bowling aligned yaw=%.4f", yaw))
	return R
end

-- 정렬 프레임 (x, y, z) -> 방 프레임
local function C(R: any, x: number, y: number, z: number, yaw: number?): CFrame
	if yaw then
		return R.A * CF(x, y, z) * ANG(0, yaw, 0)
	end
	return R.A * CF(x, y, z)
end
local function P(R: any, x: number, y: number, z: number): Vector3
	return R.A * V3(x, y, z)
end
-- 방 프레임 점 -> 정렬 프레임 점
local function toA(R: any, p: Vector3): Vector3
	return R.A:PointToObjectSpace(p)
end
-- 맵 rec 의 정렬 프레임 AABB
local function abox(R: any, r: any): (Vector3, Vector3)
	local A = R.A:Inverse()
	local mn, mx = V3(math.huge, math.huge, math.huge), V3(-math.huge, -math.huge, -math.huge)
	for _, x in { r.min.X, r.max.X } do
		for _, z in { r.min.Z, r.max.Z } do
			local p = A * V3(x, 0, z)
			mn = mn:Min(V3(p.X, r.min.Y, p.Z))
			mx = mx:Max(V3(p.X, r.max.Y, p.Z))
		end
	end
	-- 회전 AABB 는 살짝 부풂: 원래 파트 크기로 줄임
	local s = r.part.Size
	local c = (mn + mx) / 2
	local lc = A * r.lcf
	local ex = math.abs(lc.XVector.X) * s.X / 2 + math.abs(lc.YVector.X) * s.Y / 2 + math.abs(lc.ZVector.X) * s.Z / 2
	local ez = math.abs(lc.XVector.Z) * s.X / 2 + math.abs(lc.YVector.Z) * s.Y / 2 + math.abs(lc.ZVector.Z) * s.Z / 2
	return V3(c.X - ex, mn.Y, c.Z - ez), V3(c.X + ex, mx.Y, c.Z + ez)
end

local function B(R: any, name: string, sx: number, sy: number, sz: number, x: number, y: number, z: number, look: any, yaw: number?): BasePart
	return R.K:box(name, V3(sx, sy, sz), C(R, x, y, z, yaw), look)
end

-- 바닥 소품 자리 확인 (정렬 프레임)
local function spot(R: any, x: number, z: number, yaw: number, sx: number, sy: number, sz: number, pad: number?): boolean
	return R.K:spot(C(R, x, 0, z, yaw), V3(sx, sy, sz), pad or 0.2)
end

local function hideRec(K: any, r: any)
	Scan.hide(K.hidden, r.part)
end
local function hideNames(K: any, V: any, names: { [string]: boolean }, pred: ((any) -> boolean)?): number
	local n = 0
	for _, r in V.parts do
		if names[r.name] and (pred == nil or pred(r)) then
			hideRec(K, r)
			n += 1
		end
	end
	return n
end

-- 글자판
local function txt(K: any, name: string, w: number, h: number, dcf: CFrame, s: string, fg: Color3, bg: Color3?, font: Enum.Font?, glow: number?, o: any?): (BasePart, TextLabel)
	local opts: any = { fg = fg, bg = bg, font = font or F.GothamBold, glow = glow, d = 0.02 }
	if o then
		for k, v in o do
			opts[k] = v
		end
	end
	return K:text(name, w, h, dcf, s, opts)
end

-- 수평으로 누운 글자 (바닥 스티커): p = 중심, yaw = 읽는 사람이 서는 쪽이 +Z 가 되게
local function floorDcf(R: any, x: number, z: number, yaw: number, y: number?): CFrame
	local base = C(R, x, y or 0.012, z, yaw)
	return CFrame.fromMatrix(base.Position, base.XVector, -base.ZVector, base.YVector)
end

-- 공지 액자 (제목 띠 + 본문)
local function notice(K: any, dcf: CFrame, w: number, h: number, title: string, body: string, head: Color3?, o: any?)
	local hc = head or rgb(40, 40, 46)
	K:plate("NoticeFrame", w + 0.12, h + 0.12, 0.05, dcf, BLACKMETAL)
	K:plate("NoticeBack", w, h, 0.07, dcf, Look.paper)
	local th = math.min(h * 0.22, 0.7)
	txt(K, "NoticeTitle", w, th, dcf * CF(0, h / 2 - th / 2, 0.071), title, WHITE, hc, F.GothamBlack)
	txt(K, "NoticeBody", w * 0.92, (h - th) * 0.9, dcf * CF(0, -th / 2, 0.071), body, rgb(30, 30, 34), nil, F.GothamMedium, nil, { wrap = true })
	K:plate("NoticeGlass", w, h, 0.01, dcf * CF(0, 0, 0.08), { c = rgb(230, 236, 240), m = M.Glass, t = 0.9, r = 0.2 })
end

-- 천장 매다는 줄 (천장 H 까지)
local function hang(R: any, x: number, y: number, z: number, look: any?)
	R.K:seg("HangCable", P(R, x, y, z), P(R, x, R.H - 0.02, z), 0.04, look or lk(120, 122, 126, M.Metal))
end

-- 스피커 (천장 매달림 원통형 펜던트 스피커)
local function pendSpeaker(R: any, x: number, y: number, z: number)
	local K = R.K
	hang(R, x, y + 0.9, z, CORD)
	K:vcyl("SpeakerCan", 0.9, 0.9, C(R, x, y + 0.45, z), MATTE)
	K:disc("SpeakerGrill", 0.84, 0.04, C(R, x, y - 0.02, z), lk(40, 40, 44, M.Fabric))
	K:vcyl("SpeakerCap", 0.08, 0.4, C(R, x, y + 0.94, z), BLACKMETAL)
end

local function sprinklerRun(R: any, x0: number, x1: number, z: number, step: number)
	local K = R.K
	local y = R.H - 0.5
	K:seg("SprinklerPipe", P(R, x0, y, z), P(R, x1, y, z), 0.16, lk(176, 30, 30, M.Metal))
	local n = math.floor((x1 - x0) / step)
	for i = 0, n do
		local x = x0 + 0.5 * step + i * step
		if x < x1 then
			K:seg("SprinklerDrop", P(R, x, y, z), P(R, x, y - 0.5, z), 0.08, lk(176, 30, 30, M.Metal))
			K:disc("SprinklerHead", 0.22, 0.05, C(R, x, y - 0.55, z), Look.brass)
		end
	end
	-- 행거
	for i = 0, math.floor((x1 - x0) / 8) do
		local x = x0 + 2 + i * 8
		if x < x1 then
			K:seg("PipeHanger", P(R, x, y, z), P(R, x, R.H, z), 0.05, BLACKMETAL)
		end
	end
end

-- 나선 덕트 (x 방향) : 원통 조각 + 이음 띠 + 행거 + 디퓨저
local function ductX(R: any, x0: number, x1: number, y: number, z: number, d: number, look: any?)
	local K = R.K
	local L = look or lk(46, 46, 52, M.Metal)
	local seg = 7.5
	local n = math.max(1, math.floor((x1 - x0) / seg + 0.5))
	local step = (x1 - x0) / n
	for i = 0, n - 1 do
		local a = x0 + i * step
		K:cyl("Duct", step, d, C(R, a + step / 2, y, z), L)
		if i > 0 then
			K:cyl("DuctSeam", 0.18, d + 0.08, C(R, a, y, z), lk(70, 70, 76, M.Metal))
		end
		local hx = a + step / 2
		K:bar("DuctStrap", P(R, hx, y + d / 2, z), P(R, hx, R.H, z), 0.08, 0.08, BLACKMETAL)
		if i % 2 == 1 then
			-- 원형 디퓨저 (아래로 달림)
			K:vcyl("DiffuserNeck", 0.5, d * 0.45, C(R, hx, y - d / 2 - 0.2, z), L)
			K:disc("Diffuser", d * 0.75, 0.12, C(R, hx, y - d / 2 - 0.5, z), lk(70, 70, 76, M.Metal))
			K:disc("DiffuserCone", d * 0.45, 0.1, C(R, hx, y - d / 2 - 0.62, z), lk(36, 36, 40, M.Metal))
		end
	end
	K:disc("DuctCapA", d + 0.04, 0.1, C(R, x0, y, z) * ANG(0, 0, PI / 2), L)
end

-- 케이블 트레이 (x 방향 사다리)
local function trayX(R: any, x0: number, x1: number, y: number, z: number)
	local K = R.K
	local L = BLACKMETAL
	K:box("CableTrayRail", V3(x1 - x0, 0.18, 0.06), C(R, (x0 + x1) / 2, y, z - 0.6), L)
	K:box("CableTrayRail", V3(x1 - x0, 0.18, 0.06), C(R, (x0 + x1) / 2, y, z + 0.6), L)
	local n = math.floor((x1 - x0) / 2.5)
	for i = 0, n do
		local x = x0 + 0.3 + i * 2.5
		if x < x1 then
			K:box("CableTrayRung", V3(0.08, 0.05, 1.2), C(R, x, y - 0.06, z), L)
		end
	end
	K:box("CableBundle", V3(x1 - x0 - 0.2, 0.14, 0.7), C(R, (x0 + x1) / 2, y + 0.02, z - 0.1), lk(30, 30, 34, M.Rubber))
	K:box("CableBundle", V3(x1 - x0 - 0.2, 0.1, 0.2), C(R, (x0 + x1) / 2, y + 0.04, z + 0.35), lk(200, 120, 30, M.Rubber))
	for i = 0, math.floor((x1 - x0) / 10) do
		local x = x0 + 3 + i * 10
		if x < x1 then
			K:seg("TrayHanger", P(R, x, y, z - 0.62), P(R, x, R.H, z - 0.62), 0.05, L)
			K:seg("TrayHanger", P(R, x, y, z + 0.62), P(R, x, R.H, z + 0.62), 0.05, L)
		end
	end
end

-- 바닥 화분 (맵 Pot/Leaves 를 같은 자리에 다시)
local function replantAll(R: any, kinds: { string })
	local K, V = R.K, R.V
	local i = 0
	for _, r in V.byName.Pot or {} do
		if r.size.Y > 1.2 then
			i += 1
			local kind = kinds[(i - 1) % #kinds + 1]
			K:free(function()
				Props.floorPlant(K, CF(r.c.X, 0, r.c.Z), { kind = kind, h = 6.2, dia = math.min(2.0, math.max(r.size.X, r.size.Z)), pot = lk(30, 28, 34, M.Concrete) })
			end)
			hideRec(K, r)
			for _, q in V.parts do
				if (q.name == "Soil" or q.name == "Leaves") and math.abs(q.c.X - r.c.X) < 1.8 and math.abs(q.c.Z - r.c.Z) < 1.8 then
					hideRec(K, q)
				end
			end
		end
	end
end

-- 바 스툴 받침 (맵 Seat 는 그대로 두고 아래만 새로): pcf 바닥 (Seat 중심 아래), top = Seat 윗면
local function stoolBase(K: any, pcf: CFrame, top: number, seatDia: number, frame: any?, ring: any?)
	local fr = frame or CHROME
	K:disc("StoolBase", 1.25, 0.08, pcf * CF(0, 0.04, 0), fr)
	K:disc("StoolBaseRubber", 1.27, 0.03, pcf * CF(0, 0.015, 0), Look.rubber)
	K:ell("StoolBaseDome", V3(0.7, 0.2, 0.7), pcf * CF(0, 0.1, 0), fr)
	K:vcyl("StoolPost", top - 0.62, 0.22, pcf * CF(0, 0.12 + (top - 0.62) / 2, 0), fr)
	K:vcyl("StoolGasLift", 0.5, 0.3, pcf * CF(0, top - 0.6, 0), BLACKMETAL)
	K:ring("StoolFootRing", pcf * CF(0, top * 0.38, 0) * ANG(PI / 2, 0, 0), 0.62, 0.07, 10, ring or fr)
	for i = 0, 2 do
		local a = i * 2 * PI / 3 + 0.3
		K:seg("StoolSpoke", pcf * V3(0, top * 0.38, 0), pcf * V3(math.cos(a) * 0.62, top * 0.38, math.sin(a) * 0.62), 0.05, fr)
	end
	K:disc("StoolSwivel", seatDia * 0.62, 0.12, pcf * CF(0, top - 0.33, 0), BLACKMETAL)
end

-- 소파 껍데기 (맵 Seat 쿠션은 그대로): pcf = 바닥 가운데, +Z = 앉은 사람이 보는 쪽.
-- W 전체 폭 (팔걸이 포함), D 전체 깊이 (등받이 포함), seatBot = Seat 아랫면 높이 (베이스 윗면), backTop, armTop
local function sofaShell(K: any, pcf: CFrame, W: number, D: number, seatBot: number, backTop: number, armTop: number, o: any)
	local L = o.leather or PLUM
	local Ld = o.dark or PLUMDK
	local legL = o.legs or Look.brass
	local arm = o.arm or 0.7
	local back = o.back or 0.8
	local hw, hd = W / 2, D / 2
	-- 다리
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			K:vcyl("SofaLeg", 0.28, 0.16, pcf * CF(sx * (hw - 0.35), 0.14, sz * (hd - 0.3)), legL)
		end
	end
	-- 베이스 (앞 모서리 둥글게)
	local bw = W - 2 * arm
	local bd = D - back
	K:rbox("SofaBase", V3(bw, seatBot - 0.28, bd), 0.14, pcf * CF(0, 0.28 + (seatBot - 0.28) / 2, hd - bd / 2), L)
	K:box("SofaPiping", V3(bw, 0.05, 0.05), pcf * CF(0, seatBot - 0.02, hd - 0.02), Ld)
	-- 등받이 (위 모서리 둥글게) + 채널 터프팅
	local bh = backTop - 0.28
	K:rbox("SofaBack", V3(W - 0.02, bh, back), 0.3, pcf * CF(0, 0.28 + bh / 2, -hd + back / 2), L)
	local nch = math.max(2, math.floor(bw / 0.9))
	for i = 1, nch - 1 do
		local x = -bw / 2 + bw * i / nch
		K:box("SofaChannel", V3(0.05, bh - 1.1, 0.04), pcf * CF(x, 0.28 + seatBot + (bh - seatBot) / 2 - 0.1, -hd + back + 0.01), Ld)
	end
	-- 등 쿠션 (Seat 위 뒤쪽에 기댄 것)
	local nc = o.cushions or 2
	local cw = bw / nc
	for i = 1, nc do
		local x = -bw / 2 + cw * (i - 0.5)
		K:ell("SofaBackCushion", V3(cw - 0.12, (backTop - seatBot) * 0.82, 0.62), pcf * CF(x, seatBot + (backTop - seatBot) * 0.47, -hd + back + 0.3) * ANG(math.rad(-10), 0, 0), L)
	end
	-- 팔걸이 (위 모서리 둥글게)
	for _, sx in { -1, 1 } do
		local ah = armTop - 0.28
		K:rbox("SofaArm", V3(D - 0.02, ah, arm), 0.26, pcf * CF(sx * (hw - arm / 2), 0.28 + ah / 2, 0) * ANG(0, PI / 2, 0), L)
		K:box("SofaArmPiping", V3(0.05, 0.05, D - 0.1), pcf * CF(sx * (hw - arm), armTop - 0.12, 0), Ld)
	end
end

-- =====================================================================================================
-- 1F 로비
-- =====================================================================================================

-- 렌탈 볼링화 (pcf = 선반 위, +Z = 뒤꿈치 = 보는 쪽)
local function rentalShoe(K: any, pcf: CFrame, a: Color3, b: Color3, size: string?, full: boolean)
	K:box("ShoeSole", V3(0.42, 0.08, 0.96), pcf * CF(0, 0.04, 0), RUBBERW)
	K:box("ShoeUpper", V3(0.38, 0.19, 0.8), pcf * CF(0, 0.175, -0.06), { c = a, m = M.Leather })
	K:box("ShoeHeel", V3(0.4, 0.3, 0.26), pcf * CF(0, 0.22, 0.33), { c = b, m = M.Leather })
	if full then
		K:box("ShoeStrap", V3(0.405, 0.05, 0.15), pcf * CF(0, 0.27, -0.06), lk(26, 26, 28, M.Fabric))
	end
	if size then
		txt(K, "ShoeSize", 0.26, 0.14, pcf * CF(0, 0.25, 0.46), size, rgb(20, 20, 24), rgb(246, 246, 240), F.GothamBlack)
	end
end

local SHOE_COLS = {
	{ rgb(196, 36, 40), rgb(30, 44, 96) },
	{ rgb(30, 44, 96), rgb(196, 36, 40) },
	{ rgb(36, 36, 40), rgb(196, 36, 40) },
	{ rgb(30, 44, 96), rgb(220, 220, 214) },
	{ rgb(36, 36, 40), rgb(150, 150, 154) },
	{ rgb(120, 30, 34), rgb(36, 36, 40) },
}

local function lobbyShoes(R: any)
	local K, V = R.K, R.V
	local full = hi(K)
	-- 칸 나누기: Divider x 위치 (정렬), Shelf y
	local cells: { [string]: { any } } = {}
	for _, r in V.byName.Shoe or {} do
		local a = toA(R, r.c)
		if a.Z < -9 then
			hideRec(K, r)
			local row = math.clamp(math.floor((r.min.Y - 0.5) / 1.45) + 1, 1, 6)
			local col = math.clamp(math.floor((a.X - 5.05) / 3.25) + 1, 1, 8)
			local key = row .. ":" .. col
			cells[key] = cells[key] or {}
			table.insert(cells[key], { a = a, y = r.min.Y, row = row, col = col })
		end
	end
	for _, r in V.byName.SoleHeel or {} do
		if toA(R, r.c).Z < -9 then
			hideRec(K, r)
		end
	end
	for _, list in cells do
		table.sort(list, function(p, q)
			return p.a.X < q.a.X
		end)
		for i, s in list do
			local cs = SHOE_COLS[s.row]
			local size = tostring(220 + (s.row - 1) * 10 + math.floor((s.col - 1) / 2) * 5)
			rentalShoe(K, C(R, s.a.X, s.y, -11.2), cs[1], cs[2], if i == 1 and full then size else nil, full)
		end
	end
	-- 선반 앞 모서리 LED (칸마다 은은한 빛) + 칸 위 사이즈 띠 위 크롬 모서리
	for i = 0, 6 do
		local y = 0.53 + i * 1.45 + 0.13
		B(R, "CubbyEdge", 26.8, 0.04, 0.06, 17.98, y - 0.01, -10.53, lk(150, 120, 90, M.Metal))
	end
	-- 신발장 위 간접조명 (선반 맨 위)
	local strip = B(R, "CubbyLEDStrip", 26.4, 0.08, 0.1, 17.98, 9.42, -10.7, nl(rgb(255, 236, 210)))
	K:light(strip, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 11, Brightness = 0.8, Angle = 120, Color = rgb(255, 230, 200) })
	-- 빈 칸 몇 개: 대여 나간 표시 '대여중' 꼬리표
	local tags = 0
	for row = 1, 6 do
		for col = 1, 8 do
			if not cells[row .. ":" .. col] and tags < 4 then
				tags += 1
				local x = 5.05 + (col - 0.5) * 3.25
				local y = 0.65 + (row - 1) * 1.45
				txt(K, "ShoeOutTag", 1.1, 0.34, C(R, x, y + 0.45, -10.55), "대여중", WHITE, rgb(196, 36, 40), F.GothamBold)
			end
		end
	end
end

-- 리셉션 카운터 앞면 마감 + 위 캐노피 조명
local function lobbyReception(R: any)
	local K, V = R.K, R.V
	local body = V:first("Body")
	local x0, x1, zf = 3.98, 31.98, 0.75
	if body then
		local mn, mx = abox(R, body)
		x0, x1, zf = mn.X, mx.X, mx.Z
	end
	K:free(function()
		-- 양 끝: 세로 루버 (백라이트 아크릴 위 짙은 리브)
		for _, seg in { { x0 + 0.05, 7.85 }, { 28.1, x1 - 0.05 } } do
			local a, b = seg[1], seg[2]
			B(R, "CounterGlowPanel", b - a, 2.9, 0.04, (a + b) / 2, 0.42 + 1.45, zf + 0.02, nl(rgb(120, 60, 220), 0.25))
			local n = math.floor((b - a) / 0.42)
			for i = 0, n do
				local x = a + 0.12 + i * ((b - a - 0.24) / math.max(1, n))
				B(R, "CounterRib", 0.16, 2.9, 0.12, x, 0.42 + 1.45, zf + 0.08, lk(34, 26, 46, M.WoodPlanks))
			end
		end
		-- 가운데: 사인 위아래 헤어라인 띠
		B(R, "CounterBand", 20.2, 0.36, 0.08, 17.98, 3.22, zf + 0.04, BRUSHED)
		B(R, "CounterBand", 20.2, 0.36, 0.08, 17.98, 0.95, zf + 0.04, BRUSHED)
		B(R, "CounterBandLED", 20.2, 0.05, 0.06, 17.98, 3.0, zf + 0.06, nl(PURPLE))
		-- 끝 둥근 기둥 마감
		R.K:vcyl("CounterEndCap", 3.1, 0.5, C(R, x0 - 0.05, 0.42 + 1.55, zf - 1.35), lk(34, 26, 46, M.WoodPlanks))
		R.K:vcyl("CounterEndCap", 3.1, 0.5, C(R, x1 + 0.05, 0.42 + 1.55, zf - 1.35), lk(34, 26, 46, M.WoodPlanks))
		-- 상판 아래 금속 몰딩
		B(R, "CounterTopTrim", x1 - x0, 0.08, 0.06, (x0 + x1) / 2, 3.47, zf + 0.33, Look.goldMetal)
	end)
	-- 캐노피 (리셉션 위 매달린 사각 라인 조명)
	local yC = 17.4
	local cx0, cx1, cz0, cz1 = 3.6, 32.4, -8.6, 2.4
	local frameL = MATTE
	local glow = nl(rgb(255, 238, 214))
	for _, z in { cz0, cz1 } do
		B(R, "CanopyFrame", cx1 - cx0, 0.36, 0.5, (cx0 + cx1) / 2, yC, z, frameL)
		B(R, "CanopyDiffuser", cx1 - cx0 - 0.2, 0.04, 0.36, (cx0 + cx1) / 2, yC - 0.19, z, glow)
	end
	for _, x in { cx0, (cx0 + cx1) / 2, cx1 } do
		B(R, "CanopyFrame", 0.5, 0.36, cz1 - cz0, x, yC, (cz0 + cz1) / 2, frameL)
		B(R, "CanopyDiffuser", 0.36, 0.04, cz1 - cz0 - 0.2, x, yC - 0.19, (cz0 + cz1) / 2, glow)
	end
	for _, x in { cx0 + 0.3, cx1 - 0.3, (cx0 + cx1) / 2 } do
		for _, z in { cz0, cz1 } do
			hang(R, x, yC + 0.18, z)
		end
	end
	-- 스포트 2 (카운터 위)
	for _, x in { 10.0, 24.0 } do
		R.K:vcyl("CanopySpot", 0.5, 0.5, C(R, x, yC - 0.45, 0.6), frameL)
		local lens = R.K:disc("CanopySpotLens", 0.36, 0.03, C(R, x, yC - 0.71, 0.6), Look.lampWarm)
		B(R, "CanopySpotArm", 0.12, 0.12, 1.8, x, yC - 0.2, 1.5, frameL)
		R.K:light(lens, "SpotLight", { Face = Enum.NormalId.Bottom, Range = 22, Brightness = 1.4, Angle = 70, Color = rgb(255, 232, 200) })
	end
	-- 직원 의자 (맵 Seat 그대로, 받침만 새로)
	for _, r in V.byName.Seat or {} do
		local a = toA(R, r.c)
		if a.Z < -2.5 and a.X > 3 and r.max.Y > 2.2 then
			K:free(function()
				stoolBase(K, C(R, a.X, 0, a.Z), r.max.Y, 1.3, BLACKMETAL, CHROME)
			end)
			for _, q in V.parts do
				if (q.name == "StoolPost" or q.name == "StoolFoot") and math.abs(q.c.X - r.c.X) < 0.9 and math.abs(q.c.Z - r.c.Z) < 0.9 then
					hideRec(K, q)
				end
			end
		end
	end
	-- 볼링화 반납함 (손님 쪽, 카운터 동쪽 끝 앞)
	if spot(R, 30.0, 2.6, FZ, 2.8, 3.4, 1.4, 0.1) then
		local pc = C(R, 30.0, 0, 2.6)
		for _, sx in { -1, 1 } do
			K:box("ReturnRackLeg", V3(0.1, 2.4, 0.1), pc * CF(sx * 1.3, 1.2, 0.6), CHROME)
			K:box("ReturnRackLeg", V3(0.1, 2.4, 0.1), pc * CF(sx * 1.3, 1.2, -0.6), CHROME)
		end
		K:box("ReturnRackShelf", V3(2.7, 0.06, 1.3), pc * CF(0, 0.5, 0), CHROME)
		K:box("ReturnRackShelf", V3(2.7, 0.06, 1.3), pc * CF(0, 1.6, 0), CHROME)
		for _, sx in { -0.65, 0.65 } do
			K:box("ReturnBasket", V3(1.2, 0.7, 1.15), pc * CF(sx, 1.98, 0), lk(30, 40, 90, M.Plastic, { t = 0.15 }))
			K:box("ReturnBasketRim", V3(1.24, 0.06, 1.19), pc * CF(sx, 2.34, 0), lk(20, 26, 70, M.Plastic))
			rentalShoe(K, pc * CF(sx - 0.2, 2.36, 0) * ANG(0.5, 0.4, 0), SHOE_COLS[1][1], SHOE_COLS[1][2], nil, false)
		end
		K:vcyl("SprayBottle", 0.7, 0.3, pc * CF(0.9, 0.88, -0.2), lk(60, 150, 230, M.Plastic, { t = 0.2 }))
		K:box("SprayHead", V3(0.22, 0.2, 0.3), pc * CF(0.9, 1.33, -0.2), lk(240, 240, 240, M.Plastic))
		K:box("ShoeBoxStack", V3(1.1, 0.5, 0.8), pc * CF(-0.6, 0.78, 0), lk(196, 162, 118, M.Cardboard))
		txt(K, "ReturnSign", 2.6, 0.9, pc * CF(0, 3.0, 0.62) * ANG(math.rad(-8), 0, 0), "볼링화 반납\n소독 후 재사용합니다", WHITE, rgb(40, 30, 70), F.GothamBold)
		K:box("ReturnSignPost", V3(0.08, 0.6, 0.08), pc * CF(0, 2.55, 0.6), CHROME)
	end
	-- 줄 서는 곳 (차단봉 4개 + 벨트)
	local posts = { V3(6.8, 0, 2.2), V3(6.8, 0, 4.6), V3(11.8, 0, 2.2), V3(11.8, 0, 4.6) }
	local ok = {}
	for i, p in posts do
		if spot(R, p.X, p.Z, 0, 0.8, 3.2, 0.8, 0) then
			ok[i] = true
			local pc = C(R, p.X, 0, p.Z)
			K:disc("StanchionBase", 0.8, 0.1, pc * CF(0, 0.05, 0), CHROME)
			K:vcyl("StanchionPole", 2.9, 0.18, pc * CF(0, 1.55, 0), CHROME)
			K:vcyl("StanchionHead", 0.3, 0.26, pc * CF(0, 3.05, 0), BLACKMETAL)
		end
	end
	for _, pr in { { 1, 2 }, { 3, 4 } } do
		if ok[pr[1]] and ok[pr[2]] then
			local a, b = posts[pr[1]], posts[pr[2]]
			K:bar("StanchionBelt", P(R, a.X, 2.95, a.Z), P(R, b.X, 2.95, b.Z), 0.04, 0.22, lk(110, 40, 200, M.Fabric))
		end
	end
	if ok[3] then
		txt(K, "QueueSign", 1.3, 0.85, C(R, 11.8, 3.75, 4.6, FZ), "접수 · 결제\n줄을 서 주세요", WHITE, rgb(30, 24, 50), F.GothamBold)
		K:box("QueueSignPost", V3(0.06, 0.4, 0.06), C(R, 11.8, 3.25, 4.55), CHROME)
	end
end

-- 키오스크 (맵 KioskBody/Base/Screen 자리 그대로 덮어씀)
local function lobbyKiosk(R: any)
	local K, V = R.K, R.V
	local scr = V:first("KioskScreen")
	if not scr then
		return
	end
	local mn, mx = abox(R, scr)
	local cx = (mn.X + mx.X) / 2
	local zs = mx.Z
	local sw, sh = mx.X - mn.X, mx.Y - mn.Y
	local sy = (mn.Y + mx.Y) / 2
	hideNames(K, V, { KioskBody = true, KioskBase = true, KioskScreen = true })
	local label: TextLabel? = nil
	local scrPart: BasePart? = nil
	K:free(function()
		local pc = C(R, cx, 0, zs - 0.35)
		K:box("KioskPlinth", V3(1.8, 0.16, 1.2), pc * CF(0, 0.08, -0.1), MATTE)
		K:box("KioskNeck", V3(0.7, 1.2, 0.5), pc * CF(0, 0.76, -0.15), lk(230, 230, 236, M.SmoothPlastic))
		K:rbox("KioskBody", V3(1.45, 4.5, 0.62), 0.16, pc * CF(0, 3.45, -0.05) * ANG(0, PI / 2, 0), lk(238, 238, 242, M.SmoothPlastic))
		K:box("KioskBezel", V3(sw + 0.16, sh + 0.2, 0.06), pc * CF(0, sy, 0.27), lk(18, 18, 22, M.Glass))
		scrPart = K:box("KioskLCD", V3(sw, sh, 0.04), pc * CF(0, sy, 0.31), { c = rgb(20, 16, 40), m = M.Neon, t = 0.1 })
		local _, lb = txt(K, "KioskUI", sw * 0.92, sh * 0.9, pc * CF(0, sy, 0.335), "광안 락볼링\n\n▶ 게임 접수\n▶ 레인 현황\n▶ 볼링화 대여", WHITE, nil, F.GothamBold, 1.4, { wrap = false })
		label = lb
		txt(K, "KioskHeader", 1.3, 0.34, pc * CF(0, 5.45, 0.27), "무인 접수 KIOSK", WHITE, rgb(110, 40, 200), F.GothamBlack, 1.2)
		-- 카드 리더 선반 + IC 슬롯 + NFC + 영수증
		K:box("KioskShelf", V3(1.3, 0.12, 0.42), pc * CF(0, 2.15, 0.45), lk(200, 200, 206, M.SmoothPlastic))
		K:box("KioskCardSlot", V3(0.5, 0.06, 0.04), pc * CF(-0.3, 2.35, 0.3), BLACKMETAL)
		K:box("KioskNFC", V3(0.36, 0.02, 0.3), pc * CF(0.32, 2.22, 0.45), nl(rgb(60, 200, 255), 0.3))
		K:box("KioskReceipt", V3(0.6, 0.04, 0.04), pc * CF(0, 1.75, 0.3), BLACKMETAL)
		K:box("KioskScanner", V3(0.3, 0.3, 0.06), pc * CF(-0.45, 1.75, 0.31), lk(20, 20, 24, M.Glass))
		K:box("KioskScanLED", V3(0.2, 0.03, 0.02), pc * CF(-0.45, 1.75, 0.345), Look.ledRed)
		K:box("KioskSpeaker", V3(0.8, 0.06, 0.02), pc * CF(0, 1.42, 0.31), lk(60, 60, 64, M.Fabric))
	end)
	if label then
		Interact.screenLoop(K, scrPart, label, {
			{ text = "광안 락볼링\n\n▶ 게임 접수\n▶ 레인 현황\n▶ 볼링화 대여", c = rgb(20, 16, 40) },
			{ text = "게임 수 선택\n\n1게임 4,500원\n2게임 9,000원\n3게임 13,500원", c = rgb(16, 30, 50) },
			{ text = "레인 현황\n\n빈 레인 4\n대기 2팀\n예상 15분", c = rgb(14, 36, 26) },
			{ text = "락볼링 타임\n20:00~\n\n1게임 5,500원\n볼링화 1,500원", c = rgb(46, 14, 44) },
		}, 4.5)
	end
end

-- 양말 자판기 (키오스크와 카운터 사이)
local function sockVending(R: any, x: number, z: number)
	local K = R.K
	if not spot(R, x, z, FZ, 2.6, 6.4, 2.0, 0.15) then
		return
	end
	local pc = C(R, x, 0, z)
	local w, h, d = 2.6, 6.2, 2.0
	K:box("SockVendBody", V3(w, h, d), pc * CF(0, h / 2, 0), lk(244, 244, 248, M.SmoothPlastic))
	K:box("SockVendSide", V3(0.06, h, d), pc * CF(-w / 2 - 0.02, h / 2, 0), lk(120, 50, 210, M.SmoothPlastic))
	K:box("SockVendSide", V3(0.06, h, d), pc * CF(w / 2 + 0.02, h / 2, 0), lk(120, 50, 210, M.SmoothPlastic))
	local f = d / 2
	-- 유리창 + 안쪽 칸
	local gx, gw = -0.3, 1.8
	K:box("SockVendInner", V3(gw, 3.8, 0.1), pc * CF(gx, 3.6, f - 0.9), lk(30, 26, 40, M.SmoothPlastic))
	local cols = { rgb(240, 240, 240), rgb(30, 30, 34), rgb(210, 60, 80), rgb(60, 120, 220), rgb(250, 200, 60), rgb(130, 80, 220) }
	for row = 0, 3 do
		local y = 2.0 + row * 0.95
		K:box("SockVendTray", V3(gw, 0.05, 0.8), pc * CF(gx, y - 0.05, f - 0.45), CHROME)
		txt(K, "SockPrice", 0.5, 0.18, pc * CF(gx - 0.6, y - 0.14, f - 0.04), "1,500원", rgb(30, 30, 30), rgb(255, 240, 120), F.GothamBold)
		for c = 0, 2 do
			local col = cols[(row * 3 + c) % #cols + 1]
			K:box("SockPack", V3(0.42, 0.62, 0.12), pc * CF(gx - 0.6 + c * 0.6, y + 0.3, f - 0.3), { c = col, m = M.SmoothPlastic })
			K:box("SockPackLabel", V3(0.3, 0.16, 0.02), pc * CF(gx - 0.6 + c * 0.6, y + 0.42, f - 0.23), lk(250, 250, 250, M.SmoothPlastic))
			K:cyl("SockCoil", 0.7, 0.18, pc * CF(gx - 0.6 + c * 0.6, y + 0.02, f - 0.45) * ANG(0, PI / 2, 0), lk(180, 180, 186, M.Metal))
		end
	end
	K:box("SockVendGlass", V3(gw + 0.1, 3.9, 0.04), pc * CF(gx, 3.6, f + 0.02), gl(rgb(220, 230, 240), 0.7))
	-- 오른쪽 조작부
	local px = 0.95
	K:box("SockVendPanel", V3(0.55, 3.9, 0.06), pc * CF(px, 3.6, f + 0.02), lk(40, 40, 46, M.SmoothPlastic))
	K:box("SockVendLED", V3(0.42, 0.24, 0.02), pc * CF(px, 5.1, f + 0.06), nl(rgb(255, 80, 60)))
	for i = 0, 2 do
		for j = 0, 3 do
			K:box("SockVendKey", V3(0.1, 0.1, 0.03), pc * CF(px - 0.13 + i * 0.13, 4.5 - j * 0.15, f + 0.06), lk(200, 200, 204, M.SmoothPlastic))
		end
	end
	K:box("SockVendBill", V3(0.34, 0.08, 0.03), pc * CF(px, 3.75, f + 0.06), BLACKMETAL)
	K:box("SockVendCoin", V3(0.06, 0.2, 0.03), pc * CF(px, 3.45, f + 0.06), Look.goldMetal)
	K:box("SockVendCard", V3(0.36, 0.3, 0.05), pc * CF(px, 3.0, f + 0.06), lk(30, 30, 34, M.SmoothPlastic))
	K:box("SockVendCardLED", V3(0.24, 0.04, 0.02), pc * CF(px, 3.1, f + 0.09), nl(LIME))
	-- 취출구
	K:box("SockVendDoor", V3(1.6, 0.7, 0.06), pc * CF(gx, 0.95, f + 0.02), lk(30, 30, 34, M.SmoothPlastic))
	K:box("SockVendFlap", V3(1.4, 0.5, 0.03), pc * CF(gx, 0.95, f + 0.06), lk(60, 60, 66, M.Plastic, { t = 0.3 }))
	-- 머리 간판
	K:box("SockVendHeader", V3(w, 0.8, d * 0.6), pc * CF(0, h - 0.4, 0.4), lk(120, 50, 210, M.SmoothPlastic))
	txt(K, "SockVendTitle", w - 0.2, 0.6, pc * CF(0, h - 0.4, 0.7 + 0.01), "양말 자판기 SOCKS", WHITE, nil, F.GothamBlack, 1.3)
	txt(K, "SockVendNote", 1.9, 0.5, pc * CF(-0.2, 1.65, f + 0.04), "볼링화 대여 시 양말 착용 필수\n덧신 · 발목양말 · 장목양말", rgb(40, 30, 60), rgb(250, 248, 255), F.GothamMedium)
end

-- 신발 살균건조기 (맵 상자 자리 그대로, 유리문 2 + 칸 + UV)
local function lobbySterilizer(R: any): any
	local K, V = R.K, R.V
	local box = V:first("ShoeSterilizer")
	if not box then
		return nil
	end
	local mn, mx = abox(R, box)
	hideNames(K, V, { ShoeSterilizer = true, SterilizerUV = true })
	local cx = (mn.X + mx.X) / 2
	local w = mx.X - mn.X
	local d = mx.Z - mn.Z
	local h = mx.Y
	local zf = mx.Z
	local uv: { BasePart } = {}
	local timer: TextLabel? = nil
	local panel: BasePart? = nil
	K:free(function()
		local pc = C(R, cx, 0, (mn.Z + mx.Z) / 2)
		K:box("SterilBody", V3(w, h, d - 0.1), pc * CF(0, h / 2, -0.05), lk(236, 238, 240, M.SmoothPlastic))
		K:box("SterilKick", V3(w - 0.1, 0.35, 0.06), pc * CF(0, 0.18, d / 2 - 0.08), BLACKMETAL)
		K:box("SterilTop", V3(w + 0.1, 0.16, d), pc * CF(0, h - 0.08, 0), lk(200, 202, 206, M.Metal))
		local doorW = (w - 0.3) / 2
		for i, sx in { -1, 1 } do
			local dx = sx * (doorW / 2 + 0.05)
			-- 안쪽 (보라 UV 칸 + 선반 + 신발)
			K:box("SterilInner", V3(doorW - 0.1, 4.4, 0.06), pc * CF(dx, 3.15, -d / 2 + 0.25), lk(60, 40, 90, M.SmoothPlastic))
			for s = 0, 3 do
				local y = 1.15 + s * 1.1
				K:box("SterilRack", V3(doorW - 0.15, 0.04, d - 0.6), pc * CF(dx, y, 0), CHROME)
				if s < 3 or i == 1 then
					local cs = SHOE_COLS[(s + i) % #SHOE_COLS + 1]
					rentalShoe(K, pc * CF(dx - 0.25, y + 0.02, 0.1) * ANG(0, PI, 0), cs[1], cs[2], nil, false)
					rentalShoe(K, pc * CF(dx + 0.25, y + 0.02, 0.1) * ANG(0, PI, 0), cs[1], cs[2], nil, false)
				end
			end
			local tube = K:box("SterilUVTube", V3(0.08, 4.2, 0.08), pc * CF(dx + sx * (doorW / 2 - 0.15), 3.15, d / 2 - 0.35), nl(rgb(150, 90, 255)))
			table.insert(uv, tube)
			-- 유리문 + 프레임 + 손잡이
			K:box("SterilDoorGlass", V3(doorW, 4.5, 0.04), pc * CF(dx, 3.15, d / 2 - 0.02), gl(rgb(200, 190, 255), 0.6))
			for _, fy in { 0.9, 5.4 } do
				K:box("SterilDoorRail", V3(doorW, 0.1, 0.08), pc * CF(dx, fy, d / 2 - 0.02), lk(180, 182, 186, M.Metal))
			end
			K:box("SterilDoorStile", V3(0.1, 4.5, 0.08), pc * CF(dx - sx * (doorW / 2 - 0.05), 3.15, d / 2 - 0.02), lk(180, 182, 186, M.Metal))
			K:box("SterilDoorHandle", V3(0.08, 1.2, 0.12), pc * CF(dx - sx * (doorW / 2 - 0.22), 3.2, d / 2 + 0.06), CHROME)
		end
		-- 조작부 (문 아래)
		panel = K:box("SterilPanel", V3(w - 0.4, 0.5, 0.05), pc * CF(0, 0.62, d / 2 + 0.0), lk(30, 30, 36, M.SmoothPlastic))
		local _, lb = txt(K, "SterilTimer", 0.9, 0.34, pc * CF(-0.7, 0.62, d / 2 + 0.03), "대기", rgb(120, 255, 160), rgb(10, 14, 12), F.Code, 1.4)
		timer = lb
		for b = 0, 2 do
			K:disc("SterilButton", 0.2, 0.05, pc * CF(0.35 + b * 0.35, 0.62, d / 2 + 0.03) * ANG(PI / 2, 0, 0), if b == 0 then Look.ledGreen else lk(200, 200, 204, M.SmoothPlastic))
		end
		K:box("SterilVent", V3(w - 0.8, 0.3, 0.04), pc * CF(0, h - 0.5, d / 2 - 0.0), lk(150, 152, 156, M.Metal))
		txt(K, "SterilLabel", w - 0.4, 0.28, pc * CF(0, 0.2 + 0.05, d / 2 + 0.0), "자외선 · 열풍 신발 살균건조기", rgb(40, 40, 46), nil, F.GothamBold)
	end)
	-- 상호작용: 살균 시작 (UV 켜짐 + 타이머)
	local running = false
	local t0 = 0
	local tnow = 0
	Interact.anim(K, function(t)
		tnow = t
		if running and timer then
			local left = math.max(0, 30 - (t - t0))
			timer.Text = string.format("UV %02d초", math.floor(left))
			if left <= 0 then
				running = false
				timer.Text = "완료"
				for _, p in uv do
					p.Color = rgb(150, 90, 255)
					p.Transparency = 0
				end
			else
				local pulse = 0.5 + 0.5 * math.sin(t * 6)
				for _, p in uv do
					p.Color = rgb(150, 90, 255):Lerp(rgb(230, 200, 255), pulse * 0.6)
				end
			end
		end
	end)
	if panel then
		Interact.toggle(K, panel, {
			object = "신발 살균건조기",
			onText = "살균 시작",
			offText = "살균 중지",
			state = true,
			on = function(state)
				-- state = 다음 행동이 '살균 시작' 이면 true (처음 true → 누르면 false = 살균 중)
				if not state then
					running = true
					t0 = tnow
				else
					running = false
					if timer then
						timer.Text = "대기"
					end
				end
			end,
		})
	end
	return { x = cx, z = zf }
end

-- 레인 현황판 (레인 홀 입구 위에 매달린 양면 LED)
local function laneBoard(R: any, x: number, z: number, y: number)
	local K = R.K
	local w, h = 15, 3.8
	local pc = C(R, x, y, z)
	K:box("LaneBoardCase", V3(w + 0.4, h + 0.4, 0.5), pc, MATTE)
	K:box("LaneBoardTrim", V3(w + 0.44, 0.08, 0.54), pc * CF(0, h / 2 + 0.2, 0), nl(PURPLE))
	K:box("LaneBoardTrim", V3(w + 0.44, 0.08, 0.54), pc * CF(0, -h / 2 - 0.2, 0), nl(PURPLE))
	for _, sx in { -1, 1 } do
		hang(R, x + sx * (w / 2 - 0.8), y + h / 2 + 0.2, z, CORD)
	end
	local front = pc * CF(0, 0, 0.26)
	K:box("LaneBoardFace", V3(w, h, 0.02), front, { c = rgb(8, 8, 14), m = M.SmoothPlastic })
	txt(K, "LaneBoardTitle", 6.0, 0.6, front * CF(-4.2, h / 2 - 0.42, 0.015), "LANE STATUS · 레인 현황", rgb(255, 210, 90), nil, F.GothamBlack, 1.6)
	local _, clk = txt(K, "LaneBoardClock", 3.0, 0.5, front * CF(5.4, h / 2 - 0.42, 0.015), "대기 2팀 · 약 15분", rgb(140, 230, 255), nil, F.GothamBold, 1.6)
	local cells = {}
	local cw = (w - 0.6) / 6
	for i = 1, 12 do
		local col = (i - 1) % 6
		local row = (i - 1) // 6
		local cx = -w / 2 + 0.3 + cw * (col + 0.5)
		local cy = 0.25 - row * 1.45
		local plate = K:box("LaneCell", V3(cw - 0.12, 1.3, 0.02), front * CF(cx, cy, 0.012), { c = rgb(30, 120, 60), m = M.Neon, t = 0.35 })
		local _, lb = txt(K, "LaneCellText", cw - 0.3, 1.15, front * CF(cx, cy, 0.03), string.format("%02d\n빈 레인", i), WHITE, nil, F.GothamBold, 1.5)
		table.insert(cells, { p = plate, l = lb, i = i })
	end
	-- 뒷면: 로비 안내
	local back = pc * CF(0, 0, -0.26) * ANG(0, PI, 0)
	K:box("LaneBoardBack", V3(w, h, 0.02), back, { c = rgb(12, 10, 20), m = M.SmoothPlastic })
	txt(K, "LaneBoardBackText", w - 1, h - 0.8, back * CF(0, 0, 0.015), "◀ LOBBY · EXIT\n카운터 · 볼링화 대여 · 프로샵", WHITE, nil, F.GothamBlack, 1.3)
	-- 상태 순환 (사용중 / 대기 / 빈 레인 / 정비중)
	local ST = {
		{ "사용중", rgb(200, 40, 60) },
		{ "사용중", rgb(200, 40, 60) },
		{ "대기", rgb(220, 160, 30) },
		{ "빈 레인", rgb(30, 140, 70) },
		{ "사용중", rgb(200, 40, 60) },
		{ "정비중", rgb(90, 90, 100) },
	}
	local last = -1
	Interact.anim(K, function(t)
		local step = math.floor(t / 7)
		if step == last then
			return
		end
		last = step
		local busy = 0
		for _, c in cells do
			local k = math.floor(rnd(step, c.i) * 5.99) + 1
			if c.i == 11 then
				k = 6
			end
			local st = ST[k]
			if c.p.Parent then
				c.p.Color = st[2]
			end
			if c.l.Parent then
				local g = if st[1] == "사용중" then string.format("\n%d/3 게임", math.floor(rnd(step + 3, c.i) * 3) + 1) else ""
				c.l.Text = string.format("%02d\n%s%s", c.i, st[1], g)
			end
			if st[1] == "사용중" then
				busy += 1
			end
		end
		if clk.Parent then
			local wait = math.max(0, busy - 7)
			clk.Text = if wait > 0 then string.format("대기 %d팀 · 약 %d분", wait, wait * 8) else "바로 이용 가능"
		end
	end)
end

-- 명예의 전당 트로피 진열장 (서쪽 끝, +X 를 봄)
local function trophyCase(R: any, x: number, z0: number, z1: number)
	local K = R.K
	local len = z1 - z0
	local dep = 2.2
	if not spot(R, x + dep / 2, (z0 + z1) / 2, FX, len, 9, dep, 0.05) then
		-- spot 의 크기는 pcf 기준 (X = 폭) → yaw FX 로 돌림
		return
	end
	local pc = C(R, x + dep / 2, 0, (z0 + z1) / 2, FX) -- +Z = +X (보는 쪽)
	local h = 7.6
	K:box("TrophyPlinth", V3(len, 0.9, dep), pc * CF(0, 0.45, 0), MATTE)
	K:box("TrophyKickLED", V3(len - 0.2, 0.06, 0.04), pc * CF(0, 0.12, dep / 2 + 0.01), nl(rgb(255, 200, 110)))
	K:box("TrophyBack", V3(len, h - 0.9, 0.2), pc * CF(0, 0.9 + (h - 0.9) / 2, -dep / 2 + 0.1), lk(40, 28, 22, M.Wood))
	K:box("TrophyTop", V3(len + 0.1, 0.5, dep + 0.1), pc * CF(0, h + 0.25, 0), MATTE)
	txt(K, "TrophyHeader", len - 1.2, 0.42, pc * CF(0, h + 0.25, dep / 2 + 0.06), "명예의 전당  HALL OF FAME", rgb(255, 214, 120), nil, F.GothamBlack, 1.3)
	-- 유리 + 프레임
	K:box("TrophyGlass", V3(len - 0.1, h - 0.95, 0.05), pc * CF(0, 0.9 + (h - 0.9) / 2, dep / 2 - 0.03), gl(rgb(230, 236, 240), 0.82))
	for _, sx in { -1, 1 } do
		K:box("TrophySideGlass", V3(0.05, h - 0.95, dep - 0.2), pc * CF(sx * (len / 2 - 0.03), 0.9 + (h - 0.9) / 2, 0.05), gl(rgb(230, 236, 240), 0.82))
		K:box("TrophyPost", V3(0.12, h - 0.9, 0.12), pc * CF(sx * (len / 2 - 0.06), 0.9 + (h - 0.9) / 2, dep / 2 - 0.06), Look.goldMetal)
	end
	local n = 4
	for i = 1, 3 do
		K:box("TrophyMullion", V3(0.06, h - 0.9, 0.08), pc * CF(-len / 2 + len * i / n, 0.9 + (h - 0.9) / 2, dep / 2 - 0.05), Look.goldMetal)
	end
	local lamp = K:box("TrophyLED", V3(len - 0.4, 0.06, 0.1), pc * CF(0, h - 0.06, dep / 2 - 0.3), nl(rgb(255, 232, 196)))
	K:light(lamp, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 9, Brightness = 1.0, Angle = 110, Color = rgb(255, 226, 180) })
	local GOLD = lk(212, 172, 70, M.Metal, { r = 0.15 })
	local SILVER = lk(200, 204, 210, M.Metal, { r = 0.15 })
	local MARBLEB = lk(30, 30, 34, M.Marble)
	for s = 0, 2 do
		local y = 2.3 + s * 1.75
		K:box("TrophyShelf", V3(len - 0.3, 0.06, dep - 0.4), pc * CF(0, y, 0.05), gl(rgb(230, 240, 240), 0.5))
		local cnt = 7
		for j = 0, cnt - 1 do
			local tx = -len / 2 + 0.6 + j * (len - 1.2) / (cnt - 1)
			local kind = (j + s) % 4
			local base = pc * CF(tx, y + 0.03, 0.15 + (if j % 2 == 0 then -0.2 else 0.15))
			local metal = if (j + s) % 3 == 0 then SILVER else GOLD
			K:box("TrophyBase", V3(0.42, 0.24, 0.42), base * CF(0, 0.12, 0), MARBLEB)
			if kind == 0 then
				-- 컵 트로피
				K:vcyl("TrophyStem", 0.3, 0.1, base * CF(0, 0.39, 0), metal)
				K:ell("TrophyCup", V3(0.42, 0.42, 0.42), base * CF(0, 0.72, 0), metal)
				K:ring("TrophyHandle", base * CF(0.22, 0.75, 0), 0.1, 0.04, 6, metal)
				K:ring("TrophyHandle", base * CF(-0.22, 0.75, 0), 0.1, 0.04, 6, metal)
			elseif kind == 1 then
				-- 핀 트로피
				K:ell("TrophyPin", V3(0.28, 0.62, 0.28), base * CF(0, 0.58, 0), metal)
				K:ball("TrophyPinHead", 0.17, base * CF(0, 0.95, 0), metal)
			elseif kind == 2 then
				-- 공 + 핀
				K:ball("TrophyBall", 0.34, base * CF(-0.05, 0.42, 0), metal)
				K:ell("TrophyPin", V3(0.14, 0.42, 0.14), base * CF(0.14, 0.45, 0), metal)
			else
				-- 상패 (기울어진 판)
				K:box("TrophyPlaque", V3(0.5, 0.62, 0.06), base * CF(0, 0.55, 0) * ANG(math.rad(-10), 0, 0), WALNUT)
				K:box("TrophyPlaqueMetal", V3(0.38, 0.4, 0.02), base * CF(0, 0.57, 0.04) * ANG(math.rad(-10), 0, 0), metal)
			end
		end
	end
	-- 바닥 칸: 퍼펙트 300 기념 볼
	for j, c in { rgb(120, 20, 160), rgb(20, 70, 170), rgb(180, 30, 40) } do
		local tx = -len / 2 + 1.2 + (j - 1) * (len - 2.4) / 2
		K:disc("PerfectCup", 0.5, 0.12, pc * CF(tx, 0.96, 0.1), GOLD)
		K:ball("PerfectBall", 0.85, pc * CF(tx, 1.43, 0.1), { c = c, m = M.SmoothPlastic, r = 0.2 })
		txt(K, "PerfectTag", 0.8, 0.26, pc * CF(tx, 1.05, dep / 2 - 0.1), "PERFECT 300", rgb(30, 22, 10), rgb(230, 196, 110), F.GothamBlack)
	end
	-- 진열장 위: 퍼펙트 게임 기록 액자 3
	local names = { "2024.11 김*준\n300 PERFECT", "2025.07 박*희\n300 PERFECT", "2026.03 이*호\n299 / 동호회 리그" }
	for j = 1, 3 do
		local fx = -len / 2 + len * (j - 0.5) / 3
		Props.frame(K, pc * CF(fx, h + 1.9, -dep / 2 + 0.25), 2.2, 2.0, {
			art = { { rgb(40, 34, 60), 0, 0.32, 1, 0.68 }, { rgb(240, 200, 120), 0.3, 0.45, 0.4, 0.45 }, { rgb(250, 250, 250), 0.38, 0.75, 0.24, 0.18 } },
			frame = Look.goldMetal,
			mat = Look.of(26, 22, 30),
			text = names[j],
			fg = WHITE,
			textH = 0.32,
			textY = -0.52,
		})
	end
	-- 뒷면 (오락코너 쪽): 깔끔한 판 + 안내
	local back = pc * CF(0, 0, -dep / 2) * ANG(0, PI, 0)
	K:box("TrophyRear", V3(len, h, 0.06), back * CF(0, h / 2 + 0.25, 0.03), lk(34, 26, 52, M.SmoothPlastic))
	txt(K, "TrophyRearText", len - 2, 1.0, back * CF(0, 4.6, 0.07), "GWANGAN ROCK BOWL · 광안 락볼링클럽", rgb(220, 200, 255), nil, F.GothamBlack, 1.2)
end

-- 대기 소파 (맵 WaitingSofa, Seat 그대로)
local function lobbySofa(R: any)
	local K, V = R.K, R.V
	local base, backr = nil, nil
	for _, r in V.byName.Base or {} do
		if r.part.Parent and r.part.Parent.Name == "WaitingSofa" then
			base = r
		end
	end
	for _, r in V.byName.Backrest or {} do
		if r.part.Parent and r.part.Parent.Name == "WaitingSofa" then
			backr = r
		end
	end
	if not base or not backr then
		return
	end
	local bmn, bmx = abox(R, base)
	local kmn, kmx = abox(R, backr)
	local x0, x1 = math.min(bmn.X, kmn.X) - 0.1, math.max(bmx.X, kmx.X) + 0.1
	local zf = math.min(bmn.Z, kmn.Z)
	local zb = math.max(bmx.Z, kmx.Z)
	local facing = if kmn.Z > bmn.Z then BZ else FZ
	local cz = (zf + zb) / 2
	local seatBot = 1.14
	for _, r in V.byName.Seat or {} do
		if math.abs(r.c.Z - cz) < 2 and r.c.X > x0 and r.c.X < x1 then
			seatBot = r.min.Y
		end
	end
	local par = base.part.Parent
	for _, r in V.parts do
		if r.part:IsDescendantOf(par :: Instance) or ((r.name == "Arm" or r.name == "BackCushion") and r.c.X > x0 - 1 and r.c.X < x1 + 1 and math.abs(r.c.Z - cz) < 2.5) then
			if r.name ~= "Seat" and not r.part:IsA("Seat") then
				hideRec(K, r)
			end
		end
	end
	K:free(function()
		sofaShell(K, C(R, (x0 + x1) / 2, 0, cz, facing), x1 - x0, zb - zf, seatBot, 4.2, 2.5, { leather = PLUM, dark = PLUMDK, cushions = 3, legs = Look.goldMetal })
	end)
	K:reserve(P(R, x0, 0, zf - 0.2), P(R, x1, 4.4, zb + 0.2), "sofa")
	-- 낮은 테이블 (소파 앞)
	local tz = zf - 1.9
	if facing == FZ then
		tz = zb + 1.9
	end
	local tx = (x0 + x1) / 2
	if spot(R, tx, tz, 0, 4.4, 1.5, 1.8, 0.1) then
		local pc = C(R, tx, 0, tz)
		K:slab("CoffeeTop", 4.4, 1.8, 0.14, 0.4, pc * CF(0, 1.38, 0), lk(232, 228, 222, M.Marble))
		K:slab("CoffeeShelf", 4.0, 1.4, 0.06, 0.3, pc * CF(0, 0.4, 0), Look.goldMetal)
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				K:vcyl("CoffeeLeg", 1.3, 0.1, pc * CF(sx * 1.9, 0.66, sz * 0.62), Look.goldMetal)
			end
		end
		K:box("Magazine", V3(0.9, 0.04, 1.2), pc * CF(-1.2, 1.47, 0.1) * ANG(0, 0.25, 0), lk(220, 60, 80, M.SmoothPlastic))
		K:box("Magazine", V3(0.9, 0.04, 1.2), pc * CF(-1.05, 1.51, 0.05) * ANG(0, -0.15, 0), lk(40, 120, 200, M.SmoothPlastic))
		K:box("FlyerStand", V3(0.8, 0.9, 0.3), pc * CF(1.1, 1.9, 0) * ANG(math.rad(-10), 0, 0), Look.acrylicWhite)
		txt(K, "FlyerText", 0.7, 0.8, pc * CF(1.1, 1.9, 0.16) * ANG(math.rad(-10), 0, 0), "이달의 이벤트\n3게임 10% 할인\n생일 팀 음료 1잔", rgb(40, 30, 60), rgb(255, 250, 240), F.GothamBold, nil, { wrap = true })
		K:vcyl("TissueBox", 0.3, 0.4, pc * CF(1.8, 1.6, 0.3), lk(240, 240, 236, M.SmoothPlastic))
	end
	-- 우산꽂이 (소파 뒤 유리 쪽 끝)
	if spot(R, x0 + 0.5, zb + 1.0, 0, 1.1, 2.4, 1.1, 0) then
		local pc = C(R, x0 + 0.5, 0, zb + 1.0)
		K:vcyl("UmbrellaStand", 2.0, 1.0, pc * CF(0, 1.0, 0), lk(150, 152, 158, M.Metal))
		K:vcyl("UmbrellaStandRim", 0.1, 1.06, pc * CF(0, 2.0, 0), CHROME)
		for i = 0, 2 do
			local a = i * 2.1
			K:seg("Umbrella", (pc * CF(math.cos(a) * 0.25, 0.2, math.sin(a) * 0.25)).Position, (pc * CF(math.cos(a) * 0.32, 3.2, math.sin(a) * 0.32)).Position, 0.22, { c = ({ rgb(30, 30, 34), rgb(30, 70, 140), rgb(170, 30, 40) })[i + 1], m = M.Fabric })
		end
		txt(K, "UmbrellaTag", 0.9, 0.3, pc * CF(0, 1.4, 0.52) * ANG(0, 0, 0), "우산꽂이", rgb(30, 30, 30), rgb(250, 250, 250), F.GothamBold)
	end
end

-- 프로샵 (맵 유리 진열대 자리 + 볼 진열 타워 + 가방)
local BALLS = {
	{ "Storm Phaze II", "15lb · 289,000원", rgb(40, 60, 170), rgb(120, 30, 160) },
	{ "Roto Grip Hustle", "14lb · 199,000원", rgb(220, 60, 140), rgb(250, 200, 60) },
	{ "Hammer Black Widow", "15lb · 309,000원", rgb(30, 30, 34), rgb(200, 30, 40) },
	{ "Brunswick Rhino", "13lb · 179,000원", rgb(40, 160, 120), rgb(30, 60, 140) },
	{ "Motiv Venom Shock", "15lb · 259,000원", rgb(250, 120, 30), rgb(40, 40, 46) },
	{ "Columbia 300 White Dot", "12lb · 129,000원", rgb(120, 200, 255), rgb(240, 240, 250) },
}

local function swirlBall(K: any, cf: CFrame, d: number, a: Color3, b: Color3)
	K:ball("ProBallCore", d, cf, { c = a, m = M.SmoothPlastic, r = 0.18 })
	K:ell("ProBallSwirl", V3(d * 1.01, d * 0.42, d * 0.7), cf * ANG(0.5, 0.3, 0.7), { c = b, m = M.SmoothPlastic, r = 0.18 })
	K:ell("ProBallSwirl", V3(d * 0.7, d * 1.01, d * 0.4), cf * ANG(-0.4, 0.9, 0.2), { c = b:Lerp(a, 0.4), m = M.SmoothPlastic, r = 0.18 })
	-- 지공 3구멍 (위)
	for _, h in { { -0.12, 0 }, { 0.12, 0 }, { 0, 0.24 } } do
		K:disc("ProBallHole", d * 0.14, 0.02, cf * CF(h[1] * d, d * 0.49, h[2] * d - 0.08 * d), lk(10, 10, 12, M.SmoothPlastic))
	end
end

local function lobbyProShop(R: any): any
	local K, V = R.K, R.V
	local base = V:first("CaseBase")
	local res: any = {}
	if base then
		local mn, mx = abox(R, base)
		hideNames(K, V, { CaseBase = true, CaseGlass = true, CaseTop = true, CaseShelf = true, ProBall = true })
		local cx, cz = (mn.X + mx.X) / 2, (mn.Z + mx.Z) / 2
		local w, d = mx.X - mn.X, mx.Z - mn.Z
		K:free(function()
			local pc = C(R, cx, 0, cz, BZ) -- 진열대 정면 = -Z (로비 안쪽)
			K:box("ShowcaseBase", V3(w, 2.6, d - 0.1), pc * CF(0, 1.3, -0.05), MATTE)
			K:box("ShowcaseKick", V3(w - 0.1, 0.3, 0.06), pc * CF(0, 0.15, d / 2 - 0.12), nl(PURPLE))
			K:box("ShowcaseTrim", V3(w, 0.06, 0.06), pc * CF(0, 2.58, d / 2 - 0.06), Look.goldMetal)
			-- 유리 몸체
			local gh = 3.8
			K:box("ShowcaseGlassF", V3(w - 0.1, gh, 0.05), pc * CF(0, 2.6 + gh / 2, d / 2 - 0.1), gl(rgb(230, 238, 240), 0.82))
			K:box("ShowcaseGlassT", V3(w - 0.1, 0.05, d - 0.2), pc * CF(0, 2.6 + gh, 0), gl(rgb(230, 238, 240), 0.8))
			for _, sx in { -1, 1 } do
				K:box("ShowcaseGlassS", V3(0.05, gh, d - 0.2), pc * CF(sx * (w / 2 - 0.05), 2.6 + gh / 2, 0), gl(rgb(230, 238, 240), 0.82))
				K:box("ShowcasePost", V3(0.08, gh, 0.08), pc * CF(sx * (w / 2 - 0.05), 2.6 + gh / 2, d / 2 - 0.1), BLACKMETAL)
			end
			K:box("ShowcaseBackPanel", V3(w - 0.2, gh, 0.06), pc * CF(0, 2.6 + gh / 2, -d / 2 + 0.15), lk(26, 22, 34, M.SmoothPlastic))
			local led = K:box("ShowcaseLED", V3(w - 0.4, 0.05, 0.08), pc * CF(0, 2.6 + gh - 0.08, d / 2 - 0.3), nl(rgb(255, 240, 220)))
			K:light(led, "SpotLight", { Face = Enum.NormalId.Bottom, Range = 9, Brightness = 1.2, Angle = 100, Color = rgb(255, 240, 220) })
			K:box("ShowcaseShelf", V3(w - 0.3, 0.05, d - 0.4), pc * CF(0, 4.45, 0), gl(rgb(230, 240, 240), 0.5))
			-- 아래 칸: 볼 6개 (받침컵 위)
			for i, bdef in BALLS do
				local bx = -w / 2 + 0.75 + (i - 1) * (w - 1.5) / 5
				K:disc("BallCup", 0.42, 0.12, pc * CF(bx, 2.66, 0.1), CHROME)
				swirlBall(K, pc * CF(bx, 3.08, 0.1), 0.8, bdef[3], bdef[4])
				txt(K, "BallTag", 0.7, 0.2, pc * CF(bx, 2.72, d / 2 - 0.16) * ANG(math.rad(-50), 0, 0), bdef[2], rgb(20, 20, 24), rgb(250, 248, 240), F.GothamBold)
			end
			-- 윗 칸: 장갑 · 아대 · 테이프 · 로진백 · 클리너
			local items = { "glove", "wrist", "tape", "rosin", "cleaner", "glove", "wrist", "tape" }
			for i, kind in items do
				local ix = -w / 2 + 0.6 + (i - 1) * (w - 1.2) / (#items - 1)
				local b = pc * CF(ix, 4.48, 0.05)
				if kind == "glove" then
					K:box("ProGlove", V3(0.5, 0.7, 0.14), b * CF(0, 0.35, 0) * ANG(math.rad(-15), 0, 0), lk(30, 30, 34, M.Leather))
					K:box("ProGloveStrap", V3(0.52, 0.14, 0.16), b * CF(0, 0.15, 0.02) * ANG(math.rad(-15), 0, 0), lk(200, 30, 40, M.Fabric))
				elseif kind == "wrist" then
					K:box("ProWrist", V3(0.4, 0.9, 0.3), b * CF(0, 0.45, 0), lk(40, 40, 46, M.Fabric))
					K:box("ProWristPlate", V3(0.3, 0.5, 0.04), b * CF(0, 0.5, 0.16), lk(150, 152, 156, M.Metal))
				elseif kind == "tape" then
					for k = 0, 2 do
						K:box("ProTapeBox", V3(0.4, 0.26, 0.26), b * CF(0, 0.13 + k * 0.27, 0), { c = ({ rgb(240, 240, 240), rgb(250, 80, 40), rgb(40, 140, 230) })[k + 1], m = M.SmoothPlastic })
					end
				elseif kind == "rosin" then
					K:ell("ProRosin", V3(0.45, 0.3, 0.45), b * CF(0, 0.15, 0), lk(236, 232, 220, M.Fabric))
					K:ell("ProRosin", V3(0.45, 0.3, 0.45), b * CF(0.1, 0.4, 0.05), lk(40, 40, 120, M.Fabric))
				else
					K:vcyl("ProCleaner", 0.8, 0.3, b * CF(0, 0.4, 0), lk(60, 180, 90, M.Plastic))
					K:vcyl("ProCleanerCap", 0.18, 0.18, b * CF(0, 0.89, 0), lk(240, 240, 240, M.Plastic))
				end
			end
		end)
		res.case = { x = cx, z = cz, w = w, d = d }
		K:reserve(P(R, mn.X, 0, mn.Z), P(R, mx.X, 6.6, mx.Z), "case")
	end
	-- 볼 진열 타워 (3단 경사 레일)
	local tx, tz = 31.6, 9.3
	if spot(R, tx, tz, BZ, 2.8, 5.8, 2.2, 0.1) then
		local pc = C(R, tx, 0, tz, BZ)
		for _, sx in { -1, 1 } do
			K:box("BallTreePost", V3(0.14, 5.6, 0.14), pc * CF(sx * 1.3, 2.8, -0.8), BLACKMETAL)
			K:box("BallTreeFoot", V3(0.2, 0.1, 2.0), pc * CF(sx * 1.3, 0.05, 0), BLACKMETAL)
		end
		local k = 0
		for tier = 0, 2 do
			local y = 0.9 + tier * 1.55
			local zt = 0.55 - tier * 0.45
			for _, sx in { -1, 1 } do
				K:bar("BallTreeRail", (pc * CF(sx * 0.25, y, zt)).Position, (pc * CF(sx * 0.25, y + 0.25, -0.8)).Position, 0.06, 0.06, CHROME)
			end
			for _, bx in { -0.85, 0, 0.85 } do
				k += 1
				local bd = BALLS[(k - 1) % #BALLS + 1]
				K:disc("BallTreeCup", 0.5, 0.08, pc * CF(bx, y, zt - 0.3), CHROME)
				swirlBall(K, pc * CF(bx, y + 0.42, zt - 0.3), 0.78, bd[3], bd[4])
			end
			K:box("BallTreeShelf", V3(2.7, 0.08, 0.9), pc * CF(0, y - 0.04, zt - 0.3), BLACKMETAL)
		end
		txt(K, "BallTreeSign", 2.6, 0.6, pc * CF(0, 5.35, -0.72), "PRO SHOP · 지공 상담", WHITE, rgb(110, 40, 200), F.GothamBlack, 1.3)
		-- 주인공 볼 (상호작용: 볼 구경하기 → 다른 볼로)
		local featured: { BasePart } = {}
		local plate = K:box("FeaturedStand", V3(1.0, 0.5, 1.0), pc * CF(0, 5.6 + 0.25 - 0.0, 0.2), CHROME)
		K:disc("FeaturedRing", 0.95, 0.06, pc * CF(0, 6.12, 0.2), nl(PINK))
		local core = K:ball("FeaturedBall", 1.0, pc * CF(0, 6.65, 0.2), { c = BALLS[1][3], m = M.SmoothPlastic, r = 0.2 })
		local sw = K:ell("FeaturedSwirl", V3(1.01, 0.45, 0.72), pc * CF(0, 6.65, 0.2) * ANG(0.5, 0.3, 0.7), { c = BALLS[1][4], m = M.SmoothPlastic, r = 0.2 })
		table.insert(featured, core)
		table.insert(featured, sw)
		local _, tag = txt(K, "FeaturedTag", 2.4, 0.5, pc * CF(0, 4.75, -0.72), BALLS[1][1] .. "\n" .. BALLS[1][2], rgb(30, 20, 40), rgb(255, 236, 180), F.GothamBold)
		Interact.spin(K, featured, (K.cf * C(R, tx, 6.65, tz - 0.2)).Position, 0.12)
		Interact.cycle(K, plate, BALLS, {
			action = "다음 볼 보기",
			object = "프로샵 볼 구경하기",
			on = function(_i, b)
				if core.Parent then
					core.Color = b[3]
				end
				if sw.Parent then
					sw.Color = b[4]
				end
				if tag.Parent then
					tag.Text = b[1] .. "\n" .. b[2]
				end
			end,
		})
	end
	-- 볼링 가방 2 (진열대 옆, 유리 앞 낮게)
	for _, bx in { 33.7 } do
		if spot(R, bx, 10.6, 0, 1.3, 1.9, 2.0, 0) then
			local pc = C(R, bx, 0, 10.6)
			K:rbox("BowlingBag", V3(2.0, 1.4, 1.0), 0.35, pc * CF(0, 0.85, 0) * ANG(0, PI / 2, 0), lk(30, 30, 40, M.Fabric))
			K:box("BowlingBagStripe", V3(1.02, 0.16, 2.02), pc * CF(0, 0.9, 0), lk(150, 60, 230, M.Fabric))
			K:bar("BowlingBagHandle", (pc * CF(0, 1.55, -0.6)).Position, (pc * CF(0, 1.55, 0.6)).Position, 0.12, 0.12, BLACKMETAL)
			K:vcyl("BowlingBagWheel", 0.14, 0.3, pc * CF(0.4, 0.15, -0.8) * ANG(0, 0, PI / 2), Look.rubber)
			K:vcyl("BowlingBagWheel", 0.14, 0.3, pc * CF(-0.4, 0.15, -0.8) * ANG(0, 0, PI / 2), Look.rubber)
		end
	end
	return res
end

-- 포토존 (동쪽 벽): 원근 레인 배경 · 대형 핀 · 대형 볼 · 바닥 스티커 · 링라이트 (상호작용: 사진 찍기)
local function lobbyPhoto(R: any, wallX: number)
	local K = R.K
	local face = BX -- 벽면이 -X 를 봄
	local function wd(z: number, y: number, off: number): CFrame
		return C(R, wallX - off, y, z, face)
	end
	-- 배경판 (z -6.6..6.6, 아래 0..8.9): 짙은 보라 + 원근 레인
	K:free(function()
		K:plate("PhotoBackdrop", 13.2, 8.8, 0.03, wd(0, 4.45, 0.04), lk(28, 14, 50, M.SmoothPlastic))
		-- 레인 (사다리꼴: 가운데 판 + 양쪽 쐐기)
		local laneC = wd(0, 2.7, 0.07)
		K:plate("PhotoLane", 1.2, 5.2, 0.02, laneC, lk(214, 172, 112, M.WoodPlanks))
		for _, sx in { -1, 1 } do
			-- 쐐기를 판처럼 세워 사다리꼴 옆면
			K:make("WedgePart", "PhotoLaneSide", V3(0.02, 5.2, 1.9), laneC * CF(sx * (0.6 + 0.95), 0, 0.005) * ANG(0, -sx * PI / 2, 0) * ANG(0, 0, 0), lk(214, 172, 112, M.WoodPlanks))
			K:plate("PhotoGutter", 0.3, 5.2, 0.02, laneC * CF(sx * 2.6, 0, -0.002), lk(20, 20, 24, M.Metal))
		end
		-- 화살표 (레인 위)
		for i = -2, 2 do
			K:plate("PhotoArrow", 0.2, 0.36, 0.01, laneC * CF(i * 0.45, -1.2 + math.abs(i) * 0.25, 0.02), lk(30, 24, 20, M.SmoothPlastic))
		end
		-- 핀 10개 (소실점)
		local rows = { { 0 }, { -0.25, 0.25 }, { -0.5, 0, 0.5 }, { -0.75, -0.25, 0.25, 0.75 } }
		for r, list in rows do
			for _, px in list do
				local pcf = wd(px, 5.55 + r * 0.42, 0.1)
				K:plate("PhotoPin", 0.28, 0.62, 0.02, pcf, lk(250, 250, 248, M.SmoothPlastic))
				K:plate("PhotoPinNeck", 0.3, 0.06, 0.02, pcf * CF(0, 0.12, 0.004), lk(220, 30, 40, M.SmoothPlastic))
			end
		end
		-- 글자
		txt(K, "PhotoTitle", 9.5, 1.3, wd(0, 1.05, 0.1), "STRIKE ZONE · 광안 락볼링", rgb(255, 230, 120), nil, F.GothamBlack, 1.6)
		txt(K, "PhotoHash", 6, 0.5, wd(0, 0.32, 0.1), "#광안락볼링 #광안리의밤 #스트라이크", rgb(200, 180, 255), nil, F.GothamBold, 1.3)
		-- 별 점 (반짝이 네온)
		for i = 1, 14 do
			local zz = -6 + rnd(3, i) * 12
			local yy = 1.6 + rnd(5, i) * 6.8
			if math.abs(zz) > 2.8 or yy > 7.8 then
				K:plate("PhotoStar", 0.12, 0.12, 0.02, wd(zz, yy, 0.08) * ANG(0, 0, PI / 4), nl(if i % 3 == 0 then PINK elseif i % 3 == 1 then CYAN else WHITE))
			end
		end
	end)
	-- 대형 핀 (왼쪽)
	local pz = -8.0
	if spot(R, wallX - 1.6, pz, 0, 2.0, 7.0, 2.0, 0) then
		local pc = C(R, wallX - 1.6, 0, pz)
		local W2 = lk(248, 248, 246, M.SmoothPlastic, { r = 0.1 })
		K:disc("GiantPinBase", 1.3, 0.1, pc * CF(0, 0.05, 0), W2)
		K:ell("GiantPinBody", V3(1.9, 3.8, 1.9), pc * CF(0, 2.1, 0), W2)
		K:ell("GiantPinNeck", V3(0.9, 2.0, 0.9), pc * CF(0, 4.4, 0), W2)
		K:ell("GiantPinHead", V3(1.15, 1.4, 1.15), pc * CF(0, 5.6, 0), W2)
		K:vcyl("GiantPinStripe", 0.16, 0.86, pc * CF(0, 4.55, 0), lk(210, 30, 40, M.SmoothPlastic))
		K:vcyl("GiantPinStripe", 0.16, 0.8, pc * CF(0, 4.25, 0), lk(210, 30, 40, M.SmoothPlastic))
		K:disc("GiantPinBottom", 1.25, 0.04, pc * CF(0, 0.12, 0), Look.rubber)
	end
	-- 대형 볼 (오른쪽)
	if spot(R, wallX - 1.9, 7.6, 0, 3.4, 3.4, 3.4, 0) then
		local pc = C(R, wallX - 1.9, 1.7, 7.6)
		swirlBall(K, pc, 3.3, rgb(120, 40, 200), rgb(255, 80, 180))
		K:disc("GiantBallRing", 1.6, 0.12, C(R, wallX - 1.9, 0.06, 7.6), nl(PURPLE))
	end
	-- 바닥 스티커
	local sx, sz = wallX - 4.5, -0.1
	K:disc("PhotoSpotRing", 3.6, 0.02, C(R, sx, 0.012, sz), lk(250, 220, 90, M.SmoothPlastic))
	K:disc("PhotoSpotInner", 3.1, 0.02, C(R, sx, 0.022, sz), lk(30, 16, 54, M.SmoothPlastic))
	txt(K, "PhotoSpotText", 2.6, 0.9, floorDcf(R, sx, sz, BX, 0.035), "PHOTO SPOT\n여기 서서 찰칵!", rgb(255, 230, 120), nil, F.GothamBlack)
	-- 링라이트 삼각대 (사진 찍는 쪽)
	local rx, rz = wallX - 10.0, -0.1
	if spot(R, rx, rz, FX, 1.6, 5.4, 1.6, 0) then
		local pc = C(R, rx, 0, rz, FX) -- +Z = 벽 쪽
		for i = 0, 2 do
			local a = i * 2 * PI / 3
			K:seg("TripodLeg", (pc * CF(0, 2.0, 0)).Position, (pc * CF(math.cos(a) * 0.8, 0.02, math.sin(a) * 0.8)).Position, 0.07, BLACKMETAL)
		end
		K:vcyl("TripodPole", 2.4, 0.1, pc * CF(0, 3.2, 0), BLACKMETAL)
		local ringC = pc * CF(0, 4.8, 0)
		local ring = K:ring("RingLightLamp", ringC, 0.75, 0.16, 16, nl(rgb(255, 250, 240)))
		K:ring("RingLightHousing", ringC * CF(0, 0, -0.06), 0.75, 0.24, 16, BLACKMETAL)
		K:box("RingPhoneHolder", V3(0.1, 0.5, 0.06), ringC * CF(0, -0.2, 0.05), BLACKMETAL)
		local phone = K:box("RingPhone", V3(0.36, 0.72, 0.05), ringC * CF(0, 0.05, 0.1), lk(20, 20, 24, M.Glass))
		local scr = K:box("RingPhoneScreen", V3(0.32, 0.66, 0.01), ringC * CF(0, 0.05, 0.13), { c = rgb(40, 40, 60), m = M.Neon, t = 0.2 })
		local flashPart = ring[1]
		local fl = flashPart and K:light(flashPart, "PointLight", { Range = 16, Brightness = 0.4, Color = rgb(255, 240, 255) })
		local _, cd = txt(K, "PhotoCountdown", 1.6, 0.6, pc * CF(0, 5.8, 0.0) * ANG(0, PI, 0), "", rgb(255, 230, 120), nil, F.GothamBlack, 2)
		local flashAt = -100
		local tnow = 0
		Interact.anim(K, function(t)
			tnow = t
			local dt = t - flashAt
			if dt < 0 then
				return
			end
			if dt < 3 then
				cd.Text = tostring(3 - math.floor(dt))
			elseif dt < 3.6 then
				cd.Text = "찰칵!"
				if fl then
					fl.Brightness = 3.5
				end
				if scr.Parent then
					scr.Color = rgb(255, 255, 255)
				end
			elseif dt < 6 then
				cd.Text = "♥ 저장 완료"
				if fl then
					fl.Brightness = 0.4
				end
				if scr.Parent then
					scr.Color = rgb(120, 60, 200)
				end
			else
				cd.Text = ""
				if scr.Parent then
					scr.Color = rgb(40, 40, 60)
				end
			end
		end)
		Interact.prompt(K, phone, {
			action = "사진 찍기",
			object = "포토존 링라이트",
			fn = function()
				if tnow - flashAt > 6 then
					flashAt = tnow
				end
			end,
		})
	end
	-- 보라 무드 조명 (포토존)
	local glow = B(R, "PhotoUplight", 12.6, 0.1, 0.2, wallX - 0.25, 0.08, 0, nl(PURPLE), FX)
	K:light(glow, "SurfaceLight", { Face = Enum.NormalId.Top, Range = 12, Brightness = 1.2, Angle = 90, Color = rgb(190, 120, 255) })
end

-- 로비 천장 설비 (덕트 · 트레이 · 스프링클러 · 스피커 · 라인 조명)
local function lobbyCeiling(R: any)
	local K = R.K
	local H = R.H
	ductX(R, -43.6, 43.2, H - 2.3, 9.4, 2.0)
	ductX(R, -43.6, 2.8, H - 1.9, -5.5, 1.6)
	trayX(R, -43.6, 43.2, H - 1.1, -0.8)
	sprinklerRun(R, -43.6, 43.2, 3.2, 7.2)
	for _, p in { V3(-36, 0, -9), V3(-20, 0, -4), V3(-8, 0, 5), V3(26, 0, 6), V3(40, 0, -6) } do
		pendSpeaker(R, p.X, 15.8, p.Z)
	end
	-- 천장 네온 라인 (서쪽 절반, 코스믹 느낌)
	local cols = { CYAN, PINK, PURPLE, CYAN }
	for i, z in { -10.5, -2.6, 5.2, 11.0 } do
		B(R, "CeilNeonLine", 40, 0.12, 0.12, -23, H - 0.25, z, nl(cols[i]))
	end
	for _, x in { -40, -27, -14 } do
		B(R, "CeilNeonLine", 0.12, 0.12, 22, x, H - 0.27, 0.2, nl(PURPLE))
	end
	-- CCTV + 화재감지 + 비상등
	K:ell("CCTVDome", V3(0.8, 0.5, 0.8), C(R, 2.5, H - 0.25, -1.5), lk(30, 30, 34, M.Glass, { t = 0.2 }))
	K:disc("CCTVBase", 0.9, 0.08, C(R, 2.5, H - 0.04, -1.5), lk(236, 236, 236, M.SmoothPlastic))
	for _, p in { V3(-30, 0, 2), V3(12, 0, -4), V3(36, 0, 3) } do
		K:disc("SmokeDetector", 0.6, 0.12, C(R, p.X, H - 0.06, p.Z), lk(240, 240, 238, M.SmoothPlastic))
		K:disc("SmokeDetectorLED", 0.08, 0.02, C(R, p.X + 0.15, H - 0.13, p.Z), Look.ledRed)
	end
end

-- 로비 바닥 그래픽 (입구 로고 · 레인 방향 화살표)
local function lobbyFloor(R: any)
	local K = R.K
	-- 입구 로고 링 (자동문 안쪽, 현관 keep 은 0.1 아래라 상관없음)
	local lx, lz = -33, 4.2
	K:disc("FloorLogoRing", 6.4, 0.02, C(R, lx, 0.012, lz), lk(150, 70, 255, M.SmoothPlastic))
	K:disc("FloorLogoInner", 5.9, 0.02, C(R, lx, 0.02, lz), lk(18, 16, 26, M.Marble))
	txt(K, "FloorLogoText", 5.0, 1.6, floorDcf(R, lx, lz, FZ, 0.034), "GWANGAN\nROCK BOWL", rgb(220, 200, 255), nil, F.GothamBlack)
	-- 레인 쪽 화살표 + 글자
	for _, a in { { -4.5, -10.2, "LANES 1-12 ▲" }, { 40.5, -11.6, "LANES ▲" } } do
		txt(K, "FloorArrowText", 4.4, 1.0, floorDcf(R, a[1], a[2], FZ, 0.03), a[3], rgb(255, 214, 90), nil, F.GothamBlack)
		for i = 0, 2 do
			K:box("FloorChevron", V3(1.2, 0.02, 0.24), C(R, a[1] - 0.45, 0.02, a[2] + 1.0 + i * 0.6) * ANG(0, 0.6, 0), lk(255, 214, 90, M.SmoothPlastic))
			K:box("FloorChevron", V3(1.2, 0.02, 0.24), C(R, a[1] + 0.45, 0.02, a[2] + 1.0 + i * 0.6) * ANG(0, -0.6, 0), lk(255, 214, 90, M.SmoothPlastic))
		end
	end
	-- 카운터 앞 대기선
	B(R, "FloorQueueLine", 26, 0.02, 0.2, 18, 0.012, 6.2, lk(255, 214, 90, M.SmoothPlastic))
	txt(K, "FloorQueueText", 6.0, 0.6, floorDcf(R, 18, 6.9, FZ, 0.03), "여기서 잠시 기다려 주세요", rgb(255, 214, 90), nil, F.GothamBold)
end

-- 로비 벽 (동쪽 벽 남는 곳) 공지 · 포스터 + X배너
local function lobbyNotices(R: any, wallX: number)
	local K = R.K
	notice(K, C(R, wallX - 0.02, 5.4, -10.2 + 0.0, BX) * CF(0, 0, 0), 1.6, 2.2, "이용 안내", "· 볼링화 착용 필수\n· 양말 미착용 시 입장 불가\n· 레인 음식물 반입 금지\n· 청소년 22시 이후 보호자 동반", rgb(110, 40, 200))
	Props.frame(K, C(R, wallX - 0.02, 8.0, 10.2, BX), 2.6, 3.6, {
		art = { { rgb(26, 20, 40), 0, 0, 1, 1 }, { rgb(150, 70, 255), 0.1, 0.55, 0.8, 0.32 }, { rgb(255, 220, 120), 0.3, 0.12, 0.4, 0.4 } },
		text = "초보 볼링교실\n매주 화·목 19시\n1:1 레슨 상담",
		fg = WHITE,
		textH = 0.45,
		textY = 0.55,
		frame = BLACKMETAL,
	})
	-- X배너 (서쪽, 트로피장 앞쪽 끝)
	local bx, bz = -41.6, 3.9
	if spot(R, bx, bz, FX, 1.8, 6.0, 1.0, 0) then
		local pc = C(R, bx, 0, bz, FX)
		K:seg("XBannerLeg", (pc * CF(-0.8, 0.02, -0.4)).Position, (pc * CF(0.75, 5.8, 0)).Position, 0.06, BLACKMETAL)
		K:seg("XBannerLeg", (pc * CF(0.8, 0.02, -0.4)).Position, (pc * CF(-0.75, 5.8, 0)).Position, 0.06, BLACKMETAL)
		K:box("XBannerSheet", V3(1.6, 5.2, 0.02), pc * CF(0, 3.3, 0.04), lk(250, 248, 255, M.Fabric))
		txt(K, "XBannerText", 1.5, 4.8, pc * CF(0, 3.3, 0.06), "생일파티\n단체 대관\n\nLEAGUE\nNIGHT\n매주 목요일\n\n☎ 051-756-2026", rgb(80, 30, 160), nil, F.GothamBlack, nil, { wrap = false })
	end
end

local function buildLobby(R: any)
	local K = R.K
	local wallX = 43.5
	local wl = R.V:first("WallLiner")
	if wl then
		local mn = abox(R, wl)
		if mn.X > 40 then
			wallX = mn.X
		end
	end
	local steps = {
		{ "ceiling", function() K:free(function() lobbyCeiling(R) end) end },
		{ "shoes", function() lobbyShoes(R) end },
		{ "reception", function() lobbyReception(R) end },
		{ "kiosk", function() lobbyKiosk(R) end },
		{ "sock", function() sockVending(R, 1.3, -0.4) end },
		{ "steril", function() lobbySterilizer(R) end },
		{ "board", function() laneBoard(R, -4.6, -12.5, 14.6) end },
		{ "trophy", function() trophyCase(R, -43.4, -6.8, 2.4) end },
		{ "sofa", function() lobbySofa(R) end },
		{ "plants", function() replantAll(R, { "monstera", "olive" }) end },
		{ "proshop", function() lobbyProShop(R) end },
		{ "photo", function() lobbyPhoto(R, wallX) end },
		{ "floor", function() lobbyFloor(R) end },
		{ "notices", function() lobbyNotices(R, wallX) end },
	}
	for _, st in steps do
		local ok, err = pcall(st[2])
		if not ok then
			K:note("lobby." .. st[1] .. " error: " .. tostring(err))
		end
	end
end

-- =====================================================================================================
-- 스타일 · 진입점
-- =====================================================================================================

function T.style(V: any): any
	-- 트인 홀 쪽 '앞 유리' keep 은 실제 유리가 없는 방에서 걷어냄 (라운지 · 바 · 분식: 앞이 다른 방으로 열림)
	if V.type ~= "bowlobby" then
		local keep = {}
		for _, k in V.keep do
			if k.kind ~= "window" then
				table.insert(keep, k)
			end
		end
		V.keep = keep
	end
	return {
		chair = false,
		stool = false,
		table = false,
		counter = false,
		base = false,
		lower = false,
		mat = false,
		clock = false,
		license = false,
		cctv = false,
		ceiling = false,
		lights = { kind = "none" },
		skip = { floor = true, ceiling = true, walls = true, fixtures = true, upgrades = true, chairs = true, stools = true, tables = true, counters = true },
	}
end

function T.build(K: any, V: any, S: any)
	local R = makeR(K, V)
	if V.type == "bowlobby" then
		buildLobby(R)
	end
end

return T
