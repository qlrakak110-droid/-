--!strict
-- GwangalliBuildingInterior/T_facility: 큰 시설의 부속 방 (restroom corridor office elevhall) 실내 (Venues.luau 의 방, Scan.fitRoom).
--   style(V) -> S  Common 단계는 모두 끔 (벽 · 천장이 맵에서 약 0.95 도 돌아가 있어서, 마감은 전부 '정렬 프레임' 에서 직접 지음)
--   build(K, V, S) 유형별 디테일
--
-- 방 (광안 락볼링빌딩, Workspace.Gwangalli.bowling):
--   restroom  남자 / 여자 화장실 (11x22.6, 천장 10.8): 대형 포세린 벽 · 바닥 타일 + 줄눈 · 배수구, 알루미늄 스트립 천장 + 다운라이트 ·
--             환풍기 (돌아감) · 스프링클러 · 열감지기 · 스피커, 칸 2 (HPL 칸막이 · 스테인리스 헤드레일 · 경첩 · 사용중 표시 잠금 ·
--             양변기 + 비데 · 센서 세척밸브 · 점보롤 휴지걸이 · 휴대폰 선반 · 옷걸이 · 비상벨 · 안내문), 청소도구함 · 점검구 문,
--             세면대 (다크 마블 피처월 · 탑볼 2 · 센서 수전 · 거품 비누 · 백라이트 거울), 핸드드라이어 · 페이퍼타올 + 휴지통,
--             손 씻기 6단계 · 금연 · 청소 점검표 · 불법촬영 점검 · 방향제 · 안심 비상벨,
--             남: 소변기 4 (어린이용 1) + 가림판 + 센서 + 트렌치 배수 + 소변기 위 홍보 액자 / 여: 파우더 선반 + 원형 LED 거울 ·
--             기저귀 교환대 (접었다 폈다) · 무료 생리대함 · 칸마다 위생용품 수거함 · 유아 보호의자
--   corridor  락볼링 복도 (28x40): 내린 천장 (블랙 텍스 + 라인 조명) · 다크 HPL 징두리 + 퍼플 LED 라인 · 화장실 입구 픽토그램 ·
--             유료 보관함 30칸 (번호 · 열쇠) · 자판기 2 (진짜 진열 · 가격 · 동전 · 카드 · 취출구) · 정수기 디테일 · 분리수거함 ·
--             옥내소화전함 + 발신기 · 게시판 · 디지털 사이니지 · 벤치 · 볼링화 살균기 · 통로유도등 · 비상구 패닉바 · CCTV
--   office    사무실 · 창고 (14.7x22.8): 책상 + 모니터 (CCTV 분할 화면) · 사무 의자 · 금고 · 서류장 · 앵글 선반 + 재고 박스 ·
--             스코어 서버 랙 · 화이트보드 근무표 · 분전함 · 핸드카트 · 셔터 하역 구역 표시
--   elevhall  1F 엘리베이터 홀 / 2F~4F 엘리베이터 홀: 스톤 클래딩 (버튼은 그대로) · 스테인리스 문 · 층 표시기 (애니메이션) ·
--             층별 안내 (넘겨 보기) · 우편함 (열어 보기) · 우산 비닐 · CCTV · 소화전 / 2F+: 롤스크린 (올리고 내리기) · 벤치 ·
--             사이니지 TV · 소화전함 · 정수기 · 게시판
-- 상호작용 (클라이언트 전용, 서버 행동과 겹치지 않음): 화장실 칸 잠그기 · 손 씻기 · 손 말리기 · 기저귀 교환대 / 보관함 문 ·
--   사이니지 넘기기 · 손 소독 / CCTV 채널 · 금고 문 · 스탠드 / 층별 안내 · 우편함 · 롤스크린
-- 게임플레이 계약 (bowling.json): ElevatorButton_* · ButtonPlate · ElevatorStop_* · Destination_* · 계단 · 입구 · VendingMachine 의
--   충돌 상자는 그대로. 버튼 앞 1.6 · 패드 · 계단 · 입구는 비움 (keep). 버튼 6.5 안에 우리 프롬프트 없음.
--   숨기는 것 (장식 파트만, 같은 자리에 더 나은 것): 화장실 StallPanel · StallDoor · Toilet · SinkCounter · Basin · Mirror · Wainscot,
--   복도 Lockers · LockerSeam · 자판기 Body/Display/Can, 홀 Sign_▲ · Sign_층별 안내 · Mailbox · Bench/BenchBase.

local Look = require(script.Parent:WaitForChild("Look"))
local Props = require(script.Parent:WaitForChild("Props"))
local Interact = require(script.Parent:WaitForChild("Interact"))
local Scan = require(script.Parent:WaitForChild("Scan"))
local Kit = require(script.Parent:WaitForChild("Kit"))
local TweenService = game:GetService("TweenService")

local T = {}
T.types = { "restroom", "corridor", "office", "elevhall" }

local CF, V3 = CFrame.new, Vector3.new
local ANG = CFrame.Angles
local PI = math.pi
local M = Enum.Material
local F = Enum.Font
local rgb = Color3.fromRGB
local BLACK, WHITE = Color3.new(0, 0, 0), Color3.new(1, 1, 1)

-- 재질 ------------------------------------------------------------------------------------------------
local function lk(r: number, g: number, b: number, m: Enum.Material?, extra: { [string]: any }?): { [string]: any }
	local t: { [string]: any } = { c = rgb(r, g, b), m = m or M.SmoothPlastic }
	if extra then
		for k, v in extra do
			t[k] = v
		end
	end
	return t
end
local function nl(c: Color3, t: number?): { [string]: any }
	return { c = c, m = M.Neon, t = t or 0 }
end
local function gl(c: Color3?, t: number?): { [string]: any }
	return { c = c or rgb(220, 232, 238), m = M.Glass, t = t or 0.6, r = 0.12 }
end

local PORC = lk(248, 248, 246, M.SmoothPlastic, { r = 0.06 }) -- 위생도기
local PORC_IN = lk(222, 226, 228, M.SmoothPlastic) -- 도기 안쪽 (그늘)
local CHROME = lk(214, 218, 222, M.Metal, { r = 0.3 })
local SST = lk(176, 180, 184, M.Metal, { r = 0.1 }) -- 헤어라인 스테인리스
local SST_D = lk(120, 124, 128, M.Metal)
local MIRROR = { c = rgb(150, 162, 172), m = M.Glass, t = 0, r = 0.35 }
local HPL = lk(96, 70, 52, M.Wood) -- 칸막이 HPL (월넛)
local HPL_EDGE = lk(58, 44, 34, M.Wood)
local BLK = lk(24, 24, 26)
local WHT = lk(244, 244, 240)
local PAPER = lk(248, 246, 238)

-- 작은 도구 ----------------------------------------------------------------------------------------
local function rnd(seed: number, i: number): number
	local s = math.sin((seed % 9973) * 0.731 + i * 12.9898) * 43758.5453
	return s - math.floor(s)
end
local function hi(K: any): boolean
	return K.detail == "high"
end
local function tween(p: BasePart?, goal: { [string]: any }, t: number?)
	if p and p.Parent then
		TweenService:Create(p, TweenInfo.new(t or 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	end
end
local function sound(part: BasePart?, id: string, vol: number?, dur: number?)
	if not part or part.Parent == nil then
		return
	end
	local s = Instance.new("Sound")
	s.Name = "GwFacilitySound"
	s.SoundId = id
	s.Volume = vol or 0.4
	s.RollOffMaxDistance = 28
	s.Parent = part
	s:Play()
	task.delay(dur or 3, function()
		s:Destroy()
	end)
end
local SND_WATER = "rbxasset://sounds/swoosh.wav"
local SND_CLICK = "rbxasset://sounds/clickfast.wav"
local SND_DOOR = "rbxasset://sounds/button.wav"

-- 정렬 프레임 -------------------------------------------------------------------------------------------
-- 맵에서 잰 벽 안쪽 면 (정렬 프레임). 방 프레임 (월드 축) 에서 건물이 0.01651 rad 돌아가 있음.
local ROOMS: { [string]: any } = {
	wc_m = { x0 = -5.55, x1 = 5.65, z0 = -11.38, z1 = 11.32, H = 10.81 },
	wc_f = { x0 = -5.55, x1 = 5.65, z0 = -11.48, z1 = 11.22, H = 10.81 },
	office = { x0 = -7.46, x1 = 7.19, z0 = -11.31, z1 = 11.39, H = 10.81 },
	corridor = { x0 = -14.5, x1 = 13.8, z0 = -20.19, z1 = 20.1, H = 21.9 },
	elevhall = { x0 = -6.2, x1 = 6.5, z0 = -10.18, z1 = 10.8, H = 11.81 },
	hall2 = { x0 = -10.42, x1 = 10.3, z0 = -10.5, z1 = 10.4, H = 9.48 },
	hall3 = { x0 = -10.42, x1 = 10.3, z0 = -10.5, z1 = 10.4 },
	hall4 = { x0 = -10.42, x1 = 10.3, z0 = -10.5, z1 = 10.4 },
}

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

local function makeRoom(K: any, V: any): any
	local spec = ROOMS[V.room or ""] or {}
	local yaw: number? = nil
	local best = 0
	for _, r in V.parts do
		if r.name == "Wall" or r.name == "Divider" or string.find(r.name, "Floor", 1, true) or string.find(r.name, "Ceiling", 1, true) then
			local s = r.part.Size
			local a = math.max(s.X, s.Z) * math.max(s.Y, 1)
			if a > best then
				best = a
				yaw = yawOf(r.lcf)
			end
		end
	end
	local y = yaw or 0.01651
	local R: any = { K = K, V = V, A = ANG(0, y, 0), yaw = y }
	R.x0, R.x1 = spec.x0 or V.x0, spec.x1 or V.x1
	R.z0, R.z1 = spec.z0 or V.z0, spec.z1 or V.z1
	-- 천장: 맵 천장 파트의 아랫면 (없으면 V.H)
	local H = spec.H
	if not H then
		for _, r in V.parts do
			if string.find(r.name, "Ceiling", 1, true) and r.size.X > V.W * 0.6 and r.min.Y > 4 and r.min.Y < V.H + 0.6 then
				H = r.min.Y
			end
		end
	end
	R.H = H or V.H
	R.cx, R.cz = (R.x0 + R.x1) / 2, (R.z0 + R.z1) / 2
	R.W, R.D = R.x1 - R.x0, R.z1 - R.z0
	K:note(string.format("aligned yaw=%.4f x %.2f..%.2f z %.2f..%.2f H %.2f", y, R.x0, R.x1, R.z0, R.z1, R.H))
	return R
end

-- 정렬 프레임 → 방 프레임
local function fc(R: any, x: number, y: number, z: number, yaw: number?): CFrame
	return R.A * CF(x, y, z) * ANG(0, yaw or 0, 0)
end
local function ap(R: any, x: number, y: number, z: number): Vector3
	return R.A * V3(x, y, z)
end
-- 벽 표시면 dcf (side = "L" | "R" | "B" | "F"; u = 그 벽을 따라가는 정렬 좌표 (L/R = z, B/F = x))
local function wf(R: any, side: string, u: number, y: number, off: number?): CFrame
	local o = off or 0
	if side == "L" then
		return fc(R, R.x0 + o, y, u, PI / 2)
	elseif side == "R" then
		return fc(R, R.x1 - o, y, u, -PI / 2)
	elseif side == "B" then
		return fc(R, u, y, R.z0 + o, 0)
	end
	return fc(R, u, y, R.z1 - o, PI)
end
-- 위를 보는 면 (바닥 글자 · 판 윗면): 글자 위쪽 = 정렬 -Z
local function upF(R: any, x: number, y: number, z: number, yaw: number?): CFrame
	return fc(R, x, y, z, yaw) * ANG(-PI / 2, 0, 0)
end

-- 프리미티브 (정렬 프레임 CFrame / 점)
local function bx(R: any, n: string, s: Vector3, c: CFrame, l: any): BasePart
	return R.K:box(n, s, R.A * c, l)
end
local function wd(R: any, n: string, s: Vector3, c: CFrame, l: any): BasePart
	return R.K:wedge(n, s, R.A * c, l)
end
local function cy(R: any, n: string, len: number, d: number, c: CFrame, l: any): BasePart
	return R.K:cyl(n, len, d, R.A * c, l)
end
local function vc(R: any, n: string, h: number, d: number, c: CFrame, l: any): BasePart
	return R.K:vcyl(n, h, d, R.A * c, l)
end
local function bl(R: any, n: string, d: number, c: CFrame, l: any): BasePart
	return R.K:ball(n, d, R.A * c, l)
end
local function el(R: any, n: string, s: Vector3, c: CFrame, l: any): BasePart
	return R.K:ell(n, s, R.A * c, l)
end
local function sg(R: any, n: string, a: Vector3, b: Vector3, d: number, l: any): BasePart?
	return R.K:seg(n, R.A * a, R.A * b, d, l)
end
local function br(R: any, n: string, a: Vector3, b: Vector3, w: number, h: number, l: any): BasePart?
	return R.K:bar(n, R.A * a, R.A * b, w, h, l)
end
-- dcf 는 이미 방 프레임 (wf / fc 결과)
local function pl(R: any, n: string, w: number, h: number, d: number, dcf: CFrame, l: any): BasePart
	return R.K:plate(n, w, h, d, dcf, l)
end
local function dk(R: any, n: string, dia: number, t: number, c: CFrame, l: any): BasePart
	return R.K:disc(n, dia, t, R.A * c, l)
end
-- 표시면(dcf, 방 프레임)에 붙는 원판 (축 = dcf Z)
local function wdisc(R: any, n: string, dia: number, t: number, dcf: CFrame, l: any): BasePart
	return R.K:disc(n, dia, t, dcf * CF(0, 0, t / 2) * ANG(PI / 2, 0, 0), l)
end
local function tx(R: any, n: string, w: number, h: number, dcf: CFrame, s: string, fg: Color3, bg: Color3?, font: Enum.Font?, glow: number?, o: any?): (BasePart, TextLabel)
	local op: any = { fg = fg, bg = bg, font = font or F.GothamBold, glow = glow, d = 0.02 }
	if o then
		for k, v in o do
			op[k] = v
		end
	end
	return R.K:text(n, w, h, dcf, s, op)
end
local function light(R: any, p: BasePart?, kind: string, props: { [string]: any }): Light?
	if not p then
		return nil
	end
	return R.K:light(p, kind, props)
end

-- 바닥 소품 자리 (정렬 프레임 점 x,z · 방향 yaw · 크기)
local function spot(R: any, x: number, z: number, yaw: number, size: Vector3, pad: number?): boolean
	return R.K:spot(fc(R, x, 0, z, yaw), size, pad)
end

-- 정렬 상자 → keep (긴 상자는 8 스터드 조각으로)
local function keepBox(R: any, x0: number, z0: number, x1: number, z1: number, y1: number, kind: string, y0: number?)
	local yb = y0 or 0.1
	local ax0, ax1 = math.min(x0, x1), math.max(x0, x1)
	local az0, az1 = math.min(z0, z1), math.max(z0, z1)
	local nx = math.max(1, math.ceil((ax1 - ax0) / 8))
	local nz = math.max(1, math.ceil((az1 - az0) / 8))
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			local xa = ax0 + (ax1 - ax0) * i / nx
			local xb = ax0 + (ax1 - ax0) * (i + 1) / nx
			local za = az0 + (az1 - az0) * j / nz
			local zb = az0 + (az1 - az0) * (j + 1) / nz
			local c = R.A * CF((xa + xb) / 2, (yb + y1) / 2, (za + zb) / 2)
			local mn, mx = Kit.laabb(c, V3(xb - xa, y1 - yb, zb - za))
			R.V:addKeep(mn, mx, kind)
		end
	end
end

-- 맵 파트 (V.parts rec) 의 정렬 AABB
local function abox(R: any, rec: any): (Vector3, Vector3)
	return Kit.laabb(R.A:ToObjectSpace(rec.lcf), rec.part.Size)
end
local function recs(V: any, name: string): { any }
	return V.byName[name] or {}
end
local function hide(R: any, rec: any)
	Scan.hide(R.K.hidden, rec.part)
end
local function hideAll(R: any, name: string)
	for _, r in recs(R.V, name) do
		hide(R, r)
	end
end

-- 월드 좌표의 맵 파트 찾기 (방 모델 밖에 있는 엘리베이터 버튼 · 패드 같은 것)
local function worldFind(R: any, prefix: string, pad: number): { any }
	local out = {}
	local V = R.V
	local root = workspace:FindFirstChild("Gwangalli")
	local scope: Instance? = root and (root:FindFirstChild("bowling") or root) or nil
	if not scope then
		return out
	end
	local ok, list = pcall(function()
		return (scope :: Instance):GetDescendants()
	end)
	if not ok then
		return out
	end
	for _, d in list do
		if d:IsA("BasePart") and string.sub(d.Name, 1, #prefix) == prefix then
			local lc = V.cf:ToObjectSpace(d.CFrame)
			local p = lc.Position
			if p.X > V.x0 - pad and p.X < V.x1 + pad and p.Z > V.z0 - pad and p.Z < V.z1 + pad and p.Y > -2 and p.Y < V.H + 2 then
				local amn, amx = Kit.laabb(R.A:ToObjectSpace(lc), d.Size)
				table.insert(out, { part = d, name = d.Name, min = amn, max = amx, c = (amn + amx) / 2 })
			end
		end
	end
	return out
end

-- 우리 프롬프트가 피할 서버 앵커 추가 (엘리베이터 버튼 등): K.hostPts 를 미리 만들어 둠
local function addHost(R: any, p: Vector3)
	local K = R.K
	if not K.hostPts then
		K.hostPts = Interact.hostPoints(R.V)
	end
	table.insert(K.hostPts, R.A * p)
end

-- 공통 마감 도구 ------------------------------------------------------------------------------------------

-- 벽 타일: 판 + 줄눈 (u0..u1 = 벽 좌표, y0..y1). o.tw / o.th (타일), o.grout, o.off, o.ug (u 방향 줄눈 기준)
local function tiles(R: any, side: string, u0: number, u1: number, y0: number, y1: number, look: any, o: any?)
	local op: any = o or {}
	local off = op.off or 0
	local tw, th = op.tw or 1.8, op.th or 0.9
	local grout = op.grout or lk(186, 182, 176)
	local a, b = math.min(u0, u1), math.max(u0, u1)
	local len, hh = b - a, y1 - y0
	if len < 0.05 or hh < 0.05 then
		return
	end
	R.K:free(function()
		pl(R, op.name or "WallTile", len, hh, 0.03, wf(R, side, (a + b) / 2, (y0 + y1) / 2, off), look)
		local base = op.y0 or 0
		local k0 = math.floor((y0 - base) / th) + 1
		local y = base + k0 * th
		while y < y1 - 0.06 do
			if y > y0 + 0.06 then
				pl(R, "TileGrout", len, 0.03, 0.036, wf(R, side, (a + b) / 2, y, off), grout)
			end
			y += th
		end
		if op.noV then
			return
		end
		local ug = op.ug or 0
		local u = ug + math.floor((a - ug) / tw + 1) * tw
		while u < b - 0.06 do
			if u > a + 0.06 then
				pl(R, "TileGrout", 0.03, hh, 0.036, wf(R, side, u, (y0 + y1) / 2, off), grout)
			end
			u += tw
		end
	end)
end

-- 바닥 타일 (정렬 상자 x0..x1, z0..z1): 판 + 줄눈
local function floorTiles(R: any, x0: number, x1: number, z0: number, z1: number, look: any, grout: any, t: number, y: number?, name: string?)
	local yy = y or 0.012
	R.K:free(function()
		bx(R, name or "FloorTile", V3(x1 - x0, 0.024, z1 - z0), CF((x0 + x1) / 2, yy, (z0 + z1) / 2), look)
		local x = math.floor(x0 / t + 1) * t
		while x < x1 - 0.05 do
			bx(R, "FloorGrout", V3(0.04, 0.026, z1 - z0 - 0.02), CF(x, yy + 0.002, (z0 + z1) / 2), grout)
			x += t
		end
		local z = math.floor(z0 / t + 1) * t
		while z < z1 - 0.05 do
			bx(R, "FloorGrout", V3(x1 - x0 - 0.02, 0.026, 0.04), CF((x0 + x1) / 2, yy + 0.002, z), grout)
			z += t
		end
	end)
end

-- 천장 설비 (정렬 x, z; 천장 아랫면 y)
local function sprinkler(R: any, x: number, z: number, y: number)
	R.K:free(function()
		dk(R, "SprinklerRose", 0.32, 0.03, CF(x, y - 0.015, z), WHT)
		vc(R, "SprinklerBody", 0.16, 0.09, CF(x, y - 0.1, z), lk(186, 152, 88, M.Metal))
		dk(R, "SprinklerDeflector", 0.22, 0.02, CF(x, y - 0.2, z), lk(186, 152, 88, M.Metal))
		vc(R, "SprinklerBulb", 0.1, 0.04, CF(x, y - 0.13, z + 0.03), nl(rgb(230, 60, 50), 0.2))
	end)
end
local function detector(R: any, x: number, z: number, y: number, kind: string?)
	R.K:free(function()
		dk(R, "DetectorBase", 0.62, 0.05, CF(x, y - 0.025, z), WHT)
		dk(R, if kind == "heat" then "HeatDetector" else "SmokeDetector", 0.5, 0.16, CF(x, y - 0.12, z), WHT)
		if kind == "heat" then
			vc(R, "HeatDetectorTip", 0.12, 0.16, CF(x, y - 0.25, z), lk(40, 40, 42))
		else
			for i = 0, 5 do
				local a = i * PI / 3
				bx(R, "DetectorSlot", V3(0.04, 0.1, 0.14), CF(x + math.cos(a) * 0.22, y - 0.14, z + math.sin(a) * 0.22) * ANG(0, -a, 0), lk(200, 200, 198))
			end
		end
		dk(R, "DetectorLED", 0.05, 0.02, CF(x + 0.15, y - 0.205, z), nl(rgb(255, 50, 40)))
	end)
end
local function cctvDome(R: any, x: number, z: number, y: number)
	R.K:free(function()
		dk(R, "CCTVBase", 0.72, 0.08, CF(x, y - 0.04, z), WHT)
		el(R, "CCTVDome", V3(0.56, 0.5, 0.56), CF(x, y - 0.08, z), { c = rgb(30, 34, 40), m = M.Glass, t = 0.2, r = 0.25 })
		bl(R, "CCTVLens", 0.14, CF(x, y - 0.24, z + 0.08), lk(10, 10, 12))
		dk(R, "CCTVLED", 0.04, 0.02, CF(x + 0.27, y - 0.09, z), nl(rgb(255, 40, 40)))
	end)
end
local function speaker(R: any, x: number, z: number, y: number)
	R.K:free(function()
		dk(R, "CeilSpeakerRim", 0.8, 0.04, CF(x, y - 0.02, z), WHT)
		dk(R, "CeilSpeakerGrille", 0.68, 0.03, CF(x, y - 0.04, z), lk(226, 226, 222, M.DiamondPlate))
	end)
end
-- 매입 다운라이트 (정렬 x,z). withLight = SpotLight
local function downlight(R: any, x: number, z: number, y: number, o: any?)
	local op: any = o or {}
	local d = op.dia or 0.75
	local lens
	R.K:free(function()
		dk(R, "DownlightTrim", d, 0.04, CF(x, y - 0.02, z), op.trim or WHT)
		dk(R, "DownlightReflector", d * 0.82, 0.045, CF(x, y - 0.025, z), lk(200, 200, 198, M.Metal))
		lens = dk(R, "DownlightLens", d * 0.6, 0.03, CF(x, y - 0.045, z), op.glow or nl(rgb(255, 240, 222)))
	end)
	if op.light and lens then
		light(R, lens, "SpotLight", { Face = Enum.NormalId.Bottom, Range = op.range or 16, Brightness = op.bright or 1.1, Angle = op.angle or 90, Color = op.color or rgb(255, 236, 214) })
	end
	return lens
end
-- 비상조명등 (천장/벽 박스, 녹색 충전 LED)
local function emergencyLight(R: any, dcf: CFrame)
	pl(R, "EmergencyLightBox", 1.1, 0.42, 0.24, dcf, WHT)
	pl(R, "EmergencyLightLens", 0.8, 0.22, 0.02, dcf * CF(0, -0.02, 0.24), lk(250, 250, 246, M.Glass, { t = 0.2 }))
	wdisc(R, "EmergencyLightLED", 0.06, 0.02, dcf * CF(0.45, 0.12, 0.24), nl(rgb(60, 230, 90)))
	tx(R, "EmergencyLightLabel", 0.5, 0.1, dcf * CF(-0.25, 0.14, 0.245), "비상조명등", rgb(80, 80, 80), nil, F.GothamBold)
end

-- 인쇄물 (얇은 종이 + 글자, 투명 아크릴 꽂이 선택)
local function notice(R: any, n: string, w: number, h: number, dcf: CFrame, title: string, body: string?, o: any?)
	local op: any = o or {}
	local bg: Color3 = op.bg or rgb(250, 249, 244)
	local fg: Color3 = op.fg or rgb(30, 30, 32)
	local acc: Color3 = op.acc or rgb(200, 30, 36)
	if op.holder then
		pl(R, n .. "Holder", w + 0.14, h + 0.14, 0.04, dcf, lk(230, 232, 234, M.Glass, { t = 0.5 }))
		dcf = dcf * CF(0, 0, 0.04)
	end
	pl(R, n .. "Sheet", w, h, 0.012, dcf, { c = bg, m = M.SmoothPlastic })
	local th = if body then math.min(h * 0.26, 0.55) else h * 0.9
	tx(R, n .. "Title", w * 0.92, th, dcf * CF(0, if body then h / 2 - th / 2 - 0.05 else 0, 0.013), title, acc, nil, op.font or F.GothamBlack)
	if body then
		local bh = h - th - 0.16
		tx(R, n .. "Body", w * 0.9, bh, dcf * CF(0, -h / 2 + bh / 2 + 0.06, 0.013), body, fg, nil, F.GothamMedium, nil, { wrap = op.wrap })
	end
end

-- 금연 표지 (원 + 사선 픽토그램 + 글자)
local function noSmoking(R: any, dcf: CFrame, s: number?)
	local k = s or 1
	pl(R, "NoSmokingPlate", 1.3 * k, 1.75 * k, 0.03, dcf, WHT)
	local c = dcf * CF(0, 0.22 * k, 0.03)
	wdisc(R, "NoSmokingRing", 0.95 * k, 0.012, c, lk(206, 30, 36))
	wdisc(R, "NoSmokingFace", 0.78 * k, 0.014, c, WHT)
	pl(R, "NoSmokingCig", 0.56 * k, 0.1 * k, 0.012, c * CF(0, 0, 0.016), lk(60, 60, 62))
	pl(R, "NoSmokingCigTip", 0.1 * k, 0.1 * k, 0.012, c * CF(0.33 * k, 0, 0.016), lk(230, 120, 40))
	pl(R, "NoSmokingBar", 0.84 * k, 0.09 * k, 0.012, c * CF(0, 0, 0.03) * ANG(0, 0, PI / 4), lk(206, 30, 36))
	tx(R, "NoSmokingText", 1.16 * k, 0.32 * k, dcf * CF(0, -0.5 * k, 0.031), "금 연", lk(206, 30, 36).c, nil, F.GothamBlack)
	tx(R, "NoSmokingFine", 1.16 * k, 0.16 * k, dcf * CF(0, -0.76 * k, 0.031), "위반 시 과태료 10만원", rgb(60, 60, 60), nil, F.GothamBold)
end

-- 사람 픽토그램 (남 = 파랑 바지, 여 = 빨강 치마). dcf 중심, h 높이
local function pictogram(R: any, dcf: CFrame, h: number, female: boolean, c: Color3)
	local k = h / 2.4
	local look = { c = c, m = M.SmoothPlastic }
	wdisc(R, "PictoHead", 0.5 * k, 0.03, dcf * CF(0, 0.9 * k, 0), look)
	if female then
		pl(R, "PictoBody", 0.56 * k, 0.6 * k, 0.03, dcf * CF(0, 0.35 * k, 0), look)
		R.K:wedge("PictoSkirtL", V3(0.03, 0.75 * k, 0.24 * k), dcf * CF(-0.4 * k, -0.25 * k, 0.015) * ANG(0, PI / 2, 0), look)
		R.K:wedge("PictoSkirtR", V3(0.03, 0.75 * k, 0.24 * k), dcf * CF(0.4 * k, -0.25 * k, 0.015) * ANG(0, -PI / 2, 0), look)
		pl(R, "PictoSkirt", 0.56 * k, 0.75 * k, 0.03, dcf * CF(0, -0.25 * k, 0), look)
		pl(R, "PictoLeg", 0.13 * k, 0.5 * k, 0.03, dcf * CF(-0.13 * k, -0.86 * k, 0), look)
		pl(R, "PictoLeg", 0.13 * k, 0.5 * k, 0.03, dcf * CF(0.13 * k, -0.86 * k, 0), look)
	else
		pl(R, "PictoBody", 0.6 * k, 0.85 * k, 0.03, dcf * CF(0, 0.22 * k, 0), look)
		pl(R, "PictoLeg", 0.24 * k, 0.95 * k, 0.03, dcf * CF(-0.15 * k, -0.68 * k, 0), look)
		pl(R, "PictoLeg", 0.24 * k, 0.95 * k, 0.03, dcf * CF(0.15 * k, -0.68 * k, 0), look)
	end
	pl(R, "PictoArm", 0.13 * k, 0.75 * k, 0.03, dcf * CF(-0.4 * k, 0.2 * k, 0), look)
	pl(R, "PictoArm", 0.13 * k, 0.75 * k, 0.03, dcf * CF(0.4 * k, 0.2 * k, 0), look)
end

-- 손 씻기 6단계 포스터
local function handwashPoster(R: any, dcf: CFrame)
	pl(R, "HandwashFrame", 2.3, 3.1, 0.04, dcf, lk(236, 238, 240, M.Glass, { t = 0.3 }))
	local d = dcf * CF(0, 0, 0.04)
	pl(R, "HandwashSheet", 2.2, 3.0, 0.012, d, PAPER)
	pl(R, "HandwashBand", 2.2, 0.5, 0.014, d * CF(0, 1.25, 0), lk(30, 120, 190))
	tx(R, "HandwashTitle", 2.0, 0.36, d * CF(0, 1.25, 0.015), "올바른 손 씻기 6단계", WHITE, nil, F.GothamBlack)
	local steps = { "① 손바닥", "② 손등", "③ 손가락 사이", "④ 두 손 모아", "⑤ 엄지 손가락", "⑥ 손톱 밑" }
	for i = 1, 6 do
		local cx = if i % 2 == 1 then -0.53 else 0.53
		local cyy = 0.62 - math.floor((i - 1) / 2) * 0.78
		local c = d * CF(cx, cyy, 0.014)
		pl(R, "HandwashCell", 0.96, 0.7, 0.012, c, lk(232, 242, 250))
		wdisc(R, "HandwashHand", 0.34, 0.012, c * CF(-0.22, 0.06, 0), lk(244, 196, 160))
		wdisc(R, "HandwashHand", 0.3, 0.012, c * CF(-0.08, 0.1, 0.004), lk(236, 184, 148))
		for k = 0, 2 do
			wdisc(R, "HandwashBubble", 0.1, 0.012, c * CF(-0.36 + k * 0.12, -0.2, 0.004), lk(150, 200, 236))
		end
		tx(R, "HandwashStep", 0.52, 0.2, c * CF(0.2, 0.0, 0.004), steps[i], rgb(20, 60, 110), nil, F.GothamBold)
	end
	tx(R, "HandwashFoot", 2.0, 0.22, d * CF(0, -1.36, 0.015), "흐르는 물에 비누로 30초 이상", rgb(30, 90, 150), nil, F.GothamBold)
end

-- 청소 점검표 (클립보드)
local function cleaningSheet(R: any, dcf: CFrame, who: string)
	pl(R, "ClipboardBack", 1.25, 1.75, 0.04, dcf, lk(120, 84, 52, M.Wood))
	pl(R, "ClipboardClip", 0.6, 0.16, 0.08, dcf * CF(0, 0.82, 0.03), SST)
	local d = dcf * CF(0, -0.04, 0.04)
	pl(R, "CleanSheet", 1.1, 1.5, 0.01, d, PAPER)
	tx(R, "CleanTitle", 1.0, 0.18, d * CF(0, 0.62, 0.011), "화장실 청소 점검표", rgb(20, 20, 22), nil, F.GothamBlack)
	local times = { "09:00", "12:00", "15:00", "18:00", "21:00", "24:00" }
	for i, t in times do
		local y = 0.42 - (i - 1) * 0.19
		pl(R, "CleanRule", 1.0, 0.012, 0.012, d * CF(0, y - 0.095, 0.011), lk(150, 150, 150))
		tx(R, "CleanTime", 0.36, 0.13, d * CF(-0.3, y, 0.011), t, rgb(40, 40, 40), nil, F.GothamMedium)
		if i <= 5 then
			tx(R, "CleanSign", 0.4, 0.13, d * CF(0.24, y, 0.011), if i % 2 == 0 then who else "김OO ✓", rgb(30, 50, 160), nil, F.PermanentMarker)
		end
	end
end

-- 휴지통 (스테인리스 사각, 위 열림) pcf 바닥
local function binSquare(R: any, x: number, z: number, yaw: number, h: number, label: string?)
	local pcf = fc(R, x, 0, z, yaw)
	R.K:box("BinBody", V3(1.1, h, 0.8), R.A:Inverse() * R.A * pcf * CF(0, h / 2, 0), SST)
	R.K:box("BinRim", V3(1.16, 0.08, 0.86), pcf * CF(0, h - 0.04, 0), SST_D)
	R.K:box("BinBag", V3(1.0, 0.04, 0.7), pcf * CF(0, h - 0.12, 0), lk(30, 30, 32))
	R.K:box("BinFoot", V3(1.04, 0.08, 0.74), pcf * CF(0, 0.04, 0), BLK)
	if label then
		R.K:text("BinLabel", 0.8, 0.24, pcf * CF(0, h * 0.62, 0.41), label, { fg = rgb(30, 30, 32), d = 0.01, font = F.GothamBold })
	end
end

-- ==========================================================================================================
-- 화장실 (restroom)
-- ==========================================================================================================

-- 칸 문 (모델) : hingeX 쪽 경첩, 닫힌 면 z = zf, 문 폭 w. 반환 { model, handle, setState }
local function stallDoor(R: any, idx: number, xa: number, xb: number, zf: number, hingeLeft: boolean, female: boolean, startOpen: boolean): any
	local K = R.K
	local w = xb - xa
	local y0, y1 = 0.55, 6.85
	local h = y1 - y0
	local zc = zf - 0.07
	local hingeX = if hingeLeft then xa else xb
	local latchSign = if hingeLeft then 1 else -1 -- 경첩 반대쪽 (+x 방향이면 1)
	local parts: any = {}
	local ind: TextLabel? = nil
	local indPart: BasePart? = nil
	local handle: BasePart? = nil
	local model = K:group("StallDoor_" .. idx, function()
		local cx = (xa + xb) / 2
		bx(R, "StallDoorLeaf", V3(w - 0.04, h, 0.12), CF(cx, (y0 + y1) / 2, zc), HPL)
		bx(R, "StallDoorEdge", V3(w, 0.04, 0.13), CF(cx, y1 - 0.02, zc), HPL_EDGE)
		bx(R, "StallDoorEdge", V3(w, 0.04, 0.13), CF(cx, y0 + 0.02, zc), HPL_EDGE)
		-- 경첩 3개 (스테인리스 원통)
		for _, yy in { y0 + 0.6, (y0 + y1) / 2, y1 - 0.6 } do
			cy(R, "StallHinge", 0.04, 0.12, CF(hingeX + latchSign * 0.04, yy, zc + 0.08) * ANG(0, 0, PI / 2), SST)
			bx(R, "StallHingeLeaf", V3(0.35, 0.45, 0.02), CF(hingeX + latchSign * 0.2, yy, zc + 0.07), SST)
		end
		-- 표시 잠금 (바깥 +Z 면): 스테인리스 판 + 창 (비어있음 초록 / 사용중 빨강)
		local lx = (if hingeLeft then xb else xa) - latchSign * 0.32
		bx(R, "StallLockPlate", V3(0.34, 0.7, 0.03), CF(lx, 3.65, zf + 0.0), SST)
		local ip, il = tx(R, "StallIndicator", 0.26, 0.16, fc(R, lx, 3.82, zf + 0.016, 0), "비어있음", WHITE, rgb(30, 150, 70), F.GothamBold, 0.6)
		indPart, ind = ip, il
		-- 손잡이 (D 형 풀 핸들)
		local hp = bx(R, "StallHandle", V3(0.06, 0.62, 0.06), CF(lx, 3.2, zf + 0.2), CHROME)
		sg(R, "StallHandleArm", V3(lx, 3.46, zf + 0.0), V3(lx, 3.46, zf + 0.2), 0.05, CHROME)
		sg(R, "StallHandleArm", V3(lx, 2.94, zf + 0.0), V3(lx, 2.94, zf + 0.2), 0.05, CHROME)
		handle = hp
		-- 안쪽 (-Z 면): 옷걸이 + 잠금 손잡이 + 안내문
		local inz = zc - 0.06
		bx(R, "StallHookBase", V3(0.16, 0.24, 0.04), CF(lx, 5.9, inz - 0.02), CHROME)
		sg(R, "StallHook", V3(lx, 5.88, inz - 0.04), V3(lx, 6.02, inz - 0.28), 0.06, CHROME)
		bl(R, "StallHookTip", 0.1, CF(lx, 6.04, inz - 0.29), CHROME)
		bx(R, "StallLockKnob", V3(0.12, 0.24, 0.1), CF(lx, 3.65, inz - 0.05), CHROME)
		local nd = fc(R, (xa + xb) / 2, 4.6, inz - 0.001, PI)
		notice(R, "StallInNotice", 1.2, 0.9, nd, "휴지는 변기에!", "사용한 화장지는 변기에 넣고\n물을 내려 주세요\n(물티슈 · 위생용품 제외)", { acc = rgb(20, 90, 170) })
		-- 바깥 면: 칸 번호 + 안심 스티커
		local od = fc(R, (xa + xb) / 2, 5.6, zf + 0.002, 0)
		wdisc(R, "StallNumberPlate", 0.5, 0.02, od, SST)
		tx(R, "StallNumber", 0.36, 0.3, od * CF(0, 0, 0.021), tostring(idx), rgb(30, 30, 32), nil, F.GothamBlack)
		if female or idx == 1 then
			local sd = fc(R, (xa + xb) / 2, 4.55, zf + 0.002, 0)
			pl(R, "SafeSticker", 0.9, 0.42, 0.01, sd, lk(255, 224, 70))
			tx(R, "SafeStickerText", 0.84, 0.36, sd * CF(0, 0, 0.011), "불법촬영 점검 완료\n안심 화장실 · 부산경찰", rgb(30, 30, 30), nil, F.GothamBold)
		end
	end)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, { p = d, cf = d.CFrame })
		end
	end
	local hingeW = K.cf * (R.A * V3(hingeX, 0, zf - 0.07))
	local axis = (K.cf * R.A).YVector
	local openA = (if hingeLeft then 1 else -1) * math.rad(78) -- 안쪽 (-Z) 으로
	local function set(open: boolean, closedLocked: boolean, instant: boolean?)
		local a = if open then openA else 0
		local rot = CFrame.new(hingeW) * CFrame.fromAxisAngle(axis, a) * CFrame.new(-hingeW)
		for _, r in parts do
			if r.p.Parent then
				if instant then
					r.p.CFrame = rot * r.cf
				else
					TweenService:Create(r.p, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = rot * r.cf }):Play()
				end
			end
		end
		if ind and indPart then
			ind.Text = if closedLocked then "사용중" else "비어있음"
			ind.BackgroundColor3 = if closedLocked then rgb(200, 30, 36) else rgb(30, 150, 70)
		end
	end
	return { model = model, handle = handle, set = set, open = startOpen }
end

-- 양변기 (비데 + 센서 세척밸브). x, 뒷벽 z0 (정렬), 정면 +Z
local function toilet(R: any, x: number, zb: number, female: boolean)
	local K = R.K
	local z = zb + 0.95 -- 변기 중심
	local f = function(dx: number, y: number, dz: number): CFrame
		return fc(R, x + dx, y, z + dz, 0)
	end
	-- 받침 · 트랩
	R.K:ell("ToiletFoot", V3(0.86, 0.9, 1.1), R.A * f(0, 0.45, -0.1), PORC)
	R.K:box("ToiletFootBase", V3(0.8, 0.12, 0.95), R.A * f(0, 0.06, -0.1), PORC)
	-- 볼 (도기) + 안쪽 + 물
	R.K:ell("ToiletBowl", V3(1.22, 0.62, 1.55), R.A * f(0, 1.0, 0.12), PORC)
	R.K:ell("ToiletBowlIn", V3(0.86, 0.06, 1.12), R.A * f(0, 1.3, 0.16), PORC_IN)
	R.K:ell("ToiletWater", V3(0.5, 0.05, 0.62), R.A * f(0, 1.31, 0.16), gl(rgb(170, 200, 214), 0.25))
	-- 시트 (비데 일체형): 링 + 뒤 본체 + 옆 조작부
	R.K:ell("ToiletSeat", V3(1.28, 0.08, 1.62), R.A * f(0, 1.36, 0.14), WHT)
	R.K:ell("ToiletSeatHole", V3(0.84, 0.09, 1.1), R.A * f(0, 1.365, 0.18), lk(206, 212, 216))
	R.K:box("BidetBody", V3(1.24, 0.34, 0.62), R.A * f(0, 1.5, -0.62), WHT)
	R.K:box("BidetTop", V3(1.18, 0.06, 0.56), R.A * f(0, 1.7, -0.62), lk(232, 232, 228))
	R.K:box("BidetPanel", V3(0.26, 0.14, 0.62), R.A * f(0.72, 1.56, -0.3), WHT)
	for i, c in { rgb(40, 120, 220), rgb(230, 90, 150), rgb(220, 40, 40), rgb(60, 180, 90) } do
		R.K:disc("BidetButton", 0.07, 0.02, R.A * f(0.72, 1.635, -0.52 + i * 0.1), { c = c, m = M.SmoothPlastic })
	end
	R.K:text("BidetLabel", 0.22, 0.08, R.A * fc(R, x + 0.72, 1.565, z - 0.5, 0) * CF(0, 0, 0.31) * ANG(0, 0, 0), "비데", { fg = rgb(60, 60, 60), d = 0.005 })
	-- 뚜껑 (올려진 상태, 뒤로 살짝)
	R.K:ell("ToiletLid", V3(1.2, 1.5, 0.08), R.A * f(0, 2.42, -0.86) * ANG(math.rad(-8), 0, 0), WHT)
	-- 세척밸브 (벽 매립 센서) + 관
	local wcf = fc(R, x, 3.15, zb, 0)
	pl(R, "FlushPlate", 0.72, 0.95, 0.05, wcf, SST)
	pl(R, "FlushSensor", 0.4, 0.22, 0.02, wcf * CF(0, 0.2, 0.05), lk(14, 14, 18, M.Glass, { r = 0.2 }))
	wdisc(R, "FlushSensorLED", 0.05, 0.015, wcf * CF(0.14, 0.2, 0.065), nl(rgb(255, 60, 50)))
	wdisc(R, "FlushButton", 0.26, 0.04, wcf * CF(0, -0.18, 0.05), CHROME)
	tx(R, "FlushLabel", 0.6, 0.1, wcf * CF(0, -0.4, 0.052), "자동 물내림", rgb(70, 70, 70), nil, F.GothamBold)
	sg(R, "FlushPipe", V3(x, 2.68, zb + 0.06), V3(x, 1.85, zb + 0.06), 0.16, CHROME)
	sg(R, "FlushPipe", V3(x, 1.85, zb + 0.06), V3(x, 1.72, zb + 0.32), 0.16, CHROME)
	-- 급수 앵글밸브
	sg(R, "AngleValve", V3(x - 0.5, 0.9, zb + 0.02), V3(x - 0.5, 0.9, zb + 0.2), 0.1, CHROME)
	bl(R, "AngleValveKnob", 0.14, f(-0.5, 0.9, -0.73), CHROME)
end

-- 점보롤 휴지걸이 (칸막이 면 dcf)
local function jumboRoll(R: any, dcf: CFrame)
	wdisc(R, "JumboRollCase", 1.05, 0.4, dcf, lk(236, 236, 232))
	wdisc(R, "JumboRollWindow", 0.7, 0.02, dcf * CF(0, 0.06, 0.4), lk(70, 74, 80, M.Glass, { t = 0.3 }))
	wdisc(R, "JumboRollPaper", 0.62, 0.01, dcf * CF(0, 0.06, 0.39), PAPER)
	pl(R, "JumboRollTear", 0.5, 0.06, 0.08, dcf * CF(0, -0.47, 0.32), lk(120, 124, 128))
	pl(R, "JumboRollTail", 0.34, 0.3, 0.01, dcf * CF(0, -0.62, 0.3), PAPER)
	tx(R, "JumboRollLabel", 0.42, 0.08, dcf * CF(0, 0.3, 0.405), "PAPER", rgb(120, 120, 120), nil, F.GothamBold)
end

-- 소변기 (벽걸이 + 센서 + 가림판 은 따로). wall dcf (벽 표면, +Z = 방 안), kid = 낮은 어린이용
local function urinal(R: any, dcf: CFrame, kid: boolean)
	local k = if kid then 0.82 else 1
	local y0 = if kid then -0.7 else 0 -- dcf 는 성인 기준 높이 2.4 에 둠
	local c = dcf * CF(0, y0, 0)
	R.K:ell("UrinalShell", V3(1.12 * k, 2.3 * k, 1.1), c * CF(0, 0, 0.32), PORC)
	R.K:box("UrinalBack", V3(1.0 * k, 2.1 * k, 0.12), c * CF(0, 0, 0.06), PORC)
	R.K:ell("UrinalBowl", V3(0.78 * k, 1.55 * k, 0.5), c * CF(0, -0.12, 0.66), PORC_IN)
	R.K:ell("UrinalLip", V3(0.86 * k, 0.24, 0.42), c * CF(0, -0.98 * k, 0.72), PORC)
	wdisc(R, "UrinalDrain", 0.22, 0.02, c * CF(0, -0.72 * k, 0.5) * ANG(-PI / 2.6, 0, 0), CHROME)
	-- 센서 세척 (위 크롬 관 + 감지기)
	local s = c * CF(0, 1.65 * k, 0)
	pl(R, "UrinalSensorBox", 0.5, 0.62, 0.22, s, CHROME)
	pl(R, "UrinalSensorEye", 0.3, 0.16, 0.02, s * CF(0, -0.1, 0.22), lk(14, 14, 18, M.Glass, { r = 0.2 }))
	wdisc(R, "UrinalSensorLED", 0.04, 0.012, s * CF(0.1, -0.1, 0.24), nl(rgb(255, 60, 50)))
	R.K:cyl("UrinalFeed", 0.48 * k, 0.1, s * CF(0, -0.55 * k, 0.12) * ANG(0, 0, PI / 2), CHROME)
end

-- 소변기 가림판 (벽 dcf 기준 u 위치에서 방 안쪽으로 dep)
local function urinalDivider(R: any, side: string, u: number, dep: number, look: any)
	local K = R.K
	local d = wf(R, side, u, 2.95, 0)
	K:box("UrinalDivider", V3(0.1, 3.3, dep), d * CF(0, 0, dep / 2 + 0.02), look)
	K:box("UrinalDividerEdge", V3(0.12, 3.3, 0.06), d * CF(0, 0, dep + 0.02), HPL_EDGE)
	for _, yy in { -1.2, 1.2 } do
		K:box("UrinalDividerBracket", V3(0.2, 0.3, 0.12), d * CF(0, yy, 0.06), SST)
	end
end

local function restroom(R: any)
	local K, V = R.K, R.V
	local female = string.find(V.name or "", "여자", 1, true) ~= nil
	local x0, x1, z0, z1, H = R.x0, R.x1, R.z0, R.z1, R.H
	-- 맵 배치 읽기 (정렬 AABB)
	local panels = {}
	for _, r in recs(V, "StallPanel") do
		local mn, mx = abox(R, r)
		table.insert(panels, { mn = mn, mx = mx, c = (mn + mx) / 2 })
	end
	table.sort(panels, function(a, b)
		return a.c.X < b.c.X
	end)
	local sinks = {}
	for _, r in recs(V, "SinkCounter") do
		local mn, mx = abox(R, r)
		table.insert(sinks, { mn = mn, mx = mx, c = (mn + mx) / 2 })
	end
	table.sort(sinks, function(a, b)
		return a.c.Z < b.c.Z
	end)
	local ps: any = nil
	for _, r in recs(V, "PrivacyScreen") do
		local mn, mx = abox(R, r)
		ps = { mn = mn, mx = mx }
	end
	local sinkRight = #sinks > 0 and sinks[1].c.X > 0
	local sinkSide = if sinkRight then "R" else "L"
	local otherSide = if sinkRight then "L" else "R"
	local zf = if #panels > 0 then panels[1].mx.Z else z0 + 5.4 -- 칸 앞면
	local wallBack = z0
	-- 문 (정렬)
	local door = V.door
	local dX = if door then (R.A:Inverse() * V3(door.x, 0, door.z)).X else 0
	local dL, dR = dX - 1.75, dX + 1.75
	local psZ0 = if ps then ps.mn.Z else z1 - 3.8
	local psZ1 = if ps then ps.mx.Z else z1 - 3.2

	-- 숨김: 칸막이 · 문 · 변기 · 세면대 · 거울 · 타일 띠
	for _, n in { "StallPanel", "StallDoor", "Toilet", "SinkCounter", "Basin", "Mirror", "Wainscot" } do
		hideAll(R, n)
	end

	-- keep: 칸 앞 통로 · 입구 · 칸 안 (변기 앞)
	keepBox(R, dL - 0.2, z1 - 3.0, dR + 0.2, z1 + 0.4, 7.6, "door")

	-- 바닥: 미끄럼 방지 포세린 600각 + 배수구 --------------------------------------------------
	local floorL = lk(118, 116, 112, M.Slate)
	floorTiles(R, x0, x1, z0, z1, floorL, lk(84, 82, 80), 1.8)
	-- 문턱 (스테인리스)
	K:free(function()
		bx(R, "Threshold", V3(dR - dL, 0.04, 0.8), CF(dX, 0.03, z1 + 0.35), SST)
	end)
	local function drain(x: number, z: number)
		K:free(function()
			bx(R, "FloorDrain", V3(0.8, 0.03, 0.8), CF(x, 0.03, z), SST)
			for i = -2, 2 do
				bx(R, "FloorDrainSlot", V3(0.6, 0.032, 0.05), CF(x, 0.034, z + i * 0.12), lk(40, 42, 44))
			end
		end)
	end
	drain((x0 + x1) / 2 - 0.4, (zf + psZ0) / 2 - 1.0)
	for _, pc in { 1, 2 } do
		if panels[pc] and panels[pc + 1] then
			drain((panels[pc].mx.X + panels[pc + 1].mn.X) / 2 + 1.0, zf - 1.0)
		end
	end

	-- 벽 타일 ----------------------------------------------------------------------------------------------
	local tileL = lk(222, 218, 210, M.CeramicTiles)
	local accentD = lk(66, 68, 72, M.Slate)
	local grout = lk(190, 186, 180)
	-- 뒷벽 (칸 뒤)
	tiles(R, "B", x0, x1, 0, H, tileL, { grout = grout })
	-- 앞벽 (문 양옆 + 문 위)
	tiles(R, "F", x0, dL, 0, H, tileL, { grout = grout })
	tiles(R, "F", dR, x1, 0, H, tileL, { grout = grout })
	tiles(R, "F", dL, dR, 7.85, H, tileL, { grout = grout })
	-- 세면대 쪽 벽: 칸 구역 · 세면대 앞 피처월 · 입구 쪽
	local cz0 = if #sinks > 0 then sinks[1].mn.Z - 0.65 else -2.4
	local cz1 = if #sinks > 0 then sinks[#sinks].mx.Z + 0.65 else 5.8
	tiles(R, sinkSide, z0, cz0, 0, H, tileL, { grout = grout })
	tiles(R, sinkSide, cz1, z1, 0, H, tileL, { grout = grout })
	-- 반대쪽 벽: 남 = 소변기 구역 다크 슬레이트 (세로 타일) / 여 = 웜 타일
	if female then
		tiles(R, otherSide, z0, z1, 0, H, tileL, { grout = grout })
	else
		tiles(R, otherSide, z0, zf + 0.6, 0, H, tileL, { grout = grout })
		tiles(R, otherSide, zf + 0.6, psZ0 - 0.3, 0, 7.2, accentD, { grout = lk(46, 48, 50), tw = 0.9, th = 1.8 })
		tiles(R, otherSide, zf + 0.6, psZ0 - 0.3, 7.2, H, tileL, { grout = grout })
		tiles(R, otherSide, psZ0 - 0.3, z1, 0, H, tileL, { grout = grout })
	end
	-- 걸레받이 (스테인리스 띠)
	K:free(function()
		for _, s in { { "B", x0, x1 }, { "F", x0, dL }, { "F", dR, x1 }, { sinkSide, z0, z1 }, { otherSide, z0, z1 } } do
			local a, b = math.min(s[2], s[3]), math.max(s[2], s[3])
			pl(R, "Baseboard", b - a, 0.3, 0.05, wf(R, s[1], (a + b) / 2, 0.15, 0.03), SST_D)
		end
	end)
	-- 칸막이 (가림벽) 타일 + 끝 몰딩
	if ps then
		K:free(function()
			local w = ps.mx.X - ps.mn.X
			local cx = (ps.mn.X + ps.mx.X) / 2
			for _, face in { { ps.mn.Z, PI }, { ps.mx.Z, 0 } } do
				local d = fc(R, cx, 3.7, face[1], face[2])
				pl(R, "ScreenTile", w, 7.4, 0.03, d, tileL)
				for i = 1, 8 do
					pl(R, "TileGrout", w, 0.03, 0.036, d * CF(0, -3.7 + i * 0.9, 0), grout)
				end
			end
			local endX = if math.abs(ps.mx.X - dX) > math.abs(ps.mn.X - dX) then ps.mx.X else ps.mn.X
			local sgn = if endX == ps.mx.X then 1 else -1
			bx(R, "ScreenEdge", V3(0.06, 7.42, ps.mx.Z - ps.mn.Z + 0.08), CF(endX + sgn * 0.03, 3.71, (ps.mn.Z + ps.mx.Z) / 2), SST)
			bx(R, "ScreenCap", V3(w + 0.06, 0.06, ps.mx.Z - ps.mn.Z + 0.08), CF(cx, 7.44, (ps.mn.Z + ps.mx.Z) / 2), SST)
		end)
	end

	-- 천장: 알루미늄 스트립 + 몰딩 + 설비 ------------------------------------------------------------
	K:free(function()
		bx(R, "CeilingStrip", V3(R.W - 0.04, 0.03, R.D - 0.04), CF(R.cx, H - 0.02, R.cz), lk(238, 238, 234, M.Metal, { r = 0.04 }))
		local z = z0 + 0.6
		while z < z1 - 0.2 do
			bx(R, "CeilingStripGap", V3(R.W - 0.06, 0.035, 0.05), CF(R.cx, H - 0.025, z), lk(176, 176, 172))
			z += 0.6
		end
		for _, s in { "L", "R", "B", "F" } do
			local len = if s == "L" or s == "R" then R.D else R.W
			local u = if s == "L" or s == "R" then R.cz else R.cx
			pl(R, "CeilingAngle", len, 0.16, 0.06, wf(R, s, u, H - 0.09, 0.0), lk(226, 226, 222, M.Metal))
		end
	end)
	-- 조명 (다운라이트) : 칸 2 · 통로 2 · 입구 1
	local cxs = (x0 + x1) / 2
	for i = 1, #panels - 1 do
		local sx = (panels[i].mx.X + panels[i + 1].mn.X) / 2
		downlight(R, sx, (z0 + zf) / 2, H, { light = true, range = 13, bright = 0.9, angle = 95 })
	end
	local midX = if sinkRight then x1 - 3.4 else x0 + 3.4
	local oppX = if sinkRight then x0 + 2.4 else x1 - 2.4
	downlight(R, midX, cz0 + 1.6, H, { light = true, range = 15, bright = 0.85 })
	downlight(R, midX, cz1 - 1.6, H, { light = false })
	downlight(R, oppX, zf + 2.6, H, { light = true, range = 15, bright = 0.8 })
	downlight(R, oppX, psZ0 - 2.2, H, { light = false })
	downlight(R, (dL + dR) / 2 + (if dX < cxs then 1.2 else -1.2), (psZ1 + z1) / 2, H, { light = true, range = 11, bright = 0.7 })
	-- 환풍기 (그릴 + 돌아가는 날개)
	local function fan(x: number, z: number)
		local blades = {}
		K:free(function()
			bx(R, "ExhaustFrame", V3(1.3, 0.05, 1.3), CF(x, H - 0.03, z), WHT)
			bx(R, "ExhaustHole", V3(1.1, 0.04, 1.1), CF(x, H - 0.035, z), lk(40, 40, 42))
			for i = 0, 3 do
				local a = i * PI / 2 + 0.3
				table.insert(blades, bx(R, "ExhaustBlade", V3(0.42, 0.02, 0.16), CF(x, H - 0.06, z) * ANG(0, a, 0) * CF(0.24, 0, 0) * ANG(0.35, 0, 0), lk(200, 200, 198)))
			end
			dk(R, "ExhaustHub", 0.16, 0.05, CF(x, H - 0.065, z), lk(200, 200, 198))
			for i = -4, 4 do
				bx(R, "ExhaustGrille", V3(1.1, 0.03, 0.04), CF(x, H - 0.085, z + i * 0.12), WHT)
			end
		end)
		Interact.spin(K, blades, K.cf * (R.A * V3(x, H - 0.06, z)), 1.6)
	end
	fan(oppX - (if sinkRight then -1.2 else 1.2), (z0 + zf) / 2 + 0.6)
	fan(midX + (if sinkRight then -1.6 else 1.6), psZ0 - 1.6)
	for _, p in { { cxs - 2.6, z0 + 2.4 }, { cxs + 2.6, z0 + 2.4 }, { cxs, zf + 3.4 }, { cxs, psZ0 - 3.4 } } do
		sprinkler(R, p[1], p[2], H)
	end
	detector(R, cxs + 0.8, (zf + psZ0) / 2, H, "heat")
	speaker(R, cxs - 1.0, (zf + psZ0) / 2 + 2.2, H)
	emergencyLight(R, wf(R, "F", if dX < cxs then dR + 1.2 else dL - 1.2, 9.4, 0.03))

	-- 칸 (칸막이 + 앞판 + 문 + 헤드레일) ------------------------------------------------------------
	local stallDoors = {}
	K:free(function()
		for _, p in panels do
			local px = (p.mn.X + p.mx.X) / 2
			local zc = (z0 + zf) / 2
			bx(R, "StallPanel", V3(0.14, 6.4, zf - z0 - 0.04), CF(px, 3.75, zc + 0.02), HPL)
			bx(R, "StallPanelEdge", V3(0.15, 6.4, 0.04), CF(px, 3.75, zf - 0.02), HPL_EDGE)
			-- 벽 U 채널 + 받침 다리
			bx(R, "StallWallChannel", V3(0.22, 6.2, 0.06), CF(px, 3.75, z0 + 0.06), SST)
			for _, zz in { z0 + 0.8, zf - 0.5 } do
				vc(R, "StallLeg", 0.5, 0.12, CF(px, 0.27, zz), SST)
				dk(R, "StallFoot", 0.26, 0.04, CF(px, 0.02, zz), SST)
			end
		end
		if #panels >= 2 then
			local a, b = panels[1].mn.X, panels[#panels].mx.X
			-- 헤드레일 (앞면 위)
			bx(R, "StallHeadrail", V3(b - a + 0.1, 0.14, 0.2), CF((a + b) / 2, 7.0, zf - 0.07), SST)
		end
	end)
	-- 앞판 (필라스터) + 문
	for i = 1, #panels - 1 do
		local a, b = panels[i].mx.X, panels[i + 1].mn.X
		local w = b - a
		local dw = math.min(2.5, w - 0.6)
		local hingeLeft = i == 1
		local da = if hingeLeft then a + 0.12 else b - 0.12 - dw
		local db = da + dw
		K:free(function()
			-- 필라스터 (문 양옆, 바닥 다리 + 헤드레일까지)
			for _, seg in { { a, da - 0.02 }, { db + 0.02, b } } do
				if seg[2] - seg[1] > 0.04 then
					bx(R, "StallPilaster", V3(seg[2] - seg[1], 6.4, 0.14), CF((seg[1] + seg[2]) / 2, 3.75, zf - 0.07), HPL)
					vc(R, "StallLeg", 0.5, 0.1, CF((seg[1] + seg[2]) / 2, 0.27, zf - 0.07), SST)
				end
			end
		end)
		local startOpen = not (i == 2)
		local sd = stallDoor(R, i, da, db, zf, hingeLeft, female, startOpen)
		if startOpen then
			sd.set(true, false, true)
		else
			sd.set(false, true, true)
		end
		table.insert(stallDoors, sd)
		-- 칸 안: 변기 · 휴지걸이 · 선반 · 비상벨 · 수거함 · 안내
		local sx = (a + b) / 2
		toilet(R, sx, wallBack, female)
		local sideX = if i == 1 then a else b -- 칸막이 면 (변기 옆)
		local sideYaw = if i == 1 then PI / 2 else -PI / 2
		local sideOff = if i == 1 then 0.08 else -0.08
		jumboRoll(R, fc(R, sideX + sideOff, 2.75, wallBack + 1.75, sideYaw))
		-- 휴대폰 선반
		local sh = fc(R, sideX + sideOff, 3.7, wallBack + 3.2, sideYaw)
		pl(R, "PhoneShelf", 0.9, 0.06, 0.32, sh, SST)
		pl(R, "PhoneShelfLip", 0.9, 0.12, 0.03, sh * CF(0, 0.05, 0.3), SST)
		-- 비상벨
		local eb = fc(R, sideX + sideOff, 3.05, wallBack + 3.2, sideYaw)
		pl(R, "EmergencyBell", 0.46, 0.46, 0.08, eb * CF(0, -0.52, 0), lk(220, 222, 220))
		wdisc(R, "EmergencyBellBtn", 0.26, 0.06, eb * CF(0, -0.52, 0.08), lk(210, 30, 36))
		tx(R, "EmergencyBellLabel", 0.7, 0.14, eb * CF(0, -0.88, 0.005), if female then "여성안심 비상벨" else "비상벨", rgb(200, 30, 36), nil, F.GothamBold)
		if female then
			-- 위생용품 수거함 (변기 옆 바닥)
			local bxx = sideX + (if i == 1 then 0.5 else -0.5)
			bx(R, "SanitaryBin", V3(0.55, 1.2, 0.9), CF(bxx, 0.6, wallBack + 0.65), WHT)
			bx(R, "SanitaryBinLid", V3(0.57, 0.08, 0.92), CF(bxx, 1.24, wallBack + 0.65), lk(200, 200, 196))
			tx(R, "SanitaryBinLabel", 0.5, 0.2, fc(R, bxx + (if i == 1 then 0.28 else -0.28), 0.85, wallBack + 0.65, if i == 1 then PI / 2 else -PI / 2), "위생용품\n수거함", rgb(60, 60, 60), nil, F.GothamBold)
			if i == 1 then
				-- 유아 보호의자 (접힌 상태)
				local bc = fc(R, b - 0.08, 3.6, wallBack + 2.8, -PI / 2)
				pl(R, "BabySeat", 1.3, 1.6, 0.28, bc, lk(236, 230, 214))
				pl(R, "BabySeatFace", 1.1, 1.3, 0.04, bc * CF(0, 0, 0.28), lk(250, 246, 236))
				tx(R, "BabySeatLabel", 0.9, 0.24, bc * CF(0, 0.35, 0.33), "유아 보호의자", rgb(90, 120, 170), nil, F.GothamBold)
				wdisc(R, "BabySeatIcon", 0.4, 0.02, bc * CF(0, -0.15, 0.32), lk(140, 180, 220))
			end
		end
	end
	-- 칸 문 프롬프트
	for i, sd in stallDoors do
		if sd.handle then
			local open = sd.open
			Interact.prompt(K, sd.handle, {
				action = if open then "문 닫고 잠그기" else "잠금 풀기",
				object = string.format("화장실 %d번 칸", i),
				sound = SND_DOOR,
				fn = function(_n, p)
					open = not open
					sd.set(open, not open)
					p.ActionText = if open then "문 닫고 잠그기" else "잠금 풀기"
				end,
			})
		end
	end
	-- 칸막이 끝 공간 (벽과 첫/끝 칸막이 사이): 청소도구함 · 점검구 앞판 + 문
	local function closet(xa: number, xb: number, label: string)
		if xb - xa < 0.6 then
			return
		end
		K:free(function()
			local w = xb - xa
			bx(R, "ClosetFront", V3(w, 6.4, 0.14), CF((xa + xb) / 2, 3.75, zf - 0.07), HPL)
			bx(R, "ClosetDoorLine", V3(0.03, 6.0, 0.15), CF(xa + 0.1, 3.75, zf - 0.07), HPL_EDGE)
			bx(R, "ClosetDoorLine", V3(0.03, 6.0, 0.15), CF(xb - 0.1, 3.75, zf - 0.07), HPL_EDGE)
			bx(R, "ClosetHandle", V3(0.05, 0.5, 0.06), CF(xb - 0.3, 3.4, zf + 0.04), CHROME)
			bx(R, "ClosetLock", V3(0.12, 0.12, 0.03), CF(xb - 0.3, 3.9, zf + 0.01), CHROME)
			local d = fc(R, (xa + xb) / 2, 5.3, zf + 0.002, 0)
			pl(R, "ClosetSign", math.min(1.2, w - 0.3), 0.5, 0.01, d, SST)
			tx(R, "ClosetSignText", math.min(1.1, w - 0.4), 0.42, d * CF(0, 0, 0.011), label, rgb(40, 40, 42), nil, F.GothamBold)
			for _, xx in { xa + 0.15, xb - 0.15 } do
				vc(R, "StallLeg", 0.5, 0.1, CF(xx, 0.27, zf - 0.07), SST)
			end
		end)
	end
	if #panels >= 2 then
		closet(x0, panels[1].mn.X, "청소\n도구함")
		closet(panels[#panels].mx.X, x1, "점검구\n관계자외")
		K:free(function()
			-- 헤드레일 끝까지
			bx(R, "StallHeadrail", V3(panels[1].mn.X - x0, 0.14, 0.2), CF((x0 + panels[1].mn.X) / 2, 7.0, zf - 0.07), SST)
			bx(R, "StallHeadrail", V3(x1 - panels[#panels].mx.X, 0.14, 0.2), CF((x1 + panels[#panels].mx.X) / 2, 7.0, zf - 0.07), SST)
			-- 칸 위 (헤드레일 ~ 7.2) 가림 판 없음: 실제처럼 위가 트임
		end)
	end

	-- 세면대 ----------------------------------------------------------------------------------------------
	R.vanity = { side = sinkSide, z0 = cz0, z1 = cz1 }
	if #sinks > 0 then
		local sgn = if sinkRight then -1 else 1 -- 벽에서 방 안쪽 방향 (x)
		local wallX = if sinkRight then x1 else x0
		local chase = 0.5 -- 배관 벽 깊이 (맵 세면대가 벽에서 0.5 떨어져 있음)
		local faceX = wallX + sgn * chase
		local topY = sinks[1].mx.Y
		local frontX = if sinkRight then sinks[1].mn.X else sinks[1].mx.X
		local depth = math.abs(frontX - faceX)
		local czc = (cz0 + cz1) / 2
		local len = cz1 - cz0
		local dark = lk(54, 54, 58, M.Marble)
		K:free(function()
			-- 피처월 (다크 마블, 바닥 ~ 천장)
			bx(R, "VanityWall", V3(chase, H - 0.05, len), CF(wallX + sgn * chase / 2, (H - 0.05) / 2, czc), dark)
			for k = 1, 3 do
				local zz = cz0 + len * k / 4
				bx(R, "VanityWallJoint", V3(chase + 0.01, H - 0.06, 0.03), CF(wallX + sgn * chase / 2, (H - 0.05) / 2, zz), lk(36, 36, 38))
			end
			bx(R, "VanityWallJoint", V3(chase + 0.01, 0.03, len), CF(wallX + sgn * chase / 2, 4.15, czc), lk(36, 36, 38))
			-- 상판 (화이트 쿼츠) + 앞 에이프런 + 아래 LED
			bx(R, "VanityTop", V3(depth + 0.05, 0.22, len - 0.3), CF(faceX + sgn * (depth + 0.05) / 2, topY - 0.11, czc), lk(240, 238, 232, M.Marble))
			bx(R, "VanityApron", V3(0.12, 0.75, len - 0.3), CF(faceX + sgn * (depth - 0.02), topY - 0.55, czc), lk(240, 238, 232, M.Marble))
			bx(R, "VanityUnder", V3(depth - 0.15, 0.08, len - 0.4), CF(faceX + sgn * (depth / 2), topY - 0.92, czc), lk(190, 188, 184))
			bx(R, "VanityLED", V3(0.06, 0.04, len - 0.5), CF(faceX + sgn * (depth - 0.12), topY - 0.95, czc), nl(rgb(255, 226, 190)))
			bx(R, "VanityBacksplash", V3(0.04, 0.5, len - 0.3), CF(faceX + sgn * 0.02, topY + 0.25, czc), lk(240, 238, 232, M.Marble))
		end)
		-- 거울 (백라이트) + 조명
		local mirrorH, mirrorW = 3.7, len - 1.1
		local md = wf(R, sinkSide, czc, topY + 0.7 + mirrorH / 2 + 0.25, chase)
		local halo = pl(R, "MirrorHaloLED", mirrorW + 0.16, mirrorH + 0.16, 0.03, md, nl(rgb(255, 236, 214)))
		pl(R, "MirrorBack", mirrorW, mirrorH, 0.08, md * CF(0, 0, 0.03), lk(30, 30, 32))
		pl(R, "Mirror", mirrorW - 0.04, mirrorH - 0.04, 0.02, md * CF(0, 0, 0.11), MIRROR)
		light(R, halo, "SurfaceLight", { Face = Enum.NormalId.Back, Range = 9, Brightness = 0.55, Angle = 120, Color = rgb(255, 236, 214) })
		-- 탑볼 + 수전 + 비누
		local faucets = {}
		for si, s in sinks do
			local bz = s.c.Z
			local bxx = faceX + sgn * (depth * 0.55)
			local bc = fc(R, bxx, topY, bz, 0)
			K:free(function()
				R.K:ell("VesselBowl", V3(1.15, 0.62, 1.45), R.A * bc * CF(0, 0.26, 0), PORC)
				R.K:ell("VesselInner", V3(0.98, 0.05, 1.26), R.A * bc * CF(0, 0.54, 0), PORC_IN)
				R.K:disc("VesselDrain", 0.2, 0.02, R.A * bc * CF(0, 0.56, 0), CHROME)
				R.K:disc("VesselFoot", 0.6, 0.06, R.A * bc * CF(0, 0.03, 0), PORC)
			end)
			-- 센서 수전 (거위목): 벽 쪽 상판에서 세움
			local fx = faceX + sgn * 0.32
			local fpos = V3(fx, topY, bz)
			local stream: BasePart? = nil
			local eye: BasePart? = nil
			K:free(function()
				dk(R, "FaucetBase", 0.26, 0.05, CF(fx, topY + 0.025, bz), CHROME)
				sg(R, "FaucetBody", V3(fx, topY, bz), V3(fx, topY + 1.15, bz), 0.15, CHROME)
				sg(R, "FaucetSpout", V3(fx, topY + 1.13, bz), V3(bxx - sgn * 0.08, topY + 1.13, bz), 0.12, CHROME)
				sg(R, "FaucetNose", V3(bxx - sgn * 0.08, topY + 1.13, bz), V3(bxx - sgn * 0.08, topY + 1.0, bz), 0.12, CHROME)
				eye = dk(R, "FaucetEye", 0.06, 0.02, CF(bxx - sgn * 0.08, topY + 1.05, bz) * ANG(0, 0, PI / 2), lk(14, 14, 18))
				stream = vc(R, "FaucetWater", 0.42, 0.06, CF(bxx - sgn * 0.08, topY + 0.75, bz), { c = rgb(200, 226, 240), m = M.Glass, t = 1, r = 0.2 })
				-- 거품 비누 (데크형 노즐)
				local sz = bz + (if si == 1 then -0.75 else 0.75)
				sg(R, "SoapNozzle", V3(fx, topY, sz), V3(fx, topY + 0.55, sz), 0.1, CHROME)
				sg(R, "SoapNozzleTip", V3(fx, topY + 0.55, sz), V3(fx + sgn * 0.32, topY + 0.55, sz), 0.08, CHROME)
				tx(R, "SoapLabel", 0.34, 0.1, fc(R, fx + sgn * 0.25, topY + 0.011, sz, if sinkRight then PI / 2 else -PI / 2) * ANG(-PI / 2, 0, 0), "SOAP", rgb(110, 110, 110), nil, F.GothamBold)
			end)
			table.insert(faucets, { stream = stream, eye = eye, pos = fpos })
			-- 손 씻기 (물 + 소리, 4초 뒤 꺼짐)
			if stream then
				local busy = false
				Interact.prompt(K, stream, {
					action = "손 씻기",
					object = "센서 수전",
					sound = false,
					fn = function()
						if busy then
							return
						end
						busy = true
						tween(stream, { Transparency = 0.35 }, 0.15)
						sound(stream, SND_WATER, 0.35, 3)
						task.delay(4, function()
							tween(stream, { Transparency = 1 }, 0.3)
							busy = false
						end)
					end,
				})
			end
		end
		-- 절수 스티커
		local sd = wf(R, sinkSide, czc, topY + 0.6, chase + 0.002)
		tx(R, "WaterSticker", 2.4, 0.22, sd, "물을 아껴 씁시다 · 센서에 손을 대 주세요", rgb(220, 220, 220), nil, F.GothamMedium)
	end

	-- 세면대 옆: 핸드드라이어 (칸 쪽) · 페이퍼타올 + 휴지통 (입구 쪽) --------------------------------
	local dz = (zf + cz0) / 2
	local dryerD = wf(R, sinkSide, dz, 3.9, 0.03)
	local dryerLED: BasePart? = nil
	do
		pl(R, "HandDryerBody", 1.3, 2.1, 0.75, dryerD, lk(236, 236, 234))
		pl(R, "HandDryerFace", 1.16, 1.2, 0.04, dryerD * CF(0, 0.38, 0.75), lk(40, 42, 46))
		pl(R, "HandDryerSlot", 1.0, 0.5, 0.12, dryerD * CF(0, -0.55, 0.7), lk(26, 26, 28))
		pl(R, "HandDryerTray", 1.2, 0.1, 0.5, dryerD * CF(0, -1.05, 0.5), lk(210, 210, 206))
		dryerLED = pl(R, "HandDryerLED", 0.7, 0.06, 0.02, dryerD * CF(0, 0.75, 0.79), nl(rgb(70, 160, 255)))
		tx(R, "HandDryerBrand", 0.9, 0.18, dryerD * CF(0, 0.2, 0.795), "JET TOWEL", rgb(220, 220, 220), nil, F.GothamBold)
		local nd = wf(R, sinkSide, dz, 6.0, 0.03)
		notice(R, "DryerNotice", 1.4, 0.7, nd, "핸드드라이어", "손을 넣으면 자동으로 작동합니다\n물기를 털고 사용하세요", { acc = rgb(30, 100, 180), holder = true })
	end
	if dryerLED then
		local busy = false
		Interact.prompt(K, dryerLED, {
			action = "손 말리기",
			object = "핸드드라이어",
			sound = false,
			fn = function()
				if busy or not dryerLED then
					return
				end
				busy = true
				dryerLED.Color = rgb(120, 255, 160)
				sound(dryerLED, "rbxasset://sounds/action_falling.mp3", 0.25, 3)
				task.delay(3.2, function()
					if dryerLED then
						dryerLED.Color = rgb(70, 160, 255)
					end
					busy = false
				end)
			end,
		})
	end
	-- 페이퍼타올 + 휴지통 (세면대와 가림벽 사이)
	local tz = (cz1 + psZ0) / 2
	if psZ0 - cz1 > 1.4 then
		local td = wf(R, sinkSide, tz, 5.0, 0.03)
		pl(R, "TowelBox", 1.2, 1.6, 0.48, td, lk(238, 238, 236))
		pl(R, "TowelWindow", 0.8, 0.5, 0.02, td * CF(0, 0.3, 0.48), lk(60, 64, 70, M.Glass, { t = 0.3 }))
		pl(R, "TowelPaper", 0.9, 0.24, 0.03, td * CF(0, -0.82, 0.32), PAPER)
		tx(R, "TowelLabel", 0.9, 0.14, td * CF(0, 0.66, 0.485), "PAPER TOWEL", rgb(130, 130, 130), nil, F.GothamBold)
		local bxx = if sinkRight then x1 - 0.5 else x0 + 0.5
		if spot(R, bxx, tz, if sinkRight then -PI / 2 else PI / 2, V3(1.16, 2.4, 0.86), 0.05) then
			binSquare(R, bxx, tz, if sinkRight then -PI / 2 else PI / 2, 2.4, "종이타올")
		end
	end

	-- 반대쪽 벽: 남 = 소변기 / 여 = 파우더 선반 + 기저귀 교환대 + 생리대함 -------------------------------
	local oWallX = if sinkRight then x0 else x1
	local oSgn = if sinkRight then 1 else -1
	if not female then
		local za, zb = zf + 1.0, psZ0 - 0.6
		local n = math.max(2, math.min(4, math.floor((zb - za) / 2.45)))
		local pitch = (zb - za) / n
		-- 소변기 앞 트렌치 배수 + 다크 타일 띠
		K:free(function()
			bx(R, "UrinalFloorBand", V3(1.6, 0.03, zb - za + 0.3), CF(oWallX + oSgn * 0.8, 0.026, (za + zb) / 2), lk(64, 64, 66, M.Slate))
			bx(R, "TrenchDrain", V3(0.3, 0.035, zb - za), CF(oWallX + oSgn * 1.45, 0.03, (za + zb) / 2), SST)
			local z = za + 0.1
			while z < zb - 0.1 do
				bx(R, "TrenchSlot", V3(0.18, 0.037, 0.05), CF(oWallX + oSgn * 1.45, 0.031, z), lk(40, 42, 44))
				z += 0.2
			end
		end)
		local ads = {
			{ "한 걸음 더 가까이!", "남자가 흘리지 말아야 할 것은\n눈물만이 아닙니다" },
			{ "STRIKE NIGHT", "금 · 토 22시~ 코즈믹 볼링\n1게임 6,000원" },
			{ "생일파티 패키지", "4인 2게임 + 음료\n59,000원 · 프런트 문의" },
			{ "볼링 레슨", "초보 환영 1:1 레슨\n30분 30,000원" },
		}
		for i = 1, n do
			local uz = za + pitch * (i - 0.5)
			local kid = i == n
			urinal(R, wf(R, otherSide, uz, 2.4, 0), kid)
			-- 위 선반 + 액자
			local shd = wf(R, otherSide, uz, if kid then 4.4 else 5.0, 0)
			pl(R, "UrinalShelf", 1.0, 0.06, 0.34, shd, SST)
			local ad = ads[((i - 1) % #ads) + 1]
			local fd = wf(R, otherSide, uz, 6.6, 0.02)
			pl(R, "AdFrame", 1.5, 1.95, 0.06, fd, SST)
			pl(R, "AdSheet", 1.36, 1.8, 0.01, fd * CF(0, 0, 0.06), if i == 1 then PAPER else lk(26, 20, 48))
			tx(R, "AdTitle", 1.24, 0.38, fd * CF(0, 0.55, 0.072), ad[1], if i == 1 then rgb(20, 90, 170) else rgb(255, 210, 60), nil, F.GothamBlack)
			tx(R, "AdBody", 1.24, 0.9, fd * CF(0, -0.25, 0.072), ad[2], if i == 1 then rgb(40, 40, 40) else rgb(240, 236, 255), nil, F.GothamMedium)
			if i > 1 then
				pl(R, "AdStripe", 1.36, 0.06, 0.012, fd * CF(0, 0.28, 0.07), nl(rgb(170, 70, 255)))
			end
			if kid then
				tx(R, "KidLabel", 0.9, 0.24, wf(R, otherSide, uz, 3.65, 0.01), "어린이용", rgb(240, 240, 240), rgb(40, 140, 210), F.GothamBold)
			end
		end
		for i = 1, n - 1 do
			urinalDivider(R, otherSide, za + pitch * i, 1.45, HPL)
		end
	else
		-- 파우더 선반 (벽걸이) + 원형 LED 거울 2 + 드라이어 홀더
		local pz0, pz1 = zf + 1.4, zf + 1.4 + 5.2
		local pzc = (pz0 + pz1) / 2
		local sh = fc(R, oWallX + oSgn * 0.7, 2.95, pzc, 0)
		K:free(function()
			bx(R, "PowderShelf", V3(1.4, 0.16, pz1 - pz0), sh, lk(240, 238, 232, M.Marble))
			bx(R, "PowderShelfLED", V3(0.05, 0.04, pz1 - pz0 - 0.2), sh * CF(oSgn * 0.64, -0.1, 0), nl(rgb(255, 226, 190)))
			for _, zz in { pz0 + 0.4, pz1 - 0.4 } do
				bx(R, "PowderBracket", V3(1.2, 0.5, 0.08), CF(oWallX + oSgn * 0.6, 2.62, zz), SST)
			end
		end)
		for k, zz in { pz0 + 1.3, pz1 - 1.3 } do
			local md = wf(R, otherSide, zz, 5.4, 0.02)
			local ring = wdisc(R, "RoundMirrorLED", 2.3, 0.04, md, nl(rgb(255, 238, 220)))
			wdisc(R, "RoundMirror", 2.16, 0.05, md * CF(0, 0, 0.03), MIRROR)
			if k == 1 then
				light(R, ring, "PointLight", { Range = 7, Brightness = 0.45, Color = rgb(255, 232, 210) })
			end
		end
		-- 헤어드라이어 홀더
		local hd = wf(R, otherSide, pzc, 4.1, 0.02)
		pl(R, "DryerHolder", 0.5, 0.7, 0.3, hd, WHT)
		sg(R, "HairDryer", ap(R, oWallX + oSgn * 0.35, 3.9, pzc), ap(R, oWallX + oSgn * 0.35, 4.5, pzc), 0.3, lk(250, 250, 250))
		sg(R, "HairDryerNozzle", ap(R, oWallX + oSgn * 0.35, 4.5, pzc), ap(R, oWallX + oSgn * 0.75, 4.55, pzc), 0.22, lk(230, 230, 230))
		-- 선반 위 소품: 티슈 · 면봉 통 · 손 소독제
		K:free(function()
			bx(R, "TissueBox", V3(0.5, 0.3, 0.9), CF(oWallX + oSgn * 0.7, 3.18, pz0 + 0.8), lk(250, 250, 248))
			bx(R, "TissueTop", V3(0.2, 0.06, 0.3), CF(oWallX + oSgn * 0.7, 3.36, pz0 + 0.8), PAPER)
			vc(R, "SanitizerBottle", 0.5, 0.26, CF(oWallX + oSgn * 0.7, 3.28, pz1 - 0.7), lk(220, 236, 246, M.Glass, { t = 0.3 }))
			vc(R, "SanitizerPump", 0.16, 0.1, CF(oWallX + oSgn * 0.7, 3.6, pz1 - 0.7), WHT)
		end)
		-- 기저귀 교환대 (접었다 폈다): 파우더 선반과 가림벽 사이
		local bz = (pz1 + psZ0) / 2
		if psZ0 - pz1 > 2.4 then
			local hingeY = 2.0
			local tableParts = {}
			local m = K:group("DiaperTable", function()
				local dcf = wf(R, otherSide, bz, hingeY + 1.0, 0.02)
				pl(R, "DiaperBody", 2.6, 2.0, 0.42, dcf, lk(236, 228, 210))
				pl(R, "DiaperFace", 2.4, 1.8, 0.03, dcf * CF(0, 0, 0.42), lk(246, 240, 226))
				wdisc(R, "DiaperIcon", 0.7, 0.02, dcf * CF(0, 0.2, 0.45), lk(120, 170, 220))
				tx(R, "DiaperLabel", 2.0, 0.3, dcf * CF(0, -0.55, 0.45), "기저귀 교환대", rgb(70, 110, 160), nil, F.GothamBold)
				pl(R, "DiaperHandle", 0.8, 0.12, 0.1, dcf * CF(0, 0.85, 0.45), lk(200, 196, 186))
			end)
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(tableParts, { p = d, cf = d.CFrame })
				end
			end
			local hingeW = K.cf * (R.A * V3(oWallX + oSgn * 0.02, hingeY, bz))
			local axis = (K.cf * R.A).ZVector
			local down = false
			local hp = m:FindFirstChild("DiaperHandle") :: BasePart?
			if hp then
				Interact.prompt(K, hp, {
					action = "펼치기",
					object = "기저귀 교환대",
					sound = SND_DOOR,
					fn = function(_n, p)
						down = not down
						local a = if down then oSgn * (PI / 2) else 0
						local rot = CFrame.new(hingeW) * CFrame.fromAxisAngle(axis, -a) * CFrame.new(-hingeW)
						for _, r in tableParts do
							if r.p.Parent then
								TweenService:Create(r.p, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = rot * r.cf }):Play()
							end
						end
						p.ActionText = if down then "접기" else "펼치기"
					end,
				})
			end
		end
		-- 무료 생리대함 (칸 앞 벽)
		local fd = wf(R, otherSide, zf + 0.75, 4.2, 0.02)
		pl(R, "PadBox", 1.0, 1.5, 0.45, fd, lk(250, 214, 226))
		pl(R, "PadBoxWindow", 0.7, 0.5, 0.02, fd * CF(0, 0.25, 0.45), lk(250, 250, 250, M.Glass, { t = 0.3 }))
		pl(R, "PadBoxSlot", 0.6, 0.1, 0.05, fd * CF(0, -0.45, 0.45), lk(180, 120, 140))
		tx(R, "PadBoxLabel", 0.9, 0.3, fd * CF(0, -0.15, 0.455), "생리대 무료\n1인 1개", rgb(170, 50, 90), nil, F.GothamBold)
	end

	-- 입구 가림벽 / 벽면 게시물 ----------------------------------------------------------------------
	if ps then
		local cx = (ps.mn.X + ps.mx.X) / 2
		-- 방 안쪽 면: 손 씻기 6단계 (세면대 쪽 끝으로)
		local hx = cx + (if sinkRight then 1.2 else -1.2)
		handwashPoster(R, fc(R, hx, 4.9, ps.mn.Z - 0.035, PI))
		-- 입구 쪽 면: 금연 + 청소 점검표 + 안심 안내
		local ex = cx + (if dX > cx then 1.0 else -1.0)
		noSmoking(R, fc(R, ex - 1.1, 5.2, ps.mx.Z + 0.035, 0), 1.0)
		cleaningSheet(R, fc(R, ex + 0.6, 4.6, ps.mx.Z + 0.035, 0), "박OO ✓")
		local sp = fc(R, ex - 0.2, 6.75, ps.mx.Z + 0.035, 0)
		pl(R, "SafeNotice", 2.4, 0.6, 0.012, sp, lk(255, 224, 70))
		tx(R, "SafeNoticeText", 2.3, 0.5, sp * CF(0, 0, 0.013), if female then "여성 안심 화장실 · 불법촬영 점검 완료\n비상벨을 누르면 경찰이 출동합니다" else "불법촬영 카메라 점검 완료\n깨끗한 화장실 함께 만들어요", rgb(30, 30, 30), nil, F.GothamBold)
	end
	-- 방향제 (자동 분사기, 높은 곳)
	local fz = (cz1 + psZ0) / 2 + (if sinkRight then 0 else 0)
	local ad = wf(R, otherSide, (zf + psZ0) / 2 + (if female then 2.4 else 0), 8.4, 0.02)
	pl(R, "AirFreshener", 0.6, 0.9, 0.36, ad, WHT)
	pl(R, "AirFreshenerWindow", 0.36, 0.2, 0.02, ad * CF(0, 0.15, 0.36), lk(160, 200, 236, M.Glass, { t = 0.3 }))
	wdisc(R, "AirFreshenerLED", 0.05, 0.02, ad * CF(0.18, -0.3, 0.36), nl(rgb(60, 220, 120)))
	local _ = fz
	-- 입구 쪽 앞벽: 청소 시간 안내 + 콘센트
	local hw = wf(R, "F", if dX < R.cx then dR + 1.6 else dL - 1.6, 5.4, 0.03)
	notice(R, "CleanTimeNotice", 1.3, 1.0, hw, "청소 중 잠시", "매 3시간 청소합니다\n불편을 드려 죄송합니다\n- 광안 락볼링클럽 -", { acc = rgb(20, 100, 170), holder = true })
	-- 미끄럼 주의 A형 표지 (청소 직후)
	local ax = if sinkRight then x1 - 2.3 else x0 + 2.3
	local az = zf + 0.9
	if spot(R, ax, az, if sinkRight then -PI / 2 else PI / 2, V3(1.2, 2.2, 1.0), 0.05) then
		local pc = fc(R, ax, 0, az, if sinkRight then -PI / 2 else PI / 2)
		for _, s in { -1, 1 } do
			R.K:box("WetSignPanel", V3(1.1, 2.1, 0.06), pc * CF(0, 1.05, s * 0.22) * ANG(s * 0.2, 0, 0), lk(250, 204, 20))
			R.K:text("WetSignText", 0.9, 1.0, pc * CF(0, 1.15, s * 0.255) * ANG(s * 0.2, if s > 0 then 0 else PI, 0), "주의\n미끄러움\nCAUTION", { fg = rgb(20, 20, 20), d = 0.01, font = F.GothamBlack })
		end
		R.K:box("WetSignTop", V3(1.1, 0.12, 0.2), pc * CF(0, 2.12, 0), lk(30, 30, 30))
	end
end

-- ==========================================================================================================
-- 아직 안 만든 방 (다음 단계에서 채움)
-- ==========================================================================================================
local function corridor(_R: any) end
local function office(_R: any) end
local function elevhall(_R: any) end

function T.style(V: any): any
	-- 공통 단계 전부 끔 (정렬 프레임에서 직접 지음)
	return {
		chair = false, stool = false, table = false, counter = false, base = false, lower = false, mat = false,
		clock = false, license = false, cctv = false, ceiling = false, lights = { kind = "none" },
		skip = { floor = true, ceiling = true, walls = true, chairs = true, stools = true, tables = true, counters = true, upgrades = true, fixtures = true },
	}
end

function T.build(K: any, V: any, S: any)
	local R = makeRoom(K, V)
	if V.type == "restroom" then
		restroom(R)
	elseif V.type == "corridor" then
		corridor(R)
	elseif V.type == "office" then
		office(R)
	elseif V.type == "elevhall" then
		elevhall(R)
	end
end

return T
